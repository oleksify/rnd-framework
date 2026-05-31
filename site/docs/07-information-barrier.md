## Information barrier

The single most important rule: **the verifier never sees the builder's reasoning.** Not the self-assessment, not the working notes, not the "this edge case probably won't matter" asides. The verifier judges the work against the pre-registered contract and the code alone.

```
   ┌────────────────────┐                     ┌────────────────────┐
   │      BUILDER       │   ╳  barrier  ╳     │     VERIFIER       │
   │  (its own context) │ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │  (its own context) │
   └─────────┬──────────┘                     └─────────┬──────────┘
             │ writes                                   │ reads
             ▼                                          ▼
     builds/…-self-assessment.md            ✗ blocked  validation-contract.md
     briefs/…                               ✗ blocked  the changed code
                                                        ✓ allowed
```

### Why

If the reviewer reads the author's framing first, the reviewer anchors on it. Known weaknesses get re-labelled as acceptable; verification quietly becomes rubber-stamping. Keeping the reviewer blind to the author's reasoning is what makes the check independent — the same reason scientific peer review and independent V&V separate the author from the checker.

### How it is enforced

Two layers, so a single mistake does not open the barrier:

1. **Structural isolation.** The builder and verifier run as separate agents in separate context windows. The verifier's context simply never contains the builder's notes — there is nothing to leak.

2. **Hooks.** Three pre-tool-use hooks (`read-gate.sh`, `glob-grep-gate.sh`, `bash-gate.sh`) block any attempt by the verifier or polisher to read a barrier-protected path — anything under `self-assessment`, `briefs/`, or `cleanup/`. If isolation ever failed, the hooks would still refuse the read.

The orchestrator is the legitimate consumer of those protected notes — it relays them to you — and so it is not barrier-restricted. Only the checking agents are.
