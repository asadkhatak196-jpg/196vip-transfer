-- Transfer runtime RPCs for the current app bundle.
-- Run only AFTER confirming the existing vip_* schema is present.
-- Additive only: this migration does not delete or reset app data.

begin;

alter table public.vip_profiles add column if not exists is_available boolean not null default false;
alter table public.vip_profiles add column if not exists phone text;
alter table public.vip_profiles add column if not exists account_type text check (account_type is null or account_type in ('customer','driver'));
grant update (account_type, phone, full_name) on public.vip_profiles to authenticated;
alter table public.vip_offers add column if not exists eta_text text;
alter table public.vip_vehicles add column if not exists approved boolean not null default false;
update public.vip_vehicles v set approved=true from public.vip_driver_applications a where a.driver_id=v.driver_id and a.status='approved' and v.approved=false;
alter table public.vip_bookings add column if not exists booking_type text not null default 'Now Booking';
alter table public.vip_bookings add column if not exists pickup_latitude double precision;
alter table public.vip_bookings add column if not exists pickup_longitude double precision;
alter table public.vip_bookings alter column category drop not null;
alter table public.vip_bookings drop constraint if exists vip_bookings_status_check;
alter table public.vip_bookings add constraint vip_bookings_status_check check (status in ('open','accepted','driver_arrived','in_progress','completed','cancelled'));
alter table public.vip_settings add column if not exists comfort_price numeric(10,2) not null default 200;
alter table public.vip_settings add column if not exists business_price numeric(10,2) not null default 350;
alter table public.vip_settings add column if not exists vip_price numeric(10,2) not null default 500;
alter table public.vip_settings add column if not exists pricing_mode text not null default 'driver_offers';
alter table public.vip_settings add column if not exists offers_enabled boolean not null default true;

create table if not exists public.vip_driver_documents (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.vip_profiles(id) on delete cascade,
  document_type text not null,
  file_path text not null,
  created_at timestamptz not null default now()
);
alter table public.vip_driver_documents enable row level security;
drop policy if exists "vip driver documents owner admin" on public.vip_driver_documents;
create policy "vip driver documents owner admin" on public.vip_driver_documents for select to authenticated using (driver_id=auth.uid() or public.vip_is_admin());
drop policy if exists "vip driver documents insert own" on public.vip_driver_documents;
create policy "vip driver documents insert own" on public.vip_driver_documents for insert to authenticated with check (driver_id=auth.uid());
grant select, insert on public.vip_driver_documents to authenticated;

