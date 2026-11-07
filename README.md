# BuildStock — Vijay Balaji Agency

[![Build Android APK](https://github.com/Hem1234567/Inventory-management-System-bala/actions/workflows/ci.yml/badge.svg)](https://github.com/Hem1234567/Inventory-management-System-bala/actions/workflows/ci.yml)

Offline-first inventory, billing and accounting for a building-materials dealer
(cement, sand, jelly, gravel, blocks) — retail and wholesale, GST and non-GST,
several godowns and several phones.

**Flutter (Android) · Riverpod · GoRouter · Drift/SQLite · Firebase Auth + Cloud Firestore**

> The app ships with no sample products, customers, invoices or statistics.
> Every figure and document is derived from records the business enters.

---

## Contents

1. [Features](#1-features)
2. [Download the APK](#2-download-the-apk)
3. [Architecture](#3-architecture)
4. [Feature guide](#4-feature-guide)
5. [Firebase setup](#5-firebase-setup)
6. [Build, CI and release](#6-build-ci-and-release)
7. [Testing](#7-testing)
8. [Project conventions](#8-project-conventions)
9. [Limitations and notes](#9-limitations-and-notes)

---

## 1. Features

| Area | What you get |
| --- | --- |
| **Billing** | Retail/wholesale, GST/non-GST, discounts, partial payments, UPI QR (no gateway), A4 bill/estimate in the Vijay Balaji format, 58 mm and 80 mm thermal |
| **Quotations & estimates** | Create from checkout, validity days, **convert to invoice** (stock leaves the chosen godown, source marked converted) |
| **Customer orders** | Record what a customer asked for, track status (open → confirmed → ready → delivered), **create an invoice from the order** |
| **Credit & debit notes** | Customer and supplier notes that change only the party balance; PDF print/share; original bills never edited |
| **Returns** | Sales and purchase returns with stock and balance effects |
| **Inventory** | Append-only stock ledger, stores and godowns, **godown choice** in sales, purchases, adjustments and filters, stock transfers |
| **Barcode & QR** | Camera scanner for billing, purchases, product form and inventory lookup; **scan a bill's QR to open it** |
| **Photos** | Camera/gallery capture, compression, upload to ImgBB or Cloudinary for products, logo, signature, stamp, customers, suppliers, staff, drivers, supplier bills and **delivery proof** |
| **Reports** | Sales, GST, stock value, outstanding, low stock; **Excel (.xlsx) and CSV export** |
| **Alerts** | **Low-stock notifications** (at most once a day per set of products) |
| **People & payroll** | Staff, drivers, attendance, salary generation and payment, **printable salary slips** |
| **Search** | **Global search** across products, bills, customers, suppliers, orders, purchases, returns, staff, drivers, deliveries and expenses |
| **Printing** | Android print dialog **or direct ESC/POS** to network (TCP 9100), Bluetooth and USB thermal printers |
| **Backup** | **Backup and restore** of all data to a file, plus an automatic daily local backup |
| **Team** | **Invite users**, roles and permissions, **device management** (enable/disable), join a shop with an invite code |
| **Sync** | Durable outbox, idempotent writes, incremental pull, conflict detection; Firestore rules enforce roles and immutability |
| **Languages** | English and Tamil |

---

## 2. Download the APK

Every push to GitHub runs **Build Android APK**.

1. Open the repository → **Actions** → the latest *Build Android APK* run.
2. Download the **buildstock-apk** artifact (a zip containing `BuildStock-v<version>-build<N>.apk`).
3. Unzip and install on the phone (allow *install unknown apps* once).

Tag a release (`git tag v1.0.0 && git push --tags`) to publish the APK as a GitHub
release automatically.

---

## 3. Architecture

Feature-first clean architecture:

```
lib/
  app/                 theme, router, shell, preferences
  core/
    audit/             immutable audit writer
    backup/            backup & restore service
    database/          Drift schema (41 tables), migrations, providers
    domain/            shared enums and status strings
    errors/            typed AppFailure
    export/            Excel workbook builder and report queries
    firebase/          initialization and auth wrapper
    media/             photo capture, compression, upload to image hosts
    notifications/     low-stock notifier
    printing/          ESC/POS encoder, thermal printer service
    qr/ scanner/       UPI payload, invoice QR payload, camera scanner
    security/          permission catalog and role defaults
    session/           device identity and shop binding
    sync/              outbox, backend, engine, local mirror, controller
    utils/             money, quantity, dates, ids, json, validators
    widgets/           design-system components and forms
  features/            dashboard, sales, invoices, orders, products, inventory,
                       customers, suppliers, purchases, returns, accounts,
                       stores, staff, deliveries, reports, search, team,
                       settings, sync
  l10n/                English and Tamil ARB files
android/.../MainActivity.kt   Bluetooth + USB printer channel
```

Rules enforced in code:

* The UI never imports `cloud_firestore`. Only `FirestoreSyncBackend`, the
  invoice-retrieval path and the team/invite repository (access control) touch it.
* Money is **integer paise**, quantities are **integer milli-units**, tax rates
  are **basis points**. No business amount is a `double`.
* Every business write and its outbox entry share one SQLite transaction.
* Finalized invoices are immutable. Corrections use cancellation, returns and
  credit/debit notes.
* Stock is an append-only ledger; the `inventories` row is a projection.
* Firestore rules independently enforce roles, immutability and idempotency.
* The database schema is unchanged by the features below, so the committed
  Drift code (`app_database.g.dart`) stays valid and CI does not need
  `build_runner`.

### Synchronization

* `sync_queue` is the durable outbox (`pending → syncing → synced | failed | conflict`).
* Documents use client-generated IDs, so a retried operation overwrites the same
  Firestore document instead of duplicating it.
* Remote writes fail with a conflict when the remote `version` is newer than the
  local `baseVersion`; applying a pull never overwrites an entity that has a
  pending local change.
* Backoff: 30 s → 2 m → 8 m → 30 m → 2 h → 6 h. App start, resume and a returning
  network connection trigger a run.
* A device switched off in **Team & devices** keeps working offline but stops
  exchanging data.

---

## 4. Feature guide

### Barcode and QR scanning
*Sales → scanner icon* adds products continuously (same product again = +1).
Also available on the product form (barcode field), purchase form, Inventory
(find a product's stock) and Search. *Invoices → scanner icon* opens a bill from
the QR printed on it. Every bill carries a small reference QR containing only
`buildstock://invoice/<bill number>`; no customer data is encoded. Camera
permission is requested on first use; you can always type the code instead.

### Photos and image hosting
Photos are compressed on the phone (JPEG, longest side 1280 px) and saved
locally, so every screen works offline. When a host is configured, they are
uploaded and the stored reference is swapped for the public URL, which then
syncs to every device. Firebase Storage is **not** used (Spark plan).

*Settings → Photo hosting*: choose **ImgBB** (API key from api.imgbb.com) or
**Cloudinary** (cloud name + an *unsigned* upload preset). Keys are stored on the
device only. They can also be supplied at build time:
`--dart-define=IMGBB_API_KEY=...` or
`--dart-define=CLOUDINARY_CLOUD_NAME=... --dart-define=CLOUDINARY_UPLOAD_PRESET=...`.
Pending uploads retry automatically on app start, resume and network return.

### Quotations, estimates and orders
*Checkout → Document* switches between **Invoice / Estimate / Quotation**.
Estimates and quotations never change stock and use their own number series
(`VBA-EST-…`, `VBA-QTN-…`). Open one and choose **Convert to invoice**: pick the
godown, optionally record a payment, and the new invoice is linked to the source.
*More → Customer Orders* tracks requests; **Create invoice from order** fills the
cart and marks the order *invoiced* after checkout.

### Credit and debit notes
*More → Returns & Credit/Debit Notes → New → Credit / debit note*.

| Type | Effect |
| --- | --- |
| Credit note (customer) | customer owes less |
| Debit note (customer) | customer owes more |
| Debit note (supplier) | you owe the supplier less |
| Credit note (supplier) | you owe the supplier more |

Notes never move stock. Balances, ledgers and the dashboard include them.

### Godowns
Sales and quotation conversion choose **Take stock from** (or *Automatic*, which
uses the largest balances first and splits across godowns when needed).
Purchases choose **Receive stock into**. Inventory can be filtered by location and
adjustments are made per location. Cancelling an invoice returns stock to the
exact location it left.

### Reports and Excel
*Reports → export menu*: one workbook with Sales, Purchases, Stock, Customer
dues, Supplier payables, Expenses, GST summary and Payments (this month or all
time), or single-purpose workbooks; sales CSV is still available.

### Low-stock notifications
*Settings → Low stock alerts*. Android 13+ asks for notification permission.

### Salary slips
*Salary → Slip* on any salary record: earnings, deductions, net pay, amount in
words, payment history and signature lines; print or share as PDF.

### Printing
*Settings → Printer & paper*:

* **Android print dialog** — A4 and any printer with an Android print service.
* **Network** — enter the printer IP (port 9100).
* **Bluetooth** — pair the printer in Android settings first, then choose it.
* **USB** — connect with an OTG cable and grant permission.

Direct printing renders the thermal bill as an image, so Tamil and the ₹ sign print
correctly. *Auto print after finalizing* is optional. Use **Test print** to verify.

### Backup and restore
*Settings → Backup & restore*: create a `.bsbackup` file (compressed, integrity
checked), restore from a file, or restore one of the last 7 automatic daily
backups. Restoring first saves a safety copy, keeps this device's identity and
never moves invoice number sequences backwards.

### Team and devices
*Settings → Team & devices* (owner/admin):

* **Invites** — enter the person's email and role; share the 10-character code
  (single use, 7 days).
* **Members** — change role, permissions or disable an account.
* **Devices** — enable/disable or remove a phone.

A new member signs in with the invited email and uses *Settings → Join a shop*.

---

## 5. Firebase setup

1. Firebase console → Project settings → **Add app → Android**, package
   `com.vijaybalaji.buildstock`.
2. Enable **Email/Password** authentication and create Firestore (production mode).
3. Copy the Android app ID (`1:...:android:...`) and either:
   * pass it locally: `flutter build apk --dart-define=FIREBASE_ANDROID_APP_ID=<id>`, or
   * in GitHub: **Settings → Secrets and variables → Actions → Variables →**
     `FIREBASE_ANDROID_APP_ID`. CI passes it automatically.
4. Deploy rules and indexes:

   ```bash
   firebase deploy --only firestore:rules,firestore:indexes
   ```

Without an app ID the app runs in full offline mode and Sync Center explains what
is missing. The web API key in `firebase_runtime.dart` identifies the project; it
is not a secret.

`firestore.rules` highlights: deny by default; every path scoped to an active
membership; append-only stock movements, payments, salary payments and audit
logs; finalized invoices immutable (an estimate may only be linked to the invoice
it became); credit/debit notes must carry `stock_action == 'none'`; invites are
single-use and email-bound; only the owner/admin may enable or disable devices or
change members; image metadata is writable by its owner or an admin.

---

## 6. Build, CI and release

### GitHub Actions

| Workflow | Trigger | Result |
| --- | --- | --- |
| `ci.yml` — *Build Android APK* | push, pull request, manual | `buildstock-apk` artifact; separate non-blocking *Analyze and test* job |
| `release.yml` — *Release* | tag `v*` or manual | GitHub release with the APK |
| `integration.yml` | manual | `integration_test` on an Android emulator |

The workflows pin **Flutter 3.47.9** (the version in `.metadata`), JDK 17, Android
SDK 36 and NDK 28.2.13676358, so builds are reproducible. The committed Drift and
localization code is used as-is; no code generation runs in CI.

Optional repository settings:

* Variable `FIREBASE_ANDROID_APP_ID` — enables cloud sync in CI builds.
* Secrets for a signed release (`release.yml`): `ANDROID_KEYSTORE_BASE64`,
  `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`. Without
  them the APK is debug-signed and still installs.

### Local build

```bash
flutter --version          # 3.47.9
flutter pub get
flutter build apk --release --no-tree-shake-icons \
  --dart-define=FIREBASE_ANDROID_APP_ID=<id>
```

JDK 17–24 is required for Gradle 8.14. After changing a Drift table or ARB file:

```bash
dart run build_runner build --delete-conflicting-outputs
```

---

## 7. Testing

```bash
flutter test                      # unit and widget tests
flutter test integration_test     # database-backed flows (device or emulator)
```

Unit tests cover money, quantities, GST arithmetic, invoice numbers, permissions,
the A4 invoice, invoice QR payloads, ESC/POS encoding and print settings, image-host
responses, backup validation, credit/debit note types, order lines, search
escaping, date conversion and salary-slip totals. Integration tests run search,
orders, credit/debit notes and backup/restore against an in-memory SQLite
database.

---

## 8. Project conventions

* Parse money with `Money.tryParseRupees` and store `int` paise; quantities with
  `Quantity.tryParseMilli`.
* New tables need a schema bump, a migration case and regenerated Drift code.
* New business writes call `Outbox.enqueue` in the same transaction.
* New Firestore collections need rules, indexes and a `SyncCollections` entry.
* Never commit `key.properties`, keystores, `google-services.json` or service
  account JSON.

---

## 9. Limitations and notes

* Cloud sync needs the Android Firebase app ID (section 5).
* Image upload needs an ImgBB key or Cloudinary preset; photos work locally
  without one.
* Direct Bluetooth/USB printing sends ESC/POS raster images; very old printers
  without raster support should use the print dialog. A4 always uses the dialog.
* Bluetooth printers must be paired in Android settings first.
* Backups hold this device's local data; copy them off the phone for safety.
  Cloud sync is a separate mechanism that shares data between devices.
* Run the Firestore rules in the Firebase emulator before production deployment.

---

Built for Vijay Balaji Agency. Source delivered to the business; no third-party
sample data is included.
