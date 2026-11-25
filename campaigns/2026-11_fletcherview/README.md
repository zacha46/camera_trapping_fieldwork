# 2026-11 Fletcherview camera trap campaign

Camera trap survey of the TERN Fletcherview Tropical Rangeland SuperSite (JCU
Fletcherview Research Station, about 30 km north of Charters Towers, QLD), deploying
the week of 23 November 2026 for about three months. The design places cameras on a
regular grid centred on the OzFlux eddy covariance tower (AU-Fle), with priority given
to the tower's upwind source area so that animal activity can be related to the flux
record.

This README is the decisions log for the campaign. It records what was decided and why;
the scripts record how. Every derived number lives in the summary tables the scripts
write, not in this file:

- `outputs/wind_summary_v1.csv` — wind record size, circular means, sector shares
- `outputs/design_summary_v4.csv` — scale, site counts by status, cameras for
  backups, MCP areas against the target, the FV04 move, extents (earlier designs have
  their own `design_summary_vN.csv`)
- `outputs/design_summary_v8.csv`, `nvis_areas_v8.csv`, `design_comparison_v8.csv`,
  `design_mcp_v8.csv`, `hectares_v8.csv`, `backup_hectares_v8.csv` and
  `hectare_distances_v8.csv` — the current hectare design: parcel areas, subgroup areas
  (whole parcel and the side reachable in the wet), hectare purity and spacing, the A2O
  hectares, the backups, and the comparison with v4 and v5. The v6 and v7 tables are in
  `outputs/OLD/`.

## How to run

From the repository root, after placing the raw inputs listed in
[`data/raw/README.md`](data/raw/README.md):

```sh
Rscript campaigns/2026-11_fletcherview/01_wind_footprint.R
Rscript campaigns/2026-11_fletcherview/02_water_and_basemap.R   # needs internet and a system GDAL
Rscript campaigns/2026-11_fletcherview/03_design_grid.R
Rscript campaigns/2026-11_fletcherview/04_fetch_v6_layers.R  # needs internet
Rscript campaigns/2026-11_fletcherview/05_design_hectares.R
Rscript campaigns/2026-11_fletcherview/06_prepare_wimp_deployments.R  # after the field days
```

`06_prepare_wimp_deployments.R` reads the EpiCollect deployment export from
`data/raw/epicollect/` and writes WIMP upload rows to `data/processed/`. It posts
nothing: the rows go to `sync_wimp_deployments()` in camDB's `code_monitor_crosswalk`,
dry run first.

The hectare scripts (04 and 05) read every site-specific value from
`v6_site_config.R`, which is named for the method introduced in v6; its
`design_version` sets the version the outputs carry, now v8. To run the hectare design
at another TERN SuperSite, copy that file and the two scripts into the new campaign and
change the config.

`02_water_and_basemap.R` reads the QTopo GeoPDFs with the command-line GDAL tools,
because the GDAL bundled with the CRAN builds of sf and terra cannot read PDFs. On
macOS, `brew install gdal` provides them. Its outputs are cached in `data/processed/`,
so it only needs re-running if the area or the sheets change.

Coordinate-bearing outputs (the QField folder, KML, points CSV, preview) are written to
`outputs/` locally and are never committed.

## Field map in QField

`outputs/qfield_v4/` is a self-contained QField project:

| File | Contents |
|---|---|
| `fletcherview_v4.qgs` | the project: layer order, symbols, labels, opening view |
| `fletcherview_design_v4.gpkg` | camera sites and their 100 m placement circles, flux tower, approximate boundary, wind wedge and footprint zone, mapped channels, wet-season zone, and an empty `deployments` layer |
| `qtopo_basemap.tif` | QTopo 1:25k basemap (sheets 8158-31 and -32), 3 m pixels, works offline |

