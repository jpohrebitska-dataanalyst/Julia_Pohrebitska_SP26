-- Part 1: Write SQL queries to retrieve the following data. 

-- Task 1.1:
-- The marketing team needs a list of animation movies between 2017 and 2019 
-- to promote family-friendly content in an upcoming season in stores. 
-- Show all animation movies released during this period with rate more than 1, 
-- sorted alphabetically

-- Assumptions:
-- under 'rate more than 1' I interpret rate as rental_rate, meaning the rental price of the film.
-- 'more than 1' is interpreted strictly as > 1, not >= 1
-- I assume that the category value may potentially appear in different letter cases, 
-- so I normalize it with LOWER(c.name) = 'animation' to make the filter case-INSENSITIVE
-- I assume that the marketing dept needs these 5 columns in the result

-- Conclusions:
-- I would choose the JOIN solution in production in this case because 
-- it is the most direct approach here. It is also the easiest to read and explain.
-- I do not see much value in using a CTE here, because there is no real need to separate 
-- animation films into a separate step. The required data is already easy to access through joins.
-- The same mostly applies to the subquery approach. In this case, both CTE and subquery feel a bit like overengineering, 
-- although they could be more useful if the task became more complex later.

-- var.1 JOIN
SELECT 
	f.film_id, 
	f.title AS film_title, 
	f.rental_rate, 
	f.release_year, 
	c.name AS category_name
FROM public.film f
INNER JOIN public.film_category fc ON f.film_id = fc.film_id 
INNER JOIN public.category c ON c.category_id = fc.category_id
WHERE f.release_year BETWEEN 2017 AND 2019
	AND LOWER(c.name) = 'animation'
	AND f.rental_rate > 1
ORDER BY f.title ASC;


-- var.2 CTE
WITH animation_films AS(
	SELECT
		fc.film_id,
		c.name AS category_name
	FROM public.film_category fc
	INNER JOIN public.category c ON c.category_id = fc.category_id 
	WHERE LOWER(c.name) = 'animation'
	)
SELECT 
	f.film_id, 
	f.title AS film_title, 
	f.rental_rate, 
	f.release_year, 
	af.category_name
FROM public.film f
INNER JOIN animation_films af ON f.film_id = af.film_id 
WHERE f.release_year BETWEEN 2017 AND 2019
	AND f.rental_rate > 1
ORDER BY f.title ASC;


-- var.3 SUBQUERY
SELECT 
	f.film_id, 
	f.title AS film_title, 
	f.rental_rate, 
	f.release_year,
	c.name AS category_name
FROM public.film f
INNER JOIN public.film_category fc ON fc.film_id = f.film_id
INNER JOIN public.category c ON c.category_id = fc.category_id
WHERE f.film_id IN (
	SELECT
		fc.film_id
	FROM public.film_category fc
	INNER JOIN public.category c ON c.category_id = fc.category_id 
	WHERE LOWER(c.name) = 'animation'
	)
	AND f.release_year BETWEEN 2017 AND 2019
	AND f.rental_rate > 1
ORDER BY f.title ASC;


-- Task 1.2:
--The finance department requires a report on store performance to assess profitability 
--and plan resource allocation for stores after March 2017. 
--Calculate the revenue earned by each rental store after March 2017 (since April) 
--(include columns: address and address2 – as one COLUMN, revenue)

-- Assumptions:
-- the finance department requires a report with store_id, address and revenue
--'After March 2017 (since April)' means from 2017-04-01 inclusive
-- store revenue is determined through the relationship inventory -> rental -> payment
-- address2 may be NULL

-- Conclusions:
-- I would choose the JOIN solution in production in this case because
-- it is the most direct and natural way to calculate store revenue
-- through related transactional tables.
-- It is also the easiest to read, explain, and validate step by step.
-- I do not see much value in using a CTE here, because the logic is still simple
-- and does not require splitting the query into several clearly separate stages.
-- The subquery approach also works, but in this case it feels less straightforward
-- than the JOIN solution and gives no clear advantage.
-- CTE and subquery solutions could become more useful later
-- if the reporting logic becomes more complex or requires additional intermediate steps.

