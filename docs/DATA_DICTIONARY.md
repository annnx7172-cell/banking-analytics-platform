# Data Dictionary (Berka PKDD'99 Financial dataset, anonymised Czech bank, 1993-1998)
Column meanings for district columns follow the dataset's published description (A1 id ... A16 crimes 1996).

## Raw tables (loaded as-is from the .asc files)
| Table | Rows | Grain | Notes |
|---|---|---|---|
| raw_account | 4,500 | account | frequency = statement frequency; date = YYMMDD |
| raw_client | 5,369 | client | birth_number = YYMMDD, month + 50 for women |
| raw_disp | 5,369 | client-account link | type OWNER / DISPONENT; only owners can take loans |
| raw_card | 892 | card | junior / classic / gold |
| raw_loan | 682 | loan (max one per account) | status A finished paid, B finished unpaid, C running OK, D running in debt |
| raw_order | 6,471 | standing order | k_symbol = purpose |
| raw_district | 77 | district | demographics A1-A16 |
| raw_trans | 1,056,320 | transaction | type PRIJEM credit / VYDAJ debit (VYBER = legacy debit code) |

## Staging and mart objects
| Object | Grain | Key columns / logic |
|---|---|---|
| stg_* | cleaned copies | dates to ISO, codes decoded, '?' to NULL, k_symbol none -> 'NONE', VYBER -> VYDAJ, duplicate postings removed |
| rej_trans | rejected row | reject_reason = DUPLICATE_POSTING |
| mart_account_month | account x month (about 4,500 x up to 72) | credits, debits, net_flow, est_balance = running sum of signed flows |
| mart_account_360 | account | owner, gender, age, district, region, card, loan, 1998 balance metrics, tier (NTILE(4) of 1998 average balance: Premium top 25%, Basic bottom 25%) |
| vw_balance_trend_monthly | month x tier x region | accounts, total_balance, credits, debits |
| vw_tier_summary | tier | accounts, avg balance, card penetration, bad-loan %, overdrawn accounts |
| vw_cashflow_monthly | month x type x operation x symbol | txn_count, amount |
| vw_loan_portfolio | region x district x status x duration | loans, loan_amount, bad_amount |
| vw_loan_watchlist | bad loan (B or D) | balance_cover flag (Overdrawn / Low cover / OK) |
| vw_district_scorecard | district | demographics + accounts, loans, bad_loan_pct |
| vw_card_summary | card type x tier | accounts, avg balance |
| vw_standing_orders | purpose | orders, total and average amount |
| dq_log | check run | check_name, severity, failed_rows, status |

## Definitions
- **Bad loan** = status B or D. **Overdrawn** = reconstructed month-end balance below zero in 1998. **Tier** is relative to this bank's accounts, not an absolute wealth measure.
- Berka is a retail bank. There is no Wealth or Wholesale split in the data, so tiers and the loan book are the closest analogues.
