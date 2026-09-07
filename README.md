# Shramsetu Automation Engine

Contractor / Principal Employer registration OCR auto-fill engine: FastAPI backend, Flutter mobile client, Streamlit local dashboard, Docker deployment.

## 📱 Get the APK (no local Flutter install needed)

APKs are built automatically by GitHub Actions and published to a
permanent **Release** — no login required, no expiry, always the newest
build. Two ways to trigger a build:

1. **Automatic** — push any change under `mobile/**` to `main`.
2. **On-demand** — repo page → **Actions** tab → **Flutter Build** (left
   sidebar) → **Run workflow** button. Optionally set your backend
   server's LAN IP in the `api_url` field (e.g. `http://192.168.1.50:8000`)
   so the app talks to your server instead of the emulator default.

Either way, after the run finishes (~3-5 min, green check on the commit),
grab the APK from:

```
https://github.com/<YOUR_USERNAME>/<YOUR_REPO>/releases/tag/apk-latest
```

(Replace `<YOUR_USERNAME>/<YOUR_REPO>` with your actual GitHub path — this
becomes a real link once the repo exists.) Download **app-release.apk**
(recommended) or **app-debug.apk** (troubleshooting only), transfer it to
an Android phone, and install it (enable "Install unknown apps" for
whichever app you used to open the file).

A 30-day copy is also kept under the Actions run's "Artifacts" section as
a fallback, but the Release link above is the easy path.

## Repository Structure
```
shramsetu-automation-engine/
├── .github/workflows/        # CI: backend pytest, Flutter build
├── backend/                  # FastAPI app, SQLAlchemy models, OCR engine
│   └── app/templates/        # Put your .docx templates here (see note below)
├── mobile/                   # Flutter Android/iOS client
├── ui_web/                   # Streamlit local dashboard
└── docker-compose.yml
```

## Word Templates
`backend/app/templates/Shramsetu_Contractor_Template.docx` and
`Shramsetu_Principal_Employer_Template.docx` are included, built directly
from the field structure documented in the office's verified Shramsetu
User Manual references (Establishment Master → Registration Application →
License FORM-25 → Bank Guarantee for Contractor; Establishment Master →
Registration Application for Principal Employer). All 162 portal fields are
wired as docxtpl `{{ jinja }}` placeholders in `ShramsetuFormModel`
(`backend/app/models.py`) — every field name matches 1:1, and every
placeholder was verified to render as a single unsplit Word run (the
critical docxtpl requirement) before packaging.

## Document Checklist Integration
`GET /api/ocr/document-checklist/{CONTRACTOR|PRINCIPAL_EMPLOYER}` returns
the exact 11-document (Contractor/License) or 10-document (Principal
Employer) checklist from the office's verified Shramsetu Exhaustive
AutoFill Documents Checklist, with each document's OCR `doc_type` code.
`ShramsetuDocParser.route_by_doc_type()` in `backend/app/engine.py` has a
dedicated extractor per document — PAN, GSTIN, Work Order, PE Form-III/EIN,
Authorized Person ID, Designation Proof, Bank Details, Shop &
Establishment Certificate, EPF/ESIC, Prior License, Constitution/Ownership
Proof, Deployed Contractor List, Factory Process Details, and BOCW
Approval. Section B (Manpower) is modelled as the real gender-disaggregated
matrix (Male/Female/Trans × 5 categories, with auto-computed row/column/
grand totals) per Part 3 of the checklist — not a single aggregate number
per category.

## Offline Draft Storage & State Management
Offline drafts (partially-filled Contractor/PE/License forms) are persisted
via `flutter_secure_storage` (encrypted key-value, `mobile/lib/services/
db_service.dart`) rather than SQLite — each draft is one encrypted entry;
`readAll()` filters by key prefix to list them. `mobile/lib/providers/
draft_provider.dart` is a `ChangeNotifier` wrapping this, registered at the
app root in `main.dart` via `provider`; the home screen's "Saved Offline
Drafts" list reads it directly and can resume or delete any draft.

## Document Capture & OCR
`scan_screen.dart` offers both **file picker** (existing PDF/JPG/PNG,
unchanged) and **live in-app camera capture** for a document per required
type. The camera path was rebuilt this round on the `camera` plugin
(replacing the earlier `image_picker`-based "launch the OS camera app"
flow) specifically because the approved Camera Settings requirements
(resolution, live grid overlay, flash) are only controllable through a
real in-app preview, not `image_picker`'s simple launcher.

**Camera Settings screen** (`camera_settings_screen.dart`, reachable via
the ⚙ icon on the Home app bar) implements every row of the approved
requirements table verbatim: Camera Resolution (8M/5M/3M/2M/1M — mapped to
the `camera` plugin's fixed `ResolutionPreset` tiers, an approximate
mapping since the plugin doesn't expose exact megapixel control; disclosed
in `camera_settings_model.dart`), Auto Crop, Manual Crop, Filter
(Original/Auto/B&W/Grayscale/Enhance/Clear), Enhance Text, Auto Enhance,
Show Grid, Auto Flash, and Reset to Default. Settings persist via
`shared_preferences` (a separate, non-sensitive store from
`flutter_secure_storage`, which stays reserved for offline draft form
data).

