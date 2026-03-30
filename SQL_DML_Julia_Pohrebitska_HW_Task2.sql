-- Task 2

-- ======================================
-- 2.1. Create table ‘table_to_delete’ and fill it with the following query:
-- ======================================

-- creating table
CREATE TABLE table_to_delete AS
SELECT 'veeeeeeery_long_string' || x AS col
FROM generate_series(1,(10^7)::int) x; -- generate_series() creates 10^7 rows of sequential numbers from 1 to 10000000 (10^7)

-- execution time - 28 sec.

SELECT *
FROM table_to_delete
LIMIT 100;

-- ======================================
--2.2. Lookup how much space this table consumes with the following query:
-- ======================================

SELECT *, pg_size_pretty(total_bytes) AS total,
	pg_size_pretty(index_bytes) AS INDEX,
	pg_size_pretty(toast_bytes) AS toast,
	pg_size_pretty(table_bytes) AS TABLE
FROM ( SELECT *, total_bytes-index_bytes-COALESCE(toast_bytes,0) AS table_bytes
       FROM (SELECT c.oid,nspname AS table_schema,
             	relname AS TABLE_NAME,
                c.reltuples AS row_estimate,
                pg_total_relation_size(c.oid) AS total_bytes,
                pg_indexes_size(c.oid) AS index_bytes,
                pg_total_relation_size(reltoastrelid) AS toast_bytes
             FROM pg_class c
             LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
             	WHERE relkind = 'r'
             ) a
       ) a
       WHERE table_name LIKE '%table_to_delete%';

--Total space consumption of table_to_delete
--Row estimate: 10,000,364
--Total bytes: 602,611,712
--Index bytes: 0 
--Toast bytes: 8,192 
--Table size, MB: 575

-- ======================================
-- 2.3. Issue the following DELETE operation on ‘table_to_delete’:
-- ======================================

DELETE FROM table_to_delete
WHERE REPLACE(col, 'veeeeeeery_long_string','')::int % 3 = 0; -- removes 1/3 of all rows


-- a) Note how much time it takes to perform this DELETE statement;
-- execution time - 27 sec.

-- b) Total space consumption after DELETE
--Row estimate: 6,667,124 (33.3% less)
--Total bytes: 602,611,712 (the same)
--Index bytes: 0 (the same)
--Toast bytes: 8,192 (the same)
--Table size, MB: 575 (the same)

-- Short conclusion: after the DELETE operation, 3,333,333 rows were removed in 27 seconds. 
-- The estimated number of remaining rows became 6,667,124. 
-- However, the table size did not decrease and stayed at 575 MB. 
-- This shows that DELETE does not immediately free disk space, even though a 1/3 of rows were removed.

SELECT count(*)
FROM table_to_delete ttd;

-- c) Perform the following command (if you're using DBeaver, press Ctrl+Shift+O 
-- to observe server output (VACUUM results)): 

VACUUM FULL VERBOSE table_to_delete;
-- execution time - 12 sec.

-- d) Check space consumption of the table once again and make conclusions;

-- Total space consumption after VACUUM:
-- Row estimate: 6,667,124 (the same)
-- Total bytes: 401,580,032 (33.3% less)
-- Index bytes: 0 bytes (the same)
-- Toast bytes: 8,192 bytes (the same)
-- Table size: 383 MB (33.3% less)

-- Short conclusion:
-- Initially, the table size was 575 MB. 
-- After DELETing 1/3 of the rows, the number of rows decreased (by 33.3%), 
-- but the table size remained unchanged. 
-- This is because PostgreSQL does not immediately free disk space after DELETE; 
-- instead, it marks rows as deleted and keeps the space for future posible reuse. 
-- After VACUUM FULL, the table size decreased to 383 MB (by 33.3%), so VACUUM physically cleanup space.
-- This is the main difference between logical deletion (DELETE) and physical space reclamation (VACUUM FULL).

-- e) Recreate ‘table_to_delete’ table;
DROP TABLE IF EXISTS table_to_delete;

-- execution time - 0.112 sec.

CREATE TABLE table_to_delete AS
SELECT 'veeeeeeery_long_string' || x AS col
FROM generate_series(1,(10^7)::int) x; -- generate_series() creates 10^7 rows of sequential numbers from 1 to 10000000 (10^7)

SELECT count(*)
FROM table_to_delete ttd;

-- ======================================
-- 2.4. Issue the following TRUNCATE operation: TRUNCATE table_to_delete;
-- ======================================

TRUNCATE table_to_delete;

-- a) Note how much time it takes to perform this TRUNCATE statement.
-- execution time - 0.077 sec.

-- b) Compare with previous results and make conclusion.
-- execution time of DELETE query - 27 sec., while execution time of TRUNCATE query is 0.077 sec., that is 350 times faster.

-- c) Check space consumption of the table once again and make conclusions;
-- Total space consumption after TRUNCATE:
--Row estimate: 0 (100% less)
--Total bytes: 8,192 (almost 100% less)
--Index bytes: 0 (the same)
--Toast bytes: 8,192 (the same)
--Table size, MB: 0 (100% less)

-- ======================================
-- 2.5. Hand over your investigation's results to your mentor. The results must include:
-- ======================================

-- a) Space consumption of ‘table_to_delete’ table before and after each operation;
-- Before DELETE:
-- 575 MB (602,611,712 bytes), 10 M rows 

-- After DELETE (1/3 rows removed):
-- 575 MB (602,611,712 bytes) - 0% change in size, but 33.3% less rows

-- After VACUUM FULL:
-- 383 MB (401,580,032 bytes) - 33.3% less in size, and 0% change in rows

-- After TRUNCATE:
-- 8 KB (8192 bytes) and 0 rows - that is almost 100% cleanup

--b) Compare DELETE and TRUNCATE in terms of:

-- Execution time:
-- DELETE 27 sec
-- TRUNCATE 0.077 sec
-- TRUNCATE is 350 times faster

-- Disk space usage:
-- DELETE - size stays the same (0% change), even we have less rows
-- VACUUM FULL - cleanup data physically (33% in our case)
-- TRUNCATE - frees almost 100% immediately

-- Transaction behavior:
-- DELETE - row-by-row operation, that is why it is not fast
-- TRUNCATE - bulk operation (does not scan rows), that is why it is much more faster

-- Rollback possibility:
-- both can be rolled back before COMMIT
-- but TRUNCATE is more 'aggressive' (instant full cleanup)

-- c) Explain:
-- why DELETE does not free space immediately
-- DELETE does not physically remove data. It just marks rows as deleted.
-- PostgreSQL keeps that space for possible reuse - that’s why size stay the same 575 MB.

-- why VACUUM FULL changes table size
-- VACUUM FULL rewrites the table from scratch.
-- It removes 'dead space' and table becomes smaller (-192 MB, 33.3% less in our case).

-- why TRUNCATE behaves differently
-- TRUNCATE does not delete rows one by one (as DELETE does).
-- It just resets the table, it is super fast and frees space instantly (almost 100% cleanup).

-- how these operations affect performance and storage
-- DELETE - slow and leaves unused space inside the table
-- VACUUM FULL - needs extra time, but cleans up that unused space after DELETE
-- TRUNCATE - fastest and most efficient for full cleanup

