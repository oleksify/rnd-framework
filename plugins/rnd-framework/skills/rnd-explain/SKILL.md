---
name: rnd-explain
description: "Generate a self-contained, interactive HTML explanation of a code change — Background, Intuition, Code walkthrough, and a 5-question quiz — for someone who wasn't there when it was written."
user-invocable: false
effort: medium
---

# R&D Framework: Explain a Change

Turn a diff into a single-page HTML document that teaches a reader what changed and why. The command that invokes this skill has already resolved the diff target and the output path (`$RND_DIR/explain/YYYY-MM-DD-<slug>.html`); this skill owns everything downstream of that.

The generated document is a single self-contained, offline (`file://`) HTML file whose content spine is **Markdoc** — markdown plus `{% tag %}` custom components — rendered in the browser at load. You author **one thing only**: the contents of the `<script type="text/markdoc" id="doc">` island (prose plus custom-tag attributes). Everything else — the inlined Markdoc runtime, the tag schema, the render functions, the custom-element behavior, the on-load parse/validate/render pipeline, and the CSS — is fixed code you never touch. This is the whole determinism contract: your only surface is the island; nothing you write can accidentally break the mechanism that renders it.

## Step 1: Read the Diff

Read the diff text handed to you by the invoking command. This is the sole source material for Background, Intuition, and Code — do not fetch anything else about the change.

## Step 2: Check for Session Enrichment (Optional, Additive Only)

Look for a pipeline session directory. Two outcomes, and only two:

- **Session present** — verification reports exist under `$RND_DIR/verifications/T*-verification.md` for tasks that touch the files in the diff. For each touched task's report, pull a short inline excerpt from its `## Case for PASS` section and its `## Coverage Gaps` section (these are the exact heading strings the verifier's reports use). You will fold these excerpts into the `# Code` heading's content in Step 3 below.
- **Session absent** — no `$RND_DIR`, no verification reports, or no report touches the diffed files. Author the island exactly as if this step didn't exist: no error, no empty marker, no dangling reference to a session that isn't there. The no-session and session-present islands differ only in the presence of the extra excerpts under `# Code` — nothing else changes.

This step can only ever add content. It never gates, blocks, or changes anything else.

## Step 3: Author the Markdoc Island

The island is ordinary Markdoc: standard markdown (GFM pipe tables, fenced code blocks, inline code spans, lists) plus the custom tags described in the Tag Reference below. Author it flush-left — indenting a line turns it into an indented code block under the Markdoc parser.

The document's structure comes entirely from four **level-1 headings**, which must appear exactly once each, in exactly this order, and nowhere else:

```
# Background
# Intuition
# Code
# Quiz
```

Everything under a given heading — prose, lists, callouts, charts, diagrams, code blocks, the stepper, the quiz tag — becomes the content of that section. The fixed renderer maps these four headings onto the report's four section ids (`background`, `intuition`, `code`, `quiz-section`) and mounts each heading's content into the matching section body. Do not add a fifth heading, do not reorder these four, and do not make any of them conditional. Custom tags always live inside one of the four sections — never outside all of them.

### 3.1 `# Background`

Two parts, both present:

- **Deep beginner background** — the concepts a total newcomer would need. Wrap this in a `{% callout %}` or a plain disclosure-style aside so a reader who already knows the basics can skip past it quickly (a short "skip if you already know this" lead-in line works well).
- **Narrow change-relevant background** — the specific context needed to understand *this* change and nothing more. Not skippable; this is the part everyone reads.

### 3.2 `# Intuition`

Convey the essence of the change, not its implementation details. Use concrete toy-data examples — small, made-up inputs and outputs that make the idea tangible. Reach for `{% diagram %}` and `{% chart %}` liberally here (see the Tag Reference) to carry intuition that prose alone would labor to explain.

### 3.3 `# Code`

A high-level, grouped walkthrough of the actual change — group related edits by concern or file, not a line-by-line narration. This is where a reader connects the intuition from 3.2 to the real diff. `{% stepper %}` is a good fit for a multi-stage transformation; a `{% mock %}` block can sketch a simplified before/after view.

If Step 2 found a session, fold its short excerpts from `## Case for PASS` and `## Coverage Gaps` in here, inline, attached to the part of the walkthrough they're relevant to — inline text, not a separate heading and not an external link. If Step 2 found nothing, this heading contains only the walkthrough.

### 3.4 `# Quiz`

A short lead-in sentence, then a single `{% quiz %}` tag holding exactly 5 medium-difficulty multiple-choice questions — see the Quiz Data Contract below for the exact shape. Medium difficulty means: hard enough that answering correctly requires having understood the change, not so hard the questions are gotchas, and not so easy they're rote recall.

