---
id: OBN-RA1
role: reality-auditor
language: elixir
tags: [anomaly, skepticism, defensive-programming]
applicable_task_types: [new-feature, bugfix, refactor, infra]
scope: Audit whether Oban job retention is configured — without the pruner, completed and discarded records accumulate unboundedly.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle by flagging that job insertion is a side effect that also grows the `oban_jobs` table forever unless a retention policy trims it.

**Good audit output:**
> `config/config.exs` configures Oban with `queues: [default: 10]` but no `plugins:` key. The `Oban.Plugins.Pruner` is absent from the plugin list. All completed and discarded job records remain in the `oban_jobs` table permanently. On a table receiving 1 000 jobs/day, this is ~365 K rows/year with no automatic cleanup. Flag: add `{Oban.Plugins.Pruner, max_age: 7 * 24 * 3600}` to the plugins list, or document the manual retention strategy (e.g., pg_partman). Ref: https://hexdocs.pm/oban/Oban.Plugins.Pruner.html

**Worse audit output:**
> The Oban configuration looks reasonable. Jobs are being processed in the default queue.

**Why good is better:** The worse output only checks whether jobs are processed — it misses the accumulation side effect entirely. Every Oban deployment needs an answer to "what happens to rows after they complete?" The good output quantifies the growth rate, names the missing plugin, and provides the fix. Completed jobs are invisible to operators until the table causes a disk or query-performance incident; catch it during audit, not during an outage.
