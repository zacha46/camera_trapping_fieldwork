# Raw inputs — 2026-11 Fletcherview

None of these files are committed. Put them in this folder before running the scripts.

| File | What it is | Source | Used by |
|---|---|---|---|
| `FletcherviewTropicalRangeland_2023_L3.nc` | OzFlux L3 30-minute flux and met data, 2023 | OzFlux data portal, site AU-Fle (CC BY 4.0) | `01_wind_footprint.R` |
| `FletcherviewTropicalRangeland_2024_L3.nc` | as above, 2024 | as above | `01_wind_footprint.R` |
| `FletcherviewTropicalRangeland_2025_L3.nc` | as above, 2025 to 18 July | as above | `01_wind_footprint.R` |
| `propertyScreenshot.png` | Google satellite screenshot, 1458 x 1013 px, north-up; property boundary hand-drawn in red, tower footprint in orange | screenshot by ZDA | `02_design_grid.R` (preview background only) |
| `QTopo_25k_8158-33.pdf` | QTopo 1:25k GeoPDF basemap for field navigation | Queensland Government QTopo | not used by the scripts |
| `fletcherview_planned_points_v1.csv` | *optional* v1 planned points from the original chat session | ZDA | `02_design_grid.R` validation, skipped if absent |

The boundary polygon is traced from `propertyScreenshot.png` in pixel coordinates and
is written into `02_design_grid.R`, so the design itself does not need the image.
