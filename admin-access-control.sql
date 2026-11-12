-- Transfer: main administrator and revocable secondary administrators.
-- Run this once in Supabase SQL Editor AFTER the existing Transfer upgrade SQL.
-- Safe additive migration: does not delete existing app data.

begin;

create table if not exists public.vip_secondary_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vip_secondary_admins_email_lower check (email = lower(email))
);

alter table public.vip_secondary_admins enable row level security;
revoke all on public.vip_secondary_admins from anon, authenticated;

-- The primary administrator is fixed in database logic and cannot be replaced
-- from the browser or by a secondary administrator.
create or replace function public.vip_is_main_admin()
returns boolean
language sql stable security definer
set search_path = public, auth
as $$
  select lower(coalesce(auth.jwt() ->> 'email','')) = 'asadkhatak196@gmail.com';
$$;

create or replace function public.vip_is_admin()
returns boolean
language sql stable security definer
set search_path = public, auth
as $$
  select public.vip_is_main_admin()
      or exists (
        select 1 from public.vip_secondary_admins a
        where a.user_id = auth.uid() and a.enabled = true
      );
$$;

revoke all on function public.vip_is_main_admin() from public, anon;
revoke all on function public.vip_is_admin() from public, anon;
grant execute on function public.vip_is_main_admin() to authenticated;
grant execute on function public.vip_is_admin() to authenticated;

-- Main admin can add an already-registered account by email.
create or replace function public.vip_main_admin_add_secondary(p_email text)
returns void
language plpgsql security definer
set search_path = public, auth
as $$
declare v_user auth.users%rowtype; v_email text;
begin
  if not public.vip_is_main_admin() then raise exception 'Main administrator access required'; end if;
  v_email := lower(trim(coalesce(p_email,'')));
  if v_email = '' or position('@' in v_email) < 2 then raise exception 'Enter a valid email address'; end if;
  if v_email = 'asadkhatak196@gmail.com' then raise exception 'The main administrator cannot be added as a secondary administrator'; end if;
  select * into v_user from auth.users where lower(email) = v_email limit 1;
  if v_user.id is null then raise exception 'This user must sign in to Transfer once before being added as an administrator'; end if;
  insert into public.vip_secondary_admins(user_id,email,enabled)
  values(v_user.id,v_email,true)
  on conflict(user_id) do update set email=excluded.email, enabled=true, updated_at=now();
end;
$$;

create or replace function public.vip_main_admin_set_secondary_status(p_user_id uuid,p_enabled boolean)
returns void
language plpgsql security definer
set search_path = public, auth
as $$
begin
  if not public.vip_is_main_admin() then raise exception 'Main administrator access required'; end if;
  if exists(select 1 from auth.users where id=p_user_id and lower(email)='asadkhatak196@gmail.com') then
    raise exception 'The main administrator cannot be disabled';
  end if;
  update public.vip_secondary_admins
     set enabled=p_enabled, updated_at=now()
   where user_id=p_user_id;
  if not found then raise exception 'Secondary administrator not found'; end if;
end;
$$;

create or replace function public.vip_main_admin_list_secondary()
returns table(user_id uuid,email text,enabled boolean,created_at timestamptz)
language plpgsql stable security definer
set search_path = public, auth
as $$
begin
  if not public.vip_is_main_admin() then raise exception 'Main administrator access required'; end if;
  return query select a.user_id,a.email,a.enabled,a.created_at
    from public.vip_secondary_admins a order by a.created_at desc;
end;
$$;

revoke all on function public.vip_main_admin_add_secondary(text) from public, anon;
revoke all on function public.vip_main_admin_set_secondary_status(uuid,boolean) from public, anon;
revoke all on function public.vip_main_admin_list_secondary() from public, anon;
grant execute on function public.vip_main_admin_add_secondary(text) to authenticated;
grant execute on function public.vip_main_admin_set_secondary_status(uuid,boolean) to authenticated;
grant execute on function public.vip_main_admin_list_secondary() to authenticated;

commit;
