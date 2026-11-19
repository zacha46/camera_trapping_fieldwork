### 02_design_grid.R -- camera grid for the Fletcherview flux tower campaign
##
## Lays an 800 m square grid over Fletcherview with one node on the flux tower,
## keeps the nodes far enough inside the property for a camera to go on a nearby
## tree, and labels each by priority: footprint (upwind of the tower, from
## 01_wind_footprint.R), core, drop_first (give up first if cameras run short) and
## reserve (deploy only if cameras are spare).
##
## There is no cadastral boundary, so the property outline is traced by hand from a
## satellite screenshot and scaled to the station's known 2,400 ha. Treat it as
## approximate; see the campaign README.
##
## Inputs: none required. data/raw/propertyScreenshot.png is used only as the
## preview background; data/raw/fletcherview_planned_points_v1.csv is used to
## validate against v1 if present.
## Outputs (outputs/): GeoPackage for QField, KML, CSV of points, preview figure,
## and a summary table holding every number quoted in the campaign README.


## Load libraries
library(tidyverse) # For basic data wrangling and plotting
library(sf)        # For everything spatial (terra:: is used once, for the screenshot)
library(here)      # For project-relative paths so this runs on any machine

## Load the shared helpers this script uses
source(here("R", "pixel_to_map.R"))
source(here("R", "make_grid_design.R"))
source(here("R", "classify_points.R"))
source(here("R", "write_kml_points.R"))


#
##
### Set the knobs for this design ----

## design version stamped on every output file
design_version <- "v1"
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
### Which core nodes are the first to drop?
## two interior downwind nodes whose loss leaves the MCP unchanged (FV03 and FV14 in v1)
drop_first_offsets <- data.frame(grid_i = c(-3, -3), grid_j = c(3, 1))

## colours for each status, used by the KML and the preview
status_colours <- c(footprint = "#E41A1C", core = "#FFD92F",
                    drop_first = "#FF7F00", reserve = "#999999")

## compare against the numbers from the original v1 chat session
check_against_v1 <- TRUE


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
### Lay the grid and classify the nodes ----

## grid nodes inside the inset boundary, with distance and bearing from the tower
points <- make_grid_design(boundary, origin = tower_utm, spacing = grid_spacing_m,
                           inset = boundary_inset_m, id_prefix = point_prefix)

## label each node footprint, reserve, drop_first or core
points <- classify_points(points,
                          footprint_max_dist = footprint_max_dist_m,
                          footprint_bearing = footprint_bearing,
                          reserve_min_dist = reserve_min_dist_m,
                          reserve_bearing = reserve_bearing,
                          drop_first_offsets = drop_first_offsets)

## add WGS84 coordinates for GPS units and the CSV
ll <- st_coordinates(st_transform(points, 4326))
points$lat <- ll[, "Y"]
points$lon <- ll[, "X"]

## spatial coverage as minimum convex polygons (MCP) of the cameras actually planned
# planned = every non-reserve node
planned <- points |> filter(status != "reserve")
mcp_planned_km2 <- as.numeric(st_area(st_convex_hull(st_union(planned)))) / 1e6
# the same, if the drop_first nodes are given up
planned_less_drop <- planned |> filter(status != "drop_first")
mcp_less_drop_km2 <- as.numeric(st_area(st_convex_hull(st_union(planned_less_drop)))) / 1e6

## how far apart the two published tower positions are
tower_ozflux_utm <- st_sfc(st_point(c(146.189138, -19.887285)), crs = 4326) |>
  st_transform(crs_utm) |>
  st_coordinates() |>
  as.vector()
tower_offset_m <- sqrt(sum((tower_ozflux_utm - tower_utm)^2))

# show the design in the console
print(st_drop_geometry(points) |> select(point_id, grid_i, grid_j, status, dist_m, bearing),
      digits = 4)
print(table(points$status))


#
##
### Check the reproduction against the v1 chat session ----

