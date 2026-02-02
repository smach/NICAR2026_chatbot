# Helper function for sample question button common logic
handle_question_button <- function(query, chat_obj) {
  chat <- chat_obj()
  if (!is.null(chat)) {
    # CRITICAL: Capture token totals BEFORE the query starts
    prev_totals <- get_cumulative_tokens(chat)
    message("[LOGGING] Sample button query. Previous totals: ",
            prev_totals$input_tokens, " input, ",
            prev_totals$output_tokens, " output")

    tryCatch({
      response_stream <- chat$stream_async(query)
      chat_append("session_chat", response_stream) %>%
        then(function(result) {
          # Calculate tokens used for THIS query
          usage <- calculate_interaction_tokens(chat, prev_totals)
          if (!is.null(usage)) {
            log_api_usage(
              input_tokens = usage$input_tokens,
              output_tokens = usage$output_tokens,
              model = "gemini-2.5-flash"
            )
          }
        }) %>%
        catch(function(error) {
          chat_append("session_chat",
                      paste("Sorry, I had trouble searching for sessions:", error$message))
        })
    }, error = function(e) {
      chat_append("session_chat",
                  paste("Sorry, I had trouble processing that question:", e$message))
    })
  } else {
    chat_append("session_chat",
                "The chat system is not initialized yet. Please wait a moment and try again.")
  }
}