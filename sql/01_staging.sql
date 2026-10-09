-- STAGING LAYER (SQLite dialect; Snowflake / SQL Server ports in /snowflake and /sqlserver)
-- Raw tables are never modified. Staging standardises codes, converts dates, quarantines bad rows.
-- Berka dates are stored as YYMMDD integers -> converted to ISO dates (19YY-MM-DD).

DROP TABLE IF EXISTS stg_district;
CREATE TABLE stg_district AS
SELECT A1 AS district_id, A2 AS district_name, A3 AS region, A4 AS inhabitants,
       A10 AS urban_ratio_pct, A11 AS avg_salary,
       CASE WHEN TRIM(CAST(A12 AS TEXT)) = '?' THEN NULL ELSE CAST(A12 AS REAL) END AS unemployment_95,
       A13 AS unemployment_96, A14 AS entrepreneurs_per_1000,
       CASE WHEN TRIM(CAST(A15 AS TEXT)) = '?' THEN NULL ELSE CAST(A15 AS INTEGER) END AS crimes_95,
       A16 AS crimes_96
FROM raw_district;

DROP TABLE IF EXISTS stg_account;
CREATE TABLE stg_account AS
SELECT account_id, district_id,
       CASE frequency WHEN 'POPLATEK MESICNE' THEN 'Monthly statement'
                      WHEN 'POPLATEK TYDNE' THEN 'Weekly statement'
                      WHEN 'POPLATEK PO OBRATU' THEN 'Statement after transaction'
                      ELSE 'Unknown' END AS statement_frequency,
       '19' || SUBSTR(CAST(date AS TEXT),1,2) || '-' || SUBSTR(CAST(date AS TEXT),3,2) || '-' || SUBSTR(CAST(date AS TEXT),5,2) AS open_date
FROM raw_account;

-- birth_number = YYMMDD, month + 50 for women
DROP TABLE IF EXISTS stg_client;
CREATE TABLE stg_client AS
SELECT client_id, district_id,
       CASE WHEN CAST(SUBSTR(printf('%06d', birth_number),3,2) AS INT) > 50 THEN 'F' ELSE 'M' END AS gender,
       '19' || SUBSTR(printf('%06d', birth_number),1,2) || '-' ||
       printf('%02d', CASE WHEN CAST(SUBSTR(printf('%06d', birth_number),3,2) AS INT) > 50
                           THEN CAST(SUBSTR(printf('%06d', birth_number),3,2) AS INT) - 50
                           ELSE CAST(SUBSTR(printf('%06d', birth_number),3,2) AS INT) END) || '-' ||
       SUBSTR(printf('%06d', birth_number),5,2) AS birth_date
FROM raw_client;

ALTER TABLE stg_client ADD COLUMN age_at_1998 INTEGER;
UPDATE stg_client SET age_at_1998 = 1998 - CAST(SUBSTR(birth_date,1,4) AS INT);

DROP TABLE IF EXISTS stg_disp;
CREATE TABLE stg_disp AS
SELECT disp_id, client_id, account_id, LOWER(type) AS disp_type FROM raw_disp;

DROP TABLE IF EXISTS stg_card;
CREATE TABLE stg_card AS
SELECT card_id, disp_id, type AS card_type,
       '19' || SUBSTR(issued,1,2) || '-' || SUBSTR(issued,3,2) || '-' || SUBSTR(issued,5,2) AS issued_date
FROM raw_card;

DROP TABLE IF EXISTS stg_loan;
CREATE TABLE stg_loan AS
SELECT loan_id, account_id, amount, duration AS duration_months, payments AS monthly_payment, status,
       CASE status WHEN 'A' THEN 'Finished, paid' WHEN 'B' THEN 'Finished, unpaid'
                   WHEN 'C' THEN 'Running, OK' WHEN 'D' THEN 'Running, in debt' END AS status_desc,
       CASE WHEN status IN ('B','D') THEN 1 ELSE 0 END AS is_bad,
       '19' || SUBSTR(CAST(date AS TEXT),1,2) || '-' || SUBSTR(CAST(date AS TEXT),3,2) || '-' || SUBSTR(CAST(date AS TEXT),5,2) AS loan_date
FROM raw_loan;

DROP TABLE IF EXISTS stg_order;
CREATE TABLE stg_order AS
SELECT order_id, account_id, amount,
       CASE TRIM(COALESCE(k_symbol,'')) WHEN 'SIPO' THEN 'Household' WHEN 'POJISTNE' THEN 'Insurance'
            WHEN 'LEASING' THEN 'Leasing' WHEN 'UVER' THEN 'Loan payment' ELSE 'Unspecified' END AS purpose
FROM raw_order;

-- Transactions: standardise codes, sign the amount, drop exact duplicate postings (different trans_id only)
DROP TABLE IF EXISTS stg_trans;
CREATE TABLE stg_trans AS
SELECT trans_id, account_id, txn_date, txn_type, operation, amount, signed_amount, balance_reported, k_symbol, bank, account
FROM (
  SELECT trans_id, account_id,
         '19' || SUBSTR(CAST(date AS TEXT),1,2) || '-' || SUBSTR(CAST(date AS TEXT),3,2) || '-' || SUBSTR(CAST(date AS TEXT),5,2) AS txn_date,
         CASE WHEN type = 'VYBER' THEN 'VYDAJ' ELSE type END AS txn_type,          -- legacy withdrawal code -> VYDAJ
         COALESCE(operation, 'NOT_APPLICABLE') AS operation,                       -- interest postings carry no operation
         amount,
         CASE WHEN type = 'PRIJEM' THEN amount ELSE -amount END AS signed_amount,
         balance AS balance_reported,
         CASE WHEN k_symbol IS NULL OR TRIM(k_symbol) = '' THEN 'NONE' ELSE TRIM(k_symbol) END AS k_symbol,  -- NULL and ' ' both mean "none"
         bank, account,
         ROW_NUMBER() OVER (PARTITION BY account_id, date, type, operation, amount, balance, k_symbol ORDER BY trans_id) AS rn
  FROM raw_trans
) WHERE rn = 1;

DROP TABLE IF EXISTS rej_trans;
CREATE TABLE rej_trans AS
SELECT trans_id, account_id, date, type, operation, amount, balance, k_symbol, 'DUPLICATE_POSTING' AS reject_reason
FROM (
  SELECT t.*, ROW_NUMBER() OVER (PARTITION BY account_id, date, type, operation, amount, balance, k_symbol ORDER BY trans_id) AS rn
  FROM raw_trans t
) WHERE rn > 1;

CREATE INDEX idx_stg_trans_acct_date ON stg_trans (account_id, txn_date);
CREATE INDEX idx_stg_disp_acct ON stg_disp (account_id);
CREATE INDEX idx_stg_disp_client ON stg_disp (client_id);
CREATE INDEX idx_stg_loan_acct ON stg_loan (account_id);
