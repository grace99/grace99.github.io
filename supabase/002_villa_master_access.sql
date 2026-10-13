-- Optional: apply only if villaMaster needs access policies for this app.
-- Run 001_association.sql first. Existing rows and columns are left intact.
begin;
do $$
begin
 if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'villaMaster'
   and policyname not in ('fernsvilla_villa_read','fernsvilla_villa_insert','fernsvilla_villa_update')) then
  raise exception 'villaMaster already has other policies. Review them before applying association access policies; no policies were changed.';
 end if;
end;
$$;
alter table public."villaMaster" enable row level security;
revoke all on public."villaMaster" from anon;
grant select on public."villaMaster" to authenticated;
grant insert ("Villa","Name","Area","Street","MaintAmount","ResStatus","OwnORrent","NumRes","NumKids","NumVehicles","NumPets","OwnCCTV","OwnPwrLine","Ostatus","PriPhoneNo","SecPhoneNo","PriEmailAdd","SecEmailAdd") on public."villaMaster" to authenticated;
grant update ("Name","Area","Street","MaintAmount","ResStatus","OwnORrent","NumRes","NumKids","NumVehicles","NumPets","OwnCCTV","OwnPwrLine","Ostatus","PriPhoneNo","SecPhoneNo","PriEmailAdd","SecEmailAdd") on public."villaMaster" to authenticated;
-- Identity-backed inserts require sequence usage on projects with explicit sequence ACLs.
do $$
declare seq text;
begin
 seq := pg_get_serial_sequence('public."villaMaster"','id');
 if seq is not null then execute format('grant usage on sequence %s to authenticated',seq); end if;
end;
$$;
drop policy if exists fernsvilla_villa_read on public."villaMaster";
create policy fernsvilla_villa_read on public."villaMaster" for select to authenticated using (
 exists (select 1 from public.fernsvilla_members where user_id = auth.uid())
);
drop policy if exists fernsvilla_villa_insert on public."villaMaster";
create policy fernsvilla_villa_insert on public."villaMaster" for insert to authenticated with check (
 exists (select 1 from public.fernsvilla_members where user_id = auth.uid() and role in ('admin','editor'))
);
drop policy if exists fernsvilla_villa_update on public."villaMaster";
create policy fernsvilla_villa_update on public."villaMaster" for update to authenticated using (
 exists (select 1 from public.fernsvilla_members where user_id = auth.uid() and role in ('admin','editor'))
) with check (
 exists (select 1 from public.fernsvilla_members where user_id = auth.uid() and role in ('admin','editor'))
);
commit;
