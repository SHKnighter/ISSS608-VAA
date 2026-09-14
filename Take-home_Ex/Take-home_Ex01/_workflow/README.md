# Reproduction and recovery

This folder records provenance, runtime information, validation and local review.

- `acquisition.json`: NASA/BIG source details and SHA256 hashes.
- `parameters.txt` and `parameters.rds`: bandwidths, grid, distances and seeds.
- `prepare.log`, `analyse.log`: processing evidence; the local `report-render.log` is not versioned.
- `session-info.txt`: R and package versions used for the analysis.
- Local `REVIEW.md`, `checkpoint.json` and `PROF_REQUIREMENTS_CHECKLIST.md` support review and recovery and are not versioned.
- `final-review-counts.log`: independent raw CSV and polygon selection counts, plus selected curve checks.
- `final-review-validation.log`: final local resource, page-limit and preservation checks.

Work from `Take-home_Ex/Take-home_Ex01` for the R scripts. A standard render of `technical-report.qmd` executes `R/01-prepare.R` and `R/02-analyse.R` from local raw data. This includes 398 simulated reference patterns and can take several minutes. Render `executive-summary.qmd` afterwards; it consumes the report's verified results. Keep the two supplied FIRMS CSV filenames unchanged.

For wording-only edits, use `quarto render technical-report.qmd -P recompute:false`; the cache guard must validate inputs, analysis scripts and outputs before reuse. Do not bypass or blindly regenerate its fingerprint. The slide render also calls `R/03-presentation-figures.R` to redraw presentation PNGs from the same saved results, without repeating the analysis or simulations.

On this Windows installation use R 4.6.1 and the existing user package library. Set the process locale to `LC_ALL=C`; source text is explicitly UTF-8. The restricted shell has a different R library view, so host execution may be required. Do not reinstall packages solely because a restricted session cannot see them.

After interruption, first read `C:/Users/Lenovo/Downloads/Geo/RESUME.md`, inspect any recorded process and the logs, and check completed outputs before restarting. A successfully saved first-order result or simulation envelope is a checkpoint, not proof that the report is complete. Never invent missing results. Preserve local changes and raw inputs.

Publication is separate from local rendering. GitHub stores the reproducible project and rendered website; Netlify publishes `_site`. Preserve the raw inputs and fingerprinted results when preparing a release.
