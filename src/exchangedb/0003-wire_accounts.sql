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

-- new columns for #8000
ALTER TABLE wire_accounts
  ADD COLUMN priority INT8 NOT NULL DEFAULT (0),
  ADD COLUMN bank_label TEXT DEFAULT (NULL);

COMMENT ON COLUMN wire_accounts.priority
  IS 'priority determines the order in which wallets should display wire accounts';
COMMENT ON COLUMN wire_accounts.bank_label
  IS 'label to show in the selector for this bank account in the wallet UI';
