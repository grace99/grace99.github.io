-- Fix update access after member read access is already working.
-- Run in Supabase SQL Editor. No records or unrelated policies are modified.
BEGIN;
GRANT UPDATE (
  "Name", "Area", "Street", "MaintAmount", "ResStatus", "OwnORrent",
  "NumRes", "NumKids", "NumVehicles", "NumPets", "OwnCCTV", "OwnPwrLine",
  "Ostatus", "PriPhoneNo", "SecPhoneNo", "PriEmailAdd", "SecEmailAdd"
) ON public."villaMaster" TO authenticated;

DROP POLICY IF EXISTS fernsvilla_villa_update ON public."villaMaster";
CREATE POLICY fernsvilla_villa_update ON public."villaMaster"
FOR UPDATE TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.fernsvilla_members
    WHERE user_id = auth.uid() AND role IN ('admin', 'editor')
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.fernsvilla_members
    WHERE user_id = auth.uid() AND role IN ('admin', 'editor')
  )
);
COMMIT;
