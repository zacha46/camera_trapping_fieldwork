#' Move Chosen Camera Sites to the Driest Spot Near Their Grid Node
#'
#' @description For each chosen point, searches every spot within `max_move` metres
#'   of it (on a `step`-metre lattice) that also lies inside `allowed_area`, and moves
#'   the point to the spot farthest from any feature in `water`. Ties go to the spot
#'   nearest the original node. The original node position is kept in `node_x` and
#'   `node_y`, and `moved_m` records how far each point moved (0 for points not
#'   moved). `x`, `y`, `dist_m` and `bearing` are recomputed from the new position.
#' @param points sf point layer with `point_id`, `x`, `y`, `dist_m` and `bearing`
#'   (output of `make_grid_design()`), in a projected CRS with metre units.
#' @param ids character. `point_id`s of the points to move.
#' @param water sf. Water features to move away from, same CRS as `points`.
#' @param max_move numeric. Furthest a point may move, metres.
#' @param allowed_area sf or sfc polygon. Where a point may go (e.g. the inset boundary).
#' @param origin numeric, length 2. Map (x, y) that `dist_m` and `bearing` are measured from.
#' @param step numeric. Lattice spacing for the search, metres.
#' @return `points` with moved geometry and columns `node_x`, `node_y`, `moved_m` and
#'   `water_dist_after_m` added. Hard `stop()`s if an ID is not found or a point has
#'   no allowed spot within `max_move`.
#' @author Zachary Amir
relocate_away_from_water <- function(points, ids, water, max_move, allowed_area,
                                     origin, step = 10) {
  ## every requested ID must exist
  missing_ids <- setdiff(ids, points$point_id)
  if (length(missing_ids) > 0) {
    stop("relocate_away_from_water could not find: ", paste(missing_ids, collapse = ", "),
         "\nCheck the IDs against the current design.")
  } # end ID check

  # remember every point's grid node before anything moves
  points$node_x <- points$x
  points$node_y <- points$y
  # nothing has moved yet
  points$moved_m <- 0
  # merge the allowed area into one shape
  allowed <- sf::st_union(sf::st_geometry(allowed_area))
  # and the water into one shape, for fast distances
  water_union <- sf::st_union(sf::st_geometry(water))

  # for each point to move,
  for (id in ids) {
    # its row and position
    r <- which(points$point_id == id)
    here_pt <- sf::st_geometry(points)[r]
    ## candidate spots: a lattice over the search circle, kept if inside both
    ## the circle and the allowed area
    circle <- sf::st_buffer(here_pt, max_move)
    cand <- sf::st_make_grid(circle, cellsize = step, what = "centers")
    cand <- cand[lengths(sf::st_intersects(cand, circle)) > 0 &
                   lengths(sf::st_intersects(cand, allowed)) > 0]
    # a point with nowhere to go is a design problem, not something to guess at
    if (length(cand) == 0) {
      stop(sprintf("relocate_away_from_water: %s has no allowed spot within %g m.\n", id, max_move),
           "Increase max_move or leave this point where it is.")
    } # end empty candidates check

    ## pick the spot farthest from water, breaking ties by staying close
    # distance from each candidate to the nearest water
    d_water <- as.numeric(sf::st_distance(cand, water_union))
    # distance from each candidate to the original node
    d_node <- as.numeric(sf::st_distance(cand, here_pt))
    # farthest from water first, then nearest the node
    best <- order(-round(d_water), d_node)[1]

    # move the point
    sf::st_geometry(points)[r] <- cand[best]
    # and record how far it went
    points$moved_m[r] <- d_node[best]
  } # end per point

  ## refresh the coordinates, distance and bearing from the new positions
  xy <- sf::st_coordinates(points)
  points$x <- xy[, "X"]
  points$y <- xy[, "Y"]
  points$dist_m <- sqrt((points$x - origin[1])^2 + (points$y - origin[2])^2)
  points$bearing <- (atan2(points$x - origin[1], points$y - origin[2]) * 180 / pi) %% 360
  # distance to water at each point's final position
  points$water_dist_after_m <- as.numeric(sf::st_distance(points, water_union))

  return(points)
} # end function
