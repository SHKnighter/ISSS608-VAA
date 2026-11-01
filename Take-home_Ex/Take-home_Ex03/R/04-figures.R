# Reproducible figures for the approved R/Quarto report and revealjs slides.
# Run from Take-home_Ex03: Rscript --vanilla R/04-figures.R
# Uses saved real-data results only; this script never fits or reruns the model.
Sys.setenv(LC_ALL = "C")
suppressPackageStartupMessages({
  library(ggplot2)
  library(sf)
  library(patchwork)
  library(ggrepel)
})
required <- c("data/processed/public-prepared.rds", "output/huff-study.rds")
if (!all(file.exists(required))) stop("Prepared spatial data and saved model study are required.")
public <- readRDS(required[1])
study <- readRDS(required[2])
dir.create("output/figures", recursive = TRUE, showWarnings = FALSE)
dir.create("output/tables", recursive = TRUE, showWarnings = FALSE)
dir.create("_workflow", recursive = TRUE, showWarnings = FALSE)

blue <- "#2166A5"
orange <- "#CE702D"
ink <- "#263745"
muted <- "#65727D"
neutral <- "#EBEEF0"
subzones <- public$subzones
stations <- public$stations
station_names <- setNames(stations$station_name, stations$station_id)
proposal <- public$crosswalk[!public$crosswalk$baseline_reference, ]
proposal <- proposal[!duplicated(proposal$station_id), ]
proposal_points <- stations[match(proposal$station_id, stations$station_id), ]
proposal_points$line <- proposal$proposal_line
proposal_points$line <- factor(proposal_points$line, levels = c("JRL", "CRL"))
existing <- stations[stations$available_existing, ]
new_ids <- stations$station_id[!stations$available_existing]
study_bbox <- st_bbox(subzones)
map_xlim <- unname(study_bbox[c("xmin", "xmax")])
map_ylim <- unname(study_bbox[c("ymin", "ymax")])
format_k <- function(x) paste0(format(round(x / 1000), trim = TRUE, big.mark = ","), "k")
format_n <- function(x) format(round(x), trim = TRUE, big.mark = ",", scientific = FALSE)
format_short <- function(x) ifelse(abs(x) < 1000, format_n(x),
                                    ifelse(abs(x) < 10000, sprintf("%.1fk", x / 1000), format_k(x)))
format_signed <- function(x) ifelse(x > 0, paste0("+", round(x), "%"), paste0(round(x), "%"))
theme_course <- function(base_size = 13) {
  theme_minimal(base_size = base_size, base_family = "Arial") +
    theme(plot.title = element_text(size = 20, face = "bold", color = ink, margin = margin(b = 7)),
          plot.subtitle = element_text(size = 12.5, color = muted, margin = margin(b = 12)),
          plot.caption = element_text(size = 10.5, hjust = 0, color = muted, lineheight = 1.12,
                                      margin = margin(t = 10)),
          plot.title.position = "plot", plot.caption.position = "plot",
          legend.title = element_text(size = 11), legend.text = element_text(size = 10.5),
          legend.position = "right", legend.key.height = grid::unit(0.55, "cm"),
          axis.title = element_text(size = 12), axis.text = element_text(size = 11, color = ink),
          panel.grid.minor = element_blank(), panel.grid.major = element_line(color = "#E5E9EC", linewidth = 0.3),
          strip.text = element_text(face = "bold", color = ink, size = 12),
          plot.margin = margin(16, 22, 14, 16))
}
theme_set(theme_course())
theme_map <- function() theme(axis.text = element_blank(), axis.ticks = element_blank(),
                              axis.title = element_blank(), panel.grid = element_blank())
