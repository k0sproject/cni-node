# CNI Node

[![License: Apache-2.0][Apache 2.0 Badge]][Apache 2.0]
[![GitHub Release Badge]][GitHub Releases]
[![CNI Plugins Badge]][CNI Plugins Release]

A [Docker] image for installing and configuring [CNI Plugins] and [Multus CNI]
on a node. For example on a [Kubernetes] one.

* [Usage](#usage)
  * [Install CNI](#install-cni)
    * [Binaries](#binaries)
* [Usage in Kubernetes](#usage-in-kubernetes)
  * [Simple Example](#simple-example)
* [License](#license)


Work based on https://github.com/openvnf/cni-node; We've simplified the setup very much, and thus "broken" any backwards compatibility so hence a no-fork repo for this.

## Usage

Run without arguments to see usage:

```
$ docker run --rm quay.io/k0sproject/cni-node:latest
```

Print list of available CNI plugins:

```
$ docker run --rm quay.io/k0sproject/cni-node:latest list
```

### Install CNI

The following components can be installed:

* CNI plugins binaries

#### Binaries

CNI plugins binaries are baked into the image and installed to the
"/host/opt/cni/bin" directory:

```
$ docker run --rm \
    -v /opt/cni/bin:/host/opt/cni/bin \
    quay.io/openvnf/cni-node install --plugins=flannel,ipvlan
```

Will install specified plugins to hosts "/opt/cni/bin".


## Usage in Kubernetes

One of the advantages in using CNI Node with Kubernetes is ability to
incorporate the [Kube Watch] project for tracking changes automatically applying
them. We will start from a simple example and get back to the Kube Watch based
one later on.

### Simple-ish Example

An example with kube-router where cni-node container is used as an `initContainer` to push the CNI bins into the node:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  labels:
    k8s-app: kube-router
    tier: node
  name: kube-router
  namespace: kube-system
spec:
  selector:
    matchLabels:
      k8s-app: kube-router
      tier: node
  template:
    metadata:
      labels:
        k8s-app: kube-router
        tier: node
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
    spec:
      priorityClassName: system-node-critical
      serviceAccountName: kube-router
      initContainers:
        - name: install-cni-bins
          image: docker.io/jnummelin/cni-node:latest
          imagePullPolicy: Always
          args:
            - install
          volumeMounts:
          - name: cni-bin
            mountPath: /host/opt/cni/bin
        - name: install-cniconf
          image: docker.io/cloudnativelabs/kube-router
          imagePullPolicy: Always
          command:
          - /bin/sh
          - -c
          - set -e -x;
            if [ ! -f /etc/cni/net.d/10-kuberouter.conflist ]; then
              if [ -f /etc/cni/net.d/*.conf ]; then
                rm -f /etc/cni/net.d/*.conf;
              fi;
              TMP=/etc/cni/net.d/.tmp-kuberouter-cfg;
              cp /etc/kube-router/cni-conf.json ${TMP};
              mv ${TMP} /etc/cni/net.d/10-kuberouter.conflist;
            fi
          volumeMounts:
          - mountPath: /etc/cni/net.d
            name: cni-conf-dir
          - mountPath: /etc/kube-router
            name: kube-router-cfg
      hostNetwork: true
      tolerations:
      - effect: NoSchedule
        operator: Exists
      - key: CriticalAddonsOnly
        operator: Exists
      - effect: NoExecute
        operator: Exists
      volumes:
      - name: lib-modules
        hostPath:
          path: /lib/modules
      - name: cni-conf-dir
        hostPath:
          path: /etc/cni/net.d
      - name: cni-bin
        hostPath:
          path: /opt/cni/bin
          type: DirectoryOrCreate
      - name: kube-router-cfg
        configMap:
          name: kube-router-cfg
      - name: xtables-lock
        hostPath:
          path: /run/xtables.lock
          type: FileOrCreate
      containers:
      - name: kube-router
        image: docker.io/cloudnativelabs/kube-router
        imagePullPolicy: Always
        args:
        - "--run-router=true"
        - "--run-firewall=true"
        - "--run-service-proxy=false"
        - "--bgp-graceful-restart=true"
        - "--metrics-port=8080"
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        - name: KUBE_ROUTER_CNI_CONF_FILE
          value: /etc/cni/net.d/10-kuberouter.conflist
        livenessProbe:
          httpGet:
            path: /healthz
            port: 20244
          initialDelaySeconds: 10
          periodSeconds: 3
        resources:
          requests:
            cpu: 250m
            memory: 250Mi
        securityContext:
          privileged: true
        volumeMounts:
        - name: lib-modules
          mountPath: /lib/modules
          readOnly: true
        - name: cni-conf-dir
          mountPath: /etc/cni/net.d
        - name: xtables-lock
          mountPath: /run/xtables.lock
          readOnly: false

```

<!-- Links -->

[RBAC]: https://kubernetes.io/docs/reference/access-authn-authz/rbac
[Docker]: https://docs.docker.com
[DaemonSet]: https://kubernetes.io/docs/concepts/workloads/controllers/daemonset
[Kubernetes]: https://kubernetes.io
[CNI Plugins]: https://github.com/containernetworking/plugins
[CNI Node Docker Image]: Dockerfile

<!-- Badges -->

[Apache 2.0]: https://opensource.org/licenses/Apache-2.0
[Apache 2.0 Badge]: https://img.shields.io/badge/License-Apache%202.0-yellowgreen.svg?style=flat-square
[GitHub Releases]: https://github.com/k0sproject/cni-node/releases
[GitHub Release Badge]: https://img.shields.io/github/release/k0sproject/cni-node/all.svg?style=flat-square
[CNI Plugins Release]: https://github.com/containernetworking/plugins/releases/tag/v0.9.1