Copy the whole folder to the phone (on iOS, into QField's folder via the Files app) and
open the `.qgs`. Every layer except `deployments` is read-only. To log a camera, add a
point to `deployments` at the tree: pick the `point_id` from the drop-down, type the
`deployment_id` (the ID used in EpiCollect), and `recorded_at` fills itself with the
current time. The KML in `outputs/` holds the same sites for Google Earth.

**Using the sites in the field.** Put a camera at every footprint and main site. Then
take the cameras that are left and work down the backup list, B1 first; if a backup
site cannot be reached, skip it and go to the next. Backups carry their rank on the map
label (e.g. "FV13 (B1)") and in the points CSV, which lists them in rank order.

**Placement circles.** Each site is drawn with a 100 m radius circle, sized in metres
on the ground, so it stays the same real size at every zoom. Put the camera on the
best tree inside the circle; the site dot marks the grid node at its centre.

## Design v4

### Step 1: where the tower looks (`01_wind_footprint.R`)

The tower measures fluxes from the land upwind of it, so the footprint is set by the
direction the wind blows *from*. The analysis uses the OzFlux L3 half-hourly record
for 2023 to July 2025 and keeps only half-hours that passed every OzFlux QC check
(`Wd_QCFlag == 0`), had a valid bearing, and had wind faster than 0.5 m/s. Daytime
is incoming shortwave radiation above 10 W/m². Directions are binned into 16 sectors
of 22.5°, with north centred on 0°, and summarised by the circular mean and the mean
resultant length R.

The deployment season (November to February, daytime) is the subset that matters for
the design. Its wind comes mostly from the north-east to east, with very little from
the south-west to west, and is more concentrated than the full-year record. The
footprint is therefore taken as the arc from 10° to 125° (NNE to ESE) from the tower.
The 2025 season contributes only January and February, because the 2025 file ends in
July; its mean direction differs from 2023 and 2024 (see the per-year rows of
`wind_summary_v1.csv`). The wind analysis is unchanged since v1.

Tower height is 25 m and canopy height 12 m (OzFlux metadata).

### Step 2: mapped water and basemap (`02_water_and_basemap.R`)

Hydrography comes from the Queensland Government "Water courses and bodies" service
(© State of Queensland, CC BY 4.0), fetched for the station plus about 1 km. The
design uses only its **watercourse-area** polygons, the mapped channels of the Burdekin
River and Hann, Lolworth and Arthur Creeks. Dams, lakes and the drainage lines are
fetched and cached for context but do not affect the design. The basemap is QTopo
1:25k sheets 8158-31 and 8158-32, cropped to their map frames and mosaicked; sheets
8158-33 and -34 lie wholly west of the station.

### Step 3: the grid (`03_design_grid.R`)

**Boundary.** No cadastral boundary was available (the QLD Globe property layer
failed), so the property outline was traced by hand from a north-up Google satellite
screenshot. The trace is georeferenced on the tower, assuming equal x and y scale, and
the metres-per-pixel scale is chosen so the traced polygon covers the station's
2,400 ha. The boundary layer carries the note "APPROXIMATE – traced from screenshot,
scaled to 2,400 ha".

**Grid.** An 800 m square grid in WGS 84 / UTM 55S (EPSG:32755) with a node exactly
on the tower. Nodes are kept if they lie inside the boundary shrunk inward by 100 m,
since each camera goes on the best tree within about 100 m of its node. IDs run north
to south, then west to east (FV01, FV02, ...).

**Status.** Every grid node is one of three field statuses. The first rule that
matches wins.

| Status | Rule | In the field |
|---|---|---|
| `footprint` | inside the footprint zone: the wind wedge (within 2,000 m at a bearing of 10–125°) widened by 200 m all round | always deploy, even near water |
| `backup` | any of: within 250 m of the Burdekin River channel or 150 m of any other mapped creek channel, judged where the camera goes; every other node (odd `i + j`) beyond 1,600 m at a bearing of 170–330° (the far downwind block, checkerboard-thinned); grid offsets (i = −3, j = 3) and (i = −3, j = 1), two interior downwind nodes | fill in rank order with the cameras left after footprint and main |
| `main` | everything else | always deploy |

`i` and `j` are the grid column and row offsets from the tower (east and north
positive). Each backup carries a `backup_reason` listing every rule it meets.

**Camera budget.** The campaign has 30 cameras. Footprint and main sites take some
of them; the rest go to backups (`n_planned` and `n_backup_cameras` in the design
summary).

**Backup ranking.** Backups away from water come first, then those near water; within
each group the next site is the one that most enlarges the minimum convex polygon
(MCP) of the cameras already placed. Sites that add less than 1 ha more than the best
count as ties and go to the one farthest from water. FV01 is ranked last whatever its
gain (see the decisions log). The design summary gives the MCP of the always-deployed
sites, the MCP once every backup camera is placed, and the backup rank at which
coverage passes the 15 km² target.

**Moved site.** FV04 sat on the bank of the Burdekin. Its camera goes to the spot
farthest from any mapped channel within 300 m of its grid node and inside the inset
boundary (the distances before and after are in the design summary). The grid node
stays its reference; the preview draws an arrow from the node to the new spot. The
water rule is applied at the new spot, so FV04 is now a main site.

**Outputs.** The QField folder above, with site markers and placement circles sized
in metres; a KML with the boundary, sites in one folder per
status, and the flux tower; a points CSV with backups in rank order; and a preview over
the QTopo basemap with legends for camera status, every map layer and the markers.

## Design v6: stratified hectares

v6 replaces the grid with 1 ha plots (100 × 100 m) stratified by vegetation. Within a
plot the cameras are not independent: the plot, not the camera, is the sampling unit,
and cameras go on features chosen in the field. v7 keeps every v6 rule and changes only
the A2O hectares (see "Design v7" below); v8 adds backup hectares for the hectares
beyond Lolworth Creek (see "Design v8"). The PDF `outputs/fletcherview_v8.pdf` holds
the maps, a close-up of each hectare and backup over satellite imagery, the hectare and
backup tables and the comparison with v4 and v5. `outputs/qfield_v8/` (zipped as
`qfield_v8.zip`) is the matching QField project. Earlier PDFs and QField projects are
in `outputs/OLD/`.

**Caveat.** The state and national layers are coarse (NVIS is mapped on a 100 m grid)
and the tracks are unverified. Confirm each hectare's vegetation subgroup and its
access on the ground before deploying.

### Step 1: layers (`04_fetch_v6_layers.R`)

- **Boundary.** The Queensland cadastral parcel for Lot 4 on DV450 (Digital Cadastral
  Database, © State of Queensland, CC BY 4.0). Its mapped area differs from its
  registered area by the cadastre's stated mapping accuracy (1:25,000); both are in
  `design_summary_v6.csv`.
- **Vegetation.** NVIS 6.0 extant Major Vegetation Subgroups (DCCEEW) are the
  strata. Queensland regional ecosystems (pre-clearing and remnant) are included for
  interpretation only.
- **Tracks.** OpenStreetMap first, then the Queensland roads and tracks layer, then
  the collaborator's v5 points. Every track feature carries its source. A free
  satellite backdrop (Esri World Imagery) is drawn in the PDF and QField so tracks can
  be checked by eye.

### Step 2: hectares (`05_design_hectares.R`)

| Rule | Setting |
|---|---|
| Stratum | an NVIS subgroup covering at least 1 km² of the parcel; smaller subgroups are listed but not sampled |
| Hectares per stratum | 2; the TERN core plot and the A2O hectares count towards their own subgroup |
| Cameras | 30 in total; 4 per hectare if that fits, otherwise 3 |
| Access | a track crosses every hectare chosen by the rules, so its edge is on the track and no part of it is more than about 140 m from it; the fixed hectares (core plot and A2O) are exempt |
| Purity | share of the hectare mapped as its subgroup; at least 75% where possible |
| Spacing | replicates of one subgroup about 1 km apart |
| Candidates | squares on a 25 m lattice, wholly inside the parcel, not overlapping another hectare |
| Order | core plot first, then by straight-line distance from the flux tower |

Each hectare gets four nominal guide points at its edge midpoints; the one nearest a
track is the on-track guide. The field note asks for one camera on the track and the
rest off it, on dense tussock for spectacled hare-wallaby and on rock, logs or
termite mounds with a low camera for reptiles. The design uses no drift fences or
thermal cues.

### Step 3: comparison with the grid

`design_comparison_v6.csv` gives, for each NVIS subgroup, its share of the parcel
against the cameras and the share of sampled sites in that subgroup under the v4 grid
(the 30 sites given cameras), the v5 relocated points and the v6 hectares. The v4 and
v5 rows include sites that fall off the cadastral parcel. `design_mcp_v7.csv` gives
each design's minimum convex polygon.

## Design v7: A2O hectares on the wet-season recorders

v6 placed one A2O hectare on a point for A2O site 61 that turned out to sit on the
station buildings (`v6_a2o_point_to_station_m` in `design_summary_v8.csv`). v7 places
the A2O hectares on handheld GPS fixes of the site's four recorders
(`data/raw/GPS_fletcher_values.csv`, rows with `point_type` "sensor"). The recorders
are two wet–dry pairs, A and B. Cameras run through the wet season, so the two wet
recorders each anchor a hectare:

| Hectare | Recorder | Counts as |
|---|---|---|
| `A2O-A` | Acoustic wet A | the second replicate of its subgroup, with the core plot |
| `A2O-B` | Acoustic wet B | the first replicate of its subgroup; the second is chosen by the v6 rules |

The subgroups are in `hectares_v8.csv`. Each A2O hectare is the 100 m square that
contains its recorder, chosen as in v6: crossed by a track if possible, then purest,
then nearest a track. No track crosses either (`a2o_hectares_crossed_by_track` and
`a2o_min_dist_track_m` in the design summary), so both are exempt from the access rule
like the core plot, and their field note says to walk in on the route the A2O team uses
to service the recorder. The four recorders are drawn on every map, labelled by name.
The hectare count, cameras per hectare and camera budget are unchanged.

## Design v8: backups for the hectares beyond Lolworth Creek

Lolworth Creek crosses the northern part of the parcel from west to east, and reaching
its far side from the station means crossing it. Into the wet season the crossing may
close. `05_design_hectares.R` cuts the parcel along the creek's mapped line (QLD
hydrography) and treats as reachable, in each parcel part, the piece nearest the flux
tower. Main hectares outside the reachable side are at risk (`hectares_beyond_barrier`
in `design_summary_v8.csv`), and each has a backup on the reachable side:

