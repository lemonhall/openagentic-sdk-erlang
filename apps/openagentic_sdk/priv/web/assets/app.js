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
  es.onopen = () => setOverall("running");
  es.onerror = () => setOverall("disconnected");
  es.onmessage = (e) => {
    // Some events may come as default message; try parse anyway.
    tryHandleEvent(e.data);
  };
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
      addMsg(`tool.use · ${ev.step_id}`, `${se.name} ${JSON.stringify(se.input || {})}`);
      return;
    }
    if (se.type === "tool.result" && se.is_error) {
      addMsg(`tool.error · ${ev.step_id}`, `${se.error_type}\n${se.error_message}`);
      return;
    }
    return;
  }
  if (type === "workflow.done") {
    setOverall(ev.status || "done");
    addMsg("done", ev.final_text || "");
    return;
  }
}

$("composer").addEventListener("submit", async (e) => {
  e.preventDefault();
  const prompt = $("prompt").value.trim();
  const dsl = $("dslPath").value.trim();
  if (!prompt) return;

  $("prompt").value = "";
  $("chat").innerHTML = "";
  for (const s of stepIds) setStep(s, "pending");
  setOverall("starting");

  addMsg("you", prompt);
  try {
    const res = await postJson("/api/workflows/start", { prompt, dsl });
    state.workflowId = res.workflow_id;
    state.workflowSessionId = res.workflow_session_id;
    addMsg("system", `workflow_id=${state.workflowId}\nworkflow_session_id=${state.workflowSessionId}`);
    connectSse(res.events_url);
  } catch (err) {
    setOverall("error");
    addMsg("error", err.message || String(err));
  }
});

