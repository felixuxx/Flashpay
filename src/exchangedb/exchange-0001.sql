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
  ,denom_type INT4 NOT NULL DEFAULT (1) -- 1 == RSA (for now, remove default later!)
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

CREATE INDEX IF NOT EXISTS denominations_by_expire_legal_index
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
  (wire_target_serial_id BIGSERIAL -- UNIQUE
  ,h_payto BYTEA PRIMARY KEY CHECK (LENGTH(h_payto)=64)
  ,payto_uri VARCHAR NOT NULL
  ,kyc_ok BOOLEAN NOT NULL DEFAULT (FALSE)
  ,external_id VARCHAR
  )
  PARTITION BY HASH (h_payto);
COMMENT ON TABLE wire_targets
  IS 'All senders and recipients of money via the exchange';
COMMENT ON COLUMN wire_targets.payto_uri
  IS 'Can be a regular bank account, or also be a URI identifying a reserve-account (for P2P payments)';
COMMENT ON COLUMN wire_targets.h_payto
  IS 'Unsalted hash of payto_uri';
COMMENT ON COLUMN wire_targets.kyc_ok
  IS 'true if the KYC check was passed successfully';
COMMENT ON COLUMN wire_targets.external_id
  IS 'Name of the user that was used for OAuth 2.0-based legitimization';
CREATE TABLE IF NOT EXISTS wire_targets_default
  PARTITION OF wire_targets
  FOR VALUES WITH (MODULUS 1, REMAINDER 0);

CREATE TABLE IF NOT EXISTS reserves
  (reserve_uuid BIGSERIAL
  ,reserve_pub BYTEA PRIMARY KEY CHECK(LENGTH(reserve_pub)=32)
  ,current_balance_val INT8 NOT NULL
  ,current_balance_frac INT4 NOT NULL
  ,expiration_date INT8 NOT NULL
  ,gc_date INT8 NOT NULL
  )
  PARTITION BY HASH (reserve_pub);
COMMENT ON TABLE reserves
  IS 'Summarizes the balance of a reserve. Updated when new funds are added or withdrawn.';
COMMENT ON COLUMN reserves.reserve_pub
  IS 'EdDSA public key of the reserve. Knowledge of the private key implies ownership over the balance.';
COMMENT ON COLUMN reserves.current_balance_val
  IS 'Current balance remaining with the reserve';
COMMENT ON COLUMN reserves.expiration_date
  IS 'Used to trigger closing of reserves that have not been drained after some time';
COMMENT ON COLUMN reserves.gc_date
  IS 'Used to forget all information about a reserve during garbage collection';
CREATE TABLE IF NOT EXISTS reserves_default
  PARTITION OF reserves
  FOR VALUES WITH (MODULUS 1, REMAINDER 0);

CREATE INDEX IF NOT EXISTS reserves_by_expiration_index
  ON reserves
  (expiration_date
  ,current_balance_val
  ,current_balance_frac
  );
COMMENT ON INDEX reserves_by_expiration_index
  IS 'used in get_expired_reserves';
CREATE INDEX IF NOT EXISTS reserves_by_reserve_uuid_index
  ON reserves
  (reserve_uuid);
CREATE INDEX IF NOT EXISTS reserves_by_gc_date_index
  ON reserves
  (gc_date);
COMMENT ON INDEX reserves_by_gc_date_index
  IS 'for reserve garbage collection';


CREATE TABLE IF NOT EXISTS reserves_in
  (reserve_in_serial_id BIGSERIAL -- UNIQUE
  ,reserve_pub BYTEA PRIMARY KEY REFERENCES reserves (reserve_pub) ON DELETE CASCADE
  ,wire_reference INT8 NOT NULL
  ,credit_val INT8 NOT NULL
  ,credit_frac INT4 NOT NULL
  ,wire_source_serial_id INT8 NOT NULL -- REFERENCES wire_targets (wire_target_serial_id)
  ,exchange_account_section TEXT NOT NULL
  ,execution_date INT8 NOT NULL
  )
  PARTITION BY HASH (reserve_pub);
COMMENT ON TABLE reserves_in
  IS 'list of transfers of funds into the reserves, one per incoming wire transfer';
COMMENT ON COLUMN reserves_in.wire_source_serial_id
  IS 'Identifies the debited bank account and KYC status';
COMMENT ON COLUMN reserves_in.reserve_pub
  IS 'Public key of the reserve. Private key signifies ownership of the remaining balance.';
COMMENT ON COLUMN reserves_in.credit_val
  IS 'Amount that was transferred into the reserve';
CREATE TABLE IF NOT EXISTS reserves_in_default
  PARTITION OF reserves_in
  FOR VALUES WITH (MODULUS 1, REMAINDER 0);

CREATE INDEX IF NOT EXISTS reserves_in_by_reserve_in_serial_id_index
  ON reserves_in
  (reserve_in_serial_id);
CREATE INDEX IF NOT EXISTS reserves_in_by_exchange_account_section_execution_date_index
  ON reserves_in
  (exchange_account_section
  ,execution_date
  );
CREATE INDEX IF NOT EXISTS reserves_in_by_exchange_account_reserve_in_serial_id_index
  ON reserves_in
  (exchange_account_section,
  reserve_in_serial_id DESC
  );


CREATE TABLE IF NOT EXISTS reserves_close
  (close_uuid BIGSERIAL -- UNIQUE / PRIMARY KEY
  ,reserve_pub BYTEA NOT NULL REFERENCES reserves (reserve_pub) ON DELETE CASCADE
  ,execution_date INT8 NOT NULL
  ,wtid BYTEA NOT NULL CHECK (LENGTH(wtid)=32)
  ,wire_target_serial_id INT8 NOT NULL -- REFERENCES wire_targets (wire_target_serial_id)
  ,amount_val INT8 NOT NULL
  ,amount_frac INT4 NOT NULL
  ,closing_fee_val INT8 NOT NULL
  ,closing_fee_frac INT4 NOT NULL)
  PARTITION BY HASH (reserve_pub);
COMMENT ON TABLE reserves_close
  IS 'wire transfers executed by the reserve to close reserves';
COMMENT ON COLUMN reserves_close.wire_target_serial_id
  IS 'Identifies the credited bank account (and KYC status). Note that closing does not depend on KYC.';
CREATE TABLE IF NOT EXISTS reserves_close_default
  PARTITION OF reserves_close
  FOR VALUES WITH (MODULUS 1, REMAINDER 0);

CREATE INDEX IF NOT EXISTS reserves_close_by_close_uuid_index
  ON reserves_close
  (close_uuid);
CREATE INDEX IF NOT EXISTS reserves_close_by_reserve_pub_index
  ON reserves_close
  (reserve_pub);


CREATE TABLE IF NOT EXISTS reserves_out
  (reserve_out_serial_id BIGSERIAL -- UNIQUE
  ,h_blind_ev BYTEA PRIMARY KEY CHECK (LENGTH(h_blind_ev)=64)
  ,denominations_serial INT8 NOT NULL REFERENCES denominations (denominations_serial)
  ,denom_sig BYTEA NOT NULL
  ,reserve_uuid INT8 NOT NULL -- REFERENCES reserves (reserve_uuid) ON DELETE CASCADE
  ,reserve_sig BYTEA NOT NULL CHECK (LENGTH(reserve_sig)=64)
  ,execution_date INT8 NOT NULL
  ,amount_with_fee_val INT8 NOT NULL
  ,amount_with_fee_frac INT4 NOT NULL
  )
  PARTITION BY HASH (h_blind_ev);
COMMENT ON TABLE reserves_out
  IS 'Withdraw operations performed on reserves.';
