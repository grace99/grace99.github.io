-- READ ONLY. Run this file by itself.
-- These inconsistencies are evidence, not instructions to reassign villas.
SELECT p.id AS payment_id, p."Villa" AS payment_villa,
       d.villa AS due_villa, d."dueTyp", d."dueDate", d."dueAmt"
FROM public."VillaPmt" p
JOIN public."villaDues" d ON d."PmtId" = p.id
WHERE p."Villa" IS DISTINCT FROM d.villa
ORDER BY p.id, d."dueDate";
