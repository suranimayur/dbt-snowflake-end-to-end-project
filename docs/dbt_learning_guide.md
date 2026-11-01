# dbt on Snowflake — Learning Guide

A complete walkthrough of this repository: what each model does, why it is configured the
way it is, how the project is tested, and what went wrong along the way. Read it top to
bottom on your first pass, then use the troubleshooting and exercise sections as a
reference.

**Contents**

1. [What you will learn](#1-what-you-will-learn)
2. [The project at a glance](#2-the-project-at-a-glance)
3. [Mental model: ELT in three layers](#3-mental-model-elt-in-three-layers)
4. [Repository layout](#4-repository-layout)
5. [Setup from zero](#5-setup-from-zero)
6. [Sources](#6-sources)
7. [Layer 1 — staging models](#7-layer-1--staging-models)
8. [Layer 2 — dimensional models](#8-layer-2--dimensional-models)
9. [Configuration and materialisations](#9-configuration-and-materialisations)
10. [Testing](#10-testing)
11. [Source freshness](#11-source-freshness)
12. [Daily workflow](#12-daily-workflow)
13. [Troubleshooting ledger](#13-troubleshooting-ledger)
14. [Known gaps and next steps](#14-known-gaps-and-next-steps)
15. [Exercises](#15-exercises)
16. [Glossary](#16-glossary)

---

## 1. What you will learn

By the end of this guide you should be able to:

- Explain the difference between **EL** (outside dbt) and **T** (inside dbt), and why raw
  tables are read through `source()` rather than by name.
- Read a dbt project's lineage and say which model produces which grain.
- Choose a **materialisation** (view, table, incremental) deliberately, and override it at
  the right level of the config hierarchy.
- Write **data tests** that protect grain and referential integrity.
- Configure **source freshness** and interpret its three outcomes: pass, warn, error.
- Diagnose the four error classes this project has actually hit.

---

## 2. The project at a glance

| Item | Value |
| :--- | :--- |
| dbt Core | 1.12.6 |
| Snowflake adapter | 1.12.4 |
| Project / profile name | `dbt_project` |
| Targets | `dev` (default), `prod` |
| Python | 3.13, managed with `uv` |
| Models | 7 (3 staging, 4 dimensional) |
| Sources | 1 (`raw`) with 3 tables |
| Data tests | 8 (all on sources) |
| Raw data | `RAW_DB.RAW_SCHEMA` |
| dbt output (`dev`) | `DBT_LANDING_DB.DBT_LANDING_SCHEMA` |

Current snapshot size:

| Raw table | Rows | Grain |
| :--- | ---: | :--- |
| `RAW_HOSTS` | 14,111 | one row per host |
| `RAW_LISTINGS` | 17,499 | one row per listing |
| `RAW_REVIEWS` | 410,284 | one row per review |

---

## 3. Mental model: ELT in three layers

dbt does not load data. Data arrives in `RAW_DB.RAW_SCHEMA` from an external process
(ingestion tool, script, manual upload) and dbt's job is the **T** — it reads raw tables,
applies logic in SQL files, and materialises the results as views and tables in a target
schema.

The project splits that transformation into two layers:

```
RAW_DB.RAW_SCHEMA                          ← EL: outside dbt, no dbt code touches it
  RAW_HOSTS     RAW_LISTINGS     RAW_REVIEWS
      │              │               │
      │        source('raw', …)      │        ← the only allowed read path
      ▼              ▼               ▼
models/src/  ── staging ── materialised as TABLES (tag: src)
  src_hosts     src_listings     src_review
      │              │               │          rename + light typing, never joins
      ▼              ▼               ▼
models/dim/  ── marts ──── materialised as VIEWS
  dim_hosts_cleaned   dim_listings_cleaned   dim_review_cleaned
              ╲              ╱
               ▼            ▼
           dim_listings_w_hosts ── TABLE (denormalised, one row per listing)
```

**Why two layers rather than one?** Staging models give every downstream model a stable
interface: column names and types are settled in exactly one place, so a rename in the raw
table is a one-line change instead of a hunt across marts. Marts are then free to express
business rules and joins.

**Grain discipline.** Every model in this project keeps the grain of the table it reads,
with one exception worth studying: `dim_listings_w_hosts` joins hosts onto listings but the
join is `left join` on `host_id`, and `host_id` is unique per host, so the output is still
one row per listing — it does not fan out.

---

## 4. Repository layout

```
dbt-training/
├── dbt_project/
│   ├── dbt_project.yml            project config: name, profile, paths, folder defaults
│   ├── models/
│   │   ├── src/
│   │   │   ├── sources.yml        source declarations + tests + freshness
│   │   │   ├── src_hosts.sql
│   │   │   ├── src_listings.sql
│   │   │   └── src_review.sql
│   │   └── dim/
│   │       ├── dim_hosts_cleaned.sql
│   │       ├── dim_listings_cleaned.sql
│   │       ├── dim_review_cleaned.sql
│   │       └── dim_listings_w_hosts.sql
│   ├── analyses/  macros/  seeds/  snapshots/  tests/    scaffolds, currently empty
│   └── .user.yml                  dbt-generated project id (commit-safe, not secret)
├── docs/
│   ├── dbt_learning_guide.md      ← this file
│   └── dbt_snowflake_commands.md  command reference
├── src/dbt_training/              Python package with a placeholder entry point
├── logs/                          dbt log output
├── pyproject.toml / uv.lock       dependencies
└── README.md                      project overview and quickstart
```

---

## 5. Setup from zero

```bash
uv sync                         # creates .venv with dbt-core + dbt-snowflake
cd dbt_project
dbt debug                       # proves the profile and the Snowflake connection work
```

`dbt debug` is not optional ceremony: it separates *connection* problems from *model*
problems, which is where most beginners lose time.

### Profile

dbt looks for a profile whose name matches `profile:` in `dbt_project.yml` — here
`dbt_project`. Credentials do not belong in the repository; `dbt_project/.gitignore`
already ignores `profiles.yml`, so a project-local file is safe to use with
`dbt --profiles-dir .`.

```yaml
# ~/.dbt/profiles.yml
dbt_project:
  target: dev
  outputs:
    dev:
      type: snowflake
      account: <org>-<account>
      user: <user>
      password: "{{ env_var('DBT_SNOWFLAKE_PASSWORD') }}"   # or private_key_path
      role: <role>
      database: DBT_LANDING_DB   # where models are built; sources.yml pins raw_db itself
      warehouse: <warehouse>
      schema: dbt_landing_schema     # dbt writes models here (this project's dev schema)
      threads: 4
    prod:
      type: snowflake
      # same connection, different schema/warehouse, for scheduled runs
```

Keeping secrets in `env_var()` and out of YAML means the profile can be shared and the
secret rotates independently.

---

## 6. Sources

`sources.yml` teaches dbt three things: that these tables exist, how to describe and test
them, and where their physical data lives.

```yaml
version: 2

sources:
  - name: raw
    database: raw_db
    schema: raw_schema
    tables:
      - name: hosts
        identifier: raw_hosts
```

**`name` vs `identifier` — the single most common source mistake.**

- `name` is dbt's logical handle. Models say `{{ source('raw', 'hosts') }}`.
- `identifier` is the physical table (or view) name when it differs from `name`. Here the
  logical name is `hosts` and the physical table is `RAW_HOSTS`.

`schema` and `database` set the rest of the path, so dbt resolves
`{{ source('raw', 'hosts') }}` to `RAW_DB.RAW_SCHEMA.RAW_HOSTS`. A model that instead
writes `{{ source('raw', 'raw_hosts') }}` fails at compile time, because `raw_hosts` is not
a declared table name — it is only an identifier. This project hit exactly that error; see
[§13](#13-troubleshooting-ledger).

**Why bother with `source()` at all?** Three reasons:

1. **Lineage.** Raw tables appear in the dbt docs DAG, so you can see what depends on them.
2. **Freshness and tests.** You cannot freshness-check or test a literal table reference.
3. **One place to change.** Move the raw schema and you edit one YAML file, not every model.

---

## 7. Layer 1 — staging models

Staging models do the boring, load-bearing work: they rename columns to a house style,
apply explicit casts, and set the materialisation. They contain **no joins and no business
logic**, which makes them cheap to re-read and safe to change.

### `src_hosts.sql`

```sql
{{ config(
    materialized='table',
    transient=true,
    tags =['src'],
    alias='src_hosts')
}}

with cte_1 as (
    select id, name, is_superhost, created_at, updated_at
    from {{ source('raw', 'hosts') }}
)

select
    id            as host_id,
    name          as host_name,
    is_superhost  as host_is_superhost,
    created_at    as host_created_at,
    updated_at    as host_updated_at
from cte_1
```

Teaching points:

- `id → host_id` prefixes the key with the entity name, so a join never has an ambiguous
  `id` column. This convention pays off in `dim_listings_w_hosts`.
- `transient=true` asks Snowflake for a **transient** table: no fail-safe storage, cheaper,
  appropriate for data that is rebuilt from source and does not need point-in-time recovery.
- `tags=['src']` enables `dbt run --select tag:src`.
- `alias='src_hosts'` is explicit even though it matches the file name — useful when a
  downstream team expects a fixed name regardless of file renames.

### `src_listings.sql`

```sql
with cte_1 as (
    select id, listing_url, name, room_type, host_id,
           minimum_nights, price, created_at, updated_at
    from {{ source('raw', 'listings') }}
)

select
    id             as listing_id,
    listing_url,
    name           as listing_name,
    room_type,
    host_id,
    minimum_nights,
    price          as price_sdr,      -- still the raw '$123.00' text
    created_at,
    updated_at
from cte_1
```

`price` is deliberately **not** cast here: it stays text, aliased `price_sdr`, and is
converted in the mart. Staging keeps raw fidelity; marts own the cleaning rules.

This model has no `config()` block, so it inherits `materialized: table` from
`dbt_project.yml` (§9). Comparing the two files is a good way to see inheritance in action.

### `src_review.sql`

```sql
with cte_1 as (
    select listing_id, date, reviewer_name, comments, sentiment
    from {{ source('raw', 'reviews') }}
)

select
    listing_id,
    date           as review_date,
    reviewer_name,
    comments       as review_text,
    sentiment      as review_sentiment
from cte_1
```

Note the file is `src_review.sql` (singular) while the source is `reviews` — the model name
comes from the file name, so downstream code must use `ref('src_review')`. Renaming the file
to `src_reviews.sql` would be a tidy-up; see §14.

---

## 8. Layer 2 — dimensional models

Marts apply business rules and joins. All four are `view` by default (cheap, always fresh)
except the denormalised table.

### `dim_hosts_cleaned.sql`

```sql
with src_hosts as (select * from {{ ref('src_hosts') }}),

cleaned as (
    select
        host_id,
        coalesce(host_name, 'Anonymous')   as host_name,
        coalesce(host_is_superhost, 'f')   as host_is_superhost,
        host_created_at,
        host_updated_at
    from src_hosts
    where host_id is not null
)

select * from cleaned
```

Three business rules, each one a decision worth stating out loud:

1. Missing names become `'Anonymous'` — BI-friendly, avoids `NULL` labels in dashboards.
2. Missing superhost flags become `'f'` — note the column is **text**, not boolean
   (`IS_SUPERHOST` is `TEXT` in the raw table), so `'f'` is the honest default.
3. Rows without a `host_id` are dropped: a host row with no key cannot be joined to a
   listing, so it only adds noise.

Every model in this project uses the same shape — `with <source> as (select * from ref)`
then a `cleaned` CTE then a final `select *` — which makes diffs read consistently.

### `dim_listings_cleaned.sql`

```sql
with src_listintgs as (select * from {{ ref('src_listings') }})

select
    listing_id,
    listing_url,
    listing_name,
    room_type,
    host_id,
    case when minimum_nights = 0 then 1 else minimum_nights end as minimum_nights,
    replace(price_sdr, '$')::number(10,2) as price,
    created_at,
    updated_at
from src_listintgs
```

- A `minimum_nights` of `0` is not a valid booking constraint, so it is normalised to `1`.
- `PRICE` is `TEXT` containing values like `$120.00`. `replace(...,'$')` strips the symbol
  and `::number(10,2)` casts the remainder, converting a string field into an analysable
  numeric one. If any value ever arrives unparseable, this model fails loudly — which is
  the correct behaviour (see the `try_cast` note in §14).
- The CTE name `src_listintgs` is a typo carried in the source file; renaming it is safe and
  purely cosmetic.

### `dim_review_cleaned.sql`

```sql
with src_review as (select * from {{ ref('src_review') }})

select
    listing_id,
    review_date,
    reviewer_name,
    review_text,
    review_sentiment
from src_review
```

A pass-through today. Its value is contractual: consumers point at
`dim_review_cleaned`, so cleaning (deduplication, sentiment normalisation, PII removal on
`reviewer_name`) can be added later without breaking anyone.

### `dim_listings_w_hosts.sql`

```sql
{{ config(
    materialized='table',
    transient='false'
) }}

with cte_listings as (select * from {{ ref('dim_listings_cleaned') }}),
     cte_hosts    as (select * from {{ ref('dim_hosts_cleaned') }})

select
    l.listing_id, l.listing_url, l.listing_name, l.room_type,
    l.minimum_nights, l.price,
    h.host_id, h.host_name, h.host_is_superhost, h.host_created_at,
    greatest(l.updated_at, h.host_updated_at) as updated_at,
    l.created_at
from cte_listings as l
left join cte_hosts as h
  on l.host_id = h.host_id
```

This is the project's presentation model: one row per listing with host attributes attached,
materialised as a table because BI tools query it repeatedly.

- **`left join` keeps every listing**, even one whose host is missing — desirable, since
  a listing without a host is still a listing a user can book. An `inner join` would
  silently drop rows; check the `host_id` null count if you ever change the join type.
- **`greatest(l.updated_at, h.host_updated_at)`** makes the row's `updated_at` reflect the
  newest input. This is a simple approximation of change tracking; a `snapshot` (§14) is the
  correct tool when you need history rather than a timestamp.
- **`transient='false'`** passes the *string* `'false'` where a boolean is expected. Querying
  `information_schema.tables` on 2026-11-01 shows `DIM_LISTINGS_W_HOSTS` with
  `IS_TRANSIENT = YES`, so the intended permanent table was not produced. Write
  `transient=false` (no quotes) and re-check `IS_TRANSIENT` to confirm.

---

## 9. Configuration and materialisations

`dbt_project.yml` holds settings that apply to the project as a whole and defaults per
folder:

```yaml
name: 'dbt_project'
version: '1.0.0'
profile: 'dbt_project'

model-paths: ["models"]
# … analyses, test, seed, macro, snapshot paths …

clean-targets:
  - "target"
  - "dbt_packages"

models:
  dbt_project:        # must match the project name
    src:
      +materialized: table
    dim:
      +materialized: view
      +transient: false
```

The `+` prefix marks a config that applies to every model at that level. A model-level
`config()` block overrides it.

### Precedence, lowest to highest

1. `dbt_project.yml` folder defaults
2. A `models:` entry in a `*.yml` properties file
3. A `config()` block inside the `.sql` file

So `dim_listings_w_hosts` beats `dim: +materialized: view` and becomes a table.

### Choosing a materialisation

| Materialisation | What dbt issues | Use when |
| :--- | :--- | :--- |
| `view` | `create view` | Logic is cheap, or downstream needs always-fresh data. Default for marts here. |
| `table` | `create table as select` | Reused repeatedly, or the query is slow enough that re-running it per view is wasteful. |
| `incremental` | `insert`/`merge` into an existing table | Source is huge and only new rows matter. Not used yet — see §14. |
| `ephemeral` | CTE injected into the consumer | A staging step never queried on its own. |

This project's choice is simple and defensible: staging as tables (they are read by several
models), marts as views (cheap, always current), the one denormalised wide table as a table.

**Snowflake-specific:** `transient` controls fail-safe. `transient=true` skips the 7-day
fail-safe period, lowering storage cost for data that can be rebuilt. That is why
`src_hosts` sets it — the table is a pure function of the raw table.

Worth knowing before you rely on the default: on 2026-11-01 **all four tables** in
`DBT_LANDING_SCHEMA` reported `IS_TRANSIENT = YES` — including `src_listings` and
`src_review`, which set no `transient` config at all, and `dim_listings_w_hosts`, which asks
for `'false'`. So the folder-level `+transient: false` and the quoted string are not both
doing what they appear to do. Verify the outcome instead of assuming it:

```sql
select table_name, table_type, is_transient
from information_schema.tables
where table_schema = current_schema()
order by table_name;
```

---

## 10. Testing

Eight tests, all declared in `sources.yml`:

| Source table | Column | Test | Why it matters |
| :--- | :--- | :--- | :--- |
| `hosts` | `id` | `unique` | Grain guard: one row per host |
| `hosts` | `id` | `not_null` | A keyless host row cannot join |
| `listings` | `id` | `unique` | Grain guard: one row per listing |
| `listings` | `id` | `not_null` | Primary key integrity |
| `listings` | `host_id` | `not_null` | Join key integrity for `dim_listings_w_hosts` |
| `reviews` | `listing_id` | `not_null` | Join key integrity |
| `reviews` | `date` | `not_null` | Freshness/ordering depends on it |
| `reviews` | `reviewer_name` | `not_null` | Downstream display assumption |

A deliberate omission: **`reviews.listing_id` is not tested for uniqueness.** A listing has
many reviews, so uniqueness would fail by design — and a test that fails by design trains
people to ignore failing tests. The source description says this out loud, which is exactly
what documentation is for.

`unique` on `reviews` has no surrogate key to hang on. If you need one, add a
`dbt_utils.generate_surrogate_key(['listing_id','date','reviewer_name'])` in the staging
model — accepting that duplicate reviews by the same person on the same day would collapse.

Run them with:

```bash
dbt test                    # every test
dbt test --select source:raw   # just the source tests
```

---

## 11. Source freshness

Freshness answers: *is the data behind this source recent enough to trust?* dbt runs
`select max(<loaded_at_field>) from <source>` and compares it to now.

```yaml
- name: hosts
  identifier: raw_hosts
  config:
    loaded_at_field: updated_at
    freshness:
      warn_after: {count: 24, period: hour}
      error_after: {count: 48, period: hour}
```

Outcomes map to exit codes: **pass** (0), **warn** (0, with a warning), **error**
(non-zero — `dbt source freshness` fails the run).

### Two lessons from this project

**1. Pick a column that means "load time".** `updated_at` on `raw_hosts` is a genuine
row-update timestamp, so a fresh load makes `max(updated_at)` recent and the check is
meaningful. `raw_reviews` has no such column — its only time field is `date`, the timestamp
*of the review itself*. Freshness on `date` measures how recent the reviews are, not when
data was loaded. That is a proxy, and the config comment says so.

**2. Thresholds must match the dataset.** With `error_after: 24 hour`, `raw.reviews`
reported `ERROR STALE` on the first run — correctly. The newest review in this static
snapshot is **2021-10-22** (~44,000 hours old), so *any* hour-scale threshold fails. The
thresholds were widened to `2190 day` / `3650 day` for deliberately-stale demo data; the
alternative is to remove the `freshness:` block and comment why. Never relax a threshold
without first checking `max(loaded_at_field)`:

```sql
select max(date) as newest, datediff(hour, max(date), current_timestamp()) as hours_old
from raw_db.raw_schema.raw_reviews;
```

**Valid periods:** `minute`, `hour`, `day` only. `period: year` fails at parse time
(`'year' is not a valid TimePeriod`), so express longer windows in days.

---

## 12. Daily workflow

```bash
cd dbt_project

dbt debug                        # connection check after any profile/credential change
dbt source freshness             # is the raw data current?
dbt compile                      # render SQL to target/compiled/ without executing
dbt run                          # build all models
dbt test                         # validate
dbt build                        # run + test + snapshot, interleaved by DAG order
dbt docs generate && dbt docs serve    # lineage + column docs on localhost:8080
```

Selective and directed runs:

```bash
dbt run --select src_hosts                 # one model
dbt run --select src                       # one folder
dbt run --select tag:src                   # by tag
dbt run --select +dim_listings_w_hosts     # model + all ancestors
dbt run --select dim_listings_w_hosts+     # model + all descendants
dbt run --select src_hosts --full-refresh  # force rebuild of an incremental model
dbt show --select dim_listings_w_hosts     # preview a model's rows
dbt show --inline "select count(*) from {{ ref('src_hosts') }}"
```

`dbt build` is preferred for CI and production because it tests each model before building
its children — a failing test stops that branch instead of propagating bad data.

---

## 13. Troubleshooting ledger

Every error this project has actually produced, with root cause and fix.

### `depends on a source named 'raw.raw_hosts' which was not found`

```
Model 'model.dbt_project.src_hosts' (models\src\src_hosts.sql) depends on a source
named 'raw.raw_hosts' which was not found
```

**Root cause:** `source('raw', X)` takes the table's declared `name`, not its `identifier`.
`sources.yml` declares `name: hosts` with `identifier: raw_hosts`, so the correct call is
`source('raw', 'hosts')`.

**Fix:** use declared names in every model:

```sql
{{ source('raw', 'hosts') }}      -- not 'raw_hosts'
{{ source('raw', 'listings') }}   -- not 'raw_listings'
{{ source('raw', 'reviews') }}    -- not 'raw_reviews'
```

**Lesson:** the `identifier` exists precisely so the two names can differ. Verify with
`dbt parse` — it catches this class of error without touching the warehouse.

### `ERROR STALE` from `dbt source freshness`

**Root cause:** `max(date)` in `raw_reviews` is older than `error_after`, or the thresholds
were written for a live feed while the data is a static snapshot.

**Fix:** check the data first, then decide. Here the snapshot's newest review is from
2021-10-22, so hour-scale thresholds could never pass; they were widened and documented.
Silently widening a threshold on *live* data would be the wrong move — that would hide a
real ingestion outage.

### `Field "warn_after" … has invalid value {'count': 6, 'period': 'year'}`

**Root cause:** dbt's `TimePeriod` enum accepts only `minute`, `hour`, `day`.

**Fix:** convert to days — 6 years is `{count: 2190, period: day}`.

### `Pulling freshness from warehouse metadata tables for 0 sources`

Not an error: Snowflake adapter metadata-based freshness applies only where configured, so
dbt fell back to issuing a query per source. Expected on this project.

---

## 14. Known gaps and next steps

Deliberately listed, not hidden — good starting points for contribution.

| Area | Gap | Suggested action |
| :--- | :--- | :--- |
| Tests | Only sources are tested; no model-level tests | Add `unique`/`not_null` on `dim_*` primary keys and a `relationships` test from `dim_listings_w_hosts.host_id` to `dim_hosts_cleaned.host_id` |
| Naming | `src_review.sql` vs source `reviews`; `src_listintgs` typo | Rename to `src_reviews.sql` and fix the CTE alias |
| Config | `transient='false'` passes a string | Use `transient=false` |
| Robustness | `replace(price_sdr,'$')::number(10,2)` fails on any malformed value | Use `try_to_number(replace(price_sdr,'$'),10,2)` plus a `not_null` test on `price` to surface bad rows as a test failure instead of a build failure |
| Type | `host_is_superhost` is text (`'t'`/`'f'`), so `coalesce(..., 'f')` is the only option | Cast to boolean in staging once consumers agree |
| History | `dim_listings_w_hosts.updated_at` folds both inputs into one timestamp | Add a `snapshot` on `dim_listings_cleaned` for SCD2 history |
| Performance | 410k reviews are handled as full rebuilds | Consider `materialized='incremental'` with `unique_key` for review aggregates |
| Docs | Models have no column descriptions | Add `models/dim/schema.yml` with descriptions and `data_tests`, then `dbt docs generate` |
| Ops | No CI | Add a GitHub Actions job running `dbt build --target prod` on pull requests |
| Objects | `MAYUR_SRC_HOSTS` sits in `DBT_LANDING_SCHEMA` from an earlier alias experiment | `drop table` it, or capture the alias experiment as a documented tag variant |
| `transient` | All four tables report `IS_TRANSIENT = YES` even where `false` was intended | Make the flag explicit (`transient=false`, no quotes) and assert the outcome in CI |

---

## 15. Exercises

Work through these in order; each builds on the previous state of the project.

1. **Trace the lineage.** Run `dbt ls --select +dim_listings_w_hosts` and confirm the
   output matches the DAG in §3. Then explain why `dim_review_cleaned` is absent.
2. **Break the source on purpose.** Change `src_listings.sql` to
   `{{ source('raw', 'raw_listings') }}` and run `dbt parse`. Read the error, then revert.
   You have now reproduced the project's first real bug.
3. **Expose the grain.** Write a singular test in `dbt_project/tests/` asserting
   `select host_id, count(*) from {{ ref('dim_hosts_cleaned') }} group by 1 having count(*) > 1`
   returns no rows. Run `dbt test --select dim_hosts_cleaned`.
4. **Add referential integrity.** Add a `relationships` test in a new
   `models/dim/schema.yml` from `dim_listings_w_hosts.host_id` to
   `dim_hosts_cleaned.host_id`. Decide whether `severity: warn` is more appropriate than the
   default error, given the `left join`.
5. **Prove the join does not fan out.** Compare `count(*)` on `dim_listings_cleaned` with
   `count(*)` on `dim_listings_w_hosts`. They should match; explain what a difference would
   imply.
6. **Widen a mart.** Build a listing-level review summary: number of reviews and average
   `review_sentiment` (you will need to decide how sentiment is encoded before averaging
   anything). Materialise it as a table and document the grain.
7. **Change a materialisation.** Switch `dim_review_cleaned` from view to table via
   `dbt_project.yml`, rebuild, and inspect the resulting object in
   `information_schema.tables`. Explain what `is_transient` shows for `src_hosts` versus
   `dim_review_cleaned`.
8. **Run freshness like an operator.** Set `raw.hosts` to `warn_after: 1 hour`,
   `error_after: 2 hours`, and confirm `dbt source freshness` fails after the newest
   `updated_at` ages out. Note the non-zero exit code — that is what a scheduler acts on.

---

## 16. Glossary

| Term | Meaning |
| :--- | :--- |
| **Model** | A `.sql` file (plus optional config) that dbt compiles into a `select` and materialises. |
| **Source** | A declaration of an existing table dbt does not build, referenced with `source()`. |
| **`ref()`** | Resolves a model name to its physical relation and creates a DAG dependency. |
| **Grain** | What one row represents. Protect it with `unique` tests. |
| **Materialisation** | How a model is persisted: view, table, incremental, ephemeral. |
| **Tag** | A label on models for selective runs, e.g. `--select tag:src`. |
| **Seed** | A CSV committed to the repo and loaded with `dbt seed`. |
| **Snapshot** | A dbt-built SCD2 history table capturing row changes over time. |
| **Freshness** | `max(loaded_at_field)` compared against now, with warn/error thresholds. |
| **Singular test** | A SQL file under `tests/` that must return zero rows. |
| **Generic test** | A reusable assertion (`unique`, `not_null`, `relationships`) applied in YAML. |
| **Target schema** | The schema dbt writes to, defined by the profile's `schema`. |
| **Transient table** | Snowflake table without fail-safe storage; cheaper, rebuildable data. |

---

*Verified against dbt Core 1.12.6 / dbt-snowflake 1.12.4 on 2026-11-01: `dbt parse`,
`dbt source freshness` (2/2 pass) and a full `dbt run` (`PASS=7 WARN=0 ERROR=0`) into
`DBT_LANDING_DB.DBT_LANDING_SCHEMA`. Row counts and the `$123.00` price format were read from the
warehouse at that time.*
