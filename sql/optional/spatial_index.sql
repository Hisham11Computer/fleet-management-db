-- Optional spatial index. On MySQL 8 the optimizer only uses a spatial index when
-- the column has an SRID attribute, so for production recreate the column as
--   current_location POINT NOT NULL SRID 4326
-- (and mind that SRID 4326 uses latitude-longitude axis order).
USE RouteMasterX;
ALTER TABLE GPS_Live_Logs ADD SPATIAL INDEX idx_gps_location (current_location);
