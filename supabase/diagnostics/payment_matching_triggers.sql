-- READ ONLY. Run this file by itself; share ALL result rows.
SELECT c.relname AS table_name, t.tgname AS trigger_name,
       pg_get_triggerdef(t.oid) AS trigger_definition,
       n.nspname || '.' || p.proname AS function_name,
       pg_get_functiondef(p.oid) AS function_definition
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_proc p ON p.oid = t.tgfoid
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE t.tgrelid IN ('public."VillaPmt"'::regclass, 'public."villaDues"'::regclass)
  AND NOT t.tgisinternal AND t.tgenabled <> 'D'
ORDER BY c.relname, t.tgname;