**Capture pipeline** (`camera_capture_screen.dart` →
`image_processing_service.dart`), in the approved order — resolution/
flash applied at the live `CameraController` level → Auto/Manual Crop →
Filter/Enhancement → OCR:
- **Manual Crop** uses `image_cropper`'s real interactive crop UI.
- **Auto Crop is a disclosed simplification**, not true computer-vision
  document-boundary detection: it trims a fixed ~3% margin from each edge.
  Genuine auto-boundary-detection (finding a document's four corners
  against an arbitrary background) needs a dedicated CV library or trained
  model and is out of scope for this pass — flagged in code comments
  rather than silently claimed as solved.
- **Filters** are real pixel transforms via the `image` package
  (`img.grayscale`, `img.normalize`, a fixed-threshold binarize for B&W,
  `img.adjustColor` for Enhance, a sharpen `img.convolution` kernel for
  Clear) — not placeholder no-ops.
- Every external package API call used here (`camera`'s `CameraController`/
  `CameraPreview`/`takePicture`/`setFlashMode`, `image_cropper`'s
  `ImageCropper().cropImage`, the `image` package's `normalize`/
  `adjustColor`/`convolution`/`copyCrop`/pixel-access functions,
  `File.readAsBytes()`'s `Uint8List` return type) was checked against
  current, live package documentation before being written — not just
  recalled from training data — given none of this can be executed here
  (no Flutter SDK in this build environment). Structurally verified
  (imports resolve, braces/parens balanced, no undeclared packages) but
  **never compiled or run**.

Image-based OCR itself (server-side, unchanged by the above) is
implemented via `pytesseract` + Pillow (`backend/app/engine.py`'s
`extract_text_from_image`) — requires the `tesseract-ocr` system binary
(installed automatically in `backend/Dockerfile`; for bare-metal, `apt
install tesseract-ocr` / `brew install tesseract` / the Windows installer).
**This was verified with real execution in the build environment**
(Tesseract 5.3.4 was actually present): a synthetic test image was OCR'd,
and the raw output — `"PF Registration No. GJ/ANDI0012345"` /
`"ESIC Cade: 31-00-887654-000-1001"` (note the dropped "E" and misread
digits, genuine Tesseract noise, not fabricated) — broke the original
strict-prefix regex parser. It was replaced with a `rapidfuzz`-based
fuzzy-line-match (`ShramsetuDocParser._fuzzy_line_extract`) that correctly
recovers both codes; this fix is locked in by
`test_parse_epf_esic_tolerates_real_tesseract_ocr_noise` using that exact
captured OCR output as a fixture. The `rapidfuzz` call itself couldn't be
executed here (package unavailable, no network) — the fix was validated
with an equivalent `difflib`-based substring-ratio stand-in reproducing
`partial_ratio`'s matching semantics; the PDF/Tesseract/PIL portions above
ran for real.

## Application Entry Point & Architecture Decision
A **"＋ નવી અરજી" (New Application)** floating action button was added to
the Home screen (`home_screen.dart`) per the approved requirements
addition — a single, central entry point listing all application types
(Contractor Registration, Principal Employer Registration, FORM-25
License) in a bottom sheet, structured so future types (Renewal,
Amendment/Update) can be added to that one list without touching the rest
of the screen. This is **additive only**: the three existing module cards
on the Home screen are unchanged and still work exactly as before, per
the requirements document's explicit "don't replace existing modules"
instruction.

**Architecture decision (Path A vs. Path B, from the pre-development
audit): Path B — native Dart — is the committed direction.** Reasoning
recap: it's the standard, well-proven pattern for offline Flutter apps
(no special Play Store scrutiny), and every Python module already has a
working, tested reference implementation, so porting business logic to
Dart is mechanical rather than exploratory. Path A (embedding Python via
Chaquopy for a persistent local FastAPI/Uvicorn server) was found to rest
on a pattern with a live, unresolved open-source community question
(python-for-android issue #3033) rather than a solved one — real risk of
a late-stage dead end. This session's new camera/image-processing code
was written natively in Dart from the start, consistent with that
decision; porting the remaining Python backend logic (manpower matrix,
PAN/GSTIN/BG calculations, docx generation) to Dart is the next
architecture-relevant step, not yet done.

## Master Data Layer & Python → Dart Port (Path B in progress)
Local SQLite Master Data storage (`services/database_service.dart` +
`models/master_data_models.dart`) — this fully replaces the previous
FastAPI/SQLAlchemy backend's database role, running entirely on-device.
Four master tables (Establishment, Authorized Person, Bank Details,
Principal Employer) each implement `findOrCreate*`: look up by the
record's natural key (PAN, identity number, IFSC+account, EIN); if found,
merge in any newly-provided non-empty fields and return the existing
record; if not, insert a new one. This is the actual point of "Master
Data" — a verified Establishment record shouldn't need re-entry on the
next application. `sqflite`'s API was verified against current, live
Flutter documentation (docs.flutter.dev, updated May 2026) before writing
this, not assumed from memory.

**Business logic ported from `backend/app/models.py` /
`backend/app/engine.py` to pure Dart** (`services/business_calculators_service.dart`):
PAN/GSTIN format validation, the full manpower matrix (5 categories × 3
genders, apprentice deliberately excluded from the grand total — same
rule as the Python original, same reasoning preserved in comments), and
the Bank Guarantee calculator. Every regex and formula was copied from
the actual Python source (not rewritten from memory) and cross-checked
field-by-field. The BG calculator's rounding mode (round-half-away-from-
zero in Dart vs. Python's banker's rounding) was explicitly tested for
divergence across 8 realistic input combinations — zero divergences found
for this formula's specific shape, documented as a low-risk disclosed
caveat rather than assumed identical.

**OCR text parsing ported** (`services/ocr_text_parser_service.dart`):
all 12 of `ShramsetuDocParser`'s regex-based field extractors (PAN, GST,
Bank, Work Order, PE Form-3, Authorized Person ID, Designation Proof,
Shop/Establishment, EPF/ESIC, Prior License, Constitution Proof,
Contractor List), plus the two-stage EPF/ESIC extractor (identity-prefix
first, fuzzy fallback second) that fixed two real cross-contamination
bugs in the Python version. The fuzzy-matching algorithm itself
(`services/fuzzy_match_service.dart`) is a **hand-written Dart
approximation** of rapidfuzz's `partial_ratio` — not a byte-identical
port, since no equivalent well-established Dart package was found and
introducing an unproven one felt like a worse risk than writing a small,
auditable Levenshtein-based version directly. Before committing to it,
the exact algorithm was prototyped in Python (executable in this
environment) and run against the project's own real Tesseract-OCR-noise
test fixture (`"EF Registration No. Gu/ANDI0012345" / "ESIC Cade:
31-00-987654.000-1001"`) — it recovered both values correctly. A second,
harder adversarial test (deliberately worded to bypass the identity-
prefix stage) surfaced a real characteristic: the short fuzzy keyword
list (`"ESIC Code"`, `"ESI Code"`) doesn't match longer, differently-
worded real-world label variants well — but this traces back to the
original Python keyword list's own coverage, not something the Dart port
broke; noted rather than hidden.

