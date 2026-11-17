import { authenticate, clearedCookie, keyMatches, ownerKeyUsable, playbackSignature, randomToken, sameOrigin, sessionCookie, signatureMatches } from "./auth";
import { MAX_BYTES, PART_SIZE, PLAYBACK_SECONDS, objectKey, serveVideo } from "./media";
import { adminPage, notFoundPage, sharePage } from "./pages";

interface Env {
  DB: D1Database;
  VIDEOS: R2Bucket;
  OWNER_KEY?: string;
}

interface VideoRow {
  id: string;
  title: string;
  status: string;
  stream_uid: string | null;
  duration_s: number | null;
  object_key: string | null;
  size_bytes: number | null;
  upload_id: string | null;
  uploaded_at: string | null;
  created_at: string;
  updated_at: string;
}

interface ShareRow {
  id: string;
  video_id: string;
  token: string;
  link_url: string | null;
  link_label: string | null;
  created_at: string;
  revoked_at: string | null;
}

const PRIVATE_HEADERS = {
  "Cache-Control": "no-store",
  "X-Robots-Tag": "noindex, nofollow",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
};

function json(data: unknown, status = 200, extra: HeadersInit = {}): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...PRIVATE_HEADERS, ...extra },
  });
}

function html(body: string, status = 200): Response {
  return new Response(body, {
    status,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; media-src 'self'; img-src 'self' data:; form-action 'self'; base-uri 'none'",
      ...PRIVATE_HEADERS,
    },
  });
}

const error = (status: number, message: string) => json({ error: message }, status);

/** Only web links, so a share can't carry a `javascript:` or other odd link onto the viewing page. */
function cleanLink(value: unknown): string | null {
  if (typeof value !== "string" || value.trim() === "") return null;
  try {
    const url = new URL(value.trim());
    return url.protocol === "https:" || url.protocol === "http:" ? url.toString() : null;
  } catch {
    return null;
  }
}

function cleanTitle(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const title = value.trim().replace(/\s+/g, " ");
  return title.length >= 1 && title.length <= 200 ? title : null;
}

