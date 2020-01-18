--
-- This file is part of TALER
-- Copyright (C) 2014--2020 Taler Systems SA
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

-- Everything in one big transaction
BEGIN;

-- This script DROPs all of the tables we create, including the
-- versioning schema!
--
-- Unlike the other SQL files, it SHOULD be updated to reflect the
-- latest requirements for dropping tables.

-- Drops for 0001.sql
DROP TABLE IF EXISTS prewire CASCADE;
DROP TABLE IF EXISTS recoup CASCADE;
DROP TABLE IF EXISTS recoup_refresh CASCADE;
DROP TABLE IF EXISTS aggregation_tracking CASCADE;
DROP TABLE IF EXISTS wire_out CASCADE;
DROP TABLE IF EXISTS wire_fee CASCADE;
DROP TABLE IF EXISTS deposits CASCADE;
DROP TABLE IF EXISTS refunds CASCADE;
DROP TABLE IF EXISTS refresh_commitments CASCADE;
DROP TABLE IF EXISTS refresh_revealed_coins CASCADE;
DROP TABLE IF EXISTS refresh_transfer_keys CASCADE;
DROP TABLE IF EXISTS known_coins CASCADE;
DROP TABLE IF EXISTS reserves_close CASCADE;
DROP TABLE IF EXISTS reserves_out CASCADE;
DROP TABLE IF EXISTS reserves_in CASCADE;
DROP TABLE IF EXISTS reserves CASCADE;
DROP TABLE IF EXISTS denomination_revocations CASCADE;
DROP TABLE IF EXISTS denominations CASCADE;

-- Drop versioning (0000.sql)
DROP SCHEMA IF EXISTS _v CASCADE;

-- And we're out of here...
COMMIT;
