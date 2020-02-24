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

-- Check patch versioning is in place.
SELECT _v.register_patch('auditor-0001', NULL, NULL);


CREATE TABLE IF NOT EXISTS auditor_exchanges
  (master_pub BYTEA PRIMARY KEY CHECK (LENGTH(master_pub)=32)
  ,exchange_url VARCHAR NOT NULL
  );
-- Table with list of signing keys of exchanges we are auditing
CREATE TABLE IF NOT EXISTS auditor_exchange_signkeys
  (master_pub BYTEA CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,ep_start INT8 NOT NULL
  ,ep_expire INT8 NOT NULL
  ,ep_end INT8 NOT NULL
  ,exchange_pub BYTEA NOT NULL CHECK (LENGTH(exchange_pub)=32)
  ,master_sig BYTEA NOT NULL CHECK (LENGTH(master_sig)=64)
  );
-- Table with all of the denomination keys that the auditor
-- is aware of.
CREATE TABLE IF NOT EXISTS auditor_denominations
  (denom_pub_hash BYTEA PRIMARY KEY CHECK (LENGTH(denom_pub_hash)=64)
  ,master_pub BYTEA CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,valid_from INT8 NOT NULL
  ,expire_withdraw INT8 NOT NULL
  ,expire_deposit INT8 NOT NULL
  ,expire_legal INT8 NOT NULL
  ,coin_val INT8 NOT NULL
  ,coin_frac INT4 NOT NULL
  ,fee_withdraw_val INT8 NOT NULL
  ,fee_withdraw_frac INT4 NOT NULL
  ,fee_deposit_val INT8 NOT NULL
  ,fee_deposit_frac INT4 NOT NULL
  ,fee_refresh_val INT8 NOT NULL
  ,fee_refresh_frac INT4 NOT NULL
  ,fee_refund_val INT8 NOT NULL
  ,fee_refund_frac INT4 NOT NULL
  );
-- Table indicating up to which transactions the auditor has
-- processed the exchange database.  Used for SELECTing the
-- statements to process.  The indices below include the last
-- serial ID from the respective tables that we have
-- processed. Thus, we need to select those table entries that are
-- strictly larger (and process in monotonically increasing
-- order).
CREATE TABLE IF NOT EXISTS auditor_progress_reserve
  (master_pub BYTEA CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,last_reserve_in_serial_id INT8 NOT NULL DEFAULT 0
  ,last_reserve_out_serial_id INT8 NOT NULL DEFAULT 0
  ,last_reserve_recoup_serial_id INT8 NOT NULL DEFAULT 0
  ,last_reserve_close_serial_id INT8 NOT NULL DEFAULT 0
  ,PRIMARY KEY (master_pub)
  );
CREATE TABLE IF NOT EXISTS auditor_progress_aggregation
  (master_pub BYTEA CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,last_wire_out_serial_id INT8 NOT NULL DEFAULT 0
  ,PRIMARY KEY (master_pub)
  );
CREATE TABLE IF NOT EXISTS auditor_progress_deposit_confirmation
  (master_pub BYTEA CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,last_deposit_confirmation_serial_id INT8 NOT NULL DEFAULT 0
  ,PRIMARY KEY (master_pub)
  );
CREATE TABLE IF NOT EXISTS auditor_progress_coin
  (master_pub BYTEA CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,last_withdraw_serial_id INT8 NOT NULL DEFAULT 0
  ,last_deposit_serial_id INT8 NOT NULL DEFAULT 0
  ,last_melt_serial_id INT8 NOT NULL DEFAULT 0
  ,last_refund_serial_id INT8 NOT NULL DEFAULT 0
  ,last_recoup_serial_id INT8 NOT NULL DEFAULT 0
  ,last_recoup_refresh_serial_id INT8 NOT NULL DEFAULT 0
  ,PRIMARY KEY (master_pub)
  );
