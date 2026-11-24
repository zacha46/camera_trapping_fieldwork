### Choose the v6 hectare design and compare it with the v4 and v5 grids
## 25 November 2026, Fletcherview Research Station, QLD
# Zachary Amir

### Stratified hectares instead of a grid:
## The property is split into NVIS vegetation subgroups; every subgroup covering at least
## 1 km2 is a stratum and gets two 1 ha plots (100 x 100 m). The TERN core plot and the
## Australian Acoustic Observatory (A2O) site are fixed hectares and count towards their
## subgroup. Every other hectare is crossed by a track, as pure in its subgroup as
## possible, and about 1 km from its replicate. Cameras within a hectare are placed in
## the field on features; this script gives only nominal edge-midpoint guides.

### Inputs and outputs:
## Reads the layers cached by 04_fetch_v6_layers.R and the v4 QField GeoPackage. Writes
## to outputs/: fletcherview_v6.gpkg, fletcherview_v6.pdf, a QField folder, a hectare
## points CSV, and the tracked summary tables quoted by the campaign README.
## Settings live in v6_site_config.R.


## Load libraries
library(tidyverse) # For basic data wrangling
library(sf)        # For everything spatial
library(terra)     # For the satellite imagery backdrop
library(here)      # For project-relative paths so this runs on any machine

## Load the site settings and the shared helpers this script uses
source(here("campaigns", "2026-11_fletcherview", "v6_site_config.R"))
source(here("R", "read_nvis_subgroups.R"))
source(here("R", "make_hectare_squares.R"))
source(here("R", "select_hectares.R"))
source(here("R", "anchor_hectare.R"))
source(here("R", "hectare_camera_guides.R"))
source(here("R", "plot_table_page.R"))
source(here("R", "qgis_layer_xml.R"))
source(here("R", "write_qgis_project.R"))

# where the cached inputs are
cache_gpkg <- file.path(campaign_dir, "data", "processed", "v6_layers.gpkg")
cache_imagery <- file.path(campaign_dir, "data", "processed", "esri_imagery.tif")
# where the outputs go
out_dir <- file.path(campaign_dir, "outputs")
# if the cache is missing,
if (!file.exists(cache_gpkg) || !file.exists(cache_imagery)) {
  # stop because this script works offline from the cache
  stop("No cached v6 layers in data/processed/.\n",
       "Run campaigns/2026-11_fletcherview/04_fetch_v6_layers.R first (needs internet).")
} # end cache check


#
##
### Read the cached layers ----

## each layer, renamed so its geometry column is always 'geometry'
read_layer <- function(lyr) {
  # read one layer from the cache
  x <- st_read(cache_gpkg, layer = lyr, quiet = TRUE)
  # give its geometry column the same name as every other layer
  st_geometry(x) <- "geometry"
  x
} # end reader helper
boundary <- read_layer("boundary")
osm_roads <- read_layer("tracks_osm")
qld_roads <- read_layer("tracks_qld")
v5_points <- read_layer("v5_points")
re_preclear <- read_layer("re_preclear")
re_remnant <- read_layer("re_remnant")

## the fixed points, in UTM
# the flux tower
tower <- st_transform(st_sfc(st_point(c(tower_lon, tower_lat)), crs = 4326), crs_utm)
# the A2O site
a2o <- st_transform(st_sfc(st_point(c(a2o_lon, a2o_lat)), crs = 4326), crs_utm)


#
##
### Find the vegetation strata ----

# read the subgroup code-to-name table
mvs_names <- read.csv(nvis_names_path)
# map the subgroups on the property
nvis <- read_nvis_subgroups(nvis_grid_path, boundary, mvs_names)
# view them, largest first
st_drop_geometry(nvis)

## the subgroups must tile the property, or areas and shares are wrong
# total subgroup area and the property's mapped area, km2
nvis_total_km2 <- sum(nvis$area_km2)
boundary_km2 <- as.numeric(st_area(boundary)) / 1e6
# if they differ by more than 1%,
if (abs(nvis_total_km2 / boundary_km2 - 1) > 0.01) {
  # stop because part of the property has no vegetation class (or is counted twice)
  stop(sprintf("NVIS subgroups cover %.2f km2 but the property is %.2f km2.",
               nvis_total_km2, boundary_km2),
       "\nCheck the NVIS grid covers the whole property.")
} # end coverage check

## a subgroup is a stratum if it is big enough
nvis$eligible <- nvis$area_km2 >= stratum_min_km2
# the strata, largest first
strata <- nvis$mvs_code[nvis$eligible]
# view the subgroups too small to sample
message("Too small to sample: ",
        paste(sprintf("%d %s (%.2f km2)", nvis$mvs_code[!nvis$eligible],
                      nvis$mvs_name[!nvis$eligible], nvis$area_km2[!nvis$eligible]),
              collapse = "; "))
