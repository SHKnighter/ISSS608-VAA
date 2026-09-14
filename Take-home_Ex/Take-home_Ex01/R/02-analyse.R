suppressPackageStartupMessages({library(sf);library(dplyr);library(ggplot2);library(spatstat.geom);library(spatstat.explore);library(spatstat.random)})
dir.create('output/figures',showWarnings=FALSE,recursive=TRUE)
z <- readRDS('data/processed/prepared.rds'); p <- z$points; b <- z$boundary
W <- as.owin(st_geometry(b)); W <- rescale(W,1000,unitname=c('kilometre','kilometres'))
X <- ppp(p$easting_m/1000,p$northing_m/1000,window=W)
stopifnot(npoints(X)==nrow(p),!any(duplicated(X)))
params <- list(seed=6262026L,nsim=199L,kde_sigma_km=c(5,10),pixel_km=0.5,r_km=seq(0,10,by=0.1),inhom_sigma_km=10)
saveRDS(params,'_workflow/parameters.rds')
writeLines(capture.output(str(params)),'_workflow/parameters.txt')
theme_set(theme_minimal(base_size=12)+theme(panel.grid.minor=element_blank(),plot.title=element_text(face='bold'),plot.title.position='plot',plot.caption.position='plot',plot.margin=margin(12,12,12,12),plot.caption=element_text(hjust=0,size=9)))
save_plot <- function(g,name,w=9,h=6) ggsave(paste0('output/figures/',name,'.png'),g,width=w,height=h,dpi=180,bg='white')
map <- ggplot()+geom_sf(data=b,fill='#edf1f3',colour='#34495e',linewidth=.35)+geom_sf(data=p,colour='#d55129',alpha=.35,size=.35)+
 labs(title='Thermal detections in Kapuas',subtitle='VIIRS S-NPP | Jan-Aug 2026 | nominal/high confidence',x=NULL,y=NULL,caption='Sources: NASA FIRMS request 804686; BIG boundary.\nEach point represents a satellite detection.')+
 annotate('text',x=st_bbox(b)['xmin']+13000,y=st_bbox(b)['ymax']-15000,label='N',size=5)+
 annotate('segment',x=st_bbox(b)['xmin']+5000,xend=st_bbox(b)['xmin']+55000,y=st_bbox(b)['ymin']+8000,yend=st_bbox(b)['ymin']+8000,linewidth=1)+
 annotate('text',x=st_bbox(b)['xmin']+30000,y=st_bbox(b)['ymin']+17000,label='50 km',size=3)+theme(axis.text.x=element_text(angle=35,hjust=1,size=9))
save_plot(map,'detections',8,9)
months <- format(seq(as.Date('2026-01-01'),as.Date('2026-08-01'),by='month'),'%Y-%m')
monthly <- data.frame(month=months,n=as.integer(table(factor(p$month,levels=months))))
monthly$calendar_days <- c(31,28,31,30,31,30,31,31)
monthly$per_calendar_day <- monthly$n/monthly$calendar_days
write.csv(monthly,'output/tables/monthly.csv',row.names=FALSE)
g <- ggplot(monthly,aes(month,n))+geom_col(fill='#d55129',width=.65)+geom_text(aes(label=format(n,big.mark=',')),vjust=-.4,size=3.7)+
 scale_y_continuous(expand=expansion(mult=c(0,.12)))+labs(title='August accounts for most retained detections',x=NULL,y='Detection records',caption='Zero denotes no retained detections, not proven absence of fire. Coverage and processing vary.')
