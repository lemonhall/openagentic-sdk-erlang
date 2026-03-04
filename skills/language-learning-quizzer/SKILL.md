---
name: language-learning-quizzer
description: Use when creating language-learning multiple-choice practice (A/B/C/D; single- or multi-select) from learner logs or mistake sets, and you must generate a session JSONL file with answer key, grading, and wrongbook updates using the most recent N sessions (max 5).
---

# Language Learning Quizzer

## Overview

Generate a batch of multiple-choice questions (A/B/C/D), store a fixed answer key at generation time, then deliver the quiz **interactively (one question at a time)** or as a **single batch**. Grade against the stored key and persist everything to a per-session `JSONL` file (`session-YYYYMMDD-HHMM.jsonl`). Build/update a wrongbook from incorrect items.

Core principle: **The answer key is fixed at question generation time and must not change after the learner submits any answers.**

## Inputs (what to ask for)

Ask for the minimum missing info, one at a time:

1. **Target language** (e.g., Japanese) and **learner level** (e.g., N4 / A2).
2. **Source material** (one or more):
   - A learning trace text file (notes, study log, chat transcript)
   - A prior wrongbook (`practice/wrongbook.jsonl`)
   - Recent session logs (`practice/sessions/session-*.jsonl`)
3. **Quiz settings**:
   - `num_questions` (default: 20)
   - Mix: single-select vs multi-select (default: 80% single, 20% multi)
   - Focus (optional): vocab / grammar / kanji / listening (text-only) / reading
   - Delivery mode (default: interactive): `interactive` (one question at a time) or `batch` (all questions then one JSON submission)
4. **Reference window**: use most recent `N` sessions, `1 <= N <= 5` (default: 3).

## Output Contract

You must produce:

1. A batch quiz persisted to JSONL: numbered questions `1..num_questions` with options `A..D` and a fixed answer key stored in the `question.correct` fields.
2. Quiz delivery (choose one):
   - **Interactive mode (default):** show **one** question at a time; collect/validate the answer; record it; grade immediately; give brief feedback; then move on.
   - **Batch mode:** show all questions; learner replies once with JSON mapping:
     - Keys: question numbers as strings (`"1"`, `"2"`, ...)
     - Values: array of option letters (single-select: `["A"]`, multi-select: `["B","D"]`)
3. After all questions have answers (either mode):
   - Grading + explanations
   - Error-pattern summary (group similar mistakes)
   - Session persistence: write `practice/sessions/session-YYYYMMDD-HHMM.jsonl`
   - Wrongbook update: write/refresh `practice/wrongbook.jsonl`

If you cannot write files, output the JSONL content for the user to save verbatim.

## Session Files Layout

Use these paths (relative to the working directory):

- `practice/sessions/session-YYYYMMDD-HHMM.jsonl`
- `practice/wrongbook.jsonl`

Do not overwrite old session files. Always create a new session file.

## JSONL Schema (session-*.jsonl)

Each line is one JSON object with a `type` field.

### 1) `meta` (exactly one; first line)

Required fields:
- `type`: `"meta"`
- `session_id`: `"YYYYMMDD-HHMM"` (match filename)
- `created_at`: ISO8601 timestamp
- `target_language`
- `learner_level`
- `num_questions`
- `reference_sessions_used`: array of filenames used (max 5)
- `input_files_used`: array of file paths provided by user (may be empty)

Optional but recommended:
- `schema_version`: string (e.g. `"1"`)
- `notes`: brief summary of what was extracted from inputs

### 2) `question` (one per question; before submission)

Required fields:
- `type`: `"question"`
- `qnum`: integer (1-based)
- `concept_id`: string stable identifier (see below)
- `prompt`: string
- `options`: object with keys `A`,`B`,`C`,`D` and string values
- `multi_select`: boolean
- `correct`: array of letters (sorted, uppercase), e.g. `["B"]` or `["B","D"]`
- `explanation`: string (kept for grading time; do not reveal before submission)
- `tags`: array of short strings (e.g. `["grammar","particles","wa-vs-ga"]`)
- `difficulty`: integer 1..5

`concept_id` guidance (keep it simple):
- Vocab: `vocab:<headword>`
- Kanji: `kanji:<character>`
- Grammar: `grammar:<point>`
- Reading: `reading:<topic-slug>`

