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
3. `docker compose run --rm app bundle exec rake sheet:setup` — skip if the
   sheet already has the tabs (the task aborts rather than clobber them).
4. Tunnel (one time): `TUNNEL_NAME=<per-machine-name> ./scripts/setup-tunnel.sh`.
   Tunnel names are unique per machine (e.g. `stlucy-signup-home`) — creating
   a fresh tunnel and letting `--overwrite-dns` take over the hostname is how
   you move hosting to a new machine. The script writes `protocol: http2`
   into `cloudflared/config.yml` (this network blocks QUIC; symptom of
   running without it is Cloudflare error 1033). Caveat: the script reuses
   `cloudflared/cert.pem` if present — that cert is zone-scoped, so if it was
   issued for a different zone the DNS route lands in the wrong zone and the
   `signup` CNAME must be pointed at `<tunnel-id>.cfargotunnel.com` via the
   Cloudflare dashboard/API instead.
5. `docker compose up -d --build`, then
   `curl https://signup.stlucyhomecoming.com/healthz` → `ok`.
6. Boot service (one time): `sudo ./scripts/install-boot-service.sh` installs
   and enables a systemd unit (`stlucy-signup.service`) that runs
   `docker compose up -d` at boot. Docker's `restart: unless-stopped` already
   covers most reboots; the unit makes it guaranteed and inspectable via
   `systemctl status stlucy-signup`.

**Security note:** nothing listens on the network. Compose publishes the app
on `127.0.0.1:3000` only (loopback, for local checks) and the cloudflared
sidecar makes outbound-only connections — no inbound traffic ever reaches
the host.

## Local development

```bash
bundle install
set -a && source .env && set +a
export GOOGLE_APPLICATION_CREDENTIALS=credentials/service-account.json
bin/rails s   # http://localhost:3000
```

Point the volunteer page at it: set `signup_api: "http://localhost:3000"` in
`_config.yml` and run `jekyll serve`.
