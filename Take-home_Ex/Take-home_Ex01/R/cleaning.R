clean_records <- function(d) {
  required <- c('latitude','longitude','acq_date','acq_time','satellite','confidence','source')
  stopifnot(all(required %in% names(d)))
  if (!'type' %in% names(d)) d$type <- NA_integer_
  audit <- data.frame(step=character(),before=integer(),excluded=integer(),retained=integer())
  keep <- function(ok,label) {
    ok[is.na(ok)] <- FALSE
    audit <<- rbind(audit,data.frame(step=label,before=nrow(d),excluded=sum(!ok),retained=sum(ok)))
    d <<- d[ok,,drop=FALSE]
  }
  d$acq_date <- as.Date(d$acq_date,format='%Y-%m-%d')
  tm <- suppressWarnings(as.integer(d$acq_time))
  d$acq_time <- sprintf('%04d',tm)
  keep(is.finite(d$latitude)&abs(d$latitude)<=90 & is.finite(d$longitude)&abs(d$longitude)<=180,'Valid coordinates')
  tm <- suppressWarnings(as.integer(d$acq_time))
  keep(!is.na(d$acq_date)&tm>=0&tm<=2359&tm%%100<60,'Valid UTC date and time')
  keep(d$acq_date>=as.Date('2026-01-01')&d$acq_date<=as.Date('2026-08-31'),'Study dates')
  keep(d$satellite=='SNPP','S-NPP satellite')
  d <- d[order(match(d$source,c('archive','nrt'))),,drop=FALSE]
  key <- paste(d$latitude,d$longitude,d$acq_date,d$acq_time,d$satellite,sep='|')
  keep(!duplicated(key),'Duplicate observation key (archive first)')
  keep(d$confidence %in% c('n','h'),'Nominal or high confidence')
  list(data=d,audit=audit)
}
