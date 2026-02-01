# NICAR 2026 Session Explorer

This is an AI-powered conference session discovery tool for NICAR 2026 (National Institute for Computer-Assisted Reporting), taking place March 5-8, 2026 in Indianapolis.

Anthropic's Claude wrote much of the Shiny app code. The ragnar data processing portion was written by me in partnership with Claude, and improved by ragnar package author Tomasz Kalinowski. For more on this, check out my InfoWorld article [How to create your own RAG applications in R](https://www.infoworld.com/article/4020484/generative-ai-rag-comes-to-the-r-tidyverse.html) and my [Workshop for Ukraine ($20 donation)](https://sites.google.com/view/dariia-mykhailyshyna/main/r-workshops-for-ukraine#h.nxnvhskykjzg)

Most of the docs below were written by Claude:

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

Note that Google has a pretty generous free tier for its Gemini 3 Flash Preview LLM used in the chatbot. Set your key as an environment variable:

```r
# Option 1: Set in .Renviron file
GEMINI_API_KEY=your-key-here

# Option 2: Set in R session
Sys.setenv(GEMINI_API_KEY = "-your-key-here")
```

If no key is set, the app should prompt you to enter one at startup.

## Setup

### 1. Build the Data Store
Run the data processing script to download session data and create the ragnar vector store:

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
- "What sessions is Simon Willison presenting?"
- "Show me beginner-level hands-on sessions"

### Filter Button
After the AI finds sessions, a green **"Show These X Sessions in Table"** button appears. Click it to filter the table to just those sessions. A yellow **"Show All Sessions"** button lets you clear the filter.

### Table
- **Search**: Use the search box to filter across all columns
- **Sort**: Click column headers to sort
- **Expand**: Click the triangle to see full session details
- **Columns**: Session Title, Day, Time, Speakers, Room, Skill Level, Track

## How It Works

1. **Data Processing**: Session data is downloaded from AWS S3, processed into markdown, and embedded using OpenAI's text-embedding-3-small model via ragnar.

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
- **AI**: Google Gemini for chat, OpenAI text-embedding-3-small for embeddings

## Disclaimer

This is an **unofficial** app. AI can make mistakes - always verify session details on the [official NICAR schedule](https://schedules.ire.org/nicar-2026/).
