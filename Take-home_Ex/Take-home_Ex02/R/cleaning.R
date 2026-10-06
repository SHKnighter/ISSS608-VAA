# Data preparation rules for Take-home Exercise 2.
filter_events <- function(events) {
  required <- c('event_id_cnty','event_date','country','event_type',
                'geo_precision','latitude','longitude','fatalities',
                'admin1','admin2','admin3')
  if (!all(required %in% names(events))) stop('Missing required event columns')
  if (anyNA(events$event_id_cnty) || any(!nzchar(trimws(events$event_id_cnty))))
    stop('Missing event IDs')
  if (anyDuplicated(events$event_id_cnty)) stop('Duplicate event IDs')
  if (!is.numeric(events$fatalities) || any(!is.finite(events$fatalities)) ||
      any(events$fatalities < 0 | events$fatalities != floor(events$fatalities)))
    stop('Invalid fatalities: expected nonnegative reported integers')
  events$event_date <- as.Date(as.character(events$event_date),format='%Y-%m-%d')
  events$exclusion_reason <- NA_character_
  audit <- data.frame(step='raw',input=nrow(events),removed=0L,remaining=nrow(events))
  rules <- list(
    date_in_scope=!is.na(events$event_date) & events$event_date >= as.Date('2021-01-01') &
      events$event_date <= as.Date('2025-09-30'),
    myanmar=events$country %in% 'Myanmar',
    three_violence_types=events$event_type %in% c('Battles','Explosions/Remote violence','Violence against civilians'),
    township_precision=events$geo_precision %in% c(1,2),
    valid_coordinates=is.finite(events$latitude) & is.finite(events$longitude) &
      abs(events$latitude)<=90 & abs(events$longitude)<=180)
  for (rule in names(rules)) {
    active <- is.na(events$exclusion_reason)
    keep <- rules[[rule]]; keep[is.na(keep)] <- FALSE
    removed <- active & !keep
    events$exclusion_reason[removed] <- rule
    audit <- rbind(audit,data.frame(step=rule,input=sum(active),removed=sum(removed),
                                   remaining=sum(is.na(events$exclusion_reason))))
  }
  list(events=events[is.na(events$exclusion_reason),setdiff(names(events),'exclusion_reason'),drop=FALSE],
       rejected=events[!is.na(events$exclusion_reason),,drop=FALSE], audit=audit)
}

assign_townships <- function(events,townships) {
  if (!all(c('TS_PCODE','TS') %in% names(townships))) stop('Missing township columns')
  if (anyNA(townships$TS_PCODE) || any(!nzchar(townships$TS_PCODE))) stop('Missing township codes')
  if (anyDuplicated(townships$TS_PCODE)) stop('Duplicate township codes')
  if (is.na(sf::st_crs(townships))) stop('Unknown boundary CRS')
  if (any(sf::st_is_empty(townships)) || any(!sf::st_is_valid(townships)))
    stop('Invalid or empty township geometry: inspect the source before proceeding')
  if (anyDuplicated(events$event_id_cnty)) stop('Duplicate event IDs')
  townships <- sf::st_transform(townships,4326)
  points <- sf::st_as_sf(events,coords=c('longitude','latitude'),crs=4326,remove=FALSE)
  # Closed polygons expose shared-edge ambiguities rather than choosing a side.
  hits <- sf::st_intersects(points,townships,model='closed')
  counts <- lengths(hits)
  unique_match <- counts == 1L
  assigned <- events[unique_match,,drop=FALSE]
  idx <- vapply(hits[unique_match],function(x) x[[1]],integer(1))
  assigned$TS_PCODE <- townships$TS_PCODE[idx]
  assigned$township_name <- townships$TS[idx]
  compare_name <- function(a,b) {
    normalize <- function(x) tolower(gsub('[^[:alnum:]]','',x))
    ifelse(is.na(a)|!nzchar(trimws(a)),'missing',
           ifelse(normalize(a)==normalize(b),'same','different'))
  }
  assigned$name_check <- compare_name(assigned$admin3,assigned$township_name)
  if ('ST' %in% names(townships)) {
    assigned$boundary_admin1 <- townships$ST[idx]
    assigned$admin1_check <- compare_name(assigned$admin1,assigned$boundary_admin1)
  }
  if ('DT' %in% names(townships)) {
    assigned$boundary_admin2 <- townships$DT[idx]
    assigned$admin2_check <- compare_name(assigned$admin2,assigned$boundary_admin2)
  }
  unresolved <- events[!unique_match,,drop=FALSE]
  unresolved$spatial_matches <- counts[!unique_match]
  unresolved$candidate_pcodes <- vapply(hits[!unique_match],function(i)
    paste(townships$TS_PCODE[i],collapse=';'),character(1))
  unresolved$exclusion_reason <- ifelse(unresolved$spatial_matches==0,
                                      'outside_boundary','multiple_townships')
  list(assigned=assigned,unresolved=unresolved)
}
