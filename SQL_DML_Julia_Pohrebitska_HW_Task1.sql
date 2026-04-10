-- =====================================
-- Task: applying the TCL & DML Statement
-- =====================================

--1.1. film
--1.2. film_category
--1.3. actor
--1.4. film_actor
--1.5. inventory
--1.6. customer update
--1.7. cleanup old related records
--1.8. rental
--1.9. payment

-- =====================================
-- Task 1.1. Insert FILMS
-- =====================================

-- Choose your real top-3 favorite movies 
-- (released in different years, belong to different genres) and add them to the 'film' table
-- Fill in rental rates with 4.99, 9.99 and 19.99 and rental durations with 1, 2 and 3 weeks respectively.

-- Explanations:
-- If any statement fails, the whole transaction can be rolled back
-- Before COMMIT, rollback is possible and only this transaction's changes are affected
-- Referential integrity is preserved by taking language_id from public.language
-- The script is rerunnable because NOT EXISTS prevents duplicate inserts
-- Data uniqueness is checked by the combination of title and release_year
-- INSERT INTO ... SELECT is used to avoid hardcoded foreign keys and make the script reusable


BEGIN;

-- Pre-check:
-- we are checking whether any of the chosen films
-- already exist - to avoid duplicates

SELECT
	f.film_id,
	f.title,
	f.release_year 
FROM public.film f 
WHERE (	f.title, f.release_year) IN (
	('DOCTOR STRANGE IN THE MULTIVERSE OF MADNESS', 2022),
    ('SHERLOCK HOLMES: A GAME OF SHADOWS', 2011),
    ('KING ARTHUR: LEGEND OF THE SWORD', 2017)
);

-- inserting 3 new films
INSERT INTO public.film (
	title,
	description,
	release_year,
	language_id,
	rental_duration,
    rental_rate,
    rating,
    last_update
)
SELECT 
	'DOCTOR STRANGE IN THE MULTIVERSE OF MADNESS' :: text AS title,
	'A Mind-Bending Journey of a Sorcerer who must confront dangerous powers across alternate realities.' :: text AS description,
	2022 :: public."year" AS release_year,
	l.language_id,
	7 :: int2 AS rental_duration,
	4.99 :: numeric(4, 2) AS rental_rate,
	'PG-13' :: public."mpaa_rating" AS rating,
	CURRENT_TIMESTAMP AS last_update
FROM public.language l 
	WHERE l.name = 'English'
		AND NOT EXISTS (			-- using NOT EXISTS to make this script rerunnable
			SELECT 1
			FROM public.film f
			WHERE f.title = 'DOCTOR STRANGE IN THE MULTIVERSE OF MADNESS'
			AND f.release_year = 2022
		)		
UNION ALL
SELECT 
	'SHERLOCK HOLMES: A GAME OF SHADOWS' :: text AS title,
	'A Thrilling Investigation of a Detective and his Companion who must outsmart a brilliant criminal mastermind.' :: text AS description,
	2011 :: public."year" AS release_year,
	l.language_id,
	14 :: int2 AS rental_duration,
	9.99 :: numeric(4, 2) AS rental_rate,
	'PG-13' :: public."mpaa_rating" AS rating,
	CURRENT_TIMESTAMP AS last_update
FROM public.language l 
	WHERE l.name = 'English'
		AND NOT EXISTS (			-- using NOT EXISTS to make this script rerunnable
			SELECT 1
			FROM public.film f
			WHERE f.title = 'SHERLOCK HOLMES: A GAME OF SHADOWS'
			AND f.release_year = 2011
		)		
UNION ALL
SELECT 
	'KING ARTHUR: LEGEND OF THE SWORD' :: text AS title,
	'A Heroic Tale of a Young Warrior who must embrace his destiny and reclaim his kingdom.' :: text AS description,
	2017 :: public."year" AS release_year,
	l.language_id,
	21 :: int2 AS rental_duration,
	19.99 :: numeric(4, 2) AS rental_rate,
	'PG-13' :: public."mpaa_rating" AS rating,
	CURRENT_TIMESTAMP AS last_update
FROM public.language l 
	WHERE l.name = 'English'
		AND NOT EXISTS (			-- using NOT EXISTS to make this script rerunnable
			SELECT 1
			FROM public.film f
			WHERE f.title = 'KING ARTHUR: LEGEND OF THE SWORD'
			AND f.release_year = 2017
		)
