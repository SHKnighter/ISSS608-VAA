# Run from this exercise directory; acquisition is a separate explicit command.
source('R/data-core.R')
source('R/cache-guard.R')
needed <- c('sf','readr','digest','jsonlite')
if (any(!vapply(needed,requireNamespace,logical(1),quietly=TRUE))) stop('Missing installed dependency')
files <- paste0('data/raw/',c('population-2025.csv','subzones-mp2019.geojson',
 'operational-stations.csv','future-stations.csv','train-stations-sep2026.zip','bus-stops-sep2026.zip'))
if (!all(file.exists(files))) stop('Run python R/acquire-public.py first. See data/README.md')
for (d in c('data/processed','output/tables','_workflow')) dir.create(d,showWarnings=FALSE,recursive=TRUE)
csv <- function(x,name) readr::write_csv(sf::st_drop_geometry(x),paste0('output/tables/',name,'.csv'))
rawpop <- readr::read_csv(files[1],col_types=readr::cols(.default='c'),show_col_types=FALSE)
pop <- aggregate_population(as.data.frame(rawpop))
subzones <- sf::st_read(files[2],quiet=TRUE)
if (any(!sf::st_is_valid(subzones))) subzones <- sf::st_make_valid(subzones)
subzones <- sf::st_transform(subzones,3414)
if (anyDuplicated(subzones$SUBZONE_C)) stop('Duplicate official subzone code')
pk <- paste(pop$PA,pop$SZ,sep='|')
sk <- paste(normalise_name(subzones$PLN_AREA_N),normalise_name(subzones$SUBZONE_N),sep='|')
if (anyDuplicated(pk) || anyDuplicated(sk)) stop('Duplicate subzone matching key')
unmatched <- pop[!pk %in% sk,]
csv(unmatched,'unmatched-population')
if (any(unmatched$population>0) || any(!sk %in% pk)) stop('Population/boundary mismatch: inspect unmatched-population.csv')
subzones$population <- pop$population[match(sk,pk)]
subzones$origin_id <- as.character(subzones$SUBZONE_C)
subzones <- subzones[order(subzones$origin_id),]
origins <- suppressWarnings(sf::st_point_on_surface(subzones[subzones$population>0,]))
origins$population_share <- origins$population/sum(origins$population)

op <- read.csv(files[3],stringsAsFactors=FALSE)
future <- read.csv(files[4],stringsAsFactors=FALSE)
# The professor CSV status predates the 12 July2026 CCL6 opening (official evidence in sources).
cc6 <- future[future$station_code %in% c('CC30','CC31','CC32'),]
existing <- rbind(op,cc6)[c('station_code','station_name','lat','lon')]
# The Aug/Sep2026 LTA composites identify CC34/DT16 as Bayfront and
# NS27/CC33/TE20 as Marina Bay. Retain old CE1/CE2 as aliases, not extra lines.
aliases <- data.frame(station_code=c('CC34','CC33'),source_code=c('CE1','CE2'),
 evidence=c('LTA monthly composite CC34/DT16','LTA monthly composite NS27/CC33/TE20'))
alias_rows <- existing[match(aliases$source_code,existing$station_code),]
if (anyNA(alias_rows$station_code)) stop('Missing source for monthly station-code aliases')
alias_rows$station_code <- aliases$station_code
existing <- rbind(existing,alias_rows)
csv(aliases,'station-code-aliases')
if (anyDuplicated(existing$station_code)) stop('Duplicate reference operating code')
jrl <- c(paste0('JS',1:12),paste0('JE',1:7),paste0('JW',1:5))
crl <- paste0('CR',2:13)
proposals <- future[future$station_code %in% c(jrl,crl),c('station_code','station_name','lat','lon')]
if (!setequal(proposals$station_code,c(jrl,crl)) || anyDuplicated(proposals$station_code)) stop('Incomplete JRL24/CRL1_12 scope')
proposals$line <- ifelse(proposals$station_code %in% jrl,'JRL','CRL')
crosswalk <- rbind(transform(existing,baseline_reference=TRUE,proposal_line=''),
                  transform(proposals[c('station_code','station_name','lat','lon')],baseline_reference=FALSE,proposal_line=proposals$line))
if (anyDuplicated(crosswalk$station_code)) stop('Code appears in both current and proposed records')
crosswalk$station_id <- gsub('[^A-Z0-9]+','_',normalise_name(crosswalk$station_name))
prefix <- sub('[0-9].*$','',crosswalk$station_code)
line_map <- c(NS='NSL',EW='EWL',CG='EWL',NE='NEL',CC='CCL',CE='CCL',DT='DTL',TE='TEL',
 BP='BPLRT',SE='SKLRT',SW='SKLRT',STC='SKLRT',PE='PGLRT',PW='PGLRT',PTC='PGLRT',JS='JRL',JE='JRL',JW='JRL',CR='CRL')
crosswalk$rail_line <- unname(line_map[prefix])
if (anyNA(crosswalk$rail_line)) stop('Unmapped rail line prefix')

