
-- Everything in one big transaction
-- BEGIN;

-- Check patch versioning is in place.
-- SELECT _v.register_patch('exchange-000x', NULL, NULL);


CREATE OR REPLACE FUNCTION exchange_check_coin_balance(
  IN denom_val INT8, -- value of the denomination of the coin
  IN denom_frac INT4, -- value of the denomination of the coin
  IN in_coin_pub BYTEA, -- coin public key
  IN check_recoup BOOLEAN, -- do we need to check the recoup table?
  IN zombie_required BOOLEAN, -- do we need a zombie coin?
  OUT balance_ok BOOLEAN, -- balance satisfied?
  OUT zombie_ok BOOLEAN) -- zombie satisfied?
LANGUAGE plpgsql
AS $$
DECLARE
  coin_uuid INT8; -- known_coin_id of coin_pub
DECLARE
  tmp_val INT8; -- temporary result
DECLARE
  tmp_frac INT8; -- temporary result
DECLARE
  spent_val INT8; -- how much of coin was spent?
DECLARE
  spent_frac INT8; -- how much of coin was spent?
DECLARE
  unspent_val INT8; -- how much of coin was refunded?
DECLARE
  unspent_frac INT8; -- how much of coin was refunded?
BEGIN

-- Note: possible future optimization: get the coin_uuid from the previous
-- 'ensure_coin_known' and pass that here instead of the coin_pub. Might help
-- a tiny bit with performance.
SELECT known_coin_id INTO coin_uuid
  FROM known_coins
 WHERE coin_pub=in_coin_pub;

IF NOT FOUND
THEN
  -- coin unknown, should be impossible!
  balance_ok=FALSE;
  zombie_ok=FALSE;
  ASSERT false, 'coin unknown';
  RETURN;
END IF;


spent_val = 0;
spent_frac = 0;
unspent_val = denom_val;
unspent_frac = denom_frac;

SELECT
   SUM(amount_with_fee_val) -- overflow here is not plausible
  ,SUM(CAST(amount_with_fee_frac AS INT8)) -- compute using 64 bits
  INTO
   tmp_val
  ,tmp_frac
  FROM deposits
 WHERE known_coin_id=coin_uuid;

spent_val = spent_val + tmp_val;
spent_frac = spent_frac + tmp_frac;

SELECT
   SUM(amount_with_fee_val) -- overflow here is not plausible
  ,SUM(CAST(amount_with_fee_frac AS INT8)) -- compute using 64 bits
  INTO
   tmp_val
  ,tmp_frac
  FROM refresh_commitments
 WHERE old_known_coin_id=coin_uuid;

spent_val = spent_val + tmp_val;
spent_frac = spent_frac + tmp_frac;

SELECT
   SUM(amount_with_fee_val) -- overflow here is not plausible
  ,SUM(CAST(amount_with_fee_frac AS INT8)) -- compute using 64 bits
  INTO
   tmp_val
  ,tmp_frac
  FROM refunds
 WHERE known_coin_id=coin_uuid;

unspent_val = unspent_val + tmp_val;
unspent_frac = unspent_frac + tmp_frac;

-- Note: even if 'check_recoup' is true, the tables below
-- are in practice likely empty (as they only apply if
-- the exchange (ever) had to revoke keys).
IF check_recoup
THEN

  SELECT
     SUM(amount_val) -- overflow here is not plausible
    ,SUM(CAST(amount_frac AS INT8)) -- compute using 64 bits
    INTO
     tmp_val
    ,tmp_frac
    FROM recoup_refresh
   WHERE known_coin_id=coin_uuid;

  unspent_val = unspent_val + tmp_val;
  unspent_frac = unspent_frac + tmp_frac;

  SELECT
     SUM(amount_val) -- overflow here is not plausible
    ,SUM(CAST(amount_frac AS INT8)) -- compute using 64 bits
    INTO
     tmp_val
    ,tmp_frac
    FROM recoup
   WHERE known_coin_id=coin_uuid;

  spent_val = spent_val + tmp_val;
  spent_frac = spent_frac + tmp_frac;

  SELECT
     SUM(amount_val) -- overflow here is not plausible
    ,SUM(CAST(amount_frac AS INT8)) -- compute using 64 bits
    INTO
     tmp_val
    ,tmp_frac
    FROM recoup_refresh
    JOIN refresh_revealed_coins rrc
        USING (rrc_serial)
    JOIN refresh_commitments rfc
         ON (rrc.melt_serial_id = rfc.melt_serial_id)
   WHERE rfc.old_known_coin_id=coin_uuid;

  spent_val = spent_val + tmp_val;
  spent_frac = spent_frac + tmp_frac;

  IF ( (0 < tmp_val) OR (0 < tmp_frac) )
  THEN
    -- There was a transaction that justifies the zombie
    -- status, clear the flag
    zombie_required=FALSE;
  END IF;

END IF;


-- Actually check if the coin balance is sufficient. Verbosely. ;-)
IF (unspent_val > spent_val)
THEN
  balance_ok=TRUE;
ELSE
  IF (reserve_val == amount_val) AND (reserve_frac >= amount_frac)
  THEN
    balance_ok=TRUE;
  ELSE
    balance_ok=FALSE;
  END IF;
END IF;

zombie_ok = NOT zombie_required;

END $$;

COMMENT ON FUNCTION exchange_check_coin_balance(INT8, INT4, BYTEA, BOOLEAN, BOOLEAN)
  IS 'Checks whether the coin has sufficient balance for all the operations associated with it';


-- Complete transaction
-- COMMIT;
