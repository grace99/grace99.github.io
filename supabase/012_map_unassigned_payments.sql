-- Apply after 011. Unassigned receipts may be recorded, then explicitly mapped with history.
BEGIN;
CREATE OR REPLACE FUNCTION public.fernsvilla_protect_payment_villa()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $guard$
BEGIN
 IF OLD."Villa" IS DISTINCT FROM NEW."Villa"
  AND (current_setting('fernsvilla.allow_payment_villa_correction',true) IS DISTINCT FROM 'on'
       OR coalesce(current_setting('fernsvilla.payment_villa_correction_id',true),'') NOT IN ('',OLD.id::text)) THEN
  RAISE EXCEPTION 'Payment % villa cannot change from % to %. Use a reviewed administrator correction transaction.',
   OLD.id,OLD."Villa",NEW."Villa" USING ERRCODE='23514';
 END IF;
 RETURN NULL;
END
$guard$;

DROP POLICY IF EXISTS fernsvilla_payment_insert ON public."VillaPmt";
CREATE POLICY fernsvilla_payment_insert ON public."VillaPmt" FOR INSERT TO authenticated WITH CHECK (
 EXISTS (SELECT 1 FROM public.fernsvilla_members WHERE user_id=auth.uid() AND role IN ('admin','editor'))
 AND ("Villa" IS NULL OR EXISTS (SELECT 1 FROM public."villaMaster" m WHERE m."Villa"="VillaPmt"."Villa"))
 AND "PmtDate" IS NOT NULL AND "PmtAmt">0
);
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
 IF EXISTS (SELECT 1 FROM public."villaDues" WHERE "PmtId"=p.id) THEN
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
REVOKE ALL ON FUNCTION public.fernsvilla_assign_payment_villa(bigint,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fernsvilla_assign_payment_villa(bigint,text,text) TO authenticated;
COMMIT;
