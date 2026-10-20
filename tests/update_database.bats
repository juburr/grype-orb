#!/usr/bin/env bats
# Tests for src/scripts/update_database.sh. A stub grype records the
# GRYPE_DB_CACHE_DIR it runs with and its arguments.

setup() {
    load test_helper
    common_setup

    GRYPE_LOG="${BATS_TEST_TMPDIR}/grype.log"
    stub grype "printf '%s|%s\n' \"\${GRYPE_DB_CACHE_DIR:-}\" \"\$*\" > '${GRYPE_LOG}'"
    export HOME="${BATS_TEST_TMPDIR}/home dir"
    export PARAM_DATABASE_DIR
    PARAM_DATABASE_DIR="$(command_default update_database database_dir)"
}

# exported_dir: prints GRYPE_DB_CACHE_DIR as a later step sees it, by
# sourcing BASH_ENV in a clean shell.
exported_dir() {
    # shellcheck disable=SC2016 # expanded by the clean shell, not here
    env -i bash -c 'source "$1"; printf "%s" "${GRYPE_DB_CACHE_DIR}"' _ "${BASH_ENV}"
}

@test "database_dir defaults to ~/.cache/grype/db" {
    # shellcheck disable=SC2088 # the default is a literal ~, expanded by the script
    [ "${PARAM_DATABASE_DIR}" = "~/.cache/grype/db" ]
}

@test "a leading ~ is expanded, and later steps see the same directory" {
    run bash "${SCRIPTS_DIR}/update_database.sh"

    [ "${status}" -eq 0 ]
    [ "$(cat "${GRYPE_LOG}")" = "${HOME}/.cache/grype/db|db update -vv" ]
    [ "$(exported_dir)" = "${HOME}/.cache/grype/db" ]
}

@test "an absolute database_dir is used as given" {
    export PARAM_DATABASE_DIR="/opt/grype db"

    run bash "${SCRIPTS_DIR}/update_database.sh"

    [ "${status}" -eq 0 ]
    [ "$(cat "${GRYPE_LOG}")" = "/opt/grype db|db update -vv" ]
    [ "$(exported_dir)" = "/opt/grype db" ]
}

@test "a relative database_dir is resolved against the working directory" {
    export PARAM_DATABASE_DIR="cache/db"

    run bash "${SCRIPTS_DIR}/update_database.sh"

    [ "${status}" -eq 0 ]
    [ "$(exported_dir)" = "${PWD}/cache/db" ]
}

@test "an empty database_dir fails before updating" {
    export PARAM_DATABASE_DIR=""

    run bash "${SCRIPTS_DIR}/update_database.sh"

    [ "${status}" -ne 0 ]
    [[ "${output}" == *"ERROR: database_dir is required"* ]]
    [ ! -e "${GRYPE_LOG}" ]
}

# --- database cache keys ------------------------------------------------------

KEYS="${BATS_TEST_TMPDIR}/db-cache"

# key_files PART: runs the key script for PART (location or database), which
# writes ${KEYS}-<name>.
key_files() {
    export ORB_DB_CACHE_KEY_PART="$1"
    export ORB_DB_CACHE_KEY_PREFIX="${BATS_TEST_TMPDIR}/db-cache"
    run bash "${SCRIPTS_DIR}/database_cache_key.sh"
}

# grype_stub VERSION_OUTPUT STATUS_OUTPUT [CONFIG_OUTPUT]: a grype that prints
# these for `grype version`, `grype db status` and `grype config --load`.
grype_stub() {
    printf '%s\n' "$1" > "${BATS_TEST_TMPDIR}/grype-version.out"
    printf '%s\n' "$2" > "${BATS_TEST_TMPDIR}/grype-status.out"
    printf '%s\n' "${3:-}" > "${BATS_TEST_TMPDIR}/grype-config.out"
    stub grype "case \"\$*\" in
        version) cat '${BATS_TEST_TMPDIR}/grype-version.out' ;;
        'db status') cat '${BATS_TEST_TMPDIR}/grype-status.out' ;;
        'config --load') cat '${BATS_TEST_TMPDIR}/grype-config.out' ;;
        *) exit 1 ;;
    esac"
}

