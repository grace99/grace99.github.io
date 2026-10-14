-- Apply after 013 in the Supabase SQL Editor. Adds auditing; does not alter financial data.
BEGIN;
CREATE TABLE IF NOT EXISTS public.fernsvilla_audit_events (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 event_type text NOT NULL CHECK(event_type IN ('INSERT','UPDATE','DELETE','TRUNCATE','SNAPSHOT','SIGN_IN','MONTHLY_LOAD')),
 entity text NOT NULL,
 source text NOT NULL,
 actor_id uuid,
 actor_email text,
 database_user text NOT NULL DEFAULT session_user,
 transaction_id bigint NOT NULL DEFAULT txid_current(),
 villa text,
 record_key text,
 old_record jsonb,
 new_record jsonb,
 metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
 origin_key text UNIQUE
);
CREATE INDEX IF NOT EXISTS fernsvilla_audit_occurred ON public.fernsvilla_audit_events(occurred_at DESC,id DESC);
CREATE INDEX IF NOT EXISTS fernsvilla_audit_entity ON public.fernsvilla_audit_events(entity,id DESC);
ALTER TABLE public.fernsvilla_audit_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.fernsvilla_audit_events FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.fernsvilla_audit_events TO authenticated;
DROP POLICY IF EXISTS fernsvilla_audit_admin_read ON public.fernsvilla_audit_events;
CREATE POLICY fernsvilla_audit_admin_read ON public.fernsvilla_audit_events FOR SELECT TO authenticated USING (
 EXISTS(SELECT 1 FROM public.fernsvilla_members WHERE user_id=auth.uid() AND role='admin')
);

CREATE OR REPLACE FUNCTION public.fernsvilla_audit_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $audit$
DECLARE before_row jsonb; after_row jsonb; identity_row jsonb; actor uuid:=auth.uid(); email text;
BEGIN
 IF TG_LEVEL='ROW' THEN
  IF TG_OP<>'INSERT' THEN before_row:=to_jsonb(OLD); END IF;
  IF TG_OP<>'DELETE' THEN after_row:=to_jsonb(NEW); END IF;
  IF TG_OP='UPDATE' AND before_row=after_row THEN RETURN NULL; END IF;
  identity_row:=coalesce(after_row,before_row);
 END IF;
 SELECT u.email INTO email FROM auth.users u WHERE u.id=actor;
 INSERT INTO public.fernsvilla_audit_events(event_type,entity,source,actor_id,actor_email,database_user,villa,record_key,old_record,new_record,metadata)
 VALUES(TG_OP,TG_TABLE_NAME,CASE WHEN actor IS NULL THEN 'Database' ELSE 'Authenticated request' END,actor,email,
  coalesce(nullif(current_setting('role',true),'none'),session_user),coalesce(identity_row->>'Villa',identity_row->>'villa'),
  CASE WHEN TG_TABLE_NAME IN ('villaDues','villaPaymentAllocations') THEN concat_ws(' · ',identity_row->>'villa',identity_row->>'dueTyp',identity_row->>'dueDate',identity_row->>'payment_id')
   ELSE coalesce(identity_row->>'id',identity_row->>'Villa',identity_row->>'user_id') END,
  before_row,after_row,jsonb_strip_nulls(jsonb_build_object('operation',nullif(current_setting('fernsvilla.audit_operation',true),''))));
 RETURN NULL;
END $audit$;
REVOKE ALL ON FUNCTION public.fernsvilla_audit_change() FROM PUBLIC,anon,authenticated;
DO $triggers$
DECLARE table_name text;
BEGIN
 FOREACH table_name IN ARRAY ARRAY['VillaPmt','villaDues','villaMaster','villaPaymentAllocations','villaBalances','fernsvilla_state','fernsvilla_members'] LOOP
  EXECUTE format('DROP TRIGGER IF EXISTS fernsvilla_admin_audit ON public.%I',table_name);
  EXECUTE format('CREATE TRIGGER fernsvilla_admin_audit AFTER INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.fernsvilla_audit_change()',table_name);
  EXECUTE format('DROP TRIGGER IF EXISTS fernsvilla_admin_audit_truncate ON public.%I',table_name);
  EXECUTE format('CREATE TRIGGER fernsvilla_admin_audit_truncate AFTER TRUNCATE ON public.%I FOR EACH STATEMENT EXECUTE FUNCTION public.fernsvilla_audit_change()',table_name);
 END LOOP;
END $triggers$;

-- Supabase updates last_sign_in_at on successful sign-ins. Never copy auth user rows or credentials.
CREATE OR REPLACE FUNCTION public.fernsvilla_audit_sign_in()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $signin$
BEGIN
 IF NEW.last_sign_in_at IS NULL THEN RETURN NULL; END IF;
 IF TG_OP='UPDATE' AND NEW.last_sign_in_at IS NOT DISTINCT FROM OLD.last_sign_in_at THEN RETURN NULL; END IF;
 INSERT INTO public.fernsvilla_audit_events(occurred_at,event_type,entity,source,actor_id,actor_email,record_key,metadata)
 VALUES(NEW.last_sign_in_at,'SIGN_IN','User sign-ins','Supabase Auth',NEW.id,NEW.email,NEW.id::text,
  jsonb_build_object('capture','Supabase last_sign_in_at'));
 RETURN NULL;
