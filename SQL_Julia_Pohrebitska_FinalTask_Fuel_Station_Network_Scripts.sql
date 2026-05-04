-- ===============================
 -- TASK: Create a physical database - Fuel Station Network
-- ===============================
--
-- ===============================
-- Comments:
-- ===============================
-- This physical model follows the logical model structure and keeps it in 3NF.
-- I did not add new business entities or relationships that were not part of the logical design.
--
-- I also tried to keep the script rerunnable:
-- - CREATE TABLE / ALTER TABLE use IF NOT EXISTS where possible
-- - INSERT statements use ON CONFLICT DO NOTHING or WHERE NOT EXISTS
-- This helps avoid duplicate data and allows the script to be executed more than once.
--
-- ===============================
-- Data types
-- ===============================
-- Data types were chosen based on the meaning of each column.
-- For example:
-- - NUMERIC(10,2) is used for prices to avoid rounding issues
-- - DATE is used where only the calendar date matters
-- - TIMESTAMPTZ is used where exact date-time matters (valis_to, valid_from, sale_datetime)
-- - VARCHAR is used for business codes, names, and statuses
--
-- Risk of choosing the wrong data type:
-- wrong data types can lead to loss of precision, incorrect comparisons,
-- invalid calculations or bad filtering.
--
-- ===============================
-- Foreign keys
-- ===============================
-- Foreign keys preserve relationships between parent and child tables.
-- They ensure that a child row can reference only an existing parent row.
--
-- If a foreign key is missing, the database may allow orphan rows.
-- For example, a price could reference a station_fuel that does not exist.
-- In that case, joins become unreliable and the model loses referential integrity.
--
-- ===============================
-- Many-to-many relationships
-- ===============================
-- The table station_fuel resolves the many-to-many relationship 
-- between station and fuel. 
--
-- ===============================
-- DDL order
-- ===============================
-- DDL statements are executed in parent-to-child order.
-- Parent tables must be created first, and child tables after that.
-- This is important because a foreign key cannot reference a table
-- that does not exist yet.
--
-- If the order is wrong, PostgreSQL may raise an error such as:
-- relation does not exist or a foreign key creation error.
--
-- ===============================
-- Insert logic and consistency
-- ===============================
-- While inserting data, I tried to avoid hardcoding technical IDs where possible.
-- Foreign key values are resolved from parent tables.
--
-- This makes the script more stable and portable:
-- even if generated IDs are different in another environment,
-- the inserts still preserve the correct relationships.
--
-- I used nested subqueries instead of CTEs in many INSERT statements
-- because here they are read more sequentially and keep each inserted row compact.


-- ===============================
-- Block 1. Database creation
-- ===============================

CREATE DATABASE fuel_station_net;

-- ===============================
-- Block 2. Schema and base tables
-- tables without foreign keys:
-- - station, 
-- - fuel, 
-- - customer
-- ===============================

CREATE SCHEMA IF NOT EXISTS fuel;

CREATE TABLE IF NOT EXISTS fuel.station (
	station_id BIGINT NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    station_code VARCHAR(50) NOT NULL,
    station_name VARCHAR(100) NOT NULL,
    city VARCHAR(100) NOT NULL,
    address VARCHAR(100) NOT NULL,
    opened_on DATE NOT NULL,
    closed_on DATE,
    CONSTRAINT uq_station_station_code 
    	UNIQUE (station_code),
    CONSTRAINT ck_station_closed_on_after_opened_on
        CHECK (closed_on IS NULL OR closed_on >= opened_on)
);


CREATE TABLE IF NOT EXISTS fuel.fuel (
	fuel_id BIGINT NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fuel_code VARCHAR(50) NOT NULL,
    fuel_name VARCHAR(100) NOT NULL,
    unit_name VARCHAR(50) NOT NULL DEFAULT 'liter',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_fuel_fuel_code 
    	UNIQUE (fuel_code)
);


CREATE TABLE IF NOT EXISTS fuel.customer (
	customer_id BIGINT NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_code VARCHAR(50) NOT NULL,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    phone VARCHAR(50),
    email VARCHAR(100),
    registered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_customer_customer_code 
    	UNIQUE (customer_code),
    CONSTRAINT ck_customer_registered_at_valid
        CHECK (registered_at >= TIMESTAMPTZ '2026-01-01 00:00:00+00')
);


-- ===============================
-- Block 3. Tables with foreign keys:
-- - employee, 
-- - station_fuel
-- ===============================


CREATE TABLE IF NOT EXISTS fuel.employee (
	employee_id BIGINT NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	station_id BIGINT NOT NULL,												-- FK
    employee_code VARCHAR(50) NOT NULL,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    job_title VARCHAR(50) NOT NULL,
    phone VARCHAR(100) NOT NULL,
    hired_on DATE NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_employee_station_station_id 
		FOREIGN KEY (station_id)
		REFERENCES fuel.station (station_id),
    CONSTRAINT uq_employee_employee_code 
    	UNIQUE (employee_code),
    CONSTRAINT ck_employee_employee_hired_on_valid
        CHECK (hired_on >= DATE '2026-01-01')
);


