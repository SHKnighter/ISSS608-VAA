# Run from the Exercise 2 directory. These fixtures catch sign, final-bin,
# invalid-series, and key-alignment errors independently of the real data.
if (file.exists('R/ehsa-helpers.R')) {
  source('R/ehsa-helpers.R', local=TRUE)
} else {
  # RED baseline: exercise the actual installed classifier before the repair.
  classify_ehsa_series <- function(gi_star, p_sim, threshold=.05) {
    z <- sfdep:::classify_hotspot(data.frame(gi_star, p_sim), threshold)
    data.frame(classification=z$classification, tau=z$tau, p_value=z$sl)
  }
}
expect_class <- function(gs, p, want, label) {
  got <- classify_ehsa_series(gs, p)$classification
  if (!identical(got, want)) stop(label, ': expected ', want, '; got ', got)
}
sig <- rep(.01, 20)
# Regression: relaxing negative Gi* remains cold, never intensifying hot.
expect_class(seq(-20,-1), sig, 'diminishing coldspot', 'cold sign regression')
expect_class(seq(1,20), sig, 'intensifying hotspot', 'increasing hot')
expect_class(seq(20,1), sig, 'diminishing hotspot', 'decreasing hot')
expect_class(seq(-1,-20), sig, 'intensifying coldspot', 'increasing cold intensity')
expect_class(rep(c(2,3),10), sig, 'persistent hotspot', 'hot without trend')
expect_class(rep(c(-2,-3),10), sig, 'persistent coldspot', 'cold without trend')

for (sign in c(1,-1)) {
  suffix <- if (sign==1) 'hotspot' else 'coldspot'
  gs <- sign * seq(1,2,length.out=20)
  expect_class(gs,c(rep(1,19),.01),paste('new',suffix),'new final cluster')
  expect_class(gs,c(rep(1,17),rep(.01,3)),paste('consecutive',suffix),
               'single final run')
  p <- rep(1,20); p[c(2,8,20)] <- .01
  expect_class(gs,p,paste('sporadic',suffix),'separated same-sign clusters')
  mixed <- gs; mixed[1] <- -sign * 3; p[1] <- .01
  expect_class(mixed,p,paste('oscillating',suffix),'mixed-sign history')
  expect_class(gs,c(rep(.01,19),1),paste('historical',suffix),
               'historical even when final score keeps same sign')
  expect_class(gs,c(.01,rep(1,19)),'no pattern detected',
               'sporadic requires final significant bin')
  # A prior opposite-sign bin must not erase the documented new category.
  p <- c(.01,rep(1,18),.01); mixed <- gs; mixed[1] <- -sign * 3
  expect_class(mixed,p,paste('new',suffix),'new is sign-specific')
}
expect_class(seq(1,20),rep(1,20),'no pattern detected','no significant bins')
expect_class(seq(1,20),rep(.05,20),'intensifying hotspot','inclusive monthly threshold')
expect_class(seq(1,20),rep(.05001,20),'no pattern detected','monthly threshold boundary')
expect_class(c(1:18,.5,-.5),c(rep(.01,18),1,.01),'historical hotspot',
             'dominant historical pattern precedes an opposite final bin')
expect_class(-c(1:18,.5,-.5),c(rep(.01,18),1,.01),'historical coldspot',
             'historical/final-sign precedence must be symmetric')

for (gs in list(rep(0,20),rep(3,20),c(1:19,NA_real_),c(1:19,Inf))) {
  z <- classify_ehsa_series(gs,sig)
  stopifnot('constant/nonfinite series must not produce a trend or category'=
    !z$trend_testable && is.na(z$tau) && is.na(z$p_value) && is.na(z$classification))
}
z <- classify_ehsa_series(seq(1,20),sig,isolated=TRUE)
stopifnot('isolates have no inferred label'=is.na(z$classification) && !z$trend_testable)

# Reordering either the geometry or the input must not exchange township results.
tiny <- data.frame(TS_PCODE=rep(c('B','A'),each=20),
  month=rep(seq(as.Date('2021-01-01'),by='month',length.out=20),2),
  gi_star=c(seq(-20,-1),seq(1,20)),p_sim=.01)
set.seed(23)
out <- summarise_ehsa_monthly(tiny[sample(nrow(tiny)),],c('A','B'))
stopifnot(identical(out$TS_PCODE,c('A','B')),
  identical(out$classification,c('intensifying hotspot','diminishing coldspot')))
