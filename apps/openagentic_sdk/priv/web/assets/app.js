const $ = (id) => document.getElementById(id);

const stepIds = [
  "taizi_route",
  "taizi_solo",
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
  updateCasesLink();
}

function setModeHint(text) {
  const el = $("modeHint");
  if (!el) return;
  el.textContent = text;
}

function updateCasesLink() {
  const link = $("navCasesLink");
  if (!link) return;
  const baseHref = "/view/cases.html";
  const hasSession = Boolean(state.workflowSessionId);
  link.href = hasSession
    ? `${baseHref}?workflow_session_id=${encodeURIComponent(state.workflowSessionId)}`
    : baseHref;
  link.title = hasSession ? "前往 Cases，可直接从当前 Workflow 立案" : "前往 Cases，处理案卷与任务";
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
  addWorkspaceDocLinks(el, text);
  chat.appendChild(el);
  chat.scrollTop = chat.scrollHeight;
  return el;
}

function extractWorkspaceRefs(text) {
  const s = typeof text === "string" ? text : String(text ?? "");
  const refs = [];
  const re = /workspace:[^\s`"'<>]+/g;
  for (const m of s.matchAll(re)) {
    let ref = m[0];
    // Trim trailing punctuation commonly attached in prose.
    ref = ref.replace(/[)\],.;:，。；：）》】”]+$/g, "");
    if (!ref.startsWith("workspace:")) continue;
    if (!refs.includes(ref)) refs.push(ref);
  }
  return refs;
}

function addWorkspaceDocLinks(msgEl, text) {
  const sid = state.workflowSessionId;
  if (!sid) return;
  const refs = extractWorkspaceRefs(text);
  if (!refs.length) return;

  const actions = msgEl.querySelector(".actions");
  for (const ref of refs) {
    const a = document.createElement("a");
    a.className = "btn";
    a.target = "_blank";
    a.rel = "noopener";
    a.href = `/view/workspace.html?sid=${encodeURIComponent(sid)}&path=${encodeURIComponent(ref)}`;
    a.textContent = `打开文档：${ref}`;
    actions.appendChild(a);
  }
}

function prettyJson(str) {
  try {
    return JSON.stringify(JSON.parse(str), null, 2);
  } catch {
    return str;
  }
}

function truncateText(text, maxChars = 8000) {
  if (text == null) return "";
  const s = typeof text === "string" ? text : String(text);
  if (s.length <= maxChars) return s;
  return s.slice(0, maxChars) + `\n…truncated, total=${s.length} chars)`;
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
    setModeHint("提示：SSE 已断开（可刷新页面或重新开跑）");
  };
  es.onmessage = (e) => {
    // Some events may come as default message; try parse anyway.
    tryHandleEvent(e.data);
  };
  es.addEventListener("system.init", (e) => tryHandleEvent(e.data));
  es.addEventListener("workflow.init", (e) => tryHandleEvent(e.data));
  es.addEventListener("workflow.run.start", (e) => tryHandleEvent(e.data));
  es.addEventListener("workflow.controller.message", (e) => tryHandleEvent(e.data));
  es.addEventListener("workflow.step.start", (e) => tryHandleEvent(e.data));
  es.addEventListener("workflow.step.pass", (e) => tryHandleEvent(e.data));
  es.addEventListener("workflow.step.output", (e) => tryHandleEvent(e.data));
  es.addEventListener("workflow.guard.fail", (e) => tryHandleEvent(e.data));
  es.addEventListener("workflow.transition", (e) => tryHandleEvent(e.data));
  es.addEventListener("workflow.cancelled", (e) => tryHandleEvent(e.data));
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
  if (type === "system.init") {
    const cwd = ev.cwd || "";
    addMsg("system", `system.init${cwd ? `\ncwd=${cwd}` : ""}`);
    return;
  }
  if (type === "workflow.init") {
    const name = ev.workflow_name || "";
    const dsl = ev.dsl_path || "";
    addMsg("system", `workflow.init${name ? `\nname=${name}` : ""}${dsl ? `\ndsl=${dsl}` : ""}`);
    return;
  }
  if (type === "workflow.controller.message") {
    // A "continue" message appended to the workflow session. This may arrive even if the UI wasn't the sender.
    addMsg("you", ev.text || "");
    return;
  }
  if (type === "workflow.step.start") {
    setStep(ev.step_id, "running");
    addMsg(ev.role || "step", `寮€濮嬶細${ev.step_id} (attempt=${ev.attempt})`);
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
  if (type === "workflow.transition") {
    const from = ev.from_step_id || "";
    const to = ev.to_step_id || "(end)";
    const outcome = ev.outcome || "";
    const reason = ev.reason || "";
    addMsg("system", truncateText(`transition: ${from} -> ${to}\noutcome=${outcome}${reason ? `\nreason=${reason}` : ""}`));
    return;
  }
  if (type === "workflow.cancelled") {
    setOverall("canceled");
    addMsg("system", truncateText(`workflow.cancelled\nstep_id=${ev.step_id || ""}\nreason=${ev.reason || ""}`));
    return;
  }
  if (type === "workflow.step.output") {
    const who = `杈撳嚭 路 ${ev.step_id}`;
    const fmt = ev.output_format || "text";
    const body = fmt === "json" ? prettyJson(ev.output) : ev.output;
    addMsg(who, truncateText(body));
    return;
  }
  if (type === "workflow.step.event") {
    const se = ev.step_event || {};
    if (se.type === "user.question") {
      const qid = se.question_id;
      const prompt = se.prompt || "";
      const choices = se.choices || [];
      const msgEl = addMsg(`HITL 路 ${ev.step_id}`, `${prompt}\nquestion_id=${qid}`);
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
        `tool.use 路 ${ev.step_id}`,
        truncateText(`${se.name}\n${formatAny(se.input || {})}`)
      );
      return;
    }
    if (se.type === "tool.result" && se.is_error) {
      addMsg(`tool.error 路 ${ev.step_id}`, `${se.error_type}\n${se.error_message}`);
      return;
    }
    if (se.type === "tool.result" && !se.is_error) {
      const out = se.output ?? se.result ?? se.data ?? "";
      const txt = out;
      addMsg(`tool.result 路 ${ev.step_id}`, truncateText(prettyJson(formatAny(txt))));
      return;
    }
    if (se.type === "runtime.error") {
      addMsg(
        `runtime.error 路 ${ev.step_id}`,
        truncateText(`${se.phase || ""}\n${se.error_type || ""}\n${se.error_message || ""}`)
      );
      return;
    }
    if (se.type === "hook.event") {
      addMsg(`hook.event 路 ${ev.step_id}`, truncateText(formatAny(se)));
      return;
    }
    if (se.type === "provider.event") {
      addMsg(`provider.event 路 ${ev.step_id}`, truncateText(formatAny(se.json || se)));
      return;
    }
    if (se.type === "assistant.message") {
      const text = se.text || "";
      const isSummary = se.is_summary ? " (summary)" : "";
      addMsg(`assistant${isSummary} 路 ${ev.step_id}`, truncateText(text));
      return;
    }
    if (se.type === "tool.output_compacted") {
      addMsg(`tool.compacted 路 ${ev.step_id}`, truncateText(formatAny(se)));
      return;
    }
    if (se.type === "result") {
      addMsg(`result 路 ${ev.step_id}`, truncateText(formatAny(se)));
      return;
    }
    // Ignore noisy streaming deltas by default.
    if (se.type === "assistant.delta") return;
    return;
  }
  if (type === "workflow.done") {
    setOverall(ev.status || "done");
    addMsg("done", ev.final_text || "");
    setModeHint("提示：本局已结束；继续输入会在同一局里追加并继续跑（不清空上下文）");
    return;
  }

  // Fallback: show any unknown workflow/session event so nothing "disappears".
  addMsg(`event 路 ${type || "unknown"}`, truncateText(formatAny(ev)));
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

  // If we already have a workflow session, default to continue-in-place.
  if (state.workflowSessionId) {
    $("prompt").value = "";
    addMsg("you", prompt);
    try {
      const wasRunning = state.overall === "starting" || state.overall === "running";
      if (!wasRunning) {
        setOverall("starting");
        setModeHint("提示：继续本局");
      } else {
        addMsg("system", "提示：本局仍在运行，你的输入已排队，稍后自动继续。");
      }

      const res = await postJson("/api/workflows/continue", {
        workflow_session_id: state.workflowSessionId,
        message: prompt,
      });
      state.workflowId = res.workflow_id || state.workflowId;
      state.workflowSessionId = res.workflow_session_id || state.workflowSessionId;
      if (res.workspace_dir) {
        addMsg("system", `workspace_dir=${res.workspace_dir}`);
      }
      if (res.queued) {
        addMsg("system", `queued=true queue_length=${res.queue_length ?? 0}`);
        // Keep current SSE connection; runner will continue after current finishes.
      } else {
        connectSse(res.events_url);
      }
    } catch (err) {
      setOverall("error");
      addMsg("error", err.message || String(err));
    }
    return;
  }

  // Otherwise start a new workflow.
  resetToNewSessionUi();
  setOverall("starting");
  setModeHint("提示：启动新局");
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

async function cancelRun() {
  if (!state.workflowSessionId) {
    addMsg("system", "当前没有可取消的 workflow。");
    return;
  }
  const s = state.overall;
  if (s !== "starting" && s !== "running") {
    addMsg("system", "当前 workflow 未在运行（如需继续，直接发送即可）。");
    return;
  }
  try {
    const sid = state.workflowSessionId;
    addMsg("system", `cancelling workflow_session_id=${sid} ...`);
    await postJson("/api/workflows/cancel", { workflow_session_id: sid });
    setOverall("canceled");
    // Keep SSE connection: it may still deliver buffered events; user can reconnect by sending again.
  } catch (err) {
    setOverall("error");
    addMsg("error", err.message || String(err));
  }
}

$("btnCancel").addEventListener("click", () => cancelRun());
setModeHint("提示：默认在同一局里继续；点“新开一局”才会清空上下文");

