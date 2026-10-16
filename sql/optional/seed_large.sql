-- Optional: adds ~500,000 GPS logs (5,000 completed trips x 100 logs) for a
-- realistic indexing benchmark. Run AFTER the normal setup. Takes a few minutes.
USE RouteMasterX;
CALL SeedTripsAndGPSLogs(5000, 100, 0);
SELECT COUNT(*) AS total_gps_logs FROM GPS_Live_Logs;
