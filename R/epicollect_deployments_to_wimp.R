#' Turn an EpiCollect Deployment Export Into WIMP Upload Rows
#'
#' @description Reads the CSV that EpiCollect5 exports from the camera deployment form
#'   (`epicollect/deployment/`) and returns three tables:
#'   \enumerate{
#'     \item `wimp`: the 25 `WIMP_COLUMNS` of the WildObs bulk-upload record, in their
#'       exact order, one row per deployment. This is the shape that
#'       `sync_wimp_deployments()` and `post_wimp_deployment()` in the camDB
#'       `code_monitor_crosswalk` take, and the shape the WIMP bulk CSV uploader takes.
#'     \item `full`: every value the form holds, under Camtrap DP names where one exists,
#'       for the camDB record. It adds what WIMP has no field for: `deploymentID`,
#'       `coordinateUncertainty`, the EpiCollect UUID and the two photo URLs.
#'     \item `qc`: one row per check, with the number of deployments it flagged.
#'   }
#'   The form records local wall-clock time. `deploymentStart` is converted to UTC and
#'   `utcOffset` is filled from `tz`, because the WIMP post sends the start time as UTC
#'   without shifting it. A form answer outside the lookup tables, a missing GPS fix,
#'   or a duplicated location ID stops the function, since each would either fail the
#'   post or create the wrong record.
#' @param path character. Path to the EpiCollect CSV export.
#' @param deployment_groups character. One or more WIMP deployment group labels given to
#'   every row, e.g. `"Fletcherview_2026-11"`. Unseen labels create new project groups.
#' @param tz character. Olson time zone the field team set the date and time in.
#' @param max_gps_accuracy_m numeric. GPS fixes less precise than this are flagged.
#' @param max_entry_lag_hours numeric. Entries created this long before or after the
#'   deployment start they record are flagged, which catches a mistyped date or time.
#' @return list of three data.frames: `wimp`, `full` and `qc`. Hard `stop()`s on an
#'   unreadable or changed form, a missing or invalid required answer, a missing GPS
#'   fix, or a duplicated location ID.
#' @author Zachary Amir
epicollect_deployments_to_wimp <- function(path, deployment_groups,
                                           tz = "Australia/Brisbane",
                                           max_gps_accuracy_m = 30,
                                           max_entry_lag_hours = 12) {
  # if the export is not where we were told,
  if (!file.exists(path)) {
    # stop because there is nothing to read
    stop("epicollect_deployments_to_wimp: no file at ", path, ".\n",
         "Download the CSV from the EpiCollect project and put it in data/raw/.")
  } # end file check

  # if no deployment group was given,
  if (missing(deployment_groups) || length(deployment_groups) == 0 ||
      any(is.na(deployment_groups)) || any(!nzchar(deployment_groups))) {
    # stop because every deployment needs one to be found again in WIMP
    stop("epicollect_deployments_to_wimp: deployment_groups is empty.\n",
         "Give at least one group label, e.g. 'Fletcherview_2026-11'.")
  } # end groups check

  # if the time zone is not one R knows,
  if (!tz %in% OlsonNames()) {
    # stop because the UTC conversion would quietly use UTC instead
    stop("epicollect_deployments_to_wimp: '", tz, "' is not an Olson time zone.\n",
         "Use a name from OlsonNames(), e.g. 'Australia/Brisbane'.")
  } # end tz check


  #
  ##
  ### First, read the export and give its columns stable names ----

  ## EpiCollect writes a byte-order mark and truncated, numbered headers; keep every
  ## cell as text so serial numbers and SD card numbers keep their leading zeros
  raw <- utils::read.csv(path, fileEncoding = "UTF-8-BOM", colClasses = "character",
                         check.names = FALSE, na.strings = "")

  # if the export holds no entries,
  if (nrow(raw) == 0) {
    # stop because there is nothing to upload
    stop("epicollect_deployments_to_wimp: ", basename(path), " has no entries.\n",
         "Check that the right form was exported.")
  } # end empty check

  # drop the question numbers so a reordered form still matches
  stems <- .epicollect_header_stem(names(raw))
  # find which stems this export is missing
  missing_stems <- setdiff(.EPICOLLECT_DEPLOYMENT_COLUMNS, stems)
  # if any expected question is gone,
  if (length(missing_stems) > 0) {
    # stop because the form has changed since the lookup was written
    stop("epicollect_deployments_to_wimp: the export has no column for: ",
         paste(missing_stems, collapse = ", "), ".\n",
         "The form has changed: update .EPICOLLECT_DEPLOYMENT_COLUMNS to match it.")
  } # end missing stem check

  # rename each expected column to its internal name
  names(raw) <- ifelse(stems %in% .EPICOLLECT_DEPLOYMENT_COLUMNS,
                       names(.EPICOLLECT_DEPLOYMENT_COLUMNS)[
                         match(stems, .EPICOLLECT_DEPLOYMENT_COLUMNS)],
                       names(raw))
  # trim stray spaces typed into the text answers
  raw[] <- lapply(raw, function(x) trimws(x))
  # and treat an answer that trimmed to nothing as missing
  raw[] <- lapply(raw, function(x) ifelse(!is.na(x) & !nzchar(x), NA_character_, x))

  # find required answers EpiCollect should never have let through empty
  required <- c("locationID", "start_date", "start_time", "clock_ok",
                "feature_label", "bait_label", "cameraHeight", "cameraHeading")
  # count the blanks in each
  n_blank <- vapply(required, function(col) sum(is.na(raw[[col]])), integer(1))
  # if any required answer is blank,
  if (any(n_blank > 0)) {
    # stop because the post or the Camtrap DP record cannot be built without it
    stop("epicollect_deployments_to_wimp: blank required answers in ",
         paste(sprintf("%s (%d)", names(n_blank)[n_blank > 0], n_blank[n_blank > 0]),
               collapse = ", "), ".\n",
         "Fix the entries in EpiCollect and export again.")
  } # end required check

  # find location IDs entered more than once
  dup_ids <- unique(raw$locationID[duplicated(raw$locationID)])
  # if any location ID repeats,
  if (length(dup_ids) > 0) {
    # stop because the WIMP sync matches on location ID and would skip the second one
    stop("epicollect_deployments_to_wimp: location ID(s) entered more than once: ",
         paste(dup_ids, collapse = ", "), ".\n",
         "Delete the duplicate entry in EpiCollect, or give a camera swap its own ID.")
  } # end duplicate check

  # find entries with no GPS fix, since EpiCollect cannot make location required
  no_gps <- raw$locationID[is.na(raw$latitude) | is.na(raw$longitude)]
  # if any entry has no fix,
  if (length(no_gps) > 0) {
    # stop because a WIMP location cannot be made without coordinates
    stop("epicollect_deployments_to_wimp: no GPS fix for ",
         paste(no_gps, collapse = ", "), ".\n",
         "Add the coordinates to the entry in EpiCollect, then export again.")
  } # end GPS check


  #
  ##
  ### Second, convert the local start time to UTC ----

  ## the form stores day-first dates, so the format is fixed rather than guessed;
  ## a guessed format would read 05/11 as 11 May without complaint
  local_start <- as.POSIXct(paste(raw$start_date, raw$start_time),
                            format = "%d/%m/%Y %H:%M", tz = tz)
  # find starts that did not parse
  bad_start <- raw$locationID[is.na(local_start)]
  # if any did not parse,
  if (length(bad_start) > 0) {
    # stop because deploymentStart is required by WIMP
    stop("epicollect_deployments_to_wimp: unreadable start date or time for ",
         paste(bad_start, collapse = ", "), ".\n",
         "Expected dd/mm/yyyy and HH:MM, as the form records them.")
  } # end start parse check

  # write the same instant in UTC as a naive datetime, the shape the WIMP post expects
  start_utc <- format(local_start, "%Y-%m-%d %H:%M:%S", tz = "UTC")
  # read this zone's offset at each start, e.g. "+1000", which also handles daylight saving
  offset_raw <- format(local_start, "%z")
  # and rewrite it in the bulk-upload dialect, e.g. "UTC+10" or "UTC+09:30"
  utc_offset <- .z_offset_to_wimp(offset_raw)

  # read EpiCollect's own record of when each entry was made, already in UTC
  created_utc <- as.POSIXct(raw$created_at, format = "%Y-%m-%dT%H:%M:%OS", tz = "UTC")
  # measure how far that is from the start time typed into the form
  entry_lag_h <- as.numeric(difftime(created_utc, local_start, units = "hours"))


  #
  ##
  ### Third, translate the drop-down answers into WIMP vocabularies ----

  # look each feature label up in the Camtrap DP featureType table
  feature_hit <- match(raw$feature_label, .FEATURE_LUT$form_label)
  # if a label is not in the table,
  if (anyNA(feature_hit)) {
    # stop because an unmapped feature would be posted as free text and rejected
    stop("epicollect_deployments_to_wimp: featuretype answer(s) not in .FEATURE_LUT: ",
         paste(unique(raw$feature_label[is.na(feature_hit)]), collapse = ", "), ".\n",
         "Add the new drop-down option to .FEATURE_LUT.")
  } # end feature check

  # look each bait label up in the WIMP bait table
  bait_hit <- match(raw$bait_label, .BAIT_LUT$form_label)
  # if a label is not in the table,
  if (anyNA(bait_hit)) {
    # stop because the WIMP bait resolver rejects labels outside the project list
    stop("epicollect_deployments_to_wimp: bait answer(s) not in .BAIT_LUT: ",
         paste(unique(raw$bait_label[is.na(bait_hit)]), collapse = ", "), ".\n",
         "Add the new drop-down option to .BAIT_LUT.")
  } # end bait check

  # read the clock check, where "No" means the timestamps need correcting
  timestamp_issues <- raw$clock_ok == "No"
  # leave camera make blank when the drop-down could only say "Other"
  camera_make <- ifelse(raw$cameraMake == "Other", NA_character_, raw$cameraMake)

  ## pack the camera settings into WIMP tags; each distinct key:value becomes a project
  ## tag, so only settings with a handful of possible values belong here
  tags <- .build_tag_string(list(
    # how many frames each trigger takes
    photosPerTrigger   = raw$photosPerTrigger,
    # the sensitivity setting as written on the camera
    triggerSensitivity = raw$triggerSensitivity,
    # the infrared flash type
    flashType          = raw$flashType,
    # what powers the camera
    batteryType        = raw$batteryType,
    # the specific bait, kept only when WIMP files it under 'Other Bait'
    baitTypeOther      = .BAIT_LUT$companion[bait_hit],
    # which SD card went in, matching the camDB crosswalk tag of the same name
    sdCardNumber       = raw$sdCardNumber,
    # which security key locks the camera
    pythonKeyNumber    = raw$pythonKeyNumber
  )) # end tag list

  ## start the notes with the EpiCollect UUID so a WIMP deployment can always be traced
  ## back to its form entry, then add whatever the field team wrote
  notes <- ifelse(is.na(raw$comments),
                  sprintf("epicollectUUID:%s", raw$ec5_uuid),
                  sprintf("epicollectUUID:%s | %s", raw$ec5_uuid, raw$comments))


  #
  ##
  ### Finally, assemble the WIMP rows, the full record and the checks ----

  ## the 25 WIMP_COLUMNS in the order camDB's crosswalk_monitor_to_wimp.R defines them
  wimp <- data.frame(
    locationID         = raw$locationID,
    latitude           = as.numeric(raw$latitude),
    longitude          = as.numeric(raw$longitude),
    deploymentStart    = start_utc,
    deploymentEnd      = NA_character_,                                # retrieval form
    setupBy            = raw$setupBy,
    cameraID           = raw$cameraID,                                 # serial number
    cameraModel        = raw$cameraModel,
    cameraHeight       = as.numeric(raw$cameraHeight),                 # metres
    cameraTilt         = as.numeric(raw$cameraTilt),
    cameraHeading      = as.numeric(raw$cameraHeading),                # degrees
    detectionDistance  = as.numeric(raw$detectionDistance),            # metres
    timestampIssues    = timestamp_issues,
    baitUse            = .BAIT_LUT$wimp_label[bait_hit],
    deploymentGroups   = paste(deployment_groups, collapse = " | "),
    deploymentTags     = tags,
    habitat            = raw$habitat,
    featureType        = .FEATURE_LUT$featureType[feature_hit],
    deploymentComments = notes,
    cameraMake         = camera_make,
    cameraYOP          = NA_integer_,                                  # not collected
    cameraSerialNo     = raw$cameraID,
    pickupBy           = NA_character_,                                # retrieval form
    utcOffset          = utc_offset,
    cameraDelay        = as.integer(raw$cameraDelay),                  # seconds
    stringsAsFactors   = FALSE
  ) # end wimp table

  # if the table has drifted from the 25 columns the WIMP tools expect,
  if (!identical(names(wimp), .WIMP_COLUMNS)) {
    # stop because the sync matches columns by name and order
    stop("epicollect_deployments_to_wimp: wimp table columns do not match .WIMP_COLUMNS.\n",
         "Edit the data.frame() call above to the camDB WIMP_COLUMNS order.")
  } # end column order check

  ## the full record keeps everything, with the Camtrap DP extras up front
  full <- data.frame(
    # the location ID doubles as the deployment ID while each point holds one camera
    deploymentID          = raw$locationID,
    wimp,
    coordinateUncertainty = as.numeric(raw$coordinateUncertainty),
    deploymentStartLocal  = format(local_start, "%Y-%m-%d %H:%M:%S"),
    featureTypeForm       = raw$feature_label,
    baitForm              = raw$bait_label,
    epicollectUUID        = raw$ec5_uuid,
    epicollectCreatedAt   = raw$created_at,
    entryLagHours         = round(entry_lag_h, 2),
    setupPhotoURL         = raw$setupPhotoURL,
    contextPhotoURL       = raw$contextPhotoURL,
    stringsAsFactors      = FALSE
  ) # end full table

  ## one row per check, counting the deployments each one flags
  qc <- data.frame(
    check = c("deployments read",
              "camera clock not correct at setup",
              sprintf("GPS accuracy worse than %s m", max_gps_accuracy_m),
              sprintf("entry made over %s h from the start time", max_entry_lag_hours),
              "no camera serial number",
              "no camera model",
              "no setup photo",
              "no detection distance"),
    n = c(nrow(full),
          sum(full$timestampIssues),
          sum(full$coordinateUncertainty > max_gps_accuracy_m, na.rm = TRUE),
          sum(abs(full$entryLagHours) > max_entry_lag_hours, na.rm = TRUE),
          sum(is.na(full$cameraID)),
          sum(is.na(full$cameraModel)),
          sum(is.na(full$setupPhotoURL)),
          sum(is.na(full$detectionDistance))),
    stringsAsFactors = FALSE
  ) # end qc table

  # name the flagged deployments so they can be checked before posting
  .warn_flagged(full$locationID, full$coordinateUncertainty > max_gps_accuracy_m,
                sprintf("GPS accuracy worse than %s m", max_gps_accuracy_m))
  # and the ones whose typed start time sits far from when the entry was made
  .warn_flagged(full$locationID, abs(full$entryLagHours) > max_entry_lag_hours,
                sprintf("entry made over %s h from the typed start: check date and time",
                        max_entry_lag_hours))

  return(list(wimp = wimp, full = full, qc = qc))
} # end epicollect_deployments_to_wimp


