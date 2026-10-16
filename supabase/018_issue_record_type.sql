-- Apply after 017, before deploying Issues / Preventive maintenance views.
BEGIN;
ALTER TABLE public.community_issues
 ADD COLUMN IF NOT EXISTS record_type text NOT NULL DEFAULT 'Issue';
UPDATE public.community_issues SET record_type='Issue' WHERE record_type IS NULL;
ALTER TABLE public.community_issues
 ALTER COLUMN record_type SET DEFAULT 'Issue',
 ALTER COLUMN record_type SET NOT NULL;
ALTER TABLE public.community_issues DROP CONSTRAINT IF EXISTS community_issues_record_type_check;
ALTER TABLE public.community_issues ADD CONSTRAINT community_issues_record_type_check
 CHECK(record_type IN ('Issue','Preventive maintenance'));
CREATE INDEX IF NOT EXISTS community_issues_type_reported_idx
 ON public.community_issues(record_type,reported_on DESC,issue_id DESC);
COMMIT;
