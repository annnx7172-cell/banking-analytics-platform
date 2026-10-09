# Data Quality & Root Cause Analysis Report (Berka PKDD'99 Financial dataset)
Generated 2026-10-09 15:38

**24 checks run: 16 passed, 7 failed, 1 warnings.**

| check_name                       | status   |   failed_rows | description                                                                           |
|:---------------------------------|:---------|--------------:|:--------------------------------------------------------------------------------------|
| DISTRICT_MISSING_VALUE           | FAIL     |             1 | District rows with ? placeholders in unemployment_95 / crimes_95                      |
| TXN_SYMBOL_INCONSISTENT_ENCODING | FAIL     |        53,433 | k_symbol uses a single space for none while other rows use NULL                       |
| TXN_LEGACY_TYPE_CODE             | FAIL     |        16,666 | type=VYBER duplicates the withdrawal code VYDAJ                                       |
| TXN_ZERO_AMOUNT                  | FAIL     |            14 | Transactions with amount = 0                                                          |
| TXN_DUPLICATE_POSTING            | FAIL     |             1 | Same account/date/type/amount/balance/symbol posted under different trans_id          |
| TRANSFER_MISSING_COUNTERPARTY    | FAIL     |             1 | Transfer without partner bank or account                                              |
| NEGATIVE_BALANCE_TXNS            | WARN     |         2,999 | Transactions leaving the account with a negative reported balance                     |
| BALANCE_RECON_ACCOUNT            | FAIL     |            64 | Accounts where summed signed flows differ from last reported balance by more than 1.0 |

Passed checks (all referential-integrity anti-joins, loan arithmetic, date-order rules, birth-date validity, reconciliations): TXN_NULL_OPERATION_UNEXPLAINED, FK_DISP_CLIENT, FK_DISP_ACCOUNT, FK_LOAN_ACCOUNT, FK_TRANS_ACCOUNT, FK_CARD_DISP, FK_CLIENT_DISTRICT, ACCOUNT_WITHOUT_OWNER, ACCOUNT_MULTIPLE_OWNERS, LOAN_PAYMENT_ARITHMETIC, LOAN_BEFORE_ACCOUNT_OPEN, CARD_BEFORE_ACCOUNT_OPEN, TXN_BEFORE_ACCOUNT_OPEN, CLIENT_INVALID_BIRTH_DATE, RECON_RAW_VS_STG_TRANS, RECON_ACCOUNT_MONTH_SPINE


## DISTRICT_MISSING_VALUE

**Evidence**

|   district_id | district_name   | region        |   unemployment_95_missing |   crimes_95_missing |   accounts |   loans |
|--------------:|:----------------|:--------------|--------------------------:|--------------------:|-----------:|--------:|
|            69 | Jesenik         | north Moravia |                         1 |                   1 |         48 |       8 |

**Likely root cause:** The source stores a literal '?' for the 1995 unemployment and crime figures of one district, so those figures were simply not supplied for it. Only the two 1995 columns are affected.

**Fix / treatment:** Staging converts '?' to NULL (no imputation). Dashboards show the district with 'n/a' for 1995 metrics and use the 1996 columns for analysis.

## TXN_SYMBOL_INCONSISTENT_ENCODING

**Evidence**

| operation      |   encoded_as_null |   encoded_as_space |
|:---------------|------------------:|-------------------:|
| PREVOD NA UCET |             8,155 |             52,817 |
| VYBER          |           274,059 |                616 |
| VYBER KARTOU   |             8,036 |                  0 |
| VKLAD          |           156,743 |                  0 |
| PREVOD Z UCTU  |            34,888 |                  0 |
| (null)         |                 0 |                  0 |

**Likely root cause:** 'No purpose' is encoded two ways: NULL on some rows and a single space on others. The space encoding is almost entirely on outgoing transfers (PREVOD NA UCET), while other operations use NULL, which suggests the two encodings come from different extract jobs or source systems.

**Fix / treatment:** Staging maps both to 'NONE' so grouping and filters in Tableau / Power BI do not split one category in two. Raise with the source owner to standardise.

## TXN_LEGACY_TYPE_CODE

**Evidence**

