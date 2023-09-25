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

-- Everything in one big transaction
BEGIN;

-- Check patch versioning is in place.
SELECT _v.register_patch('auditor-0001', NULL, NULL);


CREATE SCHEMA auditor;
COMMENT ON SCHEMA auditor IS 'taler-auditor data';

SET search_path TO auditor;

-- Not needed anymore because no longer multitenant
/*CREATE TABLE IF NOT EXISTS auditor_exchanges
  (master_pub BYTEA PRIMARY KEY CHECK (LENGTH(master_pub)=32)
  ,exchange_url VARCHAR NOT NULL
  );
COMMENT ON TABLE auditor_exchanges
  IS 'list of the exchanges we are auditing';*/

#include "0002-denominations.sql"
-- Finally, commit everything
COMMIT;
