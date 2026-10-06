# Run from the Exercise 2 directory: Rscript R/03-ehsa.R
# Reuses a matching raw simulation cache. --recompute explicitly invalidates it.
# No installation, download, or publication occurs here.
source('R/ehsa-helpers.R',local=TRUE)
needed <- c('sf','spdep','sfdep','Kendall','readr')
stopifnot(all(vapply(needed,requireNamespace,logical(1),quietly=TRUE)))
if (as.character(utils::packageVersion('sfdep'))!='0.2.5')
  stop('This audited implementation is pinned to installed sfdep 0.2.5; review internals before changing version')
for (p in c('data/processed','output/tables','_workflow'))
  dir.create(p,recursive=TRUE,showWarnings=FALSE)
log_connection <- file('_workflow/ehsa.log',open='at')
sink(log_connection,split=TRUE)
stamp <- function(text) {
  cat(format(Sys.time(),tz='UTC',usetz=TRUE),'|',text,'\n'); flush.console()
}
stamp(paste('START EHSA; PID',Sys.getpid()))
panel_path <- 'data/processed/panel.rds'
if (!file.exists(panel_path)) stop('panel.rds is missing; run R/02-panel-lmsa.R first')
panel <- readRDS(panel_path)
geo <- panel$geometry[order(panel$geometry$TS_PCODE),]
rownames(geo) <- NULL
dat <- as.data.frame(panel$data)
dat <- dat[order(dat$month,dat$TS_PCODE),]
rownames(dat) <- NULL
ids <- as.character(geo$TS_PCODE)
months <- seq(as.Date('2021-01-01'),as.Date('2025-09-01'),by='month')
expected <- data.frame(TS_PCODE=rep(ids,length(months)),
                       month=rep(months,each=length(ids)))
stopifnot(nrow(geo)==330L,nrow(dat)==18810L,length(months)==57L,
  !anyDuplicated(ids),identical(as.character(dat$TS_PCODE),expected$TS_PCODE),
  identical(dat$month,expected$month),all(is.finite(dat$event_count)),
  all(dat$event_count>=0),all(dat$event_count==floor(dat$event_count)))
nb <- sfdep::st_contiguity(sf::st_geometry(geo),queen=TRUE)
isolates <- ids[spdep::card(nb)==0L]
nb_self <- sfdep::include_self(nb)
wt <- sfdep::st_weights(nb_self,style='W',allow_zero=TRUE)
stopifnot(all(abs(vapply(wt,sum,numeric(1))-1)<1e-12),
  all(vapply(seq_along(ids),function(i) i %in% nb_self[[i]],logical(1))))
parameters <- list(outcome='event_count',months=57L,locations=330L,
  start=months[1],end=tail(months,1),queen=TRUE,weight_style='W',include_self=TRUE,
  k=1L,nsim=999L,seed=6262027L,threshold=.05,
  monthly_p_convention='sfdep p_sim=min(one-tail permutation ranks); not doubled; <=0.05',
  trend_p_convention='Kendall::MannKendall sl; strict p<0.05; no multiplicity adjustment',
  permutation_pool='sfdep conditional neighbour permutation over all township-month indices',
  isolates=isolates,sfdep_version=as.character(utils::packageVersion('sfdep')),
  method='sfdep 0.2.5 Gi* with local sign-aware Esri-inspired classification; no ArcGIS FDR equivalence')
simulation_key <- list(panel_md5=unname(tools::md5sum(panel_path)),
  sfdep=parameters$sfdep_version,spdep=as.character(utils::packageVersion('spdep')),
  sf=as.character(utils::packageVersion('sf')),R=as.character(getRversion()),
  outcome='event_count',queen=TRUE,weight_style='W',include_self=TRUE,
  nsim=parameters$nsim,seed=parameters$seed,k=parameters$k)
out_path <- 'data/processed/ehsa.rds'
cached <- if (file.exists(out_path)) readRDS(out_path) else NULL
can_reuse <- !('--recompute' %in% commandArgs(trailingOnly=TRUE)) &&
  !is.null(cached) && identical(cached$manifest$simulation_key,simulation_key) &&
  is.data.frame(cached$monthly_gi) && nrow(cached$monthly_gi)==nrow(dat)
started <- Sys.time()
if (can_reuse) {
  stamp('Matching raw Gi* simulation cache found; no permutation rerun')
  monthly_gi <- cached$monthly_gi[,c('TS_PCODE','month','gi_star','p_sim')]
  simulation_elapsed <- cached$manifest$simulation_elapsed_seconds
} else {
  stamp(paste('Calculating',parameters$nsim,'permutations for',nrow(dat),
    'bins. This call is synchronous; do not start a duplicate R process.'))
  # These are the exact unchanged computational functions called by
  # emerging_hotspot_analysis. Separating calculation from classification avoids
  # losing all permutations if the package classifier fails on a degenerate row.
  nbt <- sfdep:::spt_nb(nb_self,length(months),length(ids),k=parameters$k)
  wtt <- sfdep:::spt_wt(wt,nbt,length(months),length(ids),k=parameters$k)
  # k=1 means first month current only, then current plus previous month.
  stopifnot(all(vapply(nbt[seq_along(ids)],max,numeric(1))<=length(ids)),
    all(vapply(seq_along(ids),function(i)
      all(sort(nbt[[i+length(ids)]])==sort(c(nb_self[[i]],nb_self[[i]]+length(ids)))),logical(1))))
  set.seed(parameters$seed) # sfdep0.2.5 does not forward ...$iseed.
  gi <- sfdep:::local_g_spt(dat$event_count,dat$month,nbt,wtt,
    n_locs=length(ids),nsim=parameters$nsim)
  monthly_gi <- cbind(dat[,c('TS_PCODE','month')],gi)
  simulation_elapsed <- as.numeric(difftime(Sys.time(),started,units='secs'))
  manifest <- list(simulation_key=simulation_key,simulation_elapsed_seconds=simulation_elapsed,
    calculation_completed_utc=format(Sys.time(),tz='UTC',usetz=TRUE))
  # Checkpoint BEFORE any classification. Re-running this script reuses the
  # untouched original Gi* and p_sim rather than paying for another 999 draws.
  saveRDS(list(monthly_gi=monthly_gi,parameters=parameters,manifest=manifest,
    complete=FALSE),out_path,version=3)
  stamp(paste('Raw Gi* checkpoint saved;',round(simulation_elapsed,1),'seconds'))
}
stopifnot(identical(as.character(monthly_gi$TS_PCODE),expected$TS_PCODE),
  identical(monthly_gi$month,expected$month))