async function readJson(request: Request): Promise<Record<string, unknown>> {
  try {
    const body = await request.json();
    return body && typeof body === "object" ? (body as Record<string, unknown>) : {};
  } catch {
    return {};
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const secure = url.protocol === "https:";
    const path = url.pathname;

    if (path === "/health") return json({ ok: true });

    // Public share link: /s/<opaque token>. Unknown, revoked and deleted all look the same.
    const shareMatch = path.match(/^\/s\/([A-Za-z0-9_-]{16,64})(\/play)?$/);
    if (shareMatch) {
      const [, shareToken, playPart] = shareMatch;
      const row = await env.DB.prepare(
        `SELECT s.id AS share_id, v.title, v.status, s.link_url, s.link_label
           FROM shares s JOIN videos v ON v.id = s.video_id
          WHERE s.token = ? AND s.revoked_at IS NULL AND v.deleted_at IS NULL`,
      )
        .bind(shareToken)
        .first<{ share_id: string; title: string; status: string; link_url: string | null; link_label: string | null }>();

      if (!playPart && request.method === "GET") return row ? html(sharePage(row)) : html(notFoundPage(), 404);

      // The page asks for a short-lived playback address; it's only issued while the link is on and the video is ready.
      if (playPart && request.method === "POST") {
        if (!row || row.status !== "ready") return error(404, "Not available.");
        if (!ownerKeyUsable(env)) return error(503, "Not set up.");
        const expires = Math.floor(Date.now() / 1000) + PLAYBACK_SECONDS;
        const signature = await playbackSignature({ OWNER_KEY: env.OWNER_KEY }, row.share_id, expires);
        return json({ url: `/m/${row.share_id}?e=${expires}&s=${signature}`, expires_in: PLAYBACK_SECONDS });
      }
    }

    // The video file itself, with Range support. Checked on every request, so switching a link off or deleting the
    // video stops playback immediately instead of when the address expires.
    const mediaMatch = path.match(/^\/m\/([0-9a-f-]{36})$/);
    if (mediaMatch && (request.method === "GET" || request.method === "HEAD")) {
      if (!ownerKeyUsable(env)) return error(503, "Not set up.");
      const expires = Number(url.searchParams.get("e"));
      const signature = url.searchParams.get("s") ?? "";
      const expected = await playbackSignature({ OWNER_KEY: env.OWNER_KEY }, mediaMatch[1], expires);
      if (!Number.isFinite(expires) || expires < Date.now() / 1000 || !(await signatureMatches(signature, expected))) {
        return error(404, "Not available.");
      }
      const media = await env.DB.prepare(
        `SELECT v.object_key, v.size_bytes
           FROM shares s JOIN videos v ON v.id = s.video_id
          WHERE s.id = ? AND s.revoked_at IS NULL AND v.deleted_at IS NULL AND v.status = 'ready'`,
      )
        .bind(mediaMatch[1])
        .first<{ object_key: string; size_bytes: number }>();
      if (!media) return error(404, "Not available.");
      return serveVideo(request, env.VIDEOS, media.object_key, media.size_bytes);
    }

    // Everything below is owner-only.
    if (!ownerKeyUsable(env)) {
      return error(503, "The owner key isn't set up. Set OWNER_KEY (24 or more characters) in the Worker's secrets.");
    }
    const ownerEnv = { OWNER_KEY: env.OWNER_KEY };

    if (path === "/" || path === "/admin") return html(adminPage());

    if (path === "/admin/login" && request.method === "POST") {
      if (!sameOrigin(request)) return error(403, "Sign in from the owner page.");
      const key = (await readJson(request)).key;
      if (typeof key !== "string" || !(await keyMatches(ownerEnv, key))) {
        await new Promise((resolve) => setTimeout(resolve, 600));
        return error(401, "That key isn't right.");
      }
      return json({ ok: true }, 200, { "Set-Cookie": await sessionCookie(ownerEnv, secure) });
    }
    if (path === "/admin/logout" && request.method === "POST") {
      return json({ ok: true }, 200, { "Set-Cookie": clearedCookie(secure) });
    }

    if (!path.startsWith("/api/")) return error(404, "Not found.");

    const auth = await authenticate(request, ownerEnv);
    if (!auth) return error(401, "Sign in first.");
    const changes = request.method !== "GET" && request.method !== "HEAD";
    if (changes && auth === "owner-cookie" && !sameOrigin(request)) return error(403, "Changes must come from the owner page.");

    // GET /api/videos
    if (path === "/api/videos" && request.method === "GET") {
      const videos = (await env.DB.prepare(`SELECT * FROM videos WHERE deleted_at IS NULL ORDER BY created_at DESC`).all<VideoRow>()).results;
      const shares = (await env.DB.prepare(
        `SELECT s.* FROM shares s JOIN videos v ON v.id = s.video_id WHERE v.deleted_at IS NULL ORDER BY s.created_at DESC`,
      ).all<ShareRow>()).results;
      const storage = await env.DB.prepare(`SELECT COALESCE(SUM(size_bytes), 0) AS bytes FROM videos WHERE deleted_at IS NULL AND status = 'ready'`).first<{ bytes: number }>();
      return json({
        storage_bytes: storage?.bytes ?? 0,
        videos: videos.map((video) => ({
          ...video,
          shares: shares
            .filter((share) => share.video_id === video.id)
            .map((share) => ({ ...share, url: `${url.origin}/s/${share.token}`, active: share.revoked_at === null })),
        })),
      });
    }

    // POST /api/videos  { title }
    if (path === "/api/videos" && request.method === "POST") {
      const title = cleanTitle((await readJson(request)).title);
      if (!title) return error(400, "Give the video a title (up to 200 characters).");
      const id = crypto.randomUUID();
      await env.DB.prepare(`INSERT INTO videos (id, title) VALUES (?, ?)`).bind(id, title).run();
      return json({ id, title, status: "draft" }, 201);
    }

    const videoMatch = path.match(/^\/api\/videos\/([0-9a-f-]{36})(\/shares)?$/);
    const uploadMatch = path.match(/^\/api\/videos\/([0-9a-f-]{36})\/upload(?:\/(complete)|\/parts\/(\d{1,5}))?$/);
    if (uploadMatch) {
      const [, id, completePart, partNumber] = uploadMatch;
      const video = await env.DB.prepare(`SELECT * FROM videos WHERE id = ? AND deleted_at IS NULL`).bind(id).first<VideoRow>();
      if (!video) return error(404, "No such video.");
      const key = objectKey(id);
      const partsSoFar = async () => (await env.DB.prepare(`SELECT part_number, size_bytes FROM upload_parts WHERE video_id = ? ORDER BY part_number`).bind(id).all()).results;

      // GET: where an interrupted upload stands, so the sender can carry on.
      if (request.method === "GET" && !completePart && !partNumber) {
        return json({ status: video.status, upload_id: video.upload_id, size_bytes: video.size_bytes, part_size: PART_SIZE, parts: await partsSoFar() });
      }

      // POST: start an upload (or pick up the one in progress for a file of the same size).
      if (request.method === "POST" && !completePart && !partNumber) {
        if (video.status === "ready") return error(409, "This video is already uploaded. Add a new video to upload another file.");
        const size = Number((await readJson(request)).size);
        if (!Number.isInteger(size) || size < 1 || size > MAX_BYTES) return error(400, "The file size is missing or too large (4 GB at most).");
        if (video.upload_id && video.size_bytes === size) {
          return json({ upload_id: video.upload_id, part_size: PART_SIZE, parts: await partsSoFar() });
        }
        if (video.upload_id) {
          await env.VIDEOS.resumeMultipartUpload(key, video.upload_id).abort().catch(() => undefined);
          await env.DB.prepare(`DELETE FROM upload_parts WHERE video_id = ?`).bind(id).run();
        }
        const upload = await env.VIDEOS.createMultipartUpload(key, { httpMetadata: { contentType: "video/mp4" } });
        await env.DB.prepare(`UPDATE videos SET status = 'uploading', upload_id = ?, size_bytes = ?, object_key = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ?`)
          .bind(upload.uploadId, size, key, id)
          .run();
        return json({ upload_id: upload.uploadId, part_size: PART_SIZE, parts: [] }, 201);
      }

      // PUT: one part of the file.
      if (request.method === "PUT" && partNumber) {
        const number = Number(partNumber);
        if (video.status !== "uploading" || !video.upload_id) return error(409, "Start the upload first.");
        if (number < 1 || number > 10000) return error(400, "Part number out of range.");
        const bytes = await request.arrayBuffer();
        if (bytes.byteLength < 1 || bytes.byteLength > PART_SIZE) return error(400, "A part must be between 1 byte and 8 MB.");
        // The first part must look like an MP4 file (the word "ftyp" at byte 4), so stray files are refused early.
        if (number === 1 && (bytes.byteLength < 8 || new TextDecoder().decode(new Uint8Array(bytes, 4, 4)) !== "ftyp")) {
          return error(400, "That doesn't look like an MP4 video.");
        }
        const part = await env.VIDEOS.resumeMultipartUpload(key, video.upload_id).uploadPart(number, bytes);
        await env.DB.prepare(`INSERT OR REPLACE INTO upload_parts (video_id, part_number, etag, size_bytes) VALUES (?, ?, ?, ?)`)
          .bind(id, number, part.etag, bytes.byteLength)
          .run();
        return json({ part_number: number, size_bytes: bytes.byteLength });
      }

      // POST …/complete: stitch the parts together once every one has arrived.
      if (request.method === "POST" && completePart) {
        if (video.status !== "uploading" || !video.upload_id) return error(409, "There is no upload in progress.");
        const parts = (await env.DB.prepare(`SELECT part_number, etag, size_bytes FROM upload_parts WHERE video_id = ? ORDER BY part_number`).bind(id).all<{ part_number: number; etag: string; size_bytes: number }>()).results;
        const total = parts.reduce((sum, part) => sum + part.size_bytes, 0);
        const contiguous = parts.every((part, index) => part.part_number === index + 1);
        if (!parts.length || !contiguous || total !== video.size_bytes) {
          return error(409, `Not every part has arrived yet (${total} of ${video.size_bytes} bytes). Send the rest, then finish.`);
        }
        try {
          await env.VIDEOS.resumeMultipartUpload(key, video.upload_id).complete(parts.map((part) => ({ partNumber: part.part_number, etag: part.etag })));
        } catch (cause) {
          return error(502, `The storage service couldn't finish the file. Try the upload again. (${cause instanceof Error ? cause.message : "unknown"})`);
        }
        const stored = await env.VIDEOS.head(key);
        await env.DB.batch([
          env.DB.prepare(`UPDATE videos SET status = 'ready', upload_id = NULL, size_bytes = ?, uploaded_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'), updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ?`).bind(stored?.size ?? total, id),
          env.DB.prepare(`DELETE FROM upload_parts WHERE video_id = ?`).bind(id),
        ]);
        return json({ status: "ready", size_bytes: stored?.size ?? total });
      }

      // DELETE: give up on the upload and discard what has arrived.
      if (request.method === "DELETE" && !completePart && !partNumber) {
        if (video.upload_id) await env.VIDEOS.resumeMultipartUpload(key, video.upload_id).abort().catch(() => undefined);
        await env.DB.batch([
          env.DB.prepare(`DELETE FROM upload_parts WHERE video_id = ?`).bind(id),
          env.DB.prepare(`UPDATE videos SET status = 'draft', upload_id = NULL, size_bytes = NULL WHERE id = ?`).bind(id),
        ]);
        return json({ ok: true });
      }
      return error(405, "Not supported.");
    }
    if (videoMatch) {
      const [, id, sharesPart] = videoMatch;
      const video = await env.DB.prepare(`SELECT id, upload_id FROM videos WHERE id = ? AND deleted_at IS NULL`).bind(id).first<{ id: string; upload_id: string | null }>();
      if (!video) return error(404, "No such video.");

      // PATCH /api/videos/:id  { title }
      if (!sharesPart && request.method === "PATCH") {
        const title = cleanTitle((await readJson(request)).title);
        if (!title) return error(400, "Give the video a title (up to 200 characters).");
        await env.DB.prepare(`UPDATE videos SET title = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ?`).bind(title, id).run();
        return json({ id, title });
      }

      // DELETE /api/videos/:id  (also switches off every link)
      if (!sharesPart && request.method === "DELETE") {
        // Remove the file first. If that fails the video stays in the list, so nothing is left behind unnoticed.
        try {
          if (video.upload_id) await env.VIDEOS.resumeMultipartUpload(objectKey(id), video.upload_id).abort().catch(() => undefined);
          await env.VIDEOS.delete(objectKey(id));
        } catch (cause) {
          return error(502, `The stored file couldn't be removed, so nothing was deleted. Try again. (${cause instanceof Error ? cause.message : "unknown"})`);
        }
        await env.DB.batch([
          env.DB.prepare(`DELETE FROM upload_parts WHERE video_id = ?`).bind(id),
          env.DB.prepare(`UPDATE shares SET revoked_at = COALESCE(revoked_at, strftime('%Y-%m-%dT%H:%M:%fZ','now')) WHERE video_id = ?`).bind(id),
          env.DB.prepare(`UPDATE videos SET deleted_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ?`).bind(id),
        ]);
        return json({ ok: true });
      }

      // POST /api/videos/:id/shares  { link_url?, link_label? }
      if (sharesPart && request.method === "POST") {
        const body = await readJson(request);
        const linkUrl = cleanLink(body.link_url);
        if (typeof body.link_url === "string" && body.link_url.trim() !== "" && !linkUrl) {
          return error(400, "The extra link must start with http:// or https://.");
        }
        const label = typeof body.link_label === "string" ? body.link_label.trim().slice(0, 80) || null : null;
        const shareId = crypto.randomUUID();
        const token = randomToken();
        await env.DB.prepare(`INSERT INTO shares (id, video_id, token, link_url, link_label) VALUES (?, ?, ?, ?, ?)`)
          .bind(shareId, id, token, linkUrl, label)
          .run();
        return json({ id: shareId, token, url: `${url.origin}/s/${token}` }, 201);
      }
    }

    // POST /api/shares/:id/revoke
    const revokeMatch = path.match(/^\/api\/shares\/([0-9a-f-]{36})\/revoke$/);
    if (revokeMatch && request.method === "POST") {
      const result = await env.DB.prepare(`UPDATE shares SET revoked_at = COALESCE(revoked_at, strftime('%Y-%m-%dT%H:%M:%fZ','now')) WHERE id = ?`)
        .bind(revokeMatch[1])
        .run();
      return result.meta.changes > 0 ? json({ ok: true }) : error(404, "No such link.");
    }

    return error(404, "Not found.");
  },
} satisfies ExportedHandler<Env>;