#
##
### Lookup tables for this form ----

## the 25 WildObs bulk-upload columns, copied from WIMP_COLUMNS in camDB's
## code_monitor_crosswalk/R/crosswalk_monitor_to_wimp.R; keep the two in step
.WIMP_COLUMNS <- c(
  "locationID", "latitude", "longitude", "deploymentStart", "deploymentEnd",
  "setupBy", "cameraID", "cameraModel", "cameraHeight", "cameraTilt",
  "cameraHeading", "detectionDistance", "timestampIssues", "baitUse",
  "deploymentGroups", "deploymentTags", "habitat", "featureType",
  "deploymentComments", "cameraMake", "cameraYOP", "cameraSerialNo",
  "pickupBy", "utcOffset", "cameraDelay"
)

## each export column the function reads, as its header with the question number
## removed (see .epicollect_header_stem), named by what it becomes
.EPICOLLECT_DEPLOYMENT_COLUMNS <- c(
  ec5_uuid              = "ec5_uuid",
  created_at            = "created_at",
  locationID            = "location_id__grid_",
  setupBy               = "setup_by",
  cameraMake            = "camera_make",
  cameraModel           = "camera_model_eg_HC",
  cameraID              = "camera_id_serial_n",
  sdCardNumber          = "SD_card_number",
  pythonKeyNumber       = "python_key_number",
  start_date            = "start_date",
  start_time            = "start_time",
  clock_ok              = "camera_clock_chec",
  latitude              = "lat_coordinates_stand",
  longitude             = "long_coordinates_stand",
  coordinateUncertainty = "accuracy_coordinates_stand",
  cameraHeight          = "camera_height_m_g",
  cameraHeading         = "camera_heading_de",
  cameraTilt            = "camera_tilt_degre",
  detectionDistance     = "detection_distanc",
  feature_label         = "featuretype",
  habitat               = "habitat_short_des",
  bait_label            = "bait_or_lure_type",
  cameraDelay           = "camera_delay_betw",
  photosPerTrigger      = "photos_per_trigge",
  triggerSensitivity    = "trigger_sensitivi",
  flashType             = "flash_type",
  batteryType           = "battery_type",
  setupPhotoURL         = "setup_photo_camer",
  contextPhotoURL       = "context_photo_cam",
  comments              = "comments"
)

