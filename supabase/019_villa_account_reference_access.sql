-- Run after creating public.villa_account_reference, before using the Analytics view.
-- Adds read access only; preserves records and existing write grants/policies.
BEGIN;
ALTER TABLE public.villa_account_reference ENABLE ROW LEVEL SECURITY;
REVOKE SELECT ON public.villa_account_reference FROM PUBLIC,anon;
GRANT SELECT ON public.villa_account_reference TO authenticated;
DROP POLICY IF EXISTS fernsvilla_bank_reference_manager_read ON public.villa_account_reference;
CREATE POLICY fernsvilla_bank_reference_manager_read
 ON public.villa_account_reference FOR SELECT TO authenticated
 USING (EXISTS (
  SELECT 1 FROM public.fernsvilla_members m
  WHERE m.user_id=auth.uid() AND m.role IN ('admin','editor')
 ));
-- Keep permissive legacy SELECT policies from exposing bank references to residents/anon.
DROP POLICY IF EXISTS fernsvilla_bank_reference_read_boundary ON public.villa_account_reference;
CREATE POLICY fernsvilla_bank_reference_read_boundary
 ON public.villa_account_reference AS RESTRICTIVE FOR SELECT TO anon,authenticated
 USING (EXISTS (
  SELECT 1 FROM public.fernsvilla_members m
  WHERE m.user_id=auth.uid() AND m.role IN ('admin','editor')
 ));
COMMIT;
