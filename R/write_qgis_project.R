#' Write a QGIS Project File That QField Can Open
#'
#' @description Assembles layers built by `qgis_layer_xml()` into a `.qgs` project.
#'   Layers are drawn in the order given, first on top, and paths are stored
#'   relative to the project so the whole folder can be copied to a phone or tablet
#'   and opened in QField as is. The map opens on `extent`.
#' @param file character. Path of the `.qgs` to write. Its data files must sit where
#'   the layers' relative sources say.
#' @param title character. Project title shown in QField.
#' @param crs sf crs object. Project (map display) CRS.
#' @param layers list. Outputs of `qgis_layer_xml()`, top layer first.
#' @param extent numeric, length 4. Initial view as c(xmin, ymin, xmax, ymax) in `crs`.
#' @return character, the path of the project written. Hard `stop()`s if two
#'   layers share an ID.
#' @author Zachary Amir
write_qgis_project <- function(file, title, crs, layers, extent) {
  ## layer IDs must be unique, or QGIS silently drops one
  ids <- vapply(layers, function(l) l$id, character(1))
  if (any(duplicated(ids))) {
    stop("write_qgis_project got duplicate layer IDs: ", paste(unique(ids[duplicated(ids)]), collapse = ", "),
         "\nGive each qgis_layer_xml() call its own id.")
  } # end duplicate check

  # escape text for XML (same rules qgis_layer_xml uses)
  esc <- function(x) {
    x <- gsub("&", "&amp;", x, fixed = TRUE)
    x <- gsub("<", "&lt;", x, fixed = TRUE)
    x <- gsub(">", "&gt;", x, fixed = TRUE)
    gsub("\"", "&quot;", x, fixed = TRUE)
  } # end escape helper
  # the project CRS block, as WKT plus its EPSG code
  srs <- paste0("<spatialrefsys nativeFormat=\"Wkt\"><wkt>", esc(crs$wkt), "</wkt>",
                "<authid>EPSG:", crs$epsg, "</authid></spatialrefsys>")

  ## the layer list: one entry per layer, all switched on, in drawing order
  tree <- vapply(layers, function(l) {
    paste0("<layer-tree-layer id=\"", l$id, "\" name=\"", esc(l$name), "\" source=\"", esc(l$source),
           "\" providerKey=\"", l$provider, "\" checked=\"Qt::Checked\" expanded=\"1\" legend_exp=\"\">",
           "<customproperties/></layer-tree-layer>")
  }, character(1))

  ## the opening view
  canvas <- paste0("<mapcanvas name=\"theMapCanvas\" annotationsVisible=\"1\"><units>meters</units>",
                   "<extent><xmin>", extent[1], "</xmin><ymin>", extent[2], "</ymin>",
                   "<xmax>", extent[3], "</xmax><ymax>", extent[4], "</ymax></extent>",
                   "<rotation>0</rotation><destinationsrs>", srs, "</destinationsrs></mapcanvas>")

  ## assemble the project
  qgs <- paste0(
    "<!DOCTYPE qgis PUBLIC 'http://mrcc.com/qgis.dtd' 'SYSTEM'>\n",
    "<qgis projectname=\"", esc(title), "\" version=\"3.34.0-Prizren\">\n",
    "<homePath path=\"\"/>\n",
    "<title>", esc(title), "</title>\n",
    "<projectCrs>", srs, "</projectCrs>\n",
    "<layer-tree-group><customproperties/>\n", paste(tree, collapse = "\n"), "\n</layer-tree-group>\n",
    canvas, "\n",
    "<projectlayers>\n", paste(vapply(layers, function(l) l$xml, character(1)), collapse = "\n"),
    "\n</projectlayers>\n",
    # store paths relative to the project so the folder can move
    "<properties><Paths><Absolute type=\"bool\">false</Absolute></Paths></properties>\n",
    "</qgis>\n")
  writeLines(qgs, file, useBytes = TRUE)

  return(file)
} # end function
