-- Run in the SQL Editor of project exrhpaqpepubscyqflov.
-- Dedicated tables; no existing application data is modified.
begin;
create table if not exists public.fernsvilla_members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('admin','editor','resident')) default 'resident'
);
create table if not exists public.fernsvilla_state (
  id integer primary key check (id = 1),
  data jsonb not null,
  revision bigint not null default 0,
  updated_at timestamptz not null default now()
);
alter table public.fernsvilla_members enable row level security;
alter table public.fernsvilla_state enable row level security;
revoke all on public.fernsvilla_members, public.fernsvilla_state from anon, authenticated;
grant select on public.fernsvilla_members, public.fernsvilla_state to authenticated;

drop policy if exists fernsvilla_own_membership on public.fernsvilla_members;
create policy fernsvilla_own_membership on public.fernsvilla_members for select to authenticated using (user_id = auth.uid());
drop policy if exists fernsvilla_member_read on public.fernsvilla_state;
create policy fernsvilla_member_read on public.fernsvilla_state for select to authenticated using (
 exists (select 1 from public.fernsvilla_members where user_id = auth.uid())
);
insert into public.fernsvilla_state (id,data) values (1,
 '{"villas":[],"issues":[],"team":[],"resources":[],"posts":[],"payments":[]}'::jsonb
) on conflict (id) do nothing;

-- Atomic revision check prevents concurrent clients silently overwriting data.
create or replace function public.fernsvilla_save(expected_revision bigint, new_data jsonb)
returns bigint language plpgsql security definer set search_path = '' as $$
declare next_revision bigint;
begin
 if not exists (select 1 from public.fernsvilla_members where user_id = auth.uid() and role in ('admin','editor')) then
  raise exception 'Administrator or editor access required' using errcode = '42501';
 end if;
 if new_data is null or jsonb_typeof(new_data) <> 'object' or not (new_data ?& array['villas','issues','team','resources','posts','payments']) then
  raise exception 'Invalid association data';
 end if;
 if exists (select 1 from unnest(array['villas','issues','team','resources','posts','payments']) as keys(k) where jsonb_typeof(new_data -> k) <> 'array') then
  raise exception 'Invalid association data';
 end if;
 update public.fernsvilla_state set data = new_data, revision = revision + 1, updated_at = now()
 where id = 1 and revision = expected_revision returning revision into next_revision;
 if next_revision is null then
  raise exception 'Another member updated the data. Refresh association data and retry your change.' using errcode = '40001';
 end if;
 return next_revision;
end;
$$;
revoke all on function public.fernsvilla_save(bigint,jsonb) from public, anon, authenticated;
grant execute on function public.fernsvilla_save(bigint,jsonb) to authenticated;
commit;
