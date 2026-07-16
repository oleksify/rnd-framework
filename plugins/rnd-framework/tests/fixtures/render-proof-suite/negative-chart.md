# Background

A valid island whose chart carries negative data points. The renderer must draw
bars relative to a zero baseline so negative values render below it, never as a
negative (invalid, dropped) rect height.

# Intuition

{% callout type="info" title="Why this matters" %}
A value domain spanning zero keeps every bar's height non-negative while still
placing negative values below the baseline.
{% /callout %}

# Code

{% chart type="bar" title="Deltas" series=[{name: "delta", data: [5, -3, 8, -2, 6]}] /%}

{% chart type="line" title="Signed line" series=[{name: "signed", data: [4, -2, 6, -5, 3]}] /%}

{% chart type="area" title="Signed area" series=[{name: "signed", data: [3, -4, 5, -1, 2]}] /%}

# Quiz

{% quiz questions=[{question: "Where does the runtime come from?", options: ["A CDN script tag fetched at load", "An inlined bundle"], answer: 1, feedback: ["No CDN is used at any point.", "Correct: the bundle ships inline."]}, {question: "How is chart data authored?", options: ["A quoted JSON string attribute", "A Markdoc literal"], answer: 1, feedback: ["A quoted string breaks on quotes.", "Correct: literals resolve to real arrays."]}, {question: "When does rendering happen?", options: ["At generate time on a server", "In the browser at load"], answer: 1, feedback: ["No server render happens.", "Correct: parsed and mounted at load."]}, {question: "What guards a quiz card?", options: ["Nothing", "A per-card answered flag"], answer: 1, feedback: ["That allows re-answering.", "Correct: later clicks are ignored."]}, {question: "Is the report self-contained?", options: ["No, it fetches from a CDN", "Yes, a single file"], answer: 1, feedback: ["No network at runtime.", "Correct: one offline file."]}] /%}
