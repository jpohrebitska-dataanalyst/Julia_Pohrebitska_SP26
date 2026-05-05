-- ==============================
-- Tasks: applying view and FUNCTIONS
-- ==============================

-- ==============================
-- Task 1. Create a VIEW
-- ==============================
-- Create a view called 'sales_revenue_by_category_qtr' that shows the film category 
-- and total sales revenue for the current quarter and year.
-- The view should only display categories with at least one sale in the current quarter. 

-- Explain in the comment how you determine:
-- current quarter
-- current year
-- why only categories with sales appear
-- how zero-sales categories are excluded
-- the current default database does not contain data for the current year. Also, please indicate how you verified that view is working correctly
-- Provide example of data that should NOT appear

-- Comments:
-- 1. Current year is determined dynamically using EXTRACT(YEAR FROM CURRENT_DATE).
-- 2. Current quarter is determined dynamically using EXTRACT(QUARTER FROM CURRENT_DATE).
-- 3. Only categories with at least one sale in the current quarter appear,
--    because we use INNER JOINs and aggregate only existing payment records.
-- 	  No payments - no rows in the resulting query.
-- 4. Categories with zero sales are excluded automatically since they do not
--    produce rows in the aggregated result set (because of INNER JOINs).
-- 5. The default dvdrental dataset usually contains data for 2017H1 only.
--    As for now the VIEW returns an empty result for the actual current quarter/year. 
--    As a test we can check the VIEW for dates that do exist (2017H1), and they return the correct result.
--    (you may see the TESTING below)
-- 6. Example of data that should NOT appear:
-- - categories with payments from previous QUARTERS,
-- - categories with payments from previous YEARS,
-- - categories that have films, but no sales (p.amount) in the current quarter/year


-- ==============================
-- Pre-check
	
SELECT
	MIN(p.payment_date) AS min_date,
	MAX(p.payment_date) AS max_date
FROM payment p;

-- ==============================
-- creating view 'sales_revenue_by_category_qtr'

CREATE OR REPLACE VIEW public.sales_revenue_by_category_qtr AS       -- CREATE OR REPLACE - to avoid duplicates
SELECT
	EXTRACT(YEAR FROM CURRENT_DATE) AS current_year,
	EXTRACT(QUARTER FROM CURRENT_DATE) AS current_quarter,
	c.category_id,
	c.name AS category_name,
	SUM(p.amount) AS total_revenue
FROM public.payment p
INNER JOIN public.rental r
	ON r.rental_id = p.rental_id
INNER JOIN public.inventory i
	ON i.inventory_id = r.inventory_id
INNER JOIN public.film f
	ON f.film_id = i.film_id
INNER JOIN public.film_category fc
	ON fc.film_id = f.film_id
INNER JOIN public.category c
	ON c.category_id = fc.category_id
WHERE EXTRACT(YEAR FROM p.payment_date) = EXTRACT(YEAR FROM CURRENT_DATE)
	AND EXTRACT(QUARTER FROM p.payment_date) = EXTRACT(QUARTER FROM CURRENT_DATE)
GROUP BY 
	EXTRACT(YEAR FROM CURRENT_DATE),
	EXTRACT(QUARTER FROM CURRENT_DATE),
	c.category_id,
	c.name
HAVING SUM(p.amount) > 0;

COMMENT ON VIEW public.sales_revenue_by_category_qtr IS
'Shows total revenue by film category for the current quarter and current year. 
Revenue is calculated as SUM(payment.amount). 
Only categories with actual sales appear in the result.';

-- ==============================
-- VIEW testing

SELECT *
FROM public.sales_revenue_by_category_qtr;	

-- checking - which years/quaters really exist
SELECT
    EXTRACT(YEAR FROM payment_date) AS payment_year,
    EXTRACT(QUARTER FROM payment_date) AS payment_quarter,
    COUNT(*) AS payments_nmb,
    SUM(amount) AS total_revenue
FROM public.payment
GROUP BY
    EXTRACT(YEAR FROM payment_date),
    EXTRACT(QUARTER FROM payment_date)
ORDER BY
    payment_year,
    payment_quarter;

-- checking VIEW for existing year & quarter (2017Q2)
SELECT
	EXTRACT(YEAR FROM p.payment_date) AS payment_year,
	EXTRACT(QUARTER FROM p.payment_date) AS payment_quarter,	
	c.category_id,
	c.name AS category_name,
	SUM(p.amount) AS total_revenue
