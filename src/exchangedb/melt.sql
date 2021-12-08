
-- Everything in one big transaction
-- BEGIN;

-- Check patch versioning is in place.
-- SELECT _v.register_patch('exchange-000x', NULL, NULL);

CREATE OR REPLACE FUNCTION exchange_do_melt(
  IN denom_val INT8, -- value of the denomination of the coin
  IN denom_frac INT4, -- value of the denomination of the coin
  IN amount_val INT8, -- requested melt amount (with fee)
  IN amount_frac INT4, -- requested melt amount (with fee)
  IN in_rc BYTEA, -- refresh session hash
  IN in_coin_pub BYTEA, -- coin public key
  IN coin_sig BYTEA, -- melt signature
  IN in_noreveal_index INT4, -- suggested random noreveal index
  IN zombie_required BOOLEAN, -- do we need a zombie coin?
  OUT out_noreval_index INT4, -- noreveal index to actually use
  OUT balance_ok BOOLEAN, -- balance satisfied?
  OUT zombie_ok BOOLEAN, -- zombie satisfied?
  OUT melt_ok BOOLEAN) -- everything OK?
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

SELECT known_coin_id INTO coin_uuid
  FROM known_coins
 WHERE coin_pub=in_coin_pub;

IF NOT FOUND
THEN
  -- coin unknown, should be impossible!
  out_noreveal_index=-1;
  balance_ok=FALSE;
  zombie_ok=FALSE;
  melt_ok=FALSE;
  ASSERT false, 'coin unknown';
  RETURN;
END IF;

-- We optimistically insert, and then on conflict declare
-- the query successful due to idempotency.
INSERT INTO refresh_commitments
  (rc
  ,old_known_coin_id
  ,old_coin_sig
  ,amount_with_fee_val
  ,amount_with_fee_frac
  ,noreveal_index)
VALUES
  (in_rc
  ,coin_uuid
  ,coin_sig
  ,amount_val
  ,amount_frac
  ,in_noreveal_index)
ON CONFLICT DO NOTHING;

IF FOUND
THEN
  -- already melted, get noreveal_index
  SELECT noreveal_index INTO out_noreveal_index
    FROM refresh_commitments
   WHERE rc=in_rc ;
  balance_ok=TRUE;
  zombie_ok=TRUE;
  melt_ok=TRUE;
  RETURN;
END IF;

-- Need to check for sufficient balance...
spent_val = 0;
spent_frac = 0;
unspent_val = 0;
unspent_frac = 0;

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


------------------- TBD from here

SELECT
   reserve_uuid
  ,current_balance_val
  ,current_balance_frac_uuid
  ,expiration_date
  ,gc_date
 INTO
   reserve_uuid
  ,reserve_val
  ,reserve_frac
  ,reserve_gc
  FROM reserves
 WHERE reserve_pub=reserve_pub;

IF NOT FOUND
THEN
  -- reserve unknown
  reserve_found=FALSE;
  balance_ok=FALSE;
  kyc_ok=FALSE;
  RETURN;
END IF;

-- We optimistically insert, and then on conflict declare
-- the query successful due to idempotency.
INSERT INTO reserves_out
  (h_blind_ev
  ,denom_serial
  ,denom_sig
  ,reserve_uuid
  ,reserve_sig
  ,execution_date
  ,amount_with_fee_val
  ,amount_with_fee_frac)
VALUES
  (h_coin_envelope
  ,denom_serial
  ,denom_sig
  ,reserve_uuid
  ,reserve_sig
  ,now
  ,amount_val
  ,amount_frac)
ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- idempotent query, all constraints must be satisfied
  reserve_found=TRUE;
  balance_ok=TRUE;
  kyc_ok=TRUE;
  RETURN;
END IF;

-- Check reserve balance is sufficient.
IF (reserve_val > amount_val)
THEN
  IF (reserve_frac > amount_frac)
  THEN
    reserve_val=reserve_val - amount_val;
    reserve_frac=reserve_frac - amount_frac;
  ELSE
    reserve_val=reserve_val - amount_val - 1;
    reserve_frac=reserve_frac + 100000000 - amount_frac;
  END IF;
ELSE
  IF (reserve_val == amount_val) AND (reserve_frac >= amount_frac)
  THEN
    reserve_val=0;
    reserve_frac=reserve_frac - amount_frac;
  ELSE
    reserve_found=TRUE;
    balance_ok=FALSE;
    kyc_ok=FALSE; -- we do not really know or care
    RETURN;
  END IF;
END IF;

-- Calculate new expiration dates.
min_reserve_gc=MAX(min_reserve_gc,reserve_gc);

-- Update reserve balance.
UPDATE reserves SET
  gc_date=min_reserve_gc
 ,current_balance_val=reserve_val
 ,current_balance_frac=reserve_frac
WHERE
  reserve_uuid=reserve_uuid;

reserve_found=TRUE;
balance_ok=TRUE;

-- Obtain KYC status based on the last wire transfer into
-- this reserve. FIXME: likely not adequate for reserves that got P2P transfers!
SELECT kyc_ok
  INTO kyc_ok
  FROM reserves_in
  JOIN wire_targets USING (wire_target_serial_id)
 WHERE reserve_uuid=reserve_uuid
 LIMIT 1; -- limit 1 should not be required (without p2p transfers)



END $$;

COMMENT ON FUNCTION exchange_do_melt(INT8, INT4, BYTEA, BYTEA, BYTEA, BYTEA, BYTEA, INT8, INT8)
  IS 'Checks whether the coin has sufficient balance for a melt operation (or the request is repeated and was previously approved) and if so updates the database with the result';


-- Complete transaction
-- COMMIT;
