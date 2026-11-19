#' Rank Backup Camera Sites by Safety, Then by Spatial Coverage Gained
#'
#' @description Orders backup sites so the field team can fill them top-down once
#'   every planned site has a camera. Sites are ranked in three tiers:
#'   \enumerate{
#'     \item backups that are not flagged unsafe (`unsafe_col` is `FALSE`), then
#'     \item flagged backups, then
#'     \item any backups named in `last_ids`, in the order given.
#'   }
#'   Within each of the first two tiers the ranking is greedy: at each step, the
#'   site that most enlarges the minimum convex polygon (MCP) of the cameras already
#'   placed (all planned sites plus backups ranked so far) comes next. Sites whose
#'   gain is within `tie_km2` of the best count as ties, such as interior sites that
#'   add no area, and go to the site farthest from water (`tie_col`, larger first).
#' @param points sf point layer with `point_id` and `status`, in a projected CRS.
#' @param planned_status character. Statuses that are always deployed.
#' @param backup_status character. The status that marks backup sites.
#' @param unsafe_col character. Logical column; `TRUE` sends a site to the second tier.
#' @param tie_col character. Numeric column used to break ties, larger first.
#' @param last_ids character or NULL. Backup IDs to rank after everything else.
#' @param tie_km2 numeric. MCP gains within this many km2 of the best count as ties
#'   (default 0.01 km2, i.e. 1 ha).
#' @return `points` with `backup_rank` (1 = first to fill; NA for planned sites) and
#'   `mcp_after_km2` (MCP of planned sites plus backups up to this rank) added.
#'   Hard `stop()`s if a `last_ids` entry is not a backup site.
#' @author Zachary Amir
rank_backup_sites <- function(points, planned_status = c("footprint", "main"),
                              backup_status = "backup", unsafe_col = "near_water",
                              tie_col = "water_dist_after_m", last_ids = NULL,
                              tie_km2 = 0.01) {
  ## last_ids must all be backups
  not_backup <- setdiff(last_ids, points$point_id[points$status == backup_status])
  if (length(not_backup) > 0) {
    stop("rank_backup_sites: last_ids are not backup sites: ", paste(not_backup, collapse = ", "),
         "\nOnly backup sites can be ranked.")
  } # end last_ids check

  # MCP area in km2 of a set of points
  mcp_km2 <- function(p) as.numeric(sf::st_area(sf::st_convex_hull(sf::st_union(p)))) / 1e6

  # cameras placed so far: every planned site
  placed <- sf::st_geometry(points)[points$status %in% planned_status]
  # init the ranked list of IDs and the MCP after each
  ranked <- character(0)
  mcp_after <- numeric(0)

  ## the three tiers of backups, as sets of IDs
  backups <- points[points$status == backup_status & !points$point_id %in% last_ids, ]
  tiers <- list(backups$point_id[!backups[[unsafe_col]]],
                backups$point_id[backups[[unsafe_col]]])

  # for each of the first two tiers,
  for (tier in tiers) {
    # the sites still to rank in this tier
    remaining <- tier
    # until every site in the tier is ranked,
    while (length(remaining) > 0) {
      # MCP if each remaining site were added next
      gain <- vapply(remaining, function(id) {
        mcp_km2(c(placed, sf::st_geometry(points)[points$point_id == id]))
      }, numeric(1))
      # its tie-break value (farther from water wins)
      tie <- points[[tie_col]][match(remaining, points$point_id)]
      ## sites within tie_km2 of the biggest MCP count as equal; of those, the one
      ## farthest from water wins, so a sliver of extra area never outranks safety
      contenders <- which(gain >= max(gain) - tie_km2)
      pick <- remaining[contenders[order(-tie[contenders])[1]]]
      # place it
      placed <- c(placed, sf::st_geometry(points)[points$point_id == pick])
      ranked <- c(ranked, pick)
      mcp_after <- c(mcp_after, mcp_km2(placed))
      # and take it off the list
      remaining <- setdiff(remaining, pick)
    } # end while sites remain
  } # end per tier

  ## the named sites go last, in the order given
  for (id in last_ids) {
    placed <- c(placed, sf::st_geometry(points)[points$point_id == id])
    ranked <- c(ranked, id)
    mcp_after <- c(mcp_after, mcp_km2(placed))
  } # end per last id

  ## write the ranks back onto the points
  points$backup_rank <- match(points$point_id, ranked)
  points$mcp_after_km2 <- mcp_after[points$backup_rank]

  return(points)
} # end function
