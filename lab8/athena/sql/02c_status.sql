-- Check of the view: exactly one row per invoice, and which status each ended on.
SELECT status, count(*) AS payments, count(DISTINCT invoiceId) AS invoices
FROM lab8.payments
GROUP BY status
ORDER BY payments DESC
