-- Transfer v27: customer/driver choice and driver icon preference.
-- Run once in Supabase SQL Editor AFTER transfer-upgrade.sql and admin-access-control.sql.
-- Additive only: preserves existing accounts and bookings.
begin;

alter table public.vip_profiles
  add column if not exists account_type text
  check (account_type is null or account_type in ('customer','driver'));

-- The role remains controlled by the administrator. account_type only records
-- the user's selected experience; a driver still needs admin approval.
grant update (account_type, driver_icon) on public.vip_profiles to authenticated;

commit;
