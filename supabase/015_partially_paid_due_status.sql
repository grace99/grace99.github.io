-- Apply after 013 (and after 014 if using Admin center). Run the entire file.
-- Changes status labels only; allocation/payment amounts and outstanding balances are retained.
BEGIN;
LOCK TABLE public."VillaPmt",public."villaDues",public."villaPaymentAllocations" IN ACCESS EXCLUSIVE MODE;
CREATE OR REPLACE FUNCTION public.fernsvilla_due_status()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $status$
BEGIN
 SELECT coalesce(sum(amount),0),max(payment_id) INTO NEW."paidAmt",NEW."PmtId" FROM public."villaPaymentAllocations"
 WHERE villa=NEW.villa AND "dueTyp"=NEW."dueTyp" AND "dueDate"=NEW."dueDate";
 IF NEW."paidAmt">coalesce(NEW."dueAmt",0) THEN RAISE EXCEPTION 'Due amount cannot be less than its applied payments'; END IF;
 NEW."dueStatus":=CASE
  WHEN NEW."dueAmt"=0 THEN 'NIL'
  WHEN NEW."paidAmt">=NEW."dueAmt" THEN 'Cleared'
  WHEN NEW."paidAmt">0 THEN 'Partially paid'
  ELSE 'Unpaid'
 END;
 RETURN NEW;
END $status$;
REVOKE ALL ON FUNCTION public.fernsvilla_due_status() FROM PUBLIC,anon,authenticated;
-- Normalize existing processed dues. The existing trigger derives status from actual allocations.
-- Only differing statuses are updated; rerunning is safe and does not create duplicate history.
UPDATE public."villaDues" SET "dueStatus"="dueStatus"
WHERE "dueStatus" IS DISTINCT FROM CASE
 WHEN "dueAmt"=0 THEN 'NIL'
 WHEN "paidAmt">="dueAmt" THEN 'Cleared'
 WHEN "paidAmt">0 THEN 'Partially paid'
 ELSE 'Unpaid'
END;
COMMIT;
