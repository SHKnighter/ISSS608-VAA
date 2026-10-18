# Exercise 7 inputs

These are the instructor's original teaching files from `tskam/ISSS626-AY2026-27Aug`, commit `641bd779e733218874a95238aae53d3e3b1d5ecf`, under `In-class_Ex/In-class_Ex07/data`.

- `geospatial/MP14_SUBZONE_NO_SEA_PL.*`: 323 planning subzones.
- `geospatial/hexagons.*`: 3,125 demand polygons.
- `geospatial/ELDERCARE.*`: 120 provider points.
- `aspatial/OD_Matrix.csv`: 375,000 origin-destination pairs. Costs are metres; the QMD converts them to kilometres.

`PROVENANCE.json` records upstream paths, file sizes, Git blob IDs and local SHA-256 hashes. `VALIDATION.json` records the acquisition checks. The source files remain unchanged. The QMD repairs nine invalid subzone geometries in memory and explicitly aligns OD rows/columns by `fid`, including the gaps in provider IDs.

Capacity 100 per centre and demand 100 per hexagon are classroom assumptions assigned by the QMD. These files are not a current survey of eldercare supply or demand.
