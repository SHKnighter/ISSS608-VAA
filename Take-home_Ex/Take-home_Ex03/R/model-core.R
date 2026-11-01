# Pure, dependency-free Huff model. IDs are required at every numeric boundary.
.model_ids <- function(ids, size, label) {
  if (is.null(ids) || length(ids) != size || anyNA(ids) ||
      any(!nzchar(trimws(ids))) || anyDuplicated(ids)) {
    stop(label, " must have complete, nonempty, unique IDs.", call. = FALSE)
  }
  invisible(ids)
}

.model_matrix <- function(x, label) {
  if (!is.matrix(x) || !is.numeric(x) || any(dim(x) == 0L) ||
      any(!is.finite(x)) || any(x < 0)) {
    stop(label, " must be a nonempty, finite, nonnegative numeric matrix.",
         call. = FALSE)
  }
  .model_ids(rownames(x), nrow(x), paste(label, "rows"))
  .model_ids(colnames(x), ncol(x), paste(label, "columns"))
  invisible(x)
}

.model_vector <- function(x, label, ids = NULL, positive = FALSE,
                          positive_total = FALSE) {
  if (!is.numeric(x) || !is.null(dim(x)) || !length(x) ||
      any(!is.finite(x)) || any(x < 0) || (positive && any(x <= 0))) {
    stop(label, " must be a nonempty, finite ",
         if (positive) "positive" else "nonnegative", " numeric vector.",
         call. = FALSE)
  }
  .model_ids(names(x), length(x), label)
  if (!is.null(ids)) {
    if (length(x) != length(ids) || !setequal(names(x), ids)) {
      stop(label, " IDs must match the model IDs exactly.", call. = FALSE)
    }
    x <- x[ids]
  }
  if (!is.finite(sum(x)) || (positive_total && sum(x) <= 0)) {
    stop(label, " must have a finite",
         if (positive_total) " positive" else "", " total.", call. = FALSE)
  }
  x
}

.model_scalar <- function(x, label, strictly_positive = FALSE) {
  if (!is.numeric(x) || length(x) != 1L || !is.finite(x) ||
      x < 0 || (strictly_positive && x <= 0)) {
    stop(label, " must be a finite ",
         if (strictly_positive) "positive" else "nonnegative", " scalar.",
         call. = FALSE)
  }
  invisible(x)
}

.huff_from_logs <- function(log_distance, log_attraction, gamma, beta) {
  # Scale before subtraction so even very large finite exponents cannot overflow
  # log weights. Center each row before exponentiation (log-softmax).
  scale <- max(gamma, beta)
  scores <- sweep(-(beta / scale) * log_distance, 2L,
                  (gamma / scale) * log_attraction, "+")
  scores <- sweep(scores, 1L, apply(scores, 1L, max), "-")
  weights <- exp(scores * scale)
  sweep(weights, 1L, rowSums(weights), "/")
}

# P_ij = A_j^gamma d_ij^-beta / sum_j(A_j^gamma d_ij^-beta).
# Distances and min_distance must use the same unit (metres in this exercise).
huff_probabilities <- function(distance_matrix, attraction, gamma = 1, beta = 2,
                               min_distance = 100) {
  .model_matrix(distance_matrix, "distance_matrix")
  attraction <- .model_vector(attraction, "attraction", colnames(distance_matrix),
                              positive = TRUE)
  .model_scalar(gamma, "gamma")
  .model_scalar(beta, "beta", strictly_positive = TRUE)
  .model_scalar(min_distance, "min_distance", strictly_positive = TRUE)
  .huff_from_logs(log(pmax(distance_matrix, min_distance)), log(attraction),
                  gamma, beta)
}

# Allocate origin markets; no observed station volumes enter these features.
station_predictions <- function(probabilities, market) {
  .model_matrix(probabilities, "probabilities")
  if (any(probabilities > 1) || any(abs(rowSums(probabilities) - 1) > 1e-8)) {
    stop("Each probability row must sum to one.", call. = FALSE)
  }
  market <- .model_vector(market, "market", rownames(probabilities),
                          positive_total = TRUE)
  colSums(sweep(probabilities, 1L, market, "*"))
}

# WAPE is a ratio, e.g. 0.20 means 20%; individual zero observations are valid.
evaluate_predictions <- function(observed, predicted) {
  observed <- .model_vector(observed, "observed", positive_total = TRUE)
  predicted <- .model_vector(predicted, "predicted", names(observed))
  error <- predicted - observed
  # Scaling avoids overflow when squaring large, finite residuals.
  largest <- max(abs(error))
  rmse <- if (largest == 0) 0 else largest * sqrt(mean((error / largest)^2))
  data.frame(MAE = mean(abs(error)), RMSE = rmse,
             WAPE = sum(abs(error) / sum(observed)))
}

