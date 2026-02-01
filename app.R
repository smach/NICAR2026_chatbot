library(shiny)
library(shinychat)
library(ellmer)
library(ragnar)
library(reactable)
library(htmlwidgets) # For JS() function used in custom search
library(bslib)
library(dplyr)
library(htmltools)
library(promises)
library(arrow)
library(lubridate)
library(DBI)
source("helpers_ui.R")
source("helpers_server.R")
source("helpers_logging.R")

# Load environment variables
if (file.exists(".Renviron")) {
  readRenviron(".Renviron")
}

ui <- page_fillable(
  theme = custom_theme,

  tags$head(
    tags$style(custom_style)
  ),

  # Title panel with NICAR branding
  div(class = "header-section", div(class = "geometric-bg"), header_content),

  layout_sidebar(
    sidebar = sidebar(
      width = "40%",
      open = "open",
      title = div(
        "🤖 NICAR 2026 Conference Assistant",
        style = "color: #2B4C5E; font-weight: 600;"
      ),
      class = "chat-sidebar",

      # Sample questions
      div(
        style = "margin-bottom: 15px;",
        h5(
          "Try these questions:",
          style = "margin-top: 0; color: #2B4C5E; font-weight: 600;"
        ),
        actionButton(
          "ask_mapping",
          "🧰 What sessions are about mapping?",
          class = "btn-sample-questions"
        ),
        actionButton(
          "ask_thursday",
          "📊 Are there any generative AI sessions happening Thursday morning?",
          class = "btn-sample-questions"
        ),
        actionButton(
          "ask_spreadsheets",
          "✨ Which sessions cover spreadsheets for beginners?",
          class = "btn-sample-questions"
        )
      ),

      # Filter button container - shows "Show in Table" after AI finds sessions
      div(
        id = "show_in_table_container",
        style = "margin-bottom: 15px;",
        uiOutput("show_in_table_button")
      ),

      chat_ui(
        "session_chat",
        messages = list(
          list(
            role = "assistant",
            content = chatbot_welcome
          )
        ),
        placeholder = "Ask about conference sessions...",
        height = "400px"
      )
    ),

    # Main panel with session table
    div(
      style = "padding: 20px; background-color: white;",
      div(
        style = "margin-bottom: 20px;",
        fluidRow(
          column(
            8,
            h3(
              "📚 Session Directory",
              style = "margin: 0; color: #2B4C5E; font-weight: 600;"
            ),
            p(
              "Click any session for details • Search to filter • All descriptions are searchable",
              style = "margin: 5px 0 0 0; color: #666; font-size: 14px;"
            )
          ),
          column(
            4,
            div(
              class = "stats-box",
              style = "text-align: center;",
              textOutput("table_stats")
            )
          )
        )
      ),
      reactableOutput("session_table", height = "calc(100vh - 300px)")
    )
  )
)

