# helpers_logging.R
# Token usage logging and cost tracking for Gemini API
# Supports both local CSV logging and Supabase PostgreSQL for cloud deployment
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

# ==== SUPABASE POSTGRESQL FUNCTIONS ====

#' Check if Supabase is configured
#' @return TRUE if SUPABASE_URL and SUPABASE_KEY are set
supabase_configured <- function() {
  nzchar(Sys.getenv("SUPABASE_URL")) && nzchar(Sys.getenv("SUPABASE_KEY"))
}

#' Execute a Supabase REST API request
#' @param endpoint API endpoint (e.g., "/rest/v1/api_usage")
#' @param method HTTP method (GET, POST, etc.)
#' @param body Optional request body (list that will be converted to JSON)
#' @param query Optional query parameters (list)
#' @return Parsed response or NULL on error
supabase_request <- function(endpoint, method = "GET", body = NULL, query = NULL) {
  if (!supabase_configured()) return(NULL)

  url <- Sys.getenv("SUPABASE_URL")
  key <- Sys.getenv("SUPABASE_KEY")

  tryCatch({
    req <- httr2::request(paste0(url, endpoint)) |>
      httr2::req_method(method) |>
      httr2::req_headers(
        apikey = key,
        Authorization = paste("Bearer", key),
        `Content-Type` = "application/json",
        Prefer = "return=minimal"
      )

    if (!is.null(query)) {
      req <- httr2::req_url_query(req, !!!query)
    }

    if (!is.null(body)) {
      req <- httr2::req_body_json(req, body)
    }

    resp <- httr2::req_perform(req)

    # For POST with return=minimal, there's no body to parse
    if (method == "POST") {
      return(TRUE)
    }

    httr2::resp_body_json(resp)
  }, error = function(e) {
    message("Supabase error: ", e$message)
    NULL
  })
}

#' Log usage to Supabase (inserts a row into api_usage table)
#' @param timestamp Timestamp of the request
#' @param date Date of the request
#' @param model Model name
#' @param key_source Source of API key ("app_key" or "user_key")
#' @param input_tokens Number of input tokens
#' @param output_tokens Number of output tokens
#' @param input_cost Cost for input tokens
#' @param output_cost Cost for output tokens
#' @param total_cost Total cost for this request
#' @return TRUE if successful, FALSE otherwise
log_to_supabase <- function(timestamp, date, model, key_source,
                            input_tokens, output_tokens,
                            input_cost, output_cost, total_cost) {
  message("[LOGGING] log_to_supabase called")
  message("[LOGGING] SUPABASE_URL set: ", nzchar(Sys.getenv("SUPABASE_URL")))
  message("[LOGGING] SUPABASE_KEY set: ", nzchar(Sys.getenv("SUPABASE_KEY")))
  message("[LOGGING] supabase_configured() = ", supabase_configured())

  if (!supabase_configured()) {
    message("[LOGGING] Supabase not configured, skipping")
    return(FALSE)
  }

  tryCatch({
    message("[LOGGING] Inserting row into api_usage table...")

    result <- supabase_request(
      endpoint = "/rest/v1/api_usage",
      method = "POST",
      body = list(
        timestamp = timestamp,
        date = date,
        model = model,
        key_source = key_source,
        input_tokens = input_tokens,
        output_tokens = output_tokens,
        input_cost = input_cost,
        output_cost = output_cost,
        total_cost = total_cost
      )
    )

    if (isTRUE(result)) {
      message("[LOGGING] Supabase logging complete")
      TRUE
    } else {
      message("[LOGGING] Supabase logging may have failed")
      FALSE
    }
  }, error = function(e) {
    message("[LOGGING] Supabase logging error: ", e$message)
    FALSE
  })
}

#' Get all logs from Supabase
#' @param date Optional date to filter by (format: "YYYY-MM-DD"). Use NULL for all logs.
#' @param limit Maximum number of rows to return (default 1000)
#' @return Data frame with all log columns
get_supabase_logs <- function(date = NULL, limit = 1000) {
  if (!supabase_configured()) {
    return(data.frame(
      timestamp = character(),
      date = character(),
      model = character(),
      key_source = character(),
      input_tokens = integer(),
      output_tokens = integer(),
      input_cost = numeric(),
      output_cost = numeric(),
      total_cost = numeric()
    ))
  }

  query <- list(
    select = "*",
    order = "timestamp.desc",
    limit = as.character(limit)
  )

  if (!is.null(date)) {
    query$date <- paste0("eq.", date)
  }

  result <- supabase_request(
    endpoint = "/rest/v1/api_usage",
    method = "GET",
    query = query
  )

  if (is.null(result) || length(result) == 0) {
    return(data.frame(
      timestamp = character(),
      date = character(),
      model = character(),
      key_source = character(),
      input_tokens = integer(),
      output_tokens = integer(),
      input_cost = numeric(),
      output_cost = numeric(),
      total_cost = numeric()
    ))
  }

  # Convert list of lists to data frame
  do.call(rbind, lapply(result, as.data.frame))
}

