#' Read Wind, Radiation and CO2 Flux Series From OzFlux L3 netCDF Files
#'
#' @description Reads one or more OzFlux L3 netCDF files (one site, 30-minute time
#'   step) and stacks them into a single data frame. Only the variables needed to
#'   describe the flux footprint are kept: wind direction and speed with the wind
#'   QC flag, incoming shortwave radiation (to split day from night), and the CO2
#'   flux with its QC flag. OzFlux codes missing values as -9999 without declaring
#'   it in the file, so those are converted to `NA`. Timestamps are converted to
#'   POSIXct in the time zone the file declares (OzFlux uses local standard time).
#'   Rows with a timestamp already seen in an earlier file are dropped, so
#'   overlapping annual files do not double count.
#' @param paths character. Paths to the `.nc` files, in any order.
#' @param variables character. Variables to read. Each must exist in every file.
#' @return data.frame with a `datetime` column, one column per variable, and a
#'   `source_file` column, sorted by time. Hard `stop()`s if a file is missing or
#'   lacks a requested variable.
#' @author Zachary Amir
read_ozflux_wind <- function(paths,
                             variables = c("Wd", "Ws", "Wd_QCFlag", "Fsd",
                                           "Fco2", "Fco2_QCFlag")) {
  ## make sure every file exists before opening any of them
  missing_files <- paths[!file.exists(paths)]
  if (length(missing_files) > 0) {
    stop("read_ozflux_wind could not find: ", paste(missing_files, collapse = ", "),
         "\nCheck the file names in the campaign's data/raw/ folder.")
  } # end missing file check

  # init an empty list to hold one data frame per file
  per_file <- list()

  # for each netCDF file,
  for (p in paths) {
    # open a connection to the file
    nc <- ncdf4::nc_open(p)

    ## refuse a file that is missing any variable we need
    absent <- setdiff(variables, names(nc$var))
    if (length(absent) > 0) {
      # close the connection before stopping so the file is not left locked
      ncdf4::nc_close(nc)
      stop(basename(p), " is missing variables in read_ozflux_wind: ",
           paste(absent, collapse = ", "),
           "\nCheck it is an OzFlux L3 file, or drop those from `variables`.")
    } # end absent variable check

    ## OzFlux time is "days since 1800-01-01" in the site's local standard time
    # read the raw time values
    time_days <- as.vector(ncdf4::ncvar_get(nc, "time"))
    # grab the time zone the file declares, e.g. Australia/Brisbane
    tz <- ncdf4::ncatt_get(nc, 0, "time_zone")$value
    # convert days to seconds and add to the 1800 origin, in that time zone
    datetime <- as.POSIXct("1800-01-01 00:00:00", tz = tz) + round(time_days * 86400)

    # start this file's table with the timestamps
    df <- data.frame(datetime = datetime)
    # for each requested variable,
    for (v in variables) {
      # read it as a plain vector (the lat and lon dimensions are length one)
      values <- as.vector(ncdf4::ncvar_get(nc, v))
      # turn the OzFlux missing code into a real NA
      values[values == -9999] <- NA
      # and add it as a column
      df[[v]] <- values
    } # end per variable

    # note which file each row came from
    df$source_file <- basename(p)
    # close the connection
    ncdf4::nc_close(nc)
    # and store this file's table
    per_file[[p]] <- df
  } # end per file

  ## stack the files into one table
  wind <- per_file |>
    # bind all files' rows together
    dplyr::bind_rows() |>
    # put them in time order
    dplyr::arrange(datetime) |>
    # keep the first copy of any timestamp that appears in two files
    dplyr::distinct(datetime, .keep_all = TRUE)

  # drop the row names bind_rows inherits from the list names
  rownames(wind) <- NULL
  return(wind)
} # end function
