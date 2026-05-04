
# Installation Guide

This page provides comprehensive instructions for installing the Qubership Logging Operator in your Kubernetes
or OpenShift environment. The Logging Operator is responsible for deploying and managing various logging components,
including Graylog, FluentBit, FluentD, and Cloud Events Reader. For information about the overall architecture
of the system, see [Architecture](./architecture.md). For configuration details after installation,
see [Configuration](./graylog-configuration.md).

## Table of Contents

* [Installation Guide](#installation-guide)
  * [Table of Contents](#table-of-contents)
  * [Supported Platforms and Compatibility](#supported-platforms-and-compatibility)
    * [Kubernetes compatibility](#kubernetes-compatibility)
    * [Openshift compatibility](#openshift-compatibility)
    * [Public Cloud Provider Support](#public-cloud-provider-support)
      * [Amazon Web Services (AWS)](#amazon-web-services-aws)
      * [Azure](#azure)
      * [Google Cloud](#google-cloud)
  * [Prerequisites](#prerequisites)
    * [System requirements](#system-requirements)
      * [Platform compatibility](#platform-compatibility)
      * [Tools](#tools)
    * [Storage requirements](#storage-requirements)
      * [Supported backends](#supported-backends)
      * [Graylog Persistent Volumes](#graylog-persistent-volumes)
    * [Hardware requirements](#hardware-requirements)
      * [Small](#small)
      * [Medium](#medium)
      * [Large](#large)
      * [Storage capacity planning](#storage-capacity-planning)
    * [Environment preparation](#environment-preparation)
      * [Kubernetes](#kubernetes)
      * [OpenShift](#openshift)
      * [HostPath Persistent Volumes](#hostpath-persistent-volumes)
  * [Installation](#installation)
  * [Configuration parameters](#configuration-parameters)
  * [Post Installation Steps](#post-installation-steps)
    * [Configuring URL whitelist](#configuring-url-whitelist)
  * [Upgrade](#upgrade)
  * [Frequently asked questions](#frequently-asked-questions)
  * [Footnotes](#footnotes)

## Supported Platforms and Compatibility

### Kubernetes compatibility

According to the platform\'s third-party support policy, we now support deployments on Kubernetes N ± 2.

The current recommended Kubernetes version is `1.28.x`, which means we support:

| Kubernetes version     | Compatibility Status (logging-operator 0.48.0) |
| ---------------------- | ---------------------------------------------- |
| `1.25.x`               | Tested                                         |
| `1.26.x`               | Tested                                         |
| `1.28.x` (recommended) | Tested                                         |
| `1.29.x`               | Forward compatibility                          |
| `1.30.x`               | Forward compatibility                          |

**Note:** `Forward compatibility` means that the current version does not use any Kubernetes APIs
scheduled for removal in upcoming Kubernetes releases. All Kubernetes APIs have been verified according to
the official [Deprecated API Migration Guide](https://kubernetes.io/docs/reference/using-api/deprecation-guide/).

### Openshift compatibility

OpenShift 4.x is built on Kubernetes and regularly integrates new Kubernetes releases.
Therefore, its compatibility can be tracked by the underlying Kubernetes version.
To determine which Kubernetes version a specific OpenShift release uses, refer to its release notes.
For example, `OpenShift 4.12` is based on `Kubernetes v1.25.0`,
see the [Release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.12/html/release_notes/ocp-4-12-release-notes).

### Public Cloud Provider Support

| Cloud Provider | Managed OpenSearch  | Graylog Support | Notes                             |
| -------------- | ------------------- | --------------- | --------------------------------- |
| AWS            | ✔ Yes               | ✔ Supported     | Requires minimum hardware specs   |
| Azure          | ✘ No                | N/A             | Only custom marketplace solutions |
| GCP            | ✘ No                | N/A             | Only custom marketplace solutions |

#### Amazon Web Services (AWS)

Supported OpenSearch versions can be found in the [Supported backends](#supported-backends) section.

When using Graylog with `AWS Managed OpenSearch`, you should select an OpenSearch instance flavor
with hardware resources no less than the following:

* CPU - 2 core
* Memory - 4 Gb
* Storage type - SSD

#### Azure

Azure has no officially managed OpenSearch or Elasticsearch. You can find only custom solutions
in the Azure marketplace from other vendors.

#### Google Cloud

Google has no officially managed OpenSearch or Elasticsearch. You can find only custom solutions
in the Google marketplace from other vendors.

[Back to TOC](#table-of-contents)

## Prerequisites

### System requirements

#### Platform compatibility

| Requirement       | Version/Specification                                | Notes                                                 |
| ----------------- | ---------------------------------------------------- | ----------------------------------------------------- |
| Kubernetes        | 1.25.x, 1.26.x, 1.28.x (recommended), 1.29.x, 1.30.x | Tested <1.29, Forward-compatible (API verified) ≥1.29 |
| OpenShift         | 4.10+                                                | Based on Kubernetes version                           |

#### Tools

* kubectl/oc CLI (1.21+)
* Helm (3.0+)
* Container Runtime (Docker, cri-o, containerd)

### Storage requirements

#### Supported backends

When deploying Graylog in the cloud, you should use only the OpenSearch or Elasticsearch versions specified below.
<!-- markdownlint-disable line-length -->
| Graylog version | Elasticsearch versions    | OpenSearch versions     |
| --------------- | ------------------------- | ----------------------- |
| Graylog 4.x     | `6.8.x`, `7.7.x - 7.10.x` | `1.x *`                 |
| Graylog 5.x     | `6.8.x`, `7.10.2`         | `1.x`, `2.0.x-2.5.x **` |
<!-- markdownlint-enable line-length -->
where:

* `*` - for Graylog 4.x OpenSearch 1.x must be deployed and run **with** compatibility mode
* `**` - for Graylog 5.x OpenSearch 2.x must be deployed and run **without** compatibility mode

**Note:** Graylog may not work properly with OpenSearch/Elasticsearch versions other than specified in the table above.

Information about compatibility mode:

* [Moving from open-source Elasticsearch to OpenSearch](https://opensearch.org/blog/moving-from-opensource-elasticsearch-to-opensearch/)

#### Graylog Persistent Volumes

Graylog requires two Persistent Volumes (PVs):

* for the built-in MongoDB, used to store Graylog configuration data.

* for the journald, used as a cache between Graylog input and message processing.

NFS-like storage **is not supported!** This means you shouldn’t use PV and dynamic storage provisioners
with NFS, AWS EFS, Azure File, or any other NFS-based storage.

For Graylog `journald` storage, please select storage with sufficient throughput and speed.
Graylog may perform a high number of read and write operations on `journald` under heavy load.
Refer to the [Hardware requirements](#hardware-requirements) section for more details.

[Back to TOC](#table-of-contents)

### Hardware requirements

The following table shows the typical throughput/HWE ratio:

Graylog:

<!-- markdownlint-disable line-length -->
| Input logs, msg/sec            | <1000  | 1000-3000 | 5000-7500  | 7500-10000 | 10000-15000 | 15000-25000 | >25000 |
| ------------------------------ | ------ | --------- | ---------- | ---------- | ----------- | ----------- | ------ |
| CPU                            | 4      | 6         | 8          | 8          | 12          | 12          | 16+    |
| Graylog heap, Gb               | 1      | 2         | 2          | 4          | 4           | 6           | 6      |
| Total RAM, Gb                  | 6      | 8         | 12         | 16         | 16          | 22          | 24+    |
| HDD volume, 1/day (very rough) | <80 Gb | 80-200 Gb | 300-600 Gb | 600-800 Gb | 0.8-1 Tb    | 1-2 Tb      | 2+ Tb  |
| Disk speed, Mb/s               | 2      | 5         | 10         | 20         | 30          | 50          | 100    |
<!-- markdownlint-enable line-length -->

OpenSearch/Elasticsearch:

<!-- markdownlint-disable line-length -->
| Input logs, msg/sec            | <1000  | 1000-3000 | 5000-7500  | 7500-10000 | 10000-15000 | 15000-25000 | >25000                     |
| ------------------------------ | ------ | --------- | ---------- | ---------- | ----------- | ----------- | -------------------------- |
| CPU                            | 4      | 6         | 8          | 8          | 12          | 12          | 16+                        |
| ES heap, Gb                    | 2      | 4         | 8          | 8          | 8           | 12          | 16+ (but less that ~32 GB) |
| Total RAM, Gb                  | 6      | 8         | 12         | 16         | 16          | 22          | 24+                        |
| HDD volume, 1/day (very rough) | <80 Gb | 80-200 Gb | 300-600 Gb | 600-800 Gb | 0.8-1 Tb    | 1-2 Tb      | 2+ Tb                      |
| Disk speed, Mb/s               | 2      | 5         | 10         | 20         | 30          | 50          | 100                        |
<!-- markdownlint-enable line-length -->

#### Small

Resources in this profile were calculated for the average load `<= 3000` messages per second.

**Warning!** All the resources listed below may require tuning for your specific environment,
as different environments can have varying log types (e.g., average message size), retention periods, and other factors.
Please use these recommendations carefully, adjust them as needed,
and it is highly recommended to run SVT for Logging before deploying in production.

| Component            | CPU Requests | Memory Requests | CPU Limits | Memory Limits |
| -------------------- | ------------ | --------------- | ---------- | ------------- |
| Graylog              | `500m`       | `1500Mi`        | `1000m`    | `1500Mi`      |
| FluentD              | `100m`       | `128Mi`         | `500m`     | `512Mi`       |
| FluentBit Forwarder  | `100m`       | `128Mi`         | `300m`     | `256Mi`       |
| FluentBit Aggregator | `300m`       | `256Mi`         | `500m`     | `1Gi`         |
| Cloud Events Reader  | `50m`        | `128Mi`         | `100m`     | `128Mi`       |

**Important!** When deploying Graylog in the cloud, you need to include the resource requirements
for the OpenSearch cluster (recommended) or a single OpenSearch instance that will be deployed in the cloud.
Please refer to the OpenSearch documentation for details on hardware requirements.

#### Medium

Resources in this profile were calculated for the average load between `> 3000` and `<= 10000` messages per second.

**Warning!** All the resources listed below may require tuning for your specific environment, as different environments
can have varying log types (e.g., average message size), retention periods, and other factors.
Please use these recommendations carefully, adjust them as needed,
and it is highly recommended to run SVT for Logging before deploying in production.

| Component            | CPU Requests | Memory Requests | CPU Limits | Memory Limits |
| -------------------- | ------------ | --------------- | ---------- | ------------- |
| Graylog              | `1000m`      | `2Gi`           | `3000m`    | `4Gi`         |
| FluentD              | `100m`       | `256Mi`         | `1000m`    | `1Gi`         |
| FluentBit Forwarder  | `100m`       | `128Mi`         | `500m`     | `512Mi`       |
| FluentBit Aggregator | `500m`       | `512Mi`         | `1000m`    | `2Gi`         |
| Cloud Events Reader  | `50m`        | `128Mi`         | `300m`     | `256Mi`       |

**Important!** When deploying Graylog in the cloud, you need to include the resource requirements
for the OpenSearch cluster (recommended) or a single OpenSearch instance that will be deployed in the cloud.
 Please refer to the OpenSearch documentation for details on hardware requirements.

#### Large

Resources in this profile were calculated for the average load `> 10000` messages per second.

**Warning!** All the resources listed below may require tuning for your specific environment, as different environments
can have varying log types (e.g., average message size), retention periods, and other factors.
Please use these recommendations carefully, adjust them as needed,
and it is highly recommended to run SVT for Logging before deploying in production.

| Component            | CPU Requests | Memory Requests | CPU Limits | Memory Limits |
| -------------------- | ------------ | --------------- | ---------- | ------------- |
| Graylog              | `2000m`      | `4Gi`           | `6000m`    | `8Gi`         |
| FluentD              | `500m`       | `512Mi`         | `1000m`    | `1536Mi`      |
| FluentBit Forwarder  | `100m`       | `256Mi`         | `1000m`    | `1024Mi`      |
| FluentBit Aggregator | `500m`       | `1Gi`           | `1000m`    | `2Gi`         |
| Cloud Events Reader  | `100m`       | `128Mi`         | `300m`     | `512Mi`       |

**Important!** When deploying Graylog in the cloud, you need to include the resource requirements
for the OpenSearch cluster (recommended) or a single OpenSearch instance that will be deployed in the cloud.
Please refer to the OpenSearch documentation for details on hardware requirements.

#### Storage capacity planning

To calculate the total storage size required for logs from your environment,
please refer to the [Storage capacity planning](./storage-capacity-planning.md).

[Back to TOC](#table-of-contents)

### Environment preparation

#### Kubernetes

To deploy Logging on Kubernetes or OpenShift, you must have at least namespace administrator privileges.
Your permissions should include at minimum the following:

```yaml
kind: Role
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  namespace: <logging-namespace>
  name: deploy-user-role
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
```

**Note:** This is not the role that you have to create.
It\'s just an example showing the minimal set of permissions required.

For Kubernetes 1.25+, you **must** deploy Logging using `privileged` PSS. The logging agents require using
`hostPath` PVs to mount directories with logs from Kubernetes/OpenShift nodes.

Before deploying, please make sure that your namespace has the following labels:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: <logging_namespace_name>
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/enforce-version: latest
```

#### OpenShift

To deploy in OpenShift you need to:

* Run FluentBit/FluentD in `privileged` mode
* Create Security Context Constraints (SCC)

Run FluentBit/FluentD in `privileged` mode is mandatory.
Otherwise, the logging agents cannot access log files on the nodes.

By default, OpenShift store log files with permissions `600` and `root` ownership.

Therefore, in values.yaml you should set the following parameter to true:

```yaml
fluentbit:
  securityContextPrivileged: true
```

or

```yaml
fluentd:
  securityContextPrivileged: true
```

[Back to TOC](#table-of-contents)

#### HostPath Persistent Volumes

**Note:** When deploying Graylog with a `hostPath PV`, you **must** correctly set the `nodeSelector` parameter
to unambiguously determine the node on which Graylog will be installed.

You need to perform some preparatory steps if you want to deploy Graylog (with MongoDB inside Graylog)
on a hostPath Persistent Volume (PV).

You can learn more about hostPath PVs and their limitations in the official documentation:
[https://kubernetes.io/docs/concepts/storage/volumes/#hostpath](https://kubernetes.io/docs/concepts/storage/volumes/#hostpath)

In order to use a `hostPath` PV, you need to grant permissions for the directories inside the PV.

First, when deploying on OpenShift, the platform assigns a range of UIDs by default for running pods
(and the containers inside them) in the namespace.
If you plan to deploy on Kubernetes, you can skip this step.

Therefore, the first step is to configure a single UID that OpenShift will use.
You can do this by running the following command:

```bash
oc annotate --overwrite namespace <logging_namespace> openshift.io/sa.scc.uid-range=<uid>/<uid>
```

for example:

```bash
oc annotate --overwrite namespace logging openshift.io/sa.scc.uid-range=1100/1100
```

Second, you need to create the directories, set their ownership, and grant the necessary permissions.
In our example, let's assume that the hostPath PV is created at the following path:

```bash
/mnt/graylog-0
```

and you configure `UID = 1100`.

So you need to execute the following commands:

```bash
mkdir /mnt/graylog-0/config
chown -R 1100:1100 /mnt/graylog-0
chmod 777 /mnt/graylog-0
chmod 666 /mnt/graylog-0/config
```

If you are using an OS with SELinux, you may need to set the SELinux security context:

```bash
chcon -R unconfined_u:object_r:container_file_t:s0 /mnt/graylog-0
```

[Back to TOC](#table-of-contents)

## Installation

The Logging Operator is deployed as a Helm chart, which installs and configures Logging-operator, Graylog, FluentBit,
FluentD, Cloud Events Reader, and related resources. It can be deployed on Kubernetes, OpenShift,
or compatible managed Kubernetes services.

Before installation, make sure your platform is listed in the [Supported platforms](#supported-platforms-and-compatibility)
and meets all [Requirements](#prerequisites).
Also, complete all necessary steps from the [Environment preparation](#environment-preparation) section.

Ensure that the selected OpenSearch instance is operational and provisioned with sufficient resources
to handle Graylog’s load (when deploying Graylog in the cloud).

Installation consists of the following steps:

1. Obtain the helm chart.

   ```sh
   git clone https://github.com/Netcracker/qubership-logging-operator.git
   cd logging-operator/charts/logging-operator
   ```

2. Prepare values.yaml with target configuration.
   You can refer to [Configuration parameters](#configuration-parameters) section for details.

   Minimal values file example:

   ```yaml
   skipMetricsService: false
   containerRuntimeType: <container_runtime>
   graylog:
     install: true
     mongoStorageClassName: <storage_class>
     graylogStorageClassName: <storage_class>
     host: http://graylog.demo.qubership.org
     initContainerDockerImage: alpine:3.17.2
     elasticsearchHost: http://<opensearch_user>:<opensearch_password>@<opensearch_host>:<opensearch_port>
     indexShards: "1"
     indexReplicas: "0"
   fluentbit:
     install: true
     configmapReload:
       dockerImage: ghcr.io/jimmidyson/configmap-reload:v0.13.1
     graylogHost: <graylog_host>
     graylogPort: 12201
   fluentd:
     install: false
   ```

   where:

   * `container_runtime`: the container runtime used by your platform: `docker`, `cri-o` or `containerd`
   * `storage_class`: the storage class for the PVC which will be requested during installation.
   * `opensearch_user` and `opensearch_password`: credentials for OpenSearch user
   * `opensearch_host`: the address of OpenSearch (usually `opensearch.opensearch`)
   * `opensearch_port`: opensearch port (default `9200`)

3. Install the Helm chart from the local repository.

   ```sh
   helm upgrade --install logging-service ./ \
       -n <your_namespace> \
       -f <your_values_yaml> \
       --create-namespace
   ```

   where:

   * `your_namespace`: the target namespace where Logging will be deployed
   * `your_values_yaml`: the path to the values file prepared in step 2.

   You can override values by passing to helm install command parameter after --set directive, e.g.:

   ```sh
   helm upgrade --install logging-service ./ \
       -n <your_namespace> \
       -f <your_values_yaml> \
       --create-namespace \
       --set operatorImage=ghcr.io/netcracker/qubership-logging-operator:main
   ```

4. Verify the deployment.

   ```sh
   kubectl get pods -n logging
   ```

   ```sh
   NAME                                               READY     STATUS             RESTARTS   AGE
   events-reader-64d6698bb8-tfp5l                     1/1       Running            0          1m
   logging-fluentd-sh86l                              1/1       Running            0          1m
   logging-operator-7b586d8767-lpwzl          1/1       Running            0          1m
   ```

   All pods should enter the `Running` and `Ready` state within a few minutes.

5. Additionally, you can verify logging functionality by reviewing the integration test results (if available)
   in the selected resource for status writing.

[Back to TOC](#table-of-contents)

## Configuration parameters

<!-- markdownlint-disable line-length -->
| Level                     | Description                                                                                                 | Detailed parameters link                                                          |
| ------------------------- | ----------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| `root`                    | Common section containing some generic parameters                                                           | [Root](./installation-parameters.md#root)                                         |
| `graylog`                 | Contains parameters to enable and configure the Graylog deployment in the cloud                             | [Graylog](./installation-parameters.md#graylog)                                   |
| `graylog.tls`             | TLS configuration for Graylog WebUI and default Inputs                                                      | [Graylog TLS](./installation-parameters.md#graylog-tls)                           |
| `graylog.opensearch`      | Contains the parameters required for connection to `Opensearch`                                             | [OpenSearch](./installation-parameters.md#opensearch)                             |
| `graylog.contentPacks`    | Contains Graylog content packs parameters                                                                   | [ContentPacks](./installation-parameters.md#contentpacks)                         |
| `graylog.streams`         | Contains parameters to enable, disable or modify the retention strategy for the default Graylog's Streams   | [Graylog Streams](./installation-parameters.md#graylog-streams)                   |
| `graylog.authProxy`       | Includes parameters to enable and configure the Graylog authentication proxy                                | [Graylog Auth Proxy](./installation-parameters.md#graylog-auth-proxy)             |
| `graylog.authProxy.ldap`  | Contains parameters to configure LDAP provider for `graylog-auth-proxy`                                     | [Graylog Auth Proxy LDAP](./installation-parameters.md#graylog-auth-proxy-ldap)   |
| `graylog.authProxy.oauth` | Contains parameters to configure OAuth provider for `graylog-auth-proxy`                                    | [Graylog Auth Proxy OAuth](./installation-parameters.md#graylog-auth-proxy-oauth) |
| `fluentbit`               | Contains parameters to enable and configure FluentBit logging agent                                         | [FluentBit](./installation-parameters.md#fluentbit)                               |
| `fluentbit.aggregator`    | Contains parameters to enable and configure the FluentBit aggregator                                        | [FluentBit Aggregator](./installation-parameters.md#fluentbit-aggregator)         |
| `fluentbit.tls`           | TLS Configuration for FluentBit Graylog Output                                                              | [FluentBit TLS](./installation-parameters.md#fluentbit-tls)                       |
| `fluentd`                 | Contains parameters to configure FluentD logging agent                                                      | [FluentD](./installation-parameters.md#fluentd)                                   |
| `fluentd.tls`             | Contains parameters to configure TLS for FluentD Graylog Output                                             | [FluentD TLS](./installation-parameters.md#fluentd-tls)                           |
| `cloudEventsReader`       | Contains parameters to configure cloud-events-reader                                                        | [Cloud Events Reader](./installation-parameters.md#cloud-events-reader)           |
| `integrationTests`        | Contains parameters to enable integration tests that can verify deployment of Graylog, FluentBit or FluentD | [Integration tests](./installation-parameters.md#integration-tests)               |
<!-- markdownlint-enable line-length -->
## Post Installation Steps

### Configuring URL whitelist

After successful deploy you can configure URL whitelist.
There are certain components in Graylog which will perform outgoing HTTP requests. Among those, are event notifications
and HTTP-based data adapters.
Allowing Graylog to interact with resources using arbitrary URLs may pose a security risk. HTTP requests are executed
from Graylog servers and might therefore be able to reach more sensitive systems than an external user would have
access to, including AWS EC2 metadata, which can contain keys and other secrets, Elasticsearch and others.
It is therefore advisable to restrict access by explicitly whitelisting URLs which are considered safe. HTTP requests
will be validated against the Whitelist and are prohibited if there is no Whitelist entry matching the URL.

The Whitelist configuration is located at `System/Configurations/URL Whitelist`. The Whitelist is enabled by default.

If the security implications mentioned above are of no concern, the Whitelist can be completely disabled.
When disabled, HTTP requests will not be restricted.

Whitelist entries of type `Exact match` contain a string which will be matched against a URL by direct comparison.
If the URL is equal to this string, it is considered to be whitelisted.

Whitelist entries of type `Regex` contain a regular expression. If a URL matches the regular expression, the URL is
considered to be whitelisted. Graylog uses the Java Pattern class to evaluate regular expressions.

[Back to TOC](#table-of-contents)

## Upgrade

## Frequently asked questions

## Footnotes