-- var.1 JOIN
SELECT 
	s.store_id, 
	CONCAT (a.address, COALESCE(', ' || a.address2, '')) AS full_address,
	SUM(p.amount) AS store_revenue
FROM public.store s
INNER JOIN public.address a 
	ON a.address_id = s.address_id  
INNER JOIN public.inventory i 
	ON i.store_id = s.store_id 
INNER JOIN public.rental r 
	ON r.inventory_id = i.inventory_id 
INNER JOIN public.payment p 
	ON p.rental_id = r.rental_id 
WHERE p.payment_date >= '2017-04-01'
GROUP BY 
	s.store_id, 
	a.address, 
	a.address2
ORDER BY store_revenue DESC;


-- var.2 CTE
WITH store_payments AS(
-- this CTE retrieves list of payments for each store
	SELECT i.store_id, 
			p.amount
	FROM public.inventory i
	INNER JOIN rental r 
		ON r.inventory_id = i.inventory_id 
	INNER JOIN public.payment p
		ON p.rental_id = r.rental_id
	WHERE p.payment_date >= '2017-04-01'
)
SELECT 	
	s.store_id, 
	CONCAT (a.address, COALESCE(', ' || a.address2, '')) AS full_address,
	SUM(sp.amount) AS store_revenue
FROM public.store s	
INNER JOIN public.address a 
	ON a.address_id = s.address_id  
INNER JOIN store_payments sp
	ON sp.store_id = s.store_id 
GROUP BY 
	s.store_id, 
	a.address, 
	a.address2
ORDER BY store_revenue DESC;


-- var.3 SUBQUERY
SELECT 	
	s.store_id, 
	CONCAT (a.address, COALESCE(', ' || a.address2, '')) AS full_address,
	sp.store_revenue AS store_revenue
FROM public.store s	
INNER JOIN public.address a 
	ON a.address_id = s.address_id  
INNER JOIN
	(
	-- this subquery calculates total revenue for each store
	SELECT i.store_id, 
			SUM(p.amount) AS store_revenue
	FROM public.inventory i
	INNER JOIN rental r 
		ON r.inventory_id = i.inventory_id 
	INNER JOIN public.payment p
		ON p.rental_id = r.rental_id
	WHERE p.payment_date >= '2017-04-01'
	GROUP BY i.store_id
	) sp
	ON sp.store_id = s.store_id
ORDER BY store_revenue DESC;


-- Task 1.3:
-- the marketing dept in our stores aims to identify the most successful actors since 2015 
-- to boost customer interest in their films.
-- Show top-5 actors by number of movies (released since 2015)
-- they took part in (columns: first_name, last_name, number_of_movies, sorted by number_of_movies in descending order)

-- Assumptions:
-- we understand 'successful actors' as actors who appeared in the highest number of films
-- (not 'successful actors' by rentals or revenue)
-- 'Released since 2015" means films with release_year starting from 2015

-- Conclusions:
-- JOIN: it is the most direct and readable solution here
-- the disadvantage is that the query may become harder to read if more joins and conditions are added later
-- CTE: the main advantage is that it separates the logic into clear steps
-- the disadvantage is that for this task it feels a bit more verbose than necessary
-- Subquery: allows the filtering logic to be isolated from the final aggregation
-- the disadvantage is that it is less straightforward to read
-- I would choose the JOIN solution in production because it is the simplest option for this task

-- var.1 JOIN
SELECT 
	a.first_name, 
	a.last_name, 
	COUNT(f.film_id) AS number_of_movies
FROM public.actor a
INNER JOIN public.film_actor fa 
	ON fa.actor_id = a.actor_id 
INNER JOIN public.film f
	ON f.film_id = fa.film_id 
WHERE f.release_year >= 2015
GROUP BY 
	a.first_name, 
	a.last_name
ORDER BY number_of_movies DESC
LIMIT 5;


