# FCT Reviews Strategies — Snowflake Training Day 07

This document describes the FCT `reviews` models and the four Snowflake scenarios that were used to validate them:

1. Append
2. Insert + Delete
3. Merge
4. Delete-Insert duplicate cleanup

It also documents the micro-batch model added for this training.

All statements below assume the raw review source is:

```sql
RAW_DB.RAW_SCHEMA.RAW_REVIEWS
```

and the FCT landing table is:

```sql
DBT_LANDING_DB.DBT_LANDING_SCHEMA.FCT_REVIEWS
```

The source model in this dbt project is `src_review` and outputs these columns:

| Source column | FCT column |
|---|---|
| `listing_id` | `listing_id` |
| `date` | `review_date` |
| `reviewer_name` | `reviewer_name` |
| `comments` | `review_comments` |
| `sentiment` | `review_statement` |

Each FCT model reads:

```sql
SELECT
    listing_id,
    review_date,
    reviewer_name,
    review_text AS review_comments,
    review_sentiment AS review_statement
FROM {{ ref('src_review') }}
WHERE review_text IS NOT NULL
```

The existing incremental models are:

| Model | Behavior |
|---|---|
| `fct_reviews.sql` | Base incremental FCT table |
| `fct_reviews_append.sql` | Append-only strategy |
| `fct_reviews_delete_insert.sql` | Delete+insert strategy |
| `fct_reviews_merge.sql` | Merge strategy |
| `fct_reviews_micro_batch.sql` | Micro-batch strategy, configured as `delete+insert` |

---

## 1. Append Strategy

Append adds new source rows to the existing FCT table. It does not update or delete existing rows.

### Target table

```sql
DBT_LANDING_DB.DBT_LANDING_SCHEMA.FCT_REVIEWS_APPEND
```

### Snowflake commands

Update an existing review:

```sql
UPDATE RAW_DB.RAW_SCHEMA.RAW_REVIEWS
SET DATE = current_timestamp()
WHERE LISTING_ID = 6258535; -- 27
```

Insert a new review:

```sql
INSERT INTO RAW_DB.RAW_SCHEMA.RAW_REVIEWS
VALUES (888888, current_timestamp(), 'Rahul', 'It was good', 'positive'); -- 1
```

Delete a source review:

```sql
DELETE FROM RAW_DB.RAW_SCHEMA.RAW_REVIEWS
WHERE LISTING_ID = 6261883; -- 15
```

Select the append scenario output:

```sql
SELECT *
FROM DBT_LANDING_DB.DBT_LANDING_SCHEMA.FCT_REVIEWS_APPEND
WHERE LISTING_ID = 888888 -- 6261883 -- 6258535
```

### Expected behavior

- The append model contains all non-null rows from the source.
- Existing rows in the FCT table are preserved; new rows are added.
- The deleted source review `6261883` is not present in the append result.
- Updated and inserted rows appear only if they are loaded into the source table used by the FCT model.

---

## 2. Insert + Delete Strategy

This scenario tests the combination of inserts and deletes on source records.

### Target table

```sql
DBT_LANDING_DB.DBT_LANDING_SCHEMA.FCT_REVIEWS_DELETE_INSERT
```

### Snowflake commands

Update a source record:

```sql
UPDATE RAW_DB.RAW_SCHEMA.RAW_REVIEWS
SET DATE = current_timestamp(),
    REVIEWER_NAME = 'Insert + Delete Scenario'
WHERE LISTING_ID = 10942670;
```

Insert a new source review:

```sql
INSERT INTO RAW_DB.RAW_SCHEMA.RAW_REVIEWS
VALUES (6666666, current_timestamp(), 'Rahul', 'It was good', 'positive'); -- 1
```

Verify the inserted source record:

```sql
SELECT *
FROM RAW_DB.RAW_SCHEMA.RAW_REVIEWS
WHERE LISTING_ID = 6666666
```

Delete a source review:

```sql
DELETE FROM RAW_DB.RAW_SCHEMA.RAW_REVIEWS
WHERE LISTING_ID = 10989650;
```

Select the delete-insert scenario output:

```sql
SELECT *
FROM DBT_LANDING_DB.DBT_LANDING_SCHEMA.FCT_REVIEWS_DELETE_INSERT
WHERE LISTING_ID = 10989650; --- Still existing if deleted from Source

SELECT *
FROM DBT_LANDING_DB.DBT_LANDING_SCHEMA.FCT_REVIEWS_DELETE_INSERT
WHERE LISTING_ID = 10942670;

DROP TABLE FCT_REVIEWS_DELETE_INSERT;

SELECT *
FROM DBT_LANDING_DB.DBT_LANDING_SCHEMA.FCT_REVIEWS_DELETE_INSERT
WHERE LISTING_ID = 6666666;
```

