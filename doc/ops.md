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
   - `run-bg`
   - `stop`
   - `verify|v`
   - `all`
   - `cluster`
   - `deploy`
   - `down`
   - `status`
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

The cluster is created with a fixed host-to-node port mapping (`HOST_PORT:NODE_PORT`), and the Helm chart is deployed with a matching `NodePort` service. This means `verify` works identically against both Docker and k3d without any reconfiguration — `BASE_URL` in `ops/.env` points to the same `${HOST_PROTOCOL}://${HOST_SERVER_NAME}:${HOST_PORT}` in both cases.

The alternative — relying on `kubectl port-forward` — would require a persistent background process, is fragile under network changes, and creates a divergent workflow between Docker and k3d. The trade-off is that `NODE_PORT` must not conflict with other services in the cluster, which is unlikely in a minimal local setup.

### 7) Cluster preflight check in `deploy`

`deploy` checks that the named k3d cluster exists before attempting to import the image or run Helm. Without this check, a missing cluster produces an opaque k3d or Helm error mid-operation. The preflight exits early with a clear message pointing the operator to `mamma.sh cluster`.

### 8) `values.local.yaml` as an explicit local override file with dynamic NodePort injection

Local k3d overrides are captured in `values.local.yaml` and committed to the repository, making local deployment configuration visible, reviewable, and consistent across machines. The base `values.yaml` is unchanged and remains valid for non-local environments.

`service.nodePort` is intentionally absent from `values.local.yaml`. It is injected dynamically at deploy time by `mamma.sh` via `--set service.nodePort="${NODE_PORT}"`, sourced from `ops/.env`. This means `NODE_PORT` is the single source of truth for the node port — changing it in `.env` flows through to both the cluster port mapping and the Helm service without requiring any manual edits to committed files.

An earlier iteration hardcoded `nodePort: 30080` in `values.local.yaml`. This caused a silent misconfiguration: when `NODE_PORT` was changed in `.env`, the cluster port mapping updated correctly but the Helm service continued to expose the old port, resulting in connection failures (`HTTP 000` from curl) with no obvious error message.

### 9) `HOST_PORT` as the single source of truth for the host port

An earlier iteration used two separate variables: `PORT` (for Docker and verification) and `HOST_PORT` (for the k3d cluster port mapping). These were required to always match, creating a silent misconfiguration risk — changing one without the other caused `verify` to fail with `HTTP 000`.

`PORT` was removed and replaced with `HOST_PORT`, which is used everywhere the host port is needed: Docker port binding, the `BASE_URL` for verification, and the k3d cluster port mapping. Changing `HOST_PORT` once in `ops/.env` is sufficient.

The Go application reads `PORT` as its internal listening port, not `HOST_PORT`. `mamma.sh` bridges the two by passing `HOST_PORT`'s value into the container as `-e PORT="${HOST_PORT}"`. This preserves the application's interface while keeping the operator configuration clean.

### 10) `teardown` renamed to `down`

The command was renamed from `teardown` to `down` for brevity and consistency with common container tooling conventions (`docker compose down`). The underlying function was renamed from `do_teardown` to `do_down` to match. All references — the command dispatcher, menu, and help text — were updated consistently.

### 11) Configurable cluster topology via `ops/.env`

Cluster shape (server count, agent count, port mapping) is driven by `ops/.env` variables rather than hardcoded in the script. This allows developers on different machines to tune their local setup without modifying shared code. All variables have defaults that produce a working minimal cluster out of the box, so no configuration is required for a standard setup.

### 12) Human-readable script structure

`mamma.sh` uses named logging helpers (`_step`, `_ok`, `_err`, `_warn`, `_dim`, `_divider`, `_pause`) in place of bare `echo` calls throughout all command functions. All output flows through these helpers, which means a single `if [[ CI == true ]]` block at the top of the script is sufficient to switch the entire output mode — no command function needs to know whether it is running interactively or in a pipeline.

Section dividers (`# ─── Name ───`) break the script into clearly labelled regions (Bootstrap, Logging, Preflight helpers, Commands, Help, Interactive menu, Entry point), making it easier to navigate without an IDE.

The trade-off is a small indirection cost: contributors adding new commands must use the logging helpers rather than calling `echo` directly, and `_pause` / `_header` are no-ops in CI that exist solely to satisfy the interactive code path cleanly.

### 13) `run-bg` and `stop` as a paired detached lifecycle

`run` attaches to the container in the foreground and uses `--rm` so the container is automatically removed when the process exits. This is appropriate for interactive use but blocks the terminal and does not compose well with multi-step scripted workflows.

`run-bg` runs the container detached (`docker run -d`) without `--rm`. The container is named `${CONTAINER_NAME}` explicitly so that the paired `stop` command has a stable, unambiguous target. `stop` checks whether the named container is actually running before calling `docker stop` and `docker rm`, emitting an idempotent warning rather than an error if the container is already gone — important for scripts that may call `stop` defensively as a cleanup step.

