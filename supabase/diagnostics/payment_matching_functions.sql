-- READ ONLY. Run this file alone and paste the complete function_sql text for each row.
-- Inspect the deployed bodies, not just function/trigger names.
SELECT p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS arguments,
       pg_get_functiondef(p.oid) AS function_sql
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
 AND p.proname IN (
  'fernsvilla_payment_status',
  'fernsvilla_sync_payment_status',
  'fernsvilla_due_status',
  'fernsvilla_apply_payment',
  'fernsvilla_apply_payment_to_dues'
 )
ORDER BY p.proname;