map_frame <- function() coord_sf(crs = st_crs(3414), xlim = map_xlim, ylim = map_ylim, expand = FALSE, datum = NA)
map_base <- function() ggplot() + geom_sf(data = subzones, fill = "#F3F4F5", color = "#D9DFE3", linewidth = 0.16)
point_xy <- function(x) {
  out <- st_drop_geometry(x)
  xy <- st_coordinates(x)
  out$x <- xy[, 1]; out$y <- xy[, 2]
  out
}
label_points <- function(x, label_col = "station_name", size = 3.25) {
  geom_label_repel(data = point_xy(x), aes(x = x, y = y, label = .data[[label_col]]),
                   inherit.aes = FALSE, seed = 608, family = "Arial", size = size,
                   color = ink, fill = "white", label.size = 0.12,
                   box.padding = 0.4, point.padding = 0.3, min.segment.length = 0,
                   max.overlaps = Inf, segment.color = "#7A8790")
}
manifest <- list()
save_figure <- function(plot, stem, rows, width = 12.8, height = 7.2, caption) {
  path <- file.path("output/figures", paste0(stem, ".png"))
  ggsave(path, plot = plot, width = width, height = height, units = "in", dpi = 170,
         bg = "white", limitsize = FALSE)
  if (inherits(rows, "sf")) rows <- st_drop_geometry(rows)
  write.csv(rows, file.path("output/tables", paste0("figure-", stem, ".csv")), row.names = FALSE, na = "")
  manifest[[stem]] <<- list(file = path, width_in = width, height_in = height,
                            dpi = 170, width_px = as.integer(width * 170),
                            height_px = as.integer(height * 170), caption = caption)
  message("Saved ", path)
}

# 01: actual planning subzones and physical station locations, no schematic lines.
pop_plot <- subzones
pop_plot$population_plot <- ifelse(pop_plot$population > 0, pop_plot$population, NA_real_)
p01 <- ggplot() +
  geom_sf(data = pop_plot, aes(fill = population_plot), color = "#D7DDE1", linewidth = 0.12) +
  scale_fill_gradient(low = "#F0F2F4", high = "#8C9FAF", na.value = "#FFFFFF",
                      labels = format_k, name = "Residents\n(June 2025)") +
  geom_sf(data = existing, aes(shape = "Existing physical stations (184)"),
          size = 1.7, color = "#53616A", fill = "white", stroke = 0.5) +
  geom_sf(data = proposal_points, aes(color = line), shape = 4, size = 3.1, stroke = 1.15) +
  scale_shape_manual(values = c("Existing physical stations (184)" = 21), name = NULL) +
  scale_color_manual(values = c(JRL = orange, CRL = blue), name = "Target line-stations",
                      labels = c("JRL (24)", "CRL1 (12)"), drop = FALSE) +
  map_frame() + theme_map() +
  labs(title = "Study area and rail expansion scope",
       subtitle = "332 MP2019 subzones | 4,212,800 residents as a rounded demand proxy | station points in SVY21 (EPSG:3414)",
       caption = "Sources: URA MP2019 boundaries; SingStat June 2025 residents; LTA Sep 2026 station footprints; linked station coordinates.\n36 target line-stations merge into 29 new physical stations and 7 existing interchanges. Crosses mark station points, not rail alignments.")
save_figure(p01, "01-study-area", st_drop_geometry(subzones)[, c("origin_id", "SUBZONE_N", "population")],
            caption = "Population context and actual station points. The 36 JRL/CRL1 line-stations add 29 physical stations after existing interchanges are merged.")

# 02: September target is the direct PV monthly entry series.
observed <- existing
observed$observed <- study$validation$observed[match(observed$station_id, study$validation$station_id)]
largest_observed <- observed[order(observed$observed, decreasing = TRUE)[1:5], ]
p02 <- map_base() +
  geom_sf(data = observed, aes(size = observed), shape = 21, fill = blue,
          color = "white", stroke = 0.35, alpha = 0.82) +
  scale_size_area(max_size = 12, breaks = c(50000, 150000, 300000, 450000), labels = format_k,
                   name = "Monthly entries") + label_points(largest_observed) +
  map_frame() + theme_map() +
  labs(title = "Observed weekday morning station entries",
       subtitle = "September 2026 | 06:00-09:59 | 184 physical MRT/LRT station units | network total 19,116,754 entries",
       caption = "Source: LTA DataMall PV/Train, September 2026, WEEKDAY, 06:00-09:59. Values are monthly totals, not entries per day.\nPhysical interchanges are combined; Stevens published units are merged. Labels identify the five largest observed station totals.")
save_figure(p02, "02-observed", observed[, c("station_id", "station_name", "observed")],
            caption = "Direct September PV observations show a strongly uneven distribution of weekday morning entries across 184 physical station units.")

