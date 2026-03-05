const $ = (id) => document.getElementById(id);

const stepIds = [
  "taizi_intake",
  "zhongshu_plan",
  "menxia_review",
  "shangshu_dispatch",
  "hubu_data",
  "libu_docs",
  "bingbu_engineering",
  "xingbu_compliance",
  "gongbu_infra",
  "libu_hr_people",
  "shangshu_aggregate",
  "taizi_reply",
];

const state = {
  workflowId: null,
  workflowSessionId: null,
  overall: "idle",
  stepStatus: Object.fromEntries(stepIds.map((s) => [s, "pending"])),
  eventSource: null,
};

function setOverall(text) {
  state.overall = text;
  $("overallStatus").textContent = text;
}

function setModeHint(text) {
  const el = $("modeHint");
  if (!el) return;
  el.textContent = text;
}

function setStep(stepId, status) {
  if (!stepId || !state.stepStatus[stepId]) return;
  state.stepStatus[stepId] = status;
  const badge = document.querySelector(`[data-badge="${stepId}"]`);
  if (!badge) return;
  badge.classList.remove("running", "done", "failed");
  badge.textContent = status;
  if (status === "running") badge.classList.add("running");
  if (status === "done") badge.classList.add("done");
  if (status === "failed") badge.classList.add("failed");
}

function addMsg(who, text, meta = {}) {
  const chat = $("chat");
  const el = document.createElement("div");
  el.className = "msg";
  const when = new Date().toLocaleTimeString();
  el.innerHTML = `
    <div class="meta">
      <div class="who"></div>
      <div class="when"></div>
    </div>
    <pre class="body"></pre>
    <div class="actions"></div>
  `;
  el.querySelector(".who").textContent = who;
  el.querySelector(".when").textContent = meta.when || when;
  el.querySelector(".body").textContent = text;
  chat.appendChild(el);
  chat.scrollTop = chat.scrollHeight;
  return el;
}

function prettyJson(str) {
  try {
    return JSON.stringify(JSON.parse(str), null, 2);
  } catch {
    return str;
  }
}

async function postJson(url, obj) {
  const res = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(obj),
  });
  const text = await res.text();
  let data = null;
  try {
    data = JSON.parse(text);
  } catch {
    data = { raw: text };
  }
  if (!res.ok) {
    throw new Error(data?.error || `HTTP ${res.status}`);
  }
  return data;
}

function connectSse(eventsUrl) {
  if (state.eventSource) {
    state.eventSource.close();
    state.eventSource = null;
  }
  const es = new EventSource(eventsUrl);
  state.eventSource = es;
  es.onopen = () => {
    setOverall("running");
    setModeHint("提示：运行中（可等结束后继续输入，或点“新开一局”清空上下文）");
  };
  es.onerror = () => {
    setOverall("disconnected");
    setModeHint("提示：SSE 断开（刷新页面或重新开跑）");
  };
  es.onmessage = (e) => {
    // Some events may come as default message; try parse anyway.
    tryHandleEvent(e.data);
  };
  es.addEventListener("workflow.run.start", (e) => tryHandleEvent(e.data));
  es.addEventListener("workflow.step.start", (e) => tryHandleEvent(e.data));
  es.addEventListener("workflow.step.pass", (e) => tryHandleEvent(e.data));
  es.addEventListener("workflow.step.output", (e) => tryHandleEvent(e.data));
  es.addEventListener("workflow.guard.fail", (e) => tryHandleEvent(e.data));
  es.addEventListener("workflow.done", (e) => tryHandleEvent(e.data));
  es.addEventListener("workflow.step.event", (e) => tryHandleEvent(e.data));
}

function tryHandleEvent(jsonLine) {
  let ev = null;
  try {
    ev = JSON.parse(jsonLine);
  } catch {
    return;
  }
  handleEvent(ev);
}