CREATE TABLE IF NOT EXISTS fuel.station_fuel (
	station_fuel_id BIGINT NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	station_id BIGINT NOT NULL,												-- FK
	fuel_id BIGINT NOT NULL,												-- FK
    tank_capacity_liters NUMERIC(10,2) NOT NULL,
    current_quantity_liters NUMERIC(10,2) NOT NULL,
    is_available BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_station_fuel_station_station_id 
		FOREIGN KEY (station_id)
		REFERENCES fuel.station (station_id),
    CONSTRAINT fk_station_fuel_fuel_fuel_id 
		FOREIGN KEY (fuel_id)
		REFERENCES fuel.fuel (fuel_id),
    CONSTRAINT uq_station_fuel_station_id_fuel_id 
    	UNIQUE (station_id, fuel_id),
    CONSTRAINT ck_station_fuel_tank_capacity_positive
        CHECK (tank_capacity_liters > 0),
    CONSTRAINT ck_station_fuel_current_quantity_nonnegative
        CHECK (current_quantity_liters >= 0),
    CONSTRAINT ck_station_fuel_current_quantity_not_exceed_capacity
        CHECK (current_quantity_liters <= tank_capacity_liters)       
);

-- ===============================
-- Block 4. Tables with foreign keys:
-- - price
-- - fuel_sale
-- ===============================

CREATE TABLE IF NOT EXISTS fuel.price (
	price_id BIGINT NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	station_fuel_id BIGINT NOT NULL,									    -- FK
	price_type VARCHAR(50) NOT NULL,												
    price_per_liter NUMERIC(10,2) NOT NULL,
    valid_from TIMESTAMPTZ NOT NULL,
    valid_to TIMESTAMPTZ,
    CONSTRAINT fk_price_station_fuel_station_fuel_id 
		FOREIGN KEY (station_fuel_id)
		REFERENCES fuel.station_fuel (station_fuel_id),
    CONSTRAINT uq_price_station_fuel_id_price_type_valid_from 
    	UNIQUE (station_fuel_id, price_type, valid_from),
    CONSTRAINT ck_price_type_valid
        CHECK (price_type IN ('regular', 'promo', 'partner_discount')),
    CONSTRAINT ck_price_price_per_liter_positive
        CHECK (price_per_liter > 0),
    CONSTRAINT ck_price_valid_to_after_valid_from
        CHECK (valid_to IS NULL OR valid_to >= valid_from)       
);


CREATE TABLE IF NOT EXISTS fuel.fuel_sale (
	fuel_sale_id BIGINT NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	station_fuel_id BIGINT NOT NULL,									    -- FK
	employee_id BIGINT NOT NULL,									        -- FK
	customer_id BIGINT,          									        -- FK
	receipt_number VARCHAR(50) NOT NULL,												
    sale_datetime TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    quantity_liters NUMERIC(10,2) NOT NULL,
    price_per_liter NUMERIC(10,2) NOT NULL,
    payment_method VARCHAR(50) NOT NULL,
    discount_amount NUMERIC(10,2) NOT NULL DEFAULT 0,
    total_amount NUMERIC(12,2) GENERATED ALWAYS AS ((quantity_liters * price_per_liter) - discount_amount) STORED,
    CONSTRAINT fk_fuel_sale_station_station_fuel_id 
		FOREIGN KEY (station_fuel_id)
		REFERENCES fuel.station_fuel (station_fuel_id),
	CONSTRAINT fk_fuel_sale_employee_employee_id 
		FOREIGN KEY (employee_id)
		REFERENCES fuel.employee (employee_id),
	CONSTRAINT fk_fuel_sale_customer_customer_id 
		FOREIGN KEY (customer_id)
		REFERENCES fuel.customer (customer_id),
    CONSTRAINT uq_fuel_sale_receipt_number 
    	UNIQUE (receipt_number),
    CONSTRAINT ck_fuel_sale_quantity_liters_positive
        CHECK (quantity_liters > 0),
    CONSTRAINT ck_fuel_sale_price_per_liter_positive
        CHECK (price_per_liter > 0),
    CONSTRAINT ck_fuel_sale_discount_amount_nonnegative
        CHECK (discount_amount >= 0)
);

-- ===============================
-- Block 4.1. Alter table: set NOT NULL for customer_id in fuel_sale
-- P.S. I understood that it was better to have ids for all customers here, so I added NN constraint
-- ===============================

ALTER TABLE fuel.fuel_sale
ALTER COLUMN customer_id SET NOT NULL;

-- ===============================
-- Block 5. Alter tables: add CHECKs
-- - adding 3 checks in fuel.fuel_sale
-- ===============================

