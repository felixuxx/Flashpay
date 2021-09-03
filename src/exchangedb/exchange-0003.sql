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


CREATE TABLE IF NOT EXISTS aggregation_wip
  (aggregation_wip_serial BIGSERIAL UNIQUE
  ,wtid_raw BYTEA UNIQUE CHECK (LENGTH(wtid_raw)=32)
  ,wire_target TEXT NOT NULL
  ,exchange_account_section TEXT NOT NULL
  ,execution_date INT8 NOT NULL
  ,work_level INT4 NOT NULL
  ,PRIMARY KEY (wire_target,execution_date));

COMMENT ON TABLE aggregation_wip
  IS 'Table tracking aggregations that are work in progress, allowing aggregation work to be divided up between multiple workers. Entries are created when a worker decides that a job is too big for a single worker/transaction and thus should be sharded. They are deleted once the work has concluded, that is a wire_out entry has been created from the final aggregation level.';
COMMENT ON COLUMN aggregation_wip.wtid_raw
  IS 'wire transfer identifier to be used';
COMMENT ON COLUMN aggregation_wip.wire_target
  IS 'identifies the credit account of the aggregated payment';
COMMENT ON COLUMN aggregation_wip.execution_date
  IS 'time when the payment was triggered (is due)';
COMMENT ON COLUMN aggregation_wip.exchange_account_section
  IS 'identifies the configuration section with the debit account of this payment';
COMMENT ON COLUMN aggregation_wip.work_level
  IS 'at which level are we currently doing the aggregation work for this job; all nodes in the B-tree on lower levels must be fully aggregated when this is set';


CREATE TABLE IF NOT EXISTS aggregation_tree
 (aggregation_node_serial BIGSERIAL UNIQUE,
  aggregation_wip_serial INT8 REFERENCES aggregation_wip (aggregation_wip_serial) ON DELETE CASCADE
  ,amount_val INT8 NOT NULL DEFAULT 0
  ,amount_frac INT4 NOT NULL DEFAULT 0
  ,shard_offset INT8 NOT NULL
  ,shard_end INT8 NOT NULL
  ,shard_level INT4 NOT NULL
  ,aggregated BOOLEAN NOT NULL DEFAULT false
  ,PRIMARY KEY (aggregation_wip_uuid,shard_offset,shard_level)
  );
COMMENT ON TABLE aggregation_tree
  IS 'Entry in the B-tree for tracking aggregations that are work in progress. Entries are created when aggregation work is to be done on the level below. The exception is level 0, here each worker that performs a successful SELECT on its locked entry must create a speculative subsequent entry past the SELECTed range. Once the aggregation at for one entry is done, aggregated is set to true. Once the entire tree is aggregated, the aggregation_wip entry is deleted and the entire tree purged via the cascade.';
COMMENT ON COLUMN aggregation_tree.amount_val
  IS 'identifies the amount aggregated so far';
COMMENT ON COLUMN aggregation_tree.shard_offset
  IS 'starting offset of this aggregation entry (inclusive) in relation to the level below; at level 0, this refers to the offset in the deposits query';
COMMENT ON COLUMN aggregation_tree.shard_end
  IS 'end offset of this aggregation entry (exclusive)';
COMMENT ON COLUMN aggregation_tree.shard_level
  IS 'depth of the aggregation tree for this entry; work on a given level can only start if the level below has finished';
COMMENT ON COLUMN aggregation_tree.aggregated
  IS 'true once this transactions corresponding to this range have been added up into the amount_val (when false, amount_val is 0 and this column represents work that remains to be done)';


-- Complete transaction
COMMIT;
