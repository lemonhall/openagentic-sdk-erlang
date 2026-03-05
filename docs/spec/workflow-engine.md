# OpenAgentic Local Control Plane & Workflow Engine (DSL-first)

> Canonical spec (English). 中文版见：`docs/spec/workflow-engine.zh_ch.md`.
>
> Related (future): Remote subagents protocol (HTTP+SSE) is documented but **not required for v1**:
> - `docs/spec/agent-host-protocol.md`
> - `docs/spec/agent-host-protocol.zh_ch.md`

## 1. Problem statement

We want a “multi-agent bureaucracy” (三省六部) where:

- Some steps are **non-skippable** (AI cannot jump ahead).
- Work is **routed**: Step A must run, then its output must be reviewed by Step B, then forwarded to Step C, etc.
- The system has a **control plane**: start/stop/status/cancel, crash recovery, and observability.

We already have an Agent runtime/tool-loop. What’s missing is:

1) A **local control plane** (OTP supervision + operational API).
2) A **hard workflow engine** that schedules agents and enforces step order via a DSL.

This doc specifies the v1 architecture and a DSL that can be implemented in Erlang first and shared across sibling projects later.

Schema reference (acceptance baseline):
- `docs/spec/workflow-dsl-schema.md`
- `docs/spec/workflow-dsl-schema.zh_ch.md`

## 2. Core principles

- **Workflow engine owns the schedule**: agents do not decide what runs next.
- **Session/event log is the source of truth**: processes are replaceable cursors.
- **Hard gates**: progression requires passing explicit guards (contracts/evidence), not “best effort”.
- **Auditability**: every step produces artifacts/evidence, persisted in the same event stream.
- **Safe defaults**: read-only tooling can be auto-approved; destructive tools require explicit policy.

## 3. Local control plane (OTP)

### 3.1 Recommended supervision tree (single machine)

For each workflow instance:

- `workflow_instance_sup` (supervisor)
  - `workflow_engine` (gen_statem): executes the workflow state machine
  - `agent_pool_sup` (supervisor): manages role agents for this instance
    - `role_agent` (gen_server/gen_statem): runs the LLM runtime for a specific role

A top-level `workflow_manager` (one per node) provides:

- Create/start/resume/cancel workflow instances
- Lookup instance status
- Enforce concurrency limits

### 3.2 Control plane API (conceptual)

Minimum operations:

- `start(workflow_name, input, opts) -> {ok, workflow_id}`
- `resume(workflow_id) -> ok`
- `status(workflow_id) -> #{state := ..., current_step := ..., last_seq := ...}`
- `cancel(workflow_id, reason) -> ok`

CLI-facing (optional):

- `/workflows` list available DSL definitions
- `/run <workflow> ...` start
- `/status <id>`
- `/cancel <id>`

### 3.3 Crash recovery

Recovery should be deterministic:

- `workflow_engine` reconstructs its state by replaying persisted events.
- `role_agent` can be restarted and resume from the same `session_id`.
- Idempotency: repeated attempts must not re-run the same side-effectful tool call unless explicitly allowed.

## 4. Event model (workflow-level)

We reuse the existing session event log (`events.jsonl`) and append workflow-specific events.

Suggested new event types (v1):

- `workflow.init` — workflow started (includes `workflow_id`, `workflow_name`, DSL hash, inputs)
- `workflow.step.start` — step started (includes `step_id`, `role`, attempt)
- `workflow.step.output` — structured step output (or artifact reference)
- `workflow.guard.fail` — guard failed (includes reasons)
- `workflow.step.pass` — step accepted
- `workflow.transition` — state transition (from/to)
- `workflow.cancelled` — cancellation requested/acknowledged
- `workflow.done` — completed (includes final artifacts)

Guidelines:

- Each workflow instance SHOULD have a stable `workflow_id`.
- Each step run SHOULD include `attempt` and a stable `step_run_id`.
- Large payloads SHOULD be stored as artifacts and referenced.

## 5. DSL overview

### 5.1 File format

We want “DSL-first”. To keep implementations simple across languages:

- Canonical data model is JSON.
- YAML is allowed as an alternate serialization (same schema), but not required for v1 implementation.

Suggested locations:

- `workflows/<name>.json` (or `.yaml`)
- `workflows/prompts/<step_id>.md` (optional prompt templates)

### 5.2 Top-level schema (v1)

