# Pipeline

The CI pipeline runs on GitHub Actions and is defined in `.github/workflows/ci.yaml`. It triggers on every push to `main` and on every pull request, regardless of the target branch.

## Why these triggers

Running on pull requests catches issues before merge to `main`. Running on pushes to `main` also validates merge commits, including squash-merge outcomes that may differ slightly from branch-tested states.

## Workflow permissions

The workflow declares `contents: read`, `actions: read`, and `security-events: write`. The last permission allows CodeQL analysis and SARIF uploads (Hadolint code-quality results) to be written to GitHub’s security and code-quality surfaces, which branch protection rules can then enforce.

## Jobs

### CodeQL analysis

A dedicated job runs [CodeQL](https://codeql.github.com/) for Go on every trigger:

- Checkout
- Set up Go 1.22
- Initialise CodeQL for `go`
- `go build ./...` in `src/app` (build step improves analysis precision)
- `github/codeql-action/analyze@v3`

Findings appear under repository security / code scanning. When **branch rules** require code scanning with thresholds such as **high or higher** for security alerts and **errors** for overall alerts, merges to protected branches are blocked until those checks pass on the default or required workflow runs.

### Lint Helm chart

```yaml
lint-helm:
  name: Lint Helm Chart
  runs-on: ubuntu-latest
  steps:
    - name: Checkout
      uses: actions/checkout@v4
    - name: Set up Helm
      uses: azure/setup-helm@v4
```

Helm provides first-class tooling for validating charts before they are applied to a cluster. The lint job runs three steps in sequence: `helm dependency build` to resolve the lib-common local dependency, `helm lint` to catch structural and schema errors, and `helm template` to render the chart to YAML and confirm the output is valid. A chart that passes all three is safe to deploy.

`azure/setup-helm` installs Helm on the runner cleanly without a manual installation step.

### Lint Dockerfile

```yaml
lint-dockerfile:
  name: Lint Dockerfile
  runs-on: ubuntu-latest
  steps:
    - name: Checkout
      uses: actions/checkout@v4
      
    - name: Lint Dockerfile
      uses: hadolint/hadolint-action@v3.1.0
      with:
        dockerfile: src/Dockerfile
```

Hadolint is a Dockerfile linter that checks for common mistakes and deviations from best practice — things like missing `--no-cache` on package installs, using `ADD` where `COPY` is sufficient, or running as root. It understands the Dockerfile syntax deeply enough to follow shell commands inside `RUN` instructions.

Using the official `hadolint-action` keeps the step clean — no manual installation, no curl scripts, and the action pins to a specific version so the linting behaviour doesn't change unexpectedly between runs.

After the action step, the workflow runs the Hadolint container again to emit **SARIF** from `src/Dockerfile`, then uploads it with `github/codeql-action/upload-sarif@v3` and `category: code-quality`. That populates GitHub **code quality** alerts for the run so branch rules that require the code-quality gate at **errors** severity can evaluate this analysis alongside other uploaded SARIF.

### Build Docker image

```yaml
build:
  needs: [codeql, lint-dockerfile, lint-helm]
```

The build job only runs after CodeQL analysis and both lint jobs pass. There is no value in spending compute on a build if static analysis or chart validity has already failed.

The build uses `docker/setup-buildx-action` and `docker/build-push-action`, which are standard GitHub Actions for BuildKit builds. An alternative is running `docker buildx build` directly in a shell step, but the Actions handle BuildKit initialisation, caching configuration, and multi-platform setup with less boilerplate.

`push: false` means the image is built and verified but not pushed to any registry. The build job exists to confirm the image compiles and layers correctly, not to produce a deployable artefact.

The image is tagged with the git short SHA:

```yaml
- name: Get short SHA
  id: sha
  run: echo "short=${GITHUB_SHA::7}" >> $GITHUB_OUTPUT

tags: mamma-money-api:${{ steps.sha.outputs.short }}
```

The short SHA makes every build traceable back to the exact commit that produced it without the verbosity of the full 40-character hash. In a production pipeline this tag would be pushed to a registry and used at deploy time.

## Branch rules vs workflow

- **Code scanning (CodeQL)** and **code quality (SARIF)** gates are enforced by GitHub **branch protection / rulesets** once analysis results exist for the required checks. The workflow supplies those results; the rule configuration defines pass thresholds (for example high-or-higher security and errors-level blocking).
- **Copilot code review** (review on push, excluding draft pull requests) is a repository-level Copilot and rules configuration. It is not expressed in `ci.yaml`; it complements CI but does not replace the lint and build jobs.

See also [Contributing](./contributing.md) for the documented `main` branch rule expectations.

## Trade-offs

Running CI on every pull request provides fast feedback, but each branch push consumes runner minutes. For small teams this is generally acceptable; note that the `pull_request` trigger runs on every branch push, not only when a pull request is opened.

The build job does not cache Docker layers between runs. BuildKit cache mounts work locally but GitHub Actions runners are ephemeral — each run starts fresh. Layer caching across runs is possible using `cache-from` and `cache-to` with GitHub's cache store, but adds complexity. For a build this fast it is not worth it yet.