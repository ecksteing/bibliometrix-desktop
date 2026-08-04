# launch_app.R
# Starts Biblioshiny from the bundled portable R install.
#
# Update policy:
#   - CRAN Windows binaries only (no source builds => no Rtools for users)
#   - Never installs from GitHub (source builds often need Rtools)
#   - Newer packages install into a writable user library and take precedence
#   - If offline / update fails, the baked-in copy still launches

cran_repo <- "https://cloud.r-project.org"
app_name <- "Bibliometrix Desktop"

# Check CRAN for a newer bibliometrix binary on every launch (when online).
enable_runtime_updates <- TRUE

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

update_bibliometrix_from_cran <- function() {
  message("Checking CRAN for a newer bibliometrix Windows binary...")
  tryCatch({
    current <- installed_bibliometrix_version()
    latest <- cran_bibliometrix_binary_version()

    if (is.na(latest)) {
      message("No CRAN binary listed for this R version; keeping installed copy.")
      return(invisible(FALSE))
    }

    if (!is.na(current) && package_version(latest) <= package_version(current)) {
      message("bibliometrix is up to date (", current, ").")
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
    invisible(TRUE)
  }, error = function(e) {
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

if (isTRUE(enable_runtime_updates)) {
  update_bibliometrix_from_cran()
}

ensure_bibliometrix_installed()
message("Using bibliometrix ", installed_bibliometrix_version())

message("Starting Biblioshiny...")
host <- Sys.getenv("BIBDESK_SHINY_HOST", unset = "127.0.0.1")
port <- suppressWarnings(as.integer(Sys.getenv("BIBDESK_SHINY_PORT", unset = "3838")))
if (is.na(port) || port <= 0) {
  port <- 3838L
}

# Shiny often ends by throwing when the user closes the app; treat that as success.
# Note: closing the browser tab does NOT stop the server — relaunching the desktop
# app reopens the existing session (handled by run_bibliometrix.py).
tryCatch(
  {
    bibliometrix::biblioshiny(
      host = host,
      port = port,
      launch.browser = TRUE
    )
  },
  error = function(e) {
    message("Biblioshiny stopped: ", conditionMessage(e))
  },
  finally = {
    message("Biblioshiny session ended.")
  }
)

quit(save = "no", status = 0)
