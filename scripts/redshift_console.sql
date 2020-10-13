-- Create new schema in Redshift DB
DROP SCHEMA IF EXISTS sensor CASCADE;
CREATE SCHEMA sensor;
SET search_path = sensor;

-- Create (6) tables in Redshift DB
CREATE TABLE message -- streaming data table
(
    id      BIGINT IDENTITY (1, 1),                                   -- message id
    guid    VARCHAR(36)   NOT NULL,                                   -- device guid
    ts      BIGINT        NOT NULL DISTKEY SORTKEY,                   -- epoch in seconds
    temp    NUMERIC(5, 2) NOT NULL,                                   -- temperature reading
    created TIMESTAMP DEFAULT ('now'::text)::timestamp with time zone -- row created at
);

CREATE TABLE location -- dimension table
(
    id          INTEGER        NOT NULL DISTKEY SORTKEY, -- location id
    long        NUMERIC(10, 7) NOT NULL,                 -- longitude
    lat         NUMERIC(10, 7) NOT NULL,                 -- latitude
    description VARCHAR(256)                             -- location description
);

CREATE TABLE history -- dimension table
(
    id            INTEGER     NOT NULL DISTKEY SORTKEY, -- history id
    serviced      BIGINT      NOT NULL,                 -- service date
    action        VARCHAR(20) NOT NULL,                 -- INSTALLED, CALIBRATED, FIRMWARE UPGRADED, DECOMMISSIONED, OTHER
    technician_id INTEGER     NOT NULL,                 -- technician id
    notes         VARCHAR(256)                          -- notes
);

CREATE TABLE sensor -- dimension table
(
    id     INTEGER     NOT NULL DISTKEY SORTKEY, -- sensor id
    guid   VARCHAR(36) NOT NULL,                 -- device guid
    mac    VARCHAR(18) NOT NULL,                 -- mac address
    sku    VARCHAR(18) NOT NULL,                 -- product sku
    upc    VARCHAR(12) NOT NULL,                 -- product upc
    active BOOLEAN DEFAULT TRUE,                 --active status
    notes  VARCHAR(256)                          -- notes

);

CREATE TABLE manufacturer -- dimension table
(
    id      INTEGER      NOT NULL DISTKEY SORTKEY, -- manufacturer id
    name    VARCHAR(100) NOT NULL,                 -- company name
    website VARCHAR(100) NOT NULL,                 -- company website
    notes   VARCHAR(256)                           -- notes
);

CREATE TABLE sensors -- fact table
(
    id              BIGINT IDENTITY (1, 1) DISTKEY SORTKEY, -- fact id
    sensor_id       INTEGER     NOT NULL,                   -- sensor id
    manufacturer_id INTEGER     NOT NULL,                   -- manufacturer id
    location_id     INTEGER     NOT NULL,                   -- location id
    history_id      BIGINT      NOT NULL,                   -- history id
    message_guid    VARCHAR(36) NOT NULL                    -- sensor guid
);

-- Copy sample data to tables from S3
-- ** MUST FIRST CHANGE your_bucket_name and cluster_permissions_role_arn **
TRUNCATE TABLE history;
COPY history (id, serviced, action, technician_id, notes)
    FROM 's3://your_bucket_name/history/'
    CREDENTIALS 'aws_iam_role=cluster_permissions_role_arn'
    CSV IGNOREHEADER 1;

TRUNCATE TABLE location;
COPY location (id, long, lat, description)
    FROM 's3://your_bucket_name/location/'
    CREDENTIALS 'aws_iam_role=cluster_permissions_role_arn'
    CSV IGNOREHEADER 1;

TRUNCATE TABLE sensor;
COPY sensor (id, guid, mac, sku, upc, active, notes)
    FROM 's3://your_bucket_name/sensor/'
    CREDENTIALS 'aws_iam_role=cluster_permissions_role_arn'
    CSV IGNOREHEADER 1;

TRUNCATE TABLE manufacturer;
COPY manufacturer (id, name, website, notes)
    FROM 's3://your_bucket_name/manufacturer/'
    CREDENTIALS 'aws_iam_role=cluster_permissions_role_arn'
    CSV IGNOREHEADER 1;

TRUNCATE TABLE sensors;
COPY sensors (sensor_id, manufacturer_id, location_id, history_id, message_guid)
    FROM 's3://your_bucket_name/sensors/'
    CREDENTIALS 'aws_iam_role=cluster_permissions_role_arn'
    CSV IGNOREHEADER 1;

SELECT COUNT(*) FROM history; -- 30
SELECT COUNT(*) FROM location; -- 6
SELECT COUNT(*) FROM sensor; -- 6
SELECT COUNT(*) FROM manufacturer; --1
SELECT COUNT(*) FROM sensors; -- 30

SELECT COUNT(*) FROM message;


-- View 1: Sensor details
DROP VIEW IF EXISTS sensor_msg_detail;
CREATE OR REPLACE VIEW sensor_msg_detail AS
SELECT ('1970-01-01'::date + e.ts * interval '1 second')       AS recorded,
       e.temp,
       s.guid,
       s.sku,
       s.mac,
       l.lat,
       l.long,
       l.description                                           AS location,
       ('1970-01-01'::date + h.serviced * interval '1 second') AS installed,
       e.created                                               AS redshift
