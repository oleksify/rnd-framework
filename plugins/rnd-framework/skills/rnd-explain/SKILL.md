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

## Step 4: Self-Containment Rules

The output is a single HTML file that works when opened directly as a `file://` URL, with nothing else on the page but everything it needs.

- **Inline-only CSS and JS.** All styles live in a `<style>` block in `<head>`; all scripts live in `<script>` blocks. No `<link>` to a stylesheet, no `<script src="...">`, no external font, no external image, no CDN of any kind. Zero external URL references, full stop.
- **One long page, not tabs.** Structure the document as a single scrolling page with section headers (Background, Intuition, Code, Quiz) plus a table of contents near the top that anchor-links into each section. Do not build top-level tabs that hide sections behind a click — the reader should be able to scroll through everything.
- **Basic responsive styling.** A simple viewport meta tag and CSS that keeps the layout usable on a phone-width screen — flexible widths, no fixed-pixel layouts that overflow small screens.
- **HTML-only diagrams, never ASCII.** Every diagram is built from HTML elements and CSS (boxes, flex/grid layouts, borders, arrows drawn with CSS) — never a monospaced ASCII-art block. Prefer a small, reusable set of diagram families rather than inventing a new visual idiom per diagram:
  - a simplified UI mock (boxes standing in for screens or components), and
  - a system/data-flow diagram that includes example data flowing through it, not just unlabeled boxes and arrows.
- **HTML lists for lists.** Any enumerable set of items is a proper `<ul>`/`<ol>`, not a hand-formatted paragraph or ASCII bullet.
- **Callouts for key concepts, definitions, and edge cases.** Give these a visually distinct treatment (a bordered/tinted `<div>` or `<aside>`) so they stand out from ordinary prose.
- **Kleppmann-style prose.** Classic, clear, unshowy writing — smooth transitions between paragraphs and sections, no jargon left undefined, no abrupt topic jumps.
- **Every code block is safe from newline collapse.** Any snippet of source code goes in a `<pre>` element, or — if a custom-styled `<div>` is used to hold code instead of `<pre>` — that element's CSS must explicitly set `white-space: pre-wrap` (or `pre`). Without one of these two, the browser collapses newlines and the snippet renders as an unreadable single line.

## Step 5: Blocking Pre-Save Scan

Before writing the HTML file, scan the fully assembled HTML source as a **blocking self-check** — this runs before the Write, not after, and a failure here means you fix the document and re-scan, not that you write it anyway and note the problem.

The scan rejects the document if either of these is true:

1. **Any external URL reference exists** — search the assembled source for `http://`, `https://`, `//` protocol-relative references, or any `<link>`/`<script src>`/`<img src>` pointing outside the document itself. Any match fails the scan.
2. **Any code block lacks a newline-preserving container** — for every block of source code in the document, confirm it is wrapped in `<pre>`, or, if it uses a custom `<div>`, confirm that div's style includes `white-space: pre-wrap` or `white-space: pre`. A code block satisfying neither condition fails the scan.

On a scan failure, fix the offending block or reference and re-run the scan before proceeding to Write. Do not write a document that failed the scan and note the issue for later — there is no "later" for a document a reader may open in a browser immediately.

## Step 6: Write

Only after the Step 5 scan passes clean, write the assembled HTML to the path given by the invoking command. Do not return the HTML body as your response text.
