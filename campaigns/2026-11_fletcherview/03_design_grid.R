### 03_design_grid.R -- camera grid and QField map for the Fletcherview flux tower campaign
##
## Lays an 800 m square grid over Fletcherview with one node on the flux tower,
## keeps the nodes far enough inside the property for a camera to go on a nearby
## tree, and sorts them for the field team:
##   footprint -- upwind of the tower (from 01_wind_footprint.R); always deployed
##   main      -- the rest of the grid that is always deployed
##   backup    -- ranked 1, 2, 3, ...; filled in order with the cameras left over
## Backups are the far downwind block thinned to a checkerboard, two interior
## downwind nodes, and every site near a mapped river or creek channel (wet season).
## Each site is drawn with a 100 m placement circle for choosing the camera tree.
##
## There is no cadastral boundary, so the property outline is traced by hand from a
## satellite screenshot and scaled to the station's known 2,400 ha. Treat it as
## approximate; see the campaign README.
##
## Inputs: data/processed/qld_hydrography.gpkg and qtopo_basemap.tif from
## 02_water_and_basemap.R.
## Outputs (outputs/): a QField project folder (GeoPackage, basemap, .qgs), KML,
## CSV of points, preview figure, and a summary table holding every number quoted
## in the campaign README.


## Load libraries
library(tidyverse) # For basic data wrangling and plotting
library(sf)        # For everything spatial (terra:: is used once, for the basemap)
library(here)      # For project-relative paths so this runs on any machine

## Load the shared helpers this script uses
source(here("R", "pixel_to_map.R"))
source(here("R", "make_grid_design.R"))
source(here("R", "make_footprint_zone.R"))
source(here("R", "classify_points.R"))
source(here("R", "relocate_away_from_water.R"))
source(here("R", "rank_backup_sites.R"))
source(here("R", "write_kml_points.R"))
source(here("R", "qgis_layer_xml.R"))
source(here("R", "write_qgis_project.R"))


#
##
### Set the knobs for this design ----

## design version stamped on every output file
design_version <- "v4"
# where this campaign lives
campaign_dir <- here("campaigns", "2026-11_fletcherview")
# all distances and areas are worked in WGS 84 / UTM zone 55S
crs_utm <- 32755

### Where is the flux tower?
## v1 used this position; OzFlux metadata gives -19.887285, 146.189138 (see README)
tower_lat <- -19.887232
tower_lon <- 146.188908
## the tower's pixel in the screenshot, which anchors the georeferencing
tower_px <- c(940, 728)

## the station's area, used to set the screenshot's scale
property_area_ha <- 2400

## grid layout
grid_spacing_m <- 800 # metres between neighbouring nodes
## cameras go on the best tree within this distance of a site; the map draws a circle
## this size around each site, and the grid keeps this far inside the boundary
placement_radius_m <- 100
boundary_inset_m <- placement_radius_m
point_prefix <- "FV" # point IDs FV01, FV02, ...

## cameras available (luggage limit); whatever the planned sites leave goes to backups
camera_cap <- 30

## footprint: within 2 km of the tower, in the upwind arc from 01_wind_footprint.R,
## widened all round because the wind sometimes blows from elsewhere and the
## leeward side near the tower is monitored too (ZDA, 2026-11-19)
footprint_max_dist_m <- 2000
footprint_bearing <- c(10, 125)
footprint_buffer_m <- 200

### Which nodes are backups?
## (1) the far downwind (western) block, every other node as a checkerboard
thin_min_dist_m <- 1600
thin_bearing <- c(170, 330)
## (2) two interior downwind nodes whose loss leaves the MCP unchanged (FV03, FV14)
backup_offsets <- data.frame(grid_i = c(-3, -3), grid_j = c(3, 1),
                             reason = "interior downwind, MCP unchanged")
### (3) wet season: any site this close to a mapped channel (ZDA, 2026-11-19)
## "mapped channel" = the Queensland Government watercourse-area polygons
water_layers <- c("watercourse_area")
major_river_name <- "Burdekin River"
water_buffer_major_m <- 250 # from the Burdekin River channel
water_buffer_minor_m <- 150 # from every other mapped creek channel

