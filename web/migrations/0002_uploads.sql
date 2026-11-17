-- Where each video's file lives in the private R2 bucket, and the state of its upload.
ALTER TABLE videos ADD COLUMN object_key   TEXT;
ALTER TABLE videos ADD COLUMN size_bytes   INTEGER;
-- The R2 multipart upload in progress, so an interrupted upload can resume where it stopped.
ALTER TABLE videos ADD COLUMN upload_id    TEXT;
ALTER TABLE videos ADD COLUMN uploaded_at  TEXT;

-- One row per finished part of an upload in progress. Removed once the upload completes or is cancelled.
CREATE TABLE upload_parts (
  video_id    TEXT NOT NULL REFERENCES videos(id),
  part_number INTEGER NOT NULL,
  etag        TEXT NOT NULL,
  size_bytes  INTEGER NOT NULL,
  PRIMARY KEY (video_id, part_number)
);
