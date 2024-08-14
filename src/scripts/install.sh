#!/bin/bash

set -e

# Read in orb parameters
INSTALL_PATH=$(circleci env subst "${PARAM_INSTALL_PATH}")
VERIFY_CHECKSUMS="${PARAM_VERIFY_CHECKSUMS}"
VERSION=$(circleci env subst "${PARAM_VERSION}")

# Print command arguments for debugging purposes.
echo "Running Grype installer..."
echo "  INSTALL_PATH: ${INSTALL_PATH}"
echo "  VERIFY_CHECKSUMS: ${VERIFY_CHECKSUMS}"
echo "  VERSION: ${VERSION}"

# Lookup table of sha512 checksums for different versions of grype
declare -A sha512sums
sha512sums=(
    ["0.79.6"]="dc22e1cdefc1678e7006081689d05dc419ba5c9f4a4d13a8aa8e8c91e7015867a7d98046bb598231868200096bd9eca4a326a79a8c58af82c7943a2f025f17fa"
    ["0.79.5"]="a1dbf9266c619b345f79523543456f5b0e4146e75d67d2561a1126deaebe7489b034992d856491d0bcdb060c402ff0fd8585a136935eca917b16c2aeb2a73170"
    ["0.79.4"]="5c79b6b41d8dbacdf475c9912b7fb6da735a319d8f1d111dec983458e9731a44ab8af2d2b576941659e520ada69e4858e3a72047721bb32ecbc75c893658d3e1"
    ["0.79.3"]="6c0cd6f3494dc81bc20f4e7067baa4f6aceb53c9f74561e72fdbcaf8af8a747f6572207471f12700e4e8df7e05ea7cfac30fd3564aa14fdd06aaee24b5383f1e"
    ["0.79.2"]="2a46d292eb1e80b4888c61089aba01662c16c1222a29c7ddc6662902a1bbbb7107b199132c923aa4316a728a416fa019d9e930f795ae60b92187d3e92ee6759b"
    ["0.79.1"]="f82cf47466e102cbcd7371438b7e35d03a84e88101b194fff2f652bfcf3eb84a274897227dad69ebe0c5abe3b3a7a800e8ba01169b31fcc30bef68e740ba7858"
    ["0.79.0"]="45382138787eca989f35c3099f9631d6dc30d40617927406f02f37a114a71441cceff6fce3bc44e15c52a439fef5f3f8854d7f51262d282d7e00686631477f05"
    ["0.78.0"]="10bb8c70961d9e66f93f8791d460856c78a8bd46fa538f9094b03592a087e1b4f5b7b2c8738753a9dc3ba81e8cd569ee6b7d54717b7fae8f4111870826772afa"
    ["0.77.4"]="5744bf5452f2c79e9434bd3840ea65c6364e737623d5ccf1a420a8b9253e697fbdbda86565c96770a4fb9089a298128d4811aa7f577804df2ab8aa32bd4e42f4"
    ["0.77.3"]="841739b70ddfd90ac397e060166288da9c92a0eb4ca71d651f3bd72aad51611fd12200aba7b427e200ab661cfbea8d4b302c4e7f65e4f6b48d09eea25a43808b"
    ["0.77.2"]="cc24910c319f23072b0c79023953f40949e14cab04df279c2a4a018ded677239904f251bc910935a152e2b73a6cf77740466e7ae63eb54837f155a4517f6a594"
    ["0.77.1"]="dd5f1a397fa5bd2d6e77dd11463dce34d5ff34fbd6fca4f30588b115b2415692684e7772bbe775d1224b71b57907f4a6d473233d4109d36518e957a241a48c2b"
    ["0.77.0"]="bbc5b1d96fa8ef3840c302d6a4a6ca6c9caae57f6e635c06ee90f33e93363498535637b89d01e2dfe1940e78239f8d660412a1c8d2554344bae6b1fda4659478"
    ["0.76.0"]="41dac3b56d3fd92ed65f8704e188bb84473c9d2fa8de131b095fc087d2eee632cce44226a28026be906f94578bfbc066d89753284d740e9bb1024a4ed316d92d"
    ["0.75.0"]="681ef00777b2e2b4479d87f39c88525f4925841d025f73f5dff10b3c464e5748b73ece5d339ecff53f3e11456fa92a972cd6c0e19440628ab5b4efca0b283d6d"
    ["0.74.7"]="26054195c30327510857857b6f9b6ed5c9a02b8dcb3b7003f6e5e7f5a9edbe1330efaaa8d7f6c860562b637f774b3bcb6c4626b163567b375c135a88df3d9000"
    ["0.74.6"]="043aaae6851a21eadbff1470af9b05b24048a86ac12e13ef66d2bdd5899a1ee691d0c4423a385799fb9995cba10b5ab516aaf3ea9cfba8c300a2c8f2ff72d57e"
    ["0.74.5"]="fbc0c3bbdec78a5a6abaac5fc1463b97e9f8f00e63c918f66e45cf03ab5dea4e42194646c4002c8202e066f4e57f0ea787716b6b050e887257002f07f9b69ad6"
    ["0.74.4"]="feb7bd54648b2431a2ec5ce0401705151c5e31b486c98550cdd7279369f4022c4be085d92daa0fe92f06ae5995bd84411df2e0617b95bf8666fa1444cce04b03"
    ["0.74.3"]="2626b58d25c912ab11457793abf9ea4dbd8ea38c902defbb5905d45bf5fd8643622fc0d221f92d2aece7956a2f800628d1d8c47c115313add81deb31fb03be32"
    ["0.74.2"]="2ea984f7088341d385c72dbee95af8f540e3daceddecd10d3cd92cb551a080d132ee9c34032b9a4c8f7ed675f82cb90d0c0cbfa6c7ca4c5fc22aacdac3b145f6"
    ["0.74.1"]="1922e23880418fcb3b3552f0e46b44fd59020f697649c7684376832ad910195de5e0633c219bf9f32418e9840597b176d0e16b67b4ba2734a1f68e2eaeab4f48"
    ["0.74.0"]="2307166c8ed90be1a9ee3120f15b9c3a262fda7cf9954b26565979bfe3b1f392a10bd3bb3b51e294078519f1ffcea26a672655450ca0f288d35db4389e05ad10"
    # TODO: Add checksums for old versions...
)

