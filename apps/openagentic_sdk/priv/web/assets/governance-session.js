const el = (id) => document.getElementById(id);

const ui = {
  governanceSubtitle: el("governanceSubtitle"),
  governanceBreadcrumb: el("governanceBreadcrumb"),
  governancePageTitle: el("governancePageTitle"),
  governancePageSummary: el("governancePageSummary"),
  governanceNextAction: el("governanceNextAction"),
  governanceSessionId: el("governanceSessionId"),
  governanceObjectRef: el("governanceObjectRef"),
  governanceContextHint: el("governanceContextHint"),
  governanceTranscript: el("governanceTranscript"),
  governanceSessionForm: el("governanceSessionForm"),
  governancePrompt: el("governancePrompt"),
  governanceStatusHint: el("governanceStatusHint"),
  governanceRevisionForm: el("governanceRevisionForm"),
  revisionChangeSummary: el("revisionChangeSummary"),
  revisionObjective: el("revisionObjective"),
  revisionCredentialSlotName: el("revisionCredentialSlotName"),
  revisionCredentialBindingType: el("revisionCredentialBindingType"),
  revisionCredentialProvider: el("revisionCredentialProvider"),
  governanceRevisionHint: el("governanceRevisionHint"),
  governanceTaskSummary: el("governanceTaskSummary"),
  governanceVersionDiff: el("governanceVersionDiff"),
  governanceAuthorization: el("governanceAuthorization"),
  governanceCredentialBindingForm: el("governanceCredentialBindingForm"),
  governanceBindingSlotName: el("governanceBindingSlotName"),
  governanceBindingType: el("governanceBindingType"),
  governanceBindingProvider: el("governanceBindingProvider"),
  governanceBindingStatus: el("governanceBindingStatus"),
  governanceBindingMaterialRef: el("governanceBindingMaterialRef"),
  governanceActivateTask: el("governanceActivateTask"),
  taskDetailLink: el("taskDetailLink"),
  backToCase: el("backToCase"),
};

const searchParams = new URLSearchParams(window.location.search);

