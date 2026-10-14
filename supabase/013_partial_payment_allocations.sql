-- Apply after 012 and deploy the accompanying UI before using partial matching.
-- Original due amounts are retained; paidAmt and outstandingAmt track each due's balance.
BEGIN;
LOCK TABLE public."VillaPmt",public."villaDues" IN ACCESS EXCLUSIVE MODE;
ALTER TABLE public."villaDues" ADD COLUMN IF NOT EXISTS "paidAmt" numeric NOT NULL DEFAULT 0;
ALTER TABLE public."villaDues" ADD COLUMN IF NOT EXISTS "outstandingAmt" numeric GENERATED ALWAYS AS (greatest(coalesce("dueAmt",0)-"paidAmt",0)) STORED;
CREATE TABLE IF NOT EXISTS public."villaPaymentAllocations" (
 villa text NOT NULL, "dueTyp" text NOT NULL, "dueDate" date NOT NULL,
 payment_id bigint NOT NULL REFERENCES public."VillaPmt"(id),
 amount numeric NOT NULL CHECK (amount>0 AND amount=round(amount,2)),
 PRIMARY KEY(villa,"dueTyp","dueDate",payment_id),
 FOREIGN KEY(villa,"dueTyp","dueDate") REFERENCES public."villaDues"(villa,"dueTyp","dueDate") ON DELETE CASCADE
);
ALTER TABLE public."villaPaymentAllocations" ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public."villaPaymentAllocations" FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public."villaPaymentAllocations" TO authenticated;
DROP POLICY IF EXISTS fernsvilla_allocation_read ON public."villaPaymentAllocations";
CREATE POLICY fernsvilla_allocation_read ON public."villaPaymentAllocations" FOR SELECT TO authenticated USING (
 EXISTS (SELECT 1 FROM public.fernsvilla_members WHERE user_id=auth.uid())
);
CREATE TABLE IF NOT EXISTS public."villaPaymentAllocationHistory" (
 history_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 event_type text NOT NULL, changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 changed_by uuid, database_user text NOT NULL, transaction_id bigint NOT NULL DEFAULT txid_current(),
 old_record jsonb,new_record jsonb
);
ALTER TABLE public."villaPaymentAllocationHistory" ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public."villaPaymentAllocationHistory" FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public."villaPaymentAllocationHistory" TO authenticated;
DROP POLICY IF EXISTS fernsvilla_allocation_history_read ON public."villaPaymentAllocationHistory";
CREATE POLICY fernsvilla_allocation_history_read ON public."villaPaymentAllocationHistory" FOR SELECT TO authenticated USING (
 EXISTS (SELECT 1 FROM public.fernsvilla_members WHERE user_id=auth.uid() AND role='admin')
);
CREATE OR REPLACE FUNCTION public.fernsvilla_allocation_history()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 INSERT INTO public."villaPaymentAllocationHistory"(event_type,changed_by,database_user,old_record,new_record)
 VALUES(TG_OP,auth.uid(),session_user,CASE WHEN TG_OP<>'INSERT' THEN to_jsonb(OLD) END,CASE WHEN TG_OP<>'DELETE' THEN to_jsonb(NEW) END);
 RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS fernsvilla_allocation_history ON public."villaPaymentAllocations";
CREATE TRIGGER fernsvilla_allocation_history AFTER INSERT OR UPDATE OR DELETE ON public."villaPaymentAllocations"
 FOR EACH ROW EXECUTE FUNCTION public.fernsvilla_allocation_history();

-- Abort rather than fabricate allocations for inconsistent existing matches.
DO $$ BEGIN
 IF EXISTS (SELECT 1 FROM public."villaDues" d LEFT JOIN public."VillaPmt" p ON p.id=d."PmtId"
 WHERE d."PmtId" IS NOT NULL AND (p."Villa" IS DISTINCT FROM d.villa OR p."IsSplitParent" OR p."PmtAmt" IS NULL OR p."PmtAmt"<=0 OR d."dueAmt" IS NULL OR d."dueAmt"<=0)) THEN
  RAISE EXCEPTION 'Reconcile inconsistent payment links before installing partial allocations';
 END IF;
 IF EXISTS (SELECT 1 FROM public."villaDues" WHERE "dueStatus"='Cleared' AND "PmtId" IS NULL AND "dueAmt">0 AND "paidAmt"=0) THEN
  RAISE EXCEPTION 'A cleared due has no payment reference. Reconcile it before installation';
 END IF;
