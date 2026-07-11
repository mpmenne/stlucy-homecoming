# Volunteer Signup Service

Rails API powering the sign-up page on
[stlucyhomecoming.com/volunteer](https://stlucyhomecoming.com/volunteer/).
**The parish Google Sheet is the entire datastore** — organizers manage
capacity and see every signup right in the sheet.

- `GET /api/slots` — 2-hour slots per booth/day with capacity, everyone
  signed up (names as "First L."), open counts, chair assignments, and crew
  lists. Emails/phones never leave the server.
- `POST /api/signups` — booth shift for a start/end range (capacity-checked
  per slot, duplicate-checked, honeypot spam guard)
- `POST /api/chairs` — full-day booth chair signup
- `POST /api/crew` — join the Setup (Friday) or Teardown (Monday) crew

## The sheet — built for you by `rake sheet:setup`

```bash
# one time, or to rebuild (FORCE=1 wipes + recreates the tabs listed below):
docker compose run --rm app bundle exec rake sheet:setup
FORCE=1 docker compose run --rm app bundle exec rake sheet:setup
# customize: BOOTHS="A;B;C" DAYS="Saturday;Sunday" NEED=2 OPEN="9:00 AM" CLOSE="9:00 PM" SLOT_MINUTES=120
```

| Tab | Role |
|---|---|
| `Slot Needs` | **Organizers edit**: volunteers needed per booth per 2-hour slot. This is what makes slots appear/disappear on the site. |
| `Signups` | App appends one row per shift signup (dropdown-validated columns). |
| `Volunteer Matrix` | Live formula view of who's working when — don't edit. |
| `Booth Chairs` | One row per chaired booth-day; app appends chair signups. Add rows by hand for chairs recruited offline. |
| `Setup & Teardown` | The crew list; app appends. |

Any other tabs (e.g. `Schedule`) are ignored and untouched.

## Setup

1. `cp .env.example .env`, set `SHEET_ID` and `SECRET_KEY_BASE` (`openssl rand -hex 64`).
2. Service account key at `credentials/service-account.json` (gitignored),
   sheet shared with the service account's email as **Editor**.
3. `docker compose run --rm app bundle exec rake sheet:setup`
4. Tunnel (one time): `./scripts/setup-tunnel.sh`. Note: this network blocks
   QUIC, so `cloudflared/config.yml` needs `protocol: http2` (re-add it if
   you ever recreate the tunnel config; symptom is Cloudflare error 1033).
5. `docker compose up -d --build`, then
   `curl https://signup.stlucyhomecoming.com/healthz` → `ok`.

## Local development

```bash
bundle install
set -a && source .env && set +a
export GOOGLE_APPLICATION_CREDENTIALS=credentials/service-account.json
bin/rails s   # http://localhost:3000
```

Point the volunteer page at it: set `signup_api: "http://localhost:3000"` in
`_config.yml` and run `jekyll serve`.
