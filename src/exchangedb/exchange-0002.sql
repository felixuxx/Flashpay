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


-- need serial IDs on various tables for exchange-auditor replication
ALTER TABLE denominations
  ADD COLUMN denominations_serial BIGSERIAL UNIQUE;
COMMENT ON COLUMN denominations.denominations_serial
  IS 'needed for exchange-auditor replication logic';
ALTER TABLE refresh_revealed_coins
  ADD COLUMN rrc_serial BIGSERIAL UNIQUE;
COMMENT ON COLUMN refresh_revealed_coins.rrc_serial
  IS 'needed for exchange-auditor replication logic';
ALTER TABLE refresh_transfer_keys
  ADD COLUMN rtc_serial BIGSERIAL UNIQUE;
COMMENT ON COLUMN refresh_transfer_keys.rtc_serial
  IS 'needed for exchange-auditor replication logic';
ALTER TABLE wire_fee
  ADD COLUMN wire_fee_serial BIGSERIAL UNIQUE;
COMMENT ON COLUMN wire_fee.wire_fee_serial
  IS 'needed for exchange-auditor replication logic';

-- for the reserves, we add the new reserve_uuid, and also
-- change the foreign keys to use the new BIGSERIAL instead
-- of the public key to reference the entry
ALTER TABLE reserves
  ADD COLUMN reserve_uuid BIGSERIAL UNIQUE;
ALTER TABLE reserves_in
  ADD COLUMN reserve_uuid INT8 REFERENCES reserves (reserve_uuid) ON DELETE CASCADE;
UPDATE reserves_in
  SET reserve_uuid=r.reserve_uuid
  FROM reserves_in rin
  INNER JOIN reserves r USING(reserve_pub);
ALTER TABLE reserves_in
  ALTER COLUMN reserve_uuid SET NOT NULL;
ALTER TABLE reserves_out
  ADD COLUMN reserve_uuid INT8 REFERENCES reserves (reserve_uuid) ON DELETE CASCADE;
UPDATE reserves_out
  SET reserve_uuid=r.reserve_uuid
  FROM reserves_out rout
  INNER JOIN reserves r USING(reserve_pub);
ALTER TABLE reserves_out
  ALTER COLUMN reserve_uuid SET NOT NULL;
ALTER TABLE reserves_close
  ADD COLUMN reserve_uuid INT8 REFERENCES reserves (reserve_uuid) ON DELETE CASCADE;
UPDATE reserves_close
  SET reserve_uuid=r.reserve_uuid
  FROM reserves_close rclose
  INNER JOIN reserves r USING(reserve_pub);
ALTER TABLE reserves_close
  ALTER COLUMN reserve_uuid SET NOT NULL;

ALTER TABLE reserves_in
  DROP COLUMN reserve_pub;
ALTER TABLE reserves_out
  DROP COLUMN reserve_pub;
ALTER TABLE reserves_close
  DROP COLUMN reserve_pub;


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
-- "auditors" has no BIGSERIAL because it is a 'mutable' table
--            and is of no concern to the auditor


CREATE TABLE IF NOT EXISTS auditor_denom_sigs
  (auditor_denom_serial BIGSERIAL UNIQUE
  ,auditor_pub BYTEA NOT NULL REFERENCES auditors (auditor_pub) ON DELETE CASCADE
  ,denom_pub_hash BYTEA NOT NULL REFERENCES denominations (denom_pub_hash) ON DELETE CASCADE
  ,auditor_sig BYTEA CHECK (LENGTH(auditor_sig)=64)
  ,PRIMARY KEY (denom_pub_hash, auditor_pub)
  );
COMMENT ON TABLE auditor_denom_sigs
  IS 'Table with auditor signatures on exchange denomination keys.';
COMMENT ON COLUMN auditor_denom_sigs.auditor_pub
  IS 'Public key of the auditor.';
COMMENT ON COLUMN auditor_denom_sigs.denom_pub_hash
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


CREATE TABLE IF NOT EXISTS signkey_revocations
  (signkey_revocations_serial_id BIGSERIAL UNIQUE
  ,exchange_pub BYTEA PRIMARY KEY REFERENCES exchange_sign_keys (exchange_pub) ON DELETE CASCADE
  ,master_sig BYTEA NOT NULL CHECK (LENGTH(master_sig)=64)
  );
COMMENT ON TABLE signkey_revocations
  IS 'remembering which online signing keys have been revoked';


-- Complete transaction
COMMIT;