```json
{
  "workflow_version": "1.0",
  "name": "three-provinces-six-ministries.v1",
  "description": "Draft → Review → Dispatch → Implement → Verify",
  "roles": {
    "draft": { "purpose": "write plan/spec" },
    "review": { "purpose": "reject/approve with rules" },
    "dispatch": { "purpose": "split work into tasks" },
    "implement": { "purpose": "make changes" },
    "verify": { "purpose": "run checks and validate evidence" }
  },
  "steps": [
    {
      "id": "draft_plan",
      "role": "draft",
      "input": { "type": "controller_input" },
      "prompt": { "type": "inline", "text": "Write a plan with DoD..." },
      "output_contract": { "type": "markdown_sections", "required": ["Plan", "DoD"] },
      "guards": [
        { "type": "max_words", "value": 800 }
      ],
      "on_pass": "review_plan",
      "on_fail": "draft_plan"
    },
    {
      "id": "review_plan",
      "role": "review",
      "input": { "type": "step_output", "step_id": "draft_plan" },
      "prompt": { "type": "inline", "text": "Approve or reject with reasons..." },
      "output_contract": { "type": "decision", "allowed": ["approve", "reject"] },
      "guards": [
        { "type": "decision_requires_reasons", "when": "reject" }
      ],
      "on_pass": "dispatch_tasks",
      "on_fail": "draft_plan"
    }
  ]
}
```

### 5.3 Step fields (semantics)

Each step defines:

- **who**: `role`
- **what**: `prompt` (inline text or file reference)
- **input binding**: `input` (controller input, previous step output, selected events, artifact)
- **output contract**: `output_contract` (hard requirement)
- **guards**: machine-checkable validations
- **transitions**: `on_pass` / `on_fail` (explicit)

### 5.4 Guards (v1 minimal set)

Guards must be deterministic and runnable without the model:

- `markdown_sections(required=[...])`
- `json_schema(schema=...)` (optional, if a JSON schema library exists)
- `regex_must_match(pattern=...)`
- `max_words(value=...)`
- `requires_evidence(commands=[...])` (declares what must be present in events)

Important: `requires_evidence` does not itself run commands; it asserts that the workflow produced evidence (e.g., a `verify` step must record a `rebar3 eunit` result).

### 5.5 Tool policy per role/step (recommended)

The workflow engine should be able to configure runtime permissions per role or per step:

- default: read-only tools auto-approved
- implement steps: allow `Write/Edit` only if explicitly declared
- verify steps: allow shell execution only if declared

This can be expressed as:

```json
{ "tool_policy": { "mode": "default", "allow": ["Read","Grep"], "deny": ["Bash"] } }
```

## 6. Execution semantics

For each step:

1) Bind input (from controller input + previous outputs + selected events)
2) Start role agent with a deterministic “system prompt” derived from role + step
3) Run agent until it returns a structured output (or times out)
4) Evaluate output contract + guards
5) Append workflow events (`step.start`, `step.output`, `step.pass`/`guard.fail`)
6) Transition to next step

Key constraints:

- The engine, not the agent, decides transitions.
- A rejected step loops back explicitly (`on_fail`).
- The engine enforces `max_attempts` / `timeout`.

## 7. Mapping “三省六部” to a workflow

One practical mapping (v1, aligned with the diagram):

- 太子 (Triage/Relay): normalize the emperor’s request into an “edict” and hand off to 中书省; later produce the final reply.
- 中书省 (Plan/Decompose): produce overall plan + task decomposition + DoD.
- 门下省 (Review/Gate): hard approve/reject with required change list.
- 尚书省 (Dispatch/Coordinate): dispatch tasks to ministries and aggregate their outputs.
- 六部 (Specialists):
  - 户部: data/facts/lists
  - 礼部: docs/presentation
  - 兵部: engineering execution (code/system)
  - 刑部: compliance/risk gates
  - 工部: infrastructure/tooling
  - 吏部: collaboration/roles/policy

Parallelism can be added later by allowing a step to spawn sub-steps; v1 can stay sequential.

Example DSL (fixture, not wired into code yet):
- `workflows/three-provinces-six-ministries.v1.json`

## 8. Future: remote executors (kept as archived spec)

When local execution is stable, steps can optionally use a remote executor:

- `executor = local_otp` (v1)
- `executor = http_sse_remote` (future; uses `docs/spec/agent-host-protocol.md`)

The workflow DSL should allow choosing executor per step without changing workflow semantics.
