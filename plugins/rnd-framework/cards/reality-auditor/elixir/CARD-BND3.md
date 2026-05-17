---
id: BND3
role: reality-auditor
language: elixir
tags: [anomaly, skepticism, defensive-programming]
applicable_task_types: [new-feature, bugfix, infra]
scope: Bandit's default :idle_timeout is 60 seconds; long-running HTTP requests (uploads, slow clients, streaming) need explicit timeout configuration or they will be cut off.
specializes: [P-IMPOSSIBLE-01]
---

Specializes the impossible-states principle by flagging the assumption that a long-lived HTTP connection will stay open — an assumption that is false under Bandit's default idle timeout, which applies even to active connections that are slow to produce data.

**Good audit output:**
> `ExportController.download/2` at `lib/web/controllers/export_controller.ex:44` streams a large CSV using `send_chunked` + `chunk/2`. The Bandit adapter config at `config/config.exs:18` has no `:thousand_island_options` key — Bandit's default `:idle_timeout` of 60_000 ms applies. If the CSV generation pauses for more than 60 seconds between chunks (e.g., slow upstream API), Bandit closes the connection and the client receives a truncated file with no error. Flag: add `thousand_island_options: [read_timeout: 300_000]` (or appropriate value) to the Endpoint config, and verify the streaming loop handles `{:error, :closed}` so the exporter stops producing rows on disconnection.

**Worse audit output:**
> The controller streams a large CSV response. The chunked transfer looks correct.

**Why good is better:** Bandit enforces the idle timeout even when bytes are being exchanged — the timeout measures the time between reads from the client's socket, not total request duration. A streaming response that pauses while generating the next chunk can trip the timeout mid-stream. The good output identifies the specific endpoint, traces the config path, states the default value, and names both the symptom (truncated file) and the fix.