## featuretype drop-down -> Camtrap DP featureType, which WIMP takes as its location
## feature; bush has no feature, so it is left blank and omitted from the post
.FEATURE_LUT <- data.frame(
  form_label  = c("None (Bush)", "Road paved", "Road dirt", "Trail hiking", "Trail game",
                  "Road underpass", "Road overpass", "Road bridge", "Culvert", "Burrow",
                  "Nest site", "Carcass", "Water source", "Fruiting tree"),
  featureType = c(NA, "roadPaved", "roadDirt", "trailHiking", "trailGame",
                  "roadUnderpass", "roadOverpass", "roadBridge", "culvert", "burrow",
                  "nestSite", "carcass", "waterSource", "fruitingTree"),
  stringsAsFactors = FALSE
)

## bait drop-down -> WIMP bait label, matching the camDB crosswalk's vocabulary;
## a bait WIMP has no label for goes under 'Other Bait' and keeps its name as a tag
.BAIT_LUT <- data.frame(
  form_label = c("no bait", "food", "scent", "visual", "acoustic",
                 "mineral lick", "other bait"),
  wimp_label = c("No bait", "Food", "Scent", "Visual", "Acoustic",
                 "Other Bait", "Other Bait"),
  companion  = c(NA, NA, NA, NA, NA, "mineralLick", NA),
  stringsAsFactors = FALSE
)


