const $ = (id) => document.getElementById(id);

function qs(name) {
  return new URLSearchParams(window.location.search).get(name);
}

function escapeHtml(s) {
  return String(s)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
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
  if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);
  return data;
}

function setupMarkedNoHtml() {
  if (!window.marked) return;
  const renderer = new window.marked.Renderer();
  // Disallow raw HTML inside markdown to avoid accidental script injection.
  renderer.html = (html) => escapeHtml(html);
  window.marked.setOptions({
    renderer,
    mangle: false,
    headerIds: false,
  });
}

function isMarkdown(path) {
  const p = (path || "").toLowerCase();
  return p.endsWith(".md") || p.endsWith(".markdown");
}

function renderDoc(content, path) {
  const host = $("doc");
  host.innerHTML = "";
  if (isMarkdown(path) && window.marked) {
    const html = window.marked.parse(content || "");
    host.innerHTML = html;
    return;
  }
  const pre = document.createElement("pre");
  pre.textContent = content || "";
  host.appendChild(pre);
}

function downloadText(filename, content) {
  const blob = new Blob([content || ""], { type: "text/plain;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename || "document.txt";
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

async function load() {
  const sid = qs("sid") || qs("workflow_session_id") || "";
  const path = qs("path") || "";
  $("docPath").textContent = path ? path : "missing path";

  if (!sid || !path) {
    $("doc").innerHTML = `<div class="error">missing sid/path\n\nuse: /view/workspace.html?sid=&lt;workflow_session_id&gt;&path=workspace:deliverables/...</div>`;
    return;
  }

  const res = await postJson("/api/workspace/read", {
    workflow_session_id: sid,
    path,
  });

  const content = res.content || "";
  renderDoc(content, path);

  $("btnDownload").onclick = () => {
    const base = path.split("/").slice(-1)[0] || "document.md";
    downloadText(base, content);
  };
}

setupMarkedNoHtml();
$("btnReload").onclick = () => load().catch((e) => showErr(e));

function showErr(e) {
  $("doc").innerHTML = `<div class="error">${escapeHtml(e?.message || String(e))}</div>`;
}

load().catch((e) => showErr(e));