### Which camera sites move back from the river, and how far may they go?
## FV04 sits on the Burdekin bank; it moves to the driest spot within this radius,
## and the water rule is then judged where the camera actually goes
relocate_offsets <- data.frame(grid_i = 2, grid_j = 3)
relocate_max_m <- 300
### Which backup goes last whatever its coverage gain?
## FV01: on the Burdekin bank, and every drier spot within 400 m lies across the
## river, outside the true property (see README)
last_offsets <- data.frame(grid_i = -4, grid_j = 4,
                           note = "on the Burdekin bank; no drier spot on the property nearby")

## the analysis minimum for sampled area (camDB), km2
mcp_target_km2 <- 15

## colours for each status, used by the KML, the preview and QField
status_colours <- c(footprint = "#E41A1C", main = "#FFD92F", backup = "#FF7F00")
## colours for the other map layers
water_colour <- "#1F78B4"
tower_colour <- "#1F78B4"
boundary_colour <- "#000000"


#
##
### Trace and georeference the approximate property boundary ----

### the boundary traced on the screenshot, in pixels
## x counts right from the left edge, y counts DOWN from the top edge
boundary_px <- data.frame(
  px = c(478, 530, 580, 620, 660, 700, 750, 800, 850, 900, 960, 1020, 1080, 1120, 1160,
         1185, 1220, 1260, 1300, 1330, 1360, 1378, 1340, 1310, 1300, 1315, 1325, 1310,
         1280, 1200, 1100, 1000, 920, 890, 870, 820, 760, 720, 690, 665, 630, 560, 495,
         490, 495, 500, 505),
  py = c(292, 298, 315, 345, 385, 415, 440, 470, 488, 490, 480, 462, 440, 415, 405,
         412, 450, 500, 550, 600, 650, 690, 705, 730, 770, 810, 830, 860, 878, 882,
         880, 890, 905, 890, 850, 845, 825, 800, 780, 768, 775, 785, 785, 770, 600,
         450, 300)
) # end boundary pixels

## the scale is whatever makes the traced polygon cover the station's area
# close the ring by repeating the first vertex
ring_px <- as.matrix(rbind(boundary_px, boundary_px[1, ]))
# area of the traced polygon in square pixels
area_px <- abs(as.numeric(st_area(st_polygon(list(ring_px)))))
# metres per pixel: sqrt(target area in m2 / area in px2)
m_per_px <- sqrt(property_area_ha * 1e4 / area_px)

## the tower in UTM, which anchors the pixel-to-map conversion
tower_utm <- st_sfc(st_point(c(tower_lon, tower_lat)), crs = 4326) |>
  # project from lon/lat to metres
  st_transform(crs_utm) |>
  # and pull out the easting and northing
  st_coordinates() |>
  as.vector()

## convert every traced vertex to UTM (the y-down flip happens inside)
boundary_xy <- pixel_to_map(boundary_px$px, boundary_px$py,
                            anchor_px = tower_px, anchor_map = tower_utm, scale = m_per_px)

## build the boundary polygon, with its caveat attached
boundary <- st_sf(
  name = "Fletcherview Research Station (approximate)",
  note = sprintf("APPROXIMATE - traced from screenshot, scaled to %s ha", format(property_area_ha, big.mark = ",")),
  m_per_px = m_per_px,
  geometry = st_sfc(st_polygon(list(as.matrix(rbind(boundary_xy, boundary_xy[1, ])))), crs = crs_utm)
) # end boundary
# the area cameras may go: the boundary shrunk by the inset
boundary_inner <- st_buffer(boundary, -boundary_inset_m)

## how far the boundary reaches from the tower in each direction
bb <- st_bbox(boundary)
extent_km <- c(west = tower_utm[1] - bb[["xmin"]], east = bb[["xmax"]] - tower_utm[1],
               north = bb[["ymax"]] - tower_utm[2], south = tower_utm[2] - bb[["ymin"]]) / 1000


