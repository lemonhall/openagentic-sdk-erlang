const el = (id) => document.getElementById(id);

const ui = {
  taskSummary: el("taskSummary"),
  taskVersions: el("taskVersions"),
  taskAuthorization: el("taskAuthorization"),
  taskRuns: el("taskRuns"),
  taskArtifacts: el("taskArtifacts"),
  credentialBindingForm: el("credentialBindingForm"),
  bindingSlotName: el("bindingSlotName"),
  bindingType: el("bindingType"),
  bindingProvider: el("bindingProvider"),
  bindingStatus: el("bindingStatus"),
  bindingMaterialRef: el("bindingMaterialRef"),
  btnActivateTask: el("btnActivateTask"),
  taskGovernanceLink: el("taskGovernanceLink"),
  taskDetailHint: el("taskDetailHint"),
  backToCase: el("backToCase"),
};

const params = new URLSearchParams(window.location.search);

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function setHint(text, isError = false) {
  ui.taskDetailHint.textContent = text;
  ui.taskDetailHint.classList.toggle("errorText", isError);
}

function queryValue(...names) {
  for (const name of names) {
    const value = params.get(name);
    if (value && value.trim()) return value.trim();
  }
  return "";
}

function caseId() {
  return queryValue("case_id", "caseId");
}

