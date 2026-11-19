### 03_design_grid.R -- camera grid and QField map for the Fletcherview flux tower campaign
##
## Lays an 800 m square grid over Fletcherview with one node on the flux tower,
## keeps the nodes far enough inside the property for a camera to go on a nearby
## tree, and labels each by priority: footprint (upwind of the tower, from
## 01_wind_footprint.R), core, drop_first (planned, but the first to give up on the
## day) and reserve (deploy only if cameras are spare). Nodes near mapped river
## and creek channels are drop_first for the wet season.
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
source(here("R", "classify_points.R"))
source(here("R", "write_kml_points.R"))
source(here("R", "qgis_layer_xml.R"))
source(here("R", "write_qgis_project.R"))


#
##
### Set the knobs for this design ----

## design version stamped on every output file
design_version <- "v2"
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
boundary_inset_m <- 100 # cameras go on the best tree within ~100 m of a node
point_prefix <- "FV" # point IDs FV01, FV02, ...

## footprint: within 2 km of the tower, in the upwind arc from 01_wind_footprint.R
footprint_max_dist_m <- 2000
footprint_bearing <- c(10, 125)
## reserve: checkerboard-thin the far downwind (western) block
reserve_min_dist_m <- 1600
reserve_bearing <- c(170, 330)

### Which core nodes are drop_first?
## (1) two interior downwind nodes whose loss leaves the MCP unchanged (FV03, FV14)
drop_first_offsets <- data.frame(grid_i = c(-3, -3), grid_j = c(3, 1),
                                 reason = "interior downwind, MCP unchanged")
## (2) wet season: any node within this distance of a mapped river or creek channel
water_buffer_m <- 500
## "mapped channel" = the Queensland Government watercourse-area polygons (ZDA, 2026-11-19)
water_layers <- c("watercourse_area")

## the analysis minimum for sampled area (camDB), km2
mcp_target_km2 <- 15

## colours for each status, used by the KML, the preview and QField
status_colours <- c(footprint = "#E41A1C", core = "#FFD92F",
                    drop_first = "#FF7F00", reserve = "#999999")
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
  st_transform(crs_utm)

## the zone within the buffer distance of any channel, as one shape
water_buffer <- water_channels |>
  # widen each channel by the buffer distance
  st_buffer(water_buffer_m) |>
  # and merge them
  st_union() |>
  # as an sf layer with a label
  st_sf(name = sprintf("within %d m of a mapped channel", water_buffer_m), geometry = _)


#
##
### Lay the grid and classify the nodes ----

## grid nodes inside the inset boundary, with distance and bearing from the tower
points <- make_grid_design(boundary, origin = tower_utm, spacing = grid_spacing_m,
                           inset = boundary_inset_m, id_prefix = point_prefix)

## flag nodes within the buffer distance of a mapped channel
near_water <- lengths(st_is_within_distance(points, water_channels, water_buffer_m)) > 0
# the same, as the reason recorded against each node
water_reason <- sprintf("within %d m of a mapped river or creek channel", water_buffer_m)

## label each node footprint, reserve, drop_first or core
points <- classify_points(points,
                          footprint_max_dist = footprint_max_dist_m,
                          footprint_bearing = footprint_bearing,
                          reserve_min_dist = reserve_min_dist_m,
                          reserve_bearing = reserve_bearing,
                          drop_first_offsets = drop_first_offsets,
                          drop_first_flags = setNames(list(near_water), water_reason))
# keep the water flag itself, since footprint and reserve nodes can be near water too
points$near_water <- near_water

## add WGS84 coordinates for GPS units and the CSV
ll <- st_coordinates(st_transform(points, 4326))
points$lat <- ll[, "Y"]
points$lon <- ll[, "X"]

### spatial coverage as minimum convex polygons (MCP)
## planned = every non-reserve node
planned <- points |> filter(status != "reserve")
mcp_planned_km2 <- as.numeric(st_area(st_convex_hull(st_union(planned)))) / 1e6
## first choice = planned, less every drop_first node (the worst case on the day)
first_choice <- planned |> filter(status != "drop_first")
mcp_first_choice_km2 <- as.numeric(st_area(st_convex_hull(st_union(first_choice)))) / 1e6

