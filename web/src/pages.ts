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
  button[aria-pressed=true] { background: var(--accent); color: var(--accent-text); border-color: var(--accent); }
`;

const head = (title: string) =>
  `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>${escapeHtml(title)}</title><style>${baseStyles}</style></head>`;

/** The public page behind a share link: title, player with speed and fullscreen, and the optional extra link. */
export function sharePage(video: { title: string; status: string; link_url: string | null; link_label: string | null }): string {
  const extra = video.link_url
    ? `<p><a href="${escapeHtml(video.link_url)}" target="_blank" rel="noopener noreferrer">${escapeHtml(video.link_label || "Open the linked page")}</a></p>`
    : "";
  const ready = video.status === "ready";
  const player = ready
    ? `<div class="card" style="padding:0;overflow:hidden;background:#000"><video id="v" controls playsinline preload="metadata" style="width:100%;display:block;max-height:80vh"></video></div>
<div class="row" id="speeds" role="group" aria-label="Playback speed"><span class="muted">Speed</span></div>
<p class="msg" id="msg" role="status"></p>
<script>
const v = document.getElementById("v"), msg = document.getElementById("msg");
const token = location.pathname.split("/").pop();
let renewTimer, failures = 0;
async function load(resume) {
  try {
    const response = await fetch("/s/" + token + "/play", { method: "POST" });
    if (!response.ok) { msg.textContent = "This video isn\u2019t available any more."; v.removeAttribute("src"); return; }
    const { url, expires_in } = await response.json();
    const at = resume ? v.currentTime : 0, playing = resume && !v.paused, rate = v.playbackRate;
    v.src = url;
    v.addEventListener("loadedmetadata", () => { if (at) v.currentTime = at; v.playbackRate = rate; if (playing) v.play().catch(() => {}); }, { once: true });
    clearTimeout(renewTimer);
    renewTimer = setTimeout(() => load(true), Math.max(60, expires_in - 300) * 1000);
    msg.textContent = "";
  } catch { msg.textContent = "Couldn\u2019t load the video. Check your connection and reload."; }
}
v.addEventListener("error", () => { if (++failures <= 3) load(true); else msg.textContent = "The video stopped loading. Reload the page to try again."; });
v.addEventListener("playing", () => { failures = 0; });
const speeds = document.getElementById("speeds");
for (const rate of [0.5, 1, 1.25, 1.5, 2]) {
  const button = document.createElement("button");
  button.textContent = rate + "\u00d7";
  button.setAttribute("aria-pressed", rate === 1 ? "true" : "false");
  button.onclick = () => { v.playbackRate = rate; for (const b of speeds.querySelectorAll("button")) b.setAttribute("aria-pressed", String(b === button)); };
  speeds.append(button);
}
load(false);
</script>`
    : `<div class="card"><p class="muted">${video.status === "uploading" ? "This video is still being uploaded. Check back in a few minutes." : "The video isn\u2019t ready yet."}</p></div>`;
  return `${head(video.title)}<body><main><h1>${escapeHtml(video.title)}</h1>
${player}${extra}</main></body></html>`;
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
  <p class="muted" id="storage"></p>
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
    const { videos, storage_bytes } = await call("GET", "/api/videos");
    $("login").hidden = true; $("app").hidden = false; render(videos);
    $("storage").textContent = "Stored videos: " + (storage_bytes / 1e6).toFixed(1) + " MB of the 10 GB free allowance.";
  } catch (e) {
    if (e.status === 401) { $("app").hidden = true; $("login").hidden = false; } else say(e.message);
  }
}
function act(fn) { return async () => { say(""); try { await fn(); await load(); } catch (e) { say(e.message); } }; }
async function putPart(id, number, blob) {
  for (let attempt = 0; attempt < 4; attempt++) {
    try {
      const response = await fetch("/api/videos/" + id + "/upload/parts/" + number, { method: "PUT", body: blob });
      if (response.ok) return;
      if (response.status < 500 && response.status !== 429) { const e = new Error((await response.json().catch(() => ({}))).error || "The upload was refused."); e.fatal = true; throw e; }
    } catch (e) { if (e.fatal) throw e; }
    await new Promise((resolve) => setTimeout(resolve, 1000 * 2 ** attempt));
  }
  throw new Error("The connection kept dropping. Choose the same file and press Upload video to carry on.");
}
async function upload(video, file, progress) {
  say("");
  try {
    const info = await call("POST", "/api/videos/" + video.id + "/upload", { size: file.size });
    const have = new Set(info.parts.map((part) => part.part_number));
    const total = Math.ceil(file.size / info.part_size);
    for (let n = 1; n <= total; n++) {
      progress.textContent = "Uploading\u2026 " + Math.floor(((n - 1) / total) * 100) + "%";
      if (have.has(n)) continue;
      await putPart(video.id, n, file.slice((n - 1) * info.part_size, n * info.part_size));
    }
    progress.textContent = "Finishing\u2026";
    await call("POST", "/api/videos/" + video.id + "/upload/complete");
    await load();
  } catch (e) { progress.textContent = ""; say(e.message); }
}
function render(videos) {
  const list = $("list"); list.replaceChildren();
  if (!videos.length) list.append(el("p", { className: "muted" }, "No videos yet."));
  for (const video of videos) {
    const title = el("input", { type: "text", value: video.title, maxLength: 200, className: "grow", ariaLabel: "Video title" });
    const card = el("div", { className: "card" },
      el("div", { className: "row" }, title,
        el("button", { onclick: act(() => call("PATCH", "/api/videos/" + video.id, { title: title.value })) }, "Rename"),
        el("span", { className: "badge" }, video.status)));
    if (video.status === "ready") {
      card.append(el("p", { className: "muted", style: "margin:8px 0 0" }, "Uploaded \u00b7 " + (video.size_bytes / 1e6).toFixed(1) + " MB"));
    } else {
      const file = el("input", { type: "file", accept: "video/mp4,.mp4", ariaLabel: "Video file (MP4)" });
      const progress = el("span", { className: "muted" }, video.status === "uploading" ? "Upload unfinished. Choose the same file to carry on." : "");
      card.append(el("div", { className: "row", style: "margin-top:10px" }, file,
        el("button", { onclick: async () => { if (file.files[0]) await upload(video, file.files[0], progress); else say("Choose an MP4 file first."); } }, "Upload video"), progress));
    }
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
