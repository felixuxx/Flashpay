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
  OUT out_payto_uri TEXT,
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
DECLARE
 curs CURSOR
 FOR
 SELECT
   coin_pub
  ,deposit_serial_id
  ,wire_deadline
  ,shard
 FROM deposits_by_ready
 WHERE wire_deadline <= in_now
 AND shard >=in_start_shard_now
 AND shard <=in_end_shard_now
 LIMIT 1;
DECLARE
 i RECORD;
BEGIN
OPEN curs;
FETCH FROM curs INTO i;
IF NOT FOUND
THEN
  RETURN;
END IF;
SELECT
   payto_uri
  ,merchant_pub
  INTO
   out_payto_uri
  ,out_merchant_pub
  FROM deposits dep
  JOIN wire_targets wt
  ON (wt.wire_target_h_payto=dep.wire_target_h_payto)
  WHERE dep.coin_pub=i.coin_pub
  AND dep.deposit_serial_id=i.deposit_serial_id
  ORDER BY
   i.wire_deadline ASC
  ,i.shard ASC;

RETURN;
END $$;
