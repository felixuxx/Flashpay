
CREATE FUNCTION constrain_table_refunds4 (
  IN partition_suffix TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  table_name TEXT DEFAULT 'refunds';
BEGIN
  table_name = concat_ws('_', table_name, partition_suffix);

  EXECUTE FORMAT (
    'ALTER TABLE ' || table_name ||
    ' DROP CONSTRAINT refunds_pkey'
  );
  EXECUTE FORMAT (
    'ALTER TABLE ' || table_name ||
    ' ADD PRIMARY KEY (batch_deposit_serial_id, coin_pub, rtransaction_id) '
  );
END
$$;

INSERT INTO exchange_tables
    (name
    ,version
    ,action
    ,partitioned
    ,by_range)
  VALUES
    ('refunds4'
    ,'exchange-0004'
    ,'constrain'
    ,TRUE
    ,FALSE);
