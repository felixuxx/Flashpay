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

CREATE OR REPLACE PROCEDURE exchange_do_gc(
  IN in_ancient_date INT8,
  IN in_now INT8)
LANGUAGE plpgsql
AS $$
DECLARE
  reserve_uuid_min INT8; -- minimum reserve UUID still alive
  melt_min INT8; -- minimum melt still alive
  coin_min INT8; -- minimum known_coin still alive
  batch_deposit_min INT8; -- minimum deposit still alive
  reserve_out_min INT8; -- minimum reserve_out still alive
  denom_min INT8; -- minimum denomination still alive
BEGIN

DELETE FROM prewire
  WHERE finished=TRUE;

DELETE FROM wire_fee
  WHERE end_date < in_ancient_date;

-- FIXME: use closing fee as threshold?
DELETE FROM reserves
  WHERE gc_date < in_now
    AND current_balance = (0, 0);

SELECT
     reserve_out_serial_id
  INTO
     reserve_out_min
  FROM reserves_out
  ORDER BY reserve_out_serial_id ASC
  LIMIT 1;

DELETE FROM recoup
  WHERE reserve_out_serial_id < reserve_out_min;

SELECT
     reserve_uuid
  INTO
     reserve_uuid_min
  FROM reserves
  ORDER BY reserve_uuid ASC
  LIMIT 1;

DELETE FROM reserves_out
  WHERE reserve_uuid < reserve_uuid_min;

-- FIXME: this query will be horribly slow;
-- need to find another way to formulate it...
DELETE FROM denominations
  WHERE expire_legal < in_now
    AND denominations_serial NOT IN
      (SELECT DISTINCT denominations_serial
         FROM reserves_out)
    AND denominations_serial NOT IN
      (SELECT DISTINCT denominations_serial
         FROM known_coins
        WHERE coin_pub IN
          (SELECT DISTINCT coin_pub
             FROM recoup))
    AND denominations_serial NOT IN
      (SELECT DISTINCT denominations_serial
         FROM known_coins
        WHERE coin_pub IN
          (SELECT DISTINCT coin_pub
             FROM recoup_refresh));

SELECT
     melt_serial_id
  INTO
     melt_min
  FROM refresh_commitments
  ORDER BY melt_serial_id ASC
  LIMIT 1;

DELETE FROM refresh_revealed_coins
  WHERE melt_serial_id < melt_min;

DELETE FROM refresh_transfer_keys
  WHERE melt_serial_id < melt_min;

SELECT
     known_coin_id
  INTO
     coin_min
  FROM known_coins
  ORDER BY known_coin_id ASC
  LIMIT 1;

DELETE FROM recoup_refresh
  WHERE known_coin_id < coin_min;

DELETE FROM batch_deposits
  WHERE wire_deadline < in_ancient_date;

SELECT
     batch_deposit_serial_id
  INTO
     batch_deposit_min
  FROM coin_deposits
  ORDER BY batch_deposit_serial_id ASC
  LIMIT 1;

DELETE FROM refunds
  WHERE batch_deposit_serial_id < batch_deposit_min;
DELETE FROM aggregation_tracking
  WHERE batch_deposit_serial_id < batch_deposit_min;
DELETE FROM coin_deposits
  WHERE batch_deposit_serial_id < batch_deposit_min;



SELECT
     denominations_serial
  INTO
     denom_min
  FROM denominations
  ORDER BY denominations_serial ASC
  LIMIT 1;

DELETE FROM cs_nonce_locks
  WHERE max_denomination_serial <= denom_min;

END $$;