END $$;
INSERT INTO public."villaPaymentAllocations"(villa,"dueTyp","dueDate",payment_id,amount)
 SELECT villa,"dueTyp","dueDate","PmtId","dueAmt" FROM public."villaDues"
 WHERE "PmtId" IS NOT NULL AND "dueAmt">0 AND "paidAmt"=0
 AND NOT EXISTS (SELECT 1 FROM public."villaPaymentAllocations" a WHERE a.villa="villaDues".villa AND a."dueTyp"="villaDues"."dueTyp" AND a."dueDate"="villaDues"."dueDate")
 ON CONFLICT DO NOTHING;
DO $$ BEGIN
 IF EXISTS (SELECT 1 FROM public."VillaPmt" p JOIN public."villaPaymentAllocations" a ON a.payment_id=p.id
 GROUP BY p.id HAVING sum(a.amount)>p."PmtAmt") THEN RAISE EXCEPTION 'Existing matches exceed a payment amount. Reconcile before installation'; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.fernsvilla_due_status()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 SELECT coalesce(sum(amount),0),max(payment_id) INTO NEW."paidAmt",NEW."PmtId" FROM public."villaPaymentAllocations"
 WHERE villa=NEW.villa AND "dueTyp"=NEW."dueTyp" AND "dueDate"=NEW."dueDate";
 IF NEW."paidAmt">coalesce(NEW."dueAmt",0) THEN RAISE EXCEPTION 'Due amount cannot be less than its applied payments'; END IF;
 NEW."dueStatus":=CASE WHEN NEW."dueAmt"=0 THEN 'NIL' WHEN NEW."paidAmt">=NEW."dueAmt" THEN 'Cleared' ELSE 'Unpaid' END;
 RETURN NEW;
END $$;
CREATE OR REPLACE FUNCTION public.fernsvilla_payment_status()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 NEW."PaymentStatus":=CASE WHEN EXISTS (SELECT 1 FROM public."villaPaymentAllocations" WHERE payment_id=NEW.id) THEN 'Matched' ELSE 'Unmatched' END;
 RETURN NEW;
END $$;
CREATE OR REPLACE FUNCTION public.fernsvilla_sync_allocation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r record;
BEGIN
 IF TG_OP<>'INSERT' THEN
  UPDATE public."villaDues" SET "paidAmt"="paidAmt" WHERE villa=OLD.villa AND "dueTyp"=OLD."dueTyp" AND "dueDate"=OLD."dueDate";
  UPDATE public."VillaPmt" SET "PaymentStatus"='Unmatched' WHERE id=OLD.payment_id;
 END IF;
 IF TG_OP<>'DELETE' THEN
  UPDATE public."villaDues" SET "paidAmt"="paidAmt" WHERE villa=NEW.villa AND "dueTyp"=NEW."dueTyp" AND "dueDate"=NEW."dueDate";
  UPDATE public."VillaPmt" SET "PaymentStatus"='Matched' WHERE id=NEW.payment_id;
 END IF;
 RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS fernsvilla_sync_allocation ON public."villaPaymentAllocations";
CREATE TRIGGER fernsvilla_sync_allocation AFTER INSERT OR UPDATE OR DELETE ON public."villaPaymentAllocations"
 FOR EACH ROW EXECUTE FUNCTION public.fernsvilla_sync_allocation();
