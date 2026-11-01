# dbt_project

The dbt project for the **dbt-training** workspace: an Airbnb-style dataset transformed
with dbt Core 1.12.6 on Snowflake.

- Project name: `dbt_project`
- Profile: `dbt_project` (targets `dev`, `prod`)
- Raw data: `RAW_DB.RAW_SCHEMA` — loaded outside dbt, read only through `source()`
- Output (dev): `DBT_LANDING_DB.DBT_LANDING_SCHEMA` — all 7 models build here (`PASS=7`)
- Orphan object: `DBT_LANDING_SCHEMA.MAYUR_SRC_HOSTS` (from an earlier alias experiment,
  not produced by any current model)

## Models

| Model | Layer | Materialisation | Reads from | Grain |
| :--- | :--- | :--- | :--- | :--- |
| `src_hosts` | staging | table (transient) | `source('raw', 'hosts')` | one row per host |
| `src_listings` | staging | table | `source('raw', 'listings')` | one row per listing |
| `src_review` | staging | table | `source('raw', 'reviews')` | one row per review |
| `dim_hosts_cleaned` | marts | view | `src_hosts` | one row per host |
| `dim_listings_cleaned` | marts | view | `src_listings` | one row per listing |
| `dim_review_cleaned` | marts | view | `src_review` | one row per review |
| `dim_listings_w_hosts` | marts | table | `dim_listings_cleaned`, `dim_hosts_cleaned` | one row per listing |

Lineage:

```
raw.hosts ──▶ src_hosts ──▶ dim_hosts_cleaned ──┐
                                                ├──▶ dim_listings_w_hosts
raw.listings ─▶ src_listings ─▶ dim_listings_cleaned ─┘
raw.reviews ──▶ src_review ──▶ dim_review_cleaned
```

Staging models rename and cast only. Dimensional models carry the business logic:
`dim_hosts_cleaned` coalesces missing names to `Anonymous` and drops null keys;
`dim_listings_cleaned` replaces a `0` minimum-nights with `1` and parses the `$`-prefixed
price string into `NUMBER(10,2)`; `dim_listings_w_hosts` joins listings to hosts and keeps
the latest of the two `updated_at` values.

## Sources

Declared in [`models/src/sources.yml`](models/src/sources.yml) — 3 tables, 8 data tests.

Freshness is configured per table:

| Source table | `loaded_at_field` | warn / error | Why |
| :--- | :--- | :--- | :--- |
| `raw.hosts` | `updated_at` | 24 h / 48 h | Real row-update timestamp, so it measures load freshness |
| `raw.reviews` | `date` | 2190 d / 3650 d | No load timestamp exists; `date` is only a proxy, and the snapshot's newest review is from 2021-10-22 |

Run `dbt source freshness` to check them. Note that dbt accepts only `minute`, `hour` and
`day` as freshness periods — `year` fails at parse time.

## Configuration

`dbt_project.yml` sets folder-level defaults:

```yaml
models:
  dbt_project:
    src:
      +materialized: table
    dim:
      +materialized: view
      +transient: false
```

Override per model with a `config()` block, e.g. `src_hosts` forces
`materialized='table', transient=true`, and `dim_listings_w_hosts` forces a table because it
is queried by BI consumers. Model-level config beats folder-level config.

**Caveat, measured on 2026-11-01:** all four tables in `DBT_LANDING_SCHEMA` report
`IS_TRANSIENT = YES` — including `src_listings`/`src_review` (no `transient` config) and
`dim_listings_w_hosts` (which passes the quoted string `'false'`). Write `transient=false`
unquoted and verify, rather than assuming either the folder default or a quoted string
takes effect:

```sql
select table_name, table_type, is_transient
from information_schema.tables where table_schema = current_schema();
```

## Common commands

```bash
dbt debug                                  # connection + project sanity check
dbt run                                    # build all models
dbt run --select src                       # everything tagged 'src'
dbt run --select +dim_listings_w_hosts     # model plus its ancestors
dbt test                                   # run data tests
dbt source freshness                       # freshness per configured source
dbt compile                                # render SQL into target/compiled/ without running
dbt docs generate && dbt docs serve        # browse lineage and docs at :8080
```

## Layout

```
models/src/      staging models + sources.yml
models/dim/      dimensional models
analyses/        scratch/compiled-only SQL (empty scaffold)
macros/          project macros (empty scaffold)
seeds/           CSV seeds (empty scaffold)
snapshots/       SCD2 snapshots (empty scaffold)
tests/           singular tests (empty scaffold)
```

`target/`, `logs/`, `dbt_packages/` and `profiles.yml` are git-ignored.

## Troubleshooting

- **`depends on a source named 'raw.raw_hosts' which was not found`** — `source('raw', X)`
  takes the table's *declared* `name`, not its `identifier`. Here the name is `hosts` and
  `identifier: raw_hosts` points at the physical table.
- **`ERROR STALE` from `dbt source freshness`** — the data is older than `error_after`, or
  the thresholds do not match the dataset. Compare `max(loaded_at_field)` against
  `current_timestamp()` before changing anything.
- **`'year' is not a valid TimePeriod`** — use `day` and multiply, e.g. 6 years ≈ 2190 days.

For a full walkthrough see [`../docs/dbt_learning_guide.md`](../docs/dbt_learning_guide.md).
