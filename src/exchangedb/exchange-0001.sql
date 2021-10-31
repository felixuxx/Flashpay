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
SELECT _v.register_patch('exchange-0001', NULL, NULL);


CREATE TABLE IF NOT EXISTS denominations
  (denominations_serial BIGSERIAL UNIQUE
  ,denom_pub_hash BYTEA PRIMARY KEY CHECK (LENGTH(denom_pub_hash)=64)
  ,denom_type INT4 NOT NULL DEFAULT (0)
  ,age_restrictions INT4 NOT NULL DEFAULT (0)
  ,denom_pub BYTEA NOT NULL
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
COMMENT ON COLUMN denominations.denom_type
  IS 'determines cipher type for blind signatures used with this denomination; 0 is for RSA';
COMMENT ON COLUMN denominations.age_restrictions
  IS 'bitmask with the age restrictions that are being used for this denomination; 0 if denomination does not support the use of age restrictions';
COMMENT ON COLUMN denominations.denominations_serial
  IS 'needed for exchange-auditor replication logic';

CREATE INDEX IF NOT EXISTS denominations_expire_legal_index
  ON denominations
  (expire_legal);


CREATE TABLE IF NOT EXISTS denomination_revocations
  (denom_revocations_serial_id BIGSERIAL UNIQUE
  ,denominations_serial INT8 PRIMARY KEY REFERENCES denominations (denominations_serial) ON DELETE CASCADE
  ,master_sig BYTEA NOT NULL CHECK (LENGTH(master_sig)=64)
  );
COMMENT ON TABLE denomination_revocations
  IS 'remembering which denomination keys have been revoked';


CREATE TABLE IF NOT EXISTS wire_targets
(wire_target_serial_id BIGSERIAL UNIQUE
,h_payto BYTEA NOT NULL CHECK (LENGTH(h_payto)=64)
,payto_uri VARCHAR NOT NULL
,kyc_ok BOOLEAN NOT NULL DEFAULT (false)
,oauth_username VARCHAR
,PRIMARY KEY (h_payto)
);
COMMENT ON TABLE wire_targets
  IS 'All recipients of money via the exchange';
COMMENT ON COLUMN wire_targets.payto_uri
  IS 'Can be a regular bank account, or also be a URI identifying a reserve-account (for P2P payments)';
COMMENT ON COLUMN wire_targets.h_payto
  IS 'Unsalted hash of payto_uri';
COMMENT ON COLUMN wire_targets.kyc_ok
  IS 'true if the KYC check was passed successfully';
COMMENT ON COLUMN wire_targets.oauth_username
  IS 'Name of the user that was used for OAuth 2.0-based legitimization';


CREATE TABLE IF NOT EXISTS reserves
  (reserve_uuid BIGSERIAL UNIQUE
  ,reserve_pub BYTEA PRIMARY KEY CHECK(LENGTH(reserve_pub)=32)
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
  ,reserve_uuid INT8 NOT NULL REFERENCES reserves (reserve_uuid) ON DELETE CASCADE
  ,wire_reference INT8 NOT NULL
  ,credit_val INT8 NOT NULL
  ,credit_frac INT4 NOT NULL
  ,wire_source_serial_id INT8 NOT NULL REFERENCES wire_targets (wire_target_serial_id)
  ,exchange_account_section TEXT NOT NULL
  ,execution_date INT8 NOT NULL
  ,PRIMARY KEY (reserve_uuid, wire_reference)
  );
COMMENT ON TABLE reserves_in
  IS 'list of transfers of funds into the reserves, one per incoming wire transfer';
COMMENT ON COLUMN reserves_in.wire_source_serial_id
  IS 'Identifies the debited bank account and KYC status';-- FIXME: explain 'wire_reference'!
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
  ,reserve_uuid INT8 NOT NULL REFERENCES reserves (reserve_uuid) ON DELETE CASCADE
  ,execution_date INT8 NOT NULL
  ,wtid BYTEA NOT NULL CHECK (LENGTH(wtid)=32)
  ,wire_target_serial_id INT8 NOT NULL REFERENCES wire_targets (wire_target_serial_id)
  ,amount_val INT8 NOT NULL
  ,amount_frac INT4 NOT NULL
  ,closing_fee_val INT8 NOT NULL
  ,closing_fee_frac INT4 NOT NULL);
