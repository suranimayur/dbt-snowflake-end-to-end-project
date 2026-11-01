{{ config(
    materialized='table',
    transient=true,
    tags =['src'],
    alias='src_hosts')
}}

with cte_1 as (
    select id, name, is_superhost, created_at, updated_at
    from {{ source('raw', 'hosts') }}
)

select 
    id as host_id,
    name as host_name,
    is_superhost as host_is_superhost,
    created_at as host_created_at,
    updated_at as host_updated_at
from cte_1