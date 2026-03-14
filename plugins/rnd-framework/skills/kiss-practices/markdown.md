# Markdown — KISS Rules

- Use ATX headings (`#`) not Setext (underlines) — pick one style and stick with it
- Don't nest headings deeper than 3 levels — if you need `####`, restructure into separate sections or files
- Use `-` for unordered lists, `1.` for ordered — don't mix `*`, `+`, and `-` within a file
- Don't add HTML when Markdown syntax covers it — use `**bold**` not `<strong>bold</strong>`
- Don't create elaborate table formatting — simple pipe tables are enough; if the table is too complex for Markdown, use a different format
- Don't add blank lines between every paragraph for "readability" — one blank line separates blocks, more is noise
- Use reference-style links `[text][ref]` only when the same URL appears 3+ times — inline links are clearer for one-off references
- Don't add a table of contents manually — let the renderer or tooling generate it
- Don't wrap lines at 80 characters in prose — let the editor soft-wrap; hard wraps create noisy diffs
- Don't use blockquotes (`>`) for emphasis — they're for quotations; use bold or callout syntax for emphasis
- Keep frontmatter minimal — only fields the system actually reads; don't add metadata nobody consumes
