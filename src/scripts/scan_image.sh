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
VEX=$(circleci env subst "${PARAM_VEX}")

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
echo "  VEX: ${VEX:-<none>}"

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

# Grype does not split a comma-separated --vex value, so pass each document
# as its own flag, and fail early on a path that does not exist.
VEX_ARGS=()
if [[ -n "${VEX}" ]]; then
    IFS=',' read -ra VEX_DOCUMENTS <<< "${VEX}"
    for VEX_DOCUMENT in "${VEX_DOCUMENTS[@]}"; do
        # Trim surrounding whitespace, so "a.json, b.json" works.
        VEX_DOCUMENT="${VEX_DOCUMENT#"${VEX_DOCUMENT%%[![:space:]]*}"}"
        VEX_DOCUMENT="${VEX_DOCUMENT%"${VEX_DOCUMENT##*[![:space:]]}"}"
        if [[ ! -f "${VEX_DOCUMENT}" ]]; then
            echo "ERROR: VEX document not found: '${VEX_DOCUMENT}'" >&2
            exit 2
        fi
        VEX_ARGS+=(--vex "${VEX_DOCUMENT}")
    done

    # --vex replaces the config file's vex-documents instead of merging with
    # it, so documents listed only in the config would silently stop applying.
    if [[ -n "${CONFIG}" ]] && grep -qE '^vex-documents:' "${CONFIG}" 2>/dev/null; then
        echo "WARN: ${CONFIG} sets vex-documents, which Grype ignores when the vex parameter is set." >&2
        echo "WARN: List every VEX document in either the vex parameter or the config file." >&2
    fi
fi

grype "${SCAN_SOURCE}" -o "${OUTPUT_FORMAT}" --add-cpes-if-none -vv \
    "${FAIL_ARG[@]}" "${CONFIG_ARG[@]}" "${ONLY_FIXED_ARG[@]}" "${VEX_ARGS[@]}" > "${OUTPUT_FILE}"

echo "Wrote scan results to: ${OUTPUT_FILE}"
