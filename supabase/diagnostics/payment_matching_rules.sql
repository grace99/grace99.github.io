-- READ ONLY. Rewrite rules can add actions to an UPDATE without appearing as triggers.
SELECT schemaname, tablename, rulename, definition
FROM pg_rules
WHERE schemaname='public' AND tablename IN ('VillaPmt','villaDues')
ORDER BY tablename,rulename;
