---
id: R5
role: reality-auditor
language: elixir
tags: [anomaly, cross-check, skepticism]
applicable_task_types: [new-feature, bugfix, refactor]
scope: GenServer state lives in a process mailbox; ETS and DB can diverge from it — cross-check all three before trusting any single source.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle by flagging that process state, ETS, and the database are three separate stores that can disagree, and any audit must verify the claim against all of them.

**Good audit output:**
> `SessionServer` stores active sessions in `state.sessions` (GenServer) and writes a copy to `Sessions` ETS table on `handle_cast(:login, ...)`. The `Session` Repo table is updated separately via `Repo.update_all` on logout. Noticed: if the process crashes between the ETS write and the `Repo.update_all`, the ETS entry shows the session as active while the DB shows it as ended. Also: if the ETS table is `:protected`, reads bypass the GenServer and go directly to the table — a reader could see stale state that the GenServer has not yet propagated. Three divergence points identified; flagging.

**Worse audit output:**
> The server maintains session state in a GenServer and also caches in ETS. This is a common Elixir caching pattern.

**Why good is better:** GenServer state, ETS, and the database are independent stores. A crash, a missed `handle_info`, or a direct ETS read can leave them inconsistent. The good output traces the exact write sequence, names the crash window, and identifies the ETS access pattern that bypasses the GenServer. The worse output names the pattern without checking whether all three stores agree.