Also verify the recurring delete-insert configuration:

```sql
{{
  config(
    materialized = 'incremental',
    incremental_strategy = 'delete+insert',
    unique_key = 'listing_id'
  )
}}

WITH CTE1 AS
(
    SELECT * FROM {{ ref('src_reviews') }}
)

SELECT * FROM CTE1 WHERE REVIEW_COMMENTS IS NOT NULL

{% if is_incremental() %}

AND review_date > (SELECT MAX(review_date) FROM {{ this }})

{% endif %}
```

### Expected behavior

- The delete-insert model contains all non-null source rows.
- A source record that is deleted from `RAW_DB.RAW_SCHEMA.RAW_REVIEWS` does not appear in the FCT table.
- A source record that is inserted still appears after the model refresh.
- The `unique_key = 'listing_id'` config means the model should keep one row per listing after the delete-insert operation.

---

## 3. Merge Strategy

The merge scenario validates updates, inserts, deletes, and duplicate handling in one refresh.

### Target table

```sql
DBT_LANDING_DB.DBT_LANDING_SCHEMA.FCT_REVIEWS_MERGE
```

### Snowflake commands

Update a source record:

```sql
UPDATE RAW_DB.RAW_SCHEMA.RAW_REVIEWS
SET DATE = current_timestamp(),
    REVIEWER_NAME = 'Merge Scenario'
WHERE LISTING_ID = 6314674; -- 6
```

Insert a new source review:

```sql
INSERT INTO RAW_DB.RAW_SCHEMA.RAW_REVIEWS
VALUES (777777, current_timestamp(), 'Rahul', 'It was good', 'positive'); -- 1
```

Delete a source review:

```sql
DELETE FROM RAW_DB.RAW_SCHEMA.RAW_REVIEWS
WHERE LISTING_ID = 6316226; -- 63
```

Verify the merged result for the deleted source record:

```sql
SELECT *
FROM FCT_REVIEWS_MERGE
WHERE LISTING_ID = 6316226; -- 6314674
```

Check for duplicate rows in the merged table:

```sql
SELECT COUNT(*), LISTING_ID, REVIEWER_NAME, REVIEW_COMMENTS, REVIEW_STATEMNET
FROM FCT_REVIEWS_MERGE
GROUP BY LISTING_ID, REVIEWER_NAME, REVIEW_COMMENTS, REVIEW_STATEMNET
HAVING COUNT(1) > 1
```

Select all source reviews:

```sql
SELECT *
FROM RAW_DB.RAW_SCHEMA.RAW_REVIEWS
```

Delete duplicate source rows by windowing on `LISTING_ID`:

```sql
DELETE FROM RAW_DB.RAW_SCHEMA.RAW_REVIEWS
WHERE LISTING_ID IN (
    SELECT LISTING_ID
    FROM (
        SELECT
            LISTING_ID,
            ROW_NUMBER() OVER (
                PARTITION BY LISTING_ID
                ORDER BY LISTING_ID
            ) AS RN
        FROM RAW_DB.RAW_SCHEMA.RAW_REVIEWS
    )
    WHERE RN > 1
);
```

After cleanup, verify:

```sql
UPDATE RAW_DB.RAW_SCHEMA.RAW_REVIEWS
SET DATE = current_timestamp(),
    REVIEWER_NAME = 'Merge Scenario'
WHERE LISTING_ID = 6659150; -- 1
```

Delete the source record used for duplicate cleanup:

```sql
DELETE FROM RAW_DB.RAW_SCHEMA.RAW_REVIEWS
WHERE LISTING_ID = ; -- 63
```

Verify the merge result for the updated source record:

```sql
SELECT * FROM FCT_REVIEWS_MERGE WHERE LISTING_ID = 6659150;
```

Verify that deleting a source record does not affect a non-impacted merge target:

```sql
SELECT * FROM FCT_REVIEWS_MERGE WHERE LISTING_ID = 6834489; -- non-impact on deleted source record
```

---

## 4. Delete + Insert Strategy

The final scenario verifies that the delete+insert behavior works end to end, including the incremental configuration used for the `delete+insert` strategy.

### Snowflake commands

Update a source record:

```sql
UPDATE RAW_DB.RAW_SCHEMA.RAW_REVIEWS
SET DATE = current_timestamp(),
    REVIEWER_NAME = 'Insert + Delete Scenario'
WHERE LISTING_ID = 10942670;
```

Insert a new source review:

```sql
INSERT INTO RAW_DB.RAW_SCHEMA.RAW_REVIEWS
VALUES (6666666, current_timestamp(), 'Rahul', 'It was good', 'positive'); -- 1
```

Verify the inserted source record:

```sql
SELECT *
FROM RAW_DB.RAW_SCHEMA.RAW_REVIEWS
WHERE LISTING_ID = 6666666
```

Delete a source review:

```sql
DELETE FROM RAW_DB.RAW_SCHEMA.RAW_REVIEWS
WHERE LISTING_ID = 10989650;
```

Select the delete-insert model:

```sql
SELECT *
FROM FCT_REVIEWS_DELETE_INSERT
WHERE LISTING_ID = 10989650; --- Still existing if deleted from Source

SELECT *
FROM FCT_REVIEWS_DELETE_INSERT
WHERE LISTING_ID = 10942670;

DROP TABLE FCT_REVIEWS_DELETE_INSERT;

SELECT *
FROM FCT_REVIEWS_DELETE_INSERT
WHERE LISTING_ID = 6666666;
```

Re-apply the delete+insert incremental config:

```sql
{{
  config(
    materialized = 'incremental',
    incremental_strategy = 'delete+insert',
    unique_key = 'listing_id'
  )
}}

WITH CTE1 AS
(
    SELECT * FROM {{ ref('src_reviews') }}
)

SELECT * FROM CTE1 WHERE REVIEW_COMMENTS IS NOT NULL

{% if is_incremental() %}

AND review_date > (SELECT MAX(review_date) FROM {{ this }})

{% endif %}
```

### Expected behavior

- The FCT table reflects source rows after the delete+insert operation.
- A deleted source review does not remain in the FCT table after the refresh.
- An inserted source review remains in the FCT table.
- The duplicate source rows are cleaned before the model refresh using `ROW_NUMBER()`.
- The incremental config uses `unique_key = 'listing_id'` and copies from `{{ ref('src_reviews') }}`.

---

## 5. Micro-Batch Strategy

The micro-batch model is a smaller incremental unit designed to process and persist small batches of source rows instead of one full refresh. In this project it is implemented as a table materialized with the delete+insert strategy and `unique_key = 'listing_id'`, so each run refreshes only the changed batches and keeps one row per listing.

### Model

File: `dbt_project/models/fct/fct_reviews_micro_batch.sql`

```sql
{{
  config(
    materialized = 'table',
    transient = false,
    incremental_strategy = 'delete+insert',
    unique_key = 'listing_id'
  )
}}

WITH source_reviews AS (
    SELECT
        listing_id,
        review_date,
        reviewer_name,
        review_text,
        review_sentiment
    FROM {{ ref('src_review') }}
)

SELECT
    listing_id,
    review_date,
    reviewer_name,
    review_text AS review_comments,
    review_sentiment AS review_statement
FROM source_reviews
WHERE review_text IS NOT NULL
```

### Snowflake commands

After inserting the new micro-batch review:

```sql
INSERT INTO RAW_DB.RAW_SCHEMA.RAW_REVIEWS
VALUES (999999, current_timestamp(), 'Rahul', 'It was good', 'positive'); -- 1
```

Select the micro-batch FCT table:

```sql
SELECT *
FROM DBT_LANDING_DB.DBT_LANDING_SCHEMA.FCT_REVIEWS
WHERE LISTING_ID = 999999;
```

Select the partial source review created for the micro-batch:

```sql
SELECT *
FROM RAW_DB.RAW_SCHEMA.RAW_REVIEWS
WHERE LISTING_ID = 999999;
```

### Expected behavior

- The micro-batch model contains all non-null source rows.
- New rows are added without deleting existing rows.
- The deleted source review `6261883` is not present in the append result.
- Updated and inserted rows appear only if they are loaded into the source table used by the FCT model.
- The model is materialized as a table and can be refreshed in batches.

---

## Notes

- These queries are Snowflake-specific: `UPDATE`, `DELETE`, `INSERT`, `DROP TABLE`, `ROW_NUMBER()`, and `current_timestamp()` are all standard Snowflake SQL, but the exact table names, schemas, and permissions must be configured in your Snowflake account.
- The dbt models in `dbt_project/models/fct/` do not receive raw SQL commands. They must be refreshed with `dbt run` after the source data is updated.