# if there are more strata than the design allows,
if (length(strata) > max_strata) {
  # stop because ZDA decides how to cut the design back
  stop(sprintf("%d subgroups pass %.1f km2 but the design allows at most %d.",
               length(strata), stratum_min_km2, max_strata),
       "\nAsk ZDA which to keep, then raise max_strata or stratum_min_km2 in v6_site_config.R.")
} # end strata count check


#
##
### Gather the tracks ----

## lines from OpenStreetMap and the Queensland roads layer, each tagged with its source
track_lines <- rbind(osm_roads[, c("name", "highway", "source")],
                     qld_roads[, c("name", "highway", "source")])
## each v5 point sits on a track the collaborator traced from imagery, so it stands in
## for that track where no mapped line exists (ZDA, 2026-11-25)
track_proxies <- v5_points |>
  # name each proxy after its v5 point
  transmute(name = point_id, highway = "interpreted track (v5 point)", source = "v5_point_proxy")
# all track features together: lines and proxy points
tracks <- rbind(track_lines, track_proxies)

## how much mapped track lies on the property, by source?
track_km <- track_lines |>
  # cut the lines to the property
  st_intersection(st_geometry(boundary)) |>
  # measure each piece in km
  mutate(km = as.numeric(st_length(geometry)) / 1000) |>
  # add up by source
  st_drop_geometry() |>
  group_by(source) |>
  summarise(km = sum(km), .groups = "drop")
# view it
track_km


#
##
### Place the fixed hectares: TERN core plot and A2O site ----

## a small helper: the subgroup covering most of a square, and its share
dominant_subgroup <- function(square) {
  # cut the subgroups to the square
  pieces <- suppressWarnings(st_intersection(nvis[, "mvs_code"], st_geometry(square)))
  # area of each piece as a share of the square
  share <- as.numeric(st_area(pieces)) / hectare_size_m^2
  # the largest piece wins
  data.frame(mvs_code = pieces$mvs_code[which.max(share)], purity = max(share))
} # end dominant helper

## the core plot: north edge a set gap south of the tower, centred on its easting
tower_xy <- st_coordinates(tower)
core_geom <- make_hectare_squares(tower_xy[1, "X"],
                                  tower_xy[1, "Y"] - core_plot_gap_south_m - hectare_size_m / 2,
                                  crs_utm, hectare_size_m)
# its subgroup and purity
core <- st_sf(dominant_subgroup(core_geom), geometry = core_geom)
core$hectare_id <- "CORE"

## the A2O hectare: a square containing the A2O site, in the A2O site's own subgroup
a2o_code <- st_join(st_sf(geometry = a2o), nvis[, "mvs_code"])$mvs_code
# if the A2O site's subgroup is not a stratum,
if (!a2o_code %in% strata) {
  # warn, because it is placed anyway but will not stand in for a stratum
  warning("The A2O site falls in subgroup ", a2o_code, ", which is not a stratum; ",
          "its hectare is placed but does not replace a stratum replicate.")
} # end A2O stratum check
# slide a square around the site, preferring one crossed by a track
a2o_hect <- anchor_hectare(a2o, boundary, nvis, tracks, a2o_code, hectare_size_m)
a2o_hect$hectare_id <- "A2O"

## the fixed hectares together
fixed <- rbind(core[, c("hectare_id", "mvs_code", "purity")],
               a2o_hect[, c("hectare_id", "mvs_code", "purity")])
# view them, expecting both in the largest stratum
st_drop_geometry(fixed)


#
##
### Pick the remaining hectares, two per stratum ----

# start from the fixed hectares
hectares <- fixed
# for each stratum, largest first,
for (s in strata) {
  # how many hectares does it already have?
  n_have <- sum(hectares$mvs_code == s)
  # how many more does it need?
  n_need <- hectares_per_stratum - n_have
  # if none, go to the next stratum
  if (n_need <= 0) next
  # choose them: track-crossed, pure, about 1 km from their replicate
  picks <- select_hectares(boundary, nvis, tracks, s, n_need, origin = tower,
                           existing = hectares, size_m = hectare_size_m, lattice_m = lattice_m,
                           min_purity = min_purity, target_spacing_m = target_spacing_m)
  # name them by subgroup code and letter, e.g. MVS09-A
  picks$hectare_id <- sprintf("MVS%02d-%s", s, LETTERS[n_have + seq_len(n_need)])
  # add them to the design
  hectares <- rbind(hectares, picks[, c("hectare_id", "mvs_code", "purity")])
} # end per stratum


#
##
### Set the cameras per hectare and the deployment order ----

## the first camera count per hectare that fits the budget
n_hect <- nrow(hectares)
fits <- cameras_per_hectare_options[n_hect * cameras_per_hectare_options <= camera_budget]
# if even the smallest count does not fit,
if (length(fits) == 0) {
  # stop because the design needs more cameras than are available
  stop(sprintf("%d hectares need at least %d cameras but the budget is %d.",
               n_hect, n_hect * min(cameras_per_hectare_options), camera_budget),
       "\nRaise stratum_min_km2 or lower hectares_per_stratum in v6_site_config.R.")
} # end budget check
cameras_per_hectare <- fits[1]
hectares$cameras <- cameras_per_hectare

