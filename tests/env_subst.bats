#!/usr/bin/env bats
# Parameter values must reach `circleci env subst` on stdin:
#
#   VALUE=$(printf '%s' "${PARAM_VALUE}" | circleci env subst)
#
# Passed as an argument instead, a value that starts with "-" (such as
# "--no-cache") is parsed by the CLI as a flag rather than substituted, so the
# step fails or gets the wrong value. The CLI tests run against whatever
# circleci CLI is on the PATH, which in a CircleCI job is the job's own.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

# subst VALUE: substitutes VALUE the way the orb's scripts do.
subst() {
    printf '%s' "$1" | circleci env subst
}

@test "no script or command passes a value to circleci env subst as an argument" {
    cd "${REPO_ROOT}"
    # A quote, "$" or "-" after the command means a value is passed as an
    # argument. Comment lines are skipped, since they may describe that form.
    calls=$(grep -rnE "circleci env subst[[:space:]]+[\"'\$-]" src \
        | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)
    if [[ -n "${calls}" ]]; then
        echo "Pass values to circleci env subst on stdin, not as an argument:"
        echo "${calls}"
        return 1
    fi
}

@test "the circleci CLI leaves values that start with - intact on stdin" {
    command -v circleci > /dev/null || skip "no circleci CLI on the PATH"
    for value in --no-cache --help -n -e; do
        got=$(subst "${value}")
        if [[ "${got}" != "${value}" ]]; then
            echo "${value} became ${got}"
            return 1
        fi
    done
}

@test "the circleci CLI still expands variables on stdin" {
    command -v circleci > /dev/null || skip "no circleci CLI on the PATH"
    export ORB_ENV_SUBST_TEST_VALUE="expanded"
    # shellcheck disable=SC2016 # expanded by circleci env subst, not by bash
    [ "$(subst '--label=${ORB_ENV_SUBST_TEST_VALUE}')" = "--label=expanded" ]
    # shellcheck disable=SC2016 # expanded by circleci env subst, not by bash
    [ "$(subst '$ORB_ENV_SUBST_TEST_VALUE')" = "expanded" ]
}
