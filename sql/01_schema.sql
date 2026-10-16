-- =====================================================
-- 01_schema.sql : database, tables, constraints
-- Location convention everywhere: POINT(longitude latitude)  => x = lng, y = lat
-- Requires MySQL 8.0.16+ (CHECK constraints are enforced from that version)
-- =====================================================
CREATE DATABASE RouteMasterX CHARACTER SET utf8mb4;
USE RouteMasterX;

-- Reference data: each vehicle type has its own speed limit
CREATE TABLE Vehicle_Types (
    type_id         TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    type_name       VARCHAR(50)  NOT NULL UNIQUE,
    speed_limit_kmh DECIMAL(5,2) NOT NULL,
    CONSTRAINT chk_type_limit CHECK (speed_limit_kmh > 0)
);

CREATE TABLE Vehicles (
    vehicle_id          INT AUTO_INCREMENT PRIMARY KEY,
    plate_number        VARCHAR(100)  NOT NULL UNIQUE,
    type_id             TINYINT UNSIGNED NOT NULL,
    max_weight_capacity DECIMAL(10,2) NOT NULL,
    status ENUM('Available', 'In Trip', 'Maintenance') NOT NULL DEFAULT 'Available',
    CONSTRAINT fk_vehicles_type FOREIGN KEY (type_id) REFERENCES Vehicle_Types (type_id),
    CONSTRAINT chk_vehicle_capacity CHECK (max_weight_capacity > 0)
);

CREATE TABLE Drivers (
    driver_id      INT AUTO_INCREMENT PRIMARY KEY,
    full_name      VARCHAR(100) NOT NULL,
    license_number VARCHAR(50)  NOT NULL UNIQUE,
    phone          VARCHAR(20)  NOT NULL,
    status ENUM('Available', 'On Trip', 'On Leave') NOT NULL DEFAULT 'Available'
);

CREATE TABLE Trips (
    trip_id     INT AUTO_INCREMENT PRIMARY KEY,
    vehicle_id  INT NOT NULL,
    driver_id   INT NOT NULL,
    start_time  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    end_time    DATETIME NULL,
    trip_status ENUM('Active', 'Completed', 'Cancelled') NOT NULL DEFAULT 'Active',

    -- "Partial unique index" trick: the key is NULL unless the trip is Active,
    -- and UNIQUE allows many NULLs. Result: a vehicle / driver can have at most
    -- ONE active trip at a time, enforced by the database itself.
    active_vehicle_key INT GENERATED ALWAYS AS (IF(trip_status = 'Active', vehicle_id, NULL)) STORED,
    active_driver_key  INT GENERATED ALWAYS AS (IF(trip_status = 'Active', driver_id,  NULL)) STORED,

    CONSTRAINT fk_trips_vehicle FOREIGN KEY (vehicle_id) REFERENCES Vehicles (vehicle_id),
    CONSTRAINT fk_trips_driver  FOREIGN KEY (driver_id)  REFERENCES Drivers  (driver_id),
    CONSTRAINT chk_trip_times   CHECK (end_time IS NULL OR end_time >= start_time),
    UNIQUE KEY uq_one_active_trip_per_vehicle (active_vehicle_key),
    UNIQUE KEY uq_one_active_trip_per_driver  (active_driver_key),
    KEY idx_trips_status (trip_status)
);

CREATE TABLE GPS_Live_Logs (
    log_id           BIGINT AUTO_INCREMENT PRIMARY KEY,
    trip_id          INT NOT NULL,
    current_location POINT NOT NULL,
    speed            DECIMAL(5,2) NOT NULL,
    logged_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_gps_trip   FOREIGN KEY (trip_id) REFERENCES Trips (trip_id),
    CONSTRAINT chk_gps_speed CHECK (speed >= 0 AND speed <= 300)
);

CREATE TABLE Speed_Violations (
    violation_id   INT AUTO_INCREMENT PRIMARY KEY,
    trip_id        INT NOT NULL,
    log_id         BIGINT NOT NULL UNIQUE,          -- the GPS reading that caused it
    exceeded_speed DECIMAL(5,2) NOT NULL,
    speed_limit    DECIMAL(5,2) NOT NULL,           -- limit that applied at that moment
    violation_time DATETIME NOT NULL,
    CONSTRAINT fk_viol_trip FOREIGN KEY (trip_id) REFERENCES Trips (trip_id),
    CONSTRAINT fk_viol_log  FOREIGN KEY (log_id)  REFERENCES GPS_Live_Logs (log_id)
);

CREATE TABLE Shipments (
    shipment_id      INT AUTO_INCREMENT PRIMARY KEY,
    description      VARCHAR(255),
    weight           DECIMAL(10,2) NOT NULL,
    assigned_trip_id INT NULL,
    status           ENUM('Pending', 'Assigned', 'Delivered') NOT NULL DEFAULT 'Pending',
    delivered_at     DATETIME NULL,
    CONSTRAINT fk_ship_trip FOREIGN KEY (assigned_trip_id) REFERENCES Trips (trip_id),
    CONSTRAINT chk_ship_weight CHECK (weight > 0),
    -- invariant: a shipment has a trip if and only if it is no longer Pending
    CONSTRAINT chk_ship_state CHECK (
        (status = 'Pending' AND assigned_trip_id IS NULL) OR
        (status <> 'Pending' AND assigned_trip_id IS NOT NULL)
    ),
    KEY idx_ship_status (status)
);
