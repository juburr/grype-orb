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

grype "${SCAN_SOURCE}" -o "${OUTPUT_FORMAT}" --add-cpes-if-none -vv \
    "${FAIL_ARG[@]}" "${CONFIG_ARG[@]}" "${ONLY_FIXED_ARG[@]}" "${VEX_ARGS[@]}" > "${OUTPUT_FILE}"

echo "Wrote scan results to: ${OUTPUT_FILE}"
