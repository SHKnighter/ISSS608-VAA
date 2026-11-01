# Take-home Exercise 3: morning station demand

Author: Bao Sihan. Course: ISSS626.

This project estimates weekday 06:00–09:59 MRT/LRT station entries and examines a fixed-demand JRL24/CRL Phase 1 expansion scenario. It contains the technical report, eight-body-slide summary, actual August/September 2026 analysis, figures and reproducible source.

## Inputs and environment

The recorded environment uses R 4.6.1 and Quarto 1.10.18. Preparation requires sf, readr, units, jsonlite and digest; figures and reporting also require ggplot2, patchwork, ggrepel and knitr. readxl converts the official station-code workbook during acquisition. Core estimation uses base R. MCI 1.3.3 supplies the classroom-method reference. Python acquisition uses the standard library. Install dependencies before reproduction; rendering performs no software installation or data downloads.

See data/README.md for public sources and licences. Original inputs live in data/raw; analysis caches live in data/processed. These are excluded from Git/site delivery. Reproduction requires obtaining the documented originals first. Versioned public provenance lives in data/metadata. Runtime manifests and local recovery records are in _workflow. Both are excluded from site delivery.

## Data access and commands

Run commands from this exercise directory. Public acquisition is explicit and idempotent:

```powershell
python R/acquire-public.py --download
python R/acquire-public.py --verify
```

Apply for a DataMall AccountKey at https://datamall.lta.gov.sg/content/datamall/en/request-for-api.html. Registration sends separate DataMall API Access Key and SDK Account Key emails; use the API key (SDK guide section2.1, page19). On Windows, double-click `download-ridership.cmd` to open the local Chinese download window: a masked input field shows stars and a character count, and a status panel displays safe HTTP/network/month diagnostics. This entry point works under Restricted PowerShell policy without changing that policy. Alternatively run `python R/ridership-ui.py`, use the console fallback `python R/acquire-ridership.py --download --prompt`, or configure LTA_ACCOUNT_KEY in your local process and run `python R/acquire-ridership.py --download`. Credentials stay in process memory, not project files. The older PS1 wrapper remains available only where local script policy permits it. The helper requests August/September2026 OD and station-volume ZIPs. `--check` is an offline readiness check. Keep downloaded originals because API history is limited.

After all documented raw inputs are present, render the deliverables **in this order** from this exercise directory:

```powershell
$env:LC_ALL='C'
quarto render technical-report.qmd
quarto render executive-summary.qmd
quarto render Take-home_Ex03.qmd
```

The technical report runs preparation, observation alignment, fitting and figure generation, then records the analysis fingerprint. The summary verifies these completed outputs; rendering it before the report on a clean checkout stops for missing analysis or figures. The overview links to both pages. For a later prose-only report change with valid saved outputs, use `quarto render technical-report.qmd -P recompute:false`.

To run analysis stages separately for diagnosis, use Rscript on `R/01-prepare-public.R`, `R/02-prepare-ridership.R`, `R/03-model-scenarios.R` and `R/04-figures.R`. The report-first route above also creates the fingerprint needed by the summary and is the supported complete reproduction sequence.

Prepared caches store SHA256 fingerprints of required public inputs, all four passenger archives and preparation code. Step 03 rejects stale or unversioned caches before fitting. Step 02 stops for missing real data, unresolved station codes or incomplete reference coverage. In the final August/September analysis, 185 published code units reconcile to 184 physical stations with complete morning hours in both months. Direct PV tap-ins control the entry target; OD sums remain diagnostic, with their actual 0.58–0.60% gap retained without an assumed cause. No missing station is silently assigned zero.

## Interfaces and assumptions

- Population: official MP2019 subzone ID, June2025 residents summed over disjoint age/sex/dwelling categories; population is rounded and is a demand proxy.
- Station: one physical interchange unit; each line code maps to one station_id. Reference operating status corrects the stale coordinate library's CCL6 classification using the official July2026 opening.
- Distance: EPSG3414 metres, subzone interior points to station representatives, 100m minimum for Huff calculations.
- Attraction: (1 + unique bus stops within500m) times distinct rail-line count. Existing/future stations use the same definition; future bus supply is held fixed.
- Estimation: two common parameters, bounded multistart station-share least squares. August calibration, September conditional-share validation, final September fit. Monthly network demand is known, so validation does not test total-demand forecasting.
- Expansion: existing, +JRL24 excluding JS2A, +CR2..CR13, +both. Existing interchanges receive additional lines, not duplicate competitors. Scenario changes compare model predictions to the model baseline.

## Offline checks

```powershell
& 'C:/Program Files/R/R-4.6.1/bin/x64/Rscript.exe' --vanilla tests/test-data.R
& 'C:/Program Files/R/R-4.6.1/bin/x64/Rscript.exe' --vanilla tests/test-public.R
& 'C:/Program Files/R/R-4.6.1/bin/x64/Rscript.exe' --vanilla tests/test-model.R
& 'C:/Program Files/R/R-4.6.1/bin/x64/Rscript.exe' --vanilla tests/test-scenarios.R
python tests/test-ridership-download.py
```

Toy observations used by offline tests stay in test fixtures, not analysis outputs. Public-input checks use the actual acquired data. Actual-input preparation, fitting, figures and report have passed an end-to-end Quarto run. Validation WAPE is 49.56% for Huff, 61.66% for the distance-only reference and 1.35% for August shares scaled to September's known total. The last comparison shows weak short-term predictive performance at existing stations. Expansion outputs are conditional spatial scenarios with substantial limits.
