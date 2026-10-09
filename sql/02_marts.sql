-- MART LAYER: joins staging into reporting tables and views for Tableau / Power BI.

-- 1) Account x month spine with reconstructed balance (running sum of signed flows; reconciles to the source balance within rounding)
DROP TABLE IF EXISTS mart_account_month;
CREATE TABLE mart_account_month AS
WITH RECURSIVE m(ym) AS (
    SELECT '1993-01' UNION ALL SELECT strftime('%Y-%m', date(ym || '-01', '+1 month')) FROM m WHERE ym < '1998-12'
),
flows AS (
    SELECT account_id, SUBSTR(txn_date,1,7) AS ym,
           SUM(CASE WHEN signed_amount > 0 THEN signed_amount ELSE 0 END)  AS credits,
           SUM(CASE WHEN signed_amount < 0 THEN -signed_amount ELSE 0 END) AS debits,
           SUM(signed_amount) AS net_flow, COUNT(*) AS txn_count
    FROM stg_trans GROUP BY account_id, SUBSTR(txn_date,1,7)
),
spine AS (SELECT a.account_id, m.ym FROM stg_account a JOIN m ON m.ym >= SUBSTR(a.open_date,1,7))
SELECT s.account_id, s.ym AS month,
       COALESCE(f.credits,0) AS credits, COALESCE(f.debits,0) AS debits,
       COALESCE(f.net_flow,0) AS net_flow, COALESCE(f.txn_count,0) AS txn_count,
       SUM(COALESCE(f.net_flow,0)) OVER (PARTITION BY s.account_id ORDER BY s.ym) AS est_balance
FROM spine s LEFT JOIN flows f ON f.account_id = s.account_id AND f.ym = s.ym;
CREATE INDEX idx_mam ON mart_account_month (account_id, month);

-- 2) Account 360: one row per account = account + owner + district + card + loan + 1998 balance behaviour
DROP TABLE IF EXISTS mart_account_360;
CREATE TABLE mart_account_360 AS
WITH owner AS (
    SELECT d.account_id, c.client_id, c.gender, c.age_at_1998, c.district_id AS client_district_id
    FROM stg_disp d JOIN stg_client c ON c.client_id = d.client_id
    WHERE d.disp_type = 'owner'
),
bal AS (
    SELECT account_id,
           AVG(est_balance) AS avg_balance_1998,
           MAX(CASE WHEN month = '1998-12' THEN est_balance END) AS balance_dec98,
           MIN(est_balance) AS min_balance_1998,
           SUM(CASE WHEN est_balance < 0 THEN 1 ELSE 0 END) AS negative_months_1998,
           SUM(txn_count) AS txn_count_1998
    FROM mart_account_month WHERE month >= '1998-01' GROUP BY account_id
),
card AS (
    SELECT d.account_id, COUNT(*) AS cards,
           CASE MAX(CASE c.card_type WHEN 'gold' THEN 3 WHEN 'classic' THEN 2 ELSE 1 END)
                WHEN 3 THEN 'gold' WHEN 2 THEN 'classic' ELSE 'junior' END AS top_card
    FROM stg_card c JOIN stg_disp d ON d.disp_id = c.disp_id GROUP BY d.account_id
),
base AS (
    SELECT a.account_id, a.open_date, a.statement_frequency, a.district_id,
           dist.district_name, dist.region, o.client_id AS owner_client_id, o.gender, o.age_at_1998,
           b.avg_balance_1998, b.balance_dec98, b.min_balance_1998, b.negative_months_1998, b.txn_count_1998,
           COALESCE(cd.cards,0) AS cards, cd.top_card,
           l.loan_id, l.amount AS loan_amount, l.status AS loan_status, l.is_bad AS loan_is_bad
    FROM stg_account a
    JOIN owner o ON o.account_id = a.account_id
    JOIN stg_district dist ON dist.district_id = a.district_id
    LEFT JOIN bal b ON b.account_id = a.account_id
    LEFT JOIN card cd ON cd.account_id = a.account_id
    LEFT JOIN stg_loan l ON l.account_id = a.account_id
)
SELECT base.*,
       CASE NTILE(4) OVER (ORDER BY avg_balance_1998 DESC) WHEN 1 THEN 'Premium' WHEN 4 THEN 'Basic' ELSE 'Standard' END AS tier
FROM base;
CREATE INDEX idx_m360 ON mart_account_360 (account_id);

