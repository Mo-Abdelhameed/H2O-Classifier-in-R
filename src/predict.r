# Required Libraries
library(jsonlite)
library(h2o)

h2o.init()
set.seed(42)

# Paths
ROOT_DIR <- getwd() # dirname(getwd())
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

PREDICTOR_FILE_PATH = readRDS(PREDICTOR_FILE_PATH)
model <- h2o.loadModel(path = PREDICTOR_FILE_PATH)

predictions <- h2o.predict(model, newdata = as.h2o(df))

# Check and modify column names
new_colnames <- sapply(names(predictions), function(col) {
  modified_col <- substring(col, 2)
  if (modified_col %in% target_classes) {
    return(modified_col)
  } else {
    return(col)
  }
})

predictions <- as.data.frame(predictions)
names(predictions) <- new_colnames

predictions[[id_feature]] <- ids
predictions$predict <- NULL
write.csv(predictions, PREDICTIONS_FILE, row.names = FALSE)