FROM public.payment p
INNER JOIN public.rental r
	ON r.rental_id = p.rental_id
INNER JOIN public.inventory i
	ON i.inventory_id = r.inventory_id
INNER JOIN public.film f
	ON f.film_id = i.film_id
INNER JOIN public.film_category fc
	ON fc.film_id = f.film_id
INNER JOIN public.category c
	ON c.category_id = fc.category_id
WHERE EXTRACT(YEAR FROM p.payment_date) = 2017
	AND EXTRACT(QUARTER FROM p.payment_date) = 2
GROUP BY 
	EXTRACT(YEAR FROM p.payment_date),
	EXTRACT(QUARTER FROM p.payment_date),
	c.category_id,
	c.name;
	

-- ==============================
-- Task 2. Create a query language FUNCTIONS
-- ==============================
-- Create a query language function called 'get_sales_revenue_by_category_qtr' that accepts 
-- 1 parameter representing the current quarter and year 
-- and returns the same result as the 'sales_revenue_by_category_qtr' VIEW.
--
-- Explain in the comment:
-- - why parameter is needed
-- - what happens if:
-- - invalid quarter is passed
-- - no data exist

-- Comments:
-- 1. The parameter is needed to make the function REUSABLE for ANY quarter/year.
-- 2. The function accepts 1 DATE parameter --> and derives year and quarter from it --> EXTRACT(QUARTER FROM p_target_date).
-- 3. Invalid quarter values cannot be passed directly, because quarter is not entered manually.
-- 4. If NULL is passed, the function returns no rows.
-- 5. If no data exists for the requested quarter/year, the function returns an empty result table.
-- 6. Revenue is calculated as SUM(p.amount), and only categories with actual sales appear because INNER JOINs are used.
-- 7. CREATE OR REPLACE FUNCTION makes the script RERUNNABLE.

-- ==============================
-- creating function 'get_sales_revenue_by_category_qtr'

CREATE OR REPLACE FUNCTION public.get_sales_revenue_by_category_qtr(p_target_date DATE)
RETURNS TABLE (
    target_year INTEGER,
    target_quarter INTEGER,
    category_id INTEGER,
    category_name TEXT,
    total_revenue NUMERIC
)
LANGUAGE SQL
AS $$
    SELECT
        EXTRACT(YEAR FROM p_target_date)::INTEGER AS target_year,
        EXTRACT(QUARTER FROM p_target_date)::INTEGER AS target_quarter,
        c.category_id,
        c.name AS category_name,
        SUM(p.amount) AS total_revenue
    FROM public.payment p
    INNER JOIN public.rental r
        ON r.rental_id = p.rental_id
    INNER JOIN public.inventory i
        ON i.inventory_id = r.inventory_id
    INNER JOIN public.film f
        ON f.film_id = i.film_id
    INNER JOIN public.film_category fc
        ON fc.film_id = f.film_id
    INNER JOIN public.category c
        ON c.category_id = fc.category_id
    WHERE EXTRACT(YEAR FROM p.payment_date) = EXTRACT(YEAR FROM p_target_date)
      AND EXTRACT(QUARTER FROM p.payment_date) = EXTRACT(QUARTER FROM p_target_date)
    GROUP BY
        EXTRACT(YEAR FROM p_target_date),
        EXTRACT(QUARTER FROM p_target_date),
        c.category_id,
        c.name
	HAVING SUM(p.amount) > 0
$$;

COMMENT ON FUNCTION public.get_sales_revenue_by_category_qtr(DATE) IS
'Returns total revenue by film category for the quarter and year of the input date. 
You can pass any date within the needed quarter, for example 2017-05-15 for 2017Q2.
Revenue is calculated as SUM(payment.amount). 
Only categories with actual sales are included.';


-- ==============================
-- FUNCTION testing

-- Test 1. Valid input
-- returns category revenue for 2017Q2,
-- because 2017-04-01 belongs to 2017Q2.

SELECT *
FROM public.get_sales_revenue_by_category_qtr(DATE '2017-04-01');


-- Test 2. Edge input: NULL
-- returns 0 rows.
-- 
-- EXTRACT(YEAR/QUARTER FROM NULL) returns NULL,
-- therefore the WHERE condition is not satisfied.

