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
