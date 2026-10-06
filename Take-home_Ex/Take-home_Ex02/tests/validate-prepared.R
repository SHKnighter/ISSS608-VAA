# Independent acceptance checks for the approved supplied data snapshot.
suppressPackageStartupMessages(library(sf))
p <- readRDS('data/processed/prepared.rds')
a <- p$audit; e <- p$events; b <- p$townships
stopifnot(nrow(e)==53899L,nrow(b)==330L,
          !anyDuplicated(e$event_id_cnty),!anyDuplicated(b$TS_PCODE),
          all(st_is_valid(b)),!any(st_is_empty(b)),
          st_crs(b)$epsg==4326,all(b$PCode_V==9.4),
          identical(b$TS_PCODE,sort(b$TS_PCODE)),
          all(e$country=='Myanmar'),all(e$geo_precision %in% c(1,2)),
          all(e$event_type %in% c('Battles','Explosions/Remote violence','Violence against civilians')),
          all(e$event_date>=as.Date('2021-01-01') & e$event_date<=as.Date('2025-09-30')),
          all(e$fatalities>=0),length(unique(e$month))==57L,
          nrow(e)+sum(a$removed)==87109L,
          all(head(a$remaining,-1)==tail(a$input,-1)),
          nrow(p$unresolved)==8L,all(p$unresolved$spatial_matches==0L),
          sum(e$name_check=='missing')==102L,
          sum(e$name_check=='different')==8L)
# Unique containment was established during preparation. Recheck the retained
# assignments against their own polygons without another all-polygon join.
pts <- st_as_sf(e,coords=c('longitude','latitude'),crs=4326)
for(code in unique(e$TS_PCODE)) {
  stopifnot(all(lengths(st_intersects(pts[e$TS_PCODE==code,],b[b$TS_PCODE==code,],model='closed'))==1L))
}
m <- readRDS('_workflow/prepare-manifest.rds')
for (h in list(m$input_hashes,m$output_hashes)) stopifnot(identical(tools::md5sum(names(h)),h))
cat('PASS: 53,899 unique events, 330 valid v9.4 townships, 57 observed months, matched containment, complete reconciliation and cache fingerprints.\n')
