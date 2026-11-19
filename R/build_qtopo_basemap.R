#' Build a Single GeoTIFF Basemap From QTopo GeoPDF Map Sheets
#'
#' @description QTopo 1:25k sheets are GeoPDFs with a white collar (title, legend,
#'   margins) around the map. Mosaicking whole sheets lets one sheet's collar paint
#'   over its neighbour's map, so each sheet is first cropped to its neatline (the
#'   map frame GDAL reports in the PDF metadata). The cropped sheets are then
#'   rendered at `dpi`, reprojected to `crs`, mosaicked, and clipped to `extent`
#'   on a regular grid of `resolution` metres. The result is a JPEG-compressed RGB
#'   GeoTIFF that QField and ggplot can both read.
#'
#'   The GDAL bundled with the CRAN binaries of sf and terra cannot read PDFs, so
#'   this function calls the command-line GDAL tools (`gdalinfo`, `gdal_translate`,
#'   `gdalwarp`, `gdaladdo`) of a system GDAL built with PDF support, e.g. Homebrew
#'   `brew install gdal` on macOS.
#' @param pdf_paths character. QTopo GeoPDF files that together cover `extent`.
#' @param out_path character. Path of the GeoTIFF to write.
#' @param extent numeric, length 4. c(xmin, ymin, xmax, ymax) in `crs` units.
#' @param crs character. Target CRS, e.g. "EPSG:32755".
#' @param resolution numeric. Output pixel size in metres.
#' @param dpi numeric. Rendering resolution of the PDFs; 450 dpi gives about 3 m
#'   pixels on a 1:25k sheet.
#' @return character, the path of the GeoTIFF written. Hard `stop()`s if a PDF is
#'   missing or has no neatline, or if no system GDAL can read PDFs.
#' @author Zachary Amir
build_qtopo_basemap <- function(pdf_paths, out_path, extent, crs = "EPSG:32755",
                                resolution = 3, dpi = 450) {
  ## make sure every sheet exists before rendering any
  missing_files <- pdf_paths[!file.exists(pdf_paths)]
  if (length(missing_files) > 0) {
    stop("build_qtopo_basemap could not find: ", paste(missing_files, collapse = ", "),
         "\nCheck the QTopo file names in data/raw/.")
  } # end missing file check

  ## find the system GDAL tools
  tools_needed <- c("gdalinfo", "gdal_translate", "gdalwarp", "gdaladdo")
  tool_paths <- Sys.which(tools_needed)
  # all four must be on the PATH
  if (any(tool_paths == "")) {
    stop("build_qtopo_basemap needs the GDAL command-line tools, but could not find: ",
         paste(tools_needed[tool_paths == ""], collapse = ", "),
         "\nInstall GDAL with PDF support (macOS: brew install gdal) and restart R.")
  } # end tools check
  # and that GDAL must be able to read PDFs, not just write them
  pdf_format <- system2(tool_paths[["gdalinfo"]], c("--format", "PDF"), stdout = TRUE, stderr = TRUE)
  if (!any(grepl("HAVE_(POPPLER|PDFIUM)=YES", pdf_format))) {
    stop("The system GDAL at ", tool_paths[["gdalinfo"]], " cannot read PDFs in build_qtopo_basemap.\n",
         "Install a GDAL built with poppler or pdfium (macOS: brew install gdal).")
  } # end PDF support check

  ## a small wrapper that runs one GDAL tool and stops loudly if it fails
  run_gdal <- function(tool, args) {
    # shQuote protects paths with spaces
    out <- system2(tool_paths[[tool]], shQuote(args), stdout = TRUE, stderr = TRUE)
    # system2 attaches the exit status when the tool fails
    status <- attr(out, "status")
    if (!is.null(status) && status != 0) {
      stop(tool, " failed in build_qtopo_basemap:\n", paste(out, collapse = "\n"))
    } # end status check
    out
  } # end wrapper

  # a scratch folder for the cropped sheets, removed on exit
  tmp_dir <- tempfile("qtopo_")
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)

  # init the list of cropped sheets
  cropped <- character(0)
  # for each sheet,
  for (p in pdf_paths) {
    ## find the neatline in the PDF's metadata
    info <- paste(run_gdal("gdalinfo", p), collapse = " ")
    neatline_wkt <- regmatches(info, regexpr("NEATLINE=POLYGON \\(\\([^)]*\\)\\)", info))
    # a GeoPDF without a neatline cannot be trimmed safely
    if (length(neatline_wkt) == 0) {
      stop(basename(p), " has no NEATLINE in build_qtopo_basemap.\n",
           "Check it is a QTopo GeoPDF, or crop it by hand.")
    } # end neatline check
    # the neatline's bounding box, in the sheet's own CRS
    nb <- sf::st_bbox(sf::st_as_sfc(sub("^NEATLINE=", "", neatline_wkt)))

    ## render the sheet at the chosen dpi, cropped to the neatline
    ## (gdalwarp rather than gdal_translate, because QTopo sheets are slightly rotated)
    out <- file.path(tmp_dir, paste0(tools::file_path_sans_ext(basename(p)), ".tif"))
    run_gdal("gdalwarp",
             c("-q", "-oo", paste0("DPI=", dpi),
               # keep only the map frame, in the sheet's own CRS
               "-te", nb[["xmin"]], nb[["ymin"]], nb[["xmax"]], nb[["ymax"]],
               # mark anything outside the sheet as transparent so it never covers a neighbour
               "-dstalpha", "-r", "bilinear",
               p, out))
    cropped <- c(cropped, out)
  } # end per sheet

  ## reproject, mosaic and clip in one step, keeping transparency for the overlap
  mosaic <- file.path(tmp_dir, "mosaic.tif")
  run_gdal("gdalwarp",
           c("-q", "-overwrite",
             "-t_srs", crs,
             "-te", extent[1], extent[2], extent[3], extent[4],
             "-tr", resolution, resolution,
             # smooth resampling suits a printed map
             "-r", "bilinear",
             cropped, mosaic))

  ## keep the red, green and blue bands and compress for the phone
  run_gdal("gdal_translate",
           c("-q", "-b", "1", "-b", "2", "-b", "3",
             "-co", "COMPRESS=JPEG", "-co", "PHOTOMETRIC=YCBCR",
             "-co", "JPEG_QUALITY=85", "-co", "TILED=YES",
             mosaic, out_path))

  ## add overviews so the map pans smoothly when zoomed out
  run_gdal("gdaladdo", c("-q", "-r", "average", out_path, "2", "4", "8", "16"))

  return(out_path)
} # end function
