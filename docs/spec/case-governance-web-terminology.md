# Case Governance Web Terminology

This glossary defines the user-facing labels for the Phase 1 web UI so that one object is not described with multiple names.

| Internal concept | UI label | Notes |
| --- | --- | --- |
| `case` | ?? | Long-lived object handled in the Cases domain. |
| `case_id` | ?? ID | User-facing label; do not show ?Case ID? in Chinese UI. |
| `round_id` | ?? ID | User-facing label for the source round. |
| `candidate` | ???? | Candidate monitoring task before approval. |
| candidate review session | ?? / ???? | Only used during candidate stage. |
| approved / active task | ???? | Approved task in long-running governance. |
| governance session | ???? | Conversation page for formal task stage. |
| `mail` item | ???? | User-facing label for a message item; do not show ????. |
| inbox | ???? | Aggregated entry for all case messages. |

Notes:
- Keep `Workflow` / `Cases` / `Inbox` in the top-level navigation as product-domain names.
- Keep API field names unchanged; only the UI labels are normalized.
