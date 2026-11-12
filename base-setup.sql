-- 196 VIP Transfer - Supabase database setup
-- Safe additive setup: creates only vip_* tables and policies.
-- It does NOT delete or rename your existing tables.
-- Run this in Supabase SQL Editor while connected to the correct project.
-- Never put a service_role key in website/mobile app code.

begin;

create table if not exists public.vip_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text,
  role text not null default 'customer'
    check (role in ('customer','driver','admin')),
  driver_icon text,
  created_at timestamptz not null default now()
);

create table if not exists public.vip_driver_applications (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null unique references public.vip_profiles(id) on delete cascade,
  vehicle_category text not null default 'Comfort'
    check (vehicle_category in ('Comfort','Business','VIP')),
  vehicle_model text not null,
  vehicle_year integer,
  vehicle_plate text,
  vehicle_photo_url text,
  notes text,
  status text not null default 'pending'
    check (status in ('pending','approved','disabled')),
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
  status text not null default 'open'
    check (status in ('open','accepted','completed','cancelled')),
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
  status text not null default 'pending'
    check (status in ('pending','accepted','rejected')),
  created_at timestamptz not null default now(),
  unique (booking_id, driver_id)
);

alter table public.vip_bookings
  drop constraint if exists vip_bookings_accepted_offer_id_fkey;
alter table public.vip_bookings
  add constraint vip_bookings_accepted_offer_id_fkey
  foreign key (accepted_offer_id) references public.vip_offers(id) on delete set null;

create table if not exists public.vip_messages (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.vip_bookings(id) on delete cascade,
  sender_id uuid not null references public.vip_profiles(id),
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);

create table if not exists public.vip_settings (
  id integer primary key default 1 check (id = 1),
  offers_enabled boolean not null default true,
  pricing_mode text not null default 'driver_offers'
    check (pricing_mode in ('driver_offers','admin_fixed','both'))
);

insert into public.vip_settings(id) values (1) on conflict (id) do nothing;

-- Automatically create a customer profile for each newly registered auth user.
create or replace function public.vip_handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.vip_profiles (id, email, full_name, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    'customer'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists vip_on_auth_user_created on auth.users;
create trigger vip_on_auth_user_created
after insert on auth.users
for each row execute procedure public.vip_handle_new_user();

-- Admin check. Users cannot make themselves admins through the app.
create or replace function public.vip_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.vip_profiles p
    where p.id = auth.uid() and p.role = 'admin'
  );
$$;

-- Turn on row-level security for every new table.
alter table public.vip_profiles enable row level security;
alter table public.vip_driver_applications enable row level security;
alter table public.vip_bookings enable row level security;
alter table public.vip_vehicles enable row level security;
alter table public.vip_offers enable row level security;
alter table public.vip_messages enable row level security;
alter table public.vip_settings enable row level security;

-- Remove policies from an earlier version of this VIP setup before recreating them.
drop policy if exists "vip profile read self or admin" on public.vip_profiles;
drop policy if exists "vip profile insert self customer" on public.vip_profiles;
drop policy if exists "vip profile update self or admin" on public.vip_profiles;
drop policy if exists "vip application read own admin" on public.vip_driver_applications;
drop policy if exists "vip application create own" on public.vip_driver_applications;
drop policy if exists "vip application update admin" on public.vip_driver_applications;
drop policy if exists "vip bookings read participants" on public.vip_bookings;
drop policy if exists "vip bookings create customer" on public.vip_bookings;
drop policy if exists "vip bookings update customer admin" on public.vip_bookings;
drop policy if exists "vip vehicles read" on public.vip_vehicles;
drop policy if exists "vip vehicles manage own admin" on public.vip_vehicles;
drop policy if exists "vip offers read participants" on public.vip_offers;
drop policy if exists "vip offers create approved driver" on public.vip_offers;
drop policy if exists "vip offers update participant" on public.vip_offers;
drop policy if exists "vip messages read booking participants" on public.vip_messages;
drop policy if exists "vip messages send participants" on public.vip_messages;
drop policy if exists "vip settings read authenticated" on public.vip_settings;
drop policy if exists "vip settings update admin" on public.vip_settings;

-- Profiles: users can read their own profile; admins can read all.
create policy "vip profile read self or admin"
on public.vip_profiles for select to authenticated
using (id = auth.uid() or public.vip_is_admin());

-- Profile editing is deliberately limited to harmless profile fields.
-- Role changes (driver/admin) are performed by an administrator, not by the user.
revoke all on public.vip_profiles from anon, authenticated;
grant select on public.vip_profiles to authenticated;
grant update (full_name, driver_icon) on public.vip_profiles to authenticated;

-- Driver applications: applicants see/create their own; admins can review/update all.
create policy "vip application read own admin"
on public.vip_driver_applications for select to authenticated
using (driver_id = auth.uid() or public.vip_is_admin());

create policy "vip application create own"
on public.vip_driver_applications for insert to authenticated
with check (
  driver_id = auth.uid()
  and status = 'pending'
  and exists (
    select 1 from public.vip_profiles p
    where p.id = auth.uid() and p.role = 'customer'
  )
);

