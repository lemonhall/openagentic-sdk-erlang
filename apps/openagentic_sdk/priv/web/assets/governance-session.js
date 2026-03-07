const el = (id) => document.getElementById(id);

const ui = {
  governanceSubtitle: el("governanceSubtitle"),
  governanceSessionId: el("governanceSessionId"),
  governanceObjectRef: el("governanceObjectRef"),
  governanceContextHint: el("governanceContextHint"),
  governanceTranscript: el("governanceTranscript"),
  governanceSessionForm: el("governanceSessionForm"),
  governancePrompt: el("governancePrompt"),
  governanceStatusHint: el("governanceStatusHint"),
  backToCase: el("backToCase"),
};

const searchParams = new URLSearchParams(window.location.search);

const state = {
  sid: "",
  eventSource: null,
  seenSeqs: new Set(),
  pendingAssistantEl: null,
};

function queryValue(...names) {
  for (const name of names) {
    const value = searchParams.get(name);
    if (value && value.trim()) return value.trim();
  }
  return "";
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function setHint(text, isError = false) {
  ui.governanceStatusHint.textContent = text;
  ui.governanceStatusHint.classList.toggle("errorText", isError);
}

function formatAny(value) {
  if (value == null) return "";
  if (typeof value === "string") return value;
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
}

function formatBody(value) {
  return escapeHtml(formatAny(value)).replaceAll("\n", "<br />");
}

function appendEntry(kind, title, body, meta = "") {
  if (ui.governanceTranscript.classList.contains("empty")) {
    ui.governanceTranscript.className = "entityList";
    ui.governanceTranscript.innerHTML = "";
  }
  const card = document.createElement("article");
  card.className = "entityCard compact";
  const status =
    kind === "user"
      ? "治理指令"
      : kind === "assistant"
        ? "治理回复"
        : kind === "error"
          ? "异常"
          : "事件";
  card.innerHTML = `
    <div class="entityHeader">
      <div>
        <div class="entityTitle">${escapeHtml(title || status)}</div>
        <div class="entityMeta">${escapeHtml(meta)}</div>
      </div>
      <span class="statusChip">${escapeHtml(status)}</span>
    </div>
    <div class="entityBody">${formatBody(body)}</div>
  `;
  ui.governanceTranscript.appendChild(card);
  ui.governanceTranscript.scrollTop = ui.governanceTranscript.scrollHeight;
  return card;
}

function ensurePendingAssistant() {
  if (state.pendingAssistantEl) return state.pendingAssistantEl;
  state.pendingAssistantEl = appendEntry("assistant", "治理回复", "", "streaming");
  return state.pendingAssistantEl;
}

function clearPendingAssistant() {
  state.pendingAssistantEl = null;
}

function updatePendingAssistant(delta) {
  const card = ensurePendingAssistant();
  const body = card.querySelector(".entityBody");
  const current = body.dataset.raw || "";
  const next = `${current}${delta || ""}`;
  body.dataset.raw = next;
  body.innerHTML = formatBody(next);
}

function markSeen(ev) {
  const seq = Number(ev?.seq || ev?.["seq"] || 0);
  if (!Number.isFinite(seq) || seq <= 0) return true;
  if (state.seenSeqs.has(seq)) return false;
  state.seenSeqs.add(seq);
  return true;
}

function renderEvent(ev) {
  if (!markSeen(ev)) return;
  const type = ev?.type || ev?.["type"] || "event";
  switch (type) {
    case "system.init":
      appendEntry("system", "会话初始化", `cwd=${ev.cwd || ""}`);
      return;
    case "user.message":
      appendEntry("user", "治理指令", ev.text || "");
      return;
    case "assistant.delta":
      updatePendingAssistant(ev.text_delta || "");
      return;
    case "assistant.message":
      clearPendingAssistant();
      appendEntry("assistant", "治理回复", ev.text || "");
      return;
    case "user.question": {
      const questionId = ev.question_id || "";
      const choices = Array.isArray(ev.choices) ? ev.choices : [];
      const card = appendEntry("system", "需要人工决断", ev.prompt || "", `question_id=${questionId}`);
      if (questionId && choices.length) {
        const actions = document.createElement("div");
        actions.className = "entityActions";
        for (const choice of choices) {
          const btn = document.createElement("button");
          btn.type = "button";
          btn.className = "btn";
          btn.textContent = String(choice);
          btn.addEventListener("click", async () => {
            try {
              await answerQuestion(questionId, choice);
              setHint(`已提交决断：${choice}`);
              actions.remove();
            } catch (error) {
              setHint(error.message || String(error), true);
            }
          });
          actions.appendChild(btn);
        }
        card.appendChild(actions);
      }
      return;
    }
    case "tool.use":
      appendEntry("system", `调用工具 ${ev.name || ""}`, ev.input || {});
      return;
    case "tool.result":
      appendEntry(ev.is_error ? "error" : "system", `工具结果 ${ev.tool_use_id || ""}`, ev.is_error ? `${ev.error_type || ""}\n${ev.error_message || ""}` : ev.output || {});
      return;
    case "runtime.error":
      appendEntry("error", ev.error_type || "RuntimeError", ev.error_message || "");
      return;
    default:
      clearPendingAssistant();
      appendEntry("system", type, ev);
  }
}

function connectSse(sid) {
  if (state.eventSource) {
    state.eventSource.close();
    state.eventSource = null;
  }
  const es = new EventSource(`/api/sessions/${encodeURIComponent(sid)}/events`);
  state.eventSource = es;
  const onData = (data) => {
    if (!data) return;
    try {
      renderEvent(JSON.parse(data));
    } catch {
      appendEntry("error", "事件解析失败", data);
    }
  };
  es.onmessage = (event) => onData(event.data);
  [
    "system.init",
    "user.message",
    "assistant.delta",
    "assistant.message",
    "user.question",
    "tool.use",
    "tool.result",
    "runtime.error",
    "result",
  ].forEach((type) => {
    es.addEventListener(type, (event) => onData(event.data));
  });
  es.onerror = () => {
    setHint("治理事件流已断开，稍后可继续发送治理指令重连。", true);
  };
}

async function fetchJson(url, options = {}) {
  const response = await fetch(url, options);
  const text = await response.text();
  let data;
  try {
    data = text ? JSON.parse(text) : {};
  } catch {
    data = { raw: text };
  }
  if (!response.ok) {
    throw new Error(data.error || `HTTP ${response.status}`);
  }
  return data;
}

async function postJson(url, body) {
  return fetchJson(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body || {}),
  });
}

