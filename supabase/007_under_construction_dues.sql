-- Run after 006. Applies to future monthly loads; existing dues and payments are preserved.
BEGIN;
CREATE OR REPLACE FUNCTION public.fernsvilla_zero_construction_maintenance()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF lower(btrim(NEW."ResStatus"))='under construction' THEN
  NEW."MaintAmount":=0;
 END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS fernsvilla_construction_maintenance ON public."villaMaster";
CREATE TRIGGER fernsvilla_construction_maintenance
 BEFORE INSERT OR UPDATE OF "ResStatus","MaintAmount" ON public."villaMaster"
 FOR EACH ROW EXECUTE FUNCTION public.fernsvilla_zero_construction_maintenance();

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
 SELECT m."Villa",'Monthly maintenance','Monthly maintenance '||to_char(billing_date,'YYYY-MM'),CASE WHEN lower(btrim(m."ResStatus"))='under construction' THEN 0 ELSE m."MaintAmount" END,billing_date,'Pending',NULL
 FROM public."villaMaster" m WHERE (m."MaintAmount">0 OR lower(btrim(m."ResStatus"))='under construction')
 AND NOT EXISTS (SELECT 1 FROM public."villaDues" d WHERE d.villa=m."Villa" AND d."dueTyp"='Monthly maintenance'
 AND date_trunc('month',d."dueDate")=date_trunc('month',billing_date))
 ON CONFLICT (villa,"dueTyp","dueDate") DO NOTHING;
 GET DIAGNOSTICS inserted=ROW_COUNT;
 RETURN jsonb_build_object('inserted',inserted,'skipped',eligible-inserted,'eligible',eligible);
END $$;
REVOKE ALL ON FUNCTION public.fernsvilla_load_monthly_dues(date) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fernsvilla_load_monthly_dues(date) TO authenticated;
COMMIT;