SELECT *
FROM public.get_sales_revenue_by_category_qtr(NULL);


-- Test 3. Valid input, but no data exists
-- returns 0 rows,
-- because the default dvdrental dataset usually has no payments for 2026 Q2.

SELECT *
FROM public.get_sales_revenue_by_category_qtr(DATE '2026-04-08');


-- Test 4. Compare function output with manual query for existing data (2017Q2)
-- same business logic and same aggregation as in the function.

SELECT
    EXTRACT(YEAR FROM p.payment_date) AS payment_year,
    EXTRACT(QUARTER FROM p.payment_date) AS payment_quarter,
    c.category_id,
    c.name AS category_name,
    SUM(p.amount) AS total_revenue
FROM public.payment p
INNER JOIN public.rental r
    ON r.rental_id = p.rental_id
INNER JOIN public.inventory i
    ON i.inventory_id = r.inventory_id
INNER JOIN public.film f
    ON f.film_id = i.film_id
INNER JOIN public.film_category fc
    ON fc.film_id = f.film_id
INNER JOIN public.category c
    ON c.category_id = fc.category_id
WHERE EXTRACT(YEAR FROM p.payment_date) = 2017
  AND EXTRACT(QUARTER FROM p.payment_date) = 2
GROUP BY
    EXTRACT(YEAR FROM p.payment_date),
    EXTRACT(QUARTER FROM p.payment_date),
    c.category_id,
    c.name
HAVING SUM(p.amount) > 0
ORDER BY
    c.category_id;

-- ==============================
-- Task 3. Create procedure language FUNCTIONS
-- ==============================
-- Create a function that takes a country as an input parameter 
-- and returns the most popular film in that specific country.
--
-- Query example:
-- SELECT *
-- FROM public.most_popular_films_by_countries(ARRAY['Afghanistan', 'Brazil', 'United States']);
--
-- Explain in the comment:
-- - how 'most popular' is defined
-- - how ties are handled
-- - what happens if country has no data
--
-- Comments:
-- 1. The function accepts an array of country names to make the solution reusable
--    for one country or for multiple countries in one call.
-- 2. Most popular is defined by RENTALS COUNT --> COUNT(r.rental_id):
--    we count how many times each film was rented by customers from a given country.
-- 3. Ties are handled by returning ALL films whose rentals_count 
--    equals the maximum rentals_count within the country.
-- 4. If a country exists, but has no rental data,
--    the function returns 1 row for that country with NULL film details (because of LEFT JOIN).
-- 5. If the input array is NULL, empty, or contains NULL / blank country names,
--    the function raises an exception.
-- 6. If one or more input country names do not exist in public.country,
--    the function raises an exception and shows which values are invalid.
-- 7. CREATE OR REPLACE FUNCTION makes the script rerunnable.


-- ==============================
-- creating function 'most_popular_films_by_countries'