#' Get aggregated totals from Supabase
#' @param date Optional date to filter by. Use NULL for all-time totals.
#' @return List with total_requests, total_input_tokens, total_output_tokens, total_cost
get_supabase_totals <- function(date = NULL) {
  if (!supabase_configured()) {
    return(list(
      total_requests = NA,
      total_input_tokens = NA,
      total_output_tokens = NA,
      total_cost = NA,
      configured = FALSE
    ))
  }

  # Get all logs (or filtered by date) and aggregate in R

  # Supabase REST API doesn't support aggregation directly without RPC
  logs <- get_supabase_logs(date = date, limit = 10000)

  if (nrow(logs) == 0) {
    return(list(
      total_requests = 0L,
      total_input_tokens = 0L,
      total_output_tokens = 0L,
      total_cost = 0,
      configured = TRUE
    ))
  }

  list(
    total_requests = nrow(logs),
    total_input_tokens = sum(logs$input_tokens, na.rm = TRUE),
    total_output_tokens = sum(logs$output_tokens, na.rm = TRUE),
    total_cost = sum(logs$total_cost, na.rm = TRUE),
    configured = TRUE
  )
}

#' Get daily usage summary from Supabase
#' @return Data frame with date, requests, and total_cost per day
get_supabase_daily <- function() {
  if (!supabase_configured()) {
    return(data.frame(date = character(), requests = integer(), total_cost = numeric()))
  }

  logs <- get_supabase_logs(limit = 10000)

  if (nrow(logs) == 0) {
    return(data.frame(date = character(), requests = integer(), total_cost = numeric()))
  }

  # Aggregate by date
  daily <- aggregate(
    cbind(requests = 1, total_cost = logs$total_cost),
    by = list(date = logs$date),
    FUN = sum
  )
  daily$requests <- as.integer(daily$requests)
  daily[order(daily$date, decreasing = TRUE), ]
}

#' Delete logs from Supabase (use with caution!)
#' @param before_date Optional: delete logs before this date. If NULL, deletes ALL logs.
#' @return TRUE if successful
delete_supabase_logs <- function(before_date = NULL) {
  if (!supabase_configured()) return(FALSE)

  query <- list()
  if (!is.null(before_date)) {
    query$date <- paste0("lt.", before_date)
  } else {
    # Delete all - need some condition for Supabase
    query$id <- "gt.0"
  }

  tryCatch({
    req <- httr2::request(paste0(Sys.getenv("SUPABASE_URL"), "/rest/v1/api_usage")) |>
      httr2::req_method("DELETE") |>
      httr2::req_headers(
        apikey = Sys.getenv("SUPABASE_KEY"),
        Authorization = paste("Bearer", Sys.getenv("SUPABASE_KEY"))
      ) |>
      httr2::req_url_query(!!!query)

    httr2::req_perform(req)
    TRUE
  }, error = function(e) {
    message("Supabase delete error: ", e$message)
    FALSE
  })
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

  # Also log to Supabase if configured (for cloud deployment)
  log_to_supabase(
    timestamp = format(timestamp, "%Y-%m-%dT%H:%M:%S%z"),
    date = as.character(as.Date(timestamp)),
    model = model,
    key_source = key_source,
    input_tokens = input_tokens,
    output_tokens = output_tokens,
    input_cost = cost$input_cost,
    output_cost = cost$output_cost,
    total_cost = cost$total_cost
  )

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

#' Get cumulative token totals from a chat object
#'
#' Uses ellmer's Chat$get_tokens() method which returns a data frame with
#' one row per assistant turn. This function sums ALL rows to get cumulative totals.
#'
#' @param chat An ellmer chat object
#' @return List with cumulative input_tokens, output_tokens, and row_count
get_cumulative_tokens <- function(chat) {
  tokens_df <- tryCatch(
    chat$get_tokens(),
    error = function(e) {
      message("[LOGGING] Error calling get_tokens(): ", e$message)
      NULL
    }
  )

  if (is.null(tokens_df) || nrow(tokens_df) == 0) {
    return(list(input_tokens = 0, output_tokens = 0, row_count = 0))
  }

  # Sum ALL rows - each row is an assistant turn (including tool call responses)
  # Use na.rm = TRUE to handle any NA values gracefully
  list(
    input_tokens = sum(tokens_df$input, na.rm = TRUE) +
                   sum(tokens_df$cached_input, na.rm = TRUE),
    output_tokens = sum(tokens_df$output, na.rm = TRUE),
    row_count = nrow(tokens_df)
  )
}

#' Calculate token usage for the most recent interaction
#'
#' Compares current cumulative totals against previous totals to determine
#' how many tokens were used in the latest query. This approach guarantees
#' ALL tokens are captured, including those from multiple tool calls.
#'
#' @param chat An ellmer chat object
#' @param prev_totals List with previous cumulative totals from get_cumulative_tokens()
#' @return List with input_tokens and output_tokens for this interaction, or NULL
calculate_interaction_tokens <- function(chat, prev_totals) {
  current_totals <- get_cumulative_tokens(chat)

  # Calculate tokens used in this interaction
  input_used <- current_totals$input_tokens - prev_totals$input_tokens
  output_used <- current_totals$output_tokens - prev_totals$output_tokens
  turns_added <- current_totals$row_count - prev_totals$row_count

  message("[LOGGING] Token calculation:")
  message("[LOGGING]   Previous: ", prev_totals$input_tokens, " input, ",
          prev_totals$output_tokens, " output (", prev_totals$row_count, " turns)")
  message("[LOGGING]   Current:  ", current_totals$input_tokens, " input, ",
          current_totals$output_tokens, " output (", current_totals$row_count, " turns)")
  message("[LOGGING]   This query: ", input_used, " input, ", output_used, " output (",
          turns_added, " turns added)")

  # Only return usage if tokens were actually used
  if (input_used == 0 && output_used == 0) {
    message("[LOGGING] No tokens used in this interaction")
    return(NULL)
  }

  list(input_tokens = input_used, output_tokens = output_used)
}
