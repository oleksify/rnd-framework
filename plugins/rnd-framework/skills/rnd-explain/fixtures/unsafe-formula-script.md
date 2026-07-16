# Background

An otherwise well-formed island whose only defect is a formula that smuggles a
script element into its MathML markup. The determinism gate must reject it.

# Intuition

{% callout type="info" title="Why this matters" %}
MathML is parsed by the HTML tokenizer, so a script inside a formula is a
mutation-XSS vector.
{% /callout %}

# Code

{% formula title="Smuggled script" mathml="<mtext><script>window.__pwned=1</script></mtext>" /%}

# Quiz

{% quiz questions=[{question: "Where does the runtime come from?", options: ["A CDN", "An inlined bundle"], answer: 1, feedback: ["No CDN is used.", "Correct: the bundle ships inline."]}, {question: "How is chart data authored?", options: ["A JSON string", "A Markdoc literal"], answer: 1, feedback: ["A string breaks on quotes.", "Correct: literals resolve to real arrays."]}, {question: "When does rendering happen?", options: ["At generate time", "In the browser at load"], answer: 1, feedback: ["No server render.", "Correct: parsed and mounted at load."]}, {question: "What guards a quiz card?", options: ["Nothing", "A per-card answered flag"], answer: 1, feedback: ["That allows re-answering.", "Correct: later clicks are ignored."]}, {question: "Is the report self-contained?", options: ["No, it needs a CDN", "Yes, a single file"], answer: 1, feedback: ["No network at runtime.", "Correct: one offline file."]}] /%}
