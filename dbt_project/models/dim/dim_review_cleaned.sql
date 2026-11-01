with src_review as (

    select * from {{ ref('src_review') }}

)
select
    listing_id,
    review_date,
    reviewer_name,
    review_text,
    review_sentiment
from src_review