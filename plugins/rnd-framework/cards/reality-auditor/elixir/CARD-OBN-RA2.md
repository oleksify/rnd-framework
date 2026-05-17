---
id: OBN-RA2
role: reality-auditor
language: elixir
tags: [anomaly, inconsistency, cross-check]
applicable_task_types: [new-feature, bugfix, refactor, infra]
scope: Audit Oban queue concurrency config — per-queue limit caps concurrent jobs per node, not per worker module; multiple workers sharing a queue share the cap.
specializes: [P-IMPOSSIBLE-01]
---

Specializes the impossible-states principle by exposing that "queue concurrency = worker concurrency" is a false assumption: multiple worker modules in the same queue contend for the same slot pool.

**Good audit output:**
> `config/config.exs` sets `queues: [billing: 5]`. Three worker modules (`ChargeWorker`, `RefundWorker`, `InvoiceWorker`) all declare `queue: :billing`. The concurrency limit of 5 is shared across all three — if 5 `ChargeWorker` jobs are running, `RefundWorker` jobs queue behind them even if refunds are time-sensitive. Also: `ChargeWorker` declares `max_attempts: 20` while the queue has no per-worker override. A storm of failing `ChargeWorker` jobs (20 retries each) can crowd out the other workers. Flag: consider separate queues per worker type, or use `Oban.Pro`'s per-worker concurrency limits if available. Ref: https://hexdocs.pm/oban/Oban.html#module-queues

**Worse audit output:**
> The billing queue is configured with a concurrency of 5. This should handle the load.

**Why good is better:** The worse output confirms the number exists without checking whether the workers sharing the queue compete for the same slots. The good output traces the worker-to-queue mapping, identifies the shared-pool consequence, and flags the retry-storm amplification. Queue concurrency is a global cap, not a per-worker reservation — auditors must check both the queue config and all workers declared for it.
