# Should investing move to Sure? (assessment, 2026-11-10)

Question: replace the homegrown **investor-dashboard** and **hermes-investor plugin**
with **Sure** (we-promise/sure, the AI-native Maybe Finance fork)?

**Short answer: no, not the plugin. Probably not the dashboard either, for now.**
Sure and hermes-investor solve different problems. The only real overlap is the
investor-dashboard's *portfolio ledger* (positions, cost basis, P/L). Even there,
Sure has no connector for the broker you actually use (mBank eMakler, IKE/IKZE),
so the main thing it would offer, automatic holdings sync, doesn't apply to you.
Revisit if one of the triggers at the end fires.

## What we have today

| Piece | What it does | Category |
|---|---|---|
| **hermes-investor plugin** (Hermes Agent, NAS) | Collectors (RSS, Reddit, Stooq, Biznesradar, Yahoo), LLM sentiment scoring + aggregation, fundamentals hard filters/soft score, composite score, weekly **discovery** with tiers + anti-meme + decay, speculative sleeve, monthly **advisory briefs** with a mandatory devil's-advocate section, Telegram delivery, an outcome-tracking/feedback loop. Strategy: `hermes-investor/data/strategy.md` (VWCE backbone + opportunity sleeve; IKE/IKZE Polish dividend account). | **Research and advice engine** |
| **investor-dashboard** (`invest.mati-lab.online`) | Edit positions, cost basis, P/L, eMAKLER CSV import, price refresh, renders the plugin's analysis widgets (scores, drift, alerts), writes `portfolio.json` for the plugin. | **Portfolio ledger + UI for the engine** |
| **Actual Budget** (new, `budget.mati-lab.online`) | Cash budgeting, bank sync, spending/runway in Grafana. | **Cash flow** |

## What Sure is (Nov 2026)

- A full personal-finance app: net worth, accounts, transactions, budgets,
  **investments**. AGPL-3.0, very active: ~11k stars, weekly alphas, latest
  stable v0.7.6 (31 Oct 2026), alpha v2026.11.8 (9 Nov).
- **Investment features:** holdings built from trades, cost basis, stock splits
  (v0.7.6), trade fees, money-weighted returns and portfolio-weight rollups
  (v0.7.5), allocation by asset class/sector/region (v2026.11.8 alpha).
- **Broker connectors:** Interactive Brokers, Trade Republic, SnapTrade,
  Sharesight, Plaid, Coinbase, Kraken. **No mBank eMakler, no XTB, nothing
  Polish.** mBank-held positions would be manual entry or a trade CSV import.
- **Prices:** Yahoo, Twelve Data, Tiingo, EODHD, Alpha Vantage. Xetra is covered
  (`VWCE.DE` via Yahoo). The docs only mention **GPW (XWAR, PLN)** under
  **EODHD**, whose free tier is **20 requests/day**. There was a past bug where
  Polish prices were stored as USD (since fixed by a migration). The docs are
  marked "draft".
- **AI:** an assistant (chat over your own data, insights, "Dig in with AI"), a
  function-calling probe, an **MCP endpoint** (bearer token + user e-mail, read
  access to the family's data) and an HTTP API (`X-Api-Key` or OAuth2, OpenAPI
  spec). It talks to OpenAI-compatible providers, so it could point at LiteLLM.
- **Known rough edges** (open or recent issues): holdings ignored stock splits
  until v0.7.6; dropped Plaid holdings; stale provider-holdings views; price
  fetches that hit Yahoo rate limits.

## Feature-by-feature

| Need | hermes-investor + dashboard | Sure | Verdict |
|---|---|---|---|
| Positions, cost basis, P/L | Yes (eMAKLER CSV import, manual edit) | Yes, richer (MWR, allocation, splits) | **Sure is better UI**, but the data entry is the same: neither syncs eMakler automatically |
| IKE / IKZE account semantics | Strategy-aware (two accounts, different rules) | Generic investment accounts | Homegrown |
| GPW pricing | Stooq / Biznesradar (free, works) | EODHD, 20 req/day free; draft docs | Homegrown is safer |
| Net worth across cash + investments | No (and now cash lives in Actual) | Yes, core feature | **Sure** (or add investment balances to Actual, see below) |
| Sentiment, fundamentals scoring | Yes | No | Homegrown, no contest |
| Discovery / watchlists / speculative sleeve | Yes | No | Homegrown |
| Monthly advisory brief + devil's advocate + Telegram | Yes | No (the assistant answers questions; it doesn't research or recommend) | Homegrown |
| Outcome tracking / feedback loop | Yes (dormancy gate) | No | Homegrown |
| Chat with your portfolio | Via Hermes (Telegram) | Built-in assistant + MCP | Tie; Hermes already does this |
| Maintenance burden | Ours: incidents in Aug–Sep (UID change) and Oct–Nov (PYTHONPATH) | Upstream, but weekly alphas, AGPL, Rails + Postgres + Redis stack | Moves the work from code to upgrades |

## Options

1. **Keep everything homegrown** (recommended now). Optionally close the
   net-worth gap cheaply: have budget-worker (or the dashboard) post the daily
   investment-account value into Actual as an **off-budget tracking account**
   per broker account. The Budget dashboard's net-worth panel then covers
   everything. Roughly a day of work, no new app.
2. **Hybrid: Sure as the portfolio ledger, the plugin keeps the brains.** Drop
   the dashboard's positions/P&L UI. Hermes reads holdings from **Sure's MCP/API**
   instead of `portfolio.json`, and the analysis widgets would need a new home
   (Grafana, or keep a slim dashboard). Costs: a third finance app (Actual +
   Sure + Hermes), eMakler trades still entered by hand or CSV, GPW price
   quality to prove, and a rewrite of the plugin's portfolio adapter. The gain
   is a nicer portfolio UI and net worth.
