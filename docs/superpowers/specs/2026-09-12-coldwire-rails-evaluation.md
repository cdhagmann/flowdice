# Increment #7 — `coldwire-rails` Evaluation (candidate)

- **Date:** 2026-09-12
- **Status:** Candidate — not adopted. Re-evaluate when #7 (PWA / offline) is scoped.
- **Parent design:** `docs/superpowers/specs/2026-06-13-flowdice-architecture-and-roadmap-design.md`
  (Section C item 5, roadmap #7, open decision "Native-WebView offline strategy").
- **Candidate:** https://github.com/noreastergroup/coldwire-rails — gem `coldwire-rails`,
  MIT, Noreaster Group / Stuart Yamartino. Evaluated at 0.3.0 (commit `f14e363`, 2026-09-11)
  by reading the source, not by running it.

## Verdict

Close to a drop-in for #7's service-worker half. It would replace a hand-written worker
and the six offline gotchas that worker would otherwise have to rediscover. It does not
cover the web-app manifest or installability; those stay on the Rails 8 PWA stubs already
in the app. The one real caveat is maturity: two days old at evaluation time.

## What it is (verified from the 0.3.0 source)

- A Rails engine mounted at `/offline`. Serves a Cache API service worker at
  `/offline/service-worker.js` with `Service-Worker-Allowed: /`, registered at scope `/`.
- **Network-first.** The cache is consulted only after `fetch` fails (or when the user
  forces offline). No lookup on the happy path.
- **GET-only interception.** Non-GET requests are never touched.
- **A stored page brings its subresources:** `<link href>`, `<script src>`, `<img>`,
  `srcset`, and every value in the inline importmap JSON. Cached-as-you-go for `/*` by default.
- Refuses to store redirected responses; matches with `ignoreVary` (Rails answers HTML with
  `Vary: Accept`); strips `data-turbo-track="reload"` from anything served from cache; serves
  the offline fallback only to requests that want HTML (assets get an empty 504); answers a
  `Turbo-Frame` request with a matching `<turbo-frame>`; fallback is a 200 that boots Turbo.
- Middleware inserted at position 0 rewrites `HTTP_USER_AGENT` from a same-origin cookie the
  page writes (Android Hotwire Native workaround; the worker's fetches cannot carry the app UA).
- Garbage collection (60-day disuse, 250 MB ceiling by default), optional interval precache
  (`auto_sync`), settings page at `/offline` inheriting the host `ApplicationController` and
  layout, cross-origin hosts, `Range` caching, downloadable archives.
- Single runtime dependency `rails >= 7.1`, Ruby >= 3.1. No database, no migrations.
  Tailwind not required (its `online:`/`offline:` variants are optional). Works for anonymous
  apps: `cache_identity` is nil without `current_user` / `Current.user`.

## Fit with FlowDice

- **Section C item 5 verbatim:** the importmap crawl caches `flow_dice_evaluator` (the Opal
  bundle), the Stimulus controllers, and `calculator.css` on the first visit to `/`.
- **`POST /parse` is untouched** (non-GET), so an offline cache miss fails exactly as today
  and `roll_pipeline.js` needs no change. Cached plans re-roll offline — decision #8.
- **Three of its six gotchas apply to FlowDice now:** `Vary: Accept`, the
  `data-turbo-track="reload"` reload loop after a deploy (the layout tracks the stylesheet
  and importmap tags), and assets receiving an HTML fallback.
- **The other three are Hotwire Native rules** (200 fallback with Turbo booted, Turbo-Frame
  answer, Android UA cookie), plus documented iOS setup (app-bound domains, capped at 10
  entries). That is the "Native-WebView offline strategy" open decision, answered in favour
  of a service worker — decision #11's "Native-ready from day one".
- **No route collision.** The Rails 8 `/service-worker` stub in `config/routes.rb` is
  commented out and can stay that way. The manifest route/link stay FlowDice's to enable.
- **Installer fits the app as-is:** appends a `coldwire-cache` registration to
  `app/javascript/controllers/index.js`, inserts `<%= coldwire_service_worker_tag %>` before
  `</head>`, mounts the engine, writes an initializer with every default. Idempotent.
- `/offline` as a real route fits the URL-per-view convention (Section D).

## Costs and risks

| Signal (at 2026-09-12) | Value |
|---|---|
| Releases | 0.1.0 on 2026-09-10; 0.2.0 and 0.3.0 on 2026-09-11 |
| Authors / GitHub stars / commits | 1 / 15 / 141 |
| Config key renamed 0.2 → 0.3 | yes (`cache_origins` → `cacheable_hosts`) |
| Ruby tests | 41 (configuration, install generator, worker-source assembly) |
| Browser tests of the worker JS | 0 |
| Source size (rb/js/erb, excl. tests) | ~4.5k lines |

- README: "The API may still change before 1.0." **Pin `~> 0.3.0`.**
- FlowDice's cuprite system specs would be the only real integration test of the worker.
  Headless Chrome runs service workers; SW behaviour under Capybara/cuprite has not been
  tried in this repo. Unverified.
- **Sprawl vs. need:** archives, `Range` caching, cross-origin hosts, GC, sync, settings UI.
  FlowDice needs a fraction. The trade is one pinned dependency against hand-maintaining the
  six gotchas above.
- **Global side effect:** the UA-rewriting middleware feeds `allow_browser versions: :modern`
  in `ApplicationController`. Honest clients see no difference; `allow_browser` is a UX gate,
  not a security boundary.
- **Theme:** the `/offline` settings page and the fallback page ship light-themed plain CSS
  (white cards). Both templates are overridable; they need the dark/violet treatment.
- `cache_identity` stays nil until Phase 3 accounts; the cache is dropped on identity change,
  which matches Phase 3 sync.

## Adoption sketch (if chosen at #7 scoping)

1. `gem "coldwire-rails", "~> 0.3.0"` (re-check the current version and CHANGELOG first);
   `bin/rails coldwire:install`.
2. Leave `cache_as_you_go = ["/*"]`, `auto_sync.enabled = false` (landing on `/` caches the
   shell). Keep `never_intercept = ["/up"]`.
3. Override `app/views/coldwire/service_worker/offline_page.html.erb` and
   `app/views/coldwire/caches/show.html.erb` for the dark theme (keep the three things the
   setup doc says the fallback must retain: body-scoped CSS, the Turbo import alone,
   `turbo-cache-control: no-cache`).
4. Enable the Rails manifest route + `<link rel="manifest">`; fill in `manifest.json.erb`
   (name, colours, icons — currently the `RailsSkeleton` stub).
5. Cuprite system spec: load `/`, roll once (plan cached in IndexedDB), emulate offline via
   CDP, reload, re-roll the same notation, assert a result renders.

## Progress check — 2026-10-14

| Signal | 2026-09-12 | 2026-10-14 |
|---|---|---|
| Latest version | 0.3.0 | 0.5.0 (0.4.0 and 0.5.0 both 2026-09-17) |
| Last commit | 2026-09-11 | 2026-09-17 |
| Stars / forks | 15 / 0 | 38 / 1 |
| Contributors | 1 | 2 (one outside typo fix) |
| Open issues | 0 | 1 (#2, offline form-submission queue; no design, no comments) |
| Ruby test lines / methods | 447 / 41 | 1040 / 79 |
| Browser or JS-executing tests | 0 | 0 |
| CI workflow | none | none |

- 0.5.0: Turbo Frame responses cached apart from their page; each `respond_to` format gets
  its own entry; Turbo Streams never stored; precache entries may be hashes with `frame:` /
  `format:`. 0.4.0: settings page restructured; lowering the storage ceiling triggers a sweep.
- No config keys renamed since 0.3.0. Pin advice now `~> 0.5.0`.
- Nothing above changes the FlowDice fit: the shell is Turbo Drive-only and `POST /parse`
  stays uninterceptable. Issue #2 is irrelevant here; a parse has no value replayed later.
- Four weeks of silence after a one-week burst reads as a single-author extraction whose
  production needs were met, not as abandonment. "Maintained since 2026-09-17?" is the
  specific question for scoping time.

## Re-check before adopting

- Version, CHANGELOG, and whether anything after 0.3.0 renamed config again.
- Whether the project is still maintained (commits/issues since 2026-09-11).
- Whether a browser-level test suite has appeared upstream.