COMMENT ON COLUMN reserves_out.h_blind_ev
  IS 'Hash of the blinded coin, used as primary key here so that broken clients that use a non-random coin or blinding factor fail to withdraw (otherwise they would fail on deposit when the coin is not unique there).';
COMMENT ON COLUMN reserves_out.denominations_serial
  IS 'We do not CASCADE ON DELETE here, we may keep the denomination data alive';
CREATE TABLE IF NOT EXISTS reserves_out_default
  PARTITION OF reserves_out
  FOR VALUES WITH (MODULUS 1, REMAINDER 0);

CREATE INDEX IF NOT EXISTS reserves_out_by_reserve_out_serial_id_index
  ON reserves_out
  (reserve_out_serial_id);
CREATE INDEX IF NOT EXISTS reserves_out_by_reserve_uuid_and_execution_date_index
  ON reserves_out
  (reserve_uuid, execution_date);
COMMENT ON INDEX reserves_out_by_reserve_uuid_and_execution_date_index
  IS 'for get_reserves_out and exchange_do_withdraw_limit_check';


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
  IS 'Table storing which online signing keys have been revoked';


CREATE TABLE IF NOT EXISTS extensions
  (extension_id BIGSERIAL UNIQUE
  ,name VARCHAR NOT NULL UNIQUE
  ,config BYTEA NOT NULL
  ,config_sig BYTEA NOT NULL
  );
COMMENT ON TABLE extensions
  IS 'Configurations of the activated extensions';
COMMENT ON COLUMN extensions.name
  IS 'Name of the extension';
COMMENT ON COLUMN extensions.config
  IS 'Configuration of the extension as JSON-blob';
COMMENT ON COLUMN extensions.config
  IS 'Signature of the configuration of an extension, signed with the master key of the exchange';


CREATE TABLE IF NOT EXISTS known_coins
  (known_coin_id BIGSERIAL -- UNIQUE
  ,denominations_serial INT8 NOT NULL REFERENCES denominations (denominations_serial) ON DELETE CASCADE
  ,coin_pub BYTEA NOT NULL PRIMARY KEY CHECK (LENGTH(coin_pub)=32)
  ,age_hash BYTEA CHECK (LENGTH(age_hash)=32)
  ,denom_sig BYTEA NOT NULL
  ,remaining_val INT8 NOT NULL
  ,remaining_frac INT4 NOT NULL
  )
  PARTITION BY HASH (coin_pub); -- FIXME: or include denominations_serial? or multi-level partitioning?
COMMENT ON TABLE known_coins
  IS 'information about coins and their signatures, so we do not have to store the signatures more than once if a coin is involved in multiple operations';
COMMENT ON COLUMN known_coins.denominations_serial
  IS 'Denomination of the coin, determines the value of the original coin and applicable fees for coin-specific operations.';
COMMENT ON COLUMN known_coins.coin_pub
  IS 'EdDSA public key of the coin';
COMMENT ON COLUMN known_coins.remaining_val
  IS 'Value of the coin that remains to be spent';
COMMENT ON COLUMN known_coins.age_hash
  IS 'Optional hash for age restrictions as per DD 24 (active if denom_type has the respective bit set)';
COMMENT ON COLUMN known_coins.denom_sig
  IS 'This is the signature of the exchange that affirms that the coin is a valid coin. The specific signature type depends on denom_type of the denomination.';
CREATE TABLE IF NOT EXISTS known_coins_default
  PARTITION OF known_coins
  FOR VALUES WITH (MODULUS 1, REMAINDER 0);

CREATE INDEX IF NOT EXISTS known_coins_by_known_coin_id_index
  ON known_coins
  (known_coin_id);


CREATE TABLE IF NOT EXISTS refresh_commitments
  (melt_serial_id BIGSERIAL -- UNIQUE
  ,rc BYTEA PRIMARY KEY CHECK (LENGTH(rc)=64)
  ,old_coin_pub BYTEA NOT NULL REFERENCES known_coins (coin_pub) ON DELETE CASCADE
  ,old_coin_sig BYTEA NOT NULL CHECK(LENGTH(old_coin_sig)=64)
  ,amount_with_fee_val INT8 NOT NULL
  ,amount_with_fee_frac INT4 NOT NULL
  ,noreveal_index INT4 NOT NULL
  )
  PARTITION BY HASH (rc);
COMMENT ON TABLE refresh_commitments
  IS 'Commitments made when melting coins and the gamma value chosen by the exchange.';
COMMENT ON COLUMN refresh_commitments.noreveal_index
  IS 'The gamma value chosen by the exchange in the cut-and-choose protocol';
COMMENT ON COLUMN refresh_commitments.rc
  IS 'Commitment made by the client, hash over the various client inputs in the cut-and-choose protocol';
COMMENT ON COLUMN refresh_commitments.old_coin_pub
  IS 'Coin being melted in the refresh process.';
CREATE TABLE IF NOT EXISTS refresh_commitments_default
  PARTITION OF refresh_commitments
  FOR VALUES WITH (MODULUS 1, REMAINDER 0);

CREATE INDEX IF NOT EXISTS refresh_commitments_by_melt_serial_id_index
  ON refresh_commitments
  (melt_serial_id);
CREATE INDEX IF NOT EXISTS refresh_commitments_by_old_coin_pub_index
  ON refresh_commitments
  (old_coin_pub);


CREATE TABLE IF NOT EXISTS refresh_revealed_coins
  (rrc_serial BIGSERIAL -- UNIQUE
  ,melt_serial_id INT8 NOT NULL -- REFERENCES refresh_commitments (melt_serial_id) ON DELETE CASCADE
  ,freshcoin_index INT4 NOT NULL
  ,link_sig BYTEA NOT NULL CHECK(LENGTH(link_sig)=64)
  ,denominations_serial INT8 NOT NULL REFERENCES denominations (denominations_serial) ON DELETE CASCADE
  ,coin_ev BYTEA NOT NULL -- UNIQUE
  ,h_coin_ev BYTEA NOT NULL CHECK(LENGTH(h_coin_ev)=64) -- UNIQUE
  ,ev_sig BYTEA NOT NULL
  --  ,PRIMARY KEY (melt_serial_id, freshcoin_index) -- done per shard
  )
  PARTITION BY HASH (melt_serial_id);
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
CREATE TABLE IF NOT EXISTS refresh_revealed_coins_default
  PARTITION OF refresh_revealed_coins
  FOR VALUES WITH (MODULUS 1, REMAINDER 0);
-- We do require this primary key on each shard!
ALTER TABLE refresh_revealed_coins_default
  ADD PRIMARY KEY (melt_serial_id, freshcoin_index);

CREATE INDEX IF NOT EXISTS refresh_revealed_coins_by_rrc_serial_index
  ON refresh_revealed_coins
  (rrc_serial);
CREATE INDEX IF NOT EXISTS refresh_revealed_coins_by_melt_serial_id_index
  ON refresh_revealed_coins
  (melt_serial_id);


CREATE TABLE IF NOT EXISTS refresh_transfer_keys
  (rtc_serial BIGSERIAL -- UNIQUE
  ,melt_serial_id INT8 PRIMARY KEY -- REFERENCES refresh_commitments (melt_serial_id) ON DELETE CASCADE
  ,transfer_pub BYTEA NOT NULL CHECK(LENGTH(transfer_pub)=32)
  ,transfer_privs BYTEA NOT NULL
  )
  PARTITION BY HASH (melt_serial_id);
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
CREATE TABLE IF NOT EXISTS refresh_transfer_keys_default
  PARTITION OF refresh_transfer_keys
  FOR VALUES WITH (MODULUS 1, REMAINDER 0);

CREATE INDEX IF NOT EXISTS refresh_transfer_keys_by_rtc_serial_index
  ON refresh_transfer_keys
  (rtc_serial);


