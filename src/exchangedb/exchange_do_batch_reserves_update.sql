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
  IN in_credit_val INT8,
  IN in_credit_frac INT4,
  IN in_exchange_account_name VARCHAR,
  IN in_wire_source_h_payto BYTEA,
  IN in_notify text,
  OUT out_duplicate BOOLEAN)
LANGUAGE plpgsql
AS $$
BEGIN
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
    ,in_expiration_date)
    ON CONFLICT DO NOTHING;
  IF FOUND
  THEN
    --IF THE INSERTION WAS A SUCCESS IT MEANS NO DUPLICATED TRANSACTION
    out_duplicate = FALSE;
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
   	        WHERE reserve_pub=in_reserve_pub;
    PERFORM pg_notify(in_notify, NULL);
  ELSE
    out_duplicate = TRUE;
  END IF;
  RETURN;
END $$;
