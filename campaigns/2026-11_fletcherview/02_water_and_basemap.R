### 02_water_and_basemap.R -- mapped water and a clean field basemap for Fletcherview
##
## Two inputs the design and the field map need, built once and cached in
## data/processed/:
##   (1) Queensland Government hydrography around the station: the mapped river and
##       creek channels, which set the wet-season water rule in 03_design_grid.R,
##       plus dams and watercourse lines for context;
##   (2) a QTopo 1:25k basemap mosaicked from the two sheets covering the station,
##       used as the background of the preview figure and the QField map.
##
## Inputs: QTopo_25k_8158-31.pdf and -32.pdf in data/raw/; an internet connection
## for the hydrography service.
## Outputs (data/processed/): qld_hydrography.gpkg and qtopo_basemap.tif.


## Load libraries
library(tidyverse) # For basic data wrangling
library(sf)        # For everything spatial
library(here)      # For project-relative paths so this runs on any machine

## Load the shared helpers this script uses
source(here("R", "fetch_qld_hydrography.R"))
source(here("R", "build_qtopo_basemap.R"))


#
##
### Set the knobs ----

# where this campaign lives
campaign_dir <- here("campaigns", "2026-11_fletcherview")
# all distances and areas are worked in WGS 84 / UTM zone 55S
crs_utm <- 32755

## the area to fetch and map: the station plus about 1 km all round
area_bbox_lonlat <- c(146.14, -19.92, 146.24, -19.84) # xmin, ymin, xmax, ymax

### Which Queensland hydrography layers to fetch?
## numbers are the service's layer IDs
hydro_layers <- c(watercourse_area = 34, # mapped river and creek channels (polygons)
                  reservoir = 28,        # stock dams mapped as polygons
                  lake = 27,             # lakes
                  farm_dam = 20,         # small dams mapped as points
                  watercourse_line = 33) # every mapped drainage line

## the QTopo sheets covering the station (8158-33 and -34 lie wholly to the west)
qtopo_sheets <- c("QTopo_25k_8158-31.pdf", "QTopo_25k_8158-32.pdf")
# basemap pixel size, metres
basemap_resolution_m <- 3


#
##
### Fetch the hydrography ----

## every feature of the chosen layers that touches the area, in UTM
hydro <- fetch_qld_hydrography(area_bbox_lonlat, hydro_layers, crs = crs_utm)
# report what came back, per layer
print(table(hydro$layer))

## write it to the processed folder, replacing any earlier copy
dir.create(file.path(campaign_dir, "data", "processed"), showWarnings = FALSE)
hydro_path <- file.path(campaign_dir, "data", "processed", "qld_hydrography.gpkg")
unlink(hydro_path)
st_write(hydro, hydro_path, layer = "hydrography", quiet = TRUE)


#
##
### Build the QTopo basemap ----

## the same area as the hydrography, as a UTM extent
area_utm <- st_bbox(c(xmin = area_bbox_lonlat[1], ymin = area_bbox_lonlat[2],
                      xmax = area_bbox_lonlat[3], ymax = area_bbox_lonlat[4]),
                    crs = st_crs(4326)) |>
  # as a polygon so it can be projected
  st_as_sfc() |>
  # into UTM
  st_transform(crs_utm) |>
  # and back to a box, rounded out to whole basemap pixels
  st_bbox()
extent_utm <- c(floor(area_utm[["xmin"]] / basemap_resolution_m) * basemap_resolution_m,
                floor(area_utm[["ymin"]] / basemap_resolution_m) * basemap_resolution_m,
                ceiling(area_utm[["xmax"]] / basemap_resolution_m) * basemap_resolution_m,
                ceiling(area_utm[["ymax"]] / basemap_resolution_m) * basemap_resolution_m)

## render, mosaic and clip the two sheets
basemap_path <- build_qtopo_basemap(
  pdf_paths = file.path(campaign_dir, "data", "raw", qtopo_sheets),
  out_path = file.path(campaign_dir, "data", "processed", "qtopo_basemap.tif"),
  extent = extent_utm,
  crs = paste0("EPSG:", crs_utm),
  resolution = basemap_resolution_m
) # end basemap build

message("Hydrography and basemap written to ", file.path(campaign_dir, "data", "processed"))
