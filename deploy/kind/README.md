# Local kind deployment

## Prereqs

```bash
brew install kind helm helmfile
helm plugin install https://github.com/databus23/helm-diff --verify=false
```

## Install

```bash
cp deploy/kind/.env.example deploy/kind/.env
# edit deploy/kind/.env — set CLUSTER_NAME and BACKEND (graylog | victorialogs)

kind create cluster --name "$(grep ^CLUSTER_NAME deploy/kind/.env | cut -d= -f2)"

set -a && source deploy/kind/.env && set +a
helmfile -f deploy/kind/helmfile.yaml.gotmpl apply
```

> First `apply` with `BACKEND=graylog` pulls a ~1.5GB OpenSearch image — give it 30–40 min on a fresh node.

## Switch backend

```bash
# tear down current backend, edit BACKEND in deploy/kind/.env, then apply again
set -a && source deploy/kind/.env && set +a
helmfile -f deploy/kind/helmfile.yaml.gotmpl destroy

# edit BACKEND, source again, apply
helmfile -f deploy/kind/helmfile.yaml.gotmpl apply
```

## Uninstall

```bash
set -a && source deploy/kind/.env && set +a
helmfile -f deploy/kind/helmfile.yaml.gotmpl destroy
kind delete cluster --name "$CLUSTER_NAME"
```
