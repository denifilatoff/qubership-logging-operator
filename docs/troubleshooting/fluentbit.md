# FluentBit — Troubleshooting

## Connection timeout to Graylog in FluentBit

**Symptoms:**

The following errors in FluentBit pod logs appears:

```bash
[2024/04/25 20:54:28] [error] [upstream] connection #-1 to tcp://unavailable:0 timed out after 10 seconds (connection timeout)
[2024/04/25 20:54:29] [ warn] [net] getaddrinfo(host='<graylog_url>', err=12): Timeout while contacting DNS servers
[2024/04/25 20:54:29] [error] [output:gelf:gelf.1] no upstream connections available
```

**How to fix:**

1. Check CPU consumption by FluentBit. Usually the error appears when FluentBit
faced limit of CPU. Increase limit by setting `fluentbit.resources.limits.cpu: "1"`.

2. Add the configuration of network and health checks to FluentBit. ConfigMap `logging-fluentbit` should contain
next parameters:

    ```yaml
      fluent-bit.conf: |
        [SERVICE]
            Flush         5
            HC_Errors_Count 5
            HC_Retry_Failure_Count 5
            HC_Period 5
      output-graylog.conf: |
        [OUTPUT]
            Name     gelf
            # configuration...
            net.connect_timeout 20s
            net.max_worker_connections 35
            net.dns.mode TCP
            net.dns.resolver LEGACY
    ```

3. After updating ConfigMap you should manually delete all FluentBit pods to apply changes.

## FluentBit stuck and stopped sending logs to Graylog

**Symptoms:**

FluentBit stuck and do not send any logs.

**How to fix:**

First of all, check that you upgraded to the latest version of Logging.
If you want to solve problem manually, follow steps below (it is temporary solution):

1. Make sure that you are connected to the Cloud. Scale `logging-operator` deployment to 0 replicas with the
   command:

   ```bash
   kubectl scale -n logging deployment logging-operator --replicas=1
   ```

2. Modify ConfigMap `logging-fluentbit`:

   ```bash
   kubectl edit -n logging cm logging-fluentbit
   ```

   1. Remove from `filter-log-parser.conf` the last lines:

      ```yaml
      [FILTER]
          Name          rewrite_tag
          Match         raw.*
          Rule          $log .*  parsed.$TAG false
          Emitter_Name          raw_parsed
          Emitter_Storage.type  filesystem
          Emitter_Mem_Buf_Limit 10M
      ```

   2. Change in `output-graylog.conf` the line from

      ```yaml
      Match   parsed.**
      ```

      to

      ```yaml
      Match_Regex (raw|parsed).**
      ```

3. The last step is to delete all pods `logging-fluentbit-*`. The pods will be restarted with the last configuration.

## Fluent container restarts after changing ConfigMap

Cross-cutting with FluentD — same reloader. See [FluentD — ConfigMap reload](fluentd.md#fluent-container-restarts-after-changing-configmap).
