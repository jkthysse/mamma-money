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
   - `menu`
5. The handler runs Docker/curl operations using configuration loaded from `ops/.env`.

## Design choices

### 1) Single source of operational logic

Moving build/run/verify behaviour into `mamma.sh` keeps the code DRY rather than duplicating logic across scripts. This centralises change management and keeps behaviour consistent.

### 2) Relative-path-safe environment loading

`ops/environment.sh` now computes paths from `${BASH_SOURCE[0]}` and loads `ops/.env` from the script directory. This avoids failures when scripts are invoked from different working directories.

### 3) Dual operator UX: command mode and menu mode

`mamma.sh` supports:

- non-interactive command mode for automation and scripting (`build`, `run`, `verify`, aliases `b/r/v`)
- interactive menu mode for ad-hoc human operation (`bash ./mamma.sh`)

### 4) Fail-fast shell behaviour

`mamma.sh` uses strict shell mode (`set -euo pipefail`) to surface errors early and prevent silent failures.

## Trade-offs

### Benefits

- **Consistency:** One implementation for build/run/verify.
- **Maintainability:** Reduced script duplication and easier future changes.
- **Usability:** Supports both scripted and interactive operation.
- **Robustness:** Path-safe config loading works regardless of current directory.

### Costs / limitations

- **Single script responsibility grows:** `mamma.sh` now owns more behaviour and may need occasional refactoring as features expand.
- **Menu complexity:** Interactive mode adds UX code that is not needed for CI/non-interactive contexts.
- **`all` semantics are intentionally simple:** `all` runs build + verify and expects a running container for verification; it does not orchestrate a detached run lifecycle.

## Operational guidance

- Preferred day-to-day operator commands:
  - `bash ./mamma.sh build`
  - `bash ./mamma.sh run`
  - `bash ./mamma.sh verify`
- Short aliases are available:
  - `bash ./mamma.sh b`
  - `bash ./mamma.sh r`
  - `bash ./mamma.sh v`
## Future considerations

- Add a dedicated `run-bg` command for detached execution and a paired `stop` command.
- Add preflight checks (port availability, Docker daemon status) before `run`.
- Add optional structured logging mode for non-interactive script usage in CI.
