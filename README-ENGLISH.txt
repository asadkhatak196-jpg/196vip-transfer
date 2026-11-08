TRANSFER — BUILD 71

Build 71 connects the main booking and driver price-offer workflow to the existing Supabase project.

Customer features:
- Create Now, Later, and Airport Transfer bookings.
- Store booking details in Supabase.
- Receive driver offers ordered by lowest price.
- Accept one offer; the selected vehicle plate is revealed only after acceptance.
- Cancel an eligible booking.

Driver features:
- Approved drivers can switch online/offline.
- Online approved drivers can view open booking requests.
- Drivers can submit a SAR price and estimated pickup time.
- Offers are stored in Supabase and appear in the customer's live offer list.

Admin features:
- Review and approve/disable driver applications.
- Enable or pause driver offers.
- Save Comfort, Business, and VIP base prices.
- Review bookings and submitted offers.

Setup:
1. Keep the existing Supabase project and existing setup.sql file.
2. config.js already contains the project URL and publishable key. Never add a service_role key.
3. The additive database changes for Build 71 have already been applied to the connected project. See SUPABASE-BOOKING-OFFERS-71.sql for the migration record.
4. Upload the contents of this ZIP to the existing Netlify site/repository, replacing the matching Build 70 frontend files.
5. Test with a customer account, an approved driver account, and the authorized admin account.

Not yet connected: private document/photo uploads, in-app chat, push notifications, separate Bell delivery, trip progress persistence, GPS tracking, and rating persistence. This is a connected booking/offers build, not yet the fully finished production taxi platform.
