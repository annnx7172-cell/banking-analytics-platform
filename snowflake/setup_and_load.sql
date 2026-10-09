-- SNOWFLAKE VERSION (NOT RUN by the author of this kit: run it in your own Snowflake trial and fix any small syntax issues).
-- The Berka .asc files are semicolon-delimited with a header row.
CREATE DATABASE IF NOT EXISTS BANK_DB;
CREATE SCHEMA IF NOT EXISTS BANK_DB.RAW;  CREATE SCHEMA IF NOT EXISTS BANK_DB.STG;  CREATE SCHEMA IF NOT EXISTS BANK_DB.MART;
CREATE WAREHOUSE IF NOT EXISTS BANK_WH WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE;
USE WAREHOUSE BANK_WH; USE SCHEMA BANK_DB.RAW;

CREATE OR REPLACE FILE FORMAT berka_ff TYPE = CSV FIELD_DELIMITER = ';' SKIP_HEADER = 1 FIELD_OPTIONALLY_ENCLOSED_BY = '"' NULL_IF = ('') EMPTY_FIELD_AS_NULL = TRUE;
CREATE OR REPLACE STAGE berka_stage FILE_FORMAT = berka_ff;
-- Upload the 8 files (SnowSQL):  PUT file:///path/to/data_berka/*.asc @berka_stage;   (or use Snowsight > Load data)

CREATE OR REPLACE TABLE RAW_ACCOUNT  (account_id INT, district_id INT, frequency STRING, date INT);
CREATE OR REPLACE TABLE RAW_CLIENT   (client_id INT, birth_number INT, district_id INT);
CREATE OR REPLACE TABLE RAW_DISP     (disp_id INT, client_id INT, account_id INT, type STRING);
CREATE OR REPLACE TABLE RAW_CARD     (card_id INT, disp_id INT, type STRING, issued STRING);
CREATE OR REPLACE TABLE RAW_LOAN     (loan_id INT, account_id INT, date INT, amount NUMBER(12,0), duration INT, payments NUMBER(10,2), status STRING);
CREATE OR REPLACE TABLE RAW_ORDER    (order_id INT, account_id INT, bank_to STRING, account_to STRING, amount NUMBER(12,2), k_symbol STRING);
CREATE OR REPLACE TABLE RAW_DISTRICT (A1 INT, A2 STRING, A3 STRING, A4 INT, A5 INT, A6 INT, A7 INT, A8 INT, A9 INT, A10 NUMBER(5,1), A11 INT, A12 STRING, A13 NUMBER(5,2), A14 INT, A15 STRING, A16 INT);
CREATE OR REPLACE TABLE RAW_TRANS    (trans_id INT, account_id INT, date INT, type STRING, operation STRING, amount NUMBER(12,2), balance NUMBER(12,2), k_symbol STRING, bank STRING, account STRING);
COPY INTO RAW_ACCOUNT  FROM @berka_stage/account.asc.gz  ON_ERROR = 'ABORT_STATEMENT';
COPY INTO RAW_CLIENT   FROM @berka_stage/client.asc.gz   ON_ERROR = 'ABORT_STATEMENT';
COPY INTO RAW_DISP     FROM @berka_stage/disp.asc.gz     ON_ERROR = 'ABORT_STATEMENT';
COPY INTO RAW_CARD     FROM @berka_stage/card.asc.gz     ON_ERROR = 'ABORT_STATEMENT';
COPY INTO RAW_LOAN     FROM @berka_stage/loan.asc.gz     ON_ERROR = 'ABORT_STATEMENT';
COPY INTO RAW_ORDER    FROM @berka_stage/order.asc.gz    ON_ERROR = 'ABORT_STATEMENT';
COPY INTO RAW_DISTRICT FROM @berka_stage/district.asc.gz ON_ERROR = 'ABORT_STATEMENT';
COPY INTO RAW_TRANS    FROM @berka_stage/trans.asc.gz    ON_ERROR = 'ABORT_STATEMENT';
-- Check row counts against the pipeline log: trans 1,056,320; loan 682; account 4,500; client 5,369.

-- STAGING (Snowflake-specific: QUALIFY dedupes without a subquery, TO_DATE parses YYMMDD)
CREATE OR REPLACE TABLE BANK_DB.STG.STG_TRANS AS
SELECT trans_id, account_id, TO_DATE('19' || LPAD(date::STRING, 6, '0'), 'YYYYMMDD') AS txn_date,
       IFF(type = 'VYBER', 'VYDAJ', type) AS txn_type,
       COALESCE(operation, 'NOT_APPLICABLE') AS operation, amount,
       IFF(type = 'PRIJEM', amount, -amount) AS signed_amount, balance AS balance_reported,
       IFF(k_symbol IS NULL OR TRIM(k_symbol) = '', 'NONE', TRIM(k_symbol)) AS k_symbol, bank, account
FROM BANK_DB.RAW.RAW_TRANS
QUALIFY ROW_NUMBER() OVER (PARTITION BY account_id, date, type, operation, amount, balance, k_symbol ORDER BY trans_id) = 1;

CREATE OR REPLACE TABLE BANK_DB.STG.STG_LOAN AS
SELECT loan_id, account_id, amount, duration AS duration_months, payments AS monthly_payment, status,
       DECODE(status, 'A','Finished, paid','B','Finished, unpaid','C','Running, OK','D','Running, in debt') AS status_desc,
       IFF(status IN ('B','D'), 1, 0) AS is_bad,
       TO_DATE('19' || LPAD(date::STRING, 6, '0'), 'YYYYMMDD') AS loan_date
FROM BANK_DB.RAW.RAW_LOAN;

-- Port the rest of sql/01_staging.sql and sql/02_marts.sql the same way. Syntax notes:
--   SQLite SUBSTR(x,1,7) -> TO_CHAR(txn_date,'YYYY-MM');  strftime / date(...,'+1 month') -> DATEADD(month,1,...);  printf -> LPAD
--   the recursive month spine -> GENERATOR / a calendar table;  NTILE(4) OVER (...) works unchanged.

-- Scheduling: a TASK replaces the cron / Power Automate trigger for the SQL part
-- CREATE OR REPLACE TASK BANK_DB.MART.REFRESH_MARTS WAREHOUSE = BANK_WH SCHEDULE = 'USING CRON 0 6 * * * Asia/Kolkata' AS CALL BANK_DB.MART.SP_REFRESH();
