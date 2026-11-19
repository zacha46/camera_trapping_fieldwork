#' Sort Grid Points Into Footprint, Main and Backup Sites Around a Flux Tower
#'
#' @description Labels each node from `make_grid_design()` with a field status.
#'   Rules apply in this order, and the first that matches wins:
#'   \enumerate{
#'     \item `footprint`: the origin node itself, plus any node within
#'       `footprint_max_dist` whose bearing lies inside `footprint_bearing` (both
#'       ends inclusive). These sit in the tower's upwind source area and are always
#'       planned, whatever other rule they also meet.
#'     \item `backup`: a node that meets any backup rule: (a) beyond `thin_min_dist`
#'       inside `thin_bearing` with an odd `grid_i + grid_j`, i.e. every other node of
#'       a block thinned to a checkerboard; (b) at a grid offset in `backup_offsets`;
#'       (c) flagged `TRUE` by any rule in `backup_flags` (e.g. near water). Backups
#'       are filled in rank order once every planned site has a camera.
#'     \item `main`: everything else; always planned.
#'   }
#'   A `backup_reason` column lists every backup rule a node meets. Offsets rather
#'   than point IDs pick out hand-chosen nodes, so the choice survives renumbering.
#' @param points sf. Output of `make_grid_design()`.
#' @param footprint_max_dist numeric. Outer radius of the footprint wedge, metres.
#' @param footprint_bearing numeric, length 2. Bearing range (min, max) of the wedge.
#' @param thin_min_dist numeric. Nodes must be farther than this to be thinned.
#' @param thin_bearing numeric, length 2. Bearing range (min, max) of the thinned block.
#' @param thin_reason character. Reason recorded for thinned nodes.
#' @param backup_offsets data.frame with columns `grid_i`, `grid_j` and `reason`, or NULL.
#' @param backup_flags named list of logical vectors, one element per node, named by
#'   the reason (e.g. `list("within 500 m of water" = near)`), or NULL.
#' @return `points` with `status` and `backup_reason` columns added. Hard `stop()`s if
#'   an offset is not in the grid or is a footprint node, or if a flag vector is the
#'   wrong length.
#' @author Zachary Amir
classify_points <- function(points,
                            footprint_max_dist,
                            footprint_bearing,
                            thin_min_dist,
                            thin_bearing,
                            thin_reason = "checkerboard thinning",
                            backup_offsets = NULL,
                            backup_flags = NULL) {
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

  ## rule 2: collect every backup reason that applies to each node
  # start with no reasons recorded for any node
  reasons <- vector("list", nrow(points))

  ## (a) every other node of the thinned block, as a checkerboard
  is_thinned <- points$dist_m > thin_min_dist &
    points$bearing >= thin_bearing[1] &
    points$bearing <= thin_bearing[2] &
    (points$grid_i + points$grid_j) %% 2 == 1
  for (r in which(is_thinned)) reasons[[r]] <- c(reasons[[r]], thin_reason)

  ## (b) hand-chosen offsets
  if (!is.null(backup_offsets)) {
    # for each offset,
    for (k in seq_len(nrow(backup_offsets))) {
      # find the node at that column and row
      hit <- points$grid_i == backup_offsets$grid_i[k] &
        points$grid_j == backup_offsets$grid_j[k]
      # an offset outside the grid means the boundary or spacing changed underneath it
      if (!any(hit)) {
        stop(sprintf("classify_points: backup offset (i = %d, j = %d) is not in the grid.\n",
                     backup_offsets$grid_i[k], backup_offsets$grid_j[k]),
             "Re-check the backup choice against the current design.")
      } # end missing offset check
      # footprint nodes are always planned, so naming one as backup is a mistake
      if (any(hit & is_footprint)) {
        stop(sprintf("classify_points: backup offset (i = %d, j = %d) is a footprint node.\n",
                     backup_offsets$grid_i[k], backup_offsets$grid_j[k]),
             "Footprint nodes are always planned; pick another node.")
      } # end footprint offset check
      # record the reason against that node
      for (r in which(hit)) reasons[[r]] <- c(reasons[[r]], backup_offsets$reason[k])
    } # end per offset
  } # end offsets condition

  ## (c) rule-based flags
  if (!is.null(backup_flags)) {
    # for each rule,
    for (reason in names(backup_flags)) {
      flag <- backup_flags[[reason]]
      # one flag per node, or the flags belong to a different set of points
      if (length(flag) != nrow(points)) {
        stop(sprintf("classify_points: backup flag '%s' has %d values for %d points.\n",
                     reason, length(flag), nrow(points)),
             "Compute the flag on the same points passed to classify_points().")
      } # end flag length check
      # record the reason against every flagged node
      for (r in which(flag)) reasons[[r]] <- c(reasons[[r]], reason)
    } # end per rule
  } # end flags condition

  ## apply the rules in priority order, with main as the default
  points$status <- dplyr::case_when(
    is_footprint ~ "footprint",
    lengths(reasons) > 0 ~ "backup",
    TRUE ~ "main"
  ) # end case_when

  ## list the reasons, but only where they decided the status
  points$backup_reason <- ifelse(points$status == "backup",
                                 vapply(reasons, function(x) paste(unique(x), collapse = "; "), character(1)),
                                 NA_character_)

  return(points)
} # end function
