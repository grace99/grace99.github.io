-- Run after 013_partial_payment_allocations.sql (and subsequent migrations).
-- Replaces the split RPC only; no columns or existing payment records are changed.
BEGIN;
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
 IF total>p."PmtAmt" THEN RAISE EXCEPTION 'Allocated amounts cannot exceed the original payment amount'; END IF;
 IF total<p."PmtAmt" AND (p."Villa" IS NULL OR btrim(p."Villa")='') THEN
  RAISE EXCEPTION 'Map the original payment to a villa before leaving a credit';
 END IF;
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
 -- Keep the remainder as an active, unrestricted credit transaction. The archived
 -- receipt remains excluded from balances; all children together conserve its amount.
 IF total<p."PmtAmt" THEN
  INSERT INTO public."VillaPmt"("Villa","PmtDate","AccountNum","PmtMthd","PmtDueToward","PmtAmt","PmtRemarks","UTR","LatePmt","AllocationMonth","SplitFromPmtId","IsSplitParent")
  VALUES(p."Villa",p."PmtDate",p."AccountNum",p."PmtMthd",p."PmtDueToward",p."PmtAmt"-total,p."PmtRemarks",p."UTR",p."LatePmt",NULL,p.id,false)
  RETURNING * INTO child;
  result:=result||jsonb_build_array(to_jsonb(child));
 END IF;
 RETURN jsonb_build_object('original',to_jsonb(p),'payments',result,'already_split',false);
EXCEPTION WHEN unique_violation THEN
 RAISE EXCEPTION 'A payment already exists with this villa, amount, receipt date and billing month. No split was created.' USING ERRCODE='23505';
END $$;

COMMIT;