## the footprint wedge as a polygon, built in map coordinates so north is up
# bearings along the arc, one per degree
arc <- seq(footprint_bearing[1], footprint_bearing[2], by = 1) * pi / 180
wedge_xy <- cbind(
  # start at the tower, sweep the arc clockwise, return to the tower
  c(tower_utm[1], tower_utm[1] + footprint_max_dist_m * sin(arc), tower_utm[1]),
  c(tower_utm[2], tower_utm[2] + footprint_max_dist_m * cos(arc), tower_utm[2])
) # end wedge coordinates
footprint_wedge <- st_sf(
  name = sprintf("flux footprint: %g-%g deg within %g km", footprint_bearing[1],
                 footprint_bearing[2], footprint_max_dist_m / 1000),
  geometry = st_sfc(st_polygon(list(wedge_xy)), crs = crs_utm)
) # end wedge

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

# show the design in the console
print(st_drop_geometry(points) |> select(point_id, status, near_water, dist_m, bearing, drop_reason),
      digits = 4)
print(table(points$status))
message(sprintf("MCP planned %.2f km2; first choice only %.2f km2 (target %g km2)",
                mcp_planned_km2, mcp_first_choice_km2, mcp_target_km2))


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
  select(point_id, status, drop_reason, near_water, grid_i, grid_j, dist_m, bearing, lat, lon) |>
  # round to what is meaningful in the field
  mutate(dist_m = round(dist_m), bearing = round(bearing, 1)) |>
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
  footprint_wedge = st_transform(footprint_wedge, 4326),
  water_channels = st_transform(select(water_channels, name, perenniality, hierarchy), 4326),
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
    label = c("footprint (deploy first)", "core", "drop_first (near water / interior)",
              "reserve (only if spare)"),
    fill = unname(status_colours),
    outline = c("#000000", "#000000", "#000000", "#999999"),
    shape = c("circle", "circle", "circle", "cross2"),
    size = c(4, 4, 4, 4),
    outline_width = c(0.4, 0.4, 0.4, 0.8)
  ) # end categories
) # end status style

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
  # planned camera points, coloured by status and labelled with their ID
  qgis_layer_xml("planned_points", "Planned points", src("planned_points"), crs_ll,
                 status_style, label_field = "point_id"),
  # the approximate property boundary, outline only
  qgis_layer_xml("boundary_approx", "Property boundary (approximate)", src("boundary_approx"), crs_ll,
                 list(kind = "single", geom = "fill", fill = NULL, outline = boundary_colour,
                      outline_style = "dash", outline_width = 0.7),
                 geometry = "Polygon"),
  # the flux footprint wedge, lightly shaded
  qgis_layer_xml("footprint_wedge", "Flux footprint wedge", src("footprint_wedge"), crs_ll,
                 list(kind = "single", geom = "fill", fill = status_colours[["footprint"]], alpha = 45,
                      outline = status_colours[["footprint"]], outline_style = "dash", outline_width = 0.5),
                 geometry = "Polygon"),
  # mapped channels
  qgis_layer_xml("water_channels", "Mapped river/creek channels", src("water_channels"), crs_ll,
                 list(kind = "single", geom = "fill", fill = water_colour, alpha = 110,
                      outline = water_colour, outline_width = 0.3),
                 geometry = "Polygon"),
  # the wet-season buffer around them
  qgis_layer_xml("water_buffer", sprintf("Within %d m of a channel", water_buffer_m), src("water_buffer"),
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
kml_path <- write_kml_points(points_out, paste0(stem, ".kml"),
                             status_colours = status_colours,
                             description_cols = c("status", "drop_reason", "dist_m", "bearing", "lat", "lon"),
                             boundary = boundary, boundary_name = "Property boundary (approximate)",
                             boundary_description = boundary$note,
                             extra_points = tower_kml, extra_folder = "Flux tower",
                             doc_name = paste("Fletcherview camera design", design_version))

## CSV of points for printing and spreadsheets
points_out |>
  # drop the geometry, keep the field columns
  st_drop_geometry() |>
  select(point_id, status, drop_reason, dist_m, bearing, lat, lon) |>
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

## names for the map-layer legend, in the order they should be listed
layer_labels <- c(boundary = "Property boundary (approximate)",
                  wedge = sprintf("Flux footprint (%g-%g°, %g km)", footprint_bearing[1],
                                  footprint_bearing[2], footprint_max_dist_m / 1000),
                  channel = "Mapped river/creek channel",
                  buffer = sprintf("Within %d m of a channel", water_buffer_m))

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
  # the footprint wedge
  geom_sf(data = footprint_wedge, aes(colour = layer_labels[["wedge"]]),
          fill = status_colours[["footprint"]], alpha = 0.18, linewidth = 0.5, linetype = "dashed") +
  # the approximate boundary
  geom_sf(data = boundary, aes(colour = layer_labels[["boundary"]]),
          fill = NA, linewidth = 0.7, linetype = "longdash") +
  ## planned points as filled circles; reserve rows are drawn at size 0 (invisible) only so
  ## the status legend gets a reserve key, which override.aes then redraws as a cross
  geom_point(data = pts_df,
             aes(x, y, fill = status, size = I(ifelse(status == "reserve", 0, 3.2))),
             shape = 21, colour = "black", stroke = 0.4) +
  # reserve points as grey crosses over a black cross, so they show on any background
  geom_point(data = filter(pts_df, status == "reserve"),
             aes(x, y), shape = 4, size = 3.4, stroke = 2.2, colour = "black") +
  geom_point(data = filter(pts_df, status == "reserve"),
             aes(x, y), shape = 4, size = 3, stroke = 1.2, colour = status_colours[["reserve"]]) +
  # point IDs just above each point, with a white halo for legibility
  geom_label(data = pts_df, aes(x, y, label = point_id), size = 2.4, nudge_y = 170,
             linewidth = 0, label.padding = unit(0.08, "lines"), fill = "white", alpha = 0.8) +
  # the tower, in its own legend
  geom_point(data = data.frame(x = tower_utm[1], y = tower_utm[2]),
             aes(x, y, shape = "Flux tower (AU-Fle)"), size = 3.8, fill = tower_colour, colour = "white") +
  ## camera status legend; the reserve key is redrawn as a grey cross
  scale_fill_manual(values = status_colours, limits = names(status_colours), drop = FALSE,
                    name = "Camera status",
                    guide = guide_legend(order = 1, override.aes = list(
                      shape = c(21, 21, 21, 4), size = 3.2,
                      colour = c("black", "black", "black", status_colours[["reserve"]]),
                      stroke = c(0.4, 0.4, 0.4, 1.2)))) +
  ## map layer legend; every layer draws a key for every entry, so all their looks are set here
  scale_colour_manual(
    values = setNames(c(boundary_colour, status_colours[["footprint"]], water_colour, water_colour),
                      layer_labels),
    limits = unname(layer_labels), name = "Map layers",
    guide = guide_legend(order = 2, override.aes = list(
      fill = c(NA, status_colours[["footprint"]], water_colour, water_colour),
      alpha = c(1, 0.18, 0.45, 0.15),
      linetype = c("longdash", "dashed", "solid", "dotted"),
      linewidth = c(0.7, 0.5, 0.2, 0.3)))) +
  # tower legend
  scale_shape_manual(values = c("Flux tower (AU-Fle)" = 24), name = NULL,
                     guide = guide_legend(order = 3)) +
  # crop to the property, in UTM
  coord_sf(crs = crs_utm, datum = crs_utm, xlim = view_x, ylim = view_y, expand = FALSE) +
  # labels
  labs(title = paste("Fletcherview camera design", design_version),
       subtitle = sprintf("%d m grid from the flux tower. Basemap: QTopo 1:25k (State of Queensland).",
                          grid_spacing_m),
       x = NULL, y = NULL) +
  theme_minimal(base_size = 10) +
  theme(legend.position = "right", panel.grid = element_blank())

ggsave(paste0(stem, "_preview.png"), p, width = 11, height = 7, dpi = 200, bg = "white")


#
##
### Write the summary table ----

## every number the README quotes, one row each
n_status <- table(factor(points$status, levels = names(status_colours)))
summary_table <- data.frame(
  quantity = c("m_per_px", "boundary_area_ha", "n_nodes",
               paste0("n_", names(n_status)), "n_planned", "n_first_choice",
               "n_near_water_all", "n_near_water_footprint", "n_near_water_reserve",
               "mcp_planned_km2", "mcp_first_choice_km2", "mcp_target_km2",
               "extent_west_km", "extent_east_km", "extent_north_km", "extent_south_km",
               "tower_offset_to_ozflux_m"),
  value = c(round(m_per_px, 3), round(as.numeric(st_area(boundary)) / 1e4),
            nrow(points), as.vector(n_status), nrow(planned), nrow(first_choice),
            sum(points$near_water), sum(points$near_water & points$status == "footprint"),
            sum(points$near_water & points$status == "reserve"),
            round(mcp_planned_km2, 2), round(mcp_first_choice_km2, 2), mcp_target_km2,
            round(extent_km, 2), round(tower_offset_m, 1))
) # end summary table
write_csv(summary_table, file.path(campaign_dir, "outputs",
                                   paste0("design_summary_", design_version, ".csv")))

message("Design outputs written to ", file.path(campaign_dir, "outputs"))
