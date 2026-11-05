-- Partition column last, as CTAS requires.
CREATE TABLE lab8.payments_parquet
WITH (
  format = 'PARQUET',
  write_compression = 'SNAPPY',
  external_location = 's3://peach-lab8-757159686525/curated/payments/',
  partitioned_by = ARRAY['dt']
) AS
SELECT invoiceId, status, failureReason, amount, finalAmount, ccy, reference,
       createdDate, modifiedDate, receivedAt, merchantId, merchantName, mcc,
       customerId, paymentMethod, device, dt
FROM lab8.payments
