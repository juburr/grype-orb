#!/bin/bash
#
# Writes one of the two files the update_database cache keys are computed
# from. CircleCI never replaces a saved cache, so the database is saved under
# a key naming the database itself, and restored from the newest cache saved
# for the same location:
#
#   location (before the restore): HOME and database_dir as given, since a
#     cache is restored to the absolute path it was saved from, and the
#     database schema the installed Grype reads, so Grype releases with
#     different schemas never trade databases;
#   database (after the update): the schema, build time and source of the
#     database now in database_dir, from `grype db status`. A job that
#     downloaded a newer database saves it under a new key, and a job that
#     found the restored database current saves nothing.
#
# Parameters arrive as ORB_DB_CACHE_KEY_PART (location or database),
# ORB_DB_CACHE_KEY_FILE and, for location, PARAM_DATABASE_DIR.

set -euo pipefail

# The file is written under a new name and renamed into place, so a file or
# symlink someone else left at its name in a shared /tmp is never written
# through. mv would move it into a directory, so that is refused.
tmp=$(mktemp "${ORB_DB_CACHE_KEY_FILE}.XXXXXX")
trap 'rm -f "${tmp}"' EXIT

case "${ORB_DB_CACHE_KEY_PART}" in
    location)
        # database_dir as given: the cache steps expand ~ but not environment
        # variables, so the raw value names the directory they save.
        schema=$({ grype version 2> /dev/null || true; } | awk -F: '/^Supported DB Schema:/ { gsub(/[[:space:]]/, "", $2); print $2 }')
        printf '%s\n%s\n%s\n' "${HOME:-}" "${PARAM_DATABASE_DIR:-}" "${schema}" > "${tmp}"
        echo "Database cache location: ${PARAM_DATABASE_DIR:-} (schema ${schema:-unknown})."
        ;;
    database)
        # Path and Status are left out: the location already covers the path,
        # and the status is not part of the database.
        identity=$({ grype db status 2> /dev/null || true; } \
            | awk '/^[[:space:]]*(Schema|Built|From|Checksum):/ { $1 = $1; print }')
        if [[ -z "${identity}" ]]; then
            identity="date $(date -u +%Y-%m-%d)"
            echo "WARN: grype db status named no database; keying the cache by today's date instead." >&2
        fi
        printf '%s\n' "${identity}" > "${tmp}"
        echo "Database cache key names:"
        printf '  %s\n' "${identity}"
        ;;
    *)
        echo "ERROR: ORB_DB_CACHE_KEY_PART must be location or database, got '${ORB_DB_CACHE_KEY_PART}'." >&2
        exit 1
        ;;
esac

if [[ -d "${ORB_DB_CACHE_KEY_FILE}" ]] || ! mv -f "${tmp}" "${ORB_DB_CACHE_KEY_FILE}"; then
    echo "ERROR: Could not write ${ORB_DB_CACHE_KEY_FILE}." >&2
    exit 1
fi
