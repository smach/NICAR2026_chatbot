# helper function for sample question button common logic
handle_question_button <- function(query, chat_obj) {
  chat <- chat_obj()
  if (!is.null(chat)) {
    tryCatch({
      response_stream <- chat$stream_async(query)
      chat_append("session_chat", response_stream) %>%
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