const escapeHtml = (text: string) =>
  text.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c] ?? c);

const baseStyles = `
  :root { color-scheme: light dark; --bg: #f6f5f2; --card: #fff; --text: #1d1d1b; --muted: #6b6a66; --line: rgba(0,0,0,.1); --accent: #1d1d1b; --accent-text: #fff; --danger: #b3261e; }
  @media (prefers-color-scheme: dark) { :root { --bg: #171716; --card: #222221; --text: #f1f0ec; --muted: #a3a29d; --line: rgba(255,255,255,.14); --accent: #f1f0ec; --accent-text: #171716; --danger: #f2b8b5; } }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--text); font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
  main { max-width: 760px; margin: 0 auto; padding: 32px 16px 64px; }
  h1 { font-size: 22px; font-weight: 600; margin: 0 0 4px; }
  p { margin: 0 0 12px; } .muted { color: var(--muted); }
  .card { background: var(--card); border: 1px solid var(--line); border-radius: 10px; padding: 16px; margin: 12px 0; }
  input[type=text], input[type=password], input[type=url] { width: 100%; padding: 9px 11px; border: 1px solid var(--line); border-radius: 7px; background: transparent; color: inherit; font: inherit; }
  button { padding: 8px 14px; border-radius: 7px; border: 1px solid var(--line); background: transparent; color: inherit; font: inherit; cursor: pointer; }
  button.primary { background: var(--accent); color: var(--accent-text); border-color: var(--accent); }
  button.danger { color: var(--danger); }
  .row { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
  .grow { flex: 1 1 200px; }
  .badge { font-size: 12px; padding: 2px 8px; border-radius: 99px; border: 1px solid var(--line); color: var(--muted); }
  .msg { color: var(--danger); min-height: 1.4em; }
  code { font-size: 13px; word-break: break-all; }
`;

const head = (title: string) =>
  `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>${escapeHtml(title)}</title><style>${baseStyles}</style></head>`;

/** The public page behind a share link. The player arrives with the upload step; for now it confirms the link works. */
export function sharePage(video: { title: string; status: string; link_url: string | null; link_label: string | null }): string {
  const extra = video.link_url
    ? `<p><a href="${escapeHtml(video.link_url)}" target="_blank" rel="noopener noreferrer">${escapeHtml(video.link_label || "Open the linked page")}</a></p>`
    : "";
  return `${head(video.title)}<body><main><h1>${escapeHtml(video.title)}</h1>
<div class="card"><p class="muted">The video will play here once it has been uploaded and processed.</p></div>${extra}</main></body></html>`;
}

/** Same page for a link that never existed, was switched off, or points at a deleted video. */
export function notFoundPage(): string {
  return `${head("Link not available")}<body><main><h1>This link isn’t available</h1><p class="muted">It may have been switched off. Ask the sender for a new one.</p></main></body></html>`;
}

/** The owner page: sign in with the key, then find, rename, share, switch off and delete videos. */
export function adminPage(): string {
  return `${head("Screen Recorder · Owner")}<body><main>
<h1>Screen Recorder</h1><p class="muted">Your videos and share links. Only you can see this page.</p>
<div id="login" class="card" hidden>
  <p>Sign in with your owner key.</p>
  <form id="loginForm" class="row"><input class="grow" type="password" id="key" autocomplete="current-password" placeholder="Owner key" required><button class="primary">Sign in</button></form>
</div>
<div id="app" hidden>
  <div class="card"><form id="newForm" class="row"><input class="grow" type="text" id="newTitle" maxlength="200" placeholder="New video title" required><button class="primary">Add video</button></form></div>
  <div id="list"></div>
  <p class="row"><button id="logout">Sign out</button></p>
</div>
<p class="msg" id="msg" role="status"></p>
<script>
const $ = (id) => document.getElementById(id);
const say = (text) => { $("msg").textContent = text || ""; };
async function call(method, path, body) {
  const response = await fetch(path, { method, headers: body ? { "Content-Type": "application/json" } : {}, body: body ? JSON.stringify(body) : undefined });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) { const e = new Error(data.error || "Something went wrong."); e.status = response.status; throw e; }
  return data;
}
function el(tag, props, ...children) {
  const node = Object.assign(document.createElement(tag), props || {});
  for (const child of children) node.append(child);
  return node;
}
async function load() {
  try {
    const { videos } = await call("GET", "/api/videos");
    $("login").hidden = true; $("app").hidden = false; render(videos);
  } catch (e) {
    if (e.status === 401) { $("app").hidden = true; $("login").hidden = false; } else say(e.message);
  }
}
function act(fn) { return async () => { say(""); try { await fn(); await load(); } catch (e) { say(e.message); } }; }
function render(videos) {
  const list = $("list"); list.replaceChildren();
  if (!videos.length) list.append(el("p", { className: "muted" }, "No videos yet."));
  for (const video of videos) {
    const title = el("input", { type: "text", value: video.title, maxLength: 200, className: "grow", ariaLabel: "Video title" });
    const card = el("div", { className: "card" },
      el("div", { className: "row" }, title,
        el("button", { onclick: act(() => call("PATCH", "/api/videos/" + video.id, { title: title.value })) }, "Rename"),
        el("span", { className: "badge" }, video.status)));
    const linkUrl = el("input", { type: "url", placeholder: "Optional: Figma or staging link", className: "grow" });
    const linkLabel = el("input", { type: "text", placeholder: "Link label", maxLength: 80, style: "max-width:160px" });
    card.append(el("div", { className: "row", style: "margin-top:10px" }, linkUrl, linkLabel,
      el("button", { onclick: act(() => call("POST", "/api/videos/" + video.id + "/shares", { link_url: linkUrl.value, link_label: linkLabel.value })) }, "Create share link")));
    for (const share of video.shares) {
      const row = el("div", { className: "row", style: "margin-top:8px" },
        el("code", { className: "grow" }, share.url),
        el("span", { className: "badge" }, share.active ? "on" : "off"));
      if (share.active) {
        row.append(el("button", { onclick: async () => { await navigator.clipboard.writeText(share.url); say("Link copied."); } }, "Copy"),
          el("button", { className: "danger", onclick: act(() => call("POST", "/api/shares/" + share.id + "/revoke")) }, "Switch off"));
      }
      card.append(row);
    }
    card.append(el("div", { className: "row", style: "margin-top:10px" },
      el("button", { className: "danger", onclick: act(async () => { if (confirm("Delete this video and switch off all its links?")) await call("DELETE", "/api/videos/" + video.id); }) }, "Delete video")));
    list.append(card);
  }
}
$("loginForm").addEventListener("submit", async (event) => {
  event.preventDefault(); say("");
  try { await call("POST", "/admin/login", { key: $("key").value }); $("key").value = ""; await load(); } catch (e) { say(e.message); }
});
$("newForm").addEventListener("submit", async (event) => {
  event.preventDefault(); say("");
  try { await call("POST", "/api/videos", { title: $("newTitle").value }); $("newTitle").value = ""; await load(); } catch (e) { say(e.message); }
});
$("logout").addEventListener("click", async () => { await call("POST", "/admin/logout"); await load(); });
load();
</script></main></body></html>`;
}
