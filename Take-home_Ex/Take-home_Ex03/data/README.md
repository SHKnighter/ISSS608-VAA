# Ex03 data inputs

The public package supports the assignment's original **24 JRL + 12 CRL Phase 1** station targets. Monthly passenger archives are acquired separately with authorised DataMall access. The final analysis uses all four August/September 2026 OD and station-volume archives; their availability and reconciliation have been checked locally. The public-source catalog describes the earlier public-input acquisition stage, not the completion status of the full project.

## Files and provenance

Files live in data/raw/. Original downloads/copies are retained unchanged. The XLS extraction and CSV conversion are explicitly identified derivatives.

| Filename | Provenance / version | Structure |
|---|---|---|
| train-stations-sep2026.zip | User-supplied LTA ZIP, Sep 2026 | 234 station **polygon** records; TrainStation_Sep2026/RapidTransitSystemStation.shp |
| population-2025.csv | User-supplied SingStat, June 2025 | 100,928 rows; PA,SZ,AG,Sex,TOD,Pop,Time |
| population-2025-notes.csv | Supplied notes, generated 29 Sep 2025 | MP2019 geography; rounding and population coverage notes |
| subzones-mp2019.geojson | Official URA / data.gov.sg | 332 no-sea subzones, WGS84; Sep 2021 data vintage, portal updated 3 Dec 2025 |
| bus-stops-sep2026.zip | Official LTA static data, Sep 2026 | 5,205 SVY21 points; BusStopLocation_Sep2026/BusStop.shp |
| station-codes.zip | Official LTA mapping, Jan 2025 | Actual archive member: Train Station Codes and Chinese Names.xls |
| station-codes.xls | Exact extraction from mapping ZIP | 213 line-code rows |
| station-codes.csv | XLS convenience conversion | UTF-8 Chinese text, LF newlines; 213 rows, five columns |
| future-stations.csv | Professor-linked public GitHub repository, pinned commit below | 65 station-code rows |
| operational-stations.csv | Same pinned repository | 213 station-code rows |

The separately acquired passenger inputs are `origin_destination_train_202608.zip`, `origin_destination_train_202609.zip`, `transport_node_train_202608.zip` and `transport_node_train_202609.zip`. Direct station-volume `TOTAL_TAP_IN_VOLUME`, filtered to `WEEKDAY` hours 6–9, supplies the response. OD origin sums provide a separate diagnostic. The local August/September tap-in totals are 18,080,820 and 19,116,754; OD sums are 104,341 and 114,851 lower. No cause for the gap is assumed. The report's ridership-audit table and `output/tables/ridership-audit.csv` document the completed checks. Raw passenger files and credentials are excluded from Git and website resources.

GitHub snapshot: elliotwutingfeng/singapore_train_station_coordinates, commit 9f5972c71db8a529801eee9c527946a45a78e409. Both source CSVs have station_code,station_name,lat,lon,source,comment. Interchanges can appear more than once under different codes; these are not counts of unique physical stations. Coordinates are decimal degrees. The source/comment columns identify provenance, including manually supplied locations.

Mapping CSV columns: stn_code,mrt_station_english,mrt_station_chinese,mrt_line_english,mrt_line_chinese. Its January 2025 vintage does not establish current operation.

Bus stops have BUS_STOP_N (character identifier, preserve leading zeroes), STATUS, SERVICE_TY, LOC_DESC, RD_CD and other administrative fields. All 5,205 supplied rows have STATUS = OP and unique stop codes. Service type values include BA, BO, 0, BT, NA, BI, NB, and BD; a semantic restriction needs separate justification. The train polygons use STN_NAM codes and LIN_NAM. Both shapefiles carry SVY21 metre-grid parameters in their PRJ; inspect the source CRS before assigning EPSG:3414. Complete schemas, samples and PRJ text are in data/metadata/input-structure.json.

## Important scope decisions

