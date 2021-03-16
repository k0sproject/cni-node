FROM alpine:3.13
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG CNI_PLUGINS_VERSION=v0.9.1

RUN apk upgrade --no-cache --update && \
    apk add --no-cache gettext curl

RUN mkdir -p /opt/cni/bin

RUN curl -o cni.tgz -sSLf "https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/cni-plugins-linux-${TARGETPLATFORM##*/}-${CNI_PLUGINS_VERSION}.tgz" && \
    tar zxvf cni.tgz -C /opt/cni/bin && \
    rm -rf cni.tgz

COPY src /bin
ENTRYPOINT ["/bin/cni-node"]
CMD ["install"]