## deployment order: the core plot first, then by straight-line distance from the tower
# centre of each hectare
centres <- st_centroid(st_geometry(hectares))
# its distance from the tower
hectares$dist_tower_m <- as.numeric(st_distance(centres, tower))
# rank: core first, the rest nearest first
hectares$rank <- rank(ifelse(hectares$hectare_id == "CORE", -1, hectares$dist_tower_m),
                      ties.method = "first")
# sort by rank
hectares <- hectares[order(hectares$rank), ]
centres <- st_centroid(st_geometry(hectares))


#
##
### Describe each hectare ----

# the subgroup names
hectares <- left_join(hectares, mvs_names, by = "mvs_code")
# centre latitude and longitude, 5 decimal places
centre_ll <- st_coordinates(st_transform(centres, 4326))
hectares$centre_lat <- round(centre_ll[, "Y"], 5)
hectares$centre_lon <- round(centre_ll[, "X"], 5)

## distance to track and which source crosses each hectare
# distances from every hectare to every track feature
d_track <- matrix(as.numeric(st_distance(hectares, tracks)), nrow = nrow(hectares))
# nearest track, 0 m when one crosses the hectare
hectares$dist_track_m <- round(apply(d_track, 1, min))
# the sources of the features crossing (or, if none, nearest to) each hectare
hectares$track_source <- vapply(seq_len(nrow(hectares)), function(i) {
  # the crossing features, or failing that the nearest one
  hit <- which(d_track[i, ] == 0)
  if (length(hit) == 0) hit <- which.min(d_track[i, ])
  # their sources and names, e.g. "v5_point_proxy (FV16)"
  paste(unique(sprintf("%s (%s)", tracks$source[hit], tracks$name[hit])), collapse = "; ")
}, character(1))

## distance to the nearest hectare of the same subgroup
d_hect <- as.matrix(dist(st_coordinates(centres)))
hectares$dist_replicate_m <- vapply(seq_len(nrow(hectares)), function(i) {
  # the other hectares in this subgroup
  same <- which(hectares$mvs_code == hectares$mvs_code[i] & seq_len(nrow(hectares)) != i)
  if (length(same) == 0) NA_real_ else round(min(d_hect[i, same]))
}, numeric(1))

### One short field note per hectare:
## what is special about this hectare, then the placement guidance shared by all
hectares$field_note <- paste0(
  # the hectare-specific part
  case_when(
    hectares$hectare_id == "CORE" & core_plot_is_placeholder ~
      "Placeholder square: lay out on the TERN plot pegs. ",
    hectares$hectare_id == "A2O" ~ "Contains A2O site 61: confirm recorder positions. ",
    grepl("v5_point_proxy", hectares$track_source) & hectares$dist_track_m == 0 ~
      "Track inferred from a v5 point: confirm it is drivable. ",
    TRUE ~ ""),
  # a warning where the hectare is mixed
  ifelse(hectares$purity < min_purity, "Mixed vegetation: check the subgroup. ", ""),
  # the shared guidance
  "1 camera on-track, rest off-track; dense tussock (hare-wallaby); rock, logs, ",
  "termite mounds with a low camera (reptiles).")

# view the design
st_drop_geometry(hectares) |>
  select(rank, hectare_id, mvs_code, purity, cameras, dist_tower_m, dist_track_m, dist_replicate_m)


#
##
### Mark the camera guide points ----

# edge midpoints, the one nearest a track flagged on-track
guides <- hectare_camera_guides(hectares, tracks, "hectare_id", cameras_per_hectare)
# their latitude and longitude for the field
guide_ll <- st_coordinates(st_transform(guides, 4326))
guides$lat <- round(guide_ll[, "Y"], 5)
guides$lon <- round(guide_ll[, "X"], 5)


#
##
### Compare v4, v5 and v6 by subgroup ----

## the v4 grid as deployed with 30 cameras: footprint and main, plus the top backups
v4_all <- st_read(v4_gpkg_path, layer = "planned_points", quiet = TRUE) |> st_transform(crs_utm)
st_geometry(v4_all) <- "geometry"
# how many backups the 30 cameras reach, from the v4 summary
v4_summary <- read.csv(v4_summary_path)
n_v4_backup_cams <- v4_summary$value[v4_summary$quantity == "n_backup_cameras"]
# flag the sites that get a camera
v4_all$in_30 <- v4_all$status %in% c("footprint", "main") |
  (v4_all$status == "backup" & v4_all$backup_rank <= n_v4_backup_cams)
v4_sites <- v4_all[v4_all$in_30, ]

## a small helper: which subgroup each point falls in (NA when off the property)
point_subgroup <- function(pts) st_join(st_sf(geometry = st_geometry(pts)), nvis[, "mvs_code"])$mvs_code
v4_sites$mvs_code <- point_subgroup(v4_sites)
v5_points$mvs_code <- point_subgroup(v5_points)

