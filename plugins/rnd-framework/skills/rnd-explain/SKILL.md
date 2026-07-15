---
name: rnd-explain
description: "Generate a self-contained, interactive HTML explanation of a code change — Background, Intuition, Code walkthrough, and a 5-question quiz — for someone who wasn't there when it was written."
user-invocable: false
effort: medium
---

# R&D Framework: Explain a Change

Turn a diff into a single-page HTML document that teaches a reader what changed and why. The command that invokes this skill has already resolved the diff target and the output path (`$RND_DIR/explain/YYYY-MM-DD-<slug>.html`); this skill owns everything downstream of that — content structure, self-containment, and the pre-save scan.

## Step 1: Read the Diff

Read the diff text handed to you by the invoking command. This is the sole source material for Background, Intuition, and Code — do not fetch anything else about the change.

## Step 2: Check for Session Enrichment (Optional, Additive Only)

Look for a pipeline session directory. Two outcomes, and only two:

- **Session present** — verification reports exist under `$RND_DIR/verifications/T*-verification.md` for tasks that touch the files in the diff. For each touched task's report, pull a short inline excerpt from its `## Case for PASS` section and its `## Coverage Gaps` section (these are the exact heading strings the verifier's reports use). You will fold these excerpts into the Code section in Step 3.4 below.
- **Session absent** — no `$RND_DIR`, no verification reports, or no report touches the diffed files. Produce the document exactly as if this step didn't exist: no error, no placeholder text, no dangling reference to a session that isn't there. The no-session output and the session-present output differ only in the presence of the extra excerpts — nothing else in the document changes.

This step can only ever add content. It never gates, blocks, or changes any other section.

## Step 3: Generate the Four Sections, In This Order

Every generated document has exactly these four sections, in exactly this order. Do not add a fifth section, do not reorder them, do not make any of them conditional.

### 3.1 Background

Two parts, both present:

- **Deep beginner background** — the concepts a total newcomer would need. Mark this part as skippable (e.g. a `<details>` disclosure or a clearly labeled "skip if you already know this" subsection) so an experienced reader can jump past it.
- **Narrow change-relevant background** — the specific context needed to understand *this* change and nothing more. Not skippable; this is the part everyone reads.

### 3.2 Intuition

Convey the essence of the change, not its implementation details. Use concrete toy-data examples — small, made-up inputs and outputs that make the idea tangible. Use diagrams liberally (see the diagram rules in Step 4) to carry intuition that prose alone would labor to explain.

### 3.3 Code

A high-level, grouped walkthrough of the actual change — group related edits by concern or file, not a line-by-line narration. This is where a reader connects the intuition from 3.2 to the real diff.

### 3.4 Session Enrichment (fold-in point, when present)

If Step 2 found a session, the short inline excerpts from `## Case for PASS` and `## Coverage Gaps` belong inside this Code section, attached to the part of the walkthrough they're relevant to — inline text, not a separate section and not an external link. If Step 2 found nothing, this paragraph does not apply and the Code section contains only the walkthrough from 3.3.

### 3.5 Quiz

Exactly 5 multiple-choice questions, medium difficulty — hard enough that answering correctly requires having understood the change, not so hard they're gotchas, and not so easy they're rote recall. Every question is interactive: clicking an answer reveals whether it's correct or incorrect, plus a short piece of feedback explaining why.

**The Quiz is unconditional.** It appears on every single run, regardless of how small the diff is, how little session evidence exists, or how confident the generation felt. There is no confidence threshold, no evidence-density threshold, no "skip if trivial" branch anywhere in this section. A one-line refactor with zero session artifacts still gets a fully populated, 5-question quiz — the same as a sprawling multi-file change. If you find yourself reasoning about whether the diff is "big enough" to warrant a quiz, that reasoning is wrong; write the quiz anyway.

## Step 4: Start From the Template — Never Author CSS or the Quiz Engine

Read `${CLAUDE_SKILL_DIR}/template.html`. This is the canonical, fixed asset for every run: it already carries the full CSS design system, the four-section skeleton (Background, Intuition, Code, Quiz), the table of contents, the responsive viewport meta tag, the diagram/callout/code-block styles, and a complete, tested quiz engine. Your job in this step is to **fill it in**, never to write a new document from scratch, and never to touch its `<style>` block or its quiz engine `<script>` block.

Fill exactly these placeholders, and nothing else:

- `<!-- FILL:TITLE -->...<!-- /FILL:TITLE --></title>` and the matching one in `<h1>` — a short document title describing what changed.
- `<!-- FILL:SUBTITLE -->...<!-- /FILL:SUBTITLE -->` — a one-sentence summary.
- `<!-- FILL:BACKGROUND_DEEP -->...<!-- /FILL:BACKGROUND_DEEP -->` — the skippable deep-beginner background, already wrapped in the template's `<details class="skip">` disclosure. Leave that wrapping alone; only replace the content inside the markers.
- `<!-- FILL:BACKGROUND_NARROW -->...<!-- /FILL:BACKGROUND_NARROW -->` — the non-skippable, change-relevant background.
- `<!-- FILL:INTUITION -->...<!-- /FILL:INTUITION -->` — toy-data examples and HTML diagrams conveying the essence of the change. Reuse the template's existing diagram classes (`.diagram .flow .node` for a system/data-flow diagram with example data, `.mock` for a simplified UI mock) rather than inventing new markup.
- `<!-- FILL:CODE -->...<!-- /FILL:CODE -->` — the grouped code walkthrough. If Step 2 found session enrichment, fold its short excerpts in here, inline, attached to the relevant part of the walkthrough — this is the same fold-in point described above, just located inside the template's Code placeholder instead of a section you author yourself.
- The quiz-data placeholder JSON array inside `<script type="application/json" id="quiz-data">` — replace it with exactly 5 question objects (see the quiz data contract below). This is the **only** part of the quiz you touch; you supply question *data*, never quiz wiring, never a second quiz engine, never a second element sharing the mount id.

