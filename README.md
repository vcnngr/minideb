# VCNNGR MinidEB

**Based on Bitnami MinidEB** - A minimalist Debian-based image for containers.

## Attribution & License

This project is a fork of [Bitnami MinidEB](https://github.com/bitnami/minideb) maintaining full attribution to the original work.

**Original Copyright:** Copyright 2016-2024 Broadcom. All Rights Reserved.  
**License:** Apache License 2.0

---

## Usage

```bash
docker run --rm -it vcnngr/minideb:bookworm
```

Distributions available:
- `bookworm` (Debian 12)
- `trixie` (Debian 13 testing)
- `bullseye` (Debian 11)
- `latest` (trixie)

## Features

- **Small**: ~100MB vs ~200MB standard Debian
- **Daily Updates**: Security patches within 24h
- **Multi-Arch**: AMD64 and ARM64
- **Reproducible**: Every build is verified
- **Quality**: Debian official packages via apt

## install_packages

Convenience command for package installation:

```bash
install_packages nginx postgresql redis
```

Handles retries, cleanup, and optimization automatically.

## Building

### Build All
```bash
sudo make
```

### Build Specific Distribution
```bash
sudo make bookworm
```

### Multi-Architecture
```bash
./qemu_build bookworm arm64
```

## CI/CD

Uses Jenkins on Kubernetes for automated builds. See [Jenkinsfile](Jenkinsfile).

## Security

- Daily automated builds
- Security updates from Debian
- Trivy vulnerability scanning
- Debian Security Tracker for CVEs

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md).

## Acknowledgments

Built on the excellent work of the Bitnami team.

**Original Project:** https://github.com/bitnami/minideb

---

**"Bitnami Skills, VCNNGR Style"**
