-- SQL SERVER / AZURE SQL (T-SQL). NOT RUN by the author of this kit: test in your own instance (Azure SQL free offer, or SQL Server in Docker) and fix small syntax issues.
-- Demonstrates stored procedures, TRY/CATCH, idempotent MERGE, dedupe with ROW_NUMBER, a view, and DQ logging.
-- Load the 8 .asc files first with BULK INSERT or the Import Flat File wizard into tables raw_account, raw_trans, raw_loan, ... (same column names as the files).
CREATE TABLE dq_log (run_ts DATETIME2 DEFAULT SYSDATETIME(), check_name VARCHAR(60), severity VARCHAR(5), failed_rows INT, status VARCHAR(5));
GO
CREATE OR ALTER PROCEDURE dbo.usp_build_stg_trans
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRAN;
        TRUNCATE TABLE stg_trans;   -- re-runnable: no duplicates if the job is executed twice
        INSERT stg_trans (trans_id, account_id, txn_date, txn_type, operation, amount, signed_amount, balance_reported, k_symbol, bank, account)
        SELECT trans_id, account_id,
               TRY_CONVERT(date, '19' + RIGHT('000000' + CAST([date] AS VARCHAR(6)), 6), 112),
               IIF([type] = 'VYBER', 'VYDAJ', [type]), COALESCE(operation, 'NOT_APPLICABLE'), amount,
               IIF([type] = 'PRIJEM', amount, -amount), balance,
               IIF(k_symbol IS NULL OR LTRIM(RTRIM(k_symbol)) = '', 'NONE', LTRIM(RTRIM(k_symbol))), bank, account
        FROM (SELECT t.*, ROW_NUMBER() OVER (PARTITION BY account_id, [date], [type], operation, amount, balance, k_symbol ORDER BY trans_id) AS rn FROM raw_trans t) x
        WHERE rn = 1;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_run_dq_checks
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @n INT;
    SELECT @n = COUNT(*) FROM raw_trans WHERE [type] = 'VYBER';
    INSERT dq_log (check_name, severity, failed_rows, status) VALUES ('TXN_LEGACY_TYPE_CODE', 'FAIL', @n, IIF(@n = 0, 'PASS', 'FAIL'));
    SELECT @n = COUNT(*) FROM raw_loan l LEFT JOIN raw_account a ON a.account_id = l.account_id WHERE a.account_id IS NULL;   -- anti-join
    INSERT dq_log (check_name, severity, failed_rows, status) VALUES ('FK_LOAN_ACCOUNT', 'FAIL', @n, IIF(@n = 0, 'PASS', 'FAIL'));
    SELECT @n = COUNT(*) FROM stg_trans WHERE balance_reported < 0;
    INSERT dq_log (check_name, severity, failed_rows, status) VALUES ('NEGATIVE_BALANCE_TXNS', 'WARN', @n, IIF(@n = 0, 'PASS', 'WARN'));
END;
GO
CREATE OR ALTER VIEW dbo.vw_loan_portfolio AS
SELECT d.A3 AS region, COUNT(*) AS loans, SUM(l.amount) AS loan_amount,
       SUM(IIF(l.status IN ('B','D'), l.amount, 0)) AS bad_amount,
       CAST(100.0 * SUM(IIF(l.status IN ('B','D'), l.amount, 0)) / SUM(l.amount) AS DECIMAL(5,1)) AS bad_amount_pct
FROM raw_loan l JOIN raw_account a ON a.account_id = l.account_id JOIN raw_district d ON d.A1 = a.district_id
GROUP BY d.A3;
GO
-- Port the other views from sql/02_marts.sql: replace SUBSTR with LEFT, strftime with FORMAT/EOMONTH, and the recursive month spine works as a recursive CTE (add OPTION (MAXRECURSION 0)).
-- Schedule with SQL Server Agent or Azure Data Factory:  EXEC dbo.usp_build_stg_trans; EXEC dbo.usp_run_dq_checks;
