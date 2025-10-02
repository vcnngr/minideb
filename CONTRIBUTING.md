# Contributing to VCNNGR MinidEB

## Getting Started

1. Fork the repository
2. Clone: `git clone https://github.com/your-username/minideb`
3. Branch: `git checkout -b feature/your-feature`

## Development

Build locally:
```bash
sudo make bookworm
```

Test:
```bash
sudo make test-bookworm
```

## Standards

- All scripts must pass shellcheck
- Maintain reproducible builds
- Follow existing code style

## Submitting

1. Ensure tests pass
2. Update docs if needed
3. Clear commit messages
4. Push and create PR
