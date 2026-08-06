# scripts/bake_packages.R
# Pre-install bibliometrix and dependencies as Windows binaries into the
# bundled R-Portable library. Run this on the build machine before compiling
# the installer so end users never need Rtools.
#
#
# Usage (from repo root), either layout:
#   .\R-Portable\bin\Rscript.exe scripts\bake_packages.R
#   .\R-Portable\App\R-Portable\bin\Rscript.exe scripts\bake_packages.R

cran_repo <- "https://cloud.r-project.org"
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_dir <- if (length(file_arg)) {
  dirname(normalizePath(sub("^--file=", "", file_arg)))
} else {
  getwd()
}
root <- normalizePath(file.path(script_dir, ".."))

find_r_home <- function(root) {
  candidates <- c(
    file.path(root, "R-Portable"),                          # portable-r-windows
    file.path(root, "R-Portable", "App", "R-Portable")      # PortableApps layout
  )
  for (cand in candidates) {
    if (dir.exists(file.path(cand, "library")) &&
        (file.exists(file.path(cand, "bin", "Rscript.exe")) ||
         file.exists(file.path(cand, "bin", "x64", "Rscript.exe")))) {
      return(cand)
    }
  }
  NA_character_
}

r_home <- find_r_home(root)
if (is.na(r_home)) {
  stop(
    "Could not find R under R-Portable. Expected either:\n",
    "  R-Portable\\bin\\Rscript.exe  (portable-r-windows)\n",
    "  R-Portable\\App\\R-Portable\\bin\\Rscript.exe  (PortableApps)",
    call. = FALSE
  )
}
lib <- file.path(r_home, "library")

message("Baking packages into: ", lib)
message("R version: ", R.version.string)

options(
  repos = c(CRAN = cran_repo),
  pkgType = "binary",
  install.packages.compile.from.source = "never",
  Ncpus = max(1L, parallel::detectCores(logical = TRUE) - 1L)
)

# Prefer installing into the bundled library.
.libPaths(c(lib, .libPaths()))

pkgs <- c("bibliometrix")

message("Installing CRAN binary packages (including Suggests): ", paste(pkgs, collapse = ", "))
# Include Suggests so Biblioshiny does not try to download extras at runtime.
install.packages(
  pkgs,
  lib = lib,
  repos = cran_repo,
  type = "binary",
  dependencies = c("Depends", "Imports", "LinkingTo", "Suggests")
)

if (!requireNamespace("bibliometrix", quietly = TRUE, lib.loc = lib)) {
  stop("bibliometrix failed to install into the portable library.", call. = FALSE)
}

ver <- as.character(utils::packageVersion("bibliometrix", lib.loc = lib))
message("SUCCESS: bibliometrix ", ver, " is baked into R-Portable.")

# Warn when CRAN's binary for this R version lags the source release.
tryCatch({
  ap <- available.packages(
    repos = cran_repo,
    type = "source",
    filters = c("R_version", "OS_type", "subarch")
  )
  if ("bibliometrix" %in% rownames(ap)) {
    src_ver <- ap["bibliometrix", "Version"]
    if (package_version(src_ver) > package_version(ver)) {
      warning(
        "Bundled bibliometrix ", ver, " is behind CRAN source ", src_ver, ".\n",
        "CRAN has no newer Windows binary for this R (", R.version.string, ").\n",
        "Upgrade R-Portable to a current R 4.4/4.5 build, then re-run this script ",
        "to ship a newer bibliometrix without requiring Rtools for end users.",
        call. = FALSE
      )
    }
  }
}, error = function(e) invisible(NULL))

message("Optional: run scripts/trim_r_portable.ps1 to shrink the installer.")