# Calibrate two shared parameters to station shares. This is an in-sample fit;
# forecast validation must use an independent period or holdout elsewhere.
fit_huff <- function(distance_matrix, attraction, population, observed,
                     starts = expand.grid(gamma = c(.5, 1, 2),
                                          beta = c(1, 2, 4))) {
  .model_matrix(distance_matrix, "distance_matrix")
  attraction <- .model_vector(attraction, "attraction", colnames(distance_matrix),
                              positive = TRUE)
  population <- .model_vector(population, "population", rownames(distance_matrix),
                              positive_total = TRUE)
  observed <- .model_vector(observed, "observed", colnames(distance_matrix),
                            positive_total = TRUE)
  if (!is.data.frame(starts) || !all(c("gamma", "beta") %in% names(starts)) ||
      !nrow(starts) || !is.numeric(starts$gamma) || !is.numeric(starts$beta) ||
      any(!is.finite(starts$gamma)) || any(!is.finite(starts$beta)) ||
      any(starts$gamma < 0 | starts$gamma > 3) ||
      any(starts$beta < .5 | starts$beta > 6)) {
    stop("starts must contain finite gamma in [0,3] and beta in [0.5,6].",
         call. = FALSE)
  }
  log_distance <- log(pmax(distance_matrix, 100))
  log_attraction <- log(attraction)
  population_share <- population / sum(population)
  observed_share <- observed / sum(observed)
  objective <- function(par) {
    p <- .huff_from_logs(log_distance, log_attraction, par[1L], par[2L])
    share <- colSums(sweep(p, 1L, population_share, "*"))
    sum((share - observed_share)^2)
  }
  fits <- lapply(seq_len(nrow(starts)), function(i) {
    tryCatch(stats::optim(c(gamma = starts$gamma[i], beta = starts$beta[i]),
                          objective, method = "L-BFGS-B", lower = c(0, .5),
                          upper = c(3, 6),
                          control = list(maxit = 1000, factr = 1e5, pgtol = 1e-10)),
             error = function(e) list(par = c(gamma = NA_real_, beta = NA_real_),
                                      value = Inf, convergence = 99L,
                                      message = conditionMessage(e)))
  })
  diagnostics <- do.call(rbind, lapply(seq_along(fits), function(i) {
    f <- fits[[i]]
    data.frame(start_id = i, start_gamma = starts$gamma[i],
               start_beta = starts$beta[i], gamma = unname(f$par[1L]),
               beta = unname(f$par[2L]), objective = f$value,
               convergence = f$convergence,
               message = if (is.null(f$message)) "" else f$message)
  }))
  candidates <- which(is.finite(diagnostics$objective) & diagnostics$convergence == 0L)
  if (!length(candidates)) {
    stop("No calibration start converged; inspect inputs or starting values.",
         call. = FALSE)
  }
  best_id <- candidates[which.min(diagnostics$objective[candidates])]
  best <- fits[[best_id]]
  gamma <- unname(best$par[1L]); beta <- unname(best$par[2L])
  probabilities <- .huff_from_logs(log_distance, log_attraction, gamma, beta)
  market <- sum(observed) * population_share
  predicted <- station_predictions(probabilities, market)
  list(gamma = gamma, beta = beta, objective = best$value,
       convergence = best$convergence, start_diagnostics = diagnostics,
       probabilities = probabilities, predicted = predicted,
       metrics = evaluate_predictions(observed, predicted))
}

# Scenario must include every baseline station; additions are allowed. No zero
# baseline is invented for a new station. percent_change is in percentage units.
scenario_changes <- function(baseline_named, scenario_named) {
  baseline_named <- .model_vector(baseline_named, "baseline_named")
  scenario_named <- .model_vector(scenario_named, "scenario_named")
  if (!all(names(baseline_named) %in% names(scenario_named))) {
    stop("scenario_named must include every baseline station ID.", call. = FALSE)
  }
  station_id <- names(scenario_named)
  baseline <- unname(baseline_named[station_id])
  predicted <- unname(scenario_named)
  existing <- station_id %in% names(baseline_named)
  change <- predicted - baseline
  percent_change <- rep(NA_real_, length(station_id))
  positive <- existing & baseline > 0
  percent_change[positive] <- 100 * (change[positive] / baseline[positive])
  data.frame(station_id = station_id, baseline = baseline, predicted = predicted,
             change = change, percent_change = percent_change,
             status = ifelse(existing, "existing", "new"), stringsAsFactors = FALSE)
}
