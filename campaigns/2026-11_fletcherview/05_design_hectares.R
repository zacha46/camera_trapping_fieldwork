### Choose the stratified hectare design and compare it with the v4 and v5 grids
## 25 November 2026, Fletcherview Research Station, QLD
# Zachary Amir

### Stratified hectares instead of a grid:
## The property is split into NVIS vegetation subgroups; every subgroup covering at least
## 1 km2 is a stratum and gets two 1 ha plots (100 x 100 m). The TERN core plot and one
## hectare on each wet-season Australian Acoustic Observatory (A2O) recorder are fixed
## hectares and count towards their subgroup. Every other hectare is crossed by a track,
## as pure in its subgroup as possible, and about 1 km from its replicate. Cameras within
## a hectare are placed in the field on features; this script gives only nominal
## edge-midpoint guides.

### Inputs and outputs:
## Reads the layers cached by 04_fetch_v6_layers.R, the A2O recorder GPS fixes, the v4
## QField GeoPackage and the v6 GeoPackage. Writes to outputs/, each name carrying the
## design version: a GeoPackage, a PDF, a QField folder, a hectare points CSV, and the
## tracked summary tables quoted by the campaign README. Settings live in
## v6_site_config.R.


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

## the A2O recorders and the station, from the handheld GPS fixes
# if the GPS file is missing,
if (!file.exists(a2o_gps_path)) {
  # stop because the A2O hectares are placed on these fixes
  stop("No A2O GPS file at ", a2o_gps_path, "\n",
       "Put GPS_fletcher_values.csv in data/raw/ (see data/raw/README.md).")
} # end GPS file check
gps_fixes <- read.csv(a2o_gps_path) |>
  # turn the fixes into points
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326) |>
  # in UTM, so distances are in metres
  st_transform(crs_utm)
a2o_recorders <- gps_fixes |>
  # keep the acoustic recorders only
  filter(point_type == "sensor") |>
  # name each one and flag those that anchor a hectare
  transmute(name = title, anchors_hectare = title %in% a2o_anchor_titles)
# grab the station buildings, to measure how far the v6 A2O point sat from them
station <- st_geometry(gps_fixes[gps_fixes$point_type == "station", ])
# if any anchoring recorder named in the config is not in the GPS file,
if (sum(a2o_recorders$anchors_hectare) != length(a2o_anchor_titles)) {
  # stop because a hectare would silently go missing
  stop(sprintf("Found %d of the %d A2O recorders named in a2o_anchor_titles.",
               sum(a2o_recorders$anchors_hectare), length(a2o_anchor_titles)),
       "\nCheck the titles in v6_site_config.R against the 'title' column of ", a2o_gps_path)
} # end recorder check


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
### Place the fixed hectares: TERN core plot and A2O recorders ----

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
# what the core hectare is anchored on
core$anchor <- "TERN core plot"

## one A2O hectare per anchoring recorder, each in that recorder's own subgroup
a2o_anchors <- a2o_recorders[a2o_recorders$anchors_hectare, ]
# grab the subgroup under each recorder
a2o_anchors$mvs_code <- st_join(a2o_anchors[, "name"], nvis[, "mvs_code"])$mvs_code
# if any recorder's subgroup is not a stratum,
if (any(!a2o_anchors$mvs_code %in% strata)) {
  # warn, because its hectare is placed anyway but will not stand in for a stratum
  warning("An A2O recorder falls in a subgroup that is not a stratum (",
          paste(a2o_anchors$mvs_code[!a2o_anchors$mvs_code %in% strata], collapse = ", "),
          "); its hectare is placed but does not replace a stratum replicate.")
} # end A2O stratum check
# init a list to hold the A2O hectares
a2o_list <- list()
# for each anchoring recorder,
for (i in seq_len(nrow(a2o_anchors))) {
  # slide a square around it, preferring one crossed by a track
  a2o_list[[i]] <- anchor_hectare(st_geometry(a2o_anchors)[i], boundary, nvis, tracks,
                                  a2o_anchors$mvs_code[i], hectare_size_m)
  # name it after the recorder's letter, so "Acoustic wet A" gives A2O-A
  a2o_list[[i]]$hectare_id <- paste0("A2O-", sub(".*\\s", "", a2o_anchors$name[i]))
  # and record which recorder it holds
  a2o_list[[i]]$anchor <- a2o_anchors$name[i]
} # end per recorder
# stack them into one layer
a2o_hect <- do.call(rbind, a2o_list)

## the fixed hectares together
fixed <- rbind(core[, c("hectare_id", "mvs_code", "purity", "anchor")],
               a2o_hect[, c("hectare_id", "mvs_code", "purity", "anchor")])
