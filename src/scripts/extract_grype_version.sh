#!/bin/bash

set -e

# Determine Grype version
GRYPE_VERSION=$(grype version | grep '^Version:' | awk '{print $2}')

# Place in .bashrc file, making it accessible to all steps in the job
echo "export GRYPE_VERSION=${GRYPE_VERSION}" >> "${BASH_ENV}"

# Log version within pipeline
grype version
