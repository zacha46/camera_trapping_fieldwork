# camera_trapping_fieldwork

A reusable R workflow for planning, deploying, uploading and retrieving camera trap
(and other sensor) surveys. Each field campaign has its own folder under `campaigns/`
with numbered scripts and a README that logs its design decisions. Helpers that more
than one campaign needs live in `R/`.

## Campaigns

| Campaign | Site | Status |
|---|---|---|
| [`2026-11_fletcherview`](campaigns/2026-11_fletcherview/README.md) | TERN Fletcherview Tropical Rangeland SuperSite, QLD | design v1 reproduced |

## Getting started

```r
# restore the package versions recorded in renv.lock
renv::restore()
```

Raw inputs are not in the repository. Each campaign's `data/raw/README.md` lists what
to put there and where it comes from. Then run that campaign's scripts in order from
the repository root, for example:

```sh
Rscript campaigns/2026-11_fletcherview/01_wind_footprint.R
Rscript campaigns/2026-11_fletcherview/02_design_grid.R
```

## Coordinates and imagery

This repository is public. Camera locations, sensitive species coordinates and
third-party imagery are kept out of it by `.gitignore`; scripts write them to
`outputs/` locally. See `CLAUDE.md` for the rules.