# if any two fixed hectares touch or overlap,
if (any(lengths(st_intersects(fixed)) > 1)) {
  # stop because two fixed plots would sample the same ground
  stop("Two fixed hectares overlap: ", paste(fixed$hectare_id, collapse = ", "), ".\n",
       "Check the A2O recorder fixes and the core plot placement in v6_site_config.R.")
} # end overlap check
# view them, expecting CORE and A2O-A in subgroup 19 and A2O-B in subgroup 9
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
  # they are chosen by the rules, not anchored on anything
  picks$anchor <- NA_character_
  # add them to the design
  hectares <- rbind(hectares, picks[, c("hectare_id", "mvs_code", "purity", "anchor")])
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
# the placement guidance every hectare's note ends with
shared_guidance <- paste0("1 camera on-track, rest off-track; dense tussock (hare-wallaby); ",
                          "rock, logs, termite mounds with a low camera (reptiles).")
hectares$field_note <- paste0(
  # the hectare-specific part
  case_when(
    hectares$hectare_id == "CORE" & core_plot_is_placeholder ~
      "Placeholder square: lay out on the TERN plot pegs. ",
    grepl("^A2O-", hectares$hectare_id) & hectares$dist_track_m > 0 ~
      paste0("Contains A2O recorder '", hectares$anchor,
             "'. No mapped track: walk in on the A2O servicing route. "),
    grepl("^A2O-", hectares$hectare_id) ~
      paste0("Contains A2O recorder '", hectares$anchor, "'. "),
    grepl("v5_point_proxy", hectares$track_source) & hectares$dist_track_m == 0 ~
      "Track inferred from a v5 point: confirm it is drivable. ",
    TRUE ~ ""),
  # a warning where the hectare is mixed
  ifelse(hectares$purity < min_purity, "Mixed vegetation: check the subgroup. ", ""),
  # the shared guidance
  shared_guidance)

# view the design
st_drop_geometry(hectares) |>
  select(rank, hectare_id, mvs_code, purity, cameras, dist_tower_m, dist_track_m, dist_replicate_m)


#
##
### Plan backups for the hectares beyond the creek ----

## cut the property along the creek
# if the hydrography cache is missing,
if (!file.exists(hydro_cache)) {
  # stop because the creek cannot be found without it
  stop("No cached hydrography at ", hydro_cache, "\nRun 02_water_and_basemap.R first.")
} # end hydrography check
hydro <- st_read(hydro_cache, quiet = TRUE)
# grab the creek's mapped lines
barrier <- hydro[hydro$layer == "watercourse_line" & hydro$name %in% access_barrier_name, ]
# if the creek is not in the hydrography,
if (nrow(barrier) == 0) {
  # stop because no hectare could be judged beyond it
  stop("No watercourse line named '", access_barrier_name, "' in ", hydro_cache, ".\n",
       "Check access_barrier_name in v6_site_config.R against the hydrography names.")
} # end barrier check
# cut a 2 m gap along the creek so the property falls apart into pieces
pieces <- st_cast(st_difference(st_union(boundary), st_union(st_buffer(st_geometry(barrier), 2))),
                  "POLYGON")
# find which parcel part each piece came from
parcel_parts <- st_cast(st_union(boundary), "POLYGON")
part_of <- vapply(st_intersects(pieces, parcel_parts), function(x) x[1], integer(1))

## the reachable side: in each parcel part, the piece nearest the tower
# distance from the tower to each piece
d_piece <- as.numeric(st_distance(pieces, tower))
# keep a piece if no other piece of its part is nearer the tower (uncut parts stay whole)
reachable_piece <- vapply(seq_along(pieces), function(i) {
  d_piece[i] == min(d_piece[part_of == part_of[i]])
}, logical(1))
reachable_area <- st_sf(geometry = st_union(pieces[reachable_piece]))

## which hectares lie beyond the creek?
hectares$beyond_barrier <- lengths(st_within(hectares, reachable_area)) == 0
at_risk <- hectares$hectare_id[hectares$beyond_barrier]
# view them, expecting MVS09-B, MVS37-A and MVS37-B
message("Beyond ", access_barrier_name, ": ", paste(at_risk, collapse = ", "))
# if the backup plan names a hectare that is not beyond the creek,
if (!all(backup_plan$replaces %in% at_risk)) {
  # stop because the plan no longer matches the design
  stop("backup_plan replaces ",
       paste(setdiff(backup_plan$replaces, at_risk), collapse = ", "),
       ", which is not beyond ", access_barrier_name, ".\n",
       "Update backup_plan in v6_site_config.R to name the hectares listed above.")
} # end plan check
# if a hectare beyond the creek has no backup,
if (!all(at_risk %in% backup_plan$replaces)) {
  # warn, because it is left without one
  warning("No backup planned for ", paste(setdiff(at_risk, backup_plan$replaces), collapse = ", "),
          " beyond ", access_barrier_name, ".")
} # end coverage check

