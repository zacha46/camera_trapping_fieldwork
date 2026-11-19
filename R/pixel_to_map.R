#' Convert Image Pixel Coordinates to Projected Map Coordinates
#'
#' @description Georeferences points traced on a north-up screenshot using one
#'   anchor point whose map position is known and a single metres-per-pixel scale,
#'   assuming equal x and y scale and no rotation. Image rows count **down** from
#'   the top while map northings count **up**, so the y offset changes sign:
#'   `x_map = anchor_x + (px - anchor_px) * scale` and
#'   `y_map = anchor_y - (py - anchor_py) * scale`. This is the only place the
#'   y-down flip happens; everything downstream works in map coordinates.
#' @param px numeric. Pixel column(s), counted right from the left edge.
#' @param py numeric. Pixel row(s), counted down from the top edge.
#' @param anchor_px numeric, length 2. Pixel (column, row) of the anchor point.
#' @param anchor_map numeric, length 2. Map (easting, northing) of the anchor point,
#'   in a projected CRS with metre units.
#' @param scale numeric. Metres per pixel.
#' @return data.frame with columns `x` and `y` in map units, one row per pixel.
#'   Hard `stop()`s if `px` and `py` differ in length or `scale` is not positive.
#' @author Zachary Amir
pixel_to_map <- function(px, py, anchor_px, anchor_map, scale) {
  ## every pixel needs both a column and a row
  if (length(px) != length(py)) {
    stop("pixel_to_map received ", length(px), " columns but ", length(py), " rows.\n",
         "Supply one (px, py) pair per traced point.")
  } # end length check
  ## a zero or negative scale would collapse or mirror the map
  if (!is.numeric(scale) || length(scale) != 1 || scale <= 0) {
    stop("pixel_to_map needs a single positive scale in metres per pixel.\n",
         "Check how the scale was derived.")
  } # end scale check

  # easting grows to the right, same direction as pixel columns
  x <- anchor_map[1] + (px - anchor_px[1]) * scale
  # northing grows upward, the opposite of pixel rows, hence the minus
  y <- anchor_map[2] - (py - anchor_px[2]) * scale

  return(data.frame(x = x, y = y))
} # end function
