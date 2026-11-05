-- Way B: the crawler's table answers the same questions; failureReason is NULL where absent.
SELECT count(*) AS events,
       count(failurereason) AS with_reason,
       count_if(status = 'failure') AS failures,
       max(amount) AS max_amount,
       count(DISTINCT dt) AS partitions
FROM lab8.crawled_payments