3. **Full switch to Sure** (cash + investments, retire Actual and the dashboard).
   It contradicts the budgeting decision made today (Actual's envelope workflow
   and Enable Banking maturity), and it still leaves the research engine
   homeless. Not recommended.

## Triggers to revisit option 2

- Sure gains an **mBank eMakler** connector or a robust trade-CSV importer
  (an AI PDF trade-import proposal exists in a fork).
- GPW prices in Sure are confirmed reliable on the free tier, or you'd pay
  for EODHD.
- The dashboard needs a substantial UI rewrite anyway.
- You want family-wide net worth with a mobile app more than the budget can give.

## Prompt for a research agent

> You are evaluating whether a self-hosted personal-finance app, **Sure**
> (github.com/we-promise/sure, AGPL Maybe Finance fork), should replace or
> absorb parts of an existing homegrown investment stack. Be concrete, cite
> sources (release notes, docs.sure.am, GitHub issues/PRs, code), mark anything
> unverified, and date every claim. Today is <date>.
>
> **Current stack (the baseline to compare against):**
> - *hermes-investor*: a Python plugin for the Hermes Agent runtime. RSS/Reddit/
>   Stooq/Biznesradar/Yahoo collectors; LLM sentiment scoring via a LiteLLM
>   gateway (local Ollama models); fundamentals filters; composite scoring;
>   weekly discovery with tiering, anti-meme and decay rules; a speculative
>   sleeve; monthly markdown advisory briefs with a mandatory devil's-advocate
>   section; Telegram delivery; outcome tracking for self-calibration. Two
>   accounts at **mBank eMakler**: a standard brokerage account (VWCE on Xetra
>   ~70% + an opportunity sleeve of global stocks) and a Polish **IKE/IKZE**
>   dividend account (GPW stocks only).
> - *investor-dashboard*: FastAPI + SvelteKit; positions, cost basis, P/L;
>   eMAKLER CSV import; price refresh; renders the plugin's scores and drift
>   alerts; writes `portfolio.json` that the plugin reads.
> - Cash budgeting already lives in **Actual Budget** with Enable Banking (mBank).
>
> **Answer:**
> 1. Which broker integrations does Sure support today, and on its roadmap?
>    Specifically mBank eMakler, XTB, IBKR, Revolut. Can it import trades from a
>    CSV in a generic format? Test or describe the mapping for an eMakler
>    "portfel" / transaction-history export.
> 2. Price data for **GPW (XWAR, PLN)** and **Xetra (EUR) ETFs like VWCE**:
>    which provider, free-tier limits vs ~40 tickers daily, history depth,
>    corporate actions (splits, dividends), PLN/EUR FX handling. Any open bugs?
> 3. Investment analytics: cost-basis method (FIFO/average), dividends,
>    money/time-weighted returns, allocation views, tax-wrapper awareness
>    (IKE/IKZE or generic "tax-advantaged" flags), multi-currency net worth.
> 4. AI layer: what the assistant can do with investments (analysis, or only
>    Q&A?), whether it does any research, scoring or recommendations, which LLM
>    providers it supports (OpenAI-compatible base URL for LiteLLM?), and whether
>    a local-only model works with its function-calling probe.
> 5. Integration surface: MCP tools and HTTP API endpoints for **holdings,
>    trades, securities and prices**, read and write. Could an external agent
>    (Hermes) read holdings from Sure instead of `portfolio.json`, and write
>    analysis back (notes, tags, insights)? Auth model, rate limits.
> 6. Operations: self-hosting footprint (Rails, Postgres, Redis, Sidekiq?),
>    upgrade cadence and breaking changes over the last 6 months, data export,
>    backup/restore, multi-user/family model, mobile app scope.
> 7. Overlap with Actual Budget: would running Sure only for investments (no
>    bank sync, no budgeting) be a supported, sensible mode?
>
> **Deliver:** a feature matrix (current stack vs Sure, yes/no/partial with a
> source per cell); a migration-cost estimate for (a) Sure as the portfolio
> ledger with the plugin reading Sure's API, and (b) a full replacement; the top
> five risks; and a recommendation with explicit triggers that would change it.
> Do not recommend replacing research and recommendation features Sure doesn't have.

## Sources (accessed 2026-11-10)

- Sure repo and clients overview: https://github.com/we-promise/sure, https://github.com/we-promise/sure/blob/main/docs/clients.md
- Sure releases (v0.7.5 → v2026.11.8-alpha): https://github.com/we-promise/sure/releases
- Sure market-data providers (GPW via EODHD, Yahoo suffix table): https://docs.sure.am/providers/market-data
- Investment issues and PRs: https://github.com/we-promise/sure/issues/3781 (splits), https://github.com/we-promise/sure/pull/4315 (holdings from trades), https://github.com/we-promise/sure/pull/3888 and https://github.com/we-promise/sure/issues/3856 (price fetching / rate limits), https://github.com/we-promise/sure/pull/3484 (stale provider holdings), https://github.com/we-promise/sure/issues/4035 (Plaid holdings)
- Brokerage PDF trade-import proposal (fork): https://github.com/newmancu/sure/issues/78
- Twelve Data XWAR listing: https://twelvedata.com/exchanges/xwar
- The budgeting brief's earlier Sure verdict ("Watch"): `nas/Household Budgeting Stack for mBank Poland_ November 2026 …md` §2