const state = {
  sid: "",
  eventSource: null,
  seenSeqs: new Set(),
  pendingAssistantEl: null,
  taskDetail: null,
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

function setRevisionHint(text, isError = false) {
  ui.governanceRevisionHint.textContent = text;
  ui.governanceRevisionHint.classList.toggle("errorText", isError);
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

function actionItemsMarkup(actions = []) {
  return (Array.isArray(actions) ? actions : [])
    .filter(Boolean)
    .map((action) => {
      const klass = action.primary ? "btn primary" : "btn";
      if (action.type === "button") {
        return `<button type="button" class="${klass}" data-governance-action="${escapeHtml(action.action || "")}">${escapeHtml(action.label || "Open")}</button>`;
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

function appendEntry(kind, title, body, meta = "") {
  if (ui.governanceTranscript.classList.contains("empty")) {
    ui.governanceTranscript.className = "entityList";
    ui.governanceTranscript.innerHTML = "";
  }
  const card = document.createElement("article");
  card.className = "entityCard compact objectSummaryCard";
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

function taskContext() {
  return {
    caseId: queryValue("case_id", "caseId"),
    taskId: queryValue("task_id", "taskId"),
  };
}

function taskDetailHref() {
  const { caseId, taskId } = taskContext();
  if (!caseId || !taskId) return "/view/cases.html";
  const search = new URLSearchParams({ case_id: caseId, task_id: taskId });
  return `/view/task-detail.html?${search.toString()}`;
}

function taskDetailApiUrl() {
  const { caseId, taskId } = taskContext();
  if (!caseId || !taskId) return "";
  return `/api/cases/${encodeURIComponent(caseId)}/tasks/${encodeURIComponent(taskId)}/detail`;
}

function governanceDisplayTitle(detail = null) {
  const title = queryValue("title") || "治理会话";
  if (detail?.task?.spec?.title) return detail.task.spec.title;
  return title;
}

function renderGovernanceNextAction(action) {
  if (!ui.governanceNextAction) return;
  const buttons = Array.isArray(action?.buttons) ? action.buttons : [];
  ui.governanceNextAction.innerHTML = `
    <div class="caseActionLabel">下一步</div>
    <div class="caseActionTitle">${escapeHtml(action?.title || "先继续治理")}</div>
    <div class="caseActionBody">${escapeHtml(action?.body || "先继续对话，再决定是否修订。")}</div>
    <div class="caseActionButtons">
      ${buttons
        .map((button) => {
          const klass = button.primary ? "btn primary" : "btn";
          if (button.type === "button") {
            return `<button type="button" class="${klass}" data-governance-action="${escapeHtml(button.action || "")}">${escapeHtml(button.label || "操作")}</button>`;
          }
          return `<a class="${klass}" href="${escapeHtml(button.href || "#")}">${escapeHtml(button.label || "查看")}</a>`;
        })
        .join("")}
    </div>
  `;
}

function governanceSummaryText(detail = null) {
  const { taskId } = taskContext();
  const authStatus = detail?.authorization?.status || detail?.task?.state?.status || "";
  if (!taskId) {
    return "此页的主任务是继续候选审议对话；当前还没有正式任务，因此暂不创建正式任务版本。";
  }
  if (authStatus === "reauthorization_required" || authStatus === "credential_expired") {
    return "此页的主任务仍是继续治理，但当前版本需要先补权，再重新激活任务。";
  }
  if (authStatus === "ready_to_activate") {
    return "此页的主任务是确认修订结果；如差异无误，可直接重新激活任务。";
  }
  return "此页的主任务是继续治理对话；如需调整任务定义，再提交版本修订。";
}

function deriveGovernanceNextAction(detail = null) {
  const { taskId } = taskContext();
  const authStatus = detail?.authorization?.status || detail?.task?.state?.status || "";
  if (!taskId) {
    return {
      title: "继续审议",
      body: "当前仍处于候选审议态；先继续对话，形成正式治理结论。",
      buttons: [{ type: "button", action: "focus-prompt", label: "继续审议", primary: true }],
    };
  }
  if (authStatus === "reauthorization_required" || authStatus === "credential_expired" || authStatus === "awaiting_credentials") {
    return {
      title: "先补权",
      body: "当前任务需要有效授权；先补齐绑定，再回到治理或激活。",
      buttons: [
        { type: "link", href: "#governanceAuthorizationPanel", label: "先补权", primary: true },
        { type: "link", href: taskDetailHref(), label: "查看任务详情" },
      ],
    };
  }
  if (authStatus === "ready_to_activate") {
    return {
      title: "重新激活任务",
      body: "当前授权材料已齐备；确认无误后，可以直接重新激活任务。",
      buttons: [
        { type: "button", action: "activate-task", label: "重新激活", primary: true },
        { type: "link", href: "#governanceVersionDiffPanel", label: "查看差异" },
      ],
    };
  }
  return {
    title: "继续治理对话",
    body: "先继续对话收敛结论；如需修改任务定义，再提交新版本修订。",
    buttons: [
      { type: "button", action: "focus-prompt", label: "继续治理", primary: true },
      { type: "link", href: "#governanceRevisionPanel", label: "提交修订" },
    ],
  };
}

function syncGovernanceShell(detail = null) {
  const caseId = queryValue("case_id", "caseId");
  const candidateId = queryValue("candidate_id", "candidateId");
  const { taskId } = taskContext();
  const title = governanceDisplayTitle(detail);
  if (ui.governanceBreadcrumb) {
    const parts = ["Cases", caseId || "Case", taskId ? "任务" : candidateId ? "候选任务" : "治理对象", "治理会话"];
    ui.governanceBreadcrumb.textContent = parts.join(" / ");
  }
  if (ui.governancePageTitle) {
    ui.governancePageTitle.textContent = title;
  }
  if (ui.governancePageSummary) {
    ui.governancePageSummary.textContent = governanceSummaryText(detail);
  }
  renderGovernanceNextAction(deriveGovernanceNextAction(detail));
}

function setRevisionEnabled(enabled) {
  if (ui.revisionChangeSummary) ui.revisionChangeSummary.disabled = !enabled;
  if (ui.revisionObjective) ui.revisionObjective.disabled = !enabled;
  if (ui.revisionCredentialSlotName) ui.revisionCredentialSlotName.disabled = !enabled;
  if (ui.revisionCredentialBindingType) ui.revisionCredentialBindingType.disabled = !enabled;
  if (ui.revisionCredentialProvider) ui.revisionCredentialProvider.disabled = !enabled;
  const button = ui.governanceRevisionForm?.querySelector('button[type="submit"]');
  if (button) button.disabled = !enabled;
}

function setBindingEnabled(enabled) {
  if (ui.governanceBindingSlotName) ui.governanceBindingSlotName.disabled = !enabled;
  if (ui.governanceBindingType) ui.governanceBindingType.disabled = !enabled;
  if (ui.governanceBindingProvider) ui.governanceBindingProvider.disabled = !enabled;
  if (ui.governanceBindingStatus) ui.governanceBindingStatus.disabled = !enabled;
  if (ui.governanceBindingMaterialRef) ui.governanceBindingMaterialRef.disabled = !enabled;
  const button = ui.governanceCredentialBindingForm?.querySelector('button[type="submit"]');
  if (button) button.disabled = !enabled;
  if (ui.governanceActivateTask) ui.governanceActivateTask.disabled = !enabled;
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

function setEmptyBlock(target, text, className = "entityList empty") {
  setEmptyState(target, {
    layout: className,
    label: "空态",
    title: text,
    body: "可根据当前上下文继续对话或进入相应区块处理。",
  });
}

function renderGovernanceTaskSummary(detail) {
  if (!ui.governanceTaskSummary) return;
  const task = detail?.task || {};
  const header = task.header || {};
  const spec = task.spec || {};
  const taskState = task.state || {};
  const auth = detail?.authorization || {};
  if (!header.id) {
    setEmptyState(ui.governanceTaskSummary, {
      layout: "overviewCard empty",
      label: "任务状态",
      title: "暂无正式任务上下文",
      body: "如果当前仍处于候选审议阶段，这是正常的；先继续对话形成正式结论。",
    });
    return;
  }
  ui.governanceTaskSummary.className = "overviewCard";
  ui.governanceTaskSummary.innerHTML = `
    <div class="overviewTitle">${escapeHtml(spec.title || header.id || "未命名任务")}</div>
    ${overviewFactsMarkup([
      { label: "任务 ID", value: header.id || "" },
      { label: "任务状态", value: taskState.status || "" },
      { label: "授权状态", value: auth.status || taskState.status || "" },
      { label: "治理会话", value: task?.links?.governance_session_id || "" },
    ])}
    <div class="overviewSummary">${escapeHtml(spec.mission_statement || spec.objective || "暂无任务摘要")}</div>
  `;
}

function renderGovernanceVersionDiff(detail) {
  if (!ui.governanceVersionDiff) return;
  const diff = detail?.latest_version_diff || {};
  const changedFields = Array.isArray(diff.changed_fields) ? diff.changed_fields : [];
  if (!diff.to_version_id || !changedFields.length) {
    setEmptyState(ui.governanceVersionDiff, {
      label: "版本差异",
      title: "暂无版本差异",
      body: "当前还没有新的任务修订；如有必要，可先继续治理后再提交版本变更。",
    });
    return;
  }
  const cards = [
    summaryCardMarkup({
      title: diff.change_summary || "最新修订",
      status: diff.authorization_status || `${String(diff.changed_field_count || changedFields.length)} 项变更`,
      summary: `变更字段：${String(diff.changed_field_count || changedFields.length || 0)}`,
      meta: [{ label: "版本范围", value: `${diff.from_version_id || ""} -> ${diff.to_version_id || ""}` }],
    }),
    ...changedFields.map((item) => {
      const field = item?.field || "field";
      const fromValue = formatInline(item?.from) || "-";
      const toValue = formatInline(item?.to) || "-";
      return summaryCardMarkup({
        title: field,
        status: "已变更",
        summary: `from: ${fromValue} -> to: ${toValue}`,
      });
    }),
  ];
  if (Array.isArray(diff.newly_required_slots) && diff.newly_required_slots.length) {
    cards.push(summaryCardMarkup({ title: "新增授权槽位", status: "auth", summary: diff.newly_required_slots.join(", ") }));
  }
  ui.governanceVersionDiff.className = "entityList";
  ui.governanceVersionDiff.innerHTML = cards.join("");
}

function renderGovernanceAuthorization(detail) {
  if (!ui.governanceAuthorization) return;
  const authorization = detail?.authorization || {};
  const bindings = detail?.credential_bindings || [];
  const diff = detail?.latest_version_diff || {};
  const required = Array.isArray(authorization.required_slots) ? authorization.required_slots : [];
  const missing = Array.isArray(authorization.missing_slots) ? authorization.missing_slots : [];
  const expired = Array.isArray(authorization.expired_slots) ? authorization.expired_slots : [];
  if (!authorization.status && !required.length && !bindings.length) {
    setEmptyState(ui.governanceAuthorization, {
      label: "补权与激活",
      title: "暂无授权信息",
      body: "正式任务加载后，这里会展示缺失槽位、绑定状态与重新激活条件。",
    });
    return;
  }
  const cards = [
    summaryCardMarkup({
      title: `授权状态：${authorization.status || "unknown"}`,
      status: authorization.status || "",
      summary: required.length ? `必需槽位：${required.join(", ")}` : "当前没有额外授权要求。",
    }),
  ];
  if (missing.length) {
    cards.push(summaryCardMarkup({ title: "缺失槽位", status: "missing", summary: missing.join(", ") }));
  }
  if (expired.length) {
    cards.push(summaryCardMarkup({ title: "已过期槽位", status: "expired", summary: expired.join(", ") }));
  }
  if (diff.reauthorization_required) {
    const slots = Array.isArray(diff.newly_required_slots) ? diff.newly_required_slots : [];
    cards.push(summaryCardMarkup({ title: "当前需要重授权", status: "reauthorize", summary: `${slots.join(", ") || "请查看缺失槽位"} 补齐后即可重新激活任务。` }));
  }
  cards.push(
    ...bindings.map((binding) => {
      const spec = binding.spec || {};
      const bindingState = binding.state || {};
      return summaryCardMarkup({
        title: spec.slot_name || "未命名槽位",
        status: bindingState.status || "",
        summary: `${spec.binding_type || ""}${spec.provider ? ` / ${spec.provider}` : ""}`,
        meta: spec.material_ref ? [{ label: "material_ref", value: spec.material_ref }] : [],
      });
    })
  );
  ui.governanceAuthorization.className = "entityList";
  ui.governanceAuthorization.innerHTML = cards.join("");
  const defaultSlot = missing[0] || required[0] || "";
  if (defaultSlot && ui.governanceBindingSlotName && !ui.governanceBindingSlotName.value.trim()) {
    ui.governanceBindingSlotName.value = defaultSlot;
  }
}

function syncGovernanceTaskState(detail) {
  const taskStatus = detail?.task?.state?.status || "";
  const authStatus = detail?.authorization?.status || taskStatus;
  const diff = detail?.latest_version_diff || {};
  const required = Array.isArray(detail?.authorization?.required_slots) ? detail.authorization.required_slots : [];
  setBindingEnabled(Boolean(required.length || taskContext().taskId));
  if (ui.governanceActivateTask) {
    ui.governanceActivateTask.disabled = authStatus !== "ready_to_activate";
  }
  if (taskContext().taskId) {
    if (authStatus === "reauthorization_required") {
      setRevisionHint("最新版本已进入重授权状态：请先在本页补齐绑定，再点击“重新激活任务”。", false);
    } else if (authStatus === "credential_expired") {
      setRevisionHint("当前绑定已过期：请更新绑定材料后重新激活任务。", false);
    } else if (authStatus === "ready_to_activate" && diff.reauthorization_required) {
      setRevisionHint("重授权材料已补齐：现在可以直接在本页重新激活任务。", false);
    } else if (authStatus === "active") {
      setRevisionHint("当前版本已处于 active，可继续治理或再次修订。", false);
    }
    ui.governanceContextHint.textContent = `这里承接候选任务审议与正式任务治理。当前任务状态：${taskStatus || "未知"}；授权状态：${authStatus || "未知"}。`;
  }
  syncGovernanceShell(detail);
}

function resetGovernanceTaskPanels() {
  if (ui.governanceTaskSummary) {
    ui.governanceTaskSummary.className = "overviewCard empty";
    ui.governanceTaskSummary.textContent = "暂无正式任务上下文。";
  }
  setEmptyBlock(ui.governanceVersionDiff, "暂无版本差异");
  setEmptyBlock(ui.governanceAuthorization, "暂无授权信息");
  setBindingEnabled(false);
  syncGovernanceShell(null);
}

async function loadTaskDetail() {
  const url = taskDetailApiUrl();
  if (!url) {
    state.taskDetail = null;
    resetGovernanceTaskPanels();
    return;
  }
  const detail = await fetchJson(url);
  state.taskDetail = detail;
  renderGovernanceTaskSummary(detail);
  renderGovernanceVersionDiff(detail);
  renderGovernanceAuthorization(detail);
  syncGovernanceTaskState(detail);
}

function collectRevisionCredentialRequirements() {
  const slotName = ui.revisionCredentialSlotName?.value.trim() || "";
  if (!slotName) return undefined;
  const slot = { slot_name: slotName };
  const bindingType = ui.revisionCredentialBindingType?.value.trim() || "";
  const provider = ui.revisionCredentialProvider?.value.trim() || "";
  if (bindingType) slot.binding_type = bindingType;
  if (provider) slot.provider = provider;
  return { required_slots: [slot] };
}

function applyContext() {
  const sid = queryValue("sid", "session_id", "sessionId");
  const title = queryValue("title") || "聊天式治理 / 审议会话";
  const caseId = queryValue("case_id", "caseId");
  const { taskId } = taskContext();
  state.sid = sid;
  ui.governanceSubtitle.textContent = title;
  ui.governanceSessionId.textContent = sid || "";
  ui.governanceObjectRef.textContent = buildObjectRef() || "未指定";
  ui.backToCase.href = caseId ? `/view/cases.html?case_id=${encodeURIComponent(caseId)}` : "/view/cases.html";
  syncGovernanceShell(null);
  if (ui.taskDetailLink) {
    ui.taskDetailLink.href = taskDetailHref();
  }
  if (taskId) {
    setRevisionEnabled(true);
    setBindingEnabled(true);
    setRevisionHint("当前为正式任务治理，可基于这条治理会话直接创建新版本，也可在本页完成补权与再激活。", false);
  } else {
    setRevisionEnabled(false);
    setBindingEnabled(false);
    setRevisionHint("当前没有 task_id；这通常表示仍处于候选审议态，暂不能创建正式任务版本。", false);
    resetGovernanceTaskPanels();
  }
  if (!sid) {
    setHint("缺少 sid，无法打开治理会话。", true);
    ui.governancePrompt.disabled = true;
    setRevisionEnabled(false);
    setBindingEnabled(false);
    return false;
  }
  return true;
}

async function continueGovernance(message) {
  return postJson(`/api/sessions/${encodeURIComponent(state.sid)}/query`, { message });
}

async function createRevision(changeSummary, objective) {
  const { caseId, taskId } = taskContext();
  const payload = {
    governance_session_id: state.sid,
    revised_by_op_id: "web_user",
  };
  if (changeSummary) payload.change_summary = changeSummary;
  if (objective) payload.objective = objective;
  const credentialRequirements = collectRevisionCredentialRequirements();
  if (credentialRequirements) payload.credential_requirements = credentialRequirements;
  return postJson(`/api/cases/${encodeURIComponent(caseId)}/tasks/${encodeURIComponent(taskId)}/revise`, payload);
}

ui.governanceNextAction?.addEventListener("click", async (event) => {
  const button = event.target.closest("button[data-governance-action]");
  if (!button) return;
  if (button.dataset.governanceAction === "focus-prompt") {
    ui.governancePrompt?.focus();
    return;
  }
  if (button.dataset.governanceAction === "activate-task") {
    ui.governanceActivateTask?.click();
  }
});

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

ui.governanceRevisionForm?.addEventListener("submit", async (event) => {
  event.preventDefault();
  const { taskId } = taskContext();
  if (!taskId) {
    setRevisionHint("当前没有正式任务上下文，不能创建版本。", true);
    return;
  }
  const changeSummary = ui.revisionChangeSummary.value.trim();
  const objective = ui.revisionObjective.value.trim();
  if (!changeSummary && !objective) {
    setRevisionHint("请至少填写变更摘要或新的 Objective。", true);
    return;
  }
  try {
    setRevisionEnabled(false);
    setRevisionHint("正在创建新版本，请稍候...");
    const res = await createRevision(changeSummary, objective);
    const versionId = res?.task_version?.header?.id || "";
    const auth = res?.authorization?.status || res?.task?.state?.status || "";
    const missingSlots = Array.isArray(res?.authorization?.missing_slots) ? res.authorization.missing_slots : [];
    ui.revisionChangeSummary.value = "";
    ui.revisionObjective.value = "";
    if (ui.revisionCredentialSlotName) ui.revisionCredentialSlotName.value = "";
    if (ui.revisionCredentialBindingType) ui.revisionCredentialBindingType.value = "";
    if (ui.revisionCredentialProvider) ui.revisionCredentialProvider.value = "";
    await loadTaskDetail();
    if (auth === "reauthorization_required" || auth === "awaiting_credentials" || auth === "credential_expired" || auth === "ready_to_activate") {
      setRevisionHint(`新版本已创建${versionId ? `：${versionId}` : ""}，当前授权状态为 ${auth}。${missingSlots.length ? `缺失槽位：${missingSlots.join(", ")}。` : ""}可直接在本页补齐绑定并重新激活。`, false);
    } else {
      setRevisionHint(`新版本已创建${versionId ? `：${versionId}` : ""}。可继续在本页治理，也可查看下方差异与状态。`, false);
    }
  } catch (error) {
    setRevisionHint(error.message || String(error), true);
  } finally {
    const { taskId: nextTaskId } = taskContext();
    setRevisionEnabled(Boolean(nextTaskId));
  }
});

ui.governanceCredentialBindingForm?.addEventListener("submit", async (event) => {
  event.preventDefault();
  const { caseId, taskId } = taskContext();
  if (!caseId || !taskId) {
    setRevisionHint("当前没有正式任务上下文，不能补权。", true);
    return;
  }
  const slotName = ui.governanceBindingSlotName?.value.trim() || "";
  const bindingType = ui.governanceBindingType?.value.trim() || "";
  const materialRef = ui.governanceBindingMaterialRef?.value.trim() || "";
  if (!slotName || !bindingType || !materialRef) {
    setRevisionHint("请至少填写槽位名、绑定类型和材料引用。", true);
    return;
  }
  try {
    setBindingEnabled(false);
    setRevisionHint("正在保存补权绑定...");
    await postJson(`/api/cases/${encodeURIComponent(caseId)}/tasks/${encodeURIComponent(taskId)}/credential-bindings`, {
      slot_name: slotName,
      binding_type: bindingType,
      provider: ui.governanceBindingProvider?.value.trim() || "",
      status: ui.governanceBindingStatus?.value.trim() || "validated",
      material_ref: materialRef,
    });
    await loadTaskDetail();
    setRevisionHint("补权绑定已保存。若状态已变为 ready_to_activate，可直接重新激活任务。", false);
  } catch (error) {
    setRevisionHint(error.message || String(error), true);
  } finally {
    setBindingEnabled(Boolean(taskContext().taskId));
    if (state.taskDetail) syncGovernanceTaskState(state.taskDetail);
  }
});

ui.governanceActivateTask?.addEventListener("click", async () => {
  const { caseId, taskId } = taskContext();
  if (!caseId || !taskId) {
    setRevisionHint("当前没有正式任务上下文，不能重新激活。", true);
    return;
  }
  try {
    setBindingEnabled(false);
    setRevisionHint("正在重新激活任务...");
    await postJson(`/api/cases/${encodeURIComponent(caseId)}/tasks/${encodeURIComponent(taskId)}/activate`, {
      activated_by_op_id: "web_user",
    });
    await loadTaskDetail();
    setRevisionHint("任务已重新激活，可继续在本页治理。", false);
  } catch (error) {
    setRevisionHint(error.message || String(error), true);
  } finally {
    setBindingEnabled(Boolean(taskContext().taskId));
    if (state.taskDetail) syncGovernanceTaskState(state.taskDetail);
  }
});

async function init() {
  if (!applyContext()) return;
  connectSse(state.sid);
  if (taskContext().taskId) {
    try {
      await loadTaskDetail();
    } catch (error) {
      setRevisionHint(error.message || String(error), true);
    }
  }
}

void init();
