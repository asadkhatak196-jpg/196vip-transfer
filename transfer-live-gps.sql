-- Transfer live GPS sharing (foreground app tracking).
-- Apply AFTER base-setup.sql, transfer-runtime-rpcs.sql and admin-access-control.sql.
-- Drivers share location only while approved and marked online. Customers can read
-- only the assigned driver's latest location for their own active booking.

begin;

create table if not exists public.vip_driver_locations (
  driver_id uuid primary key references public.vip_profiles(id) on delete cascade,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  accuracy_m double precision,
  updated_at timestamptz not null default now()
);
create index if not exists vip_driver_locations_updated_idx on public.vip_driver_locations(updated_at desc);
alter table public.vip_driver_locations enable row level security;
drop policy if exists "vip driver locations assigned visibility" on public.vip_driver_locations;
create policy "vip driver locations assigned visibility"
on public.vip_driver_locations for select to authenticated
using (
  driver_id = auth.uid()
  or exists (
    select 1 from public.vip_bookings b
    join public.vip_offers o on o.id = b.accepted_offer_id
    where o.driver_id = vip_driver_locations.driver_id
      and b.customer_id = auth.uid()
      and b.status in ('accepted','driver_arrived','in_progress')
  )
  or public.vip_is_admin()
);
revoke all on public.vip_driver_locations from anon, authenticated;
grant select on public.vip_driver_locations to authenticated;

create or replace function public.vip_driver_update_location(
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_m double precision default null
) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then raise exception 'Sign-in required'; end if;
  if p_latitude is null or p_longitude is null
     or p_latitude not between -90 and 90
     or p_longitude not between -180 and 180 then
    raise exception 'Invalid GPS coordinates';
  end if;
  if not exists (
    select 1 from public.vip_profiles p
    join public.vip_driver_applications a on a.driver_id=p.id
    where p.id=auth.uid() and p.role='driver'
      and p.is_available=true and a.status='approved'
  ) or not exists (
    select 1 from public.vip_bookings b
    join public.vip_offers o on o.id=b.accepted_offer_id
    where o.driver_id=auth.uid()
      and b.status in ('accepted','driver_arrived','in_progress')
  ) then raise exception 'Only an approved online driver with an active assigned ride can share GPS location'; end if;
  insert into public.vip_driver_locations(driver_id,latitude,longitude,accuracy_m,updated_at)
  values(auth.uid(),p_latitude,p_longitude,p_accuracy_m,now())
  on conflict(driver_id) do update set
    latitude=excluded.latitude, longitude=excluded.longitude,
    accuracy_m=excluded.accuracy_m, updated_at=now();
end;
$$;
revoke all on function public.vip_driver_update_location(double precision,double precision,double precision) from public, anon;
grant execute on function public.vip_driver_update_location(double precision,double precision,double precision) to authenticated;

create or replace function public.vip_driver_clear_location()
returns void language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then raise exception 'Sign-in required'; end if;
  delete from public.vip_driver_locations where driver_id=auth.uid();
end;
$$;
revoke all on function public.vip_driver_clear_location() from public, anon;
grant execute on function public.vip_driver_clear_location() to authenticated;

commit;
