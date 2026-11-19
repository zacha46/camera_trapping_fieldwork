#' Write Planned Camera Points and a Boundary to a Styled KML File
#'
#' @description Writes a KML for Google Earth, Avenza or a phone's map app. Points
#'   are coloured by status and grouped into one folder per status, so a whole
#'   class can be switched on or off. An optional boundary is drawn as an outline
#'   with no fill, and optional extra placemarks (e.g. the flux tower) go in their
#'   own folder. The KML is written as plain text rather than through GDAL so the
#'   styling and folder layout are explicit.
#' @param points sf point layer with columns `point_id` and `status`. Any CRS; it is
#'   transformed to WGS84.
#' @param file character. Path of the `.kml` to write.
#' @param status_colours named character. Hex colour (`"#RRGGBB"`) for each status,
#'   named by status. Folder order follows this vector.
#' @param description_cols character. Columns of `points` listed in each placemark's
#'   pop-up description.
#' @param boundary sf polygon or NULL. Outline to draw.
#' @param boundary_name character. Name of the boundary placemark.
#' @param boundary_description character. Pop-up text for the boundary.
#' @param extra_points sf point layer with `name` and `description` columns, or NULL.
#' @param extra_folder character. Folder name for `extra_points`.
#' @param doc_name character. Name shown at the top of the KML document.
#' @return character, the path of the KML written. Hard `stop()`s if a status in
#'   `points` has no colour.
#' @author Zachary Amir
write_kml_points <- function(points, file, status_colours,
                             description_cols = character(0),
                             boundary = NULL, boundary_name = "Boundary",
                             boundary_description = "",
                             extra_points = NULL, extra_folder = "Other",
                             doc_name = "Camera design") {
  ## every status present needs a colour, or its points would vanish from the map
  unstyled <- setdiff(unique(points$status), names(status_colours))
  if (length(unstyled) > 0) {
    stop("write_kml_points has no colour for status: ", paste(unstyled, collapse = ", "),
         "\nAdd it to status_colours.")
  } # end colour check

  ## KML colours are aabbggrr (alpha, blue, green, red), the reverse of web hex
  hex_to_kml <- function(hex, alpha = "ff") {
    # strip the leading #
    h <- sub("^#", "", hex)
    # reassemble as alpha, blue, green, red
    paste0(alpha, substr(h, 5, 6), substr(h, 3, 4), substr(h, 1, 2))
  } # end colour helper

  ## escape the characters XML treats as markup
  xml_escape <- function(x) {
    x <- gsub("&", "&amp;", x, fixed = TRUE)
    x <- gsub("<", "&lt;", x, fixed = TRUE)
    gsub(">", "&gt;", x, fixed = TRUE)
  } # end escape helper

  ## one placemark for one point
  point_placemark <- function(name, description, lon, lat, style_id) {
    paste0("      <Placemark>\n",
           "        <name>", xml_escape(name), "</name>\n",
           "        <description>", xml_escape(description), "</description>\n",
           "        <styleUrl>#", style_id, "</styleUrl>\n",
           "        <Point><coordinates>", sprintf("%.7f,%.7f,0", lon, lat), "</coordinates></Point>\n",
           "      </Placemark>")
  } # end placemark helper

  # KML is always WGS84 longitude, latitude
  points <- sf::st_transform(points, 4326)
  # pull the coordinates out once
  xy <- sf::st_coordinates(points)

  # the round dot icon Google Earth ships with, tinted per style
  icon <- "http://maps.google.com/mapfiles/kml/shapes/placemark_circle.png"

  ## one style per status, plus the boundary and extra-point styles
  styles <- vapply(names(status_colours), function(s) {
    paste0("  <Style id=\"status_", s, "\">\n",
           "    <IconStyle><color>", hex_to_kml(status_colours[[s]]), "</color><scale>1.1</scale>",
           "<Icon><href>", icon, "</href></Icon></IconStyle>\n",
           "    <LabelStyle><scale>0.8</scale></LabelStyle>\n",
           "  </Style>")
  }, character(1))
  styles <- c(styles,
              # boundary: a thick red outline, no fill
              paste0("  <Style id=\"boundary\">\n",
                     "    <LineStyle><color>", hex_to_kml("#E41A1C"), "</color><width>3</width></LineStyle>\n",
                     "    <PolyStyle><fill>0</fill></PolyStyle>\n",
                     "  </Style>"),
              # extras: a blue star
              paste0("  <Style id=\"extra\">\n",
                     "    <IconStyle><color>", hex_to_kml("#1F78B4"), "</color><scale>1.3</scale>",
                     "<Icon><href>http://maps.google.com/mapfiles/kml/shapes/star.png</href></Icon></IconStyle>\n",
                     "  </Style>"))

  # init the list of folders
  folders <- character(0)

  ## boundary folder, drawn as an outline of its outer ring
  if (!is.null(boundary)) {
    # outer ring coordinates in WGS84
    ring <- sf::st_coordinates(sf::st_transform(sf::st_geometry(boundary), 4326))
    # KML wants "lon,lat,0" triples separated by spaces
    coord_text <- paste(sprintf("%.7f,%.7f,0", ring[, "X"], ring[, "Y"]), collapse = " ")
    folders <- c(folders, paste0(
      "    <Folder><name>", xml_escape(boundary_name), "</name>\n",
      "      <Placemark>\n",
      "        <name>", xml_escape(boundary_name), "</name>\n",
      "        <description>", xml_escape(boundary_description), "</description>\n",
      "        <styleUrl>#boundary</styleUrl>\n",
      "        <Polygon><outerBoundaryIs><LinearRing><coordinates>", coord_text,
      "</coordinates></LinearRing></outerBoundaryIs></Polygon>\n",
      "      </Placemark>\n",
      "    </Folder>"))
  } # end boundary condition

  ## one folder per status, in the order the colours were given
  for (s in names(status_colours)) {
    # which points carry this status
    rows <- which(points$status == s)
    # skip statuses with no points
    if (length(rows) == 0) next
    # build each point's placemark
    marks <- vapply(rows, function(r) {
      # list the requested attributes as "name: value" lines
      desc <- paste(paste0(description_cols, ": ",
                           vapply(description_cols, function(cl) format(sf::st_drop_geometry(points)[r, cl]),
                                  character(1))),
                    collapse = "\n")
      point_placemark(points$point_id[r], desc, xy[r, "X"], xy[r, "Y"], paste0("status_", s))
    }, character(1))
    # wrap them in a folder named after the status
    folders <- c(folders, paste0("    <Folder><name>", s, " (", length(rows), ")</name>\n",
                                 paste(marks, collapse = "\n"), "\n    </Folder>"))
  } # end per status

  ## extra placemarks (e.g. the flux tower) in their own folder
  if (!is.null(extra_points)) {
    # WGS84 coordinates of the extras
    ex <- sf::st_transform(extra_points, 4326)
    ex_xy <- sf::st_coordinates(ex)
    # one placemark each
    marks <- vapply(seq_len(nrow(ex)), function(r) {
      point_placemark(ex$name[r], ex$description[r], ex_xy[r, "X"], ex_xy[r, "Y"], "extra")
    }, character(1))
    folders <- c(folders, paste0("    <Folder><name>", xml_escape(extra_folder), "</name>\n",
                                 paste(marks, collapse = "\n"), "\n    </Folder>"))
  } # end extras condition

  ## assemble the document and write it
  kml <- paste0("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n",
                "<kml xmlns=\"http://www.opengis.net/kml/2.2\">\n",
                "<Document>\n",
                "  <name>", xml_escape(doc_name), "</name>\n",
                paste(styles, collapse = "\n"), "\n",
                paste(folders, collapse = "\n"), "\n",
                "</Document>\n</kml>\n")
  writeLines(kml, file, useBytes = TRUE)

  return(file)
} # end function
