CREATE DATABASE dbt_landing_db;

USE dbt_landing_db;

CREATE SCHEMA dbt_landing_db.dbt_landing_schema;

use schema dbt_landing_db.dbt_landing_schema;

CREATE DATABASE RAW_DB;
USE RAW_DB;
CREATE SCHEMA RAW_DB.RAW_SCHEMA;
USE RAW_DB.RAW_SCHEMA;



CREATE OR REPLACE TABLE raw_listings

                    (id integer,

                     listing_url string,

                     name string,

                     room_type string,

                     minimum_nights integer,

                     host_id integer,

                     price string,

                     created_at datetime,

                     updated_at datetime);

CREATE OR REPLACE TABLE raw_reviews

                    (listing_id integer,

                     date datetime,

                     reviewer_name string,

                     comments string,

                     sentiment string);


                     CREATE OR REPLACE TABLE raw_hosts

                    (id integer,

                     name string,

                     is_superhost string,

                     created_at datetime,

                     updated_at datetime);



COPY INTO raw_listings (id,

                        listing_url,

                        name,

                        room_type,

                        minimum_nights,

                        host_id,

                        price,

                        created_at,

                        updated_at)

                   from 's3://dbt-datasets/listings.csv'

                    FILE_FORMAT = (type = 'CSV' skip_header = 1

                    FIELD_OPTIONALLY_ENCLOSED_BY = '"');

COPY INTO raw_reviews (listing_id, date, reviewer_name, comments, sentiment)

                   from 's3://dbt-datasets/reviews.csv'RAW_DB.RAW_SCHEMA.RAW_HOSTS

                    FILE_FORMAT = (type = 'CSV' skip_header = 1

                    FIELD_OPTIONALLY_ENCLOSED_BY = '"');
COPY INTO raw_hosts (id, name, is_superhost, created_at, updated_at)

                   from 's3://dbt-datasets/hosts.csv'

                    FILE_FORMAT = (type = 'CSV' skip_header = 1

                    FIELD_OPTIONALLY_ENCLOSED_BY = '"');

SELECT TOP 10* FROM RAW_DB.RAW_SCHEMA.RAW_HOSTS ;

select top 10* from raw_listings

select top 10* from raw_hosts

select top 10* from raw_reviews

show tables in database dbt_landing_db;

-- transformation logic listing table left side and hosting table in right with host_id as join key

select max(created_at)  from raw_db.raw_schema.raw_hosts ;

select * from  raw_db.raw_schema.raw_hosts ;

update raw_db.raw_schema.raw_hosts
set updated_at = current_timestamp()
where id = 1581;