## pick each backup on the reachable side, one at a time, in plan order
# backups sit on a v5 point, the collaborator's interpreted tracks (ZDA)
backup_tracks <- tracks[tracks$source == "v5_point_proxy", ]
# start from the hectares that stay reachable; at-risk hectares are not deployed in this case
placed <- hectares[!hectares$beyond_barrier, "mvs_code"]
# init a list to hold the backups
backup_list <- list()
# for each backup in the plan,
for (i in seq_len(nrow(backup_plan))) {
  # choose one square of its subgroup, about 1 km from the nearest reachable replicate
  pick <- select_hectares(reachable_area, nvis, backup_tracks, backup_plan$mvs_code[i], 1,
                          origin = tower, existing = placed, size_m = hectare_size_m,
                          lattice_m = lattice_m, min_purity = min_purity,
                          target_spacing_m = target_spacing_m,
                          require_track = backup_plan$needs_track[i])
  # grab the IDs already used in this subgroup, main and backup
  prefix <- sprintf("MVS%02d-", backup_plan$mvs_code[i])
  used <- c(hectares$hectare_id, vapply(backup_list, function(x) x$hectare_id, character(1)))
  used <- used[startsWith(used, prefix)]
  # find the highest letter taken (0 if none)
  last <- max(c(0, match(substring(used, nchar(prefix) + 1), LETTERS)))
  # name it with the letter after that, e.g. MVS09-C after MVS09-B
  pick$hectare_id <- paste0(prefix, LETTERS[last + 1])
  # record which hectare it replaces
  pick$replaces <- backup_plan$replaces[i]
  # keep it
  backup_list[[i]] <- pick[, c("hectare_id", "mvs_code", "purity", "replaces")]
  # and count it as placed, so later backups keep their distance and never overlap it
  placed <- rbind(placed, pick[, "mvs_code"])
} # end per backup
# stack the backups into one layer
backups <- do.call(rbind, backup_list)

### Describe each backup:
## as for the main hectares, but with no rank: a backup takes its hectare's place
backups <- left_join(backups, mvs_names, by = "mvs_code")
# same camera count as the hectare it replaces
backups$cameras <- cameras_per_hectare
# centre latitude and longitude, 5 decimal places
backup_centres <- st_centroid(st_geometry(backups))
backup_ll <- st_coordinates(st_transform(backup_centres, 4326))
backups$centre_lat <- round(backup_ll[, "Y"], 5)
backups$centre_lon <- round(backup_ll[, "X"], 5)
# distance from the tower
backups$dist_tower_m <- as.numeric(st_distance(backup_centres, tower))
# distances to every track feature, and the nearest (0 m when one crosses it)
d_track_b <- matrix(as.numeric(st_distance(backups, tracks)), nrow = nrow(backups))
backups$dist_track_m <- round(apply(d_track_b, 1, min))
# the source of the nearest track feature, e.g. "v5_point_proxy (FV32)"
nearest_b <- apply(d_track_b, 1, which.min)
backups$track_source <- sprintf("%s (%s)", tracks$source[nearest_b], tracks$name[nearest_b])
# distance to the nearest reachable hectare or backup of the same subgroup
backups$dist_replicate_m <- vapply(seq_len(nrow(backups)), function(i) {
  # the others in this subgroup, excluding the at-risk hectares and this backup itself
  others <- rbind(hectares[!hectares$beyond_barrier, "mvs_code"], backups[-i, "mvs_code"])
  others <- others[others$mvs_code == backups$mvs_code[i], ]
  if (nrow(others) == 0) NA_real_ else
    round(min(as.numeric(st_distance(backup_centres[i], st_centroid(st_geometry(others))))))
}, numeric(1))
# the field note: when to use it, access, a subgroup check, then the shared guidance
backups$field_note <- paste0(
  # when to use it
  "Backup for ", backups$replaces, " if ", access_barrier_name, " cannot be crossed. ",
  # how to reach it
  ifelse(backups$dist_track_m > 0, "No track crosses it: confirm access. ",
         "Track inferred from a v5 point: confirm it is drivable. "),
  # NVIS is coarse, so the subgroup always needs checking on a backup
  "Confirm the subgroup on the ground. ",
  shared_guidance)
# view the backups
st_drop_geometry(backups) |>
  select(hectare_id, replaces, mvs_code, purity, dist_tower_m, dist_track_m, dist_replicate_m)

## tell the main hectares beyond the creek which backup stands in for them
# match each at-risk hectare to its backup
backup_for <- backups$hectare_id[match(hectares$hectare_id, backups$replaces)]
# and put that first in their field note
hectares$field_note <- ifelse(
  is.na(backup_for), hectares$field_note,
  paste0("Beyond ", access_barrier_name, ": if it cannot be crossed, use ", backup_for, ". ",
         hectares$field_note))