COMMENT ON TABLE reserves_close
  IS 'wire transfers executed by the reserve to close reserves';
COMMENT ON COLUMN reserves_close.wire_target_serial_id
  IS 'Identifies the credited bank account (and KYC status). Note that closing does not depend on KYC.';

CREATE INDEX IF NOT EXISTS reserves_close_by_uuid
  ON reserves_close
  (reserve_uuid);


CREATE TABLE IF NOT EXISTS reserves_out
  (reserve_out_serial_id BIGSERIAL UNIQUE
  ,h_blind_ev BYTEA PRIMARY KEY CHECK (LENGTH(h_blind_ev)=64)
  ,denominations_serial INT8 NOT NULL REFERENCES denominations (denominations_serial)
  ,denom_sig BYTEA NOT NULL
  ,reserve_uuid INT8 NOT NULL REFERENCES reserves (reserve_uuid) ON DELETE CASCADE
  ,reserve_sig BYTEA NOT NULL CHECK (LENGTH(reserve_sig)=64)
  ,execution_date INT8 NOT NULL
  ,amount_with_fee_val INT8 NOT NULL
  ,amount_with_fee_frac INT4 NOT NULL
  );
COMMENT ON TABLE reserves_out
  IS 'Withdraw operations performed on reserves.';
COMMENT ON COLUMN reserves_out.h_blind_ev
  IS 'Hash of the blinded coin, used as primary key here so that broken clients that use a non-random coin or blinding factor fail to withdraw (otherwise they would fail on deposit when the coin is not unique there).';
COMMENT ON COLUMN reserves_out.denominations_serial
  IS 'We do not CASCADE ON DELETE here, we may keep the denomination data alive';

CREATE INDEX IF NOT EXISTS reserves_out_reserve_uuid_index
  ON reserves_out
  (reserve_uuid);
COMMENT ON INDEX reserves_out_reserve_uuid_index
  IS 'for get_reserves_out';

CREATE INDEX IF NOT EXISTS reserves_out_execution_date
  ON reserves_out
  (execution_date);

CREATE INDEX IF NOT EXISTS reserves_out_for_get_withdraw_info
  ON reserves_out
  (denominations_serial
  ,h_blind_ev
  );

CREATE TABLE IF NOT EXISTS auditors
  (auditor_uuid BIGSERIAL UNIQUE
  ,auditor_pub BYTEA PRIMARY KEY CHECK (LENGTH(auditor_pub)=32)
  ,auditor_name VARCHAR NOT NULL
  ,auditor_url VARCHAR NOT NULL
  ,is_active BOOLEAN NOT NULL
  ,last_change INT8 NOT NULL
  );
COMMENT ON TABLE auditors
  IS 'Table with auditors the exchange uses or has used in the past. Entries never expire as we need to remember the last_change column indefinitely.';
COMMENT ON COLUMN auditors.auditor_pub
  IS 'Public key of the auditor.';
COMMENT ON COLUMN auditors.auditor_url
  IS 'The base URL of the auditor.';
COMMENT ON COLUMN auditors.is_active
  IS 'true if we are currently supporting the use of this auditor.';
COMMENT ON COLUMN auditors.last_change
  IS 'Latest time when active status changed. Used to detect replays of old messages.';


CREATE TABLE IF NOT EXISTS auditor_denom_sigs
  (auditor_denom_serial BIGSERIAL UNIQUE
  ,auditor_uuid INT8 NOT NULL REFERENCES auditors (auditor_uuid) ON DELETE CASCADE
  ,denominations_serial INT8 NOT NULL REFERENCES denominations (denominations_serial) ON DELETE CASCADE
  ,auditor_sig BYTEA CHECK (LENGTH(auditor_sig)=64)
  ,PRIMARY KEY (denominations_serial, auditor_uuid)
  );
COMMENT ON TABLE auditor_denom_sigs
  IS 'Table with auditor signatures on exchange denomination keys.';
COMMENT ON COLUMN auditor_denom_sigs.auditor_uuid
  IS 'Identifies the auditor.';
COMMENT ON COLUMN auditor_denom_sigs.denominations_serial
  IS 'Denomination the signature is for.';
