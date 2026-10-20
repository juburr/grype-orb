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

# key_file PART: runs the key script for PART (location or database) and
# writes the key file in this test's directory.
key_file() {
    export ORB_DB_CACHE_KEY_PART="$1"
    export ORB_DB_CACHE_KEY_FILE="${BATS_TEST_TMPDIR}/db-cache-$1"
    run bash "${SCRIPTS_DIR}/database_cache_key.sh"
}

# grype_stub VERSION_OUTPUT STATUS_OUTPUT: a grype that prints these for
# `grype version` and `grype db status`.
grype_stub() {
    printf '%s\n' "$1" > "${BATS_TEST_TMPDIR}/grype-version.out"
    printf '%s\n' "$2" > "${BATS_TEST_TMPDIR}/grype-status.out"
    stub grype "case \"\$*\" in
        version) cat '${BATS_TEST_TMPDIR}/grype-version.out' ;;
        'db status') cat '${BATS_TEST_TMPDIR}/grype-status.out' ;;
        *) exit 1 ;;
    esac"
}

STATUS_V6='Path:      /home/circleci/.cache/grype/db/6/vulnerability.db
Schema:    v6.1.10
Built:     2026-10-19T06:39:15Z
From:      https://grype.anchore.io/databases/v6/vulnerability-db_v6.1.10_2026-10-19T00:32:50Z_1792391955.tar.zst?checksum=sha256%3A13a1
Status:    valid'

@test "the location key names HOME, database_dir as given and the Grype schema" {
    grype_stub $'Application:         grype\nVersion:             0.119.0\nSupported DB Schema: 6' "${STATUS_V6}"

    key_file location

    [ "${status}" -eq 0 ]
    # database_dir stays as given, ~ and all: the cache steps don't expand
    # variables, so the raw value names the directory they save.
    [ "$(cat "${ORB_DB_CACHE_KEY_FILE}")" = "$(printf '%s\n%s\n%s' "${HOME}" "${PARAM_DATABASE_DIR}" 6)" ]
    [ -z "$(find "${BATS_TEST_TMPDIR}" -maxdepth 1 -name 'db-cache-*.*')" ]
}

@test "the location key changes with HOME, database_dir and the schema" {
    grype_stub 'Supported DB Schema: 6' "${STATUS_V6}"
    default_dir="${PARAM_DATABASE_DIR}"
    key_file location
    first=$(cat "${ORB_DB_CACHE_KEY_FILE}")

    export PARAM_DATABASE_DIR="${default_dir}-other"
    key_file location
    [ "$(cat "${ORB_DB_CACHE_KEY_FILE}")" != "${first}" ]

    export PARAM_DATABASE_DIR="${default_dir}" HOME="${BATS_TEST_TMPDIR}/other home"
    key_file location
    [ "$(cat "${ORB_DB_CACHE_KEY_FILE}")" != "${first}" ]

    export HOME="${BATS_TEST_TMPDIR}/home dir"
    grype_stub 'Supported DB Schema: 5' "${STATUS_V6}"
    key_file location
    [ "$(cat "${ORB_DB_CACHE_KEY_FILE}")" != "${first}" ]
}

@test "the database key names the database, not its path or status" {
    grype_stub 'Supported DB Schema: 6' "${STATUS_V6}"

    key_file database

    [ "${status}" -eq 0 ]
    [ "$(sed -n 1p "${ORB_DB_CACHE_KEY_FILE}")" = "Schema: v6.1.10" ]
    [ "$(sed -n 2p "${ORB_DB_CACHE_KEY_FILE}")" = "Built: 2026-10-19T06:39:15Z" ]
    grep -q '^From: https://grype.anchore.io/' "${ORB_DB_CACHE_KEY_FILE}"
    ! grep -qE '^(Path|Status):' "${ORB_DB_CACHE_KEY_FILE}"
}

