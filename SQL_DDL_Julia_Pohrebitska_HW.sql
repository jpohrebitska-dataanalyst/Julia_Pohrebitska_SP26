-- ===============================
 -- TASK: Create a physical database
-- ===============================
--
-- ===============================
-- Conclusions:
-- ===============================
-- This physical model follows the logical model structure and keeps it in 3NF.
-- I did not add new business entities or relationships that were not part of the logical design.
-- At the physical level, I added several extra CHECK constraints where they were useful
-- to better protect data quality and prevent invalid values from being inserted.
--
-- I also tried to keep the script rerunnable:
-- - CREATE TABLE / ALTER TABLE use IF NOT EXISTS where possible
-- - INSERT statements use ON CONFLICT DO NOTHING or WHERE NOT EXISTS
-- This helps avoid duplicate data and allows the script to be executed more than once.
-- ===============================
-- Data types
-- ===============================
-- Data types were chosen based on the meaning of each column.
-- For example:
-- - NUMERIC(10,2) is used for prices to avoid rounding issues
-- - DATE is used where only the calendar date matters
-- - TIMESTAMPTZ is used where exact date-time matters
-- - VARCHAR is used for business codes, names, and statuses
--
-- Risk of choosing the wrong data type:
-- wrong data types can lead to loss of precision, incorrect comparisons,
-- invalid calculations or bad filtering.
-- ===============================
-- Foreign keys
-- ===============================
-- Foreign keys preserve relationships between parent and child tables.
-- They ensure that a child row can reference only an existing parent row.
--
-- If a foreign key is missing, the database may allow orphan rows.
-- For example, a trip could reference a station that does not exist,
-- or a ticket sale could point to a missing ticket offer.
-- In that case, joins become unreliable and the model loses referential integrity.
--
-- ===============================
-- One-to-one relationships
-- ===============================
-- In one-to-one relationships, the foreign key was also made UNIQUE.
-- This is necessary because a foreign key alone does not guarantee 1:1.
-- Without UNIQUE, the same parent row could be referenced many times,
-- and the relationship would actually behave like one-to-many.
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
-- Foreign key values are resolved from parent tables using business attributes
-- such as line_code, station_code, ticket_type_name, schedule_name, or fleet_number.
--
-- This makes the script more stable and portable:
-- even if generated IDs are different in another environment,
-- the inserts still preserve the correct relationships.
--
-- I used nested subqueries instead of CTEs in many INSERT statements
-- because here they read more sequentially and keep each inserted row compact.


-- ===============================
-- Block 1. Database creation
-- ===============================

CREATE DATABASE subway_system_db;

-- ===============================
-- Block 1.1. Check whether tables were created
-- ===============================
	
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'subway'
ORDER BY table_name;


-- ===============================
-- Block 2. Schema and base tables
-- (tables without foreign keys)
-- ===============================

BEGIN;

CREATE SCHEMA IF NOT EXISTS subway;

CREATE TABLE IF NOT EXISTS subway.line (
	line_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    line_code VARCHAR(20) NOT NULL,
    line_name VARCHAR(100) NOT NULL,
    color_hex CHAR(7) NOT NULL,
    opened_on DATE NOT NULL,
    closed_on DATE,
    CONSTRAINT uq_line_line_code UNIQUE (line_code),
    CONSTRAINT ck_line_color_hex_format
        CHECK (color_hex ~ '^#[0-9A-Fa-f]{6}$'),
    CONSTRAINT ck_line_closed_on_after_opened_on
        CHECK (closed_on IS NULL OR closed_on >= opened_on)
);

CREATE TABLE IF NOT EXISTS subway.asset (
	asset_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	asset_type VARCHAR(20) NOT NULL,
	created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
	CONSTRAINT ck_asset_asset_type
		CHECK (asset_type IN ('train', 'station', 'track_segment'))
);

CREATE TABLE IF NOT EXISTS subway.maintenance_type (
	maintenance_type_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	maintenance_type_name VARCHAR(50) NOT NULL,
	description TEXT,
	default_interval_days INTEGER,
	CONSTRAINT uq_maintenance_type_maintenance_type_name
		UNIQUE (maintenance_type_name),
	CONSTRAINT ck_maintenance_type_default_interval 
		CHECK (default_interval_days IS NULL OR default_interval_days > 0)
);

CREATE TABLE IF NOT EXISTS subway.ticket_type (
	ticket_type_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	ticket_type_name VARCHAR(50) NOT NULL,
	description TEXT,
	CONSTRAINT uq_ticket_type_ticket_type_name
		UNIQUE (ticket_type_name)
);

COMMIT;

-- ===============================
-- Block 3. Core tables with foreign keys
-- ===============================

BEGIN;

CREATE TABLE IF NOT EXISTS subway.train (
	train_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	asset_id BIGINT NOT NULL,			-- FK
	fleet_number VARCHAR(30) NOT NULL,
	model_name VARCHAR(100) NOT NULL,
	capacity INTEGER NOT NULL,
	commissioned_on DATE NOT NULL,
	decommissioned_on DATE,
	CONSTRAINT fk_train_asset_asset_id 
		FOREIGN KEY (asset_id)
		REFERENCES subway.asset (asset_id),
	CONSTRAINT uq_train_asset_id          -- is added to preserve the one-to-one relationship
		UNIQUE (asset_id),  
	CONSTRAINT uq_train_fleet_number
		UNIQUE (fleet_number),
	CONSTRAINT ck_train_capacity
		CHECK (capacity > 0),
	CONSTRAINT ck_train_decommissioned_on_after_commissioned_on
		CHECK (decommissioned_on IS NULL OR decommissioned_on >= commissioned_on)
);

