ARG ALPINE_IMAGE=docker.io/library/alpine:3.24.1
ARG GOLANG_IMAGE=docker.io/library/golang:1.26.4-alpine3.24
# renovate: datasource=github-tags depName=containernetworking/plugins
ARG VERSION=1.9.1 REVISION=adc3e6b5b581638afbd194cf2e9319ecbb0151a1


FROM --platform=$BUILDPLATFORM $GOLANG_IMAGE AS sources
RUN apk add --no-cache git
ENV GOTOOLCHAIN=local GOTELEMETRY=off
WORKDIR /go/src/containernetworking-plugins
ARG REVISION
RUN git -c advice.detachedHead=false clone --revision $REVISION --depth=1 https://github.com/containernetworking/plugins.git .


FROM sources AS bins
ARG TARGETARCH SOURCE_DATE_EPOCH VERSION
RUN --mount=type=cache,id=containernetworking-plugins-gocache-$TARGETARCH,target=/root/.cache/go-build \
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
COPY --from=bins /go/src/containernetworking-plugins/bin/ /opt/cni/bin/
ENTRYPOINT ["/bin/cni-node"]
CMD ["install"]