@test "a newer database gets a new key, the same database the same key" {
    grype_stub 'Supported DB Schema: 6' "${STATUS_V6}"
    key_file database
    first=$(cat "${ORB_DB_CACHE_KEY_FILE}")

    # Checked again later, from another path, with another status.
    grype_stub 'Supported DB Schema: 6' "$(printf '%s\n' "${STATUS_V6}" | sed -e 's#/home/circleci#/root#' -e 's/valid/valid (checked)/')"
    key_file database
    [ "$(cat "${ORB_DB_CACHE_KEY_FILE}")" = "${first}" ]

    grype_stub 'Supported DB Schema: 6' "$(printf '%s\n' "${STATUS_V6}" | sed 's/2026-10-19T06:39:15Z/2026-10-20T06:41:02Z/')"
    key_file database
    [ "$(cat "${ORB_DB_CACHE_KEY_FILE}")" != "${first}" ]
}

@test "the database key reads a schema 5 status, with a Checksum line" {
    grype_stub 'Supported DB Schema: 5' $'Location:  /root/.cache/grype/db/5\nBuilt:     2025-01-02 01:23:45 +0000 UTC\nSchema:    5\nChecksum:  sha256:abc\nStatus:    valid'

    key_file database

    [ "${status}" -eq 0 ]
    [ "$(cat "${ORB_DB_CACHE_KEY_FILE}")" = "$(printf '%s\n%s\n%s' 'Built: 2025-01-02 01:23:45 +0000 UTC' 'Schema: 5' 'Checksum: sha256:abc')" ]
}

@test "without a database status, the database key falls back to today's date" {
    grype_stub '' ''

    key_file database

    [ "${status}" -eq 0 ]
    [ "$(cat "${ORB_DB_CACHE_KEY_FILE}")" = "date $(date -u +%Y-%m-%d)" ]
    [[ "${output}" == *"WARN: grype db status named no database"* ]]
}

@test "a cache key file is not written through a symlink" {
    grype_stub 'Supported DB Schema: 6' "${STATUS_V6}"
    target="${BATS_TEST_TMPDIR}/target"
    printf 'keep\n' > "${target}"
    ln -s "${target}" "${BATS_TEST_TMPDIR}/db-cache-database"

    key_file database

    [ "${status}" -eq 0 ]
    [ "$(cat "${target}")" = "keep" ]
    [ ! -L "${ORB_DB_CACHE_KEY_FILE}" ]
}

@test "a directory at a cache key file's name fails the step" {
    grype_stub 'Supported DB Schema: 6' "${STATUS_V6}"
    mkdir "${BATS_TEST_TMPDIR}/db-cache-location"

    key_file location

    [ "${status}" -ne 0 ]
    [[ "${output}" == *"ERROR: Could not write ${ORB_DB_CACHE_KEY_FILE}."* ]]
}

@test "an unknown key part fails the step" {
    key_file both

    [ "${status}" -ne 0 ]
    [[ "${output}" == *"ERROR: ORB_DB_CACHE_KEY_PART must be location or database"* ]]
}

@test "the newest database for the location is restored, and saved under its own key" {
    yml="${COMMANDS_DIR}/update_database.yml"
    location='{{ checksum "/tmp/grype-orb-db-cache-location" }}'
    database='{{ checksum "/tmp/grype-orb-db-cache-database" }}'

    restore=$(awk '/restore_cache:/ { on = 1; next } on && !/^ +(keys:|- grype-vuln-db)/ { exit } on && /^ +- / { sub(/^ +- /, ""); print }' "${yml}")
    [ "${restore}" = "grype-vuln-db-v2-${location}-" ]

    save=$(awk '/save_cache:/ { on = 1 } on && /key:/ { sub(/^ +key: /, ""); print; exit }' "${yml}")
    [ "${save}" = "grype-vuln-db-v2-${location}-${database}" ]

    # The steps that write the key files must name the same files.
    grep -qF 'ORB_DB_CACHE_KEY_FILE: /tmp/grype-orb-db-cache-location' "${yml}"
    grep -qF 'ORB_DB_CACHE_KEY_FILE: /tmp/grype-orb-db-cache-database' "${yml}"
}
