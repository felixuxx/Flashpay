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

CREATE OR REPLACE FUNCTION exchange_do_refund_by_coin(
  IN in_coin_pub BYTEA,
  IN in_merchant_pub BYTEA,
  IN in_h_contract BYTEA
)
RETURNS SETOF record
LANGUAGE plpgsql
AS $$
DECLARE
  curs CURSOR
  FOR
  SELECT
    amount_with_fee
   ,deposit_serial_id
  FROM refunds
  WHERE coin_pub=in_coin_pub;
DECLARE
  i RECORD;
BEGIN
OPEN curs;
LOOP
    FETCH NEXT FROM curs INTO i;
    EXIT WHEN NOT FOUND;
    RETURN QUERY
      SELECT
        i.amount_with_fee
       FROM deposits
       WHERE
         coin_pub=in_coin_pub
         AND merchant_pub=in_merchant_pub
         AND h_contract_terms=in_h_contract
         AND i.deposit_serial_id = deposit_serial_id;
END LOOP;
CLOSE curs;
END $$;

/*RETURNS TABLE(amount_with_fee taler_amount)
LANGUAGE plpgsql
AS $$
DECLARE
  curs CURSOR
  FOR
  SELECT
    r.amount_with_fee
   ,r.deposit_serial_id
  FROM refunds r
  WHERE r.coin_pub=in_coin_pub;
DECLARE
  i RECORD;
BEGIN
OPEN curs;
LOOP
    FETCH NEXT FROM curs INTO i;
    IF FOUND
    THEN
      RETURN QUERY
      SELECT
        i.amount_with_fee
       FROM deposits
       WHERE
         merchant_pub=in_merchant_pub
         AND h_contract_terms=in_h_contract
         AND i.deposit_serial_id = deposit_serial_id;
    END IF;
    EXIT WHEN NOT FOUND;
END LOOP;
CLOSE curs;

END $$;
*/
