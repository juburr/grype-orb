#!/usr/bin/env bats
# Report output and source tests for src/scripts/scan.sh. A stub grype reports
# FAKE_GRYPE_VERSION for `grype version`; for a scan, it records its arguments,
# one per line, and prints a marker report on stdout.

setup() {
    load test_helper
    common_setup

    GRYPE_ARGS="${BATS_TEST_TMPDIR}/grype.args"
    stub grype "if [[ \"\$1\" == version ]]; then echo \"Version:  \${FAKE_GRYPE_VERSION:-0.119.0}\"; exit 0; fi
printf '%s\n' \"\$@\" > '${GRYPE_ARGS}'; echo stdout-report"

    # Start from the defaults the orb passes for every scan parameter.
    local param
    for param in $(awk '/^parameters:/ { p = 1; next } p && /^[^ ]/ { exit } p && /^  [a-z_]+:$/ { sub(/:$/, ""); print $1 }' "${COMMANDS_DIR}/scan.yml"); do
        export "PARAM_${param^^}=$(command_default scan "${param}")"
    done
    export PARAM_SOURCE="sbom:./sbom.json"
}

# output_args: prints the -o values grype received, one per line.
output_args() {
    awk 'previous == "-o" { print } { previous = $0 }' "${GRYPE_ARGS}"
}

@test "source is required and has no default" {
    [ -z "$(command_default scan source)" ]
    [ "$(grep -c '^  image:' "${COMMANDS_DIR}/scan.yml")" -eq 0 ]
}

@test "an empty source fails before scanning" {
    export PARAM_SOURCE=""

    run bash "${SCRIPTS_DIR}/scan.sh"

    [ "${status}" -ne 0 ]
    [[ "${output}" == *"ERROR: source is required"* ]]
    [ ! -e "${GRYPE_ARGS}" ]
}

@test "by default, one sarif report is written to grype-scan-results.sarif" {
    [ "${PARAM_OUTPUT}" = "sarif=grype-scan-results.sarif" ]

    run bash "${SCRIPTS_DIR}/scan.sh"

    [ "${status}" -eq 0 ]
    [ "$(output_args)" = "sarif" ]
    [ "$(cat grype-scan-results.sarif)" = "stdout-report" ]
    [[ "${output}" != *"stdout-report"* ]]
}

# With fail_on, config, only_fixed and vex at their defaults, scan.sh expands
# four empty argument arrays. Under set -u, bash before 4.4 treats an empty
# array as unset, so a plain "${a[@]}" aborts the scan with "unbound
# variable"; on any bash, a fix that expands one to "" would pass grype an
# empty argument. So check the exact arguments, one per line.
@test "optional parameters left at their defaults add no arguments to the scan" {
    [ -z "${PARAM_FAIL_ON}${PARAM_CONFIG}${PARAM_VEX}" ]
    [ "${PARAM_ONLY_FIXED}" = false ]

    run bash "${SCRIPTS_DIR}/scan.sh"

    [ "${status}" -eq 0 ]
    [[ "${output}" != *"unbound variable"* ]]
    printf '%s\n' sbom:./sbom.json -o sarif --add-cpes-if-none -vv | diff - "${GRYPE_ARGS}"
}

@test "a single format=file entry redirects stdout to the file, creating its directory" {
    export PARAM_OUTPUT=json=reports/nested/scan.json

    run bash "${SCRIPTS_DIR}/scan.sh"

    [ "${status}" -eq 0 ]
    [ "$(output_args)" = "json" ]
    [ "$(cat reports/nested/scan.json)" = "stdout-report" ]
    [ ! -e grype-scan-results.sarif ]
}

@test "a single entry keeps an = inside the file" {
    export PARAM_OUTPUT="json=out/a=b.json"

    run bash "${SCRIPTS_DIR}/scan.sh"

    [ "${status}" -eq 0 ]
    [ "$(output_args)" = "json" ]
    [ "$(cat "out/a=b.json")" = "stdout-report" ]
}

@test "a single entry without a file prints the report in the step log" {
    export PARAM_OUTPUT=table

    run bash "${SCRIPTS_DIR}/scan.sh"

    [ "${status}" -eq 0 ]
    [ "$(output_args)" = "table" ]
    [[ "${output}" == *"stdout-report"* ]]
    [[ "${output}" == *"Wrote the table report to: the step log"* ]]
    [ ! -e grype-scan-results.sarif ]
}

@test "a single entry works with older Grype releases" {
    export FAKE_GRYPE_VERSION=0.50.0
    local entry
    for entry in json=scan.json table; do
        export PARAM_OUTPUT="${entry}"

        run bash "${SCRIPTS_DIR}/scan.sh"

        [ "${status}" -eq 0 ]
        [ "$(output_args)" = "${entry%%=*}" ]
    done
    [ "$(cat scan.json)" = "stdout-report" ]
}

