# Background

A valid island whose formula carries a benign non-MathML element (a bold tag)
alongside real MathML. The gate accepts it, but the render step must rebuild the
math subtree from an allowlist and drop the foreign element.

# Intuition

{% callout type="info" title="Why this matters" %}
The render path rebuilds MathML via createElementNS from an element allowlist, so
foreign or HTML nodes never enter the live math subtree.
{% /callout %}

# Code

{% formula title="Foreign element" mathml="<mrow><mi>T</mi><mo>=</mo><mn>1</mn></mrow><mtext><b>drop me</b></mtext>" /%}

# Quiz

{% quiz questions=[{question: "Where does the runtime come from?", options: ["A CDN script tag fetched at load", "An inlined bundle"], answer: 1, feedback: ["No CDN is used at any point.", "Correct: the bundle ships inline."]}, {question: "How is chart data authored?", options: ["A quoted JSON string attribute", "A Markdoc literal"], answer: 1, feedback: ["A quoted string breaks on quotes.", "Correct: literals resolve to real arrays."]}, {question: "When does rendering happen?", options: ["At generate time on a server", "In the browser at load"], answer: 1, feedback: ["No server render happens.", "Correct: parsed and mounted at load."]}, {question: "What guards a quiz card?", options: ["Nothing", "A per-card answered flag"], answer: 1, feedback: ["That allows re-answering.", "Correct: later clicks are ignored."]}, {question: "Is the report self-contained?", options: ["No, it fetches from a CDN", "Yes, a single file"], answer: 1, feedback: ["No network at runtime.", "Correct: one offline file."]}] /%}
