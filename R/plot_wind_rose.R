#' Draw a Wind Rose From a Sector Table
#'
#' @description Draws the output of `wind_rose_table()` as a polar bar chart, north
#'   at the top and bearings increasing clockwise, with each bar's length the
#'   percentage of half-hours the wind blew *from* that sector. An optional arrow
#'   marks the circular mean direction, its length scaled by R so a weak
#'   prevailing wind draws a short arrow.
#' @param rose data.frame. Output of `wind_rose_table()`.
#' @param title character. Plot title.
#' @param subtitle character. Plot subtitle, e.g. sample size and date range.
#' @param mean_dir data.frame or NULL. Output of `circular_mean_direction()`; if
#'   supplied, the mean direction is drawn as an arrow.
#' @return a ggplot object.
#' @author Zachary Amir
plot_wind_rose <- function(rose, title, subtitle = NULL, mean_dir = NULL) {
  ## refuse anything that does not look like a wind_rose_table() output
  if (!all(c("sector", "pct") %in% names(rose))) {
    stop("plot_wind_rose needs the columns `sector` and `pct`.\n",
         "Build the input with wind_rose_table().")
  } # end column check

  # the outer radius of the plot, a little past the longest bar
  r_max <- max(rose$pct) * 1.1

  ## plot sectors on a continuous bearing axis running from -11.25 to 348.75,
  ## so N (centred on 0) sits whole at the start and every bar lands on its bearing
  # half a sector, in degrees
  half <- 360 / nrow(rose) / 2
  # each sector's centre bearing, from the sector table
  rose$bearing <- rose$centre_deg

  ## bars, one per sector
  p <- ggplot2::ggplot(rose, ggplot2::aes(x = bearing, y = pct)) +
    # a bar the full width of its sector
    ggplot2::geom_col(width = 2 * half, fill = "#4C78A8", colour = "white", linewidth = 0.3) +
    # wrap bearings around the circle, rotated so bearing 0 points straight up
    ggplot2::coord_polar(start = -half * pi / 180, direction = 1) +
    # bearing axis spans exactly one turn, labelled with the sector names
    ggplot2::scale_x_continuous(limits = c(-half, 360 - half),
                                breaks = rose$centre_deg, labels = as.character(rose$sector)) +
    # fix the radial axis so the arrow and bars share a scale
    ggplot2::scale_y_continuous(limits = c(0, r_max)) +
    # label the radial axis as percentages
    ggplot2::labs(title = title, subtitle = subtitle, x = NULL,
                  y = "% of half-hours (wind from)") +
    # a clean theme so the sectors read clearly
    ggplot2::theme_minimal(base_size = 11) +
    # drop the radial tick labels, which crowd the north spoke,
    # and the minor spokes between sectors
    ggplot2::theme(axis.text.y = ggplot2::element_blank(),
                   panel.grid.minor = ggplot2::element_blank())

  ## add the mean direction as an arrow from the centre
  if (!is.null(mean_dir)) {
    # put the mean on the same -11.25 to 348.75 axis as the bars
    arrow_x <- ifelse(mean_dir$mean_deg >= 360 - half, mean_dir$mean_deg - 360, mean_dir$mean_deg)
    # build the arrow from the centre out to R times the outer radius
    arrow_df <- data.frame(x = arrow_x, xend = arrow_x, y = 0, yend = mean_dir$R * r_max)
    # draw it
    p <- p + ggplot2::geom_segment(
      data = arrow_df,
      ggplot2::aes(x = x, xend = xend, y = y, yend = yend),
      inherit.aes = FALSE, colour = "#E45756", linewidth = 1,
      arrow = ggplot2::arrow(length = ggplot2::unit(0.25, "cm"))
    ) # end arrow segment
  } # end mean direction condition

  return(p)
} # end function
