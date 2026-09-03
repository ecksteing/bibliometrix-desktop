# scripts/check_update_background.R
# Background updater for Bibliometrix.
# Invoked asynchronously by the launcher so startup is never delayed.
#
# Checks CRAN for a newer bibliometrix Windows binary at most once every 7 days.
# If a newer binary is found, installs it into the user library (user_lib)
# so it takes effect seamlessly on the next launch.

cran_repo <- "https://cloud.r-project.org"
app_name <- "Bibliometrix Desktop"
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

# Resolve short 8.3 path to prevent non-ASCII character issues
tryCatch({
  user_lib <- utils::shortPathName(user_lib)
}, error = function(e) invisible(NULL))

dir.create(user_lib, recursive = TRUE, showWarnings = FALSE)
app_data_dir <- dirname(user_lib)
dir.create(app_data_dir, recursive = TRUE, showWarnings = FALSE)
cran_check_stamp_path <- file.path(app_data_dir, "cran_update_check.txt")

# Set up library search path so current user_lib takes precedence
.libPaths(c(user_lib, .libPaths()))

options(
  repos = c(CRAN = cran_repo),
  pkgType = "binary",
  install.packages.compile.from.source = "never"
)

should_run_update_check <- function() {
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

record_update_check <- function() {
  tryCatch(
    {
      writeLines(
        strftime(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
        cran_check_stamp_path
      )
    },
    error = function(e) invisible(NULL)
  )
  invisible(NULL)
}

installed_bibliometrix_version <- function() {
  if (!requireNamespace("bibliometrix", quietly = TRUE)) {
    return(NA_character_)
  }
  as.character(utils::packageVersion("bibliometrix"))
}

# Lightweight check: attempt to read package version from CRAN web/API first,
# falling back to available.packages() if needed.
get_latest_cran_version <- function() {
  # 1. Fast lightweight check via CRAN web page (~150ms)
  url <- sprintf("%s/web/packages/bibliometrix/index.html", cran_repo)
  ver <- tryCatch({
    con <- url(url, open = "r", timeout = 4)
    on.exit(close(con), add = TRUE)
    lines <- readLines(con, n = 40L, warn = FALSE)
    ver_line <- grep("<td>Version:</td>", lines, value = TRUE)
    if (length(ver_line) > 0) {
      # Extract version from following line or same line
      idx <- which(lines == ver_line[[1L]])
      target <- if (idx < length(lines)) paste(lines[idx:(idx + 1)], collapse = " ") else ver_line[[1L]]
      m <- regmatches(target, regexec("<td>([0-9]+(\\.[0-9]+)+)</td>", target))
      if (length(m[[1L]]) >= 2) m[[1L]][[2L]] else NA_character_
    } else {
      NA_character_
    }
  }, error = function(e) NA_character_)

  if (!is.na(ver) && nzchar(ver)) {
    return(ver)
  }

  # 2. Fallback to available.packages() (safe in background worker)
  tryCatch({
    ap <- utils::available.packages(
      repos = cran_repo,
      type = "binary",
      filters = c("R_version", "OS_type", "subarch", "duplicates")
    )
    if ("bibliometrix" %in% rownames(ap)) {
      as.character(ap["bibliometrix", "Version"])
    } else {
      NA_character_
    }
  }, error = function(e) NA_character_)
}

run_background_update <- function() {
  if (!should_run_update_check()) {
    return(invisible(NULL))
  }

  current <- installed_bibliometrix_version()
  latest <- get_latest_cran_version()

  if (is.na(latest) || !nzchar(latest)) {
    return(invisible(NULL))
  }

  # Always record that we successfully reached CRAN
  record_update_check()

  if (!is.na(current) && package_version(latest) <= package_version(current)) {
    return(invisible(NULL))
  }

  # New version found: install into user_lib in background
  tryCatch({
    utils::install.packages(
      "bibliometrix",
      lib = user_lib,
      repos = cran_repo,
      type = "binary",
      dependencies = c("Depends", "Imports", "LinkingTo", "Suggests"),
      quiet = TRUE
    )
  }, error = function(e) invisible(NULL))

  invisible(NULL)
}

run_background_update()
quit(save = "no", status = 0)
