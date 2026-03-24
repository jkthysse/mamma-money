# Production-ready deployment of containerised Go app

This repository contains a containerised Go web server and development documentation.

## Repository Index

- `.github/workflows/ci.yaml`: GitHub CI pipeline configuration
- `doc/contributing.md`: [Contributing guide](./doc/contributing.md)
- `doc/docker.md`: [Docker feature development document](./doc/docker.md)
- `doc/helm.md`: [Helm feature development document](./doc/helm.md)
- `doc/pipeline.md`: [CI feature development document](./doc/pipeline.md)
- `doc/requirement.md`: [Business requirement specification document](./doc/requirement.md)
- `src/app`: Go application source code
- `src/helm`: Helm templates
- `src/.dockerignore`: Docker ignore file
- `src/Dockerfile`: Docker configuration file
- `.env.example`: Example environment configuration file
- `.gitattributes`: Normalise all text files to LF line endings on checkout 
- `.gitignore`: Keeps local environment configuration file out of the repo
- `build.sh`: Operational build script for non-technical operators
- `environment.sh`: Operational environment script to maintain DRY coding standards
- `run.sh`: Operational run script for non-technical operators
- `verify.sh`: Operational test script for non-technical operators
- `README.md`: Developer usage documentation (this document)

## Prerequisites

- Go 1.22+
- Git
- Docker (BuildKit-enabled)

## Configuration

Copy the `.env.example` in the root of the project to `.env` and update the values to match your desired configuration.

## Shell compatibility
Commands in this repository are written for Bash.
- Use `bash ./...` commands in Linux/macOS/PowerShell.

## Quick start

### First-run checklist

1. Create `.env` from `.env.example`
2. Confirm `PLATFORM`, `PORT`, and `IMAGE` values
3. Run build, run, verify scripts from repo root

### Start here
- Run app locally (developer): see `src/app` and [Developer Flow](./README.md#developer-flow---run-with-go).
- Build/run container feature details: see [Docker Feature Documentation](./doc/docker.md) and [Operator Flow](./README.md#operator-flow---run-with-docker).
- See [Helm deployment details](./doc/helm.md)
- See [CI behavior and trade-offs](./doc/pipeline.md)
- See [Contribution workflow](./doc/contributing.md)

### Developer Flow - Run with Go:

Run this command from the repository root.

```bash
go run ./src/app
```
The app listens on `PORT` (default `8080`).

### Operator Flow - Run with Docker:

Run these commands from the repository root.

Build:

```bash
bash ./build.sh
```

Run:

```bash
bash ./run.sh
```

Smoke test:

```bash
bash ./verify.sh
```

## Troubleshooting

- `Error: .env not found`  
  Create `.env` from `.env.example` in repo root.
- `bind: address already in use`  
  Change `PORT` in `.env` or stop the process using that port.
- `buildx` command unavailable  
  Ensure Docker Desktop is up to date and Buildx is enabled.

## Notes for contributors

- Keep Docker build context scoped to `src` to avoid sending unnecessary files.
- Maintain multi-stage build pattern and a non-root runtime image.
- When adding dependencies, keep `go.mod` and `go.sum` in `src/app` updated.
- See the [Contributing guide](./doc/contributing.md)