#
##
### Mark the camera guide points ----

# edge midpoints, the one nearest a track flagged on-track
guides <- hectare_camera_guides(hectares, tracks, "hectare_id", cameras_per_hectare)
guides$status <- "main"
# and the same for the backups
backup_guides <- hectare_camera_guides(backups, tracks, "hectare_id", cameras_per_hectare)
backup_guides$status <- "backup"
# one guide layer for both
guides <- rbind(guides, backup_guides)
# their latitude and longitude for the field
guide_ll <- st_coordinates(st_transform(guides, 4326))
guides$lat <- round(guide_ll[, "Y"], 5)
guides$lon <- round(guide_ll[, "X"], 5)


#
##
### Compare v4, v5 and this design by subgroup ----

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

## count sites (and this design's cameras) per subgroup, with a row for sites off the property
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
  # this design's hectares, and the cameras in them (renamed to the version when written)
  this_hectares = count_by(hectares$mvs_code),
  this_cameras = count_by(hectares$mvs_code, hectares$cameras)
) # end comparison table
# shares of sampled sites (this design's sites are hectares)
comparison$v4_site_pct <- round(100 * comparison$v4_cameras / sum(comparison$v4_cameras), 1)
comparison$v5_site_pct <- round(100 * comparison$v5_cameras / sum(comparison$v5_cameras), 1)
comparison$this_site_pct <- round(100 * comparison$this_hectares / sum(comparison$this_hectares), 1)
# drop the off-parcel row if nothing falls there
comparison <- comparison[!(is.na(comparison$mvs_code) & comparison$v4_cameras == 0 &
                             comparison$v5_cameras == 0 & comparison$this_hectares == 0), ]
# view it
comparison

## area covered by each design: minimum convex polygon (MCP), km2
mcp_km2 <- function(g) round(as.numeric(st_area(st_convex_hull(st_union(g)))) / 1e6, 2)
mcp <- data.frame(design = c("v4 grid (30 cameras)", "v5 relocated points",
                             paste(design_version, "hectares")),
                  sites = c(nrow(v4_sites), nrow(v5_points), nrow(hectares)),
                  cameras = c(nrow(v4_sites), nrow(v5_points), sum(hectares$cameras)),
                  mcp_km2 = c(mcp_km2(v4_sites), mcp_km2(v5_points), mcp_km2(hectares)))
mcp


#
##
### Write the tracked summary tables ----

## subgroup areas on the property, and on the side of the creek reachable in the wet
# cut the subgroups to the reachable side
nvis_reach <- suppressWarnings(st_intersection(nvis[, "mvs_code"], st_geometry(reachable_area)))
# their area, km2, matched back to every subgroup (0 where none is reachable)
reach_km2 <- tapply(as.numeric(st_area(nvis_reach)) / 1e6, nvis_reach$mvs_code, sum)
nvis$reachable_km2 <- ifelse(is.na(reach_km2[as.character(nvis$mvs_code)]), 0,
                             reach_km2[as.character(nvis$mvs_code)])
write.csv(st_drop_geometry(nvis) |>
            mutate(area_km2 = round(area_km2, 3), area_pct = round(100 * area_share, 1),
                   reachable_km2 = round(reachable_km2, 3)) |>
            select(mvs_code, mvs_name, area_km2, area_pct, eligible, reachable_km2),
          file.path(out_dir, sprintf("nvis_areas_%s.csv", design_version)), row.names = FALSE)

## the comparison of designs, with this design's columns named after its version
comparison_out <- comparison
names(comparison_out) <- sub("^this_", paste0(design_version, "_"), names(comparison_out))
write.csv(comparison_out, file.path(out_dir, sprintf("design_comparison_%s.csv", design_version)),
          row.names = FALSE)
# and the MCPs in their own file
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

## the backups without coordinates, with the hectare each replaces
backup_table <- st_drop_geometry(backups) |>
  transmute(hectare_id, replaces, mvs_code, subgroup = mvs_name, purity_pct = round(100 * purity),
            cameras, dist_tower_m = round(dist_tower_m), dist_track_m, track_source,
            dist_replicate_m)
write.csv(backup_table, file.path(out_dir, sprintf("backup_hectares_%s.csv", design_version)),
          row.names = FALSE)

