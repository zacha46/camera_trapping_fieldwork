#' Mark Nominal Camera Guide Points on Each Hectare
#'
#' @description Puts a guide point at the midpoint of each edge of every square plot
#'   (north, east, south, west). Guides are a starting point only: cameras within a
#'   plot are not independent and are placed in the field on features. The edge
#'   midpoint nearest a track is labelled the on-track guide; the rest are off-track.
#' @param hectares sf. Square plots with an ID column, projected CRS in metres.
#' @param tracks sf. Track lines and/or points, same CRS.
#' @param id_col character. Name of the plot ID column in `hectares`.
#' @param n_cameras integer. Guides to keep per plot (3 or 4). With 3, the off-track
#'   guide farthest from the track is dropped.
#' @return sf of points with columns `hectare_id`, `guide_id`, `side`, `role` and
#'   `dist_track_m`. Hard `stop()`s if `id_col` is missing or `n_cameras` is not 3 or 4.
#' @author Zachary Amir
hectare_camera_guides <- function(hectares, tracks, id_col = "hectare_id", n_cameras = 4) {
  # if the ID column is missing,
  if (!id_col %in% names(hectares)) {
    # stop because each guide must name its plot
    stop("hectare_camera_guides found no column '", id_col, "' in hectares.\n",
         "Pass the name of the plot ID column as id_col.")
  } # end id check
  # if the camera count is not one of the two allowed,
  if (!n_cameras %in% c(3, 4)) {
    # stop because a square has four edges to choose from
    stop("hectare_camera_guides takes n_cameras = 3 or 4, not ", n_cameras, ".")
  } # end camera check

  # init a list to hold each plot's guides
  per_plot <- list()
  # for each plot,
  for (i in seq_len(nrow(hectares))) {
    # grab its bounding box (squares are grid-aligned, so the box is the square)
    bb <- sf::st_bbox(hectares[i, ])
    # centre coordinates
    cx <- (bb[["xmin"]] + bb[["xmax"]]) / 2
    cy <- (bb[["ymin"]] + bb[["ymax"]]) / 2
    # the four edge midpoints
    mid <- data.frame(side = c("N", "E", "S", "W"),
                      x = c(cx, bb[["xmax"]], cx, bb[["xmin"]]),
                      y = c(bb[["ymax"]], cy, bb[["ymin"]], cy))
    # as points
    pts <- sf::st_as_sf(mid, coords = c("x", "y"), crs = sf::st_crs(hectares))
    # distance from each midpoint to the nearest track
    pts$dist_track_m <- apply(matrix(as.numeric(sf::st_distance(pts, tracks)), nrow = 4), 1, min)
    # the nearest is the on-track guide, the rest off-track
    pts$role <- ifelse(seq_len(4) == which.min(pts$dist_track_m), "on-track", "off-track")
    # with 3 cameras, drop the off-track guide farthest from the track
    if (n_cameras == 3) pts <- pts[-which.max(pts$dist_track_m), ]
    # note the plot and build a guide ID such as H2-N
    pts$hectare_id <- hectares[[id_col]][i]
    pts$guide_id <- paste0(pts$hectare_id, "-", pts$side)
    # store it
    per_plot[[i]] <- pts
  } # end per plot

  # stack every plot's guides
  guides <- do.call(rbind, per_plot)
  rownames(guides) <- NULL
  return(guides[, c("hectare_id", "guide_id", "side", "role", "dist_track_m")])
} # end function
