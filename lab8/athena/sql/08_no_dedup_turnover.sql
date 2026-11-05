-- What breaks without deduplication: the same turnover and counts on raw events.
SELECT 'raw events' AS source, count(*) AS rows, count_if(status = 'success') AS successes,
       CAST(sum(CASE WHEN status = 'success' AND ccy = 980 THEN finalAmount END) / 100.0 AS decimal(18, 2)) AS uah_turnover
FROM lab8.payment_events
UNION ALL
SELECT 'payments view', count(*), count_if(status = 'success'),
       CAST(sum(CASE WHEN status = 'success' AND ccy = 980 THEN finalAmount END) / 100.0 AS decimal(18, 2))
FROM lab8.payments
ORDER BY 1
