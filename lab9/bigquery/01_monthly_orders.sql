-- Lab 9, Part 4: a BigQuery query over a public dataset, the counterpart of Lab 8's Athena
-- turnover and failure-rate queries. Run it in the BigQuery console (the sandbox is enough) and
-- note "Bytes processed" in Job information. Save the result as a view or table for Looker Studio.
--
-- Only the columns named here are scanned: BigQuery is columnar and bills by bytes read, so
-- SELECT * over the same tables would cost several times more.

SELECT
  DATE_TRUNC(DATE(o.created_at), MONTH)                         AS month,
  COUNT(DISTINCT o.order_id)                                    AS orders,
  ROUND(SUM(IF(o.status = 'Complete', oi.sale_price, 0)), 2)    AS revenue_usd,
  ROUND(100 * COUNTIF(o.status IN ('Cancelled', 'Returned'))
        / COUNT(*), 2)                                          AS cancelled_or_returned_pct
FROM `bigquery-public-data.thelook_ecommerce.orders` AS o
JOIN `bigquery-public-data.thelook_ecommerce.order_items` AS oi
  ON oi.order_id = o.order_id
WHERE o.created_at >= TIMESTAMP '2024-01-01'
GROUP BY month
ORDER BY month;