RETURNING
-- shows which rows were actually inserted
	title,
	description,
	release_year,
	language_id,
	rental_duration,
    rental_rate,
    rating,
    last_update;

COMMIT;

-- =====================================
-- Task 1.2. Insert links between FILMS and GENRES
-- =====================================

-- Explanations:
-- A separate transaction is used to keep this subtask atomic
-- If the transaction fails, none of the film-category links will be saved
-- Before COMMIT, rollback is possible and only this transaction's changes will be undone
-- Referential integrity is preserved by using existing film_id values from public.film
-- and existing category_id values from public.category
-- The script avoids duplicates by checking existing links with NOT EXISTS

BEGIN;

-- Pre-check:
-- verify whether these film-category links already exist

SELECT 
	fc.film_id,
	f.title,
	fc.category_id,
	c.name AS category_name
FROM public.film_category fc 
INNER JOIN public.film f
	ON fc.film_id = f.film_id
INNER JOIN public.category c
	ON fc.category_id = c.category_id
WHERE (f.title, c.name) IN (
	('DOCTOR STRANGE IN THE MULTIVERSE OF MADNESS', 'Sci-Fi'),
    ('SHERLOCK HOLMES: A GAME OF SHADOWS', 'Action'),
    ('KING ARTHUR: LEGEND OF THE SWORD', 'Drama')
);

-- Insert the pairs film_id + category_id from 2 tables 
-- into 3d table - public.film_category

INSERT INTO public.film_category(
	film_id,
	category_id,
	last_update
)
SELECT 
	f.film_id,
	c.category_id,
	CURRENT_TIMESTAMP AS last_update
FROM public.film f
INNER JOIN category c 
	ON (f.title = 'DOCTOR STRANGE IN THE MULTIVERSE OF MADNESS' AND c.name = 'Sci-Fi')
    OR (f.title = 'SHERLOCK HOLMES: A GAME OF SHADOWS' AND c.name = 'Action')
    OR (f.title = 'KING ARTHUR: LEGEND OF THE SWORD' AND c.name = 'Drama')
WHERE NOT EXISTS (					
-- using NOT EXISTS to make this script rerunnable
	SELECT 1
	FROM public.film_category fc
		WHERE fc.film_id = f.film_id
		AND fc.category_id = c.category_id
)
RETURNING 
	film_id,
	category_id,
	last_update;

COMMIT;

-- =====================================
-- Task 1.3. INSERT ACTORS
-- =====================================

-- Add the real actors who play leading roles in your favorite movies to the 'actor' and 'film_actor' tables (6 or more actors in total).
-- You must decide how to identify actors that already exist in the system and how to avoid duplicates

-- Explanations:
-- A separate transaction is used to keep this subtask atomic
-- If the transaction fails, no new actors will be saved
-- Before COMMIT, rollback is possible and only this transaction's changes will be undone
-- The script avoids duplicates by checking existing actors by first_name and last_name
-- INSERT INTO ... SELECT is used to make the script reusable and rerunnable

BEGIN;

-- Pre-check:
-- verify whether any of these actors already exist

SELECT
	a.actor_id,
	a.first_name,
	a.last_name
FROM public.actor a 
WHERE (a.first_name, a.last_name) IN (
    ('BENEDICT', 'CUMBERBATCH'),
    ('ELIZABETH', 'OLSEN'),
    ('ROBERT', 'DOWNEY JR.'),
    ('JUDE', 'LAW'),
    ('CHARLIE', 'HUNNAM'),
    ('ASTRID', 'BERGÈS-FRISBEY')
);

-- inserting actors after checking
WITH actors_to_insert AS (
	SELECT
        'BENEDICT'::text AS first_name,
        'CUMBERBATCH'::text AS last_name
    UNION ALL
    SELECT
        'ELIZABETH'::text,
        'OLSEN'::text
    UNION ALL
    SELECT
        'ROBERT'::text,
        'DOWNEY JR.'::text
    UNION ALL
    SELECT
        'JUDE'::text,
        'LAW'::text
    UNION ALL
    SELECT
        'CHARLIE'::text,
        'HUNNAM'::text
    UNION ALL
    SELECT
        'ASTRID'::text,
        'BERGÈS-FRISBEY'::text
)
-- Insert only missing actors
INSERT INTO public.actor (
	first_name,
	last_name,
	last_update
)
SELECT
	ati.first_name,
	ati.last_name,
	CURRENT_TIMESTAMP AS last_update
