#' Download Esri World Imagery for a Map Extent
#'
#' @description Fetches Esri World Imagery tiles covering an extent through GDAL's WMS
#'   (tile service) driver, reprojects them to the extent's CRS and saves a 3-band
#'   GeoTIFF. Used as a backdrop for checking tracks and sites by eye. Esri's terms
#'   require the attribution "Source: Esri, Maxar, Earthstar Geographics, and the GIS
#'   User Community" wherever the imagery is shown.
#' @param extent sf or sfc. Any layer whose bounding box sets the area, in a projected
#'   CRS in metres.
#' @param out_path character. Where to write the GeoTIFF.
#' @param zoom integer. Tile zoom level; 16 gives about 2.4 m pixels, 17 about 1.2 m.
#' @param res_m numeric. Pixel size of the saved GeoTIFF, metres.
#' @return character, the path written. Hard `stop()`s if the tiles cannot be read.
#' @author Zachary Amir
fetch_esri_imagery <- function(extent, out_path, zoom = 16, res_m = 2.5) {
  # if the extent is in degrees,
  if (sf::st_is_longlat(extent)) {
    # stop because the pixel size is given in metres
    stop("fetch_esri_imagery needs the extent in a projected CRS in metres (e.g. UTM).\n",
         "Transform it with sf::st_transform() first.")
  } # end CRS check

  ### describe the Esri tile service for GDAL:
  ## web-mercator tiles, 256 px, addressed as /tile/{z}/{y}/{x}, three colour bands
  wms_xml <- paste0(
    "<GDAL_WMS><Service name=\"TMS\"><ServerUrl>",
    "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/${z}/${y}/${x}",
    "</ServerUrl></Service>",
    "<DataWindow><UpperLeftX>-20037508.34</UpperLeftX><UpperLeftY>20037508.34</UpperLeftY>",
    "<LowerRightX>20037508.34</LowerRightX><LowerRightY>-20037508.34</LowerRightY>",
    "<TileLevel>", zoom, "</TileLevel><TileCountX>1</TileCountX><TileCountY>1</TileCountY>",
    "<YOrigin>top</YOrigin></DataWindow>",
    "<Projection>EPSG:3857</Projection><BlockSizeX>256</BlockSizeX><BlockSizeY>256</BlockSizeY>",
    "<BandsCount>3</BandsCount><UserAgent>camera-trapping-fieldwork R workflow</UserAgent>",
    "</GDAL_WMS>")
  # write the description to a temporary file GDAL can open like a raster
  xml_path <- tempfile(fileext = ".xml")
  writeLines(wms_xml, xml_path)

  ## read only the tiles that cover the extent
  # the whole-world imagery, opened lazily
  world <- terra::rast(xml_path)
  # the extent's box, as a polygon in web mercator
  box <- terra::vect(sf::st_as_sfc(sf::st_bbox(extent)))
  box_wm <- terra::project(box, "EPSG:3857")
  # crop to the box, which downloads just those tiles
  img <- tryCatch(terra::crop(world, box_wm), error = function(e) e)
  # if the download failed,
  if (inherits(img, "error")) {
    # stop and say what to check
    stop("fetch_esri_imagery could not read Esri World Imagery tiles: ", conditionMessage(img),
         "\nCheck the internet connection, or try a lower zoom.")
  } # end download check

  ## move the imagery onto the extent's grid in metres and save it
  # an empty template grid over the extent at the chosen pixel size
  template <- terra::rast(terra::ext(box), resolution = res_m, crs = sf::st_crs(extent)$wkt)
  # resample the colours onto it smoothly
  img_proj <- terra::project(img, template, method = "bilinear")
  # write it as 8-bit colour
  terra::writeRaster(img_proj, out_path, datatype = "INT1U", overwrite = TRUE)

  return(out_path)
} # end function