CREATE TABLE IF NOT EXISTS extension_details
  (extension_details_serial_id BIGSERIAL PRIMARY KEY
  ,extension_options VARCHAR);
COMMENT ON TABLE extension_details
  IS 'Extensions that were provided with deposits (not yet used).';
COMMENT ON COLUMN extension_details.extension_options
  IS 'JSON object with options set that the exchange needs to consider when executing a deposit. Supported details depend on the extensions supported by the exchange.';


CREATE TABLE IF NOT EXISTS deposits
  (deposit_serial_id BIGSERIAL -- PRIMARY KEY
  ,shard INT8 NOT NULL
  ,known_coin_id INT8 NOT NULL -- REFERENCES known_coins (known_coin_id) ON DELETE CASCADE
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
  ,wire_target_serial_id INT8 NOT NULL -- REFERENCES wire_targets (wire_target_serial_id)
  ,tiny BOOLEAN NOT NULL DEFAULT FALSE
  ,done BOOLEAN NOT NULL DEFAULT FALSE
  ,extension_blocked BOOLEAN NOT NULL DEFAULT FALSE
  ,extension_details_serial_id INT8 REFERENCES extension_details (extension_details_serial_id) ON DELETE CASCADE
  ,UNIQUE (shard, known_coin_id, merchant_pub, h_contract_terms)
  )
  PARTITION BY HASH (shard);
CREATE TABLE IF NOT EXISTS deposits_default
  PARTITION OF deposits
  FOR VALUES WITH (MODULUS 1, REMAINDER 0);

COMMENT ON TABLE deposits
  IS 'Deposits we have received and for which we need to make (aggregate) wire transfers (and manage refunds).';
COMMENT ON COLUMN deposits.shard
  IS 'Used for load sharding. Should be set based on h_payto and merchant_pub. 64-bit value because we need an *unsigned* 32-bit value.';
COMMENT ON COLUMN deposits.wire_target_serial_id
  IS 'Identifies the target bank account and KYC status';
COMMENT ON COLUMN deposits.wire_salt
  IS 'Salt used when hashing the payto://-URI to get the h_wire';
COMMENT ON COLUMN deposits.done
  IS 'Set to TRUE once we have included this deposit in some aggregate wire transfer to the merchant';
COMMENT ON COLUMN deposits.extension_blocked
  IS 'True if the aggregation of the deposit is currently blocked by some extension mechanism. Used to filter out deposits that must not be processed by the canonical deposit logic.';
COMMENT ON COLUMN deposits.extension_details_serial_id
  IS 'References extensions table, NULL if extensions are not used';
COMMENT ON COLUMN deposits.tiny
  IS 'Set to TRUE if we decided that the amount is too small to ever trigger a wire transfer by itself (requires real aggregation)';

-- FIXME: check if we can ALWAYS include the shard in the WHERE clauses,
-- thereby resulting in a much better use of the index: we could do (shard,deposit_serial_id)!
CREATE INDEX IF NOT EXISTS deposits_deposit_by_serial_id_index
  ON deposits
  (deposit_serial_id);
CREATE INDEX IF NOT EXISTS deposits_for_get_ready_index
  ON deposits
  (shard ASC
  ,done
  ,extension_blocked
  ,tiny
  ,wire_deadline ASC
  );
COMMENT ON INDEX deposits_for_get_ready_index
  IS 'for deposits_get_ready';
-- FIXME: check if we can ALWAYS include the shard in the WHERE clauses,
-- thereby resulting in a much better use of the index: we could do (shard,merchant_pub, ...)!
CREATE INDEX IF NOT EXISTS deposits_for_iterate_matching_index
  ON deposits
  (merchant_pub
  ,wire_target_serial_id
  ,done
  ,extension_blocked
  ,refund_deadline ASC
  );
COMMENT ON INDEX deposits_for_iterate_matching_index
  IS 'for deposits_iterate_matching';


CREATE TABLE IF NOT EXISTS refunds
  (refund_serial_id BIGSERIAL -- UNIQUE
  ,deposit_serial_id INT8 NOT NULL -- REFERENCES deposits (deposit_serial_id) ON DELETE CASCADE
  ,merchant_sig BYTEA NOT NULL CHECK(LENGTH(merchant_sig)=64)
  ,rtransaction_id INT8 NOT NULL
  ,amount_with_fee_val INT8 NOT NULL
  ,amount_with_fee_frac INT4 NOT NULL
  -- ,PRIMARY KEY (deposit_serial_id, rtransaction_id) -- done per shard!
  )
  PARTITION BY HASH (deposit_serial_id);
COMMENT ON TABLE refunds
  IS 'Data on coins that were refunded. Technically, refunds always apply against specific deposit operations involving a coin. The combination of coin_pub, merchant_pub, h_contract_terms and rtransaction_id MUST be unique, and we usually select by coin_pub so that one goes first.';
COMMENT ON COLUMN refunds.deposit_serial_id
  IS 'Identifies ONLY the merchant_pub, h_contract_terms and known_coin_id. Multiple deposits may match a refund, this only identifies one of them.';
COMMENT ON COLUMN refunds.rtransaction_id
  IS 'used by the merchant to make refunds unique in case the same coin for the same deposit gets a subsequent (higher) refund';
CREATE TABLE IF NOT EXISTS refunds_default
  PARTITION OF refunds
  FOR VALUES WITH (MODULUS 1, REMAINDER 0);
ALTER TABLE refunds_default
  ADD PRIMARY KEY (deposit_serial_id, rtransaction_id);

CREATE INDEX IF NOT EXISTS refunds_by_refund_serial_id_index
  ON refunds
  (refund_serial_id);


CREATE TABLE IF NOT EXISTS wire_out
  (wireout_uuid BIGSERIAL -- PRIMARY KEY
  ,execution_date INT8 NOT NULL
  ,wtid_raw BYTEA UNIQUE NOT NULL CHECK (LENGTH(wtid_raw)=32)
  ,wire_target_serial_id INT8 NOT NULL -- REFERENCES wire_targets (wire_target_serial_id)
  ,exchange_account_section TEXT NOT NULL
  ,amount_val INT8 NOT NULL
  ,amount_frac INT4 NOT NULL
  )
  PARTITION BY HASH (wtid_raw);
COMMENT ON TABLE wire_out
  IS 'wire transfers the exchange has executed';
COMMENT ON COLUMN wire_out.exchange_account_section
  IS 'identifies the configuration section with the debit account of this payment';
COMMENT ON COLUMN wire_out.wire_target_serial_id
  IS 'Identifies the credited bank account and KYC status';
CREATE TABLE IF NOT EXISTS wire_out_default
  PARTITION OF wire_out
  FOR VALUES WITH (MODULUS 1, REMAINDER 0);

CREATE INDEX IF NOT EXISTS wire_out_by_wireout_uuid_index
  ON wire_out
  (wireout_uuid);
CREATE INDEX IF NOT EXISTS wire_out_by_wire_target_serial_id_index
  ON wire_out
  (wire_target_serial_id);



CREATE TABLE IF NOT EXISTS aggregation_tracking
  (aggregation_serial_id BIGSERIAL -- UNIQUE
  ,deposit_serial_id INT8 PRIMARY KEY -- REFERENCES deposits (deposit_serial_id) ON DELETE CASCADE
  ,wtid_raw BYTEA CONSTRAINT wire_out_ref REFERENCES wire_out(wtid_raw) ON DELETE CASCADE DEFERRABLE
  )
  PARTITION BY HASH (deposit_serial_id);
COMMENT ON TABLE aggregation_tracking
  IS 'mapping from wire transfer identifiers (WTID) to deposits (and back)';