#
##
### Read the mapped water from 02_water_and_basemap.R ----

hydro_path <- file.path(campaign_dir, "data", "processed", "qld_hydrography.gpkg")
# the design depends on it, so stop rather than carry on without the water rule
if (!file.exists(hydro_path)) {
  stop("No hydrography at ", hydro_path, "\nRun 02_water_and_basemap.R first.")
} # end hydrography check

## the channels that set the water rule
water_channels <- st_read(hydro_path, quiet = TRUE) |>
  # keep the chosen layers only
  filter(layer %in% water_layers) |>
  # into UTM for distances
  st_transform(crs_utm) |>
  # the buffer each channel gets: wider for the main river
  mutate(buffer_m = ifelse(!is.na(name) & name == major_river_name,
                           water_buffer_major_m, water_buffer_minor_m))

## the zone too close to any channel, as one shape
water_buffer <- water_channels |>
  # widen each channel by its own buffer distance
  st_buffer(water_channels$buffer_m) |>
  # and merge them
  st_union() |>
  # as an sf layer with a label
  st_sf(name = sprintf("within %d m of the %s or %d m of a creek channel",
                       water_buffer_major_m, major_river_name, water_buffer_minor_m),
        geometry = _)


#
##
### Lay the grid and sort the nodes ----

## grid nodes inside the inset boundary, with distance and bearing from the tower
points <- make_grid_design(boundary, origin = tower_utm, spacing = grid_spacing_m,
                           inset = boundary_inset_m, id_prefix = point_prefix)

## a small lookup from grid offsets to point IDs, for the hand-chosen nodes
id_at <- function(offsets) {
  points$point_id[match(paste(offsets$grid_i, offsets$grid_j), paste(points$grid_i, points$grid_j))]
} # end lookup

# distance from each grid node to the nearest channel, before any moves
points$water_dist_node_m <- as.numeric(st_distance(points, st_union(water_channels)))

## move the chosen sites back from the river (recomputes position, distance and bearing)
points <- relocate_away_from_water(points, ids = id_at(relocate_offsets),
                                   water = water_channels, max_move = relocate_max_m,
                                   allowed_area = boundary_inner, origin = tower_utm)

## flag sites inside the water zone, judged where the camera goes
near_water <- lengths(st_intersects(points, water_buffer)) > 0
# the same, as the reason recorded against each site
water_reason <- sprintf("within %d m of the %s or %d m of a creek channel",
                        water_buffer_major_m, major_river_name, water_buffer_minor_m)

## the footprint wedge and the wider zone that decides footprint sites
footprint_shapes <- make_footprint_zone(tower_utm, max_dist = footprint_max_dist_m,
                                        bearing = footprint_bearing, buffer = footprint_buffer_m,
                                        crs = crs_utm)
footprint_wedge <- filter(footprint_shapes, part == "wedge")
footprint_zone <- filter(footprint_shapes, part == "zone")

## label each site footprint, main or backup
points <- classify_points(points,
                          footprint_zone = footprint_zone,
                          thin_min_dist = thin_min_dist_m,
                          thin_bearing = thin_bearing,
                          thin_reason = "far downwind block, checkerboard thinning",
                          backup_offsets = backup_offsets,
                          backup_flags = setNames(list(near_water), water_reason))
# keep the water flag itself, since footprint sites can be near water too
points$near_water <- near_water

## rank the backups: dry sites first, then near-water sites, each by coverage gained,
## with the named sites last
last_ids <- id_at(last_offsets)
points <- rank_backup_sites(points, planned_status = c("footprint", "main"),
                            backup_status = "backup", unsafe_col = "near_water",
                            tie_col = "water_dist_after_m", last_ids = last_ids)
# note why the last sites are last
points$backup_reason[points$point_id %in% last_ids] <-
  paste0(points$backup_reason[points$point_id %in% last_ids], "; ranked last: ", last_offsets$note)

