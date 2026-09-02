#!/bin/bash

set -euo pipefail

# Read in orb parameters
FAIL_ON=$(circleci env subst "${PARAM_FAIL_ON}")
CONFIG=$(circleci env subst "${PARAM_CONFIG}")
IMAGE=$(circleci env subst "${PARAM_IMAGE}")
ONLY_FIXED=$(circleci env subst "${PARAM_ONLY_FIXED}")
OUTPUT_FILE=$(circleci env subst "${PARAM_OUTPUT_FILE}")
OUTPUT_FORMAT=$(circleci env subst "${PARAM_OUTPUT_FORMAT}")
SOURCE=$(circleci env subst "${PARAM_SOURCE}")

if [[ -n "${SOURCE}" && -n "${IMAGE}" ]]; then
    echo "ERROR: source and image are mutually exclusive; set exactly one." >&2
    exit 2
fi

SCAN_SOURCE=${SOURCE:-${IMAGE}}
if [[ -z "${SCAN_SOURCE}" ]]; then
    echo "ERROR: one of source or image is required." >&2
    exit 2
fi

# Print command arguments for debugging purposes.
echo "Running Grype scan..."
echo "  FAIL_ON: ${FAIL_ON}"
echo "  SOURCE: ${SCAN_SOURCE}"
echo "  CONFIG: ${CONFIG:-<default>}"
echo "  ONLY_FIXED: ${ONLY_FIXED}"
echo "  OUTPUT_FILE: ${OUTPUT_FILE}"
echo "  OUTPUT_FORMAT: ${OUTPUT_FORMAT}"

FAIL_ARG=()
if [[ -n "${FAIL_ON}" ]]; then
    FAIL_ARG=(--fail-on "${FAIL_ON}")
fi

CONFIG_ARG=()
if [[ -n "${CONFIG}" ]]; then
    CONFIG_ARG=(--config "${CONFIG}")
fi

ONLY_FIXED_ARG=()
case "${ONLY_FIXED}" in
    true|1)
        ONLY_FIXED_ARG=(--only-fixed)
        ;;
    false|0|"")
        ;;
    *)
        echo "ERROR: only_fixed must resolve to true or false, got: ${ONLY_FIXED}" >&2
        exit 2
        ;;
esac

grype "${SCAN_SOURCE}" -o "${OUTPUT_FORMAT}" --add-cpes-if-none -vv \
    "${FAIL_ARG[@]}" "${CONFIG_ARG[@]}" "${ONLY_FIXED_ARG[@]}" > "${OUTPUT_FILE}"

echo "Wrote scan results to: ${OUTPUT_FILE}"