The `--rm` flag is intentionally absent from `run-bg`: `--rm` causes Docker to remove the container immediately on exit, which would race with `stop` and make the command unreliable. The container therefore persists until `stop` is called explicitly.

Both commands appear in the dispatcher, the interactive menu, and the help text so the lifecycle is discoverable from all entry points.

### 14) Preflight checks before `run`, `run-bg`, and `build`

Two preflight helpers gate the commands that require a working Docker environment:

`_require_docker_daemon` calls `docker info` and exits early with a clear error if the daemon is unreachable. Without this check, a missing daemon produces a generic Docker error mid-command that is harder to act on than "Start Docker Desktop and try again."

`_require_port_free` probes `HOST_PORT` before starting a container, avoiding the cryptic `bind: address already in use` error that Docker emits when a port is already occupied. The implementation tries `ss` first (available on Linux) and falls back to `lsof` (available on macOS). If neither tool is present the check is skipped rather than blocking — this is a deliberate portability trade-off: failing hard on a missing `ss`/`lsof` would break the script on stripped environments where those tools are not installed.

Both helpers are called from `do_build`, `do_run`, and `do_run_bg`. Adding them to `build` means a failed daemon is caught before a potentially long build rather than only at the subsequent `run`.

### 15) Structured log output for CI

Most CI platforms (GitHub Actions, CircleCI, GitLab CI, Jenkins) set `CI=true` in the build environment automatically. `mamma.sh` reads `CI="${CI:-false}"` at startup and branches the entire logging layer on that value.

In CI mode all logging helpers emit plain text with `[INFO]`, `[OK]`, `[ERROR]`, and `[WARN]` level prefixes, no ANSI escape codes, and no Unicode box-drawing characters. `_divider`, `_header`, and `_pause` become no-ops — `_header` clears the screen and renders a decorative box that is meaningless in a log stream, and `_pause` waits for user input that will never arrive. Neither call needs to be removed from command functions; they simply do nothing in CI context.

Because all command functions write output exclusively through these helpers, no command function contains any CI-specific branching. The same `do_build` (for example) works correctly for both a developer at a terminal and a CI runner.

The trade-off is that contributors adding new commands must use the helpers rather than calling `echo` directly, which is a small convention overhead. The benefit is that CI compatibility is structural rather than incidental — it cannot be accidentally broken by a new command that uses `echo` with ANSI codes.

### 16) `status` command for cluster and pod health visibility

The raw output of `kubectl get nodes`, `kubectl get pods`, and `kubectl get svc` is wide, multi-column, and difficult to scan at a glance, particularly when multiple namespaces and system pods are present alongside application workloads.

`do_status` reformats each resource type with `awk` into a consistent fixed-width layout and prepends a `✔` or `✘` icon based on the resource's reported state. Three resource types are surfaced deliberately:

- **Nodes** — confirm the cluster plane is healthy before drawing conclusions about pods.
- **Pods (all namespaces)** — surface both application and system pod state. Restart count is included because a pod that is `Running` but has restarted repeatedly is not healthy in any operational sense; the raw status field alone would hide this.
- **Services** — confirm the service is registered and exposing the expected port, catching cases where a Helm deployment succeeded but the service configuration is wrong.

All `kubectl` calls pin `--context k3d-${cluster_name}` explicitly. This ensures `status` targets the correct cluster on machines with multiple kubeconfig contexts — without the flag, `kubectl` would silently query whichever context is currently active, which may not be the local k3d cluster.

The `awk` formatting is human-readable but not machine-parseable. In CI contexts where structured pod status is needed, `kubectl` should be called directly with `-o json` or `-o jsonpath`.

## Trade-offs

### Benefits

- **Consistency:** One implementation for all operator workflows.
- **Maintainability:** Reduced script duplication and centralised change management.
- **Usability:** Supports both scripted and interactive operation from the same entrypoint.
- **Robustness:** Path-safe config loading, fail-fast shell mode, and preflight checks surface problems early.
- **Portability:** Works on Linux, macOS, and WSL2 without modification. Port-check falls back gracefully when `ss`/`lsof` are unavailable.
- **Local parity:** Fixed port mapping means `verify` behaves identically against Docker and k3d.
- **Single source of truth for ports:** `HOST_PORT` and `NODE_PORT` are the only values to change when reconfiguring ports — no duplication, no silent mismatches.
- **CI compatibility is structural:** output mode is determined once at startup; individual commands contain no CI-specific branching and cannot accidentally break it.
- **Detached lifecycle is explicit:** `run-bg` and `stop` form a complete, discoverable pair with clear container-naming semantics.

### Costs / limitations