UPDATE public."villaDues" SET "paidAmt"="paidAmt";
UPDATE public."VillaPmt" SET "PaymentStatus"="PaymentStatus";
CREATE OR REPLACE FUNCTION public.fernsvilla_allocate_payment(due_villa text,due_type text,due_date date,payment_id bigint,allocation_amount numeric DEFAULT NULL,expected_paid_amount numeric DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE p public."VillaPmt"%ROWTYPE; d public."villaDues"%ROWTYPE; available numeric; portion numeric;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.fernsvilla_members WHERE user_id=auth.uid() AND role IN ('admin','editor')) THEN RAISE EXCEPTION 'Administrator or editor access required' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('fernsvilla-payment-allocations',0));
 SELECT * INTO p FROM public."VillaPmt" WHERE id=payment_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Payment not found'; END IF;
 SELECT * INTO d FROM public."villaDues" WHERE villa=due_villa AND "dueTyp"=due_type AND "dueDate"=due_date FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Due not found. Refresh and retry'; END IF;
 IF expected_paid_amount IS NOT NULL AND d."paidAmt" IS DISTINCT FROM expected_paid_amount THEN RAISE EXCEPTION 'Due allocations changed. Refresh and retry'; END IF;
 IF p."IsSplitParent" THEN RAISE EXCEPTION 'Choose a split transaction, not an archived receipt'; END IF;
 IF p."Villa" IS DISTINCT FROM d.villa THEN RAISE EXCEPTION 'Payment must belong to the same villa'; END IF;
 IF p."AllocationMonth" IS NOT NULL AND date_trunc('month',p."AllocationMonth")<>date_trunc('month',d."dueDate") THEN RAISE EXCEPTION 'This split transaction is allocated to another month'; END IF;
 SELECT p."PmtAmt"-coalesce(sum(amount),0) INTO available FROM public."villaPaymentAllocations" a WHERE a.payment_id=p.id;
 portion:=coalesce(allocation_amount,least(available,d."outstandingAmt"));
 IF d."outstandingAmt"<=0 OR portion IS NULL OR portion<=0 OR portion<>round(portion,2) OR portion>available OR portion>d."outstandingAmt" THEN RAISE EXCEPTION 'Allocation must be positive and within both payment credit and outstanding due'; END IF;
 INSERT INTO public."villaPaymentAllocations"(villa,"dueTyp","dueDate",payment_id,amount) VALUES(d.villa,d."dueTyp",d."dueDate",p.id,portion)
 ON CONFLICT ON CONSTRAINT "villaPaymentAllocations_pkey" DO UPDATE SET amount="villaPaymentAllocations".amount+EXCLUDED.amount;
 SELECT * INTO d FROM public."villaDues" WHERE villa=due_villa AND "dueTyp"=due_type AND "dueDate"=due_date;
 RETURN to_jsonb(d);
END $$;
CREATE OR REPLACE FUNCTION public.fernsvilla_apply_payment(due_villa text,due_type text,due_date date,payment_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN RETURN public.fernsvilla_allocate_payment(due_villa,due_type,due_date,payment_id,NULL); END $$;
CREATE OR REPLACE FUNCTION public.fernsvilla_apply_payment_to_dues(payment_id bigint,due_items jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE item jsonb; result jsonb:='[]'::jsonb; p public."VillaPmt"%ROWTYPE;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.fernsvilla_members WHERE user_id=auth.uid() AND role IN ('admin','editor')) THEN RAISE EXCEPTION 'Administrator or editor access required' USING ERRCODE='42501'; END IF;
 IF due_items IS NULL OR jsonb_typeof(due_items)<>'array' OR jsonb_array_length(due_items)<1 OR jsonb_array_length(due_items)>120 THEN RAISE EXCEPTION 'Select between 1 and 120 due items'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('fernsvilla-payment-allocations',0));
 FOR item IN SELECT value FROM jsonb_array_elements(due_items) ORDER BY value->>'villa',value->>'dueDate',value->>'dueTyp' LOOP
  result:=result||jsonb_build_array(public.fernsvilla_allocate_payment(item->>'villa',item->>'dueTyp',(item->>'dueDate')::date,payment_id,(item->>'amount')::numeric,(item->>'expected_paid_amount')::numeric));
 END LOOP;
 SELECT * INTO p FROM public."VillaPmt" WHERE id=payment_id;
 RETURN jsonb_build_object('dues',result,'payment',to_jsonb(p));