## count sites (and v6 cameras) per subgroup, with a row for sites off the property
# every subgroup on the property, plus one key for "off the property"
keys <- c(nvis$mvs_code, NA)
# count a vector of subgroup codes against those keys
count_by <- function(codes, w = 1) {
  vapply(keys, function(k) sum(w * (if (is.na(k)) is.na(codes) else codes %in% k)), numeric(1))
} # end count helper
comparison <- data.frame(
  # the subgroup
  mvs_code = keys,
  subgroup = c(nvis$mvs_name, "Off the cadastral parcel"),
  # its area and share of the property
  area_km2 = round(c(nvis$area_km2, NA), 2),
  area_pct = round(100 * c(nvis$area_share, NA), 1),
  stratum = c(ifelse(nvis$eligible, "yes", "no"), ""),
  # v4 grid at 30 cameras
  v4_cameras = count_by(v4_sites$mvs_code),
  # v5 relocated points
  v5_cameras = count_by(v5_points$mvs_code),
  # v6 hectares, and the cameras in them
  v6_hectares = count_by(hectares$mvs_code),
  v6_cameras = count_by(hectares$mvs_code, hectares$cameras)
) # end comparison table
# shares of sampled sites (v6 sites are hectares)
comparison$v4_site_pct <- round(100 * comparison$v4_cameras / sum(comparison$v4_cameras), 1)
comparison$v5_site_pct <- round(100 * comparison$v5_cameras / sum(comparison$v5_cameras), 1)
comparison$v6_site_pct <- round(100 * comparison$v6_hectares / sum(comparison$v6_hectares), 1)
# drop the off-parcel row if nothing falls there
comparison <- comparison[!(is.na(comparison$mvs_code) & comparison$v4_cameras == 0 &
                             comparison$v5_cameras == 0 & comparison$v6_hectares == 0), ]
# view it
comparison

## area covered by each design: minimum convex polygon (MCP), km2
mcp_km2 <- function(g) round(as.numeric(st_area(st_convex_hull(st_union(g)))) / 1e6, 2)
mcp <- data.frame(design = c("v4 grid (30 cameras)", "v5 relocated points", "v6 hectares"),
                  sites = c(nrow(v4_sites), nrow(v5_points), nrow(hectares)),
                  cameras = c(nrow(v4_sites), nrow(v5_points), sum(hectares$cameras)),
                  mcp_km2 = c(mcp_km2(v4_sites), mcp_km2(v5_points), mcp_km2(hectares)))
mcp


#
##
### Write the tracked summary tables ----

## subgroup areas on the property
write.csv(st_drop_geometry(nvis) |>
            mutate(area_km2 = round(area_km2, 3), area_pct = round(100 * area_share, 1)) |>
            select(mvs_code, mvs_name, area_km2, area_pct, eligible),
          file.path(out_dir, sprintf("nvis_areas_%s.csv", design_version)), row.names = FALSE)

## the comparison of designs, with the MCPs below the subgroup rows in their own file
write.csv(comparison, file.path(out_dir, sprintf("design_comparison_%s.csv", design_version)),
          row.names = FALSE)
write.csv(mcp, file.path(out_dir, sprintf("design_mcp_%s.csv", design_version)), row.names = FALSE)

## distances between every pair of hectares
pairs <- which(upper.tri(d_hect), arr.ind = TRUE)
hect_dist <- data.frame(from = hectares$hectare_id[pairs[, 1]],
                        to = hectares$hectare_id[pairs[, 2]],
                        same_subgroup = hectares$mvs_code[pairs[, 1]] == hectares$mvs_code[pairs[, 2]],
                        dist_m = round(d_hect[pairs])) |>
  arrange(desc(same_subgroup), from, to)
write.csv(hect_dist, file.path(out_dir, sprintf("hectare_distances_%s.csv", design_version)),
          row.names = FALSE)

## the hectares without coordinates: subgroup, purity, distances, cameras
hect_table <- st_drop_geometry(hectares) |>
  transmute(rank, hectare_id, mvs_code, subgroup = mvs_name, purity_pct = round(100 * purity),
            cameras, dist_tower_m = round(dist_tower_m), dist_track_m, track_source,
            dist_replicate_m)
write.csv(hect_table, file.path(out_dir, sprintf("hectares_%s.csv", design_version)),
          row.names = FALSE)

