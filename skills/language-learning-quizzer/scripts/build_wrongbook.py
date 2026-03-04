#!/usr/bin/env python3
import argparse
import json
import os
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SESSION_RE = re.compile(r"^session-(\d{8}-\d{4})\.jsonl$")


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _iter_jsonl(path: Path):
    with path.open("r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError as e:
                raise SystemExit(f"{path}:{line_num}: invalid JSON: {e}") from e


def _normalize_letters(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        letters = list(value)
    elif isinstance(value, list):
        letters = []
        for item in value:
            if not isinstance(item, str):
                continue
            letters.extend(list(item))
    else:
        return []
    allowed = {"A", "B", "C", "D"}
    normalized = []
    for ch in letters:
        ch = ch.strip().upper()
        if ch in allowed:
            normalized.append(ch)
    return sorted(set(normalized))


@dataclass
class WrongbookEntry:
    concept_id: str
    attempts: int = 0
    wrong: int = 0
    last_seen: str = ""
    last_session_id: str = ""
    last_example: dict[str, Any] | None = None


def _find_recent_sessions(sessions_dir: Path, limit: int) -> list[Path]:
    candidates: list[tuple[str, Path]] = []
    if not sessions_dir.exists():
        return []
    for p in sessions_dir.iterdir():
        if not p.is_file():
            continue
        m = SESSION_RE.match(p.name)
        if not m:
            continue
        candidates.append((m.group(1), p))
    candidates.sort(key=lambda t: t[0])
    return [p for _, p in candidates[-limit:]]


def build_wrongbook(sessions: list[Path]) -> dict[str, WrongbookEntry]:
    # Index questions by (session_id, qnum) so grading can attach examples.
    questions: dict[tuple[str, int], dict[str, Any]] = {}
    wrongbook: dict[str, WrongbookEntry] = {}

    for session_path in sessions:
        session_id = SESSION_RE.match(session_path.name).group(1)  # type: ignore[union-attr]
        session_created_at: str | None = None
        for obj in _iter_jsonl(session_path):
            if not isinstance(obj, dict):
                continue
            typ = obj.get("type")
            if typ == "meta":
                created_at = obj.get("created_at")
                if isinstance(created_at, str) and created_at.strip():
                    session_created_at = created_at
            elif typ == "question":
                qnum = obj.get("qnum")
                if isinstance(qnum, int):
                    questions[(session_id, qnum)] = obj
            elif typ == "grading":
                qnum = obj.get("qnum")
                if not isinstance(qnum, int):
                    continue
                question = questions.get((session_id, qnum), {})
                concept_id = question.get("concept_id") or obj.get("concept_id")
                if not isinstance(concept_id, str) or not concept_id.strip():
                    concept_id = "unknown"

                entry = wrongbook.get(concept_id)
                if entry is None:
                    entry = WrongbookEntry(concept_id=concept_id)
                    wrongbook[concept_id] = entry

                entry.attempts += 1
                is_correct = obj.get("is_correct")
                if is_correct is False:
                    entry.wrong += 1
                    entry.last_seen = session_created_at or _utc_now_iso()
                    entry.last_session_id = session_id
                    entry.last_example = {
                        "prompt": question.get("prompt"),
                        "options": question.get("options"),
                        "correct": _normalize_letters(question.get("correct")),
                        "explanation": question.get("explanation"),
                        "tags": question.get("tags") if isinstance(question.get("tags"), list) else [],
                    }

    return wrongbook


def main() -> int:
    parser = argparse.ArgumentParser(description="Build practice/wrongbook.jsonl from recent session JSONL files.")
    parser.add_argument("--sessions-dir", default="practice/sessions", help="Directory containing session-*.jsonl")
    parser.add_argument("--limit", type=int, default=5, help="Use most recent N sessions (1..5 recommended)")
    parser.add_argument("--out", default="practice/wrongbook.jsonl", help="Output wrongbook JSONL path")
    args = parser.parse_args()

    sessions_dir = Path(args.sessions_dir)
    out_path = Path(args.out)
    limit = int(args.limit)
    if limit <= 0:
        raise SystemExit("--limit must be >= 1")

    sessions = _find_recent_sessions(sessions_dir, limit=limit)
    wrongbook = build_wrongbook(sessions)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = out_path.with_suffix(out_path.suffix + ".tmp")
    with tmp_path.open("w", encoding="utf-8") as f:
        for concept_id in sorted(wrongbook.keys()):
            entry = wrongbook[concept_id]
            if entry.wrong <= 0:
                continue
            obj = {
                "concept_id": entry.concept_id,
                "attempts": entry.attempts,
                "wrong": entry.wrong,
                "last_seen": entry.last_seen,
                "last_session_id": entry.last_session_id,
                "last_example": entry.last_example,
            }
            f.write(json.dumps(obj, ensure_ascii=False) + "\n")
    os.replace(tmp_path, out_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