-- var.2 CTE
WITH actors_movies AS (
	SELECT 
		a.actor_id,
		a.first_name,
		a.last_name,
		f.film_id
	FROM public.actor a
	INNER JOIN public.film_actor fa
		ON fa.actor_id = a.actor_id 
	INNER JOIN public.film f
		ON f.film_id = fa.film_id 
	WHERE f.release_year >= 2015
	)
SELECT 
	am.first_name,
	am.last_name,
	COUNT(am.film_id) AS number_of_movies
FROM actors_movies am
GROUP BY 
	am.actor_id, -- theoretically 2 actors may have the same name and surname
	am.first_name,
	am.last_name
ORDER BY
	number_of_movies DESC
LIMIT 5;


-- var.3 SUBQUERY
SELECT 
	am.first_name,
	am.last_name,
	COUNT(am.film_id) AS number_of_movies
FROM 
	(
	SELECT 
		a.actor_id,
		a.first_name,
		a.last_name,
		f.film_id
	FROM public.actor a
	INNER JOIN public.film_actor fa
		ON fa.actor_id = a.actor_id 
	INNER JOIN public.film f
		ON f.film_id = fa.film_id 
	WHERE f.release_year >= 2015
) am
GROUP BY 
	am.actor_id,
	am.first_name,
	am.last_name
ORDER BY
	number_of_movies DESC
LIMIT 5;


-- Task 1.4:
-- The marketing team needs to track the production trends of Drama, Travel, 
-- and Documentary films to inform genre-specific marketing strategies. 
-- Show number of Drama, Travel, Documentary per year 
-- (include columns: release_year, number_of_drama_movies, number_of_travel_movies,
-- number_of_documentary_movies), sorted by release year in descending order. 
-- Dealing with NULL values is encouraged)

-- Assumptions:
-- if a category has no films in a given year, 0 is returned instead of NULL

-- Conclusions:
-- SUM(CASE WHEN ... THEN 1 ELSE 0 END) is used instead of COUNT(CASE WHEN ...),
-- because SUM correctly adds only matching rows, while COUNT with ELSE 0
-- would count both 1 and 0 values since both are non-NULL.

-- JOIN: it is the most direct and readable solution here
-- the disadvantage is that the query may become harder to read if more joins or conditions are added later
-- CTE: the main advantage is that it separates the logic into clear steps
-- the disadvantage is that for this task it feels slightly more verbose than necessary
-- Subquery: the main advantage is that it isolates the intermediate dataset before aggregation
-- the disadvantage: it is less straightforward to read 	
-- I would choose the JOIN solution in production because it is the simplest and most natural option.

-- var.1 JOIN
SELECT 
	f.release_year,
	SUM(CASE WHEN c.name = 'Drama' THEN 1 ELSE 0 END) AS number_of_drama_movies,
	SUM(CASE WHEN c.name = 'Travel' THEN 1 ELSE 0 END) AS number_of_travel_movies,
	SUM(CASE WHEN c.name = 'Documentary' THEN 1 ELSE 0 END) AS number_of_documentary_movies
FROM public.category c
INNER JOIN public.film_category fc
	ON fc.category_id = c.category_id
INNER JOIN public.film f
	ON f.film_id = fc.film_id	
WHERE c.name IN ('Drama', 'Travel', 'Documentary') -- for optimization purpose (slower without WHERE)
GROUP BY
	f.release_year
ORDER BY 
	f.release_year DESC;


-- var.2 CTE
WITH films_genres AS(
	SELECT 
		f.title,
		f.release_year,
		c.name
	FROM film f
	INNER JOIN film_category fc
		ON fc.film_id = f.film_id 
	INNER JOIN category c
		ON c.category_id = fc.category_id 
	WHERE c.name IN ('Drama', 'Travel', 'Documentary')
)
SELECT 
	fg.release_year,
	SUM(CASE WHEN fg.name = 'Drama' THEN 1 ELSE 0 END) AS number_of_drama_movies,
	SUM(CASE WHEN fg.name = 'Travel' THEN 1 ELSE 0 END) AS number_of_travel_movies,
	SUM(CASE WHEN fg.name = 'Documentary' THEN 1 ELSE 0 END) AS number_of_documentary_movies
