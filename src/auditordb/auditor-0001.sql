--
-- This file is part of TALER
-- Copyright (C) 2014--2023 Taler Systems SA
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

CREATE TYPE taler_amount
  AS
  (val INT8
  ,frac INT4
  );
COMMENT ON TYPE taler_amount
  IS 'Stores an amount, fraction is in units of 1/100000000 of the base value';


CREATE TABLE IF NOT EXISTS auditor_exchanges
  (master_pub BYTEA PRIMARY KEY CHECK (LENGTH(master_pub)=32)
  ,exchange_url TEXT NOT NULL
  );
COMMENT ON TABLE auditor_exchanges
  IS 'list of the exchanges we are auditing';


CREATE TABLE IF NOT EXISTS auditor_exchange_signkeys
  (master_pub BYTEA NOT NULL CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,ep_start INT8 NOT NULL
  ,ep_expire INT8 NOT NULL
  ,ep_end INT8 NOT NULL
  ,exchange_pub BYTEA NOT NULL CHECK (LENGTH(exchange_pub)=32)
  ,master_sig BYTEA NOT NULL CHECK (LENGTH(master_sig)=64)
  );
COMMENT ON TABLE auditor_exchange_signkeys
  IS 'list of the online signing keys of exchanges we are auditing';


CREATE TABLE IF NOT EXISTS auditor_progress_reserve
  (master_pub BYTEA NOT NULL CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,last_reserve_in_serial_id INT8 NOT NULL DEFAULT 0
  ,last_reserve_out_serial_id INT8 NOT NULL DEFAULT 0
  ,last_reserve_recoup_serial_id INT8 NOT NULL DEFAULT 0
  ,last_reserve_open_serial_id INT8 NOT NULL DEFAULT 0
  ,last_reserve_close_serial_id INT8 NOT NULL DEFAULT 0
  ,last_purse_decision_serial_id INT8 NOT NULL DEFAULT 0
  ,last_account_merges_serial_id INT8 NOT NULL DEFAULT 0
  ,last_history_requests_serial_id INT8 NOT NULL DEFAULT 0
  ,PRIMARY KEY (master_pub)
  );
COMMENT ON TABLE auditor_progress_reserve
  IS 'information as to which transactions the reserve auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


CREATE TABLE IF NOT EXISTS auditor_progress_purse
  (master_pub BYTEA NOT NULL CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,last_purse_request_serial_id INT8 NOT NULL DEFAULT 0
  ,last_purse_decision_serial_id INT8 NOT NULL DEFAULT 0
  ,last_purse_merges_serial_id INT8 NOT NULL DEFAULT 0
  ,last_account_merges_serial_id INT8 NOT NULL DEFAULT 0
  ,last_purse_deposits_serial_id INT8 NOT NULL DEFAULT 0
  ,PRIMARY KEY (master_pub)
  );
COMMENT ON TABLE auditor_progress_purse
  IS 'information as to which purses the purse auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


CREATE TABLE IF NOT EXISTS auditor_progress_aggregation
  (master_pub BYTEA CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,last_wire_out_serial_id INT8 NOT NULL DEFAULT 0
  ,PRIMARY KEY (master_pub)
  );
COMMENT ON TABLE auditor_progress_aggregation
  IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


CREATE TABLE IF NOT EXISTS auditor_progress_deposit_confirmation
  (master_pub BYTEA NOT NULL CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,last_deposit_confirmation_serial_id INT8 NOT NULL DEFAULT 0
  ,PRIMARY KEY (master_pub)
  );
COMMENT ON TABLE auditor_progress_deposit_confirmation
  IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


