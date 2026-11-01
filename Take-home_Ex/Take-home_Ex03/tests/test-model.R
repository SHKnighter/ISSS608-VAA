# Standalone, dependency-free model contract checks. Run from the exercise folder.
model_path <- file.path("R", "model-core.R")
if (file.exists(model_path)) source(model_path)

failures <- character()
checks <- 0L
check <- function(label, code) {
  checks <<- checks + 1L
  tryCatch({ force(code); cat("PASS:", label, "\n") }, error = function(e) {
    failures <<- c(failures, paste(label, conditionMessage(e), sep = ": "))
    cat("FAIL:", label, "-", conditionMessage(e), "\n")
  })
}
near <- function(actual, expected, tolerance = 1e-10) {
  if (!isTRUE(all.equal(actual, expected, tolerance = tolerance))) {
    stop(paste("Expected", paste(expected, collapse = ","), "but got",
               paste(actual, collapse = ",")), call. = FALSE)
  }
}
rejects <- function(code) {
  err <- tryCatch({ force(code); NULL }, error = identity)
  if (is.null(err)) stop("Invalid input was accepted", call. = FALSE)
}
d <- matrix(c(100, 200, 200, 100), 2, byrow = TRUE,
            dimnames = list(c("north", "south"), c("A", "B")))
a <- c(A = 1, B = 1)

