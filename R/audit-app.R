# Main shiny app
shiny_bg <- function(path, port) {
 # main app
  options(shiny.port = port)
  shiny::runApp(path)
}

# Start recorder
recorder_bg <- function(port) {
  shinyloadtest::record_session(
    target_app_url = sprintf("http://127.0.0.1:%s", port),
    host = "127.0.0.1",
    port = 8600,
    output_file = "recording.log",
    open_browser = FALSE
  )
}

start_r_bg <- function(fun, path = NULL, port = 3515) {
 
  # remove NULL elements
  args <- Filter(Negate(is.null), list(path = path, port = port))

  process <- callr::r_bg(
    func = fun,
    args = args,
    stderr= "",
    stdout = ""
  )

  while (any(is.na(pingr::ping_port("127.0.0.1", 3515)))) {
    message("Waiting for Shiny app to start...")
    Sys.sleep(0.1)
  }

  attempt::stop_if_not(
    process$is_alive(),
    msg = "Unable to launch the subprocess"
  )

  process
}

record_loadtest <- function(path, timeout = 15, workers = 5) {
  message("\n---- BEGIN LOAD-TEST ---- \n")
  # start app + recorder
  target <- start_r_bg(shiny_bg, path = path)
  recorder <- start_r_bg(recorder_bg)

  # start headless chrome (points to recorder!).
  # AppDriver also support remote urls.
  chrome <- shinytest2::AppDriver$new(
    "http://127.0.0.1:8600",
    load_timeout = timeout * 1000
  )

  chrome$set_inputs(mu = 4, timeout_ = timeout * 1000)

  # clean
  chrome$stop()
  # needed to avoid
  # java.lang.IllegalStateException: last event in log not a
  # WS_CLOSE (did you close the tab after recording?)
  Sys.sleep(2)

  # shinycannon (maybe expose other params later ...)
  target_url <- "http://127.0.0.1:3515"
  system(
    sprintf(
      "shinycannon recording.log %s --workers %s --loaded-duration-minutes 2 --output-dir run1",
      target_url, workers
    )
  )

  target$kill()

  # Treat data and generate report
  df <- shinyloadtest::load_runs("run1")
  shinyloadtest::shinyloadtest_report(
    df,
    "public/index.html",
    self_contained = TRUE,
    open_browser = FALSE
  )
}