CREATE TABLE IF NOT EXISTS auditor_progress_coin
  (master_pub BYTEA NOT NULL CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,last_withdraw_serial_id INT8 NOT NULL DEFAULT 0
  ,last_deposit_serial_id INT8 NOT NULL DEFAULT 0
  ,last_melt_serial_id INT8 NOT NULL DEFAULT 0
  ,last_refund_serial_id INT8 NOT NULL DEFAULT 0
  ,last_recoup_serial_id INT8 NOT NULL DEFAULT 0
  ,last_recoup_refresh_serial_id INT8 NOT NULL DEFAULT 0
  ,last_open_deposits_serial_id INT8 NOT NULL DEFAULT 0
  ,last_purse_deposits_serial_id INT8 NOT NULL DEFAULT 0
  ,last_purse_decision_serial_id INT8 NOT NULL DEFAULT 0
  ,PRIMARY KEY (master_pub)
  );
COMMENT ON TABLE auditor_progress_coin
  IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


CREATE TABLE IF NOT EXISTS wire_auditor_account_progress
  (master_pub BYTEA NOT NULL CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,account_name TEXT NOT NULL
  ,last_wire_reserve_in_serial_id INT8 NOT NULL DEFAULT 0
  ,last_wire_wire_out_serial_id INT8 NOT NULL DEFAULT 0
  ,wire_in_off INT8 NOT NULL
  ,wire_out_off INT8 NOT NULL
  ,PRIMARY KEY (master_pub,account_name)
  );
COMMENT ON TABLE wire_auditor_account_progress
  IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


CREATE TABLE IF NOT EXISTS wire_auditor_progress
  (master_pub BYTEA NOT NULL CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,last_reserve_close_uuid INT8 NOT NULL
  ,last_batch_deposit_uuid INT8 NOT NULL
  ,last_aggregation_serial INT8 NOT NULL
  ,PRIMARY KEY (master_pub)
  );


CREATE TABLE IF NOT EXISTS auditor_reserves
  (reserve_pub BYTEA NOT NULL CHECK(LENGTH(reserve_pub)=32)
  ,master_pub BYTEA NOT NULL CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,reserve_balance taler_amount NOT NULL
  ,reserve_loss taler_amount NOT NULL
  ,withdraw_fee_balance taler_amount NOT NULL
  ,close_fee_balance taler_amount NOT NULL
  ,purse_fee_balance taler_amount NOT NULL
  ,open_fee_balance taler_amount NOT NULL
  ,history_fee_balance taler_amount NOT NULL
  ,expiration_date INT8 NOT NULL
  ,auditor_reserves_rowid BIGINT GENERATED BY DEFAULT AS IDENTITY UNIQUE
  ,origin_account TEXT
  );
COMMENT ON TABLE auditor_reserves
  IS 'all of the customer reserves and their respective balances that the auditor is aware of';

CREATE INDEX IF NOT EXISTS auditor_reserves_by_reserve_pub
  ON auditor_reserves
  (reserve_pub);


CREATE TABLE IF NOT EXISTS auditor_purses
  (purse_pub BYTEA NOT NULL CHECK(LENGTH(purse_pub)=32)
  ,master_pub BYTEA NOT NULL CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,balance taler_amount NOT NULL DEFAULT(0,0)
  ,target taler_amount NOT NULL
  ,expiration_date INT8 NOT NULL
  ,auditor_purses_rowid BIGINT GENERATED BY DEFAULT AS IDENTITY UNIQUE
  );
COMMENT ON TABLE auditor_purses
  IS 'all of the purses and their respective balances that the auditor is aware of';

CREATE INDEX IF NOT EXISTS auditor_purses_by_purse_pub
  ON auditor_purses
  (purse_pub);


CREATE TABLE IF NOT EXISTS auditor_purse_summary
  (master_pub BYTEA NOT NULL CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,balance taler_amount NOT NULL
  ,open_purses INT8 NOT NULL
  );
COMMENT ON TABLE auditor_purse_summary
  IS 'sum of the balances in open purses';

CREATE TABLE IF NOT EXISTS auditor_reserve_balance
  (master_pub BYTEA NOT NULL CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,reserve_balance taler_amount NOT NULL
  ,reserve_loss taler_amount NOT NULL
  ,withdraw_fee_balance taler_amount NOT NULL
  ,close_fee_balance taler_amount NOT NULL
  ,purse_fee_balance taler_amount NOT NULL
  ,open_fee_balance taler_amount NOT NULL
  ,history_fee_balance taler_amount NOT NULL
  );