| At risk | Backup subgroup | Chosen on |
|---|---|---|
| MVS09-B | 9, same as the hectare it replaces | a v5 point, about 1 km from the nearest reachable subgroup-9 hectare |
| MVS37-A | 37, same as the hectare it replaces | the purest reachable square; no v5 point lies in subgroup 37 on the reachable side |
| MVS37-B | 9, a second reachable subgroup-9 hectare | a v5 point, spaced as above |

The plan lives in `backup_plan` in `v6_site_config.R`. Backups are chosen by the same
lattice, purity and spacing rules as the main hectares, but only v5 points count as
tracks, and the subgroup-37 backup has no track rule. The chosen hectares, their v5
points and spacing are in `backup_hectares_v8.csv`; the subgroup area on the reachable
side is the `reachable_km2` column of `nvis_areas_v8.csv`.

The main design is unchanged. A backup is used only if the crossing is closed on the
day, in place of the hectare it is for, and with the same cameras. Each at-risk
hectare's field note names its backup, and each backup's note names the hectare it
replaces. The backups are their own dashed layer in QField and the PDF, and the
deployments drop-down lists their IDs. The creek is drawn on every map.

## Decisions log

**2026-11-19 — v1 reproduced in R (ZDA with Claude Code).** Design v1 was first built
in a chat session in Python with no saved code. Both scripts reproduced every v1
number: every wind statistic, including the exact count of valid half-hours, and the
scale, node count and status split, both MCP areas and the four boundary extents. The
grid was then checked point by point against `fletcherview_planned_points_v1.csv` from
the chat session: all 34 IDs and statuses matched, and positions agreed to within
0.1 m, the rounding of the v1 file. The v1 files were deleted from `data/raw/` once
matched; the reproducing code is at commit `01ba7ea`.

