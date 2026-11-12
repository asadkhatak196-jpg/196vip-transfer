-- VIP Transfer: additive Supabase setup.
-- Uses auth.users UUIDs and vip_-prefixed tables to avoid overwriting your existing tables.
-- Run only after reviewing this file. Never expose service_role keys.

create table if not exists public.vip_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text,
  role text not null default 'customer' check (role in ('customer','driver','admin')),
  driver_icon text,
  created_at timestamptz not null default now()
);
create table if not exists public.vip_driver_applications (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null unique references public.vip_profiles(id) on delete cascade,
  vehicle_category text not null default 'Comfort' check (vehicle_category in ('Comfort','Business','VIP')),
  vehicle_model text not null,
  vehicle_year integer,
  vehicle_plate text,
  vehicle_photo_url text,
  notes text,
  status text not null default 'pending' check (status in ('pending','approved','disabled')),
  created_at timestamptz not null default now()
);
create table if not exists public.vip_bookings (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.vip_profiles(id),
  pickup text not null,
  destination text not null,
  pickup_at timestamptz,
  category text not null check (category in ('Comfort','Business','VIP')),
  passengers integer not null default 1 check (passengers between 1 and 20),
  notes text,
  status text not null default 'open' check (status in ('open','accepted','completed','cancelled')),
  accepted_offer_id uuid,
  created_at timestamptz not null default now()
);
create table if not exists public.vip_vehicles (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.vip_profiles(id) on delete cascade,
  category text not null check (category in ('Comfort','Business','VIP')),
  model text not null,
  plate text,
  photo_url text,
  created_at timestamptz not null default now()
);
create table if not exists public.vip_offers (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.vip_bookings(id) on delete cascade,
  driver_id uuid not null references public.vip_profiles(id),
  vehicle_id uuid references public.vip_vehicles(id),
  price_sar numeric(10,2) not null check (price_sar > 0),
  status text not null default 'pending' check (status in ('pending','accepted','rejected')),
  created_at timestamptz not null default now(),
  unique(booking_id,driver_id)
);
alter table public.vip_bookings drop constraint if exists vip_bookings_accepted_offer_id_fkey;
alter table public.vip_bookings add constraint vip_bookings_accepted_offer_id_fkey
 foreign key (accepted_offer_id) references public.vip_offers(id) on delete set null;
create table if not exists public.vip_messages (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.vip_bookings(id) on delete cascade,
  sender_id uuid not null references public.vip_profiles(id),
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);
create table if not exists public.vip_settings (
  id integer primary key default 1 check (id=1),
  offers_enabled boolean not null default true,
  pricing_mode text not null default 'driver_offers' check (pricing_mode in ('driver_offers','admin_fixed','both'))
);
insert into public.vip_settings(id) values (1) on conflict do nothing;

-- Create a basic profile after email sign-up. New accounts always start as customers.
create or replace function public.vip_handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
 insert into public.vip_profiles(id,email,full_name,role)
 values(new.id,new.email,coalesce(new.raw_user_meta_data->>'full_name',''),'customer')
 on conflict(id) do nothing;
 return new;
end; $$;
drop trigger if exists vip_on_auth_user_created on auth.users;
create trigger vip_on_auth_user_created after insert on auth.users
for each row execute procedure public.vip_handle_new_user();

alter table public.vip_profiles enable row level security;
alter table public.vip_driver_applications enable row level security;
alter table public.vip_bookings enable row level security;
alter table public.vip_vehicles enable row level security;
alter table public.vip_offers enable row level security;
alter table public.vip_messages enable row level security;
alter table public.vip_settings enable row level security;

create or replace function public.vip_is_admin()
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.vip_profiles p where p.id=auth.uid() and p.role='admin'); $$;

drop policy if exists "vip profile read self or admin" on public.vip_profiles;
create policy "vip profile read self or admin" on public.vip_profiles for select to authenticated
using (id=auth.uid() or public.vip_is_admin());
drop policy if exists "vip profile insert self customer" on public.vip_profiles;
create policy "vip profile insert self customer" on public.vip_profiles for insert to authenticated
with check (id=auth.uid() and role='customer');
drop policy if exists "vip profile update self or admin" on public.vip_profiles;
create policy "vip profile update self or admin" on public.vip_profiles for update to authenticated
using (id=auth.uid() or public.vip_is_admin())
with check ((id=auth.uid() and role in ('customer','driver')) or public.vip_is_admin());

