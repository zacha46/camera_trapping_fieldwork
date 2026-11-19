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
- `outputs/design_summary_v1.csv` — scale, node counts by status, MCP areas, extents

## How to run

From the repository root, after placing the raw inputs listed in
[`data/raw/README.md`](data/raw/README.md):

```sh
Rscript campaigns/2026-11_fletcherview/01_wind_footprint.R
Rscript campaigns/2026-11_fletcherview/02_design_grid.R
```

Each script stops before writing anything if its results drift from design v1 (the
`check_against_v1` switch at the top). Coordinate-bearing outputs (GeoPackage, KML,
points CSV, preview) are written to `outputs/` locally and are never committed.

## Design v1

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
`wind_summary_v1.csv`).

Tower height is 25 m and canopy height 12 m (OzFlux metadata).

### Step 2: the grid (`02_design_grid.R`)

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

**Status.** The first rule that matches wins.

| Status | Rule | Field meaning |
|---|---|---|
| `footprint` | the tower node, or within 2,000 m at a bearing of 10–125° | upwind source area; deploy first |
| `reserve` | bearing 170–330°, farther than 1,600 m, and odd `i + j` (checkerboard thin of the far western block) | deploy only if cameras are spare |
| `drop_first` | grid offsets (i = −3, j = 3) and (i = −3, j = 1), i.e. FV03 and FV14 | interior downwind nodes; first to give up if cameras run short, and dropping them leaves the MCP unchanged |
| `core` | everything else | deploy |

`i` and `j` are the grid column and row offsets from the tower (east and north
positive).

**Outputs.** A GeoPackage in WGS84 with `planned_points`, `boundary_approx`, and an
empty `deployments` point layer (`deployment_id`, `point_id`, `notes`, `recorded_at`)
for recording actual camera positions in QField; a KML with the boundary, points in
one folder per status, and a flux tower placemark; a points CSV; and a preview figure
over the screenshot.

## Decisions log

**2026-11-19 — v1 reproduced in R (ZDA with Claude Code).** Design v1 was first built
in a chat session in Python with no saved code. Both scripts now reproduce it and stop
if they drift. Every wind number quoted from v1 reproduces, including the exact count
of valid half-hours. Every design number reproduces too: the scale, the node count and
status split, both MCP areas, and the four boundary extents.

**Tower position.** v1 placed the tower at −19.887232, 146.188908. The OzFlux file
metadata gives −19.887285, 146.189138, about 25 m away (`tower_offset_to_ozflux_m` in
`design_summary_v1.csv`). v1's position is kept so the design is unchanged; the gap is
small next to the 800 m grid spacing and the ~100 m tree search radius.

**`drop_first` stays hard-coded, by grid offset.** No clean rule reproduces it. The
natural rule — kept nodes in the downwind block (bearing 170–330°, beyond 1,600 m)
that are not on the MCP boundary — selects FV03, FV14 and FV07. Separating FV07 would
need a distance threshold chosen only to fit the answer. The two nodes are named by
grid offset rather than ID, so a later change to the boundary that renumbers points
cannot silently move the choice to a different node.

**Not yet validated point by point.** The v1 outputs (`fletcherview_design_v1.gpkg`,
`.kml`, `fletcherview_planned_points_v1.csv`, `_preview.png`) were not available when
v1 was reproduced. `02_design_grid.R` checks IDs, status and positions (to 1 m) against
the v1 CSV automatically once that file is placed in `data/raw/`.

## Open questions

- **Footprint versus the orange outline.** The tower footprint drawn in orange on the
  screenshot lies south of the tower, whereas the wind analysis places the upwind
  source area north-east to east-south-east of it. Is the orange outline a different
  thing (for example the SuperSite core plot), or should the footprint rule be
  revisited?
- **FV04** falls on the sand of the river channel in the screenshot, and FV12 and
  FV21 sit close to the river edge. Can they be placed within 100 m, or should they be
  moved or dropped?
- **FV07** meets the same "interior downwind" description as FV03 and FV14. Should it
  also be `drop_first`?

## Design notes from the v1 chat session

<!-- Paste the contents of the claude.ai project doc
     fletcherview-2026-11/design-notes-v1.md here. -->