# 03: conditional validation is always the August fit evaluated against September.
validation <- study$validation
validation$station_name <- unname(station_names[validation$station_id])
validation$residual <- validation$predicted - validation$observed
scatter_limit <- ceiling(max(validation$predicted, validation$observed) / 100000) * 100000
p03a <- ggplot(validation, aes(observed, predicted)) +
  geom_abline(slope = 1, intercept = 0, color = "#6A737A", linewidth = 0.65, linetype = "dashed") +
  geom_point(color = blue, alpha = 0.72, size = 2.5) +
  scale_x_continuous(labels = format_k, limits = c(0, scatter_limit), expand = expansion(mult = c(0.02, 0.03))) +
  scale_y_continuous(labels = format_k, limits = c(0, scatter_limit), expand = expansion(mult = c(0.02, 0.03))) +
  coord_equal() + labs(title = "Station comparison", x = "Observed September entries", y = "Predicted September entries") +
  theme(plot.title = element_text(size = 15), plot.margin = margin(5, 8, 5, 5))
validation_metrics <- study$metrics[study$metrics$stage == "validation", ]
metric_plot <- rbind(
  data.frame(model = validation_metrics$model, metric = "WAPE (%)", value = validation_metrics$WAPE * 100,
             label = sprintf("%.1f%%", validation_metrics$WAPE * 100)),
  data.frame(model = validation_metrics$model, metric = "MAE (monthly entries)", value = validation_metrics$MAE,
             label = format_n(validation_metrics$MAE)))
metric_plot$model <- factor(metric_plot$model, levels = c("equal_attraction_beta2", "huff"),
                            labels = c("Equal attraction\nbeta = 2", "Fitted Huff"))
metric_plot$metric <- factor(metric_plot$metric, levels = c("WAPE (%)", "MAE (monthly entries)"))
p03b <- ggplot(metric_plot, aes(value, model, fill = model)) +
  geom_col(width = 0.55) + geom_text(aes(label = label), hjust = -0.12, family = "Arial", size = 4.0, color = ink) +
  scale_fill_manual(values = c("Equal attraction\nbeta = 2" = "#A8B2BA", "Fitted Huff" = blue), guide = "none") +
  scale_x_continuous(labels = function(x) ifelse(x >= 1000, format_k(x), x), expand = expansion(mult = c(0, 0.35))) +
  facet_wrap(~metric, ncol = 1, scales = "free_x") +
  labs(title = "Error against the same observations", x = NULL, y = NULL) +
  theme(plot.title = element_text(size = 15), panel.grid.major.y = element_blank(),
         strip.text = element_text(hjust = 0), plot.margin = margin(5, 5, 5, 12))
p03 <- p03a + p03b + plot_layout(widths = c(1.35, 1)) +
  plot_annotation(title = "August fit improves September allocation, with substantial error remaining",
                  subtitle = "Conditional validation: August 2026 parameters + known September network total | 184 stations | dashed line: predicted = observed",
                  caption = "Source: saved Huff study and direct LTA PV observations, weekday 06:00-09:59. WAPE = sum absolute station errors / total observed entries.\nHuff WAPE 49.56% versus 61.66% for equal-attraction inverse-square distance. This is not an independent forecast of total demand.",
                  theme = theme_course())
save_figure(p03, "03-validation", validation,
            caption = "The August-fitted Huff allocation lowers September WAPE from 61.66% to 49.56%, but large station-level residuals remain. The network total is supplied from September observations.")

