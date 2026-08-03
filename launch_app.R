# launch_app.R

# 1. Ensure pak is loaded for GitHub installation
if (!requireNamespace("pak", quietly = TRUE)) {
  install.packages("pak", repos = "https://cloud.r-project.org")
}

# 2. Update Bibliometrix directly from Massimo's GitHub repository
message("Checking for Bibliometrix updates...")
tryCatch({
  pak::pkg_install("massimoaria/bibliometrix", upgrade = TRUE, ask = FALSE)
}, error = function(e) {
  message("Offline or unable to fetch updates. Launching existing installed version...")
})

# 3. Force Shiny to open in the user's default web browser
options(shiny.launch.browser = TRUE)

# 4. Run Bibliometrix
library(bibliometrix)
bibliometrix::biblioshiny()