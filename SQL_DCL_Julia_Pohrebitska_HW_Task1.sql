-- ======================================
-- Task 1. Figure out what security precautions are already used in your 'dvd_rental' database.  Prepare description
-- ======================================
-- Focus on:
-- 1) Existing users/roles and their permissions 
-- 2) Table-level privileges
-- 3) Any existing row-level security policies
-- 4) Database-level settings like connection limits or authentication methods 
--
-- Prepare a detailed description in a text or docx file. Include SQL queries you used and their outputs for evidence
-- Explain whether it is sufficient or risky. Identify at least one potential security vulnerability and suggest an improvement

-- =======================
-- 1) Existing users/roles and their permissions 

SELECT *
FROM pg_catalog.pg_roles;

-- So, there are 17 roles, 1 of them - postgres role is a 'superuser', which has all possible rights, 
-- including LOGIN attribute (rolcanlogin = TRUE)
-- In this environment, postgres appears to be the login role, while most other entries 
-- are roles without direct login capability.

SELECT
	rolname,
	rolcanlogin
FROM pg_catalog.pg_roles
WHERE rolcanlogin = TRUE
;

-- Other PRIVILEGES:

-- rolsuper:
-- In this database, only postgres is a superuser.

-- rolinherit:
-- Shows whether a role automatically inherits privileges from roles granted to it.
-- In this database, all roles have rolinherit = TRUE, which means inherited privileges are enabled by default.

-- rolcreaterole:
-- Shows whether a role can create or manage other roles.
-- In this database, only postgres has this privilege.

-- rolcreatedb:
-- Shows whether a role can create new databases.
-- In this database, only postgres can create databases.

-- rolcanlogin:
-- Shows whether a role can log in and connect to PostgreSQL directly.
-- In this database, only postgres has rolcanlogin = TRUE.
-- All other roles are non-login roles.

-- rolreplication:
-- Shows whether a role has replication-related privileges.
-- In this database, only postgres has replication privilege.

-- rolconnlimit:
-- Shows the maximum number of concurrent connections allowed for a role.
-- Here all roles have rolconnlimit = -1, which means no role-level connection limit is set.
-- At the same time we may check the server-connection limits:

-- connection limits of the role --> '-1' means role has no limits
SELECT
    rolname,
    rolconnlimit
FROM pg_roles
ORDER BY rolname;

-- connection limits of the server --> max 100 connections
SHOW max_connections;

-- connection limits of the dvdrental DB --> '-1' means DB has no limits as well as roles
SELECT
    datname,
    datconnlimit
FROM pg_database
WHERE datname = 'dvdrental';

-- rolvaliduntil:
-- Here the value is NULL for all roles, which means no password expiration is defined.

-- rolbypassrls:
-- Shows whether a role can bypass RLS - row-level security.
-- Only postgre role has this permission.

-- General conclusion about potential security vulnerability
-- The environment contains 16 system roles and 1 login superuser role (postgres).
-- Perhaps this is acceptable for student training database, 
-- but using only a superuser account for daily work is risky.
-- A better approach would be to create separate non-superuser role 
-- with only the required privileges for everyday work.


-- =============================
-- 2) Table-level privileges
-- Table-level privileges are permissions that define what a user or role can do 
-- with a specific table, such as SELECT, INSERT, UPDATE, or DELETE, or others.
-- 
-- We may check table-level privileges through the table --> information_schema.role_table_grants.
-- Or directly in the table information --> Permissions

SELECT
    table_schema,
    table_name,
    grantee,
    privilege_type
FROM information_schema.role_table_grants
WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
ORDER BY table_schema, table_name, grantee, privilege_type;

-- General conclusion about table-level privileges:
-- Only superuser postgres has table-level privileges on each table in the dvdrental
-- with privileges to:
-- DELETE,
-- INSERT,
-- REFERENCES,
-- SELECT,
-- TRIGGER,
-- TRUNCATE,
-- UPDATE.

-- =============================
-- 3) Any existing row-level security policies
-- Row-level security is a PostgreSQL feature that restricts which rows 
-- a user or role can see or modify in a table.
-- 
-- We may check RLS through the tables --> pg_catalog.pg_tables, pg_catalog.pg_policies.
-- Or directly in the table information --> Policies

SELECT *
FROM pg_catalog.pg_tables;

SELECT *
FROM pg_catalog.pg_policies;

-- General conclusion about RLS:
-- there are no RLS policies in any table from the dvdrental DB.

--==================================
-- 4) Database-level settings like connection limits or authentication methods 

-- Database-level settings describe access and connection behavior at the database or server level.
-- For db settings we may check: pg_database, pg_roles, SHOW password_encryption, SHOW hba_file

-- Connection limits were discussed in the question (1).
-- Authentication methods define how users are allowed to connect to PostgreSQL.
-- They are usually defined in pg_hba.conf

-- location of the pg_hba.conf:
SHOW hba_file;

-- PostgreSQL use scram-sha-256 as password encryption method.
-- We may see it here:
SHOW password_encryption;

SELECT
    *
FROM pg_database
WHERE datname = 'dvdrental';

-- General conclusions about database-level settings:
-- Only local connections are allowed because the rules in the hba_file include only local connections.
-- scram-sha-256 means password-based authentication using a more secure authentication method.
-- DB has no connection limits.
