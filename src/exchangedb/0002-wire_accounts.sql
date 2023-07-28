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

CREATE TABLE wire_accounts
  (payto_uri VARCHAR PRIMARY KEY
  ,master_sig BYTEA CHECK (LENGTH(master_sig)=64)
  ,is_active BOOLEAN NOT NULL
  ,last_change INT8 NOT NULL
  ,conversion_url VARCHAR DEFAULT (NULL)
  ,debit_restrictions VARCHAR DEFAULT (NULL)
  ,credit_restrictions VARCHAR DEFAULT (NULL)
  );
COMMENT ON TABLE wire_accounts
  IS 'Table with current and historic bank accounts of the exchange. Entries never expire as we need to remember the last_change column indefinitely.';
COMMENT ON COLUMN wire_accounts.payto_uri
  IS 'payto URI (RFC 8905) with the bank account of the exchange.';
COMMENT ON COLUMN wire_accounts.master_sig
  IS 'Signature of purpose TALER_SIGNATURE_MASTER_WIRE_DETAILS';
COMMENT ON COLUMN wire_accounts.is_active
  IS 'true if we are currently supporting the use of this account.';
COMMENT ON COLUMN wire_accounts.last_change
  IS 'Latest time when active status changed. Used to detect replays of old messages.';
COMMENT ON COLUMN wire_accounts.conversion_url
  IS 'URL of a currency conversion service if conversion is needed when this account is used; NULL if there is no conversion.';
COMMENT ON COLUMN wire_accounts.debit_restrictions
  IS 'JSON array describing restrictions imposed when debiting this account. Empty for no restrictions, NULL if account was migrated from previous database revision or account is disabled.';
COMMENT ON COLUMN wire_accounts.credit_restrictions
  IS 'JSON array describing restrictions imposed when crediting this account. Empty for no restrictions, NULL if account was migrated from previous database revision or account is disabled.';


-- "wire_accounts" has no sequence because it is a 'mutable' table
--            and is of no concern to the auditor
