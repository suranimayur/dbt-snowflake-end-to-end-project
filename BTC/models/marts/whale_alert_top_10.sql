with BASE as (
    select
    *
    from {{ ref('whale_alert') }}
    order by total_sent_usd desc
    limit 10
)

select * from BASE