STATUS_V6='Path:      /home/circleci/.cache/grype/db/6/vulnerability.db
Schema:    v6.1.10
Built:     2026-10-19T06:39:15Z
From:      https://grype.anchore.io/databases/v6/vulnerability-db_v6.1.10_2026-10-19T00:32:50Z_1792391955.tar.zst?checksum=sha256%3A13a1
Status:    valid'
# grype config --load prints strings as quoted YAML.
CONFIG_V6=$'db:\n  cache-dir: \'/home/circleci/.cache/grype/db\'\n  update-url: \'https://grype.anchore.io/databases\'\n  auto-update: true'

@test "the location key names HOME, database_dir, the schema and the feed" {
    grype_stub $'Application:         grype\nSupported DB Schema: 6' "${STATUS_V6}" "${CONFIG_V6}"

    key_files location

    [ "${status}" -eq 0 ]
    # database_dir stays as given, ~ and all: the cache steps don't expand
    # variables, so the raw value names the directory they save. It is not
    # relative, so the working directory is left out.
    [ "$(cat "${KEYS}-location")" = "$(printf '%s\n%s\n\n%s\n%s' "${HOME}" "${PARAM_DATABASE_DIR}" 6 https://grype.anchore.io/databases)" ]
    [ -z "$(find "${BATS_TEST_TMPDIR}" -maxdepth 1 -name 'db-cache-*.*')" ]
}

@test "a relative database_dir adds the working directory to the location key" {
    grype_stub 'Supported DB Schema: 6' "${STATUS_V6}" "${CONFIG_V6}"
    export PARAM_DATABASE_DIR="cache/db"

    key_files location

    [ "${status}" -eq 0 ]
    [ "$(sed -n 3p "${KEYS}-location")" = "${PWD}" ]
}

@test "the location key changes with HOME, database_dir, the schema and the feed" {
    grype_stub 'Supported DB Schema: 6' "${STATUS_V6}" "${CONFIG_V6}"
    default_dir="${PARAM_DATABASE_DIR}"
    key_files location
    first=$(cat "${KEYS}-location")

    export PARAM_DATABASE_DIR="${default_dir}-other"
    key_files location
    [ "$(cat "${KEYS}-location")" != "${first}" ]

    export PARAM_DATABASE_DIR="${default_dir}" HOME="${BATS_TEST_TMPDIR}/other home"
    key_files location
    [ "$(cat "${KEYS}-location")" != "${first}" ]

    export HOME="${BATS_TEST_TMPDIR}/home dir"
    grype_stub 'Supported DB Schema: 5' "${STATUS_V6}" "${CONFIG_V6}"
    key_files location
    [ "$(cat "${KEYS}-location")" != "${first}" ]

    grype_stub 'Supported DB Schema: 6' "${STATUS_V6}" "${CONFIG_V6/grype.anchore.io/mirror.example}"
    key_files location
    [ "$(cat "${KEYS}-location")" != "${first}" ]

    grype_stub 'Supported DB Schema: 6' "${STATUS_V6}" "${CONFIG_V6}"
    key_files location
    [ "$(cat "${KEYS}-location")" = "${first}" ]
}

@test "the feed is the same whether grype config --load quotes it or not" {
    grype_stub 'Supported DB Schema: 6' "${STATUS_V6}" "${CONFIG_V6}"
    key_files location
    [ "${status}" -eq 0 ]
    [ "$(sed -n 5p "${KEYS}-location")" = "https://grype.anchore.io/databases" ]

    grype_stub 'Supported DB Schema: 6' "${STATUS_V6}" $'db:\n  update-url: "https://grype.anchore.io/databases"'
    key_files location
    [ "$(sed -n 5p "${KEYS}-location")" = "https://grype.anchore.io/databases" ]

    grype_stub 'Supported DB Schema: 6' "${STATUS_V6}" $'db:\n  update-url: https://grype.anchore.io/databases'
    key_files location
    [ "$(sed -n 5p "${KEYS}-location")" = "https://grype.anchore.io/databases" ]
}

@test "without grype config --load, the feed comes from GRYPE_DB_UPDATE_URL" {
    grype_stub 'Supported DB Schema: 5' "${STATUS_V6}" ""
    export GRYPE_DB_UPDATE_URL="https://mirror.example/listing.json"

    key_files location

    [ "${status}" -eq 0 ]
    [ "$(sed -n 5p "${KEYS}-location")" = "https://mirror.example/listing.json" ]
}

