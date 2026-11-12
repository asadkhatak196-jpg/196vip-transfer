-- Transfer runtime compatibility fixes (additive and re-runnable).
-- Apply after base-setup.sql, transfer-runtime-rpcs.sql and driver-finance.sql.
begin;

-- Allow a driver to finish/edit their own pending application before approval.
drop policy if exists "vip application owner update pending" on public.vip_driver_applications;
create policy "vip application owner update pending"
on public.vip_driver_applications for update to authenticated
using (driver_id = auth.uid() and status = 'pending')
with check (driver_id = auth.uid() and status = 'pending');
grant update (vehicle_category, vehicle_model, vehicle_year, vehicle_plate, vehicle_photo_url, notes) on public.vip_driver_applications to authenticated;

-- Offer edits are performed through a security-definer RPC because direct UPDATE
-- on offers is intentionally revoked from browser clients.
create or replace function public.vip_driver_update_offer(
  p_offer_id uuid,
  p_price numeric,
  p_eta text default null
) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_booking uuid;
begin
  if auth.uid() is null then raise exception 'Sign-in required'; end if;
  if p_price is null or p_price <= 0 then raise exception 'Offer price must be greater than zero'; end if;
  select o.booking_id into v_booking
  from public.vip_offers o
  join public.vip_bookings b on b.id=o.booking_id
  where o.id=p_offer_id and o.driver_id=auth.uid()
    and o.status='pending' and b.status='open'
  for update of o;
  if v_booking is null then raise exception 'Pending offer not found or booking is closed'; end if;
  update public.vip_offers set price_sar=p_price, eta_text=nullif(trim(p_eta), '')
  where id=p_offer_id;
end;
$$;
revoke all on function public.vip_driver_update_offer(uuid,numeric,text) from public, anon;
grant execute on function public.vip_driver_update_offer(uuid,numeric,text) to authenticated;

commit;