COMMENT ON COLUMN aggregation_tracking.wtid_raw
  IS 'We first create entries in the aggregation_tracking table and then finally the wire_out entry once we know the total amount. Hence the constraint must be deferrable and we cannot use a wireout_uuid here, because we do not have it when these rows are created. Changing the logic to first INSERT a dummy row into wire_out and then UPDATEing that row in the same transaction would theoretically reduce per-deposit storage costs by 5 percent (24/~460 bytes).';
CREATE TABLE IF NOT EXISTS aggregation_tracking_default
  PARTITION OF aggregation_tracking
  FOR VALUES WITH (MODULUS 1, REMAINDER 0);

CREATE INDEX IF NOT EXISTS aggregation_tracking_by_aggregation_serial_id_index
  ON aggregation_tracking
  (aggregation_serial_id);
CREATE INDEX IF NOT EXISTS aggregation_tracking_by_wtid_raw_index
  ON aggregation_tracking
  (wtid_raw);
COMMENT ON INDEX aggregation_tracking_by_wtid_raw_index
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

CREATE INDEX IF NOT EXISTS wire_fee_by_end_date_index
  ON wire_fee
  (end_date);


CREATE TABLE IF NOT EXISTS recoup
  (recoup_uuid BIGSERIAL -- UNIQUE
  ,known_coin_id INT8 NOT NULL -- REFERENCES known_coins (known_coin_id)
  ,coin_sig BYTEA NOT NULL CHECK(LENGTH(coin_sig)=64)
  ,coin_blind BYTEA NOT NULL CHECK(LENGTH(coin_blind)=32)
  ,amount_val INT8 NOT NULL
  ,amount_frac INT4 NOT NULL
  ,recoup_timestamp INT8 NOT NULL
  ,reserve_out_serial_id INT8 NOT NULL -- REFERENCES reserves_out (reserve_out_serial_id) ON DELETE CASCADE
  )
  PARTITION BY RANGE (known_coin_id);
COMMENT ON TABLE recoup
  IS 'Information about recoups that were executed between a coin and a reserve. In this type of recoup, the amount is credited back to the reserve from which the coin originated.';
COMMENT ON COLUMN recoup.known_coin_id
  IS 'Coin that is being debited in the recoup. Do not CASCADE ON DROP on the coin_pub, as we may keep the coin alive!';
COMMENT ON COLUMN recoup.reserve_out_serial_id
  IS 'Identifies the h_blind_ev of the recouped coin and provides the link to the credited reserve.';
COMMENT ON COLUMN recoup.coin_sig
  IS 'Signature by the coin affirming the recoup, of type TALER_SIGNATURE_WALLET_COIN_RECOUP';
COMMENT ON COLUMN recoup.coin_blind
  IS 'Denomination blinding key used when creating the blinded coin from the planchet. Secret revealed during the recoup to provide the linkage between the coin and the withdraw operation.';
CREATE TABLE IF NOT EXISTS recoup_default
  PARTITION OF recoup
  DEFAULT;

CREATE INDEX IF NOT EXISTS recoup_by_recoup_uuid_index
  ON recoup
  (recoup_uuid);
CREATE INDEX IF NOT EXISTS recoup_by_reserve_out_serial_id_index
  ON recoup
  (reserve_out_serial_id);
CREATE INDEX IF NOT EXISTS recoup_by_known_coin_id_index
  ON recoup
  (known_coin_id);


CREATE TABLE IF NOT EXISTS recoup_refresh
  (recoup_refresh_uuid BIGSERIAL -- UNIQUE
  ,known_coin_id INT8 NOT NULL -- REFERENCES known_coins (known_coin_id)
  ,coin_sig BYTEA NOT NULL CHECK(LENGTH(coin_sig)=64)
  ,coin_blind BYTEA NOT NULL CHECK(LENGTH(coin_blind)=32)
  ,amount_val INT8 NOT NULL
  ,amount_frac INT4 NOT NULL
  ,recoup_timestamp INT8 NOT NULL
  ,rrc_serial INT8 NOT NULL -- REFERENCES refresh_revealed_coins (rrc_serial) ON DELETE CASCADE -- UNIQUE
  )
  PARTITION BY RANGE (known_coin_id);
COMMENT ON TABLE recoup_refresh
  IS 'Table of coins that originated from a refresh operation and that were recouped. Links the (fresh) coin to the melted operation (and thus the old coin). A recoup on a refreshed coin credits the old coin and debits the fresh coin.';
COMMENT ON COLUMN recoup_refresh.known_coin_id
  IS 'Refreshed coin of a revoked denomination where the residual value is credited to the old coin. Do not CASCADE ON DROP on the known_coin_id, as we may keep the coin alive!';
COMMENT ON COLUMN recoup_refresh.rrc_serial
  IS 'Link to the refresh operation. Also identifies the h_blind_ev of the recouped coin (as h_coin_ev).';
COMMENT ON COLUMN recoup_refresh.coin_blind
  IS 'Denomination blinding key used when creating the blinded coin from the planchet. Secret revealed during the recoup to provide the linkage between the coin and the refresh operation.';
CREATE TABLE IF NOT EXISTS recoup_refresh_default
  PARTITION OF recoup_refresh
  DEFAULT;

CREATE INDEX IF NOT EXISTS recoup_refresh_by_recoup_refresh_uuid_index
  ON recoup_refresh
  (recoup_refresh_uuid);
CREATE INDEX IF NOT EXISTS recoup_refresh_by_rrc_serial_index
  ON recoup_refresh
  (rrc_serial);
CREATE INDEX IF NOT EXISTS recoup_refresh_by_known_coin_id_index
  ON recoup_refresh
  (known_coin_id);


CREATE TABLE IF NOT EXISTS prewire
  (prewire_uuid BIGSERIAL PRIMARY KEY
  ,wire_method TEXT NOT NULL
  ,finished BOOLEAN NOT NULL DEFAULT false
  ,failed BOOLEAN NOT NULL DEFAULT false
  ,buf BYTEA NOT NULL
  )
  PARTITION BY RANGE (prewire_uuid);
COMMENT ON TABLE prewire
  IS 'pre-commit data for wire transfers we are about to execute';
COMMENT ON COLUMN prewire.failed
  IS 'set to TRUE if the bank responded with a non-transient failure to our transfer request';
COMMENT ON COLUMN prewire.finished
  IS 'set to TRUE once bank confirmed receiving the wire transfer request';
COMMENT ON COLUMN prewire.buf
  IS 'serialized data to send to the bank to execute the wire transfer';
CREATE TABLE IF NOT EXISTS prewire_default
  PARTITION OF prewire
  DEFAULT;

CREATE INDEX IF NOT EXISTS prewire_by_finished_index
  ON prewire
  (finished);
COMMENT ON INDEX prewire_by_finished_index
  IS 'for gc_prewire';
-- FIXME: find a way to combine these two indices?
CREATE INDEX IF NOT EXISTS prewire_by_failed_finished_index
  ON prewire
  (failed,finished);
COMMENT ON INDEX prewire_by_failed_finished_index
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

CREATE INDEX IF NOT EXISTS work_shards_by_job_name_completed_last_attempt_index
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

CREATE INDEX IF NOT EXISTS revolving_work_shards_by_job_name_active_last_attempt_index
  ON revolving_work_shards
  (job_name
  ,active
  ,last_attempt
  );


-- Stored procedures


CREATE OR REPLACE FUNCTION exchange_do_withdraw(
  IN amount_val INT8,
  IN amount_frac INT4,
  IN h_denom_pub BYTEA,
  IN rpub BYTEA,
  IN reserve_sig BYTEA,
  IN h_coin_envelope BYTEA,
  IN denom_sig BYTEA,
  IN now INT8,
  IN min_reserve_gc INT8,
  OUT reserve_found BOOLEAN,
  OUT balance_ok BOOLEAN,
  OUT kycok BOOLEAN,
  OUT account_uuid INT8,
  OUT ruuid INT8)