**The quiz is unconditional.** It appears on every single run, regardless of how small the diff is, how little session evidence exists, or how confident the generation felt. There is no confidence threshold, no evidence-density threshold, no "skip if trivial" branch. A one-line refactor with zero session artifacts still gets a fully populated, 5-question quiz — the same as a sprawling multi-file change.

## Step 4: Tag Reference

Every custom tag below is declared with a typed, and in most cases required, attribute schema — the fixed schema layer rejects a missing required attribute or a wrong-typed value before the document is ever considered well-formed. Attribute names and types below are copied from that schema; do not invent attributes it doesn't declare.

| Tag | Closing form | Attributes |
|---|---|---|
| `{% callout %}...{% /callout %}` | has children (body content) | `type` — string, one of `note`, `info`, `warning`, `danger`, `success` (defaults to `note`); `title` — string, optional |
| `{% chart ... /%}` | self-closing | `type` — string, **required**, one of `bar`, `line`, `scatter`, `area`; `series` — array, **required**; `title` — string, optional |
| `{% diagram ... /%}` | self-closing | `kind` — string, **required**, one of `graph`, `tree`, `sequence`; `nodes` — array, **required**; `edges` — array, optional; `title` — string, optional |
| `{% formula ... /%}` | self-closing | `mathml` — string, **required** (native MathML markup); `title` — string, optional |
| `{% kpi ... /%}` | self-closing | `label` — string, **required**; `value` — string, **required**; `delta` — string, optional; `trend` — string, optional, one of `up`, `down`, `flat` |
| `{% mock %}...{% /mock %}` | has children (body content) | `title` — string, optional |
| `{% stepper ... /%}` | self-closing | `title` — string, optional; `steps` — array, **required** |
| `{% quiz ... /%}` | self-closing | `questions` — array, **required** (see Quiz Data Contract) |

`series`, `nodes`, `edges`, and `steps` are structured data — see the literal-syntax convention immediately below for how to author them. `callout` and `mock` are the only two tags with body content; every other tag is self-closing and carries all of its data as attributes.

- **`chart` series shape:** each entry is `{name: "<string>", data: [<numbers>]}`. The chart renders one series per entry; `type` picks the visual form (bars, a line, scattered points, or a filled area).
- **`diagram` nodes/edges shape:** each node is `{id: "<string>", label: "<string>"}`; each edge is `{from: "<node id>", to: "<node id>"}` with an optional `label`. `kind` picks the layout (a radial graph, a top-down tree, or a left-to-right sequence).
- **`stepper` steps shape:** each step is `{input: [<strings>], transform: "<string>", output: [<strings>]}` — one step per click of Next/Prev.
- **`formula` shape:** `mathml` is the inner markup of a `<math>` element (e.g. `"<mrow><mi>T</mi><mo>(</mo><mi>n</mi><mo>)</mo><mo>=</mo><mi>O</mi><mo>(</mo><mi>n</mi><mo>)</mo></mrow>"`), not a `$...$` string — there is no TeX parser here.

## Step 5: Structured Data as Markdoc Literals

Structured attributes (`series`, `nodes`, `edges`, `steps`, `questions`) are authored as **Markdoc array/object attribute literals**, using `key: value` pairs separated by commas — never as a quoted JSON string.

Correct:

```
{% chart type="bar" title="Latency by percentile (ms)" series=[{name: "p50", data: [12, 9, 8]}, {name: "p99", data: [40, 33, 29]}] /%}
```

```
{% diagram kind="graph" nodes=[{id: "parse", label: "parse"}, {id: "validate", label: "validate"}] edges=[{from: "parse", to: "validate"}] /%}
```

```
{% stepper steps=[{input: ["source = island.textContent"], transform: "Markdoc.parse(source)", output: ["ast"]}] /%}
```

Never do this — a stringified JSON attribute breaks on quotes and Unicode, throws a parse error against real data, and makes the island unreadable:

```
{% chart type="bar" series="[{\"name\":\"p50\",\"data\":[12,9,8]}]" /%}
```

The fixed render functions consume the resolved array/object values directly off the parsed node — they never call `JSON.parse` on an attribute. A stringified attribute simply arrives as an inert string and renders nothing.

## Step 6: Quiz Data Contract

The `{% quiz %}` tag's `questions` attribute is a Markdoc array literal, following the same `key: value` syntax as any other structured attribute. It must contain **exactly 5** objects, each shaped:

```
{question: "question text", options: ["option A", "option B", "..."], answer: 0, feedback: ["feedback for option A", "feedback for option B", "..."]}
```

- `question` — a non-empty string, medium-difficulty (see Step 3.4).
- `options` — an array of 2 or more option strings.
- `answer` — an integer index into `options` identifying the correct choice.
- `feedback` — an array of feedback strings, exactly parallel to `options` (same length, one string per option, explaining why that option is right or wrong).

