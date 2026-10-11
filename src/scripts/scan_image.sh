#!/bin/bash

set -euo pipefail

# Read in orb parameters
FAIL_ON=$(circleci env subst "${PARAM_FAIL_ON}")
CONFIG=$(circleci env subst "${PARAM_CONFIG}")
IMAGE=$(circleci env subst "${PARAM_IMAGE}")
ONLY_FIXED=$(circleci env subst "${PARAM_ONLY_FIXED}")
OUTPUT_FILE=$(circleci env subst "${PARAM_OUTPUT_FILE}")
OUTPUT_FORMAT=$(circleci env subst "${PARAM_OUTPUT_FORMAT}")
OUTPUT_FORMATS=$(circleci env subst "${PARAM_OUTPUT_FORMATS}")
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

# Reports are configured either with output_formats (several reports from one
# scan, each written by Grype itself) or with output_format and output_file
# (one report written to stdout and redirected to the file), never both.
if [[ -n "${OUTPUT_FORMATS}" && ( -n "${OUTPUT_FORMAT}" || -n "${OUTPUT_FILE}" ) ]]; then
    echo "ERROR: output_formats cannot be combined with output_format or output_file; use one style." >&2
    exit 2
fi

OUTPUT_ARGS=()
OUTPUT_FILES=()
if [[ -n "${OUTPUT_FORMATS}" ]]; then
    # The extra trailing comma stops read from dropping a final empty entry,
    # so "json=a.json," is rejected like any other malformed entry.
    IFS=',' read -ra OUTPUT_ENTRIES <<< "${OUTPUT_FORMATS},"
    for OUTPUT_ENTRY in "${OUTPUT_ENTRIES[@]}"; do
        # Trim surrounding whitespace, so "json=a.json, table=b.txt" works.
        OUTPUT_ENTRY="${OUTPUT_ENTRY#"${OUTPUT_ENTRY%%[![:space:]]*}"}"
        OUTPUT_ENTRY="${OUTPUT_ENTRY%"${OUTPUT_ENTRY##*[![:space:]]}"}"
        ENTRY_FORMAT="${OUTPUT_ENTRY%%=*}"
        ENTRY_FILE="${OUTPUT_ENTRY#*=}"
        if [[ "${OUTPUT_ENTRY}" != *=* || -z "${ENTRY_FORMAT}" || -z "${ENTRY_FILE}" ]]; then
            echo "ERROR: output_formats entries must be format=path, got: '${OUTPUT_ENTRY}'" >&2
            exit 2
        fi
        OUTPUT_ARGS+=(-o "${ENTRY_FORMAT}=${ENTRY_FILE}")
        OUTPUT_FILES+=("${ENTRY_FILE}")
    done

    # Grype only supports several outputs from 0.64.0, and 0.68.0 through
    # 0.104.0 can write registry credentials into JSON written straight to a
    # file (GHSA-6gxw-85q2-q646), so require a release with the feature and
    # the fix. The single-report style below redirects stdout and is unaffected.
    MIN_OUTPUT_FORMATS_VERSION=0.104.1
    INSTALLED_GRYPE_VERSION=$(grype version | awk '/^Version:/ { sub(/^v/, "", $2); print $2 }')
    if [[ ! "${INSTALLED_GRYPE_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
        [[ "$(printf '%s\n' "${MIN_OUTPUT_FORMATS_VERSION}" "${INSTALLED_GRYPE_VERSION}" | sort -V | head -n 1)" != "${MIN_OUTPUT_FORMATS_VERSION}" ]]; then
        echo "ERROR: output_formats requires Grype ${MIN_OUTPUT_FORMATS_VERSION} or later, found: '${INSTALLED_GRYPE_VERSION}'." >&2
        echo "ERROR: Install a newer Grype, or use output_format and output_file instead." >&2
        exit 2
    fi
    # Grype writes every report to its own file, leaving nothing on stdout.
    STDOUT_FILE=/dev/stdout
else
    OUTPUT_FORMAT=${OUTPUT_FORMAT:-sarif}
    OUTPUT_FILE=${OUTPUT_FILE:-grype-scan-results.sarif}
    OUTPUT_ARGS=(-o "${OUTPUT_FORMAT}")
    OUTPUT_FILES=("${OUTPUT_FILE}")
    STDOUT_FILE=${OUTPUT_FILE}
fi

# Print command arguments for debugging purposes.
echo "Running Grype scan..."
echo "  FAIL_ON: ${FAIL_ON}"
echo "  SOURCE: ${SCAN_SOURCE}"
echo "  CONFIG: ${CONFIG:-<default>}"
echo "  ONLY_FIXED: ${ONLY_FIXED}"
echo "  OUTPUT_FILE: ${OUTPUT_FILE:-<none>}"
echo "  OUTPUT_FORMAT: ${OUTPUT_FORMAT:-<none>}"
echo "  OUTPUT_FORMATS: ${OUTPUT_FORMATS:-<none>}"

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

grype "${SCAN_SOURCE}" "${OUTPUT_ARGS[@]}" --add-cpes-if-none -vv \
    "${FAIL_ARG[@]}" "${CONFIG_ARG[@]}" "${ONLY_FIXED_ARG[@]}" > "${STDOUT_FILE}"

echo "Wrote scan results to: ${OUTPUT_FILES[*]}"
