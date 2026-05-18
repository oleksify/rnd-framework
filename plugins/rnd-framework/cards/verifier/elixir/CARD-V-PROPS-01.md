---
id: V-PROPS-01
role: verifier
language: elixir
tags: [property, critique-evidence, boundaries]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Interpret a StreamData shrunk reproducer and write a concrete Feedback section when a property fails.
---

**Good Feedback entry:**
> FAIL. `lib/run-properties.sh` returned `PROPERTY_COUNTER_EXAMPLE` for property `encode_decode_roundtrip`. Shrunk reproducer: `<<0xFF, 0x00>>` (seed 4829103). StreamData reduced the input from a 47-byte binary to this 2-byte sequence — the minimal input that breaks the invariant. `Codec.encode(<<0xFF, 0x00>>)` returns `{:error, :invalid_utf8}` but `Codec.decode` is called unconditionally on the result, raising `FunctionClauseError`. The property is: `forall input <- StreamData.binary(), decode(encode(input)) == input`. The implementation must guard against non-UTF-8 input before calling `decode/1`, or the invariant must be narrowed to `StreamData.binary(:printable)`.

**Worse Feedback entry:**
> FAIL. The property test failed. The encode/decode roundtrip does not work correctly for all inputs. The implementation needs to handle edge cases.

**Why good is better:** StreamData's shrinking hands you the minimal falsifying input for free — the whole point of property-based testing. Discarding that precision in the Feedback section defeats the purpose. A good counter-example entry names the specific reproducer, the seed (so the builder can replay), the property that failed, and the concrete failure mode observed. It also tells the Builder exactly where the fix must go: guard at encode, narrow the generator, or fix the invariant. The worse entry forces the Builder to re-run the property suite from scratch to learn what the Verifier already knows. Pin the reproducer; state the cause; propose the narrowest fix boundary.