FROM films_genres fg
GROUP BY 
	fg.release_year 
ORDER BY
	fg.release_year DESC;


-- var.3 SUBQUERY
SELECT 
	fg.release_year,
	SUM(CASE WHEN fg.name = 'Drama' THEN 1 ELSE 0 END) AS number_of_drama_movies,
	SUM(CASE WHEN fg.name = 'Travel' THEN 1 ELSE 0 END) AS number_of_travel_movies,
	SUM(CASE WHEN fg.name = 'Documentary' THEN 1 ELSE 0 END) AS number_of_documentary_movies
FROM (
	SELECT 
		f.title,
		f.release_year,
		c.name
	FROM film f
	INNER JOIN film_category fc
		ON fc.film_id = f.film_id 
	INNER JOIN category c
		ON c.category_id = fc.category_id 
	WHERE c.name IN ('Drama', 'Travel', 'Documentary')
) fg
GROUP BY 
	fg.release_year 
ORDER BY
	fg.release_year DESC;


-- Part 2: Solve the following problems using SQL

-- Task 2.1. The HR department aims to reward top-performing employees in 2017
-- with bonuses to recognize their contribution to stores revenue.
-- Show which three employees generated the most revenue in 2017? 

-- Assumptions: 
-- staff could work in several stores in a year, please indicate which store the staff worked in (the last one);
-- if staff processed the payment then he works in the same store; 
-- take into account only payment_date
-- for the last payment_date we may have different payment_id (so we have to add 1 more CTE, for example)
-- the last store_id of the employee we retrieve from 'inventory' table, were the last copy of the film was sold

-- Conclusions:
-- For me, the clearest solution was the CTE approach, where the logic is split into several steps:
-- first revenue, then last payment_date, and then last payment_id.
-- The DISTINCT ON option is also very elegant, because it makes the query shorter and easier to read,
-- but it is specific to PostgreSQL and not as universal as the CTE solution.
-- A pure join-based solution looks much more complicated here, because in practice we still need
-- separate intermediate calculations to identify the latest payment and the related store.
-- The same logic can also be written with nested subqueries instead of CTEs,
-- but with several levels of nesting the query becomes harder to read.
-- In my opinion, the CTE solution gives the best balance between readability and logic.


-- var.1 CTE with PostgreSQL specific logic - DISTINCT ON... ORDER BY
WITH staff_revenue AS(
	SELECT 
	-- revenue per each employee and last payment
		p.staff_id,
		SUM(p.amount) AS total_revenue
	FROM payment p
	WHERE p.payment_date >= '2017-01-01' 
		AND p.payment_date < '2018-01-01'
	GROUP BY 
		p.staff_id
),
last_store_by_staff AS(	
	SELECT DISTINCT ON (p.staff_id)
	-- per each staff_id select 1 row with the latest payment (order by payment_date DESC)
		p.staff_id,
		i.store_id,
		p.payment_date
	FROM public.payment p
		INNER JOIN public.rental r 
			ON r.rental_id = p.rental_id 
		INNER JOIN public.inventory i 
			ON i.inventory_id = r.inventory_id  
	WHERE p.payment_date >= '2017-01-01' 
		AND p.payment_date < '2018-01-01'
	ORDER BY p.staff_id, p.payment_date DESC, p.payment_id DESC
)		
SELECT
	s.first_name || ' ' || s.last_name AS employee_name,
    ls.store_id AS last_working_store,
    sr.total_revenue
FROM staff_revenue sr
INNER JOIN staff s ON sr.staff_id = s.staff_id
INNER JOIN last_store_by_staff ls ON s.staff_id = ls.staff_id
ORDER BY sr.total_revenue DESC
LIMIT 3;	


