TRANSFER — CUSTOMER, DRIVER AND ADMIN APP

THIS IS THE APP PACKAGE, NOT THE OLD MARKETING WEBSITE.

WEB APP FILES (upload these five files to the Netlify publish root):
- index.html
- app.css
- app.js
- config.js

SUPABASE SQL FILES:
- base-setup.sql: creates the vip_* database tables and base security policies.
- admin-functions.sql: adds driver job discovery and secure admin approval/disable functions.

IMPORTANT:
1. Keep using your existing Supabase project. Do not create a new project.
2. Before uploading, open config.js and enter your existing Supabase Project URL and Publishable (anon) key. Never put a service_role or secret key in browser code.
3. In Supabase SQL Editor, first review and run base-setup.sql. It creates additive vip_* tables and does not delete existing tables.
4. Then run admin-functions.sql.
5. Upload only the four web files (index.html, app.css, app.js, config.js) to the Netlify publish directory. SQL and README files are not website files.
6. Register the first account by email OTP. It starts as customer. To make it the admin, run this separately after replacing the email:
   update public.vip_profiles set role = 'admin' where email = 'YOUR_ADMIN_GMAIL@gmail.com';
7. Test customer booking, driver application, admin approval, driver offer, customer acceptance and chat.

FEATURES:
CUSTOMER: email OTP login, create ride requests, view offers, accept an offer, in-app chat, profile.
DRIVER: apply with vehicle details, admin approval, see open requests, add vehicle, send SAR price offers, in-app chat after acceptance.
ADMIN: view accounts/applications/bookings, approve or disable drivers, enable/disable driver offers.

BRAND AND LANGUAGE:
The app interface is English-only and branded Transfer. Support: Limuzin@196vip.si.
OTP help text tells users to check Spam or Junk.

LIMITATIONS:
This is an initial functional web-app build, not a Google Play app. It does not yet include payment processing, push notifications, live GPS tracking, secure document/photo uploads, admin-issued fixed-price offers or full reports. Vehicle photo fields currently accept a URL.

SECURITY NOTE:
The browser uses only the Supabase publishable/anon key. Never add a service_role or secret key to config.js.