|   year |   legacy_type_VYBER |   standard_VYDAJ_cash_withdrawals |
|-------:|--------------------:|----------------------------------:|
|   1993 |                 371 |                             9,391 |
|   1994 |               1,485 |                            37,355 |
|   1995 |               2,045 |                            54,262 |
|   1996 |               2,856 |                            78,763 |
|   1997 |               4,494 |                           113,801 |
|   1998 |               5,415 |                           124,680 |

**Likely root cause:** Rows with type VYBER are always cash withdrawals (operation VYBER) and always debits, so VYBER is a second code for what is normally VYDAJ. Both codes appear in every year, which suggests two feeds rather than a one-off migration.

**Fix / treatment:** Staging maps VYBER to VYDAJ so debit/credit totals are right. A filter on type = 'VYDAJ' alone would have understated withdrawals.

## TXN_ZERO_AMOUNT

**Evidence**

| k_symbol    | type   |   rows_ |
|:------------|:-------|--------:|
| SANKC. UROK | VYDAJ  |      10 |
| UROK        | PRIJEM |       4 |

**Likely root cause:** All zero-value rows are interest postings (UROK) or penalty-interest postings (SANKC. UROK): interest calculated as nil but still posted.

**Fix / treatment:** Kept in staging (no balance impact). Excluded from average-transaction-size metrics.

## TXN_DUPLICATE_POSTING

**Evidence**

|   trans_id |   account_id |    date | type   | k_symbol   |   amount |   balance | reject_reason     |
|-----------:|-------------:|--------:|:-------|:-----------|---------:|----------:|:------------------|
|  3,507,085 |        9,051 | 980,228 | PRIJEM | UROK       |      0.0 |   1,367.1 | DUPLICATE_POSTING |

**Likely root cause:** Two postings share account, date, type, symbol, amount and balance but have different trans_id. Both are zero-value interest rows, so this looks like the same nil-interest posting generated twice.

**Fix / treatment:** Staging keeps the lowest trans_id; the other is quarantined in rej_trans. No balance or total changes.

## TRANSFER_MISSING_COUNTERPARTY

**Evidence**

|   trans_id |   account_id |    date | type   | operation      | k_symbol   |   amount |
|-----------:|-------------:|--------:|:-------|:---------------|:-----------|---------:|
|    236,564 |          808 | 960,412 | VYDAJ  | PREVOD NA UCET | UVER       |  4,500.0 |

**Likely root cause:** A single loan-related transfer (symbol UVER) has no partner bank or account, so the counterparty was not captured at source.

**Fix / treatment:** Left as is (one row of 273,509 transfers). Excluded from any counterparty-level analysis.

## NEGATIVE_BALANCE_TXNS (business warning)

**Evidence**

|   year |   txns_with_negative_balance |   accounts |
|-------:|-----------------------------:|-----------:|
|   1993 |                           15 |          6 |
|   1994 |                          172 |         46 |
|   1995 |                          216 |         54 |
|   1996 |                          289 |         66 |
|   1997 |                          773 |         99 |
|   1998 |                        1,534 |        162 |

**Likely root cause:** Not a data error: accounts go overdrawn. It is a risk signal, which is why it is a WARN. See INSIGHTS.md for how overdrawn accounts relate to loan defaults.

**Fix / treatment:** Exposed as an 'overdrawn' flag and in the loan watchlist (balance_cover) so a risk manager can act on it.

## BALANCE_RECON_ACCOUNT

**Evidence**

|   accounts_failing |   median_abs_diff |   max_abs_diff |   median_txn_count |   median_txn_count_all_accounts |
|-------------------:|------------------:|---------------:|-------------------:|--------------------------------:|
|               64.0 |               1.4 |            2.7 |              409.0 |                           234.7 |

**Likely root cause:** The vast majority of accounts reconcile within rounding (source amounts are to 0.1). The failing accounts have more transactions than average (median 409 vs about 235) and the largest gap is only 2.7, which is consistent with small per-row rounding differences accumulating past the 1.0 tolerance. Missing postings cannot be ruled out.

**Fix / treatment:** The dashboard balance is rebuilt from signed flows (mart_account_month.est_balance), not copied from the source. The 1.0 tolerance is documented, and the check query lists the affected accounts for review.