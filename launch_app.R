# launch_app.R
# Starts Biblioshiny from the bundled portable R install.
#
# Update policy:
#   - CRAN Windows binaries only (no source builds => no Rtools for users)
#   - Never installs from GitHub (source builds often need Rtools)
#   - Newer packages install into a writable user library and take precedence
#   - If offline / update fails, the baked-in copy still launches
#
#
# Lifecycle:
#   Closing the browser session stops the Shiny server (after a short delay),
#   so R does not keep locking files after the user is done.

cran_repo <- "https://cloud.r-project.org"
app_name <- "Bibliometrix Desktop"

# Check CRAN for a newer bibliometrix binary when online, at most weekly.
enable_runtime_updates <- TRUE
update_check_interval_days <- 7L

user_lib <- Sys.getenv("R_LIBS_USER", unset = NA_character_)
if (is.na(user_lib) || !nzchar(user_lib)) {
  local_app <- Sys.getenv("LOCALAPPDATA", unset = NA_character_)
  if (!is.na(local_app) && nzchar(local_app)) {
    user_lib <- file.path(local_app, app_name, "R_library")
  } else {
    user_lib <- file.path(path.expand("~"), ".bibliometrix-desktop", "R_library")
  }
}
dir.create(user_lib, recursive = TRUE, showWarnings = FALSE)
app_data_dir <- dirname(user_lib)
dir.create(app_data_dir, recursive = TRUE, showWarnings = FALSE)
cran_check_stamp_path <- file.path(app_data_dir, "cran_update_check.txt")

# User library first so CRAN updates override the baked copy.
portable_libs <- .libPaths()
.libPaths(c(user_lib, portable_libs))

options(
  repos = c(CRAN = cran_repo),
  pkgType = "binary",
  install.packages.compile.from.source = "never",
  shiny.launch.browser = TRUE
)

message("Library paths:")
message(paste(" -", .libPaths(), collapse = "\n"))

installed_bibliometrix_version <- function() {
  if (!requireNamespace("bibliometrix", quietly = TRUE)) {
    return(NA_character_)
  }
  as.character(utils::packageVersion("bibliometrix"))
}

cran_bibliometrix_binary_version <- function() {
  ap <- utils::available.packages(
    repos = cran_repo,
    type = "binary",
    filters = c("R_version", "OS_type", "subarch", "duplicates")
  )
  if (!"bibliometrix" %in% rownames(ap)) {
    return(NA_character_)
  }
  ap["bibliometrix", "Version"]
}

should_run_cran_update_check <- function() {
  if (!file.exists(cran_check_stamp_path)) {
    return(TRUE)
  }
  stamp <- tryCatch(
    trimws(readLines(cran_check_stamp_path, n = 1L, warn = FALSE)),
    error = function(e) NA_character_
  )
  if (length(stamp) < 1L || is.na(stamp) || !nzchar(stamp[[1L]])) {
    return(TRUE)
  }
  stamp_clean <- sub("Z$", "", stamp[[1L]], ignore.case = TRUE)
  last <- tryCatch(
    as.POSIXct(stamp_clean, format = "%Y-%m-%dT%H:%M:%S", tz = "UTC"),
    error = function(e) as.POSIXct(NA)
  )
  if (is.na(last)) {
    return(TRUE)
  }
  age_days <- as.numeric(difftime(Sys.time(), last, units = "days"))
  is.na(age_days) || age_days >= update_check_interval_days
}

