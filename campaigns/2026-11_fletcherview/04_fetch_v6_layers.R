### Fetch and cache the public layers behind the v6 hectare design
## 25 November 2026, Fletcherview Research Station, QLD
# Zachary Amir

### Downloads, once, everything 05_design_hectares.R needs from the internet:
## the cadastral property boundary, OpenStreetMap and Queensland roads, Queensland
## regional ecosystems, Esri World Imagery, and the collaborator's v5 points read from
## their Word document. Everything is cached in data/processed/, so rerun this only if
## the property, the tracks or the area change. Settings live in v6_site_config.R.


## Load libraries
library(tidyverse) # For basic data wrangling
library(sf)        # For everything spatial
library(here)      # For project-relative paths so this runs on any machine

## Load the site settings and the shared helpers this script uses
source(here("campaigns", "2026-11_fletcherview", "v6_site_config.R"))
source(here("R", "fetch_arcgis_features.R"))
source(here("R", "fetch_osm_roads.R"))
source(here("R", "read_docx_table.R"))
source(here("R", "fetch_esri_imagery.R"))

# where the cached layers go (data/processed/*.gpkg and *.tif are kept off GitHub)
cache_gpkg <- file.path(campaign_dir, "data", "processed", "v6_layers.gpkg")
cache_imagery <- file.path(campaign_dir, "data", "processed", "esri_imagery.tif")


#
##
### Property boundary from the cadastre ----

# grab every polygon of the lot on plan
parcel <- fetch_arcgis_features(cadastre_service, cadastre_layer,
                                where = sprintf("lotplan = '%s'", lotplan),
                                out_fields = "lot,plan,lotplan,lot_area,tenure,acc_code",
                                crs = crs_utm)
# if the cadastre returned nothing,
if (nrow(parcel) == 0) {
  # stop because every later step needs the boundary
  stop("No cadastral parcel found for lotplan ", lotplan, ".\n",
       "Check the lot on plan in Queensland Globe, or fall back to the traced boundary.")
} # end parcel check

## merge the parcel's parts into one boundary, keeping the legal area for comparison
boundary <- parcel |>
  # fix any self-touching rings the service sends
  st_make_valid() |>
  # one feature for the whole lot
  group_by(lotplan) |>
  # keep the registered area and positional accuracy alongside
  summarise(lot_area_ha = first(lot_area) / 1e4, acc_code = first(acc_code),
            n_parts = n(), .groups = "drop")
# and its mapped area, which differs from the registered area by the mapping accuracy
boundary$mapped_area_ha <- as.numeric(st_area(boundary)) / 1e4
# view the two areas, expecting them within a few percent
message(sprintf("Lot %s: %d part(s), %.1f ha mapped vs %.1f ha registered",
                lotplan, boundary$n_parts, boundary$mapped_area_ha, boundary$lot_area_ha))

## the box used for every other download: the property plus a margin, in lon/lat
fetch_box <- boundary |>
  # widen the property
  st_buffer(fetch_margin_m) |>
  # back to lon/lat for the web services
  st_transform(4326) |>
  # as xmin, ymin, xmax, ymax
  st_bbox() |>
  as.numeric()


#
##
### Tracks from OpenStreetMap and the Queensland roads layer ----

# grab OSM roads and tracks, saving the raw download to a temporary file
osm_roads <- fetch_osm_roads(fetch_box, tempfile(fileext = ".osm"), crs = crs_utm)
# how many OSM ways of each kind are there?
message("OSM highway ways in the box: ", paste(names(table(osm_roads$highway)),
                                               table(osm_roads$highway), collapse = ", "))

# grab Queensland roads and tracks in the same box
qld_roads <- fetch_arcgis_features(qld_roads_service, qld_roads_layer, bbox = fetch_box,
                                   out_fields = "road_name_full,class,surface_type",
                                   crs = crs_utm) |>
  # match the OSM columns so the two can be stacked
  transmute(osm_id = NA_character_, name = road_name_full, highway = class, source = "QLD")


#
##
### The collaborator's v5 points ----

# read the provisional field register from the Word document
v5_raw <- read_docx_table(v5_docx_path, table = v5_table_number)
# view the columns, expecting FV ID, Latitude, Longitude, Move and Access
names(v5_raw)

## tidy into points
v5_points <- v5_raw |>
  # give the columns short names
  transmute(point_id = `FV ID`, lat = as.numeric(Latitude), lon = as.numeric(Longitude),
            move_m = as.numeric(`Move (m, approx.)`), access = Access) |>
  # make them points in lon/lat
  st_as_sf(coords = c("lon", "lat"), crs = 4326, remove = FALSE) |>
  # and move them into UTM
  st_transform(crs_utm)
# if the table did not give 30 points with coordinates,
if (nrow(v5_points) != 30 || anyNA(v5_points$lat) || anyNA(v5_points$lon)) {
  # stop because the document has changed from the one this was written for
  stop(sprintf("Read %d v5 points (%d missing a coordinate); expected 30 complete.",
               nrow(v5_points), sum(is.na(v5_points$lat) | is.na(v5_points$lon))),
       "\nOpen the docx and check the register table is table ", v5_table_number, ".")
} # end v5 check


#
##
### Regional ecosystems, for interpretation ----

# the box as a polygon, to trim the large RE polygons
box_poly <- st_as_sfc(st_bbox(c(xmin = fetch_box[1], ymin = fetch_box[2],
                                xmax = fetch_box[3], ymax = fetch_box[4]), crs = st_crs(4326))) |>
  st_transform(crs_utm)
# init a list to hold each RE layer
re_list <- list()
# for each RE layer (pre-clearing and remnant),
for (lab in names(re_layers)) {
  # grab its polygons touching the box
  re <- fetch_arcgis_features(re_service, re_layers[[lab]], bbox = fetch_box, crs = crs_utm)
  # trim them to the box, fixing invalid rings first
  re <- suppressWarnings(st_intersection(st_make_valid(re), box_poly))
  # note which layer they came from
  re$re_layer <- lab
  # store it
  re_list[[lab]] <- re
  # view the RE mapping version the service carries
  message(lab, ": ", nrow(re), " polygons, RE version ", paste(unique(re$version), collapse = "/"))
} # end per RE layer


#
##
### Esri World Imagery for the PDF backdrop ----

# download and cache the imagery over the property plus margin
fetch_esri_imagery(st_buffer(boundary, fetch_margin_m / 2), cache_imagery, zoom = imagery_zoom)


#
##
### Cache everything ----

## start the cache fresh so stale layers never linger
unlink(cache_gpkg)
# each layer, named as 05_design_hectares.R reads it
cache_layers <- list(
  boundary = boundary,
  tracks_osm = osm_roads,
  tracks_qld = qld_roads,
  v5_points = v5_points,
  re_preclear = re_list[["re_preclear"]],
  re_remnant = re_list[["re_remnant"]]
) # end layer list
# write them one at a time into the same file
for (lyr in names(cache_layers)) {
  st_write(cache_layers[[lyr]], cache_gpkg, layer = lyr, quiet = TRUE)
} # end per layer
message("Cached layers in ", cache_gpkg, " and imagery in ", cache_imagery)