CREATE TABLE IF NOT EXISTS wire_auditor_account_progress
  (master_pub BYTEA CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,account_name TEXT NOT NULL
  ,last_wire_reserve_in_serial_id INT8 NOT NULL DEFAULT 0
  ,last_wire_wire_out_serial_id INT8 NOT NULL DEFAULT 0
  ,wire_in_off INT8
  ,wire_out_off INT8
  ,PRIMARY KEY (master_pub,account_name)
  );
CREATE TABLE IF NOT EXISTS wire_auditor_progress
  (master_pub BYTEA CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,last_timestamp INT8 NOT NULL
  ,last_reserve_close_uuid INT8 NOT NULL
  ,PRIMARY KEY (master_pub)
  );
-- Table with all of the customer reserves and their respective
-- balances that the auditor is aware of.
-- last_reserve_out_serial_id marks the last withdrawal from
-- reserves_out about this reserve that the auditor is aware of,
-- and last_reserve_in_serial_id is the last reserve_in
-- operation about this reserve that the auditor is aware of.
CREATE TABLE IF NOT EXISTS auditor_reserves
  (reserve_pub BYTEA NOT NULL CHECK(LENGTH(reserve_pub)=32)
  ,master_pub BYTEA CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,reserve_balance_val INT8 NOT NULL
  ,reserve_balance_frac INT4 NOT NULL
  ,withdraw_fee_balance_val INT8 NOT NULL
  ,withdraw_fee_balance_frac INT4 NOT NULL
  ,expiration_date INT8 NOT NULL
  ,auditor_reserves_rowid BIGSERIAL UNIQUE
  ,origin_account TEXT
  );
CREATE INDEX IF NOT EXISTS auditor_reserves_by_reserve_pub
  ON auditor_reserves
  (reserve_pub);
