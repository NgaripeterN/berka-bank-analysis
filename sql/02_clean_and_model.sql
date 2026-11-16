-- Cleaning and modelling layer: typed columns, real dates, English labels,
-- decoded client attributes, primary keys and foreign keys.
-- Run the blocks in order. raw.* stays untouched so this script can be re-run.

CREATE SCHEMA clean;

-- 1. District 
CREATE TABLE clean.district (
  district_id INT PRIMARY KEY,
  district_name TEXT,
  region TEXT,
  population INT,
  municipalities_lt_500 INT,
  municipalities_500_1999 INT,
  municipalities_2000_9999 INT,
  municipalities_gt_10000 INT,
  num_cities INT,
  urban_ratio NUMERIC(5,2),
  avg_salary INT,
  unemployment_95 NUMERIC(5,2),
  unemployment_96 NUMERIC(5,2),
  entrepreneurs_per_1000 INT,
  crimes_95 INT,
  crimes_96 INT
);

INSERT INTO clean.district
SELECT district_id::INT, district_name, region, population::INT,
  municipalities_lt_500::INT, municipalities_500_1999::INT,
  municipalities_2000_9999::INT, municipalities_gt_10000::INT,
  num_cities::INT, urban_ratio::NUMERIC, avg_salary::INT,
  NULLIF(unemployment_95,'?')::NUMERIC, unemployment_96::NUMERIC,
  entrepreneurs_per_1000::INT,
  NULLIF(crimes_95,'?')::INT, crimes_96::INT
FROM raw.district;

-- 2. Account and client 
CREATE TABLE clean.account (
  account_id INT PRIMARY KEY,
  district_id INT REFERENCES clean.district(district_id),
  statement_frequency TEXT,
  created_date DATE
);

INSERT INTO clean.account
SELECT account_id::INT, district_id::INT,
  CASE frequency
    WHEN 'POPLATEK MESICNE' THEN 'Monthly'
    WHEN 'POPLATEK TYDNE' THEN 'Weekly'
    WHEN 'POPLATEK PO OBRATU' THEN 'After transaction'
  END,
  to_date('19' || date, 'YYYYMMDD')
FROM raw.account;

-- birth_number = YYMMDD; women have 50 added to the month
CREATE TABLE clean.client (
  client_id INT PRIMARY KEY,
  gender CHAR(1),
  birth_date DATE,
  district_id INT REFERENCES clean.district(district_id)
);

INSERT INTO clean.client
SELECT client_id::INT,
  CASE WHEN mm > 12 THEN 'F' ELSE 'M' END,
  to_date('19' || yy || LPAD((CASE WHEN mm > 12 THEN mm - 50 ELSE mm END)::TEXT, 2, '0') || dd, 'YYYYMMDD'),
  district_id::INT
FROM (
  SELECT client_id, district_id,
    SUBSTRING(birth_number,1,2) AS yy,
    SUBSTRING(birth_number,3,2)::INT AS mm,
    SUBSTRING(birth_number,5,2) AS dd
  FROM raw.client
) c;

-- 3. Dispositions, loans, cards, standing orders 
CREATE TABLE clean.disp (
  disp_id INT PRIMARY KEY,
  client_id INT REFERENCES clean.client(client_id),
  account_id INT REFERENCES clean.account(account_id),
  disp_type TEXT
);
INSERT INTO clean.disp
SELECT disp_id::INT, client_id::INT, account_id::INT, INITCAP(type)
FROM raw.disp;

CREATE TABLE clean.loan (
  loan_id INT PRIMARY KEY,
  account_id INT REFERENCES clean.account(account_id),
  loan_date DATE,
  amount NUMERIC(12,2),
  duration_months INT,
  monthly_payment NUMERIC(12,2),
  status_code CHAR(1),
  status TEXT,
  is_bad_loan BOOLEAN
);
INSERT INTO clean.loan
SELECT loan_id::INT, account_id::INT,
  to_date('19' || date, 'YYYYMMDD'),
  amount::NUMERIC, duration::INT, payments::NUMERIC, status,
  CASE status
    WHEN 'A' THEN 'Finished, paid'
    WHEN 'B' THEN 'Finished, not paid'
    WHEN 'C' THEN 'Running, OK'
    WHEN 'D' THEN 'Running, in debt'
  END,
  status IN ('B','D')            -- problem loans = B (lost) + D (in arrears)
