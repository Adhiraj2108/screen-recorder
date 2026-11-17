// Checks the owner-only area and share links against a running `npm run dev` (default http://localhost:8787).
// Reads the owner key from .dev.vars and never prints it.
import { readFileSync } from "node:fs";

const base = process.env.BASE_URL ?? "http://localhost:8787";
const key = readFileSync(new URL("../" + (process.env.KEY_FILE ?? ".dev.vars"), import.meta.url), "utf8").match(/^OWNER_KEY=(.+)$/m)?.[1];
if (!key) throw new Error("No OWNER_KEY in .dev.vars");

let failures = 0;
const check = (name, ok, detail = "") => {
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${ok ? "" : "  " + detail}`);
  if (!ok) failures += 1;
};
const bearer = { Authorization: `Bearer ${key}` };
const send = (method, path, { headers = {}, body } = {}) =>
  fetch(base + path, { method, redirect: "manual", headers: { ...(body ? { "Content-Type": "application/json" } : {}), ...headers }, body: body ? JSON.stringify(body) : undefined });

// Not signed in
check("health is open", (await send("GET", "/health")).status === 200);
check("videos list needs sign-in", (await send("GET", "/api/videos")).status === 401);
check("wrong bearer key refused", (await send("GET", "/api/videos", { headers: { Authorization: "Bearer not-the-key-not-the-key-12345" } })).status === 401);
check("creating a video needs sign-in", (await send("POST", "/api/videos", { body: { title: "x" } })).status === 401);

// Sign in with the page's own origin
const origin = { Origin: base };
const bad = await send("POST", "/admin/login", { headers: origin, body: { key: "wrong-key-wrong-key-wrong-key" } });
check("wrong key can't sign in", bad.status === 401);
check("login from another site refused", (await send("POST", "/admin/login", { headers: { Origin: "https://evil.example" }, body: { key } })).status === 403);
const login = await send("POST", "/admin/login", { headers: origin, body: { key } });
check("right key signs in", login.status === 200);
const cookie = (login.headers.get("set-cookie") ?? "").split(";")[0];
check("session cookie is HttpOnly + SameSite=Strict", /HttpOnly/i.test(login.headers.get("set-cookie") ?? "") && /SameSite=Strict/i.test(login.headers.get("set-cookie") ?? ""));
const session = { Cookie: cookie, ...origin };
check("cookie session can list", (await send("GET", "/api/videos", { headers: { Cookie: cookie } })).status === 200);
check("cookie change from another site refused", (await send("POST", "/api/videos", { headers: { Cookie: cookie, Origin: "https://evil.example" }, body: { title: "x" } })).status === 403);
check("cookie change with no origin refused", (await send("POST", "/api/videos", { headers: { Cookie: cookie }, body: { title: "x" } })).status === 403);
check("forged cookie refused", (await send("GET", "/api/videos", { headers: { Cookie: "owner_session=9999999999.forged" } })).status === 401);

// Videos
const created = await (await send("POST", "/api/videos", { headers: session, body: { title: "  Brand   walkthrough " } })).json();
check("create trims the title", created.title === "Brand walkthrough", JSON.stringify(created));
check("empty title refused", (await send("POST", "/api/videos", { headers: session, body: { title: "   " } })).status === 400);
check("rename works", (await send("PATCH", `/api/videos/${created.id}`, { headers: session, body: { title: "Renamed" } })).status === 200);

// Share links
check("odd link scheme refused", (await send("POST", `/api/videos/${created.id}/shares`, { headers: session, body: { link_url: "javascript:alert(1)" } })).status === 400);
const share = await (await send("POST", `/api/videos/${created.id}/shares`, { headers: bearer, body: { link_url: "https://www.figma.com/file/abc", link_label: "Open the Figma file" } })).json();
check("share link is opaque and long", /^[A-Za-z0-9_-]{30,}$/.test(share.token ?? ""), share.token);
const publicPage = await send("GET", `/s/${share.token}`);
const publicText = await publicPage.text();
check("anyone with the link can open it", publicPage.status === 200 && publicText.includes("Renamed"));
check("viewing page shows the extra link", publicText.includes("https://www.figma.com/file/abc"));
check("viewing page is private to search engines", (publicPage.headers.get("x-robots-tag") ?? "").includes("noindex") && publicPage.headers.get("cache-control") === "no-store");
check("guessed token gets 404", (await send("GET", "/s/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")).status === 404);
const listed = await (await send("GET", "/api/videos", { headers: session })).json();
check("owner list shows the video and its link", listed.videos.find((v) => v.id === created.id)?.shares?.[0]?.active === true);

// Switching a link off
check("revoke works", (await send("POST", `/api/shares/${share.id}/revoke`, { headers: session })).status === 200);
check("revoked link no longer opens", (await send("GET", `/s/${share.token}`)).status === 404);

// Deleting a video switches off every link
const second = await (await send("POST", `/api/videos/${created.id}/shares`, { headers: session, body: {} })).json();
check("a new link opens", (await send("GET", `/s/${second.token}`)).status === 200);
check("delete works", (await send("DELETE", `/api/videos/${created.id}`, { headers: session })).status === 200);
check("deleting a video switches off its links", (await send("GET", `/s/${second.token}`)).status === 404);
check("deleted video leaves the list", !(await (await send("GET", "/api/videos", { headers: session })).json()).videos.some((v) => v.id === created.id));

// Sign out
const out = await send("POST", "/admin/logout", { headers: session });
check("sign out clears the cookie", out.status === 200 && /Max-Age=0/i.test(out.headers.get("set-cookie") ?? ""));

console.log(failures ? `\n${failures} check(s) failed` : "\nAll checks passed");
process.exit(failures ? 1 : 0);