drop policy if exists "vip application read own admin" on public.vip_driver_applications;
create policy "vip application read own admin" on public.vip_driver_applications for select to authenticated
using (driver_id=auth.uid() or public.vip_is_admin());
drop policy if exists "vip application create own" on public.vip_driver_applications;
create policy "vip application create own" on public.vip_driver_applications for insert to authenticated
with check (driver_id=auth.uid() and status='pending');
drop policy if exists "vip application update admin" on public.vip_driver_applications;
create policy "vip application update admin" on public.vip_driver_applications for update to authenticated
using (public.vip_is_admin()) with check (public.vip_is_admin());

drop policy if exists "vip bookings read participants" on public.vip_bookings;
create policy "vip bookings read participants" on public.vip_bookings for select to authenticated
using (customer_id=auth.uid() or public.vip_is_admin() or exists(select 1 from public.vip_offers o where o.booking_id=id and o.driver_id=auth.uid()));
drop policy if exists "vip bookings create customer" on public.vip_bookings;
create policy "vip bookings create customer" on public.vip_bookings for insert to authenticated
with check (customer_id=auth.uid());
drop policy if exists "vip bookings update customer admin" on public.vip_bookings;
create policy "vip bookings update customer admin" on public.vip_bookings for update to authenticated
using (customer_id=auth.uid() or public.vip_is_admin())
with check (customer_id=auth.uid() or public.vip_is_admin());

drop policy if exists "vip vehicles read" on public.vip_vehicles;
create policy "vip vehicles read" on public.vip_vehicles for select to authenticated using (true);
drop policy if exists "vip vehicles manage own admin" on public.vip_vehicles;
create policy "vip vehicles manage own admin" on public.vip_vehicles for all to authenticated
using (driver_id=auth.uid() or public.vip_is_admin()) with check (driver_id=auth.uid() or public.vip_is_admin());

drop policy if exists "vip offers read participants" on public.vip_offers;
create policy "vip offers read participants" on public.vip_offers for select to authenticated
using (driver_id=auth.uid() or public.vip_is_admin() or exists(select 1 from public.vip_bookings b where b.id=booking_id and b.customer_id=auth.uid()));
drop policy if exists "vip offers create approved driver" on public.vip_offers;
create policy "vip offers create approved driver" on public.vip_offers for insert to authenticated
with check (driver_id=auth.uid() and exists(select 1 from public.vip_driver_applications a where a.driver_id=auth.uid() and a.status='approved') and exists(select 1 from public.vip_settings s where s.id=1 and s.offers_enabled));
drop policy if exists "vip offers update participant" on public.vip_offers;
create policy "vip offers update participant" on public.vip_offers for update to authenticated
using (driver_id=auth.uid() or public.vip_is_admin() or exists(select 1 from public.vip_bookings b where b.id=booking_id and b.customer_id=auth.uid()))
with check (driver_id=auth.uid() or public.vip_is_admin() or exists(select 1 from public.vip_bookings b where b.id=booking_id and b.customer_id=auth.uid()));

drop policy if exists "vip messages read booking participants" on public.vip_messages;
create policy "vip messages read booking participants" on public.vip_messages for select to authenticated
using (sender_id=auth.uid() or public.vip_is_admin() or exists(select 1 from public.vip_bookings b where b.id=booking_id and b.customer_id=auth.uid()) or exists(select 1 from public.vip_offers o where o.booking_id=booking_id and o.driver_id=auth.uid() and o.status='accepted'));
drop policy if exists "vip messages send participants" on public.vip_messages;
create policy "vip messages send participants" on public.vip_messages for insert to authenticated
with check (sender_id=auth.uid() and (public.vip_is_admin() or exists(select 1 from public.vip_bookings b where b.id=booking_id and b.customer_id=auth.uid()) or exists(select 1 from public.vip_offers o where o.booking_id=booking_id and o.driver_id=auth.uid() and o.status='accepted')));

drop policy if exists "vip settings read authenticated" on public.vip_settings;
create policy "vip settings read authenticated" on public.vip_settings for select to authenticated using (true);
drop policy if exists "vip settings update admin" on public.vip_settings;
create policy "vip settings update admin" on public.vip_settings for update to authenticated
using (public.vip_is_admin()) with check (public.vip_is_admin());

-- IMPORTANT: after creating your own account, make it admin manually in SQL Editor:
-- update public.vip_profiles set role='admin' where email='YOUR_ADMIN_EMAIL';
-- Driver role is assigned by admin after reviewing a driver application:
-- update public.vip_profiles set role='driver' where id='DRIVER_AUTH_USER_UUID';
-- These manual admin actions avoid allowing users to promote themselves.
