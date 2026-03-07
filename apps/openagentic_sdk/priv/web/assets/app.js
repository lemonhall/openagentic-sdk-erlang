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
  updateFileCaseLink();
}

function setModeHint(text) {
  const el = $("modeHint");
  if (!el) return;
  el.textContent = text;
}

function updateFileCaseLink() {
  const link = $("btnFileCase");
  if (!link) return;
  const baseHref = "/view/cases.html";
  const hasSession = Boolean(state.workflowSessionId);
  link.href = hasSession
    ? `${baseHref}?workflow_session_id=${encodeURIComponent(state.workflowSessionId)}`
    : baseHref;
  const canFileCase =
    hasSession &&
    state.overall !== "idle" &&
    state.overall !== "starting" &&
    state.overall !== "running" &&
    state.overall !== "error" &&
    state.overall !== "canceled";
  link.setAttribute("aria-disabled", canFileCase ? "false" : "true");
  link.title = canFileCase ? "从当前已完成朝议立案" : "先完成一轮朝议，再立案";
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
    ref = ref.replace(/[)\],.;:锛屻€傦紱锛氥€嬨€嶃€忋€慮+$/g, "");
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
    a.textContent = `鎵撳紑鏂囨。锛?{ref}`;
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
  return s.slice(0, maxChars) + `\n鈥?truncated, total=${s.length} chars)`;
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
    setModeHint("鎻愮ず锛氳繍琛屼腑锛堝彲绛夌粨鏉熷悗缁х画杈撳叆锛屾垨鐐光€滄柊寮€涓€灞€鈥濇竻绌轰笂涓嬫枃锛?);
  };
  es.onerror = () => {
    setOverall("disconnected");
    setModeHint("鎻愮ず锛歋SE 鏂紑锛堝埛鏂伴〉闈㈡垨閲嶆柊寮€璺戯級");
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
    addMsg("system", `缁х画鎵ц锛歴tart_step_id=${ev.start_step_id || ""}`);
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
    addMsg("guard", `澶辫触锛?{ev.step_id}\n${(ev.reasons || []).join("\n")}`);
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
    setModeHint("鎻愮ず锛氭湰灞€宸茬粨鏉燂紱缁х画杈撳叆浼氬湪鍚屼竴灞€閲岃拷鍔犲苟缁х画璺戯紙涓嶆竻绌轰笂涓嬫枃锛?);
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
  setModeHint("鎻愮ず锛氬凡娓呯┖涓婁笅鏂囷紱涓嬩竴娆♀€滃彂閫佲€濅細鏂板紑涓€灞€");
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
        setModeHint("鎻愮ず锛氱户缁湰灞€鈥?);
      } else {
        addMsg("system", "鎻愮ず锛氭湰灞€浠嶅湪杩愯锛屼綘鐨勮緭鍏ュ凡鎺掗槦锛岀◢鍚庤嚜鍔ㄧ户缁€?);
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
  setModeHint("鎻愮ず锛氬惎鍔ㄦ柊灞€鈥?);
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
    addMsg("system", "褰撳墠 workflow 姝ｅ湪杩愯锛涜绛夌粨鏉熷悗鍐嶆柊寮€涓€灞€銆?);
    return;
  }
  resetToNewSessionUi();
  addMsg("system", "=== 宸叉竻绌轰笂涓嬫枃锛涗笅涓€娆″彂閫佷細鏂板紑 workflow ===");
}

$("btnNewRun").addEventListener("click", () => startNewRun());

async function cancelRun() {
  if (!state.workflowSessionId) {
    addMsg("system", "褰撳墠娌℃湁鍙彇娑堢殑 workflow銆?);
    return;
  }
  const s = state.overall;
  if (s !== "starting" && s !== "running") {
    addMsg("system", "褰撳墠 workflow 鏈湪杩愯锛堝闇€缁х画锛岀洿鎺ュ彂閫佸嵆鍙級銆?);
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
setModeHint("鎻愮ず锛氶粯璁ゅ湪鍚屼竴灞€閲岀户缁紱鐐光€滄柊寮€涓€灞€鈥濇墠浼氭竻绌轰笂涓嬫枃");