server <- function(input, output, session) {
  # Load session data ====
  sessions_data <- reactive({
    tryCatch(
      {
        read_parquet("sessions_info_for_app.parquet")
      },
      error = function(e) {
        # Fallback data if file not found
        data.frame(
          Title = c("Welcome to NICAR", "Getting Started with Data"),
          Day = c("Thursday", "Thursday"),
          Time = c("9:00 AM", "10:00 AM"),
          Speakers = c("IRE Staff", "TBD"),
          Room = c("Main Hall", "Room A"),
          SkillLevel = c("", "Beginner"),
          Track = c("", "Beginner"),
          Description = c("Opening session", "Introduction to data journalism"),
          Date = c("2026-03-05", "2026-03-05"),
          Time_24hr = c("09:00", "10:00"),
          Cost = c(NA, NA),
          Type = c("Special", "Hands-on")
        )
      }
    )
  })

  # Initialize store connection as a regular variable (not reactive) ====
  store <- NULL

  # connect to the store on app startup with error handling ====
  tryCatch(
    {
      store <- ragnar_store_connect(
        "nicar_2026_sessions.duckdb",
        read_only = TRUE
      )
      # May need for windows for hybrid search
      dbExecute(store@con, "LOAD fts;")
    },
    error = function(e) {
      # Silent fail - store remains NULL
      message("Could not connect to ragnar store: ", e$message)
    }
  )

  # Create basic retrieval R function
  # Returns up to top_k sessions matching the query
  retrieve_sessions_filtered <- function(
    query,
    day = NULL,
    start_time = NULL,
    end_time = NULL,
    session_type = NULL,
    skill_level = NULL,
    top_k = 20
  ) {
    # Initialize filter components
    filter_components <- list()

    # Add day filter if provided
    if (!is.null(day)) {
      # Validate day input
      valid_days <- c("Thursday", "Friday", "Saturday", "Sunday")
      if (!day %in% valid_days) {
        stop("day must be Thursday, Friday, Saturday, or Sunday")
      }
      filter_components$day <- rlang::expr(Day == !!day)
    }

    # Add time filters (using Time_24hr for easier comparison)
    if (!is.null(start_time)) {
      filter_components$start <- rlang::expr(Time_24hr >= !!start_time)
    }
    if (!is.null(end_time)) {
      filter_components$end <- rlang::expr(Time_24hr <= !!end_time)
    }

    # Add session type filter (exact match)
    if (!is.null(session_type)) {
      filter_components$type <- rlang::expr(Type == !!session_type)
    }

    # Add skill level filter (exact match)
    if (!is.null(skill_level)) {
      filter_components$skill <- rlang::expr(SkillLevel == !!skill_level)
    }

    # Combine all filter components with AND logic
    if (length(filter_components) == 0) {
      filter_expr <- NULL
    } else if (length(filter_components) == 1) {
      filter_expr <- filter_components[[1]]
    } else {
      # Combine multiple filters with &
      filter_expr <- Reduce(
        function(x, y) rlang::expr(!!x & !!y),
        filter_components
      )
    }

    # Perform retrieval - pure semantic search for topic queries
    ragnar_retrieve_vss(
      store,
      query,
      top_k = top_k,
      filter = !!filter_expr
    ) |>
      select(
        Title,
        Date,
        Track,
        Speakers,
        Description,
        Time,
        Room,
        SkillLevel,
        Type
      )
  }

  # ==== SPEAKER SEARCH TOOL ====

  # Search for sessions by speaker name or organization using BM25 keyword matching
  # This is more effective than semantic search for finding exact name matches
  #
  # Parameters:
  #   speaker_name - The speaker name, partial name, or organization to search for
  #   top_k - Number of results to return (default: 10)
  #
  # Returns:
  #   Data frame of matching sessions with key fields
  search_sessions_by_speaker <- function(speaker_name, top_k = 10) {
    ragnar_retrieve_bm25(
      store,
      speaker_name,
      top_k = top_k,
      conjunctive = FALSE # Allow partial matches for flexibility
    ) |>
      select(
        Title,
        Date,
        Track,
        Speakers,
        Description,
        Time,
        Room,
        SkillLevel,
        Type
      )
  }

  # ==== HIGHLIGHT SESSIONS TOOL ====

  # This function is called by the AI to enable the "Show in Table" filter button
  # It stores the session titles from AI recommendations in a reactive value
  # The UI then shows a button allowing users to filter the table to these sessions
  #
  # Parameters:
  #   titles - Character vector of exact session titles to highlight
  #
  # Returns:
  #   Message confirming how many sessions are ready to be filtered
  highlight_sessions <- function(titles) {
    if (length(titles) > 0) {
      clean_titles <- unlist(titles)
      ai_session_titles(clean_titles)
      return(paste(
        "Table ready to filter to",
        length(clean_titles),
        "sessions."
      ))
    } else {
      ai_session_titles(NULL)
      return("No sessions to highlight.")
    }
  }

  # Initialize a Shiny reactive value to be used later by an ellmer chat object
  chat_obj <- reactiveVal(NULL)

  # ==== STATE MANAGEMENT FOR FILTER BUTTON ====
  # ai_session_titles: Stores titles from AI's most recent recommendation
  # table_filter: When set, filters the table to show only these titles
  ai_session_titles <- reactiveVal(NULL)
  table_filter <- reactiveVal(NULL)

  # Store user-provided API key
  user_api_key <- reactiveVal(NULL)

  # Track whether using app key (from environment) or user-provided key
  key_source <- reactiveVal("app_key")

  # Show API key modal on startup if no key in environment
  observe({
    env_key <- Sys.getenv("GEMINI_API_KEY")
    if (env_key == "" && is.null(user_api_key())) {
      showModal(modalDialog(
        title = "Gemini API Key Required",
        p(
          "This app uses Google's Gemini 2.5 Flash to answer questions about NICAR 2026 sessions."
        ),
        p(
          "Please enter your own Google Gemini API key to use the chat feature. There is a free tier"
        ),
        p(tags$a(
          "Get an API key in Google's AI Studio",
          href = "https://aistudio.google.com/api-keys",
          target = "_blank"
        )),
        textInput(
          "api_key_input",
          "Your Google API Key:",
          placeholder = "..."
        ),
        p(tags$small(
          "Your key is only used for this session and is not stored.",
          style = "color: #666;"
        )),
        footer = tagList(
          modalButton("Cancel"),
          actionButton("submit_api_key", "Submit", class = "btn-primary")
        ),
        easyClose = FALSE
      ))
    }
  }) |>
    bindEvent(TRUE, once = TRUE)

  # Handle API key submission
  observeEvent(input$submit_api_key, {
    key <- input$api_key_input
    if (nchar(key) > 20) {
      user_api_key(key)
      key_source("user_key")
      removeModal()
    } else {
      showNotification(
        "Please enter a valid key",
        type = "error"
      )
    }
  })

  # Get the active API key (environment or user-provided)
  active_api_key <- reactive({
    env_key <- Sys.getenv("GEMINI_API_KEY")
    if (env_key != "") {
      return(env_key)
    }
    user_api_key()
  })

  # Initialize chat when API key is available
  observe({
    api_key <- active_api_key()
    if (is.null(api_key) || api_key == "" || is.null(store)) {
      return()
    }

    # Set the API key for this session
    Sys.setenv(GEMINI_API_KEY = api_key)

    tryCatch(
      {
        # Create tool from retrieval function (ellmer 0.3.0 syntax)
        session_retrieval_tool <- tool(
          retrieve_sessions_filtered,
          name = "retrieve_sessions_filtered",
          description = "Retrieve conference session information based on content query with optional filtering by day, time, track, session type, and skill level.",
          arguments = list(
            query = type_string(
              "The search query describing what kind of session content you're looking for (e.g., 'data visualization', 'data wrangling', 'mapping')"
            ),
            day = type_enum(
              values = c("Thursday", "Friday", "Saturday", "Sunday"),
              description = "Filter by conference day. ONLY use this if the user explicitly mentions a specific day. Do NOT pass a day value for general topic queries.",
              required = FALSE
            ),
            start_time = type_string(
              "Optional start time in HH:MM 24-hour format (e.g., '09:00'). Only sessions on or after this time will be returned.",
              required = FALSE
            ),
            end_time = type_string(
              "Optional end time in HH:MM 24-hour format (e.g., '17:00'). Only sessions on or before this time will be returned.",
              required = FALSE
            ),
            session_type = type_enum(
              values = c("Demo", "Panel", "Hands-on", "Networking", "Special"),
              description = "Filter by session format/type",
              required = FALSE
            ),
            skill_level = type_enum(
              values = c("Beginner", "Intermediate", "Advanced"),
              description = "Filter by skill level when user explicitly asks for beginner/advanced content.",
              required = FALSE
            ),
            top_k = type_integer(
              "Number of sessions to retrieve (default: 20)",
              required = FALSE
            )
          )
        )

        # ==== SYSTEM PROMPT ====
        # Instructions for the AI on how to search and respond
        system_prompt <- paste0(
          "You are a helpful assistant for NICAR 2026 conference sessions (March 2026, Thursday-Sunday). ",
          "Answer ONLY using information from the session database context - never use prior knowledge about the conference. \n\n",

          "TOOL SELECTION:\n",
          "- Topic queries (e.g., 'data visualization', 'Python'): use retrieve_sessions_filtered\n",
          "- Speaker/organization queries (e.g., 'Derek Willis', 'ProPublica'): use search_sessions_by_speaker\n\n",

          "RELEVANCE:\n",
          "Determine what each session is about based on its title and, if available, description. Include all relevant sessions.\n\n",

          "TIME HANDLING:\n",
          "Convert times to 24-hour HH:MM format. Morning: 08:00-12:00, Afternoon: 13:00-18:00.\n\n",

          "After finding sessions, call highlight_sessions with recommended titles. ",
          "Include: Title, Track, Day & Time, Room, Speakers, brief description. ",
          "If no sessions match, say so and suggest broadening the search. ",
          "End with a reminder to check the official schedule."
        )

        # Create chat ====
        # OpenAI gpt-5.1 didn't work very well
        # chat <- chat_openai(
        #   system_prompt = system_prompt,
        #   model = "gpt-5.1",
        #   params = params(temperature = 0.1),
        #   echo = "none"
        # )

        # Anthropic LLMs good but a bit pricey
        # chat <- chat_anthropic(
        #   system_prompt = system_prompt,
        #   model = "claude-sonnet-4-5-20250929",
        #   echo = "none"
        # )

        chat <- chat_google_gemini(
          system_prompt = system_prompt,
          # model = "gemini-3-flash-preview",
          model = "gemini-2.5-flash",
          echo = "none"
        )

        # ==== REGISTER TOOLS ====

        # Tool 1: Session retrieval for topic-based searches
        chat$register_tool(session_retrieval_tool)

        # Tool 2: Speaker search for finding sessions by presenter name/organization
        speaker_search_tool <- tool(
          search_sessions_by_speaker,
          name = "search_sessions_by_speaker",
          description = "Search for sessions by speaker name or affiliation using keyword matching. Use this when the user asks about a specific person, presenter, or organization (e.g., 'sessions by Sarah Cohen', 'ProPublica sessions').",
          arguments = list(
            speaker_name = type_string(
              "The speaker name, partial name, or organization/affiliation to search for"
            ),
            top_k = type_integer(
              "Number of sessions to retrieve (default: 10)",
              required = FALSE
            )
          )
        )
        chat$register_tool(speaker_search_tool)

        # Tool 2: Highlight sessions to enable "Show in Table" filter button
        # This allows users to filter the table to AI-recommended sessions
        highlight_sessions_tool <- tool(
          highlight_sessions,
          name = "highlight_sessions",
          description = "Update the session table to show only specific sessions. Call this AFTER retrieve_sessions_filtered with the Titles of sessions you are recommending. This enables a 'Show in Table' button for the user.",
          arguments = list(
            titles = type_array(
              items = type_string(),
              description = "List of exact session Titles to highlight in the table"
            )
          )
        )
        chat$register_tool(highlight_sessions_tool)

        chat_obj(chat) # chat object with all its values is now stored in the reactive value chat_obj, available to the rest of the Shiny app. This happens numerous other times
        message("Chat initialized successfully")
      },
      error = function(e) {
        message("Error initializing chat: ", e$message)
        # Fallback chat without tools
        chat <- chat_openai(
          system_prompt = "You are a helpful assistant for finding conference sessions. Say you don't have access to the session database right now.",
          model = "gpt-5.1",
          echo = "none"
        )
        chat_obj(chat)
      }
    )
  })

  # ==== HANDLERS FOR SAMPLE QUESTION BUTTONS ====
  # Clear previous AI recommendations before each new query
  observeEvent(input$ask_mapping, {
    ai_session_titles(NULL)
    handle_question_button("What sessions are about mapping?", chat_obj)
  })

  observeEvent(input$ask_thursday, {
    ai_session_titles(NULL)
    handle_question_button(
      "Are there any generative AI sessions happening Thursday morning?",
      chat_obj
    )
  })

  observeEvent(input$ask_spreadsheets, {
    ai_session_titles(NULL)
    handle_question_button(
      "Which sessions cover spreadsheets for beginners?",
      chat_obj
    )
  })

  # ==== HANDLER FOR FREE-FORM USER QUERIES ====
  observeEvent(input$session_chat_user_input, {
    req(input$session_chat_user_input)

    # Clear previous AI recommendations when user asks a new question
    ai_session_titles(NULL)

    chat <- chat_obj()
    if (is.null(chat)) {
      chat_append(
        "session_chat",
        "The chat system is not initialized yet. Please wait a moment and try again."
      )
      return()
    }

    user_input <- input$session_chat_user_input

    tryCatch(
      {
        response_stream <- chat$stream_async(user_input)
        chat_append("session_chat", response_stream) %>%
          then(function(result) {
            # Log token usage after stream completes
            usage <- extract_last_turn_usage(chat)
            if (!is.null(usage)) {
              log_api_usage(
                input_tokens = usage$input_tokens,
                output_tokens = usage$output_tokens,
                model = "gemini-2.5-flash",
                key_source = key_source()
              )
            }
          }) %>%
          catch(function(error) {
            chat_append(
              "session_chat",
              paste("Sorry, I encountered an error:", error$message)
            )
          })
      },
      error = function(e) {
        chat_append(
          "session_chat",
          paste("Sorry, I encountered an error:", e$message)
        )
      }
    )
  })

  # ==== FILTER BUTTON UI ====
  # Renders a button that appears after AI finds sessions
  # Shows "Show These X Sessions" when results exist (green)
  # Shows "Show All Sessions" when table is filtered (yellow)
  output$show_in_table_button <- renderUI({
    titles <- ai_session_titles()
    if (is.null(titles) || length(titles) == 0) {
      return(NULL)
    }

    current_filter <- table_filter()

    if (is.null(current_filter)) {
      # Show "Filter to these sessions" button
      div(
        style = "background: #e8f5e9; padding: 10px; border-radius: 8px; border: 1px solid #8FB339;",
        p(
          paste("Found", length(titles), "sessions"),
          style = "margin: 0 0 8px 0; font-size: 13px; color: #2B4C5E; font-weight: 500;"
        ),
        actionButton(
          "show_in_table",
          paste("Show These", length(titles), "Sessions in Table"),
          icon = icon("table"),
          class = "btn-conference",
          style = "width: 100%;"
        )
      )
    } else {
      # Show "Clear filter" button
      div(
        style = "background: #fff3cd; padding: 10px; border-radius: 8px; border: 1px solid #F5B800;",
        p(
          paste("Showing", length(current_filter), "filtered sessions"),
          style = "margin: 0 0 8px 0; font-size: 13px; color: #856404; font-weight: 500;"
        ),
        actionButton(
          "clear_filter",
          "Show All Sessions",
          icon = icon("times-circle"),
          class = "btn-warning",
          style = "width: 100%;"
        )
      )
    }
  })

  # ==== FILTER BUTTON CLICK HANDLERS ====

  # Handle "Show in Table" button - applies filter to table

  observeEvent(input$show_in_table, {
    table_filter(ai_session_titles())
  })

  # Handle "Show All" button - clears filter
  observeEvent(input$clear_filter, {
    table_filter(NULL)
  })

  # ==== RENDER TABLE WITH REACTABLE ====
  # Displays all sessions in an interactive, searchable table
  # Columns are ordered: Session Title, Day, Time, Speakers, Room, Skill Level, Track
  # When table_filter() is set, shows only the filtered sessions
  output$session_table <- renderReactable({
    data <- sessions_data()

    # Apply filter if set (from AI recommendations via "Show in Table" button)
    filter_titles <- table_filter()
    if (!is.null(filter_titles)) {
      data <- data |> filter(Title %in% filter_titles)
    }

    reactable(
      data,
      columns = list(
        # Primary column: Session Title (clickable for details)
        Title = colDef(
          name = "Session Title",
          minWidth = 280,
          class = "cell-title"
        ),
        # Day column with color coding (not sortable - would sort alphabetically)
        Day = colDef(
          name = "Day",
          width = 90,
          sortable = FALSE,
          class = function(value) paste0("day-", tolower(value))
        ),
        # Time column (not sortable - would sort as text incorrectly)
        Time = colDef(
          name = "Time",
          width = 85,
          sortable = FALSE,
          class = "cell-time"
        ),
        # Speakers column - now visible for easy scanning
        Speakers = colDef(
          name = "Speakers",
          minWidth = 180,
          class = "cell-speakers"
        ),
        # Room location
        Room = colDef(
          name = "Room",
          width = 100,
          class = "cell-room"
        ),
        # Skill level (Beginner, Intermediate, Advanced)
        SkillLevel = colDef(
          name = "Skill Level",
          width = 100,
          class = "cell-skill"
        ),
        # Track/category
        Track = colDef(
          name = "Track",
          width = 150,
          class = "cell-track"
        ),
        # Hidden but searchable columns
        Description = colDef(show = FALSE, searchable = TRUE),
        Date = colDef(show = FALSE),
        Time_24hr = colDef(show = FALSE),
        Cost = colDef(show = FALSE),
        Type = colDef(show = FALSE)
      ),
      # ==== DETAILS ROW (Expanded View) ====
      # Shows Description, Date, Type, and Cost when user clicks to expand a row
      # Speakers and Room are now visible in the table columns
      details = function(index) {
        session <- data[index, ]
        div(
          style = "padding: 20px; background: #f8f9fa; border-left: 4px solid #8FB339;",
          # Session title as header
          h4(
            session$Title,
            style = "color: #2B4C5E; margin-top: 0; font-weight: 600;"
          ),
          # Description first and prominent
          div(
            style = "margin-bottom: 15px; padding: 15px; background: white; border-radius: 5px;",
            p(
              session$Description,
              style = "line-height: 1.6; color: #333; margin: 0;"
            )
          ),
          # Metadata grid: Date, Type, Cost
          div(
            style = "display: grid; grid-template-columns: auto 1fr; gap: 10px; margin-bottom: 15px;",
            tags$span(strong("Date:"), style = "color: #666;"),
            tags$span(paste(session$Day, "-", session$Date)),
            tags$span(strong("Type:"), style = "color: #666;"),
            tags$span(
              if (is.na(session$Type) || session$Type == "") {
                "Not specified"
              } else {
                session$Type
              }
            ),
            tags$span(strong("Cost:"), style = "color: #666;"),
            tags$span(
              if (is.na(session$Cost) || session$Cost == "") {
                "Free / Included"
              } else {
                paste0("$", session$Cost)
              }
            )
          ),
          # Link to official schedule
          div(
            style = "margin-top: 15px; text-align: right;",
            a(
              "View in official schedule",
              href = "https://schedules.ire.org/nicar-2026/",
              target = "_blank",
              class = "btn btn-sm",
              style = "background-color: #8FB339; border-color: #8FB339; color: white;"
            )
          )
        )
      },
      searchable = TRUE,
      # Custom regex search method - allows patterns like "python|R" or "data.*viz"
      searchMethod = JS(
        "function(rows, columnIds, searchValue) {
        const pattern = new RegExp(searchValue, 'i')
        return rows.filter(function(row) {
          return columnIds.some(function(columnId) {
            return pattern.test(String(row.values[columnId]))
          })
        })
      }"
      ),
      language = reactableLang(
        searchPlaceholder = "Search (regex supported)"
      ),
      filterable = TRUE,
      highlight = TRUE,
      bordered = TRUE,
      striped = FALSE,
      pagination = TRUE,
      defaultPageSize = 12,
      showPageSizeOptions = TRUE,
      pageSizeOptions = c(12, 25, 50, 100),
      theme = table_theme
    )
  })

  # ==== UPDATE STATS ====
  # Shows session count, with filtered count when filter is active
  output$table_stats <- renderText({
    data <- sessions_data()
    filter_titles <- table_filter()

    # If filtered, show filtered count
    if (!is.null(filter_titles)) {
      paste0(
        "📊 Showing ",
        length(filter_titles),
        " of ",
        nrow(data),
        " sessions (filtered)"
      )
    } else {
      # Show full stats by day
      total_sessions <- nrow(data)
      thu_count <- sum(data$Day == "Thursday", na.rm = TRUE)
      fri_count <- sum(data$Day == "Friday", na.rm = TRUE)
      sat_count <- sum(data$Day == "Saturday", na.rm = TRUE)
      sun_count <- sum(data$Day == "Sunday", na.rm = TRUE)

      paste0(
        "📊 ",
        total_sessions,
        " Total Sessions\n",
        "Thu: ",
        thu_count,
        " | Fri: ",
        fri_count,
        " | Sat: ",
        sat_count,
        " | Sun: ",
        sun_count
      )
    }
  })
}

shinyApp(ui = ui, server = server)
