# Render-proof: automated + manual

The rnd-explain Markdoc report runtime has two complementary correctness nets:
an automated headless-Chrome smoke-check (`render-proof-suite.test.sh`) and a
manual browser spot-check for a human to run before trusting a freshly
generated report.

## Automated: `render-proof-suite.test.sh`

Run via the full suite:

```
tests/run-tests.sh
```

or standalone:

```
bash tests/render-proof-suite.test.sh
```

It validates `tests/fixtures/render-proof-suite/kitchen-sink.md` — a single
Markdoc island exercising the full v1 tag vocabulary (callout, all 4 chart
types, all 3 diagram kinds, formula, kpi, mock, a stepper, a GFM pipe-table, a
fenced code block, and a 5-question quiz) — against the determinism gate
(`report-validate.js`), then assembles it into a full report and mounts it in
headless Chrome via `tests/lib/render-check.mjs`, asserting every tag renders
with zero thrown exceptions or console errors. If Chrome is not found at the
configured path, the render-executed half prints a loud `SKIP:` line and the
test still exits 0 — the gate check runs regardless of Chrome.

## Manual spot-check procedure

Run this whenever you touch the Markdoc runtime (`template.html`), a tag's
render function, or the quiz/stepper behavior — the automated check proves the
kitchen-sink fixture is clean, but only a human eye confirms the report reads
well and the interactive elements feel right.

1. Generate a report (via the `rnd-explain` skill/command, or by assembling
   the kitchen-sink island into `template.html` the same way the test does).
2. Open the resulting `.html` file directly in a browser — double-click it on
   macOS, or `open path/to/report.html` — with **DevTools open on the Console
   tab** before or immediately after the page loads.
3. Confirm, by eye:
   - All four sections appear in order: Background, Intuition, Code, Quiz.
   - Every custom tag renders visibly: the callout box, all chart types (bar,
     line, scatter, area), all diagram kinds (graph, tree, sequence), the
     formula (native MathML, not a broken `<mrow>` text dump), the KPI cards,
     the mock window, the pipe-table, and the fenced code block with its
     newlines intact.
   - The stepper shows step 1 initially; clicking Next/Prev advances or
     retreats exactly one step and disables at the ends.
   - The quiz shows exactly 5 question cards. Clicking an option reveals
     correct/incorrect styling and per-answer feedback, and the running score
     updates. Clicking a second option on an already-answered card does
     nothing — the score does not move again.
   - The DevTools Console stays clean: no red errors, no uncaught exceptions,
     no failed network requests (there should be none — the report is fully
     offline).
4. Toggle the OS/browser color scheme to dark and confirm the report switches
   to a genuine dark palette (not a flat-black background) with no layout
   breakage.

If any of the above fails, the report must not ship — treat it the same as a
failing automated check.