## the label shown on maps: the ID, plus the rank for backups
points$map_label <- ifelse(is.na(points$backup_rank), points$point_id,
                           sprintf("%s (B%d)", points$point_id, points$backup_rank))

## add WGS84 coordinates for GPS units and the CSV
ll <- st_coordinates(st_transform(points, 4326))
points$lat <- ll[, "Y"]
points$lon <- ll[, "X"]

### spatial coverage as minimum convex polygons (MCP)
## planned = footprint and main, which are always deployed
planned <- points |> filter(status != "backup")
mcp_planned_km2 <- as.numeric(st_area(st_convex_hull(st_union(planned)))) / 1e6
## cameras left over for backups, and the coverage once they are all placed in rank order
n_backup_cameras <- camera_cap - nrow(planned)
mcp_at_cap_km2 <- points$mcp_after_km2[which(points$backup_rank == n_backup_cameras)]
## the first backup rank at which coverage reaches the target
rank_reaching_target <- min(points$backup_rank[!is.na(points$mcp_after_km2) &
                                                 points$mcp_after_km2 >= mcp_target_km2])
## every site
mcp_all_km2 <- as.numeric(st_area(st_convex_hull(st_union(points)))) / 1e6

## a placement circle around every site, for choosing the camera tree in the field
placement_zones <- points |>
  # the columns the field map needs
  select(point_id, status, backup_rank, map_label) |>
  # a circle of the placement radius
  st_buffer(placement_radius_m)

## the tower as its own layer
flux_tower <- st_sf(
  name = "Flux tower (AU-Fle)",
  note = "OzFlux eddy covariance tower; 25 m tall, canopy 12 m",
  geometry = st_sfc(st_point(tower_utm), crs = crs_utm)
) # end tower

## how far apart the two published tower positions are
tower_ozflux_utm <- st_sfc(st_point(c(146.189138, -19.887285)), crs = 4326) |>
  st_transform(crs_utm) |>
  st_coordinates() |>
  as.vector()
tower_offset_m <- sqrt(sum((tower_ozflux_utm - tower_utm)^2))

# show the design in the console, backups in rank order
print(st_drop_geometry(points) |>
        arrange(status != "footprint", status != "main", backup_rank) |>
        select(point_id, status, backup_rank, mcp_after_km2, near_water, moved_m, water_dist_after_m),
      digits = 4)
print(table(points$status))
message(sprintf("MCP planned %.2f km2; with %d backup cameras %.2f km2; target %g km2 reached at backup B%d",
                mcp_planned_km2, n_backup_cameras, mcp_at_cap_km2, mcp_target_km2, rank_reaching_target))


#
##
### Write the QField project folder ----

## one folder holds everything QField needs; copy it to the phone as is
qfield_dir <- file.path(campaign_dir, "outputs", paste0("qfield_", design_version))
dir.create(qfield_dir, recursive = TRUE, showWarnings = FALSE)
gpkg_name <- paste0("fletcherview_design_", design_version, ".gpkg")
gpkg <- file.path(qfield_dir, gpkg_name)

## the points layer, in WGS84, with the columns field staff need
points_out <- points |>
  # field-ready columns only
  select(point_id, status, backup_rank, map_label, backup_reason, near_water, moved_m,
         grid_i, grid_j, dist_m, bearing, lat, lon) |>
  # round to what is meaningful in the field
  mutate(dist_m = round(dist_m), bearing = round(bearing, 1), moved_m = round(moved_m)) |>
  # backups in rank order after the planned sites, so lists read top-down
  arrange(status == "backup", backup_rank, point_id) |>
  # GPS and QField work in WGS84
  st_transform(4326)

### an empty layer for QField to record where cameras actually went
## one dummy row sets the geometry type to POINT, then it is removed
deployments <- st_sf(
  deployment_id = "x",
  point_id = "x",
  notes = "x",
  recorded_at = as.POSIXct("2026-01-01 00:00:00", tz = "UTC"),
  geometry = st_sfc(st_point(c(tower_lon, tower_lat)), crs = 4326)
)[0, ] # end deployments layer

