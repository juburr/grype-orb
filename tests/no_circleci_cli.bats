#!/usr/bin/env bats
# Without the CircleCI CLI, as on GitHub's runners where the orb's GitHub
# Actions run these scripts, parameter values are used as they are: a $NAME
# stays literal, and a value starting with "-" is not taken for a flag. A
# stub grype records its arguments and the GRYPE_DB_CACHE_DIR it runs with.

setup() {
    load test_helper
    common_setup

    GRYPE_ARGS="${BATS_TEST_TMPDIR}/grype.args"
    stub grype "if [[ \"\$1\" == version ]]; then echo 'Version:  0.119.0'; exit 0; fi
printf '%s\n' \"\${GRYPE_DB_CACHE_DIR:-}\" \"\$@\" > '${GRYPE_ARGS}'; echo stdout-report"

    local param
    for param in $(awk '/^parameters:/ { p = 1; next } p && /^[^ ]/ { exit } p && /^  [a-z_]+:$/ { sub(/:$/, ""); print $1 }' "${COMMANDS_DIR}/scan.yml"); do
        export "PARAM_${param^^}=$(command_default scan "${param}")"
    done
    export PARAM_DATABASE_DIR
    PARAM_DATABASE_DIR="$(command_default update_database database_dir)"
    export HOME="${BATS_TEST_TMPDIR}/home"
    without_circleci_cli
}

@test "the PATH for these tests has no circleci on it" {
    run command -v circleci
    [ "${status}" -ne 0 ]
}

@test "scan uses values as they are, and takes only_fixed as true or false" {
    # shellcheck disable=SC2016 # a literal $NAME, which only the CLI would expand
    export PARAM_SOURCE='sbom:./-$NAME.json' PARAM_ONLY_FIXED=true

    run bash "${SCRIPTS_DIR}/scan.sh"

    [ "${status}" -eq 0 ]
    # shellcheck disable=SC2016 # the literal value grype must get
    grep -qxF 'sbom:./-$NAME.json' "${GRYPE_ARGS}"
    grep -qxF -- '--only-fixed' "${GRYPE_ARGS}"
    [ "$(cat grype-scan-results.sarif)" = "stdout-report" ]
}

@test "scan with only_fixed false passes no --only-fixed" {
    export PARAM_SOURCE='sbom:./sbom.json' PARAM_ONLY_FIXED=false

    run bash "${SCRIPTS_DIR}/scan.sh"

    [ "${status}" -eq 0 ]
    [ "$(grep -cxF -- '--only-fixed' "${GRYPE_ARGS}")" -eq 0 ]
}

@test "update_database uses database_dir as it is, still expanding a leading ~" {
    # shellcheck disable=SC2016 # a literal $NAME, which only the CLI would expand
    export PARAM_DATABASE_DIR='/opt/$NAME db'

    run bash "${SCRIPTS_DIR}/update_database.sh"

    [ "${status}" -eq 0 ]
    # shellcheck disable=SC2016 # the literal directory grype must get
    [ "$(head -n 1 "${GRYPE_ARGS}")" = '/opt/$NAME db' ]

    # shellcheck disable=SC2088 # a literal ~, expanded by the script
    export PARAM_DATABASE_DIR='~/.cache/grype/db'
    run bash "${SCRIPTS_DIR}/update_database.sh"

    [ "${status}" -eq 0 ]
    [ "$(head -n 1 "${GRYPE_ARGS}")" = "${HOME}/.cache/grype/db" ]
}
