---
id: P-PROPS-GEN-01
role: planner
language: generic
tags: [property, generators, domain-types, scope]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Decide when to upgrade from primitive generators to domain-typed generators based on the shape of failing inputs.
specializes: [P-PROPS-02]
---

**Good decision:**
> Counter-examples from the first property run cluster around `nil` nested inside a recursive structure: `{left: {left: nil, right: 3}, right: nil}`. A flat `fc.integer()` or `StreamData.integer()` generator cannot reproduce this — it never builds a nested shape. Upgrade the pre-registration to request a domain-typed generator: `StreamData.tree/2` (Elixir) or `fc.letrec` / `fc.record` (TypeScript). The property then explores the recursive input space and finds depth-dependent bugs.

**Worse decision:**
> Keep the generator as `StreamData.list_of(StreamData.integer())` even after failing inputs are multi-level maps. The Verifier watches the property pass on lists but the builder's implementation crashes on the real recursive input. The property test gives a false-green and the bug ships.

**Why good is better:** Primitive generators (`integer()`, `string()`, `binary()`) can only refute properties over flat inputs. Domain-typed generators model the actual input space: recursive trees, records with mutual constraints, lists with correlated lengths. The signal to upgrade is structural — when shrunk counter-examples have nested shapes, correlated fields, or mutually-constrained values that flat generators cannot produce. Calling the upgrade out in the pre-registration tells the Builder which generator shape is required before implementation begins, rather than discovering the gap at verification time.
