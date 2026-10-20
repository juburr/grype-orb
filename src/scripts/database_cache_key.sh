#!/bin/bash
#
# Writes the files the update_database cache keys are computed from, named
# ${ORB_DB_CACHE_KEY_PREFIX}-<name>. CircleCI never replaces a saved cache,
# so the database is saved under a key naming the database itself:
#
#   location, before the restore: HOME and database_dir as given, since a
#     cache is restored to the absolute path it was saved from, the working
#     directory when database_dir is relative to it, the database schema the
#     installed Grype reads, and the feed it updates from, so jobs with
#     different databases never trade them;
#   day0, day1 and day2, before the restore: today's date in UTC and the two
#     days before;
#   built and database, after the update: the build date of the database now
#     in database_dir, and its schema, build time and source from
#     `grype db status`.
#
# The save key is location, built and database, and the restore tries today's
# build date first, then the two days before, then any. CircleCI restores the
# newest cache saved under a prefix, so a job that saves an older database
# late can never outrank a newer one saved earlier. A job that found its
# restored database current saves nothing, since its key already exists.
#
# Parameters arrive as ORB_DB_CACHE_KEY_PART (location or database),
# ORB_DB_CACHE_KEY_PREFIX and, for location, PARAM_DATABASE_DIR.

set -euo pipefail

prefix=${ORB_DB_CACHE_KEY_PREFIX}
tmps=()
trap 'rm -f ${tmps[@]+"${tmps[@]}"}' EXIT

# write_key NAME CONTENT: writes CONTENT and a newline to ${prefix}-NAME. The
# file is written under a new name and renamed into place, so a file or
# symlink someone else left at its name in a shared /tmp is never written
# through. mv would move it into a directory, so that is refused.
write_key() {
    local file="${prefix}-$1" tmp
    tmp=$(mktemp "${file}.XXXXXX")
    tmps+=("${tmp}")
    printf '%s\n' "$2" > "${tmp}"
    if [[ -d "${file}" ]] || ! mv -f "${tmp}" "${file}"; then
        echo "ERROR: Could not write ${file}." >&2
        exit 1
    fi
}

case "${ORB_DB_CACHE_KEY_PART}" in
    location)
        # database_dir as given: the cache steps expand ~ but not environment
        # variables, so the raw value names the directory they save. A
        # relative one is saved from the working directory.
        dir=${PARAM_DATABASE_DIR:-}
        workdir=""
        if [[ -n "${dir}" && "${dir}" != /* && "${dir}" != \~ && "${dir}" != \~/* ]]; then
            workdir=${PWD}
        fi
        schema=$({ grype version 2> /dev/null || true; } | awk -F: '/^Supported DB Schema:/ { gsub(/[[:space:]]/, "", $2); print $2 }')
        # The effective db.update-url, from the config files and environment
        # (grype config --load needs Grype 0.78.0 or later), which prints it
        # as a quoted YAML string.
        feed=$({ grype config --load 2> /dev/null || true; } | awk '/^[[:space:]]*update-url:/ { print $2; exit }')
        feed=${feed#[\"\']}
        feed=${feed%[\"\']}
        feed=${feed:-${GRYPE_DB_UPDATE_URL:-}}
        # Credentials in a private feed's URL don't change the feed, so they
        # stay out of the key, and the log shows no query string either.
        feed=$(printf '%s\n' "${feed}" | sed -E 's#^([A-Za-z][A-Za-z0-9+.-]*://)[^/@]*@#\1#')
        write_key location "$(printf '%s\n%s\n%s\n%s\n%s' "${HOME:-}" "${dir}" "${workdir}" "${schema}" "${feed}")"
        now=$(date -u +%s)
        for day in 0 1 2; do
            write_key "day${day}" "$(date -u -d "@$((now - day * 86400))" +%Y-%m-%d)"
        done
        shown=${feed%%\?*}
        echo "Database cache location: ${dir}${workdir:+ in ${workdir}} (schema ${schema:-unknown}, feed ${shown:-default})."
        ;;
    database)
        # Path and Status are left out: the location already covers the path,
        # and the status is not part of the database. The From URL keeps only
        # its checksum parameter and loses any credentials, so a feed that signs
        # each download URL still gives every job the same key, and the log
        # shows neither.
        identity=$({ grype db status 2> /dev/null || true; } \
            | awk '/^[[:space:]]*(Schema|Built|From|Checksum):/ {
                $1 = $1
                if ($1 == "From:") {
                    url = $2
                    sub(/:\/\/[^\/@]*@/, "://", url)
                    checksum = ""
                    if (match(url, /[?&]checksum=[^&]*/)) {
                        checksum = "?" substr(url, RSTART + 1, RLENGTH - 1)
                    }
                    sub(/\?.*/, "", url)
                    $0 = "From: " url checksum
                }
                print
            }')
        built=$(printf '%s\n' "${identity}" | awk '/^Built: / { print substr($0, 8, 10); exit }')
        if [[ -z "${identity}" ]]; then
            identity="date $(date -u +%Y-%m-%d)"
            echo "WARN: grype db status named no database; keying the cache by today's date instead." >&2
        fi
        if [[ ! "${built}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
            built=$(date -u +%Y-%m-%d)
        fi
        write_key built "${built}"
        write_key database "${identity}"
        echo "Database cache key names the database built on ${built}:"
        printf '%s\n' "${identity}" | sed 's/^/  /'
        ;;
    *)
        echo "ERROR: ORB_DB_CACHE_KEY_PART must be location or database, got '${ORB_DB_CACHE_KEY_PART}'." >&2
        exit 1
        ;;
esac