#
##
### Small helpers used only by this function ----

#' Strip EpiCollect Question Numbers From Export Headers
#'
#' @description EpiCollect prefixes each header with its question number
#'   (`8_start_date`), and puts it in the middle for location parts
#'   (`lat_11_coordinates_stand`). Removing both lets the lookup survive a reordered form.
#' @param x character. Export headers.
#' @return character headers without question numbers.
#' @author Zachary Amir
.epicollect_header_stem <- function(x) {
  # drop a leading question number, e.g. "8_start_date" -> "start_date"
  x <- sub("^[0-9]+_", "", x)
  # and the number inside location parts, e.g. "lat_11_coord" -> "lat_coord"
  x <- sub("^(lat|long|accuracy|UTM_Northing|UTM_Easting|UTM_Zone)_[0-9]+_", "\\1_", x)
  return(x)
} # end .epicollect_header_stem


#' Rewrite a "+HHMM" Offset in the WIMP Bulk-Upload Dialect
#'
#' @param x character. Offsets as `format(x, "%z")` writes them, e.g. `"+1000"`.
#' @return character offsets such as `"UTC+10"` or `"UTC+09:30"`.
#' @author Zachary Amir
.z_offset_to_wimp <- function(x) {
  # split off the sign
  sign_chr <- substr(x, 1, 1)
  # then the hours
  hrs <- as.integer(substr(x, 2, 3))
  # then the minutes
  mins <- as.integer(substr(x, 4, 5))
  # write whole hours without minutes, and half-hour zones with them
  out <- ifelse(mins == 0,
                sprintf("UTC%s%d", sign_chr, hrs),
                sprintf("UTC%s%02d:%02d", sign_chr, hrs, mins))
  return(out)
} # end .z_offset_to_wimp


