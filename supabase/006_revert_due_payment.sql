-- Apply after 005_payment_splitting.sql. Reverse allocation, not receipt income.
-- Applying a payment only changes villaDues; VillaPmt balances derive from those links.
BEGIN;
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
 already_pending:=d."dueStatus" IS NOT DISTINCT FROM 'Pending' AND d."PmtId" IS NULL;
 IF NOT already_pending THEN
  IF d."dueStatus" IS DISTINCT FROM 'Cleared' OR d."PmtId" IS DISTINCT FROM expected_payment_id THEN
   RAISE EXCEPTION 'Due status or linked payment changed. Refresh and retry';
  END IF;
  UPDATE public."villaDues" SET "PmtId"=NULL,"dueStatus"='Pending'
  WHERE villa=due_villa AND "dueTyp"=due_type AND "dueDate"=due_date RETURNING * INTO d;
 END IF;
 IF expected_payment_id IS NOT NULL THEN
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
COMMIT;