**Tower position.** v1 placed the tower at −19.887232, 146.188908. The OzFlux file
metadata gives −19.887285, 146.189138, about 25 m away (`tower_offset_to_ozflux_m` in
the design summary). v1's position is kept so the design is unchanged; the gap is small
next to the 800 m grid spacing and the ~100 m tree search radius.

**FV03 and FV14 stay hard-coded, by grid offset.** No clean rule reproduces them. The
natural rule — kept nodes in the downwind block (bearing 170–330°, beyond 1,600 m)
that are not on the MCP boundary — also selects FV07. The two nodes are named by grid
offset rather than ID, so a boundary change that renumbers points cannot silently move
the choice to a different node.

**2026-11-19 — v2: wet-season water rule (ZDA).** *(v2 statuses; v3 below renamed and
merged them.)* Any camera within 500 m of a river or
water body is `drop_first`, because of wet-season flooding and access. "River or water
body" is the mapped channel polygons only; broader definitions (adding dams or major
creek lines) caught 18–23 of 34 nodes and left too few cameras. Footprint nodes are
exempt and stay footprint. `drop_first` keeps its meaning: planned, but the first to
give up, not removed from the plan. This answers the v1 questions about FV04, FV12,
FV21 and FV07, which are all now `drop_first` because of water.

