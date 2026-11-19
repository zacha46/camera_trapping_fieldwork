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
#'     \item `drop_first`: nodes at the grid offsets in `drop_first_offsets`, or
#'       flagged `TRUE` by any rule in `drop_first_flags` (e.g. near water). These
#'       are planned, but the first to give up on the day.
#'     \item `core`: everything else.
#'   }
#'   A `drop_reason` column records every reason that applies to a `drop_first`
#'   node, so the field team can see why. Offsets rather than point IDs pick out
#'   hand-chosen nodes, so the choice survives any renumbering.
#' @param points sf. Output of `make_grid_design()`.
#' @param footprint_max_dist numeric. Outer radius of the footprint wedge, metres.
#' @param footprint_bearing numeric, length 2. Bearing range (min, max) of the wedge.
#' @param reserve_min_dist numeric. Nodes must be farther than this to be reserve.
#' @param reserve_bearing numeric, length 2. Bearing range (min, max) of the reserve block.
#' @param drop_first_offsets data.frame with columns `grid_i`, `grid_j` and
#'   `reason`, or NULL.
#' @param drop_first_flags named list of logical vectors, one element per node in
#'   `points`, named by the reason (e.g. `list("within 500 m of water" = near)`), or NULL.
#' @return `points` with `status` and `drop_reason` columns added. Hard `stop()`s if
#'   a `drop_first` offset is not in the grid or is already footprint or reserve,
#'   or if a flag vector is the wrong length.
#' @author Zachary Amir
classify_points <- function(points,
                            footprint_max_dist,
                            footprint_bearing,
                            reserve_min_dist,
                            reserve_bearing,
                            drop_first_offsets = NULL,
                            drop_first_flags = NULL) {
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

  ## rule 3: hand-chosen offsets and rule-based flags, each carrying a reason
  # start with no reasons recorded for any node
  reasons <- vector("list", nrow(points))
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
      # a footprint or reserve node cannot also be a hand-chosen drop_first node
      if (any(hit & (is_footprint | is_reserve))) {
        stop(sprintf("classify_points: drop_first offset (i = %d, j = %d) is already footprint or reserve.\n",
                     drop_first_offsets$grid_i[k], drop_first_offsets$grid_j[k]),
             "Pick a core node, or change the footprint and reserve rules.")
      } # end conflicting offset check
      # record the reason against that node
      for (r in which(hit)) reasons[[r]] <- c(reasons[[r]], drop_first_offsets$reason[k])
    } # end per offset
  } # end offsets condition

  # if any rule-based flags were supplied,
  if (!is.null(drop_first_flags)) {
    # for each rule,
    for (reason in names(drop_first_flags)) {
      flag <- drop_first_flags[[reason]]
      # one flag per node, or the flags belong to a different set of points
      if (length(flag) != nrow(points)) {
        stop(sprintf("classify_points: drop_first flag '%s' has %d values for %d points.\n",
                     reason, length(flag), nrow(points)),
             "Compute the flag on the same points passed to classify_points().")
      } # end flag length check
      # record the reason against every flagged node
      for (r in which(flag)) reasons[[r]] <- c(reasons[[r]], reason)
    } # end per rule
  } # end flags condition

  # a node is drop_first if it picked up any reason
  is_drop_first <- lengths(reasons) > 0

  ## apply the rules in priority order, with core as the default
  points$status <- dplyr::case_when(
    is_footprint ~ "footprint",
    is_reserve ~ "reserve",
    is_drop_first ~ "drop_first",
    TRUE ~ "core"
  ) # end case_when

  ## list the reasons, but only where they decided the status
  points$drop_reason <- ifelse(points$status == "drop_first",
                               vapply(reasons, function(x) paste(unique(x), collapse = "; "), character(1)),
                               NA_character_)

  return(points)
} # end function
