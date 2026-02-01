# Claude Explains This Project's Shiny App

## Overview

This Shiny app creates an interactive conference session discovery tool that allows users to chat with an AI assistant to find relevant sessions at NICAR 2026. It combines:

-   **shinychat** for the chat UI interface

-   **ellmer** to connect to OpenAI's GPT model with tool calling

-   **ragnar** for RAG functionality to search through session data (both semantic and keyword search)

-   **reactable** for an interactive, filterable session table

### Key Features

1. **Dual Search Capability**: Topic-based semantic search and speaker/organization keyword search
2. **Filter Button**: After AI finds sessions, users can filter the table to show only recommended sessions
3. **Interactive Table**: Columns for Session Title, Day, Time, Speakers, Room, Skill Level, Track
4. **Expandable Details**: Click any row to see Description, Date, Type, and Cost

## Code Breakdown

### 1. **app.R - Main Application Structure**

#### Initial Setup

```
library(shiny) library(shinychat) library(ellmer) library(ragnar) # ... other libraries
```

Loads necessary packages and helper files containing UI components and server functions.

#### UI Structure

The UI uses `bslib::page_fillable()` with:

-   **Header Section**: Conference branding and title (defined in helpers_ui.R)

-   **Sidebar**: Contains the chat interface with:

    -   Three sample question buttons for common queries

    -   A `chat_ui()` component from shinychat that creates the chat interface

-   **Main Panel**: Displays all sessions in a searchable, filterable `reactable` table

### 2. **Server Logic**

#### Data Loading

```         
sessions_data <- reactive({   read_parquet("session_info_for_app.parquet") })
```

Loads conference session data from a Parquet file for the table.

#### RAG Store Connection

```         
store <- ragnar_store_connect("posit_conf_sessions.duckdb", read_only = TRUE)
```

Connects to a DuckDB database containing embedded session data. This store has already been populated with session information and their embeddings for semantic search.

#### Core Retrieval Functions

The app has two search functions, each optimized for different query types:

**1. Topic-based Search (Semantic + Keyword Hybrid)**
```r
retrieve_sessions_filtered <- function(query, day = NULL, start_time = NULL,
                                        end_time = NULL, session_type = NULL,
                                        skill_level = NULL, top_k = 20)
```

This function:
-   Takes a search query and optional filters (day, time range, type, skill level)
-   Builds filter expressions for the database query using rlang
-   Uses `ragnar_retrieve_vss()` similarity search
-   Returns relevant sessions with their details

**2. Speaker/Organization Search (Keyword-based)**
```r
search_sessions_by_speaker <- function(speaker_name, top_k = 10)
```

This function:
-   Uses `ragnar_retrieve_bm25()` for pure keyword matching
-   Better for finding exact speaker names or organization affiliations
-   Uses `conjunctive = FALSE` to allow partial matches

#### Tool Registration for AI (Three Tools)

The app uses a "multi-tool" pattern with three registered tools:

**Tool 1: Topic Search**
```r
session_retrieval_tool <- tool(
  retrieve_sessions_filtered,
  "Retrieve conference session information based on content query..."
)
```

**Tool 2: Speaker Search**
```r
speaker_search_tool <- tool(
  search_sessions_by_speaker,
  "Search for sessions by speaker name or affiliation using keyword matching..."
)
```

**Tool 3: Highlight Sessions (for Filter Button)**
```r
highlight_sessions_tool <- tool(
  highlight_sessions,
  "Update the session table to show only specific sessions..."
)
```

The `highlight_sessions` function sets a reactive value (`ai_session_titles`) that enables a "Show in Table" button. This is the "two-tool pattern" - search tools find results, then `highlight_sessions` enables table filtering.

#### Chat Initialization

