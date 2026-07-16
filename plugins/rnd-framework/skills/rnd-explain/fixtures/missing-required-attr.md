# Background

Rejection class: SCHEMA_VALIDATION. The chart below omits its required
`series` attribute, so Markdoc.validate against the typed schema returns an
error and the gate refuses the document.

# Intuition

Text.

# Code

{% chart type="bar" title="no series here" /%}

# Quiz

{% quiz questions=[{question: "Q1?", options: ["a", "b"], answer: 0, feedback: ["no", "yes"]}, {question: "Q2?", options: ["a", "b"], answer: 1, feedback: ["no", "yes"]}, {question: "Q3?", options: ["a", "b"], answer: 0, feedback: ["no", "yes"]}, {question: "Q4?", options: ["a", "b"], answer: 1, feedback: ["no", "yes"]}, {question: "Q5?", options: ["a", "b"], answer: 0, feedback: ["no", "yes"]}] /%}
