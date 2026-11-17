import { authenticate, clearedCookie, keyMatches, ownerKeyUsable, randomToken, sameOrigin, sessionCookie } from "./auth";
import { adminPage, notFoundPage, sharePage } from "./pages";

interface Env {
  DB: D1Database;
  OWNER_KEY?: string;
}

interface VideoRow {
  id: string;
  title: string;
  status: string;
  stream_uid: string | null;
  duration_s: number | null;
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
      "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; form-action 'self'; base-uri 'none'",
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
    const shareMatch = path.match(/^\/s\/([A-Za-z0-9_-]{16,64})$/);
    if (shareMatch && request.method === "GET") {
      const row = await env.DB.prepare(
        `SELECT v.id, v.title, v.status, s.link_url, s.link_label
           FROM shares s JOIN videos v ON v.id = s.video_id
          WHERE s.token = ? AND s.revoked_at IS NULL AND v.deleted_at IS NULL`,
      )
        .bind(shareMatch[1])
        .first<{ id: string; title: string; status: string; link_url: string | null; link_label: string | null }>();
      return row ? html(sharePage(row)) : html(notFoundPage(), 404);
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
      return json({
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
    if (videoMatch) {
      const [, id, sharesPart] = videoMatch;
      const video = await env.DB.prepare(`SELECT id FROM videos WHERE id = ? AND deleted_at IS NULL`).bind(id).first();
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
        await env.DB.batch([
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