## GeoPackage: start fresh so stale layers never linger
unlink(gpkg)
# each layer in WGS84, named as QField will list it
gpkg_layers <- list(
  planned_points = points_out,
  flux_tower = st_transform(flux_tower, 4326),
  boundary_approx = st_transform(boundary, 4326),
  placement_zones = st_transform(placement_zones, 4326),
  footprint_wedge = st_transform(select(footprint_wedge, name), 4326),
  footprint_zone = st_transform(select(footprint_zone, name), 4326),
  water_channels = st_transform(select(water_channels, name, perenniality, hierarchy, buffer_m), 4326),
  water_buffer = st_transform(water_buffer, 4326),
  deployments = deployments
) # end layer list
# write them one at a time into the same file
for (lyr in names(gpkg_layers)) {
  st_write(gpkg_layers[[lyr]], gpkg, layer = lyr, quiet = TRUE)
} # end per layer

## copy the basemap next to the GeoPackage
basemap_src <- file.path(campaign_dir, "data", "processed", "qtopo_basemap.tif")
if (!file.exists(basemap_src)) {
  stop("No basemap at ", basemap_src, "\nRun 02_water_and_basemap.R first.")
} # end basemap check
copied <- file.copy(basemap_src, file.path(qfield_dir, "qtopo_basemap.tif"), overwrite = TRUE)

### describe how QField draws each layer, top layer first
## every vector layer is stored in WGS84
crs_ll <- st_crs(4326)
# source string for a layer inside the GeoPackage
src <- function(lyr) paste0("./", gpkg_name, "|layername=", lyr)
# the status styles, one marker per category
status_style <- list(
  kind = "categorized", attr = "status",
  categories = data.frame(
    value = names(status_colours),
    label = c("footprint (always deploy)", "main (always deploy)", "backup (fill in rank order)"),
    fill = unname(status_colours),
    outline = "#000000",
    shape = "circle",
    # a dot fixed at 25 m across on the ground, so it never swamps the circle
    size = 25,
    size_unit = "MapUnit",
    outline_width = 0.3
  ) # end categories
) # end status style
# the placement circles, lightly filled in the status colour
zone_style <- list(
  kind = "categorized", attr = "status", geom = "fill",
  categories = data.frame(
    value = names(status_colours),
    label = sprintf("%s: %d m placement circle", names(status_colours), placement_radius_m),
    fill = unname(status_colours),
    alpha = 70,
    outline = unname(status_colours),
    outline_width = 0.6
  ) # end categories
) # end zone style

