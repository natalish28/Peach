-- Share among finished payments. A payment still in 'processing' has no outcome yet.
SELECT paymentMethod, device,
       count(*) AS finished,
       count_if(status = 'failure') AS failed,
       round(100.0 * count_if(status = 'failure') / count(*), 2) AS failure_pct
FROM {table}
WHERE status IN ('success', 'failure')
GROUP BY paymentMethod, device
ORDER BY failure_pct DESC
