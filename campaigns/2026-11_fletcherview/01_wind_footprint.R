### 01_wind_footprint.R -- which way the Fletcherview flux tower "looks"
##
## The eddy covariance tower measures fluxes from the land upwind of it, so the
## cameras that matter most for linking animals to the flux record sit in the
## directions the wind usually blows from. This script reads three years of OzFlux
## L3 half-hourly wind data, keeps the trustworthy records, and describes the wind
## for (a) the whole record and (b) the deployment season, November to February,
## in daylight, when the tower's daytime CO2 uptake is measured.
##
## Inputs: the three OzFlux netCDF files in data/raw/ (see data/raw/README.md).
## Outputs (outputs/): two wind rose PNGs, a sector table, and a summary table
## holding every number quoted in the campaign README.


## Load libraries
library(tidyverse) # For basic data wrangling and plotting
library(here)      # For project-relative paths so this runs on any machine

## Load the shared helpers this script uses
source(here("R", "read_ozflux_wind.R"))
source(here("R", "wind_rose_table.R"))
source(here("R", "circular_mean_direction.R"))
source(here("R", "plot_wind_rose.R"))


#
##
### Set the knobs for this analysis ----

## design version stamped on every output file
design_version <- "v1"
# where this campaign lives
campaign_dir <- here("campaigns", "2026-11_fletcherview")

## keep only half-hours where the wind is moving enough to have a direction
## (below ~0.5 m/s the sonic anemometer's direction is mostly noise)
min_wind_speed <- 0.5 # m/s
## call a half-hour daytime when incoming shortwave radiation is above this
min_daytime_fsd <- 10 # W/m2
## the deployment season: November through February
season_months <- c(11, 12, 1, 2)

### Which bearings does the camera design treat as the tower footprint?
## the upwind arc from NNE round to ESE, set from the season's wind rose
footprint_bearing_min <- 10  # degrees
footprint_bearing_max <- 125 # degrees

## compare against the numbers from the original v1 chat session
check_against_v1 <- TRUE


#
##
### Read and filter the OzFlux wind record ----

## find every Fletcherview L3 file in the raw folder
nc_paths <- list.files(file.path(campaign_dir, "data", "raw"),
                       pattern = "^FletcherviewTropicalRangeland_.*_L3\\.nc$",
                       full.names = TRUE)
# refuse to run without data rather than writing empty outputs
if (length(nc_paths) == 0) {
  stop("No OzFlux L3 files found in ", file.path(campaign_dir, "data", "raw"),
       "\nSee data/raw/README.md for the files this script expects.")
} # end no files check

## read and stack all years (duplicate timestamps are dropped inside)
wind_raw <- read_ozflux_wind(nc_paths)

## keep the half-hours with a trustworthy wind direction
wind <- wind_raw |>
  # QC flag 0 means the value passed every OzFlux check, untouched
  filter(Wd_QCFlag == 0) |>
  # direction must be a real compass bearing
  filter(Wd >= 0, Wd <= 360) |>
  # and the wind strong enough for the direction to mean something
  filter(Ws > min_wind_speed) |>
  # tag each half-hour with its month and calendar year
  mutate(month = as.integer(format(datetime, "%m")),
         year = as.integer(format(datetime, "%Y"))) |>
  # tag daytime by incoming sunlight (missing radiation counts as not daytime)
  mutate(daytime = !is.na(Fsd) & Fsd > min_daytime_fsd) |>
  # and tag the deployment season
  mutate(in_season = month %in% season_months)

## the season subset: November to February, daylight only
wind_season_day <- wind |>
  filter(in_season, daytime)

# report how much data survived the filters
message(sprintf("%d of %d half-hours kept (%s to %s)",
                nrow(wind), nrow(wind_raw),
                format(min(wind$datetime), "%Y-%m-%d"),
                format(max(wind$datetime), "%Y-%m-%d")))


#
##
### Summarise direction for the whole record and the season ----

## sector tables, 16 sectors of 22.5 degrees each
rose_all <- wind_rose_table(wind$Wd)
rose_season_day <- wind_rose_table(wind_season_day$Wd)

## circular mean direction and concentration (R)
mean_all <- circular_mean_direction(wind$Wd)
mean_season_day <- circular_mean_direction(wind_season_day$Wd)

## each calendar year's season on its own, to see if one year drives the result
## (2025 stops in July, so its "season" is January and February only)
mean_season_by_year <- wind_season_day |>
  # one group per calendar year
  group_by(year) |>
  # circular mean and R within each year, plus which months are present
  reframe(circular_mean_direction(Wd),
          months_present = paste(sort(unique(month)), collapse = ",")) |>
  # back to a plain data frame
  as.data.frame()

## how much of the season's daytime wind comes from the five sectors NNE to ESE
upwind_sectors <- c("NNE", "NE", "ENE", "E", "ESE")
pct_nne_to_ese <- sum(rose_season_day$pct[rose_season_day$sector %in% upwind_sectors])
## and how little comes from the opposite side, SW to W
downwind_sectors <- c("SW", "WSW", "W")
pct_sw_to_w <- sum(rose_season_day$pct[rose_season_day$sector %in% downwind_sectors])
## and the share inside the exact bearing arc the design uses for the footprint
pct_footprint_arc <- 100 * mean(wind_season_day$Wd >= footprint_bearing_min &
                                  wind_season_day$Wd <= footprint_bearing_max)


