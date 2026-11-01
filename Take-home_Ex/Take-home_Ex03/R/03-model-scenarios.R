# Run explicitly from the exercise directory. source() only defines functions.
source("R/model-core.R", local = TRUE)

.study_inputs <- function(public, ridership) {
  if (!is.list(public) || !all(c("origins", "stations", "distance_m") %in% names(public)) ||
      !inherits(public$origins, "sf") || !inherits(public$stations, "sf")) {
    stop("public must contain prepared sf origins/stations and distance_m.")
  }
  origins <- public$origins; stations <- public$stations
  if (!all(c("origin_id", "population") %in% names(origins)) ||
      !all(c("station_id", "station_name") %in% names(stations))) stop("Missing prepared ID/population columns.")
  .model_ids(origins$origin_id, nrow(origins), "origin_id")
  .model_ids(stations$station_id, nrow(stations), "station_id")
  if (anyNA(stations$station_name) || any(!nzchar(trimws(stations$station_name)))) stop("Missing station names.")
  .model_matrix(public$distance_m, "distance_m")
  if (!setequal(rownames(public$distance_m), origins$origin_id) ||
      !setequal(colnames(public$distance_m), stations$station_id)) stop("Distance IDs differ from prepared spatial IDs.")
  origins <- origins[order(origins$origin_id), ]
  stations <- stations[order(stations$station_id), ]
  distance <- public$distance_m[origins$origin_id, stations$station_id, drop = FALSE]
  population <- .model_vector(setNames(origins$population, origins$origin_id),
                              "population", positive = TRUE, positive_total = TRUE)
  scenarios <- c("existing", "jrl", "crl", "both")
  for (scenario in scenarios) {
    available_col <- paste0("available_", scenario)
    attraction_col <- paste0("attraction_", scenario)
    if (!all(c(available_col, attraction_col) %in% names(stations))) stop("Missing scenario availability/attraction columns.")
    available <- stations[[available_col]]; attraction <- stations[[attraction_col]]
    if (!is.logical(available) || anyNA(available) || !any(available) ||
        !is.numeric(attraction) || any(!is.finite(attraction[available])) ||
        any(attraction[available] <= 0) || any(!is.na(attraction[!available]))) {
      stop("Invalid scenario availability or attraction.")
    }
    if (scenario != "existing" && any(stations$available_existing & !available)) {
      stop("Each scenario must retain all existing physical stations.")
    }
  }
  if (any(stations$available_both != (stations$available_jrl | stations$available_crl))) {
    stop("Combined scenario must use the union of JRL and CRL station availability.")
  }
  if (!is.list(ridership) || anyDuplicated(names(ridership)) ||
      !setequal(names(ridership), c("2026-08", "2026-09"))) stop("Both prepared August and September observations are required.")
  existing_ids <- stations$station_id[stations$available_existing]
  observed <- lapply(ridership[c("2026-08", "2026-09")], function(x) {
    .model_vector(x, "monthly observed", existing_ids, positive_total = TRUE)
  })
  list(origins = origins, stations = stations, distance = distance,
       population = population, observed = observed, scenarios = scenarios)
}

.study_catchments <- function(probabilities, population, baseline, scenario) {
  # Columns are sorted by ID, so ties have a reproducible first-ID winner.
  winner <- max.col(probabilities, ties.method = "first")
  dominant <- colnames(probabilities)[winner]
  switched <- dominant != baseline
  catchments <- data.frame(scenario = scenario, origin_id = rownames(probabilities),
                           population = unname(population), baseline_station_id = baseline,
                           dominant_station_id = dominant,
                           dominant_probability = probabilities[cbind(seq_len(nrow(probabilities)), winner)],
                           switched = switched, stringsAsFactors = FALSE)
  switches <- data.frame(scenario = scenario, switched_origins = sum(switched),
                          switched_population = sum(population[switched]),
                          population_total = sum(population),
                          population_share = sum(population[switched]) / sum(population))
  list(catchments = catchments, switches = switches)
}