CREATE TABLE IF NOT EXISTS subway.station (
	station_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	asset_id BIGINT NOT NULL,			-- FK
	parent_station_id BIGINT,			-- FK
	station_code VARCHAR(20) NOT NULL,
	station_name VARCHAR(100) NOT NULL,
	opened_on DATE NOT NULL,
	closed_on DATE,
	CONSTRAINT fk_station_asset_asset_id 
		FOREIGN KEY (asset_id)
		REFERENCES subway.asset (asset_id),
	CONSTRAINT uq_station_asset_id          -- is added to preserve the one-to-one relationship
		UNIQUE (asset_id),  
	CONSTRAINT uq_station_station_code
		UNIQUE(station_code),
	CONSTRAINT fk_station_station_parent_station_station_id
        FOREIGN KEY (parent_station_id)
        REFERENCES subway.station (station_id),
    CONSTRAINT ck_station_closed_on_after_opened_on
        CHECK (closed_on IS NULL OR closed_on >= opened_on)
);       
        
CREATE TABLE IF NOT EXISTS subway.ticket_offer (
	ticket_offer_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	ticket_type_id BIGINT NOT NULL,			-- FK
	validity_period INTERVAL NOT NULL,
	price NUMERIC(10,2) NOT NULL,
	valid_from DATE NOT NULL,
	valid_to DATE,
	CONSTRAINT fk_ticket_offer_ticket_type_ticket_type_id
		FOREIGN KEY (ticket_type_id)
		REFERENCES subway.ticket_type (ticket_type_id),
	CONSTRAINT uq_ticket_offer_ticket_type_id_valid_from
        UNIQUE (ticket_type_id, valid_from),
    CONSTRAINT ck_ticket_offer_price
		CHECK (price > 0),
	CONSTRAINT ck_ticket_offer_valid_to_after_valid_from
		CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS subway.schedule_version (
	schedule_version_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	line_id BIGINT NOT NULL,			-- FK
	schedule_name VARCHAR(100) NOT NULL,
	day_type VARCHAR(20) NOT NULL,
	effective_from DATE NOT NULL,
	effective_to DATE,
	created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
	CONSTRAINT fk_schedule_version_line_line_id
		FOREIGN KEY (line_id)
		REFERENCES subway.line (line_id),
	CONSTRAINT ck_schedule_version_day_type
        CHECK (day_type IN ('weekday', 'weekend', 'holiday', 'special')),
    CONSTRAINT ck_schedule_version_effective_to_after_effective_from
        CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

COMMIT;

-- ===============================
-- Block 4. Child and transactional tables
-- ===============================

BEGIN;	

CREATE TABLE IF NOT EXISTS subway.line_station (	
	line_station_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	line_id BIGINT NOT NULL,			-- FK
	station_id BIGINT NOT NULL,			-- FK
	station_sequence SMALLINT NOT NULL,
	distance_from_origin_km NUMERIC(6,2) NOT NULL,
	valid_from DATE NOT NULL,
	valid_to DATE,
	CONSTRAINT fk_line_station_line_line_id
		FOREIGN KEY (line_id)
		REFERENCES subway.line (line_id),
	CONSTRAINT fk_line_station_station_station_id
		FOREIGN KEY (station_id)
		REFERENCES subway.station (station_id),	
	CONSTRAINT uq_line_station_line_id_station_sequence_valid_from
        UNIQUE (line_id, station_sequence, valid_from),	
    CONSTRAINT uq_line_station_line_id_station_id_valid_from
        UNIQUE (line_id, station_id, valid_from),	
	CONSTRAINT ck_line_station_station_sequence
        CHECK (station_sequence > 0),
	CONSTRAINT ck_line_station_distance_from_origin_km
        CHECK (distance_from_origin_km >= 0),        
    CONSTRAINT ck_line_station_valid_to_after_valid_from
        CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS subway.track_segment(	
	track_segment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	asset_id BIGINT NOT NULL,                  -- FK
	from_station_id BIGINT NOT NULL,           -- FK
	to_station_id BIGINT NOT NULL,             -- FK
	length_km NUMERIC(6,2) NOT NULL,
	opened_on DATE NOT NULL,
	closed_on DATE,
	CONSTRAINT fk_track_segment_asset_asset_id
		FOREIGN KEY (asset_id)
		REFERENCES subway.asset (asset_id),
	CONSTRAINT fk_track_segment_station_from_station_id
		FOREIGN KEY (from_station_id)
		REFERENCES subway.station(station_id),
	CONSTRAINT fk_track_segment_station_to_station_id
		FOREIGN KEY (to_station_id)
		REFERENCES subway.station(station_id),	
	CONSTRAINT uq_track_segment_asset_id          -- is added to preserve the one-to-one relationship
		UNIQUE (asset_id),  
	CONSTRAINT uq_track_segment_from_station_id_to_station_id_opened_on
		UNIQUE (from_station_id, to_station_id, opened_on),  	
	CONSTRAINT ck_track_segment_length_km
        CHECK (length_km > 0),       	
    CONSTRAINT ck_track_segment_different_stations
        CHECK (from_station_id <> to_station_id),
    CONSTRAINT ck_track_segment_closed_on_after_opened_on
        CHECK (closed_on IS NULL OR closed_on >= opened_on)	
);


CREATE TABLE IF NOT EXISTS subway.trip(	
	trip_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    schedule_version_id BIGINT NOT NULL,       -- FK
	origin_station_id BIGINT NOT NULL,	       -- FK
	destination_station_id BIGINT NOT NULL,	   -- FK
	trip_code VARCHAR(50) NOT NULL,
	direction VARCHAR(50) NOT NULL,
	planned_departure_time TIME NOT NULL,
	planned_arrival_time TIME NOT NULL,
	arrival_day_offset SMALLINT NOT NULL DEFAULT 0,
	CONSTRAINT fk_trip_schedule_version_schedule_version_id
		FOREIGN KEY (schedule_version_id)
		REFERENCES subway.schedule_version (schedule_version_id),	
	CONSTRAINT fk_trip_station_origin_station_id
		FOREIGN KEY (origin_station_id)
		REFERENCES subway.station (station_id),		
	CONSTRAINT fk_trip_station_destination_station_id
		FOREIGN KEY (destination_station_id)
		REFERENCES subway.station (station_id),	
	CONSTRAINT uq_trip_schedule_version_id_trip_code
		UNIQUE (schedule_version_id, trip_code),  		
    CONSTRAINT ck_trip_direction
        CHECK (direction IN ('outbound', 'inbound')),
    CONSTRAINT ck_trip_different_stations
        CHECK (origin_station_id <> destination_station_id),
    CONSTRAINT ck_trip_arrival_day_offset
    CHECK (arrival_day_offset >= 0)   
);

CREATE TABLE IF NOT EXISTS subway.maintenance_event (
	maintenance_event_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	asset_id BIGINT NOT NULL,                  -- FK
	maintenance_type_id BIGINT NOT NULL,       -- FK
	scheduled_start TIMESTAMPTZ NOT NULL,
	scheduled_end TIMESTAMPTZ NOT NULL,
	actual_start TIMESTAMPTZ,				   -- NULLs are allowed for planned events
	actual_end TIMESTAMPTZ,					   -- NULLs are allowed for not-yet-completed events
	maintenance_status VARCHAR(20) NOT NULL DEFAULT 'planned',
	notes TEXT,
	CONSTRAINT fk_maintenance_event_asset_asset_id
		FOREIGN KEY (asset_id)
		REFERENCES subway.asset (asset_id),	
	CONSTRAINT fk_maintenance_event_maintenance_type_maintenance_type_id
		FOREIGN KEY (maintenance_type_id)
		REFERENCES subway.maintenance_type (maintenance_type_id),		
	CONSTRAINT ck_maintenance_event_maintenance_status
        CHECK (maintenance_status IN ('planned', 'in_progress', 'completed','cancelled')),
	CONSTRAINT ck_maintenance_event_scheduled_end_after_scheduled_start
        CHECK (scheduled_end >= scheduled_start),	
    CONSTRAINT ck_maintenance_event_scheduled_start_after_2000
        CHECK (scheduled_start > TIMESTAMPTZ '2000-01-01 00:00:00+00'),
    CONSTRAINT ck_maintenance_event_actual_end_after_actual_start
        CHECK (
    -- NULLs are allowed for planned or not-yet-completed events
            actual_end IS NULL
            OR actual_start IS NULL
            OR actual_end >= actual_start
        )
);
	
COMMIT;	
	

-- ===============================
-- Block 5. Transactional and linking tables
-- ===============================

BEGIN;	

CREATE TABLE IF NOT EXISTS subway.trip_stop (	
	trip_id BIGINT NOT NULL, 			-- composite PK, FK
	stop_sequence SMALLINT NOT NULL,	-- composite PK
	line_station_id BIGINT NOT NULL, 	-- FK
	arrival_offset INTERVAL,
	departure_offset INTERVAL,
	CONSTRAINT pk_trip_stop_trip_id_stop_sequence
		PRIMARY KEY (trip_id, stop_sequence),
	CONSTRAINT fk_trip_stop_trip_trip_id
		FOREIGN KEY (trip_id)
		REFERENCES subway.trip (trip_id),	
	CONSTRAINT fk_trip_stop_line_station_line_station_id
		FOREIGN KEY (line_station_id)
		REFERENCES subway.line_station (line_station_id),		
	CONSTRAINT uq_trip_stop_trip_id_line_station_id
		UNIQUE (trip_id, line_station_id),  
	CONSTRAINT ck_trip_stop_stop_sequence
		CHECK (stop_sequence > 0), 		
	CONSTRAINT ck_trip_stop_arrival_or_departure_offset_not_null
		CHECK (arrival_offset IS NOT NULL OR departure_offset IS NOT NULL) 			
);

CREATE TABLE IF NOT EXISTS subway.train_assignment (
    train_assignment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trip_id BIGINT NOT NULL, 			-- FK
    train_id BIGINT NOT NULL, 			-- FK
	valid_from DATE NOT NULL,
	valid_to DATE,
	CONSTRAINT fk_train_assignment_trip_trip_id
		FOREIGN KEY (trip_id)
		REFERENCES subway.trip (trip_id),	
	CONSTRAINT fk_train_assignment_train_train_id
		FOREIGN KEY (train_id)
		REFERENCES subway.train (train_id),	
	CONSTRAINT uq_train_assignment_trip_id_valid_from
		UNIQUE (trip_id, valid_from),  				
    CONSTRAINT ck_train_assignment_valid_to_after_valid_from
        CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS subway.ticket_sale (
    ticket_sale_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ticket_offer_id BIGINT NOT NULL, 			-- FK
	sale_station_id BIGINT, 					-- FK
	ticket_number VARCHAR(50) NOT NULL,
	sold_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
	valid_from TIMESTAMPTZ NOT NULL,
	valid_to TIMESTAMPTZ NOT NULL,
	sale_channel VARCHAR(20) NOT NULL,
	CONSTRAINT fk_ticket_sale_ticket_offer_ticket_offer_id
		FOREIGN KEY (ticket_offer_id)
		REFERENCES subway.ticket_offer (ticket_offer_id),		
	CONSTRAINT fk_ticket_sale_station_station_id
		FOREIGN KEY (sale_station_id)
		REFERENCES subway.station (station_id),			
	CONSTRAINT uq_ticket_sale_ticket_number
		UNIQUE (ticket_number),
	CONSTRAINT ck_ticket_sale_sale_channel
        CHECK (sale_channel IN ('app', 'kiosk', 'card_terminal', 'cash_desk')),
    CONSTRAINT ck_ticket_sale_valid_to_after_valid_from
        CHECK (valid_to >= valid_from),
    CONSTRAINT ck_ticket_sale_sold_at_after_2000
    	CHECK (sold_at > TIMESTAMPTZ '2000-01-01 00:00:00+00')
);

COMMIT;

-- ===============================
-- Block 6. Populating the tables with sample data generated.
-- Use INSERT statements with ON CONFLICT DO NOTHING or WHERE NOT EXISTS to avoid duplicates. 
-- Avoid hardcoding values where possible. 
-- ===============================		

-- ====================================
-- Part 1. Base tables
-- (tables without foreign keys)
-- ====================================

BEGIN;

-- 1) line
INSERT INTO subway.line (
    line_code,
    line_name,
    color_hex,
    opened_on,
    closed_on
)
VALUES
    ('M1', 'Sviatoshynsko-Brovarska', '#E53935', DATE '1960-11-06', NULL),
    ('M2', 'Obolonsko-Teremkivska',   '#1565C0', DATE '1976-12-17', NULL),
    ('M3', 'Syretsko-Pecherska',      '#388E3C', DATE '1989-12-31', NULL)
ON CONFLICT (line_code) DO NOTHING;				-- rerunnable script
												-- using ON CONFLICT DO NOTHING because line_code is unique	

-- 2) asset

INSERT INTO subway.asset (
    asset_type,
    created_at
)
SELECT v.asset_type, v.created_at
FROM (
    VALUES
        ('station',       TIMESTAMPTZ '2026-01-01 09:00:00+02'),
        ('train',         TIMESTAMPTZ '2026-01-01 09:05:00+02'),
        ('track_segment', TIMESTAMPTZ '2026-01-01 09:10:00+02'),
        ('station',       TIMESTAMPTZ '2026-01-01 09:15:00+02'),
        ('station',       TIMESTAMPTZ '2026-01-01 09:20:00+02'),
        ('train',         TIMESTAMPTZ '2026-01-01 09:25:00+02'),
        ('train',         TIMESTAMPTZ '2026-01-01 09:30:00+02'),
        ('track_segment', TIMESTAMPTZ '2026-01-01 09:35:00+02'),
        ('track_segment', TIMESTAMPTZ '2026-01-01 09:40:00+02')
) AS v(asset_type, created_at)
WHERE NOT EXISTS (
    SELECT 1
    FROM subway.asset a
    WHERE a.asset_type = v.asset_type
      AND a.created_at = v.created_at
);
	
-- 3) maintenance_type
INSERT INTO subway.maintenance_type (
    maintenance_type_name,
    description,
    default_interval_days
)
VALUES
    ('Inspection', 'Routine technical inspection of infrastructure condition', 30),
    ('Cleaning',   'Scheduled cleaning of trains, stations, or track areas',   7),
    ('Repair',     'Corrective maintenance to fix detected issues',            90)
ON CONFLICT (maintenance_type_name) DO NOTHING;			-- rerunnable script, 
														-- using ON CONFLICT DO NOTHING because maintenance_type_name is unique


-- 4) ticket_type
INSERT INTO subway.ticket_type (
    ticket_type_name,
    description
)
VALUES
    ('Single Ride',  'One trip ticket for a single passenger'),
    ('Day Pass',     'Unlimited rides during one day'),
    ('Monthly Pass', 'Unlimited rides during one calendar month')
