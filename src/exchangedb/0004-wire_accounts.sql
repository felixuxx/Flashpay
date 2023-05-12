--
-- This file is part of TALER
-- Copyright (C) 2023 Taler Systems SA
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

ALTER TABLE wire_accounts
  ADD COLUMN conversion_url VARCHAR DEFAULT (NULL),
  ADD COLUMN debit_restrictions VARCHAR DEFAULT (NULL),
  ADD COLUMN credit_restrictions VARCHAR DEFAULT (NULL);
COMMENT ON COLUMN wire_accounts.conversion_url
  IS 'URL of a currency conversion service if conversion is needed when this account is used; NULL if there is no conversion.';
COMMENT ON COLUMN wire_accounts.debit_restrictions
  IS 'JSON array describing restrictions imposed when debiting this account. Empty for no restrictions, NULL if account was migrated from previous database revision or account is disabled.';
COMMENT ON COLUMN wire_accounts.credit_restrictions
  IS 'JSON array describing restrictions imposed when crediting this account. Empty for no restrictions, NULL if account was migrated from previous database revision or account is disabled.';
