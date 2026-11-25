### Prepare the EpiCollect deployment records for upload to the WildObs image platform
## 25 November 2026, Fletcherview Research Station, QLD
# Zachary Amir

### From a field form to WIMP rows:
## The field team records each camera in the EpiCollect deployment form. This script
## reads that form's CSV export and writes one row per deployment in the 25-column
## shape that sync_wimp_deployments() in camDB's code_monitor_crosswalk posts to WIMP.
## It posts nothing itself.

### Inputs and outputs:
## Reads the EpiCollect export from data/raw/epicollect/. Writes the WIMP rows and the
## full deployment record to data/processed/ (both carry coordinates and are ignored by
## git), and the tracked check counts to outputs/epicollect_qc_summary_vN.csv.


## Load libraries
library(tidyverse) # For basic data wrangling
library(here)      # For project-relative paths so this runs on any machine

## load the shared helper
source(here("R", "epicollect_deployments_to_wimp.R"))


#
##
### Settings for this campaign ----

## output version; bump it when the conversion rules change, and log why in the README
version <- "v1"

## the EpiCollect CSV export; swap in the real one after the field days
export_file <- here("campaigns", "2026-11_fletcherview", "data", "raw", "epicollect",
                    "TEST_OUTPUT_form-1__tern-fletcherview-cam-trap-deployment-nov-2026.csv")

## the WIMP deployment group every Fletcherview camera joins
## TODO: confirm the label with ZDA before the first live post; WIMP creates unseen groups
deployment_groups <- "Fletcherview_2026-11"

## Queensland keeps AEST all year, so every start converts at UTC+10
field_tz <- "Australia/Brisbane"


#
##
### Convert the export into WIMP rows ----

# read, check and translate the export
deps <- epicollect_deployments_to_wimp(
  # the CSV downloaded from EpiCollect
  path = export_file,
  # the group label written on every row
  deployment_groups = deployment_groups,
  # the time zone the start date and time were typed in
  tz = field_tz
) # end conversion

# view the check counts, expecting zeros below the first row
deps$qc
# view one WIMP row on its side, to compare against the form entry
glimpse(deps$wimp)


#
##
### Write the outputs ----

## both tables carry camera coordinates, so they go to data/processed/, which git ignores
processed_dir <- here("campaigns", "2026-11_fletcherview", "data", "processed")

# write the 25-column rows that sync_wimp_deployments() takes
write.csv(deps$wimp, file.path(processed_dir, sprintf("wimp_deployments_%s.csv", version)),
          row.names = FALSE, na = "")
# write the full record for camDB, which keeps what WIMP has no field for
write.csv(deps$full, file.path(processed_dir, sprintf("full_deployments_%s.csv", version)),
          row.names = FALSE, na = "")
# write the check counts, which hold no coordinates and are tracked
write.csv(deps$qc, here("campaigns", "2026-11_fletcherview", "outputs",
                        sprintf("epicollect_qc_summary_%s.csv", version)),
          row.names = FALSE)
