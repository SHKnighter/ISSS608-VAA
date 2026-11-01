# Analysis and rendering are separate from explicit acquisition.
source('R/cache-guard.R',local=TRUE)
.ex03_figures <- c('01-study-area','02-observed','03-validation','04-residuals',
 '05-new-stations','06-existing-change','07-catchment-switches','08-sensitivity')
.ex03_dependencies <- function() unique(c(ridership_dependency_paths(),
 'R/model-core.R','R/03-model-scenarios.R','R/04-figures.R','R/workflow.R',
 'data/processed/ridership-prepared.rds','output/huff-study.rds',
 list.files('output/tables',pattern='\\.csv$',full.names=TRUE),
 paste0('output/figures/',.ex03_figures,'.png')))

verify_ex03_analysis <- function() {
  required <- c('data/processed/public-prepared.rds','data/processed/ridership-prepared.rds',
    'output/huff-study.rds','_workflow/analysis-fingerprint.rds',
    paste0('output/figures/',.ex03_figures,'.png'))
  if (!all(file.exists(required))) stop('Analysis or figures missing: render with recompute:true after obtaining inputs')
  for (f in required[1:3]) verify_prepared_ridership(readRDS(f))
  previous <- readRDS('_workflow/analysis-fingerprint.rds')
  if (!identical(previous,fingerprint_files(.ex03_dependencies()))) stop('Analysis/figure dependencies changed: use recompute:true')
  invisible(TRUE)
}

ensure_ex03_analysis <- function(recompute=TRUE) {
  if (!isTRUE(recompute)) return(verify_ex03_analysis())
  exe <- file.path(R.home('bin'),if(.Platform$OS.type=='windows') 'Rscript.exe' else 'Rscript')
  if (!file.exists(exe)) stop('Rscript executable not found')
  stages <- c('01-prepare-public','02-prepare-ridership','03-model-scenarios','04-figures')
  dir.create('_workflow',showWarnings=FALSE)
  for (stage in stages) {
    script <- paste0('R/',stage,'.R'); log <- paste0('_workflow/',stage,'-render.log')
    status <- system2(exe,c('--vanilla',shQuote(script)),stdout=log,stderr=log)
    if (!identical(status,0L)) stop('Stage failed: ',stage,'\n',paste(tail(readLines(log,warn=FALSE),12),collapse='\n'))
  }
  saveRDS(fingerprint_files(.ex03_dependencies()),'_workflow/analysis-fingerprint.rds')
  verify_ex03_analysis()
}
