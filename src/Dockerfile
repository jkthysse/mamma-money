# syntax=docker/dockerfile:1.7
FROM --platform=$BUILDPLATFORM golang:1.22-alpine AS builder

WORKDIR /src/app

# Copy module metadata first so dependency download can be cached.
COPY app/go.mod app/go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

# Copy the application source after dependencies.
COPY app/ ./

ARG TARGETOS
ARG TARGETARCH
RUN --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH:-amd64} \
    go build -trimpath -ldflags="-s -w" -o /out/server ./main.go

FROM gcr.io/distroless/static-debian12:nonroot AS runtime

COPY --from=builder /out/server /server

EXPOSE 8080
ENV PORT=8080

ENTRYPOINT ["/server"]
