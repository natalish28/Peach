-- Part 4: the data that came through the stream. Each file is one Lambda batch;
-- the forced failures start partway through the run.
SELECT "$path" AS batch_file,
       min(receivedAt) AS first_received,
       count(*) AS events,
       count_if(status = 'success') AS success,
       count_if(status = 'failure') AS failure,
       round(100.0 * count_if(status = 'failure')
             / nullif(count_if(status IN ('success', 'failure')), 0), 1) AS failure_pct
FROM lab8.stream_events
GROUP BY 1
ORDER BY 2
