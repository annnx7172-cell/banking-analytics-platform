-- Each check returns: check_name | layer | severity | failed_rows | description. severity FAIL = data defect, WARN = business flag.
-- ---- completeness / consistency (found issues in real data) ----
SELECT 'DISTRICT_MISSING_VALUE','raw','FAIL', COUNT(*), 'District rows with ? placeholders in unemployment_95 / crimes_95' FROM raw_district WHERE TRIM(CAST(A12 AS TEXT))='?' OR TRIM(CAST(A15 AS TEXT))='?';
SELECT 'TXN_SYMBOL_INCONSISTENT_ENCODING','raw','FAIL', COUNT(*), 'k_symbol uses a single space for none while other rows use NULL' FROM raw_trans WHERE k_symbol IS NOT NULL AND TRIM(k_symbol)='';
SELECT 'TXN_LEGACY_TYPE_CODE','raw','FAIL', COUNT(*), 'type=VYBER duplicates the withdrawal code VYDAJ' FROM raw_trans WHERE type='VYBER';
SELECT 'TXN_ZERO_AMOUNT','raw','FAIL', COUNT(*), 'Transactions with amount = 0' FROM raw_trans WHERE amount <= 0;
SELECT 'TXN_DUPLICATE_POSTING','raw','FAIL', COUNT(*), 'Same account/date/type/amount/balance/symbol posted under different trans_id' FROM rej_trans;
SELECT 'TRANSFER_MISSING_COUNTERPARTY','raw','FAIL', COUNT(*), 'Transfer without partner bank or account' FROM raw_trans WHERE operation IN ('PREVOD NA UCET','PREVOD Z UCTU') AND (bank IS NULL OR account IS NULL);
SELECT 'TXN_NULL_OPERATION_UNEXPLAINED','raw','FAIL', COUNT(*), 'Null operation on rows that are not interest postings' FROM raw_trans WHERE operation IS NULL AND COALESCE(TRIM(k_symbol),'') <> 'UROK';
-- ---- business flags ----
SELECT 'NEGATIVE_BALANCE_TXNS','stg','WARN', COUNT(*), 'Transactions leaving the account with a negative reported balance' FROM stg_trans WHERE balance_reported < 0;
SELECT 'BALANCE_RECON_ACCOUNT','stg','FAIL', COUNT(*), 'Accounts where summed signed flows differ from last reported balance by more than 1.0' FROM (
   SELECT t.account_id FROM stg_trans t
   JOIN (SELECT account_id, SUM(signed_amount) AS cum, MAX(txn_date) AS md FROM stg_trans GROUP BY account_id) s
     ON s.account_id = t.account_id AND t.txn_date = s.md
   GROUP BY t.account_id HAVING MIN(ABS(s.cum - t.balance_reported)) > 1.0);
-- ---- referential integrity (anti-joins) ----
SELECT 'FK_DISP_CLIENT','raw','FAIL', COUNT(*), 'disp rows whose client is missing' FROM raw_disp d LEFT JOIN raw_client c ON c.client_id=d.client_id WHERE c.client_id IS NULL;
SELECT 'FK_DISP_ACCOUNT','raw','FAIL', COUNT(*), 'disp rows whose account is missing' FROM raw_disp d LEFT JOIN raw_account a ON a.account_id=d.account_id WHERE a.account_id IS NULL;
SELECT 'FK_LOAN_ACCOUNT','raw','FAIL', COUNT(*), 'loans whose account is missing' FROM raw_loan l LEFT JOIN raw_account a ON a.account_id=l.account_id WHERE a.account_id IS NULL;
SELECT 'FK_TRANS_ACCOUNT','raw','FAIL', COUNT(*), 'transactions whose account is missing' FROM raw_trans t LEFT JOIN raw_account a ON a.account_id=t.account_id WHERE a.account_id IS NULL;
SELECT 'FK_CARD_DISP','raw','FAIL', COUNT(*), 'cards whose disposition is missing' FROM raw_card c LEFT JOIN raw_disp d ON d.disp_id=c.disp_id WHERE d.disp_id IS NULL;
SELECT 'FK_CLIENT_DISTRICT','raw','FAIL', COUNT(*), 'clients whose district is missing' FROM raw_client c LEFT JOIN raw_district d ON d.A1=c.district_id WHERE d.A1 IS NULL;
-- ---- business rules ----
SELECT 'ACCOUNT_WITHOUT_OWNER','raw','FAIL', COUNT(*), 'Accounts with no OWNER disposition' FROM raw_account a WHERE NOT EXISTS (SELECT 1 FROM raw_disp d WHERE d.account_id=a.account_id AND d.type='OWNER');
SELECT 'ACCOUNT_MULTIPLE_OWNERS','raw','FAIL', COUNT(*), 'Accounts with more than one OWNER' FROM (SELECT account_id FROM raw_disp WHERE type='OWNER' GROUP BY account_id HAVING COUNT(*)>1);
SELECT 'LOAN_PAYMENT_ARITHMETIC','raw','FAIL', COUNT(*), 'Loans where payments x duration differs from amount by >1%' FROM raw_loan WHERE ABS(payments*duration - amount) > 0.01*amount;
SELECT 'LOAN_BEFORE_ACCOUNT_OPEN','stg','FAIL', COUNT(*), 'Loans dated before the account was opened' FROM stg_loan l JOIN stg_account a ON a.account_id=l.account_id WHERE l.loan_date < a.open_date;
SELECT 'CARD_BEFORE_ACCOUNT_OPEN','stg','FAIL', COUNT(*), 'Cards issued before the account was opened' FROM stg_card c JOIN stg_disp d ON d.disp_id=c.disp_id JOIN stg_account a ON a.account_id=d.account_id WHERE c.issued_date < a.open_date;
SELECT 'TXN_BEFORE_ACCOUNT_OPEN','stg','FAIL', COUNT(*), 'Transactions dated before the account was opened' FROM stg_trans t JOIN stg_account a ON a.account_id=t.account_id WHERE t.txn_date < a.open_date;
SELECT 'CLIENT_INVALID_BIRTH_DATE','stg','FAIL', COUNT(*), 'Clients whose derived birth date is not a valid date' FROM stg_client WHERE date(birth_date) IS NULL;
-- ---- reconciliation ----
SELECT 'RECON_RAW_VS_STG_TRANS','recon','FAIL', ABS((SELECT COUNT(*) FROM raw_trans) - (SELECT COUNT(*) FROM stg_trans) - (SELECT COUNT(*) FROM rej_trans)), 'raw rows must equal staging + rejected rows' ;
SELECT 'RECON_ACCOUNT_MONTH_SPINE','mart','FAIL', (SELECT COUNT(*) FROM stg_account a WHERE NOT EXISTS (SELECT 1 FROM mart_account_360 m WHERE m.account_id=a.account_id)), 'Every account must appear in the account-360 mart';
