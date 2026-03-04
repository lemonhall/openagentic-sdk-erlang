# Kotlin Parity Backlog (2026-03-04)

> 规则：先写 checklist，再做实现；一次只做一条；完成后立刻回写 evidence。

- [x] `.env` 解析对齐 Kotlin：支持未加引号 value 的 `#` 行内注释；支持 `"value" # comment` 这种“引号后跟注释”的写法（DoD：新增 eunit 覆盖；`OPENAI_API_KEY=abc #x` 解析为 `abc`；`A=" hello " #x` 解析为 ` hello `；门禁 `rebar3 eunit` 通过；Evidence：`rebar3 eunit` → `107 tests, 0 failures`；落地：`apps/openagentic_sdk/src/openagentic_dotenv.erl`、`apps/openagentic_sdk/test/openagentic_dotenv_test.erl`）

- [x] HTTP 对齐 Kotlin（OpenAI Responses）：`base_url.trimEnd('/')` 后再拼接路径，避免 `//responses` 触发重定向；并显式禁用 `httpc` 自动重定向（`autoredirect=false`）以对齐 Kotlin `instanceFollowRedirects=false`（DoD：新增 eunit 覆盖 URL join；门禁 `rebar3 eunit` 通过；Evidence：`rebar3 eunit` → `109 tests, 0 failures`；落地：`apps/openagentic_sdk/src/openagentic_http_url.erl`、`apps/openagentic_sdk/src/openagentic_openai_responses.erl`、`apps/openagentic_sdk/test/openagentic_http_url_test.erl`）
