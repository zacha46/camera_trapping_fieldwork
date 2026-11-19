#' Build the Flux Tower Footprint Wedge and Its Buffered Zone
#'
#' @description Draws the tower's upwind source area as a wedge: from the tower out
#'   to `max_dist`, between two compass bearings (clockwise from grid north). The
#'   wind does not always blow from that arc, so the wedge is then widened by
#'   `buffer` metres all round, which also takes in a strip around the tower on its
#'   leeward side. Both shapes are returned, the wedge for display and the zone for
#'   deciding which camera sites count as footprint.
#' @param origin numeric, length 2. Map (x, y) of the tower, in `crs`.
#' @param max_dist numeric. Wedge radius, metres.
#' @param bearing numeric, length 2. Bearing range (min, max) of the wedge, degrees.
#' @param buffer numeric. Distance to widen the wedge by, metres; 0 for none.
#' @param crs integer or crs. A projected CRS with metre units.
#' @return sf with two rows, `part` = "wedge" and "zone", and a `name` for each.
#'   Hard `stop()`s if the bearings are not increasing.
#' @author Zachary Amir
make_footprint_zone <- function(origin, max_dist, bearing, buffer, crs) {
  ## the arc must run clockwise from the first bearing to the second
  if (length(bearing) != 2 || bearing[1] >= bearing[2]) {
    stop("make_footprint_zone needs bearing = c(min, max) with min < max.\n",
         "For an arc through north, split it or use bearings above 360.")
  } # end bearing check

  # bearings along the arc, one per degree, in radians
  arc <- seq(bearing[1], bearing[2], by = 1) * pi / 180
  ## start at the tower, sweep the arc clockwise, return to the tower
  ## (bearing clockwise from north: east = sin, north = cos)
  wedge_xy <- cbind(
    c(origin[1], origin[1] + max_dist * sin(arc), origin[1]),
    c(origin[2], origin[2] + max_dist * cos(arc), origin[2])
  ) # end wedge coordinates
  wedge <- sf::st_sfc(sf::st_polygon(list(wedge_xy)), crs = crs)
  # widen it by the buffer, rounding the corners
  zone <- sf::st_buffer(wedge, buffer)

  return(sf::st_sf(
    part = c("wedge", "zone"),
    name = c(sprintf("flux footprint wedge: %g-%g deg within %g km", bearing[1], bearing[2], max_dist / 1000),
             sprintf("flux footprint zone: wedge plus %g m", buffer)),
    geometry = c(wedge, zone)
  )) # end return
} # end function