-- Table with the sum of the balances of all customer reserves
-- (by exchange's master public key)
CREATE TABLE IF NOT EXISTS auditor_reserve_balance
  (master_pub BYTEA CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,reserve_balance_val INT8 NOT NULL
  ,reserve_balance_frac INT4 NOT NULL
  ,withdraw_fee_balance_val INT8 NOT NULL
  ,withdraw_fee_balance_frac INT4 NOT NULL
  );
-- Table with the sum of the balances of all wire fees
-- (by exchange's master public key)
CREATE TABLE IF NOT EXISTS auditor_wire_fee_balance
  (master_pub BYTEA CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,wire_fee_balance_val INT8 NOT NULL
  ,wire_fee_balance_frac INT4 NOT NULL
  );
-- Table with all of the outstanding denomination coins that the
-- exchange is aware of and what the respective balances are
-- (outstanding as well as issued overall which implies the
-- maximum value at risk).  We also count the number of coins
-- issued (withdraw, refresh-reveal) and the number of coins seen
-- at the exchange (refresh-commit, deposit), not just the amounts. */GNUNET_PQ_make_execute (
CREATE TABLE IF NOT EXISTS auditor_denomination_pending
  (denom_pub_hash BYTEA PRIMARY KEY REFERENCES auditor_denominations (denom_pub_hash) ON DELETE CASCADE
  ,denom_balance_val INT8 NOT NULL
  ,denom_balance_frac INT4 NOT NULL
  ,denom_loss_val INT8 NOT NULL
  ,denom_loss_frac INT4 NOT NULL
  ,num_issued INT8 NOT NULL
  ,denom_risk_val INT8 NOT NULL
  ,denom_risk_frac INT4 NOT NULL
  ,recoup_loss_val INT8 NOT NULL
  ,recoup_loss_frac INT4 NOT NULL
  );
-- Table with the sum of the outstanding coins from
-- auditor_denomination_pending (denom_pubs must belong to the
-- respective's exchange's master public key); it represents the
-- auditor_balance_summary of the exchange at this point (modulo
-- unexpected historic_loss-style events where denomination keys are
-- compromised)
CREATE TABLE IF NOT EXISTS auditor_balance_summary
  (master_pub BYTEA CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,denom_balance_val INT8 NOT NULL
  ,denom_balance_frac INT4 NOT NULL
  ,deposit_fee_balance_val INT8 NOT NULL
  ,deposit_fee_balance_frac INT4 NOT NULL
  ,melt_fee_balance_val INT8 NOT NULL
  ,melt_fee_balance_frac INT4 NOT NULL
  ,refund_fee_balance_val INT8 NOT NULL
  ,refund_fee_balance_frac INT4 NOT NULL
  ,risk_val INT8 NOT NULL
  ,risk_frac INT4 NOT NULL
  ,loss_val INT8 NOT NULL
  ,loss_frac INT4 NOT NULL
  ,irregular_recoup_val INT8 NOT NULL
  ,irregular_recoup_frac INT4 NOT NULL
  );
-- Table with historic profits; basically, when a denom_pub has
-- expired and everything associated with it is garbage collected,
-- the final profits end up in here; note that the denom_pub here
-- is not a foreign key, we just keep it as a reference point.
-- revenue_balance is the sum of all of the profits we made on the
-- coin except for withdraw fees (which are in
-- historic_reserve_revenue); the deposit, melt and refund fees are given
-- individually; the delta to the revenue_balance is from coins that
-- were withdrawn but never deposited prior to expiration.
CREATE TABLE IF NOT EXISTS auditor_historic_denomination_revenue
  (master_pub BYTEA CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,denom_pub_hash BYTEA PRIMARY KEY CHECK (LENGTH(denom_pub_hash)=64)
  ,revenue_timestamp INT8 NOT NULL
  ,revenue_balance_val INT8 NOT NULL
  ,revenue_balance_frac INT4 NOT NULL
  ,loss_balance_val INT8 NOT NULL
  ,loss_balance_frac INT4 NOT NULL
  );
-- Table with historic profits from reserves; we eventually
-- GC auditor_historic_reserve_revenue, and then store the totals
-- in here (by time intervals).
CREATE TABLE IF NOT EXISTS auditor_historic_reserve_summary
  (master_pub BYTEA CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,start_date INT8 NOT NULL
  ,end_date INT8 NOT NULL
  ,reserve_profits_val INT8 NOT NULL
  ,reserve_profits_frac INT4 NOT NULL
  );
CREATE INDEX IF NOT EXISTS auditor_historic_reserve_summary_by_master_pub_start_date
  ON auditor_historic_reserve_summary
  (master_pub
  ,start_date);
-- Table with deposit confirmation sent to us by merchants;
-- we must check that the exchange reported these properly.
CREATE TABLE IF NOT EXISTS deposit_confirmations
  (master_pub BYTEA CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,serial_id BIGSERIAL UNIQUE
  ,h_contract_terms BYTEA CHECK (LENGTH(h_contract_terms)=64)
  ,h_wire BYTEA CHECK (LENGTH(h_wire)=64)
  ,timestamp INT8 NOT NULL
  ,refund_deadline INT8 NOT NULL
  ,amount_without_fee_val INT8 NOT NULL
  ,amount_without_fee_frac INT4 NOT NULL
  ,coin_pub BYTEA CHECK (LENGTH(coin_pub)=32)
  ,merchant_pub BYTEA CHECK (LENGTH(merchant_pub)=32)
  ,exchange_sig BYTEA CHECK (LENGTH(exchange_sig)=64)
  ,exchange_pub BYTEA CHECK (LENGTH(exchange_pub)=32)
  ,master_sig BYTEA CHECK (LENGTH(master_sig)=64)
  ,PRIMARY KEY (h_contract_terms,h_wire,coin_pub,merchant_pub,exchange_sig,exchange_pub,master_sig)
  );
-- Table with the sum of the ledger, auditor_historic_revenue and
-- the auditor_reserve_balance.  This is the
-- final amount that the exchange should have in its bank account
-- right now.
CREATE TABLE IF NOT EXISTS auditor_predicted_result
  (master_pub BYTEA CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,balance_val INT8 NOT NULL
  ,balance_frac INT4 NOT NULL
  );

-- Finally, commit everything
COMMIT;