if (check_against_v1) {
  ## counts per status
  n_status <- table(factor(points$status, levels = names(status_colours)))
  ## the v1 values and how close a reproduction has to be
  checks <- data.frame(
    quantity = c("m per px", "n nodes", "n footprint", "n core", "n drop_first", "n reserve",
                 "MCP planned (km2)", "MCP less drop_first (km2)",
                 "extent W (km)", "extent E (km)", "extent N (km)", "extent S (km)"),
    expected = c(8.36, 34, 7, 20, 2, 5, 19.5, 19.5, 3.9, 3.7, 3.6, 1.5),
    got = c(m_per_px, nrow(points), as.vector(n_status),
            mcp_planned_km2, mcp_less_drop_km2, extent_km),
    # v1 quoted these to the last digit shown
    tolerance = c(0.005, 0, 0, 0, 0, 0, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05)
  ) # end checks table
  # a check passes when the difference is within its tolerance
  checks$pass <- abs(checks$got - checks$expected) <= checks$tolerance
  print(checks, digits = 4)

  ## the drop_first offsets must still be the nodes v1 called FV03 and FV14
  drop_ids <- sort(points$point_id[points$status == "drop_first"])
  message("drop_first nodes: ", paste(drop_ids, collapse = ", "), " (v1: FV03, FV14)")

  ## hard stop if the reproduction drifts, so outputs are never written from a mismatch
  if (!all(checks$pass) || !identical(drop_ids, c("FV03", "FV14"))) {
    stop("02_design_grid.R does not reproduce the v1 design (see table above).\n",
         "Check the boundary, scale and rules, or set check_against_v1 <- FALSE if the design changed on purpose.")
  } # end reproduction check

  ### Point-by-point check against the v1 CSV, when it is available
  ## the v1 CSV is not in the repo; drop it into data/raw/ to run this
  v1_csv <- file.path(campaign_dir, "data", "raw", "fletcherview_planned_points_v1.csv")
  if (file.exists(v1_csv)) {
    # read the v1 points
    v1 <- read_csv(v1_csv, show_col_types = FALSE)
    # line them up with this run's points by ID
    cmp <- inner_join(st_drop_geometry(points) |> select(point_id, status, lat, lon),
                      v1 |> select(point_id, status_v1 = status, lat_v1 = lat, lon_v1 = lon),
                      by = "point_id")
    # distance between each pair of positions, in metres
    cmp$offset_m <- as.numeric(st_distance(
      st_as_sf(cmp, coords = c("lon", "lat"), crs = 4326),
      st_as_sf(cmp, coords = c("lon_v1", "lat_v1"), crs = 4326),
      by_element = TRUE))
    message(sprintf("v1 CSV: %d of %d IDs matched; %d status mismatches; max position offset %.2f m",
                    nrow(cmp), nrow(v1), sum(cmp$status != cmp$status_v1), max(cmp$offset_m)))
    # every ID, status and position (to ~1 m) must agree
    if (nrow(cmp) != nrow(points) || nrow(v1) != nrow(points) ||
        any(cmp$status != cmp$status_v1) || max(cmp$offset_m) > 1) {
      stop("02_design_grid.R does not match ", basename(v1_csv), " point by point.\n",
           "Inspect `cmp` to see which points differ.")
    } # end point-by-point check
  } else {
    # say so rather than silently skipping
    message("No v1 CSV at ", v1_csv, "; point-by-point check skipped.")
  } # end v1 CSV condition
} # end v1 check condition


#
##
### Write the GeoPackage, KML and CSV ----

# make sure the output folder exists
dir.create(file.path(campaign_dir, "outputs"), showWarnings = FALSE)
# every output shares this stem
stem <- file.path(campaign_dir, "outputs", paste0("fletcherview_design_", design_version))

## the points layer, in WGS84, with the columns field staff need
points_out <- points |>
  # field-ready columns only
  select(point_id, status, grid_i, grid_j, dist_m, bearing, lat, lon) |>
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
gpkg <- paste0(stem, ".gpkg")
unlink(gpkg)
# the planned camera points
st_write(points_out, gpkg, layer = "planned_points", quiet = TRUE)
# the approximate boundary, caveat included as attributes
st_write(st_transform(boundary, 4326), gpkg, layer = "boundary_approx", quiet = TRUE)
# and the empty deployments layer
st_write(deployments, gpkg, layer = "deployments", quiet = TRUE)

## KML for Google Earth and phones, one folder per status plus the tower
tower_sf <- st_sf(
  name = "Flux tower",
  description = sprintf("Fletcherview OzFlux tower (AU-Fle), %.6f, %.6f. Tower 25 m, canopy 12 m.",
                        tower_lat, tower_lon),
  geometry = st_sfc(st_point(c(tower_lon, tower_lat)), crs = 4326)
) # end tower placemark
kml_path <- write_kml_points(points_out, paste0(stem, ".kml"),
                             status_colours = status_colours,
                             description_cols = c("status", "dist_m", "bearing", "lat", "lon"),
                             boundary = boundary, boundary_name = "Property boundary (approximate)",
                             boundary_description = boundary$note,
                             extra_points = tower_sf, extra_folder = "Flux tower",
                             doc_name = paste("Fletcherview camera design", design_version))

## CSV of points for printing and spreadsheets
points_out |>
  # drop the geometry, keep the columns v1 published
  st_drop_geometry() |>
  select(point_id, status, dist_m, bearing, lat, lon) |>
  # full precision on coordinates
  mutate(lat = round(lat, 7), lon = round(lon, 7)) |>
  write_csv(file.path(campaign_dir, "outputs",
                      paste0("fletcherview_planned_points_", design_version, ".csv")))


#
##
### Draw the preview over the screenshot ----