# 04: signed residuals use exactly the same conditional validation as Figure 03.
residual <- existing
residual$residual <- validation$residual[match(residual$station_id, validation$station_id)]
residual$observed <- validation$observed[match(residual$station_id, validation$station_id)]
residual$predicted <- validation$predicted[match(residual$station_id, validation$station_id)]
residual$abs_residual <- abs(residual$residual)
resid_limit <- ceiling(max(residual$abs_residual) / 100000) * 100000
largest_residual <- residual[order(residual$abs_residual, decreasing = TRUE)[1:5], ]
largest_residual$label <- paste0(largest_residual$station_name, "\n", ifelse(largest_residual$residual > 0, "+", ""), format_k(largest_residual$residual))
p04 <- map_base() +
  geom_sf(data = residual, aes(fill = residual, size = abs_residual), shape = 21,
          color = "#65727D", stroke = 0.3, alpha = 0.9) +
  scale_fill_gradient2(low = blue, mid = "#FFFFFF", high = orange, midpoint = 0,
                       limits = c(-resid_limit, resid_limit), labels = format_k,
                       name = "Predicted - observed\nmonthly entries") +
  scale_size_area(max_size = 12, breaks = c(50000, 150000, 300000), labels = format_k,
                   name = "Absolute error") + label_points(largest_residual, "label") +
  map_frame() + theme_map() +
  labs(title = "Where conditional validation over- and under-allocates entries",
       subtitle = "August parameters evaluated against September 2026 | same 184 stations and predictions as Figure 03",
       caption = "Source: saved Huff validation and direct LTA PV observations, weekday 06:00-09:59 monthly totals.\nOrange = predicted above observed; blue = predicted below observed. Circle area shows absolute residual. Labels show the five largest absolute errors.")
save_figure(p04, "04-residuals", residual[, c("station_id", "station_name", "observed", "predicted", "residual")],
            caption = "Residuals are predicted minus observed monthly September entries. Large errors occur in both directions and limit confidence in individual station scenario estimates.")

# 05: genuinely new physical stations only; existing interchanges are excluded.
new_station <- stations[!stations$available_existing, ]
new_station$line <- proposal$proposal_line[match(new_station$station_id, proposal$station_id)]
new_station$line <- factor(new_station$line, levels = c("JRL", "CRL"))
combined <- study$scenarios$both$changes
new_station$predicted <- combined$predicted[match(new_station$station_id, combined$station_id)]
new_station$baseline <- NA_real_
new_station$percent_change <- NA_real_
new_rows <- st_drop_geometry(new_station)
new_rows <- new_rows[order(new_rows$line, new_rows$predicted), ]
new_rows$station_order <- factor(new_rows$station_name, levels = new_rows$station_name)
p05 <- ggplot(new_rows, aes(predicted, station_order, fill = line)) +
  geom_col(width = 0.70) +
  geom_text(aes(label = format_short(predicted)), hjust = -0.12, size = 3.25, family = "Arial", color = ink) +
  facet_wrap(~line, nrow = 1, scales = "free_y") +
  scale_fill_manual(values = c(JRL = orange, CRL = blue), guide = "none") +
  scale_x_continuous(labels = format_k, limits = c(0, max(new_rows$predicted) * 1.22), expand = expansion(mult = c(0, 0))) +
  labs(title = "Predicted entries at the 29 new physical stations",
       subtitle = "Combined JRL + CRL1 scenario | final September fit | fixed network demand of 19,116,754 monthly morning entries",
       x = "Predicted monthly entries (weekday 06:00-09:59)", y = NULL,
       caption = "Source: saved Huff combined scenario; attraction uses bus stops within 500 m and distinct rail lines. Existing interchanges are excluded.\nRanked within line. These are model allocations, not observed future ridership; new-station baseline and percentage change are undefined.") +
  theme(panel.grid.major.y = element_blank(), axis.text.y = element_text(size = 10.8),
         panel.spacing.x = grid::unit(1.4, "cm"))
save_figure(p05, "05-new-stations", new_rows[, c("station_id", "station_name", "line", "predicted", "baseline", "percent_change")],
            width = 12.8, height = 8,
            caption = "All 29 genuinely new physical stations are ranked within JRL and CRL1 under the combined, fixed-demand scenario. Existing interchange additions are retained in the existing-station comparison.")

