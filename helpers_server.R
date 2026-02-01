# helper function for sample question button common logic
handle_question_button <- function(query, chat_obj) {
  chat <- chat_obj()
  if (!is.null(chat)) {
    tryCatch({
      response_stream <- chat$stream_async(query)
      chat_append("session_chat", response_stream) %>%
        then(function(result) {
          # Log token usage after stream completes
          usage <- extract_last_turn_usage(chat)
          if (!is.null(usage)) {
            log_api_usage(
              input_tokens = usage$input_tokens,
              output_tokens = usage$output_tokens,
              model = "gemini-3-flash-preview"
            )
          }
        }) %>%
        catch(function(error) {
          chat_append("session_chat", paste("Sorry, I had trouble searching for sessions:", error$message))
        })
    }, error = function(e) {
      chat_append("session_chat", paste("Sorry, I had trouble processing that question:", e$message))
    })
  } else {
    chat_append("session_chat", "The chat system is not initialized yet. Please wait a moment and try again.")
  }
}