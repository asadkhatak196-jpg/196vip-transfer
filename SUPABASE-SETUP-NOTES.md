# Transfer — Supabase notes for Build 71

Project URL and publishable key are configured in `config.js`.

Build 71 uses the existing `vip_` schema. It does not create a second project or delete/rename existing tables.

Connected tables:
- `vip_profiles`
- `vip_driver_applications`
- `vip_bookings`
- `vip_offers`
- `vip_vehicles`
- `vip_settings`

Protected database functions used by the app:
- `vip_set_driver_availability`
- `vip_customer_offer_cards`
- `vip_accept_offer`
- `vip_cancel_booking`
- `vip_admin_set_driver_status`

Realtime publication includes booking, offer, settings, application, and profile changes.

`SUPABASE-BOOKING-OFFERS-71.sql` records the additive migration. The migration was applied to the configured project on 2026-11-08 and its main functions and Realtime publication entries were checked.

Do not delete or rerun the original `setup.sql`. Do not expose a service-role key in browser code. RLS remains enabled; the app uses only the publishable key.

Still outstanding: Storage uploads for driver documents/vehicle photos, live chat, push notification delivery, trip status persistence, GPS tracking, and rating persistence.
