# 196 VIP Transfer — website package

## Files
- `index.html` — customer, driver and admin web app
- `config.js` — Supabase public URL/key settings (fill these in)
- `logo.png` — approved Transfer logo
- `admin-driver-approval-patch.sql` — one small SQL addition for secure admin approval/disable

## Before deploying
1. Open `config.js` and replace the two placeholder values with the Supabase Project URL and Publishable/anon key. Do NOT use the service_role/secret key.
2. In Supabase SQL Editor, run `admin-driver-approval-patch.sql` once. It adds the admin-only driver approval function.
3. Upload the contents of this folder to the existing Netlify site's publish/root directory (keep the same domain).

## Important first-time setup
- The first administrator account must be promoted once in Supabase SQL Editor using the actual Gmail:
  `update public.vip_profiles set role='admin' where email='YOUR_ADMIN_GMAIL';`
- Driver applications are pending until an admin approves them.
- The customer accepts an offer through the secure `vip_accept_offer` database function included in the reviewed SQL.
- Hostinger DNS and mail records are not changed by these files.

## Scope / verification
This is a working first web-app build aligned to the reviewed `vip_*` schema. Before taking real customer bookings, test sign-in, booking creation, driver approval, vehicle display, offers, offer acceptance and chat with two test accounts. Existing Supabase policies/schema may need a small adjustment if the live project differs from the reviewed SQL. No payment gateway or SMS login is included.
