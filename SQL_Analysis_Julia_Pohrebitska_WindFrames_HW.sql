-- =======================================
-- Tasks: writing queries using window frames
-- =======================================

-- =======================================
-- Task 1
-- =======================================

-- Create a query for analyzing the annual sales data for the years 1999 to 2001, 
-- focusing on different sales channels and regions: 'Americas,' 'Asia,' and 'Europe.' 
--
-- The resulting report should contain the following columns:
--
-- 1) AMOUNT_SOLD: This column should show the total sales amount for each sales channel
-- 2) % BY CHANNELS: In this column, we should display the percentage of total sales 
-- for each channel (e.g. 100% - total sales for Americas in 1999, 63.64% - percentage of sales for the channel “Direct Sales”)
-- 3) % PREVIOUS PERIOD: This column should display the same percentage values 
-- as in the '% BY CHANNELS' column but for the previous year
-- 4) % DIFF: This column should show the difference between the '% BY CHANNELS' and 
-- '% PREVIOUS PERIOD' columns, indicating the change in sales percentage from the previous year.
-- The final result should be sorted in ascending order based on three criteria: 
-- first by 'country_region,' then by 'calendar_year,' and finally by 'channel_desc'

WITH sales_1998_2001 AS(
	SELECT 
		co.country_region,
		t.calendar_year,
		ch.channel_desc,
		SUM(s.amount_sold) AS amount_sold
	FROM sh.sales s
	INNER JOIN sh.customers c
		ON c.cust_id = s.cust_id 
	INNER JOIN sh.countries co
		ON co.country_id = c.country_id 
	INNER JOIN sh.channels ch
		ON ch.channel_id = s.channel_id 
	INNER JOIN sh.times t 
		ON t.time_id = s.time_id 
	WHERE 
		co.country_region IN ('Americas', 'Asia', 'Europe')
		AND t.calendar_year BETWEEN 1998 AND 2001					-- need to take 1998 to calculate LAG()
	GROUP BY 
		co.country_region,
		t.calendar_year,
		ch.channel_desc
),
share_by_channels AS(
	SELECT 	
		country_region,
		calendar_year,
		channel_desc,
		amount_sold,
		amount_sold*100.0 / SUM(amount_sold) OVER (PARTITION BY country_region, calendar_year) AS pct_by_channels
	FROM sales_1998_2001 
),
final_calc AS(
	SELECT
		country_region,
		calendar_year,
		channel_desc,
		amount_sold,
		pct_by_channels,
		LAG(pct_by_channels) OVER (PARTITION BY country_region, channel_desc ORDER BY calendar_year) AS pct_previous_period,
		pct_by_channels - LAG(pct_by_channels) OVER (PARTITION BY country_region, channel_desc ORDER BY calendar_year) AS diff
	FROM share_by_channels
)
SELECT 
	country_region,
	calendar_year,
	channel_desc,
	TO_CHAR(amount_sold, 'FM999,999,999,990') || ' $' AS amount_sold,
	ROUND(pct_by_channels,2) || ' %' AS "% BY CHANNELS",
	ROUND(pct_previous_period,2) || ' %' AS "% PREVIOUS PERIOD",
	ROUND(diff,2) ||' %' AS "% DIFF"
FROM final_calc
WHERE calendar_year BETWEEN 1999 AND 2001	
ORDER BY 
	country_region,
	calendar_year,
	channel_desc;



-- =======================================
-- Task 2
-- =======================================
-- You need to create a query that meets the following requirements:
-- Generate a sales report for the 49th, 50th, and 51st weeks of 1999.
--
-- Include a column named CUM_SUM to display the amounts accumulated during each week.
-- Include a column named CENTERED_3_DAY_AVG to show the average sales 
-- for the previous, current, and following days using a centered moving average.
-- For Monday, calculate the average sales based on the weekend sales (Saturday and Sunday) as well as Monday and Tuesday.
-- For Friday, calculate the average sales on Thursday, Friday, and the weekend.
--
-- Ensure that your calculations are accurate for the beginning of week 49 and the end of week 51.

