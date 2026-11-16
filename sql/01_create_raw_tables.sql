-- Berka bank dataset: staging layer.
-- Every column is TEXT so the CSV import cannot fail on odd dates or blanks.
-- Import each CSV with pgAdmin: Import/Export Data -> Header: Yes, Delimiter: ;, Quote: ", Escape: "

CREATE SCHEMA raw;

CREATE TABLE raw.account (
  account_id TEXT, district_id TEXT, frequency TEXT, date TEXT
);

CREATE TABLE raw.client (
  client_id TEXT, birth_number TEXT, district_id TEXT
);

CREATE TABLE raw.disp (
  disp_id TEXT, client_id TEXT, account_id TEXT, type TEXT
);

CREATE TABLE raw.orders (   -- file order.csv ("order" is a reserved word)
  order_id TEXT, account_id TEXT, bank_to TEXT,
  account_to TEXT, amount TEXT, k_symbol TEXT
);

CREATE TABLE raw.trans (
  trans_id TEXT, account_id TEXT, date TEXT, type TEXT, operation TEXT,
  amount TEXT, balance TEXT, k_symbol TEXT, bank TEXT, account TEXT
);

CREATE TABLE raw.loan (
  loan_id TEXT, account_id TEXT, date TEXT, amount TEXT,
  duration TEXT, payments TEXT, status TEXT
);

CREATE TABLE raw.card (
  card_id TEXT, disp_id TEXT, type TEXT, issued TEXT
);

-- Original columns A1..A16 renamed to meaningful names
CREATE TABLE raw.district (
  district_id TEXT,               -- A1
  district_name TEXT,             -- A2
  region TEXT,                    -- A3
  population TEXT,                -- A4
  municipalities_lt_500 TEXT,     -- A5
  municipalities_500_1999 TEXT,   -- A6
  municipalities_2000_9999 TEXT,  -- A7
  municipalities_gt_10000 TEXT,   -- A8
  num_cities TEXT,                -- A9
  urban_ratio TEXT,               -- A10
  avg_salary TEXT,                -- A11
  unemployment_95 TEXT,           -- A12
  unemployment_96 TEXT,           -- A13
  entrepreneurs_per_1000 TEXT,    -- A14
  crimes_95 TEXT,                 -- A15
  crimes_96 TEXT                  -- A16
);

-- Row-count check after import
-- account 4,500 | client 5,369 | disp 5,369 | district 77 | loan 682
-- card 892 | orders 6,471 | trans 1,056,320
SELECT 'account' t, COUNT(*) FROM raw.account
UNION ALL SELECT 'client', COUNT(*) FROM raw.client
UNION ALL SELECT 'disp', COUNT(*) FROM raw.disp
UNION ALL SELECT 'district', COUNT(*) FROM raw.district
UNION ALL SELECT 'loan', COUNT(*) FROM raw.loan
UNION ALL SELECT 'card', COUNT(*) FROM raw.card
UNION ALL SELECT 'orders', COUNT(*) FROM raw.orders
UNION ALL SELECT 'trans', COUNT(*) FROM raw.trans;
