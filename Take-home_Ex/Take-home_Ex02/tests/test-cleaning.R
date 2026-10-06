# Run from the Exercise 2 directory: Rscript --vanilla tests/test-cleaning.R
# These fixtures catch accidental scope expansion, dropped missing names,
# duplicate event counts, spatial join multiplication, and CRS mismatch.
suppressPackageStartupMessages(library(sf))
if (file.exists('R/cleaning.R')) source('R/cleaning.R')
stopifnot('Data preparation functions have not been implemented' =
            exists('filter_events') && exists('assign_townships'))
expect_error <- function(expr, text) {
  err <- tryCatch({force(expr); NULL}, error = identity)
  stopifnot(inherits(err, 'error'), grepl(text, conditionMessage(err), fixed=TRUE))
}
d <- data.frame(
  event_id_cnty=paste0('E',1:9),
  event_date=c('2021-01-01','2025-09-30','2022-05-01','2023-05-01',
               '2025-10-01','2024-06-01','2022-01-01','2024-01-01','bad'),
  country=c('Myanmar','Myanmar','Indian Ocean',rep('Myanmar',6)),
  event_type=c('Battles','Violence against civilians','Battles','Protests',
               rep('Explosions/Remote violence',5)),
  geo_precision=c(1,2,1,1,1,3,1,NA,1),
  latitude=rep(0.5,9), longitude=c(.5,2.5,.5,.5,.5,.5,181,.5,.5),
  fatalities=rep(0,9), admin1='Region',admin2='District',
  admin3=c('Alpha',NA,rep('Alpha',7)), stringsAsFactors=FALSE)
clean <- filter_events(d)
stopifnot(identical(clean$events$event_id_cnty,c('E1','E2')),
          is.na(clean$events$admin3[2]),
          nrow(clean$rejected)==7L,
          sum(clean$audit$removed)==7L,
          tail(clean$audit$remaining,1)==2L)
dup <- rbind(d,d[1,]); expect_error(filter_events(dup),'Duplicate event IDs')
bad <- d; bad$fatalities[1] <- -1
expect_error(filter_events(bad),'Invalid fatalities')
blank <- d; blank$event_id_cnty[1] <- ''
expect_error(filter_events(blank),'Missing event IDs')
rectangle <- function(x0,x1) st_polygon(list(matrix(c(x0,0,x1,0,x1,1,x0,1,x0,0),ncol=2,byrow=TRUE)))
b <- st_sf(TS_PCODE=c('A','B'),TS=c('Alpha','Beta'),
           geometry=st_sfc(rectangle(0,2),rectangle(1,3),crs=4326))
events <- clean$events[rep(1,5),]
events$event_id_cnty <- c('inside','overlap','outside','missing_name','name_conflict')
events$longitude <- c(.5,1.5,4,2.5,2.5)
events$admin3 <- c('Alpha','Alpha','Alpha',NA,'Alpha')
out <- assign_townships(events,b)
stopifnot(identical(out$assigned$event_id_cnty,c('inside','missing_name','name_conflict')),
          identical(out$assigned$TS_PCODE,c('A','B','B')),
          identical(out$unresolved$event_id_cnty,c('overlap','outside')),
          identical(out$unresolved$spatial_matches,c(2L,0L)),
          sum(out$assigned$name_check=='different',na.rm=TRUE)==1L,
          !anyDuplicated(out$assigned$event_id_cnty))
projected <- assign_townships(events,st_transform(b,3857))
stopifnot(identical(projected$assigned$TS_PCODE,out$assigned$TS_PCODE))
invalid <- b; invalid$TS_PCODE[2] <- 'A'
expect_error(assign_townships(events,invalid),'Duplicate township codes')
cat('PASS: scope, missing names, ID integrity, measure validity, spatial ambiguity, CRS and conflict checks.\n')