FROM actors_to_insert ati
WHERE NOT EXISTS(
-- if table actor has not these actors yet
	SELECT 1
	FROM public.actor a
	WHERE a.first_name = ati.first_name
		AND a.last_name = ati.last_name
)
-- RETURNING shows which actors were actually inserted
RETURNING
	actor_id,
	first_name,
	last_name,
	last_update;

COMMIT;
	

-- =====================================
-- Task 1.4. INSERT FILM_ACTOR links
-- =====================================
-- Link the selected films to their leading actors.

-- Explanations:
-- A separate transaction is used to keep this subtask atomic
-- If the transaction fails, no film-actor links will be saved
-- Before COMMIT, rollback is possible 
-- Referential integrity is preserved by using existing film_id values from public.film
-- and existing actor_id values from public.actor
-- The script avoids duplicates by checking existing links with NOT EXISTS
-- INSERT INTO ... SELECT is used to avoid hardcoded IDs and make the script reusable

BEGIN;

-- Pre-check:
-- verify whether these film-actor links already exist

SELECT 
	fa.actor_id,
	a.first_name,
	a.last_name,
	f.title,
	fa.film_id 
FROM public.film_actor fa 
INNER JOIN public.film f
	ON f.film_id = fa.film_id
INNER JOIN public.actor a
	ON a.actor_id = fa.actor_id
WHERE (f.title, a.first_name, a.last_name) IN (
    ('DOCTOR STRANGE IN THE MULTIVERSE OF MADNESS', 'BENEDICT', 'CUMBERBATCH'),
    ('DOCTOR STRANGE IN THE MULTIVERSE OF MADNESS', 'ELIZABETH', 'OLSEN'),
    ('SHERLOCK HOLMES: A GAME OF SHADOWS', 'ROBERT', 'DOWNEY JR.'),
    ('SHERLOCK HOLMES: A GAME OF SHADOWS', 'JUDE', 'LAW'),
    ('KING ARTHUR: LEGEND OF THE SWORD', 'CHARLIE', 'HUNNAM'),
    ('KING ARTHUR: LEGEND OF THE SWORD', 'ASTRID', 'BERGÈS-FRISBEY')
);

-- inserting film-actors links after checking
WITH film_actor_to_insert AS (
	SELECT
        'DOCTOR STRANGE IN THE MULTIVERSE OF MADNESS'::text AS title,
        'BENEDICT'::text AS first_name,
        'CUMBERBATCH'::text AS last_name
    UNION ALL
    SELECT
    	'DOCTOR STRANGE IN THE MULTIVERSE OF MADNESS'::text,
        'ELIZABETH'::text,
        'OLSEN'::text
    UNION ALL
    SELECT
        'SHERLOCK HOLMES: A GAME OF SHADOWS'::text,
        'ROBERT'::text,
        'DOWNEY JR.'::text
    UNION ALL
    SELECT
        'SHERLOCK HOLMES: A GAME OF SHADOWS'::text,
        'JUDE'::text,
        'LAW'::text
    UNION ALL
    SELECT
        'KING ARTHUR: LEGEND OF THE SWORD'::text,
        'CHARLIE'::text,
        'HUNNAM'::text
    UNION ALL
    SELECT
        'KING ARTHUR: LEGEND OF THE SWORD'::text,
        'ASTRID'::text,
        'BERGÈS-FRISBEY'::text
)
-- Insert only missing film-actor links
INSERT INTO public.film_actor (
	actor_id,
	film_id,
	last_update
)
SELECT
	a.actor_id,
	f.film_id,
	CURRENT_TIMESTAMP AS last_update
FROM film_actor_to_insert fati
INNER JOIN public.film f 
	ON f.title = fati.title
INNER JOIN public.actor a 
    ON a.first_name = fati.first_name
   	AND a.last_name = fati.last_name
