# Operations Scripts

## Context

The operator shell workflows have been consolidated into a single root entrypoint, `mamma.sh`. This change was made to improve maintainability, reduce script drift, and keep the operator experience simple.

## Architecture

The current ops workflow is structured as follows:

- `mamma.sh` is the primary command router and shared implementation.
- `ops/environment.sh` is the configuration bootstrap that loads `ops/.env`.

### Command flow

1. Operator invokes `bash ./mamma.sh <command>`.
2. `mamma.sh` sources `ops/environment.sh`.
3. `ops/environment.sh` resolves `.env` paths relative to its own location.
4. `mamma.sh` dispatches to a command handler:
   - `build|b`
   - `run|r`
   - `verify|v`
   - `all`
   - `cluster`
   - `deploy`
   - `down`
   - `menu`
5. The handler runs Docker/curl operations using configuration loaded from `ops/.env`.

## Design choices

### 1) Single source of operational logic

Moving build/run/verify behaviour into `mamma.sh` keeps the code DRY rather than duplicating logic across scripts. This centralises change management and keeps behaviour consistent.

### 2) Relative-path-safe environment loading

`ops/environment.sh` computes paths from `${BASH_SOURCE[0]}` and loads `ops/.env` from the script directory. This avoids failures when scripts are invoked from different working directories.

### 3) Dual operator UX: command mode and menu mode

`mamma.sh` supports non-interactive command mode for automation and scripting (`build`, `run`, `verify`, aliases `b/r/v`) and interactive menu mode for ad-hoc human operation (`bash ./mamma.sh`). The same handlers back both surfaces, so behaviour is identical regardless of how the script is invoked.

### 4) Fail-fast shell behaviour

`mamma.sh` uses strict shell mode (`set -euo pipefail`) to surface errors early and prevent silent failures in multi-step operations.

### 5) k3d load balancer retained

An earlier iteration of the cluster configuration used `--no-lb` to disable the k3d load balancer container and reduce memory footprint. This was removed because `--no-lb` is mutually exclusive with k3d port mapping — enabling it caused a fatal error at cluster creation:

```
FATA[0000] failed to transform ports: port-mapping of type 'proxy' specified, but loadbalancer is disabled
```

The load balancer is required for the `--port` mapping that exposes the NodePort on the host. Without it, the service can only be reached via `kubectl port-forward`, which requires a persistent background process and diverges from the Docker workflow. The resource cost of the load balancer container is negligible compared to the operational complexity of working without it.

### 6) Fixed NodePort with k3d port mapping over `kubectl port-forward`

The cluster is created with a fixed host-to-node port mapping (`K3D_HOST_PORT:K3D_NODE_PORT`), and the Helm chart is deployed with a matching `NodePort` service via `values.local.yaml`. This means `verify` works identically against both Docker and k3d without any reconfiguration — `BASE_URL` in `ops/.env` points to the same `HOST:PORT` in both cases.

The alternative — relying on `kubectl port-forward` — would require a persistent background process, is fragile under network changes, and creates a divergent workflow between Docker and k3d. The trade-off is that `K3D_NODE_PORT` must not conflict with other services in the cluster, which is unlikely in a minimal local setup.

### 7) Cluster preflight check in `deploy`

`deploy` checks that the named k3d cluster exists before attempting to import the image or run Helm. Without this check, a missing cluster produces an opaque k3d or Helm error mid-operation. The preflight exits early with a clear message pointing the operator to `mamma.sh cluster`.

### 8) `values.local.yaml` as an explicit local override file

Rather than passing `--set` flags at deploy time, local k3d overrides are captured in `values.local.yaml` and committed to the repository. This makes the local deployment configuration visible, reviewable, and consistent across machines. The base `values.yaml` is unchanged and remains valid for non-local environments — the separation ensures no local-only values accidentally propagate to production deployments.

### 9) Configurable cluster topology via `ops/.env`

Cluster shape (server count, agent count, port mapping) is driven by `ops/.env` variables rather than hardcoded in the script. This allows developers on different machines to tune their local setup without modifying shared code. All variables have defaults that produce a working minimal cluster out of the box, so no configuration is required for a standard setup.

## Trade-offs

### Benefits

- **Consistency:** One implementation for all operator workflows.
- **Maintainability:** Reduced script duplication and centralised change management.
- **Usability:** Supports both scripted and interactive operation from the same entrypoint.
- **Robustness:** Path-safe config loading, fail-fast shell mode, and preflight checks surface problems early.
- **Portability:** Works on Linux, macOS, and Windows (WSL2). Git Bash on Windows is not tested and not recommended due to path translation behaviour and k3d compatibility.
- **Local parity:** Fixed port mapping means `verify` behaves identically against Docker and k3d.

### Costs / limitations

- **Single script responsibility grows:** `mamma.sh` now owns more behaviour and may need occasional refactoring as features expand.
- **Menu complexity:** Interactive mode adds UX code that is not needed for CI/non-interactive contexts.
- **`all` semantics are intentionally simple:** `all` runs build + verify and expects a running container for verification; it does not orchestrate a detached run lifecycle.
- **k3d port conflict risk:** The fixed `K3D_NODE_PORT` could conflict with another service in the cluster, though this is unlikely in a minimal local setup.
- **`values.local.yaml` is committed:** Local override values are visible in the repository, which is intentional for transparency but means the file should never contain secrets.

## Operational guidance

- Preferred day-to-day operator commands:
  - `bash ./mamma.sh build`
  - `bash ./mamma.sh run`
  - `bash ./mamma.sh verify`
- Short aliases are available:
  - `bash ./mamma.sh b`
  - `bash ./mamma.sh r`
  - `bash ./mamma.sh v`

## Local k3d deployment

For deploying to a local Kubernetes cluster on a resource-constrained machine, the workflow is:

```bash
# 1. Create the cluster (once)
bash ./mamma.sh cluster

# 2. Build the image and deploy to the cluster
bash ./mamma.sh build
bash ./mamma.sh deploy

# 3. Verify the service (same command as Docker verification)
bash ./mamma.sh verify

# 4. When done, reclaim resources
bash ./mamma.sh down
```

### Cluster configuration

The `cluster` command is fully configurable via `ops/.env`. All variables have sensible defaults so no changes are required for a standard local setup.

| Variable | Default | Description |
|---|---|---|
| `K3D_CLUSTER_NAME` | `mamma-money` | Name of the local k3d cluster |
| `K3D_SERVERS` | `1` | Number of server nodes |
| `K3D_AGENTS` | `0` | Number of agent nodes |
| `K3D_HOST_PORT` | `8080` | Host port mapped into the cluster |
| `K3D_NODE_PORT` | `30080` | NodePort exposed by the cluster |

The default configuration is intentionally minimal — a single server node with no agents, Traefik, or metrics-server disabled.

Developers who want a heavier local setup (e.g. a dedicated agent node) can override the relevant variables in their `ops/.env`:

```bash
K3D_AGENTS=1
```

The port mapping means `verify` works identically against both Docker and k3d without reconfiguration.

### Helm values

`values.local.yaml` is applied automatically by `deploy`. It overrides:
- `image.pullPolicy: Never` — uses the locally imported image without attempting a registry pull
- `service.type: NodePort` with `nodePort: 30080` — aligns with the k3d port mapping

The base `values.yaml` is unchanged and remains valid for non-local environments.

## Future considerations

- Add a dedicated `run-bg` command for detached execution and a paired `stop` command.
- Add preflight checks (port availability, Docker daemon status) before `run`.
- Add optional structured logging mode for non-interactive script usage in CI.