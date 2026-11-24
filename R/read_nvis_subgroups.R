#' Map NVIS Major Vegetation Subgroups Within a Property
#'
#' @description Reads the national NVIS Major Vegetation Subgroups (MVS) grid, cuts out
#'   the cells around a property, turns them into polygons (one per subgroup) and clips
#'   them to the property boundary. Each subgroup gets its name from a code-to-name
#'   table and its area on the property. The grid has 100 m cells, so subgroup edges
#'   are only as precise as that.
#' @param grid_path character. Path to the NVIS MVS raster (e.g. the ESRI grid folder
#'   `aus6_0e_mvs` from NVIS 6.0 extant).
#' @param boundary sf. Property boundary polygon(s), in a projected CRS in metres.
#' @param names_lookup data.frame. Columns `mvs_code` (integer) and `mvs_name`.
#' @return sf of polygons in the boundary's CRS, one row per subgroup, with columns
#'   `mvs_code`, `mvs_name`, `area_km2` and `area_share`, sorted largest first. Hard
#'   `stop()`s if the boundary is not projected or misses the grid.
#' @author Zachary Amir
read_nvis_subgroups <- function(grid_path, boundary, names_lookup) {
  # if the grid file is not there,
  if (!file.exists(grid_path)) {
    # stop and say what to download
    stop("read_nvis_subgroups found no NVIS grid at ", grid_path,
         "\nDownload NVIS Major Vegetation Subgroups (extant) from DCCEEW and point grid_path at it.")
  } # end grid check
  # if the boundary is in degrees,
  if (sf::st_is_longlat(boundary)) {
    # stop because areas must be worked in metres
    stop("read_nvis_subgroups needs the boundary in a projected CRS in metres (e.g. UTM).\n",
         "Transform it with sf::st_transform() first.")
  } # end CRS check
  # if the lookup lacks the columns used for the join,
  if (!all(c("mvs_code", "mvs_name") %in% names(names_lookup))) {
    # stop and name them
    stop("read_nvis_subgroups needs names_lookup with columns mvs_code and mvs_name.\n",
         "Read templates/nvis_mvs60_names.csv.")
  } # end lookup check

  ## cut the national grid down to the property
  # open the grid without loading it into memory
  grid <- terra::rast(grid_path)
  # merge the boundary into one shape and widen it by 500 m so edge cells are kept
  area <- sf::st_buffer(sf::st_union(boundary), 500)
  # move that shape into the grid's CRS (Australian Albers)
  area_grid <- terra::project(terra::vect(area), terra::crs(grid))
  # if the property lies outside the grid,
  if (is.null(terra::intersect(terra::ext(grid), terra::ext(area_grid)))) {
    # stop because there is nothing to read
    stop("read_nvis_subgroups: the boundary does not overlap the NVIS grid.\n",
         "Check the boundary's CRS and that the grid covers this site.")
  } # end overlap check
  # crop the grid to the widened property, keeping whole cells
  cropped <- terra::crop(grid, area_grid, snap = "out")

  ## turn the cells into one polygon per subgroup code
  polys <- terra::as.polygons(cropped, dissolve = TRUE)
  # convert to sf and move into the boundary's CRS
  polys <- sf::st_transform(sf::st_as_sf(polys), sf::st_crs(boundary))
  # name the code column consistently, whatever the grid called it
  names(polys)[1] <- "mvs_code"
  # make sure the code is a whole number for the join
  polys$mvs_code <- as.integer(polys$mvs_code)

  ## keep only the part of each subgroup on the property
  # clip to the boundary (one merged shape, so subgroups are not split by parcel part)
  on_prop <- suppressWarnings(sf::st_intersection(polys, sf::st_union(boundary)))
  # add the subgroup names
  on_prop <- dplyr::left_join(on_prop, names_lookup, by = "mvs_code")
  # calculate each subgroup's area on the property in km2
  on_prop$area_km2 <- as.numeric(sf::st_area(on_prop)) / 1e6
  # and its share of the property
  on_prop$area_share <- on_prop$area_km2 / sum(on_prop$area_km2)
  # sort largest first and tidy the columns
  on_prop <- on_prop[order(-on_prop$area_km2), c("mvs_code", "mvs_name", "area_km2", "area_share")]
  rownames(on_prop) <- NULL

  return(on_prop)
} # end function
