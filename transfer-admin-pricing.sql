-- Admin fixed-price and override offer workflows.
-- Apply after transfer-runtime-rpcs.sql and transfer-security-fixes.sql.
begin;

-- Driver offers are disabled in admin_fixed mode and allowed in driver_offers/both.
drop policy if exists "vip offers create approved online driver" on public.vip_offers;
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
  and exists (
    select 1 from public.vip_settings s
    where s.id=1 and s.offers_enabled=true and s.pricing_mode in ('driver_offers','both')
  )
);

create or replace function public.vip_admin_create_fixed_offer(
  p_booking_id uuid,
  p_driver_id uuid,
  p_price numeric
) returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_vehicle_id uuid; v_offer_id uuid; v_customer_id uuid;
begin
  if auth.uid() is null or not public.vip_is_admin() then raise exception 'Administrator access required'; end if;
  if p_price is null or p_price<=0 then raise exception 'Offer price must be greater than zero'; end if;
  select b.customer_id into v_customer_id from public.vip_bookings b
   where b.id=p_booking_id and b.status='open' for update;
  if v_customer_id is null then raise exception 'Open booking not found'; end if;
  select v.id into v_vehicle_id from public.vip_vehicles v
   join public.vip_driver_applications a on a.driver_id=v.driver_id
   join public.vip_profiles p on p.id=v.driver_id
   where v.driver_id=p_driver_id and v.approved=true
     and a.status='approved' and p.role='driver'
   order by v.created_at desc limit 1;
  if v_vehicle_id is null then raise exception 'Selected driver has no approved vehicle'; end if;
  select id into v_offer_id from public.vip_offers
   where booking_id=p_booking_id and driver_id=p_driver_id and status='pending'
   for update;
  if v_offer_id is null then
    insert into public.vip_offers(booking_id,driver_id,vehicle_id,price_sar,status)
    values(p_booking_id,p_driver_id,v_vehicle_id,p_price,'pending') returning id into v_offer_id;
  else
    update public.vip_offers set vehicle_id=v_vehicle_id,price_sar=p_price,eta_text='Admin fixed offer'
     where id=v_offer_id;
  end if;
  insert into public.vip_notifications(recipient_id,sender_id,booking_id,notification_type,title,body)
  values(p_driver_id,auth.uid(),p_booking_id,'admin_fixed_offer','Admin fixed-price offer','Admin has prepared a fixed-price offer for this booking.');
  insert into public.vip_notifications(recipient_id,sender_id,booking_id,notification_type,title,body)
  values(v_customer_id,auth.uid(),p_booking_id,'admin_fixed_offer','New Transfer price offer','An administrator has added a fixed-price driver offer to your booking.');
  return v_offer_id;
end;
$$;
revoke all on function public.vip_admin_create_fixed_offer(uuid,uuid,numeric) from public,anon;
grant execute on function public.vip_admin_create_fixed_offer(uuid,uuid,numeric) to authenticated;

create or replace function public.vip_admin_set_offer_price(
  p_offer_id uuid,
  p_price numeric
) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_driver uuid; v_booking uuid;
begin
  if auth.uid() is null or not public.vip_is_admin() then raise exception 'Administrator access required'; end if;
  if p_price is null or p_price<=0 then raise exception 'Offer price must be greater than zero'; end if;
  select driver_id,booking_id into v_driver,v_booking from public.vip_offers
   where id=p_offer_id and status='pending' for update;
  if v_driver is null then raise exception 'Pending offer not found'; end if;
  update public.vip_offers set price_sar=p_price,eta_text=coalesce(eta_text,'Admin price override') where id=p_offer_id;
  insert into public.vip_notifications(recipient_id,sender_id,booking_id,notification_type,title,body)
  values(v_driver,auth.uid(),v_booking,'admin_price_override','Offer price updated','Admin changed the price of your pending offer.');
end;
$$;
revoke all on function public.vip_admin_set_offer_price(uuid,numeric) from public,anon;
grant execute on function public.vip_admin_set_offer_price(uuid,numeric) to authenticated;

commit;
