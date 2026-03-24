# Production-ready deployment of containerised Go app

This repository contains a simple Go web server and development documentation.

## Repository layout

- `README.md`: Developer usage documentation (this document)
- `doc/requirement.md`: [Business requirement specification document](./doc/requirement.md)
- `doc/docker.md`: [Docker feature development document](./doc/docker.md)
- `doc/contributing.md`: [Contributing guide](./doc/contributing.md)
- `src/app`: Go application source code
- `src/helm`: Helm templates provided
- `src/.dockerignore`: Docker ignore file
- `src/Dockerfile`: Docker configuration file
- `.env.example`: Example environment configuration file
- `.gitattributes`: Normalise all text files to LF line endings on checkout 
- `.gitignore`: Keeps local environment configuration file out of the repo
- `build.sh`: Operational build script for non-technical operators
- `environment.sh`: Operational environment script to maintain DRY coding standards
- `run.sh`: Operational run script for non-technical operators
- `verify.sh`: Operational test script for non-technical operators

## Prerequisites

- Go 1.22+
- Git
- Docker (BuildKit-enabled)

## Configuration

Copy the `.env.example` in the root of the project to `.env`.  Update the values to match your desired configuration.

## Quick start

### Run directly with Go:

From the repository root:

```bash
go run ./src/app
```
The app listens on `PORT` (default `8080`).

### Run with Docker

From the repository root:

Build:

```bash
./build.sh
```

Run:

```bash
./run.sh
```

Smoke test:

```bash
./verify.sh
```

## Notes for contributors

- Keep Docker build context scoped to `src` to avoid sending unnecessary files.
- Maintain multi-stage build pattern and a non-root runtime image.
- When adding dependencies, keep `go.mod` and `go.sum` in `src/app` updated.