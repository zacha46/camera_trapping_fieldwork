# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Session start

Read this section first, every session, before writing anything.

### The three style guides are binding

Read all three at session start. They govern more than formatting — where one of
them disagrees with a prompt, the style guide wins and you say so rather than
quietly picking one.

| What it governs | Path |
|---|---|
| All R code | `/Users/zachary_amir/Dropbox/UQ Years/UQ 2026 & WildObs/AI formatting style guides/zachary_amir_R_coding_style.md` |
| All R comments | `/Users/zachary_amir/Dropbox/UQ Years/UQ 2026 & WildObs/AI formatting style guides/zachary_amir_R_commenting_style_guide.md` |
| All prose, including README decision logs and figure captions | `/Users/zachary_amir/Dropbox/UQ Years/UQ 2026 & WildObs/AI formatting style guides/zachary_amir_scientific_writing_guide.md` |

The short version of the code rules, which does not replace reading the guides:

- Comments explain data transformations, statistical intent or ecological
  interpretation in plain English, never syntax.
- Comments describe the current state of the code only. A comment that only makes
  sense to someone who knows what the code used to be gets deleted. History lives
  in a campaign README decisions log or a commit message.
- Never mark a section with a banner rule of repeated `#`, `-` or `=`. RStudio's
  Jump To navigator builds a nameless section out of any such line.
- One comment per step, sitting directly above the line it explains, in multi-line
  pipe chains and in failure-scenario checks. Never hoist them into a block.
- `here()` for every path.
- No hard-coded derived number in prose. Every quotable result is written by a
  script to a `*_summary_vN.csv` in that campaign's `outputs/`, and READMEs point
  there. Design *inputs* (grid spacing, bearing ranges) are decisions, not results,
  and may be stated.
- Heavy commenting is expected. Assume the reader knows ecology and is rusty on R.
- Native pipe `|>`, `<-` assignment, `TRUE`/`FALSE` spelled out, `data.frame()` not
  `tibble()`, no `stopifnot()`, `sprintf()` for messages with two or more values.

### Commit discipline

Do not work on the `main` branch. Check `git status` before starting and
report a dirty tree rather than committing someone else's work in progress.

- Work on a branch named `claude/<slug>`. Zach reviews the branch and opens the PR.
- Commit at every phase gate, without being asked. One commit per phase minimum,
  more where a phase produces genuinely separable pieces.
- Commit **before** stopping for approval, so what is approved is what is recorded.
- Commit messages say what changed and why, in plain English.
- Never amend, rebase or force-push. If something needs undoing, say so.
- Say explicitly in the phase report if `.gitignore` was touched.

### Who decides what

- Any ambiguity about ecological meaning, survey design or field logistics is
  Zach's call: stop and ask, don't guess.
- Ambiguity about implementation (naming, structure, helper functions) is yours:
  pick one and note it in the phase report.
- End every phase report with two lists: "Decisions I made" and "Needs your review
  and testing". Flag anything you could not verify.

### Dependencies

R only. The approved set is `tidyverse`, `sf`, `terra`, `here`, `ncdf4` (or
`tidync`), plus `renv`. **Ask before adding any other package**, even a small one.
`renv.lock` records versions; run `renv::snapshot()` after an approved addition.

## Public repo, sensitive coordinates

This repository is public. Raw coordinates of sensitive species records never go
into it, and neither do camera locations or third-party imagery. `.gitignore`
enforces the defaults:

- `campaigns/*/data/raw/*` is ignored except its `README.md`, which says where each
  input comes from. Raw inputs are large (OzFlux netCDF, QTopo GeoPDFs) or not ours
  to redistribute (Google satellite screenshots).
- Coordinate-bearing outputs (`*.gpkg`, `*.kml`, `*points*.csv`) and preview figures
  drawn over imagery are ignored. Wind roses and summary tables are tracked.
- If a new output carries coordinates, name it so a rule already catches it, or add
  a rule, before the first run that writes it.
- Never print species-record coordinates into a commit message, issue, PR or README.

## What this repo is

Reusable R workflow for planning, deploying, uploading and retrieving camera trap
(and other sensor) surveys, run by Zach Amir (TERN / WildObs). Each field campaign
gets its own folder; code that more than one campaign needs moves into `R/`.

```
R/                         shared helpers, one function per file, loaded with source()
templates/                 gear lists, checklists, camera settings, form definitions
campaigns/<YYYY-MM_site>/
  README.md                decisions log for this campaign (the authority on why)
  NN_<step>.R              numbered scripts, run in order
  data/raw/                inputs (ignored except README.md)
  data/processed/          intermediate files written by the scripts
  outputs/                 gpkg, kml, csv, figures, versioned _vN
```

There is no build system and no test suite. Scripts are run top to bottom with
`Rscript campaigns/<campaign>/NN_<step>.R` from the repo root, or sourced in RStudio.

### Helpers in `R/`

`R/` is written as package code so it can become a package later without a rewrite:

- one exported function per file, file named after it;
- roxygen header with `@author`, `@param`, `@return`;
- never `library()`; every call qualified `pkg::fun()`;
- validate inputs at the top and `stop()` with a message that says what to do next.

Scripts load the helpers with `source(here::here("R", "<file>.R"))`, one line each.

### Output versioning

Every output carries a design version suffix (`_v1`, `_v2`, ...) set once at the top
of the script that writes it. A change to design rules bumps the version and is
logged in the campaign README; old versions are not overwritten.

### Campaign-specific knowledge

Each campaign README holds the design decisions, their reasons, and the validation
against any earlier version. Read it before changing that campaign's scripts.

## Where notes go

`.claude/prompts_and_responses/<topic>/` (gitignored) holds the back-and-forth with
Zach: prompts, review notes, question lists. One subdirectory per topic; add to an
existing one before creating another.

## Not in this repo

Reading camtrap DP packages, camDB queries and WildObs data model questions belong in
[WildObsR](https://github.com/WildObs/WildObsR). If a fieldwork task (EpiCollect
imports, image-platform uploads, pulling annotated data) turns out to be general,
say so before writing it here.
