# Hosting the videos: two designs (decision pending, 17 Nov 2026)

Both keep the same owner page, share links and database already built. Only where the video file lives and how it plays changes.

## A. Cloudflare R2 (free tier), served by the Worker

**Cost.** Free tier (Cloudflare's R2 pricing page, updated 30 Oct 2026): 10 GB-month storage, 1 million "write" and 10 million "read" operations per month, and no charge for data sent to viewers. Beyond that, $0.015 per GB-month. R2 is already enabled on the account.
**Size reality.** Real recordings from this app run about 0.8 Mbps, roughly 6 MB per minute for simple windows. A dense, moving Figma file could be 2 to 3 times that. So a 10-minute video is about 60 to 150 MB, and 10 GB holds roughly 70 to 150 of them.

**How it works**
1. A private bucket (new, `recorder-videos`, no public address). Nothing is readable without going through the Worker.
2. Upload: the app asks the Worker for a short-lived upload permission, then sends the file in parts straight to the bucket (resumable: a dropped connection resumes from the last finished part, no duplicate videos). The Worker checks the owner key before issuing any permission.
3. Playback: the share page asks the Worker for a short-lived signed video address. The Worker checks the share is on, then streams the file with byte-range support so seeking and speed changes work and phones can start playing right away.
4. Delete: removes the object from the bucket, then marks the video deleted. Switching a link off blocks new playback; an address already issued works until it expires (a few minutes), as the brief documents.
5. The finished MP4 must have its index at the front so it starts playing before it has fully downloaded. Today the app's files have it at the end, so the app needs a small "optimise for streaming" step (one setting in the existing remux, about an hour of work).

**Trade-offs.** No automatic lower-quality versions, so a client on weak mobile data downloads the full-quality file (about 6 to 15 MB a minute) and may buffer. We would build the player (speed, fullscreen) ourselves, which is simple for plain MP4. Quality for dense text is the best case, since the viewer gets the original rather than a 1080p copy.

## B. Cloudflare Stream (paid)

**Cost.** $5 per month for each 1,000 minutes of storage capacity, bought in advance, plus $1 per 1,000 minutes watched. About $5 to $6 a month at the brief's example usage. Requires turning on Stream billing.
**How it works.** The Worker's Stream binding creates upload links and playback tokens. Stream converts every video into several qualities, adapts to the viewer's connection, and its player handles speed and fullscreen. Capped at 1080p. Upload and delete are managed by Stream.
**Trade-offs.** Smoothest viewing on any device or connection, least code to write and maintain. Costs money every month and caps quality at 1080p.

## Suggested path

Start with R2 (free, original quality, plenty of room). The share page and database don't change, so if a client ever struggles to play a long video on mobile data, Stream can be added later for those videos without losing anything built.
