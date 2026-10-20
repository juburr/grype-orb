#!/usr/bin/env bats
# Tests for src/scripts/update_database.sh. A stub grype records the
# GRYPE_DB_CACHE_DIR it runs with and its arguments.

setup() {
    load test_helper
    common_setup

    GRYPE_LOG="${BATS_TEST_TMPDIR}/grype.log"
    stub grype "printf '%s|%s\n' \"\${GRYPE_DB_CACHE_DIR:-}\" \"\$*\" > '${GRYPE_LOG}'"
    export HOME="${BATS_TEST_TMPDIR}/home dir"
    export PARAM_DATABASE_DIR
    PARAM_DATABASE_DIR="$(command_default update_database database_dir)"
}

# exported_dir: prints GRYPE_DB_CACHE_DIR as a later step sees it, by
# sourcing BASH_ENV in a clean shell.
exported_dir() {
    # shellcheck disable=SC2016 # expanded by the clean shell, not here
    env -i bash -c 'source "$1"; printf "%s" "${GRYPE_DB_CACHE_DIR}"' _ "${BASH_ENV}"
}

@test "database_dir defaults to ~/.cache/grype/db" {
    # shellcheck disable=SC2088 # the default is a literal ~, expanded by the script
    [ "${PARAM_DATABASE_DIR}" = "~/.cache/grype/db" ]
}

@test "a leading ~ is expanded, and later steps see the same directory" {
    run bash "${SCRIPTS_DIR}/update_database.sh"

    [ "${status}" -eq 0 ]
    [ "$(cat "${GRYPE_LOG}")" = "${HOME}/.cache/grype/db|db update -vv" ]
    [ "$(exported_dir)" = "${HOME}/.cache/grype/db" ]
}

@test "an absolute database_dir is used as given" {
    export PARAM_DATABASE_DIR="/opt/grype db"

    run bash "${SCRIPTS_DIR}/update_database.sh"

    [ "${status}" -eq 0 ]
    [ "$(cat "${GRYPE_LOG}")" = "/opt/grype db|db update -vv" ]
    [ "$(exported_dir)" = "/opt/grype db" ]
}

@test "a relative database_dir is resolved against the working directory" {
    export PARAM_DATABASE_DIR="cache/db"

    run bash "${SCRIPTS_DIR}/update_database.sh"

    [ "${status}" -eq 0 ]
    [ "$(exported_dir)" = "${PWD}/cache/db" ]
}

@test "an empty database_dir fails before updating" {
    export PARAM_DATABASE_DIR=""

    run bash "${SCRIPTS_DIR}/update_database.sh"

    [ "${status}" -ne 0 ]
    [[ "${output}" == *"ERROR: database_dir is required"* ]]
    [ ! -e "${GRYPE_LOG}" ]
}

# --- database cache keys ------------------------------------------------------

# cache_key_setup: points the key script at files in this test's directory.
cache_key_setup() {
    export ORB_DB_CACHE_LOCATION_FILE="${BATS_TEST_TMPDIR}/db-cache-location"
    export ORB_DB_CACHE_DATE_FILE="${BATS_TEST_TMPDIR}/db-cache-date"
}

@test "the cache key files name the location and today's UTC date" {
    cache_key_setup

    run bash "${SCRIPTS_DIR}/database_cache_key.sh"

    [ "${status}" -eq 0 ]
    # database_dir stays as given, ~ and all: the cache steps don't expand
    # variables, so the raw value names the directory they save.
    [ "$(cat "${ORB_DB_CACHE_LOCATION_FILE}")" = "$(printf '%s\n%s' "${HOME}" "${PARAM_DATABASE_DIR}")" ]
    [ "$(cat "${ORB_DB_CACHE_DATE_FILE}")" = "$(date -u +%Y-%m-%d)" ]
    [ -z "$(find "${BATS_TEST_TMPDIR}" -maxdepth 1 -name 'db-cache-*.*')" ]
}

@test "the location key changes with HOME and database_dir, not with the day" {
    cache_key_setup
    default_dir="${PARAM_DATABASE_DIR}"
    bash "${SCRIPTS_DIR}/database_cache_key.sh"
    first=$(cat "${ORB_DB_CACHE_LOCATION_FILE}")
    first_day=$(cat "${ORB_DB_CACHE_DATE_FILE}")

    export PARAM_DATABASE_DIR="${default_dir}-other"
    bash "${SCRIPTS_DIR}/database_cache_key.sh"
    [ "$(cat "${ORB_DB_CACHE_LOCATION_FILE}")" != "${first}" ]

    export PARAM_DATABASE_DIR="${default_dir}" HOME="${BATS_TEST_TMPDIR}/other home"
    bash "${SCRIPTS_DIR}/database_cache_key.sh"
    [ "$(cat "${ORB_DB_CACHE_LOCATION_FILE}")" != "${first}" ]
    [ "$(cat "${ORB_DB_CACHE_DATE_FILE}")" = "${first_day}" ]
}

@test "a cache key file is not written through a symlink" {
    cache_key_setup
    target="${BATS_TEST_TMPDIR}/target"
    printf 'keep\n' > "${target}"
    ln -s "${target}" "${ORB_DB_CACHE_DATE_FILE}"

    run bash "${SCRIPTS_DIR}/database_cache_key.sh"

    [ "${status}" -eq 0 ]
    [ "$(cat "${target}")" = "keep" ]
    [ ! -L "${ORB_DB_CACHE_DATE_FILE}" ]
}

@test "a directory at a cache key file's name fails the step" {
    cache_key_setup
    mkdir "${ORB_DB_CACHE_DATE_FILE}"

    run bash "${SCRIPTS_DIR}/database_cache_key.sh"

    [ "${status}" -ne 0 ]
    [[ "${output}" == *"ERROR: Could not write ${ORB_DB_CACHE_DATE_FILE}."* ]]
}

@test "the database is saved under today's key and restored from the newest earlier one" {
    yml="${COMMANDS_DIR}/update_database.yml"
    location='{{ checksum "/tmp/grype-orb-db-cache-location" }}'
    day='{{ checksum "/tmp/grype-orb-db-cache-date" }}'
    today="grype-vuln-db-v2-${location}-${day}"

    # Restore today's exact key first, then any earlier day for this location.
    restore=$(awk '/restore_cache:/ { on = 1; next } on && !/^ +(keys:|- grype-vuln-db)/ { exit } on && /^ +- / { sub(/^ +- /, ""); print }' "${yml}")
    [ "${restore}" = "$(printf '%s\n%s' "${today}" "grype-vuln-db-v2-${location}-")" ]

    save=$(awk '/save_cache:/ { on = 1 } on && /key:/ { sub(/^ +key: /, ""); print; exit }' "${yml}")
    [ "${save}" = "${today}" ]

    # The step that writes the key files must name the same files.
    grep -qF 'ORB_DB_CACHE_LOCATION_FILE: /tmp/grype-orb-db-cache-location' "${yml}"
    grep -qF 'ORB_DB_CACHE_DATE_FILE: /tmp/grype-orb-db-cache-date' "${yml}"
}