-- var.2. CTE without PostgreSQL specific logic
WITH staff_revenue AS (
    SELECT
        p.staff_id,
        SUM(p.amount) AS total_revenue
    FROM payment p
    WHERE p.payment_date >= '2017-01-01'
    	AND p.payment_date < '2018-01-01'
    GROUP BY p.staff_id
),
last_payment_date_by_staff AS (
    SELECT
        p.staff_id,
        MAX(p.payment_date) AS last_payment_date
    FROM payment p
    WHERE p.payment_date >= '2017-01-01'
      AND p.payment_date < '2018-01-01'
    GROUP BY p.staff_id
),
last_payment_id_by_staff AS (
-- for the last payment_date we may have different payment_id
    SELECT
        p.staff_id,
        MAX(p.payment_id) AS last_payment_id
    FROM payment p
    INNER JOIN last_payment_date_by_staff ldate
        ON p.staff_id = ldate.staff_id
    	AND p.payment_date = ldate.last_payment_date
    WHERE p.payment_date >= '2017-01-01'
    	AND p.payment_date < '2018-01-01'
    GROUP BY p.staff_id
),
last_store_by_staff AS (
-- the last store by the latest payment_id by employee
    SELECT
        p.staff_id,
        i.store_id
    FROM payment p
    INNER JOIN last_payment_id_by_staff lid
        ON p.staff_id = lid.staff_id
    	AND p.payment_id = lid.last_payment_id
    INNER JOIN rental r
        ON r.rental_id = p.rental_id
    INNER JOIN inventory i
        ON i.inventory_id = r.inventory_id
)
SELECT
    s.first_name || ' ' || s.last_name AS employee_name,
    lstore.store_id AS last_working_store,
    sr.total_revenue
FROM staff_revenue sr
INNER JOIN staff s
    ON s.staff_id = sr.staff_id
INNER JOIN last_store_by_staff lstore
    ON lstore.staff_id = sr.staff_id
ORDER BY sr.total_revenue DESC
LIMIT 3;


-- Task 2.2
-- The management team wants to identify the most popular movies and their target audience age groups
-- to optimize marketing efforts.
-- Show which 5 movies were rented more than others (number of rentals),
-- and what is the expected age of the audience for these movies.
-- To determine expected age, use the Motion Picture Association film rating system.

-- Assumptions:
-- the expected age of the audience is shown in the rating_description
-- popularity is measured by COUNT(r.rental_id)
-- INNER JOIN is used because only movies that were actually rented should appear in the result
-- if several movies have the same number of rentals, we shoud include them in the final result
-- and show Top 5 including ties 


-- Conclusions:
-- JOIN: it is the most direct and readable solution for this task.
-- The disadvantage is that the query can become harder to maintain if more business logic is added later.
-- CTE: the main advantage is that it separates rental aggregation from the final step
-- The disadvantage is that for this task it is slightly more verbose than necessary.
-- SUBQUERY: the main advantage is that it keeps the intermediate aggregation isolated inside one nested block
-- The disadvantage is that it is a bit less straightforward to read.
-- I would choose the JOIN solution in production because it is the simplest and most natural option for this task
-- If the logic becomes more complex later, for example with additional filters or ranking rules,
-- the CTE solution may become more convenient.

-- I used FETCH FIRST 5 ROWS WITH TIES because ties should not be removed artificially
-- by film_id or alphabetical order. On my opinion, excluding films with the same rental count
-- would make the result less accurate and could provide misleading information for the marketing department.


-- var.1 JOIN
SELECT 
	f.film_id,
	f.title,
	f.rental_rate,
	f.rating AS rating_code,
	CASE 
        WHEN f.rating = 'G' THEN 'All ages'
        WHEN f.rating = 'PG' THEN 'Parental guidance suggested'
        WHEN f.rating = 'PG-13' THEN '13+ (parent required to be cautious for under 13)'
        WHEN f.rating = 'R' THEN '17+ (parent required for under 17)'
        WHEN f.rating = 'NC-17' THEN '17+ only'
	  ELSE 'Unknown Rating'
	END AS rating_description,
	COUNT(r.rental_id) AS number_of_rentals
FROM film f
INNER JOIN inventory i 
	ON i.film_id = f.film_id 
INNER JOIN rental r 
	ON r.inventory_id = i.inventory_id 
