-- Apply after 007. Normalize due labels and derive payment matching from actual due links.
BEGIN;
ALTER TABLE public."VillaPmt" ADD COLUMN IF NOT EXISTS "PaymentStatus" text;
ALTER TABLE public."VillaPmt" ALTER COLUMN "PaymentStatus" SET DEFAULT 'Unmatched';
ALTER TABLE public."villaDues" ALTER COLUMN "dueStatus" SET DEFAULT 'Unpaid';

CREATE OR REPLACE FUNCTION public.fernsvilla_due_status()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 NEW."dueStatus":=CASE WHEN NEW."dueAmt"=0 THEN 'NIL'
  WHEN NEW."PmtId" IS NOT NULL OR NEW."dueStatus"='Cleared' THEN 'Cleared' ELSE 'Unpaid' END;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS fernsvilla_due_status ON public."villaDues";
CREATE TRIGGER fernsvilla_due_status BEFORE INSERT OR UPDATE ON public."villaDues"
 FOR EACH ROW EXECUTE FUNCTION public.fernsvilla_due_status();

CREATE OR REPLACE FUNCTION public.fernsvilla_payment_status()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 NEW."PaymentStatus":=CASE WHEN EXISTS (SELECT 1 FROM public."villaDues" WHERE "PmtId"=NEW.id)
  THEN 'Matched' ELSE 'Unmatched' END;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS fernsvilla_payment_status ON public."VillaPmt";
CREATE TRIGGER fernsvilla_payment_status BEFORE INSERT OR UPDATE OF "PaymentStatus" ON public."VillaPmt"
 FOR EACH ROW EXECUTE FUNCTION public.fernsvilla_payment_status();

CREATE OR REPLACE FUNCTION public.fernsvilla_sync_payment_status()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF TG_OP<>'INSERT' THEN
  UPDATE public."VillaPmt" SET "PaymentStatus"='Unmatched' WHERE id=OLD."PmtId";
 END IF;
 IF TG_OP<>'DELETE' THEN
  UPDATE public."VillaPmt" SET "PaymentStatus"='Matched' WHERE id=NEW."PmtId";
 END IF;
 RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS fernsvilla_sync_payment_status ON public."villaDues";
CREATE TRIGGER fernsvilla_sync_payment_status AFTER INSERT OR UPDATE OF "PmtId" OR DELETE ON public."villaDues"
 FOR EACH ROW EXECUTE FUNCTION public.fernsvilla_sync_payment_status();
REVOKE ALL ON FUNCTION public.fernsvilla_payment_status(),public.fernsvilla_sync_payment_status() FROM PUBLIC,anon,authenticated;

-- Preserve amounts, payment links and Cleared items; normalize September/October and other labels.
UPDATE public."villaDues" SET "dueStatus"=CASE WHEN "dueAmt"=0 THEN 'NIL'
 WHEN "PmtId" IS NOT NULL OR "dueStatus"='Cleared' THEN 'Cleared' ELSE 'Unpaid' END;
UPDATE public."VillaPmt" p SET "PaymentStatus"=CASE WHEN EXISTS
 (SELECT 1 FROM public."villaDues" d WHERE d."PmtId"=p.id) THEN 'Matched' ELSE 'Unmatched' END;

DROP POLICY IF EXISTS fernsvilla_due_insert ON public."villaDues";
CREATE POLICY fernsvilla_due_insert ON public."villaDues" FOR INSERT TO authenticated WITH CHECK (
 EXISTS (SELECT 1 FROM public.fernsvilla_members WHERE user_id=auth.uid() AND role IN ('admin','editor'))
 AND EXISTS (SELECT 1 FROM public."villaMaster" m WHERE m."Villa"=villa)
 AND "dueTyp"<>'Monthly maintenance' AND "dueTyp" IS NOT NULL AND length(btrim("dueTyp"))>0 AND "dueDate" IS NOT NULL
 AND "dueAmt">0 AND "dueStatus"='Unpaid' AND "PmtId" IS NULL
);

-- Repeatable monthly assessments, one per permanent villa account per calendar month.
CREATE OR REPLACE FUNCTION public.fernsvilla_load_monthly_dues(billing_date date)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE inserted integer; eligible integer;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.fernsvilla_members WHERE user_id=auth.uid() AND role IN ('admin','editor')) THEN
  RAISE EXCEPTION 'Administrator or editor access required' USING ERRCODE='42501';
 END IF;
 IF billing_date IS NULL THEN RAISE EXCEPTION 'Billing date is required'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('fernsvilla-monthly-'||to_char(billing_date,'YYYY-MM'),0));
 SELECT count(*) INTO eligible FROM public."villaMaster" WHERE "MaintAmount">0 OR lower(btrim("ResStatus"))='under construction';
 INSERT INTO public."villaDues"(villa,"dueTyp","dueDesc","dueAmt","dueDate","dueStatus","PmtId")
 SELECT m."Villa",'Monthly maintenance','Monthly maintenance '||to_char(billing_date,'YYYY-MM'),CASE WHEN lower(btrim(m."ResStatus"))='under construction' THEN 0 ELSE m."MaintAmount" END,billing_date,CASE WHEN lower(btrim(m."ResStatus"))='under construction' THEN 'NIL' ELSE 'Unpaid' END,NULL
 FROM public."villaMaster" m WHERE (m."MaintAmount">0 OR lower(btrim(m."ResStatus"))='under construction')
 AND NOT EXISTS (SELECT 1 FROM public."villaDues" d WHERE d.villa=m."Villa" AND d."dueTyp"='Monthly maintenance'
 AND date_trunc('month',d."dueDate")=date_trunc('month',billing_date))
 ON CONFLICT (villa,"dueTyp","dueDate") DO NOTHING;
 GET DIAGNOSTICS inserted=ROW_COUNT;
 RETURN jsonb_build_object('inserted',inserted,'skipped',eligible-inserted,'eligible',eligible);