qgis_layers <- list(
  # where cameras actually went: editable, with a drop-down for point_id and an automatic timestamp
  qgis_layer_xml("deployments", "Deployments (record here)", src("deployments"), crs_ll,
                 list(kind = "single", geom = "marker", shape = "star", size = 5,
                      fill = "#33A02C", outline = "#000000"),
                 label_field = "deployment_id", read_only = FALSE,
                 field_defaults = c(recorded_at = "now()"),
                 value_maps = list(point_id = points_out$point_id)),
  # the flux tower
  qgis_layer_xml("flux_tower", "Flux tower", src("flux_tower"), crs_ll,
                 list(kind = "single", geom = "marker", shape = "triangle", size = 5,
                      fill = tower_colour, outline = "#FFFFFF")),
  # camera sites, coloured by status and labelled with ID and backup rank
  qgis_layer_xml("planned_points", "Camera sites", src("planned_points"), crs_ll,
                 status_style, label_field = "map_label"),
  # the placement circle around each site, fixed in metres
  qgis_layer_xml("placement_zones", sprintf("Placement circles (%d m)", placement_radius_m),
                 src("placement_zones"), crs_ll, zone_style, geometry = "Polygon"),
  # the approximate property boundary, outline only
  qgis_layer_xml("boundary_approx", "Property boundary (approximate)", src("boundary_approx"), crs_ll,
                 list(kind = "single", geom = "fill", fill = NULL, outline = boundary_colour,
                      outline_style = "dash", outline_width = 0.7),
                 geometry = "Polygon"),
  # the wind wedge, as an outline
  qgis_layer_xml("footprint_wedge", "Flux footprint wedge (wind)", src("footprint_wedge"), crs_ll,
                 list(kind = "single", geom = "fill", fill = NULL,
                      outline = status_colours[["footprint"]], outline_style = "dash", outline_width = 0.5),
                 geometry = "Polygon"),
  # the wider footprint zone, lightly shaded
  qgis_layer_xml("footprint_zone", sprintf("Flux footprint zone (wedge + %d m)", footprint_buffer_m),
                 src("footprint_zone"), crs_ll,
                 list(kind = "single", geom = "fill", fill = status_colours[["footprint"]], alpha = 40,
                      outline = status_colours[["footprint"]], outline_width = 0.3),
                 geometry = "Polygon"),
  # mapped channels
  qgis_layer_xml("water_channels", "Mapped river/creek channels", src("water_channels"), crs_ll,
                 list(kind = "single", geom = "fill", fill = water_colour, alpha = 110,
                      outline = water_colour, outline_width = 0.3),
                 geometry = "Polygon"),
  # the wet-season buffer around them
  qgis_layer_xml("water_buffer", sprintf("Wet-season zone (%d m Burdekin, %d m creeks)",
                                       water_buffer_major_m, water_buffer_minor_m), src("water_buffer"),
                 crs_ll,
                 list(kind = "single", geom = "fill", fill = water_colour, alpha = 35,
                      outline = water_colour, outline_style = "dot", outline_width = 0.4),
                 geometry = "Polygon"),
  # the QTopo basemap, at the bottom
  qgis_layer_xml("qtopo_basemap", "QTopo 1:25k basemap", "./qtopo_basemap.tif", st_crs(crs_utm),
                 list(kind = "raster"))
) # end layer list

## open on the property, with a little margin
view <- c(bb[["xmin"]] - 500, bb[["ymin"]] - 500, bb[["xmax"]] + 500, bb[["ymax"]] + 500)
qgs_path <- write_qgis_project(file.path(qfield_dir, paste0("fletcherview_", design_version, ".qgs")),
                               title = paste("Fletcherview camera design", design_version),
                               crs = st_crs(crs_utm), layers = qgis_layers, extent = view)


#
##
### Write the KML and CSV ----

# both share this stem
stem <- file.path(campaign_dir, "outputs", paste0("fletcherview_design_", design_version))

## KML for Google Earth and phones, one folder per status plus the tower
tower_kml <- st_sf(
  name = "Flux tower",
  description = sprintf("Fletcherview OzFlux tower (AU-Fle), %.6f, %.6f. Tower 25 m, canopy 12 m.",
                        tower_lat, tower_lon),
  geometry = st_sfc(st_point(c(tower_lon, tower_lat)), crs = 4326)
) # end tower placemark
kml_path <- write_kml_points(mutate(points_out, point_id = map_label), paste0(stem, ".kml"),
                             status_colours = status_colours,
                             description_cols = c("status", "backup_rank", "backup_reason", "moved_m",
                                                  "dist_m", "bearing", "lat", "lon"),
                             boundary = boundary, boundary_name = "Property boundary (approximate)",
                             boundary_description = boundary$note,
                             extra_points = tower_kml, extra_folder = "Flux tower",
                             doc_name = paste("Fletcherview camera design", design_version))

## CSV of points for printing and spreadsheets, backups in rank order
points_out |>
  # drop the geometry, keep the field columns
  st_drop_geometry() |>
  select(point_id, status, backup_rank, backup_reason, moved_m, dist_m, bearing, lat, lon) |>
  # full precision on coordinates
  mutate(lat = round(lat, 7), lon = round(lon, 7)) |>
  write_csv(file.path(campaign_dir, "outputs",
                      paste0("fletcherview_planned_points_", design_version, ".csv")), na = "")


#
##
### Draw the preview over the QTopo basemap ----