create policy "vip application update admin"
on public.vip_driver_applications for update to authenticated
using (public.vip_is_admin())
with check (public.vip_is_admin());

-- Bookings: customers create their own; only the customer and admin can view.
create policy "vip bookings read participants"
on public.vip_bookings for select to authenticated
using (
  customer_id = auth.uid()
  or public.vip_is_admin()
  or exists (
    select 1 from public.vip_offers o
    where o.booking_id = id and o.driver_id = auth.uid()
  )
);

create policy "vip bookings create customer"
on public.vip_bookings for insert to authenticated
with check (
  customer_id = auth.uid()
  and status = 'open'
  and accepted_offer_id is null
);

-- Vehicles: signed-in users can see vehicle details; owners/admins can manage.
create policy "vip vehicles read"
on public.vip_vehicles for select to authenticated
using (true);

create policy "vip vehicles manage own admin"
on public.vip_vehicles for all to authenticated
using (driver_id = auth.uid() or public.vip_is_admin())
with check (driver_id = auth.uid() or public.vip_is_admin());

-- Offers: participants can view. Only approved, enabled drivers can create offers.
create policy "vip offers read participants"
on public.vip_offers for select to authenticated
using (
  driver_id = auth.uid()
  or public.vip_is_admin()
  or exists (
    select 1 from public.vip_bookings b
    where b.id = booking_id and b.customer_id = auth.uid()
  )
);

create policy "vip offers create approved driver"
on public.vip_offers for insert to authenticated
with check (
  driver_id = auth.uid()
  and exists (
    select 1 from public.vip_profiles p
    where p.id = auth.uid() and p.role = 'driver'
  )
  and exists (
    select 1 from public.vip_driver_applications a
    where a.driver_id = auth.uid() and a.status = 'approved'
  )
  and exists (
    select 1 from public.vip_bookings b
    where b.id = booking_id and b.status = 'open'
  )
  and exists (
    select 1 from public.vip_settings s
    where s.id = 1 and s.offers_enabled = true
  )
);

-- Do not grant direct offer updates. Customers accept through the secure function below.
revoke update, delete on public.vip_offers from anon, authenticated;
grant select, insert on public.vip_offers to authenticated;

-- Securely accept one offer for the signed-in booking owner.
create or replace function public.vip_accept_offer(p_offer_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking_id uuid;
begin
  select o.booking_id into v_booking_id
  from public.vip_offers o
  join public.vip_bookings b on b.id = o.booking_id
  where o.id = p_offer_id
    and b.customer_id = auth.uid()
    and b.status = 'open'
    and o.status = 'pending'
  for update of b;

  if v_booking_id is null then
    raise exception 'Offer not found or booking is not available to this customer';
  end if;

  update public.vip_offers
  set status = case when id = p_offer_id then 'accepted' else 'rejected' end
  where booking_id = v_booking_id;

  update public.vip_bookings
  set status = 'accepted', accepted_offer_id = p_offer_id
  where id = v_booking_id;
end;
$$;

revoke all on function public.vip_accept_offer(uuid) from public;
grant execute on function public.vip_accept_offer(uuid) to authenticated;

-- Messages: customer/admin and the driver with the accepted offer can chat.
create policy "vip messages read booking participants"
on public.vip_messages for select to authenticated
using (
  public.vip_is_admin()
  or exists (
    select 1 from public.vip_bookings b
    where b.id = booking_id and b.customer_id = auth.uid()
  )
  or exists (
    select 1 from public.vip_offers o
    where o.booking_id = booking_id
      and o.driver_id = auth.uid()
      and o.status = 'accepted'
  )
);

create policy "vip messages send participants"
on public.vip_messages for insert to authenticated
with check (
  sender_id = auth.uid()
  and (
    public.vip_is_admin()
    or exists (
      select 1 from public.vip_bookings b
      where b.id = booking_id and b.customer_id = auth.uid()
    )
    or exists (
      select 1 from public.vip_offers o
      where o.booking_id = booking_id
        and o.driver_id = auth.uid()
        and o.status = 'accepted'
    )
  )
);

-- Settings: all signed-in users can read; only admins can change.
create policy "vip settings read authenticated"
on public.vip_settings for select to authenticated
using (true);

create policy "vip settings update admin"
on public.vip_settings for update to authenticated
using (public.vip_is_admin())
with check (public.vip_is_admin());

commit;

-- AFTER the first account is registered, make that account admin manually:
-- Replace the email below with the exact Gmail address used for your first account,
-- then run this single statement separately in SQL Editor:
-- update public.vip_profiles set role = 'admin' where email = 'YOUR_GMAIL@gmail.com';

-- To approve a driver later, an admin must review the application, then run:
-- update public.vip_driver_applications set status = 'approved' where driver_id = 'DRIVER_USER_UUID';
-- update public.vip_profiles set role = 'driver' where id = 'DRIVER_USER_UUID';
-- To disable a driver:
-- update public.vip_driver_applications set status = 'disabled' where driver_id = 'DRIVER_USER_UUID';
