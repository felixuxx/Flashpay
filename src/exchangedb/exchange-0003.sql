--
-- This file is part of TALER
-- Copyright (C) 2021 Taler Systems SA
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
SELECT _v.register_patch('exchange-0003', NULL, NULL);



ALTER TABLE deposits
  ADD COLUMN shard INT4 NOT NULL DEFAULT 0;
COMMENT ON COLUMN deposits.shard
  IS 'Used for load sharding. Should be set based on h_wire, merchant_pub and a service salt. Default of 0 onlyapplies for colums migrated from a previous version without sharding support. 64-bit value because we need an *unsigned* 32-bit value.';

DROP INDEX deposits_get_ready_index;
CREATE INDEX deposits_get_ready_index
  ON deposits
  (shard
  ,tiny
  ,done
  ,wire_deadline
  ,refund_deadline
  );
COMMENT ON INDEX deposits_get_ready_index
  IS 'for deposits_get_ready';



CREATE UNLOGGED TABLE IF NOT EXISTS revolving_work_shards
  (shard_serial_id BIGSERIAL UNIQUE
  ,last_attempt INT8 NOT NULL
  ,start_row INT4 NOT NULL
  ,end_row INT4 NOT NULL
  ,active BOOLEAN NOT NULL DEFAULT FALSE
  ,job_name VARCHAR NOT NULL
  ,PRIMARY KEY (job_name, start_row)
  );
CREATE INDEX IF NOT EXISTS revolving_work_shards_index
  ON revolving_work_shards
  (job_name
  ,active
  ,last_attempt
  );
COMMENT ON TABLE revolving_work_shards
  IS 'coordinates work between multiple processes working on the same job with partitions that need to be repeatedly processed; unlogged because on system crashes the locks represented by this table will have to be cleared anyway, typically using "taler-exchange-dbinit -s"';
COMMENT ON COLUMN revolving_work_shards.shard_serial_id
  IS 'unique serial number identifying the shard';
COMMENT ON COLUMN revolving_work_shards.last_attempt
  IS 'last time a worker attempted to work on the shard';
COMMENT ON COLUMN revolving_work_shards.active
  IS 'set to TRUE when a worker is active on the shard';
COMMENT ON COLUMN revolving_work_shards.start_row
  IS 'row at which the shard scope starts, inclusive';
COMMENT ON COLUMN revolving_work_shards.end_row
  IS 'row at which the shard scope ends, exclusive';
COMMENT ON COLUMN revolving_work_shards.job_name
  IS 'unique name of the job the workers on this shard are performing';

-- Complete transaction
COMMIT;