ALTER TABLE fuel.fuel_sale
DROP CONSTRAINT IF EXISTS ck_fuel_sale_discount_amount_not_exceed_total,
DROP CONSTRAINT IF EXISTS ck_fuel_sale_payment_method_valid,
DROP CONSTRAINT IF EXISTS ck_fuel_sale_sale_datetime_valid;

ALTER TABLE fuel.fuel_sale
ADD CONSTRAINT ck_fuel_sale_discount_amount_not_exceed_total
CHECK (discount_amount <= quantity_liters * price_per_liter);

ALTER TABLE fuel.fuel_sale
ADD CONSTRAINT ck_fuel_sale_payment_method_valid
CHECK (payment_method IN ('cash', 'card', 'mobile_app', 'corporate_card', 'fuel_card'));

ALTER TABLE fuel.fuel_sale
ADD CONSTRAINT ck_fuel_sale_sale_datetime_valid
CHECK (sale_datetime >= TIMESTAMPTZ '2026-01-01 00:00:00+00');

-- checking constraints:
SELECT
	table_name,
    constraint_name,
    constraint_type
FROM information_schema.table_constraints
WHERE table_schema = 'fuel'
ORDER BY 
	table_name,
    constraint_name,
    constraint_type;

-- ===============================
-- Check whether tables were created
-- ===============================
	
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'fuel'
ORDER BY table_name;

-- ===============================
-- Block 6. Populate the tables with the sample data generated, 
-- ensuring each table has at least 6+ rows (for a total of 36+ rows in all the tables) for the last 3 months.
-- Create DML scripts for insert your data. 
-- ===============================

-- station
-- fuel
-- customer

-- 1) station
INSERT INTO fuel.station (
    station_code,
    station_name,
    city,
    address,
    opened_on,
    closed_on
)
VALUES
    ('WOG001', 'WOG Obolon',   'Kyiv',     '25 Obolonskyi Ave',         DATE '2026-01-05', NULL),
    ('WOG002', 'WOG Pozniaky', 'Kyiv',     '14 Mykhaila Hryshka St',    DATE '2026-01-09', NULL),
    ('WOG003', 'WOG Teremky',  'Kyiv',     '8 Akademika Hlushkova Ave', DATE '2026-01-14', NULL),
    ('WOG004', 'WOG Brovary',  'Brovary',  '121 Kyivska St',            DATE '2026-01-20', NULL),
    ('WOG005', 'WOG Boryspil', 'Boryspil', '67 Kyivskyi Shliakh St',    DATE '2026-02-02', NULL),
    ('WOG006', 'WOG Irpin',    'Irpin',    '39 Soborna St',             DATE '2026-02-11', NULL)
ON CONFLICT (station_code) DO NOTHING
RETURNING 
	station_code,
    station_name,
    city,
    address,
    opened_on,
    closed_on;


-- 2) fuel
INSERT INTO fuel.fuel (
    fuel_code,
    fuel_name,
    unit_name,         -- default value 'liter', but it is stated to be explicitly seen
    is_active
)
VALUES
    ('A95',    'Gasoline A-95',           'liter', TRUE),
    ('A95P',   'Gasoline A-95 Premium',   'liter', TRUE),
    ('A98',    'Gasoline A-98',           'liter', TRUE),
    ('DIESEL', 'Diesel Fuel',             'liter', TRUE),
    ('DP',     'Diesel Premium',          'liter', TRUE),
    ('LPG',    'Liquefied Petroleum Gas', 'liter', TRUE)
ON CONFLICT (fuel_code) DO NOTHING
RETURNING 
    fuel_code,
    fuel_name,
    unit_name,
    is_active;


-- 3) customer
INSERT INTO fuel.customer (
    customer_code,
    first_name,
    last_name, 
    phone,
    email,
    registered_at,
    is_active
)
VALUES
    ('CUST001', 'Oleksandr', 'Melnyk',     '+380671112233', 'oleksandr.melnyk@gmail.com',  TIMESTAMPTZ '2026-04-01 08:15:00+02', TRUE),
    ('CUST002', 'Iryna',     'Kovalenko',  '+380931234567', 'iryna.kovalenko@gmail.com',   TIMESTAMPTZ '2026-04-01 18:25:00+02', TRUE),
    ('CUST003', 'Dmytro',    'Shevchenko', NULL,            NULL,                          TIMESTAMPTZ '2026-04-01 09:25:00+02', TRUE),
    ('CUST004', 'Oles',      'Honchar',    NULL,            NULL,                          TIMESTAMPTZ '2026-04-02 13:05:00+02', TRUE),
    ('CUST005', NULL,        NULL,         '+380672554422', NULL,                          TIMESTAMPTZ '2026-04-02 13:25:00+02', TRUE),
    ('CUST006', NULL,        NULL,         NULL,            NULL,                          TIMESTAMPTZ '2026-04-02 13:35:00+02', TRUE)
ON CONFLICT (customer_code) DO NOTHING
RETURNING 
    customer_code,
    first_name,
    last_name, 
    phone,
    email,
    registered_at,
    is_active;

