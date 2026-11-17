# Screen Recorder web (Milestone 2)

A small Cloudflare Worker for the hosted-video side: an owner-only page, a database (D1) for videos and share links, and the public share link page. Video upload and playback (Cloudflare Stream) come in the next step.

## Run it on your Mac

```bash
cd web
npm install          # once; downloads the tools (about 240 MB, safe to delete later)
npm run db:local     # once; creates the local test database (about 1 MB)
npm run dev          # starts it at http://localhost:8787
```

Open http://localhost:8787. Sign in with the key in `web/.dev.vars` (the text after `OWNER_KEY=`). That file stays on your Mac and is never committed. `npm run smoke` (with `npm run dev` running, and ffmpeg installed) runs all the automatic checks.

## The live copy on Cloudflare

Deployed as the Worker `recorder-web` with its own database `recorder-db` (the "recorder-" prefix keeps it apart from other things on the account) at https://recorder-web.rae-social-agency.workers.dev. Its owner key is separate from the local one and lives in the Worker's secrets plus `web/.prod.vars` on the Mac (uncommitted). Publish changes with `npx wrangler deploy` from `web/` (after `npm run db:remote` if the schema changed).

## What exists now

Upload and playback use a private R2 bucket (`recorder-videos`). The owner page has an upload box (choose an MP4; it uploads in 8 MB parts and resumes if the connection drops). The share page has the player with speed buttons and fullscreen. The Mac app's Upload button comes in step 3.

- Owner page: sign in, add/rename/delete videos, create share links (with an optional Figma or staging link), copy them, switch them off.
- Share links: `/s/<random token>`. Unknown, switched-off and deleted all show the same "not available" page.
- Owner-only API under `/api/*`. It accepts the signed session cookie, or `Authorization: Bearer <key>` for scripts.
- Privacy defaults: pages are `no-store` and `noindex`; the key lives only in the Worker's secrets.

## Later steps

Upload and playback with Cloudflare Stream (private video, short-lived signed playback), the Upload button in the app, the branded viewing page with fullscreen and speed.
