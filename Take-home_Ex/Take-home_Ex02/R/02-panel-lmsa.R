# Run from the Exercise 2 directory; the existing prepared cache is the input.
source('R/lmsa-helpers.R',local=TRUE)
needed <- c('sf','spdep','readr')
stopifnot(all(vapply(needed,requireNamespace,logical(1),quietly=TRUE)))
for (p in c('data/processed','output/tables','_workflow')) dir.create(p,recursive=TRUE,showWarnings=FALSE)
prepared <- readRDS('data/processed/prepared.rds')
panel <- create_panel(prepared$events,prepared$townships)
saveRDS(panel,'data/processed/panel.rds',version=3)
cat('PASS: saved panel.rds with',nrow(panel$data),'rows;',sum(panel$data$event_count),
    'events;',sum(panel$data$event_count==0),'zero township-months.\n')
write_table <- function(x,name) readr::write_csv(x,file.path('output/tables',paste0(name,'.csv')))
d <- panel$data
measures <- c('event_count','battles','explosions_remote','civilian_violence','fatalities')
monthly <- stats::aggregate(d[measures],d['month'],sum)
monthly$year <- as.integer(format(monthly$month,'%Y'))
monthly$calendar_month <- as.integer(format(monthly$month,'%m'))
monthly$period <- ifelse(monthly$year==2025,'2025 (January-September only)',as.character(monthly$year))
annual <- stats::aggregate(monthly[measures],monthly['year'],sum)
annual$months_observed <- as.integer(table(monthly$year)[as.character(annual$year)])
annual$period <- ifelse(annual$year==2025,'2025 (January-September only)',paste0(annual$year,' (January-December)'))
jan_sep <- monthly[monthly$calendar_month<=9,]
annual_comparable <- stats::aggregate(jan_sep[measures],jan_sep['year'],sum)
annual_comparable$period <- paste0(annual_comparable$year,' (January-September)')
annual_comparable$change_previous_percent <- c(NA,100*diff(annual_comparable$event_count)/head(annual_comparable$event_count,-1))
type_names <- c(battles='Battles',explosions_remote='Explosions/Remote violence',civilian_violence='Violence against civilians')
type_composition <- data.frame(event_type=unname(type_names),
  events=vapply(names(type_names),function(nm) sum(d[[nm]]),numeric(1)))
type_composition$share_percent <- 100*type_composition$events/sum(d$event_count)
monthly_types <- do.call(rbind,lapply(names(type_names),function(nm)
  data.frame(month=monthly$month,event_type=type_names[[nm]],events=monthly[[nm]])))
township_totals <- stats::aggregate(d[measures],d['TS_PCODE'],sum)
township_totals <- township_totals[match(panel$geometry$TS_PCODE,township_totals$TS_PCODE),]
stopifnot(identical(township_totals$TS_PCODE,panel$geometry$TS_PCODE))
descriptive_sf <- panel$geometry
for (nm in measures) descriptive_sf[[nm]] <- township_totals[[nm]]
township_rank <- sf::st_drop_geometry(descriptive_sf[c('TS_PCODE','TS','ST',measures)])
township_rank <- township_rank[order(-township_rank$event_count,township_rank$TS_PCODE),]
township_rank$rank <- seq_len(nrow(township_rank))
township_rank$share_percent <- 100*township_rank$event_count/sum(d$event_count)
township_rank$cumulative_share_percent <- cumsum(township_rank$share_percent)
panel_summary <- data.frame(measure=c('townships','months','township_month_rows','recorded_events',
  'reported_fatalities','zero_township_months','zero_townships_full_period','nonzero_townships',
  'monthly_min','monthly_max','township_median','township_mean','top_10_event_share_percent'),
  value=c(nrow(panel$geometry),length(unique(d$month)),nrow(d),sum(d$event_count),sum(d$fatalities),
    sum(d$event_count==0),sum(township_totals$event_count==0),sum(township_totals$event_count>0),
    min(monthly$event_count),max(monthly$event_count),median(township_totals$event_count),
    mean(township_totals$event_count),sum(head(township_rank$share_percent,10))))
write_table(panel_summary,'panel-summary')
write_table(d,'panel-monthly-townships')
write_table(monthly,'descriptive-monthly')
write_table(annual,'descriptive-annual-observed')
write_table(annual_comparable,'descriptive-annual-jan-sep')
write_table(type_composition,'descriptive-type-composition')
write_table(monthly_types,'descriptive-monthly-types')
write_table(township_rank,'descriptive-township-totals')
if ('--panel-only' %in% commandArgs(trailingOnly=TRUE)) quit(status=0L)

