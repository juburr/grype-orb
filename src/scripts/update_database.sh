#!/bin/bash

set -e 

# Read in orb parameters
DATABASE_PATH=$(circleci env subst "${PARAM_DATABASE_PATH}")

# Print command arguments for debugging purposes.
echo "Running Grype database updater..."
echo "  DATABASE_PATH: ${DATABASE_PATH}"

# The GRYPE_DB_CACHE_DIR environment variable should not be renamed, as it's
# used by Grype itself to determine where to place the vulnerability database.
export GRYPE_DB_CACHE_DIR="${DATABASE_PATH}"

# Update the vulnerability database, with the highest verbosity level
grype db update -vv
