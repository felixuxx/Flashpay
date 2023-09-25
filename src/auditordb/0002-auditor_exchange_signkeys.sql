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

CREATE TABLE IF NOT EXISTS auditor_exchange_signkeys
    ,ep_start INT8 NOT NULL
    ,ep_expire INT8 NOT NULL
    ,ep_end INT8 NOT NULL
    ,exchange_pub BYTEA NOT NULL CHECK (LENGTH(exchange_pub)=32)
    ,master_sig BYTEA NOT NULL CHECK (LENGTH(master_sig)=64)
    );
COMMENT ON TABLE auditor_exchange_signkeys
  IS 'list of the online signing keys of exchanges we are auditing';