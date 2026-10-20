#!/bin/bash
#
# Writes the two files the update_database cache keys are computed from:
#
#   - the location file names HOME and database_dir as given, since a cache
#     is restored to the absolute path it was saved from;
#   - the date file names today's date in UTC. CircleCI never replaces a
#     saved cache, so under a fixed key the first database saved would be
#     restored forever. A key per day lets each day's first job save a fresh
#     database, and the restore falls back to the newest earlier one.
#
# Parameters arrive as PARAM_DATABASE_DIR, ORB_DB_CACHE_LOCATION_FILE and
# ORB_DB_CACHE_DATE_FILE.

set -euo pipefail

# Each file is written under a new name and renamed into place, so a file or
# symlink someone else left at its name in a shared /tmp is never written
# through. mv would move it into a directory, so that is refused.
location_tmp=$(mktemp "${ORB_DB_CACHE_LOCATION_FILE}.XXXXXX")
date_tmp=$(mktemp "${ORB_DB_CACHE_DATE_FILE}.XXXXXX")
trap 'rm -f "${location_tmp}" "${date_tmp}"' EXIT

# database_dir as given: the cache steps expand ~ but not environment
# variables, so the raw value names the directory they save and restore.
printf '%s\n%s\n' "${HOME:-}" "${PARAM_DATABASE_DIR:-}" > "${location_tmp}"
date -u +%Y-%m-%d > "${date_tmp}"

for pair in "${location_tmp}:${ORB_DB_CACHE_LOCATION_FILE}" "${date_tmp}:${ORB_DB_CACHE_DATE_FILE}"; do
    tmp=${pair%%:*}
    file=${pair#*:}
    if [[ -d "${file}" ]] || ! mv -f "${tmp}" "${file}"; then
        echo "ERROR: Could not write ${file}." >&2
        exit 1
    fi
done

echo "Vulnerability database cache keys for ${PARAM_DATABASE_DIR:-} on $(cat "${ORB_DB_CACHE_DATE_FILE}") (UTC)."
