
{{ config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key='hash_key') 
}}


with flattened_outputs as (

select
tx.hash_key,
tx.block_number,
tx.block_timestamp,
tx.is_coinbase,
f.value:address::string as output_address,
f.value:value::FLOAT as output_value

from {{ ref("stg_btc")}} tx,
lateral flatten(input => outputs) f

where f.value:address is not null

{% if is_incremental() %}

and tx.BLOCK_TIMESTAMP >= (select max(BLOCK_TIMESTAMP) from {{ this }})

{% endif %}
)
select 
hash_key,
block_number,
block_timestamp,
is_coinbase,
output_address,
output_value

from 

flattened_outputs