function handleEvent(ev) {
  const type = ev.type;
  if (type === "workflow.run.start") {
    for (const stepId of stepIds) setStep(stepId, "pending");
    setOverall("running");
    addMsg("system", `继续执行：start_step_id=${ev.start_step_id || ""}`);
    return;
  }
  if (type === "workflow.step.start") {
    setStep(ev.step_id, "running");
    addMsg(ev.role || "step", `开始：${ev.step_id} (attempt=${ev.attempt})`);
    return;
  }
  if (type === "workflow.step.pass") {
    setStep(ev.step_id, "done");
    return;
  }
  if (type === "workflow.guard.fail") {
    setStep(ev.step_id, "failed");
    addMsg("guard", `失败：${ev.step_id}\n${(ev.reasons || []).join("\n")}`);
    return;
  }
  if (type === "workflow.step.output") {
    const who = `输出 · ${ev.step_id}`;
    const fmt = ev.output_format || "text";
    const body = fmt === "json" ? prettyJson(ev.output) : ev.output;
    addMsg(who, body);
    return;
  }
  if (type === "workflow.step.event") {
    const se = ev.step_event || {};
    if (se.type === "user.question") {
      const qid = se.question_id;
      const prompt = se.prompt || "";
      const choices = se.choices || [];
      const msgEl = addMsg(`HITL · ${ev.step_id}`, `${prompt}\nquestion_id=${qid}`);
      const actions = msgEl.querySelector(".actions");
      for (const c of choices) {
        const btn = document.createElement("button");
        btn.className = "btn primary";
        btn.type = "button";
        btn.textContent = c;
        btn.onclick = async () => {
          try {
            await postJson("/api/questions/answer", { question_id: qid, answer: c });
            addMsg("you", `answered: ${c} (qid=${qid})`);
          } catch (e) {
            addMsg("error", `answer failed: ${e.message}`);
          }
        };
        actions.appendChild(btn);
      }
      return;
    }
    if (se.type === "tool.use") {
      addMsg(
        `tool.use · ${ev.step_id}`,
        `${se.name}\n${JSON.stringify(se.input || {}, null, 2)}`
      );
      return;
    }
    if (se.type === "tool.result" && se.is_error) {
      addMsg(`tool.error · ${ev.step_id}`, `${se.error_type}\n${se.error_message}`);
      return;
    }
    if (se.type === "tool.result" && !se.is_error) {
      const out = se.output ?? se.result ?? se.data ?? "";
      const txt =
        typeof out === "string" ? out : JSON.stringify(out, null, 2);
      addMsg(`tool.result · ${ev.step_id}`, prettyJson(txt));
      return;
    }
    return;
  }
  if (type === "workflow.done") {
    setOverall(ev.status || "done");
    addMsg("done", ev.final_text || "");
    setModeHint("提示：本局已结束；继续输入会在同一局里追加并继续跑（不清空上下文）");
    return;
  }
}

function resetToNewSessionUi() {
  if (state.eventSource) {
    state.eventSource.close();
    state.eventSource = null;
  }
  state.workflowId = null;
  state.workflowSessionId = null;
  $("chat").innerHTML = "";
  for (const stepId of stepIds) setStep(stepId, "pending");
  setOverall("idle");
  setModeHint("提示：已清空上下文；下一次“发送”会新开一局");
}

$("composer").addEventListener("submit", async (e) => {
  e.preventDefault();
  const prompt = $("prompt").value.trim();
  const dsl = $("dslPath").value.trim();
  if (!prompt) return;

  const s = state.overall;
  if (s === "starting" || s === "running") {
    addMsg("system", "当前 workflow 正在运行；请等结束后再继续输入。");
    return;
  }

  // If we already have a workflow session, default to continue-in-place.
  if (state.workflowSessionId) {
    $("prompt").value = "";
    addMsg("you", prompt);
    try {
      setOverall("starting");
      setModeHint("提示：继续本局…");
    const res = await postJson("/api/workflows/continue", {
      workflow_session_id: state.workflowSessionId,
      message: prompt,
    });
    state.workflowId = res.workflow_id || state.workflowId;
    state.workflowSessionId = res.workflow_session_id || state.workflowSessionId;
    if (res.workspace_dir) {
      addMsg("system", `workspace_dir=${res.workspace_dir}`);
    }
    connectSse(res.events_url);
  } catch (err) {
    setOverall("error");
    addMsg("error", err.message || String(err));
  }
    return;
  }

  // Otherwise start a new workflow.
  resetToNewSessionUi();
  setOverall("starting");
  setModeHint("提示：启动新局…");
  try {
    $("prompt").value = "";
    addMsg("you", prompt);
    const res = await postJson("/api/workflows/start", { prompt, dsl });
    state.workflowId = res.workflow_id;
    state.workflowSessionId = res.workflow_session_id;
    addMsg(
      "system",
      `workflow_id=${state.workflowId}\nworkflow_session_id=${state.workflowSessionId}${
        res.workspace_dir ? `\nworkspace_dir=${res.workspace_dir}` : ""
      }`
    );
    connectSse(res.events_url);
  } catch (err) {
    setOverall("error");
    addMsg("error", err.message || String(err));
  }
});

async function startNewRun() {
  const s = state.overall;
  if (s === "starting" || s === "running") {
    addMsg("system", "当前 workflow 正在运行；请等结束后再新开一局。");
    return;
  }
  resetToNewSessionUi();
  addMsg("system", "=== 已清空上下文；下一次发送会新开 workflow ===");
}

$("btnNewRun").addEventListener("click", () => startNewRun());
setModeHint("提示：默认在同一局里继续；点“新开一局”才会清空上下文");
