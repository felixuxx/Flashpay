--
-- This file is part of TALER
-- Copyright (C) 2014--2021 Taler Systems SA
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
SELECT _v.register_patch('benchmark-0001', NULL, NULL);

-- Naive, btree version
CREATE TABLE IF NOT EXISTS benchmap
  (uuid BIGSERIAL PRIMARY KEY
  ,hc BYTEA UNIQUE CHECK(LENGTH(hc)=64)
  ,expiration_date INT8 NOT NULL
  );

-- Replace btree with hash-based index
CREATE TABLE IF NOT EXISTS benchhmap
  (uuid BIGSERIAL PRIMARY KEY
  ,hc BYTEA NOT NULL CHECK(LENGTH(hc)=64)
  ,expiration_date INT8 NOT NULL
  );
CREATE INDEX IF NOT EXISTS benchhmap_index
  ON benchhmap
  USING HASH (hc);
ALTER TABLE benchhmap
  ADD CONSTRAINT pk
  EXCLUDE USING HASH (hc with =);

-- Keep btree, also add 32-bit hash-based index on top
CREATE TABLE IF NOT EXISTS benchemap
  (uuid BIGSERIAL PRIMARY KEY
  ,ihc INT4 NOT NULL
  ,hc BYTEA UNIQUE CHECK(LENGTH(hc)=64)
  ,expiration_date INT8 NOT NULL
  );
CREATE INDEX IF NOT EXISTS benchemap_index
  ON benchemap
  USING HASH (ihc);

-- Complete transaction
COMMIT;
