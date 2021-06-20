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
SELECT _v.register_patch('exchange-0001', NULL, NULL);


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
COMMENT ON TABLE denominations
  IS 'Main denominations table. All the valid denominations the exchange knows about.';

CREATE INDEX IF NOT EXISTS denominations_expire_legal_index
  ON denominations
  (expire_legal);


CREATE TABLE IF NOT EXISTS denomination_revocations
  (denom_revocations_serial_id BIGSERIAL UNIQUE
  ,denom_pub_hash BYTEA PRIMARY KEY REFERENCES denominations (denom_pub_hash) ON DELETE CASCADE
  ,master_sig BYTEA NOT NULL CHECK (LENGTH(master_sig)=64)
  );
COMMENT ON TABLE denomination_revocations
  IS 'remembering which denomination keys have been revoked';


CREATE TABLE IF NOT EXISTS reserves
  (reserve_pub BYTEA PRIMARY KEY CHECK(LENGTH(reserve_pub)=32)
  ,account_details TEXT NOT NULL
  ,current_balance_val INT8 NOT NULL
  ,current_balance_frac INT4 NOT NULL
  ,expiration_date INT8 NOT NULL
  ,gc_date INT8 NOT NULL
  );
COMMENT ON TABLE reserves
  IS 'Summarizes the balance of a reserve. Updated when new funds are added or withdrawn.';
COMMENT ON COLUMN reserves.expiration_date
  IS 'Used to trigger closing of reserves that have not been drained after some time';
COMMENT ON COLUMN reserves.gc_date
  IS 'Used to forget all information about a reserve during garbage collection';


CREATE INDEX IF NOT EXISTS reserves_expiration_index
  ON reserves
  (expiration_date
  ,current_balance_val
  ,current_balance_frac
  );
COMMENT ON INDEX reserves_expiration_index
  IS 'used in get_expired_reserves';

CREATE INDEX IF NOT EXISTS reserves_gc_index
  ON reserves
  (gc_date);
COMMENT ON INDEX reserves_gc_index
  IS 'for reserve garbage collection';


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
COMMENT ON TABLE reserves_in
  IS 'list of transfers of funds into the reserves, one per incoming wire transfer';
-- FIXME: explain 'wire_reference'!
CREATE INDEX IF NOT EXISTS reserves_in_execution_index
  ON reserves_in
  (exchange_account_section
  ,execution_date
  );
CREATE INDEX IF NOT EXISTS reserves_in_exchange_account_serial
  ON reserves_in
  (exchange_account_section,
  reserve_in_serial_id DESC
  );


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
COMMENT ON TABLE reserves_close
  IS 'wire transfers executed by the reserve to close reserves';

CREATE INDEX IF NOT EXISTS reserves_close_by_reserve
  ON reserves_close
  (reserve_pub);


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
COMMENT ON TABLE reserves_out
  IS 'Withdraw operations performed on reserves.';
COMMENT ON COLUMN reserves_out.h_blind_ev
  IS 'Hash of the blinded coin, used as primary key here so that broken clients that use a non-random coin or blinding factor fail to withdraw (otherwise they would fail on deposit when the coin is not unique there).';
COMMENT ON COLUMN reserves_out.denom_pub_hash
  IS 'We do not CASCADE ON DELETE here, we may keep the denomination data alive';
-- FIXME: replace denom_pub_hash with denominations_serial *EVERYWHERE*

CREATE INDEX IF NOT EXISTS reserves_out_reserve_pub_index
  ON reserves_out
  (reserve_pub);
COMMENT ON INDEX reserves_out_reserve_pub_index
  IS 'for get_reserves_out';
CREATE INDEX IF NOT EXISTS reserves_out_execution_date
  ON reserves_out
  (execution_date);
CREATE INDEX IF NOT EXISTS reserves_out_for_get_withdraw_info
  ON reserves_out
  (denom_pub_hash
  ,h_blind_ev
  );


CREATE TABLE IF NOT EXISTS known_coins
  (known_coin_id BIGSERIAL UNIQUE
  ,coin_pub BYTEA NOT NULL PRIMARY KEY CHECK (LENGTH(coin_pub)=32)
  ,denom_pub_hash BYTEA NOT NULL REFERENCES denominations (denom_pub_hash) ON DELETE CASCADE
  ,denom_sig BYTEA NOT NULL
  );
