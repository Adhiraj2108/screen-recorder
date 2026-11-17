-- One owner, so no users table. Videos and the links shared for them.
CREATE TABLE videos (
  id          TEXT PRIMARY KEY,
  title       TEXT NOT NULL,
  -- draft: record created, nothing uploaded yet. Later: uploading, processing, ready, failed.
  status      TEXT NOT NULL DEFAULT 'draft',
  -- Cloudflare Stream's ID for the private video. Filled in at the upload step.
  stream_uid  TEXT,
  duration_s  REAL,
  created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at  TEXT
);

CREATE TABLE shares (
  id          TEXT PRIMARY KEY,
  video_id    TEXT NOT NULL REFERENCES videos(id),
  -- The opaque part of the link. Random, not guessable, and revocable.
  token       TEXT NOT NULL UNIQUE,
  -- Optional "open the Figma file / staging site" link shown on the viewing page.
  link_url    TEXT,
  link_label  TEXT,
  created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  revoked_at  TEXT
);

CREATE INDEX shares_video ON shares(video_id);