WHERE NOT EXISTS(
-- if table film_actor has not these film-actor links yet
	SELECT 1
	FROM public.film_actor fa
	WHERE fa.actor_id = a.actor_id
		AND fa.film_id = f.film_id
)
-- RETURNING shows which actors were actually inserted
RETURNING
	actor_id,
	film_id,
	last_update;

COMMIT;


-- =====================================
-- Task 1.5. INSERT movies to INVENTORY
-- =====================================
-- Add your favorite movies to any store's inventory
-- assuming that we adding 1 copy of each film

-- Explanations:
-- A separate transaction is used to keep this subtask atomic
-- If the transaction fails, no inventory records will be saved
-- Before COMMIT, rollback is possible and only this transaction's changes will be undone
-- Referential integrity is preserved by using existing film_id values from public.film
-- and an existing store_id from public.store
-- The script avoids unnecessary duplicates by checking whether the same film
-- is already present in the same store
-- INSERT INTO ... SELECT is used to avoid hardcoded film IDs and make the script reusable


BEGIN;

-- Pre-check:
-- verify whether these films are already exists in INVENTORY

SELECT
    i.inventory_id,
    i.film_id,
    f.title,
    i.store_id,
    i.last_update
FROM public.inventory i
INNER JOIN public.film f
    ON f.film_id = i.film_id
WHERE f.title IN (
      'DOCTOR STRANGE IN THE MULTIVERSE OF MADNESS',
      'SHERLOCK HOLMES: A GAME OF SHADOWS',
      'KING ARTHUR: LEGEND OF THE SWORD'
  );

-- 
WITH selected_store AS (
-- selecting the first store in the store table by sorting
    SELECT
        s.store_id
    FROM public.store s
    ORDER BY s.store_id ASC
    LIMIT 1
),
add_films_to_inventory AS (
    SELECT 'DOCTOR STRANGE IN THE MULTIVERSE OF MADNESS'::text AS title
    UNION ALL
    SELECT 'SHERLOCK HOLMES: A GAME OF SHADOWS'::text
    UNION ALL
    SELECT 'KING ARTHUR: LEGEND OF THE SWORD'::text
)
INSERT INTO public.inventory (
	film_id,
    store_id,
    last_update
)
SELECT 
	f.film_id,
	ss.store_id,
	CURRENT_TIMESTAMP AS last_update
FROM add_films_to_inventory afti
INNER JOIN public.film f
	ON f.title = afti.title
CROSS JOIN selected_store ss
WHERE NOT EXISTS(
-- insert only if the selected store does not already have this film
	SELECT 1
	FROM public.inventory i
	WHERE i.store_id = ss.store_id
		AND i.film_id = f.film_id
)
-- RETURNING shows which inventory rows were actually inserted
RETURNING
	film_id,
    store_id,
    last_update;

COMMIT;

-- =====================================
-- Task 1.6. UPDATE existing CUSTOMER with my personal data
-- =====================================
-- Alter any existing customer in the database with at least 43 rental and 43 payment records.
-- Change their personal data to yours (first name, last name, address, etc.).
-- You can use any existing address from the "address" table.

-- Remove any records related to you (as a customer) from all tables except 'Customer' and 'Inventory'

-- Explanations:
-- A separate transaction is used to keep this subtask atomic
-- If the transaction fails, no customer data will be changed
-- Before COMMIT, rollback is possible and only this transaction's changes will be undone
-- Referential integrity is preserved because address_id refers to an existing row in public.address
-- The update targets one specific customer selected by customer_id.

SELECT
-- selecting customer with 43+ rentals and 43+ payments to alter his/her data later
	c.customer_id,
	c.first_name,
	c.last_name,
	c.email,
	c.address_id,
	COUNT(DISTINCT r.rental_id) AS number_of_rentals,
	COUNT(DISTINCT p.payment_id) AS number_of_payments
FROM public.customer c
LEFT JOIN public.rental r 
	ON r.customer_id = c.customer_id 
LEFT JOIN public.payment p 
	ON p.customer_id = c.customer_id 
GROUP BY 
	c.customer_id,
	c.first_name,
	c.last_name,
	c.email,
	c.address_id
HAVING COUNT(DISTINCT r.rental_id) >= 43
	AND COUNT(DISTINCT p.payment_id) >= 43
ORDER BY 
	number_of_rentals DESC,
	number_of_payments DESC,
	c.customer_id ASC;
	

BEGIN;

