# Run from the exercise directory. Fixtures check counting and identity errors.
if (!file.exists('R/data-core.R')) stop('RED: data-core.R is not implemented')
source('R/data-core.R')
must_fail <- function(expr) stopifnot(inherits(tryCatch({force(expr); NULL}, error=identity), 'error'))
stopifnot(identical(canonical_station_code(c('NS26-EW14',' EW14-NS26 ')),
                    c('EW14-NS26','EW14-NS26')))
must_fail(canonical_station_code(c('EW14-EW14')))
stopifnot(identical(canonical_station_code('NS26/EW14'),'EW14-NS26'))
pop <- data.frame(PA=c('A','A','B'), SZ=c('X','X','Y'), AG=c('0_to_4','5_to_9','0_to_4'),
                  Sex='Males', TOD='Others', Pop=c('10','20','0'), Time='2025')
p <- aggregate_population(pop)
stopifnot(p$population[p$SZ=='X']==30, p$population[p$SZ=='Y']==0)
must_fail(aggregate_population(rbind(pop,pop[1,])))
bad <- pop; bad$Pop[1] <- 'na'; must_fail(aggregate_population(bad))
od <- data.frame(YEAR_MONTH='2026-09', DAY_TYPE=c('WEEKDAY','WEEKDAY','WEEKDAY','WEEKENDS/HOLIDAY','WEEKDAY'),
 TIME_PER_HOUR=c('6','9','10','7','8'), PT_TYPE='TRAIN',
 ORIGIN_PT_CODE=c('NS26-EW14','EW14-NS26','A','A','B'),
 DESTINATION_PT_CODE=c('C','D','B','B','C'), TOTAL_TRIPS=c('5','7','100','200','3'))
y <- aggregate_am_boardings(od,'2026-09')
stopifnot(y$observed_boardings[y$station_code=='EW14-NS26']==12,
          y$observed_boardings[y$station_code=='B']==3, sum(y$observed_boardings)==15)
must_fail(aggregate_am_boardings(rbind(od,od[1,]),'2026-09'))
bad <- od; bad$TOTAL_TRIPS[1] <- '-1'; must_fail(aggregate_am_boardings(bad,'2026-09'))
must_fail(aggregate_am_boardings(od,'2026-08'))
cw <- data.frame(station_code=c('EW14','NS26','B'),station_id=c('RAFFLES_PLACE','RAFFLES_PLACE','B'))
a <- align_boardings(y,cw,c('RAFFLES_PLACE','B'))
stopifnot(identical(a,c(RAFFLES_PLACE=12,B=3)))
must_fail(align_boardings(y,cw,c('RAFFLES_PLACE','B','MISSING')))
bad <- cw; bad$station_id[2] <- 'OTHER'; must_fail(align_boardings(y,bad,c('RAFFLES_PLACE','B')))
cat('PASS: data identity, population aggregation, AM origin counting, and invalid-input checks\n')