-- =================================
-- inserting tables with FK (through SELECT)
-- employee
-- station_fuel
-- price
-- fuel_sale
-- =================================

-- 4) employee
INSERT INTO fuel.employee (
	station_id,
	employee_code,
	first_name,
	last_name,
	job_title,
	phone,
	hired_on,
	is_active
)
SELECT 
	(	SELECT station_id
		FROM fuel.station s
		WHERE s.station_code = v.station_code
	) AS station_id,                                     -- FK
	v.employee_code,
	v.first_name,
	v.last_name,
	v.job_title,
	v.phone,
	v.hired_on,
	v.is_active
FROM (
	VALUES
		('WOG001', 'EMP001', 'Olena',    'Marko',     'station manager', '+380671110001', DATE '2026-01-06', TRUE),
        ('WOG001', 'EMP002', 'Ihor',     'Kotenko',   'cashier',         '+380671110002', DATE '2026-01-07', TRUE),
        ('WOG001', 'EMP003', 'Dmytro',   'Savchuk',   'operator',        '+380671110003', DATE '2026-01-10', TRUE),
        ('WOG002', 'EMP004', 'Anna',     'Bilyk',     'station manager', '+380671110004', DATE '2026-01-06', TRUE),
        ('WOG002', 'EMP005', 'Serhii',   'Tkach',     'cashier',         '+380671110005', DATE '2026-01-07', TRUE),
        ('WOG002', 'EMP006', 'Kateryna', 'Honchar',   'operator',        '+380671110006', DATE '2026-01-10', TRUE)
) AS v (
	station_code,
	employee_code,
	first_name,
	last_name,
	job_title,
	phone,
	hired_on,
	is_active
)
ON CONFLICT (employee_code) DO NOTHING
RETURNING 
	employee_id,
    station_id,
	employee_code,
	first_name,
	last_name,
	job_title,
	phone,
	hired_on,
	is_active;


-- 5) station_fuel
INSERT INTO fuel.station_fuel (
	station_id,
	fuel_id,
	tank_capacity_liters,
	current_quantity_liters,
	is_available
)
SELECT 
	(	SELECT station_id
		FROM fuel.station s
		WHERE s.station_code = v.station_code
	) AS station_id,                                     -- FK
	(	SELECT fuel_id
		FROM fuel.fuel f
		WHERE f.fuel_code = v.fuel_code
	) AS fuel_id,                                        -- FK
	v.tank_capacity_liters,
	v.current_quantity_liters,
	v.is_available
FROM (
	VALUES
		('WOG001', 'A95',     12000.00, 8400.00, TRUE),
        ('WOG001', 'DIESEL',  15000.00, 9700.00, TRUE),
        ('WOG001', 'LPG',     10000.00, 6100.00, TRUE),
        ('WOG002', 'A95',      8000.00, 2500.00, TRUE),
        ('WOG002', 'DIESEL',  11000.00, 7200.00, TRUE),
        ('WOG002', 'LPG',     14000.00, 8800.00, TRUE)
) AS v (
	station_code,
	fuel_code,
	tank_capacity_liters,
	current_quantity_liters,
	is_available
)
ON CONFLICT (station_id, fuel_id) DO NOTHING
RETURNING 
	station_fuel_id,
	station_id,
	fuel_id,
	tank_capacity_liters,
	current_quantity_liters,
	is_available;


-- 6) price
INSERT INTO fuel.price (
	station_fuel_id,
	price_type,
	price_per_liter,
	valid_from,
	valid_to
)
SELECT 
	(	SELECT sf.station_fuel_id
		FROM fuel.station_fuel sf
		WHERE sf.station_id = (
			SELECT s.station_id 
			FROM fuel.station s
			WHERE s.station_code = v.station_code
		)	
		AND sf.fuel_id = (
			SELECT f.fuel_id 
			FROM fuel.fuel f
			WHERE f.fuel_code = v.fuel_code
		) 
	) AS station_fuel_id,                                     -- FK
	v.price_type,
	v.price_per_liter,
	v.valid_from,
	v.valid_to
FROM (
	VALUES
		('WOG001', 'A95',    'regular', 76.99, TIMESTAMPTZ '2026-01-01 00:00:00+02', NULL),
		('WOG001', 'DIESEL', 'regular', 93.99, TIMESTAMPTZ '2026-01-01 00:00:00+02', NULL),
		('WOG001', 'LPG',    'promo',   46.99, TIMESTAMPTZ '2026-04-01 00:00:00+02', TIMESTAMPTZ '2026-04-30 22:59:59+02'),
		('WOG002', 'A95',    'regular', 76.99, TIMESTAMPTZ '2026-01-01 00:00:00+02', NULL),
		('WOG002', 'DIESEL', 'regular', 93.99, TIMESTAMPTZ '2026-01-01 00:00:00+02', NULL),
		('WOG002', 'LPG',    'promo',   46.99, TIMESTAMPTZ '2026-04-01 00:00:00+02', TIMESTAMPTZ '2026-04-30 22:59:59+02')
) AS v (
	station_code,
	fuel_code,
	price_type,
	price_per_liter,
	valid_from,
	valid_to
)
ON CONFLICT (station_fuel_id, price_type, valid_from) DO NOTHING
RETURNING 
	price_id,
	station_fuel_id,
	price_type,
	price_per_liter,
	valid_from,
	valid_to;