## every other quotable number
summary_tab <- data.frame(quantity = c(
  "parcel_mapped_ha", "parcel_registered_ha", "parcel_parts", "nvis_subgroups_on_parcel",
  "n_strata", "n_hectares", "cameras_per_hectare", "cameras_used", "cameras_spare",
  "core_plot_placeholder", "a2o_subgroup", "a2o_hectare_crossed_by_track",
  "min_purity_pct", "lowest_hectare_purity_pct", "track_km_on_parcel_osm",
  "track_km_on_parcel_qld", "v5_points_off_parcel", "v4_sites_off_parcel",
  "re_version", "tower_to_core_centre_m"),
  value = c(
    round(boundary$mapped_area_ha, 1), round(boundary$lot_area_ha, 1), boundary$n_parts,
    nrow(nvis), length(strata), n_hect, cameras_per_hectare, sum(hectares$cameras),
    camera_budget - sum(hectares$cameras), core_plot_is_placeholder, a2o_code,
    a2o_hect$crossed_by_track, round(100 * min_purity), round(100 * min(hectares$purity)),
    round(sum(track_km$km[track_km$source == "OSM"]), 2),
    round(sum(track_km$km[track_km$source == "QLD"]), 2),
    sum(is.na(v5_points$mvs_code)), sum(is.na(v4_sites$mvs_code)),
    paste(unique(re_preclear$version), collapse = "/"),
    round(hectares$dist_tower_m[hectares$hectare_id == "CORE"])))
write.csv(summary_tab, file.path(out_dir, sprintf("design_summary_%s.csv", design_version)),
          row.names = FALSE)

## the field table with coordinates (kept off GitHub by the *points* rule)
write.csv(st_drop_geometry(hectares) |>
            select(rank, hectare_id, mvs_name, centre_lat, centre_lon, cameras, dist_track_m,
                   field_note),
          file.path(out_dir, sprintf("%s_hectare_points_%s.csv", site_name, design_version)),
          row.names = FALSE)


#
##
### Write the GeoPackage ----

## the regional ecosystems, pre-clearing and remnant stacked, with their shared columns
re_cols <- c("re", "re_label", "landzone", "vm_class", "bd_status", "version", "re_layer")
re_polygons <- rbind(re_preclear[, intersect(re_cols, names(re_preclear))],
                     re_remnant[, intersect(re_cols, names(re_remnant))])

## an empty layer for QField to record where each camera actually went
deployments <- st_sf(
  deployment_id = "x", hectare_id = "x", guide_id = "x", notes = "x",
  recorded_at = as.POSIXct("2026-01-01 00:00:00", tz = "UTC"),
  geometry = st_sfc(st_point(c(tower_lon, tower_lat)), crs = 4326)
)[0, ] # end deployments layer

## every layer, in WGS84 as QField and Google Earth expect
gpkg_layers <- list(
  boundary = boundary,
  nvis_subgroups = nvis,
  re_polygons = re_polygons,
  tracks = tracks,
  v4_grid = v4_all,
  v5_points = v5_points,
  v6_hectares = hectares |> mutate(map_label = sprintf("%s (%d)", hectare_id, rank)),
  v6_camera_guides = guides,
  flux_tower = st_sf(name = "Flux tower", geometry = tower),
  a2o_site = st_sf(name = "A2O site 61", geometry = a2o),
  deployments = deployments
) # end layer list
# the GeoPackage lives in the QField folder, with a copy at the top of outputs/
qfield_dir <- file.path(out_dir, paste0("qfield_", design_version))
dir.create(qfield_dir, showWarnings = FALSE)
gpkg_name <- sprintf("%s_%s.gpkg", site_name, design_version)
gpkg <- file.path(qfield_dir, gpkg_name)
# start fresh so stale layers never linger
unlink(gpkg)
# write each layer
for (lyr in names(gpkg_layers)) {
  st_write(st_transform(gpkg_layers[[lyr]], 4326), gpkg, layer = lyr, quiet = TRUE)
} # end per layer
# copy it to outputs/ as the deliverable
file.copy(gpkg, file.path(out_dir, gpkg_name), overwrite = TRUE)


#
##
### Draw the PDF maps and tables ----

## shared drawing settings
# one colour per subgroup, strata strong and the rest pale
sub_cols <- setNames(hcl.colors(nrow(nvis), "Set 2"), nvis$mvs_code)
sub_cols[!nvis$eligible] <- adjustcolor(sub_cols[!nvis$eligible], alpha.f = 0.45)
# design colours
col_v4 <- "#E41A1C"
col_v5 <- "#377EB8"
col_v6 <- "#000000"
col_track <- "#FF7F00"
# write labels with a white halo so they read over imagery
halo_text <- function(x, y, labels, cex = 0.7, col = "black", halo = "white", ...) {
  # draw the label slightly offset in eight directions in the halo colour
  for (a in seq(0, 2 * pi, length.out = 9)[-9]) {
    text(x + cos(a) * strwidth("x", cex = cex) * 0.12, y + sin(a) * strheight("x", cex = cex) * 0.12,
         labels, cex = cex, col = halo, ...)
  } # end per offset
  # then the label itself on top
  text(x, y, labels, cex = cex, col = col, ...)
} # end halo helper
# the map extent: the property plus a margin
map_box <- st_bbox(st_buffer(boundary, 300))
# hectare centre coordinates and labels
cxy <- st_coordinates(centres)
hect_labels <- sprintf("%s (%d)", hectares$hectare_id, hectares$rank)
# the imagery
img <- rast(cache_imagery)
# the PDF, A4 landscape
pdf_path <- file.path(out_dir, sprintf("%s_%s.pdf", site_name, design_version))
pdf(pdf_path, width = 11.69, height = 8.27)