@test "several entries become repeated -o format=file flags from one scan" {
    export PARAM_OUTPUT="json=scan.json, table=reports/scan.txt"

    run bash "${SCRIPTS_DIR}/scan.sh"

    [ "${status}" -eq 0 ]
    [ "$(output_args)" = "$(printf 'json=scan.json\ntable=reports/scan.txt')" ]
    [ -d reports ]
    [[ "${output}" == *"stdout-report"* ]]
    [ ! -e grype-scan-results.sarif ]
}

@test "several entries may send one report to the step log" {
    export PARAM_OUTPUT="sarif=out/a=b.sarif,table"

    run bash "${SCRIPTS_DIR}/scan.sh"

    [ "${status}" -eq 0 ]
    [ "$(output_args)" = "$(printf 'sarif=out/a=b.sarif\ntable')" ]
    [ -d out ]
    [[ "${output}" == *"stdout-report"* ]]
}

@test "several entries require Grype 0.104.1 or later" {
    export PARAM_OUTPUT="json=scan.json,table=scan.txt"
    local version
    for version in 0.63.0 0.104.0 "[not provided]"; do
        export FAKE_GRYPE_VERSION="${version}"

        run bash "${SCRIPTS_DIR}/scan.sh"

        [ "${status}" -ne 0 ]
        [[ "${output}" == *"ERROR: several output entries require Grype 0.104.1 or later"* ]]
        [ ! -e "${GRYPE_ARGS}" ]
    done

    export FAKE_GRYPE_VERSION=0.104.1
    run bash "${SCRIPTS_DIR}/scan.sh"
    [ "${status}" -eq 0 ]
}

@test "malformed output entries are rejected" {
    local entry
    for entry in "=scan.json" "json=" "json=scan.json,,table=scan.txt" "json=scan.json," ",json=scan.json"; do
        export PARAM_OUTPUT="${entry}"

        run bash "${SCRIPTS_DIR}/scan.sh"

        [ "${status}" -ne 0 ]
        [[ "${output}" == *"ERROR: output entries must be format or format=file"* ]]
        [ ! -e "${GRYPE_ARGS}" ]
    done
}

@test "unknown output formats are rejected" {
    local entry
    for entry in "spdx-json=scan.json" "JSON" "json=scan.json,xml=reports/scan.xml"; do
        export PARAM_OUTPUT="${entry}"

        run bash "${SCRIPTS_DIR}/scan.sh"

        [ "${status}" -ne 0 ]
        [[ "${output}" == *"ERROR: unknown output format"* ]]
        [ ! -e "${GRYPE_ARGS}" ]
        [ ! -e reports ]
    done
}

@test "only one entry may omit a file" {
    export PARAM_OUTPUT="table,json"

    run bash "${SCRIPTS_DIR}/scan.sh"

    [ "${status}" -ne 0 ]
    [[ "${output}" == *"ERROR: at most one output entry can omit a file"* ]]
    [ ! -e "${GRYPE_ARGS}" ]
}

@test "whitespace and newlines around output are ignored" {
    export PARAM_OUTPUT=$'\n json=scan.json \n'

    run bash "${SCRIPTS_DIR}/scan.sh"

    [ "${status}" -eq 0 ]
    [ "$(output_args)" = "json" ]
    [ "$(cat scan.json)" = "stdout-report" ]
}

# read stops at a newline, so a list over several lines would lose the
# entries after the first line.
@test "an output list over several lines is rejected" {
    local value
    for value in $'json=scan.json,\ntable=scan.txt' $'json=scan.json\ntable'; do
        export PARAM_OUTPUT="${value}"

        run bash "${SCRIPTS_DIR}/scan.sh"

        [ "${status}" -ne 0 ]
        [[ "${output}" == *"ERROR: output must be on one line"* ]]
        [ ! -e "${GRYPE_ARGS}" ]
    done
}

@test "an empty output is rejected" {
    local value
    for value in "" "  "; do
        export PARAM_OUTPUT="${value}"

        run bash "${SCRIPTS_DIR}/scan.sh"

        [ "${status}" -ne 0 ]
        [[ "${output}" == *"ERROR: output is empty"* ]]
        [ ! -e "${GRYPE_ARGS}" ]
    done
}

@test "several entries keep the step's earlier output when stdout is a file" {
    export PARAM_OUTPUT="json=scan.json,table"

    bash "${SCRIPTS_DIR}/scan.sh" > step.log 2>&1

    grep -q '^Running Grype scan' step.log
    grep -q '^stdout-report$' step.log
    [ "$(tr -d '\0' < step.log | wc -c)" -eq "$(wc -c < step.log)" ]
}
