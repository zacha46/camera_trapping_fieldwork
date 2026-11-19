#' Summarise Compass Directions With the Circular Mean and Mean Resultant Length
#'
#' @description Directions cannot be averaged arithmetically (the mean of 350 and
#'   10 degrees is 0, not 180). Each direction is treated as a unit vector, the
#'   vectors are averaged, and the angle of the average vector is the circular
#'   mean. The length of the average vector, R, runs from 0 (directions spread
#'   evenly around the compass, so the mean is meaningless) to 1 (every
#'   direction identical).
#' @param degrees numeric. Compass directions in degrees, clockwise from north.
#'   `NA` values are dropped.
#' @return data.frame with one row: `n`, `mean_deg` (0 to 360) and `R` (0 to 1).
#'   Hard `stop()`s if no non-missing directions are supplied.
#' @author Zachary Amir
circular_mean_direction <- function(degrees) {
  # drop missing directions
  degrees <- degrees[!is.na(degrees)]
  ## an empty set of directions has no mean
  if (length(degrees) == 0) {
    stop("circular_mean_direction received no non-missing directions.\n",
         "Check the filter that built the input vector.")
  } # end empty check

  # convert to radians for the trig functions
  radians <- degrees * pi / 180
  ## compass bearings run clockwise from north, so the east component is sin
  ## and the north component is cos
  # average east component of the unit vectors
  mean_east <- mean(sin(radians))
  # average north component of the unit vectors
  mean_north <- mean(cos(radians))
  # the angle of the average vector, back in compass degrees (0 to 360)
  mean_deg <- (atan2(mean_east, mean_north) * 180 / pi) %% 360
  # the length of the average vector, i.e. how concentrated the directions are
  R <- sqrt(mean_east^2 + mean_north^2)

  return(data.frame(n = length(degrees), mean_deg = mean_deg, R = R))
} # end function
