<div align="center">
  <img align="center" width="320" src="assets/logos/grype-orb-logo.png" alt="Grype Orb">
  <h1>CircleCI Grype Orb</h1>
  <i>An orb for simplifying Grype installation and performing vulnerability scans within CircleCI.</i><br /><br />
</div>

[![CircleCI Build Status](https://circleci.com/gh/juburr/grype-orb.svg?style=shield "CircleCI Build Status")](https://circleci.com/gh/juburr/grype-orb) [![CircleCI Orb Version](https://badges.circleci.com/orbs/juburr/grype-orb.svg)](https://circleci.com/developer/orbs/orb/juburr/grype-orb) [![GitHub License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](https://raw.githubusercontent.com/juburr/grype-orb/master/LICENSE) [![CircleCI Community](https://img.shields.io/badge/community-CircleCI%20Discuss-343434.svg)](https://discuss.circleci.com/c/ecosystem/orbs)

This is an unofficial Grype orb used for installing Grype in your CircleCI
pipeline and performing vulnerability scans of container images, SBOMs,
directories, registries, and other Grype-supported sources. Contributions are
welcome!

## Features
### **Secure By Design**
- **Least Privilege**: Installs to a user-owned directory by default, with no `sudo` usage anywhere in this orb.
- **Integrity**: Checksum validation of all downloaded binaries using SHA-512, failing closed by default when a version's checksum is unknown (see [Checksum verification](#checksum-verification)).
- **Provenance**: Installs directly from Grype's official [releases page](https://github.com/anchore/grype/releases/) on GitHub. No third-party websites, domains, or proxies are used.
- **Confidentiality**: All secrets and environment variables are handled in accordance with CircleCI's [security recommendations](https://circleci.com/docs/security-recommendations/) and [best practices](https://circleci.com/docs/orbs-best-practices/).
- **Privacy**: No usage data of any kind is collected or shipped back to the orb developer.

### **Platforms**
- Linux `amd64` (`x86_64`) and `arm64` (`aarch64`), on Docker or machine executors, including CircleCI's Arm resource classes. `install` detects the architecture with `uname -m`, downloads the matching Grype release, and verifies it against a per-architecture checksum table. Any other platform is a hard error.
- The binary cache key includes the architecture, so amd64 and arm64 jobs never share a cached download.
- If `install_path` is not on `PATH` (as can happen on machine executors), `install` creates it and adds it to `PATH` for the job's later steps.

Info for security teams:
- Required external access to allow, if running a locked down, self-hosted CircleCI pipeline on-prem:
  - `github.com`: For download and installation of the Grype tool.
  - `grype.anchore.io`: For vulnerability database updates on Grype 0.88.0 and later, including the default version.
  - `toolbox-data.anchore.io`: For vulnerability database updates on Grype 0.87.0 and earlier.

## Example Usage

```yaml
version: 2.1

orbs:
  grype: juburr/grype-orb@latest

parameters:
  cimg_base_version:
    type: string
    default: "current-22.04"
  grype_version:
    type: string
    default: "0.119.0"

jobs:
  scan_container:
    docker:
      - image: cimg/base:<< pipeline.parameters.cimg_base_version >>
    parameters:
      image:
        type: string
        description: "container image to scan"
    steps:
      - checkout
      - grype/install:
          caching: true
          verify_checksums: strict
          version: << pipeline.parameters.grype_version >>
      - grype/log_version
      - grype/update_database
      - grype/scan_image:
          fail_on: critical
          image: gcr.io/distroless/base:latest
          output_file: gcr.distroless.base.grype.sarif
          output_format: sarif
      - run:
          name: Log Scan Results
          command: cat gcr.distroless.base.grype.sarif
```

## Checksum verification

`install` verifies the SHA-512 checksum of the Grype binary against a lookup
table maintained in this orb. The `verify_checksums` parameter controls what
happens when the requested `version` is missing from that table:

| Value | Listed version | Unlisted version |
| --- | --- | --- |
| `strict` (default) | Verified | Fails before downloading anything |
| `known_versions` | Verified | Installed unverified, with a warning |
| `"false"` | Not verified | Not verified (not recommended) |

If you pin a Grype release newer than this orb knows about, upgrade the orb or
contribute the checksum; set `verify_checksums: known_versions` only as a
temporary opt-out.

## Scan sources and policy

`scan_image` retains its original `image` parameter for backward
compatibility. New configurations can use the more accurately named `source`
parameter with any source syntax supported by Grype, including `cpes:` files
and `zarf:` package archives. Set exactly one of `source` or `image`.

```yaml
- grype/scan_image:
    source: sbom:./forge.cdx.json
    config: .grype.yaml
    only_fixed: true
    fail_on: high
    output_format: sarif
    output_file: forge.grype.sarif

- grype/scan_image:
    source: dir:.
    output_format: json
    output_file: repository.grype.json
```

The `config` parameter is passed to Grype as `--config`, allowing a committed
policy file to carry ignore rules. Repositories can pair that file with their
own CI validation for required rationale and expiry metadata. `only_fixed`
passes `--only-fixed`. The existing `fail_on` parameter remains optional;
leave it empty to report findings without gating.

## Multiple report formats

`output_formats` renders several reports from a single scan, so every report
comes from the same cataloging pass and the same vulnerability database
snapshot. Separate scans could each pick up a database update, and they repeat
the image pull and cataloging work. List comma-separated `format=path` pairs;
each becomes its own `-o format=path` flag:

```yaml
- grype/scan_image:
    source: sbom:./forge.cdx.json
    output_formats: json=forge.grype.json,table=forge.grype.txt
```

`output_formats` requires Grype 0.104.1 or later; the default version
qualifies. Older releases either lack multiple outputs (before 0.64.0) or can
write registry credentials into JSON written straight to a file (0.68.0 through
0.104.0, [GHSA-6gxw-85q2-q646](https://github.com/anchore/grype/security/advisories/GHSA-6gxw-85q2-q646)),
so the step fails before scanning on them. The single-report style is
unaffected on any version, because it redirects Grype's stdout to the file.

`output_formats` cannot be combined with `output_format` or `output_file`.
Without it, the single-report behavior is unchanged: `output_format` defaults
to `sarif` and `output_file` to `grype-scan-results.sarif`. When `fail_on`
trips, every report is still written before the step fails.
