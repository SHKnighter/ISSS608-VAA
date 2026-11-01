if (!file.exists('data/processed/public-prepared.rds')) stop('RED: public inputs not prepared')
p <- readRDS('data/processed/public-prepared.rds')
stopifnot(nrow(p$subzones)==332, !anyDuplicated(p$subzones$origin_id),
          !anyNA(p$subzones$population),sum(p$subzones$population)==p$source_population,
          all(p$origins$population>0),!anyDuplicated(p$stations$station_id),
          !anyDuplicated(p$crosswalk$station_code),
          sum(p$proposals$line=='JRL')==24, sum(p$proposals$line=='CRL')==12,
          !'JS2A' %in% p$proposals$station_code,
          all(c('CC30','CC31','CC32') %in% p$crosswalk$station_code[p$crosswalk$baseline_reference]),
          sf::st_crs(p$stations)$epsg==3414,
          all(is.finite(p$distance_m)),all(p$distance_m>=0),
          identical(rownames(p$distance_m),p$origins$origin_id),
          identical(colnames(p$distance_m),p$stations$station_id))
ix <- p$crosswalk$station_id[match(c('NS4','BP1','JS1'),p$crosswalk$station_code)]
stopifnot(length(unique(ix))==1, p$stations$bus_stops_500m>=0)
stopifnot(p$crosswalk$station_id[match('CC34',p$crosswalk$station_code)]=='BAYFRONT',
          p$crosswalk$station_id[match('CC33',p$crosswalk$station_code)]=='MARINA_BAY',
          length(unique(p$crosswalk$station_id[match(c('DT10','TE11'),p$crosswalk$station_code)]))==1)
cat('PASS: population conservation, spatial keys/CRS, JRL/CRL scope, corrected CCL6 roster, interchange merge and matrix ordering\n')
