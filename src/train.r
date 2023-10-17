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
INPUT_SCHEMA_DIR <- file.path(INPUT_DIR, "schema")
DATA_DIR <- file.path(INPUT_DIR, "data")
TRAIN_DIR <- file.path(DATA_DIR, "training")
MODEL_ARTIFACTS_PATH <- file.path(MODEL_INPUTS_OUTPUTS, "model", "artifacts")
PREDICTOR_DIR_PATH <- file.path(MODEL_ARTIFACTS_PATH, "predictor")
PREDICTOR_FILE_PATH <- file.path(MODEL_ARTIFACTS_PATH, "predictor_path.rds")
IMPUTATION_FILE <- file.path(MODEL_ARTIFACTS_PATH, "imputation.rds")
OHE_ENCODER_FILE <- file.path(MODEL_ARTIFACTS_PATH, "ohe.rds")
TOP_10_CATEGORIES_MAP <- file.path(MODEL_ARTIFACTS_PATH, "map.rds")

if (!dir.exists(MODEL_ARTIFACTS_PATH)) {
    dir.create(MODEL_ARTIFACTS_PATH, recursive = TRUE)
}
if (!dir.exists(file.path(MODEL_ARTIFACTS_PATH, "predictor"))) {
    dir.create(file.path(MODEL_ARTIFACTS_PATH, "predictor"))
}


# Reading the schema
# The schema contains metadata about the datasets. 
# We will use the scehma to get information about the type of each feature (NUMERIC or CATEGORICAL)
# and the id and target features, this will be helpful in preprocessing stage.

file_name <- list.files(INPUT_SCHEMA_DIR, pattern = "*.json")[1]
schema <- fromJSON(file.path(INPUT_SCHEMA_DIR, file_name))
features <- schema$features

numeric_features <- features$name[features$dataType == "NUMERIC"]
categorical_features <- features$name[features$dataType == "CATEGORICAL"]
id_feature <- schema$id$name
target_feature <- schema$target$name
model_category <- schema$modelCategory
nullable_features <- features$name[features$nullable == TRUE]

# Reading training data
file_name <- list.files(TRAIN_DIR, pattern = "*.csv")[1]
# Read the first line to get column names
header_line <- readLines(file.path(TRAIN_DIR, file_name), n = 1)
col_names <- unlist(strsplit(header_line, split = ",")) # assuming ',' is the delimiter
# Read the CSV with the exact column names
df <- read.csv(file.path(TRAIN_DIR, file_name), skip = 0, col.names = col_names, check.names=FALSE)

# Impute missing data
imputation_values <- list()

columns_with_missing_values <- colnames(df)[apply(df, 2, anyNA)]
for (column in columns_with_missing_values) {
    if (column %in% numeric_features) {
        value <- median(df[, column], na.rm = TRUE)
    } else {
        value <- as.character(df[, column] %>% tidyr::replace_na())
        value <- value[1]
    }
    df[, column][is.na(df[, column])] <- value
    imputation_values[column] <- value
}
saveRDS(imputation_values, IMPUTATION_FILE)


# Encoding Categorical features

# The id column is just an identifier for the training example, so we will exclude it during the encoding phase.
# Target feature will be label encoded in the next step.

ids <- df[, id_feature]
target <- df[, target_feature]
df[[target_feature]] <- NULL
df[[id_feature]] <- NULL

# One Hot Encoding
if(length(categorical_features) > 0){
    top_10_map <- list()
    for(col in categorical_features) {
        # Get the top 10 categories for the column
        top_10_categories <- names(sort(table(df[[col]]), decreasing = TRUE)[1:10])

        # Save the top 3 categories for this column
        top_10_map[[col]] <- top_10_categories
        # Replace categories outside the top 3 with "Other"
        df[[col]][!(df[[col]] %in% top_10_categories)] <- "Other"
    }

    df_encoded <- dummy_cols(df, select_columns = categorical_features, remove_selected_columns = TRUE)
    encoded_columns <- setdiff(colnames(df_encoded), colnames(df))
    saveRDS(encoded_columns, OHE_ENCODER_FILE)
    saveRDS(top_10_map, TOP_10_CATEGORIES_MAP)
    df <- df_encoded
}

df[[target_feature]] <- as.factor(target)


splits <- h2o.splitFrame(as.h2o(df), ratios = 0.95, seed = 42)
train <- splits[[1]]
test <- splits[[2]]

automl_models <- h2o.automl(
  x = colnames(df),
  y = target_feature,
  training_frame = train,
  leaderboard_frame = test,
  max_runtime_secs = 120,
  max_models=10,
  project_name = "automl_classification",
  seed=42
)

leaderboard <- automl_models@leaderboard

best_model <- automl_models@leader
path = h2o.saveModel(object = best_model, path = PREDICTOR_DIR_PATH, force = TRUE)

saveRDS(path, PREDICTOR_FILE_PATH)
