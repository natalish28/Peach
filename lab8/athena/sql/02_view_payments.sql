-- One row per invoiceId: the latest status. Exact duplicates go first, in the
-- inner query, because row_number() would make every row unique for a DISTINCT
-- applied after it.
CREATE OR REPLACE VIEW lab8.payments AS
SELECT invoiceId, status, failureReason, amount, finalAmount, ccy, reference,
       createdDate, modifiedDate, receivedAt, merchantId, merchantName, mcc,
       customerId, paymentMethod, device, dt
FROM (
  SELECT *, row_number() OVER (PARTITION BY invoiceId ORDER BY modifiedDate DESC) AS rn
  FROM (SELECT DISTINCT * FROM lab8.payment_events)
)
WHERE rn = 1