### Page 1: overview of all three designs over the vegetation strata
## map on the left, legend on the right
layout(matrix(1:2, nrow = 1), widths = c(2.8, 1.4))
par(mar = c(1, 1, 3, 1))
# the subgroups, filled
plot(st_geometry(nvis), col = sub_cols[as.character(nvis$mvs_code)], border = NA,
     xlim = map_box[c("xmin", "xmax")], ylim = map_box[c("ymin", "ymax")],
     main = "Fletcherview: v4 grid, v5 relocated points and v6 hectares over NVIS subgroups")
# the property boundary
plot(st_geometry(boundary), border = "grey20", lwd = 1.5, add = TRUE)
# mapped tracks
plot(st_geometry(track_lines), col = col_track, lwd = 1.5, add = TRUE)
# v4 sites with a camera
plot(st_geometry(v4_sites), pch = 4, col = col_v4, cex = 0.9, lwd = 1.5, add = TRUE)
# v5 points
plot(st_geometry(v5_points), pch = 2, col = col_v5, cex = 0.9, lwd = 1.5, add = TRUE)
# v6 hectares, outlined, with a marker so they show at this scale
plot(st_geometry(hectares), border = col_v6, lwd = 1.5, add = TRUE)
points(cxy, pch = 22, cex = 1.6, lwd = 1.5, col = col_v6)
# their labels
halo_text(cxy[, 1], cxy[, 2], hect_labels, pos = 4, offset = 0.8, cex = 0.75, font = 2)
# the tower and A2O site
plot(tower, pch = 17, col = "navy", cex = 1.3, add = TRUE)
plot(a2o, pch = 8, col = "purple", cex = 1.2, add = TRUE)
## the legend
par(mar = c(1, 0, 3, 1))
plot.new()
# one entry per subgroup, wrapped onto two lines so long names fit the panel
sub_labels <- vapply(sprintf("%d %s (%.2f km2)%s", nvis$mvs_code, nvis$mvs_name, nvis$area_km2,
                             ifelse(nvis$eligible, "", ", not sampled")),
                     function(s) paste(strwrap(s, 42), collapse = "\n"), character(1))
legend("topleft", bty = "n", cex = 0.7, title = "NVIS subgroup", title.adj = 0,
       fill = sub_cols, border = NA, legend = sub_labels, y.intersp = 1.6)
legend("bottomleft", bty = "n", cex = 0.8,
       legend = c("v4 grid site (30 cameras)", "v5 relocated point", "v6 hectare (rank)",
                  "Mapped track (OSM / QLD)", "Flux tower", "A2O site 61", "Cadastral parcel"),
       pch = c(4, 2, 22, NA, 17, 8, NA), lty = c(NA, NA, NA, 1, NA, NA, 1),
       col = c(col_v4, col_v5, col_v6, col_track, "navy", "purple", "grey20"),
       lwd = c(1.5, 1.5, 1.5, 1.5, NA, NA, 1.5))
layout(1)

### Page 2: the v6 hectares over satellite imagery
par(mar = c(2, 1, 3, 1))
# the imagery cropped to the map box
plotRGB(img, ext = ext(map_box[c("xmin", "xmax", "ymin", "ymax")]), mar = c(2, 1, 3, 1),
        main = "v6 hectares over Esri World Imagery (labels: ID (deployment rank))")
# the property boundary
plot(st_geometry(boundary), border = "white", lwd = 1.2, lty = 2, add = TRUE)
# mapped tracks
plot(st_geometry(track_lines), col = col_track, lwd = 1.5, add = TRUE)
# the v5 points standing in for tracks
plot(st_geometry(v5_points), pch = 2, col = "cyan", cex = 0.7, add = TRUE)
# the hectares and their labels
plot(st_geometry(hectares), border = "yellow", lwd = 2, add = TRUE)
halo_text(cxy[, 1], cxy[, 2], hect_labels, pos = 4, offset = 0.8, cex = 0.8, font = 2,
          col = "black", halo = "yellow")
# the tower
plot(tower, pch = 17, col = "white", cex = 1.2, add = TRUE)
mtext("Imagery: Esri, Maxar, Earthstar Geographics, and the GIS User Community. Yellow: v6 hectares; orange: OSM/QLD tracks; cyan triangles: v5 points (interpreted tracks).",
      side = 1, line = 0.5, cex = 0.65)

