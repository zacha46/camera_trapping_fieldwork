#' Build the QGIS Project XML for One Styled Map Layer
#'
#' @description Writes the `<maplayer>` element a QGIS or QField project needs to
#'   draw one layer: where the data are, their CRS, and how to draw them. Three
#'   styles are supported, chosen by `style$kind`:
#'   \enumerate{
#'     \item `"categorized"`: features coloured by the value of one column, one
#'       symbol per value (`style$attr`, `style$categories`); markers by default, or
#'       polygon fills with `style$geom = "fill"`.
#'     \item `"single"`: every feature drawn alike, as a marker (`style$geom =
#'       "marker"`), a line (`style$geom = "line"`, drawn in the `outline` colour,
#'       width and style) or a polygon fill (`style$geom = "fill"`).
#'     \item `"raster"`: a three-band RGB image drawn as is.
#'   }
#'   Colours are hex strings (`"#RRGGBB"`) with an optional `alpha` (0-255).
#'   Marker sizes are in millimetres on screen unless `size_unit = "MapUnit"`, which
#'   sizes them in the project CRS's units (metres for UTM), so they keep their
#'   ground size at every zoom.
#'   Marker shapes use QGIS names such as `"circle"`, `"cross2"` (an X),
#'   `"triangle"` or `"star"`. Outline styles are `"solid"`, `"dash"` or `"dot"`.
#'   Only the elements needed to draw the layer are written; QGIS fills in its own
#'   defaults for everything else when the project opens.
#' @param id character. Unique layer ID within the project.
#' @param name character. Name shown in the layer list and legend.
#' @param source character. Data source relative to the project file, e.g.
#'   `"./design.gpkg|layername=planned_points"` or `"./basemap.tif"`.
#' @param crs sf crs object. The layer's CRS.
#' @param style list. Drawing style, as described above.
#' @param geometry character. "Point", "Line" or "Polygon" for vector layers; ignored for
#'   rasters.
#' @param label_field character or NULL. Column to label features with.
#' @param read_only logical. Stop QField from editing this layer.
#' @param field_defaults named character or NULL. QGIS expressions that fill a
#'   field when a feature is added, named by field, e.g. c(recorded_at = "now()").
#' @param value_maps named list or NULL. Drop-down choices for fields, named by
#'   field, each a character vector of allowed values.
#' @return list with `id`, `name`, `source`, `provider` and `xml` (character).
#'   Hard `stop()`s on an unknown style kind.
#' @author Zachary Amir
qgis_layer_xml <- function(id, name, source, crs, style, geometry = "Point",
                           label_field = NULL, read_only = TRUE,
                           field_defaults = NULL, value_maps = NULL) {
  ## only the three supported styles
  if (!style$kind %in% c("categorized", "single", "raster")) {
    stop("qgis_layer_xml does not know style kind '", style$kind, "' for layer ", name, ".\n",
         "Use 'categorized', 'single' or 'raster'.")
  } # end style check

  ## rasters are read by GDAL, vectors by OGR
  is_raster <- style$kind == "raster"
  provider <- if (is_raster) "gdal" else "ogr"

  # the CRS block, carried as full WKT so QGIS cannot misread it
  srs <- qgis_srs_xml(crs)

  ## how to draw the layer
  if (style$kind == "raster") {
    # three bands straight through as red, green and blue, no stretching
    renderer <- paste0(
      "<pipe>",
      "<rasterrenderer type=\"multibandcolor\" redBand=\"1\" greenBand=\"2\" blueBand=\"3\" ",
      "alphaBand=\"-1\" opacity=\"1\"><rasterTransparency/></rasterrenderer>",
      "<brightnesscontrast brightness=\"0\" contrast=\"0\" gamma=\"1\"/>",
      "</pipe>")
  } else if (style$kind == "single") {
    # one symbol for every feature
    renderer <- paste0("<renderer-v2 type=\"singleSymbol\" forceraster=\"0\" symbollevels=\"0\" enableorderby=\"0\">",
                       "<symbols>", qgis_symbol_xml("0", style), "</symbols>",
                       "</renderer-v2>")
  } else {
    # one category per value, each pointing at its own numbered symbol
    cats <- style$categories
    category_xml <- paste0("<category render=\"true\" symbol=\"", seq_len(nrow(cats)) - 1,
                           "\" value=\"", cats$value, "\" label=\"", cats$label, "\"/>",
                           collapse = "")
    # build each category's symbol from its row
    symbol_xml <- vapply(seq_len(nrow(cats)), function(k) {
      # markers unless the style asks for polygon fills
      geom <- if (is.null(style$geom)) "marker" else style$geom
      qgis_symbol_xml(as.character(k - 1), c(as.list(cats[k, ]), geom = geom))
    }, character(1))
    renderer <- paste0("<renderer-v2 type=\"categorizedSymbol\" attr=\"", style$attr,
                       "\" forceraster=\"0\" symbollevels=\"0\" enableorderby=\"0\">",
                       "<categories>", category_xml, "</categories>",
                       "<symbols>", paste(symbol_xml, collapse = ""), "</symbols>",
                       "</renderer-v2>")
  } # end renderer choice

  ## labels: bold black text with a white halo, just beside the point
  labeling <- ""
  if (!is.null(label_field)) {
    labeling <- paste0(
      "<labeling type=\"simple\"><settings calloutType=\"simple\">",
      "<text-style fieldName=\"", label_field, "\" isExpression=\"0\" fontSize=\"10\" ",
      "fontSizeUnit=\"Point\" fontWeight=\"75\" textColor=\"0,0,0,255\" textOpacity=\"1\">",
      "<text-buffer bufferDraw=\"1\" bufferSize=\"1\" bufferSizeUnits=\"MM\" ",
      "bufferColor=\"255,255,255,255\" bufferOpacity=\"1\"/>",
      "</text-style>",
      # around the point, 1.5 mm out
      "<placement placement=\"0\" dist=\"1.5\" distUnits=\"MM\"/>",
      "<rendering drawLabels=\"1\" obstacle=\"1\" scaleVisibility=\"0\"/>",
      "</settings></labeling>")
  } # end labeling condition

  ## values filled in automatically when QField adds a feature
  defaults <- ""
  if (!is.null(field_defaults)) {
    defaults <- paste0("<defaults>",
                       paste0("<default field=\"", names(field_defaults), "\" expression=\"",
                              qgis_escape(field_defaults), "\" applyOnUpdate=\"0\"/>", collapse = ""),
                       "</defaults>")
  } # end defaults condition

  ## drop-down lists for fields, so field staff pick rather than type
  field_config <- ""
  if (!is.null(value_maps)) {
    fields <- vapply(names(value_maps), function(f) {
      # one map entry per allowed value, shown and stored as the same text
      entries <- paste0("<Option type=\"Map\"><Option type=\"QString\" name=\"", value_maps[[f]],
                        "\" value=\"", value_maps[[f]], "\"/></Option>", collapse = "")
      paste0("<field name=\"", f, "\" configurationFlags=\"NoFlag\">",
             "<editWidget type=\"ValueMap\"><config><Option type=\"Map\">",
             "<Option type=\"List\" name=\"map\">", entries, "</Option>",
             "</Option></config></editWidget></field>")
    }, character(1))
    field_config <- paste0("<fieldConfiguration>", paste(fields, collapse = ""), "</fieldConfiguration>")
  } # end value map condition

  ## assemble the layer element
  type_attrs <- if (is_raster) {
    "type=\"raster\""
  } else {
    paste0("type=\"vector\" geometry=\"", geometry, "\" labelsEnabled=\"",
           as.integer(!is.null(label_field)), "\"")
  } # end type attributes
  xml <- paste0(
    "<maplayer ", type_attrs, " readOnly=\"", as.integer(read_only), "\" ",
    "hasScaleBasedVisibilityFlag=\"0\" minScale=\"100000000\" maxScale=\"0\" autoRefreshEnabled=\"0\">",
    "<id>", id, "</id>",
    "<datasource>", qgis_escape(source), "</datasource>",
    "<layername>", qgis_escape(name), "</layername>",
    "<srs>", srs, "</srs>",
    "<provider encoding=\"UTF-8\">", provider, "</provider>",
    "<flags><Identifiable>1</Identifiable><Removable>1</Removable><Searchable>1</Searchable><Private>0</Private></flags>",
    renderer, labeling, field_config, defaults,
    "</maplayer>")

  return(list(id = id, name = name, source = source, provider = provider, xml = xml))
} # end function


