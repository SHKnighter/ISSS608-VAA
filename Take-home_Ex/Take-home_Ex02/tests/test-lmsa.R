# Run from the Exercise 2 directory. Fixtures catch zero loss, key drift,
# wrong event-type sums, fabricated neighbours, and incorrect significance tails.
check <- function(ok, label) {
  if (!isTRUE(ok)) stop('FAIL: ', label, call.=FALSE)
  cat('PASS:', label, '\n')
}
check(file.exists('R/lmsa-helpers.R'), 'panel/LMSA helpers exist')
source('R/lmsa-helpers.R')
square <- function(x, y) sf::st_polygon(list(rbind(c(x,y), c(x+1,y),
  c(x+1,y+1), c(x,y+1), c(x,y))))
geometry <- sf::st_sf(TS_PCODE=c('B','A','C','D','E','F'),
  geometry=sf::st_sfc(square(1,0),square(0,0),square(2,0),square(0,1),
    square(1,1),square(10,10), crs=3857))
events <- data.frame(TS_PCODE=c('B','A','B','E'),
  month=as.Date(c('2021-01-01','2021-01-01','2021-01-01','2021-03-01')),
  event_type=c('Battles','Explosions/Remote violence','Violence against civilians','Battles'),
  fatalities=c(2,3,4,0),geo_precision=c(1L,2L,1L,1L))
panel <- create_panel(events,geometry,as.Date('2021-01-01'),as.Date('2021-03-01'))
d <- panel$data
check(nrow(d)==18L && !anyDuplicated(d[c('TS_PCODE','month')]), 'complete unique township-month keys')
check(identical(panel$geometry$TS_PCODE,c('A','B','C','D','E','F')) &&
  identical(d$TS_PCODE,rep(c('A','B','C','D','E','F'),3)), 'geometry and panel use the same ordered keys')
check(sum(d$event_count)==4 && sum(d$fatalities)==9 &&
  sum(d$battles)==2 && sum(d$explosions_remote)==1 && sum(d$civilian_violence)==1,
  'event types and fatalities reconcile to source')
check(all(d$event_count[d$month==as.Date('2021-02-01')]==0) &&
  all(d$event_count[d$TS_PCODE=='F']==0), 'missing months and empty townships are zero filled')
check(!inherits(d,'sf') && all(d$event_count==d$battles+d$explosions_remote+d$civilian_violence),
  'plain panel contains additive nonnegative counts')
weights <- make_lmsa_weights(panel$geometry)
check(identical(weights$ids,panel$geometry$TS_PCODE) &&
  identical(weights$isolates,6L), 'weights preserve IDs and retain the genuine isolate')
check(all(vapply(seq_along(weights$nb),function(i) !i %in% weights$nb[[i]],logical(1))) &&
  all(vapply(seq_along(weights$nb_star),function(i) i %in% weights$nb_star[[i]],logical(1))),
  'Moran excludes self and Gi star includes self')
check(all(abs(vapply(weights$listw$weights,sum,numeric(1))[1:5]-1)<1e-12),
  'contiguous rows use W normalisation')
values <- setNames(c(0,5,20,100,250,3),weights$ids)
result <- compute_lmsa(values,weights,nsim=99L,seed=6262026L)
check(identical(result$TS_PCODE,weights$ids), 'statistical rows retain input IDs')
check(result$moran_class[6]=='No contiguous neighbours' &&
  result$gi_class[6]=='No contiguous neighbours' &&
  is.na(result$p_ii_sim[6]) && is.na(result$p_sim[6]),
  'isolates never receive inferential labels or p values')
check(all(c('ii','gi_star','gi_raw','p_ii_sim','p_sim','p_ii_bh','p_gi_bh',
  'moran_class','gi_class','moran_class_bh','gi_class_bh') %in% names(result)),
  'output exposes actual statistics, permutation p values and BH classes')
# Compare the public output with spdep explicitly selecting the two-sided rank p.
direct_i <- spdep::localmoran_perm(values,weights$listw,nsim=99L,
  zero.policy=TRUE,alternative='two.sided',iseed=6262026L)
direct_g <- spdep::localG_perm(values,weights$listw_star,nsim=99L,
  zero.policy=TRUE,alternative='two.sided',iseed=6262026L,
  fix_i_in_Gstar_permutations=TRUE)
check(isTRUE(all.equal(result$p_ii_sim[1:5],unname(direct_i[1:5,'Pr(z != E(Ii)) Sim']))) &&
  isTRUE(all.equal(result$p_sim[1:5],unname(attr(direct_g,'internals')[1:5,'Pr(z != E(Gi)) Sim']))),
  'Moran and Gi star use two-sided rank permutation p values')
check(inherits(try(compute_lmsa(values[c(2,1,3:6)],weights,99L,6262026L),silent=TRUE),'try-error'),
  'misordered outcome IDs are rejected')
if ('--artifacts' %in% commandArgs(trailingOnly=TRUE)) {
  prepared <- readRDS('data/processed/prepared.rds')
  panel <- readRDS('data/processed/panel.rds')
  d <- panel$data
  check(nrow(d)==18810L && nrow(panel$geometry)==330L &&
    length(unique(d$month))==57L && !anyDuplicated(d[c('month','TS_PCODE')]),
    'formal panel is 330 townships by 57 months')
  check(sum(d$event_count)==nrow(prepared$events) &&
    sum(d$fatalities)==sum(prepared$events$fatalities), 'formal panel conserves retained data')
  check(all(d$event_count==d$battles+d$explosions_remote+d$civilian_violence) &&
    all(as.matrix(d[c('event_count','battles','explosions_remote','civilian_violence','fatalities')])>=0),
    'formal panel is additive and nonnegative')
  lmsa <- readRDS('data/processed/lmsa.rds')
  check(identical(lmsa$results$TS_PCODE,panel$geometry$TS_PCODE) &&
    identical(lmsa$weights$ids,panel$geometry$TS_PCODE), 'formal result and weights keys align')
  check(sum(lmsa$results$event_count)==nrow(prepared$events) &&
    sum(lmsa$results$event_count_gp1)==sum(prepared$events$geo_precision==1),
    'main and precision-one totals reconcile')
  iso <- lmsa$weights$isolates
  check(length(iso)==3L && all(lmsa$results$moran_class[iso]=='No contiguous neighbours') &&
    all(lmsa$results$gi_class[iso]=='No contiguous neighbours'), 'formal islands remain descriptive')
  check(lmsa$parameters$nsim==999L && lmsa$parameters$seed==6262026L,
    'formal output records required permutation settings')
}
cat('PASS: all panel/LMSA checks.\n')
