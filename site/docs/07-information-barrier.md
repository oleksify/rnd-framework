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

If the reviewer reads the author's framing first, they anchor on it. Known weaknesses get re-labelled as acceptable, and verification quietly turns into rubber-stamping. Keeping the reviewer blind to the author's reasoning is what makes the check independent — the same reason scientific peer review keeps the reviewer separate from the author.

### How it is enforced

Two layers, so a single mistake does not open the barrier:

1. **Structural isolation.** The builder and verifier run as separate agents in separate context windows. The verifier's context simply never contains the builder's notes — there is nothing to leak.

2. **Hooks.** Three pre-tool-use hooks (`read-gate.sh`, `glob-grep-gate.sh`, `bash-gate.sh`) block any attempt by the verifier or polisher to read a barrier-protected path — anything under `self-assessment`, `briefs/`, or `cleanup/`. If isolation ever failed, the hooks would still refuse the read.

The orchestrator is the legitimate consumer of those protected notes — it relays them to you — and so it is not barrier-restricted. Only the checking agents are.

### The wording channel

Blocking the builder's notes closes the obvious leak. But there's a quieter one: the planner's *exact phrasing*. If the verifier reads each requirement in the same words the planner wrote, it can drift into matching the sentence — "yes, that line is there" — instead of independently re-checking that the claim is actually true. Same anchoring trap, smaller door.

So before the verifier sees the contract, a separate agent (`rnd-assertion-paraphraser`) re-words every assertion into different phrasing with **identical meaning**. Anything that has to stay exact — file names, function names, numeric thresholds, literal tokens — is kept byte-for-byte; only the surrounding natural language changes. The verifier checks the very same claims, just not in the wording it might lazily recognise. The re-worded blocks are only logged as injected once they've actually been pasted into the verifier's prompt, so the record can't claim a swap that didn't happen.