-- Pre-check:
-- verify the selected customer before update

WITH selected_customer AS (
    SELECT
        c.customer_id,
        COUNT(DISTINCT r.rental_id) AS number_of_rentals,
		COUNT(DISTINCT p.payment_id) AS number_of_payments
    FROM public.customer c
    LEFT JOIN public.rental r
        ON r.customer_id = c.customer_id
    LEFT JOIN public.payment p
        ON p.customer_id = c.customer_id
    GROUP BY c.customer_id
    HAVING COUNT(DISTINCT r.rental_id) >= 43 
       AND COUNT(DISTINCT p.payment_id) >= 43 
    ORDER BY
	    number_of_rentals DESC,
		number_of_payments DESC,
		c.customer_id ASC
    LIMIT 1
)
SELECT
    c.customer_id,
    c.store_id,
    c.first_name,
    c.last_name,
    c.email,
    c.address_id,
    c.activebool,
    c.create_date,
    c.last_update,
    c.active
FROM public.customer c
INNER JOIN selected_customer sc
    ON sc.customer_id = c.customer_id;
	
-- updating customer's info with my personal data
WITH selected_customer AS (
    SELECT
        c.customer_id,
        COUNT(DISTINCT r.rental_id) AS number_of_rentals,
		COUNT(DISTINCT p.payment_id) AS number_of_payments
    FROM public.customer c
    LEFT JOIN public.rental r
        ON r.customer_id = c.customer_id
    LEFT JOIN public.payment p
        ON p.customer_id = c.customer_id
    GROUP BY c.customer_id
    HAVING COUNT(DISTINCT r.rental_id) >= 43 
       AND COUNT(DISTINCT p.payment_id) >= 43 
    ORDER BY
	    number_of_rentals DESC,
		number_of_payments DESC,
		c.customer_id ASC
    LIMIT 1
)
UPDATE public.customer c
SET
	first_name = 'JULIA',
	last_name = 'POHREBITSKA',
	email = 'j.pohrebitska@ukr.net',
	last_update = CURRENT_TIMESTAMP
FROM selected_customer sc
WHERE sc.customer_id = c.customer_id 
RETURNING
-- specifying rows will be updated 
	c.customer_id,
    c.store_id,
    c.first_name,
    c.last_name,
    c.email,
    c.address_id,
    c.activebool,
    c.create_date,
    c.last_update,
    c.active;

COMMIT;

	
-- =====================================
-- Task 1.7. DELETE old records related to me from Rental and Payment
-- =====================================
-- Remove any records related to you (as a customer) 
-- from all tables except 'Customer' and 'Inventory'
-- So, we need to delete selected customer's data from Payment and Rental

-- Explanations:
-- A separate transaction is used to keep this subtask atomic
-- If the transaction fails, no old related records will be deleted
-- Before COMMIT, rollback is possible 
-- Deleting from Payment first and then from Rental helps avoid dependency issues
-- The script only affects records of the selected customer

BEGIN;

-- Pre-check:
-- show existing payments and rentals for the selected customer

WITH selected_customer AS (
    SELECT
        c.customer_id
    FROM public.customer c
    WHERE c.first_name = 'JULIA'
      AND c.last_name = 'POHREBITSKA'
      AND c.email = 'j.pohrebitska@ukr.net'
)
SELECT 
	sc.customer_id,
	r.rental_id,
	r.rental_date,
	p.payment_id,
	p.payment_date
FROM selected_customer sc
LEFT JOIN public.rental r
	ON r.customer_id = sc.customer_id 
LEFT JOIN public.payment p
	ON p.rental_id = r.rental_id 
ORDER BY
    r.rental_date,
    p.payment_date;

-- Delete old PAYMENTS of the selected customer
DELETE FROM public.payment p
WHERE p.customer_id IN (
    SELECT c.customer_id
    FROM public.customer c
    WHERE c.first_name = 'JULIA'
      	AND c.last_name = 'POHREBITSKA'
      	AND c.email = 'j.pohrebitska@ukr.net'
	)
RETURNING 
	p.payment_id,
	p.customer_id,
	p.staff_id,
	p.rental_id,
	p.amount,
	p.payment_date;