async function answerQuestion(questionId, answer) {
  return postJson("/api/questions/answer", { question_id: questionId, answer });
}

function buildObjectRef() {
  const parts = [];
  const caseId = queryValue("case_id", "caseId");
  const candidateId = queryValue("candidate_id", "candidateId");
  const taskId = queryValue("task_id", "taskId");
  const mode = queryValue("mode") || "governance";
  if (caseId) parts.push(`case=${caseId}`);
  if (candidateId) parts.push(`candidate=${candidateId}`);
  if (taskId) parts.push(`task=${taskId}`);
  parts.push(`mode=${mode}`);
  return parts.join(" ; ");
}

function applyContext() {
  const sid = queryValue("sid", "session_id", "sessionId");
  const title = queryValue("title") || "聊天式治理 / 审议会话";
  const caseId = queryValue("case_id", "caseId");
  state.sid = sid;
  ui.governanceSubtitle.textContent = title;
  ui.governanceSessionId.textContent = sid || "";
  ui.governanceObjectRef.textContent = buildObjectRef() || "未指定";
  ui.backToCase.href = caseId ? `/view/cases.html?case_id=${encodeURIComponent(caseId)}` : "/view/cases.html";
  if (!sid) {
    setHint("缺少 sid，无法打开治理会话。", true);
    ui.governancePrompt.disabled = true;
    return false;
  }
  return true;
}

async function continueGovernance(message) {
  return postJson(`/api/sessions/${encodeURIComponent(state.sid)}/query`, { message });
}

ui.governanceSessionForm?.addEventListener("submit", async (event) => {
  event.preventDefault();
  const message = ui.governancePrompt.value.trim();
  if (!message) {
    setHint("请输入治理指令。", true);
    return;
  }
  try {
    ui.governancePrompt.disabled = true;
    setHint("治理会话进行中，请稍候...");
    await continueGovernance(message);
    ui.governancePrompt.value = "";
    setHint("治理回复已返回，可继续追问或修订。", false);
  } catch (error) {
    setHint(error.message || String(error), true);
  } finally {
    ui.governancePrompt.disabled = false;
    ui.governancePrompt.focus();
  }
});

function init() {
  if (!applyContext()) return;
  connectSse(state.sid);
}

void init();