save_plot(g,'monthly',9,5)
kd <- lapply(params$kde_sigma_km,function(s) density(X,sigma=s,eps=params$pixel_km,edge=TRUE))
grids <- bind_rows(lapply(seq_along(kd),function(i){d<-as.data.frame(kd[[i]]);names(d)<-c('x','y','intensity');d$bandwidth<-paste('Gaussian sigma =',params$kde_sigma_km[i],'km');d}))
bs <- st_as_sf(as.polygonal(W))
g <- ggplot(grids,aes(x,y,fill=intensity))+geom_raster()+geom_sf(data=bs,inherit.aes=FALSE,fill=NA,colour='#34495e',linewidth=.3)+
 scale_fill_viridis_c(option='inferno',name='Detections / sq km',na.value='white')+coord_sf(datum=NA)+facet_wrap(~bandwidth)+
 annotate('segment',x=160,xend=210,y=9625,yend=9625,linewidth=.8,colour='#cccccc')+
 annotate('text',x=185,y=9632,label='50 km',colour='#777777',size=3)+
 labs(title='Detection intensity at two smoothing scales',subtitle='Boundary-corrected Gaussian KDE; 500 m grid; north is up',x=NULL,y=NULL,caption='Same colour scale across panels. Density measures observed detections, not burned area or risk.')
save_plot(g,'kde',10,9)
main <- kd[[1]]; broad <- kd[[2]]
peak <- as.data.frame(main); peak <- peak[which.max(peak$value),]
correlation <- cor(as.vector(main$v),as.vector(broad$v),use='complete.obs',method='spearman')
summary <- list(n=npoints(X),area_km2=area.owin(W),august_share=monthly$n[8]/sum(monthly$n),kde_spearman=correlation,kde_peak=peak,known_static=sum(p$type==2,na.rm=TRUE),unknown_type=sum(is.na(p$type)))
saveRDS(list(X=X,kde=kd,monthly=monthly,summary=summary),'data/processed/first-order.rds')
cat('CP4A saved\n');print(summary)
# Conditional-on-count CSR reference. Pointwise envelopes are explicitly labelled; no multiple-distance p-value is claimed.
set.seed(params$seed)
csr <- envelope(X,Lest,nsim=params$nsim,simulate=expression(runifpoint(npoints(X),win=W)),r=params$r_km,correction='translate',savefuns=TRUE,verbose=FALSE)
saveRDS(csr,'data/processed/csr-envelope.rds');cat('CSR simulations saved\n')
# Inhomogeneous binomial reference conditional on count and an estimated smooth intensity.
# Reestimate the leave-one-out intensity for each simulated pattern at the same fixed bandwidth.
L_adjusted <- function(Y,r,...) {
 lambda <- density(Y,sigma=params$inhom_sigma_km,at='points',leaveoneout=TRUE,edge=TRUE)
 K <- Kinhom(Y,lambda=lambda,r=r,correction='translate')
 eval.fv(sqrt(K/pi))
}
set.seed(params$seed+1L)
inh <- envelope(X,L_adjusted,nsim=params$nsim,simulate=expression(rpoint(npoints(X),f=broad,win=W,forcewin=TRUE)),r=params$r_km,savefuns=TRUE,verbose=FALSE)
saveRDS(inh,'data/processed/inhom-envelope.rds');cat('Inhomogeneous simulations saved\n')
curves <- bind_rows(lapply(c('CSR','Inhomogeneous reference'),function(label){e<-as.data.frame(if(label=='CSR')csr else inh);data.frame(r=e$r,observed=e$obs-e$r,lower=e$lo-e$r,upper=e$hi-e$r,reference=label)}))
write.csv(curves,'output/tables/l-curves.csv',row.names=FALSE)
g <- ggplot(curves,aes(r,observed))+geom_ribbon(aes(ymin=lower,ymax=upper),fill='#bdcbd3',alpha=.7)+geom_hline(yintercept=0,linetype=2,colour='#555555')+geom_line(colour='#d55129',linewidth=.9)+facet_wrap(~reference,scales='free_y')+
 labs(title='Pair structure relative to two spatial reference patterns',subtitle='Translation correction | 199 simulations | conditional on 6,515 points',x='Distance r (km)',y='L(r) - r (km)',caption='Grey: pointwise min-max reference envelope (~99% at each distance). Panels have different y scales.\nInhomogeneous envelope is an estimated-intensity diagnostic, not a calibrated global significance test.')
save_plot(g,'l-functions',10,5.5)
saveRDS(list(params=params,summary=summary,curves=curves),'data/processed/results.rds')
writeLines(capture.output(sessionInfo()),'_workflow/session-info.txt')
cat('CP4B saved\n');print(curves[curves$r %in% c(1,5,10),])
