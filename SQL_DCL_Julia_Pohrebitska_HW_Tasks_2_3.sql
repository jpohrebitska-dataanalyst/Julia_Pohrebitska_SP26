--================================
-- Task 2. Implement role-based authentication model for dvd_rental database
--================================

-- 1. Create a new user with the username "rentaluser" and the password "rentalpassword". 
-- Give the user the ability to connect to the database but no other permissions.

-- 2. Grant "rentaluser" permission allows reading data from the "customer" table. 
-- Сheck to make sure this permission works correctly: write a SQL query to select all customers.

-- 3. Create a new user group called "rental" and add "rentaluser" to the group. 

-- 4. Grant the "rental" group INSERT and UPDATE permissions for the "rental" table. 
-- Insert a new row and update one existing row in the "rental" table under that role. 

-- 5. Revoke the "rental" group's INSERT permission for the "rental" table. 
-- Try to insert new rows into the "rental" table make sure this action is denied.

-- 6. Create a personalized role for any customer already existing in the dvd_rental database. 
-- The name of the role name must be client_{first_name}_{last_name} (omit curly brackets). 
-- The customer's payment and rental history must not be empty. 
--
-- For each permission change:
-- Demonstrate both successful and denied access 
-- Provide SQL query showing the error message when access is restricted


-- =============================================
-- 1. Create a new user with the username "rentaluser" and the password "rentalpassword". 
-- Give the user the ability to connect to the database but no other permissions.

DO $$
	BEGIN
		IF NOT EXISTS (
			SELECT 1
			FROM pg_catalog.pg_roles
			WHERE rolname = 'rentaluser'
		) THEN
			CREATE ROLE rentaluser LOGIN PASSWORD 'rentalpassword';
		END IF;
END
$$;

-- CREATE ROLE rentaluser LOGIN PASSWORD 'rentalpassword';      -- users are roles with login
GRANT CONNECT ON DATABASE dvdrental TO rentaluser;

-- =============================================
-- 2. Grant "rentaluser" permission allows reading data from the "customer" table. 
-- Сheck to make sure this permission works correctly: write a SQL query to select all customers.

-- checking before granting access to read
-- the result: denied access 
SET ROLE rentaluser;

SELECT 
	customer_id,
	first_name,
	last_name
FROM public.customer;

-- granting access to read
-- the result: successful access 
SET ROLE postgres;

GRANT SELECT ON public.customer TO rentaluser;

SET ROLE rentaluser;

SELECT 
	customer_id,
	first_name,
	last_name
FROM public.customer;

-- =============================================
-- 3. Create a new user group called "rental" and add "rentaluser" to the group. 

DO $$
BEGIN
	IF NOT EXISTS (
		SELECT 1
		FROM pg_catalog.pg_roles
		WHERE rolname = 'rental'
	) THEN
		CREATE ROLE rental;
	END IF;
END;
$$

-- CREATE ROLE rental;
GRANT rental TO rentaluser;

-- =============================================
-- 4. Grant the "rental" group INSERT and UPDATE permissions for the "rental" table. 
-- Insert a new row and update one existing row in the "rental" table under that role. 

SET ROLE postgres;

GRANT INSERT, UPDATE ON public.rental TO rental;
GRANT SELECT ON public.inventory TO rental;               -- it seems that we also need SELECT privileges on other tables 
GRANT SELECT ON public.customer TO rental;                -- to fetch values like inventory_id, customer_id, and staff_id
GRANT SELECT ON public.staff TO rental;					  -- and avoid hardcoding;
GRANT SELECT ON public.rental TO rental;

SET ROLE rentaluser;

-- Inserting a new row
INSERT INTO public.rental (
	rental_date,
	inventory_id,
	customer_id,
	return_date,
	staff_id,
	last_update)
SELECT
	NOW(),
	(SELECT MAX(i.inventory_id) FROM public.inventory i) AS inventory_id,
	(
		SELECT c.customer_id
		FROM public.customer c
		WHERE c.first_name = 'JULIA'
			AND c.last_name = 'POHREBITSKA'
			AND c.email = 'j.pohrebitska@ukr.net') AS customer_id,
	NULL AS return_date,
    (SELECT MAX(s.staff_id) FROM public.staff s) AS staff_id,
	CURRENT_TIMESTAMP AS last_update
WHERE NOT EXISTS (
    SELECT 1
    FROM public.rental r
    WHERE r.inventory_id = (SELECT MAX(i.inventory_id) FROM public.inventory i)
      AND r.customer_id = (
            SELECT c.customer_id
            FROM public.customer c
            WHERE c.first_name = 'JULIA'
              AND c.last_name = 'POHREBITSKA'
              AND c.email = 'j.pohrebitska@ukr.net'
      )
      AND r.return_date IS NULL
)	
RETURNING
	rental_id,
	rental_date,
	inventory_id,
	customer_id,
	return_date,
	staff_id,
	last_update;
	
-- checking who is the current_user now
SELECT current_user;

-- checking that the record has been writen
SELECT *
FROM rental r 
WHERE r.customer_id = 148;

-- updating one existing row 
SET ROLE postgres;

UPDATE public.rental
SET 
	return_date	= NOW(),
	last_update = CURRENT_TIMESTAMP
