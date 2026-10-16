# Design decisions

![Architecture](images/architecture.svg)

## 1. Rules live in the database, not in the application
Anything that must *always* be true is enforced by the database, so no client (script, BI tool, future API) can break it:

| Rule | Mechanism |
|---|---|
| A vehicle / driver has at most one Active trip | Stored generated column + `UNIQUE` key (a "partial unique index", which MySQL lacks natively) |
| Only Available vehicles / drivers can start a trip | `BEFORE INSERT` trigger raising `SIGNAL` |
| Vehicle / driver status follows the trip | `AFTER INSERT/UPDATE` triggers on `Trips` |
| Speeding is recorded automatically | `AFTER INSERT` trigger on `GPS_Live_Logs` |
| Positive weights, valid time ranges, sane speeds | `CHECK` constraints (MySQL 8.0.16+) |
| A shipment has a trip iff it is not Pending | `CHECK` on `Shipments` |

## 2. Speed limits are data, not code
The limit depends on the vehicle type (`Vehicle_Types.speed_limit_kmh`). Changing a limit is an `UPDATE`, not a code deployment. Each violation stores the limit that applied at that moment, so history stays correct if limits change later.

## 3. Geospatial conventions
* Points are stored as `POINT(longitude latitude)` (x = longitude, y = latitude) with SRID 0, and distances use `ST_Distance_Sphere` (meters, spherical earth, error well under 1% for fleet distances).
* A unit test checks the Cairo-Alexandria distance (~180 km) so an accidental lat/lng swap is caught immediately.
* Trip distance uses `LAG()` over the GPS points of each trip; "latest position" uses `ROW_NUMBER()`.

## 4. Shipment assignment and concurrency
`AssignShipmentToDriver` runs in a transaction: it locks the shipment, picks the tightest-fitting Active trip (`FOR UPDATE`), then re-checks the remaining capacity with a *locking read* before committing. This prevents two sessions from overloading the same vehicle. Known limit: if the re-check fails the procedure asks the caller to retry instead of trying the next-best trip.

## 5. Indexing strategy
* `idx_gps_speed` demonstrates the full-scan -> range-scan improvement on a selective predicate.
* `idx_gps_trip_time (trip_id, logged_at)` serves the queries the system really runs (route of a trip, latest position).
* `idx_viol_time` makes the "today" reports use a range scan; the views use `>= CURDATE() AND < CURDATE() + 1 DAY` instead of `DATE(col) = ...`, which would prevent index use.

## 6. Scaling path (not implemented)
* `GPS_Live_Logs` grows fastest. MySQL partitioned tables cannot have foreign keys, so the usual path is: drop the FK, partition by month on `logged_at` (primary key becomes `(log_id, logged_at)`), and archive old partitions.
* For heavy analytics, stream the GPS events to a log / lake (Kafka -> Parquet) and query them there; keep MySQL for the transactional part.
* For production geo queries, use `SRID 4326` + a `SPATIAL INDEX`.

## 7. Known limitations
* Seed data is synthetic.
* The speed trigger adds a join per GPS insert; at very high ingest rates, move violation detection to a stream processor.
* No authentication / roles are modeled.
