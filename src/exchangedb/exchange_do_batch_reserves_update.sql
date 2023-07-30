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

CREATE OR REPLACE FUNCTION exchange_do_batch_reserves_update(
  IN in_reserve_pub BYTEA,
  IN in_expiration_date INT8,
  IN in_wire_ref INT8,
  IN in_credit taler_amount,
  IN in_exchange_account_name TEXT,
  IN in_wire_source_h_payto BYTEA,
  IN in_notify text,
  OUT out_duplicate BOOLEAN)
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO reserves_in
    (reserve_pub
    ,wire_reference
    ,credit
    ,exchange_account_section
    ,wire_source_h_payto
    ,execution_date)
    VALUES
    (in_reserve_pub
    ,in_wire_ref
    ,in_credit
    ,in_exchange_account_name
    ,in_wire_source_h_payto
    ,in_expiration_date)
    ON CONFLICT DO NOTHING;
  IF FOUND
  THEN
    --IF THE INSERTION WAS A SUCCESS IT MEANS NO DUPLICATED TRANSACTION
    out_duplicate = FALSE;
    UPDATE reserves rs
      SET
         current_balance.frac = (rs.current_balance).frac+in_credit.frac
           - CASE
             WHEN (rs.current_balance).frac + in_credit.frac >= 100000000
               THEN 100000000
             ELSE 1
             END
        ,current_balance.val = (rs.current_balance).val+in_credit.val
           + CASE
             WHEN (rs.current_balance).frac + in_credit.frac >= 100000000
               THEN 1
             ELSE 0
             END
             ,expiration_date=GREATEST(expiration_date,in_expiration_date)
             ,gc_date=GREATEST(gc_date,in_expiration_date)
   	        WHERE reserve_pub=in_reserve_pub;
    EXECUTE FORMAT (
      'NOTIFY %s'
      ,in_notify);
  ELSE
    out_duplicate = TRUE;
  END IF;
  RETURN;
END $$;
