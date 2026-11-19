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
- `outputs/design_summary_v2.csv` — scale, node counts by status, water flags, MCP
  areas against the target, extents (`design_summary_v1.csv` holds the v1 design)

## How to run

From the repository root, after placing the raw inputs listed in
[`data/raw/README.md`](data/raw/README.md):

```sh
Rscript campaigns/2026-11_fletcherview/01_wind_footprint.R
Rscript campaigns/2026-11_fletcherview/02_water_and_basemap.R   # needs internet and a system GDAL
Rscript campaigns/2026-11_fletcherview/03_design_grid.R
```

`02_water_and_basemap.R` reads the QTopo GeoPDFs with the command-line GDAL tools,
because the GDAL bundled with the CRAN builds of sf and terra cannot read PDFs. On
macOS, `brew install gdal` provides them. Its outputs are cached in `data/processed/`,
so it only needs re-running if the area or the sheets change.

Coordinate-bearing outputs (the QField folder, KML, points CSV, preview) are written to
`outputs/` locally and are never committed.

## Field map in QField

`outputs/qfield_v2/` is a self-contained QField project:

| File | Contents |
|---|---|
| `fletcherview_v2.qgs` | the project: layer order, symbols, labels, opening view |
| `fletcherview_design_v2.gpkg` | planned points, flux tower, approximate boundary, footprint wedge, mapped channels, 500 m water zone, and an empty `deployments` layer |
| `qtopo_basemap.tif` | QTopo 1:25k basemap (sheets 8158-31 and -32), 3 m pixels, works offline |

Copy the whole folder to the phone (on iOS, into QField's folder via the Files app) and
open the `.qgs`. Every layer except `deployments` is read-only. To log a camera, add a
point to `deployments` at the tree: pick the `point_id` from the drop-down, type the
`deployment_id` (the ID used in EpiCollect), and `recorded_at` fills itself with the
current time. The KML in `outputs/` holds the same points for Google Earth.

## Design v2

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
`wind_summary_v1.csv`). The wind analysis is unchanged from v1.

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

**Status.** The first rule that matches wins.

| Status | Rule | Field meaning |
|---|---|---|
| `footprint` | the tower node, or within 2,000 m at a bearing of 10–125° | upwind source area; deploy first, even near water |
| `reserve` | bearing 170–330°, farther than 1,600 m, and odd `i + j` (checkerboard thin of the far western block) | deploy only if cameras are spare |
| `drop_first` | within 500 m of a mapped channel, **or** grid offset (i = −3, j = 3) or (i = −3, j = 1) | planned, but the first to give up on the day (wet-season access, cameras short) |
| `core` | everything else | deploy |

`i` and `j` are the grid column and row offsets from the tower (east and north
positive). Each `drop_first` point carries a `drop_reason`, and every point carries a
`near_water` flag, so footprint and reserve points near water are visible too.

**Outputs.** The QField folder above; a KML with the boundary, points in one folder per
status, and the flux tower; a points CSV; and a preview over the QTopo basemap with
legends for camera status and every map layer.

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

**2026-11-19 — v2: wet-season water rule (ZDA).** Any camera within 500 m of a river or
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

**Planned and worst-case coverage.** With the water rule, the planned set (every
non-reserve point) still covers the v1 MCP, but if every `drop_first` camera is given
up the remaining footprint and core cameras cover well under the 15 km² analysis
minimum (`mcp_first_choice_km2` against `mcp_target_km2` in `design_summary_v2.csv`).
The lost area is the grid's outer corners near the channels: the north-west (FV01, FV05),
the north and east along the Burdekin (FV04, FV12, FV21) and the south (FV30, FV34).

## Open questions

- **Worst-case MCP below target.** If all `drop_first` cameras are skipped, coverage
  falls below 15 km². Should some outer `drop_first` nodes be kept regardless (for
  example FV05 and FV34, which sit near the edge of the 500 m zone), or should a camera
  be moved away from the channel within its 100 m search radius instead of dropped?
- **Boundary accuracy.** Over QTopo, the traced north boundary runs inside the Burdekin
  channel, where the screenshot trace followed the south bank, so the trace is out by
  roughly 100–200 m there. FV01 and FV03 sit in or beside the mapped channel. The fix is
  still the cadastral parcel (see the to-do in the design notes).
- **Reserve near water.** FV02 and FV06 are reserve and within 500 m of a channel. They
  stay reserve; say if they should be removed altogether.

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
