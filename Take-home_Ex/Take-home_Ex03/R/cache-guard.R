# Bind prepared artifacts to the raw inputs and preparation code actually used.
fingerprint_files <- function(paths) {
  if (!length(paths) || anyNA(paths) || anyDuplicated(paths)) stop('Invalid dependency paths')
  stats::setNames(vapply(paths,function(f) {
    if (file.exists(f)) digest::digest(file=f,algo='sha256') else 'MISSING'
  },character(1)),paths)
}
verify_prepared_ridership <- function(cache) {
  previous <- attr(cache,'input_fingerprint')
  if (is.null(previous) || is.null(names(previous)) || !length(previous)) stop('Unversioned cache: rerun preparation')
  if (!identical(previous,fingerprint_files(names(previous)))) stop('Stale cache: raw inputs or preparation changed; rerun preparation')
  invisible(TRUE)
}
public_dependency_paths <- function() c(paste0('data/raw/',c('population-2025.csv',
 'subzones-mp2019.geojson','operational-stations.csv','future-stations.csv',
 'train-stations-sep2026.zip','bus-stops-sep2026.zip')),
 'R/data-core.R','R/cache-guard.R','R/01-prepare-public.R')
ridership_dependency_paths <- function() unique(c(public_dependency_paths(),
 paste0('data/raw/origin_destination_train_',c('202608','202609'),'.zip'),
 paste0('data/raw/transport_node_train_',c('202608','202609'),'.zip'),
 'data/processed/public-prepared.rds','R/02-prepare-ridership.R'))