ON CONFLICT (ticket_type_name) DO NOTHING;				-- rerunnable script, 
														-- using ON CONFLICT DO NOTHING because ticket_type_name is unique

COMMIT;

-- Check: number of rows & values inside 
SELECT 
	'line' AS table_name, 
	COUNT(*) AS row_count 
FROM subway.line
UNION ALL
SELECT 
	'asset', 
	COUNT(*) 
FROM subway.asset
UNION ALL
SELECT 
	'maintenance_type', 
	COUNT(*) 
FROM subway.maintenance_type
UNION ALL
SELECT 
	'ticket_type', 
	COUNT(*) 
FROM subway.ticket_type;
	
SELECT *
FROM subway.asset;
SELECT *
FROM subway.line;
SELECT *
FROM subway.maintenance_type;
SELECT *
FROM subway.ticket_type;


-- ====================================
-- Part 2. Core tables with foreign keys
-- ====================================

SELECT *
FROM subway.train;
SELECT *
FROM subway.station;
SELECT *
FROM subway.ticket_offer;
SELECT *
FROM subway.schedule_version;

-- 5) train

INSERT INTO subway.train (
    asset_id,
    fleet_number,
    model_name,
    capacity,
    commissioned_on,
    decommissioned_on
)
SELECT
    a.asset_id,         -- FK
    v.fleet_number,
    v.model_name,
    v.capacity,
    v.commissioned_on,
    v.decommissioned_on
