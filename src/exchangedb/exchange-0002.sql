--
-- This file is part of TALER
-- Copyright (C) 2020 Taler Systems SA
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
SELECT _v.register_patch('exchange-0002', NULL, NULL);

ALTER TABLE prewire
  ADD failed BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN prewire.failed
  IS 'set to TRUE if the bank responded with a non-transient failure to our transfer request';
COMMENT ON COLUMN prewire.finished
  IS 'set to TRUE once bank confirmed receiving the wire transfer request';
COMMENT ON COLUMN prewire.buf
  IS 'serialized data to send to the bank to execute the wire transfer';

-- change comment, existing index is still useful, but only for gc_prewire.
COMMENT ON INDEX prepare_iteration_index
  IS 'for gc_prewire';

-- need a new index for updated wire_prepare_data_get statement:
CREATE INDEX IF NOT EXISTS prepare_get_index
  ON prewire
  (failed,finished);
COMMENT ON INDEX prepare_get_index
  IS 'for wire_prepare_data_get';


CREATE TABLE IF NOT EXISTS future_denominations
  (denom_pub_hash BYTEA PRIMARY KEY CHECK (LENGTH(denom_pub_hash)=64)
  ,denom_pub BYTEA NOT NULL
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
COMMENT ON TABLE future_denominations
  IS 'Future denominations. Moved to denomiations once the master signature is provided. Kept separate (instead of using NULL-able master_sig column) to ensure denomination keys without master signature cannot satisfy foreign key constraints of other tables.';
COMMENT ON COLUMN future_denominations.valid_from
  IS 'Earliest time when the private key can be used to withdraw.';
COMMENT ON COLUMN future_denominations.expire_withdraw
  IS 'Latest time when the private key can be used to withdraw.';

CREATE INDEX IF NOT EXISTS future_denominations_expire_withdraw_index
  ON future_denominations
  (expire_withdraw);
COMMENT ON INDEX future_denominations_expire_withdraw_index
  IS 'Future denominations that cannot be withdrawn anymore can be deleted.';



CREATE TABLE IF NOT EXISTS auditors
  (auditor_pub BYTEA PRIMARY KEY CHECK (LENGTH(auditor_pub)=32)
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
  (auditor_pub BYTEA NOT NULL REFERENCES auditors (auditor_pub) ON DELETE CASCADE
  ,denom_pub_hash BYTEA NOT NULL REFERENCES denominations (denom_pub_hash) ON DELETE CASCADE
  ,auditor_sig BYTEA PRIMARY KEY CHECK (LENGTH(auditor_sig)=64)
  );
COMMENT ON TABLE auditor_denom_sigs
  IS 'Table with auditor signatures on exchange denomination keys.';
COMMENT ON COLUMN auditor_denom_sigs.auditor_pub
  IS 'Public key of the auditor.';
COMMENT ON COLUMN auditor_denom_sigs.denom_pub_hash
  IS 'Denomination the signature is for.';
COMMENT ON COLUMN auditor_denom_sigs.auditor_sig
  IS 'Signature of the auditor, of purpose TALER_SIGNATURE_AUDITOR_EXCHANGE_KEYS.';
CREATE INDEX IF NOT EXISTS auditor_denom_sigs_denom_hash_index
  ON auditor_denom_sigs
  (denom_pub_hash);


CREATE TABLE IF NOT EXISTS exchange_sign_keys
  (exchange_pub BYTEA PRIMARY KEY
  ,master_pub BYTEA NOT NULL CHECK (LENGTH(master_pub)=32)
  ,master_sig BYTEA NOT NULL CHECK (LENGTH(master_sig)=64)
  ,legal_end INT8 NOT NULL
  );
COMMENT ON TABLE exchange_sign_keys
  IS 'Table with master public key signatures on exchange online signing keys.';
COMMENT ON COLUMN exchange_sign_keys.exchange_pub
  IS 'Public online signing key of the exchange.';
COMMENT ON COLUMN exchange_sign_keys.master_pub
  IS 'Master public key of the exchange that was used for master_sig.';
COMMENT ON COLUMN exchange_sign_keys.master_sig
  IS 'Signature affirming the validity of the signing key of purpose TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY.';
COMMENT ON COLUMN exchange_sign_keys.legal_end
  IS 'Time when this online signing key legally expires.';


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


CREATE TABLE IF NOT EXISTS signkey_revocations
  (signkey_revocations_serial_id BIGSERIAL UNIQUE
  ,exchange_pub BYTEA PRIMARY KEY REFERENCES exchange_sign_keys (exchange_pub) ON DELETE CASCADE
  ,master_sig BYTEA NOT NULL CHECK (LENGTH(master_sig)=64)
  );
COMMENT ON TABLE signkey_revocations
  IS 'remembering which online signing keys have been revoked';


-- Complete transaction
COMMIT;