### Page 3: a close-up of each hectare, for checking tracks by eye
n_panel <- nrow(hectares)
par(mfrow = c(2, ceiling(n_panel / 2)))
# for each hectare,
for (i in seq_len(n_panel)) {
  # a 600 m window around its centre
  win <- ext(cxy[i, 1] - 300, cxy[i, 1] + 300, cxy[i, 2] - 300, cxy[i, 2] + 300)
  plotRGB(img, ext = win, mar = c(0.5, 0.5, 2.5, 0.5),
          main = sprintf("%s (rank %d): %d%% MVS %d", hectares$hectare_id[i], hectares$rank[i],
                         round(100 * hectares$purity[i]), hectares$mvs_code[i]))
  # tracks and v5 points nearby
  plot(st_geometry(track_lines), col = col_track, lwd = 2, add = TRUE)
  plot(st_geometry(v5_points), pch = 2, col = "cyan", cex = 1.2, lwd = 2, add = TRUE)
  # the hectare
  plot(st_geometry(hectares[i, ]), border = "yellow", lwd = 2, add = TRUE)
  # its guide points, the on-track one filled
  g <- guides[guides$hectare_id == hectares$hectare_id[i], ]
  plot(st_geometry(g), pch = ifelse(g$role == "on-track", 21, 1), bg = "yellow", col = "black",
       cex = 1.3, add = TRUE)
  # a 100 m scale bar in the lower left
  segments(win[1] + 40, win[3] + 40, win[1] + 140, win[3] + 40, col = "white", lwd = 3)
  text(win[1] + 90, win[3] + 60, "100 m", col = "white", cex = 0.7)
} # end per hectare
par(mfrow = c(1, 1))

### Page 4: the hectare field table
plot_table_page(
  st_drop_geometry(hectares) |>
    transmute(Rank = rank, Hectare = hectare_id,
              Subgroup = sprintf("%d %s", mvs_code, mvs_name),
              `Purity %` = round(100 * purity),
              `Centre lat` = sprintf("%.5f", centre_lat), `Centre long` = sprintf("%.5f", centre_lon),
              `To track (m)` = dist_track_m, Cameras = cameras, `Field note` = field_note),
  title = sprintf("v6 hectares: %d hectares x %d cameras = %d of %d cameras (deploy in rank order)",
                  n_hect, cameras_per_hectare, sum(hectares$cameras), camera_budget),
  footnote = paste(
    "Cameras within a hectare are not independent: place them in the field on features.",
    "Guide points (edge midpoints) are nominal starting points only. 'To track' is the gap",
    "between the hectare and the nearest track feature; 0 means a track crosses it.",
    "Rank: core plot first, then by straight-line distance from the flux tower.",
    "No drift fences or thermal cues. NVIS is mapped at ~100 m and the tracks are",
    "unverified: confirm the subgroup and access on the ground."),
  max_chars = 34)

### Page 5: the comparison of designs
plot_table_page(
  comparison |>
    transmute(Subgroup = ifelse(is.na(mvs_code), subgroup, sprintf("%d %s", mvs_code, subgroup)),
              `Area km2` = area_km2, `Area %` = area_pct, Stratum = stratum,
              `v4 cameras` = v4_cameras, `v4 sites %` = v4_site_pct,
              `v5 cameras` = v5_cameras, `v5 sites %` = v5_site_pct,
              `v6 hectares` = v6_hectares, `v6 cameras` = v6_cameras, `v6 sites %` = v6_site_pct),
  title = "Share of sampled sites in each NVIS subgroup: v4 grid, v5 points, v6 hectares",
  footnote = paste0(
    "MCP (minimum convex polygon) area: ",
    paste(sprintf("%s, %d cameras: %.2f km2", mcp$design, mcp$cameras, mcp$mcp_km2), collapse = "; "),
    ". v4 counts the 30 sites given cameras (footprint, main and the top backups). ",
    "v6 site share counts hectares; each hectare holds ", cameras_per_hectare, " cameras."),
  max_chars = 40)

### Page 6: distances between hectares
plot_table_page(
  hect_dist |> transmute(From = from, To = to,
                         `Same subgroup` = ifelse(same_subgroup, "yes", ""), `Distance (m)` = dist_m),
  title = "Distances between hectare centres (same-subgroup pairs first)",
  footnote = sprintf("Target spacing between hectares of one subgroup: about %d m.", target_spacing_m))

dev.off()
message("Wrote ", pdf_path)


#
##
### Build the QField project ----

## copy the QTopo basemap next to the GeoPackage
basemap_src <- file.path(campaign_dir, "data", "processed", "qtopo_basemap.tif")
# if it is missing,
if (!file.exists(basemap_src)) {
  # stop because the field map would open with no basemap offline
  stop("No QTopo basemap at ", basemap_src, "\nRun 02_water_and_basemap.R first.")
} # end basemap check
file.copy(basemap_src, file.path(qfield_dir, "qtopo_basemap.tif"), overwrite = TRUE)
# and the satellite imagery, for checking tracks offline
file.copy(cache_imagery, file.path(qfield_dir, "esri_imagery.tif"), overwrite = TRUE)