-- Delete old RENTALS of the selected customer
DELETE FROM public.rental r
WHERE r.customer_id IN (
    SELECT c.customer_id
    FROM public.customer c
    WHERE c.first_name = 'JULIA'
      	AND c.last_name = 'POHREBITSKA'
      	AND c.email = 'j.pohrebitska@ukr.net'
	)
RETURNING 
	r.rental_id,
	r.rental_date,
	r.inventory_id,
	r.customer_id,
	r.return_date,
	r.staff_id,
	r.last_update;
	
COMMIT; 

-- =====================================
-- Task 1.8. INSERT RENTALS
-- =====================================
-- RENT your favorite movies from the store they are in 
-- (add corresponding records to the database to represent this activity)

-- Explanations:
-- A separate transaction is used to keep this subtask atomic
-- If the transaction fails, no rental records will be saved
-- Before COMMIT, rollback is possible and only this transaction's changes will be undone
-- Referential integrity is preserved by using existing customer_id, inventory_id, and staff_id values
-- The script avoids duplicates by checking whether the same customer already rented
-- the same inventory item on the same rental_date.
-- Store and staff are selected dynamically, without hardcoding store_id

BEGIN;

-- Pre-check:
-- show the inventory items and one existing staff member

-- this query shows that 3 films are in inventory
SELECT
    i.inventory_id,
    i.film_id,
    f.title,
    i.store_id
FROM public.inventory i
INNER JOIN public.film f
    ON f.film_id = i.film_id
WHERE f.title IN (
      'DOCTOR STRANGE IN THE MULTIVERSE OF MADNESS',
      'SHERLOCK HOLMES: A GAME OF SHADOWS',
      'KING ARTHUR: LEGEND OF THE SWORD'
  );

-- this query shows one staff member from the selected store
SELECT 
	s.staff_id,
	s.first_name,
	s.last_name,
	s.store_id
FROM public.staff s
WHERE s.store_id = (
	SELECT
    	i.store_id
    FROM public.inventory i
    ORDER BY i.store_id ASC
    LIMIT 1
    )
ORDER BY s.staff_id ASC
LIMIT 1;


WITH rentals_to_insert AS(
	SELECT
        'DOCTOR STRANGE IN THE MULTIVERSE OF MADNESS'::text AS title,
        TIMESTAMP '2017-01-10 10:00:00' AS rental_date,
        TIMESTAMP '2017-01-20 10:00:00' AS return_date
    UNION ALL
    SELECT
        'SHERLOCK HOLMES: A GAME OF SHADOWS'::text,
        TIMESTAMP '2017-01-11 11:00:00',
        TIMESTAMP '2017-01-21 11:00:00'
    UNION ALL
    SELECT
        'KING ARTHUR: LEGEND OF THE SWORD'::text,
        TIMESTAMP '2017-01-12 12:00:00',
        TIMESTAMP '2017-01-22 12:00:00'
),
customer_data AS (
    SELECT c.customer_id
    FROM public.customer c
    WHERE c.first_name = 'JULIA'
      	AND c.last_name = 'POHREBITSKA'
      	AND c.email = 'j.pohrebitska@ukr.net'
),
inventory_data AS(
	SELECT
		i.inventory_id,
		i.store_id,
		f.title
	FROM public.inventory i
	INNER JOIN public.film f
		ON f.film_id = i.film_id 
	WHERE f.title IN (
        'DOCTOR STRANGE IN THE MULTIVERSE OF MADNESS',
        'SHERLOCK HOLMES: A GAME OF SHADOWS',
        'KING ARTHUR: LEGEND OF THE SWORD'
        )
),
staff_data AS(
	SELECT 
		s.staff_id
	FROM public.staff s
	WHERE s.store_id = (
		SELECT
	    	idata.store_id
	    FROM inventory_data idata
	    ORDER BY idata.store_id ASC
	    LIMIT 1
	    )
	ORDER BY s.staff_id ASC
	LIMIT 1
)
INSERT INTO public.rental (
	rental_date,
	inventory_id,
	customer_id,
	return_date,
	staff_id,
	last_update
)
SELECT 
	rti.rental_date,
	idata.inventory_id,
	cd.customer_id,
	rti.return_date,
	sd.staff_id,
	CURRENT_TIMESTAMP AS last_update
FROM rentals_to_insert rti
INNER JOIN inventory_data idata
	ON idata.title = rti.title