FROM (
    VALUES
        (TIMESTAMPTZ '2026-01-01 09:05:00+02', '1207', '81-717/714',         1100, DATE '2015-03-01', NULL::DATE),
        (TIMESTAMPTZ '2026-01-01 09:25:00+02', '1215', '81-717/714',         1100, DATE '2016-06-15', NULL::DATE),
        (TIMESTAMPTZ '2026-01-01 09:30:00+02', '0988', '81-540.2K/541.2K',    980, DATE '2008-09-01', DATE '2024-12-31')
) AS v(created_at, fleet_number, model_name, capacity, commissioned_on, decommissioned_on)
INNER JOIN subway.asset a
	ON a.asset_type = 'train'
    AND a.created_at = v.created_at
WHERE NOT EXISTS (
    SELECT 1
    FROM subway.train t
    WHERE t.fleet_number = v.fleet_number
)
RETURNING
	train_id,
	asset_id,
    fleet_number,
    model_name,
    capacity,
    commissioned_on,
    decommissioned_on;


-- 6) station
-- subway.station has a self-referencing foreign key, 
-- so we need to insert the parent station first 
-- and then insert child stations referencing the already existing parent station.

-- Stage 1. Inserting the parent station first 

INSERT INTO subway.station (
    asset_id,
    parent_station_id,
    station_code,
    station_name,
    opened_on,
    closed_on
)
SELECT
    a.asset_id,
    NULL,
    'MAI_HUB',
    'Maidan Hub',
    DATE '1976-12-17',
    NULL::DATE
