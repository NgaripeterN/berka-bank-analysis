-- Analysis queries, in the order they were run. Findings are in the README.

-- 1. Loan portfolio health 
SELECT status, COUNT(*) AS loans,
       SUM(amount) AS total_amount,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_loans
FROM clean.loan
GROUP BY status
ORDER BY status;

-- 2. Does loan duration affect default? 
SELECT duration_months,
       COUNT(*) AS loans,
       SUM(is_bad_loan::INT) AS bad_loans,
       ROUND(100.0 * AVG(is_bad_loan::INT), 1) AS bad_loan_pct
FROM clean.loan
GROUP BY duration_months
ORDER BY duration_months;

-- 3. Does loan size matter? 
SELECT CASE WHEN amount < 100000 THEN '1. Under 100k'
            WHEN amount < 200000 THEN '2. 100k-200k'
            WHEN amount < 300000 THEN '3. 200k-300k'
            ELSE '4. 300k+' END AS amount_band,
       COUNT(*) AS loans,
       SUM(is_bad_loan::INT) AS bad_loans,
       ROUND(100.0 * AVG(is_bad_loan::INT), 1) AS bad_loan_pct
FROM clean.loan
GROUP BY 1
ORDER BY 1;

-- 4. Regional loan risk (loan -> account -> district) 
SELECT d.region,
       COUNT(*) AS loans,
       ROUND(AVG(l.amount)) AS avg_loan,
       ROUND(100.0 * AVG(l.is_bad_loan::INT), 1) AS bad_loan_pct
FROM clean.loan l
JOIN clean.account a ON a.account_id = l.account_id
JOIN clean.district d ON d.district_id = a.district_id
GROUP BY d.region
ORDER BY bad_loan_pct DESC;

-- 5. Do district conditions explain regional risk? 
SELECT d.region,
       COUNT(*) AS loans,
       ROUND(AVG(d.avg_salary)) AS avg_salary,
       ROUND(AVG(d.unemployment_96), 2) AS unemployment_96,
       ROUND(AVG(d.crimes_96)) AS crimes_96,
       ROUND(100.0 * AVG(l.is_bad_loan::INT), 1) AS bad_loan_pct
FROM clean.loan l
JOIN clean.account a ON a.account_id = l.account_id
JOIN clean.district d ON d.district_id = a.district_id
GROUP BY d.region
ORDER BY bad_loan_pct DESC;

-- 6. Borrower age at loan date (CTE). Filter to account Owners so each loan
--    is counted once; Disponents would duplicate rows. 
WITH loan_clients AS (
  SELECT l.loan_id, l.is_bad_loan, c.gender,
         EXTRACT(YEAR FROM age(l.loan_date, c.birth_date))::INT AS age_at_loan
  FROM clean.loan l
  JOIN clean.disp dp ON dp.account_id = l.account_id AND dp.disp_type = 'Owner'
  JOIN clean.client c ON c.client_id = dp.client_id
)
SELECT CASE WHEN age_at_loan < 30 THEN '1. Under 30'
            WHEN age_at_loan < 40 THEN '2. 30-39'
            WHEN age_at_loan < 50 THEN '3. 40-49'
            WHEN age_at_loan < 60 THEN '4. 50-59'
            ELSE '5. 60+' END AS age_band,
       COUNT(*) AS loans,
       SUM(is_bad_loan::INT) AS bad_loans,
       ROUND(100.0 * AVG(is_bad_loan::INT), 1) AS bad_loan_pct
FROM loan_clients
GROUP BY 1
ORDER BY 1;

-- 7. Gender 
WITH loan_clients AS (
  SELECT l.loan_id, l.is_bad_loan, c.gender
  FROM clean.loan l
  JOIN clean.disp dp ON dp.account_id = l.account_id AND dp.disp_type = 'Owner'
  JOIN clean.client c ON c.client_id = dp.client_id
)
SELECT gender,
       COUNT(*) AS loans,
       SUM(is_bad_loan::INT) AS bad_loans,
       ROUND(100.0 * AVG(is_bad_loan::INT), 1) AS bad_loan_pct
FROM loan_clients
GROUP BY gender
ORDER BY gender;

-- 8. Client base by age (as of 31 Dec 1998, the end of the data) and gender ----
SELECT CASE WHEN age < 25 THEN '1. Under 25'
            WHEN age < 35 THEN '2. 25-34'
            WHEN age < 45 THEN '3. 35-44'
            WHEN age < 55 THEN '4. 45-54'
            WHEN age < 65 THEN '5. 55-64'
            ELSE '6. 65+' END AS age_band,
       gender,
       COUNT(*) AS clients
FROM (
  SELECT gender,
         EXTRACT(YEAR FROM age(DATE '1998-12-31', birth_date))::INT AS age
  FROM clean.client
) c
GROUP BY 1, 2
ORDER BY 1, 2;

-- 9. Credit cards: mix and average holder age 
SELECT cd.card_type,
       COUNT(*) AS cards,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_cards,
       ROUND(AVG(EXTRACT(YEAR FROM age(DATE '1998-12-31', c.birth_date)))) AS avg_age
FROM clean.card cd
JOIN clean.disp dp ON dp.disp_id = cd.disp_id
JOIN clean.client c ON c.client_id = dp.client_id
GROUP BY cd.card_type
ORDER BY cards DESC;

-- 10. Monthly cash flow 
SELECT date_trunc('month', trans_date)::DATE AS month,
       COUNT(*) AS transactions,
       SUM(CASE WHEN trans_type = 'Credit' THEN amount ELSE 0 END) AS inflow,
       SUM(CASE WHEN trans_type = 'Withdrawal' THEN amount ELSE 0 END) AS outflow
FROM clean.trans
GROUP BY 1
ORDER BY 1;