**2026-11-19 — the orange "footprint" on the screenshot was a guess (ZDA).** The
footprint is taken from the OzFlux wind record only. The preview and field map use the
QTopo basemap and the design's own layers, so neither the hand-drawn orange outline
nor the red boundary appears.

**2026-11-19 — v3: one ranked backup list, "core" renamed "main" (ZDA).** v2 had two
categories with overlapping meaning: `drop_first` (planned, skip if needed) and
`reserve` (unplanned, use if spare). Skipping a `drop_first` site freed a camera that
was implicitly meant for a `reserve` site, and three of the five reserves were drier
than the `drop_first` sites ranked above them. Both are now one `backup` list, ranked
as described above (ZDA chose coverage-first ranking over safest-first, which stayed
below the 15 km² target with 30 cameras). "Core" is renamed "main" because "core" means
something else to the flux community; "main" was chosen over "property" to avoid
confusion with the property boundary.

**FV04 moved back from the river; FV01 ranked last instead (2026-11-19).** ZDA asked
for both to move back from the Burdekin. FV04 moves within 300 m to drier ground. FV01
cannot: every spot within 400 m of its node that is clear of the channel lies north of
the river, which the traced boundary includes only because it is out by 100–200 m
there. Moving FV01 to the nearest spot at least 500 m from any channel would place it
1.4 km away and beside FV05, gaining no coverage. FV01 therefore stays at its node and
is ranked last among the backups.

**2026-11-19 — v4: narrower water rule, wider footprint, fixed-size sites (ZDA, after
loading v2 and v3 in QField).** The 500 m water buffer was too generous: it is now
250 m from the Burdekin River channel and 150 m from every other mapped creek channel.
The footprint now includes a 200 m strip around the wind wedge, because the wind
sometimes blows from other directions and the leeward side near the tower is
monitored too; this adds FV17 and FV32. Site markers in QField were drawn in screen
millimetres, so they changed ground size with every zoom; each site now has a 100 m
placement circle sized in metres. The backup ranking rules are unchanged (ZDA liked
the v3 ordering). Water is now judged at the camera's final position, which makes the
moved FV04 a main site. Counts, the camera budget and coverage are in
`design_summary_v4.csv`.

**2026-11-25 — v6: stratified hectares, cadastral boundary (ZDA with Claude Code).**
The cadastral parcel replaces the traced boundary for v6. The v4 grid stays as built,
and the comparison counts its sites that fall off the parcel. Public track data barely
cover the property. OpenStreetMap has no tracks inside the parcel, only a short service
road, and the Queensland layer has none. ZDA therefore chose to treat each v5 point as a
point on a track, since the collaborator placed every v5 point on a track interpreted
from satellite images. A hectare crossed only by such a point carries a field note to
confirm the track exists. The A2O site 61 falls in the same subgroup as the TERN core
plot, so ZDA chose it as that subgroup's second replicate rather than as an extra
hectare. The core plot's corners are not published. OzFlux places plot QDAEIU0008 south
of the tower, so a placeholder square sits just south of it, to be replaced by the
plot's surveyed pegs. The cleared class (NVIS 98) falls just under the 1 km² threshold
(`nvis_areas_v6.csv`) and is not sampled. The A2O hectare is below the 75% purity aim,
because the A2O site sits beside cleared ground around the station buildings. The
cameras left over after the hectares are not yet assigned (`cameras_spare` in
`design_summary_v6.csv`).

