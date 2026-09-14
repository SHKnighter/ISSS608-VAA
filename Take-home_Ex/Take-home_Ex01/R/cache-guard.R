analysis_fingerprint <- function() {
 files <- c(list.files('data/raw',full.names=TRUE),
  c('R/cleaning.R','R/01-prepare.R','R/02-analyse.R'),
  list.files('data/processed',full.names=TRUE),
  list.files('output/figures',full.names=TRUE),list.files('output/tables',full.names=TRUE))
 tools::md5sum(sort(files))
}
record_analysis_fingerprint <- function() saveRDS(analysis_fingerprint(),'_workflow/analysis-fingerprint.rds')
verify_analysis_fingerprint <- function() {
 f <- '_workflow/analysis-fingerprint.rds'
 if(!file.exists(f)||!identical(readRDS(f),analysis_fingerprint()))
  stop('Inputs, analytical code or results changed. Render with recompute:true to rebuild verified outputs.')
}
