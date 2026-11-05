-- The answers about scale, all on the raw events.
WITH distinct_events AS (SELECT DISTINCT * FROM lab8.payment_events),
lag AS (
  SELECT date_diff('second', from_iso8601_timestamp(modifiedDate), from_iso8601_timestamp(receivedAt)) AS s
  FROM distinct_events
)
SELECT
  (SELECT count(*) FROM lab8.payment_events)                       AS raw_events,
  (SELECT count(*) FROM distinct_events)                           AS distinct_events,
  (SELECT count(*) FROM lab8.payment_events)
    - (SELECT count(*) FROM distinct_events)                       AS duplicate_rows,
  (SELECT count(DISTINCT invoiceId) FROM lab8.payment_events)      AS unique_invoices,
  (SELECT count(*) FROM lag WHERE s > 3600)                        AS over_1h_late,
  (SELECT max(s) FROM lag)                                         AS max_lateness_s
