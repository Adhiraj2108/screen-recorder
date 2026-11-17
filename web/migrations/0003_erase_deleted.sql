-- Delete now erases a video's record completely (owner decision, 17 Nov 2026).
-- Clear out the records that earlier deletes left behind, marked deleted_at.
DELETE FROM upload_parts WHERE video_id IN (SELECT id FROM videos WHERE deleted_at IS NOT NULL);
DELETE FROM shares WHERE video_id IN (SELECT id FROM videos WHERE deleted_at IS NOT NULL);
DELETE FROM videos WHERE deleted_at IS NOT NULL;