## helper: escape text for an XML attribute or element
qgis_escape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  gsub("\"", "&quot;", x, fixed = TRUE)
} # end escape helper

## helper: the <spatialrefsys> block for a CRS, as WKT plus its EPSG code
qgis_srs_xml <- function(crs) {
  paste0("<spatialrefsys nativeFormat=\"Wkt\">",
         "<wkt>", qgis_escape(crs$wkt), "</wkt>",
         "<authid>EPSG:", crs$epsg, "</authid>",
         "</spatialrefsys>")
} # end srs helper

## helper: hex colour plus alpha to QGIS "r,g,b,a"
qgis_colour <- function(hex, alpha = 255) {
  rgb <- grDevices::col2rgb(hex)
  paste(c(rgb[, 1], alpha), collapse = ",")
} # end colour helper

## helper: one <symbol> element, marker or fill, from a style list
qgis_symbol_xml <- function(name, s) {
  # fill in optional settings with plain defaults
  alpha <- if (is.null(s$alpha)) 255 else s$alpha
  outline <- if (is.null(s$outline)) "#000000" else s$outline
  outline_style <- if (is.null(s$outline_style)) "solid" else s$outline_style
  outline_width <- if (is.null(s$outline_width)) 0.4 else s$outline_width
  size_unit <- if (is.null(s$size_unit)) "MM" else s$size_unit
  # each option is a typed key-value pair inside an Option map
  opt <- function(k, v) paste0("<Option type=\"QString\" name=\"", k, "\" value=\"", v, "\"/>")

  if (s$geom == "marker") {
    # a simple marker: shape, size and colours
    layer <- paste0("<layer class=\"SimpleMarker\" enabled=\"1\" locked=\"0\" pass=\"0\"><Option type=\"Map\">",
                    opt("name", s$shape), opt("size", s$size), opt("size_unit", size_unit),
                    opt("color", qgis_colour(s$fill, alpha)),
                    opt("outline_color", qgis_colour(outline)),
                    opt("outline_style", outline_style),
                    opt("outline_width", outline_width), opt("outline_width_unit", "MM"),
                    "</Option></layer>")
    type <- "marker"
  } else if (s$geom == "line") {
    # a simple line: colour, width and dash style taken from the outline settings
    layer <- paste0("<layer class=\"SimpleLine\" enabled=\"1\" locked=\"0\" pass=\"0\"><Option type=\"Map\">",
                    opt("line_color", qgis_colour(outline, alpha)),
                    opt("line_style", outline_style),
                    opt("line_width", outline_width), opt("line_width_unit", "MM"),
                    "</Option></layer>")
    type <- "line"
  } else {
    # a simple fill: optional fill colour and an outline
    fill_style <- if (is.null(s$fill) || is.na(s$fill)) "no" else "solid"
    fill_col <- if (fill_style == "no") "0,0,0,0" else qgis_colour(s$fill, alpha)
    layer <- paste0("<layer class=\"SimpleFill\" enabled=\"1\" locked=\"0\" pass=\"0\"><Option type=\"Map\">",
                    opt("style", fill_style), opt("color", fill_col),
                    opt("outline_color", qgis_colour(outline)),
                    opt("outline_style", outline_style),
                    opt("outline_width", outline_width), opt("outline_width_unit", "MM"),
                    "</Option></layer>")
    type <- "fill"
  } # end geometry choice

  paste0("<symbol type=\"", type, "\" name=\"", name, "\" alpha=\"1\" clip_to_extent=\"1\" force_rhr=\"0\">",
         layer, "</symbol>")
} # end symbol helper