-- ------------ reporting views ------------
DROP VIEW IF EXISTS vw_balance_trend_monthly;
CREATE VIEW vw_balance_trend_monthly AS
SELECT m.month, a.tier, a.region, COUNT(*) AS accounts, SUM(m.est_balance) AS total_balance,
       SUM(m.credits) AS credits, SUM(m.debits) AS debits
FROM mart_account_month m JOIN mart_account_360 a ON a.account_id = m.account_id
GROUP BY m.month, a.tier, a.region;

DROP VIEW IF EXISTS vw_tier_summary;
CREATE VIEW vw_tier_summary AS
SELECT tier, COUNT(*) AS accounts, ROUND(AVG(avg_balance_1998),0) AS avg_balance,
       ROUND(100.0 * SUM(CASE WHEN cards > 0 THEN 1 ELSE 0 END) / COUNT(*), 1) AS card_penetration_pct,
       SUM(CASE WHEN loan_id IS NOT NULL THEN 1 ELSE 0 END) AS loans,
       ROUND(100.0 * SUM(COALESCE(loan_is_bad,0)) / NULLIF(SUM(CASE WHEN loan_id IS NOT NULL THEN 1 ELSE 0 END),0), 1) AS bad_loan_pct,
       SUM(CASE WHEN negative_months_1998 > 0 THEN 1 ELSE 0 END) AS accounts_overdrawn_1998
FROM mart_account_360 GROUP BY tier;

DROP VIEW IF EXISTS vw_cashflow_monthly;
CREATE VIEW vw_cashflow_monthly AS
SELECT SUBSTR(txn_date,1,7) AS month, txn_type, operation, k_symbol, COUNT(*) AS txn_count, SUM(amount) AS amount
FROM stg_trans GROUP BY SUBSTR(txn_date,1,7), txn_type, operation, k_symbol;

DROP VIEW IF EXISTS vw_loan_portfolio;
CREATE VIEW vw_loan_portfolio AS
SELECT d.region, d.district_name, l.status_desc, l.duration_months,
       COUNT(*) AS loans, SUM(l.amount) AS loan_amount,
       SUM(CASE WHEN l.is_bad = 1 THEN l.amount ELSE 0 END) AS bad_amount, SUM(l.is_bad) AS bad_loans
FROM stg_loan l JOIN stg_account a ON a.account_id = l.account_id
JOIN stg_district d ON d.district_id = a.district_id
GROUP BY d.region, d.district_name, l.status_desc, l.duration_months;

DROP VIEW IF EXISTS vw_loan_watchlist;
CREATE VIEW vw_loan_watchlist AS
SELECT l.loan_id, l.account_id, l.loan_date, l.amount, l.duration_months, l.monthly_payment, l.status, l.status_desc,
       a.district_name, a.region, a.tier, a.balance_dec98, a.negative_months_1998,
       CASE WHEN a.balance_dec98 < 0 THEN 'Overdrawn' WHEN a.balance_dec98 < 3 * l.monthly_payment THEN 'Low cover' ELSE 'OK' END AS balance_cover
FROM stg_loan l JOIN mart_account_360 a ON a.account_id = l.account_id
WHERE l.status IN ('B','D');

DROP VIEW IF EXISTS vw_district_scorecard;
CREATE VIEW vw_district_scorecard AS
SELECT d.district_id, d.district_name, d.region, d.inhabitants, d.avg_salary, d.unemployment_96, d.crimes_96,
       COUNT(a.account_id) AS accounts, ROUND(AVG(a.avg_balance_1998),0) AS avg_balance,
       COUNT(a.loan_id) AS loans, SUM(COALESCE(a.loan_is_bad,0)) AS bad_loans,
       ROUND(100.0 * SUM(COALESCE(a.loan_is_bad,0)) / NULLIF(COUNT(a.loan_id),0), 1) AS bad_loan_pct
FROM stg_district d LEFT JOIN mart_account_360 a ON a.district_id = d.district_id
GROUP BY d.district_id, d.district_name, d.region, d.inhabitants, d.avg_salary, d.unemployment_96, d.crimes_96;

DROP VIEW IF EXISTS vw_card_summary;
CREATE VIEW vw_card_summary AS
SELECT COALESCE(top_card,'no card') AS card_type, tier, COUNT(*) AS accounts, ROUND(AVG(avg_balance_1998),0) AS avg_balance
FROM mart_account_360 GROUP BY COALESCE(top_card,'no card'), tier;

DROP VIEW IF EXISTS vw_standing_orders;
CREATE VIEW vw_standing_orders AS
SELECT purpose, COUNT(*) AS orders, SUM(amount) AS total_amount, ROUND(AVG(amount),0) AS avg_amount FROM stg_order GROUP BY purpose;
