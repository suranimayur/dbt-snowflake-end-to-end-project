with src_listintgs as (

    select * from {{ ref('src_listings') }}

)
select
listing_id,
listing_url,
listing_name,
room_type,
host_id,
CASE WHEN minimum_nights = 0 THEN 1 ELSE minimum_nights END as minimum_nights,
REPLACE(price_sdr,'$')::NUMBER(10,2) as price,
created_at,
updated_at


from src_listintgs