END $signin$;
REVOKE ALL ON FUNCTION public.fernsvilla_audit_sign_in() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS fernsvilla_admin_sign_in ON auth.users;
CREATE TRIGGER fernsvilla_admin_sign_in AFTER INSERT OR UPDATE OF last_sign_in_at ON auth.users
 FOR EACH ROW EXECUTE FUNCTION public.fernsvilla_audit_sign_in();

-- Keep the existing load implementation and its locking/idempotency behavior. Only the public wrapper is callable.
DO $wrap$
BEGIN
 IF to_regprocedure('public.fernsvilla_load_monthly_dues_core(date)') IS NULL THEN
  ALTER FUNCTION public.fernsvilla_load_monthly_dues(date) RENAME TO fernsvilla_load_monthly_dues_core;
 END IF;
END $wrap$;
REVOKE ALL ON FUNCTION public.fernsvilla_load_monthly_dues_core(date) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.fernsvilla_load_monthly_dues(billing_date date)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $load$
DECLARE result jsonb; actor uuid:=auth.uid(); email text; previous_operation text:=current_setting('fernsvilla.audit_operation',true);
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.fernsvilla_members WHERE user_id=actor AND role IN ('admin','editor')) THEN
  RAISE EXCEPTION 'Administrator or editor access required' USING ERRCODE='42501';
 END IF;
 PERFORM set_config('fernsvilla.audit_operation','Monthly dues load',true);
 result:=public.fernsvilla_load_monthly_dues_core(billing_date);
 SELECT u.email INTO email FROM auth.users u WHERE u.id=actor;
 INSERT INTO public.fernsvilla_audit_events(event_type,entity,source,actor_id,actor_email,record_key,metadata)
 VALUES('MONTHLY_LOAD','villaDues','Authenticated request',actor,email,billing_date::text,result||jsonb_build_object('billing_date',billing_date));
 PERFORM set_config('fernsvilla.audit_operation',coalesce(previous_operation,''),true);
 RETURN result;
END $load$;
REVOKE ALL ON FUNCTION public.fernsvilla_load_monthly_dues(date) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fernsvilla_load_monthly_dues(date) TO authenticated;

-- Reuse retained financial history. Unique origin keys make backfilling safe on reruns.
DO $backfill$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.fernsvilla_audit_events WHERE origin_key='admin-center-installed') THEN
INSERT INTO public.fernsvilla_audit_events(occurred_at,event_type,entity,source,actor_id,actor_email,database_user,transaction_id,villa,record_key,old_record,new_record,metadata,origin_key)
 SELECT h.changed_at,h.event_type,'VillaPmt',CASE WHEN h.changed_by IS NULL THEN 'Database' ELSE 'Authenticated request' END,
 h.changed_by,u.email,h.database_user,h.transaction_id,coalesce(h.new_record->>'Villa',h.old_record->>'Villa'),h.payment_id::text,
 h.old_record,h.new_record,'{"historical":true}'::jsonb,'VillaPmtHistory:'||h.history_id FROM public."VillaPmtHistory" h LEFT JOIN auth.users u ON u.id=h.changed_by
 ON CONFLICT(origin_key) DO NOTHING;
INSERT INTO public.fernsvilla_audit_events(occurred_at,event_type,entity,source,actor_id,actor_email,database_user,transaction_id,villa,record_key,old_record,new_record,metadata,origin_key)
 SELECT h.changed_at,h.event_type,'villaDues',CASE WHEN h.changed_by IS NULL THEN 'Database' ELSE 'Authenticated request' END,
 h.changed_by,u.email,h.database_user,h.transaction_id,h.due_villa,concat_ws(' · ',h.due_villa,h.due_type,h.due_date),
 h.old_record,h.new_record,'{"historical":true}'::jsonb,'villaDuesHistory:'||h.history_id FROM public."villaDuesHistory" h LEFT JOIN auth.users u ON u.id=h.changed_by
 ON CONFLICT(origin_key) DO NOTHING;
INSERT INTO public.fernsvilla_audit_events(occurred_at,event_type,entity,source,actor_id,actor_email,database_user,transaction_id,villa,record_key,old_record,new_record,metadata,origin_key)
 SELECT h.changed_at,h.event_type,'villaPaymentAllocations',CASE WHEN h.changed_by IS NULL THEN 'Database' ELSE 'Authenticated request' END,
 h.changed_by,u.email,h.database_user,h.transaction_id,coalesce(h.new_record->>'villa',h.old_record->>'villa'),
 concat_ws(' · ',coalesce(h.new_record,h.old_record)->>'villa',coalesce(h.new_record,h.old_record)->>'dueTyp',coalesce(h.new_record,h.old_record)->>'dueDate',coalesce(h.new_record,h.old_record)->>'payment_id'),
 h.old_record,h.new_record,'{"historical":true}'::jsonb,'villaPaymentAllocationHistory:'||h.history_id FROM public."villaPaymentAllocationHistory" h LEFT JOIN auth.users u ON u.id=h.changed_by
 ON CONFLICT(origin_key) DO NOTHING;
  INSERT INTO public.fernsvilla_audit_events(event_type,entity,source,metadata,origin_key)
  VALUES('SNAPSHOT','Admin center','Database','{"installation":true,"description":"Audit capture installed; retained financial history imported"}'::jsonb,'admin-center-installed');
 END IF;
END $backfill$;
COMMIT;
