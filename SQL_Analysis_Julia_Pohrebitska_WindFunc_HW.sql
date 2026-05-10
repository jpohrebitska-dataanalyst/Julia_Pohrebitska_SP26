--===========================================
-- Task 1
--===========================================
-- Create a query to produce a sales report highlighting the top customers 
-- with the highest sales across different sales channels. 
-- This report should list the top-5 customers for each channel. 
-- Additionally, calculate a key performance indicator (KPI) called 'sales_percentage',
-- which represents the percentage of a customer's sales relative to the total sales within their respective channel.

-- Please format the columns as follows:
-- Display the total sales amount with two decimal places
-- Display the sales percentage with four decimal places and include the percent sign (%) at the end
-- Display the result for each channel in descending order of sales

WITH total_sales AS(
	SELECT
		ch.channel_desc,
		c.cust_last_name,
		c.cust_first_name,
		SUM(s.amount_sold) AS amount_sold
	FROM sh.sales s
	INNER JOIN sh.customers c
		ON c.cust_id = s.cust_id 
	INNER JOIN sh.channels ch
		ON ch.channel_id = s.channel_id
	GROUP BY 
		ch.channel_desc,
		c.cust_last_name,
		c.cust_first_name
	),
ranked_sales AS(
	SELECT
		channel_desc,
		cust_last_name, 
		cust_first_name,
		amount_sold,
		ROW_NUMBER() OVER (PARTITION BY channel_desc ORDER BY amount_sold DESC) AS rn,
		amount_sold*100/SUM(amount_sold) OVER (PARTITION BY channel_desc) AS sales_percentage
	FROM total_sales
)
SELECT 	
	channel_desc,
	cust_last_name, 
	cust_first_name,
	TO_CHAR(amount_sold, 'FM99999990.00') AS amount_sold,						-- text format
	TO_CHAR(sales_percentage, 'FM99999990.0000') || '%' AS sales_percentage		-- text format
FROM ranked_sales
WHERE rn <= 5
ORDER BY 
	channel_desc,
	ranked_sales.amount_sold DESC;								-- sorting by number, not amount_sold as TEXT from the last SELECT 


--===========================================
-- Task 2
--===========================================
-- Create a query to retrieve data for a report that displays the total sales 
-- for all products in the Photo category in the Asian region for the year 2000. 
-- Calculate the overall report total and name it 'YEAR_SUM'
	
-- Display the sales amount with 2 decimal places
-- Display the result in descending order of 'YEAR_SUM'
-- For this report, consider exploring the use of the crosstab function. 

-- Comments:
-- 1) it seems like this task can be done with the help of CASE WHEN & without crosstab.
-- I use TO_CHAR also to display values as it was asked in the task, but we could also leave as it was.
-- 2) in the part 2 below I also wrote a crosstab solution.
	
--===========================================
-- Part 1. Using CASE WHEN
--===========================================

WITH main_calc AS(
	SELECT
		p.prod_name AS product_name,
		SUM(CASE WHEN t.calendar_quarter_number = 1 THEN s.amount_sold ELSE 0 END) AS q1,
		SUM(CASE WHEN t.calendar_quarter_number = 2 THEN s.amount_sold ELSE 0 END) AS q2,
		SUM(CASE WHEN t.calendar_quarter_number = 3 THEN s.amount_sold ELSE 0 END) AS q3,
		SUM(CASE WHEN t.calendar_quarter_number = 4 THEN s.amount_sold ELSE 0 END) AS q4,
		SUM(s.amount_sold) AS year_sum
	FROM sh.products p
	INNER JOIN sh.sales s
		ON s.prod_id = p.prod_id 
	INNER JOIN sh.times t
		ON t.time_id = s.time_id 
	INNER JOIN sh.customers c 
		ON c.cust_id = s.cust_id 
	INNER JOIN sh.countries co
		ON co.country_id = c.country_id
	WHERE t.calendar_year = 2000
		AND p.prod_category ILIKE 'photo'
		AND co.country_region ILIKE 'asia'
	GROUP BY 
		p.prod_name
	ORDER BY 
		year_sum DESC
)
SELECT 
	product_name,
	TO_CHAR(q1, 'FM999999990.00') AS q1,
	TO_CHAR(q2, 'FM999999990.00') AS q2,
	TO_CHAR(q3, 'FM999999990.00') AS q3,
	TO_CHAR(q4, 'FM999999990.00') AS q4,
	TO_CHAR(year_sum, 'FM999999990.00') AS year_sum
