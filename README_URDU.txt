VIP TRANSFER — Cross-platform starter (iPhone + Android + Web)

اہم بات:
یہ ZIP مکمل source project ہے؛ یہ ابھی public internet پر live نہیں ہے اور نہ ہی APK/App Store package ہے۔
Customer اور Driver کے signup/login، booking، driver offers، chat API، admin settings، driver/vehicle approval اور PostgreSQL schema شامل ہیں۔
نئے database پر server شروع ہونے پر schema initialize کرنے کی کوشش کرتا ہے۔ پھر بھی اسے deploy کرکے لازماً test کرنا ہوگا۔

اکاؤنٹس:
1) Customer: ایپ میں اپنا نام، email، password لکھ کر Account type = Customer منتخب کریں، پھر Create account۔
2) Driver: Account type = Driver منتخب کرکے Create account۔ ڈرائیور/گاڑی کی منظوری Admin کو دینی ہوگی۔
3) Admin: Admin خود public registration سے نہیں بنتا۔ Server hosting کے environment settings میں ADMIN_EMAIL اور ADMIN_PASSWORD مقرر کریں۔ پہلی کامیاب startup پر اسی email کا admin بنے گا۔ Admin اسی email/password سے Sign in کرے گا۔
4) Admin settings میں driver offers on/off، pricing mode، Comfort/Business/VIP rates، model year visibility اور driver/vehicle approvals ہیں۔

لوکل ٹیسٹ (developer/computer درکار):
1) Node.js 20+ اور Docker انسٹال کریں۔
2) اس فولڈر میں .env.example کی کاپی بنا کر نام .env رکھیں۔
3) .env میں DB_PASSWORD، JWT_SECRET، ADMIN_EMAIL اور ADMIN_PASSWORD کے لیے مضبوط منفرد values رکھیں۔ اپنی passwords کسی کو chat میں نہ بھیجیں۔
4) Docker Desktop چلائیں، پھر اسی فولڈر میں command چلائیں: docker compose up --build
5) browser میں http://localhost:8080 کھولیں۔

اصل live server کے لیے:
- ایسا hosting provider درکار ہے جو Node.js app اور PostgreSQL database دونوں چلا سکے۔
- Host کی طرف سے ملنے والا DATABASE_URL اور دیگر environment variables set کرنے ہوں گے۔
- public HTTPS domain، CORS/origin settings، logs، database backups، monitoring اور production security review درکار ہیں۔
- Netlify static hosting اکیلے اس Node.js/PostgreSQL backend کو نہیں چلاتی؛ backend/database الگ deploy کرنا ہوگا۔
- Hosting account، domain یا credentials تک رسائی کے بغیر میں یہاں سے آپ کی طرف سے live server create یا configure نہیں کر سکتا۔ اپنے passwords/secret keys چیٹ میں نہ بھیجیں۔

موبائل:
- HTTPS deployment کے بعد Android Chrome میں menu > Install app / Add to Home screen۔
- iPhone Safari میں Share > Add to Home Screen۔
- Google Play / Apple App Store کے لیے الگ packaging، developer accounts اور review درکار ہیں۔

ابھی production سے پہلے ضروری کام/ٹیسٹ:
- حقیقی hosting پر deployment اور end-to-end tests
- email/SMS verification، push notifications، payments، maps/GPS
- محفوظ vehicle photo upload/storage (ابھی photo URL field ہے)
- backups/monitoring اور independent security review
- admin-fixed price mode کی مکمل dispatch/driver assignment workflow کو business rules کے مطابق مکمل کرنا

یہ Gitransfer کی copy نہیں؛ VIP TRANSFER کے لیے بنایا گیا starter implementation ہے۔
Support email: support@limuzin.vip.si
