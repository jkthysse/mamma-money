# Production-ready deployment of containerised Go app

This repository contains a containerised Go web server and development documentation.

## Repository Index

- `.github/workflows/ci.yaml`: GitHub CI pipeline configuration
- `doc/assessors.md`: Evidence and deviation notes for assessors
- `doc/contributing.md`: [Contribution Guidelines](./doc/contributing.md)
- `doc/docker.md`: [Docker feature development documentation](./doc/docker.md)
- `doc/helm.md`: [Helm feature development documentation](./doc/helm.md)
- `doc/ops.md`: [Operational workflow documentation](./doc/ops.md)
- `doc/pipeline.md`: [CI feature development documentation](./doc/pipeline.md)
- `doc/requirement.md`: [Business requirement specification documentation](./doc/requirement.md)
- `src/app`: Go application source code
- `src/helm`: Helm deployment source code
- `src/.dockerignore`: Docker ignore file
- `src/Dockerfile`: Docker configuration file
- `ops/.env.example`: Example environment configuration file
- `ops/environment.sh`: Operational environment bootstrap script
- `.gitattributes`: Normalise all text files to LF line endings on checkout 
- `.gitignore`: Keeps local environment configuration file out of the repo
- `mamma.sh`: Unified operations script
- `README.md`: Developer usage documentation (this document)

## Prerequisites

- Curl: See [the official curl website](https://curl.se/)
- Go 1.22+ `curl -sS https://webinstall.dev/golang | bash`
- Git: `curl -sS https://webinstall.dev/git | bash`
- Docker (BuildKit-enabled): `curl -fsSL https://get.docker.com | bash`

BuildKit has been enabled by default since Docker 23, so no additional configuration needed. That said — on WSL2 most developers would typically install Docker Desktop on Windows and enable the WSL2 backend in its settings, rather than installing Docker Engine inside WSL2 directly. Docker Desktop then makes the Docker socket available inside WSL2 automatically.

## Requirements for local cluster deployment
- K3d: `curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | TAG=v5.6.0 bash`
- Helm: `curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash`

## Configuration

Copy `ops/.env.example` to `ops/.env` and update values for the target environment.

## Shell compatibility

Commands in this repository are written for Bash.
- Use `bash ./...` commands in Linux/macOS/PowerShell.

## Quick start

### First-run checklist

1. Create `ops/.env` from `ops/.env.example`
2. Confirm `TARGET_PLATFORM`, `HOST_PORT`, and `DOCKER_IMAGE` values
3. Run `mamma.sh` commands from repo root

### Start here

- Run app locally (developer): see `src/app` and [Developer Flow](./README.md#developer-flow---run-with-go).
- Build/run container feature details: see [Docker Feature Documentation](./doc/docker.md) and [Operator Flow](./README.md#operator-flow---run-with-docker).
- See [Local k3d deployment](./README.md#operator-flow---deploy-to-local-k3d-cluster)
- See [Helm deployment details](./doc/helm.md)
- See [CI behaviour and trade-offs](./doc/pipeline.md)
- See [Contribution Guidelines](./doc/contributing.md)

### Developer Flow - Run with Go:

Run this command from the repository root.

```bash
go run ./src/app
```
The app listens on `HOST_PORT` (default `8080`).

### Operator Flow - Run with Docker:

Run these commands from the repository root.

Operational commands:

```bash
bash ./mamma.sh build
bash ./mamma.sh b
bash ./mamma.sh run
bash ./mamma.sh r
bash ./mamma.sh run-bg
bash ./mamma.sh stop
bash ./mamma.sh verify
bash ./mamma.sh v
bash ./mamma.sh all
```

Interactive menu:

```bash
bash ./mamma.sh
```

### Operator Flow - Deploy to local k3d cluster:

For local Kubernetes deployment. See [Operations documentation](./doc/ops.md) for full configuration reference.

```bash
bash ./mamma.sh cluster  # create the cluster (once)
bash ./mamma.sh build    # build the image
bash ./mamma.sh deploy   # import image and install Helm chart
bash ./mamma.sh status  # node/pod/service health for the cluster
bash ./mamma.sh verify   # smoke test (same as Docker)
bash ./mamma.sh down     # delete the cluster and free resources
```

## Troubleshooting

- `Error: .env not found`  
  Create `ops/.env` from `ops/.env.example`.
- `bind: address already in use`  
  `mamma.sh` runs preflight checks before `run` / `run-bg` / `build` and will fail fast when `HOST_PORT` is already bound. Update `HOST_PORT` in `ops/.env` or stop the process using that port.
- `buildx` command unavailable  
  Ensure Docker Desktop is up to date and Buildx is enabled.

## Notes for contributors

- Keep Docker build context scoped to `src` to avoid sending unnecessary files.
- Maintain multi-stage build pattern and a non-root runtime image.
- When adding dependencies, keep `go.mod` and `go.sum` in `src/app` updated.
- See the [Contribution Guidelines](./doc/contributing.md)