CREATE OR REPLACE FUNCTION public.most_popular_films_by_countries(p_input_countries TEXT[])
RETURNS TABLE (
    country TEXT,
    film TEXT,
    rating public."mpaa_rating",
    language BPCHAR(20),
    length SMALLINT,
    release_year public."year"
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_invalid_countries TEXT;
BEGIN
	-- list of exceptions:
	-- 1)
    IF p_input_countries IS NULL THEN
        RAISE EXCEPTION 'Input array of countries must not be NULL.';
    END IF;

	-- 2) validate that the length of the array > 0
    IF COALESCE(array_length(p_input_countries, 1), 0) = 0 THEN              -- array_length() returns NULL if the input array is NULL
        RAISE EXCEPTION 'Input array of countries must not be empty.';		 -- (p_input_countries, 1) --> 1-dimension array	
    END IF;
	
	-- 3) validate that EACH array element contains a non-empty country name
    IF EXISTS (
        SELECT 1
        FROM unnest(p_input_countries) AS c(country)
        WHERE c.country IS NULL
           OR BTRIM(c.country) = ''
    ) THEN
        RAISE EXCEPTION 'Input array contains NULL or empty country names.';
    END IF;

	-- 4) collect unknown countries and raise an exception if any are found
    SELECT STRING_AGG(cleaned.country, ', ' ORDER BY cleaned.country)          -- collect countries in one string
    INTO v_invalid_countries
    FROM (
        SELECT DISTINCT BTRIM(c.country) AS country
        FROM unnest(p_input_countries) AS c(country)
    ) cleaned
    LEFT JOIN public.country ref
        ON ref.country = cleaned.country
    WHERE ref.country_id IS NULL;

    IF v_invalid_countries IS NOT NULL THEN
        RAISE EXCEPTION 'These countries do not exist in public.country: %', v_invalid_countries;
    END IF;

	-- main query:
    RETURN QUERY
    WITH input_countries AS (
        -- remove duplicates and preserve input order
        SELECT DISTINCT ON (BTRIM(c.country))
            BTRIM(c.country) AS country,
            country_order
        FROM unnest(p_input_countries) WITH ORDINALITY AS c(country, country_order)
        ORDER BY
            BTRIM(c.country),
            country_order
    ),
    film_rentals AS (
        -- count rentals for each film in each input country
        SELECT
            co.country,
            f.film_id,
            f.title,
            f.rating,
            l.name,
            f.length,
            f.release_year,
            COUNT(r.rental_id) AS rentals_count
        FROM public.customer cu
        INNER JOIN public.address a
            ON a.address_id = cu.address_id
        INNER JOIN public.city ci
            ON ci.city_id = a.city_id
        INNER JOIN public.country co
            ON co.country_id = ci.country_id
        INNER JOIN public.rental r
            ON r.customer_id = cu.customer_id
        INNER JOIN public.inventory i
            ON i.inventory_id = r.inventory_id
        INNER JOIN public.film f
            ON f.film_id = i.film_id
        INNER JOIN public.language l
            ON l.language_id = f.language_id
        WHERE co.country IN (
            SELECT ic.country
            FROM input_countries ic
        )
        GROUP BY
            co.country,
            f.film_id,
            f.title,
            f.rating,
            l.name,
            f.length,
            f.release_year
    ),
    max_rentals_by_country AS (
        -- find maximum rentals count per country (window functions are NOT recommended here)
        SELECT
            fr.country,
            MAX(fr.rentals_count) AS max_rentals_count
        FROM film_rentals fr
        GROUP BY
            fr.country
    ),
    top_films AS (
        -- select only films with the maximum rentals count in each country
        -- that is why it returns all ties (if they exist)
        SELECT
            fr.country,
            fr.title,
            fr.rating,
            fr.name,
            fr.length,
            fr.release_year
        FROM film_rentals fr
        INNER JOIN max_rentals_by_country maxre
            ON maxre.country = fr.country
            AND maxre.max_rentals_count = fr.rentals_count
    )
    SELECT
        ic.country,
        top.title AS film,
        top.rating,
        top.name AS language,
        top.length,
        top.release_year
    FROM input_countries ic
    LEFT JOIN top_films top
        ON top.country = ic.country
    ORDER BY
        ic.country_order,
        top.title;

END;
$$;

COMMENT ON FUNCTION public.most_popular_films_by_countries(TEXT[]) IS
'Returns the most popular film by country for the countries passed in the input array. 
Popularity is calculated by rentals count --> COUNT(r.rental_id). 
If several films share the top rentals count, all of them are returned. 
If a country has no rental data, the function returns that country with NULL film details.';


-- ==============================
-- FUNCTION testing

-- Test 1. Valid input
-- returns the most popular films for each listed country.
-- If there is a tie inside one country, several rows for that country are returned.

SELECT *
FROM public.most_popular_films_by_countries(
    ARRAY['Afghanistan', 'Brazil', 'United States']
);


-- Test 2. Invalid input: NULL array
-- ERROR: Input array of countries must not be NULL.

SELECT *
FROM public.most_popular_films_by_countries(NULL);


-- Test 3. Invalid input: unknown country
-- Expected result:
-- ERROR: These countries do not exist in public.country: Atlantis

SELECT *
FROM public.most_popular_films_by_countries(
    ARRAY['Ukraine', 'Wacanda', 'Sokoviya']
);


-- Test 4. Invalid input: empty value instead of country name
-- ERROR: Input array contains NULL or empty country names.

SELECT *
FROM public.most_popular_films_by_countries(
    ARRAY['Ukraine', '']
);


-- Test 5:
-- find countries that exist in public.country but have NO rental data at all
-- Australia has NO rentals in public.rental

SELECT
    co.country
