// Upload into the private bucket and playback out of it. The bucket has no public address: the only way to a
// video is through this Worker, after it has checked the owner key (uploads) or an active share link (playback).

export const PART_SIZE = 8 * 1024 * 1024; // R2 needs 5 MiB or more per part, except the last
export const MAX_BYTES = 4 * 1024 * 1024 * 1024;
export const PLAYBACK_SECONDS = 30 * 60;

export const objectKey = (videoId: string) => `videos/${videoId}/original.mp4`;

export type ByteRange = { offset: number; length: number };

/** Reads a single `Range: bytes=…` request. `null` means no range (send the whole file); "invalid" means 416. */
export function parseRange(header: string | null, size: number): ByteRange | "invalid" | null {
  if (!header) return null;
  const match = header.trim().match(/^bytes=(\d*)-(\d*)$/);
  if (!match) return null; // Multi-range or unknown units: a full response is always allowed.
  const [, from, to] = match;
  if (from === "" && to === "") return "invalid";
  if (from === "") {
    const suffix = Number(to);
    if (suffix === 0) return "invalid";
    const length = Math.min(suffix, size);
    return { offset: size - length, length };
  }
  const start = Number(from);
  if (start >= size) return "invalid";
  const end = to === "" ? size - 1 : Math.min(Number(to), size - 1);
  if (end < start) return "invalid";
  return { offset: start, length: end - start + 1 };
}

const PLAYBACK_HEADERS = {
  "Content-Type": "video/mp4",
  "Accept-Ranges": "bytes",
  "Cache-Control": "private, no-store",
  "X-Content-Type-Options": "nosniff",
  "X-Robots-Tag": "noindex, nofollow",
  "Referrer-Policy": "no-referrer",
};

/** Sends the file, or the part of it the player asked for, so seeking and fast starts work like on any video site. */
export async function serveVideo(request: Request, bucket: R2Bucket, key: string, size: number): Promise<Response> {
  const range = parseRange(request.headers.get("Range"), size);
  if (range === "invalid") {
    return new Response(null, { status: 416, headers: { ...PLAYBACK_HEADERS, "Content-Range": `bytes */${size}` } });
  }
  const offset = range?.offset ?? 0;
  const length = range?.length ?? size;
  const headers: Record<string, string> = { ...PLAYBACK_HEADERS, "Content-Length": String(length) };
  if (range) headers["Content-Range"] = `bytes ${offset}-${offset + length - 1}/${size}`;
  const status = range ? 206 : 200;
  if (request.method === "HEAD") return new Response(null, { status, headers });

  const object = await bucket.get(key, range ? { range: { offset, length } } : undefined);
  if (!object || !("body" in object)) return new Response("Not found", { status: 404 });
  return new Response(object.body, { status, headers });
}
