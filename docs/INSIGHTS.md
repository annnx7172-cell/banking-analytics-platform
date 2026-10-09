# Key findings (all computed from the data by src/insights.py)

1. **Loan book:** 682 loans worth 103,261,740. 11.1% of loans by count and 15.1% by amount are bad (status B finished unpaid, or D running in debt). Bad loans are bigger than average.
2. **Regions:** bad-loan rate ranges from 1.6% to 15.8% (north Bohemia has only 61 loans, so treat its low rate with caution).

| region          |   loans |   bad_loans |   bad_loan_pct |
|:----------------|--------:|------------:|---------------:|
| west Bohemia    |      57 |           9 |           15.8 |
| north Moravia   |     117 |          18 |           15.4 |
| south Bohemia   |      60 |           9 |           15   |
| central Bohemia |      90 |          10 |           11.1 |
| east Bohemia    |      84 |           9 |           10.7 |
| south Moravia   |     129 |          13 |           10.1 |
| Prague          |      84 |           7 |            8.3 |
| north Bohemia   |      61 |           1 |            1.6 |

3. **Duration:** 12-month loans have the lowest bad rate; 24 to 60 months are all similar.

|   duration_months |   loans |   bad_loan_pct |
|------------------:|--------:|---------------:|
|                12 |     131 |            8.4 |
|                24 |     138 |           12.3 |
|                36 |     130 |           11.5 |
|                48 |     138 |           11.6 |
|                60 |     145 |           11.7 |

4. **Overdrawn accounts and bad loans:** every loan whose account was overdrawn at some point in 1998 is bad, versus a much lower rate otherwise. **Caveat:** loan status is a final snapshot, so overdraft may be a result of the default rather than an early warning. Timing cannot be tested with this dataset; the watchlist treats it as a flag to review, not a predictor.

|   overdrawn_1998 |   loans |   bad_loans |   bad_loan_pct |
|-----------------:|--------:|------------:|---------------:|
|                0 |     653 |          47 |            7.2 |
|                1 |      29 |          29 |          100   |

5. **Tiers (by 1998 average balance):** bad-loan rate falls from Basic to Premium. Part of this is mechanical, because accounts in trouble have lower balances.

| tier     |   accounts |   avg_balance |   card_penetration_pct |   loans |   bad_loan_pct |   accounts_overdrawn_1998 |
|:---------|-----------:|--------------:|-----------------------:|--------:|---------------:|--------------------------:|
| Premium  |      1,125 |         64740 |                   45.7 |     246 |            6.1 |                         2 |
| Standard |      2,250 |         34040 |                   15.8 |     354 |            8.8 |                        23 |
| Basic    |      1,125 |         16360 |                    2   |      82 |           36.6 |                        82 |

6. **Demographics do not explain defaults.** District unemployment, salary and crime show no relationship with the district bad-loan rate, so risk is not simply a poor-area effect (with a small number of loans per district, weak effects could still be hidden).

| district metric   |   districts (>=5 loans) |   Spearman rho vs bad-loan % |   p-value |
|:------------------|------------------------:|-----------------------------:|----------:|
| unemployment_96   |                      65 |                         0.06 |      0.63 |
| avg_salary        |                      65 |                        -0.05 |      0.66 |
| crimes_96         |                      65 |                        -0.05 |      0.68 |
