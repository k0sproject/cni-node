ARG \
  ALPINE_IMAGE=docker.io/library/alpine:3.22.7 \
  GOLANG_IMAGE=docker.io/library/golang:1.26.10-alpine3.23 \
  VERSION=1.8.0 \
  HASH=f0510b4452dda4b08d4b088d02e005ac507cb96fb7247b4422ae591286390369

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
  && for p in /run/patches/*.patch; do \
     [ "$p" != '/run/patches/*.patch' ] || { echo No patches found.; break; }; \
    echo Applying "$p" >&2; \
    patch -p1 <"$p"; \
  done

# Re-vendor the dependencies, as the patches may have touched go.mod/go.sum
RUN go mod vendor


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