WITH daily_data AS(
	SELECT
		t.calendar_week_number,
		t.time_id,
		t.day_name,
		SUM(s.amount_sold) AS sales
	FROM sh.sales s
	INNER JOIN sh.times t
		ON t.time_id = s.time_id 
	WHERE 
		t.calendar_year = 1999
		AND t.calendar_week_number IN (48,49,50,51,52)
	GROUP BY 
		t.calendar_week_number,
		t.time_id,
		t.day_name
),
three_days_moving_avg AS (
	SELECT
		calendar_week_number,
		time_id,
		day_name,
		sales,
		SUM(sales) OVER (
			PARTITION BY calendar_week_number 
			ORDER BY time_id ASC
			ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW              	-- better to point ROWS explicitly because RANGE will be by default
		) AS cum_sum,
		AVG(sales) OVER (
			ORDER BY time_id 
			ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING
		) AS three_days_avg
	FROM daily_data 
),
diff_moving_avg AS (
	SELECT
		calendar_week_number,
		time_id,
		day_name,
		sales,
		cum_sum,
		CASE 
			WHEN day_name = 'Monday' THEN 
			AVG(sales) OVER (
				ORDER BY time_id 
				ROWS BETWEEN 2 PRECEDING AND 1 FOLLOWING
			)
			WHEN day_name = 'Friday' THEN
			AVG(sales) OVER (
				ORDER BY time_id 
				ROWS BETWEEN 1 PRECEDING AND 2 FOLLOWING
			)
			ELSE three_days_avg
		END AS centered_3_day_avg
FROM three_days_moving_avg
)
SELECT 
	calendar_week_number,
	time_id,
	day_name,
	ROUND(sales,2) AS sales,
	ROUND(cum_sum,2) AS cum_sum,
	ROUND(centered_3_day_avg,2) AS centered_3_day_avg 
FROM diff_moving_avg
WHERE calendar_week_number IN (49,50,51)
ORDER BY 
	calendar_week_number,
	time_id;


-- =======================================
-- Task 3
-- =======================================
-- Please provide 3 instances of utilizing window functions that include a frame clause, 
-- using RANGE, ROWS, and GROUPS modes. 
-- Additionally, explain the reason for choosing a specific frame type for each example. 
-- This can be presented as a single query or as 3 distinct queries.

-- =======================================
-- 1) RANGE & GROUPS example
-- Comparing sales for products with similar list price (prod_list_price)
-- to identify the most promising price segment
-- =======================================

-- COMMENTS:
-- the existing prices' range in the DB: $7.99 - $1299.99
-- I used RANGE here because the calculation is based on a price interval, not on a fixed number of rows. 
-- For each product I calculate sales within +/-$10 below and above the prod_list_price.

-- The main business insight: the mid-level $35–55 price segment looks very strong. 
-- Products in this range show high total sales in the surrounding price range, 
-- so this segment may be especially attractive for customers and worth focusing on in pricing or promotion decisions.

-- I also used GROUPS here because products with the same prod_list_price form 1 peer group.
-- GROUPS BETWEEN 1 PRECEDING AND 1 FOLLOWING means that for each price group
-- I calculate sales for the previous price group, the current price group, and the next price group.

-- The main business insight: the price groups around $45–50 look especially strong.
-- For example, the group with products priced at $45.99, together with the neighboring price groups,
-- shows high total sales. If I were analyzing this as a marketer, I would pay attention to this segment,
-- because it may be attractive for customers and useful for pricing or promotion decisions.

-- Also some expensive products show high sales as well.
-- This means that even though these products have higher prices, they still generate significant revenue,
-- so they should not be ignored in the analysis.


WITH product_groups AS(
	SELECT
		p.prod_id,
		p.prod_name,
		p.prod_category_desc,
		p.prod_list_price,
		SUM(s.amount_sold) AS sales
	FROM sh.sales s 
	INNER JOIN sh.products p 
		ON p.prod_id = s.prod_id 
	GROUP BY 
		p.prod_id,
		p.prod_name,
		p.prod_category_desc,
		p.prod_list_price
)
SELECT
	prod_id,
	prod_name,
	prod_category_desc,
	prod_list_price,
	ROUND(sales,0) AS sales,
	ROUND(SUM(sales) OVER(
		ORDER BY prod_list_price
		RANGE BETWEEN 10 PRECEDING AND 10 FOLLOWING
	),0) AS sales_in_price_range,
	ROUND(SUM(sales) OVER(
		ORDER BY prod_list_price
		GROUPS BETWEEN 1 PRECEDING AND 1 FOLLOWING
	),0) AS sales_in_price_group
FROM product_groups;


-- =======================================
-- 2) GROUPS example
-- Comparing sales by customers with similar income level (cust_income_level)
-- to identify the most promising income level group
-- =======================================

