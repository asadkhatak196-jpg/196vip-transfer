-- TRANSFER BUILD 70 — Auth and role authorization hardening
-- Additive/safe migration for the existing Transfer Supabase project.
-- Run ONCE in Supabase SQL Editor after reviewing the existing project.
-- Does not drop tables or delete user/booking data.

begin;

-- A new authenticated user always starts as a CUSTOMER.
-- User-editable auth metadata is used only for display name/phone, never for roles.
create or replace function public.transfer_handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.vip_profiles (id, email, full_name, role, is_available, account_type)
  values (
    new.id,
    lower(coalesce(new.email, '')),
    left(coalesce(new.raw_user_meta_data ->> 'full_name', ''), 120),
    'customer',
    false,
    null
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- Install/update the signup trigger without touching existing profiles.
drop trigger if exists transfer_auth_user_profile on auth.users;
create trigger transfer_auth_user_profile
after insert on auth.users
for each row execute function public.transfer_handle_new_auth_user();

-- Backfill only missing profiles for accounts that already exist in Auth.
insert into public.vip_profiles (id, email, full_name, role, is_available, account_type)
select u.id, lower(coalesce(u.email, '')),
       left(coalesce(u.raw_user_meta_data ->> 'full_name', ''), 120),
       'customer', false, null
from auth.users u
where not exists (select 1 from public.vip_profiles p where p.id = u.id);

-- Enforce least privilege. A user may edit only their basic profile fields and
-- account_type choice. They cannot grant themselves driver/admin role or set
-- availability. Driver role is still granted only by protected admin workflow.
revoke insert, update, delete on public.vip_profiles from anon;
revoke update on public.vip_profiles from authenticated;
grant select on public.vip_profiles to authenticated;
grant update (full_name, phone, driver_icon, account_type)
  on public.vip_profiles to authenticated;

-- RLS remains mandatory for the exposed profile table.
alter table public.vip_profiles enable row level security;

-- The existing profile update policy and vip_protect_profile_fields trigger
-- enforce ownership/admin access and prevent self-editing role/email.
-- Ensure the admin-check RPCs cannot be called by anonymous visitors.
revoke all on function public.vip_is_admin() from public, anon;
revoke all on function public.vip_is_main_admin() from public, anon;
grant execute on function public.vip_is_admin() to authenticated;
grant execute on function public.vip_is_main_admin() to authenticated;

commit;

-- Expected security behavior after this migration:
-- 1. Email OTP authenticates the identity; no password or SMS is required.
-- 2. New accounts start as customer; user_metadata cannot assign a role.
-- 3. /admin requires vip_is_admin() (primary admin email or enabled secondary admin).
-- 4. /driver requires role='driver'; the driver application must be approved first.
-- 5. A customer cannot change their role, email, or online/availability flag.
