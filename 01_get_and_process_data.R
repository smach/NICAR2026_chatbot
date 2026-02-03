library(dplyr)
library(ragnar)
library(lubridate)

data_url <- "https://ire-nicar-conference-schedules.s3.us-east-2.amazonaws.com/nicar-2026/nicar-2026-schedule.csv"
data_file <- "nicar2026_schedule_r_download.csv"
if (file.exists(data_file)) {
  file.remove(data_file)
}
download.file(data_url, data_file, mode = "wb")

sessions_df <- rio::import(data_file) |>
  mutate(
    session_id = as.character(session_id),
    recorded = as.character(recorded),
    date = as.character(date),
    day = format(as.Date(date), "%A") # Add a column for day of week
  )


# I'm going to add a text column with all the information I'd like:
# The session title, speaker, date, starting time, room, level, day, tracks, type, skill_level, cost, recorded, and description.

# I've added ### before the title because that signifies 'level 3 header' in markdown. Markdown is the preferred ragnar format and we'll be creating a single markdown document next.

sessions_df <- sessions_df |>
  mutate(
    text = paste0(
      "### ",
      title,
      "\n\n",
      "Speaker: ",
      speakers,
      "\n",
      "Date: ",
      date,
      "\n",
      "Time: ",
      start_time,
      "\n",
      "Room: ",
      room,
      "\n",
      "Type: ",
      type,
      "\n",
      "Skill Level: ",
      skill_level,
      "\n",
      "Track: ",
      tracks,
      "\n",
      "Cost: ",
      ifelse(is.na(cost), "", paste0("$", cost)),
      "\n\n",
      "Recorded:",
      recorded,
      "\n",
      "Description: ",
      description,
      "\n\n" # Changed from "\n" to "\n\n"
    )
  )

# Then use more separation when collapsing
sessions_markdown <- paste(sessions_df$text, collapse = "\n\n")


# This creates the single markdown doc
sessions_markdown <- paste(sessions_df$text, collapse = "\n\n")

# Save it to use later
cat(sessions_markdown, file = "sessions.md")

# ragnar will be happiest if we turn that markdown string into a ragnar MarkdownDocument object. If you use ragnar's read_as_markdown() to parse things like a URL for a Web page, the result is automatically a MarkdownDocument object. But since we already have markdown, we didn't need that part.

sessions_markdown_doc <- MarkdownDocument(
  text = sessions_markdown,
  origin = "sessions.md"
)

class(sessions_markdown_doc)

# We don't actually need to chunk, this creates an already chunked table
sessions_chunks <- sessions_df |>
  transmute(
    text,
    Title = title,
    Speakers = speakers,
    Description = description,
    Date = date,
    Time = start_time,
    Room = room,
    Track = tracks,
    SkillLevel = skill_level,
    Cost = cost,
    Day = day,
    Type = type,
    Recorded = recorded,
    Time_24hr = format(parse_date_time(start_time, "I:M p"), "%H:%M"),
    context = title
  ) |>
  arrange(Date, Time_24hr)

glimpse(sessions_chunks)


# I woud like to have columns for Title, Description, Speakers, Date, Time, Time_24hr (for properly sorting things like 11 am and 1 pm),  Room, Parent (the track an individual session is part of),  URL, Day (Wednesday or Thursday) in my data:

sessions_metadata <- sessions_df |>
  select(
    Title = title,
    # Description = "TO COME",
    Speakers = speakers,
    Date = date,
    Time = start_time,
    Room = room,
    Track = tracks,
    SkillLevel = skill_level,
    Cost = cost,
    Day = day,
    Type = type,
    Recorded = recorded
  ) |>
  mutate(
    Time_24hr = parse_date_time(Time, "I:M p"),
    Time_24hr = format(Time_24hr, "%H:%M"),
    Date = as.character(Date) # I've had issues with R dates in duckdb data stores
  )


sessions_chunks <- sessions_chunks |>
  arrange(
    Date,
    Time_24hr
  )

# I'd like a version of this to display in a Shiny app table, separate from my chatbot
# NOTE: We exclude 'text' column here - it's only needed for the ragnar store, not the table
# This keeps the parquet file smaller and the table loads faster
# Column order matches desired table display order
sessions_info_for_app <- sessions_chunks |>
  select(
    Title,
    Day,
    Time,
    Speakers,
    Room,
    SkillLevel,
    Track,
    Description,
    Date,
    Time_24hr,
    Cost,
    Recorded,
    Type
  )
# Turn back to Boolean just for app, R table can handle but don't think DuckDB can understand R Boolean
sessions_info_for_app <- sessions_info_for_app |>
  mutate(
    Recorded = if_else(Recorded == "TRUE", TRUE, FALSE)
  )
rio::export(sessions_info_for_app, "sessions_info_for_app.parquet")

# I want  metadata columns in the store in addition to the default start, end, context, text, and embeddings, so I'm defining them here:

my_extra_columns <- data.frame(
  Title = character(),
  Description = character(),
  Speakers = character(),
  Date = character(),
  Time = character(),
  Room = character(),
  Track = character(),
  SkillLevel = character(),
  Cost = integer(),
  Type = character(),
  Time_24hr = character(),
  Day = character(),
  Recorded = character()
)

store_file_location <- "nicar_2026_sessions.duckdb"

# Creates an empty store, including all the extra columns
# Added overwrite = TRUE to overwrite my existing data store.
store <- ragnar_store_create(
  store_file_location,
  embed = \(x) ragnar::embed_openai(x, model = "text-embedding-3-small"),
  extra_cols = my_extra_columns,
  overwrite = TRUE,
  version = 1
)

# Inserts the chunks into the store
ragnar_store_insert(store, sessions_chunks)

# Don't forget this part! Build the store index
ragnar_store_build_index(store)

# You can inspect the store via the built-in Web inspector
# ragnar_store_inspect(store)

# Or turn it into a conventional R tibble / data frame and inspect that way
chunks_in_the_store <- tbl(store@con, "chunks") |>
  select(-embedding) |>
  collect()

# May need for Windows
DBI::dbExecute(store@con, "INSTALL fts;")
DBI::dbExecute(store@con, "LOAD fts;")

# 1 way to disconnect from the store, using the DBI package
DBI::dbDisconnect(store@con, shutdown = TRUE)
