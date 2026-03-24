# Docker

The service is containerised using a multi-stage Docker build at `src/Dockerfile`. This document explains the architecture decisions and their trade-offs.

## Repository layout

The requirement spec places the Dockerfile, application code, and Helm charts at the repository root. This project deviates from that deliberately.

All source code — the Go application, the Dockerfile, and the Helm charts — lives under `src/`. The repository root is reserved for operations: shell scripts, environment configuration, and CI. This separation means a developer working on the application never needs to look past `src/`, and an operator running or deploying the service works entirely from the root without digging into application internals.

The trade-off is a slight divergence from the spec's expected layout, which is documented here so it is clearly intentional rather than an oversight. The Docker build context is scoped to `src/` accordingly — `BUILD_CONTEXT=src` in `.env` — which also means the Dockerfile is found automatically without needing a `-f` flag.

## What the image provides

- A two-stage build that keeps the Go toolchain out of the final image entirely
- A `distroless/static` runtime image — no shell, no package manager, nothing an attacker can use
- Non-root execution via the `nonroot` user baked into the distroless image
- BuildKit cache mounts so incremental rebuilds only recompile what changed

## Runtime behaviour

The server listens on `PORT` (defaults to `8080`) and exposes two endpoints:

- `GET /` → `Hello, World!`
- `GET /healthz` → `ok`

## Local development

Copy `.env.example` to `.env` and set your platform before running anything:

```bash
cp .env.example .env
```

The `PLATFORM` value in `.env` controls the build target. Set it to match your deployment target, not your local machine — if you are on Apple Silicon but deploying to x86, keep it as `linux/amd64`.

```bash
./build.sh   # builds and loads the image into your local Docker
./run.sh     # runs the container on port 8080
./verify.sh  # hits / and /healthz to confirm the container is up
```

### Platform and cross-compilation

The Dockerfile is set up for cross-compilation from the start. The builder stage always runs natively on your machine (`$BUILDPLATFORM`), and the Go compiler targets whatever `PLATFORM` you set in `.env` via `GOOS`/`GOARCH`. This means a Mac developer building `linux/amd64` for an x86 server compiles at native speed — no emulation.

This matters when deploying to AWS Graviton (t4g, m7g, c7g instances), which are ARM-based and typically 20–40% cheaper than equivalent x86 instances. Setting `PLATFORM=linux/arm64` in `.env` produces a Graviton-compatible image from any machine without any other changes.

## Dockerfile walk-through

### Builder stage

```dockerfile
# syntax=docker/dockerfile:1.7
FROM --platform=$BUILDPLATFORM golang:1.22-alpine AS builder
```

The parser directive at the top pins the BuildKit frontend to 1.7, which is what unlocks the `--mount=type=cache` syntax used later. Without it, older Docker daemons would silently ignore those cache mounts and every build would start cold.

Alpine is used for the builder rather than the full Debian-based Go image. The Go toolchain dominates the layer size either way, but Alpine cuts the noise. The usual concern with Alpine — that it uses `musl libc` instead of `glibc` — doesn't apply here because `CGO_ENABLED=0` means the binary never links against libc at all.

```dockerfile
COPY app/go.mod app/go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download
```

`go.mod` and `go.sum` are copied before any application source so Docker can cache the dependency download as its own layer. If you change application code without touching dependencies, `go mod download` doesn't run again — it hits the layer cache. The `--mount=type=cache` goes further: it persists the module cache on disk across builds even when the layer cache is invalidated, so previously downloaded modules don't need to be re-fetched.

`go.sum` is currently empty because this service has no external dependencies, but it needs to exist and be committed. The moment a dependency is added via `go get`, `go.sum` gets populated with checksums, and `go mod download` will fail in CI without it.

```dockerfile
COPY app/ ./
```

Source is copied after dependencies, intentionally. Reversing this order would mean any source change busts the `go mod download` cache, defeating the purpose of the split.

```dockerfile
ARG TARGETOS
ARG TARGETARCH
RUN --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH:-amd64} \
    go build -trimpath -ldflags="-s -w" -o /out/server ./main.go
```

`TARGETOS` and `TARGETARCH` are populated automatically by BuildKit from the `--platform` flag and fed into `GOOS`/`GOARCH`, which is how Go's compiler knows to produce a binary for the target rather than the build machine.

`CGO_ENABLED=0` produces a fully static binary with no shared library dependencies. This is what makes it possible to run in `distroless/static`, which contains no libc. The trade-off is that packages with CGO dependencies (certain database drivers, sqlite bindings) won't compile — acceptable for a standard HTTP service.

The `--mount=type=cache` on the Go build cache means only changed packages are recompiled on subsequent builds. On larger codebases this is the difference between a 30-second rebuild and a 3-minute one.

`-trimpath` removes local filesystem paths from the compiled binary. Without it, stack traces embed paths like `/home/username/project/...`, which leaks your build environment layout and makes builds non-reproducible across machines.

`-ldflags="-s -w"` strips the symbol table (`-s`) and DWARF debug information (`-w`) from the binary. This typically reduces binary size by 20–30%. The cost is that you cannot attach a debugger like `delve` to a production build — which is the right trade-off. If you need to debug a production issue, reproduce it locally with these flags removed.

The binary is written to `/out/server`, outside the source tree, so the `COPY` in the next stage has a clean, unambiguous target.

### Runtime stage

```dockerfile
FROM gcr.io/distroless/static-debian12:nonroot AS runtime
```

`distroless/static` contains timezone data, CA certificates, and nothing else — no shell, no package manager, no `curl`. The attack surface in the running container is essentially just the application binary itself. If an attacker achieves code execution, they have no tools to work with.

The `nonroot` variant configures the image to run as UID 65532. This happens at the image level rather than through a `USER` directive, so it can't be accidentally dropped. `debian12` pins the base to a specific Debian release for predictable CVE patching cycles.

The only meaningful operational trade-off is that `docker exec -it <container> /bin/sh` doesn't work — there's no shell to exec into. For Kubernetes deployments, `kubectl debug` with an ephemeral container is the correct approach. For local debugging, run the application directly with `go run` rather than through the container.

```dockerfile
COPY --from=builder /out/server /server
```

This is the only file that makes it into the final image from the build stage. The Go toolchain, source code, module cache, and all intermediate build artefacts are discarded.

```dockerfile
EXPOSE 8080
ENV PORT=8080
```

`EXPOSE` is metadata — it documents intent but doesn't open anything. `ENV PORT=8080` sets the default port the application reads at startup, which makes it overridable at runtime via `docker run -e PORT=9090` without rebuilding the image.

```dockerfile
ENTRYPOINT ["/server"]
```

The array form (exec form) runs the binary directly as PID 1. The string form would spawn `/bin/sh -c /server` first, which doesn't exist in distroless and would crash immediately. Beyond that, PID 1 receives `SIGTERM` from Docker on shutdown — with a shell in the way, that signal often doesn't reach the application, and the container gets force-killed after the timeout instead of shutting down cleanly.

## Design philosophy

Every decision in this Dockerfile is pulled in the same direction: fast builds, small image, minimal attack surface. The main thing given up in exchange is runtime debuggability — you can't shell into the container, and the binary has no debug symbols. That's a deliberate trade-off. Production debugging should come from structured logs and traces built into the application, not from poking around inside a running container.