FROM public.country co
LEFT JOIN public.city ci
    ON ci.country_id = co.country_id
LEFT JOIN public.address a
    ON a.city_id = ci.city_id
LEFT JOIN public.customer cu
    ON cu.address_id = a.address_id
LEFT JOIN public.rental r
    ON r.customer_id = cu.customer_id
GROUP BY
    co.country
HAVING COUNT(r.rental_id) = 0
ORDER BY
    co.country;

-- checking that for Australia the function retrieves NULLs in all rows
SELECT *
FROM public.most_popular_films_by_countries(
    ARRAY['United States', 'Ukraine', 'Australia']
);
 


-- ==============================
-- Task 4. Create procedure language FUNCTIONS
-- ==============================
-- Create a function that generates a list of movies available in stock 
-- based on a partial title match (e.g., movies containing the word 'love' in their title). 
--
-- The titles of these movies are formatted as '%...%', 
-- and if a movie with the specified title is not in stock, 
-- return a message indicating that it was not found.
--
-- The function should produce the result set in the following format: row_num, film_title, language, customer_name, rental_date
-- (note: the 'row_num' field is an automatically generated counter field, 
-- starting from 1 and incrementing for each entry, e.g., 1, 2, ..., 100, 101, ...).
-- 
-- Query example: select * from public.films_in_stock_by_title('%love%’);
-- 
-- Explain in the comment:
-- - how pattern matching works (LIKE, %)
-- - how you ensure performance: which part of your query may become slow on large data;
-- - how your implementation minimizes unnecessary data processing
-- - case sensitivity
-- - what happens if:
--   - multiple matches
--   - no matches
--
--
-- Comments:
-- 1. The function searches films by title using ILIKE and a pattern such as '%love%'.
-- 2. '%' in the search pattern means any sequence of characters before or after the word.
-- 3. ILIKE is used to make the search case-insensitive.
-- 4. A film is treated as available in stock if at least one inventory copy is not rented now.
-- 5. The last rental is determined as the latest rental_date for the film.
-- 6. If multiple films match the pattern and are available, all of them are returned.
-- 7. If no matching films are available in stock, the function raises an exception.
-- 8. Performance notes:
-- - The slowest part on large tables may be the joins with rental history.
-- - To keep the query simpler and avoid unnecessary processing,
-- the implementation first narrows the data to matching titles and available copies,
-- and only then adds the latest rental information.



CREATE OR REPLACE FUNCTION public.films_in_stock_by_title(p_word_to_find TEXT)
RETURNS TABLE (
    row_num INTEGER,
    film_title TEXT,
    language BPCHAR(20),
    customer_name TEXT,
    rental_date TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
BEGIN
	-- list of exceptions:
	-- 1) validate that the input word is not NULL
    IF p_word_to_find IS NULL THEN
        RAISE EXCEPTION 'Input search pattern must not be NULL.';
    END IF;

	-- 2) validate that the input word is not empty
    IF BTRIM(p_word_to_find) = '' THEN                                      
        RAISE EXCEPTION 'Input search pattern must not be empty.';		             
    END IF;

	-- main query: returns matching films that are currently in stock
    RETURN QUERY
    WITH stock_films AS (
        -- count films in stock
    	SELECT DISTINCT
            f.film_id,
            f.title,
            l.name AS language
        FROM public.film f
        INNER JOIN public.language l
            ON l.language_id = f.language_id
        INNER JOIN public.inventory i
            ON i.film_id = f.film_id
        LEFT JOIN public.rental r_current
            ON r_current.inventory_id = i.inventory_id
            AND r_current.return_date IS NULL				-- active rental for the copy
        WHERE f.title ILIKE p_word_to_find					-- ILIKE is a case-insensitive version of the LIKE
        	AND r_current.rental_id IS NULL					-- keep only copies that are currently available
    ),
    last_rentals AS (
        SELECT DISTINCT ON (f.film_id)						-- leave 1 row only for 1 film (determined by ORDER BY)
            f.film_id,
            cu.first_name || ' ' || cu.last_name AS customer_name,
            r.rental_date
        FROM public.film f
        INNER JOIN public.inventory i
            ON i.film_id = f.film_id
        INNER JOIN public.rental r
            ON r.inventory_id = i.inventory_id
        INNER JOIN public.customer cu
            ON cu.customer_id = r.customer_id
        ORDER BY
            f.film_id,
            r.rental_date DESC
    )
    SELECT
        ROW_NUMBER() OVER (ORDER BY sf.title)::INTEGER AS row_num,		-- generate row numbers by film title
        sf.title AS film_title,
        sf.language,
        lr.customer_name,
        lr.rental_date
    FROM stock_films sf
    LEFT JOIN last_rentals lr											-- attach the latest rental info for each film
        ON lr.film_id = sf.film_id			
    ORDER BY
        sf.title;

    -- if nothing was returned, raise exception
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No films in stock match the pattern: %', p_word_to_find;
    END IF;
