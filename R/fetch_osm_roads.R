#' Download OpenStreetMap Roads and Tracks for a Small Box
#'
#' @description Downloads every OpenStreetMap feature in a small longitude/latitude box
#'   from the OSM editing API (`api/0.6/map`) and keeps the ways tagged `highway`
#'   (roads, tracks, service roads, paths). The API is used rather than Overpass
#'   because it answers small boxes directly; it refuses boxes larger than 0.25 square
#'   degrees. The raw XML is saved to `out_path` and read with GDAL's OSM driver.
#'   Data (c) OpenStreetMap contributors, ODbL.
#' @param bbox numeric, length 4. Box as c(xmin, ymin, xmax, ymax) in WGS84 longitude
#'   and latitude.
#' @param out_path character. Where to save the downloaded `.osm` file.
#' @param crs integer or crs. CRS to return the lines in.
#' @return sf of lines with columns `osm_id`, `name`, `highway` and `source` (always
#'   "OSM"); zero rows if the box holds no roads. Hard `stop()`s if the download fails.
#' @author Zachary Amir
fetch_osm_roads <- function(bbox, out_path, crs = 4326) {
  # if the box is not four numbers in lon/lat order,
  if (length(bbox) != 4 || bbox[1] >= bbox[3] || bbox[2] >= bbox[4]) {
    # stop because the API would reject it
    stop("fetch_osm_roads needs bbox = c(xmin, ymin, xmax, ymax) in lon/lat.\n",
         "Check the order and that min < max.")
  } # end bbox check
  # if the box is larger than the API allows,
  if ((bbox[3] - bbox[1]) * (bbox[4] - bbox[2]) > 0.25) {
    # stop and suggest splitting it
    stop("fetch_osm_roads box covers more than 0.25 square degrees, the OSM API limit.\n",
         "Use a smaller box around the property.")
  } # end size check

  ## download the map data; the API asks clients to name themselves with a user agent
  url <- paste0("https://api.openstreetmap.org/api/0.6/map?bbox=", paste(bbox, collapse = ","))
  # name this workflow generically, carrying no personal details
  old_ua <- options(HTTPUserAgent = "camera-trapping-fieldwork R workflow")
  # download, catching failure so it can be explained
  got <- tryCatch(utils::download.file(url, out_path, quiet = TRUE, mode = "wb"),
                  error = function(e) e)
  # put the user agent back as it was
  options(old_ua)
  # if the download failed,
  if (inherits(got, "error") || !file.exists(out_path)) {
    # stop and say what to check
    stop("fetch_osm_roads could not download ", url, "\n",
         "Check the internet connection, or try again later if the API is busy.")
  } # end download check

  ## read the line features and keep the roads
  # GDAL's OSM driver puts ways in the 'lines' layer
  ways <- sf::st_read(out_path, layer = "lines", quiet = TRUE)
  # keep only ways carrying a highway tag
  roads <- ways[!is.na(ways$highway), c("osm_id", "name", "highway")]
  # note where each line came from
  roads$source <- rep("OSM", nrow(roads))

  # return the roads in the requested CRS
  return(sf::st_transform(roads, crs))
} # end function
