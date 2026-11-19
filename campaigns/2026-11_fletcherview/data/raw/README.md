# Raw inputs — 2026-11 Fletcherview

None of these files are committed. Put them in this folder before running the scripts.

| File | What it is | Source | Used by |
|---|---|---|---|
| `FletcherviewTropicalRangeland_2023_L3.nc` | OzFlux L3 30-minute flux and met data, 2023 | OzFlux data portal, site AU-Fle (CC BY 4.0) | `01_wind_footprint.R` |
| `FletcherviewTropicalRangeland_2024_L3.nc` | as above, 2024 | as above | `01_wind_footprint.R` |
| `FletcherviewTropicalRangeland_2025_L3.nc` | as above, 2025 to 18 July | as above | `01_wind_footprint.R` |
| `QTopo_25k_8158-31.pdf`, `QTopo_25k_8158-32.pdf` | QTopo 1:25k GeoPDF sheets covering the station | Queensland Government QTopo (CC BY 4.0) | `02_water_and_basemap.R` (basemap) |
| `QTopo_25k_8158-33.pdf`, `QTopo_25k_8158-34.pdf` | neighbouring sheets, wholly west of the station | as above | not used |
| `propertyScreenshot.png` | Google satellite screenshot, 1458 x 1013 px, north-up; property boundary hand-drawn in red | screenshot by ZDA | provenance only: the boundary in `03_design_grid.R` was traced from it |

The hydrography is downloaded by `02_water_and_basemap.R` from the Queensland
Government "Water courses and bodies" map service, so it needs no file here.
