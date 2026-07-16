# Background

A well-formed report in every respect except its quiz: the correct option is the longest in every question, so only the length-bias guard fires.

# Intuition

{% callout type="info" title="Why this matters" %}
Structured data stays typed and self-contained.
{% /callout %}

# Code

{% chart type="bar" title="Latency (ms)" series=[{name: "p50", data: [12, 9, 8]}, {name: "p99", data: [40, 33, 29]}] /%}

# Quiz

{% quiz questions=[{question: "Where does the runtime come from?", options: ["A CDN", "An inlined bundle authored at build time"], answer: 1, feedback: ["No CDN is used.", "Correct: the bundle ships inline."]}, {question: "How is chart data authored?", options: ["A JSON string", "A typed Markdoc array or object literal"], answer: 1, feedback: ["A string breaks on quotes.", "Correct: literals resolve to real arrays."]}, {question: "When does rendering happen?", options: ["At generate time", "In the browser during the on-load pipeline"], answer: 1, feedback: ["No server render.", "Correct: parsed and mounted at load."]}, {question: "What guards a quiz card?", options: ["Nothing", "A per-card answered guard flag on the element"], answer: 1, feedback: ["That allows re-answering.", "Correct: later clicks are ignored."]}, {question: "Is the report self-contained?", options: ["No", "Yes, it is a single fully self-contained file"], answer: 1, feedback: ["It needs no network.", "Correct: one offline file."]}] /%}
