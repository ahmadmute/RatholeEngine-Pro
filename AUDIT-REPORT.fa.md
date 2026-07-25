# گزارش ممیزی و آماده‌سازی RatholeEngine Pro v1.5.1

تاریخ: 2026-07-25
مخزن هدف: `ahmadmute/RatholeEngine-Pro`

## ورودی‌های بررسی‌شده

- `RatholeEngine-main.zip`
- `RatholeEngine-1.5.0.zip`
- `rathole-manager.zip`

دو آرشیو کامل `main` و `1.5.0` از نظر فایل‌های استخراج‌شده یکسان بودند. آرشیو manager همان مدیر را به‌همراه باینری‌های Core برای `x86_64` و `aarch64` داشت؛ بنابراین نسخه کامل به‌عنوان پایه انتخاب و Coreهای امضاشده به آن افزوده شد.

## نتیجه کلی

نسخه آماده‌شده شماره `1.5.1` دارد، ساختار و مسیرهای موجود را حفظ می‌کند و تغییرات روی پایداری state/config، امنیت Hub، صحت به‌روزرسانی، ایمنی Bootstrap، اعتبارسنجی ورودی‌ها، رابط وب و پوشش تست متمرکز است.

## ایرادهای مهم پیدا و اصلاح‌شده

| شدت | ایراد | اصلاح |
|---|---|---|
| بالا | override مسیرها در حالت library نادیده گرفته می‌شد و ابزار تست/تعمیر ممکن بود به `/etc` واقعی بنویسد | همه مسیرهای `STATE`، TOML و Nginx اکنون overrideپذیرند و تست sandbox واقعی اضافه شد |
| بالا | شکست `jq` یا قطع عملیات می‌توانست state را خالی/ناقص کند | temp هم‌دایرکتوری، `flock`، بررسی خروجی و JSON، حفظ مجوز و replace اتمیک |
| بالا | probeهای adaptive، host/port را داخل `bash -c` قرار می‌دادند | انتقال مقادیر با positional argv و تست تزریق |
| بالا | آپدیت Hub/Panel/Node فایل دانلودشده را بدون تطبیق checksum اجرا می‌کرد | دریافت و بررسی `SHA256SUMS` برای `install.sh`، bootstrap و bundle؛ رد پیش‌فرض update تأییدنشده |
| بالا | Bootstrap با root آرشیو را بدون بررسی traversal/symlink باز می‌کرد | رد `../`، مسیر مطلق، symlink، device و فایل خاص پیش از نصب |
| بالا | رمز Hub با SHA-256 ساده و بدون salt نگهداری می‌شد | PBKDF2-SHA256 با salt تصادفی و 310,000 دور؛ مهاجرت خودکار hash قدیمی پس از ورود موفق |
| بالا | API token در `localStorage` مرورگر ماندگار بود | نشست HttpOnly/SameSite، حذف token از JavaScript، endpoint خروج و refresh امن نشست هنگام rotation |
| متوسط | ورودی port فقط ظاهراً عددی بود و مقادیر بالاتر از 65535 پذیرفته می‌شد | اعتبارسنجی واقعی بازه `1..65535` در API و CLI |
| متوسط | username با `-` می‌توانست در argv ابزار SSH شبیه option تفسیر شود | regex اختصاصی SSH user و اعتبارسنجی دفاعی درست قبل از ساخت argv |
| متوسط | عملیات هم‌زمان می‌توانستند regenerate/update را روی هم اجرا کنند | command lock برای mutationهای panel و node |
| متوسط | هدرهای امنیتی و cache policy پنل ناکافی بود | CSP، DENY frame، no-referrer، permissions policy، COOP/CORP و no-store |
| متوسط | service هاب محدودسازی سیستم‌عامل کمی داشت | `UMask=0077`، `NoNewPrivileges`، `PrivateTmp`، ProtectKernel/FS و محدودیت‌های systemd |
| متوسط | شماره نسخه Hub/manager با release هماهنگ نبود | همگام‌سازی روی `1.5.1` و اصلاح منبع پیش‌فرض repository |
| پایین | harness قدیمی مسیر اشتباه داشت و بدون state، FAIL چاپ می‌کرد ولی با rc=0 تمام می‌شد | مسیر درست، init flag-based، اجرای 14 سناریو در CI و بررسی نبود `FAIL:` |
| پایین | package ممکن بود فقط ZIP یا فقط TAR بسازد | ساخت اجباری هر دو asset و بررسی نام‌های archive |