weights <- make_lmsa_weights(panel$geometry)
nsim <- 999L
seed <- 6262026L
main <- compute_lmsa(setNames(township_totals$event_count,township_totals$TS_PCODE),weights,nsim,seed)
gp1_panel <- create_panel(prepared$events[prepared$events$geo_precision==1L,],panel$geometry)
gp1_totals <- stats::aggregate(gp1_panel$data[measures],gp1_panel$data['TS_PCODE'],sum)
gp1_totals <- gp1_totals[match(weights$ids,gp1_totals$TS_PCODE),]
gp1 <- compute_lmsa(setNames(gp1_totals$event_count,gp1_totals$TS_PCODE),weights,nsim,seed)
results <- descriptive_sf
for (nm in setdiff(names(main),'TS_PCODE')) results[[nm]] <- main[[nm]]
results$event_count_gp1 <- gp1_totals$event_count
for (nm in setdiff(names(gp1),c('TS_PCODE','neighbor_count')))
  results[[paste0(nm,'_gp1')]] <- gp1[[nm]]
results$moran_agreement <- results$moran_class==results$moran_class_gp1
results$gi_agreement <- results$gi_class==results$gi_class_gp1
class_counts <- do.call(rbind,lapply(c('moran','gi'),function(method)
  do.call(rbind,lapply(c('main','BH','precision1'),function(variant) {
    field <- paste0(method,'_class',switch(variant,main='',BH='_bh',precision1='_gp1'))
    levels <- if (method=='moran') c('HH','LL','HL','LH','Not significant','No contiguous neighbours') else
      c('Hotspot','Coldspot','Not significant','No contiguous neighbours')
    data.frame(method=method,variant=variant,class=levels,
      townships=as.integer(table(factor(results[[field]],levels=levels))))
  }))))
agreement <- do.call(rbind,lapply(c('moran','gi'),function(method)
  do.call(rbind,lapply(c('all townships','with contiguous neighbours'),function(scope) {
    rows <- if (scope=='all townships') seq_len(nrow(results)) else which(results$neighbor_count>0)
    same <- results[[paste0(method,'_agreement')]][rows]
    data.frame(method=method,scope=scope,townships=length(rows),agree=sum(same),
      disagree=sum(!same),agreement_percent=100*mean(same))
  }))))
transition_table <- function(method,suffix) {
  as.data.frame(table(main=results[[paste0(method,'_class')]],
    comparison=results[[paste0(method,'_class',suffix)]]),responseName='townships')
}
write_table(sf::st_drop_geometry(results),'lmsa-township-results')
write_table(class_counts,'lmsa-class-counts')
write_table(agreement,'lmsa-sensitivity-agreement')
write_table(transition_table('moran','_gp1'),'lmsa-moran-precision1-transitions')
write_table(transition_table('gi','_gp1'),'lmsa-gi-precision1-transitions')
write_table(transition_table('moran','_bh'),'lmsa-moran-bh-transitions')
write_table(transition_table('gi','_bh'),'lmsa-gi-bh-transitions')
write_table(sf::st_drop_geometry(results[weights$isolates,c('TS_PCODE','TS','ST','event_count')]),'lmsa-isolates')
parameters <- list(nsim=nsim,seed=seed,alpha=0.05,alternative='two.sided',
  outcome='full-period raw event_count',weights='Queen contiguity, row-standardised W',
  moran_self=FALSE,gi_self=TRUE,gi_self_fixed_during_permutation=TRUE,
  moran_p_field='Pr(z != E(Ii)) Sim',gi_p_field='Pr(z != E(Gi)) Sim',
  moran_quadrants='Signs of x-global mean and W*(x-global mean)',
  permutation_sampling='spdep default: conditional draws with replacement (no_repeat_in_row=FALSE)',
  cpu_count=1L,serial=TRUE,s2=TRUE,precision_main=c(1L,2L),precision_sensitivity=1L,
  bh_family='327 non-isolate township p values, separately for Moran and Gi star',
  input_hashes=tools::md5sum(c('data/processed/prepared.rds','R/lmsa-helpers.R','R/02-panel-lmsa.R')),
  package_versions=vapply(needed,function(nm) as.character(utils::packageVersion(nm)),character(1)),
  completed_utc=format(Sys.time(),tz='UTC',usetz=TRUE))
lmsa <- list(results=results,weights=weights,parameters=parameters,
  summary=list(class_counts=class_counts,agreement=agreement),
  descriptive=list(panel_summary=panel_summary,monthly=monthly,annual=annual,
    annual_comparable=annual_comparable,type_composition=type_composition,
    monthly_types=monthly_types,township_rank=township_rank))
saveRDS(lmsa,'data/processed/lmsa.rds',version=3)
print(panel_summary,row.names=FALSE)
print(class_counts,row.names=FALSE)
print(agreement,row.names=FALSE)
cat('PASS: formal panel and LMSA saved. nsim=999; seed=6262026; serial.\n')
