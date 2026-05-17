---
id: R6
role: reality-auditor
language: elixir
tags: [anomaly, skepticism, defensive-programming]
applicable_task_types: [new-feature, bugfix, refactor, infra]
scope: :gen_tcp and :gen_udp default to :infinity timeouts; assume a hanging call unless an explicit timeout is visible in the code.
specializes: [P-IMPOSSIBLE-01]
---

Specializes the impossible-states principle by flagging the assumption that a TCP call will eventually return — an assumption that is false without an explicit timeout.

**Good audit output:**
> `:gen_tcp.connect/4` at `lib/tcp_client.ex:34` is called with `[:binary, active: false]` — no timeout in the options list. The default receive timeout is `:infinity`. If the remote host accepts the TCP handshake but never sends data, `receive` will block the calling process indefinitely. This is not a theoretical concern: any firewall drop after the SYN-ACK reproduces it. Flag: add `{:timeout, 5_000}` to the connect options and `{:recv_timeout, 5_000}` to the recv call.

**Worse audit output:**
> The code uses `:gen_tcp` to connect to the remote service. The connection options look reasonable.

**Why good is better:** `:gen_tcp.recv/3` and `:gen_tcp.connect/4` do not have a default timeout — they block forever unless the third/fourth argument names one explicitly. The good output identifies the specific call, explains the failure mode (firewall drop after handshake), and names the exact option to fix it. The worse output reads "looks reasonable" without checking whether `:infinity` is the actual behavior.