@test "credentials in the feed stay out of the location key, and the log shows no query" {
    grype_stub 'Supported DB Schema: 6' "${STATUS_V6}" $'db:\n  update-url: \'https://user:s3cret@mirror.example/databases?token=t0ken\''

    key_files location

    [ "${status}" -eq 0 ]
    [ "$(sed -n 5p "${KEYS}-location")" = "https://mirror.example/databases?token=t0ken" ]
    [[ "${output}" == *"feed https://mirror.example/databases)."* ]]
    [[ "${output}" != *s3cret* && "${output}" != *t0ken* ]]
}

@test "the day keys name today and the two days before in UTC" {
    grype_stub 'Supported DB Schema: 6' "${STATUS_V6}" "${CONFIG_V6}"
    now=$(date -u +%s)

    key_files location

    [ "${status}" -eq 0 ]
    # Allow for the clock passing midnight between the script and this check.
    for day in 0 1 2; do
        got=$(cat "${KEYS}-day${day}")
        [ "${got}" = "$(date -u -d "@$((now - day * 86400))" +%Y-%m-%d)" ] \
            || [ "${got}" = "$(date -u -d "@$((now + 60 - day * 86400))" +%Y-%m-%d)" ]
    done
}

@test "the database key names the database, not its path or status, and its build date" {
    grype_stub 'Supported DB Schema: 6' "${STATUS_V6}" "${CONFIG_V6}"

    key_files database

    [ "${status}" -eq 0 ]
    [ "$(sed -n 1p "${KEYS}-database")" = "Schema: v6.1.10" ]
    [ "$(sed -n 2p "${KEYS}-database")" = "Built: 2026-10-19T06:39:15Z" ]
    grep -q '^From: https://grype.anchore.io/' "${KEYS}-database"
    # A bare "! grep" line can't fail a bats test, so test the count.
    [ "$(grep -cE '^(Path|Status):' "${KEYS}-database")" -eq 0 ]
    [ "$(cat "${KEYS}-built")" = "2026-10-19" ]
}

@test "the database key keeps only the From URL's checksum, without credentials or signatures" {
    signed() {
        printf '%s\n' "${STATUS_V6}" | sed "s|^From: .*|From:      https://user:s3cret@mirror.example/v6/db.tar.zst?X-Amz-Signature=$1\\&checksum=sha256%3A13a1\\&X-Amz-Expires=60|"
    }
    grype_stub 'Supported DB Schema: 6' "$(signed aaa)" "${CONFIG_V6}"
    key_files database
    [ "${status}" -eq 0 ]
    [ "$(sed -n 3p "${KEYS}-database")" = "From: https://mirror.example/v6/db.tar.zst?checksum=sha256%3A13a1" ]
    [[ "${output}" != *s3cret* && "${output}" != *Signature* ]]
    first=$(cat "${KEYS}-database")

    # Another job downloading the same database through a new signed URL.
    grype_stub 'Supported DB Schema: 6' "$(signed bbb)" "${CONFIG_V6}"
    key_files database
    [ "$(cat "${KEYS}-database")" = "${first}" ]

    grype_stub 'Supported DB Schema: 6' "$(printf '%s\n' "${STATUS_V6}" | sed 's|?checksum=.*||')" "${CONFIG_V6}"
    key_files database
    [ "$(sed -n 3p "${KEYS}-database")" = "From: https://grype.anchore.io/databases/v6/vulnerability-db_v6.1.10_2026-10-19T00:32:50Z_1792391955.tar.zst" ]
}

@test "a build date key matches the day key for that date byte for byte" {
    grype_stub 'Supported DB Schema: 6' \
        "$(printf '%s\n' "${STATUS_V6}" | sed "s/2026-10-19T06:39:15Z/$(date -u +%Y-%m-%d)T06:39:15Z/")" "${CONFIG_V6}"

    key_files location
    key_files database

    cmp "${KEYS}-built" "${KEYS}-day0"
}

