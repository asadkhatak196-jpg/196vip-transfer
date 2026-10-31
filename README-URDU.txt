VIP TRANSFER — READY-TO-CONNECT STARTER
========================================

یہ پہلے سے بنائی گئی فائلوں والا فولڈر ہے۔ اس میں ویب ایپ کا ابتدائی کام کرنے والا فرنٹ اینڈ، Supabase کنفیگ فائل، اور الگ SQL setup موجود ہے۔

فولڈر:
- public/index.html      ویب ایپ
- public/config.js       Supabase URL اور Publishable key
- public/manifest.json   PWA کی بنیادی معلومات
- supabase/setup.sql     نئے vip_ ٹیبلز اور RLS پالیسیز
- docs/NEXT-STEPS-URDU.txt اگلے مراحل

اہم حفاظتی باتیں:
1. پرانا BIGSERIAL/BIGINT والا SQL دوبارہ نہ چلائیں۔
2. یہ setup الگ vip_ ناموں والے ٹیبل بناتا ہے تاکہ پہلے سے موجود جدول overwrite نہ ہوں۔
3. setup.sql چلانے سے پہلے موجودہ Supabase schema اور policies کا backup/جائزہ لیں۔
4. config.js میں صرف Project URL اور Publishable/anon key ڈالیں۔ Secret/service_role key کبھی نہیں۔
5. پہلے سے موجود Supabase جدولوں (driver_applications, vehicles, driver_documents وغیرہ) کو یہ فائل تبدیل نہیں کرتی۔
6. یہ ایک ابتدائی قابلِ جوڑ ورژن ہے؛ اصل استعمال سے پہلے RLS/policies، قبول شدہ آفر کے flow، دستاویزات کی محفوظ Storage، live chat updates، validation، اور Android icon customization کی مکمل جانچ ضروری ہے۔

Netlify:
Publish directory کو public مقرر کریں۔ Domain 196vip.si اور DNS settings کو بلا ضرورت نہ چھیڑیں۔
Support: limuzin@196vip.si
