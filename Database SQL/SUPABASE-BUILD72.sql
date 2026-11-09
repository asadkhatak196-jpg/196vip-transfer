-- Transfer Build 72: live chat, in-app notifications, secure driver files,
-- persistent ride status/history, and database-backed admin offer removal.
-- Additive and safe to re-run. Existing bookings/users are preserved.
begin;

-- Ride workflow: accepted -> driver_arrived -> in_progress -> completed.
alter table public.vip_bookings drop constraint if exists vip_bookings_status_check;
alter table public.vip_bookings add constraint vip_bookings_status_check
  check (status in ('open','accepted','driver_arrived','in_progress','completed','cancelled'));

create table if not exists public.vip_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.vip_profiles(id) on delete cascade,
  sender_id uuid references public.vip_profiles(id) on delete set null,
  booking_id uuid references public.vip_bookings(id) on delete cascade,
  notification_type text not null check (notification_type in ('new_booking','new_message','ride_status','admin_notice')),
  title text not null,
  body text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.vip_notifications enable row level security;
drop policy if exists "vip notifications read own admin" on public.vip_notifications;
create policy "vip notifications read own admin" on public.vip_notifications
 for select to authenticated using (recipient_id=(select auth.uid()) or public.vip_is_admin());
drop policy if exists "vip notifications mark own read" on public.vip_notifications;
create policy "vip notifications mark own read" on public.vip_notifications
 for update to authenticated using (recipient_id=(select auth.uid()) or public.vip_is_admin())
 with check (recipient_id=(select auth.uid()) or public.vip_is_admin());
revoke all on public.vip_notifications from anon, public;
grant select, update on public.vip_notifications to authenticated;

-- Notify every currently-online, approved driver automatically when a booking is created.
create or replace function public.transfer_notify_online_drivers_new_booking()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 insert into public.vip_notifications(recipient_id,sender_id,booking_id,notification_type,title,body)
 select p.id,new.customer_id,new.id,'new_booking','New ride request',
        left(new.pickup || ' → ' || new.destination,240)
 from public.vip_profiles p
 join public.vip_driver_applications a on a.driver_id=p.id and a.status='approved'
 where p.role='driver' and p.is_available=true and p.id<>new.customer_id;
 return new;
end; $$;
drop trigger if exists transfer_booking_notify_drivers on public.vip_bookings;
create trigger transfer_booking_notify_drivers after insert on public.vip_bookings
 for each row when (new.status='open') execute function public.transfer_notify_online_drivers_new_booking();

-- Notify the other participant for every persisted chat message.
create or replace function public.transfer_notify_chat_participant()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_customer uuid; v_driver uuid; v_recipient uuid;
begin
 select b.customer_id,o.driver_id into v_customer,v_driver
 from public.vip_bookings b left join public.vip_offers o on o.id=b.accepted_offer_id
 where b.id=new.booking_id and b.status in ('accepted','driver_arrived','in_progress','completed');
 if v_customer is null or v_driver is null then return new; end if;
 if new.sender_id=v_customer then v_recipient:=v_driver;
 elsif new.sender_id=v_driver then v_recipient:=v_customer;
 else return new; end if;
 insert into public.vip_notifications(recipient_id,sender_id,booking_id,notification_type,title,body)
 values(v_recipient,new.sender_id,new.booking_id,'new_message','New chat message','You received a new message about your Transfer booking.');
 return new;
end; $$;
drop trigger if exists transfer_message_notify_participant on public.vip_messages;
create trigger transfer_message_notify_participant after insert on public.vip_messages
 for each row execute function public.transfer_notify_chat_participant();

-- Persist status transitions; only the assigned driver or admin may advance a ride.
create or replace function public.vip_update_ride_status(p_booking_id uuid,p_status text)
returns boolean language plpgsql security definer set search_path=public,pg_temp as $$
declare v_driver uuid; v_customer uuid; v_old text;
begin
 if auth.uid() is null then raise exception 'Sign-in required'; end if;
 if p_status not in ('driver_arrived','in_progress','completed') then raise exception 'Invalid ride status'; end if;
 select b.customer_id,b.status,o.driver_id into v_customer,v_old,v_driver
 from public.vip_bookings b left join public.vip_offers o on o.id=b.accepted_offer_id
 where b.id=p_booking_id for update of b;
 if not found then raise exception 'Booking not found'; end if;
 if not public.vip_is_admin() and auth.uid()<>v_driver then raise exception 'Only the assigned driver or Admin can update this ride'; end if;
 if (v_old='accepted' and p_status<>'driver_arrived') or
    (v_old='driver_arrived' and p_status<>'in_progress') or
    (v_old='in_progress' and p_status<>'completed') then
   raise exception 'Ride status must follow: accepted → driver arrived → in progress → completed';
 end if;
 update public.vip_bookings set status=p_status where id=p_booking_id;
 insert into public.vip_notifications(recipient_id,sender_id,booking_id,notification_type,title,body)
 values(v_customer,auth.uid(),p_booking_id,'ride_status','Ride status updated',replace(p_status,'_',' '));
 return true;
end; $$;
revoke all on function public.vip_update_ride_status(uuid,text) from public,anon;
grant execute on function public.vip_update_ride_status(uuid,text) to authenticated;

-- Ensure admin offer removal is callable only by authenticated Admin.
revoke all on function public.vip_admin_cancel_offer(uuid) from public,anon;
grant execute on function public.vip_admin_cancel_offer(uuid) to authenticated;