END $$;
DROP FUNCTION IF EXISTS public.fernsvilla_revert_due_payment(text,text,date,bigint,numeric);
CREATE OR REPLACE FUNCTION public.fernsvilla_revert_due_payment(due_villa text,due_type text,due_date date,expected_payment_id bigint,expected_due_amount numeric,expected_paid_amount numeric DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE d public."villaDues"%ROWTYPE; ids bigint[]; payments jsonb; p jsonb; released numeric;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.fernsvilla_members WHERE user_id=auth.uid() AND role IN ('admin','editor')) THEN RAISE EXCEPTION 'Administrator or editor access required' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('fernsvilla-payment-allocations',0));
 SELECT array_agg(DISTINCT payment_id) INTO ids FROM public."villaPaymentAllocations" WHERE villa=due_villa AND "dueTyp"=due_type AND "dueDate"=due_date;
 PERFORM id FROM public."VillaPmt" WHERE id=ANY(ids) ORDER BY id FOR UPDATE;
 SELECT * INTO d FROM public."villaDues" WHERE villa=due_villa AND "dueTyp"=due_type AND "dueDate"=due_date FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Due not found'; END IF;
 IF d."dueAmt" IS DISTINCT FROM expected_due_amount OR (d."paidAmt">0 AND (d."PmtId" IS DISTINCT FROM expected_payment_id OR (expected_paid_amount IS NOT NULL AND d."paidAmt" IS DISTINCT FROM expected_paid_amount))) THEN RAISE EXCEPTION 'Due allocations changed. Refresh and retry'; END IF;
 released:=d."paidAmt";
 DELETE FROM public."villaPaymentAllocations" WHERE villa=due_villa AND "dueTyp"=due_type AND "dueDate"=due_date;
 SELECT * INTO d FROM public."villaDues" WHERE villa=due_villa AND "dueTyp"=due_type AND "dueDate"=due_date;
 SELECT coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) INTO payments FROM public."VillaPmt" q WHERE id=ANY(ids);
 SELECT to_jsonb(q) INTO p FROM public."VillaPmt" q WHERE id=expected_payment_id;
 RETURN jsonb_build_object('due',to_jsonb(d),'payments',payments,'payment',p,'released_amount',released,'already_reverted',released=0);
END $$;
REVOKE ALL ON FUNCTION public.fernsvilla_allocate_payment(text,text,date,bigint,numeric,numeric),public.fernsvilla_revert_due_payment(text,text,date,bigint,numeric,numeric),public.fernsvilla_allocation_history(),public.fernsvilla_sync_allocation(),public.fernsvilla_due_status() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fernsvilla_allocate_payment(text,text,date,bigint,numeric,numeric),public.fernsvilla_revert_due_payment(text,text,date,bigint,numeric,numeric) TO authenticated;