@test "a newer database gets a new key, the same database the same key" {
    grype_stub 'Supported DB Schema: 6' "${STATUS_V6}" "${CONFIG_V6}"
    key_files database
    first=$(cat "${KEYS}-database")

    # Checked again later, from another path, with another status.
    grype_stub 'Supported DB Schema: 6' "$(printf '%s\n' "${STATUS_V6}" | sed -e 's#/home/circleci#/root#' -e 's/valid/valid (checked)/')" "${CONFIG_V6}"
    key_files database
    [ "$(cat "${KEYS}-database")" = "${first}" ]

    grype_stub 'Supported DB Schema: 6' "$(printf '%s\n' "${STATUS_V6}" | sed 's/2026-10-19T06:39:15Z/2026-10-20T06:41:02Z/')" "${CONFIG_V6}"
    key_files database
    [ "$(cat "${KEYS}-database")" != "${first}" ]
    [ "$(cat "${KEYS}-built")" = "2026-10-20" ]
}

@test "the database key reads a schema 5 status, with a Checksum line" {
    grype_stub 'Supported DB Schema: 5' $'Location:  /root/.cache/grype/db/5\nBuilt:     2025-01-02 01:23:45 +0000 UTC\nSchema:    5\nChecksum:  sha256:abc\nStatus:    valid'

    key_files database

    [ "${status}" -eq 0 ]
    [ "$(cat "${KEYS}-database")" = "$(printf '%s\n%s\n%s' 'Built: 2025-01-02 01:23:45 +0000 UTC' 'Schema: 5' 'Checksum: sha256:abc')" ]
    [ "$(cat "${KEYS}-built")" = "2025-01-02" ]
}

@test "without a database status, the database keys fall back to today's date" {
    grype_stub '' ''

    key_files database

    [ "${status}" -eq 0 ]
    [ "$(cat "${KEYS}-database")" = "date $(date -u +%Y-%m-%d)" ]
    [ "$(cat "${KEYS}-built")" = "$(date -u +%Y-%m-%d)" ]
    [[ "${output}" == *"WARN: grype db status named no database"* ]]
}

@test "a cache key file is not written through a symlink" {
    grype_stub 'Supported DB Schema: 6' "${STATUS_V6}" "${CONFIG_V6}"
    target="${BATS_TEST_TMPDIR}/target"
    printf 'keep\n' > "${target}"
    ln -s "${target}" "${KEYS}-database"

    key_files database

    [ "${status}" -eq 0 ]
    [ "$(cat "${target}")" = "keep" ]
    [ ! -L "${KEYS}-database" ]
}

@test "a directory at a cache key file's name fails the step" {
    grype_stub 'Supported DB Schema: 6' "${STATUS_V6}" "${CONFIG_V6}"
    mkdir "${KEYS}-location"

    key_files location

    [ "${status}" -ne 0 ]
    [[ "${output}" == *"ERROR: Could not write ${KEYS}-location."* ]]
}

@test "an unknown key part fails the step" {
    key_files both

    [ "${status}" -ne 0 ]
    [[ "${output}" == *"ERROR: ORB_DB_CACHE_KEY_PART must be location or database"* ]]
}

@test "the newest database built today, then before, is restored, and saved under its own key" {
    yml="${COMMANDS_DIR}/update_database.yml"
    location='{{ checksum "/tmp/grype-orb-db-cache-location" }}'
    sum() { printf '{{ checksum "/tmp/grype-orb-db-cache-%s" }}' "$1"; }

    restore=$(awk '/restore_cache:/ { on = 1; next } on && !/^ +(keys:|- grype-vuln-db)/ { exit } on && /^ +- / { sub(/^ +- /, ""); print }' "${yml}")
    [ "${restore}" = "$(printf '%s\n%s\n%s\n%s' \
        "grype-vuln-db-v2-${location}-$(sum day0)-" \
        "grype-vuln-db-v2-${location}-$(sum day1)-" \
        "grype-vuln-db-v2-${location}-$(sum day2)-" \
        "grype-vuln-db-v2-${location}-")" ]

    save=$(awk '/save_cache:/ { on = 1 } on && /key:/ { sub(/^ +key: /, ""); print; exit }' "${yml}")
    [ "${save}" = "grype-vuln-db-v2-${location}-$(sum built)-$(sum database)" ]

    # Both key steps write the files the keys name.
    [ "$(grep -c 'ORB_DB_CACHE_KEY_PREFIX: /tmp/grype-orb-db-cache$' "${yml}")" -eq 2 ]
}
