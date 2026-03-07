const el = (id) => document.getElementById(id);

const ui = {
  workflowSessionId: el("workflowSessionId"),
  caseTitle: el("caseTitle"),
  openingBrief: el("openingBrief"),
  currentSummary: el("currentSummary"),
  caseIdInput: el("caseIdInput"),
  roundIdInput: el("roundIdInput"),
  caseOverview: el("caseOverview"),
  candidateList: el("candidateList"),
  taskList: el("taskList"),
  templateList: el("templateList"),
  mailList: el("mailList"),
  caseStatusHint: el("caseStatusHint"),
  caseBreadcrumb: el("caseBreadcrumb"),
  casePageTitle: el("casePageTitle"),
  casePageSummary: el("casePageSummary"),
  caseNextAction: el("caseNextAction"),
  caseWorkspaceGuide: el("caseWorkspaceGuide"),
  caseCreateForm: el("caseCreateForm"),
  templateCreateForm: el("templateCreateForm"),
  templateTitle: el("templateTitle"),
  templateSummary: el("templateSummary"),
  templateObjective: el("templateObjective"),
  templateBody: el("templateBody"),
  btnExtractCandidates: el("btnExtractCandidates"),
  btnLoadOverview: el("btnLoadOverview"),
  workspaceSections: Array.from(document.querySelectorAll("[data-case-workspace]")),
};

const searchParams = new URLSearchParams(window.location.search);

function setHint(text, isError = false) {
  ui.caseStatusHint.textContent = text;
  ui.caseStatusHint.classList.toggle("errorText", isError);
}

function queryValue(...names) {
  for (const name of names) {
    const value = searchParams.get(name);
    if (value && value.trim()) return value.trim();
  }
  return "";
}

function currentCaseId() {
  return ui.caseIdInput?.value.trim() || "";
}