Distractors must be as specific, plausible, and **comparable in length** as the correct answer — the correct answer must not be the longest option, because option length then becomes a tell that lets a reader guess "pick the longest" without understanding the change. The validator rejects a quiz (`QUIZ_LENGTH_BIAS`) when the correct option is the longest (or tied for longest) in more than half the questions, so balance option lengths across every question.

The fixed quiz custom element reads this array, renders one card per question, and handles click-to-reveal, per-answer feedback, a running score, and a guard against double-answering. None of that wiring is something you write — you only ever supply the `questions` array.

## Step 7: Blocking Pre-Save Validation Scan

Before writing anything, validate the assembled document with the headless validator — this is a **blocking** self-check that runs before the Write, not after. A failure means you fix the island and re-run the scan, not that you write the document and note the problem for later.

```
node "${CLAUDE_SKILL_DIR}/report-validate.js" <path-to-assembled-report.html>
```

or, to check just the island text against the fixed shell's inlined runtime and schema before assembling the full document:

```
node "${CLAUDE_SKILL_DIR}/report-validate.js" --island <path-to-island-source>
```

Both forms print `{ ok, violations: [{ code, message }] }` to stdout and exit non-zero if `ok` is false. Each violation carries a distinct code:

| Code | Meaning |
|---|---|
| `RUNTIME_UNAVAILABLE` | the Markdoc runtime could not be loaded for validation |
| `UNFILLED_MARKER` | a stray, never-replaced authoring marker remains anywhere in the island — including nested inside a tag attribute value, where a schema-only check would never see it |
| `EXTERNAL_URL` | an `http(s)://` or protocol-relative (`//host.tld`) reference appears in active island prose |
| `RUNTIME_EXTERNAL_REQUEST` | an `import(` or `fetch(` call appears in active island prose — see the conservative-bias note below |
| `SECTION_COUNT` | the island does not contain exactly the four required level-1 headings |
| `SECTION_ORDER` | the four level-1 headings are present but out of order |
| `PARSE_ERROR` | the Markdoc parser threw on the island source |
| `SCHEMA_VALIDATION` | schema validation rejected a missing required attribute, a wrong-typed attribute, or a value outside a tag's allowed set |
| `TRANSFORM_ERROR` | the transform step threw after schema validation passed |
| `QUIZ_COUNT` | the quiz tag is missing, duplicated, or its `questions` array is not exactly 5 entries |
| `QUIZ_MALFORMED` | a quiz question is missing its text, has fewer than two options, has an out-of-range or non-integer `answer` index, or a `feedback` array that isn't parallel to `options` |
| `QUIZ_LENGTH_BIAS` | the correct option is the longest (or tied for longest) in more than half the questions — a length tell; balance option lengths so the correct answer is not systematically the longest |

**Conservative-bias note on `EXTERNAL_URL`/`RUNTIME_EXTERNAL_REQUEST`:** the scan only looks at "active" prose — the contents of fenced code blocks and inline code spans are stripped out first, so a real `fetch(...)` or `import(...)` example written for illustration must live inside a fenced code block or an inline code span. The identical token typed as bare prose, outside any code fence or span, is treated as a real external reference and rejected. If the walkthrough needs to show such a call as an example, always put it in a fenced block or backtick span.

On any violation, fix the offending construct in the island and re-run the full scan before proceeding. Never write a document that failed the scan while planning to fix it afterward — there is no "afterward" for a document a reader may open in a browser immediately.

## Step 8: Manual Browser Spot-Check

After the pre-save scan passes and the file is written, do one more check with a human eye:

1. Open the generated `.html` file directly from disk (`file://…`) in a real browser.
2. Open DevTools and keep the console visible while the page loads and while you interact with it.
3. Confirm all four sections appear, in order, and every custom tag you authored (chart, diagram, formula, kpi, mock, callout, stepper) renders a visible, non-empty element.
4. Click through the quiz: exactly 5 cards; clicking an option reveals correct/incorrect plus its feedback; the running score updates; clicking the same card again does not change the score.
5. If a stepper is present, click through it and confirm it advances and retreats one step at a time.
6. The console stays clean throughout — zero errors, zero thrown exceptions, zero failed-resource warnings.

## Step 9: Assemble and Write

Only after the Step 7 scan is clean:

1. Take the fixed shell asset at `${CLAUDE_SKILL_DIR}/template.html` unchanged, byte for byte.
2. Replace only the text between `<script type="text/markdoc" id="doc">` and its closing `</script>` with the island you authored in Step 3. Every other byte — the `<style>` block, the inlined Markdoc runtime, the tag schema, the render functions, the custom-element behavior, the on-load renderer, and the validation gate — ships unchanged.
3. Write the assembled document to the path given by the invoking command.
4. Do not return the HTML body as your response text.
