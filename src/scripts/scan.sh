#!/bin/bash

set -euo pipefail

# subst VALUE: expands environment variables in VALUE with the CircleCI CLI,
# which reads it on stdin. Without the CLI, as in GitHub Actions or a local
# run, the value is used as it is.
subst() {
    if command -v circleci > /dev/null 2>&1; then
        printf '%s' "$1" | circleci env subst
    else
        printf '%s\n' "$1"
    fi
}

# Read in orb parameters
FAIL_ON=$(subst "${PARAM_FAIL_ON}")
CONFIG=$(subst "${PARAM_CONFIG}")
ONLY_FIXED=$(subst "${PARAM_ONLY_FIXED}")
OUTPUT=$(subst "${PARAM_OUTPUT}")
SOURCE=$(subst "${PARAM_SOURCE}")
VEX=$(subst "${PARAM_VEX}")

if [[ -z "${SOURCE}" ]]; then
    echo "ERROR: source is required, but it is empty." >&2
    exit 2
fi

# output and vex are comma-separated lists on one line: read stops at a
# newline, so the entries after one would be lost. Whitespace around a list,
# such as the final newline of a YAML block scalar, is ignored.
OUTPUT="${OUTPUT#"${OUTPUT%%[![:space:]]*}"}"
OUTPUT="${OUTPUT%"${OUTPUT##*[![:space:]]}"}"
VEX="${VEX#"${VEX%%[![:space:]]*}"}"
VEX="${VEX%"${VEX##*[![:space:]]}"}"

# output uses Grype's own -o syntax: a comma-separated list of entries, each
# "format" (printed in the step log) or "format=file". REPORT_FORMATS and
# REPORT_FILES hold one element per entry, with an empty file for the log.
if [[ -z "${OUTPUT}" ]]; then
    echo "ERROR: output is empty; list at least one format, such as sarif=grype-scan-results.sarif or table." >&2
    exit 2
fi
if [[ "${OUTPUT}" == *$'\n'* ]]; then
    echo "ERROR: output must be on one line; separate its entries with commas." >&2
    exit 2
fi
VALID_REPORT_FORMATS=(json table cyclonedx cyclonedx-json sarif template)
REPORT_FORMATS=()
REPORT_FILES=()
STDOUT_ENTRIES=0
# The extra trailing comma stops read from dropping a final empty entry, so
# "json=a.json," is rejected like any other malformed entry.
IFS=',' read -ra OUTPUT_ENTRIES <<< "${OUTPUT},"
# Arrays that can be empty are expanded as ${a[@]+"${a[@]}"}: under set -u,
# bash before 4.4 treats an empty array as unset and "${a[@]}" aborts.
for OUTPUT_ENTRY in ${OUTPUT_ENTRIES[@]+"${OUTPUT_ENTRIES[@]}"}; do
    # Trim surrounding whitespace, so "json=a.json, table" works.
    OUTPUT_ENTRY="${OUTPUT_ENTRY#"${OUTPUT_ENTRY%%[![:space:]]*}"}"
    OUTPUT_ENTRY="${OUTPUT_ENTRY%"${OUTPUT_ENTRY##*[![:space:]]}"}"
    # Only the first "=" separates the format, so a file may contain "=".
    ENTRY_FORMAT="${OUTPUT_ENTRY%%=*}"
    ENTRY_FILE=""
    if [[ "${OUTPUT_ENTRY}" == *=* ]]; then
        ENTRY_FILE="${OUTPUT_ENTRY#*=}"
    fi
    if [[ -z "${ENTRY_FORMAT}" || ( "${OUTPUT_ENTRY}" == *=* && -z "${ENTRY_FILE}" ) ]]; then
        echo "ERROR: output entries must be format or format=file, got: '${OUTPUT_ENTRY}'" >&2
        exit 2
    fi
    if [[ " ${VALID_REPORT_FORMATS[*]} " != *" ${ENTRY_FORMAT} "* ]]; then
        echo "ERROR: unknown output format '${ENTRY_FORMAT}'; use one of: ${VALID_REPORT_FORMATS[*]}" >&2
        exit 2
    fi
    if [[ -z "${ENTRY_FILE}" ]]; then
        STDOUT_ENTRIES=$((STDOUT_ENTRIES + 1))
    fi
    REPORT_FORMATS+=("${ENTRY_FORMAT}")
    REPORT_FILES+=("${ENTRY_FILE}")
done

# The step log can only hold one report.
if [[ "${STDOUT_ENTRIES}" -gt 1 ]]; then
    echo "ERROR: at most one output entry can omit a file, got ${STDOUT_ENTRIES}: '${OUTPUT}'" >&2
    exit 2
fi

OUTPUT_ARGS=()
if [[ "${#REPORT_FORMATS[@]}" -eq 1 ]]; then
    # A single report is written to stdout, which is redirected to its file
    # below, so it works with any Grype release.
    OUTPUT_ARGS=(-o "${REPORT_FORMATS[0]}")
else
    # Grype only supports several outputs from 0.64.0, and 0.68.0 through
    # 0.104.0 can write registry credentials into JSON written straight to a
    # file (GHSA-6gxw-85q2-q646), so require a release with the feature and
    # the fix. A single entry is written through stdout and is unaffected.
    MIN_MULTIPLE_OUTPUTS_VERSION=0.104.1
    INSTALLED_GRYPE_VERSION=$(grype version | awk '/^Version:/ { sub(/^v/, "", $2); print $2 }')
    if [[ ! "${INSTALLED_GRYPE_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
        [[ "$(printf '%s\n' "${MIN_MULTIPLE_OUTPUTS_VERSION}" "${INSTALLED_GRYPE_VERSION}" | sort -V | head -n 1)" != "${MIN_MULTIPLE_OUTPUTS_VERSION}" ]]; then
        echo "ERROR: several output entries require Grype ${MIN_MULTIPLE_OUTPUTS_VERSION} or later, found: '${INSTALLED_GRYPE_VERSION}'." >&2
        echo "ERROR: Install a newer Grype, or list a single output entry." >&2
        exit 2
    fi
    for i in "${!REPORT_FORMATS[@]}"; do
        if [[ -n "${REPORT_FILES[i]}" ]]; then
            OUTPUT_ARGS+=(-o "${REPORT_FORMATS[i]}=${REPORT_FILES[i]}")
        else
            OUTPUT_ARGS+=(-o "${REPORT_FORMATS[i]}")
        fi
    done
fi

# Print command arguments for debugging purposes.
echo "Running Grype scan..."
echo "  FAIL_ON: ${FAIL_ON}"
echo "  SOURCE: ${SOURCE}"
echo "  CONFIG: ${CONFIG:-<default>}"
echo "  ONLY_FIXED: ${ONLY_FIXED}"
echo "  OUTPUT: ${OUTPUT}"
echo "  VEX: ${VEX:-<none>}"

FAIL_ARG=()
case "${FAIL_ON}" in
    never) ;;
    negligible|low|medium|high|critical) FAIL_ARG=(--fail-on "${FAIL_ON}") ;;
    *)
        echo "ERROR: fail_on must be critical, high, medium, low, negligible, or never; got '${FAIL_ON}'." >&2
        exit 2
        ;;
esac

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
if [[ "${VEX}" == *$'\n'* ]]; then
    echo "ERROR: vex must be on one line; separate its documents with commas." >&2
    exit 2
fi
if [[ -n "${VEX}" ]]; then
    # The extra trailing comma stops read from dropping a final empty entry,
    # so "a.json," is rejected like any other empty entry.
    IFS=',' read -ra VEX_DOCUMENTS <<< "${VEX},"
    for VEX_DOCUMENT in ${VEX_DOCUMENTS[@]+"${VEX_DOCUMENTS[@]}"}; do
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
    if CONFIG_DUMP=$(grype config --load ${CONFIG_ARG[@]+"${CONFIG_ARG[@]}"} 2>/dev/null); then
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

for REPORT_FILE in ${REPORT_FILES[@]+"${REPORT_FILES[@]}"}; do
    if [[ -n "${REPORT_FILE}" ]]; then
        mkdir -p -- "$(dirname -- "${REPORT_FILE}")"
    fi
done

# A single report with a file goes to stdout, redirected to that file.
# Otherwise Grype writes any files itself and its stdout stays the step's own:
# duplicate it rather than reopening /dev/stdout, which would truncate the
# step's output when that is a regular file.
if [[ "${#REPORT_FORMATS[@]}" -eq 1 && -n "${REPORT_FILES[0]}" ]]; then
    exec 3> "${REPORT_FILES[0]}"
else
    exec 3>&1
fi

grype "${SOURCE}" ${OUTPUT_ARGS[@]+"${OUTPUT_ARGS[@]}"} --add-cpes-if-none -vv \
    ${FAIL_ARG[@]+"${FAIL_ARG[@]}"} ${CONFIG_ARG[@]+"${CONFIG_ARG[@]}"} \
    ${ONLY_FIXED_ARG[@]+"${ONLY_FIXED_ARG[@]}"} ${VEX_ARGS[@]+"${VEX_ARGS[@]}"} >&3

for i in "${!REPORT_FORMATS[@]}"; do
    echo "Wrote the ${REPORT_FORMATS[i]} report to: ${REPORT_FILES[i]:-the step log}"
done
