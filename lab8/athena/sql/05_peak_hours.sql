-- Hour the payment was created, UTC.
SELECT hour(from_iso8601_timestamp(createdDate)) AS hour_utc, count(*) AS payments
FROM {table}
GROUP BY 1
ORDER BY 1