FROM main_calc;


--===========================================
-- Part 2. Using crosstab
--===========================================

CREATE EXTENSION IF NOT EXISTS tablefunc;

WITH quarter_sales AS(
	SELECT *
	FROM crosstab(
		'
		SELECT
			p.prod_name AS product_name,						-- row_name
			t.calendar_quarter_number,							-- category
			SUM(s.amount_sold) AS year_sum						-- value
		FROM sh.products p
		INNER JOIN sh.sales s
			ON s.prod_id = p.prod_id 
		INNER JOIN sh.times t
			ON t.time_id = s.time_id 
		INNER JOIN sh.customers c 
			ON c.cust_id = s.cust_id 
		INNER JOIN sh.countries co
			ON co.country_id = c.country_id
		WHERE t.calendar_year = 2000
			AND p.prod_category ILIKE ''photo''
			AND co.country_region ILIKE ''asia''
		GROUP BY 
			p.prod_name,
			t.calendar_quarter_number
		ORDER BY 
			p.prod_name,
			t.calendar_quarter_number
		'
		,
		'
		SELECT 1
		UNION ALL SELECT 2
		UNION ALL SELECT 3
		UNION ALL SELECT 4
		'
		) AS ct (
		product_name TEXT,
		q1 NUMERIC,
		q2 NUMERIC,
		q3 NUMERIC,
		q4 NUMERIC
		)
),
final_calc AS(
	SELECT 		
		product_name,
		COALESCE(q1,0) AS q1,
		COALESCE(q2,0) AS q2,
		COALESCE(q3,0) AS q3,
		COALESCE(q4,0) AS q4,
		COALESCE(q1,0) + COALESCE(q2,0) + COALESCE(q3,0) + COALESCE(q4,0) AS year_sum
	FROM quarter_sales
	ORDER BY year_sum DESC
)
SELECT 	
	product_name,
	TO_CHAR(q1, 'FM999999990.00') AS q1,
	TO_CHAR(q2, 'FM999999990.00') AS q2,
	TO_CHAR(q3, 'FM999999990.00') AS q3,
	TO_CHAR(q4, 'FM999999990.00') AS q4,
	TO_CHAR(year_sum, 'FM999999990.00') AS year_sum
FROM final_calc;


--===========================================
-- Task 3
--===========================================
-- Create a query to generate a sales report for customers 
-- ranked in the top 300 based on total sales in the years 1998, 1999, and 2001. 
-- The report should be categorized based on sales channels, and separate calculations should be performed for each channel.

-- Retrieve customers who ranked among the top 300 in sales for the years 1998, 1999, and 2001
-- Categorize the customers based on their sales channels
-- Perform separate calculations for each sales channel
-- Include in the report only purchases made on the channel specified
-- Format the column so that total sales are displayed with two decimal places

WITH sales_by_year AS (
	SELECT
		ch.channel_desc,
		t.calendar_year,
		c.cust_id,
		c.cust_last_name,
		c.cust_first_name,
		SUM(s.amount_sold) AS amount_sold
		FROM sh.sales s
		INNER JOIN sh.customers c 
			ON c.cust_id = s.cust_id 
		INNER JOIN sh.channels ch
			ON ch.channel_id = s.channel_id
		INNER JOIN sh.times t
			ON t.time_id = s.time_id 
		WHERE t.calendar_year IN (1998, 1999, 2001)
		GROUP BY 
			ch.channel_desc,
			t.calendar_year,
			c.cust_id,
			c.cust_last_name,
			c.cust_first_name
),
ranked_sales AS(
	SELECT
		channel_desc,
		calendar_year,
		cust_id,
		cust_last_name,
		cust_first_name,
		amount_sold,
		ROW_NUMBER() OVER (PARTITION BY channel_desc, calendar_year ORDER BY amount_sold DESC) AS rn
	FROM sales_by_year
),
top_300_ranking AS(
	SELECT
		channel_desc,
		calendar_year,
		cust_id,
		cust_last_name,
		cust_first_name,
		amount_sold,
		rn
	FROM ranked_sales
	WHERE rn <= 300
),
present_in_all_3_years AS(
	SELECT
		channel_desc,
		cust_id,
		cust_last_name,
		cust_first_name
	FROM top_300_ranking
	GROUP BY 
		channel_desc,
		cust_id,
		cust_last_name,
		cust_first_name
	HAVING COUNT(DISTINCT calendar_year) = 3
)
SELECT 
	p.channel_desc,
	p.cust_id,
	p.cust_last_name,
	p.cust_first_name,
	TO_CHAR(SUM(t.amount_sold), 'FM999999990.00') AS amount_sold
