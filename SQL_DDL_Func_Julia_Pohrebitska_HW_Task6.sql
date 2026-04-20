
-- ==============================
-- Task 6.2. FUNCTION 'rewards_report' - CORRECTION
-- ==============================
-- 1. Why does ‘rewards_report’ function return 0 rows? 
-- 2. Correct and recreate the function, so that it's able to return rows properly.
-- 3. What is tmpSQL variable for in ‘rewards_report’ function? 
-- 4. Can this function be recreated without EXECUTE statement and dynamic SQL? Why
-- 
-- Comments:
-- 1. The function returns 0 rows because it filters payments relative to CURRENT_DATE - 3 months,
--    while the dvdrental dataset contains historical data (2017M1-2017M6). 
-- As a result, the calculated date range does not match the historical payment dates in the table.
-- 
SELECT 
	MIN(payment_date),
	MAX(payment_date)
FROM public.payment p; 
--
--
-- 2. To fix it, the function should calculate the target month from the actual data in the payment table (2017)
--    instead of the current system date (2026).
-- 3. tmpSQL is used to store dynamically built SQL statements. In this function, it is used to create
--    and execute an INSERT statement for the temporary table of customers, and later a DROP TABLE statement.
-- 4. Yes, this function can be recreated without EXECUTE / tmpSQL and dynamic SQL, because all required tables,
--    conditions and parameters are known in advance (not dynamic).
--    In the original function, dynamic SQL was used to insert eligible customer IDs into the tmpSQL 
--    and then read from the tmpSQL to return the final customer rows. 
--    However, this extra step is not necessary here, because we can select the matching customers directly from the payment and customer tables. 
--    The query structure is fixed, so there is no need to build SQL dynamically or use EXECUTE. 
--    A static SQL query with RETURN QUERY is simpler, safer, and easier to read and maintain.


CREATE OR REPLACE FUNCTION public.rewards_report_upd(
    min_monthly_purchases integer,
    min_dollar_amount_purchased numeric
)
RETURNS SETOF customer
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    last_month_start date;
    last_month_end date;
BEGIN
    -- Validation
    IF min_monthly_purchases <= 0 THEN
        RAISE EXCEPTION 'Minimum monthly purchases parameter must be > 0';
    END IF;

    IF min_dollar_amount_purchased <= 0 THEN
        RAISE EXCEPTION 'Minimum monthly dollar amount purchased parameter must be > 0';
    END IF;

    -- START. Use the latest payment date in the table (2017M6), not CURRENT_DATE
    SELECT date_trunc('month', MAX(payment_date))::date
    INTO last_month_start
    FROM payment;

    -- END. Use another function 'last_day'
    last_month_end := public.last_day(last_month_start);

    RETURN QUERY
	SELECT c.*
    FROM customer c
    WHERE c.customer_id IN (
	    SELECT p.customer_id
	    FROM payment p
	    WHERE p.payment_date::date BETWEEN last_month_start AND last_month_end
	    GROUP BY 
	    	p.customer_id
	    HAVING COUNT(*) > min_monthly_purchases
	    	AND SUM(p.amount) > min_dollar_amount_purchased
	    );

    RETURN;
END
$function$;


COMMENT ON FUNCTION public.rewards_report_upd(integer, numeric) IS
'Returns full customer data for customers who meet the minimum monthly purchase-count (COUNT(p.payment_id))
and monthly revenue thresholds (SUM(p.amount)) in the latest month available in the payment table. 
Uses a static query instead of dynamic SQL.
The function filters last month payments relative to dvdrental dates (2017M1-2017M6) and not current date';


-- =============================
-- Function testing
-- users with > 39 purchases & > $200 revenue

SELECT *
FROM public.rewards_report_upd(39,200);

-- checking payments of the particular customer:

SELECT *
FROM public.payment p 
WHERE p.customer_id = 526
	AND payment_date >= '2017-06-01';



-- ==============================
-- Task 6.3. FUNCTION 'get_customer_balance' - CORRECTION
-- ==============================
-- Try to change function using the requirements from the function's comments.
--
-- Comments:
-- 1. In the whole we have to calculate 3 business rules:
-- 		1) RENTAL FEES FOR ALL PREVIOUS RENTALS (--> correct)
--   	2) 1 DOLLAR FOR EVERY DAY THE PREVIOUS RENTALS ARE OVERDUE (--> correction needed)
--      3) IF A FILM IS MORE THAN RENTAL_DURATION * 2 OVERDUE, CHARGE THE REPLACEMENT_COST (--> creation needed)
-- 		So, we have to correct the overdue rule (2) and the replacement_cost rule (3).
--
-- 2. In the corrected overdue logic & replacement_cost logic, overdue days are calculated up to effective_date,
--    not only up to return_date.
-- 	  To do this, the function uses LEAST(COALESCE(r.return_date, p_effective_date), p_effective_date),
--    so the calculation stops at the earlier of return_date or effective_date.
-- 4. This makes the balance effective as of p_effective_date,
--    including still-open rentals where return_date IS NULL.
-- 5. The corrected function also implements rule (3), which was missing from the original code at all:
--    if overdue days are greater than f.rental_duration * 2, the function adds f.replacement_cost.
-- 6. The final balance is calculated as:
--    v_rentfees + v_overfees + v_replacementfees - v_payments


