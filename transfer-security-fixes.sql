-- Transfer privacy hardening. Apply after base-setup.sql and existing runtime migrations.
-- Prevent direct table reads from revealing vehicle plates before offer acceptance.
-- Require an accepted booking before either participant can access chat messages.

begin;

-- Vehicle information is private until a customer accepts that driver's offer.
drop policy if exists "vip vehicles read" on public.vip_vehicles;
create policy "vip vehicles read owner admin accepted customer"
on public.vip_vehicles for select to authenticated
using (
  driver_id = auth.uid()
  or public.vip_is_admin()
  or exists (
    select 1
    from public.vip_offers o
    join public.vip_bookings b on b.id=o.booking_id
    where o.vehicle_id=vip_vehicles.id
      and o.driver_id=vip_vehicles.driver_id
      and o.status='accepted'
      and b.accepted_offer_id=o.id
      and b.customer_id=auth.uid()
  )
);

-- A customer can no longer read/send messages before an offer is accepted.
drop policy if exists "vip messages read booking participants" on public.vip_messages;
create policy "vip messages read accepted booking participants"
on public.vip_messages for select to authenticated
using (
  public.vip_is_admin()
  or exists (
    select 1 from public.vip_bookings b
    where b.id=booking_id and b.customer_id=auth.uid()
      and b.accepted_offer_id is not null
      and b.status in ('accepted','driver_arrived','in_progress','completed')
  )
  or exists (
    select 1 from public.vip_offers o
    join public.vip_bookings b on b.id=o.booking_id
    where o.booking_id=vip_messages.booking_id
      and o.driver_id=auth.uid() and o.status='accepted'
      and b.accepted_offer_id=o.id
      and b.status in ('accepted','driver_arrived','in_progress','completed')
  )
);

drop policy if exists "vip messages send participants" on public.vip_messages;
create policy "vip messages send accepted booking participants"
on public.vip_messages for insert to authenticated
with check (
  sender_id=auth.uid()
  and (
    public.vip_is_admin()
    or exists (
      select 1 from public.vip_bookings b
      where b.id=booking_id and b.customer_id=auth.uid()
        and b.accepted_offer_id is not null
        and b.status in ('accepted','driver_arrived','in_progress','completed')
    )
    or exists (
      select 1 from public.vip_offers o
      join public.vip_bookings b on b.id=o.booking_id
      where o.booking_id=vip_messages.booking_id
        and o.driver_id=auth.uid() and o.status='accepted'
        and b.accepted_offer_id=o.id
        and b.status in ('accepted','driver_arrived','in_progress','completed')
    )
  )
);


-- Drivers may create offers only while approved, online, offers are enabled,
-- and the referenced vehicle is approved and owned by that driver.
drop policy if exists "vip offers create approved driver" on public.vip_offers;
create policy "vip offers create approved online driver"
on public.vip_offers for insert to authenticated
with check (
  driver_id=auth.uid()
  and exists (
    select 1 from public.vip_profiles p
    join public.vip_driver_applications a on a.driver_id=p.id
    where p.id=auth.uid() and p.role='driver'
      and p.is_available=true and a.status='approved'
  )
  and exists (
    select 1 from public.vip_vehicles v
    where v.id=vehicle_id and v.driver_id=auth.uid() and v.approved=true
  )
  and exists (
    select 1 from public.vip_bookings b
    where b.id=booking_id and b.status='open'
  )
  and exists (select 1 from public.vip_settings s where s.id=1 and s.offers_enabled=true)
);

-- Keep an existing offer editable only while the driver remains approved and online.
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
  if not exists (
    select 1 from public.vip_profiles p
    join public.vip_driver_applications a on a.driver_id=p.id
    join public.vip_settings s on s.id=1
    where p.id=auth.uid() and p.role='driver' and p.is_available=true
      and a.status='approved' and s.offers_enabled=true and s.pricing_mode in ('driver_offers','both')
  ) then raise exception 'Only an approved online driver can edit an offer while offers are enabled'; end if;
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

-- Notify the selected driver when the customer accepts the offer.
create or replace function public.vip_accept_offer(p_offer_id uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_booking_id uuid; v_driver_id uuid; v_customer_id uuid;
begin
  select o.booking_id,o.driver_id,b.customer_id
    into v_booking_id,v_driver_id,v_customer_id
  from public.vip_offers o
  join public.vip_bookings b on b.id=o.booking_id
  where o.id=p_offer_id and b.customer_id=auth.uid()
    and b.status='open' and o.status='pending'
  for update of b;
  if v_booking_id is null then raise exception 'Offer not found or booking is not available to this customer'; end if;
  update public.vip_offers
     set status=case when id=p_offer_id then 'accepted' else 'rejected' end
   where booking_id=v_booking_id;
  update public.vip_bookings
     set status='accepted',accepted_offer_id=p_offer_id
   where id=v_booking_id;
  insert into public.vip_notifications(recipient_id,sender_id,booking_id,notification_type,title,body)
  values(v_driver_id,auth.uid(),v_booking_id,'offer_accepted','Your offer was accepted','The customer accepted your price. Open Transfer to view the booking and chat.');
end;
$$;
revoke all on function public.vip_accept_offer(uuid) from public, anon;
grant execute on function public.vip_accept_offer(uuid) to authenticated;

commit;
