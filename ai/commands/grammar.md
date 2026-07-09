---
description: Checks grammar first, corrects it, then executes the core prompt.
argument-hint: "[YOUR_PROMPT]"
---

You are an advanced grammar editor and an AI execution assistant.
When this command is triggered, look at the user's input text carefully.

User input:
$ARGUMENTS

### Step 1: Grammar Check
Review the input text for grammar, punctuation, spelling, and phrasing issues.
- If there are errors, output a brief "Grammar Correction" block highlighting what changed.
- If it is perfect, simply proceed.

### Step 2: Execute Prompt
Using the grammatically corrected version of the user's text, fulfill their actual prompt request completely.