## describe how QField draws each layer, top layer first
crs_ll <- st_crs(4326)
# source string for a layer inside the GeoPackage
src <- function(lyr) paste0("./", gpkg_name, "|layername=", lyr)
qgis_layers <- list(
  # where cameras actually went: editable, with drop-downs and an automatic timestamp
  qgis_layer_xml("deployments", "Deployments (record here)", src("deployments"), crs_ll,
                 list(kind = "single", geom = "marker", shape = "star", size = 5,
                      fill = "#33A02C", outline = "#000000"),
                 label_field = "deployment_id", read_only = FALSE,
                 field_defaults = c(recorded_at = "now()"),
                 value_maps = list(hectare_id = hectares$hectare_id, guide_id = guides$guide_id)),
  # the flux tower and the A2O site
  qgis_layer_xml("flux_tower", "Flux tower", src("flux_tower"), crs_ll,
                 list(kind = "single", geom = "marker", shape = "triangle", size = 5,
                      fill = "#1F78B4", outline = "#FFFFFF")),
  qgis_layer_xml("a2o_site", "A2O site 61", src("a2o_site"), crs_ll,
                 list(kind = "single", geom = "marker", shape = "star", size = 5,
                      fill = "#6A3D9A", outline = "#FFFFFF")),
  # guide points, labelled, filled on the on-track guide
  qgis_layer_xml("v6_camera_guides", "v6 camera guides (nominal)", src("v6_camera_guides"), crs_ll,
                 list(kind = "categorized", attr = "role",
                      categories = data.frame(value = c("on-track", "off-track"),
                                              label = c("on-track guide", "off-track guide"),
                                              fill = c("#FFFF33", "#FFFFFF"), outline = "#000000",
                                              shape = "circle", size = 3, outline_width = 0.4)),
                 label_field = "guide_id"),
  # the hectares, outlined and labelled with ID and rank
  qgis_layer_xml("v6_hectares", "v6 hectares (ID (rank))", src("v6_hectares"), crs_ll,
                 list(kind = "single", geom = "fill", fill = "#FFFF33", alpha = 60,
                      outline = "#000000", outline_width = 0.8),
                 geometry = "Polygon", label_field = "map_label"),
  # mapped tracks only (the v5 proxy points are drawn with the v5 layer)
  qgis_layer_xml("tracks", "Tracks (OSM / QLD)",
                 paste0(src("tracks"), "|geometrytype=LineString"), crs_ll,
                 list(kind = "single", geom = "line", outline = col_track, outline_width = 0.8),
                 geometry = "Line"),
  # the earlier designs, for reference
  qgis_layer_xml("v5_points", "v5 relocated points", src("v5_points"), crs_ll,
                 list(kind = "single", geom = "marker", shape = "triangle", size = 3,
                      fill = col_v5, outline = "#FFFFFF"),
                 label_field = "point_id"),
  qgis_layer_xml("v4_grid", "v4 grid sites", src("v4_grid"), crs_ll,
                 list(kind = "single", geom = "marker", shape = "cross2", size = 3,
                      fill = col_v4, outline = col_v4, outline_width = 0.6)),
  # the property boundary
  qgis_layer_xml("boundary", "Cadastral parcel", src("boundary"), crs_ll,
                 list(kind = "single", geom = "fill", fill = NULL, outline = "#000000",
                      outline_style = "dash", outline_width = 0.7),
                 geometry = "Polygon"),
  # the subgroups, lightly shaded
  qgis_layer_xml("nvis_subgroups", "NVIS subgroups", src("nvis_subgroups"), crs_ll,
                 list(kind = "categorized", attr = "mvs_code", geom = "fill",
                      categories = data.frame(value = nvis$mvs_code,
                                              label = sprintf("%d %s", nvis$mvs_code, nvis$mvs_name),
                                              fill = substr(sub_cols, 1, 7), alpha = 90,
                                              outline = substr(sub_cols, 1, 7), outline_width = 0.2)),
                 geometry = "Polygon"),
  # satellite imagery and the QTopo basemap at the bottom
  qgis_layer_xml("esri_imagery", "Esri World Imagery", "./esri_imagery.tif", st_crs(crs_utm),
                 list(kind = "raster")),
  qgis_layer_xml("qtopo_basemap", "QTopo 1:25k basemap", "./qtopo_basemap.tif", st_crs(crs_utm),
                 list(kind = "raster"))
) # end layer list

## open on the property, with a little margin
bb <- st_bbox(boundary)
view <- c(bb[["xmin"]] - 300, bb[["ymin"]] - 300, bb[["xmax"]] + 300, bb[["ymax"]] + 300)
qgs_path <- write_qgis_project(file.path(qfield_dir, sprintf("%s_%s.qgs", site_name, design_version)),
                               title = paste("Fletcherview hectare design", design_version),
                               crs = st_crs(crs_utm), layers = qgis_layers, extent = view)
message("Wrote QField project ", qgs_path)
