-- =====================================================
-- 02_triggers.sql : business rules enforced inside the database
-- Created BEFORE seeding so seeded data goes through the same rules.
-- =====================================================
USE RouteMasterX;

DELIMITER $$

-- 1) A new ACTIVE trip is only allowed for an Available vehicle and driver
CREATE TRIGGER trg_trips_before_insert
BEFORE INSERT ON Trips
FOR EACH ROW
BEGIN
    DECLARE v_vehicle_status VARCHAR(20) DEFAULT NULL;
    DECLARE v_driver_status  VARCHAR(20) DEFAULT NULL;

    IF NEW.trip_status = 'Active' THEN
        SELECT status INTO v_vehicle_status FROM Vehicles WHERE vehicle_id = NEW.vehicle_id;
        SELECT status INTO v_driver_status  FROM Drivers  WHERE driver_id  = NEW.driver_id;

        IF v_vehicle_status IS NULL OR v_vehicle_status <> 'Available' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Vehicle is not available for a new trip';
        END IF;
        IF v_driver_status IS NULL OR v_driver_status <> 'Available' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Driver is not available for a new trip';
        END IF;
    END IF;
END$$

-- 2) Starting a trip marks the vehicle and driver as busy
CREATE TRIGGER trg_trips_after_insert
AFTER INSERT ON Trips
FOR EACH ROW
BEGIN
    IF NEW.trip_status = 'Active' THEN
        UPDATE Vehicles SET status = 'In Trip' WHERE vehicle_id = NEW.vehicle_id;
        UPDATE Drivers  SET status = 'On Trip' WHERE driver_id  = NEW.driver_id;
    END IF;
END$$

-- 3) Ending / cancelling a trip frees them again (never overrides Maintenance / On Leave)
CREATE TRIGGER trg_trips_after_update
AFTER UPDATE ON Trips
FOR EACH ROW
BEGIN
    IF OLD.trip_status = 'Active' AND NEW.trip_status <> 'Active' THEN
        UPDATE Vehicles SET status = 'Available' WHERE vehicle_id = NEW.vehicle_id AND status = 'In Trip';
        UPDATE Drivers  SET status = 'Available' WHERE driver_id  = NEW.driver_id  AND status = 'On Trip';
    END IF;
END$$

-- 4) Every GPS reading above the vehicle TYPE's speed limit becomes a violation
CREATE TRIGGER trg_gps_after_insert_speed_check
AFTER INSERT ON GPS_Live_Logs
FOR EACH ROW
BEGIN
    DECLARE v_limit DECIMAL(5,2) DEFAULT NULL;

    SELECT vt.speed_limit_kmh INTO v_limit
    FROM Trips t
    JOIN Vehicles v       ON v.vehicle_id = t.vehicle_id
    JOIN Vehicle_Types vt ON vt.type_id   = v.type_id
    WHERE t.trip_id = NEW.trip_id;

    IF v_limit IS NOT NULL AND NEW.speed > v_limit THEN
        INSERT INTO Speed_Violations (trip_id, log_id, exceeded_speed, speed_limit, violation_time)
        VALUES (NEW.trip_id, NEW.log_id, NEW.speed, v_limit, NEW.logged_at);
    END IF;
END$$

DELIMITER ;
