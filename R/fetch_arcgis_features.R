#' Download Features From an ArcGIS REST Map Service Layer
#'
#' @description Queries one layer of an ArcGIS REST MapServer (such as the Queensland
#'   Government spatial services) and returns its features as an sf layer. Features can
#'   be selected by an attribute filter (`where`), by a longitude/latitude box, or both.
#'   GDAL reads the GeoJSON reply straight from the web address, so no extra packages
#'   are needed. Features are returned whole, not clipped to the box.
#' @param service character. Address of the MapServer, ending in `MapServer`, e.g.
#'   "https://spatial-gis.information.qld.gov.au/arcgis/rest/services/Biota/RegionalEcosystemMapping/MapServer".
#' @param layer_id integer. Layer number within the service.
#' @param bbox numeric, length 4, or NULL. Box as c(xmin, ymin, xmax, ymax) in WGS84
#'   longitude and latitude; NULL selects by `where` alone.
#' @param where character. SQL filter on the layer's attributes, e.g. "lotplan = '4DV450'".
#' @param out_fields character. Comma-separated attribute names to keep, or "*" for all.
#' @param crs integer or crs. CRS to return the features in.
#' @return sf of the matching features, possibly with zero rows. Hard `stop()`s if the
#'   service cannot be read.
#' @author Zachary Amir
fetch_arcgis_features <- function(service, layer_id, bbox = NULL, where = "1=1",
                                  out_fields = "*", crs = 4326) {
  # if the service address does not end in MapServer,
  if (!grepl("MapServer/?$", service)) {
    # stop because the query path is built on top of it
    stop("fetch_arcgis_features needs a service address ending in 'MapServer', not: ", service,
         "\nCopy the address from the service's REST directory page.")
  } # end service check
  # if a box is given but is not four numbers in lon/lat order,
  if (!is.null(bbox) && (length(bbox) != 4 || bbox[1] >= bbox[3] || bbox[2] >= bbox[4])) {
    # stop because the service would silently return nothing
    stop("fetch_arcgis_features needs bbox = c(xmin, ymin, xmax, ymax) in lon/lat.\n",
         "Check the order and that min < max.")
  } # end bbox check

  ## build the query address, asking for GeoJSON in WGS84
  url <- paste0(sub("/$", "", service), "/", layer_id, "/query?",
                # attribute filter, with spaces and quotes made safe for a web address
                "where=", utils::URLencode(where, reserved = TRUE),
                # the attributes to send back
                "&outFields=", utils::URLencode(out_fields, reserved = TRUE),
                # always return coordinates in WGS84 longitude and latitude
                "&outSR=4326&f=geojson")
  # if a box was given, add a spatial filter for features touching it
  if (!is.null(bbox)) {
    url <- paste0(url, "&geometry=", paste(bbox, collapse = ","),
                  "&geometryType=esriGeometryEnvelope&inSR=4326",
                  "&spatialRel=esriSpatialRelIntersects")
  } # end bbox condition

  # read the reply, catching any failure so it can be reported with the layer
  feats <- tryCatch(sf::st_read(url, quiet = TRUE), error = function(e) e)
  # if the read failed,
  if (inherits(feats, "error")) {
    # stop and say which layer failed and what to check
    stop("fetch_arcgis_features could not read layer ", layer_id, " of ", service, ": ",
         conditionMessage(feats), "\nCheck the internet connection and the layer number.")
  } # end read error check

  # return the features in the requested CRS
  return(sf::st_transform(feats, crs))
} # end function