### 3) `submission` (batch mode; exactly one; after learner replies)

Required fields:
- `type`: `"submission"`
- `raw`: string (the learner message or JSON text)
- `answers`: object mapping `"1"`..`"N"` to arrays of letters

Normalization rules for `answers`:
- Uppercase letters only
- Remove duplicates
- Sort letters
- Validate each answer is subset of `{A,B,C,D}`
If the learner includes extra keys, ignore them; if keys are missing, treat as unanswered (`[]`).

### 3b) `response` (interactive mode; one per question)

Required fields:
- `type`: `"response"`
- `qnum`: integer
- `raw`: string (the learner message, e.g. `"B"` or `"A,C"`)
- `answer`: array of letters (normalized; sorted; unique)

Normalization rules for `answer`:
- Uppercase letters only
- Remove duplicates
- Sort letters
- Validate each answer is subset of `{A,B,C,D}`

Format checks (recommended):
- If the question is single-select and `answer` has multiple letters: record it and grade as incorrect with `error_label: "format-error"`.
- If empty after normalization: treat as unanswered.

### 4) `grading` (one per question; after submission)

Required fields:
- `type`: `"grading"`
- `qnum`: integer
- `user`: array of letters (normalized)
- `correct`: array of letters (must match the question’s correct)
- `is_correct`: boolean
- `error_label`: short string (see below)
- `feedback`: string (include why correct and why learner choice is wrong)

Grading rule (strict set match):
- `is_correct = (set(user) == set(correct))`
- Multi-select does **not** get partial credit; if needed, mention partial overlap in `feedback`.

Edge cases:
- Unanswered: `user: []`, `is_correct: false`, `error_label: "unanswered"`
- Wrong format (e.g. non-letters): normalize; if empty after normalization, treat as unanswered
- Single-select question with multiple letters: grade as incorrect; `error_label: "format-error"`

`error_label` suggestions:
- `"knowledge-gap"` (doesn’t know concept)
- `"confusion-similar"` (confused with similar word/kanji/grammar)
- `"careless"` (misread, missed negation, etc.)
- `"overgeneralization"` (applied rule too broadly)
- `"unanswered"`
- `"format-error"`

### 5) `summary` (exactly one; last line)

Required fields:
- `type`: `"summary"`
- `total`: integer
- `correct_count`: integer
- `wrong_count`: integer
- `wrong_qnums`: array of integers
- `top_error_labels`: object label->count
- `top_concepts_wrong`: array of objects `{concept_id, wrong_count}`

## Wrongbook Schema (practice/wrongbook.jsonl)

One line per `concept_id` aggregated across sessions (not per question instance).

Required fields:
- `concept_id`
- `attempts`: integer
- `wrong`: integer
- `last_seen`: ISO8601 timestamp (use the session’s `meta.created_at`)
- `last_session_id`: string
- `last_example`: object with `{prompt, options, correct, explanation, tags}`

### Wrongbook Update Rules

- Aggregate by `concept_id` across sessions (not by `qnum`).
- Increment `attempts` for every graded question that has the concept.
- Increment `wrong` only when `is_correct` is `false`.
- Update `last_seen`, `last_session_id`, and `last_example` only on wrong answers.
- Keep the wrongbook focused: store only entries with `wrong >= 1`.
- Default rebuild scope: use the most recent `N<=5` session files unless the user requests otherwise.

## Optional Tooling

If you want a deterministic wrongbook rebuild from the most recent sessions, you can run:

`python3 skills/language-learning-quizzer/scripts/build_wrongbook.py --sessions-dir practice/sessions --limit 5 --out practice/wrongbook.jsonl`

## Workflow (strict)

1. Load inputs (files) and the most recent `N<=5` sessions if present.
2. Identify weak concepts (prior wrongbook + recent wrong `grading` entries).
3. Generate the batch quiz (do not reveal answers).
4. Generate and store the answer key immediately (as `question.correct` in JSONL).
5. Deliver the quiz:
   - **Interactive mode (default):** for `qnum=1..N`, show exactly one question, collect a single answer, validate, append a `response` line, then append its `grading` line and give short feedback immediately.
   - **Batch mode:** ask learner to submit a single JSON mapping answers; append one `submission` line.