COMMENT ON TABLE known_coins
  IS 'information about coins and their signatures, so we do not have to store the signatures more than once if a coin is involved in multiple operations';

CREATE INDEX IF NOT EXISTS known_coins_by_denomination
  ON known_coins
  (denom_pub_hash);


CREATE TABLE IF NOT EXISTS refresh_commitments
  (melt_serial_id BIGSERIAL UNIQUE
  ,rc BYTEA PRIMARY KEY CHECK (LENGTH(rc)=64)
  ,old_coin_pub BYTEA NOT NULL REFERENCES known_coins (coin_pub) ON DELETE CASCADE
  ,old_coin_sig BYTEA NOT NULL CHECK(LENGTH(old_coin_sig)=64)
  ,amount_with_fee_val INT8 NOT NULL
  ,amount_with_fee_frac INT4 NOT NULL
  ,noreveal_index INT4 NOT NULL
  );
COMMENT ON TABLE refresh_commitments
  IS 'Commitments made when melting coins and the gamma value chosen by the exchange.';

CREATE INDEX IF NOT EXISTS refresh_commitments_old_coin_pub_index
  ON refresh_commitments
  (old_coin_pub);


CREATE TABLE IF NOT EXISTS refresh_revealed_coins
  (rc BYTEA NOT NULL REFERENCES refresh_commitments (rc) ON DELETE CASCADE
  ,freshcoin_index INT4 NOT NULL
  ,link_sig BYTEA NOT NULL CHECK(LENGTH(link_sig)=64)
  ,denom_pub_hash BYTEA NOT NULL REFERENCES denominations (denom_pub_hash) ON DELETE CASCADE
  ,coin_ev BYTEA UNIQUE NOT NULL
  ,h_coin_ev BYTEA NOT NULL CHECK(LENGTH(h_coin_ev)=64)
  ,ev_sig BYTEA NOT NULL
  ,PRIMARY KEY (rc, freshcoin_index)
  ,UNIQUE (h_coin_ev)
  );
COMMENT ON TABLE refresh_revealed_coins
  IS 'Revelations about the new coins that are to be created during a melting session.';
COMMENT ON COLUMN refresh_revealed_coins.rc
  IS 'refresh commitment identifying the melt operation';
COMMENT ON COLUMN refresh_revealed_coins.freshcoin_index
  IS 'index of the fresh coin being created (one melt operation may result in multiple fresh coins)';
COMMENT ON COLUMN refresh_revealed_coins.coin_ev
  IS 'envelope of the new coin to be signed';
COMMENT ON COLUMN refresh_revealed_coins.h_coin_ev
  IS 'hash of the envelope of the new coin to be signed (for lookups)';
COMMENT ON COLUMN refresh_revealed_coins.ev_sig
  IS 'exchange signature over the envelope';

CREATE INDEX IF NOT EXISTS refresh_revealed_coins_coin_pub_index
  ON refresh_revealed_coins
  (denom_pub_hash);


CREATE TABLE IF NOT EXISTS refresh_transfer_keys
  (rc BYTEA NOT NULL PRIMARY KEY REFERENCES refresh_commitments (rc) ON DELETE CASCADE
  ,transfer_pub BYTEA NOT NULL CHECK(LENGTH(transfer_pub)=32)
  ,transfer_privs BYTEA NOT NULL
  );
COMMENT ON TABLE refresh_transfer_keys
  IS 'Transfer keys of a refresh operation (the data revealed to the exchange).';
COMMENT ON COLUMN refresh_transfer_keys.rc
  IS 'refresh commitment identifying the melt operation';
COMMENT ON COLUMN refresh_transfer_keys.transfer_pub
  IS 'transfer public key for the gamma index';
COMMENT ON COLUMN refresh_transfer_keys.transfer_privs
  IS 'array of TALER_CNC_KAPPA - 1 transfer private keys that have been revealed, with the gamma entry being skipped';

