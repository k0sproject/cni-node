ARG \
  ALPINE_IMAGE=docker.io/library/alpine:3.22.2 \
  GOLANG_IMAGE=docker.io/library/golang:1.25.2-alpine \
  VERSION=1.8.0 \
  HASH=f0510b4452dda4b08d4b088d02e005ac507cb96fb7247b4422ae591286390369

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