FROM sensors f
         INNER JOIN sensor s ON (f.sensor_id = s.id)
         INNER JOIN history h ON (f.history_id = h.id)
         INNER JOIN location l ON (f.location_id = l.id)
         INNER JOIN manufacturer m ON (f.manufacturer_id = m.id)
         INNER JOIN message e ON (f.message_guid = e.guid)
WHERE s.active IS TRUE
  AND h.action = 'INSTALLED'
ORDER BY f.id;

-- View 2: Message count per sensor
DROP VIEW IF EXISTS sensor_msg_count;
CREATE OR REPLACE VIEW sensor_msg_count AS
SELECT count(e.temp) AS msg_count,
       s.guid,
       l.lat,
       l.long,
       l.description AS location
FROM sensors f
         INNER JOIN sensor s ON (f.sensor_id = s.id)
         INNER JOIN history h ON (f.history_id = h.id)
         INNER JOIN location l ON (f.location_id = l.id)
         INNER JOIN message e ON (f.message_guid = e.guid)
WHERE s.active IS TRUE
  AND h.action = 'INSTALLED'
GROUP BY s.guid, l.description, l.lat, l.long
ORDER BY msg_count, s.guid;

-- View 3: Average temperature per sensor (all data)
DROP VIEW IF EXISTS sensor_avg_temp;
CREATE OR REPLACE VIEW sensor_avg_temp AS
SELECT avg(e.temp)   AS avg_temp,
       count(s.guid) AS msg_count,
       s.guid,
       l.lat,
       l.long,
       l.description AS location
FROM sensors f
         INNER JOIN sensor s ON (f.sensor_id = s.id)
         INNER JOIN history h ON (f.history_id = h.id)
         INNER JOIN location l ON (f.location_id = l.id)
         INNER JOIN message e ON (f.message_guid = e.guid)
WHERE s.active IS TRUE
  AND h.action = 'INSTALLED'
GROUP BY s.guid, l.description, l.lat, l.long
ORDER BY avg_temp, s.guid;

-- View 4: Average temperature per sensor (last 30 minutes)
DROP VIEW IF EXISTS sensor_avg_temp_current;
CREATE OR REPLACE VIEW sensor_avg_temp_current AS
SELECT avg(e.temp)   AS avg_temp,
       count(s.guid) AS msg_count,
       s.guid,
       l.lat,
       l.long,
       l.description AS location
FROM sensors f
         INNER JOIN sensor s ON (f.sensor_id = s.id)
         INNER JOIN history h ON (f.history_id = h.id)
         INNER JOIN location l ON (f.location_id = l.id)
         INNER JOIN (SELECT ('1970-01-01'::date + ts * interval '1 second') AS recorded_time,
                            guid,
                            temp
                     FROM message
                     WHERE DATEDIFF(minute, recorded_time, GETDATE()) <= 30) e ON (f.message_guid = e.guid)
WHERE s.active IS TRUE
  AND h.action = 'INSTALLED'
GROUP BY s.guid, l.description, l.lat, l.long
ORDER BY avg_temp, s.guid;

-- View 5: Latency between recorded and written to Redshift
DROP VIEW IF EXISTS message_latency;
CREATE OR REPLACE VIEW message_latency AS
SELECT ('1970-01-01'::date + ts * interval '1 second') AS recorded_time,
       created                                         AS redshift_time,
       DATEDIFF(seconds, recorded_time, redshift_time) AS diff_seconds
FROM message
ORDER BY diff_seconds;

SELECT COUNT(*)
FROM sensor_msg_detail;

SELECT *
FROM sensor_msg_detail;

-- Troubleshooting COPY from S3 to Redshift
TRUNCATE TABLE message;
COPY message (ts, guid, temp)
    FROM 's3://redshift-stack-databucket-your_bucket/message/manifests/2020/03/02/20/redshift-delivery-stream-2020-03-02-20-51-34-94629991-9aa7-48d9-900e-8efadfbfdc7e'
    CREDENTIALS 'aws_iam_role=arn:aws:iam::your_account:role/ClusterPermissionsRole'
    JSON 'auto' GZIP;

COPY sensor.message (ts, guid, temp)
    FROM 's3://redshift-stack-databucket-your_bucket/message/manifests/2020/03/02/20/redshift-delivery-stream-2020-03-02-20-51-34-94629991-9aa7-48d9-900e-8efadfbfdc7e'
    CREDENTIALS 'aws_iam_role=arn:aws:iam::your_account:role/ClusterPermissionsRole'
    MANIFEST JSON 'auto' GZIP;

SELECT *
FROM pg_catalog.stl_load_errors
ORDER BY starttime DESC
LIMIT 10;

SELECT *
FROM pg_catalog.stl_connection_log;

SELECT DISTINCT remotehost
FROM pg_catalog.stl_connection_log
ORDER BY remotehost DESC;

SELECT *
FROM pg_catalog.stl_connection_log
WHERE remotehost LIKE '::ffff:52.70.63%'
ORDER BY recordtime DESC;

SELECT *
FROM pg_catalog.stl_loaderror_detail;
