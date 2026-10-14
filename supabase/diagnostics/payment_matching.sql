-- READ ONLY. Run each SELECT separately and share its result.
-- 1. Enabled user-defined triggers on payment and due tables.
SELECT c.relname AS table_name, t.tgname AS trigger_name,
       pg_get_triggerdef(t.oid) AS trigger_definition,
       n.nspname || '.' || p.proname AS function_name
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_proc p ON p.oid = t.tgfoid
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE t.tgrelid IN ('public."VillaPmt"'::regclass, 'public."villaDues"'::regclass)
  AND NOT t.tgisinternal AND t.tgenabled <> 'D'
ORDER BY c.relname, t.tgname;

-- 2. Payments linked to dues for a DIFFERENT villa: confirms current inconsistencies,
-- but cannot establish which value was correct before the incident.
SELECT p.id AS payment_id, p."Villa" AS payment_villa,
       d.villa AS due_villa, d."dueTyp", d."dueDate", d."dueAmt"
FROM public."VillaPmt" p
JOIN public."villaDues" d ON d."PmtId" = p.id
WHERE p."Villa" IS DISTINCT FROM d.villa
ORDER BY p.id, d."dueDate";

-- 3. Balance breakdown for villa 126 and previously discussed IDs.
-- Add other affected payment IDs to the IN list if appropriate.
SELECT p.id AS payment_id, p."Villa", p."PmtAmt", p."PaymentStatus",
       p."IsSplitParent", p."SplitFromPmtId",
       count(d."PmtId") AS linked_due_count,
       coalesce(sum(d."dueAmt"),0) AS applied_amount,
       CASE WHEN p."IsSplitParent" THEN 0
            ELSE p."PmtAmt"-coalesce(sum(d."dueAmt"),0) END AS available_balance
FROM public."VillaPmt" p
LEFT JOIN public."villaDues" d ON d."PmtId"=p.id
WHERE p."Villa"='126' OR p.id IN (35,56)
GROUP BY p.id
ORDER BY p.id;
