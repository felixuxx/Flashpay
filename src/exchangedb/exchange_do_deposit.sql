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
CREATE OR REPLACE FUNCTION exchange_do_deposit(
  -- For batch_deposits
  IN in_shard INT8,
  IN in_merchant_pub BYTEA,
  IN in_wallet_timestamp INT8,
  IN in_exchange_timestamp INT8,
  IN in_refund_deadline INT8,
  IN in_wire_deadline INT8,
  IN in_h_contract_terms BYTEA,
  IN in_wallet_data_hash BYTEA, -- can be NULL
  IN in_wire_salt BYTEA,
  IN in_wire_target_h_payto BYTEA,
  IN in_policy_details_serial_id INT8, -- can be NULL
  IN in_policy_blocked BOOLEAN,
  -- For wire_targets
  IN in_receiver_wire_account TEXT,
  -- For coin_deposits
  IN ina_coin_pub BYTEA[],
  IN ina_coin_sig BYTEA[],
  IN ina_amount_with_fee taler_amount[],
  OUT out_exchange_timestamp INT8,
  OUT out_insufficient_balance_coin_index INT4, -- index of coin with bad balance, NULL if none
  OUT out_conflict BOOL
 )
LANGUAGE plpgsql
AS $$
DECLARE
  wtsi INT8; -- wire target serial id
  bdsi INT8; -- batch_deposits serial id
  curs REFCURSOR;
  i INT4;
  ini_amount_with_fee taler_amount;
  ini_coin_pub BYTEA;
  ini_coin_sig BYTEA;
BEGIN
-- Shards:
--         INSERT wire_targets (by h_payto), ON CONFLICT DO NOTHING;
--         INSERT batch_deposits (by shard, merchant_pub), ON CONFLICT idempotency check;
--         INSERT[] coin_deposits (by coin_pub), ON CONFLICT idempotency check;
--         UPDATE[] known_coins (by coin_pub)


-- First, get or create the 'wtsi'
INSERT INTO wire_targets
    (wire_target_h_payto
    ,payto_uri)
  VALUES
    (in_wire_target_h_payto
    ,in_receiver_wire_account)
  ON CONFLICT DO NOTHING -- for CONFLICT ON (wire_target_h_payto)
  RETURNING
    wire_target_serial_id
  INTO
    wtsi;

IF NOT FOUND
THEN
  SELECT
    wire_target_serial_id
  INTO
    wtsi
  FROM wire_targets
  WHERE
    wire_target_h_payto=in_wire_target_h_payto;
END IF;


-- Second, create the batch_deposits entry
INSERT INTO batch_deposits
  (shard
  ,merchant_pub
  ,wallet_timestamp
  ,exchange_timestamp
  ,refund_deadline
  ,wire_deadline
  ,h_contract_terms
  ,wallet_data_hash
  ,wire_salt
  ,wire_target_h_payto
  ,policy_details_serial_id
  ,policy_blocked
  )
  VALUES
  (in_shard
  ,in_merchant_pub
  ,in_wallet_timestamp
  ,in_exchange_timestamp
  ,in_refund_deadline
  ,in_wire_deadline
  ,in_h_contract_terms
  ,in_wallet_data_hash
  ,in_wire_salt
  ,in_wire_target_h_payto
  ,in_policy_details_serial_id
  ,in_policy_blocked)
  ON CONFLICT DO NOTHING -- for CONFLICT ON (merchant_pub, h_contract_terms)
  RETURNING
    batch_deposit_serial_id
  INTO
    bdsi;

IF NOT FOUND
THEN
  -- Idempotency check: see if an identical record exists.
  -- We do select over merchant_pub, h_contract_terms and wire_target_h_payto
  -- first to maximally increase the chance of using the existing index.
  SELECT
      exchange_timestamp
     ,batch_deposit_serial_id
   INTO
      out_exchange_timestamp
     ,bdsi
   FROM batch_deposits
   WHERE shard=in_shard
     AND merchant_pub=in_merchant_pub
     AND h_contract_terms=in_h_contract_terms
     AND wire_target_h_payto=in_wire_target_h_payto
     -- now check the rest, too
     AND ( (wallet_data_hash=in_wallet_data_hash) OR
           (wallet_data_hash IS NULL AND in_wallet_data_hash IS NULL) )
     AND wire_salt=in_wire_salt
     AND wallet_timestamp=in_wallet_timestamp
     AND refund_deadline=in_refund_deadline
     AND wire_deadline=in_wire_deadline
     AND ( (policy_details_serial_id=in_policy_details_serial_id) OR
           (policy_details_serial_id IS NULL AND in_policy_details_serial_id IS NULL) );
  IF NOT FOUND
  THEN
    -- Deposit exists, but with *strange* differences. Not allowed.
    out_conflict=TRUE;
    RETURN;
  END IF;
END IF;

out_conflict=FALSE;

-- Deposit each coin

FOR i IN 1..array_length(ina_coin_pub,1)
LOOP
  ini_coin_pub = ina_coin_pub[i];
  ini_coin_sig = ina_coin_sig[i];
  ini_amount_with_fee = ina_amount_with_fee[i];

  INSERT INTO coin_deposits
    (batch_deposit_serial_id
    ,coin_pub
    ,coin_sig
    ,amount_with_fee
    )
    VALUES
    (bdsi
    ,ini_coin_pub
    ,ini_coin_sig
    ,ini_amount_with_fee
    )
    ON CONFLICT DO NOTHING;

  IF FOUND
  THEN
    -- Insert did happen, update balance in known_coins!

    UPDATE known_coins kc
      SET
        remaining.frac=(kc.remaining).frac-ini_amount_with_fee.frac
          + CASE
              WHEN (kc.remaining).frac < ini_amount_with_fee.frac
              THEN 100000000
              ELSE 0
            END,
        remaining.val=(kc.remaining).val-ini_amount_with_fee.val
          - CASE
              WHEN (kc.remaining).frac < ini_amount_with_fee.frac
              THEN 1
              ELSE 0
            END
      WHERE coin_pub=ini_coin_pub
        AND ( ((kc.remaining).val > ini_amount_with_fee.val) OR
              ( ((kc.remaining).frac >= ini_amount_with_fee.frac) AND
                ((kc.remaining).val >= ini_amount_with_fee.val) ) );

    IF NOT FOUND
    THEN
      -- Insufficient balance.
      -- Note: C arrays are 0 indexed, but i started at 1
      out_insufficient_balance_coin_index=i-i;
      RETURN;
    END IF;
  END IF;
END LOOP; -- end FOR all coins

END $$;