#' Join Named Settings Into One WIMP Tag String Per Row
#'
#' @description Builds `key:value | key:value` strings, the format the camDB crosswalk
#'   uses, so tags from EpiCollect and from Monitor land in the same project vocabulary.
#'   A missing value drops its key rather than writing `key:NA`; commas become
#'   semicolons and pipes are removed, so each value stays one tag and one CSV field.
#' @param settings named list of equal-length character vectors.
#' @return character vector, `NA` for a row with no settings.
#' @author Zachary Amir
.build_tag_string <- function(settings) {
  # count the rows from the first setting
  n <- length(settings[[1]])
  # start every row with no tags
  out <- rep(NA_character_, n)
  # for each row,
  for (i in seq_len(n)) {
    # grab this row's value of every setting
    vals <- vapply(settings, function(v) as.character(v[i]), character(1))
    # keep only the settings that were answered
    vals <- vals[!is.na(vals) & nzchar(vals)]
    # skip the row if nothing was answered
    if (length(vals) == 0) next
    # make commas safe for the CSV uploader
    vals <- gsub(",", ";", vals, fixed = TRUE)
    # and remove pipes, which separate tags
    vals <- gsub("|", "", vals, fixed = TRUE)
    # join as key:value pairs
    out[i] <- paste(sprintf("%s:%s", names(vals), vals), collapse = " | ")
  } # end per row
  return(out)
} # end .build_tag_string


#' Warn With the Location IDs a Check Flagged
#'
#' @param ids character. Location IDs.
#' @param flag logical. TRUE where the check failed; NA is treated as not flagged.
#' @param what character. What the check looks for.
#' @return NULL, called for its warning.
#' @author Zachary Amir
.warn_flagged <- function(ids, flag, what) {
  # treat an unanswered value as not flagged
  flag <- flag & !is.na(flag)
  # if any deployment was flagged,
  if (any(flag)) {
    # warn with their IDs so they can be checked in EpiCollect before posting
    warning(sprintf("%s: %s", what, paste(ids[flag], collapse = ", ")), call. = FALSE)
  } # end flag condition
  return(NULL)
} # end .warn_flagged
