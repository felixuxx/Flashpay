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
CREATE OR REPLACE FUNCTION batch_reserves_in(
  IN in_reserve_pub BYTEA,
  IN in_expiration_date INT8,
  IN in_gc_date INT8,
  IN in_wire_ref INT8,
  IN in_credit_val INT8,
  IN in_credit_frac INT4,
  IN in_exchange_account_name VARCHAR,
  IN in_exectution_date INT8,
  IN in_wire_source_h_payto BYTEA,    ---h_payto
  IN in_payto_uri VARCHAR,
  IN in_reserve_expiration INT8,
  OUT out_reserve_found BOOLEAN,
  OUT transaction_duplicate BOOLEAN,
  OUT ruuid INT8)
LANGUAGE plpgsql
AS $$
DECLARE
  my_amount_val INT8;
DECLARE
  my_amount_frac INT4;
BEGIN

  INSERT INTO reserves
    (reserve_pub
    ,current_balance_val
    ,current_balance_frac
    ,expiration_date
    ,gc_date)
    VALUES
    (in_reserve_pub
    ,in_credit_val
    ,in_credit_frac
    ,in_expiration_date
    ,in_gc_date)
   ON CONFLICT DO NOTHING
   RETURNING reserve_uuid INTO ruuid;

  IF FOUND
  THEN
    -- We made a change, so the reserve did not previously exist.
    out_reserve_found = FALSE;
  ELSE
    -- We made no change, which means the reserve existed.
    out_reserve_found = TRUE;
  END IF;

  --SIMPLE INSERT ON CONFLICT DO NOTHING
  INSERT INTO wire_targets
    (wire_target_h_payto
    ,payto_uri)
    VALUES
    (in_wire_source_h_payto
    ,in_payto_uri)
  ON CONFLICT DO NOTHING;

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
    ,in_expiration_date);

  --IF THE INSERTION WAS A SUCCESS IT MEANS NO DUPLICATED TRANSACTION
  IF FOUND
  THEN
    transaction_duplicate = FALSE;
    IF out_reserve_found
    THEN
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
      	      WHERE reserves.reserve_pub=in_reserve_pub;
      out_reserve_found = TRUE;
      RETURN;
    ELSE
      out_reserve_found=FALSE;
      RETURN;
    END IF;
    out_reserve_found = TRUE;
  ELSE
    transaction_duplicate = TRUE;
    IF out_reserve_found
    THEN
      out_reserve_found = TRUE;
      RETURN;
    ELSE
      out_reserve_found = FALSE;
      RETURN;
    END IF;
  END IF;
END $$;