FROM subway.asset a
WHERE a.asset_type = 'station'
	AND a.created_at = TIMESTAMPTZ '2026-01-01 09:00:00+02'
  	AND NOT EXISTS (
    	SELECT 1
        FROM subway.station s
        WHERE s.station_code = 'MAI_HUB'
  )
RETURNING 
    station_id,
    asset_id,
    parent_station_id,
    station_code,
    station_name,
    opened_on,
    closed_on;

-- Stage 2. Adding child station where we have already parent station

INSERT INTO subway.station (
    asset_id,				-- FK
    parent_station_id,		-- FK
    station_code,
    station_name,
    opened_on,
    closed_on
)
SELECT
    a.asset_id,			
    b.station_id,		
    v.station_code,
    v.station_name,
    v.opened_on,
    v.closed_on
FROM (
    VALUES
        (TIMESTAMPTZ '2026-01-01 09:15:00+02', 'MAI', 'Maidan Nezalezhnosti', DATE '1976-12-17', NULL::DATE),
        (TIMESTAMPTZ '2026-01-01 09:20:00+02', 'KHR', 'Khreshchatyk',         DATE '1960-11-06', NULL::DATE)
) AS v(created_at, station_code, station_name, opened_on, closed_on)
INNER JOIN subway.asset a
	ON a.asset_type = 'station'
	AND a.created_at = v.created_at
INNER JOIN subway.station b
    ON b.station_code = 'MAI_HUB'
WHERE NOT EXISTS (
    SELECT 1
    FROM subway.station s
    WHERE s.station_code = v.station_code
)
RETURNING 
    station_id,
    asset_id,
    parent_station_id,
    station_code,
    station_name,
    opened_on,
    closed_on;


-- 7) ticket_offer

INSERT INTO subway.ticket_offer (
    ticket_type_id,			-- FK
    validity_period,
    price,
    valid_from,
    valid_to
)
SELECT
    tt.ticket_type_id,     
    v.validity_period,
    v.price,
    v.valid_from,
    v.valid_to
FROM (
    VALUES
        ('Single Ride',  INTERVAL '01:30:00',  30.00, DATE '2026-01-01', NULL::DATE),   -- NULL::DATE means that ticket offer is active now
        ('Day Pass',     INTERVAL '1 day',    120.00, DATE '2026-01-01', NULL::DATE),
        ('Monthly Pass', INTERVAL '30 days',  550.00, DATE '2026-01-01', NULL::DATE)
) AS v(ticket_type_name, validity_period, price, valid_from, valid_to)
INNER JOIN subway.ticket_type tt
    ON tt.ticket_type_name = v.ticket_type_name
WHERE NOT EXISTS (
    SELECT 1
    FROM subway.ticket_offer t
    WHERE t.ticket_type_id = tt.ticket_type_id
      AND t.valid_from = v.valid_from
)
RETURNING
    ticket_offer_id,
    ticket_type_id,
    validity_period,
    price,
    valid_from,
    valid_to;

SELECT *
FROM subway.ticket_offer;


-- 8) schedule_version

INSERT INTO subway.schedule_version (
    line_id,
    schedule_name,
    day_type,
    effective_from,
    effective_to,
    created_at
)
SELECT
    (
    	SELECT l.line_id
        FROM subway.line l
        WHERE l.line_code = v.line_code
    ) AS line_id,      					-- FK
    v.schedule_name,
    v.day_type,
    v.effective_from,
    v.effective_to,
    v.created_at
FROM (
    VALUES
        ('M1', 'Weekday Winter Schedule 2026', 'weekday', DATE '2026-01-01', NULL::DATE,         TIMESTAMPTZ '2025-12-15 10:00:00+02'),
        ('M1', 'Weekend Schedule 2026',        'weekend', DATE '2026-01-01', NULL::DATE,         TIMESTAMPTZ '2025-12-15 10:05:00+02'),
        ('M2', 'Holiday Service Plan',         'holiday', DATE '2026-01-05', DATE '2026-01-10',  TIMESTAMPTZ '2025-12-20 14:30:00+02')
) AS v(line_code, schedule_name, day_type, effective_from, effective_to, created_at)
WHERE NOT EXISTS (
    SELECT 1
    FROM subway.schedule_version sv
    WHERE sv.line_id = (
        SELECT l.line_id
        FROM subway.line l
        WHERE l.line_code = v.line_code
    )
      AND sv.schedule_name = v.schedule_name
      AND sv.effective_from = v.effective_from
)
RETURNING
    schedule_version_id,
    line_id,
    schedule_name,
    day_type,
    effective_from,
    effective_to,
    created_at;

SELECT *
FROM subway.schedule_version;

COMMIT;

-- ===============================
-- Part 3. Child and transactional tables
-- ===============================

