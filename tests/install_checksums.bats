#!/usr/bin/env bats
# Checksum policy tests for src/scripts/install.sh. They run offline: stub
# wget and curl record each download and serve a fake Grype tarball whose
# binary matches no checksum in the lookup table.

setup() {
    load test_helper
    common_setup

    INSTALL_DIR="${BATS_TEST_TMPDIR}/bin"
    DOWNLOAD_LOG="${BATS_TEST_TMPDIR}/downloads.log"
    FAKE_TARBALL="${BATS_TEST_TMPDIR}/fake-grype.tar.gz"
    mkdir -p "${INSTALL_DIR}" "${BATS_TEST_TMPDIR}/release"
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

    export PARAM_INSTALL_PATH="${INSTALL_DIR}"
    UNLISTED_VERSION="0.0.0-unlisted"
}

@test "install defaults verify_checksums to strict" {
    [ "$(command_default install verify_checksums)" = "strict" ]
}

@test "an unlisted version fails by default without downloading or installing" {
    export PARAM_VERIFY_CHECKSUMS="$(command_default install verify_checksums)"
    export PARAM_VERSION="${UNLISTED_VERSION}"

    run bash "${SCRIPTS_DIR}/install.sh"

    [ "${status}" -ne 0 ]
    [[ "${output}" == *"No checksum available for version ${UNLISTED_VERSION} and strict mode is enabled."* ]]
    [ ! -e "${DOWNLOAD_LOG}" ]
    [ ! -e "${INSTALL_DIR}/grype" ]
}

@test "an unlisted version fails when verify_checksums is unset" {
    unset PARAM_VERIFY_CHECKSUMS
    export PARAM_VERSION="${UNLISTED_VERSION}"

    run bash "${SCRIPTS_DIR}/install.sh"

    [ "${status}" -ne 0 ]
    [[ "${output}" == *"No checksum available for version ${UNLISTED_VERSION}"* ]]
    [ ! -e "${DOWNLOAD_LOG}" ]
    [ ! -e "${INSTALL_DIR}/grype" ]
}

@test "known_versions still installs an unlisted version, with a warning" {
    export PARAM_VERIFY_CHECKSUMS=known_versions
    export PARAM_VERSION="${UNLISTED_VERSION}"

    run bash "${SCRIPTS_DIR}/install.sh"

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"WARN: No checksum available for version ${UNLISTED_VERSION}"* ]]
    grep -q "/v${UNLISTED_VERSION}/" "${DOWNLOAD_LOG}"
    [ -x "${INSTALL_DIR}/grype" ]
}

@test "false still installs an unlisted version without verification" {
    export PARAM_VERIFY_CHECKSUMS=false
    export PARAM_VERSION="${UNLISTED_VERSION}"

    run bash "${SCRIPTS_DIR}/install.sh"

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"WARN: Checksum validation is disabled."* ]]
    [ -x "${INSTALL_DIR}/grype" ]
}

@test "strict rejects a listed version whose binary does not match its checksum" {
    export PARAM_VERIFY_CHECKSUMS=strict
    export PARAM_VERSION="$(command_default install version)"

    run bash "${SCRIPTS_DIR}/install.sh"

    [ "${status}" -ne 0 ]
    [[ "${output}" == *"ERROR: Checksum verification failed!"* ]]
    [ ! -e "${INSTALL_DIR}/grype" ]
}