# 06: compare scenario predictions with fitted model baseline, never observations.
change <- existing
change$baseline <- combined$baseline[match(change$station_id, combined$station_id)]
change$predicted <- combined$predicted[match(change$station_id, combined$station_id)]
change$percent_change <- combined$percent_change[match(change$station_id, combined$station_id)]
change$change <- combined$change[match(change$station_id, combined$station_id)]
change_limit <- ceiling(max(abs(change$percent_change)) / 10) * 10
largest_change <- change[order(abs(change$percent_change), decreasing = TRUE)[1:5], ]
largest_change$label <- paste0(largest_change$station_name, "\n", format_signed(largest_change$percent_change))
p06 <- map_base() +
  geom_sf(data = change, aes(fill = percent_change), shape = 21, size = 3.6,
          color = "#586872", stroke = 0.35) +
  scale_fill_gradient2(low = blue, mid = "#FFFFFF", high = orange, midpoint = 0,
                       limits = c(-change_limit, change_limit), breaks = c(-100, -50, 0, 50, 100),
                       labels = format_signed, name = "Change from fitted\nexisting-network baseline") +
  label_points(largest_change, "label") + map_frame() + theme_map() +
  labs(title = "Existing stations: changes under the combined expansion scenario",
       subtitle = "184 existing physical stations | (combined prediction / fitted existing-network baseline - 1) x 100% | symmetric scale around zero",
       caption = "Source: saved September-fitted Huff scenarios; both scenarios conserve the same 19,116,754 monthly morning entries.\nOrange = gain; blue = loss. Added lines can strengthen existing interchanges. This compares two model allocations, not observed before-and-after changes.")
save_figure(p06, "06-existing-change", change[, c("station_id", "station_name", "baseline", "predicted", "change", "percent_change")],
            caption = "Percentage changes compare the combined expansion with the fitted existing-network baseline. They describe fixed-demand redistribution and include gains at some existing interchanges.")

# 07: actual polygons carry the population-weighted dominant-choice comparison.
scenario_titles <- c(jrl = "JRL only", crl = "CRL1 only", both = "JRL + CRL1")
switch_polygons <- do.call(rbind, lapply(names(scenario_titles), function(scenario) {
  x <- subzones
  catchment <- study$catchments[study$catchments$scenario == scenario, ]
  x$scenario <- scenario
  x$switched <- catchment$switched[match(x$origin_id, catchment$origin_id)]
  x$dominant_station_id <- catchment$dominant_station_id[match(x$origin_id, catchment$origin_id)]
  x$baseline_station_id <- catchment$baseline_station_id[match(x$origin_id, catchment$origin_id)]
  x$state <- ifelse(is.na(x$switched), "No resident proxy", ifelse(x$switched, "Dominant station changes", "Dominant station retained"))
  metric <- study$switches[study$switches$scenario == scenario, ]
  x$panel <- sprintf("%s\n%s residents (%.2f%%)", scenario_titles[[scenario]],
                      format_n(metric$switched_population), 100 * metric$population_share)
  x
}))
switch_polygons$panel <- factor(switch_polygons$panel, levels = unique(switch_polygons$panel))
switch_polygons$state <- factor(switch_polygons$state,
                                levels = c("Dominant station changes", "Dominant station retained", "No resident proxy"))
p07 <- ggplot(switch_polygons) +
  geom_sf(aes(fill = state), color = "#C8D0D5", linewidth = 0.13) +
  scale_fill_manual(values = c("Dominant station changes" = orange,
                               "Dominant station retained" = "#D6E1E9", "No resident proxy" = "#FFFFFF"),
                     drop = FALSE, name = NULL) +
  facet_wrap(~panel, nrow = 1) + map_frame() + theme_map() +
  labs(title = "Population in subzones whose dominant modelled station changes",
       subtitle = "Dominant station = highest Huff probability | changes relative to the fitted existing-network scenario | 241 populated subzones",
       caption = "Source: saved Huff scenarios and SingStat June 2025 rounded resident population. Denominator: 4,212,800 residents; non-populated subzones are neutral.\nOrange identifies changed origin assignments, not observed commuters moving stations. Counts are population proxies and do not sum predicted station entries.") +
  theme(legend.position = "bottom", strip.text = element_text(size = 12, lineheight = 1.15),
         panel.spacing.x = grid::unit(0.25, "cm"))
save_figure(p07, "07-catchment-switches", switch_polygons[, c("scenario", "origin_id", "population", "switched", "baseline_station_id", "dominant_station_id")],
            caption = "Dominant-choice changes affect resident proxies of 222,460 (5.28%) under JRL, 209,240 (4.97%) under CRL1, and 431,700 (10.25%) combined. These are modelled origin assignments, not observed rider movements.")