SELECT *
FROM subway.line_station;
SELECT *
FROM subway.track_segment;
SELECT *
FROM subway.trip;
SELECT *
FROM subway.maintenance_event;

-- 9) line_station

INSERT INTO subway.line_station (
    line_id,			-- FK
    station_id,			-- FK
    station_sequence,
    distance_from_origin_km,
    valid_from,
    valid_to
)
SELECT
    (
        SELECT l.line_id
        FROM subway.line l
        WHERE l.line_code = v.line_code
    ) AS line_id,           
    (
        SELECT s.station_id
        FROM subway.station s
        WHERE s.station_code = v.station_code
    ) AS station_id,        
    v.station_sequence,
    v.distance_from_origin_km,
    v.valid_from,
    v.valid_to
FROM (
    VALUES
        ('M1', 'MAI_HUB', 1, 0.00::NUMERIC(6,2), DATE '1976-12-17', NULL::DATE),
        ('M1', 'MAI',     2, 2.40::NUMERIC(6,2), DATE '1976-12-17', NULL::DATE),
        ('M1', 'KHR',     3, 5.10::NUMERIC(6,2), DATE '1976-12-17', NULL::DATE)
) AS v(line_code, station_code, station_sequence, distance_from_origin_km, valid_from, valid_to)
WHERE NOT EXISTS (
    SELECT 1
    FROM subway.line_station ls
    WHERE ls.line_id = (
        SELECT l.line_id
        FROM subway.line l
        WHERE l.line_code = v.line_code
    )
      AND ls.station_id = (
        SELECT s.station_id
        FROM subway.station s
        WHERE s.station_code = v.station_code
    )
      AND ls.valid_from = v.valid_from
)
RETURNING
    line_station_id,
    line_id,
    station_id,
    station_sequence,
    distance_from_origin_km,
    valid_from,
    valid_to;

SELECT *
FROM subway.line_station;


-- 10) track_segment

INSERT INTO subway.track_segment (
    asset_id,          -- FK
    from_station_id,   -- FK
    to_station_id,     -- FK
    length_km,
    opened_on,
    closed_on
)
SELECT
    a.asset_id,
    (
        SELECT s.station_id
        FROM subway.station s
        WHERE s.station_code = v.from_station_code
    ) AS from_station_id,
    (
        SELECT s.station_id
        FROM subway.station s
        WHERE s.station_code = v.to_station_code
    ) AS to_station_id,
    v.length_km,
    v.opened_on,
    v.closed_on
FROM (
    VALUES
		(TIMESTAMPTZ '2026-01-01 09:10:00+02', 'MAI_HUB', 'MAI',     2.40::NUMERIC(6,2), DATE '1960-11-06', NULL::DATE),
        (TIMESTAMPTZ '2026-01-01 09:35:00+02', 'MAI',     'KHR',     2.70::NUMERIC(6,2), DATE '1960-11-06', NULL::DATE),
        (TIMESTAMPTZ '2026-01-01 09:40:00+02', 'KHR',     'MAI_HUB', 1.95::NUMERIC(6,2), DATE '1960-11-06', NULL::DATE)
) AS v(created_at, from_station_code, to_station_code, length_km, opened_on, closed_on)
INNER JOIN subway.asset a
    ON a.asset_type = 'track_segment'
    AND a.created_at = v.created_at
WHERE NOT EXISTS (
    SELECT 1
    FROM subway.track_segment ts
    WHERE ts.from_station_id = (
        SELECT s.station_id
        FROM subway.station s
        WHERE s.station_code = v.from_station_code
    )
      AND ts.to_station_id = (
        SELECT s.station_id
        FROM subway.station s
        WHERE s.station_code = v.to_station_code
    )
      AND ts.opened_on = v.opened_on
)
RETURNING
    track_segment_id,
    asset_id,
    from_station_id,
    to_station_id,
    length_km,
    opened_on,
    closed_on;

SELECT *
FROM subway.track_segment;


-- 11) trip

INSERT INTO subway.trip (
    schedule_version_id,    	 -- FK
    origin_station_id,       	 -- FK
    destination_station_id,  	 -- FK
    trip_code,
    direction,
    planned_departure_time,
    planned_arrival_time,
    arrival_day_offset
)
SELECT
    (
        SELECT sv.schedule_version_id
        FROM subway.schedule_version sv
        WHERE sv.schedule_name = v.schedule_name
    ) AS schedule_version_id,
    (
        SELECT s.station_id
        FROM subway.station s
        WHERE s.station_code = v.origin_station_code
    ) AS origin_station_id,
    (
        SELECT s.station_id
        FROM subway.station s
        WHERE s.station_code = v.destination_station_code
    ) AS destination_station_id,
    v.trip_code,
    v.direction,
    v.planned_departure_time,
    v.planned_arrival_time,
    v.arrival_day_offset
FROM (
    VALUES
        ('Weekday Winter Schedule 2026', 'MAI_HUB', 'KHR',     'M1_0805_OB', 'outbound', TIME '08:05:00', TIME '08:42:00', 0::SMALLINT),
        ('Weekday Winter Schedule 2026', 'KHR',     'MAI_HUB', 'M1_0845_IB', 'inbound',  TIME '08:45:00', TIME '09:22:00', 0::SMALLINT),
        ('Holiday Service Plan',         'MAI_HUB', 'KHR',     'M2_2350_OB', 'outbound', TIME '23:50:00', TIME '00:20:00', 1::SMALLINT)
) AS v(schedule_name, origin_station_code, destination_station_code, trip_code, direction, planned_departure_time, planned_arrival_time, arrival_day_offset)
WHERE NOT EXISTS (
    SELECT 1
    FROM subway.trip t
    WHERE t.schedule_version_id = (
        SELECT sv.schedule_version_id
        FROM subway.schedule_version sv
        WHERE sv.schedule_name = v.schedule_name
    )
      AND t.trip_code = v.trip_code
)
RETURNING
    trip_id,
    schedule_version_id,
    origin_station_id,
    destination_station_id,
    trip_code,
    direction,
    planned_departure_time,
    planned_arrival_time,
    arrival_day_offset;