record_cran_update_check <- function() {
  tryCatch(
    {
      writeLines(
        strftime(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
        cran_check_stamp_path
      )
    },
    error = function(e) {
      message("Could not write CRAN check stamp: ", conditionMessage(e))
    }
  )
  invisible(NULL)
}

update_bibliometrix_from_cran <- function() {
  message("Checking CRAN for a newer bibliometrix Windows binary...")
  tryCatch({
    current <- installed_bibliometrix_version()
    latest <- cran_bibliometrix_binary_version()

    if (is.na(latest)) {
      message("No CRAN binary listed for this R version; keeping installed copy.")
      record_cran_update_check()
      return(invisible(FALSE))
    }

    if (!is.na(current) && package_version(latest) <= package_version(current)) {
      message("bibliometrix is up to date (", current, ").")
      record_cran_update_check()
      return(invisible(FALSE))
    }

    message(
      "Updating bibliometrix",
      if (!is.na(current)) paste0(" from ", current),
      " to ", latest, " (CRAN binary)..."
    )

    utils::install.packages(
      "bibliometrix",
      lib = user_lib,
      repos = cran_repo,
      type = "binary",
      dependencies = c("Depends", "Imports", "LinkingTo", "Suggests")
    )

    new_ver <- installed_bibliometrix_version()
    message("Installed bibliometrix ", new_ver, " into user library.")
    record_cran_update_check()
    invisible(TRUE)
  }, error = function(e) {
    # Leave stamp untouched so an offline failure retries on the next launch.
    message("CRAN update skipped (offline or unavailable): ", conditionMessage(e))
    invisible(FALSE)
  })
}

ensure_bibliometrix_installed <- function() {
  if (requireNamespace("bibliometrix", quietly = TRUE)) {
    return(invisible(TRUE))
  }

  message("bibliometrix not found; attempting CRAN binary install...")
  tryCatch({
    utils::install.packages(
      "bibliometrix",
      lib = user_lib,
      repos = cran_repo,
      type = "binary",
      dependencies = c("Depends", "Imports", "LinkingTo", "Suggests")
    )
  }, error = function(e) {
    stop(
      "bibliometrix is not installed and a binary install failed.\n",
      "Rebuild the installer after running scripts/bake_packages.R.\n",
      "Original error: ", conditionMessage(e),
      call. = FALSE
    )
  })

  if (!requireNamespace("bibliometrix", quietly = TRUE)) {
    stop(
      "bibliometrix is still unavailable after install. ",
      "Rebuild with scripts/bake_packages.R.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

# Full-page splash while Shiny UI/assets initialise (avoids a blank white page).
wrap_loading_splash <- function(app) {
  original_ui <- app$ui
  app$ui <- function(request) {
    ui <- if (is.function(original_ui)) original_ui(request) else original_ui
    shiny::tagList(
      shiny::tags$head(
        shiny::tags$style(shiny::HTML("
          #bibdesk-splash {
            position: fixed; inset: 0; z-index: 99999;
            display: flex; flex-direction: column; align-items: center; justify-content: center;
            gap: 14px; background: #f4f7fb; color: #1f2a37;
            font-family: 'Segoe UI', Tahoma, sans-serif;
          }
          #bibdesk-splash .spinner {
            width: 48px; height: 48px; border-radius: 50%;
            border: 4px solid #d9e7ee; border-top-color: #1f6f8b;
            animation: bibdesk-spin 0.8s linear infinite;
          }
          #bibdesk-splash p { margin: 0; color: #5b6b7c; }
          @keyframes bibdesk-spin { to { transform: rotate(360deg); } }
        ")),
        shiny::tags$script(shiny::HTML("
          (function () {
            function hideSplash() {
              var el = document.getElementById('bibdesk-splash');
              if (el) el.style.display = 'none';
            }
            document.addEventListener('DOMContentLoaded', function () {
              if (window.jQuery) {
                jQuery(document).on('shiny:sessioninitialized shiny:idle', hideSplash);
              }
              setTimeout(hideSplash, 20000);
            });
          })();
        "))
      ),
      shiny::div(
        id = "bibdesk-splash",
        shiny::div(class = "spinner", `aria-hidden` = "true"),
        shiny::tags$h2("Loading Biblioshiny…"),
        shiny::tags$p("Preparing the interface. This may take a moment.")
      ),
      ui
    )
  }
  app
}

# Stop the server when the browser session ends so R does not linger and lock files.
# A short delay avoids quitting during a normal page refresh.
wrap_stop_when_browser_closes <- function(app) {
  original <- app$serverFuncSource
  app$serverFuncSource <- function() {
    server <- original()
    function(input, output, session) {
      session$onSessionEnded(function() {
        if (requireNamespace("later", quietly = TRUE)) {
          later::later(function() {
            message("Browser session ended; stopping Biblioshiny.")
            shiny::stopApp()
          }, delay = 2)
        } else {
          message("Browser session ended; stopping Biblioshiny.")
          shiny::stopApp()
        }
      })
      server(input, output, session)
    }
  }
  app
}

run_biblioshiny_desktop <- function(host, port, launch_browser = FALSE) {
  app_dir <- system.file("biblioshiny", package = "bibliometrix")
  if (!nzchar(app_dir) || !dir.exists(app_dir)) {
    stop("Could not find biblioshiny app directory inside the bibliometrix package.", call. = FALSE)
  }

  # Mirror bibliometrix::biblioshiny defaults that matter for desktop use.
  shiny::shinyOptions(maxUploadSize = 500)
  shiny::shinyOptions(biblioshiny.max.rows = Inf)

  app <- shiny::shinyAppDir(app_dir)
  app <- wrap_loading_splash(app)
  app <- wrap_stop_when_browser_closes(app)
  shiny::runApp(
    app,
    host = host,
    port = port,
    launch.browser = isTRUE(launch_browser)
  )
}

if (isTRUE(enable_runtime_updates)) {
  if (should_run_cran_update_check()) {
    update_bibliometrix_from_cran()
  } else {
    message(
      "Skipping CRAN update check (last successful check within ",
      update_check_interval_days,
      " days)."
    )
  }
}

ensure_bibliometrix_installed()
message("Using bibliometrix ", installed_bibliometrix_version())

host <- Sys.getenv("BIBDESK_SHINY_HOST", unset = "127.0.0.1")
port <- suppressWarnings(as.integer(Sys.getenv("BIBDESK_SHINY_PORT", unset = "3838")))
if (is.na(port) || port <= 0) {
  port <- 3838L
}

launch_browser <- !identical(Sys.getenv("BIBDESK_LAUNCH_BROWSER", unset = "0"), "0")

message("Starting Biblioshiny on http://", host, ":", port, " ...")
tryCatch(
  {
    run_biblioshiny_desktop(host = host, port = port, launch_browser = launch_browser)
  },
  error = function(e) {
    message("Biblioshiny stopped: ", conditionMessage(e))
  },
  finally = {
    message("Biblioshiny session ended.")
  }
)

quit(save = "no", status = 0)