function taskId() {
  return queryValue("task_id", "taskId");
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

function governanceHref(task) {
  const sid = task?.links?.governance_session_id || "";
  const cid = caseId();
  const tid = taskId();
  if (!sid || !cid || !tid) return "/view/cases.html";
  const search = new URLSearchParams({ sid, case_id: cid, task_id: tid, mode: "governance" });
  return `/view/governance-session.html?${search.toString()}`;
}

function renderSummary(detail) {
  const task = detail?.task || {};
  const header = task.header || {};
  const spec = task.spec || {};
  const state = task.state || {};
  ui.taskSummary.className = "overviewCard";
  ui.taskSummary.innerHTML = `
    <div class="overviewTitle">${escapeHtml(spec.title || header.id || "未命名任务")}</div>
    <div class="overviewMeta">任务 ID：<code>${escapeHtml(header.id || "")}</code></div>
    <div class="overviewMeta">状态：${escapeHtml(state.status || "")}</div>
    <div class="overviewMeta">健康：${escapeHtml(state.health || "")}</div>
    <div class="overviewMeta">治理会话：<code>${escapeHtml(task?.links?.governance_session_id || "")}</code></div>
    <div class="overviewSummary">${escapeHtml(spec.mission_statement || "")}</div>
  `;
  ui.taskGovernanceLink.href = governanceHref(task);
  ui.backToCase.href = `/view/cases.html?case_id=${encodeURIComponent(caseId())}`;
}

function renderList(target, items, emptyText, renderer) {
  if (!Array.isArray(items) || !items.length) {
    target.className = "entityList empty";
    target.textContent = emptyText;
    return;
  }
  target.className = "entityList";
  target.innerHTML = items.map(renderer).join("");
}

function renderVersions(detail) {
  renderList(ui.taskVersions, detail?.versions || [], "暂无版本历史", (version) => {
    const header = version.header || {};
    const state = version.state || {};
    const spec = version.spec || {};
    return `
      <article class="entityCard compact">
        <div class="entityHeader">
          <div>
            <div class="entityTitle">${escapeHtml(header.id || "版本")}</div>
            <div class="entityMeta">状态：${escapeHtml(state.status || "")}</div>
          </div>
          <span class="statusChip">${escapeHtml(state.status || "")}</span>
        </div>
        <div class="entityBody">${escapeHtml(spec.objective || "")}</div>
      </article>
    `;
  });
}

function renderAuthorization(detail) {
  const authorization = detail?.authorization || {};
  const bindings = detail?.credential_bindings || [];
  const required = Array.isArray(authorization.required_slots) ? authorization.required_slots : [];
  const missing = Array.isArray(authorization.missing_slots) ? authorization.missing_slots : [];
  const expired = Array.isArray(authorization.expired_slots) ? authorization.expired_slots : [];
  const lines = [
    `<article class="entityCard compact"><div class="entityTitle">授权状态：${escapeHtml(authorization.status || "")}</div><div class="entityBody">必需槽位：${escapeHtml(required.join(", ") || "无")}</div></article>`,
  ];
  if (missing.length) {
    lines.push(`<article class="entityCard compact"><div class="entityTitle">缺失槽位</div><div class="entityBody">${escapeHtml(missing.join(", "))}</div></article>`);
  }
  if (expired.length) {
    lines.push(`<article class="entityCard compact"><div class="entityTitle">已过期槽位</div><div class="entityBody">${escapeHtml(expired.join(", "))}</div></article>`);
  }
  lines.push(
    ...bindings.map((binding) => {
      const spec = binding.spec || {};
      const state = binding.state || {};
      return `
        <article class="entityCard compact">
          <div class="entityHeader">
            <div class="entityTitle">${escapeHtml(spec.slot_name || "未命名槽位")}</div>
            <span class="statusChip">${escapeHtml(state.status || "")}</span>
          </div>
          <div class="entityBody">${escapeHtml(spec.binding_type || "")}${spec.provider ? ` / ${escapeHtml(spec.provider)}` : ""}<br/>${escapeHtml(spec.material_ref || "")}</div>
        </article>
      `;
    })
  );
  ui.taskAuthorization.className = "entityList";
  ui.taskAuthorization.innerHTML = lines.join("");
  if (required.length && !ui.bindingSlotName.value.trim()) {
    ui.bindingSlotName.value = required[0];
  }
}

function renderRuns(detail) {
  renderList(ui.taskRuns, detail?.runs || [], "暂无运行记录", () => "");
}

function renderArtifacts(detail) {
  renderList(ui.taskArtifacts, detail?.artifacts || [], "暂无交付物", () => "");
}

let currentDetail = null;

async function loadDetail() {
  const data = await fetchJson(`/api/cases/${encodeURIComponent(caseId())}/tasks/${encodeURIComponent(taskId())}/detail`);
  currentDetail = data;
  renderSummary(data);
  renderVersions(data);
  renderAuthorization(data);
  renderRuns(data);
  renderArtifacts(data);
  const status = data?.task?.state?.status || "";
  const auth = data?.authorization?.status || status;
  setHint(`当前任务状态：${status}；授权状态：${auth}`);
}

ui.credentialBindingForm?.addEventListener("submit", async (event) => {
  event.preventDefault();
  try {
    setHint("正在保存授权绑定...");
    await postJson(`/api/cases/${encodeURIComponent(caseId())}/tasks/${encodeURIComponent(taskId())}/credential-bindings`, {
      slot_name: ui.bindingSlotName.value.trim(),
      binding_type: ui.bindingType.value.trim(),
      provider: ui.bindingProvider.value.trim(),
      status: ui.bindingStatus.value.trim() || "validated",
      material_ref: ui.bindingMaterialRef.value.trim(),
    });
    await loadDetail();
    setHint("授权绑定已保存。", false);
  } catch (error) {
    setHint(error.message || String(error), true);
  }
});

ui.btnActivateTask?.addEventListener("click", async () => {
  try {
    setHint("正在激活任务...");
    await postJson(`/api/cases/${encodeURIComponent(caseId())}/tasks/${encodeURIComponent(taskId())}/activate`, {});
    await loadDetail();
    setHint("任务已激活。", false);
  } catch (error) {
    setHint(error.message || String(error), true);
  }
});

async function init() {
  if (!caseId() || !taskId()) {
    setHint("缺少 case_id 或 task_id。", true);
    return;
  }
  try {
    await loadDetail();
  } catch (error) {
    setHint(error.message || String(error), true);
  }
}

void init();