**2026-11-25 — EpiCollect export to WIMP rows (ZDA with Claude Code).** A test entry
from the live form was converted with `06_prepare_wimp_deployments.R` and passed
offline through the camDB body builder with no unmapped columns. The location ID is
the key: the live form no longer asks for a deployment ID, and WIMP's sync matches on
location name, so each ID must be unique within the campaign. Start times are AEST
wall-clock in the form and are converted to UTC with `utcOffset` UTC+10, because the
WIMP post sends the time as given. Feature and bait drop-downs are translated to the
Camtrap DP and WIMP labels the camDB crosswalk uses. Mineral lick has no WIMP bait
label, so it goes in as Other Bait with a `baitTypeOther` tag. Camera settings, the SD
card and the security key number become `key:value` tags in the crosswalk's format. The
EpiCollect UUID leads the deployment notes so a WIMP record can be traced to its entry.
Check counts are in `epicollect_qc_summary_v1.csv`.

**2026-11-25 — v7: A2O hectares moved to the wet-season recorders (ZDA with Claude
Code).** The A2O coordinates used in v6 were wrong: the point ZDA supplied fell on the
station buildings, which is why that hectare looked odd. ZDA supplied
GPS fixes of the four recorders taken on 23 July 2026 and asked for the A2O sampling to
match the wet-season recorders. The two wet recorders are too far apart for one
hectare, so ZDA chose one hectare on each (over one hectare on either recorder alone, or
on all four recorders). Neither is near a mapped track or a v5 point, and ZDA chose to
exempt them from the access rule with a field note rather than move them. The version
bumps to v7 and the v6 outputs move to `outputs/OLD/`. The two A2O hectares are purer
than the v6 A2O hectare, but the design's MCP is smaller and the subgroup-19 replicates
are further apart than the target (`design_mcp_v7.csv`, `hectare_distances_v7.csv`).

**2026-11-25 — v8: backups for the hectares beyond Lolworth Creek (ZDA with Claude
Code).** ZDA flagged that the creek just north of A2O-A must be crossed to reach the
subgroup-37 band and the northern subgroup-9 block, and may not be passable into the
wet season. Splitting the parcel at Lolworth Creek confirmed the three hectares ZDA
named (MVS09-B, MVS37-A, MVS37-B) are the only ones beyond it. ZDA suggested moving
MVS09-B to the southern end of the property in the same subgroup, on a v5 point; the
backup rules picked exactly that. Very little subgroup 37 is reachable, and the only
place a pure hectare fits is a narrow NVIS strip beside v5 point FV28. ZDA chose one
subgroup-37 backup there, flagged for checking on the ground, with MVS37-B's cameras
going to a second reachable subgroup-9 hectare. Two subgroup-37 hectares in the strip
would have sat 150 m apart, and the imagery does not show the strip as distinct from
the woodland around it. ZDA chose backups used only if the crossing is closed, over
replacing the at-risk hectares outright. `select_hectares()` gained a `require_track`
switch for that backup, and now stops instead of returning empty hectares when the
candidates cannot be spaced without overlapping. The version bumps to v8 and the v7
outputs move to `outputs/OLD/`.

## Open questions

- **v8: if the creek closes, subgroup 37 drops to one hectare** in a strip NVIS may
  have mapped wrongly, and subgroup 9 rises to three hectares. Confirm the strip is
  tussock grassland before relying on it. A2O-B sits on the reachable side but next to
  the creek; check that its own access does not cross it.

- **v7: A2O recorders sit on the hectare edge.** Each A2O square contains its recorder,
  but the rule that picks the square (purity, then track distance) leaves both
  recorders on an edge rather than central. Options: centre each square on its
  recorder, or keep the rule.
- **v7: replicate spacing.** The core plot and A2O-A, the two subgroup-19 hectares, are
  well beyond the 1 km spacing target, and MVS09-B is placed against A2O-B
  (`hectare_distances_v8.csv`). MVS09-B also sits next to a river channel on the
  imagery; check its wet-season access with the other riverside hectares.

