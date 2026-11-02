TRANSFER — TODAY TRANSFER RELEASE

PACKAGE CONTENTS
- index.html — application entry page
- styles.css — mobile-first design
- app.js — customer, driver and admin interface
- config.js — existing Supabase project connection settings
- manifest.json — installable web app metadata
- sw.js — service worker and offline app shell
- logo.svg and icons/ — shared Transfer T app icon
- transfer-admin-update.sql — additive Supabase update for admin controls

BRAND AND CUSTOMER DISPLAY
- App name: Transfer
- Main heading: Book Your Car
- Service line: Airport Transfer & Shuttle Services
- Tagline: Your Favourite Car, Right at Your Doorstep.
- Vehicle line: Small Cars & Economy, Sedan, SUV, GMC, Yukon, Tahoe, Lexus, Ford Taurus, Mercedes Vito, Mercedes Sprinter and Hiace Coaster.
- Support: Limuzin@196vip.si
- English-only interface. No sample bookings or private-ride wording.

FEATURES IN THIS RELEASE
- Email OTP sign-in with the notice: Your OTP may be in your spam folder.
- One shared Transfer app and one shared T launcher icon before sign-in.
- Customer and Driver role selection after sign-in. Driver access requires admin approval.
- Customer booking requests using pickup and destination text, including journeys between cities or countries.
- Drivers can add vehicles and submit SAR price offers for open requests.
- Customers can compare driver offers and vehicle photos. Vehicle plate is shown only after an offer is accepted.
- In-app chat for accepted bookings. Customer and driver phone numbers are not displayed to each other.
- Admin can approve/disable drivers, end pending offers, override pending offer prices, switch driver offers on/off, and set the company commission percentage.
- Driver in-app icon selection with a four-digit PIN gate, preset icons and an optional picture. This changes the icon inside the driver workspace only; the installed home-screen icon remains the shared Transfer T icon.
- PWA installation support for Android and iPhone home screens.

IMPORTANT LIMITATIONS
- This is an installable PWA package, not a native Android APK or an iOS App Store app. The first installation is initiated from the app link in a browser; after installation it opens as a standalone app. iPhone users add it from Safari using Share > Add to Home Screen.
- The four-digit driver icon PIN is a convenience lock in the browser on that device. It is not a server-enforced security boundary.
- The company commission percentage is saved as an admin setting. Automatic fee collection, invoicing and driver payouts are not connected to a payment provider.
- Vehicle photos are supplied as image URLs. Secure photo/document uploads are not included.
- Cross-city and international booking requests store the pickup and destination entered by the customer. The system does not automatically dispatch a vehicle or determine location using GPS.
- Actual database operation depends on the existing Supabase project, table schema, RLS policies, email OTP configuration and the update script below. This package has not been connected to your private project because your project URL and publishable key were not included in the files supplied for this review.

SETUP — KEEP YOUR EXISTING PROJECT
1. Extract this ZIP file.
2. Open config.js and replace only the two placeholder values with your existing Supabase Project URL and Publishable (anon) key. Do not use a service_role or secret key. Do not send these keys in chat.
3. In the SAME existing Supabase project, review transfer-admin-update.sql and run it once in SQL Editor. It is additive: it adds the phone and commission fields, approved-driver booking visibility, and admin-only functions. It does not drop or rename tables.
4. Make sure the first administrator account has role = admin in vip_profiles. If it is not already set, use the SQL Editor with the exact email of your admin account:
   update public.vip_profiles set role = 'admin' where email = 'YOUR_ADMIN_EMAIL';
5. Upload the contents of this folder (not the enclosing folder) to the root/publish directory of your existing GitHub repository. Keep the icons folder.
6. Deploy through your existing Netlify site connected to that repository. Keep the custom domain 196vip.si and its current DNS setup unchanged.
7. Test OTP sign-in, customer booking, driver application approval, driver vehicle creation, offers, offer acceptance, chat and admin settings before inviting customers.

SUPABASE SAFETY
- Keep the existing Supabase project and existing vip_* tables. Do not create a replacement project.
- Never put a service_role key or secret key in config.js.
- Do not delete existing Supabase tables or policies.
- If the actual table columns differ from the reviewed vip_* schema, pause deployment and reconcile the schema first.

NETLIFY / GITHUB FILE LAYOUT
index.html
styles.css
app.js
config.js
manifest.json
sw.js
logo.svg
icons/icon-192.png
icons/icon-512.png
transfer-admin-update.sql (keep for reference; it is not loaded by the browser)
README-ENGLISH.txt
