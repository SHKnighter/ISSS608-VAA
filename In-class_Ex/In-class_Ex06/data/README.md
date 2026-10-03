# In Class Exercise 6 data

`aspatial/Hunan_GDPPC.csv` is the instructor's Hunan county GDP per capita
panel: 88 counties, annual observations from 2005 through 2021, 1,496 records.

Source: https://raw.githubusercontent.com/tskam/ISSS626-AY2026-27Aug/master/In-class_Ex/In-class_Ex05/data/aspatial/Hunan_GDPPC.csv

Downloaded on 4 October 2026. SHA-256:
`1c2e81fe553e094fd0eda5522aa79638fff37549236f17e8f94cc63b077ea8ee`.

The `geospatial/Hunan.*` shapefile components are copied byte-for-byte from
Hands-on Exercise 5A in this repository. Their original CRS is WGS 84;
the exercise transforms them to UTM zone 50N (EPSG:32650).

The page creates `rds/analysis_results.rds`, containing the ordered panel,
yearly Gi* statistics, Mann–Kendall results, and emerging hotspot results.