``
chat <- chat_google_gemini(
  system_prompt = system_prompt, # instructions for the LLM
  model = "gemini-3-flash-preview",
  echo = "none"
)
chat$register_tool(session_retrieval_tool)
chat$register_tool(speaker_search_tool)
chat$register_tool(highlight_sessions_tool)
```

Creates a Goiogle Gemini chat instance with:

-   A detailed system prompt explaining when to use each search tool
-   Three registered tools: topic search, speaker search, and highlight
-   Instructions to ALWAYS call `highlight_sessions` after finding results

#### State Management for Filter Button

```r
ai_session_titles <- reactiveVal(NULL)  # Titles from AI's recommendation
table_filter <- reactiveVal(NULL)       # Applied filter for table
```

The filter button workflow:
1. User asks a question
2. AI searches and calls `highlight_sessions(titles)`
3. `ai_session_titles` is set, triggering the filter button to appear
4. User clicks "Show These X Sessions in Table"
5. `table_filter` is set, filtering the reactable
6. User can click "Show All Sessions" to clear the filter

#### User Interaction Handlers

**Sample Questions**: Three predefined buttons trigger common queries:

```         
observeEvent(input$ask_wrangling, {   handle_question_button("What sessions are about data wrangling?", chat_obj) })
```

**Free-form Chat**: Handles user-typed questions:

```         
observeEvent(input$session_chat_user_input, {   response_stream <- chat$stream_async(user_input)   chat_append("session_chat", response_stream) })
```

Uses async streaming to provide real-time responses without blocking the UI.

#### Session Table

```r
output$session_table <- renderReactable({
  data <- sessions_data()

  # Apply filter if set (from AI recommendations)
  filter_titles <- table_filter()
  if (!is.null(filter_titles)) {
    data <- data |> filter(Title %in% filter_titles)
  }

  reactable(data, columns = list(...))
})
```

Creates an interactive table with:

-   **Visible columns** (in order): Session Title, Day, Time, Speakers, Room, Skill Level, Track
-   **Hidden but searchable**: Description, Date, Cost, Type, text
-   Expandable rows showing: Description (prominent), Date, Type, Cost
-   Color-coded days (Thursday=green, Friday=yellow, Saturday=blue, Sunday=purple)
-   Links to the official NICAR schedule
-   Global table search bar includes regular expression capability
-   Filtering support when AI recommends sessions

### 3. **Helper Files**

#### helpers_server.R

Contains `handle_question_button()` which:

-   Retrieves the chat object

-   Sends queries asynchronously

-   Handles errors gracefully

-   Appends responses to the chat UI

#### helpers_ui.R

Defines:

-   **header_content**: Conference branding and warnings

-   **chatbot_welcome**: Initial greeting message

-   **custom_style**: CSS for visual styling

-   **custom_theme**: Bootstrap theme configuration

-   **table_theme**: Reactable table styling

## How RAG Works in This App

1.  **Embedding Storage**: Conference sessions are pre-embedded and stored in DuckDB via ragnar

2.  **Query Processing**: When users ask questions, the AI:

    -   Interprets the natural language query

    -   Calls the retrieval tool with appropriate parameters

    -   Converts time references (e.g., "morning") to specific times

3.  **Semantic Search**: ragnar performs vector similarity search to find relevant sessions

4.  **Filtering**: Additional filters (day, time) are applied at the database level

5.  **Response Generation**: The AI formats the retrieved sessions into a helpful response

## Key Features

-   **Async Operations**: Uses promises and async generators to prevent UI blocking

-   **Error Handling**: Graceful fallbacks if API keys or database connections fail

-   **Smart Time Parsing**: Converts natural language time references to 24-hour format

-   **Dual Interface**: Both chat-based discovery and table-based browsing

-   **Context Awareness**: AI only answers based on actual session data, not general knowledge

-   **Dual Search**: Topic-based semantic search AND speaker/organization keyword search

-   **Filter Button**: "Show in Table" button appears after AI finds sessions, allowing users to filter the table

-   **Two-Tool Pattern**: Separates search (finding sessions) from highlighting (enabling table filter)

This architecture aims to create a powerful, user-friendly interface for conference attendees to discover relevant sessions through natural language queries while maintaining the ability to browse and filter all sessions.
