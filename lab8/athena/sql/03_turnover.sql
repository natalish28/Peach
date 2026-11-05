-- {table} is lab8.payments (JSON) or lab8.payments_parquet.
SELECT merchantId, merchantName, ccy,
       CASE ccy WHEN 980 THEN 'UAH' WHEN 840 THEN 'USD' WHEN 978 THEN 'EUR' END AS currency,
       count(*) AS payments,
       CAST(sum(finalAmount) / 100.0 AS decimal(18, 2)) AS turnover
FROM {table}
WHERE status = 'success'
GROUP BY merchantId, merchantName, ccy
ORDER BY merchantId, ccy
