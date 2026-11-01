with cte_1 as (
    select id, listing_url, name, room_type, host_id, minimum_nights, price, created_at, updated_at
    from {{ source('raw', 'listings') }}
)

select 
    id as listing_id,
    listing_url,
    name as listing_name,
    room_type ,
    host_id as host_id,
    minimum_nights as minimum_nights,
    price as price_sdr,
    created_at as created_at,
    updated_at as updated_at
from cte_1