run_huff_study <- function(public, ridership) {
  input <- .study_inputs(public, ridership) # Complete validation precedes all fitting.
  stations <- input$stations; population <- input$population
  existing <- stations$available_existing
  distance <- input$distance[, existing, drop = FALSE]
  attraction <- setNames(stations$attraction_existing[existing], stations$station_id[existing])
  august <- fit_huff(distance, attraction, population, input$observed[["2026-08"]])
  total <- sum(input$observed[["2026-09"]])
  market <- total * (population / sum(population))
  validation_p <- huff_probabilities(distance, attraction, august$gamma, august$beta)
  validation_predicted <- station_predictions(validation_p, market)
  reference_p <- huff_probabilities(distance, setNames(rep(1, ncol(distance)), colnames(distance)), gamma = 0, beta = 2)
  reference_predicted <- station_predictions(reference_p, market)
  september <- fit_huff(distance, attraction, population, input$observed[["2026-09"]])
  metric_row <- function(stage, model, training, evaluation, values) {
    cbind(data.frame(stage = stage, model = model, training_month = training,
                      evaluation_month = evaluation, stringsAsFactors = FALSE), values)
  }
  metrics <- rbind(
    metric_row("calibration", "huff", "2026-08", "2026-08", august$metrics),
    metric_row("validation", "huff", "2026-08", "2026-09",
               evaluate_predictions(input$observed[["2026-09"]], validation_predicted)),
    metric_row("validation", "equal_attraction_beta2", NA_character_, "2026-09",
               evaluate_predictions(input$observed[["2026-09"]], reference_predicted)),
    metric_row("final_fit", "huff", "2026-09", "2026-09", september$metrics))
  validation <- data.frame(station_id = colnames(distance),
                            observed = unname(input$observed[["2026-09"]]),
                            predicted = unname(validation_predicted),
                            reference = unname(reference_predicted), stringsAsFactors = FALSE)
  probability <- function(scenario, floor) {
    available <- stations[[paste0("available_", scenario)]]
    a <- setNames(stations[[paste0("attraction_", scenario)]][available], stations$station_id[available])
    huff_probabilities(input$distance[, available, drop = FALSE], a,
                       september$gamma, september$beta, min_distance = floor)
  }
  scenarios <- setNames(vector("list", length(input$scenarios)), input$scenarios)
  baseline_p <- probability("existing", 100)
  baseline <- colnames(baseline_p)[max.col(baseline_p, ties.method = "first")]
  for (scenario in input$scenarios) {
    p <- probability(scenario, 100)
    predicted <- station_predictions(p, market)
    catchment <- .study_catchments(p, population, baseline, scenario)
    scenarios[[scenario]] <- c(list(probabilities = p, predicted = predicted,
                                    changes = scenario_changes(september$predicted, predicted)), catchment)
  }
  sensitivity_predictions <- list(); sensitivity_switches <- list(); counter <- 0L
  for (floor in c(100, 250)) {
    baseline_floor <- probability("existing", floor)
    baseline_winner <- colnames(baseline_floor)[max.col(baseline_floor, ties.method = "first")]
    for (scenario in input$scenarios) {
      counter <- counter + 1L
      p <- probability(scenario, floor)
      predicted <- station_predictions(p, market)
      comparison <- scenario_changes(scenarios[[scenario]]$predicted, predicted)
      sensitivity_predictions[[counter]] <- data.frame(
        scenario = scenario, min_distance_m = floor, gamma = september$gamma, beta = september$beta,
        station_id = comparison$station_id, predicted = comparison$predicted,
        change_from_100m = comparison$change, percent_change_from_100m = comparison$percent_change)
      switching <- .study_catchments(p, population, baseline_winner, scenario)$switches
      sensitivity_switches[[counter]] <- cbind(min_distance_m = floor, switching)
    }
  }
  start_diagnostics <- rbind(cbind(month = "2026-08", august$start_diagnostics),
                              cbind(month = "2026-09", september$start_diagnostics))
  list(fits = list(august = august, september = september), metrics = metrics,
       validation = validation, scenarios = scenarios,
       catchments = do.call(rbind, lapply(scenarios, `[[`, "catchments")),
       switches = do.call(rbind, lapply(scenarios, `[[`, "switches")),
       sensitivity = list(station_predictions = do.call(rbind, sensitivity_predictions),
                           switches = do.call(rbind, sensitivity_switches)),
       population = population, market = market, start_diagnostics = start_diagnostics)
}

# Explicit script entry point only. Missing real observations cannot produce a fit.
if (sys.nframe() == 0L) {
  required <- file.path("data", "processed", c("public-prepared.rds", "ridership-prepared.rds"))
  if (!all(file.exists(required))) {
    stop("Missing prepared public/ridership RDS inputs. Complete preparation first; no model outputs were written.")
  }
  source('R/cache-guard.R')
  public <- readRDS(required[1]); ridership <- readRDS(required[2])
  verify_prepared_ridership(public); verify_prepared_ridership(ridership)
  study <- run_huff_study(public, ridership)
  attr(study,'input_fingerprint') <- fingerprint_files(c(required,'R/model-core.R',
    'R/03-model-scenarios.R','R/cache-guard.R'))
  # No directory or result file is created until validation and the study succeed.
  dir.create("output/tables", recursive = TRUE, showWarnings = FALSE)
  saveRDS(study, "output/huff-study.rds")
  write_table <- function(x, name) write.csv(x, file.path("output", "tables", paste0(name, ".csv")), row.names = FALSE, na = "")
  write_table(study$metrics, "model-metrics")
  write_table(study$validation, "model-validation")
  write_table(study$start_diagnostics, "model-start-diagnostics")
  write_table(do.call(rbind, lapply(names(study$fits), function(month) {
    fit <- study$fits[[month]]
    data.frame(fit = month, gamma = fit$gamma, beta = fit$beta,
                objective = fit$objective, convergence = fit$convergence)
  })), "model-parameters")
  changes <- do.call(rbind, lapply(names(study$scenarios), function(scenario) {
    cbind(scenario = scenario, study$scenarios[[scenario]]$changes)
  }))
  write_table(changes, "scenario-station-changes")
  write_table(study$catchments, "scenario-catchments")
  write_table(study$switches, "scenario-switches")
  write_table(study$sensitivity$station_predictions, "sensitivity-station-predictions")
  write_table(study$sensitivity$switches, "sensitivity-switches")
  cat("Observed-data Huff study saved to output/huff-study.rds and output/tables.\n")
}
