# Background

Rejection class: UNFILLED_MARKER. The first quiz question's text is an unfilled
uppercase placeholder nested inside the quiz tag attribute. Markdoc parses that
attribute as an opaque string, so the typed schema never sees the marker — only
the raw-text scan over the island catches it.

# Intuition

Text.

# Code

Text.

# Quiz

{% quiz questions=[{question: "{% QUESTION_TEXT %}", options: ["a", "b"], answer: 0, feedback: ["no", "yes"]}, {question: "Q2?", options: ["a", "b"], answer: 1, feedback: ["no", "yes"]}, {question: "Q3?", options: ["a", "b"], answer: 0, feedback: ["no", "yes"]}, {question: "Q4?", options: ["a", "b"], answer: 1, feedback: ["no", "yes"]}, {question: "Q5?", options: ["a", "b"], answer: 0, feedback: ["no", "yes"]}] /%}