COMMENT ON COLUMN auditor_denom_sigs.auditor_sig
  IS 'Signature of the auditor, of purpose TALER_SIGNATURE_AUDITOR_EXCHANGE_KEYS.';


CREATE TABLE IF NOT EXISTS exchange_sign_keys
  (esk_serial BIGSERIAL UNIQUE
  ,exchange_pub BYTEA PRIMARY KEY CHECK (LENGTH(exchange_pub)=32)
  ,master_sig BYTEA NOT NULL CHECK (LENGTH(master_sig)=64)
  ,valid_from INT8 NOT NULL
  ,expire_sign INT8 NOT NULL
  ,expire_legal INT8 NOT NULL
  );
COMMENT ON TABLE exchange_sign_keys
  IS 'Table with master public key signatures on exchange online signing keys.';
COMMENT ON COLUMN exchange_sign_keys.exchange_pub
  IS 'Public online signing key of the exchange.';
COMMENT ON COLUMN exchange_sign_keys.master_sig
  IS 'Signature affirming the validity of the signing key of purpose TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY.';
COMMENT ON COLUMN exchange_sign_keys.valid_from
  IS 'Time when this online signing key will first be used to sign messages.';
COMMENT ON COLUMN exchange_sign_keys.expire_sign
  IS 'Time when this online signing key will no longer be used to sign.';
COMMENT ON COLUMN exchange_sign_keys.expire_legal
  IS 'Time when this online signing key legally expires.';


CREATE TABLE IF NOT EXISTS signkey_revocations
  (signkey_revocations_serial_id BIGSERIAL UNIQUE
  ,esk_serial INT8 PRIMARY KEY REFERENCES exchange_sign_keys (esk_serial) ON DELETE CASCADE
  ,master_sig BYTEA NOT NULL CHECK (LENGTH(master_sig)=64)
  );
COMMENT ON TABLE signkey_revocations
  IS 'remembering which online signing keys have been revoked';


CREATE TABLE IF NOT EXISTS known_coins
  (known_coin_id BIGSERIAL UNIQUE
  ,coin_pub BYTEA NOT NULL PRIMARY KEY CHECK (LENGTH(coin_pub)=32)
  ,age_hash BYTEA CHECK (LENGTH(age_hash)=32)
  ,denominations_serial INT8 NOT NULL REFERENCES denominations (denominations_serial) ON DELETE CASCADE
  ,denom_sig BYTEA NOT NULL
  );
COMMENT ON TABLE known_coins
  IS 'information about coins and their signatures, so we do not have to store the signatures more than once if a coin is involved in multiple operations';
COMMENT ON COLUMN known_coins.coin_pub
  IS 'EdDSA public key of the coin';
COMMENT ON COLUMN known_coins.age_hash
  IS 'Optional hash for age restrictions as per DD 24 (active if denom_type has the respective bit set)';
COMMENT ON COLUMN known_coins.denom_sig
  IS 'This is the signature of the exchange that affirms that the coin is a valid coin. The specific signature type depends on denom_type of the denomination.';

CREATE INDEX IF NOT EXISTS known_coins_by_denomination
  ON known_coins
  (denominations_serial);


CREATE TABLE IF NOT EXISTS refresh_commitments
  (melt_serial_id BIGSERIAL UNIQUE
  ,rc BYTEA PRIMARY KEY CHECK (LENGTH(rc)=64)
  ,old_known_coin_id INT8 NOT NULL REFERENCES known_coins (known_coin_id) ON DELETE CASCADE
  ,old_coin_sig BYTEA NOT NULL CHECK(LENGTH(old_coin_sig)=64)
  ,amount_with_fee_val INT8 NOT NULL
  ,amount_with_fee_frac INT4 NOT NULL
  ,noreveal_index INT4 NOT NULL
  );
COMMENT ON TABLE refresh_commitments
  IS 'Commitments made when melting coins and the gamma value chosen by the exchange.';

CREATE INDEX IF NOT EXISTS refresh_commitments_old_coin_id_index
  ON refresh_commitments
  (old_known_coin_id);


