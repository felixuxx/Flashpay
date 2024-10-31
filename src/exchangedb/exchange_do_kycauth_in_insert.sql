--
-- This file is part of TALER
-- Copyright (C) 2024 Taler Systems SA
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


DROP PROCEDURE IF EXISTS exchange_do_kycauth_in_insert;
CREATE PROCEDURE exchange_do_kycauth_in_insert(
  IN in_account_pub BYTEA,
  IN in_wire_reference INT8,
  IN in_credit taler_amount,
  IN in_wire_source_h_payto BYTEA,
  IN in_h_normalized_payto BYTEA,
  IN in_payto_uri TEXT,
  IN in_exchange_account_name TEXT,
  IN in_execution_date INT8,
  IN in_notify_s TEXT)
LANGUAGE plpgsql
AS $$
BEGIN

  INSERT INTO kycauths_in
    (account_pub
    ,wire_reference
    ,credit
    ,wire_source_h_payto
    ,exchange_account_section
    ,execution_date
    ) VALUES (
     in_account_pub
    ,in_wire_reference
    ,in_credit
    ,in_wire_source_h_payto
    ,in_exchange_account_name
    ,in_execution_date
    )
    ON CONFLICT DO NOTHING;

  IF NOT FOUND
  THEN
    -- presumably already done
    RETURN;
  END IF;

  UPDATE wire_targets
     SET target_pub=in_account_pub
   WHERE wire_target_h_payto=in_wire_source_h_payto;

  IF NOT FOUND
  THEN
    INSERT INTO wire_targets
      (wire_target_h_payto
      ,h_normalized_payto
      ,payto_uri
      ,target_pub
      ) VALUES (
       in_wire_source_h_payto
      ,in_h_normalized_payto
      ,in_payto_uri
      ,in_account_pub);
  END IF;

  EXECUTE FORMAT (
     'NOTIFY %s'
    ,in_notify_s);

END $$;