CREATE OR REPLACE FUNCTION public.fernsvilla_split_payment(payment_id bigint,expected_amount numeric,allocations jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE p public."VillaPmt"%ROWTYPE; child public."VillaPmt"%ROWTYPE; item jsonb;
 total numeric:=0; portion numeric; billing_month date; target_villa text; result jsonb:='[]'::jsonb;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.fernsvilla_members WHERE user_id=auth.uid() AND role IN ('admin','editor')) THEN
  RAISE EXCEPTION 'Administrator or editor access required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO p FROM public."VillaPmt" WHERE id=payment_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Payment not found'; END IF;
 IF p."SplitFromPmtId" IS NOT NULL THEN RAISE EXCEPTION 'A split transaction cannot be split again'; END IF;
 -- Retry after an interrupted response returns the existing result, without creating more IDs.
 IF p."IsSplitParent" THEN
  SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY c.id),'[]'::jsonb) INTO result
  FROM public."VillaPmt" c WHERE c."SplitFromPmtId"=p.id;
  IF jsonb_array_length(result)=0 THEN RAISE EXCEPTION 'Split receipt has no transactions. Contact the administrator'; END IF;
  RETURN jsonb_build_object('original',to_jsonb(p),'payments',result,'already_split',true);
 END IF;
 IF EXISTS (SELECT 1 FROM public."villaPaymentAllocations" a WHERE a.payment_id=p.id) THEN
  RAISE EXCEPTION 'This payment is already applied to dues and cannot be split';
 END IF;
 IF p."PmtAmt" IS NULL OR p."PmtAmt"<=0 OR p."PmtAmt" IS DISTINCT FROM expected_amount THEN
  RAISE EXCEPTION 'Payment amount changed or is invalid. Refresh and retry';
 END IF;
 IF allocations IS NULL OR jsonb_typeof(allocations)<>'array' OR jsonb_array_length(allocations)<2 OR jsonb_array_length(allocations)>120 THEN
  RAISE EXCEPTION 'Enter between 2 and 120 allocations';
 END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(allocations) LOOP
  IF jsonb_typeof(item)<>'object' OR item->>'month' IS NULL OR (item->>'month') !~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
   OR item->>'amount' IS NULL OR (item->>'amount') !~ '^[0-9]+(\.[0-9]{1,2})?$' THEN
   RAISE EXCEPTION 'Each allocation needs a valid YYYY-MM month and a positive amount with at most two decimals';
  END IF;
  target_villa:=coalesce(item->>'villa',p."Villa");
  IF target_villa IS NULL OR btrim(target_villa)='' OR NOT EXISTS (SELECT 1 FROM public."villaMaster" WHERE "Villa"=target_villa) THEN
   RAISE EXCEPTION 'Choose an existing villa for each allocation';
  END IF;
  billing_month:=to_date((item->>'month')||'-01','YYYY-MM-DD');
  IF to_char(billing_month,'YYYY-MM')<>item->>'month' THEN RAISE EXCEPTION 'Invalid allocation month'; END IF;
  portion:=(item->>'amount')::numeric;
  IF portion<=0 THEN RAISE EXCEPTION 'Every allocation amount must be greater than zero'; END IF;
  total:=total+portion;
 END LOOP;
 IF total<>p."PmtAmt" THEN RAISE EXCEPTION 'Allocated amounts must equal the original payment amount'; END IF;
 IF (SELECT count(DISTINCT ROW(coalesce(value->>'villa',p."Villa"),value->>'month')) FROM jsonb_array_elements(allocations))<>jsonb_array_length(allocations) THEN
  RAISE EXCEPTION 'Use one allocation per villa and month';
 END IF;
 UPDATE public."VillaPmt" SET "IsSplitParent"=true WHERE id=p.id RETURNING * INTO p;
 FOR item IN SELECT value FROM jsonb_array_elements(allocations) LOOP
  INSERT INTO public."VillaPmt"("Villa","PmtDate","AccountNum","PmtMthd","PmtDueToward","PmtAmt","PmtRemarks","UTR","LatePmt","AllocationMonth","SplitFromPmtId","IsSplitParent")
  VALUES(coalesce(item->>'villa',p."Villa"),p."PmtDate",p."AccountNum",p."PmtMthd",p."PmtDueToward",(item->>'amount')::numeric,p."PmtRemarks",p."UTR",p."LatePmt",to_date((item->>'month')||'-01','YYYY-MM-DD'),p.id,false)
  RETURNING * INTO child;
  result:=result||jsonb_build_array(to_jsonb(child));
 END LOOP;
 RETURN jsonb_build_object('original',to_jsonb(p),'payments',result,'already_split',false);
EXCEPTION WHEN unique_violation THEN
 RAISE EXCEPTION 'A payment already exists with this villa, amount, receipt date and billing month. No split was created.' USING ERRCODE='23505';
END $$;

CREATE OR REPLACE FUNCTION public.fernsvilla_assign_payment_villa(payment_id bigint,villa_number text,expected_villa text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $mapping$
DECLARE p public."VillaPmt"%ROWTYPE; previous_setting text; previous_id text;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.fernsvilla_members WHERE user_id=auth.uid() AND role IN ('admin','editor')) THEN
  RAISE EXCEPTION 'Administrator or editor access required' USING ERRCODE='42501';
 END IF;
 IF villa_number IS NULL OR btrim(villa_number)='' OR NOT EXISTS (SELECT 1 FROM public."villaMaster" WHERE "Villa"=villa_number) THEN
  RAISE EXCEPTION 'Choose an existing villa';
 END IF;
 SELECT * INTO p FROM public."VillaPmt" WHERE id=payment_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Payment not found'; END IF;
 IF p."Villa"=villa_number THEN
  RETURN jsonb_build_object('payment',to_jsonb(p),'already_mapped',true);
 END IF;
 IF p."Villa" IS DISTINCT FROM expected_villa THEN RAISE EXCEPTION 'Payment villa changed. Refresh and retry'; END IF;
 IF p."IsSplitParent" THEN
  RAISE EXCEPTION 'Archived split receipts cannot be mapped';
 END IF;
 IF EXISTS (SELECT 1 FROM public."villaPaymentAllocations" a WHERE a.payment_id=p.id) THEN
  RAISE EXCEPTION 'This payment is already linked to dues and cannot be mapped';
 END IF;
 previous_id:=current_setting('fernsvilla.payment_villa_correction_id',true);
 previous_setting:=current_setting('fernsvilla.allow_payment_villa_correction',true);
 PERFORM set_config('fernsvilla.payment_villa_correction_id',p.id::text,true);
 PERFORM set_config('fernsvilla.allow_payment_villa_correction','on',true);
 UPDATE public."VillaPmt" SET "Villa"=villa_number WHERE id=p.id RETURNING * INTO p;
 PERFORM set_config('fernsvilla.allow_payment_villa_correction',coalesce(previous_setting,'off'),true);
 PERFORM set_config('fernsvilla.payment_villa_correction_id',coalesce(previous_id,''),true);
 RETURN jsonb_build_object('payment',to_jsonb(p),'already_mapped',false);
