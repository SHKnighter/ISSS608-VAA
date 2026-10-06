# Static report figures, reused by the revealjs summary.
suppressPackageStartupMessages({library(sf);library(dplyr);library(ggplot2);library(tmap)})
panel <- readRDS('data/processed/panel.rds')
lmsa <- readRDS('data/processed/lmsa.rds')
ehsa <- readRDS('data/processed/ehsa.rds')
dir.create('output/figures',recursive=TRUE,showWarnings=FALSE)
theme_set(theme_minimal(base_size=14)+theme(panel.grid.minor=element_blank(),
  plot.title=element_text(face='bold',size=18),plot.subtitle=element_text(size=12),
  plot.caption=element_text(size=10,hjust=0),axis.title=element_text(size=12)))
source_note <- 'Sources: ACLED supplied snapshot; MIMU township boundaries v9.4'
save_chart <- function(p,name,width=10,height=5.5) {
  ggsave(file.path('output/figures',paste0(name,'.png')),plot=p,
         width=width,height=height,dpi=160,bg='white')
}
monthly <- panel$data |> group_by(month) |> summarise(events=sum(event_count),.groups='drop')
save_chart(ggplot(monthly,aes(month,events))+geom_line(linewidth=.8,color='#216b68')+
  geom_point(size=1.6,color='#216b68')+expand_limits(y=0)+
  scale_x_date(date_breaks='6 months',date_labels='%b %Y')+
  scale_y_continuous(labels=scales::label_comma())+
  labs(title='Recorded violence by month',subtitle='Myanmar, January 2021 to September 2025',
       x=NULL,y='Retained events',caption='All 57 months are included. Counts reflect available reports.')+
  theme(axis.text.x=element_text(angle=35,hjust=1)),'monthly-events')
types <- data.frame(type=c('Battles','Explosions / remote violence','Violence against civilians'),
  events=c(sum(panel$data$battles),sum(panel$data$explosions_remote),sum(panel$data$civilian_violence)))
types$type <- reorder(types$type,types$events)
save_chart(ggplot(types,aes(events,type))+geom_col(fill='#357c79',width=.62)+
  geom_text(aes(label=scales::comma(events)),hjust=-.15,size=4.5)+
  scale_x_continuous(labels=scales::label_comma(),expand=expansion(mult=c(0,.18)))+
  labs(title='Event types retained for analysis',x='Events',y=NULL,
       caption='The categories are mutually exclusive ACLED event types.'),'event-types',10,4.4)

tmap_mode('plot')
tmap_options(show.messages=FALSE)
# Equal-area display projection for the whole country. Joins/Queen weights use
# the original WGS84 geometry; no distance-based inference uses this display CRS.
map_crs <- '+proj=aea +lat_1=10 +lat_2=28 +lat_0=19 +lon_0=96 +datum=WGS84 +units=m +no_defs'
map_data <- st_transform(lmsa$results,map_crs)
categorical_map <- function(x,field,palette,title,legend_title,filename) {
  stopifnot(all(unique(as.character(x[[field]])) %in% names(palette)))
  x[[field]] <- factor(x[[field]],levels=names(palette))
  build_map <- function(legend_size=1,heading=TRUE) {
    z <- tm_shape(x)+tm_polygons(fill=field,col='#ffffff',lwd=.35,
    fill.scale=tm_scale_categorical(values=palette,levels=names(palette),levels.drop=TRUE),
    fill.legend=tm_legend(title=legend_title,text.size=.95*legend_size,title.size=legend_size,
                        position=tm_pos_out('right','center')))+
    tm_layout(frame=FALSE,bg.color='white',outer.margins=c(.025,.025,.025,.025))
    if (heading) z <- z +
      tm_title(title,size=1.15,position=tm_pos_out('center','top',pos.h='left'))+
      tm_credits(source_note,size=.6,position=tm_pos_out('center','bottom',pos.h='left'))
    z
  }
  m <- build_map()
  tmap_save(m,file.path('output/figures',paste0(filename,'.png')),
            width=7.5,height=8,units='in',dpi=160)
  # Same validated data and colour mapping, with larger legends for projection.
  if (filename %in% c('township-counts','local-moran','ehsa-significant-categories'))
    tmap_save(build_map(legend_size=1.45,heading=FALSE),
      file.path('output/figures',paste0(filename,'-slides.png')),
      width=8,height=7,units='in',dpi=160)
  invisible(m)
}
map_data$count_band <- cut(map_data$event_count,
  breaks=c(-.5,.5,50.5,200.5,500.5,1000.5,Inf),
  labels=c('0','1 to 50','51 to 200','201 to 500','501 to 1,000','More than 1,000'))
categorical_map(map_data,'count_band',setNames(c('#f0f0f0','#d4eeeb','#94d0c4','#4fada0','#24786c','#084c43'),
  levels(map_data$count_band)),'Total recorded events, 2021 to September 2025','Events','township-counts')