Everything outside these markers — the `<style>` block, the `<nav class="toc">`, the section `<h2>` ids (`background`, `intuition`, `code`, `quiz-section`), the `<div id="quiz-root">` mount, the `<div id="quiz-score">` status line, and the fixed quiz engine `<script>` — ships byte-for-byte as it is in the template. Do not add a fifth section, do not reorder the four sections, do not rename or duplicate any id already present in the template.

The template gives you self-containment (inline-only CSS/JS, no external references, responsive viewport) and the diagram/callout/code CSS for free — you never write any of that. What you still author by hand, inside the placeholders above, follows these rules:

- **HTML lists for lists.** Any enumerable set of items is a proper `<ul>`/`<ol>`, not a hand-formatted paragraph or ASCII bullet.
- **Callouts for key concepts, definitions, and edge cases.** Wrap these in the template's `<aside class="callout">` (with a `<span class="tag">` label), so they stand out from ordinary prose.
- **Kleppmann-style prose.** Classic, clear, unshowy writing — smooth transitions between paragraphs and sections, no jargon left undefined, no abrupt topic jumps.
- **Every code block is safe from newline collapse.** Any snippet of source code goes in a `<pre>` element (the template already styles `pre`), or — if you use a custom-styled `<div>` instead — that element's CSS must explicitly set `white-space: pre-wrap` (or `pre`). Without one of these two, the browser collapses newlines and the snippet renders as an unreadable single line.
- **HTML-only diagrams, never ASCII.** Build every diagram from the template's existing diagram classes (`.diagram .flow .node` for a system/data-flow diagram carrying example data, `.mock` for a simplified UI mock) — never a monospaced ASCII-art block, and never a new diagram idiom invented from scratch.

### Quiz data contract

The quiz-data `<script type="application/json" id="quiz-data">` block holds a pure JSON array — no comments, no JS syntax, just data the fixed engine parses at load time. It must contain **exactly 5** objects, each shaped:

```json
{
  "q": "question text",
  "opts": ["option A", "option B", "..."],
  "correct": 0,
  "fb": ["feedback for option A", "feedback for option B", "..."]
}
```

- `q` — a string, medium-difficulty question (see Step 3.5 for the difficulty bar).
- `opts` — an array of 2 or more option strings.
- `correct` — an integer index into `opts` identifying the right answer.
- `fb` — an array of feedback strings, exactly parallel to `opts` (same length, one feedback string per option, explaining why that option is right or wrong).

The template's fixed engine script reads this JSON, renders one card per question, and handles click-to-reveal, per-answer feedback, a running score, and a guard against double-answering. None of that wiring is something you write — it already works; you only ever supply the array above.

## Step 5: Blocking Pre-Save Scan

Before writing the HTML file, scan the fully assembled HTML source (the template with all placeholders filled) as a **blocking self-check** — this runs before the Write, not after, and a failure here means you fix the document and re-scan, not that you write it anyway and note the problem.

The scan rejects the document if any of these is true:

1. **Any external URL reference exists** — search the assembled source for `http://`, `https://`, `//` protocol-relative references, or any `<link>`/`<script src>`/`<img src>` pointing outside the document itself. Any match fails the scan.
2. **Any code block lacks a newline-preserving container** — for every block of source code in the document, confirm it is wrapped in `<pre>`, or, if it uses a custom `<div>`, confirm that div's style includes `white-space: pre-wrap` or `white-space: pre`. A code block satisfying neither condition fails the scan.
3. **Any duplicate `id` attribute exists in the assembled document** — collect every `id="..."` in the source and confirm each value appears exactly once. A duplicate (the exact defect this template exists to prevent — see the note on the quiz mount id above) fails the scan.
4. **The quiz-data JSON does not parse** — extract the text content of `<script type="application/json" id="quiz-data">` and confirm `JSON.parse` succeeds on it. A parse failure fails the scan.
5. **The quiz data is not exactly 5 well-formed questions** — after parsing, confirm the array has exactly 5 entries, and that each entry has a string `q`, an `opts` array of at least 2 entries, a `correct` value that is a valid index into `opts` (`0 <= correct < opts.length`), and an `fb` array of feedback strings the same length as `opts`. Any entry failing any of these fails the scan.
6. **A `FILL:` or `FILL_ME` marker remains in the assembled source** — search for the literal strings `FILL:` and `FILL_ME` anywhere in the document. A match means a placeholder was left unfilled, and fails the scan.

On a scan failure, fix the offending block, reference, or data and re-run the full scan before proceeding to Write. Do not write a document that failed the scan and note the issue for later — there is no "later" for a document a reader may open in a browser immediately.

## Step 6: Write

Only after the Step 5 scan passes clean, write the assembled HTML to the path given by the invoking command. Do not return the HTML body as your response text.
