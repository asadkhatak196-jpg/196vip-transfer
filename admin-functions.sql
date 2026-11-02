-- Transfer app: required database additions for driver discovery and admin approval.
-- Run this AFTER the reviewed base setup SQL in the Supabase SQL Editor.
-- Safe additive migration: does not delete existing tables or booking data.

begin;

-- Approved, enabled drivers may discover open booking requests so they can quote a price.
drop policy if exists "vip drivers read open bookings" on public.vip_bookings;
create policy "vip drivers read open bookings"
on public.vip_bookings for select to authenticated
using (
  status = 'open'
  and exists (
    select 1
    from public.vip_profiles p
    join public.vip_driver_applications a on a.driver_id = p.id
    where p.id = auth.uid()
      and p.role = 'driver'
      and a.status = 'approved'
  )
);

-- Allow a signed-in user to update only the profile columns already granted
-- by the base setup (full_name and driver_icon). Role is changed only by the
-- administrator RPC below.
drop policy if exists "vip profile update own fields" on public.vip_profiles;
create policy "vip profile update own fields"
on public.vip_profiles for update to authenticated
using (id = auth.uid() or public.vip_is_admin())
with check (id = auth.uid() or public.vip_is_admin());

-- Admin-only function to approve or disable a driver without granting users
-- direct permission to change their own account role.
create or replace function public.vip_admin_set_driver_status(
  p_driver_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.vip_is_admin() then
    raise exception 'Administrator access required';
  end if;

  if p_status not in ('approved', 'disabled') then
    raise exception 'Status must be approved or disabled';
  end if;

  update public.vip_driver_applications
  set status = p_status
  where driver_id = p_driver_id;

  if not found then
    raise exception 'Driver application not found';
  end if;

  update public.vip_profiles
  set role = case when p_status = 'approved' then 'driver' else 'customer' end
  where id = p_driver_id;
end;
$$;

revoke all on function public.vip_admin_set_driver_status(uuid, text) from public;
grant execute on function public.vip_admin_set_driver_status(uuid, text) to authenticated;

-- Explicit table permissions used by the browser application.
grant select, insert on public.vip_bookings to authenticated;
grant select, insert on public.vip_driver_applications to authenticated;
grant select, insert, update, delete on public.vip_vehicles to authenticated;
grant select, insert on public.vip_offers to authenticated;
grant select, insert on public.vip_messages to authenticated;
grant select, update on public.vip_settings to authenticated;

commit;