moran_colors <- c('HH'='#b63b35','LL'='#377cad','HL'='#dc917c','LH'='#a98fce',
 'Not significant'='#e2e5e5','No contiguous neighbours'='#686c70')
gi_colors <- c('Hotspot'='#b63b35','Coldspot'='#377cad',
 'Not significant'='#e2e5e5','No contiguous neighbours'='#686c70')
categorical_map(map_data,'moran_class',moran_colors,'Local Moran clusters','Permutation p < 0.05','local-moran')
categorical_map(map_data,'gi_class',gi_colors,'Getis-Ord Gi* hot and cold spots','Permutation p < 0.05','gistar')

eh <- st_transform(ehsa$geometry,map_crs)
stopifnot(identical(eh$TS_PCODE,ehsa$results$TS_PCODE))
eh$ehsa_class <- ifelse(is.na(ehsa$results$classification),'Not testable',ehsa$results$classification)
eh$trend_direction <- ehsa$results$trend_direction
class_colors <- c('new hot spot'='#ed8c24','consecutive hot spot'='#c66b12',
 'intensifying hot spot'='#9b161c','persistent hot spot'='#c34040',
 'diminishing hot spot'='#d77d8c','sporadic hot spot'='#e1ad85',
 'oscillating hot spot'='#aa4787','historical hot spot'='#b78c70',
 'new cold spot'='#48b9cf','consecutive cold spot'='#1695a9',
 'intensifying cold spot'='#12396c','persistent cold spot'='#366eab',
 'diminishing cold spot'='#9baccf','sporadic cold spot'='#9ecedf',
 'oscillating cold spot'='#7664ad','historical cold spot'='#88a1a4',
 'no pattern detected'='#e2e5e5','no pattern'='#e2e5e5','not testable'='#686c70')
norm <- function(x) gsub('coldspot','cold spot',gsub('hotspot','hot spot',gsub('_',' ',tolower(x))))
classes <- sort(unique(eh$ehsa_class))
pal <- setNames(unname(class_colors[norm(classes)]),classes)
if (anyNA(pal)) stop('Unmapped EHSA class: ',paste(names(pal)[is.na(pal)],collapse=', '))
categorical_map(eh,'ehsa_class',pal,'Emerging hot and cold spot categories','Full history classification','ehsa-categories')
eh$significant_category <- ifelse(ehsa$results$trend_testable,
  ifelse(ehsa$results$significant_trend,eh$ehsa_class,'No significant trend'),'Not testable')
significant_pal <- c(pal,'No significant trend'='#e2e5e5')
significant_pal[norm(names(significant_pal)) %in% c('no pattern detected','no pattern')] <- '#baa98e'
if (!'Not testable' %in% names(significant_pal)) significant_pal <- c(significant_pal,'Not testable'='#686c70')
categorical_map(eh,'significant_category',significant_pal,
  'EHSA categories with significant trends','Mann-Kendall p < 0.05','ehsa-significant-categories')
trend_colors <- c('increasing Gi*'='#b63b35','decreasing Gi*'='#377cad',
                 'no significant trend'='#e2e5e5','not testable'='#686c70')
categorical_map(eh,'trend_direction',trend_colors,'Changes in relative clustering','Mann-Kendall p < 0.05','ehsa-trends')

# Deterministic examples: the largest event total within each of up to four
# most populated classified groups. These are illustrations, not extra tests.
r <- ehsa$results
totals <- st_drop_geometry(lmsa$results)[,c('TS_PCODE','TS','event_count')]
r <- left_join(r,totals,by='TS_PCODE')
groups <- r |> filter(!is.na(classification),!grepl('no pattern',norm(classification))) |>
  count(classification,sort=TRUE) |> head(4)
example <- r |> filter(classification %in% groups$classification) |>
  arrange(classification,desc(event_count),TS_PCODE) |> group_by(classification) |> slice_head(n=1) |> ungroup()
readr::write_csv(st_drop_geometry(example),'output/tables/ehsa-illustrative-townships.csv')
histories <- inner_join(ehsa$monthly_gi,example[,c('TS_PCODE','TS','classification')],by='TS_PCODE')
histories$label <- paste(histories$TS,histories$classification,sep=': ')
save_chart(ggplot(histories,aes(month,gi_star))+geom_hline(yintercept=0,color='grey65')+
  geom_line(color='#216b68',linewidth=.6)+facet_wrap(~label,ncol=2,scales='fixed')+
  scale_x_date(date_breaks='2 years',date_labels='%Y')+
  labs(title='Examples of Gi* histories',x=NULL,y='Spatio-temporal Gi*',
  caption='Largest event total in each displayed category. The y-axis is shared across panels.'),
  'ehsa-examples',11,6.8)
cat('PASS: nine report figures and three slide variants saved from the same validated data.\n')
