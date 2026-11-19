#' Tabulate Wind Directions Into Compass Sectors
#'
#' @description Assigns each wind direction to one of 16 compass sectors of 22.5
#'   degrees, each centred on its named bearing (so N covers 348.75 to 11.25
#'   degrees), and returns the count and percentage in each. Sectors with no
#'   observations are kept with zero, so the table always has 16 rows in compass
#'   order. Directions are where the wind blows *from*, as OzFlux records them.
#' @param degrees numeric. Wind directions in degrees, 0 to 360. `NA` is dropped.
#' @return data.frame with columns `sector` (factor, N to NNW), `centre_deg`, `n`
#'   and `pct`. Hard `stop()`s if any direction is outside 0 to 360.
#' @author Zachary Amir
wind_rose_table <- function(degrees) {
  # drop missing directions
  degrees <- degrees[!is.na(degrees)]
  ## a direction outside the compass means the input was not filtered
  if (any(degrees < 0 | degrees > 360)) {
    stop("wind_rose_table received directions outside 0 to 360 degrees.\n",
         "Filter to valid directions before tabulating.")
  } # end range check

  # the 16 sector names in clockwise order from north
  sector_names <- c("N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                    "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW")
  # each sector is 22.5 degrees wide
  width <- 360 / length(sector_names)

  ## shift by half a sector so N is centred on 0, then count whole sectors
  # e.g. 355 deg shifts to 6.25, which falls in sector 1 (N)
  sector_index <- floor(((degrees + width / 2) %% 360) / width) + 1
  # label each direction with its sector name, keeping compass order
  sector <- factor(sector_names[sector_index], levels = sector_names)

  ## count per sector, keeping empty sectors as zero
  counts <- as.vector(table(sector))
  rose <- data.frame(
    # sector name in compass order
    sector = factor(sector_names, levels = sector_names),
    # the bearing each sector is centred on
    centre_deg = (seq_along(sector_names) - 1) * width,
    # number of half-hours in the sector
    n = counts,
    # and its share of all half-hours
    pct = 100 * counts / sum(counts)
  ) # end rose table

  return(rose)
} # end function
