# dbt Training — Analytics Engineering on Snowflake

A hands-on dbt project that models an Airbnb-style dataset (hosts, listings and reviews)
from raw Snowflake tables into tested, documented dimensional models.

The repository is a learning workspace: every model, config choice and test is small
enough to read in one sitting, and the docs explain the reasoning behind it.

## Stack

| Layer | Tool / version |
| :--- | :--- |
| Transformation | dbt Core 1.12.6 |
| Adapter | dbt-snowflake 1.12.4 |
| Warehouse | Snowflake — raw in `RAW_DB.RAW_SCHEMA`, models built into `DBT_LANDING_DB.DBT_LANDING_SCHEMA` |
| Language | SQL + Jinja, Python 3.13 |
| Environment | `uv` (see `pyproject.toml` / `uv.lock`) |

## Data flow

```
RAW_DB.RAW_SCHEMA                         (loaded outside dbt: EL, not T)
  RAW_HOSTS   RAW_LISTINGS   RAW_REVIEWS
       |            |             |
       |   source('raw', ...)     |
       v            v             v
models/src/ — materialized as TABLES (tag: src)
  src_hosts    src_listings    src_review        ← rename/type-cast only
       |            |             |
       v            v             v
models/dim/ — materialized as VIEWS
  dim_hosts_cleaned   dim_listings_cleaned   dim_review_cleaned
             \              /
              v            v
          dim_listings_w_hosts — materialized as TABLE
              (denormalised listing × host, one row per listing)
```

Row counts in the current snapshot: 14,111 hosts, 17,499 listings, 410,284 reviews.

## Repository layout

```
dbt-training/
├── dbt_project/                # the dbt project
│   ├── models/
│   │   ├── src/                # staging models + sources.yml
│   │   └── dim/                # dimensional models
│   ├── analyses/  macros/  seeds/  snapshots/  tests/   # scaffolds, unused
│   └── dbt_project.yml         # paths, materialisation defaults
├── docs/
│   ├── dbt_learning_guide.md   # full walkthrough of models, config and tests
│   └── dbt_snowflake_commands.md
├── src/dbt_training/           # Python package (placeholder CLI entry point)
├── logs/
├── pyproject.toml              # Python dependencies (uv)
└── uv.lock
```

## Prerequisites

- Python 3.13 and [`uv`](https://docs.astral.sh/uv/)
- A Snowflake account with `RAW_DB.RAW_SCHEMA` populated (`RAW_HOSTS`, `RAW_LISTINGS`, `RAW_REVIEWS`)
- A dbt profile named `dbt_project` with a `dev` target
  (`~/.dbt/profiles.yml`, or a repo-local `profiles.yml` — it is git-ignored)

## Quickstart

```bash
uv sync                  # create .venv and install dbt + adapter
cd dbt_project
dbt debug                # confirm the Snowflake connection before anything else
dbt run                  # build all 7 models
dbt test                 # run the 8 source tests
dbt source freshness     # freshness of raw.hosts and raw.reviews
dbt docs generate && dbt docs serve   # browse lineage and column docs
```

Useful selective runs:

```bash
dbt run --select src_hosts          # one model
dbt run --select src                # everything tagged 'src'
dbt run --select +dim_listings_w_hosts   # the model and its ancestors
```

## Documentation

- [`docs/dbt_learning_guide.md`](docs/dbt_learning_guide.md) — end-to-end guide: data
  layers, every model explained, configuration, tests, freshness, troubleshooting the
  errors this project actually hit, and exercises.
- [`docs/dbt_snowflake_commands.md`](docs/dbt_snowflake_commands.md) — production-oriented
  dbt command reference.

## Conventions

- Staging models (`src_*`) only rename columns and apply light typing; they never join.
- Dimensional models (`dim_*`) apply business rules and joins, and are views unless the
  query is expensive enough to justify a table.
- Sources are declared once in `models/src/sources.yml`; models never reference raw table
  names literally.
- `dbt_project.yml` sets defaults per folder; a model-level `config()` block overrides them.

## Author

suranimayur — surani.mayur@gmail.com