CREATE TABLE IF NOT EXISTS refresh_revealed_coins
  (rrc_serial BIGSERIAL UNIQUE
  ,melt_serial_id INT8 NOT NULL REFERENCES refresh_commitments (melt_serial_id) ON DELETE CASCADE
  ,freshcoin_index INT4 NOT NULL
  ,link_sig BYTEA NOT NULL CHECK(LENGTH(link_sig)=64)
  ,denominations_serial INT8 NOT NULL REFERENCES denominations (denominations_serial) ON DELETE CASCADE
  ,coin_ev BYTEA UNIQUE NOT NULL
  ,h_coin_ev BYTEA NOT NULL CHECK(LENGTH(h_coin_ev)=64)
  ,ev_sig BYTEA NOT NULL
  ,PRIMARY KEY (melt_serial_id, freshcoin_index)
  ,UNIQUE (h_coin_ev)
  );
COMMENT ON TABLE refresh_revealed_coins
  IS 'Revelations about the new coins that are to be created during a melting session.';
COMMENT ON COLUMN refresh_revealed_coins.rrc_serial
  IS 'needed for exchange-auditor replication logic';
COMMENT ON COLUMN refresh_revealed_coins.melt_serial_id
  IS 'Identifies the refresh commitment (rc) of the melt operation.';
COMMENT ON COLUMN refresh_revealed_coins.freshcoin_index
  IS 'index of the fresh coin being created (one melt operation may result in multiple fresh coins)';
COMMENT ON COLUMN refresh_revealed_coins.coin_ev
  IS 'envelope of the new coin to be signed';
COMMENT ON COLUMN refresh_revealed_coins.h_coin_ev
  IS 'hash of the envelope of the new coin to be signed (for lookups)';
COMMENT ON COLUMN refresh_revealed_coins.ev_sig
  IS 'exchange signature over the envelope';

CREATE INDEX IF NOT EXISTS refresh_revealed_coins_denominations_index
  ON refresh_revealed_coins
  (denominations_serial);


CREATE TABLE IF NOT EXISTS refresh_transfer_keys
  (rtc_serial BIGSERIAL UNIQUE
  ,melt_serial_id INT8 PRIMARY KEY REFERENCES refresh_commitments (melt_serial_id) ON DELETE CASCADE
  ,transfer_pub BYTEA NOT NULL CHECK(LENGTH(transfer_pub)=32)
  ,transfer_privs BYTEA NOT NULL
  );
COMMENT ON TABLE refresh_transfer_keys
  IS 'Transfer keys of a refresh operation (the data revealed to the exchange).';
COMMENT ON COLUMN refresh_transfer_keys.rtc_serial
  IS 'needed for exchange-auditor replication logic';
COMMENT ON COLUMN refresh_transfer_keys.melt_serial_id
  IS 'Identifies the refresh commitment (rc) of the operation.';
COMMENT ON COLUMN refresh_transfer_keys.transfer_pub
  IS 'transfer public key for the gamma index';
COMMENT ON COLUMN refresh_transfer_keys.transfer_privs
  IS 'array of TALER_CNC_KAPPA - 1 transfer private keys that have been revealed, with the gamma entry being skipped';

CREATE INDEX IF NOT EXISTS refresh_transfer_keys_coin_tpub
  ON refresh_transfer_keys
  (melt_serial_id
  ,transfer_pub
  );
COMMENT ON INDEX refresh_transfer_keys_coin_tpub
  IS 'for get_link (unsure if this helps or hurts for performance as there should be very few transfer public keys per rc, but at least in theory this helps the ORDER BY clause)';


CREATE TABLE IF NOT EXISTS deposits
  (deposit_serial_id BIGSERIAL PRIMARY KEY
  ,shard INT8 NOT NULL DEFAULT 0
  ,known_coin_id INT8 NOT NULL REFERENCES known_coins (known_coin_id) ON DELETE CASCADE
  ,amount_with_fee_val INT8 NOT NULL
  ,amount_with_fee_frac INT4 NOT NULL
  ,wallet_timestamp INT8 NOT NULL
  ,exchange_timestamp INT8 NOT NULL
  ,refund_deadline INT8 NOT NULL
  ,wire_deadline INT8 NOT NULL
  ,merchant_pub BYTEA NOT NULL CHECK (LENGTH(merchant_pub)=32)
  ,h_contract_terms BYTEA NOT NULL CHECK (LENGTH(h_contract_terms)=64)
  ,coin_sig BYTEA NOT NULL CHECK (LENGTH(coin_sig)=64)
  ,wire_salt BYTEA NOT NULL CHECK (LENGTH(wire_salt)=16)
  ,wire_target_serial_id INT8 NOT NULL REFERENCES wire_targets (wire_target_serial_id)
  ,tiny BOOLEAN NOT NULL DEFAULT FALSE
  ,done BOOLEAN NOT NULL DEFAULT FALSE
  ,extension_blocked BOOLEAN NOT NULL DEFAULT FALSE
  ,extension_options VARCHAR
  ,UNIQUE (known_coin_id, merchant_pub, h_contract_terms)
  );