GROUP BY
	f.film_id,
	f.title,
	f.rental_rate,
	f.rating
ORDER BY
	number_of_rentals DESC,
	f.rental_rate DESC
FETCH FIRST 5 ROWS WITH TIES;

-- var.2 CTE
WITH movie_rentals AS(
-- calculating number of rentals for all movies
	SELECT 
		f.film_id,
		f.title,
		f.rating AS rating_code,
		COUNT(r.rental_id) AS number_of_rentals
	FROM film f
	INNER JOIN inventory i 
		ON i.film_id = f.film_id 
	INNER JOIN rental r 
		ON r.inventory_id = i.inventory_id 
	GROUP BY
		f.film_id,
		f.title,
		f.rating
)
SELECT 
	mr.film_id,
	mr.title,
	mr.rating_code,
-- adding rating description with years
	CASE 
        WHEN mr.rating_code = 'G' THEN 'All ages'
        WHEN mr.rating_code = 'PG' THEN 'Parental guidance suggested'
        WHEN mr.rating_code = 'PG-13' THEN '13+ (parent required to be cautious for under 13)'
        WHEN mr.rating_code = 'R' THEN '17+ (parent required for under 17)'
        WHEN mr.rating_code = 'NC-17' THEN '17+ only'
	  ELSE 'Unknown Rating'
	END AS rating_description,
	mr.number_of_rentals
FROM movie_rentals mr
ORDER BY
	mr.number_of_rentals DESC,
	mr.title ASC
FETCH FIRST 5 ROWS WITH TIES;

-- var.3 SUBQUERY
SELECT 
	mr.film_id,
	mr.title,
	mr.rating_code,
-- adding rating description with years
	CASE 
        WHEN mr.rating_code = 'G' THEN 'All ages'
        WHEN mr.rating_code = 'PG' THEN 'Parental guidance suggested'
        WHEN mr.rating_code = 'PG-13' THEN '13+ (parent required to be cautious for under 13)'
        WHEN mr.rating_code = 'R' THEN '17+ (parent required for under 17)'
        WHEN mr.rating_code = 'NC-17' THEN '17+ only'
	  ELSE 'Unknown Rating'
	END AS rating_description,
	mr.number_of_rentals
FROM (
	-- calculating number of rentals for all movies
	SELECT 
		f.film_id,
		f.title,
		f.rating AS rating_code,
		COUNT(r.rental_id) AS number_of_rentals
	FROM film f
	INNER JOIN inventory i 
		ON i.film_id = f.film_id 
	INNER JOIN rental r 
		ON r.inventory_id = i.inventory_id 
	GROUP BY
		f.film_id,
		f.title,
		f.rating
) mr
ORDER BY
	mr.number_of_rentals DESC,
	mr.title ASC
FETCH FIRST 5 ROWS WITH TIES;


-- Part 3. Which actors/actresses didn't act for a longer period of time than the others? 

-- The stores’ marketing team wants to analyze actors' inactivity periods to select those with notable career
-- breaks for targeted promotional campaigns, highlighting their comebacks or consistent appearances to 
-- engage customers with nostalgic or reliable film stars.
-- Here are a few options (provide solutions for each one)

-- Assumptions:
-- Inactivity - is the period between current year and the year of the last release.
-- Gap - is the break between two releases.
-- We assume that the marketing team needs at least the list of 3 actors for their promotional campaigns.

-- Conclusions:
-- For V1 (inactivity period), all three approaches are possible: JOIN, CTE, and SUBQUERY,
-- because the task is based on one main aggregation step - finding the latest release year per actor.
-- The JOIN version is the shortest one and works well here.
-- The CTE version makes the logic a little bit more clear, because it separates the step of finding the last film
-- release year from the final calculation.
-- The SUBQUERY version follows the same logic as the CTE solution, but in my opinion it is slightly less readable.
-- 
-- For V2 (sequential career gaps), I chose the CTE + correlation subquery approach because it has step-by-step logic:
-- first we need to identify the next release year for each actor’s film, and then calculate the maximum gap.
-- A simple JOIN or SUBQUERY solution for V2 would probably be much harder to read and explain.
-- Window functions (LAG) will be probably the most appropriate solution for V2 task.


