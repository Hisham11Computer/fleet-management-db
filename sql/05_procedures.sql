-- =====================================================
-- 05_procedures.sql : trip lifecycle + shipment assignment
-- =====================================================
USE RouteMasterX;

DROP FUNCTION  IF EXISTS Fn_Remaining_Capacity;
DROP PROCEDURE IF EXISTS StartTrip;
DROP PROCEDURE IF EXISTS CompleteTrip;
DROP PROCEDURE IF EXISTS AssignShipmentToDriver;

DELIMITER $$

-- Remaining capacity (kg) of a trip's vehicle = capacity - weight already assigned
CREATE FUNCTION Fn_Remaining_Capacity(p_trip_id INT)
RETURNS DECIMAL(10,2)
READS SQL DATA
BEGIN
    DECLARE v_capacity DECIMAL(10,2) DEFAULT 0;
    DECLARE v_assigned DECIMAL(10,2) DEFAULT 0;

    SELECT v.max_weight_capacity INTO v_capacity
    FROM Trips t JOIN Vehicles v ON v.vehicle_id = t.vehicle_id
    WHERE t.trip_id = p_trip_id;

    SELECT COALESCE(SUM(weight), 0) INTO v_assigned
    FROM Shipments WHERE assigned_trip_id = p_trip_id;

    RETURN v_capacity - v_assigned;
END$$

-- Start a trip. Availability / double-booking rules live in the triggers + unique keys.
CREATE PROCEDURE StartTrip(IN p_vehicle_id INT, IN p_driver_id INT, OUT p_trip_id INT)
BEGIN
    INSERT INTO Trips (vehicle_id, driver_id, trip_status)
    VALUES (p_vehicle_id, p_driver_id, 'Active');
    SET p_trip_id = LAST_INSERT_ID();
END$$

-- Complete a trip: frees vehicle + driver (trigger) and marks its shipments Delivered
CREATE PROCEDURE CompleteTrip(IN p_trip_id INT)
BEGIN
    DECLARE v_status VARCHAR(20) DEFAULT NULL;

    START TRANSACTION;
    SELECT trip_status INTO v_status FROM Trips WHERE trip_id = p_trip_id FOR UPDATE;

    IF v_status IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Trip not found';
    ELSEIF v_status <> 'Active' THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Trip is not active';
    ELSE
        UPDATE Trips SET trip_status = 'Completed', end_time = NOW() WHERE trip_id = p_trip_id;
        UPDATE Shipments SET status = 'Delivered', delivered_at = NOW()
        WHERE assigned_trip_id = p_trip_id AND status = 'Assigned';
        COMMIT;
    END IF;
END$$

-- Best-fit assignment: tightest Active trip that still has enough remaining capacity.
CREATE PROCEDURE AssignShipmentToDriver(IN p_shipment_id INT, OUT p_message VARCHAR(255))
BEGIN
    DECLARE v_trip_id  INT DEFAULT NULL;
    DECLARE v_weight   DECIMAL(10,2) DEFAULT NULL;
    DECLARE v_capacity DECIMAL(10,2) DEFAULT 0;
    DECLARE v_assigned DECIMAL(10,2) DEFAULT 0;

    START TRANSACTION;

    -- lock the shipment; it must exist and still be Pending
    SELECT weight INTO v_weight
    FROM Shipments
    WHERE shipment_id = p_shipment_id AND status = 'Pending'
    FOR UPDATE;

    IF v_weight IS NULL THEN
        ROLLBACK;
        SET p_message = 'Error: Shipment not found or already assigned';
    ELSE
        -- pick (and lock) the candidate trip with the smallest sufficient remaining capacity
        SELECT t.trip_id INTO v_trip_id
        FROM Trips t
        WHERE t.trip_status = 'Active'
          AND Fn_Remaining_Capacity(t.trip_id) >= v_weight
        ORDER BY Fn_Remaining_Capacity(t.trip_id) ASC, t.trip_id ASC
        LIMIT 1
        FOR UPDATE;

        IF v_trip_id IS NULL THEN
            ROLLBACK;
            SET p_message = 'Error: No available vehicles with enough capacity!';
        ELSE
            -- re-check under the lock with a locking read (sees the latest committed data)
            SELECT v.max_weight_capacity INTO v_capacity
            FROM Trips t JOIN Vehicles v ON v.vehicle_id = t.vehicle_id
            WHERE t.trip_id = v_trip_id;

            SELECT COALESCE(SUM(weight), 0) INTO v_assigned
            FROM Shipments WHERE assigned_trip_id = v_trip_id FOR UPDATE;

            IF v_capacity - v_assigned >= v_weight THEN
                UPDATE Shipments
                SET status = 'Assigned', assigned_trip_id = v_trip_id
                WHERE shipment_id = p_shipment_id;
                COMMIT;
                SET p_message = CONCAT('Success: Shipment assigned to Trip ID ', v_trip_id);
            ELSE
                ROLLBACK;
                SET p_message = 'Error: Capacity changed concurrently, please retry';
            END IF;
        END IF;
    END IF;
END$$

DELIMITER ;

-- Demo
CALL AssignShipmentToDriver(1, @msg);
SELECT @msg AS result;
SELECT * FROM Shipments;
