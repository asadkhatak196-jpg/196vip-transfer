-- Transfer Driver Finance & Cash Collection
-- Additive migration: does not delete or reset existing app data or login sessions.

begin;

alter table public.vip_profiles
  add column if not exists commission_percent numeric(5,2);

do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'vip_profiles_commission_percent_check'
      and conrelid = 'public.vip_profiles'::regclass
  ) then
    alter table public.vip_profiles
      add constraint vip_profiles_commission_percent_check
      check (commission_percent is null or commission_percent in (5, 10));
  end if;
end $$;

create table if not exists public.vip_driver_ledger (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null unique references public.vip_bookings(id) on delete restrict,
  driver_id uuid not null references public.vip_profiles(id) on delete restrict,
  customer_id uuid not null references public.vip_profiles(id) on delete restrict,
  fare_sar numeric(12,2) not null check (fare_sar > 0),
  commission_percent numeric(5,2) not null check (commission_percent in (5,10)),
  commission_sar numeric(12,2) not null check (commission_sar >= 0),
  driver_net_sar numeric(12,2) not null check (driver_net_sar >= 0),
  cash_collected boolean not null,
  completed_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists vip_driver_ledger_driver_completed_idx
  on public.vip_driver_ledger(driver_id, completed_at desc);

alter table public.vip_driver_ledger enable row level security;
drop policy if exists "Driver or admin can view finance ledger" on public.vip_driver_ledger;
create policy "Driver or admin can view finance ledger"
  on public.vip_driver_ledger
  for select to authenticated
  using (driver_id = (select auth.uid()) or public.vip_is_admin());

grant select on public.vip_driver_ledger to authenticated;
revoke insert, update, delete, truncate, references, trigger on public.vip_driver_ledger from anon, authenticated;

create or replace function public.vip_admin_set_driver_commission(
  p_driver_id uuid,
  p_percent numeric
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not public.vip_is_admin() then
    raise exception 'Admin access required';
  end if;
  if p_percent not in (5,10) then
    raise exception 'Commission must be 5 or 10 percent';
  end if;
  update public.vip_profiles
     set commission_percent = p_percent
   where id = p_driver_id
     and exists (select 1 from public.vip_driver_applications a where a.driver_id = p_driver_id and a.status = 'approved');
  if not found then
    raise exception 'Driver profile not found';
  end if;
end;
$$;
revoke all on function public.vip_admin_set_driver_commission(uuid,numeric) from public, anon;
grant execute on function public.vip_admin_set_driver_commission(uuid,numeric) to authenticated;

create or replace function public.vip_update_ride_status(p_booking_id uuid, p_status text)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_driver uuid; v_customer uuid; v_old text;
begin
  if auth.uid() is null then raise exception 'Sign-in required'; end if;
  if p_status not in ('driver_arrived','in_progress') then
    raise exception 'Ride completion must use the cash collection confirmation flow';
  end if;
  select b.customer_id,b.status,o.driver_id
    into v_customer,v_old,v_driver
  from public.vip_bookings b
  left join public.vip_offers o on o.id=b.accepted_offer_id
  where b.id=p_booking_id for update of b;
  if not found then raise exception 'Booking not found'; end if;
  if not public.vip_is_admin() and auth.uid()<>v_driver then
    raise exception 'Only the assigned driver or Admin can update this ride';
  end if;
  if (v_old='accepted' and p_status<>'driver_arrived')
     or (v_old='driver_arrived' and p_status<>'in_progress') then
    raise exception 'Ride status must follow: accepted → driver arrived → in progress → completed';
  end if;
  update public.vip_bookings set status=p_status where id=p_booking_id;
  insert into public.vip_notifications(recipient_id,sender_id,booking_id,notification_type,title,body)
  values(v_customer,auth.uid(),p_booking_id,'ride_status','Ride status updated',replace(p_status,'_',' '));
  return true;
end;
$$;
revoke all on function public.vip_update_ride_status(uuid,text) from public, anon;
grant execute on function public.vip_update_ride_status(uuid,text) to authenticated;

create or replace function public.vip_complete_ride(
  p_booking_id uuid,
  p_cash_collected boolean
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_driver_id uuid;
  v_customer_id uuid;
  v_status text;
  v_offer_id uuid;
  v_fare numeric(12,2);
  v_percent numeric(5,2);
  v_commission numeric(12,2);
  v_net numeric(12,2);
begin
  if auth.uid() is null then
    raise exception 'Sign-in required';
  end if;

  select b.customer_id, b.status, b.accepted_offer_id, o.driver_id, o.price_sar
    into v_customer_id, v_status, v_offer_id, v_driver_id, v_fare
  from public.vip_bookings b
  left join public.vip_offers o on o.id = b.accepted_offer_id
  where b.id = p_booking_id
  for update of b;

  if not found or v_offer_id is null or v_driver_id is null then
    raise exception 'Accepted booking or driver offer not found';
  end if;
  if not public.vip_is_admin() and auth.uid() <> v_driver_id then
    raise exception 'Only the assigned driver or Admin can complete this ride';
  end if;
  if v_status <> 'in_progress' then
    raise exception 'Ride must be in progress before completion';
  end if;

  select commission_percent into v_percent
  from public.vip_profiles
  where id = v_driver_id
    and exists (select 1 from public.vip_driver_applications a where a.driver_id = v_driver_id and a.status = 'approved');
  if v_percent not in (5,10) then
    raise exception 'Admin must assign this driver a 5% or 10% commission before completing the ride';
  end if;

  v_commission := round(v_fare * v_percent / 100.0, 2);
  v_net := v_fare - v_commission;

  insert into public.vip_driver_ledger(
    booking_id, driver_id, customer_id, fare_sar,
    commission_percent, commission_sar, driver_net_sar, cash_collected
  ) values (
    p_booking_id, v_driver_id, v_customer_id, v_fare,
    v_percent, v_commission, v_net, p_cash_collected
  ) on conflict (booking_id) do nothing;

  update public.vip_bookings set status = 'completed' where id = p_booking_id;

  insert into public.vip_notifications(
    recipient_id, sender_id, booking_id, notification_type, title, body
  ) values (
    v_customer_id, auth.uid(), p_booking_id, 'ride_status', 'Ride completed',
    case when p_cash_collected then 'Ride completed. Cash was collected.'
         else 'Ride completed. Cash has not yet been collected.' end
  );
end;
$$;
revoke all on function public.vip_complete_ride(uuid,boolean) from public, anon;
grant execute on function public.vip_complete_ride(uuid,boolean) to authenticated;

commit;
