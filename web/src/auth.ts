// Owner-only access. There is one owner, identified by a long secret key kept in the Worker's secrets
// (never in the code or the desktop app's source). Signing in with the key sets a signed, expiring session cookie.

const SESSION_COOKIE = "owner_session";
const SESSION_SECONDS = 60 * 60 * 24 * 14;
const encoder = new TextEncoder();

export interface AuthEnv {
  OWNER_KEY?: string;
}

/** The key must be long enough to be unguessable, or the owner area stays closed. */
export function ownerKeyUsable(env: AuthEnv): env is { OWNER_KEY: string } {
  return typeof env.OWNER_KEY === "string" && env.OWNER_KEY.length >= 24;
}

async function sha256(text: string): Promise<ArrayBuffer> {
  return crypto.subtle.digest("SHA-256", encoder.encode(text));
}

/** Compares two secrets without leaking how many characters matched. */
async function safeEqual(a: string, b: string): Promise<boolean> {
  const [x, y] = await Promise.all([sha256(a), sha256(b)]);
  return crypto.subtle.timingSafeEqual(x, y);
}

async function sign(key: string, message: string): Promise<string> {
  const hmacKey = await crypto.subtle.importKey("raw", encoder.encode(`session:${key}`), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", hmacKey, encoder.encode(message));
  return base64Url(new Uint8Array(signature));
}

export function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function randomToken(byteLength = 24): string {
  return base64Url(crypto.getRandomValues(new Uint8Array(byteLength)));
}

/** Signs a playback address. Tied to one share link, so switching the link off ends playback at once. */
export async function playbackSignature(env: { OWNER_KEY: string }, shareId: string, expires: number): Promise<string> {
  const hmacKey = await crypto.subtle.importKey("raw", encoder.encode(`playback:${env.OWNER_KEY}`), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return base64Url(new Uint8Array(await crypto.subtle.sign("HMAC", hmacKey, encoder.encode(`${shareId}.${expires}`))));
}

export async function signatureMatches(a: string, b: string): Promise<boolean> {
  return safeEqual(a, b);
}

export async function keyMatches(env: { OWNER_KEY: string }, candidate: string): Promise<boolean> {
  return safeEqual(candidate, env.OWNER_KEY);
}

export async function sessionCookie(env: { OWNER_KEY: string }, secure: boolean): Promise<string> {
  const expires = Math.floor(Date.now() / 1000) + SESSION_SECONDS;
  const value = `${expires}.${await sign(env.OWNER_KEY, String(expires))}`;
  return `${SESSION_COOKIE}=${value}; Path=/; HttpOnly; SameSite=Strict; Max-Age=${SESSION_SECONDS}${secure ? "; Secure" : ""}`;
}

export function clearedCookie(secure: boolean): string {
  return `${SESSION_COOKIE}=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0${secure ? "; Secure" : ""}`;
}

export type AuthResult = "owner-cookie" | "owner-bearer" | null;

/** Checks the session cookie or an `Authorization: Bearer <key>` header (for scripts). */
export async function authenticate(request: Request, env: { OWNER_KEY: string }): Promise<AuthResult> {
  const bearer = request.headers.get("Authorization")?.match(/^Bearer (.+)$/)?.[1];
  if (bearer && (await keyMatches(env, bearer))) return "owner-bearer";

  const cookie = request.headers.get("Cookie")?.split(/;\s*/).find((part) => part.startsWith(`${SESSION_COOKIE}=`));
  const value = cookie?.slice(SESSION_COOKIE.length + 1);
  if (!value) return null;
  const [expires, signature] = value.split(".");
  if (!expires || !signature || Number(expires) < Date.now() / 1000) return null;
  return (await safeEqual(signature, await sign(env.OWNER_KEY, expires))) ? "owner-cookie" : null;
}

/** A browser form from another site can't ride on the cookie: changes must come from this site. */
export function sameOrigin(request: Request): boolean {
  const origin = request.headers.get("Origin");
  return origin !== null && origin === new URL(request.url).origin;
}