## read the basemap as an RGB array scaled to 0-1
## (terra:: rather than library(terra), because loading it would mask dplyr's select())
basemap <- terra::rast(basemap_src)
basemap_array <- terra::as.array(basemap)[, , 1:3] / 255
basemap_ext <- as.vector(terra::ext(basemap)) # xmin, xmax, ymin, ymax

## plain data frames for ggplot, all in UTM metres
pts_df <- st_drop_geometry(points) |>
  # keep status in the legend order
  mutate(status = factor(status, levels = names(status_colours)))
# the sites that moved, with their original grid node
moved_df <- filter(pts_df, moved_m > 0)

## names for the map-layer legend, in the order they should be listed
layer_labels <- c(boundary = "Property boundary (approximate)",
                  wedge = sprintf("Wind wedge (%g-%g°, %g km)", footprint_bearing[1],
                                  footprint_bearing[2], footprint_max_dist_m / 1000),
                  zone = sprintf("Flux footprint zone (wedge + %d m)", footprint_buffer_m),
                  channel = "Mapped river/creek channel",
                  buffer = sprintf("Wet-season zone (%d m Burdekin, %d m creeks)",
                                   water_buffer_major_m, water_buffer_minor_m))
## names for the marker legend
marker_labels <- c(tower = "Flux tower (AU-Fle)", node = "Grid node (camera moved off it)")

## the view: the property plus a margin
view_x <- c(bb[["xmin"]] - 600, bb[["xmax"]] + 600)
view_y <- c(bb[["ymin"]] - 600, bb[["ymax"]] + 600)

## build the preview
p <- ggplot() +
  # the QTopo basemap, placed by its own georeferencing
  annotation_raster(basemap_array, xmin = basemap_ext[1], xmax = basemap_ext[2],
                    ymin = basemap_ext[3], ymax = basemap_ext[4]) +
  # the wet-season water buffer
  geom_sf(data = water_buffer, aes(colour = layer_labels[["buffer"]]),
          fill = water_colour, alpha = 0.15, linewidth = 0.3, linetype = "dotted") +
  # the mapped channels
  geom_sf(data = water_channels, aes(colour = layer_labels[["channel"]]),
          fill = water_colour, alpha = 0.45, linewidth = 0.2) +
  # the footprint zone, shaded
  geom_sf(data = footprint_zone, aes(colour = layer_labels[["zone"]]),
          fill = status_colours[["footprint"]], alpha = 0.15, linewidth = 0.3) +
  # the wind wedge inside it, as a dashed outline
  geom_sf(data = footprint_wedge, aes(colour = layer_labels[["wedge"]]),
          fill = NA, linewidth = 0.5, linetype = "dashed") +
  # the approximate boundary
  geom_sf(data = boundary, aes(colour = layer_labels[["boundary"]]),
          fill = NA, linewidth = 0.7, linetype = "longdash") +
  # for moved sites, an arrow from the grid node to the camera's new spot
  geom_segment(data = moved_df, aes(x = node_x, y = node_y, xend = x, yend = y),
               arrow = arrow(length = unit(0.18, "cm")), linewidth = 0.5) +
  # and the grid node itself as a hollow circle
  geom_point(data = moved_df, aes(node_x, node_y, shape = marker_labels[["node"]]),
             size = 2.6, stroke = 0.6) +
  # the placement circle around every site, filled by status
  geom_sf(data = mutate(placement_zones, status = factor(status, levels = names(status_colours))),
          aes(fill = status), colour = "black", linewidth = 0.25, alpha = 0.75) +
  # and the site itself as a small dot at its centre
  geom_point(data = pts_df, aes(x, y), size = 0.5) +
  # labels: ID, plus rank for backups, with a white halo for legibility
  geom_label(data = pts_df, aes(x, y, label = map_label), size = 2.3, nudge_y = 170,
             linewidth = 0, label.padding = unit(0.08, "lines"), fill = "white", alpha = 0.8) +
  # the tower
  geom_point(data = data.frame(x = tower_utm[1], y = tower_utm[2]),
             aes(x, y, shape = marker_labels[["tower"]]), size = 3.8, fill = tower_colour, colour = "white") +
  # camera status legend
  scale_fill_manual(values = status_colours, limits = names(status_colours),
                    labels = c("footprint (always deploy)", "main (always deploy)",
                               "backup, ranked B1, B2, ... (fill in order)"),
                    name = sprintf("Camera site (%d m placement circle)", placement_radius_m),
                    guide = guide_legend(order = 1)) +
  ## map layer legend; every layer draws a key for every entry, so all their looks are set here
  scale_colour_manual(
    values = setNames(c(boundary_colour, status_colours[["footprint"]], status_colours[["footprint"]],
                        water_colour, water_colour),
                      layer_labels),
    limits = unname(layer_labels), name = "Map layers",
    guide = guide_legend(order = 2, override.aes = list(
      fill = c(NA, NA, status_colours[["footprint"]], water_colour, water_colour),
      alpha = c(1, 1, 0.15, 0.45, 0.15),
      linetype = c("longdash", "dashed", "solid", "solid", "dotted"),
      linewidth = c(0.7, 0.5, 0.3, 0.2, 0.3)))) +
  ## marker legend; both marker layers draw both keys, so their looks are set here too
  scale_shape_manual(values = setNames(c(24, 1), marker_labels), limits = unname(marker_labels),
                     name = NULL,
                     guide = guide_legend(order = 3, override.aes = list(
                       fill = c(tower_colour, NA), colour = c(tower_colour, "black"),
                       size = c(3.8, 2.6)))) +
  # crop to the property, in UTM
  coord_sf(crs = crs_utm, datum = crs_utm, xlim = view_x, ylim = view_y, expand = FALSE) +
  # labels
  labs(title = paste("Fletcherview camera design", design_version),
       subtitle = sprintf(paste0("%d m grid from the flux tower. %d cameras: %d always deployed, ",
                                 "%d to backups B1-B%d. Basemap: QTopo 1:25k (State of Queensland)."),
                          grid_spacing_m, camera_cap, nrow(planned), n_backup_cameras, n_backup_cameras),
       x = NULL, y = NULL) +
  theme_minimal(base_size = 10) +
  theme(legend.position = "right", panel.grid = element_blank())

