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

1. **GitHub**: create a repo, push this code, then Settings → Pages → deploy
   from the `main` branch root. The `CNAME` file sets the custom domain.
2. **Cloudflare** (also needed for the signup tunnel): add the
   `stlucyhomecoming.com` zone, point the registrar at Cloudflare's
   nameservers, then add DNS records:
   - `A` records on `@` → GitHub Pages IPs: `185.199.108.153`,
     `185.199.109.153`, `185.199.110.153`, `185.199.111.153`
   - `CNAME` on `www` → `<your-github-username>.github.io`
   - (the `signup` record is created automatically by
     `signup-app/scripts/setup-tunnel.sh`)
   - Set the GitHub Pages IPs' proxy status to **DNS only** (grey cloud) so
     GitHub can issue its TLS cert, and enable "Enforce HTTPS" in GitHub Pages
     settings once the cert is issued.
3. **Signup service**: see [`signup-app/README.md`](signup-app/README.md).

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