## how far the v6 A2O point sat from the station and from the recorders now used
# if the v6 GeoPackage is missing,
if (!file.exists(v6_gpkg_path)) {
  # stop because the v6 A2O point cannot be compared
  stop("No v6 GeoPackage at ", v6_gpkg_path, "\n",
       "Restore outputs/OLD/fletcherview_v6.gpkg from git, or fix v6_gpkg_path in v6_site_config.R.")
} # end v6 file check
# read the single A2O point the v6 design was built on
v6_a2o <- st_read(v6_gpkg_path, layer = "a2o_site", quiet = TRUE) |> st_transform(crs_utm)
# its distance to the station buildings
v6_a2o_to_station_m <- round(min(as.numeric(st_distance(v6_a2o, station))))
# and to the nearest anchoring recorder
v6_a2o_to_anchor_m <- round(min(as.numeric(st_distance(v6_a2o, a2o_anchors))))

## every other quotable number
summary_tab <- data.frame(quantity = c(
  "parcel_mapped_ha", "parcel_registered_ha", "parcel_parts", "nvis_subgroups_on_parcel",
  "n_strata", "n_hectares", "cameras_per_hectare", "cameras_used", "cameras_spare",
  "core_plot_placeholder", "a2o_hectares", "a2o_subgroups", "a2o_hectares_crossed_by_track",
  "a2o_min_dist_track_m", "v6_a2o_point_to_station_m", "v6_a2o_point_to_nearest_anchor_m",
  "min_purity_pct", "lowest_hectare_purity_pct", "track_km_on_parcel_osm",
  "track_km_on_parcel_qld", "v5_points_off_parcel", "v4_sites_off_parcel",
  "re_version", "tower_to_core_centre_m", "access_barrier", "reachable_ha",
  "hectares_beyond_barrier", "n_backups", "backups_crossed_by_track"),
  value = c(
    round(boundary$mapped_area_ha, 1), round(boundary$lot_area_ha, 1), boundary$n_parts,
    nrow(nvis), length(strata), n_hect, cameras_per_hectare, sum(hectares$cameras),
    camera_budget - sum(hectares$cameras), core_plot_is_placeholder, nrow(a2o_hect),
    paste(a2o_hect$mvs_code, collapse = "/"), sum(a2o_hect$crossed_by_track),
    round(min(a2o_hect$dist_track_m)), v6_a2o_to_station_m, v6_a2o_to_anchor_m,
    round(100 * min_purity), round(100 * min(hectares$purity)),
    round(sum(track_km$km[track_km$source == "OSM"]), 2),
    round(sum(track_km$km[track_km$source == "QLD"]), 2),
    sum(is.na(v5_points$mvs_code)), sum(is.na(v4_sites$mvs_code)),
    paste(unique(re_preclear$version), collapse = "/"),
    round(hectares$dist_tower_m[hectares$hectare_id == "CORE"]), access_barrier_name,
    round(as.numeric(st_area(reachable_area)) / 1e4, 1), paste(at_risk, collapse = "/"),
    nrow(backups), sum(backups$dist_track_m == 0)))
write.csv(summary_tab, file.path(out_dir, sprintf("design_summary_%s.csv", design_version)),
          row.names = FALSE)

## the field table with coordinates (kept off GitHub by the *points* rule)
write.csv(rbind(st_drop_geometry(hectares) |>
                  # the main hectares, in rank order
                  transmute(status = "main", rank, hectare_id, replaces = NA, mvs_name,
                            centre_lat, centre_lon, cameras, dist_track_m, field_note),
                st_drop_geometry(backups) |>
                  # then the backups, unranked, each naming the hectare it replaces
                  transmute(status = "backup", rank = NA, hectare_id, replaces, mvs_name,
                            centre_lat, centre_lon, cameras, dist_track_m, field_note)),
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

## this design's layer names carry its version, e.g. v7_hectares
hect_layer <- paste0(design_version, "_hectares")
guide_layer <- paste0(design_version, "_camera_guides")
backup_layer <- paste0(design_version, "_backup_hectares")
# every layer, in WGS84 as QField and Google Earth expect
gpkg_layers <- list(
  boundary = boundary,
  nvis_subgroups = nvis,
  re_polygons = re_polygons,
  tracks = tracks,
  v4_grid = v4_all,
  v5_points = v5_points,
  hectares = hectares |> mutate(map_label = sprintf("%s (%d)", hectare_id, rank)),
  camera_guides = guides,
  backup_hectares = backups |> mutate(map_label = sprintf("%s (for %s)", hectare_id, replaces)),
  access_barrier = st_sf(name = access_barrier_name, geometry = st_union(st_geometry(barrier))),
  flux_tower = st_sf(name = "Flux tower", geometry = tower),
  a2o_recorders = a2o_recorders,
  deployments = deployments
) # end layer list
# rename the hectare and guide layers to carry the version
names(gpkg_layers)[names(gpkg_layers) == "hectares"] <- hect_layer
names(gpkg_layers)[names(gpkg_layers) == "camera_guides"] <- guide_layer
names(gpkg_layers)[names(gpkg_layers) == "backup_hectares"] <- backup_layer
# the deliverable: every layer in one GeoPackage at the top of outputs/
gpkg_name <- sprintf("%s_%s.gpkg", site_name, design_version)
gpkg <- file.path(out_dir, gpkg_name)
# start fresh so stale layers never linger
unlink(gpkg)
# write each layer
for (lyr in names(gpkg_layers)) {
  st_write(st_transform(gpkg_layers[[lyr]], 4326), gpkg, layer = lyr, quiet = TRUE)
} # end per layer

### the QField copy: one small GeoPackage per layer
## QField on iOS marked some layers invalid when all of them shared one GeoPackage
## with the editable deployments layer, so each layer gets its own file here
qfield_dir <- file.path(out_dir, paste0("qfield_", design_version))
# start the folder fresh so stale files never linger
unlink(qfield_dir, recursive = TRUE)
dir.create(qfield_dir)
# the tracks file holds lines only (the v5 proxy points are in the v5 layer)
qfield_layers <- gpkg_layers
qfield_layers$tracks <- track_lines
# for each layer,
for (lyr in names(qfield_layers)) {
  # write it to its own file named after the layer
  st_write(st_transform(qfield_layers[[lyr]], 4326), file.path(qfield_dir, paste0(lyr, ".gpkg")),
           layer = lyr, quiet = TRUE)
} # end per QField layer


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
col_hect <- "#000000"
col_track <- "#FF7F00"
col_backup <- "#D95F02"
col_creek <- "#1F78B4"
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
# backup centre coordinates and labels
bxy <- st_coordinates(backup_centres)
backup_labels <- sprintf("%s (for %s)", backups$hectare_id, backups$replaces)
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
     main = sprintf("Fletcherview: v4 grid, v5 relocated points and %s hectares over NVIS subgroups",
                    design_version))