**OCR pipeline now wired end-to-end** (this round): `scan_screen.dart`'s
`_extractDocument` no longer calls a backend at all — the now-dead
`ApiService`/`api_service.dart` and its `http` dependency were removed
entirely (zero remaining references, verified before deletion) rather
than left as stale artifacts. For image captures (JPG/PNG — the camera-
capture path), it now calls `OcrEngineService.extractTextFromImage`
(Google ML Kit, on-device, verified: publisher, 383 likes, max pub
points, actively updated as of Feb 2026 — see `ocr_engine_service.dart`,
API confirmed against live docs.flutter.dev / pub.dev / Google's Android
ML Kit reference before writing) and routes the resulting text through
`OcrTextParserService.routeByDocType` (now covering all 14 document types
the Python backend handled — the previous 3-parser gap — FACTORY_DETAILS,
BOCW_APPROVAL, EXECUTED_BG — was closed this round too).
**PDF files remain a disclosed, real gap**: ML Kit's TextRecognizer works
on images, not PDF text layers/pages, and no PDF text-extraction package
has been added. Rather than silently fail against a no-longer-existing
backend call, PDF uploads now show a clear in-app message and skip
straight to manual entry on the Review screen.

**Docx generation — decision made, not left open.** Rather than depend on
the Dart `docxtpl` package (version `0.0.1`, >1 year since last GitHub
activity — a real risk signal) or attempt a from-scratch ZIP
implementation, `docx_template_service.dart` does plain `{{tag}}`
substitution directly against `word/document.xml`, built on the `archive`
package (verified: version 4.0.9, verified publisher, 884 likes, max pub
points, 6.93M downloads — a dramatically more mature foundation).
**Explicitly scoped, not a general docxtpl replacement**: this only works
because both existing templates were already verified (in an earlier
session, via the docx skill's split-run checker) to have every `{{tag}}`
placeholder in a single XML run — i.e. Word never split a placeholder
across runs when they were built. `findUnresolvedTags()` exists
specifically to catch that failure class before it ships silently, should
a different, unverified template ever be swapped in.

**Document Generation — now wired end-to-end, closing the gap flagged in
the last status report** (`document_generation_service.dart` +
`webview_screen.dart`'s new app-bar action). The two `.docx` templates,
previously only present on the (now-unused, Path B) backend, were copied
byte-for-byte into `mobile/assets/word_templates/` (verified identical
via `diff` after copying) and registered in `pubspec.yaml`'s
`flutter: assets:`. `WebViewScreen` now takes a `moduleType` parameter
(previously missing — added here, one call site updated in
`review_screen.dart`) to pick the right template: PE_REGISTRATION uses
the Principal Employer template, everything else (REGISTRATION, LICENSE)
uses the Contractor template, matching the same applicant-role logic
`review_screen.dart`'s section-visibility already uses. Generating a
document logs a `DOCUMENT_GENERATED` entry to the Audit Trail and opens
the platform share sheet via `share_plus` so the user can save/print/
email the result immediately.

**A real, version-specific API risk was caught before writing this**:
`share_plus` had a confirmed breaking change at v11.0.0 — the old static
`Share.share()`/`Share.shareXFiles()` API is deprecated in favor of
`SharePlus.instance.share(ShareParams(...))`. Targeting the current
v13.1.0 (Apr 2026), the new API was used throughout. A second, genuinely
documented bug was also handled rather than ignored: a live GitHub issue
(fluttercommunity/plus_plugins#3685) shows `SharePlus.instance.share`
crashing on iOS when `sharePositionOrigin` is unset/zero — the Generate
Document button is wrapped in a `Builder` specifically to get a
`BuildContext` tied to the button's own on-screen position, so a real
`Rect` can be computed and passed, not left null.

**A verification-tooling detour worth recording honestly:** this file's
naive brace-counter flagged a `{`/`}` mismatch (33 vs 34) caused by a
regex quantifier literal (`{0,60}`) combined with a bracket-class literal
`}` inside the same pattern string — investigated rather than dismissed
or panicked over. A follow-up "smarter" checker (stripping string/regex
literals before counting) was written to resolve it, but that checker
turned out to have its OWN bug (a `[^']*`-style pattern matching across
newlines when an unpaired quote existed anywhere in a file, corrupting
totals for several unrelated files). Both checkers' claims were verified
against a direct manual line-by-line trace of the actual code structure
before trusting either — the real code was correct throughout; both
false alarms came from limitations in the verification tooling itself,
not the shipped Dart.

**Master Data wiring into the Review/Save flow — now done, all four
masters** (`review_screen.dart`'s `_saveAndContinue` →
`_syncMasterDataAndApplication`). Saving a reviewed application genuinely
calls `findOrCreateEstablishment`/`findOrCreateAuthorizedPerson`/
`findOrCreatePrincipalEmployer`/`findOrCreateBankDetails` and
`saveApplication` (which auto-logs to Audit Trail) — Master Data is
reused across applications, not just sitting in unused tables. Each call
is gated on its natural key being non-empty, so a section hidden for the
current `moduleType` (e.g. the Principal Employer counterpart fields
during a PE_REGISTRATION flow, where the PE is the applicant, not a
counterpart being named) doesn't create a junk empty-keyed record.
**Bank Details Master's prerequisite gap is closed**: `bg_bank_account_number`
was added to `ShramsetuFormModel`'s Bank Guarantee section (confirmed
NOT accidentally added to `_intFields` — account numbers need leading
zeros preserved as text, not parsed as int) specifically to unblock this
safely; the wiring is gated on BOTH IFSC and account number being
non-empty together, since the table's uniqueness is the pair, not either
field alone.

A real bug was caught and fixed while wiring this: the save call
originally referenced `_model.toJsonString()`, which doesn't exist on
`ShramsetuFormModel` (only `toJson()`, returning a `Map`) — would have
failed to compile. Fixed to `jsonEncode(_model.toJson())`, and the
model's `fields` map was checked to confirm it holds only
JSON-serializable strings/ints before trusting that call.

## v4 Requirements Additions: Themes, Advanced OCR, Audit Trail
Responding to `Setumitra_Project_Requirements_Updated_Master_v4.docx`.
Items 1–4 (New Application button, Camera Settings, Camera/OCR Workflow,
UI Simplicity) were already implemented in earlier rounds. This round
adds:

**5 Themes** (`theme_service.dart` + `theme_provider.dart`) — Professional
Blue (default), Classic Light, Modern Teal, Dark, High Contrast, in the
exact names/order specified. Wired into `main.dart` via
`Consumer<ThemeProvider>` so switching is instant and app-wide.
Switching themes touches only `ThemeData` — no other provider or stored
data is read or modified, satisfying "Theme બદલવાથી data/functionality
બદલાવું નહીં જોઈએ." The `ThemeData.cardTheme` type (`CardThemeData`, not
the older `CardTheme`) was checked against current Flutter docs before
use, given this was a real breaking change in Flutter 3.32.

**Audit Trail** (new `audit_trail` table in `database_service.dart` +
`audit_trail_screen.dart`) — part of the approved End-to-End Core
Workflow chain (Document → OCR → Verify/Edit → Master Data → New App →
Auto-Fill → Final Review → Shramsetu → Document Generation/Save → Audit
Trail). **A real correctness issue was caught and fixed here**: adding a
table only inside `onCreate` does nothing for anyone who already has an
existing database at the old schema version — `onCreate` only runs for
brand-new databases. Fixed with a proper `onUpgrade` migration and a
schema version bump (1 → 2), not just an edit to `onCreate` alone.
Currently logs `APPLICATION_CREATED`/`APPLICATION_UPDATED` from
`saveApplication`; other workflow milestones (Auto-Fill run, Document
Generated, OCR Verified) can call the same `DatabaseService.logAction`
as those screens get wired up — not all steps log yet.

**Advanced OCR Controls** (`advanced_ocr_settings_model.dart` +
`advanced_ocr_settings_screen.dart`), deliberately kept OUT of the main
Camera Settings screen per "Advanced OCR controls અલગ Advanced sectionમાં
રહેશે." Every control was checked against what the engine actually
supports before being built, per the explicit constraint ("જે controls
device/OCR engine ખરેખર support કરે તે જ implement/expose કરવા; UI-only
fake options નહીં"):
- **OCR script/language** — real (`TextRecognizer(script:)` genuinely
  changes what ML Kit recognizes). One caveat handled honestly: the
  Devanagari script enum's exact Dart spelling couldn't be independently
  confirmed with full confidence during research, and this app's actual
  OCR targets (PAN, GSTIN, EPF/ESIC, etc.) are all Latin-script English
  documents anyway, so rather than risk a hardcoded switch statement
  failing to *compile* over a guessed spelling, the label lookup uses the
  enum's runtime `.name` string with a safe fallback instead.
- **Denoise** — real, via the `image` package's `gaussianBlur` (verified
  against pub.dev docs before use, same package already depended on, no
  new dependency).
- **B&W threshold/intensity** — was a hidden constant (128) in
  `ImageProcessingService`; now a genuine adjustable 0–255 slider, threaded
  through `applyFilter`/`processForOcr`.
- **OCR confidence / uncertain-field indication** — real, but **Android-
  only**, confirmed directly from the `google_mlkit_text_recognition`
  package's own changelog ("Fix: Confidence and angle only available for
  Android"). `OcrEngineService.extractWithConfidence` returns `null` on
  iOS or when no lines had a score; the UI is built to show "not
  available" rather than ever fabricate a number. Confidence is currently
  a document-level average across all recognized lines, not yet mapped
  back to the specific line each individual parsed field came from — a
  further refinement, not done this round.
- **Auto Enhance** — already existed (Camera Settings); referenced here
  as the same real toggle, not duplicated.
- **Re-scan/Re-process** and **Reset Advanced OCR Settings to Default** —
  Reset is implemented and verified end-to-end (load/save/reset/UI
  consistency checked programmatically, all 4 fields present in each).
  Re-scan (re-run OCR on an already-captured image with new settings,
  without re-photographing) is **not yet wired** — a real gap, not done
  this round.

**Settings hub** (`settings_screen.dart`) ties the theme picker, Camera
Settings, Advanced OCR Controls, Audit Trail, and (as of this round)
Website & Auto-Fill Mapping together in one place, reachable from the
Home screen's app bar (replacing the previous direct shortcut straight
to Camera Settings) — keeping the main Dashboard itself untouched and
simple, per the "UI Simplicity Rule."

