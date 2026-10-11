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
else
    OUTPUT_FORMAT=${OUTPUT_FORMAT:-sarif}
    OUTPUT_FILE=${OUTPUT_FILE:-grype-scan-results.sarif}
    OUTPUT_ARGS=(-o "${OUTPUT_FORMAT}")
    OUTPUT_FILES=("${OUTPUT_FILE}")
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
    # The extra trailing comma stops read from dropping a final empty entry,
    # so "a.json," is rejected like any other empty entry.
    IFS=',' read -ra VEX_DOCUMENTS <<< "${VEX},"
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

    # --vex replaces the vex-documents in Grype's configuration instead of
    # merging with them, so documents listed only there would silently stop
    # applying. Ask Grype for its resolved configuration rather than parsing
    # YAML here: that covers the config file, Grype's search paths and
    # GRYPE_VEX_DOCUMENTS, in any valid spelling.
    if CONFIG_DUMP=$(grype config --load "${CONFIG_ARG[@]}" 2>/dev/null); then
        CONFIGURED_VEX=$(awk '
            /^vex-documents:/ { found = 1; sub(/^vex-documents:[[:space:]]*/, ""); if ($0 != "[]") docs = $0; next }
            found && /^[[:space:]]+- / { sub(/^[[:space:]]+- /, ""); docs = docs (docs == "" ? "" : ", ") $0; next }
            found && !/^[[:space:]]*$/ { exit }
            END { gsub(/["\047]/, "", docs); print docs }
        ' <<< "${CONFIG_DUMP}")
        if [[ -n "${CONFIGURED_VEX}" ]]; then
            echo "WARN: Grype's configuration lists vex-documents (${CONFIGURED_VEX}), which the vex parameter replaces rather than adds to." >&2
            echo "WARN: List every VEX document in either the vex parameter or the config file." >&2
        fi
    else
        echo "WARN: Could not read Grype's configuration (grype config --load needs Grype 0.78.0 or later)." >&2
        echo "WARN: Note that the vex parameter replaces any vex-documents listed there rather than adding to them." >&2
    fi
fi

# The single report goes to stdout, redirected to output_file. With
# output_formats Grype writes every report itself, so its stdout stays the
# step's own: duplicate it rather than reopening /dev/stdout, which would
# truncate the step's output when that is a regular file.
if [[ -n "${OUTPUT_FORMATS}" ]]; then
    exec 3>&1
else
    exec 3> "${OUTPUT_FILE}"
fi

grype "${SCAN_SOURCE}" "${OUTPUT_ARGS[@]}" --add-cpes-if-none -vv \
    "${FAIL_ARG[@]}" "${CONFIG_ARG[@]}" "${ONLY_FIXED_ARG[@]}" "${VEX_ARGS[@]}" >&3

echo "Wrote scan results to: ${OUTPUT_FILES[*]}"