COMMENT ON TABLE auditor_reserve_balance
  IS 'sum of the balances of all customer reserves (by exchange master public key)';


CREATE TABLE IF NOT EXISTS auditor_wire_fee_balance
  (master_pub BYTEA NOT NULL CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,wire_fee_balance taler_amount NOT NULL
  );
COMMENT ON TABLE auditor_wire_fee_balance
  IS 'sum of the balances of all wire fees (by exchange master public key)';


CREATE TABLE IF NOT EXISTS auditor_denomination_pending
  (denom_pub_hash BYTEA PRIMARY KEY CHECK (LENGTH(denom_pub_hash)=64)
  ,denom_balance taler_amount NOT NULL
  ,denom_loss taler_amount NOT NULL
  ,num_issued INT8 NOT NULL
  ,denom_risk taler_amount NOT NULL
  ,recoup_loss taler_amount NOT NULL
  );
COMMENT ON TABLE auditor_denomination_pending
  IS 'outstanding denomination coins that the exchange is aware of and what the respective balances are (outstanding as well as issued overall which implies the maximum value at risk).';
COMMENT ON COLUMN auditor_denomination_pending.num_issued
  IS 'counts the number of coins issued (withdraw, refresh) of this denomination';
COMMENT ON COLUMN auditor_denomination_pending.denom_risk
  IS 'amount that could theoretically be lost in the future due to recoup operations';
COMMENT ON COLUMN auditor_denomination_pending.denom_loss
  IS 'amount that was lost due to failures by the exchange';
COMMENT ON COLUMN auditor_denomination_pending.recoup_loss
  IS 'amount actually lost due to recoup operations after a revocation';


CREATE TABLE IF NOT EXISTS auditor_balance_summary
  (master_pub BYTEA NOT NULL CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,denom_balance taler_amount NOT NULL
  ,deposit_fee_balance taler_amount NOT NULL
  ,melt_fee_balance taler_amount NOT NULL
  ,refund_fee_balance taler_amount NOT NULL
  ,purse_fee_balance taler_amount NOT NULL
  ,open_deposit_fee_balance taler_amount NOT NULL
  ,risk taler_amount NOT NULL
  ,loss taler_amount NOT NULL
  ,irregular_loss taler_amount NOT NULL
  );
COMMENT ON TABLE auditor_balance_summary
  IS 'the sum of the outstanding coins from auditor_denomination_pending (denom_pubs must belong to the respectives exchange master public key); it represents the auditor_balance_summary of the exchange at this point (modulo unexpected historic_loss-style events where denomination keys are compromised)';
COMMENT ON COLUMN auditor_balance_summary.denom_balance
 IS 'total amount we should have in escrow for all denominations';


CREATE TABLE IF NOT EXISTS auditor_historic_denomination_revenue
  (master_pub BYTEA NOT NULL CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,denom_pub_hash BYTEA PRIMARY KEY CHECK (LENGTH(denom_pub_hash)=64)
  ,revenue_timestamp INT8 NOT NULL
  ,revenue_balance taler_amount NOT NULL
  ,loss_balance taler_amount NOT NULL
  );
COMMENT ON TABLE auditor_historic_denomination_revenue
  IS 'Table with historic profits; basically, when a denom_pub has expired and everything associated with it is garbage collected, the final profits end up in here; note that the denom_pub here is not a foreign key, we just keep it as a reference point.';
COMMENT ON COLUMN auditor_historic_denomination_revenue.revenue_balance
  IS 'the sum of all of the profits we made on the coin except for withdraw fees (which are in historic_reserve_revenue); so this includes the deposit, melt and refund fees';


CREATE TABLE IF NOT EXISTS auditor_historic_reserve_summary
  (master_pub BYTEA NOT NULL CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,start_date INT8 NOT NULL
  ,end_date INT8 NOT NULL
  ,reserve_profits taler_amount NOT NULL
  );