-- COMMENTS:
-- we cannot use here RANGE because cust_income_level is text 
-- I used GROUPS here because customers with the same income level form 1 peer group.
-- GROUPS BETWEEN 1 PRECEDING AND 1 FOLLOWING means that for each income level
-- I calculate sales for the previous income group, the current income group, and the next income group.

-- The main business insight: the customers with income level around $70k–130k look especially strong 
-- and show high total sales (more than $43 mln in total).


WITH income_groups AS(
	SELECT
		c.cust_income_level,
		SUM(s.amount_sold) AS sales
	FROM sh.sales s 
	INNER JOIN sh.customers c
		ON c.cust_id = s.cust_id 
	GROUP BY 
		c.cust_income_level
)
SELECT
	cust_income_level,
	ROUND(sales,0) AS sales,
	ROUND(SUM(sales) OVER(
		ORDER BY cust_income_level
		GROUPS BETWEEN 1 PRECEDING AND 1 FOLLOWING
	),0) AS sales_in_income_group
FROM income_groups
WHERE cust_income_level IS NOT NULL;


-- =======================================
-- 3) RANGE example
-- Comparing sales by customers with similar birth years (cust_year_of_birth)
-- to identify the most promising birth-year segment
-- =======================================

-- COMMENTS:
-- I used RANGE here because the calculation is based on a numeric interval,
-- not on a fixed number of rows or peer groups.
-- In this case, cust_year_of_birth is numeric, so RANGE works well.
-- GROUPS are also possible here. But if some birth years are missing, 
-- GROUPS BETWEEN 20 PRECEDING AND 20 FOLLOWING would take 20 existing groups,
-- which could cover more than 20 actual years.
-- That is why RANGE is a better choice here.

-- RANGE BETWEEN 20 PRECEDING AND 20 FOLLOWING means that for each birth year
-- I calculate sales for customers born within 20 years before and 20 years after the current birth year.

-- The main business insight:
-- customers born around 1959 show the strongest result.
-- The +/- 20 years birth-year segment around 1959 generates the highest total sales.
-- So, customers born approximately between 1939 and 1979 may be the most valuable audience
-- for marketing and product targeting.


WITH birth_segments AS(
	SELECT
		c.cust_year_of_birth,
		SUM(s.amount_sold) AS sales
	FROM sh.sales s 
	INNER JOIN sh.customers c
		ON c.cust_id = s.cust_id 
	GROUP BY 
		c.cust_year_of_birth
)
SELECT
	cust_year_of_birth,
	ROUND(sales,0) AS sales,
	ROUND(SUM(sales) OVER(
		ORDER BY cust_year_of_birth
		RANGE BETWEEN 20 PRECEDING AND 20 FOLLOWING
	),0) AS sales_in_birth_segment
FROM birth_segments;


-- =======================================
-- 4) ROWS example
-- Calculating three_weeks_moving_avg sales for 2000 for weekly sales
-- =======================================

-- COMMENTS:
-- I used ROWS here because I wanted to calculate a moving average based on a fixed number of rows. 
-- In this case each row represents 1 week, so ROWS BETWEEN 2 PRECEDING AND CURRENT ROW 
-- calculates the average sales for the current week and the 2 previous weeks.

-- The main business insight: 
-- The weekly sales are quite volatile, with several sharp peaks (week 8, 29 and 50) and drops, 
-- but the moving average shows that the overall sales level remains relatively 
-- stable during most of the year. 

-- The 3-week moving average helps smooth short-term weekly fluctuations 
-- and shows the general sales trend more clearly. 


WITH weekly_sales AS(
	SELECT
		t.calendar_year,
		t.calendar_week_number, 
		SUM(s.amount_sold) AS sales
	FROM sh.sales s
	INNER JOIN sh.times t 
		ON t.time_id = s.time_id 
	WHERE t.calendar_year IN (1999, 2000)
	GROUP BY 
		t.calendar_year,
		t.calendar_week_number	
),
mooving_avg_calc AS(
	SELECT
		calendar_year,
		calendar_week_number,
		sales,
		AVG(sales) OVER (
			ORDER BY calendar_year, calendar_week_number
			ROWS BETWEEN 2 PRECEDING AND CURRENT ROW 
		) AS three_weeks_mooving_avg
	FROM weekly_sales
)
SELECT 
	calendar_year,
	calendar_week_number,
	ROUND(sales,0) AS sales,
	ROUND(three_weeks_mooving_avg, 0) AS three_weeks_mooving_avg
FROM mooving_avg_calc
WHERE calendar_year = 2000;

















