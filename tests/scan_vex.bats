#!/usr/bin/env bats
# VEX parameter tests for src/scripts/scan.sh. A stub grype records the
# arguments of a scan, one per line, so the tests can check how parameters are
# mapped. For `grype config --load` it records those arguments separately and
# prints GRYPE_CONFIG_DUMP, modelled on Grype's real output, or fails when that
# file is missing, as Grype releases before 0.78.0 do.

setup() {
    load test_helper
    common_setup

    GRYPE_ARGS="${BATS_TEST_TMPDIR}/grype.args"
    GRYPE_CONFIG_ARGS="${BATS_TEST_TMPDIR}/grype-config.args"
    GRYPE_CONFIG_DUMP="${BATS_TEST_TMPDIR}/grype-config.yaml"
    stub grype "if [[ \"\$1 \$2\" == 'config --load' ]]; then
    printf '%s\n' \"\$@\" > '${GRYPE_CONFIG_ARGS}'
    [[ -f '${GRYPE_CONFIG_DUMP}' ]] || exit 1
    cat '${GRYPE_CONFIG_DUMP}'
    exit 0
fi
printf '%s\n' \"\$@\" > '${GRYPE_ARGS}'"
    config_dump 'vex-documents: []'

    # Start from the defaults the orb passes for every scan parameter.
    local param
    for param in $(awk '/^parameters:/ { p = 1; next } p && /^[^ ]/ { exit } p && /^  [a-z_]+:$/ { sub(/:$/, ""); print $1 }' "${COMMANDS_DIR}/scan.yml"); do
        export "PARAM_${param^^}=$(command_default scan "${param}")"
    done
    export PARAM_SOURCE="sbom:./sbom.json"
    printf '{}\n' > a.openvex.json
    printf '{}\n' > b.openvex.json
}

# config_dump LINES...: sets what the stub's `grype config --load` prints for
# the vex-documents setting, between the neighbouring keys Grype prints.
config_dump() {
    {
        printf 'from: []\n\n'
        printf '# a list of VEX documents to consider when producing scanning results (env: GRYPE_VEX_DOCUMENTS)\n'
        printf '%s\n' "$@"
        printf '\n# VEX statuses to consider as ignored rules (env: GRYPE_VEX_ADD)\nvex-add: []\n'
    } > "${GRYPE_CONFIG_DUMP}"
}

# vex_args: prints the --vex values grype received, one per line.
vex_args() {
    awk 'previous == "--vex" { print } { previous = $0 }' "${GRYPE_ARGS}"
}

@test "vex is empty by default and adds no --vex flags" {
    [ -z "${PARAM_VEX}" ]

    run bash "${SCRIPTS_DIR}/scan.sh"

    [ "${status}" -eq 0 ]
    [ "$(grep -cx -- '--vex' "${GRYPE_ARGS}")" -eq 0 ]
}

@test "a single VEX document becomes one --vex flag" {
    export PARAM_VEX=a.openvex.json

    run bash "${SCRIPTS_DIR}/scan.sh"

    [ "${status}" -eq 0 ]
    [ "$(vex_args)" = "a.openvex.json" ]
}

@test "comma-separated VEX documents become repeated --vex flags, in order" {
    export PARAM_VEX="b.openvex.json, a.openvex.json"

    run bash "${SCRIPTS_DIR}/scan.sh"

    [ "${status}" -eq 0 ]
    [ "$(vex_args)" = "$(printf 'b.openvex.json\na.openvex.json')" ]
}

@test "a missing VEX document fails before scanning" {
    export PARAM_VEX="a.openvex.json,missing.openvex.json"

    run bash "${SCRIPTS_DIR}/scan.sh"

    [ "${status}" -ne 0 ]
    [[ "${output}" == *"ERROR: VEX document not found: 'missing.openvex.json'"* ]]
    [ ! -e "${GRYPE_ARGS}" ]
}

@test "an empty entry in the VEX list fails before scanning" {
    export PARAM_VEX="a.openvex.json,,b.openvex.json"

    run bash "${SCRIPTS_DIR}/scan.sh"

    [ "${status}" -ne 0 ]
    [[ "${output}" == *"ERROR: VEX document not found: ''"* ]]
    [ ! -e "${GRYPE_ARGS}" ]
}

@test "a trailing comma in the VEX list fails before scanning" {
    export PARAM_VEX="a.openvex.json,"

    run bash "${SCRIPTS_DIR}/scan.sh"

    [ "${status}" -ne 0 ]
    [[ "${output}" == *"ERROR: VEX document not found: ''"* ]]
    [ ! -e "${GRYPE_ARGS}" ]
}

@test "vex warns when Grype's configuration lists vex-documents" {
    config_dump 'vex-documents:' "  - 'b.openvex.json'" "  - 'policy/c.openvex.json'"
    export PARAM_CONFIG=grype.yaml PARAM_VEX=a.openvex.json

    run bash "${SCRIPTS_DIR}/scan.sh"

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"WARN: Grype's configuration lists vex-documents (b.openvex.json, policy/c.openvex.json)"* ]]
    [ "$(cat "${GRYPE_CONFIG_ARGS}")" = "$(printf 'config\n--load\n--config\ngrype.yaml')" ]
    [ "$(vex_args)" = "a.openvex.json" ]
}

@test "vex does not warn when Grype's configuration lists no vex-documents" {
    export PARAM_VEX=a.openvex.json

    run bash "${SCRIPTS_DIR}/scan.sh"

    [ "${status}" -eq 0 ]
    [[ "${output}" != *"WARN"* ]]
    [ "$(cat "${GRYPE_CONFIG_ARGS}")" = "$(printf 'config\n--load')" ]
}

@test "without vex, Grype's configuration is not queried" {
    config_dump 'vex-documents:' "  - 'b.openvex.json'"

    run bash "${SCRIPTS_DIR}/scan.sh"

    [ "${status}" -eq 0 ]
    [[ "${output}" != *"WARN"* ]]
    [ ! -e "${GRYPE_CONFIG_ARGS}" ]
}

@test "vex notes the replacement when Grype cannot report its configuration" {
    rm "${GRYPE_CONFIG_DUMP}"
    export PARAM_VEX=a.openvex.json

    run bash "${SCRIPTS_DIR}/scan.sh"

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"WARN: Could not read Grype's configuration (grype config --load needs Grype 0.78.0 or later)."* ]]
    [ "$(vex_args)" = "a.openvex.json" ]
}