- **FV03 gets a camera but sits inside the Burdekin channel.** Ranked by coverage,
  FV03 is backup B6, within the cameras available, although QTopo maps it inside the
  river channel. FV02 (B5) is about 60 m from a creek channel. Options: rank FV03 last
  like FV01, move it like FV04, or leave it.
- **Boundary accuracy.** Over QTopo, the traced north boundary runs inside the Burdekin
  channel, where the screenshot trace followed the south bank, so the trace is out by
  roughly 100–200 m there. The cadastral parcel is now fetched for v6
  (`04_fetch_v6_layers.R`); the v4 sites off it are counted in
  `design_comparison_v6.csv`. Rebuilding v4 on the parcel is not yet done.
- **v6–v8: water and the riverside hectares.** The hectare design has no water rule.
  Both tussock-grassland hectares sit beside creek lines, because that subgroup follows
  the watercourses. Check wet-season access before deploying them.
- **EpiCollect: location ID format and deployment group.** The live form's example is
  `FV12_20261125`, a v4 grid name plus date, while v8 cameras sit in hectares
  (`MVS09-B`, `A2O-A`). The ID format, whether the script should check IDs against the v6
  design, and the WIMP group label (`Fletcherview_2026-11` for now) are to confirm
  before the first post.
- **v6–v8: spare cameras.** Options: a fifth camera in some hectares, or a seventh
  hectare (for example in the cleared class, which falls just short of a stratum).

## Design notes from the v1 chat session

### Targets
- camDB: >10 deployments, >100 trap-nights, >10 species; sampled area (MCP/bbox) target 50 km² is a soft suggestion — 15 km² is the analysis minimum and is the working target (property is ~2,400 ha = 24 km², so 50 km² is not achievable on-property).
- Project outcome: grazing pressure (cattle, macropods, other grazers), linked to flux tower and acoustic (A2O) data.

### Design decisions
- Systematic 800 m grid aligned on the flux tower (-19.887232, 146.188908), clipped to the property (100 m inward buffer).
- Cameras placed at the best tree within ~100 m of each grid point; strapped to trees, heights vary (cattle rubbing); deployment metadata (height, angle, feature) recorded as detection covariates.
- Motion trigger only (cameras can't do time-lapse simultaneously). No locks (property secure). ~3-month deployment; retrieval possibly by station maintenance crew.
- Max 30 cameras (luggage).

### Wind / flux footprint
- OzFlux L3 2023–2025 (sonic Wd, QC flag 0, Ws > 0.5 m/s). Nov–Feb daytime: circular mean ~64° (ENE); ~69% of half-hours from NNE–ESE (10–125°); <5% from SW–W. Confirmed by a colleague's higher-resolution map.
- Tower 25 m, canopy 12 m. Footprint likely mostly within a few hundred m to ~1 km upwind (rule of thumb, not modelled).
- "Footprint" points = within 2 km of tower and bearing 10–125° (plus tower point).

### v1 grid (boundary APPROXIMATE — traced from screenshot, scaled to 2,400 ha)
- 34 nodes: 7 footprint, 20 core, 2 drop_first (FV03, FV14 — interior, downwind, MCP unchanged), 5 reserve (checkerboard-thinned downwind west block).
- Planned 29 points → MCP ~19.5 km²; 27 points (dropping FV03, FV14) → MCP still ~19.5 km².
- FV04, FV12, FV21, FV01 are near the Burdekin channel — check access/flooding.
- To do: replace approximate boundary with QLD cadastre parcel (Queensland Globe → Property layer → click parcel for Lot on Plan; or Cadastral data – Queensland series, filter by lot/plan) and regenerate.

### Field data workflow
- EpiCollect form for camera metadata (simple method). QField (free, iOS) as navigation map: QTopo 1:25k GeoPDF (sheet 8158-33 et al.) + design GeoPackage/KML; drop a point named with the deployment ID and join to EpiCollect by ID in R.
- Avenza free tier limit hit; KoboToolbox not a map tool on iPhone.
