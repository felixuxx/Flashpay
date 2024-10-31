--
-- This file is part of TALER
-- Copyright (C) 2014--2024 Taler Systems SA
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


DROP FUNCTION IF EXISTS exchange_do_array_reserves_insert;
CREATE FUNCTION exchange_do_array_reserves_insert(
  IN in_gc_date INT8,
  IN in_reserve_expiration INT8,
  IN ina_reserve_pub BYTEA[],
  IN ina_wire_ref INT8[],
  IN ina_credit taler_amount[],
  IN ina_exchange_account_name TEXT[],
  IN ina_execution_date INT8[],
  IN ina_wire_source_h_payto BYTEA[],
  IN ina_h_normalized_payto BYTEA[],
  IN ina_payto_uri TEXT[],
  IN ina_notify TEXT[])
RETURNS SETOF exchange_do_array_reserve_insert_return_type
LANGUAGE plpgsql
AS $$
DECLARE
  conflict BOOL;
  dup BOOL;
  uuid INT8;
  i INT4;
  ini_reserve_pub BYTEA;
  ini_wire_ref INT8;
  ini_credit taler_amount;
  ini_exchange_account_name TEXT;
  ini_execution_date INT8;
  ini_wire_source_h_payto BYTEA;
  ini_h_normalized_payto BYTEA;
  ini_payto_uri TEXT;
  ini_notify TEXT;
BEGIN

  FOR i IN 1..array_length(ina_reserve_pub,1)
  LOOP
    ini_reserve_pub = ina_reserve_pub[i];
    ini_wire_ref = ina_wire_ref[i];
    ini_credit = ina_credit[i];
    ini_exchange_account_name = ina_exchange_account_name[i];
    ini_execution_date = ina_execution_date[i];
    ini_wire_source_h_payto = ina_wire_source_h_payto[i];
    ini_h_normalized_payto = ina_h_normalized_payto[i];
    ini_payto_uri = ina_payto_uri[i];
    ini_notify = ina_notify[i];

--    RAISE WARNING 'Starting loop on %', ini_notify;

    INSERT INTO wire_targets
      (wire_target_h_payto
      ,h_normalized_payto
      ,payto_uri
      ) VALUES (
        ini_wire_source_h_payto
        ini_h_normalized_payto
       ,ini_payto_uri
      )
    ON CONFLICT DO NOTHING;

    INSERT INTO reserves
      (reserve_pub
      ,current_balance
      ,expiration_date
      ,gc_date
    ) VALUES (
      ini_reserve_pub
     ,ini_credit
     ,in_reserve_expiration
     ,in_gc_date
    )
    ON CONFLICT DO NOTHING
    RETURNING reserve_uuid
      INTO uuid;
    conflict = NOT FOUND;

    INSERT INTO reserves_in
      (reserve_pub
      ,wire_reference
      ,credit
      ,exchange_account_section
      ,wire_source_h_payto
      ,execution_date
    ) VALUES (
      ini_reserve_pub
     ,ini_wire_ref
     ,ini_credit
     ,ini_exchange_account_name
     ,ini_wire_source_h_payto
     ,ini_execution_date
    )
    ON CONFLICT DO NOTHING;

    IF NOT FOUND
    THEN
      IF conflict
      THEN
        dup = TRUE;
      else
        dup = FALSE;
      END IF;
    ELSE
      IF NOT conflict
      THEN
        EXECUTE FORMAT (
          'NOTIFY %s'
          ,ini_notify);
      END IF;
      dup = FALSE;
    END IF;
    RETURN NEXT (dup,uuid);
  END LOOP;
  RETURN;
END $$;
