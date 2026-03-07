const inboxLink = document.getElementById("inboxLink");
const inboxUnreadBadge = document.getElementById("inboxUnreadBadge");

function currentPageLabel() {
  const title = (document.title || "").trim();
  return title.replace(/^OpenAgentic\s*[·-]\s*/u, "").trim() || "当前页面";
}

function currentReturnTarget() {
  const path = `${window.location.pathname || "/"}${window.location.search || ""}`;
  if (!path.startsWith("/") || path.startsWith("//")) return "/";
  return path;
}

function syncInboxLink() {
  if (!inboxLink) return;
  const onInboxPage = window.location.pathname === "/view/inbox.html";
  if (onInboxPage) return;
  const params = new URLSearchParams();
  params.set("return_to", currentReturnTarget());
  params.set("return_label", currentPageLabel());
  inboxLink.href = `/view/inbox.html?${params.toString()}`;
}

function renderUnreadCount(count) {
  const unreadCount = Number.isFinite(count) && count > 0 ? count : 0;
  if (inboxUnreadBadge) {
    inboxUnreadBadge.textContent = unreadCount > 99 ? "99+" : String(unreadCount);
    inboxUnreadBadge.hidden = unreadCount <= 0;
  }
  if (inboxLink) {
    inboxLink.title = unreadCount > 0
      ? `统一信箱（${unreadCount} 条未读）`
      : "统一信箱（无未读）";
  }
}

async function loadInboxUnreadCount() {
  try {
    const response = await fetch("/api/inbox/unread-count", { cache: "no-store" });
    if (!response.ok) return;
    const data = await response.json();
    renderUnreadCount(Number(data?.unread_count || 0));
  } catch {
  }
}

syncInboxLink();
void loadInboxUnreadCount();
