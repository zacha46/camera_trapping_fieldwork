#' Build Square Plots Around Centre Points
#'
#' @description Makes one north-aligned square polygon per centre point, `size_m` on a
#'   side. With the default 100 m this is a 1 ha plot, the size of a TERN core plot.
#'   Squares are aligned to the grid of the projected CRS (e.g. UTM), which differs
#'   from true north by under a degree at Australian latitudes.
#' @param x numeric. Easting of each centre, metres.
#' @param y numeric. Northing of each centre, metres.
#' @param crs integer or crs. Projected CRS the centres are in.
#' @param size_m numeric. Side length of each square, metres.
#' @return sfc of polygons, one per centre, in `crs`. Hard `stop()`s if `x` and `y`
#'   differ in length.
#' @author Zachary Amir
make_hectare_squares <- function(x, y, crs, size_m = 100) {
  # if the coordinate vectors do not pair up,
  if (length(x) != length(y)) {
    # stop because each square needs one easting and one northing
    stop(sprintf("make_hectare_squares got %d eastings but %d northings.", length(x), length(y)),
         "\nPass one x and one y per square.")
  } # end length check

  # half the side, the distance from centre to each edge
  h <- size_m / 2
  # build each square as a closed ring of its four corners, anticlockwise from SW
  squares <- lapply(seq_along(x), function(i) {
    ring <- rbind(c(x[i] - h, y[i] - h), c(x[i] + h, y[i] - h), c(x[i] + h, y[i] + h),
                  c(x[i] - h, y[i] + h), c(x[i] - h, y[i] - h))
    sf::st_polygon(list(ring))
  }) # end per centre

  return(sf::st_sfc(squares, crs = crs))
} # end function
