# NICAR 2026 Session Explorer

This repo contains code for an R Shiny app for exploring the NICAR 2026 data journalism conference schedule. It features a chatbot that answers natural language questions about the schedule, as well as a searchable table with that info.

This year's NICAR (National Institute for Computer-Assisted Reporting) conference takes place March 5-8 in Indianapolis.

Anthropic's Claude wrote much of the Shiny app code. The rest was written by me in partnership with Claude, and improved by ragnar package author Tomasz Kalinowski. For more on this, check out my InfoWorld article [How to create your own RAG applications in R](https://www.infoworld.com/article/4020484/generative-ai-rag-comes-to-the-r-tidyverse.html) and my [Workshop for Ukraine ($20 donation)](https://sites.google.com/view/dariia-mykhailyshyna/main/r-workshops-for-ukraine#h.nxnvhskykjzg)

The documentation below was written by Claude and lightly edited by me:

## Features

- **AI-Powered Chat**: Ask natural language questions to find relevant sessions
- **Topic Search**: Semantic search for sessions by topic, skill level, or session type
- **Speaker Search**: Keyword-based search for sessions by presenter name or organization
- **Filter Button**: After AI finds sessions, click to filter the table to just those results
- **Interactive Table**: Browse all sessions with sorting, filtering, and search
- **Expandable Details**: Click any session to see full description, date, type, and cost
- **Color-Coded Days**: Visual distinction between Thursday, Friday, Saturday, and Sunday sessions

## Requirements

### R Version
- R 4.1.0 or higher recommended

### Required Packages
```r
install.packages(c("shiny", "bslib", "reactable", "dplyr", "arrow", "htmltools", "promises", "lubridate", "DBI"))

# Install from GitHub (development versions)
pak::pak("posit-dev/shinychat")
pak::pak("posit-dev/ellmer")
pak::pak("posit-dev/ragnar")
```

### API Key
You need a Google Gemini API key for the chat functionality if you run this locally. If you want to generate the ragnar data store, you'll also need an OpenAI key for the text embeddings. 

Google has a free tier for its Gemini 2.5 Flash LLM used in the chatbot, so you can try it out locally for free. Set your key as an environment variable:

```r
# Option 1: Set in .Renviron file
GEMINI_API_KEY=your-key-here

# Option 2: Set in R session
Sys.setenv(GEMINI_API_KEY = "-your-key-here")
```

If no key is set, the app should prompt you to enter one at startup.

If you want to generate the data store from scratch, you'll also need an OpenAI API key for the embeddings.

## Setup

### 1. Build the Data Store
If you don't want to use the existing data in this repo, you can run the data processing script to download session data and create the ragnar vector store:

```r
source("01_get_and_process_data.R")
```

This creates:
- `nicar_2026_sessions.duckdb` - Ragnar vector store with embeddings
- `sessions_info_for_app.parquet` - Session data for the table display

### 2. Run the App
```r
shiny::runApp()
```

Or in RStudio, open `app.R` and click "Run App".

### Note on Usage Logging

The app has optional API usage logging for cost monitoring, but **logging is disabled by default**. If `NICAR_CHATBOT_LOG_USAGE` isn't in your environment, logging is simply skipped - you don't need to set anything and the app won't error.

If you want to enable logging (e.g., for your own deployment), set `NICAR_CHATBOT_LOG_USAGE=TRUE` in your `.Renviron` file. See [logging.md](logging.md) for full setup instructions including cloud deployment with Supabase.

**Only token usage and calculated costs are logged.* No information about queries, users, user API addresses, or API keys (if the app is set up to ask people to enter their own keys) is EVER saved.

## File Structure

| File | Description |
|------|-------------|
| `app.R` | Main Shiny application with UI and server logic |
| `helpers_ui.R` | UI components, styling, and themes |
| `helpers_server.R` | Server helper functions for chat handling |
| `01_get_and_process_data.R` | Data processing pipeline (run once to set up) |
| `nicar_2026_sessions.duckdb` | Ragnar vector store with session embeddings |
| `sessions_info_for_app.parquet` | Session data for table display |
| `claude_explains_shiny_app.md` | Detailed code explanation |

## Usage

### Chat Interface
Ask questions like:
- "What sessions are about data visualization?"
- "Are there any Python sessions on Friday afternoon?"
- "What sessions is Simon Willison leading?"
- "Show me beginner-level hands-on sessions"

### Filter Button
After the AI finds sessions, a green **"Show These X Sessions in Table"** button appears. Click it to filter the table to just those sessions. A yellow **"Show All Sessions"** button lets you clear the filter.

### Table
- **Search**: Use the search box to filter across all columns (regular expressions are supported in the global search but not the column filter boxes)
- **Expand**: Click the triangle to see full session details
- **Columns**: Session Title, Day, Time, Speakers, Room, Skill Level, Track

## How It Works

1. **Data Processing**: Session data is downloaded from the [conference website](https://schedules.ire.org/nicar-2026/), processed into markdown, and embedded using OpenAI's text-embedding-3-small model via the ragnar R package.

2. **RAG Search**: The app uses ragnar's search capabilities:
   - Vector Similarity Search (VSS) for semantic matching
   - BM25 for keyword matching

3. **Tool Calling**: The AI has three tools:
   - `retrieve_sessions_filtered` - Topic-based semantic search
   - `search_sessions_by_speaker` - Keyword search for speakers/orgs
   - `highlight_sessions` - Enables the filter button

4. **Two-Tool Pattern**: Search tools find sessions, then `highlight_sessions` is called to enable table filtering. This separates search logic from UI updates.

## Credits

- **Conference**: [NICAR 2026](https://www.ire.org/training/conferences/nicar-2026/) by IRE (Investigative Reporters and Editors)
- **Packages**: [shinychat](https://github.com/posit-dev/shinychat), [ellmer](https://github.com/posit-dev/ellmer), [ragnar](https://github.com/posit-dev/ragnar) by Posit
- **AI**: Google Gemini for chat, OpenAI text-embedding-3-small for embeddings, Claude for writing much of the code, Sharon Machlis for being the project manager, editor, and code reviewer 😅

## Disclaimer

This is an **unofficial** app. AI can make mistakes - and the schedule may have last-minute changes. Always verify session details on the [official NICAR schedule](https://schedules.ire.org/nicar-2026/).