-- V1: Inactivity - the gap between the latest release_year and current year per each actor

-- var.1 JOIN
SELECT
	a.actor_id,
	a.first_name,
	a.last_name,
	MAX(f.release_year) AS last_film_release_year,
	EXTRACT(YEAR FROM CURRENT_DATE) - MAX(f.release_year) AS actor_inactive_period
FROM public.actor a
INNER JOIN film_actor fa
	ON fa.actor_id = a.actor_id
INNER JOIN film f 
	ON f.film_id  = fa.film_id 
GROUP BY 
	a.actor_id,
	a.first_name,
	a.last_name
ORDER BY 
	actor_inactive_period DESC
FETCH FIRST 3 ROWS WITH TIES;

-- var.2 CTE
WITH actors_last_film AS(
-- showing information about the last release year for each actor
	SELECT
		a.actor_id,
		a.first_name,
		a.last_name,
		MAX(f.release_year) AS last_film_release_year
	FROM public.actor a
	INNER JOIN film_actor fa
		ON fa.actor_id = a.actor_id
	INNER JOIN film f 
		ON f.film_id  = fa.film_id 
	GROUP BY 
		a.actor_id,
		a.first_name,
		a.last_name
)
SELECT 
		actor_id,
		first_name,
		last_name,
		last_film_release_year,
		EXTRACT(YEAR FROM CURRENT_DATE) - last_film_release_year AS actor_inactive_period
FROM actors_last_film
ORDER BY 
	actor_inactive_period DESC
FETCH FIRST 3 ROWS WITH TIES;

-- var.3 SUBQUERY
SELECT 
		actor_last_film.actor_id,
		actor_last_film.first_name,
		actor_last_film.last_name,
		actor_last_film.last_film_release_year,
		EXTRACT(YEAR FROM CURRENT_DATE) - actor_last_film.last_film_release_year AS actor_inactive_period
FROM (
-- showing information about the last release year for each actor
	SELECT
		a.actor_id,
		a.first_name,
		a.last_name,
		MAX(f.release_year) AS last_film_release_year
	FROM public.actor a
	INNER JOIN film_actor fa
		ON fa.actor_id = a.actor_id
	INNER JOIN film f 
		ON f.film_id  = fa.film_id 
	GROUP BY 
		a.actor_id,
		a.first_name,
		a.last_name
) AS actor_last_film
ORDER BY 
	actor_inactive_period DESC
FETCH FIRST 3 ROWS WITH TIES;


-- V2: GAPS between sequential films per each actor 
-- var.1 CTE
WITH actor_film_steps AS (
    -- this block forms the 'steps' of a career: for each film we look for the year of the next film
    SELECT 
        fa.actor_id,
        f.release_year AS current_film_year,
        (
        --for each year we generate the next release year
            SELECT MIN(next_f.release_year)
            FROM public.film next_f
            INNER JOIN public.film_actor next_fa 
            	ON next_f.film_id = next_fa.film_id
            -- we are looking the same actor from the outer query
            WHERE next_fa.actor_id = fa.actor_id 
            -- looking only for releases strictly after the current one
            	AND next_f.release_year > f.release_year
        ) AS next_film_year
    FROM public.film_actor fa
    INNER JOIN public.film f 
        ON fa.film_id = f.film_id
    ORDER BY 
	    fa.actor_id,
	    current_film_year
)
SELECT 
    a.actor_id,
    a.first_name,
    a.last_name,
    MAX(steps.next_film_year - steps.current_film_year) AS max_career_gap
FROM public.actor a
INNER JOIN actor_film_steps steps 
    ON a.actor_id = steps.actor_id
-- excluding the last film in the career to exclude NULLs
WHERE steps.next_film_year IS NOT NULL
GROUP BY 
    a.actor_id, 
    a.first_name, 
    a.last_name
ORDER BY 
    max_career_gap DESC, 
    a.last_name ASC
FETCH FIRST 3 ROWS WITH TIES;


