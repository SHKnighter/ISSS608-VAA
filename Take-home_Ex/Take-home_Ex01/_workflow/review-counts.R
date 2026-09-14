# Independent review: do not call the production cleaning helper.
suppressPackageStartupMessages(library(sf))
a <- read.csv('data/raw/fire_archive_SV-C2_804686.csv',colClasses='character')
n <- read.csv('data/raw/fire_nrt_SV-C2_804686.csv',colClasses='character')
common <- intersect(names(a),names(n)); raw <- rbind(a[common],n[common])
lon <- as.numeric(raw$longitude); lat <- as.numeric(raw$latitude)
b <- st_transform(st_zm(st_read('data/raw/kapuas_big_20240905.geojson',quiet=TRUE)),4326)
box <- st_bbox(b)
idx <- which(lon>=box['xmin'] & lon<=box['xmax'] & lat>=box['ymin'] & lat<=box['ymax'])
candidate <- st_as_sf(data.frame(lon=lon[idx],lat=lat[idx]),coords=c('lon','lat'),crs=4326)
county <- raw[idx[lengths(st_intersects(candidate,b))>0],]
retained <- county[county$confidence %in% c('n','h'),]
actual <- c(raw=nrow(raw),county=nrow(county),low=sum(county$confidence=='l'),retained=nrow(retained),august=sum(substr(retained$acq_date,6,7)=='08'))
stopifnot(identical(as.integer(actual),c(199798L,6716L,201L,6515L,6290L)))
curve <- read.csv('output/tables/l-curves.csv')
excess <- aggregate(I(observed>upper)~reference,subset(curve,r>=.5),sum)
stopifnot(all(excess[,2]==96))
print(actual); print(excess)
cat('PASS: independent raw CSV count and polygon selection; selected curve claims.\n')
