const el = (id) => document.getElementById(id);

const ui = {
  inboxFilterForm: el("inboxFilterForm"),
  inboxStatus: el("inboxStatus"),
  globalMailList: el("globalMailList"),
  inboxHint: el("inboxHint"),
};

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

function setHint(text, isError = false) {
  if (!ui.inboxHint) return;
  ui.inboxHint.textContent = text;
  ui.inboxHint.classList.toggle("errorText", isError);
}

function currentStatus() {
  return (ui.inboxStatus?.value || "all").trim() || "all";
}

function renderMailList(items) {
  if (!ui.globalMailList) return;
  if (!Array.isArray(items) || !items.length) {
    ui.globalMailList.className = "entityList empty";
    ui.globalMailList.textContent = "暂无内邮";
    return;
  }
  ui.globalMailList.className = "entityList";
  ui.globalMailList.innerHTML = items
    .map((item) => {
      const header = item.header || {};
      const spec = item.spec || {};
      const state = item.state || {};
      const links = item.links || {};
      const ext = item.ext || {};
      return `
        <article class="entityCard compact">
          <div class="entityHeader">
            <div>
              <div class="entityTitle">${escapeHtml(spec.title || "内邮")}</div>
              <div class="entityMeta">${escapeHtml(ext.case_title || links.case_id || "")}</div>
            </div>
            <span class="statusChip">${escapeHtml(state.status || "")}</span>
          </div>
          <div class="entityBody">${escapeHtml(spec.summary || "")}</div>
          <div class="caseActions">
            <button type="button" class="btn" data-action="read" data-case-id="${escapeHtml(links.case_id || "")}" data-id="${escapeHtml(header.id || "")}">标记已读</button>
            <button type="button" class="btn" data-action="archive" data-case-id="${escapeHtml(links.case_id || "")}" data-id="${escapeHtml(header.id || "")}">归档</button>
          </div>
        </article>
      `;
    })
    .join("");
}

async function loadInbox() {
  const status = currentStatus();
  const suffix = status && status !== "all" ? `?status=${encodeURIComponent(status)}` : "";
  setHint("正在加载统一信箱...");
  const data = await fetchJson(`/api/inbox${suffix}`);
  renderMailList(data?.mail || []);
  setHint("统一信箱已更新。", false);
}

async function updateMail(caseId, mailId, action) {
  const url = `/api/cases/${encodeURIComponent(caseId)}/mail/${encodeURIComponent(mailId)}/${encodeURIComponent(action)}`;
  await postJson(url, { acted_by_op_id: "web_user" });
  await loadInbox();
}

ui.inboxFilterForm?.addEventListener("submit", async (event) => {
  event.preventDefault();
  try {
    await loadInbox();
  } catch (error) {
    setHint(error.message || String(error), true);
  }
});

ui.globalMailList?.addEventListener("click", async (event) => {
  const button = event.target.closest("button[data-action]");
  if (!button) return;
  try {
    await updateMail(button.dataset.caseId || "", button.dataset.id || "", button.dataset.action || "read");
  } catch (error) {
    setHint(error.message || String(error), true);
  }
});

void loadInbox();
