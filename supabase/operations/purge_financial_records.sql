-- DESTRUCTIVE ONE-TIME OPERATION: deletes ALL dues and payments.
-- Run the complete file in Supabase SQL Editor using the project administrator role.
-- Keep a table export beforehand if these records need to be retained.
-- Villa master, membership, other app data, schema, policies, guards and identity sequences remain unchanged.
BEGIN;
SET LOCAL lock_timeout = '15s';
LOCK TABLE public."VillaPmt", public."villaDues" IN ACCESS EXCLUSIVE MODE;

-- Remove due references before deleting receipts and their split transactions.
DELETE FROM public."villaDues";
DELETE FROM public."VillaPmt";

COMMIT;

-- Both counts must be zero after the operation.
SELECT (SELECT count(*) FROM public."villaDues") AS dues_remaining,
       (SELECT count(*) FROM public."VillaPmt") AS payments_remaining;
