-- Reporting layer: one tidy view per dashboard page. Power BI connects to these only.
-- Each view has a different grain (loan / client / month x region), so they are
-- kept separate and joined in Power BI through shared dimension tables.

CREATE SCHEMA reporting;

-- Page 1: one row per loan (682 rows, 76 bad loans) 
CREATE VIEW reporting.v_loan_details AS
SELECT l.loan_id,
       l.account_id,
       l.loan_date,
       l.amount,
       CASE WHEN l.amount < 100000 THEN '1. Under 100k'
            WHEN l.amount < 200000 THEN '2. 100k-200k'
            WHEN l.amount < 300000 THEN '3. 200k-300k'
            ELSE '4. 300k+' END AS amount_band,
       l.duration_months,
       l.monthly_payment,
       l.status,
       l.is_bad_loan,
       l.is_bad_loan::INT AS bad_loan_flag,
       d.district_name,
       d.region,
       d.avg_salary,
       d.unemployment_96,
       c.gender,
       EXTRACT(YEAR FROM age(l.loan_date, c.birth_date))::INT AS age_at_loan
FROM clean.loan l
JOIN clean.account a  ON a.account_id = l.account_id
JOIN clean.district d ON d.district_id = a.district_id
JOIN clean.disp dp    ON dp.account_id = l.account_id AND dp.disp_type = 'Owner'
JOIN clean.client c   ON c.client_id = dp.client_id;

-- Page 2: one row per client (5,369 rows, 892 card holders) 
-- LEFT JOIN keeps clients without a card.
CREATE VIEW reporting.v_customer_profile AS
SELECT c.client_id,
       c.gender,
       c.birth_date,
       EXTRACT(YEAR FROM age(DATE '1998-12-31', c.birth_date))::INT AS age_1998,
       CASE WHEN EXTRACT(YEAR FROM age(DATE '1998-12-31', c.birth_date)) < 25 THEN '1. Under 25'
            WHEN EXTRACT(YEAR FROM age(DATE '1998-12-31', c.birth_date)) < 35 THEN '2. 25-34'
            WHEN EXTRACT(YEAR FROM age(DATE '1998-12-31', c.birth_date)) < 45 THEN '3. 35-44'
            WHEN EXTRACT(YEAR FROM age(DATE '1998-12-31', c.birth_date)) < 55 THEN '4. 45-54'
            WHEN EXTRACT(YEAR FROM age(DATE '1998-12-31', c.birth_date)) < 65 THEN '5. 55-64'
            ELSE '6. 65+' END AS age_band,
       d.district_name,
       d.region,
       d.avg_salary,
       dp.disp_type AS client_role,
       COALESCE(cd.card_type, 'No card') AS card_type,
       (cd.card_id IS NOT NULL)::INT AS has_card_flag
FROM clean.client c
JOIN clean.district d ON d.district_id = c.district_id
JOIN clean.disp dp ON dp.client_id = c.client_id
LEFT JOIN clean.card cd ON cd.disp_id = dp.disp_id;

-- Page 3: one row per month and region (576 rows, 1,056,320 transactions) 
-- Summarising in SQL keeps the 1M-row table out of Power BI.
CREATE VIEW reporting.v_monthly_cashflow AS
SELECT date_trunc('month', t.trans_date)::DATE AS month,
       d.region,
       COUNT(*) AS transactions,
       SUM(CASE WHEN t.trans_type = 'Credit' THEN t.amount ELSE 0 END) AS inflow,
       SUM(CASE WHEN t.trans_type = 'Withdrawal' THEN t.amount ELSE 0 END) AS outflow
FROM clean.trans t
JOIN clean.account a ON a.account_id = t.account_id
JOIN clean.district d ON d.district_id = a.district_id
GROUP BY 1, 2;

-- Checks
SELECT COUNT(*), SUM(bad_loan_flag) FROM reporting.v_loan_details;            -- 682, 76
SELECT COUNT(*), SUM(has_card_flag) FROM reporting.v_customer_profile;        -- 5369, 892
SELECT COUNT(*), SUM(transactions) FROM reporting.v_monthly_cashflow;         -- 576, 1056320