COMMENT ON TABLE deposits
  IS 'Deposits we have received and for which we need to make (aggregate) wire transfers (and manage refunds).';
COMMENT ON COLUMN deposits.shard
  IS 'Used for load sharding. Should be set based on h_wire, merchant_pub and a service salt. Default of 0 onlyapplies for columns migrated from a previous version without sharding support. 64-bit value because we need an *unsigned* 32-bit value.';
COMMENT ON COLUMN deposits.wire_target_serial_id
  IS 'Identifies the target bank account and KYC status';COMMENT ON COLUMN deposits.wire_salt
  IS 'Salt used when hashing the payto://-URI to get the h_wire';
COMMENT ON COLUMN deposits.done
  IS 'Set to TRUE once we have included this deposit in some aggregate wire transfer to the merchant';
COMMENT ON COLUMN deposits.extension_blocked
  IS 'True if the aggregation of the deposit is currently blocked by some extension mechanism. Used to filter out deposits that must not be processed by the canonical deposit logic.';
COMMENT ON COLUMN deposits.extension_options
  IS 'JSON object with options set that the exchange needs to consider when executing the deposit. Supported details depend on the extensions supported by the exchange.';
COMMENT ON COLUMN deposits.tiny
  IS 'Set to TRUE if we decided that the amount is too small to ever trigger a wire transfer by itself (requires real aggregation)';

CREATE INDEX IF NOT EXISTS deposits_coin_pub_merchant_contract_index
  ON deposits
  (known_coin_id
  ,merchant_pub
  ,h_contract_terms
  );
COMMENT ON INDEX deposits_coin_pub_merchant_contract_index
  IS 'for get_deposit_for_wtid and test_deposit_done';
CREATE INDEX IF NOT EXISTS deposits_get_ready_index
  ON deposits
  (shard
  ,tiny
  ,done
  ,extension_blocked
  ,wire_deadline
  ,refund_deadline
  );
COMMENT ON INDEX deposits_coin_pub_merchant_contract_index
  IS 'for deposits_get_ready';
CREATE INDEX IF NOT EXISTS deposits_iterate_matching_index
  ON deposits
  (merchant_pub
  ,wire_target_serial_id
  ,done
  ,extension_blocked
  ,wire_deadline
  );
COMMENT ON INDEX deposits_iterate_matching_index
  IS 'for deposits_iterate_matching';


CREATE TABLE IF NOT EXISTS refunds
  (refund_serial_id BIGSERIAL UNIQUE
  ,deposit_serial_id INT8 NOT NULL REFERENCES deposits (deposit_serial_id) ON DELETE CASCADE
  ,merchant_sig BYTEA NOT NULL CHECK(LENGTH(merchant_sig)=64)
  ,rtransaction_id INT8 NOT NULL
  ,amount_with_fee_val INT8 NOT NULL
  ,amount_with_fee_frac INT4 NOT NULL
  ,PRIMARY KEY (deposit_serial_id, rtransaction_id)
  );
COMMENT ON TABLE refunds
  IS 'Data on coins that were refunded. Technically, refunds always apply against specific deposit operations involving a coin. The combination of coin_pub, merchant_pub, h_contract_terms and rtransaction_id MUST be unique, and we usually select by coin_pub so that one goes first.';
COMMENT ON COLUMN refunds.deposit_serial_id
  IS 'Identifies ONLY the merchant_pub, h_contract_terms and known_coin_id. Multiple deposits may match a refund, this only identifies one of them.';
