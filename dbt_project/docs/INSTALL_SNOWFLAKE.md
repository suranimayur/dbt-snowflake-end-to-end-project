# Snowflake Setup for FCT Reviews Training

This file documents how to run the FCT reviews scenarios with SnowSQL.

## Requirements

- SnowSQL installed and configured.
- Access to the Snowflake account used for the dbt project.
- A database/schema pair for raw source data and one for landing FCT data.

Recommended Snowflake objects:

```sql
CREATE DATABASE IF NOT EXISTS RAW_DB;
CREATE DATABASE IF NOT EXISTS DBT_LANDING_DB;

CREATE SCHEMA IF NOT EXISTS RAW_DB.RAW_SCHEMA;
CREATE SCHEMA IF NOT EXISTS DBT_LANDING_DB.DBT_LANDING_SCHEMA;
```

## SnowSQL Connection Profile

Add or update a profile in SnowSQL, typically `~/.snowsql/config`, for example:

```ini
[dev]
account = MKNOBGE-MW11651
user = SURANI001
password = <your_password>
database = DBT_LANDING_DB
schema = DBT_LANDING_SCHEMA
warehouse = COMPUTE_WH
role = ACCOUNTADMIN
```

Adjust `account`, `user`, `password`, `database`, `schema`, `warehouse`, and `role` to your environment.

## Verify Connection

```bash
snowsql -c dev -q "SELECT CURRENT_ACCOUNT(), CURRENT_DATABASE(), CURRENT_SCHEMA();"
```

## Mandatory Raw Table Setup

Create the raw reviews table referenced by the documentation:

```sql
CREATE TABLE IF NOT EXISTS RAW_DB.RAW_SCHEMA.RAW_REVIEWS (
    LISTING_ID NUMBER,
    DATE TIMESTAMP_NTZ,
    REVIEWER_NAME VARCHAR,
    REVIEW_COMMENTS VARCHAR,
    REVIEW_STATEMNET VARCHAR
);
```

Make sure the dbt source `raw.reviews` points to this table, or override the source name in `dbt_project/models/src/src_review.sql` to match your Snowflake source.

## Optional Helper for Repeated Run Verification

Create a small script `docs/fct_run_verification.sql` and execute it after each scenario:

```sql
-- Example helper. Replace with your actual landing table names.
-- SELECT * FROM DBT_LANDING_DB.DBT_LANDING_SCHEMA.FCT_REVIEWS;
-- SELECT * FROM DBT_LANDING_DB.DBT_LANDING_SCHEMA.FCT_REVIEWS_APPEND;
-- SELECT * FROM DBT_LANDING_DB.DBT_LANDING_SCHEMA.FCT_REVIEWS_DELETE_INSERT;
-- SELECT * FROM DBT_LANDING_DB.DBT_LANDING_SCHEMA.FCT_REVIEWS_MERGE;
```
