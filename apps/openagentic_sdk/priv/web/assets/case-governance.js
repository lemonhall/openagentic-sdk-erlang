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
  mailList: el("mailList"),
  caseStatusHint: el("caseStatusHint"),
  caseCreateForm: el("caseCreateForm"),
  btnExtractCandidates: el("btnExtractCandidates"),
  btnLoadOverview: el("btnLoadOverview"),
};

function setHint(text, isError = false) {
  ui.caseStatusHint.textContent = text;
  ui.caseStatusHint.classList.toggle("errorText", isError);
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

function renderOverview(data) {
  const caseObj = data?.case || null;
  if (!caseObj) {
    ui.caseOverview.className = "overviewCard empty";
    ui.caseOverview.textContent = "暂无案卷数据";
    return;
  }
  const spec = caseObj.spec || {};
  const state = caseObj.state || {};
  const header = caseObj.header || {};
  ui.caseOverview.className = "overviewCard";
  ui.caseOverview.innerHTML = `
    <div class="overviewTitle">${escapeHtml(spec.title || "Untitled Case")}</div>
    <div class="overviewMeta">Case ID: <code>${escapeHtml(header.id || "")}</code></div>
    <div class="overviewMeta">阶段：${escapeHtml(state.phase || "")}</div>
    <div class="overviewMeta">状态：${escapeHtml(state.status || "")}</div>
    <div class="overviewMeta">Active Tasks: ${escapeHtml(state.active_task_count ?? 0)}</div>
    <div class="overviewSummary">${escapeHtml(state.current_summary || spec.opening_brief || "")}</div>
  `;
}

function actionButtons(candidate) {
  const id = candidate?.header?.id || "";
  const status = candidate?.state?.status || "";
  if (!id || status === "approved" || status === "discarded") return "";
  return `
    <div class="entityActions">
      <button class="btn primary" data-action="approve" data-id="${escapeHtml(id)}">生效</button>
      <button class="btn danger" data-action="discard" data-id="${escapeHtml(id)}">废弃</button>
    </div>
  `;
}

function renderCandidateList(candidates) {
  if (!Array.isArray(candidates) || !candidates.length) {
    ui.candidateList.className = "entityList empty";
    ui.candidateList.textContent = "暂无候选任务";
    return;
  }
  ui.candidateList.className = "entityList";
  ui.candidateList.innerHTML = candidates
    .map((candidate) => {
      const header = candidate.header || {};
      const spec = candidate.spec || {};
      const state = candidate.state || {};
      return `
        <article class="entityCard">
          <div class="entityHeader">
            <div>
              <div class="entityTitle">${escapeHtml(spec.title || header.id || "Untitled Candidate")}</div>
              <div class="entityMeta">${escapeHtml(header.id || "")}</div>
            </div>
            <span class="statusChip">${escapeHtml(state.status || "")}</span>
          </div>
          <div class="entityBody">${escapeHtml(spec.objective || spec.mission_statement || "")}</div>
          ${actionButtons(candidate)}
        </article>
      `;
    })
    .join("");
}

function renderTaskList(tasks) {
  if (!Array.isArray(tasks) || !tasks.length) {
    ui.taskList.className = "entityList empty";
    ui.taskList.textContent = "暂无正式任务";
    return;
  }
  ui.taskList.className = "entityList";
  ui.taskList.innerHTML = tasks
    .map((task) => {
      const header = task.header || {};
      const spec = task.spec || {};
      const state = task.state || {};
      return `
        <article class="entityCard compact">
          <div class="entityHeader">
            <div>
              <div class="entityTitle">${escapeHtml(spec.title || header.id || "Untitled Task")}</div>
              <div class="entityMeta">${escapeHtml(header.id || "")}</div>
            </div>
            <span class="statusChip">${escapeHtml(state.status || "")}</span>
          </div>
          <div class="entityBody">${escapeHtml(spec.mission_statement || "")}</div>
        </article>
      `;
    })
    .join("");
}

function renderMailList(mailItems) {
  if (!Array.isArray(mailItems) || !mailItems.length) {
    ui.mailList.className = "entityList empty";
    ui.mailList.textContent = "暂无内邮";
    return;
  }
  ui.mailList.className = "entityList";
  ui.mailList.innerHTML = mailItems
    .map((item) => {
      const spec = item.spec || {};
      const state = item.state || {};
      return `
        <article class="entityCard compact">
          <div class="entityHeader">
            <div class="entityTitle">${escapeHtml(spec.title || "Mail")}</div>
            <span class="statusChip">${escapeHtml(state.status || "")}</span>
          </div>
          <div class="entityBody">${escapeHtml(spec.summary || "")}</div>
        </article>
      `;
    })
    .join("");
}

function hydrateFromOverview(data) {
  renderOverview(data);
  renderCandidateList(data?.candidates || []);
  renderTaskList(data?.tasks || []);
  renderMailList(data?.mail || []);
  const caseId = data?.case?.header?.id || "";
  const rounds = Array.isArray(data?.rounds) ? data.rounds : [];
  const lastRound = rounds.length ? rounds[rounds.length - 1] : null;
  if (caseId) ui.caseIdInput.value = caseId;
  if (lastRound?.header?.id) ui.roundIdInput.value = lastRound.header.id;
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
    setHint("请先输入 workflow session id。", true);
    return;
  }
  setHint("正在创建案卷...");
  const created = await postJson("/api/cases", {
    workflow_session_id: workflowSessionId,
    title: ui.caseTitle.value.trim(),
    opening_brief: ui.openingBrief.value.trim(),
    current_summary: ui.currentSummary.value.trim(),
  });
  ui.caseIdInput.value = created?.case?.header?.id || "";
  ui.roundIdInput.value = created?.round?.header?.id || "";
  hydrateFromOverview({ case: created.case, rounds: [created.round], candidates: [], tasks: [], mail: [] });
  setHint("案卷已创建，可继续抽取候选任务。", false);
}

async function extractCandidates() {
  const caseId = ui.caseIdInput.value.trim();
  if (!caseId) {
    setHint("请先创建案卷或填入 case id。", true);
    return;
  }
  setHint("正在抽取候选任务...");
  const payload = {};
  if (ui.roundIdInput.value.trim()) payload.round_id = ui.roundIdInput.value.trim();
  const extracted = await postJson(`/api/cases/${encodeURIComponent(caseId)}/candidates/extract`, payload);
  hydrateFromOverview(extracted.overview);
  setHint(`已抽取 ${Array.isArray(extracted.candidates) ? extracted.candidates.length : 0} 个候选任务。`);
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
