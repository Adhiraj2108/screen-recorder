# Screen Recorder web (Milestone 2)

A small Cloudflare Worker for the hosted-video side: an owner-only page, a database (D1) for videos and share links, and the public share link page. Video upload and playback (Cloudflare Stream) come in the next step.

## Run it on your Mac

```bash
cd web
npm install          # once; downloads the tools (about 240 MB, safe to delete later)
npm run db:local     # once; creates the local test database (about 1 MB)
npm run dev          # starts it at http://localhost:8787
```

Open http://localhost:8787. Sign in with the key in `web/.dev.vars` (the text after `OWNER_KEY=`). That file stays on your Mac and is never committed. `npm run smoke` (with `npm run dev` running) runs the automatic checks.

## What exists now

There is deliberately **no upload box yet**. This step only manages video records and share links. Uploading starts in step 2 (Cloudflare Stream) and gets its button in the app in step 3. Until then the share page says the video will play once it's uploaded.

- Owner page: sign in, add/rename/delete videos, create share links (with an optional Figma or staging link), copy them, switch them off.
- Share links: `/s/<random token>`. Unknown, switched-off and deleted all show the same "not available" page.
- Owner-only API under `/api/*`. It accepts the signed session cookie, or `Authorization: Bearer <key>` for scripts.
- Privacy defaults: pages are `no-store` and `noindex`; the key lives only in the Worker's secrets.

## Later steps

Upload and playback with Cloudflare Stream (private video, short-lived signed playback), the Upload button in the app, the branded viewing page with fullscreen and speed.
