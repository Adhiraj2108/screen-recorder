// Upload, playback (with seeking) and deletion, against a running app. Needs ffmpeg to make a test video.
//   npm run dev            then   node scripts/smoke-media.mjs
// Against the live copy: BASE_URL=https://… KEY_FILE=.prod.vars R2_FLAG=--remote node scripts/smoke-media.mjs
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const base = process.env.BASE_URL ?? "http://localhost:8787";
const r2Flag = process.env.R2_FLAG ?? "--local";
const key = readFileSync(new URL("../" + (process.env.KEY_FILE ?? ".dev.vars"), import.meta.url), "utf8").match(/^OWNER_KEY=(.+)$/m)?.[1];
if (!key) throw new Error("No OWNER_KEY found");

let failures = 0;
const check = (name, ok, detail = "") => { console.log(`${ok ? "PASS" : "FAIL"}  ${name}${ok ? "" : "  " + detail}`); if (!ok) failures += 1; };
const sha = (bytes) => createHash("sha256").update(bytes).digest("hex");
const auth = { Authorization: `Bearer ${key}` };
const send = (method, path, { headers = {}, body, json } = {}) =>
  fetch(base + path, { method, headers: { ...(json ? { "Content-Type": "application/json" } : {}), ...headers }, body: json ? JSON.stringify(json) : body });

// A real MP4 of about 20 MB (noise compresses badly, which is what we want here), so it spans three 8 MB parts.
const dir = mkdtempSync(join(tmpdir(), "recorder-"));
const file = join(dir, "test.mp4");
execFileSync("ffmpeg", ["-loglevel", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=1280x720:rate=30", "-f", "lavfi", "-i", "anoisesrc=d=20:c=pink", "-t", "20",
  "-vf", "noise=alls=60:allf=t", "-c:v", "libx264", "-b:v", "8M", "-maxrate", "8M", "-bufsize", "8M", "-pix_fmt", "yuv420p", "-c:a", "aac", "-movflags", "+faststart", file]);
const bytes = readFileSync(file);
const size = bytes.length;
console.log(`test video: ${(size / 1e6).toFixed(1)} MB`);

const video = await (await send("POST", "/api/videos", { headers: auth, json: { title: "Media test" } })).json();
const share = await (await send("POST", `/api/videos/${video.id}/shares`, { headers: auth, json: {} })).json();

// Before any upload
check("share page says the video isn't ready", (await (await send("GET", `/s/${share.token}`)).text()).includes("isn’t ready"));
check("no playback address before upload", (await send("POST", `/s/${share.token}/play`)).status === 404);
check("upload needs the owner key", (await send("POST", `/api/videos/${video.id}/upload`, { json: { size } })).status === 401);
check("a part can't be sent before the upload starts", (await send("PUT", `/api/videos/${video.id}/upload/parts/1`, { headers: auth, body: bytes.subarray(0, 1000) })).status === 409);
check("oversized file refused", (await send("POST", `/api/videos/${video.id}/upload`, { headers: auth, json: { size: 5 * 1024 ** 3 } })).status === 400);

// Upload in parts, with an interruption
const started = await (await send("POST", `/api/videos/${video.id}/upload`, { headers: auth, json: { size } })).json();
const partSize = started.part_size;
const total = Math.ceil(size / partSize);
check("upload starts with 8 MB parts", partSize === 8 * 1024 * 1024 && total >= 3, `${partSize} ${total}`);
check("a non-MP4 first part is refused", (await send("PUT", `/api/videos/${video.id}/upload/parts/1`, { headers: auth, body: new Uint8Array(2000).fill(65) })).status === 400);
const part = (n) => bytes.subarray((n - 1) * partSize, Math.min(size, n * partSize));
check("part 1 uploads", (await send("PUT", `/api/videos/${video.id}/upload/parts/1`, { headers: auth, body: part(1) })).status === 200);
check("finishing early is refused", (await send("POST", `/api/videos/${video.id}/upload/complete`, { headers: auth })).status === 409);

// "Interruption": ask again for the same file and carry on from what arrived
const resumed = await (await send("POST", `/api/videos/${video.id}/upload`, { headers: auth, json: { size } })).json();
check("resuming reports the parts already sent", resumed.upload_id === started.upload_id && resumed.parts.length === 1 && resumed.parts[0].part_number === 1, JSON.stringify(resumed));
for (let n = 2; n <= total; n++) {
  const response = await send("PUT", `/api/videos/${video.id}/upload/parts/${n}`, { headers: auth, body: part(n) });
  if (response.status !== 200) check(`part ${n} uploads`, false, String(response.status));
}
const done = await send("POST", `/api/videos/${video.id}/upload/complete`, { headers: auth });
const doneBody = await done.json();
check("upload completes", done.status === 200 && doneBody.status === "ready" && doneBody.size_bytes === size, JSON.stringify(doneBody));
check("a finished video can't be uploaded over", (await send("POST", `/api/videos/${video.id}/upload`, { headers: auth, json: { size } })).status === 409);

