#' Choose Track-Side Hectare Plots Within One Vegetation Stratum
#'
#' @description Searches a lattice of candidate 1 ha squares and picks `n_needed` of
#'   them for one vegetation subgroup, following these rules:
#'   \enumerate{
#'     \item a candidate lies wholly inside the property and a track feature crosses
#'       it (a track line intersects it, or a track point lies inside it). A crossed
#'       square has its edge within 0 m of a track, and no part of it is more than
#'       about 141 m from that track, so it can be walked from the track;
#'     \item its purity is the share of its area mapped as the target subgroup;
#'       candidates below `min_purity` are used only if too few reach it;
#'     \item it may not overlap a hectare already placed (`existing`);
#'     \item replicates of one subgroup sit about `target_spacing_m` apart. With no
#'       replicate yet placed and two needed, every pair is scored at once; otherwise
#'       each new square is scored against the nearest replicate already placed.
#'       Scores are |spacing - target| rounded to 100 m, then highest mean purity,
#'       then shortest distance from `origin` (closest to the base comes first).
#'   }
#' @param boundary sf. Property boundary, projected CRS in metres.
#' @param nvis sf. Subgroup polygons with column `mvs_code`, same CRS.
#' @param tracks sf. Track lines and/or points, same CRS.
#' @param subgroup_code integer. The NVIS MVS code to sample.
#' @param n_needed integer. How many hectares to choose.
#' @param origin sfc. One point (e.g. the flux tower) used to break ties.
#' @param existing sf or NULL. Hectares already placed, with column `mvs_code`.
#' @param size_m numeric. Side of each square, metres.
#' @param lattice_m numeric. Spacing of candidate centres, metres.
#' @param min_purity numeric. Purity a candidate should reach, 0 to 1.
#' @param target_spacing_m numeric. Wanted distance between replicates, metres.
#' @param require_track logical. If `FALSE`, rule 1 drops its track condition, so any
#'   square wholly inside the property is a candidate; `tracks` is then unused. Use it
#'   only where a subgroup has no track and access is checked another way.
#' @return sf of `n_needed` squares with columns `mvs_code`, `purity`,
#'   `meets_min_purity` and `dist_origin_m`. Hard `stop()`s if fewer than `n_needed`
#'   candidates exist.
#' @author Zachary Amir
select_hectares <- function(boundary, nvis, tracks, subgroup_code, n_needed, origin,
                            existing = NULL, size_m = 100, lattice_m = 25, min_purity = 0.75,
                            target_spacing_m = 1000, require_track = TRUE) {
  # if the boundary is in degrees,
  if (sf::st_is_longlat(boundary)) {
    # stop because the lattice is laid out in metres
    stop("select_hectares needs every layer in a projected CRS in metres (e.g. UTM).\n",
         "Transform the inputs with sf::st_transform() first.")
  } # end CRS check
  # if the subgroup is not on the vegetation map,
  if (!subgroup_code %in% nvis$mvs_code) {
    # stop because no square could be scored
    stop("select_hectares: subgroup ", subgroup_code, " is not in the nvis layer.\n",
         "Check the eligible subgroup list.")
  } # end subgroup check
  # if nothing is needed, return an empty layer straight away
  if (n_needed < 1) return(NULL)

  #
  ##
  ### Lay out candidate squares that a track crosses ----

  # merge the property into one shape
  prop <- sf::st_union(boundary)
  # lattice of candidate centres across the property's bounding box
  bb <- sf::st_bbox(prop)
  xs <- seq(bb[["xmin"]] + size_m / 2, bb[["xmax"]] - size_m / 2, by = lattice_m)
  ys <- seq(bb[["ymin"]] + size_m / 2, bb[["ymax"]] - size_m / 2, by = lattice_m)
  # every combination of x and y, as a table of centres
  centres <- expand.grid(x = xs, y = ys)
  # as points
  centre_pts <- sf::st_as_sf(centres, coords = c("x", "y"), crs = sf::st_crs(boundary), remove = FALSE)

  ## keep centres close enough to a track that the square could touch it
  # if the access rule applies,
  if (require_track) {
    # a square reaches at most half a diagonal (~71 m for 100 m) from its centre
    near <- lengths(sf::st_is_within_distance(centre_pts, tracks, dist = size_m / sqrt(2))) > 0
    centres <- centres[near, ]
    # if no centre is near a track,
    if (nrow(centres) == 0) {
      # stop because no square can meet the access rule
      stop("select_hectares found no candidate square near any track.\n",
           "Check that the tracks layer overlaps the property.")
    } # end near check
  } # end access rule condition

  # build the candidate squares
  cand <- sf::st_sf(centres, geometry = make_hectare_squares(centres$x, centres$y,
                                                             sf::st_crs(boundary), size_m))
  # keep squares wholly inside the property
  cand <- cand[lengths(sf::st_within(cand, prop)) > 0, ]
  # keep squares a track feature actually crosses, if the access rule applies
  if (require_track) cand <- cand[lengths(sf::st_intersects(cand, tracks)) > 0, ]
  # drop squares that overlap a hectare already placed
  if (!is.null(existing) && nrow(existing) > 0) {
    cand <- cand[lengths(sf::st_intersects(cand, existing)) == 0, ]
  } # end existing condition

  ## score purity: the share of each square mapped as the target subgroup
  # the target subgroup's polygons, merged
  target <- sf::st_union(nvis[nvis$mvs_code == subgroup_code, ])
  # give each square a row number so overlaps can be matched back to it
  cand$cid <- seq_len(nrow(cand))
  # cut each square to the part inside the subgroup (squares with no overlap drop out)
  overlap <- suppressWarnings(sf::st_intersection(cand[, "cid"], sf::st_sf(geometry = target)))
  # start every square at zero purity
  cand$purity <- 0
  # and fill in the overlap area as a share of the square, matched by row number
  cand$purity[overlap$cid] <- as.numeric(sf::st_area(overlap)) / size_m^2
  # distance from the origin, used to break ties
  cand$dist_origin_m <- as.numeric(sf::st_distance(sf::st_centroid(sf::st_geometry(cand)), origin))
  # keep only squares that touch the subgroup at all
  cand <- cand[cand$purity > 0, ]

  ## prefer squares that reach the minimum purity, if there are enough
  cand$meets_min_purity <- cand$purity >= min_purity
  # if enough squares reach the minimum,
  if (sum(cand$meets_min_purity) >= n_needed) {
    # keep only those
    cand <- cand[cand$meets_min_purity, ]
  } # end purity filter
  # if there are still too few candidates,
  if (nrow(cand) < n_needed) {
    # stop because the subgroup cannot be sampled under the access rule
    stop(sprintf("select_hectares found %d candidate square(s) for subgroup %d but needs %d.",
                 nrow(cand), subgroup_code, n_needed),
         "\nAdd tracks in this subgroup, or relax min_purity or the access rule.")
  } # end candidate count check

  #
  ##
  ### Pick the replicates ----

  # the replicates of this subgroup already placed
  same <- if (is.null(existing)) NULL else existing[existing$mvs_code == subgroup_code, ]
  # init the chosen rows
  chosen <- integer(0)

  # if two are needed and none are placed yet, score every pair together
  if (n_needed == 2 && (is.null(same) || nrow(same) == 0)) {
    # distances between every pair of candidate centres
    d <- as.matrix(stats::dist(cand[, c("x", "y"), drop = TRUE]))
    # every pair once (upper triangle)
    pairs <- which(upper.tri(d), arr.ind = TRUE)
    # keep pairs far enough apart that the squares cannot overlap
    pairs <- pairs[d[pairs] >= size_m * sqrt(2), , drop = FALSE]
    # if no two candidates are far enough apart,
    if (nrow(pairs) == 0) {
      # stop because two hectares here would overlap
      stop("select_hectares: every pair of candidates for subgroup ", subgroup_code,
           " overlaps.\nAdd tracks in this subgroup, relax the access rule, or ask for one hectare.")
    } # end pair check
    # score each pair: closeness to the target spacing, in 100 m steps
    off <- round(abs(d[pairs] - target_spacing_m) / 100)
    # then mean purity, highest first
    pur <- (cand$purity[pairs[, 1]] + cand$purity[pairs[, 2]]) / 2
    # then mean distance from the origin, nearest first
    org <- (cand$dist_origin_m[pairs[, 1]] + cand$dist_origin_m[pairs[, 2]]) / 2
    # take the best-scoring pair
    best <- order(off, -pur, org)[1]
    chosen <- unname(pairs[best, ])
  } else {
    # otherwise add squares one at a time
    for (k in seq_len(n_needed)) {
      # start an empty set of placed replicates
      placed <- sf::st_sfc(crs = sf::st_crs(boundary))
      # add the ones placed before this call
      if (!is.null(same) && nrow(same) > 0) placed <- c(placed, sf::st_geometry(same))
      # and the ones chosen earlier in this loop
      if (length(chosen) > 0) placed <- c(placed, sf::st_geometry(cand[chosen, ]))
      # candidates not yet chosen and not overlapping a chosen square
      free <- setdiff(seq_len(nrow(cand)), chosen)
      if (length(chosen) > 0) {
        free <- free[lengths(sf::st_intersects(cand[free, ], cand[chosen, ])) == 0]
      } # end overlap condition
      # if no candidate is left,
      if (length(free) == 0) {
        # stop because the next hectare would overlap one already chosen
        stop(sprintf("select_hectares placed %d of %d hectares for subgroup %d; the rest overlap.",
                     length(chosen), n_needed, subgroup_code),
             "\nAdd tracks in this subgroup, relax the access rule, or ask for fewer hectares.")
      } # end free check
      # if no replicate is placed yet, spacing cannot be scored
      if (length(placed) == 0) {
        # so take the purest, nearest the origin
        pick <- free[order(-cand$purity[free], cand$dist_origin_m[free])[1]]
      } else {
        # distances from each free candidate's centre to each placed replicate's centre
        dmat <- matrix(as.numeric(sf::st_distance(sf::st_centroid(sf::st_geometry(cand[free, ])),
                                                  sf::st_centroid(placed))),
                       nrow = length(free))
        # keep the distance to the nearest one
        dn <- apply(dmat, 1, min)
        # score as for pairs: spacing, then purity, then distance from the origin
        off <- round(abs(dn - target_spacing_m) / 100)
        pick <- free[order(off, -cand$purity[free], cand$dist_origin_m[free])[1]]
      } # end placed condition
      # store the pick
      chosen <- c(chosen, pick)
    } # end per square needed
  } # end pair vs one-at-a-time

  # return the chosen squares with their scores
  out <- cand[chosen, c("purity", "meets_min_purity", "dist_origin_m")]
  out$mvs_code <- rep(as.integer(subgroup_code), nrow(out))
  rownames(out) <- NULL
  return(out)
} # end function
