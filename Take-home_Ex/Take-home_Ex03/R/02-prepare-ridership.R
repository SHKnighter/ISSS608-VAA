# Explicitly fails before producing model inputs when real observations are missing.
source('R/data-core.R')
source('R/cache-guard.R')
months <- c('202608','202609')
required <- c(paste0('data/raw/origin_destination_train_',months,'.zip'),
              paste0('data/raw/transport_node_train_',months,'.zip'))
missing <- required[!file.exists(required)]
if (length(missing)) stop('Real ridership inputs required: ',paste(missing,collapse=', '),
 '. Apply for DataMall access; run python R/acquire-ridership.py --download. No calibration was run.')
if (!file.exists('data/processed/public-prepared.rds')) stop('Run R/01-prepare-public.R first')
p <- readRDS('data/processed/public-prepared.rds')
verify_prepared_ridership(p)
expected <- p$stations$station_id[p$stations$available_existing]
read_zip_csv <- function(path) {
  members <- unzip(path,list=TRUE)$Name
  csv <- members[grepl('\\.csv$',members,ignore.case=TRUE)]
  if (length(csv)!=1) stop('Expected exactly one CSV in ',path)
  con <- unz(path,csv,open='rb'); on.exit(close(con))
  x <- readr::read_csv(con,col_types=readr::cols(.default='c'),progress=FALSE,show_col_types=FALSE)
  if (nrow(readr::problems(x))) stop('CSV parse errors in ',path)
  as.data.frame(x)
}
observed <- list(); audit <- list(); reconciliations <- list()
for (m in months) {
  label <- paste0(substr(m,1,4),'-',substr(m,5,6))
  raw <- read_zip_csv(paste0('data/raw/origin_destination_train_',m,'.zip'))
  entries <- aggregate_am_boardings(raw,label)
  pv_path <- paste0('data/raw/transport_node_train_',m,'.zip')
  crosscheck <- 'not supplied'
  if (file.exists(pv_path)) {
    pv <- read_zip_csv(pv_path)
    require_columns(pv,c('PT_CODE','TOTAL_TAP_IN_VOLUME'))
    pv$ORIGIN_PT_CODE <- pv$PT_CODE; pv$DESTINATION_PT_CODE <- 'ALL'
    pv$TOTAL_TRIPS <- pv$TOTAL_TAP_IN_VOLUME
    independent <- aggregate_am_boardings(pv,label)
    # Only explicit zero observations can fill stations absent from the OD table.
    zeros <- independent[independent$observed_boardings==0 & !independent$station_code %in% entries$station_code,]
    entries <- rbind(entries,zeros)
    values <- align_boardings(independent,p$crosswalk,expected)
    od_values <- align_boardings(entries,p$crosswalk,expected)
    # The target is tap-in entries: PV measures it directly. OD trip origin sums
    # differ slightly in real monthly data; retain the discrepancy, do not force
    # equality or assume an undocumented suppression mechanism.
    reconciliations[[label]] <- data.frame(month=label,station_id=expected,
      pv_tap_ins=unname(values),od_origin_trips=unname(od_values),
      od_minus_pv=unname(od_values-values),
      relative_difference=ifelse(values>0,unname((od_values-values)/values),NA_real_))
    crosscheck <- 'PV controls entry target; OD discrepancy explicitly retained'
  } else stop('Direct PV tap-in observations required for ',label)
  observed[[label]] <- values
  audit[[label]] <- data.frame(month=label,raw_od_rows=nrow(raw),observed_physical_stations=length(values),
   weekday_0600_0959_monthly_entries=sum(values),od_origin_trips=sum(od_values),
   od_minus_pv=sum(od_values-values),od_relative_difference=sum(od_values-values)/sum(values),pv_check=crosscheck)
}
# Both months have succeeded before any prepared observation output is published.
for (label in names(observed)) {
  values <- observed[[label]]
  readr::write_csv(data.frame(station_id=names(values),observed_boardings=unname(values),month=label),
   paste0('output/tables/observed-',gsub('-','',label,fixed=TRUE),'.csv'))
}
readr::write_csv(do.call(rbind,audit),'output/tables/ridership-audit.csv')
readr::write_csv(do.call(rbind,reconciliations),'output/tables/od-pv-reconciliation.csv')
sep <- observed[['2026-09']]
origins <- sf::st_drop_geometry(p$origins[c('origin_id','population','population_share')])
origins$market_potential <- sum(sep)*origins$population_share
readr::write_csv(origins,'output/tables/origins.csv')
dest <- sf::st_drop_geometry(p$stations[p$stations$available_existing,])
dest$observed_boardings <- unname(sep[dest$station_id])
readr::write_csv(dest,'output/tables/destinations.csv')
for (scenario in c('existing','both')) {
  selected <- which(p$stations[[paste0('available_',scenario)]])
  d <- p$distance_m[,selected,drop=FALSE]
  si <- data.frame(origin_id=rep(rownames(d),times=ncol(d)),station_id=rep(colnames(d),each=nrow(d)),
   distance_m=as.vector(d),attraction=rep(p$stations[[paste0('attraction_',scenario)]][selected],each=nrow(d)))
  stopifnot(!anyDuplicated(si[c('origin_id','station_id')]))
  readr::write_csv(si,paste0('output/tables/si-',if(scenario=='both') 'expanded' else 'existing','.csv'))
}
attr(observed,'input_fingerprint') <- fingerprint_files(ridership_dependency_paths())
saveRDS(observed,'data/processed/ridership-prepared.rds')
cat('PASS: real monthly observations, reference coverage and model tables prepared.\n')
