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


CREATE OR REPLACE FUNCTION exchange_do_recoup_by_reserve(
  IN res_pub BYTEA
)
RETURNS TABLE
(
  denom_sig            BYTEA,
  denominations_serial INT8,
  coin_pub             BYTEA,
  coin_sig             BYTEA,
  coin_blind           BYTEA,
  amount               taler_amount,
  recoup_timestamp     INT8
)
LANGUAGE plpgsql
AS $$
DECLARE
  res_uuid INT8;
  blind_ev BYTEA;
  c_pub    BYTEA;
BEGIN
  SELECT reserve_uuid
   INTO res_uuid
   FROM reserves
   WHERE reserve_pub = res_pub;

  FOR blind_ev IN
    SELECT h_blind_ev
      FROM reserves_out ro
      JOIN reserve_history rh
        ON (rh.serial_id = ro.reserve_out_serial_id)
    WHERE rh.reserve_pub = res_pub
      AND rh.table_name='reserves_out'
  LOOP
    SELECT robr.coin_pub
      INTO c_pub
      FROM exchange.recoup_by_reserve robr
    WHERE robr.reserve_out_serial_id = (
      SELECT reserve_out_serial_id
        FROM reserves_out
      WHERE h_blind_ev = blind_ev
    );
    RETURN QUERY
      SELECT kc.denom_sig,
             kc.denominations_serial,
             rc.coin_pub,
             rc.coin_sig,
             rc.coin_blind,
             rc.amount,
             rc.recoup_timestamp
      FROM (
        SELECT denom_sig
              ,denominations_serial
        FROM exchange.known_coins
        WHERE known_coins.coin_pub = c_pub
      ) kc
      JOIN (
        SELECT coin_pub
              ,coin_sig
              ,coin_blind
              ,amount
              ,recoup_timestamp
        FROM exchange.recoup
        WHERE recoup.coin_pub = c_pub
      ) rc USING (coin_pub);
  END LOOP;
END;
$$;

COMMENT ON FUNCTION exchange_do_recoup_by_reserve
  IS 'Recoup by reserve as a function to make sure we hit only the needed partition and not all when joining as joins on distributed tables fetch ALL rows from the shards';