# 08: deterministic floor sensitivity with final parameters held fixed.
sens <- study$sensitivity$station_predictions
floor_100 <- sens[sens$scenario == "both" & sens$min_distance_m == 100, ]
floor_250 <- sens[sens$scenario == "both" & sens$min_distance_m == 250, ]
sensitivity <- data.frame(station_id = floor_100$station_id,
                          predicted_100m = floor_100$predicted,
                          predicted_250m = floor_250$predicted[match(floor_100$station_id, floor_250$station_id)])
sensitivity$station_name <- unname(station_names[sensitivity$station_id])
sensitivity$status <- factor(ifelse(sensitivity$station_id %in% new_ids, "New physical stations (29)", "Existing stations (184)"),
                             levels = c("Existing stations (184)", "New physical stations (29)"))
sensitivity$change <- sensitivity$predicted_250m - sensitivity$predicted_100m
sensitivity$percent_change <- 100 * sensitivity$change / sensitivity$predicted_100m
reallocated <- sum(abs(sensitivity$change)) / 2 / sum(sensitivity$predicted_100m)
sensitivity_limit <- ceiling(max(sensitivity$predicted_100m, sensitivity$predicted_250m) / 100000) * 100000
sens_labels <- sensitivity[order(abs(sensitivity$change), decreasing = TRUE)[1:4], ]
p08 <- ggplot(sensitivity, aes(predicted_100m, predicted_250m)) +
  geom_abline(slope = 1, intercept = 0, color = "#6A737A", linewidth = 0.65, linetype = "dashed") +
  geom_point(aes(fill = status, shape = status), size = 3.0, color = "white", stroke = 0.4, alpha = 0.85) +
  geom_label_repel(data = sens_labels, aes(label = station_name), seed = 608, family = "Arial", size = 3.3,
                   box.padding = 0.4, point.padding = 0.3, min.segment.length = 0,
                   fill = "white", color = ink, label.size = 0.12, max.overlaps = Inf) +
  scale_fill_manual(values = c("Existing stations (184)" = blue, "New physical stations (29)" = orange), name = NULL) +
  scale_shape_manual(values = c("Existing stations (184)" = 21, "New physical stations (29)" = 24), name = NULL) +
  scale_x_continuous(labels = format_k, limits = c(0, sensitivity_limit), expand = expansion(mult = c(0.02, 0.03))) +
  scale_y_continuous(labels = format_k, limits = c(0, sensitivity_limit), expand = expansion(mult = c(0.02, 0.03))) +
  coord_equal() +
  labs(title = "Distance-floor sensitivity changes station allocations",
       subtitle = sprintf("Combined JRL + CRL1 | final gamma = %.4f, beta = %.5f held fixed | %.2f%% of network entries reallocated (half L1)",
                           study$fits$september$gamma, study$fits$september$beta, 100 * reallocated),
       x = "Predicted monthly entries: 100 m distance floor", y = "Predicted monthly entries: 250 m distance floor",
       caption = "Source: saved fixed-parameter sensitivity; September 2026 weekday 06:00-09:59 monthly demand.\nDashed line: equal predictions; labels: four largest absolute differences. These are deterministic assumptions, not confidence intervals.\nBoth floors conserve network demand. Dominant-origin switch counts remain unchanged.")
save_figure(p08, "08-sensitivity", sensitivity,
            caption = sprintf("Raising the distance floor from 100 m to 250 m reallocates %.2f%% of combined-scenario entries (half the absolute station changes / network total). Some small station allocations change substantially in relative terms, despite unchanged dominant-origin switch counts.", 100 * reallocated))

jsonlite::write_json(list(renderer = "R ggplot2 + sf; explicit Quarto/revealjs surface", figures = manifest,
                          input_files = required, model_rerun = FALSE,
                          package_versions = setNames(lapply(c("ggplot2", "sf", "patchwork", "ggrepel"),
                                                              function(x) as.character(packageVersion(x))),
                                                      c("ggplot2", "sf", "patchwork", "ggrepel"))),
                     "_workflow/figures-manifest.json", auto_unbox = TRUE, pretty = TRUE)
cat("Eight actual-data figures saved; visual QA recorded separately after inspecting exports.\n")