-- 7) fuel_sale
INSERT INTO fuel.fuel_sale (
	station_fuel_id,
	employee_id,
	customer_id,
	receipt_number,
	sale_datetime,
	quantity_liters,
	price_per_liter,
	payment_method,
	discount_amount
)
SELECT 
	(	SELECT sf.station_fuel_id
		FROM fuel.station_fuel sf
		WHERE sf.station_id = (
			SELECT s.station_id 
			FROM fuel.station s
			WHERE s.station_code = v.station_code
		)	
		AND sf.fuel_id = (
			SELECT f.fuel_id 
			FROM fuel.fuel f
			WHERE f.fuel_code = v.fuel_code
		) 
	) AS station_fuel_id,                                     -- FK
	(	SELECT e.employee_id
		FROM fuel.employee e
		WHERE e.employee_code = v.employee_code
	) AS employee_id,                                         -- FK	
	(	SELECT c.customer_id
		FROM fuel.customer c
		WHERE c.customer_code = v.customer_code
	) AS customer_id,                                         -- FK	
	v.receipt_number,
	v.sale_datetime,
	v.quantity_liters,
	v.price_per_liter,
	v.payment_method,
	v.discount_amount
FROM (
	VALUES
		('WOG001', 'A95',    'EMP002', 'CUST001', 'RCPT000001', TIMESTAMPTZ '2026-04-01 08:15:00+03', 30.00, 76.99, 'card',          0.00),
		('WOG001', 'DIESEL', 'EMP002', 'CUST002', 'RCPT000002', TIMESTAMPTZ '2026-04-01 18:25:00+03', 45.00, 93.99, 'fuel_card',     0.00),
		('WOG001', 'LPG',    'EMP002', 'CUST003', 'RCPT000003', TIMESTAMPTZ '2026-04-01 09:25:00+03', 20.00, 46.99, 'cash',          0.00),
		('WOG002', 'A95',    'EMP005', 'CUST004', 'RCPT000004', TIMESTAMPTZ '2026-04-02 13:05:00+03', 10.00, 76.99, 'mobile_app',   20.00),
		('WOG002', 'DIESEL', 'EMP005', 'CUST005', 'RCPT000005', TIMESTAMPTZ '2026-04-02 13:25:00+03', 31.00, 93.99, 'card',          0.00),
		('WOG002', 'LPG',    'EMP005', 'CUST006', 'RCPT000006', TIMESTAMPTZ '2026-04-02 13:35:00+03', 32.00, 46.99, 'card',         10.00)
) AS v (
	station_code,
	fuel_code,
	employee_code,
	customer_code,
	receipt_number,
	sale_datetime,
	quantity_liters,
	price_per_liter,
	payment_method,
	discount_amount
)
ON CONFLICT (receipt_number) DO NOTHING
RETURNING 
	fuel_sale_id,
	station_fuel_id,
	employee_id,
	customer_id,
	receipt_number,
	sale_datetime,
	quantity_liters,
	price_per_liter,
	payment_method,
	discount_amount,
	total_amount;

-- ===============================
-- Block 7. Create a function that updates data in one of your tables. 
-- This function should take the following input arguments:
-- - The primary key value of the row you want to update
-- - The name of the column you want to update
-- - The new value you want to set for the specified column
-- This function should be designed to modify the specified row in the table, updating the specified column with the new value.
-- ===============================

CREATE OR REPLACE FUNCTION fuel.update_customer_data (
	p_customer_id   BIGINT,
	p_column_name   VARCHAR,
	p_new_value     TEXT
	)
RETURNS TEXT	
LANGUAGE plpgsql
AS $$
BEGIN
	-- 1) allowing to update ONLY selected columns of the customer,
	-- when the company obtains new customer's data: first_name, last_name, phone, email

	IF p_column_name = 'first_name' THEN
		UPDATE fuel.customer
		SET first_name = p_new_value
		WHERE customer_id = p_customer_id;

	ELSIF p_column_name = 'last_name' THEN
		UPDATE fuel.customer
		SET last_name = p_new_value
		WHERE customer_id = p_customer_id;

	ELSIF p_column_name = 'phone' THEN
		UPDATE fuel.customer
		SET phone = p_new_value
		WHERE customer_id = p_customer_id;

	ELSIF p_column_name = 'email' THEN
		UPDATE fuel.customer
		SET email = p_new_value
		WHERE customer_id = p_customer_id;

	ELSE
		RAISE EXCEPTION 'Column "%" is not allowed for updating', p_column_name;
	END IF;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'Customer with customer_id = % was not found', p_customer_id;
	END IF;


    RETURN format(
		'Customer field "%s" for customer_id = %s was successfully updated to "%s".',      -- %s -->  text, %I --> identifier, %L--> literal/value
		p_column_name,
		p_customer_id,
		p_new_value
	);
