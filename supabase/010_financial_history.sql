-- Run after 009, before fresh imports. Records future changes and an installation snapshot.
BEGIN;
LOCK TABLE public."VillaPmt",public."villaDues" IN ACCESS EXCLUSIVE MODE;
CREATE TABLE IF NOT EXISTS public."VillaPmtHistory" (
 history_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 payment_id bigint,
 event_type text NOT NULL CHECK (event_type IN ('SNAPSHOT','INSERT','UPDATE','DELETE')),
 changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 changed_by uuid,
 database_user text NOT NULL,
 transaction_id bigint NOT NULL DEFAULT txid_current(),
 old_record jsonb,
 new_record jsonb
);
CREATE TABLE IF NOT EXISTS public."villaDuesHistory" (
 history_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 due_villa text,
 due_type text,
 due_date date,
 event_type text NOT NULL CHECK (event_type IN ('SNAPSHOT','INSERT','UPDATE','DELETE')),
 changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 changed_by uuid,
 database_user text NOT NULL,
 transaction_id bigint NOT NULL DEFAULT txid_current(),
 old_record jsonb,
 new_record jsonb
);
CREATE INDEX IF NOT EXISTS fernsvilla_payment_history_key ON public."VillaPmtHistory"(payment_id,history_id);
CREATE INDEX IF NOT EXISTS fernsvilla_due_history_key ON public."villaDuesHistory"(due_villa,due_type,due_date,history_id);
ALTER TABLE public."VillaPmtHistory" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."villaDuesHistory" ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public."VillaPmtHistory",public."villaDuesHistory" FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public."VillaPmtHistory",public."villaDuesHistory" TO authenticated;
DROP POLICY IF EXISTS fernsvilla_payment_history_read ON public."VillaPmtHistory";
CREATE POLICY fernsvilla_payment_history_read ON public."VillaPmtHistory" FOR SELECT TO authenticated USING (
 EXISTS (SELECT 1 FROM public.fernsvilla_members WHERE user_id=auth.uid() AND role='admin')
);
DROP POLICY IF EXISTS fernsvilla_due_history_read ON public."villaDuesHistory";
CREATE POLICY fernsvilla_due_history_read ON public."villaDuesHistory" FOR SELECT TO authenticated USING (
 EXISTS (SELECT 1 FROM public.fernsvilla_members WHERE user_id=auth.uid() AND role='admin')
);

-- Capture any records still present. Existing history is never overwritten on reinstallation.
INSERT INTO public."VillaPmtHistory"(payment_id,event_type,changed_by,database_user,new_record)
 SELECT p.id,'SNAPSHOT',auth.uid(),session_user,to_jsonb(p) FROM public."VillaPmt" p
 WHERE NOT EXISTS (SELECT 1 FROM public."VillaPmtHistory");
INSERT INTO public."villaDuesHistory"(due_villa,due_type,due_date,event_type,changed_by,database_user,new_record)
 SELECT d.villa,d."dueTyp",d."dueDate",'SNAPSHOT',auth.uid(),session_user,to_jsonb(d) FROM public."villaDues" d
 WHERE NOT EXISTS (SELECT 1 FROM public."villaDuesHistory");

CREATE OR REPLACE FUNCTION public.fernsvilla_record_financial_history()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $history$
DECLARE before_row jsonb; after_row jsonb; identity_row jsonb;
BEGIN
 IF TG_OP<>'INSERT' THEN before_row:=to_jsonb(OLD); END IF;
 IF TG_OP<>'DELETE' THEN after_row:=to_jsonb(NEW); END IF;
 IF TG_OP='UPDATE' AND before_row=after_row THEN RETURN NULL; END IF;
 identity_row:=coalesce(after_row,before_row);
 IF TG_TABLE_NAME='VillaPmt' THEN
  INSERT INTO public."VillaPmtHistory"(payment_id,event_type,changed_by,database_user,old_record,new_record)
   VALUES((identity_row->>'id')::bigint,TG_OP,auth.uid(),session_user,before_row,after_row);
 ELSIF TG_TABLE_NAME='villaDues' THEN
  INSERT INTO public."villaDuesHistory"(due_villa,due_type,due_date,event_type,changed_by,database_user,old_record,new_record)
   VALUES(identity_row->>'villa',identity_row->>'dueTyp',(identity_row->>'dueDate')::date,TG_OP,auth.uid(),session_user,before_row,after_row);
 ELSE RAISE EXCEPTION 'Unsupported financial history source';
 END IF;
 RETURN NULL;
END
$history$;
REVOKE ALL ON FUNCTION public.fernsvilla_record_financial_history() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS fernsvilla_payment_history ON public."VillaPmt";
CREATE TRIGGER fernsvilla_payment_history AFTER INSERT OR UPDATE OR DELETE ON public."VillaPmt"
 FOR EACH ROW EXECUTE FUNCTION public.fernsvilla_record_financial_history();
DROP TRIGGER IF EXISTS fernsvilla_due_history ON public."villaDues";
CREATE TRIGGER fernsvilla_due_history AFTER INSERT OR UPDATE OR DELETE ON public."villaDues"
 FOR EACH ROW EXECUTE FUNCTION public.fernsvilla_record_financial_history();
-- Prevent truncation from silently bypassing the row history. The supported purge uses DELETE.
CREATE OR REPLACE FUNCTION public.fernsvilla_reject_financial_truncate()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $truncate_guard$
BEGIN
 RAISE EXCEPTION 'Use DELETE to clear financial records so their history is retained';
END
$truncate_guard$;
DROP TRIGGER IF EXISTS fernsvilla_payment_no_truncate ON public."VillaPmt";
CREATE TRIGGER fernsvilla_payment_no_truncate BEFORE TRUNCATE ON public."VillaPmt"
 EXECUTE FUNCTION public.fernsvilla_reject_financial_truncate();
DROP TRIGGER IF EXISTS fernsvilla_due_no_truncate ON public."villaDues";
CREATE TRIGGER fernsvilla_due_no_truncate BEFORE TRUNCATE ON public."villaDues"
 EXECUTE FUNCTION public.fernsvilla_reject_financial_truncate();
COMMIT;