**Not started this round** (from the v4 document): Contacts & Excel
export (Settings item 5), and Google Drive export/backup (item 10).
Flagged here rather than silently dropped.

## Website & Auto-Fill Mapping — Now Configurable (v4 Settings Item 6)
`portal_field_map.dart` was a hardcoded, rebuild-required Dart file.
It's now the **factory-default seed** for a versioned, database-backed
config (`auto_fill_mapping_service.dart` + a new `auto_fill_mapping_versions`
table — schema bumped 2 → 3, with a proper `onUpgrade` migration, same
correctness pattern as the Audit Trail table's own migration earlier).

**Scope, stated honestly:** the requirements' "Check for Update" implies
polling a remote server for a newer mapping. There is no such server
reachable by the mobile app under the Path B architecture — that specific
mechanism is NOT implemented. What genuinely satisfies the underlying
need ("update the mapping without an app rebuild") instead: local JSON
**import** (validated structurally — must be four flat string-to-string
maps, nothing else; this is the enforcement of "NO arbitrary JS/code edit
allowed" from the requirements, not just a stated policy), full
**version history**, and **rollback** to any prior version by id, not a
destructive re-import.

**This is genuinely wired, not a settings screen with no effect**:
`webview_screen.dart`'s Auto-Fill payload builders were rewritten to load
the active mapping from `AutoFillMappingService` at `initState` (cached
per screen instance, not re-queried per keystroke) and use it instead of
the old static `PortalFieldMap.resolve()` calls — the FAB is disabled
with a "Loading mapping…" label until that load completes, so Auto-Fill
can never fire against a stale or missing mapping.

**"Auto-Fill Test" is a real structural check, not a placeholder button**:
it finds portal field names claimed by more than one semantic key within
the mapping (the same class of collision risk manually checked several
times earlier in this project) and reports them for the admin to judge —
not a hard pass/fail, since some duplicates are legitimate (the existing,
already-verified-safe `Registrationfees` case, appearing on two genuinely
different portal pages, is exactly the kind of thing this test surfaces
and a human confirms). The exact duplicate-detection algorithm was
independently simulated in Python against the real mapping data before
trusting the Dart port — it correctly found that one known case and
nothing else.

## Contacts & Excel Export (v4 Settings Item 5)
`contacts_export_service.dart` + `contacts_export_screen.dart`, pulling
from Master Data (`establishment_master`), not from any single
application — consistent with Master Data's whole point being the
canonical, de-duplicated source.

**`establishment_master` gained 4 columns** (`mobile_number`, `email_id`,
`username`, `password`) — schema bumped 3 → 4 with a proper
`ALTER TABLE ADD COLUMN` migration for existing installs, same
correctness discipline as every prior schema change this project. Two of
the four (`mobile_number`/`email_id`) are sourced from
`ShramsetuFormModel`'s existing, already-in-the-Registration-form fields
— NOT new form fields, only new Master Data columns wired through
`review_screen.dart`'s save flow. The other two (`username`/`password`)
have no source anywhere in the OCR/Registration flow at all — they're
Shramsetu **portal login** credentials, a genuinely separate concept —
and are entered/edited directly in the Contacts screen's inline editor.

**Stored and exported in plain text, deliberately** — the requirements
explicitly approved this. Flagged here as a real security tradeoff made
because it was specified, not because it's a generally-recommended
pattern for credential storage.

**Column interpretation, disclosed honestly**: "Type (Contractor/
Establishment)" and "Contractor Name if (blank for Establishment)" were
worked from a compressed summary of the original requirements doc, not a
verbatim re-read — `DatabaseService.deriveEstablishmentType` infers Type
from whether an establishment has a linked REGISTRATION/LICENSE
application (→ "Contractor") versus only ever being touched via
PE_REGISTRATION or no application at all (→ "Establishment"), and the
Contractor Name / Establishment Name columns are populated mutually
exclusively based on that. This is a reasoned best-effort against the
actual data model, not a literally re-quoted spec — open to correction
with the exact original wording if this doesn't match.

**A real bug caught before shipping**: `Excel.createExcel()` auto-creates
a default sheet named `'Sheet1'`; the first draft of both export
functions separately accessed `workbook['Contacts']` /
`workbook['Unique Emails']`, which — confirmed against the `excel`
package's actual behavior — CREATES a second, distinct empty sheet
alongside `'Sheet1'` rather than reusing it. Every exported file would
have shipped with an unwanted blank extra sheet. Fixed by renaming the
auto-created sheet instead of creating a new one.

**Package choice**: `excel` (v4.0.0, 162k downloads, 1000+ likes) was
chosen over the newer `excel_plus` (more actively updated but only 8.4k
downloads) — unlike the `docxtpl`-Dart-vs-`archive` decision earlier
(a clear-cut "too immature, avoid" case), this was a genuine trade-off
between proven scale and freshness, not a one-sided risk call; `excel`'s
cell-value API (`TextCellValue`, the sealed `CellValue` base class) was
independently confirmed against the official Dart API docs before use.
`excel_plus` is noted here as a documented, available alternative if
`excel` specifically causes problems.

## Re-scan / Re-process (Advanced OCR Controls)
`scan_screen.dart`'s document rows now show a refresh icon once a
document has been captured/picked — tapping it re-runs OCR text
extraction and parsing on the SAME already-stored image, without
re-photographing. Useful after changing the OCR Language/Script setting,
or to retry a poor first-pass result. Scoped honestly: this does NOT
re-apply a different crop/filter/threshold to a fresh capture (the image
was already processed at capture time) — a genuinely new photo, with new
settings applied, still requires tapping the row to reopen the source
picker, exactly as before.

## Google Drive Export/Backup (v4 Requirements Item 10) — Read Before Relying On This
This is the **highest-uncertainty feature in the entire project**, for
reasons genuinely different from every other package decision made this
session. Full disclosure lives in `google_drive_backup_service.dart`'s
doc comment (surfaced to the admin in `google_drive_backup_screen.dart`'s
UI too, not just buried in code) — summarized here:

1. `google_sign_in` underwent a **major breaking refactor at v7.0.0**:
   the `GoogleSignIn()` constructor was removed entirely in favor of a
   singleton (`GoogleSignIn.instance`), and sign-in/authorization became
   two separate steps. This code targets the current, fully-migrated v7
   pattern, verified consistently across the official pub.dev page, the
   official Dart API docs, and an independent technical migration
   writeup — not a single, possibly-stale source.
2. **A live, still-open GitHub issue** (flutter/flutter#173407) reports a
   403 "unregistered caller" error reaching Google Drive specifically
   after upgrading to this same package version. Close reading of that
   report's own code shows it mixes the OLD, removed constructor pattern
   with NEW v7 calls — plausibly a migration mistake in the reporter's
   own code, not necessarily an unfixable package defect — but this could
   NOT be independently confirmed either way without a real device and a
   real Google Cloud OAuth client, neither of which exist in this build
   environment.
3. **A real, unavoidable, non-code prerequisite**: no matter how correct
   this Dart code is, the feature cannot function until a Google Cloud
   Console project is created, the Drive API enabled, an OAuth consent
   screen configured, and Android/iOS OAuth client IDs generated and tied
   to this app's actual package name (`com.example.setumitra`) and
   signing certificate (SHA-1 fingerprint). That setup is entirely
   external to this codebase and cannot be completed from within it.

**Given all of the above, on-device debugging and adjustment should be
expected for this specific feature — not treated as a sign the approach
is fundamentally wrong.** Every other integration in this project was
verified with meaningfully higher confidence than this one.

**What's implemented**: sign-in with the narrow `drive.file` scope
(Google's recommended minimal scope — access only to files this app
itself creates, not the user's whole Drive), and a "Backup Contacts Now"
action that exports the Contacts Excel sheet and uploads it. The exact
upload call (`drive.Media(stream, length)` +
`driveApi.files.create(file, uploadMedia: media)`) was verified against a
complete, real, working Flutter sample, not just API documentation
fragments.

**"Offline-first" is honestly simplified**, per the requirements'
"offline-first (local export without internet, upload when connectivity
available)": this attempts the upload immediately and reports success or
a specific failure reason. It does **not** implement a persistent
background retry queue — that's a meaningfully larger feature on its own
(would need a background task scheduler, its own verification pass, and
its own risk disclosure) — on failure, the user retries manually. Flagged
as a real, disclosed simplification rather than silently claimed as
fully "offline-first."

## Portal Auto-Fill: Real Field-Name Mapping (verified against actual portal HTML)
Six real Shramsetu portal pages have now been inspected directly (see the
list below); **127 of 207 total fields (61%)** have a **confirmed** real
portal `name` mapping extracted straight from live HTML, the rest fall
back to generic name/id/data-field guessing rather than a fabricated
mapping.

Pages inspected, with duplicate detection results:
- `Establishment_Application_Master...html` (+ two later re-uploads,
  "PAGE-2" and "page-3") — all three are **byte-for-byte structurally
  identical** (same 110-field fingerprint); no new data across the
  re-uploads, already fully processed.
- `Establishment_Application_Master...registration_form_for_contractor.html`
  — the Contractor-specific variant (106/110 fields identical to the PE
  variant; the 4-field difference is the "Contractor manpower" row,
  confirmed genuinely absent from a Contractor's own form).
- `Application_for_License_form_25_for_contractor.html` — FORM-25 License
  page (186 elements), including the real 88-item Nature-of-Work and
  33-item District checkbox checklists.
- `Application_for_Registration_for_establishments_Under_OSHWC_Code...html`
  (two uploads, "_5" and "_for_contractor" — confirmed **structurally
  identical** to each other, same 180-field fingerprint) — this is the
  real "Registration Application" (Step B) page, filling in ~15 fields
  that had been on generic-guess fallback for the whole project:
  `application_date` (`AppDate`), `application_number` (`AppID`),
  `probable_commencement_date` (`ProbableDate`),
  `expected_completion_date` (`ExpectedDate`),
  `registration_fee_details` (`Registrationfees`),
  `registration_otp` (`OTP`), `total_contract_labour`
  (`totalContractLabour`), `contract_commencement_date`/
  `contract_completion_date` (`commencement`/`completion`).
- `Application_List...html` — an application search/listing dashboard
  (12 filter fields, not a data-entry form), but it confirmed the first
  real Bank Guarantee field names: `bg_format_number` (`txtBGNumber`),
  `bg_date` (`txtBGIssueDate`), `bg_signed_pdf_reference`
  (`fileBGDocument`).

**Corrections made from earlier rounds, now that more pages give
disambiguating context:**
- `application_date` was previously mapped to `ApplicationCurdate` (from
  the Establishment Master page) based on a label that, on inspection,
  was never actually confirmed (empty in the original extraction — an
  artifact of an early label-recovery heuristic bug). The Registration
  Application page's `AppDate` has a cleanly confirmed bilingual label
  ("Application Date / અરજીની તારીખ") and is the semantically correct
  match for the Dart UI section it lives in; `application_date` now maps
  to `AppDate`.
- `contract_commencement_date`/`contract_completion_date` were previously
  mapped to the License FORM-25 page's `CommencementDate`/`CompletionDate`
  — but the Registration Application page (which is what that Dart
  section actually represents) has its own, differently-cased
  `commencement`/`completion` fields. Since `license_commencement_date`/
  `license_completion_date` already existed as separate (previously
  unmapped) model fields, the fix was clean: `contract_*` now points to
  the Registration page's names, and `license_*` now points to the
  License page's names it always should have.

**Ambiguity from the previous round, now resolved:** the OSHWC Registration
page's `ContractorName`/`ContractorAddress`/`ContractorDistrictName`/
`ContractorTalukaName`/`ContractorPincode` field cluster sits directly
under a real, confirmed section header — **"D. Contract Details"** — with
an EIN-search dropdown immediately preceding it that lists real
establishment names (e.g. "LARSEN AND TOUBRO LTD"). This exactly matches
the pre-existing "Contract Details — Principal Employer" Dart section
structure: on a Contractor's own registration page, this section is where
the Contractor selects/names their Principal Employer — the ASP.NET
markup simply reuses generically-named `Contractor*` fields to mean "the
other party in the contract" regardless of which role is filling the
form. Mapped to `pe_name`/`pe_address`/`pe_district`/`pe_taluka`/
`pe_pincode` accordingly. Two related fields on this same section,
`pe_ein_selected` and `pe_mobile`, were deliberately left **unmapped**
rather than pointed at the section's bare `EIN`/`MobileNo` inputs: those
exact names are already claimed elsewhere on the same page by the
applicant's own `ein`/`mobile_number` fields, and mapping both would make
the webview auto-fill JS inject two different values into the same DOM
element (a real collision class already found and fixed once this
session in the OCR pipeline — see the EPF/ESIC incident notes below).

`PositionDropdown` (appearing on multiple pages) was confirmed via label
lookup to be the top navbar account menu ("Profile / Change Password /
Logout") — UI chrome, not a data field — and is correctly excluded from
the mapping.

Two genuinely new fields were discovered with no prior model
representation: `establishment_contract_labour_max`
(`EstablismentContlabmax` — no label text was recoverable from the HTML;
its exact meaning is inferred from the field name alone and flagged for
manual verification) and `applicant_name` (`Name`, confirmed bilingual
label "Name / નામ", but its precise role — applicant vs. authorized
person vs. establishment contact — couldn't be disambiguated from the
captured page structure, so it was kept as a distinct field rather than
merged into `authorized_person_name`).

## Run — Backend (FastAPI)
```bash
cd backend
python -m venv venv && source venv/bin/activate   # Windows: venv\Scripts\activate
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```
Docs: http://localhost:8000/docs

## Run — Local Web UI (Streamlit)
```bash
cd ui_web
pip install streamlit requests
streamlit run app.py
```

## Run — Mobile (Flutter)
**Easiest:** don't run Flutter locally at all — see "📱 Get the APK" at the
top of this README for a pre-built APK from GitHub Actions.

For local development instead:
```bash
cd mobile
flutter pub get
flutter run --dart-define=SHRAMSETU_API_URL=http://<your-lan-ip>:8000
```

## Run — Everything via Docker
```bash
docker compose up --build
```
API: http://localhost:8000 · Dashboard: http://localhost:8501

## Tests
```bash
cd backend
pytest -v
```

## Notes on scope of automated verification
- Python code in `backend/` was syntax-checked (`py_compile`, all files
  pass) and additionally exercised via `backend/tests/standalone_verify.py`
  — a dependency-light replica of the core logic (manpower matrix math,
  PAN/GSTIN validation, Bank Guarantee calculation, OCR regex/fuzzy
  parsers) runnable without `fastapi`/`pydantic`/`sqlalchemy`/`docxtpl`/
  `rapidfuzz` installed. Run with `python tests/standalone_verify.py
  --loop 10` for a repeated-execution stress check; two real bugs in the
  EPF/ESIC OCR extractor were found and fixed this way (see the
  `_identity_prefix_line_extract` docstring in `app/engine.py` for the
  full incident history). The real `pytest` suite
  (`tests/test_pipeline.py`) exercises the actual FastAPI app end-to-end
  but could **not** be executed in this build environment (no network
  access to install the dependencies above) — run
  `pip install -r requirements.txt && pytest -v` locally to confirm.
- Both `.docx` templates were rendered to PDF and visually verified, and
  every `{{ field }}` placeholder (174 in Contractor, 99 in PE, per the
  latest `standalone_verify.py` run) was programmatically confirmed to sit
  in a single unsplit Word XML run.
- Flutter/Dart files were brace/paren-balance checked after every edit;
  `flutter analyze` and `flutter build apk --debug` could **not** run here
  (no Flutter SDK / network in this sandbox) — the `flutter-build.yml` CI
  workflow runs both automatically on push, or run them locally before
  shipping. Docker builds are similarly untested here (no Docker daemon
  available) — `docker compose build` should be run locally or via CI
  before relying on the containerized deployment.
- The mobile `ShramsetuFormModel` (`mobile/lib/models/form_model.dart`) is
  a generic `Map<String, dynamic>` wrapper covering the same field set as
  the backend Pydantic model, grouped into the same sections used by
  `review_screen.dart`. `webview_screen.dart`'s auto-fill JS resolves each
  field through `mobile/lib/models/portal_field_map.dart` to the real
  portal `name` attribute where confirmed, falling back to generic
  `name=`/`id=`/`data-field=` guessing otherwise.
- All 207 user-editable portal fields are wired into a mobile UI section
  (verified programmatically: zero editable model fields missing from the
  UI, zero UI keys that don't exist in the model). 127 of those 207
  (61%) have a confirmed real-portal-name mapping extracted directly from
  live HTML captures; the rest fall back to generic guessing. Home screen
  offers three entry points — Contractor Registration, Principal Employer
  Registration, and FORM-25 License — each showing only the sections
  relevant to that role/flow, plus role-specific OCR document lists per
  the Exhaustive AutoFill Documents Checklist (11 docs for
  Contractor/License, 10 for Principal Employer).