SELECT *
FROM subway.trip;


-- 12) maintenance_event

INSERT INTO subway.maintenance_event (
    asset_id,              		-- FK
    maintenance_type_id,   		-- FK
    scheduled_start,
    scheduled_end,
    actual_start,
    actual_end,
    maintenance_status,
    notes
)
SELECT
    a.asset_id,
    (
        SELECT mt.maintenance_type_id
        FROM subway.maintenance_type mt
        WHERE mt.maintenance_type_name = v.maintenance_type_name
    ) AS maintenance_type_id,
    v.scheduled_start,
    v.scheduled_end,
    v.actual_start,
    v.actual_end,
    v.maintenance_status,
    v.notes
FROM (
    VALUES
        ('station', TIMESTAMPTZ '2026-01-01 09:00:00+02', 'Inspection',
         TIMESTAMPTZ '2026-03-15 01:00:00+02', TIMESTAMPTZ '2026-03-15 04:00:00+02',
         TIMESTAMPTZ '2026-03-15 01:10:00+02', TIMESTAMPTZ '2026-03-15 03:50:00+02',
         'completed', 'Routine overnight inspection'),
        ('train', TIMESTAMPTZ '2026-01-01 09:05:00+02', 'Cleaning',
         TIMESTAMPTZ '2026-03-18 00:30:00+02', TIMESTAMPTZ '2026-03-18 05:30:00+02',
         TIMESTAMPTZ '2026-03-18 00:40:00+02', NULL::TIMESTAMPTZ,
         'in_progress', 'Brake system maintenance'),
        ('track_segment', TIMESTAMPTZ '2026-01-01 09:10:00+02', 'Repair',
         TIMESTAMPTZ '2026-03-20 02:00:00+02', TIMESTAMPTZ '2026-03-20 06:00:00+02',
         NULL::TIMESTAMPTZ, NULL::TIMESTAMPTZ,
         'planned', 'Scheduled track repair')
) AS v(asset_type, created_at, maintenance_type_name, scheduled_start, scheduled_end, actual_start, actual_end, maintenance_status, notes)
INNER JOIN subway.asset a
    ON a.asset_type = v.asset_type
    AND a.created_at = v.created_at
WHERE NOT EXISTS (
    SELECT 1
    FROM subway.maintenance_event me
    WHERE me.asset_id = a.asset_id
      AND me.maintenance_type_id = (
          SELECT mt.maintenance_type_id
          FROM subway.maintenance_type mt
          WHERE mt.maintenance_type_name = v.maintenance_type_name
      )
      AND me.scheduled_start = v.scheduled_start
)
RETURNING
    maintenance_event_id,
    asset_id,
    maintenance_type_id,
    scheduled_start,
    scheduled_end,
    actual_start,
    actual_end,
    maintenance_status,
    notes;

SELECT *
FROM subway.maintenance_event;
SELECT *
FROM subway.asset a ;

COMMIT;

-- ===============================
-- Part 4. Transactional and linking tables
-- ===============================

SELECT *
FROM subway.trip_stop;
SELECT *
FROM subway.train_assignment;
SELECT *
FROM subway.ticket_sale;


INSERT INTO subway.trip_stop (
    trip_id,             -- composite PK, FK
    stop_sequence,       -- composite PK
    line_station_id,     -- FK
    arrival_offset,
    departure_offset
)
SELECT
    (
        SELECT t.trip_id
        FROM subway.trip t
        WHERE t.trip_code = v.trip_code
    ) AS trip_id,
    v.stop_sequence,
    (
        SELECT ls.line_station_id
        FROM subway.line_station ls
        INNER JOIN subway.station s
        	ON s.station_id = ls.station_id
        WHERE s.station_code = v.station_code
        	AND ls.line_id = (
              SELECT l.line_id
              FROM subway.line l
              WHERE l.line_code = v.line_code
          )
    ) AS line_station_id,
    v.arrival_offset,
    v.departure_offset
FROM (
    VALUES
        -- Trip M1_0805_OB: MAI_HUB --> MAI --> KHR
        ('M1_0805_OB', 'M1', 'MAI_HUB', 1::SMALLINT, NULL::INTERVAL,      INTERVAL '00:00:00'),
        ('M1_0805_OB', 'M1', 'MAI',     2::SMALLINT, INTERVAL '00:04:00', INTERVAL '00:05:00'),
        ('M1_0805_OB', 'M1', 'KHR',     3::SMALLINT, INTERVAL '00:09:00', INTERVAL '00:10:00'),
        -- Trip M1_0845_IB: KHR --> MAI --> MAI_HUB
        ('M1_0845_IB', 'M1', 'KHR',     1::SMALLINT, NULL::INTERVAL,      INTERVAL '00:00:00'),
        ('M1_0845_IB', 'M1', 'MAI',     2::SMALLINT, INTERVAL '00:04:00', INTERVAL '00:05:00'),
        ('M1_0845_IB', 'M1', 'MAI_HUB', 3::SMALLINT, INTERVAL '00:09:00', NULL::INTERVAL)
) AS v(trip_code, line_code, station_code, stop_sequence, arrival_offset, departure_offset)
WHERE NOT EXISTS (
    SELECT 1
    FROM subway.trip_stop ts
    WHERE ts.trip_id = (
        SELECT t.trip_id
        FROM subway.trip t
        WHERE t.trip_code = v.trip_code
    )
      AND ts.stop_sequence = v.stop_sequence
)
RETURNING
    trip_id,
    stop_sequence,
    line_station_id,
    arrival_offset,
    departure_offset;

