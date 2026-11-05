WITH lag AS (
  SELECT date_diff('second', from_iso8601_timestamp(modifiedDate), from_iso8601_timestamp(receivedAt)) AS s
  FROM (SELECT DISTINCT * FROM lab8.payment_events)
)
SELECT count_if(s > 60) AS late_over_60s,
       count(*) AS events,
       round(100.0 * count_if(s > 60) / count(*), 3) AS late_pct,
       count_if(s > 3600) AS late_over_1h,
       max(s) AS max_lateness_s
FROM lag