CROSS JOIN customer_data cd
CROSS JOIN staff_data sd
WHERE NOT EXISTS (
	SELECT 1
	FROM public.rental r
	WHERE r.rental_date = rti.rental_date
		AND r.inventory_id = idata.inventory_id
		AND r.customer_id = cd.customer_id
)
RETURNING
	rental_date,
	inventory_id,
	customer_id,
	return_date,
	staff_id,
	last_update;

COMMIT; 


-- =====================================
-- Task 1.9. INSERT PAYMENTS	
-- =====================================
-- PAY for your favorite movies
-- (add corresponding records to the database to represent this activity)

-- Explanations:
-- A separate transaction is used to keep this subtask atomic
-- If the transaction fails, no payment records will be saved
-- Before COMMIT, rollback is possible.
-- Referential integrity is preserved by using existing customer_id, staff_id, and rental_id values.
-- The script avoids duplicates by checking whether the same payment already exists
-- for the same customer, rental, amount, and payment_date.

BEGIN;

-- Pre-check:
-- show the selected rentals that will be used for payments

SELECT
    r.rental_id,
    r.rental_date,
    r.inventory_id,
    r.customer_id,
    r.return_date,
    r.staff_id,
    f.title,
    f.rental_rate
FROM public.rental r
INNER JOIN public.inventory i
    ON i.inventory_id = r.inventory_id
INNER JOIN public.film f
    ON f.film_id = i.film_id
INNER JOIN public.customer c
    ON c.customer_id = r.customer_id
WHERE c.first_name = 'JULIA'
	AND c.last_name = 'POHREBITSKA'
	AND c.email = 'j.pohrebitska@ukr.net'
	AND f.title IN (
      'DOCTOR STRANGE IN THE MULTIVERSE OF MADNESS',
      'SHERLOCK HOLMES: A GAME OF SHADOWS',
      'KING ARTHUR: LEGEND OF THE SWORD'
      )
ORDER BY r.rental_date;


WITH payments_to_insert AS (
    SELECT
        'DOCTOR STRANGE IN THE MULTIVERSE OF MADNESS'::text AS title,
        TIMESTAMP '2017-01-10 10:05:00' AS payment_date
    UNION ALL
    SELECT
        'SHERLOCK HOLMES: A GAME OF SHADOWS'::text,
        TIMESTAMP '2017-01-11 11:05:00'
    UNION ALL
    SELECT
        'KING ARTHUR: LEGEND OF THE SWORD'::text,
        TIMESTAMP '2017-01-12 12:05:00'
),
customer_data AS (
    SELECT
        c.customer_id
    FROM public.customer c
    WHERE c.first_name = 'JULIA'
    	AND c.last_name = 'POHREBITSKA'
    	AND c.email = 'j.pohrebitska@ukr.net'
),
rental_data AS (
    SELECT
        r.rental_id,
        r.rental_date,
        r.customer_id,
        r.staff_id,
        f.title,
        f.rental_rate
    FROM public.rental r
    INNER JOIN public.inventory i
        ON i.inventory_id = r.inventory_id
    INNER JOIN public.film f
        ON f.film_id = i.film_id
    WHERE f.title IN (
        'DOCTOR STRANGE IN THE MULTIVERSE OF MADNESS',
        'SHERLOCK HOLMES: A GAME OF SHADOWS',
        'KING ARTHUR: LEGEND OF THE SWORD'
    )
)
INSERT INTO public.payment (
    customer_id,
    staff_id,
    rental_id,
    amount,
    payment_date
)
SELECT
    cd.customer_id,
    rd.staff_id,
    rd.rental_id,
    rd.rental_rate AS amount,
    pti.payment_date
FROM payments_to_insert pti
INNER JOIN rental_data rd
    ON rd.title = pti.title
INNER JOIN customer_data cd
    ON cd.customer_id = rd.customer_id
WHERE NOT EXISTS (
    SELECT 1
    FROM public.payment p
    WHERE p.customer_id = cd.customer_id
      AND p.rental_id = rd.rental_id
      AND p.amount = rd.rental_rate
      AND p.payment_date = pti.payment_date
)
RETURNING
    payment_id,
    customer_id,
    staff_id,
    rental_id,
    amount,
    payment_date;

COMMIT;