SELECT *
FROM subway.trip_stop
ORDER BY trip_id, stop_sequence;


-- 14) train_assignment
-- Relationships are preserved by resolving trip_id and train_id from already existing business keys
-- (trip_code and fleet_number) instead of hardcoding technical IDs.

INSERT INTO subway.train_assignment (
    trip_id,         	-- FK
    train_id,        	-- FK
    valid_from,
    valid_to
)
SELECT
    (
        SELECT t.trip_id
        FROM subway.trip t
        WHERE t.trip_code = v.trip_code
    ) AS trip_id,
    (
        SELECT tr.train_id
        FROM subway.train tr
        WHERE tr.fleet_number = v.fleet_number
    ) AS train_id,
    v.valid_from,
    v.valid_to
FROM (
    VALUES
        ('M1_0805_OB', '1207', DATE '2026-01-01', DATE '2026-03-31'),
        ('M1_0805_OB', '1215', DATE '2026-04-01', NULL::DATE),
        ('M1_0845_IB', '0988', DATE '2026-01-01', NULL::DATE)
) AS v(trip_code, fleet_number, valid_from, valid_to)
WHERE NOT EXISTS (
    SELECT 1
    FROM subway.train_assignment ta
    WHERE ta.trip_id = (
        SELECT t.trip_id
        FROM subway.trip t
        WHERE t.trip_code = v.trip_code
    )
      AND ta.valid_from = v.valid_from
)
RETURNING
    train_assignment_id,
    trip_id,
    train_id,
    valid_from,
    valid_to;

SELECT *
FROM subway.train_assignment
ORDER BY train_assignment_id;


-- 15) ticket_sale
-- We resolve ticket_offer_id from ticket_type_name and ticket offer start date,
-- and station_id from station_code, so inserted data stays consistent with parent tables.
-- sale_station_id is NULL for app sales according to the logical model

INSERT INTO subway.ticket_sale (
    ticket_offer_id,     	-- FK
    sale_station_id,     	-- FK
    ticket_number,
    sold_at,
    valid_from,
    valid_to,
    sale_channel
)
SELECT
    (
        SELECT toff.ticket_offer_id
        FROM subway.ticket_offer toff
        INNER JOIN subway.ticket_type tt
            ON tt.ticket_type_id = toff.ticket_type_id
        WHERE tt.ticket_type_name = v.ticket_type_name
        	AND toff.valid_from = v.offer_valid_from
    ) AS ticket_offer_id,
    (
        SELECT s.station_id
        FROM subway.station s
        WHERE s.station_code = v.station_code
    ) AS sale_station_id,
    v.ticket_number,
    v.sold_at,
    v.valid_from,
    v.valid_to,
    v.sale_channel
FROM (
    VALUES
        ('Single Ride',  DATE '2026-01-01', 'MAI_HUB', 'TCK-2026-000001',
         TIMESTAMPTZ '2026-03-10 08:15:00+02',
         TIMESTAMPTZ '2026-03-10 08:15:00+02',
         TIMESTAMPTZ '2026-03-10 09:45:00+02',
         'kiosk'),
        ('Day Pass',     DATE '2026-01-01', NULL,      'TCK-2026-000002',
         TIMESTAMPTZ '2026-03-10 09:05:00+02',
         TIMESTAMPTZ '2026-03-10 09:05:00+02',
         TIMESTAMPTZ '2026-03-11 09:05:00+02',
         'app'),
        ('Single Ride',  DATE '2026-01-01', 'KHR',     'TCK-2026-000003',
         TIMESTAMPTZ '2026-03-10 10:20:00+02',
         TIMESTAMPTZ '2026-03-10 10:20:00+02',
         TIMESTAMPTZ '2026-03-10 11:50:00+02',
         'cash_desk')
) AS v(ticket_type_name, offer_valid_from, station_code, ticket_number, sold_at, valid_from, valid_to, sale_channel)
WHERE NOT EXISTS (
    SELECT 1
    FROM subway.ticket_sale ts
    WHERE ts.ticket_number = v.ticket_number
)
RETURNING
    ticket_sale_id,
    ticket_offer_id,
    sale_station_id,
    ticket_number,
    sold_at,
    valid_from,
    valid_to,
    sale_channel;

SELECT *
FROM subway.ticket_sale
ORDER BY ticket_sale_id;

COMMIT;

-- ===============================
-- Block 7. Add record_ts column to all tables
-- ===============================

BEGIN;

ALTER TABLE subway.line
ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;

ALTER TABLE subway.asset
ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;

ALTER TABLE subway.maintenance_type
ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;

ALTER TABLE subway.ticket_type
ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;

ALTER TABLE subway.train
ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;

ALTER TABLE subway.station
ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;

ALTER TABLE subway.ticket_offer
ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;

ALTER TABLE subway.schedule_version
ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;

ALTER TABLE subway.line_station
ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;

ALTER TABLE subway.track_segment
ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;

ALTER TABLE subway.trip
ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;

ALTER TABLE subway.maintenance_event
ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;

ALTER TABLE subway.trip_stop
ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;

ALTER TABLE subway.train_assignment
ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;

ALTER TABLE subway.ticket_sale
ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;

COMMIT;

-- ==== quick check of record_ts
SELECT record_ts
FROM subway.ticket_sale;
SELECT record_ts
FROM subway.line;
SELECT record_ts
FROM subway.asset;
SELECT record_ts
FROM subway.train_assignment;
