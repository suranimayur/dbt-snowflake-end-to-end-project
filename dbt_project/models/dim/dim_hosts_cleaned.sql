with src_hosts as (

    select * from {{ ref('src_hosts') }}

),

cleaned as (

    select
        host_id,
        coalesce(host_name, 'Anonymous')        as host_name,
        coalesce(host_is_superhost, 'f')        as host_is_superhost,
        host_created_at,
        host_updated_at
    from src_hosts
    where host_id is not null

)

select * from cleaned
