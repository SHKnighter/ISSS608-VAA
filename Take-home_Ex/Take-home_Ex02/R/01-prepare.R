# Run from the Exercise 2 directory. No installation or download occurs here.
source('R/cleaning.R',local=TRUE)
needed <- c('sf','readr','dplyr','tidyr','spdep','sfdep','tmap','Kendall','knitr','digest','jsonlite')
missing <- needed[!vapply(needed,requireNamespace,logical(1),quietly=TRUE)]
if (length(missing)) stop('Missing packages: ',paste(missing,collapse=', '))
csv_path <- 'data/raw/ACLED_Data_Myanmar_Jan2021-Sep2025.csv'
boundary_path <- 'data/raw/myanmar-townships-mimu-v9.4.geojson'
inputs <- c(csv_path,boundary_path,'_workflow/acquisition.json','R/cleaning.R','R/01-prepare.R')
if (!all(file.exists(inputs))) stop('Missing inputs. See data/README.md')
acquisition <- jsonlite::fromJSON('_workflow/acquisition.json')
for (raw_path in c(csv_path,boundary_path)) {
  record <- acquisition$sources[acquisition$sources$local_file==raw_path,]
  if (nrow(record)!=1L || !identical(tolower(record$sha256),
      digest::digest(file=raw_path,algo='sha256'))) stop('Source SHA256 mismatch: ',raw_path)
}
for (p in c('data/processed','output/tables','_workflow')) dir.create(p,recursive=TRUE,showWarnings=FALSE)
events <- readr::read_csv(csv_path,show_col_types=FALSE,progress=FALSE,
  col_types=readr::cols(.default=readr::col_skip(),
    event_id_cnty='c',event_date='c',year='i',time_precision='i',
    disorder_type='c',event_type='c',sub_event_type='c',country='c',
    admin1='c',admin2='c',admin3='c',location='c',latitude='d',longitude='d',
    geo_precision='i',fatalities='d'))
if (nrow(readr::problems(events))) stop('CSV parsing problems: inspect raw source')
events <- as.data.frame(events)
townships <- sf::st_read(boundary_path,quiet=TRUE)
stopifnot('Expected the official 330-township v9.4 layer'=
  nrow(townships)==330L && 'PCode_V' %in% names(townships) &&
  all(!is.na(townships$PCode_V) & townships$PCode_V==9.4))
townships <- sf::st_transform(townships,4326)
townships <- townships[order(townships$TS_PCODE),]
rownames(townships) <- NULL
clean <- filter_events(events)
spatial <- assign_townships(clean$events,townships)
audit <- rbind(clean$audit,
  data.frame(step='unique_township_match',input=nrow(clean$events),
    removed=nrow(spatial$unresolved),remaining=nrow(spatial$assigned)))
stopifnot(nrow(events)==sum(audit$removed)+nrow(spatial$assigned),
          !anyDuplicated(spatial$assigned$event_id_cnty),
          all(spatial$assigned$TS_PCODE %in% townships$TS_PCODE))
spatial$assigned$month <- as.Date(format(spatial$assigned$event_date,'%Y-%m-01'))
write_table <- function(x,name) readr::write_csv(x,file.path('output/tables',paste0(name,'.csv')))
write_table(audit,'cleaning-audit')
write_table(as.data.frame(table(events$country),responseName='events'),'raw-country-counts')
write_table(as.data.frame(table(events$event_type),responseName='events'),'raw-event-types')
write_table(as.data.frame(table(events$geo_precision),responseName='events'),'raw-geo-precision')
write_table(as.data.frame(table(spatial$assigned$geo_precision),responseName='events'),'retained-geo-precision')
write_table(as.data.frame(table(spatial$assigned$name_check),responseName='events'),'township-name-checks')
write_table(as.data.frame(table(spatial$unresolved$exclusion_reason),responseName='events'),'spatial-exclusions')
quality <- data.frame(measure=c('raw_records','raw_unique_ids','raw_missing_admin3',
  'main_scope_before_precision','after_precision_and_coordinates','retained_unique_township',
  'retained_missing_admin3','unmatched_points','multiple_matches','township_name_difference',
  'admin1_name_difference','admin2_name_difference','boundary_townships','observed_months'),
  value=c(nrow(events),length(unique(events$event_id_cnty)),sum(is.na(events$admin3)|events$admin3==''),
    audit$remaining[audit$step=='three_violence_types'],nrow(clean$events),nrow(spatial$assigned),
    sum(spatial$assigned$name_check=='missing'),sum(spatial$unresolved$spatial_matches==0),
    sum(spatial$unresolved$spatial_matches>1),sum(spatial$assigned$name_check=='different'),
    sum(spatial$assigned$admin1_check=='different'),sum(spatial$assigned$admin2_check=='different'),
    nrow(townships),length(unique(spatial$assigned$month))))
write_table(quality,'quality-summary')
readr::write_csv(clean$rejected,'data/processed/excluded-before-spatial.csv')
readr::write_csv(spatial$unresolved,'data/processed/unresolved-spatial.csv')
conflict <- spatial$assigned$name_check=='different' |
  spatial$assigned$admin1_check=='different' | spatial$assigned$admin2_check=='different'
readr::write_csv(spatial$assigned[conflict,],'data/processed/name-conflicts.csv')
readr::write_csv(spatial$assigned,'data/processed/assigned-events.csv')
prepared <- list(events=spatial$assigned,townships=townships,audit=audit,
  quality=quality,unresolved=spatial$unresolved,
  scope=list(event_types=c('Battles','Explosions/Remote violence','Violence against civilians'),
    country='Myanmar',start=as.Date('2021-01-01'),end=as.Date('2025-09-30'),
    geo_precision=c(1L,2L),boundary_version='MIMU v9.4',assignment='unique closed-polygon intersection'))
saveRDS(prepared,'data/processed/prepared.rds',version=3)
outputs <- c('data/processed/prepared.rds','data/processed/assigned-events.csv',
             paste0('output/tables/',c('cleaning-audit','raw-country-counts',
               'raw-event-types','raw-geo-precision','retained-geo-precision',
               'township-name-checks','spatial-exclusions','quality-summary'),'.csv'))
saveRDS(list(input_hashes=tools::md5sum(inputs),output_hashes=tools::md5sum(outputs),
             completed_utc=format(Sys.time(),tz='UTC',usetz=TRUE)),
        '_workflow/prepare-manifest.rds')
capture.output({
  cat('Quarto:',system2('quarto','--version',stdout=TRUE),'\n')
  print(data.frame(package=needed,version=vapply(needed,function(x) as.character(utils::packageVersion(x)),character(1))))
  sessionInfo()
},file='_workflow/environment.txt')
print(audit,row.names=FALSE)
print(quality,row.names=FALSE)
cat('PASS: prepared data saved; all input records reconciled.\n')
