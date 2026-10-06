# Take-home Exercise 2 data

These inputs are local working copies. Do not commit or publish `raw/`, derived
event-level files, or the source-page snapshots in `../_workflow/sources/`.

| Local input | Source and snapshot |
| --- | --- |
| `raw/ACLED_Data_Myanmar_Jan2021-Sep2025.csv` | User-supplied ACLED export, copied byte-for-byte from `C:/Users/Lenovo/Downloads/Geo/`. The filename labels January 2021–September 2025. The original download date is unknown; the copy time is not the original download date. |
| `raw/myanmar-townships-mimu-v9.4.geojson` | Nationwide MIMU township boundary layer, PCode v9.4; WFS `GetFeature` in EPSG:4326 without a feature limit. The saved response has 330 features. |

Official references:

- [MIMU township layer and use restrictions](https://geonode.themimu.info/layers/geonode%3Ammr_polbnda_adm3_250k_mimu_1)
- [MIMU metadata API](https://geonode.themimu.info/api/layers/?title__icontains=Township&limit=10)
- [ACLED codebook](https://acleddata.com/methodology/acled-codebook)

MIMU's layer metadata requires prior written agreement for use on an online
platform. Bao Sihan confirmed that final online-display permission had been
obtained on 6 October 2026. This release displays the coursework report and
aggregate figures; raw boundary and event files remain local. Online-display
permission is not treated as a general licence to redistribute the raw inputs.
The ACLED codebook snapshot records the methodology available at acquisition;
it does not establish which codebook version applied when the supplied CSV was
originally downloaded.

## Reproduce acquisition

From the repository root, run this command in PowerShell with the original CSV:

```powershell
& './Take-home_Ex/Take-home_Ex02/R/00-acquire.ps1' -AcledSource 'C:/Users/Lenovo/Downloads/Geo/ACLED_Data_Myanmar_Jan2021-Sep2025.csv'
```

The script uses native PowerShell and requires no added packages. It copies the
CSV and retrieves the boundary and reference pages on first use. A rerun checks
recorded SHA-256 hashes and reuses existing snapshots without refreshing them.
It stops if a supplied or existing file differs, rather than replacing it.
An interrupted download may leave a `.pending-*` file for inspection.

`../_workflow/acquisition.json` records the URLs, UTC and Singapore acquisition
timestamps, byte counts, SHA-256 hashes, and source-specific provenance.
The original CSV and local copy must match the recorded hash. New online
downloads can change; retain the saved inputs and manifest to reproduce this
particular analysis snapshot. Analysis outputs belong in `processed/` and are
created by the exercise's cleaning workflow, without modifying `raw/`.
