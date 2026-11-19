#' Lay a Square Sampling Grid Over a Study Area
#'
#' @description Builds a square grid of candidate camera points with one node exactly
#'   on an origin (e.g. a flux tower), then keeps the nodes that fall inside the
#'   study-area boundary shrunk inward by `inset` metres. The inset leaves room to
#'   place each camera on the best tree within that distance of its node without
#'   crossing the boundary. For each kept node it records the grid offsets from the
#'   origin (`grid_i` columns east, `grid_j` rows north), the distance from the
#'   origin, and the bearing from the origin in degrees clockwise from grid north.
#'   Nodes are numbered north to south, then west to east within a row.
#' @param boundary sf or sfc polygon in a projected CRS with metre units.
#' @param origin numeric, length 2. Map (x, y) of the node the grid is anchored to,
#'   in the boundary's CRS.
#' @param spacing numeric. Distance between neighbouring nodes, metres.
#' @param inset numeric. Distance to shrink the boundary inward before keeping nodes,
#'   metres. Use 0 to keep every node inside the boundary.
#' @param id_prefix character. Prefix for point IDs, e.g. "FV" gives FV01, FV02, ...
#' @return sf point layer in the boundary's CRS with columns `point_id`, `grid_i`,
#'   `grid_j`, `x`, `y`, `dist_m` and `bearing`. Hard `stop()`s if the boundary is
#'   not projected or no node survives.
#' @author Zachary Amir
make_grid_design <- function(boundary, origin, spacing, inset = 0, id_prefix = "P") {
  ## distances and bearings only make sense in a metre-based projection
  if (sf::st_is_longlat(boundary)) {
    stop("make_grid_design needs the boundary in a projected CRS (metres), not lon/lat.\n",
         "Transform it first, e.g. sf::st_transform(boundary, 32755) for UTM 55S.")
  } # end projection check

  # merge the boundary into one shape, in case it arrives in pieces
  boundary <- sf::st_union(sf::st_geometry(boundary))
  # shrink it inward so every node has room around it
  inner <- sf::st_buffer(boundary, -inset)

  ## how many grid steps are needed in each direction to cover the boundary
  bb <- sf::st_bbox(boundary)
  # columns west and east of the origin
  i_range <- floor((bb[["xmin"]] - origin[1]) / spacing):ceiling((bb[["xmax"]] - origin[1]) / spacing)
  # rows south and north of the origin
  j_range <- floor((bb[["ymin"]] - origin[2]) / spacing):ceiling((bb[["ymax"]] - origin[2]) / spacing)

  ## every combination of column and row offsets is a candidate node
  nodes <- expand.grid(grid_i = i_range, grid_j = j_range)
  # node easting
  nodes$x <- origin[1] + nodes$grid_i * spacing
  # node northing
  nodes$y <- origin[2] + nodes$grid_j * spacing

  ## turn candidates into points and keep those inside the shrunken boundary
  nodes <- sf::st_as_sf(nodes, coords = c("x", "y"), crs = sf::st_crs(boundary), remove = FALSE)
  inside <- lengths(sf::st_intersects(nodes, inner)) > 0
  nodes <- nodes[inside, ]
  # stop rather than return an empty design
  if (nrow(nodes) == 0) {
    stop(sprintf("make_grid_design kept no nodes with spacing %g m and inset %g m.\n", spacing, inset),
         "Check the boundary and origin share a CRS, or reduce the spacing or inset.")
  } # end empty design check

  ## distance and bearing of each node from the origin
  # offsets east and north of the origin
  dx <- nodes$x - origin[1]
  dy <- nodes$y - origin[2]
  # straight-line distance
  nodes$dist_m <- sqrt(dx^2 + dy^2)
  ## bearing clockwise from grid north: atan2(east, north), wrapped to 0-360
  nodes$bearing <- (atan2(dx, dy) * 180 / pi) %% 360

  ## number the nodes north to south, then west to east
  nodes <- nodes |>
    # highest northing first, then lowest easting
    dplyr::arrange(dplyr::desc(y), x) |>
    # zero-padded IDs so they sort correctly as text
    dplyr::mutate(point_id = sprintf("%s%02d", id_prefix, dplyr::row_number())) |>
    # put the ID first
    dplyr::relocate(point_id)

  return(nodes)
} # end function
