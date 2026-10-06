# Panel and local spatial inference helpers. All statistical inputs are PCODE keyed.
create_panel <- function(events, townships, start=as.Date('2021-01-01'),
                         end=as.Date('2025-09-01')) {
  stopifnot(inherits(townships,'sf'), !anyDuplicated(townships$TS_PCODE),
    all(events$TS_PCODE %in% townships$TS_PCODE), inherits(events$month,'Date'),
    all(events$event_type %in% c('Battles','Explosions/Remote violence','Violence against civilians')),
    all(is.finite(events$fatalities) & events$fatalities>=0))
  geometry <- townships[order(townships$TS_PCODE),]
  rownames(geometry) <- NULL
  months <- seq(start,end,by='month')
  stopifnot(all(events$month %in% months))
  frame <- expand.grid(TS_PCODE=geometry$TS_PCODE, month=months,
                       KEEP.OUT.ATTRS=FALSE,stringsAsFactors=FALSE)
  event_counts <- data.frame(TS_PCODE=events$TS_PCODE, month=events$month,
    event_count=1L,battles=as.integer(events$event_type=='Battles'),
    explosions_remote=as.integer(events$event_type=='Explosions/Remote violence'),
    civilian_violence=as.integer(events$event_type=='Violence against civilians'),
    fatalities=events$fatalities)
  measures <- c('event_count','battles','explosions_remote','civilian_violence','fatalities')
  if (nrow(event_counts)) {
    totals <- stats::aggregate(event_counts[measures],event_counts[c('TS_PCODE','month')],sum)
    frame <- merge(frame,totals,by=c('TS_PCODE','month'),all.x=TRUE,sort=FALSE)
  } else {
    for (nm in measures) frame[[nm]] <- 0
  }
  for (nm in measures) frame[[nm]][is.na(frame[[nm]])] <- 0
  frame <- frame[order(frame$month,frame$TS_PCODE),c('TS_PCODE','month',measures)]
  rownames(frame) <- NULL
  stopifnot(nrow(frame)==nrow(geometry)*length(months),
    !anyDuplicated(frame[c('TS_PCODE','month')]),sum(frame$event_count)==nrow(events),
    sum(frame$fatalities)==sum(events$fatalities),
    all(frame$event_count==frame$battles+frame$explosions_remote+frame$civilian_violence))
  list(data=frame,geometry=geometry)
}

make_lmsa_weights <- function(geometry) {
  stopifnot(inherits(geometry,'sf'), !anyDuplicated(geometry$TS_PCODE),
    identical(geometry$TS_PCODE,sort(geometry$TS_PCODE)))
  old_s2 <- sf::sf_use_s2()
  on.exit(suppressMessages(sf::sf_use_s2(old_s2)),add=TRUE)
  suppressMessages(sf::sf_use_s2(TRUE))
  # poly2nb's warnings about the documented islands/components are informative.
  nb <- spdep::poly2nb(geometry,queen=TRUE,row.names=geometry$TS_PCODE)
  nb_star <- spdep::include.self(nb)
  listw <- spdep::nb2listw(nb,style='W',zero.policy=TRUE)
  listw_star <- spdep::nb2listw(nb_star,style='W',zero.policy=TRUE)
  list(ids=geometry$TS_PCODE,nb=nb,nb_star=nb_star,listw=listw,
    listw_star=listw_star,isolates=which(spdep::card(nb)==0L))
}

compute_lmsa <- function(values, weights, nsim=999L, seed=6262026L, alpha=0.05) {
  stopifnot(is.numeric(values),identical(names(values),weights$ids),
    all(is.finite(values)),length(unique(values))>1L,
    identical(attr(weights$nb,'region.id'),weights$ids))
  # NULL selects spdep's serial path (one CPU), including on Windows.
  old_cores <- spdep::set.coresOption(NULL)
  on.exit(spdep::set.coresOption(old_cores),add=TRUE)
  set.seed(seed)
  moran <- spdep::localmoran_perm(values,weights$listw,nsim=nsim,
    zero.policy=TRUE,spChk=TRUE,alternative='two.sided',iseed=seed)
  set.seed(seed)
  gi <- spdep::localG_perm(values,weights$listw_star,nsim=nsim,
    zero.policy=TRUE,spChk=TRUE,alternative='two.sided',iseed=seed,
    fix_i_in_Gstar_permutations=TRUE)
  gi_details <- attr(gi,'internals')
  stopifnot(identical(rownames(moran),weights$ids),isTRUE(attr(gi,'gstari')),
    'Pr(z != E(Ii)) Sim' %in% colnames(moran),
    'Pr(z != E(Gi)) Sim' %in% colnames(gi_details))
  centered <- unname(values-mean(values))
  lag_centered <- unname(spdep::lag.listw(weights$listw,values-mean(values),zero.policy=TRUE))
  quadrant <- ifelse(centered>0,ifelse(lag_centered>0,'HH','HL'),
                                  ifelse(lag_centered>0,'LH','LL'))
  out <- data.frame(TS_PCODE=weights$ids,neighbor_count=spdep::card(weights$nb),
    centered_x=centered,lag_centered_x=lag_centered,quadrant=quadrant,
    ii=unname(moran[,'Ii']),z_ii=unname(moran[,'Z.Ii']),
    p_ii_normal=unname(moran[,'Pr(z != E(Ii))']),
    p_ii_sim=unname(moran[,'Pr(z != E(Ii)) Sim']),
    p_ii_folded=unname(moran[,'Pr(folded) Sim']),
    gi_star=as.numeric(gi),gi_raw=unname(gi_details[,'Gi']),
    gi_z_sim=unname(gi_details[,'StdDev.Gi']),
    p_gi_normal=unname(gi_details[,'Pr(z != E(Gi))']),
    p_sim=unname(gi_details[,'Pr(z != E(Gi)) Sim']),
    p_gi_folded=unname(gi_details[,'Pr(folded) Sim']))
  # A self-only Gi* does not supply a neighbouring comparison. Keep islands
  # in the descriptive population, but remove their inference from both tests.
  statistic_fields <- c('ii','z_ii','p_ii_normal','p_ii_sim','p_ii_folded',
    'gi_star','gi_raw','gi_z_sim','p_gi_normal','p_sim','p_gi_folded')
  out[weights$isolates,statistic_fields] <- NA_real_
  out$quadrant[weights$isolates] <- NA_character_
  out$p_ii_bh <- stats::p.adjust(out$p_ii_sim,method='BH')
  out$p_gi_bh <- stats::p.adjust(out$p_sim,method='BH')
  moran_class <- function(p) {
    ans <- rep('Not significant',nrow(out))
    valid <- is.finite(p) & p<alpha & centered!=0 & lag_centered!=0
    ans[valid] <- quadrant[valid]
    ans[weights$isolates] <- 'No contiguous neighbours'
    ans
  }
  gi_class <- function(p) {
    ans <- rep('Not significant',nrow(out))
    valid <- is.finite(p) & p<alpha & is.finite(out$gi_star) & out$gi_star!=0
    ans[valid] <- ifelse(out$gi_star[valid]>0,'Hotspot','Coldspot')
    ans[weights$isolates] <- 'No contiguous neighbours'
    ans
  }
  out$moran_class <- moran_class(out$p_ii_sim)
  out$moran_class_bh <- moran_class(out$p_ii_bh)
  out$gi_class <- gi_class(out$p_sim)
  out$gi_class_bh <- gi_class(out$p_gi_bh)
  out
}