## read the screenshot as an RGB array scaled to 0-1
screenshot_path <- file.path(campaign_dir, "data", "raw", "propertyScreenshot.png")
if (file.exists(screenshot_path)) {
  ## terra reads PNGs; it is called with terra:: rather than loaded, because
  ## loading it would mask dplyr's select()
  # it warns that the image has no map extent, which is expected
  img <- suppressWarnings(terra::rast(screenshot_path))
  # keep red, green and blue (drop alpha if present) as a rows x cols x 3 array
  img_array <- terra::as.array(img)[, , 1:3] / 255

  ## where the image's edges fall in UTM, using the same anchor and scale
  img_corners <- pixel_to_map(c(0, ncol(img)), c(nrow(img), 0),
                              anchor_px = tower_px, anchor_map = tower_utm, scale = m_per_px)

  ## the footprint wedge, built in map coordinates so north is up
  # bearings along the arc, one per degree
  arc <- seq(footprint_bearing[1], footprint_bearing[2], by = 1) * pi / 180
  wedge <- data.frame(
    # start at the tower, sweep the arc clockwise, return to the tower
    x = c(tower_utm[1], tower_utm[1] + footprint_max_dist_m * sin(arc), tower_utm[1]),
    y = c(tower_utm[2], tower_utm[2] + footprint_max_dist_m * cos(arc), tower_utm[2])
  ) # end wedge

  ## plain data frames for ggplot, all in UTM metres
  pts_df <- st_drop_geometry(points) |>
    # keep status in the legend order
    mutate(status = factor(status, levels = names(status_colours)))
  boundary_df <- rbind(boundary_xy, boundary_xy[1, ])

  ## build the preview
  p <- ggplot() +
    # the screenshot, stretched to its georeferenced corners
    annotation_raster(img_array, xmin = img_corners$x[1], xmax = img_corners$x[2],
                      ymin = img_corners$y[1], ymax = img_corners$y[2]) +
    # the footprint wedge, lightly shaded
    geom_polygon(data = wedge, aes(x, y), fill = "#E41A1C", alpha = 0.18,
                 colour = "#E41A1C", linewidth = 0.4, linetype = "dashed") +
    # the traced boundary
    geom_path(data = boundary_df, aes(x, y), colour = "white", linewidth = 0.6, linetype = "dotted") +
    # planned points as filled circles
    geom_point(data = filter(pts_df, status != "reserve"),
               aes(x, y, fill = status), shape = 21, size = 3.2, colour = "black", stroke = 0.4) +
    # reserve points as grey crosses, over a black cross so they show on pale ground
    geom_point(data = filter(pts_df, status == "reserve"),
               aes(x, y), shape = 4, size = 3.4, stroke = 2.2, colour = "black") +
    geom_point(data = filter(pts_df, status == "reserve"),
               aes(x, y, colour = status), shape = 4, size = 3, stroke = 1.2) +
    # point IDs just above each point
    geom_text(data = pts_df, aes(x, y, label = point_id), colour = "white",
              size = 2.6, nudge_y = 140, fontface = "bold") +
    # the tower
    annotate("point", x = tower_utm[1], y = tower_utm[2], shape = 24, size = 3.5,
             fill = "#1F78B4", colour = "white") +
    # status colours, shared by fill and colour
    # planned statuses in the fill legend, reserve alone in the colour legend below it
    scale_fill_manual(values = status_colours, breaks = c("footprint", "core", "drop_first"),
                      name = "Status") +
    scale_colour_manual(values = status_colours, name = NULL) +
    # equal metres on both axes, cropped to the screenshot
    coord_equal(xlim = img_corners$x, ylim = img_corners$y, expand = FALSE) +
    # labels
    labs(title = paste("Fletcherview camera design", design_version),
         subtitle = sprintf(paste0("%d m grid from the flux tower (blue triangle); shaded wedge = ",
                                   "footprint, %g-%g° within %g km. Boundary approximate."),
                            grid_spacing_m, footprint_bearing[1], footprint_bearing[2],
                            footprint_max_dist_m / 1000),
         x = "Easting (m, UTM 55S)", y = "Northing (m, UTM 55S)") +
    theme_minimal(base_size = 10) +
    theme(legend.position = "right")

  ggsave(paste0(stem, "_preview.png"), p, width = 10, height = 7.2, dpi = 200, bg = "white")
} else {
  # the preview is optional; the design does not depend on the image
  message("No screenshot at ", screenshot_path, "; preview skipped.")
} # end screenshot condition


#
##
### Write the summary table ----

## every number the README quotes, one row each
n_status <- table(factor(points$status, levels = names(status_colours)))
summary_table <- data.frame(
  quantity = c("m_per_px", "boundary_area_ha", "n_nodes",
               paste0("n_", names(n_status)), "n_planned",
               "mcp_planned_km2", "mcp_less_drop_first_km2",
               "extent_west_km", "extent_east_km", "extent_north_km", "extent_south_km",
               "tower_offset_to_ozflux_m"),
  value = c(round(m_per_px, 3), round(as.numeric(st_area(boundary)) / 1e4),
            nrow(points), as.vector(n_status), nrow(planned),
            round(mcp_planned_km2, 2), round(mcp_less_drop_km2, 2),
            round(extent_km, 2), round(tower_offset_m, 1))
) # end summary table
write_csv(summary_table, file.path(campaign_dir, "outputs",
                                   paste0("design_summary_", design_version, ".csv")))

message("Design outputs written to ", file.path(campaign_dir, "outputs"))
