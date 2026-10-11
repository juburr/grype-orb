#!/usr/bin/env bats
# Report output tests for src/scripts/scan_image.sh. A stub grype reports
# FAKE_GRYPE_VERSION for `grype version`; for a scan, it records its arguments,
# one per line, and prints a marker report on stdout.

setup() {
    load test_helper
    common_setup

    GRYPE_ARGS="${BATS_TEST_TMPDIR}/grype.args"
    stub grype "if [[ \"\$1\" == version ]]; then echo \"Version:  \${FAKE_GRYPE_VERSION:-0.119.0}\"; exit 0; fi
printf '%s\n' \"\$@\" > '${GRYPE_ARGS}'; echo stdout-report"

    # Start from the defaults the orb passes for every scan_image parameter.
    local param
    for param in $(awk '/^parameters:/ { p = 1; next } p && /^[^ ]/ { exit } p && /^  [a-z_]+:$/ { sub(/:$/, ""); print $1 }' "${COMMANDS_DIR}/scan_image.yml"); do
        export "PARAM_${param^^}=$(command_default scan_image "${param}")"
    done
    export PARAM_SOURCE="sbom:./sbom.json"
}

# output_args: prints the -o values grype received, one per line.
output_args() {
    awk 'previous == "-o" { print } { previous = $0 }' "${GRYPE_ARGS}"
}

@test "by default, one sarif report is written to grype-scan-results.sarif" {
    run bash "${SCRIPTS_DIR}/scan_image.sh"

    [ "${status}" -eq 0 ]
    [ "$(output_args)" = "sarif" ]
    [ "$(cat grype-scan-results.sarif)" = "stdout-report" ]
}

@test "output_format and output_file still write a single report" {
    export PARAM_OUTPUT_FORMAT=json PARAM_OUTPUT_FILE=scan.json

    run bash "${SCRIPTS_DIR}/scan_image.sh"

    [ "${status}" -eq 0 ]
    [ "$(output_args)" = "json" ]
    [ "$(cat scan.json)" = "stdout-report" ]
}

@test "output_file alone keeps the sarif default format" {
    export PARAM_OUTPUT_FILE=results.sarif

    run bash "${SCRIPTS_DIR}/scan_image.sh"

    [ "${status}" -eq 0 ]
    [ "$(output_args)" = "sarif" ]
    [ "$(cat results.sarif)" = "stdout-report" ]
}

@test "output_formats becomes repeated -o format=path flags from one scan" {
    export PARAM_OUTPUT_FORMATS="json=scan.json, table=reports/scan.txt"

    run bash "${SCRIPTS_DIR}/scan_image.sh"

    [ "${status}" -eq 0 ]
    [ "$(output_args)" = "$(printf 'json=scan.json\ntable=reports/scan.txt')" ]
    [[ "${output}" == *"stdout-report"* ]]
    [ ! -e grype-scan-results.sarif ]
}

@test "output_formats keeps an = inside the path" {
    export PARAM_OUTPUT_FORMATS="json=out/a=b.json"

    run bash "${SCRIPTS_DIR}/scan_image.sh"

    [ "${status}" -eq 0 ]
    [ "$(output_args)" = "json=out/a=b.json" ]
}

@test "output_formats with output_format is rejected" {
    export PARAM_OUTPUT_FORMATS="json=scan.json" PARAM_OUTPUT_FORMAT=sarif

    run bash "${SCRIPTS_DIR}/scan_image.sh"

    [ "${status}" -ne 0 ]
    [[ "${output}" == *"ERROR: output_formats cannot be combined with output_format or output_file"* ]]
    [ ! -e "${GRYPE_ARGS}" ]
}

@test "output_formats with output_file is rejected" {
    export PARAM_OUTPUT_FORMATS="json=scan.json" PARAM_OUTPUT_FILE=scan.sarif

    run bash "${SCRIPTS_DIR}/scan_image.sh"

    [ "${status}" -ne 0 ]
    [[ "${output}" == *"ERROR: output_formats cannot be combined with output_format or output_file"* ]]
    [ ! -e "${GRYPE_ARGS}" ]
}

@test "malformed output_formats entries are rejected" {
    local entry
    for entry in "json" "=scan.json" "json=" "json=scan.json,,table=scan.txt" "json=scan.json,"; do
        export PARAM_OUTPUT_FORMATS="${entry}"

        run bash "${SCRIPTS_DIR}/scan_image.sh"

        [ "${status}" -ne 0 ]
        [[ "${output}" == *"ERROR: output_formats entries must be format=path"* ]]
        [ ! -e "${GRYPE_ARGS}" ]
    done
}

@test "output_formats requires Grype 0.104.1 or later" {
    export PARAM_OUTPUT_FORMATS="json=scan.json,table=scan.txt"
    local version
    for version in 0.63.0 0.104.0 "[not provided]"; do
        export FAKE_GRYPE_VERSION="${version}"

        run bash "${SCRIPTS_DIR}/scan_image.sh"

        [ "${status}" -ne 0 ]
        [[ "${output}" == *"ERROR: output_formats requires Grype 0.104.1 or later"* ]]
        [ ! -e "${GRYPE_ARGS}" ]
    done

    export FAKE_GRYPE_VERSION=0.104.1
    run bash "${SCRIPTS_DIR}/scan_image.sh"
    [ "${status}" -eq 0 ]
}

@test "the single-report style works with older Grype releases" {
    export FAKE_GRYPE_VERSION=0.50.0 PARAM_OUTPUT_FORMAT=json PARAM_OUTPUT_FILE=scan.json

    run bash "${SCRIPTS_DIR}/scan_image.sh"

    [ "${status}" -eq 0 ]
    [ "$(cat scan.json)" = "stdout-report" ]
}

@test "output_formats keeps the step's earlier output when stdout is a file" {
    export PARAM_OUTPUT_FORMATS="json=scan.json"

    bash "${SCRIPTS_DIR}/scan_image.sh" > step.log 2>&1

    grep -q '^Running Grype scan' step.log
    grep -q '^stdout-report$' step.log
    [ "$(tr -d '\0' < step.log | wc -c)" -eq "$(wc -c < step.log)" ]
}