# the property boundary
plot(st_geometry(boundary), border = "grey20", lwd = 1.5, add = TRUE)
# mapped tracks
plot(st_geometry(track_lines), col = col_track, lwd = 1.5, add = TRUE)
# v4 sites with a camera
plot(st_geometry(v4_sites), pch = 4, col = col_v4, cex = 0.9, lwd = 1.5, add = TRUE)
# v5 points
plot(st_geometry(v5_points), pch = 2, col = col_v5, cex = 0.9, lwd = 1.5, add = TRUE)
# this design's hectares, outlined, with a marker so they show at this scale
plot(st_geometry(hectares), border = col_hect, lwd = 1.5, add = TRUE)
points(cxy, pch = 22, cex = 1.6, lwd = 1.5, col = col_hect)
# their labels
halo_text(cxy[, 1], cxy[, 2], hect_labels, pos = 4, offset = 0.8, cex = 0.75, font = 2)
# the creek that may close in the wet season
plot(st_geometry(barrier), col = col_creek, lwd = 2.5, add = TRUE)
# the backup hectares, dashed, with their own marker and labels
plot(st_geometry(backups), border = col_backup, lwd = 1.5, lty = 2, add = TRUE)
points(bxy, pch = 23, cex = 1.5, lwd = 1.5, col = col_backup)
halo_text(bxy[, 1], bxy[, 2], backup_labels, pos = 4, offset = 0.8, cex = 0.7, font = 3,
          col = col_backup)
# the tower
plot(tower, pch = 17, col = "navy", cex = 1.3, add = TRUE)
# and the A2O recorders
plot(st_geometry(a2o_recorders), pch = 8, col = "purple", cex = 1.2, add = TRUE)
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
       legend = c("v4 grid site (30 cameras)", "v5 relocated point",
                  paste(design_version, "hectare (rank)"), "Backup hectare (for ...)",
                  "Mapped track (OSM / QLD)", paste(access_barrier_name, "(wet-season barrier)"),
                  "Flux tower", "A2O site 61 recorder", "Cadastral parcel"),
       pch = c(4, 2, 22, 23, NA, NA, 17, 8, NA), lty = c(NA, NA, NA, NA, 1, 1, NA, NA, 1),
       col = c(col_v4, col_v5, col_hect, col_backup, col_track, col_creek, "navy", "purple",
               "grey20"),
       lwd = c(1.5, 1.5, 1.5, 1.5, 1.5, 2.5, NA, NA, 1.5))
layout(1)

### Page 2: the hectares over satellite imagery
par(mar = c(2, 1, 3, 1))
# the imagery cropped to the map box
plotRGB(img, ext = ext(map_box[c("xmin", "xmax", "ymin", "ymax")]), mar = c(2, 1, 3, 1),
        main = sprintf("%s hectares over Esri World Imagery (labels: ID (deployment rank))",
                       design_version))
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
# the creek
plot(st_geometry(barrier), col = "deepskyblue", lwd = 2, add = TRUE)
# the backups, dashed orange, and their labels
plot(st_geometry(backups), border = "orange", lwd = 2, lty = 2, add = TRUE)
halo_text(bxy[, 1], bxy[, 2], backup_labels, pos = 4, offset = 0.8, cex = 0.75, font = 3,
          col = "black", halo = "orange")
