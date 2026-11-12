TRANSFER — BUILD 201 (CLOUDFLARE PAGES)
======================================

This is the Transfer PWA web-app source package. It is prepared for Cloudflare Pages static hosting and uses the existing Supabase project configured in config.js.

DEPLOY ROOT FILES
-----------------
Upload these files and icons from this folder to the ROOT of the Cloudflare Pages site:
- index.html
- app.js
- config.js
- style.css
- sw.js
- manifest.json
- _redirects
- icon-180.png
- icon-192.png
- icon-512.png

Do not upload the sql folder as website assets. Keep it for Supabase database work.

IMPORTANT SUPABASE NOTES
------------------------
1. This package is connected to the existing Supabase project using its browser-safe publishable key in config.js. Never replace it with a service_role or secret key.
2. Keep the existing live Supabase database and user records. Do not create a new project for this build.
3. Keep setup.sql. It is included unchanged as a retained project file; it is NOT the migration to rerun on the existing database.
4. Do NOT run base-setup.sql or setup.sql against the existing live database. They are historical/base schema files and may conflict with the already-created vip_* tables.
5. The project notes say driver-finance.sql has already been applied. Do NOT run it again unless the database has been independently checked and it is confirmed missing.
6. The current app requires the RPCs and columns in sql/transfer-runtime-rpcs.sql. Review and run that additive migration once in the existing Supabase SQL Editor after confirming the current vip_* tables are present.
7. The current offer editing flow also requires sql/transfer-runtime-fixes.sql. Review and apply it after transfer-runtime-rpcs.sql.
8. If admin-functions.sql, admin-access-control.sql, or account-role-and-icon.sql have not already been applied, review and run them in this order AFTER transfer-runtime-rpcs.sql:
   - admin-functions.sql
   - admin-access-control.sql
   - account-role-and-icon.sql
   Do not rerun migrations that are already applied.
9. Apply sql/transfer-security-fixes.sql after the base schema, runtime fixes and admin-access-control.sql. It tightens direct vehicle and chat access so vehicle plates stay hidden until offer acceptance.
10. Apply sql/transfer-admin-pricing.sql after transfer-security-fixes.sql for admin fixed-price offers and price overrides.
11. Apply sql/transfer-live-gps.sql after transfer-runtime-rpcs.sql and admin-access-control.sql to enable foreground driver GPS sharing for an assigned active ride.
12. The main administrator account configured by admin-access-control.sql is Asadkhatak196@gmail.com.
13. Supabase Auth email OTP must be enabled. The OTP message says: “Your OTP may be in your spam folder.”
14. Supabase Storage buckets and policies are included in transfer-runtime-rpcs.sql for private driver documents and vehicle photos.

FEATURES IN THIS WEB BUILD
--------------------------
- English Transfer branding and support contact: Limuzin@196vip.si
- Email OTP authentication using Supabase
- After OTP, Customer or Driver experience selection; protected Admin routing
- Customer booking form for airport and city-to-city trips
- Customer-only booking Bell to alert approved online drivers, plus customer-only assigned-driver chat alert
- Driver application, vehicle details, document uploads, approval state, online/offline availability and price offers
- Customer offer cards with vehicle plate hidden until acceptance
- In-app chat after offer acceptance; phone numbers are not shown in chat
- Admin booking, application, offer, driver approval/disable, fixed-price offer creation and pending-offer price overrides
- Driver cash-collection completion flow and 5% / 10% commission ledger
- Driver-only four-digit local PIN using PBKDF2-SHA-256 on this device
- Foreground live GPS sharing during an accepted active ride, with customer-side driver map
- PWA manifest, icons, service worker and Cloudflare Pages route fallback

IMPORTANT LIMITS — NOT CLAIMED AS LIVE-VERIFIED
-----------------------------------------------
- This package has been syntax-checked and its ZIP integrity will be checked, but it has NOT been connected to a live browser session or tested end-to-end against the user's live Supabase data.
- Cloudflare Pages deployment itself must still be performed in the user's Cloudflare account.
- Real OS web-push notifications while the app is closed, payment processing, multi-currency conversion, country-by-country regulatory onboarding and a signed Android APK are not included as completed services in this build.
- Fixed-price offer creation and overrides require the new admin pricing migration to be applied and tested against the live database.
- The driver PIN is a local device privacy lock, not server-side authentication or a replacement for Android device security. Clearing browser data removes it.
- Availability and booking alerts in this build are in-app database notifications; they are not guaranteed OS push alerts while the app is closed.

TEST BEFORE PUBLIC LAUNCH
-------------------------
1. Deploy the root web files to a Cloudflare Pages preview URL first.
2. Confirm email OTP sign-in for a new Customer and a new Driver account.
3. Confirm Customer/Driver choice persists after refresh.
4. Submit a Driver application, then approve it from the Admin account.
5. Set the driver online, create a Customer booking, and confirm the driver receives an in-app alert.
6. Send an offer; confirm the Customer sees the vehicle/photo/price but not the plate.
7. Accept the offer; confirm chat opens and the plate becomes visible only after acceptance.
8. Test driver-arrived, in-progress, and completed ride transitions; test both cash-collected YES and NO with a commission rate assigned.
9. Test driver PIN lock, private document viewing, driver disable, offer removal and booking cancellation.
10. Only after these tests pass should the Cloudflare Pages project be promoted to production.


LIVE GPS TRACKING (FOREGROUND)
------------------------------
Apply `sql/transfer-live-gps.sql` after `sql/transfer-runtime-rpcs.sql` and `sql/admin-access-control.sql`. An approved driver who is online and has an accepted active ride shares GPS location while the Driver panel remains open. The customer can see the assigned driver's last location on the ride status map. The app requests browser location permission. Mobile browsers may suspend location updates when the app is backgrounded or the phone is locked; this is not a native background tracking service.
