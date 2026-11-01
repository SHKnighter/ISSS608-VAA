# Tiny fixtures stay in memory or temporary directories; never actual outputs.
source("R/model-core.R")
study_path <- file.path("R", "03-model-scenarios.R")
if (file.exists(study_path)) source(study_path)
failures <- character(); checks <- 0L
check <- function(label, code) {
  checks <<- checks + 1L
  tryCatch({ force(code); cat("PASS:", label, "\n") }, error = function(e) {
    failures <<- c(failures, paste(label, conditionMessage(e), sep = ": "))
    cat("FAIL:", label, "-", conditionMessage(e), "\n")
  })
}
near <- function(actual, expected, tolerance = 1e-7) {
  if (!isTRUE(all.equal(actual, expected, tolerance = tolerance))) stop("Unexpected numeric result")
}
rejects <- function(code) {
  error <- tryCatch({ force(code); NULL }, error = identity)
  if (is.null(error)) stop("Invalid study input was accepted")
}
stopifnot(requireNamespace("sf", quietly = TRUE))
origins <- sf::st_as_sf(data.frame(origin_id = c("x", "y", "z"),
                                  population = c(7, 13, 73), x = 1:3, y = 1:3),
                        coords = c("x", "y"), crs = 3414)
stations <- sf::st_as_sf(data.frame(station_id = c("A", "B", "C", "J", "R"),
                                   station_name = c("Alpha", "Beta", "Gamma", "JRL new", "CRL new"),
                                   x = 1:5, y = 1:5), coords = c("x", "y"), crs = 3414)
for (scenario in c("existing", "jrl", "crl", "both")) {
  available <- c(TRUE, TRUE, TRUE, scenario %in% c("jrl", "both"), scenario %in% c("crl", "both"))
  stations[[paste0("available_", scenario)]] <- available
  stations[[paste0("attraction_", scenario)]] <- ifelse(available, c(1, 2, 4, 6, 8), NA_real_)
}
distance <- matrix(c(1000, 2000, 4000, 100, 10000,
                     2000, 1000, 2000, 10000, 10000,
                     4000, 2000, 1000, 10000, 100), 3, byrow = TRUE,
                   dimnames = list(c("x", "y", "z"), c("A", "B", "C", "J", "R")))
public <- list(origins = origins, stations = stations, distance_m = distance)
# Exact hand-derived August totals from weights 4:2:1, 1:8:4, 1:8:64.
ridership <- list("2026-08" = c(A = 600, B = 1800, C = 6900),
                  "2026-09" = c(C = 13800, A = 1200, B = 3600))
