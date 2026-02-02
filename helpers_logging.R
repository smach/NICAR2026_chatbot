# helpers_logging.R
# Token usage logging and cost tracking for Gemini API
# Supports both local CSV logging and Upstash Redis for cloud deployment
#
# To disable logging, set NICAR_CHATBOT_LOG_USAGE=false in your environment or .Renviron
# Logging is disabled by default for local development

#' Check if usage logging is enabled
#' @return TRUE if NICAR_CHATBOT_LOG_USAGE env var is "true" (case-insensitive)
logging_enabled <- function() {
 tolower(Sys.getenv("NICAR_CHATBOT_LOG_USAGE", "false")) == "true"
}

# Pricing constants for gemini-2.5-flash
# As of Feb 2025: $0.30 per million input tokens, $2.50 per million output tokens
GEMINI_FLASH_PRICING <- list(
  input_per_million = 0.30,
  output_per_million = 2.50
)

#' Calculate cost from token counts
#' @param input_tokens Number of input tokens
#' @param output_tokens Number of output tokens
#' @param model Model name (for future extensibility)
#' @return List with input_cost, output_cost, and total_cost
calculate_cost <- function(
  input_tokens,
  output_tokens,
  model = "gemini-2.5-flash"
) {
  pricing <- GEMINI_FLASH_PRICING
  input_cost <- (input_tokens / 1e6) * pricing$input_per_million
  output_cost <- (output_tokens / 1e6) * pricing$output_per_million
  list(
    input_cost = input_cost,
    output_cost = output_cost,
    total_cost = input_cost + output_cost
  )
}

# ==== UPSTASH REDIS FUNCTIONS ====

#' Check if Upstash is configured
#' @return TRUE if UPSTASH_URL and UPSTASH_TOKEN are set
upstash_configured <- function() {
  nzchar(Sys.getenv("UPSTASH_URL")) && nzchar(Sys.getenv("UPSTASH_TOKEN"))
}

#' Execute an Upstash Redis command
#' @param command Vector of command parts (e.g., c("INCRBYFLOAT", "key", "1.5"))
#' @return Parsed response or NULL on error
upstash_command <- function(command) {
  if (!upstash_configured()) return(NULL)

  url <- Sys.getenv("UPSTASH_URL")
  token <- Sys.getenv("UPSTASH_TOKEN")

  tryCatch({
    resp <- httr2::request(url) |>
      httr2::req_headers(Authorization = paste("Bearer", token)) |>
      httr2::req_body_json(command) |>
      httr2::req_perform() |>
      httr2::resp_body_json()
    resp$result
  }, error = function(e) {
    message("Upstash error: ", e$message)
    NULL
  })
}

#' Log usage to Upstash Redis (increments running totals AND daily totals)
#' @param input_tokens Number of input tokens
#' @param output_tokens Number of output tokens
#' @param total_cost Total cost for this request
#' @return TRUE if successful, FALSE otherwise
log_to_upstash <- function(input_tokens, output_tokens, total_cost) {
  message("[LOGGING] log_to_upstash called")
  message("[LOGGING] UPSTASH_URL set: ", nzchar(Sys.getenv("UPSTASH_URL")))
  message("[LOGGING] UPSTASH_TOKEN set: ", nzchar(Sys.getenv("UPSTASH_TOKEN")))
  message("[LOGGING] upstash_configured() = ", upstash_configured())

  if (!upstash_configured()) {
    message("[LOGGING] Upstash not configured, skipping")
    return(FALSE)
  }

  # Get today's date for daily keys
 today <- format(Sys.Date(), "%Y-%m-%d")

  tryCatch({
    # Running totals (all-time)
    message("[LOGGING] Updating running totals...")
    upstash_command(c("INCR", "nicar:total_requests"))
    upstash_command(c("INCRBYFLOAT", "nicar:total_input_tokens", as.character(input_tokens)))
    upstash_command(c("INCRBYFLOAT", "nicar:total_output_tokens", as.character(output_tokens)))
    upstash_command(c("INCRBYFLOAT", "nicar:total_cost", as.character(total_cost)))

    # Daily totals (for tracking by day)
    message("[LOGGING] Updating daily totals for ", today)
    upstash_command(c("INCR", paste0("nicar:daily:", today, ":requests")))
    upstash_command(c("INCRBYFLOAT", paste0("nicar:daily:", today, ":cost"), as.character(total_cost)))

    # Track which days have data (for listing)
    upstash_command(c("SADD", "nicar:days", today))

    message("[LOGGING] Upstash logging complete")
    TRUE
  }, error = function(e) {
    message("[LOGGING] Upstash logging error: ", e$message)
    FALSE
  })
}

