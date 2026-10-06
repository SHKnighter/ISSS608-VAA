# Separate numerical work from text/layout renders without accepting stale data.
analysis_runtime <- function() c(R=as.character(getRversion()),
  vapply(c('sf','spdep','sfdep','Kendall','tmap','ggplot2'),
    function(x)as.character(utils::packageVersion(x)),character(1)))
analysis_inputs <- function() sort(c(
  'data/raw/ACLED_Data_Myanmar_Jan2021-Sep2025.csv',
  'data/raw/myanmar-townships-mimu-v9.4.geojson','_workflow/acquisition.json',
  list.files('R',pattern='[.](R|ps1)$',full.names=TRUE)))
analysis_outputs <- function() sort(c(
  list.files('data/processed',pattern='[.](rds|csv)$',full.names=TRUE),
  list.files('output/tables',pattern='[.]csv$',full.names=TRUE),
  list.files('output/figures',pattern='[.]png$',full.names=TRUE)))
record_analysis_fingerprint <- function() {
  stopifnot(all(file.exists(c('data/processed/prepared.rds','data/processed/panel.rds',
    'data/processed/lmsa.rds','data/processed/ehsa.rds'))))
  saveRDS(list(inputs=tools::md5sum(analysis_inputs()),outputs=tools::md5sum(analysis_outputs()),
    runtime=analysis_runtime(),
    recorded_utc=format(Sys.time(),tz='UTC',usetz=TRUE)),
    '_workflow/analysis-fingerprint.rds')
}
verify_analysis_fingerprint <- function() {
  if (!file.exists('_workflow/analysis-fingerprint.rds')) stop('No verified analysis cache. Run a normal render.')
  m <- readRDS('_workflow/analysis-fingerprint.rds')
  if (!identical(analysis_runtime(),m$runtime))
    stop('R or analysis package versions changed. Review the environment before reusing cached results.')
  if (!identical(tools::md5sum(analysis_inputs()),m$inputs) ||
      !identical(tools::md5sum(analysis_outputs()),m$outputs))
    stop('Analysis inputs or outputs changed. Rerun affected stages and validate before recording a new fingerprint.')
  invisible(TRUE)
}
