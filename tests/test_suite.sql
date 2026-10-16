-- =====================================================
-- Self-checking tests. Run on a freshly built database.
-- NOTE: the tests create a few rows (a trip and two shipments).
-- =====================================================
USE RouteMasterX;

DROP TEMPORARY TABLE IF EXISTS _test_results;
CREATE TEMPORARY TABLE _test_results (test_name VARCHAR(120), passed BOOLEAN);

DROP PROCEDURE IF EXISTS RunTests;
DELIMITER $$
CREATE PROCEDURE RunTests()
BEGIN
    DECLARE v_failed   INT DEFAULT 0;
    DECLARE v_vehicle  INT;
    DECLARE v_driver   INT;
    DECLARE v_trip     INT;
    DECLARE v_shipment INT;
    DECLARE v_msg      VARCHAR(255);
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_failed = 1;

    -- ---------- seed data ----------
    INSERT INTO _test_results VALUES ('seed: 500 vehicles', (SELECT COUNT(*) FROM Vehicles) = 500);
    INSERT INTO _test_results VALUES ('seed: 500 drivers',  (SELECT COUNT(*) FROM Drivers) = 500);
    INSERT INTO _test_results VALUES ('seed: at least 5000 GPS logs', (SELECT COUNT(*) FROM GPS_Live_Logs) >= 5000);
    INSERT INTO _test_results VALUES ('seed: 100 active trips', (SELECT COUNT(*) FROM Trips WHERE trip_status = 'Active') = 100);

    -- ---------- speed trigger ----------
    INSERT INTO _test_results VALUES ('trigger: every violation exceeds its limit',
        NOT EXISTS (SELECT 1 FROM Speed_Violations WHERE exceeded_speed <= speed_limit));
    INSERT INTO _test_results VALUES ('trigger: violations match readings over the limit',
        (SELECT COUNT(*) FROM GPS_Live_Logs g
           JOIN Trips t ON t.trip_id = g.trip_id
           JOIN Vehicles v ON v.vehicle_id = t.vehicle_id
           JOIN Vehicle_Types vt ON vt.type_id = v.type_id
          WHERE g.speed > vt.speed_limit_kmh) = (SELECT COUNT(*) FROM Speed_Violations));

    -- ---------- status automation ----------
    INSERT INTO _test_results VALUES ('status: active trips => vehicles In Trip',
        NOT EXISTS (SELECT 1 FROM Trips t JOIN Vehicles v ON v.vehicle_id = t.vehicle_id
                    WHERE t.trip_status = 'Active' AND v.status <> 'In Trip'));
    INSERT INTO _test_results VALUES ('status: active trips => drivers On Trip',
        NOT EXISTS (SELECT 1 FROM Trips t JOIN Drivers d ON d.driver_id = t.driver_id
                    WHERE t.trip_status = 'Active' AND d.status <> 'On Trip'));

    -- ---------- double booking is rejected ----------
    SELECT vehicle_id INTO v_vehicle FROM Trips WHERE trip_status = 'Active' ORDER BY trip_id LIMIT 1;
    SELECT driver_id  INTO v_driver  FROM Drivers WHERE status = 'Available' ORDER BY driver_id LIMIT 1;
    SET v_failed = 0;
    CALL StartTrip(v_vehicle, v_driver, v_trip);
    INSERT INTO _test_results VALUES ('rule: busy vehicle cannot start another trip', v_failed = 1);

    -- ---------- trip lifecycle ----------
    SELECT vehicle_id INTO v_vehicle FROM Vehicles WHERE status = 'Available' ORDER BY vehicle_id LIMIT 1;
    SELECT driver_id  INTO v_driver  FROM Drivers  WHERE status = 'Available' ORDER BY driver_id LIMIT 1;
    SET v_failed = 0;
    CALL StartTrip(v_vehicle, v_driver, v_trip);
    INSERT INTO _test_results VALUES ('lifecycle: StartTrip succeeds', v_failed = 0 AND v_trip IS NOT NULL);
    INSERT INTO _test_results VALUES ('lifecycle: start marks vehicle In Trip',
        (SELECT status FROM Vehicles WHERE vehicle_id = v_vehicle) = 'In Trip');

    CALL CompleteTrip(v_trip);
    INSERT INTO _test_results VALUES ('lifecycle: completion sets status and end_time',
        (SELECT trip_status FROM Trips WHERE trip_id = v_trip) = 'Completed'
        AND (SELECT end_time FROM Trips WHERE trip_id = v_trip) IS NOT NULL);
    INSERT INTO _test_results VALUES ('lifecycle: completion frees the vehicle',
        (SELECT status FROM Vehicles WHERE vehicle_id = v_vehicle) = 'Available');
    INSERT INTO _test_results VALUES ('lifecycle: completion frees the driver',
        (SELECT status FROM Drivers WHERE driver_id = v_driver) = 'Available');

    SET v_failed = 0;
    CALL CompleteTrip(v_trip);
    INSERT INTO _test_results VALUES ('lifecycle: completing twice is rejected', v_failed = 1);

    -- ---------- shipment assignment ----------
    INSERT INTO Shipments (description, weight) VALUES ('Test cargo', 400.00);
    SET v_shipment = LAST_INSERT_ID();
    CALL AssignShipmentToDriver(v_shipment, v_msg);
    INSERT INTO _test_results VALUES ('shipment: normal shipment is assigned',
        v_msg LIKE 'Success%' AND (SELECT status FROM Shipments WHERE shipment_id = v_shipment) = 'Assigned');

    INSERT INTO Shipments (description, weight) VALUES ('Too heavy', 60000.00);
    SET v_shipment = LAST_INSERT_ID();
    CALL AssignShipmentToDriver(v_shipment, v_msg);
    INSERT INTO _test_results VALUES ('shipment: overweight shipment is rejected',
        v_msg LIKE 'Error%' AND (SELECT status FROM Shipments WHERE shipment_id = v_shipment) = 'Pending');

    INSERT INTO _test_results VALUES ('shipment: no vehicle is ever over capacity',
        NOT EXISTS (
            SELECT 1 FROM (
                SELECT t.trip_id, SUM(s.weight) AS w, MAX(v.max_weight_capacity) AS c
                FROM Trips t
                JOIN Vehicles v  ON v.vehicle_id = t.vehicle_id
                JOIN Shipments s ON s.assigned_trip_id = t.trip_id
                GROUP BY t.trip_id
            ) x WHERE x.w > x.c));

    -- ---------- geo ----------
    INSERT INTO _test_results VALUES ('geo: Cairo-Alexandria distance is about 180 km',
        ST_Distance_Sphere(POINT(31.2357, 30.0444), POINT(29.9187, 31.2001)) / 1000 BETWEEN 170 AND 190);
    INSERT INTO _test_results VALUES ('geo: one latest position per active trip',
        (SELECT COUNT(*) FROM View_Latest_Vehicle_Positions) = (SELECT COUNT(*) FROM Trips WHERE trip_status = 'Active'));
    INSERT INTO _test_results VALUES ('geo: trip distances are positive',
        (SELECT MIN(distance_km) FROM View_Trip_Distance) > 0);
END$$
DELIMITER ;

CALL RunTests();
DROP PROCEDURE RunTests;

SELECT test_name, IF(passed, 'PASS', 'FAIL') AS result FROM _test_results;
SELECT CONCAT(SUM(passed), ' / ', COUNT(*), ' tests passed') AS summary FROM _test_results;
