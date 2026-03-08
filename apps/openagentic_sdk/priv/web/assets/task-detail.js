const el = (id) => document.getElementById(id);

const ui = {
  taskBreadcrumb: el("taskBreadcrumb"),
  taskPageTitle: el("taskPageTitle"),
  taskPageSummary: el("taskPageSummary"),
  taskNextAction: el("taskNextAction"),
  taskSummary: el("taskSummary"),
  taskVersions: el("taskVersions"),
  taskVersionDiff: el("taskVersionDiff"),
  taskAuthorization: el("taskAuthorization"),
  taskRuns: el("taskRuns"),
  taskRunAttempts: el("taskRunAttempts"),
  taskFactReports: el("taskFactReports"),
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
  taskPrimaryPathHint: el("taskPrimaryPathHint"),
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

function actionItemsMarkup(actions = []) {
  return (Array.isArray(actions) ? actions : [])
    .filter(Boolean)
    .map((action) => {
      const klass = action.primary ? "btn primary" : "btn";
      if (action.type === "button") {
        return `<button type="button" class="${klass}" data-task-action="${escapeHtml(action.action || "")}">${escapeHtml(action.label || "Open")}</button>`;
      }
      return `<a class="${klass}" href="${escapeHtml(action.href || "#")}">${escapeHtml(action.label || "Open")}</a>`;
    })
    .join("");
}

function emptyStateMarkup({ label = "Empty", title = "No Content", body = "", actions = [] } = {}) {
  const actionsHtml = actionItemsMarkup(actions);
  return `
    <div class="emptyState">
      <div class="emptyStateLabel">${escapeHtml(label)}</div>
      <div class="emptyStateTitle">${escapeHtml(title)}</div>
      <div class="emptyStateBody">${escapeHtml(body)}</div>
      ${actionsHtml ? `<div class="emptyStateActions">${actionsHtml}</div>` : ""}
    </div>
  `;
}

function setEmptyState(target, { layout = "entityList empty", label = "Empty", title = "No Content", body = "", actions = [] } = {}) {
  if (!target) return;
  target.className = layout;
  target.innerHTML = emptyStateMarkup({ label, title, body, actions });
}

function summaryMetaMarkup(items = []) {
  const validItems = (Array.isArray(items) ? items : []).filter((item) => item && item.label && item.value);
  if (!validItems.length) return "";
  return `
    <dl class="objectSummaryMeta">
      ${validItems
        .map(
          (item) => `
            <div class="objectSummaryMetaItem">
              <dt>${escapeHtml(item.label)}</dt>
              <dd>${escapeHtml(item.value)}</dd>
            </div>
          `
        )
        .join("")}
    </dl>
  `;
}

function summaryCardMarkup({ title = "Untitled", status = "", summary = "", actions = "", meta = [], compact = true } = {}) {
  const compactClass = compact ? " compact" : "";
  return `
    <article class="entityCard objectSummaryCard${compactClass}">
      <div class="entityHeader">
        <div class="entityTitle">${escapeHtml(title)}</div>
        ${status ? `<span class="statusChip">${escapeHtml(status)}</span>` : ""}
      </div>
      <div class="objectSummarySummary">${escapeHtml(summary || "No summary")}</div>
      ${actions ? `<div class="entityActions">${actions}</div>` : ""}
      ${summaryMetaMarkup(meta)}
    </article>
  `;
}

function overviewFactsMarkup(items = []) {
  const validItems = (Array.isArray(items) ? items : []).filter((item) => item && item.label && item.value != null && item.value !== "");
  if (!validItems.length) return "";
  return `
    <div class="overviewFacts">
      ${validItems
        .map(
          (item) => `
            <div class="overviewFact">
              <div class="overviewFactLabel">${escapeHtml(item.label)}</div>
              <div class="overviewFactValue">${escapeHtml(String(item.value))}</div>
            </div>
          `
        )
        .join("")}
    </div>
  `;
}

function renderNextAction(action) {
  if (!ui.taskNextAction) return;
  const buttons = Array.isArray(action?.buttons) ? action.buttons : [];
  ui.taskNextAction.innerHTML = `
    <div class="caseActionLabel">下一步</div>
    <div class="caseActionTitle">${escapeHtml(action?.title || "先查看任务状态")}</div>
    <div class="caseActionBody">${escapeHtml(action?.body || "先看当前任务状态，再决定下一步。")}</div>
    <div class="caseActionButtons">
      ${buttons
        .map((button) => {
          const klass = button.primary ? "btn primary" : "btn";
          if (button.type === "button") {
            return `<button type="button" class="${klass}" data-task-action="${escapeHtml(button.action || "")}">${escapeHtml(button.label || "操作")}</button>`;
          }
          return `<a class="${klass}" href="${escapeHtml(button.href || "#")}">${escapeHtml(button.label || "查看")}</a>`;
        })
        .join("")}
    </div>
  `;
}

function taskPrimaryPathHint(detail) {
  const status = detail?.task?.state?.status || "";
  const auth = detail?.authorization?.status || status;
  if (auth === "awaiting_credentials" || auth === "reauthorization_required" || auth === "credential_expired") {
    return "任务详情优先：先在此页补权并确认授权缺口，处理完再决定是否回治理会话。";
  }
  if (auth === "ready_to_activate") {
    return "任务详情优先：先在此页确认差异与授权已齐备，再执行激活或进入治理。";
  }
  return "任务详情优先：先在此页确认状态、差异与授权，再决定是否进入治理会话。";
}

function taskPageSummary(detail) {
  const status = detail?.task?.state?.status || "";
  const auth = detail?.authorization?.status || status;
  const diff = detail?.latest_version_diff || {};
  if (auth === "awaiting_credentials" || auth === "reauthorization_required" || auth === "credential_expired") {
    return "当前主任务：先补齐授权，再回来确认任务是否具备重新激活条件。";
  }
  if (auth === "ready_to_activate") {
    return "当前主任务：先看清差异与授权结果，再激活任务。";
  }
  if (diff.to_version_id) {
    return "当前主任务：先看最新版本差异与授权影响，再决定是否继续治理。";
  }
  return "当前主任务：看清当前状态、版本差异与授权结果，再决定是否进入治理。";
}

function deriveNextAction(detail) {
  const task = detail?.task || {};
  const status = task?.state?.status || "";
  const auth = detail?.authorization?.status || status;
  const diff = detail?.latest_version_diff || {};
  const governance = governanceHref(task);

  if (auth === "awaiting_credentials" || auth === "reauthorization_required" || auth === "credential_expired") {
    return {
      title: "先补权",
      body: "当前任务缺少有效授权；先在本页补齐绑定，再决定是否重新激活。",
      buttons: [
        { type: "link", href: "#taskBindingPanel", label: "先补权", primary: true },
        { type: "link", href: "#taskVersionDiffPanel", label: "查看差异" },
      ],
    };
  }

  if (auth === "ready_to_activate") {
    return {
      title: "激活任务",
      body: "授权材料已齐备；确认差异无误后，可以直接激活任务。",
      buttons: [
        { type: "button", action: "activate-task", label: "激活任务", primary: true },
        { type: "link", href: "#taskVersionDiffPanel", label: "查看差异" },
      ],
    };
  }

  if (diff.to_version_id) {
    return {
      title: "先看版本差异",
      body: "当前任务已有最新修订；先确认差异，再决定是否继续治理。",
      buttons: [
        { type: "link", href: "#taskVersionDiffPanel", label: "查看差异", primary: true },
        ...(governance ? [{ type: "link", href: governance, label: "进入治理会话" }] : []),
      ],
    };
  }

  return {
    title: "查看状态结果",
    body: "当前任务已可正常查看；先看状态和授权结果，再决定是否进入治理。",
    buttons: [
      { type: "link", href: "#taskSummaryPanel", label: "查看状态", primary: true },
      ...(governance ? [{ type: "link", href: governance, label: "进入治理会话" }] : []),
    ],
  };
}

function syncTaskShell(detail) {
  const task = detail?.task || {};
  const header = task.header || {};
  const spec = task.spec || {};
  const title = spec.title || header.id || "未命名任务";
  if (ui.taskBreadcrumb) {
    ui.taskBreadcrumb.textContent = `Cases / ${caseId() || "Case"} / ${title}`;
  }
  if (ui.taskPageTitle) {
    ui.taskPageTitle.textContent = title;
  }
  if (ui.taskPageSummary) {
    ui.taskPageSummary.textContent = taskPageSummary(detail);
  }
  if (ui.taskPrimaryPathHint) {
    ui.taskPrimaryPathHint.textContent = taskPrimaryPathHint(detail);
  }
  renderNextAction(deriveNextAction(detail));
}

function renderSummary(detail) {
  const task = detail?.task || {};
  const header = task.header || {};
  const spec = task.spec || {};
  const state = task.state || {};
  if (!header.id && !spec.title) {
    setEmptyState(ui.taskSummary, {
      layout: "overviewCard empty",
      label: "任务状态",
      title: "暂无任务上下文",
      body: "请返回案卷工作台重新选择任务。",
    });
    syncTaskShell(detail);
    return;
  }
  ui.taskSummary.className = "overviewCard";
  ui.taskSummary.innerHTML = `
    <div class="overviewTitle">${escapeHtml(spec.title || header.id || "未命名任务")}</div>
    ${overviewFactsMarkup([
      { label: "任务 ID", value: header.id || "" },
      { label: "状态", value: state.status || "" },
      { label: "健康", value: state.health || "" },
      { label: "治理会话", value: task?.links?.governance_session_id || "" },
    ])}
    <div class="overviewSummary">${escapeHtml(spec.mission_statement || spec.objective || "暂无任务摘要")}</div>
  `;
  ui.taskGovernanceLink.href = governanceHref(task);
  ui.backToCase.href = `/view/cases.html?case_id=${encodeURIComponent(caseId())}`;
  syncTaskShell(detail);
}

function renderList(target, items, emptyState, renderer) {
  if (!Array.isArray(items) || !items.length) {
    setEmptyState(target, {
      label: emptyState?.label || "Empty",
      title: emptyState?.title || "No Content",
      body: emptyState?.body || "",
      actions: emptyState?.actions || [],
    });
    return;
  }
  target.className = "entityList";
  target.innerHTML = items.map(renderer).join("");
}

function renderVersions(detail) {
  renderList(
    ui.taskVersions,
    detail?.versions || [],
    {
      label: "版本历史",
      title: "暂无版本历史",
      body: "如需调整任务定义，可回治理页提交修订。",
    },
    (version) => {
      const header = version.header || {};
      const state = version.state || {};
      const spec = version.spec || {};
      return summaryCardMarkup({
        title: header.id || "版本",
        status: state.status || "",
        summary: spec.objective || spec.summary || "暂无版本摘要",
        meta: [{ label: "版本 ID", value: header.id || "" }],
      });
    }
  );
}

function formatInline(value) {
  if (value == null) return "";
  if (typeof value === "string") return value;
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

function renderLatestVersionDiff(detail) {
  const diff = detail?.latest_version_diff || {};
  const changedFields = Array.isArray(diff.changed_fields) ? diff.changed_fields : [];
  if (!diff.to_version_id || !changedFields.length) {
    setEmptyState(ui.taskVersionDiff, {
      label: "版本差异",
      title: "暂无版本差异",
      body: "当前还没有最新修订差异，可先查看状态或继续治理。",
      actions: [{ type: "link", href: "#taskSummaryPanel", label: "看状态", primary: true }],
    });
    return;
  }
  const cards = [
    summaryCardMarkup({
      title: diff.change_summary || "最新版本修订",
      status: `${String(diff.changed_field_count || changedFields.length)} 项变更`,
      summary: diff.reauthorization_required ? "本次修订引入了新的授权要求，需补齐后再激活。" : "当前修订未引发新的重授权要求。",
      meta: [
        { label: "版本范围", value: `${diff.from_version_id || ""} -> ${diff.to_version_id || ""}` },
        { label: "授权影响", value: diff.reauthorization_required ? "需重授权" : "无额外要求" },
      ],
    }),
    ...changedFields.map((item) => {
      const field = item?.field || "field";
      const fromValue = formatInline(item?.from) || "?";
      const toValue = formatInline(item?.to) || "?";
      return summaryCardMarkup({
        title: field,
        status: "已变更",
        summary: `from: ${fromValue} -> to: ${toValue}`,
      });
    }),
  ];
  if (Array.isArray(diff.newly_required_slots) && diff.newly_required_slots.length) {
    cards.push(
      summaryCardMarkup({
        title: "新增授权槽位",
        status: "auth",
        summary: diff.newly_required_slots.join(", "),
      })
    );
  }
  ui.taskVersionDiff.className = "entityList";
  ui.taskVersionDiff.innerHTML = cards.join("");
}

function renderAuthorization(detail) {
  const authorization = detail?.authorization || {};
  const bindings = detail?.credential_bindings || [];
  const required = Array.isArray(authorization.required_slots) ? authorization.required_slots : [];
  const missing = Array.isArray(authorization.missing_slots) ? authorization.missing_slots : [];
  const expired = Array.isArray(authorization.expired_slots) ? authorization.expired_slots : [];
  if (!authorization.status && !required.length && !bindings.length) {
    setEmptyState(ui.taskAuthorization, {
      label: "授权结果",
      title: "暂无授权信息",
      body: "任务详情加载后，这里会展示必需槽位、缺失项和已有绑定。",
    });
    return;
  }
  const lines = [
    summaryCardMarkup({
      title: `授权状态：${authorization.status || "unknown"}`,
      status: authorization.status || "",
      summary: required.length ? `必需槽位：${required.join(", ")}` : "当前没有额外授权要求。",
    }),
  ];
  if (missing.length) {
    lines.push(summaryCardMarkup({ title: "缺失槽位", status: "missing", summary: missing.join(", ") }));
  }
  if (expired.length) {
    lines.push(summaryCardMarkup({ title: "已过期槽位", status: "expired", summary: expired.join(", ") }));
  }
  const diff = detail?.latest_version_diff || {};
  if (diff.reauthorization_required) {
    const slots = Array.isArray(diff.newly_required_slots) ? diff.newly_required_slots : [];
    lines.push(summaryCardMarkup({ title: "修订后需重授权", status: "reauthorize", summary: `需先补齐：${slots.join(", ") || "请查看缺失槽位"}` }));
  }
  lines.push(
    ...bindings.map((binding) => {
      const spec = binding.spec || {};
      const state = binding.state || {};
      return summaryCardMarkup({
        title: spec.slot_name || "未命名槽位",
        status: state.status || "",
        summary: `${spec.binding_type || ""}${spec.provider ? ` / ${spec.provider}` : ""}`,
        meta: spec.material_ref ? [{ label: "material_ref", value: spec.material_ref }] : [],
      });
    })
  );
  ui.taskAuthorization.className = "entityList";
  ui.taskAuthorization.innerHTML = lines.join("");
  if (required.length && !ui.bindingSlotName.value.trim()) {
    ui.bindingSlotName.value = required[0];
  }
}

function renderRuns(detail) {
  renderList(
    ui.taskRuns,
    detail?.runs || [],
    {
      label: "运行记录",
      title: "暂无运行记录",
      body: "如果任务还未激活，先完成补权或激活。",
    },
    (run) => {
      const header = run?.header || {};
      const state = run?.state || {};
      return summaryCardMarkup({
        title: header.id || "运行记录",
        status: state.status || "",
        summary: formatInline(run?.spec || run?.output || run || "") || "暂无运行输出",
      });
    }
  );
}

function sessionEventsHref(sessionId) {
  if (!sessionId) return "";
  return `/api/sessions/${encodeURIComponent(sessionId)}/events`;
}

function reportLineageSummary(report) {
  const ext = report?.ext || {};
  const lineage = ext.report_lineage_id || "";
  const supersedes = ext.supersedes_report_id || "";
  const supersededBy = ext.superseded_by_report_id || "";
  return [lineage ? `lineage=${lineage}` : "", supersedes ? `supersedes=${supersedes}` : "", supersededBy ? `superseded_by=${supersededBy}` : ""]
    .filter(Boolean)
    .join(" | ");
}

function renderRunAttempts(detail) {
  renderList(
    ui.taskRunAttempts,
    detail?.run_attempts || [],
    {
      label: "Run Attempts",
      title: "No attempts yet",
      body: "Attempt-level execution records appear here after a run starts.",
    },
    (attempt) => {
      const header = attempt?.header || {};
      const state = attempt?.state || {};
      const spec = attempt?.spec || {};
      const links = attempt?.links || {};
      const sessionId = links.execution_session_id || "";
      const meta = [
        { label: "attempt_id", value: header.id || "" },
        { label: "attempt_index", value: spec.attempt_index || "" },
        { label: "execution_session_id", value: sessionId },
        { label: "events", value: sessionEventsHref(sessionId) },
        { label: "scratch_ref", value: links.scratch_ref || "" },
        { label: "failure_class", value: state.failure_class || "" },
      ].filter((item) => item.value);
      return summaryCardMarkup({
        title: header.id || "Run Attempt",
        status: state.status || "",
        summary: state.failure_summary || spec.attempt_reason || "Run attempt recorded",
        meta,
      });
    }
  );
}

function renderFactReports(detail) {
  renderList(
    ui.taskFactReports,
    detail?.fact_reports || [],
    {
      label: "Fact Reports",
      title: "No reports yet",
      body: "Successful monitoring deliveries will appear here with lineage and artifact refs.",
    },
    (report) => {
      const header = report?.header || {};
      const state = report?.state || {};
      const spec = report?.spec || {};
      const links = report?.links || {};
      const meta = [
        { label: "report_id", value: header.id || "" },
        { label: "run_id", value: links.run_id || "" },
        { label: "successful_attempt_id", value: links.successful_attempt_id || "" },
        { label: "report_kind", value: spec.report_kind || "" },
        { label: "lineage", value: reportLineageSummary(report) },
        { label: "artifact_refs", value: Array.isArray(spec.artifact_refs) ? String(spec.artifact_refs.length) : "" },
      ].filter((item) => item.value);
      return summaryCardMarkup({
        title: header.id || "Fact Report",
        status: state.status || "",
        summary: state.quality_summary || state.alert_summary || spec.report_kind || "Formal fact report",
        meta,
      });
    }
  );
}

function renderArtifacts(detail) {
  renderList(
    ui.taskArtifacts,
    detail?.artifacts || [],
    {
      label: "交付物",
      title: "暂无交付物",
      body: "任务运行后的输出会在这里沉淀。",
    },
    (artifact) => {
      const header = artifact?.header || {};
      const spec = artifact?.spec || {};
      return summaryCardMarkup({
        title: spec.title || header.id || "交付物",
        status: spec.kind || "artifact",
        summary: spec.summary || spec.path || formatInline(artifact) || "暂无交付摘要",
        meta: header.id ? [{ label: "artifact_id", value: header.id }] : [],
      });
    }
  );
}

let currentDetail = null;

async function loadDetail() {
  const data = await fetchJson(`/api/cases/${encodeURIComponent(caseId())}/tasks/${encodeURIComponent(taskId())}/detail`);
  currentDetail = data;
  renderSummary(data);
  renderVersions(data);
  renderLatestVersionDiff(data);
  renderAuthorization(data);
  renderRuns(data);
  renderRunAttempts(data);
  renderFactReports(data);
  renderArtifacts(data);
  const status = data?.task?.state?.status || "";
  const auth = data?.authorization?.status || status;
  setHint(`当前任务状态：${status}；授权状态：${auth}`);
}

ui.taskNextAction?.addEventListener("click", async (event) => {
  const button = event.target.closest("button[data-task-action]");
  if (!button) return;
  try {
    if (button.dataset.taskAction === "activate-task") {
      ui.btnActivateTask?.click();
    }
  } catch (error) {
    setHint(error.message || String(error), true);
  }
});

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