END $$;
REVOKE ALL ON FUNCTION public.fernsvilla_load_monthly_dues(date) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fernsvilla_load_monthly_dues(date) TO authenticated;

CREATE OR REPLACE FUNCTION public.fernsvilla_revert_due_payment(
 due_villa text,due_type text,due_date date,expected_payment_id bigint,expected_due_amount numeric
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE d public."villaDues"%ROWTYPE; p public."VillaPmt"%ROWTYPE; used numeric:=0; already_pending boolean:=false;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.fernsvilla_members WHERE user_id=auth.uid() AND role IN ('admin','editor')) THEN
  RAISE EXCEPTION 'Administrator or editor access required' USING ERRCODE='42501';
 END IF;
 IF due_villa IS NULL OR due_type IS NULL OR due_date IS NULL THEN RAISE EXCEPTION 'Due identity is required'; END IF;
 -- Match the lock order of payment application and splitting.
 IF expected_payment_id IS NOT NULL THEN
  SELECT * INTO p FROM public."VillaPmt" WHERE id=expected_payment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Linked payment not found. Refresh and retry'; END IF;
 END IF;
 SELECT * INTO d FROM public."villaDues" WHERE villa=due_villa AND "dueTyp"=due_type AND "dueDate"=due_date FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Due not found. Refresh and retry'; END IF;
 IF d."dueAmt" IS DISTINCT FROM expected_due_amount THEN RAISE EXCEPTION 'Due amount changed. Refresh and retry'; END IF;
 already_pending:=d."dueStatus" IS NOT DISTINCT FROM 'Unpaid' AND d."PmtId" IS NULL;
 IF NOT already_pending THEN
  IF d."dueStatus" IS DISTINCT FROM 'Cleared' OR d."PmtId" IS DISTINCT FROM expected_payment_id THEN
   RAISE EXCEPTION 'Due status or linked payment changed. Refresh and retry';
  END IF;
  UPDATE public."villaDues" SET "PmtId"=NULL,"dueStatus"='Unpaid'
  WHERE villa=due_villa AND "dueTyp"=due_type AND "dueDate"=due_date RETURNING * INTO d;
 END IF;
 IF expected_payment_id IS NOT NULL THEN
  SELECT * INTO p FROM public."VillaPmt" WHERE id=expected_payment_id;
  SELECT coalesce(sum("dueAmt"),0) INTO used FROM public."villaDues" WHERE "PmtId"=p.id;
 END IF;
 RETURN jsonb_build_object('due',to_jsonb(d),
  'payment',CASE WHEN expected_payment_id IS NULL THEN NULL ELSE to_jsonb(p) END,
  'available_amount',CASE WHEN expected_payment_id IS NULL THEN NULL WHEN p."IsSplitParent" THEN 0 ELSE p."PmtAmt"-used END,
  'released_amount',CASE WHEN already_pending THEN 0 ELSE coalesce(d."dueAmt",0) END,
  'already_reverted',already_pending);
END $$;
REVOKE ALL ON FUNCTION public.fernsvilla_revert_due_payment(text,text,date,bigint,numeric) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fernsvilla_revert_due_payment(text,text,date,bigint,numeric) TO authenticated;

-- All selected dues clear together or the entire request rolls back.
CREATE OR REPLACE FUNCTION public.fernsvilla_apply_payment_to_dues(payment_id bigint,due_items jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE p public."VillaPmt"%ROWTYPE; item jsonb; result jsonb:='[]'::jsonb; updated jsonb;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.fernsvilla_members WHERE user_id=auth.uid() AND role IN ('admin','editor')) THEN
  RAISE EXCEPTION 'Administrator or editor access required' USING ERRCODE='42501';
 END IF;
 IF due_items IS NULL OR jsonb_typeof(due_items)<>'array' OR jsonb_array_length(due_items)<1 OR jsonb_array_length(due_items)>120 THEN
  RAISE EXCEPTION 'Select between 1 and 120 due items';
 END IF;
 SELECT * INTO p FROM public."VillaPmt" WHERE id=payment_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Payment not found'; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(due_items) ORDER BY value->>'villa',value->>'dueDate',value->>'dueTyp' LOOP
  updated:=public.fernsvilla_apply_payment(item->>'villa',item->>'dueTyp',(item->>'dueDate')::date,payment_id);
  result:=result||jsonb_build_array(updated);
 END LOOP;
 SELECT * INTO p FROM public."VillaPmt" WHERE id=payment_id;
 RETURN jsonb_build_object('dues',result,'payment',to_jsonb(p));
END $$;
REVOKE ALL ON FUNCTION public.fernsvilla_apply_payment_to_dues(bigint,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fernsvilla_apply_payment_to_dues(bigint,jsonb) TO authenticated;
COMMIT;
