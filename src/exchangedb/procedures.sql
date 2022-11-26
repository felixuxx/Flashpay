--
-- This file is part of TALER
-- Copyright (C) 2014--2022 Taler Systems SA
--
-- TALER is free software; you can redistribute it and/or modify it under the
-- terms of the GNU General Public License as published by the Free Software
-- Foundation; either version 3, or (at your option) any later version.
--
-- TALER is distributed in the hope that it will be useful, but WITHOUT ANY
-- WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
-- A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License along with
-- TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
--

-- Everything in one big transaction
BEGIN;

SET search_path TO exchange;

---------------------------------------------------------------------------
--                      Stored procedures
---------------------------------------------------------------------------


CREATE OR REPLACE FUNCTION exchange_do_withdraw(
  IN cs_nonce BYTEA,
  IN amount_val INT8,
  IN amount_frac INT4,
  IN h_denom_pub BYTEA,
  IN rpub BYTEA,
  IN reserve_sig BYTEA,
  IN h_coin_envelope BYTEA,
  IN denom_sig BYTEA,
  IN now INT8,
  IN min_reserve_gc INT8,
  OUT reserve_found BOOLEAN,
  OUT balance_ok BOOLEAN,
  OUT nonce_ok BOOLEAN,
  OUT ruuid INT8)
LANGUAGE plpgsql
AS $$
DECLARE
  reserve_gc INT8;
DECLARE
  denom_serial INT8;
DECLARE
  reserve_val INT8;
DECLARE
  reserve_frac INT4;
BEGIN
-- Shards: reserves by reserve_pub (SELECT)
--         reserves_out (INSERT, with CONFLICT detection) by wih
--         reserves by reserve_pub (UPDATE)
--         reserves_in by reserve_pub (SELECT)
--         wire_targets by wire_target_h_payto

SELECT denominations_serial
  INTO denom_serial
  FROM exchange.denominations
 WHERE denom_pub_hash=h_denom_pub;

IF NOT FOUND
THEN
  -- denomination unknown, should be impossible!
  reserve_found=FALSE;
  balance_ok=FALSE;
  ruuid=0;
  ASSERT false, 'denomination unknown';
  RETURN;
END IF;


SELECT
   current_balance_val
  ,current_balance_frac
  ,gc_date
  ,reserve_uuid
 INTO
   reserve_val
  ,reserve_frac
  ,reserve_gc
  ,ruuid
  FROM exchange.reserves
 WHERE reserves.reserve_pub=rpub;

IF NOT FOUND
THEN
  -- reserve unknown
  reserve_found=FALSE;
  balance_ok=FALSE;
  nonce_ok=TRUE;
  ruuid=2;
  RETURN;
END IF;

