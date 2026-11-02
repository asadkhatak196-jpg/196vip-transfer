-- Transfer: additive admin and privacy update for the EXISTING vip_* schema.
-- Review this script before running it in the SAME Supabase project.
-- It does not drop, rename, or recreate existing tables.

begin;

alter table public.vip_profiles add column if not exists phone text;
alter table public.vip_settings add column if not exists commission_percent numeric(5,2) not null default 10
  check (commission_percent >= 0 and commission_percent <= 100);

grant update (phone) on public.vip_profiles to authenticated;

drop policy if exists "vip profile update own permitted fields" on public.vip_profiles;
create policy "vip profile update own permitted fields"
on public.vip_profiles for update to authenticated
using (id = auth.uid() or public.vip_is_admin())
with check (id = auth.uid() or public.vip_is_admin());

-- Allow approved drivers to see open booking requests before they submit an offer.
drop policy if exists "vip bookings read open approved drivers" on public.vip_bookings;
create policy "vip bookings read open approved drivers"
on public.vip_bookings for select to authenticated
using (
  status = 'open'
  and exists (select 1 from public.vip_profiles p where p.id = auth.uid() and p.role = 'driver')
  and exists (select 1 from public.vip_driver_applications a where a.driver_id = auth.uid() and a.status = 'approved')
);

-- Keep phone number in the private profile row when a new email OTP account is created.
create or replace function public.vip_handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.vip_profiles (id, email, full_name, role, phone)
  values (new.id, new.email, coalesce(new.raw_user_meta_data ->> 'full_name',''), 'customer', new.raw_user_meta_data ->> 'phone')
  on conflict (id) do update set email = excluded.email, phone = coalesce(excluded.phone, public.vip_profiles.phone);
  return new;
end;
$$;

-- Admin-only review: approve a driver or disable the driver's account.
create or replace function public.vip_admin_review_driver(p_application_id uuid, p_approved boolean)
returns void language plpgsql security definer set search_path = public
as $$
declare v_driver uuid;
begin
  if not public.vip_is_admin() then raise exception 'Admin access required'; end if;
  select driver_id into v_driver from public.vip_driver_applications where id = p_application_id for update;
  if v_driver is null then raise exception 'Driver application not found'; end if;
  update public.vip_driver_applications set status = case when p_approved then 'approved' else 'disabled' end where id = p_application_id;
  update public.vip_profiles set role = case when p_approved then 'driver' else 'customer' end where id = v_driver;
end;
$$;
revoke all on function public.vip_admin_review_driver(uuid, boolean) from public;
grant execute on function public.vip_admin_review_driver(uuid, boolean) to authenticated;

-- Admin can override a driver offer price or end it (existing status 'rejected' is used as ended).
create or replace function public.vip_admin_update_offer(p_offer_id uuid, p_price_sar numeric, p_end_offer boolean)
returns void language plpgsql security definer set search_path = public
as $$
begin
  if not public.vip_is_admin() then raise exception 'Admin access required'; end if;
  if p_end_offer then
    update public.vip_offers set status = 'rejected' where id = p_offer_id and status = 'pending';
  else
    if p_price_sar is null or p_price_sar <= 0 then raise exception 'Price must be greater than zero'; end if;
    update public.vip_offers set price_sar = p_price_sar where id = p_offer_id and status = 'pending';
  end if;
  if not found then raise exception 'Pending offer not found'; end if;
end;
$$;
revoke all on function public.vip_admin_update_offer(uuid, numeric, boolean) from public;
grant execute on function public.vip_admin_update_offer(uuid, numeric, boolean) to authenticated;

-- Admin can switch driver offers on/off and set the company commission percentage.
create or replace function public.vip_admin_update_settings(p_offers_enabled boolean, p_commission_percent numeric)
returns void language plpgsql security definer set search_path = public
as $$
begin
  if not public.vip_is_admin() then raise exception 'Admin access required'; end if;
  if p_commission_percent < 0 or p_commission_percent > 100 then raise exception 'Commission must be between 0 and 100'; end if;
  update public.vip_settings set offers_enabled = p_offers_enabled, commission_percent = p_commission_percent where id = 1;
  if not found then insert into public.vip_settings(id, offers_enabled, commission_percent) values (1, p_offers_enabled, p_commission_percent); end if;
end;
$$;
revoke all on function public.vip_admin_update_settings(boolean, numeric) from public;
grant execute on function public.vip_admin_update_settings(boolean, numeric) to authenticated;

commit;
