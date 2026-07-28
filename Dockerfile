ARG \
  ALPINE_IMAGE=docker.io/library/alpine:3.24.1 \
  GOLANG_IMAGE=docker.io/library/golang:1.26.4-alpine3.24 \
  VERSION=1.9.1 \
  HASH=34bd82d47e981940751619c9cc44c095bb90bfcaf8d71865cbb822c37690a764

FROM --platform=$BUILDPLATFORM $GOLANG_IMAGE AS sources
RUN apk add --no-cache patch
ENV GOTOOLCHAIN=local GOTELEMETRY=off
WORKDIR /go/src/containernetworking-plugins
ARG VERSION HASH
RUN --mount=source=files/patches,target=/run/patches,ro \
  --mount=type=tmpfs,target=/tmp \
  set -euo pipefail \
  && wget -qO /tmp/sources.tar.gz https://github.com/containernetworking/plugins/archive/refs/tags/v$VERSION.tar.gz \
  && { echo $HASH /tmp/sources.tar.gz | sha256sum -c -; } || { sha256sum /tmp/sources.tar.gz; exit 1; } \
  && tar xf /tmp/sources.tar.gz --strip-components=1 \
  && for p in /run/patches/*; do \
    echo Applying "$p" >&2; \
    patch -p1 <"$p"; \
  done


FROM sources AS bins
ARG TARGETARCH SOURCE_DATE_EPOCH
RUN --mount=type=cache,id=calico-gocache-$TARGETARCH,target=/root/.cache/go-build \
  --network=none \
  CGO_ENABLED=0 GOARCH=$TARGETARCH ./build_linux.sh -trimpath -buildvcs=false \
    -ldflags "-s -w -extldflags -static -X github.com/containernetworking/plugins/pkg/utils/buildversion.BuildVersion=v$VERSION"


FROM $ALPINE_IMAGE AS busybox
RUN apk add busybox-static


FROM $ALPINE_IMAGE AS baselayout
COPY --from=busybox /bin/busybox.static /bin/busybox
RUN /bin/busybox --install
COPY src/cni-node /bin/cni-node


FROM scratch
LABEL org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.source="https://github.com/k0sproject/cni-node"
COPY --from=baselayout / /
ARG VERSION
COPY --from=bins /go/src/containernetworking-plugins/bin/ /opt/cni/bin/
ENTRYPOINT ["/bin/cni-node"]
CMD ["install"]