#' Get running totals from Upstash
#' @return List with total_requests, total_input_tokens, total_output_tokens, total_cost
get_upstash_totals <- function() {
  if (!upstash_configured()) {
    return(list(
      total_requests = NA,
      total_input_tokens = NA,
      total_output_tokens = NA,
      total_cost = NA,
      configured = FALSE
    ))
  }

  list(
    total_requests = as.integer(upstash_command(c("GET", "nicar:total_requests")) %||% 0),
    total_input_tokens = as.numeric(upstash_command(c("GET", "nicar:total_input_tokens")) %||% 0),
    total_output_tokens = as.numeric(upstash_command(c("GET", "nicar:total_output_tokens")) %||% 0),
    total_cost = as.numeric(upstash_command(c("GET", "nicar:total_cost")) %||% 0),
    configured = TRUE
  )
}

#' Get daily usage stats from Upstash
#' @param date Optional date (defaults to today). Use "all" to get all days.
#' @return Data frame with date, requests, and cost
get_upstash_daily <- function(date = NULL) {
 if (!upstash_configured()) {
    return(data.frame(date = character(), requests = integer(), cost = numeric()))
 }

 if (is.null(date)) {
    date <- format(Sys.Date(), "%Y-%m-%d")
 }

 if (date == "all") {
    # Get all days that have data
    days <- upstash_command(c("SMEMBERS", "nicar:days"))
    if (is.null(days) || length(days) == 0) {
      return(data.frame(date = character(), requests = integer(), cost = numeric()))
    }
    # Sort days
    days <- sort(unlist(days))

    # Get stats for each day
    results <- lapply(days, function(d) {
      data.frame(
        date = d,
        requests = as.integer(upstash_command(c("GET", paste0("nicar:daily:", d, ":requests"))) %||% 0),
        cost = as.numeric(upstash_command(c("GET", paste0("nicar:daily:", d, ":cost"))) %||% 0)
      )
    })
    do.call(rbind, results)
 } else {
    # Get stats for specific date
    data.frame(
      date = date,
      requests = as.integer(upstash_command(c("GET", paste0("nicar:daily:", date, ":requests"))) %||% 0),
      cost = as.numeric(upstash_command(c("GET", paste0("nicar:daily:", date, ":cost"))) %||% 0)
    )
 }
}

#' Reset Upstash counters (use with caution!)
#' @param daily_too If TRUE, also deletes daily stats. Default FALSE.
#' @return TRUE if successful
reset_upstash_totals <- function(daily_too = FALSE) {
  if (!upstash_configured()) return(FALSE)

  # Reset running totals
  upstash_command(c("SET", "nicar:total_requests", "0"))
  upstash_command(c("SET", "nicar:total_input_tokens", "0"))
  upstash_command(c("SET", "nicar:total_output_tokens", "0"))
  upstash_command(c("SET", "nicar:total_cost", "0"))

  if (daily_too) {
    # Get all days and delete their keys
    days <- upstash_command(c("SMEMBERS", "nicar:days"))
    if (!is.null(days) && length(days) > 0) {
      for (d in days) {
        upstash_command(c("DEL", paste0("nicar:daily:", d, ":requests")))
        upstash_command(c("DEL", paste0("nicar:daily:", d, ":cost")))
      }
    }
    upstash_command(c("DEL", "nicar:days"))
  }

  TRUE
}

# ==== LOCAL CSV FUNCTIONS ====

#' Get log directory (Posit Connect Cloud compatible)
#' Uses CONNECT_DATA_DIR on Connect, falls back to logs/ locally
#' @return Path to log directory
get_log_dir <- function() {
  log_dir <- Sys.getenv("CONNECT_DATA_DIR", "logs")
  if (!dir.exists(log_dir)) {
    dir.create(log_dir, recursive = TRUE)
  }
  log_dir
}

