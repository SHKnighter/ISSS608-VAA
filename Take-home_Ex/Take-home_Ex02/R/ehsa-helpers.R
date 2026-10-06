# Local classification rules informed by Esri's category definitions, not an
# implementation of ArcGIS's FDR-adjusted EHSA. sfdep's monthly p_sim is retained.
# Source: https://doc.esri.com/en/arcgis-pro/latest/tool-reference/space-time-pattern-mining/learnmoreemerging.html
# Overlapping definitions are resolved explicitly: historical before all other
# patterns; new, then consecutive, before oscillating. Counts are sign-specific.
classify_ehsa_series <- function(gi_star, p_sim, threshold=.05, isolated=FALSE) {
  stopifnot(length(gi_star)==length(p_sim),length(threshold)==1L,
            is.finite(threshold),threshold>0,threshold<1)
  n <- length(gi_star)
  reason <- if (isolated) 'isolated township' else if (n<3L) 'fewer than three months' else
    if (any(!is.finite(gi_star))) 'nonfinite Gi* series' else
    if (any(!is.finite(p_sim)) || any(p_sim<0 | p_sim>1)) 'invalid permutation p' else
    if (length(unique(gi_star))<2L) 'constant Gi* series' else NA_character_
  res <- data.frame(classification=NA_character_,tau=NA_real_,p_value=NA_real_,
    trend_testable=FALSE,untestable_reason=reason,significant_trend=FALSE,
    trend_direction='not testable',n_months=n,n_hot=NA_integer_,n_cold=NA_integer_,
    hot_fraction=NA_real_,cold_fraction=NA_real_,final_hot=NA,final_cold=NA)
  if (!is.na(reason)) return(res)
  mk <- Kendall::MannKendall(gi_star)
  tau <- as.numeric(mk$tau); p <- as.numeric(mk$sl)
  if (!is.finite(tau) || !is.finite(p)) {
    res$untestable_reason <- 'nonfinite Mann-Kendall result'
    return(res)
  }
  hot <- p_sim<=threshold & gi_star>0
  cold <- p_sim<=threshold & gi_star<0
  res$tau <- tau; res$p_value <- p; res$trend_testable <- TRUE
  res$significant_trend <- p<threshold
  res$trend_direction <- if (p<threshold && tau>0) 'increasing Gi*' else
    if (p<threshold && tau<0) 'decreasing Gi*' else 'no significant trend'
  res$n_hot <- sum(hot); res$n_cold <- sum(cold)
  res$hot_fraction <- mean(hot); res$cold_fraction <- mean(cold)
  res$final_hot <- hot[n]; res$final_cold <- cold[n]
  res$classification <- 'no pattern detected'
  # Resolve historical dominance before either sign's final-bin category. This
  # makes sign reversal symmetric even when the final bin is significant in the
  # opposite direction. The published definitions overlap in this edge case.
  if (mean(hot)>=.9 && !hot[n]) {
    res$classification <- 'historical hotspot'; return(res)
  }
  if (mean(cold)>=.9 && !cold[n]) {
    res$classification <- 'historical coldspot'; return(res)
  }
  for (sign in c(1,-1)) {
    same <- if (sign==1) hot else cold
    opposite <- if (sign==1) cold else hot
    suffix <- if (sign==1) 'hotspot' else 'coldspot'
    fraction <- mean(same)
    if (!same[n]) next
    if (fraction>=.9) {
      state <- if (p<threshold && tau*sign>0) 'intensifying' else
        if (p<threshold && tau*sign<0) 'diminishing' else 'persistent'
      res$classification <- paste(state,suffix); return(res)
    }
    if (sum(same)==1L) {
      res$classification <- paste('new',suffix); return(res)
    }
    terminal_run <- rle(same)
    final_length <- tail(terminal_run$lengths,1L)
    if (final_length>=2L && final_length==sum(same)) {
      res$classification <- paste('consecutive',suffix); return(res)
    }
    state <- if (any(opposite)) 'oscillating' else 'sporadic'
    res$classification <- paste(state,suffix); return(res)
  }
  res
}

summarise_ehsa_monthly <- function(monthly_gi, location_ids, isolates=character(), threshold=.05) {
  required <- c('TS_PCODE','month','gi_star','p_sim')
  stopifnot(all(required %in% names(monthly_gi)),!anyDuplicated(location_ids),
    !anyNA(monthly_gi$TS_PCODE),!anyNA(monthly_gi$month),
    setequal(monthly_gi$TS_PCODE,location_ids))
  key <- paste(monthly_gi$TS_PCODE,monthly_gi$month)
  if (anyDuplicated(key)) stop('Duplicate township-month keys')
  dates <- sort(unique(monthly_gi$month))
  out <- lapply(location_ids,function(id) {
    z <- monthly_gi[monthly_gi$TS_PCODE==id,]
    z <- z[order(z$month),]
    if (!identical(z$month,dates)) stop('Incomplete month coverage for ',id)
    cbind(data.frame(TS_PCODE=id),classify_ehsa_series(z$gi_star,z$p_sim,
      threshold=threshold,isolated=id %in% isolates))
  })
  out <- do.call(rbind,out); rownames(out) <- NULL
  out
}

# Preserve actual sfdep0.2.5 classifications for inspection. A bad series must
# not discard the expensive Gi* simulation for all other locations.
raw_sfdep_ehsa <- function(monthly_gi, location_ids, threshold=.05) {
  stopifnot(as.character(utils::packageVersion('sfdep'))=='0.2.5')
  out <- lapply(location_ids,function(id) {
    z <- monthly_gi[monthly_gi$TS_PCODE==id,]
    z <- z[order(z$month),c('gi_star','p_sim')]
    error <- NA_character_
    raw <- tryCatch(sfdep:::classify_hotspot(z,threshold),error=function(e) {
      error <<- conditionMessage(e); NULL
    })
    if (is.null(raw)) raw <- data.frame(tau=NA_real_,sl=NA_real_,S=NA_real_,
      D=NA_real_,varS=NA_real_,classification=NA_character_)
    cbind(data.frame(TS_PCODE=id),raw,raw_error=error)
  })
  out <- do.call(rbind,out); rownames(out) <- NULL
  out
}

