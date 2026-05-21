# FluentD — Troubleshooting

## FluentD worker killed and restart with SIGKILL

**Symptoms:**

* In FluentD logs can be found the similar logs

    ```bash
    2024-05-14 10:14:23 +0000 [error]: Worker 1 exited unexpectedly with signal SIGKILL
    2024-05-14 10:14:25 +0000 [info]: #1 init workers logger path=nil rotate_age=nil rotate_size=nil
    ```

* After restart FluentD use a lot of read DiskIO operations and throughput
* The `dmesg` logs from Kubernetes node contains message about OOM for `ruby` process

**Root cause:**

FluentD inside the container run more than 1 process. Usually it run 3 ruby processes:

* 1 supervisor process that manage other FluentD processes
* 2 worker processes, for `#0` and `#1` workers

Worker `#1` collect, process, and send logs. It has a buffer that in almost all FluentD versions
was hardcoded in `1Gb`.

If FluentD has a memory limit `1Gi` so it just can't fit all content of the buffer. As result, the worker `#1`
can be killed by OOMKiller and restarted by supervisor process.

**How to fix:**

There are two solutions that exist to fix this issue:

* Either need increase the FluentD memory limit till `1500Mi` or to `2Gi`
* Or need to decrease the buffer size to value less than `1Gb`, for example to `512Mb`

    ```yaml
    <store ignore_error>
      @type gelf
      @log_level warn
      host "#{ENV['GRAYLOG_HOST']}"
      port "#{ENV['GRAYLOG_PORT']}"
      ...
      retry_wait 1s
      <buffer>
        total_limit_size 512Mb
      </buffer>
    </store>
    ```

## FluentD generate a high DiskIO read load

**Symptoms:**

* FluentD use a lot of read DiskIO operations and throughput
* In FluentD logs can be found the similar logs

    ```bash
    2024-05-14 10:14:23 +0000 [error]: Worker 1 exited unexpectedly with signal SIGKILL
    2024-05-14 10:14:25 +0000 [info]: #1 init workers logger path=nil rotate_age=nil rotate_size=nil
    ```

**How to fix:**

Most probably it's a problem described in [FluentD worker killed and restart with SIGKILL](#fluentd-worker-killed-and-restart-with-sigkill).
So please refer to it to check root cause and how to fix it.

## FluentD failed to flush buffer, data too big

**Symptoms:**

* In FluentD logs can be found the similar logs

    ```bash
    2024-02-13 11:46:42 +0000 [warn]: #1 failed to flush the buffer. error_class="ArgumentError" error="Data too big (514737 bytes), would create more than 128 chunks!" plugin_id="object:cb5c"
    2024-02-13 11:46:42 +0000 [warn]: #1 got unrecoverable error in primary and no secondary error_class=ArgumentError error="Data too big (514737 bytes), would create more than 128 chunks!"
    ```

**Root cause:**

The error can be reproduced if you send logs to Graylog using input with UDP protocol.
According to [official documentation](https://go2docs.graylog.org/5-0/getting_in_log_data/gelf.html?#GELFviaUDP)
related to GELF there are restrictions:

```bash
UDP datagrams are limited to a size of 65536 bytes. Some Graylog components are limited to processing up to 8192 bytes.
```

```bash
All chunks **MUST** arrive within 5 seconds or the server will discard all chunks that have arrived or
are in the process of arriving. A message **MUST NOT** consist of more than 128 chunks.
```

There was FluentD [issue](https://github.com/fluent/fluentd/issues/3651) on GitHub also.

To send logs to Graylog we use output plugin [`fluent-plugin-gelf-hs`](https://github.com/hotschedules/fluent-plugin-gelf-hs)
that uses Ruby module [`gelf-rb`](https://github.com/graylog-labs/gelf-rb).
The gelf-hs library creates the Notifier from the `gelf` using the "WAN" network type [see source code](
https://github.com/hotschedules/fluent-plugin-gelf-hs/blob/master/lib/fluent/plugin/out_gelf.rb#L52).
It means that the `max chunk size` should be set as `1420 (bytes)` [see source code](
https://github.com/graylog-labs/gelf-rb/blob/master/lib/gelf/notifier.rb#L57-L67).

According to GELF specification and validation, we should not separate data into more than 128 chunks.
It seems the max data size for GELF UDP that can be sent is:

```bash
1420 bytes * 128 chunks = 181760 bytes =~ 177 Kb
```

So if we correctly understand the ruby code the max data size for GELF UDP is **~177 Kb**.

**How to fix:**

We highly recommend to use TCP connection from FluentD/FluentBit to Graylog.

If you need to use UDP connection for some reasons, you can try to set smaller value in Graylog buffer section
in FluentD configuration. To do that you need to:

1. Scal to 0 replicas (because it can rewrite your changes in Fluentd Configuration).

    ```bash
    kubectl scale -n <namespace> deployment logging-operator --replicas=0
    ```

2. Edit configmap `logging-fluentd`.

    ```bash
    kubectl edit cm logging-fluentd -n <namespace>
    ```

3. Find part of configuration `output-graylog.conf`, in section `<buffer>` set the value:

    ```xml
    <store ignore_error>
      @type gelf
      # other parameters
      <buffer>
        chunk_limit_size 176KB
      </buffer>
    </store>
    ```

**Note:** Read more about buffering parameters in
[official FluentD documentation](https://docs.fluentd.org/configuration/buffer-section#buffering-parameters).

## Fluent container restarts after changing ConfigMap

**Symptoms:**

Fluent container restarts after manually updating configmap.

**How to fix:**

1. Check logs from the main Fluents' container. It contains information about error.
Example:

   ```bash
      2024-09-12 09:56:10 +0000 [error]: Worker 0 exited unexpectedly with status 1
      /fluentd/vendor/bundle/ruby/3.2.0/gems/fluentd-1.17.1/lib/fluent/config/basic_parser.rb:92:in `parse_error!': unmatched end tag at filter-add-hostname.conf line 6,12 (Fluent::ConfigParseError)
         hostnameTest "#{ENV['HOSTNAME']}"
       </record>
      ----------^
      </filter>
   ```

2. Found the problem file: `unmatched end tag at filter-add-hostname.conf line 6,12`
3. Fix configuration and wait for the next reload.