study <- NULL
check("study retains actual fits and independent temporal validation", {
  study <<- run_huff_study(public, ridership)
  stopifnot(all(c("august", "september") %in% names(study$fits)),
            nrow(study$metrics) == 4L, nrow(study$start_diagnostics) == 18L)
  near(study$validation$predicted, c(1200, 3600, 13800))
  stopifnot(study$metrics$RMSE[study$metrics$stage == "validation" & study$metrics$model == "huff"] < 1e-3,
            study$metrics$RMSE[study$metrics$model == "equal_attraction_beta2"] > 100)
})
check("all four scenarios use identical populations, total, and fitted parameters", {
  stopifnot(identical(names(study$scenarios), c("existing", "jrl", "crl", "both")))
  near(study$population, c(x = 7, y = 13, z = 73))
  near(study$market, c(x = 1400, y = 2600, z = 14600))
  for (scenario in study$scenarios) {
    near(sum(scenario$predicted), 18600)
    near(rowSums(scenario$probabilities), c(x = 1, y = 1, z = 1))
    stopifnot(identical(scenario$catchments$origin_id, c("x", "y", "z")),
              identical(scenario$catchments$population, c(7, 13, 73)),
              !anyDuplicated(scenario$changes$station_id))
  }
})
check("unchanged existing scenario exactly reproduces fitted baseline", {
  baseline <- study$scenarios$existing
  near(baseline$predicted, study$fits$september$predicted, tolerance = 1e-12)
  near(baseline$changes$change, c(0, 0, 0), tolerance = 1e-12)
  near(baseline$switches$population_share, 0)
})
check("new competitors have no invented historical volume", {
  both <- study$scenarios$both$changes
  stopifnot(identical(both$station_id, c("A", "B", "C", "J", "R")),
            all(is.na(both$baseline[both$status == "new"])),
            all(is.na(both$percent_change[both$status == "new"])))
})
check("dominant catchment switches are weighted by residential population", {
  near(study$switches$switched_population, c(0, 7, 73, 80))
  near(study$switches$population_share, c(0, 7 / 93, 73 / 93, 80 / 93))
  stopifnot(identical(study$scenarios$both$catchments$dominant_station_id, c("J", "B", "R")))
})
check("100m versus 250m sensitivity preserves demand and uses fixed parameters", {
  sensitivity <- study$sensitivity$station_predictions
  stopifnot(setequal(sensitivity$min_distance_m, c(100, 250)),
            all(sensitivity$gamma == study$fits$september$gamma),
            all(sensitivity$beta == study$fits$september$beta))
  for (floor in c(100, 250)) for (scenario in names(study$scenarios)) {
    values <- sensitivity$predicted[sensitivity$min_distance_m == floor & sensitivity$scenario == scenario]
    near(sum(values), 18600)
  }
  stopifnot(any(abs(sensitivity$change_from_100m[sensitivity$min_distance_m == 250]) > 1))
})
check("shuffled named inputs produce the same ID-aligned results", {
  shuffled <- public
  shuffled$origins <- public$origins[c(3, 1, 2), ]
  shuffled$stations <- public$stations[c(5, 2, 4, 1, 3), ]
  shuffled$distance_m <- public$distance_m[c(2, 3, 1), c(4, 5, 3, 1, 2)]
  other <- run_huff_study(shuffled, lapply(ridership, rev))
  near(other$market, study$market)
  for (scenario in names(study$scenarios)) {
    near(other$scenarios[[scenario]]$predicted, study$scenarios[[scenario]]$predicted)
  }
})
check("incomplete rosters, duplicate physical stations, and corrupted inputs fail", {
  wrong <- ridership; wrong[[1]] <- wrong[[1]][-1]
  rejects(run_huff_study(public, wrong))
  wrong <- public; wrong$stations$station_id[2] <- "A"
  rejects(run_huff_study(wrong, ridership))
  wrong <- public; wrong$distance_m[1, 1] <- NA_real_
  rejects(run_huff_study(wrong, ridership))
  wrong <- public; wrong$origins$population[1] <- 0
  rejects(run_huff_study(wrong, ridership))
  wrong <- public; wrong$stations$attraction_both[1] <- NA_real_
  rejects(run_huff_study(wrong, ridership))
  wrong <- public; wrong$stations$available_jrl[1] <- FALSE
  rejects(run_huff_study(wrong, ridership))
})
check("source is inert and explicit entry point stops before writes if inputs are missing", {
  temp <- tempfile("huff-entry-"); dir.create(temp)
  dir.create(file.path(temp, "R"))
  file.copy(c(study_path, "R/model-core.R"), file.path(temp, "R"))
  old <- getwd()
  tryCatch({
    setwd(temp)
    source("R/03-model-scenarios.R", local = new.env())
    stopifnot(!dir.exists("output"))
    rscript <- file.path(R.home("bin"), "Rscript.exe")
    status <- suppressWarnings(system2(rscript, c("--vanilla", "R/03-model-scenarios.R"),
                                      stdout = "run.log", stderr = "run.log"))
    stopifnot(status != 0L, !dir.exists("output"), !dir.exists("data"),
              any(grepl("prepared", readLines("run.log"))))
  }, finally = { setwd(old); unlink(temp, recursive = TRUE) })
})
cat(sprintf("\n%d checks, %d failures\n", checks, length(failures)))
if (length(failures)) stop(paste(failures, collapse = "\n"), call. = FALSE)
