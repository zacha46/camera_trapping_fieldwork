#' Place a Hectare Plot Over a Fixed Point
#'
#' @description Places one square plot that must contain a given point (for example an
#'   acoustic recorder site), sliding it around the point in `step_m` steps. The square
#'   chosen is, in order of preference: crossed by a track, purest in the target
#'   vegetation subgroup, then closest to a track. Squares leaving the property are
#'   not considered.
#' @param anchor sfc. The point the square must contain, projected CRS in metres.
#' @param boundary sf. Property boundary, same CRS.
#' @param nvis sf. Subgroup polygons with column `mvs_code`, same CRS.
#' @param tracks sf. Track lines and/or points, same CRS.
#' @param subgroup_code integer. NVIS MVS code the square should represent.
#' @param size_m numeric. Side of the square, metres.
#' @param step_m numeric. How far the square slides per step, metres.
#' @return sf of one square with columns `mvs_code`, `purity`, `crossed_by_track` and
#'   `dist_track_m`. Hard `stop()`s if no square around the point fits on the property.
#' @author Zachary Amir
anchor_hectare <- function(anchor, boundary, nvis, tracks, subgroup_code, size_m = 100,
                           step_m = 25) {
  # if more than one anchor point is given,
  if (length(anchor) != 1) {
    # stop because one square is placed per point
    stop("anchor_hectare places one square per call but got ", length(anchor), " points.\n",
         "Call it once per anchor.")
  } # end anchor check

  ## every centre that keeps the anchor inside the square
  # offsets from the anchor, up to half a side in each direction
  offs <- seq(-size_m / 2, size_m / 2, by = step_m)
  # the anchor's coordinates
  xy <- sf::st_coordinates(anchor)
  # all combinations of x and y offsets, as centres
  centres <- expand.grid(x = xy[1, "X"] + offs, y = xy[1, "Y"] + offs)
  # the squares around those centres
  cand <- sf::st_sf(centres, geometry = make_hectare_squares(centres$x, centres$y,
                                                             sf::st_crs(boundary), size_m))
  # keep only squares wholly on the property
  cand <- cand[lengths(sf::st_within(cand, sf::st_union(boundary))) > 0, ]
  # if none fit,
  if (nrow(cand) == 0) {
    # stop because the anchor is too close to the boundary
    stop("anchor_hectare: no square around the anchor fits inside the property.\n",
         "Check the anchor coordinates, or move it further from the boundary.")
  } # end fit check

  ## score each square
  # does a track cross it?
  cand$crossed_by_track <- lengths(sf::st_intersects(cand, tracks)) > 0
  # how far is its nearest edge from a track (0 when crossed)?
  cand$dist_track_m <- apply(matrix(as.numeric(sf::st_distance(cand, tracks)), nrow = nrow(cand)),
                             1, min)
  # what share of it lies in the target subgroup?
  target <- sf::st_union(nvis[nvis$mvs_code == subgroup_code, ])
  cand$purity <- vapply(seq_len(nrow(cand)), function(i) {
    # area of this square inside the subgroup, as a share of the square
    piece <- suppressWarnings(sf::st_intersection(sf::st_geometry(cand)[i], target))
    if (length(piece) == 0) 0 else sum(as.numeric(sf::st_area(piece))) / size_m^2
  }, numeric(1))

  # take the best: crossed by a track first, then purest, then closest to a track
  best <- order(!cand$crossed_by_track, -cand$purity, cand$dist_track_m)[1]
  out <- cand[best, c("purity", "crossed_by_track", "dist_track_m")]
  out$mvs_code <- as.integer(subgroup_code)
  rownames(out) <- NULL
  return(out)
} # end function
