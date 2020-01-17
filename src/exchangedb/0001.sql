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
SELECT _v.register_patch('0001', NULL, NULL);


-- Main denominations table. All the coins the exchange knows about.
CREATE TABLE IF NOT EXISTS denominations
  (denom_pub_hash BYTEA PRIMARY KEY CHECK (LENGTH(denom_pub_hash)=64)
  ,denom_pub BYTEA NOT NULL
  ,master_pub BYTEA NOT NULL CHECK (LENGTH(master_pub)=32)
  ,master_sig BYTEA NOT NULL CHECK (LENGTH(master_sig)=64)
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
CREATE INDEX denominations_expire_legal_index
  ON denominations
  (expire_legal);

-- denomination_revocations table is for remembering which denomination keys have been revoked
CREATE TABLE IF NOT EXISTS denomination_revocations
  (denom_revocations_serial_id BIGSERIAL UNIQUE
  ,denom_pub_hash BYTEA PRIMARY KEY REFERENCES denominations (denom_pub_hash) ON DELETE CASCADE
  ,master_sig BYTEA NOT NULL CHECK (LENGTH(master_sig)=64)
  );
-- reserves table is for summarization of a reserve.  It is updated when new
-- funds are added and existing funds are withdrawn.  The 'expiration_date'
-- can be used to eventually get rid of reserves that have not been used
-- for a very long time (usually by refunding the owner)
CREATE TABLE IF NOT EXISTS reserves
  (reserve_pub BYTEA PRIMARY KEY CHECK(LENGTH(reserve_pub)=32)
  ,account_details TEXT NOT NULL
  ,current_balance_val INT8 NOT NULL
  ,current_balance_frac INT4 NOT NULL
  ,expiration_date INT8 NOT NULL
  ,gc_date INT8 NOT NULL
  );
-- index on reserves table (TODO: useless due to primary key!?)
CREATE INDEX reserves_reserve_pub_index
  ON reserves
  (reserve_pub);
-- index for get_expired_reserves
CREATE INDEX reserves_expiration_index
  ON reserves
  (expiration_date
  ,current_balance_val
  ,current_balance_frac
  );
-- index for reserve GC operations
CREATE INDEX reserves_gc_index
  ON reserves
  (gc_date);
-- reserves_in table collects the transactions which transfer funds
-- into the reserve.  The rows of this table correspond to each
-- incoming transaction.
CREATE TABLE IF NOT EXISTS reserves_in
  (reserve_in_serial_id BIGSERIAL UNIQUE
  ,reserve_pub BYTEA NOT NULL REFERENCES reserves (reserve_pub) ON DELETE CASCADE
  ,wire_reference INT8 NOT NULL
  ,credit_val INT8 NOT NULL
  ,credit_frac INT4 NOT NULL
  ,sender_account_details TEXT NOT NULL
  ,exchange_account_section TEXT NOT NULL
  ,execution_date INT8 NOT NULL
  ,PRIMARY KEY (reserve_pub, wire_reference)
  );
-- Create indices on reserves_in
CREATE INDEX reserves_in_execution_index
  ON reserves_in
  (exchange_account_section
  ,execution_date
  );
CREATE INDEX reserves_in_exchange_account_serial
  ON reserves_in
  (exchange_account_section,
  reserve_in_serial_id DESC
  );
-- This table contains the data for wire transfers the exchange has
-- executed to close a reserve.
CREATE TABLE IF NOT EXISTS reserves_close
  (close_uuid BIGSERIAL PRIMARY KEY
  ,reserve_pub BYTEA NOT NULL REFERENCES reserves (reserve_pub) ON DELETE CASCADE
  ,execution_date INT8 NOT NULL
  ,wtid BYTEA NOT NULL CHECK (LENGTH(wtid)=32)
  ,receiver_account TEXT NOT NULL
  ,amount_val INT8 NOT NULL
  ,amount_frac INT4 NOT NULL
  ,closing_fee_val INT8 NOT NULL
  ,closing_fee_frac INT4 NOT NULL);
CREATE INDEX reserves_close_by_reserve
  ON reserves_close
  (reserve_pub);
-- Table with the withdraw operations that have been performed on a reserve.
--  The 'h_blind_ev' is the hash of the blinded coin. It serves as a primary
-- key, as (broken) clients that use a non-random coin and blinding factor
-- should fail to even withdraw, as otherwise the coins will fail to deposit
-- (as they really must be unique).
-- For the denom_pub, we do NOT CASCADE on DELETE, we may keep the denomination key alive!
CREATE TABLE IF NOT EXISTS reserves_out
  (reserve_out_serial_id BIGSERIAL UNIQUE
  ,h_blind_ev BYTEA PRIMARY KEY CHECK (LENGTH(h_blind_ev)=64)
  ,denom_pub_hash BYTEA NOT NULL REFERENCES denominations (denom_pub_hash)
  ,denom_sig BYTEA NOT NULL
  ,reserve_pub BYTEA NOT NULL REFERENCES reserves (reserve_pub) ON DELETE CASCADE
  ,reserve_sig BYTEA NOT NULL CHECK (LENGTH(reserve_sig)=64)
  ,execution_date INT8 NOT NULL
  ,amount_with_fee_val INT8 NOT NULL
  ,amount_with_fee_frac INT4 NOT NULL
  );
-- Index blindcoins(reserve_pub) for get_reserves_out statement
CREATE INDEX reserves_out_reserve_pub_index
  ON reserves_out
  (reserve_pub);
CREATE INDEX reserves_out_execution_date
  ON reserves_out
  (execution_date);
CREATE INDEX reserves_out_for_get_withdraw_info
  ON reserves_out
  (denom_pub_hash
  ,h_blind_ev
  );
-- Table with coins that have been (partially) spent, used to track
-- coin information only once.
CREATE TABLE IF NOT EXISTS known_coins
  (coin_pub BYTEA NOT NULL PRIMARY KEY CHECK (LENGTH(coin_pub)=32)
  ,denom_pub_hash BYTEA NOT NULL REFERENCES denominations (denom_pub_hash) ON DELETE CASCADE
  ,denom_sig BYTEA NOT NULL
  );
CREATE INDEX known_coins_by_denomination
  ON known_coins
  (denom_pub_hash);
-- Table with the commitments made when melting a coin. */
CREATE TABLE IF NOT EXISTS refresh_commitments
  (melt_serial_id BIGSERIAL UNIQUE
  ,rc BYTEA PRIMARY KEY CHECK (LENGTH(rc)=64)
  ,old_coin_pub BYTEA NOT NULL REFERENCES known_coins (coin_pub) ON DELETE CASCADE
  ,old_coin_sig BYTEA NOT NULL CHECK(LENGTH(old_coin_sig)=64)
  ,amount_with_fee_val INT8 NOT NULL
  ,amount_with_fee_frac INT4 NOT NULL
  ,noreveal_index INT4 NOT NULL
  );
CREATE INDEX refresh_commitments_old_coin_pub_index
  ON refresh_commitments
  (old_coin_pub);
-- Table with the revelations about the new coins that are to be created
-- during a melting session.  Includes the session, the cut-and-choose
-- index and the index of the new coin, and the envelope of the new
-- coin to be signed, as well as the encrypted information about the
-- private key and the blinding factor for the coin (for verification
-- in case this newcoin_index is chosen to be revealed)
CREATE TABLE IF NOT EXISTS refresh_revealed_coins
  (rc BYTEA NOT NULL REFERENCES refresh_commitments (rc) ON DELETE CASCADE
  ,newcoin_index INT4 NOT NULL
  ,link_sig BYTEA NOT NULL CHECK(LENGTH(link_sig)=64)
  ,denom_pub_hash BYTEA NOT NULL REFERENCES denominations (denom_pub_hash) ON DELETE CASCADE
  ,coin_ev BYTEA UNIQUE NOT NULL
  ,h_coin_ev BYTEA NOT NULL CHECK(LENGTH(h_coin_ev)=64)
  ,ev_sig BYTEA NOT NULL
  ,PRIMARY KEY (rc, newcoin_index)
  ,UNIQUE (h_coin_ev)
  );
CREATE INDEX refresh_revealed_coins_coin_pub_index
  ON refresh_revealed_coins
  (denom_pub_hash);
-- Table with the transfer keys of a refresh operation; includes
-- the rc for which this is the link information, the
-- transfer public key (for gamma) and the revealed transfer private
-- keys (array of TALER_CNC_KAPPA - 1 entries, with gamma being skipped) */
CREATE TABLE IF NOT EXISTS refresh_transfer_keys
  (rc BYTEA NOT NULL PRIMARY KEY REFERENCES refresh_commitments (rc) ON DELETE CASCADE
  ,transfer_pub BYTEA NOT NULL CHECK(LENGTH(transfer_pub)=32)
  ,transfer_privs BYTEA NOT NULL
  );
-- for get_link (not sure if this helps, as there should be very few
-- transfer_pubs per rc, but at least in theory this helps the ORDER BY
-- clause.
CREATE INDEX refresh_transfer_keys_coin_tpub
  ON refresh_transfer_keys
  (rc
  ,transfer_pub
  );
-- This table contains the wire transfers the exchange is supposed to
-- execute to transmit funds to the merchants (and manage refunds).
CREATE TABLE IF NOT EXISTS deposits
  (deposit_serial_id BIGSERIAL PRIMARY KEY
  ,coin_pub BYTEA NOT NULL REFERENCES known_coins (coin_pub) ON DELETE CASCADE
  ,amount_with_fee_val INT8 NOT NULL
  ,amount_with_fee_frac INT4 NOT NULL
  ,timestamp INT8 NOT NULL
  ,refund_deadline INT8 NOT NULL
  ,wire_deadline INT8 NOT NULL
  ,merchant_pub BYTEA NOT NULL CHECK (LENGTH(merchant_pub)=32)
  ,h_contract_terms BYTEA NOT NULL CHECK (LENGTH(h_contract_terms)=64)
  ,h_wire BYTEA NOT NULL CHECK (LENGTH(h_wire)=64)
  ,coin_sig BYTEA NOT NULL CHECK (LENGTH(coin_sig)=64)
  ,wire TEXT NOT NULL
  ,tiny BOOLEAN NOT NULL DEFAULT FALSE
  ,done BOOLEAN NOT NULL DEFAULT FALSE
  ,UNIQUE (coin_pub, merchant_pub, h_contract_terms)
  );
-- Index for get_deposit_for_wtid and get_deposit_statement */
CREATE INDEX deposits_coin_pub_merchant_contract_index
  ON deposits
  (coin_pub
  ,merchant_pub
  ,h_contract_terms
  );
-- Index for deposits_get_ready
CREATE INDEX deposits_get_ready_index
  ON deposits
  (tiny
  ,done
  ,wire_deadline
  ,refund_deadline
  );
-- Index for deposits_iterate_matching
CREATE INDEX deposits_iterate_matching
  ON deposits
  (merchant_pub
  ,h_wire
  ,done
  ,wire_deadline
  );
-- Table with information about coins that have been refunded. (Technically
-- one of the deposit operations that a coin was involved with is refunded.)
-- The combo of coin_pub, merchant_pub, h_contract_terms and rtransaction_id
-- MUST be unique, and we usually select by coin_pub so that one goes first. */
CREATE TABLE IF NOT EXISTS refunds
  (refund_serial_id BIGSERIAL UNIQUE
  ,coin_pub BYTEA NOT NULL REFERENCES known_coins (coin_pub) ON DELETE CASCADE
  ,merchant_pub BYTEA NOT NULL CHECK(LENGTH(merchant_pub)=32)
  ,merchant_sig BYTEA NOT NULL CHECK(LENGTH(merchant_sig)=64)
  ,h_contract_terms BYTEA NOT NULL CHECK(LENGTH(h_contract_terms)=64)
  ,rtransaction_id INT8 NOT NULL
  ,amount_with_fee_val INT8 NOT NULL
  ,amount_with_fee_frac INT4 NOT NULL
  ,PRIMARY KEY (coin_pub, merchant_pub, h_contract_terms, rtransaction_id)
  );
CREATE INDEX refunds_coin_pub_index
  ON refunds
  (coin_pub);
-- This table contains the data for
-- wire transfers the exchange has executed.
CREATE TABLE IF NOT EXISTS wire_out
  (wireout_uuid BIGSERIAL PRIMARY KEY
  ,execution_date INT8 NOT NULL
  ,wtid_raw BYTEA UNIQUE NOT NULL CHECK (LENGTH(wtid_raw)=32)
  ,wire_target TEXT NOT NULL
  ,exchange_account_section TEXT NOT NULL
  ,amount_val INT8 NOT NULL
  ,amount_frac INT4 NOT NULL
  );
-- Table for the tracking API, mapping from wire transfer identifier
-- to transactions and back
CREATE TABLE IF NOT EXISTS aggregation_tracking
  (aggregation_serial_id BIGSERIAL UNIQUE
  ,deposit_serial_id INT8 PRIMARY KEY REFERENCES deposits (deposit_serial_id) ON DELETE CASCADE
  ,wtid_raw BYTEA  CONSTRAINT wire_out_ref REFERENCES wire_out(wtid_raw) ON DELETE CASCADE DEFERRABLE
  );
-- Index for lookup_transactions statement on wtid
CREATE INDEX aggregation_tracking_wtid_index
  ON aggregation_tracking
  (wtid_raw);
-- Table for the wire fees.
CREATE TABLE IF NOT EXISTS wire_fee
  (wire_method VARCHAR NOT NULL
  ,start_date INT8 NOT NULL
  ,end_date INT8 NOT NULL
  ,wire_fee_val INT8 NOT NULL
  ,wire_fee_frac INT4 NOT NULL
  ,closing_fee_val INT8 NOT NULL
  ,closing_fee_frac INT4 NOT NULL
  ,master_sig BYTEA NOT NULL CHECK (LENGTH(master_sig)=64)
  ,PRIMARY KEY (wire_method, start_date)
  );
CREATE INDEX wire_fee_gc_index
  ON wire_fee
  (end_date);
-- Table for /payback information
-- Do not cascade on the coin_pub, as we may keep the coin alive! */
CREATE TABLE IF NOT EXISTS payback
  (payback_uuid BIGSERIAL UNIQUE
  ,coin_pub BYTEA NOT NULL REFERENCES known_coins (coin_pub)
  ,coin_sig BYTEA NOT NULL CHECK(LENGTH(coin_sig)=64)
  ,coin_blind BYTEA NOT NULL CHECK(LENGTH(coin_blind)=32)
  ,amount_val INT8 NOT NULL
  ,amount_frac INT4 NOT NULL
  ,timestamp INT8 NOT NULL
  ,h_blind_ev BYTEA NOT NULL REFERENCES reserves_out (h_blind_ev) ON DELETE CASCADE
  );
CREATE INDEX payback_by_coin_index
  ON payback
  (coin_pub);
CREATE INDEX payback_by_h_blind_ev
  ON payback
  (h_blind_ev);
CREATE INDEX payback_for_by_reserve
  ON payback
  (coin_pub
  ,h_blind_ev
  );
-- Table for /payback-refresh information
-- Do not cascade on the coin_pub, as we may keep the coin alive! */
CREATE TABLE IF NOT EXISTS payback_refresh
  (payback_refresh_uuid BIGSERIAL UNIQUE
  ,coin_pub BYTEA NOT NULL REFERENCES known_coins (coin_pub)
  ,coin_sig BYTEA NOT NULL CHECK(LENGTH(coin_sig)=64)
  ,coin_blind BYTEA NOT NULL CHECK(LENGTH(coin_blind)=32)
  ,amount_val INT8 NOT NULL
  ,amount_frac INT4 NOT NULL
  ,timestamp INT8 NOT NULL
  ,h_blind_ev BYTEA NOT NULL REFERENCES refresh_revealed_coins (h_coin_ev) ON DELETE CASCADE
  );
CREATE INDEX payback_refresh_by_coin_index
  ON payback_refresh
  (coin_pub);
CREATE INDEX payback_refresh_by_h_blind_ev
  ON payback_refresh
  (h_blind_ev);
CREATE INDEX payback_refresh_for_by_reserve
  ON payback_refresh
  (coin_pub
  ,h_blind_ev
  );
-- This table contains the pre-commit data for
-- wire transfers the exchange is about to execute.
CREATE TABLE IF NOT EXISTS prewire
  (prewire_uuid BIGSERIAL PRIMARY KEY
  ,type TEXT NOT NULL
  ,finished BOOLEAN NOT NULL DEFAULT false
  ,buf BYTEA NOT NULL
  );
-- Index for wire_prepare_data_get and gc_prewire statement
CREATE INDEX prepare_iteration_index
  ON prewire
  (finished);

-- Complete transaction
COMMIT;
