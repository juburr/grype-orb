#!/bin/bash

# Convenience script, not used by directly by the production orb, but
# for development purposes when adding SHA-512 checksums to the lookup
# tables in install.sh. Prints one entry per architecture, ready to paste
# into the matching sha512sums_<arch> table.
#
# Each tarball is checked against the release's checksums.txt before its
# grype binary is hashed. If cosign is installed, the signature on
# checksums.txt is verified as well.

set -e
set +o history

# Fetch CLI arguments
# Can also be set as environment variables.
ARCHS=${ARCHS:-"amd64 arm64"}
while getopts :v:a: flag
do
    case "${flag}" in
        v) VERSION=${OPTARG};;
        a) ARCHS=${OPTARG};;
        *) echo "Invalid option: -${OPTARG}" >&2; exit 1;;
    esac
done

# Validate input arguments
if [[ -z "${VERSION}" ]]; then
  echo "Must specify a version number."
  echo "Usage: $0 -v 1.0.0 [-a amd64|arm64]"
  echo "Alternatively: VERSION=1.0.0 $0"
  exit 1
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "${WORK_DIR}"' EXIT
cd "${WORK_DIR}"

BASE_URL="https://github.com/anchore/grype/releases/download/v${VERSION}"
CHECKSUMS_FILE="grype_${VERSION}_checksums.txt"
wget -q "${BASE_URL}/${CHECKSUMS_FILE}"

# Grype has signed checksums.txt since 0.72.0, always from its release
# workflow on main. Older releases publish no signature at all.
FIRST_SIGNED_VERSION=0.72.0
if command -v cosign > /dev/null; then
    if [[ "$(printf '%s\n' "${FIRST_SIGNED_VERSION}" "${VERSION}" | sort -V | head -n 1)" != "${FIRST_SIGNED_VERSION}" ]]; then
        echo "WARN: Grype ${VERSION} predates signed releases; checking tarballs against checksums.txt only." >&2
    else
        wget -q "${BASE_URL}/${CHECKSUMS_FILE}.sig" "${BASE_URL}/${CHECKSUMS_FILE}.pem"
        cosign verify-blob \
            --certificate "${CHECKSUMS_FILE}.pem" \
            --signature "${CHECKSUMS_FILE}.sig" \
            --certificate-identity https://github.com/anchore/grype/.github/workflows/release.yaml@refs/heads/main \
            --certificate-oidc-issuer https://token.actions.githubusercontent.com \
            "${CHECKSUMS_FILE}" > /dev/null 2>&1 \
            || { echo "ERROR: cosign could not verify the signature on ${CHECKSUMS_FILE}." >&2; exit 1; }
    fi
fi

# Download each architecture's tarball, check it against checksums.txt, and
# get the SHA-512 checksum of the grype binary inside. Suppress output for
# readability; this is a dev script, so simply re-enable output if you need
# to debug anything.
for ARCH in ${ARCHS}; do
    TARBALL="grype_${VERSION}_linux_${ARCH}.tar.gz"
    wget -q "${BASE_URL}/${TARBALL}"
    grep " ${TARBALL}\$" "${CHECKSUMS_FILE}" | sha256sum --check --quiet -
    mkdir "${ARCH}"
    tar -xzf "${TARBALL}" -C "${ARCH}" grype
    CHECKSUM=$(sha512sum "${ARCH}/grype" | awk '{ print $1 }')
    echo "sha512sums_${ARCH}:"
    echo "    [\"${VERSION}\"]=\"${CHECKSUM}\""
done
