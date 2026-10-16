-- =====================================================
-- 06_geo_queries.sql : the geospatial layer
-- Points are POINT(lng lat); ST_Distance_Sphere returns METERS.
-- =====================================================
USE RouteMasterX;

DROP PROCEDURE IF EXISTS FindNearestVehicles;
DROP PROCEDURE IF EXISTS VehiclesWithinRadius;

-- Latest known position of every vehicle that is on an Active trip
CREATE OR REPLACE VIEW View_Latest_Vehicle_Positions AS
SELECT
    x.trip_id,
    v.plate_number,
    d.full_name AS driver_name,
    ST_Y(x.current_location) AS lat,
    ST_X(x.current_location) AS lng,
    x.speed,
    x.logged_at
FROM (
    SELECT g.trip_id, g.current_location, g.speed, g.logged_at,
           ROW_NUMBER() OVER (PARTITION BY g.trip_id ORDER BY g.logged_at DESC, g.log_id DESC) AS rn
    FROM GPS_Live_Logs g
    JOIN Trips t0 ON t0.trip_id = g.trip_id AND t0.trip_status = 'Active'
) x
JOIN Trips    t ON t.trip_id    = x.trip_id
JOIN Vehicles v ON v.vehicle_id = t.vehicle_id
JOIN Drivers  d ON d.driver_id  = t.driver_id
WHERE x.rn = 1;

-- Distance travelled per trip = sum of the distances between consecutive GPS points
CREATE OR REPLACE VIEW View_Trip_Distance AS
SELECT trip_id, COUNT(*) AS gps_points, ROUND(SUM(segment_m) / 1000, 2) AS distance_km
FROM (
    SELECT g.trip_id,
           ST_Distance_Sphere(
               g.current_location,
               LAG(g.current_location) OVER (PARTITION BY g.trip_id ORDER BY g.logged_at, g.log_id)
           ) AS segment_m
    FROM GPS_Live_Logs g
) s
GROUP BY trip_id;

-- Speeding hotspots on a ~1 km grid (0.01 degree cells)
CREATE OR REPLACE VIEW View_Speeding_Hotspots AS
SELECT
    ROUND(ST_Y(g.current_location), 2) AS grid_lat,
    ROUND(ST_X(g.current_location), 2) AS grid_lng,
    COUNT(*)                           AS violations,
    MAX(sv.exceeded_speed)             AS max_speed_kmh
FROM Speed_Violations sv
JOIN GPS_Live_Logs g ON g.log_id = sv.log_id
GROUP BY grid_lat, grid_lng;

DELIMITER $$

-- N closest vehicles (currently on the road) to a point
CREATE PROCEDURE FindNearestVehicles(IN p_lat DECIMAL(9,6), IN p_lng DECIMAL(9,6), IN p_limit INT)
BEGIN
    SELECT trip_id, plate_number, driver_name,
           ROUND(ST_Distance_Sphere(POINT(lng, lat), POINT(p_lng, p_lat)) / 1000, 2) AS distance_km,
           speed, logged_at
    FROM View_Latest_Vehicle_Positions
    ORDER BY distance_km ASC
    LIMIT p_limit;
END$$

-- Geofence-style query: every vehicle inside a circle
CREATE PROCEDURE VehiclesWithinRadius(IN p_lat DECIMAL(9,6), IN p_lng DECIMAL(9,6), IN p_radius_km DECIMAL(8,2))
BEGIN
    SELECT trip_id, plate_number, driver_name,
           ROUND(ST_Distance_Sphere(POINT(lng, lat), POINT(p_lng, p_lat)) / 1000, 2) AS distance_km
    FROM View_Latest_Vehicle_Positions
    WHERE ST_Distance_Sphere(POINT(lng, lat), POINT(p_lng, p_lat)) <= p_radius_km * 1000
    ORDER BY distance_km ASC;
END$$

DELIMITER ;

-- Demo (Tahrir Square, Cairo)
CALL FindNearestVehicles(30.0444, 31.2357, 5);
CALL VehiclesWithinRadius(30.0444, 31.2357, 10);
SELECT * FROM View_Trip_Distance ORDER BY distance_km DESC LIMIT 10;
SELECT * FROM View_Speeding_Hotspots ORDER BY violations DESC LIMIT 10;