# the tower
plot(tower, pch = 17, col = "white", cex = 1.2, add = TRUE)
# the A2O recorders
plot(st_geometry(a2o_recorders), pch = 8, col = "magenta", cex = 1.1, lwd = 1.5, add = TRUE)
mtext(paste0("Imagery: Esri, Maxar, Earthstar Geographics, and the GIS User Community. Yellow: ",
             design_version, " hectares; dashed orange: backups; orange: OSM/QLD tracks; ",
             "blue: ", access_barrier_name, "; cyan triangles: v5 points (interpreted tracks); ",
             "magenta stars: A2O recorders."),
      side = 1, line = 0.5, cex = 0.65)

### Page 3: a close-up of each hectare and backup, for checking tracks by eye
## the main hectares then the backups, in one set of panels
panels <- rbind(hectares[, c("hectare_id", "mvs_code", "purity")],
                backups[, c("hectare_id", "mvs_code", "purity")])
# their centres
pxy <- rbind(cxy, bxy)
# a title for each: rank for main hectares, the replaced hectare for backups
panel_titles <- c(sprintf("%s (rank %d)", hectares$hectare_id, hectares$rank),
                  sprintf("%s (backup for %s)", backups$hectare_id, backups$replaces))
# yellow outline for main hectares, orange for backups
panel_border <- c(rep("yellow", nrow(hectares)), rep("orange", nrow(backups)))
n_panel <- nrow(panels)
par(mfrow = c(ceiling(n_panel / 3), 3))
# for each hectare,
for (i in seq_len(n_panel)) {
  # a 600 m window around its centre
  win <- ext(pxy[i, 1] - 300, pxy[i, 1] + 300, pxy[i, 2] - 300, pxy[i, 2] + 300)
  plotRGB(img, ext = win, mar = c(0.5, 0.5, 2.5, 0.5),
          main = sprintf("%s: %d%% MVS %d", panel_titles[i], round(100 * panels$purity[i]),
                         panels$mvs_code[i]))
  # tracks and v5 points nearby
  plot(st_geometry(track_lines), col = col_track, lwd = 2, add = TRUE)
  plot(st_geometry(v5_points), pch = 2, col = "cyan", cex = 1.2, lwd = 2, add = TRUE)
  # the creek, where it is in view
  plot(st_geometry(barrier), col = "deepskyblue", lwd = 2, add = TRUE)
  # the hectare
  plot(st_geometry(panels[i, ]), border = panel_border[i], lwd = 2, add = TRUE)
  # its guide points, the on-track one filled
  g <- guides[guides$hectare_id == panels$hectare_id[i], ]
  plot(st_geometry(g), pch = ifelse(g$role == "on-track", 21, 1), bg = "yellow", col = "black",
       cex = 1.3, add = TRUE)
  # A2O recorders nearby, drawn last so the guides never hide them
  plot(st_geometry(a2o_recorders), pch = 8, col = "magenta", cex = 1.4, lwd = 2, add = TRUE)
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
  title = sprintf("%s hectares: %d hectares x %d cameras = %d of %d cameras (deploy in rank order)",
                  design_version, n_hect, cameras_per_hectare, sum(hectares$cameras), camera_budget),
  footnote = paste(
    "Cameras within a hectare are not independent: place them in the field on features.",
    "Guide points (edge midpoints) are nominal starting points only. 'To track' is the gap",
    "between the hectare and the nearest track feature; 0 means a track crosses it.",
    "Rank: core plot first, then by straight-line distance from the flux tower.",
    "No drift fences or thermal cues. NVIS is mapped at ~100 m and the tracks are",
    "unverified: confirm the subgroup and access on the ground."),
  max_chars = 34)

### Page 5: the backup field table
plot_table_page(
  st_drop_geometry(backups) |>
    # give every column a readable heading for the page
    transmute(Backup = hectare_id, `For` = replaces,
              Subgroup = sprintf("%d %s", mvs_code, mvs_name),
              `Purity %` = round(100 * purity),
              `Centre lat` = sprintf("%.5f", centre_lat), `Centre long` = sprintf("%.5f", centre_lon),
              `To track (m)` = dist_track_m, Cameras = cameras, `Field note` = field_note),
  title = sprintf("Backups if %s cannot be crossed: use each in place of the hectare it is for",
                  access_barrier_name),
  footnote = paste(
    "Each backup is on the tower side of the creek, in the subgroup given in the backup plan.",
    "Backups were chosen on v5 points where one lies in that subgroup on the reachable side;",
    "where none does, the purest square was chosen and its access must be confirmed."),
  max_chars = 34)