END;
$$;


COMMENT ON FUNCTION fuel.update_customer_data(
    BIGINT,
    VARCHAR,
    TEXT
)
IS 'Updates customer data in fuel.customer using customer_id, column name, and a new value. 
Only first_name, last_name, phone, and email are allowed for update. 
The function returns a confirmation message after the field is successfully updated.';


-- checking the function:
SELECT fuel.update_customer_data (1,'phone','+380685555555');
SELECT fuel.update_customer_data (5,'first_name','Yaroslava');
SELECT fuel.update_customer_data (5,'last_name','Gnatiuk');
SELECT fuel.update_customer_data (3,'email','d.shev45@gmail.com');

-- checking the updated data in the customer table:
SELECT *
FROM fuel.customer c 
WHERE customer_id IN (1,5,3);


-- ===============================
-- Block 8. Create a function that adds a new transaction to your transaction table. 
-- You can define the input arguments and output format. 
-- Make sure all transaction attributes can be set with the function (via their natural keys). 
-- The function does not need to return a value but should confirm the successful insertion of the new transaction.
-- ===============================

-- ===============================
-- Block 8.1. Create SEQUENCE for receipt numbers
-- to avoid manual entry of receipt numbers
-- ===============================

CREATE SEQUENCE IF NOT EXISTS fuel.receipt_number_seq
START WITH 7
INCREMENT BY 1;

-- check:
SELECT *
FROM information_schema."sequences" s 
-- =============================


-- creating a function for transactional table --> fuel.fuel_sale
CREATE OR REPLACE FUNCTION fuel.add_transaction (
	p_station_code     VARCHAR(50),
	p_fuel_code        VARCHAR(50),
	p_employee_code    VARCHAR(50),
	p_customer_code    VARCHAR(50),
	p_quantity_liters  NUMERIC(10,2),
	p_payment_method   VARCHAR(50),
	p_price_type       VARCHAR(50) DEFAULT 'regular',
	p_discount_amount  NUMERIC(10,2) DEFAULT 0,
	p_sale_datetime    TIMESTAMPTZ DEFAULT NOW()
	)
RETURNS TABLE (
	fuel_sale_id       BIGINT,
	station_fuel_id    BIGINT,
	employee_id        BIGINT,
	customer_id        BIGINT,
	receipt_number     VARCHAR(50),
	sale_datetime      TIMESTAMPTZ,
	quantity_liters    NUMERIC(10,2),
	price_per_liter    NUMERIC(10,2),
	payment_method     VARCHAR(50),
	discount_amount    NUMERIC(10,2), 
	total_amount       NUMERIC(12,2)
)	
LANGUAGE plpgsql
AS $$
DECLARE
	v_station_fuel_id  BIGINT;
	v_employee_id      BIGINT;
	v_customer_id      BIGINT;
	v_price_per_liter  NUMERIC(10,2);
	v_receipt_number   VARCHAR(50);	
BEGIN
	-- 1) find station_fuel_id by station_code + fuel_code --> 
	-- and inserting into v_station_fuel_id
	SELECT sf.station_fuel_id
	INTO v_station_fuel_id
	FROM fuel.station_fuel sf
	INNER JOIN fuel.station s                   -- the same variant like it was used in INSERT fuel_sale but using joins
		ON s.station_id = sf.station_id
	INNER JOIN fuel.fuel f    
		ON f.fuel_id = sf.fuel_id
	WHERE s.station_code = p_station_code
	AND f.fuel_code = p_fuel_code;

	IF v_station_fuel_id IS NULL THEN
		RAISE EXCEPTION 'Station-fuel combination was not found for station_code = % and fuel_code = %', 
		p_station_code, p_fuel_code;
	END IF;

	 -- 2) find employee_id by employee_code
	SELECT e.employee_id
	INTO v_employee_id
	FROM fuel.employee e
	WHERE e.employee_code = p_employee_code;

	IF v_employee_id IS NULL THEN
		RAISE EXCEPTION 'Employee with employee_code = % was not found', p_employee_code;
	END IF;

	 -- 3) find customer_id by customer_code
	SELECT c.customer_id
	INTO v_customer_id
	FROM fuel.customer c
	WHERE c.customer_code = p_customer_code;

	IF v_customer_id IS NULL THEN
		RAISE EXCEPTION 'Customer with customer_code = % was not found', p_customer_code;
	END IF;

    -- 4) find actual price valid at the moment of sale --> fuel.price
	SELECT p.price_per_liter
	INTO v_price_per_liter
	FROM fuel.price p 
	WHERE p.station_fuel_id = v_station_fuel_id
		AND p.price_type = p_price_type
		AND p.valid_from <= p_sale_datetime
		AND (p.valid_to IS NULL OR p.valid_to >= p_sale_datetime)
	ORDER BY p.valid_from DESC                   -- in case of pricing periods for some reasons are overlapping
	LIMIT 1;

	IF v_price_per_liter IS NULL THEN
		RAISE EXCEPTION 'No valid % price was found for station_code = % and fuel_code = % at %', 
		p_price_type, p_station_code, p_fuel_code, p_sale_datetime;
	END IF;

    -- 5) generate receipt number automatically --> number like RCPT000001
	v_receipt_number := 'RCPT' || LPAD(NEXTVAL('fuel.receipt_number_seq')::TEXT, 6, '0');

    -- 6) insert transaction and return all inserted row - explicitly
	RETURN QUERY
	INSERT INTO fuel.fuel_sale(
		station_fuel_id,
		employee_id,
		customer_id,
		receipt_number,
		sale_datetime,
		quantity_liters,
		price_per_liter,
		payment_method,
		discount_amount
	)
	VALUES(
		v_station_fuel_id,
		v_employee_id,
		v_customer_id,
		v_receipt_number,
		p_sale_datetime,
		p_quantity_liters,
		v_price_per_liter,
		p_payment_method,
		p_discount_amount
	)
	RETURNING
        fuel_sale.fuel_sale_id,
        fuel_sale.station_fuel_id,
        fuel_sale.employee_id,
        fuel_sale.customer_id,
        fuel_sale.receipt_number,
        fuel_sale.sale_datetime,
        fuel_sale.quantity_liters,
        fuel_sale.price_per_liter,
        fuel_sale.payment_method,
        fuel_sale.discount_amount,
        fuel_sale.total_amount;