-- We optimistically insert, and then on conflict declare
-- the query successful due to idempotency.
INSERT INTO exchange.reserves_out
  (h_blind_ev
  ,denominations_serial
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
  ,ruuid
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
  nonce_ok=TRUE;
  RETURN;
END IF;

-- Check reserve balance is sufficient.
IF (reserve_val > amount_val)
THEN
  IF (reserve_frac >= amount_frac)
  THEN
    reserve_val=reserve_val - amount_val;
    reserve_frac=reserve_frac - amount_frac;
  ELSE
    reserve_val=reserve_val - amount_val - 1;
    reserve_frac=reserve_frac + 100000000 - amount_frac;
  END IF;
ELSE
  IF (reserve_val = amount_val) AND (reserve_frac >= amount_frac)
  THEN
    reserve_val=0;
    reserve_frac=reserve_frac - amount_frac;
  ELSE
    reserve_found=TRUE;
    nonce_ok=TRUE; -- we do not really know
    balance_ok=FALSE;
    RETURN;
  END IF;
END IF;

-- Calculate new expiration dates.
min_reserve_gc=GREATEST(min_reserve_gc,reserve_gc);

-- Update reserve balance.
UPDATE reserves SET
  gc_date=min_reserve_gc
 ,current_balance_val=reserve_val
 ,current_balance_frac=reserve_frac
WHERE
  reserves.reserve_pub=rpub;

reserve_found=TRUE;
balance_ok=TRUE;



-- Special actions needed for a CS withdraw?
IF NOT NULL cs_nonce
THEN
  -- Cache CS signature to prevent replays in the future
  -- (and check if cached signature exists at the same time).
  INSERT INTO exchange.cs_nonce_locks
    (nonce
    ,max_denomination_serial
    ,op_hash)
  VALUES
    (cs_nonce
    ,denom_serial
    ,h_coin_envelope)
  ON CONFLICT DO NOTHING;

  IF NOT FOUND
  THEN
    -- See if the existing entry is identical.
    SELECT 1
      FROM exchange.cs_nonce_locks
     WHERE nonce=cs_nonce
       AND op_hash=h_coin_envelope;
    IF NOT FOUND
    THEN
      reserve_found=FALSE;
      balance_ok=FALSE;
      nonce_ok=FALSE;
      RETURN;
    END IF;
  END IF;
ELSE
  nonce_ok=TRUE; -- no nonce, hence OK!
END IF;

END $$;


COMMENT ON FUNCTION exchange_do_withdraw(BYTEA, INT8, INT4, BYTEA, BYTEA, BYTEA, BYTEA, BYTEA, INT8, INT8)
  IS 'Checks whether the reserve has sufficient balance for a withdraw operation (or the request is repeated and was previously approved) and if so updates the database with the result';




CREATE OR REPLACE FUNCTION exchange_do_batch_withdraw(
  IN amount_val INT8,
  IN amount_frac INT4,
  IN rpub BYTEA,
  IN now INT8,
  IN min_reserve_gc INT8,
  OUT reserve_found BOOLEAN,
  OUT balance_ok BOOLEAN,
  OUT ruuid INT8)
LANGUAGE plpgsql
AS $$
DECLARE
  reserve_gc INT8;
DECLARE
  reserve_val INT8;
DECLARE
  reserve_frac INT4;
BEGIN
-- Shards: reserves by reserve_pub (SELECT)
--         reserves_out (INSERT, with CONFLICT detection) by wih
--         reserves by reserve_pub (UPDATE)
--         reserves_in by reserve_pub (SELECT)
--         wire_targets by wire_target_h_payto

SELECT
   current_balance_val
  ,current_balance_frac
  ,gc_date
  ,reserve_uuid
 INTO
   reserve_val
  ,reserve_frac
  ,reserve_gc
  ,ruuid
  FROM exchange.reserves
 WHERE reserves.reserve_pub=rpub;

IF NOT FOUND
THEN
  -- reserve unknown
  reserve_found=FALSE;
  balance_ok=FALSE;
  ruuid=2;
  RETURN;
END IF;

-- Check reserve balance is sufficient.
IF (reserve_val > amount_val)
THEN
  IF (reserve_frac >= amount_frac)
  THEN
    reserve_val=reserve_val - amount_val;
    reserve_frac=reserve_frac - amount_frac;
  ELSE
    reserve_val=reserve_val - amount_val - 1;
    reserve_frac=reserve_frac + 100000000 - amount_frac;
  END IF;
ELSE
  IF (reserve_val = amount_val) AND (reserve_frac >= amount_frac)
  THEN
    reserve_val=0;
    reserve_frac=reserve_frac - amount_frac;
  ELSE
    reserve_found=TRUE;
    balance_ok=FALSE;
    RETURN;
  END IF;
END IF;

-- Calculate new expiration dates.
min_reserve_gc=GREATEST(min_reserve_gc,reserve_gc);

-- Update reserve balance.
UPDATE reserves SET
  gc_date=min_reserve_gc
 ,current_balance_val=reserve_val
 ,current_balance_frac=reserve_frac
WHERE
  reserves.reserve_pub=rpub;

reserve_found=TRUE;
balance_ok=TRUE;

END $$;

COMMENT ON FUNCTION exchange_do_batch_withdraw(INT8, INT4, BYTEA, INT8, INT8)
  IS 'Checks whether the reserve has sufficient balance for a withdraw operation (or the request is repeated and was previously approved) and if so updates the database with the result. Excludes storing the planchets.';





CREATE OR REPLACE FUNCTION exchange_do_batch_withdraw_insert(
  IN cs_nonce BYTEA,
  IN amount_val INT8,
  IN amount_frac INT4,
  IN h_denom_pub BYTEA,
  IN ruuid INT8,
  IN reserve_sig BYTEA,
  IN h_coin_envelope BYTEA,
  IN denom_sig BYTEA,
  IN now INT8,
  OUT out_denom_unknown BOOLEAN,
  OUT out_nonce_reuse BOOLEAN,
  OUT out_conflict BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
  denom_serial INT8;
BEGIN
-- Shards: reserves by reserve_pub (SELECT)
--         reserves_out (INSERT, with CONFLICT detection) by wih
--         reserves by reserve_pub (UPDATE)
--         reserves_in by reserve_pub (SELECT)
--         wire_targets by wire_target_h_payto

out_denom_unknown=TRUE;
out_conflict=TRUE;
out_nonce_reuse=TRUE;

SELECT denominations_serial
  INTO denom_serial
  FROM exchange.denominations
 WHERE denom_pub_hash=h_denom_pub;

IF NOT FOUND
THEN
  -- denomination unknown, should be impossible!
  out_denom_unknown=TRUE;
  ASSERT false, 'denomination unknown';
  RETURN;
END IF;
out_denom_unknown=FALSE;

INSERT INTO exchange.reserves_out
  (h_blind_ev
  ,denominations_serial
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
  ,ruuid
  ,reserve_sig
  ,now
  ,amount_val
  ,amount_frac)
ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  out_conflict=TRUE;
  RETURN;
END IF;
out_conflict=FALSE;

-- Special actions needed for a CS withdraw?
out_nonce_reuse=FALSE;
IF NOT NULL cs_nonce
THEN
  -- Cache CS signature to prevent replays in the future
  -- (and check if cached signature exists at the same time).
  INSERT INTO exchange.cs_nonce_locks
    (nonce
    ,max_denomination_serial
    ,op_hash)
  VALUES
    (cs_nonce
    ,denom_serial
    ,h_coin_envelope)
  ON CONFLICT DO NOTHING;

  IF NOT FOUND
  THEN
    -- See if the existing entry is identical.
    SELECT 1
      FROM exchange.cs_nonce_locks
     WHERE nonce=cs_nonce
       AND op_hash=h_coin_envelope;
    IF NOT FOUND
    THEN
      out_nonce_reuse=TRUE;
      ASSERT false, 'nonce reuse attempted by client';
      RETURN;
    END IF;
  END IF;
END IF;

END $$;

COMMENT ON FUNCTION exchange_do_batch_withdraw_insert(BYTEA, INT8, INT4, BYTEA, INT8, BYTEA, BYTEA, BYTEA, INT8)
  IS 'Stores information about a planchet for a batch withdraw operation. Checks if the planchet already exists, and in that case indicates a conflict';




-- NOTE: experiment, currently dead, see postgres_Start_deferred_wire_out;
-- now done inline. FIXME: Remove code here once inline version is confirmed working nicely!
CREATE OR REPLACE PROCEDURE defer_wire_out()
LANGUAGE plpgsql
AS $$
BEGIN

IF EXISTS (
  SELECT 1
    FROM exchange.information_Schema.constraint_column_usage
   WHERE table_name='wire_out'
     AND constraint_name='wire_out_ref')
THEN
  SET CONSTRAINTS wire_out_ref DEFERRED;
END IF;

END $$;


CREATE OR REPLACE FUNCTION exchange_do_recoup_by_reserve(
  IN res_pub BYTEA
)
RETURNS TABLE
(
  denom_sig            BYTEA,
  denominations_serial BIGINT,
  coin_pub             BYTEA,
  coin_sig             BYTEA,
  coin_blind           BYTEA,
  amount_val           BIGINT,
  amount_frac          INTEGER,
  recoup_timestamp     BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
  res_uuid BIGINT;
  blind_ev BYTEA;
  c_pub    BYTEA;
BEGIN
  SELECT reserve_uuid
  INTO res_uuid
  FROM exchange.reserves
  WHERE reserves.reserve_pub = res_pub;

  FOR blind_ev IN
    SELECT h_blind_ev
      FROM exchange.reserves_out_by_reserve
    WHERE reserves_out_by_reserve.reserve_uuid = res_uuid
  LOOP
    SELECT robr.coin_pub
      INTO c_pub
      FROM exchange.recoup_by_reserve robr
    WHERE robr.reserve_out_serial_id = (
      SELECT reserves_out.reserve_out_serial_id
        FROM exchange.reserves_out
      WHERE reserves_out.h_blind_ev = blind_ev
    );
    RETURN QUERY
      SELECT kc.denom_sig,
             kc.denominations_serial,
             rc.coin_pub,
             rc.coin_sig,
             rc.coin_blind,
             rc.amount_val,
             rc.amount_frac,
             rc.recoup_timestamp
      FROM (
        SELECT *
        FROM exchange.known_coins
        WHERE known_coins.coin_pub = c_pub
      ) kc
      JOIN (
        SELECT *
        FROM exchange.recoup
        WHERE recoup.coin_pub = c_pub
      ) rc USING (coin_pub);
  END LOOP;
END;
$$;

COMMENT ON FUNCTION exchange_do_recoup_by_reserve
  IS 'Recoup by reserve as a function to make sure we hit only the needed partition and not all when joining as joins on distributed tables fetch ALL rows from the shards';


CREATE OR REPLACE FUNCTION exchange_do_deposit(
  IN in_amount_with_fee_val INT8,
  IN in_amount_with_fee_frac INT4,
  IN in_h_contract_terms BYTEA,
  IN in_wire_salt BYTEA,
  IN in_wallet_timestamp INT8,
  IN in_exchange_timestamp INT8,
  IN in_refund_deadline INT8,
  IN in_wire_deadline INT8,
  IN in_merchant_pub BYTEA,
  IN in_receiver_wire_account VARCHAR,
  IN in_h_payto BYTEA,
  IN in_known_coin_id INT8,
  IN in_coin_pub BYTEA,
  IN in_coin_sig BYTEA,
  IN in_shard INT8,
  IN in_policy_blocked BOOLEAN,
  IN in_policy_details_serial_id INT8,
  OUT out_exchange_timestamp INT8,
  OUT out_balance_ok BOOLEAN,
  OUT out_conflict BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
  wtsi INT8; -- wire target serial id
BEGIN
-- Shards: INSERT policy_details (by policy_details_serial_id)
--         INSERT wire_targets (by h_payto), on CONFLICT DO NOTHING;
--         INSERT deposits (by coin_pub, shard), ON CONFLICT DO NOTHING;
--         UPDATE known_coins (by coin_pub)

INSERT INTO exchange.wire_targets
  (wire_target_h_payto
  ,payto_uri)
  VALUES
  (in_h_payto
  ,in_receiver_wire_account)
ON CONFLICT DO NOTHING -- for CONFLICT ON (wire_target_h_payto)
  RETURNING wire_target_serial_id INTO wtsi;

IF NOT FOUND
THEN
  SELECT wire_target_serial_id
  INTO wtsi
  FROM exchange.wire_targets
  WHERE wire_target_h_payto=in_h_payto;
END IF;


INSERT INTO exchange.deposits
  (shard
  ,coin_pub
  ,known_coin_id
  ,amount_with_fee_val
  ,amount_with_fee_frac
  ,wallet_timestamp
  ,exchange_timestamp
  ,refund_deadline
  ,wire_deadline
  ,merchant_pub
  ,h_contract_terms
  ,coin_sig
  ,wire_salt
  ,wire_target_h_payto
  ,policy_blocked
  ,policy_details_serial_id
  )
  VALUES
  (in_shard
  ,in_coin_pub
  ,in_known_coin_id
  ,in_amount_with_fee_val
  ,in_amount_with_fee_frac
  ,in_wallet_timestamp
  ,in_exchange_timestamp
  ,in_refund_deadline
  ,in_wire_deadline
  ,in_merchant_pub
  ,in_h_contract_terms
  ,in_coin_sig
  ,in_wire_salt
  ,in_h_payto
  ,in_policy_blocked
  ,in_policy_details_serial_id)
  ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- Idempotency check: see if an identical record exists.
  -- Note that by checking 'coin_sig', we implicitly check
  -- identity over everything that the signature covers.
  -- We do select over merchant_pub and wire_target_h_payto
  -- primarily here to maximally use the existing index.
  SELECT
     exchange_timestamp
   INTO
     out_exchange_timestamp
   FROM exchange.deposits
   WHERE shard=in_shard
     AND merchant_pub=in_merchant_pub
     AND wire_target_h_payto=in_h_payto
     AND coin_pub=in_coin_pub
     AND coin_sig=in_coin_sig;
     -- AND policy_details_serial_id=in_policy_details_serial_id; -- FIXME: is this required for idempotency?

  IF NOT FOUND
  THEN
    -- Deposit exists, but with differences. Not allowed.
    out_balance_ok=FALSE;
    out_conflict=TRUE;
    RETURN;
  END IF;

  -- Idempotent request known, return success.
  out_balance_ok=TRUE;
  out_conflict=FALSE;

  RETURN;
END IF;


out_exchange_timestamp=in_exchange_timestamp;

-- Check and update balance of the coin.
UPDATE known_coins
  SET
    remaining_frac=remaining_frac-in_amount_with_fee_frac
       + CASE
         WHEN remaining_frac < in_amount_with_fee_frac
         THEN 100000000
         ELSE 0
         END,
    remaining_val=remaining_val-in_amount_with_fee_val
       - CASE
         WHEN remaining_frac < in_amount_with_fee_frac
         THEN 1
         ELSE 0
         END
  WHERE coin_pub=in_coin_pub
    AND ( (remaining_val > in_amount_with_fee_val) OR
          ( (remaining_frac >= in_amount_with_fee_frac) AND
            (remaining_val >= in_amount_with_fee_val) ) );

IF NOT FOUND
THEN
  -- Insufficient balance.
  out_balance_ok=FALSE;
  out_conflict=FALSE;
  RETURN;
END IF;

-- Everything fine, return success!
out_balance_ok=TRUE;
out_conflict=FALSE;

END $$;



CREATE OR REPLACE FUNCTION exchange_do_melt(
  IN in_cs_rms BYTEA,
  IN in_amount_with_fee_val INT8,
  IN in_amount_with_fee_frac INT4,
  IN in_rc BYTEA,
  IN in_old_coin_pub BYTEA,
  IN in_old_coin_sig BYTEA,
  IN in_known_coin_id INT8, -- not used, but that's OK
  IN in_noreveal_index INT4,
  IN in_zombie_required BOOLEAN,
  OUT out_balance_ok BOOLEAN,
  OUT out_zombie_bad BOOLEAN,
  OUT out_noreveal_index INT4)
LANGUAGE plpgsql
AS $$
DECLARE
  denom_max INT8;
BEGIN
-- Shards: INSERT refresh_commitments (by rc)
-- (rare:) SELECT refresh_commitments (by old_coin_pub) -- crosses shards!
-- (rare:) SEELCT refresh_revealed_coins (by melt_serial_id)
-- (rare:) PERFORM recoup_refresh (by rrc_serial) -- crosses shards!
--         UPDATE known_coins (by coin_pub)

INSERT INTO exchange.refresh_commitments
  (rc
  ,old_coin_pub
  ,old_coin_sig
  ,amount_with_fee_val
  ,amount_with_fee_frac
  ,noreveal_index
  )
  VALUES
  (in_rc
  ,in_old_coin_pub
  ,in_old_coin_sig
  ,in_amount_with_fee_val
  ,in_amount_with_fee_frac
  ,in_noreveal_index)
  ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- Idempotency check: see if an identical record exists.
  out_noreveal_index=-1;
  SELECT
     noreveal_index
    INTO
     out_noreveal_index
    FROM exchange.refresh_commitments
   WHERE rc=in_rc;
  out_balance_ok=FOUND;
  out_zombie_bad=FALSE; -- zombie is OK
  RETURN;
END IF;


IF in_zombie_required
THEN
  -- Check if this coin was part of a refresh
  -- operation that was subsequently involved
  -- in a recoup operation.  We begin by all
  -- refresh operations our coin was involved
  -- with, then find all associated reveal
  -- operations, and then see if any of these
  -- reveal operations was involved in a recoup.
  PERFORM
    FROM exchange.recoup_refresh
   WHERE rrc_serial IN
    (SELECT rrc_serial
       FROM exchange.refresh_revealed_coins
      WHERE melt_serial_id IN
      (SELECT melt_serial_id
         FROM exchange.refresh_commitments
        WHERE old_coin_pub=in_old_coin_pub));
  IF NOT FOUND
  THEN
    out_zombie_bad=TRUE;
    out_balance_ok=FALSE;
    RETURN;
  END IF;
END IF;

out_zombie_bad=FALSE; -- zombie is OK


-- Check and update balance of the coin.
UPDATE known_coins
  SET
    remaining_frac=remaining_frac-in_amount_with_fee_frac
       + CASE
         WHEN remaining_frac < in_amount_with_fee_frac
         THEN 100000000
         ELSE 0
         END,
    remaining_val=remaining_val-in_amount_with_fee_val
       - CASE
         WHEN remaining_frac < in_amount_with_fee_frac
         THEN 1
         ELSE 0
         END
  WHERE coin_pub=in_old_coin_pub
    AND ( (remaining_val > in_amount_with_fee_val) OR
          ( (remaining_frac >= in_amount_with_fee_frac) AND
            (remaining_val >= in_amount_with_fee_val) ) );

IF NOT FOUND
THEN
  -- Insufficient balance.
  out_noreveal_index=-1;
  out_balance_ok=FALSE;
  RETURN;
END IF;



-- Special actions needed for a CS melt?
IF NOT NULL in_cs_rms
THEN
  -- Get maximum denominations serial value in
  -- existence, this will determine how long the
  -- nonce will be locked.
  SELECT
      denominations_serial
    INTO
      denom_max
    FROM exchange.denominations
      ORDER BY denominations_serial DESC
      LIMIT 1;

  -- Cache CS signature to prevent replays in the future
  -- (and check if cached signature exists at the same time).
  INSERT INTO exchange.cs_nonce_locks
    (nonce
    ,max_denomination_serial
    ,op_hash)
  VALUES
    (cs_rms
    ,denom_serial
    ,in_rc)
  ON CONFLICT DO NOTHING;

  IF NOT FOUND
  THEN
    -- Record exists, make sure it is the same
    SELECT 1
      FROM exchange.cs_nonce_locks
     WHERE nonce=cs_rms
       AND op_hash=in_rc;

    IF NOT FOUND
    THEN
       -- Nonce reuse detected
       out_balance_ok=FALSE;
       out_zombie_bad=FALSE;
       out_noreveal_index=42; -- FIXME: return error message more nicely!
       ASSERT false, 'nonce reuse attempted by client';
    END IF;
  END IF;
END IF;

-- Everything fine, return success!
out_balance_ok=TRUE;
out_noreveal_index=in_noreveal_index;

END $$;



CREATE OR REPLACE FUNCTION exchange_do_refund(
  IN in_amount_with_fee_val INT8,
  IN in_amount_with_fee_frac INT4,
  IN in_amount_val INT8,
  IN in_amount_frac INT4,
  IN in_deposit_fee_val INT8,
  IN in_deposit_fee_frac INT4,
  IN in_h_contract_terms BYTEA,
  IN in_rtransaction_id INT8,
  IN in_deposit_shard INT8,
  IN in_known_coin_id INT8,
  IN in_coin_pub BYTEA,
  IN in_merchant_pub BYTEA,
  IN in_merchant_sig BYTEA,
  OUT out_not_found BOOLEAN,
  OUT out_refund_ok BOOLEAN,
  OUT out_gone BOOLEAN,
  OUT out_conflict BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
  dsi INT8; -- ID of deposit being refunded
DECLARE
  tmp_val INT8; -- total amount refunded
DECLARE
  tmp_frac INT8; -- total amount refunded
DECLARE
  deposit_val INT8; -- amount that was originally deposited
DECLARE
  deposit_frac INT8; -- amount that was originally deposited
BEGIN
-- Shards: SELECT deposits (coin_pub, shard, h_contract_terms, merchant_pub)
--         INSERT refunds (by coin_pub, rtransaction_id) ON CONFLICT DO NOTHING
--         SELECT refunds (by coin_pub)
--         UPDATE known_coins (by coin_pub)

SELECT
   deposit_serial_id
  ,amount_with_fee_val
  ,amount_with_fee_frac
  ,done
INTO
   dsi
  ,deposit_val
  ,deposit_frac
  ,out_gone
FROM exchange.deposits
 WHERE coin_pub=in_coin_pub
  AND shard=in_deposit_shard
  AND merchant_pub=in_merchant_pub
  AND h_contract_terms=in_h_contract_terms;

IF NOT FOUND
THEN
  -- No matching deposit found!
  out_refund_ok=FALSE;
  out_conflict=FALSE;
  out_not_found=TRUE;
  out_gone=FALSE;
  RETURN;
END IF;

INSERT INTO exchange.refunds
  (deposit_serial_id
  ,coin_pub
  ,merchant_sig
  ,rtransaction_id
  ,amount_with_fee_val
  ,amount_with_fee_frac
  )
  VALUES
  (dsi
  ,in_coin_pub
  ,in_merchant_sig
  ,in_rtransaction_id
  ,in_amount_with_fee_val
  ,in_amount_with_fee_frac)
  ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- Idempotency check: see if an identical record exists.
  -- Note that by checking 'coin_sig', we implicitly check
  -- identity over everything that the signature covers.
  -- We do select over merchant_pub and h_contract_terms
  -- primarily here to maximally use the existing index.
   PERFORM
   FROM exchange.refunds
   WHERE coin_pub=in_coin_pub
     AND deposit_serial_id=dsi
     AND rtransaction_id=in_rtransaction_id
     AND amount_with_fee_val=in_amount_with_fee_val
     AND amount_with_fee_frac=in_amount_with_fee_frac;

  IF NOT FOUND
  THEN
    -- Deposit exists, but have conflicting refund.
    out_refund_ok=FALSE;
    out_conflict=TRUE;
    out_not_found=FALSE;
    RETURN;
  END IF;

  -- Idempotent request known, return success.
  out_refund_ok=TRUE;
  out_conflict=FALSE;
  out_not_found=FALSE;
  out_gone=FALSE;
  RETURN;
END IF;

IF out_gone
THEN
  -- money already sent to the merchant. Tough luck.
  out_refund_ok=FALSE;
  out_conflict=FALSE;
  out_not_found=FALSE;
  RETURN;
END IF;

-- Check refund balance invariant.
SELECT
   SUM(amount_with_fee_val) -- overflow here is not plausible
  ,SUM(CAST(amount_with_fee_frac AS INT8)) -- compute using 64 bits
  INTO
   tmp_val
  ,tmp_frac
  FROM exchange.refunds
  WHERE coin_pub=in_coin_pub
    AND deposit_serial_id=dsi;
IF tmp_val IS NULL
THEN
  RAISE NOTICE 'failed to sum up existing refunds';
  out_refund_ok=FALSE;
  out_conflict=FALSE;
  out_not_found=FALSE;
  RETURN;
END IF;

-- Normalize result before continuing
tmp_val = tmp_val + tmp_frac / 100000000;
tmp_frac = tmp_frac % 100000000;

-- Actually check if the deposits are sufficient for the refund. Verbosely. ;-)
IF (tmp_val < deposit_val)
THEN
  out_refund_ok=TRUE;
ELSE
  IF (tmp_val = deposit_val) AND (tmp_frac <= deposit_frac)
  THEN
    out_refund_ok=TRUE;
  ELSE
    out_refund_ok=FALSE;
  END IF;
END IF;

IF (tmp_val = deposit_val) AND (tmp_frac = deposit_frac)
THEN
  -- Refunds have reached the full value of the original
  -- deposit. Also refund the deposit fee.
  in_amount_frac = in_amount_frac + in_deposit_fee_frac;
  in_amount_val = in_amount_val + in_deposit_fee_val;

  -- Normalize result before continuing
  in_amount_val = in_amount_val + in_amount_frac / 100000000;
  in_amount_frac = in_amount_frac % 100000000;
END IF;

-- Update balance of the coin.
UPDATE known_coins
  SET
    remaining_frac=remaining_frac+in_amount_frac
       - CASE
         WHEN remaining_frac+in_amount_frac >= 100000000
         THEN 100000000
         ELSE 0
         END,
    remaining_val=remaining_val+in_amount_val
       + CASE
         WHEN remaining_frac+in_amount_frac >= 100000000
         THEN 1
         ELSE 0
         END
  WHERE coin_pub=in_coin_pub;


out_conflict=FALSE;
out_not_found=FALSE;

END $$;

-- COMMENT ON FUNCTION exchange_do_refund(INT8, INT4, BYTEA, BOOLEAN, BOOLEAN)
--  IS 'Executes a refund operation, checking that the corresponding deposit was sufficient to cover the refunded amount';




CREATE OR REPLACE FUNCTION exchange_do_recoup_to_reserve(
  IN in_reserve_pub BYTEA,
  IN in_reserve_out_serial_id INT8,
  IN in_coin_blind BYTEA,
  IN in_coin_pub BYTEA,
  IN in_known_coin_id INT8,
  IN in_coin_sig BYTEA,
  IN in_reserve_gc INT8,
  IN in_reserve_expiration INT8,
  IN in_recoup_timestamp INT8,
  OUT out_recoup_ok BOOLEAN,
  OUT out_internal_failure BOOLEAN,
  OUT out_recoup_timestamp INT8)
LANGUAGE plpgsql
AS $$
DECLARE
  tmp_val INT8; -- amount recouped
DECLARE
  tmp_frac INT8; -- amount recouped
BEGIN
-- Shards: SELECT known_coins (by coin_pub)
--         SELECT recoup      (by coin_pub)
--         UPDATE known_coins (by coin_pub)
--         UPDATE reserves (by reserve_pub)
--         INSERT recoup      (by coin_pub)

out_internal_failure=FALSE;


-- Check remaining balance of the coin.
SELECT
   remaining_frac
  ,remaining_val
 INTO
   tmp_frac
  ,tmp_val
FROM exchange.known_coins
  WHERE coin_pub=in_coin_pub;

IF NOT FOUND
THEN
  out_internal_failure=TRUE;
  out_recoup_ok=FALSE;
  RETURN;
END IF;

IF tmp_val + tmp_frac = 0
THEN
  -- Check for idempotency
  SELECT
    recoup_timestamp
  INTO
    out_recoup_timestamp
    FROM exchange.recoup
    WHERE coin_pub=in_coin_pub;

  out_recoup_ok=FOUND;
  RETURN;
END IF;


-- Update balance of the coin.
UPDATE known_coins
  SET
     remaining_frac=0
    ,remaining_val=0
  WHERE coin_pub=in_coin_pub;


-- Credit the reserve and update reserve timers.
UPDATE reserves
  SET
    current_balance_frac=current_balance_frac+tmp_frac
       - CASE
         WHEN current_balance_frac+tmp_frac >= 100000000
         THEN 100000000
         ELSE 0
         END,
    current_balance_val=current_balance_val+tmp_val
       + CASE
         WHEN current_balance_frac+tmp_frac >= 100000000
         THEN 1
         ELSE 0
         END,
    gc_date=GREATEST(gc_date, in_reserve_gc),
    expiration_date=GREATEST(expiration_date, in_reserve_expiration)
  WHERE reserve_pub=in_reserve_pub;


IF NOT FOUND
THEN
  RAISE NOTICE 'failed to increase reserve balance from recoup';
  out_recoup_ok=TRUE;
  out_internal_failure=TRUE;
  RETURN;
END IF;


INSERT INTO exchange.recoup
  (coin_pub
  ,coin_sig
  ,coin_blind
  ,amount_val
  ,amount_frac
  ,recoup_timestamp
  ,reserve_out_serial_id
  )
VALUES
  (in_coin_pub
  ,in_coin_sig
  ,in_coin_blind
  ,tmp_val
  ,tmp_frac
  ,in_recoup_timestamp
  ,in_reserve_out_serial_id);

-- Normal end, everything is fine.
out_recoup_ok=TRUE;
out_recoup_timestamp=in_recoup_timestamp;

END $$;

-- COMMENT ON FUNCTION exchange_do_recoup_to_reserve(INT8, INT4, BYTEA, BOOLEAN, BOOLEAN)
--  IS 'Executes a recoup of a coin that was withdrawn from a reserve';






CREATE OR REPLACE FUNCTION exchange_do_recoup_to_coin(
  IN in_old_coin_pub BYTEA,
  IN in_rrc_serial INT8,
  IN in_coin_blind BYTEA,
  IN in_coin_pub BYTEA,
  IN in_known_coin_id INT8,
  IN in_coin_sig BYTEA,
  IN in_recoup_timestamp INT8,
  OUT out_recoup_ok BOOLEAN,
  OUT out_internal_failure BOOLEAN,
  OUT out_recoup_timestamp INT8)
LANGUAGE plpgsql
AS $$
DECLARE
  tmp_val INT8; -- amount recouped
DECLARE
  tmp_frac INT8; -- amount recouped
BEGIN

-- Shards: UPDATE known_coins (by coin_pub)
--         SELECT recoup_refresh (by coin_pub)
--         UPDATE known_coins (by coin_pub)
--         INSERT recoup_refresh (by coin_pub)


out_internal_failure=FALSE;


-- Check remaining balance of the coin.
SELECT
   remaining_frac
  ,remaining_val
 INTO
   tmp_frac
  ,tmp_val
FROM exchange.known_coins
  WHERE coin_pub=in_coin_pub;

IF NOT FOUND
THEN
  out_internal_failure=TRUE;
  out_recoup_ok=FALSE;
  RETURN;
END IF;

IF tmp_val + tmp_frac = 0
THEN
  -- Check for idempotency
  SELECT
      recoup_timestamp
    INTO
      out_recoup_timestamp
    FROM exchange.recoup_refresh
    WHERE coin_pub=in_coin_pub;
  out_recoup_ok=FOUND;
  RETURN;
END IF;

-- Update balance of the coin.
UPDATE known_coins
  SET
     remaining_frac=0
    ,remaining_val=0
  WHERE coin_pub=in_coin_pub;


-- Credit the old coin.
UPDATE known_coins
  SET
    remaining_frac=remaining_frac+tmp_frac
       - CASE
         WHEN remaining_frac+tmp_frac >= 100000000
         THEN 100000000
         ELSE 0
         END,
    remaining_val=remaining_val+tmp_val
       + CASE
         WHEN remaining_frac+tmp_frac >= 100000000
         THEN 1
         ELSE 0
         END
  WHERE coin_pub=in_old_coin_pub;


IF NOT FOUND
THEN
  RAISE NOTICE 'failed to increase old coin balance from recoup';
  out_recoup_ok=TRUE;
  out_internal_failure=TRUE;
  RETURN;
END IF;


INSERT INTO exchange.recoup_refresh
  (coin_pub
  ,known_coin_id
  ,coin_sig
  ,coin_blind
  ,amount_val
  ,amount_frac
  ,recoup_timestamp
  ,rrc_serial
  )
VALUES
  (in_coin_pub
  ,in_known_coin_id
  ,in_coin_sig
  ,in_coin_blind
  ,tmp_val
  ,tmp_frac
  ,in_recoup_timestamp
  ,in_rrc_serial);

-- Normal end, everything is fine.
out_recoup_ok=TRUE;
out_recoup_timestamp=in_recoup_timestamp;

END $$;




-- COMMENT ON FUNCTION exchange_do_recoup_to_coin(INT8, INT4, BYTEA, BOOLEAN, BOOLEAN)
--  IS 'Executes a recoup-refresh of a coin that was obtained from a refresh-reveal process';



CREATE OR REPLACE PROCEDURE exchange_do_gc(
  IN in_ancient_date INT8,
  IN in_now INT8)
LANGUAGE plpgsql
AS $$
DECLARE
  reserve_uuid_min INT8; -- minimum reserve UUID still alive
DECLARE
  melt_min INT8; -- minimum melt still alive
DECLARE
  coin_min INT8; -- minimum known_coin still alive
DECLARE
  deposit_min INT8; -- minimum deposit still alive
DECLARE
  reserve_out_min INT8; -- minimum reserve_out still alive
DECLARE
  denom_min INT8; -- minimum denomination still alive
BEGIN

DELETE FROM exchange.prewire
  WHERE finished=TRUE;

DELETE FROM exchange.wire_fee
  WHERE end_date < in_ancient_date;

-- TODO: use closing fee as threshold?
DELETE FROM exchange.reserves
  WHERE gc_date < in_now
    AND current_balance_val = 0
    AND current_balance_frac = 0;

SELECT
     reserve_out_serial_id
  INTO
     reserve_out_min
  FROM exchange.reserves_out
  ORDER BY reserve_out_serial_id ASC
  LIMIT 1;

DELETE FROM exchange.recoup
  WHERE reserve_out_serial_id < reserve_out_min;
-- FIXME: recoup_refresh lacks GC!

SELECT
     reserve_uuid
  INTO
     reserve_uuid_min
  FROM exchange.reserves
  ORDER BY reserve_uuid ASC
  LIMIT 1;

DELETE FROM exchange.reserves_out
  WHERE reserve_uuid < reserve_uuid_min;

-- FIXME: this query will be horribly slow;
-- need to find another way to formulate it...
DELETE FROM exchange.denominations
  WHERE expire_legal < in_now
    AND denominations_serial NOT IN
      (SELECT DISTINCT denominations_serial
         FROM exchange.reserves_out)
    AND denominations_serial NOT IN
      (SELECT DISTINCT denominations_serial
         FROM exchange.known_coins
        WHERE coin_pub IN
          (SELECT DISTINCT coin_pub
             FROM exchange.recoup))
    AND denominations_serial NOT IN
      (SELECT DISTINCT denominations_serial
         FROM exchange.known_coins
        WHERE coin_pub IN
          (SELECT DISTINCT coin_pub
             FROM exchange.recoup_refresh));

SELECT
     melt_serial_id
  INTO
     melt_min
  FROM exchange.refresh_commitments
  ORDER BY melt_serial_id ASC
  LIMIT 1;

DELETE FROM exchange.refresh_revealed_coins
  WHERE melt_serial_id < melt_min;

DELETE FROM exchange.refresh_transfer_keys
  WHERE melt_serial_id < melt_min;

SELECT
     known_coin_id
  INTO
     coin_min
  FROM exchange.known_coins
  ORDER BY known_coin_id ASC
  LIMIT 1;

DELETE FROM exchange.deposits
  WHERE known_coin_id < coin_min;

SELECT
     deposit_serial_id
  INTO
     deposit_min
  FROM exchange.deposits
  ORDER BY deposit_serial_id ASC
  LIMIT 1;

DELETE FROM exchange.refunds
  WHERE deposit_serial_id < deposit_min;

DELETE FROM exchange.aggregation_tracking
  WHERE deposit_serial_id < deposit_min;

SELECT
     denominations_serial
  INTO
     denom_min
  FROM exchange.denominations
  ORDER BY denominations_serial ASC
  LIMIT 1;

DELETE FROM exchange.cs_nonce_locks
  WHERE max_denomination_serial <= denom_min;

END $$;




CREATE OR REPLACE FUNCTION exchange_do_purse_deposit(
  IN in_partner_id INT8,
  IN in_purse_pub BYTEA,
  IN in_amount_with_fee_val INT8,
  IN in_amount_with_fee_frac INT4,
  IN in_coin_pub BYTEA,
  IN in_coin_sig BYTEA,
  IN in_amount_without_fee_val INT8,
  IN in_amount_without_fee_frac INT4,
  IN in_reserve_expiration INT8,
  IN in_now INT8,
  OUT out_balance_ok BOOLEAN,
  OUT out_conflict BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
  was_merged BOOLEAN;
DECLARE
  psi INT8; -- partner's serial ID (set if merged)
DECLARE
  my_amount_val INT8; -- total in purse
DECLARE
  my_amount_frac INT4; -- total in purse
DECLARE
  was_paid BOOLEAN;
DECLARE
  my_in_reserve_quota BOOLEAN;
DECLARE
  my_reserve_pub BYTEA;
BEGIN

-- Store the deposit request.
INSERT INTO exchange.purse_deposits
  (partner_serial_id
  ,purse_pub
  ,coin_pub
  ,amount_with_fee_val
  ,amount_with_fee_frac
  ,coin_sig)
  VALUES
  (in_partner_id
  ,in_purse_pub
  ,in_coin_pub
  ,in_amount_with_fee_val
  ,in_amount_with_fee_frac
  ,in_coin_sig)
  ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- Idempotency check: check if coin_sig is the same,
  -- if so, success, otherwise conflict!
  PERFORM
  FROM exchange.purse_deposits
  WHERE coin_pub = in_coin_pub
    AND purse_pub = in_purse_pub
    AND coin_sig = in_cion_sig;
  IF NOT FOUND
  THEN
    -- Deposit exists, but with differences. Not allowed.
    out_balance_ok=FALSE;
    out_conflict=TRUE;
    RETURN;
  END IF;
END IF;


-- Debit the coin
-- Check and update balance of the coin.
UPDATE known_coins
  SET
    remaining_frac=remaining_frac-in_amount_with_fee_frac
       + CASE
         WHEN remaining_frac < in_amount_with_fee_frac
         THEN 100000000
         ELSE 0
         END,
    remaining_val=remaining_val-in_amount_with_fee_val
       - CASE
         WHEN remaining_frac < in_amount_with_fee_frac
         THEN 1
         ELSE 0
         END
  WHERE coin_pub=in_coin_pub
    AND ( (remaining_val > in_amount_with_fee_val) OR
          ( (remaining_frac >= in_amount_with_fee_frac) AND
            (remaining_val >= in_amount_with_fee_val) ) );

IF NOT FOUND
THEN
  -- Insufficient balance.
  out_balance_ok=FALSE;
  out_conflict=FALSE;
  RETURN;
END IF;


-- Credit the purse.
UPDATE purse_requests
  SET
    balance_frac=balance_frac+in_amount_without_fee_frac
       - CASE
         WHEN balance_frac+in_amount_without_fee_frac >= 100000000
         THEN 100000000
         ELSE 0
         END,
    balance_val=balance_val+in_amount_without_fee_val
       + CASE
         WHEN balance_frac+in_amount_without_fee_frac >= 100000000
         THEN 1
         ELSE 0
         END
  WHERE purse_pub=in_purse_pub;

out_conflict=FALSE;
out_balance_ok=TRUE;

-- See if we can finish the merge or need to update the trigger time and partner.
SELECT partner_serial_id
      ,reserve_pub
  INTO psi
      ,my_reserve_pub
  FROM exchange.purse_merges
 WHERE purse_pub=in_purse_pub;

IF NOT FOUND
THEN
  RETURN;
END IF;

SELECT
    amount_with_fee_val
   ,amount_with_fee_frac
   ,in_reserve_quota
  INTO
    my_amount_val
   ,my_amount_frac
   ,my_in_reserve_quota
  FROM exchange.purse_requests
  WHERE (purse_pub=in_purse_pub)
    AND ( ( ( (amount_with_fee_val <= balance_val)
          AND (amount_with_fee_frac <= balance_frac) )
         OR (amount_with_fee_val < balance_val) ) );
IF NOT FOUND
THEN
  RETURN;
END IF;

-- Remember how this purse was finished.
INSERT INTO purse_decision
  (purse_pub
  ,action_timestamp
  ,refunded)
VALUES
  (in_purse_pub
  ,in_now
  ,FALSE);

IF (my_in_reserve_quota)
THEN
  UPDATE reserves
    SET purses_active=purses_active-1
  WHERE reserve_pub IN
    (SELECT reserve_pub
       FROM exchange.purse_merges
      WHERE purse_pub=my_purse_pub
     LIMIT 1);
END IF;


IF (0 != psi)
THEN
  -- The taler-exchange-router will take care of this.
  UPDATE purse_actions
     SET action_date=0 --- "immediately"
        ,partner_serial_id=psi
   WHERE purse_pub=in_purse_pub;
ELSE
  -- This is a local reserve, update balance immediately.
  INSERT INTO reserves
    (reserve_pub
    ,current_balance_frac
    ,current_balance_val
    ,expiration_date
    ,gc_date)
  VALUES
    (my_reserve_pub
    ,my_amount_frac
    ,my_amount_val
    ,in_reserve_expiration
    ,in_reserve_expiration)
  ON CONFLICT DO NOTHING;

  IF NOT FOUND
  THEN

    UPDATE reserves
      SET
       current_balance_frac=current_balance_frac+my_amount_frac
        - CASE
          WHEN current_balance_frac + my_amount_frac >= 100000000
            THEN 100000000
          ELSE 0
          END
      ,current_balance_val=current_balance_val+my_amount_val
        + CASE
          WHEN current_balance_frac + my_amount_frac >= 100000000
            THEN 1
          ELSE 0
          END
      ,expiration_date=GREATEST(expiration_date,in_reserve_expiration)
      ,gc_date=GREATEST(gc_date,in_reserve_expiration)
      WHERE reserve_pub=my_reserve_pub;
  END IF;

END IF;


END $$;




CREATE OR REPLACE FUNCTION exchange_do_purse_merge(
  IN in_purse_pub BYTEA,
  IN in_merge_sig BYTEA,
  IN in_merge_timestamp INT8,
  IN in_reserve_sig BYTEA,
  IN in_partner_url VARCHAR,
  IN in_reserve_pub BYTEA,
  IN in_wallet_h_payto BYTEA,
  IN in_expiration_date INT8,
  OUT out_no_partner BOOLEAN,
  OUT out_no_balance BOOLEAN,
  OUT out_conflict BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
  my_amount_val INT8;
DECLARE
  my_amount_frac INT4;
DECLARE
  my_purse_fee_val INT8;
DECLARE
  my_purse_fee_frac INT4;
DECLARE
  my_partner_serial_id INT8;
DECLARE
  my_in_reserve_quota BOOLEAN;
BEGIN

IF in_partner_url IS NULL
THEN
  my_partner_serial_id=0;
ELSE
  SELECT
    partner_serial_id
  INTO
    my_partner_serial_id
  FROM exchange.partners
  WHERE partner_base_url=in_partner_url
    AND start_date <= in_merge_timestamp
    AND end_date > in_merge_timestamp;
  IF NOT FOUND
  THEN
    out_no_partner=TRUE;
    out_conflict=FALSE;
    RETURN;
  END IF;
END IF;

out_no_partner=FALSE;


-- Check purse is 'full'.
SELECT amount_with_fee_val
      ,amount_with_fee_frac
      ,purse_fee_val
      ,purse_fee_frac
      ,in_reserve_quota
  INTO my_amount_val
      ,my_amount_frac
      ,my_purse_fee_val
      ,my_purse_fee_frac
      ,my_in_reserve_quota
  FROM exchange.purse_requests
  WHERE purse_pub=in_purse_pub
    AND balance_val >= amount_with_fee_val
    AND ( (balance_frac >= amount_with_fee_frac) OR
          (balance_val > amount_with_fee_val) );
IF NOT FOUND
THEN
  out_no_balance=TRUE;
  out_conflict=FALSE;
  RETURN;
END IF;
out_no_balance=FALSE;

-- Store purse merge signature, checks for purse_pub uniqueness
INSERT INTO exchange.purse_merges
    (partner_serial_id
    ,reserve_pub
    ,purse_pub
    ,merge_sig
    ,merge_timestamp)
  VALUES
    (my_partner_serial_id
    ,in_reserve_pub
    ,in_purse_pub
    ,in_merge_sig
    ,in_merge_timestamp)
  ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- Idempotency check: see if an identical record exists.
  -- Note that by checking 'merge_sig', we implicitly check
  -- identity over everything that the signature covers.
  PERFORM
  FROM exchange.purse_merges
  WHERE purse_pub=in_purse_pub
     AND merge_sig=in_merge_sig;
  IF NOT FOUND
  THEN
     -- Purse was merged, but to some other reserve. Not allowed.
     out_conflict=TRUE;
     RETURN;
  END IF;

  -- "success"
  out_conflict=FALSE;
  RETURN;
END IF;
out_conflict=FALSE;


-- Initialize reserve, if not yet exists.
INSERT INTO reserves
  (reserve_pub
  ,expiration_date
  ,gc_date)
  VALUES
  (in_reserve_pub
  ,in_expiration_date
  ,in_expiration_date)
  ON CONFLICT DO NOTHING;

-- Remember how this purse was finished.
INSERT INTO purse_decision
  (purse_pub
  ,action_timestamp
  ,refunded)
VALUES
  (in_purse_pub
  ,in_merge_timestamp
  ,FALSE);

IF (my_in_reserve_quota)
THEN
  UPDATE reserves
    SET purses_active=purses_active-1
  WHERE reserve_pub IN
    (SELECT reserve_pub
       FROM exchange.purse_merges
      WHERE purse_pub=my_purse_pub
     LIMIT 1);
END IF;

-- Store account merge signature.
INSERT INTO exchange.account_merges
  (reserve_pub
  ,reserve_sig
  ,purse_pub
  ,wallet_h_payto)
  VALUES
  (in_reserve_pub
  ,in_reserve_sig
  ,in_purse_pub
  ,in_wallet_h_payto);

-- If we need a wad transfer, mark purse ready for it.
IF (0 != my_partner_serial_id)
THEN
  -- The taler-exchange-router will take care of this.
  UPDATE purse_actions
     SET action_date=0 --- "immediately"
        ,partner_serial_id=my_partner_serial_id
   WHERE purse_pub=in_purse_pub;
ELSE
  -- This is a local reserve, update reserve balance immediately.

  -- Refund the purse fee, by adding it to the purse value:
  my_amount_val = my_amount_val + my_purse_fee_val;
  my_amount_frac = my_amount_frac + my_purse_fee_frac;
  -- normalize result
  my_amount_val = my_amount_val + my_amount_frac / 100000000;
  my_amount_frac = my_amount_frac % 100000000;

  UPDATE exchange.reserves
  SET
    current_balance_frac=current_balance_frac+my_amount_frac
       - CASE
         WHEN current_balance_frac + my_amount_frac >= 100000000
         THEN 100000000
         ELSE 0
         END,
    current_balance_val=current_balance_val+my_amount_val
       + CASE
         WHEN current_balance_frac + my_amount_frac >= 100000000
         THEN 1
         ELSE 0
         END
  WHERE reserve_pub=in_reserve_pub;

END IF;


RETURN;

END $$;

COMMENT ON FUNCTION exchange_do_purse_merge(BYTEA, BYTEA, INT8, BYTEA, VARCHAR, BYTEA, BYTEA, INT8)
  IS 'Checks that the partner exists, the purse has not been merged with a different reserve and that the purse is full. If so, persists the merge data and either merges the purse with the reserve or marks it as ready for the taler-exchange-router. Caller MUST abort the transaction on failures so as to not persist data by accident.';


CREATE OR REPLACE FUNCTION exchange_do_reserve_purse(
  IN in_purse_pub BYTEA,
  IN in_merge_sig BYTEA,
  IN in_merge_timestamp INT8,
  IN in_reserve_sig BYTEA,
  IN in_reserve_quota BOOLEAN,
  IN in_purse_fee_val INT8,
  IN in_purse_fee_frac INT4,
  IN in_reserve_pub BYTEA,
  IN in_wallet_h_payto BYTEA,
  OUT out_no_funds BOOLEAN,
  OUT out_no_reserve BOOLEAN,
  OUT out_conflict BOOLEAN)
LANGUAGE plpgsql
AS $$
BEGIN

-- Store purse merge signature, checks for purse_pub uniqueness
INSERT INTO exchange.purse_merges
    (partner_serial_id
    ,reserve_pub
    ,purse_pub
    ,merge_sig
    ,merge_timestamp)
  VALUES
    (0
    ,in_reserve_pub
    ,in_purse_pub
    ,in_merge_sig
    ,in_merge_timestamp)
  ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- Idempotency check: see if an identical record exists.
  -- Note that by checking 'merge_sig', we implicitly check
  -- identity over everything that the signature covers.
  PERFORM
  FROM exchange.purse_merges
  WHERE purse_pub=in_purse_pub
     AND merge_sig=in_merge_sig;
  IF NOT FOUND
  THEN
     -- Purse was merged, but to some other reserve. Not allowed.
     out_conflict=TRUE;
     out_no_reserve=FALSE;
     out_no_funds=FALSE;
     RETURN;
  END IF;

  -- "success"
  out_conflict=FALSE;
  out_no_funds=FALSE;
  out_no_reserve=FALSE;
  RETURN;
END IF;
out_conflict=FALSE;

PERFORM
  FROM exchange.reserves
 WHERE reserve_pub=in_reserve_pub;

out_no_reserve = NOT FOUND;

IF (in_reserve_quota)
THEN
  -- Increment active purses per reserve (and check this is allowed)
  IF (out_no_reserve)
  THEN
    out_no_funds=TRUE;
    RETURN;
  END IF;
  UPDATE exchange.reserves
     SET purses_active=purses_active+1
   WHERE reserve_pub=in_reserve_pub
     AND purses_active < purses_allowed;
  IF NOT FOUND
  THEN
    out_no_funds=TRUE;
    RETURN;
  END IF;
ELSE
  --  UPDATE reserves balance (and check if balance is enough to pay the fee)
  IF (out_no_reserve)
  THEN
    IF ( (0 != in_purse_fee_val) OR
         (0 != in_purse_fee_frac) )
    THEN
      out_no_funds=TRUE;
      RETURN;
    END IF;
  ELSE
    UPDATE exchange.reserves
      SET
        current_balance_frac=current_balance_frac-in_purse_fee_frac
         + CASE
         WHEN current_balance_frac < in_purse_fee_frac
         THEN 100000000
         ELSE 0
         END,
       current_balance_val=current_balance_val-in_purse_fee_val
         - CASE
         WHEN current_balance_frac < in_purse_fee_frac
         THEN 1
         ELSE 0
         END
      WHERE reserve_pub=in_reserve_pub
        AND ( (current_balance_val > in_purse_fee_val) OR
              ( (current_balance_frac >= in_purse_fee_frac) AND
                (current_balance_val >= in_purse_fee_val) ) );
    IF NOT FOUND
    THEN
      out_no_funds=TRUE;
      RETURN;
    END IF;
  END IF;
END IF;

out_no_funds=FALSE;


-- Store account merge signature.
INSERT INTO exchange.account_merges
  (reserve_pub
  ,reserve_sig
  ,purse_pub
  ,wallet_h_payto)
  VALUES
  (in_reserve_pub
  ,in_reserve_sig
  ,in_purse_pub
  ,in_wallet_h_payto);

END $$;

COMMENT ON FUNCTION exchange_do_reserve_purse(BYTEA, BYTEA, INT8, BYTEA, BOOLEAN, INT8, INT4, BYTEA, BYTEA)
  IS 'Create a purse for a reserve.';






CREATE OR REPLACE FUNCTION exchange_do_account_merge(
  IN in_purse_pub BYTEA,
  IN in_reserve_pub BYTEA,
  IN in_reserve_sig BYTEA,
  OUT out_balance_ok BOOLEAN,
  OUT out_conflict BOOLEAN)
LANGUAGE plpgsql
AS $$
BEGIN
  -- FIXME: function/API is dead! Do DCE?
END $$;



CREATE OR REPLACE FUNCTION exchange_do_expire_purse(
  IN in_start_time INT8,
  IN in_end_time INT8,
  IN in_now INT8,
  OUT out_found BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
  my_purse_pub BYTEA;
DECLARE
  my_deposit record;
DECLARE
  my_in_reserve_quota BOOLEAN;
BEGIN

-- FIXME: we should probably do this in a loop
-- and expire all at once, instead of one per query
SELECT purse_pub
      ,in_reserve_quota
  INTO my_purse_pub
      ,my_in_reserve_quota
  FROM exchange.purse_requests
 WHERE (purse_expiration >= in_start_time) AND
       (purse_expiration < in_end_time) AND
   purse_pub NOT IN (SELECT purse_pub
                       FROM purse_decision)
 ORDER BY purse_expiration ASC
 LIMIT 1;
out_found = FOUND;
IF NOT FOUND
THEN
  RETURN;
END IF;

INSERT INTO purse_decision
  (purse_pub
  ,action_timestamp
  ,refunded)
VALUES
  (my_purse_pub
  ,in_now
  ,TRUE);

IF (my_in_reserve_quota)
THEN
  UPDATE reserves
    SET purses_active=purses_active-1
  WHERE reserve_pub IN
    (SELECT reserve_pub
       FROM exchange.purse_merges
      WHERE purse_pub=my_purse_pub
     LIMIT 1);
END IF;

-- restore balance to each coin deposited into the purse
FOR my_deposit IN
  SELECT coin_pub
        ,amount_with_fee_val
        ,amount_with_fee_frac
    FROM exchange.purse_deposits
  WHERE purse_pub = my_purse_pub
LOOP
  UPDATE exchange.known_coins SET
    remaining_frac=remaining_frac+my_deposit.amount_with_fee_frac
     - CASE
       WHEN remaining_frac+my_deposit.amount_with_fee_frac >= 100000000
       THEN 100000000
       ELSE 0
       END,
    remaining_val=remaining_val+my_deposit.amount_with_fee_val
     + CASE
       WHEN remaining_frac+my_deposit.amount_with_fee_frac >= 100000000
       THEN 1
       ELSE 0
       END
    WHERE coin_pub = my_deposit.coin_pub;
  END LOOP;
END $$;

COMMENT ON FUNCTION exchange_do_expire_purse(INT8,INT8,INT8)
  IS 'Finds an expired purse in the given time range and refunds the coins (if any).';




CREATE OR REPLACE FUNCTION exchange_do_history_request(
  IN in_reserve_pub BYTEA,
  IN in_reserve_sig BYTEA,
  IN in_request_timestamp INT8,
  IN in_history_fee_val INT8,
  IN in_history_fee_frac INT4,
  OUT out_balance_ok BOOLEAN,
  OUT out_idempotent BOOLEAN)
LANGUAGE plpgsql
AS $$
BEGIN

  -- Insert and check for idempotency.
  INSERT INTO exchange.history_requests
  (reserve_pub
  ,request_timestamp
  ,reserve_sig
  ,history_fee_val
  ,history_fee_frac)
  VALUES
  (in_reserve_pub
  ,in_request_timestamp
  ,in_reserve_sig
  ,in_history_fee_val
  ,in_history_fee_frac)
  ON CONFLICT DO NOTHING;

  IF NOT FOUND
  THEN
    out_balance_ok=TRUE;
    out_idempotent=TRUE;
    RETURN;
  END IF;

  out_idempotent=FALSE;

  -- Update reserve balance.
  UPDATE exchange.reserves
   SET
    current_balance_frac=current_balance_frac-in_history_fee_frac
       + CASE
         WHEN current_balance_frac < in_history_fee_frac
         THEN 100000000
         ELSE 0
         END,
    current_balance_val=current_balance_val-in_history_fee_val
       - CASE
         WHEN current_balance_frac < in_history_fee_frac
         THEN 1
         ELSE 0
         END
  WHERE
    reserve_pub=in_reserve_pub
    AND ( (current_balance_val > in_history_fee_val) OR
          ( (current_balance_frac >= in_history_fee_frac) AND
            (current_balance_val >= in_history_fee_val) ) );

  IF NOT FOUND
  THEN
    -- Either reserve does not exist, or balance insufficient.
    -- Both we treat the same here as balance insufficient.
    out_balance_ok=FALSE;
    RETURN;
  END IF;

  out_balance_ok=TRUE;
END $$;


CREATE OR REPLACE FUNCTION exchange_do_reserve_open_deposit(
  IN in_coin_pub BYTEA,
  IN in_known_coin_id INT8,
  IN in_coin_sig BYTEA,
  IN in_reserve_sig BYTEA,
  IN in_reserve_pub BYTEA,
  IN in_coin_total_val INT8,
  IN in_coin_total_frac INT4,
  OUT out_insufficient_funds BOOLEAN)
LANGUAGE plpgsql
AS $$
BEGIN

INSERT INTO exchange.reserves_open_deposits
  (reserve_sig
  ,reserve_pub
  ,coin_pub
  ,coin_sig
  ,contribution_val
  ,contribution_frac
  )
  VALUES
  (in_reserve_sig
  ,in_reserve_pub
  ,in_coin_pub
  ,in_coin_sig
  ,in_coin_total_val
  ,in_coin_total_frac)
  ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- Idempotent request known, return success.
  out_insufficient_funds=FALSE;
  RETURN;
END IF;


-- Check and update balance of the coin.
UPDATE exchange.known_coins
  SET
    remaining_frac=remaining_frac-in_coin_total_frac
       + CASE
         WHEN remaining_frac < in_coin_total_frac
         THEN 100000000
         ELSE 0
         END,
    remaining_val=remaining_val-in_coin_total_val
       - CASE
         WHEN remaining_frac < in_coin_total_frac
         THEN 1
         ELSE 0
         END
  WHERE coin_pub=in_coin_pub
    AND ( (remaining_val > in_coin_total_val) OR
          ( (remaining_frac >= in_coin_total_frac) AND
            (remaining_val >= in_coin_total_val) ) );

IF NOT FOUND
THEN
  -- Insufficient balance.
  out_insufficient_funds=TRUE;
  RETURN;
END IF;

-- Everything fine, return success!
out_insufficient_funds=FALSE;

END $$;


CREATE OR REPLACE FUNCTION exchange_do_reserve_open(
  IN in_reserve_pub BYTEA,
  IN in_total_paid_val INT8,
  IN in_total_paid_frac INT4,
  IN in_reserve_payment_val INT8,
  IN in_reserve_payment_frac INT4,
  IN in_min_purse_limit INT4,
  IN in_default_purse_limit INT4,
  IN in_reserve_sig BYTEA,
  IN in_desired_expiration INT8,
  IN in_reserve_gc_delay INT8,
  IN in_now INT8,
  IN in_open_fee_val INT8,
  IN in_open_fee_frac INT4,
  OUT out_open_cost_val INT8,
  OUT out_open_cost_frac INT4,
  OUT out_final_expiration INT8,
  OUT out_no_funds BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
  my_balance_val INT8;
DECLARE
  my_balance_frac INT4;
DECLARE
  my_cost_val INT8;
DECLARE
  my_cost_tmp INT8;
DECLARE
  my_cost_frac INT4;
DECLARE
  my_years_tmp INT4;
DECLARE
  my_years INT4;
DECLARE
  my_needs_update BOOL;
DECLARE
  my_purses_allowed INT8;
DECLARE
  my_expiration_date INT8;
DECLARE
  my_reserve_expiration INT8;
BEGIN

-- FIXME: use SELECT FOR UPDATE?
SELECT
  purses_allowed
 ,expiration_date
 ,current_balance_val
 ,current_balance_frac
INTO
  my_purses_allowed
 ,my_reserve_expiration
 ,my_balance_val
 ,my_balance_frac
FROM reserves
WHERE
  reserve_pub=in_reserve_pub;

IF NOT FOUND
THEN
  -- FIXME: do we need to set a 'not found'?
  RAISE NOTICE 'reserve not found';
  RETURN;
END IF;

-- Do not allow expiration time to start in the past already
IF (my_reserve_expiration < in_now)
THEN
  my_expiration_date = in_now;
ELSE
  my_expiration_date = my_reserve_expiration;
END IF;

my_cost_val = 0;
my_cost_frac = 0;
my_needs_update = FALSE;
my_years = 0;

-- Compute years based on desired expiration time
IF (my_expiration_date < in_desired_expiration)
THEN
  my_years = (31535999999999 + in_desired_expiration - my_expiration_date) / 31536000000000;
  my_purses_allowed = in_default_purse_limit;
  my_expiration_date = my_expiration_date + 31536000000000 * my_years;
END IF;

-- Increase years based on purses requested
IF (my_purses_allowed < in_min_purse_limit)
THEN
  my_years = (31535999999999 + in_desired_expiration - in_now) / 31536000000000;
  my_expiration_date = in_now + 31536000000000 * my_years;
  my_years_tmp = (in_min_purse_limit + in_default_purse_limit - my_purses_allowed - 1) / in_default_purse_limit;
  my_years = my_years + my_years_tmp;
  my_purses_allowed = my_purses_allowed + (in_default_purse_limit * my_years_tmp);
END IF;


-- Compute cost based on annual fees
IF (my_years > 0)
THEN
  my_cost_val = my_years * in_open_fee_val;
  my_cost_tmp = my_years * in_open_fee_frac / 100000000;
  IF (CAST (my_cost_val + my_cost_tmp AS INT8) < my_cost_val)
  THEN
    out_open_cost_val=9223372036854775807;
    out_open_cost_frac=2147483647;
    out_final_expiration=my_expiration_date;
    out_no_funds=FALSE;
    RAISE NOTICE 'arithmetic issue computing amount';
  RETURN;
  END IF;
  my_cost_val = CAST (my_cost_val + my_cost_tmp AS INT8);
  my_cost_frac = my_years * in_open_fee_frac % 100000000;
  my_needs_update = TRUE;
END IF;

-- check if we actually have something to do
IF NOT my_needs_update
THEN
  out_final_expiration = my_reserve_expiration;
  out_open_cost_val = 0;
  out_open_cost_frac = 0;
  out_no_funds=FALSE;
  RAISE NOTICE 'no change required';
  RETURN;
END IF;

-- Check payment (coins and reserve) would be sufficient.
IF ( (in_total_paid_val < my_cost_val) OR
     ( (in_total_paid_val = my_cost_val) AND
       (in_total_paid_frac < my_cost_frac) ) )
THEN
  out_open_cost_val = my_cost_val;
  out_open_cost_frac = my_cost_frac;
  out_no_funds=FALSE;
  -- We must return a failure, which is indicated by
  -- the expiration being below the desired expiration.
  IF (my_reserve_expiration >= in_desired_expiration)
  THEN
    -- This case is relevant especially if the purse
    -- count was to be increased and the payment was
    -- insufficient to cover this for the full period.
    RAISE NOTICE 'forcing low expiration time';
    out_final_expiration = 0;
  ELSE
    out_final_expiration = my_reserve_expiration;
  END IF;
  RAISE NOTICE 'amount paid too low';
  RETURN;
END IF;

-- Check reserve balance is sufficient.
IF (my_balance_val > in_reserve_payment_val)
THEN
  IF (my_balance_frac >= in_reserve_payment_frac)
  THEN
    my_balance_val=my_balance_val - in_reserve_payment_val;
    my_balance_frac=my_balance_frac - in_reserve_payment_frac;
  ELSE
    my_balance_val=my_balance_val - in_reserve_payment_val - 1;
    my_balance_frac=my_balance_frac + 100000000 - in_reserve_payment_frac;
  END IF;
ELSE
  IF (my_balance_val = in_reserve_payment_val) AND (my_balance_frac >= in_reserve_payment_frac)
  THEN
    my_balance_val=0;
    my_balance_frac=my_balance_frac - in_reserve_payment_frac;
  ELSE
    out_final_expiration = my_reserve_expiration;
    out_open_cost_val = my_cost_val;
    out_open_cost_frac = my_cost_frac;
    out_no_funds=TRUE;
    RAISE NOTICE 'reserve balance too low';
  RETURN;
  END IF;
END IF;

UPDATE reserves SET
  current_balance_val=my_balance_val
 ,current_balance_frac=my_balance_frac
 ,gc_date=my_reserve_expiration + in_reserve_gc_delay
 ,expiration_date=my_expiration_date
 ,purses_allowed=my_purses_allowed
WHERE
 reserve_pub=in_reserve_pub;

out_final_expiration=my_expiration_date;
out_open_cost_val = my_cost_val;
out_open_cost_frac = my_cost_frac;
out_no_funds=FALSE;
RETURN;

END $$;

CREATE OR REPLACE FUNCTION insert_or_update_policy_details(
  IN in_policy_hash_code BYTEA,
  IN in_policy_json VARCHAR,
  IN in_deadline INT8,
  IN in_commitment_val INT8,
  IN in_commitment_frac INT4,
  IN in_accumulated_total_val INT8,
  IN in_accumulated_total_frac INT4,
  IN in_fee_val INT8,
  IN in_fee_frac INT4,
  IN in_transferable_val INT8,
  IN in_transferable_frac INT4,
  IN in_fulfillment_state SMALLINT,
  OUT out_policy_details_serial_id INT8,
  OUT out_accumulated_total_val INT8,
  OUT out_accumulated_total_frac INT4,
  OUT out_fulfillment_state SMALLINT)
LANGUAGE plpgsql
AS $$
DECLARE
       cur_commitment_val INT8;
       cur_commitment_frac INT4;
       cur_accumulated_total_val INT8;
       cur_accumulated_total_frac INT4;
BEGIN
       -- First, try to create a new entry.
       INSERT INTO policy_details
               (policy_hash_code,
                policy_json,
                deadline,
                commitment_val,
                commitment_frac,
                accumulated_total_val,
                accumulated_total_frac,
                fee_val,
                fee_frac,
                transferable_val,
                transferable_frac,
                fulfillment_state)
       VALUES (in_policy_hash_code,
                in_policy_json,
                in_deadline,
                in_commitment_val,
                in_commitment_frac,
                in_accumulated_total_val,
                in_accumulated_total_frac,
                in_fee_val,
                in_fee_frac,
                in_transferable_val,
                in_transferable_frac,
                in_fulfillment_state)
       ON CONFLICT (policy_hash_code) DO NOTHING
       RETURNING policy_details_serial_id INTO out_policy_details_serial_id;

       -- If the insert was successful, return
       -- We assume that the fullfilment_state was correct in first place.
       IF FOUND THEN
               out_accumulated_total_val  = in_accumulated_total_val;
               out_accumulated_total_frac = in_accumulated_total_frac;
               out_fulfillment_state      = in_fulfillment_state;
               RETURN;
       END IF;

       -- We had a conflict, grab the parts we need to update.
       SELECT policy_details_serial_id,
               commitment_val,
               commitment_frac,
               accumulated_total_val,
               accumulated_total_frac
       INTO out_policy_details_serial_id,
               cur_commitment_val,
               cur_commitment_frac,
               cur_accumulated_total_val,
               cur_accumulated_total_frac
       FROM policy_details
       WHERE policy_hash_code = in_policy_hash_code;

       -- calculate the new values (overflows throws exception)
       out_accumulated_total_val  = cur_accumulated_total_val  + in_accumulated_total_val;
       out_accumulated_total_frac = cur_accumulated_total_frac + in_accumulated_total_frac;
       -- normalize
       out_accumulated_total_val = out_accumulated_total_val + out_accumulated_total_frac / 100000000;
       out_accumulated_total_frac = out_accumulated_total_frac % 100000000;

       IF (out_accumulated_total_val > (1 << 52))
       THEN
               RAISE EXCEPTION 'accumulation overflow';
       END IF;


       -- Set the fulfillment_state according to the values.
       -- For now, we only update the state when it was INSUFFICIENT.
       -- FIXME: What to do in case of Failure or other state?
       IF (out_fullfillment_state = 1) -- INSUFFICIENT
       THEN
               IF (out_accumulated_total_val >= cur_commitment_val OR
                       (out_accumulated_total_val = cur_commitment_val AND
                               out_accumulated_total_frac >= cur_commitment_frac))
               THEN
                       out_fulfillment_state = 2; -- READY
               END IF;
       END IF;

       -- Now, update the record
       UPDATE exchange.policy_details
       SET
               accumulated_val  = out_accumulated_total_val,
               accumulated_frac = out_accumulated_total_frac,
               fulfillment_state = out_fulfillment_state
       WHERE
               policy_details_serial_id = out_policy_details_serial_id;
END $$;

CREATE OR REPLACE FUNCTION batch_reserves_in(
  IN in_reserve_pub BYTEA,
  IN in_expiration_date INT8,
  IN in_gc_date INT8,
  IN in_wire_ref INT8,
  IN in_credit_val INT8,
  IN in_credit_frac INT4,
  IN in_exchange_account_name VARCHAR,
  IN in_exectution_date INT8,
  IN in_wire_source_h_payto BYTEA,    ---h_payto
  IN in_payto_uri VARCHAR,
  IN in_reserve_expiration INT8,
  OUT out_reserve_found BOOLEAN,
  OUT transaction_duplicate BOOLEAN,
  OUT ruuid INT8)
LANGUAGE plpgsql
AS $$
DECLARE
  my_amount_val INT8;
DECLARE
  my_amount_frac INT4;
BEGIN

  INSERT INTO reserves
    (reserve_pub
    ,current_balance_val
    ,current_balance_frac
    ,expiration_date
    ,gc_date)
    VALUES
    (in_reserve_pub
    ,in_credit_val
    ,in_credit_frac
    ,in_expiration_date
    ,in_gc_date)
   ON CONFLICT DO NOTHING
   RETURNING reserve_uuid INTO ruuid;

  IF FOUND
  THEN
    -- We made a change, so the reserve did not previously exist.
    out_reserve_found = FALSE;
  ELSE
    -- We made no change, which means the reserve existed.
    out_reserve_found = TRUE;
  END IF;

  --SIMPLE INSERT ON CONFLICT DO NOTHING
  INSERT INTO wire_targets
    (wire_target_h_payto
    ,payto_uri)
    VALUES
    (in_wire_source_h_payto
    ,in_payto_uri)
  ON CONFLICT DO NOTHING;

  INSERT INTO reserves_in
    (reserve_pub
    ,wire_reference
    ,credit_val
    ,credit_frac
    ,exchange_account_section
    ,wire_source_h_payto
    ,execution_date)
    VALUES
    (in_reserve_pub
    ,in_wire_ref
    ,in_credit_val
    ,in_credit_frac
    ,in_exchange_account_name
    ,in_wire_source_h_payto
    ,in_expiration_date);

  --IF THE INSERTION WAS A SUCCESS IT MEANS NO DUPLICATED TRANSACTION
  IF FOUND
  THEN
    transaction_duplicate = FALSE;
    IF out_reserve_found
    THEN
      UPDATE reserves
        SET
           current_balance_frac = current_balance_frac+in_credit_frac
             - CASE
               WHEN current_balance_frac + in_credit_frac >= 100000000
                 THEN 100000000
               ELSE 1
               END
              ,current_balance_val = current_balance_val+in_credit_val
             + CASE
               WHEN current_balance_frac + in_credit_frac >= 100000000
                 THEN 1
               ELSE 0
               END
               ,expiration_date=GREATEST(expiration_date,in_expiration_date)
               ,gc_date=GREATEST(gc_date,in_expiration_date)
      	      WHERE reserves.reserve_pub=in_reserve_pub;
      out_reserve_found = TRUE;
      RETURN;
    ELSE
      out_reserve_found=FALSE;
      RETURN;
    END IF;
    out_reserve_found = TRUE;
  ELSE
    transaction_duplicate = TRUE;
    IF out_reserve_found
    THEN
      out_reserve_found = TRUE;
      RETURN;
    ELSE
      out_reserve_found = FALSE;
      RETURN;
    END IF;
  END IF;
END $$;

COMMIT;