FROM raw.loan;

CREATE TABLE clean.card (
  card_id INT PRIMARY KEY,
  disp_id INT REFERENCES clean.disp(disp_id),
  card_type TEXT,
  issued_date DATE
);
INSERT INTO clean.card
SELECT card_id::INT, disp_id::INT, INITCAP(type),
  to_date('19' || LEFT(issued, 6), 'YYYYMMDD')
FROM raw.card;

CREATE TABLE clean.orders (
  order_id INT PRIMARY KEY,
  account_id INT REFERENCES clean.account(account_id),
  bank_to TEXT,
  account_to TEXT,
  amount NUMERIC(12,2),
  purpose TEXT
);
INSERT INTO clean.orders
SELECT order_id::INT, account_id::INT, bank_to, account_to, amount::NUMERIC,
  CASE NULLIF(TRIM(k_symbol),'')
    WHEN 'POJISTNE' THEN 'Insurance'
    WHEN 'SIPO' THEN 'Household'
    WHEN 'LEASING' THEN 'Leasing'
    WHEN 'UVER' THEN 'Loan payment'
  END
FROM raw.orders;

-- 4. Transactions (1,056,320 rows) 
-- Blank k_symbol/bank/account values are stored three ways in the raw data
-- (NULL, empty string, single space); NULLIF(TRIM(...), '') makes them all NULL.
CREATE TABLE clean.trans (
  trans_id INT PRIMARY KEY,
  account_id INT REFERENCES clean.account(account_id),
  trans_date DATE,
  trans_type TEXT,
  operation TEXT,
  amount NUMERIC(12,2),
  balance NUMERIC(12,2),
  purpose TEXT,
  partner_bank TEXT,
  partner_account TEXT
);

INSERT INTO clean.trans
SELECT trans_id::INT, account_id::INT,
  to_date('19' || date, 'YYYYMMDD'),
  CASE type WHEN 'PRIJEM' THEN 'Credit' ELSE 'Withdrawal' END,
  CASE NULLIF(TRIM(operation),'')
    WHEN 'VKLAD' THEN 'Cash deposit'
    WHEN 'PREVOD Z UCTU' THEN 'Incoming transfer'
    WHEN 'VYBER' THEN 'Cash withdrawal'
    WHEN 'VYBER KARTOU' THEN 'Card withdrawal'
    WHEN 'PREVOD NA UCET' THEN 'Outgoing transfer'
  END,
  amount::NUMERIC, balance::NUMERIC,
  CASE NULLIF(TRIM(k_symbol),'')
    WHEN 'POJISTNE' THEN 'Insurance'
    WHEN 'SLUZBY' THEN 'Statement fee'
    WHEN 'UROK' THEN 'Interest credited'
    WHEN 'SANKC. UROK' THEN 'Penalty interest'
    WHEN 'SIPO' THEN 'Household'
    WHEN 'DUCHOD' THEN 'Pension'
    WHEN 'UVER' THEN 'Loan payment'
  END,
  NULLIF(TRIM(bank),''), NULLIF(TRIM(account),'')
FROM raw.trans;

CREATE INDEX idx_trans_account ON clean.trans(account_id);
CREATE INDEX idx_trans_date ON clean.trans(trans_date);

-- 5. Verification: counts must equal the raw layer 
SELECT 'district' t, COUNT(*) FROM clean.district
UNION ALL SELECT 'account', COUNT(*) FROM clean.account
UNION ALL SELECT 'client', COUNT(*) FROM clean.client
UNION ALL SELECT 'disp', COUNT(*) FROM clean.disp
UNION ALL SELECT 'loan', COUNT(*) FROM clean.loan
UNION ALL SELECT 'card', COUNT(*) FROM clean.card
UNION ALL SELECT 'orders', COUNT(*) FROM clean.orders
UNION ALL SELECT 'trans', COUNT(*) FROM clean.trans;
