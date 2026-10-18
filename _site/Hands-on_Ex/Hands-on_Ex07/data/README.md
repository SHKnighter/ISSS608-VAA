# Hands-on Exercise 7 data

Source: user-supplied `Hands-on Exercise 7.zip`, extracted on 2026-10-19. Analysis follows the supplied HTML for *R for Geospatial Data Science and Analytics*, Chapter 17, modified 2026-10-16: https://r4gdsa.netlify.app/chap17.html.

- `geospatial/MP14_SUBZONE_NO_SEA_PL.*`: 323 URA Master Plan 2014 subzones; includes planning-region names. Nine invalid geometries are repaired in the QMD before overlay.
- `geospatial/hexagons.*`: 3,125 teaching grid polygons, described by the chapter as having a 250 m radius.
- `geospatial/ELDERCARE.*`: 120 teaching facility points. Facility `fid` values are nonconsecutive.
- `aspatial/OD_Matrix.csv`: 375,000 unique hexagon-facility pairs; origin/destination IDs plus entry, network, exit and total distances in metres.

Original shapefile and metadata sidecars are retained. The archive's two `.qmd` GIS metadata files are omitted because they are not Quarto source documents or required shapefile components. No source data were edited. Derived scores are computed in memory from relative paths during rendering. Demand and capacity are uniform assumptions of 100; the QMD converts costs to kilometres, aligns the matrix by `fid`, and assigns each hexagon to its greatest-overlap planning region.

The instructor identifies the hexagons, eldercare points and OD table as specially prepared teaching/research data and asks for formal approval for other uses. These files are used here for the supplied coursework exercise. The source boundary year and teaching-data assumptions mean this is not a current service-provision assessment.
