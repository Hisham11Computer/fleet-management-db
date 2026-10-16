-- =====================================================
-- 03_seed.sql : realistic sample data
--   500 vehicles, 500 drivers, 100 active trips x 50 GPS logs = 5,000 logs
-- GPS logs are a random walk around Cairo: the position moves according to the
-- speed and heading, so distances computed later are realistic.
-- =====================================================
USE RouteMasterX;

INSERT INTO Vehicle_Types (type_name, speed_limit_kmh) VALUES
    ('Van', 120.00), ('Truck', 100.00), ('Heavy Truck', 90.00);

DROP PROCEDURE IF EXISTS SeedVehicles;
DROP PROCEDURE IF EXISTS SeedDrivers;
DROP PROCEDURE IF EXISTS SeedTripsAndGPSLogs;

DELIMITER $$

CREATE PROCEDURE SeedVehicles()
BEGIN
    DECLARE i INT DEFAULT 1;
    START TRANSACTION;
    WHILE i <= 500 DO
        INSERT INTO Vehicles (plate_number, type_id, max_weight_capacity)
        VALUES (
            CONCAT('XYZ-', i, '-', FLOOR(RAND() * 900 + 100)),
            FLOOR(1 + RAND() * 3),                     -- type 1..3
            ROUND(1000 + RAND() * 9000, 2)             -- capacity 1,000 - 10,000 kg
        );
        SET i = i + 1;
    END WHILE;
    COMMIT;
END$$

CREATE PROCEDURE SeedDrivers()
BEGIN
    DECLARE i INT DEFAULT 1;
    START TRANSACTION;
    WHILE i <= 500 DO
        INSERT INTO Drivers (full_name, license_number, phone)
        VALUES (
            CONCAT('Driver Captain ', i),
            CONCAT('LIC-', i, '-', FLOOR(RAND() * 9000 + 1000)),
            CONCAT('+201', FLOOR(RAND() * 900000000 + 100000000))
        );
        SET i = i + 1;
    END WHILE;
    COMMIT;
END$$

-- p_trips          : total trips to create
-- p_logs_per_trip  : GPS readings per trip (one per minute)
-- p_active_trips   : how many of them are Active (max 500, distinct vehicles/drivers);
--                    the rest are Completed trips in the past.
CREATE PROCEDURE SeedTripsAndGPSLogs(IN p_trips INT, IN p_logs_per_trip INT, IN p_active_trips INT)
BEGIN
    DECLARE v_trip    INT DEFAULT 1;
    DECLARE v_log     INT;
    DECLARE v_trip_id INT;
    DECLARE v_vehicle INT;
    DECLARE v_driver  INT;
    DECLARE v_status  VARCHAR(20);
    DECLARE v_start   DATETIME;
    DECLARE v_end     DATETIME DEFAULT NULL;
    DECLARE v_lat     DECIMAL(10,6);
    DECLARE v_lng     DECIMAL(10,6);
    DECLARE v_heading DOUBLE;
    DECLARE v_speed   DECIMAL(5,2);
    DECLARE v_step    DOUBLE;

    START TRANSACTION;
    WHILE v_trip <= p_trips DO
        IF v_trip <= p_active_trips THEN
            SET v_status  = 'Active';
            SET v_vehicle = MOD(v_trip * 7, 500) + 1;    -- 7 and 13 are coprime with 500 =>
            SET v_driver  = MOD(v_trip * 13, 500) + 1;   -- all distinct for up to 500 trips
            SET v_start   = NOW() - INTERVAL (p_logs_per_trip + 5) MINUTE;
            SET v_end     = NULL;
        ELSE
            SET v_status  = 'Completed';
            SET v_vehicle = FLOOR(1 + RAND() * 500);
            SET v_driver  = FLOOR(1 + RAND() * 500);
            SET v_start   = NOW() - INTERVAL (p_logs_per_trip + 60 + FLOOR(RAND() * 10000)) MINUTE;
            SET v_end     = v_start + INTERVAL p_logs_per_trip MINUTE;
        END IF;

        INSERT INTO Trips (vehicle_id, driver_id, start_time, end_time, trip_status)
        VALUES (v_vehicle, v_driver, v_start, v_end, v_status);
        SET v_trip_id = LAST_INSERT_ID();

        -- start somewhere around Cairo with a random heading
        SET v_lat     = 30.0444 + (RAND() - 0.5) * 0.2;
        SET v_lng     = 31.2357 + (RAND() - 0.5) * 0.2;
        SET v_heading = RAND() * 2 * PI();

        SET v_log = 1;
        WHILE v_log <= p_logs_per_trip DO
            -- mostly 45-85 km/h, with ~8% speeding spikes (up to 140 km/h)
            SET v_speed   = ROUND(45 + RAND() * 40 + IF(RAND() < 0.08, 25 + RAND() * 30, 0), 2);
            SET v_heading = v_heading + (RAND() - 0.5) * 0.4;
            SET v_step    = v_speed * 0.00015;           -- degrees travelled in 1 minute
            SET v_lat     = v_lat + COS(v_heading) * v_step;
            SET v_lng     = v_lng + SIN(v_heading) * v_step / COS(RADIANS(v_lat));

            INSERT INTO GPS_Live_Logs (trip_id, current_location, speed, logged_at)
            VALUES (
                v_trip_id,
                ST_PointFromText(CONCAT('POINT(', v_lng, ' ', v_lat, ')')),
                v_speed,
                v_start + INTERVAL v_log MINUTE
            );
            SET v_log = v_log + 1;
        END WHILE;

        COMMIT;
        START TRANSACTION;
        SET v_trip = v_trip + 1;
    END WHILE;
    COMMIT;
END$$

DELIMITER ;

CALL SeedVehicles();
CALL SeedDrivers();
CALL SeedTripsAndGPSLogs(100, 50, 100);

INSERT INTO Shipments (description, weight) VALUES
    ('Electronics Cargo',      3000.00),
    ('Construction Materials', 8500.00),
    ('Pharmaceutical Boxes',    450.00),
    ('Heavy Machinery',       60000.00);   -- heavier than any vehicle: must be rejected
