# Background

This report is the kitchen-sink render-proof: one island exercising every
custom tag in the vocabulary, wired into the fixed four-section arc.

{% callout type="warning" title="Read this first" %}
Every tag below is rendered from Markdoc array/object **literals** — never a
stringified JSON blob — so quotes and Unicode (café, 日本語) survive intact.
{% /callout %}

# Intuition

The tag vocabulary, side by side:

| Tag     | Variants                  | Rendered as   |
|---------|---------------------------|---------------|
| chart   | bar, line, scatter, area  | SVG           |
| diagram | graph, tree, sequence     | SVG           |
| formula | —                         | MathML        |
| stepper | —                         | `<x-stepper>` |

A fenced code block, newline-safe:

```js
const ast = window.Markdoc.parse(source);
const tree = window.Markdoc.transform(ast, config);
```

{% kpi label="Tags covered" value="8" delta="+8 new" trend="up" /%}
{% kpi label="Chart types" value="4" /%}
{% kpi label="Diagram kinds" value="3" /%}

{% mock title="kitchen-sink.html" %}
One island, every tag, one offline file.
{% /mock %}

# Code

Four chart types over comparable data:

{% chart type="bar" title="Bar" series=[{name: "p50", data: [12, 9, 8, 14]}, {name: "p99", data: [40, 33, 29, 45]}] /%}

{% chart type="line" title="Line" series=[{name: "requests/s", data: [5, 12, 9, 20, 17]}] /%}

{% chart type="scatter" title="Scatter" series=[{name: "latency", data: [3, 8, 5, 12, 7, 15]}] /%}

{% chart type="area" title="Area" series=[{name: "throughput", data: [2, 6, 4, 9, 11]}] /%}

Three diagram kinds over a small graph:

{% diagram kind="graph" title="Graph" nodes=[{id: "a", label: "A"}, {id: "b", label: "B"}, {id: "c", label: "C"}] edges=[{from: "a", to: "b"}, {from: "b", to: "c"}] /%}

{% diagram kind="tree" title="Tree" nodes=[{id: "root", label: "root"}, {id: "left", label: "left"}, {id: "right", label: "right"}] edges=[{from: "root", to: "left"}, {from: "root", to: "right"}] /%}

{% diagram kind="sequence" title="Sequence" nodes=[{id: "client", label: "Client"}, {id: "server", label: "Server"}] edges=[{from: "client", to: "server", label: "request"}, {from: "server", to: "client", label: "response"}] /%}

A closed-form bound, in native MathML:

{% formula title="Linear time" mathml="<mrow><mi>T</mi><mo>(</mo><mi>n</mi><mo>)</mo><mo>=</mo><mi>O</mi><mo>(</mo><mi>n</mi><mo>)</mo></mrow>" /%}

Step through the render pipeline:

{% stepper title="Render pipeline" steps=[{input: ["island.textContent"], transform: "Markdoc.parse", output: ["ast"]}, {input: ["ast"], transform: "Markdoc.validate", output: ["[]"]}, {input: ["ast"], transform: "Markdoc.transform", output: ["tree"]}, {input: ["tree"], transform: "renderNode per section", output: ["DOM mounted"]}] /%}

# Quiz

{% quiz questions=[{question: "Which esbuild flag makes window.Markdoc exist?", options: ["--format=cjs, a CommonJS module output", "--format=iife --global-name=Markdoc", "--format=esm"], answer: 1, feedback: ["Incorrect: CJS never defines a browser global.", "Correct: the IIFE format with a global name is what exposes window.Markdoc.", "Incorrect: ESM needs a module loader, not a global."]}, {question: "How is chart series data authored in the island?", options: ["A quoted JSON string passed as an attribute", "A Markdoc array/object literal", "A separate CSV file"], answer: 1, feedback: ["Incorrect: a quoted string breaks on quotes and Unicode.", "Correct: literals like series=[{name: \"p99\", data: [1,2,3]}] resolve to real arrays.", "Incorrect: nothing external is read at render time."]}, {question: "How many diagram kinds does the tag support?", options: ["Two", "Three", "Five"], answer: 1, feedback: ["Incorrect: graph, tree, and sequence make three.", "Correct: graph, tree, and sequence.", "Incorrect: there is no fourth or fifth kind."]}, {question: "What guards a quiz card from re-scoring on a second click?", options: ["Nothing, it always re-scores on every click", "A per-card answered attribute", "The whole quiz reloads"], answer: 1, feedback: ["Incorrect: that would let the score drift.", "Correct: data-answered is set on the first click and later clicks are ignored.", "Incorrect: nothing reloads."]}, {question: "What happens when the pre-save gate rejects an island?", options: ["It ships anyway with a console warning", "The report shows a distinct rejection reason and does not ship", "It silently falls back to the previously shipped older template"], answer: 1, feedback: ["Incorrect: a rejected island is not written.", "Correct: each rejection carries its own code and message.", "Incorrect: there is no older-template fallback in this runtime."]}] /%}
