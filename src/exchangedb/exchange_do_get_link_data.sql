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
/*DROP FUNCTION exchange_do_refund_by_coin(
  IN in_coin_pub BYTEA,
  IN in_merchant_pub BYTEA,
  IN in_h_contract BYTEA
);*/
CREATE OR REPLACE FUNCTION exchange_do_get_link_data(
  IN in_coin_pub BYTEA
)
RETURNS SETOF record
LANGUAGE plpgsql
AS $$
DECLARE
  curs CURSOR
  FOR
  SELECT
   melt_serial_id
  FROM refresh_commitments
  WHERE old_coin_pub=in_coin_pub;

DECLARE
  i RECORD;
BEGIN
OPEN curs;
LOOP
    FETCH NEXT FROM curs INTO i;
    EXIT WHEN NOT FOUND;
    RETURN QUERY
      SELECT
       tp.transfer_pub
      ,denoms.denom_pub
      ,rrc.ev_sig
      ,rrc.ewv
      ,rrc.link_sig
      ,rrc.freshcoin_index
      ,rrc.coin_ev
      FROM refresh_revealed_coins rrc
       JOIN refresh_transfer_keys tp
         ON (tp.melt_serial_id=rrc.melt_serial_id)
       JOIN denominations denoms
         ON (rrc.denominations_serial=denoms.denominations_serial)
       WHERE rrc.melt_serial_id =i.melt_serial_id;
END LOOP;
CLOSE curs;
END $$;
