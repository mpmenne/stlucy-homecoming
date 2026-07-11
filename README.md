# St. Lucy Homecoming — stlucyhomecoming.com

Website for the St. Lucy Parish Homecoming (September 12 & 13, 2026, St. Joan
of Arc Campus, Pernod & Hampton, St. Louis).

Two pieces:

| Piece | What | Where it runs |
|---|---|---|
| This repo root | Jekyll site — all content pages in Markdown | GitHub Pages at `stlucyhomecoming.com` |
| [`signup-app/`](signup-app/) | Rails volunteer-signup API backed by a Google Sheet | Docker on the home server, exposed at `signup.stlucyhomecoming.com` via Cloudflare Tunnel |

## Editing content

Every page is a Markdown file at the repo root: `index.md`, `volunteer.md`,
`reunion.md`, `contact.md`. Edit, commit, push — GitHub Pages redeploys
automatically in a minute or two. Search the files for `TODO` to find spots
awaiting real copy (event hours, schedule, reunion details).

## Local preview

```bash
rbenv local 3.3.6   # already set via .ruby-version
bundle install
bundle exec jekyll serve   # http://localhost:4000
```

## Deploying (one-time setup)

1. **GitHub Pages** (`gh auth login` first):
   ```bash
   gh api -X POST repos/mpmenne/stlucy-homecoming/pages \
     -f build_type=legacy -f "source[branch]=main" -f "source[path]=/"
   gh api -X PUT repos/mpmenne/stlucy-homecoming/pages -f cname=stlucyhomecoming.com
   # once .https_certificate.state is issued/approved:
   gh api -X PUT repos/mpmenne/stlucy-homecoming/pages -F https_enforced=true
   ```
2. **Cloudflare DNS** (dashboard, zone `stlucyhomecoming.com`) — all records
   **DNS only (grey cloud)** so GitHub can issue and renew its TLS cert:
   - Delete any leftover records on `@` and `www` (e.g. parking-page records).
   - `A` on `@` → `185.199.108.153`, `185.199.109.153`, `185.199.110.153`,
     `185.199.111.153`
   - `CNAME` on `www` → `mpmenne.github.io`
   - `CNAME` on `signup` → `<tunnel-id>.cfargotunnel.com`, **Proxied** (orange
     cloud — tunnels only work proxied). Normally created by
     `signup-app/scripts/setup-tunnel.sh`; set by hand if the script's login
     cert was scoped to the wrong zone.
3. **Signup service**: see [`signup-app/README.md`](signup-app/README.md) —
   includes the boot service (`signup-app/scripts/install-boot-service.sh`).

## Temporary stakeholder password gate

While the site is a proposal, every page shows a password overlay
(`_includes/password-gate.html`, toggled by `password_gate` in `_config.yml`).
It's a soft lock to signal "not public yet" — not real security (the repo and
HTML are public). To go public: set `password_gate: false` and push.

## SEO checklist (do these — they're the whole ballgame for outranking the old event page)

- [ ] Verify the domain in [Google Search Console](https://search.google.com/search-console)
      and submit `https://stlucyhomecoming.com/sitemap.xml`.
- [ ] Ask the parish to **link to stlucyhomecoming.com from saintlucystl.org** —
      ideally from its `/homecoming` page. A link from the parish site is the
      strongest ranking signal we can get.
- [ ] Share the link anywhere the event is mentioned (parish bulletin, Facebook,
      Nextdoor, school newsletters) — real links and traffic compound.
- [ ] After deploy, paste the homepage URL into Google's
      [Rich Results Test](https://search.google.com/test/rich-results) and
      confirm the Event markup validates.

Note on the former event name: per the parish's wishes it appears **only** in
machine-readable structured data (`_includes/event-jsonld.html`), never in
visible copy. Please keep it that way when editing.
