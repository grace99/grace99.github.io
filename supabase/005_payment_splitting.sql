-- Apply after 004_dues_payments.sql. Existing receipts and dues links remain intact.
BEGIN;
ALTER TABLE public."VillaPmt"
 ADD COLUMN IF NOT EXISTS "AllocationMonth" date,
 ADD COLUMN IF NOT EXISTS "SplitFromPmtId" bigint REFERENCES public."VillaPmt"(id),
 ADD COLUMN IF NOT EXISTS "IsSplitParent" boolean NOT NULL DEFAULT false;

-- Serializes against payment matching using the same payment row lock.
CREATE OR REPLACE FUNCTION public.fernsvilla_split_payment(payment_id bigint,expected_amount numeric,allocations jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE p public."VillaPmt"%ROWTYPE; child public."VillaPmt"%ROWTYPE; item jsonb;
 total numeric:=0; portion numeric; billing_month date; result jsonb:='[]'::jsonb;
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
 IF EXISTS (SELECT 1 FROM public."villaDues" WHERE "PmtId"=p.id) THEN
  RAISE EXCEPTION 'This payment is already applied to dues and cannot be split';
 END IF;
 IF p."PmtAmt" IS NULL OR p."PmtAmt"<=0 OR p."PmtAmt" IS DISTINCT FROM expected_amount THEN
  RAISE EXCEPTION 'Payment amount changed or is invalid. Refresh and retry';
 END IF;
 IF allocations IS NULL OR jsonb_typeof(allocations)<>'array' OR jsonb_array_length(allocations)<2 OR jsonb_array_length(allocations)>120 THEN
  RAISE EXCEPTION 'Enter between 2 and 120 monthly allocations';
 END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(allocations) LOOP
  IF jsonb_typeof(item)<>'object' OR item->>'month' IS NULL OR (item->>'month') !~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
   OR item->>'amount' IS NULL OR (item->>'amount') !~ '^[0-9]+(\.[0-9]{1,2})?$' THEN
   RAISE EXCEPTION 'Each allocation needs a valid YYYY-MM month and a positive amount with at most two decimals';
  END IF;
  billing_month:=to_date((item->>'month')||'-01','YYYY-MM-DD');
  IF to_char(billing_month,'YYYY-MM')<>item->>'month' THEN RAISE EXCEPTION 'Invalid allocation month'; END IF;
  portion:=(item->>'amount')::numeric;
  IF portion<=0 THEN RAISE EXCEPTION 'Every allocation amount must be greater than zero'; END IF;
  total:=total+portion;
 END LOOP;
 IF total<>p."PmtAmt" THEN RAISE EXCEPTION 'Allocated amounts must equal the original payment amount'; END IF;
 IF (SELECT count(DISTINCT value->>'month') FROM jsonb_array_elements(allocations))<>jsonb_array_length(allocations) THEN
  RAISE EXCEPTION 'Use one allocation per month';
 END IF;
 UPDATE public."VillaPmt" SET "IsSplitParent"=true WHERE id=p.id RETURNING * INTO p;
 FOR item IN SELECT value FROM jsonb_array_elements(allocations) LOOP
  INSERT INTO public."VillaPmt"("Villa","PmtDate","AccountNum","PmtMthd","PmtDueToward","PmtAmt","PmtRemarks","UTR","LatePmt","AllocationMonth","SplitFromPmtId","IsSplitParent")
  VALUES(p."Villa",p."PmtDate",p."AccountNum",p."PmtMthd",p."PmtDueToward",(item->>'amount')::numeric,p."PmtRemarks",p."UTR",p."LatePmt",to_date((item->>'month')||'-01','YYYY-MM-DD'),p.id,false)
  RETURNING * INTO child;
  result:=result||jsonb_build_array(to_jsonb(child));
 END LOOP;
 RETURN jsonb_build_object('original',to_jsonb(p),'payments',result,'already_split',false);
END $$;
REVOKE ALL ON FUNCTION public.fernsvilla_split_payment(bigint,numeric,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fernsvilla_split_payment(bigint,numeric,jsonb) TO authenticated;

-- Archived originals are visible for audit but cannot fund any dues.
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
 IF p."IsSplitParent" THEN RAISE EXCEPTION 'Choose a split transaction payment ID, not the original receipt'; END IF;
 SELECT * INTO d FROM public."villaDues" WHERE villa=due_villa AND "dueTyp"=due_type AND "dueDate"=due_date FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Due not found. Refresh and retry'; END IF;
 IF d."dueStatus"='Cleared' OR d."PmtId" IS NOT NULL THEN RAISE EXCEPTION 'This due is already cleared or assigned to a payment'; END IF;
 IF p."Villa" IS DISTINCT FROM d.villa THEN RAISE EXCEPTION 'Payment must belong to the same villa'; END IF;
 IF p."AllocationMonth" IS NOT NULL AND date_trunc('month',p."AllocationMonth")<>date_trunc('month',d."dueDate") THEN RAISE EXCEPTION 'This split transaction is allocated to another month'; END IF;
 IF d."dueAmt" IS NULL OR d."dueAmt"<=0 OR p."PmtAmt" IS NULL OR p."PmtAmt"<=0 THEN RAISE EXCEPTION 'Due and payment amounts must be positive'; END IF;
 SELECT coalesce(sum("dueAmt"),0) INTO used FROM public."villaDues" WHERE "PmtId"=payment_id;
 IF p."PmtAmt"-used<d."dueAmt" THEN RAISE EXCEPTION 'Payment has insufficient unallocated balance to clear this due'; END IF;
 UPDATE public."villaDues" SET "PmtId"=payment_id,"dueStatus"='Cleared'
 WHERE villa=due_villa AND "dueTyp"=due_type AND "dueDate"=due_date RETURNING * INTO d;
 RETURN to_jsonb(d);
END $$;
-- Existing function grants are preserved by CREATE OR REPLACE.
COMMIT;
