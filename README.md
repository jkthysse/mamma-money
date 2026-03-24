# Production-ready deployment of containerised Go app

This repository contains a simple Go web server and development documentation.

## Repository layout

- `README.md`: Developer usage documentation (this document)
- `doc/requirement.md`: [Business requirement document](./doc/requirement.md)
- `doc/docker.md`: [Docker feature development document](./doc/docker.md)
- `doc/contributing.md`: [Contributing guide](./doc/contributing.md)
- `src/app`: Go application source code

## Prerequisites

## Prerequisites

- Go 1.22+
- Git
- Docker (BuildKit-enabled)

## Quick start

Run directly with Go:

```bash
go run ./src/app
```
The app listens on `PORT` (default `8080`).

## Build and run with Docker

From the repository root:

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