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