-- Storage buckets: public vehicle photos; private identity and licence documents.
insert into storage.buckets(id,name,public,file_size_limit)
values ('transfer-vehicle-photos','transfer-vehicle-photos',true,10485760)
on conflict (id) do update set public=true;
insert into storage.buckets(id,name,public,file_size_limit)
values ('transfer-driver-documents','transfer-driver-documents',false,15728640)
on conflict (id) do update set public=false;
drop policy if exists "Transfer vehicle photo upload own" on storage.objects;
create policy "Transfer vehicle photo upload own" on storage.objects for insert to authenticated
with check (bucket_id='transfer-vehicle-photos' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "Transfer vehicle photo owner update" on storage.objects;
create policy "Transfer vehicle photo owner update" on storage.objects for update to authenticated
using (bucket_id='transfer-vehicle-photos' and (storage.foldername(name))[1]=auth.uid()::text)
with check (bucket_id='transfer-vehicle-photos' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "Transfer vehicle photo public read" on storage.objects;
create policy "Transfer vehicle photo public read" on storage.objects for select to anon, authenticated
using (bucket_id='transfer-vehicle-photos');
drop policy if exists "Transfer documents upload own" on storage.objects;
create policy "Transfer documents upload own" on storage.objects for insert to authenticated
with check (bucket_id='transfer-driver-documents' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "Transfer documents read owner admin" on storage.objects;
create policy "Transfer documents read owner admin" on storage.objects for select to authenticated
using (bucket_id='transfer-driver-documents' and ((storage.foldername(name))[1]=auth.uid()::text or public.vip_is_admin()));


create table if not exists public.vip_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.vip_profiles(id) on delete cascade,
  sender_id uuid references public.vip_profiles(id) on delete set null,
  booking_id uuid references public.vip_bookings(id) on delete cascade,
  notification_type text not null default 'system',
  title text not null,
  body text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.vip_notifications add column if not exists sender_id uuid references public.vip_profiles(id) on delete set null;
alter table public.vip_notifications add column if not exists booking_id uuid references public.vip_bookings(id) on delete cascade;
alter table public.vip_notifications add column if not exists notification_type text not null default 'system';
alter table public.vip_notifications add column if not exists title text not null default 'Transfer update';
alter table public.vip_notifications add column if not exists body text not null default '';
alter table public.vip_notifications add column if not exists is_read boolean not null default false;
alter table public.vip_notifications add column if not exists created_at timestamptz not null default now();
create index if not exists vip_notifications_recipient_created_idx on public.vip_notifications(recipient_id, created_at desc);
alter table public.vip_notifications enable row level security;
drop policy if exists "vip notifications read own" on public.vip_notifications;
create policy "vip notifications read own" on public.vip_notifications for select to authenticated using (recipient_id = auth.uid() or public.vip_is_admin());
drop policy if exists "vip notifications update own" on public.vip_notifications;
create policy "vip notifications update own" on public.vip_notifications for update to authenticated using (recipient_id = auth.uid()) with check (recipient_id = auth.uid());
grant select, update on public.vip_notifications to authenticated;

-- Customers see offers for their own booking. Vehicle plate is hidden until the offer is accepted.
create or replace function public.vip_customer_offer_cards(p_booking_id uuid)
returns table (
  id uuid, booking_id uuid, driver_id uuid, vehicle_id uuid,
  driver_name text, vehicle_model text, vehicle_photo_url text,
  vehicle_category text, vehicle_plate text, price_sar numeric,
  eta_text text, offer_status text, created_at timestamptz
)
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.vip_bookings b where b.id = p_booking_id and b.customer_id = auth.uid()
  ) then raise exception 'Booking not found for this customer'; end if;
  return query
  select o.id, o.booking_id, o.driver_id, o.vehicle_id,
         coalesce(p.full_name, 'Transfer driver'), v.model, v.photo_url, v.category,
         case when b.accepted_offer_id = o.id then v.plate else null end,
         o.price_sar, o.eta_text, o.status, o.created_at
  from public.vip_offers o
  join public.vip_bookings b on b.id = o.booking_id
  left join public.vip_profiles p on p.id = o.driver_id
  left join public.vip_vehicles v on v.id = o.vehicle_id
  where o.booking_id = p_booking_id
    and (o.status in ('pending','accepted') or public.vip_is_admin())
  order by o.price_sar asc, o.created_at asc;
end;
$$;
revoke all on function public.vip_customer_offer_cards(uuid) from public, anon;
grant execute on function public.vip_customer_offer_cards(uuid) to authenticated;

create or replace function public.vip_set_driver_availability(p_available boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'Sign-in required'; end if;
  if not exists (select 1 from public.vip_profiles p join public.vip_driver_applications a on a.driver_id=p.id where p.id=auth.uid() and p.role='driver' and a.status='approved') then
    raise exception 'Only an approved driver can change availability';
  end if;
  update public.vip_profiles set is_available = p_available where id=auth.uid();
end;
$$;
revoke all on function public.vip_set_driver_availability(boolean) from public, anon;
grant execute on function public.vip_set_driver_availability(boolean) to authenticated;

create or replace function public.vip_cancel_booking(p_booking_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_customer uuid; v_driver uuid; v_status text;
begin
  select b.customer_id,b.status,o.driver_id into v_customer,v_status,v_driver
  from public.vip_bookings b left join public.vip_offers o on o.id=b.accepted_offer_id
  where b.id=p_booking_id for update of b;
  if not found then raise exception 'Booking not found'; end if;
  if auth.uid() is null or (auth.uid()<>v_customer and not public.vip_is_admin()) then raise exception 'Not allowed to cancel this booking'; end if;
  if v_status in ('completed','cancelled') then raise exception 'This booking can no longer be cancelled'; end if;
  update public.vip_bookings set status='cancelled' where id=p_booking_id;
  update public.vip_offers set status='rejected' where booking_id=p_booking_id and status='pending';
  if v_driver is not null then
    insert into public.vip_notifications(recipient_id,sender_id,booking_id,notification_type,title,body)
    values(v_driver,auth.uid(),p_booking_id,'booking_cancelled','Booking cancelled','The customer or administrator cancelled this booking.');
  end if;
end;
$$;
revoke all on function public.vip_cancel_booking(uuid) from public, anon;
grant execute on function public.vip_cancel_booking(uuid) to authenticated;

create or replace function public.vip_admin_cancel_offer(p_offer_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_booking uuid; v_driver uuid;
begin
  if auth.uid() is null or not public.vip_is_admin() then raise exception 'Administrator access required'; end if;
  select booking_id,driver_id into v_booking,v_driver from public.vip_offers where id=p_offer_id and status='pending' for update;
  if not found then raise exception 'Pending offer not found'; end if;
  update public.vip_offers set status='rejected' where id=p_offer_id;
  insert into public.vip_notifications(recipient_id,sender_id,booking_id,notification_type,title,body)
  values(v_driver,auth.uid(),v_booking,'offer_cancelled','Offer removed','An administrator removed your offer.');
end;
$$;
revoke all on function public.vip_admin_cancel_offer(uuid) from public, anon;
grant execute on function public.vip_admin_cancel_offer(uuid) to authenticated;

-- Customer's booking bell: notify all approved, online drivers. The function is owner-scoped.
create or replace function public.vip_customer_alert_drivers(p_booking_id uuid)
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare v_count integer;
begin
  if auth.uid() is null or not exists(select 1 from public.vip_bookings where id=p_booking_id and customer_id=auth.uid() and status='open') then
    raise exception 'Open booking not found for this customer';
  end if;
  insert into public.vip_notifications(recipient_id,sender_id,booking_id,notification_type,title,body)
  select p.id,auth.uid(),p_booking_id,'new_booking','New Transfer booking','A customer is requesting a transfer. Open Transfer to view the route and send an offer.'
  from public.vip_profiles p
  join public.vip_driver_applications a on a.driver_id=p.id and a.status='approved'
  where p.role='driver' and p.is_available=true;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function public.vip_customer_alert_drivers(uuid) from public, anon;
grant execute on function public.vip_customer_alert_drivers(uuid) to authenticated;

-- Customer-only chat bell: notify the assigned driver without exposing either phone number.
create or replace function public.vip_customer_alert_assigned_driver(p_booking_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_driver uuid;
begin
  select o.driver_id into v_driver from public.vip_bookings b join public.vip_offers o on o.id=b.accepted_offer_id
  where b.id=p_booking_id and b.customer_id=auth.uid() and b.status in ('accepted','driver_arrived','in_progress');
  if v_driver is null then raise exception 'No assigned driver found for this booking'; end if;
  insert into public.vip_notifications(recipient_id,sender_id,booking_id,notification_type,title,body)
  values(v_driver,auth.uid(),p_booking_id,'chat_alert','Customer needs your attention','The customer has sent you an alert in Transfer chat.');
end;
$$;
revoke all on function public.vip_customer_alert_assigned_driver(uuid) from public, anon;
grant execute on function public.vip_customer_alert_assigned_driver(uuid) to authenticated;

commit;