-- Realtime streams used by active customer/driver/admin sessions.
do $$ declare t text; begin
 foreach t in array array['vip_messages','vip_notifications'] loop
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
   execute format('alter publication supabase_realtime add table public.%I',t);
  end if;
 end loop;
end $$;

-- Public vehicle images; sensitive identity/licence files remain in a private bucket.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('transfer-vehicle-photos','transfer-vehicle-photos',true,10485760,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=true,file_size_limit=10485760,allowed_mime_types=excluded.allowed_mime_types;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('transfer-driver-documents','transfer-driver-documents',false,15728640,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict(id) do update set public=false,file_size_limit=15728640,allowed_mime_types=excluded.allowed_mime_types;

-- Vehicle images can be read publicly for offer cards; only owner uploads/updates/deletes.
drop policy if exists "transfer vehicle photos public read" on storage.objects;
create policy "transfer vehicle photos public read" on storage.objects for select to public using(bucket_id='transfer-vehicle-photos');
drop policy if exists "transfer vehicle photos owner insert" on storage.objects;
create policy "transfer vehicle photos owner insert" on storage.objects for insert to authenticated
 with check(bucket_id='transfer-vehicle-photos' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists "transfer vehicle photos owner update" on storage.objects;
create policy "transfer vehicle photos owner update" on storage.objects for update to authenticated
 using(bucket_id='transfer-vehicle-photos' and ((storage.foldername(name))[1]=(select auth.uid())::text or (select public.vip_is_admin())))
 with check(bucket_id='transfer-vehicle-photos' and ((storage.foldername(name))[1]=(select auth.uid())::text or (select public.vip_is_admin())));
drop policy if exists "transfer vehicle photos owner delete" on storage.objects;
create policy "transfer vehicle photos owner delete" on storage.objects for delete to authenticated
 using(bucket_id='transfer-vehicle-photos' and ((storage.foldername(name))[1]=(select auth.uid())::text or (select public.vip_is_admin())));

-- Private documents: only the driver who owns the folder and Admin can read.
drop policy if exists "transfer private docs owner admin read" on storage.objects;
create policy "transfer private docs owner admin read" on storage.objects for select to authenticated
 using(bucket_id='transfer-driver-documents' and ((storage.foldername(name))[1]=(select auth.uid())::text or (select public.vip_is_admin())));
drop policy if exists "transfer private docs owner insert" on storage.objects;
create policy "transfer private docs owner insert" on storage.objects for insert to authenticated
 with check(bucket_id='transfer-driver-documents' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists "transfer private docs owner admin update" on storage.objects;
create policy "transfer private docs owner admin update" on storage.objects for update to authenticated
 using(bucket_id='transfer-driver-documents' and ((storage.foldername(name))[1]=(select auth.uid())::text or (select public.vip_is_admin())))
 with check(bucket_id='transfer-driver-documents' and ((storage.foldername(name))[1]=(select auth.uid())::text or (select public.vip_is_admin())));
drop policy if exists "transfer private docs owner admin delete" on storage.objects;
create policy "transfer private docs owner admin delete" on storage.objects for delete to authenticated
 using(bucket_id='transfer-driver-documents' and ((storage.foldername(name))[1]=(select auth.uid())::text or (select public.vip_is_admin())));

commit;

-- Extend chat access through every active ride status (not just 'accepted').
drop policy if exists "vip messages read booking participants" on public.vip_messages;
create policy "vip messages read booking participants" on public.vip_messages for select to authenticated using (
 public.vip_is_admin()
 or exists(select 1 from public.vip_bookings b where b.id=vip_messages.booking_id and b.customer_id=(select auth.uid()) and b.status in ('accepted','driver_arrived','in_progress','completed'))
 or exists(select 1 from public.vip_offers o join public.vip_bookings b on b.id=o.booking_id where o.booking_id=vip_messages.booking_id and o.driver_id=(select auth.uid()) and o.status='accepted' and b.status in ('accepted','driver_arrived','in_progress','completed'))
);
drop policy if exists "vip messages send participants" on public.vip_messages;
create policy "vip messages send participants" on public.vip_messages for insert to authenticated with check (
 sender_id=(select auth.uid()) and (
  public.vip_is_admin()
  or exists(select 1 from public.vip_bookings b where b.id=vip_messages.booking_id and b.customer_id=(select auth.uid()) and b.status in ('accepted','driver_arrived','in_progress','completed'))
  or exists(select 1 from public.vip_offers o join public.vip_bookings b on b.id=o.booking_id where o.booking_id=vip_messages.booking_id and o.driver_id=(select auth.uid()) and o.status='accepted' and b.status in ('accepted','driver_arrived','in_progress','completed'))
 )
);
drop policy if exists "vip application update own pending" on public.vip_driver_applications;
create policy "vip application update own pending" on public.vip_driver_applications for update to authenticated
 using(driver_id=(select auth.uid()) and status='pending')
 with check(driver_id=(select auth.uid()) and status='pending');

-- Trigger-only functions must not be exposed as callable RPC endpoints.
revoke all on function public.transfer_notify_online_drivers_new_booking() from public, anon, authenticated;
revoke all on function public.transfer_notify_chat_participant() from public, anon, authenticated;
revoke all on function public.transfer_handle_new_auth_user() from public, anon, authenticated;
