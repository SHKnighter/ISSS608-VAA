# Take-home Exercise 2

This folder is the source for the Myanmar township conflict analysis. The
technical report and eight-slide executive summary use the same saved results.
The study covers January 2021–September 2025 and the three selected ACLED event
types. The report and slides form part of Bao Sihan's ISSS626 coursework website.

## Inputs and environment

See [data/README.md](data/README.md) for the supplied CSV, official MIMU v9.4
boundary, acquisition command, checksums and public-use restrictions. Restricted
inputs and event-level derivatives are deliberately not committed. Analysis
requires these local inputs; figures alone cannot recreate the analysis.

The verified environment is R 4.6.1 and Quarto 1.10.18, with sf 1.1.2,
spdep 1.4.2, sfdep 0.2.5, tmap 4.4.1 and Kendall 2.2.2. The workflow checks
dependencies rather than installing or upgrading packages automatically.

## Run from this folder

```powershell
quarto render technical-report.qmd
quarto render executive-summary.qmd
quarto render Take-home_Ex02.qmd
```

The normal report render reads the original local inputs, prepares and joins
events, builds the complete panel, calculates LMSA and EHSA, and draws figures.
EHSA reuses an exactly matching saved Gi* simulation. To explicitly run a fresh
999-permutation EHSA calculation, use `Rscript R/03-ehsa.R --recompute`; this may
take a substantial time. Do not launch a second copy while it is running.

For wording or layout edits, use `quarto render technical-report.qmd -P recompute:false`.
This verifies analysis input, output and runtime fingerprints
before using the cached results. A changed data source, analysis script or
result file needs review and the appropriate analysis stage to run again.

## Files

- `R/00-acquire.ps1`: acquisition and SHA-256 provenance.
- `R/01-prepare.R`, `R/cleaning.R`: scope, precision and unique spatial joins.
- `R/02-panel-lmsa.R`, `R/lmsa-helpers.R`: complete panel, Queen weights, Local
  Moran and Gi*, BH comparison and precision-1 sensitivity.
- `R/03-ehsa.R`, `R/ehsa-helpers.R`: original sfdep Gi*, saved raw output and
  locally tested sign-aware history categories.
- `R/04-figures.R`: source-backed figures shared by report and slides.
- `tests/`: data reconciliation, statistical edge cases, ordering and output
  acceptance checks; no production permutations are launched by the tests.
- `output/tables/`, `output/figures/`: aggregate evidence and rendered figures.
- `_workflow/`: provenance, version records, logs, review and recovery notes.

Meaningful validation commands, from this folder:

```powershell
Rscript tests/test-cleaning.R
Rscript tests/validate-prepared.R
Rscript tests/test-lmsa.R --artifacts
Rscript tests/test-ehsa.R
python tests/validate-pages.py
```

The page check expects the three exercise pages, the home page and the
take-home overview to have been rendered into the existing `_site` directory.
Successful checks are reused for unchanged artifacts. Raw data, boundary
downloads and local workflow files are excluded from website resources.