LANGUAGE plpgsql
AS $$
DECLARE
  reserve_gc INT8;
DECLARE
  denom_serial INT8;
DECLARE
  reserve_val INT8;
DECLARE
  reserve_frac INT4;
BEGIN
-- Shards: reserves by reserve_pub (SELECT)
--         reserves_out (INSERT, with CONFLICT detection) by h_blind_ev
--         reserves by reserve_pub (UPDATE)
--         reserves_in by reserve_pub (SELECT)
--         wire_targets by wire_target_serial_id

SELECT denominations_serial INTO denom_serial
  FROM denominations
 WHERE denom_pub_hash=h_denom_pub;

IF NOT FOUND
THEN
  -- denomination unknown, should be impossible!
  reserve_found=FALSE;
  balance_ok=FALSE;
  kycok=FALSE;
  account_uuid=0;
  ruuid=0;
  ASSERT false, 'denomination unknown';
  RETURN;
END IF;

SELECT
   current_balance_val
  ,current_balance_frac
  ,gc_date
  ,reserve_uuid
 INTO
   reserve_val
  ,reserve_frac
  ,reserve_gc
  ,ruuid
  FROM reserves
 WHERE reserves.reserve_pub=rpub;

IF NOT FOUND
THEN
  -- reserve unknown
  reserve_found=FALSE;
  balance_ok=FALSE;
  kycok=FALSE;
  account_uuid=0;
  ruuid=0;
  RETURN;
END IF;

-- We optimistically insert, and then on conflict declare
-- the query successful due to idempotency.
INSERT INTO reserves_out
  (h_blind_ev
  ,denominations_serial
  ,denom_sig
  ,reserve_uuid
  ,reserve_sig
  ,execution_date
  ,amount_with_fee_val
  ,amount_with_fee_frac)
VALUES
  (h_coin_envelope
  ,denom_serial
  ,denom_sig
  ,ruuid
  ,reserve_sig
  ,now
  ,amount_val
  ,amount_frac)
ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- idempotent query, all constraints must be satisfied
  reserve_found=TRUE;
  balance_ok=TRUE;
  kycok=TRUE;
  account_uuid=0;
  RETURN;
END IF;

-- Check reserve balance is sufficient.
IF (reserve_val > amount_val)
THEN
  IF (reserve_frac > amount_frac)
  THEN
    reserve_val=reserve_val - amount_val;
    reserve_frac=reserve_frac - amount_frac;
  ELSE
    reserve_val=reserve_val - amount_val - 1;
    reserve_frac=reserve_frac + 100000000 - amount_frac;
  END IF;
ELSE
  IF (reserve_val = amount_val) AND (reserve_frac >= amount_frac)
  THEN
    reserve_val=0;
    reserve_frac=reserve_frac - amount_frac;
  ELSE
    reserve_found=TRUE;
    balance_ok=FALSE;
    kycok=FALSE; -- we do not really know or care
    account_uuid=0;
    RETURN;
  END IF;
END IF;

-- Calculate new expiration dates.
min_reserve_gc=GREATEST(min_reserve_gc,reserve_gc);

-- Update reserve balance.
UPDATE reserves SET
  gc_date=min_reserve_gc
 ,current_balance_val=reserve_val
 ,current_balance_frac=reserve_frac
WHERE
  reserves.reserve_pub=rpub;

reserve_found=TRUE;
balance_ok=TRUE;

-- Obtain KYC status based on the last wire transfer into
-- this reserve. FIXME: likely not adequate for reserves that got P2P transfers!
SELECT
   kyc_ok
  ,wire_source_serial_id
  INTO
   kycok
  ,account_uuid
  FROM reserves_in
  JOIN wire_targets ON (wire_source_serial_id = wire_target_serial_id)
 WHERE reserve_pub=rpub
 LIMIT 1; -- limit 1 should not be required (without p2p transfers)

END $$;

COMMENT ON FUNCTION exchange_do_withdraw(INT8, INT4, BYTEA, BYTEA, BYTEA, BYTEA, BYTEA, INT8, INT8)
  IS 'Checks whether the reserve has sufficient balance for a withdraw operation (or the request is repeated and was previously approved) and if so updates the database with the result';