#
##
### Check the reproduction against the v1 chat session ----

if (check_against_v1) {
  ## the v1 values and how close a reproduction has to be
  checks <- data.frame(
    quantity = c("n valid half-hours", "all data mean (deg)", "all data R",
                 "Nov-Feb day mean (deg)", "Nov-Feb day R",
                 "Nov-Feb day % NNE..ESE", "2025 Nov-Feb day mean (deg)"),
    expected = c(43139, 86, 0.51, 64, 0.58, 69, 85),
    got = c(nrow(wind), mean_all$mean_deg, mean_all$R,
            mean_season_day$mean_deg, mean_season_day$R, pct_nne_to_ese,
            mean_season_by_year$mean_deg[mean_season_by_year$year == 2025]),
    # v1 quoted means to the degree, R to 2 dp, percentages to the whole number
    tolerance = c(0, 1, 0.01, 1, 0.01, 1, 1)
  ) # end checks table
  # a check passes when the difference is within its tolerance
  checks$pass <- abs(checks$got - checks$expected) <= checks$tolerance
  print(checks, digits = 4)
  # the SW-W claim is a threshold, not a value
  message(sprintf("SW+WSW+W = %.1f%% (v1: < 5%%)", pct_sw_to_w))

  ## hard stop if the reproduction drifts, so outputs are never written from a mismatch
  if (!all(checks$pass) || pct_sw_to_w >= 5) {
    stop("01_wind_footprint.R does not reproduce the v1 wind numbers (see table above).\n",
         "Check the filters, or set check_against_v1 <- FALSE if the inputs changed on purpose.")
  } # end reproduction check
} # end v1 check condition


#
##
### Write the wind roses and tables ----

# make sure the output folder exists
dir.create(file.path(campaign_dir, "outputs"), showWarnings = FALSE)

## wind rose (a): every valid half-hour
p_all <- plot_wind_rose(
  rose_all,
  title = "Fletcherview flux tower: wind direction, all data",
  subtitle = sprintf("%s valid half-hours, %s to %s; arrow = circular mean (%.0f°, R = %.2f)",
                     format(nrow(wind), big.mark = ","),
                     format(min(wind$datetime), "%d %b %Y"),
                     format(max(wind$datetime), "%d %b %Y"),
                     mean_all$mean_deg, mean_all$R),
  mean_dir = mean_all
) # end plot a
ggsave(file.path(campaign_dir, "outputs", paste0("wind_rose_all_", design_version, ".png")),
       p_all, width = 6, height = 6.5, dpi = 200, bg = "white")

## wind rose (b): deployment season, daylight only
p_season <- plot_wind_rose(
  rose_season_day,
  title = "Fletcherview flux tower: wind direction, Nov-Feb daytime",
  subtitle = sprintf("%s half-hours with Fsd > %d W/m²; arrow = circular mean (%.0f°, R = %.2f)",
                     format(nrow(wind_season_day), big.mark = ","), min_daytime_fsd,
                     mean_season_day$mean_deg, mean_season_day$R),
  mean_dir = mean_season_day
) # end plot b
ggsave(file.path(campaign_dir, "outputs", paste0("wind_rose_novfeb_day_", design_version, ".png")),
       p_season, width = 6, height = 6.5, dpi = 200, bg = "white")

## both sector tables in one long CSV
sector_table <- bind_rows(
  # every valid half-hour
  mutate(rose_all, subset = "all"),
  # season daytime only
  mutate(rose_season_day, subset = "novfeb_day")
) |>
  # subset first so the CSV reads naturally
  relocate(subset)
write_csv(sector_table, file.path(campaign_dir, "outputs",
                                  paste0("wind_sectors_", design_version, ".csv")))

## every number the README quotes, one row each
summary_table <- data.frame(
  quantity = c("n_valid_halfhours", "first_date", "last_date",
               "all_mean_deg", "all_R",
               "novfeb_day_n", "novfeb_day_mean_deg", "novfeb_day_R",
               "novfeb_day_pct_NNE_to_ESE", "novfeb_day_pct_SW_to_W",
               "novfeb_day_pct_footprint_arc",
               paste0("novfeb_day_", mean_season_by_year$year, "_mean_deg"),
               paste0("novfeb_day_", mean_season_by_year$year, "_R"),
               paste0("novfeb_day_", mean_season_by_year$year, "_months")),
  value = c(nrow(wind),
            format(min(wind$datetime), "%Y-%m-%d"),
            format(max(wind$datetime), "%Y-%m-%d"),
            round(mean_all$mean_deg, 1), round(mean_all$R, 3),
            nrow(wind_season_day),
            round(mean_season_day$mean_deg, 1), round(mean_season_day$R, 3),
            round(pct_nne_to_ese, 1), round(pct_sw_to_w, 1),
            round(pct_footprint_arc, 1),
            round(mean_season_by_year$mean_deg, 1),
            round(mean_season_by_year$R, 3),
            mean_season_by_year$months_present)
) # end summary table
write_csv(summary_table, file.path(campaign_dir, "outputs",
                                   paste0("wind_summary_", design_version, ".csv")))

message("Wind roses and tables written to ", file.path(campaign_dir, "outputs"))
