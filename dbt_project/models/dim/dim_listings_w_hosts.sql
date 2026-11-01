{{
    
    config(
        materialized='table',
        transient='false'
    )
}}

with cte_listings as (
    select
    *
    from {{ ref('dim_listings_cleaned') }}
),
cte_hosts as (
    select
    *
    from {{ ref('dim_hosts_cleaned') }}
)
select

    l.listing_id,
    l.listing_url,
    l.listing_name,
    l.room_type,
    l.minimum_nights,
    l.price,
    h.host_id,
    h.host_name,
    h.host_is_superhost,
    h.host_created_at,
    greatest(l.updated_at, h.host_updated_at) as updated_at,
    l.created_at

from cte_listings as l
left join cte_hosts as h
on l.host_id = h.host_id