ggsave(paste0(stem, "_preview.png"), p, width = 11, height = 7, dpi = 200, bg = "white")


#
##
### Write the summary table ----

## every number the README quotes, one row each
n_status <- table(factor(points$status, levels = names(status_colours)))
# the moved and last-ranked sites, for the README
moved <- points |> st_drop_geometry() |> filter(moved_m > 0)
summary_table <- data.frame(
  quantity = c("m_per_px", "boundary_area_ha", "n_nodes",
               paste0("n_", names(n_status)), "n_planned", "camera_cap", "n_backup_cameras",
               "mcp_planned_km2", "mcp_at_camera_cap_km2", "mcp_all_sites_km2", "mcp_target_km2",
               "backup_rank_reaching_target",
               paste0(moved$point_id, "_moved_m"),
               paste0(moved$point_id, "_water_dist_before_m"),
               paste0(moved$point_id, "_water_dist_after_m"),
               "extent_west_km", "extent_east_km", "extent_north_km", "extent_south_km",
               "tower_offset_to_ozflux_m"),
  value = c(round(m_per_px, 3), round(as.numeric(st_area(boundary)) / 1e4),
            nrow(points), as.vector(n_status), nrow(planned), camera_cap, n_backup_cameras,
            round(mcp_planned_km2, 2), round(mcp_at_cap_km2, 2), round(mcp_all_km2, 2), mcp_target_km2,
            rank_reaching_target,
            round(moved$moved_m), round(moved$water_dist_node_m), round(moved$water_dist_after_m),
            round(extent_km, 2), round(tower_offset_m, 1))
) # end summary table
write_csv(summary_table, file.path(campaign_dir, "outputs",
                                   paste0("design_summary_", design_version, ".csv")))

message("Design outputs written to ", file.path(campaign_dir, "outputs"))
