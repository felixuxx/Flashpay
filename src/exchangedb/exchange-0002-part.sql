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

-- ------------------------------ wire_targets ----------------------------------------

SELECT create_table_wire_targets();

COMMENT ON TABLE wire_targets
  IS 'All senders and recipients of money via the exchange';
COMMENT ON COLUMN wire_targets.payto_uri
  IS 'Can be a regular bank account, or also be a URI identifying a reserve-account (for P2P payments)';
COMMENT ON COLUMN wire_targets.wire_target_h_payto
  IS 'Unsalted hash of payto_uri';

CREATE TABLE IF NOT EXISTS wire_targets_default
  PARTITION OF wire_targets
  FOR VALUES WITH (MODULUS 1, REMAINDER 0);

SELECT add_constraints_to_wire_targets_partition('default');

