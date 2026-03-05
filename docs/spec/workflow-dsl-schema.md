# OpenAgentic Workflow DSL Schema (v1)

> Canonical schema (English). 中文版见：`docs/spec/workflow-dsl-schema.zh_ch.md`.
>
> This document is the acceptance baseline for implementing the local workflow engine described in:
> - `docs/spec/workflow-engine.md`
> - `docs/spec/workflow-engine.zh_ch.md`

## 1. Goals

- Define a **machine-validated** workflow DSL that enforces non-skippable steps.
- Keep the data model simple enough for **cross-language** implementations later.
- Make validation **fail-fast** (bad DSL should not start a workflow).

Non-goals:
- A full general-purpose BPMN engine.
- Dynamic discovery of roles/agents.

## 2. File format & loading rules

- Canonical serialization: **JSON** (UTF-8).
- Optional alternate serialization: YAML (same schema), but v1 implementation may accept JSON only.
- A workflow definition is loaded from a file such as:
  - `workflows/<name>.json`
- Prompt files are resolved relative to repo root (or a configured workflow root):
  - `workflows/prompts/<step_id>.md`

Security:
- Prompt files are plain text/Markdown; do not execute them.
- Never read or log secrets (e.g., `.env`).

## 3. Versioning

- `workflow_version` is a protocol string, v1: `"1.0"`.
- Unknown `workflow_version` MUST be rejected at load time.
- Unknown fields MUST be ignored for forward compatibility **only if** they do not affect semantics; otherwise reject (implementation choice). Recommended: reject unknown fields during v1 to avoid silent misconfig.

## 4. Top-level object

Required fields:
- `workflow_version` (string, must be `"1.0"`)
- `name` (string, stable identifier)
- `steps` (array of `Step`, length >= 1)

Optional fields:
- `description` (string)
- `roles` (object map `role_name -> RoleSpec`)
- `defaults` (Defaults)

### 4.1 `RoleSpec`

```json
{ "purpose": "short description" }
```

Only informational in v1, but may be used to build system prompts later.

### 4.2 `Defaults`

```json
{
  "max_attempts": 3,
  "timeout_seconds": 900,
  "tool_policy": { ... }
}
```

`Defaults` apply to every step unless overridden by the step.

## 5. Step object

Required fields:
- `id` (string; unique within workflow; recommended `[a-z0-9_]+`)
- `role` (string; should exist in `roles` if provided)
- `input` (InputBinding)
- `prompt` (PromptRef)
- `output_contract` (OutputContract)
- `on_pass` (string step id, or `null` to indicate terminal)
- `on_fail` (string step id, or `null` if failure terminates)

Optional fields:
- `guards` (array of Guard; default `[]`)
- `max_attempts` (int >= 1; default from `defaults`)
- `timeout_seconds` (int >= 1; default from `defaults`)
- `tool_policy` (ToolPolicy; default from `defaults`)
- `executor` (string; v1 MUST be `"local_otp"` if present; reserved: `"http_sse_remote"`)

Validation rules:
- All step `id`s must be unique.
- Any `on_pass`/`on_fail` step id must refer to an existing step.
- At least one terminal path must exist (a step with `on_pass=null` or `on_fail=null` reachable).
- Unknown `executor` MUST be rejected.

## 6. InputBinding

Discriminated union by `type`:

### 6.1 `controller_input`

```json
{ "type": "controller_input" }
```

The initial input provided when starting the workflow.

### 6.2 `step_output`

```json
{ "type": "step_output", "step_id": "draft_plan" }
```

Binds to the last accepted output of the referenced step.

### 6.3 `merge`

```json
{
  "type": "merge",
  "sources": [
    { "type": "step_output", "step_id": "a" },
    { "type": "step_output", "step_id": "b" }
  ]
}
```

Concatenates or structured-merges inputs. Implementation choice:
- If all sources are JSON objects → merge keys (later sources override).
- Otherwise → concatenate as text with delimiters.

v1 recommendation: concatenate as text unless a step explicitly requests JSON.

### 6.4 Reserved (future)

Allowed in schema but not required for v1 implementation:
- `artifact_ref`
- `event_query`

Implementations may reject reserved types until implemented.

## 7. PromptRef

Discriminated union by `type`:

### 7.1 `inline`

```json
{ "type": "inline", "text": "..." }
```

### 7.2 `file`

```json
{ "type": "file", "path": "workflows/prompts/draft_plan.md" }
```

Validation:
- `file.path` must exist at workflow load time (recommended) unless `allow_missing_prompts=true` is explicitly configured (v1 default: reject).

## 8. OutputContract

Discriminated union by `type`:

### 8.1 `markdown_sections`

```json
{ "type": "markdown_sections", "required": ["目标","计划"] }
```

Rule: output must contain all required section titles (match `^#+\s+<title>` or other robust heuristics).

### 8.2 `decision`

```json
{
  "type": "decision",
  "allowed": ["approve","reject"],
  "format": "json",
  "fields": ["decision","reasons","required_changes"]
}
```

Rule: output must parse as JSON object and contain required fields.

### 8.3 `json_object`

```json
{ "type": "json_object", "schema_hint": { "tasks": [] } }
```

Rule: output must parse as a JSON object. `schema_hint` is informational (not authoritative).

### 8.4 Reserved (future)

- `json_schema` (strict validation with a JSON schema)
- `artifact_required` (requires producing an artifact reference)

## 9. Guard

Guards are deterministic checks evaluated by the engine after output is produced.

Discriminated union by `type`:

### 9.1 `max_words`

```json
{ "type": "max_words", "value": 900 }
```

### 9.2 `regex_must_match`

```json
{ "type": "regex_must_match", "pattern": "\"tasks\"\\s*:" }
```

### 9.3 `markdown_sections`

Same as output contract, but usable as an extra guard:

```json
{ "type": "markdown_sections", "required": ["DoD"] }
```

### 9.4 `decision_requires_reasons`

```json
{ "type": "decision_requires_reasons", "when": "reject" }
```

Rule: if decision equals `when`, `reasons` and `required_changes` must be non-empty arrays.

### 9.5 `requires_evidence`

```json
{ "type": "requires_evidence", "commands": ["rebar3 eunit"] }
```

Rule: workflow event log must include evidence that these commands were executed in the verify phase.
How evidence is represented is an implementation detail, but the engine must be able to prove it.

Validation rules:
- Unknown guard `type` MUST be rejected at workflow load time (fail-fast).

## 10. ToolPolicy

`tool_policy` controls the permission gate mode for a step/role.

```json
{
  "mode": "default",
  "allow": ["Read", "Grep"],
  "deny": ["Bash"]
}
```

Fields:
- `mode` (string): `default | prompt | deny | bypass`
- `allow` (string[], optional): explicit allowlist additions
- `deny` (string[], optional): explicit denylist additions

Merge rules (recommended):
- Start from runtime defaults.
- Apply workflow `defaults.tool_policy`.
- Apply step `tool_policy` (overrides).

Security note:
- `bypass` is powerful; only allow in trusted environments.

## 11. Example

See fixture:

- `workflows/three-provinces-six-ministries.v1.json`

