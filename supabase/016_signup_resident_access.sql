-- Run after 015. Adds pending registrations and resident-only blog publication.
BEGIN;
CREATE TABLE IF NOT EXISTS public.fernsvilla_registrations (
 user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
 email text NOT NULL, full_name text NOT NULL,
 requested_at timestamptz NOT NULL DEFAULT now(),
 confirmed_at timestamptz,
 status text NOT NULL DEFAULT 'Pending' CHECK(status IN ('Pending','Approved')),
 approved_at timestamptz, approved_by uuid
);
ALTER TABLE public.fernsvilla_registrations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.fernsvilla_registrations FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.fernsvilla_registrations TO authenticated;
DROP POLICY IF EXISTS fernsvilla_registration_read ON public.fernsvilla_registrations;
CREATE POLICY fernsvilla_registration_read ON public.fernsvilla_registrations FOR SELECT TO authenticated USING (
 user_id=auth.uid() OR EXISTS(SELECT 1 FROM public.fernsvilla_members WHERE user_id=auth.uid() AND role='admin')
);
CREATE OR REPLACE FUNCTION public.fernsvilla_registration_request()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $request$
BEGIN
 IF TG_OP='INSERT' AND NEW.email IS NOT NULL AND NEW.raw_user_meta_data->>'fernsvilla_signup'='true' THEN
  INSERT INTO public.fernsvilla_registrations(user_id,email,full_name,confirmed_at)
  VALUES(NEW.id,NEW.email,left(coalesce(nullif(btrim(NEW.raw_user_meta_data->>'full_name'),''),NEW.email),120),NEW.email_confirmed_at)
  ON CONFLICT(user_id) DO NOTHING;
 ELSIF TG_OP='UPDATE' THEN
  UPDATE public.fernsvilla_registrations SET email=NEW.email,confirmed_at=NEW.email_confirmed_at WHERE user_id=NEW.id;
 END IF;
 RETURN NULL;
END $request$;
REVOKE ALL ON FUNCTION public.fernsvilla_registration_request() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS fernsvilla_registration_request ON auth.users;
CREATE TRIGGER fernsvilla_registration_request AFTER INSERT OR UPDATE OF email,email_confirmed_at ON auth.users FOR EACH ROW EXECUTE FUNCTION public.fernsvilla_registration_request();
CREATE OR REPLACE FUNCTION public.fernsvilla_approve_registration(registration_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $approve$
DECLARE result public.fernsvilla_members%ROWTYPE;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.fernsvilla_members WHERE user_id=auth.uid() AND role='admin') THEN RAISE EXCEPTION 'Administrator access required' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM public.fernsvilla_registrations WHERE user_id=registration_user FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Registration not found'; END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id=registration_user AND email_confirmed_at IS NOT NULL) THEN RAISE EXCEPTION 'The user must confirm their email first'; END IF;
 INSERT INTO public.fernsvilla_members(user_id,role) VALUES(registration_user,'resident') ON CONFLICT(user_id) DO NOTHING;
 SELECT * INTO result FROM public.fernsvilla_members WHERE user_id=registration_user;
 UPDATE public.fernsvilla_registrations SET status='Approved',approved_at=coalesce(approved_at,now()),approved_by=coalesce(approved_by,auth.uid()) WHERE user_id=registration_user AND status='Pending';
 RETURN to_jsonb(result);
END $approve$;
REVOKE ALL ON FUNCTION public.fernsvilla_approve_registration(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fernsvilla_approve_registration(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.fernsvilla_add_post(post_title text,post_category text,post_body text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $post$
DECLARE post jsonb; author_name text;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.fernsvilla_members WHERE user_id=auth.uid() AND role IN ('admin','editor','resident')) THEN RAISE EXCEPTION 'Approved association membership required' USING ERRCODE='42501'; END IF;
 IF post_title IS NULL OR length(btrim(post_title)) NOT BETWEEN 1 AND 200 OR post_body IS NULL OR length(btrim(post_body)) NOT BETWEEN 1 AND 20000 OR post_category IS NULL OR post_category NOT IN ('Gardening','Wellness','Food & cooking','Books & culture','Community','Other') THEN RAISE EXCEPTION 'Enter a valid title, category and story'; END IF;
 SELECT coalesce(nullif(btrim(raw_user_meta_data->>'full_name'),''),email,'Association member') INTO author_name FROM auth.users WHERE id=auth.uid();
 post:=jsonb_build_object('title',btrim(post_title),'category',post_category,'body',btrim(post_body),'author',author_name,'created_by',auth.uid(),'created_at',clock_timestamp(),'emoji','🌿');
 UPDATE public.fernsvilla_state SET data=jsonb_set(data,'{posts}',jsonb_build_array(post)||coalesce(data->'posts','[]'::jsonb)),revision=revision+1,updated_at=now() WHERE id=1;
 IF NOT FOUND THEN RAISE EXCEPTION 'Association is not initialized'; END IF;
 RETURN post;
END $post$;
REVOKE ALL ON FUNCTION public.fernsvilla_add_post(text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fernsvilla_add_post(text,text,text) TO authenticated;
-- Registration changes are part of the existing admin audit feed.
DROP TRIGGER IF EXISTS fernsvilla_admin_audit ON public.fernsvilla_registrations;
CREATE TRIGGER fernsvilla_admin_audit AFTER INSERT OR UPDATE OR DELETE ON public.fernsvilla_registrations FOR EACH ROW EXECUTE FUNCTION public.fernsvilla_audit_change();
-- Include app registrations created before installation without changing existing memberships.
INSERT INTO public.fernsvilla_registrations(user_id,email,full_name,confirmed_at,status)
 SELECT u.id,u.email,left(coalesce(nullif(btrim(u.raw_user_meta_data->>'full_name'),''),u.email),120),u.email_confirmed_at,
 CASE WHEN EXISTS(SELECT 1 FROM public.fernsvilla_members m WHERE m.user_id=u.id) THEN 'Approved' ELSE 'Pending' END
 FROM auth.users u WHERE u.email IS NOT NULL AND u.raw_user_meta_data->>'fernsvilla_signup'='true'
 ON CONFLICT(user_id) DO NOTHING;
COMMIT;