WHERE rental_id = (
	SELECT MAX(r.rental_id)
	FROM public.rental r
	WHERE r.customer_id = (
		SELECT c.customer_id 
		FROM public.customer c
        WHERE c.first_name = 'JULIA'
        	AND c.last_name = 'POHREBITSKA'
        	AND c.email = 'j.pohrebitska@ukr.net'
	)
	AND return_date IS NULL 
)
RETURNING
	rental_id,
	rental_date,
	inventory_id,
	customer_id,
	return_date,
	staff_id,
	last_update;	
	
-- checking that the record has been updated
SELECT *
FROM rental r 
WHERE r.customer_id = 148;
	
-- checking existing roles and their privileges
SELECT grantee, table_schema, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE grantee IN ('rental', 'rentaluser')
ORDER BY grantee, table_name, privilege_type;

-- users & roles
SELECT pg_get_userbyid(member) AS user_name,
       pg_get_userbyid(roleid) AS role_name
FROM pg_auth_members
WHERE pg_get_userbyid(member) = 'rentaluser';

-- users & roles as id
SELECT *
FROM pg_auth_members;

-- ===========================================
-- 5. Revoke the "rental" group's INSERT permission for the "rental" table. 
-- Try to insert new rows into the "rental" table make sure this action is denied.

SET ROLE postgres;

REVOKE INSERT ON public.rental FROM rental;

SET ROLE rentaluser;

-- Inserting a new row after REVOKE
-- SQL Error: access is denied for rental table
INSERT INTO public.rental (
	rental_date,
	inventory_id,
	customer_id,
	return_date,
	staff_id,
	last_update)
SELECT
	NOW(),
	(SELECT MIN(i.inventory_id) FROM public.inventory i) AS inventory_id,         -- this time MIN(id) was used
	(
		SELECT c.customer_id
		FROM public.customer c
		WHERE c.first_name = 'JULIA'
			AND c.last_name = 'POHREBITSKA'
			AND c.email = 'j.pohrebitska@ukr.net') AS customer_id,
	NULL AS return_date,
    (SELECT MIN(s.staff_id) FROM public.staff s) AS staff_id,
	CURRENT_TIMESTAMP AS last_update
WHERE NOT EXISTS (
    SELECT 1
    FROM public.rental r
    WHERE r.inventory_id = (SELECT MIN(i.inventory_id) FROM public.inventory i)
      AND r.customer_id = (
            SELECT c.customer_id
            FROM public.customer c
            WHERE c.first_name = 'JULIA'
              AND c.last_name = 'POHREBITSKA'
              AND c.email = 'j.pohrebitska@ukr.net'
      )
      AND r.return_date IS NULL
)	
RETURNING
	rental_id,
	rental_date,
	inventory_id,
	customer_id,
	return_date,
	staff_id,
	last_update;


-- =============================================
-- 6. Create a personalized role for any customer already existing in the dvd_rental database. 
-- The name of the role name must be client_{first_name}_{last_name} (omit curly brackets). 
-- The customer's payment and rental history must not be empty. 

SET ROLE postgres;

-- selecting the customer:
SELECT 	
	c.customer_id,
	c.first_name,
	c.last_name,
	COUNT(DISTINCT r.rental_id) AS rentals_cnt,
	COUNT(DISTINCT p.payment_id) AS payments_cnt
FROM public.customer c 
INNER JOIN public.rental r 
	ON r.customer_id = c.customer_id 
INNER JOIN public.payment p
	ON p.customer_id = c.customer_id 
GROUP BY 
	c.customer_id
HAVING
	COUNT(DISTINCT r.rental_id) > 80
	AND COUNT(DISTINCT p.payment_id) > 80
ORDER BY 
	rentals_cnt DESC,
	payments_cnt DESC;
	

-- a personalized role is created for an existing customer (customer_id = 526)
CREATE ROLE client_karl_seal;

-- checking the role for client
-- it has its own id, rolinherit, but no other rights yet

SELECT *
FROM pg_catalog.pg_roles pr 
WHERE pr.rolname = 'client_karl_seal';



-- =================================================
-- Task 3. Implement row-level security
-- =================================================
-- Configure that role so that the customer can only access their own data in the "rental" and "payment" tables. 
-- Write a query to make sure this user sees only their own data and one to show zero rows or error
-- As a result you have to demonstrate:
--   access to allowed records 
--   denied access to other users’ records 

SET ROLE postgres;

-- 1) granting read access to these 2 tables
GRANT SELECT ON public.rental TO client_karl_seal;
GRANT SELECT ON public.payment TO client_karl_seal;

-- 2) enabling RLS
ALTER TABLE public.rental ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment ENABLE ROW LEVEL SECURITY;

-- 3) creating policies
-- Karl Seal can only see rows with his customer_id (customer_id = 526)
CREATE POLICY rental_client_karl_seal_policy 
ON public.rental
FOR SELECT
TO client_karl_seal
USING (customer_id = 526);

CREATE POLICY payment_client_karl_seal_policy 
ON public.payment
FOR SELECT 
TO client_karl_seal
USING (customer_id = 526);

-- checking whether RLS is working
SET ROLE client_karl_seal;

-- result: role client_karl_seal sees his rentals & payments only
-- and doesn't see others.
SELECT *
FROM public.rental
WHERE customer_id = 526;

SELECT *
FROM public.rental
WHERE customer_id <> 526;

-- we may also check RLS through the table -->  pg_catalog.pg_policies.
-- or directly in the table information --> Policies
SELECT *
FROM pg_catalog.pg_policies;
