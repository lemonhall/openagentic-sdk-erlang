const el = (id) => document.getElementById(id);

const ui = {
  reconsiderationPreview: el("reconsiderationPreview"),
  reconsiderationHint: el("reconsiderationHint"),
  reconsiderationLifecycleHint: el("reconsiderationLifecycleHint"),
  reconsiderationBaselinePanel: el("reconsiderationBaselinePanel"),
  reconsiderationChangesPanel: el("reconsiderationChangesPanel"),
  reconsiderationControversiesPanel: el("reconsiderationControversiesPanel"),
  btnStartReconsideration: el("btnStartReconsideration"),
  btnDeferReconsideration: el("btnDeferReconsideration"),
};

const searchParams = new URLSearchParams(window.location.search);

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
  if (!ui.reconsiderationHint) return;
  ui.reconsiderationHint.textContent = text;
  ui.reconsiderationHint.classList.toggle("errorText", isError);
}

function setLifecycleHint(text, isError = false) {
  if (!ui.reconsiderationLifecycleHint) return;
  ui.reconsiderationLifecycleHint.textContent = text;
  ui.reconsiderationLifecycleHint.classList.toggle("errorText", isError);
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
  if (!response.ok) throw new Error(data.error || `HTTP ${response.status}`);
  return data;
}

async function postJson(url, body) {
  return fetchJson(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body || {}),
  });
}

function renderPreview(data) {
  const payload = data?.preview || {};
  const packageMeta = data?.reconsideration_package || {};
  const packageState = packageMeta.state || {};
  const caseMeta = payload.case || {};
  const roundMeta = payload.based_on_round || {};
  const packMeta = payload.observation_pack || {};
  const reviewMeta = payload.inspection_review || {};
  const summary = payload.summary || {};
  const reports = Array.isArray(payload.reports) ? payload.reports : [];
  const baselineFacts = Array.isArray(payload.baseline_facts) ? payload.baseline_facts : [];
  const changeFacts = Array.isArray(payload.change_facts) ? payload.change_facts : [];
  const urgentRefs = Array.isArray(payload.urgent_refs) ? payload.urgent_refs : [];
  const reviewHistory = Array.isArray(reviewMeta.status_history) ? reviewMeta.status_history : [];
  const reviewFlow = reviewHistory.map((item) => item?.status || "").filter(Boolean).join(" -> ");
  const packageDisplayCode = packageState.display_code || data?.reconsideration_session_context?.package_display_code || "";
  const packageVersionNo = packageState.version_no || data?.reconsideration_session_context?.package_version_no || "";
  const controversies = Array.isArray(summary.controversies) ? summary.controversies : [];
  ui.reconsiderationPreview.className = "overviewCard";
  ui.reconsiderationPreview.innerHTML = `
    <div class="overviewTitle">${escapeHtml(caseMeta.title || "未命名案卷")}</div>
    <div class="overviewMeta">${escapeHtml(packMeta.title || "观察包")}</div>
    <div class="overviewMeta">卷宗编号：${escapeHtml(packageDisplayCode || "unknown")}${packageVersionNo ? ` · 第${escapeHtml(String(packageVersionNo))}版` : ""}</div>
    <div class="overviewSummary">${escapeHtml(summary.trigger_reason || "暂无触发原因")}</div>
    <div class="overviewFacts">
      <div class="overviewFact"><div class="overviewFactLabel">检察结论</div><div class="overviewFactValue">${escapeHtml(reviewMeta.status || "")}</div></div>
      <div class="overviewFact"><div class="overviewFactLabel">检察过程</div><div class="overviewFactValue">${escapeHtml(reviewFlow || reviewMeta.process_state || reviewMeta.status || "")}</div></div>
      <div class="overviewFact"><div class="overviewFactLabel">争议条目</div><div class="overviewFactValue">${escapeHtml(String((summary.controversies || []).length))}</div></div>
      <div class="overviewFact"><div class="overviewFactLabel">纳入报告</div><div class="overviewFactValue">${escapeHtml(String(reports.length))}</div></div>
      <div class="overviewFact"><div class="overviewFactLabel">重大急报</div><div class="overviewFactValue">${escapeHtml(String(urgentRefs.length))}</div></div>
    </div>
    <div class="overviewMeta">上一轮：${escapeHtml(roundMeta.id || "unknown")}</div>
    <div class="entityList">
      ${reports.map((report) => `<article class="entityCard compact"><div class="entityTitle">${escapeHtml(report.task_id || report.report_id || "报告")}</div><div class="entityBody">${escapeHtml(report.result_summary || report.delta_summary || "暂无摘要")}</div></article>`).join("")}
    </div>
  `;

  renderLifecycleState(packageState, packageMeta.links || {});
  renderPanel(
    ui.reconsiderationBaselinePanel,
    baselineFacts,
    "暂无基线摘要",
    (item) => `<article class="entityCard compact"><div class="entityTitle">${escapeHtml(item.category || "基线")}</div><div class="entityBody">${escapeHtml(item.summary || "")}</div></article>`
  );
  renderPanel(
    ui.reconsiderationChangesPanel,
    changeFacts,
    "暂无变化事实",
    (item) => `<article class="entityCard compact"><div class="entityTitle">${escapeHtml(item.category || "变化")}</div><div class="entityBody">${escapeHtml(item.summary || item.delta_summary || "")}</div></article>`
  );
  renderPanel(
    ui.reconsiderationControversiesPanel,
    controversies,
    "暂无争议条目",
    (item) => `<article class="entityCard compact"><div class="entityTitle">${escapeHtml(item.title || item.id || "争议")}</div><div class="entityBody">${escapeHtml(item.summary || item.question || "")}</div></article>`
  );
}

