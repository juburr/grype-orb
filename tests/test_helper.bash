# Shared setup for the bats tests in this directory, loaded with `load test_helper`.
#
# Each test gets its own working directory and a stub directory placed ahead
# of the real binaries on PATH. The orb scripts read their parameters through
# `circleci env subst`, so a stub for it is always installed; tests add more
# stubs (grype, wget, uname, ...) with `stub`.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
SCRIPTS_DIR="${REPO_ROOT}/src/scripts"
COMMANDS_DIR="${REPO_ROOT}/src/commands"

common_setup() {
    TEST_WORK_DIR="${BATS_TEST_TMPDIR}/work"
    STUB_DIR="${BATS_TEST_TMPDIR}/stubs"
    mkdir -p "${TEST_WORK_DIR}" "${STUB_DIR}"
    PATH="${STUB_DIR}:${PATH}"
    # CircleCI points BASH_ENV at a file that later steps source. Give each
    # test its own, so scripts under test cannot leak into the real job.
    BASH_ENV="${BATS_TEST_TMPDIR}/bash_env"
    : > "${BASH_ENV}"
    export PATH BASH_ENV
    stub circleci 'if [[ "$1 $2" == "env subst" ]]; then printf "%s\n" "$3"; else exit 1; fi'
    cd "${TEST_WORK_DIR}" || return 1
}

# stub NAME BODY: installs an executable named NAME that runs the bash BODY.
stub() {
    printf '#!/bin/bash\n%s\n' "$2" > "${STUB_DIR}/$1"
    chmod +x "${STUB_DIR}/$1"
}

# command_default COMMAND PARAMETER: prints a parameter's default value from
# src/commands/COMMAND.yml, so tests exercise the defaults users actually get.
command_default() {
    awk -v param="  $2:" '
        $0 == param { found = 1; next }
        found && /^    default:/ { value = $2; gsub(/"/, "", value); print value; exit }
        found && /^  [^ ]/ { exit }
    ' "${COMMANDS_DIR}/$1.yml"
}
