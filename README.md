<div align="center">
  <img align="center" width="320" src="assets/logos/grype-orb-logo.png" alt="Grype Orb">
  <h1>CircleCI Grype Orb</h1>
  <i>An orb for simplifying Grype installation and performing vulnerability scans within CircleCI.</i><br /><br />
</div>

[![CircleCI Build Status](https://circleci.com/gh/juburr/grype-orb.svg?style=shield "CircleCI Build Status")](https://circleci.com/gh/juburr/grype-orb) [![CircleCI Orb Version](https://badges.circleci.com/orbs/juburr/grype-orb.svg)](https://circleci.com/developer/orbs/orb/juburr/grype-orb) [![GitHub License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](https://raw.githubusercontent.com/juburr/grype-orb/master/LICENSE) [![CircleCI Community](https://img.shields.io/badge/community-CircleCI%20Discuss-343434.svg)](https://discuss.circleci.com/c/ecosystem/orbs)

This is an unofficial Grype orb used for installing Grype in your CircleCI pipeline and performing vulnerability scans of your container images. Contributions are welcome!

## Features
### **Secure By Design**
- **Least Privilege**: Installs to a user-owned directory by default, with no `sudo` usage anywhere in this orb.
- **Integrity**: Checksum validation of all downloaded binaries using SHA-512.
- **Provenance**: Installs directly from Grype's official [releases page](https://github.com/anchore/grype/releases/) on GitHub. No third-party websites, domains, or proxies are used.
- **Confidentiality**: All secrets and environment variables are handled in accordance with CircleCI's [security recommendations](https://circleci.com/docs/security-recommendations/) and [best practices](https://circleci.com/docs/orbs-best-practices/).
- **Privacy**: No usage data of any kind is collected or shipped back to the orb developer.
