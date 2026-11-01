# Pure preparation helpers. No downloads, package installation or global options.
normalise_name <- function(x) gsub('[[:space:]]+', ' ', toupper(trimws(as.character(x))))

canonical_station_code <- function(x) {
  x <- gsub('/','-',normalise_name(x),fixed=TRUE)
  if (anyNA(x) || any(!nzchar(x))) stop('Missing station code')
  vapply(strsplit(x, '-', fixed=TRUE), function(parts) {
    parts <- trimws(parts)
    if (any(!nzchar(parts)) || anyDuplicated(parts)) stop('Invalid or repeated station code')
    paste(sort(parts),collapse='-')
  }, character(1), USE.NAMES=FALSE)
}

require_columns <- function(x, cols) {
  absent <- setdiff(cols,names(x))
  if (length(absent)) stop('Missing columns: ',paste(absent,collapse=', '))
}

aggregate_population <- function(x) {
  keys <- c('PA','SZ','AG','Sex','TOD','Time')
  require_columns(x,c(keys,'Pop'))
  if (anyNA(x[keys]) || anyDuplicated(x[keys])) stop('Missing or duplicate population category key')
  if (!all(as.character(x$Time)=='2025')) stop('Expected June2025 population')
  n <- suppressWarnings(as.numeric(x$Pop))
  if (any(!is.finite(n)) || any(n<0 | n!=floor(n))) stop('Invalid resident count')
  x$PA <- normalise_name(x$PA); x$SZ <- normalise_name(x$SZ); x$population <- n
  out <- aggregate(population~PA+SZ,x,sum)
  if (sum(out$population)!=sum(n)) stop('Population aggregation lost records')
  out[order(out$PA,out$SZ),]
}

aggregate_am_boardings <- function(x, month) {
  keys <- c('YEAR_MONTH','DAY_TYPE','TIME_PER_HOUR','PT_TYPE','ORIGIN_PT_CODE','DESTINATION_PT_CODE')
  require_columns(x,c(keys,'TOTAL_TRIPS'))
  if (!nrow(x) || anyNA(x[keys]) || anyDuplicated(x[keys])) stop('Empty, missing or duplicate OD key')
  if (!all(x$YEAR_MONTH==month)) stop('Unexpected year/month in source archive')
  if (!all(x$PT_TYPE=='TRAIN')) stop('Expected TRAIN records only')
  hour <- suppressWarnings(as.numeric(x$TIME_PER_HOUR))
  trips <- suppressWarnings(as.numeric(x$TOTAL_TRIPS))
  if (any(!is.finite(hour)) || any(hour<0 | hour>23 | hour!=floor(hour))) stop('Invalid hour')
  if (any(!is.finite(trips)) || any(trips<0 | trips!=floor(trips))) stop('Invalid trip count')
  if (!all(x$DAY_TYPE %in% c('WEEKDAY','WEEKENDS/HOLIDAY'))) stop('Unknown day type')
  keep <- x$DAY_TYPE=='WEEKDAY' & hour %in% 6:9
  if (!any(keep)) stop('No weekday morning observations')
  d <- data.frame(station_code=canonical_station_code(x$ORIGIN_PT_CODE[keep]),observed_boardings=trips[keep])
  out <- aggregate(observed_boardings~station_code,d,sum)
  if (sum(out$observed_boardings)!=sum(trips[keep])) stop('Morning totals do not reconcile')
  out$month <- month
  out[order(out$station_code),]
}

align_boardings <- function(y, crosswalk, expected_ids) {
  require_columns(y,c('station_code','observed_boardings'))
  require_columns(crosswalk,c('station_code','station_id'))
  if (anyDuplicated(crosswalk$station_code) || anyNA(crosswalk$station_id)) stop('Invalid crosswalk')
  ids <- vapply(strsplit(y$station_code,'-',fixed=TRUE),function(parts) {
    mapped <- crosswalk$station_id[match(parts,crosswalk$station_code)]
    if (anyNA(mapped) || length(unique(mapped))!=1L) stop('Unresolved observed station: ',paste(parts,collapse='-'))
    mapped[1]
  },character(1))
  totals <- tapply(y$observed_boardings,ids,sum)
  if (!setequal(names(totals),expected_ids)) stop('Observed/reference roster differs. Missing: ',
    paste(setdiff(expected_ids,names(totals)),collapse=','),'; additional: ',paste(setdiff(names(totals),expected_ids),collapse=','))
  stats::setNames(as.numeric(totals[expected_ids]),expected_ids)
}