- **Single script responsibility grows:** `mamma.sh` now owns more behaviour and may need occasional refactoring as features expand.
- **Menu complexity:** Interactive mode adds UX code that is not needed for CI/non-interactive contexts.
- **`all` semantics are intentionally simple:** `all` runs build + verify and expects a running container for verification; it does not orchestrate a detached run lifecycle.
- **k3d port conflict risk:** The fixed `NODE_PORT` could conflict with another service in the cluster, though this is unlikely in a minimal local setup.
- **`values.local.yaml` is committed:** Local override values are visible in the repository, which is intentional for transparency but means the file should never contain secrets.
- **`HOST_PORT` / app `PORT` indirection:** The mapping between `HOST_PORT` (operator config) and `PORT` (app env var) is implicit in `mamma.sh`. A developer reading the Dockerfile or Go source will see `PORT`; a developer reading `ops/.env` will see `HOST_PORT`. This is documented but adds a small cognitive overhead.
- **Logging helper convention:** Contributors must use `_step`/`_ok`/`_err` etc. rather than bare `echo` calls. A command that writes directly to stdout will bypass CI mode and emit ANSI codes in log output.
- **`status` output is human-readable only:** the `awk`-formatted node/pod/service tables are not machine-parseable. CI workflows that need structured cluster state should call `kubectl` directly with `-o json` or `-o jsonpath`.

## Operational guidance

- Preferred day-to-day operator commands:
  - `bash ./mamma.sh build`
  - `bash ./mamma.sh run`
  - `bash ./mamma.sh verify`
- Short aliases are available:
  - `bash ./mamma.sh b`
  - `bash ./mamma.sh r`
  - `bash ./mamma.sh v`
- For scripted or background workflows:
  - `bash ./mamma.sh run-bg` — start the container detached
  - `bash ./mamma.sh stop`   — stop and remove it
- To inspect cluster health after a k3d deployment:
  - `bash ./mamma.sh status`

## Local k3d deployment (WSL2)

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

> Note on the assessment 'bonus' port (8081): the requirement suggests port-forwarding to `localhost:8081`. This repo instead uses a fixed k3d host port mapping (`HOST_PORT:NODE_PORT`) so `mamma.sh verify` runs against the same `BASE_URL` format used for Docker. See [Assessor Notes](./assessors.md) for the full deviation rationale. The screenshots below reflect the default `HOST_PORT=8080`. To match the requirement exactly, set `HOST_PORT=8081` in `ops/.env` and rerun `cluster`, `deploy`, and `verify`.

**Evidence: local k3d workflow (screenshots)**

**1) Cluster creation (`bash ./mamma.sh cluster`)**

<img src="img/cluster_create.png" alt="Successful cluster creation" width="800" style="height:auto;" />

**2) Build + deploy (`bash ./mamma.sh build` + `bash ./mamma.sh deploy`)**

<img src="img/cluster_build.png" alt="Successful cluster build run" width="800" style="height:auto;" />

<img src="img/cluster_deploy.png" alt="Successful Helm deployment" width="800" style="height:auto;" />

**3) Verify + kubectl checks (`bash ./mamma.sh verify`)**

<img src="img/cluster_verify.png" alt="Cluster successfully verified" width="800" style="height:auto;" />

<img src="img/kubectl_checks.png" alt="Successful Kubectl checks" width="800" style="height:auto;" />

### Cluster configuration

The `cluster` command is fully configurable via `ops/.env`. All variables have sensible defaults so no changes are required for a standard local setup.

| Variable | Default | Description |
|---|---|---|
| `HOST_PORT` | `8080` | Host port — used for Docker, verification, and k3d port mapping |
| `CLUSTER_NAME` | `mamma-money` | Name of the local k3d cluster |
| `CLUSTER_SERVERS` | `1` | Number of server nodes |
| `CLUSTER_AGENTS` | `0` | Number of agent nodes |
| `NODE_PORT` | `30080` | NodePort exposed by the cluster |

`HOST_PORT` is the single variable to change when running on a different port. It flows through to Docker port binding, the `BASE_URL` used by `verify`, and the k3d cluster port mapping automatically.

Developers who want a heavier local setup (e.g. a dedicated agent node) can override the relevant variables in their `ops/.env`:

```bash
CLUSTER_AGENTS=1
```

The port mapping means `verify` works identically against both Docker and k3d without reconfiguration.

### Helm values

`values.local.yaml` is applied automatically by `deploy`. It overrides:
- `image.pullPolicy: Never` — uses the locally imported image without attempting a registry pull
- `service.type: NodePort` — exposes the service via a fixed node port

`service.nodePort` is not hardcoded in `values.local.yaml`. It is injected dynamically at deploy time from `NODE_PORT` in `ops/.env` via `--set service.nodePort`. This ensures the node port is always consistent with the cluster port mapping without requiring manual edits to committed files.

The base `values.yaml` is unchanged and remains valid for non-local environments.