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


CREATE TABLE partner_accounts
  (payto_uri VARCHAR PRIMARY KEY
  ,partner_serial_id INT8 REFERENCES partners(partner_serial_id) ON DELETE CASCADE
  ,partner_master_sig BYTEA CHECK (LENGTH(partner_master_sig)=64)
  ,last_seen INT8 NOT NULL
  );
CREATE INDEX IF NOT EXISTS partner_accounts_index_by_partner_and_time
  ON partner_accounts (partner_serial_id,last_seen);
COMMENT ON TABLE partner_accounts
  IS 'Table with bank accounts of the partner exchange. Entries never expire as we need to remember the signature for the auditor.';
COMMENT ON COLUMN partner_accounts.payto_uri
  IS 'payto URI (RFC 8905) with the bank account of the partner exchange.';
COMMENT ON COLUMN partner_accounts.partner_master_sig
  IS 'Signature of purpose TALER_SIGNATURE_MASTER_WIRE_DETAILS by the partner master public key';
COMMENT ON COLUMN partner_accounts.last_seen
  IS 'Last time we saw this account as being active at the partner exchange. Used to select the most recent entry, and to detect when we should check again.';