- Keep the original 24 JRL targets. LTA's March 2026 update adds JS2A Forest Hill as a 25th station for the mid-2030s. The original 24 exclude JS2A. JRL stage 1 now targets mid-2028; stage 2 2028, stage 3 2029. CRL1 targets 2030.
- The professor CSV's older operational/future labels are reconciled with the actual monthly data. Official CCL6 evidence records CC30 Keppel, CC31 Cantonment and CC32 Prince Edward Road opening on 12 July 2026; all three occur in both observation months and are included in the baseline. CC33/CC34 are aliases of Marina Bay/Bayfront. Stevens' separate DT10/TE11 observations are combined. The 185 published units map to 184 physical stations, with no unresolved codes or missing morning code-hour records.
- NE18 Punggol Coast, DT4 Hume and PW2 Teck Lee are already included as operational. Closed BP14 Ten Mile Junction is absent. TE10, TE21 and TE22A are deferred.
- TE30/TE31 and DT36/DT37 have 2026 target language, but the initial official-source check did not establish their opening by September. None occurs in either month's passenger archive. They are outside the observed baseline; an absent record is not converted to a zero observation or used to claim an opening date.
- Population remains June 2025 deliberately. Notes specify MP2019 boundaries and nearest-10 rounding; zero and missing data need distinct handling. The live catalogue's newer 2026 data has not replaced these supplied originals.

Exact target codes, interchange evidence and current-roster caveats are in data/metadata/rail-evidence.json. Public URLs, SHA-256 hashes, acquisition UTC, version and license notes are in _workflow/acquisition.json and data/metadata/public-source-catalog.json.

## Reproduce acquisition

Run from the exercise directory:

~~~powershell
python R/acquire-public.py --verify
python R/acquire-public.py --download
~~~

The default is offline verification. Only explicit --download uses the network; Quarto render must never invoke it. Existing matching files are retained; a mismatch fails instead of replacing an original. Requests have a 40-second timeout and at most three attempts. Missing local copies can be supplied using --local-train and --local-population-dir. A missing CSV derivative is regenerated with installed R/readxl; use --rscript if needed. The converter sets a Windows UTF-8 locale and verifies Chinese characters survive.

The data.gov.sg public poll-download flow briefly returns an expiring S3 URL. The script saves the downloaded data and stable source URL, never that signed URL. No LTA key, browser account, cookies, authenticated session, HDB or OSM inputs are used.

## Sources and reuse

Primary catalogues: [LTA static data](https://datamall.lta.gov.sg/content/datamall/en/static-data.html), [URA no-sea subzones](https://data.gov.sg/datasets/d_8594ae9ff96d0c708bc2af633048edfb/view), [SingStat geographic distribution](https://www.singstat.gov.sg/find-data/explore-data-themes/population/geographic-distribution), and the [pinned station repository](https://github.com/elliotwutingfeng/singapore_train_station_coordinates/tree/9f5972c71db8a529801eee9c527946a45a78e409).

URA's portal dataset and the GitHub **dataset** use Singapore Open Data Licence 1.0. GitHub **source code** uses Apache-2.0; both notices are retained in data/metadata/. Direct LTA downloads are recorded under [DataMall Terms of Use](https://datamall.lta.gov.sg/content/datamall/en/term-of-use.html), without assuming a blanket open-data license. The supplied population folder has no license file; cite Singapore Department of Statistics and retain its notes. Raw inputs are for local coursework review.

Evidence retrieval hashes are retained in data/metadata/source-access.json; full official page/PDF bodies are not copied into the report. The old LTA Ten Mile Junction PDF is searchable through the web tool but its direct GET returned 404; this failure is recorded and an official SMRT timetable is provided as a fallback. Initial default-user-agent 403 responses and the unreadable SingStat page body are also recorded truthfully.


The nonsecret acquisition catalog, source evidence and license notices in data/metadata are versioned source inputs. They remain excluded from website resources. Runtime manifests, verification logs and collaboration recovery records remain private in _workflow.