FROM present_in_all_3_years p
INNER JOIN top_300_ranking t
	ON t.channel_desc = p.channel_desc 
	AND t.cust_id = p.cust_id 
GROUP BY 
	p.channel_desc,
	p.cust_id,
	p.cust_last_name,
	p.cust_first_name
ORDER BY 
	SUM(t.amount_sold) DESC;
	


--===========================================
-- Task 4
--===========================================
-- Create a query to generate a sales report for January 2000, February 2000, and March 2000
-- specifically for the Europe and Americas regions.
-- Display the result by months and by product category in alphabetical order.


--==================================
-- Variant 1. Using CASE WHEN, without any window function
SELECT
	t.calendar_month_desc,
	p.prod_category,
	SUM(CASE WHEN co.country_region = 'Americas' THEN s.amount_sold ELSE 0 END) AS Americas_sales,
	SUM(CASE WHEN co.country_region = 'Europe' THEN s.amount_sold ELSE 0 END) AS Europe_sales
FROM sh.sales s
INNER JOIN sh.products p
	ON p.prod_id = s.prod_id 
INNER JOIN sh.customers c
	ON c.cust_id = s.cust_id 
INNER JOIN sh.countries co
	ON co.country_id = c.country_id 
INNER JOIN sh.times t
	ON t.time_id = s.time_id 
WHERE t.calendar_month_desc IN ('2000-01', '2000-02', '2000-03')
	AND co.country_region IN ('Americas', 'Europe')
GROUP BY 
	t.calendar_month_desc,
	p.prod_category
ORDER BY 
	t.calendar_month_desc,
	p.prod_category;

--==================================
-- Variant 2. Using window function
WITH cat_region_sales AS(
	SELECT
		t.calendar_month_desc,
		p.prod_category,
		co.country_region,
		SUM(s.amount_sold) AS amount_sold
	FROM sh.sales s
	INNER JOIN sh.products p
		ON p.prod_id = s.prod_id 
	INNER JOIN sh.customers c
		ON c.cust_id = s.cust_id 
	INNER JOIN sh.countries co
		ON co.country_id = c.country_id 
	INNER JOIN sh.times t
		ON t.time_id = s.time_id 
	WHERE t.calendar_month_desc IN ('2000-01', '2000-02', '2000-03')
		AND co.country_region IN ('Americas', 'Europe')
	GROUP BY 
		t.calendar_month_desc,
		p.prod_category,
		co.country_region
),
window_calc AS(
SELECT 
	calendar_month_desc,
	prod_category,
	SUM(CASE WHEN country_region = 'Americas' THEN amount_sold ELSE 0 END) 
		OVER (PARTITION BY calendar_month_desc, prod_category) AS Americas_sales,
	SUM(CASE WHEN country_region = 'Europe' THEN amount_sold ELSE 0 END) 
		OVER (PARTITION BY calendar_month_desc, prod_category) AS Europe_sales	
FROM cat_region_sales
)
SELECT DISTINCT 
	calendar_month_desc,
	prod_category,
	TO_CHAR(Americas_sales, 'FM999999990.00') AS Americas_sales,
	TO_CHAR(Europe_sales, 'FM999999990.00') AS Europe_sales
FROM window_calc	
ORDER BY 
	calendar_month_desc,
	prod_category;
