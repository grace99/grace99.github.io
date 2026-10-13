-- Existing villaDues and VillaPmt tables are retained; no financial rows are migrated or deleted.
-- Run after 001_association.sql. Membership controls access.
BEGIN;
ALTER TABLE public."villaDues" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."VillaPmt" ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public."villaDues",public."VillaPmt" FROM anon;
GRANT SELECT ON public."villaDues",public."VillaPmt" TO authenticated;
GRANT INSERT (villa,"dueTyp","dueDesc","dueAmt","dueDate","dueStatus","PmtId") ON public."villaDues" TO authenticated;
GRANT INSERT ("Villa","PmtDate","AccountNum","PmtMthd","PmtDueToward","PmtAmt","PmtRemarks","UTR","LatePmt") ON public."VillaPmt" TO authenticated;
DO $$ DECLARE seq text; BEGIN
 seq:=pg_get_serial_sequence('public."VillaPmt"','id');
 IF seq IS NOT NULL THEN EXECUTE format('GRANT USAGE ON SEQUENCE %s TO authenticated',seq); END IF;
END $$;
DROP POLICY IF EXISTS fernsvilla_due_read ON public."villaDues";
CREATE POLICY fernsvilla_due_read ON public."villaDues" FOR SELECT TO authenticated USING (
 EXISTS (SELECT 1 FROM public.fernsvilla_members WHERE user_id=auth.uid())
);
DROP POLICY IF EXISTS fernsvilla_payment_read ON public."VillaPmt";
CREATE POLICY fernsvilla_payment_read ON public."VillaPmt" FOR SELECT TO authenticated USING (
 EXISTS (SELECT 1 FROM public.fernsvilla_members WHERE user_id=auth.uid())
);
DROP POLICY IF EXISTS fernsvilla_due_insert ON public."villaDues";
CREATE POLICY fernsvilla_due_insert ON public."villaDues" FOR INSERT TO authenticated WITH CHECK (
 EXISTS (SELECT 1 FROM public.fernsvilla_members WHERE user_id=auth.uid() AND role IN ('admin','editor'))
 AND EXISTS (SELECT 1 FROM public."villaMaster" m WHERE m."Villa"=villa)
 AND "dueTyp"<>'Monthly maintenance' AND "dueTyp" IS NOT NULL AND length(btrim("dueTyp"))>0 AND "dueDate" IS NOT NULL
 AND "dueAmt">0 AND "dueStatus"='Pending' AND "PmtId" IS NULL
);
DROP POLICY IF EXISTS fernsvilla_payment_insert ON public."VillaPmt";
CREATE POLICY fernsvilla_payment_insert ON public."VillaPmt" FOR INSERT TO authenticated WITH CHECK (
 EXISTS (SELECT 1 FROM public.fernsvilla_members WHERE user_id=auth.uid() AND role IN ('admin','editor'))
 AND "Villa" IS NOT NULL AND "PmtDate" IS NOT NULL AND "PmtAmt">0
);

-- Lock the payment before checking allocation. Two simultaneous requests cannot spend its balance twice.
CREATE OR REPLACE FUNCTION public.fernsvilla_apply_payment(due_villa text,due_type text,due_date date,payment_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE p public."VillaPmt"%ROWTYPE; d public."villaDues"%ROWTYPE; used numeric;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.fernsvilla_members WHERE user_id=auth.uid() AND role IN ('admin','editor')) THEN
  RAISE EXCEPTION 'Administrator or editor access required' USING ERRCODE='42501';
 END IF;
 IF due_villa IS NULL OR due_type IS NULL OR due_date IS NULL OR payment_id IS NULL THEN RAISE EXCEPTION 'Due identity and payment ID are required'; END IF;
 SELECT * INTO p FROM public."VillaPmt" WHERE id=payment_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Payment not found'; END IF;
 SELECT * INTO d FROM public."villaDues" WHERE villa=due_villa AND "dueTyp"=due_type AND "dueDate"=due_date FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Due not found. Refresh and retry'; END IF;
 IF d."dueStatus"='Cleared' OR d."PmtId" IS NOT NULL THEN RAISE EXCEPTION 'This due is already cleared or assigned to a payment'; END IF;
 IF p."Villa" IS DISTINCT FROM d.villa THEN RAISE EXCEPTION 'Payment must belong to the same villa'; END IF;
 IF d."dueAmt" IS NULL OR d."dueAmt"<=0 OR p."PmtAmt" IS NULL OR p."PmtAmt"<=0 THEN RAISE EXCEPTION 'Due and payment amounts must be positive'; END IF;
 SELECT coalesce(sum("dueAmt"),0) INTO used FROM public."villaDues" WHERE "PmtId"=payment_id;
 IF p."PmtAmt"-used<d."dueAmt" THEN RAISE EXCEPTION 'Payment has insufficient unallocated balance to clear this due'; END IF;
 UPDATE public."villaDues" SET "PmtId"=payment_id,"dueStatus"='Cleared'
 WHERE villa=due_villa AND "dueTyp"=due_type AND "dueDate"=due_date RETURNING * INTO d;
 RETURN to_jsonb(d);
END $$;
REVOKE ALL ON FUNCTION public.fernsvilla_apply_payment(text,text,date,bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fernsvilla_apply_payment(text,text,date,bigint) TO authenticated;

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
 SELECT count(*) INTO eligible FROM public."villaMaster" WHERE "MaintAmount">0;
 INSERT INTO public."villaDues"(villa,"dueTyp","dueDesc","dueAmt","dueDate","dueStatus","PmtId")
 SELECT m."Villa",'Monthly maintenance','Monthly maintenance '||to_char(billing_date,'YYYY-MM'),m."MaintAmount",billing_date,'Pending',NULL
 FROM public."villaMaster" m WHERE m."MaintAmount">0
 AND NOT EXISTS (SELECT 1 FROM public."villaDues" d WHERE d.villa=m."Villa" AND d."dueTyp"='Monthly maintenance'
 AND date_trunc('month',d."dueDate")=date_trunc('month',billing_date))
 ON CONFLICT (villa,"dueTyp","dueDate") DO NOTHING;
 GET DIAGNOSTICS inserted=ROW_COUNT;
 RETURN jsonb_build_object('inserted',inserted,'skipped',eligible-inserted,'eligible',eligible);
END $$;
REVOKE ALL ON FUNCTION public.fernsvilla_load_monthly_dues(date) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fernsvilla_load_monthly_dues(date) TO authenticated;
COMMIT;
