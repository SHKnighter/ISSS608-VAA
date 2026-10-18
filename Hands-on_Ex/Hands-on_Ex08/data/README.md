# Exercise 8 data provenance

The input files were supplied by the user in `Hands-on_Ex08.zip` for a local reproduction of the instructor's [Chapter 18: Market Area Analysis for Retail and Service Locations using Huff model](https://r4gdsa.netlify.app/chap18). The saved instructor HTML records a modification date of July 20, 2026. Extracted for this exercise on October 19, 2026.

Archive SHA-256: `53c477238076480ffc36c02aa120213756b6720a34f9d809dc9bc3fd0ab3b106`.

## Retained source data

| Relative path | Content | Records |
|---|---|---:|
| `geospatial/STORES_TC.shp` and supplied `.dbf`, `.shx`, `.prj` | Store points | 28 |
| `geospatial/TOWN_TC.shp` and supplied `.dbf`, `.shx`, `.prj`, `.cpg` | Town polygons | 28 |
| `geospatial/VILLAGE_TC.shp` and supplied `.dbf`, `.shx`, `.prj`, `.cpg` | Village multipolygons | 622 |
| `aspatial/pop2019.csv` | 2019 population by village | 625 |
| `aspatial/Store_sales_data.csv` | Store-level sales records by point of delivery | 5,499 |

All geospatial layers are supplied in TWD97 / TM2 zone 121 (EPSG:3826), with metre coordinates. Source files are unchanged. The teaching HTML's opening list refers to `*_TN`; the executable code and supplied archive use `*_TC`, which this page follows. The duplicate `STORES_TC1` layer, `storeCD.csv`, and shapefile `.qmd` metadata files are not used or copied.

## Preparation and scope

The analysis removes hyphens from population `V_ID` before matching to `VILLCODE`. Five polygons have no matched population, and eight population rows have no matching polygon. Following the instructor, only the 617 matched villages are modelled, totalling 2,804,359 residents. No missing population is imputed. The sales table contains 234 store codes; the 28 mapped stores all match, while 206 codes outside the store layer do not enter the model.

Sales are imported with `na = ""` because `NA` is a literal store code in 29 CSV records. The default reader's missing-value marker would otherwise erase that identifier. It belongs to the 206 codes outside the mapped layer, so this import correction does not change the 28-store results.

Store attractiveness is uniformly 100. Distance is straight-line distance from `st_point_on_surface()` village interior points, not network distance. The MCI 1.3.3 defaults are made explicit: power attractiveness with gamma=1 and power distance with lambda=-2. `shares.total()` weights probabilities by resident population; its output is potential in people, not sales currency. The source archive does not establish sales period or currency, so the observed `Amount` units are retained as supplied.

The QMD checks exact keys and matrix ordering, completeness of all 17,276 village-store pairs, the within-village Huff denominator, probability bounds and sums, and conservation of total population. No external data, geocoding, or routing service is used.

## R environment

The local reproduction uses R 4.6.1 with sf 1.1.2, tidyverse 2.0.0, MCI 1.3.3, tmap 4.4.1, and ggstatsplot 1.1.1. Package installation is shown as a non-executing setup example in the page. All input paths are relative to the exercise folder.