EXCEPTION WHEN unique_violation THEN
 RAISE EXCEPTION 'A payment already exists with this villa, amount, receipt date and billing month. No mapping was applied.' USING ERRCODE='23505';
END
$mapping$;

-- One financial balance account for each permanent master Villa (including grouped plots).
CREATE TABLE IF NOT EXISTS public."villaBalances" (
 "Villa" text PRIMARY KEY REFERENCES public."villaMaster"("Villa"),
 "outstandingBalance" numeric NOT NULL DEFAULT 0 CHECK ("outstandingBalance">=0),
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public."villaBalances" ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public."villaBalances" FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public."villaBalances" TO authenticated;
DROP POLICY IF EXISTS fernsvilla_balance_read ON public."villaBalances";
CREATE POLICY fernsvilla_balance_read ON public."villaBalances" FOR SELECT TO authenticated USING (
 EXISTS (SELECT 1 FROM public.fernsvilla_members WHERE user_id=auth.uid())
);
INSERT INTO public."villaBalances"("Villa") SELECT "Villa" FROM public."villaMaster" ON CONFLICT DO NOTHING;
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public."villaDues"'::regclass AND conname='villaDues_villa_balance_fkey') THEN
  ALTER TABLE public."villaDues" ADD CONSTRAINT "villaDues_villa_balance_fkey" FOREIGN KEY(villa) REFERENCES public."villaBalances"("Villa");
 END IF;
END $$;
CREATE OR REPLACE FUNCTION public.fernsvilla_create_balance_account()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 INSERT INTO public."villaBalances"("Villa") VALUES(NEW."Villa") ON CONFLICT DO NOTHING;
 RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS fernsvilla_create_balance_account ON public."villaMaster";
CREATE TRIGGER fernsvilla_create_balance_account AFTER INSERT ON public."villaMaster"
 FOR EACH ROW EXECUTE FUNCTION public.fernsvilla_create_balance_account();
CREATE OR REPLACE FUNCTION public.fernsvilla_sync_villa_balance()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE old_villa text; new_villa text; account text;
BEGIN
 IF TG_OP<>'INSERT' THEN old_villa:=OLD.villa; END IF;
 IF TG_OP<>'DELETE' THEN new_villa:=NEW.villa; END IF;
 -- Serialize aggregate updates per villa; query sums after acquiring the account lock.
 FOR account IN SELECT DISTINCT v FROM unnest(ARRAY[old_villa,new_villa]) v WHERE v IS NOT NULL ORDER BY v LOOP
  PERFORM "Villa" FROM public."villaBalances" WHERE "Villa"=account FOR UPDATE;
  UPDATE public."villaBalances" SET "outstandingBalance"=(SELECT coalesce(sum("outstandingAmt"),0) FROM public."villaDues" WHERE villa=account),updated_at=clock_timestamp() WHERE "Villa"=account;
 END LOOP;
 RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS fernsvilla_sync_villa_balance ON public."villaDues";
CREATE TRIGGER fernsvilla_sync_villa_balance AFTER INSERT OR UPDATE OR DELETE ON public."villaDues"
 FOR EACH ROW EXECUTE FUNCTION public.fernsvilla_sync_villa_balance();
UPDATE public."villaBalances" b SET "outstandingBalance"=(SELECT coalesce(sum("outstandingAmt"),0) FROM public."villaDues" WHERE villa=b."Villa");
REVOKE ALL ON FUNCTION public.fernsvilla_create_balance_account(),public.fernsvilla_sync_villa_balance() FROM PUBLIC,anon,authenticated;
COMMIT;
