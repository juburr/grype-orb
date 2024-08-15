#!/bin/bash

set -e

# Read in orb parameters
FAIL_ON=$(circleci env subst "${PARAM_FAIL_ON}")
IMAGE=$(circleci env subst "${PARAM_IMAGE}")
OUTPUT_FILE=$(circleci env subst "${PARAM_OUTPUT_FILE}")
OUTPUT_FORMAT=$(circleci env subst "${PARAM_OUTPUT_FORMAT}")

# Print command arguments for debugging purposes.
echo "Running Grype scan..."
echo "  FAIL_ON: ${FAIL_ON}"
echo "  IMAGE: ${IMAGE}"
echo "  OUTPUT_FILE: ${OUTPUT_FILE}"
echo "  OUTPUT_FORMAT: ${OUTPUT_FORMAT}"

FAIL_ARG=()
if [[ -n "${FAIL_ON}" ]]; then
    FAIL_ARG=(--fail-on "${FAIL_ON}")
fi

grype "${IMAGE}" -o "${OUTPUT_FORMAT}" --add-cpes-if-none -vv "${FAIL_ARG[@]}" > "${OUTPUT_FILE}"

echo "Wrote scan results to: ${OUTPUT_FILE}"
