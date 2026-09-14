# Redraw saved results for slides; do not fit models or simulate patterns.
suppressPackageStartupMessages({library(sf);library(ggplot2);library(spatstat.geom)})
presentation_data <- readRDS('data/processed/prepared.rds')
presentation_first <- readRDS('data/processed/first-order.rds')
presentation_results <- readRDS('data/processed/results.rds')
dir.create('presentation/figures',recursive=TRUE,showWarnings=FALSE)
slide_theme <- theme_minimal(base_size=15)+theme(panel.grid.minor=element_blank(),
 plot.title=element_text(face='bold',size=16),plot.title.position='plot',
 plot.caption.position='plot',plot.margin=margin(8,12,8,8),
 plot.caption=element_text(size=10,hjust=0),legend.title=element_text(size=11))
save_slide_figure <- function(plot,name,width,height) {
 ggsave(paste0('presentation/figures/',name,'.svg'),plot,width=width,height=height,
        device=grDevices::svg,bg='white')
 ggsave(paste0('presentation/figures/',name,'.png'),plot,width=width,height=height,dpi=160,bg='white')
}
pp <- presentation_data$points; bb <- presentation_data$boundary
map <- ggplot()+geom_sf(data=bb,fill='#edf2f4',colour='#34495e',linewidth=.4)+
 geom_sf(data=pp,colour='#c9522b',size=.35,alpha=.4)+
 annotate('text',x=st_bbox(bb)['xmin']+10000,y=st_bbox(bb)['ymax']-16000,label='N',size=4)+
 annotate('segment',x=st_bbox(bb)['xmin']+5000,xend=st_bbox(bb)['xmin']+55000,
          y=st_bbox(bb)['ymin']+8000,yend=st_bbox(bb)['ymin']+8000,linewidth=.8)+
 annotate('text',x=st_bbox(bb)['xmin']+30000,y=st_bbox(bb)['ymin']+17000,label='50 km',size=3.5)+
 labs(x=NULL,y=NULL)+slide_theme+
 theme(axis.text.x=element_text(angle=35,hjust=1,size=10),axis.text.y=element_text(size=10))
save_slide_figure(map,'detections',5.2,7.5)
mm <- presentation_first$monthly; mm$label <- factor(month.abb[1:8],levels=month.abb[1:8])
monthly_plot <- ggplot(mm,aes(label,n))+geom_col(fill='#c9522b',width=.68)+
 geom_text(aes(label=format(n,big.mark=',')),vjust=-.4,size=4)+
 scale_y_continuous(expand=expansion(mult=c(0,.12)))+
 labs(title='Detections by month',x=NULL,y='Records')+slide_theme
save_slide_figure(monthly_plot,'monthly',7,4.2)
grid <- do.call(rbind,lapply(1:2,function(i){d<-as.data.frame(presentation_first$kde[[i]]);
 names(d)<-c('x','y','intensity');d$bandwidth<-factor(paste(c(5,10)[i],'km sigma'),levels=c('5 km sigma','10 km sigma'));d}))
outline <- st_as_sf(as.polygonal(Window(presentation_first$X)))
kde_plot <- ggplot(grid,aes(x,y,fill=intensity))+geom_raster()+
 geom_sf(data=outline,inherit.aes=FALSE,fill=NA,colour='#34495e',linewidth=.3)+
 scale_fill_viridis_c(option='inferno',name='Detections per sq km',na.value='white')+
 facet_wrap(~bandwidth)+coord_sf(datum=NA)+
 labs(x=NULL,y=NULL,caption='Same colour scale; north is up')+slide_theme+
 theme(legend.position='bottom',legend.key.width=grid::unit(1.4,'cm'),legend.key.height=grid::unit(.25,'cm'))
save_slide_figure(kde_plot,'density',5.8,6.8)
curves <- presentation_results$curves
curves$reference <- factor(curves$reference,levels=c('CSR','Inhomogeneous reference'),labels=c('Uniform reference','Varying intensity reference'))
curve_plot <- ggplot(curves,aes(r,observed))+geom_ribbon(aes(ymin=lower,ymax=upper),fill='#b8c7d0',alpha=.8)+
 geom_hline(yintercept=0,linetype=2,colour='#666666')+geom_line(colour='#c9522b',linewidth=1)+
 facet_wrap(~reference,scales='free_y')+
 scale_y_continuous(labels=function(x)sub('-',intToUtf8(8722),format(x,trim=TRUE),fixed=TRUE))+
 labs(x='Distance (km)',y='L relative to r (km)',caption='199 simulations per reference; grey bands are pointwise envelopes. Vertical scales differ.')+slide_theme
save_slide_figure(curve_plot,'pairpatterns',10.5,4.3)
