# Required Libraries
library(jsonlite)
library(h2o)
library(fastDummies)

h2o.init()
set.seed(42)

# Define directories and paths
ROOT_DIR <- dirname(getwd())
MODEL_INPUTS_OUTPUTS <- file.path(ROOT_DIR, 'model_inputs_outputs')
INPUT_DIR <- file.path(MODEL_INPUTS_OUTPUTS, "inputs")
OUTPUT_DIR <- file.path(MODEL_INPUTS_OUTPUTS, "outputs")
INPUT_SCHEMA_DIR <- file.path(INPUT_DIR, "schema")
DATA_DIR <- file.path(INPUT_DIR, "data")
TRAIN_DIR <- file.path(DATA_DIR, "training")
TEST_DIR <- file.path(DATA_DIR, "testing")
MODEL_ARTIFACTS_PATH <- file.path(MODEL_INPUTS_OUTPUTS, "model", "artifacts")
PREDICTOR_FILE_PATH <- file.path(MODEL_ARTIFACTS_PATH, "predictor_path.rds")
PREDICTIONS_DIR <- file.path(OUTPUT_DIR, 'predictions')
PREDICTIONS_FILE <- file.path(PREDICTIONS_DIR, 'predictions.csv')
IMPUTATION_FILE <- file.path(MODEL_ARTIFACTS_PATH, "imputation.rds")
OHE_ENCODER_FILE <- file.path(MODEL_ARTIFACTS_PATH, "ohe.rds")
TOP_10_CATEGORIES_MAP <- file.path(MODEL_ARTIFACTS_PATH, "map.rds")

if (!dir.exists(PREDICTIONS_DIR)) {
  dir.create(PREDICTIONS_DIR, recursive = TRUE)
}

# Reading the schema
file_name <- list.files(INPUT_SCHEMA_DIR, pattern = "*.json")[1]
schema <- fromJSON(file.path(INPUT_SCHEMA_DIR, file_name))
features <- schema$features

numeric_features <- features$name[features$dataType != 'CATEGORICAL']
categorical_features <- features$name[features$dataType == 'CATEGORICAL']
id_feature <- schema$id$name
target_feature <- schema$target$name
target_classes <- schema$target$classes
model_category <- schema$modelCategory
nullable_features <- features$name[features$nullable == TRUE]


# Reading test data.
file_name <- list.files(TEST_DIR, pattern = "*.csv", full.names = TRUE)[1]
# Read the first line to get column names
header_line <- readLines(file_name, n = 1)
col_names <- unlist(strsplit(header_line, split = ",")) # assuming ',' is the delimiter
# Read the CSV with the exact column names
df <- read.csv(file_name, skip = 0, col.names = col_names, check.names=FALSE)

ids <- df[[id_feature]]

imputation_values <- readRDS(IMPUTATION_FILE)
for (column in names(df)[sapply(df, function(col) any(is.na(col)))]) {
  df[, column][is.na(df[, column])] <- imputation_values[[column]]
}

# Saving the id column in a different variable and then dropping it.
ids <- df[[id_feature]]
df[[id_feature]] <- NULL

# Encoding
# We encode the data using the same encoder that we saved during training.
if (length(categorical_features) > 0 && file.exists(OHE_ENCODER_FILE)) {
  top_10_map <- readRDS(TOP_10_CATEGORIES_MAP)
  encoder <- readRDS(OHE_ENCODER_FILE)
  for(col in categorical_features) {
    # Use the saved top 3 categories to replace values outside these categories with 'Other'
    df[[col]][!(df[[col]] %in% top_10_map[[col]])] <- "Other"
  }

  test_df_encoded <- dummy_cols(df, select_columns = categorical_features, remove_selected_columns = TRUE)
  encoded_columns <- readRDS(OHE_ENCODER_FILE)
  # Add missing columns with 0s
    for (col in encoded_columns) {
        if (!col %in% colnames(test_df_encoded)) {
            test_df_encoded[[col]] <- 0
        }
    }

# Remove extra columns
    extra_cols <- setdiff(colnames(test_df_encoded), c(colnames(df), encoded_columns))
    df <- test_df_encoded[, !names(test_df_encoded) %in% extra_cols]
}


PREDICTOR_FILE_PATH = readRDS(PREDICTOR_FILE_PATH)
model <- h2o.loadModel(path = PREDICTOR_FILE_PATH)

predictions <- h2o.predict(model, newdata = as.h2o(df))

# # Check and modify column names
# new_colnames <- sapply(names(predictions), function(col) {
#   modified_col <- substring(col, 2)
#   if (modified_col %in% target_classes) {
#     return(modified_col)
#   } else {
#     return(col)
#   }
# })

predictions <- as.data.frame(predictions)
predictions$predict <- NULL
names(predictions) <- sort(target_classes)

predictions[[id_feature]] <- ids
write.csv(predictions, PREDICTIONS_FILE, row.names = FALSE)
