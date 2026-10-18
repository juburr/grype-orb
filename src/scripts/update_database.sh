#!/bin/bash

set -euo pipefail

# Read in orb parameters
DATABASE_DIR=$(printf '%s' "${PARAM_DATABASE_DIR}" | circleci env subst)

if [[ -z "${DATABASE_DIR}" ]]; then
    echo "ERROR: database_dir is required, but it is empty." >&2
    exit 2
fi

# Expand a leading ~ the way the restore_cache and save_cache steps do, and
# make a relative path absolute, so every later step finds the same directory.
if [[ "${DATABASE_DIR}" == \~ || "${DATABASE_DIR}" == \~/* ]]; then
    DATABASE_DIR="${HOME}${DATABASE_DIR:1}"
fi
if [[ "${DATABASE_DIR}" != /* ]]; then
    DATABASE_DIR="${PWD}/${DATABASE_DIR}"
fi

# Print command arguments for debugging purposes.
echo "Running Grype database updater..."
echo "  DATABASE_DIR: ${DATABASE_DIR}"

# GRYPE_DB_CACHE_DIR is the variable Grype itself reads to locate the
# vulnerability database, so it must keep this name. Export it to later steps
# too, so scans and `grype db list` use this database.
export GRYPE_DB_CACHE_DIR="${DATABASE_DIR}"
if [[ -n "${BASH_ENV:-}" ]]; then
    printf 'export GRYPE_DB_CACHE_DIR=%q\n' "${GRYPE_DB_CACHE_DIR}" >> "${BASH_ENV}"
fi

# Update the vulnerability database, with the highest verbosity level
grype db update -vv