check("equal distance and attraction split demand equally", {
  p <- huff_probabilities(d * 0 + 100, a)
  near(unname(p), matrix(.5, 2, 2))
  stopifnot(identical(dimnames(p), dimnames(d)))
})
check("inverse-square distance gives a hand-calculated 80/20 split", {
  p <- huff_probabilities(d / 100, a, beta = 2, min_distance = 1)
  near(unname(p), matrix(c(.8, .2, .2, .8), 2, byrow = TRUE))
})
check("zero distance uses the stated 100m floor", {
  z <- d; z[1, 1] <- 0
  near(unname(huff_probabilities(z, a)[1, ]), c(.8, .2))
})
check("named market volumes conserve the literal network total", {
  p <- huff_probabilities(d, a)
  y <- station_predictions(p, c(south = 200, north = 100))
  near(y, c(A = 120, B = 180))
  near(sum(y), 300)
})
check("attraction and observation inputs align by ID, not position", {
  p <- huff_probabilities(d * 0 + 100, c(B = 3, A = 1))
  near(unname(p[1, ]), c(.25, .75))
  m <- evaluate_predictions(c(A = 100, B = 200), c(B = 180, A = 120))
  near(as.numeric(m[1, ]), c(20, 20, 40 / 300))
})
check("a new competitor enters every origin denominator", {
  base <- huff_probabilities(d * 0 + 100, a)
  expanded <- cbind(d * 0 + 100, C = c(100, 100))
  p <- huff_probabilities(expanded, c(A = 1, B = 1, C = 2))
  near(unname(p), matrix(c(.25, .25, .5), 2, 3, byrow = TRUE))
  stopifnot(all(p[, c("A", "B")] < base))
})
check("unchanged fixed parameters reproduce baseline predictions", {
  before <- station_predictions(huff_probabilities(d, a), c(north = 100, south = 200))
  after <- station_predictions(huff_probabilities(d, a), c(north = 100, south = 200))
  result <- scenario_changes(before, after)
  near(result$change, c(0, 0)); near(result$percent_change, c(0, 0))
  stopifnot(all(result$status == "existing"))
})
check("new stations have no invented prior baseline", {
  result <- scenario_changes(c(A = 0, B = 100), c(C = 50, B = 90, A = 10))
  stopifnot(identical(result$station_id, c("C", "B", "A")),
            identical(result$status, c("new", "existing", "existing")),
            is.na(result$baseline[1]), is.na(result$change[1]),
            is.na(result$percent_change[1]), is.na(result$percent_change[3]))
  near(result$baseline[-1], c(100, 0))
  near(result$change[-1], c(-10, 10)); near(result$percent_change[2], -10)
})
check("log-space computation remains finite over extreme distances", {
  extreme <- matrix(c(1e-300, 1e300, 1e300, 1e-300), 2,
                    dimnames = dimnames(d))
  p <- huff_probabilities(extreme, c(A = 1e300, B = 1e-300),
                          gamma = 3, beta = 6, min_distance = 1e-300)
  stopifnot(all(is.finite(p)))
  near(rowSums(p), c(north = 1, south = 1))
  near(unname(p), diag(2))
})
check("calibration improves an independent known-parameter fixture", {
  # At gamma=1,beta=2 these rows have weights 4:2:1, 1:8:4, 1:8:64.
  # Markets 700,1300,7300 therefore give station totals 600,1800,6900.
  distance <- matrix(c(1000, 2000, 4000, 2000, 1000, 2000,
                       4000, 2000, 1000), 3, byrow = TRUE,
                     dimnames = list(c("x", "y", "z"), c("A", "B", "C")))
  attraction <- c(A = 1, B = 2, C = 4)
  observed <- c(C = 6900, A = 600, B = 1800)
  fit <- fit_huff(distance, attraction, c(z = 73, x = 7, y = 13), observed)
  stopifnot(all(c("gamma", "beta", "objective", "convergence", "start_diagnostics",
                  "probabilities", "predicted", "metrics") %in% names(fit)),
            fit$convergence == 0L, nrow(fit$start_diagnostics) == 9L,
            fit$gamma >= 0, fit$gamma <= 3, fit$beta >= .5, fit$beta <= 6,
            fit$objective < 1e-12)
  near(fit$predicted, c(A = 600, B = 1800, C = 6900), tolerance = 1e-5)
  initial <- station_predictions(huff_probabilities(distance, attraction, .5, 1),
                                 c(x = 700, y = 1300, z = 7300))
  stopifnot(fit$metrics$RMSE < evaluate_predictions(observed, initial)$RMSE)
})
check("zero observations are valid when network total is positive", {
  near(as.numeric(evaluate_predictions(c(A = 0, B = 100), c(A = 10, B = 90))),
       c(10, 10, .2))
})
check("missing, duplicated, and mismatched station IDs fail", {
  rejects(huff_probabilities(d, c(1, 1)))
  rejects(huff_probabilities(d, c(A = 1, C = 1)))
  rejects(huff_probabilities(d, c(A = 1, A = 1)))
  bad <- d; colnames(bad) <- c("A", "A")
  rejects(huff_probabilities(bad, a))
  bad <- d; rownames(bad) <- NULL
  rejects(huff_probabilities(bad, a))
  rejects(station_predictions(huff_probabilities(d, a), c(north = 100, other = 200)))
  rejects(evaluate_predictions(c(A = 1, B = 2), c(A = 1, C = 2)))
  rejects(scenario_changes(c(A = 1, B = 2), c(A = 1)))
})
check("corrupted, empty, negative, and non-finite model inputs fail", {
  for (v in c(-1, NA_real_, Inf, NaN)) {
    bad <- d; bad[1, 1] <- v
    rejects(huff_probabilities(bad, a))
    rejects(huff_probabilities(d, c(A = v, B = 1)))
    rejects(station_predictions(huff_probabilities(d, a), c(north = v, south = 2)))
    rejects(evaluate_predictions(c(A = v, B = 2), c(A = 1, B = 2)))
    rejects(evaluate_predictions(c(A = 1, B = 2), c(A = v, B = 2)))
    rejects(scenario_changes(c(A = 1), c(A = v)))
  }
  rejects(huff_probabilities(matrix(numeric(), 0, 0), numeric()))
  rejects(huff_probabilities(d, c(A = 0, B = 1)))
  rejects(station_predictions(huff_probabilities(d, a), c(north = 0, south = 0)))
  rejects(evaluate_predictions(c(A = 0, B = 0), c(A = 1, B = 2)))
  rejects(evaluate_predictions(numeric(), numeric()))
  rejects(scenario_changes(numeric(), c(A = 1)))
})
check("invalid parameters and non-probability rows fail", {
  for (v in c(-1, NA_real_, Inf)) rejects(huff_probabilities(d, a, gamma = v))
  for (v in c(-1, 0, NA_real_, Inf)) {
    rejects(huff_probabilities(d, a, beta = v))
    rejects(huff_probabilities(d, a, min_distance = v))
  }
  rejects(huff_probabilities(d, a, gamma = c(1, 2)))
  rejects(station_predictions(d, c(north = 1, south = 2)))
  bad <- d * 0 + .5; bad[1, 1] <- NA_real_
  rejects(station_predictions(bad, c(north = 1, south = 2)))
})
check("fit rejects invalid populations, observations, and start bounds", {
  rejects(fit_huff(d, a, c(north = 0, south = 0), c(A = 1, B = 2)))
  rejects(fit_huff(d, a, c(north = NA, south = 1), c(A = 1, B = 2)))
  rejects(fit_huff(d, a, c(north = 1, south = 1), c(A = 0, B = 0)))
  rejects(fit_huff(d, a, c(north = 1, south = 1), c(A = 1, B = 2),
                   starts = data.frame(gamma = 4, beta = 2)))
  rejects(fit_huff(d, a, c(north = 1, south = 1), c(A = 1, B = 2),
                   starts = data.frame(gamma = numeric(), beta = numeric())))
})

cat(sprintf("\n%d checks, %d failures\n", checks, length(failures)))
if (length(failures)) stop(paste(failures, collapse = "\n"), call. = FALSE)
