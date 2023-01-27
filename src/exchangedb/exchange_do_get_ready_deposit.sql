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
CREATE OR REPLACE FUNCTION exchange_do_get_ready_deposit(
  IN in_now INT8,
  IN in_start_shard_now INT8,
  IN in_end_shard_now INT8,
  OUT out_payto_uri VARCHAR,
  OUT out_merchant_pub BYTEA
)
LANGUAGE plpgsql
AS $$
DECLARE
 var_wire_target_h_payto BYTEA;
DECLARE
 var_coin_pub BYTEA;
DECLARE
 var_deposit_serial_id INT8;
BEGIN

SELECT
   coin_pub
  ,deposit_serial_id
  INTO
   var_coin_pub
  ,var_deposit_serial_id
  FROM deposits_by_ready
  WHERE wire_deadline <= in_now
  AND shard >= in_start_shard_now
  AND shard <=in_end_shard_now
  ORDER BY
   wire_deadline ASC
  ,shard ASC;

SELECT
  merchant_pub
 ,wire_target_h_payto
 INTO
  out_merchant_pub
 ,var_wire_target_h_payto
 FROM deposits
 WHERE coin_pub=var_coin_pub
   AND deposit_serial_id=var_deposit_serial_id;

SELECT
 payto_uri
 INTO out_payto_uri
 FROM wire_targets
 WHERE wire_target_h_payto=var_wire_target_h_payto;

RETURN;
END $$;