COMMENT ON COLUMN refunds.rtransaction_id
  IS 'used by the merchant to make refunds unique in case the same coin for the same deposit gets a subsequent (higher) refund';


CREATE TABLE IF NOT EXISTS wire_out
  (wireout_uuid BIGSERIAL PRIMARY KEY
  ,execution_date INT8 NOT NULL
  ,wtid_raw BYTEA UNIQUE NOT NULL CHECK (LENGTH(wtid_raw)=32)
  ,wire_target_serial_id INT8 NOT NULL REFERENCES wire_targets (wire_target_serial_id)
  ,exchange_account_section TEXT NOT NULL
  ,amount_val INT8 NOT NULL
  ,amount_frac INT4 NOT NULL
  );
COMMENT ON TABLE wire_out
  IS 'wire transfers the exchange has executed';
COMMENT ON COLUMN wire_out.exchange_account_section
  IS 'identifies the configuration section with the debit account of this payment';
COMMENT ON COLUMN wire_out.wire_target_serial_id
  IS 'Identifies the credited bank account and KYC status';

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
  (wire_fee_serial BIGSERIAL UNIQUE
  ,wire_method VARCHAR NOT NULL
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
COMMENT ON COLUMN wire_fee.wire_fee_serial
  IS 'needed for exchange-auditor replication logic';

CREATE INDEX IF NOT EXISTS wire_fee_gc_index
  ON wire_fee
  (end_date);


CREATE TABLE IF NOT EXISTS recoup
  (recoup_uuid BIGSERIAL UNIQUE
  ,known_coin_id INT8 NOT NULL REFERENCES known_coins (known_coin_id)
  ,coin_sig BYTEA NOT NULL CHECK(LENGTH(coin_sig)=64)
  ,coin_blind BYTEA NOT NULL CHECK(LENGTH(coin_blind)=32)
  ,amount_val INT8 NOT NULL
  ,amount_frac INT4 NOT NULL
  ,timestamp INT8 NOT NULL
  ,reserve_out_serial_id INT8 NOT NULL REFERENCES reserves_out (reserve_out_serial_id) ON DELETE CASCADE
  );
COMMENT ON TABLE recoup
  IS 'Information about recoups that were executed';
COMMENT ON COLUMN recoup.known_coin_id
  IS 'Do not CASCADE ON DROP on the known_coin_id, as we may keep the coin alive!';
COMMENT ON COLUMN recoup.reserve_out_serial_id
  IS 'Identifies the h_blind_ev of the recouped coin.';

CREATE INDEX IF NOT EXISTS recoup_by_h_blind_ev
  ON recoup
  (reserve_out_serial_id);
CREATE INDEX IF NOT EXISTS recoup_for_by_reserve
  ON recoup
  (known_coin_id
  ,reserve_out_serial_id
  );


CREATE TABLE IF NOT EXISTS recoup_refresh
  (recoup_refresh_uuid BIGSERIAL UNIQUE
  ,known_coin_id INT8 NOT NULL REFERENCES known_coins (known_coin_id)
  ,coin_sig BYTEA NOT NULL CHECK(LENGTH(coin_sig)=64)
  ,coin_blind BYTEA NOT NULL CHECK(LENGTH(coin_blind)=32)
  ,amount_val INT8 NOT NULL
  ,amount_frac INT4 NOT NULL
  ,timestamp INT8 NOT NULL
  ,rrc_serial INT8 NOT NULL UNIQUE REFERENCES refresh_revealed_coins (rrc_serial) ON DELETE CASCADE
  );
COMMENT ON COLUMN recoup_refresh.known_coin_id
  IS 'Do not CASCADE ON DROP on the known_coin_id, as we may keep the coin alive!';
COMMENT ON COLUMN recoup_refresh.rrc_serial
  IS 'Identifies the h_blind_ev of the recouped coin (as h_coin_ev).';

CREATE INDEX IF NOT EXISTS recoup_refresh_by_h_blind_ev
  ON recoup_refresh
  (rrc_serial);
CREATE INDEX IF NOT EXISTS recoup_refresh_for_by_reserve
  ON recoup_refresh
  (known_coin_id
  ,rrc_serial
  );


CREATE TABLE IF NOT EXISTS prewire
  (prewire_uuid BIGSERIAL PRIMARY KEY
  ,type TEXT NOT NULL
  ,finished BOOLEAN NOT NULL DEFAULT false
  ,failed BOOLEAN NOT NULL DEFAULT false
  ,buf BYTEA NOT NULL
  );
COMMENT ON TABLE prewire
  IS 'pre-commit data for wire transfers we are about to execute';
COMMENT ON COLUMN prewire.failed
  IS 'set to TRUE if the bank responded with a non-transient failure to our transfer request';
COMMENT ON COLUMN prewire.finished
  IS 'set to TRUE once bank confirmed receiving the wire transfer request';
COMMENT ON COLUMN prewire.buf
  IS 'serialized data to send to the bank to execute the wire transfer';

CREATE INDEX IF NOT EXISTS prepare_iteration_index
  ON prewire
  (finished);
COMMENT ON INDEX prepare_iteration_index
  IS 'for gc_prewire';

CREATE INDEX IF NOT EXISTS prepare_get_index
  ON prewire
  (failed,finished);
COMMENT ON INDEX prepare_get_index
  IS 'for wire_prepare_data_get';


CREATE TABLE IF NOT EXISTS wire_accounts
  (payto_uri VARCHAR PRIMARY KEY
  ,master_sig BYTEA CHECK (LENGTH(master_sig)=64)
  ,is_active BOOLEAN NOT NULL
  ,last_change INT8 NOT NULL
  );
COMMENT ON TABLE wire_accounts
  IS 'Table with current and historic bank accounts of the exchange. Entries never expire as we need to remember the last_change column indefinitely.';
COMMENT ON COLUMN wire_accounts.payto_uri
  IS 'payto URI (RFC 8905) with the bank account of the exchange.';
COMMENT ON COLUMN wire_accounts.master_sig
  IS 'Signature of purpose TALER_SIGNATURE_MASTER_WIRE_DETAILS';
COMMENT ON COLUMN wire_accounts.is_active
  IS 'true if we are currently supporting the use of this account.';
COMMENT ON COLUMN wire_accounts.last_change
  IS 'Latest time when active status changed. Used to detect replays of old messages.';
-- "wire_accounts" has no BIGSERIAL because it is a 'mutable' table
--            and is of no concern to the auditor


CREATE TABLE IF NOT EXISTS work_shards
  (shard_serial_id BIGSERIAL UNIQUE
  ,last_attempt INT8 NOT NULL
  ,start_row INT8 NOT NULL
  ,end_row INT8 NOT NULL
  ,completed BOOLEAN NOT NULL DEFAULT FALSE
  ,job_name VARCHAR NOT NULL
  ,PRIMARY KEY (job_name, start_row)
  );
COMMENT ON TABLE work_shards
  IS 'coordinates work between multiple processes working on the same job';
COMMENT ON COLUMN work_shards.shard_serial_id
  IS 'unique serial number identifying the shard';
COMMENT ON COLUMN work_shards.last_attempt
  IS 'last time a worker attempted to work on the shard';
COMMENT ON COLUMN work_shards.completed
  IS 'set to TRUE once the shard is finished by a worker';
COMMENT ON COLUMN work_shards.start_row
  IS 'row at which the shard scope starts, inclusive';
COMMENT ON COLUMN work_shards.end_row
  IS 'row at which the shard scope ends, exclusive';
COMMENT ON COLUMN work_shards.job_name
  IS 'unique name of the job the workers on this shard are performing';

CREATE INDEX IF NOT EXISTS work_shards_index
  ON work_shards
  (job_name
  ,completed
  ,last_attempt
  );


CREATE UNLOGGED TABLE IF NOT EXISTS revolving_work_shards
  (shard_serial_id BIGSERIAL UNIQUE
  ,last_attempt INT8 NOT NULL
  ,start_row INT4 NOT NULL
  ,end_row INT4 NOT NULL
  ,active BOOLEAN NOT NULL DEFAULT FALSE
  ,job_name VARCHAR NOT NULL
  ,PRIMARY KEY (job_name, start_row)
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

CREATE INDEX IF NOT EXISTS revolving_work_shards_index
  ON revolving_work_shards
  (job_name
  ,active
  ,last_attempt
  );




-- Complete transaction
COMMIT;