END;
$$;

COMMENT ON FUNCTION fuel.add_transaction(
    VARCHAR(50),
    VARCHAR(50),
    VARCHAR(50),
    VARCHAR(50),
    NUMERIC(10,2),
    VARCHAR(50),
    VARCHAR(50),
    NUMERIC(10,2),
    TIMESTAMPTZ
)
IS 'Adds a new transaction to fuel.fuel_sale using natural keys 
(station_code, fuel_code, employee_code, customer_code). 
The function resolves foreign keys, finds the valid price by price_type and sale_datetime, 
generates a receipt number automatically, inserts the transaction, and returns the inserted row.';


-- checking the function
-- 1) several VALID insertions:
SELECT *
FROM fuel.add_transaction(
    p_station_code   => 'WOG001',
    p_fuel_code      => 'A95',
    p_employee_code  => 'EMP001',
    p_customer_code  => 'CUST003',
    p_quantity_liters=> 20.00,
    p_payment_method => 'cash'
);

SELECT *
FROM fuel.add_transaction(
    p_station_code   => 'WOG001',
    p_fuel_code      => 'A95',
    p_employee_code  => 'EMP002',
    p_customer_code  => 'CUST003',
    p_quantity_liters=> 30.00,
    p_payment_method => 'card'
);

SELECT *
FROM fuel.add_transaction(
    p_station_code   => 'WOG002',
    p_fuel_code      => 'A95',
    p_employee_code  => 'EMP004',
    p_customer_code  => 'CUST005',
    p_quantity_liters=> 22.50,
    p_payment_method => 'mobile_app'
);

SELECT *
FROM fuel.add_transaction(
    p_station_code   => 'WOG002',
    p_fuel_code      => 'LPG',
    p_employee_code  => 'EMP004',
    p_customer_code  => 'CUST001',
    p_quantity_liters=> 40.80,
    p_payment_method => 'card',
    p_price_type     => 'promo',				
	p_discount_amount=> 10.00
);

-- 2) it is NOT VALID insertion because there is no 'promo' price for A95 in fuel.price table
-- an error has occurred: No valid promo price was found for station_code = WOG002 
-- and fuel_code = A95 at 2026-04-05 10:15:00+03

SELECT *
FROM fuel.add_transaction(
    p_station_code   => 'WOG002',
    p_fuel_code      => 'A95',
    p_employee_code  => 'EMP004',
    p_customer_code  => 'CUST005',
    p_quantity_liters=> 42.50,
    p_payment_method => 'mobile_app',
    p_price_type     => 'promo',				-- there is no 'promo' for A95 in fuel.price table
	p_discount_amount=> 200.00,
	p_sale_datetime  => TIMESTAMPTZ '2026-04-05 10:15:00+03'
);

-- 3) it is NOT VALID insertion because there is no 'regular' price for LPG in fuel.price table
--  ('regular' is inserted by default)
-- an error has occurred: No valid regular price was found for station_code = WOG001 
-- and fuel_code = LPG at 2026-04-24 11:31:51.902738+03

SELECT *
FROM fuel.add_transaction(
    p_station_code   => 'WOG001',
    p_fuel_code      => 'LPG',
    p_employee_code  => 'EMP002',
    p_customer_code  => 'CUST004',
    p_quantity_liters=> 10.00,
    p_payment_method => 'cash'
);