6. Grade strictly against stored key; never “adjust” the key post-hoc.
   - Interactive: grade each question immediately after its `response`.
   - Batch: grade after `submission`.
7. Append `summary` as the last line after all `grading` entries exist.
8. Update `practice/wrongbook.jsonl`.
9. Provide grouped feedback: cluster errors by `concept_id`, `error_label`, and common confusions.
   - Start with: top 3 `concept_id` by wrong count
   - Then: top `error_label` patterns
   - For each cluster: give a short “rule of thumb” and 2–3 micro-drills the learner can do next

## Quiz Generation Constraints (quality)

- Each question targets **one primary concept** and sets `concept_id` accordingly.
- Each printed question must explicitly label **single-select** vs **multi-select** (e.g. `（单选）` / `（多选）`).
- Options must be plausible; distractors should represent common confusions.
- For single-select: exactly 1 correct option.
- For multi-select: 2 correct options by default; ensure distractors are clearly wrong.
- Avoid trick wording; difficulty comes from concept, not ambiguity.
- Keep prompts short; include minimal context.
- Always provide exactly 4 options `A..D`; avoid “All/None of the above”.

## Answer Submission Template (what to print)

Interactive mode (default): after printing **one** question, ask the learner to reply with:
- Single-select: `A` / `B` / `C` / `D`
- Multi-select: `A,C` (comma-separated) or `AC` (letters in any order)

Batch mode: after printing the full quiz, print:

- A reminder: “Reply once with JSON; keys are question numbers as strings; values are arrays of letters.”
- A JSON skeleton with all keys present, e.g.:

```json
{
  "1": ["A"],
  "2": ["B", "D"],
  "3": ["C"]
}
```

## Common Mistakes (and how to prevent)

- **Leaking answers early**: Never show `correct` or `explanation` until after the learner has answered that question (interactive) or until after the batch submission (batch).
- **Changing answer key after seeing user answers**: Prohibited. Grade against the stored key.
- **Inconsistent numbering**: Use `qnum` 1..N everywhere; submission keys must match.
- **Invalid JSON**: If the learner submission isn’t valid JSON, ask them to resend with valid JSON only.
- **Multi-select ambiguity**: State clearly in each question whether it is single- or multi-select.

## Red Flags — STOP and Fix

- “I should tweak the answer key because the learner’s choice seems reasonable.”
- “I’ll just grade informally without writing the JSONL.”
- “I can skip wrongbook update this time.”
- “I’ll change question numbering mid-session.”
- “I’ll reveal the correct options to help them answer faster.”
- “I’ll regenerate a ‘better’ quiz after seeing their answers (same session).”

## Pressure Scenarios (tests for this skill)

Use these to verify compliance:

1. **Time pressure**: Learner asks “just give me 50 questions fast”.
   - Must still create a valid session JSONL schema and fixed answer key.
2. **Authority pressure**: Learner insists “your answer is wrong; change it”.
   - Must not change stored key; explain and, if needed, propose a follow-up clarifying note as a new question in a new session.
3. **Messy input**: Input is a long log with mixed languages and typos.
   - Must extract a small set of concepts, tag them, and generate coherent MCQ.

## End-to-End Example (minimal)

1) You store 5 questions numbered 1..5 in `practice/sessions/session-YYYYMMDD-HHMM.jsonl` (with `question.correct` fixed).

2) Interactive mode: you show one question, the learner answers, you immediately grade and continue:

```
1. （单选）Choose the correct meaning of 「相手」:
   A. envelope
   B. opponent / partner
   C. weather
   D. promise
```

Learner answers: `B`

You append a `response` line, then a `grading` line for q1, and show brief feedback.

3) Batch mode: learner submits:

```json
{"1":["A"],"2":["B","D"],"3":["C"],"4":["A"],"5":["B"]}
```

4) You write:
- `practice/sessions/session-YYYYMMDD-HHMM.jsonl` containing `meta`, 5 `question`s, (`response`s and/or `submission`), 5 `grading`s, `summary`
- `practice/wrongbook.jsonl` updated from wrong `grading`s