# Verfies that the SHA-512 checksum of a file matches what was in the lookup table
verify_checksum() {
    local file=$1
    local expected_checksum=$2

    actual_checksum=$(sha512sum "${file}" | awk '{ print $1 }')

    echo "Verifying checksum for ${file}..."
    echo "  Actual: ${actual_checksum}"
    echo "  Expected: ${expected_checksum}"

    if [[ "${actual_checksum}" != "${expected_checksum}" ]]; then
        echo "ERROR: Checksum verification failed!"
        exit 1
    fi

    echo "Checksum verification passed!"
}

# Check if the grype tar file was in the CircleCI cache.
# Cache restoration is handled in install.yml
if [[ -f grype.tar.gz ]]; then
    tar -xvzf grype.tar.gz grype
fi

# If there was no cache hit, go ahead and re-download the binary.
# Tar it up to save on cache space used.
if [[ ! -f grype ]]; then
    wget "https://github.com/anchore/grype/releases/download/v${VERSION}/grype_${VERSION}_linux_amd64.tar.gz" -O grype.tar.gz
    tar -xvzf grype.tar.gz grype
fi

# A grype binary should exist at this point, regardless of whether it was obtained
# through cache or re-downloaded. First verify its integrity.
if [[ "${VERIFY_CHECKSUMS}" != "false" ]]; then
    EXPECTED_CHECKSUM=${sha512sums[${VERSION}]}
    if [[ -n "${EXPECTED_CHECKSUM}" ]]; then
        # If the version is in the table, verify the checksum
        verify_checksum "grype" "${EXPECTED_CHECKSUM}"
    else
        # If the version is not in the table, this means that a new version of Cosign
        # was released but this orb hasn't been updated yet to include its checksum in
        # the lookup table. Allow developers to configure if they want this to result in
        # a hard error, via "strict mode" (recommended), or to allow execution for versions
        # not directly specified in the above lookup table.
        if [[ "${VERIFY_CHECKSUMS}" == "known_versions" ]]; then
            echo "WARN: No checksum available for version ${VERSION}, but strict mode is not enabled."
            echo "WARN: Either upgrade this orb, submit a PR with the new checksum."
            echo "WARN: Skipping checksum verification..."
        else
            echo "ERROR: No checksum available for version ${VERSION} and strict mode is enabled."
            echo "ERROR: Either upgrade this orb, submit a PR with the new checksum, or set 'verify_checksums' to 'known_versions'."
            exit 1
        fi
    fi
else
    echo "WARN: Checksum validation is disabled. This is not recommended. Skipping..."
fi

# After verifying integrity, install it by moving it to
# an appropriate bin directory and marking it as executable.
mv grype "${INSTALL_PATH}/grype"
chmod +x "${INSTALL_PATH}/grype"