CREATE INDEX IF NOT EXISTS refresh_transfer_keys_coin_tpub
  ON refresh_transfer_keys
  (rc
  ,transfer_pub
  );
COMMENT ON INDEX refresh_transfer_keys_coin_tpub
  IS 'for get_link (unsure if this helps or hurts for performance as there should be very few transfer public keys per rc, but at least in theory this helps the ORDER BY clause)';


CREATE TABLE IF NOT EXISTS deposits
  (deposit_serial_id BIGSERIAL PRIMARY KEY
  ,coin_pub BYTEA NOT NULL REFERENCES known_coins (coin_pub) ON DELETE CASCADE
  ,amount_with_fee_val INT8 NOT NULL
  ,amount_with_fee_frac INT4 NOT NULL
  ,wallet_timestamp INT8 NOT NULL
  ,exchange_timestamp INT8 NOT NULL
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
COMMENT ON TABLE deposits
  IS 'Deposits we have received and for which we need to make (aggregate) wire transfers (and manage refunds).';
COMMENT ON COLUMN deposits.done
  IS 'Set to TRUE once we have included this deposit in some aggregate wire transfer to the merchant';
COMMENT ON COLUMN deposits.tiny
  IS 'Set to TRUE if we decided that the amount is too small to ever trigger a wire transfer by itself (requires real aggregation)';

CREATE INDEX IF NOT EXISTS deposits_coin_pub_merchant_contract_index
  ON deposits
  (coin_pub
  ,merchant_pub
  ,h_contract_terms
  );
COMMENT ON INDEX deposits_coin_pub_merchant_contract_index
  IS 'for get_deposit_for_wtid and test_deposit_done';
CREATE INDEX IF NOT EXISTS deposits_get_ready_index
  ON deposits
  (tiny
  ,done
  ,wire_deadline
  ,refund_deadline
  );
COMMENT ON INDEX deposits_coin_pub_merchant_contract_index
  IS 'for deposits_get_ready';
CREATE INDEX IF NOT EXISTS deposits_iterate_matching_index
  ON deposits
  (merchant_pub
  ,h_wire
  ,done
  ,wire_deadline
  );
COMMENT ON INDEX deposits_iterate_matching_index
  IS 'for deposits_iterate_matching';


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
COMMENT ON TABLE refunds
  IS 'Data on coins that were refunded. Technically, refunds always apply against specific deposit operations involving a coin. The combination of coin_pub, merchant_pub, h_contract_terms and rtransaction_id MUST be unique, and we usually select by coin_pub so that one goes first.';
COMMENT ON COLUMN refunds.rtransaction_id
  IS 'used by the merchant to make refunds unique in case the same coin for the same deposit gets a subsequent (higher) refund';

CREATE INDEX IF NOT EXISTS refunds_coin_pub_index
  ON refunds
  (coin_pub);


CREATE TABLE IF NOT EXISTS wire_out
  (wireout_uuid BIGSERIAL PRIMARY KEY
  ,execution_date INT8 NOT NULL
  ,wtid_raw BYTEA UNIQUE NOT NULL CHECK (LENGTH(wtid_raw)=32)
  ,wire_target TEXT NOT NULL
  ,exchange_account_section TEXT NOT NULL
  ,amount_val INT8 NOT NULL
  ,amount_frac INT4 NOT NULL
  );
COMMENT ON TABLE wire_out
  IS 'wire transfers the exchange has executed';


CREATE TABLE IF NOT EXISTS aggregation_tracking
  (aggregation_serial_id BIGSERIAL UNIQUE
  ,deposit_serial_id INT8 PRIMARY KEY REFERENCES deposits (deposit_serial_id) ON DELETE CASCADE
  ,wtid_raw BYTEA CONSTRAINT wire_out_ref REFERENCES wire_out(wtid_raw) ON DELETE CASCADE DEFERRABLE
  );
COMMENT ON TABLE aggregation_tracking
  IS 'mapping from wire transfer identifiers (WTID) to deposits (and back)';
COMMENT ON COLUMN aggregation_tracking.wtid_raw
  IS 'We first create entries in the aggregation_tracking table and then finally the wire_out entry once we know the total amount. Hence the constraint must be deferrable and we cannot use a wireout_uuid here, because we do not have it when these rows are created. Changing the logic to first INSERT a dummy row into wire_out and then UPDATEing that row in the same transaction would theoretically reduce per-deposit storage costs by 5 percent (24/~460 bytes).';

CREATE INDEX IF NOT EXISTS aggregation_tracking_wtid_index
  ON aggregation_tracking
  (wtid_raw);
COMMENT ON INDEX aggregation_tracking_wtid_index
  IS 'for lookup_transactions';


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
COMMENT ON TABLE wire_fee
  IS 'list of the wire fees of this exchange, by date';

CREATE INDEX IF NOT EXISTS wire_fee_gc_index
  ON wire_fee
  (end_date);


CREATE TABLE IF NOT EXISTS recoup
  (recoup_uuid BIGSERIAL UNIQUE
  ,coin_pub BYTEA NOT NULL REFERENCES known_coins (coin_pub)
  ,coin_sig BYTEA NOT NULL CHECK(LENGTH(coin_sig)=64)
  ,coin_blind BYTEA NOT NULL CHECK(LENGTH(coin_blind)=32)
  ,amount_val INT8 NOT NULL
  ,amount_frac INT4 NOT NULL
  ,timestamp INT8 NOT NULL
  ,h_blind_ev BYTEA NOT NULL REFERENCES reserves_out (h_blind_ev) ON DELETE CASCADE
  );
COMMENT ON TABLE recoup
  IS 'Information about recoups that were executed';
COMMENT ON COLUMN recoup.coin_pub
  IS 'Do not CASCADE ON DROP on the coin_pub, as we may keep the coin alive!';

-- Note: this first index is redundant;
-- It is implicitly removed by the exchange-0002.sql
-- schema changes.
CREATE INDEX IF NOT EXISTS recoup_by_coin_index
  ON recoup
  (coin_pub);
CREATE INDEX IF NOT EXISTS recoup_by_h_blind_ev
  ON recoup
  (h_blind_ev);
CREATE INDEX IF NOT EXISTS recoup_for_by_reserve
  ON recoup
  (coin_pub
  ,h_blind_ev
  );


CREATE TABLE IF NOT EXISTS recoup_refresh
  (recoup_refresh_uuid BIGSERIAL UNIQUE
  ,coin_pub BYTEA NOT NULL REFERENCES known_coins (coin_pub)
  ,coin_sig BYTEA NOT NULL CHECK(LENGTH(coin_sig)=64)
  ,coin_blind BYTEA NOT NULL CHECK(LENGTH(coin_blind)=32)
  ,amount_val INT8 NOT NULL
  ,amount_frac INT4 NOT NULL
  ,timestamp INT8 NOT NULL
  ,h_blind_ev BYTEA NOT NULL REFERENCES refresh_revealed_coins (h_coin_ev) ON DELETE CASCADE
  );
COMMENT ON COLUMN recoup_refresh.coin_pub
  IS 'Do not CASCADE ON DROP on the coin_pub, as we may keep the coin alive!';

-- Note: this index is redundant; implicitly removed
-- by the exchange-0002.sql update!
CREATE INDEX IF NOT EXISTS recoup_refresh_by_coin_index
  ON recoup_refresh
  (coin_pub);
CREATE INDEX IF NOT EXISTS recoup_refresh_by_h_blind_ev
  ON recoup_refresh
  (h_blind_ev);
CREATE INDEX IF NOT EXISTS recoup_refresh_for_by_reserve
  ON recoup_refresh
  (coin_pub
  ,h_blind_ev
  );


CREATE TABLE IF NOT EXISTS prewire
  (prewire_uuid BIGSERIAL PRIMARY KEY
  ,type TEXT NOT NULL
  ,finished BOOLEAN NOT NULL DEFAULT false
  ,buf BYTEA NOT NULL
  );
COMMENT ON TABLE prewire
  IS 'pre-commit data for wire transfers we are about to execute';

CREATE INDEX IF NOT EXISTS prepare_iteration_index
  ON prewire
  (finished);
COMMENT ON INDEX prepare_iteration_index
  IS 'for wire_prepare_data_get and gc_prewire';


-- Complete transaction
COMMIT;
