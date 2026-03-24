# Pipeline

The CI pipeline runs on GitHub Actions and is defined in `.github/workflows/ci.yaml`. It triggers on every push to `main` and on every pull request, regardless of the target branch.

## Why these triggers

Running on pull requests is where the pipeline earns its keep — it catches problems before they reach `main`, which is the point. Running on pushes to `main` as well means the pipeline also validates merge commits, which matters if a squash merge produces something subtly different from what was tested on the branch.

## Jobs

### Lint Helm chart

```yaml
lint-helm:
  uses: azure/setup-helm@v4
```

Helm provides first-class tooling for validating charts before they are applied to a cluster. The lint job runs three steps in sequence: `helm dependency build` to resolve the lib-common local dependency, `helm lint` to catch structural and schema errors, and `helm template` to render the chart to YAML and confirm the output is valid. A chart that passes all three is safe to deploy.

`azure/setup-helm` installs Helm on the runner cleanly without a manual installation step.

### Lint Dockerfile

```yaml
lint-dockerfile:
  uses: hadolint/hadolint-action@v3.1.0
  with:
    dockerfile: src/Dockerfile
```

Hadolint is a Dockerfile linter that checks for common mistakes and deviations from best practice — things like missing `--no-cache` on package installs, using `ADD` where `COPY` is sufficient, or running as root. It understands the Dockerfile syntax deeply enough to follow shell commands inside `RUN` instructions.

Using the official `hadolint-action` keeps the step clean — no manual installation, no curl scripts, and the action pins to a specific version so the linting behaviour doesn't change unexpectedly between runs.

### Build Docker image

```yaml
build:
  needs: [lint-dockerfile, lint-helm]
```

The build job only runs if both lint jobs pass. There is no value in spending compute on a build if either the Dockerfile or the Helm chart has already been flagged as invalid.

The build uses `docker/setup-buildx-action` and `docker/build-push-action`, which are the standard GitHub Actions for BuildKit builds. The alternative would be running `docker buildx build` directly in a shell step, but the Actions handle BuildKit initialisation, layer caching configuration, and multi-platform setup cleanly without boilerplate.

`push: false` means the image is built and verified but not pushed to any registry. The build job exists to confirm the image compiles and layers correctly, not to produce a deployable artefact.

The image is tagged with the git short SHA:

```yaml
- name: Get short SHA
  id: sha
  run: echo "short=${GITHUB_SHA::7}" >> $GITHUB_OUTPUT

tags: mamma-money-api:${{ steps.sha.outputs.short }}
```

The short SHA makes every build traceable back to the exact commit that produced it without the verbosity of the full 40-character hash. In a production pipeline this tag would be pushed to a registry and used at deploy time.

## Trade-offs

Running CI on every pull request means developers get feedback quickly, but it also means every branch push consumes runner minutes. For a small team this is a non-issue, but it is worth knowing that the `pull_request` trigger fires on every push to the branch, not just when the PR is opened.

The build job does not cache Docker layers between runs. BuildKit cache mounts work locally but GitHub Actions runners are ephemeral — each run starts fresh. Layer caching across runs is possible using `cache-from` and `cache-to` with GitHub's cache store, but adds complexity. For a build this fast it is not worth it yet.