END;
$$;


COMMENT ON FUNCTION public.films_in_stock_by_title(TEXT) IS
'Returns films whose titles match the input pattern and that are currently available in stock. 
Availability means at least one copy exists in inventory and is not rented out now. 
The function also shows the latest rental customer and rental date for each film. 
If no matching films are available, an exception is raised.';


-- ==============================
-- FUNCTION testing

-- Test 1. Valid input
-- returns a list of movies available in stock based on a partial title match

SELECT * 
FROM public.films_in_stock_by_title('%ACADEMY DINOSAUR%');

SELECT * 
FROM public.films_in_stock_by_title('%doctor%');

SELECT * 
FROM public.films_in_stock_by_title('%DOCTOR%');


-- Test 2. Invalid input: NULL input
-- ERROR: Input search pattern must not be NULL.

SELECT *
FROM public.films_in_stock_by_title(NULL);


-- Test 3. Invalid input: empty value
-- ERROR: Input search pattern must not be empty.

SELECT *
FROM public.films_in_stock_by_title('');

-- Test 4. Valid input, but nothing was found
-- EXCEPTION: No films in stock match the pattern

SELECT *
FROM public.films_in_stock_by_title('%no sleep%');



-- ==============================
-- Task 5. Create procedure language FUNCTIONS
-- ==============================
-- Create a procedure language function called 'new_movie' that takes a movie title as a parameter and inserts a new movie 
-- with the given title in the film table.   
-- The function should generate a new unique film ID,
-- set the rental rate to 4.99, the rental duration to three days, the replacement cost to 19.99.
-- The release year and language are optional and by default should be current year and Klingon respectively. 
--
-- Query example:
-- SELECT *
-- FROM public.new_movie('The Gentlemen', 2026, 'English');
--
-- Explain in the comment:
-- how you generate unique ID
-- how you ensure no duplicates
-- what happens if movie already exists
-- how you validate language existence
-- what happens if insertion fails
-- how consistency is preserved
--
-- Comments:
-- 1. A new unique film_id is generated automatically by the film table during INSERT,
--    and the generated value is captured with RETURNING.
-- 2. Duplicate titles are prevented by checking (IF EXISTS) the film table before INSERT.
-- 3. Title comparison is trimmed and case-insensitive.
-- 4. If the movie already exists, the function raises an exception
--    and the INSERT is not performed.
-- 5. The function validates language existence by searching for the input language
--    in public.language using a trimmed, case-insensitive comparison.
-- 6. If the language does not exist, the function inserts it into public.language first.
-- 7. If movie insertion fails, PostgreSQL rolls back the statement,
--    so no partial movie row is saved.
-- 8. Consistency is preserved because validation, optional language insert,
--    and movie insert happen in one function execution.
-- 9. CREATE OR REPLACE FUNCTION makes the script rerunnable.

-- Parameters:
-- - p_title: movie title (required)
-- - p_release_year: optional, defaults to current year
-- - p_language_name: optional, defaults to 'Klingon'


