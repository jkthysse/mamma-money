# Helm

The Helm chart for this service lives at `src/helm/mamma-money-api/`. It deploys the application to Kubernetes using shared templates provided by the `src/helm/lib-common/` library chart. This document explains the structure, the decisions made, and the issues found in lib-common.

## Chart structure

```
src/helm/
├── lib-common/              provided library chart
│   ├── Chart.yaml
│   └── templates/
│       ├── _helpers.tpl
│       ├── _deployment.tpl
│       └── _service.tpl
└── mamma-money-api/         application chart
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
        ├── deployment.yaml
        └── service.yaml
```

The application chart templates contain a single line each — a call to the corresponding lib-common named template. All the Kubernetes resource structure lives in lib-common, and all the configuration lives in `values.yaml`. This is the intended pattern for a library chart: the consumer chart is thin by design.

## Naming

The requirement spec names the chart `helm/hello-world/`. This project uses `src/helm/mamma-money-api/` for two reasons. First, all source lives under `src/` as documented in `doc/docker.md`. Second, `mamma-money-api` reflects what the service actually is rather than the name of the learning exercise it started as. The release name used in `helm template` and `helm install` is `mamma-money-api` consistently.

## values.yaml decisions

```yaml
image:
  repository: mamma-money-api
  tag: local
```

The default tag is `local` to match the image produced by `bash ./mamma.sh build` on a developer machine. In CI and production this would be overridden with the git short SHA at deploy time using `--set image.tag=$SHA`.

```yaml
service:
  type: ClusterIP
  port: 80
  targetPort: 8080
```

`ClusterIP` is the correct default for an internal service — it is not exposed outside the cluster without an explicit ingress or port-forward. Port 80 on the service maps to port 8080 on the container, which is what the Go application listens on.

```yaml
probes:
  liveness:
    path: /healthz
    initialDelaySeconds: 10
    periodSeconds: 10
  readiness:
    path: /healthz
    initialDelaySeconds: 5
    periodSeconds: 10
```

Both probes point at `/healthz`, which the application exposes explicitly for this purpose. The readiness probe has a shorter initial delay than liveness — readiness failing removes the pod from the service load balancer, while liveness failing restarts the container. It is safer to be conservative with liveness.

```yaml
resources:
  requests:
    cpu: 50m
    memory: 32Mi
  limits:
    cpu: 100m
    memory: 64Mi
```

Resource requests and limits are set conservatively for a stateless Go HTTP server with no external dependencies. Requests tell the Kubernetes scheduler how much capacity to reserve on a node; limits cap what the container can actually consume. Without both, the scheduler cannot make good placement decisions and a misbehaving container can starve neighbouring pods.

## Bug found in lib-common

`src/helm/lib-common/templates/_deployment.tpl` had an indentation error in the container `ports` block. The original file had `ports` indented at the same level as `imagePullPolicy`, making it a sibling field on the container rather than a child:

```yaml
# original — incorrect
          imagePullPolicy: IfNotPresent
        ports:                          ← wrong indentation
            - name: http
```

This produces invalid Kubernetes YAML. The `ports` field must be at the same indentation level as `imagePullPolicy`, inside the container spec:

```yaml
# fixed — correct
          imagePullPolicy: IfNotPresent
          ports:                        ← correct indentation
            - name: http
```

The fix has been applied to `_deployment.tpl`. Without it, any Deployment produced by this library chart would be rejected by the Kubernetes API server.

## CI integration

The helm lint job in `.github/workflows/ci.yaml` validates the chart on every pull request and push to main:

```yaml
- name: Build lib-common dependency
  run: helm dependency build src/helm/mamma-money-api

- name: Lint chart
  run: helm lint src/helm/mamma-money-api

- name: Render chart
  run: helm template mamma-money-api src/helm/mamma-money-api
```

`helm dependency build` must run first — it resolves the `file://../lib-common` reference and packages it into `charts/` inside the application chart directory. Without this step, both `helm lint` and `helm template` fail immediately because they cannot find lib-common.

The build job in CI depends on both linting jobs passing before it runs, so a broken chart blocks the Docker image build as well.