function renderPanel(node, items, emptyText, renderItem) {
  if (!node) return;
  if (!Array.isArray(items) || !items.length) {
    node.className = "entityList empty";
    node.textContent = emptyText;
    return;
  }
  node.className = "entityList";
  node.innerHTML = items.map((item) => renderItem(item || {})).join("");
}

function renderLifecycleState(state, links) {
  const status = String(state?.status || "").trim();
  const consumedBy = links?.consumed_by_round_id || "";
  if (status === "consumed_by_round") {
    setLifecycleHint(`当前卷宗已被复议轮次采用：${consumedBy || "unknown"}`);
    if (ui.btnStartReconsideration) ui.btnStartReconsideration.disabled = true;
    if (ui.btnDeferReconsideration) ui.btnDeferReconsideration.disabled = true;
    return;
  }
  if (status === "superseded") {
    setLifecycleHint("当前卷宗已被新版卷宗替代，请优先查看新版。", true);
    if (ui.btnStartReconsideration) ui.btnStartReconsideration.disabled = true;
    if (ui.btnDeferReconsideration) ui.btnDeferReconsideration.disabled = true;
    return;
  }
  if (status === "deferred") {
    setLifecycleHint("当前卷宗处于继续观察状态；若仍在新鲜期内，可稍后重新开启复议。");
    if (ui.btnStartReconsideration) ui.btnStartReconsideration.disabled = false;
    if (ui.btnDeferReconsideration) ui.btnDeferReconsideration.disabled = false;
    return;
  }
  setLifecycleHint("当前卷宗已整理完毕，可先阅卷再决定是否开启复议。");
  if (ui.btnStartReconsideration) ui.btnStartReconsideration.disabled = false;
  if (ui.btnDeferReconsideration) ui.btnDeferReconsideration.disabled = false;
}

async function loadPreview() {
  const caseId = queryValue("case_id", "caseId");
  const packageId = queryValue("package_id", "packageId");
  if (!caseId || !packageId) {
    setHint("缺少 case_id 或 package_id。", true);
    return;
  }
  const data = await fetchJson(`/api/cases/${encodeURIComponent(caseId)}/reconsideration-packages/${encodeURIComponent(packageId)}/preview`);
  renderPreview(data);
  setHint("卷宗预览已更新。", false);
}

async function startReconsideration() {
  const caseId = queryValue("case_id", "caseId");
  const packageId = queryValue("package_id", "packageId");
  const data = await postJson(`/api/cases/${encodeURIComponent(caseId)}/reconsideration-packages/${encodeURIComponent(packageId)}/start`, { started_by_op_id: "web_user" });
  setHint(`已开启复议轮次：${data?.round?.header?.id || "unknown"}`);
  await loadPreview();
}

async function deferReconsideration() {
  const caseId = queryValue("case_id", "caseId");
  const packageId = queryValue("package_id", "packageId");
  await postJson(`/api/cases/${encodeURIComponent(caseId)}/reconsideration-packages/${encodeURIComponent(packageId)}/defer`, { acted_by_op_id: "web_user" });
  setHint("当前卷宗已标记为继续观察。", false);
  await loadPreview();
}

ui.btnStartReconsideration?.addEventListener("click", async () => {
  try {
    await startReconsideration();
  } catch (error) {
    setHint(error.message || String(error), true);
  }
});

ui.btnDeferReconsideration?.addEventListener("click", async () => {
  try {
    await deferReconsideration();
  } catch (error) {
    setHint(error.message || String(error), true);
  }
});

void loadPreview();
