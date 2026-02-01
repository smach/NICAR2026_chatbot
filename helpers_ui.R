header_content <- div(
  class = "header-content",
  h1(
    "NICAR 2026 Session Explorer",
    style = "margin: 0; font-weight: 300; font-size: 2.5rem;"
  ),
  h3(
    "AI-Powered Conference Session Discovery",
    style = "margin: 10px 0; font-weight: 300; opacity: 0.9;"
  ),
  p(
    "📍 Indianapolis • March 5-8, 2026",
    style = "margin: 10px 0; font-size: 16px; opacity: 0.8;"
  ),
  p(
    "⚠️ AI can make mistakes - always verify details on the ",
    a(
      "official schedule",
      href = "https://schedules.ire.org/nicar-2026/",
      target = "_blank",
      style = "color: #F5B800; font-weight: bold; text-decoration: underline;"
    ),
    style = "margin: 15px 0; font-size: 14px;"
  )
)

chatbot_welcome <- "Welcome to this NICAR 2026 UNOFFICIAL app! 🎉 I'm here to help you find conference sessions during times when multiple activities are going on at once. I can search by topic, day, time, or level. What interests you?"


custom_style <- HTML(
  "
      /* ---------- HEADER ---------- */
      .header-section {
        background: #2B4C5E;      /* solid dark color */
        color: #ffffff;
        padding: 20px;
        margin: -15px -15px 15px -15px;
        text-align: center;        /* <-- centering */
      }

      /* If the .header-content wrapper is still used, keep it centered too */
      .header-content { text-align: center; }

      /* Hide the old diamond overlay, just in case */
      .geometric-bg { display: none !important; }

      /* ---------- IMPROVED CHAT SIDEBAR ---------- */
      .chat-sidebar { 
        background: #ffffff !important;  /* White background for better contrast */
        border: 1px solid #e0e0e0;
        border-radius: 5px;
        padding: 10px;
      }
      
      /* Assistant messages - white background with dark text */
      .shinychat-message-assistant .shinychat-message-content {
        background-color: #ffffff !important;
        color: #2B4C5E !important; /* Ensures readable text */
        border: 1px solid #d0d0d0 !important;
        padding: 15px !important;
        border-radius: 8px !important;
        margin: 10px 0 !important;
        font-size: 15px !important;
        line-height: 1.7 !important;
      }
      
      /* User messages - very light background with dark text */
      .shinychat-message-user .shinychat-message-content {
        background-color: #f0f0f0 !important;
        color: #2B4C5E !important; /* Ensures readable text */
        border: 1px solid #d0d0d0 !important;
        padding: 15px !important;
        border-radius: 8px !important;
        margin: 10px 0 !important;
        font-size: 15px !important;
        line-height: 1.7 !important;
      }
      
      /* Make sure headings in chat are also dark */
      .shinychat-messages h1,
      .shinychat-messages h2,
      .shinychat-messages h3,
      .shinychat-messages h4,
      .shinychat-messages h5,
      .shinychat-messages h6 {
        color: #2B4C5E !important;
        font-weight: 600 !important;
      }
      
      /* Ensure lists are readable */
      .shinychat-messages ul,
      .shinychat-messages ol {
        color: #2B4C5E !important;
        padding-left: 20px !important;
      }
      
      .shinychat-messages li {
        color: #2B4C5E !important;
        margin-bottom: 8px !important;
      }
      
      /* ---------- SAMPLE QUESTION BUTTONS ---------- */
      .btn-sample-questions {
        width: 100%; 
        margin-bottom: 8px; 
        white-space: normal; 
        text-align: left;
        background-color: #2B4C5E !important;  /* Dark background */
        color: #ffffff !important;              /* White text */
        border: 2px solid #2B4C5E !important;
        padding: 10px 15px;
        font-size: 14px;
        font-weight: 500;
        transition: all 0.2s ease;
      }
      
      .btn-sample-questions:hover {
        background-color: #1a2f3d !important;  /* Darker on hover */
        border-color: #1a2f3d !important;
        color: #ffffff !important;
        transform: translateY(-1px);
        box-shadow: 0 2px 4px rgba(0,0,0,0.2);
      }
      
      .btn-sample-questions:focus {
        outline: 3px solid #8FB339 !important;
        outline-offset: 2px;
      }
      
      .btn-sample-questions:last-child {
        margin-bottom: 0;
      }
      
      /* ---------- OTHER BUTTONS ---------- */
      .btn-conference {
        background-color: #8FB339;
        border-color:     #8FB339;
        color: #ffffff;
        font-weight: 500;
      }
      .btn-conference:hover {
        background-color: #7A9A2E;
        border-color:     #7A9A2E;
      }

      /* Warning button for Show All Sessions (clear filter) */
      .btn-warning {
        background-color: #F5B800;
        border-color:     #F5B800;
        color: #2B4C5E;
        font-weight: 500;
      }
      .btn-warning:hover {
        background-color: #D9A300;
        border-color:     #D9A300;
        color: #2B4C5E;
      }

      /* ---------- STATS BOX ---------- */
      .stats-box {
        background: #A8C6C4;
        color: #2B4C5E;
        padding: 10px;
        border-radius: 5px;
        font-weight: 600;
      }
      
      /* ---------- SECTION HEADERS ---------- */
      h5 {
        color: #2B4C5E !important;
        font-weight: 600 !important;
      }

      /* ---------- REACTABLE CELL STYLES ---------- */
      /* Day column color classes */
      .day-thursday { color: #8FB339; font-weight: 600; }
      .day-friday { color: #F5B800; font-weight: 600; }
      .day-saturday { color: #4A90D9; font-weight: 600; }
      .day-sunday { color: #9B59B6; font-weight: 600; }

      /* Other pre-computed cell styles */
      .cell-title { font-weight: 600; color: #2B4C5E; white-space: normal; line-height: 1.4; }
      .cell-speakers { font-size: 13px; color: #555; white-space: normal; line-height: 1.3; }
      .cell-room { font-size: 14px; color: #666; }
      .cell-skill { font-size: 13px; color: #666; }
      .cell-track { color: #666; }
      .cell-time { font-size: 14px; }
      
      /* ---------- CHAT INPUT ---------- */
      .shiny-input-container input[type='text'] {
        border: 2px solid #e0e0e0;
        font-size: 14px;
        padding: 8px 12px;
      }
      
      .shiny-input-container input[type='text']:focus {
        border-color: #8FB339;
        outline: none;
        box-shadow: 0 0 0 3px rgba(143, 179, 57, 0.1);
      }
    "
)


custom_theme <- bs_theme(
  bootswatch = "flatly",
  primary = "#8FB339",
  bg = "#ffffff", # Changed from #f8f9fa to white for better contrast
  fg = "#2B4C5E",
  base_font = font_google("Source Sans Pro")
)

table_theme <- reactableTheme(
  searchInputStyle = list(
    width = "100%",
    backgroundColor = "#ffffff", # White background for search
    border = "2px solid #e0e0e0",
    borderRadius = "4px",
    padding = "8px 12px",
    fontSize = "14px"
  ),
  headerStyle = list(
    background = "#A8C6C4",
    color = "#2B4C5E",
    fontWeight = "600",
    fontSize = "14px"
  ),
  rowStyle = list(
    cursor = "pointer",
    "&:hover" = list(background = "#f0f8f6")
  )
)