CREATE OR REPLACE FUNCTION public.new_movie(
    p_title TEXT,   
    p_release_year INTEGER DEFAULT EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER,
    p_language_name TEXT DEFAULT 'Klingon'
)
RETURNS TABLE (
    film_id INTEGER,
    title TEXT,
    language BPCHAR(20),
    release_year public."year",
    rental_duration SMALLINT,
    rental_rate NUMERIC,
    replacement_cost NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_new_film_id INTEGER;
    v_language_id SMALLINT;
    v_language_name BPCHAR(20);
BEGIN
    -- 1) validate that the title is not NULL
    IF p_title IS NULL THEN
        RAISE EXCEPTION 'Movie title must not be NULL.';
    END IF;

    -- 2) validate that the title is not empty
    IF BTRIM(p_title) = '' THEN
        RAISE EXCEPTION 'Movie title must not be empty.';
    END IF;

    -- 3) validate that the language name is not NULL or empty
    IF p_language_name IS NULL OR BTRIM(p_language_name) = '' THEN
        RAISE EXCEPTION 'Language name must not be NULL or empty.';
    END IF;

    -- 4) prevent duplicate movie titles (case-insensitive)
    IF EXISTS (
        SELECT 1
        FROM public.film f
        WHERE UPPER(BTRIM(f.title)) = UPPER(BTRIM(p_title))
    ) THEN
        RAISE EXCEPTION 'Movie "%" already exists in public.film.', BTRIM(p_title);
    END IF;

    -- 5) validate that the language exists and get its language_id
    SELECT
        l.language_id,
        l.name
    INTO
        v_language_id,
        v_language_name
    FROM public.language l
    WHERE UPPER(BTRIM(l.name)) = UPPER(BTRIM(p_language_name));

	-- 6) insert the language if it does not exist yet
    IF v_language_id IS NULL THEN
    	INSERT INTO public.language(
			name,
			last_update
		)
		VALUES (
			BTRIM(p_language_name),
			CURRENT_TIMESTAMP
		)
		RETURNING
			language_id,
			name
		INTO
			v_language_id,
			v_language_name;
	END IF;

    -- 7) insert the new movie and capture generated film_id
    INSERT INTO public.film AS f (
        title,
        release_year,
        language_id,
        rental_duration,
        rental_rate,
        replacement_cost
    )
    VALUES (
        UPPER(BTRIM(p_title)),
        p_release_year::public."year",
        v_language_id,
        3,
        4.99,
        19.99
	)
	RETURNING f.film_id
	INTO v_new_film_id;

    -- 8) return the inserted row
	RETURN QUERY
	SELECT
	    f.film_id,
	    f.title::TEXT,
	    l.name AS language,
	    f.release_year,
	    f.rental_duration,
	    f.rental_rate,
	    f.replacement_cost
	FROM public.film f
	INNER JOIN public.language l
	    ON l.language_id = f.language_id
	WHERE f.film_id = v_new_film_id;
END;
$$;


COMMENT ON FUNCTION public.new_movie(TEXT, INTEGER, TEXT) IS
'Inserts a new movie into public.film. 
The function generates a new unique film_id, set the rental_rate to 4.99, 
the rental_duration to 3 days, the replacement_cost to 19.99.
Duplicate titles are checked before insertion using a trimmed, case-insensitive comparison. 
The function validates that the input language exists in public.language. 
If the language is missing, it is inserted as a new language.';


-- ==============================
-- FUNCTION testing

-- Test 1. Valid input (film_title only)
-- in the result a new film inserted with default language (Klingon)
-- and Klingon was inserted into public.language

SELECT * 
FROM public.new_movie('Operation Fortune');

-- checking if new film was really inserted:
SELECT 	
	f.film_id,
    f.title,
    l.name AS language_name,
    f.release_year,
    f.rental_duration,
    f.rental_rate,
    f.replacement_cost
FROM public.film f
LEFT JOIN public.language l
	ON l.language_id = f.language_id 
WHERE f.title = 'Operation Fortune';

-- the list of all languages:
SELECT DISTINCT 
	name
FROM public.language;

-- Test 2. Valid input (3 parameters)
-- in the result a new film inserted with default language (Klingon)
-- and new language (Klingon) was inserted into public.language

SELECT * 
FROM public.new_movie('The Covenant', 2026, 'English');

-- checking if new film was really inserted:
SELECT 	
	f.film_id,
    f.title,
    l.name AS language_name,
    f.release_year,
    f.rental_duration,
    f.rental_rate,
    f.replacement_cost
FROM public.film f
LEFT JOIN public.language l
	ON l.language_id = f.language_id 
WHERE f.release_year = 2026;


-- Test 3. Invalid input: existing movie
-- ERROR: Movie "The Gentlemen" already exists in public.film.

SELECT * 
FROM public.new_movie('The Gentlemen', 2026, 'English');


-- Test 4. Valid input: movie + language (without release_year)
-- release_year is inserted by default

SELECT *
FROM public.new_movie(
    p_title => 'Spirited Away',
    p_language_name => 'Japanese'
);



