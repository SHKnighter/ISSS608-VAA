source('R/cleaning.R')
fixture <- data.frame(latitude=c(-2,-2,-2,95,-2,-2),longitude=114,
 acq_date=c('2026-08-01','2026-08-01','2026-08-02','2026-08-01','2026-08-03','bad'),
 acq_time=c('513','0513','0513','0513','0513','0513'),
 satellite='SNPP',confidence=c('n','n','n','n','l','n'),
 source=c('nrt','archive','nrt','nrt','nrt','nrt'),type=NA_integer_)
z <- clean_records(fixture)
stopifnot(nrow(z$data)==2, z$data$source[1]=='archive',
 length(unique(z$data$acq_date))==2,all(z$data$acq_time=='0513'),
 sum(z$audit$excluded)==4,all(is.na(z$data$type)))
cat('PASS: archive precedence, timestamp normalization, repeated-date retention, invalid inputs, confidence, unavailable type.\n')
