ARG \
  ALPINE_IMAGE=docker.io/library/alpine:3.21.3 \
  GOLANG_IMAGE=docker.io/library/golang:1.24.2-alpine \
  VERSION=1.7.1 \
  HASH=95b639f8ccbb714da98e331ef8813f790d447fce5417f2f8a575f3c62bfb1474

FROM --platform=$BUILDPLATFORM $GOLANG_IMAGE AS bins
ARG VERSION HASH

RUN wget https://github.com/containernetworking/plugins/archive/refs/tags/v${VERSION}.tar.gz \
  && { echo "${HASH} *v${VERSION}.tar.gz" | sha256sum -c -; } \
  && tar xf "v${VERSION}.tar.gz" -C /go \
  && rm -- "v${VERSION}.tar.gz"

WORKDIR /go/plugins-$VERSION

ARG TARGETPLATFORM
RUN set -x \
  && apk add bash \
  && mkdir -p /opt/stage/usr/local/bin \
  && case "${TARGETPLATFORM-~}" in \
    linux/amd64) export GOARCH=amd64 ;; \
    linux/arm64) export GOARCH=arm64 ;; \
    linux/arm/v7) export GOARCH=arm ;; \
    linux/riscv64) export GOARCH=riscv64 ;; \
    ~);; \
    *) echo Unsupported target platform: "$TARGETPLATFORM" >&2; exit 1;; \
  esac \
  && CGO_ENABLED=0 ./build_linux.sh -trimpath -buildvcs=false \
    -ldflags "-s -w -extldflags -static -X github.com/containernetworking/plugins/pkg/utils/buildversion.BuildVersion=v$VERSION"


FROM $ALPINE_IMAGE AS busybox
RUN apk add busybox-static


FROM $ALPINE_IMAGE AS baselayout
COPY --from=busybox /bin/busybox.static /bin/busybox
RUN /bin/busybox --install
COPY src/cni-node /bin/cni-node


FROM scratch
COPY --from=baselayout / /
ARG VERSION
COPY --from=bins /go/plugins-$VERSION/bin/ /opt/cni/bin/
ENTRYPOINT ["/bin/cni-node"]
CMD ["install"]