raw_results <- raw_sfdep_ehsa(monthly_gi,ids,threshold=parameters$threshold)
results <- summarise_ehsa_monthly(monthly_gi,ids,isolates=isolates,
  threshold=parameters$threshold)
stopifnot(identical(results$TS_PCODE,raw_results$TS_PCODE))
results$raw_class <- raw_results$classification
results$raw_tau <- as.numeric(raw_results$tau)
results$raw_p_value <- as.numeric(raw_results$sl)
results$raw_error <- raw_results$raw_error
results$raw_class_normalized <- gsub('oscilating','oscillating',results$raw_class,fixed=TRUE)
results$class_changed <- !is.na(results$classification) &
  (is.na(results$raw_class_normalized) | results$classification!=results$raw_class_normalized)
monthly_gi$isolated <- monthly_gi$TS_PCODE %in% isolates
monthly_gi$bin_class <- ifelse(!is.finite(monthly_gi$gi_star) | !is.finite(monthly_gi$p_sim),
  'not testable',ifelse(monthly_gi$p_sim<=parameters$threshold & monthly_gi$gi_star>0,
  'hot',ifelse(monthly_gi$p_sim<=parameters$threshold & monthly_gi$gi_star<0,'cold','not significant')))
monthly_gi$bin_class[monthly_gi$isolated] <- 'isolated township'
stopifnot(nrow(results)==330L,!anyDuplicated(results$TS_PCODE),
  all(!results$significant_trend[!results$trend_testable]),
  all(is.na(results$classification[results$TS_PCODE %in% isolates])),
  all(results$p_value[results$significant_trend]<parameters$threshold))
all_classes <- c('new','consecutive','intensifying','persistent','diminishing',
  'sporadic','oscillating','historical')
all_classes <- c(paste(all_classes,'hotspot'),paste(all_classes,'coldspot'),
  'no pattern detected','not testable')
display_class <- ifelse(is.na(results$classification),'not testable',results$classification)
category_counts <- data.frame(classification=all_classes,
  townships=as.integer(table(factor(display_class,levels=all_classes))),
  significant_trend=as.integer(table(factor(display_class[results$significant_trend],levels=all_classes))))
class_changes <- results[results$class_changed,c('TS_PCODE','raw_class','classification','tau','p_value')]
trend_counts <- as.data.frame(table(results$trend_direction),responseName='townships')
names(trend_counts)[1] <- 'trend_direction'
write_table <- function(x,name) readr::write_csv(x,file.path('output/tables',paste0('ehsa-',name,'.csv')))
write_table(results,'townships')
write_table(monthly_gi,'monthly-gi')
write_table(category_counts,'category-counts')
write_table(class_changes,'class-changes')
write_table(trend_counts,'trend-counts')
manifest <- list(simulation_key=simulation_key,simulation_elapsed_seconds=simulation_elapsed,
  completed_utc=format(Sys.time(),tz='UTC',usetz=TRUE),
  source_hashes=tools::md5sum(c(panel_path,'R/03-ehsa.R','R/ehsa-helpers.R','tests/test-ehsa.R')),
  versions=vapply(needed,function(p) as.character(utils::packageVersion(p)),character(1)))
audit_functions <- c('emerging_hotspot_analysis','local_g_spt','local_g_spt_impl',
  'local_g_spt_calc','cond_permute_nb','spt_nb','spt_wt','classify_hotspot','fxs')
package_source <- setNames(lapply(audit_functions,function(f)
  capture.output(print(get(f,asNamespace('sfdep'))))),audit_functions)
ehsa <- list(results=results,monthly_gi=monthly_gi,raw_results=raw_results,
  geometry=geo,parameters=parameters,manifest=manifest,
  category_counts=category_counts,trend_counts=trend_counts,class_changes=class_changes,
  package_source=package_source,complete=TRUE)
saveRDS(ehsa,out_path,version=3)
stamp(paste('COMPLETE;',nrow(results),'townships;',sum(results$significant_trend),
  'significant MK trends;',sum(results$class_changed),'corrected classes'))
print(category_counts,row.names=FALSE)
print(trend_counts,row.names=FALSE)
stamp('PASS: all 18,810 township-month keys and 330 result keys aligned')
sink(); close(log_connection)
