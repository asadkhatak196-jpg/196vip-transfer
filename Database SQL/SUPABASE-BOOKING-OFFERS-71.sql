-- Transfer Build 71: live bookings, driver offers, pricing controls and realtime.
-- This additive migration was applied to the connected Transfer project on 2026-11-08.
-- Re-running is intended to be safe; do not remove existing tables or data.

begin;

create or replace function public.transfer_handle_new_auth_user()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
  insert into public.vip_profiles (id,email,full_name,role,is_available,account_type)
  values (new.id,lower(coalesce(new.email,'')),left(coalesce(new.raw_user_meta_data->>'full_name',''),120),'customer',false,null)
  on conflict (id) do nothing;
  return new;
end; $$;
drop trigger if exists transfer_auth_user_profile on auth.users;
create trigger transfer_auth_user_profile after insert on auth.users
for each row execute function public.transfer_handle_new_auth_user();

alter table public.vip_bookings add column if not exists booking_type text not null default 'Now Booking';
alter table public.vip_bookings alter column category drop not null;
alter table public.vip_offers add column if not exists eta_text text;
do $$ begin
 if not exists(select 1 from pg_constraint where conname='vip_bookings_booking_type_check' and conrelid='public.vip_bookings'::regclass) then
  alter table public.vip_bookings add constraint vip_bookings_booking_type_check check(booking_type in ('Now Booking','Later Booking','Airport Transfer'));
 end if;
end $$;

drop policy if exists "vip offers create approved driver" on public.vip_offers;
create policy "vip offers create approved driver" on public.vip_offers for insert to authenticated
with check (
 driver_id=(select auth.uid()) and status='pending'
 and exists(select 1 from public.vip_profiles p join public.vip_driver_applications a on a.driver_id=p.id
  where p.id=(select auth.uid()) and p.role='driver' and p.is_available and a.status='approved')
 and exists(select 1 from public.vip_bookings b where b.id=booking_id and b.status='open')
 and exists(select 1 from public.vip_settings s where s.id=1 and s.offers_enabled)
 and (vehicle_id is null or exists(select 1 from public.vip_vehicles v where v.id=vehicle_id and v.driver_id=(select auth.uid())))
);

create or replace function public.vip_set_driver_availability(p_available boolean)
returns boolean language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if auth.uid() is null then raise exception 'Sign-in required'; end if;
 if not exists(select 1 from public.vip_profiles where id=auth.uid() and role='driver') then raise exception 'Driver account is not approved'; end if;
 if p_available and not exists(select 1 from public.vip_driver_applications where driver_id=auth.uid() and status='approved') then raise exception 'Driver application must be approved before going online'; end if;
 update public.vip_profiles set is_available=p_available where id=auth.uid();
 return p_available;
end; $$;

create or replace function public.vip_customer_offer_cards(p_booking_id uuid)
returns table(offer_id uuid,booking_id uuid,driver_id uuid,vehicle_id uuid,price_sar numeric,offer_status text,created_at timestamptz,eta_text text,vehicle_model text,vehicle_category text,vehicle_photo_url text,driver_name text,vehicle_plate text)
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 if auth.uid() is null then raise exception 'Sign-in required'; end if;
 if not exists(select 1 from public.vip_bookings b where b.id=p_booking_id and b.customer_id=auth.uid()) then raise exception 'Booking not found for this customer'; end if;
 return query select o.id,o.booking_id,o.driver_id,o.vehicle_id,o.price_sar,o.status,o.created_at,o.eta_text,
  coalesce(v.model,a.vehicle_model),coalesce(v.category,a.vehicle_category),coalesce(v.photo_url,a.vehicle_photo_url),p.full_name,
  case when o.status='accepted' then coalesce(v.plate,a.vehicle_plate) else null end
 from public.vip_offers o left join public.vip_vehicles v on v.id=o.vehicle_id and v.driver_id=o.driver_id
 left join public.vip_driver_applications a on a.driver_id=o.driver_id left join public.vip_profiles p on p.id=o.driver_id
 where o.booking_id=p_booking_id and o.status in ('pending','accepted')
 order by case when o.status='accepted' then 0 else 1 end,o.price_sar asc,o.created_at asc;
end; $$;

create or replace function public.vip_accept_offer(p_booking_id uuid,p_offer_id uuid)
returns boolean language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if auth.uid() is null then raise exception 'Sign-in required'; end if;
 if not exists(select 1 from public.vip_bookings where id=p_booking_id and customer_id=auth.uid() and status='open') then raise exception 'This booking is not open or does not belong to you'; end if;
 if not exists(select 1 from public.vip_offers where id=p_offer_id and booking_id=p_booking_id and status='pending') then raise exception 'This offer is no longer available'; end if;
 update public.vip_offers set status='rejected' where booking_id=p_booking_id and status='pending' and id<>p_offer_id;
 update public.vip_offers set status='accepted' where id=p_offer_id and booking_id=p_booking_id;
 update public.vip_bookings set status='accepted',accepted_offer_id=p_offer_id where id=p_booking_id and customer_id=auth.uid();
 return true;
end; $$;

create or replace function public.vip_cancel_booking(p_booking_id uuid)
returns boolean language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if auth.uid() is null then raise exception 'Sign-in required'; end if;
 update public.vip_bookings set status='cancelled' where id=p_booking_id and status in ('open','accepted') and (customer_id=auth.uid() or public.vip_is_admin());
 if not found then raise exception 'Booking not found or cannot be cancelled'; end if;
 update public.vip_offers set status='rejected' where booking_id=p_booking_id and status='pending';
 return true;
end; $$;

create or replace function public.vip_admin_set_driver_status(p_driver_id uuid,p_status text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if auth.uid() is null or not public.vip_is_admin() then raise exception 'Administrator access required'; end if;
 if p_status not in ('approved','disabled','pending') then raise exception 'Invalid driver status'; end if;
 update public.vip_driver_applications set status=p_status where driver_id=p_driver_id;
 if not found then raise exception 'Driver application not found'; end if;
 update public.vip_profiles set role=case when p_status='approved' then 'driver' else 'customer' end,
   account_type=case when p_status='approved' then 'driver' else 'customer' end,
   is_available=false where id=p_driver_id;
 update public.vip_vehicles set approved=(p_status='approved') where driver_id=p_driver_id;
end; $$;

revoke all on function public.vip_set_driver_availability(boolean) from public,anon;
revoke all on function public.vip_customer_offer_cards(uuid) from public,anon;
revoke all on function public.vip_accept_offer(uuid,uuid) from public,anon;
revoke all on function public.vip_cancel_booking(uuid) from public,anon;
revoke all on function public.vip_admin_set_driver_status(uuid,text) from public,anon;
grant execute on function public.vip_set_driver_availability(boolean) to authenticated;
grant execute on function public.vip_customer_offer_cards(uuid) to authenticated;
grant execute on function public.vip_accept_offer(uuid,uuid) to authenticated;
grant execute on function public.vip_cancel_booking(uuid) to authenticated;
grant execute on function public.vip_admin_set_driver_status(uuid,text) to authenticated;

do $$ declare t text; begin
 foreach t in array array['vip_bookings','vip_offers','vip_settings','vip_driver_applications','vip_profiles'] loop
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
   execute format('alter publication supabase_realtime add table public.%I',t);
  end if;
 end loop;
end $$;
commit;
