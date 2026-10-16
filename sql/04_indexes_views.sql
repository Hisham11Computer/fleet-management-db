-- =====================================================
-- 04_indexes_views.sql : indexing benchmark + reporting views
-- Run AFTER seeding so the benchmark is meaningful.
-- =====================================================
USE RouteMasterX;

-- ---------- Benchmark: filter on speed ----------
-- Before: type = ALL (full table scan, every row examined)
EXPLAIN SELECT * FROM GPS_Live_Logs WHERE speed >= 120.00;

CREATE INDEX idx_gps_speed ON GPS_Live_Logs (speed);

-- After: type = range, key = idx_gps_speed (only matching rows examined)
EXPLAIN SELECT * FROM GPS_Live_Logs WHERE speed >= 120.00;

-- ---------- Indexes that serve the real queries ----------
-- route / "latest position" lookups per trip, ordered by time
CREATE INDEX idx_gps_trip_time ON GPS_Live_Logs (trip_id, logged_at);
-- daily reports filter violations by time range
CREATE INDEX idx_viol_time ON Speed_Violations (violation_time);

-- ---------- Reporting views ----------
CREATE OR REPLACE VIEW View_Daily_High_Risk_Drivers AS
SELECT
    d.full_name AS driver_name,
    v.plate_number,
    sv.exceeded_speed,
    sv.speed_limit,
    sv.violation_time
FROM Speed_Violations sv
JOIN Trips    t ON t.trip_id    = sv.trip_id
JOIN Drivers  d ON d.driver_id  = t.driver_id
JOIN Vehicles v ON v.vehicle_id = t.vehicle_id
WHERE sv.violation_time >= CURDATE()
  AND sv.violation_time <  CURDATE() + INTERVAL 1 DAY;

CREATE OR REPLACE VIEW View_Driver_Risk_Today AS
SELECT
    d.driver_id,
    d.full_name AS driver_name,
    COUNT(*)    AS violations_today,
    MAX(sv.exceeded_speed) AS max_speed_kmh
FROM Speed_Violations sv
JOIN Trips   t ON t.trip_id   = sv.trip_id
JOIN Drivers d ON d.driver_id = t.driver_id
WHERE sv.violation_time >= CURDATE()
  AND sv.violation_time <  CURDATE() + INTERVAL 1 DAY
GROUP BY d.driver_id, d.full_name;

SELECT * FROM View_Driver_Risk_Today ORDER BY violations_today DESC LIMIT 10;
