suppressPackageStartupMessages({library(sf);library(spatstat.geom)})
z <- readRDS('data/processed/prepared.rds')
first <- readRDS('data/processed/first-order.rds')
res <- readRDS('data/processed/results.rds')
stopifnot(nrow(z$points)==npoints(first$X),sum(first$monthly$n)==nrow(z$points),
 all(st_is_valid(z$boundary)),all(lengths(st_intersects(z$points,z$boundary))>0),
 all(z$points$confidence %in% c('n','h')),res$params$nsim==199L,
 all(is.finite(res$curves$observed)),all(is.finite(res$curves$lower)),
 all(is.finite(res$curves$upper)),all(res$curves$lower<=res$curves$upper))
for(name in c('csr','inhom')) {
 e <- readRDS(paste0('data/processed/',name,'-envelope.rds'))
 sims <- as.data.frame(attr(e,'simfuns'))
 stopifnot(ncol(sims)==200,all(is.finite(as.matrix(sims))))
}
cat('PASS: count reconciliation, spatial containment, confidence, finite curves and all 199 simulations per reference.\n')
