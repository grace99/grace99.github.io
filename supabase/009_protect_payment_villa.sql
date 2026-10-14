-- Run after 008. This guard does not repair or reassign any existing payment.
-- Normal matching, status updates, date corrections and splitting remain permitted.
BEGIN;
CREATE OR REPLACE FUNCTION public.fernsvilla_protect_payment_villa()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $guard$
BEGIN
 IF OLD."Villa" IS DISTINCT FROM NEW."Villa"
  AND current_setting('fernsvilla.allow_payment_villa_correction',true) IS DISTINCT FROM 'on' THEN
  RAISE EXCEPTION 'Payment % villa cannot change from % to %. Use a reviewed administrator correction transaction.',
   OLD.id,OLD."Villa",NEW."Villa" USING ERRCODE='23514';
 END IF;
 RETURN NULL;
END
$guard$;
DROP TRIGGER IF EXISTS fernsvilla_protect_payment_villa ON public."VillaPmt";
-- Check every UPDATE, including changes introduced by BEFORE triggers.
CREATE TRIGGER fernsvilla_protect_payment_villa AFTER UPDATE ON public."VillaPmt"
 FOR EACH ROW EXECUTE FUNCTION public.fernsvilla_protect_payment_villa();
COMMIT;

-- A reviewed administrator repair can explicitly opt in inside ONE transaction:
-- BEGIN;
-- SET LOCAL fernsvilla.allow_payment_villa_correction = 'on';
-- ... narrowly scoped corrections with verified old and new villa values ...
-- COMMIT;
-- Never guess new values or run a broad UPDATE without a WHERE clause.