## بازطراحی پنل

- ظاهر Control Center حرفه‌ای و responsive با سلسله‌مراتب بصری روشن‌تر
- کارت‌ها، وضعیت‌ها، badgeها و action feedback یکپارچه‌تر
- focus state مناسب برای استفاده با کیبورد
- حفظ hash-router، endpointها، دکمه‌ها و عملیات موجود
- تغییر ندادن مدل inventory و command allow-list فعلی

## تست‌های اجراشده و موفق

- syntax همه فایل‌های Shell با `bash -n`
- compile همه فایل‌های Python
- تولید config خالی/پر Node و commit قفل‌شده TOML
- کنترل path مخفی WebSocket
- تولید config واقعی Nginx و موفقیت `nginx -t`
- probe و controller adaptive، threshold/cooldown/plain guard و تست injection
- state failure atomicity هنگام خرابی عمدی `jq`
- رد archive traversal در Bootstrap
- 19 تست Hub: allow-list، validation، PBKDF2، legacy migration، session cookie، logout، security headers، port range و SSH option injection
- بررسی checksum Core و رد باینری tampered
- بررسی ساختار workflow Release
- 14 سناریوی manager harness: init/add/remove/reuse port/direct/plain/SNI/status/off
- ساخت موفق `rathole-manager.zip` و `rathole-manager.tar.gz`

خروجی اجرای نهایی: `ALL_FINAL_LOCAL_TESTS_OK`

## Core همراه بسته

- `x86_64-unknown-linux-gnu/rathole`
  SHA-256: `2a44755dd0430eb5d4e1eb3ff0dacb67e02cadd1342c00e0f9afb3f975e94fd4`
- `aarch64-unknown-linux-gnu/rathole`
  SHA-256: `c68aeae557acdda11715e4933aee0018b3329d835cb7553e9ef177ba45822005`
- نسخه باینری x86_64: `rathole 0.5.1-ratholeengine.1`

## محدودیت‌های این ممیزی

- تست end-to-end واقعی بین دو VPS مستقل، اینترنت عمومی، TLS واقعی و ترافیک Xray انجام نشد؛ چنین تستی به دو سرور و دامنه/گواهی واقعی نیاز دارد. در عوض مسیرهای config، Nginx، HTTP Hub، probe، state و packaging محلی تست شدند.
- تست بازسازی Core از source pinned در این محیط اجرا نشد، چون DNS محیط اجرای محلی `github.com` را resolve نکرد. workflow موجود در GitHub CI این تست را روی runner آنلاین اجرا می‌کند. باینری‌های همراه از نظر checksum و نسخه بررسی شدند.
- مرورگر Chromium محیط محلی navigation به HTTP localhost را با policy مسدود کرد؛ بنابراین screenshot خودکار UI گرفته نشد. API واقعی HTTP، HTML/CSS static checks و تست‌های session/security موفق بودند.

## انتشار پیشنهادی

```bash
git clone https://github.com/ahmadmute/RatholeEngine-Pro.git
cd RatholeEngine-Pro
# محتوای بسته ready-to-push را داخل مخزن قرار بده، سپس:
git add -A
git commit -m "release: prepare RatholeEngine Pro v1.5.1"
git push -u origin main

git tag -a v1.5.1 -m "RatholeEngine Pro v1.5.1"
git push origin v1.5.1
```

با push شدن tag، workflow Release باید Coreها، bundleها و `SHA256SUMS` را منتشر کند.
