with whales as (
select
output_address,
sum(output_value) as total_sent,
count(*) as txn_count
from {{ ref('stg_btc_transactions') }}
 where output_value > 10
group by output_address
order by total_sent desc
),
LATEST_PRICE AS (
    select
    close_price_usd as  price
    from {{ ref('btc_usd_max') }}
    where to_date(replace(event_date,' UTC','')) = current_date()
)
select
w.output_address,
w.total_sent,
w.txn_count
from whales w
order by total_sent desc
