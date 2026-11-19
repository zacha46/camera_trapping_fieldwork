#' Assign Deployment Priority Classes to Grid Points Around a Flux Tower
#'
#' @description Labels each node from `make_grid_design()` with a status that says
#'   how to treat it in the field. Rules apply in this order, and the first that
#'   matches wins:
#'   \enumerate{
#'     \item `footprint`: the origin node itself, plus any node within
#'       `footprint_max_dist` whose bearing lies inside `footprint_bearing` (both
#'       ends inclusive). These sit in the tower's upwind source area.
#'     \item `reserve`: nodes beyond `reserve_min_dist` whose bearing lies inside
#'       `reserve_bearing`, thinned to a checkerboard by keeping only those with an
#'       odd `grid_i + grid_j`. Reserve points are deployed only if spare cameras
#'       remain.
#'     \item `drop_first`: nodes at the grid offsets listed in `drop_first_offsets`.
#'       These are the first planned cameras to give up if cameras run short.
#'     \item `core`: everything else.
#'   }
#'   Offsets rather than point IDs pick out `drop_first` nodes, so the choice
#'   survives any renumbering caused by a changed boundary.
#' @param points sf. Output of `make_grid_design()`.
#' @param footprint_max_dist numeric. Outer radius of the footprint wedge, metres.
#' @param footprint_bearing numeric, length 2. Bearing range (min, max) of the wedge.
#' @param reserve_min_dist numeric. Nodes must be farther than this to be reserve.
#' @param reserve_bearing numeric, length 2. Bearing range (min, max) of the reserve block.
#' @param drop_first_offsets data.frame with columns `grid_i` and `grid_j`, or NULL.
#' @return `points` with a `status` column added. Hard `stop()`s if a
#'   `drop_first` offset is not in the grid or is already footprint or reserve.
#' @author Zachary Amir
classify_points <- function(points,
                            footprint_max_dist,
                            footprint_bearing,
                            reserve_min_dist,
                            reserve_bearing,
                            drop_first_offsets = NULL) {
  ## refuse anything that does not look like a make_grid_design() output
  needed <- c("grid_i", "grid_j", "dist_m", "bearing")
  if (!all(needed %in% names(points))) {
    stop("classify_points needs the columns ", paste(needed, collapse = ", "), ".\n",
         "Build the points with make_grid_design().")
  } # end column check

  ## rule 1: the tower node and the upwind wedge
  is_footprint <- points$dist_m == 0 |
    (points$dist_m <= footprint_max_dist &
       points$bearing >= footprint_bearing[1] &
       points$bearing <= footprint_bearing[2])

  ## rule 2: every other node of the far downwind block, as a checkerboard
  is_reserve <- points$dist_m > reserve_min_dist &
    points$bearing >= reserve_bearing[1] &
    points$bearing <= reserve_bearing[2] &
    (points$grid_i + points$grid_j) %% 2 == 1

  ## rule 3: the named offsets
  # start with no node flagged
  is_drop_first <- rep(FALSE, nrow(points))
  # if any offsets were supplied,
  if (!is.null(drop_first_offsets)) {
    # for each offset,
    for (k in seq_len(nrow(drop_first_offsets))) {
      # find the node at that column and row
      hit <- points$grid_i == drop_first_offsets$grid_i[k] &
        points$grid_j == drop_first_offsets$grid_j[k]
      # an offset outside the grid means the boundary or spacing changed underneath it
      if (!any(hit)) {
        stop(sprintf("classify_points: drop_first offset (i = %d, j = %d) is not in the grid.\n",
                     drop_first_offsets$grid_i[k], drop_first_offsets$grid_j[k]),
             "Re-check the drop_first choice against the current design.")
      } # end missing offset check
      # a footprint or reserve node cannot also be a drop_first core node
      if (any(hit & (is_footprint | is_reserve))) {
        stop(sprintf("classify_points: drop_first offset (i = %d, j = %d) is already footprint or reserve.\n",
                     drop_first_offsets$grid_i[k], drop_first_offsets$grid_j[k]),
             "Pick a core node, or change the footprint and reserve rules.")
      } # end conflicting offset check
      # flag it
      is_drop_first <- is_drop_first | hit
    } # end per offset
  } # end drop_first condition

  ## apply the rules in priority order, with core as the default
  points$status <- dplyr::case_when(
    is_footprint ~ "footprint",
    is_reserve ~ "reserve",
    is_drop_first ~ "drop_first",
    TRUE ~ "core"
  ) # end case_when

  return(points)
} # end function
