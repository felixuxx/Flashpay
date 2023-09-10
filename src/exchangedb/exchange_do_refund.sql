--
-- This file is part of TALER
-- Copyright (C) 2014--2023 Taler Systems SA
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

CREATE OR REPLACE FUNCTION exchange_do_refund(
  IN in_amount_with_fee taler_amount,
  IN in_amount taler_amount,
  IN in_deposit_fee taler_amount,
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
  bdsi INT8; -- ID of deposit being refunded
DECLARE
  tmp_val INT8; -- total amount refunded
DECLARE
  tmp_frac INT8; -- total amount refunded, large fraction to deal with overflows!
DECLARE
  tmp taler_amount; -- total amount refunded, normalized
DECLARE
  deposit taler_amount; -- amount that was originally deposited
BEGIN
-- Shards: SELECT deposits (coin_pub, shard, h_contract_terms, merchant_pub)
--         INSERT refunds (by coin_pub, rtransaction_id) ON CONFLICT DO NOTHING
--         SELECT refunds (by coin_pub)
--         UPDATE known_coins (by coin_pub)

SELECT
   bdep.batch_deposit_serial_id
  ,(cdep.amount_with_fee).val
  ,(cdep.amount_with_fee).frac
  ,bdep.done
 INTO
   bdsi
  ,deposit.val
  ,deposit.frac
  ,out_gone
 FROM batch_deposits bdep
 JOIN coin_deposits cdep
   USING (batch_deposit_serial_id)
 WHERE cdep.coin_pub=in_coin_pub
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

INSERT INTO refunds
  (batch_deposit_serial_id
  ,coin_pub
  ,merchant_sig
  ,rtransaction_id
  ,amount_with_fee
  )
  VALUES
  (bdsi
  ,in_coin_pub
  ,in_merchant_sig
  ,in_rtransaction_id
  ,in_amount_with_fee
  )
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
     AND batch_deposit_serial_id=bdsi
     AND rtransaction_id=in_rtransaction_id
     AND amount_with_fee=in_amount_with_fee;

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
   SUM((refs.amount_with_fee).val) -- overflow here is not plausible
  ,SUM(CAST((refs.amount_with_fee).frac AS INT8)) -- compute using 64 bits
  INTO
   tmp_val
  ,tmp_frac
  FROM refunds refs
  WHERE coin_pub=in_coin_pub
    AND batch_deposit_serial_id=bdsi;
IF tmp_val IS NULL
THEN
  RAISE NOTICE 'failed to sum up existing refunds';
  out_refund_ok=FALSE;
  out_conflict=FALSE;
  out_not_found=FALSE;
  RETURN;
END IF;

-- Normalize result before continuing
tmp.val = tmp_val + tmp_frac / 100000000;
tmp.frac = tmp_frac % 100000000;

-- Actually check if the deposits are sufficient for the refund. Verbosely. ;-)
IF (tmp.val < deposit.val)
THEN
  out_refund_ok=TRUE;
ELSE
  IF (tmp.val = deposit.val) AND (tmp.frac <= deposit.frac)
  THEN
    out_refund_ok=TRUE;
  ELSE
    out_refund_ok=FALSE;
  END IF;
END IF;

IF (tmp.val = deposit.val) AND (tmp.frac = deposit.frac)
THEN
  -- Refunds have reached the full value of the original
  -- deposit. Also refund the deposit fee.
  in_amount.frac = in_amount.frac + in_deposit_fee.frac;
  in_amount.val = in_amount.val + in_deposit_fee.val;

  -- Normalize result before continuing
  in_amount.val = in_amount.val + in_amount.frac / 100000000;
  in_amount.frac = in_amount.frac % 100000000;
END IF;

-- Update balance of the coin.
UPDATE known_coins kc
  SET
    remaining.frac=(kc.remaining).frac+in_amount.frac
       - CASE
         WHEN (kc.remaining).frac+in_amount.frac >= 100000000
         THEN 100000000
         ELSE 0
         END,
    remaining.val=(kc.remaining).val+in_amount.val
       + CASE
         WHEN (kc.remaining).frac+in_amount.frac >= 100000000
         THEN 1
         ELSE 0
         END
  WHERE coin_pub=in_coin_pub;

out_conflict=FALSE;
out_not_found=FALSE;

END $$;

COMMENT ON FUNCTION exchange_do_refund(taler_amount, taler_amount, taler_amount, BYTEA, INT8, INT8, INT8, BYTEA, BYTEA, BYTEA)
  IS 'Executes a refund operation, checking that the corresponding deposit was sufficient to cover the refunded amount';
