#!/usr/bin/env bats
# VEX parameter tests for src/scripts/scan_image.sh. A stub grype records its
# arguments, one per line, so the tests can check how parameters are mapped.

setup() {
    load test_helper
    common_setup

    GRYPE_ARGS="${BATS_TEST_TMPDIR}/grype.args"
    stub grype "printf '%s\n' \"\$@\" > '${GRYPE_ARGS}'"

    # Start from the defaults the orb passes for every scan_image parameter.
    local param
    for param in $(awk '/^parameters:/ { p = 1; next } p && /^[^ ]/ { exit } p && /^  [a-z_]+:$/ { sub(/:$/, ""); print $1 }' "${COMMANDS_DIR}/scan_image.yml"); do
        export "PARAM_${param^^}=$(command_default scan_image "${param}")"
    done
    export PARAM_SOURCE="sbom:./sbom.json"
    printf '{}\n' > a.openvex.json
    # Keep Grype's home and XDG config search paths inside the test.
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}"
    unset XDG_CONFIG_HOME GRYPE_CONFIG
    export XDG_CONFIG_DIRS="${BATS_TEST_TMPDIR}/xdg"
    printf '{}\n' > b.openvex.json
}

# vex_args: prints the --vex values grype received, one per line.
vex_args() {
    awk 'previous == "--vex" { print } { previous = $0 }' "${GRYPE_ARGS}"
}

@test "vex is empty by default and adds no --vex flags" {
    [ -z "${PARAM_VEX}" ]

    run bash "${SCRIPTS_DIR}/scan_image.sh"

    [ "${status}" -eq 0 ]
    [ "$(grep -cx -- '--vex' "${GRYPE_ARGS}")" -eq 0 ]
}

@test "a single VEX document becomes one --vex flag" {
    export PARAM_VEX=a.openvex.json

    run bash "${SCRIPTS_DIR}/scan_image.sh"

    [ "${status}" -eq 0 ]
    [ "$(vex_args)" = "a.openvex.json" ]
}

@test "comma-separated VEX documents become repeated --vex flags, in order" {
    export PARAM_VEX="b.openvex.json, a.openvex.json"

    run bash "${SCRIPTS_DIR}/scan_image.sh"

    [ "${status}" -eq 0 ]
    [ "$(vex_args)" = "$(printf 'b.openvex.json\na.openvex.json')" ]
}

@test "a missing VEX document fails before scanning" {
    export PARAM_VEX="a.openvex.json,missing.openvex.json"

    run bash "${SCRIPTS_DIR}/scan_image.sh"

    [ "${status}" -ne 0 ]
    [[ "${output}" == *"ERROR: VEX document not found: 'missing.openvex.json'"* ]]
    [ ! -e "${GRYPE_ARGS}" ]
}

@test "an empty entry in the VEX list fails before scanning" {
    export PARAM_VEX="a.openvex.json,,b.openvex.json"

    run bash "${SCRIPTS_DIR}/scan_image.sh"

    [ "${status}" -ne 0 ]
    [[ "${output}" == *"ERROR: VEX document not found: ''"* ]]
    [ ! -e "${GRYPE_ARGS}" ]
}

@test "a trailing comma in the VEX list fails before scanning" {
    export PARAM_VEX="a.openvex.json,"

    run bash "${SCRIPTS_DIR}/scan_image.sh"

    [ "${status}" -ne 0 ]
    [[ "${output}" == *"ERROR: VEX document not found: ''"* ]]
    [ ! -e "${GRYPE_ARGS}" ]
}

@test "vex warns when the config file also lists vex-documents" {
    printf 'vex-documents:\n  - b.openvex.json\n' > grype.yaml
    export PARAM_CONFIG=grype.yaml PARAM_VEX=a.openvex.json

    run bash "${SCRIPTS_DIR}/scan_image.sh"

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"WARN: grype.yaml sets vex-documents"* ]]
    [ "$(vex_args)" = "a.openvex.json" ]
}

@test "a config file with vex-documents alone does not warn" {
    printf 'vex-documents:\n  - b.openvex.json\n' > grype.yaml
    export PARAM_CONFIG=grype.yaml

    run bash "${SCRIPTS_DIR}/scan_image.sh"

    [ "${status}" -eq 0 ]
    [[ "${output}" != *"WARN"* ]]
}

@test "vex warns when an auto-discovered config file lists vex-documents" {
    mkdir -p .grype "${HOME}/.config/grype" "${XDG_CONFIG_DIRS}/grype"
    printf 'vex-documents:\n  - b.openvex.json\n' > .grype/config.yaml
    printf 'vex-documents:\n  - b.openvex.json\n' > "${HOME}/.config/grype/config.yaml"
    printf 'vex-documents:\n  - b.openvex.json\n' > "${XDG_CONFIG_DIRS}/grype/config.yml"
    export PARAM_VEX=a.openvex.json

    run bash "${SCRIPTS_DIR}/scan_image.sh"

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"WARN: .grype/config.yaml sets vex-documents"* ]]
    [[ "${output}" == *"WARN: ${HOME}/.config/grype/config.yaml sets vex-documents"* ]]
    [[ "${output}" == *"WARN: ${XDG_CONFIG_DIRS}/grype/config.yml sets vex-documents"* ]]
}

@test "an explicit config file stops auto-discovered files from warning" {
    printf 'vex-documents:\n  - b.openvex.json\n' > .grype.yaml
    printf 'only-fixed: true\n' > grype.yaml
    export PARAM_CONFIG=grype.yaml PARAM_VEX=a.openvex.json

    run bash "${SCRIPTS_DIR}/scan_image.sh"

    [ "${status}" -eq 0 ]
    [[ "${output}" != *"WARN"* ]]
}

@test "vex warns for other YAML spellings of vex-documents, but not for comments" {
    export PARAM_CONFIG=grype.yaml PARAM_VEX=a.openvex.json
    local spelling
    for spelling in 'vex-documents : [b.openvex.json]' '"vex-documents": [b.openvex.json]' \
        "'vex-documents': [b.openvex.json]" '{vex-documents: [b.openvex.json]}'; do
        printf '%s\n' "${spelling}" > grype.yaml

        run bash "${SCRIPTS_DIR}/scan_image.sh"

        [ "${status}" -eq 0 ]
        [[ "${output}" == *"WARN: grype.yaml sets vex-documents"* ]]
    done

    printf '# vex-documents: [b.openvex.json]\nonly-fixed: true # vex-documents: [b.openvex.json]\n' > grype.yaml
    run bash "${SCRIPTS_DIR}/scan_image.sh"
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"WARN"* ]]
}