### Page 6: the comparison of designs
comparison_page <- comparison |>
  # give every column a readable heading for the page
  transmute(Subgroup = ifelse(is.na(mvs_code), subgroup, sprintf("%d %s", mvs_code, subgroup)),
            `Area km2` = area_km2, `Area %` = area_pct, Stratum = stratum,
            `v4 cameras` = v4_cameras, `v4 sites %` = v4_site_pct,
            `v5 cameras` = v5_cameras, `v5 sites %` = v5_site_pct,
            `this hectares` = this_hectares, `this cameras` = this_cameras,
            `this sites %` = this_site_pct)
# label this design's columns with its version
names(comparison_page) <- sub("^this ", paste0(design_version, " "), names(comparison_page))
plot_table_page(
  comparison_page,
  title = sprintf("Share of sampled sites in each NVIS subgroup: v4 grid, v5 points, %s hectares",
                  design_version),
  footnote = paste0(
    "MCP (minimum convex polygon) area: ",
    paste(sprintf("%s, %d cameras: %.2f km2", mcp$design, mcp$cameras, mcp$mcp_km2), collapse = "; "),
    ". v4 counts the 30 sites given cameras (footprint, main and the top backups). ",
    design_version, " site share counts hectares; each hectare holds ", cameras_per_hectare,
    " cameras."),
  max_chars = 40)

### Page 7: distances between hectares
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
# source string for a layer: its own GeoPackage, next to the project
src <- function(lyr) paste0("./", lyr, ".gpkg|layername=", lyr)
qgis_layers <- list(
  # where cameras actually went: editable, with drop-downs and an automatic timestamp
  qgis_layer_xml("deployments", "Deployments (record here)", src("deployments"), crs_ll,
                 list(kind = "single", geom = "marker", shape = "star", size = 5,
                      fill = "#33A02C", outline = "#000000"),
                 label_field = "deployment_id", read_only = FALSE,
                 field_defaults = c(recorded_at = "now()"),
                 value_maps = list(hectare_id = c(hectares$hectare_id, backups$hectare_id),
                                   guide_id = guides$guide_id)),
  # the flux tower and the A2O recorders, labelled by name
  qgis_layer_xml("flux_tower", "Flux tower", src("flux_tower"), crs_ll,
                 list(kind = "single", geom = "marker", shape = "triangle", size = 5,
                      fill = "#1F78B4", outline = "#FFFFFF")),
  qgis_layer_xml("a2o_recorders", "A2O site 61 recorders", src("a2o_recorders"), crs_ll,
                 list(kind = "single", geom = "marker", shape = "star", size = 5,
                      fill = "#6A3D9A", outline = "#FFFFFF"),
                 label_field = "name"),
  # guide points, labelled, filled on the on-track guide
  qgis_layer_xml(guide_layer, paste(design_version, "camera guides (nominal)"), src(guide_layer),
                 crs_ll,
                 list(kind = "categorized", attr = "role",
                      categories = data.frame(value = c("on-track", "off-track"),
                                              label = c("on-track guide", "off-track guide"),
                                              fill = c("#FFFF33", "#FFFFFF"), outline = "#000000",
                                              shape = "circle", size = 3, outline_width = 0.4)),
                 label_field = "guide_id"),
  # the hectares, outlined and labelled with ID and rank
  # the backups, dashed orange, labelled with the hectare each replaces
  qgis_layer_xml(backup_layer, paste0("Backup hectares (if ", access_barrier_name, " is closed)"),
                 src(backup_layer), crs_ll,
                 list(kind = "single", geom = "fill", fill = NULL, outline = col_backup,
                      outline_style = "dash", outline_width = 0.8),
                 geometry = "Polygon", label_field = "map_label"),
  # the creek that may close in the wet season
  qgis_layer_xml("access_barrier", paste(access_barrier_name, "(wet-season barrier)"),
                 src("access_barrier"), crs_ll,
                 list(kind = "single", geom = "line", outline = col_creek, outline_width = 1.2),
                 geometry = "Line"),
  qgis_layer_xml(hect_layer, paste(design_version, "hectares (ID (rank))"), src(hect_layer), crs_ll,
                 list(kind = "single", geom = "fill", fill = "#FFFF33", alpha = 60,
                      outline = "#000000", outline_width = 0.8),
                 geometry = "Polygon", label_field = "map_label"),
  # mapped tracks only (the v5 proxy points are drawn with the v5 layer)
  qgis_layer_xml("tracks", "Tracks (OSM / QLD)", src("tracks"), crs_ll,
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