CREATE OR REPLACE FUNCTION public.get_customer_balance_upd(
	p_customer_id integer, 
	p_effective_date timestamp with time ZONE
)
RETURNS numeric
LANGUAGE plpgsql
AS $function$
       --#OK, WE NEED TO CALCULATE THE CURRENT BALANCE GIVEN A CUSTOMER_ID AND A DATE
       --#THAT WE WANT THE BALANCE TO BE EFFECTIVE FOR. THE BALANCE IS:
       --#   1) RENTAL FEES FOR ALL PREVIOUS RENTALS
       --#   2) $1 FOR EVERY DAY THE PREVIOUS RENTALS ARE OVERDUE
       --#   3) IF A FILM IS MORE THAN RENTAL_DURATION * 2 OVERDUE, CHARGE THE REPLACEMENT_COST
       --#   4) SUBTRACT ALL PAYMENTS MADE BEFORE THE DATE SPECIFIED

DECLARE
    v_overfees NUMERIC(10,2);       		-- sum of overdue fees
    v_replacementfees NUMERIC(10,2);   	 	-- sum of replacement costs
    v_rentfees NUMERIC(10,2);       		-- sum of rental fees
    v_payments NUMERIC(10,2); 				-- sum of payments made before the effective date
											-- Main logic: v_rentfees + v_overfees + v_replacementfees - v_payments
BEGIN
    -- 1) rental fees for all rentals made on or before the effective date
	SELECT COALESCE(SUM(f.rental_rate), 0)
    INTO v_rentfees
    FROM public.rental r
    INNER JOIN public.inventory i
        ON i.inventory_id = r.inventory_id
    INNER JOIN public.film f
        ON f.film_id = i.film_id
    WHERE r.customer_id = p_customer_id
        AND r.rental_date <= p_effective_date;

    -- 2) $1 for every overdue day, calculated up to the effective_date (not to the return_date)
    SELECT COALESCE(SUM(
        CASE
            WHEN (
                LEAST(COALESCE(r.return_date, p_effective_date), p_effective_date)::date
                - r.rental_date::date
            ) > f.rental_duration
            AND (
                LEAST(COALESCE(r.return_date, p_effective_date), p_effective_date)::date
                - r.rental_date::date
            ) <= f.rental_duration * 2
            THEN (
                LEAST(COALESCE(r.return_date, p_effective_date), p_effective_date)::date
                - r.rental_date::date
            ) - f.rental_duration
            ELSE 0
        END
    ), 0)
    INTO v_overfees
    FROM public.rental r
    INNER JOIN public.inventory i
        ON i.inventory_id = r.inventory_id
    INNER JOIN public.film f
        ON f.film_id = i.film_id
    WHERE r.customer_id = p_customer_id
        AND r.rental_date <= p_effective_date;

    -- 3) if a film is more than rental_duration * 2 overdue, charge replacement_cost
	-- calculated up to the effective_date (not to the return_date)
    SELECT COALESCE(SUM(
        CASE
            WHEN (
                LEAST(COALESCE(r.return_date, p_effective_date), p_effective_date)::date
                - r.rental_date::date
            ) > f.rental_duration * 2
            THEN f.replacement_cost
            ELSE 0
        END
    ), 0)
    INTO v_replacementfees
    FROM public.rental r
    INNER JOIN public.inventory i
        ON i.inventory_id = r.inventory_id
    INNER JOIN public.film f
        ON f.film_id = i.film_id
    WHERE r.customer_id = p_customer_id
    	AND r.rental_date <= p_effective_date;

    -- 4) calculate all payments made on or before the effective date
    SELECT COALESCE(SUM(p.amount), 0)
    INTO v_payments
    FROM public.payment p
    WHERE p.customer_id = p_customer_id
    	AND p.payment_date <= p_effective_date;

	-- 5) calculate the customer's balance
    RETURN v_rentfees + v_overfees + v_replacementfees - v_payments;
END
$function$
;

COMMENT ON FUNCTION public.get_customer_balance_upd(integer, timestamp with time zone) IS
'Returns the customer balance as of effective_date. 
The function calculates rental fees, overdue fees ($1 for every overdue day), 
replacement costs (for rentals overdue more than rental_duration * 2), 
and subtracts all payments made on or before effective_date.
Positive balance means the customer owes money.
Negative balance means overpaid / credit balance';

-- =============================
-- Function testing
-- positive balance = the customer owes money
-- negative balance = overpaid / credit balance

SELECT *
FROM public.get_customer_balance_upd(526,'2026-04-13 00:00:00+03'::timestamptz);

-- the old version of this function
SELECT *
FROM public.get_customer_balance(526,'2026-04-13 00:00:00+03'::timestamptz);