function setWorkspaceVisible(visible) {
  for (const section of ui.workspaceSections || []) {
    section.classList.toggle("isHidden", !visible);
  }
  ui.caseWorkspaceGuide?.classList.toggle("isHidden", visible);
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

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function actionItemsMarkup(actions = []) {
  return (Array.isArray(actions) ? actions : [])
    .filter(Boolean)
    .map((action) => {
      const klass = action.primary ? "btn primary" : "btn";
      if (action.type === "button") {
        return `<button type="button" class="${klass}" data-case-action="${escapeHtml(action.action || "")}">${escapeHtml(action.label || "Open")}</button>`;
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

function summaryCardMarkup({ title = "Untitled", status = "", summary = "", actions = "", meta = [], compact = false } = {}) {
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

function governanceSessionHref({ sid, caseId, candidateId, taskId, title, mode }) {
  if (!sid) return "";
  const params = new URLSearchParams();
  params.set("sid", sid);
  if (caseId) params.set("case_id", caseId);
  if (candidateId) params.set("candidate_id", candidateId);
  if (taskId) params.set("task_id", taskId);
  if (title) params.set("title", title);
  if (mode) params.set("mode", mode);
  return `/view/governance-session.html?${params.toString()}`;
}

function sessionMetaLine(label, sid) {
  if (!sid) return "";
  return `<div class="entityMeta">${escapeHtml(label)}：<code>${escapeHtml(sid)}</code></div>`;
}

function candidateSessionHref(candidate) {
  const header = candidate?.header || {};
  const links = candidate?.links || {};
  const state = candidate?.state || {};
  const sid = links.review_session_id || "";
  const caseId = currentCaseId() || links.case_id || "";
  return governanceSessionHref({
    sid,
    caseId,
    candidateId: header.id || "",
    title: (candidate?.spec?.title || header.id || "候选任务") + " / 审议会话",
    mode: state.status === "approved" ? "governance" : "candidate_review",
  });
}

function candidateSessionButton(candidate) {
  const state = candidate?.state || {};
  const href = candidateSessionHref(candidate);
  if (!href) return "";
  const label = state.status === "approved" ? "继续治理" : "进入审议";
  return `<a class="btn" href="${escapeHtml(href)}">${escapeHtml(label)}</a>`;
}

function taskSessionHref(task) {
  const header = task?.header || {};
  const links = task?.links || {};
  const sid = links.governance_session_id || "";
  const caseId = currentCaseId() || links.case_id || "";
  return governanceSessionHref({
    sid,
    caseId,
    taskId: header.id || "",
    title: (task?.spec?.title || header.id || "正式任务") + " / 治理会话",
    mode: "governance",
  });
}

function taskSessionButton(task) {
  const href = taskSessionHref(task);
  if (!href) return "";
  return `<a class="btn" href="${escapeHtml(href)}">打开治理</a>`;
}

function taskDetailHref(task) {
  const header = task?.header || {};
  const links = task?.links || {};
  const caseId = currentCaseId() || links.case_id || "";
  const taskId = header.id || "";
  if (!caseId || !taskId) return "";
  const params = new URLSearchParams({ case_id: caseId, task_id: taskId });
  return `/view/task-detail.html?${params.toString()}`;
}

function taskDetailButton(task) {
  const href = taskDetailHref(task);
  if (!href) return "";
  return `<a class="btn" href="${escapeHtml(href)}">任务详情</a>`;
}

function renderNextAction(action) {
  if (!ui.caseNextAction) return;
  const buttons = Array.isArray(action?.buttons) ? action.buttons : [];
  ui.caseNextAction.innerHTML = `
    <div class="caseActionLabel">下一步</div>
    <div class="caseActionTitle">${escapeHtml(action?.title || "先进入案卷")}</div>
    <div class="caseActionBody">${escapeHtml(action?.body || "先立案或输入 Case ID，再进入案卷工作台。")}</div>
    <div class="caseActionButtons">
      ${buttons
        .map((button) => {
          const klass = button.primary ? "btn primary" : "btn";
          if (button.type === "button") {
            return `<button type="button" class="${klass}" data-case-action="${escapeHtml(button.action || "")}">${escapeHtml(button.label || "操作")}</button>`;
          }
          return `<a class="${klass}" href="${escapeHtml(button.href || "#")}">${escapeHtml(button.label || "查看")}</a>`;
        })
        .join("")}
    </div>
  `;
}

function pendingCandidates(items) {
  return (Array.isArray(items) ? items : []).filter((candidate) => {
    const status = candidate?.state?.status || "";
    return status !== "approved" && status !== "discarded";
  });
}

function casePageSummary(data) {
  const caseObj = data?.case || null;
  const state = caseObj?.state || {};
  const pending = pendingCandidates(data?.candidates || []);
  const tasks = Array.isArray(data?.tasks) ? data.tasks : [];
  if (pending.length) {
    return "当前主任务：先处理候选审议，再决定哪些任务转正进入长期治理。";
  }
  if (tasks.length) {
    return "当前主任务：围绕正式任务继续治理，并留意版本差异、授权状态和激活进度。";
  }
  if (state.current_summary) {
    return state.current_summary;
  }
  return "当前主任务：先补齐候选来源，让案卷进入可治理状态。";
}

function deriveNextAction(data) {
  const pending = pendingCandidates(data?.candidates || []);
  if (pending.length) {
    const candidate = pending[0];
    return {
      title: "进入审议",
      body: "当前还有待审候选任务；先完成审议，再决定是否转成正式任务。",
      buttons: [{ type: "link", href: candidateSessionHref(candidate), label: "进入审议", primary: true }],
    };
  }

  const tasks = Array.isArray(data?.tasks) ? data.tasks : [];
  const credentialTask = tasks.find((task) => {
    const status = task?.state?.status || "";
    return status === "awaiting_credentials" || status === "reauthorization_required" || status === "credential_expired";
  });
  if (credentialTask) {
    return {
      title: "先补权",
      body: "当前正式任务缺少授权或需要重授权；请先进入任务详情处理。",
      buttons: [{ type: "link", href: taskDetailHref(credentialTask), label: "先补权", primary: true }],
    };
  }

  const readyTask = tasks.find((task) => (task?.state?.status || "") === "ready_to_activate");
  if (readyTask) {
    return {
      title: "查看差异并激活",
      body: "当前版本已就绪；请先查看任务详情，再执行激活。",
      buttons: [{ type: "link", href: taskDetailHref(readyTask), label: "查看任务详情", primary: true }],
    };
  }

  const activeTask = tasks[0] || null;
  if (activeTask) {
    return {
      title: "继续治理",
      body: "已有正式任务；继续沿用同一条治理线推进。",
      buttons: [
        { type: "link", href: taskSessionHref(activeTask), label: "继续治理", primary: true },
        { type: "link", href: taskDetailHref(activeTask), label: "任务详情" },
      ],
    };
  }

  return {
    title: "重新抽取候选任务",
    body: "当前案卷还没有可处理任务；先重新抽取候选任务，再进入审议。",
    buttons: [{ type: "button", action: "extract-candidates", label: "重新抽取", primary: true }],
  };
}

function syncCaseShell(data) {
  const caseObj = data?.case || null;
  if (!caseObj) {
    if (ui.caseBreadcrumb) ui.caseBreadcrumb.textContent = "Cases / 案卷入口";
    if (ui.casePageTitle) ui.casePageTitle.textContent = "先创建案卷或进入既有案卷";
    if (ui.casePageSummary) {
      ui.casePageSummary.textContent = "此页的主任务是进入案卷：要么从已完成 Workflow 立案，要么输入既有 Case ID 进入工作台。";
    }
    renderNextAction({
      title: "先创建案卷或输入 Case ID",
      body: "完成立案或进入既有案卷后，这一页才会展开案卷工作台。",
      buttons: [
        { type: "link", href: "#caseCreateForm", label: "去立案", primary: true },
        { type: "link", href: "#caseIdInput", label: "输入 Case ID" },
      ],
    });
    setWorkspaceVisible(false);
    return;
  }

  const header = caseObj.header || {};
  const spec = caseObj.spec || {};
  const title = spec.title || header.id || "未命名案卷";
  if (ui.caseBreadcrumb) ui.caseBreadcrumb.textContent = `Cases / ${title}`;
  if (ui.casePageTitle) ui.casePageTitle.textContent = title;
  if (ui.casePageSummary) ui.casePageSummary.textContent = casePageSummary(data);
  renderNextAction(deriveNextAction(data));
  setWorkspaceVisible(true);
}

function renderOverview(data) {
  const caseObj = data?.case || null;
  if (!caseObj) {
    setEmptyState(ui.caseOverview, {
      layout: "overviewCard empty",
      label: "案卷摘要",
      title: "暂无案卷数据",
      body: "请先立案或输入 Case ID 进入工作台。",
      actions: [
        { type: "link", href: "#caseCreateForm", label: "先立案", primary: true },
        { type: "link", href: "#caseIdInput", label: "输入 Case ID" },
      ],
    });
    return;
  }
  const spec = caseObj.spec || {};
  const state = caseObj.state || {};
  const header = caseObj.header || {};
  ui.caseOverview.className = "overviewCard";
  ui.caseOverview.innerHTML = `
    <div class="overviewTitle">${escapeHtml(spec.title || "未命名案卷")}</div>
    ${overviewFactsMarkup([
      { label: "案卷 ID", value: header.id || "" },
      { label: "阶段", value: state.phase || "" },
      { label: "状态", value: state.status || "" },
      { label: "生效任务数", value: state.active_task_count ?? 0 },
    ])}
    <div class="overviewSummary">${escapeHtml(state.current_summary || spec.opening_brief || "暂无摘要")}</div>
  `;
}

function actionButtons(candidate) {
  const id = candidate?.header?.id || "";
  const status = candidate?.state?.status || "";
  const sessionButton = candidateSessionButton(candidate);
  const buttons = [sessionButton];
  if (id && status !== "approved" && status !== "discarded") {
    buttons.push(`<button class="btn primary" data-action="approve" data-id="${escapeHtml(id)}">生效</button>`);
    buttons.push(`<button class="btn danger" data-action="discard" data-id="${escapeHtml(id)}">废弃</button>`);
  }
  return buttons.filter(Boolean).join("");
}

function renderCandidateList(candidates) {
  if (!Array.isArray(candidates) || !candidates.length) {
    setEmptyState(ui.candidateList, {
      label: "候选任务",
      title: "暂无候选任务",
      body: "可先重新抽取候选任务，或回看案卷摘要确认当前节奏。",
      actions: [
        { type: "link", href: "#btnExtractCandidates", label: "重新抽取", primary: true },
        { type: "link", href: "#caseOverviewPanel", label: "看案卷摘要" },
      ],
    });
    return;
  }
  ui.candidateList.className = "entityList";
  ui.candidateList.innerHTML = candidates
    .map((candidate) => {
      const header = candidate.header || {};
      const links = candidate.links || {};
      const spec = candidate.spec || {};
      const state = candidate.state || {};
      return summaryCardMarkup({
        title: spec.title || header.id || "未命名候选任务",
        status: state.status || "",
        summary: spec.objective || spec.mission_statement || "暂无候选摘要",
        actions: actionButtons(candidate),
        meta: [
          { label: "候选 ID", value: header.id || "" },
          { label: "审议会话", value: links.review_session_id || "待生成" },
        ],
      });
    })
    .join("");
}

function renderTaskList(tasks) {
  if (!Array.isArray(tasks) || !tasks.length) {
    setEmptyState(ui.taskList, {
      label: "正式任务",
      title: "暂无正式任务",
      body: "候选尚未转正，先去完成候选审议。",
      actions: [
        { type: "link", href: "#candidateSection", label: "看候选任务", primary: true },
        { type: "link", href: "#btnExtractCandidates", label: "重新抽取" },
      ],
    });
    return;
  }
  ui.taskList.className = "entityList";
  ui.taskList.innerHTML = tasks
    .map((task) => {
      const header = task.header || {};
      const links = task.links || {};
      const spec = task.spec || {};
      const state = task.state || {};
      const status = state.status || "";
      const sessionHref = taskSessionHref(task);
      const detailHref = taskDetailHref(task);
      const needsAuthorization = status === "awaiting_credentials" || status === "reauthorization_required" || status === "credential_expired";
      const readyToActivate = status === "ready_to_activate";
      const actions = [
        needsAuthorization && detailHref
          ? `<a class="btn primary" href="${escapeHtml(detailHref)}">先补权</a>`
          : readyToActivate && detailHref
            ? `<a class="btn primary" href="${escapeHtml(detailHref)}">激活前检查</a>`
            : sessionHref
              ? `<a class="btn primary" href="${escapeHtml(sessionHref)}">继续治理</a>`
              : detailHref
                ? `<a class="btn primary" href="${escapeHtml(detailHref)}">查看任务详情</a>`
                : "",
        sessionHref ? `<a class="btn" href="${escapeHtml(sessionHref)}">打开治理</a>` : "",
        detailHref ? `<a class="btn" href="${escapeHtml(detailHref)}">任务详情</a>` : "",
      ]
        .filter(Boolean)
        .join("");
      return summaryCardMarkup({
        title: spec.title || header.id || "未命名正式任务",
        status,
        summary: spec.mission_statement || spec.objective || "暂无任务摘要",
        actions,
        meta: [
          { label: "任务 ID", value: header.id || "" },
          { label: "治理会话", value: links.governance_session_id || "待创建" },
        ],
        compact: true,
      });
    })
    .join("");
}

function renderTemplateList(templates) {
  if (!ui.templateList) return;
  if (!Array.isArray(templates) || !templates.length) {
    setEmptyState(ui.templateList, {
      label: "模板库",
      title: "暂无模板",
      body: "等治理方式稳定之后，再把成熟做法沉淀成模板。",
    });
    return;
  }
  ui.templateList.className = "entityList";
  ui.templateList.innerHTML = templates
    .map((item) => {
      const header = item.header || {};
      const spec = item.spec || {};
      return summaryCardMarkup({
        title: spec.title || header.id || "模板",
        status: "template",
        summary: spec.summary || spec.objective || "暂无模板摘要",
        actions: `<button type="button" class="btn primary" data-action="instantiate-template" data-id="${escapeHtml(header.id || "")}">实例化候选</button>`,
        meta: [{ label: "模板 ID", value: header.id || "" }],
        compact: true,
      });
    })
    .join("");
}

function renderMailList(mailItems) {
  if (!Array.isArray(mailItems) || !mailItems.length) {
    setEmptyState(ui.mailList, {
      label: "内邮",
      title: "暂无内邮",
      body: "候选抽取、转正或修订通知会沉淀在这里。",
      actions: [{ type: "link", href: "/view/inbox.html", label: "打开统一信箱" }],
    });
    return;
  }
  ui.mailList.className = "entityList";
  ui.mailList.innerHTML = mailItems
    .map((item) => {
      const header = item.header || {};
      const spec = item.spec || {};
      const state = item.state || {};
      return summaryCardMarkup({
        title: spec.title || "内邮",
        status: state.status || "",
        summary: spec.summary || "暂无摘要",
        actions: `<a class="btn" href="/view/inbox.html">打开统一信箱</a>`,
        meta: header.id ? [{ label: "邮件 ID", value: header.id }] : [],
        compact: true,
      });
    })
    .join("");
}

function hydrateFromOverview(data) {
  syncCaseShell(data);
  renderOverview(data);
  renderCandidateList(data?.candidates || []);
  renderTaskList(data?.tasks || []);
  renderTemplateList(data?.templates || []);
  renderMailList(data?.mail || []);
  const caseId = data?.case?.header?.id || "";
  const rounds = Array.isArray(data?.rounds) ? data.rounds : [];
  const lastRound = rounds.length ? rounds[rounds.length - 1] : null;
  if (caseId) ui.caseIdInput.value = caseId;
  if (lastRound?.header?.id) ui.roundIdInput.value = lastRound.header.id;
}

function overviewFromCreateResponse(created) {
  if (created?.overview) return created.overview;
  return {
    case: created?.case || null,
    rounds: created?.round ? [created.round] : [],
    candidates: created?.candidates || [],
    tasks: [],
    templates: created?.templates || [],
    mail: created?.mail || [],
  };
}

async function loadOverview() {
  const caseId = ui.caseIdInput.value.trim();
  if (!caseId) {
    setHint("请先输入 case id。", true);
    return;
  }
  setHint("正在加载案卷总览...");
  const overview = await fetchJson(`/api/cases/${encodeURIComponent(caseId)}/overview`);
  hydrateFromOverview(overview);
  setHint("案卷总览已更新。");
}

async function createCase(event) {
  event.preventDefault();
  const workflowSessionId = ui.workflowSessionId.value.trim();
  if (!workflowSessionId) {
    setHint("请先输入已完成朝议的 workflow session id。", true);
    return;
  }
  setHint("正在立案...");
  const created = await postJson("/api/cases", {
    workflow_session_id: workflowSessionId,
    title: ui.caseTitle.value.trim(),
    opening_brief: ui.openingBrief.value.trim(),
    current_summary: ui.currentSummary.value.trim(),
  });
  ui.caseIdInput.value = created?.case?.header?.id || "";
  ui.roundIdInput.value = created?.round?.header?.id || "";
  hydrateFromOverview(overviewFromCreateResponse(created));
  const candidateCount = Array.isArray(created?.candidates)
    ? created.candidates.length
    : Array.isArray(created?.overview?.candidates)
      ? created.overview.candidates.length
      : 0;
  if (candidateCount > 0) {
    setHint(`已立案；提案官已自动抽取 ${candidateCount} 个候选任务。`);
    return;
  }
  setHint("已立案；提案官暂未抽取到候选任务，可稍后重新抽取。", false);
}

async function extractCandidates() {
  const caseId = ui.caseIdInput.value.trim();
  if (!caseId) {
    setHint("请先创建案卷或填入 case id。", true);
    return;
  }
  setHint("正在重新抽取候选任务...");
  const payload = {};
  if (ui.roundIdInput.value.trim()) payload.round_id = ui.roundIdInput.value.trim();
  const extracted = await postJson(`/api/cases/${encodeURIComponent(caseId)}/candidates/extract`, payload);
  hydrateFromOverview(extracted.overview);
  setHint(`已重新抽取 ${Array.isArray(extracted.candidates) ? extracted.candidates.length : 0} 个候选任务。`);
}

async function approveCandidate(candidateId) {
  const caseId = ui.caseIdInput.value.trim();
  setHint(`正在生效候选任务 ${candidateId} ...`);
  await postJson(`/api/cases/${encodeURIComponent(caseId)}/candidates/${encodeURIComponent(candidateId)}/approve`, {
    approved_by_op_id: "web_user",
    approval_summary: "Approved from web UI",
    objective: "Track statement frequency, wording, and topic changes",
    schedule_policy: { mode: "interval", interval: { value: 6, unit: "hours" } },
    report_contract: { kind: "markdown", required_sections: ["Summary", "Facts"] },
  });
  await loadOverview();
  setHint(`候选任务 ${candidateId} 已生效。`);
}

async function discardCandidate(candidateId) {
  const caseId = ui.caseIdInput.value.trim();
  setHint(`正在废弃候选任务 ${candidateId} ...`);
  await postJson(`/api/cases/${encodeURIComponent(caseId)}/candidates/${encodeURIComponent(candidateId)}/discard`, {
    acted_by_op_id: "web_user",
    reason: "Discarded from web UI",
  });
  await loadOverview();
  setHint(`候选任务 ${candidateId} 已废弃。`);
}

async function createTemplate(event) {
  event.preventDefault();
  const caseId = ui.caseIdInput.value.trim();
  if (!caseId) {
    setHint("请先创建案卷或填入 case id。", true);
    return;
  }
  setHint("正在创建模板...");
  await postJson(`/api/cases/${encodeURIComponent(caseId)}/templates`, {
    created_by_op_id: "web_user",
    title: ui.templateTitle?.value?.trim() || "",
    summary: ui.templateSummary?.value?.trim() || "",
    objective: ui.templateObjective?.value?.trim() || "",
    template_body: ui.templateBody?.value?.trim() || "",
  });
  await loadOverview();
  setHint("模板已创建。", false);
}

async function instantiateTemplate(templateId) {
  const caseId = ui.caseIdInput.value.trim();
  if (!caseId) {
    setHint("请先创建案卷或填入 case id。", true);
    return;
  }
  setHint(`正在按模板 ${templateId} 生成候选任务...`);
  await postJson(`/api/cases/${encodeURIComponent(caseId)}/templates/${encodeURIComponent(templateId)}/instantiate`, {
    acted_by_op_id: "web_user",
  });
  await loadOverview();
  setHint(`模板 ${templateId} 已实例化为候选任务。`);
}

function applyQueryPrefill() {
  const workflowSessionId = queryValue("workflow_session_id", "workflowSessionId");
  const caseId = queryValue("case_id", "caseId");
  const roundId = queryValue("round_id", "roundId");
  if (workflowSessionId && !ui.workflowSessionId.value.trim()) {
    ui.workflowSessionId.value = workflowSessionId;
  }
  if (caseId && !ui.caseIdInput.value.trim()) {
    ui.caseIdInput.value = caseId;
  }
  if (roundId && !ui.roundIdInput.value.trim()) {
    ui.roundIdInput.value = roundId;
  }
}

async function initCasePage() {
  syncCaseShell(null);
  applyQueryPrefill();
  if (ui.caseIdInput.value.trim()) {
    try {
      await loadOverview();
    } catch (error) {
      setHint(error.message || String(error), true);
    }
    return;
  }
  if (ui.workflowSessionId.value.trim()) {
    setHint("已预填已完成朝议的 workflow session id；确认后可直接立案。", false);
  }
}

ui.caseNextAction?.addEventListener("click", async (event) => {
  const button = event.target.closest("button[data-case-action]");
  if (!button) return;
  try {
    if (button.dataset.caseAction === "extract-candidates") {
      await extractCandidates();
    }
  } catch (error) {
    setHint(error.message || String(error), true);
  }
});

ui.caseCreateForm?.addEventListener("submit", async (event) => {
  try {
    await createCase(event);
  } catch (error) {
    setHint(error.message || String(error), true);
  }
});

ui.btnLoadOverview?.addEventListener("click", async () => {
  try {
    await loadOverview();
  } catch (error) {
    setHint(error.message || String(error), true);
  }
});

ui.btnExtractCandidates?.addEventListener("click", async () => {
  try {
    await extractCandidates();
  } catch (error) {
    setHint(error.message || String(error), true);
  }
});

ui.candidateList?.addEventListener("click", async (event) => {
  const button = event.target.closest("button[data-action]");
  if (!button) return;
  const candidateId = button.dataset.id;
  const action = button.dataset.action;
  try {
    if (action === "approve") {
      await approveCandidate(candidateId);
    } else if (action === "discard") {
      await discardCandidate(candidateId);
    }
  } catch (error) {
    setHint(error.message || String(error), true);
  }
});

ui.templateCreateForm?.addEventListener("submit", async (event) => {
  try {
    await createTemplate(event);
  } catch (error) {
    setHint(error.message || String(error), true);
  }
});

ui.templateList?.addEventListener("click", async (event) => {
  const button = event.target.closest("button[data-action='instantiate-template']");
  if (!button) return;
  try {
    await instantiateTemplate(button.dataset.id || "");
  } catch (error) {
    setHint(error.message || String(error), true);
  }
});

void initCasePage();
