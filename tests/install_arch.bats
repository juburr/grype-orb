#!/usr/bin/env bats
# Architecture tests for src/scripts/install.sh. They run offline: a stub
# uname reports the platform under test, and stub wget and curl record each
# download and serve a fake Grype tarball.

setup() {
    load test_helper
    common_setup

    INSTALL_DIR="${BATS_TEST_TMPDIR}/bin"
    DOWNLOAD_LOG="${BATS_TEST_TMPDIR}/downloads.log"
    FAKE_TARBALL="${BATS_TEST_TMPDIR}/fake-grype.tar.gz"
    mkdir -p "${BATS_TEST_TMPDIR}/release"
    printf '#!/bin/sh\necho fake grype\n' > "${BATS_TEST_TMPDIR}/release/grype"
    tar -czf "${FAKE_TARBALL}" -C "${BATS_TEST_TMPDIR}/release" grype

    local download='url=""; out=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -O|-o) out="$2"; shift 2 ;;
        https://*) url="$1"; shift ;;
        *) shift ;;
    esac
done'
    stub wget "${download}
echo \"\${url}\" >> '${DOWNLOAD_LOG}'
cp '${FAKE_TARBALL}' \"\${out}\""
    cp "${STUB_DIR}/wget" "${STUB_DIR}/curl"
    stub uname 'case "$1" in -s) echo "${FAKE_OS:-Linux}" ;; -m) echo "${FAKE_ARCH}" ;; *) exit 1 ;; esac'

    export PARAM_INSTALL_PATH="${INSTALL_DIR}"
    export PARAM_VERSION="0.0.0-unlisted"
    export PARAM_VERIFY_CHECKSUMS=known_versions
}

# expected_checksum ARCH: runs a strict install of the default version with the
# fake tarball, and prints the checksum install.sh compared it against.
expected_checksum() {
    FAKE_ARCH="$1" PARAM_VERIFY_CHECKSUMS=strict PARAM_VERSION="$(command_default install version)" \
        bash "${SCRIPTS_DIR}/install.sh" 2>&1 | awk '/Expected:/ { print $2 }'
}

@test "x86_64 downloads the linux_amd64 asset" {
    export FAKE_ARCH=x86_64

    run bash "${SCRIPTS_DIR}/install.sh"

    [ "${status}" -eq 0 ]
    [ "$(cat "${DOWNLOAD_LOG}")" = "https://github.com/anchore/grype/releases/download/v0.0.0-unlisted/grype_0.0.0-unlisted_linux_amd64.tar.gz" ]
}

@test "aarch64 downloads the linux_arm64 asset" {
    export FAKE_ARCH=aarch64

    run bash "${SCRIPTS_DIR}/install.sh"

    [ "${status}" -eq 0 ]
    [ "$(cat "${DOWNLOAD_LOG}")" = "https://github.com/anchore/grype/releases/download/v0.0.0-unlisted/grype_0.0.0-unlisted_linux_arm64.tar.gz" ]
}

@test "arm64 downloads the linux_arm64 asset" {
    export FAKE_ARCH=arm64

    run bash "${SCRIPTS_DIR}/install.sh"

    [ "${status}" -eq 0 ]
    grep -q '_linux_arm64\.tar\.gz$' "${DOWNLOAD_LOG}"
}

@test "an unsupported architecture is a hard error" {
    export FAKE_ARCH=s390x

    run bash "${SCRIPTS_DIR}/install.sh"

    [ "${status}" -ne 0 ]
    [[ "${output}" == *"ERROR: Unsupported CPU architecture: s390x."* ]]
    [ ! -e "${DOWNLOAD_LOG}" ]
    [ ! -e "${INSTALL_DIR}/grype" ]
}

@test "a non-Linux operating system is a hard error" {
    export FAKE_OS=Darwin FAKE_ARCH=arm64

    run bash "${SCRIPTS_DIR}/install.sh"

    [ "${status}" -ne 0 ]
    [[ "${output}" == *"ERROR: Unsupported operating system: Darwin."* ]]
    [ ! -e "${DOWNLOAD_LOG}" ]
}

@test "the default version has a distinct checksum for each architecture" {
    local amd64 arm64
    amd64=$(expected_checksum x86_64)
    arm64=$(expected_checksum aarch64)

    [ "${#amd64}" -eq 128 ]
    [ "${#arm64}" -eq 128 ]
    [ "${amd64}" != "${arm64}" ]
    awk '/^sha512sums_amd64=\(/,/^\)/' "${SCRIPTS_DIR}/install.sh" | grep -q "\"${amd64}\""
    awk '/^sha512sums_arm64=\(/,/^\)/' "${SCRIPTS_DIR}/install.sh" | grep -q "\"${arm64}\""
}

@test "a missing install path is created and exported to later steps" {
    export FAKE_ARCH=x86_64

    run bash "${SCRIPTS_DIR}/install.sh"

    [ "${status}" -eq 0 ]
    [ -x "${INSTALL_DIR}/grype" ]
    grep -qxF "export PATH=\"${INSTALL_DIR}:\${PATH}\"" "${BASH_ENV}"
}

@test "an install path already on PATH is not exported again" {
    export FAKE_ARCH=x86_64
    export PATH="${INSTALL_DIR}:${PATH}"

    run bash "${SCRIPTS_DIR}/install.sh"

    [ "${status}" -eq 0 ]
    [ ! -s "${BASH_ENV}" ]
}
