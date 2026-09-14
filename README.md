# ISSS626 Geospatial Analytics and Applications

Coursework website by Bao Sihan, built with Quarto and published on Netlify.

[Visit the website](https://isss626-2025-26t4-bao-sihan.netlify.app/)

## Repository layout

| Location | Contents |
|---|---|
| `Hands-on_Ex/` | Hands-on exercises, source documents and exercise data |
| `Take-home_Ex/` | Take-home reports, presentations, R scripts and data |
| `_site/` | Rendered website deployed by Netlify |
| `_quarto.yml` | Website navigation, style and render targets |
| `tests/` | Checks for the existing hands-on exercises |

The repository keeps its original name, `ISSS608-VAA`, so existing GitHub and Netlify connections continue to work. Its current coursework is ISSS626.

## Take-home Exercise 1

The exercise studies satellite thermal detections in Kapuas Regency from January to August 2026 using data preparation, monthly summaries, kernel density estimation and L-function comparisons.

- [Technical report](https://isss626-2025-26t4-bao-sihan.netlify.app/Take-home_Ex/Take-home_Ex01/technical-report.html)
- [Executive summary](https://isss626-2025-26t4-bao-sihan.netlify.app/Take-home_Ex/Take-home_Ex01/executive-summary.html)

Within `Take-home_Ex/Take-home_Ex01/`, `data/raw` preserves the downloaded files, `data/processed` holds prepared spatial objects and simulation results, `R` contains the analysis scripts, `output` contains analytical figures and tables, and `_workflow` records provenance, parameters, versions and verification evidence. Presentation images are in `presentation/figures`.

## Reproduce and publish

Use R and Quarto with the packages and versions listed in the report. From `Take-home_Ex/Take-home_Ex01`, run:

```sh
quarto render technical-report.qmd
quarto render executive-summary.qmd
```

The report rebuilds the analysis from the saved raw inputs, including 398 simulated reference patterns. For wording-only edits, `quarto render technical-report.qmd -P recompute:false` validates the saved input and output fingerprints before reusing results.

Render website changes locally and include the resulting `_site` updates in the commit. Netlify serves `_site` from the production branch; it does not need to run the R analysis remotely. Local review notes, caches and unused alternate presentation exports are excluded from Git.