out_rev <- summarise_ehsa_monthly(tiny,c('B','A'))
stopifnot(identical(out_rev$classification,c('diminishing coldspot','intensifying hotspot')))
bad <- try(summarise_ehsa_monthly(rbind(tiny,tiny[1,]),c('A','B')),silent=TRUE)
stopifnot('duplicate township-month keys must stop'=inherits(bad,'try-error'))

# Characterization: our separate calculation/classification path must return
# the unchanged sfdep observations, permutation p, and raw labels. Twelve cells
# avoid zero variance from a neighbourhood spanning the entire synthetic map.
fixture_geo <- sf::st_sf(TS_PCODE=sprintf('T%02d',1:12),geometry=sf::st_make_grid(
  sf::st_as_sfc(sf::st_bbox(c(xmin=0,ymin=0,xmax=12,ymax=1),crs=3857)),n=c(12,1)))
fixture <- expand.grid(TS_PCODE=fixture_geo$TS_PCODE,month=1:6,stringsAsFactors=FALSE)
fixture$event_count <- (seq_len(nrow(fixture))^2 %% 23) + rep(1:6,each=12)
cube <- sfdep::spacetime(fixture,fixture_geo,.loc_col='TS_PCODE',.time_col='month')
set.seed(701)
original <- sfdep::emerging_hotspot_analysis(cube,'event_count',k=1,include_gi=TRUE,
  nsim=9,threshold=.05)
nb <- sfdep::include_self(sfdep::st_contiguity(sf::st_geometry(fixture_geo)))
wt <- sfdep::st_weights(nb,style='W')
nbt <- sfdep:::spt_nb(nb,6,12,1)
wtt <- sfdep:::spt_wt(wt,nbt,6,12,1)
stopifnot('first month excludes future time'=all(unlist(nbt[1:12])<=12),
  'second month contains only current and previous neighbours'=
    setequal(nbt[[13]],c(1,2,13,14)))
set.seed(701)
same_gi <- sfdep:::local_g_spt(fixture$event_count,fixture$month,nbt,wtt,12,nsim=9)
stopifnot('split computation preserves exact sfdep Gi* and p'=
  identical(same_gi,attr(original,'gi_star')))
same_raw <- raw_sfdep_ehsa(cbind(fixture[,c('TS_PCODE','month')],same_gi),fixture_geo$TS_PCODE)
stopifnot('raw classes retain installed sfdep behavior'=
  identical(same_raw$classification,original$classification),
  identical(same_raw$tau,original$tau))
cat('PASS: EHSA category/sign/final-bin/constant/isolate/key tests and original sfdep parity.\n')


# Optional integration checks run only after the formal checkpoint is complete.
if (file.exists('data/processed/ehsa.rds')) {
  formal <- readRDS('data/processed/ehsa.rds')
  if (isTRUE(formal$complete)) {
    z <- formal$results; m <- formal$monthly_gi
    panel <- readRDS('data/processed/panel.rds')
    stopifnot(nrow(z)==330L,nrow(m)==18810L,
      identical(z$TS_PCODE,as.character(formal$geometry$TS_PCODE)),
      identical(m$TS_PCODE,panel$data$TS_PCODE),identical(m$month,panel$data$month),
      !anyDuplicated(paste(m$TS_PCODE,m$month)),
      sum(formal$category_counts$townships)==330L,
      sum(formal$category_counts$significant_trend)==sum(z$significant_trend),
      all(!z$significant_trend[!z$trend_testable]),
      all(z$p_value[z$significant_trend]<.05),
      all(is.na(z$classification[z$TS_PCODE %in% formal$parameters$isolates])),
      all(is.finite(m$p_sim)),all(m$p_sim>=.001 & m$p_sim<=1),
      all(abs(m$p_sim*1000-round(m$p_sim*1000))<1e-9),
      identical(formal$manifest$simulation_key$panel_md5,
                unname(tools::md5sum('data/processed/panel.rds'))))
    hot <- !is.na(z$classification) & z$classification=='intensifying hotspot'
    cold <- !is.na(z$classification) & z$classification=='diminishing coldspot'
    stopifnot(all(z$hot_fraction[hot]>=.9 & z$final_hot[hot] & z$tau[hot]>0),
      all(z$cold_fraction[cold]>=.9 & z$final_cold[cold] & z$tau[cold]>0),
      all(z$raw_tau[z$trend_testable]==z$tau[z$trend_testable]),
      all(z$raw_p_value[z$trend_testable]==z$p_value[z$trend_testable]))
    cat('PASS: formal EHSA result keys, class totals, isolate masks, trend p, and 999-permutation p grid.\n')
  }
}