CREATE OR REPLACE FUNCTION exchange_do_withdraw_limit_check(
  IN ruuid INT8,
  IN start_time INT8,
  IN upper_limit_val INT8,
  IN upper_limit_frac INT4,
  OUT below_limit BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
  total_val INT8;
DECLARE
  total_frac INT8; -- INT4 could overflow during accumulation!
BEGIN
-- NOTE: Read-only, but crosses shards.
-- Shards: reserves by reserve_pub
--         reserves_out by reserve_uuid -- crosses shards!!


SELECT
   SUM(amount_with_fee_val) -- overflow here is not plausible
  ,SUM(CAST(amount_with_fee_frac AS INT8)) -- compute using 64 bits
  INTO
   total_val
  ,total_frac
  FROM reserves_out
 WHERE reserve_uuid=ruuid
   AND execution_date > start_time;

-- normalize result
total_val = total_val + total_frac / 100000000;
total_frac = total_frac % 100000000;

-- compare to threshold
below_limit = (total_val < upper_limit_val) OR
            ( (total_val = upper_limit_val) AND
              (total_frac <= upper_limit_frac) );
END $$;

COMMENT ON FUNCTION exchange_do_withdraw_limit_check(INT8, INT8, INT8, INT4)
  IS 'Check whether the withdrawals from the given reserve since the given time are below the given threshold';




CREATE OR REPLACE FUNCTION exchange_do_deposit(
  IN in_amount_with_fee_val INT8,
  IN in_amount_with_fee_frac INT4,
  IN in_h_contract_terms BYTEA,
  IN in_wire_salt BYTEA,
  IN in_wallet_timestamp INT8,
  IN in_exchange_timestamp INT8,
  IN in_refund_deadline INT8,
  IN in_wire_deadline INT8,
  IN in_merchant_pub BYTEA,
  IN in_receiver_wire_account VARCHAR,
  IN in_h_payto BYTEA,
  IN in_known_coin_id INT8,
  IN in_coin_pub BYTEA,
  IN in_coin_sig BYTEA,
  IN in_shard INT8,
  IN in_extension_blocked BOOLEAN,
  IN in_extension_details VARCHAR,
  OUT out_exchange_timestamp INT8,
  OUT out_balance_ok BOOLEAN,
  OUT out_conflict BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
  wtsi INT8; -- wire target serial id
DECLARE
  xdi INT8; -- eXstension details serial id
BEGIN
-- Shards: INSERT extension_details (by extension_details_serial_id)
--         INSERT wire_targets (by h_payto), on CONFLICT DO NOTHING;
--         INSERT deposits (by shard + known_coin_id, merchant_pub, h_contract_terms), ON CONFLICT DO NOTHING;
--         UPDATE known_coins (by coin_pub)

IF NOT NULL in_extension_details
THEN
  INSERT INTO extension_details
  (extension_options)
  VALUES
    (in_extension_details)
  RETURNING extension_details_serial_id INTO xdi;
ELSE
  xdi=NULL;
END IF;


INSERT INTO wire_targets
  (h_payto
  ,payto_uri)
  VALUES
  (in_h_payto
  ,in_receiver_wire_account)
ON CONFLICT (h_payto) DO NOTHING
  RETURNING wire_target_serial_id INTO wtsi;

IF NOT FOUND
THEN
  SELECT wire_target_serial_id
  INTO wtsi
  FROM wire_targets
  WHERE h_payto=in_h_payto;
END IF;


INSERT INTO deposits
  (shard
  ,known_coin_id
  ,amount_with_fee_val
  ,amount_with_fee_frac
  ,wallet_timestamp
  ,exchange_timestamp
  ,refund_deadline
  ,wire_deadline
  ,merchant_pub
  ,h_contract_terms
  ,coin_sig
  ,wire_salt
  ,wire_target_serial_id
  ,extension_blocked
  ,extension_details_serial_id
  )
  VALUES
  (in_shard
  ,in_known_coin_id
  ,in_amount_with_fee_val
  ,in_amount_with_fee_frac
  ,in_wallet_timestamp
  ,in_exchange_timestamp
  ,in_refund_deadline
  ,in_wire_deadline
  ,in_merchant_pub
  ,in_h_contract_terms
  ,in_coin_sig
  ,in_wire_salt
  ,wtsi
  ,in_extension_blocked
  ,xdi)
  ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- Idempotency check: see if an identical record exists.
  -- Note that by checking 'coin_sig', we implicitly check
  -- identity over everything that the signature covers.
  -- We do select over merchant_pub and h_contract_terms
  -- primarily here to maximally use the existing index.
  SELECT
     exchange_timestamp
   INTO
     out_exchange_timestamp
   FROM deposits
   WHERE
     shard=in_shard AND
     known_coin_id=in_known_coin_id AND
     merchant_pub=in_merchant_pub AND
     h_contract_terms=in_h_contract_terms AND
     coin_sig=in_coin_sig;

  IF NOT FOUND
  THEN
    -- Deposit exists, but with differences. Not allowed.
    out_balance_ok=FALSE;
    out_conflict=TRUE;
    RETURN;
  END IF;

  -- Idempotent request known, return success.
  out_balance_ok=TRUE;
  out_conflict=FALSE;

  RETURN;
END IF;


out_exchange_timestamp=in_exchange_timestamp;

-- Check and update balance of the coin.
UPDATE known_coins
  SET
    remaining_frac=remaining_frac-in_amount_with_fee_frac
       + CASE
         WHEN remaining_frac < in_amount_with_fee_frac
         THEN 100000000
         ELSE 0
         END,
    remaining_val=remaining_val-in_amount_with_fee_val
       - CASE
         WHEN remaining_frac < in_amount_with_fee_frac
         THEN 1
         ELSE 0
         END
  WHERE coin_pub=in_coin_pub
    AND ( (remaining_val > in_amount_with_fee_val) OR
          ( (remaining_frac >= in_amount_with_fee_frac) AND
            (remaining_val >= in_amount_with_fee_val) ) );

IF NOT FOUND
THEN
  -- Insufficient balance.
  out_balance_ok=FALSE;
  out_conflict=FALSE;
  RETURN;
END IF;

-- Everything fine, return success!
out_balance_ok=TRUE;
out_conflict=FALSE;

END $$;



CREATE OR REPLACE FUNCTION exchange_do_melt(
  IN in_amount_with_fee_val INT8,
  IN in_amount_with_fee_frac INT4,
  IN in_rc BYTEA,
  IN in_old_coin_pub BYTEA,
  IN in_old_coin_sig BYTEA,
  IN in_known_coin_id INT8, -- not used, but that's OK
  IN in_noreveal_index INT4,
  IN in_zombie_required BOOLEAN,
  OUT out_balance_ok BOOLEAN,
  OUT out_zombie_bad BOOLEAN,
  OUT out_noreveal_index INT4)
LANGUAGE plpgsql
AS $$
BEGIN
-- Shards: INSERT refresh_commitments (by rc)
-- (rare:) SELECT refresh_commitments (by old_coin_pub) -- crosses shards!
-- (rare:) SEELCT refresh_revealed_coins (by melt_serial_id)
-- (rare:) PERFORM recoup_refresh (by rrc_serial) -- crosses shards!
--         UPDATE known_coins (by coin_pub)

INSERT INTO refresh_commitments
  (rc
  ,old_coin_pub
  ,old_coin_sig
  ,amount_with_fee_val
  ,amount_with_fee_frac
  ,noreveal_index
  )
  VALUES
  (in_rc
  ,in_old_coin_pub
  ,in_old_coin_sig
  ,in_amount_with_fee_val
  ,in_amount_with_fee_frac
  ,in_noreveal_index)
  ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- Idempotency check: see if an identical record exists.
  out_noreveal_index=-1;
  SELECT
     noreveal_index
    INTO
     out_noreveal_index
    FROM refresh_commitments
   WHERE rc=in_rc;
  out_balance_ok=FOUND;
  out_zombie_bad=FALSE; -- zombie is OK
  RETURN;
END IF;


IF in_zombie_required
THEN
  -- Check if this coin was part of a refresh
  -- operation that was subsequently involved
  -- in a recoup operation.  We begin by all
  -- refresh operations our coin was involved
  -- with, then find all associated reveal
  -- operations, and then see if any of these
  -- reveal operations was involved in a recoup.
  PERFORM
    FROM recoup_refresh
   WHERE rrc_serial IN
    (SELECT rrc_serial
       FROM refresh_revealed_coins
      WHERE melt_serial_id IN
      (SELECT melt_serial_id
         FROM refresh_commitments
        WHERE old_coin_pub=in_old_coin_pub));
  IF NOT FOUND
  THEN
    out_zombie_bad=TRUE;
    out_balance_ok=FALSE;
    RETURN;
  END IF;
END IF;

out_zombie_bad=FALSE; -- zombie is OK


-- Check and update balance of the coin.
UPDATE known_coins
  SET
    remaining_frac=remaining_frac-in_amount_with_fee_frac
       + CASE
         WHEN remaining_frac < in_amount_with_fee_frac
         THEN 100000000
         ELSE 0
         END,
    remaining_val=remaining_val-in_amount_with_fee_val
       - CASE
         WHEN remaining_frac < in_amount_with_fee_frac
         THEN 1
         ELSE 0
         END
  WHERE coin_pub=in_old_coin_pub
    AND ( (remaining_val > in_amount_with_fee_val) OR
          ( (remaining_frac >= in_amount_with_fee_frac) AND
            (remaining_val >= in_amount_with_fee_val) ) );

IF NOT FOUND
THEN
  -- Insufficient balance.
  out_noreveal_index=-1;
  out_balance_ok=FALSE;
  RETURN;
END IF;

-- Everything fine, return success!
out_balance_ok=TRUE;
out_noreveal_index=in_noreveal_index;

END $$;



CREATE OR REPLACE FUNCTION exchange_do_refund(
  IN in_amount_with_fee_val INT8,
  IN in_amount_with_fee_frac INT4,
  IN in_amount_val INT8,
  IN in_amount_frac INT4,
  IN in_deposit_fee_val INT8,
  IN in_deposit_fee_frac INT4,
  IN in_h_contract_terms BYTEA,
  IN in_rtransaction_id INT8,
  IN in_deposit_shard INT8,
  IN in_known_coin_id INT8,
  IN in_coin_pub BYTEA,
  IN in_merchant_pub BYTEA,
  IN in_merchant_sig BYTEA,
  OUT out_not_found BOOLEAN,
  OUT out_refund_ok BOOLEAN,
  OUT out_gone BOOLEAN,
  OUT out_conflict BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
  dsi INT8; -- ID of deposit being refunded
DECLARE
  tmp_val INT8; -- total amount refunded
DECLARE
  tmp_frac INT8; -- total amount refunded
DECLARE
  deposit_val INT8; -- amount that was originally deposited
DECLARE
  deposit_frac INT8; -- amount that was originally deposited
BEGIN
-- Shards: SELECT deposits (by shard, known_coin_id,h_contract_terms, merchant_pub)
--         INSERT refunds (by deposit_serial_id, rtransaction_id) ON CONFLICT DO NOTHING
--         SELECT refunds (by deposit_serial_id)
--         UPDATE known_coins (by coin_pub)

SELECT
   deposit_serial_id
  ,amount_with_fee_val
  ,amount_with_fee_frac
  ,done
INTO
   dsi
  ,deposit_val
  ,deposit_frac
  ,out_gone
FROM deposits
WHERE shard=in_deposit_shard
  AND known_coin_id=in_known_coin_id
  AND h_contract_terms=in_h_contract_terms
  AND merchant_pub=in_merchant_pub;

IF NOT FOUND
THEN
  -- No matching deposit found!
  out_refund_ok=FALSE;
  out_conflict=FALSE;
  out_not_found=TRUE;
  out_gone=FALSE;
  RETURN;
END IF;


INSERT INTO refunds
  (deposit_serial_id
  ,merchant_sig
  ,rtransaction_id
  ,amount_with_fee_val
  ,amount_with_fee_frac
  )
  VALUES
  (dsi
  ,in_merchant_sig
  ,in_rtransaction_id
  ,in_amount_with_fee_val
  ,in_amount_with_fee_frac)
  ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- Idempotency check: see if an identical record exists.
  -- Note that by checking 'coin_sig', we implicitly check
  -- identity over everything that the signature covers.
  -- We do select over merchant_pub and h_contract_terms
  -- primarily here to maximally use the existing index.
   PERFORM
   FROM refunds
   WHERE
     deposit_serial_id=dsi AND
     rtransaction_id=in_rtransaction_id AND
     amount_with_fee_val=in_amount_with_fee_val AND
     amount_with_fee_frac=in_amount_with_fee_frac;

  IF NOT FOUND
  THEN
    -- Deposit exists, but have conflicting refund.
    out_refund_ok=FALSE;
    out_conflict=TRUE;
    out_not_found=FALSE;
    RETURN;
  END IF;

  -- Idempotent request known, return success.
  out_refund_ok=TRUE;
  out_conflict=FALSE;
  out_not_found=FALSE;
  out_gone=FALSE;
  RETURN;
END IF;


IF out_gone
THEN
  -- money already sent to the merchant. Tough luck.
  out_refund_ok=FALSE;
  out_conflict=FALSE;
  out_not_found=FALSE;
  RETURN;
END IF;



-- Check refund balance invariant.
SELECT
   SUM(amount_with_fee_val) -- overflow here is not plausible
  ,SUM(CAST(amount_with_fee_frac AS INT8)) -- compute using 64 bits
  INTO
   tmp_val
  ,tmp_frac
  FROM refunds
  WHERE
    deposit_serial_id=dsi;
IF tmp_val IS NULL
THEN
  RAISE NOTICE 'failed to sum up existing refunds';
  out_refund_ok=FALSE;
  out_conflict=FALSE;
  out_not_found=FALSE;
  RETURN;
END IF;

-- Normalize result before continuing
tmp_val = tmp_val + tmp_frac / 100000000;
tmp_frac = tmp_frac % 100000000;

-- Actually check if the deposits are sufficient for the refund. Verbosely. ;-)
IF (tmp_val < deposit_val)
THEN
  out_refund_ok=TRUE;
ELSE
  IF (tmp_val = deposit_val) AND (tmp_frac <= deposit_frac)
  THEN
    out_refund_ok=TRUE;
  ELSE
    out_refund_ok=FALSE;
  END IF;
END IF;

IF (tmp_val = deposit_val) AND (tmp_frac = deposit_frac)
THEN
  -- Refunds have reached the full value of the original
  -- deposit. Also refund the deposit fee.
  in_amount_frac = in_amount_frac + in_deposit_fee_frac;
  in_amount_val = in_amount_val + in_deposit_fee_val;

  -- Normalize result before continuing
  in_amount_val = in_amount_val + in_amount_frac / 100000000;
  in_amount_frac = in_amount_frac % 100000000;
END IF;

-- Update balance of the coin.
UPDATE known_coins
  SET
    remaining_frac=remaining_frac+in_amount_frac
       - CASE
         WHEN remaining_frac+in_amount_frac >= 100000000
         THEN 100000000
         ELSE 0
         END,
    remaining_val=remaining_val+in_amount_val
       + CASE
         WHEN remaining_frac+in_amount_frac >= 100000000
         THEN 1
         ELSE 0
         END
  WHERE coin_pub=in_coin_pub;


out_conflict=FALSE;
out_not_found=FALSE;

END $$;

-- COMMENT ON FUNCTION exchange_do_refund(INT8, INT4, BYTEA, BOOLEAN, BOOLEAN)
--  IS 'Executes a refund operation, checking that the corresponding deposit was sufficient to cover the refunded amount';


CREATE OR REPLACE FUNCTION exchange_do_recoup_to_reserve(
  IN in_reserve_pub BYTEA,
  IN in_reserve_out_serial_id INT8,
  IN in_amount_val INT8,
  IN in_amount_frac INT4,
  IN in_coin_blind BYTEA,
  IN in_coin_pub BYTEA,
  IN in_known_coin_id INT8,
  IN in_coin_sig BYTEA,
  IN in_reserve_gc INT8,
  IN in_reserve_expiration INT8,
  IN in_recoup_timestamp INT8,
  OUT out_recoup_ok BOOLEAN,
  OUT out_internal_failure BOOLEAN,
  OUT out_recoup_timestamp INT8)
LANGUAGE plpgsql
AS $$
DECLARE
  tmp_val INT8; -- previous amount recouped
DECLARE
  tmp_frac INT8; -- previous amount recouped
BEGIN
-- Shards: SELECT known_coins (by coin_pub)
--         SELECT recoup (by known_coin_id)
--         UPDATE reserves (by reserve_pub)
--         INSERT recoup (by known_coin_id)

out_internal_failure=FALSE;

-- Check and update balance of the coin.
UPDATE known_coins
  SET
    remaining_frac=remaining_frac-in_amount_frac
       + CASE
         WHEN remaining_frac < in_amount_frac
         THEN 100000000
         ELSE 0
         END,
    remaining_val=remaining_val-in_amount_val
       - CASE
         WHEN remaining_frac < in_amount_frac
         THEN 1
         ELSE 0
         END
  WHERE coin_pub=in_coin_pub
    AND ( (remaining_val > in_amount_val) OR
          ( (remaining_frac >= in_amount_frac) AND
            (remaining_val >= in_amount_val) ) );

IF NOT FOUND
THEN
  -- Check if we already recouped this coin before!
  SELECT
       amount_val
      ,amount_frac
      ,recoup_timestamp
    INTO
       tmp_val
      ,tmp_frac
      ,out_recoup_timestamp
    FROM recoup
    WHERE known_coin_id=in_known_coin_id;

  IF FOUND
  THEN
    -- Idempotent request, all OK!
    out_recoup_ok= (tmp_val = in_amount_val) AND
                   (tmp_frac = in_amount_frac);
    RETURN;
  END IF;

  out_recoup_ok=FALSE;
  RETURN;
END IF;


-- Credit the reserve and update reserve timers.
UPDATE reserves
  SET
    current_balance_frac=current_balance_frac+in_amount_frac
       - CASE
         WHEN current_balance_frac+in_amount_frac >= 100000000
         THEN 100000000
         ELSE 0
         END,
    current_balance_val=current_balance_val+in_amount_val
       + CASE
         WHEN current_balance_frac+in_amount_frac >= 100000000
         THEN 1
         ELSE 0
         END,
    gc_date=GREATEST(gc_date, in_reserve_gc),
    expiration_date=GREATEST(expiration_date, in_reserve_expiration)
  WHERE reserve_pub=in_reserve_pub;


IF NOT FOUND
THEN
  RAISE NOTICE 'failed to increase reserve balance from recoup';
  out_recoup_ok=FALSE;
  out_internal_failure=TRUE;
  RETURN;
END IF;


INSERT INTO recoup
  (known_coin_id
  ,coin_sig
  ,coin_blind
  ,amount_val
  ,amount_frac
  ,recoup_timestamp
  ,reserve_out_serial_id
  )
VALUES
  (in_known_coin_id
  ,in_coin_sig
  ,in_coin_blind
  ,in_amount_val
  ,in_amount_frac
  ,in_recoup_timestamp
  ,in_reserve_out_serial_id);

-- Normal end, everything is fine.
out_recoup_ok=TRUE;
out_recoup_timestamp=in_recoup_timestamp;

END $$;

-- COMMENT ON FUNCTION exchange_do_recoup_to_reserve(INT8, INT4, BYTEA, BOOLEAN, BOOLEAN)
--  IS 'Executes a recoup of a coin that was withdrawn from a reserve';






CREATE OR REPLACE FUNCTION exchange_do_recoup_to_coin(
  IN in_old_coin_pub BYTEA,
  IN in_rrc_serial INT8,
  IN in_amount_val INT8,
  IN in_amount_frac INT4,
  IN in_coin_blind BYTEA,
  IN in_coin_pub BYTEA,
  IN in_known_coin_id INT8,
  IN in_coin_sig BYTEA,
  IN in_recoup_timestamp INT8,
  OUT out_recoup_ok BOOLEAN,
  OUT out_internal_failure BOOLEAN,
  OUT out_recoup_timestamp INT8)
LANGUAGE plpgsql
AS $$
DECLARE
  tmp_val INT8; -- previous amount recouped
DECLARE
  tmp_frac INT8; -- previous amount recouped
BEGIN

-- Shards: UPDATE known_coins (by coin_pub)
--         SELECT recoup_refresh (by known_coin_id)
--         UPDATE known_coins (by coin_pub)
--         INSERT recoup_refresh (by known_coin_id)


out_internal_failure=FALSE;

-- Check and update balance of the coin.
UPDATE known_coins
  SET
    remaining_frac=remaining_frac-in_amount_frac
       + CASE
         WHEN remaining_frac < in_amount_frac
         THEN 100000000
         ELSE 0
         END,
    remaining_val=remaining_val-in_amount_val
       - CASE
         WHEN remaining_frac < in_amount_frac
         THEN 1
         ELSE 0
         END
  WHERE coin_pub=in_coin_pub
    AND ( (remaining_val > in_amount_val) OR
          ( (remaining_frac >= in_amount_frac) AND
            (remaining_val >= in_amount_val) ) );

IF NOT FOUND
THEN
  -- Check if we already recouped this coin before!
  SELECT
       amount_val
      ,amount_frac
      ,recoup_timestamp
    INTO
       tmp_val
      ,tmp_frac
      ,out_recoup_timestamp
    FROM recoup_refresh
    WHERE known_coin_id=in_known_coin_id;

  IF FOUND
  THEN
    -- Idempotent request, all OK!
    out_recoup_ok= (tmp_val = in_amount_val) AND
                   (tmp_frac = in_amount_frac);
    RETURN;
  END IF;

  -- Insufficient balance, not idempotent.
  out_recoup_ok=FALSE;
  RETURN;
END IF;


-- Credit the old coin.
UPDATE known_coins
  SET
    remaining_frac=remaining_frac+in_amount_frac
       - CASE
         WHEN remaining_frac+in_amount_frac >= 100000000
         THEN 100000000
         ELSE 0
         END,
    remaining_val=remaining_val+in_amount_val
       + CASE
         WHEN remaining_frac+in_amount_frac >= 100000000
         THEN 1
         ELSE 0
         END
  WHERE coin_pub=in_old_coin_pub;


IF NOT FOUND
THEN
  RAISE NOTICE 'failed to increase old coin balance from recoup';
  out_recoup_ok=FALSE;
  out_internal_failure=TRUE;
  RETURN;
END IF;


INSERT INTO recoup_refresh
  (known_coin_id
  ,coin_sig
  ,coin_blind
  ,amount_val
  ,amount_frac
  ,recoup_timestamp
  ,rrc_serial
  )
VALUES
  (in_known_coin_id
  ,in_coin_sig
  ,in_coin_blind
  ,in_amount_val
  ,in_amount_frac
  ,in_recoup_timestamp
  ,in_rrc_serial);

-- Normal end, everything is fine.
out_recoup_ok=TRUE;
out_recoup_timestamp=in_recoup_timestamp;

END $$;


-- COMMENT ON FUNCTION exchange_do_recoup_to_coin(INT8, INT4, BYTEA, BOOLEAN, BOOLEAN)
--  IS 'Executes a recoup-refresh of a coin that was obtained from a refresh-reveal process';



CREATE OR REPLACE PROCEDURE exchange_do_gc(
  IN in_ancient_date INT8,
  IN in_now INT8)
LANGUAGE plpgsql
AS $$
DECLARE
  reserve_uuid_min INT8; -- minimum reserve UUID still alive
DECLARE
  melt_min INT8; -- minimum melt still alive
DECLARE
  coin_min INT8; -- minimum known_coin still alive
DECLARE
  deposit_min INT8; -- minimum deposit still alive
DECLARE
  reserve_out_min INT8; -- minimum reserve_out still alive
BEGIN

DELETE FROM prewire
  WHERE finished=TRUE;

DELETE FROM wire_fee
  WHERE end_date < in_ancient_date;

-- TODO: use closing fee as threshold?
DELETE FROM reserves
  WHERE gc_date < in_now
    AND current_balance_val = 0
    AND current_balance_frac = 0;

SELECT
     reserve_out_serial_id
  INTO
     reserve_out_min
  FROM reserves_out
  ORDER BY reserve_out_serial_id ASC
  LIMIT 1;

DELETE FROM recoup
  WHERE reserve_out_serial_id < reserve_out_min;


SELECT
     reserve_uuid
  INTO
     reserve_uuid_min
  FROM reserves
  ORDER BY reserve_uuid ASC
  LIMIT 1;

DELETE FROM reserves_out
  WHERE reserve_uuid < reserve_uuid_min;


DELETE FROM denominations
  WHERE expire_legal < in_now
    AND denominations_serial NOT IN
      (SELECT DISTINCT denominations_serial
         FROM reserves_out)
    AND denominations_serial NOT IN
      (SELECT DISTINCT denominations_serial
         FROM known_coins
        WHERE known_coin_id IN
          (SELECT DISTINCT known_coin_id
             FROM recoup))
    AND denominations_serial NOT IN
      (SELECT DISTINCT denominations_serial
         FROM known_coins
        WHERE known_coin_id IN
          (SELECT DISTINCT known_coin_id
             FROM recoup_refresh));

SELECT
     melt_serial_id
  INTO
     melt_min
  FROM refresh_commitments
  ORDER BY melt_serial_id ASC
  LIMIT 1;

DELETE FROM refresh_revealed_coins
  WHERE melt_serial_id < melt_min;

DELETE FROM refresh_transfer_keys
  WHERE melt_serial_id < melt_min;

SELECT
     known_coin_id
  INTO
     coin_min
  FROM known_coins
  ORDER BY known_coin_id ASC
  LIMIT 1;

DELETE FROM deposits
  WHERE known_coin_id < coin_min;

SELECT
     deposit_serial_id
  INTO
     deposit_min
  FROM deposits
  ORDER BY deposit_serial_id ASC
  LIMIT 1;

DELETE FROM refunds
  WHERE deposit_serial_id < deposit_min;

DELETE FROM aggregation_tracking
  WHERE deposit_serial_id < deposit_min;


END $$;


-- Complete transaction
COMMIT;
