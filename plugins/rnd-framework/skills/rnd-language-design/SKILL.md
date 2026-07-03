---
name: rnd-language-design
description: Use when planning a DSL, interpreter, compiler, parser, renderer, or other small language so syntax, semantics, diagnostics, and empirical specs are explicit before implementation.
effort: low
---

# R&D Language Design

## Overview

Plan small languages by making their observable behavior explicit before implementation. The output is a language-agnostic design package that a Builder and Verifier can test, not a vague parser idea.

**Core principle:** make syntax, structure, semantics, and failures observable in the specification before they become code paths.

## When to Use

- A task introduces or changes a DSL, template language, query language, rules language, command language, or other compact notation with executable or renderable behavior.
- The work needs explicit decisions about syntax, grammar, parsing, AST shape, semantics, validation, diagnostics, rendering, execution, or compilation.
- The design still depends on intuition, examples in someone's head, or implementation details that are not yet written down as contracts.
- Do not use this for plain structured data that has no language behavior beyond static field validation.

## The Iron Law

If the language cannot be specified with accepted examples, rejected examples, AST expectations, semantic results, and diagnostic expectations, it is not ready to build.

## Process

1. **Problem framing**
   - State the user job, the authoring environment, and the exact behavior the language must make easier than direct host-system usage.
   - Name the intended audience, the expected scale, and the mistakes the design should prevent.
   - State what is intentionally out of scope so the language does not grow into a general-purpose catch-all.

2. **Existing alternatives**
   - Compare the proposal against existing formats, configuration shapes, rule systems, query surfaces, or plain data plus helper code.
   - Justify why a new language is needed instead of extending or constraining an existing representation.
   - Record the migration or interoperability boundary if the language coexists with another surface.

3. **Syntax**
   - Define the surface forms: literals, identifiers, keywords, delimiters, comments, whitespace policy, grouping, precedence, and associativity.
   - Keep syntax minimal and predictable. Every token should earn its place by changing observable meaning or authoring clarity.
   - List ambiguous-looking forms early so they are resolved in the spec instead of in parser code.

4. **Grammar**
   - Write the grammar or equivalent parse contract for every construct and composition rule.
   - Distinguish lexical structure from higher-level composition when that separation matters.
   - Document ambiguity resolution, reserved forms, and termination rules so parsing behavior is reproducible.

5. **AST design**
   - Define node kinds, required fields, optional fields, source spans, and canonical child ordering.
   - Decide which syntax sugar survives in the AST and which forms normalize into a smaller semantic core.
   - Produce golden AST cases for representative accepted examples, including edge shapes and normalized forms.

6. **Semantics**
   - Define what each AST node means, what context it can read, and what outputs, effects, or failures it may produce.
   - Separate parse validity from semantic validity so the design is clear about what is structurally valid but semantically rejected.
   - Name invariants that must hold after semantic analysis, lowering, or execution.

7. **Parser or compiler pipeline**
   - Specify the ordered stages, such as lexing, parsing, AST normalization, name resolution, validation, lowering, optimization, rendering, execution, or emission.
   - State the input and output contract for each stage and which stages may stop with diagnostics.
   - Keep the pipeline simple enough that each stage has one job and one observable artifact.

8. **Renderer or executor**
   - Define the runtime, renderer, interpreter, or emitter contract that consumes the analyzed form.
   - State whether output should preserve formatting choices, normalize them, or ignore them.
   - When the language targets another representation, specify what must round-trip and what may be canonicalized.

9. **Validator**
   - Write explicit validation rules for names, references, cardinality, ranges, prohibited combinations, and context-dependent constraints.
   - Separate validator output from runtime failures so users know whether a problem is authoring-time or execution-time.
   - Decide which checks belong before execution and which belong inside the executor because they depend on runtime inputs.

10. **Diagnostics**
    - Define stable diagnostic classes, required message facts, and source-location expectations.
    - Prefer diagnostics that explain the violated rule and point to the smallest useful span.
    - Create diagnostics fixtures for parse errors, semantic errors, and validation errors that are likely to recur.

11. **Test design**
    - Write accepted examples that must parse and reach the intended semantic result.
    - Write rejected examples that must fail with the correct stage and diagnostic class.
    - Maintain golden AST cases for syntax-to-structure expectations.
    - Define semantic invariants that should hold across broad input families.
    - Add round-trip or rendering checks when the language renders, serializes, or lowers into another stable form.

12. **Language evolution**
    - Decide how new constructs will be introduced without breaking existing authored material unexpectedly.
    - Mark which syntax is reserved for future use and which behaviors are guaranteed stable.
    - Require compatibility notes whenever a change affects parsing, AST shape, semantics, diagnostics, or rendered output.

### Empirical specification outputs

Every language plan should leave behind an empirical specification package:

- Accepted examples with expected semantic outcomes
- Rejected examples with expected failure stage and diagnostics
- Golden AST cases for representative source forms
- Semantic invariants that remain true across broad classes of inputs
- Diagnostics fixtures with source-location expectations
- Round-trip or rendering checks for any stable output surface

## Common Rationalizations

- "We can clean up the grammar after the parser works." If the grammar is implicit in code, ambiguity is already winning.
- "The AST can mirror the parse tree for now." Parse trees preserve syntax accidents; ASTs should preserve meaning.
- "Validation can happen wherever it is convenient." Unowned validation rules drift between parser, executor, and callers.
- "One or two happy-path examples are enough." Without rejected examples, golden AST cases, and diagnostics fixtures, the spec is not falsifiable.
- "We can add compatibility rules later." Language evolution without an explicit stability story turns every revision into a surprise.

## Verification Checklist

- [ ] Problem framing names the user job, audience, and out-of-scope behavior.
- [ ] Existing alternatives were considered and rejected for explicit reasons.
- [ ] Syntax and grammar are documented with ambiguity resolution.
- [ ] AST design defines node kinds, normalization rules, and golden AST cases.
- [ ] Semantics define meaning, stage boundaries, and semantic invariants.
- [ ] The parser or compiler pipeline is staged with concrete input and output contracts.
- [ ] The renderer or executor contract is explicit about output shape and canonicalization.
- [ ] Validator rules and diagnostics fixtures are defined separately from runtime behavior.
- [ ] Test design includes accepted examples, rejected examples, golden AST cases, diagnostics fixtures, semantic invariants, and round-trip or rendering checks.
- [ ] Language evolution documents reserved space and compatibility expectations.

## Related Skills

- `rnd-framework:rnd-decomposition` — Pre-register the language work as testable tasks once the design package is clear.
- `rnd-framework:rnd-brainstorm` — Use when the language problem itself is still vague and needs framing before planning.
- `rnd-framework:rnd-review` — Review language changes against explicit syntax, semantics, diagnostics, and invariant contracts.
