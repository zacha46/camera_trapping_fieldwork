### Every site-specific setting for the Fletcherview v6 hectare design
## 25 November 2026, Fletcherview Research Station, QLD
# Zachary Amir

### This file defines objects only:
## It runs no analysis and writes no files, so 04_fetch_v6_layers.R and
## 05_design_hectares.R both source it. To run the v6 method at another TERN
## SuperSite, copy this file into that campaign and change the values below.

## design version stamped on every output file and layer name
design_version <- "v7"
# short site name used in output file names
site_name <- "fletcherview"
# where this campaign lives
campaign_dir <- here::here("campaigns", "2026-11_fletcherview")
# all distances and areas are worked in this projected CRS (WGS 84 / UTM zone 55S)
crs_utm <- 32755

### The property: one Queensland cadastral lot on plan
## QLD Digital Cadastral Database (DCDB), "Cadastral parcels" layer
cadastre_service <- "https://spatial-gis.information.qld.gov.au/arcgis/rest/services/PlanningCadastre/LandParcelPropertyFramework/MapServer"
cadastre_layer <- 4
lotplan <- "4DV450"

### Fixed points on the site
## flux tower, as used since v1 (OzFlux metadata differs by ~25 m; see README)
tower_lon <- 146.188908
tower_lat <- -19.887232
## TERN core 1 ha plot (QDAEIU0008): OzFlux says the tower stands north of it, but no
## corner coordinates are published, so this placeholder square sits with its north
## edge this far south of the tower, centred on the tower's easting
core_plot_gap_south_m <- 10
core_plot_is_placeholder <- TRUE # ZDA: confirm on the ground at deployment
## Australian Acoustic Observatory (A2O) site 61: handheld GPS fixes of its recorders
a2o_gps_path <- file.path(campaign_dir, "data", "raw", "GPS_fletcher_values.csv")
### Which recorders anchor a hectare?
## the wet-season pair, since cameras run Nov-Feb; each gets its own hectare (ZDA)
a2o_anchor_titles <- c("Acoustic wet A", "Acoustic wet B")

### Vegetation layers
## NVIS 6.0 extant Major Vegetation Subgroups, 100 m grid, from the camDB curation folder
nvis_grid_path <- paste0("/Users/zachary_amir/Dropbox/ECL spatial layers repository/",
                         "Australian spatial layers GIS data/AUS/NVIS_Veg/Major_Veg_Sub/",
                         "GRID_NVIS6_0_AUST_EXT_MVS/aus6_0e_mvs")
# code-to-name table for the subgroups
nvis_names_path <- here::here("templates", "nvis_mvs60_names.csv")
## Queensland regional ecosystems (interpretation only), pre-clearing and remnant layers
re_service <- "https://spatial-gis.information.qld.gov.au/arcgis/rest/services/Biota/RegionalEcosystemMapping/MapServer"
re_layers <- c(re_preclear = 1, re_remnant = 2)

### Tracks, in order of preference
## (1) OpenStreetMap, (2) QLD roads and tracks, (3) the collaborator's v5 points,
## each of which sits on a track interpreted from satellite images (ZDA, 2026-11-25)
qld_roads_service <- "https://spatial-gis.information.qld.gov.au/arcgis/rest/services/Transportation/RoadsAndTracks/MapServer"
qld_roads_layer <- 10
v5_docx_path <- file.path(campaign_dir, "data", "raw", "Fletcherview_Camera_Trap_Survey.docx")
v5_table_number <- 1 # the "provisional field register" table
## fetch tracks and imagery this far beyond the property
fetch_margin_m <- 1000
## Esri World Imagery zoom level for the PDF backdrop (16 is ~2.4 m pixels)
imagery_zoom <- 16

### Hectare design rules
## a subgroup is a stratum if it covers at least this much of the property
stratum_min_km2 <- 1
# hectares per stratum (the core hectare counts as one of its stratum's)
hectares_per_stratum <- 2
# stop and ask if there are more strata than this
max_strata <- 5
# cameras in total, including the core hectare
camera_budget <- 30
# cameras per hectare: the first that fits the budget is used
cameras_per_hectare_options <- c(4, 3)
# side of each hectare, metres
hectare_size_m <- 100
# spacing of candidate hectare centres, metres
lattice_m <- 25
# share of a hectare that should be its own subgroup
min_purity <- 0.75
# wanted distance between hectares of the same subgroup, metres
target_spacing_m <- 1000

### Earlier designs to compare against
v4_gpkg_path <- file.path(campaign_dir, "outputs", "OLD", "qfield_v4", "fletcherview_design_v4.gpkg")
v4_summary_path <- file.path(campaign_dir, "outputs", "OLD", "design_summary_v4.csv")
v6_gpkg_path <- file.path(campaign_dir, "outputs", "OLD", "fletcherview_v6.gpkg")
