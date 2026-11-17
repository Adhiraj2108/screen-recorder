# Milestone 3 hands-on checks

Kept apart from PROGRESS.md so it doesn't clash with other work in progress. Fold into PROGRESS.md's Milestone 3 section when convenient.

## Switch a link off; a fresh browser can't play it — passed 17 Nov 2026

Run against the live site (https://recorder-web.rae-social-agency.workers.dev) with a made-up 20-second test pattern and tone (no real footage), uploaded through the owner API, with two share links (A and B) on the same video.

| Step | Result |
| --- | --- |
| Link A opened in a browser and played | Played (3.4 s in, no errors). |
| Link A switched off (09:49 UTC) | Server confirmed. |
| Same open tab: the playback address it already had, asked for a new part of the file | Refused (404). |
| Same open tab: asking for a new playback address | Refused (404). |
| A brand-new browser tab opening link A | "This link isn't available" page (404), no player. |
| A client with no cookies at all (curl) opening link A or asking to play | Both refused (404). |
| Link B on the same video | Still played, so switching off one link doesn't affect others. |

Honest limit: in the tab that was already open, the browser had already downloaded the whole short clip before the link was switched off, so it could finish playing what it had. Nothing new is sent after switching off. On long videos the browser only holds a few minutes ahead, so playback stops when that runs out.

Clean-up: the test video was deleted afterwards. Deleting also switched off link B (404), removed it from the video list, and the stored file is gone from the `recorder-videos` bucket (checked directly).

## Relaunch the app mid-upload and recover — needs the owner

This needs clicks in the Mac app, which the test tools can't do. Owner steps were sent in the project thread.