read_zip_shp <- function(path) {
  members <- unzip(path,list=TRUE)$Name
  shp <- members[grepl('\\.shp$',members,ignore.case=TRUE)]
  if (length(shp)!=1) stop('Expected one SHP per archive: ',path)
  x <- sf::st_read(paste0('/vsizip/',normalizePath(path,winslash='/'),'/',shp),quiet=TRUE)
  if (is.na(sf::st_crs(x))) stop('Source CRS is missing: ',path)
  # Read the WKT rather than replacing an unspecified EPSG identifier.
  sf::st_transform(x,3414)
}
footprints <- read_zip_shp(files[5])
if (any(!sf::st_is_valid(footprints))) footprints <- sf::st_make_valid(footprints)
ids <- sort(unique(crosswalk$station_id))
geometry <- vector('list',length(ids)); point_source <- character(length(ids))
for (i in seq_along(ids)) {
  rows <- crosswalk[crosswalk$station_id==ids[i],]
  footprint_rows <- which(footprints$STN_NAM %in% rows$station_code)
  if (length(footprint_rows)) {
    geometry[[i]] <- suppressWarnings(sf::st_point_on_surface(sf::st_union(footprints[footprint_rows,])))[[1]]
    point_source[i] <- 'LTA footprint union interior point'
  } else {
    z <- sf::st_as_sf(data.frame(lon=median(rows$lon),lat=median(rows$lat)),coords=c('lon','lat'),crs=4326)
    geometry[[i]] <- sf::st_geometry(sf::st_transform(z,3414))[[1]]
    point_source[i] <- 'Professor-linked coordinate library'
  }
}
stations <- sf::st_sf(station_id=ids,station_name=crosswalk$station_name[match(ids,crosswalk$station_id)],
 point_source=point_source,geometry=sf::st_sfc(geometry,crs=3414))
bus <- read_zip_shp(files[6])
bus_source_count <- nrow(bus)
bus <- bus[!is.na(bus$STATUS)&bus$STATUS=='OP',]
if (anyNA(bus$BUS_STOP_N) || anyDuplicated(bus$BUS_STOP_N)) stop('Missing/duplicate operational bus-stop ID needs review')
stations$bus_stops_500m <- lengths(sf::st_is_within_distance(stations,bus,dist=500))
for (scenario in c('existing','jrl','crl','both')) {
  selected <- crosswalk$baseline_reference | (scenario %in% c('jrl','both') & crosswalk$proposal_line=='JRL') |
    (scenario %in% c('crl','both') & crosswalk$proposal_line=='CRL')
  counts <- tapply(crosswalk$rail_line[selected],crosswalk$station_id[selected],function(x) length(unique(x)))
  stations[[paste0('lines_',scenario)]] <- as.integer(counts[stations$station_id])
  stations[[paste0('available_',scenario)]] <- !is.na(stations[[paste0('lines_',scenario)]])
  stations[[paste0('attraction_',scenario)]] <- (1+stations$bus_stops_500m)*stations[[paste0('lines_',scenario)]]
}
distance_m <- units::drop_units(sf::st_distance(origins,stations))
rownames(distance_m) <- origins$origin_id; colnames(distance_m) <- stations$station_id
prepared <- list(subzones=subzones,origins=origins,stations=stations,crosswalk=crosswalk,proposals=proposals,
 distance_m=distance_m,source_population=sum(pop$population))
attr(prepared,'input_fingerprint') <- fingerprint_files(public_dependency_paths())
saveRDS(prepared, 'data/processed/public-prepared.rds')
csv(subzones[c('origin_id','PLN_AREA_N','SUBZONE_N','population')],'origin-population')
csv(stations,'station-candidates'); csv(crosswalk,'station-code-crosswalk');csv(proposals,'proposed-line-stations')
audit <- data.frame(measure=c('raw_population_rows','official_subzones','positive_population_origins','resident_population_rounded',
 'reference_existing_physical_stations','expanded_physical_stations','JRL_line_stations','CRL1_line_stations','all_bus_features','operational_bus_stops'),
 value=c(nrow(rawpop),nrow(subzones),nrow(origins),sum(pop$population),sum(stations$available_existing),nrow(stations),24,12,bus_source_count,nrow(bus)))
csv(audit,'public-data-audit')
fingerprint <- list(acquired_inputs=lapply(files,function(f) list(file=f,sha256=digest::digest(file=f,algo='sha256'))),
 code_sha256=digest::digest(file='R/01-prepare-public.R',algo='sha256'),
 data_core_sha256=digest::digest(file='R/data-core.R',algo='sha256'),status='PUBLIC_INPUTS_PREPARED_RIDERSHIP_AND_MONTHLY_ROSTER_PENDING')
jsonlite::write_json(fingerprint,'_workflow/public-preparation.json',auto_unbox=TRUE,pretty=TRUE)
print(audit,row.names=FALSE)
cat('Public inputs prepared. Existing roster remains a reference pending monthly ridership reconciliation.\n')
