# EpiCollect deployment form

`camtrap-deployment-v3.form.epicollect.json` is the general camera-deployment form,
for any campaign. Import it into an EpiCollect5 project (Formbuilder → Import form).
It records what is measured at setup; retrieval (`deploymentEnd`) is recorded
separately, and fields assigned in the office (`locationName`, `deploymentGroups`,
`projectName`) are not in the form.

| Question | Camtrap DP / WildObs field |
|---|---|
| deployment id | `deploymentID` |
| location id / grid point | `locationID` |
| setup by | `setupBy` |
| camera make + camera model | `cameraModel`, as `make-model` |
| camera id (serial number) | `cameraID` |
| start date + start time | `deploymentStart` |
| camera clock checked and correct? | `timestampIssues` (`No` → `true`) |
| coordinates | `latitude`, `longitude` |
| camera height / heading / tilt | `cameraHeight`, `cameraHeading`, `cameraTilt` |
| detection distance | `detectionDistance` |
| featuretype | `featureType` (`None (Bush)` → empty) |
| habitat | `habitat` |
| bait or lure type | `baitUse` (`false` only for `no bait`); the value goes in `deploymentTags` as `lure: <value>` |
| camera delay between triggers | `cameraDelay` |
| photos per trigger, trigger sensitivity, flash type, battery type | `deploymentTags` |
| SD card number, python key number | `deploymentTags` |
| comments | `deploymentComments` |

The bait/lure values match the WildObs image platform's list. Coordinate uncertainty
and `cameraDepth` are deliberately left out: the first comes from the GPS fix, the
second applies only to underwater cameras. Campaign-specific variants (for example a
drop-down of grid point IDs instead of free text) live in that campaign's folder.

## The live form has moved on from this JSON

The Fletcherview project's form was edited in the web formbuilder after this file was
written: the deployment id question is gone (location id is now the key), and camera
model and serial number are optional. Export the live form (Formbuilder → Export form)
and commit it as the next version before reusing this file elsewhere.

## Getting the records into the WildObs image platform

`R/epicollect_deployments_to_wimp.R` reads the CSV export (Data → Download → CSV) and
returns the 25-column WIMP bulk-upload rows that camDB's `sync_wimp_deployments()`
posts. It converts the AEST start time to UTC, translates the feature and bait
drop-downs, packs camera settings into `key:value` tags, and stops on a missing GPS
fix or a repeated location ID. A campaign script calls it and writes the rows; see
`campaigns/2026-11_fletcherview/06_prepare_wimp_deployments.R`. Exports carry camera
coordinates, so keep them in the campaign's `data/raw/`, which git ignores.

## EpiCollect rules that are easy to break when editing the JSON by hand

- **Location, photo, audio and video questions cannot be required.** The formbuilder
  rejects the whole form ("form is invalid", no detail). The GPS fix therefore has to
  be checked in the field.
- Integer, decimal and radio questions need `"default": ""`, not `null` (the server
  rejects `null`).
- Input refs are 60 characters (`<32-char project>_<13-char form>_<13-char input>`) and
  answer refs exactly 13 letters or digits, all unique.
