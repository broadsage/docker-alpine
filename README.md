# docker-alpine

The official Docker image for [Alpine Linux](https://alpinelinux.org).
The image is only 5MB and has access to a package repository that is much more featureful than other BusyBox based images.

## Why

Docker images today are big.
Usually much larger than they need to be.
There are a lot of ways to make them smaller, but the Docker populace still jumps to the `ubuntu` base image for most projects.
The size savings over `ubuntu` and other bases are huge:

```text
REPOSITORY  TAG     IMAGE ID      CREATED      SIZE
alpine      latest  961769676411  4 weeks ago  5.58MB
ubuntu      latest  2ca708c1c9cc  2 days ago   64.2MB
debian      latest  c2c03a296d23  9 days ago   114MB
centos      latest  67fa590cfc1c  4 weeks ago  202MB
```

There are images such as `progrium/busybox` which get us close to a minimal container and package system, but these particular BusyBox builds piggyback on the OpenWRT package index, which is often lacking and not tailored towards generic everyday applications.
Alpine Linux has a much more featureful and up to date [Package Index](https://pkgs.alpinelinux.org):

```bash
$ docker run progrium/busybox opkg-install nodejs
Unknown package 'nodejs'.
Collected errors:
 * opkg_install_cmd: Cannot install package nodejs.

$ docker run alpine apk add --no-cache nodejs
fetch http://dl-cdn.alpinelinux.org/alpine/v3.9/main/x86_64/APKINDEX.tar.gz
fetch http://dl-cdn.alpinelinux.org/alpine/v3.9/community/x86_64/APKINDEX.tar.gz
(1/7) Installing ca-certificates (20190108-r0)
(2/7) Installing c-ares (1.15.0-r0)
(3/7) Installing libgcc (8.3.0-r0)
(4/7) Installing http-parser (2.8.1-r0)
(5/7) Installing libstdc++ (8.3.0-r0)
(6/7) Installing libuv (1.23.2-r0)
(7/7) Installing nodejs (10.14.2-r0)
Executing busybox-1.29.3-r10.trigger
Executing ca-certificates-20190108-r0.trigger
OK: 31 MiB in 21 packages
```

This makes Alpine Linux a great image base for utilities, as well as production applications.
[Read more about Alpine Linux here](https://www.alpinelinux.org/about/) and it will become obvious how its mantra fits in right at home with Docker images.

> **Note**: All of the example outputs above were last generated/updated on May 3rd 2019.

## Usage

Stop doing this:

```dockerfile
FROM ubuntu:22.04
RUN apt-get update -q \
  && DEBIAN_FRONTEND=noninteractive apt-get install -qy mysql-client \
  && apt-get clean \
  && rm -rf /var/lib/apt
ENTRYPOINT ["mysql"]
```

This took 28 seconds to build and yields a 169 MB image.

Start doing this:

```dockerfile
FROM alpine:3.16
RUN apk add --no-cache mysql-client
ENTRYPOINT ["mysql"]
```

Only 4 seconds to build and results in a 41 MB image!

## Quick Start

### Basic Examples

**Run a command:**

```bash
docker run alpine:latest echo "Hello from Alpine!"
```

**Interactive shell:**

```bash
docker run -it alpine:latest /bin/sh
```

**Install packages:**
```bash
docker run alpine:latest apk add --no-cache curl
```

### Simple Dockerfile Example

```dockerfile
FROM alpine:3.22
RUN apk add --no-cache nginx
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

**💡 For production examples, best practices, and advanced usage, see [docs/usage.md](docs/usage.md)**

## Migration from Ubuntu/Debian

**Key Differences:**

| Aspect | Ubuntu/Debian | Alpine |
|--------|---------------|--------|
| Package Manager | `apt-get` | `apk` |
| C Library | glibc | musl libc |
| Default Shell | bash | sh (BusyBox ash) |
| Init System | systemd | OpenRC |

**Common Package Mappings:**

| Ubuntu/Debian | Alpine |
|---------------|--------|
| `build-essential` | `build-base` |
| `python3-pip` | `py3-pip` |
| `ca-certificates` | `ca-certificates` |

**Quick Conversion:**

```dockerfile
# Before (Ubuntu)
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y python3 python3-pip

# After (Alpine)
FROM alpine:3.22
RUN apk add --no-cache python3 py3-pip
```

**📚 For detailed migration guide and troubleshooting, see [docs/usage.md](docs/usage.md) and [docs/caveats.md](docs/caveats.md)**

## Security Features

All images in this repository are built with enterprise-grade security features:

### 🔒 Image Signing & Attestations

Images are signed and attested using registry-specific best practices:

**For GHCR (ghcr.io)**: GitHub native attestations  
**For DockerHub (docker.io)**: Sigstore Cosign signatures

#### Verify GHCR Images (Recommended)

```bash
# Install GitHub CLI (if not already installed)
# macOS: brew install gh
# Linux: See https://github.com/cli/cli#installation

# Verify GHCR image with GitHub Attestations
gh attestation verify oci://ghcr.io/broadsage/alpine:3.22 --owner broadsage

# View detailed provenance and SBOM
gh attestation verify oci://ghcr.io/broadsage/alpine:3.22 \
  --owner broadsage \
  --format json | jq
```

#### Verify DockerHub Images

```bash
# Install cosign (if not already installed)
# macOS: brew install cosign
# Linux: See https://docs.sigstore.dev/cosign/installation/

# Verify DockerHub image signature
cosign verify \
  --certificate-identity-regexp="https://github.com/broadsage/docker-alpine" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  docker.io/broadsage/alpine:3.22
```

### 📋 Software Bill of Materials (SBOM)

Every image includes a Software Bill of Materials (SBOM) in SPDX format, providing complete transparency about all packages and dependencies.

#### View SBOM for GHCR Images

```bash
# GHCR: SBOM is included in GitHub Attestations
gh attestation verify oci://ghcr.io/broadsage/alpine:3.22 \
  --owner broadsage \
  --format json | jq '.verificationResult.statement.predicate'
```

#### View SBOM for DockerHub Images

```bash
# DockerHub: SBOM attached as Cosign attestation
cosign verify-attestation \
  --type spdxjson \
  --certificate-identity-regexp="https://github.com/broadsage/docker-alpine" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  docker.io/broadsage/alpine:3.22 | jq -r '.payload' | base64 -d | jq
```

### 🏗️ Build Provenance (SLSA)

All images include SLSA v1.0 build provenance attestations that provide verifiable information about how the image was built, including:

- Build process details
- Source repository and commit
- Build environment
- Build parameters

#### Verify Build Provenance for GHCR Images

```bash
# GHCR: Built-in GitHub Attestations (recommended)
gh attestation verify oci://ghcr.io/broadsage/alpine:3.22 --owner broadsage

# View detailed provenance in JSON format
gh attestation verify oci://ghcr.io/broadsage/alpine:3.22 \
  --owner broadsage \
  --format json | jq '.verificationResult.statement.predicate'
```

#### Verify Build Provenance for DockerHub Images

```bash
# Verify provenance attestation signature
cosign verify-attestation \
  --type https://slsa.dev/provenance/v1 \
  --certificate-identity-regexp="https://github.com/broadsage/docker-alpine" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  docker.io/broadsage/alpine:3.22

# Extract and view provenance details
cosign verify-attestation \
  --type https://slsa.dev/provenance/v1 \
  --certificate-identity-regexp="https://github.com/broadsage/docker-alpine" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  docker.io/broadsage/alpine:3.22 \
  | jq -r '.payload' | base64 -d | jq '.predicate'

# View specific provenance fields
# Builder information
cosign verify-attestation \
  --type https://slsa.dev/provenance/v1 \
  --certificate-identity-regexp="https://github.com/broadsage/docker-alpine" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  docker.io/broadsage/alpine:3.22 \
  | jq -r '.payload' | base64 -d | jq '.predicate.runDetails.builder'

# Source repository and commit
cosign verify-attestation \
  --type https://slsa.dev/provenance/v1 \
  --certificate-identity-regexp="https://github.com/broadsage/docker-alpine" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  docker.io/broadsage/alpine:3.22 \
  | jq -r '.payload' | base64 -d | jq '.predicate.buildDefinition.resolvedDependencies'

# Complete build workflow information
cosign verify-attestation \
  --type https://slsa.dev/provenance/v1 \
  --certificate-identity-regexp="https://github.com/broadsage/docker-alpine" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  docker.io/broadsage/alpine:3.22 \
  | jq -r '.payload' | base64 -d | jq '.predicate.buildDefinition.externalParameters'
```

#### Verify All Attestations at Once

```bash
# GHCR: Verify all attestations (SBOM + Provenance)
gh attestation verify oci://ghcr.io/broadsage/alpine:3.22 \
  --owner broadsage

# DockerHub: List all attestations
cosign tree docker.io/broadsage/alpine:3.22

# DockerHub: Verify image signature
cosign verify \
  --certificate-identity-regexp="https://github.com/broadsage/docker-alpine" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  docker.io/broadsage/alpine:3.22

# DockerHub: Verify SBOM attestation
cosign verify-attestation \
  --type spdxjson \
  --certificate-identity-regexp="https://github.com/broadsage/docker-alpine" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  docker.io/broadsage/alpine:3.22

# DockerHub: Verify provenance attestation
cosign verify-attestation \
  --type https://slsa.dev/provenance/v1 \
  --certificate-identity-regexp="https://github.com/broadsage/docker-alpine" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  docker.io/broadsage/alpine:3.22
```

#### Verification Troubleshooting

If verification fails, ensure:

1. **Cosign is up to date** (v2.0+):

   ```bash
   cosign version
   # Should be v2.0.0 or later
   ```

2. **Image tag exists**:

   ```bash
   docker pull docker.io/broadsage/alpine:3.22
   ```

3. **Using full image reference**:

   ```bash
   # ✅ Correct
   docker.io/broadsage/alpine:3.22
   
   # ❌ Incorrect (missing registry)
   broadsage/alpine:3.22
   ```

4. **Network connectivity** to Rekor transparency log:

   ```bash
   curl -s https://rekor.sigstore.dev/api/v1/log | jq
   ```

### 🛡️ Vulnerability Scanning (Snyk)

All images are scanned for security vulnerabilities using [Snyk Container](https://snyk.io/product/container-vulnerability-management/) with enterprise-grade vulnerability detection.

**View security findings:**

```bash
# Check GitHub Security tab for vulnerability reports
# https://github.com/broadsage/docker-alpine/security/code-scanning
```

Snyk scanning provides:

- OS package vulnerability detection
- High-severity threshold enforcement
- Automatic security alerts
- Integration with GitHub Security tab
- Prioritized remediation guidance

### ✅ Supply Chain Security

- **Image Signing**:
  - GHCR: GitHub native attestations (zero config, UI integration)
  - DockerHub: Sigstore/Cosign signatures (industry standard)
- **SBOM Generation**: Complete software bill of materials (SPDX format)
- **Build Provenance**: SLSA attestations for build transparency
- **Vulnerability Scanning**: Snyk enterprise scanning with SARIF reporting
- **Pinned Dependencies**: All GitHub Actions pinned to specific SHA256 hashes
- **Hardened Runners**: Network egress auditing with Step Security
- **Automated Updates**: Dependabot keeps dependencies current
- **Security Scanning**: OpenSSF Scorecard and dependency review
- **Clean Build Process**: Reproducible builds from official Alpine minirootfs

### 🏗️ Multi-Architecture Support

Images are built natively for 8 architectures:

- `linux/amd64` (x86_64)
- `linux/arm64` (aarch64)
- `linux/arm/v7` (armv7)
- `linux/arm/v6` (armhf)
- `linux/386` (x86)
- `linux/ppc64le`
- `linux/s390x`
- `linux/riscv64`

Docker automatically pulls the correct architecture for your platform.

### 📦 Available Tags

- `latest` - Latest stable version (currently 3.22.x)
- `edge` - Rolling release from Alpine edge branch
- `3.22`, `3.22.2` - Specific version tags
- `3.21`, `3.21.5` - Previous stable versions
- `3.20`, `3.19` - Older stable versions

All tags point to multi-architecture manifests.

## Documentation

- [About](docs/about.md) - Learn more about Alpine Linux, musl libc, and BusyBox
- [Usage](docs/usage.md) - Package management and examples
- [Build](docs/build.md) - How to build Alpine images locally
- [Caveats](docs/caveats.md) - Important differences from glibc-based systems

## Frequently Asked Questions (FAQ)

### Why Alpine Linux?

**Size**: Alpine images are 5-10x smaller than Ubuntu/Debian equivalents (5MB vs 64MB+)  
**Security**: Smaller attack surface with minimal packages and proactive security updates  
**Performance**: Faster downloads, less disk space, quicker container startup  
**Modern**: Uses musl libc, BusyBox, and modern tooling

### How often are images updated?

Images are automatically rebuilt:

- **Daily**: All stable versions (3.19, 3.20, 3.21, 3.22, edge) at 3 AM UTC
- **On Alpine Release**: When new Alpine versions are published
- **Security Patches**: Incorporated within 24 hours via nightly rebuilds

Check the image provenance to see exact build time:

```bash
docker inspect alpine:3.22 | jq '.[0].Created'
```

### What's the difference between musl and glibc?

Alpine uses **musl libc** instead of **glibc**:

**Pros:**

- Smaller size (~600KB vs 3MB)
- Simpler codebase (better for security auditing)
- Standards-compliant
- Works for 99% of applications

**Cons:**

- Pre-compiled binaries built for glibc won't work
- Some edge cases in thread handling
- Different DNS resolver behavior

**Solution**: Use Alpine packages (already compiled for musl) or compile from source.

### My pre-compiled binary doesn't work!

If you have a glibc-compiled binary:

**Option 1**: Use `gcompat` (adds glibc compatibility layer):

```dockerfile
RUN apk add --no-cache gcompat
```

**Option 2**: Use multi-stage build with Alpine-compiled version:

```dockerfile
FROM alpine:3.22 AS builder
RUN apk add --no-cache build-base
COPY source /src
RUN cd /src && make

FROM alpine:3.22
COPY --from=builder /src/app /app
CMD ["/app"]
```

**Option 3**: Use official Alpine package instead of external binary

### How do I find package names?

Search at [pkgs.alpinelinux.org](https://pkgs.alpinelinux.org) or use:

```bash
# Search in container
docker run alpine:3.22 apk search <package-name>

# Example: PostgreSQL
docker run alpine:3.22 apk search postgres
```

Common mappings:

- `build-essential` → `build-base`
- `python3-pip` → `py3-pip`
- `openjdk-11-jdk` → `openjdk11`

### Which version should I use?

**Production**: Pin to specific version

```dockerfile
FROM alpine:3.22.2  # Exact version
```

**Development**: Use major version

```dockerfile
FROM alpine:3.22    # Latest patch in 3.22.x
```

**Bleeding Edge**: Use edge (not recommended for production)

```dockerfile
FROM alpine:edge
```

**LTS Support**:

- Each Alpine version supported for ~2 years
- Security updates throughout support period
- See [Alpine releases](https://alpinelinux.org/releases/)

### How do I debug "package not found" errors?

```bash
# Update package index first
docker run alpine:3.22 sh -c "apk update && apk search <package>"

# Check which repository contains the package
docker run alpine:3.22 sh -c "apk update && apk search -v <package>"

# Some packages are in community repository
# Add community repo to /etc/apk/repositories if needed
```

### How do I set timezone?

```dockerfile
FROM alpine:3.22

# Install timezone data
RUN apk add --no-cache tzdata

# Set timezone
ENV TZ=America/New_York
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone

# Verify
RUN date
```

### Why is there no bash by default?

Alpine uses BusyBox `ash` shell (`/bin/sh`) to save space (~1MB savings).

To add bash:

```dockerfile
FROM alpine:3.22
RUN apk add --no-cache bash

# Then use in scripts
CMD ["/bin/bash", "-c", "echo Hello"]
```

Most shell scripts work fine with `/bin/sh`. Only add `bash` if truly needed.

### How do I install Python packages?

```dockerfile
FROM alpine:3.22

# Install Python and pip
RUN apk add --no-cache python3 py3-pip

# Install packages (use --no-cache-dir to save space)
RUN pip3 install --no-cache-dir requests flask

# Or install with build dependencies
RUN apk add --no-cache --virtual .build-deps \
        gcc \
        python3-dev \
        musl-dev && \
    pip3 install --no-cache-dir cryptography && \
    apk del .build-deps
```

### Are Alpine images secure?

**Yes!** Features:

- ✅ Minimal packages, daily rebuilds, signed images with SBOM/provenance
- ✅ Automated vulnerability scanning

Verify: `gh attestation verify oci://ghcr.io/broadsage/alpine:3.22 --owner broadsage`

### Which architectures are supported?

8 architectures: amd64, arm64, armv7, armv6, 386, ppc64le, s390x, riscv64. Docker automatically selects the correct one.

### Where can I get help?

- **Complete Guide**: [docs/usage.md](docs/usage.md) - Examples, best practices, production patterns
- **Caveats**: [docs/caveats.md](docs/caveats.md) - musl libc differences
- **Package Search**: <https://pkgs.alpinelinux.org/>
- **Report Issues**: <https://github.com/broadsage/docker-alpine/issues>

## Building Images

Use the `prepare-branch.sh` script to prepare and organize Alpine Docker images:

```bash
# Prepare edge branch
./prepare-branch.sh prepare edge

# Or run the complete workflow
./prepare-branch.sh all edge
```

For versioned releases: `./prepare-branch.sh all v3.19`

Run `./prepare-branch.sh help` for more information.

## Additional Documentation

- [About](docs/about.md) - Alpine Linux, musl libc, and BusyBox details
- [Usage](docs/usage.md) - **Complete guide** with examples and best practices
- [Build](docs/build.md) - Build Alpine images locally
- [Caveats](docs/caveats.md) - Important differences from glibc-based systems
- [GitHub Workflows](docs/github-workflows.md) - CI/CD pipeline details

## License

See [LICENSE](LICENSE) file.