#' Log a single API call to CSV and Upstash (if configured)
#'
#' Logging is controlled by the NICAR_CHATBOT_LOG_USAGE environment variable.
#' Set NICAR_CHATBOT_LOG_USAGE=TRUE to enable logging, otherwise logging is skipped.
#'
#' @param input_tokens Number of input tokens
#' @param output_tokens Number of output tokens
#' @param model Model name
#' @param key_source Source of API key: "app_key" (environment) or "user_key" (user-provided)
#' @param timestamp Timestamp of the API call
#' @return Invisibly returns the log entry data frame (or NULL if logging disabled)
log_api_usage <- function(
  input_tokens,
  output_tokens,
  model,
  key_source = "app_key",
  timestamp = Sys.time()
) {
  # Debug: log that we're attempting to log
  message("[LOGGING] log_api_usage called with ", input_tokens, " input, ", output_tokens, " output tokens")
  message("[LOGGING] NICAR_CHATBOT_LOG_USAGE = '", Sys.getenv("NICAR_CHATBOT_LOG_USAGE", ""), "'")
  message("[LOGGING] logging_enabled() = ", logging_enabled())

  # Skip logging if disabled
 if (!logging_enabled()) {
    message("[LOGGING] Logging disabled, skipping")
    return(invisible(NULL))
 }

  cost <- calculate_cost(input_tokens, output_tokens, model)

  log_entry <- data.frame(
    timestamp = format(timestamp, "%Y-%m-%d %H:%M:%S"),
    date = as.character(as.Date(timestamp)),
    model = model,
    key_source = key_source,
    input_tokens = input_tokens,
    output_tokens = output_tokens,
    input_cost = cost$input_cost,
    output_cost = cost$output_cost,
    total_cost = cost$total_cost,
    stringsAsFactors = FALSE
  )

  # Log to local CSV
  log_file <- file.path(get_log_dir(), "api_usage.csv")
  write_header <- !file.exists(log_file)
  suppressWarnings(
    write.table(
      log_entry,
      log_file,
      sep = ",",
      append = TRUE,
      row.names = FALSE,
      col.names = write_header,
      quote = TRUE
    )
  )

  # Also log to Upstash if configured (for cloud deployment)
  log_to_upstash(input_tokens, output_tokens, cost$total_cost)

  invisible(log_entry)
}

#' Get daily summary of API usage
#' @param date Date to summarize (defaults to today)
#' @return Data frame with daily totals
get_daily_summary <- function(date = Sys.Date()) {
  log_file <- file.path(get_log_dir(), "api_usage.csv")

  if (!file.exists(log_file)) {
    return(data.frame(
      date = as.character(date),
      total_requests = 0L,
      total_input_tokens = 0L,
      total_output_tokens = 0L,
      total_cost = 0
    ))
  }

  logs <- read.csv(log_file, stringsAsFactors = FALSE)
  logs$date <- as.Date(logs$date)
  target_date <- as.Date(date)

  daily <- logs[logs$date == target_date, ]

  if (nrow(daily) == 0) {
    return(data.frame(
      date = as.character(target_date),
      total_requests = 0L,
      total_input_tokens = 0L,
      total_output_tokens = 0L,
      total_cost = 0
    ))
  }

  data.frame(
    date = as.character(target_date),
    total_requests = nrow(daily),
    total_input_tokens = sum(daily$input_tokens),
    total_output_tokens = sum(daily$output_tokens),
    total_cost = sum(daily$total_cost)
  )
}

#' Extract token usage from the last assistant turn in an ellmer chat object
#' @param chat An ellmer chat object
#' @return List with input_tokens and output_tokens, or NULL if unavailable
extract_last_turn_usage <- function(chat) {
  turns <- chat$get_turns()
  if (length(turns) == 0) {
    return(NULL)
  }

  # Find the index of the last user turn
  last_user_idx <- 0
  for (i in seq_along(turns)) {
    role <- tryCatch(turns[[i]]@role, error = function(e) "")
    if (role == "user") last_user_idx <- i
  }

  if (last_user_idx == 0 || last_user_idx >= length(turns)) {
    return(NULL)
  }

  # Sum all assistant turns AFTER the last user turn
  # (These are all the turns generated in response to the latest query)
  total_input <- 0
  total_output <- 0

  for (i in (last_user_idx + 1):length(turns)) {
    role <- tryCatch(turns[[i]]@role, error = function(e) "")
    if (role == "assistant") {
      tokens <- turns[[i]]@tokens
      if (!any(is.na(tokens))) {
        total_input <- total_input + tokens[1] + tokens[3] # uncached + cached
        total_output <- total_output + tokens[2]
      }
    }
  }

  if (total_input == 0 && total_output == 0) {
    return(NULL)
  }

  list(
    input_tokens = total_input,
    output_tokens = total_output
  )
}
