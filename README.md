# NiyuktiAI

**Upload once. Apply smarter.** An assistant that finds Indian government job
notifications, works out which ones you are actually eligible for, and fills in
their application forms from documents you have already confirmed.

You still press Submit. You still pay the fee. Those are yours, deliberately.

---

## Running it

```powershell
powershell -ExecutionPolicy Bypass -File start.ps1    # then http://localhost/
powershell -File stop.ps1
```

Three processes come up. The front end is not one of them — it is files on
disk that nginx serves directly.

| | | |
| --- | --- | --- |
| `backend/` | FastAPI + RapidOCR + Claude Opus 5 — reads documents, holds the vault, scans the job boards, answers the chat | `:8765` |
| `runner/` | Node + Playwright — opens the real portal, streams it into the page, fills the forms | `:8766` |
| `web/` | Static HTML, CSS and Bootstrap 5 — the whole front end | served by nginx on `:80` |

nginx puts all three on one origin: the pages call `/v1/…` and `/runner/…`, so
there is no CORS, no API base to configure per environment and no key in the
page. Its configuration is `deploy/niyuktiai.conf`.

Logs land in `.run\`.

---

## The front end

No framework, no bundler, no build step. `web/*.html` **are** the site — edit
one and reload.

```
web/
  index.html  login.html  onboarding.html        the public pages
  dashboard.html  jobs.html  job.html  apply.html
  live.html  assistant.html  applications.html  application.html
  documents.html  profile.html  alerts.html  settings.html

  assets/css/
    tokens.css        colour ramps, type scale, radii, elevation
    base.css          the reset, typography, icon sizing, Bootstrap wiring
    components.css    buttons, badges, cards, forms, modals, toasts
    shell.css         the nav rail, the topbar, the mobile bar
    pages.css         one banner-marked section per page
    landing.css       the public surface, scoped to [data-surface="public"]

  assets/js/
    core/     api.js   talking to the two services
              ui.js    icons, toasts, the rail, the theme
    data/     eligibility.js  jobs.js  profile.js  applicant.js  applications.js
    live/     session.js  portal.js
    pages/    one file per page, named after the page
    landing/  landing.js  legal.js

  assets/vendor/      Bootstrap 5.3.8 and Font Awesome 7, vendored — no CDN
```

Two rules worth knowing before editing:

- **Bootstrap is configured, not overridden.** Its custom properties are
  pointed at our tokens in `base.css`, so a `.btn` or a `.card` picks up the
  product's palette without a single `!important`.
- **Nothing hardcodes a colour.** Every value comes from `tokens.css`.

---

## What is real

Everything on screen comes from the two services. There is no seeded data and
no demo mode behind the login.

- **Jobs** are scanned hourly from SSC and APPSC's own portals, FreeJobAlert
  and Sarkari Result, classified by Claude, then enriched from each issuer's
  own notification PDF. Every job links to its source.
- **Your details** are read from the documents you upload — a Class 10
  marksheet becomes an education record, a caste certificate sets the category.
  The profile starts blank.
- **The match percentage** is computed by `data/eligibility.js` from your own
  age, qualification, category and documents. The same function feeds the
  card's ring, the job page's panel and the pre-application checklist, so those
  three can never disagree.

### Nothing is invented

A board line often does not say what a post requires. That gap is carried as a
flag, not filled with a guess:

- an unstated qualification is `qualificationKnown: false` and reads "see the
  official notification" — it is never defaulted to a value that would score as
  satisfied;
- an unstated closing date is `lastDateKnown: false` and shows no countdown;
- a fee row whose label is not a fee is dropped rather than printed as money.

An earlier version defaulted the qualification to "10th Pass" and every job
then matched at nearly 100%. That is the failure this rule exists to prevent.

---

## What the product will not do

Stated here because they are not settings:

- **Nothing is submitted without you.** The final Submit on any portal is yours.
- **Payments are yours.** A fee is paid by you, on the portal, with NiyuktiAI
  telling you what it is for.
- **Passwords, OTPs and captchas are never stored.** They are typed once into
  the portal and never reach a log or a file.
- **Aadhaar and PAN are filled and shown in full in the app's own preview** —
  the preview exists so you can check the number typed is yours, and a row of
  dots checks nothing — but stay masked in logs and run history.
- **The portal runs on your computer.** Your documents are read here and go to
  the government portal, nowhere else.

---

## Signing in

Google, through the document service (`backend/app/routers/auth.py`). Set in
`.env.local`:

```
AUTH_GOOGLE_ID=…
AUTH_GOOGLE_SECRET=…
AUTH_SECRET=…                      # also signs the account token
AUTH_ALLOWED_EMAILS=a@b.com,…      # unset means open, which is only right on a laptop
AUTH_URL=https://your.domain        # pin it when behind a proxy
```

Register `<origin>/v1/auth/callback` as an authorised redirect URI against the
OAuth client — one per origin you use.

Each signed-in account gets its own vault under `backend/vault/accounts/<id>/`,
named by a hash of the email. With no sign-in configured everything lives in
one local vault, which is how a laptop install works.

---

## Testing

```powershell
cd runner
npm test          # the portal gate and the fill-verification rules
npm run selftest  # a whole application run against the practice portal
cd ..\backend
.venv\Scripts\python.exe -m pytest
```

`RUNNER_DEMO=1` (which `start.ps1` sets) keeps the runner's own practice portal
available in Live Working — a full run, login and OTP and payment included,
that never leaves the machine.