// Playback, the way a browser does it
const page = await (await send("GET", `/s/${share.token}`)).text();
check("share page has the player and speed buttons", page.includes("<video") && page.includes("Playback speed"));
const play = await send("POST", `/s/${share.token}/play`);
const { url: mediaPath } = await play.json();
check("a playback address is issued", play.status === 200 && /^\/m\/[0-9a-f-]{36}\?e=\d+&s=/.test(mediaPath), mediaPath);
const get = (headers = {}, path = mediaPath) => fetch(base + path, { headers });

const whole = await get();
const wholeBytes = new Uint8Array(await whole.arrayBuffer());
check("whole file plays back byte for byte", whole.status === 200 && sha(wholeBytes) === sha(bytes) && whole.headers.get("accept-ranges") === "bytes" && whole.headers.get("content-type") === "video/mp4");
const first = await get({ Range: "bytes=0-1" });
check("Safari's first probe (bytes=0-1) gets a 206", first.status === 206 && first.headers.get("content-range") === `bytes 0-1/${size}` && (await first.arrayBuffer()).byteLength === 2);
const mid = await get({ Range: "bytes=1000000-1999999" });
check("a seek into the middle returns exactly that slice", mid.status === 206 && mid.headers.get("content-range") === `bytes 1000000-1999999/${size}` && sha(new Uint8Array(await mid.arrayBuffer())) === sha(bytes.subarray(1000000, 2000000)));
const open = await get({ Range: "bytes=19000000-" });
check("open-ended range runs to the end", open.status === 206 && sha(new Uint8Array(await open.arrayBuffer())) === sha(bytes.subarray(19000000)));
const tail = await get({ Range: "bytes=-500" });
check("suffix range returns the last 500 bytes", tail.status === 206 && sha(new Uint8Array(await tail.arrayBuffer())) === sha(bytes.subarray(size - 500)));
const past = await get({ Range: `bytes=${size + 10}-` });
check("range past the end gets 416", past.status === 416 && past.headers.get("content-range") === `bytes */${size}`);
const head = await fetch(base + mediaPath, { method: "HEAD" });
check("HEAD reports the size", head.status === 200 && head.headers.get("content-length") === String(size));
check("playback is private (no-store, noindex)", whole.headers.get("cache-control") === "private, no-store" && (whole.headers.get("x-robots-tag") ?? "").includes("noindex"));

// Addresses can't be forged or reused elsewhere
const [pathOnly, query] = mediaPath.split("?");
check("tampered signature refused", (await get({}, `${pathOnly}?${query.replace(/s=./, "s=X")}`)).status === 404);
check("expired address refused", (await get({}, `${pathOnly}?e=1000&s=${new URLSearchParams(query).get("s")}`)).status === 404);
check("address for another share refused", (await get({}, `/m/00000000-0000-4000-8000-000000000000?${query}`)).status === 404);
check("no signature refused", (await get({}, pathOnly)).status === 404);

// Switching the link off ends playback at once, even with an address already issued
const revoked = await send("POST", `/api/shares/${share.id}/revoke`, { headers: auth });
check("revoke works", revoked.status === 200);
check("an issued address stops working immediately", (await get({ Range: "bytes=0-1" })).status === 404);
check("no new address after revoke", (await send("POST", `/s/${share.token}/play`)).status === 404);

// Deleting removes the stored file
const second = await (await send("POST", `/api/videos/${video.id}/shares`, { headers: auth, json: {} })).json();
const objectName = `recorder-videos/videos/${video.id}/original.mp4`;
const exists = () => { try { execFileSync("npx", ["wrangler", "r2", "object", "get", objectName, r2Flag, "--file", join(dir, "check.bin")], { stdio: "pipe", cwd: new URL("..", import.meta.url).pathname }); return true; } catch { return false; } };
check("the file is in the bucket before delete", exists());
check("delete works", (await send("DELETE", `/api/videos/${video.id}`, { headers: auth })).status === 200);
check("the file is gone from the bucket after delete", !exists());
check("links to a deleted video are off", (await send("GET", `/s/${second.token}`)).status === 404);

// Cancelling an upload
const cancelVideo = await (await send("POST", "/api/videos", { headers: auth, json: { title: "Cancel test" } })).json();
await send("POST", `/api/videos/${cancelVideo.id}/upload`, { headers: auth, json: { size: 20_000_000 } });
check("a part uploads for the cancel test", (await send("PUT", `/api/videos/${cancelVideo.id}/upload/parts/1`, { headers: auth, body: bytes.subarray(0, partSize) })).status === 200);
check("cancel works", (await send("DELETE", `/api/videos/${cancelVideo.id}/upload`, { headers: auth })).status === 200);
const status = await (await send("GET", `/api/videos/${cancelVideo.id}/upload`, { headers: auth })).json();
check("cancelled upload is back to draft with no parts", status.status === "draft" && status.parts.length === 0, JSON.stringify(status));
await send("DELETE", `/api/videos/${cancelVideo.id}`, { headers: auth });

console.log(failures ? `\n${failures} check(s) failed` : "\nAll media checks passed");
process.exit(failures ? 1 : 0);
