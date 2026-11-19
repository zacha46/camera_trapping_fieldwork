#' Download Queensland Government Hydrography for a Bounding Box
#'
#' @description Queries the Queensland Government "Water courses and bodies" map
#'   service (InlandWaters/WaterCoursesAndBodies) for every feature of the chosen
#'   layers that intersects a longitude/latitude box, and returns them as one sf
#'   layer clipped to that box. Each feature keeps its name, perenniality and
#'   hierarchy where the source layer has them, plus the layer it came from.
#'   Large features such as river channels extend far past the box, so clipping
#'   keeps the result small. The data are (c) State of Queensland, CC BY 4.0.
#' @param bbox numeric, length 4. Box as c(xmin, ymin, xmax, ymax) in WGS84
#'   longitude and latitude.
#' @param layers named integer. Service layer IDs to fetch, named with a short
#'   label, e.g. c(watercourse_area = 34, reservoir = 28).
#' @param crs integer or crs. CRS to return the features in.
#' @return sf with columns `layer`, `name`, `perenniality`, `hierarchy`,
#'   `feature_type` and geometry; zero rows if nothing intersects. Hard `stop()`s
#'   if the service returns an error.
#' @author Zachary Amir
fetch_qld_hydrography <- function(bbox, layers, crs = 4326) {
  ## the box must be four numbers in lon/lat order
  if (length(bbox) != 4 || bbox[1] >= bbox[3] || bbox[2] >= bbox[4]) {
    stop("fetch_qld_hydrography needs bbox = c(xmin, ymin, xmax, ymax) in lon/lat.\n",
         "Check the order and that min < max.")
  } # end bbox check

  # the service's base address
  base <- paste0("https://spatial-gis.information.qld.gov.au/arcgis/rest/services/",
                 "InlandWaters/WaterCoursesAndBodies/MapServer/")
  # the columns kept from every layer (some layers lack some of them)
  keep_cols <- c("name", "perenniality", "hierarchy", "feature_type")
  # the box as a polygon, for clipping
  box <- sf::st_as_sfc(sf::st_bbox(c(xmin = bbox[1], ymin = bbox[2], xmax = bbox[3], ymax = bbox[4]),
                                   crs = sf::st_crs(4326)))

  # init an empty list to hold one layer's features each
  per_layer <- list()
  # for each requested layer,
  for (lab in names(layers)) {
    ## ask for every feature intersecting the box, as GeoJSON in lon/lat
    url <- paste0(base, layers[[lab]], "/query?where=1%3D1",
                  "&geometry=", paste(bbox, collapse = ","),
                  "&geometryType=esriGeometryEnvelope&inSR=4326",
                  "&spatialRel=esriSpatialRelIntersects&outFields=*&outSR=4326&f=geojson")
    # GDAL reads the GeoJSON straight from the web address
    feats <- tryCatch(sf::st_read(url, quiet = TRUE), error = function(e) e)
    # surface a service failure with the layer it came from
    if (inherits(feats, "error")) {
      stop("fetch_qld_hydrography could not read layer ", lab, " (", layers[[lab]], "): ",
           conditionMessage(feats), "\nCheck the internet connection and the service address.")
    } # end read error check
    # skip layers with nothing in the box
    if (nrow(feats) == 0) next

    # add any of the kept columns this layer lacks, as missing
    for (cl in setdiff(keep_cols, names(feats))) feats[[cl]] <- NA_character_
    # note the source layer
    feats$layer <- lab
    # keep only the shared columns so the layers stack
    feats <- feats[, c("layer", keep_cols)]
    # trim features to the box; spherical geometry is switched off for the clip
    ## because the service's polygons are not always valid on the sphere
    old_s2 <- suppressMessages(sf::sf_use_s2(FALSE))
    feats <- suppressMessages(suppressWarnings(sf::st_intersection(sf::st_make_valid(feats), box)))
    suppressMessages(sf::sf_use_s2(old_s2))
    # store it
    per_layer[[lab]] <- feats
  } # end per layer

  ## stack the layers, or return an empty layer if the box held nothing
  if (length(per_layer) == 0) {
    return(sf::st_sf(layer = character(0), name = character(0), perenniality = character(0),
                     hierarchy = character(0), feature_type = character(0),
                     geometry = sf::st_sfc(crs = 4326)) |> sf::st_transform(crs))
  } # end empty condition
  hydro <- do.call(rbind, per_layer)
  # drop the row names rbind builds from the list names
  rownames(hydro) <- NULL

  return(sf::st_transform(hydro, crs))
} # end function