-- checking the updated data in the fuel_sale table:
SELECT *
FROM fuel.fuel_sale;


-- ===============================
-- Block 9. Create a view that presents analytics for the most recently added quarter 
-- in your database. Ensure that the result excludes irrelevant fields 
-- such as surrogate keys and duplicate entries.
-- ===============================

-- ==============================
-- Pre-check
	
SELECT
	MIN(fs.sale_datetime) AS min_date,
	MAX(fs.sale_datetime) AS max_date
FROM fuel.fuel_sale fs;

-- ==============================
-- creating view 'revenue_by_station_fuel_qtr'

CREATE OR REPLACE VIEW fuel.revenue_by_station_fuel_qtr AS           -- CREATE OR REPLACE is used to recreate the view safely if it already exists
SELECT
	EXTRACT(YEAR FROM sale.sale_datetime) AS sales_year,
	EXTRACT(QUARTER FROM sale.sale_datetime) AS sales_quarter,
	s.station_name,
	f.fuel_name,
	ROUND(SUM(sale.quantity_liters),0) AS total_liters_sold,
	ROUND(SUM(sale.total_amount),0) AS total_revenue,
	COUNT(sale.receipt_number) AS total_check_number,
	ROUND(SUM(sale.total_amount)/COUNT(sale.receipt_number),0) AS avg_check,
	ROUND(SUM(sale.discount_amount)/COUNT(sale.receipt_number), 0) AS avg_discount_per_check
FROM fuel.fuel_sale sale
INNER JOIN fuel.station_fuel sf
	ON sf.station_fuel_id = sale.station_fuel_id
INNER JOIN fuel.fuel f
	ON f.fuel_id = sf.fuel_id
INNER JOIN fuel.station s
	ON s.station_id = sf.station_id
WHERE DATE_TRUNC('quarter', sale.sale_datetime) = ( 					   
	SELECT DATE_TRUNC('quarter', MAX(fs.sale_datetime))				    -- max quarter = the last quarter in the DB
	FROM fuel.fuel_sale fs
)
GROUP BY 
	EXTRACT(YEAR FROM sale.sale_datetime),
	EXTRACT(QUARTER FROM sale.sale_datetime),
	s.station_name,
	f.fuel_name
ORDER BY
	EXTRACT(YEAR FROM sale.sale_datetime),
	EXTRACT(QUARTER FROM sale.sale_datetime),
	s.station_name,
	total_revenue DESC;

COMMENT ON VIEW fuel.revenue_by_station_fuel_qtr IS
'Shows total liters sold, total revenue, total number of checks, average check and average discount per check
by station and fuel type for the most recently added quarter in the fuel_station_net DB. 
Revenue is calculated as SUM(fuel_sale.total_amount).';

-- check:
SELECT *
FROM fuel.revenue_by_station_fuel_qtr;

-- ===============================
-- Block 10. Create a read-only role for the manager. 
-- This role should have permission to perform SELECT queries on the database tables, and also be able to log in. 
-- Please ensure that you adhere to best practices for database security when defining this role
-- ===============================

-- 1) create role
CREATE ROLE manager_readonly LOGIN PASSWORD 'Re27ad!Ro28le@#';      
-- users are roles with login
-- in a real project the password should be stored securely 
-- and should not be seen in a shared file or public repository

-- 2) grant read-only access to all PRESENT tables and views in schema fuel
GRANT CONNECT ON DATABASE fuel_station_net TO manager_readonly;
GRANT USAGE ON SCHEMA fuel TO manager_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA fuel TO manager_readonly;

-- 3) grant read-only access to all FUTURE tables and views in schema fuel
ALTER DEFAULT PRIVILEGES IN SCHEMA fuel                             
GRANT SELECT ON TABLES TO manager_readonly;

COMMENT ON ROLE manager_readonly IS
'Read-only role for a manager. It can connect to the fuel_station_net DB 
and run SELECT queries on tables and views in the fuel schema.';

-- check 1:
-- manager_readonly has an access to all tables in the schema
SET ROLE manager_readonly;

SELECT *
FROM fuel.customer;
SELECT *
FROM fuel.fuel_sale;

SELECT current_role;

-- check 2:
-- manager_readonly has NO access to UPDATE tables in the schema
SET ROLE manager_readonly;

UPDATE fuel.fuel
SET fuel_code = 'A100'
WHERE fuel_id = 1;

SELECT current_role;

-- check 3:
-- manager_readonly has NO access to FUNCTIONS/SEQUENCES in the schema
SET ROLE manager_readonly;
SELECT fuel.update_customer_data (1,'phone','+380685555555');

SELECT *
FROM fuel.receipt_number_seq;

-- checking the role and its privileges
SELECT grantee, table_schema, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE grantee IN ('manager_readonly')
ORDER BY grantee, table_name, privilege_type;

SELECT *
FROM pg_catalog.pg_roles pr 
WHERE pr.rolname = 'manager_readonly';