COMMENT ON TABLE auditor_historic_reserve_summary
  IS 'historic profits from reserves; we eventually GC auditor_historic_reserve_revenue, and then store the totals in here (by time intervals).';

CREATE INDEX IF NOT EXISTS auditor_historic_reserve_summary_by_master_pub_start_date
  ON auditor_historic_reserve_summary
  (master_pub
  ,start_date);


CREATE TABLE IF NOT EXISTS deposit_confirmations
  (master_pub BYTEA NOT NULL CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY UNIQUE
  ,h_contract_terms BYTEA NOT NULL CHECK (LENGTH(h_contract_terms)=64)
  ,h_policy BYTEA NOT NULL CHECK (LENGTH(h_policy)=64)
  ,h_wire BYTEA NOT NULL CHECK (LENGTH(h_wire)=64)
  ,exchange_timestamp INT8 NOT NULL
  ,refund_deadline INT8 NOT NULL
  ,wire_deadline INT8 NOT NULL
  ,total_without_fee taler_amount NOT NULL
  ,coin_pubs BYTEA[] NOT NULL CHECK (CARDINALITY(coin_pubs)>0)
  ,coin_sigs BYTEA[] NOT NULL CHECK (CARDINALITY(coin_sigs)=CARDINALITY(coin_pubs))
  ,merchant_pub BYTEA NOT NULL CHECK (LENGTH(merchant_pub)=32)
  ,exchange_sig BYTEA NOT NULL CHECK (LENGTH(exchange_sig)=64)
  ,exchange_pub BYTEA NOT NULL CHECK (LENGTH(exchange_pub)=32)
  ,master_sig BYTEA NOT NULL CHECK (LENGTH(master_sig)=64)
  ,PRIMARY KEY (h_contract_terms,h_wire,merchant_pub,exchange_sig,exchange_pub,master_sig)
  );
COMMENT ON TABLE deposit_confirmations
  IS 'deposit confirmation sent to us by merchants; we must check that the exchange reported these properly.';


CREATE TABLE IF NOT EXISTS auditor_predicted_result
  (master_pub BYTEA NOT NULL CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,balance taler_amount NOT NULL
  ,drained taler_amount NOT NULL
  );
COMMENT ON TABLE auditor_predicted_result
  IS 'Table with the sum of the ledger, auditor_historic_revenue and the auditor_reserve_balance and the drained profits.  This is the final amount that the exchange should have in its bank account right now (and the total amount drained as profits to non-escrow accounts).';


CREATE TABLE IF NOT EXISTS auditor_pending_deposits
  (master_pub BYTEA NOT NULL CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,total_amount taler_amount NOT NULL
  ,wire_target_h_payto BYTEA CHECK (LENGTH(wire_target_h_payto)=32)
  ,batch_deposit_serial_id INT8 NOT NULL
  ,deadline INT8 NOT NULL
  ,PRIMARY KEY(master_pub, batch_deposit_serial_id)
  );
COMMENT ON TABLE auditor_pending_deposits
  IS 'Table with the sum of the (batch) deposits we have seen but not yet checked that they have been aggregated and wired for a particular target bank account';
COMMENT ON COLUMN auditor_pending_deposits.total_amount
  IS 'Amount we expect to be wired in total for the batch. Includes deposit fees, not the actual expected net wire transfer amount.';
COMMENT ON COLUMN auditor_pending_deposits.wire_target_h_payto
  IS 'Hash of the payto URI of the bank account to be credited by the deadline';
COMMENT ON COLUMN auditor_pending_deposits.batch_deposit_serial_id
  IS 'Entry in the batch_deposits table of the exchange this entry is for';
COMMENT ON COLUMN auditor_pending_deposits.deadline
  IS 'Deadline by which funds should be wired (may be in the future)';
CREATE INDEX IF NOT EXISTS auditor_pending_deposits_by_deadline
  ON auditor_pending_deposits
  (master_pub
  ,deadline ASC);

-- Finally, commit everything
COMMIT;
