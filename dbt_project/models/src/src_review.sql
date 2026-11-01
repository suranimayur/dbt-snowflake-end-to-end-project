with cte_1 as (
    select listing_id, date, reviewer_name, comments, sentiment
    from {{ source('raw', 'reviews') }}
)

select 
    listing_id,
    date as review_date,
    reviewer_name,
    comments as review_text,
    sentiment as review_sentiment
from cte_1