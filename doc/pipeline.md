# Continuous Integration Pipeline

# Pipeline

The CI pipeline runs on GitHub Actions and is defined in `.github/workflows/ci.yml`. It triggers on every push to `main` and on every pull request, regardless of the target branch.

## Why these triggers

Running on pull requests is where the pipeline earns its keep — it catches problems before they reach `main`, which is the point. Running on pushes to `main` as well means the pipeline also validates merge commits, which matters if a squash merge produces something subtly different from what was tested on the branch.

## Jobs

The pipeline is being built incrementally alongside the features it covers. Jobs are added as the corresponding feature is developed, so the pipeline always reflects the current state of the codebase rather than referencing things that don't exist yet.

### Lint Dockerfile

```yaml
lint-dockerfile:
  uses: hadolint/hadolint-action@v3.1.0
  with:
    dockerfile: src/Dockerfile
```

Hadolint is a Dockerfile linter that checks for common mistakes and deviations from best practice — things like missing `--no-cache` on package installs, using `ADD` where `COPY` is sufficient, or running as root. It understands the Dockerfile syntax deeply enough to follow shell commands inside `RUN` instructions.

Using the official `hadolint-action` keeps the step clean — no manual installation, no curl scripts, and the action pins to a specific version so the linting behaviour doesn't change unexpectedly between runs.

