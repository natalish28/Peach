SELECT count(*) AS events, count(DISTINCT invoiceId) AS invoices,
       count(*) - (SELECT count(*) FROM (SELECT DISTINCT * FROM lab8.stream_events)) AS duplicate_rows,
       count_if(status = 'failure') AS failures,
       count(DISTINCT "$path") AS files
FROM lab8.stream_events
