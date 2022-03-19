--
-- PostgreSQL database dump
--

-- Dumped from database version 12.9 (Ubuntu 12.9-0ubuntu0.20.04.1)
-- Dumped by pg_dump version 12.9 (Ubuntu 12.9-0ubuntu0.20.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: _v; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA _v;


--
-- Name: SCHEMA _v; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA _v IS 'Schema for versioning data and functionality.';


--
-- Name: assert_patch_is_applied(text); Type: FUNCTION; Schema: _v; Owner: -
--

CREATE FUNCTION _v.assert_patch_is_applied(in_patch_name text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    t_text TEXT;
BEGIN
    SELECT patch_name INTO t_text FROM _v.patches WHERE patch_name = in_patch_name;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Patch % is not applied!', in_patch_name;
    END IF;
    RETURN format('Patch %s is applied.', in_patch_name);
END;
$$;


--
-- Name: FUNCTION assert_patch_is_applied(in_patch_name text); Type: COMMENT; Schema: _v; Owner: -
--

COMMENT ON FUNCTION _v.assert_patch_is_applied(in_patch_name text) IS 'Function that can be used to make sure that patch has been applied.';


--
-- Name: assert_user_is_not_superuser(); Type: FUNCTION; Schema: _v; Owner: -
--

CREATE FUNCTION _v.assert_user_is_not_superuser() RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_super bool;
BEGIN
    SELECT usesuper INTO v_super FROM pg_user WHERE usename = current_user;
    IF v_super THEN
        RAISE EXCEPTION 'Current user is superuser - cannot continue.';
    END IF;
    RETURN 'assert_user_is_not_superuser: OK';
END;
$$;


--
-- Name: FUNCTION assert_user_is_not_superuser(); Type: COMMENT; Schema: _v; Owner: -
--

COMMENT ON FUNCTION _v.assert_user_is_not_superuser() IS 'Function that can be used to make sure that patch is being applied using normal (not superuser) account.';


--
-- Name: assert_user_is_one_of(text[]); Type: FUNCTION; Schema: _v; Owner: -
--

CREATE FUNCTION _v.assert_user_is_one_of(VARIADIC p_acceptable_users text[]) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
    IF current_user = any( p_acceptable_users ) THEN
        RETURN 'assert_user_is_one_of: OK';
    END IF;
    RAISE EXCEPTION 'User is not one of: % - cannot continue.', p_acceptable_users;
END;
$$;


--
-- Name: FUNCTION assert_user_is_one_of(VARIADIC p_acceptable_users text[]); Type: COMMENT; Schema: _v; Owner: -
--

COMMENT ON FUNCTION _v.assert_user_is_one_of(VARIADIC p_acceptable_users text[]) IS 'Function that can be used to make sure that patch is being applied by one of defined users.';


--
-- Name: assert_user_is_superuser(); Type: FUNCTION; Schema: _v; Owner: -
--

CREATE FUNCTION _v.assert_user_is_superuser() RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_super bool;
BEGIN
    SELECT usesuper INTO v_super FROM pg_user WHERE usename = current_user;
    IF v_super THEN
        RETURN 'assert_user_is_superuser: OK';
    END IF;
    RAISE EXCEPTION 'Current user is not superuser - cannot continue.';
END;
$$;


--
-- Name: FUNCTION assert_user_is_superuser(); Type: COMMENT; Schema: _v; Owner: -
--

COMMENT ON FUNCTION _v.assert_user_is_superuser() IS 'Function that can be used to make sure that patch is being applied using superuser account.';


--
-- Name: register_patch(text); Type: FUNCTION; Schema: _v; Owner: -
--

CREATE FUNCTION _v.register_patch(text) RETURNS SETOF integer
    LANGUAGE sql
    AS $_$
    SELECT _v.register_patch( $1, NULL, NULL );
$_$;


--
-- Name: FUNCTION register_patch(text); Type: COMMENT; Schema: _v; Owner: -
--

COMMENT ON FUNCTION _v.register_patch(text) IS 'Wrapper to allow registration of patches without requirements and conflicts.';


--
-- Name: register_patch(text, text[]); Type: FUNCTION; Schema: _v; Owner: -
--

CREATE FUNCTION _v.register_patch(text, text[]) RETURNS SETOF integer
    LANGUAGE sql
    AS $_$
    SELECT _v.register_patch( $1, $2, NULL );
$_$;


--
-- Name: FUNCTION register_patch(text, text[]); Type: COMMENT; Schema: _v; Owner: -
--

COMMENT ON FUNCTION _v.register_patch(text, text[]) IS 'Wrapper to allow registration of patches without conflicts.';


--
-- Name: register_patch(text, text[], text[]); Type: FUNCTION; Schema: _v; Owner: -
--

CREATE FUNCTION _v.register_patch(in_patch_name text, in_requirements text[], in_conflicts text[], OUT versioning integer) RETURNS SETOF integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    t_text   TEXT;
    t_text_a TEXT[];
    i INT4;
BEGIN
    -- Thanks to this we know only one patch will be applied at a time
    LOCK TABLE _v.patches IN EXCLUSIVE MODE;

    SELECT patch_name INTO t_text FROM _v.patches WHERE patch_name = in_patch_name;
    IF FOUND THEN
        RAISE EXCEPTION 'Patch % is already applied!', in_patch_name;
    END IF;

    t_text_a := ARRAY( SELECT patch_name FROM _v.patches WHERE patch_name = any( in_conflicts ) );
    IF array_upper( t_text_a, 1 ) IS NOT NULL THEN
        RAISE EXCEPTION 'Versioning patches conflict. Conflicting patche(s) installed: %.', array_to_string( t_text_a, ', ' );
    END IF;

    IF array_upper( in_requirements, 1 ) IS NOT NULL THEN
        t_text_a := '{}';
        FOR i IN array_lower( in_requirements, 1 ) .. array_upper( in_requirements, 1 ) LOOP
            SELECT patch_name INTO t_text FROM _v.patches WHERE patch_name = in_requirements[i];
            IF NOT FOUND THEN
                t_text_a := t_text_a || in_requirements[i];
            END IF;
        END LOOP;
        IF array_upper( t_text_a, 1 ) IS NOT NULL THEN
            RAISE EXCEPTION 'Missing prerequisite(s): %.', array_to_string( t_text_a, ', ' );
        END IF;
    END IF;

    INSERT INTO _v.patches (patch_name, applied_tsz, applied_by, requires, conflicts ) VALUES ( in_patch_name, now(), current_user, coalesce( in_requirements, '{}' ), coalesce( in_conflicts, '{}' ) );
    RETURN;
END;
$$;


--
-- Name: FUNCTION register_patch(in_patch_name text, in_requirements text[], in_conflicts text[], OUT versioning integer); Type: COMMENT; Schema: _v; Owner: -
--

COMMENT ON FUNCTION _v.register_patch(in_patch_name text, in_requirements text[], in_conflicts text[], OUT versioning integer) IS 'Function to register patches in database. Raises exception if there are conflicts, prerequisites are not installed or the migration has already been installed.';


--
-- Name: unregister_patch(text); Type: FUNCTION; Schema: _v; Owner: -
--

CREATE FUNCTION _v.unregister_patch(in_patch_name text, OUT versioning integer) RETURNS SETOF integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    i        INT4;
    t_text_a TEXT[];
BEGIN
    -- Thanks to this we know only one patch will be applied at a time
    LOCK TABLE _v.patches IN EXCLUSIVE MODE;

    t_text_a := ARRAY( SELECT patch_name FROM _v.patches WHERE in_patch_name = ANY( requires ) );
    IF array_upper( t_text_a, 1 ) IS NOT NULL THEN
        RAISE EXCEPTION 'Cannot uninstall %, as it is required by: %.', in_patch_name, array_to_string( t_text_a, ', ' );
    END IF;

    DELETE FROM _v.patches WHERE patch_name = in_patch_name;
    GET DIAGNOSTICS i = ROW_COUNT;
    IF i < 1 THEN
        RAISE EXCEPTION 'Patch % is not installed, so it can''t be uninstalled!', in_patch_name;
    END IF;

    RETURN;
END;
$$;


--
-- Name: FUNCTION unregister_patch(in_patch_name text, OUT versioning integer); Type: COMMENT; Schema: _v; Owner: -
--

COMMENT ON FUNCTION _v.unregister_patch(in_patch_name text, OUT versioning integer) IS 'Function to unregister patches in database. Dies if the patch is not registered, or if unregistering it would break dependencies.';


--
-- Name: add_constraints_to_aggregation_tracking_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_aggregation_tracking_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE aggregation_tracking_' || partition_suffix || ' '
      'ADD CONSTRAINT aggregation_tracking_' || partition_suffix || '_aggregation_serial_id_key '
        'UNIQUE (aggregation_serial_id) '
  );
END
$$;


--
-- Name: add_constraints_to_cs_nonce_locks_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_cs_nonce_locks_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE cs_nonce_locks_' || partition_suffix || ' '
      'ADD CONSTRAINT cs_nonce_locks_' || partition_suffix || '_cs_nonce_lock_serial_id_key '
        'UNIQUE (cs_nonce_lock_serial_id)'
  );
END
$$;


--
-- Name: add_constraints_to_deposits_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_deposits_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE deposits_' || partition_suffix || ' '
      'ADD CONSTRAINT deposits_' || partition_suffix || '_deposit_serial_id_pkey '
        'PRIMARY KEY (deposit_serial_id)'
  );
END
$$;


--
-- Name: add_constraints_to_known_coins_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_known_coins_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE known_coins_' || partition_suffix || ' '
      'ADD CONSTRAINT known_coins_' || partition_suffix || 'k_nown_coin_id_key '
        'UNIQUE (known_coin_id)'
  );
END
$$;


--
-- Name: add_constraints_to_recoup_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_recoup_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE recoup_' || partition_suffix || ' '
      'ADD CONSTRAINT recoup_' || partition_suffix || '_recoup_uuid_key '
        'UNIQUE (recoup_uuid) '
  );
END
$$;


--
-- Name: add_constraints_to_recoup_refresh_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_recoup_refresh_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE recoup_refresh_' || partition_suffix || ' '
      'ADD CONSTRAINT recoup_refresh_' || partition_suffix || '_recoup_refresh_uuid_key '
        'UNIQUE (recoup_refresh_uuid) '
  );
END
$$;


--
-- Name: add_constraints_to_refresh_commitments_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_refresh_commitments_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE refresh_commitments_' || partition_suffix || ' '
      'ADD CONSTRAINT refresh_commitments_' || partition_suffix || '_melt_serial_id_key '
        'UNIQUE (melt_serial_id)'
  );
END
$$;


--
-- Name: add_constraints_to_refresh_revealed_coins_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_refresh_revealed_coins_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE refresh_revealed_coins_' || partition_suffix || ' '
      'ADD CONSTRAINT refresh_revealed_coins_' || partition_suffix || '_rrc_serial_key '
        'UNIQUE (rrc_serial) '
      ',ADD CONSTRAINT refresh_revealed_coins_' || partition_suffix || '_coin_ev_key '
        'UNIQUE (coin_ev) '
      ',ADD CONSTRAINT refresh_revealed_coins_' || partition_suffix || '_h_coin_ev_key '
        'UNIQUE (h_coin_ev) '
      ',ADD PRIMARY KEY (melt_serial_id, freshcoin_index) '
  );
END
$$;


--
-- Name: add_constraints_to_refresh_transfer_keys_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_refresh_transfer_keys_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE refresh_transfer_keys_' || partition_suffix || ' '
      'ADD CONSTRAINT refresh_transfer_keys_' || partition_suffix || '_rtc_serial_key '
        'UNIQUE (rtc_serial)'
  );
END
$$;


--
-- Name: add_constraints_to_refunds_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_refunds_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE refunds_' || partition_suffix || ' '
      'ADD CONSTRAINT refunds_' || partition_suffix || '_refund_serial_id_key '
        'UNIQUE (refund_serial_id) '
      ',ADD PRIMARY KEY (deposit_serial_id, rtransaction_id) '
  );
END
$$;


--
-- Name: add_constraints_to_reserves_close_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_reserves_close_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE reserves_close_' || partition_suffix || ' '
      'ADD CONSTRAINT reserves_close_' || partition_suffix || '_close_uuid_pkey '
        'PRIMARY KEY (close_uuid)'
  );
END
$$;


--
-- Name: add_constraints_to_reserves_in_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_reserves_in_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE reserves_in_' || partition_suffix || ' '
      'ADD CONSTRAINT reserves_in_' || partition_suffix || '_reserve_in_serial_id_key '
        'UNIQUE (reserve_in_serial_id)'
  );
END
$$;


--
-- Name: add_constraints_to_reserves_out_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_reserves_out_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE reserves_out_' || partition_suffix || ' '
      'ADD CONSTRAINT reserves_out_' || partition_suffix || '_reserve_out_serial_id_key '
        'UNIQUE (reserve_out_serial_id)'
  );
END
$$;


--
-- Name: add_constraints_to_wire_out_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_wire_out_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE wire_out_' || partition_suffix || ' '
      'ADD CONSTRAINT wire_out_' || partition_suffix || '_wireout_uuid_pkey '
        'PRIMARY KEY (wireout_uuid)'
  );
END
$$;


--
-- Name: add_constraints_to_wire_targets_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_wire_targets_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE wire_targets_' || partition_suffix || ' '
      'ADD CONSTRAINT wire_targets_' || partition_suffix || '_wire_target_serial_id_key '
        'UNIQUE (wire_target_serial_id)'
  );
END
$$;


--
-- Name: defer_wire_out(); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.defer_wire_out()
    LANGUAGE plpgsql
    AS $$
BEGIN

IF EXISTS (
  SELECT 1
    FROM information_Schema.constraint_column_usage
   WHERE table_name='wire_out'
     AND constraint_name='wire_out_ref')
THEN
  SET CONSTRAINTS wire_out_ref DEFERRED;
END IF;

END $$;


--
-- Name: deposits_by_coin_delete_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.deposits_by_coin_delete_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  DELETE FROM deposits_by_coin
   WHERE coin_pub = OLD.coin_pub
     AND shard = OLD.shard
     AND deposit_serial_id = OLD.deposit_serial_id;
  RETURN OLD;
END $$;


--
-- Name: FUNCTION deposits_by_coin_delete_trigger(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.deposits_by_coin_delete_trigger() IS 'Replicate deposits deletions into deposits_by_coin table.';


--
-- Name: deposits_by_coin_insert_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.deposits_by_coin_insert_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO deposits_by_coin
    (deposit_serial_id
    ,shard
    ,coin_pub)
  VALUES
    (NEW.deposit_serial_id
    ,NEW.shard
    ,NEW.coin_pub);
  RETURN NEW;
END $$;


--
-- Name: FUNCTION deposits_by_coin_insert_trigger(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.deposits_by_coin_insert_trigger() IS 'Replicate deposit inserts into deposits_by_coin table.';


--
-- Name: exchange_do_deposit(bigint, integer, bytea, bytea, bigint, bigint, bigint, bigint, bytea, character varying, bytea, bigint, bytea, bytea, bigint, boolean, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_deposit(in_amount_with_fee_val bigint, in_amount_with_fee_frac integer, in_h_contract_terms bytea, in_wire_salt bytea, in_wallet_timestamp bigint, in_exchange_timestamp bigint, in_refund_deadline bigint, in_wire_deadline bigint, in_merchant_pub bytea, in_receiver_wire_account character varying, in_h_payto bytea, in_known_coin_id bigint, in_coin_pub bytea, in_coin_sig bytea, in_shard bigint, in_extension_blocked boolean, in_extension_details character varying, OUT out_exchange_timestamp bigint, OUT out_balance_ok boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
  wtsi INT8; -- wire target serial id
DECLARE
  xdi INT8; -- eXstension details serial id
BEGIN
-- Shards: INSERT extension_details (by extension_details_serial_id)
--         INSERT wire_targets (by h_payto), on CONFLICT DO NOTHING;
--         INSERT deposits (by shard + merchant_pub + h_payto), ON CONFLICT DO NOTHING;
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
  (wire_target_h_payto
  ,payto_uri)
  VALUES
  (in_h_payto
  ,in_receiver_wire_account)
ON CONFLICT DO NOTHING -- for CONFLICT ON (wire_target_h_payto)
  RETURNING wire_target_serial_id INTO wtsi;

IF NOT FOUND
THEN
  SELECT wire_target_serial_id
  INTO wtsi
  FROM wire_targets
  WHERE wire_target_h_payto=in_h_payto;
END IF;


INSERT INTO deposits
  (shard
  ,coin_pub
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
  ,wire_target_h_payto
  ,extension_blocked
  ,extension_details_serial_id
  )
  VALUES
  (in_shard
  ,in_coin_pub
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
  ,in_h_payto
  ,in_extension_blocked
  ,xdi)
  ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- Idempotency check: see if an identical record exists.
  -- Note that by checking 'coin_sig', we implicitly check
  -- identity over everything that the signature covers.
  -- We do select over merchant_pub and wire_target_h_payto
  -- primarily here to maximally use the existing index.
  SELECT
     exchange_timestamp
   INTO
     out_exchange_timestamp
   FROM deposits
   WHERE shard=in_shard
     AND merchant_pub=in_merchant_pub
     AND wire_target_h_payto=in_h_payto
     AND coin_pub=in_coin_pub
     AND coin_sig=in_coin_sig;

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


--
-- Name: exchange_do_gc(bigint, bigint); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.exchange_do_gc(in_ancient_date bigint, in_now bigint)
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
DECLARE
  denom_min INT8; -- minimum denomination still alive
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
-- FIXME: recoup_refresh lacks GC!

SELECT
     reserve_uuid
  INTO
     reserve_uuid_min
  FROM reserves
  ORDER BY reserve_uuid ASC
  LIMIT 1;

DELETE FROM reserves_out
  WHERE reserve_uuid < reserve_uuid_min;

-- FIXME: this query will be horribly slow;
-- need to find another way to formulate it...
DELETE FROM denominations
  WHERE expire_legal < in_now
    AND denominations_serial NOT IN
      (SELECT DISTINCT denominations_serial
         FROM reserves_out)
    AND denominations_serial NOT IN
      (SELECT DISTINCT denominations_serial
         FROM known_coins
        WHERE coin_pub IN
          (SELECT DISTINCT coin_pub
             FROM recoup))
    AND denominations_serial NOT IN
      (SELECT DISTINCT denominations_serial
         FROM known_coins
        WHERE coin_pub IN
          (SELECT DISTINCT coin_pub
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

SELECT
     denominations_serial
  INTO
     denom_min
  FROM denominations
  ORDER BY denominations_serial ASC
  LIMIT 1;

DELETE FROM cs_nonce_locks
  WHERE max_denomination_serial <= denom_min;

END $$;


--
-- Name: exchange_do_melt(bytea, bigint, integer, bytea, bytea, bytea, bigint, integer, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_melt(in_cs_rms bytea, in_amount_with_fee_val bigint, in_amount_with_fee_frac integer, in_rc bytea, in_old_coin_pub bytea, in_old_coin_sig bytea, in_known_coin_id bigint, in_noreveal_index integer, in_zombie_required boolean, OUT out_balance_ok boolean, OUT out_zombie_bad boolean, OUT out_noreveal_index integer) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
  denom_max INT8;
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



-- Special actions needed for a CS melt?
IF NOT NULL in_cs_rms
THEN
  -- Get maximum denominations serial value in
  -- existence, this will determine how long the
  -- nonce will be locked.
  SELECT
      denominations_serial
    INTO
      denom_max
    FROM denominations
      ORDER BY denominations_serial DESC
      LIMIT 1;

  -- Cache CS signature to prevent replays in the future
  -- (and check if cached signature exists at the same time).
  INSERT INTO cs_nonce_locks
    (nonce
    ,max_denomination_serial
    ,op_hash)
  VALUES
    (cs_rms
    ,denom_serial
    ,in_rc)
  ON CONFLICT DO NOTHING;

  IF NOT FOUND
  THEN
    -- Record exists, make sure it is the same
    SELECT 1
      FROM cs_nonce_locks
     WHERE nonce=cs_rms
       AND op_hash=in_rc;

    IF NOT FOUND
    THEN
       -- Nonce reuse detected
       out_balance_ok=FALSE;
       out_zombie_bad=FALSE;
       out_noreveal_index=42; -- FIXME: return error message more nicely!
       ASSERT false, 'nonce reuse attempted by client';
    END IF;
  END IF;
END IF;




-- Everything fine, return success!
out_balance_ok=TRUE;
out_noreveal_index=in_noreveal_index;

END $$;


--
-- Name: exchange_do_recoup_to_coin(bytea, bigint, bytea, bytea, bigint, bytea, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_recoup_to_coin(in_old_coin_pub bytea, in_rrc_serial bigint, in_coin_blind bytea, in_coin_pub bytea, in_known_coin_id bigint, in_coin_sig bytea, in_recoup_timestamp bigint, OUT out_recoup_ok boolean, OUT out_internal_failure boolean, OUT out_recoup_timestamp bigint) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
  tmp_val INT8; -- amount recouped
DECLARE
  tmp_frac INT8; -- amount recouped
BEGIN

-- Shards: UPDATE known_coins (by coin_pub)
--         SELECT recoup_refresh (by coin_pub)
--         UPDATE known_coins (by coin_pub)
--         INSERT recoup_refresh (by coin_pub)


out_internal_failure=FALSE;


-- Check remaining balance of the coin.
SELECT
   remaining_frac
  ,remaining_val
 INTO
   tmp_frac
  ,tmp_val
FROM known_coins
  WHERE coin_pub=in_coin_pub;

IF NOT FOUND
THEN
  out_internal_failure=TRUE;
  out_recoup_ok=FALSE;
  RETURN;
END IF;

IF tmp_val + tmp_frac = 0
THEN
  -- Check for idempotency
  SELECT
      recoup_timestamp
    INTO
      out_recoup_timestamp
    FROM recoup_refresh
    WHERE coin_pub=in_coin_pub;
  out_recoup_ok=FOUND;
  RETURN;
END IF;

-- Update balance of the coin.
UPDATE known_coins
  SET
     remaining_frac=0
    ,remaining_val=0
  WHERE coin_pub=in_coin_pub;


-- Credit the old coin.
UPDATE known_coins
  SET
    remaining_frac=remaining_frac+tmp_frac
       - CASE
         WHEN remaining_frac+tmp_frac >= 100000000
         THEN 100000000
         ELSE 0
         END,
    remaining_val=remaining_val+tmp_val
       + CASE
         WHEN remaining_frac+tmp_frac >= 100000000
         THEN 1
         ELSE 0
         END
  WHERE coin_pub=in_old_coin_pub;


IF NOT FOUND
THEN
  RAISE NOTICE 'failed to increase old coin balance from recoup';
  out_recoup_ok=TRUE;
  out_internal_failure=TRUE;
  RETURN;
END IF;


INSERT INTO recoup_refresh
  (coin_pub
  ,known_coin_id
  ,coin_sig
  ,coin_blind
  ,amount_val
  ,amount_frac
  ,recoup_timestamp
  ,rrc_serial
  )
VALUES
  (in_coin_pub
  ,in_known_coin_id
  ,in_coin_sig
  ,in_coin_blind
  ,tmp_val
  ,tmp_frac
  ,in_recoup_timestamp
  ,in_rrc_serial);

-- Normal end, everything is fine.
out_recoup_ok=TRUE;
out_recoup_timestamp=in_recoup_timestamp;

END $$;


--
-- Name: exchange_do_recoup_to_reserve(bytea, bigint, bytea, bytea, bigint, bytea, bigint, bigint, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_recoup_to_reserve(in_reserve_pub bytea, in_reserve_out_serial_id bigint, in_coin_blind bytea, in_coin_pub bytea, in_known_coin_id bigint, in_coin_sig bytea, in_reserve_gc bigint, in_reserve_expiration bigint, in_recoup_timestamp bigint, OUT out_recoup_ok boolean, OUT out_internal_failure boolean, OUT out_recoup_timestamp bigint) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
  tmp_val INT8; -- amount recouped
DECLARE
  tmp_frac INT8; -- amount recouped
BEGIN
-- Shards: SELECT known_coins (by coin_pub)
--         SELECT recoup      (by coin_pub)
--         UPDATE known_coins (by coin_pub)
--         UPDATE reserves (by reserve_pub)
--         INSERT recoup      (by coin_pub)

out_internal_failure=FALSE;


-- Check remaining balance of the coin.
SELECT
   remaining_frac
  ,remaining_val
 INTO
   tmp_frac
  ,tmp_val
FROM known_coins
  WHERE coin_pub=in_coin_pub;

IF NOT FOUND
THEN
  out_internal_failure=TRUE;
  out_recoup_ok=FALSE;
  RETURN;
END IF;

IF tmp_val + tmp_frac = 0
THEN
  -- Check for idempotency
  SELECT
    recoup_timestamp
  INTO
    out_recoup_timestamp
    FROM recoup
    WHERE coin_pub=in_coin_pub;

  out_recoup_ok=FOUND;
  RETURN;
END IF;


-- Update balance of the coin.
UPDATE known_coins
  SET
     remaining_frac=0
    ,remaining_val=0
  WHERE coin_pub=in_coin_pub;


-- Credit the reserve and update reserve timers.
UPDATE reserves
  SET
    current_balance_frac=current_balance_frac+tmp_frac
       - CASE
         WHEN current_balance_frac+tmp_frac >= 100000000
         THEN 100000000
         ELSE 0
         END,
    current_balance_val=current_balance_val+tmp_val
       + CASE
         WHEN current_balance_frac+tmp_frac >= 100000000
         THEN 1
         ELSE 0
         END,
    gc_date=GREATEST(gc_date, in_reserve_gc),
    expiration_date=GREATEST(expiration_date, in_reserve_expiration)
  WHERE reserve_pub=in_reserve_pub;


IF NOT FOUND
THEN
  RAISE NOTICE 'failed to increase reserve balance from recoup';
  out_recoup_ok=TRUE;
  out_internal_failure=TRUE;
  RETURN;
END IF;


INSERT INTO recoup
  (coin_pub
  ,coin_sig
  ,coin_blind
  ,amount_val
  ,amount_frac
  ,recoup_timestamp
  ,reserve_out_serial_id
  )
VALUES
  (in_coin_pub
  ,in_coin_sig
  ,in_coin_blind
  ,tmp_val
  ,tmp_frac
  ,in_recoup_timestamp
  ,in_reserve_out_serial_id);

-- Normal end, everything is fine.
out_recoup_ok=TRUE;
out_recoup_timestamp=in_recoup_timestamp;

END $$;


--
-- Name: exchange_do_refund(bigint, integer, bigint, integer, bigint, integer, bytea, bigint, bigint, bigint, bytea, bytea, bytea); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_refund(in_amount_with_fee_val bigint, in_amount_with_fee_frac integer, in_amount_val bigint, in_amount_frac integer, in_deposit_fee_val bigint, in_deposit_fee_frac integer, in_h_contract_terms bytea, in_rtransaction_id bigint, in_deposit_shard bigint, in_known_coin_id bigint, in_coin_pub bytea, in_merchant_pub bytea, in_merchant_sig bytea, OUT out_not_found boolean, OUT out_refund_ok boolean, OUT out_gone boolean, OUT out_conflict boolean) RETURNS record
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
-- Shards: SELECT deposits (by shard, coin_pub, h_contract_terms, merchant_pub)
--         INSERT refunds (by deposit_serial_id, rtransaction_id) ON CONFLICT DO NOTHING
--         SELECT refunds (by deposit_serial_id)
--         UPDATE known_coins (by coin_pub)

SELECT
   dep.deposit_serial_id
  ,dep.amount_with_fee_val
  ,dep.amount_with_fee_frac
  ,dep.done
INTO
   dsi
  ,deposit_val
  ,deposit_frac
  ,out_gone
FROM deposits_by_coin dbc
  JOIN deposits dep USING (shard,deposit_serial_id)
 WHERE dbc.coin_pub=in_coin_pub
  AND dep.shard=in_deposit_shard
  AND dep.merchant_pub=in_merchant_pub
  AND dep.h_contract_terms=in_h_contract_terms;

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
  ,shard
  ,merchant_sig
  ,rtransaction_id
  ,amount_with_fee_val
  ,amount_with_fee_frac
  )
  VALUES
  (dsi
  ,in_deposit_shard
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
   WHERE shard=in_deposit_shard
     AND deposit_serial_id=dsi
     AND rtransaction_id=in_rtransaction_id
     AND amount_with_fee_val=in_amount_with_fee_val
     AND amount_with_fee_frac=in_amount_with_fee_frac;

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
  WHERE shard=in_deposit_shard
    AND deposit_serial_id=dsi;
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


--
-- Name: exchange_do_withdraw(bigint, integer, bytea, bytea, bytea, bytea, bytea, bigint, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_withdraw(amount_val bigint, amount_frac integer, h_denom_pub bytea, rpub bytea, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT kycok boolean, OUT ruuid bigint, OUT account_uuid bigint) RETURNS record
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


SELECT denominations_serial INTO denom_serial
  FROM denominations
 WHERE denom_pub_hash=h_denom_pub;

IF NOT FOUND
THEN
  -- denomination unknown, should be impossible!
  reserve_found=FALSE;
  balance_ok=FALSE;
  kycok=FALSE;
  ruuid=0;
  account_uuid=0;
  ASSERT false, 'denomination unknown';
  RETURN;
END IF;


UPDATE reserves SET
   gc_date=GREATEST(gc_date, min_reserve_gc)
  ,current_balance_val=current_balance_val - amount_val
     - CASE WHEN (current_balance_frac < amount_frac)
         THEN 1
         ELSE 0
       END
  ,current_balance_frac=current_balance_frac - amount_frac
     + CASE WHEN (current_balance_frac < amount_frac)
         THEN 100000000
         ELSE 0
       END
 WHERE reserves.reserve_pub=rpub
   AND ( (current_balance_val > amount_val) OR
         ( (current_balance_val = amount_val) AND
           (current_balance_frac >= amount_frac) ) );

balance_ok=FOUND;

-- Obtain KYC status based on the last wire transfer into
-- this reserve. FIXME: likely not adequate for reserves that got P2P transfers!
SELECT
   kyc_ok
  ,wire_source_serial_id
  ,reserve_uuid
  INTO
   kycok
  ,account_uuid
  ,ruuid
  FROM reserves 
  JOIN reserves_in USING (reserve_uuid)
  JOIN wire_targets ON (wire_source_serial_id = wire_target_serial_id)
 WHERE reserves.reserve_pub=rpub
 LIMIT 1; -- limit 1 should not be required (without p2p transfers)

IF NOT FOUND
THEN
  -- reserve unknown
  reserve_found=FALSE;
  balance_ok=FALSE;
  kycok=FALSE;
  account_uuid=0;
  RETURN;
END IF;

reserve_found=TRUE;


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
  balance_ok=TRUE;
  -- rollback any potential balance update we may have made
  ROLLBACK;
  START TRANSACTION ISOLATION LEVEL SERIALIZABLE;
  RETURN;
END IF;

END $$;


--
-- Name: FUNCTION exchange_do_withdraw(amount_val bigint, amount_frac integer, h_denom_pub bytea, rpub bytea, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT kycok boolean, OUT ruuid bigint, OUT account_uuid bigint); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.exchange_do_withdraw(amount_val bigint, amount_frac integer, h_denom_pub bytea, rpub bytea, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT kycok boolean, OUT ruuid bigint, OUT account_uuid bigint) IS 'Checks whether the reserve has sufficient balance for a withdraw operation (or the request is repeated and was previously approved) and if so updates the database with the result';


--
-- Name: exchange_do_withdraw(bytea, bigint, integer, bytea, bytea, bytea, bytea, bytea, bigint, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_withdraw(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, rpub bytea, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT kycok boolean, OUT account_uuid bigint, OUT ruuid bigint) RETURNS record
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
--         reserves_out (INSERT, with CONFLICT detection) by wih
--         reserves by reserve_pub (UPDATE)
--         reserves_in by reserve_pub (SELECT)
--         wire_targets by wire_target_h_payto

SELECT denominations_serial
  INTO denom_serial
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
  ruuid=2;
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
  IF (reserve_frac >= amount_frac)
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



-- Special actions needed for a CS withdraw?
IF NOT NULL cs_nonce
THEN
  -- Cache CS signature to prevent replays in the future
  -- (and check if cached signature exists at the same time).
  INSERT INTO cs_nonce_locks
    (nonce
    ,max_denomination_serial
    ,op_hash)
  VALUES
    (cs_nonce
    ,denom_serial
    ,h_coin_envelope)
  ON CONFLICT DO NOTHING;

  IF NOT FOUND
  THEN
    -- See if the existing entry is identical.
    SELECT 1
      FROM cs_nonce_locks
     WHERE nonce=cs_nonce
       AND op_hash=h_coin_envelope;
    IF NOT FOUND
    THEN
      reserve_found=FALSE;
      balance_ok=FALSE;
      kycok=FALSE;
      account_uuid=0;
      ruuid=1; -- FIXME: return error message more nicely!
      ASSERT false, 'nonce reuse attempted by client';
    END IF;
  END IF;
END IF;



-- Obtain KYC status based on the last wire transfer into
-- this reserve. FIXME: likely not adequate for reserves that got P2P transfers!
SELECT
   kyc_ok
  ,wire_target_serial_id
  INTO
   kycok
  ,account_uuid
  FROM reserves_in
  JOIN wire_targets ON (wire_source_h_payto = wire_target_h_payto)
 WHERE reserve_pub=rpub
 LIMIT 1; -- limit 1 should not be required (without p2p transfers)


END $$;


--
-- Name: FUNCTION exchange_do_withdraw(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, rpub bytea, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT kycok boolean, OUT account_uuid bigint, OUT ruuid bigint); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.exchange_do_withdraw(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, rpub bytea, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT kycok boolean, OUT account_uuid bigint, OUT ruuid bigint) IS 'Checks whether the reserve has sufficient balance for a withdraw operation (or the request is repeated and was previously approved) and if so updates the database with the result';


--
-- Name: exchange_do_withdraw_limit_check(bigint, bigint, bigint, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_withdraw_limit_check(ruuid bigint, start_time bigint, upper_limit_val bigint, upper_limit_frac integer, OUT below_limit boolean) RETURNS boolean
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


--
-- Name: FUNCTION exchange_do_withdraw_limit_check(ruuid bigint, start_time bigint, upper_limit_val bigint, upper_limit_frac integer, OUT below_limit boolean); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.exchange_do_withdraw_limit_check(ruuid bigint, start_time bigint, upper_limit_val bigint, upper_limit_frac integer, OUT below_limit boolean) IS 'Check whether the withdrawals from the given reserve since the given time are below the given threshold';


--
-- Name: recoup_delete_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recoup_delete_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  DELETE FROM recoup_by_reserve
   WHERE reserve_out_serial_id = OLD.reserve_out_serial_id
     AND coin_pub = OLD.coin_pub;
  RETURN OLD;
END $$;


--
-- Name: FUNCTION recoup_delete_trigger(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.recoup_delete_trigger() IS 'Replicate recoup deletions into recoup_by_reserve table.';


--
-- Name: recoup_insert_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recoup_insert_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO recoup_by_reserve
    (reserve_out_serial_id
    ,coin_pub)
  VALUES
    (NEW.reserve_out_serial_id
    ,NEW.coin_pub);
  RETURN NEW;
END $$;


--
-- Name: FUNCTION recoup_insert_trigger(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.recoup_insert_trigger() IS 'Replicate recoup inserts into recoup_by_reserve table.';


--
-- Name: reserves_out_by_reserve_delete_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reserves_out_by_reserve_delete_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  DELETE FROM reserves_out_by_reserve
   WHERE reserve_uuid = OLD.reserve_uuid;
  RETURN OLD;
END $$;


--
-- Name: FUNCTION reserves_out_by_reserve_delete_trigger(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.reserves_out_by_reserve_delete_trigger() IS 'Replicate reserve_out deletions into reserve_out_by_reserve table.';


--
-- Name: reserves_out_by_reserve_insert_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reserves_out_by_reserve_insert_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO reserves_out_by_reserve
    (reserve_uuid
    ,h_blind_ev)
  VALUES
    (NEW.reserve_uuid
    ,NEW.h_blind_ev);
  RETURN NEW;
END $$;


--
-- Name: FUNCTION reserves_out_by_reserve_insert_trigger(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.reserves_out_by_reserve_insert_trigger() IS 'Replicate reserve_out inserts into reserve_out_by_reserve table.';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: patches; Type: TABLE; Schema: _v; Owner: -
--

CREATE TABLE _v.patches (
    patch_name text NOT NULL,
    applied_tsz timestamp with time zone DEFAULT now() NOT NULL,
    applied_by text NOT NULL,
    requires text[],
    conflicts text[]
);


--
-- Name: TABLE patches; Type: COMMENT; Schema: _v; Owner: -
--

COMMENT ON TABLE _v.patches IS 'Contains information about what patches are currently applied on database.';


--
-- Name: COLUMN patches.patch_name; Type: COMMENT; Schema: _v; Owner: -
--

COMMENT ON COLUMN _v.patches.patch_name IS 'Name of patch, has to be unique for every patch.';


--
-- Name: COLUMN patches.applied_tsz; Type: COMMENT; Schema: _v; Owner: -
--

COMMENT ON COLUMN _v.patches.applied_tsz IS 'When the patch was applied.';


--
-- Name: COLUMN patches.applied_by; Type: COMMENT; Schema: _v; Owner: -
--

COMMENT ON COLUMN _v.patches.applied_by IS 'Who applied this patch (PostgreSQL username)';


--
-- Name: COLUMN patches.requires; Type: COMMENT; Schema: _v; Owner: -
--

COMMENT ON COLUMN _v.patches.requires IS 'List of patches that are required for given patch.';


--
-- Name: COLUMN patches.conflicts; Type: COMMENT; Schema: _v; Owner: -
--

COMMENT ON COLUMN _v.patches.conflicts IS 'List of patches that conflict with given patch.';


--
-- Name: aggregation_tracking; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.aggregation_tracking (
    aggregation_serial_id bigint NOT NULL,
    deposit_serial_id bigint NOT NULL,
    wtid_raw bytea NOT NULL
)
PARTITION BY HASH (deposit_serial_id);


--
-- Name: TABLE aggregation_tracking; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.aggregation_tracking IS 'mapping from wire transfer identifiers (WTID) to deposits (and back)';


--
-- Name: COLUMN aggregation_tracking.wtid_raw; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.aggregation_tracking.wtid_raw IS 'We first create entries in the aggregation_tracking table and then finally the wire_out entry once we know the total amount. Hence the constraint must be deferrable and we cannot use a wireout_uuid here, because we do not have it when these rows are created. Changing the logic to first INSERT a dummy row into wire_out and then UPDATEing that row in the same transaction would theoretically reduce per-deposit storage costs by 5 percent (24/~460 bytes).';


--
-- Name: aggregation_tracking_aggregation_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.aggregation_tracking ALTER COLUMN aggregation_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.aggregation_tracking_aggregation_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: aggregation_tracking_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.aggregation_tracking_default (
    aggregation_serial_id bigint NOT NULL,
    deposit_serial_id bigint NOT NULL,
    wtid_raw bytea NOT NULL
);
ALTER TABLE ONLY public.aggregation_tracking ATTACH PARTITION public.aggregation_tracking_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: app_bankaccount; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_bankaccount (
    is_public boolean NOT NULL,
    account_no integer NOT NULL,
    balance character varying NOT NULL,
    user_id integer NOT NULL
);


--
-- Name: app_bankaccount_account_no_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.app_bankaccount_account_no_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: app_bankaccount_account_no_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.app_bankaccount_account_no_seq OWNED BY public.app_bankaccount.account_no;


--
-- Name: app_banktransaction; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_banktransaction (
    id bigint NOT NULL,
    amount character varying NOT NULL,
    subject character varying(200) NOT NULL,
    date timestamp with time zone NOT NULL,
    cancelled boolean NOT NULL,
    request_uid character varying(128) NOT NULL,
    credit_account_id integer NOT NULL,
    debit_account_id integer NOT NULL
);


--
-- Name: app_banktransaction_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.app_banktransaction_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: app_banktransaction_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.app_banktransaction_id_seq OWNED BY public.app_banktransaction.id;


--
-- Name: app_talerwithdrawoperation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_talerwithdrawoperation (
    withdraw_id uuid NOT NULL,
    amount character varying NOT NULL,
    selection_done boolean NOT NULL,
    confirmation_done boolean NOT NULL,
    aborted boolean NOT NULL,
    selected_reserve_pub text,
    selected_exchange_account_id integer,
    withdraw_account_id integer NOT NULL
);


--
-- Name: auditor_balance_summary; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_balance_summary (
    master_pub bytea NOT NULL,
    denom_balance_val bigint NOT NULL,
    denom_balance_frac integer NOT NULL,
    deposit_fee_balance_val bigint NOT NULL,
    deposit_fee_balance_frac integer NOT NULL,
    melt_fee_balance_val bigint NOT NULL,
    melt_fee_balance_frac integer NOT NULL,
    refund_fee_balance_val bigint NOT NULL,
    refund_fee_balance_frac integer NOT NULL,
    risk_val bigint NOT NULL,
    risk_frac integer NOT NULL,
    loss_val bigint NOT NULL,
    loss_frac integer NOT NULL,
    irregular_recoup_val bigint NOT NULL,
    irregular_recoup_frac integer NOT NULL
);


--
-- Name: TABLE auditor_balance_summary; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_balance_summary IS 'the sum of the outstanding coins from auditor_denomination_pending (denom_pubs must belong to the respectives exchange master public key); it represents the auditor_balance_summary of the exchange at this point (modulo unexpected historic_loss-style events where denomination keys are compromised)';


--
-- Name: auditor_denom_sigs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_denom_sigs (
    auditor_denom_serial bigint NOT NULL,
    auditor_uuid bigint NOT NULL,
    denominations_serial bigint NOT NULL,
    auditor_sig bytea,
    CONSTRAINT auditor_denom_sigs_auditor_sig_check CHECK ((length(auditor_sig) = 64))
);


--
-- Name: TABLE auditor_denom_sigs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_denom_sigs IS 'Table with auditor signatures on exchange denomination keys.';


--
-- Name: COLUMN auditor_denom_sigs.auditor_uuid; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denom_sigs.auditor_uuid IS 'Identifies the auditor.';


--
-- Name: COLUMN auditor_denom_sigs.denominations_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denom_sigs.denominations_serial IS 'Denomination the signature is for.';


--
-- Name: COLUMN auditor_denom_sigs.auditor_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denom_sigs.auditor_sig IS 'Signature of the auditor, of purpose TALER_SIGNATURE_AUDITOR_EXCHANGE_KEYS.';


--
-- Name: auditor_denom_sigs_auditor_denom_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.auditor_denom_sigs ALTER COLUMN auditor_denom_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.auditor_denom_sigs_auditor_denom_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: auditor_denomination_pending; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_denomination_pending (
    denom_pub_hash bytea NOT NULL,
    denom_balance_val bigint NOT NULL,
    denom_balance_frac integer NOT NULL,
    denom_loss_val bigint NOT NULL,
    denom_loss_frac integer NOT NULL,
    num_issued bigint NOT NULL,
    denom_risk_val bigint NOT NULL,
    denom_risk_frac integer NOT NULL,
    recoup_loss_val bigint NOT NULL,
    recoup_loss_frac integer NOT NULL,
    CONSTRAINT auditor_denomination_pending_denom_pub_hash_check CHECK ((length(denom_pub_hash) = 64))
);


--
-- Name: TABLE auditor_denomination_pending; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_denomination_pending IS 'outstanding denomination coins that the exchange is aware of and what the respective balances are (outstanding as well as issued overall which implies the maximum value at risk).';


--
-- Name: COLUMN auditor_denomination_pending.num_issued; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denomination_pending.num_issued IS 'counts the number of coins issued (withdraw, refresh) of this denomination';


--
-- Name: COLUMN auditor_denomination_pending.denom_risk_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denomination_pending.denom_risk_val IS 'amount that could theoretically be lost in the future due to recoup operations';


--
-- Name: COLUMN auditor_denomination_pending.recoup_loss_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denomination_pending.recoup_loss_val IS 'amount actually lost due to recoup operations past revocation';


--
-- Name: auditor_exchange_signkeys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_exchange_signkeys (
    master_pub bytea NOT NULL,
    ep_start bigint NOT NULL,
    ep_expire bigint NOT NULL,
    ep_end bigint NOT NULL,
    exchange_pub bytea NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT auditor_exchange_signkeys_exchange_pub_check CHECK ((length(exchange_pub) = 32)),
    CONSTRAINT auditor_exchange_signkeys_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE auditor_exchange_signkeys; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_exchange_signkeys IS 'list of the online signing keys of exchanges we are auditing';


--
-- Name: auditor_exchanges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_exchanges (
    master_pub bytea NOT NULL,
    exchange_url character varying NOT NULL,
    CONSTRAINT auditor_exchanges_master_pub_check CHECK ((length(master_pub) = 32))
);


--
-- Name: TABLE auditor_exchanges; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_exchanges IS 'list of the exchanges we are auditing';


--
-- Name: auditor_historic_denomination_revenue; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_historic_denomination_revenue (
    master_pub bytea NOT NULL,
    denom_pub_hash bytea NOT NULL,
    revenue_timestamp bigint NOT NULL,
    revenue_balance_val bigint NOT NULL,
    revenue_balance_frac integer NOT NULL,
    loss_balance_val bigint NOT NULL,
    loss_balance_frac integer NOT NULL,
    CONSTRAINT auditor_historic_denomination_revenue_denom_pub_hash_check CHECK ((length(denom_pub_hash) = 64))
);


--
-- Name: TABLE auditor_historic_denomination_revenue; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_historic_denomination_revenue IS 'Table with historic profits; basically, when a denom_pub has expired and everything associated with it is garbage collected, the final profits end up in here; note that the denom_pub here is not a foreign key, we just keep it as a reference point.';


--
-- Name: COLUMN auditor_historic_denomination_revenue.revenue_balance_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_historic_denomination_revenue.revenue_balance_val IS 'the sum of all of the profits we made on the coin except for withdraw fees (which are in historic_reserve_revenue); so this includes the deposit, melt and refund fees';


--
-- Name: auditor_historic_reserve_summary; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_historic_reserve_summary (
    master_pub bytea NOT NULL,
    start_date bigint NOT NULL,
    end_date bigint NOT NULL,
    reserve_profits_val bigint NOT NULL,
    reserve_profits_frac integer NOT NULL
);


--
-- Name: TABLE auditor_historic_reserve_summary; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_historic_reserve_summary IS 'historic profits from reserves; we eventually GC auditor_historic_reserve_revenue, and then store the totals in here (by time intervals).';


--
-- Name: auditor_predicted_result; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_predicted_result (
    master_pub bytea NOT NULL,
    balance_val bigint NOT NULL,
    balance_frac integer NOT NULL
);


--
-- Name: TABLE auditor_predicted_result; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_predicted_result IS 'Table with the sum of the ledger, auditor_historic_revenue and the auditor_reserve_balance.  This is the final amount that the exchange should have in its bank account right now.';


--
-- Name: auditor_progress_aggregation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_aggregation (
    master_pub bytea NOT NULL,
    last_wire_out_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: TABLE auditor_progress_aggregation; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_progress_aggregation IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


--
-- Name: auditor_progress_coin; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_coin (
    master_pub bytea NOT NULL,
    last_withdraw_serial_id bigint DEFAULT 0 NOT NULL,
    last_deposit_serial_id bigint DEFAULT 0 NOT NULL,
    last_melt_serial_id bigint DEFAULT 0 NOT NULL,
    last_refund_serial_id bigint DEFAULT 0 NOT NULL,
    last_recoup_serial_id bigint DEFAULT 0 NOT NULL,
    last_recoup_refresh_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: TABLE auditor_progress_coin; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_progress_coin IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


--
-- Name: auditor_progress_deposit_confirmation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_deposit_confirmation (
    master_pub bytea NOT NULL,
    last_deposit_confirmation_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: TABLE auditor_progress_deposit_confirmation; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_progress_deposit_confirmation IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


--
-- Name: auditor_progress_reserve; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_reserve (
    master_pub bytea NOT NULL,
    last_reserve_in_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_out_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_recoup_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_close_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: TABLE auditor_progress_reserve; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_progress_reserve IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


--
-- Name: auditor_reserve_balance; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_reserve_balance (
    master_pub bytea NOT NULL,
    reserve_balance_val bigint NOT NULL,
    reserve_balance_frac integer NOT NULL,
    withdraw_fee_balance_val bigint NOT NULL,
    withdraw_fee_balance_frac integer NOT NULL
);


--
-- Name: TABLE auditor_reserve_balance; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_reserve_balance IS 'sum of the balances of all customer reserves (by exchange master public key)';


--
-- Name: auditor_reserves; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_reserves (
    reserve_pub bytea NOT NULL,
    master_pub bytea NOT NULL,
    reserve_balance_val bigint NOT NULL,
    reserve_balance_frac integer NOT NULL,
    withdraw_fee_balance_val bigint NOT NULL,
    withdraw_fee_balance_frac integer NOT NULL,
    expiration_date bigint NOT NULL,
    auditor_reserves_rowid bigint NOT NULL,
    origin_account text,
    CONSTRAINT auditor_reserves_reserve_pub_check CHECK ((length(reserve_pub) = 32))
);


--
-- Name: TABLE auditor_reserves; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_reserves IS 'all of the customer reserves and their respective balances that the auditor is aware of';


--
-- Name: auditor_reserves_auditor_reserves_rowid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.auditor_reserves_auditor_reserves_rowid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auditor_reserves_auditor_reserves_rowid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.auditor_reserves_auditor_reserves_rowid_seq OWNED BY public.auditor_reserves.auditor_reserves_rowid;


--
-- Name: auditor_wire_fee_balance; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_wire_fee_balance (
    master_pub bytea NOT NULL,
    wire_fee_balance_val bigint NOT NULL,
    wire_fee_balance_frac integer NOT NULL
);


--
-- Name: TABLE auditor_wire_fee_balance; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_wire_fee_balance IS 'sum of the balances of all wire fees (by exchange master public key)';


--
-- Name: auditors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditors (
    auditor_uuid bigint NOT NULL,
    auditor_pub bytea NOT NULL,
    auditor_name character varying NOT NULL,
    auditor_url character varying NOT NULL,
    is_active boolean NOT NULL,
    last_change bigint NOT NULL,
    CONSTRAINT auditors_auditor_pub_check CHECK ((length(auditor_pub) = 32))
);


--
-- Name: TABLE auditors; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditors IS 'Table with auditors the exchange uses or has used in the past. Entries never expire as we need to remember the last_change column indefinitely.';


--
-- Name: COLUMN auditors.auditor_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditors.auditor_pub IS 'Public key of the auditor.';


--
-- Name: COLUMN auditors.auditor_url; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditors.auditor_url IS 'The base URL of the auditor.';


--
-- Name: COLUMN auditors.is_active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditors.is_active IS 'true if we are currently supporting the use of this auditor.';


--
-- Name: COLUMN auditors.last_change; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditors.last_change IS 'Latest time when active status changed. Used to detect replays of old messages.';


--
-- Name: auditors_auditor_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.auditors ALTER COLUMN auditor_uuid ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.auditors_auditor_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: auth_group; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_group (
    id integer NOT NULL,
    name character varying(150) NOT NULL
);


--
-- Name: auth_group_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.auth_group_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_group_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.auth_group_id_seq OWNED BY public.auth_group.id;


--
-- Name: auth_group_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_group_permissions (
    id bigint NOT NULL,
    group_id integer NOT NULL,
    permission_id integer NOT NULL
);


--
-- Name: auth_group_permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.auth_group_permissions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_group_permissions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.auth_group_permissions_id_seq OWNED BY public.auth_group_permissions.id;


--
-- Name: auth_permission; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_permission (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    content_type_id integer NOT NULL,
    codename character varying(100) NOT NULL
);


--
-- Name: auth_permission_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.auth_permission_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_permission_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.auth_permission_id_seq OWNED BY public.auth_permission.id;


--
-- Name: auth_user; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_user (
    id integer NOT NULL,
    password character varying(128) NOT NULL,
    last_login timestamp with time zone,
    is_superuser boolean NOT NULL,
    username character varying(150) NOT NULL,
    first_name character varying(150) NOT NULL,
    last_name character varying(150) NOT NULL,
    email character varying(254) NOT NULL,
    is_staff boolean NOT NULL,
    is_active boolean NOT NULL,
    date_joined timestamp with time zone NOT NULL
);


--
-- Name: auth_user_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_user_groups (
    id bigint NOT NULL,
    user_id integer NOT NULL,
    group_id integer NOT NULL
);


--
-- Name: auth_user_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.auth_user_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_user_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.auth_user_groups_id_seq OWNED BY public.auth_user_groups.id;


--
-- Name: auth_user_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.auth_user_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_user_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.auth_user_id_seq OWNED BY public.auth_user.id;


--
-- Name: auth_user_user_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_user_user_permissions (
    id bigint NOT NULL,
    user_id integer NOT NULL,
    permission_id integer NOT NULL
);


--
-- Name: auth_user_user_permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.auth_user_user_permissions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_user_user_permissions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.auth_user_user_permissions_id_seq OWNED BY public.auth_user_user_permissions.id;


--
-- Name: cs_nonce_locks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cs_nonce_locks (
    cs_nonce_lock_serial_id bigint NOT NULL,
    nonce bytea NOT NULL,
    op_hash bytea NOT NULL,
    max_denomination_serial bigint NOT NULL,
    CONSTRAINT cs_nonce_locks_nonce_check CHECK ((length(nonce) = 32)),
    CONSTRAINT cs_nonce_locks_op_hash_check CHECK ((length(op_hash) = 64))
)
PARTITION BY HASH (nonce);


--
-- Name: TABLE cs_nonce_locks; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.cs_nonce_locks IS 'ensures a Clause Schnorr client nonce is locked for use with an operation identified by a hash';


--
-- Name: COLUMN cs_nonce_locks.nonce; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.cs_nonce_locks.nonce IS 'actual nonce submitted by the client';


--
-- Name: COLUMN cs_nonce_locks.op_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.cs_nonce_locks.op_hash IS 'hash (RC for refresh, blind coin hash for withdraw) the nonce may be used with';


--
-- Name: COLUMN cs_nonce_locks.max_denomination_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.cs_nonce_locks.max_denomination_serial IS 'Maximum number of a CS denomination serial the nonce could be used with, for GC';


--
-- Name: cs_nonce_locks_cs_nonce_lock_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.cs_nonce_locks ALTER COLUMN cs_nonce_lock_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.cs_nonce_locks_cs_nonce_lock_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: cs_nonce_locks_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cs_nonce_locks_default (
    cs_nonce_lock_serial_id bigint NOT NULL,
    nonce bytea NOT NULL,
    op_hash bytea NOT NULL,
    max_denomination_serial bigint NOT NULL,
    CONSTRAINT cs_nonce_locks_nonce_check CHECK ((length(nonce) = 32)),
    CONSTRAINT cs_nonce_locks_op_hash_check CHECK ((length(op_hash) = 64))
);
ALTER TABLE ONLY public.cs_nonce_locks ATTACH PARTITION public.cs_nonce_locks_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: denomination_revocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.denomination_revocations (
    denom_revocations_serial_id bigint NOT NULL,
    denominations_serial bigint NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT denomination_revocations_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE denomination_revocations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.denomination_revocations IS 'remembering which denomination keys have been revoked';


--
-- Name: denomination_revocations_denom_revocations_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.denomination_revocations ALTER COLUMN denom_revocations_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.denomination_revocations_denom_revocations_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: denominations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.denominations (
    denominations_serial bigint NOT NULL,
    denom_pub_hash bytea NOT NULL,
    denom_type integer DEFAULT 1 NOT NULL,
    age_mask integer DEFAULT 0 NOT NULL,
    denom_pub bytea NOT NULL,
    master_sig bytea NOT NULL,
    valid_from bigint NOT NULL,
    expire_withdraw bigint NOT NULL,
    expire_deposit bigint NOT NULL,
    expire_legal bigint NOT NULL,
    coin_val bigint NOT NULL,
    coin_frac integer NOT NULL,
    fee_withdraw_val bigint NOT NULL,
    fee_withdraw_frac integer NOT NULL,
    fee_deposit_val bigint NOT NULL,
    fee_deposit_frac integer NOT NULL,
    fee_refresh_val bigint NOT NULL,
    fee_refresh_frac integer NOT NULL,
    fee_refund_val bigint NOT NULL,
    fee_refund_frac integer NOT NULL,
    CONSTRAINT denominations_denom_pub_hash_check CHECK ((length(denom_pub_hash) = 64)),
    CONSTRAINT denominations_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE denominations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.denominations IS 'Main denominations table. All the valid denominations the exchange knows about.';


--
-- Name: COLUMN denominations.denominations_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.denominations.denominations_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: COLUMN denominations.denom_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.denominations.denom_type IS 'determines cipher type for blind signatures used with this denomination; 0 is for RSA';


--
-- Name: COLUMN denominations.age_mask; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.denominations.age_mask IS 'bitmask with the age restrictions that are being used for this denomination; 0 if denomination does not support the use of age restrictions';


--
-- Name: denominations_denominations_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.denominations ALTER COLUMN denominations_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.denominations_denominations_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: deposit_confirmations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposit_confirmations (
    master_pub bytea NOT NULL,
    serial_id bigint NOT NULL,
    h_contract_terms bytea NOT NULL,
    h_extensions bytea NOT NULL,
    h_wire bytea NOT NULL,
    exchange_timestamp bigint NOT NULL,
    refund_deadline bigint NOT NULL,
    wire_deadline bigint NOT NULL,
    amount_without_fee_val bigint NOT NULL,
    amount_without_fee_frac integer NOT NULL,
    coin_pub bytea NOT NULL,
    merchant_pub bytea NOT NULL,
    exchange_sig bytea NOT NULL,
    exchange_pub bytea NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT deposit_confirmations_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT deposit_confirmations_exchange_pub_check CHECK ((length(exchange_pub) = 32)),
    CONSTRAINT deposit_confirmations_exchange_sig_check CHECK ((length(exchange_sig) = 64)),
    CONSTRAINT deposit_confirmations_h_contract_terms_check CHECK ((length(h_contract_terms) = 64)),
    CONSTRAINT deposit_confirmations_h_contract_terms_check1 CHECK ((length(h_contract_terms) = 64)),
    CONSTRAINT deposit_confirmations_h_wire_check CHECK ((length(h_wire) = 64)),
    CONSTRAINT deposit_confirmations_master_sig_check CHECK ((length(master_sig) = 64)),
    CONSTRAINT deposit_confirmations_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


--
-- Name: TABLE deposit_confirmations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.deposit_confirmations IS 'deposit confirmation sent to us by merchants; we must check that the exchange reported these properly.';


--
-- Name: deposit_confirmations_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.deposit_confirmations_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: deposit_confirmations_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.deposit_confirmations_serial_id_seq OWNED BY public.deposit_confirmations.serial_id;


--
-- Name: deposits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposits (
    deposit_serial_id bigint NOT NULL,
    shard bigint NOT NULL,
    coin_pub bytea NOT NULL,
    known_coin_id bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    wallet_timestamp bigint NOT NULL,
    exchange_timestamp bigint NOT NULL,
    refund_deadline bigint NOT NULL,
    wire_deadline bigint NOT NULL,
    merchant_pub bytea NOT NULL,
    h_contract_terms bytea NOT NULL,
    coin_sig bytea NOT NULL,
    wire_salt bytea NOT NULL,
    wire_target_h_payto bytea,
    tiny boolean DEFAULT false NOT NULL,
    done boolean DEFAULT false NOT NULL,
    extension_blocked boolean DEFAULT false NOT NULL,
    extension_details_serial_id bigint,
    CONSTRAINT deposits_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT deposits_coin_sig_check CHECK ((length(coin_sig) = 64)),
    CONSTRAINT deposits_h_contract_terms_check CHECK ((length(h_contract_terms) = 64)),
    CONSTRAINT deposits_merchant_pub_check CHECK ((length(merchant_pub) = 32)),
    CONSTRAINT deposits_wire_salt_check CHECK ((length(wire_salt) = 16)),
    CONSTRAINT deposits_wire_target_h_payto_check CHECK ((length(wire_target_h_payto) = 32))
)
PARTITION BY HASH (shard);


--
-- Name: TABLE deposits; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.deposits IS 'Deposits we have received and for which we need to make (aggregate) wire transfers (and manage refunds).';


--
-- Name: COLUMN deposits.shard; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.shard IS 'Used for load sharding. Should be set based on merchant_pub. 64-bit value because we need an *unsigned* 32-bit value.';


--
-- Name: COLUMN deposits.known_coin_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.known_coin_id IS 'Used for garbage collection';


--
-- Name: COLUMN deposits.wire_salt; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.wire_salt IS 'Salt used when hashing the payto://-URI to get the h_wire';


--
-- Name: COLUMN deposits.wire_target_h_payto; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.wire_target_h_payto IS 'Identifies the target bank account and KYC status';


--
-- Name: COLUMN deposits.tiny; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.tiny IS 'Set to TRUE if we decided that the amount is too small to ever trigger a wire transfer by itself (requires real aggregation)';


--
-- Name: COLUMN deposits.done; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.done IS 'Set to TRUE once we have included this deposit in some aggregate wire transfer to the merchant';


--
-- Name: COLUMN deposits.extension_blocked; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.extension_blocked IS 'True if the aggregation of the deposit is currently blocked by some extension mechanism. Used to filter out deposits that must not be processed by the canonical deposit logic.';


--
-- Name: COLUMN deposits.extension_details_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.extension_details_serial_id IS 'References extensions table, NULL if extensions are not used';


--
-- Name: deposits_by_coin; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposits_by_coin (
    deposit_serial_id bigint,
    shard bigint NOT NULL,
    coin_pub bytea NOT NULL,
    CONSTRAINT deposits_by_coin_coin_pub_check CHECK ((length(coin_pub) = 32))
)
PARTITION BY HASH (coin_pub);


--
-- Name: TABLE deposits_by_coin; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.deposits_by_coin IS 'Enables fast lookups of deposit by coin_pub, auto-populated via TRIGGER below';


--
-- Name: deposits_by_coin_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposits_by_coin_default (
    deposit_serial_id bigint,
    shard bigint NOT NULL,
    coin_pub bytea NOT NULL,
    CONSTRAINT deposits_by_coin_coin_pub_check CHECK ((length(coin_pub) = 32))
);
ALTER TABLE ONLY public.deposits_by_coin ATTACH PARTITION public.deposits_by_coin_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: deposits_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposits_default (
    deposit_serial_id bigint NOT NULL,
    shard bigint NOT NULL,
    coin_pub bytea NOT NULL,
    known_coin_id bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    wallet_timestamp bigint NOT NULL,
    exchange_timestamp bigint NOT NULL,
    refund_deadline bigint NOT NULL,
    wire_deadline bigint NOT NULL,
    merchant_pub bytea NOT NULL,
    h_contract_terms bytea NOT NULL,
    coin_sig bytea NOT NULL,
    wire_salt bytea NOT NULL,
    wire_target_h_payto bytea,
    tiny boolean DEFAULT false NOT NULL,
    done boolean DEFAULT false NOT NULL,
    extension_blocked boolean DEFAULT false NOT NULL,
    extension_details_serial_id bigint,
    CONSTRAINT deposits_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT deposits_coin_sig_check CHECK ((length(coin_sig) = 64)),
    CONSTRAINT deposits_h_contract_terms_check CHECK ((length(h_contract_terms) = 64)),
    CONSTRAINT deposits_merchant_pub_check CHECK ((length(merchant_pub) = 32)),
    CONSTRAINT deposits_wire_salt_check CHECK ((length(wire_salt) = 16)),
    CONSTRAINT deposits_wire_target_h_payto_check CHECK ((length(wire_target_h_payto) = 32))
);
ALTER TABLE ONLY public.deposits ATTACH PARTITION public.deposits_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.deposits ALTER COLUMN deposit_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.deposits_deposit_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: django_content_type; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.django_content_type (
    id integer NOT NULL,
    app_label character varying(100) NOT NULL,
    model character varying(100) NOT NULL
);


--
-- Name: django_content_type_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.django_content_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: django_content_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.django_content_type_id_seq OWNED BY public.django_content_type.id;


--
-- Name: django_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.django_migrations (
    id bigint NOT NULL,
    app character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    applied timestamp with time zone NOT NULL
);


--
-- Name: django_migrations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.django_migrations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: django_migrations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.django_migrations_id_seq OWNED BY public.django_migrations.id;


--
-- Name: django_session; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.django_session (
    session_key character varying(40) NOT NULL,
    session_data text NOT NULL,
    expire_date timestamp with time zone NOT NULL
);


--
-- Name: exchange_sign_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.exchange_sign_keys (
    esk_serial bigint NOT NULL,
    exchange_pub bytea NOT NULL,
    master_sig bytea NOT NULL,
    valid_from bigint NOT NULL,
    expire_sign bigint NOT NULL,
    expire_legal bigint NOT NULL,
    CONSTRAINT exchange_sign_keys_exchange_pub_check CHECK ((length(exchange_pub) = 32)),
    CONSTRAINT exchange_sign_keys_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE exchange_sign_keys; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.exchange_sign_keys IS 'Table with master public key signatures on exchange online signing keys.';


--
-- Name: COLUMN exchange_sign_keys.exchange_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exchange_sign_keys.exchange_pub IS 'Public online signing key of the exchange.';


--
-- Name: COLUMN exchange_sign_keys.master_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exchange_sign_keys.master_sig IS 'Signature affirming the validity of the signing key of purpose TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY.';


--
-- Name: COLUMN exchange_sign_keys.valid_from; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exchange_sign_keys.valid_from IS 'Time when this online signing key will first be used to sign messages.';


--
-- Name: COLUMN exchange_sign_keys.expire_sign; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exchange_sign_keys.expire_sign IS 'Time when this online signing key will no longer be used to sign.';


--
-- Name: COLUMN exchange_sign_keys.expire_legal; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exchange_sign_keys.expire_legal IS 'Time when this online signing key legally expires.';


--
-- Name: exchange_sign_keys_esk_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.exchange_sign_keys ALTER COLUMN esk_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.exchange_sign_keys_esk_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: extension_details; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.extension_details (
    extension_details_serial_id bigint NOT NULL,
    extension_options character varying
);


--
-- Name: TABLE extension_details; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.extension_details IS 'Extensions that were provided with deposits (not yet used).';


--
-- Name: COLUMN extension_details.extension_options; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.extension_details.extension_options IS 'JSON object with options set that the exchange needs to consider when executing a deposit. Supported details depend on the extensions supported by the exchange.';


--
-- Name: extension_details_extension_details_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.extension_details ALTER COLUMN extension_details_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.extension_details_extension_details_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: extensions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.extensions (
    extension_id bigint NOT NULL,
    name character varying NOT NULL,
    config bytea
);


--
-- Name: TABLE extensions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.extensions IS 'Configurations of the activated extensions';


--
-- Name: COLUMN extensions.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.extensions.name IS 'Name of the extension';


--
-- Name: COLUMN extensions.config; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.extensions.config IS 'Configuration of the extension as JSON-blob, maybe NULL';


--
-- Name: extensions_extension_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.extensions ALTER COLUMN extension_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.extensions_extension_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: global_fee; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.global_fee (
    global_fee_serial bigint NOT NULL,
    start_date bigint NOT NULL,
    end_date bigint NOT NULL,
    history_fee_val bigint NOT NULL,
    history_fee_frac integer NOT NULL,
    kyc_fee_val bigint NOT NULL,
    kyc_fee_frac integer NOT NULL,
    account_fee_val bigint NOT NULL,
    account_fee_frac integer NOT NULL,
    purse_fee_val bigint NOT NULL,
    purse_fee_frac integer NOT NULL,
    purse_timeout bigint NOT NULL,
    kyc_timeout bigint NOT NULL,
    history_expiration bigint NOT NULL,
    purse_account_limit integer NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT global_fee_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE global_fee; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.global_fee IS 'list of the global fees of this exchange, by date';


--
-- Name: COLUMN global_fee.global_fee_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.global_fee.global_fee_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: global_fee_global_fee_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.global_fee ALTER COLUMN global_fee_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.global_fee_global_fee_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: known_coins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.known_coins (
    known_coin_id bigint NOT NULL,
    denominations_serial bigint NOT NULL,
    coin_pub bytea NOT NULL,
    age_commitment_hash bytea,
    denom_sig bytea NOT NULL,
    remaining_val bigint NOT NULL,
    remaining_frac integer NOT NULL,
    CONSTRAINT known_coins_age_commitment_hash_check CHECK ((length(age_commitment_hash) = 32)),
    CONSTRAINT known_coins_coin_pub_check CHECK ((length(coin_pub) = 32))
)
PARTITION BY HASH (coin_pub);


--
-- Name: TABLE known_coins; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.known_coins IS 'information about coins and their signatures, so we do not have to store the signatures more than once if a coin is involved in multiple operations';


--
-- Name: COLUMN known_coins.denominations_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.known_coins.denominations_serial IS 'Denomination of the coin, determines the value of the original coin and applicable fees for coin-specific operations.';


--
-- Name: COLUMN known_coins.coin_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.known_coins.coin_pub IS 'EdDSA public key of the coin';


--
-- Name: COLUMN known_coins.age_commitment_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.known_coins.age_commitment_hash IS 'Optional hash of the age commitment for age restrictions as per DD 24 (active if denom_type has the respective bit set)';


--
-- Name: COLUMN known_coins.denom_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.known_coins.denom_sig IS 'This is the signature of the exchange that affirms that the coin is a valid coin. The specific signature type depends on denom_type of the denomination.';


--
-- Name: COLUMN known_coins.remaining_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.known_coins.remaining_val IS 'Value of the coin that remains to be spent';


--
-- Name: known_coins_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.known_coins_default (
    known_coin_id bigint NOT NULL,
    denominations_serial bigint NOT NULL,
    coin_pub bytea NOT NULL,
    age_commitment_hash bytea,
    denom_sig bytea NOT NULL,
    remaining_val bigint NOT NULL,
    remaining_frac integer NOT NULL,
    CONSTRAINT known_coins_age_commitment_hash_check CHECK ((length(age_commitment_hash) = 32)),
    CONSTRAINT known_coins_coin_pub_check CHECK ((length(coin_pub) = 32))
);
ALTER TABLE ONLY public.known_coins ATTACH PARTITION public.known_coins_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: known_coins_known_coin_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.known_coins ALTER COLUMN known_coin_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.known_coins_known_coin_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_accounts (
    account_serial bigint NOT NULL,
    merchant_serial bigint NOT NULL,
    h_wire bytea NOT NULL,
    salt bytea NOT NULL,
    payto_uri character varying NOT NULL,
    active boolean NOT NULL,
    CONSTRAINT merchant_accounts_h_wire_check CHECK ((length(h_wire) = 64)),
    CONSTRAINT merchant_accounts_salt_check CHECK ((length(salt) = 16))
);


--
-- Name: TABLE merchant_accounts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_accounts IS 'bank accounts of the instances';


--
-- Name: COLUMN merchant_accounts.h_wire; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_accounts.h_wire IS 'salted hash of payto_uri';


--
-- Name: COLUMN merchant_accounts.salt; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_accounts.salt IS 'salt used when hashing payto_uri into h_wire';


--
-- Name: COLUMN merchant_accounts.payto_uri; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_accounts.payto_uri IS 'payto URI of a merchant bank account';


--
-- Name: COLUMN merchant_accounts.active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_accounts.active IS 'true if we actively use this bank account, false if it is just kept around for older contracts to refer to';


--
-- Name: merchant_accounts_account_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.merchant_accounts ALTER COLUMN account_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.merchant_accounts_account_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_contract_terms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_contract_terms (
    order_serial bigint NOT NULL,
    merchant_serial bigint NOT NULL,
    order_id character varying NOT NULL,
    contract_terms bytea NOT NULL,
    h_contract_terms bytea NOT NULL,
    creation_time bigint NOT NULL,
    pay_deadline bigint NOT NULL,
    refund_deadline bigint NOT NULL,
    paid boolean DEFAULT false NOT NULL,
    wired boolean DEFAULT false NOT NULL,
    fulfillment_url character varying,
    session_id character varying DEFAULT ''::character varying NOT NULL,
    claim_token bytea NOT NULL,
    CONSTRAINT merchant_contract_terms_claim_token_check CHECK ((length(claim_token) = 16)),
    CONSTRAINT merchant_contract_terms_h_contract_terms_check CHECK ((length(h_contract_terms) = 64))
);


--
-- Name: TABLE merchant_contract_terms; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_contract_terms IS 'Contracts are orders that have been claimed by a wallet';


--
-- Name: COLUMN merchant_contract_terms.merchant_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.merchant_serial IS 'Identifies the instance offering the contract';


--
-- Name: COLUMN merchant_contract_terms.order_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.order_id IS 'Not a foreign key into merchant_orders because paid contracts persist after expiration';


--
-- Name: COLUMN merchant_contract_terms.contract_terms; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.contract_terms IS 'These contract terms include the wallet nonce';


--
-- Name: COLUMN merchant_contract_terms.h_contract_terms; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.h_contract_terms IS 'Hash over contract_terms';


--
-- Name: COLUMN merchant_contract_terms.pay_deadline; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.pay_deadline IS 'How long is the offer valid. After this time, the order can be garbage collected';


--
-- Name: COLUMN merchant_contract_terms.refund_deadline; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.refund_deadline IS 'By what times do refunds have to be approved (useful to reject refund requests)';


--
-- Name: COLUMN merchant_contract_terms.paid; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.paid IS 'true implies the customer paid for this contract; order should be DELETEd from merchant_orders once paid is set to release merchant_order_locks; paid remains true even if the payment was later refunded';


--
-- Name: COLUMN merchant_contract_terms.wired; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.wired IS 'true implies the exchange wired us the full amount for all non-refunded payments under this contract';


--
-- Name: COLUMN merchant_contract_terms.fulfillment_url; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.fulfillment_url IS 'also included in contract_terms, but we need it here to SELECT on it during repurchase detection; can be NULL if the contract has no fulfillment URL';


--
-- Name: COLUMN merchant_contract_terms.session_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.session_id IS 'last session_id from we confirmed the paying client to use, empty string for none';


--
-- Name: COLUMN merchant_contract_terms.claim_token; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.claim_token IS 'Token optionally used to access the status of the order. All zeros (not NULL) if not used';


--
-- Name: merchant_deposit_to_transfer; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_deposit_to_transfer (
    deposit_serial bigint NOT NULL,
    coin_contribution_value_val bigint NOT NULL,
    coin_contribution_value_frac integer NOT NULL,
    credit_serial bigint NOT NULL,
    execution_time bigint NOT NULL,
    signkey_serial bigint NOT NULL,
    exchange_sig bytea NOT NULL,
    CONSTRAINT merchant_deposit_to_transfer_exchange_sig_check CHECK ((length(exchange_sig) = 64))
);


--
-- Name: TABLE merchant_deposit_to_transfer; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_deposit_to_transfer IS 'Mapping of deposits to (possibly unconfirmed) wire transfers; NOTE: not used yet';


--
-- Name: COLUMN merchant_deposit_to_transfer.execution_time; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_deposit_to_transfer.execution_time IS 'Execution time as claimed by the exchange, roughly matches time seen by merchant';


--
-- Name: merchant_deposits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_deposits (
    deposit_serial bigint NOT NULL,
    order_serial bigint,
    deposit_timestamp bigint NOT NULL,
    coin_pub bytea NOT NULL,
    exchange_url character varying NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    deposit_fee_val bigint NOT NULL,
    deposit_fee_frac integer NOT NULL,
    refund_fee_val bigint NOT NULL,
    refund_fee_frac integer NOT NULL,
    wire_fee_val bigint NOT NULL,
    wire_fee_frac integer NOT NULL,
    signkey_serial bigint NOT NULL,
    exchange_sig bytea NOT NULL,
    account_serial bigint NOT NULL,
    CONSTRAINT merchant_deposits_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT merchant_deposits_exchange_sig_check CHECK ((length(exchange_sig) = 64))
);


--
-- Name: TABLE merchant_deposits; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_deposits IS 'Refunds approved by the merchant (backoffice) logic, excludes abort refunds';


--
-- Name: COLUMN merchant_deposits.deposit_timestamp; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_deposits.deposit_timestamp IS 'Time when the exchange generated the deposit confirmation';


--
-- Name: COLUMN merchant_deposits.wire_fee_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_deposits.wire_fee_val IS 'We MAY want to see if we should try to get this via merchant_exchange_wire_fees (not sure, may be too complicated with the date range, etc.)';


--
-- Name: COLUMN merchant_deposits.signkey_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_deposits.signkey_serial IS 'Online signing key of the exchange on the deposit confirmation';


--
-- Name: COLUMN merchant_deposits.exchange_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_deposits.exchange_sig IS 'Signature of the exchange over the deposit confirmation';


--
-- Name: merchant_deposits_deposit_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.merchant_deposits ALTER COLUMN deposit_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.merchant_deposits_deposit_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_exchange_signing_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_exchange_signing_keys (
    signkey_serial bigint NOT NULL,
    master_pub bytea NOT NULL,
    exchange_pub bytea NOT NULL,
    start_date bigint NOT NULL,
    expire_date bigint NOT NULL,
    end_date bigint NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT merchant_exchange_signing_keys_exchange_pub_check CHECK ((length(exchange_pub) = 32)),
    CONSTRAINT merchant_exchange_signing_keys_master_pub_check CHECK ((length(master_pub) = 32)),
    CONSTRAINT merchant_exchange_signing_keys_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE merchant_exchange_signing_keys; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_exchange_signing_keys IS 'Here we store proofs of the exchange online signing keys being signed by the exchange master key';


--
-- Name: COLUMN merchant_exchange_signing_keys.master_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_exchange_signing_keys.master_pub IS 'Master public key of the exchange with these online signing keys';


--
-- Name: merchant_exchange_signing_keys_signkey_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.merchant_exchange_signing_keys ALTER COLUMN signkey_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.merchant_exchange_signing_keys_signkey_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_exchange_wire_fees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_exchange_wire_fees (
    wirefee_serial bigint NOT NULL,
    master_pub bytea NOT NULL,
    h_wire_method bytea NOT NULL,
    start_date bigint NOT NULL,
    end_date bigint NOT NULL,
    wire_fee_val bigint NOT NULL,
    wire_fee_frac integer NOT NULL,
    closing_fee_val bigint NOT NULL,
    closing_fee_frac integer NOT NULL,
    wad_fee_val bigint NOT NULL,
    wad_fee_frac integer NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT merchant_exchange_wire_fees_h_wire_method_check CHECK ((length(h_wire_method) = 64)),
    CONSTRAINT merchant_exchange_wire_fees_master_pub_check CHECK ((length(master_pub) = 32)),
    CONSTRAINT merchant_exchange_wire_fees_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE merchant_exchange_wire_fees; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_exchange_wire_fees IS 'Here we store proofs of the wire fee structure of the various exchanges';


--
-- Name: COLUMN merchant_exchange_wire_fees.master_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_exchange_wire_fees.master_pub IS 'Master public key of the exchange with these wire fees';


--
-- Name: merchant_exchange_wire_fees_wirefee_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.merchant_exchange_wire_fees ALTER COLUMN wirefee_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.merchant_exchange_wire_fees_wirefee_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_instances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_instances (
    merchant_serial bigint NOT NULL,
    merchant_pub bytea NOT NULL,
    auth_hash bytea,
    auth_salt bytea,
    merchant_id character varying NOT NULL,
    merchant_name character varying NOT NULL,
    address bytea NOT NULL,
    jurisdiction bytea NOT NULL,
    default_max_deposit_fee_val bigint NOT NULL,
    default_max_deposit_fee_frac integer NOT NULL,
    default_max_wire_fee_val bigint NOT NULL,
    default_max_wire_fee_frac integer NOT NULL,
    default_wire_fee_amortization integer NOT NULL,
    default_wire_transfer_delay bigint NOT NULL,
    default_pay_delay bigint NOT NULL,
    CONSTRAINT merchant_instances_auth_hash_check CHECK ((length(auth_hash) = 64)),
    CONSTRAINT merchant_instances_auth_salt_check CHECK ((length(auth_salt) = 32)),
    CONSTRAINT merchant_instances_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


--
-- Name: TABLE merchant_instances; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_instances IS 'all the instances supported by this backend';


--
-- Name: COLUMN merchant_instances.auth_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.auth_hash IS 'hash used for merchant back office Authorization, NULL for no check';


--
-- Name: COLUMN merchant_instances.auth_salt; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.auth_salt IS 'salt to use when hashing Authorization header before comparing with auth_hash';


--
-- Name: COLUMN merchant_instances.merchant_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.merchant_id IS 'identifier of the merchant as used in the base URL (required)';


--
-- Name: COLUMN merchant_instances.merchant_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.merchant_name IS 'legal name of the merchant as a simple string (required)';


--
-- Name: COLUMN merchant_instances.address; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.address IS 'physical address of the merchant as a Location in JSON format (required)';


--
-- Name: COLUMN merchant_instances.jurisdiction; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.jurisdiction IS 'jurisdiction of the merchant as a Location in JSON format (required)';


--
-- Name: merchant_instances_merchant_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.merchant_instances ALTER COLUMN merchant_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.merchant_instances_merchant_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_inventory; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_inventory (
    product_serial bigint NOT NULL,
    merchant_serial bigint NOT NULL,
    product_id character varying NOT NULL,
    description character varying NOT NULL,
    description_i18n bytea NOT NULL,
    unit character varying NOT NULL,
    image bytea NOT NULL,
    taxes bytea NOT NULL,
    price_val bigint NOT NULL,
    price_frac integer NOT NULL,
    total_stock bigint NOT NULL,
    total_sold bigint DEFAULT 0 NOT NULL,
    total_lost bigint DEFAULT 0 NOT NULL,
    address bytea NOT NULL,
    next_restock bigint NOT NULL,
    minimum_age integer DEFAULT 0 NOT NULL
);


--
-- Name: TABLE merchant_inventory; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_inventory IS 'products offered by the merchant (may be incomplete, frontend can override)';


--
-- Name: COLUMN merchant_inventory.description; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.description IS 'Human-readable product description';


--
-- Name: COLUMN merchant_inventory.description_i18n; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.description_i18n IS 'JSON map from IETF BCP 47 language tags to localized descriptions';


--
-- Name: COLUMN merchant_inventory.unit; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.unit IS 'Unit of sale for the product (liters, kilograms, packages)';


--
-- Name: COLUMN merchant_inventory.image; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.image IS 'NOT NULL, but can be 0 bytes; must contain an ImageDataUrl';


--
-- Name: COLUMN merchant_inventory.taxes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.taxes IS 'JSON array containing taxes the merchant pays, must be JSON, but can be just "[]"';


--
-- Name: COLUMN merchant_inventory.price_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.price_val IS 'Current price of one unit of the product';


--
-- Name: COLUMN merchant_inventory.total_stock; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.total_stock IS 'A value of -1 is used for unlimited (electronic good), may never be lowered';


--
-- Name: COLUMN merchant_inventory.total_sold; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.total_sold IS 'Number of products sold, must be below total_stock, non-negative, may never be lowered';


--
-- Name: COLUMN merchant_inventory.total_lost; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.total_lost IS 'Number of products that used to be in stock but were lost (spoiled, damaged), may never be lowered; total_stock >= total_sold + total_lost must always hold';


--
-- Name: COLUMN merchant_inventory.address; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.address IS 'JSON formatted Location of where the product is stocked';


--
-- Name: COLUMN merchant_inventory.next_restock; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.next_restock IS 'GNUnet absolute time indicating when the next restock is expected. 0 for unknown.';


--
-- Name: COLUMN merchant_inventory.minimum_age; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.minimum_age IS 'Minimum age of the customer in years, to be used if an exchange supports the age restriction extension.';


--
-- Name: merchant_inventory_locks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_inventory_locks (
    product_serial bigint NOT NULL,
    lock_uuid bytea NOT NULL,
    total_locked bigint NOT NULL,
    expiration bigint NOT NULL,
    CONSTRAINT merchant_inventory_locks_lock_uuid_check CHECK ((length(lock_uuid) = 16))
);


--
-- Name: TABLE merchant_inventory_locks; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_inventory_locks IS 'locks on inventory helt by shopping carts; note that locks MAY not be honored if merchants increase total_lost for inventory';


--
-- Name: COLUMN merchant_inventory_locks.total_locked; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory_locks.total_locked IS 'how many units of the product does this lock reserve';


--
-- Name: COLUMN merchant_inventory_locks.expiration; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory_locks.expiration IS 'when does this lock automatically expire (if no order is created)';


--
-- Name: merchant_inventory_product_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.merchant_inventory ALTER COLUMN product_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.merchant_inventory_product_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_keys (
    merchant_priv bytea NOT NULL,
    merchant_serial bigint NOT NULL,
    CONSTRAINT merchant_keys_merchant_priv_check CHECK ((length(merchant_priv) = 32))
);


--
-- Name: TABLE merchant_keys; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_keys IS 'private keys of instances that have not been deleted';


--
-- Name: merchant_kyc; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_kyc (
    kyc_serial_id bigint NOT NULL,
    kyc_timestamp bigint NOT NULL,
    kyc_ok boolean DEFAULT false NOT NULL,
    exchange_sig bytea,
    exchange_pub bytea,
    exchange_kyc_serial bigint DEFAULT 0 NOT NULL,
    account_serial bigint NOT NULL,
    exchange_url character varying NOT NULL,
    CONSTRAINT merchant_kyc_exchange_pub_check CHECK ((length(exchange_pub) = 32)),
    CONSTRAINT merchant_kyc_exchange_sig_check CHECK ((length(exchange_sig) = 64))
);


--
-- Name: TABLE merchant_kyc; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_kyc IS 'Status of the KYC process of a merchant account at an exchange';


--
-- Name: COLUMN merchant_kyc.kyc_timestamp; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_kyc.kyc_timestamp IS 'Last time we checked our KYC status at the exchange. Useful to re-check if the status is very stale. Also the timestamp used for the exchange signature (if present).';


--
-- Name: COLUMN merchant_kyc.kyc_ok; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_kyc.kyc_ok IS 'true if the KYC check was passed successfully';


--
-- Name: COLUMN merchant_kyc.exchange_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_kyc.exchange_sig IS 'signature of the exchange affirming the KYC passed (or NULL if exchange does not require KYC or not kyc_ok)';


--
-- Name: COLUMN merchant_kyc.exchange_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_kyc.exchange_pub IS 'public key used with exchange_sig (or NULL if exchange_sig is NULL)';


--
-- Name: COLUMN merchant_kyc.exchange_kyc_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_kyc.exchange_kyc_serial IS 'Number to use in the KYC-endpoints of the exchange to check the KYC status or begin the KYC process. 0 if we do not know it yet.';


--
-- Name: COLUMN merchant_kyc.account_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_kyc.account_serial IS 'Which bank account of the merchant is the KYC status for';


--
-- Name: COLUMN merchant_kyc.exchange_url; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_kyc.exchange_url IS 'Which exchange base URL is this KYC status valid for';


--
-- Name: merchant_kyc_kyc_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.merchant_kyc ALTER COLUMN kyc_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.merchant_kyc_kyc_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_order_locks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_order_locks (
    product_serial bigint NOT NULL,
    total_locked bigint NOT NULL,
    order_serial bigint NOT NULL
);


--
-- Name: TABLE merchant_order_locks; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_order_locks IS 'locks on orders awaiting claim and payment; note that locks MAY not be honored if merchants increase total_lost for inventory';


--
-- Name: COLUMN merchant_order_locks.total_locked; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_order_locks.total_locked IS 'how many units of the product does this lock reserve';


--
-- Name: merchant_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_orders (
    order_serial bigint NOT NULL,
    merchant_serial bigint NOT NULL,
    order_id character varying NOT NULL,
    claim_token bytea NOT NULL,
    h_post_data bytea NOT NULL,
    pay_deadline bigint NOT NULL,
    creation_time bigint NOT NULL,
    contract_terms bytea NOT NULL,
    CONSTRAINT merchant_orders_claim_token_check CHECK ((length(claim_token) = 16)),
    CONSTRAINT merchant_orders_h_post_data_check CHECK ((length(h_post_data) = 64))
);


--
-- Name: TABLE merchant_orders; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_orders IS 'Orders we offered to a customer, but that have not yet been claimed';


--
-- Name: COLUMN merchant_orders.merchant_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_orders.merchant_serial IS 'Identifies the instance offering the contract';


--
-- Name: COLUMN merchant_orders.claim_token; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_orders.claim_token IS 'Token optionally used to authorize the wallet to claim the order. All zeros (not NULL) if not used';


--
-- Name: COLUMN merchant_orders.h_post_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_orders.h_post_data IS 'Hash of the POST request that created this order, for idempotency checks';


--
-- Name: COLUMN merchant_orders.pay_deadline; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_orders.pay_deadline IS 'How long is the offer valid. After this time, the order can be garbage collected';


--
-- Name: COLUMN merchant_orders.contract_terms; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_orders.contract_terms IS 'Claiming changes the contract_terms, hence we have no hash of the terms in this table';


--
-- Name: merchant_orders_order_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.merchant_orders ALTER COLUMN order_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.merchant_orders_order_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_refund_proofs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_refund_proofs (
    refund_serial bigint NOT NULL,
    exchange_sig bytea NOT NULL,
    signkey_serial bigint NOT NULL,
    CONSTRAINT merchant_refund_proofs_exchange_sig_check CHECK ((length(exchange_sig) = 64))
);


--
-- Name: TABLE merchant_refund_proofs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_refund_proofs IS 'Refunds confirmed by the exchange (not all approved refunds are grabbed by the wallet)';


--
-- Name: merchant_refunds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_refunds (
    refund_serial bigint NOT NULL,
    order_serial bigint NOT NULL,
    rtransaction_id bigint NOT NULL,
    refund_timestamp bigint NOT NULL,
    coin_pub bytea NOT NULL,
    reason character varying NOT NULL,
    refund_amount_val bigint NOT NULL,
    refund_amount_frac integer NOT NULL
);


--
-- Name: COLUMN merchant_refunds.rtransaction_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_refunds.rtransaction_id IS 'Needed for uniqueness in case a refund is increased for the same order';


--
-- Name: COLUMN merchant_refunds.refund_timestamp; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_refunds.refund_timestamp IS 'Needed for grouping of refunds in the wallet UI; has no semantics in the protocol (only for UX), but should be from the time when the merchant internally approved the refund';


--
-- Name: merchant_refunds_refund_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.merchant_refunds ALTER COLUMN refund_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.merchant_refunds_refund_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_tip_pickup_signatures; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tip_pickup_signatures (
    pickup_serial bigint NOT NULL,
    coin_offset integer NOT NULL,
    blind_sig bytea NOT NULL
);


--
-- Name: TABLE merchant_tip_pickup_signatures; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_tip_pickup_signatures IS 'blind signatures we got from the exchange during the tip pickup';


--
-- Name: merchant_tip_pickups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tip_pickups (
    pickup_serial bigint NOT NULL,
    tip_serial bigint NOT NULL,
    pickup_id bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    CONSTRAINT merchant_tip_pickups_pickup_id_check CHECK ((length(pickup_id) = 64))
);


--
-- Name: TABLE merchant_tip_pickups; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_tip_pickups IS 'tips that have been picked up';


--
-- Name: merchant_tip_pickups_pickup_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.merchant_tip_pickups ALTER COLUMN pickup_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.merchant_tip_pickups_pickup_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_tip_reserve_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tip_reserve_keys (
    reserve_serial bigint NOT NULL,
    reserve_priv bytea NOT NULL,
    exchange_url character varying NOT NULL,
    payto_uri character varying,
    CONSTRAINT merchant_tip_reserve_keys_reserve_priv_check CHECK ((length(reserve_priv) = 32))
);


--
-- Name: COLUMN merchant_tip_reserve_keys.payto_uri; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tip_reserve_keys.payto_uri IS 'payto:// URI used to fund the reserve, may be NULL once reserve is funded';


--
-- Name: merchant_tip_reserves; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tip_reserves (
    reserve_serial bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    merchant_serial bigint NOT NULL,
    creation_time bigint NOT NULL,
    expiration bigint NOT NULL,
    merchant_initial_balance_val bigint NOT NULL,
    merchant_initial_balance_frac integer NOT NULL,
    exchange_initial_balance_val bigint DEFAULT 0 NOT NULL,
    exchange_initial_balance_frac integer DEFAULT 0 NOT NULL,
    tips_committed_val bigint DEFAULT 0 NOT NULL,
    tips_committed_frac integer DEFAULT 0 NOT NULL,
    tips_picked_up_val bigint DEFAULT 0 NOT NULL,
    tips_picked_up_frac integer DEFAULT 0 NOT NULL,
    CONSTRAINT merchant_tip_reserves_reserve_pub_check CHECK ((length(reserve_pub) = 32))
);


--
-- Name: TABLE merchant_tip_reserves; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_tip_reserves IS 'private keys of reserves that have not been deleted';


--
-- Name: COLUMN merchant_tip_reserves.expiration; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tip_reserves.expiration IS 'FIXME: EXCHANGE API needs to tell us when reserves close if we are to compute this';


--
-- Name: COLUMN merchant_tip_reserves.merchant_initial_balance_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tip_reserves.merchant_initial_balance_val IS 'Set to the initial balance the merchant told us when creating the reserve';


--
-- Name: COLUMN merchant_tip_reserves.exchange_initial_balance_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tip_reserves.exchange_initial_balance_val IS 'Set to the initial balance the exchange told us when we queried the reserve status';


--
-- Name: COLUMN merchant_tip_reserves.tips_committed_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tip_reserves.tips_committed_val IS 'Amount of outstanding approved tips that have not been picked up';


--
-- Name: COLUMN merchant_tip_reserves.tips_picked_up_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tip_reserves.tips_picked_up_val IS 'Total amount tips that have been picked up from this reserve';


--
-- Name: merchant_tip_reserves_reserve_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.merchant_tip_reserves ALTER COLUMN reserve_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.merchant_tip_reserves_reserve_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_tips; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tips (
    tip_serial bigint NOT NULL,
    reserve_serial bigint NOT NULL,
    tip_id bytea NOT NULL,
    justification character varying NOT NULL,
    next_url character varying NOT NULL,
    expiration bigint NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    picked_up_val bigint DEFAULT 0 NOT NULL,
    picked_up_frac integer DEFAULT 0 NOT NULL,
    was_picked_up boolean DEFAULT false NOT NULL,
    CONSTRAINT merchant_tips_tip_id_check CHECK ((length(tip_id) = 64))
);


--
-- Name: TABLE merchant_tips; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_tips IS 'tips that have been authorized';


--
-- Name: COLUMN merchant_tips.reserve_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tips.reserve_serial IS 'Reserve from which this tip is funded';


--
-- Name: COLUMN merchant_tips.expiration; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tips.expiration IS 'by when does the client have to pick up the tip';


--
-- Name: COLUMN merchant_tips.amount_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tips.amount_val IS 'total transaction cost for all coins including withdraw fees';


--
-- Name: COLUMN merchant_tips.picked_up_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tips.picked_up_val IS 'Tip amount left to be picked up';


--
-- Name: merchant_tips_tip_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.merchant_tips ALTER COLUMN tip_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.merchant_tips_tip_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_transfer_signatures; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_transfer_signatures (
    credit_serial bigint NOT NULL,
    signkey_serial bigint NOT NULL,
    wire_fee_val bigint NOT NULL,
    wire_fee_frac integer NOT NULL,
    credit_amount_val bigint NOT NULL,
    credit_amount_frac integer NOT NULL,
    execution_time bigint NOT NULL,
    exchange_sig bytea NOT NULL,
    CONSTRAINT merchant_transfer_signatures_exchange_sig_check CHECK ((length(exchange_sig) = 64))
);


--
-- Name: TABLE merchant_transfer_signatures; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_transfer_signatures IS 'table represents the main information returned from the /transfer request to the exchange.';


--
-- Name: COLUMN merchant_transfer_signatures.credit_amount_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_transfer_signatures.credit_amount_val IS 'actual value of the (aggregated) wire transfer, excluding the wire fee, according to the exchange';


--
-- Name: COLUMN merchant_transfer_signatures.execution_time; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_transfer_signatures.execution_time IS 'Execution time as claimed by the exchange, roughly matches time seen by merchant';


--
-- Name: merchant_transfer_to_coin; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_transfer_to_coin (
    deposit_serial bigint NOT NULL,
    credit_serial bigint NOT NULL,
    offset_in_exchange_list bigint NOT NULL,
    exchange_deposit_value_val bigint NOT NULL,
    exchange_deposit_value_frac integer NOT NULL,
    exchange_deposit_fee_val bigint NOT NULL,
    exchange_deposit_fee_frac integer NOT NULL
);


--
-- Name: TABLE merchant_transfer_to_coin; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_transfer_to_coin IS 'Mapping of (credit) transfers to (deposited) coins';


--
-- Name: COLUMN merchant_transfer_to_coin.exchange_deposit_value_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_transfer_to_coin.exchange_deposit_value_val IS 'Deposit value as claimed by the exchange, should match our values in merchant_deposits minus refunds';


--
-- Name: COLUMN merchant_transfer_to_coin.exchange_deposit_fee_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_transfer_to_coin.exchange_deposit_fee_val IS 'Deposit value as claimed by the exchange, should match our values in merchant_deposits';


--
-- Name: merchant_transfers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_transfers (
    credit_serial bigint NOT NULL,
    exchange_url character varying NOT NULL,
    wtid bytea,
    credit_amount_val bigint NOT NULL,
    credit_amount_frac integer NOT NULL,
    account_serial bigint NOT NULL,
    verified boolean DEFAULT false NOT NULL,
    confirmed boolean DEFAULT false NOT NULL,
    CONSTRAINT merchant_transfers_wtid_check CHECK ((length(wtid) = 32))
);


--
-- Name: TABLE merchant_transfers; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_transfers IS 'table represents the information provided by the (trusted) merchant about incoming wire transfers';


--
-- Name: COLUMN merchant_transfers.credit_amount_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_transfers.credit_amount_val IS 'actual value of the (aggregated) wire transfer, excluding the wire fee, according to the merchant';


--
-- Name: COLUMN merchant_transfers.verified; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_transfers.verified IS 'true once we got an acceptable response from the exchange for this transfer';


--
-- Name: COLUMN merchant_transfers.confirmed; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_transfers.confirmed IS 'true once the merchant confirmed that this transfer was received';


--
-- Name: merchant_transfers_credit_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.merchant_transfers ALTER COLUMN credit_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.merchant_transfers_credit_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: prewire; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.prewire (
    prewire_uuid bigint NOT NULL,
    wire_method text NOT NULL,
    finished boolean DEFAULT false NOT NULL,
    failed boolean DEFAULT false NOT NULL,
    buf bytea NOT NULL
)
PARTITION BY HASH (prewire_uuid);


--
-- Name: TABLE prewire; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.prewire IS 'pre-commit data for wire transfers we are about to execute';


--
-- Name: COLUMN prewire.finished; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prewire.finished IS 'set to TRUE once bank confirmed receiving the wire transfer request';


--
-- Name: COLUMN prewire.failed; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prewire.failed IS 'set to TRUE if the bank responded with a non-transient failure to our transfer request';


--
-- Name: COLUMN prewire.buf; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prewire.buf IS 'serialized data to send to the bank to execute the wire transfer';


--
-- Name: prewire_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.prewire_default (
    prewire_uuid bigint NOT NULL,
    wire_method text NOT NULL,
    finished boolean DEFAULT false NOT NULL,
    failed boolean DEFAULT false NOT NULL,
    buf bytea NOT NULL
);
ALTER TABLE ONLY public.prewire ATTACH PARTITION public.prewire_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: prewire_prewire_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.prewire ALTER COLUMN prewire_uuid ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.prewire_prewire_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: recoup; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recoup (
    recoup_uuid bigint NOT NULL,
    coin_pub bytea NOT NULL,
    coin_sig bytea NOT NULL,
    coin_blind bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    recoup_timestamp bigint NOT NULL,
    reserve_out_serial_id bigint NOT NULL,
    CONSTRAINT recoup_coin_blind_check CHECK ((length(coin_blind) = 32)),
    CONSTRAINT recoup_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT recoup_coin_sig_check CHECK ((length(coin_sig) = 64))
)
PARTITION BY HASH (coin_pub);


--
-- Name: TABLE recoup; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.recoup IS 'Information about recoups that were executed between a coin and a reserve. In this type of recoup, the amount is credited back to the reserve from which the coin originated.';


--
-- Name: COLUMN recoup.coin_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.recoup.coin_pub IS 'Coin that is being debited in the recoup. Do not CASCADE ON DROP on the coin_pub, as we may keep the coin alive!';


--
-- Name: COLUMN recoup.coin_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.recoup.coin_sig IS 'Signature by the coin affirming the recoup, of type TALER_SIGNATURE_WALLET_COIN_RECOUP';


--
-- Name: COLUMN recoup.coin_blind; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.recoup.coin_blind IS 'Denomination blinding key used when creating the blinded coin from the planchet. Secret revealed during the recoup to provide the linkage between the coin and the withdraw operation.';


--
-- Name: COLUMN recoup.reserve_out_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.recoup.reserve_out_serial_id IS 'Identifies the h_blind_ev of the recouped coin and provides the link to the credited reserve.';


--
-- Name: recoup_by_reserve; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recoup_by_reserve (
    reserve_out_serial_id bigint NOT NULL,
    coin_pub bytea,
    CONSTRAINT recoup_by_reserve_coin_pub_check CHECK ((length(coin_pub) = 32))
)
PARTITION BY HASH (reserve_out_serial_id);


--
-- Name: TABLE recoup_by_reserve; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.recoup_by_reserve IS 'Information in this table is strictly redundant with that of recoup, but saved by a different primary key for fast lookups by reserve_out_serial_id.';


--
-- Name: recoup_by_reserve_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recoup_by_reserve_default (
    reserve_out_serial_id bigint NOT NULL,
    coin_pub bytea,
    CONSTRAINT recoup_by_reserve_coin_pub_check CHECK ((length(coin_pub) = 32))
);
ALTER TABLE ONLY public.recoup_by_reserve ATTACH PARTITION public.recoup_by_reserve_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: recoup_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recoup_default (
    recoup_uuid bigint NOT NULL,
    coin_pub bytea NOT NULL,
    coin_sig bytea NOT NULL,
    coin_blind bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    recoup_timestamp bigint NOT NULL,
    reserve_out_serial_id bigint NOT NULL,
    CONSTRAINT recoup_coin_blind_check CHECK ((length(coin_blind) = 32)),
    CONSTRAINT recoup_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT recoup_coin_sig_check CHECK ((length(coin_sig) = 64))
);
ALTER TABLE ONLY public.recoup ATTACH PARTITION public.recoup_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: recoup_recoup_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.recoup ALTER COLUMN recoup_uuid ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.recoup_recoup_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: recoup_refresh; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recoup_refresh (
    recoup_refresh_uuid bigint NOT NULL,
    coin_pub bytea NOT NULL,
    known_coin_id bigint NOT NULL,
    coin_sig bytea NOT NULL,
    coin_blind bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    recoup_timestamp bigint NOT NULL,
    rrc_serial bigint NOT NULL,
    CONSTRAINT recoup_refresh_coin_blind_check CHECK ((length(coin_blind) = 32)),
    CONSTRAINT recoup_refresh_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT recoup_refresh_coin_sig_check CHECK ((length(coin_sig) = 64))
)
PARTITION BY HASH (coin_pub);


--
-- Name: TABLE recoup_refresh; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.recoup_refresh IS 'Table of coins that originated from a refresh operation and that were recouped. Links the (fresh) coin to the melted operation (and thus the old coin). A recoup on a refreshed coin credits the old coin and debits the fresh coin.';


--
-- Name: COLUMN recoup_refresh.coin_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.recoup_refresh.coin_pub IS 'Refreshed coin of a revoked denomination where the residual value is credited to the old coin. Do not CASCADE ON DROP on the coin_pub, as we may keep the coin alive!';


--
-- Name: COLUMN recoup_refresh.known_coin_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.recoup_refresh.known_coin_id IS 'FIXME: (To be) used for garbage collection (in the future)';


--
-- Name: COLUMN recoup_refresh.coin_blind; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.recoup_refresh.coin_blind IS 'Denomination blinding key used when creating the blinded coin from the planchet. Secret revealed during the recoup to provide the linkage between the coin and the refresh operation.';


--
-- Name: COLUMN recoup_refresh.rrc_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.recoup_refresh.rrc_serial IS 'Link to the refresh operation. Also identifies the h_blind_ev of the recouped coin (as h_coin_ev).';


--
-- Name: recoup_refresh_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recoup_refresh_default (
    recoup_refresh_uuid bigint NOT NULL,
    coin_pub bytea NOT NULL,
    known_coin_id bigint NOT NULL,
    coin_sig bytea NOT NULL,
    coin_blind bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    recoup_timestamp bigint NOT NULL,
    rrc_serial bigint NOT NULL,
    CONSTRAINT recoup_refresh_coin_blind_check CHECK ((length(coin_blind) = 32)),
    CONSTRAINT recoup_refresh_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT recoup_refresh_coin_sig_check CHECK ((length(coin_sig) = 64))
);
ALTER TABLE ONLY public.recoup_refresh ATTACH PARTITION public.recoup_refresh_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: recoup_refresh_recoup_refresh_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.recoup_refresh ALTER COLUMN recoup_refresh_uuid ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.recoup_refresh_recoup_refresh_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: refresh_commitments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refresh_commitments (
    melt_serial_id bigint NOT NULL,
    rc bytea NOT NULL,
    old_coin_pub bytea NOT NULL,
    old_coin_sig bytea NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    noreveal_index integer NOT NULL,
    CONSTRAINT refresh_commitments_old_coin_sig_check CHECK ((length(old_coin_sig) = 64)),
    CONSTRAINT refresh_commitments_rc_check CHECK ((length(rc) = 64))
)
PARTITION BY HASH (rc);


--
-- Name: TABLE refresh_commitments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.refresh_commitments IS 'Commitments made when melting coins and the gamma value chosen by the exchange.';


--
-- Name: COLUMN refresh_commitments.rc; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_commitments.rc IS 'Commitment made by the client, hash over the various client inputs in the cut-and-choose protocol';


--
-- Name: COLUMN refresh_commitments.old_coin_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_commitments.old_coin_pub IS 'Coin being melted in the refresh process.';


--
-- Name: COLUMN refresh_commitments.noreveal_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_commitments.noreveal_index IS 'The gamma value chosen by the exchange in the cut-and-choose protocol';


--
-- Name: refresh_commitments_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refresh_commitments_default (
    melt_serial_id bigint NOT NULL,
    rc bytea NOT NULL,
    old_coin_pub bytea NOT NULL,
    old_coin_sig bytea NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    noreveal_index integer NOT NULL,
    CONSTRAINT refresh_commitments_old_coin_sig_check CHECK ((length(old_coin_sig) = 64)),
    CONSTRAINT refresh_commitments_rc_check CHECK ((length(rc) = 64))
);
ALTER TABLE ONLY public.refresh_commitments ATTACH PARTITION public.refresh_commitments_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.refresh_commitments ALTER COLUMN melt_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.refresh_commitments_melt_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: refresh_revealed_coins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refresh_revealed_coins (
    rrc_serial bigint NOT NULL,
    melt_serial_id bigint NOT NULL,
    freshcoin_index integer NOT NULL,
    link_sig bytea NOT NULL,
    denominations_serial bigint NOT NULL,
    coin_ev bytea NOT NULL,
    h_coin_ev bytea NOT NULL,
    ev_sig bytea NOT NULL,
    ewv bytea NOT NULL,
    CONSTRAINT refresh_revealed_coins_h_coin_ev_check CHECK ((length(h_coin_ev) = 64)),
    CONSTRAINT refresh_revealed_coins_link_sig_check CHECK ((length(link_sig) = 64))
)
PARTITION BY HASH (melt_serial_id);


--
-- Name: TABLE refresh_revealed_coins; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.refresh_revealed_coins IS 'Revelations about the new coins that are to be created during a melting session.';


--
-- Name: COLUMN refresh_revealed_coins.rrc_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.rrc_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: COLUMN refresh_revealed_coins.melt_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.melt_serial_id IS 'Identifies the refresh commitment (rc) of the melt operation.';


--
-- Name: COLUMN refresh_revealed_coins.freshcoin_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.freshcoin_index IS 'index of the fresh coin being created (one melt operation may result in multiple fresh coins)';


--
-- Name: COLUMN refresh_revealed_coins.coin_ev; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.coin_ev IS 'envelope of the new coin to be signed';


--
-- Name: COLUMN refresh_revealed_coins.h_coin_ev; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.h_coin_ev IS 'hash of the envelope of the new coin to be signed (for lookups)';


--
-- Name: COLUMN refresh_revealed_coins.ev_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.ev_sig IS 'exchange signature over the envelope';


--
-- Name: COLUMN refresh_revealed_coins.ewv; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.ewv IS 'exchange contributed values in the creation of the fresh coin (see /csr)';


--
-- Name: refresh_revealed_coins_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refresh_revealed_coins_default (
    rrc_serial bigint NOT NULL,
    melt_serial_id bigint NOT NULL,
    freshcoin_index integer NOT NULL,
    link_sig bytea NOT NULL,
    denominations_serial bigint NOT NULL,
    coin_ev bytea NOT NULL,
    h_coin_ev bytea NOT NULL,
    ev_sig bytea NOT NULL,
    ewv bytea NOT NULL,
    CONSTRAINT refresh_revealed_coins_h_coin_ev_check CHECK ((length(h_coin_ev) = 64)),
    CONSTRAINT refresh_revealed_coins_link_sig_check CHECK ((length(link_sig) = 64))
);
ALTER TABLE ONLY public.refresh_revealed_coins ATTACH PARTITION public.refresh_revealed_coins_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: refresh_revealed_coins_rrc_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.refresh_revealed_coins ALTER COLUMN rrc_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.refresh_revealed_coins_rrc_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: refresh_transfer_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refresh_transfer_keys (
    rtc_serial bigint NOT NULL,
    melt_serial_id bigint NOT NULL,
    transfer_pub bytea NOT NULL,
    transfer_privs bytea NOT NULL,
    CONSTRAINT refresh_transfer_keys_transfer_pub_check CHECK ((length(transfer_pub) = 32))
)
PARTITION BY HASH (melt_serial_id);


--
-- Name: TABLE refresh_transfer_keys; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.refresh_transfer_keys IS 'Transfer keys of a refresh operation (the data revealed to the exchange).';


--
-- Name: COLUMN refresh_transfer_keys.rtc_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_transfer_keys.rtc_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: COLUMN refresh_transfer_keys.melt_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_transfer_keys.melt_serial_id IS 'Identifies the refresh commitment (rc) of the operation.';


--
-- Name: COLUMN refresh_transfer_keys.transfer_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_transfer_keys.transfer_pub IS 'transfer public key for the gamma index';


--
-- Name: COLUMN refresh_transfer_keys.transfer_privs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_transfer_keys.transfer_privs IS 'array of TALER_CNC_KAPPA - 1 transfer private keys that have been revealed, with the gamma entry being skipped';


--
-- Name: refresh_transfer_keys_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refresh_transfer_keys_default (
    rtc_serial bigint NOT NULL,
    melt_serial_id bigint NOT NULL,
    transfer_pub bytea NOT NULL,
    transfer_privs bytea NOT NULL,
    CONSTRAINT refresh_transfer_keys_transfer_pub_check CHECK ((length(transfer_pub) = 32))
);
ALTER TABLE ONLY public.refresh_transfer_keys ATTACH PARTITION public.refresh_transfer_keys_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: refresh_transfer_keys_rtc_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.refresh_transfer_keys ALTER COLUMN rtc_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.refresh_transfer_keys_rtc_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: refunds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refunds (
    refund_serial_id bigint NOT NULL,
    shard bigint NOT NULL,
    deposit_serial_id bigint NOT NULL,
    merchant_sig bytea NOT NULL,
    rtransaction_id bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    CONSTRAINT refunds_merchant_sig_check CHECK ((length(merchant_sig) = 64))
)
PARTITION BY HASH (shard);


--
-- Name: TABLE refunds; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.refunds IS 'Data on coins that were refunded. Technically, refunds always apply against specific deposit operations involving a coin. The combination of coin_pub, merchant_pub, h_contract_terms and rtransaction_id MUST be unique, and we usually select by coin_pub so that one goes first.';


--
-- Name: COLUMN refunds.deposit_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refunds.deposit_serial_id IS 'Identifies ONLY the merchant_pub, h_contract_terms and coin_pub. Multiple deposits may match a refund, this only identifies one of them.';


--
-- Name: COLUMN refunds.rtransaction_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refunds.rtransaction_id IS 'used by the merchant to make refunds unique in case the same coin for the same deposit gets a subsequent (higher) refund';


--
-- Name: refunds_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refunds_default (
    refund_serial_id bigint NOT NULL,
    shard bigint NOT NULL,
    deposit_serial_id bigint NOT NULL,
    merchant_sig bytea NOT NULL,
    rtransaction_id bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    CONSTRAINT refunds_merchant_sig_check CHECK ((length(merchant_sig) = 64))
);
ALTER TABLE ONLY public.refunds ATTACH PARTITION public.refunds_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: refunds_refund_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.refunds ALTER COLUMN refund_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.refunds_refund_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: reserves; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserves (
    reserve_uuid bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    current_balance_val bigint NOT NULL,
    current_balance_frac integer NOT NULL,
    expiration_date bigint NOT NULL,
    gc_date bigint NOT NULL,
    CONSTRAINT reserves_reserve_pub_check CHECK ((length(reserve_pub) = 32))
)
PARTITION BY HASH (reserve_pub);


--
-- Name: TABLE reserves; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.reserves IS 'Summarizes the balance of a reserve. Updated when new funds are added or withdrawn.';


--
-- Name: COLUMN reserves.reserve_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves.reserve_pub IS 'EdDSA public key of the reserve. Knowledge of the private key implies ownership over the balance.';


--
-- Name: COLUMN reserves.current_balance_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves.current_balance_val IS 'Current balance remaining with the reserve';


--
-- Name: COLUMN reserves.expiration_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves.expiration_date IS 'Used to trigger closing of reserves that have not been drained after some time';


--
-- Name: COLUMN reserves.gc_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves.gc_date IS 'Used to forget all information about a reserve during garbage collection';


--
-- Name: reserves_close; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserves_close (
    close_uuid bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    execution_date bigint NOT NULL,
    wtid bytea NOT NULL,
    wire_target_h_payto bytea,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    closing_fee_val bigint NOT NULL,
    closing_fee_frac integer NOT NULL,
    CONSTRAINT reserves_close_wire_target_h_payto_check CHECK ((length(wire_target_h_payto) = 32)),
    CONSTRAINT reserves_close_wtid_check CHECK ((length(wtid) = 32))
)
PARTITION BY HASH (reserve_pub);


--
-- Name: TABLE reserves_close; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.reserves_close IS 'wire transfers executed by the reserve to close reserves';


--
-- Name: COLUMN reserves_close.wire_target_h_payto; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves_close.wire_target_h_payto IS 'Identifies the credited bank account (and KYC status). Note that closing does not depend on KYC.';


--
-- Name: reserves_close_close_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.reserves_close ALTER COLUMN close_uuid ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.reserves_close_close_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: reserves_close_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserves_close_default (
    close_uuid bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    execution_date bigint NOT NULL,
    wtid bytea NOT NULL,
    wire_target_h_payto bytea,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    closing_fee_val bigint NOT NULL,
    closing_fee_frac integer NOT NULL,
    CONSTRAINT reserves_close_wire_target_h_payto_check CHECK ((length(wire_target_h_payto) = 32)),
    CONSTRAINT reserves_close_wtid_check CHECK ((length(wtid) = 32))
);
ALTER TABLE ONLY public.reserves_close ATTACH PARTITION public.reserves_close_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: reserves_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserves_default (
    reserve_uuid bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    current_balance_val bigint NOT NULL,
    current_balance_frac integer NOT NULL,
    expiration_date bigint NOT NULL,
    gc_date bigint NOT NULL,
    CONSTRAINT reserves_reserve_pub_check CHECK ((length(reserve_pub) = 32))
);
ALTER TABLE ONLY public.reserves ATTACH PARTITION public.reserves_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: reserves_in; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserves_in (
    reserve_in_serial_id bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    wire_reference bigint NOT NULL,
    credit_val bigint NOT NULL,
    credit_frac integer NOT NULL,
    wire_source_h_payto bytea,
    exchange_account_section text NOT NULL,
    execution_date bigint NOT NULL,
    CONSTRAINT reserves_in_wire_source_h_payto_check CHECK ((length(wire_source_h_payto) = 32))
)
PARTITION BY HASH (reserve_pub);


--
-- Name: TABLE reserves_in; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.reserves_in IS 'list of transfers of funds into the reserves, one per incoming wire transfer';


--
-- Name: COLUMN reserves_in.reserve_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves_in.reserve_pub IS 'Public key of the reserve. Private key signifies ownership of the remaining balance.';


--
-- Name: COLUMN reserves_in.credit_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves_in.credit_val IS 'Amount that was transferred into the reserve';


--
-- Name: COLUMN reserves_in.wire_source_h_payto; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves_in.wire_source_h_payto IS 'Identifies the debited bank account and KYC status';


--
-- Name: reserves_in_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserves_in_default (
    reserve_in_serial_id bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    wire_reference bigint NOT NULL,
    credit_val bigint NOT NULL,
    credit_frac integer NOT NULL,
    wire_source_h_payto bytea,
    exchange_account_section text NOT NULL,
    execution_date bigint NOT NULL,
    CONSTRAINT reserves_in_wire_source_h_payto_check CHECK ((length(wire_source_h_payto) = 32))
);
ALTER TABLE ONLY public.reserves_in ATTACH PARTITION public.reserves_in_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: reserves_in_reserve_in_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.reserves_in ALTER COLUMN reserve_in_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.reserves_in_reserve_in_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: reserves_out; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserves_out (
    reserve_out_serial_id bigint NOT NULL,
    h_blind_ev bytea,
    denominations_serial bigint NOT NULL,
    denom_sig bytea NOT NULL,
    reserve_uuid bigint NOT NULL,
    reserve_sig bytea NOT NULL,
    execution_date bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    CONSTRAINT reserves_out_h_blind_ev_check CHECK ((length(h_blind_ev) = 64)),
    CONSTRAINT reserves_out_reserve_sig_check CHECK ((length(reserve_sig) = 64))
)
PARTITION BY HASH (h_blind_ev);


--
-- Name: TABLE reserves_out; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.reserves_out IS 'Withdraw operations performed on reserves.';


--
-- Name: COLUMN reserves_out.h_blind_ev; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves_out.h_blind_ev IS 'Hash of the blinded coin, used as primary key here so that broken clients that use a non-random coin or blinding factor fail to withdraw (otherwise they would fail on deposit when the coin is not unique there).';


--
-- Name: COLUMN reserves_out.denominations_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves_out.denominations_serial IS 'We do not CASCADE ON DELETE here, we may keep the denomination data alive';


--
-- Name: reserves_out_by_reserve; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserves_out_by_reserve (
    reserve_uuid bigint NOT NULL,
    h_blind_ev bytea,
    CONSTRAINT reserves_out_by_reserve_h_blind_ev_check CHECK ((length(h_blind_ev) = 64))
)
PARTITION BY HASH (reserve_uuid);


--
-- Name: TABLE reserves_out_by_reserve; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.reserves_out_by_reserve IS 'Information in this table is strictly redundant with that of reserves_out, but saved by a different primary key for fast lookups by reserve public key/uuid.';


--
-- Name: reserves_out_by_reserve_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserves_out_by_reserve_default (
    reserve_uuid bigint NOT NULL,
    h_blind_ev bytea,
    CONSTRAINT reserves_out_by_reserve_h_blind_ev_check CHECK ((length(h_blind_ev) = 64))
);
ALTER TABLE ONLY public.reserves_out_by_reserve ATTACH PARTITION public.reserves_out_by_reserve_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: reserves_out_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserves_out_default (
    reserve_out_serial_id bigint NOT NULL,
    h_blind_ev bytea,
    denominations_serial bigint NOT NULL,
    denom_sig bytea NOT NULL,
    reserve_uuid bigint NOT NULL,
    reserve_sig bytea NOT NULL,
    execution_date bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    CONSTRAINT reserves_out_h_blind_ev_check CHECK ((length(h_blind_ev) = 64)),
    CONSTRAINT reserves_out_reserve_sig_check CHECK ((length(reserve_sig) = 64))
);
ALTER TABLE ONLY public.reserves_out ATTACH PARTITION public.reserves_out_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.reserves_out ALTER COLUMN reserve_out_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.reserves_out_reserve_out_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.reserves ALTER COLUMN reserve_uuid ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.reserves_reserve_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: revolving_work_shards; Type: TABLE; Schema: public; Owner: -
--

CREATE UNLOGGED TABLE public.revolving_work_shards (
    shard_serial_id bigint NOT NULL,
    last_attempt bigint NOT NULL,
    start_row integer NOT NULL,
    end_row integer NOT NULL,
    active boolean DEFAULT false NOT NULL,
    job_name character varying NOT NULL
);


--
-- Name: TABLE revolving_work_shards; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.revolving_work_shards IS 'coordinates work between multiple processes working on the same job with partitions that need to be repeatedly processed; unlogged because on system crashes the locks represented by this table will have to be cleared anyway, typically using "taler-exchange-dbinit -s"';


--
-- Name: COLUMN revolving_work_shards.shard_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revolving_work_shards.shard_serial_id IS 'unique serial number identifying the shard';


--
-- Name: COLUMN revolving_work_shards.last_attempt; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revolving_work_shards.last_attempt IS 'last time a worker attempted to work on the shard';


--
-- Name: COLUMN revolving_work_shards.start_row; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revolving_work_shards.start_row IS 'row at which the shard scope starts, inclusive';


--
-- Name: COLUMN revolving_work_shards.end_row; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revolving_work_shards.end_row IS 'row at which the shard scope ends, exclusive';


--
-- Name: COLUMN revolving_work_shards.active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revolving_work_shards.active IS 'set to TRUE when a worker is active on the shard';


--
-- Name: COLUMN revolving_work_shards.job_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revolving_work_shards.job_name IS 'unique name of the job the workers on this shard are performing';


--
-- Name: revolving_work_shards_shard_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.revolving_work_shards ALTER COLUMN shard_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.revolving_work_shards_shard_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: signkey_revocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.signkey_revocations (
    signkey_revocations_serial_id bigint NOT NULL,
    esk_serial bigint NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT signkey_revocations_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE signkey_revocations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.signkey_revocations IS 'Table storing which online signing keys have been revoked';


--
-- Name: signkey_revocations_signkey_revocations_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.signkey_revocations ALTER COLUMN signkey_revocations_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.signkey_revocations_signkey_revocations_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: wire_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_accounts (
    payto_uri character varying NOT NULL,
    master_sig bytea,
    is_active boolean NOT NULL,
    last_change bigint NOT NULL,
    CONSTRAINT wire_accounts_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE wire_accounts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wire_accounts IS 'Table with current and historic bank accounts of the exchange. Entries never expire as we need to remember the last_change column indefinitely.';


--
-- Name: COLUMN wire_accounts.payto_uri; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_accounts.payto_uri IS 'payto URI (RFC 8905) with the bank account of the exchange.';


--
-- Name: COLUMN wire_accounts.master_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_accounts.master_sig IS 'Signature of purpose TALER_SIGNATURE_MASTER_WIRE_DETAILS';


--
-- Name: COLUMN wire_accounts.is_active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_accounts.is_active IS 'true if we are currently supporting the use of this account.';


--
-- Name: COLUMN wire_accounts.last_change; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_accounts.last_change IS 'Latest time when active status changed. Used to detect replays of old messages.';


--
-- Name: wire_auditor_account_progress; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_auditor_account_progress (
    master_pub bytea NOT NULL,
    account_name text NOT NULL,
    last_wire_reserve_in_serial_id bigint DEFAULT 0 NOT NULL,
    last_wire_wire_out_serial_id bigint DEFAULT 0 NOT NULL,
    wire_in_off bigint NOT NULL,
    wire_out_off bigint NOT NULL
);


--
-- Name: TABLE wire_auditor_account_progress; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wire_auditor_account_progress IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


--
-- Name: wire_auditor_progress; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_auditor_progress (
    master_pub bytea NOT NULL,
    last_timestamp bigint NOT NULL,
    last_reserve_close_uuid bigint NOT NULL
);


--
-- Name: wire_fee; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_fee (
    wire_fee_serial bigint NOT NULL,
    wire_method character varying NOT NULL,
    start_date bigint NOT NULL,
    end_date bigint NOT NULL,
    wire_fee_val bigint NOT NULL,
    wire_fee_frac integer NOT NULL,
    closing_fee_val bigint NOT NULL,
    closing_fee_frac integer NOT NULL,
    wad_fee_val bigint NOT NULL,
    wad_fee_frac integer NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT wire_fee_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE wire_fee; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wire_fee IS 'list of the wire fees of this exchange, by date';


--
-- Name: COLUMN wire_fee.wire_fee_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_fee.wire_fee_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: wire_fee_wire_fee_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.wire_fee ALTER COLUMN wire_fee_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.wire_fee_wire_fee_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: wire_out; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_out (
    wireout_uuid bigint NOT NULL,
    execution_date bigint NOT NULL,
    wtid_raw bytea NOT NULL,
    wire_target_h_payto bytea,
    exchange_account_section text NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    CONSTRAINT wire_out_wire_target_h_payto_check CHECK ((length(wire_target_h_payto) = 32)),
    CONSTRAINT wire_out_wtid_raw_check CHECK ((length(wtid_raw) = 32))
)
PARTITION BY HASH (wtid_raw);


--
-- Name: TABLE wire_out; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wire_out IS 'wire transfers the exchange has executed';


--
-- Name: COLUMN wire_out.wire_target_h_payto; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_out.wire_target_h_payto IS 'Identifies the credited bank account and KYC status';


--
-- Name: COLUMN wire_out.exchange_account_section; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_out.exchange_account_section IS 'identifies the configuration section with the debit account of this payment';


--
-- Name: wire_out_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_out_default (
    wireout_uuid bigint NOT NULL,
    execution_date bigint NOT NULL,
    wtid_raw bytea NOT NULL,
    wire_target_h_payto bytea,
    exchange_account_section text NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    CONSTRAINT wire_out_wire_target_h_payto_check CHECK ((length(wire_target_h_payto) = 32)),
    CONSTRAINT wire_out_wtid_raw_check CHECK ((length(wtid_raw) = 32))
);
ALTER TABLE ONLY public.wire_out ATTACH PARTITION public.wire_out_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: wire_out_wireout_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.wire_out ALTER COLUMN wireout_uuid ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.wire_out_wireout_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: wire_targets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_targets (
    wire_target_serial_id bigint NOT NULL,
    wire_target_h_payto bytea NOT NULL,
    payto_uri character varying NOT NULL,
    kyc_ok boolean DEFAULT false NOT NULL,
    external_id character varying,
    CONSTRAINT wire_targets_wire_target_h_payto_check CHECK ((length(wire_target_h_payto) = 32))
)
PARTITION BY HASH (wire_target_h_payto);


--
-- Name: TABLE wire_targets; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wire_targets IS 'All senders and recipients of money via the exchange';


--
-- Name: COLUMN wire_targets.wire_target_h_payto; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_targets.wire_target_h_payto IS 'Unsalted hash of payto_uri';


--
-- Name: COLUMN wire_targets.payto_uri; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_targets.payto_uri IS 'Can be a regular bank account, or also be a URI identifying a reserve-account (for P2P payments)';


--
-- Name: COLUMN wire_targets.kyc_ok; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_targets.kyc_ok IS 'true if the KYC check was passed successfully';


--
-- Name: COLUMN wire_targets.external_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_targets.external_id IS 'Name of the user that was used for OAuth 2.0-based legitimization';


--
-- Name: wire_targets_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_targets_default (
    wire_target_serial_id bigint NOT NULL,
    wire_target_h_payto bytea NOT NULL,
    payto_uri character varying NOT NULL,
    kyc_ok boolean DEFAULT false NOT NULL,
    external_id character varying,
    CONSTRAINT wire_targets_wire_target_h_payto_check CHECK ((length(wire_target_h_payto) = 32))
);
ALTER TABLE ONLY public.wire_targets ATTACH PARTITION public.wire_targets_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: wire_targets_wire_target_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.wire_targets ALTER COLUMN wire_target_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.wire_targets_wire_target_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: work_shards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.work_shards (
    shard_serial_id bigint NOT NULL,
    last_attempt bigint NOT NULL,
    start_row bigint NOT NULL,
    end_row bigint NOT NULL,
    completed boolean DEFAULT false NOT NULL,
    job_name character varying NOT NULL
);


--
-- Name: TABLE work_shards; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.work_shards IS 'coordinates work between multiple processes working on the same job';


--
-- Name: COLUMN work_shards.shard_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.work_shards.shard_serial_id IS 'unique serial number identifying the shard';


--
-- Name: COLUMN work_shards.last_attempt; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.work_shards.last_attempt IS 'last time a worker attempted to work on the shard';


--
-- Name: COLUMN work_shards.start_row; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.work_shards.start_row IS 'row at which the shard scope starts, inclusive';


--
-- Name: COLUMN work_shards.end_row; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.work_shards.end_row IS 'row at which the shard scope ends, exclusive';


--
-- Name: COLUMN work_shards.completed; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.work_shards.completed IS 'set to TRUE once the shard is finished by a worker';


--
-- Name: COLUMN work_shards.job_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.work_shards.job_name IS 'unique name of the job the workers on this shard are performing';


--
-- Name: work_shards_shard_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.work_shards ALTER COLUMN shard_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.work_shards_shard_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: app_bankaccount account_no; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_bankaccount ALTER COLUMN account_no SET DEFAULT nextval('public.app_bankaccount_account_no_seq'::regclass);


--
-- Name: app_banktransaction id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_banktransaction ALTER COLUMN id SET DEFAULT nextval('public.app_banktransaction_id_seq'::regclass);


--
-- Name: auditor_reserves auditor_reserves_rowid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_reserves ALTER COLUMN auditor_reserves_rowid SET DEFAULT nextval('public.auditor_reserves_auditor_reserves_rowid_seq'::regclass);


--
-- Name: auth_group id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_group ALTER COLUMN id SET DEFAULT nextval('public.auth_group_id_seq'::regclass);


--
-- Name: auth_group_permissions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_group_permissions ALTER COLUMN id SET DEFAULT nextval('public.auth_group_permissions_id_seq'::regclass);


--
-- Name: auth_permission id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_permission ALTER COLUMN id SET DEFAULT nextval('public.auth_permission_id_seq'::regclass);


--
-- Name: auth_user id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_user ALTER COLUMN id SET DEFAULT nextval('public.auth_user_id_seq'::regclass);


--
-- Name: auth_user_groups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_user_groups ALTER COLUMN id SET DEFAULT nextval('public.auth_user_groups_id_seq'::regclass);


--
-- Name: auth_user_user_permissions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_user_user_permissions ALTER COLUMN id SET DEFAULT nextval('public.auth_user_user_permissions_id_seq'::regclass);


--
-- Name: deposit_confirmations serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_confirmations ALTER COLUMN serial_id SET DEFAULT nextval('public.deposit_confirmations_serial_id_seq'::regclass);


--
-- Name: django_content_type id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.django_content_type ALTER COLUMN id SET DEFAULT nextval('public.django_content_type_id_seq'::regclass);


--
-- Name: django_migrations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.django_migrations ALTER COLUMN id SET DEFAULT nextval('public.django_migrations_id_seq'::regclass);


--
-- Data for Name: patches; Type: TABLE DATA; Schema: _v; Owner: -
--

COPY _v.patches (patch_name, applied_tsz, applied_by, requires, conflicts) FROM stdin;
exchange-0001	2022-03-19 13:55:46.617346+01	grothoff	{}	{}
merchant-0001	2022-03-19 13:55:47.968616+01	grothoff	{}	{}
auditor-0001	2022-03-19 13:55:48.791688+01	grothoff	{}	{}
\.


--
-- Data for Name: aggregation_tracking_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.aggregation_tracking_default (aggregation_serial_id, deposit_serial_id, wtid_raw) FROM stdin;
\.


--
-- Data for Name: app_bankaccount; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_bankaccount (is_public, account_no, balance, user_id) FROM stdin;
t	3	+TESTKUDOS:0	3
t	4	+TESTKUDOS:0	4
t	5	+TESTKUDOS:0	5
t	6	+TESTKUDOS:0	6
t	7	+TESTKUDOS:0	7
t	8	+TESTKUDOS:0	8
t	9	+TESTKUDOS:0	9
f	10	+TESTKUDOS:0	10
f	11	+TESTKUDOS:0	11
f	12	+TESTKUDOS:90	12
t	1	-TESTKUDOS:200	1
f	13	+TESTKUDOS:82	13
t	2	+TESTKUDOS:28	2
\.


--
-- Data for Name: app_banktransaction; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_banktransaction (id, amount, subject, date, cancelled, request_uid, credit_account_id, debit_account_id) FROM stdin;
1	TESTKUDOS:100	Joining bonus	2022-03-19 13:55:57.553511+01	f	df227c8b-0444-47dc-ad0c-aaecd725583d	12	1
2	TESTKUDOS:10	4483M9E44TRDA33F527C0TRWR4Q01GJCGTX4DW4R73ENA9TE31FG	2022-03-19 13:56:01.464322+01	f	e3ef4fdd-3e76-45f1-a836-e6c5a07c60de	2	12
3	TESTKUDOS:100	Joining bonus	2022-03-19 13:56:08.849+01	f	d00122a8-5e68-4619-90ff-475acce6b3ff	13	1
4	TESTKUDOS:18	1TR301WZDQBEZ3SK9YHS17F7QFK5E78E0K5215QCDX1BNSWSKJ70	2022-03-19 13:56:09.409632+01	f	82c4e044-1d59-427d-b92c-fa357c54f9ae	2	13
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
6505dcb9-8f51-4ecf-bc98-8c87a40aa284	TESTKUDOS:10	t	t	f	4483M9E44TRDA33F527C0TRWR4Q01GJCGTX4DW4R73ENA9TE31FG	2	12
07be1b19-12dc-43ca-8aac-2babd6bd0323	TESTKUDOS:18	t	t	f	1TR301WZDQBEZ3SK9YHS17F7QFK5E78E0K5215QCDX1BNSWSKJ70	2	13
\.


--
-- Data for Name: auditor_balance_summary; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_balance_summary (master_pub, denom_balance_val, denom_balance_frac, deposit_fee_balance_val, deposit_fee_balance_frac, melt_fee_balance_val, melt_fee_balance_frac, refund_fee_balance_val, refund_fee_balance_frac, risk_val, risk_frac, loss_val, loss_frac, irregular_recoup_val, irregular_recoup_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denom_sigs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_denom_sigs (auditor_denom_serial, auditor_uuid, denominations_serial, auditor_sig) FROM stdin;
1	1	114	\\x9650349f03b938029f1836606aecea3ec26c0125ddda7fbf3dd8b4e942a7d576178e1478cdf3e19528bd1e1d0cc5f1d9d4088d3aad95a1505e9732ee8b147c0c
2	1	251	\\x1d08f89ec2523eea559b41b9ed793be4ebd547e84c622dc811b76f2f78123ee7c9c8abb27da840010e2e847f5a4a521d811d10a09e36230a5a0f96117d069e01
3	1	257	\\x55aae3622696065517604d2e5063981a022f86840457e0e89d98e2ff1136ec73bd69b3a7e2fb219419f73ace6fe419b4eda5efbb45a5835ff089f1d4b7587a0c
4	1	143	\\x2db95086e6224eb57a1d322bf735074496afbe0795ab756a338d78f0af0c4027ec4b7be52115f762aa1ca7e0655545684e246d7576570fe1d560661903fdd50d
5	1	173	\\x94caf79d805196a59d18fb3ef8f89387a815e71cbf7d55fe80010f9e098ad1719c9bfb27dec657754bd64f272479c75299c678fb9770114bf4e13b0ad757f80a
6	1	186	\\x9009c9e97c9b5cac40d70d1bc12b1faacbd0f42efe38c2bb5465622ba043adb885aaafc9858260754f2c2ba2d8f5c016e11eeaf68e46dd29379bc3ad267ef402
7	1	187	\\xa5413c0e5832501e6fe60282227221b67add21e3d11f1ae6ad6492960875ff16e5ad2502413ecef042228d59eaaa8ef0c0e320be0fbda4cba10f345ab99a6b09
8	1	203	\\x56a5be9515b9438e4f7f303babbd65435eed1a92bb18780e4228d2517c34bab5cc8feda84c254f4926ff85af3956b7f087fc523ed1b5038f9aa58b08c85e7c0b
9	1	144	\\xd563d68670188d479576502d590e6eb0be5c815e8b0c4eeb3cfdff33fe3c3e50c2ad1bb117b63b6020d40317144695bcd6986f8bbe9abe16fe4bc1b7d35ce609
10	1	335	\\xf7733f22cdcf073354d9b0caa0966c191b66fc108bf91be05c173c63f43ec6a17a5019a9394e68a4ea2a7abe06ebf9e4265ad7ccff06740a4b7f34a2302f6e0a
11	1	171	\\xf7341a8b4217c5da7cb2c8e03f185f16049936762f723ba5f0deda37ff15e919fe1b2a32cad819fdbaaf9606d6e05e41f12fb61f588bd32f9e5800809e4a190d
12	1	207	\\x9b0473196dbac9d2c02458db1fc4825ad334214b5df2d509edc7bd4c9790721f657fc540bd7c61ca6590ba008e53b229137ce9c56bff4e8f012f566823b7c701
13	1	182	\\xe21d6fca846e007f42d778373d264f0a25c189c88adabb5f1b16c63aa4a1790750a2c7604b5dc47659f063065349b9e8f73a22875122b6c8225741390bb98b06
14	1	347	\\xad08326e9d4405efd2099a7c70bd35552f3e681588d44cb8432954070a7299ceea701d88250d385b1f38589fd1486f8f8881673cc15289d6f8b6b4cc8e74260e
15	1	220	\\xf7bc6a9e82908a951fba4c7d25e43a4fd22534b567d58d1e766db1a1057a9e0a534045865c6a9a5763e87cc4e99a067a4bf7841dbe1edce32abd606030aa8705
16	1	326	\\x4d3b471b95d85d15e5250cf1c407cadbb622ef4dff6482d37be906e77a0d58928df32f8fd9fc32f508d9ee9a5474b7d5e0b1c68c163c83dd92f7217888f96501
17	1	28	\\xee4951ea8683e8909725d1c8e7e41966937603b1887a51a275cdb8f176be41fece0cd4b34a3155b15cfbee30ad064476409881413c88529ac715c8623890cc08
18	1	247	\\xe125037a018ea0ad6d90c3cc485ae14f30b334c52a1802eef73d16b4def66f9394f3aaf33643fc319d2fa0f4235eed7c129d541d9ed5298efc351c3437e72704
19	1	371	\\x3090c8f87e8295c8fdbf6aeb153a47f161c7e3e14310907733037293cd0a3dfc6a70fe31816dba7dc496e55c92d4c4df7bfe4308c12d18849a48cb9fb8419b04
20	1	170	\\xea5b3a586a2a18accc3a38c78158d1567691f27b9275cb9da14b8772e7bdcd0df234fa39b8d9fa203ee8e3628445894b5750f1842c240e3d5b5e7f6c5a648106
21	1	305	\\x7feab03a576e20d68af4637b5a706bfb019ce4ed5c60bdbb6cc6dce9f2a507679c14d1860d6434d12ac33022f1ba8b2e90c0c7fa67f501accafc13cf2a22190a
22	1	337	\\xc203ea9bb781149a6032f8385f4706af8824ba9d62e08d29cd0639923fd1f4cb9b10d213380ff14e81c894f77a49929f06875738fe21ede9f477dd96fc8e4f01
23	1	422	\\x36bb4ebae075e4690d25f973f96259be7fb773f73aebc43fea7888c9c0e8edf09a0189455dadbcbac596f594947b7eb79f03632b20b881a2ea069be528d55209
24	1	414	\\x7a52b4998ac6315f5a7c07775eb74345c1d52d92d66b3f70d78cba22edcb16cdcf00e168bc4bc4eedf3a67688bfa9627fd5d35c930951e50fef0dc891dabd507
25	1	277	\\xd9bbe96fbb3b46dd707de1ec278d4ea712e797a17beb91785a625bd050a98c1c44d2f1469061fa1082e8f8fa5d6b736b9e3102233ae0c3233be465a4993e2406
26	1	380	\\x41b49e8b7a5496dbd1e18dfd21f0227a659b81d894f785281b054ee92452e2f1b96be6aef57b3db16c08cd306bc9390ff15f65ae582da18ae6e2937f649b5403
27	1	387	\\x366e2f40267a0c9e91fee92ab3d223932b96618855a774e8c7eedc58f651b4c7cd8feb2f5d492f36b50a9c713e2afeeeb91b72d9a8cabb03becbbf64edc9a80d
28	1	230	\\x3d056e1f8a954d001df3b86b17dc5e05b9434b52df128c3e967de869445353a46acb521b3586492e8f9ea7caefa362ddc3863fc1ace4de16af1cb275e375aa05
29	1	206	\\x2455619fa53011e9f9ae3561b95e866805bab86b0b211f7984a94ceac34a4e9eb09fa180a75f0e12663afe81f338cca096e769e4cc8674a29e9f5ab0f85a6705
30	1	367	\\x189d3e6d584a22b6561ea1f8454efb0d8fc4a2da922158926da773aeaba051dc91f0797df7ad1c78e202957b9cb395d86aee709649c17572d43cdb578622fb0a
31	1	368	\\x1642aa807adaa7dcb1301142f39d4fe55c19543fb6673c79b79005102408d4f24ff57464b03e1ace16eaee83803f384a3d4e9aa7f95b9a174dfbeb6bc28afc02
32	1	79	\\x242872f00e2a991312e10321a8b61a7a6c513a8ba508a53f570f7418faf3f03c0046f6fa6e5a5ccb6c41335d701d45ca0caee4e6d3b241daaa33496d3ae7c801
33	1	23	\\x0bc491ba32aa5850eb207b64e2c93473465eebdbf257211c4b465b54d9eefb52a4e810434b08c5d79ff459fd44a5ea6512c97061deaee17c8d589c58b52b150d
34	1	340	\\x0cb2947e63df8990c528bd57ad92458b54f634bad61d8e685162ab9460a5b9e813a56218f6b5a179983c313151d368f3d49c5aae88ec9649079bc0306d47c10d
35	1	86	\\x72f6f746883b63157b55cc77e1a809f033f5a20f52298df340a7ecb6a1b1fb05ef69c53f36872b9161d3bf789660aa7c5dc3914a34b2ad241e7d34f3f49dd407
36	1	109	\\xca4e82ecbf07a950d1c15fcd994d7374f9ae1b818db5183fdf8498f3d16cb34de7ce928629934cc7ae335212ba8e0b90241e558be092baa4ee0c20be8dafdd01
37	1	119	\\x7a0e5df38df5b35414c5c7276a7f5720f2a3bb93d04ea95aa504cead7d5e8338293ec9faf126b81d7272dc89cee376aab6f8479a6ae962ffd198e023c69f140b
38	1	146	\\x1d9c2fec3d775ae15bc99e0967b79cc5344e13fa9904604cbadc6beca5b09fd915d6004bed9de0896c81a1c8a9e0e541e043ab5bce53afafa4052ed3868a7902
39	1	166	\\x8ff63e5a9a142864a5e13daed9e5b7fd3cd2509e584aa38470aedd79d0c8d81c42ea3e7d24e12b0136f6cacf737c8f3a09f1a39cccebbf7dbaca50fbcd275b0a
40	1	361	\\x58543c621c8ce68494747dadc1d5dc4c717cbdc0c70b93a7354f8b1939a495e066faf3be1327ed0d18f1053832293ab0cbc9a0ece6e424a7315c69df800ea70b
41	1	165	\\x79741542e93d6c07433b5fbc93462b2e5b5224cc88f29b53ee93cb8d3958d6c815b7e50f4f47bb95f8d14e97a3a9ab8c955cfc01c3b5d508d9de5ed34695e308
42	1	95	\\xa159157a2c5b0cf9b5bf930f6eab81b95abe3657aaad6d2a9b6adfc016faa8047931bcb200b43706e7ea1c4da29fec523fe51667b2970e62e8f583ba2bd0b307
43	1	98	\\xce303dc0cf291a9769c2f0c4344e0279629d976eb88e213c9f24aaa2cea55e0928c2ef7a2b1a9a1ab2b478b71c7af43ca7133b59d41605e10a9e444c8442bc0e
44	1	48	\\x52e6dc72da26adad12420f1e754cc80fd88c89a34a878ef06b6ff996fc9db6e4503c8782e690a9e759c8afc6d820dcf50da32193034cdb910051a8851922cd0a
45	1	284	\\x7c5373fa780bdbe61beef30cdd995657d5a9872acb70b802ac78f6acdb9cec6bc4c42d402e8785cd91ffc6a0a7e142c8c3216e0005d9044770b094ee328c400b
46	1	198	\\xf4e6d60d10d1e804a6fac796bfadc8929854af36a40ec2349403cf2b77a9c71457560319e855a2e9b3451c2b15b8bf3e4318035aa9490ed31ceaf5e4d1efac09
47	1	417	\\x4262a8856d034efe1975e4900329027dd75d1fc0c8377e3aab7b609cff1ef3df5fe28b18d0991cac42f16761706b2f3c6d9a754e2761391b773c5bc948b0da0d
48	1	103	\\x9b5d9321cbdc5872de0ba2f8d18a1f2fbed0caf9e8933aa09dbb7638c9d2547cded65a5d6816b360e79834109083a5b719d2cd282ed1388aea6e52fe94398b05
49	1	52	\\xd5639301fa5c1dfa45b2c7fde2474b0fc2a50152b74133cc35d9350d2db5b996d927d5652e1bb67e9e944476283e0383877d0beb82f69ba198db929b59e0a00d
50	1	57	\\xb8d9920034f66d6f6f1b343b47f3fee8904d561096a89a21f3b37eece47d7d8e0b2b63258013b9eb6e18fcab2785241ef4c0283b875de12df0cf7febe0b14305
51	1	411	\\x16b6f01f19a86fa200dd4a5b575d75e236c848d44553eb2dc7ba3afd0e764b0f65cde604452945217923dd13cc6595a5579f1b5896f893780df23c6150852501
52	1	258	\\xc0f19908842fcba75b9166ba5fd6b4de74e3ff65f4787cd1435ba56b7980ea67378bef70264b7f8293cdd09f34639b74b66f2f5a2cf71a5e2b09ae0fd1d6230d
53	1	377	\\xd1172916d0b09ff2a10e3fcacb4d245a3186ac77b699f3e9aa675743d76dd9a8c575781b48898c9818a7a426eb10373c0dfc2ed1e1ea90b1b5a9ac026a87160e
54	1	311	\\x630beff8241f190263f369ef27469f8093bed62487d60a785d233148573cb475c50f20c28a3ab49c5ecdceae541f2065b60d4f26f2d93d4aced3708a77fbb406
55	1	260	\\x59a74396074f12b3530b65a1ee3aaa72b49761584de752020cbe02e3ec024140a76a5046ac9262c65f951ef0df70ab14c9f36e32900324374bef86982e9f2a00
56	1	259	\\x58e1ede3afffaea6203d848da87e1c00e26a80a1ce5cc55103208ca72c53c101c13c73daa8341b526762bb0813162036a0f4bb8c49367c9fea3c57de9d8dc401
57	1	274	\\x582910cc4b93886e8aae54120f72fb9a24e141952e566021b2ce6bbfc8555e4b914b60a2cef689d6807e27130dad135f2ec2148b7a637c4e3a75c1b9e2802309
58	1	293	\\xd515f5d355829d842e458b1fc5fa21d421f5fc36e5c938c888e1a7a42e3df7bb1b26d28f9761904ba37cfe8fca2be42f2a2cb8afc29b1d7aff626891ea531407
59	1	289	\\x61a36fa95780de8c255644c44bf68594a3d94c788f82dea61a3b25994906e11b5c1f02d06dca39c3eb38033e608702ee62de3d47e916dce9abad3a66181a160e
60	1	18	\\x479d51a95352bbde784521d327277eaae0be38139ac5090470e559c3a22e2a28b72a4a7ed6c4743ff40e2842f0cd2ef74dbf74c12f7e6a84b2a7ea1d1a68f102
61	1	302	\\xfb6908457ac2aa6b8b9a48996f402620e65b63dc2e4e1c04262a9dc97763df94d8c1439446fbb545efbae92839391829be6825035eae86f6674a4156f7d8110e
62	1	407	\\x41ae2bccfd8127c7dabdd8900901f5fb4ddcaada99771dcf4aec50b98c76090080b95e4e6539014ee0427ad4870ab8a36491d909abc0679e9f90f468dc268105
63	1	41	\\xa28457ae471c0937e260718dde3d288bc3769e8543bb141715ff3bac85a165d91ea249e6b4790cc15d5eb0c36ae27b0b245111f6e09be4dcb4233602bb085001
64	1	318	\\xe1dc516898ccfbe472ee5474f86f34d680a11ee2df8335ea67de7d2ddfcf0d880ccbb8b0b6a07b3da548080bb10d058efc17a4142fd349442703fd53ac5cf00e
65	1	283	\\xa50048a172141e01725fdf386d7705dec53669f8484b38cb8c8a71c035ccb2b480361a680af8b941f0eb297d0a54e6de32fc1677cb6fe287a0728dbd1614dd03
66	1	306	\\x143bc26667adf726494b23140b028c7b1f868a63873498f9bf4d6ad6e284fe9633ba57fa75cbb6a3a0642d1fe86406cce134666b7714279a36f0618c64138f0d
67	1	280	\\x2efc748483a8f9d83db66ddf73d451848208a83bb71cd1b4e67626e719daa2c1f865c4ac1af9dd247b70aab4ada22a75d559169d4cb18b7120fc2fe974926301
68	1	290	\\xb225fb1c18ed935d56dd0ba3bbd122a599248e33941b0e8682c82e8c597756895dd0926dad5fed5144c22cc7dfa912185f21c2518752a47b30f66fbcd716ca04
69	1	218	\\x24525284e5f422d306a95306cdf4d08b2129e08d4e7b6f1c7a1fffc08d54c833551d7869777cf94758229b7a56821812132e4f7f244cbf8eee6dbdd58e35610e
70	1	320	\\x76ad134ac4622ce7d1a732ee4f4c4173e56d1b5f35a86b6b391191a2f1a62038c722a47986903cc79e2d6fef4304d79f033c17fb8a6e9899733f41852c324c09
71	1	195	\\xc79bd76faafb20dfdeae767d47ae7f4aef9b77d86036900d8e4002c59a41ef2b669b6d8ea01bd2db0f2d36bf7f2c5c2cd108e2531293b11be9c29dda1c336a0d
72	1	156	\\x35762a78b764726b0c416fe38d219e5d929571e1bd185aeacd0b4f79cf35a7887a124e445ea8858cad5d292c4f906cd2967fc4c34b42e651b9ac6de9d5c1c907
73	1	325	\\x7e31010f48b83166de5d6acba3349bb891e0839801114d061fb37e6f1b89a2ecb1e5b09b371771394aba778409e5832c0db0c9dc614aef0df115add6e96b5e04
74	1	1	\\xdbe1aa5090120d6594f90f323e4b6e8a51744a34fbb1575775e7bc047ed3660c22474781554ba4fe3f4ef4b1f8d978c48c323bc218ce18d48cda2e20e701f90b
75	1	126	\\x0cd5f25ce887f08807eac3e7de07c763460d597fae6c63ce0c9fde6824a9690365efb28a9a55a5d97963aa3036ad85fadae048c6017f29672f3b234ab8b4dc0a
76	1	319	\\xf119a1918ac5de119bbdf96644aa0aa3f499ff45e4264d97015e9301236393e879907a3a914c3f8cbc75d13dea359089b043b1ad6c98229fe668840640f5ed01
77	1	141	\\xba80dbefe4e4722919adb257c5cfc7c3870d6cbd0e3668548da6c67e2206deb1b4eda9fc93f67585d8acd334eca53c529ee4ea8482cd2823a3810428415e9b00
78	1	163	\\x6c5bf0f0ee2b24b71cdd5c2f9ed96c193ff3476fec6cddfb779a71dd7273515efbab9ec0d645f409566d0b91d82832ff880814af4c1e111651d65a1872ab780d
79	1	63	\\x38231931510103722e22ba5ee8f3a2d9d59bbfb7b3f7eb1e54c79398b6616cc9beaa9511df8834fa7faea0c54ab37499ef8ebaec62bdd479a519f462a5128e04
80	1	81	\\x5329661282f10ade6eefc61db4cedaffc83aa9918c56143c78373afcc1445cf9240914bbf93357b0fdf1d5f90e78381b335cf76a7df08d6afea866d063534505
81	1	50	\\x215423a5ca2360c88a51c4d9a1d597fef0e4a7d6667fa8ab4b5acee7f8b4867e393f6f20b6534a0481ddffe8390ed1b0295651c7b87c1ae58cccde70fcfdc807
82	1	237	\\xd35dc7a0ba3f42f59c3ffdaf61c736bd160369f0458db40911225eb274dea0acab6f4d9086afa1f82de64322f10462ba6dc9a78ac87859d6690636ccd463f00d
83	1	225	\\xabccd0e3446c29501e8cd15ac4b9ebb18eca5b924020b170d3bde017ff8d323d2d5352dcf4977e839ac7fa02b1eac4b4a25b46585996e4241e43e23c6c81ae0a
84	1	303	\\x434a9dc577b3230fb22dc42124ed25990f44377913b4de4ed514d12bb18e61514b10cd982875faa86d9ee179f1c69bf55429a6b01a56e58b738068c5a19d5308
85	1	139	\\xd64a50b2b8dc6f07277b098a2babe16a35962a225ecb79af2d98649d37f8b0930d94d71415a4b1187ceba724e4610bebb8a087e4e5882ca3f71deebf8a1aa40a
86	1	108	\\x5b92ef261ad3ff8eb1ee2c2acdce071c503be587ec19d8a198b3c69216f7a9a0e60acd676b77026a8023fc3af4815f86af3a3709f9f8639a5c1571d859311c02
87	1	70	\\xce564f995f49be1037f503384e6fd7069069b33aa5174a1f9740c1da88d500df8c4689555c726084e873f5b043c75408b0143fa4f5a54d46d6dadfe6e65ede02
88	1	4	\\x707a92e0eea557b6e567b70841431aed9f679ad88e9f93085474f4b67f7ec4d1f0acee27af6c9c7ad10dd92f0763477f67b414da28343124657d99c8328b020d
89	1	75	\\xba07fb3cf0e7d4ef1b78b611b2463ec769004900b115acd03fd2146b8e9a74b314427b691b7f86c174abaf611015716052a1469443233a48f148fc7f0b1e9207
90	1	167	\\x25065c3dfb36d4fffca23d219637aa1a6c9812d07c043836ab21c225ab24d07512792e530a231885385a0a4d6f8aa1edd765a72f2cf02fb55ec13d184a6c2d05
91	1	381	\\x08647561b8dd399bac94b953c4671a9d038534b4b7ad89e97e967874e7fc41701e3babe71c7aa2f799f5b0f7e4ad3ed35385f39a9b217d95279fdd6f0fb41c05
92	1	299	\\x5aee413cd1d2d56d775c65b2abe341ba3123d6274ef3e5b6faaa265728084d4eaddb48e86c2a941c1b287b5da8aac6a35088f1ff94979b2692ce5bba0eb0cf03
93	1	33	\\x07ff2d0328b2ed063f9bb91391f11ee5f0a724c171236e83efa18eb895efbd027b1acfd6f6fd0be7991f1109120c5dfbb7fea220553da8a282fae6369956ac09
94	1	110	\\x04f8ff30230390f7cd1a2adb3a855d0561740027ca132cd94f03c51115667574afa59519bca615872198a95f03d50d101b6105f63c01af58ea5231c6526ed80f
95	1	271	\\x3a8d3ea3593bb9dc9e4d2e1c252fae872efbd23a03e15aafca3ab05e0df073f834d2b3e1a447f1b4cff8a49a4ad4e09612087f8618e6f06ca3706a9aed4bd10f
96	1	344	\\x9cf386beacc5dcdb6cb79b63f6fa3bdb15c71ebaa50f0cb7bfb5e6119fc3b4d913821b1337791ab534d12d5eb47b34f5a21547d79b6dc4075bc0ab1ce499c50b
97	1	122	\\x17fd720a163bd2c1006e3ce23ed913fcda16f900b73a3c6fc7766dfb80db4c6611ca7f98138ac25c9a34c92fe29a854fb3d7ba7ae7837d392b4a681553099e0e
98	1	249	\\x8c9454c86770146b7b74c212bd27d79ee912fcb98a3b0c0ef0bbabdacb27b2cb8c67dfe48cd597a1cae7963bea6bf53082228de50f4c03970a35497bcfc57d08
99	1	360	\\xead6de4fef4dd7244a3d68ee7ee6e89cb656f361ee17afa1c31baee4bd5d1fc363f58a7f9e0bf3b75310d8f6f8291b0f61d6406175893549edc0f5d8fedded03
100	1	5	\\x8db09603422b3828095b3034be209b22b619a4237dd80f725be9155c7d3037c5973a9a297fcbf98dae21035cf82adcfd041e75d706131e9ac38e0e769766b005
101	1	375	\\x2df9299b29dea286983c2cff6b06c785203be91b9f9f98b06bad0a659383e2a4f73a733b2e978bbe0ec540195408fd0488561912528e90ea4ae6a85fe1a1ac0e
102	1	66	\\xe90868ddcdb72aa0fa18d1f7da1e96aaac166930c76ca6602119b1fc2e0cceedd7b768d378ceced0c2fc9fb73a47919f12d79e1aad7ecb2b467c0f1ab8fea701
103	1	83	\\xc139da5f1ab8bb7ef2bb3fc5d5fc6f9fc1ff9b4197e5caefbae90ca97a4b3daa6ba8d9d199e0cafdab2cd1d0bc18deb5d4bc500596caa24863e74b6bda82aa0d
104	1	133	\\x7a6f0d254adbed8f6c0eaf1ce8677f9440822586515aedb95f8f57743f7dbaa7970964a4bfb2e81a1ae94f1a800b6cb58c8947ac3e9191c9b9baeba062da150b
105	1	96	\\x66719adc146d7f8529938ab38501d1e758501005c0af9d297fada8daf984d33bf95797b9d6a19b8fa1a3bf25d326710cf310d622ccfc1d14845d579e06f42900
106	1	191	\\xacfc4225ddd97d65991acd76d6065fe7c57abd95469ea3b4cd65ecd1b499758813757b5f49494541d73271ea39dc79a97439cc330a36b29561d9566750113202
107	1	298	\\x5c7eccde6f2afcdb0bcb543bf0d8d45e505863c5284cb82f90444e1a730449b7c72955af6137927093226be1a52fa043e96d911328a843d2c6d0637294e7b503
108	1	209	\\x5b2b2f2a7a35598fece1b6e78cf8b43eeaac343ce0d23ba2052239c32bf19982fb20e7b06454f56aa3df277b0bf993afff53c111655c5c523e035f8030e53f06
109	1	192	\\xeaaf96b90384b1d513d356c201309180091a7956254cb35da207f3c308158d003a29621b944eecea81f09d605f9872815a00a7ade4b32905deaec7fe9b094502
110	1	229	\\x221c409022f96814d7c0a371e3cf61e0cec7d1828a2e628ac4f8b1915fc13b987926cd436dc8c772fe673516424fa54fa0c7b1131756fe1c8936213d7613030b
111	1	9	\\x1709883ca2c72f8ac98501cd59ffdae6025c8f4a02428cf9cbf08b2ef481d8bdae45abbac520aeab714f4eca666a28afb2a24b7694b0b670943f6fe414680e0e
112	1	267	\\x57cc0a573ea8da1a1e6fda150af0196014af7a084ada80d46d80df5429e3e8e5f97ade1c711b6997e561adb8e336ecda23365fa350b9c767751361a5af81cf08
113	1	196	\\x2961a07f8cd59874ed2de70f2c1e879f9ebece27af05e1b2e8c18ae35175b920116e48ef568ebae2c292a561bcb97ef24e3eabc3567299b987091c90e3d6b205
114	1	104	\\xc531b3c767e7f1019526e55ecbdf303abffe9e00693a9b1a12f9e07029c557bcd549030cb7a3698b127c1ee30bb32a40fad6c89fdcad99e04f911c9de5ba1204
115	1	97	\\x7d062061842ca36d9c96df7813e99f6715b914c8e202fda0e258c1a2bc97e4be7e73448644f029a60c72946e308ed1ad71fdb6ba05f391c5f96df8a30ab8c50f
116	1	65	\\x48a1e4549d2ae2c6e21351e8fcfeb531cf142d7f1a07191e57839f7f4a507d15d3fc9ed3d3f5ee1e20632e0336bd0457999b8297cd1013df0cb7b7f1a6aadf0c
117	1	31	\\x0fa00727aed95e640c12c45df83d3764b0a6789ff3a877a49810a3a39233a1a011b9645e67766bab579610ed6a6b791341f03aa1f70250f70a74795886b13909
118	1	348	\\x71b2b211bd3f532631fec1ce1b0d823a37c2572ae6db2ff2f572054bb9ad0f5c30cfa9af386368bafc99f6c87c9f6dfc24929b953ebc35080b2cca132294ad0d
119	1	11	\\xb30dffe1cb64d480987e953aafb3a05bc8d7ccae98150280fedf56fc12c28ab1b1c5ab306a6289969fd95d6f494a8df5d450019a680c608125f9859d9c976b0c
120	1	53	\\xab6406e27ee5a8df0937699a06d7cc7ec6f130d4322d90d08516a6360f2735d4b9781684de0be18cbeac68de8f41e6d8f81c5ad599602ac002727a46f3f4a30e
121	1	252	\\xcfd27d05a49a0d312b596ad828f0e302435fe936d34524a5a7775e7c9813912dfafdda32dd40b45718d60643b8a53dde78556f83135c7f3a6d57a9f921979409
122	1	415	\\x4cafdc666d3b1c48b340706ac04b4f8caadd90329ed18002b76abff6c495576a6430458ac2f03984e167dedf90f843dae2438e96b21dd5a0d2452a4e6fdbe606
123	1	174	\\xc34e4b4d68bab39c33bb4f57230f4bd70fd1f14789cf6c914560c4755500878fb73c602f75309c8d973c93149c161102b728b4fbb4726876f7e4653961761302
124	1	168	\\x603202ce1af4ff8e54c60902fb516c7858e1f2776c287950fd91f3ded1857f6b104467d603f8cceef865d199fd7f797d4c4c063acdd3fbf7b12fee1797520f0b
125	1	172	\\xb87ae01948e76da196ad33ce4dd2f938aa3af76682d5f6c72eaaa5b61d76bc184b5eb03000267e26ff690a42acdb55902d10bc1f01a3e5069af0d5b13115af0c
126	1	131	\\xb0dbb355083490c8edd8205f9efbbb4fc43ae9f5d0958b00e970df883e6da7698f87219d2bf4f60fd56ecac9e28704453a02eeb1888219f868e5a0ccd00a1504
127	1	366	\\x214022b669a6ceb2c6ed3876b4e607766407c2b9a99c87a6f5919de81612410cd085fb96ef979a23dc88e1471d871cb5f521f2030a41be6db6bcc7c20db8d602
128	1	137	\\xb1da6f8a0e3a410a1b3021afbfcb62efc0f982cfbdb3a01d6cd75b367c31c6d507c6e1600c00de17cda6e1febfce1739ce2d28a02adff81b2fcdc3cce44ea509
129	1	58	\\x8ca0242773f711934831bca722d9308c30fda0d968aece9e81681446297610387bedd8e26cd5d4f487d8a6e6f3b97cc14440c0b48b12499ed0675346b3fc5700
130	1	67	\\x5b9277dfe4bd38bb38e7f22fa9f9a0be5ddab25f34cef2e61381e0536d7b2883c58b83f5b7d919670ac100062a4e276e092088f0d5757300ff37d95cc4501908
131	1	17	\\x128dd210c041243d443b61e1a6f3cdf72196177758e2c6576c221d2cf3cfac6a1a410f86d454395af0031eb5dc2268abce5e7dbcc8c706118a797f2a4e946d06
132	1	25	\\x6a8bff0602b41018dfd98412d1a040adf4554c08dcd768d9fa2fbf9fa8d8289cc454b5af093ba0730df663b911dad9cbba01a04737483aca072661288c56960a
133	1	71	\\x06dba481310aa48ce3e0f3a945ffccca5ec869024fec541a5b3d1a67c673ddaf2534aeba99594c72c52660e2991f57c900382a9b2a1574afcdff5d03c538fc05
134	1	19	\\xcd59a1b9417aa8788f5868f762060edeed0b93ac961abacae23fbc4a3d0aabe6717b1c67b41754c7f5b397958b3037c063d05b51be370ffa88804dd6819b360b
135	1	261	\\x4d8cdecdb0acf6d9ba35438c33f06d0164646c86091b9c53cc8f924d50d43dc5ff076a9a2af0a7ceb705c9c41f15d0085c409afe9d6f41cb1005c89628aa3f0b
136	1	276	\\x83bd61b15aca7de82f26c0108e1a02049dc3c8c6aae60c18324b9249c0898d790d72616130e9fc01c6d581b86b42f6d30240c03893de36e5bcf3530eb773380f
137	1	200	\\x0600113b8882997718840e4d2d0f4d61d2ae9baf3e7a5f6175cd80a901d8d13f132403d7e76f320f7a5b7f0ab3dc5ec4617997bedb8677c2130d3f3f4a0ad108
138	1	135	\\xcb73ef09df3b0c40b51306f93eb23f7cec17221e6fa7731c5ee8d90527d41128133674f46cf5c8acb7f3856e0de63de9c69c68b8320b8741aee220a78b8d7600
139	1	76	\\x68b7bcdc8a4e87e1451bbda62a41ef9dea25bad35fc0664e8a83bcbda2cdd7567f10bc87a5069dd52954fda4f7b4c4bff6022d02ffe7559cabc5fe55156c770e
140	1	228	\\x4e40c776b45f19e9fa2150270a4b4ca0bd1b9dfa08de9dca59e6ccd62e2ed2f5889022b8fa9600787047a946f1228ab100b234fec8e83e7bdd7fe2c113ef030e
141	1	88	\\xb74535c30b1c60d47e95bdb1c412ccd964b8fea0048a82fd26f1e3f0eaed28172b9a1bc107c49ea288c36b55bf049f0b09305a80ea550fafc749ca4cd6576f09
142	1	91	\\x2f68a015ba49314359d1c6992d9e05a8cf54b9850822615d001f55167d89fa5f8deec077e6a1c078bd0ffa3af79e1cdc131d7909f0cb831a3d952b250f4e6600
143	1	147	\\xa8855c080fe48edcaf286daa5c9528326ca6369a7f43ad50d87adfec0a4fbafcc5972d2aa7598dfbf264888d9ac965ef0ef795ea8c73ebbce0b2e02a40a04c02
144	1	153	\\xfad0f0d73cc50616e1d4c22a71d8cc6dd82a90f37b4dc058e730f88a4fd2bd479b2f23e10f68c254d0bf5c628502d5ac3f9bf1b1f11a3ff04dd63c33e75fc00f
145	1	233	\\x26bc123db82258b50c3cfe1caf9453275051e2ed610160394c0a6bbe049c6bbef50c5d569b80eb2731d117b7da428163a598ed0d20117417804216da0807af02
146	1	105	\\x65a5776a67087bac7cee294a7ef3dfaba0b0887083809bea8b2f2cb8aae1ac851dde6c67d5d90a0f2f3d60c0e8071b6961c34f07f82ebbfee72abd94d4c46d02
147	1	343	\\x73b6381fcf17807f3c037a835957892dc310d048b91168d1b33ba738546929956dd642f437b0372813256bea9036e440153d6acac0a39a131589d0187c700801
148	1	412	\\xc26c902d0b57fb58d8a0da130b1a79431fb25cf5c08e2eddf00dd5d1299d53825351ee66dc241c6d6cedac54b3961132b60c66966fe131bd1dd095decfee1201
149	1	317	\\x3e44383395240e7f202e947ff1e343690d8f33c0289225c1319d334f5917c1ec5f0ccc88bc57d038547b7e2f023e546b10395a9ee17463afa950e3b923aa8102
150	1	117	\\xe24362920e2b1b4bbb37faa4ce154bde1ff59ddc96ade60e0826dac2743b4b86952fe568692babac9a5dd45fefe1b4d22e658dff367b9615ac76370b18362f05
151	1	315	\\x5403bda0925182b95dd1142819aa5d116287d880354bf5ea8aa1e66f4abc9608578049bf63b95859c2db402bc592cedb4800d994c8e3c8e99c5627906b0d8d0d
152	1	202	\\xb52b245fb9a20028af74fc1809779e2a3cc43a47347a9cadd70da7d2c524b905991ddb66f37306435fc62e93bc793058a158c2e973c7fdec53b63eacc867fa01
153	1	160	\\xe8be11f0c39e73a4a2755c502c9f4ca8da788f13b88d5714b65ef6ba6e3e68f9546e0393c4e2993c52dc9ab0e1997e5f88eaa65d0c44b4d4029ff8035e4dc00d
154	1	59	\\x80c5002334e31a227f11fe6012f4e912a6b40e0568ec3e00f26204288747a36780846f09855631fb658c4fa7037dd8e9fbd4aaf7544d4780ec740a7515a91c01
155	1	255	\\x4a50cc0aa57029dd4715de5ff756c9876afaf79d37d17720576fc679a30eaf25af93f6a468a8a3ddd5fdf787d32040b266df7f22aeda258a53bdccd16a35c00d
156	1	357	\\xa536a6541650af5208368c95861484e3e7b37bb6d842c49968e37a64c243eb8e73e18046cf2d53cabe825b49d230b2e0c3a1c3a63e8f287a67df880bc17bff0c
157	1	408	\\xc2481ac9d3365f2c78d81f8846b1fd3bca65c12b1b764c53db5419e5815f6c2a5b9622ed2fee0bb12d35c1e5388dbec6d070942da36895119ea5b218896ef303
158	1	269	\\x17167d23a880bcafd0966ed40662265bb67275309c4b7565dac61570cf66d991d170b1ab34baf45f1b57f26c3309822c0782e933b36e61cdd62c9966c6e1f906
159	1	113	\\x910c0f3778ca86517b8ef49dffbe6e3bffb9afa3114cadd2553c7f9addf52e78e58ca8019d50cd8c02b34cb8821a65a168d9c3de6a46b4792c31d9ee5932ed0b
160	1	178	\\xcd848ae83f27185f6ac91da93cbff3d4a5d84c105da2a30306f7c2f43f61ff2c13c74c03431c69c263b291621e2946ff33d54776c84998a89f5a9e4ecbdab80c
161	1	396	\\xffaf6621951bbe8d21803c9024a8dba9429173c2fa0d85c0ab2791e26ff0f8f2eacc7b8044bb5056b801eab27c92fdf22f4bb97cf02ab45546a018c88bbbfb03
162	1	285	\\x60adc668bfca4f83bdd51cc96dc9fcb6443c241ef81e04d288db7287761ec88d8b142e4cfadab10997ad98352a6adc9a19440d83559e48a7c82b1bb18c4fc409
163	1	2	\\xe6f28c477c6b31aa220f25f414e0d57676c1b9008ab86e3b66b989a518a7e75306f5fe08a4c05537ee26f7be20ad09b0e5729484983dbb649699f1c70a495d03
164	1	158	\\x82234799220bb7368ed00f3404a5b328d66d6df3ef475c7e98f938e96e17d47d9ecb48a38f4152b7225fa5c8946e666002a820c5f5234e60c6caa5d47cb81903
165	1	150	\\x13bdcaa40d7364d90e779c7af145a7e6472627aa8d5106347de9008ad131cda0357792a899ff1f571a06c637c7934debd88c562d30f049d17a4ab9786de5390e
166	1	385	\\xf074c915be993cae33d5da815fd8fc1ea92392347b16c3c4390b79b780cfe33148c1b9de8b65b32e948122246477ed1d1960365eea6ad0c150a3b714283ae009
167	1	84	\\xa44589c893ad43ca5a47fa93286671a0359b565c4e82945fc5721f6f81a3c14747e4fe1391e3c1bcfdc5eee2b16c1844226fddd011ca0bf9585b464d66ecf50f
168	1	175	\\x51ac22cb01c0445326435b872727cd0d780a42c246a8ed2bb118b80ae66f13edb9250f1a994cd52239ef82669bfe55135b9e1c8ac2eea7df59812e976b5d1c03
169	1	419	\\x300dccdf264c3c8490790cae100293297b29f49fd2a37aa9ea870aafd7e92674cb3ae0844a696b5e97b17ea452ab814c6bfaf1b616aec89aee31275b73116904
170	1	287	\\xce8a61be27e157fd3a8876080f21e243503023dc5cb95dfece65b48654316936c918bba7ea05a0c7e9cd84b49236384235152e22b629ab63510ac45220a93d0f
171	1	376	\\xb5fa379c3a66bf6129f514f19acc05584088d0cd2536d0fd8cfbdffce24dc63f5120ee14546843e1235ae71cb8996641e60353d9c6418e6f0f1dd65714d69c06
172	1	169	\\xa5e94e4a82e42b4a9b3019f09ad3da4a48f2b1e391a18f6bd9732267cfe9ae5b9cb4d8a0754a81f1faa5965550064afa58feffab839631cfe66a3a2e73065805
173	1	64	\\x036af65bef999d73d9613bdee6ad2249733a78490c58d4cf11296ae4c1fb7b4bccfea715282ea3c160705a5b7e26945ef2ab65986358d9d0791189fd49dadc0a
174	1	390	\\x9a174a61fb1a24854ded6d5f72ca6b1d24309e4a408f31a38283630617bb22514630c84a2afcd144621cf77efe95ac9be85392fa8efde1f53e52c1cf0130f20a
175	1	157	\\x13960def34d3661193445282d60ea2d995cd49fed540b6f5bad416b21f25406e70f3f6396dcabb636fc6759e810d8c551ce060d68755e8aff9ad4a1da383040d
176	1	365	\\xf29744f88d3b198f875ba653302d62a0783e2b5dee4b964a502108912e43e397ff073f9699c3bcc5efd1eef5daba045ab404c0a331e5d70bd05e235cf733990b
177	1	316	\\x81cdc6f8ffd453bbed1131b1e514d9324c462ee797de76a4e66165ba121b4b644c334d11ce634a10e108aec90ea19834a33d7dc8c5b7bcd99bbb4242c7fc9107
178	1	243	\\x92ba9eab05c4128ccdd8dba30b00eaf39eaa726c1bce78b4e391726a1ea52a7872c6a7e9586fd199246848ec25b64a041ac7075e7d872f407482a05f7c6d4b04
179	1	199	\\x284e524e86875114f09b739155eb7348d7b8da684088904037644e680cc301ffadbd23e5610bd004eeded03f05be1d71c40fd9ecb54fe92600c9ba1e9ca8dc0e
180	1	351	\\xdaba075b77dc06388d85b1853dc30e45dca193a37befdd9b7d3fb1c10922e1ad482964da7659f6d96d1dba09e09a0c305e39e5649ff0c7e4ece145cb4aaac30c
181	1	355	\\x2fffb05fa891d0a7b692605df7c5a91d7aef2c362f4da721d07c1f222c63723785e58ad448eec1d6aa0a2e979b39863e5005801962dbc618947551e17131490d
182	1	145	\\xe17b949e1374e886596a1f4d81df3fa226b2ee6c1dc66aee54ab5cd7924f67e117b60e70d07da2075dd95b1a706ebe7cc19e3d00069b2da355c552e1d2e71e06
183	1	363	\\x108dd56cf85289a609d6f469dbe29c03ea1394e7f833be774ffc597431c5f65258eb184c4c9e20b176caddbd90c3f5606f77fb244794e28c0e19fb2feb10dc0a
184	1	313	\\x57ee4a51c0318f95de57b8bcef58e2fd8273ab15a2e5f1766bcba43ca06a02e8b2647317306ed0cfa5f76d84bba17ccd1ae05e4dcb8c208e89700df525d81e07
185	1	6	\\x7a5e5c29e0a3e8d45ff89d638d58d5c85d9c9b178402b7c548a0b205680950d0c93d30831cb856785515f759579e15a531f880d1bf88551bf2276cee0d157e0a
186	1	328	\\xf5781410eeb413257c4be989aed3f1b6efc925cd6cded32c3562bcdb65fb2df86949d75d9d0feab793e22356d8cef1b005ffe9102b59de231b75997e7ed1c10e
187	1	82	\\x00883e222798b5202a59fd6b8727e6a8cafc65e739983109a01e02fe690a5538a3af6083bd6ba33b5949f68e9104748a8f639fa4463792bcffdba769f3f7be02
188	1	301	\\xfee3eea67ff00ae4ec5e0c52f8586118f8dd4305f562e3ec5e7fb33892e79218476790fe6579b7a9f31b3730fea1cdf51a5af931b8bbdd73490103d3e20dce0b
189	1	392	\\xd71dd3799970fb135f1819f1a787b29b88216e783976262eeebd3222dfb842654a950afb9ec5bb40ed553af4d4be961051ff6d6e85e2dfbc450d42da34c6ef0e
190	1	333	\\x7363d762fb08c7e5d94595fbce058cf802e4e1829d912d8e8dfc1db7e42f55d9ce9b4637440c863f6d948e1555f7a9fd3a4fe0e96b2757dbd9a650a4ad180105
191	1	112	\\xbbfe3ca10f23b3f5ea474265da1b022354cf79edc69454d946ac2d61b09ab949346df36a6613b7e3caee84a8a7d35a48e3dddbb57881bc060338297e9b89640a
192	1	402	\\xfe5b86f1753c8cba1f32954afe75e900e6dc5255e5df7809d41790371d25cea03267e9638d3e7fb6d1ce2a1c0f2e43b111b04f0d7de4285fb082d67a3f962c09
193	1	176	\\x2c3a82ba9d33a56f5536a665576c9392e92ddb546925565043e7dfece4a88e96034126ef9da63be72f1a6a4b9afb6940c42ba2c299ad8d8409628f2e57326c08
194	1	345	\\xcf38e0f301bc11aff13eb8161bb510665590261d8254326442f7e934530afd402f0c7a0eed4cae87a8104aa1084088fb7a81b54ae26f69dbd67f27fca3abf601
195	1	332	\\xe3bee5ac109a61d2812c9655fd9367a69d960e70aeb3dd87c0e05afda06c29b64ea36744be32b10647db268f74828a22022c8e825e965e178f869a2cca5a5105
196	1	89	\\xc501dbf29f9e4666610680e58d26d2b67d6e3fb2ebed2a948ede861259b177ec11def77ad54107323a5ecab1d4f51d65afc714865e37aac71a72a15be406de01
197	1	240	\\x0146ba1d5f02164b22c7547cae2a25868a4773a57863a649670dd83c40edde9af92f58ccef1aff40e7902e4ff0887d2e0cdd2aaada20e5fbe8ecca6c665f0502
198	1	211	\\x083592efa9deb168ad736ac6e2ca09e9d62e6133cf06611b079ea942da51f4fe465abbd4eb031059f364687686fcf980fd368a588c34feaf53932c6176cfb40d
199	1	49	\\x6088017a8a29b6287192c93467ffe4e6d186fc60421c7e6c8c06ff43aaeafaa7699479034e9916c6f6d886199cc17ef9dc53a6cf26ebc79a1d9d6c08e91c300e
200	1	99	\\x28fb4cd6e8a5b5803d21586bc2347389c64d17a145f837681e9cc8961a19653a07edf88353f09f64b0ac27160ba1c0b68670904b159df0baa57835eed651760d
201	1	164	\\xcf34089e27cc9b92c8751751078044da2e48fb2e568e53f72a34f86e6142d0ea846ce68149c0d3657816d53f52077e5dc6d97b7b6501e01f255058ee9024ce0c
202	1	336	\\xd8d32f26aad9a6aad76fdf53eefc2e6c04ea040d0a3f02995919e4e3906491c46d4176610fb1e09c0ede195074227fe75d8d3a0c9b497c8bac2ad1c2bd5add03
203	1	309	\\x543e928f30284adff886bbfd9e04cae3cf3cd8d7c43bdbd242e89fbcffca9435d6f31904d027839b4a69c6e9cae773f36be5a91f900cf18566889c2f9e648905
204	1	266	\\x6905f135cf6f90fc370266b903d104d90b91f7f3de6f2c1b6b0d02f46b4f48c31e3eb802ace674b8522a56920b4d7595520313f4dbbc513e5b7644ec61e79402
205	1	244	\\xc6a4dac4298d3ff9add9480c18a1a26a3febb40b0718df367db8a1ab540273c3a2443508b3d698eadb5b17332ea559d8c78e96b7384b4ee33f9420d9f69f3003
206	1	26	\\x2718d32ef9a250d3d5222397569e0f1df9b0b137251b705e2d3ce81d340f2e08b8ec34c98304a7006516f1000fee5db2fa1649fbc7677b2f8232b54e479aad02
207	1	393	\\xe2abd19b9edb14b85e360c87bd066ab293f5b63e852d4bc3495dea7575a921f5662d1a78b888872884427d6aca3ea68b4e8844441042e33aaf83d8788ab46a0f
208	1	409	\\x6e24b326345c3b05e820cbbc588ca2a99d1825fa96f3278c6f6d615042e6b3a94eed2ab0477564694f1a9d8a802e00193ced5106550ef54564963942dcc0a803
209	1	118	\\xa26ba725d8500932834a34e06ad96a94359920826b10aef3b681ecaec24fda3a82e3a02875946e3a99166e1a3ba4872bf9e0f92316b23a46c2d175fd8bad2604
210	1	125	\\x4879cb64d4cd9da940222b6189bc1c6a759a19b8fe5a11fae73c8163ca84ace9f7d5ef003a122837ec9e488d15d7596dd28f25001c39913523d89e30b3900203
211	1	55	\\xeee0fe11f3b2e4a0f7fff7cc1d59d3a25adbf376a89cc0c9595e46a3aad24bd95ff1fe3228bd81742807c22e1f5c0d6495c22fc854c3198655a50b3418d29a0f
212	1	210	\\xaa64366a68e80a0c2221e167cae18b6b899c011c31fec71c0398765e7e2060f0fafe530e1265d4ab688c47e62a660664b062f3a54b1f5fee59100188ee279e04
213	1	420	\\x721811d1dbb6d38b267fe8f76d567865525d76504ea1b4c0a6ebe338680c69df4d9dd2d21870e72129950423db475d7c6cb8619daa36054850cffe9954e6ce09
214	1	279	\\x914bdcf0e4e0f97a549c33b920533f2ede2921334fa153959d521e02a999e7d08be30da8f36189eea09eeecbea69f15f73ffa7d5c9e9c6056c299b9ee4f93c04
215	1	46	\\x6e13314af5ee340153176930fe77a971d0fd7728f7231c3438f4fe23046ad88613fd305f4ad1064a6b33a9548670a111c5a4269eeee5f32e8237cad0cd037608
216	1	94	\\x7c5dfa913706ded25d85ddf62c6ff0b3d51559d7da1d9851769858dc8524c9a61640af3b240275fd4cfc818606678614ed3fa7c55ee84d762d28e30e7d93e900
217	1	219	\\x42930c15fcaaf557aa3582df1db50c1e3a564fd2988266cdb0df65f1ba278b35a7a84fd2c85ec24037f66b463a303e6a6727abf11218e5f433a829a0c05a4203
218	1	224	\\xa63b3b566e8f7e17a2a4b6efb751a0967b8fff400ae7dc40e1d3072b78878a9520b786b223d68721a7cc40c3ab5fd929520e28e48c73ce0a7d16d55bf4ecc00c
219	1	78	\\xdc89f49681c7aa0a1d03e6548c0597044ba557ad8eb900012040a9de9a234e31e03011921d48f28d98aeae161f436472b290bace0844fabf45700675d47caa00
220	1	405	\\x098708c1f06149f92ce9ff5a9dcd43800e648fb59ecd0bf1e5157bae9b49088c68d8b86bedcf4670d8c1b494fe55c2f8f056893cebc7eacf192d9c0fdac3f908
221	1	208	\\x0dec2ff8bcf7f5e3c8a7f8fc2e9cee2fb2201da25c752011c415be299e33b7596630ffa7e355d63bacc31a312c19170ddb7c9205001846ef084c58b62b57ef0d
222	1	61	\\xca9a4a4b2ea9e33a11b8a4ead97ee8c806c00209350788dc0abe925fb9a5214eb902f936d8b4e5c5e41b5da25f5e899765a96c0dac0fc591d884a721efc5c605
223	1	378	\\x2a1284946d5379a3eee08ac50322674da335a488fc7ce0a030d24ec7b84086f90f0a95813f1c0909afc9682b71cb44a0d4d8fc2886629e69f8684809b06dfb0a
224	1	35	\\x46e9516785f3323c9ac2582e6e76bfc781a683b318eb1fc46876148b47fee2460a68ac5a25c3951998915ccdbaacab20f7edb08fe0031df0178028296add6c08
225	1	205	\\xb0c75d5a36de36f4c69c73324f63661be7fb7df968b632a41603349dcee9484fadbf74cb997421d696fb34c81949abf91ff06259c69baa5f2e390fa023efab08
226	1	292	\\xef11c4e7023d49270d67be89f42cd6b96e10df9a7ae489bbd48503e9e52e91e3061c6e623a6cddd80f98920c5b3456d937b54fad91718046843126c6c11c6d07
227	1	401	\\xec7f1993855001452eb9856e7792284719adaaf2db90edaa9c6626615980a07f22bc2622f0f9df82cecfcedf964ed36895c0aaae270e7bdd51454ff8caf5560e
228	1	116	\\x51d90fcc6c340e3ce1a29754a4ab6b5c1abc64321940f5ddb7e19640e6a8d566e34cd83498778f9fcf55aa90f2757a7fe17dc96844fc4b2955489bd0152b7e00
229	1	22	\\xb34086887f090d7454ad1c92fc1b403bbf69f9b81c1a9c9565269920b0d5a5edc910eac4b724a8fe6c0a038ad46ea3df2c4fcdcf167c2d149865db5540e40300
230	1	134	\\x8040d2c1562389f75121a2291c6e21053a775f86089af92be5b7855e57d92d779f57c351360aa392725a455da7a93d69a1209df11a5120358b42c122bad10505
231	1	382	\\xf2f9666e21c6cd0c92dd6de0e7af63f3206b7875d69d6888982c10f1d3302ae420d1dfc6919cad1271398dd72944f1582a1df235493b91e6ebf1404a3eb4380e
232	1	69	\\xb11d75c24dbfde951e17d8ae9ee4566ea9e2113a935cd46f1a7197338d1c1685822e3e7eef170ee673b5c06bf6345b2426e97cb2cbe7370e02f7818c968c1709
233	1	227	\\xa2bdaf50f80988d083ed5710e6d6f8639e3193465925d64cfa385f582423c621fe7c76ad4d50c0ec538910b27c4c4a1883e0740beee0699439172f1816a76a02
234	1	248	\\x2eced4842793eb0c8bbd48c3c0229bc8b66ad542b0f484aeedf77a91ad9c97ee0ce3d2a38a24432c0e92de2b426d5225ef5c5d27f9e3fc5166d5b359cec14f03
235	1	154	\\xe7e64f810dbe2115890d01dd611de2d514b7219893b59f59b3150571be46a1c678e10fcea8b785c133f0a7d2192b627f8a9e88bd3e22cea0998767db500ca009
236	1	216	\\x0e4e43cf767df14ff7f329cdcdc753411ead0dc1ce6d767053764c98c63bb0e6ae3cfc0f4d6fcd3b5415595937915dc669c3e5e732c3c79150f2ae1aeabeb005
237	1	314	\\xda5e85e15b9e9d02ce7d0d4de5299f2615c2bb79519282109e43076a6bd34d2b3c972a2c46198ef916a4c78746c6c0fbbc8319a594a9b0a87a48be00b7565707
238	1	74	\\x883553dd1530c18b21950f74f3f009ae0f93a3313d7b73db79a46335349dc8daea665775136b9f6aa5b56a7f5684eb71eed81001a14938a85a77a9202800e902
239	1	270	\\x36374b9671a2c7f68acdc1be509abe972dcebb070be325af0bf44c663e68deb14cda1a0ac9aa260ea886396d5f834fa4c75e80eb5fc437bfb07904ca5ba3ca02
240	1	43	\\xa86d44628bad20e4458e6ddae53f588ba08d3318e75da6ce077581c9ad7555cc3aa314510f688ee15ec91bf4c6f3cc2275391a79ad1d307a0319736d9d75f603
241	1	236	\\x6ef2454b27d71a1c5cdc4229daafa702fafe353b5c63905504318450311805a60bb5c18c198492797449facdff6f32d4f21ae0c85c1456f520bd09c252850408
242	1	115	\\x70031ce1bd5ab5b17196400edc91b1d2eafa6516b7d13ef6a1da717bda7459081d13dc43ea664d8291092216450acb768faec515e21faba84d4049f19621e00a
243	1	189	\\x4efb1993f0752f90806756f6804a0c14617fb82ca963b01d5643fc9b305f600967ea915d795e7d6454b04a13a6edbde49b7fcb9a9613b47835c9592f3fbae30b
244	1	100	\\x331cb3df58e1d3e889601e19add73bae77e05c1b1a743f725d1e2b0ae66c68d4184a5fedcf3c28ba8b9e4022e3f7adf06a36df0e6d96103ac9266d7f84d5110c
245	1	321	\\x216dc9582e1fd24b675070bd15ab50d933c431af9361c2ba4d0a2f4a42451cfafa2dd383abc42731c3b98f1bd6fe983e9421f83bf12700646edcd41cc5246a07
246	1	111	\\x7f0ab4dc01c7652f7f8536cf716014790cdc0114130bf0b749f7431622d0f165957d99c6ea7747b0509d977734e4842206ceaa9080504d946c4db80586be8706
247	1	34	\\x2becc4f5a4bf5167285f136862d4acdb2387fdae54f7eb09d4283596293620d09e9a1dd586007a3639ffa4bd34784b0e30c10c273a6978fc22c3dad657063c03
248	1	278	\\xbf7bc367fbf523a049f2dc80da9c6838a918ec39ff60cd4307572947271e13a82a9c106bef4217318339ed228b49c6b8804dbb8ef2144ded329d814a2627bb04
249	1	37	\\x3711add4af4a04669ac40aa952bf397038109c59010c6c48336bb5b4af28c9c46cae74874cd08112d9cf20b519bf78ea0589a84e2de96e7693f48fa0a73c7305
250	1	281	\\x9a1c066e7ff01f8df8c4731ef75e38aed7b710c6f466fe961090cf47228266e0700ac8ac596664c8eda27bcc54933ddb55bb8bdd044b7f4188b1acfef6d8e70c
251	1	307	\\x8c1f9761b8894fb20bfec1398697cbc7be5c3b3e26723c0c22c436677cb387fa5207f134b6acde3241ea749234618e45e4718e1ccc21d92eb2d72b139623c90c
252	1	372	\\xb8ab484cffc403c30f5a10158d1147b6b4ceb9ee66197e6b144a53442b079f6eb45f382628bb73dead7f1f8ae4704b71c78b3dba0c800b6b4833a5562cf16a06
253	1	54	\\x51bd6712136b7cf9a9457778735a2f4611d5484bb9b43fd2ae43d02ef9e4e2c82d068bbd003c7ee91cd0be60449bf3c5ff4a9eef8e7672489849fb5f974c2b05
254	1	359	\\x8976486cebd469d6f51a83902b0594fa4510f32341bd85cf9c554d5b594cdf3932e449c6077824502481908c0888cd1e5cfc6e45a94d5eee61fe55f621ebcc00
255	1	262	\\x24edcd63360fad4ff0aab5c04c4809ec4019de3b5e82df81fdf7d4a716de0b2a9c73a4bdb9e4f629083a7dcdf336c62cc3b40e4b98318140c7b152d4f7bbab0b
256	1	197	\\xa2eaeab7a055ac05a53b60be712373345ef4c509e1a00539f5076ecaf7985fa8c62612ab5f0a5444965f1a1b1b318798152715dc61388398ba281791a50f9d0e
257	1	358	\\x51db2004e7a82a6892162ba5ec165a264371417a55b20fb39f1fc33703b654f04254726171752f49651ba7f492cdac81b50ff00b76a1803ebd5dfb0cf2a4af0b
258	1	341	\\x83d8aa84ae40f4a42e60809c823173ce99bcdb8fd3497a66aa7a2605262f6f9025ec4702193a3d4144ca4844f91b6b1b268c2b91a27aa239d4cf3584553b4103
259	1	282	\\x02285b7a2e57479a0a0544c10ac1fca8063d190d30b6025bf7e2a1510077574f5a1338be1c3aa318f9134028505b5c571dd321519d04fc396e194c5525bd6102
260	1	188	\\x7f22659a30131af8426d9c5f9697b8d727a946d0d3f16ae011a6298698830f598efae3dc8ae8bb2abec086c0c27bfb1d5dbc2812f0b38f2c6090d5ed3550ef04
261	1	272	\\xfcf23c1a21ef9af356097217a06c47dbde29866e21271d32d1fc1aae4fca729d9fb605f0d8abaa4fdbfe7afc747d1f95cd8247be89377684807fed51c359340e
262	1	242	\\x0944137f8924dc8440f93fe4ebc7ef68865d5493c31e08674d7f9f10df061a700da70e455494f0555e2d7ffb369e59079bd26d6c80ac2cc52d62b38f19775703
263	1	356	\\xbc42412d9bc65ebf35566e1ed95891ab6d94fc43dfaf7cf3b9d42b58907b4575fa550453b94e89375e03c7f71b843427f63c25ce0437f793efcce7b6de1d2200
264	1	151	\\x70842d51f918a5bacc2b6010cb06aa5777cf2000ba51147e23a9a594b10321a63a14c7f22585fad18b9ecf7a38a78b227652116826e1c3af0d1f5d572c64590d
265	1	183	\\xc651e595ef59a4c2505e6031b37ef4ef59ba20900610ccfd5b15098be00832e1d06dcbc1db292ff4dbc6bf2a0d7d67e16ad50187d95dea7c75fbb778a711880b
266	1	102	\\x17fdc729cf0dde17e3c25d1ad5300f5c3107c92caacf1b978304af111deb4c37d1bf098f9d3025d0def4373878bad05eb8b32e188b895272c438c1243b135905
267	1	379	\\x20ee1f928e9aff1b27aa4d4c47380a4d894eac7e425e98ed96e8c1cbebab3ab5fffe53831f6eeeb5cdbb2994317d48ec992dd0f58bb3d09f5e52d7c82e82150f
268	1	185	\\x6bf4596202983a7a201a62cb1e68428d9c4b7dab59445b0c70fa34decb06123cb732f75e8db3e3d14fbd5cd6f1036e0fb7e4d2081701b2dd89d18c43c1bfe505
269	1	264	\\xcb5fded17e2eca7bc69c536ba7bff2000a4932efe11521878318ca603689b1918bd61dc2172d1a281c2ddf2dc8e0d04c58b997f9fe9d182612e76c909d14440e
270	1	395	\\xe9e100ea608fdad013b28e0b9e2d9922b70668d9c6d4e09b9e98fffce0ad622afe0628d1c803f8996b03f23ef2e8838ac94f02f8d303590833366753039c3b0b
271	1	310	\\xed961de064a6a6611139f08cd8da7cef41b7c040283cfa0dd290b6f8dc9781f669c44b42b163b37e0eb782a2dfb1b24abb396e5d0e0f8efd4a80ea5fe9ee3c02
272	1	349	\\x822c23c56f7639d83566d59646c9bd9af2f2ff7ce0a1428421876470842538196e6b3a2bcc5604ee42cc4e54aab97a4b76dcf292374e60ad3e9973180f8e680f
273	1	273	\\x295639cc12ba2ff98623c176e73a41529bc943c03e9364d3bf893f9879e1b6533a3bfa155b507c057c454e70cb2330f802a6d6da0f7e2ee76ba77fbffa185e07
274	1	124	\\x2d27a5027b719ee5ca356a746163004ddce776574bb2a84d658ff4c2c91ec8f29fb604d36bf6d8c74d4e382692ffb214577fc652b7e13c8ed37920a20fee5408
275	1	161	\\x8d321e3a24555576178b97c3c0ad797acf79d50ddcb1db984058399e3da6f97afd104590af6cce70739ae5c6b3b7e19a55cdba1fe3f67de03d3b34c25f03d50d
276	1	352	\\x373083dccc9dcdc8efe6b47050a90e4f57bf419c0cb63851b0a8de8d69f53e039bf2912a65559a2a38f427dc2d0021b11acc043ca4fb052d79d9508c9452870e
277	1	101	\\xf1b60ebe072f60eb9d1f65e8dfec1df7e0bc41d52b5320183892bc6ddc1a87de4636eadc73340d3216b5f3778a176bf5a37fdd32bf175ac90f9e9ef6df295403
278	1	254	\\xe45c2c749cd385b9c800dcc3bcdb30ebad54d5496a64cbed4ca3384bad4b22928f797dcc15df8726b29cd2c3adc47b39a2b6c65c60d146752791ff436adf4b04
279	1	177	\\x8926ffe577d4f53e0f8158a91d8c0beccffd502258ac5fb3f5f25efc95fd6a2f436a0973d84467b4144cdfd7297ab99baa12bb7c98deb9c43f9173fbe5295208
280	1	39	\\x3611155ae990036d030b99fcaed4d8a1ba5e84a34a00ed149fe304a7cb09ac3de897e481a1a7d2207ace3dbf83e734b81497b20e6793fe1803bd00392fbb950a
281	1	406	\\xb31bfc46f02acd8369aeccab25e81b49739899aec6a05df31bb1719af2adcf66f8adcf22e20e8c1c302611f1bbe8d6bac71e5cf67f68841940b9d96141a6890a
282	1	339	\\xb065001fd51e30d5d7e595325e4cbf127208414b8b2d1a39c866e613f3be0105e026dbf918a29a931f706f65d977fdf1690774fe51d5913b895c76cc4e7c120f
283	1	410	\\xcdf27311fc817165afe941bf6c16e65e5c6005ff5b324dfec47b3b01e9e92e20b6c00d8beb178b56b94b2d9b941b11dccca8148bb13640e1779ca176d2723807
284	1	330	\\xe798118f60afb40b57a395220cf4a02cf16a94b9734fe9cd11eb4de1fa01d65d64bef76b9d4ce7342052569ba498be6e38db63fb935e1c5db1fd0028e2f75909
285	1	226	\\xec44be54044bb521e2168dd36cd090435db2fed610e712978988e8becff6717e454451500beeb1ee38155c3fca915726f82d2fffac2dc9d36daed7c71acfcd0c
286	1	353	\\xdf145b70866cc7d8e55168c67d9a08a5c289f41f7c34989a82f4dc6f5f4b8a03501ba407afbb6ef547a82acfca5192d06c13665fff3166ac820f82423e23e50e
287	1	238	\\x469374d26cb2a1a6f12680303c9952ef2a304266599e859a0a987eb0e1b24b59bbe91b6dcb9210f8ed7b82b1838ee6ffe61df77c389e8b3df3e189c42794c30f
288	1	140	\\x0b626710a827f57c05befe1fd5ac224b1a7ecc82a2503b27c821b903277137c3958edc6c67383477ab4acfd803a3927225cba916dc22bac797d6d4261378b405
289	1	245	\\x5325fbd499600295e5e2213990ad1c965b4fa0b58dd02ab1e2916372f5bf250cffd798b25562af7ae22506369279465d39ffcb942058e9d005ae82608fccfc06
290	1	128	\\x6038eb18239440ae27fdc66ec92a3a166e041bdb301cb3e7e3ecfb4c29aafa4fa2b2081a6ac2630a5b50cd45db18588586db4960026b5723bc9033cb1da9160f
291	1	194	\\x0ea6e9e492d24daeaba6f7a84edd9b43e3d45929ab774a44dc568ff41c0d63c5adc55dfe5f797f6ef0ccc1322d44b00038be493552ea4671dd72ddc492b4ea07
292	1	246	\\xcec0c26b792ee91bc90f0e9255c84377548f47e3abbddbab6ffebbd1ceb1df25a8e42115585147bc9dc6d81f17074572a61f1693d9bc422ad70dbee7585a610e
293	1	235	\\xf59fdcee6bb8b72238c5f7222f820a5cfd5b21e81a623c012f368cb57e89d70dd68999475c68c72012a88827ee4070f15e6ad9ee3f1ebc0933e89fb55a29e80c
294	1	222	\\x308ed3b9c0693789a41be549ced0da5e046e87f52ecd76149bc8bfdff4fb1dfdc6a8b51f2f1e6190dfb47a408bc73189037f99417069e61b2e741e13ca5aa506
295	1	45	\\xd1094ef52a2cb26f8630fe8ede7266399a9c00db75300af10cddd846df669f21edfac68b057d1485f39babf666f5ff0f38a7c077ee34ae6d8e4ece5a05c31e02
296	1	10	\\xa27a1c8203f3de1fec51e7c6a76cad0510aabe767cc55437e3b9b5f9e95747adec77965d22e2e9db8ed187accf0131595d19a8491589c3b64c7856c57709d605
297	1	286	\\x1a610a7143e354da322f776b90cda075a16a2555c524ce04fbda09ad6a6dc08788e96ee7c595426a83cc6002ddab07ad786f981c8bb1c78e109b8eddd101ae0a
298	1	331	\\x584444299a4b768bb29773596ba9c4d185342a3dde98587e853622e23c36b70474aa8e6cdd7d2dd31880d90cb3c8f7bfb93f4aa9702fc75946a9875cb7f65a0b
299	1	265	\\x8800493a29ee52f50912c3be5fc23fb36a885eb54cb65481ce61874c5eaacc6f45826d7c17c8371e9f141cf8416a7d85c169e819710452d1e34961d25616c00d
300	1	399	\\xa83adb3e2f1e36c341ee35f0eb7d328075c2ff7cc8777904e1fbaac71afeb0417322751cea0dfb2a61a4985bd00c6f65408d5489ff79dc8257468956943bf40d
301	1	136	\\x78c48f97d931049bec885305dcffe92443cd183a078e1eaf58e5219fb9833bb9f93e0730ff78c9a77f95ad2301a1b8f60f2123a4b389ee6f79d31d2812733a04
302	1	214	\\x58aa39d947d3faf60614f66cb8bc0b6a9b2671b45e710b3229cfcdb369666bad4375d5ff98eb4359d15588102798e7aea72fb87ab15e385dc1489616305edb0b
303	1	80	\\x0fadff0f224755cd1e7403c93cc4efcc04015e19c7d677cd8fa285d004d7b08086987cee9d1fc96f3f5399a1329869bdd44fff36d9938aeea0608f0a8d5c790b
304	1	423	\\xdc7e370a9817b3e54143e73c21547b432d9f24afdb6a7dd852f68aa6191301ca1938ed5d39fb10278ab429f74852e0af2320dfe43ba69f908e4812db5b173208
305	1	327	\\x25cee65fd56a627aeb5c9b27d43ad3feb5569d1384cb5d6c71ceb5bf2eac762ac8c7f4b8b8d69ba0df271bb9e91f7d89aba34bc1cf09559490ba5e2eefc7ba0f
306	1	416	\\x1a9b6b84fead4e6f0c1ead9f0675197029cc80bad5c4488809324be9451a35109bc0c982087296c875544de7e50725fc0e694e2630886b97f1ef7fcf7a099a00
307	1	68	\\xfd7935b73ee131c9bc3690720d08c448112c1939f3fd1c9ab61b3de5ba27c6a252526e1dcadc1db9b8d558af727095c77b35ad8cfb1ef0a40b7590d02ec1240a
308	1	77	\\x91d52e5a2ec2c983d688d10187800ee7b1eaeb4208bb20109f430234d84785185b07311ead70cf7e7d0257229bb39faec56c07d3bac36b773660d7c481847104
309	1	342	\\x18fee729626336c365e7e746d2871108bacad3d0cf1ee2b87194dd509ed96948d751cbbf18d241f00db697592d758de657fce592b6a5ea42bbe19cafd9329700
310	1	27	\\x72e545c4edd9b8474de89d6ffc1f97b6602980b228b6d08f06fd67ff863d66814f938882a6374ecd200f26bb270baf20b8d4072a14be39076fc471c799f58806
311	1	93	\\x9b62e60f016b506c3078946b38bcdc9d23faa7f49d1f75b09c8c53c9a557d2e2aec37eb31c785af1ff2cd8fd3f328d0a00462a374b944f7a0fd28bbc3838cf09
312	1	364	\\xb3ee33bd11c6aa65250260bb0c1d99bc3e6af6118074cd0303588f272ad5788972db22c283635f5f44a88dc7ae3209701b262b4f3d671612a396abe4929f7c0b
313	1	29	\\xdb18b32d9130c5fa6009e5c4960c8bf39da58bff4281d722c5db2dfc4f1aaa23fa62c57b1081f053cd8032c1d8a6df7255d4aee3ec6de7bea9b1fb81c1812c0f
314	1	40	\\x4a44f44e7b10591f486c6f5a8ca26994fdb4f91235bed6112e3acd2cfaf4fe4e132062e00c11b296cfb8ff308c89c257db4904dd7f118d9e05b4effbf7b71803
315	1	15	\\xd10788cf44f8e2f678e2c4fefab07cf3bedac4503d742cd539c2ebe5f4035aad06eb614155fcc337ab8b26e4b734fef7d259fc43d3d4d8c6858cbaf9a1f61e05
316	1	394	\\xe845e90cf950811268f124873ea3142d57cccb0bd9c854d90f43f31eb02950a1d6cee6c8e36b685f24f1118522e10eacbbd4ed18746a67cea6c9a5ea0f683307
317	1	373	\\x50ae73e4aa22c5a2e255528586ed7cf93b73ffddaf00158f97d2d659cf337a239287919461e0bf34666a4cbffc014523045bf012490485f45fa6e41b8d4e3f01
318	1	329	\\xd0af1b189f5a7de259baa8a84bc35fb6f16959cdd9c12a00329a81b8b70b0eb2d5c8fcac80e01a5ea331fc24cae559237d09ef3b5a47bf52229915f727f9dc01
319	1	36	\\xb71bc7971aafc7b558bf4772156c00872c2322374fcaf68e87d8fc3eac5d1ba6f20e28e745e5a46aa9e2fd5674ebe6eecd4b4367b78141d7b7f254fdb548f004
320	1	3	\\x5f7b32775c9e0bd88c7dca2ca02403b144e7c0d0d082af961645f2b47385948bc6616b144b19b13f98ae54ef905fdffdebe8b61684ff9fcb3a42d8f09a689705
321	1	132	\\x83394ca27d9322cc066371e4d2a79281fabfdea65670d1706462679e61f0a21e95ad1b5c31a15e18d935c68d734b1a769eb30f56fca86e5e2a08f3846902a80d
322	1	155	\\xfe92a3641957a92ddbe70144419cbb176964a0128c2f557a7c8e7fcbe44251a52ddb3d94e41ffae7c53ae5b00fce833b61a0fe175cbc5cc1ba41ea8d2ebdb300
323	1	400	\\xd8356e9a7c30c9cc5b1aa5ea61d83e3a34ed92da293facff32e7f4c297c117b0935778208d657d71fd0a2faaa927eca62629d8745ebdafbc30e2be44ed65ed0a
324	1	413	\\x51f7ae6f2b08253abd0c91b04445e879258c8d1aabaa379142eab8f121163f49940b44a02fe31bbe46471d734f745833cec137a56f7a188070c42d2851911d03
325	1	263	\\x2411491e7afa2ae230dbc3f1d0eaa934ecd9b64d7aaeb4a44c27f4ee4fca290ed6601e47572d53edc21c17587532a69f6aef01a75e167612426f48b586d4c00a
326	1	421	\\xd6c5eee763896d6cad855db7975862505586d1632542f9dac9bcad015df1bee6b9f638213951025e1c00a27215b83771b141d2829989909220aea69c55d59b07
327	1	24	\\x10383b6fbd95c75282df59e8c357667bf92997c97c2494515aa0b15621b4f283f005d39ac216190cb65dff9be26d82dd715a228133c8acc24bd6d3eced60e808
328	1	221	\\x87360022fe48728a5da2cd219801f7ab811f0bbb38b34341cb5ec5e1fc6fe83c98d76480327ec324c0015ecb46200f4110eac8af6e2db0af49d0f66f62a55d0b
329	1	107	\\x1213587741c4437524eb7ebd14b4b2c8b1dfa9adfe4514ea7ab67268ea3afeda8ffdf9f7007809749677bfcb4f7415f7018e02a959458ee7ed53a877ac15e20b
330	1	201	\\xf8ad1c0722afea6b4a1e99bf5b4e62b49426030e4d48f29529371eb8e3832e12b9b3e569bd7ee696a9b8b0d1239251537b426abe0a395d3fbd6f446b350d5c06
331	1	12	\\xd0e10657d96f18a0c2b720357ad18547aff4c64e4f6a9a0832bf9726510306236c54dd4d15faece879e694507e4b64e561a94b7a189f922215857dc55ee6fb02
332	1	296	\\xffcef283c2ce4b0b8f5a64ee4f036e4eec6aaed693004700f0036d153cb799f07cd1b21466bedab65b2fb58e88c776a6c949567d141e8c75d4532e734296350a
333	1	386	\\x739d46898f1c5fdd603c435e74d9a5103c321db4e96e99fb3fd0690dc8424b71a5756131c1044e79b7771c806f61780925f6933df8e5a57164e50596e32e1209
334	1	148	\\xba19fccdd728bb75a2e5671b3bf1fa32520f8a681a73ba6d5ab63b5593975daecf90f6e614c8f74d7534f9eb4e77467c7dff59898a19e82aefbe65cf3b094703
335	1	374	\\xe38fc1b3599623523873015464feca97de44a3cd16b174644cd1ab7ffc7be0ca52e77fed49a2ff54658ae3fbcd4a6611553c29239cfacac3be697bef5514a802
336	1	184	\\x021fa535515e9decb3a421c384db87e305e35314b4982b85345a9fa309369bbc1b1da42d1aac3f2420514f22bfb32f317b7e3f8b9e1190349c17e2f4a32aaa0c
337	1	297	\\x3c7c47b54e55723f9e640d75b30296d91b24f0130e5d2ce34566fda26101dc55302cef201850b38575db1ca23dd5422e57908a49b0b5a8f06c03407d89bb2f09
338	1	129	\\x1a90d994488e8df84c5b28dd3b810eeb923e670227a8c23aea04199d2dc735d0becabe27d262fdba3b67c4a49e68ed5a8e0c4a12ea160792931700a4d9120209
339	1	215	\\xdc4e30dafe713aad63244134074af5295a63aa8fea99dde03c7a9a1dd074b178ee8f27422aa2d6c00cfe6a117d8f70e6f2b5848e8e9115a0494d2da04e49fe0a
340	1	324	\\x195fd71ff668f098d3d0628041ca1d99df8f126af0c35d08a0a35a0d0fda30d12ab2261b04bb2488e7f5bae75b48b097dde70bf1f2cd2aa58e14f236fced860d
341	1	256	\\x364618608550acc2846fa77955aa6dc16c5b796d2b6b74f95a93cabb49345f163baff15d3222ad29e0176ff344a72ed44b61961528f4208e02fa1b5620cd6101
342	1	295	\\x6efe33ae998363a715b2e56cd433afdec9b5ec5d108a79496f8953eccf19e2b50c972fad0b1a6534446e715098db48eb415db035cd4dda345c201cad0a262c05
343	1	85	\\x847fca3f5bb7a8ffac037bf3ee1b6cb6198fc14d516bcdd72fc5a7d809ae3d9c8b02520654dc8e730dbd4e3d19779573e63bde8000e447805f70ff02ce1f2007
344	1	388	\\xcb8d9693f6e8ff9be23555a563d1aab4007ffbab938c1eb41fd1af41251ec7833c038cf629d83a90d2e7eb71c216272a56293b6cd239bfcf03c864ffd59e720c
345	1	42	\\x3332f7499b185b88e3e0bd5f5dd15d0e4dec0cfb880572fef70178450269c1be8102f9e55b77220f1734e8b010b1217b9ac659549bf3f50d5cd01dd64beb650a
346	1	20	\\xbb18633bd8d9e1bf43fa8148bb4cad2f64354a26e7cb2fe71bb91249aa5e5ff16f873a0e1579311962632a750358f3cfe2657cacfbfffe280f65db0dc4bb2a0c
347	1	241	\\x12e40a1165a0673b9d17d0b062be6a66c41be42aba8fde5e965f800463f11b12c8535c5a5e2004159bfebf9be99547753a06e620c4d4bd96a0f0ea00fee43007
348	1	404	\\x5eb749d06e62b3bce2e334c6b71d5ccd688421bc07c26437483c5f456ce3f62175d9cc97a5aa6b16a1229320e8f67c49b243c465298464fa609410dda7b75000
349	1	350	\\xd494f32b7cc8a05397518b44234718cea08fdc2915ac3bbf953663b4c682a1648ddc2f449324fc6deb1832739f6c70e2554d027f736e810693df00d7dd3aec09
350	1	13	\\x095c18a024a15b8cb67871dbbd9d454ca77ab5671414848bd2d17dfa95a6f22b171b610358bb433b089a3dd93ebf1d08d4a972d57d4cf26c3fce50216473f305
351	1	123	\\xe4d46090f5aec9be2e127e4ec5e1f74a9aefcbbf7ac6d1aea46b828593df42412a4661f196a47abe3f1aee53d22e01f16628d8cdbdb30ea01ad0ede439ccd60f
352	1	304	\\xb736013c9a99c870128745628e5573c99d0bfc00352bf5e5e97a6b989083177a2de9999708a5ce66763a4b17961f20b297bc6f0a4a577860cd8c8ec4fc9f4d00
353	1	288	\\x0d4ecaf08c76e9316141bfbe72558dd6788b9ee9d4404b574d060c140270de99e6a3ec4d0919d9509c91abbdeae65bb541a86ff8ded710c24bd97c001a909d0f
354	1	32	\\xd592de3f10aad7ab733c267933cb687b3361444fff19d27f60954935402dcf2031a981195bac9cf820e0bcc2c7e5751d04be4c3f069673d6b4cae58a85f74909
355	1	391	\\xa49ce307f5da19202410f526ae8241b0aea85025c735f1db66116c7f59312eb38887060761cdeb763d8f59fea7f938f214f1562e64ac0a99a79aed0872c7a00e
356	1	7	\\x002cdbea0f3581a7782b1dfc6a11370409a1d19f1d66fc17e7f7bc345da142fef41f204d38803393eb2b605f8298811c42097a8a4683fd7db2d6fa6592adb307
357	1	73	\\x7b1ddf8697e003d9ee0e550de1d6564297db6c60b944600e53384c35cf907f4c87c16a0a038ac10467989617295043907f80acee894ff1ff78cb3ac53da78208
358	1	8	\\x7009a424296ce3e774d78835d530d3004747a97d8b4f8a317758bb67ed591ac9193a92eb1d661983b58cc78e2804e6b5f724923e0335c82b392d8b8a76ef8009
359	1	87	\\x9861a615c9db43c3dd1f5baad34c7cd3d5829f178d9c6e9d9da02aa4ed9558d22668a8dfa926a4c609f96a0df346b6e2b4a1b8ec2c76de7bae728c1768b6eb06
360	1	90	\\x76761d9b403385db28a5d9c87bc553b5b81755a3d5dbb58f7354a87ba74323052eff7b0eeb77309e2c45aae87786422022a5dcb72ce915bdbefa71901a312901
361	1	389	\\x67569a4977486158558955d0c687bfbbe75da76cc34df9d306572076edbc6d0c4bfdeb535260a10dc9f3870f5690f6d086d5398ec6d672ebf47265c9bf68d308
362	1	383	\\x237497f75878cb5aa8d1c4450d75e98f1676877817707455c49268fbf7b7f4ee53c4eb8166f4a402e1f84aa1934db39484b61c5883a7d7dd06ca3de38f35490f
363	1	217	\\x112600b3d037bc2893196723e9ca55295e36f7f35bc681571efd2d4786d127feb07ced0a8305c1ffa9e5dfd6355fa93381c9c477fc6f40a249eb3b12c615830a
364	1	398	\\x69ca002c891c9c9dee622bae26b6719e5bc584f702a71b3e8fe0f16c12611f4a7da86a56f44fc54d93897eda9d1f68f563067443131847e48b1e33e9b5aade05
365	1	403	\\x2a4751e227a1e22970bdd095cf39e9a633208e0679c40453bad1c81d649b7d2e3e34a293677c02a78c7e9ab60e5739da61ba135f61e7ee8e56f0acc89142720e
366	1	232	\\xe179b32c05b95704fc55eec8e52e397c6caf84a99bdf3be9f6ff3fb80589d9bda2b1f76735f17717fd82ba6c4d4d0912509f9a2971c61eec82fc336492e98a0f
367	1	346	\\x6b7148c0e9c3b3b2f2921aed9fe58fd6adbbe0d9c3f9c5452053cd3f79aa41105ebcb2efc0576f7daf9ec30150648e95ec4fd34b1f9971357139d21b01dba306
368	1	384	\\x30dc388221aa7484fdbf20cf022a69650c54d356bbd1241f2342d729aad0410d98843a7036d57d28566b9e59dae153d315204dbdfb0c1b91a0ca9e22b3d26008
369	1	300	\\x4c73c425863256c22ae0d9ddb53ada1464982463cbaf78f6dcfbc5328a072b362a6cb1dc936c45aeb6e7f24410a76bf02c6418c9d4e7fb1741076d7b606a4805
370	1	234	\\x27bc18eaece84e0605f875afb90034991d1845001101356be834b6b3eb5c9dee45b146fb86e24bb0dc6d195e4f9fc2ca746964569f4cc0cb3046f50032a4a507
371	1	179	\\xf7ab935b6910a68bb87ea3d615407a04ca76a435df1d0991a5157b342b598d17abee7a2b7023ee125b32c9441a23f20e8556c848601522a3a6086718e54dfa01
372	1	127	\\x3f707ac28574828d805420e11d1d2a87f52649c875613043c6ed9aef03b18eafcb625d49a59b0438a307efc80dd4457538422b1927ff35eb4fce9dfdd16c4301
373	1	308	\\xc4d5847802c8c9eb15bb5909a5611ede82346750d5fdb5ec0b7c9a4671f61a63975ead6dad426667775092b236c0a6c69d4d5a6ac76a76012b0f9c0f3a6ba10f
374	1	106	\\x2ff6dbcdf16a33842f659ee1fb8fbef9f9ef67000f6d0af38be3d5cbaa08e0088c0101a0c095646855db3b1bc553b4e94f5988c80494b3de6b44cf7f9000be0f
375	1	56	\\x7a52223a51968fab81f560b9d1c65c13b92e1cd5ab82f6c0f073d8e1e60f08ae4f58ed1b75e29557aa462a72e5c5ac06bb67c80a98f6d6d8dd37f3d1d48ba208
376	1	47	\\x3ad42c3fc2daf360d1238ed075f14528084b0f8fdb8eef5ba7d898ffce4a0ebc90c39fafea1bb4a292df0511d934123edfb0f7e5744be328f9a72c3b2bb43c01
377	1	159	\\x54a1f1ba7b5e8fe10f34c07b1617b2a6eefeba4469727b0cfd439089334e2734cdf69d00fe97430f102b24d820e0c73a1aeb10e905fb912f2dc56cdaecb3890f
378	1	212	\\xc4e0373844cff1326c08100ab770324a55befced45da6d40edcc04bbea7e10e36b55dd9d64b66d5fa0a7481ceac5e8103bc79da491a6a81bcf582fa65de9180b
379	1	354	\\xc9c0050bf02f4e53f39970e94e21213fede2fb5857cac6be722c1e0f40a3ba9f695f2c3c43ded451e56e32898836fecd87edbcc4e45101bbd17bf3c6a36b4208
380	1	92	\\x6c6a1c6a37f0ff74df4f2fc90b24b64b16f369e42c6c4f32c867e581cc7cbb53ad8d8c2a6a5265151cf35f49803786b382ffa09b7feccefe350f9b8a86d7590f
381	1	149	\\xa61eac60516ba30af9b33b26f19249bd68a24c8d40b054dd53aef075c750292f5cbef745a39626791b2b5fda1c54dbcf0e96a909ee02ad4524c1dcbd7a148d0b
382	1	152	\\x0f0822b2acd83844014fc3a824419e2df4e1dd03bef9e205b48caf013c97ed7b3516163833d668cdfeb38021a8088dd4a36dc1ffca13688d9ec9a2bc6ff89e09
383	1	16	\\xcc60dbbe7351d93c2879f3f72ffe9aacfb86a514a25ab4d037fca597c88460edaba959f6611dfd0189cb7bd5448b8521854d749ca77687aba8b874939fe5a50d
384	1	268	\\x2b9b8b69da0c4c88a1f5a6902d2b0be413e5a5ee2350a204243879ed9a972ad4256458466096d283ebf7f167986056ce6ed9cb579e8646ff005d3aca45131a03
385	1	60	\\xe15de3e4e591289153539f7f23788351a85dd1a7ec3c176c096fb63e96c9adc37f2155b797733b0cdb79819f2844054628b45923c4473e1ef36766ff060cfa06
386	1	338	\\xa88cf4caf96e5fccfd2f3b2187d7a3493d710cd2c8618fcdb4fe05e26a3c74c6b7d6aa9f1da1e74c7034cbd2097f975ab669be1bc4f6a6e86bf3dab36b998f09
387	1	213	\\xe30a45a1ac7603a5895117a9f4997812a86b06b49638c456295a7aa045085c38e17ee666016e4fb7c1899eb424b9f50c32ca3f7e2a788740bab6c3330168590e
388	1	323	\\x118ad1de01eddacfc339022df2d8a0ffdb0d8dabd1510755f73b3d2d42eefd2d253a12d13600a1d54de0595b007b56100b282d9ccf9157c5913dd4aa48149b0a
389	1	334	\\xa718bacc0a62eed6f959233830a908409c0f46ca2124cd42ae8bea9b50810c626923b738346265e2d011db9b748662627de610c5943e72314c89dd6e5a1cc10e
390	1	424	\\x397fb0ec3ce92dea41102ff2daae70fcefd3deb439dea450623bb23528eb37bf6384c36b9ad8473ffac12f91ff943f576bd8aca2c04cad96be3b29eb64bc1002
391	1	51	\\x37f1880913a1e74fe9bfb0ad7abe58a80b2fa26886829a86ece3c46983cb3effebe1bc843f1b57312a3e8e83688443c81b1f1d0c88ceaf0e4d05be17853a300f
392	1	121	\\x4ee4c5de80f6ee9de7dd775d5149f8a270a07fd6cb5f64b96d67c9d2bf557e1d69c418b942098dc8b37bcb759ec8d4a202b050aabc6620a31dc6ef340b56810b
393	1	30	\\xc9a11b1fb6637a800a27873fcd9fbb1556a3124f4f186edaf40ab976e72d67195ac7dd5acc91395c02a4e8a23f5039d81b5614edc31b984e69ed7d45f2252e06
394	1	21	\\x43f20f68d2ee3886872879ed6e0de7fe9eb06b094bcd3f1bdc28bfd96927bfb8a96878c30e2e17e7920207e87dcd7e7ecc1f1931e63eddc1f72f2f85b53a7d09
395	1	370	\\x8cd8962797ec9c094755005554d18f07e170806122189db7a8baecac7cabe0339c7a93939222df537c19c3467495ad5ba6d52290338a0b684c50a96c537b3204
396	1	193	\\x899fa045ab86e0a3689f3634a5afe19bf47a869ae871cbc6115e2930ae469f2f7dad0b88ede31be3e0c20b96446aeb3b7273254c6653152b799c56d266574e0a
397	1	369	\\x839ce4d3cb5e2010da2e0d5cb8903681166739f13517e042d9a383f98fab2f707c846f32ba9a24080152ec9bd3bc9df4b5a81ddd70c39287d6bfcdd38ac7ac08
398	1	180	\\xffa0b26b88d5b6b0ca94dc248058eff7b1654d1dd0a5e2160136e6081250c5e9e4033b2a273a1d0d3e3c0cac30584eb720082a50c2071efef0c0819ecb29b00e
399	1	72	\\x980eb89ec9ea2970cc197e71c12a63f9dc56911f3e414c98eb443cbddb660af530fd8bed758a1d3b57468e3f7f19cc5b6acb4b10d7c47fb720d93cce167a6403
400	1	231	\\xe0c04166cf21b78abb63885be0976e9ad36c2896b4d2cc206b31b7773965ca363fcc91abaa0a2412931689eacd709b2962bc4aa44e968e7285857dc8724d150d
401	1	204	\\xd61f1498b342ce83dea7db89ff4d324c05540cc72f4d7d70d9adcd489b685f6619236ed2f7d83d0a5946ce18522f389fbdacaa37703164955c13276e4e88e70c
402	1	181	\\xd0c7300395dd23ede7d5a254b58d90727af4af6f6d7dde23a9d05335a0268bfaf4d58ef8e832636895363d554852bf9e38aa8a5259ec1b7ccd362c4deaf09200
403	1	130	\\x4dd51aa865c672b332bff00a4d1017736fd71ee47b7ddfeef4badc3c7312d100c9faa5be63fb864f77ecdec940f57eaa2f769abbc0bbf099362868bef7f48102
404	1	397	\\x605800fe5133a5b50a3a52824beb6dc4b23cbcf47b382ccab569b36f730ebb7a935ce57e8a41b3bc64aeafc50e8718f8ff99dbd63195a87a222c797e172d4504
405	1	38	\\x52da7fdb24c73356961fe4214e2261fa8636c7e7de0ce36d27234bfd0ccfdb8548437b166d246d37a14ae74cd3a6a8020686f6a5307ba190e3daf89e2fdfc80e
406	1	142	\\x136dc52abd8df64e48920ff0d2fb25c65f23974fe21ce2dcb0c745b6d1127e1f783d870deb1adf7c216f4712f604702881cfd1fa4565e1367467ceb9a4543500
407	1	239	\\xd99d8b461777ca0230ede018209729af79325db836ba99ac4ee224d598b731aa9321e026e53d3c42b3d88bafd086cddb44285990a06b102a1aae9258d30f2e0b
408	1	120	\\x860bc22adb2cac5f9b2a64a3786bb507a850fbee7401aef2e2715f2f55d8d46abbb9fae952a8286c9d9ccdda454a8b7ab7c11be25107502051bd9bab9091c801
409	1	253	\\x77593d2e57d9b39f5e882203161f1c073ed2723c3c93252c9ba8cce39342520f628a2014684f4ff709d00b08ccc13835dbd6ce13f7994841aeb9addeeb861303
410	1	250	\\xa0beac9b9e7668bb40551f52d3fd5d9f86eeb6fcae8a0fffddff1026d7f5250010d2d89a8e75b04bfd6f0952154dd5de4b9dd02ee8eb97945f572a1facaac307
411	1	312	\\x6b3feba6e827adbf177ce5c6df6601c08c93c4a085adbf568c4a5f70a14d3d3fef4064dfee29d0ae11b3589b14a037d460679b875d9a1cb5c9e12a5f6db1960e
412	1	138	\\x532d40967738f17e9e1b7ad83a524c0eaaa41feb74374c05a4ba7e30f3ffeab5830cab9e8921932a1430350260f79dd2f5e7ee139b3f5bf778eaa1824a62ce00
413	1	294	\\x27dce942ddbf53de4302d08279f0b15943c1b8350ea986ab684a0393c1246c95e1d3a930bd3fb5e6d2143ef62c829d12c365811ad7ed172eccdee49809cb9103
414	1	322	\\x88e0de863130974adcde0858386967ffbc973df21a526e29099b2762eed6bed83eb9f1d09c6c285eef4603db9cc3e52bbf94a1c2f0a936e157a7ad9b2114a209
415	1	14	\\x12b778d166b09919d8daa3ab708220ea03666dbf5c7a6ab5acf2eb2801d6ca821beb66f4621b0e3bbdd7bb4c24afec2fe4e910ee94b158ffe7c4c42780517f07
416	1	44	\\xc78778e072955582f914789c34ad4fa18c74ca4a8789f5016450159e0801bf7129eddee8bf0fc9acb26cf56cc54eee1b7890da328df8eaba173f3380b766200d
417	1	275	\\xdfaf2a8501cd7a3f88dfd1359924ceaef2ad8949c1f414e02e60b9e6854236dd272eff740ded62f560e841d58d99a66ec4f65d27c3be736a23610d0846ee3803
418	1	418	\\x4040b7acc616d81e00aab9e3b59427bffb2a71d653e81ef4a95fd250cd2639fb6414c4c96a9d87cbed80d65eb74ac97773b30d5a0321cca418c5fb1d0f465e0e
419	1	62	\\x7135697a274e3959151c84edc73e9e1cfae1281044d6865f8561d488b2b5563944ca166ac018071deb507221fb59f8321a4cefb34dfb3ef1f3030e008e4dd407
420	1	162	\\x99187c73210d29bbbfc0376ba1158632097329d774fd2a7dd597a9b52df2183165fe4d2ff43bcb223091adcecda3f8d39c98abc751573d4738966edbeb929809
421	1	291	\\x27d218b0c3c86f34c35bde1285d7f0a6d24fc7edbf50694efc762c0c27ccf162dcb240046a907f8fe5a01fd2ae3004ef6ca65583a4ea51516d5c4485f5ade60b
422	1	190	\\xd5aa534041b3d400e9021d8b2220c1380cd041362d054b6e87e6534d625bebef0899ef0ffd5af2861b9c4403dd31306e9bb901ff251c75d8e6c45aa6a45de60d
423	1	223	\\xf685cade53fe879f8ec1d1646206bee65ad7d7c265ca57a4849d02217d6bcf3c5df69f7d881fea3a9104d76a2d38bfed2d588c6b57b714193dd8d156d1440d0c
424	1	362	\\x096e29ae7a02530e1bcd5c4d866487bdb61ad2fbc21eb1dfa4d365f74de57a437894901c815da99021bd00c753a6bd05e8b1a9905c3eaa0c65ec1cb57a7c460a
\.


--
-- Data for Name: auditor_denomination_pending; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_denomination_pending (denom_pub_hash, denom_balance_val, denom_balance_frac, denom_loss_val, denom_loss_frac, num_issued, denom_risk_val, denom_risk_frac, recoup_loss_val, recoup_loss_frac) FROM stdin;
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\\xa16c5cfed3956325f6eecb00f848eff541a89f48c4901c59d5948551563c325a	1647694549000000	1654952149000000	1657371349000000	\\xa1f7e8f207772bb43cff98cf5b263f95c973d65f8d2e1f0911533057f56daee4	\\xa843f5cae36c57b13eafa8d14eafa5421a8cc163748679d5591c428df8e04c5e30f8eadf5430bb0e70b3522ed38a44347483e7be05b39ebe0419d94762ca450d
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xa16c5cfed3956325f6eecb00f848eff541a89f48c4901c59d5948551563c325a	http://localhost:8081/
\.


--
-- Data for Name: auditor_historic_denomination_revenue; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_historic_denomination_revenue (master_pub, denom_pub_hash, revenue_timestamp, revenue_balance_val, revenue_balance_frac, loss_balance_val, loss_balance_frac) FROM stdin;
\.


--
-- Data for Name: auditor_historic_reserve_summary; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_historic_reserve_summary (master_pub, start_date, end_date, reserve_profits_val, reserve_profits_frac) FROM stdin;
\.


--
-- Data for Name: auditor_predicted_result; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_predicted_result (master_pub, balance_val, balance_frac) FROM stdin;
\.


--
-- Data for Name: auditor_progress_aggregation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_progress_aggregation (master_pub, last_wire_out_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_coin; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_progress_coin (master_pub, last_withdraw_serial_id, last_deposit_serial_id, last_melt_serial_id, last_refund_serial_id, last_recoup_serial_id, last_recoup_refresh_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_deposit_confirmation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_progress_deposit_confirmation (master_pub, last_deposit_confirmation_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_reserve; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_progress_reserve (master_pub, last_reserve_in_serial_id, last_reserve_out_serial_id, last_reserve_recoup_serial_id, last_reserve_close_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_reserve_balance; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_reserve_balance (master_pub, reserve_balance_val, reserve_balance_frac, withdraw_fee_balance_val, withdraw_fee_balance_frac) FROM stdin;
\.


--
-- Data for Name: auditor_reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_reserves (reserve_pub, master_pub, reserve_balance_val, reserve_balance_frac, withdraw_fee_balance_val, withdraw_fee_balance_frac, expiration_date, auditor_reserves_rowid, origin_account) FROM stdin;
\.


--
-- Data for Name: auditor_wire_fee_balance; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_wire_fee_balance (master_pub, wire_fee_balance_val, wire_fee_balance_frac) FROM stdin;
\.


--
-- Data for Name: auditors; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditors (auditor_uuid, auditor_pub, auditor_name, auditor_url, is_active, last_change) FROM stdin;
1	\\x9183f255a3ce14cfcadb9d888d5d323476aff2718ef17c6b4428fa0b5c51c9f8	TESTKUDOS Auditor	http://localhost:8083/	t	1647694555000000
\.


--
-- Data for Name: auth_group; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auth_group (id, name) FROM stdin;
\.


--
-- Data for Name: auth_group_permissions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auth_group_permissions (id, group_id, permission_id) FROM stdin;
\.


--
-- Data for Name: auth_permission; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auth_permission (id, name, content_type_id, codename) FROM stdin;
1	Can add permission	1	add_permission
2	Can change permission	1	change_permission
3	Can delete permission	1	delete_permission
4	Can view permission	1	view_permission
5	Can add group	2	add_group
6	Can change group	2	change_group
7	Can delete group	2	delete_group
8	Can view group	2	view_group
9	Can add user	3	add_user
10	Can change user	3	change_user
11	Can delete user	3	delete_user
12	Can view user	3	view_user
13	Can add content type	4	add_contenttype
14	Can change content type	4	change_contenttype
15	Can delete content type	4	delete_contenttype
16	Can view content type	4	view_contenttype
17	Can add session	5	add_session
18	Can change session	5	change_session
19	Can delete session	5	delete_session
20	Can view session	5	view_session
21	Can add bank account	6	add_bankaccount
22	Can change bank account	6	change_bankaccount
23	Can delete bank account	6	delete_bankaccount
24	Can view bank account	6	view_bankaccount
25	Can add taler withdraw operation	7	add_talerwithdrawoperation
26	Can change taler withdraw operation	7	change_talerwithdrawoperation
27	Can delete taler withdraw operation	7	delete_talerwithdrawoperation
28	Can view taler withdraw operation	7	view_talerwithdrawoperation
29	Can add bank transaction	8	add_banktransaction
30	Can change bank transaction	8	change_banktransaction
31	Can delete bank transaction	8	delete_banktransaction
32	Can view bank transaction	8	view_banktransaction
\.


--
-- Data for Name: auth_user; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auth_user (id, password, last_login, is_superuser, username, first_name, last_name, email, is_staff, is_active, date_joined) FROM stdin;
1	pbkdf2_sha256$260000$UrEypFkfaQi90IgdjJB0XQ$mRbbUbNVAB9LXtsEzqyWUWRqyQCv4zYeUexFaKReUF0=	\N	f	Bank				f	t	2022-03-19 13:55:49.860654+01
3	pbkdf2_sha256$260000$GNd9ev8duK4oIHjQGtOrFP$XG9r/ny/F5x6M9zUoWuAl7bOsEarVKTMttWJAvxhKeE=	\N	f	blog				f	t	2022-03-19 13:55:50.097097+01
4	pbkdf2_sha256$260000$1071zvJY0guF6piaMaYw2n$NlT8a4xknpYShyGaFbxRmZKezbD/f7WAahhVz913uns=	\N	f	Tor				f	t	2022-03-19 13:55:50.224176+01
5	pbkdf2_sha256$260000$NZ4ZFkGb8XI1Xe94ILxgDU$HfBZOtat2X3L/4VJTm95FfHuhyz6i9gHy5CEHoQP/Do=	\N	f	GNUnet				f	t	2022-03-19 13:55:50.34642+01
6	pbkdf2_sha256$260000$Hs73qeJCwmWwR5YIVqOZPT$c8vtZ5zHvhd4IrcUf4Hv1fyiDJ44i6Iz11DlSV/XO7Q=	\N	f	Taler				f	t	2022-03-19 13:55:50.466886+01
7	pbkdf2_sha256$260000$HbUCLawNhoSFqGT9le6FNy$wTZxGrcB4WsUA87nqwr26p1lifSzSH/MLR2OnQjFxFc=	\N	f	FSF				f	t	2022-03-19 13:55:50.585646+01
8	pbkdf2_sha256$260000$l0Lh5uULZJ7HbqXuH6vfgp$fQA9kt3FAZfDQo4cZ9cC3FxUgx9k+NHZ8e9rdCfHJAo=	\N	f	Tutorial				f	t	2022-03-19 13:55:50.70326+01
9	pbkdf2_sha256$260000$hckY7Sf9zG6VCLwH1zkqAg$XXaOblQYUCVQCeQhNyJ69eEIbQ1q+P21JmNqHiOWay8=	\N	f	Survey				f	t	2022-03-19 13:55:50.820953+01
10	pbkdf2_sha256$260000$GMcmPniFkBd6s0abcPIm7w$zb9Wu37taKAoZirE69CkaQ5VSDa3dL4OHSvuxGlr6LI=	\N	f	42				f	t	2022-03-19 13:55:51.224069+01
11	pbkdf2_sha256$260000$J6xm1TuoqXvW0HyWSwK8sU$fDm5VxjlWbZys2zB+WJgO4bwBhN6HXZXsb5Qyo3mPdU=	\N	f	43				f	t	2022-03-19 13:55:51.636393+01
2	pbkdf2_sha256$260000$9X1zII1mZCV1eI6BrjTUeL$adlv0RTdtneYYYvH9HS1ixem5QK+mc+7KnwpxlOuakA=	\N	f	Exchange				f	t	2022-03-19 13:55:49.978379+01
12	pbkdf2_sha256$260000$6ZehBToqv4wY5Q3ysiWmI0$Xsnecy/CQUW8Ocmu+X61UIEhztYk0norSZgWtmIwjgk=	\N	f	testuser-ymqrsenl				f	t	2022-03-19 13:55:57.435679+01
13	pbkdf2_sha256$260000$BUgf7v5qZhinv9V3i0lpTx$25IkYipNbor29RyXQ9Pp5iD43+ssIw7VXhPPHz1r3Us=	\N	f	testuser-inu22dec				f	t	2022-03-19 13:56:08.713205+01
\.


--
-- Data for Name: auth_user_groups; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auth_user_groups (id, user_id, group_id) FROM stdin;
\.


--
-- Data for Name: auth_user_user_permissions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auth_user_user_permissions (id, user_id, permission_id) FROM stdin;
\.


--
-- Data for Name: cs_nonce_locks_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.cs_nonce_locks_default (cs_nonce_lock_serial_id, nonce, op_hash, max_denomination_serial) FROM stdin;
\.


--
-- Data for Name: denomination_revocations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denomination_revocations (denom_revocations_serial_id, denominations_serial, master_sig) FROM stdin;
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denominations_serial, denom_pub_hash, denom_type, age_mask, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
1	\\x0854eda36a2ebf536cf590fb36e9e0e8f3854857a2e5f20152936c3eada9c0d3712a17ec8a3c195af03851983797273df4abb0e965b86dc964ce6f3201c8e03f	1	0	\\x000000010000000000800003cbb76edf43257694182ad42c8f6392a845442053e471222b9b1e58ef49884ef30155c23b7ce67a93898b83b3551b7e407c1d3d129b529a448e32e6576c2795e81caaa82856e02f98950b3bdfabd354470d61ef1baf8b08aca5b0f2772b5d1c05443200e15e76879e5acc42f0504ad17a49904204350bab734ae494b691667b5d010001	\\x908cd163bb01e7140671ef7dd6821f9848657db4e87ba8e804c40c8a396e2ad13f384c14fe3303c7dca88b5548d5b63e883fb52f7d4e794e8133e4a96449d00f	1673688049000000	1674292849000000	1737364849000000	1831972849000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
2	\\x0878c53e144d7d4ff0567a56fce9297abb1a252586b7fed1e131f381a109b26a5f453f1c612a845db3e9a35bf310be593ab029b068890d27df18f0658eb41c96	1	0	\\x000000010000000000800003b37c9d1d4b6e134df43a195ce4d5fa384bfd78136166a6b57b07fe26aded9eb2cdc87eb5381fdf3e8e0cb1f986689b2d4c69ceb2b17f1495f367ea5e49d1e286b35c9e03d2dc42fd3d9d69d20faa13c7880e4a1980db248e4d0d3294f3aab4b9aff1e778ee3db616778617aae0faf708a509c1d9996a90734e0ba359303b4bf9010001	\\x8cb2a327f6dec0ca40dcb31b6ef9d759cc6e4a3cf279d1015de6e60d46685f69bd3d7232d64ec337400095de637e35684dd3d9709e65d8cb332ceb949feca006	1667038549000000	1667643349000000	1730715349000000	1825323349000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
3	\\x0974f91b94206233369f72cf6b1d37d0f827ee1ee1e9162d8b117df87c8cb27e23486cbf96d7b358592d61226dccde0911a610114fca277e1e1088a48f78e425	1	0	\\x000000010000000000800003c0336c1ef12e2000bffdf732f1377e94e07021762a47b822fe8774f9be9c5be42f00a4911bad9770ea6160b62e38ddcc6f89db26c6147b9f6172f883e74d5df133f0396c9518e99ec1ff8352cde530bb7c99e2283b3013196a31bf0ce02a6adc88fe2d3235d782abe776f2873ddb9b91bce4a615e6587aee461b8b9a886ba0f9010001	\\x620cf014d24d2f07e6cddb4b01d4d734246e5545f5797beaeb22fbc65a5d849732741cbf964404937262a0f36679df0d71d031453d5890eba0695bc3f2efd007	1655553049000000	1656157849000000	1719229849000000	1813837849000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
4	\\x09006422b521af95e4bc784705dfe71142657d579a836f666b0da32200e1caf111e6bdbc6ad9eb9a3631fd8dc6991920ebbe53c2198c26ec9aa597b87fc3cb72	1	0	\\x000000010000000000800003a2aec0d40926314cf780017c1782c52b5e65bb2dde8412977b3813532cfc4345f4e203bc4cc59635e5b186a553d897a236227f115f7704248059b0142dc2da65b189029c58f167b86c22ea13c48d82bad20c4f7e943b497ae56ebcfd13838587e1f5ec29ff5e9cc75b16dbecb670bc5e947e8bbfa5485438805ce4ac3d7918b7010001	\\xdcb838a04a7c65d3302ce8b411bd6fd554de5be573ebf8f1ae4a047aec0d47c4773c5e0d400e7fd79f7062876d33780ee1103bb7b8cc35a2c6a3c9137f27c80f	1673083549000000	1673688349000000	1736760349000000	1831368349000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
5	\\x0a70cab5b88e5fbef51fd8d0eb76ac2a7b2655048062f8638f282ac2b5d69e1195aac64fd661f749db0f4eb20e4001213d0eac4617e079729135a77ee018a392	1	0	\\x000000010000000000800003d2bc7e6e4f77ea02e4b1ed9508994526f2f1ca4ebc6b56ae2fee08abc9a3fb556d60c0e9c89a4ef51e6b20fa9a857ce7c0fe98094b5dcd7fd1d6d919efb5ab186d446047e581507ae477c534b6e94a03d7f88be193d8151aac3f928eff3707b849938f692cbf4f57c768bb920a5344d7596006b11333dd7b13cc75055a0a0afd010001	\\x9fe8879b795abf54651751edbe5ccf2a80edbfd11c17ed8d0718a9eaccfb9467d36a739fb3103a3e2bcf51ff466b3ad68fc24dc954d081347811996da7c35200	1671874549000000	1672479349000000	1735551349000000	1830159349000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
6	\\x0cfcbc232c10c9b45e54cd748523e3660888cf6044264ff1d327702cd5c834c270a49e21c5da21aab9862ecf30b0dc2f2d5b0fd656b0f00da48f25508a9166a4	1	0	\\x000000010000000000800003c33173ec14b68abf743a4312122009595e0d31695f0885896b44345218b9cb3a4df8c0e037465b611cb131ea2298c48a861a8c8b1eae2215ba95c899cf4b9273f0f124b691417175c8d57afa7d208222287574835328abe1517ff4e48adbd31d8f077fd21246e4468a3ac9d890032a996e7f40870e12d6a3538c6b45f4eb0155010001	\\xb6bbdc79a8bccb033a1d8dafc442783cac0ddad3ae26382cf412c00419100c503d278cf52824c3e8d4034f086491411b738ed2f0c2ea567047faf5a4ecc9c609	1665225049000000	1665829849000000	1728901849000000	1823509849000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
7	\\x0c7ca83dd64040106e9ec1705183510441613172cd55935417d9d029bb978867ebcf74a9c8c3fb56816f8fdf69dfc6aff8778943619ce59d51043aa3843a4e55	1	0	\\x000000010000000000800003e68ed1d6564fcded51fbe618607042dc37998ec6671f615965e01d8479995cf1e97a215fee0f824ca6b0f5e278e925ec0fcd85839c4f23bfb28cd7cf065c9dcf759e9e42c48d7e4b1035b056a50018800acb3c37c90e7123480baf406d0a32f0dabdbea91a2fb1e8825f5a81708fb09f5860921e4a689051c70d602770d807c9010001	\\x619c703b7360873782de44941a3a66bc2ffa8e47bf7f40b7eeeeb0917013092304b5ac027982b250246f3e39c99a91d3e0be2f57b934de1a97f10f512217f20e	1652530549000000	1653135349000000	1716207349000000	1810815349000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
8	\\x0cc4c2eb616740630ca9f2cbeaef37eb5b978aefe0b196ed1003244f40ebf47a430e7d5e1758913deed334e49b89cc172752f6b548104772a997cdfc7400b231	1	0	\\x000000010000000000800003a941b67262193306856e4fc8673afab29f14de8c205fdbe484f7ff33a48ff61ebddafca54a8f01bafe68c351ffadda742c2f3363f0ed61709601c09d5805a426d2f00e1c5b461621524fe8b4507814d605c509a8890ad9ac010ef5dcc1bd257fa173c3f6c8b055579daf96e2c9410119bc75223e5b66a365903f15df038a1d5d010001	\\x7c35781800e1e2e0881fa369fe1f9be778426aba4f3be1d7e02b0653239ba7b3ac224b3791d04a4f5c1c9a68f44cd732fb2e0ba6f30d6dfce6d8c994c4c0d100	1652530549000000	1653135349000000	1716207349000000	1810815349000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
9	\\x0f84c5f09d50a156ba0e3128ee7c5e76a746f398c22c8217c9636f151f104a7cd1976f18e4dbf96a09a92a87220d2af79cea13e7f6dd835a1725857ad990676a	1	0	\\x000000010000000000800003b34de9d10849fac899c0540ae79ced3ec48c79ee54620d308d7d162d08c495bfd717a1cadd0790dddf734130d3dcbe8a29c953e600e24f20687c6bd5399f540e96446d3c6108aa36e2d9e38a8e6ccf24745cf706d46dc337650b40143b953173c76ecb4fad4169bd9fa607fec7d3eb499a96df3d8cc57176096f16b2b1af088b010001	\\xca2e4416e426ba2942ac1772e119b7e423ce33e1b53c31674803bd852d5538e6702ae156c74700cc96282b7e8fd5f13f3b47f2d0226451756c0c699c41a1f607	1671270049000000	1671874849000000	1734946849000000	1829554849000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
10	\\x14581062c523f4a41b152eab39d9d59e8d450a0a4eb812f17ff569d9528329bb7e4a364f11c87241489ae9c9d0b5021735659eca182cc093ac931568500a410f	1	0	\\x000000010000000000800003a99bb136aef0a97c961e10bcf0af35d057c4d8f81ac15757fae1e5ffca5fea3c0b22dca1268349c401925af8c683c029e9ff13c88e90d490c8954f8ae7204eb2518a27d7d5114c50ad5b8119e4486c893dbc5354b84bfe1f885199c4b75a69adb9b34f6d31b31f0a638cd0ecfb3564c9c11fd7a999dd55156737b70e2bbf6851010001	\\x720281be06ac0eb29e0e96b092a22c7a55c7edcc8be1ec5ee0d4d6b19c9e5bdc7cd357967538715ae1aab3aeb37cc2a846603e16f26dada020f44e2a72673201	1657366549000000	1657971349000000	1721043349000000	1815651349000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
11	\\x1560e0342383bea15b41412b4dcaad94c264bf996e1fbb34f3adb9296b0dce0cd20cb06d6ea267abab19b2b4bb12a3ebbc392d48083bd4e63845ac115614d3e0	1	0	\\x000000010000000000800003b0035a3aa4d3683fc414454148af17cba242a2199560400995f3ca2c55ab40d32a6e9e9659c43492a2e49a365f889e59928021b41b590d69e1de388a173430f2fbddc17259b6a3c79fb16c1002be3711baf5f2cc70be661f6343186dbd0d269300b5d3160b978ffd344c3676e54a1e30c8592bfd759784f55eea634d086397b9010001	\\xb9f0b76ddd89a24ca03f37c523b5a73aea9b17f3649df595c7014f50b90fe6aa96fbe882c42e7d3051139672da8c3701e2ac0259dca7846d61ec901fff1dd604	1670665549000000	1671270349000000	1734342349000000	1828950349000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
12	\\x159cdbcf259f8665c4cc98af76ca50bd1f6a1427be4c154ba030d2feaca6414da55dd92a88d21f2d9c3295cd6b3aaf928b60fc586393a272d94c91a3f521edb8	1	0	\\x000000010000000000800003b4ca3ade5830c5bdcdca3433f6afedf3e5f87cbc3f11c56216ba1bd5b236e356024b0a4aeba0c16a0a0d086e2a8d94d9dc1502bb87c7a1f6f53ee68121b239ee6e41f3703094f36c6a1dbf23557c0d4efa609e752b0c0d467e669102976e66645c471a0c441edf7c564092de16b558d57a53d9bb3b5522a88b17655ce48b683d010001	\\xadc0d78a21f095d72d7471598ddb16e71c854ca2f1bfd44be52db0144445829d6cb8cce3b7c1e95ca6320cbc12bbad4ef272eacd1aa1a6aff41ab7837159840e	1654344049000000	1654948849000000	1718020849000000	1812628849000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
13	\\x1740589cebc82d25b53620a3ed4e00bb202b9a12b94baf0e20a099123c7d92b3b72dc0e2e85278eb7c9b291d916030d7ba18f5b0f41d8b9ffe8ecee5bec9ddcd	1	0	\\x000000010000000000800003f077676971e2af6d623078b4a9e7eaf9adb8313c7a36f76261248e2a5c012d7a1f81425f7074b6c5b0d24275672acc1dc35a05721f7a64aaa080552f21421500c98958a32053c91f5c8675f3fb28f50f76c113089bd7c607e88f50d0241f522e63cfac164ef6a4ff9cfee40bd8c384f5dc1cede58c5b5700d712c4c55f849e2d010001	\\xed49df2bffaf8c51c193551030190f78fe4cf09aab00302253d0e135e2c2a27520efd0052117909e10393d2d97c7c26bb92c1eaf31005d0dfc82bb9d98ae2708	1653135049000000	1653739849000000	1716811849000000	1811419849000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
14	\\x1744aa372e69c069217f630af35d7393a867801dccc8186ce261add645b88d1ff7cfceababc411512dd0bcf60c4a38cdf7737adc220c9a18b9b2627e072211aa	1	0	\\x000000010000000000800003b083010dd1dc8050a6dcde5984b8e91dc95ac1dd33317dbbe1bd1ddfe8824cecad816eaa531773e0e2c51bd1367de3aeb83558a0a23b6a06aae396f3cd108fe5f1f61a962b5a683d259ebaf9e403bd1210a69300ef046e335ffdaffde0dd2c62b811e419274c5c54c78c755bf574afd4709883ab48ced0666c345454042e9aa3010001	\\xa481b5e77c6b238761bbcf540a1efd1dd284953027bd1d432efc089f6f5dbef33514edc66ccf7fcfbf7b51ac4f1f69bc9201a7bde4a15aad47be3650d44ecd0b	1648299049000000	1648903849000000	1711975849000000	1806583849000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
15	\\x1ba8cc59d348c9deefcd7a3f321f727f72978397041eb7c391ba94d2ee3371a76800e51d05982151249ef28a9c88c29dd21e43e9a03e4cad2ca2323358510b0e	1	0	\\x0000000100000000008000039a91bc1a247a949f8981ecacb65c22b4420b303d66304eaf60317be61766159bcb7c33a87c883c8772209105e5c59bb3c1bec9ebf217458f8305115e7901b9d52a1173e0527fea37cbffac2a184c6bd5c6571061247db5f335c992757d910e954540323e3011911a26075aa4bd0d3c8860ef9cc94dd9ad22c2402653a76b119d010001	\\x61a25b476f2a6fa1d191b3ff028a7db6e6fcfaed726d7d15db9e42a1426d19872d9f5a5e1bb87863dfc498ce7c304f230b59876acdc846e0705e98ca4ae03404	1655553049000000	1656157849000000	1719229849000000	1813837849000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
16	\\x1c64113243d4f766729f21af3e3b6bd2be908ef3dd789dae6f9914163e5145d17d270f04de452478eb813103b8856458813f276449cd19e25584e76bc3e6afdf	1	0	\\x000000010000000000800003d10e7a3791adcc06e73b4270d16bfc54f0f5f73138d3a8d8fec613fe145edd3951930493788a2a463b40e9d642e9b3663a0690c34a0ee078ea2f87bf84cec2b66781fb4aa6dbbcb6e60726bcff32ef0ccef3500e972cc8bf86d2c61868d7a9704b6b59921c8c02ee035d1b552e4105822e995ef00312745c23f4c1dc60ce54ed010001	\\x0e3b02c26c2fd4dfa69a043d34db4f32af53f03616e043678236a27f40c9c563fe69952c24ba3a13c0c21269560dc097b6acc1ce5c650296e0e49fa979197e02	1650717049000000	1651321849000000	1714393849000000	1809001849000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
17	\\x1eb8161fdd6e151c02b7a21e3c5a7dda1cb359cbb39d9ade7f7cf90b65672bafa493d51db235a273333cab0e712540b9366f22b4090e908385b19d85f76cc898	1	0	\\x000000010000000000800003a7cd4ae6cfd6b3fbcc23d117aa8b6b73ed223e1ee05f34e8f6db53793912b5211cac92aaa5e62dffff1d996efea89b486bf3df31ba319759d4da9dec57e7bc530b072c33efdebcbf2dd6d50672e2e27423d358fbd55103b4fc971856ccb79de256787f2f044a1a44a2e839385f48a4127d6d6d31eeafdc27b059bdfb4691c9b7010001	\\x0cfa609bbe605289135db877f5ad7338378ebf9da1fe9c4cc24105b4b4a61f216df9fc4979ee47326129ef24edbbeea0b8c33e8ead139d287c27430a55f19e0a	1669456549000000	1670061349000000	1733133349000000	1827741349000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
18	\\x21cc2639080162b969dd9f45292a19f5b6efdd35d60857171e20a04e4c28b2205a54c0a10404d917aa7ca48517bfe3c76cdd8d2f72d18babb1396f14537eee4c	1	0	\\x000000010000000000800003b8aae24392611da920462eff0f4d888de5140098ce6b283687bd8cd0804e5437d432ecc0f6d1b8b8f1c77858ca9bead14a68ac63a6fdfd649fb9a9a239fc11afcadc12b84b0ecf2dda45e8541d357ccdbaef2e1f11684aba42a88329112428a8a9878b9e2513ad47246f1d68c3977cc0125f0599a8ae1cbde85c029dac5e6993010001	\\x0724571cc19a595476b88acc198a4f6d3814f96583b7fc74472666431532b9fb1c6344f5f9c24e2d049b532bc0dd1c831c8fdf4e538832dba5fbccdb1b9e2608	1674897049000000	1675501849000000	1738573849000000	1833181849000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
19	\\x22e01d59ae24d39b0ed77134563947204b6228dd86d8185ebb91d0a030f98b529e6a8fc1b9537693704eb08bc7d83e1b6747c418599a9aa17331a2887b286290	1	0	\\x000000010000000000800003beccf7bec3d5238488586f91dd06c72a7f2752ff41139f66a1405e667ef5bece5b3ddcf053bd44c71508615414f896541da91936f354c58dff433f873dd3d2b8796f36b2d4e85b8dc2d6b2e223ae9fb2de523ebbcf93e6ddda494340b9ba7dc4ba8bf76d4689808f01a11bb3eb214107361cea5cb120da183360d7da17bd2219010001	\\x31f56e34d16c359203c905a80f9c2026c7a63851078a4bfad21e3ec342208c273d52696b219888e3a89d66e1c8e811bcb5edfad1bf2221e58f0a27067ed4af06	1669456549000000	1670061349000000	1733133349000000	1827741349000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
20	\\x2a94f41a1cb5567fce26da0650d76e5916ce7d89d99ff56a8fa8095d5ad23f1e5743e5e099e573ff2bb69916e3196b1c32afddf601c9f516f897dd0bf2d885d7	1	0	\\x000000010000000000800003bb2d31396693eedcffc8cc7db087bb29c67a3268f7402e5997d1250a670eda8e5d7d63a3cdf9e9b1a35edd06c9e85bba3a5e426178e89fa2aa0ab4594fab1cc7a550badc6d2fe1d4bbb226b2acda02ba5f838ab163843e812aed470df0b33851900cbc13235eaab15961a888d2f9cabef6ed70c82b2243f3f3384b9b2ee28a1b010001	\\x1f6b465893a1c15d9c43997d24674aa05e3d57029fe718374c0ea866161fcd1da1ac9fd37d5076882792ae5412fa6877344cd40b643b1e7fd4e92ebdb9b11e0d	1653135049000000	1653739849000000	1716811849000000	1811419849000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
21	\\x2cc4fb95d0f0442382b84bd01a42f5342e920a20110cae193951d0f7fe33dcfaccd68bf74ade7f93a85489623ea281af9f903c62c6206194c873d0322d01feb9	1	0	\\x000000010000000000800003e4c8617a18e5aba72449d9134947478b3d0af777869410439b5b61eb918cf6716e11397b0077e0e5f466ce76a3fc6d629f7fbd460bad3fd152817a817d5432e210076034cd6dc9527a48fe34c618a08ecf540cea9f81de568a778ca1bf94bc043473ae1a3485e51f7b71ff58cc4120f0371caccca9c4450c19db8c808b1a9f15010001	\\xaa437714124717a7516c4dd2ae2793db10fad67c98a9ae3b2154243897678f792077396621c6e2325d3b2750f8ca6a2ce09f42cd38ead9450917e2cdced21603	1649508049000000	1650112849000000	1713184849000000	1807792849000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
22	\\x3198ace9aeda71e45b13768c308485afda7b51d0861a1ecb6aed08dbec9e8808452a1793784617de79929242388ae02a9457b1ad20bf4a57f04fff0e3fa236dd	1	0	\\x000000010000000000800003d58f245fe83346c78ebf6da42c8531fab8cd57ce7aaa97f38dbbc74b24c316fe60083720e6283c4d76a51ac54b59b10136241aa8c397ed933179c088bb0f0af675b15a6096fb625e732f856480fbd989f014a678b8d2779777a3a32e8bfec9eb45d305c6385fd0a45696aeb573568863e0de247957b0a004d6f482bf075f878b010001	\\x4ba317eb9b73c7445746db1aba9091c08cee601bf5f293184e75cf340ab095ad38f3d31e9c0cb9c553a218824f9e9f803139bf99a38297207066cc0824159301	1662202549000000	1662807349000000	1725879349000000	1820487349000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
23	\\x3240d83bcbc4e1e3b72907c2cc2bf16e970976dca7a79fc470105c00dbbcf04e60cecd9cf7c825757e5cbb08c8559e9c8e974aa91b598082ed6d756a17227044	1	0	\\x000000010000000000800003ebc03e31a16ec7052615d626657c8ce315c8bb7924ad554225687fb5c14930fd65caed2c07df71c36ef97434ab95ddd3ac23876da2c653d78646f8d10ea157f439a023bb09f5d7aa1dbea79724833ea9fb9380045d63bae7e3d71da53e54bae2bb416e159cd68272d4693e57772440a27ab43488550dad10618946f1feb17627010001	\\xb4f94f54c4ef92c71255157529addb17d056aaa17913ca72bfebf3ab2ada3231ea67a53d9436d16088002d620cff9c8caf505f7ea50707ffcd47894968a65c0b	1676710549000000	1677315349000000	1740387349000000	1834995349000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
24	\\x33f88b7b8994aba73367713d573e41c198d4d7c92fa2047f30c6155d3b25440ce0c49cf2589183132de376863b081814f4cae66e5501710d758cc560874aa1ae	1	0	\\x000000010000000000800003cfebabf7a793c3678c17b2804ca5ed5652ede9c17669ba896b9a8f88b784255e3128d157c7980505bc1ddcc79f14c0f471056d5b67c6175d15d8405f46ccdfdc528274184ba4900c809f69644ee8f2ab624bd40eb8ec9451ef7dbd8fc1de28917ef266a0d392bd76fe3a7f38c2951c3bd16b746ae52db1dce4257e0134137169010001	\\x0a45e09e3db773b3e8a16a7e5ed4f5635cf2f577757ac5deb59e962077cc8ce441ceb16d66c3b8264ce0752b03c51ffd0974e91c265534777747523e7c7d460a	1654948549000000	1655553349000000	1718625349000000	1813233349000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
25	\\x3b2c865c57d1e55b3ea825a70b468bea5096ae62543082a7b8a8aea4ea05305436d60be63437cbe5c432eb5e0bb89e601041564a342de91b06eed1dfcccbeea4	1	0	\\x000000010000000000800003b37047d0382d58a86c2e7c3e8a85748f22582a285ff43cde0af76af04d4ee0ece51d0e96ccd7e7d83666f891bc1c7b0bcf4016403ef4f451ff089c10aded44f0e71a84186c2afac22fad0cbf3fba6488847008c55781fdb48088171d33d926e73737457bb3bfa1214ec8f4ad410bd6b3029db504e26388cb9be85c1374b7f1bf010001	\\x7d6d2a756cecb176809c29c208a74b9b6ce46eaa9cd06a4474a73d593ef780d78a52640029790c9f3e5d5d5df3e562693b815af72d53443e8200b3f42de40a04	1669456549000000	1670061349000000	1733133349000000	1827741349000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
26	\\x3e287ca6b3c3e3c89c1c0bfaa32134ea28664f35f865859f142bd6a93f5b443295a31bd85f398d74b87860ce89d28eac0a7327cd4a5d6af99cc964c5b6bc1900	1	0	\\x000000010000000000800003c1e3ef608c2886ea04c95193d80f57e44ab3024bdb9d8aa8ae64eed87a0e56b81c740a91f61eb6c116fee5fd7db5d365049c2661242f2d9bd7416b40b113f19354bc6bf15e0ffc18596a877dd7ca8425493a1a36d5545661f15118b9d4442f64c0b038340faa7089b5a6373b5816ed9300a47a12757956adf1e155216ba0095b010001	\\x4f4103acbcefb2e94afc2b2209101d2e66cd4ec60e910c59c4b7f7b5a573875752e8e1e7e32cef808b3261f6b56651cff871416860421a5881782556939dbe05	1664016049000000	1664620849000000	1727692849000000	1822300849000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
27	\\x4420a46c20ddd496e110608c9bca850eedab486deee02d29776186a7103263369764bb3e2d94dbd2de74be963f2663b238f0f39aa2f92696b92341cd58f1c670	1	0	\\x000000010000000000800003d11032b58a6a91cc372c2cc65a5e90b479a97be35a441b8b50c10813e5755022022ad3534875ebad479bb0820814f322d138b58c47b20c39c37e7dae952c0a434b184a92efdee293c0dce6deae179aa20a2d5f60f77cbd07ea1275c11317a2c2f596f69b3db2d768d26a66660a7dc7943800866725c62e6fe6d9a75ac0c94a21010001	\\x34d26d6651024081ab13baced0fe24f84d216eda0ca06486cdc1a662e56bef324e7646f523ad546c8fee6c5b5502b24e5c0c00b0b349e7c6dde8d102f2b5b101	1656157549000000	1656762349000000	1719834349000000	1814442349000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
28	\\x4b54a02c2d34821849f2f94aca7970b51bb91877fcd33692f90f4b73d165b0d9e26d23c88eb0362d070d4e6761525f51aaee6fca7bdffe6d92e5a22a9945a46c	1	0	\\x000000010000000000800003f1975d5b9bf3525be23f62a5990faf58d8a103668855d4bb0162191c9422203d8d99f309097f3a0aeb5a5af0d541f09083bbbcfc310cbacc3df698dd03a7ade448d55172fdc0f07ece183626a4093b3fe9801b17cf2a918fa98b7d11f05c6e522d0308f6d9a9ca9b6b03522de95fe8346f5a0cb67b7bf4cde5beda228567d4d9010001	\\xaa922a12442e7d5a60b58afc1e20785e06d9c6182b8de28644b97235ec77c40e82a6391fe27b78226b2fa7b1d7726495365b41abb07499b60a9f71dadacc900b	1677919549000000	1678524349000000	1741596349000000	1836204349000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
29	\\x4fe010e530e42524be956b619a9fa55b15cdd678d8c3c1436075f312d41c14e79eb16516f3f2ea4be4450c332d44a72231a415ad7b29a0aac493e9ccd192ba55	1	0	\\x000000010000000000800003b94dc76007865d6a27665aac676640f46ad138233927c30569a56cdad531bce233596dd92a973ba39d4908a91c5110a4cd8fa1df6d074e3f332012e6a3ae45346002d5694f0641392ad6840249622a1849a01fce35bc0d8632b26f1f0d8788d919c3e6722cf4e844a0c53e6c5d35612db45943f21a21f6e339fe4ba8742b027b010001	\\x24e901a10fa11f2cda6df4560a8e72330b8f1db42d75ca21f34fbd20098a7e391f9c29ea4cb961666bef498fe156bc9232932d0bbeba2bce329bf7be135a1705	1655553049000000	1656157849000000	1719229849000000	1813837849000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
30	\\x5238543fe3456f13dc6e009dc441153f1ea69be2fa692a6177bab45b0b48d0a59f27d5853e5ba116742220e4db863cd4c6843129aa0e9614c891c5bce3804ea5	1	0	\\x000000010000000000800003d2720de75cecc70915c8bfd6f8cb7ea5df01d249b50d40097466b199915db87034d744be0eadb4aed0ceb2cfb82535d35dd4a82fe3caaba42bcf58f4ffa5ccf3b1c1c62d34edbcabbdfb1939c39f52e084c7c38e7b1fafbb604dce0f89bdf485938516263792974f3cb97b478eb8a62ecc561a990701d06b39d2092e51a6d9ff010001	\\xc9a613ec2d2f99a9687bdff421e05027850684939675d9c0b84d6489c78c06f1c5107b5cfefd3150bb35cc8f6efe4e482ee8f687f8f16e45309d7194a4003704	1649508049000000	1650112849000000	1713184849000000	1807792849000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
31	\\x53b449c22139e7ae35de8da01b955d55b755b58721dba2c0017f18698b88d1346dcb26d7777aa4769a60a121b390739c4416403c2ebb8ee32bef1f7faa956dfa	1	0	\\x0000000100000000008000039a8925478d00db5f7ca89612c349c5bfbd428b418d2363be88a8f2f8d819784ce19414e837f56d19e684a6118fcbce170415207e9eb13825dbcc4d54cdf4fce5a4c32f7280e618d4c92ef858a2dc7994ea74e53209f3c621da3d4f683017e3d604e61b60a1a7035e80f82a93bbfe9a97c60079838187dcf53493ab23da283af5010001	\\xa5f70e066a4b3b60cf3b85f8f92faf71d7bd59e06de90ad97d68666685d6c9717b9c02cac1d0355adc4ba2915b53f100ee8309aae86781787fb51ee072da2c05	1670665549000000	1671270349000000	1734342349000000	1828950349000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
32	\\x569c6b0acd3b8d911e18398a24f396db28e7125d30a51c6252445e97e8bce2b4e41b0df7fe75d1c2784c34e1bf91df877da6779d1b92ded20db4afb30deca492	1	0	\\x000000010000000000800003a4b828372f28a56767ad5ea9c37819a4f09944f039976f637152464dff6635c2a3547650ee76068231d991f47f2f094989bc53d2d921e72574a913dbed036e88d97b9b50395440987f1d9c377b6f224543bda268c29449845ddc98f0983eb6bc399448f40ee5ec349a13a447cffa5fbf69923227a8959e6413d713c045305a91010001	\\xb7d41929ad5bb66355e24b3ec3f059dae96848b3513bf8eda51acfd66410c754c9f993e20085f69f8f0b36ad6bc6c7c88a66253a05673ffd507c7be3c804ae05	1652530549000000	1653135349000000	1716207349000000	1810815349000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
33	\\x59e02dca1ea899e3d5415a4858a8e4b8340888433262a73ab17c3bbac813f3e4d53076e94b03e95c2e7803bb99d8da387e7c8bc189aeb65900e0e2d12c540655	1	0	\\x000000010000000000800003985054fd35835f1d7e3dd96351cb0a858a6ffd02db772bb7f6ecba9791ca52480904fe213ee220824ed8c109be14792bfcf0dee2a5a42547b5efe7d5501fbd555c0052e6d6f777ca998778385c2d0699fd0385444991a030ca76a3de6b81d190bdc0bdfa5a95b71cf081dab63180a5c73d30bfcbfa589b07cfd3a882ae836453010001	\\xc930cbf3d990dd99919c10451392decd1f6bbafb4204e1b6976e3c5f2e34c802b720abfc4bf15fce4855e21682542537268ee59b6daed698b1241d954eb4cc00	1672479049000000	1673083849000000	1736155849000000	1830763849000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
34	\\x5af46348e8c73d3c3f7e02c8f01672e3fd03beb0129015b569315e0778c97478dedc1bd57991753bcc0d33fc122d62f98d3017868e21405f52ba24e5edfd53a7	1	0	\\x000000010000000000800003c3733684ee9463985a1f6fe11b24da0664483cc137ffc16c79cfdc2ebcd8ad3a1af581703849aaf79d2d467c5e706ced7d5c0a751536deed8d41d99287e8e8b6d0b1eb33aa495f520d91563137e6687ca223740217386356d3baf6bb78c620aa0cabea24572db5d895dd12144062f15d0a40b3167d5707a7147d4fbd1152a121010001	\\xe2bac1786c8954c853835ae12a4dfc64a3f283e1fc0b1bef4e35b06b2db2be088d0d1d3ecfa103c7c287038012f846094572dd038b9e980078e644afb7346f02	1660993549000000	1661598349000000	1724670349000000	1819278349000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
35	\\x5b4ca329c52a831bc797b592c697682a45f82cdca37b36298839494c5bab8d9f57110ffce6a8249981d49975d5024cb3815d670c27e96a024246dab139aa67bc	1	0	\\x000000010000000000800003bfa8fc7811d2c82165615e4ee633bea32d290132d07a7f76f2b310f790122852fcc987a1446d0019bb9b60a73fbcc811c270e38ec29ecafb06686e09708c6a1850288eb91a40a5e3f0fa60d639b07de314c9a78400b5529bd997bcd0d37dfacd42074f2c71d357551a0e98fe8633c09c50e0a3e2de47b555fc2691313d28da2d010001	\\x647b641a53cd5776711fabcb8133f1a801cc1aba7870be07a368e33e6713dec1f5d94109f6d253d516b6f3c89aae71730d84b720837c2b78e4c56cf9bc8fcf0e	1662807049000000	1663411849000000	1726483849000000	1821091849000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
36	\\x5c58d22884e5d7143d7afd74936f1c43065e548fcaa950623b38e8e1a8518064a31f8d653d35079df81597ab2a2f78a8e978ff1adb4c53e81d0c4fd7575ec0dd	1	0	\\x000000010000000000800003b77fe594a3ed0ccc57435cb75f2cac1e5a382fd2218f48c7e9f3e31cf5ff473cac5edee488bbd69ca60b035616714e6a8855c0a6344bdea17776f8b269128ec583f020971612440762c7881fb3e68a3702223fd96238bf3de394a4a8cb7cf12e32781c03b71371a736347ae88052aa9157fcdb9d1d2ae69aa44f142360c477ad010001	\\x0f45f560f107df6772f5c27adf71275ff0ce202c990a5fb0e40b9c75303551cc7eceecf93dd6cba363909009acb5607307d3feaf5bcb4c1bf607f2726fd62006	1655553049000000	1656157849000000	1719229849000000	1813837849000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
37	\\x5f7c310a371b497608fa9a39789a3c741fcc2bed2c2010914282487b2d915e171cd6ef9e97f34357a45a0a704fe5a443f4f453edb3a9f1c6bd0319e88c2a95b6	1	0	\\x000000010000000000800003aae5702fdf486887ebfc1cd0d64985af31a98a9bcf4158af32924a987efbf5a9027a422c28c796bf2d917b8cf72d05360c212edeb2dd1edf55f48cf03768d92ecc5ac3f6dea8100a0b5342e35eee26e4989d35cc784f2b6dc323bcf24b857a524b52091875378fd54b6fb1cddcb38ee4d85462fb5c2d4cb0147514353c6ceac1010001	\\x888f260677da725c502b878c51193b8f65f0802b60caa767ce2b69dbe77381203260f9863ae5fb2ec5ff2a51cd883b4c0cd64e59b6ab0137e0caba0ac34e8f0b	1660389049000000	1660993849000000	1724065849000000	1818673849000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
38	\\x6014cf39e40e79d4157a9f17d7501b2e7bda967b30fefe352eee786199803016cfd550d257643b0fd89784eb356d6d8516227cea11e5800439af2ea1b88e4b16	1	0	\\x000000010000000000800003ad2e89de9860d2d931755db04c2f7a666a0cd26496b7aeba566556a1ee0685ff5f6329566d09a69534b22ef2d12e95718a5b22327094fc3fca92723510ae64ed59301f1e488377985ac48244ab8ebaa8b9dfb20f0db759e1771ba90af2d9a79680d07af146f6fc2d472355fd30bb570287f475d38a5ed06828f10665acdc423f010001	\\x2ba016a695923df6084961c0f5ab7f75181bcc39349664e32f9b6489341beee462b72fbc8a4a20fc1b1a44b15ea8003841595d75899439bdecd0885b1cd37707	1648903549000000	1649508349000000	1712580349000000	1807188349000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
39	\\x60acc271ac41653e10594497cfc5f5d18cfd55bad96bef4734088f155ab85070b7dcbae6db390e6daaae685b30a107eecb331fa0b7f232e516e01e69d23f2f5c	1	0	\\x000000010000000000800003bf92397c8580c3002ecb65c3931630b2727cffa12892714b80ec27d45ce2890f88678d028f99ad98678b86306b1389237366a3f5b712a48114ce7b0293ed453c5360231a466289f8834f1f8b88087a1cba2b5ce7a83152419fd4f7dfc6655ae528c4c207c00dbd956efdbf19349a1a867670774dd185cf24cda84e037029a919010001	\\xa32dedc636c3c47ce72ed013fb24e55189897a97db6549e6e918ceb4e6bdee6029ca53a116f735bbfe4f4ad48d776483f242c2b7bd0da5de156d658ff6058d06	1658575549000000	1659180349000000	1722252349000000	1816860349000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
40	\\x66e8f7f521ae7edb85db39f60e32696feb7d9045ce0a6261eaba71f275eea1ebb456c46eb5476eb9da4b7a8e3837735cd7a799d871d1c7c3a922d35f11ed74bf	1	0	\\x000000010000000000800003d1fe5fba933877d36db34aa957f9b687f883c77d6aefb0b77e5bfa33ab9099b123d23bf950c84b805919d6d9913ed0d164ea706ce13509eeae21d28ee2ee708e54489cf35ee054d84101f5849acd111808a639fb2e0d7b88e500be48f5e97d0a57524c6d0455c0659db9331a0ba6c2a70a16c106a176cc4b2892f5750cc9b98f010001	\\xf831e8de58f14e73e70498c7b76004b4f68b3db845a9b8fa1300936de8f4636c19663abe23612d555fc55a999ca12eb428495ee2973c9069315eb806d7075103	1655553049000000	1656157849000000	1719229849000000	1813837849000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
41	\\x6c303dfe6ff36ee76692c1a2e8ec41a3c213c78b7568abce351e6a4cd6c644fbb56983013eebfdebdd54d441f08a7fb7d3605b897d46e6e6db9e3b10a2a21ead	1	0	\\x000000010000000000800003cda9d47ab6c87019e32e3f44b62d51e03156913a0fd2ada43eb26d0dbcb5ce3258121006d45a4970de77331024d5b5eac22e673d6c2667169716ef2b01bfc79804d0db961981ce2e75b694085eaf4ce1aa1147184e845a66f1ffd0c40be82c6cf72b580db1eaf20eaed719ec63eb2f91c7d7a722b3dc1a68d9cb961f8fa6ab21010001	\\x48c59997f48c131144700c5891e18d4503f5844f43d402f999ff2d537aa419664a61ea4a57f714ce0b28d36259b36bbcdd0c2fe8385c6a10b67226c7a8706b0d	1674897049000000	1675501849000000	1738573849000000	1833181849000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
42	\\x719c74445a9f40171f0c42ecbfca8559d49e2f1044da934f0b55aafdc38e094e5ba2f5647f0a92a447dc7c9d2744891b30798885da9375a7c038ac6e20bb9dd0	1	0	\\x000000010000000000800003aff6916265349eb146c463a5f1c9fc2f14066f772e08ab15d481523487f35e5be4d06369f02f27e4abe4a1547b2c96a25dac5bd837269a5e97153912a8f55eadebdc96fb3dba2f9ba36fd4a1beef4ab61e0c450b0a452dda488289d4458ecb741293d9ff055abf4acde683f13a6e540de875e173d17fc970f14368c6ffa4e6f5010001	\\x31c0a025fad18ea76995c51f9f53ef9136e7c20c15a511c6fa10256c287a2f07fd3978133864d88c6c0c439c995d25b140eef3fccc13e5c522e2fcddcda80502	1653135049000000	1653739849000000	1716811849000000	1811419849000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
43	\\x738c85cfa1abcade437bea565e9170a4fddae30a8d1506134936bf76f2d39771e1ce033d94342df76edf2df2fb3636fafa51595119ec6ec1f2d494c0f5fbbede	1	0	\\x000000010000000000800003abb4b2e82235fb183e167866de63621a4431494d37862ab86098f1ad1cff22725ba75e94e337e271cd2f565a8489ab99d86a361597230d2d1daf0105b9dc9ea068a44d550a8fd3b299a0d383fe61140971df13192d2fbb9bea77c32ad0a6b4d52216a4a1e06c4a451da98e061b0eefd4c058663fa2813df3686432439545260d010001	\\x31a48e8d8fb0b199b7c18bb9c8c2827fcebad32b6e4789a7a5f4dfcf9e3ce21094f0d9dc01c045c751b90cc1a1fc6db35ca5d795cc47284be2367d4a9db25e03	1661598049000000	1662202849000000	1725274849000000	1819882849000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
44	\\x730c246cb80557ac222473a76f6d16cf41e0467e247797d1f587b4f3103d4c9f3a4ddb184d310a517bfa458afbf6d8cdb871031ba4e69cac5b0fe2e45cc15c34	1	0	\\x000000010000000000800003baffd1f0bbbf471b3935e87ed1be6c942f1c38cd608c62b7bf8a286b41a3469db23fdee50f717ebc77da83b5dc38a4d5599f92d4d0155e0c7194f5cd9b986285c57bce271a2b4e34d4ce8af3d2cdc8393844149943d029cab735962ef90b59c496a3875b828245cddd224e84d032ac4f683e6b43d6d68f31d1e1da80ca664357010001	\\xd6824e7c32e0c018e26221775bcc7960e662b4d4a0ee5a9d64cdbf5c6888316fdbd8e5ef563fc4ed5711a9f562909e15625268a4b83fbdb309a016c242eabb0b	1648299049000000	1648903849000000	1711975849000000	1806583849000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
45	\\x77488334c735cfab33a35fd3efac7d136b6bb8b91caf7ff510030502ef7a38b06203a57ddd84990008aad8624c1e905d8e5fd9e2000c4fb6a4d35f9ce0377282	1	0	\\x000000010000000000800003c9889225419a722daa082cce19276331319471f3ed811c3a4fa4d69ad2af48808babeb1d249a64320cef8d375c644cc63b4fb943c6c93fad1c4ac6d67635768a86bf9be2827cc368f687655092be1244c3f083b8f90e608e27c1ca447ed03114907ef67cc8bea8e653f3f08370f53cb2bf2c0db5493bcc4cda0baaa2b2b30173010001	\\x1b4c332922f5f3c14dc2d9193c741223aa3e737a12cb0235d24f179da622d52d781ffca7da47c976cf7eede311628ecb604b35fc98b1f41f509a022dda48a10c	1657366549000000	1657971349000000	1721043349000000	1815651349000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
46	\\x7a6cff7f2fabf50189133f1e3e3aa9e1d63af17a5dee0f17c4fef9e6cc5036ef5a3c3c4b444fd49d013dc5b1d1a4f5bc67a0e0bedb5e47f80c74b2afa1f9cb8b	1	0	\\x000000010000000000800003c0edc810926d18111e023e138ed29ed9f34b73927f6e5e9f6b255acf67e244f876c36fdf84b24e91cbec4e3b86514f5eedaf9ca2cc370100349186188916ac74b6eff2eee7ead21413288d63d6f0fc67abe8979b8653f75cebb1f171817362af2c1ea463422009a23789805c29c28f06da8afd27357d053427b72c1a20c46899010001	\\x30fa0f53dbf916c763789faeef43506cb37c69a0359774480fcc778b78d11dd22c0ed80f6f708d16bc58d7ac084a18c42f2e1cb94e52b95225be94d787597405	1663411549000000	1664016349000000	1727088349000000	1821696349000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
47	\\x7dfcfc6a408fbdb4499d118778344e3b5e02aab406eb394f2c034b91b90cbf2f9e70c7fe00e834c66d2b25a91b16831439bbb03e227c23b5cbffb8fb2369c819	1	0	\\x000000010000000000800003b5d3ceffa9e7c2c07110d4ee94c9d88dd697bee5ce0a508ca552c7efd7529cfcc9ec496f81bf08f84fccdad1f37032b073232e7975bc4728b6699a1ff0003cb82b51658720e26b8502ce2ced74482fd8da67c208bf114db4cebc5b502e2c9b1fe871369c602f5bcb2bca188ec097c0a7abba885ef2e30b07834809080e76d333010001	\\xe3e53ffe45c21d49aa97c3b5f433559fd8f60d79fcca57a12405d0d6ee1b12efabf79dbdf20c1215b8faebf20d866835fd93db48e7595d710aa3bd6c4f980e0d	1651321549000000	1651926349000000	1714998349000000	1809606349000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
48	\\x8118db4631e97d8a64f96ff773bd9d4feec917f7c67ed1c00cbf7706aa0a0e19cbc085e146cdb635ed010b983274375b640bf4820d6c82155a89e12fddfb6d8b	1	0	\\x000000010000000000800003a834a72711fe0c00f18482962a12ea2c473c628b10d5cac40717f6119b6329f1951d1df3f99b14500727d1a24c44f0983bc96713079b62b2c2d944eb26c755c356aa424e914b3747b89e73b5832aae0eceb493e41edce272fe5e4406bd50170a5264a9e5b87cf2338bac583f9638f0e209979a301a4a9c6281620a2baf43e109010001	\\xa4e6ac3c32bdd6f3e1f86482cc856776a79968e5ba79937df4cea762585ce4d397fea42c5643ee0335c8d5d9b091f119ccd50058d44e61c19a9eb0eff1c2120e	1676106049000000	1676710849000000	1739782849000000	1834390849000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
49	\\x814ccaf10b0dc015ffb025fa558fc1adeb52ff238b3424f9e253b2334a7203d550c12205037520fd3e7f98bb6feb5e3d9c046449341de1565ee280c9d33e677d	1	0	\\x000000010000000000800003c77198e494af39e735a0810a31690a66f753dc0960a77b2cd795efa2c4e2f475e601f84b21bed60a38d56cdced4fd9aa1a5c735976734dac38995f4f99080c8fadcecad31555769159756af43b6f37dfcece73ca3e9dd4badfc4e0373af7819a239731af7a131ca008c0d985be22b196a8d87e397a9b3f898f8f3ec48e3af889010001	\\x1b44c6abd64858f0fc30d471e5d9a0ca41079a7a5cceb86422ff284c2b55a7852d5e7c19f5a496774b60465cffecb63b17c19a8b4a8ab0cd1a391552c69c4102	1664620549000000	1665225349000000	1728297349000000	1822905349000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
50	\\x8204d786f2f34bcb9c50237082f1bdd407b6e48ee7bb49be4ff3c747d3f05ddd808baa1be33133b0f57f5f18ece377230479fea9376dcf22a1394a2203bdfd9f	1	0	\\x000000010000000000800003bd15bba92454cdbbf7b00e76b839932268d49f56eb5a9dd0189a48bbb488be3db9dc4805d8c11f9185f33e01b777d5bf3953aaa2e2aa12c8ed4d6b6ab6cf408041356268c8fcd9c450be88a84eadc70a08d5e3936a6584aec7708f072ac1c20e94410a993deca9e218b58b403c91d55ad042431920420ec5254775bcdf7f41f7010001	\\x11334bafdc48a44104e7924aef06c859091d67de0fa26af9e80416daf544b5470566be37cb2763ee1875820997a31e889c88618e9a9df9b6d80281cb3a749f00	1673083549000000	1673688349000000	1736760349000000	1831368349000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
51	\\x85246f37873e9ec5795f0fd642c993c1841cc6db9df4f328b1df9c7015f205224e36c104ae3ad5399f045b874f18b02103cb0fed09d8be3a1fcda92c5eb014b2	1	0	\\x000000010000000000800003c1208a67824009f3db1997174f6f8365d32438c122b2be0b0b07c8f80fa12324e9507a4f6f70da7fc8dcc60d13a40de74b433de9e2037ef5f685657d139c2d8bdcf77f808b5b281b9d40f96c2e5e01f30e2fbe73db8f6944cf10e007cb517233c1698ce5040f75cb064e553fd734cc935537b29b01797d7ccab8003220987bb5010001	\\xd0f517fd29a0c1575483174b78e4eb6b551f26742698aa69c9b07f7539a626a1ed5816c0daafea96aa4d587b4a2c63bd8e619a6263ef88c23bcd8717e24c6d04	1650112549000000	1650717349000000	1713789349000000	1808397349000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
52	\\x8abc9bd4972119b5d947c21d19ebc811ec7318f4bfdb083f1308fbe0e3cb9ae62813c977d1be338f6354deef006695b3a09831aff5e85c81337c844a2b7132f3	1	0	\\x000000010000000000800003af79a6ffeb58cb32ffc9b4854b6847b7c738c9852f652c966d62f4b0dd49cb89029bdfae4031e9060d163dc89cf7abc84ad769da3ff9d89f97d785b45757724d6b5fd76383ef251897fcb4d55e08e00aedcc8fbfdfc0daf99f1bac483212ee21ad4f0069257be8989e18b495f88460b8d8d59f3544aa347aca65cf50cdce7b7f010001	\\xd452de20634ed3d3a89c358f69b5d686965cb09d449809b4c1d2cab4ba3c0963d663f9002dbc8d07412d4bc5bb4cae3fe02060b56986cf8ae1a6fd78a055890d	1675501549000000	1676106349000000	1739178349000000	1833786349000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
53	\\x8ee40ec49239aac6389374b6f45a806e2c943e70ff8c72e1613380e147a2f74bef807d97372d77c5bc833c1ac17d0fce0394e2d4d6f4b96d6f33a22aca15e32d	1	0	\\x000000010000000000800003d24a7ae3f24f2d16c74cf1f7c2667373def57586f9fee47e960925f937ef1674867811e60fa65f48fdf654be4298cf1dcb801ecc034ddfbf9f6ae3b2415a0ac02b809c7116aab0849a6e69378a4cea6dcd5251f3bda1c386f3f1bde15259d77484a269fc43c0612369f59f739439e99a2f73334bd6fed7d111a38944efbd4d33010001	\\x9ccd3c50e7e5f6f72dde6e3657780f1721946f679040551bac28f56f0e62b8733e297281668864daf4eb59057d0992e773dc708343fa3cbc6998968c1d2fad00	1670665549000000	1671270349000000	1734342349000000	1828950349000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
54	\\x9068ee40b506be47a36afd688859d84a82217232be531aec2bde35258cca44db9bc71847a75a2f05eb288c8822f2cc205b3bf819598b6629718cb5816486853a	1	0	\\x000000010000000000800003c68df545eb7cdfa82021b55cbe7dce4c424a8740eb5d380b91eec217ea2932ad82429415b5e316f4df9e57b947be16c35569bc06c4e50444496a0e737a7b8550ae61a9a2ed84eea4c6e5ed18bcd6f24a983989f3069d9c3f62e611b20a53d974977cf603fa393b4c5f79aa251801d4aabd83ca1ba14351394c38174eaf238659010001	\\x4889a4c26add10714d30bf7e2f1752b80d733dbbb15e7eec19e36de64a97305b87c5af0eb41b546ec963cc85cf638ffb64495290ef2bbd59a598a453f9daad04	1660389049000000	1660993849000000	1724065849000000	1818673849000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
55	\\x98a06f7a6b21c44ded30859837c5a6f8b68f62d4e995569a1370e181b895001599ca51d224fdbab987415e8734852fbab51d8f6a05fbe01674432b053c2f6aa5	1	0	\\x000000010000000000800003a2b85724ccfc89c9326894c52344cd422096c906003dd849480c686d46e16fdcdae4690a767f82c38b3a958c84e1d902b5e8bb8a3709b0e6930ff88c3d0150624d382b63c982b2080a15ced2b80e12d466bd520cb51f381069ff7b64d4f669be84a2d9036519abd33431abb40ffdce71b39e71ce79d834cb7baa4839ed4eaf3d010001	\\x7e500102943fbd5326ec23b200aa3e6acaf11602050c684a9ded3aaddd8cef418ac71d1d9c4befc864f502a9b9dffad871e81aaa9b8b3905de64bf0d51df8d0d	1663411549000000	1664016349000000	1727088349000000	1821696349000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
56	\\x9a90aa2cc50a8801107af511e2ed8782ed20852350f54adaaf6e4d131f5df6a5236c0062a7e7b13929d4bb7b70bdb5ac4c2a9432917bfb7905d699b3331f8eff	1	0	\\x0000000100000000008000039e23bffed3c7d85393e27e00c7ea944ccaa36cd2d690552be3d2f7c9772abe53ca908491b6ce10d4e2d48ba2282c4c293cde0da8805375d12879801875bf035315f27792e50b661b387597562d6229f2d6e362825d46f6e260d71e29f2009b2c53034bdaa6a0624a78d93950c2e5562195f4c41756506e7ca9174efc6900f5b7010001	\\x6e4f3441eab3444a58af899e6eedeb9ceae39bc515d16cc1cb14e888987e9911d3f2649840ba3ac264244c39e516085eda00eb6f7db796366c349264edf0e30a	1651321549000000	1651926349000000	1714998349000000	1809606349000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
57	\\x9a245dce561ddecabe718fc4df643528b8c9acd00ec31d76838edb1dc16e9326f323ae7582a0f3e42d046f93b1a3fac5d79280a2b70aab982456916cbcf778a1	1	0	\\x000000010000000000800003b4a8e3dfd6eeb24aac816a898ed8261aeef92ed1d63c54e9f38cc91309ae95ebe4ba23a69e00da81c26fbd53599b5eb2107c6e0e5024b53875b79f22bc1725518fcc48317d5b8f056fe103b8b1dc6ca12015b02e07eac565e8e4e7e170ce78e6ef51d48a98e4be68a4cd0ef6f63ed761f0d499e27b1ce30bc7b93f3837a2ca0b010001	\\x349160b36deddec11bbcd3a0afab09fc46d1b0ff3c14456aa3c37d6c61d277f83e824a48f2066a53bb896951d048709a49cc190f1810db9b9fe90310fc33650e	1675501549000000	1676106349000000	1739178349000000	1833786349000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
58	\\x9db889bcc6b2bf705953fb1e6d96ed7776b396202b495d1805f8a2578e05dbec2b35f75cc57c95ae35a2f0a024060f27a7029dff95187fc88ac1f95ee1ddebbe	1	0	\\x000000010000000000800003c7b552a3459354c4b3f83d88a67bdbaf40ab9de2fe2515e8f3de10fd39191af99be46acf612a012c6926f8543b55f84285311790ed1ed4f1efe132bce2db9003f7c8323a0a965f19710fb9af98a886854a3a4a5acc8bcaf6afeb5a4a3e675b50e3de430a1f1975307d86ead2c1a7a7e65809e9693b4ea7af0bf1e52172da9553010001	\\x8647bc4d70ff0d9dd70a4f002369750175851c0dcf1a2a01d354f697a2fcde1fa3352a7b5b82501e0b627fc93b4ae7644ce6f51b431786ed70270b102bd7bd03	1669456549000000	1670061349000000	1733133349000000	1827741349000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
59	\\xa158c452efd856ca66a6a57b42442652afd7b41ac3b117f3b7f231d981be6910195ef1376abbadce19a12d21104b2ae8f9e5f62c8c7fc44db6e95ac357ab7e90	1	0	\\x000000010000000000800003db82fb878ec00fefb76c8178c324ac622d760a0b199cb9ed4fdd5f8c210a8d8777f4fe7d1177b91b561885b18b34f71c61942f14a8a922c21f833c8b0979a1b01a8acc37ac8987cf3602922d16ebd8a1346d2578b4bc7ed893f8d2f3b14fc4738b9b187a5ef8372b5be0733f4e1499aafad614e8a0d52f8bb2dcbdd5b556ae9f010001	\\x4d43d8ffa8846a4ff611c914db2c765ed6c03d8949a4da2deeb794be567d04f3eed9a5eae81c768101789361629a2e21a85b5da171c7e300b8bf04fca5a00f05	1667643049000000	1668247849000000	1731319849000000	1825927849000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
60	\\xa1987ef30f641c41e55288025f2bc21255bb5c1fe1f68ef70b70a9a2b769eabe6f7098dadd7aea5499ba14fc7e5fcda17f6806f1aa643ace90646c3e1528afba	1	0	\\x000000010000000000800003e88b37d89f310f834c126b2cfa0ef96653b0c93100ac8b908f1604164f53df2887b64bdcbaa92d8bb5f294b228af36a9896185ac2c7dd63c1098c71d40432520243d10da8aa16cbfc682cfaa8a0fb97151fd76ef7a840369f17367681db983f6d9ae8b593931c91bccb5bbdd9811f035ad56fbfa55319e06f4dcdb36f27b5b7b010001	\\xe6bb3e64b5e207e8d7335e2a9044288505d5261d5288bc448740df66fb6dbc3cd2728b703c408d0aeaeeee3863d89a7307270adc8d8afb48bf42470c0c542509	1650112549000000	1650717349000000	1713789349000000	1808397349000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
61	\\xa2703ec62c55527974952dd160511db39fc3f55e2022b43785c1c6ccbd4a4b355edcb2bb23f1a3a0e90d6e0cc3a06894bbb2860fce976d96dff32da01faa533b	1	0	\\x0000000100000000008000039bf959a01d2257864c4bd52e960c6d997dc56ad711c67ab3473deec9a7771d28eed61c23ea893e30beb2d183daa5130f009669f42e3f1fa86c3a600c249d89ed4380732f539da68db8bcfc6dfab09ed6e63ddaa62e5d73ae098ccac8a392502b92841ea8ac853609e1e0f2194acdb08f6498fd36bc4c812d54d9d40655122c97010001	\\x8dfe148c826548cf06342cd42a08b2798d29c81a593828d58cf8c79f55179dead54629fec9a0b8384b48f5820d9e0df932acd9d9b3c0a8a45873db8715947e0c	1662807049000000	1663411849000000	1726483849000000	1821091849000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
62	\\xaf5073b588ed9ec03eb4930b1b0b17db8651f5f606e6474e24840800b2206ed19ab45ffb1c2753d124c9cbdee35e52884f5c2c6335d6c4e7f01005602e0ee60c	1	0	\\x000000010000000000800003a9a0427eb592976362461b89bd82a7d6436ff7ddaa72e6b5db9efb7fb1c882d7f42fdded27730180452649d8eb3772283fcdf02f9462c3979f6b65fde16c4e6fc533c50cbb975a5aa83815c0eb9b2e449055134b6dbd0beb4db2002ff2f072eedefa6b777b85609e80aa9f93ddeb63eff5112aec00733e0b77cad97d612a79ad010001	\\x5deb30a2cf8c1f7717c131de0526ec5f042d6e6e3bb6b4b1ace29cf9f3878530d770ff7c8b60d07c438b766acc1f8c565980617fe75b8c5be6de25dbb1051501	1647694549000000	1648299349000000	1711371349000000	1805979349000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
63	\\xb3585e24e46b12f0249310455174359753522b937f598ccb40ca5cb71019445b0191ac110f3872bd2900826c674a826ac98941f08bdefb4f389bd2b8189e147c	1	0	\\x000000010000000000800003cb02c78aa38f095b50a11c8c02ffb088a38fea90ecce34f45fa6993dacd1e944ae84df30441b03e3ddc4c15df09f1df4de6f33cce1671592fb0173b6f1801436e06074184f6504f2d769ed64af662be58d6c42b0f67fae49c3b1fad2bd4d8c334f60ff20e851ebb51f5371aa3bb44ed1a06256410d6f6f18bab14137c5a9121f010001	\\xe5c14a6acfe3d4c2cbba88439d1932c5b1169c1a1791280369eda96abb5616bd0eda15f35888f0000b8a01c8ec99019f70182fb2d45e543d3edfcbb846f3ae03	1673688049000000	1674292849000000	1737364849000000	1831972849000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
64	\\xb344321c731cbf55f7338dd53c8605feb6a4a6f3feaf9604f57e78af41dac029ff20e4a98862ce4c597269ebd11e299dc89db34ee58f3bad02b8411211c0ede8	1	0	\\x000000010000000000800003c6a57876bec4c3a08e056d534edcf3edd113f9b092f504f52b184ea33a9f0a836525e0f8646749fd84ebbf12bb88746d0a9f6edfa7986b7732c8ede1641ff3c1b3a1441b5060e5081fdef3348d01546638a249541e24ccb40fa6995b84604c62abcf59b41afbc5de4bd6bf30a12c8b1ab2aae0d887e8e765f64cf79010b80bd3010001	\\x6f8209b56090492aa777e1b7671a1127aeb99140f84e65832b94d904c29f27dad7ce0469ba1120f2dcb2ead44c577dea31a6e0ce728a258832283c08e7312901	1666434049000000	1667038849000000	1730110849000000	1824718849000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
65	\\xb3c43d15d5bd0fb87888037065ec8e97e3c318925664e33ba74e65398ad5d9f25ddbeee6e6e0bdfdf64fc975983399175df4fede5e0f2b9343d52ed9355bc84e	1	0	\\x000000010000000000800003b311160b0f5e1243cf6a187fc3b085a03c817f14ea7acbd2c28c9d47aac740344a817865edecb69ac984541217e5d94dce00dc3ed85210bd3a958c7b1e33a0496746d17b757e149eb32dab4f997e87b61173d806e04284aa39ba7760edc9c1c2b5a75c0b4a0abaf74bc5a7241e100a0db5ebbb9e7b8003cc5bf1e40169261add010001	\\x79a505e5237b43bdd57c19ab1fc3741921627134faf45ccdfd2e68ea331b66c01b5103049d27bf1570807f94de0a990ccbcedc433e1d57168f752e73cc20d201	1670665549000000	1671270349000000	1734342349000000	1828950349000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
66	\\xc078b4e5fb7f983c816183b2ae892ca69c90dfcf245fd84ce093a47240749c06348a7f76546da82cf50c60ae5a4e2a4058d715cff2fd16ca0a65a1f9528be7c3	1	0	\\x000000010000000000800003d389059b78a5331690526a5221fee94ba755be7559e344dbc384a4d843022ea0a27dc3cdbcdbb32aa7932130d1de90a635a359f8e6085ba912eb1dda9b7e85a5148e8e37a01a912bedd3a0c865bcb7834f21abb2feb8db7493fdbbeb203e32ddca9cb31d945f86329a8214187368f2ab4e510ae2a08c787dc0b66f721d518d31010001	\\x546aa87c86e576a11eb6b0274be8b4aa0a6e91142043a0b6cdedeba093486d4549547e532eccb5da80e77926f3cbaa2fdf5be25ebda8871d950106274cda4a00	1671874549000000	1672479349000000	1735551349000000	1830159349000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
67	\\xc0e843b08e6bec6b1c2092f4b002d21debcd9ba0ac4279b9417ee8c31c1752aaf9ff3ae786ef57ea71e599207e7a403b8328a85cbac334e952ac5925bbc74880	1	0	\\x000000010000000000800003ec0d407583aa3403eb0c4c5394eeb06971189a154634b19713bb3bc5bbb3e9efc7f38561793ad5e7bbe5af5b4c41d9e0e11e1f1dab9ffd362afa8550b3048145ce055eadf78f9b1a5d97331524667f76ec598a4189445d7341c7de3ba0d926e27c20bb69c6ad66a68440babd4f2d309e846a988c8b86818004663926cd4fd153010001	\\xe757a0069ce59a28c434beabd8fe96365d61710cd3bd32d7596ab3ab0db9e6f3ffa316e16c0f5b706dafe37614cbe8923c9b7f7f5fe94a9b74eca1eae85ea608	1669456549000000	1670061349000000	1733133349000000	1827741349000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
68	\\xc2105df8667036621a0f9dbe6dde8e584d6806df009d04fa507a2fb9a3eacec24eca25ed0b63761c49e2c6347a06553eb7d333921ae9c6a59d71ace338f84abf	1	0	\\x000000010000000000800003aa5a09fa9d05dd4f71c30cedd6fd430b2d063986c6bd6c458f567127ccacac4021dcd18c37b5697cf650721dddc74752452a21fa14bbf5d69e9707f4f388cb81716e0a398ab2cf4b7322e107a7290bc88fa0a928c97cd66cef5ba59f525a7fd6c65e6143f2e0b8866fad7f22eb4cabdb11fd13b1b9320dd4a384c8d1d8f75ecd010001	\\x84798732c5adca8fe6d4876182f7e377a202bf733fc1b2b98776f07c7d3c2ecb785f07f59451e31388e49dab567319f0f1622f225ce7993c14ee21a3decd9c0d	1656157549000000	1656762349000000	1719834349000000	1814442349000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
69	\\xc3f4298f9486990523173e2a2b9070ac3b4748e80e754d289db8b6d9dcda3ca8a6048927f8f03d611b5d05328b255f1b386006a91d8c57d58fa41bc9365b57b3	1	0	\\x000000010000000000800003dd1c6c393fdd9ce28f901ac650ef83406c091b321becfb2df412566294ef48ab39c329fdffb1a88f4ee44daf9a85ec6dc8316fc2244463d7f39aed25ee4028204c3524904765eb4855c0856a5a69f99c3afba4e890c2af8231db29059e2fdc8cb804a45741355ff825f1ec159b9e8fc8a6423f79f63c35326ddf2691acd98ee9010001	\\xb0d83f95c09341ecc87cb6daf72fe6c4bb6061969c9d862eff3d5f87d9ef942e062e1d7f201b59a32d191bd11cd410ee2aa66fe7b02366a28f34d60a95952009	1662202549000000	1662807349000000	1725879349000000	1820487349000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
70	\\xc3f83a11ee6555870195a6271a6ab05d7a872be3b791f9c1ad5e9a00cc592e5717a8218c58e6f76c52ccbe1f260b16dcc73c750546597302113a790b8b90090b	1	0	\\x000000010000000000800003c33653a425e4aa84aef9859d2d7cec805723c97596dd31fa21feeeb5a753622724f5e7901e02851bca6525067303cb0821d8ed74314e73ff8b2b2c0d3871e31ae9c5cdc9befbdc391a734f81f934de7cccd4f57ff8d2c93e5c1e6121eee2b09c3af350d01de63e1e5590866b1671ea5cdfd1967bbe4329c032ba58031392c5e5010001	\\x57c4ebba39d9cd861d8737fb469e915a9fe370ef51e9428d1e8c92ad13e71a4806fb57e469dbaf4eabb81c693e402dc48d00500af88c3a1f89aa07d25fbe1b0e	1673083549000000	1673688349000000	1736760349000000	1831368349000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
71	\\xc400d82c8eea0d9ac44c16c3be1fbb702abd7ee81539a2a19f182e76f8c389d3448142c57636a42e2b689f5fae41621caa880d6c0133329ad7f3eee5af097f85	1	0	\\x000000010000000000800003f100b9c2f90b7ccf2155401fb257d1742f9742070c5f0e4843b50b240a1683ca0605ed07f118493dd9cacd6c1702397c98ff4af9ee9d6714800f53e4701c7a62592caca4c5bb8732789024cf5e0dfba5391e5f2bb0020a6f58dd34e01dd1ec58107fe21cdf60e721f525ea9a0170d7b55f0a026406e9c50991fdfaf40669ad1f010001	\\x972b0f9569859337bd1f1ca33d987251f4517ef04cff622df279b47f383f7c01d291257f0ad3a0143b849d534d81c3d4d2d448cbb12081e86ab21a4783dbf906	1669456549000000	1670061349000000	1733133349000000	1827741349000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
72	\\xc708f726edb55513fc9ebd7eb67c0ddd299f6f647bd666b46e47b81626294743f516163197fddd3a393d4340b1930661621b265ccbf64ad9283a6c117e63b2f0	1	0	\\x000000010000000000800003b6ad23f1a9a84839c9e161fbe545d621417812d9b7e79b07af5f88648a3700eb75cf8cf7b4d6c044e33a5e7c596dfebbbbc4738a1b9b65cc1ff3213a078f9930af78de11b3dce3a679c3936c7ad7a8c0ae38b45eedddc9a712aa1edecc35c81e1e73e02deeda50b6688aa7bc2ef797dada2a74a6deaf93b0f3940a4f76b5661b010001	\\x5f3d580e744b018f567b51f4c554b4b0ce966a0adbbfdb1e57f845d7122745140197a85c5c64fa7109b1fa680edbf4536ec44d5b6b49972c17367bec29e53305	1649508049000000	1650112849000000	1713184849000000	1807792849000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
73	\\xcae8774a82878a17145796b40fdccc7d371db714c1025c7d145f05d3f92efad498011fde8b4b2026e0f4d81dc6964ed3f4b77f3b4ba804473de648a22a963afb	1	0	\\x000000010000000000800003db83c1f5ad4996a9abb72d541b85abbf8358019bca6b41e2edf9198a84adcbc4a1f8965a3b0ce86ba4656664b4cd480ffd1e5dab5c449656610eb6c0e1660052ee78d0e11835d9664a58b82f590a5193560008237d127a774a8ebf12fb9c16fb387f54e0be67fc7ddf0a152e714e3700bb91a59f9158e3f886bd848332f2ae11010001	\\x439648a1a520a99f8cd5bd678dc63f0c75d2b3214305f24e2704a884597af89d518a11a42d9597e6d4fafa00723158be6ee5fb3291cd58500e3ac8624c3d9501	1652530549000000	1653135349000000	1716207349000000	1810815349000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
74	\\xcbf49c88fc93264b182bab16b52abd35b9ddb2bc3b9a8b66b98ea6c15647b886cebe57525a847647c5748e294fdf83577668bf148ec5dd92055e7798aa1323a1	1	0	\\x0000000100000000008000039b3c737994d756ad85988fb35df143ab7c98e5b8204ced5a1fbab3b743d2a5eae520a0dd5fc4c59b40ce6a8c1e5c86b066c306769ed9173ce6a4b24055e615cafec204a0e34c68b667b9664366e5d9d03920f59606b100b6e67d7672ce7ec3d6f51fad022eaa8fa2336ade770a49f3b61860b1f69ae97abe4165594af385be4b010001	\\x7d3348bc84ee9f72d1d63135d50b6108cf7483255115dcefe121205a1dd682336a171f519fedaad20f332f73234e1b6cefd79fe3dc9eab8f32eb9f9b6a786807	1661598049000000	1662202849000000	1725274849000000	1819882849000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
75	\\xcfe4d9339de76c23437e0515bc0b0bb93be2558794dde35fca60f41a5f807c30e6d5b86ea9c9010e2041f5cdd0df407169cb2786f418770c167ee7095c4f7a97	1	0	\\x000000010000000000800003cecb43d3fd74b51d0f794b6d3dab737bfe26c43948a63c0d47d3474892be2f37221274c63f81918e519cc3cf73b9c4c7864821b864ea3ee21a6e60fc3f6870227020f58516baed94d404e6c102a323d1bcafdfc495fbf282772cee3e4aa9a6de515ed255ac9fcdfe9bc9199740bc75d221e95b050aa05cdef208d5f100481c71010001	\\x93b11a58e8ebe0501e253173a8b9552ea81d3890baebed6d78c11907dfaf4b93e562d240b91b319a1268601b8509739bf4feeb9d625c55b8f533f30b4e5fa90a	1672479049000000	1673083849000000	1736155849000000	1830763849000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
76	\\xd30868da154597503198ef182636d2d6b1ce718fd70760fabccd9a07b51d37d78c751f7e2508ba42b87770d7f95db37acfa1ba4cfce49ee45357a5dadad5d48b	1	0	\\x000000010000000000800003be9efe535350187f1530c89e06ddd2175a65ae95ac7958a21951ce93e62a82e0679bae2b5503ced8df55243c63931803d9b66691747ade9ec64af2b26ce416932a270cee74fe5e1082d257057792c959f3e767c9825830cdf538d9cd0641b587c71551357d190e6e562bc3b3136ba7d495a0ead190f55028d0a6b64ad6883ae7010001	\\x7878d63ab5461e364e8d593751a07ad2d7778f0a535de12c42d06a2d1e7604ec60615c73c199f7705604dbbb37eec9b41a3851ea00e1f28e2dde946abaa64f0e	1668852049000000	1669456849000000	1732528849000000	1827136849000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
77	\\xd4602c626d9851b08a62d019c7553d59fe1764698d81147e675c460ad3c793d02c73e66ac3f5ebc7d52af90a3fe39875b96ccdb9e30c7c1dcb679e6fb612c849	1	0	\\x000000010000000000800003e970347f07fa1d56e540505295c2ecea53926d42fdc5bb1e441e275a2b41c55a55bcd14aa053714e373f3c6511711dfc943d51f97510eca32c762fcde1e9d63318197c447a63a38a9e610218321d0d5c8e411ee102f6bcecec468dcb6f50156fab931294dcbfd680c8110fc4649513cf44b42bd18cd2a4bf27d76d1b419dbbdb010001	\\x92dca14ecef20d91cbc783939e5fc532568b7599cf930b826c518de5aea545767319fd650de05822a4a89b6b0eb7e969e7a151cd017178b39b892a4061bcf70c	1656157549000000	1656762349000000	1719834349000000	1814442349000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
78	\\xd4f4b9a824b8b1785ec491658f725d6dc024199cdf8fc39c4e0f4d248d0633d8895c61de254c9097f2ef283384b4f348d50b740aeaa00373580d6e2f7b3285d2	1	0	\\x000000010000000000800003fa94ae500fa9c95cd67c6c1ee7920d6e717b98b3f931669a830cd0c5dcf5aef5e56ebfae7e620f439ad75115fd7393fe61c294267bc42f936f6b8654bb670066e239f07b1f32baa163e076ea440977d7a79b126f2bd4843f3f216857d83e0ed2769788020cc45df86d64319a9be32c411a20ecca56b2a3a3f9b953f52f4cc789010001	\\x2a781ec5f78e6af63813848edd2df1d22c284387dd508b5b26b83c41796d91a5d05eb78e572704c83c629a5761b5a1338ad1f77fb48f3b217eb8ca9aa20ff108	1662807049000000	1663411849000000	1726483849000000	1821091849000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
79	\\xd7406f6d5d555807fb9ded64eb4f420c058c8e3a5ac9017ae2a2f3b2c56ef27d5108d89a1e214d052f79e1528fdf209673b569c68fcb5bab450549a531ef9075	1	0	\\x000000010000000000800003d8300c27457b4b0424408ad2b593da2753e0c55c08f0a514b846e485e3a4766657eee2f6a65815c3a02e8036e44a050ba7b4ef3c8c6cfb24c2d4923d9b30094040a8fe9ceb559a9d446ec37245a692c6858c08b5c68bdfd24f44e6949347c0df94379312d3c9fdfac91dc5878681dd694b35e3c21cbb7765fadbd3540bd53e89010001	\\x0eb780fe07f3b467c65434579379df6328ca6de674f2a995052d46d47cee038c45a08b3800c7eb515b0cc154d22b03b4c87170cb3a9d828c35b2dc6a83d2bb0e	1677315049000000	1677919849000000	1740991849000000	1835599849000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
80	\\xd8687d0afb8ccd0c03423995a685a9e5821f42bbee8a98a2d7b1cf894b86c40616cdc317083df389c71a0395599907bd7ac2d69a08b3ee3f3d148456ebb86054	1	0	\\x000000010000000000800003cc7879512ad54280484a33fb892d9d9d2ba7a2af3bb8702916619252dcf3bd702328e203a08028e695d951abca14f68c5832e0487eb55d42bbdf2eae2b6ee03d5e4e760c80a2d95bde9b542bee41537170f19fe634ac4bf822ec4644c3f97120da964c9a3b09ec349e978bad9e1a0046ae0e226cb85ab723321b4977dae9c607010001	\\xe1dba295faee6043c6e2765caa04e359431d1467428fe1c1255ce33f4d19fc1f26955c94aac07943cca90573f6f0896f595857da67418c4892a85111c4a58a0d	1656762049000000	1657366849000000	1720438849000000	1815046849000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
81	\\xd9f482abdb66ecb5fa4d059f8b5a8a1f244a79a7cb4aab5bfad888903456aaf3a937930802c5eb4863ff9af8178dbb2d7a085930d29ca7106337d34ec0fc8a1e	1	0	\\x000000010000000000800003bc07395137c69d6dd3539740fdade798c33d5288c74416fed245f312fd63cb98cd0caac984aa0d63b6696ef658cc0b4949ade749816a9a0244e9cc0f5adbc90b930b22cef709b861a5cee99ce73d33479cb537ccb2051662aabacee9580b660258dcc54e744178ee90a84e871594b1e4825d40edee6f6b771d9462da5d5a764d010001	\\xf77112bb0c46847c38fc43fbb477408f50f7479ea7964ed891cf3a158095be1bf7730dd63d9867be21d4a1c88938f84520904ada107a56f22284d0bdc784d709	1673688049000000	1674292849000000	1737364849000000	1831972849000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
82	\\xdbd018be9db7a2fac46d9a5a354080d66d40d1c8e5d798d03d4b793611adefce179d4442216bc99d044ffbeee54cc181414b50bd1d8b870eb01c298afacc01e7	1	0	\\x000000010000000000800003acb4a8f77894ea584a15bf627313ea0338f56636f8201cfb22757aa8903b35ea34bbbbe89de29c1d29b8f0f097cb92cf8e1cbea0f7bef30f94566131df77ef513fc28894b097a681f7f0ed82488546b800b69ab0fba23a730f383fe6fcc027360fc0fbe5078883dba46de805ba7d8e3144f1698d6a21eb5547586f94a2b4789f010001	\\x13b20d43f86f6be6acc18c7b41ed42059d1d6e400c7dd4b7fd5977435a4302e6a68cda48850d406d989d176fd38f3f99af2365fb8cfd9d86762cba97d5159a02	1665225049000000	1665829849000000	1728901849000000	1823509849000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
83	\\xdb4cb3e4a01035d5ccbaecd47a3ff9c46eac5a99c879ae12aeb56e28616a362e7a8f38dd6d695bc4ce43b7661851f1ebac680b0f87a49b5bb052247ab6891a49	1	0	\\x000000010000000000800003b1852c74d9a274ba104d5909375ef2f93786f2572d85b52320574ef9994b415deeb143bc0e8430a7c763bdfec8550bcd7a7b717e40640f067518a42a9c6f50fcc332b2062b2afbb34fb49039501622bc20188f1924856a5908ccefdbb4520b16807b878892b5d8acad16f3d024458613651ff039ea8bb28aabada053e1706abb010001	\\xc1079cd48b0c62b6cf56268e9e8faa4fd54f5a2e87f56d6d80879ab81ebfc409903f217091438113dd917107a55d01e7ae1ca164c987f6e754be8300d19eb609	1671874549000000	1672479349000000	1735551349000000	1830159349000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
84	\\xdcd4b24716587b47d14c256da3f64ddb5cd2b0d7d757f1ed353c9d3a61ee7ef736405e8f10b6516a242d210fb14d70ea388aab45f0a6fdaf7ff001d101488022	1	0	\\x000000010000000000800003ba0d510bf74755e58497f11891c1225ff5ae0e207c8f2573f6dae9bad229688c3c32e796f618ddc863a188f521c64948c2d637a58c2646c007590fbbc4b4fdef1c8a1eb10ff8149230addd1d8e17625546a49d0e56df99908e226ee13621edd1f72cf91e422f43d8e6941339303b8eb979cf371bcd773afa7c7b67bb73decb27010001	\\xb1e46ad83b02ba3351bbecb627f14088340ac1e51df0aa689528e673cdbc4442edb0769a2c1d4553f9b4878e48f8944cfb33a62e30ec810e794cf645a7c81b0d	1667038549000000	1667643349000000	1730715349000000	1825323349000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
85	\\xdd08dbad985baab7e3e616e3001b761b99a86083d4e5bcc813f131dded483bb0009a58ce9be8ece567206273ff4234bbf20b7733482d865724f1f6519bc39396	1	0	\\x000000010000000000800003b9c38d02d56fdff90de7ac8e6bb0f106f5dfa3ad5c9fc503d6a5a25cf2863911103c0b4547c2327b993c6b00875b1ebb496092129d4b410f244301a8ae51df092a5e1e5f425ed6c08a79b3085d46dda7d414467cf5d17268ccc244ee54302619820aff30072dfee7d78dbec92c19f9d41e1aeb97985635182c949eab2c5e7c55010001	\\x196001ef356e22287792f76c74b87ba914f319aea2742064cee3408097dd186ddceaa5d394d08c02878f84035d733c44def0ff776b5a8e74d8bfe4ae3b3a120d	1653739549000000	1654344349000000	1717416349000000	1812024349000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
86	\\xe2e0c7c1a2aa9c7df30b605dd534e64bef8d619a002cb981f950a56f9d0a51818e5ae93e6163eeb99da535986b18e97d0e9ca84a180a6641c019430510443f6e	1	0	\\x000000010000000000800003e2910b9afd33ffc7cc097bde5782d10572c88614a50d50fb2af1907e74c5bcc3a7fb1e343198b384524561196dd6e30d008dc80aae8ef69c346ad03f0954c397b6019d80f44a62ccb955c251757a057c99628b99d371f77f6ec6de72b0692031d80296e10208ffc75580bab404fdde46da3d2319de46400fe3fb0316e5733a4b010001	\\xb3afbe2cbc9a2813ac88b07ebc446b3581c288373d3b3ec953f96aef5e6cfd183c17dbec45305aa15fe06803cc5b272cfeb241ceb88dfc3eef933c21f31e7205	1676710549000000	1677315349000000	1740387349000000	1834995349000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
87	\\xe250c984bcdd2de255e0e0aa9759e9059d81627b564aa38355463b6eeca067c9116a85a006a8e77d84660d9af77cc7afc62139deb45e806375245ed63b849c60	1	0	\\x000000010000000000800003a967e7eff1e070f8bc250de7eb96858e34fb84e1d6cc051e2908a1d6d4feadaf22b2b46cb17552f2d9c5211f4fda5ceb0c8f1df85478da0239cbdeb39b67de7ee2a5b0d4b348eea1ea3eaac7ea579d64f9d9a9a704ad63eaf40d7a7304438331e6d67816aae57bf16c90900f46fff4ed978c88e6f842bd6fc4bcfa45f64fae65010001	\\x584b42353b376a0501cdf999ba16fc9b42ff8d1fc5cb2a51ebf7a79522d4a21a009e840c86b835ff38e624c98e8429ea1146e006c3a5b7beb4e9c5801c991e03	1652530549000000	1653135349000000	1716207349000000	1810815349000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
88	\\xe7304a4d893fcf62302113f3c3f218e05e108773e3a559574ecb25eb4416b263a03c60f754242b61e6f70db412acdd18f488c6df05ae83c15d69f545af5f6e75	1	0	\\x0000000100000000008000039e7a1828643c170a8273f101296951c627549dd6280023effe7c00603425a85b79176d817cddd74fec28af72f7227cf0b104518500ca24e16373b3436a7d7e1c42f3aecd93f78bd7c181aaf96f2639212b47678504c0bc9ab76c35c0a0d8775deb43c67b80bab2ae1225358edc54ad4f1f773d4cc26e8b1889ee2d6025392309010001	\\x5f3fadd206344cc600be50270e3e6e3549b025d8a3251d55f2b3070770d9d533a61a72267adadce775015cd56e255a18fd769de0237ae6a5d43434df27b98604	1668852049000000	1669456849000000	1732528849000000	1827136849000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
89	\\xe9ac73508a42d63b29e041ab456580248b2e416e64c81840002742a5dbe28009a33d6938c08fc0ef3eb6711405ac9c217cf3918456e952f44433db226cafacb5	1	0	\\x000000010000000000800003d88e57edeca66df2d49777aed2cd405162a6c0947a69f32dc6bb23f7074ac76bc88c16de8908a84b71251013b62b55b1617800e3076dabd1a8c676308025e6899743474bee3fbe9df31ff7339c1d0b986954faf5c10dfd1426b15242e188df25cd9daff8d23b2c5273d9b65f4ecc6a91e12a45157ffe94e1f71d1c0785051319010001	\\x3052b8596b5fda4f8d70d469387fe3cb6417e087cbca74cbd726eac8b6dd18080b8a256d78fd7cfc527622a33ce50b7e2e5eb23337f98aa5deebb7b5ddb14d06	1664620549000000	1665225349000000	1728297349000000	1822905349000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
90	\\xead82691992693f822ed1766d7ce793b9ba821dad83ecdd702f1663cf577a42d4d83c80b2c688690286ba156dcc236423d5a083c9d2a494b20e06db92b7e0beb	1	0	\\x000000010000000000800003bce30cdc8af69dfa0dd9cb6f7e8196880b1777de77cf8889103fb1b0ed345a2f184fabc06123691f4d509bab5cee154537bc6548eca294d18ab5b2482baeef598e87874497b5ed55437b6375add302d06ff3ff4b787802c52e62d3628d58c5838696a3f88721d17287f7ef0fe84e434811e04032cf9f63b972913dca66bf123d010001	\\xebc351060bab2e1a2bba87763572720d116600b284f481aae583104cb8eeabbab82efac91cdf9a2bb8422e91bd59894f8fbcb77e5581ac2a17f5504d956b6806	1652530549000000	1653135349000000	1716207349000000	1810815349000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
91	\\xedc8046044004cd965faeefd878e50b5e1f969bd21de9a98f8508da50e75993097751894ddc1277a3ddb20be34a9859c15162dd1790c5a2096831fac241d1598	1	0	\\x000000010000000000800003d195125378f38811a26a7ab69078db82233496cf3fbab43e52667e870fcb7da912b16047c191f0ff62145717ebe9bfd91b826289f110ce8e4f5683076c2d6d73e0349ca54d6b98a11ddfa125da46db85ef2082a4b60a0e810f4bcb9cde01d057f911d0afacc74ae5298a9555de13183c8e48384f95bc9416f352f95b5cd03b3d010001	\\x522dd8238dec3af6f9b3f423d079c6ab3cda523c30b734880ed6e42b17ba961ef373048d5cf95c80610a70ce05dede16ad63e68e3e1bdf335cbb49032692ee02	1668852049000000	1669456849000000	1732528849000000	1827136849000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
92	\\xf350414f702566b73568edaa307573c11c18d0664e963f0cd2e7603fbe0ab8f53c9876e8261a519267b7accd6065eddb6040d985bda4ffdbf62c188d71694777	1	0	\\x000000010000000000800003b93250849151763d06ae0473e7aa452c30489708e6e77350d65a0c95b30b3557065d55c720ea6974020d2be75070e5f164e6cd4cd57a697288d2fc7a1bb3e6b291f4c1ef87cf963e4e716ace19eb399fa0d9465044f2ab04bd7af667e0eb67f34bc722031b90ab925459758bd91466065463857d1233d614c4cfecabbcc3fafd010001	\\xd2e552f4343920e45d1ffe1d47607b3134e5d0ce7772901dba71b3fc0565926e9f2e513fea6dd18655207cfadc6d37c2e080d726cb4af8312bd06b52e96bca04	1650717049000000	1651321849000000	1714393849000000	1809001849000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
93	\\xf438857dbb2f734f6f51f3b1e1eeeaa3161849948b08c0fe2f6b91a7d91828e9eb69991936b2722b024cf097c379eef05f18b185b130f3539be5c5f15c3ef33d	1	0	\\x000000010000000000800003c923437546f9f408d040c0dde0da3f72bfcbae6b8378c07c746aaa1f822e64d9a20265881aead4c518e011ec489747e4c723bd3476b00fd50968d12798612f95b57746ec3fab316849556ac03dd4080e8b041bd717117c8fc4bc1879ea1dfd29a9fa9bac63b0c5d303fafe18316773a677ee41d14e3c2f78ed4e567ea2f41dcf010001	\\x4a4f48e83bb634c0d64e7acf4617c6c11e6feaf9dc966b36376d87cbcc5ce07649c89fbdc722dfd30418e41cc2a21d6c36def35f54278780ed9547e8d8222600	1656157549000000	1656762349000000	1719834349000000	1814442349000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
94	\\xf6149c9e98b996377454490b449132cb5666ef7699d11239b95d14bf2ca05966e34689c34c4daf48eff5c3ef1ae53affd073aebf5b91a48c40fdf6a8a1cae759	1	0	\\x000000010000000000800003ba8f6d64d2400a5e0ab8eda71d801406ce376adafadc6a58483a0a5923028b80ac7f02c19018a193f4ac9206aba98c222349a74e43e18e7e37a6286aba2fe606ec2df20cb0f733c317d28ae9189cd7cd5ef2fd94a76ed33876f0bd21865443c35b340cdfd93ec38d386dcf6a7716798ecf40ef2c3a3864fce389b78124d07053010001	\\x14ff27e162ea3b9677d95763dee05e00d91f4fe974bcb250e49e4ccf74a1710ebb322d30f28180f985105a1d0b79c544e41006cd51addb942055c620ecafff0d	1663411549000000	1664016349000000	1727088349000000	1821696349000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
95	\\xf82c3ccce165f1d06297beb339f7f923bb38ae9ada08b8ef30769b0cd9b9fb0d89d290ce27f8c3c207cde101df28723532eee31a005bfc86cf40e38646df2f7e	1	0	\\x000000010000000000800003d18b5b96451683a04cf41da49db02a72ee15dd4cdb945434d3773e0c0ee6124091daa6b5aeb4be1dc5690b0b05ff5b18c7ea920f64f71583b7ceaaca9d9f78a7f525d6c700bb30daaeb163afa8cbc7c888c146ff41e73e4bb43fac09f91fc6603d7d351f923454a25c9434550e67074ae1755c64a6299dcd4cbd664542e5baa9010001	\\x9b6eb9deabc4c229ac7dea469feaa0e635eafe8b07d90d3611c412c12a1cbc26ffe602a92e62be2342928acc75f823012f3dd1d9c6bb8b5ddc28ea944f976b00	1676106049000000	1676710849000000	1739782849000000	1834390849000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
96	\\xf92092a06ab741d8944848456804f27d8888c161a28c940562c2ae6c90f20b7e0ae6599194e5825946e00921918f188d2118b1e399ac933abf1d07569e430e20	1	0	\\x000000010000000000800003babf2d85fab450a4c26dd0ec34f2a8482375682ee766cb3b2fd449c0a700c0594a117980187bff75da02c12b0607394373696e5963372210310426b23bc54587d0ae90c324a67827c8d0ec1927d4913b0cf29d62076478f4dbc9a24f17807780a2d96376dd5a9decb4818d6ed729ca1c5a5d26631fdca2200c9202408de2553b010001	\\xe9ee05673d42f8098bc1b4d7b1538159df9229fe100db6ec93af12b0602116c0707568fc5f2e45ca7695ef6941014e8c87c48cda7cd000770e996029c33bed0b	1671270049000000	1671874849000000	1734946849000000	1829554849000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
97	\\x021598b158f8375dc1b80c6e8c2ef56a03467eddb15d71106227ff3d1cd677594339338cc0a70185099f489e975de93544ef959ea31f72c62407ea642808fabe	1	0	\\x000000010000000000800003c2083a81bb536867778c61c994e5180ac544cc11c3c89a0fc4f00a8dfa359903c1873b2f7124465e3f2ed9ea93d11385b3cb38d7050eb1ecf483c72027413cad069e6f9efed6cf4b16877c7d02ad2282cd229f710ccf4390df91bf6cea0eb194d505624ee2dcc3d2af752b5175487bf3d6aeb0070ed897ecf60ded6651226b0f010001	\\x139d5c4109acb5497479bc8e24cd6feb215497d52458b7f2202c8f4f083f1eb1f3290d43a1d5d31052ff27aada5af6601f50a4544dbf57c6fc553e44fc1ef803	1670665549000000	1671270349000000	1734342349000000	1828950349000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
98	\\x03751bd96bd2979e49e13f02770d3a44f5b652e09c24d0f5eb2a704b1a78beabb70f3a8b1f13f0b7d9b78aa8d2d4bfc7ff57372480df2c739fca3b61bdfe297b	1	0	\\x000000010000000000800003cbfd9a74e495fc1d93264f7bf4c04c2af859bda38b875f6aac9c20fc2e96427aecf46d69fe6569f8101ae5e6dacdaed77b21645f05025e4a35788ba0b8e818a0025f1d4300ede4fc5ea321fa35882d586b70ac1736b8ef594b0c21e8f47415e866583986825bca621aa1a8467c22ee05442a68d25d7ae66979b48a93648232fd010001	\\x4568e67ae64f13afbc3e6c434e2e2772215d5df94bb92d2ad2c550bdb2038e56c7bade9a1226c12b281ba406c684b7b45383ee62139d3f49af7abbc2d56f3005	1676106049000000	1676710849000000	1739782849000000	1834390849000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
99	\\x03258708eae8156de5208b5a0fd06fdf8178ccd437e156f7d11ee37a97568ba6b0945976b11c51c99f234ab81268063e9b888304959d3abff84dd777f9e383a1	1	0	\\x000000010000000000800003a189e1fab32722c6e541d554fb041997cbb1cf432720434a55a82a60c9e4f0e990d5506fb14e08e2a41f5441d2af80f79a72ee945b861ef7a71e9f67e3d1b249963a00b7c241d5d4414c71d95a2ed56422ef5c62eca933e939e4d576a3f45ba7bb8a70a45f2dce1eb3b8cf45eb70158b8bd8537a31506f2e60d46a0e909e7721010001	\\x28fadc81692020845b7de54b57855b98ec536095915d14e78950e83e88032511515b2a909f8ce7295362e7bf4900fdb9563428876c86339209aad776eefcf90b	1664620549000000	1665225349000000	1728297349000000	1822905349000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
100	\\x060907075d5486a2e508379c6272d0d0a438062cad1e18aefb0c3c20978e77e37364c7d105ef5469d6a01c14e478b1e469c77a45bbd0b509bbddd9b0b517e8b3	1	0	\\x000000010000000000800003b53ad6ef02487893d76a23edfa75bc4369f81656adb7d39c7c356fe99b955c14f2f023731cd5aa358a0a8d3301036d17a3020fb92dc36751ada5ba51e73f008fa4454ac1d4e56bf0b746dd4906dde1645fcf0adaef23a00f6f2abbb11c73b7b70cdfef7b0383ec88f2b6be120cd425011c166f8cec10b904383e8749a69e3efd010001	\\x558a223fc2b7efbc1c26e877e5aa55b0909d1bb4f6ef58f4302200349efca741b302019f457ed7e65fd5306ce80fad570146621b340f688b93537d7c87475f02	1660993549000000	1661598349000000	1724670349000000	1819278349000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
101	\\x0669788247ed40d61552999057f4dc1ee6b75400722ce5d4ee7d4a3ae30f2d53ced60268d6bebe6a49bfa874e4d93776c0fae63ff2829e3de3b215c4bcf21492	1	0	\\x000000010000000000800003ddfce4632301c21aebdeba310980ed51b11914d2dbcd1454fc67cdbbc8d8be8b2a51ed08086e2d9c36e91d88f342e41f5b5a3de7b8c236c1e526657f4b5f8b3619fe491de14c6fd83813b83ce9f0500b77c290a4d910af854f0eff3d88adf84965b354259d25fe52acc23bb3e51166aa7635488379c55ea4d7763dacc8f3a98d010001	\\x2aa8e4c1196a14b5b794f03ebbe30a1c7a51797fd87ecd693ae2fdcf1a0f26a46707a7159748eb1436e1aeb32f35425050d5ff076cf4c53bb482e388538ff205	1658575549000000	1659180349000000	1722252349000000	1816860349000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
102	\\x0f45aec9b14b014b7e204ab3941f65b4eb38fa0b94e6d88f6da083b4ec2c03ad207213f7695465cb8e3c08ec4ebc703a3993eae386b6792278adaede6578c0d0	1	0	\\x000000010000000000800003f7e0ab77afb21df332238820657a00a2921a430a4964d29ad40299cbb12a48db79b91e053467fe96dac20f12ca57e0f2ef9daf087f4b0be89127293c82f7e4f2c0abaf9759fe8e3a215f5c46dde8ee3a9a70d8bc6729ceb6869356f7ca1f7cb65909549032a2540531750da759b74921709cabb9013888315362503f985fcc8f010001	\\x42aa7fa79944faade93b87eabe482d0e880502f90bd7c43b3637bfe83c11aa6349574732af9b51dc7228326c96c30945434483052eee2d6dbdfa8e41c65cbe08	1659180049000000	1659784849000000	1722856849000000	1817464849000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
103	\\x13e1862a705385c7ef87cc3743079de697896f9e6ab7e8ca14d58e097f7504df1ff482fb9527bf369c34d72470e2936b2e556aeec57d396906ff7dc4cdb2069d	1	0	\\x0000000100000000008000039d43eceb1b03599965feabeb2648f54411a5a2e290b7cf7952a99fe1559d18e33e62b30a5e5cb2ab6d14515d4ad1aad2fa13e9035182bd1894bde1da78b8d5c07c3cc061382b293ca947c534e28e2322fcf09832595f42027df32a52d27d8c05cbd758b8de617ac6dba5bd9994549b1cd08cdf76137b9b6f9404cbba9f2ff715010001	\\x0bd5e774133ceaa49a62c61de7c87da1d6eba2f6d9ca2e7b0146eb87f27f51cf44c2202238d968c81a440f68b141b6d3b084c21b8a7b41c8aefccbb4d762310d	1676106049000000	1676710849000000	1739782849000000	1834390849000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
104	\\x13a509ef33f1c7b8361c2cfd25d7ef25d3663931931e375808e30470732e480d0700e401eda6f5c3efc00dff8e560afb9c42b5434e51c9e73b2d87e2a0ade1d0	1	0	\\x000000010000000000800003ce81c871ebce80640c26a0e17c5396ea5b77294987ce295d40c2a54140962355f2bc0c5527b6c3bdc6b62c05cb78475004270642c5ab5338a7b810e4794c4ea794eca36638ebf8fb70d165a2323297bc4fa5195f7f490260770b287449f5696ee21f336b9395c0b61826430fbced0bdb8a64272335fb2f714790ec57f82e9569010001	\\x2ae54d77628b0d8570dd1ddd360402a8b3d0aebaed449306a989d29466d9a6441478c62659d45ba6ca7a3ead985e7aa1feb4674fc47b79281501b569b7bc4b03	1670665549000000	1671270349000000	1734342349000000	1828950349000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
105	\\x13e9f9efa3787a6463ad6a95d1a9df8f4ae77c10ce0ef8cf66cd5d44995b7ab9ada483dc1193dd71df8268568f1f3bed04992337890bb32fe73f8d7ba624802c	1	0	\\x000000010000000000800003bbdff80ff28c9776c5c8a7e0f7859b3f1c234544d0436bfc0968ddf5f4427e961fc0d5d4e14f6612783f83c583e8008db574612712f023b87554b34f8010782a7b470762812f78f06fad3492d0f19597652bd422d2e2fd3277b91c4a0e7a5b2a0a072fdba5c95b2753df56703a235a9ffa076a20bb41f50bf633e3752f1d99d5010001	\\x59c8f26683781214d16634912382241f2919f055628bb356941dfc0b7d253c80d8c6c4181d6c7eb56778820852ca7c11c30972b3c5ed4939670abb284a57d408	1668247549000000	1668852349000000	1731924349000000	1826532349000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
106	\\x15912986bdfe834944a8af5470870656c9507a8cac97d7cdc8596dc1111ebca9ccfaeec22c9fe791861be9bc44c2e2a258c45c691cdc38f3cb2e0b89200f019e	1	0	\\x000000010000000000800003cd55b9bdbcc8e99a9d2593a95a8e40e5f6a7910979cff4e086837ceda92d7aa9413e8222be49173046ff9abf7658de0a03cc2e638c096ffc12ef59bb3d43cbe966888fbba453e702d02007e2fe2fb7172ef3412c0dd261a194a16aca6ea73300d3262324e90a49fb2b3207e41c56b63446dc628575f26c166918ef9d51e9a1db010001	\\x8664e9a05bc988f1cb3aa7aaa355601cec0a5ba32d76be26c34652937c27b8514a5c9c3d276037627da5130dc94aca4e813133d7c4eac2739c1bbb650827610d	1651321549000000	1651926349000000	1714998349000000	1809606349000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
107	\\x155d35499d1de37c08422ef60a3bfc3549eae11b2f3c88f7223429f07c24ec97017c7080dbcae9dcb978f2e4a6cdfc9c6216b832af872f4f7c910366eea0ac02	1	0	\\x000000010000000000800003c117f9b261d6df8303546c387ff0178d60926dacf47926656c3263a39dc46e69d1e2c63c9dd2875234ebdfbf851c6111b0e1f7f7bfeb5f54a287c061567d6b8184588ecd78d1756a7d2ce1503f57d3ba5484281b2baba1cc26ac92bd899b7572afadf837c409fd4fa698d1acd9524f4db3ae60d1381f1c29c5229607510ef171010001	\\x6b1e3aa90f049d3141faa2e16d7c67b5b95b1f7fc217516b7590d3beed146fcd42e35ee0c34eb9b17bb1c8a20b81bc7b3dfa83829bce94bcfb1414fc87cd3503	1654344049000000	1654948849000000	1718020849000000	1812628849000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
108	\\x16ed80b16385cd9c90e9bac8cb2faa9cfbe86570d5e9eb9a6df999331167fa52e9c7fd88ef096ba4520cc54757b5db8c91ae85555aa114bed58170a1702cbbdb	1	0	\\x000000010000000000800003ba0f4edf3ef70eb78edfbacc2ea6edf18af069d7cb294631c5cb373362072f1627b598914ade21574b6b1bcc5e0e977d458f1d61d42054d759e97052c1725653b67e4753670530c08507a9fd17970769a113336844200692fef577c8fbf4b228d85836e5666be0dd7b9aa9a7ee2b394eb859a9d196a6596065f351df0ffbc98b010001	\\xbead43cfd06606ef7ce4d9d9cb72a5c671bad4b54da5befbfb1e4a782dbd85f9c0efe49c16c7a0a3490b280a783b12042b878a64505760e4395fcd313da33e0d	1673083549000000	1673688349000000	1736760349000000	1831368349000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
109	\\x1749a0a0437d6dc8e3d33a4e36110019a024454e2826cf98430055381fcdbe8543b2e1938644fc589f30f0419a5a76ce5eb849b4368955e62a39b9f41309063b	1	0	\\x000000010000000000800003c54f6d25088fce670757283d28c0b5382e2ddbf999df44a9f62778a3df1c430eff30a0871b3840bda2abc079128990b02edd7280f6899100b093be424bf7cfc098bea6b5a35c80c63db103acd204791eb12d030c26cffb3a555811e30fef681c7c5a98d9e1596bbb170d6185e35651537f1672ddcd95de62c845c5bb6bd8901d010001	\\x275b5f4337838035cf1ae0c25b21d641895e95cff590ebec7f6946e85c80105a6ad5c71a3f99b21082cdafb99295959a0ac8c39d64807ed232eef88b0e8a1a0a	1676710549000000	1677315349000000	1740387349000000	1834995349000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
110	\\x1a61ab6cb239dad823182d6a13123fae4e53fd8cf353f97637a7042ac781fb9a3cc5d0ec6b5ef4c0be1bcbd4c92761b19db0056a22cba7be38a4fd0e18f78693	1	0	\\x000000010000000000800003bdd489ae5f97f0e8fe5029bd9c82427aea629f76f6f24ce29b6798ebd5d9cf9fb5b57be0ff8077fa216fe134c0b48fd234ffe7925818cf484527882d777dcaf151cbb514309488d1d61ae54d94d53eb3ac6954e6db3824f58ecc3f4eb192b27a2adbe0b81a3b601f8b32a1527c32e5542aaa14e7adb64d09196ecfade9393395010001	\\xd8bea1bce56f2ea00d1d78e2e04ea50d8f83df65c18281f82c56e626cfe851190b33040c3bbdc888faa753bd0724118d13c0308612649425403793758a545608	1672479049000000	1673083849000000	1736155849000000	1830763849000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
111	\\x1d557237c47beb082946224b7fea6afa532b6bcdb1f03ec02b828b05a71c59f6bda282a5ff1da4e04bebb4d5a840b6009323d294af60a87db4414328e331d156	1	0	\\x000000010000000000800003f34183a05c32fbb4116e5295e3f3411999fafca7e6c366531e8aa442da364adf31edbb9f2471080bccc11bd390b792b9c8e1c0842e2a0ea2338ad905a383f16c775bde7d46a2224fa1360dcbff76d1974d30a936600f1f0f1968a0b94397ac10461bfb2a558dd765aa4aa64ce1b800387b536e6d8ea7026515ad625f2e45720d010001	\\x4f3e405cb0a0f97a373e0de6a28f7846f7ddfb77d990cac70f53cfc333f9958f028f26c15e36b45895e2f79827eb181b8332bc81d23ed39806cbe36bd525e809	1660993549000000	1661598349000000	1724670349000000	1819278349000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
112	\\x1e392af56a090757a1f4fce27fcb257695c980e015ceaa36eaee1bfef978bd6fe3eed873198dc2492b270277e1f66f750d5f6381247cd4f51c0fec9bbdfe2b37	1	0	\\x000000010000000000800003c44b799875d1d1b6d1de4d56894dd7e0d7bde385fd3c5c5108f66185422442e2d2264feb7236ace01d1a523fd768e93dbc2bfcb16b60fd53600363109cf098aa74faec46a3f574d01cef381678e73030a37b82d8f4fb39bd828d584f62bd64b26734cdb0e13c7704f5d52dc4c45001337eb0757ffcffa587708a1f764e69f667010001	\\xb1ffd4a03f5bb1a7315010a9fd48c7c8588df3396b7dd818836ac01c00fae2ccebc14fcfa62513f1717106414def3269f09a8116ee271f499f2335f97e0b020f	1665225049000000	1665829849000000	1728901849000000	1823509849000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
113	\\x2739d9fb37f21e16000ad32f99fc436253a9a14ca45c6e9d2f73c4e71ee7f32feb1810263215e1188904797926eae6299947eb48f1762b31edf69cf808be69ec	1	0	\\x000000010000000000800003ac236e7771123b1bd7f5d9a2209a6d5aa1ae6ec82e01b13d591dbd6f0b714ee0963b31a44d4913bff9c8e0a82cae29204c998282e3521dbdf17142a32cdebfaca84877e65b629b67b468cbc0e3967149bb4b3fc678a8979185d6b609aaa2241f052853688d910f16a5d9351052c9661937238746aaa451630552eb57ae9ace3d010001	\\x63d2f4348222c22d93bbca73062e6a0d43202d988ffc78be4978f3053ce53d4fb8e481413ce74a7e6ac81bd5f7cd2152b16e99242511d63d9a578e794171810b	1667643049000000	1668247849000000	1731319849000000	1825927849000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
114	\\x2bc1ea52e95ee5804105982dd753b09785608421587d7ba2e6b2681f08e7d87cab672885d33113d2de8b7f4d9b538a224ad87e785864687f51d1cb89f550a080	1	0	\\x000000010000000000800003ad16360e621307b3161cfd30b5c55d5591f6c8265b84aa901193eb988c8c3bd95bdbb6995111f42e360fcb7c3b62949618a9a689de8951d0b1d74107501b36bb14f3dfd3e22edaf8ead9d71bc4fab1ebd734174c8c7ab2084b46cd0c0a649759d6558c7b4b869927d50c30fdc6682df7652dcb454f5cbc79c44f59c38e989add010001	\\xe7546b44e66af926cc6b7fb34ec1b24e0fe707f4537c7c80df34f405d9967dd10b8f37e81ad2510286747b50b5e3d26f874fa139049a454bdf786b4bf4d4ff01	1679128549000000	1679733349000000	1742805349000000	1837413349000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
115	\\x2cd5d81c5f0cb6026e926f5af5eef4b113090f374e56ed68e6ab7a562c103596b86c3862140b3ed07d6eb3201de264f72c3f75f00e62821fd973b0527f8846ce	1	0	\\x000000010000000000800003b44f626f0777600ab1bd24be6a89cbfb4fadf7d0c971e8ac311f94a58f68bd344c27030756009c9620a38b78f4495a525a01561867d82872a424223200cc8640313d4fc61a7879c4a734eedd46b5691767405c470b5aeb4ec77ef9c201d448b39407ce16b4d15fb8220b3e4abbb64e488fea21d71f9115308c5471af44af7ab9010001	\\x2a710085202a960716211692b412de30d74baaca9b5ffa591d7914529965b7527c252849c10fd9b1674fb866b0f574a19fcab6e56b6b70cd64063a2f1a0f2307	1660993549000000	1661598349000000	1724670349000000	1819278349000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
116	\\x2c89a93418557b1a267a822ca83503e4f009745c0fa6e02e1b5f483dd0a85dcffaf7fa340723f423394d24cef07c427785d4e786f755af43be7b19f4ff390e12	1	0	\\x000000010000000000800003d236a76935cb3f5a236ff35df8024ced985957c60b35286503e2e5cba47c213c2e4eb24ea789d245bbcccfe231fa267e8310d4afd37b2bf29a0c2427e6e842b79d4a46ced2fe3c9dd5c6bae94835a1014abcdc823d28d6bc391b4aecb182d6e0b3168d6f863ebaa20860e8f21ac0a40c59be3ec2bb328b610aff148f9d236bf7010001	\\x4bab643866c9b8a74f5092dc2a202d64b295aa73a6b6dd4f87e8d39754f27dc3a0f3fedc7279bd2952e69f589d04dc053c6a84a5f55418acfbc8772f08a1fa04	1662202549000000	1662807349000000	1725879349000000	1820487349000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
117	\\x2d599b48598430ea25ed7a08338adf96b0869136b89c62e1e7dbb83fcba8a3cf460b43a175bf5d5a58d39232509ddb45791a6bd60d189d189ed758559aab5453	1	0	\\x000000010000000000800003aad1eae0caa323fd9c5f2b76c857fcba7d565e18479817ac40b329d8f456451726635fd300d220f79e1dd2f950c0cb2fcfa31155bb589d9114273d08b5db6c5ca742b3901e629b0fa86ff05c11361a44cf7d4277dd3b9770f7c46e22b3d2de92c68cffe7b8090be587ea185b3b6687ff32a33871105716af0fb4cfe3ae356771010001	\\x88624ea56e54118420a1cd6ec87332fbe390ab73332ae5115fcf005bd3ee6ba4aeeccef294ce8e58ff0b6fdd8a115b9e2433b89d0248b92e1b16e7ffa0957908	1668247549000000	1668852349000000	1731924349000000	1826532349000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
118	\\x30ad93e98d1a09ecec42019707068b6dfc8a590fa75ca3a94a8522312767ac1bc4c68ae53d177a03b076698fd3cf091645195d7a2b3e97c9bdd830eccf9e12f6	1	0	\\x000000010000000000800003d61a126eb455f104281d46113665175447c525dfea3ec483ed1b92d65b494ce4f69d88b29eff5469019a91f7b666c7c3a5ea6ea8fb56138cc768d414fa2019619445a85fe2f0f0ecd5d958c7c2e843e581c1538817d9a76981b8ec1e1d91f114a795a1474788f788dd77780b49296d48eeecd83d8755bc266f7518e8a7ca7891010001	\\xa719247ed8cc38c0fb34de61e4572dcf67b9829823956755645473ba794fca6c87ee857f7b4a6c298173836807756905d3ec2e25f708530597f2f8de33d25b0f	1663411549000000	1664016349000000	1727088349000000	1821696349000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
119	\\x36f14fbbde208fbee71b4e97ecdae5a77df679fe658ebea57c8ecf2d79d2b2b246138f15d7c6d72dc1de7708dccc16453a0535c2f3343190ab110dab991208a7	1	0	\\x000000010000000000800003b5ec41c198dcecde7a00aa2bca7d161589ceb8964a62f9760ad5a4ae50be97958611ac4a3898dc9c7dc46bd7352dac263758b969929d7e2439f7e3ca75bd34fbc8701b46a1a4fade89c1c824fadd6905a08713f1520ca00bdd633653938656590bc9847275390a666aad52add806496587672996cae841a4d43c0d3f06c5d5a9010001	\\x80d77fb96aee518c3b4cd2ed8366e2639d1a9799ba73a9c42e68a21938c2b35ba394bf7e1ac67e1575540c617a568be1e48123df344b93e0306d6d702b174b08	1676710549000000	1677315349000000	1740387349000000	1834995349000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
120	\\x3b9d4a094e61b9f98072508b7802edab5dfc57fa2416ac434eb43e14b66a8f69cb84d369f8eeb825d5235265c486fd4c651a12e61dbd45799f9becbb504fe862	1	0	\\x000000010000000000800003b511e262662e6b9ee4d9f79886dbb0dc1077e64f07665c8f8f988bf311a309b52a1ced6e6512fc6de9c3010c837b5759c0753ea9938add830e89f811f121da927f26b4380557b1698d57c8a62f01bf21e9e21b5bed86ee3a6ad580da15cff12c2e4e8514053e7af91a8b471e455d9c8c3bfefd9fb987c0265e2f45619c8f8a8d010001	\\x672e3a1a1518ba370776c9a8a7cb21044249916900a38f931c0feeab1cc45a29438efb9c01d1fc51a497f93b4da798a24b237f4356e17e0e3392d3fdddbb310e	1648903549000000	1649508349000000	1712580349000000	1807188349000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
121	\\x3bcdc05690075eccacbdc668c46b16364540e3489643b892562fbdd2c0b227d973bcee9182a3a341b96fd60bd527c213346239c1ede5982e6bf730f6c9c0769c	1	0	\\x000000010000000000800003aa2ba3a44dc8edba2c80f0a0697b7eb3cad5479a51877eb0d05d6a0048c7b070e17f8c16d7c2f7f83b683feab41b7ee21d1e2179cb9a618b9f659b7d61b525c6afceb9b2802e2ad7c4583a08f4600f77b30ec2526060cf2a3734972fd5446ae5819a7cfffa67a196c3d66ba561051e60f0e5205abd5deadd559115541d0e4f6f010001	\\xd24efaacbc50333e76204793ad3928c0d5ba2d2eab22bd57638ca377e5b7651d0d3281a1af91465938cdd6eb5d33ac2c159a0b96c6d0c95b7289af55d9eb0e09	1650112549000000	1650717349000000	1713789349000000	1808397349000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
122	\\x3fb18845160bb27a7b59b54b0b685d05c738dbb2151115686d1c92c7f5d244d8a1171d295e8403ed82cb6ec7693200309d5a0f697eebbd196b2a6101933527b5	1	0	\\x000000010000000000800003c0f6a19c77598e1b6f0668aabd88e41b7e2d1c1fefee1944f8b1caf2a10cbc784b02e8ecdd633e289db8a8860c12d429242b8daaa36a9164a5923faf511a0a8c28882d69f17bf95b3e1ad6f47388b341ec29803411954ae8afd96761f70f45a06eaa716d0d5893866bfd39e0265e1615c3461f45195926013f73250635e04df9010001	\\xb2b34837f9f69ec19e1a4a81f4427d8048924e5bebba6eee7f00894ac3d305f95690c58f8c22bacc90b1776bf5fe510388b2ba644c6a4861a0a60fc8682cdc06	1671874549000000	1672479349000000	1735551349000000	1830159349000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
123	\\x3f9d2456b14860f95d4fdcfc973677b91c4dd0bdf65e42123a732f5364200b9f380cb591fbb00d93a611fdf54cef345d67d6fc195002dc08c94275575136c849	1	0	\\x000000010000000000800003974b92a79e06de0c5fadaa08bea583059ca8cba689f6a84f9c23c80f673701d2574be8c83a718d1e3fa7df25ea356d5ba8db74bd225b3ca73b37d5d1f53dd381a924656724c630e26d51c5730c7a9c15ae570b686ceea5432a47b2d32989ee10f166856562e1c7ffdf45163af6bfb97b1ad69db78f8d19fa946784747287d39b010001	\\x40b244e3f7321dfe4a21b10d09c99943555b935b38ddf5cf7a4ec45c260e190029627caae87533f84df57a971e48b1b46dc24ffb7ed6b67bc3c25b8c4249df02	1653135049000000	1653739849000000	1716811849000000	1811419849000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
124	\\x405d79b11396bf82ef802f2363f3858e744c73a744bb469ebcb694b2ab0084093842b331a95a6512c82064904e115d2f146c0605e9f1693d08ab91fdb29131f5	1	0	\\x000000010000000000800003bb5364a23052ca1b1dd9b113d902313c5cc004e54f211806ac49c8860e067978895b43962fc40ed8b81488246991036f60af37febf1cb770f871dac83bc0204bbc635782bd6a8c44e9d137755fd2abde3ad70f214fec8a9d8121740fc404c1582039c70a0d63de051dc4a83323af03e20c0b495afb96cd32fc7aa80a60c9fff3010001	\\x3f8a4ad789ecbcf0f567801143579f3735c72f833059fb2b80fcd1f07728a953d2d3a847aceb581f25cc1c66d5fd57f7815b64415c05d90ed247a7267821b602	1658575549000000	1659180349000000	1722252349000000	1816860349000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
125	\\x433d27bd7e23107e1e445f34efb1771df0a03cc9a52266def82b1b91c21809b2b4299fe78fbcbfd045c731d23e176888845bfd926f58948cea874175af75ec0b	1	0	\\x000000010000000000800003abfb5935d76c81dcdd4b07c246ac3012e7bc65359466d84f201a3a713124df866f125b20de69afd2cf018922de2c5ba5ee7ff2bbff686698ecf66219f487afe7eff574aecd8a13f67e05a896900a4f680a99e8e1b28e8376a109e166640d50e00c6a8486753c7bc874cf1a8406853d0439cdb18dd54bed71fc4cb9aaf03ca6e1010001	\\x3253d39deb0af5a843d03bd097448d9cc5d6578b66c24525c3413f9530335610d1b0be83ed6fb1d65460cdfebe0f7076b19d4c66e8f7d841c133fd9ac4cd120f	1663411549000000	1664016349000000	1727088349000000	1821696349000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
126	\\x4539b7833c340df39d8b38c393a965810ea2cf1296416d1bc3f6b5ffa8aa6983ce25de3141f45cabc710ecf07ea3db6dcc5c02247ab91aa6ace95f7c2a856847	1	0	\\x0000000100000000008000039d676581931b282e8c6c553c13cdff22e2de00aa7e19edf57a5e493169adafbbef7534f21595a0d27ca04690b4ebe100bccca04b2c3a18f6d319cc1ff5af641ca6e0fcfd0f07a8134a0ca3e025679d75432134d57d8d5a356759553877721182eea5343edc42155e4921845d0e954217a2543a0cc1a1108ea2c8ba69dc67aaff010001	\\x914871612f5e7d7ea73e0bed210d43b8ca88b92466ba6076488f7b41778f2302b4a68cf3b376a520d880ad7e615b0fba0a9e6fb95cf2e58cab970b0e06862705	1673688049000000	1674292849000000	1737364849000000	1831972849000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
127	\\x451d1a605008ec8f9f890cd7fc8b4d472dea34e9bc58170b139cdd38840bab8c6629ac39d86d64d20bb9011570a93eab23fa11fb1371f2cc638ced9055e4b332	1	0	\\x0000000100000000008000039e33d34785f2e4cf709597211b3bd1dba6a886d56dae3b9d9a245d7edf3bd0cca48c489d6b77e4f1b0b695f79309606fd3ba0bef9319694db179958e46e411e09873e3ab0486b019e9e5a1797f89e9c476c2ec125c94d17fc8b55c67d289b41aee523541745f2c52ac6ca5b74c02afcabbfc393dd84699182f5b544d5df0a4a3010001	\\x6ba99a1dbba9cac64846902b5b69cb8fdb9f9304aa4e3c7837aad143143da5e25d5636826b908711f264a980016479106aad6e8bb42380669da214bda1984d03	1651321549000000	1651926349000000	1714998349000000	1809606349000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
128	\\x45fd459b05834b6f30957f2220ac962a7d9c512a606f68324e8f300f5cc9830ad74a02128850a70344fa0fbb0760ceedc9449cf28caecd7c3fd8575e3a623d97	1	0	\\x0000000100000000008000039af9dda65020b6b6fd017b571b027958f5778c7e2ec39d5c9663bcaf735659bacddab5cc0436d317b1fec78c4ac473e36a94e8dafc0a35129ac18539e8550c226ef831edbb8ad0c615cc7e0bf648053a2cd8e75587024071e9e14a5e45e15d0939cce6b70fc49dd13d9593793a4c598bb1e54beab1b0a61dcde7f822bd7656f9010001	\\x47d80f85b11ce9c2b2190e52e1069d2da6355e3641726986ae0ad2d857a27d418dbb7450af65e08b4d73b7926d3475ce233e68169df0d3ff9bb4d25ccdd39105	1657366549000000	1657971349000000	1721043349000000	1815651349000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
129	\\x46a9688471ed363b55d19d1e13b52801913c4e6fef408995d63787a785dbdeff180fdcad9f1a0530e896c709e180634cf8260504c2a4e5e61808d596a7241a22	1	0	\\x000000010000000000800003acb3a2bfc856d0348c73bcc4966e2dda4013a0d87e7e739d1563b99be8c6292310034d47fd7d08bdc5a30c8ecbd8f14b2ff9b52e4f9d36d64f0051730c3433a7efd80caf571577a82b98feb4031d701433157a7376e444d933e773bc5f2f1016e7d1fc5e91001e7d602bde177509fff8042ebf19aeb42cfff2733f1ab9ae27d1010001	\\xc052864da60e04d092a8975ae3e123bdec994a2db1b63362bd4be1c3f3e746d852a4fc1322e69d47b7215d01b721b44e88be111d89ee9900fb4edb8f8dd33904	1653739549000000	1654344349000000	1717416349000000	1812024349000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
130	\\x48a99db0ebeee8bed6572da17e8ed02c5b95a6db653035b94f2540d1dde4d6422b96d9d8a2c384aba474ba6841758173e8db99eb01a02fd6f272224ebdf0d44c	1	0	\\x000000010000000000800003c2e6e1d4b38f8d712138f16061960659ac4fc3e00f9c0cd9b149511ee7b705da5307e519627351c6d02ebecaf4abacb223e9fa2de04bbd37d80f3bae90df5fb879d4d2d5126ec86e1716beacf181fb6e1061bd47dbe3aab0e62b0e6d0e676325593acac573bb207e7e332537ab529ef1111ee94d4827d3b9800310acd9532373010001	\\x6e4f9103fae33dd37e75e88af306c07dcee514e8bfbaedda50bc849d2731cc5759688860bae920906156e531fed23a3775ca9d53f255e7148bb9f5d88c6fbb0c	1648903549000000	1649508349000000	1712580349000000	1807188349000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
131	\\x49dd292a108b82f4b6d4c6b4ab2764791f53d508f9293b0e02322541cf1ab4f48023c73c158692ec30ea53a569b9840958e69e008e86c1d1560c62ce0fda8c87	1	0	\\x000000010000000000800003e0a64505a4b0dd5117dedab6f0c8b6235e13e59420abc20000a4ca5c2c73683c44338f446e4c8b250b973e8e3d9df6d7fcb69d0d4eea888be4d29f481d699b2a6686504328863383312b93367d9fdf220ee271e0e9987ab93667dcacc5b5678e8120a0e82ab4e9657e82bdb12fc5165e89c7051f6245904be81f7542baabc559010001	\\xb543e2902289b7e861358b3043370150717402426defcbb55ec4b6e07e281aeb6f5dc008ad821aa337fd558aabb1a0cd9960d5fe51ea7f9de3aa29dd7225d802	1670061049000000	1670665849000000	1733737849000000	1828345849000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
132	\\x4aa9a22d315ed4391b84ea939781e0210f51c2e2d11f194ce0258946353d30e3f295d0ac0e572ea443e5e8937e3d103beab3455aad2e8e10a8adb363a93e6c4d	1	0	\\x000000010000000000800003d617ff030bcc138460476dd5b5deddf37758b8022f1897c6d5291648d8705843fa6a61a2718d341944174772255ae3429205be40e47db7f38fba7eb3bfe94ced04cbfb5d75d1490866442baa1ca832436a5bc6655ebff2b9afad2c43d53fb09082c4e03346b22cdc1d9e621fced605ab3eeb3790dc3b9f3e7463381d1c051a63010001	\\x8a7573661eb9c23f99613b269ad901cf379557b5fd29f9529c7c27b3d07dd8e53631c8d292cf6fce314431a0eb5e2e5ab818d57ad3519c7f7ffdacdc0143d20e	1654948549000000	1655553349000000	1718625349000000	1813233349000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
133	\\x4c7d0cddcf8402ec0e03a61b235d064b29a02220e9e2fc51060b1d5f8bd7025c176732bde1fe9e0b42be456be15b45f9f9036c8fb2e2b3978de28b2a6505d895	1	0	\\x000000010000000000800003d4a1d3e0998f1b1820a10e64389974bf6c8dd0aeb521211a7fea3d863ff7adf341f5eb54b9cfe3d270f0089c6e1188a4195319d8f7a73ac85b9715e8261696f5e718f0f44c0ea52de4d9c809783329fe1ca37bb3ea92f755ee5ab7986e0772456de50faeb34179c836ef2aca4d18447c3daceb523a967bf27bd305522df1a815010001	\\x19a35fee8a2ab9d526d45aa677e84ce554ec3e8cd3e0525d769a6c59225d10397127a8aa1ddc8374bf0416a68fb4391d375537598c131cfd7de85b4971ca6501	1671874549000000	1672479349000000	1735551349000000	1830159349000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
134	\\x5289e45cbad32387630fc8dac03c5aea87520ed22fd6e5e84aa399d874c323754362367d24cd7719b1ca255bca61a0f254f7b8336c4b8f15e1e5ac56c8925a6b	1	0	\\x000000010000000000800003ed59a2eafb6477649e3567e135c947e255619bcbc8da7a022f9a7078b13311d8b72710169ce12cfaab0b3e75cc244ae15687bc242ed8f8d69d89171b5db8a21aa874b3f38d842d057a9d5230656d8ed9fc0c61c1db35836cf3da83ca1278861ec1153eeb16a1ebfdf4de32b37ff599000ddb78f0cb69cf2c125df3472e5e439d010001	\\xf9dad47d43c56825dde2648ec44a214ce3870bc9bfd54578c925b3f70d3bc329e57f3091616acf19522656bdb395d5dd66dd162951f2343e6c28731405040506	1662202549000000	1662807349000000	1725879349000000	1820487349000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
135	\\x5291237eaa7bb0509a08682f1ca7556817cfa984edccfc7a736bf68d14a42062a7be5f6cca206ceebb57e9f0169bb3b92e62d4677f0209f197535dd3ff496358	1	0	\\x000000010000000000800003a8f0606b19da3ae3c14afb23123456ef3803242ce43cbd3a259469160d398afc9152d3a256f7b34232922d0d18340e9c09324ebafe3b2ee2b7267dc0a9f3226bb73d56b8cceb32a510186f77a75d0114ca91329aaa503e4869f44dca9372f7de1ae1b8c08568c1fba189f9e3a5bf879bb3b5b4227d759cbd0cfc3742918dfa83010001	\\x2deafdc43a875edecb12ea72e2b887de51f18da8e14cdf8162222889ae0334b3b69c3546ae0d4ae9d484bd26be6e0e1f09d99e834088890fadd0540ac7d0fd07	1668852049000000	1669456849000000	1732528849000000	1827136849000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
136	\\x55493efa713441f39911f5a56d5b53342e3bcac209619a64135e5525e65697b2fa3b85cfdf06291e0dda20cb3358dc679ef46b887891a8fcc6e6c8bf132bf01f	1	0	\\x000000010000000000800003a7c92d2cdef3a63a726030c7bc1fc05255ae6ce8541993979cfc47daace0ddf88fb01995774bf22f772b9ff25ba26e3989276032179c43d6cc89e4b2449bbb22498e9f359f910ea88dac84778761adf368cbc433af96898204a5764c4e6e8040467423d6200ceb02525e2887fb09d9573093be644cf21a7943ac2f5bacff2f1b010001	\\x954cc83f2a3cb6fac654403da77a015bd3fffd8448fdeb111c21626197658b0ad711c660c3c0e3ec42855f85338b4c204f680f1421a8fdbf0cfcaa51b779ca0d	1656762049000000	1657366849000000	1720438849000000	1815046849000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
137	\\x5d25d293e44a29137eb97ecbed16cd3eccec78641e5a9eab3abae34f6069eb8f3b5cac175f2a5070008c2e7452f1204fb84e24f9e1f206f9183561cf74fd1270	1	0	\\x000000010000000000800003d52aac2be5ae97aba5a2c1a67d29cd1b76d3ebcd6bc9c1439659f8caabbe4120a8c131de9bb0a52f28eac32a522c7087b0a4b638002e09e140c495527230f5e9b3fa1322e935e1a61e9c586dbe04318d3ecea64dfae602bc7b482435eda2cba48b6a288e15d5daa34b10ab1ceab26d187e3cc09c9f7dbfc752bfc44216d26d9d010001	\\x9abf79a5b0f19259a068cf0b2a9268c1f80e953a64eba51f4a25dcccc6603be99d9d3ecca4fd75d3b1f3f074060e53a4ef49f546450d244ce9056a811c45ff05	1670061049000000	1670665849000000	1733737849000000	1828345849000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
138	\\x5dd104ce50b5a1cad1ab1e094c8810f38c3736133fd894ed8260c6508bb13457bd8f73d70c9dd5eeea88533f051fe0658b2a986731305964b67a244a6030f16f	1	0	\\x000000010000000000800003dfa9c01209d9492fd98efc79681af726daad88847259ac989539c98c7d75cddbc49d09dfe799188209dd0a89729e8ac6358d5b5bce145e66083eb06911cfb46dd2a872c62ae93a8677b1cd9c2c3569748a1993a799720a21a9cab095eb6c37d3461893e822c4dacfca40a6432ddbad25a70e158ad2fa1e7eec37c186a27a6157010001	\\x6ab2b1a1db175204958f80c51a9a36e2b2a481d8ac9db7b449eb308a1cfe4f9242455b3ad0ea67cbfbbfe60779513af58b9c482650f5394762f1c4671c652b04	1648299049000000	1648903849000000	1711975849000000	1806583849000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
139	\\x5de5c52e14d2ada5aea9a6b7936cbd78c2639c6473556acc1be5fd3af92279bf960f49d7be373c8858ab53cc5a7249c79748b0df732eb362dfe71ff66c6095e5	1	0	\\x000000010000000000800003c847bd2650843c2f5f4a1cf75a32f01383b3b9d2b5cdf100073c92dd4318e9dcac3dd3e6d3a15df6f85b89acca3206594fd62a60fc65e44d3e9bd563941de3d1afddadcb39a7a89051f9d98595e54107af7e31c70da108b1ab6c60d635741f4086a62e0707d7c30b46b93260e258f0e775a6ae13a949ff935f74d5ba710968cb010001	\\x86d6f6938b7632676dc979586383879f79f830555f40b30a22328f541ef6969029478c4a0debf7e97dee2d4ab126ad65c8cd2a5f0099e3d04efa8a507c5d0a07	1673083549000000	1673688349000000	1736760349000000	1831368349000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
140	\\x60694c3b5548cfa49a403c8be05bb5445b0dee6f99e2cd78704f999cfd2b9f92bed67136c11b61a3510e16997a565c76d3f1f526ec31fd2529ef50a7b6851366	1	0	\\x000000010000000000800003bd962088d6170cb4a4b0dcf4e0826525b00beee74076a7ad119d9766b8d626b8fd07f0186cce5228722a0fa10daa4f64a0a7892e6d05ea1dc68ae7ee382a81bc1413ad9464baf89ffb3141f24d05809c336b6453b1a736dc1bfc254b56736803f7c7f8544724000b0190e66288536bc6d725c187760fb05cf0f05a1e41a032f7010001	\\xb9f57a2ccdb4c8cd0ff7f5a52a8d2806393635c000eba459f98447066fab002a70e2e193c6aaf89692b9269e7b539d1cf9b6f921638c3b2da39e9f78f831460c	1657971049000000	1658575849000000	1721647849000000	1816255849000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
141	\\x626df614d981bb554336007a2ea79ac3b41731f6efbf3ceb4a848aebad6b2cb6668bbabb229eca3dd8758c1b310a435582371e7df86cad4769a2bfa31a7cf087	1	0	\\x000000010000000000800003d28cc01712af73c298ef7b9cdd16d76bc04af56646dd48363816d98fcc065f2a6b89de1c0ee69396f340939e57ed55c45f7a9b26dc5b03b30e550b1097614e03222768465051776cfe0f446ff710cb251f1038a7778028243af159aed7e20cdaf41e6d82469cc0d46a023698ac9b2ce18619f6ecbf95c316d73ddfffc21416b1010001	\\x0d1aebe72b54e52ede293bcc8da4eca5e496da55463b30ae3f0162e80fdf1549e6cdb3f26a56624cc143c977f08eb77fceeea633480ac1c09dda3a8a070c700f	1673688049000000	1674292849000000	1737364849000000	1831972849000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
142	\\x62b1341d89924e4f5d1fd4def688ed47443e268fea9c6fdfdaffb0a710fccbd49492629749c4081e2109efcdcf91c31c08851ed52709b15a4b5b581362e81b35	1	0	\\x000000010000000000800003ac0bcf81075451cd541aa7f734486509740f59474c5264540746ce94f6872764a52000ea0dd4ac71db478c0d02cbd02dbcd74bfc137b09b32b6a8aafdff3139317e812c781a538993b2736d0f632a2a77bb91d0249fffe726cf7afd4bfd652b24d58163ae53c11b12ae98648de0ae83dca841ca363a4940c1da81d95a65e4bc1010001	\\x70bd97ecb60f645c8cd76485d0f7da941865b66d61b66a7b067522de4e4431e5fce9b14ef061bd732edbbd71330ea40a410af040ddd897f4808c4cd8ebec7b0a	1648903549000000	1649508349000000	1712580349000000	1807188349000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
143	\\x66d5301a40c6ac96de41ef66ce8e315fad7b93d7070918d62f57d93c7c127e7db1cbee8a0a24a8a3025510d196fae47690546017391c0c6299cdc7138529e999	1	0	\\x0000000100000000008000039e2ebf838761aa5582e25a1c023c57e154dd779f8f9008acb038462d92dfffb364f1965f849702b44eb11f52dd1ad18d6fe313b047b64dd1f73b14bf1ea02aa6d3efcb805c2b92b44d91ca94c83baa48ca5252a77b353b581e49d48186380efdc08019ba8a2c57ac191dde1a06d2332e37a7d7428a6cd1c01ebd192788164409010001	\\x3488793a2e35e55bd5f9ab57662a021d1beb48f9b665498ee5e4d6e92b8467e7643a345bec3ef95e9b11d238e209d83638c677ac2fff258b53dc9c39cdc12a07	1679128549000000	1679733349000000	1742805349000000	1837413349000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
144	\\x6f51ff942863115317d08ec694fc3ca14c54af0cf5b9c79068108b9fd18371f237547f89964ea4e8730730293ff4c43e4247b86c9368093a0e3b0610147180a0	1	0	\\x000000010000000000800003cb2ca9be282761e96bde908db8e321571a17f13af86b16dca2b16cbe6d4d329f09dca75f22a5444325fb0d1d58b838a69547d6e148cbfc76050b05d2301cc25494ae3739177a16fc459ed0874f2a2bbeed4b26b499b36f336832a5ad27d51b1bf4050106af9afc3fcc1593a53dd37b9196c337f5d5d0da587e7f048b0c93bf7f010001	\\x136370578121276e8c6a3d5cb5ce786f7d36e98fd6280660474f4d2d3691404c5b9283a0d0f60948ab87f3979ee6e801117d6a06590b4ffb9ddb46f8d539e300	1678524049000000	1679128849000000	1742200849000000	1836808849000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
145	\\x6f397e1cdfbce397590b644a07a337b4e52f02ed17afffe41305c5f38b7d52704a034eedb4a0a5df7f106368b41630861a24f30b3f9c2b6946c456395d0bf317	1	0	\\x000000010000000000800003db56cc36273e7caad7ebf69138af2052a82ec5dd0279274e61eb7526889c04deccac21f284ced5256afae47b9529082d5056ae35cbf85f190523a39db9d5ea7e4df6a2542b67160b7747f6c79c9f45d2e71865b31991e7f3b52b4f6683dfc336b48becc8abd50b3becf62e02b2106c50e368d759f8fd3fd0b0fcddfd3550c277010001	\\x430c515ce44dfe9648318a1dafb3e53e6ffe7e850f9205867392be78497868043e6aa154e1ffe97d6ddf9fb5eb5f5758334b08d92174dc0c810a054108804902	1665829549000000	1666434349000000	1729506349000000	1824114349000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
146	\\x70ed037d19c4ddc74a83b9c540a6675acf5f888f6d6866bc8480edac9a22ac952445931c803073ee33259e8a5031e586b0140b5e4235c93f537c3f67e2191bbe	1	0	\\x000000010000000000800003aea151bf0ce5dfe9030a2ac8c14acd66c8c4862221f0ce4d95b1a3b86cf21e8edff4997ee28dc4ff4a7416847b94e0fc2c734eec7f262f0e0c22857de72c6e839b1879e05da67ed3adaac4af5bcb6000e28b7f2d1a6c3de2128b0974da2960134ec296eaa7829463732057899b39d3fbb6b11c71c5550bf6d13e9c4cec55cc81010001	\\x8935a13c4bbe237996dd670e6e89fcb381bf425852bebcf7a2f14cc32cda5fed546570eed3fb322ac82e7df2da49b09de3cb92c78694b4deeae61571932b990f	1676710549000000	1677315349000000	1740387349000000	1834995349000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
147	\\x706158495e64454691b695b43b03a3e786defad6b4b8a26cc6f7577c6d1162779a871da08b4f519e4c0c40efcf0a45c6bc7f27a69a5fa2e286bfcd89471b0e02	1	0	\\x000000010000000000800003ed944a6713fc7ddbd83a773704f227bd0b2f0a154669dd6619610b4c2a3f98372019de9b1a1dd550c8623def8b2f70b76a353398c737c46f70117d3ece329e1f4bb7fb67302dcccac9003749d51e4b1c51b575a240d7b298b96c3f6acce363cc285bb53448a7d8d342a597973b7276504eece3864884d5d9f827b1825045b9bd010001	\\x406124476d01336b15ddc1bfefeed29070e474dcf3d591345a303ac302f9086db8b76def3b0a100895d729f7a626ad977b9c3e3ee003a9e43006dbddbca91c09	1668852049000000	1669456849000000	1732528849000000	1827136849000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
148	\\x7279d550f2b754ee9af3f514ba52b6939b830f49d1a450d384b3fc7b76a244e434f7ff4737011212ee8070dfba6a78b8aeca446d5ccb4485ed6aaa553b36f014	1	0	\\x0000000100000000008000039e47bd6b3fc1efee25235469bfbd5b7cb98db41f1bf3dbfce41036a8f713e92a30972b5fa410d9da11eab971b85836025e1e6bc4bd40004a81cdd13e654d998ceee90d095933bd8325ceb7f2e11978c05df7448c791f63c332e0fdcaadd25a9734b4acc2f52441e60942f97addb2ecc7157da5a02dcfa67a90e9805a28ad7795010001	\\x2dd20b2b6891585a8f55bfd6ee7ea3e75861ca8e879c4e280509552d99adfc31842f0db2819d01c68bbb15a0282d62e0c0c51f3122a0f6e5b18883845adebd07	1654344049000000	1654948849000000	1718020849000000	1812628849000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
149	\\x7921911edc30c8b5b3d78929ab1a9858be28d430970eebec99fdbd6fa7b6703e1bd81454b72920ce679249dc30121d4dc5799390b84e3cd1b6377b18a4b4c0b5	1	0	\\x000000010000000000800003ec68f2c0d0c276012463936239964fb4eac5e7cefc8685f1fa8118da806863ffac06ed8e7fd0dee94326e804e9deef3fbc64af25edbcee5355a587ff431909468327e0cd05c7a5d5d7398edc39c35e14a37087c6b065c1183638c4f33c2044436db30cda9c49de2aaf8bb4f09870d662c082d935d164853060186d2919068903010001	\\x030de1e5e1f59ea210dda1945d7aec8ef742b10993ba2689166a8e5a5e4fad67306d5fb7cfd5ae5238e53d376b00be415fcfd737652cb64e9585693452617403	1650717049000000	1651321849000000	1714393849000000	1809001849000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
150	\\x7901e7dfbad7e62cdefdcee6f9fd80f378d3a1ce49f5df1cd1cbcaca165137570bfb48c1c0f9f1d283a07bee72109cafbce5c11178478ff3c460004822f83a7f	1	0	\\x000000010000000000800003cfe34fe157d878f30314ba286a011c6f2b55e022defcd702ca0f2595bc579e164b79e676cec22823b01daedf3b68206e0e4402f5752721cbc3e886194485b834d5a6b468fc5a5ca3f256bde99f9e18e40b0c34e0fe26988d6bf59561868c83520c8f6299b3e6b1aa5fb051e28c1bd36031c7b8c51cb114af02add46ff08320c5010001	\\x41051f4720dc16dfa33a1b9d0bc253307a12043596ec620e47d211cf9545303d26fb46a6de902e7d7e6a22a36d331eb083a2fecf62cf75eaa1266e6c72325b0d	1667038549000000	1667643349000000	1730715349000000	1825323349000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
151	\\x7b65939ff84027b395a69eb6a2cc12cd5f1302b96313aee55869448dde2f0d9fddc2fa0a28d16ef45290017681dfa152e6ab3af9e5f3be70d7d165f1c9c7ac5f	1	0	\\x000000010000000000800003ae2dad9888352ae58a618537e0e15a94ec05d0ba10e828a76fe347a4a9b952ff0a22adcd58a1db2e16c2cdbe630fb0b38a0cbf96cdcfad02c68e04b297349ea4007dea80c94e15bbe67cf870704d83d64bfabfaf0fe1b04b6b79e4d14358b25e7fb3f60be62a4be31be97e3a72fb152059854aca89ea7a367d043644f971db73010001	\\xb6280ea4977e41d8236ebd77be95f1ef83739611d8e08be7a82c3403872e55ca968c948d70dd0970ad9dff80fc62ba10c3a89b39c36939677e5959907dbac40a	1659784549000000	1660389349000000	1723461349000000	1818069349000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
152	\\x7b9d1441f8fe4041327126a17259f92410b3db1d3e65595e8ac73117bd1fa6800007b5915c6e391777c5e475fd514e071b4dc0a035ddb8125bba92579396304a	1	0	\\x000000010000000000800003d25ff9f24637da3fb97190abdcee0d4004512ca6f8ac3b1c5826be746e66c2760a4913de7fc8af754e37ecf986bace1bd8045eaa3b4ee89292fdbfc5644ef2f49048e9b37dd2a3c5481a66449264843d720b0c537a3b89a12461a9a3e9549f31d6ea4e98b61eafb5d54d4d258f853ee69b9f503adc627fe0140376ca504eb58d010001	\\x5e332e4561008812db97d344f08fee8facce03fa6819d90af1dabbd6fb7c2cc069794fbd3821e34874d5ba3b01cbc8f9309c99ba4dad6368cb158ced3ff4f10f	1650717049000000	1651321849000000	1714393849000000	1809001849000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
153	\\x7d3d06f8a17f18ebee6939578f655a826826fbf10bf24cf5c53e1ae413be7a7bfa0493e5b2d23a71f07035d11f3f1ba29b7211eb651067830f41976aa57f09e5	1	0	\\x000000010000000000800003d017514a47c540ef1cea765b96b96bef19eb1c0121e84ed24cb44e34ff7fb38c1f415020041cb4256b25128998344547425b14b819750d2d55fd1446992aad912485978aae2ca5fe816b28d96e5156eccad5fb59031658ff8b4667e8e3bc676ce9c33d091cc8b0fcb54deec8b4d8a2726452084719a5962cf6698e928b42d7dd010001	\\x83285a8e8ad48bb38de9e5015babe05db37c229bc0764d9628c5fc063052d18a0495a06c6118fb7f14d84516f80fdeeea7a5f48031d79fe49879e60af520ec02	1668852049000000	1669456849000000	1732528849000000	1827136849000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
154	\\x8039b3f800a501f919b0cc438956e686e047925c74dc45e546b1d2cf4490e1e271120beed21aa6484a3d3207b4e51474c8405675a865f6a77fe77b4d71495139	1	0	\\x000000010000000000800003c0347b61370141414c182e2c0d707e276d7afd4a7833820cd29d1fa0d2e9d52de4d47c6114d2cf65142d4ffd42f42b3bfb26b770f688cd003a2b184685fc6e102d3dc39432eed02a05a855a94fcfacf0dd9bc2309fd674ed98038468fd8a2c411f83f7e4aac350887e21f2996ebde0676ee1a700e725017f17f623473e9db6d7010001	\\x4ba5aa734284c7712ddaef21555b793794b53e0bd734d813b03e8828d197b00551e5b3f8f816f86db04ce61ae41eddb05dd327da41447373b9873d0a61f9640d	1661598049000000	1662202849000000	1725274849000000	1819882849000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
155	\\x81753a8f3f021ce62f7d2914b8a5ebcfc70c44e351518f0368d16265793f31fd4ec145963ad35cf973020094dfbc1db303d81935068ec8cc7ca8429967596d93	1	0	\\x000000010000000000800003d4f3e1a4d9e2f83f0c95d48c6dfb68472679a38d20c85d88060f19f2e4ae73e51c81a483b56c33bdcf5b1562e3bcdf3233f0ef4486feeca541704d2010bded98c2c2894b74ccc245dace283493d5eb4986fb5752a92d655f32d33b4cbc7baa9ec2203d5085ce1d68fd7a06fd6c37c4faa3d93fa0ea2c737a6588ba4d49a014e9010001	\\x97f1d71847dcb98c2932aa2a208712d728d26cef37f7628e340505490e62a82ca3eae3c4f5b2c61315f1664df139274fb115450d8a76f483b8647ba1fe93300a	1654948549000000	1655553349000000	1718625349000000	1813233349000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
156	\\x835de7c447a0063d98b62ac12757d23cbf291879e9fab0da0b7e674da853ee3dce942eb5baf365accf39e3a7fa4a7efe7de668e8bd57194271b42a225fecab32	1	0	\\x000000010000000000800003b6fc8839ad2e5998e7d269861e265f3ea58185385a863c667d34a357eb81e18506b74782dfa5086947184f18f3627632b7d7c82422dd753752eb09da798b0d3bc669998af881eb21fe4a61fb67befa738f5c090915aa43511b6c6f1a00f2058fe2a6718929323b5dc0b985b6b09b5f043038bddb01f8f02a9c88fc44d20d7679010001	\\x5e70f6ee84871fb972fe05374b505703519867ed3febf511403725ac00406b17b5e753507cfea614621487a6debfcde1937322358943a8da0a861b8939ff0302	1674292549000000	1674897349000000	1737969349000000	1832577349000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
157	\\x83e51bf12d0e5901af1be93de107816b696f8c2bd43d740ebfa424013a79c835c314cc3e1ff3d1d23554db88cf5b754d4fd8768212c54098f4dead0042a940e8	1	0	\\x000000010000000000800003a68a6ae7dc406ad3ca99cae58f5560966ad720c5247c334768c580f26454b5ce9a8614127fc58053e41b00e52deeaf24c0db9f62569d6af7099b5328331fedf3a566c4444b703f29b822e8661163c98928075ceaa24537b475eb5da975a0f89c72f1f212209c678a1f3e9340cd30362187ab43fcf56b1bdc915ef06aac219b7d010001	\\x99064065808016a562327be1b552197265b913d3e88d99393052b1710a59937856c1a062d84a0bdca190d9a4d09415e59abf39140098725452d7eb8a75a1c201	1666434049000000	1667038849000000	1730110849000000	1824718849000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
158	\\x851d3aecfdf717eebe6c26dca7d32fd29f9ef379f3d06cb0a6bf3366c5ed32932fbc5b3c73c6d63e0a3f24e3ce6cf844053e32662ffc37cf46d12d456a0d4d7d	1	0	\\x000000010000000000800003b60e85072a56cc71f2dda5d6c0ac78322fcfe6971c2e74ac1ac69de1ae5741bd10ef39264be9d721eaa6c57ff5e3091841f91471d0babe3d8516fd858e4704a51c9e3e99ac544a89eaa4f31fc52a379beed05b01be0759256a802e917e64ac22a6d0f825e9740d33932aee6281464c88caabba907c6893c741d906ee949b7bd5010001	\\x64c974951157cfd92fa3e116ff4adde087c51e8f9925eb418c25e3c4ce75f48ed0a2deba9a5d38db789b9e0787b25312aee869535fb488f3e1824c792ad1de03	1667038549000000	1667643349000000	1730715349000000	1825323349000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
159	\\x86653a3c9544c506202ff572309c089c767fdbe52f1cbd3c1aa1a71df20ac0d1b268f8bf8636cc9cb548fa7b7884fc371962f948823a960282e25a742dec4710	1	0	\\x000000010000000000800003a90339b8f9975cfda2c7f319839592e7719b3bea59bf320ad20cd43612b6030a7d38c7357774a83589b71c81e30f2484e0f06257fa93295042b29a6d21707e5e9363d0066d50c5e2584870544c902581ed3f076906d4818529ece76b453ff7d62f0f6bd953df332c3a9b70cfbef0ed932dfc055676f7f0782cb0eeea0622bedb010001	\\x791d3399b7b255a7e18b13459584dffa0bda44311b6bed528cf180d85bc29b392e37eee3a35aec7461c9fc18ce8f5e29d6e93c484d7d0af7b12ff03b36c3d10e	1650717049000000	1651321849000000	1714393849000000	1809001849000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
160	\\x87f9930e2a18cd8b65584ac98aada36fbd4abd80c451940b08e3d156e50c41e78a73f5398b91cbb84a3a99ea8633c6c03a011f799dbb0206ada44ad02b01b6a7	1	0	\\x000000010000000000800003aa1d55b44027a0f7fbe44802f655f0eed4251280b1bd373cc3f5c94eaf8ae03d568424f7e6bee15f69165ef86105270a563b6754c739c742f3fbbe6063f6d1f895896a4d60ba4d652a81ce8fb4ef9af64e72af7dde108a55f94f6e91a8b71d4ee26bd0c19d994b71cd988567ea1210efca1dfc03d808ea06bf058daf7576cc7b010001	\\x2fc375e40ab710213ae040e1f4ba479cbff7757f5a7605a5d3cd4d68e8b0fbd550d543fe7502c11a4d1f25f1b9b531a35c840db5eef74a10d46d81e7e5a7b600	1667643049000000	1668247849000000	1731319849000000	1825927849000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
161	\\x8959cf39cec59cb533b27d4b39ebacc976bf4f6dfbcb47a901929dea74651ad1be2dac179c48f1a94ac260eefdb1bbaee0cb081196280200b7fe639bd9f3d5e0	1	0	\\x000000010000000000800003bbebc11c0dce957b7fefba652f8057acf222f21a5394c3ad46c5057e16f0d634d8b8fe44e3d98758b78b8d57da29f598406322fa8997d52684483488e135a97567f474e7fd34d29326e5efec47d67685cb3870b44565436d8dd46326b95cc26030cf83630281822a16c7169ce87466aea37fa71e1bd22633ece4aa5f6978fb7f010001	\\x9388497cc2007d00b10a04e37407cfba4b5e912e9fcacb786a30496a2688053b6fd426f76e819f1eed8de0a7a73fa6cff2567149095b234d5b87854097cd560f	1658575549000000	1659180349000000	1722252349000000	1816860349000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
162	\\x8cd5bac8c3ce227f1b011ab3be32d9a2f0896c603095c8ca3d8c283b39cd5bb92bfb1c9a6c5d7fd847c33b5b014eb7b8489b7092adc9587edd087e098b51bfef	1	0	\\x000000010000000000800003b570a9de5b46364b0aa563bdd4be423e8b0d7ee8ebf2ac931c521afee29d0a210b6e3b2737416c1327dbc59054efcd2160896aefbca6d00311c1066936bbef5fdd21ceca0bd8d18c2e9c7166ba9e04cc763e736fbd83f19120e43af00f6ca0bb2f37ade7daaf301072a56b34fb927f00f72414fbd27379373ec9c33076c50af5010001	\\xc5cad30ff0847a1345a1db37feb5b17c30dc83f7e3c33544844bf01ee558125f39047b94ab4fef253aa2a9f5f02bfcb58aeafce36da6163f306963dd7a927600	1647694549000000	1648299349000000	1711371349000000	1805979349000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
163	\\x8c6d73e1fe20ffcecbdeec4994256918bf802c15e1d8e9488512af0a9b4790a38f2680a07752ecf17cb9a672621ec6b2a383b99ff9f4c26c19b8581038603150	1	0	\\x0000000100000000008000039be46dd0a97bf841b01e02ec00fa2c7878181827dfb74ef0997aadf3c4fb9c89de3a80c406347fd852126c6796a5c4af5f388afb0547404c49ac8ebd67389412584873fa7da44f2361453c07017156218940c7cc5584c9ea3a8b73b42f67a00454d36564090eec21fd7d5d6d5f356cd047ecd337fc317aa4748c34b2591c6061010001	\\xb57b80e5f412380ec85ec4cbdb9c17cd31d122be61424c3976304ac452e3ba18e420de02ac2dc926f407b1d0dbe8831c1cc55754342a2c29b37ef79f609d1c06	1673688049000000	1674292849000000	1737364849000000	1831972849000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
164	\\x90250dc298c0e689a252e1673182a8e81a298651a8a00b5b45ec72fe3cdf210b42333ae967ebe56ed4d626afbaa481fd1aa3dead611f2ef6f6281a20db8feea4	1	0	\\x000000010000000000800003bf6a222dea40c2ae9a64ecf05f8d2496212913b2edbe1151ceec0987cb55b1f1b4149382afdb2109fdd1d82d32de97f51990f280282aaab0a17ee29cbbbe0b7267bc8cfc413966370731c83c4918f4eacc7afa20ad1e55e6186f76dd3fca957f466a0be9f00e614fe5309e8419b14eae47ed8542c7321b97e71711ddf8497927010001	\\x0b16d1348487b35bcd4b68573ac396cabbf9d330008f86cf98e9ebb174487cbc7d4802b6601a9dfd12d7e9d7788b83f74568421fa15a99adc7162de69823390d	1664016049000000	1664620849000000	1727692849000000	1822300849000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
165	\\x900dd56d25584f54ec61f729ee6ab838088c0204e4514228bbedc802c60e84c19b20de294b06ca94a3ddc5347f606f6941dcb9529ad911873e4e0f080c9a51fc	1	0	\\x000000010000000000800003b448c640e40b83ee5cd3f72aaa0bc97778fc1e125cc3a9172ae9a4cc2b545b25444241365d5af8c35652d07bd656166582330629c8079364f748b83bb5d3aa89159e026e225f1f0cca04d751dfe792ed087de4ee9de5a5133a0fbaa548006f891f1d7fcd03700f0c1c92b9a5de5cdd81dcbe50ceeadb48310a4949b73fc7ff25010001	\\x73e653e7f5d6fa496df333729cf296a28f5938abd2c3e9b4bfeaa3b5d90dd812a77e711a9ba03a5e64c5dfa48f88ce90094f9bbea772ef81aeeabdcc07797a02	1676106049000000	1676710849000000	1739782849000000	1834390849000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
166	\\x91015369520e65e21cb9c0ef7862f5759301ae295fada8101b42d4ae4936a70d16cc31cab0c2a3a3167b30b8c0f83532ebbe9ff610743f4f8d53b889491017cc	1	0	\\x000000010000000000800003d79b192a79b0529ba33448c26f687253febb2b21441c6259f093ad52dded78ad1b6948f6404b4905f9165ec91be7539c3549a1b3d3555c280d511e9763030dddb9b15c2b13ca2f99e6fea88771b7c3cbde1897e7fb07a75fe4ad02b2a37811bb8a5e18d974ef492d65663e20fecbe8a4a01dd943efd61d72505a999e7bef9f13010001	\\x42811ee23e9e828b1a5ef691eaf53c684c13c4b1d2227118feea07d2677be4849927788a67aba9f3910210d4194a490ec5ffdcfde703a3509fb8c5cf27d0ae05	1676710549000000	1677315349000000	1740387349000000	1834995349000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
167	\\x916139cab2553b5954950d3abc0dbbb7c8ac5e8b97adf357139a102526df6fc8c9629b295d2e61fedf36cbf166f31542ca4559afa4ab9eeffea97b31f5ac4f80	1	0	\\x000000010000000000800003d5ec486482a64412bf23d75ffe6a1571c4c3fd0b68830e76e514039bf1685767c6950612f06846f0bf05c3f7cdd350b6666edee94acf40aff5225b4c4fb5424fb3f2a2b73524625762e26fa883f0401a1ccf6aae7f45c6042fdc1d909e9b2ecf4bf05d71237da90f9added9c79a656f68b9ec9b9db30489afc5c013f0c790233010001	\\xa9016c7a0c8fd328415d393fa5072843d659446273ddef549ccca5d83b9e1b6415fcba0df598676eb4c2455293038062e08d39154d164f55d9fd5f871623830e	1672479049000000	1673083849000000	1736155849000000	1830763849000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
168	\\x92d5636ef95fff962f3fdfb9b62cb646ceb5208606f4f9760eabefab33f98d89a966b5650d7533830b767cd39bab708c896b99265075a95439569bad8eac7e0f	1	0	\\x000000010000000000800003f50725c3857b5b616640c1819b93bfe6ddec2f048449e7f911f67efc622999115f6b7198e22f114022743e189531e5fcefb456404aaee959574ed02b5305264ae8b2fd721371841177f13b0e089c7ab81a5ec35987ce9a61b28bdad0bd37a6350c432062b5469b94e2acb67e8dd592ba5dbc90c1e405e4032395344859f8839f010001	\\x91634027f9bd7ef5798f41f36075bccfcfb8f776b4e7ea3213e5a8d156a08e6b81a1b6cde92b2bb9218a72b3112c7c71185fc2792ffce4ec3536c2f1f9f83402	1670061049000000	1670665849000000	1733737849000000	1828345849000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
169	\\x9309a494663c62eeb3d9d9367108e2b40d559499b58b2997d873593acdc8b43eea232326e72487b7d89d4bd57f5f126bd4c74ea408b7d0009433f0082d1ae872	1	0	\\x000000010000000000800003a8aa70ad40fc3e219ed934adb597053fa9d28dd1c7b6c4affaf17c905998814fc7dc562a51d801ec83c3fee8eae8b6089ffa64693e62685d4728a96c18f6f0e13ab416124b525b41f99d8188448025ca39b9dfc68b0da51eabf4924597d4a9caec49000ffdad4e5c40606fd0bc73e464f309b0b4d7775a1ce1850af132a73213010001	\\xaa1e207e9be9ad6bfde5d9f226a9ac16f2cae0c20507c91754613ceb9c665cc83d92b2501a2da0e9c2b89da7c11f88484b163a9a3258422ad7e93c65b76a450f	1666434049000000	1667038849000000	1730110849000000	1824718849000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
170	\\x958931f989d56f3d718b91f3e5c44aded192310b0a01eba0afba1148c267ee497d798654ce7a3acdd324e4e2539d7f559b63b0bde2163c83fc787274956b3a7f	1	0	\\x000000010000000000800003c58d3fb02c0cc68d113f6bf7f7e4e7eddd495d696d6a42f6b135ec04199ba5026e6a5687d16cc8ba1a31ac4a5c09acb29be4fdf521b1c861bb9ccc06f524832d65fcd8c4ac6a775701e626d2ae6ca24748ba29e8a24632cc7015b1402bd992cc801649f3d8765fb23ad6972ec9ea3dc8ec83007118cd0e51d0ad3c52c27b7801010001	\\xc4bc7cbad1cb6bf1ea8f7f844a2fe90d0385db5808b1f3d258e013be5c7c1df7ae236f2d1b3fe5e392ab96293df98bbcd3f9ba117476ce40a79e4d15fb25980a	1677919549000000	1678524349000000	1741596349000000	1836204349000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
171	\\x9515070884b1897fcdd91919552482123a1f2410383fed3d32cc38bea3cb287acc1dc1e50de702d4aea9b36995cc9f62331170ca7c78d2471ecd5abd1a0c87d1	1	0	\\x000000010000000000800003b1ad68cc9fd4c77935a659f6139f6acb3517848652ec9f8b1c9d86e65d81e129561491bf701b20589ad23bd618c8262b5ba221a69bdbc8457ee849539291ba8f9f6331c322053b048337a0bf05aade056c0094600fb50dda95b856094ce6793cdd8f492b705698fdc19548fce49e0875c408698897795d6bbebd22b12e43c1f5010001	\\xc92c98cb02401ef7bc5967658f50aa5c67736500183e0d7847f406067d187c88900b1aa3253111c268cced9bf5b904e8f8c4c5bb1364a99c689ed4616d077e0a	1678524049000000	1679128849000000	1742200849000000	1836808849000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
172	\\x9521a56c52ba0af61af8c8b6312dc7cde09b6e9f38b227246eb636d9dabaf7d2160c353a2468be60c76d6ee4ce3f712aa98b5d7f6f0a87959922764f7c8d3d63	1	0	\\x000000010000000000800003b6fb85ddc132e858d699df653227ce63af22a8220971ac76dbf1d7f81a4c75f375db7a0f87cb7bb56691d2bcc32339c523742a8a3a11c20c421768f245d38d2425540550ce7cd78d06c0b710f7f393e53d9da21367c329a88a9fb781340d00c35e710cf4a0a19fdf528a07762494361028928f081d7143645df26b8da8ec00ad010001	\\xf846310e9311bb0dbd5fd60ff386a3c5385fe071de64363111a41b559a5b6dd8dfb0ed484556d7204f516ca7c97dea78a34b37bd770fdf6abb8ad5102ffa760b	1670061049000000	1670665849000000	1733737849000000	1828345849000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
173	\\x976185e757e5bf07a86eecfa5d80c6554f3f3c429efad7c657fba526468d392901774f829ceeb3104c2601940a491feaeac82fbb1d4e7a6b1d160bca3fe1ef7a	1	0	\\x000000010000000000800003bb1aae49d798238b6452b493ba905e61cb5df07846d6489c5006fea5e85076f6249f3936b4b7a2626977ddee17c9b6b21e3886d299b44d1857f5b7d17428c0886e3f573ec254a5076350b78be39253fa68d9b64dee29879ed832af9c8c063a72935df2ea83194c294e5b855a0602849767e2801c317a7f692494d122abca8c1d010001	\\xdf1aa6edddb6f06c35e0ef2488fbe7d8c56e981c1e8a4d6a2eaf5f4067605456afb6364dd560c664cd241825b7b957c36b8d7aa694f64007fcd540e1f6df4102	1679128549000000	1679733349000000	1742805349000000	1837413349000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
174	\\x99b5f634295f4b5e89fd5c2b1f3ed1a724e9f4f9e6587f101a3fbe650d75ddf947b87824d331ea859db5dc0b600be25894147877f619cf9fdfc2c7c80835749d	1	0	\\x000000010000000000800003b62bfb9b5bcf5276234e3c295b1a0c6646b72a0533b5c5e754d9c8167848a7ebc91ad5d3af4559f31e43be154275737865b8221bf7964e7d9fb610beaf6f59c2d2460f44503ad190e7c6d001a54ebf23ed4565bb189d17b2b77ec2858e02dffd12d7b6382223dc66c847ff20d02943396dfb911d5c751b5da4439f1ee4c9f175010001	\\x00999661ef5da24079c458e9409b606d17e29bd6620df3f55e2905d903f1de85abba0e3b8243994c359c495b2909f789cf3c0af8e69e33f2368498699fea6600	1670061049000000	1670665849000000	1733737849000000	1828345849000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
175	\\x9af1173444faf333843c2c885e9a75ef1b56defb4c63693144b59c2c250e5219135e65c108bced8eda7914bc55a341ac7736692f0940423ed91923e1695e1c5d	1	0	\\x000000010000000000800003d268e1d1d7b35a85f0221cb591a1ecb7b95849ff1bbf07827bb6de6440fdddd71e3c0950446bbcb04d419a48fe26da4ff9442ae939a697c33da5ec32d4477bece288d7e392b5d55a5ab656b5331fd2b245d87e843389f76ba977e7a40138af411f1732296f59b3430df26be16594cd799a36c99d0741c70acea4b0aefc4c8833010001	\\xdd2559b059de56e90320e990cbd6efa2fb30dc8d087496fe55e263c2b523315b027d893e6a0e5c84395612549d56c6d1268ab8b9721771a18339ca29ed96a206	1667038549000000	1667643349000000	1730715349000000	1825323349000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
176	\\x9badcdb383df05c436ccd0b8adc27628bcfc07c6aec0036f9262cfc761ad3c4ba08ba7a81a7570cd276b35eea4205a8801e356a276cdfb7e798077d7c66c4588	1	0	\\x000000010000000000800003d1968bcfd12f055b637d9fa36e1044c31e6f23ba8be50c008a7ed6bdc7db93287bfe45db2993d27ba24c20c6bd91f113d8dd168a4e02a7b806d66fc3ba504136f76bd7d61e98ace32d4f66a9b6eb905d94ab831d1a82fbf6013b192d99a74c8edff47571e9c241e22e946b725e970f75a896371b6c5763c8ceedd728604ce075010001	\\xfad15c15b0c8fcc810140ed95a0de6753c5742e3d5089355f9d3ec81da6d8e051beb3b1a01ada9d3da96359d714c7fcb7a9603efb56728aaf8aa57d1a3eb7b0e	1664620549000000	1665225349000000	1728297349000000	1822905349000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
177	\\x9ca93a52531603cb6fc6361892bd6c70293e8f138d541a5c1600d7cc9b5d468fae74a3a9ceeb3e5ec3e3aaa87dd55edd96c65ec86366630cf9f1746e48c1e6ff	1	0	\\x000000010000000000800003f51a7fb6448833c38e2751d4ef746ff48c20dced1d1bf12a2339913a4f1109d0322efc4dcdbb7392f3bab5486b6a16a52940b8d589ceb28c44e5e9f1a5794ce585a64cf36017cf9f24c5ef7b2c1ee99b60c7edcfe3ad0db858d910cd9c36b7805f5463cf0910ac8fcd621534db47f4eb28b9beaa51e81e6b1edfa5f0644a8289010001	\\x3d237adfeb00f3c6f9fff922eaf9f6f7bfccbb24c9a41fbceb29aef92587d83a39d1b6b4329164ca02702aec36382a9e3a0f8b9e0b07d0a052c8a7437068b606	1658575549000000	1659180349000000	1722252349000000	1816860349000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
178	\\x9fd111e90ca1b4e6cfa6ac7db1bd89909b4fd30952e76843135bbd172b5d8b5e3e21917727f1b19a284a1146a2abece0dd7a0ae3c6601e93c5a6526697c6017e	1	0	\\x000000010000000000800003c23d29b152f00806ac36c3b7a209c8f51ed372670c277c176ad699b38eea73805ad8d5f890d22e3fe59154d59db80d649c2957953c8b75e07907a1b0c00b01bf65f19b1bf3214b2e56dba32a70a96c0068b4df7cc94a04f39d93731e7700f2d4e6b6520e5900c69be7b6fa699e2a7bfc2c16cfba5f93df549a394fcfe529d54f010001	\\xd0eabffc24bb89d87920048d24344204c5f35d15e70019248ea99ce0da05aba0f89fa1b8933c9fbe0a60f876dfc66c8c9e0d9bb58a9d9b00267d6eade7cc9b0b	1667643049000000	1668247849000000	1731319849000000	1825927849000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
179	\\xa1ad829aa4be4abf7a60d6c68395cdd421453cdcd889b3cbba2010774d26b11946579625a389ae4b988360ab86ccdb3137691ca66ac78b78caf4cca661ca72f9	1	0	\\x000000010000000000800003bf6436be4db145267e3fb6f4034eefcd5aa6693ce078d077aca41e28f15fa345b3bd6a5d9e4a000465a1290940457850d87493b3d9c2e19fce40b552b0c983a10c34e7845781adf79ae0fe6a8b72b8c02f49b234ee395b04f311915d583718c202a83646c1421292459e1b2784f9f2eddf16c7ac24aaea15e69b6e16ecd39b85010001	\\x28e762bb107d81e28b3fbff2a7f6cb6a8955fb42ec15fa2a504b6eb5adc1d58a129490cd6306e657cebaae8120b4d4669bcb350fbecd3672685d2f5e28b67702	1651321549000000	1651926349000000	1714998349000000	1809606349000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
180	\\xa621f3f881cfad8ace267518b2258aff2444f9dbc8c812e7b24bd8c3ee8343fdd2bf3ee1fc0cdcfa064186f3928ea2f2732ac07c0cf3aee21835dd3baa615137	1	0	\\x000000010000000000800003bf5d5bec4c8006abd443d232680bf2085bbcb4cde1a3faadc1e6ef8d0c3d4c782bace1b691727069fbe16776cc07d7a1519aa8817fe66713df9ca56fc1dc2bf13c99b50792f384bb335b8aa4339afaa9620d66ea1cacc2adfcb5a642792f27877c1c31d4baa4f954e9f4975d1d985b32429a8483031fd70344593cda311a1715010001	\\x09a4dec1cbddf88740f2ef809b1e73ca1c5c247eae685098c4b4cdc334d7cd0e4a83cd58c566dec41bd1dd6a93089f49fa57ae7167c9d02b76a562bedc130a02	1649508049000000	1650112849000000	1713184849000000	1807792849000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
181	\\xa89d5318853355a14cfb49f6ab01b584b6d7959c68bdeb5f90d37157e0b81412b3e0abdbfe5a5a6c51a9fc41401a2553cbce82e74a490f2d5587745658c5ab64	1	0	\\x000000010000000000800003d6bda943cf3e92256503a24a71cf28e615b90733c1dcc764af62e47c20aff5d4f864f2e5b2d7f4846c3bf4ae980c02ff1efc5dc8029e44b9fda92e74b498fe909a925e473d764a5b6ad2ce23e05ca1d798d6bd360ea8d425456750ecc7b9a7f8ed79c083d6e2b1153c4b130a70cd355ad47fd4ed501f153b57a617c44811827b010001	\\xdc4e13bf33d02cc38912b90c69719a6fc4a777fb1d7b5ed899db629bde21b7b85dc74b3ffca3a250848c015204f6d72eb661b434a5e154cedfa4f222d35abb06	1648903549000000	1649508349000000	1712580349000000	1807188349000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
182	\\xa979c1f7db5dcbdcd06b5578c4e4c78fdf664a7263dad852b6eae2015839f7b76a993af227be632070b7a4eacea1d94a7c7698d74207cc98894c03d92e4431cb	1	0	\\x00000001000000000080000397f2c5f7f012327081e948c9a82d95355df9a69ab9033858078e4fa30686646954a452d3f70521ad510604cb9a5cc2729f2f9f277988469b8b4206028813e48babe26dfd2210c7dcdae7030349d67fa3422fc89a97fa27cfdf41d5f68b3a10a9e098af69d3dfb083987dba453043d4667fe4f00224645422c49080c557414175010001	\\x4fa6d2bef096b1668b553de0450987254271a80fdbfda7fbe2b5487ed0007d17926255983656663187956e89c9b13d7a90de299705e8b66aab50880962be5502	1678524049000000	1679128849000000	1742200849000000	1836808849000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
183	\\xac79bfeb8f57a9d598678e1c0f106d282730ae7b23a4eed528d6edf6f1e0735b0a85699b8e6725391031aeeacd9fb2cda9f43ea5565736388d2515da8faecacd	1	0	\\x000000010000000000800003bad295c566ecb32e2e770f4c28db8dbf57f03560384c3198bb5885a402499aa7c52a24978931600af98a3b6d49c5e78db162eb38fc667980d220438675113879c8ef35baf7cff0f28a3cb671f6984137482c0194acfc94c2a04445bb57e9352305955d4a2f1b75c66adfd76bcb6fc95fd87f6f61adaa876ad560dec202bf6291010001	\\x0f26a7c0528c728ff423cc4b05fd0b40fe305984f6b3028bc956a53208d0b56ea12efa30e9a14f57e872e2f8a7257929640945105b4cb9ef16f091e99e9b7402	1659180049000000	1659784849000000	1722856849000000	1817464849000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
184	\\xafe5f2066b8c0223d5c9416380cbf8dbd6381a0046f950013a1be775a3eadce9c907a082e4100757354d847eea0c72a4d71d3fd584359088bf3924691aad5db7	1	0	\\x000000010000000000800003bc2119191ab4799e00421bb59a7d449f0299696cf92213a0b2f2dc2d39ed935e10dc6e5dbee0f26b8b90ecfba19c41955ef993b0a89643b152930d64989643d00be5906e927bf345773a797f28e6693b12adb5325aa78a4ece775e27b0b722bb34948c7075bf3bd5979a1ff7fb61ddfb7ea9f63d20303d60a72d4c35ea0a2d6b010001	\\x592b0fa6ddc1322193df66a4e166935bb6b4cc678c8ac0c03caacf5967ac12eb93ed94d5b8991b0be4e073db2aa6eb5de86304896b22ec93b915ffe1424da70a	1654344049000000	1654948849000000	1718020849000000	1812628849000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
185	\\xaf8558b18981840c9fd2585182b737e805c61388494e7779b42f2003e17e5181eb753d874cef2cbd22d97d029786e79e13f82edcf923da63a41a0394b6b08f28	1	0	\\x000000010000000000800003b2adb737c9f134521b22b46c1e103e989d5a362b4e0a5c74798feb1bf55b81780c11c218070bdd7d940b9465756cfb67edb6b55653b0eafda48955b60c67115beea04e785a39857fda90b25679c5ed4c09c93a8906dd8db20a741496a92fa78d568d0a9c1b2bcb4feb7a5913f19a7e84280658ba105b96d6e8d8d2aca0e01427010001	\\xf0f0c658a4455169ae47e24efda33dba9392139b1558336f9724ad1e6eca49ddb144a158060c79a92b7bc60cb113b0423f11b52c95cc72123df6bb6cc743090c	1659180049000000	1659784849000000	1722856849000000	1817464849000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
186	\\xb0890af99f2aa8b68d0ad9d40a5bccd4f0c5cd536ec6a8f33cd0c18a1ca095382f19d218cf40c51fd181f09f545abe39f592fbeaeffbd3870aa542391309bba9	1	0	\\x000000010000000000800003beb61f7689dcbb0dd601292324e8d271396f46a1b45b9b24bd9e61f7ff9d5a427b38f05706cf1aeab7745544b839ab29fda49e270fcaee796a85efc1e17a427f24fc27c3c413d0529e0a3c6e8cdd3e1c8952cc44636fc6bd6cbf5b4efb7193e8d6d99deca643833080855bad730e82589947b428a12bf1659edd26a54f9d348f010001	\\xd7985ae64c1e871e9148522b972857eadffec55be5b3b306472381c609fa9f8a62028bb185892f091f33099a6a8b80e56f1e58f514c0c097fa629b7f847eb402	1679128549000000	1679733349000000	1742805349000000	1837413349000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
187	\\xb1955836bf77ae98bfad4e1b950873b2972f36a9329ab40a131ca7d5664b35db25aba8af08a37443acdbe6094538bf1e2890a0226b29abb602dffc6445b4d3c3	1	0	\\x000000010000000000800003c2fb94ff01940afe166b9bd47d9d5ac1c939576f4d8a0c1285278ceee8570850900206ce96b1d5230fe0b3d7685583ebed098938bd3f3ff8850c444c865855737ac4c590aa92fb7dc369f21ecc0b4539fab350f2a6f47a79b0357b411397ac20fe9fc509695d769ec3736316fd481be828984b575edf004949d9e80d74b38407010001	\\x926c75b54a95c6b5abcae579f54a78e41b92ef6155be1b4430e3d6dca83ae6505a26cda28d50b985b8e799714db29ef0523ced367fad715330d2f420b0052e08	1679128549000000	1679733349000000	1742805349000000	1837413349000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
188	\\xb269c2a152a8dc071654f77784e11765f5d4d2b4cda163e4b0f980aefe92c77875c9ece32ca44592497217ee42e1b156e08c8aa59394cc69b5c3951c18c7773b	1	0	\\x000000010000000000800003b4d5cbb7935595df3127697e985f7b87f58141738e17e24107d9082dfbd41b4e74333a7e6b4f5781f04c37b15ad65bce69cfd7b218f7ede419b47027f5575be341d0b59eeeece0cc5afddec40811218f48f27d929542bc416dcd7a95cf9fc6c39422a2d43b5cb11ff89d5be0acb620bcd2045ed5d93d07df474bad70b1063ed1010001	\\xe2d3733356c946ba8b062be454d5304cf6f1a4294b8516aaf82a610e10da475eac1744957c8840adf3719be36de181ed0b2590dc4647660a7e75844cde19a60b	1659784549000000	1660389349000000	1723461349000000	1818069349000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
189	\\xb2e16e2b38eed96ebf7d868b27789f6db6f5dfe4cb4383258d982157390416572add3c2e38fecae8c14c799f83dbd3dc3120b6c103f28a9e87779b96a1624b58	1	0	\\x000000010000000000800003bc7e3a881e2b5fec1e59d4e379b6df78e056ffef9edac3ee3d7cd6dbc7fde4aa278aaa06b9853aef7daa980049ada5d197a089d906bf3e91c94f7dfcda8f77894946edc2cada3af2a52e5aef7b88932c02e48d88ba3dde5e0d964db895b3bd13c84d37bf7f1e78d8fa0fed7e25ec5c333544f2599e45c8179e32bc85b836b883010001	\\xc3bd61fec55ec503aaef16c772bd669e200b231a3dc12e51c895f07c89c826cd88204e1d8557e646ab3d4e30e80297792d3d35f90f5b425446fb02909d82b509	1660993549000000	1661598349000000	1724670349000000	1819278349000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
190	\\xb4a5be79757e926f817b358d5c92cc8df8b494c96e45ef8ac497cd2e891dcfa7546a69aa31907509efceca970adae319147a3ab3bb364df8bdea1089e4a8b172	1	0	\\x000000010000000000800003b2acb696a7fb922af417e24b3d309d2e81f78f1443db667047a2e00cbed84147cb76a45ee681d394998a4aec936f916a26ea0f74148016a59849772d5f26d0cc438efa1efa486785b8f209a1cb15d7df2f709ef99efe3510d7f19def13ddcf1af53d0293acbf38c0194a721055e93f6adce22048524cc9c2986766a9e11ba601010001	\\x68dcca41335af2a4797c305da310409433ee3e228fcb16aebeb19352cff736475ce9b576e698b80c43275bf061c056b2e17bde32d487d205ea77c97c17dd0e00	1647694549000000	1648299349000000	1711371349000000	1805979349000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
191	\\xb7896e9cf36414e3b9d6680a8082482f8e5672f9640b5e664ce53ef053acdc938dbe723db69084631bd4a1aea8e0947e5e568a8a014b6cacdc138b4d515997ba	1	0	\\x000000010000000000800003dbc9293412f1555f950c04a99ca21e35010733d2846c23674a7a47db644a83d91778d325990ad59b7a3dc1d5b83296f300ae79c8d16636c64fb64cc49dddb6ec8d34244284c03bb6db54f19ff81b0559a62be49bc881675dc0ad962855978ace96e4e1264ba540322cb9388e5ae0272144996c33b9e0c1fa8b039bd7ada88351010001	\\xeeea46252fbace20b9954595eb85df8c3777e78bc932f019dd2b4574dbccafc81cf71e5298d43fe3d414687c7fb00f1f9f4a95bbd3c2f9144bdc1dcbb049f700	1671270049000000	1671874849000000	1734946849000000	1829554849000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
192	\\xb80d5be954c966427a6b98dec17c9433f82502919c4c62a6e14e3f2a5c07079ccdbcfc009130909c145fa73440cb419b0b876b5e6946a62740ed2f3487c2f474	1	0	\\x000000010000000000800003a4ddd83add49cee5b968ca83b18143f8d4ae03cfd8c35d374cf8e840e329914909692b1eca37bc972936074606ba4f89187034ebfd33c62d94e5aa9aa4e8e07124a61ec5e4338b5c7214d1c8605040ac2c7de1576ab13657908ef47b165bb5e12a5cd63fd62f1c705c0b50cc166ba1a82e1d868ad741e351a0fd2315337edcad010001	\\xdafe1e7ae9bf1e0bdd6edc1d3b74a95fa677acc21445114db223fb9b8d4f0cc978d92e56876a9c5c15f28c60618862451e86f3d11ecc92b23d28f10878d62d0c	1671270049000000	1671874849000000	1734946849000000	1829554849000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
193	\\xb9817f2cd631bb460844a1ff82478b1c18e1a104f7fd4b000a06a693d9a7fbe7088fd67c5e432f13be69ce38aec34fff14254c117920c708fafc650123352f66	1	0	\\x000000010000000000800003ba0f749a966216384afacd1c7c8502f938ea0034f83d392be708b4376a801ec51702013c7980f75bd5f8e2f30498b08a2afcbca461f2cac8a0ec1fcfdb0e9a1d140ef012dad79a5c763eea0b1a4f902294592b53a150759bfc5c1238e0260a41bb03459a86c41e11508162ac2b662fba78dacc2973c273d4c674142e05e80529010001	\\x58548d48a7e3ff57b5d8d619be2f6890ab0284364f66d9a3f8969d1951bc81853717f0e8acc0ae7112633195354a9c58e2662b0c55f6164bb4fb522b1053240b	1649508049000000	1650112849000000	1713184849000000	1807792849000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
194	\\xbb753c0c4f41db24b19ac630d444a2049a3c3fc629ce5de946841db22ed36dc73aeb316c34b153098674eceeb76db4baa9de9ac7613908b6400b2129d0ec1f9a	1	0	\\x000000010000000000800003c98ce8f905960e8ef27bd63eabc929b31ad442924a4165995aa18bc2e34503ea9a9eda1a2a06d6cfcf7932138d0a191a96d15445270b227e6709db9f9d160af88aa087b2b1a39d899e66740e96bbe0bffbb5109be304f3b5a3f225a77bc3dc7b37e0b74487998dc9c0921d563c4b35651e1500c880303af3718963f757462ee7010001	\\xb3554556c6b9abba480ec12539d884ce4353ed473c03db12f393f1261e1a1e382dba5ea68048e397934d3d32b4f4d6dcfc100752726c6513968e43816f02dc06	1657366549000000	1657971349000000	1721043349000000	1815651349000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
195	\\xbef53015843610f6fc51e87877ab1caa4a12105ca36e98a6bf6ec4ba3bf174ebdca705b4106ed05998126f1feed8f9f7c431681df60d808dcc25a57485dbeb1d	1	0	\\x000000010000000000800003b0e8e832071122a5880fa3a04bff6e91c96431d804361224678809942ea83b1bee4ee1230264e401d6d053bede1bfc29e1f8be9979b30ec61dcffb59f038ab6301ed08e6fd5a5733f5c195824766b43ba59aa2921f1ce0b44c70cebae7ee1f3b091e47c47440a29667be1a3ffd3602c10e49b51cc1a1048ad93daf5750474e8f010001	\\x54434599e8a82cd17337f259cd9c413f3cb6a47ba98f575c3058f2230bd3772f1d54cdb653af09eb519e3107c67e6b7bf07fc50999e0adb3ca4373825fb61e0d	1674292549000000	1674897349000000	1737969349000000	1832577349000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
196	\\xc7b1277530ffa425916632c7a2af1dd2079d6b606a4ca297983faf9ed8fab5e767777dbaf0625acc51fc3fc873df5efe083788532d72dc10ae2673e21a42c9d3	1	0	\\x000000010000000000800003d1fd2ccbf860250e597473525cf32ee602a5309c77d8b984b47a0cd38017c55d8bb49a03b96cb3da5b6ae0f263bab7288aa6ebbe1df3a30d2d6fb8b5b8b23985a09f45fd9a43d051af39108a7a78ddfc593bf134b276d4b74607b509d15a07bcd3cd73c5ce0272c0e7271f25647712266cb6f1d0bd909cabad3b2b23a2401c8f010001	\\x920ffac37ea59f7f9ecfb14cab77b287acbcc5e6bfbebc54a7bb16af3182571b76a3fb6c57b802a9b0c580fbc13e7802e662e3bf3c9230e92a27a303c9d0dc01	1670665549000000	1671270349000000	1734342349000000	1828950349000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
197	\\xc74d6b1aaea8cce81b9ea8904323e3b9c68467f52a80fa7af01e7a1f891eb139820fb63b5a080438026e9065ce2f91512b58182e32e7bbd88fcc51a5a2e08766	1	0	\\x000000010000000000800003bb89ef580c328278a294a9412aabf7f3b6a10c105d4ac61f42b4e2bde27cb94aa1a78a215154b82f498d162a1f35b0b4bc5fd480f2a2a31c2c1577fd2b354ab1baefe2d6443dc004e333b5dba4df9038aa993dc485b5137a2a435e5a7d3a91ca0fb42093fda80e3fe334ecf5c6ada5f261b4f751a82e8524fd28aab607bdf94b010001	\\x2645b40c141b0a54033c5d15192684f3391b503c11c253a6abaf2aad7b6d18dc3cb36a7e55a39f4d2e21b9a5028331b8935a588928e92722bed340e0f623770b	1660389049000000	1660993849000000	1724065849000000	1818673849000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
198	\\xca51d2b44a821b3b9cf086ba5b70a55a225ad737a101abc679c417cd067e5bc752113017c5b60a758c02b1f00980a33580ed8d113cbe93a0c5769e378d975b24	1	0	\\x000000010000000000800003dbeae2525c4372eccb1d0f3bdd8b3ae63afab0c661438add687bae66c85e8ea9acbe6d2ac22fbbe9f716bc3864c70313014ead90b9825c0ac627b8de2eed3976cc64b72ad60a33515018353146a20a9c8240d47f14f4373f85bf49215692e527f74f459b1ebcfb331462f45fdbe8bc9c02149a1932470908ccd42a2b76332d4b010001	\\xf77612025a1b9cf55131bfa71c79acb01916c0e60ba41c67047a121c3466fc6fcaa642d740578485b7c6859718ad5ee9522af62cf86ba6a46e8c91409fe83209	1676106049000000	1676710849000000	1739782849000000	1834390849000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
199	\\xd1955cc59b2bef1f2262ce1e5b000329db3e2ac295960527ba2c0ad267bc8fa5f3077d6d633ae8a09ac7cc8eb3561456492d8cabb6876fd17129ac0510398cb7	1	0	\\x000000010000000000800003beac71568a7178e1ea52aec5f1b80019f0a2bdda3fed102b33cbb4c991ccdd7e28f4175a06387df29c65a671a0e1f3a5bd903f9bc7c794a66bc7522c368812a99c91ea3f9d60c224fac48611811944f52504b8fda487c71d0f85c26f37dd04ad4593b4b53de145e531d21a79f6dc3e022e063003ebfb42cc5d4ed93d8e752beb010001	\\xf6a34c8f8a20ad4eea3491956f8a99f81ee16f22aaa6a90ea013334c3e56feacfbd684b4f588d838965bb39e169f911c2706d84d76d628f602796575a33b5e07	1665829549000000	1666434349000000	1729506349000000	1824114349000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
200	\\xd56d6d7bd3430674908ec77519f648bbbb9aec3a148c17f92d864acebf48290746f2c0d26c2994327c7a86637b5727817029cd77d899cec1157d86bb46a4d97a	1	0	\\x000000010000000000800003a72c38f62608d9247e473b95163aba77675036ae61f21b1c811ae19154ef4abab8031beec4adffb86434c47c90fd3ee356d9e93187281bea6a62e7936f1d5ac5a55956a6792012303040c822ddb06ab27ef0262cbed99ec7abe5e4842327bc24595332bc56b21256cfccccedad229b851db02ea5ab5a2a445bd3c488a5a38019010001	\\x43fbf384ed366820487152898c88b02d536ec7424063ed7dd22762eb59290a4a1dbb56789e452a5341ad8e941a5dd246e6b33da84e20a9a5a76cfcf9f4c03300	1668852049000000	1669456849000000	1732528849000000	1827136849000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
201	\\xd78d3597511da3f082fedad08d4168302747e3bdf68cb08fd098b77211b7d1b5f1d6dd20ce8e1d073fe3544e856a0f639cbe5037d031624c3cedd4b2d3e28b77	1	0	\\x000000010000000000800003f93d20444d7e9150b5742cf0ff1b50c72e27680fae9599bd8f2037709bd73736537d5afca7eb8b52af11ab82f9d4a48c9eb84fa66a5e365dd08e00bc2648bd255b29ce0a6deffae7f401f9a501d31815e32699cffda41bb40ec8b1a500158a752fdfd30cf1a66ca4a4cb3bc7c29f0e27d19f668859de2f1c291a965b5bc4ea11010001	\\x7a2117e5f8dc55162f7bd3bbcc9a01bba5142d089a7ea6d5add6943943f7dfe812427199da117779e1246819550e63e75a4a53dcd5db8949e4754e9aaa784507	1654344049000000	1654948849000000	1718020849000000	1812628849000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
202	\\xd8d1ec47863f2e945795e3305b600a0613c32a8bf1b9a67fd8ef1ba389ba8f91776edbc06b2314209de9d0b74e01288841fdc1f13a5a32a67f48a22849e0b4df	1	0	\\x00000001000000000080000395becead43f7ab24b888b87961042bc57d13865d7814a04fb301d5f2803a3ace47a52e202496bcd641935840762beb7b08298f77036ba2887c763ca30b66a36731781afb41124aeaa7f784fef6f6ddfc505ba20c99d912d30a8e1a5857f92e072381a6bf4179548902b84f0b4b285c3ab596cfb084117a743269511f17ed4291010001	\\xab1879009e95ba9e8f815fff65de25d546994d25658959e313c98671ef76f91105c477843c60f855ae7b6876a17d29f16d39f7fd5d1f7ed6abf21edba5e6bb0d	1668247549000000	1668852349000000	1731924349000000	1826532349000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
203	\\xdc99d4e6ef30e7d14ee25afcfd6bfe48208fd0bf96d39054224d6d7149f837b56cddd0f9d494dd6422c89ded97f9e78d9c13a5c7679256d950084638be8e803e	1	0	\\x000000010000000000800003ae2f8733b8613d4e4db4f969189b6f506ed5f63b28536bacf9549fc1b68e2f212e758e9020f3c84753dcb452e6caa8d0befae62e85e67c57e11a94bea66bd591f0a1878b272478d43f42a5abdb3daca26c6063b48df44551f36c057fe27c4620cf8e622e17b390b6a0fc300fca09b71cafe7eee0f3ae8cf2aa431220228eeaa7010001	\\xa3f996e929cb2e33ffa9bfe4278870060ef848502e6284067c3c11b3062fbe793658d5ad7377497791c89e99dbd203a7b7fca51a1433c6145cf398177d36fb07	1679128549000000	1679733349000000	1742805349000000	1837413349000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
204	\\xde194b996abc901075c5b6bf9032483e586aecc613947fd8c7e0ca0d2b37994fd1fdf7df9fa3a6f09870a0e443c2da9843780300f8bec06d40a308fd438376a2	1	0	\\x000000010000000000800003d2e68584a43af06809f72afe29017ef378d0294f31bc1054ab32f976b81495c915d2e109d68ca47cc50237a1f04857e838d35ab7939ba362efefe897ed8d69f521fe4379f0aa024b22a348b1524f9e014e911d5e3b7a7cff36c9640906f2a31feff87d5ddee71f47e4e2eba686e310287915cb5473a4b373c5751fcbab84a681010001	\\x0728680de97eaedb38478e7fdfa02bef765c68eea336eb7af65e74a82a43a94f722432e3f66720ab20f88194bf145e31f84b2345c95b4aa213e188889c06aa07	1648903549000000	1649508349000000	1712580349000000	1807188349000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
205	\\xdf7561cee2d7c72e51beafb5d60f0fc783d7a61c207e1329bc0819a5d48880eeb66402cf001f07691924ab291c5ea3772dac68ac360539ad24dd9f3cb6018354	1	0	\\x000000010000000000800003f76d1fecb22bec47e6bca93df812b3da20ea63e1bc081837c81e1a18878d74e2830a8dd6d059ae8b395856dc1c57ef00f98ccd4d3f2be1e6d6ab3194b37f8fd7a62bccc8b70870d78a233b534639a8467e117697098193d91dbc779e99a149853e35a214de176060a172744daa08deafd3acc687deeb6bdf2009a5b86dbfae05010001	\\x350ca4cca966e4dcff47380041c30c554acc0f0c63a1988ce72888c7b081402550f09e5926fdf74b284d2e91ab2b1b78833d59cae46c3a4d25077c771b34920f	1662202549000000	1662807349000000	1725879349000000	1820487349000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
206	\\xe1959491d6d279d50a292742d8da84e4ed92ab87a0b5d98388ab8ea4a690e6335170f41b2fcbc72676254f4a4db8c47e2999bd198bd4573a7ef84fcee5437811	1	0	\\x000000010000000000800003b1fb3b672d878e1be072194bc7fb6f4f496c9776e778887bf03d61f84526ff6a34debd826e0086055e89681c5cb0dd0ef8d4a6d6298584d31de2e37239113b5c4945c2068c35cec596400a3556e371ba9d075d7f7ed427e707ccfa03e6c10a02350e3dbf7dc1267d28190e59bb5ec9306fecdcc81cdc42c447c3f106872d5eb3010001	\\xf1e38e98eca3afd86dbd568f4a2da1939a69201272fe2a5dfa5ad621e4bec97171f3ef8c5ded2440985ecd5ded890f9a1163525b09a8050f838c8d2a65c07409	1677315049000000	1677919849000000	1740991849000000	1835599849000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
207	\\xe4bd05577ffdeed82032b05bb6c8f2e934f250fcca4b72437a3ed8809be815e7d5cf8de85e77d1e8ee6f7cf79225080beca20c1b7733be80e9581a4abe95f414	1	0	\\x000000010000000000800003c4fcfc6523959b3ca305cd83b64f47dd9940484dd04beff9614d697a9003804d67b907e688e6531360fdfbd59435d8ae3170e4077dc4ea78d369d779ad05ae5d6f0428437f66dce45e7070827cd51ed34e63077b3242fe4f21ff4360f65c19ba5dfa258ed5face5820f45f3a7f8a1b0de43b78b3b037dbd989c99d94ffd07d95010001	\\x9bf7316add67c700933d0bda292416f4b3ad2560ed0e2ce52e76abed8a1be7d69df0b3241e75c1295cfe5493e0c7d7f8b876441af87da1c6dc7bbbe454a34101	1678524049000000	1679128849000000	1742200849000000	1836808849000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
208	\\xe8fd43e4b786661827250799a532a2f9695f8ea29bc860ce767d6b226c6c7cc96e12063403c1c5c1e3ce678d41af4e0aa842a77120b16029c6572c63749fee3e	1	0	\\x000000010000000000800003ae42638ad29ec94c900c464262b5f8c30a4aeabb04a1611098f87d682ed31c45efbb3f1b649cf8251947df11f6307ef6e1b095d562f543d14aeb77bdd61b8168116cf4c0466a154c1711169026ebfa330716e73d4f619aa512799d0406d2e8966157541216fa9db269f39088ef969bed06c7ff83939666a95783a63cd360f03f010001	\\x61f177e4ede17aa314fde42c4a6cb9a3f157059f194915a90c8c13c4d6a24808e2b397e4a726649ebf080e296308e11e30b73825e6525f907995064a4e92ab0e	1662807049000000	1663411849000000	1726483849000000	1821091849000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
209	\\xeb9147ef6af45df713ebf54535271cef7d6943d78ad2aafc6c8201f84955830e206367e8c65f37b2a235f263da23e50d7c08a9ddfa3c27b9ce71f4cfb086244d	1	0	\\x000000010000000000800003c1306b5f64b0308dccc15941423bb72974aee3d1abf95d8c83ebdbb8987d69d8981b06dc7935b3b674fee8b18f4197a42843cb136ca8b81c3644feac896543276f569c92a2fff5755dc2e432c1c31cf5ec17df47da33164b3d5ea88abd80ded323c748837264ed20ddb644453acdd389405040b5a022fcdbbf2db4e5a55cc13f010001	\\x5bc77acb750a3eddb4a70a52284937f566fac0b1575d1030068ca5157c6532c44bbf0f0ec6953f3c3bbc6e6e06ad76a71ec17bc01d61b71f66838686208ae900	1671270049000000	1671874849000000	1734946849000000	1829554849000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
210	\\xedf1f42b5b362263a33b904b74cac58dd214c6a5daf18f6390a8211c5c2418762022562b90351ca195359a0c5192853a619cd439c87ab9cbe87da816820597f5	1	0	\\x000000010000000000800003b31941f86dcaf5dbafd45dfa904b0137fb2b9e5116d6fde63b00936f9e071b11712ddc2bb0bace2eab523cde15af69a9e9d19faa4ebd6118c3dae87ba1cf157a455fc18bb8f69ca15870bb488cf5c9bf4b87fb0ef1eee887e9b7e509461b023565d2576ac52fda0a4bfd97d6b29a42530ed227f9afc1a3c444047bfb134a31eb010001	\\x5ad2aa4b04d0bd963a83cbfa041e843e382f0dbab86077abe4ea4210301162154d54fbd5ac6cc7f6f1154abe086fdc04a6b4df8a4d7e41c07b1f26b37546230c	1663411549000000	1664016349000000	1727088349000000	1821696349000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
211	\\xf171b17452652494fc3e4f112010e9c5f746e49a30b0a6ca2c8007764769a68c8d12d276fefe4c97c763765adef6d881bc8ed4e83e18771f85ee7c9531b9af35	1	0	\\x000000010000000000800003d6fca933f9352e01135c17e4d811f1afa66666c649d9aea45abd6bb8de946423ea68b6e4bbbe02cd1e593bf0be5e782b54d917478610709037996f7f3801d97d1b318ec4f74f2f5b85c743e3682e51150d6ee4c923f042c7882e47df66b7aba4d022b60c33310e43291e3bd1b53d7d66e0900b23a30947ea5422a3f31bc958e9010001	\\x58d0d0db7002c75db76fbaf0a59400574b76585346478af658b904dc789185012fb84344c6840eadbc59a5513322c70d8f25775041e1dcdd703ad6fb20c45207	1664620549000000	1665225349000000	1728297349000000	1822905349000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
212	\\xf695e86ebd0543ead1d5d3f4ca9d9ecf635b40b36b8ef646e272ff9921a442691f5129cc63bce5209600e6d2fcbdb130a0b5fd9d0129a70d9ab667169d2d7d88	1	0	\\x000000010000000000800003cf097063dd82b94938062ab90d7c4d73591fe665890f88c3f455bca7d2abb6009464d29d990b5ba4c154562e73aad13a192efc7a4d8c8c4b1f5f1e377a0d99371fabdb0074d2abf970c26802811767e1e359b7bb59cb5ba192fd456a335ab80d0c087bed0ab0028190c2ffce96fc9149fcb0e09c541419e62d3c38c115d6cde9010001	\\x9d05c9cf1c77e92c57f4aeefc0e680c8110b5ea776e20066b58703daa65e87372020ce58dd057bb651aefd0af6452c69f3cde3163da12338c519a26e4c5e7a08	1650717049000000	1651321849000000	1714393849000000	1809001849000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
213	\\xf729abfd93d7c1a40b18875c831b8bd9cd6b52553cecd4772db7a29a73db019d0d60e47c8fc45ea6f3eb866c26ff49561aede64f42416dde0c4349df4abac90c	1	0	\\x000000010000000000800003b71c9eb666e62699c7d0cb2a9532d06b58c1cd7b6ae6f25c5986f6d86cb491d9da27e1c3fef59da814c217e9b2d91408b8bef1295fa47dcfb7e4b544b2e08fa832de75b0d7c9ae23e33822e92b2b4f5c9ee2f335e359b084583de1f37456955c8dd3a93a09b58166d9b84355156494e6912a9b964f585ca3539dccbd4d2746e1010001	\\xecaa571339211f4280bee64c74d5de1e5138962dfc46990bf6b97d6cc8af356a790b0a294036f446b97fca0ab626d24f5e154326485f7a33c72cc572ea57d401	1650112549000000	1650717349000000	1713789349000000	1808397349000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
214	\\xf7e18544d8a2d7b6d5b9bba1a73f186423e64d086363e786c3dacc8ccac8743468f1b345e99eba91a2503b0844af7d2b62ae38f8537c690283732bec6c352491	1	0	\\x000000010000000000800003bbb4e3659f7657a0b1adef84d85520ece9bac46709766e32468bd32c7c6f1d8b09f68b19139f5d38dd75ffd11ce1a2fc3cc300e1cb9063a76148b85d8cdf1441d0c254d74f15446e29960bee83df713b71170f01e2f614b8d0d71e1a6a12b906c2b8ff6229bfbaac8298974a8345bf6dd47abde5e2e740e1d29e607f6f6dc5c3010001	\\x6e6007072977caead25727eb13363f4444b9102eeacf3efec9c30d36aefd25e7033f380a97af3dbdf14f7606a9a6974b8a85696acb4ac17d64614914397e190a	1656762049000000	1657366849000000	1720438849000000	1815046849000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
215	\\xf741e4aa405d62f986b2e07b7bdbc8d6c0c74f46affb42338846dc6cb2f1921a70196980fd51bdefb282d8f038734b4c91e879844c887415e80f0f2d787fd0ba	1	0	\\x000000010000000000800003b6e1aff5c47306ae613431627728c7bfd9ee67a294ae2f354c0764813371b3756d8d362d5fc827f2ec705bde5cfa4159bb620157bbe46207e4316a600b3f686a4d734167c82355b6afbfd8dab48225a81705ad80699510771f841083c9ee73d9fd5551194c38ec40ad05521fe5b24a04a3457a63c50596e2b125e2988a133cd5010001	\\x517345174c801142e4806cbb0b07d6e26a6c3d1e98c8bd1e355083b97a07603546ec6ad2603d44a7b44c8767a6846a35c3b1d64b764db62266cdc0805f3a0804	1653739549000000	1654344349000000	1717416349000000	1812024349000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
216	\\xf8e1b421e53478a39afa164bd0d697d47b395d1f18ee7d7f1af67657568522e386ea52ef2cc6d185cce1a704f86808a42ef1eaed35eaa87ce14f6bdba1b1ece6	1	0	\\x000000010000000000800003b3e87bf0e5be88644ec4ccee8c217f272d9c02d8443ba8eb75d65623ba9827383bcb69f0ebc50cfdc2d330bbec46a9bd625822333f8c3245c82e5904fd5384abfbfa87b93886f565244ebe03ff68fb3011a7145ffe1020914d3a45d7c6517167f2d68210fb7c11793de2e7698a6f4716ed07ede8aa2c3ee1cfb8b5868441398d010001	\\xaaac922e4bf7f47d6c9ebae6ce590851b5bcec9a029a27c0fa579fa31fdb1dfd0e3338695ae3a079bd7de94e5fd0142c3204c20ce0704c7056ec15f88f847006	1661598049000000	1662202849000000	1725274849000000	1819882849000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
217	\\x0296211d64b98df981e154a407eac13d5f1fd616370963087804765d3636df25df1adb22db5686f89c2cacd40f388f081f740734e3ef70e02e873d7db50f6420	1	0	\\x000000010000000000800003f5fd381d2c1abeeafa61e26b00092c6751dfaff84a810d8359d55d34be011f4a0436d3325da6330fb2a0ec404a256e4885c51ecfafc9b56673751894525442d3ede260f93241ea4e43999891d067bb2622381d05aa89994b1efbfaf2337853fedfa6465d94133258fa52a3d8b3fd137aa6c91ff2dcd8170eb611e08134a733c3010001	\\xeb619325d87d24fc73eadb0c2a5ff5c161acb587c77aa5b24d7c9b946dcdbf67c6c46d4e062f043a8faeaf4874b12f0dd993c7a8bbc61256f7cd83172f8e9f00	1651926049000000	1652530849000000	1715602849000000	1810210849000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
218	\\x032aca08d79d6ad87138519212f9b0ac22de8faf14fae7bb4cfffd616ccfd1b39f14d81cac588bb8906bf12110cded6d26b0b938b0f61c43091928121d4f0a26	1	0	\\x000000010000000000800003babcac5ef7b2547bdf9f28657a71f543eaa7094e99f934fa21ac7fd2a3aae0e994e02accdbb2ec9dad47d5257f1e4659372252a7478b39312a3705bdebbf872688135772140c34b2c94300df3c1c13bd1af521a81ff72d9ae9de6d7e78f09cc67e1b32f9e03559819ef16d083e535944610afaa56479a0b26a907d4bbfe9fe31010001	\\xe0124d583d8c021c729d0e49b30052ce20cdbc47e0db0955427ad2a47ac17f1e30e21071ac24e42a0f246bcff745106a46d79a515e9e48935caa6b7bb5b80704	1674292549000000	1674897349000000	1737969349000000	1832577349000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
219	\\x041639f755e22f5e4009ffc1a48a36ac50e20ac9adc8dd3de176c3109f579629622b1aad4b2bdf504a83e8cf58064345f8b94efd1a9d1cb3b8eb681d31cb5382	1	0	\\x000000010000000000800003c850dcf225da07cbc0bf53da6085e2a281e160c3d16114d010ca6ea519ca1beb679872cd55263a12ca08a7eb2e2c249cb0982fdd24f0cebd3901e8a8143f49edab67b33039fa21781f3cfbd69046952029572a8f9535de76f0be386fe198f7a2958d38aeb1a52f621817af54178aa60d16be3debe3557ca9abc3712d98ca59a5010001	\\xadd912381c86ff7191fe77ba7f8a47cda66eb2ecff0a162d32c1dba5f639ed4c27aa7906cd26cbd685ec574e08716b6582267e2a0e11e261ea481f7d0701520a	1662807049000000	1663411849000000	1726483849000000	1821091849000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
220	\\x061ef1634bcc133c657eb38cf2b4b76c03a8cc52e113d43b2a89b730e17ac25752976824a44bb12e3ff36b9891430e13866d3819eb8154ec96d3ab079840ae78	1	0	\\x000000010000000000800003b64b69020d39505e3279c415283335871ea3f45815e2a904a1df1a5548aeff01d3986142664f7034ef9a65e19fbf890b34823fa5c3f15c886519cbbef613eabc240685d3bb76d61d0d5d7f179f81519b407b3d516114f5348760d14d2e96d2435ce1c9e7ecab0ad7eb957becbea84255af76d521c11c9bf8f327028322892ae3010001	\\xf84d20a44ab07ff2acb1683e5ff8647e798395e6307b7ce5a12296a32ceba27cedd9e3cf0ff1cc3428439d78709d8de09d36925fe937a6298ebd273f8fc2b307	1678524049000000	1679128849000000	1742200849000000	1836808849000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
221	\\x070e5e684bbcf7147917193b5e95fdd641fcc3c7afd0496d6141004e410fabf0d64c91adfc489f61a7a3e5d7c95db23286cf88aa5b1fa96702fe6f685f210873	1	0	\\x000000010000000000800003de3c5bda4597f62f89aff1c3da58d945c6561d0da2e1d29358568ba606c281739f04716f088766d5fedd11b5efaa99cb241e614217ee5e6387356da45804c2ff6d047f70f6ab99c79b79f20f4073ddd479477124a35c39d2433d997340caeda02afd20987be139655d990e063dfac534e5bd7b367e9c3cb41c4458994b52f897010001	\\x27772c3f5363138f4cfb49cfa4e5a5a7817485bf707c3f73507aa5cb9ba9786f88288848791075600d1160f467881cedbebf280c58fedd8968677f8b24abe802	1654948549000000	1655553349000000	1718625349000000	1813233349000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
222	\\x0976c097b5db1c341d52ef8f0bd05d0f09e7524068bd9657717ea7bf4803afd3a286d2b9737cea94d586fb75d28ebca8415c49e96821b46f3d7d7002cab69c6d	1	0	\\x000000010000000000800003c72a5d7b70ce0832d1a76f7d44b2f91e28ddf5f6d6595f52624ec9b679509c8306f4ed2ac0723e299c0904b0e708bcfd7f3ea16d25648d52602c0d2092a90f9d743c71b4a0782a35744acfab90e3e654eda2160cf253e0aa4109b2ae82b626ee70c38c816eb737344da0687d9d70b8f7a3eb5c178152c98df2fb5e57ee21a63f010001	\\x2d0bb92c228619491e5d7466e218cb5bbcbeedc5af0b63ca109cf05273348e1bcb77f01c8c6da69e43be8fad8fccfb96fe4ee6590d65bda1fcf5743b4b469406	1657366549000000	1657971349000000	1721043349000000	1815651349000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
223	\\x11fa715ef627a69899438a7e05e40d4d8af58fef5ef68d4796e93e33fe193c12a57ff68d142d2429a291c34c63b2307d9cdfee881c51093e805a9e6be542f111	1	0	\\x000000010000000000800003d0dad5cb1b41480b4ca2b0685279cdb9e301d237f56cb6832e88ae733111e1a8d288e45675572f57b1ee4c069fe31e87995e5c7b9345e4d3127e3905ee6a144e44fc406ee9893c011674fb1c5df62998eee0a47236851643219d530195e9f78b549e107fb0fe064b507ad4e01687f0e32addcdab48fa9db37597508530b84c5d010001	\\xd969b4320d69aaab2ff54b99d487d2431b874955f63353496fe95b2938ec1961b40126bf67b58281c5cc498227dc4ca3223aa670d2aa7f53aa7a21bdbeb59506	1647694549000000	1648299349000000	1711371349000000	1805979349000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
224	\\x19dae1ce159ee4fcb3c75fb32d504d975939e8d9cbe0177f4a255dfd08d520766f1e6e0b65e2e6ce1deab500086d317fc8fb74cf2ab58e192fdfcc671a78b2f5	1	0	\\x000000010000000000800003c3bf9394820191979fae76c16023f84e90b3e43bfdc15b9f42042b3428e88130df10bd1d1133ad190cff79757b5e0e35eedcd8962accf30c1e4345b50170878ce6a327586788dda910f6705dd972f3115479ad5c4a05de6f3da45f39148d1d698f5eb1d860c9b1ce66afe1e66cf8f5e41836b79fb6032046e15c3cb2ab505be7010001	\\x580195ad7abc4b9063783f87644e73105319eb4578c2676b50df331858fe987248aba29f14d582b60f45d919ec889faf5cd3b4cb30c532c1460391d594fcea0b	1662807049000000	1663411849000000	1726483849000000	1821091849000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
225	\\x1a068c2b36c015cc6c207cf26f80fb8c9bdcf90fa0ce4708104c229fc96d47fffc2512d8cc86c4db5a3eb90d265692c36fce86a1c57731947cb726acd68d9bdd	1	0	\\x000000010000000000800003dc6749361279af2682637d0cae7d5673be5662f8eb1672ffda2040915df5fae61eb499590ad31c37bb5c83fe15c9382a3c894f119eaa1f9e69e85c378d3cadb0028094cee0ff36c041eccf34d1fcf8bd25f3b73fbbe4205802799e0e3db62e0cad74fbe83f0d7199b53413d0ffb6fd817da9d268fadd8d1c0bdd80cdda697f2d010001	\\x685d36cd0d55c04d55d733330654bc4719a36cbb01f531cdccbc4f1e2b0d351b82e3904d7d2d61d917e5d2ffedcdc73986bee8e39c0ea81781ae222329ad7208	1673083549000000	1673688349000000	1736760349000000	1831368349000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
226	\\x1d2ad36584583dd159ee7aa863b6f8e88e222632dfe0e2aeb7260b5071b64ee8e4a891161e3dd834519aa4bdabee506dc6c0cbed92bb56381f6384fb23b78aa7	1	0	\\x000000010000000000800003b381a14ebbfee9ad9e455b41d44eea3a43b7cccb50f6ad7fc72a90daaf44a307500ee29f912f4ab305037ac39a10d3fd0facc02115f6301c3ddacf04dd4bb899e6dd96c02a0066690fc77540194bd1b4117ad415f2632a845c26e00e6b367c4cf63eb7f74a9261a34d4b8f32afa877b32c722fccbc0739b2c1bd576fb2bc5ddd010001	\\x0117bbb44fb53e53fc002677429d66cc8f3f52e1c6a2699fcc77ac0ed78b9f74ccc75cdb8c76346b4e32e6fbbe0f747117f8328a8be68cf60aa5f6a18ff47606	1657971049000000	1658575849000000	1721647849000000	1816255849000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
227	\\x1d1e8748f914b57c815fad48e8276fee86fe9f269b4b3a0a88478c0242c8af302173276773a37cc32d4d689659ddd08ce0a651dd4da0b53ef0fedd5ff7ab11a2	1	0	\\x000000010000000000800003af1e8aeda63fde3fb657148abb34589012c89940f964f34bf9b0fa8b83791e030fe264f3ba1bf4d7c8ddc2f2c03b1d188e5955767b7bd77b3c1457599407a6806f2fc98946635b8a322fb8c1b043f04a1f95adcbfb926d28330f9cf69f85dbab68c53b6dbb1d90695703682a2901ef4a318f6bc4fee31ed72610c787b286a395010001	\\xd3041f5c456772710a5a94089096b7da7bf1c8a8b02cb98f634afa2c6f28040ae37d0d3443772f0a468113ddad6c00020d97d19c320173bb84d67166c55b100c	1661598049000000	1662202849000000	1725274849000000	1819882849000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
228	\\x2106623ae460d24f48a7802ca7596a07f585da4da948c7f1b930bd28f04106835d0d78d7e478c495066fff94b38d86558b8287f4d87035c9de6108b4c6f3c846	1	0	\\x000000010000000000800003a989a6c66fd34bc18b4f85679b40a58836de62d37ff05e4dd42d673d1c0657295807a0d46c3ff0fffb7532a7a7cc04dcb239e944798b97d85228a8bb7c634753506e97deb75aef7e0d5db666a0d204cdf9df0ddb46351dac4519b2e67b0bc3a05b04cb3caba02855fc7317694247f23e3f017408f1451a215f37f8e695593a71010001	\\x96c869211d63e25a0222523c3a7ce4c89d6e7fab7a0fb1350b5ad5fac68e8175f7861e177dd2a8c5a8eec78ea3c665e235cc86a9f57cccc14917ace96032be08	1668852049000000	1669456849000000	1732528849000000	1827136849000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
229	\\x21f6fd530816eab06ea046b1ee980c5a15186d6e0fb7fd8f9d6fc97e834df2af6f8796a81ce20f19354c77a2dffdd5c7c0fce2bc865a813fd62642b54506483f	1	0	\\x000000010000000000800003d5944c5737231b7e2d3b41851c1515a563531b89c5519512c73e73cd4fffef6c619d60089bfc9e0b5492016f3ddf9c855b5533f1936371289a19a63bfb1430776d8368ddd16ea1e9d5212992a0737a31797c032f6ff9ebc5395cdf776be6953ef98ec8bafb01fc061c08b29e6dbff94e7f2c06358c85f4a6bcfeb38282924053010001	\\x03a343924dd6f3e8bd32305d0ce54c5d0e65c7e391c2f96b4f601542654ee73c2c59102922e8d0dbcef6a96ca8ab36bd9f78fa01bb423d985f2aede54d164608	1671270049000000	1671874849000000	1734946849000000	1829554849000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
230	\\x235a4da37a8865c34d18b8cd3666050a783dbf74261d48271079caabd8184c19f8ab0f26124d8e5e7b7d10f0138bc104449c4417d6c7741ff6279160b6601ac0	1	0	\\x000000010000000000800003cf1fe965d1d9f6c86aab055efc5eb535ac06fccf41b440fdb76e7aa4b0972e29b640785fc9ce005843c76307d220b67cdf3fa972e2a8d77e9217ff62b80eaab3197046ed6afe8902b3afa27a6925363bf72974f3aba291eee7aed3af4b19e9f84bc52fbb5142e645787655caa949d51ce1cebdfe412edeb2008db0b4e8e9f3db010001	\\x4731645ffa4e2e0b5b5432b33642c1a808f7a49318e7be86d77e7b55ac65bc78c9453e7d4ca81ded6279684b56c28fb63681913f741f5d238380b79aad59690c	1677315049000000	1677919849000000	1740991849000000	1835599849000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
231	\\x26de9afa701abdeface221a7d8f3a45e11132261c30ad51ea8902c22edac3e4ccbc4fe3fc1510fb51c5ca7004f8b4bc4b52a0eb988e214b1ef28ba015420a259	1	0	\\x000000010000000000800003d1aabb3f153463e76e2176eb73d9d87a33377c48d764ed513889f589f2915d869f4396ff5f2a2699f9225f8f850b015f630ced01ba7daafb988e05cf7a22abbdd9360da59869d3d7d921fd8c46cacff13f3d40587ab6d9cc8068b6901fe9b2253fdc80f8f6f7be2068a0b16487495181a0af818d4263062d9559b4360b649a61010001	\\xb78dcd8ff0217670a335e57e3005627c86d149ef7accb54e58c81521145eae5689442eb817b618ffa591b3e3347bdc290214628457ce5715742e0917da089a00	1649508049000000	1650112849000000	1713184849000000	1807792849000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
232	\\x29fe6912492475f4cdc0abc79048ee9e505b73772c1f7e0df28863bf8ec34dbcc844828d60d2d3de7b0199bf2792fdf724727095f051cc564ff5eeb0c7a62217	1	0	\\x000000010000000000800003c9428df1c892f23543dd757c6f0b9fe03d0a855067a3bdb2ba61e0732c723e2c6d94adbcea039dd8d4aed3b17f9a9fb6bd2e1ce50af068c326e8c9fe2c346c3622e63e0c0be9bcdb47cca28546b50c6ef970c05136b6ecc6daf3532050b99da3dbbb09f2e280e87de007d65b65e6b675d4341aa0967e8d3d4912c145ad28e6d3010001	\\xf3d6c71264889c647a3793571993b3d7ba1cccd787af552777d880629171ec30784c2b47c2b44c369babe79b88a21e15d3ae70e9b8fff4d79da468c72be60c01	1651926049000000	1652530849000000	1715602849000000	1810210849000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
233	\\x2972af66beaba293b180ea4a2d23202a0b31848137a50bd47565f849b68f2c1b9c2c17f1bb0ec31aea3d6e0c2cb23233aeccb3812cb7a79433d6b4a4e24d8a8c	1	0	\\x000000010000000000800003e82eafc377f148fdc4b8e637cb020a4c5e814a77d558841c24378a8e3f11124766223f7b66e6fd1e173fd4bf5a407f2e75bfc47c02d284760c60c8b9cb7ef81301da55f3da603ae1fe7f3fc4c1dbea646e7f5a10321df5ca6b4568b74884f995d03a322f7683c920b75bd6334476bb72ad38c53674083e2419be49dfb56b9c2b010001	\\x060d84e1d3497b62dd311905b1f7c178f569ee17bd4faea80c57045e1283a29e6cd0292fb5e970c0fa631c93ef14f4d777e7e40638ec238de8b34eb1271b1a00	1668247549000000	1668852349000000	1731924349000000	1826532349000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
234	\\x2a02f53a222d8b4d7d743ed98a94070f8810ab723b9ef8e61c665eb94117e67d666a331d877f94875b03e35d8286b18a7755f990b8c7c6d094e97afe91906301	1	0	\\x000000010000000000800003f7efcf3cb6b03b52ab90e3072800f02a77b002dbe312e46f0b7776a8e61d32c310a380f4aaaf42d5ad98bba6c749ee7a6aa054b98794fa2de87213da45dc5f42195f81ea2967b331c9449484d7e3deb0332fa7e8fd0263dbf81faf17087335e00b94f097e270decf5ebc5d735838d2e3a26ccdba946dadada181b5056ec0fff9010001	\\x32fabe0e6281306f191574a30b91f90436c1fb3003a99e3861694d9ca270aa37896d4936452c39aa1b328b418a67759dd13742dad03ee49a72a9b289c07eb204	1651321549000000	1651926349000000	1714998349000000	1809606349000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
235	\\x2c5e933578f48b32dff492b018bad8961350e4881142b520739c10c358a80aaac4416b97c9be6fa5e57421f3979d5d3725401151131ff44ed3034bd06674f00f	1	0	\\x000000010000000000800003cd8411695cc552d3894ea8016790693ab73457b4eccf9d5baf665131ec0c1a498c2e41557d3f8e63a3afbb96ee7de25bd85dd77548fe7fe95654da6d58a45a264243544516c116a609129ffebe23d1b0f8d277f995d721914f68643ee69c3d64b065eebfc43af28f976992642e47a08aeb09662cef8f94fdad71d9f0677ff83d010001	\\xb5720030c67ca0a6694912cac93248327f18916c9660a66a9e451f64b873e617a4ade896f1ed1138c72a2f8f0ef5b18a4fe8d0b5a4d202e9a446983799e78709	1657366549000000	1657971349000000	1721043349000000	1815651349000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
236	\\x3152a9c6644abd4f2c978ea6fe60da2f864fe7855e4c94fcd7a31d0c2e092e252e49d9d908d86893216cfdd16649d827edbb79a01588f684cd40fd43d214beff	1	0	\\x000000010000000000800003c45989db67b95c0baffc9480b09f45e7386d69a0319f81956c6df9c617c913fa0accd9d65974cbe810c0d1316d70811385294443411c1a040f89b88cda8787edd03f2e9daf6c34320ef974c2465067d027d1c51410e6857b3564e032d9ec196f3dc4ec25586eeafb47f0602db364de7640add9acdeee824e01c1c3e383dbc777010001	\\x16cc391fe9971824df0f99695f59af1f90b39131bc92cd5d21d4aef6ec3301a0f1123d3faaf48f9da7ef7ab9f7307dd1aebf0f1f4c6a16f5396fa30d3604090c	1660993549000000	1661598349000000	1724670349000000	1819278349000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
237	\\x3fa6ac926cfca687a691e0acae7f9c6d94f43206c8902391a698aae9303d7a6c262c398f43d18654122b220ea58005622da1c6f0112bfeb0741300453a666bbf	1	0	\\x000000010000000000800003c5e9f8f5135a0b7abb591d815b947b484657b0cce73c722ee9f3e0b6f58db7d434115d1819698d2dcce2a9df037e504dbf3d64bfac63f5752274dad3110be98e1154f1c5439ae16d586e13797582ac36ee1b80cfaa9bcc983edf26f3eb053f670f39189771a598f0a0799764fbf265285649e3105c2be3a488e432f964444579010001	\\xabdec10436109dd3bee37c5720906c9a1a5d803b7dfae39d982d36b25a310d36cbd09c2ef554f802bf9369edbc9fc90f75ad7dd4e80238045f62503940ad3402	1673083549000000	1673688349000000	1736760349000000	1831368349000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
238	\\x417ed52ed0aae52492bd94d40016f3ce60431274248f0d17d10de5b03a2f0a13917f02d3057193e078b9add39b5ac6634f67a2a27b6244f0fbf63177d9f760e7	1	0	\\x000000010000000000800003b1c4a994b694327feed33476aae4db663a74b3fc377bcc874fa0090273ede2da7e46eb373eb8f4dbb88acd1a9305cf5cb1a1c2b15a308ae9c3acaa861173764189bd3557bcaf642b818ac16f2a0692f9d8cd4848b50a05824558801ec3a1b37f0da641284e8ed1302b1cd19c0bafe545a1df6bcf9eaf970fea0c667e164be3d5010001	\\x755463d8afb4c906b8d90e359c5e01b63407fd953db51b191857227f68c1f2d2b223c7cc500b97a1b593d5ce8b5ad4cac9f7512e412230f9040d5db7c979f001	1657971049000000	1658575849000000	1721647849000000	1816255849000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
239	\\x43a6b215b70114901e5bcf43342eec9602f9ae655d4c7c95cf189e96904cc790365a6ea4292205a8b283894a3b2af24853363e0d57ee3380ca0fd62270b4ef7d	1	0	\\x000000010000000000800003c828c22f65c8626c809fca1a5d9f3afb5b9986ead2d5838c53bac34ee6c0f221e8fcccd84f49acdd563f12ab46921e19faf0632f04a22ff8b4922501ef69c9a2da69037fbc805045335aa3876a45f60df7430130468aa6f6adcb56379275b7b1a92c71d3ec8830cddb2e42eb4c49649df691e66a99acd23af9d243cf70a8e949010001	\\xad16ef0d8e520a4013e55b11d6b9f1b37d829db676bcd5fa4da8aaf1702627552dfb2f10b8743013baa5803fd7d879bcc44090cf05166084d585bbb57cc5b10a	1648903549000000	1649508349000000	1712580349000000	1807188349000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
240	\\x46caaa8653b6f7ad292619d1663a2fe7216eeabeb00e638482d81c890ab0dfc8b547b2698650c50aeda69baed1449580a63aeba01ba3856a23e3a9fde2141041	1	0	\\x000000010000000000800003b1a659d8138e5bffdb43903c4ff50be8fdec61863c9881393a7da2878e15a0b651973cbdeaf0f6caa9401f6ee2080593c40fed4aae7287bacebb875748f7a3b225908776c43c8581bc597951448cf78f47bef7503468bf2e1d7b91a8510fd1d539966980c09091fa2d2b5a5479e0c17ea190650e695234a5166ff229f201c42b010001	\\x2bdf7ab76110a7917f878a120d72b67a1918c23ee4d5d3b1ea04fae2be692fea53b38ae98789d3283ae308206383abef827aed7747430c3448ce377945ec4e07	1664620549000000	1665225349000000	1728297349000000	1822905349000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
241	\\x490ac88e18dd42ce7b6893e5cc76c13ed8e7e22cc37c383be6c438f929890c8a39738ffeb3188ee016a8fe7f22f96f53d54118972e0541ffea18c37afcbd7353	1	0	\\x000000010000000000800003a6206589f74995e44952e0a9ea940281443288edd8cae2187c46942c3f6fbfae04c34bbfac2fde30bc27adb0c4dc1ad660ee56ccc543f5c5bf0db96f6eaee9393a7edc9687bf5778585d97536726a6a403289b88447a3f9e6dc0967c533298df263ba6ffffe7f7b5b996cfedcf87cdeb4018dcb288d010c430941b9db9137331010001	\\x5ea778fc4b318b79d2dc1fe72827695593a600f2076784b8d93f120a15349dfb217fcf5c8d8140a0876fadb8acadfdac72b048edd762de1ee50a0fe2d2e7f702	1653135049000000	1653739849000000	1716811849000000	1811419849000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
242	\\x4a72c3dea825f907c8042ef9e57b49b9339c848a5649058182abc82ff9679ee0ce9aaa4e9280b47202469c9a8d5f17a466e7c4c52268d2e7e91af3aff5905265	1	0	\\x000000010000000000800003bf5041b71304b344f67a2bded02058e761d975d745b18c4fff42439b7878e42a36f2c154cad7b2cf3aa3be078ebf6f3c07624f8e8c17352fb5c027129cf82166a39658b588bd72923a468c2dd9b7bd321281c618ea280c68d5e4e3ccb57033138f8afce0fa9188b4ce24c61e8776492ac9d2068053bb0c6d103bb01b5db8c8bf010001	\\xac8119061bb3bf6342b69ce57968db6c67f278274de6f45c76b2f22139077248a3bc1d8e3b6ee7b4379d16b2b96ccf4f478c28fa1281ceb6feed099f96d09902	1659784549000000	1660389349000000	1723461349000000	1818069349000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
243	\\x4bae301c793fbfa91f49d8519c5ee229c0c47efdf0fa471c563acdb7efe4eba6d16a1a6efe41dbd8e68bf6c4e5212d647d90e6287c6c2a899f6b0264fefb9e68	1	0	\\x000000010000000000800003d6c999b8d2c093df9d779cbfaa1dc61aa33d30dbe9b29d67e0ac4d66f629b1d99306b4be6de37a942ad9b9494dcc1e87eb1b39a5952209bb149f331580b8872a2a4e2c03d4f228d202553da96bea2ac2f278fb5825a9f01afcb3de8013df7f4a2b7b9df680d4614ea447c7e9b6d2b8b14fbd77470f3b16966004a07a1959040f010001	\\x4d6b8d8151d93269c08f031fc66214e41841ee25f9fe92f3f0b1ed462065ff5aeb714acf67a7e4810db70ff129a24b8f938909023feebadb4bffc26b35a9dd0c	1665829549000000	1666434349000000	1729506349000000	1824114349000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
244	\\x4c32673e328f3ada7efdfde3423310d148ea1cf7a9948ba480f2aba102abb176e83e4299b936945dfe69ae285c185ca8cfb8b1fb078cf17f89ef840e6e9f73be	1	0	\\x000000010000000000800003c3f82046c00d846ff5cec32971f514ab65a91ce0f0f68b867b02f7d717bf618107086a876c729916d10d19e1d1f0bc019bf42e23cdf9b24ddf2d308a174ba8bcebd5f2f9f828f6bababb338d819f32142699da9e6b22ec5ac0042faa848ffa7121016f12f05faf8ca08fa6091cc9dcca95c602fb577d432382287794ee006f87010001	\\x870cd009680bfc677839bf8679f311fe5fba7453dcff6339bd37b635c4ac555651583fed3f927368a7500c521096aa6ef5b0545fc0429c9d90ba06c8beeb6c08	1664016049000000	1664620849000000	1727692849000000	1822300849000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
245	\\x4e66ea4874f856c4a3e738f904f046ac604895cd537ca72e838d26c8e0fb4bbba44d808b0cd51a169e205c5f8b536a07b7786596143092866966ce6a8d949d06	1	0	\\x000000010000000000800003e8b6cd502e2f68ce6f606f12750a2672542feee267c0147c948fd0e07c5de303a77ca9b0a2f538fef01a9c084d479357c32e63daef884caa44186487a17a49e291dbe669178458afc24007b99c0c919bd4167af4c080510f9aa32e824bdb13ab119ec9d1f98086e174d3284c4dd194055827546b2cf3424a3225a6ac2d5506b5010001	\\x4159ea034859b7a5ea6972b1bef6ebe92d0e14590f8b2f0af8ffcc26987e68d0612e514e223a6d47cf220bb0671883412f51c8ad0d09f0f22e2061681a1c0e00	1657366549000000	1657971349000000	1721043349000000	1815651349000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
246	\\x51fad74c1ccd891995c3edad76de8baf3930958cf1429974df742e3b9687a9b97cf7c5ab6b17705b5691b88503c6bb3bf9f614eea5482b1f4895b155b672fb54	1	0	\\x000000010000000000800003cf69b62819712391a929d06e3cf283acb7ea4e4853e2313981c5c46c9441f0260f143a9ae264e1a6b2422c566a00fab69aa0234392f9c805ccfba9bda1767e834fd5f77661806edcaad4db347c10dc48b12d0a3be04d6773f30c58e7f289078678bc42c46b583e49994f77173fbba93ca5535eb438407dbacf418a7cf480a763010001	\\xcb7151941a51276cb14aa9430082de9ccafab34b5bc60e33da61932e4897332e36b6e31efc79a75d689a859f609a1c1adf621f064b6314209b6e337ee25db90b	1657366549000000	1657971349000000	1721043349000000	1815651349000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
247	\\x529a145f7f8727ba83ec78ef7de2d73c091645b974cc2a36c674717633080de0aa01e85016f810b71c57913734950b4a895d4078a72af553ec7d98a1c3882265	1	0	\\x000000010000000000800003b1a47c91afd085d4b1d1905c582dc7ae673abda7ea659896411a066523a736cd155106932e11809d3bab7c8aebfa66d8cadcf7d4d02996dbeff9ba1f88b0e11f39a20a8d850a23f061775f4c9ed6f3c7415f980fa8914733a9b35d160569c8f0574b661904e669860292125d4a1a13ea56a6927a9d98c2a02fb6d01effef50cd010001	\\x6cd2d355db6009101f5f954425b4130954cacfae898f832067504f68fac5be175838d16efdcb838e0102babf4f3dd66925225f4c369ace7fc03d7ed0525d710a	1677919549000000	1678524349000000	1741596349000000	1836204349000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
248	\\x57b692c11feda3b52fdb16f510f4bec068bdd6e2c036671a50874069ce01e8109fe14fab511527c4053564ccad1f4132b2d566dc8bdc7f50f4b14388e1b96b2f	1	0	\\x000000010000000000800003bdff31cea3aa14cf718ffacc851381ac40d67594b262efadd4589a1f23062dc81937b476cecd047e1357e7a22457cb0e786565481d82caf454beb6088f0c43f711d50dc3ea49a90c4a56cca87d7abea2ad07ddaf5abc0057de33e33ef6d78110fce5952a39d1c55c9f86d5f00dd412a2e86aee9a0f1873ec59b679052890234b010001	\\xe3270aed24462065c5bbe8945baabb4e9166b7a322bce41c937bd8be8db5a9e2f5895d177437cbf9c36755cc605177e219dedf4287cc725b2d7c8c70444bef0d	1661598049000000	1662202849000000	1725274849000000	1819882849000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
249	\\x5842c0d6881ff39b7b6970fa5ad33cb5955a3c50fc8967d54cabd4a1339a01036d585487e06954d96362ce8c8c353ac71ebb92c694de9b5bb33a020ad77a1268	1	0	\\x000000010000000000800003c32117e1ba4e874850e96788fec1b17ef1971052e76c46ae528809a5d0bf91faf7a99429834232b1c65b227d70ffd0329a06cdf353147b83e6805bb7083eced6979874ccc22148f37120eac64e63dee3c50795c89018f38e8b1c8d998f50d67074bb7b47fadf20f501484f596ebfe944446cf39403fe10dcfe0964b81291064f010001	\\xc1431699e924c31acb1817abf536360d47cc39d57d8669a64e359a3eda71ff34c4c36006b1236537b72c7a40663a7a1c1c85ef44e187541faef0006f57cef508	1671874549000000	1672479349000000	1735551349000000	1830159349000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
250	\\x5aea6ee696801b6dbc5395299e44e91154f7d6df3237730866b99a0e4bce8160cbe22114f5b8ee1e5ded9bb62864ba378b86c5d07bfb6bafb2dd9733a60b4b7f	1	0	\\x000000010000000000800003bafb4f03505ee6ddda173992218400ba36fa820f53030e9b0eb968ff9b0d78565a8b6e0534730ba3561ad18eb97ca3858bfd5571df5bbf78cc91f2611ee76082c8980b39647b9c98be3bd27874946de07912ae7c41a7f465165ebf8edf1c69a6aadf4e00376f35cd31a509280ba796826f7381cad733cd20dec8fa2fea20bdef010001	\\x05739e0b354bcd5ebceca461afde036ee2f696ea2368a8a541f0283a11ead9034a5335a26c6add1cee1d67f10e673b0fda9b83b4dc3ede1649c19470b7686f03	1648299049000000	1648903849000000	1711975849000000	1806583849000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
251	\\x681a4dd2c443f4ea8e8fe4066773ca1cb93958c0c4d91d55aa5c350b8db27b6d06c1afe15bd72b28f089824ada13677d9222bd821985a12f6a7d7b4c5e2b468a	1	0	\\x000000010000000000800003b44f66a11ff86c186b8992ef0f26b213e6ff22fb2d95c46fabec50f9351270a757a2a610ce449224a4d020cd86efe95264e21cdfe61add400bf54a07c96d49159f229fd17d88d52e02b477398ae45ba9a7b39a1d13344cf466d05597e6d78f02f890fa72417d306b7278812866ae9720e941db8e7b8277bd898c0874ca21734f010001	\\xfcdf6defe763145f5b895dc693dc72758d9955e7869bb9bfed4e2d9e9b36d1acefdc111f1dd4a0ebf3a54c246cd4e33fda438f0e2822371ebb5eafa6f21f560d	1679128549000000	1679733349000000	1742805349000000	1837413349000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
252	\\x6da23de6eb4c8865007c9620e75ca23c4648bad24ce1ac8785c8b8e48e45f8293dddb72915b0b0fc36467aeee3288c2a2aa81d39b87e15aa13845fdbabb8768a	1	0	\\x000000010000000000800003cc45de6531afaccbc819337bf4033ee8415586cf5ae3720aaeda74d1ba4d0c5c3649afdb07d53bd595b2ccb9ff590b1e5dbfe637d9146fdc09f9ab58492e0f46d18482a3ad288ae82e554b77a98c0d4b55ac0394c5683201f79f55d7115646fe79922edf50e71c5aa0cb168ff7d905227ee966fcf8f6d051ad749c6a2ff290af010001	\\xf70fef81f19eeabe4c99435b3124430ba210211a44a86022db0b0ccb51180f6889159af5fc280871c83343cec47f1f70bbd78fc1e9078cc9057ff04cbf221b0f	1670061049000000	1670665849000000	1733737849000000	1828345849000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
253	\\x6eaea56f25f44adc89c947ec6d6a5ad36684d8fa21cdbe1d5e2a4b567ff9265b87ffe266ad744641527a86f99334e10d907ec5eea038b1e83a4a3237e926aca7	1	0	\\x000000010000000000800003a112c160b7f2877f5ea8751fcbb14cac3bfd0ba58ef213c35e9cac95b94ff7a492457cb167cb9e45a03c697d7cd10b657ed8554ac653550dd646ea9da9a750e09d7c243c6137979826705ae1aa2a5bea93536cc2be986752fa72ee2da439c474c5f21a2b16a2ce40ee66b2e01e6b187c2310fa8bf4ff37327dcceec5fed5fda9010001	\\x4ac3bfcf3531ae49e28c44394f426237b9ff79b3291e23d7be2919cecdb3bc72cb014e29dc25b6accc52a00d7f5a39db9c7d7fed1ad04cb22dd9d6ccfe6e8003	1648299049000000	1648903849000000	1711975849000000	1806583849000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
254	\\x6f9eb0a54cd6644e26cb59e277cbb10245932f54dd88a05e506f6121a1a63d2012f3479401e857700314246da67940ea47e84d2c6ccb615f1f0ad9adea0a745d	1	0	\\x000000010000000000800003add8db510869f2bc06eb4a531a359a9e6bb831fced36bc6efed0cedf81b5f66454447ef454c323e4f8907aa75ef0e6aa4180394078382ed831917200580fcf92a342deb7d9782ab3d539d2b5cb4ff45bc2ef1001eb0df1b5bb6a5475eebc6eefcbdd5d6665d5e657776f538ad146bc4ce271478316a51b144869080c923c8281010001	\\x5d74c7e70f81f5c066a805eece37aaefc327f79adc46e4f32b4344afbc17317efa871b2b7acffe1a8cc505df389ca772f1c32754df04bd1d8bc78b379afae308	1658575549000000	1659180349000000	1722252349000000	1816860349000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
255	\\x6fba3f6419c59ced8094cf49cc9afaebf3925fd3a9464f242dfe4d0e3c3d0e9c4879898e1dade1ced75da32ea792c81a12b945dbb67d8c904134a4e08f0d9041	1	0	\\x000000010000000000800003e5656e971886ac593b0fe42ba45feff451ce685f397a3ec1c7d1a796da61a6472cfc581350d39ccc91082f6acd909f55ab41992f2a52cde284a51f777f142ce2d46c799f72e73123bb91d706dbe5e1540309cb68f1cbcc561582fa8a42f395052211e02f7bcd6622a4b782e290b2ed99f2a7c5ca2a695ab910de93e8802bfbe1010001	\\xab1f0d4557f409c456f0155f631ca688c704b9f18597651c33eadf5682e7638aaf7afecd75f0f4b06e543abacd22ad06bdfd8bdf665c1c3ead74c857eb29bc07	1667643049000000	1668247849000000	1731319849000000	1825927849000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
256	\\x702ad12dc3f7d8556adaccf4b13d62aec5a3269d7b33ef8d77fc5fe6e91b36e7f57e0a4e35efd91cd9030aa3a659e4606d516025648f71ec62e111ae0c62ed12	1	0	\\x000000010000000000800003c5af080241f609df08bf3a0f05c25cc4d653ae29cf4ff6afc3f6af4f8905a96b9e8b7f56e3e0f0e8a7d06994190efbe6efbe030f5bd3ea39842843ec074b3943b5e8031a49c97c35529a8d4d70a48b390df05f0ce265b4005d987de208b2e20d9d83b175b80d0c79b7bafb897e90cea951cce6493fed49c5b13d3f1627ce0b03010001	\\x722b8aad202b2d48bdb0783704af3c79837a4d174ac46b4cc21fcee31242281e78e7388ad906e511aec8416e67a8add55971ee8db4067a02e7f286b7d9de990f	1653739549000000	1654344349000000	1717416349000000	1812024349000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
257	\\x73fe9899e4d3f7f095a5805b91396f5743696c776891a382069b56e5e1e26213b3cc04adb8868c0ee28f65188f572dda95373c9551094351018de872e5b90a47	1	0	\\x000000010000000000800003b453a36af174fc896f2945d2c8e818c09bde1dd4483b6e8d0b1f2ff14063f24bd676db0121e23ef49bf70f57337f1e4a851f2b6837932a0c97d744bd285d232fb00ae5cbaf17a9155ede7cf3be5d404a731a4686080895bd95fb55df197eebf790d22026893a1647470a2287fef7dfc3e3226e58d520e99e64876ed9924d3da9010001	\\xc06357426560ae58c68aae3a55cb6231a7ca586d6b09861d1967ae042e66032f745a9da05900530b39a93362c9f69aa5da6c3ad3e4c165680d85a0760d9b860e	1679128549000000	1679733349000000	1742805349000000	1837413349000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
258	\\x773ee88c13adf2ce74adf9e15d96a03f6ef706e603a2acbc02f1287e241c908dae8294c5c3a3d347391973b446d9d73685f360b69aab2641672ef570951d2d1b	1	0	\\x000000010000000000800003dad2e5cb4bcea27b93102bbe595863ddc377f4dcbe895d8e54b7c70358400b0b0bf56a0bdb67913314dee3e0abc73a22a402cb37efe68b9f40823a0f2d4a4f7523ea0cf0137d05bbcfb085a1f87c9c0c7c6cb51a8aca3a9d594f0669c683e601b713e0e796b7604394455c031ab5d540ced80f38105acb1de302fdf911368d49010001	\\xcbb50d2346e8b2d895d6d0b6b3596b66a3ab10721ec5f03d4f1e7d2f775792739e887b39862decd38b9be17513176364ec1fb8834ac5f8c6d9ee79a1df8e490f	1675501549000000	1676106349000000	1739178349000000	1833786349000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
259	\\x7972db3edc246356d1e5290008e8f5b9572d409e9aa68cf287a3d2f6ccfc4241134bfca04187c7ce06a208c97f10fd4ffa0e3affffe4bab87b052f7dd3ed5fce	1	0	\\x000000010000000000800003e8fa180c7776b654294f1691874a43c1bbebe62ca9728b7662ee59c6812dacf9e628d86a9b35a08a5c01124c9eb6bfd3d79c3a4c480c70fb21addfc3fbf364aae2fcc56cfd70e937f63d09494f525b4a3c0ab6e5a13e1782273bc433c97e0f4b0b5ac92d3fd6bc2a669be3f63196b65dc5befd7c983a87ee3ad642e57a0e23a5010001	\\xc87298757d0d8698564f4138a4a72c6de3981849f345a3e3e67e37f7949e37ab415c1cc8029f0ceef30f582c37f40ba5412660f95e3564ef6fa0467fec0ea30c	1675501549000000	1676106349000000	1739178349000000	1833786349000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
260	\\x7c7a80dbd4afaefde6381f7ceef3d99f13e808d50a0eca0a3d44a19632bbfbdb4e9d797adb5e9259a507ffd2477984bf679cfff12c0806dc228ff85e216179a8	1	0	\\x000000010000000000800003e2b88c426c0709ceda965191287d351411d8373a266f3fa6c11380c18f9291e75da347632f1f16cebe839efb7cc21e9a2f1d973ac4c399ce15c7476ec834a7019027fb7f4f4d7c8a8d89bd41774366077e78f6595006e4bdf8657cead32f2fd1ca7a76e449ada2492e707312677690928844fc3715f278fffda4785ba8bd184b010001	\\x1dda8457a7242de8de1e19cb1587f9d92edef6dd88097c9a7cb4116e1e45d5feb7b6a1f5403b645d74f64c4d2e5c019658f55ac21d2977541b50f3a2ca27460a	1675501549000000	1676106349000000	1739178349000000	1833786349000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
261	\\x7fa6f579ae555e4a36db7a092073cf50feb7fb70ca0187d0ff4a649e9d626a6bbc361765651478efb4829151eef01560ad80fee47770c06df8861c4933875a79	1	0	\\x000000010000000000800003c616600ac92f5e3492fb88f828e945bcc55c6276a59f6b1331274f0924831d14b2d24f15a6f588076cbfa432ade9822463e6921018752c281bcf36155c2712e17e3513b5e1f51bd3570e3a88a1508fc8692a8bec330734f7bc0a524151144fe5b38930c1b3e1b886b54c67917281ba2d591560ee75dd8d01d5354fa39c5f93e1010001	\\x3aaf349d09ba0c99be6c9c5b878f5f566385fdb2bd23e938f042705e34092b7dfcc055582c1418de0279d06f361c54241e033dc7d47d446cb2d4868cb1dd390a	1669456549000000	1670061349000000	1733133349000000	1827741349000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
262	\\x7f32015b251407e9aaa1f0cef313a56011e07ba2c15db66bc951d7fb0695922e9bafd04b8fbdec012d7abdd4f3248b762ae2adb3a01468d1c3267db1b4454eed	1	0	\\x000000010000000000800003df3349a18561de4ada6917f960af323282acae729dbe49e0f64d1a217351fc243554940f4cfdb99f30a1257cbc4434811c6607f21e3ed275b2a4f889b3ea69b38e4b3ffcb7ab3a67743c330f32b2069137dd2807b7878963beecdbd2cb187346d1d90f242733f7cfea3e2ae7f589f4f970c2b575a18fba972e53acea97892359010001	\\x18161b0f43efcc9b05e3cd206d49b22187664fe9b98179216977a942287967ada205c00be1962514d92877d0affa9c3f9f675b0acf74e84593906770a824a209	1660389049000000	1660993849000000	1724065849000000	1818673849000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
263	\\x807e3ff8eeb9b47da54cb4dbc73d88e9d1da2d52a3e03752dba02a4081d45b934f4b2a4391f0e3f8a78621d65a38ec6c4f1444aa8a17228cacd0f21467f2b30f	1	0	\\x000000010000000000800003c4ba1253da80ece9456fac0c3b27ba6678f77b1a83ab35811def435b5a2d9de08ab41fdcfdb888975c695388529e37613eddd02bc1a13dc83025f1fff397ac7b760f80311f7eebb5cb691b32884d9c59f35f510ad08548059f70a07dd7d89abda950ddcaddf1c79d33689ccba455f12efdeb121dd90bd37ca33124fa3d2ebeb7010001	\\x42f5739df08592353406e2713d951efc42e156381691baf2e1d8b7ddd3a8d3ab6ded7c8486705faeffe2371aa46d39db76733133511d8533f7310a61dee98509	1654948549000000	1655553349000000	1718625349000000	1813233349000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
264	\\x816e5948843376cb911ee0fe6df77dc5ac3a1914d5fdf4625393e6222bc79c15aa6ba41ef1b860b823044b1daa1687b60fd4d1fbd541214a3ccb6ac87aa40cdf	1	0	\\x000000010000000000800003db75cf8bd4b2d71cdb432bb70bdcf45f7671c2dd944da10bd5e5a4f1cccf6b6d1c91125b4096b4a894c8bd747f99add382e0fff7329b705dc5a64b0d7b8cfacef4b0ce5884b9b2777e231793fd8eb6c47791983251e7c62351d4d2969812aef2c7a3c632530f36a88b8279889683fff3544327136117bd0a14b7633aba115249010001	\\x0e789cc1aaebaf7e65bc903d400c5c56443bec5334888106b28e0a91fee81fd35fac883b190e8f4b6ebbba01e447b5827b3d0d6168deebc425aacbcff8efce07	1659180049000000	1659784849000000	1722856849000000	1817464849000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
265	\\x821eaf3a9c0358a7f9de34cecbe74aa1d54f26d583ae391176ddf2d6a510db6bdc69370acfa1bb376ce3e102378bb8efeb7584f3f96cfbe50409bb5b7b5e6ad8	1	0	\\x0000000100000000008000039e9ec5d63cb2b1194f309a8fc505fed29b726f896582096060a47a9b6b9bf86bcd0daf138d7286820fc732d8b9f69a551ee224c80c2274b5d5e0859dcbb2f1cee91fd4bf7e6ea328a028ef7eb483a8823809d49d744e6997549761a6cbbb6539d5acbd74f2d8b62a9b346ace245b8065360dd5f53190b3271fd7c6d0926d3537010001	\\xd7b288d14af1964e90eb2af50b5730722e2b91dc85626a6e95eec1f830db00e528752915b4a10b57fda1740aff1eb747c1ab0385ad3bfa806a89592cbc2e6e0d	1656762049000000	1657366849000000	1720438849000000	1815046849000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
266	\\x83066bae8d3b78ff01ad672207d38331da85450b4e72bd2b704df1c5d91dd1532e60cc22c189938acb390972fa8bfbab19cb33e7f190c798b20992163e2dcd6c	1	0	\\x000000010000000000800003c14c8e4e545e17572a8a1c84e437180ce32af662d3f2cf5730a60a0591647f9c56b27b021fe13f4b3a2a828c8e540a5aeb906fa6466fab2d6fdf27089e085bb847b6be46b7cab1660a91fa8c3487f3ec1a691da1b53615eb1bc9183bf0814b36cbfbe7ad99aaca191f9019d56e13bfd0ebd5ecc673363f495bdd56a65e22b4d1010001	\\xa1fd574dea8df35282fd3beab58d5d4f6c18f7341500bf7124b331f1f397d986336036e9fca2c54d78558b0cf9f27716df4e68a7f02bdce35e822969f080ed06	1664016049000000	1664620849000000	1727692849000000	1822300849000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
267	\\x886a8718da82a503d9cbfdcdcb6262136e0de0e49b2a0870d05a27285d17396de214b8716ba4e8f812021cbe28249740990b32cc9f443b77992d491573204076	1	0	\\x000000010000000000800003c7519183e57379c201860dc922b0ad517cc5ead5415ae77d09bfed91aa0a802cd9998843439a21142528e4b52e598cce52a5207482fe621b08a824381323f52f4bb5b0d7217b1466b460d61d3c59f4a59b9de179429f3323a7987761ac2d2be3a7e068d3a11a0630f3addf18ff2231ad5a76b9fc1aac92e0f2ee2fd176dd27c7010001	\\x95abb8a165ab8e01da5867ce37050b50fb666638e0ad7dd5079689f589d00806745b8d5e4d79161d4161a43bd1f843ceb99f899077c52fdc90dd76983cfa4c05	1671270049000000	1671874849000000	1734946849000000	1829554849000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
268	\\x8ad2318a7b7e94bafccbdfbd553362871c9dd2839e28ac5ae0a24dfa3cbe764125c89153a9ccd8664979f30a0dffd593eac5569f505834441f8767562e3bdd44	1	0	\\x000000010000000000800003c143ac27c1fe2239620513bbbc8e477225c7980e1918a6ee99acd096e5a085bb8264e76521ae186fe616205cf8ef320fac1238888e273354e95233e1bf9fa8b2cb1cdca04f461c1fc01d44db78af44d4dad42292941fec954f22503302e2f5263317f599b0045d369a7be066a743880cdb64c858c88b4c3b570f820af256ede7010001	\\xc5fcca627ded934a3442d6489ee87205c90fb83701746ed43edb362524c7d1781c1267caa69b96a5d244b2c29f8fc27d07ade8752fd3b0e5f11e72c78261790d	1650717049000000	1651321849000000	1714393849000000	1809001849000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
269	\\x921a149e1cad608329c8ece6221ef6170768074c1ad88fb1743d5b54629586b2eddb479e76a1acaf5b89e1d2e0cf26d7785028469a4c98ed0cb3db1919e13fd9	1	0	\\x000000010000000000800003c1cb326d3bfd49ad6acdadaace5005efbaecaa118a2f4dcefdcd1136942f7ebf75dc4ab37a44a79b7c92bf6af3bab12b2342d41cdfb7e81b12f6e5ff692d5716d713eb78c256433d38157c3e87c8494d4ea6068235e34ab8481ce1ca824edcc0c54d9d9f2b3d91a71601868cc285e4b8a7daf91cfe33128b14d240e4b6b270a3010001	\\x29cee06d13287dea2ab01c50ac1ab9abae98660ca8f175bb86e812f3baf5567d6bb25fc70c59e249099e9ff80d84303bd26293a28161681ab3a5960f313ec601	1667643049000000	1668247849000000	1731319849000000	1825927849000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
270	\\x95467e20446f218ea2005f969de5ccd59734da5e0a54659e15d6379320a569b642f7ee4730c464d9f384cc93d9acbac1393b4f777b5fec1ca25bee51a3b295af	1	0	\\x000000010000000000800003adfcca24f323608947413e4ac4f4cbb83c8919c245983ab66b349ea672558425d38703531a1a1d5a6d687b52e894b56ccfa52d73dac36eaed47bb0220c2c7692a81cb76f26034db22de45b834b19c8969b2651580e78d192fc32da2b9bee379371a280720acb0d7758dfde3e5613e15d7d8956eac68bad0cc2c6ac9024d93429010001	\\x408cb2898290804d78f6bf6a031d87a0d719fbb36337c85c4dad031930686cadd9be0e919445fd212f4d591a0117993070d0820fc262469c7d587d79e0e40a08	1661598049000000	1662202849000000	1725274849000000	1819882849000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
271	\\x96ca8e91b823ce24d0725bad1fc822cd457ff94913ba482dc7f4d2def2410c5390641d1adbce902020ba13329f7ff1af958ddf3c777eed76476579027bf23eef	1	0	\\x000000010000000000800003f2748c26a06e293589163c80d1db7fc150390bc72e804ffbe2310f23b4ccf5d722d42e30ff977e885209d59f71a957ce9e088ab6bce2ae366c88d4119299858b1712a23f12b73b716aa928824ab30c5755eb4e04e91509bda0aaeddbd9bea2e32e4f28eee9b850b590cfe5013fcfb66e77c1e3a74b9eba745de1353c5ecb36e3010001	\\x7041914b76e47a15d9c0dcdfe6f0bf51beee54a1ce7b72aabd3e1cbfc95795d869c19941b094652855b002902cee442ab63474eb932ebafcd43eeeb45a8b9c0a	1672479049000000	1673083849000000	1736155849000000	1830763849000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
272	\\x9adac2bbfbc910d3bbb27b1b75ba73b8aff5ea4041f72fcff8fca4f2fef4c832edd2f89b3d7ed4ab037287904671f28e25cd9f335eb25cf401ed18297d49d2e9	1	0	\\x000000010000000000800003a5bf005b2b0274efbed63f339c8a2bea16539b36b698325178ff20d74f6ed79f797f1bddf28e0555ceca6a9327bb86eda991660e50f19d5254515836770645f888d6c27c47316349bef17f859c3457fa528bf8f961d7a298b6e3752f4a870a86b020a3d21419f68447f0fab46012a46591e354fb79e8d4fb112b1035b3795609010001	\\x337f57a112bd277fdf2155c1c9c25c97b868045c21176580dd8322a5c3d52e4e28bd54d30a7a42a0c5b0a059d46cd05df54978b3881a1342795aa551e4e40504	1659784549000000	1660389349000000	1723461349000000	1818069349000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
273	\\x9d8a33e460a27dad82fcf843e8504b726db197ffce13346f8b07be5ae834e85cadc758b10cbc5f12bbcff16e05f56dbfc73e4bf55cb63aa9f48d21dd00bd270b	1	0	\\x000000010000000000800003bb293df38ca099835e15781d732f07aa919431d9364eb0ca6ff30192b0c5dc5aaa6d5a0ae42c16fa64459834c920a42c6a03349114c02982bcf13e2e438f641f26b1fc24f327f2966249dc302ebac40c3625c09052b508c839a07ad9e4a2f0dcde589e590da1e23a296ab2b8a453b868a165b7927aae0c738e95798b218d539f010001	\\x8f58398fec61fcdca7735e95a335cfe42ae4bb606d3415f73f980cc3924d54b4139c844a85c309fb19f1c18ebf43e9b3ae8ee95777933a26aa22206e5f839909	1658575549000000	1659180349000000	1722252349000000	1816860349000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
274	\\x9e72018578e7e2069e319104c8e0bf56711d7ea75d5988ce3c277a59782a79ba54d5536d1e1d12551e19c4a178cb942f92b22fd2a0d0d46476ba193060b27ff1	1	0	\\x000000010000000000800003b58592b133166a4ca995cf869f4af1b59dcacf9e54219d2dd69d36245425c49f93eb9158e5f5133c4064eb602f09682714daf30a75aef6e11632a8a749d886a0cc4376c68709534c6fd80e83cb1bb3efb2320e423bf2015560ba3e625969826aca220eb54d7bf37d34f4004a9ad91f776d7d30232622721a7e7653b8c5da581f010001	\\xf8337ee5191b30976fa83d9f1f301f8018d06b56bb1e1f34b6b6178d9065e4e65830a28ced0292047ade6436f2c2180eb670871b10c72bda87745638a5942202	1674897049000000	1675501849000000	1738573849000000	1833181849000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
275	\\xa072f5ea83cedb0d661ae5a85159df9601476c07d7d9659adbac283840059919f59791f59399e42e6033ef23a42c78fea2e2efa855dfda93e308161d41ff7b51	1	0	\\x000000010000000000800003b14405c2437fc4b875ca0a2b8de46c3ef152acd7d037e969bb1bbbfaff127fb8890ee5a31d6c84ae31642f6d6787cf28e333c2377aefadc4ab30a14b39ac9225b9560ae46a88a2de575f3b9b6c47d6f2d1b0bc55c5f13e149e06dedb2faebdb31b84e6e657d15fdc4a805855535a2272e6564ebe305471174a38f6f6d1094579010001	\\x5cba77abebded63aa4e6a0fbba206338364aae20d64c29fd89f4bb4ddd42f6a4426f736d4613f8a05be873c6790dd0fc6f4c2f776d0f2c7df067ef177cb5bb0e	1647694549000000	1648299349000000	1711371349000000	1805979349000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
276	\\xa1bae89ca31633f13e417a96641d300e7603058152efb1131fd9d25f3d7f4d3a9a5881ef0ece3414d140260d44c25a341ebcb3a11269ce6b0182564faecb07d0	1	0	\\x0000000100000000008000039c62429f06129ed5ecd4a651df25cb7fc489c5a287399249a5ae07942c2b473adc4b3f5ddc27c76d59a4e7663a4af01b3e0fe967113845463ae37ed4c11de98682f7bb9d0824e5acbd3c0ecff3b04357a170da0b9de912d3ccb081182ef1dc2a3574f4eaf93e1aa1bb861d1f841a784bcbda446d03fb18a995e2dc95ed7361fd010001	\\x0dec2c8dfff008f92827c364918d6159ed2517e168633bf80ccd887902b00ec640b8dd3648aed9a6c47490c22e2aea4b9981821c7ee93d3d2a4e33afdf833f00	1669456549000000	1670061349000000	1733133349000000	1827741349000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
277	\\xa40af2c1b0f38abcc1086d549b77a09484a050d071d23158855d5edc8664d724c3e09ec005415e0b42f9eb92fafe0eba6a1d229463d4a194970c10d16ad7acd5	1	0	\\x000000010000000000800003bd9b0f5db434abd4033923bf332b17184154c594cc0d8cb96021c5813588bef3e5e16e88a6e6050df5aae0e88c7c1bd703fb13facfab442e0143aa37e8e725dfe205f247af580b330e125ef2bbeeda514ef26671a4d6af4f7a9de96959be4dadadedf9cdaa4b1b7045a49037ea14d6b1b2dd52f3424b7c5ebaace62bd5cfbaa1010001	\\x63a9c6f75bc30825eadf9835e46a5435a1da0457edc9810bf4180b4d91664da3fe06cf16a92a80c2d7a0dfe352424f6fbd9a5e8e2c2fcb6bca30799ac3827800	1677315049000000	1677919849000000	1740991849000000	1835599849000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
278	\\xa6fab6f60f95fc1994c4512a563dad6fbaf9a1aaa4dc457781b5159165f315483762111cb4de0d0c97401cdfbea01d74837517aa5c9b32710e3b3605a84a826c	1	0	\\x000000010000000000800003c687c9960bfb30bdbdf63554f65719bc4a8b549bf0ce1f4cfaf4cdbe99a1227609483583cf6435ad2c78e03d0cb8c9e32c9d02d3e6eb6cd53e4f5571bceecf112f4ed4200a0c5f64cfe6ab3ccc54bb4766b6baef60ba866cf84497ea9fd4098f76a44da472678b7df72eb66e81af194cebe8677e776a0f9d69ceaa21348851df010001	\\xdee61b61f6b65db4eba7dc317cddf7460c6272b93e6bfda17a37c6c0bb2e074756075377057f31f1be32447c4988fdafa7985fec5a991783395d0e8225e66f07	1660993549000000	1661598349000000	1724670349000000	1819278349000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
279	\\xa7aec4eb5395038402151a0473dd2da83c239ca890dcf8609cbed68ca1e27b7edabd940c56c5ce7a58da55d7cf3f7437e3d8eafe94f21e484d3511b642a34842	1	0	\\x000000010000000000800003d0c0e4618cf2735667b1ecffc81a12c22b897f11156a60a4a51fa7035237c6a4898bdcb9e129ed0768ce4e876c5cca403009d1195202f72c2dccf9c7d3fc8b452518ad0c2f9bd2606dceff18bb7f9f815e7231496c0f81eb4cc15ea297301d28ef945b7976cffa73eeb07a625523ebac017aa593541f5bcb8f4feba53c6ec38d010001	\\x0ee4cd2be445127824a071d51a7641ad577ac19c2d341f2beac052ef45593d7b76c17e8878ac9e031b82bbbd3d4a41cfccf4b40ed1ce339a2ad54eee79fea206	1663411549000000	1664016349000000	1727088349000000	1821696349000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
280	\\xb012f63c7a479d4bf8e6d6069a8cf12c30e59d36f32f421c7b03358ee9e313b1176a27ac0ec9d4035b168fe0babfcbb68de3fe5b8a95599cea66779dae09f440	1	0	\\x000000010000000000800003b9b1ad11b0ef4c0763d3f43135e10c8ae3fa0b681b9600f979687b67769ea383828530b722b8a94b41b07b2960f5c9fca796916410505d3c8018ae473e47d0c8f987da52c79f23134b49cc2182933860c92076d377f40c44b77c3a8d2a21ee4a9fc6d49849af7a7019bac423ab518efabd32652342ce8379e9d0c1fb95650dd5010001	\\x13d70932dfd69f0faf2b929dab5c548a53ee198777551ebcc38df2bbfc768666640c4bb392d7508c68743ad1c6919bc76d690a46657e71a61fe3930b524b8b01	1674292549000000	1674897349000000	1737969349000000	1832577349000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
281	\\xb9de873900cfd71d497c5086e224446808f2eb2e7a430b15eb511c9a4306986abe7d8a285d5a19020513f7be01b38de7c26a9447c955002faaf1080216c725ce	1	0	\\x000000010000000000800003fb068eb44bf4cbc658fb231f2663e4c6033df575cf4949c61ae0bd38175a16cadc140c07e50ed1d02760de6137d1304a9f1592f494717de7d13452cbe594b2cdad8b02d7493018f2f01eb66cc29dee4b1014dc7618b5f0ccb794c9bbda7bee8472e6008b6fedb26ce1087f34099f6ca4d654c10e8ee9e0f823fd3dfe7d4a18df010001	\\x81465ddf98edc8845a4ca6e41f8a85cbf51a77a3a2a289a8d320e7d07518299ea19fa570bfbf993b97dd5b3f3b6fe97d78b58e1a38e8d90cbcb6f2ce9d54fa08	1660389049000000	1660993849000000	1724065849000000	1818673849000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
282	\\xba866e80f95d9aeea916ae4bc3b3bcf1baebf0e97cd24695cbe972fd6a6df3c9a6edb0df1fbfd657b43e6cea7f2e3ffb885419c4d7d669ebd032a6a99167c3e4	1	0	\\x000000010000000000800003c862afbbe8fac004adec2db79d33366195eacdc303f0193fc56dbf558116fdafd8abc399a0b1a6a229d1b19119cf1e240ebac8aca69f3cc2bf399148e806a318566cde3bff1a9bdf646d4ba424dbdf232544e5f629b49b44db8e8923d4a391ce591854bd06b5ea1b747bafc5c45adb27e0b343cf662f819cbfa3b47da37111d5010001	\\x6b700c5365067b050e4b753be80cdb3c98a93acbce9a3a4c2c5a4ae073e5ba1fb816578a5f95bbad16b5aa6ae33dcd760d87a4934ee752a56ce7af3af425850d	1659784549000000	1660389349000000	1723461349000000	1818069349000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
283	\\xbcf242f4b7adbf7e0a4fe2869600c37b4f651d237f3d74528cd0bd7c85f642b8c3ef3952609d75536b986291bc3e65559e1a0f297ad6a464feff01d9e0b6e860	1	0	\\x000000010000000000800003d4be976783bab2915bd24f6881c4cc71c881be89cbce263cfa26a8847d18bdf7e5557eb1979f0ba4d01de225ae8dcf1eb13236593bb222c8391d22418e2ef7a6612c3a6edda45e9813724dfee183870d1967840a3e41f063a8a832173ef54b93ce74cc15985edeb8977ee48ecfb4f4ab08ea41a054c09143fcf1d33d9e4725fd010001	\\x5df0fde572e1de6de8d54c2c68e6405cc78e53b8a13d8d36e7dfa2515b2055b2b6fa101bab76a1b53366cd7a0bc93e3be0c544cc0ee70c5ad8c04b8ecf0b6604	1674292549000000	1674897349000000	1737969349000000	1832577349000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
284	\\xbdd2546ffcb8163b95960e350cadaeba8912d27f674ce1a3e81bc7529accb19bec1783cbdb060c15b939fb1237066ee6b67995474bc285ba7c04ad41c7e59ac7	1	0	\\x000000010000000000800003d311cd2176f6ecbcf0bd560ec5f0a4be255a9cfe6d23940375873a8e52c6a694de386e0f6919246e435f0d9d3f8a28cca973404531741e8ba3d50d2e6c67d6e654a8af3ffac9247607fc53cf69d8ab8195bf8b44d93d895b7727f30a4a6f1a1ca42e95582e531a81448b2d8665c012cf3ac7c408370b090cabe731c7bc1994ab010001	\\xef911d0e44f41dc0bd1d298daae461351694e63af6815ed975cbd428b0fc0e6560ec58e5fb2e79025e2242a75ffbd98762e953aa8816f5170dd77be9b3b46105	1676106049000000	1676710849000000	1739782849000000	1834390849000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
285	\\xc34a41e56f51a6e882386fad3af827c6021bc5f8df3bc4807dfe9ef04f9cb0998de428e7790c83d0d6575d9950c337fa42a53fc9886ed7cfcf705e91d596d892	1	0	\\x000000010000000000800003ac6bc0f1316af893cdfdcf77982ae0cce39fe527a4f2c52cac1e76496ab1beccc62a04a5e13ba3b094c53b0ebb191d90c1d0a99b5644cfb4403eb8cac83eb13e4669ddf8c6cb4c9d1387903d3d382a57419b94fe3acc745100c8b9c5feebb43a31c33d282c98ac6cbe1dfb5a936691075eadda7838328bbc9f78a4dd4b95991b010001	\\xb22e2d3a67453530f66f08498df6bfc0f32a0afab4922c8c1a2f9683b0fa24218a5757a0f107d33fadc05543a28dc05c01f72c1c2f83550df349c33a5b1ce305	1667038549000000	1667643349000000	1730715349000000	1825323349000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
286	\\xc5eaac40cc506ebd9f89fe9ff001bba3177786a106dc9e72adf5b071bd134f6ff5c0dcc28975254a12707221ec3e8358f03b9b018807ec3e090520ae67f8aee7	1	0	\\x000000010000000000800003e67239ffdd46eca741cbd4a6eeb57a864e61b9324033f96f363e1937652ac59a28be66a2ad941c84088e9b3b22ec5c26989ced52ddf2ee1c8582cbe7d272cf4845700645c90c0986e783e7b9e99241ab26908f34edebdade1bb27093b215cb6ac4ef7ecea7b6d9ce3b6a232d61b6c9848b437814692a34e16ce680c2c8794739010001	\\x156c8a624ccb35e6d3af520b2268e37e5285427e37a58156466a39ca768982fa6a836cd7a14f4e9d851d427c4e482b44352875668b8dd88ab329b0c69afaef0e	1656762049000000	1657366849000000	1720438849000000	1815046849000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
287	\\xc6d6ba4697aa0ff58d68098205f1a934b8c6a4248f6411e2ab4e01daef2e38b42c98bfa8ce8ddea677ee88affafec38c699425757106f16df4a87cd2cf85dbe2	1	0	\\x000000010000000000800003ad9e0ad112a57c2ae9ac81567aef1ccc19c58ac80f9dbf67bd7bc91f93949ec5a8870268eaaf9712d4f49971bf6ca46c78345835846cc5c6698347679192fdd86bbbe447bec86836d34e84b19d25fb001f9cbd2492378538be95fd5f952a63140e3cd4e1b9c7e1fe8d2c70667d60924e8a60a48bcc199da063c6d08e38d3b93d010001	\\x6cd0ddf9b4223c720e6aa78fcf07adf9c891affd0156c6cb17989d4dac1f4404cb04b87a802608931d4bfb7401c8f7a2881d6e6aa34f2c465b37aae27a427900	1666434049000000	1667038849000000	1730110849000000	1824718849000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
288	\\xc836aa707974e4aff8a8f291424b8b8c2421310155571d3c2f4a2f38003664b8601f3ecab4cedff9865a251d7da8d460127135b111a945ba2e742ae658dfb11f	1	0	\\x000000010000000000800003c6a1fc48b547eb058a7c8b7d97494eaed6131e5ba55b6af63153712bb5aa1a64eeb5cf4ce17b7d30f3a7a6dc3d1583e328a030668eec340a5b76ce7b794c8579f539c8da21f5f1843ca0c43c56bbfe9b31546cd67fcde05ac19a42783ac64e27345536a4b6b6985019e84f645c084fc038bd3de14efbafda430f16d4bdc693d7010001	\\x3e602420c16b69f806c09b8830766990114beaab5e27edb02d535f800d9c1e1ee8755787e4cfcc1fcb8e32f90aac5979f6f5cc824bcc409bc2ecf50886aa750a	1652530549000000	1653135349000000	1716207349000000	1810815349000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
289	\\xc94ea0cc7d73b9034ae6577fd53c812f48b77b1712d5522c5f83065aaa2de9eb0c9affc4d2e26016f4c5379420575fb60cf573a791e0b642a11e40a4d615b9d7	1	0	\\x000000010000000000800003a61cafe656f72712f968ce9c08f865b182833d6ccc9757a903d92e208ba89c0f14271e2b5d6f90dc24040f775d427f6f9e24d4a76e35e2bf233e2b8fc1628d37f2387f36f1e724d86db0150f729489943b0fd2f285e2cf4845a0dc1fa8df7e830e8873f3b42fd616dd12f79de2149e4ca609c85d38ff77b4194a3f6d099f387f010001	\\x0e90373b2dc63c0970143b1e7e94f2faac1171015a65811bc862d26a2fdba8925440e5964767936611ff63a93193cbde114a431b6d2545788d98c6ccec3a4b04	1674897049000000	1675501849000000	1738573849000000	1833181849000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
290	\\xcb26a26149d011a95fccf163230d114dbb466e5c9eab2705bedccb09abf6bb82341f9eedde9c03827feca73e119e14d4610345bd534ab65273343ab5ca96262b	1	0	\\x000000010000000000800003ccc2c9e0a7a39350bdad7b9d04e2759538b5bcde91b65b488046d4f502c667f0494bef28e0f432d24daddbdcb4a53379f4a32f290aab404cae236798713dc7529172431cf1ca285a450b5cdefeaa37e11bd89f2050106e4694683739b11ad3d280a5cf007be21e5eb1ea5a88a8945c9238d9289707436c72202a22434fddf8ad010001	\\x3d22ee15bf5ac44b8c94ab7565f216a90051b31924cdf802138efaad9a3476a5e71068e366e77231b070cc0de340a4db1bcecd46130b27340e0620419cbb8b03	1674292549000000	1674897349000000	1737969349000000	1832577349000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
291	\\xce96dd374fef019eee37f6dd38f8cf6366ce20b7dddb560ea333af49b67857fa36f9889d1e97dedc3d8d1d69827e65417dbaa7e73cc75814fda0f30a3a4e53b0	1	0	\\x000000010000000000800003d1b5ae1b170a143db00a792bae154f37e3ccde746f5423c834840b182f213e7f81d858766b7412175e6bb93303b7d024bdc6444a5d4fff9a64832eec702af744d1f8193ebe2d773392058904d3f05e840b4772f228f522e851f79c17734e2dcb421a5286ad4858c83389d755983a5a7eb8e037be1d4967c09fff62f16431b58f010001	\\xf25201822df4f2b3db262648c4f65413fa3206c9a6bf410bf53716b987fc9120cdaea3c962274db80cae1f7f8cad776025fa8b2ebe5e29f15c110f906d9ab80c	1647694549000000	1648299349000000	1711371349000000	1805979349000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
292	\\xd062877aad88642b5cb86bc9e8b48a873e2e9690ba896d703a2174610fb2c0f80b82073873618ae9b368ee14f4d60d394e109f16648a1bbc643dc8bd7a151068	1	0	\\x000000010000000000800003c1a15d387ddf60817896f89e4d35ca5adb52f0fc7b1daddbfe38faee2e5cda4a0453957675d705f9f99c1aa9c7cf4f8cc20dd975db6e4752f40cf69d6c24452495d4892ef30a5137fb591ba5d89c843e6464e1ae01454d48a04aa6c0f0e46dad04577012bc5178a32142043e9941a2c9bedf2277041da5bcb92044b77eb83425010001	\\x43a6c56eab0249e5a6faa1dc3b149c57a0fa2e8b17d5a8915e1a1df7f7f79cd41578222fecb68e2b1a588a0afa0e5fb9252187683881bd7f4add87011041b102	1662202549000000	1662807349000000	1725879349000000	1820487349000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
293	\\xd0e2347f0b522efb070443f0e93f6a67ded854fe3ce2e8a3d8d6c3b3d24f6e8093644881d075b310118dc9a6507f203d9910aeb31b95101762e65af7fed69989	1	0	\\x000000010000000000800003f059e7c001c5e5e43eee8d14f899fb5f7063b0b039f08ddb97cbcb58d0ae563280e19d542c42021e42bf8db3096d381a8fba4c80c65aaf651376771c289a5e694b750830262f30e89bf1848da78adc0de05eca8af70e8165dca6e175841752bb46154e11c2b2ce66a8ab66cd287125eb002d8bef9eb6cbae4c6dc93bf7521bc5010001	\\xa6a6865416f795dfa4d7de9466b987e6a141958c1577fb8beb984b5601702bd2dd8176da80894ef67a09e303e4479463b9479f6621c2121509288a0a45b86204	1674897049000000	1675501849000000	1738573849000000	1833181849000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
294	\\xd362393a469de04b1af58fa91f88208cc02f8e0f6f6e272bb9f582ba5b46fca5b0623e93d5d696efb6df866812b951bae2fa035c4ba4a282601191f2fa456bf9	1	0	\\x000000010000000000800003f908245795539c9a4367d6608cecfa9de0f3ca24cdcac3ea298f62301126b8b82d59d05e6f7c282ef066e205f004b1bde64448b281429bd01d394e45729e422723b9585ad9075d0a25f05616bbf5c4a48b3479020b872a59ae62ca7ace8997d9445b29423a3e508900103692009254b8e5df890cd2beb5300ecefb53ee0b5deb010001	\\xcab3b11fb07965eda926e9bac64c1e61b09437752d09bd98b62eb69bc16dedbd01aa6a9906a597b6ad45c38ef24387c5647488a9019cdde5eee047dcf4154e0a	1648299049000000	1648903849000000	1711975849000000	1806583849000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
295	\\xd5062c379201861a9cfced16c446b54a9846d81805d2eb2c981d97ae068ea4c3ad537608c92b2450e7099a0f511f3bf97012fc02c45d975e586e66f23878410c	1	0	\\x000000010000000000800003bf89336f09e5e4a4b1dc281a1c03b2c89ce5474d0a6b5bf1aadad32828e58e1fa3e01111db40a9b87d1d823f8998fb26f9b493738147ccdc553e3d9017d4c1acd90b43926f1341fe74b9eaab51e3906e045145497473cf16b428aea5dadc381ecb9ca34914b9e755d31a1d521a03206e38b8819fff42ceb074fe06ace7e29e73010001	\\xa25c5ede2be885c5a2914045e99a3d36d61dfc29985977aac920b0982893c1a71c1ea11d8b41971bbcd2aea80abb90b168cee16b5ec3708f72877821b7b20f0b	1653739549000000	1654344349000000	1717416349000000	1812024349000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
296	\\xdb2a23ae1c26857a6fa8457d4ac8333461305411ab303d9b65c205bb2529428468b5edbfe3d42eb7944bdd326dd7540f808c48ef2133870e60a52576e84047bd	1	0	\\x000000010000000000800003d390bd3b30427348b6530af8459205d6bb5a4eab633132891f3d2a5084b0991a24a3bfbd5b18dff4a57db7aa9677c92ca5d8b8e53e7ebd34ed5a4ca8a3056d710c9131dd19c59c7fe5d5ebccb7024bc2c0c836be5008e669131a71a6b490a944091f53f39cdcacf62457131ee2333c244828f59d99e34cdce1a61d0b6f5c5dc9010001	\\x201c549188487f25f7bd19ddecdde8752faecdc8785b8a8a273292ffd4c7bc043c06bc1edf3f4703b16f5e4a61b7c1c73df1f769d116ffe2ea35f73057cbb10a	1654344049000000	1654948849000000	1718020849000000	1812628849000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
297	\\xe6c295c6b90e1f8c5945bb2776ad558bc3d2af05ae7db4c927c0e82f9206e67323f384953e4f57b65145d3afd426ca36928e46f874ef02986f8e42ac5bd6d46e	1	0	\\x000000010000000000800003aa8f395f11cc13e7a829f47d8cb93efaca67e008439636b9434d64269a5013f0aa6ed61aa14094b273981d0b8c26523f9355fef5eeca09143c2f2a5fe6faf2c1a6efe4bbbc12abb4762debaa37b23b4b04a64d886006a0d69c65af8d04eddacda359240e42c677b147c9a9327f2b85df6ea110f669b78f8311b1aecdcbed1987010001	\\x779c2f44751054a2abb3230dfb3ccece0d0e59e5b6e5f31e871b6e5bf0d56aa11f90e867de57cf717d3f1482b8ad6c2c81b562a294e4ea9b4749e310034f630d	1653739549000000	1654344349000000	1717416349000000	1812024349000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
298	\\xee5621c3da70169a5523b7f0b2691d82c21391c4627640f2e575ca05a91bca127ddac3f06c038213698ded4e348bc819359d773925e01033f9075c098eb4c9b0	1	0	\\x000000010000000000800003ab81431367af61255f2140cd64ef725b83c1eed38df0d5422c2b84924d41123edec5aef5614e011e51b5666eb649a0382aa614a6b13732deb67d42a1b0605f2cf459f76d165f12f1600ea073e3e907e69dcaaf4a4e432e0e8eae7f23bdfe41eef4f3efe0147977e34ae7bab4068026e945c192c167b35e879ad8b843f76ec261010001	\\x07c24d06d8ac7b108e5bb1bb3409fc2df2e1ce08f7e724ffe4b45d51127c49e5c9cfca7c89228677fec827d952da6d74f671c938086bb5cbae55d8071ba9030c	1671270049000000	1671874849000000	1734946849000000	1829554849000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
299	\\xf06a12f9d4a2a9ebb093c8864a599df9fc3b7402bf41f07068fc49a7aab1141ceb945da085fae2b873eba5ecbf0a41c31dfd71a86c1ac5df415236b74cb5da1f	1	0	\\x000000010000000000800003d6dc123f542e81171c4cbb1d40cbc3fe85a970176689b2ddd44da35fb5350c8c664da0f05e0228464708c0e8400a743ce63e740b172f52e1f45f9fffb33768bd147262f7f5db0d1e1a1240f93d757a51a9f768d57afef2a91f278edd3658bff67a22c4961803a569e65b426a4d14f0a4dd9659f4c73c71304d47f575e38628c5010001	\\x7a820991c8330a010775efb6ac806bf5cefe918a7161630bb09470e319895a29dcf74940fedb05c5980949ead2932ed1b5d80ceecde0d647a7ca9b6f5f9a4705	1672479049000000	1673083849000000	1736155849000000	1830763849000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
300	\\xf01a83a682fa9927d84d58bc7973fdd6c62bf4f701f84cbd10994599766868334bef3b42ca21e63122a78f964398a67524d32e218f6b9a10ee1e7ee4f6d0ae16	1	0	\\x000000010000000000800003df7868c247e47d6f7e21426337d880b2d521d82b7bc1cd0332469f5313d1fd09f1dddb94f8122098d8eebf67864acf3897220825a97c2036d83ddf8aaed9d29082df4f1c55ea5984df1d55b8a7d51847bdec0518b11993ec39c674c5563a898cd4e1fd84935cbb505e81af240e4417f3ec8af4d4b1f5a75f54a4c668dc918d25010001	\\xcb2c82fb8593e35ee41f03c8fb4c3b0391eeceadfb3d93ce207a03e314b29b2b67b0b53f33b318ef9fc75e0e19a0daffc7dea62dc5c6bbf71b41abc74fb0dc01	1651321549000000	1651926349000000	1714998349000000	1809606349000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
301	\\xf26a8db65f623f0f12942eb2e7477a4cc9e30707ac1ba14b28a0b632414206a06d4e66001ef227b6caf34ea0fa6a150fffc2d5c5bf73200c607a2992d94c9344	1	0	\\x000000010000000000800003b90c3033a555ef32f1c3df6e4b2004d300d1d297a4cc9e09ebce598a03abda145a88552b38e40ad8033623c1e06017cccad16a67e9a893c545d6a49ec533bb9e39e6bea941dbbc63a4b231639813fd7495edd0b79d6955f80c6787e78a7feb998dc86051d6ac9a7f8e845c9a6f62b786d05ce84bb1a734802d9615abf0c182bd010001	\\x97ca7f8fff7349c0993ceb6a13a5482534ebcefddc28d129e52aab9e1eaf51803a20b1e4f547e09b4e5481338a1d5928d9a4be13bd3981652f00a8c485c9ee06	1665225049000000	1665829849000000	1728901849000000	1823509849000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
302	\\xf4caa093f1c1be4c1e7c2f07eeb64532743aa20a056a2c8405f7a8ddb863df94b13fc99cfb2e14e3284dac9c63f44872840d3fddc82d5d655cf04136fa3ea871	1	0	\\x000000010000000000800003cd81743bdf125560540dbc3ebcf7fdc5e1bd0e9677778924697b032ac66dee2eb16b7f7df2a033dd59d3b30f0d2204e8a5e9b04aa5d6955ec1fd2cc1d251f7927d87a6083ad6a0da9299f5c119976931b15e356e3acb3d4aadde830d53159afc14c351fa0ae0c6b4610ca1fd800d73d75d2f7e30d7973bf3eca6a9825b953731010001	\\xdfe46c65432ee7119863b447170d4371edc20b6c9507550b2e2db5ce85f6ed61e99d4bb03d88f622b50fd9e4c407f12a55883b8f5c51c8f46032f8d3c0398209	1674897049000000	1675501849000000	1738573849000000	1833181849000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
303	\\xf5f69bb04f971c1243c58fed54df1736aac3897873b46268ff9203dfc42da6618a2be6ed668e2a53ee0820fcd774b66870a38996f7d15e62c181d58a99eff17f	1	0	\\x000000010000000000800003a5f326f669ec029c7c713ef3e07b1d757acbc4d710b2466f8a01fda54b20289061d7517bcf8d603ba664a52df21a97afe9ee2bd9c2e00b95fe889dba750815115e06ed75fed0b2dfffde243c3542b602a7f4cfaf8f17564dd66ab3997752dd43f08716531210aa4df8dfb8b332a5675bd3d53d9929862009b0bfe8e15f619131010001	\\x450adf2440aeff47bc5763d5d765843ea730d36f027d7bf88a615a00bd4c207a0410b22b260de250047c92878325ef3f0340afc8e6355183dbfc19baa540b205	1673083549000000	1673688349000000	1736760349000000	1831368349000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
304	\\xf5d6bda964d2f3605a6a83a2e91c47c8e1f08a14d1016dd9b2ee94411c81ff967f00c98aa3905a05078750c0bac19b3ee57813e60679a96d1dead78b57dd5202	1	0	\\x000000010000000000800003ae89a638293794b0b1a541df9d35f4c830419c100e12b61265a7ce6ce913a6f1096204629aee0b780c24c7ded2a3e87696d59b5eea4e28b5d0eacf7b6c1abcfbdc1a4eb26f34e733452c48484de212b319a630dcebdc3491d74e279bf4e00938043d8cdf91a943f013bf3666f5f5151bc1cc178de4f3198dcd8fce71a73c11b7010001	\\x55fc259dd7e9a6a874319a610d348998b945c01700c389c7d215e49db9088c96da5e1c3feffb28ad286af448366cbb784f4122c8ff5fd7d9cda77b42e7b58404	1653135049000000	1653739849000000	1716811849000000	1811419849000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
305	\\xf63e94c75e42d3926d9ecdbde3d6f95f18669eeec05a5a0c517e959e49bba72719c52058356ef60a5eb873ee07efe9ec57f59594b5b6f119497425676b9827cb	1	0	\\x000000010000000000800003ea6c3e2c96d0aa08506614fa93fd3b978112cc892569ab8ff52371d55912a7a2e751f2d8f7cec61f3232696171adf31068228ac0c9aace1c5ae1fe7ee3a201255dd3850af830c7e195d8ad7ecd58da024dcaeef0c96ee3c2763b5a1e2a391a358b743a64ef536481d47e027ee0253a315fdaf0e5ab446874dc3945d73d1627b9010001	\\x2ace5a2f514ef515e0f2336c6b4b48cce28476ee02ef42f95578e479af4db90be2aa98a3dd055bdb027eaf3cb0e0d87dd4a0bc6ef59428efb46d1d7b18665c06	1677919549000000	1678524349000000	1741596349000000	1836204349000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
306	\\xf9a65185f9b07c6094a73965a2dc6fbdc6b2536630ceb2531dc247b6d4b118c91e31254c6e1420c343c34107d9e1164658cf59b6dd3cf405b8e45976d54ba3f9	1	0	\\x000000010000000000800003b1cc07b208bb29ab72ee2743af1037448aacf0e981020bcd2c6ced2c97bb78da816be3f79aa5c8c5bc5bd5c1e7ef748dec0080a16abeb889fa112019a4f9797868ca02ea8319c10a89c3e61e3ad3fa40fe744307496c146a4c26953aae4de175feb34b795228dea65766a1efffefcfac9a6a26ef754f863d34e527d6b8c352b9010001	\\x4b3c3bd9f21cbb4bafdefa0b1f91ca6b24f8bebdaaa09b8ab634d0677e512515cd4f5cbfe06e381ee74d02aa7230a9115ded17bc39459f7a84e6ee8c2050610f	1674292549000000	1674897349000000	1737969349000000	1832577349000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
307	\\xf96efad761495e57965c0b8523440023670b639f43d085ae57de4362e2af42df2b3f14ddbc9c1edafd3b3a40345a196ff8d60a78c5dd1c69f4e8f5f4cc8658eb	1	0	\\x000000010000000000800003c3ba89a1ce0e84662b27813353df64dc58cdfd77735c15bc0ea71b3b79a807b1111e0eb4cad707aac2d6575d0dad0eb7faa84d853e9e988501139d7b23d8465f1dd683c387a3cae20d7ac93c851d8f68f330fe2cbc3a66e0ad94fabb5426221d4bdcdccd6050408857d7cfc181db8f8b45ce8d05906169a5653079890370cca9010001	\\x48c592a6bdffb817b576c2d56d18712a94b36df3115cb5aece5fff525109a266ced4e56256e51620d1146225fda598d6027278df4741a2da2b675b54c6fa1903	1660389049000000	1660993849000000	1724065849000000	1818673849000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
308	\\xfa6e43a8e96dd9afbef9eaa8c5927e0d592b81abc662ebaeacde896976702bae441dbf2e88cc6b52997e25267a2ab40285146a723975bc2aeba0fa40b1e55faa	1	0	\\x000000010000000000800003c94e154516e19fc8a7423880c905a73c798fca3df057fd3d00fc98f5a79e12a1d1c6051de290c3758edc69082d85321999c580db2df6fe279ca0db38b7dde9ba3fb9a426dc62cc013fb755cdea0158bf48a9d0e970347a3c87197a0167fe99afd84aad6b43540a423fb04c0ce6ad8b633248482d6906c8d27ee30a4d6c2779c3010001	\\x69173c8c8f951909b2081ff94b027b7cc218c9f3541bcfb94b9d82b9c24775d53e7e60403c89dedca4feaa3142b32315e087cfdcbd7c31e13a5490af76007f00	1651321549000000	1651926349000000	1714998349000000	1809606349000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
309	\\xfd7ea73ce2da8bdc13e2beffe2737efe6dc12f020a6367a13c48d587778ea777cb23c6925418e57cba54489cd0df0d507a97d7fefd8cf678ab3df36ee9d726cc	1	0	\\x000000010000000000800003bfd7f4b63713a2498e051b4f9b8ea09173fd0330eae60898bba5d6e73f19171f990af29763a551a3b27eb82d55a14592062d6d8746af5959a657594389a8dcf02ba4316017ef19d46d39c4f464e88f29ede26edf4cdb03b720f59b51522c0d307996957866246d405ea97a6a58a4d879bf44a7039a89b8a14bd527a7e52a6f11010001	\\x55d573bc094e1d4e74c208a938d96a19da9eb7ba90143e87c448677475bceffb7c5ca3e0f59a0a7cbf45c68402354411d1bc121e89d92ca3bbc33ea31883f708	1664016049000000	1664620849000000	1727692849000000	1822300849000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
310	\\xfd921f68135ce76b3eace4dad0e709b498e305c972c1d610a3836250b72e6dcf8b68293c3c9c4908828be17df934c258bc19b613685c8b56d044e4da2f96d6d2	1	0	\\x000000010000000000800003ae0a40e8bdf29bcd25acaea7925ab705e9c1818f07d39c0eec175e6845afca139797dc6c3d7f96f0ca88574f616ad32790fd282804fab1fe810856b5dcdd60645987405c2affd0d43662b722f74ef499ffda6369ef53e637fc4e5f2a4755156ffe64eaec889f75f857cf5827fab424e47b454ec9b7d7c14db5ea9e12d170f81f010001	\\x2eb74ae2b1145b73997b074f97127117b2901f861606f5260b6fb2405c7930273b60697f993e0e20c0aa2af6469be96fe659b7c07cec8609228245bc9472690c	1659180049000000	1659784849000000	1722856849000000	1817464849000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
311	\\xff9e53c933cc92a587ef81b92cc935ca10e1946be94ea0af47927391c2e444245fdb87ede535e2b141b6c7858bb6fcdd2fcc6f1e66204181498770b56ab0640e	1	0	\\x000000010000000000800003d095da06c05b564d9385426c78d14740193247b59c8762f65ea3eb53b29828df98baed8dcb90e32af46f9c630f4b3c3ccbfd2bb70caf436d411a023f3a9f5709b4b75a1811c8299912466d4c1e275f2c2ea592d235f3ca6b38dbb1017e58f8633593b0e04c819b16e7d3a8e1ad1be91435cab9b5d09fefefcdf80bc27dead91f010001	\\x2cbadde9571acbc9244ec2831504a027e661513c520d988f384f8cc079e201949bc6eceb345c8abe6b73cad1ff58d35153b753730307af60ac429b7c2c549e08	1675501549000000	1676106349000000	1739178349000000	1833786349000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
312	\\xffb21338ae5ff1f8532d214c2a725881f7854bf83dbe9f6a8332b4c72cd73558e2bce516ea0320565327cfbd11e57d7e8f7531e6e2db53b132dccc306baf7d42	1	0	\\x000000010000000000800003d3922a88e2ab51a9989d05eff3d34f629ad52cab70a96f757931522101f7d2bb4abc3101e8ca257e3c4bbdb5e2031a610ef39fe9c7e7ae5825b6e2c23009fda1431df76c8c2cf78854aa4be4b1d12929089797ba276deded592d74270613a28d3c24571b0172c4f174d3fe2addcfb7658e7098a286c2d08b5640e81bae1d3acd010001	\\x4d1abf39c0c06f2bd99cdcfc7f9780e8f5810e6f7696b247a871cfb1b208929a2b61cbcad073c28ba646b6b1a5da7c480c0d6cb6fbc498bc1a35ee4a4ca1a903	1648299049000000	1648903849000000	1711975849000000	1806583849000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
313	\\x010b3eaa326741e931de941d41b0b0f40d07a51918469d0293fd7d3f0e9dfd6a2c2c156a494f449d50f65fde1e12c0e9c5c6b323531cd0c5e5a5c8a81db1a4cf	1	0	\\x000000010000000000800003ea19dad907b8b47c16173c93ba5575ed4fc1b5c91dffd1a15891cdf4b584d388b24729e9607626bdf5356abe251d360b2fbefb5fa33536eeff878acae60fbd0b94b7e5916e7ea06376090e640fd03e65073c56ccf843150caeae9cc167129f1c6eea8d70bcd2e7ba0bc5e7517fc0782b31960ff6677f10d355c5487075e16533010001	\\x5691db568f8a5a49f4f54b8a334cc27be22022c53ac1eb61712fca644e87b6e8ae56e9300475abf7fe3882438458b8c9bdcac7c349705051e8a58308d2161b08	1665829549000000	1666434349000000	1729506349000000	1824114349000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
314	\\x028b25eeae4d1f4c78162d3922aeb79d91c63db02199b4b62c2986cc1e710b223dc273d7a19056aa288721528c86547f5fc3fed3fcf1bea640522c84764510a6	1	0	\\x000000010000000000800003cc16580cf805e4c23174ffee59cd9ef553c14263f68b9bff5bc30de9a59c336bd78c54383893014f6a64283793ded0413c5be22c80deec3275dfabd1bc9cc1eb0dbb111402745b649e15617f8258712cc050834dedceb046be24c3e529f40fb5861bab12df0b7f045572fac1f2c74379ae7237dba846958d92cc1294909b4b7d010001	\\xdd694ebed9633ce17118d6f8bfce06cadfa6abbfcd0494dc39d3d79a27d9758e944ab4eb6f85bb63f872eec8f55f95a98499683d5a9c1aa17bc630a822bbc10a	1661598049000000	1662202849000000	1725274849000000	1819882849000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
315	\\x08b78c8d800821ba21e409eb995cbb05bb769a58c2021ec1918857634dc468f76e11a294f31e3fbc14f11f580440ac0c3d826e2569b169ffa8e188e6372bfd0c	1	0	\\x000000010000000000800003ee150ab14b6ac4e6619b135bc24d642086b9faa8359f6d9cccc4a726ae7c571f35f44ab886000fe0b75a08c51f6e703b44437ebd72e7b3ce96e221feb9402daa33c48618f37a749c4c88f491b833c330a58334d4beed1af4b7ccee3db54a3ddc82855aa2d1ea8e1f95777f4a4cc083cc5fdd428721a8ee1ec94d361d3f603d69010001	\\x21043acf4b86fafd42e7ebe059f0cf02b92b6b6f88c9e8a84ab522bbbc42b7943713c1dac7e9b0eab039254be5048ef1e81d6f455671554cc147f4252641a408	1668247549000000	1668852349000000	1731924349000000	1826532349000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
316	\\x082f9857c53d9c028099ec62703200a3f2f73e8bc16ac9fe108b416a9edce69b2e53528dc834363c532c8fd9ae2f9f93eb9382afd0fa0379c50a12dd8875cd4f	1	0	\\x000000010000000000800003b5baee49a09922220cf3796154ebf6f6910fd121ea4ae0e41ed4f36535a76d11b714eacf9aaa11fc398bc32ccdcbb4f2497d0f69fad5e164df94431fa56084e4e1bd876663e3a3acfa3e38b61026620925d6123a6b7b9957d1b212a6d50bde65ae22f86eef64c57470b6a81cd702d21a7077e66167d7d120edad96cbd463d9fb010001	\\x5ad2cf983bc6b14b283a7681d1c48f98bb6bd1a22ec403e6054c902b25100723e0c74743cd8c9e3aa077629b10cd48b066d0b9cee132a760eeb7f16424668205	1665829549000000	1666434349000000	1729506349000000	1824114349000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
317	\\x084fa644f0c74afded11172bae71f10d1aeeba4184608860aab464767f4b1c98c8ea64d070fbc97e17c7cdd93b7c827a7e6f9ff3ff60a946128569271c015b30	1	0	\\x000000010000000000800003d1d979bd4b30e66c17b64b16923df3ad53071e9f9ef3e3a66af56bc7afc2acb8abe94687440c62882ebaf48057705d2aa72f16e66ea3fd1346bff73f585f33277ee6b67cc6c33064d61d747cebc8ab23e854b39b0ae115fa5a70cf931db4c4c20e42761043c7f0eabd38731318300956b804536fab50861166ed66d86bfff52b010001	\\xf04c1c10768f93e257145e3389597e4f16af59c04c8d9f563f3b80976c0d7000bfae1829b9bb2e9784beadf10b271ca5b5ee78d4b5b7ae1c529288f92d52cd06	1668247549000000	1668852349000000	1731924349000000	1826532349000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
318	\\x0ce3ff9ed25f9a4367e8534bf9e8d714a8438d990b573f3922c5d6dc5b71ca9f9cc51f4a970d6bbaba876d854f56305ff9686c020db0d1afe4dc3d559d5ad561	1	0	\\x000000010000000000800003d6d8114739561e17233cc25253c49cb501ea5e4edd7c5870cf2761b60fda88cf13fc8dff50a7b69351df1f0ad77fd547d61811ddda8d5ebc05e6481ed05479c8096072fb9682c6e939ec5d36f8efa2d79611362687a1c1db33c513f115430364788a398f3352c739b28f48099bf46a804485a3dad863ef88ace59a5960190a1b010001	\\xfd0ba0b086286d00a41ad646c7765453906cadb2b297b679df647c4853e3205f4c9573510763f25c73ac28cebb186f858748b52282035d85764004f421159506	1674897049000000	1675501849000000	1738573849000000	1833181849000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
319	\\x0eeb99ee84cd593419c9ebf7a90ed26d81a72be181dbe8749be7d55b290e09e7af77d5b6a2469e7d17fc62d61ebb7726b86dffe7316e34de6ed69e5bdeb3eb70	1	0	\\x000000010000000000800003cbe81e9fe5e02ecb83c8fd69a5158030a7182079ee5356871b7c83e790e6275c896566a9671d4171c491839dd8e7eef17a89cbf9543ccaa408794f7b53bac77ab47745c05b6ff2be8c9468e31b8c13ff7b05e6b60b4d9ffdb096b536f9e484f02e07cc703ce5a066a221fcdc2eaefcd8296fef7e089174f1867e0b3473e67de7010001	\\x1fc81c320f1c124cd65f2b22e20d6d12e7b1cb1f47e4b6cbd619203c387c719eeef1511b1e5e983ea3c0abaed1f3092504ede42884b383fc444b49ba4a730809	1673688049000000	1674292849000000	1737364849000000	1831972849000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
320	\\x124bc3c094b20cf40efc44bbc862edfc618875384d41e6db70ea750b3b768de5fc4e46ef4187e366980598432cc7cb87a6c2f26b86fb814821631aaca997cc2a	1	0	\\x000000010000000000800003a4ef0aa15f283fa00d76fe24c957af52b70f6c4d6c25af3844c6c19f1a123b2cee83d0fce6f48ae6f7eca2f53a7e06cce3f278fea23345c8a1b4dcb2193ae3f348c779649afb15fc863eca6df3a8aa4f5fce9aba5e32728edd34ceeab819d8bfda61a1b3252a4cbf2d0837bc2be3038ff69ddf1d987db3e06eb769760c61a14f010001	\\x1d7659f81aa2402198a8ed2af614cd7ef2f067aa5730563ff86b8b8f6534e39f1cc32a3b94f56d2cfd5bf5cfe10761ab551c072390b774730b7226e3fcad310d	1674292549000000	1674897349000000	1737969349000000	1832577349000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
321	\\x168b4450a98c4d6ae873593491160e5a95174974167fd6f98e865661a84fe2c4f5ca0daa39504a08eafc811cc4929b611226a70491b79466cdc62aded14c8d98	1	0	\\x000000010000000000800003a0816c5539b9e22127d99b492d633e18d32f6fecc92d2ee919d5e0cc33a7692c1cb61f54e3b9a345f08812929a0a2ef66eaad23867bbb877b7fdfd8de2aafdc19b9d0be198254eeaf5d4d877155bb1e3397972c08d29c7729b87070e63db1ddc65d19764a22de638c9f726737a0bcdd04d16b5779bf5f1b221ea4524db12bae3010001	\\x14b6a94f64f9238268a6fc1fa9a5331cab7f1ae94f32aee8eed04b842a2ce558504dc8ec0edf6ae77fc31783058b282161039e70411a9e462dbc6c62fba30f08	1660993549000000	1661598349000000	1724670349000000	1819278349000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
322	\\x17271051bc43db783f3925bab1e773664fe53c61628aea708efcc86d2d7d09762e8ae69bf6d7a2ee472daf2080db78a6a90c6ec534f4e22e57e6bb3bbc7dda40	1	0	\\x000000010000000000800003e358bed5ef21044bf21f617e470ee926baba23b7205525b27f12406318ce70fb087d3ebf12de316c9ce214118e2ad21731395376cb63e988221897fc1deb0ff43f75551e6890843db14f252ec7e90a2d522a5db6d2e5e1169ffd0ed65eba649414b4235fb1dcf4a978bff9433834747f3711e98b59f2c13379051d2a9cfb37e9010001	\\x000741f0ca18d70edbeac43baea36b81667b981366356802a79ef0d96222ad45ef638eb57506474ac3626d3bf48aaf3beb4105cb0ba9984b16d4a3533ba55703	1648299049000000	1648903849000000	1711975849000000	1806583849000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
323	\\x1d07a6523c5b1646b2cfb8ff3bb230e42c517b6ffcc0a51f30199503dba2e5818aa2f70bf201792ca1d0ecaaa877f77a24da59a4d0702e68946fc24c4120bd1b	1	0	\\x000000010000000000800003b2bdf7e98b4ba2173dbf93ff8c181cbf8136a347ce4807bf24ef3cabd5dd91191115c3f5318720a43bd05640e3ee0f49b0e2e0c7d20fc6cb226bb6d0fd4de3fe03781c34abb72dc3e6e09be0915edb04b673b9163e6deedab71dd1bcb9dc1017311cdd71b33d62c0acc322da3461d317747a56b129b25eb6a25731906f123d57010001	\\x358e4986443ad23c919efec5b0154776a7122cf54c4eb93e97e779d98210d364312039b964a30d279f43d58fc2fa918e4ee19136900818d0ed25a85dcea42e06	1650112549000000	1650717349000000	1713789349000000	1808397349000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
324	\\x22dbe4d2df72bdb288baed49a278926807869158862ee8de42eecb8e16bc7e92cdc93280c436aa054d61d7b04c4645b3faf9519b1925c78bacbd812320e5efbb	1	0	\\x000000010000000000800003b41ab5d7e0577defe7821ab292b269e1af5c515f49aa6ab450baabebd43ac9010218e8f5458a1c6c2fa3c4256b01d20a5c5708ef71a01fad7b2cbaca2cca86d86c330f753ba2422b0baa575a90b423b50ec253109471752b81904aeda72505f380f0f751f13c38a9eb20afafb93b9c60103cb8b6d8a6715b9fc2a1bda2b79cd7010001	\\xc21a25045bf849829cdfa06a26e9ec1e136278983cf371746e299333a85512e17ad505daad265d6bdd6ca64837de17386335ef38c438e04471c2222b8a0b540f	1653739549000000	1654344349000000	1717416349000000	1812024349000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
325	\\x2317e96f37737b33adfaeb81dca2682c4b03f07c046caad888e51951841a59239799b6dfb9225680ad501b2c8bf99ed9f6705e43dc71a1dd2a7e2391cc8b5301	1	0	\\x000000010000000000800003c31f980933d9b12ebbda2c9fda52ec99bcaad9fddd0deee184d3501b320c0fab91a50f1dd48e808124827f6181bf360370405226f113ff3b3f8f40087049dd3ec12b539271247f72b67ecdf2f2babd7c591b2e993ec64c219a56f50e8569c581950f4bffa28db6957d81b1c642366750280a7005953abde7dcbcdf91b26cd191010001	\\x951d558a0ab99e27930b5c2b8959f1655319dcc6c357c9cef64e311d826fabc33ed8c38017ad4f27816888642254911fe949e7ce5e2fd0e91c449685f1b0010a	1673688049000000	1674292849000000	1737364849000000	1831972849000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
326	\\x2bef786f864d95daa4fae3f0e1f00847664a7a1e3444ba222d76a28032969ead882a0bd29cf2e983e76adb250505c671dcdebee2944d531780870c93ed8d5e02	1	0	\\x000000010000000000800003ae1f3274c43ab65b3c3d9974dfb05797f632002f83adedd7f2e663396e0ea661e3225891c2595b207b41ae66fc2b8003e82de5f693f25006b261a0402f0fce2c130a98052dc885e47140532fa2537b527b10e3898f8ff9bbc8558eb7e95544b4248bd8a397bf21ff361e0e83da9ebfa5ad9a8d885af142076a41f74c350c3555010001	\\x52206601b6573d2981f0f96569219d0fec4e97cf1de2d6496d7445c3e0869eae0c97502d891a35e839fa15edba7ab1f14a2d1796fc9bb65545357f59c5ef8500	1678524049000000	1679128849000000	1742200849000000	1836808849000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
327	\\x2c03faca848b70e384d14a769f0a808dcc482d13c4549fdead7a5a165918dad995aa5d8d3b7d69e9c5670633c18e6c146a9a4b40fcf480245abd56a052233bc7	1	0	\\x000000010000000000800003d3314537da1ba45ff0d7d902a617e96f514a8e9091bc769e34d2b0af8ffcdcc168dce9098ce90c2cdd9ac6c4e95ebcc983b48537be345ee83ac2871fe6343d41ed80a68739a5fc9d32531f4cf4aab9e006b3e4ec734d0ffec3ad192ae518cf000cb0e6200538b1c80d060c7d09ef91d40b90872d90cee009940e5a12d4f0ea6b010001	\\xedc57980f1a43cd4d7ad6877edeccce24bc1b6d0b63d06f390ce2f5badc4c7327391234f3c976c86d2373e2d440255a8171da9f0075fd41213a91d9051858d0d	1656157549000000	1656762349000000	1719834349000000	1814442349000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
328	\\x2d4700075f57d03583b26c19d9e340c4251a1cc849230abfd13340e605e6fd2e6248af2161ab0da1ab4c1d8a2c8035c20400a0f7bd5aed3e67ceba09dbb7fc04	1	0	\\x000000010000000000800003cfee7fe3ba477412372c97da4df24b9f9e62bd189b5ee9f5db14d169283b2a9b3a8c1c6fe6b09f179a45da8999b84c38bf65f745e3ecb30f089df96065738495268a5f2fee61c8dea5fef2ec3644f3bf76032577403024e1dcf3d307063d58d0a3c65860c60eba604422f809104e3195d5dae0087e56d8854672d4fe8b240d81010001	\\x79986b78566d27d023e969f92d102558135597a0049cba817c5b4fb1601ef2b1f06bff710e021b046b84e1b98e8b177964d10342d80a0ce70986a336de42b103	1665225049000000	1665829849000000	1728901849000000	1823509849000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
329	\\x2eaf754ea6178fec1ae9d4074517a012d1ede3c5df1c6307ecd5f751460c26752c7ec926aa3dc7780799b2fd9bd5e6881a09272d1ca0d228305dccf11ee62926	1	0	\\x000000010000000000800003a6de1e669dad7614cc8b8ec06669ea6f3e11b86594bd5f3365a2763231d8b11fae24d2cd37f3aa22db9c636d16c6ca45db1e6afeb1f90225113ef54d8c9c55c883cc055e67679aa401df30a179a385c844303afde619c7fce63d15b3753adc1a180e6415ed445799fe4b897ea0a6e04f4b5dbd74540daa874f1fc32312c2529d010001	\\x363647727002c7a02c7e650e3f445eabc2d1c0f177042f89259427f40449255a861388aee9d990931f135962edce55432ec6fc30f198825d023fc47476aad00c	1655553049000000	1656157849000000	1719229849000000	1813837849000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
330	\\x32976cf64d1991a254abd2e5fa684ec70f0e54e187c7ffe3a78c8fe99b9bdd24e2477feadc070453a82056e949a953de0c7007002d29bb81da1d2b6ed3dc12dc	1	0	\\x000000010000000000800003f2e46f5f159d6dc834e2150f7c93acbb7cf80f67496fde44bb3ed55f1cf0c05fe809e9fb9dfab992e725752368d5ac830a2c035cbce0825bfa510b552b783baa6cef51460d536109903ca5a45a81105618f748820b334f3e8c1167771daeec12f810fec5100c21dbca6954ac7d9911df46361aded55714bcdcb82318400c120d010001	\\xa788e58e0f0c6910d4b79f5f32a7b4e3d16b24fad8cc655cc6fa83f68e96a6ff968b5f5b9a76e68f793dd26a1705989511e84369844eaffd71970a29d05bd600	1657971049000000	1658575849000000	1721647849000000	1816255849000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
331	\\x33d7f24ca18267a518c25c886fb09a717f31930d17e63b400d2de375091da6e6c5c83651c5f849479fc1b0679abef4bde7fa84a3c8efa70780b594d06c5f1b01	1	0	\\x000000010000000000800003d9836dec8d200f9533794f1c1317dc2d2ca9b1b91f4d1eb70e7725565ba14843f561fdb944c5acc6e7a32439e0dc5a6d12e5daad34fdc85364aa15fe1c89d1fedb8ec4a009a8ff4657f02aff4edf13ec29cf53983ff660f4c67be9270935ea82e6ba4bd466916bc5005e42a72152694450caf181172f21713cb8502510313767010001	\\xe33d39dc35ee37fd85b98b7088930b743337b6fce5ac0bf88d03aaafe9bd31cc148658243b23b024359ef47db9eba939f2caf4138909d4d39e62feff1ada070f	1656762049000000	1657366849000000	1720438849000000	1815046849000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
332	\\x376b45586c4aec098dc1152dec48d8f6c9133383c2e40fc9320e4b9acc1e3da300c6c4dfbc4101c334f2920a07d722d9a6676da2c4767074ffd53a428d7a28c2	1	0	\\x0000000100000000008000039e14c7e347ebee5c4e164169849709a3cb62b5fe4c2acc6bf0c7756a0eb098872d6734304e96eb6bb026a9fb68338cf48245b8cc6afbdc003bf2a6ed0aa9eaff0a94d7442675701d4d3a4bd06a214355575d81a9dfbe378865ff01d0cc5c88fdcc3c0c4c1d49dd234ad1f40a3f009431ecb4664f8edb814c7eef1f7636fb4329010001	\\x35963f85318f5cf64f6858bc83d3243829cdcb2115257bd18f33d3c2cebac36f01bfee9bc499a9122ca5f0aece5d065aed4757cf7d4fb1cd5af30be4e13c0f0d	1664620549000000	1665225349000000	1728297349000000	1822905349000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
333	\\x3c179dd266202d113d38576fff94f5dd298f4e38a9b4d87ae083c5f86308cdc12e0975b885ed3bbd82de8a1d94ba2986e4e95cda5c13d6e45975c5363cd35bf1	1	0	\\x000000010000000000800003b40de80acb2cbe59f8e81b82a9ae4c11353947466f2ce7c949875639a25d93c23346279da9815c161ae5155a179613faf301673bfc64637a937e7eddd5b556aa39e07868ed9755fa54bfba88cf2953dfeafbd2b7c39f3f9ea196fafa4279ee5b3f86b31d9fa5e9ecd1dd32fc04abed6df244ec7598918901107838aa47244637010001	\\x23039e1ef7818ec21ee689776a2f5f4401b7f43d7c6f37b6c1c5ca372a8b5950b73f9e10866eb2b794480f022a927f321083c8bb96b572f0c8f914f87006190c	1665225049000000	1665829849000000	1728901849000000	1823509849000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
334	\\x3d972e4ea6e237c1a82b197ce8e93ad0585023b25d4c8a1555ec211d3757f50f2e3c830c575b7afaf5f15fa15f92403b0583dc04a1bbd302628d64edba3b9a68	1	0	\\x000000010000000000800003db2f4426991dba919fd01e2499c3dc9ad167bd8a2b3c0fa061037842cada7ae662e1cc2f7a6585d9d6ad3b62618a537ab4e7d2c0ef37dc97febcb8b90dfc7a03da4218fb6647d523b7ec278c93c040c3460c86278c16ed94287f77fd30bc234fa12ee6daa38ea4885a410331d22243ef9fbab2c9039d7e4c09e04ccf44a0351d010001	\\xc52c71f6c76fc501f201bb5dc8a89166956b6803c1306faeca247947d442d4e7941dcad24a03b431179d902c6393e7bac42f71c6336094968c96fc867c58c600	1650112549000000	1650717349000000	1713789349000000	1808397349000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
335	\\x453314ac09c3e38245ff0d1dcd532b68c708881207f6ac517110b1f5658465408f1a3de3aff67d89d547233e27417f5f401d8fbe58c55c6954d7d19a210c309f	1	0	\\x000000010000000000800003e4de738b8217676dcfba209929d733da4c146e492edf51ad9c18cfaa03dbcdf3efca6f0d631faebba9a39a7eb02701e635e62e96cbceceeef1b3623559653faf0c342b7f146a630aa2c618e7776820f9422c0af6357ce3cd29e0153b4b260ecbf9d4abe2fbb06a59cb60e6fedcca24a164a2db6e9242b35dd6296b0655ad51a9010001	\\x7a3b7bafd6007b552768da7347302bdcb8cb488cdbfcef29a247aa6b2bf946c97d64aef440246c7d95dd464d7a3a92f57af8c76be470b0a9416dae9cddedba0a	1678524049000000	1679128849000000	1742200849000000	1836808849000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
336	\\x48efe1fd7072e9de12b1f78bf65c7afa96c1b54c6e457f859e72666f41f3e633c933093a0e7199b61db03b11d5e326c90296b755a26f4e2e20349b6045a3fb75	1	0	\\x000000010000000000800003cfc630a4360d8ebeb241595c1c99b11cc6adf46eac4e0cf1171d0f2ef0650bdd1c5cc5b1198bd50e6a26e48734261d510478fabffa122eda3b6ddfb69e8317fd1f71663ba8f1352956572be8f9a9bf4f5980cfee65b3c47b74a99254bcfae13501c5dcda76e99c651f3bb618099dc24088a481ee5487c99d2389bdf579e624c3010001	\\xceb57359133a106c4c78023d79bb8c7bda310c36504fdf9eb457b604115cbbef42344f6bad6d3e2bded76002c9eb7c6fcbb94131d299b19278847f271726fc0b	1664016049000000	1664620849000000	1727692849000000	1822300849000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
337	\\x4a4363b1f915113647fd91c23b14bcde3529aa3d41fa99898893bf98eb8b7e5768e18537c4be0934a25e165516c500f0a307560f3b6c8522900f082a7949949f	1	0	\\x000000010000000000800003c0ab2ee5a6b7f529aa53fe2d11d0e87294b3009e90bda2be82558dc7f1b3db7641d33c696108d0f9544c218ed9356a6f60bf0f444fd48b981841b3f7e6cf07be2ec919a7dd2ff88ae14e42bd1a2fc346044a9c6f4f29423d04eedab1b7eded66fd07b83fd5f40b9208f823a70d9a6cec19dd14b29ff6f02e7407446075f912fb010001	\\x18f2c2838ff28bd106f8d882beda756437ab58a73cab66a5c6ce2da061718bed08b0b94a268a3c0e143dad843f39ba9b1a7a08e24c7db2ed6bc6f5f403d7a609	1677919549000000	1678524349000000	1741596349000000	1836204349000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
338	\\x4fcbd0bf8d5cb25aaa8ec1eaa36d962dd1d04a31778164ed6eccff8a45ddc3174bf34c3e777a1bd4380d90e1b1f098426fd960199cac6e0b80e196f555fc4561	1	0	\\x000000010000000000800003fd038586c804cf4b3e787b36a709d4ab9ee3ac825cdfcc18638d2a816c6f966164df8a248f1064b4b73568896fac90eacc15f7a2c634a3f3e624abe07774b6b7416b749d2270324202a732e27b13647c36f6bcfa117568096ec5c65ee85d4f74a902b4c593682a99dfc0f6a5dc69cbd5460944018784bde26e060dcda1a54beb010001	\\x509e0354d962ecb065b53388ff9bee114a0cd0537132e1c77ab6e049d4a9ead6d51344db1ff6638b2090ee910cab25b954e0ce8da4ed456f7968cd6da9d2a50f	1650112549000000	1650717349000000	1713789349000000	1808397349000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
339	\\x53f7fdeb5eba0a1facd3949bda25b84ce3116ce3b3d1a60771f8397d9530bdb163109f591dabd86a01adaab257746aeffb4bd021ac974a23b9daacc0f67ece30	1	0	\\x000000010000000000800003cae7ef349a848986c0f999fca17417792c54fd8190193786ae04d7cfdf8afac02b81997b6187b55b814fc7bdf837a853076e2ae20d7bcd9ec14c3b935ab01c4a07881d04df132cd2ea9010350f2e496a9f9b760adc5f0768bc6351b0983ad55fdca4ad14b526f2812d1a2564dfd1273682a4a8d20efcb54b307b456871728da5010001	\\x2c6fc248f6f47044fb457cc8753ee010647076f8562de175559db63c1902a0a49378489a396ef94a9f1d433d33d9118d4f794552398ff432f6d451de933d5a07	1657971049000000	1658575849000000	1721647849000000	1816255849000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
340	\\x53a74c287267120c17841e78b5920ee72a725819a8f06b1a434ef080db1d84fe81c07090cd5015c8d4e0dfb3eef03af230786568e69acd17f85dfc283ae82a09	1	0	\\x000000010000000000800003cb3dca92bc954b329dd76edadc300726c947c742d2b22e1b299d9239a859b4ccaca4c537b5d52478389c02cbe1b00321235d46c36c2493d052a666a54710acf9f302b52d3a3d9bc8ebf4cd72d3aa9f92830682934b844722aa1e9bd42c4848ec16d2eeb2ffa7b45cae7a5a4ccbb23140275d6112d151f4cb7b8739a615c81f63010001	\\xa8c78804735323d612f46fed6b30410eca242fc7a0a7e81314db6161180760213280c1cb8fb3c4845ca721583aafc038662e351cee3c418d7a9e83f3d8a82304	1676710549000000	1677315349000000	1740387349000000	1834995349000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
341	\\x535fe50eda0a83359f0dfadb34497da04ad7029d3f62702ef0a61aee1b2a935555fefd6b202d5aea06871f6d4b4451593c6ff56fff317b038300c5dae3e79307	1	0	\\x000000010000000000800003a8159d38c7341f8d09300cc5add07129ab31943ecb68a5785189919d8acd3943a9e6b4f93731a230e9766997c9eafe9056a902659831016b08d21077464b2a2c74688150dbc8cd7164d0e5829eb9805648fe5929d4472a1eb46e5fe3ab24c728258d5585d3b301d082c9c3cdfe8748b467074831e702ac0cf2101a6178cdfe41010001	\\x9d8ed4e37d6b7ff6006a22f7389463fc95ed8829e9f164727283f60828a1729c91996947edaaa458787b7270f49d67ed913f6869525c8cdd9ef07cfa5d69390b	1659784549000000	1660389349000000	1723461349000000	1818069349000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
342	\\x546b89ea5ed0162648e6947913cb15af694e747883d3ba497f16feec3822e3b1f278516136bd49c34bfdcfc65a6d22aed7cbbd55c07e5763c00d5db44f20ffc8	1	0	\\x000000010000000000800003913a2f0de55b9d38f37bc54de26333d3a0fb19d0ca7cb8027903b78a07b3b2fa6c38c6b27257707908976660d74a3b5def2fe4efac48056bf540de43e0ea9690d749c6b6ef575c9ddbb2bc6449a1f31d08b8bfa79f1cd5688a8bb2428675af36663e602e804fc38c724be5d522546a4c7b7aa8f8d58317425e9b15233f22a0f1010001	\\x33b39837a30894f8a80dfd51324900b5ffe21c17004fc4a2ebda0a545f7543f9b26064e69ea9e501b428301b33d82682ffdec0dd83fba79a78f02edf3ac9990d	1656157549000000	1656762349000000	1719834349000000	1814442349000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
343	\\x5b33f9760dcf44df0ac1dde3860e77947a5acd6f7c72ff59fd91ab2d3fdf07ea45d19f7569e162502101d6c3f1f319d37f85136e8e866b364572d7c3075b2185	1	0	\\x000000010000000000800003c6329889218c9009a5dab8c5003c20e65b24bdb3f52ceeeac0da10e4fdead387264a32921c953ef152bb97737c65a32888504eea9995f442e979a1bf83dceb26c35135e25739dfaf33172440fd73f310c01706a796a492a623a6aa729eaa39264e8cfc184d67a0497dfc420c903feaacafec1d2330fbd2bde9e0e7df9b2e57bd010001	\\xe3da79b7ff4edf79c774ddb0ed98da5e1d4166ef910714821680ca76a43b67cf4902910b9bc0ee440a466f4b152728572be049bb5df3f62b6805b62ed4333e08	1668247549000000	1668852349000000	1731924349000000	1826532349000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
344	\\x61d36a388fb84cf47e60f1fdecc03d3a195385af66c0f42d4ad8875324224900977214d7f96f14dce855ca800cab3d70e6d61695933c4eedc1c89a3ff1daa77a	1	0	\\x000000010000000000800003be0999dd77dab162fb768ae5ea3629a38c62f5a3be3e74da26f165809a9dcd10e28f996efb2e04ee829afe9e6b59c7c5606786400ac8b9d697c539cb3526f5015c7c94615c54d578573c4ba794facd83a82b74c674b6689213d1d524999c68c09a6f12a3ba8edb54e88ee55e5dda6951400206d3331b7efb65092ad19ba4b78d010001	\\x4ccc7278ac1135857bc290e957e7bbc6ba2c883da2d6e9abf26a54976771a8dfa6104a19e7412d594985fbfe75eeb0f139284d220247e3605e8c224a63c9260d	1672479049000000	1673083849000000	1736155849000000	1830763849000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
345	\\x628bceec1083155195dfa7088ddefbc8fb08eefb9429fe78dd286a6945ccb70deaf75b7bd1d1c9dc320b3b9b33e2cb79bbba45f2abbaada211ae8aa9aea31418	1	0	\\x000000010000000000800003b220d538d8c6075c5877fd37716b0315386292a30856f28fcafc56f0f0b53435772193b612ed892672346b43e5c4874ffa830a5aa9b5ec866c2e1375e9835e578d75c467de77321c3f042109cc70816835493960c23d88fe8489c944046f7128175c4e9ea0b907bd0298ae182bb52b8aeac6741aaf43eddc34d66d1ba4c6459f010001	\\x1f9036debd33ca080f6e44140133ce449df8354674e01c3a54ec3c1770972b87b154365ffa1de6a32c67ad6438e1e87bf033a91a2ef91b83b9949dbb8d8d0607	1664620549000000	1665225349000000	1728297349000000	1822905349000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
346	\\x6347a0097788980def9909022d50825afc6e32ec343b710e12f6877e200dbe243f1132165c23eae35d89957156fde867dfb1f7cee575774b5fb9ff3d8a32b763	1	0	\\x000000010000000000800003ab1e80021c3dc876b8de3a1160528cdf8a912ab772ab9e77c791593dd05aea52e92ce247a91eabcd0cf5b8bfcb4825face2a3eae0fcfd37dadc5407aa10f85749421fec559ab07736c9a0b8957fa0dbd96103d91e2549f6edc75aa8da8dbd0597e19af3788b78dc4c6294985d8f46e307cd62b3393803c375cedb823c4f3835b010001	\\x529080733224cf6d6f7de530f421aff28ee8dc45765790bb2ad1290bc08db6bc8b233e1f1f91bad64e425d5ac4d18b038ecab4e8a7aa5b87483362cda980ee07	1651926049000000	1652530849000000	1715602849000000	1810210849000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
347	\\x6493d4dc3976ef3f3f5dcc41ad82d45c0011a33026910972f5df4e65963f5c3569fb28196d332f0e5995f1a23129a1835819bbe4baf612d67bce1ae31faf194f	1	0	\\x000000010000000000800003e1cba852d0dfb3c041e1f57eb39b7d608015f4a4482cbf381360c203b76cb72ce021bdc004a39c1841a99e80f5345cbda186a515685850ed9e664edda34badee1398b1e514c92e5a7078d9dca57ec87f87d6fd2c29f71363106f1cd243ec5e781904c2ed1765ff8cf866fcdda3d12ab3e571997f3fbb88f38153d3c5fa49dc3d010001	\\x57d6bc7d4a5cd9c5b437888ca4c2054f4136514360d90a49300a060e0d6fef3b58e4bb269d9f423377a28a053d93d435c4f906824104f3f502e9d35ace92800b	1678524049000000	1679128849000000	1742200849000000	1836808849000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
348	\\x67ffb7660fc4da0bf75b83d1ac93ace0b7b68d90de0d3f11cbf093a371c5381ac5db38042a0199cd7a21e42689c7fceaf5e0a491b2dde4eeb274bd93d9a4863a	1	0	\\x000000010000000000800003cfa3445238c4e19f3952f2cf3ea90b40b2b82b9413e05678b828a9f6283d66f1be9b583a262c55c72bf78262248da1cbb157410473286d33ee96aa7d760f78cca39232fb205e1b1026b31a5919b88c15a6672f066955545bbca35a8bad1529f430ad59b0f05ec3cd75dea78c2c5b5b6d916fb79994023489666ab62672760a65010001	\\x762cd3fce99b16c85a4f29c792ee11a647204661c051db5d1e2777035c06ccea7d8ffe9872f16a65ed55ba420ca17cb329e22a604c7b800d21062276e683c602	1670665549000000	1671270349000000	1734342349000000	1828950349000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
349	\\x6c7fdffffb39f80673c26071b30334e88c9401110dd9fd3920b806fd5d02c79afc9b504b1d86f880ccd66b2fe9342f453b61a9e945317051c0b73e4014dd680e	1	0	\\x000000010000000000800003f9e147b7b5baa771ef9dd0506b0b26daca95a3c7f10883b6b0110d31a81511f886aea3a5df48765e6ee316d626a89121900d9c196f69e174f37b3ea995b6a813f06f33c1ac0c0130067405e132e723a0a4bc7fd86e62e6a62130dc2b820a19bc43d68b2e05572feed33a09d5f4e68eeddf14a00f672727400da5792660cb8aa1010001	\\x760da27665cc962104b556db578ab8dc6f6eedddd8ec3188207e7070942b177af187f66c99ac71c9e419722d4bb4bcf781dbfd154dceaa4924fcfaaa5fb23b0d	1659180049000000	1659784849000000	1722856849000000	1817464849000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
350	\\x73cb969967f13df4e88f9403c83a0ce45a1bf7ffa1309d41081d801543c0ab40d0e8f417beeed43648edbb6c79bb613169a55edc5ebf09815351a753bc547609	1	0	\\x000000010000000000800003e4cbd12c0ef084719b1c90f2838d49a827ca2ca1c3f58de0263087b58cd6aab28b6402777fed35d26743c57529023cb18b2f76d5dcdeccfe81a4e8bc6eba72d69c464ab2004539ee88260bb1543e1678f656aac969081ace717d14ee543ef1c2020a11ebb542856aa6d08f5f6756617d2cdff8e2ca7956f538195de475867061010001	\\x62dd0acc8061d2e3184d71c10b23c158ca2c4f2a9b9b030687fcd2a9c3fdb1f00bf49129c4e17c62e6c9ebe3d869aa8380ae1bb3dca5918409ff73abb7fdea0e	1653135049000000	1653739849000000	1716811849000000	1811419849000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
351	\\x7447a5b38d1de64c531398ecf7cb3ad12d8e8611791029eca95ef736a111f18534c9116ea765a9a0d72a730b8f60bdef074bd7ca0c0d1cedf75e3e2aecd19795	1	0	\\x000000010000000000800003caa7bcc09327d9dc49faf65c6b7f2efffc29b4f6cf8623968a4a71696f156566cdf2781173adae16d91d020fb7ea2ea762ef8ef98f0ef71d4233a6a66b0a649f1ddde5a30a0cad6f7e34e218db021803fad4c151ae46bde0677c7b22317ab5efeeeb6f86433d1bea4bd59864043973d0a30a6e53e122e1da62c6853f3869560b010001	\\xc50c0678fa69aca3c3df5ba17729bcf31c5642671cfb19aff64ed99d29eee591f254da4745d249e60e74ad6cab9bdc8e60cecf0e1f3171f2c5f8c173c3cd9004	1665829549000000	1666434349000000	1729506349000000	1824114349000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
352	\\x7563ff9ca592a3c279517573b1b794408fe60873e17dba0b137bf25d12825a201ed7858da4258de4cee4d422a5e293e9a901d395b8d79ad02f3f87849a863ef7	1	0	\\x000000010000000000800003ecf2366e869c45718cb588b45f0cb26745a827055739b56d624b948db96df73f3d58c60bcbbae0f4b4d292c626963565098a57be13684a3812ef62f013c3bba67194c48adf4973c115db20a7cd5a461deb87006c31037b94d7f0c5fc5aa91a5b8e9de5c4f1e82e4b6f3f3a411e17e86d9cc5c2b659505f871ba411b033883355010001	\\x427109afed626464ae64ccb46e21886f6ba951c9d77beb2f18449fa5e83097577a69ca58658e3a614401d1bb41723f7bd941f7aca4af79047e21a544f69dea0d	1658575549000000	1659180349000000	1722252349000000	1816860349000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
353	\\x77bbd6f561b8013909b3904abe02134bd1176f18c377c8d009293ee9ce20191e534a7998346a7901b398c0ce235e7cc655d1d7dcb7d7688a5519b9a329f30aea	1	0	\\x000000010000000000800003ae0857340d2a195c68327b91e1c18ffac66ef86b4945343608597d6942ec5f56bafdb7d77db41b8c356e59c622e16c29a805abe5dd4e2a07769846e2f054c13a9bff2fea15506122cb83e5c4d5f406785ebfaf2b9dcd008fe4aef5334421a382f6e3b66b842b77c4f51f328c6240e8046a19b7980568e87d72fb4d4a65f96cc9010001	\\x3029e9d68293105e762c12d103a680fd353a0fa8554336e1a7105917dafc7b3c1774aadce62219604ad6d45a53d3092d60487d03b03a46f4b52716927d7ede03	1657971049000000	1658575849000000	1721647849000000	1816255849000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
354	\\x78cf58de455019fcab1ab42b8094ce777a31140b2bcc594be449f638844b09274f82b972bfec1801b40b6674d4e354c42807f1b5ebc8f11fbb123f65f44583ca	1	0	\\x000000010000000000800003e4fd32c1dcdd12c8102f748443b155b7aa8927214a81dcbfb2953b45f8896eef4ecec2f32f7d75b41fc02a8cf7708164af9f1f0dfa5048751e9d7464d727627bd246f1149d11e15a2170ec941f5d6c7ca3452ab7aec79fa3efd6b80131c03308e27dd9229bf51983b6ddce4bbd0738aabbf74f86207d23fd9b7c82ec5f0d275f010001	\\x28bf776943716133ca00dc9838ad4ecf69a1decf435f78e3cb85c61862ac1457cd66df2c2b22ea6ab2db2b2c95e7a77a8347beb2e3fa9b7260375573a5b4b90f	1650717049000000	1651321849000000	1714393849000000	1809001849000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
355	\\x7adf1bd549a4eb3e42768d12a9b68f404fcaf83934c946c3c34c98809a75dbd422b73e805dcb0714000e136dac4f0373f083920339cd3b58141c773b2f392e10	1	0	\\x000000010000000000800003d585d03fe58c9a512ab86de969310f10bacc01a5863677cfd38b4fa82e18ca567b5c734a98fb05d09ea96c255996d2749e3470c615d70e12d350054e28dbd46f6a5c245df1e0f23537e841547f5c59d98a8da5116e36a419f98726752658fa389edba037c07f38f24c530e04375df9514049d7ed8a939fd2fe7c87fc4645bb6b010001	\\xcf93dbae92ba072d3cf4ecacc8e1f53141bf15a4b27bee3f7ad3962a0257edabac0412cef3dc170ae2a89a3abba880a55a0b2632829bb3680a31e747d62a4f09	1665829549000000	1666434349000000	1729506349000000	1824114349000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
356	\\x7ccbcf4a7b7f666912db3adf6e3379d06dec9b7807976c92a0805d67bcde019d653a6c247bf04b2ef273b53f130d7cace396f0dc52c2dfb31bffe7672b389417	1	0	\\x000000010000000000800003aa02c19fe8d5396ca635fe0e81c8b55e513c24d2e423433520e6459bf4b0fb9bf7cef8d7851a8ce01641dedf1baf6820d604d23f66bfabfe5303856cdda1639185b9e4dd91b0754fee227dab4d176e5d0f032c4025c76e6692be58e76fbe98854e0d9605b3e149fdfbdc9a05ca74b5c37ba5a9dabd0cc060e245ce0689d8b937010001	\\x808fc94095e5af8edb15b595c4f2111d8d318021d2c2e029ba4bfe6767950dd059c20c5d87238693ce616afb0e4b196b8f31bfeb93d5a679ccd1de82a0700606	1659784549000000	1660389349000000	1723461349000000	1818069349000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
357	\\x7e43a8d9a118a47e0abd3a4fa95a9df07a3c790906fac24bc1a63f483a70f7671cd4e23d0258446fd71ed1cde318f83f15b366bed577433af343219e9ec5fe18	1	0	\\x000000010000000000800003aeddead4a29c979801cd81afacb764550d9e9ae6407c554a801929e42133ddf336d1d47fae016114b019b068fd551860cb2228f703ad7c4e037863a7d46a13d27f75b3ca8938262060429f2541470687c4170a47bc6201c04c9fee930b7b66ee908a13783447fd9654cacaa26d17c3f38930065d4fa7de220d3725af8c897ad5010001	\\x01d9665eb0427b99d2fd7eabdf7ef4eece965a3eb4a4553f7436888a2d4d0f0ce3f18da1852babd9308558d23e27d1e978447bf4587ae8d281b3c8afec66250f	1667643049000000	1668247849000000	1731319849000000	1825927849000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
358	\\x838f12ccd6aff10b2ce606c32b5de8728aeb6dc9cdad52ac46e27cd895790790f89a6790364d851b79bbd826bdf638a0ffeca935dd2a1f70035c3e5cb459b6a8	1	0	\\x000000010000000000800003c13c10047eee01b0cf964bc861e81dc5b1ceaf9462006b0e414d8984b0f0b42a1c7c31c6f18cc06ed5731791365c90d2f2d8836e56d375a1deb0afb56e8ecdb2c4c455aa88995e633fbda37335bba54cde143989f8ef8934d8b93cab2135a3a572fb0ccf4e88da8db8c9e0cebda268929d21b12ac46a7f80baacff0d78b5aa8d010001	\\x359f039845fe47070bf4887c1d6258183b92d3337ec3af567d98174f44343d28791351eecf4cc6a04c95dd7629bb9f7172c729622f81c9e3f88604dc55a55b0b	1659784549000000	1660389349000000	1723461349000000	1818069349000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
359	\\x830752d8a0f0a682feb05208baa79e6367131637dd1f9072585a507b891904d05e87e62935f7375613da36c5e5702e67a573fb0f7a75ed73782117737c3e04b2	1	0	\\x000000010000000000800003bfe1085cc10ec77431bb0201e848de542ff91d6451cd0693d1bf662b92afc96e61c669e67912c0b12431aee78a7de42dbea40c9e2103a63642df844cb61d4b78260b7f44f20a06253589e49bdb3e50d874ef7781c79718f0ca540fa80d61b113ef76f7f7be00607e07d00f1dda1ef405f3cabc4a3bc4b38fdec22c10c9b3d1d1010001	\\x06ab86bf18d5c36dcb0fb291c10a5c9a07887aa9cdf9c802d7a9f24a7b90d61bc646e94637fd0b4a1ec0d98ce2029d322d3ce81a0a695a534b9a41af8d16250f	1660389049000000	1660993849000000	1724065849000000	1818673849000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
360	\\x859bf6d4d2e26c03093cf46afcb93a4494e4eee0fc9a8aadd48d777679c715c1b1b9e0115ca5c5631535da41e88343f0538baaa932ad0ac6281399b9aa44a9ee	1	0	\\x000000010000000000800003cd351f202413f6415cb0f48987b7bdff7873a32a9bb2007f46329bb5b2fcfbeabeb7ef97359fee71d35499d106f795b7bb36d643625e437dd30804d54f489f1e8f17df49498e82775f66a02bd3877c8ac1666caaa506c9a19144b25ebbdd9735394e2c31f4188fac04ea66075734e4fd907b5f9eab510bd382b0b1e5e71f7935010001	\\x3bb97e81a21e28b8d1f284316e57f5cdd3989cd5e2a7f33021d347cace85cdeda3bca0e70393c8d9a17362f65b7572acd80a682295729ce95f13487fd6f86b03	1671874549000000	1672479349000000	1735551349000000	1830159349000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
361	\\x8623bb33aea8c02a32e0848edb60ce41c4dd4c1de3186a16e469d1004793ec7ca83ad4a93130f94b8dad62cb41e695a54574315b9b88b79e78fe6ca2352fa0b3	1	0	\\x000000010000000000800003acc0a37aec8dd27c1c10f26ff834bb599a8ce84e3a2544c0b2b1a96e75cbf1bfb88e29771590583a65ae4bcae194fbec6c16516a2a1af678fdc5ef309bed73d03985e8f523017ed105cc001815f906cfc301b2a0ab6c5ac01b721e614837973a0122b045ec6986ecc0cdc1d0773c06639a615a7e85ef20777f19d69ee8b6700d010001	\\xe1be4609f889dc1c39de8c873352904317215e4f3b554732979953ac73875e03bb1483e1a2d2a59ce823ee08e87ea1a3fc33894d61197ec5f66262ba02be1b08	1676710549000000	1677315349000000	1740387349000000	1834995349000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
362	\\x8843a95edb584f1cc271b85f2e8d11d6d47521efc638a6747d2d11836364c0149c687f0c52f999e81d28d3198dffed90f8851b36aa64b640f5749939885d505c	1	0	\\x000000010000000000800003b050a38802daeeb50ce457be8872a32828a4c5ef3e22144fdb116dcac310d92e0689fced63535ea44646db96b8aa10d8461ee2f9dc220ed92103757e42a4c3cc89d23348f5a296672545c59c40adb0f1692a5533e8290c8989ff3735e5ca8d77a41a998443870bad4e59483bb9e96bfad452164ae399e5c316d236ff5ac7e4db010001	\\xeb1b4a5358c3229d9f1f0554a7f707949d5e840ad2e80b4051d7b4208ad706331fe6a56daeb212df614558d63960b3f8a816b618f1d67ddc1172a0ea27215905	1647694549000000	1648299349000000	1711371349000000	1805979349000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
363	\\x887b24f864031012733a05ddde5b71a041bce5cce5e5e263d1cf4ecd03e563c6b2b68f92721b4ba8d956b603aca7e71db7955f5d4a6d5ebfae3a42402af2778f	1	0	\\x0000000100000000008000039df30e75ec10e79daffa19dadeb9df2c12db7fede49a2dc45b45cb7b033f712cb8b05165f7f60bc143b1926a21e84080c1acabc8bf58bfb41d3d57e53e50179792a90a278c9d878194dd7d3a04bef8f6f52952f7cc8cd94ddd8931d7553a7b7423465768f7dac18b2b3c0e1c003b6f0417b9030730a4e0ec70e572c3ded40833010001	\\xaa9770b53d71a4312e22958c3e0d2d03b0c057234e6b3157accc0f69592aa1fb92bca4e61d36e8e33b705113e8255f9029c17e52ab442b9c6b9045d1d3d2ad0f	1665829549000000	1666434349000000	1729506349000000	1824114349000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
364	\\x8b7b15b86f9439fb4c75676c465ec10318b7f785a4b44c2f6f87edc4727cff914c60dc2fb6ed0599f083e1dfc8ba54406780549e110ab6b06b65fc5ec86925d9	1	0	\\x000000010000000000800003d99736a18dcdb3d169af2cdd216f7040fbd61c8667279d8010985dea02f6f30e79d08c80fb2c97f83cf73e8eabf5995c1edfd7ab3fc9a3ae163ca511a7ff7cd034ad98ca6cc1773a619e9bffed2ee7b3807fdca2d8579f3c522b1f7cde1638dbb19ba58f7e32781a4254ff138d8eb8f260f3cc9669757369eee9fde4a4b059df010001	\\xb8249e051759c1f6b4b8c660b5a5a84ac17d2be5efedbe73c72164eb6f3d43794a3bba40218628218351d469eef62e0476e1758d093c68d99ab253576c3e9f08	1656157549000000	1656762349000000	1719834349000000	1814442349000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
365	\\x8df7597211ddd40f7cf7f8c3f84d4d1b6cb9111950294ec4d8bff0a6eb7dddaf1f20419408afe4153af1b4b5cff4e93c681e6e3b767046a9131c020bedbeb9a9	1	0	\\x000000010000000000800003947295f905510a96b7f209b67f61199645d015b3dcddca81a432d6675cd5d30e05d0224de4d9f6ffaae4eb5d321fb65cbb0c9c87b769405278c612e91fae412f55136a2f022ef39b2d2d6db1fa5134bfd5fa7768a4540d75b7389674b2ba9e0492b9803df68fa45be561ab37b4d7ff4fbc36bab3f02df1dc26421e6358fef00d010001	\\xf05478c8e272d3360636d8196f0330412ce422adc43a9701a21919f2abf05c3b521e175445f2131284fce9efe3380cb8d009103e6df6b088c232f64ac7ea270e	1666434049000000	1667038849000000	1730110849000000	1824718849000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
366	\\x8e0b5464b07b620ff4af5dcf0f6962fb4ddc45452226f5eae0bdd18080671255df0c8d68fada252d91c2f6a1c31e888ecf33da743cc35e551d40c3d486ff4720	1	0	\\x000000010000000000800003e65e1b27402fc9f5467dc5bec5b7326c28013c437475c0bcbcee1e9964aef215eddeb8e31ed3ee641819a14c7a5d283fa31e90af4be2598b6b602788f57a5acef41b66786daac812f8783eeca581dc4c5025f92e4013a27463ea6b0fcfe04ea488e270bd024cfe3e659872184166a5181f8e8ab9b2046aeb5600cde503a05421010001	\\x3265f374c68bdfd9f95fbfcd77af84da0c7cd8e5b0d5b4c5975de6b01ed192969ce6ec1798b27e8876acabf82bbb450cec7917a97a045cc7a157593c85773006	1670061049000000	1670665849000000	1733737849000000	1828345849000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
367	\\x93bb94405ec85440c034ef215929467236237cd09d25a998896446dc83983842b92bbc025025b6d6c208e8a86075662c67d238a7883761c54d71a271b5c55aac	1	0	\\x000000010000000000800003eba3dc4d6f851bdf84ab5ae2cad7a3cdebc0f019bc8fed7af7e4e30ee2cd9564e4b5b9b26d74e431e4d5c375d3479985444cd54ab38de162366300202b95dfee391ad46dbd9abc41cfd231b40f8d08960e18d19e679f9d57b735dfbed9c1a4b593830ba81d78eb197a1879c01c107bc8881799e5669262f450c677a2b071e217010001	\\xae56d449715ff943fe840b240f192ff0a007be21545b17c53b39784a4a25c3ad5ca08c461c38d44e8b14e900e09a91d47b10299f49f316443bd404ad37061d0b	1677315049000000	1677919849000000	1740991849000000	1835599849000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
368	\\x94db834ab2538b64ce88aba0f4b1af0ecf587e46bb78218f9a23cbec5fedae96d4ffa66627f4ab9a5ac976ef9215849547ef390093e229f2ec7f9aa56b8e9af2	1	0	\\x000000010000000000800003af7db63871c647af74958fcbc467dfbd973f340158164fdab1e4ee7799e6ce15fe61ac5614dca034c504ec58ae7f88c071996c03aacb0ca6246edc61b8ce4a3ab1e1c086c86c15b185a00aea2e7c2247664515d6591b20b28ab7cf3da178aaf88c417b3767065ba725e876ac539d9e77a965bb9909d9414f84691ee31ef6be6d010001	\\xff6479c192c6cc526d2fa7b66e3da0a92bf36f8e79387fddc735193acf6e1f47c0020aad69bf3453835bacbc44278c6cbadb81ed8cfa7961a7035041087a9e03	1677315049000000	1677919849000000	1740991849000000	1835599849000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
369	\\x96cb33d5f9d83740f143e61f47b21c24f3ce6f15efa9c2c9f066537aaac02523be317f2948043f10ea763b6795321730af8b9e3a5731998aca18433a33f833b3	1	0	\\x000000010000000000800003e141cd9007f37c8bbb26ba6e53971f346659296866c00918413e6f5a1a1f119d97bd7f5158afe7626681c8e8964b717ecae5aa3d9ff2d440a4503ef2006fcb0abc4bb1210ed738c14c62c09c65c909d0c090fad643807d6853f037c5df79b5a8e633e2db316562bd5de96ac86ea6fb3cb3dad0252d4f27ceaab1c57cfb9a1b9f010001	\\x040127565a806de7ecebcdb7a58dca2766b8207a151cb7b707e9ad0400507aeb2137f7ac3f688f5f607997375dcba872b7fe6d8126d26a2294a491f9e32fac08	1649508049000000	1650112849000000	1713184849000000	1807792849000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
370	\\x975bad601cb12a63e359cae98c446d354199ca95313b1616ba5f9c6969115d5efa51d699bde642136fea70eae7776fa72d4ebb229494b3da2dde7e6ac9e5dbe0	1	0	\\x000000010000000000800003e83f09366db9238f07a48460c9ed4a4363c68904ddbca526feea9028ed5a9d19b1b29bec122990183f627a0265f785ba1c9e7a2dcd3c8a2ea47f82d653782ca16e2eea6f97e86f7ee97ee255e1e2c4b9939dee1cb4d74e9e8b1d4886a826263ffe7f0af39af6236aa2770a284ba18110eda4a31bad1ba285766973755b7848d5010001	\\x6f0ddc81004edc8a3e2f02d43e77054f7d9faddd4ce574dd92cbcb0d2a738de42678b8f6667d6e577846cf1c964b8d614f789a78eb206793aea4d822f5816607	1649508049000000	1650112849000000	1713184849000000	1807792849000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
371	\\x97d3b18010759d2dace2fb18b2388686cc676f54086904e355ecf3a37ec65e8d8650a445b0e91d45e412a89742331ddbf56138100086ff1bbb23a61faf65ae4a	1	0	\\x000000010000000000800003a33e63c8c7b812267136f29aa8907772866dcc7c24880789fa4f6d315142a31c6e40e86b3ac1dfc3ecb8a215024bf8aba5a36f4b7544f66e21aa1cad7156fdef7d5e8f6296024d3962eed5ac88b1ae9c4eb286ccdb53cfabc753b232fc1d79091c0849fd28821b1715f5a78540d47dcbeef996b291a16319a234a9403eca11d7010001	\\x22076f2e15199b5d29e718324dcafd7b942dabf440772b12acb9e0089ff1bc19484536867dd4ac92244f857a07e76c442b0b6aba4c02eb58c138ca7dd00f7605	1677919549000000	1678524349000000	1741596349000000	1836204349000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
372	\\x9917b49fbdd32660c83e7cc8354952b840c5d8a65a36b4b15daa5ed1a9f9eecc4e2f76fb1ed589473769fc0f8df07fdfcedcb0487a93678052edcd0b363e00c9	1	0	\\x000000010000000000800003bb735f4a60e3f7ae22749d001dd46a31afa7f02f2c20012315279ae85b6dc31b7924aafc627e9a3ac86eb9342afb187192070b6cad571c9892a8cc9cd55e497b4fb3143df121cc2ca73676eda7907e74820de43973f94c94e5bd7cdc899facd8a794cf29869bd9bad49fb327677167133c77a1e07cf2f6c24bd1a0b18ce645b1010001	\\x637fd2a0ac7569f9e16a5acc154df60bc3cf682925ffa3fd476115032ba766fb6c63c4b408194df71adcef35f06fd6e9b2abdc5459688ef58d2d689195583903	1660389049000000	1660993849000000	1724065849000000	1818673849000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
373	\\x9bb7d6ed158dc86fe8ef449f715fb018538fa15544bf9a73b7317de1411fcf779e341ee5e4ca05140187ea81c62830006786f6acb7d533d544e68395cb92e65a	1	0	\\x000000010000000000800003a7b97b3e169ac4b7b49f2e05ddb02fc7ee27885346198ddb4c9e939c52616522323b2f03f9e08c6f61ecfd9ee44bcf8bb2c22b3e6daac07a1ebd31599594bfb117537b62fe4e649f3caf2adc8f7480a9084ace77a93b62aaf351cf6615935321a2ac67326931974776ba1da4edbf261fdb5a31bbc5ee5bcdbc20f0329e308f3d010001	\\xfeba91b4e20622d54c255b9f5f729cdc7426c423ebbd03e8835faf13832df5b732f0d6cd8b87cdc7ed504b45a99ed9d3e3bddc89555f26101023d4cafb906600	1655553049000000	1656157849000000	1719229849000000	1813837849000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
374	\\x9dcf8f5c533789e32d4034cd18ad0f438375e5ea806ea634fc6a28f8d12150c98e00e0b0dc5f5022f9257301980d72940d5e6f0a904e9c3d2008880148460aa2	1	0	\\x000000010000000000800003be349fcec2bf00609406f742d12823887e3d23f2cb951f13dd756744f32ed0e4a18a3ff4a7496128ba9a7364cc9f47f48f7bea10b7c532d665c5971250015d4b6fbb594c2ef4050ca54059bc13b95b745c0aad4a87b67e0a2bc19f49fda67163b607c8edbf3f7cb975253361cae9f25a9714af369f651b4eb8e8bba10bf94935010001	\\xafc87e2f2b945ec9d9776d75646b153158dc99ea2aa8696ff050c5ec627867a53e2540385af3562291cb32e5ae9aa6cd0e2b1f90f0c1c6ccf3bcec456333b509	1654344049000000	1654948849000000	1718020849000000	1812628849000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
375	\\x9d2f1e5d2f152713184a9d46c6877d9eb01908a4139f408969e47766fe71680d7efe77082213cceb7f8ffb744d2866f491f3b8f64c6aabc5e3c2d2c8a3fd7dfe	1	0	\\x000000010000000000800003bbd52b5ba34070468dcc2a1c088a6c79fefb4539cdf5761beb853492c315d63538dda086e59aa0086f069b4417cd6019dde5a73006d4c00589b66d9ee15c9ffea07f07d2f3a5f4dc2ec0db899a0990280398cedf18b14d75f0b49a97b1c0a2ed1c93f50a26ee9a38c3a25a9ec534b4f60a3f069c05fbbf6a7f373cd61cbd58a7010001	\\xa34f1646010100bb063288425f1dcec871140cf65ecd8ea4faed9cb2d5513f2f5bf26c1f48cc245c5f0f1c52257c4a8418cd924519e8ba83bf9d1dcc0bf16f09	1671874549000000	1672479349000000	1735551349000000	1830159349000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
376	\\x9e2fa4a39600338c75c52d901e002ebee785852cd5464bedd3836f2f9a684a6425927a2b2a70b6bd49e78d8725c44c9314289402958b6acdc78c209fe8e34cc1	1	0	\\x000000010000000000800003bbb207fa26fac78e2eda48250c43df60c01350389c3356f7eb28610cbd968c182b8e3e44e92cfa0ab5cc1ea2b9e590cf5deaca34fad0ffc634a5541c4ea1f40b477416ef7aa8fba8d1fcdad55e668db1deb988774b694ffbc6a3aa31b712ff6a1e02118cc57a370c62b2556b27220193eec7fcf6d295c62d3fbf9b29028568ff010001	\\x827546817a04b115b012c06a1719f5c66db775489e2daa4124eeb9a336e615ea31493ce62e70950afeed11e8cfa5034647d8f199ffc0caa229f64cd8b73fd401	1666434049000000	1667038849000000	1730110849000000	1824718849000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
377	\\xa2dffa8d5802a3211c7ba1cff42504670009c246080ecf7ed798df0d5152cd744077877401ff81b0b6c0dc037ad461262e73a452d84fb5abc803fa4f6d69b848	1	0	\\x000000010000000000800003bd2321407da19531cd110c8a5d964ca76f0db0ede10142bcf2a07dd18cf1d0dcb414845e765992773e2ea1142d3e21d3e02978f214d21569920c123510529b51f1f867b33b096c6546110b421efff1545b7cf59b3b03074af79b999a015ba768f3fb31a572ed801d2e2cd94c297f8216e6c579ce070961adcafb06e438058d4b010001	\\x82f55dfd527cd297d60e23c10661bb6f35f89420ad3a1b8e59648b66d6a71cee3d1be859bd9a097ffee21b15224dea545f19cde1bbd544f67977957408920f0b	1675501549000000	1676106349000000	1739178349000000	1833786349000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
378	\\xa237e73d3b67da9c87b44f178df1c2335cadc66c50a9921a9067fc96febdad51bccdb656dfb889dc7954f35d2b03f27f71463105b229ab88860e0ecab2b3e398	1	0	\\x000000010000000000800003ccd9a35f739aa2c3346db85b2d6aa4c78081703c8b7fa7a0ce9f3610741fdc81bda6107c5777cdfbfdcd472308810a9d502e1cd928793ccf2ec903c1b171d20261b021d8431184d48a96d26932db4a772e2020888602bb830469270f22468047dfcbce7f85cf0fa6a363d6e7b0f3a8097e74de839f9620830dc7940c1bae56a7010001	\\x1a8179c6434f563ebfcbf70a0502c3b81405fdf9a63b50867aaa1da4c5e81fb12cc0063d2d4fc5a997929734d586438e1842589eabfa92902654761487595901	1662807049000000	1663411849000000	1726483849000000	1821091849000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
379	\\xa20b70c0c9c990989d053c47279b42e8464595c7646e7d18685fbf7e4488965c83aaae8c7b1189ad049a3a180a02d633881c4c5453c575bc7eb80763dfe58d87	1	0	\\x000000010000000000800003babe1d6c10c0cef45920bd9982690f53acc014db1d1d86ca8590697e504e0eddfa7a7ad440b5ad331c16579557e2f22b0811676c3edff6af88a1f44791d5b036157d9cd0a41a984e56adbe981f1f510dd1d399566da8fb08faac77ba0fa116cb7ab82f0c71e624851a0faef3b6077b173a6d40e98f193b883df8d89f336ed43b010001	\\x911d92940d9ba00d0be0f52924002905261dff5b2297266e31c45e236017a52e32dcb26c2ec3524af79234684b5cfafb8b9907e5502c13bf44e6ae704bcd9104	1659180049000000	1659784849000000	1722856849000000	1817464849000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
380	\\xa227f3ce8565370fc07503ae27e8f8d8d239acf1bdf89e6eb3b2f6c2062f67ffe7f65fc66baa60d36bed685f4f81b9025c0bdf67da2e5b446e51f7f920d6848c	1	0	\\x000000010000000000800003a56f89d5141ee3bae0703cdecc19f23ca8136593bf8b751349512c4ef5ec91151266038d007e27be0552c85528dc4dd421b33cf0df6e9e8ecd0ccfb75f68b858869479feca01e550ce7fb9e018af6ef51b3c8d3e2d261038c75da94ce38b58076abfe40772303ba9139704be10ea6e73955a2eef33bf81cc38ea3b330b473571010001	\\x2bb88c471a23d90dcc3294cb841132710bf72375a149ca61b9e342eae1571ee900af56952da211aa94ca93538ed72c1339d5daa858f65615f56d96f377379709	1677315049000000	1677919849000000	1740991849000000	1835599849000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
381	\\xa387536ddbbc036ecb62aa4e896eb2e74fe0c363aaeb52dd1651419a2c231aacd7aec8dcb7461ad4d8f1833474f2cf80b2318e5a59229bf8059d526f73c2598d	1	0	\\x000000010000000000800003aadf09d94c5900014786238c871487bc962e47b4675c7b3149dea46af833d5297f9e48525a5490b3b5ea492eecc5ba49dbd0f77875b93543e2e2c2c206d20c25033cd6ad77a29b15ae463a2fb208fa901a41b306f646e0ac502d16c151979455b8200fe123c55169ba35837a49d015cf2a43bb31d9cbdee8f3009c678a3bbb8b010001	\\xb92b686edd2bd245424566dabba24a9f3ab33432b7a4e5729e08bb760eb850d0f463207976793473fdccf7f0caf0598fa040475969f56c8247a35e27ec1dbc06	1672479049000000	1673083849000000	1736155849000000	1830763849000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
382	\\xa3371d8a0f56dfb60209ba9e8ea0c554715978eb166402ad775d1fb2d01c3feec96b3d1d0786f75d8a35b5a31aad99a550d143dedd14513d3ef8900bc9574eb2	1	0	\\x000000010000000000800003aae33f9e08027ea2bcd995f208ecb02457129ea1cda21ff304377a805fb5d8490b547a9321cbd8df60a2acab340217dd5f92179ddf6766d2f24a6ee2f3e4be4fd3b86ae1d036ea26383ea8bee107c220a30a8b7a9158ebe0f0aaac7dbe3cf4403a868640ef7d7bdf5520a89e021b9cd02fcc5fd16e83d57262edf762e7f6ba5d010001	\\x8e629a7c63f58a6069aa9fdc8bebc705997a712b8f16bb1601e74aa75c64bd3dac13046fd1f32f1515f14c5284952489a8083986eb45e7bf530ecee0ed5d7803	1662202549000000	1662807349000000	1725879349000000	1820487349000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
383	\\xa40f626b36408233295647d22f0031e036ade8f4fd34f5e45a1afbb44b0ecde2462c428d9952d2bf9028a31064436f0098a7df1d8f15335063470cae1de05247	1	0	\\x000000010000000000800003a80ab594b1b550bbd33b99a61d2a6c0a4fa266a9bec8acce35c42c3a14a3a601f5f0df7b8bfdf17e7af4148d17797031856433a5a0185bb729ddc5225ddd90a7d126977a855269a7688044be656930133917fe42948b85bb282c57cb5471aa637b653a643f0d1a6f5773ceace67269ca5dee510574cd8bdeeed86adcf7565de3010001	\\x12096e7345ac6d77891c4d200369c98a471cc3d9a89ade0cafe94adc2c1bde6e0c6aac9fd3d87cf301e54eb7acdefba73cd6be83c6ff862b48d6d17aaa86b503	1651926049000000	1652530849000000	1715602849000000	1810210849000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
384	\\xa7a36007e75952850b743e8b21a14e5d96dc07ffa7e7f7e9398dc0320fe80671bf5ece238f37cd63af2eaf8c6e27edaade00a18ed743ac59e26597375b7e6a7f	1	0	\\x000000010000000000800003cb484b7bb3bbb70163f5a1537b1183297d422d9d5c43ef626a754b4d11a045ada80090e48c15a7eb768930e50828c366a7ca5a2f44ed4da428cfaf84a86e1003f93650fc1cc94ba4516a22724558243b2886af3e2c6bfda4d57e8b297fbf748af20a3b777425618108ac1ddd22548fc242c8159c22301cb489179be434aa21c3010001	\\xcffd0d371410cfb4d4644346ceb11947092eb914c7d0bf2ebf03db95ce1a45e379132adc335356de8a66607d7281135e75cb43aa089b3fe4c8e07cf379ed8604	1651926049000000	1652530849000000	1715602849000000	1810210849000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
385	\\xaa6394174d834d1c713a5c75b0b635a8f024aad01d29a0828d23ddcd117431f6df7b8dc0d1f8231de7ffbf041dd26ffac06a0d5f84dfc02c47154ec8d12d2c0f	1	0	\\x000000010000000000800003b98dd8037f5e47ae7c9c8647896ed04bed22739d1637bf47506133b3f05da97b647b6b647e9c4977cb0bb8261b63ef21832a21317009c2e9dcaeaac6d4bee043588e7e33e15ddf8810b1a10b05104b8d758e1f28b35f133a26bdf502c49db01675ebc87667b9ff3c978fb0e53e8689c56b4178c53961851aa8366837d3ced2db010001	\\xb2da1b46538899f6dc00f1823c26d87954d57595362629868b0f5e5b57d1d68e6218b504e3db0a0b876267d5f7dee103abe251df2a567c0cbbcfd154f2afcf01	1667038549000000	1667643349000000	1730715349000000	1825323349000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
386	\\xae139ec88d583cb5840d27266437f2db070d3edc3589bd51133d1bfab7070e086ba9888ff9834d791eb28176c4446fe527004abf3ccbe144ea485e047db590bb	1	0	\\x000000010000000000800003ea30d663fb9458ff58595d1a566d0ba13b8b610b0038eecc438d85baaecb2b6213502b2f79657da63b1e1900ae4c87c9593a7c6fcc93d2f11e19dc7fbb2e8d5c135c1fa558919e168aabe47addbdc5b692bc41ef7ddd45597c8bb3c5baee082c44c07e10223658bc7104ee047658e49a1e74cf4a3e389051f2a81f89d6007445010001	\\x90ea84b0a0bfd1153ffed36fa401b489d194dafbfeacdb0d3b69a6bf013e04973e370765d80b81f8d6068d3a399a8b22c4da3ee1ba9e70ef219211468f5bd20c	1654344049000000	1654948849000000	1718020849000000	1812628849000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
387	\\xb003b98273e65b95384da48c25ff37fc19d98b2bd67885d74aaecce82d86c3d8800f1d5753dd7bc59ec86fe6ca55aa12ebd3a305b635a24c50b92df5eac1adc7	1	0	\\x000000010000000000800003ab2c89ed5c43af63386c8357c69589f125877f8648d736f1cb6b4b9a6a5d52c97bbfd00c2607bb69219af04bd7c55b53e8a31bbf61c5a4c83b6dad708b72b1103a9caa14e9f3c34cb3d0a5eda7623c49443004e3ac7923dc20de6a37af30932f2f80186147334ec13c746ee201dbb763a02fdeff51efc27d74ce66dad1f03bb7010001	\\x790c1de1e72b89ec4f819e833fbf752f87b2f1346e0f7d1c401918bcb73ec429b99bc788048a2c60e8d49754fade9c3b09190be4bea719a070fa744f7f6b9407	1677315049000000	1677919849000000	1740991849000000	1835599849000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
388	\\xb07f70045b8e1fb7e812fa5c7fe28e6fe21883c450dda429927b5a5cdf40c2494deb8b1ab1113b34cd02817a690339f7e917f9f6885bde322e9ad42980795c25	1	0	\\x000000010000000000800003cb4b45640d70f0db984281a2136061f87261b652091c103827ee0310f75d1fb38249936966d02349e2eb70da17b384c739802cdca0104ee43fd7a22d8119fa5e26ff1cea70a23a123d61a4b80d71bab97f377c97d5edde7471ec7371992fdc7c9d7f75e47ea5eb2f2e9680a5d8ab92a592c208dc567291dbb186c31492ff1603010001	\\x0f9a6d651cd5f566d12947c32c624bcae8eee473f317f69bc0b1fc505abeda611177e4ce58c9adf8f6fd5ad3a3863082253af8eb0f3fbc94a6cf3a219a31d30f	1653739549000000	1654344349000000	1717416349000000	1812024349000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
389	\\xb3c32b4722fc4b4284f3852c880209b6b6ca3470e71036806f3e70a41facbe8dcbed229d49d5505d7efd2a34016724f2fa3aedbdc7a3ee90cd3f7112798736f3	1	0	\\x000000010000000000800003bd5412eeef7720d7eb616710ca2e58cb367f3d2477f57f205fd09987979f7b422dadae03e32f767f37f5b41e556c52cca952feb589ecbe132deecad7b34fe62aa23f1bbaab87f948d3fa9e17eb5530d0cdc755cc4c0b19ceef7276a076d7892125d7628b5c62c9acba78769793bf4d3fce4d1485afc92861a3229965b1a177df010001	\\x6e717a581447e91e02b957e92a8767f0873ef480b5bf9e56a27002a0a30f3c452d0af48eb1ab0d24c11c64999f540202fa0bff4e0498c6234594253bdc5f380f	1651926049000000	1652530849000000	1715602849000000	1810210849000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
390	\\xb52f1a10f7c7d95b60276fde1b825281e7d4534b7227ee4b39bcd363d62aac95240eb65be94275df91f4c64c410e75c6a402b869b56256197c0a4748ab88fb08	1	0	\\x000000010000000000800003fd12a6fb3cc8ad3ac636b50560280512095ed170f7a47533dc93105cbb50b4051a962437c01044c5eb0c857c76d794745c049a497bf55dbb38ee00d9945a776849acc205c47702c2e7bf16041513400f4673749094fa7f2756bbd9b38f2b4b743a7732b092ba2215ff58e38cb19bb64be0af270e10ae2b2b1de8289b62f9a667010001	\\xaaa8a6677e09bd9b22a2e384276d7821df72c1360e8e009c83af66bf163f4418fa5833e155364e3f9cfed1c0dd6477b4ef651afe3c714a8d085bd2f000e5460b	1666434049000000	1667038849000000	1730110849000000	1824718849000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
391	\\xb7c7fb640852918088d0b2582be22ed6f47abe3ca14d25b48a4951f0dbcc09f09d63a2393eb8782751fb23828a56d9fb07f8fa78a4afa7736c4f29eb2cd7852d	1	0	\\x000000010000000000800003aca9d184405dfbc3aa15b92bfe9dfc1eac4471efec4438819c5fc28f47d90dad983b9d9399f4bdaea658a49a071adc818e3c6c5d45e4159993760d112bdfb66c245adf638d3fc98242495cecc1081b86a9de6c7667ee6e98746b5221f7887693f0910fd1de955d47a3e054783a59c1db93529959576c527f9e89acf64fd62c23010001	\\xdc5a041c61db5f7440d740491394b86ef9e447e2b5850d86af96643fcf26c3bc8e1f424c110c6da4cb6ab286077f19304eb2d5bc55dbbdd8218135bc18095d07	1652530549000000	1653135349000000	1716207349000000	1810815349000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
392	\\xb86ba9fbb58502e7f2a364d6c0833c8bd309e9dc61ec086b4c9d26a98e8918fba1881c514c7c928afe1fbc7aff8c29e32906ee82a1e2687027e75c43b6ea0553	1	0	\\x000000010000000000800003af6501d8adb8b755f529917c8491bdbeea1690d1dfda46576d90fb3994857dd6e72b76bf2a1303f2988f54f7d74f48ad0224a997943f2400bbd3fce56f544d0f3d5f8284c04c72b86a63fa5c0acf91c93eacb6f209e6d9f8dd7b84751efccd06aa469902875626b505402699ef8ec2713ff3ce952f2f3e69afe50048525d9e03010001	\\xe796ffa9cb02992e3cfb95c7ae449a0e19f553225226935ed967514ad90ab25d7d5a8be81415b05bb600f48d7a23bd3f96ccd15c2e75185cf1cf2672f16f820f	1665225049000000	1665829849000000	1728901849000000	1823509849000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
393	\\xb9a7db36c5b08c86dc9ebbc2a5535b33098f9b3bc57938feb3669e724437bdcd5f6658c080235dcbf74895d80a1c4a95ee4fea9c3c475092aa037ccbc71e0eb3	1	0	\\x000000010000000000800003d975fc37f5b6cf9a173bf2dd88a1023ba6122ad6dec3ffe9175932b3d15366027457880047e6084a633c129bbe076ab7ff7e4c6e6995f3144b5000799c8c31932025c5c6c194020db51874cf0cf3e9e631c3cc2fe9cc5f3fc0bc8f3f23ea8ef15b33656c070faff4950fefcc7b94a9d47f06e28db71bd5bcc5978d813997adab010001	\\x8a06604a5634b48e772fa2408f3560029f87c16be9504c4a0a36a63ef195361dca1bd0237d135d97a5ba1933495892c1b5e190481dbd574dd94d81b84e34540b	1664016049000000	1664620849000000	1727692849000000	1822300849000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
394	\\xbb4738e0e1e9468d043441bdcfd8821514bfe52874738f7baaab167f3cf15d1a27e56bf85613d6bc97b5c03a25d32552d673eac81052fc85302a75255118d548	1	0	\\x000000010000000000800003cbc21ff9fa520a2a640b57d821a46b6778e76390118469799b763f5d756e2729e0137c50f5a9460663957ab4fa6e5c6b9a87b94f544de213636cde61362bf96285cd6662d30aa99897be84061bd11d773acb47b5ffe6f2380b95aa1f6b99603074b1996d377accb44d0872d8500dca49f05aee483a39089372516097fff73e65010001	\\x9a34ff0f7ff45b6a5d48b4e73f182b08290fcea4f6fc525f30c34ec7258315b33d23b9efd7f049b2ff66d29fcc44e486579f123ebde2356a585dc66801df2d08	1655553049000000	1656157849000000	1719229849000000	1813837849000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
395	\\xbba320f956d876b2a8b691b7712e644ace7914359ce8b27f6c276c4cb59effca14e6bcc2953fb4208939072148d8e287c37166d27ab28599ad2ee46dce17d688	1	0	\\x000000010000000000800003e01808be81bbccccacdbe09785163ac172b53353d155156f4ca11d0189c32cf8aaf028a2764911f466c6852809321958c62e742a448d866b7da10c6f2d71e163a51805dcc9b0403121302bf71ba3128bdd37f7f176c79a56d2b86cce7b8d030f3d27dacacab9ea7acad4cd1f64495ac5c6a12388a7f37663597b6cf9bf465459010001	\\xc36984c21359245b00beceab08d83f1d5a2496c688c9a185f30a9c86a5fcc91f6d496759dffc9970256f0629e1bf7dc38d64e423f79a3760bc1b862e92db6902	1659180049000000	1659784849000000	1722856849000000	1817464849000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
396	\\xbdbbd0e5b38ae2f2587cb70305286e389e8bacf4d1da5dfc7c49a832d3c932541687273eab1748b384f428d75c4d601c71dd5ebc643f59f37b1d283a5f6006b6	1	0	\\x000000010000000000800003c06817e3a45b0b72ebe31306e759cd745c03485d50791ba8cc2762ceb4d1d00b1042ce92a35e3f6d038aceef1bcecc88f9a466196dec19058497aa8cec4e992d8e3bf01619cfd28fda09b6d2ba561fb5d3cd5b60c72b2fd00521ff59ed7da442b5c66d6ecd0a3283587dfee521e9ba20d224f8c471772ced6702ef675cbe25c5010001	\\xea002ba6387b0317b9ef43c55fb8f57da5d416ea19f34e4cbd7b610dec4f6f3f3d34451b387981632c63950e7cc04ac54e21c145c95b226b5bd1c440bc9ed404	1667038549000000	1667643349000000	1730715349000000	1825323349000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
397	\\xbe1348d41d653dd49654a79fa31b2b0a7b520871fe961e7ece1746fc6d2c7c146a95f11c51ea885ae5f7610979bfb54c1163b32af28e172fef1f300289680e32	1	0	\\x000000010000000000800003cd547c76257b29d9c5a75917a71f609e797b0ae5520e8521e504db0b9858f2f3ecdf0ca3ee818f38a92b40652de0714716d2da73d98f2db665a8cc0f98b5eb415fb184fa94b1d05cc63891a60a7feb364e800852e0f0762fce5410e7206cfda73a27bd1349b2f62e1d18f1e500a35c57d6bcb5b078d9ac31f8faa4935b617bb7010001	\\xcd234c6186a44e46865aff29f8a6df4498da3be96dfafbf45b8608f52ad4d59c93b03e95db16345c56781e26a8a662996cef89f7a4303a1f52a06895f46f6009	1648903549000000	1649508349000000	1712580349000000	1807188349000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
398	\\xc1e726f0c12ba5a911436b203789493ac1cfe46c4cf3d91c4eb41e5fb47f906230cc6e1475bd1763f788b29162718883a9d2ac938d01cacef62a4c5a964d9afb	1	0	\\x000000010000000000800003d1f01531cbec9e4800c8dc71eadc13a5c34e11c1963aeb7f8b08f4be5474d4fa9b72ae12dbe61d459c4d46cb526d10a3b8763d3067c8e5f3ff0da56fc1625e19b5a42430fb2dac03fa539c3939f379f0bc13375d8a65091a87370e8c2840d191203bf735cae21a3738aa0a42c485e8abd12c1b3d19f29f35ccb2ed6ba22cf0a9010001	\\x873800595476122cfe8a27ae5219ae2cb331d9ebbc6b8b5343e46c6082d16ee15a5e824e4154ca4b6b57d6f75138f89b4326c3b5d65389b2bf708334d8fee501	1651926049000000	1652530849000000	1715602849000000	1810210849000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
399	\\xc277c03707ad5f9e524b7b72127299a2142695d21bd60b7d21212fda0402d6c772dd885881f4fe708b8f970355ea4ceddd1ab3f49d5354540079b0063c174737	1	0	\\x000000010000000000800003bbc153ac1d11b4e2d6e56815b3bedc48b86b0db0ec2f316468ff28a5606d8b92f8f59049334125dff3fc21b9202373e6641d68ead962612a3dff8db31e47a346c3f0b9694f2739593180ea6f1e16d43f523e86478c3d234a5278bcff9f2e3c2a7bcf72c2ed43d516924ba1ec2737257487462c7698b053b96fdfe9ae6096cbe1010001	\\xb088842b10150f93d20e319ac51755fef8295e98a84d26c555ec1853b09dad695b151229d6b4e265c5dfe1886e9c903de7f0ba7bdadb703469fcf0d3322f2806	1656762049000000	1657366849000000	1720438849000000	1815046849000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
400	\\xc4bfc76bf20fb904c301a66031c8da34c8f749d127c88e8a88bf88ae940e80f086f7baef0f934e1dfc37968640fe236461b36987ec00b3baae0ddc1d45836018	1	0	\\x000000010000000000800003eabf7c2babd340be2dd169b2713c67f6774e689794efa8319dad0e5aea59fff2bd25c9bf197dcb8c9a1194cf569d9e880a5eefc7cdb43277c24f6f187e725331394813166f8678d0c733a2cbd91674d898787055b856cb000b2e57048ac5ffde7939f0f3d42406c75c282690e673c28bb7d2db8b5f00bc7195a46a12fc80dbcd010001	\\xf7e14abcd758511c9479d4cab4387a7fbf3766f611ca7498fc957e9e7af202e4bf9d1d4e0841fff5c3ea50717772073f23bfd1b3e2792492428c2f8ea7d32d0a	1654948549000000	1655553349000000	1718625349000000	1813233349000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
401	\\xc59f1b69709e17f00fe21436c762c14ccb331a6682fccdccaa60aa206efc4395a988339c7e64d2b227c6df4e311ac062871de6d44f91a5866235747e6fd3f948	1	0	\\x000000010000000000800003a3d95d6c6f326ed84465cfedc364d872e956a70d2cd4775c9327ce5022adf8e050770497a516bb6459aceadc19f4a8eedd99c6e6362c15dfeea7ce15357b1a3d646dd2bf6a86e3b799bac87a954c6e5d77533dec5188eceee8ca5ed77b30bd0b17c49ecf7f307dbf92a7a439b5a2ddafd4547b6d24ab9eb42aff2809c2b71c9d010001	\\x78f1d13e839ed6ec4e54be29350c30eb2ebd64e3373ca1925b3742feba26bad2cfe1dc24cdf1c911b2cb98536774fc88f16b639caba8ad623ea72698f60e0200	1662202549000000	1662807349000000	1725879349000000	1820487349000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
402	\\xccff55fe667a621c8e8a5896e4de234c0971fe53b27a951308412a2e2c45bfb44ba20a461707cfe93f71e12cc1609e6369e1c194f1636126ca31a0d40e86a135	1	0	\\x000000010000000000800003d82b2fa69d5cfdbd3777b953b84e664f9f61cb2b0c1cfeb366349cc4e590026c89cb75aca037fb80a002fe1b38f2bfe1d93e390650644101ef8159ff7ec65bd58926e122832a38b87dc46feb922f32f93b1dda2510320dcdb50d2f9861f404d24c90fc835d3df2609f51bf5922095fd8abcacecc3aa765cc2c2e6eabaa8ec5f9010001	\\x0ce7f7b0cc0db8fc7f0303ed7d17d6cc2f12c21177947bd240a3dc928c174dd569f4be1fa3e479c6d1ad236d75d2eb4a8b08e8945224f5bde6b7b3353392560b	1665225049000000	1665829849000000	1728901849000000	1823509849000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
403	\\xd3e7b241d0a0eac8440a9d3b22c42b5dfaea57391c7d431fb024880b843bfb88088f3f4f9aed2d0e0edc95303dab132a7afbd02443f691077300f9c056dc0b5f	1	0	\\x000000010000000000800003c98410e12d4f6c28d77d1ff3f5f4cace0d2c5a82f2aa9cab14d0319403988ace12f2a1f0a74fdfe8a61360aaa15570aa82048a32442da6455b677103576599df72a5976d4a2c607687d61171da18f659e76d846ff779d9f0148cf5c3727f68c29c8dcdec33600bea9a63362f2ce0def659e034bcb0668fd35b638d72e057aba1010001	\\x5a28b5f7bc0716dafefcd189d56fad0baf3d2c59b76eae09214a05059e93d8b9ec4a0943ef39aeb2d175f23aaa50be0239e8369fde5fe90e3dbf5a15cb37d606	1651926049000000	1652530849000000	1715602849000000	1810210849000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
404	\\xd6af304502f14a193806573dccfdc4c30d8a29903f4e42b616e92cefcde6eed3edc12354a1534b43fd8b30ce31abd7b7d183cca60519810800f7dd016fe258fd	1	0	\\x000000010000000000800003bc3ce08e52d4a321ced91de7012f690dad9e5cfec6fac49a3a62308459869643099932b8682524dad9ea7286a0cb1e5e8d9ed7ed55df6ce7d7f0b9c68ba40908df3ac63d6d293c9edce22933d0367d498bd9a617fb6c19f4a947c8135564188826792b02312e514fb4028eae12459213d117c2f66bcec202a0d44341c77026e1010001	\\x7f5a6a0b82b6dd74b70d64f824cfe142143c55ba1607ca60cdc22892918a8ff258311c82f8bd4029780014d8978e20f0d69652c1b2052a6c5a19cbc7e8aa7d01	1653135049000000	1653739849000000	1716811849000000	1811419849000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
405	\\xd72f0ed9603df274629c01783cfb610d8b63b909ee1beb80b361cf7e97026ae8f768da44099bc9bacee6873de6166517c07dc6d91a37326cef3ccb1e777c8fd5	1	0	\\x000000010000000000800003ad08e913181a29cbad0e8bd10fad4b11f9cdac834793ac84bd32859f55486f5ef6ef10f8e19c7307f26bb65a47bbe8e9e3497ea82dfd416f0a1c4d3dd531017c50e1e9dbe8a75a0bc550866c3d76b61ea7bb22773d0217e296e09436b54612ac42465d6df62ec498def6a7ca3a61bf5a6b986e6a94bb76309b4957b5d8ce008b010001	\\x8d7d0049d7fb9e848b87bd2a76b30393c18d984da8f7f13c2895cfcfb0b0edd38999cf2334d4cef9c252ed01bbb8b00aa0a2218de8fbad3573fb8681100c010e	1662807049000000	1663411849000000	1726483849000000	1821091849000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
406	\\xd813a26ec02a12d5e5ca130d240558b7b9c3a1e5ecbb903635846c67b014ed68b13b55f13f4299220522699597c72ce3856a048dfe0e79aa1a4af607ab52553a	1	0	\\x000000010000000000800003ba0952e9931304a86c79bc8ea2ef4f581d77973fecef669050df246e21886725a99e4aeb5e8a9bc837940e4ee9d9f074f74f12ab9af70d3383425d55be3ff7663d82555a0226da062defdc399d166657eb3868a6a9526150206dc680ac3a466fbe761738d8bfb6d8535e401aefe664c4d56be9bc0feedf45cf602cf319dc7999010001	\\x66d438f6e522f3f3202621d4aba2af9d85d5f3b6fd40bebef54b0362b07a9de02c6aa68be7aa68ff15e42bc42cf80170c99764e036f370de332f7e3f39efcb02	1657971049000000	1658575849000000	1721647849000000	1816255849000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
407	\\xd9cb2ad5baea918713007d07b7484a9bfbf61c1baa0b9eeda29105514b4e1e4e0f9d61fa1e0830d639e4ad841023d3655ac27056287401be5d283bffbe43bc40	1	0	\\x000000010000000000800003e11a29ea575e121bb5264f7eed6f50762a98e1acbd486cbb126286d27a47f808eadbbd0b7f54f930bd760289864bc51a724c13e21c4b4aa37126b71e226be15fc7ef9be81e12996e6f9e6ea7a57ac6e22598dced103a194d334e8a2c0b4478c62d704ade0085f0acd2294eb67b42be064de1c458a60b520c921c94e400bf5a01010001	\\xb959095767520567f4f32a71f7d4409661eac07e16048bc6cd6b2352cda88d7e7d4c887c850ebe09213fccb3d808ce287cfe216addc8e374a9e06cf3d38a370a	1674897049000000	1675501849000000	1738573849000000	1833181849000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
408	\\xd92bfccc02758e1b681f03adec6a4d28e8a2c8d4c8b4359d566f5f8245a6b8fe65a9b4d7bf87843b6416ec79e2ccc29a6ee976847dc3cd8ee3c29f8a4600d793	1	0	\\x000000010000000000800003d3137fb0c02537ee4ddc947457d857abfd3bff68e40fe297bcd69993acb3d549718fbaa993183f792598d630cde06abea0c2c7ae844f0f979dc11d4c83ec785b069b106d2883acbcebc697cb780b4abac4ec193989d0cf3c511e9ed9b5ed93398c871e9e0a96d9386a10f2d8fc6e33a5b146e4d8fee94cd42f85ad6ccdbcb5f9010001	\\xa932aedcc67ea5730f541502493a1cada969ca7b5db91ae4c6d45c1fd8632bbe390db03365019c6c9b5af1051d7a986b8a73cee5544ab321a8cb35eeeac3160d	1667643049000000	1668247849000000	1731319849000000	1825927849000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
409	\\xdbb37fd15dc49e347414e7173e5f2b565c307be0fd93571bdffc1dcd1caa1e07067cc832a0f724071b423636ba07d2e4b8c04a25e71798361a21793a18fa6bdc	1	0	\\x000000010000000000800003b5eb5c6182f8111b8a34c4d721620721ecbf56576af165c82e3c2e206ad0563484c84d90e9c1b2a359e910130d9442cd49015310669a0a5a96cc38505a08470c15abeaefa5560b5c3864913707723bf9106a8ea6adee395452a7561e0e84cad4e1505637dc8324e063c46e48b491250404976625eaf603c738cac5a1c0c0be55010001	\\x724c0a576f75ab4a1b30c669bdfe784504ea63e48adbee7c5ee8121a02391626f422e4b0596fd1bde6a6774f06eaaf637b7b5648309ed164b4c21e1fa94b1b0b	1664016049000000	1664620849000000	1727692849000000	1822300849000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
410	\\xddbbfa29a285cfe75986795b8fe01990b26ecd53b9bd00ec2c24de8b82a27bbf96e64e1e2fb9652b122fbdb6737a61f7a30c7a4d4473ecb381fccdad1e7a216e	1	0	\\x000000010000000000800003f57f3754b2c20f1acf4ca97e1fffebb3ab69c6161fa6c2a2ded26664ef3bf24d21b83a6735bcbb8856f7f54b2447c1be5ff86f42728d93ac294575f2f26e7eb245786fa0ea530cb066bd49aceee05e85162ca539680a78cdd59428af41cd200c6de492bd9a5b02fc840c64de1c5ad5def10ea7d6e32f1b772c2962482f33bf83010001	\\x3d69f4d43e6351cf2474705bcebd2237c528f7f915667906c3c19c25c3478a1fe9de63908fae2f93391973dfb62e3092988b7ffae69cd3797fffae70f15bc209	1657971049000000	1658575849000000	1721647849000000	1816255849000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
411	\\xe0f75891b9fd1eac019f5ff56d61bf0ed1d56e09bb076914e7ec8297045b7f279063f969ac333df40a71fb6c426bd0a13e00be161a1383ad05cdb563e5c227c4	1	0	\\x000000010000000000800003b2be6327de09c1afd1c18984dd40deea732f9217d125966a378b382438ff413879c17b4325e3b66630794efba774a78645bf8e65a1e071cc6089f2f9dd32b3d7c124092f501220567ca8df794936a101a4a15720bd31fd37fa9f352c6e315a14bef57be85882a844c0fda3826b88dc206e9baa7d546e85ddbc06e342ec812717010001	\\xf25d31e3b39282746df28c52ed0278d277497686e1cff0264d4b6db10ee9823bc3f1c6a2cd30ebf01665d1855164c2ef1829db4d52311cc526b402f2b9211e02	1675501549000000	1676106349000000	1739178349000000	1833786349000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
412	\\xe25bb511c5e1ca93b371e64f3a3b387703d23a53b6fb6de9b14fca92933a052c50c8302168ba4931eff1625bfe2ed7da2c40f725ae667675c55de8f73e365aaf	1	0	\\x000000010000000000800003cae7306a2ba63f3a6ba4ff513af65f54648855cbde823173a331b5bd60f015e3e660a0bf10b620adfeb54f5fa1417b90f874544f83d69f6d2100d2bad5f8de64aa352d4e4f2ba7e2c01d569096f89e27e4d317c6be424e164ffddaf8a75f70e1d70974944b3700925586aaf25974d596d57e4bdc941437c9e10b7800fcd791c3010001	\\x02b8f21e170a6a1385ae4e24ea533ee7729058d2ecabb1c7019a2d73ac1c3635749420d6406b190d6cb72f1bf73f01403edb79e6aeb31605bb0dd9c0aa6db807	1668247549000000	1668852349000000	1731924349000000	1826532349000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
413	\\xe52ffae22bd3868979f259ab29df0f052dac1abac4c7a6fd404e709dae89434b47a2a2763d82f44a589b64c58e7a7438c95a41bf58940f6d087b9937fb1b95b7	1	0	\\x000000010000000000800003d32bc3150a0bd9c0c954efdbbe0830829573c5488948864daa83b220cfd0ef52d12ec9cb9cb5b5fe5655152957d85edd95c16b7953da0cfaca555239d989ffa85fda64b0ae322693ab4ac5592767f0a0403cdef6aef427cd54288e394d9a0b980707b77f9f51084812aa977b934b5572d233ad4a712e7277c96ed57b1a8b1767010001	\\xde09d8ead6ecefdfb8930379c405835d24c698fc25dd44ecbb1c20bf492c96d6589ee2219105be12362f66cb5c55aba8bca1f58234eaa6c725b66358687ff109	1654948549000000	1655553349000000	1718625349000000	1813233349000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
414	\\xe52f5a2cf639d23960edc0210fce1990bb060c0ac2bf7f3e33d375508b7df6e9584158e4e05f6eae12e724697667a92557902a13bef776fdb7e21f1116bcb29e	1	0	\\x000000010000000000800003b63837eecdfbca957a3c0e7a773a40350ec7836e8ca0a5414ca6878b4221ac7b8b81f97389d2f0b0136cef4dcd1e749884d7cf5e99cf896d7d60e6558b29fa967a5063dd0315fa527b24293afe9d458adcaef537c63d432202167b5c6e2e14c475373aebebf314f8bedf9c8b05bbf264b0b2924e05dc4a85d9cf9a58b8b7f535010001	\\x4cb4e7a7bd3226a976649828ac9ff91a3903a33ab8fc4acfc45c12abb7bc06d177541d0f769a152d632d172e2a5fe2b6ce46b38a05abbe76e35dda8f71552506	1677919549000000	1678524349000000	1741596349000000	1836204349000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
415	\\xe6af221b11a5217b0ddcc7e209427317e99904353eba7402f753eecb22b15bab702e7ef413c3b331d04831fa99ddd964228cb6414e634106a6979e16389866a2	1	0	\\x000000010000000000800003c848db1797266e51eb0893c70f53ffce66c33d9a5df468e77486f18071d437cb96700142f613c19e3e75f4f013f8ef2d243044977170e9130c8955ce4a0e23cb7704c54ffefc4a3c54699c05afc46b068896dbfa5f50b869c0e001811e73cd4d00bb1773736cdd53e4d1773aa45ab61481a6f5e44c69554d67abf7ab30304a13010001	\\x17af11220ee6e26843001fc549d0bd070f12575c0aab4ba07e705a246f7ba6992977898e2fd963f18ca009f7f0cfb89dcff1c9de17729fde281d1b6b3f36fd0f	1670061049000000	1670665849000000	1733737849000000	1828345849000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
416	\\xec4fd445a194b927bd73539c2a3f6f39fec9b41c96102c2a3427a7febd520faf6d23f6f7f946abffceeedb060fb348c5338f7924d56c57d00746b89d09718877	1	0	\\x000000010000000000800003bf06885e4693e32d9991d2319c89201ce926a4f030c257739e85a84aaa82414f0ac5b708aa9acda91ec7e40c7a5f01c2ec7df5a27eecd7ea5a75957bc6ea167a0320dbf257accf5ef739615bd73b5aefc0e17abcd456b6d7c3a078f9df7434a29a3bfa7a6652219929659caa407164efe46d8d8d568a261255f5833b62e493b9010001	\\xe6114e9ffad61e22e27fd4a909e47915cb80c3373f7a3d29690f21bfea9b267ad66af855207bacf206c4f88a08556f2497f2282313166292004d9debe5b3bb0b	1656157549000000	1656762349000000	1719834349000000	1814442349000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
417	\\xed17bc97ca19380c429a8050b1e12e1ac1dce47ad03e16ba2c4b9ff8f12b995fe8fefc9830f3f71a26fd654f6385b8592400001b324375f4d967f933801a3932	1	0	\\x000000010000000000800003c2e2dd4db4e2572128a8a708af492d20e1b015d4c844caa2a9fac1e581371e2e99790b35432305e8da0565a34739f82fc52379966bb4960722924378d47e4c54d734549553b431702dbf763e08dd83fc8d7019ec3725e12adea321985cf706345b28bbf188a4337b26c71b2a241274d43efae8434a741dba2b8c331bb98f3117010001	\\x060e63d02c51b6709ac6fbf2a0402ed858680a5a24c17e2ad42f1f0afe422302e5faeea017be89ffb4440f6f8ed8a6528a67c580c47ae1bbfd775cdbed0dff0c	1676106049000000	1676710849000000	1739782849000000	1834390849000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
418	\\xeddb40b7d4bec1871fb039ad5957c0836ce606dfedd26436066962f8649822c5e7de73331cc96c463a9fb841257431e31b570169fc3162a38687576bc9887da1	1	0	\\x000000010000000000800003b1390c14adaa3079abad4e0dc92e719aac478f452e41b04975de9db1c7627336e8e210b45f528beab414f670e10b37fcfa1b35a710222e73aee14821d4910fc3a6c42964420de5122195bb966f0b62de909304827dc742789bea15212aa920d21d885881bda9d12b0ee308ec8694ae46ed1bbe921e4888f1d12aaa304d6a8b2d010001	\\x388352b5cd1000033e0e72237c0dc09aa9f90275172b2b03c5bb6a17472b87ab3bb659eb89c8e7120bc97ad1f40c762757851fa3d2d46789b0345a5081faf505	1647694549000000	1648299349000000	1711371349000000	1805979349000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
419	\\xeee7490c43b28904fca9b06d3c56ddd3625470415df531ef46cb06ff3946600ff33e961391b1f883d56285462fcde19099ff3742134657b99ab32a0de60b705e	1	0	\\x000000010000000000800003b8ec3d853b01658ede9860402fc72b3446fb47eee52fd16659e41db5a02b9b2ee4706fce6c14e245fd0e5c2b2cf4fcfc02661378adb71cc30282cd6fdf9c6e2dab05a06ef5934cf035c6954d6c5f58d453f6ce61b5a3eb13bb852a1fe4162ab3a18f9e37fbb7c9c3b3640f9f123d10bc6b62fa7e65ba2a1ec093996b5752c789010001	\\xd15c9b99ca7cc7206b89199bf2114606729a32927c9907e9b9ae39e4693086de652ea608c14df47b03ef780c7d227d84f2d5a3cb5150331a89a452e9a358b005	1666434049000000	1667038849000000	1730110849000000	1824718849000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
420	\\xeeaf5d0b5b50db12c2b91b3c396015ca2550e232e096c6a6966080bc293aaec86eedd564d0d0c09f12252f39945b0e9333219d6b3ffad2c359114e97bb1b8557	1	0	\\x000000010000000000800003e16fbdfe51f21d4e088061fdd428177089d7ed6085c95322733c0be717515994393922b4d48c69c69b87475c9705e97add8b0783d3535236613b1a0c04be85b343c565bd47c13224d3ba550e50f519d37f1deda75809a7eb01368fade8f3720aadf4a63625502b14ec37e19eb6303039d16e1b4e719e278cd4edbac91c9d3b8f010001	\\xbeb79cb40e68fa7311577396a56ba168cfc6059392af641e23d1c751b1e8630291f796646b0453214911e4b5fc2da3184ff3b68a4c5117790886c884b920080d	1663411549000000	1664016349000000	1727088349000000	1821696349000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
421	\\xefb749e25b7ed161e36cf2a6b78aece47e7eaa67c1930313263c33bf08c1af26622b1300fdeefdd136be5c7f674ea12523fe9f9d49838b6a556d57f1bb7b8587	1	0	\\x000000010000000000800003b719e7d973ae00baa602e7afecd632d21779a09910bba6ea8c9957494ca2481ad26c4a4f320fa13043f54186410a6dde30fa08993e3f665a245611c186003b849dd79be385546e60d5f7d25342d922dbd5b26de6a7984dc53313dd9cc34a246c8e89208323d7d877a696667f548b02ff59fbd282369aaaac6f911b62c1768725010001	\\x55620cb69442c2e1281b8903ff75f264c4ecbe5ab58eaf888228e45c4ca454cf023ba7bb95491161c597be29536a3fc50b4b4bc4b5ee1edcb2097669f10f6104	1654948549000000	1655553349000000	1718625349000000	1813233349000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
422	\\xeff700a45d804f52ea1fe091c2ea4a93f6c22590ecfe80d946fc22765fb1a0429afe354c3d338f7289bd950f3e9a643552db20ce11784e7e95782581b77fee2c	1	0	\\x000000010000000000800003a98fcf002d8a90fa001091fe5d416973076b6d7ffdbbfabd0af8ae7dd8e297590e64758676c438fe4a998efe1eb2bd8630bf87e8bd8c93c30d881092d84438f8b811743fd96227c7ccb87dc12716416b76609cdde04af64026207ebbbffc617183c0fe6ab9229a19d37477f2dd17a6429ecf54d9e9bb87481437d50ba79b1f09010001	\\x7485f441280cb1e43d6171456f9f267a3c4aea3f12028404774a499d7a924e6509b32bdeee871ea61a532293b4c616e721f6955322f9a37377e3d806576e140a	1677919549000000	1678524349000000	1741596349000000	1836204349000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
423	\\xfbafbb5fc0301a5c609d4dbc621641fea34ff39d985b93a7267d2d71705cb5481cea0793701f0e0c6ab6d96a25bde6fec15b1c69863a337b0c70ac615873399a	1	0	\\x000000010000000000800003a2a2048fd1ef4a7e7e90aa2922bd9fd8b5e7b3c124972010d13f5a46b3d208af1684dcd0feba0b6398c579f82d9c8c998e41bd0c52cf6bcee7c231f340c3b69dd51f6214fe8712b8052b98dd53cb685d03d52b5714bedcaa19c56c7374141741b68f116ee55a09211e1fa4a148d3fbb6bfa6f0792b633a903dd18a5cc7a49fab010001	\\x8751d0894df9a198247c8adb2628416e18d1fa113fbeaf63a4928ce2e9b40404abf6dd2d7b7a2c62d8fcf1986374f0ebd597f2d49d9b9c8975f2fa935cca5006	1656762049000000	1657366849000000	1720438849000000	1815046849000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
424	\\xfd8f8a5bf56531e9f3a04278c2a3cad5643453cebff7fa6c3090e3ac1e752cd3268d807c7162d42290368a18d7f2d49781b580180c6f62c961a9b152e88d5f70	1	0	\\x000000010000000000800003dbdd0721d9fc1a3897a0719d5d0304d92a1c7cbed5a383f10673e05e507f94ca81302d6aa7751a021307016d095181bb36fe9ad8ac726a8bfc49a7f635fae587fcad79ceab944ef99e5853403079122cca7dc9dc7ba5496f4d74affc594c7cd62d1a52f12bb2df75d3cd2296dfafaf2c5565ebd929bfa3d25d69870eb381f0b5010001	\\xb77711c282928ebf6b915ca1cf2e05d33faa4e384e942ff5ab4ca89c0c0534d9e76fb452fcbae88139815bc420b597f51c0bb0528fed8b4463b1a3ad2d14f703	1650112549000000	1650717349000000	1713789349000000	1808397349000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\xa16c5cfed3956325f6eecb00f848eff541a89f48c4901c59d5948551563c325a	1	\\x55d1e0b30de3acc24c90b8c8daf8067557a2e6735819869a471ac496fd86c8a2682a2c3b5cf8f10b2d232e58b2c62a679ad9675b3ef0c6717f03f5b2c14f614a	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x6ce8c8d7a5c839bb6e93c8cc120ba3c8fcc42473b22d550dcdb1c1dd605d766a390afc28c470ebc033001764143c25bbe1d64e758218f53f1207a3621492301f	1647694567000000	1647695464000000	1647695464000000	3	98000000	\\xef160ebe36cd15678403d431781b69467a9a68ed4734eb3efbf6b5bfd731b5f6	\\x49c1d6af1a5a0d1d96417af61d46fe4c8e6df18862e3b6f2ddb917d8dcec0ff7	\\xf51f3b88cec3157273b4123ecc6e2909ef1c7614d279c076c32d1dab41564745f292bdf371b56701ba1b4a6ec03ce212a8b3ce934a74f98ef9749e50cd26b906	\\xa1f7e8f207772bb43cff98cf5b263f95c973d65f8d2e1f0911533057f56daee4	\\x40f07a1ffd7f00005ff07a1ffd7f00007ff07a1ffd7f000040f07a1ffd7f00007ff07a1ffd7f00000000000000000000000000000000000000cbb461536c138f
\\xa16c5cfed3956325f6eecb00f848eff541a89f48c4901c59d5948551563c325a	2	\\x8f6eb5dc689a8be1fb363def3951752e7fc10db0aa559a81e0ce81c358d9ca09fdb796131cdf0ad44ea999071bc0e97c787b04ada9392b499ca9fd105374054e	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x6ce8c8d7a5c839bb6e93c8cc120ba3c8fcc42473b22d550dcdb1c1dd605d766a390afc28c470ebc033001764143c25bbe1d64e758218f53f1207a3621492301f	1647694573000000	1647695471000000	1647695471000000	6	99000000	\\x7c7a5199b4d1b4eaec6a7d07ec7b3e1090b46de0a7f07805e5dc18cb948fa8f8	\\x49c1d6af1a5a0d1d96417af61d46fe4c8e6df18862e3b6f2ddb917d8dcec0ff7	\\x1fd02eee9a7ba58ea7e22cc5b5b53e7d003723b980f9ed8ec0cbb8d4b08bf22e8f194577e80876d15420adedb6396fe76a1fc220b7230678529815878ee8450b	\\xa1f7e8f207772bb43cff98cf5b263f95c973d65f8d2e1f0911533057f56daee4	\\x40f07a1ffd7f00005ff07a1ffd7f00007ff07a1ffd7f000040f07a1ffd7f00007ff07a1ffd7f00000000000000000000000000000000000000cbb461536c138f
\\xa16c5cfed3956325f6eecb00f848eff541a89f48c4901c59d5948551563c325a	3	\\xd333f065e11394734a73f635ee5c26ccce8e4c703481a49564d3676adafdb5286a85580fb570a78d13e4b877fadf028357406f1def611c8d34a8422c621a62b1	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x6ce8c8d7a5c839bb6e93c8cc120ba3c8fcc42473b22d550dcdb1c1dd605d766a390afc28c470ebc033001764143c25bbe1d64e758218f53f1207a3621492301f	1647694579000000	1647695477000000	1647695477000000	2	99000000	\\x7df0febbd6ab4363355b68427a16e5c05345124c644e1199c4aa42ef93a799b7	\\x49c1d6af1a5a0d1d96417af61d46fe4c8e6df18862e3b6f2ddb917d8dcec0ff7	\\x6574a4a4dc39ff24e3b4df4075bcaec4f584e56357b760c4e16024943b9f9b4d40bcf5da900b2308dc6ed1fe13372e51eb9155fbed80b964ed9b71754f600502	\\xa1f7e8f207772bb43cff98cf5b263f95c973d65f8d2e1f0911533057f56daee4	\\x40f07a1ffd7f00005ff07a1ffd7f00007ff07a1ffd7f000040f07a1ffd7f00007ff07a1ffd7f00000000000000000000000000000000000000cbb461536c138f
\.


--
-- Data for Name: deposits_by_coin_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_by_coin_default (deposit_serial_id, shard, coin_pub) FROM stdin;
1	1426881619	\\xef160ebe36cd15678403d431781b69467a9a68ed4734eb3efbf6b5bfd731b5f6
2	1426881619	\\x7c7a5199b4d1b4eaec6a7d07ec7b3e1090b46de0a7f07805e5dc18cb948fa8f8
3	1426881619	\\x7df0febbd6ab4363355b68427a16e5c05345124c644e1199c4aa42ef93a799b7
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, tiny, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	1426881619	\\xef160ebe36cd15678403d431781b69467a9a68ed4734eb3efbf6b5bfd731b5f6	1	4	0	1647694564000000	1647694567000000	1647695464000000	1647695464000000	\\x49c1d6af1a5a0d1d96417af61d46fe4c8e6df18862e3b6f2ddb917d8dcec0ff7	\\x55d1e0b30de3acc24c90b8c8daf8067557a2e6735819869a471ac496fd86c8a2682a2c3b5cf8f10b2d232e58b2c62a679ad9675b3ef0c6717f03f5b2c14f614a	\\x62874263c328f3f57c81362152a3e2d4e11826b6d3f13308366351f2797cea6df89dcb28ea04c2b732e571f27bf6421c9e1cfd52231cbb11404def1a2d1b2702	\\x27bda7056c14c4f68ea42bf28b900f80	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
2	1426881619	\\x7c7a5199b4d1b4eaec6a7d07ec7b3e1090b46de0a7f07805e5dc18cb948fa8f8	3	7	0	1647694571000000	1647694573000000	1647695471000000	1647695471000000	\\x49c1d6af1a5a0d1d96417af61d46fe4c8e6df18862e3b6f2ddb917d8dcec0ff7	\\x8f6eb5dc689a8be1fb363def3951752e7fc10db0aa559a81e0ce81c358d9ca09fdb796131cdf0ad44ea999071bc0e97c787b04ada9392b499ca9fd105374054e	\\x93ee1b6a72c8ece744b26f8088ca23f9322013cd737e67848f82f2362384d94ad7154449fdac41deb7821bcc700dcb49e5e2dd0baf3befd102818729758e8d0f	\\x27bda7056c14c4f68ea42bf28b900f80	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
3	1426881619	\\x7df0febbd6ab4363355b68427a16e5c05345124c644e1199c4aa42ef93a799b7	6	3	0	1647694577000000	1647694579000000	1647695477000000	1647695477000000	\\x49c1d6af1a5a0d1d96417af61d46fe4c8e6df18862e3b6f2ddb917d8dcec0ff7	\\xd333f065e11394734a73f635ee5c26ccce8e4c703481a49564d3676adafdb5286a85580fb570a78d13e4b877fadf028357406f1def611c8d34a8422c621a62b1	\\xb35cf8c232acdf59395b05c3b9c3f9b05e67413fc1d4c26c2bd3ec8818221bc747c261925bb3b8423a14847d30c933bdf5884cf23c4ae09c381ebb324bd95c0c	\\x27bda7056c14c4f68ea42bf28b900f80	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
\.


--
-- Data for Name: django_content_type; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.django_content_type (id, app_label, model) FROM stdin;
1	auth	permission
2	auth	group
3	auth	user
4	contenttypes	contenttype
5	sessions	session
6	app	bankaccount
7	app	talerwithdrawoperation
8	app	banktransaction
\.


--
-- Data for Name: django_migrations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.django_migrations (id, app, name, applied) FROM stdin;
1	contenttypes	0001_initial	2022-03-19 13:55:49.377214+01
2	auth	0001_initial	2022-03-19 13:55:49.538364+01
3	app	0001_initial	2022-03-19 13:55:49.662439+01
4	contenttypes	0002_remove_content_type_name	2022-03-19 13:55:49.67336+01
5	auth	0002_alter_permission_name_max_length	2022-03-19 13:55:49.681217+01
6	auth	0003_alter_user_email_max_length	2022-03-19 13:55:49.688316+01
7	auth	0004_alter_user_username_opts	2022-03-19 13:55:49.695919+01
8	auth	0005_alter_user_last_login_null	2022-03-19 13:55:49.70278+01
9	auth	0006_require_contenttypes_0002	2022-03-19 13:55:49.705921+01
10	auth	0007_alter_validators_add_error_messages	2022-03-19 13:55:49.71247+01
11	auth	0008_alter_user_username_max_length	2022-03-19 13:55:49.726773+01
12	auth	0009_alter_user_last_name_max_length	2022-03-19 13:55:49.73328+01
13	auth	0010_alter_group_name_max_length	2022-03-19 13:55:49.74193+01
14	auth	0011_update_proxy_permissions	2022-03-19 13:55:49.750559+01
15	auth	0012_alter_user_first_name_max_length	2022-03-19 13:55:49.757322+01
16	sessions	0001_initial	2022-03-19 13:55:49.789401+01
\.


--
-- Data for Name: django_session; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.django_session (session_key, session_data, expire_date) FROM stdin;
\.


--
-- Data for Name: exchange_sign_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.exchange_sign_keys (esk_serial, exchange_pub, master_sig, valid_from, expire_sign, expire_legal) FROM stdin;
1	\\x80276108b23efae2afc5cad6b4c106d01803cb19d53b20065233ece8d664c36b	\\xb8257716b544aa40ee4cca6d20b5b4dcbe73a57feb1ffc0b498cf8721a8fe83dbeeeb2d32e6f1744108004aa2c322d51e3c7713239f00aab818eab305741410f	1654951849000000	1662209449000000	1664628649000000
2	\\xa1f7e8f207772bb43cff98cf5b263f95c973d65f8d2e1f0911533057f56daee4	\\xa843f5cae36c57b13eafa8d14eafa5421a8cc163748679d5591c428df8e04c5e30f8eadf5430bb0e70b3522ed38a44347483e7be05b39ebe0419d94762ca450d	1647694549000000	1654952149000000	1657371349000000
3	\\x87bf59f4d9048203fdea5d984fe3adbd473cca5f46d0d102bedb584ce3d50fac	\\xdd921ffd2bd1639f3cdbb9b9a5e71751ede0c960c0128863c3d9545d69411b3088364f55beb902bd15be7d46ad336a099dbeb841f952fd04f5a257269622790a	1662209149000000	1669466749000000	1671885949000000
4	\\xc81f4465a151f0b4b105a783e1047a8be051d2ff801e4b5d87eedb4e08c31c0c	\\x51aa5cfe59fe8b752b0eae32e14c65452bac099a06fd56ab34b6d5605aa7cf70aa44f4adff94bbed765adb58ced1dd4a8d0ef6e50a7079f3a5e7f07a20989b07	1669466449000000	1676724049000000	1679143249000000
5	\\x7014a47b5b8bb66933f4219d8483e063823f6f9ae26d5ec237e2a62120b7e9dc	\\xd5b52f74d2ce5f7a383886398122d54cdaeb6b9b2a18bd71700b61ea4400a21ff8b905d968e49e60c01ef400d0aae8a54d7744343ba2e3d8503769725d44500c	1676723749000000	1683981349000000	1686400549000000
\.


--
-- Data for Name: extension_details; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.extension_details (extension_details_serial_id, extension_options) FROM stdin;
\.


--
-- Data for Name: extensions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.extensions (extension_id, name, config) FROM stdin;
\.


--
-- Data for Name: global_fee; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.global_fee (global_fee_serial, start_date, end_date, history_fee_val, history_fee_frac, kyc_fee_val, kyc_fee_frac, account_fee_val, account_fee_frac, purse_fee_val, purse_fee_frac, purse_timeout, kyc_timeout, history_expiration, purse_account_limit, master_sig) FROM stdin;
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\xe35a442f6ebcb57c8fc0c2d372f0de9775dfd01f8a343ae17f98ebbdf7b21fb0325b4a20d276dd9bae440e7fdbb743829bff4548ba4a739d30dbd12ba59e1807
\.


--
-- Data for Name: known_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins_default (known_coin_id, denominations_serial, coin_pub, age_commitment_hash, denom_sig, remaining_val, remaining_frac) FROM stdin;
1	162	\\xef160ebe36cd15678403d431781b69467a9a68ed4734eb3efbf6b5bfd731b5f6	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000008f4be4b1020c62822312b8978ee69cd3293c3e7e62206ee907bbce9855f5ed32ecae2c91dbad71fab094f85ab49f010a3fb78d86867209b3ecd6b1dbb4afc9b5b2256f9876448be7eaaff6d7b41e2a015e8275f65d9928f6b11fb542d852a5c287f6cec821ed520280984921b4f76342908356dbf902d97c8fb35a482dc139a7	0	0
3	62	\\x7c7a5199b4d1b4eaec6a7d07ec7b3e1090b46de0a7f07805e5dc18cb948fa8f8	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000a1fea3fe5188fedf8bf0e5dd976d72add195afe65c0b0788e4ab9295275375ba37fb5bd89b67dfe66adb4d766684d8f184f50f97779e199c2a2b50536485f56715b47446d07522ab776d2dd0e05e141678192896eacdeddf2922c4592d5b9682015961da8dc77b362a3508249bfcf37234222d9243e9530ce8cffd0ea9e3e31f	0	1000000
6	418	\\x7df0febbd6ab4363355b68427a16e5c05345124c644e1199c4aa42ef93a799b7	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000008c10086ac4fadec838b5d9429a17eb3ed2641b9fd0c34629fe5beb3a9ee13fd0b9150ccf0c70ce35e93b77dd6cef378f26eb89515f32c27cf006688bc6d3e8e919a88bd6078d85e5ae6df64a9cd3b6559afd1ddbb4daf9e669b2cbb212d01dc12b3d8331996c9eb66bf08f533fed5f383b1fde74ec6cd7f9503790faf5617a9c	0	1000000
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x6ce8c8d7a5c839bb6e93c8cc120ba3c8fcc42473b22d550dcdb1c1dd605d766a390afc28c470ebc033001764143c25bbe1d64e758218f53f1207a3621492301f	\\x27bda7056c14c4f68ea42bf28b900f80	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.078-02MFHQF8AKY6W	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634373639353436343030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634373639353436343030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22444b4d43484e58355330575650564d4b5333363134325833533359433839334b5038504e41334544503730585452325845534e334a3251573533323731545930364330314553304d37474a5651524550395354523436374e3757393046385632324a3933303752222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3037382d30324d4648514638414b593657222c2274696d657374616d70223a7b22745f73223a313634373639343536342c22745f6d73223a313634373639343536343030307d2c227061795f646561646c696e65223a7b22745f73223a313634373639383136342c22745f6d73223a313634373639383136343030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224d355035535a504b4a4e484a4258514553433046474a3746594e305448375438524a38315250454e4a4a324e324e485736394430227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2239373058444252544238364856354a314642563154485159394a37365657433843424856445750585134425848513743315a5647222c226e6f6e6365223a22483930315451544339564a51353158473446595737484646484e59594333534441304b3746594b3930385748564139344d505030227d	\\x55d1e0b30de3acc24c90b8c8daf8067557a2e6735819869a471ac496fd86c8a2682a2c3b5cf8f10b2d232e58b2c62a679ad9675b3ef0c6717f03f5b2c14f614a	1647694564000000	1647698164000000	1647695464000000	t	f	taler://fulfillment-success/thx		\\x48546fabf3afb053740613f81f4553ca
2	1	2022.078-03CD61R1XBMR6	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634373639353437313030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634373639353437313030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22444b4d43484e58355330575650564d4b5333363134325833533359433839334b5038504e41334544503730585452325845534e334a3251573533323731545930364330314553304d37474a5651524550395354523436374e3757393046385632324a3933303752222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3037382d303343443631523158424d5236222c2274696d657374616d70223a7b22745f73223a313634373639343537312c22745f6d73223a313634373639343537313030307d2c227061795f646561646c696e65223a7b22745f73223a313634373639383137312c22745f6d73223a313634373639383137313030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224d355035535a504b4a4e484a4258514553433046474a3746594e305448375438524a38315250454e4a4a324e324e485736394430227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2239373058444252544238364856354a314642563154485159394a37365657433843424856445750585134425848513743315a5647222c226e6f6e6365223a22594a41515a4a42453859315033535a5242544b4a3343345a54594441313156365a344b32334a4a524d323431504a344e424e3530227d	\\x8f6eb5dc689a8be1fb363def3951752e7fc10db0aa559a81e0ce81c358d9ca09fdb796131cdf0ad44ea999071bc0e97c787b04ada9392b499ca9fd105374054e	1647694571000000	1647698171000000	1647695471000000	t	f	taler://fulfillment-success/thx		\\x49a2159cebeba2d33a67a9610258bc83
3	1	2022.078-020ACBV1839SE	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634373639353437373030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634373639353437373030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22444b4d43484e58355330575650564d4b5333363134325833533359433839334b5038504e41334544503730585452325845534e334a3251573533323731545930364330314553304d37474a5651524550395354523436374e3757393046385632324a3933303752222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3037382d30323041434256313833395345222c2274696d657374616d70223a7b22745f73223a313634373639343537372c22745f6d73223a313634373639343537373030307d2c227061795f646561646c696e65223a7b22745f73223a313634373639383137372c22745f6d73223a313634373639383137373030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224d355035535a504b4a4e484a4258514553433046474a3746594e305448375438524a38315250454e4a4a324e324e485736394430227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2239373058444252544238364856354a314642563154485159394a37365657433843424856445750585134425848513743315a5647222c226e6f6e6365223a22305847305750485a393044394b52474733584444373331423857455130374839445a5242594232364836395748595943345a5247227d	\\xd333f065e11394734a73f635ee5c26ccce8e4c703481a49564d3676adafdb5286a85580fb570a78d13e4b877fadf028357406f1def611c8d34a8422c621a62b1	1647694577000000	1647698177000000	1647695477000000	t	f	taler://fulfillment-success/thx		\\x599df823330061526fa162168fb4d105
\.


--
-- Data for Name: merchant_deposit_to_transfer; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposit_to_transfer (deposit_serial, coin_contribution_value_val, coin_contribution_value_frac, credit_serial, execution_time, signkey_serial, exchange_sig) FROM stdin;
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposits (deposit_serial, order_serial, deposit_timestamp, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_serial, exchange_sig, account_serial) FROM stdin;
1	1	1647694567000000	\\xef160ebe36cd15678403d431781b69467a9a68ed4734eb3efbf6b5bfd731b5f6	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	2	\\xf51f3b88cec3157273b4123ecc6e2909ef1c7614d279c076c32d1dab41564745f292bdf371b56701ba1b4a6ec03ce212a8b3ce934a74f98ef9749e50cd26b906	1
2	2	1647694573000000	\\x7c7a5199b4d1b4eaec6a7d07ec7b3e1090b46de0a7f07805e5dc18cb948fa8f8	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	2	\\x1fd02eee9a7ba58ea7e22cc5b5b53e7d003723b980f9ed8ec0cbb8d4b08bf22e8f194577e80876d15420adedb6396fe76a1fc220b7230678529815878ee8450b	1
3	3	1647694579000000	\\x7df0febbd6ab4363355b68427a16e5c05345124c644e1199c4aa42ef93a799b7	http://localhost:8081/	3	0	0	1000000	0	1000000	0	1000000	2	\\x6574a4a4dc39ff24e3b4df4075bcaec4f584e56357b760c4e16024943b9f9b4d40bcf5da900b2308dc6ed1fe13372e51eb9155fbed80b964ed9b71754f600502	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xa16c5cfed3956325f6eecb00f848eff541a89f48c4901c59d5948551563c325a	\\x80276108b23efae2afc5cad6b4c106d01803cb19d53b20065233ece8d664c36b	1654951849000000	1662209449000000	1664628649000000	\\xb8257716b544aa40ee4cca6d20b5b4dcbe73a57feb1ffc0b498cf8721a8fe83dbeeeb2d32e6f1744108004aa2c322d51e3c7713239f00aab818eab305741410f
2	\\xa16c5cfed3956325f6eecb00f848eff541a89f48c4901c59d5948551563c325a	\\xa1f7e8f207772bb43cff98cf5b263f95c973d65f8d2e1f0911533057f56daee4	1647694549000000	1654952149000000	1657371349000000	\\xa843f5cae36c57b13eafa8d14eafa5421a8cc163748679d5591c428df8e04c5e30f8eadf5430bb0e70b3522ed38a44347483e7be05b39ebe0419d94762ca450d
3	\\xa16c5cfed3956325f6eecb00f848eff541a89f48c4901c59d5948551563c325a	\\x87bf59f4d9048203fdea5d984fe3adbd473cca5f46d0d102bedb584ce3d50fac	1662209149000000	1669466749000000	1671885949000000	\\xdd921ffd2bd1639f3cdbb9b9a5e71751ede0c960c0128863c3d9545d69411b3088364f55beb902bd15be7d46ad336a099dbeb841f952fd04f5a257269622790a
4	\\xa16c5cfed3956325f6eecb00f848eff541a89f48c4901c59d5948551563c325a	\\xc81f4465a151f0b4b105a783e1047a8be051d2ff801e4b5d87eedb4e08c31c0c	1669466449000000	1676724049000000	1679143249000000	\\x51aa5cfe59fe8b752b0eae32e14c65452bac099a06fd56ab34b6d5605aa7cf70aa44f4adff94bbed765adb58ced1dd4a8d0ef6e50a7079f3a5e7f07a20989b07
5	\\xa16c5cfed3956325f6eecb00f848eff541a89f48c4901c59d5948551563c325a	\\x7014a47b5b8bb66933f4219d8483e063823f6f9ae26d5ec237e2a62120b7e9dc	1676723749000000	1683981349000000	1686400549000000	\\xd5b52f74d2ce5f7a383886398122d54cdaeb6b9b2a18bd71700b61ea4400a21ff8b905d968e49e60c01ef400d0aae8a54d7744343ba2e3d8503769725d44500c
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\xa16c5cfed3956325f6eecb00f848eff541a89f48c4901c59d5948551563c325a	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x7855d90d7f297e273467620a4766b196428ea382dc748d26490a479015f80359ec7830ab208f921ce3ee431949584900bde921b63c5f015cf932f0af12eba50c
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\x49c1d6af1a5a0d1d96417af61d46fe4c8e6df18862e3b6f2ddb917d8dcec0ff7	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
\.


--
-- Data for Name: merchant_inventory; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_inventory (product_serial, merchant_serial, product_id, description, description_i18n, unit, image, taxes, price_val, price_frac, total_stock, total_sold, total_lost, address, next_restock, minimum_age) FROM stdin;
\.


--
-- Data for Name: merchant_inventory_locks; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_inventory_locks (product_serial, lock_uuid, total_locked, expiration) FROM stdin;
\.


--
-- Data for Name: merchant_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_keys (merchant_priv, merchant_serial) FROM stdin;
\\xa3767340a712a6f556679a539a133fccec644aa7479566e28e153000d97ecdd6	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1647694567000000	f	\N	\N	2	1	http://localhost:8081/
\.


--
-- Data for Name: merchant_order_locks; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_order_locks (product_serial, total_locked, order_serial) FROM stdin;
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_orders (order_serial, merchant_serial, order_id, claim_token, h_post_data, pay_deadline, creation_time, contract_terms) FROM stdin;
\.


--
-- Data for Name: merchant_refund_proofs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refund_proofs (refund_serial, exchange_sig, signkey_serial) FROM stdin;
1	\\x4849d0ff57b157265baa944e24ff3c8b832c2560b8fd6d1272c8e4f326d2c44fab9afcc32c2a80dadf52ab708b556da8cf240b0fc0700bfd925f8285bdb9ca0e	2
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1647694574000000	\\x7c7a5199b4d1b4eaec6a7d07ec7b3e1090b46de0a7f07805e5dc18cb948fa8f8	test refund	6	0
\.


--
-- Data for Name: merchant_tip_pickup_signatures; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tip_pickup_signatures (pickup_serial, coin_offset, blind_sig) FROM stdin;
\.


--
-- Data for Name: merchant_tip_pickups; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tip_pickups (pickup_serial, tip_serial, pickup_id, amount_val, amount_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tip_reserve_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tip_reserve_keys (reserve_serial, reserve_priv, exchange_url, payto_uri) FROM stdin;
\.


--
-- Data for Name: merchant_tip_reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tip_reserves (reserve_serial, reserve_pub, merchant_serial, creation_time, expiration, merchant_initial_balance_val, merchant_initial_balance_frac, exchange_initial_balance_val, exchange_initial_balance_frac, tips_committed_val, tips_committed_frac, tips_picked_up_val, tips_picked_up_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tips; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tips (tip_serial, reserve_serial, tip_id, justification, next_url, expiration, amount_val, amount_frac, picked_up_val, picked_up_frac, was_picked_up) FROM stdin;
\.


--
-- Data for Name: merchant_transfer_signatures; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_transfer_signatures (credit_serial, signkey_serial, wire_fee_val, wire_fee_frac, credit_amount_val, credit_amount_frac, execution_time, exchange_sig) FROM stdin;
\.


--
-- Data for Name: merchant_transfer_to_coin; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_transfer_to_coin (deposit_serial, credit_serial, offset_in_exchange_list, exchange_deposit_value_val, exchange_deposit_value_frac, exchange_deposit_fee_val, exchange_deposit_fee_frac) FROM stdin;
\.


--
-- Data for Name: merchant_transfers; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_transfers (credit_serial, exchange_url, wtid, credit_amount_val, credit_amount_frac, account_serial, verified, confirmed) FROM stdin;
\.


--
-- Data for Name: prewire_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.prewire_default (prewire_uuid, wire_method, finished, failed, buf) FROM stdin;
\.


--
-- Data for Name: recoup_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_by_reserve_default (reserve_out_serial_id, coin_pub) FROM stdin;
\.


--
-- Data for Name: recoup_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_default (recoup_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, reserve_out_serial_id) FROM stdin;
\.


--
-- Data for Name: recoup_refresh_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh_default (recoup_refresh_uuid, coin_pub, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, rrc_serial) FROM stdin;
\.


--
-- Data for Name: refresh_commitments_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments_default (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\x8454ee9c7ac7fb09ba9013c282a4ae4f928d5974a734e04e50215955a7f01cfae36ee381c057217140919c17ad2abf4568db8231661b03256bbfcccfe5e92b82	\\xef160ebe36cd15678403d431781b69467a9a68ed4734eb3efbf6b5bfd731b5f6	\\x589aa38fc2e23032f5744c39e19b2d59fd02dfabb405780f316534d66e5172a92475a9a96ff245ef4fda7d0d94ff83325ef51eda109f8ac80596fd01049d5805	4	0	0
2	\\x30ea3edcc364d870908f069aebee31881c80644d9d9b9fc756e777413c3408c70b45eb2d690dbf3888bda565ad90df672adfdf3d7c7f6c5a6e2ffeb4fb59cff5	\\x7c7a5199b4d1b4eaec6a7d07ec7b3e1090b46de0a7f07805e5dc18cb948fa8f8	\\xbb04b281bb2d56af4fd15af278e22fe262f5f2b7cb043809f8f9f86d8726d0ee9fa0ab567b69b9b85c246d42b3ffd42837c9a56fe62da4b920d5fd7eadd8a701	3	0	1
3	\\xdda0cbc7b4b4d04fcd48a1351a14e33d84c023b8f31189e93232d046bf91d5d877f822d2c85b7696e13abc90e14acab70bf4b8749eabb46016843ed5c8801dcd	\\x7c7a5199b4d1b4eaec6a7d07ec7b3e1090b46de0a7f07805e5dc18cb948fa8f8	\\x5511fe68abaa10392daf1bd94838465ea4bdc03c797e87023bc8032359cea05582303f0ca9dc41816ca64d52937e513e77f7669dbfe48c652a3cdd9ae5390d08	5	98000000	2
4	\\x15cba37e94b4618b1498fdb8195a91dbd32fd907f654322006ebc551ce91cdc2365773cb708de3413479af42842b2c16f79cd51fd6eed278ac44676120332b97	\\x7df0febbd6ab4363355b68427a16e5c05345124c644e1199c4aa42ef93a799b7	\\xf36c209121ae7bebef697028e40329bf9ae7411f01ee18246473c09370cc18a4d6e1392f3f15cd6a0fa4cd9a6516113d78aa64d02b55c111c743a22f2a9fea00	1	99000000	1
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\x77f2af341ee429ae44413ee5ce790b32ae63b1a1b46116a88c8a89d30b7ee4a6f7bb75c0dae3f9ab83e463f2c21cec40169a2599a7111aa08ab6e99f0a2ca800	275	\\x0000000100000100a55b03e87de8431e6e6fd8c8b162427b7e5c9911d15afe85074f290ade8e7965baa0ba85a7582a451fc1a0b5fc3c3009c78b07e1cc06411d85cebcd0373ee3b0c0879a066a63e674fdd54a8a5f1570b2f86e8bc0cfc8962da43dd8e4a713b4e9adc9d02440cd84abaf640f73313aab8d6efa7aaf41a56226f2e76dd57bf222a2	\\x4cc9f6eed9f029ef62c90963ad767c5eb9a0ad867ec90a1ba2ff8248ff58f9fc2c4f641018d5e63ac8f473a12209f3dc4fc7a741c71d957e8dc1045992d57da8	\\x000000010000000197e10ce21edf10a47718fda39264eb5df60c2a72e310206cdc880a54b7871fe9647126d4214865bf66154f8ce7c55938bf0d388b7a8149f44306d0d3eb617466b4bc9b27b89ebcecd803dc95415184309f92c5b200be6e476f35c905eb6326b0b94809cf1cf54c8002d2d28b3dd4d8098c1921d06f0744e0abc33799c068649b	\\x0000000100010000
2	1	1	\\x7499d306fbe4a1ccd9618d651a107f01a305be5805c95620db20ff439f62ed7e5f31d7fa9056e462d34148639ab2444b4413c849cda08287f47cdc521ecc220e	291	\\x000000010000010074e65050fbd1e4c9a6ddf4dc88847277691c4f144025115637dc71c74955c0c31f4068a2cb7886bfd04b0d23e8adf103a3635d1e773d33d44193ac5c46a76fdc7715c39a16fdab3984fa5166c783bb042f8aee407611f52d462220bbf9b4ac0b386d69bee9c5bdbaf04e3d3dc77641a722a598ff888c79657d3477c7de54597e	\\x021cbff6aeda13b6f35911bd7796e1eed99ab30a61dede9d3e0cda22dc143838e2e28dd75a49e5b6ce67e532ed64f1f7be4416c8934293ac0ffec0e451d30e38	\\x0000000100000001860be3e5ee87fc191dbc3663b19665a60d24ed83b6beb3f7c5659cd56facc223de7c2f32b9e161dcf5b55363cbe9979308e1e6ec0526b40de1e670a31bf800050ee6802b3214daccaa52e9f43c21fe94d331d36c0540f46864b583583fc2d04b568a357ceb829c38b7d22b5f88f4a659e109fc00b2b4891f3fd897375b02c4d9	\\x0000000100010000
3	1	2	\\xcc77c7fc0da9e7d2d5279c00e7f43f01510e2b6a0eaf729a276b787d30d82d2c71763a2f46f6e04b341547f77b8c5502393777ca9e9e4611690f8e0905de6303	223	\\x0000000100000100acba8445efa16e3c70333aee40de4d6400b8833ee0f245163958092de29e02099c508cf48b96eef73c77b14003b1c67f3cf633d32d680219e65349d2cefb55f7d8dde819f37e2aa5cf65b72f730c1fe7ecb2758f5fef91494f748b0651920cb3f309adc72504c80928149fbf6f936a9110a69fc4eb70b95cacebd60646a7c48f	\\x040301dad9018e0d932d6c5bb18398e7b5722e00070223d096e8750d76f6d52b7905837d5aff2bbec726d53af990fbe7ab16c1d443741a31a1b3026a9ad8b9f9	\\x00000001000000017998ea8ad7b55a4fecbd85c553662ccf02ca5179c7915b7c26ba82d2bae88ae7ba77e32764ba7470d41c6e5dc0e17f57a75ab3f319a1f5835943ce96951c99dd58ad00d71a71d6fc66e62f741623eb6f6bac6121143e5dcf0ac28f1a300212da5fe491b2da0d39bca5408ed1b5f4e6bcac6e12857429b7e199d01e765cf29ab2	\\x0000000100010000
4	1	3	\\x4f8de0ab47af2694f6c1a70ea749801e5041d84e5c3a7f20d3cfec24bb295321d81c12f9df33e77d7b9cd9920bba4c7ec56c458cd3b926ed5e2f80b18f399a03	223	\\x0000000100000100c350a9f22f793be2d07691482079a73356d8d834195d8d5ce6a64103249b6c6be9766e369aa778bd2f2379f8f061dbaa9ff9a000248b625cdfadee96227c34f11d6f00901343d3519b5561bba44e1da2b37eed192d4ef0373b08e0258a978144d4ff7bc5cdcd75d63a126335220c40caa15a27fe274b10cff0b56133ac0e58c8	\\xf0f49610f03b5b052f49355ef76da8b2a219fc7f13fa90c743f9a6db6c5f2c621491f275bd6c29cc50c101f001dfbe62cc5a03b63c456b85aad98a8ddfbd438a	\\x0000000100000001b29fd6a79de342a4540acfc51b6e0f3cf85b6a8925a8e8ea7761adf9714f6e33bcf9dd59f0b5a090a5c9a05b95c4b13e16720e4d582a3e2501d08a6c14b7c2d321690252a9ef02de029a0b0b88ca0263e82927e3367ea365f933e27df57d4c57688c81c4ba6ef22353a0154904dd1c020373f612004c81c3c6c1257719264bb4	\\x0000000100010000
5	1	4	\\xcf0e56bd290d175bd5d8b1781add7d69c8e691fa7fb63ca999050f0ddd5ae1838e231044bf5efbbd85be207a2bc6c7f669676ab087890ecbcc9f5d5c6fba3f09	223	\\x000000010000010091128879cb80f04ab1f36beeca1cc6ba4ff5260a2677e1aa9657397ef4d51e43e455d08f290dc2076871a35e4335a35527ba9932047dd9d491d06ab2344066b6bd9f10dfddbd99d0fd80f20999d2012f0ecfbb940f7b90cd9c08f972c1e675c9ff804a5c6c4922b383ab0e7832e85fc4f1617b9bb7c622502d037cd415a4c259	\\x5b9b74f7a669bd60937c337e2a5a0fb3af1d6bd8cfbbf4b9c51e5c3f6f91025bb3f9c9e3a1ee2533fb44c9d0ec10286b4d28d6722902b460af74cec56f723281	\\x0000000100000001c88937a0edc81609192f5ae2ec73a507f9330744013389b4e2587d566b221af9c45e90f7f286469360d472c17e6f9393d9b7c497a3664a29091ef1f09e7f03a674bec12dcbcc197753e79d86c71afd80147189d4ed9a3b17de75a5fd51764199f2ee85b78ccd0b76c1897e82726ef73d959d1ef6e97a9ab2ce8fe668c247bd8a	\\x0000000100010000
6	1	5	\\x6f73bbd7003c59205feb37223aae3be522011819dc11273d4702fd30e3acf28016e46b28ff91ee5984778135873034f38c5895598983b7bb0012833049a98f02	223	\\x00000001000001009d25d140067296276faaa8d8f1856a66871e13590e611364f52fab2ee26e44b04e1d9e43defb4d85ffd66dae99cf48af018ecda82ffab31eecbed38bf38e016553f7b2b45bdcf9f3745fc23fd6876d4f0339736a51ce88b3c28cfb1f95111fad02a50085f0de32cd9a13c260d6711b27fe11b0fd716872db3d1371728ada3bfb	\\xa942276b72ec690dbcf96613a8be994d06f05bdc5a12f895c1426b23665493a1338a430286ad8f54dfc1f50207fff81ac0f6858dd362b4cfcb7ae2d0e66e07ff	\\x0000000100000001cd174f1bf9e078c0dc74d3401e4d0d7d76184728ff9ad1fc072444a52d6976baf19ffc220979980a037d0cea8ea88a234abca4205b20ac2bd99b29d0d72357d25f8e89895d5eb83133c01e3f2b0748d4d81974a116097c40aff60067b0aa5a90bc4f2cb7a020d4a92dcea8f501c5a6afd34bbd6f036c946df4aa1c1106de1958	\\x0000000100010000
7	1	6	\\x9fd860dba719c8df4ecb17d57713e039be00f24548fe84f111ebe9e3b17a307e29c6292ce73f04216f506927b1d5b87b85916ec1fbede74a8c569af0e772c700	223	\\x000000010000010006b6524bb06723ce8167184f1150ba15b2bae6b4e212344b20d6b8d27f76628699f846dc153b26010e57539c36c99b22a44330dbfed883ddcd4d9fb0b5d848aaaabe49a705a1fc4a2229748de999f1e480061de8d01d7b669f54beff56db40abff7b4cae9a9ee97312c42d512ad97005b66c080bfbfe4754c5b6435587fad409	\\x1945fd45b14e2d4339efaa108f6427ece81abd10c3c5049bdb1fb7ab30da2b3ddbc4fb9349f87435aedc0365074ceab7c549582ceb8c25ec2934987913e9f153	\\x00000001000000012c3017c331c883f14aec20a7c324eabeeb2cf9b6c8d6cf12b9e63eaa211edddf76f0d86a3efa88ce80d77173c695c7b8f7784343927628b7aa8c8b849bd50602b23ff9e459e8d09b0fdcd096ee60a59ccb62eef17eddd307f3df576b551c0468aca85399313a3f970ccf68f8ecb79af3bf8a32cecf43ea6a70fda47e30bf67ce	\\x0000000100010000
8	1	7	\\x6b3fce658d1d3fee7cc22b472da49280a6fe19197b976245aa2432a03753cb1f1fecccf46b4ce3104d1ed08a6ce92db68a605e5106c17a54171bd739843a8c02	223	\\x00000001000001002a65b7df5a0d12868409788a0f6bc532751cc70f536f5606344c23fdfd9edff86eee1861b73dd22fec7e6844c1aba29c3cdbb1ea9f6a9c17a6a3858e1c95ba3263ee9438bd3c798acd62cdc2f39c67103b3fb01fec39c8ffa8e6e3e25df7afe8532e5652f7adb71b166110dee760ab7f92a33f52bb8853fc61aaf71a6b1912b4	\\x82b9104973a074c14e3fe8b8f4883c6f7016a167df25ba425d8d6b9d8b11db5999fdcead967c647ea7513b213e82bbe244d741f6cca3aa9fd00270be5fc978e8	\\x0000000100000001500f10604e00332e9d6d4ba696e02ad23f0db0107f65868bb943c1344a7a6e1b3b78ef09e020edcd68fb052f517cd9783b1a452f1365ae3eb7337408b9206ea1c16a876ea396fbc39017aede86c911b6a3cb1b1036a4f7b3e030e6df86f7ffb4fe5a091de4a582f3c4439f546db9d5f608e72565c283227365071febdb3cfc44	\\x0000000100010000
9	1	8	\\x7900fc1e72e4bc3bbbb7eef6e1a91ed7583311f946981098b680ea07825d241785c8cde59357f31aa4cb5de58b3d7747b4b79a6e34c500d7cc5d73be84413309	223	\\x000000010000010004421d0529654f56f9439a56d85f435ec846eed840bb1bdfb9d8b80de4693c4ee0a6b6c1070da31acad0f4bb9d115b1e6d063cbea338dbff563af570a1a27b8be4648d63bc81accf47b4b999f9e7bf17103dd96c258b4db2c99b6f99baa1989a42073acdd73be2dbe998cdb1c516555b1b020d3f900d164e867545c9416267ce	\\x98787c45f7bd2d79c6b74d964029c181e9bafe68130489041a0158438ae8fa7a05444a13707c42f7413d4555842bb48720c060190669c9afc9fbdef939cc8bed	\\x00000001000000018e37cb47b3fd1e2e9a2bead8001967e053071a26b2bb888da79b0aa3e5ee3af8c5b45fbcb14e1f3d126bccd7bb98142182485727d3131a800e9be18b0809d87cebdcae79796307671bbafaba459416dc966faf566a8ce75fec873239bc56f86909c27b61da4a1a7c3af31f5b2aae23f8739729e3fd79445f4196b7fd63bd932b	\\x0000000100010000
10	1	9	\\xd67d4b67fed0b377e55363f035a0562cf988b9ab19e9a82aa8a9b3f9218bb4c118851df1d95b7ee2e21b8163e5a56f707fa154635080e9474060510ef33ac404	223	\\x0000000100000100835a1f0fa1afc827b0b577b215f0f353e207c05c2e09b97834076e1bc5237010e7ace460bb3d31c59cf85a6e503afd6c005a41d75119ba3f934a1cd23bab476aab1bb2ffd72bc8adbbb1c61a00c346100bbf4eb7bcaf54b82a1d998f948c0cd13c69ff593ab8044b0c653fa669a42aae044322e9509c2f2fe64941636b121b9a	\\x674654744eda658b1ef744bcc2418c0b670dd133f73ba1cf3ad0a565da06697741071356ea985bceef78300c94264730cad9ef40e344672eb0781f3b342a2016	\\x00000001000000011432858df6c63ccfc093ae45dcea44f9ab12ea9b1ecc482fc79ef078c8d34e7e6ba4b838fe6427ec70a82594a0c6653e1c9c21a98d495b66f91f95fe1b6b69949e70df48e4dc5108eb9a840d8acead3895f261e21d9847f6fed92fbe46f0b21449c262d51474eaa9fe8df5b653dabc2595f5e9c76112af1eee793784581c71c3	\\x0000000100010000
11	1	10	\\x643ca2dfa3550335b25039cb34778f35c09e846f377314d9af19f71674242a6b1a69474f1c09380ab5bc517edf499e3166b9fd805050be183683cf8e6eb26600	362	\\x000000010000010037c3d9a149a87c7116227eacd4f9344ac1af5225c73d2097988534ca38a9af2518c297919b3068814b106753d23a8b177084682b93174a25043d2a39d1a0d1ca056e3cf55b4ba18ffbd9bfa02d3bf3cbc9c0050485fd25c0815257e6bdb03f74ebbe2c7bc1ccd93569d3edf5c0594cad92cb76771b0b633b70535f1a8096815f	\\x33fbc7ead5fc9fc3301300ccf8866daf3f0baefab4c4516cbda6efaee2e2be2b5c8c089e698248227aa67bf8f679d71d543fd624717aeb97bd60853b6ddf47cb	\\x00000001000000013a5c8e1fdc05558bde25c29b13022c5940e315d79960227e8ec05e3eeae53a1b4df56cbc5b103e5c8d78d5e7eda6dbf2e2dad52e4269d922a5ff1307aa2598677181d6f96871341b4994ba7cd18f62c143085a18cde082ed1b5bcbc4d83c1695a125f3cf691da818831e0f0fa66687aeae8042bc46f47a17dbb01f9fd2f33878	\\x0000000100010000
12	1	11	\\x76b3e11a94b32029a9ef262e721f590e9a49daceb17f64e9fbc882804004207f3dc09f5c6cffc87ceb2076e8630757d4d141e9df608c107123f86ccb51d16f01	362	\\x00000001000001006aa1a6b7a39fbc50224a85a06a7809bba7b092d81d731cfad1a4ab74ec5f05c90dd7680f8e60d7f02e9f78b75a3e25e71d236e8d67c1b99c8efc0b164d4d9efb1c0ec248512422a12021ff459c0dae08966b953d44bfb894ebe9009b8f7d6324ad75e92d86e2ffb9ef1eef30d92843a625d9fde3fb7b6420e8723cbcb54c6131	\\x96e5c4cc4fa3f3f6a50743af947d23b9f4f356e25ec22abe01e84f3f8c2e46be9c878a2c675819e657e9239a5122fab1c1d08e027fc033f4d7068cde10fb56d5	\\x000000010000000134929929d10a696c4c4aa434d6377f03ad3b2183dac3e9df299945710878f46836150d8f93f42a1b41faa1496966d03eb7bc2946a9e5ef58e2d2e24b86b14d67a6c265b60066dc3dec0df164e0767c1993485281de8650ee1428a66ad0a1cd463263cd379c4dc7f5f114f20064125dddbcf94f95fb5557b5aa5c25e78bf3b9cf	\\x0000000100010000
13	2	0	\\x28e6b0ed721f901e845b62eab3237c1f6a37655b83e691e4340cd261aca6e92f208770856707afc9e4bba9d594d56aa19f62ca546398031f04c48221f4b48900	275	\\x0000000100000100014a14943c01fb0ce919c338c1e6cd3269d1ac914e59773c92569277ab5a5f39b6c8006dab69ae4f3ed5a91458774e8f7ab537b0bb00794480f837819a83041b0f5d954225c8044e45007dc087f32c5aee060f92d29245e54a66c56f184cdbd9ae6f3cc9648a598f268130fdd56dae9548c283430f2e0d13e2a703f87aae0e8b	\\xfdd3fdfaed421919b89fcace278d67f2bb04bb9b31bc68b6b5db42bde3806b5e15055a4668f5835ab364df9866f1e5a4de6dc255a25f93675960f886302b6a2c	\\x00000001000000014e4ad6d732d51908bc0c748241a0fb66ffb3948de7538600bee7ea21632b3aad3c6f6199f4d5b42b307619151750e3e242ed2bc3332f1ef77d85249c3234f344f56c4cd60d5e5cef5e3c9c921f16d9be4fcc5e277dcf2afd23295137c0c048011b7e006edf6bafec2894ad3c6e08768cca9bda131f91dc2fe6a6926f654f020f	\\x0000000100010000
14	2	1	\\xf607b34681ab6fc0958ccacb35256ff67bfb0f1ca1ce2dfd7200b20d32952a1dc26a2ba521d9157f5821b4347702158f446b1c10508a1d705748530ccad1b00f	223	\\x000000010000010069d4adc6f8430021382d7d232558cee89c9ba50acb6f674c7f090b30fece832905808828cecd413263618f8cab74a7f63d83d218fa01ee7100d17db9144ab2e27d5bcb805216529b7af6a83c9890ceb67195a6bcacfd1d8842f0369d675010447fc4109d11b0433c152bce03babb77c586f6580105e349793139aae543579988	\\x28224e43f07b9e3796bc007153f40a7f4662d6605d53716a84a2fed1fa411ad5cab08e2d7d9ac38756e3b54fb1171de71de9a1128d543ccd9ce339712b7da691	\\x000000010000000155e09d0a6768a72305f859ecae831296e7d4f11bc522a2b9c504f586dd2c525c7c1b61fdd054155d862e454fbd8c9b2d303e1f649cb6c6aaa5e20787d9bf5814f736b50db8db9d0ecd6f1a3c4fe6d92d8cde761d97ea487659d36bc1ad982ca6174e74b5cdf887553b9ecb181156f8ea9dd32d202437f38ec724c637014ab41d	\\x0000000100010000
15	2	2	\\x184090183a3d3566542f66b99ec76ddc1963e7521450f9c8980d55b8b9e5e35eeff50c7cfe3e2f0929f5a4319481a6745e286011869b991fd164c55343b3b60a	223	\\x0000000100000100036c5cba57ca93811fbe4f0e07aa15a17f1439f1477194f11239c0cac542db088c88de5ef12e6d457a54bc3dfb56bda349c9eb1ab8e9940709457d27066382c06fe305b41e7716d018f8a8decb85b4351e571a86f2c0a3ad7868eb6446c2f1b6c8f20c57cd6f306d8b6044467f105a7629571d3630ebf2611309ec9f43c28e3d	\\x2495e1d52e30c0a027a0847c66d799021290a6b4af939a7f4dbd72ea7a2f6896befa81ec092611a20ec8a0f22dc171092267aad8d9981204991e492c68c05a71	\\x000000010000000173848e478d8ea074c722a008e8bc4c99744336cec397e568a044373f40993b28bf77a400557b3e1557f7d2102beddd68f61bee18bca3a6ce9238b26beaf907e106b0be23636030f454a85e400f877aacaef155c595c11c2236098bb3e382ea8ff5cec73d95ff7e27a25d5fc1b756f463d55010e69e8c6a4c968e23a3a5aa9440	\\x0000000100010000
16	2	3	\\xfed4e833d8ee78db71a361dbf00fdc927c2b26015cdebba36a9fc60423e1628593e4c496b8cf474daab73269a60b54463cbd565fda6f59267d0fb5bc54fd280f	223	\\x000000010000010043e97d4a34ccd14718ee45184b876b642c02c0410c5f332c3360faacb1f9b3c7eafb38eb0cea52b0cc7bf836c36c9e9c435c9418b1ea5785fb30cbe4bf4125f8836eee9e03d67ae136809ea74d6f5c51f33ca1a552bb997a894750ba02ca97a60b693af94d372c89532f6820a1311154245d86e039ed3fdc1af57ad7ef6df8c0	\\x6c06f060fad191d64a9a707cf7a7f9d884054fac3fb5548f4981fa066eab1920a2c73f11cb4090dd68dfbf68eba3621f8597985d566e99f4994e0f0a4a25c0f9	\\x0000000100000001a0d95fa003b8e9ad20ad34c3ca750fb3624022fbb26222924e2bdb72cc5e6376d3166be3ed3bd4d1b454d240f8fd21afdbdfaa0447052dc2c792ae45a1d9cd6afc12859dab402b824c7e0f1705cc9d20c5cf20f4abe942e0925d23108f5abff927b7084a3987732ced08ef63e41dfc6852d8dc1d88de2b8f149309a7e7f12396	\\x0000000100010000
17	2	4	\\xa96764294aeab24225c39a48e27058c61ac862d282ed70558cf3aef7adc60394c576cd0e68142e367f58d74454848859c2acadcd1b99b3082651a19b814fcf03	223	\\x0000000100000100629f5ed9b50a1c9047b051f6dc2ff2cd612842dc777c2db0ebcf005602dadfd2c02141f7ea82de9146415202e552d563860e2af04b679d78aa1685b7c6cce4907a4df352c6296559550c84fe98d3620a4140e9183cec3647ec4caa8c1147877e81a8ce9bc0197cb772e7011e55347988f8def99a9456fa948ca5feb6becccd72	\\xb7bb2c899be86282c5fc0c9fe54ca2115891082989d7bb0ca5257b97a4261dd1a3fb41a4265ff252866f79974b7eacbb60f553d1a3bac78071b8c1b2571019de	\\x00000001000000012161c973b42b07589cc02710acd6900b3a78b6d172ef807f7d73efa95e9dd4161d1290146d7bd5368eba44eb13a7944f5fb32a5cd7eb1f9db25b0eab0ab7afe27377f1143c72953f1d65bb8af47337e6e03312308075bae5af6a41c627a513e574e79979662cca930d0d56a92716a213c72bcbc0f15677decc8bc4b0a910cffc	\\x0000000100010000
18	2	5	\\xe1608de561bd8bd036b561645e4fc552960990554de99da599b3935fa1b3747d2e54e8a1245d0e892599d16cb6b2b0296b5c3725d6af5a76b2c6a5d84461cd0a	223	\\x0000000100000100af797beef59e81c05c3e5ebe87601f64f652f475dd6db23cd1d497ccf5ecfaa0bfcaec9d5494b56ef17ae748dbecda7b8d97291e10a08fac35b9649b0f130ec810fdc960b4ec5019a50571cd478060121b79c0ea54bf962323c338f750305f0fd0989e1d850a956addd53c8bc2108c717ce85521bc84160c79dbfc304cf9ea53	\\x2b1177a52e73bae5609a60014b43efaff36cf576b4761e65a01d7a50a21979b9f8b615124c680a5505752c427f73d37ab55159f0cb7b708dc425629a7cc84f47	\\x000000010000000119ba1cf6c47e99f838e9bcaad82839f6112e191d58eb926addc8dddb59353ce816bc0420d6d86b8a4f4f373c5c82fc4602266672a4aaae4dda52050c1dc6c2629db2e7a629a7b51784e15ef43eb136baac36e341271feaa4bb5c37dbe4c099565e7f525decae76fb7f3db06097c6c8ee020d6ad3e05e46f50b7fc43b70fd405e	\\x0000000100010000
19	2	6	\\xd8fb5a1eecd9e2fd6e07d9385a32d12a4450c6f0fc2634bf91b9119a994b4b7ee208e8a68b64dd0fb5205a6a2ef71784e3ee3236d580514b9d6e707fb1696503	223	\\x000000010000010056b7104c17facd91a11dc46db04f7eb8efbd1f51916e9a934b886683bb0fd8ffe0cd32d30fa71bb5504c43c585269be5feca56f0c1ac730132c48eda36915b0909a93dbc1644e1c68acc5bd4ca1adc81d166c3a4a9eb3d160d92f7b13894f56969391e1d43547d68eca06db5baeaa41b4afdd6a097fce50c0c761038df965ce0	\\x5bd49e83016371d670f1049c3d231cf1a78fa680fe0c3244cbe16c829370c2241563ac4ae65c709118ad14e4c87238d27b7cd0fa3bb6f6f89d9500255e81d691	\\x0000000100000001c5de95bbd64002fad13e80b450407b5addd7e6b432783ebc89131c6e418c13e94507b4ad8b2a8f75a471b35eedc4af801ae268a1cd1edfaf53da49b8ea210e6f8405e12ba923a281d43438cddb36e01605937324a0c418403af062de2c37295f52cdb75f3101e02c72b50824546a817fa639c660cd138c511c820a54ecb333f5	\\x0000000100010000
20	2	7	\\xd47b0afd41e141fa69093cc80a3f9ffd7e191388731ec25d08649c30086ad2260b154dca039b6601dfc7a62cfa7b2011ecce85d1ed0681823dcc0132bc4b9504	223	\\x000000010000010068a1bdea9d35a2004117395e3e27d5ee08cdb590613c3a98f0f922663bf44d1a192ad6df6bdf585a5b3fe1ec00d9150c884e668c5c97fa41eacf10207b61c2b8cb0eeff6cefe35df8b8116c0f21872b89beb2b329c9c94fd4724678bc46c5173537e657b1b3b4d97c4e704d2d45a0e0eb65d5f1505236b45b6b58458c62bb992	\\x63d5ceca1a3230ad3a117f2dbb26601ce2996b8a6eaa0ff598fce64059f664dfd219acbd7299fb686122586d860ddf3b5bbadcf0eb89bf3e1d8f29f235a4c6eb	\\x000000010000000158fcf042fe1c404d85421ef25075e1f831157a784021bf9380d85fb24b66d69019c4475d7740b18d78292ddbab3ecd9c2e6af004f6b6d01a05f559d4a8af4fccc611e1f9144c53dd66e544ceba4ee3669b4f616e09355d86ccf589a8d168da68ba7c20acf0c0de16296e4d02645c4d457da208764cdd18f436e899c9735e4dce	\\x0000000100010000
21	2	8	\\x2606af7be4b9c71385e4f3a0caf1692955a845b73b283b7c7d9fcaa376ef9c5d3eb95ed93b4778a16d84c40803f40cb6410f2343a895105a48e46b6ed6fbac0a	223	\\x00000001000001000ffd04f7bcde3be20ca8c6c7fe4833012cc2bd71b0b310d18c8549cd0aff456a11dab361c7bb6e95ab02203998409b60bb9504e293c0cc6c768fc266a8f8aa4f662e16f22a3855e951aab22d81f812a1100cef629c4f15cb6df2b27f3497c9088bc7f7cf23864d800039ed6d59720ab9a861ea4647a34783ae4207e4e163491f	\\x7f13f35cf9c01d8c37ecae4c540e2cba60d20e9fc28f95063e2da940c0597400127fd67a55a16bfa91ae063d74fd4e935b31a987511e17d4d1b31099914facfc	\\x00000001000000013285d2d5b4d09541e5daadaf8bdcd75cdf44d1124881b902c0f5e52c40fecb49619d21004df7819e4d6ab8b5542a40399252c66b5d934374467da164553840773a88afaedb2f6082062046352742a19807700dded69544023e202daa823222575ad675461fd5591c6967222f984dd1dc498fcef442fa9c9e6173f319153f66e2	\\x0000000100010000
22	2	9	\\x4434ece92c422f8c3dd81caaf44309582e622de89d5900a83d47ec0a8d32d1bd45bab44b3d4e28a747b4cd3686cf04153eb1a912a81256e0a40eda45b190f101	362	\\x00000001000001000506f42159b4df389b5f3a31b1125891fa037249739b77ea955a68c42e925dc914e9c00a2862a69280d4ddb9cf87d1d8a0dcf077ea23e36b138f534344e2749e48815b45aaca153e9f0142c67d57c86f832f08517b5e16d058c33abc21ec5f1e1e88e68671159c075229ad28d1b8445cbeaed15c4bd750cd6321616fb4d8a84f	\\x28a68e9f9f0d9bad0376d8aff2d6a0cb0aed5a18e7acf0b2f8fb8e688213001902ba38fc5d1cb4adaa7d8894fc80d62efda2ebe9cfca9936d5332f7a110637a3	\\x00000001000000012263d783414cee66079344c3f471dad8bca91639a1e9eeb7ec3036be1d54c50773aa0542f2a9332cb10052cff3c7870cb0516a57641c2a0f57a7ff52ed01f65ecfe6758a0334ba52d14ed4348499fbcebb90aa2002c6f880dffe1c0d9c2d510c23ad8c276897716e233cc47b1ef64beaa6688facc0b7ab18d57466d94c4ca595	\\x0000000100010000
23	2	10	\\x65188a7f72986ac833b2f8afbd635223568bd16926cca950d9589669389cbb996bb3577f1362fbcd41f7d6d141e0c86d43a4d023b4d0494bad729fb701b0010c	362	\\x00000001000001000186f69cbeb9a6e9679704fdcf8dc8229c1f79ec98931c82b4406ee17f1adcf113f93e53723c781e00902d41d72b3f3c2ac834dec2cd28db8ac807d8ca982cbfd13acae50015b70733c020c29be48efbe0107778c0c75f4f149564187b1d989c84136c85420e528ffefb41aacd11ee58cd6f840d37888c17417c1f1005813e4a	\\x90cc9b9ba0bef3792dd4c41e853aef05f1807eb8769e95ae9e957b14d77cfd0d3ce0ccc4bdcaec6bc593de80ce75d437e56072e6b545ada30b9a4cecd7a6e1ac	\\x000000010000000143c3f3d9e8e5ac496c6251d0b1dbea1d6edb6ffb8d178ba0801504cbd3c124ae303f4fc7dd21d2ed04c8aa49ef686c16de83206f011fc5cc0e027f313a13446bc49cba91b9e7bc6db579bc8b80cdd5ab83d7a12a2a883a1180b86641d26b7cc1a16f8b6df0329aabbe18d4a0426d74d41b2d92424172bea3931255591de4c915	\\x0000000100010000
24	2	11	\\x14a17e2ba2e51149e64e9d5e83d5c1dfdc00915d877dbc5fce022fdac3b70b768a3c915b7de971581f80c70caf5d6458807aebda6cf4801659249b88e5b7db0b	362	\\x00000001000001006ea4bcde9b16b60598278839f5a329ab0f441b6a54df06c93b35251f8d7b2d04a43ee970533c982cb4526c671e2989a61b7a5670f0af4a250ce3fb59f9184e6968740b2acab367123ef0468a164634114cfb3af1e1e11007a2eaa78b339c2143b03acdbc9253f87092b93c47d58cf6c2b63891f24bb967bebf927a9dfc5e05d4	\\x7e89ff7226ef5270d24a516f204f92837e4e7724c604a9ce4ef78ceb3506db0da2d6d4977986d4c751653d05b6d56de8d1296751bb150b02a12fbd5336d31778	\\x00000001000000015b9d22afc3d3658d42481bf300a82132c197b168e260e66967d97637391bc38795b85b298e8fb4097a0c015f1df08f770e0f38f68102410f41a03fef2699e747d4dccf722bfdab0295b8e96dbd67addf65dcf9a9fd55b1ed43df1073b12e064361f1b27089fd301548eba091f218bd144d3e02bb809dedbfbf01c5d7fecf8803	\\x0000000100010000
25	3	0	\\x74e2cb6c3055fc463e379d9fcab3b00e43fea51af5c51be866142695d4348d04a3dcb043c33545f3bdb9d787d0ae9052d5f5b45d012812ad34894852ffa6e20b	418	\\x000000010000010036534161c8036758412b36b6f7f899b4327aa4f75d0ae297fa7bcd6f22d97fd0aff67cdb5d7bdd62bdcab23158faa400d43f375448227894f75b50e03f78be65bf15e8cb67f16f245e7133d30191c834e72d9ceb92307792261d3670299c4b70561132764fef2f375a4eb624a29521366fb0b0e9f7538b4da8037080a794f568	\\x95595919b35a495aa182b938e21a78a78c99f969fb7a4feceaba8cae44e8bd781e80c2af936acc2d6dc59769edb22a646ddcc22bde8ee19bf3a78b599cfae74d	\\x0000000100000001a3eb2c1fe1f921e072ee7e15892828dfb52bbfa1924b62c077ffcf7253678d3238cbb02f237b4ad077ffc50489418801d554fa954a141af8df3c4f7b4da0fa6b51f9721b16481596f82cbf3bc28e5e180c9ca91b86e1a4115db6c883c3833f632a8ef4af52e5816dc12753789fffe196f9bf3eebd3409142fc0c0698c4d293b6	\\x0000000100010000
26	3	1	\\xfd80d18a83cad3450ae6e31c0100e4f5ab7b38da4a20569c28cc8fff8e488fa4d12348368395879ac1c055afdc3a8374d506187b0cb4784eb9c941552df48c00	223	\\x000000010000010014d887f222e92436b01e79f376c3edee83734ea333002e972a51c9c6a0d87cba0da1e80363e5cc83c39e3ae9c99218c2f96e3bc738bcebf9db45976fc4c2dc1bc2335dc898b308fda421e69cfa185c1e4e04b5230bea3e0ba78ab75e96adbceefec73158841ad4e5a3b26db8ea5d8a77284df72138febef746fbfd52843d4753	\\x92536edbe1dbd8d22f3560f9f800e640570e5ad74324818cda976f5feedf69bb50604405398ad3bb3f37396e5566d4ca4294f39fcbd48deab73303f3dd7008f4	\\x0000000100000001b9df24e060ce024bf7d25e9f025b1ffbfa3c0bd171c1943decdafb4e9784d2be84aac9adb9c215df2095d1daf64f0f0577e47bc17fa78fcc50fa08a68e9f9e89abb8b1acfed90547622d95c304cb0acf0c5b6e0262aa490d42449213e11d433d6026df31132750fdd1da2e877ab2319d8dc302384f989181acb385c4dd1ad510	\\x0000000100010000
27	3	2	\\x21e900392b5c73e1bc13233f946bf431fa16c946af04e220a3070f7966d8a9f1f8bfcca2d6c0638c7b218afa2a9f5d61b364f49fa00f25ad42d66bc403814108	223	\\x000000010000010036f4da0b47f27e5568ec33d88f75b8dd45e96cd5e694d270a205c1906dcb5a025ad975df06fd178bbedfcf7df741c5f8bf1268b2f35a3638ae1ce49d79eb0284942768e486d45b5b3b7608954d91896dd8ec7db7b3516f490f8b41884f6dd6f3fdbc307f0874fd0ee345594b20339af9d60f46c15273a3d0f65b35d051228630	\\x7b369358ea5c92a3d4e58a212a8cdccb0a8d6f6ee767da2a3e55b0c07abbb14537344a075c543384de11afef37600287f27bed93eab741c5ec04432a8fdc5c26	\\x00000001000000016e5f26913ce541036ed76a8364fb29ffea4a1f3ccc20e9170228d0df1bf7a5366d238dbc874dcdca4b49cb34af848e78776c854f1359c37773c26c84db922b89c8254fd419432044741c393121eba7e632726aa13ec5c6f7cd365a222ec65f455f3513cdd69ffe8433ee1605cf6f0951307133616779c4bae359fd72cd220060	\\x0000000100010000
28	3	3	\\xd4c6ce4b527962fe9a26ccb23a50a45e883d934ae01ef97fc958e52018ddbdb6d9873568ede7f32f51464fffd0ec99a2d5d81ae1693b5706e7f98b1c74f9cb0d	223	\\x0000000100000100061f22b58290d13472389a0cbe5a72a56b4dbb24560a0d423f48a5b5b42ee9b64581002e0aaa40d29a0cbfb83b34bb653f8a0a8179917c8895d9a0a44c7ad2eee8f0134ea8797c230b627deec3322a29981e823c66f406fd25974934c54622b1d8f1a39a55f43d5148f9a19dc4b4e009578bb7d1581ecb107c751e71e3fd3c59	\\xfbe1b5b6a4c7a739719070418caebbc58cf82dbd389f73644ab91d28d45e1d6ae9df1f98e5f153cea4e5a2233335487eaf1f374de807d52036f9b3102a266cdb	\\x0000000100000001c7b0d6f69bed37f3d435a26c53775a435c1294fa74345f4547e940c3ebc27ebd421393001809b3ae83d04678736ca4d059c6defba45f78c7f08a0cc588798378501280c4e1409ef9be64242a499595988bf9d7e88c573bb0956581812a93d3eb5996357584276e063839b0cd7af9f70a608514acb5ea2e7e5f5276271f2c308a	\\x0000000100010000
29	3	4	\\x294ec7efea7bb56b70a39c68a6280acffc3b5d830714644354892c49adec2dcabd5cedd1e1e97b05342623eac2922b42e2447b89a7ebf744da6fc0ddb6745402	223	\\x000000010000010076e25adcdab65d1b55119c3860514692094c6d4258e76f2718b8f662e4af0983b713ebba6879cc2a60132b6e48d4b2c9d2490105a7f90ebcb17809d7d26cc8f74e30c8bb3e2060c9e2e7f42cd6b890704dd2fc847914d6d0a161dd8372052802dd1717fb1cd5041f1e61097f1e6810867ab12554e3e63d725292626a3c68fbf9	\\x5768ad6cd2eb963b14304db28db07f709ec7f68c42acdd5c47480cb9acbbc8c5f169ab49d921f1f37bf18707b4cf121a6c239a87973ddb748dc273b6ecb2ba73	\\x00000001000000010a6c61b56d4ba52b3d356fe4ef2080e31c0b719c96c9505d2ee05dce872099c25ca68aa1adcf3e2d4c85de045e9e72da12a8aa2bbd8dea02062588dbea7f75ee4fab8cdba3daade65c1a72d3aa739815d63cf9182a62d9f190f0db5c02d09843f89c48eca87b8769bb8958a23dc54b7d6b11da5d9afaa8b2a58b266048a537a9	\\x0000000100010000
30	3	5	\\x394386c897bb994fc8061c9de5d422b22dba8fd441f311d9367862bf8734b3356f598a80eb3eace5ef356790cf30f2b94a4bb05c64c2a0dfaf22b73216d90800	223	\\x00000001000001008940d64b25469940f73c9eb67ac25a78ecc42fcc7e9eacaa05f23b3e0117236530599459eb26198e63e2414a82709b91a199d8552acbf05d53903967c8d2dbe73ea987e93ac34a9a84f88e3b0341d13542faba656284f38a4dbc0a2fcf8e3937205f19c3b98c7144d0ae88bf3ec3345f183b27963f49f5919afc4ffa226758bf	\\x9881035457de8c75a45c1bb2cde379f446c3a45ff3849110f312213f466c334d8672766312eeaceb14c471489689795fbe4fce1096cfb88e614ff2638d1f91a8	\\x0000000100000001638a1b03e94437032ed9d245128b97612924778c8ddaa59a3aac2a67d6b6262e64a0fef235dc5cd80882aaedbf7fe7e3359c9df78ac2bc7e90585a710dc544f1c8be33fa3979405a6b3fe70e039cac833cf957ef9e59223786a096d5741bb9d9e974155b9cbd6070a00083d8bb50317ae9cab004d6efa2038ac9e22c130b6e35	\\x0000000100010000
31	3	6	\\x8688949d5848e57b7f8be26a33fbd8885a4b002d5d3d2c8aef6c5deb504f6fed6ddde6047f5357f42e09f3348a9c473f747fcc45a1202a7e60836e46a04ea908	223	\\x000000010000010037dead80be35763655898a6d222c08910f7823c00a464f4989d48159c052de5d602661a1c230a16974d0974f8a002b4f458a15c50e7b577fb245059567595a9ce262c48fc700166be8cb9f46f6e06a5b7395c39a27fe726cbbc082f3f54d86c2b2446cc0867b8cdef6d2e270f188c26a4f44018564b568f5bb4ac1a58800e0a3	\\x4a9eaaca3f59066405dec31fa4611e498c14b0417be0176c776d7364c41b5f644db8c1a45c0daeca46d6f305098f6a2cd13e3e6ef1c523912e6884d74707aef7	\\x00000001000000019e0c392ed17fb6530c364e8693749f1bc7e24c572f0af72155811e09f9cc182214d2da0f49cc49639aa404610a4033909d244b49a9db030344e9144cc7194fb572e44ec460e9fdab45cbbc4c386fe622783796ff18ff7a6455ab5f29847c057433e664edcf8fc67fb3593d713c77b7d5fc25191b53c7e0b9ede9aa499bfb65eb	\\x0000000100010000
32	3	7	\\x8f7c903d1ac5b054f0afc5bd05bcff6321d726a057266090a9cc09b4ddc6f05580d71076eb9bd5c8498994e89aa29ce00452795ac0d0ffa0a5a4d03b7d0d0308	223	\\x000000010000010081e3b8d21d1c833be6f7479f02b74cc9fafd915d0c18b07151dc32fafdf685f77c7a28147c879966fc3a7d0b406b629e74fe2adcee6849a3a9fe94ada083e21041b58292aefaea97c954e6b8bca75588f5ac4cc7acef2a55f99d014b2f0ff9ce01afac1f77a2c018af7830b3b047ceeb0f51476653d27345fd8f1007c373711e	\\x5d1b314afcb7b9f0c821ec8d88f56e236649b04b5c2b8bf4835d201474829a5907cfe26692a9d4254b4878a6d0b54164f0fad03fe8710d042f2fc7a47d593427	\\x0000000100000001bbb35e0a9bd571ffb35643252e617f1b9a90316c29ff84f0448fc501ee70f19dd2eb68ac99a50c875cf25ed7b456418ce4c56c1b950f3ae44069b2f5bf54d40f8a9a84fade9da6ba14925b7cb009bf68e24013cf4885413b4ec797c2f294c7d55dde510c907d445fbdfa95c33dad9c0b4186154ca59f7913b33bd5605e32f65d	\\x0000000100010000
33	3	8	\\x20f6c683b6909b80922a9c8caceb10d5a01717fe8c4dee6711f4c470aa30b494e139c03dfba7355185e6f8ab2f349adc817c1f9ca2a1670afaaa58537871d80b	223	\\x00000001000001007f36a5dba0fa71609d21238d1ba01f2dee11545d11296af71d0848cdd68200c0647a429203d500e56f4171dbdf48aff36245358c7d247a0c12249d7d8f188610f8e82f3b6baffcd86789dada7269a8ccdd3ac9de21ec8ac003fde013524ad8e840dca3ff6662f032368d3b11685d9ba8fd6ae68b893d68e49451f52c79eab1ba	\\x88b75580c481f5b1ffddeebbde8fa8adaceccbb0fac7ba71f7f9c6926a2f579d9783b533c5dddd7dc86c6f2750dcff9da11b9c3eab57c85582e31c115a566f93	\\x00000001000000012ea0a2209e28e03dcb927d0560a36b469c0bb646bec0c561782c2064dae20eeb03a60a7a80ab4f417fdfe3c490fe14256a7fae5c188b4476275c8b37324c3364414f55fa6a5538d123be6609796ef2040d5edb95774ffeb96e7a88d9c487d0ab785f1a812d620b76915613a0d0c5c4f667a60781c0da107b6b686d3085e22b83	\\x0000000100010000
34	3	9	\\x30d3290a83984221869eef827991bc15e5ad6733a6f78254bd5dae023c3e3652e51a42eb89d1c9f18b1c3585780c7e6e8ee96f1f509daeb8e0452e7928096d0d	362	\\x0000000100000100681e8981cc752e376ecb270c4688028202fc483f1729e40f7c525cb249fdd58d06982087be0b899e491ab8361dd3ce7927dc75a685c6f4b9ada9769edbd88a60bcd25a7546c543a99c98a84a312f52410adbf4698059a95c88f08a9fb3e34f1e39c38c37a30d7b66ef6403a6a2ec7c72b533d2aba8ae01087a3d7827f457329e	\\x5171fb1b84e2a856d0e39ff3163600907e11c2ce40ed4b80bf30c2e04d1c540ad36361656cd48e4fd841cc75f28f209cf4542b4f05594c14589545dd24075308	\\x00000001000000019aca8a2db37da037214e108b396dfe2974ba3170820812c82e18944347c70cfa53680f62644ec78ca020e8cbdb5e68fdb79f3bce316b43f8ddd02eb4ecab9fac141875555664f2dc051b01b178af0b203e1ded51b7e43dccf2a47f14e4a451d7b23a80912f05feabdbb1acf2c6413801fc1ea181610b57b075ac6213d0ec3460	\\x0000000100010000
35	3	10	\\x90625cb1e05e3005d198c038d055bc201cdcb6316a2ea4422090cd4b0cc0d801dc68c73d69fd7d24c88f4606521afa3f1a7cfd03dfdc1845f21a4efba532cb07	362	\\x0000000100000100343e44a3fd2c1de8073775ea6641962ddfeb4716e2e652aab360e2b6aa465de007ac7bcf9b2043c3e313a2b4c5929bbed118483f06a574eaa9467bd60521985a24c8ec856e9e3da0e10bf088cb410588878f33cea7005fb5781204d3f1746834ee13fd1636ff4d50b0cc1f0156255623421f899f8dc783d34e4f41326d6061d9	\\xa2d5e5cbb09d91160d53f45fbb4f0edd4786e3465e6deaacd66259ec3e5c42557db003e578e4b2c88f4936c088f4bee17db6b2ad7d0642d23ac82464aea24e51	\\x00000001000000017f0845cb39d264095d92b82fbbee0af4cadf3099a1f7e8b9b93e75cddaa0b35f633386ca136d68ea50f80f3c16967a5141969bbb4740d79dff24a2eab59e5a4d1795977ecf40adef49675c5078ee20113e12e390e644154dfb8e951237cafb9a5b8e193f2fa27c966321a18049d08c0141a30d0668d388fe9e271fc8685b08d7	\\x0000000100010000
36	3	11	\\x59277d4d7e8f097d45ad83e82e2b0c01e623302f8488c2825696546ebfc8c768cbf4e9f0de6d2db0a444b49436c0e60a0c98e99eed2538c33ce25a95c0d8ba0d	362	\\x00000001000001004986c64a10b6068c684f76b47ad53cc561d56d929fa61d95a431a7470debe2dfb86f9fbb9a55cfc6f09049a8018ae45fb5da7faae852099e50d581875dc507443dfb92ccc84e2d7cc74ab34877da321ba4fae022a573e9594cf6e545db3c533120bd929308863c05dc821ff1039cb8ef4ee08d87a3ebde866e840e1780aeaaee	\\xb30f08977d10fc4a8e7133c2ef48eff5d882c75c03cd26223eb062837976881eccd73a0a708ab68ebd757bf75a935a8b42487346b9471e9b44c8749778421011	\\x00000001000000016fe8d2f54db38d96cf5991b560574526840233fe76b6a05e896df57cf073efb954185aecf884db564eb887bdc01f6ce5b1b0543dcd3e72820f4790af798cca6829e24a732adda030f91fbc538ac6ad20afed1454f809af739e87dd2501ab448f8cafc7f3861a24081d3d96f449a4576dad0ac73d58b9a07f4976ff7e56964033	\\x0000000100010000
37	4	0	\\xd3ae4cc136aa7a0b0071b54190bffb138666d08ee6b12d5b72d4fe9f9e5b2ada3116054251b3ceac69670de6491b1fbfcd344e03e4bfe4f22a11da8e233cfe02	291	\\x000000010000010074c8198c01d3e154bd4f8678519e25ab9fdc5dda2300d3d9d6face76caf312c89cdb59918698b8656351a743db1cd4846b78cb2ea088a40c39806ecb6a521e9436a8ebf10372bbc9b2959fcf87db8b1166cd1a259b3300832d83572a15bb71bc86bd617e1c064e75430a6635e146e66995ccba162bc7a944c7358b24df12a02e	\\x91ee9c003c94612ef2fc7ec06dde8ecc1f772fc9fb78416a32a7e51b1efd7deb0c92f96eee26717392e0ce7374f404522b67f2b52c97b9170847e1e65f1fb56d	\\x00000001000000015ae780d632559012402350035f60f9decfe0159009b3571432839d5d0cb38845ae6e457951dab9608a0adb5f4e8369cf80adad24ce0c9a4cfe7741cc49847ea1a19d48155e83bc7308b038fd53986769336645c3ae8dfbad25d57333b5b8cb4033328a99ccd71bc765410b9055ec408d8a0edb49f57433244441d2042178f7c5	\\x0000000100010000
38	4	1	\\xadb62ea0fa2315f178254a0f5aefa6f35d52715d23c333e5afe4dfe8db067eaf251cef985f430d786b1a56b8392311473b9091db6c8165113e3a6bc2b19b7a09	223	\\x00000001000001007b8b295c07f4f2d0e8f32eaf3be68638674727b31010c99fdad5fad7102ce2608862e9b680c6390c64409e1be59a5818550a8f504fae9aaa6686c63be79696a0cdd00723f42203a715a382c44cad5f5b0ade23f4898dee0e9c6edb19123aab523ba4987a3d4c1af8efd71b3d6f24d2ed50ff786b976ad0e02de0932d2b73500d	\\xe40b9fade929331c29e9483136eb88bfb926ae7aae2cd94e9a30757a6160c618ea52cfe87244f657918bb34c04aa4a641e637d5a5e4c12eeeeaf7223804aa903	\\x00000001000000018f76ddbbd733be4a9f2dcc66d557188280455bbe18e37e098c69c20341128355623c8af6629f88c8906637cc80c0d5ed3542ce5bb429fcec4aa4eaac36b545ac24af91d1c0c7cfd31fb9e323830dc6f36c756e524640f0f0d4ba2319bd9151a5113d9624a8e82ef5d0b92005ac506946c5e3ed896f432700910438d335e467a6	\\x0000000100010000
39	4	2	\\x379242f0471af1a8b020ce8e72f4afe3c2c3965ed63507289332fcef34564bba30c6c431c6366bbe651d21b81ea95caaa7d758925253bdbea1ef1dd4567bad0b	223	\\x00000001000001008796725274636ec3e18071317c8fe6cb670c59dc12cdea8bade7243501565e277eae9d2e462eb317c88479656207b1fee53689eb8606e38d870a8672ae27ceb8373a1b0321b070536337c20ea1dc6acb107024acc4e368235a59cdd78591ec919455d0cb862f61b6d04d171d927e61f731e79ea4246857b08126d125c74086a8	\\xa06ec43daa23d9050b369b490ac738a27e48b81e5141946cf335d4187044b4ea8fa045f2306ff2d9882e2d4398c720b469d2a6e0345c5f4a0f0888410ba0fb39	\\x0000000100000001969682eff30725d67f5c47e54fd3e5ae9e77e086b1f6274dbf2173b72cd5188273855815c9f171ac37297935e1790438ac5832eb8625f38dcf17f25e82076d1254f348d4f4bb757a33c0f8350e28d872709b060d94ede256032274fc591be86a2445ed676e97e7b230650f808d2ef7423fad5b9002188b7fa701067c0e8b383b	\\x0000000100010000
40	4	3	\\x53925e15af9b1df926435cba0761ec95deb3325ed64988b7b7f5d8f8ff91d5cb470f42bf7d88470975667a042dc07d16e785e6b679e560d5bd2d23b68ced6f03	223	\\x000000010000010048ea397ccd1832b6ee2c9e368c580cd33be5489a5afa9b4b49f19746e605afadffa1a0500b1a2cb6d0e00291d46877608c542b30daec501f9ee194262adc8f645cb0186b3387b7b723b6391d302bbd8b45860ea793e248ebf58efe37e7389d8aa174de0df8d323fa7ac27664e9366d6b003959a9e0c9f78d33eef731b0bb6819	\\x5c6ecd0067b34e7044c079661eefdfa8681080532fd7aa603cc13146895fe65a84191d9224084a62a82579b0b95966dcbea5b07703511c7edf09d1d250ebc59d	\\x0000000100000001bf81802450770c793f553d09093ce2da7a29449dff74a4fa6bc56de8233ebda8f11a63338c1ad664040c53cb150f26959eb83719415e5c58bc0ec86928f47ad7d1aa2470cfbdf22c37e73322db9399c800759fafe4e635d346a2eb56233eac290d7c4e591d1265e2b6490c1cfd87eb812edaebed0eec3d0890bfb400a9e49a0f	\\x0000000100010000
41	4	4	\\x6426f1e7e0ef77c980e16f0b0e8493f7acab2ae7cc4b24a6628d789910d41df992e1df3a6341057de507c37e775ab9c2fa0ab491029909fb7e2f9c2d148a4d09	223	\\x00000001000001005f841b54f82de6a1a67876ad6a7f11ea72b4f57235535fb7a9defb19e493fd1896625ed71798bef16cf5ba83de39dc9f05f64d7750f00f5cb06e5d2d4eaa7b0b72a4aac27275d37d5c0431a145b4a897e81491dc5a6a7e5e310e1820b67089836a6723cdb4ddfb7621a9c80fc6c768ea16d0079cdb466827506149d8cadc276a	\\xed1cee102e4eae9c4ba89cc55db1cd033c63a7a593f089ebe26f4dbad94b25148d235a3e57ba07eda1f0962c6f9c7f49d87c0d17ed22c7e1eb8c842ff61c3cc8	\\x00000001000000011060ffeb9fbf2d1c263bbe2501b595d1b338188920eca070383b2d25b95f01656d6a821132bcbbd93e37ba26ce2d1c6de0c40a65602e08285b0e6e8c31e4a1893788d8bb5e4de6ba80a05dca8619e24dc76e7233abbedfc4709ce56588830fd41fb173b25bfea49bb580715cb446cf05a2ba952a3ba8378f9e57365f9632ad75	\\x0000000100010000
42	4	5	\\xcec8104c1ee9aa345e06e1fd78e78c8eaf561dfe97658dcbfd311d176f38a0ce619945e47a6e0c1dc20deee423b2d4e5b6533d0bd863513f1716d44a0973f800	223	\\x000000010000010014fa6f5d52b4cb62ea97d1c26e53301c85ae3eedf7421a13797fba86ce2c7f6c3492bf21caf95d6a338d11897be118741aed9d7140374e4c282de6e7a0c5f8f9a748fe075c47a5fc2040c55135f0721ed5daced3660a5c78c4c821e1a1cf14d0fd5e092706c869ecdb4f31bb9d812a56b9bb6e9f7ee16c5ce88afc1c78c664ed	\\x5491ddab0b0d678e8de282622e97fef80ea799bbc79a792263037a030bc553cde2498ef68036c25e690edd675e43a6bea23c0563c19808208b830749ad172ca6	\\x000000010000000161b1415ee6905093ac899a472fde81453433c4d88f7d5a0b07264d41c3d19b8d097ea8470fa9cb2c79a4ac6bee4f85dd5fc63e0010b4d9d90438eccfde647f7a8358d66c8f06e593d9c800a4733cd877bb295c4570f20e98432ae6c7540806b1644a53ce9de20f2bfa496ee1b765acb1f6e75ab59a080ad1e2958cd2923d088c	\\x0000000100010000
43	4	6	\\xdeaf6ecc7d719ce65f566abb70369c3b36374a1156153b6e3abf35ef5179abb0d05e250768208c05d56434440079b4eec728281e018c026295b3f36967a1ff0d	223	\\x000000010000010077abb5558c5570ae37641043423145978388e99d63eecde78d10cc2269a3e225de544bef1578d3effa03911e7ab1193bec9abfcf88e364760eabdbfdef249304b89c8682bb8dd7fa74003754b9e1c2d467843c0406417f6f7d8f6a95867f38af7818964dd6907a1130f99344510b0be78d093cb89a1eec948db757c06bf50607	\\x7a91834aeeedc912bfac5abaa2ed3003b9137b31b17ac5ee6ce492ced39824cc96df99604802ef4e553f8087cfc86c716db41beff878058bcd75ac01313f73a9	\\x0000000100000001c96ca81f0ed048c26d52e3906ade97923f07a8a1c259525f1ff8050da90bde53413a88a35f21411fb79eb1b89e5d372c76f08a7496be2391211a8ff8ba78069d92c0e2238bfd1ec09ecc0af08c57d688f57557b1b1347beac230ca402763e0f42a630f76914eba2a4c79e22de9372d04e292809c567749f24779311fbc2734b2	\\x0000000100010000
44	4	7	\\xba2ff77a70bec37c498b8d6d1e4d64521470364000b9067f4b4fc640e32519ee6daa929f8e8154e229e7df64cfd4c8bd99023e9381ad4352a883cd37e6c7bd0f	223	\\x00000001000001001af353fe26ccf6a94e8d1e37f663809e4850303280f959eb11fc51bd2a31de3e563fe050430637541080dbd7b3fdaec5361664472a2987215d7bfa131f4cd895e4ef37d9f108a537ab3096960b8e294f2d7fd65aaccf0425833dcaa1808340b4a7be49310ca4f0f20264de1faa2eb63f3848493a412be91b9f4242c92cea10d9	\\xdb79600cf34ece65cc47e13fe60adb68c360824758c440e85cf12eca2bd63a2b46703acfa778def21c9909bace49398601ab443769aadfa49cc5b97439d772fc	\\x0000000100000001c528072e314b6ad6bf8ac39a2a7533a45a0fa1c1ab24c2a875d8fe01a4ea3119925221fbc1dd90cb48114c07f437fd21993549cd7d531f6380d5bd1188dce994ad3c7725a33e014e57bb6976011fd736885d86b4df0349b90d92267ff0282de7e4ca21b54f57d411c36af3d993d03be8d88e43baf354ba700f644618f7234674	\\x0000000100010000
45	4	8	\\x67239f4d6ae2abc4b012962e9acc35a8a91f8b8435951e0538e15a9438ada71119f7f836b6b662a6bcb334fe719f89ea1a8509b58dfcadd45c57a9c56a9d5107	223	\\x00000001000001006039d9a2589fe356d68edcd84e403d8ec32b8873ac4f7f8b0396f92ae93b8aa83dfe626e811f4073030b3e6773b3149883a2746b9bd040a0065a869e0c89a730236fa3586aef2c360c3606a0861c8986303dfbc3a98357dc93fd555a4b1d0cd4c6a87f38eaa87895a34a7105c255de7ff617ed81fe9c12e8a800f515fc5e4321	\\x2e791408cc27f6f736edad8cb1ff7d60c5c7d5c2756f49416032cc5d6de9f8a109e180cf6ab6069cea09089090d97939772d2bf9c376c9649d50e30b3edac967	\\x0000000100000001b4a9fd0977c099d05f6b4b3f6d3752efdb96ada7799b86fa4f7db5a709c0a904e8ec54c8e017ae029627c1dd494a517a437faefde95635c6e66274e2c2c5bacacd17110377f9ded52086e247b6c1c2e8d96b5831814e629acce87d96d669434fd9da498d77d687f81a7c84bb615d37d81590f613aaeabb6a25cbdc3ed4919d70	\\x0000000100010000
46	4	9	\\x1b13322833f568295fb0be30d815c37bcbdecf6590b7817e0f1053b5af10274bf5a7fd6c304666bb25900eda63a1a98c00a23a1e99c83dacdacf031050a83207	362	\\x000000010000010007e1e4c25aa7f718be743c1ef3226270a2d11ac72e05672d996a677c3b52a7447f267dcc13dc691a07cbdac4e9b151c2115736877cfe2ee90fcec7d7c253f15c892257f5d3808274ed78121719509d03dfd2d60ff5bcd0e7aa9ad143fa3c45f60406d7cd94cf8a5689b3f01b05cc98b4880e1f9af21e314fd1d79910e5d0e990	\\x73aca408d54f468433ce07fe44dabaccb49b5390644fed244ca37a7c28af4b8d787359ca9a1acd982d61467dfe8b7dfa0c1819fa4307905e4a21c60a526bb137	\\x00000001000000012279b155baa3579df4a6e22e4e416cd2bac56925a3f94e144d6c418c92a5cf1f4697cad5d55d392e90794fcb1913a02e255fa480873ec28ff7dcd30adbd29967ec7942cd2eabbf4c53158d63519fe3ea0ac1baa50c072af9e44b95f9b6c91ed1bab054ff61d8183a984d545a063a71de06420a1b2d5ef504501f4a42dbb5714f	\\x0000000100010000
47	4	10	\\x6a6fd874cb4327b38c9ff7a773c48babdc4834049134cdc3a273a3b8e793814a258587a4afdeb120080a1db475a0f791d5dbfac7559a386335a61fb3c1cebd0c	362	\\x000000010000010047d5634e6d96594b4d1166faad2da3c06511dbe40c19cc3e2307f73ebdf395328eb3316510df9131a593c32f747f05e56ab2168fc0c4d037c4f9c3ccb68615df2f9f4e9222580d1c6b4b58425cd2b95e542f1a73c49ec5a03a18a200766bfed6af590f4d5f1a6c0328cb6528263dd43857d4f98a5ef7129eca8ef4d65d974302	\\x66465217c2aeee8bc4020a99027bf5b268d2ad658b6972e5d997512275daa427187767ea406fa5ddcbe58b3741fa9a513e7ef0ee0f0e61475d517cae6e04cd4f	\\x00000001000000015e1759614dd64e6914bd7e0edef110a81f8f6af1c6ac77b2fdb4f43b20f28f0638724a43f5b6ce94b0b7606f2678f64e1a9f23874d3b2f66b00b0497290c70f042735926ab6bbfdf7757282a085d310e2075819a159e53162ecb3639a2162db1fe636e5af02297522a719a579f9a99ec74804a6990719bc3662bad5f53045c6c	\\x0000000100010000
48	4	11	\\x15bd01f796e8a8d721530debbbda370b3ad07de00173252cdb0dd96f6ce3483554b080af1d4d558c8c224e3fc437ef959ceb25f01281f5b10051fe0aa418dd04	362	\\x00000001000001008d97aba4caa6d171241a79acc82ffd94694aa86da485183166122a810104e07432c7b2c72f27d8ebb34bbe9ee0e860babf85be6638d4c36a1808c4e1f0a639fee8e01de8a3d8680d1239c48b178a4ccfe1742932f88faa682d931bc7ced693eb6c5ee3a82e790cef7d2be12554ba1198430ee710f5d1a0e8f416b32b8ffca518	\\x4b72da9eab68785706dbc84d4b24077f8260c9f0bfd6dfb6548c3dbb49f37af94c91f0b0bf4d3b001a044cc1ff9dd2291e40fe547a28c84327e7a0e725a03b64	\\x0000000100000001201d927dcc3f95ffc582ab33906d0542758b6c37f9817c973e15f94e8c309163cd04c1428045ee20392f003cdcc92a75c5da53778531417168646dd12375733a0760e2c649e41f648e1955cd1d3bb56028725a13597d2c450a86f0c37a7bbb337af56a997431bb55152a0aa5ddc22136dd9cc69e81313d1d9a86f64c560bfafd	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\xabadec8a6b33d1596bf0b56211b603ea9918dd60e84beed1e1e6b890b7afc662	\\x1bfc2cb83f222f8842292b40f3f44d98079c5ea36aa61acb1bfd7482979c7e44bc319551e563079d22831b9b939b25587983b93bde3be8c391b72265f79e36a7
2	2	\\x69e7289a14040bad3dd48421fcee918070e51b4068eec351f9cf9cd35167de1c	\\x98af2c295e07dc339d0d88076ad4f0d64810241aff12a5227e41a83a14010135799e1b7f1d556e3ed68605c24dfad8018caca1b96c407e19156780ac8f67f34b
3	3	\\xe99305b7ff9ddee3c7c19f1eb1081f8dba04df3d263243edff182bb08567d323	\\x239a997674fbb6c19786a87d9394695f1490b3c12081958b253981db54bced104ac2d0214b915993d5b37e55a2eed30df7212ef08c9c7135f41b29d4478f5c9d
4	4	\\x9080f45fa86f3b3b3811837f28ad264af46659b47fa03a0c79cb20dda62eda4c	\\xeaab02994e7a340b82ec9a922e5a4bfebc5f20f3a5a816378a73a6be8645efd9c8e9389e5a3cb457ff437a25c169fd3c2cdf6a18ffd0ce37680518ac36065bed
\.


--
-- Data for Name: refunds_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds_default (refund_serial_id, shard, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	1426881619	2	\\x68f6ba2eb47ca0a67b538472e831120c6919b05d88090b6e94d23352b9322884d69641670c716bd5b936939bb2d19840c8c68521cd3a9b53fb62d3816250c604	1	6	0
\.


--
-- Data for Name: reserves_close_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_close_default (close_uuid, reserve_pub, execution_date, wtid, wire_target_h_payto, amount_val, amount_frac, closing_fee_val, closing_fee_frac) FROM stdin;
\.


--
-- Data for Name: reserves_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_default (reserve_uuid, reserve_pub, current_balance_val, current_balance_frac, expiration_date, gc_date) FROM stdin;
1	\\x21103a25c426b0d50c6f288ec06b1cc12e00c24c86ba46f09838dd55274e185f	0	1000000	1650113761000000	1868446564000000
2	\\x0eb030079f6dd6ef8f334fa3909de7bbe6571d0e04ca2096ec6f42bae7999c8e	0	1000000	1650113769000000	1868446570000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\x21103a25c426b0d50c6f288ec06b1cc12e00c24c86ba46f09838dd55274e185f	2	10	0	\\xbf5c4070abfc28fa3a801bb819401d8dc92ac20962b5a308ec9c6d07ee26a856	exchange-account-1	1647694561000000
2	\\x0eb030079f6dd6ef8f334fa3909de7bbe6571d0e04ca2096ec6f42bae7999c8e	4	18	0	\\x1e35f1bb440d72b935d1d4b332438662dc524f0eba57c35deda08425a29051fe	exchange-account-1	1647694569000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x0077bc3efeaa48f6faa29d4af46dc54ecce365edf839f13bc93e0a781755cea660bf2b2b044016989d047221925851aae7cc9f80f8a7681092cabb9182543952
1	\\x073ab42ae1f2c71aa4c5989601b4b1998f571fd1e15132ec54126f89246393e2d23d2bee869afa50136345c075f32a4b6a361121af4092484b7ad667bf690370
1	\\x1a66042adfc649135a7d8e8e7e13014ba4fd34e146c32bb2ca40cb8ae81f7a20ffb25be2c79503cfcdef3ad2c9ee54ac32acff1085241380b6bd3f71b3fa855d
1	\\xfee96c9ae0889295c6a22002885f59e1d38d8943d9c6b281d5739010aa19947455befd3469c654eb4b8dcd7c3109a93d0be6eef2058a4ebb23e70390310e767b
1	\\xa21ed21093aa5117ca21285f744cb2f51f6a8dc87bf97900ab3b5ff4a994bd816b65a5fcaaa56d4f7209b7627ba37e6151768f667a7956719a249048462a2ee4
1	\\x91a175c0450d5a2e177d736a65535fba449135f21e00446354f32de1a982c3991266ff296643e52c241a78ef212836ecdcf7b07a33efcf3d17565db064cab2d4
1	\\xfccfd1a56d8b7a484e83267b781e2fc7a6c38bc748a6a07926e09ec4f64856e8f2492e908d87522d65e4680c51fead14e1acd6c1e410bd1a17aa1971b0e2a9a4
1	\\xf5c5b9af0cee0d96d6dc3d30b4eecd967c98d0c31c33f5ec850cdef21d8e68a2d7884b60635c84a8323fe7f1c1f2a234054d9a31a21e36d66d6ba52ac8fc0027
1	\\xaed1c9e07e9116347446e50da19272f7a5695c8c03f90167539b85f3507e4599d3674f014c6607b18c4ed738cd58f71cd4d1c447d4047f6c54fb1884d0820263
1	\\xe30f405d265ca46a78ec0be41a15521b4bb570500c7700932ffc6b3e2064af6ce1dbe7cf51bedccae0a62060387543eb264f92d61f84bf07e293c5c2a73baba4
1	\\x2a70e4bfd8a1afcad962a5be0b64b997e8aa1ebde883e688a5719da0ce7312765089ed826aaaf367790189278a3a2c94dc20aaceeb4ec1141597d79fdd3394c5
1	\\x5e879f73db7cc9d7d5713b32d546af94c4a72229021f2d88cfe3422411e9223d13040326c67c2bbc4f1120902eb2ca8250f75be9b7791c0c05bf8a4d01e00746
2	\\x9fc0fb7dae9ff4b7471d801f64ba756a823e4aa92f7b4f912d8392a52ccf6c013a96bb1ae27c8adee4d2113e8106ae0d69f92b610c44c4e783286d1d3e66bf96
2	\\x7c61711f0601a332e1ab2e286ff4803c4bdb3edb80f5141ea027cc4eddbb82ec7e0965aca211982fc3dcc954b1df2fab0a3b3be52905e6116031d86127520f1c
2	\\x1109c0d6be10c4ed6d93716449374c696629584c803e02d39d53bdbe176a2f6d34b5ed2b991f491f29ce91fae7d53ae5a0b481cd3c27329c860de59dbf2a8158
2	\\xc45e94594e7b6f47073161d49efa9fb4bc62c71c8b5e8ebcbacd25ec43bde25c4b12c5129e8c720cbf28f89ca6d6b90882eaaec422be8045a22d4c5a65f3bdaa
2	\\xe63280862d4d05e9ef31593cc595cfe769c02427ddf80c12d182831279891b2fa8290c6ab93be70db6dbd02326eaad6e9adf93c9d55cb635df9cde56212ad307
2	\\x8d5b7d08a309d8c2c42e08b25fb615f17862a1561050e2babb300aa4d6a8610f5500a967c02e599036accf91475920bc7f095f4921c36208fa0c711a4b1ed6ac
2	\\x5ecf68923750db8b6cdeb997c571ea79b7267a1e5eba12bbe7a4cc3bd1d35fe611ba3125716d8dff08beb09ece2a7565deb10f2453acf5b19617e6da678037ec
2	\\x42806aba2a5486dd3c1dceeb6e2e27b710512f3011973bbad79532d064c94fc15a52995d69cf15005281431a24b7ef7721b63504a0fa941eefd1fa555c32cc85
2	\\x1154257d09072e3d17da166f617abac5a8e3154f645ece27d10599e6f4437226cb2ad5e6d695fa453a686350993ba683f3db4d50e02d0c3fbc076b1aeab2d8ad
2	\\x937f38efe3f42cb0d5366b93bca2c10096785c9348ac1572748e46a1053e56e5b3229a855f2fff86d76aa7a01011e37e8ac34ae4d4c3713b40da46e58c4d94b8
2	\\x30e6f1fd417824642202a0bf108c29596f8a621270e5a30174f0799a3ade5ade0dcce9c7e1da9394b8087a57734809aee111714858c96f2c4e3e4658a2b6b26a
2	\\x8c5e3549fdb78d7993ddf0b0cf06da05cd24f78b354d1223517da494f113db4b287c23971cb01904500d36dec049eb262b35cfdcdb169dba84042446804e5574
2	\\xe38768be542fa7057a681eed3947176555de51069a0dc0248732832a6aaa2f73de00362e723c4997a4fc59b7e5686d6033a2457f582d3269ff75a20d449b2eb5
2	\\xd14b3661bf3482062c9e4f6c43db1fb3e874f9ab806cf723f18c3788d3d6c535c2776c149e69d558c6e23df8f7dd0ee73846198af55cc447c5f2f0f56b19b44f
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x0077bc3efeaa48f6faa29d4af46dc54ecce365edf839f13bc93e0a781755cea660bf2b2b044016989d047221925851aae7cc9f80f8a7681092cabb9182543952	162	\\x00000001000000016556f9ec435e2b2b7715b950bdc2e672a7b454be11e17ee71784d3424c9f6ba309a0dac212463a67998137285e211593242494ac02a438456df23564e17950b48a813e769894e5c6d1047c7d4105f2eb4565426af038e8aa5ac0152b6a70b08888c7dbf9812576df1f5860e2eee8ad0d9ac59dd307bd0bf548d35819a51e795f	1	\\xd7cbcd38308ea8540405be0778f3297e671b733c10241358a512897e16c34ee483037fee0bfc403de63c1e292940891fcd33af27cafaa72b86ab6062f90b110b	1647694564000000	8	5000000
2	\\x073ab42ae1f2c71aa4c5989601b4b1998f571fd1e15132ec54126f89246393e2d23d2bee869afa50136345c075f32a4b6a361121af4092484b7ad667bf690370	291	\\x000000010000000136f05775604dc76cce1318947010229ff916520cd7a93a4b1ee77e8ea1876bfe4efb2cbec4fa9fa14c196e2aaa6db91c7038324ecf70bfa5eb83aef796636a4f71e3d0daa0efdcf0336900e7b38b391a5bf64ce48d13ada49416b84586b0bc8eeda4d01234adcb09d1bce0142f12d5f38bf4717254dba67a4696b4741b61c033	1	\\xfe53bb12d7bc4932565141708deedb52b22feab2806c98d7a401b36299ba45ff74e39d76547f9de16d657dd4918671448b8785275200aa0810d0edc89575b70b	1647694564000000	1	2000000
3	\\x1a66042adfc649135a7d8e8e7e13014ba4fd34e146c32bb2ca40cb8ae81f7a20ffb25be2c79503cfcdef3ad2c9ee54ac32acff1085241380b6bd3f71b3fa855d	223	\\x0000000100000001453c273f7735c3daa973ba00ee30a5f8cfdee93bda64febaa201fe95edd1cc3586be4dc6b26da8a516d768cc65d937f178619ec10d562adeda3c3326fb7e43e09beb5d1b8291f72100a7cc1a79e52296f8e4bed4f5cf7ad037f0d1a86910a037a45bf29b3413b269bd1d073cdcb3fb66f7166230a4f553d7450f86cb4dfa7bb0	1	\\x27e0bf7c0e33df14443378799109cdc31e3189dca5c88a1c9c6040b4e3bb476f9818a4bc757f46d22337bac4e7847183a7b343abff0430b2906ee6e49e0b270b	1647694564000000	0	11000000
4	\\xfee96c9ae0889295c6a22002885f59e1d38d8943d9c6b281d5739010aa19947455befd3469c654eb4b8dcd7c3109a93d0be6eef2058a4ebb23e70390310e767b	223	\\x0000000100000001208755c5563f35941c88d482130c66f819a296fe973d004ce2bfc47587082567becc8ba091e28dcf898fb507c319313746938dd753d5a2623adc9a0c5b607ed40a797b6760427f045d97b4c46c14eee56fe30fdfde5dd277580d24c26b1462f41049ab21b6f918c2cb139a4629c0ff83b0c01c433318f8e197b1f0eb82fea460	1	\\xb92d4ff911b5caee1781b105abaf157784d69a51bb1fb0e09b42c9e85056e83435bda3d87c09e1cf02455f73ca539cf48ad8ebaddc36ecd21badc85db9d1a602	1647694564000000	0	11000000
5	\\xa21ed21093aa5117ca21285f744cb2f51f6a8dc87bf97900ab3b5ff4a994bd816b65a5fcaaa56d4f7209b7627ba37e6151768f667a7956719a249048462a2ee4	223	\\x00000001000000017399e1865093c4fa7b6140e96395653dbdd532f74e76a353fa2573d6a1d53c41cd6f0be55ac92a9665348da43cc109641f7d68dce44fc4e04cfec874258fb703c702b9d1e1490a47bbc471ddc647268a2c7550cee8ed52eeaf2dbb4c45bd1002da45b7ceadb03c455f0b257a323bd462a9f86e7778e7582fbd2196b94803aed6	1	\\x4b3b006a53766995aab7764d81a6b0c40419c24dcd64d8ef2105574a27797e4dbca2516f1c67a2cb733d7ecfd761032a633273d695301345224bd5a716d5d901	1647694564000000	0	11000000
6	\\x91a175c0450d5a2e177d736a65535fba449135f21e00446354f32de1a982c3991266ff296643e52c241a78ef212836ecdcf7b07a33efcf3d17565db064cab2d4	223	\\x00000001000000013632f7a3b156203208e2cd200fb790c61c39a8bc0267648bc7e412b1c7740b9bbc29a2a756952a0bd0de8f44ddb5d9a1b445a1b06823a596f8b53cdf20fa5885a57b32507b36662e8eb83bb2084b56f105c7758f5753aee752a9caa56d427ff9ad0e0405295960dbae4c716e4fff58b7c31ef4cad5dc8f97e32327eeaec7855a	1	\\xcf2dcf10366be39248a3c92864d0bbec6232912806d63cfb1d5deaddebea803b4b2108b863f671b8df8af5090d4c2056269dfc75022cdecd462eb5ae1d68ef0b	1647694564000000	0	11000000
7	\\xfccfd1a56d8b7a484e83267b781e2fc7a6c38bc748a6a07926e09ec4f64856e8f2492e908d87522d65e4680c51fead14e1acd6c1e410bd1a17aa1971b0e2a9a4	223	\\x000000010000000198a6aa2684c8cab25b54944036b9d9fc3a56cde3054ff7f416f00d1cd792b0495184dfba0e1152b7aa9991887af062f235c5188cc7810e62c510c4c0c0604d9680fcdb538963fb30ec7d172658d0db631a29c8443f62882113eb18af77417158989415dff13c6b3195585e6ac696127128601c34bc0f624ba0ae3efe2972e6e6	1	\\x9ac295f159e8845cc9eb72aad563ad4ca3f19815233ca887aa2b60bbdeff4a542f9d2d77fd377aca15f5a09309451d5dbc7f630a401bde339a5cbdeb2d5ba809	1647694564000000	0	11000000
8	\\xf5c5b9af0cee0d96d6dc3d30b4eecd967c98d0c31c33f5ec850cdef21d8e68a2d7884b60635c84a8323fe7f1c1f2a234054d9a31a21e36d66d6ba52ac8fc0027	223	\\x0000000100000001c277e1ef347e86bd5645780ff8585e6adec9ffefb03b3db12da098fa5315746fc2bb7035bb5c08f947b6724e8075aafb444649c0ac950285ef5134343116fe7c62ea444f2f36df98e65929bd79b4c17dcfed72bc6b374fd4f7faed4a9f74e84291695dece84975b1fa7cec481f70d558e2c08ae5d36457eaaa7999932af1d340	1	\\xde31bb6c3c341917b3f26388d63f2494e2155f7e2b1cb0648673d605857fb8b10c97c712c669e6ea0e4f2734e4abe0ed0fe82434125f31ec1a3c1004d4f1d900	1647694564000000	0	11000000
9	\\xaed1c9e07e9116347446e50da19272f7a5695c8c03f90167539b85f3507e4599d3674f014c6607b18c4ed738cd58f71cd4d1c447d4047f6c54fb1884d0820263	223	\\x00000001000000012f36a8a040657bbaddfbee04a9ad02f0dd9fb4b26c411d9c2a0c4e484d7961cce7b6a7e22ab5de338e650c957a147a41e3e7672be511babd704c8c50986980cb5279b634b4eb837d53e218519159ff2b51b199a5c478f2c319d5eff74cfd291959b78e29b99d7b5268479f3ac168559eeedfcb2502e4ad850c8acfcc6cf529f7	1	\\xacb5cfb4e0f35c30ea60a3c5ac73a0cff7877e158bbd8816b488687236c3c4c5e3cb9109447d72df584756ab51828e5ddf92ec37ac2c0e75fdaebc6678a8df0f	1647694564000000	0	11000000
10	\\xe30f405d265ca46a78ec0be41a15521b4bb570500c7700932ffc6b3e2064af6ce1dbe7cf51bedccae0a62060387543eb264f92d61f84bf07e293c5c2a73baba4	223	\\x0000000100000001121b933ad4bc9a2263ef08600df88a487bb20927a6265d1b8982902c4b955331d66a5539580229b333bcd54070e44249c81d81271f1a03e6a8b03b0e0954bf72cf7160780f42bcb09b72b1fa42d468baa7e8664cb98b095e543e6e4f0a857f5b39ca38d4f6dbde08387a5868ad47ab9e94667efb99d17173cd3819636f815f68	1	\\x4e1e5b0f9b8c1c12d274ea244f0e35e47f0bd7a1f4047652c55c40f36e8fcf9b877d575e3bc48f232a3679e9328fc99bcb6e16e7235487aa1850cc1e269f330a	1647694564000000	0	11000000
11	\\x2a70e4bfd8a1afcad962a5be0b64b997e8aa1ebde883e688a5719da0ce7312765089ed826aaaf367790189278a3a2c94dc20aaceeb4ec1141597d79fdd3394c5	362	\\x00000001000000016d323e2b5adc3663629981ec7f02d0fd1e5e855a357375198cf8cb5100f35edaf97feadd2ede1a6dc6d24f236303fcfafab2a19bcfca335c96d720a8845bbf91f01bc1b37460e9eaa2f4c677bb4c82f2894fce2a815e7d33835f41a0fda581127d124d8368da9291f2f442e4ac4ba174f66362e83d2d8111fd9a1b81462c820a	1	\\x3e522419e72d46589e6f4e89172517696e9fe9b8946a8eb72b5648f55288131419901c23b0cdce381da4cba60f84ef33c30fbb57c63ccfe0cd9aa0a9edeca608	1647694564000000	0	2000000
12	\\x5e879f73db7cc9d7d5713b32d546af94c4a72229021f2d88cfe3422411e9223d13040326c67c2bbc4f1120902eb2ca8250f75be9b7791c0c05bf8a4d01e00746	362	\\x00000001000000011cd7b7bfef64956169f790a285ccfc93ef011b21326a5a7dca3e0d7864744f66ebb8afe8c4bdb9cabd0af34d1cffb425ac2d99428a6349d9a06705ca379b827d8404a9061ca8244441d24c970bc3ad99dedecec81ae97b8a7e365ebede764d08123f8571cd5d89100c7489acbf687af932126ec2fd95a4afe6e33d531da697c3	1	\\x8234ce22298722ba8c4c6e5eddbb6955cb453953cad786c6dbfe96c29b76721f659f3d01e9c29962b8e43fa3b232f53a84353a0b90caa2f99f7549c8609ece02	1647694564000000	0	2000000
13	\\x9fc0fb7dae9ff4b7471d801f64ba756a823e4aa92f7b4f912d8392a52ccf6c013a96bb1ae27c8adee4d2113e8106ae0d69f92b610c44c4e783286d1d3e66bf96	62	\\x00000001000000010fe7288b87032c1ea8dcb10a859b40586d4f4f02dc2aabd19297784424273b618883d7c73572995a4ee490a1ab21671c9975e27528093fb6b706378f1c886b4e27a7453e274699171f5670c381b944d3c291217503026bba35926f322a9582c534f111ec9b988ca444e2aa23030abce1ebf72fbbe2ec611417abf7ae9a91ba62	2	\\x793656f8e85c44bd6d82c094e288dd422a46f2ebcf1801a9ef8f2a5bdb1b1f1375cd2bb6952af82bc871cf8882da6905ef784da3b200d4d7a81cf242f866900a	1647694570000000	10	1000000
14	\\x7c61711f0601a332e1ab2e286ff4803c4bdb3edb80f5141ea027cc4eddbb82ec7e0965aca211982fc3dcc954b1df2fab0a3b3be52905e6116031d86127520f1c	418	\\x000000010000000104339df0802e9cf64e09d2b016cd936e488151053a015e72a5ef350561b749e8b1f660a273a3edac185cb0def7cbf9ff8ce90dcc961d216278e4bf4d105268afd7a80879d8fd1f6c018e1c690a422728cb7c07cbd16fb04d09a5ceedd520a12685e6b5a2a6b9aab6f61bf2a2c4a8439261e2be10121b5f0f5db400364bb438e1	2	\\x8181a1135785fba6caedaa76443b89feb6953dca8b38da6db87b5e0e7e0e8977a717c57297f906fb02548d1697a7712d6e665c600f1e92c52de02b9c63becf09	1647694570000000	5	1000000
15	\\x1109c0d6be10c4ed6d93716449374c696629584c803e02d39d53bdbe176a2f6d34b5ed2b991f491f29ce91fae7d53ae5a0b481cd3c27329c860de59dbf2a8158	275	\\x00000001000000018a06011155e904bac876dfc8d41a567ac08beced83959a2a3f33f2ad04ca899dcf92ed5a88d74ab82dfebc964938d25eff944da657e7aa7734cbb0bdee0faae1917c8a7971746b2d05d6951ec79198e8461480c1631e7e2fe8320f61696915521825a6f44346192fe6af815bbf0e0892680718b9aa39e5df91d314458fca7ce0	2	\\xe6763fdd39125b9438ec77172f18df3ab625de61cba7d4021364109a15df4f3a31848f2dc0ad376b7ff8fa64f48c56ac4c3362ed6f40d9bcb0e83190feebb407	1647694570000000	2	3000000
16	\\xc45e94594e7b6f47073161d49efa9fb4bc62c71c8b5e8ebcbacd25ec43bde25c4b12c5129e8c720cbf28f89ca6d6b90882eaaec422be8045a22d4c5a65f3bdaa	223	\\x000000010000000198a5ab04a87069ae094d71faeb7ea65058d40185097c9409368aca76bf30d2e80d9b3b67451fa659b0cb946c19c44e08502c83cd82a0c78eff21cd10ecedadaf4dff2127c87d4a0d68bcacce5648e8fd76c95dc6e5120beb8370a4def7ae27473f640c2fb82b5f4c5f23d92188e402b99da2128d319c3da49d37bc6e57367395	2	\\xa90038d8716360b6969dacb62841f91f3e4bf22036d85e46acb4443dbc5439fbaba4c8c8f27a2f3d9fdeba35e57989f76b3afb694c21ffed380b7be47f293e01	1647694570000000	0	11000000
17	\\xe63280862d4d05e9ef31593cc595cfe769c02427ddf80c12d182831279891b2fa8290c6ab93be70db6dbd02326eaad6e9adf93c9d55cb635df9cde56212ad307	223	\\x00000001000000013f8497a059fed664639d96ca233402361ae7194ef2c6fa30f033a53a9e300febac721351dcdf5ce621149cff4727e18af226766b3cc4fdbff13abbea975e95c6107563cb5e855fd9d3c452bde406419b1838842b12f2538d082952dbdc4a83c553f6ddb516d9591a242172cb9a465547bbb4d73e8406ad738e0bb5f43215ea7a	2	\\x124c694d7a640d307a1dfbd492b8242474698ba8a8a581d6747f9f73a8fdb5105d24d3978660247450150a49b14c87d22d0c9ee97b73c61fa973b2a57a5f7004	1647694570000000	0	11000000
18	\\x8d5b7d08a309d8c2c42e08b25fb615f17862a1561050e2babb300aa4d6a8610f5500a967c02e599036accf91475920bc7f095f4921c36208fa0c711a4b1ed6ac	223	\\x0000000100000001236487b0a590f6d28df5ab96a225d4512c3d8fa37122ef28c66f70c3bec01f87128196f9d56766f9ea5b51bbed4b6b818fecba5c7d809e6fcbc2fbdd6d1d30bd54e89da66606cf9b7d58acd942df38085f239dd6f2adb33df50ca014c95097a7165ff5eff2947ade81216323b93aa43e75c5901f3f945dd95867b563f0993603	2	\\x8f87173c5ddbecc43a6f26eee3204bcd07102bf6c8a0c056907301ceab54febfb11617635eec25fb706de4b5101b4b5add32aced8ee6564b6defe029fc32f600	1647694570000000	0	11000000
19	\\x5ecf68923750db8b6cdeb997c571ea79b7267a1e5eba12bbe7a4cc3bd1d35fe611ba3125716d8dff08beb09ece2a7565deb10f2453acf5b19617e6da678037ec	223	\\x00000001000000017256abedfaa16489908c937aa519e454bde401b0d0aba9b37d350e002debf308fe74a7b90f3060665f6922312af9481946094fbe0062c25baa75842bb357d8714270605dc1a04d6cac2a97d9d92560bef04118b909a71801f543fbb413bb050c24c36318679f5d7f87e2569522d843dfd404654899e2fa6097b4f96a06cbd6fe	2	\\xc0d0294e51335fce86c76cf2ad60e51d9cdc10a2fd70d57f6c685b86c4b4524eb432b7f4c3fd7b14abcd7000aadf1b5d2f6ad3f6120e8359aa0060db2e60bb0a	1647694570000000	0	11000000
20	\\x42806aba2a5486dd3c1dceeb6e2e27b710512f3011973bbad79532d064c94fc15a52995d69cf15005281431a24b7ef7721b63504a0fa941eefd1fa555c32cc85	223	\\x0000000100000001664738f3e856206360695a0afd199834b233dd27ca89eeba123b8d1f3430ec7a157c57d9a31a8b36399fca1797846f73e12b80564ca10f38f5dae131089603b85eaf2890c6fbfed0d62d45b0b4926467a94bc16f9493ce461107b6ee92cd5a6cdf79adf7f9e3a0122943ff831e54559dcd13596ba6d46ccceb6a4fb86ec51138	2	\\xb3d9d33560ca306a7796acd347b8dc6b17baeea827100ecb4fd7ad06ee60d9ba6ee97322c5d108b20cfece09694644f16b4007635cdd149ffb218cdfe9653f0a	1647694570000000	0	11000000
21	\\x1154257d09072e3d17da166f617abac5a8e3154f645ece27d10599e6f4437226cb2ad5e6d695fa453a686350993ba683f3db4d50e02d0c3fbc076b1aeab2d8ad	223	\\x0000000100000001745d33bc9ce9302e846b72fed21d67a7cd4dc1244f3e78e9ada1ae0f8d7bbae3e317a874cf4299411585ee9bd9fc3128ecbf3276dcc2508fd51f9fa3c3bd0efb3f5ee2a9bde32488207fd53fdd9ea83c854802d81fc753f2f5447e7a54e2c88c0facfd94ed10d95be467ba047e3f27eb6f8d29521fcb847dd1b57d1d30b5e6de	2	\\x968fa98223dbca1cd6a6356e14b1bc206a00a0e5aeaf00f90a7d3de5e150df0e705bff62d3780576c5f8c981997219cf1fa9f262ff2ec4f623d9493aa299af0f	1647694570000000	0	11000000
22	\\x937f38efe3f42cb0d5366b93bca2c10096785c9348ac1572748e46a1053e56e5b3229a855f2fff86d76aa7a01011e37e8ac34ae4d4c3713b40da46e58c4d94b8	223	\\x000000010000000141c25d8b3ec7ae2257363e12316ae1ef3617b26a1e6ba4b7120fc2e7762644cef9b1938244c7e56a7394ab270d4c9a09230f9e31db6b84c3f9386b3de03338e5171d4ab204964986fabad4888b2284dc4c068ab78496708fc76fc58a4fe916c6d0f0983ab879e2c1d5921c13175cfe5dd2d9ebab8bdaa60ffb2ce4e801ea1fea	2	\\xb5c2d9a376d767ac31e3d5c75063aaefd40cc162552ebfc786cfbfffee8e4688d4dbb8871e23c8243cdf5195d66b2c717beb602c81f4cc0552e62cff200e2900	1647694570000000	0	11000000
23	\\x30e6f1fd417824642202a0bf108c29596f8a621270e5a30174f0799a3ade5ade0dcce9c7e1da9394b8087a57734809aee111714858c96f2c4e3e4658a2b6b26a	223	\\x000000010000000161f204a537a985a27178340bba699b8a205e8fd61e14fb7fcfac7064400ec2f64ee52a6bf5bf29f8948e073db15112f643faa8575fda7b7ad865cba3eccaac89f8174bc89387b46d5f9b02c82fa78b650eab7be456c55b8496c39ad063812f2734c3c344283c5a410d9059d2415897385fd9f86540b66d147d2856540f1179f0	2	\\x0fb322fac673ede30812877f2e54d6e0c47da0e0d91a19431a66c24940f6e96720abe120395b9cd43e3fd015035cf4b80bbd8ad713f18b183692ac682b9e4805	1647694570000000	0	11000000
24	\\x8c5e3549fdb78d7993ddf0b0cf06da05cd24f78b354d1223517da494f113db4b287c23971cb01904500d36dec049eb262b35cfdcdb169dba84042446804e5574	362	\\x00000001000000012f4a1a368f9a72f8ca6053bbad424ff1eb0920bc592a1a6e39fb2f01af59569c7043059070b9ecf3f5752ec1ae2b01a5ab9c2ed18086ae87859d2d1446e458dd049bc15c6fdf4d672705b02da5755d969adef5e0af67eba63494953d585f77c8cd008c69fdffdca68d4408cfdfb445727c08a5be6e3b1e15be7216f197cee242	2	\\x0ca48648bd487b080e9738bdde1c1e9b307c9e0afe39c59c2c987b570b06ab9f8756354492356f54e682d4df2c3aed928483d4296b76e5716a3b5c4e9f1f6c02	1647694570000000	0	2000000
25	\\xe38768be542fa7057a681eed3947176555de51069a0dc0248732832a6aaa2f73de00362e723c4997a4fc59b7e5686d6033a2457f582d3269ff75a20d449b2eb5	362	\\x0000000100000001a23e34175bd2e15d0ebac54ef6e1acdec579a8d3b24848945a51e0c4697096b9b666d6adcdff3d064f9e605835deaaf3a1a11cec87bd98b590b1c6630c1bfd2500660290d2cbed99ab9bfe5a33a25c235a21114bf2d47f3fbdddb470aa3424235db46d997dc74342d8d1d05e3cedbf99366b4733e2caccd27adfbc5dcdd081fa	2	\\xb73d126e45d4af8d2b666bed194f0be93b149eb3ff40a2f162ac4c7412fae217e0811a25fa5eab42c37f3e5624eb0551b7e646259d4a74af68c1fde5959d570a	1647694570000000	0	2000000
26	\\xd14b3661bf3482062c9e4f6c43db1fb3e874f9ab806cf723f18c3788d3d6c535c2776c149e69d558c6e23df8f7dd0ee73846198af55cc447c5f2f0f56b19b44f	362	\\x000000010000000122dc82df3ec39d871a2ff8490de31ccb49aa5523614a9ac024c817b63f7d18b4b393618e356c368b48b8096a4f64d9837986efb1286b73d763ea715af65dd27c03afb836339eebe2e69c6055f8e5dbda99d8e67041416409c7e16445f4edf61c9b4a6ca3928a2b5d11e96ba4768fdd835f7bf00f39e4ea4192679a274ccc2100	2	\\x6ce4d1db9d499f71f33b9023ef8592f444412af6d833dc3d45215f1f959525fa279ef712cd1b8250e943af2d173fb802f257e6433feeaca514495ec5d3474109	1647694570000000	0	2000000
\.


--
-- Data for Name: revolving_work_shards; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.revolving_work_shards (shard_serial_id, last_attempt, start_row, end_row, active, job_name) FROM stdin;
\.


--
-- Data for Name: signkey_revocations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.signkey_revocations (signkey_revocations_serial_id, esk_serial, master_sig) FROM stdin;
\.


--
-- Data for Name: wire_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_accounts (payto_uri, master_sig, is_active, last_change) FROM stdin;
payto://x-taler-bank/localhost/Exchange	\\xf1f764a9854f478f0188acf4a1197df80fe82f0d8513a353728f01ffc075aa4178b67502f0abc48ac63382ca74a272339e80a22f6162e9977a1d7a8c4873bd09	t	1647694555000000
\.


--
-- Data for Name: wire_auditor_account_progress; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_auditor_account_progress (master_pub, account_name, last_wire_reserve_in_serial_id, last_wire_wire_out_serial_id, wire_in_off, wire_out_off) FROM stdin;
\.


--
-- Data for Name: wire_auditor_progress; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_auditor_progress (master_pub, last_timestamp, last_reserve_close_uuid) FROM stdin;
\.


--
-- Data for Name: wire_fee; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_fee (wire_fee_serial, wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	x-taler-bank	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x7855d90d7f297e273467620a4766b196428ea382dc748d26490a479015f80359ec7830ab208f921ce3ee431949584900bde921b63c5f015cf932f0af12eba50c
\.


--
-- Data for Name: wire_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_out_default (wireout_uuid, execution_date, wtid_raw, wire_target_h_payto, exchange_account_section, amount_val, amount_frac) FROM stdin;
\.


--
-- Data for Name: wire_targets_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_targets_default (wire_target_serial_id, wire_target_h_payto, payto_uri, kyc_ok, external_id) FROM stdin;
1	\\xbf5c4070abfc28fa3a801bb819401d8dc92ac20962b5a308ec9c6d07ee26a856	payto://x-taler-bank/localhost/testuser-ymqrsenl	f	\N
2	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	payto://x-taler-bank/localhost/43	f	\N
3	\\x1e35f1bb440d72b935d1d4b332438662dc524f0eba57c35deda08425a29051fe	payto://x-taler-bank/localhost/testuser-inu22dec	f	\N
\.


--
-- Data for Name: work_shards; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.work_shards (shard_serial_id, last_attempt, start_row, end_row, completed, job_name) FROM stdin;
1	1647694549000000	0	1024	f	wirewatch-exchange-account-1
\.


--
-- Name: aggregation_tracking_aggregation_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.aggregation_tracking_aggregation_serial_id_seq', 1, false);


--
-- Name: app_bankaccount_account_no_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.app_bankaccount_account_no_seq', 13, true);


--
-- Name: app_banktransaction_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.app_banktransaction_id_seq', 4, true);


--
-- Name: auditor_denom_sigs_auditor_denom_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auditor_denom_sigs_auditor_denom_serial_seq', 424, true);


--
-- Name: auditor_reserves_auditor_reserves_rowid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auditor_reserves_auditor_reserves_rowid_seq', 1, false);


--
-- Name: auditors_auditor_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auditors_auditor_uuid_seq', 1, true);


--
-- Name: auth_group_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auth_group_id_seq', 1, false);


--
-- Name: auth_group_permissions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auth_group_permissions_id_seq', 1, false);


--
-- Name: auth_permission_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auth_permission_id_seq', 32, true);


--
-- Name: auth_user_groups_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auth_user_groups_id_seq', 1, false);


--
-- Name: auth_user_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auth_user_id_seq', 13, true);


--
-- Name: auth_user_user_permissions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auth_user_user_permissions_id_seq', 1, false);


--
-- Name: cs_nonce_locks_cs_nonce_lock_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.cs_nonce_locks_cs_nonce_lock_serial_id_seq', 1, false);


--
-- Name: denomination_revocations_denom_revocations_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.denomination_revocations_denom_revocations_serial_id_seq', 1, false);


--
-- Name: denominations_denominations_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.denominations_denominations_serial_seq', 424, true);


--
-- Name: deposit_confirmations_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposit_confirmations_serial_id_seq', 3, true);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposits_deposit_serial_id_seq', 3, true);


--
-- Name: django_content_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.django_content_type_id_seq', 8, true);


--
-- Name: django_migrations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.django_migrations_id_seq', 16, true);


--
-- Name: exchange_sign_keys_esk_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.exchange_sign_keys_esk_serial_seq', 5, true);


--
-- Name: extension_details_extension_details_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.extension_details_extension_details_serial_id_seq', 1, false);


--
-- Name: extensions_extension_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.extensions_extension_id_seq', 1, false);


--
-- Name: global_fee_global_fee_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.global_fee_global_fee_serial_seq', 1, true);


--
-- Name: known_coins_known_coin_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.known_coins_known_coin_id_seq', 7, true);


--
-- Name: merchant_accounts_account_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_accounts_account_serial_seq', 1, true);


--
-- Name: merchant_deposits_deposit_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_deposits_deposit_serial_seq', 3, true);


--
-- Name: merchant_exchange_signing_keys_signkey_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_exchange_signing_keys_signkey_serial_seq', 5, true);


--
-- Name: merchant_exchange_wire_fees_wirefee_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_exchange_wire_fees_wirefee_serial_seq', 1, true);


--
-- Name: merchant_instances_merchant_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_instances_merchant_serial_seq', 1, true);


--
-- Name: merchant_inventory_product_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_inventory_product_serial_seq', 1, false);


--
-- Name: merchant_kyc_kyc_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_kyc_kyc_serial_id_seq', 1, true);


--
-- Name: merchant_orders_order_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_orders_order_serial_seq', 3, true);


--
-- Name: merchant_refunds_refund_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_refunds_refund_serial_seq', 1, true);


--
-- Name: merchant_tip_pickups_pickup_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_tip_pickups_pickup_serial_seq', 1, false);


--
-- Name: merchant_tip_reserves_reserve_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_tip_reserves_reserve_serial_seq', 1, false);


--
-- Name: merchant_tips_tip_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_tips_tip_serial_seq', 1, false);


--
-- Name: merchant_transfers_credit_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_transfers_credit_serial_seq', 1, false);


--
-- Name: prewire_prewire_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.prewire_prewire_uuid_seq', 1, false);


--
-- Name: recoup_recoup_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.recoup_recoup_uuid_seq', 1, false);


--
-- Name: recoup_refresh_recoup_refresh_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.recoup_refresh_recoup_refresh_uuid_seq', 1, false);


--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refresh_commitments_melt_serial_id_seq', 4, true);


--
-- Name: refresh_revealed_coins_rrc_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refresh_revealed_coins_rrc_serial_seq', 48, true);


--
-- Name: refresh_transfer_keys_rtc_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refresh_transfer_keys_rtc_serial_seq', 4, true);


--
-- Name: refunds_refund_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refunds_refund_serial_id_seq', 1, true);


--
-- Name: reserves_close_close_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_close_close_uuid_seq', 1, false);


--
-- Name: reserves_in_reserve_in_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_in_reserve_in_serial_id_seq', 2, true);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_out_reserve_out_serial_id_seq', 26, true);


--
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_reserve_uuid_seq', 2, true);


--
-- Name: revolving_work_shards_shard_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.revolving_work_shards_shard_serial_id_seq', 1, false);


--
-- Name: signkey_revocations_signkey_revocations_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.signkey_revocations_signkey_revocations_serial_id_seq', 1, false);


--
-- Name: wire_fee_wire_fee_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.wire_fee_wire_fee_serial_seq', 1, true);


--
-- Name: wire_out_wireout_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.wire_out_wireout_uuid_seq', 1, false);


--
-- Name: wire_targets_wire_target_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.wire_targets_wire_target_serial_id_seq', 5, true);


--
-- Name: work_shards_shard_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.work_shards_shard_serial_id_seq', 1, true);


--
-- Name: patches patches_pkey; Type: CONSTRAINT; Schema: _v; Owner: -
--

ALTER TABLE ONLY _v.patches
    ADD CONSTRAINT patches_pkey PRIMARY KEY (patch_name);


--
-- Name: aggregation_tracking_default aggregation_tracking_default_aggregation_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aggregation_tracking_default
    ADD CONSTRAINT aggregation_tracking_default_aggregation_serial_id_key UNIQUE (aggregation_serial_id);


--
-- Name: aggregation_tracking aggregation_tracking_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aggregation_tracking
    ADD CONSTRAINT aggregation_tracking_pkey PRIMARY KEY (deposit_serial_id);


--
-- Name: aggregation_tracking_default aggregation_tracking_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aggregation_tracking_default
    ADD CONSTRAINT aggregation_tracking_default_pkey PRIMARY KEY (deposit_serial_id);


--
-- Name: app_bankaccount app_bankaccount_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_bankaccount
    ADD CONSTRAINT app_bankaccount_pkey PRIMARY KEY (account_no);


--
-- Name: app_bankaccount app_bankaccount_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_bankaccount
    ADD CONSTRAINT app_bankaccount_user_id_key UNIQUE (user_id);


--
-- Name: app_banktransaction app_banktransaction_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_banktransaction
    ADD CONSTRAINT app_banktransaction_pkey PRIMARY KEY (id);


--
-- Name: app_banktransaction app_banktransaction_request_uid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_banktransaction
    ADD CONSTRAINT app_banktransaction_request_uid_key UNIQUE (request_uid);


--
-- Name: app_talerwithdrawoperation app_talerwithdrawoperation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_talerwithdrawoperation
    ADD CONSTRAINT app_talerwithdrawoperation_pkey PRIMARY KEY (withdraw_id);


--
-- Name: auditor_denom_sigs auditor_denom_sigs_auditor_denom_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_auditor_denom_serial_key UNIQUE (auditor_denom_serial);


--
-- Name: auditor_denom_sigs auditor_denom_sigs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_pkey PRIMARY KEY (denominations_serial, auditor_uuid);


--
-- Name: auditor_denomination_pending auditor_denomination_pending_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denomination_pending
    ADD CONSTRAINT auditor_denomination_pending_pkey PRIMARY KEY (denom_pub_hash);


--
-- Name: auditor_exchanges auditor_exchanges_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_exchanges
    ADD CONSTRAINT auditor_exchanges_pkey PRIMARY KEY (master_pub);


--
-- Name: auditor_historic_denomination_revenue auditor_historic_denomination_revenue_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_historic_denomination_revenue
    ADD CONSTRAINT auditor_historic_denomination_revenue_pkey PRIMARY KEY (denom_pub_hash);


--
-- Name: auditor_progress_aggregation auditor_progress_aggregation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_progress_aggregation
    ADD CONSTRAINT auditor_progress_aggregation_pkey PRIMARY KEY (master_pub);


--
-- Name: auditor_progress_coin auditor_progress_coin_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_progress_coin
    ADD CONSTRAINT auditor_progress_coin_pkey PRIMARY KEY (master_pub);


--
-- Name: auditor_progress_deposit_confirmation auditor_progress_deposit_confirmation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_progress_deposit_confirmation
    ADD CONSTRAINT auditor_progress_deposit_confirmation_pkey PRIMARY KEY (master_pub);


--
-- Name: auditor_progress_reserve auditor_progress_reserve_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_progress_reserve
    ADD CONSTRAINT auditor_progress_reserve_pkey PRIMARY KEY (master_pub);


--
-- Name: auditor_reserves auditor_reserves_auditor_reserves_rowid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_reserves
    ADD CONSTRAINT auditor_reserves_auditor_reserves_rowid_key UNIQUE (auditor_reserves_rowid);


--
-- Name: auditors auditors_auditor_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditors
    ADD CONSTRAINT auditors_auditor_uuid_key UNIQUE (auditor_uuid);


--
-- Name: auditors auditors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditors
    ADD CONSTRAINT auditors_pkey PRIMARY KEY (auditor_pub);


--
-- Name: auth_group auth_group_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_group
    ADD CONSTRAINT auth_group_name_key UNIQUE (name);


--
-- Name: auth_group_permissions auth_group_permissions_group_id_permission_id_0cd325b0_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_group_id_permission_id_0cd325b0_uniq UNIQUE (group_id, permission_id);


--
-- Name: auth_group_permissions auth_group_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_pkey PRIMARY KEY (id);


--
-- Name: auth_group auth_group_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_group
    ADD CONSTRAINT auth_group_pkey PRIMARY KEY (id);


--
-- Name: auth_permission auth_permission_content_type_id_codename_01ab375a_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_content_type_id_codename_01ab375a_uniq UNIQUE (content_type_id, codename);


--
-- Name: auth_permission auth_permission_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_pkey PRIMARY KEY (id);


--
-- Name: auth_user_groups auth_user_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_user_groups
    ADD CONSTRAINT auth_user_groups_pkey PRIMARY KEY (id);


--
-- Name: auth_user_groups auth_user_groups_user_id_group_id_94350c0c_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_user_groups
    ADD CONSTRAINT auth_user_groups_user_id_group_id_94350c0c_uniq UNIQUE (user_id, group_id);


--
-- Name: auth_user auth_user_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_user
    ADD CONSTRAINT auth_user_pkey PRIMARY KEY (id);


--
-- Name: auth_user_user_permissions auth_user_user_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permissions_pkey PRIMARY KEY (id);


--
-- Name: auth_user_user_permissions auth_user_user_permissions_user_id_permission_id_14a6b632_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permissions_user_id_permission_id_14a6b632_uniq UNIQUE (user_id, permission_id);


--
-- Name: auth_user auth_user_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_user
    ADD CONSTRAINT auth_user_username_key UNIQUE (username);


--
-- Name: cs_nonce_locks_default cs_nonce_locks_default_cs_nonce_lock_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cs_nonce_locks_default
    ADD CONSTRAINT cs_nonce_locks_default_cs_nonce_lock_serial_id_key UNIQUE (cs_nonce_lock_serial_id);


--
-- Name: cs_nonce_locks cs_nonce_locks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cs_nonce_locks
    ADD CONSTRAINT cs_nonce_locks_pkey PRIMARY KEY (nonce);


--
-- Name: cs_nonce_locks_default cs_nonce_locks_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cs_nonce_locks_default
    ADD CONSTRAINT cs_nonce_locks_default_pkey PRIMARY KEY (nonce);


--
-- Name: denomination_revocations denomination_revocations_denom_revocations_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denomination_revocations
    ADD CONSTRAINT denomination_revocations_denom_revocations_serial_id_key UNIQUE (denom_revocations_serial_id);


--
-- Name: denomination_revocations denomination_revocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denomination_revocations
    ADD CONSTRAINT denomination_revocations_pkey PRIMARY KEY (denominations_serial);


--
-- Name: denominations denominations_denominations_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denominations
    ADD CONSTRAINT denominations_denominations_serial_key UNIQUE (denominations_serial);


--
-- Name: denominations denominations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denominations
    ADD CONSTRAINT denominations_pkey PRIMARY KEY (denom_pub_hash);


--
-- Name: deposit_confirmations deposit_confirmations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_confirmations
    ADD CONSTRAINT deposit_confirmations_pkey PRIMARY KEY (h_contract_terms, h_wire, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig);


--
-- Name: deposit_confirmations deposit_confirmations_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_confirmations
    ADD CONSTRAINT deposit_confirmations_serial_id_key UNIQUE (serial_id);


--
-- Name: deposits_default deposits_default_deposit_serial_id_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits_default
    ADD CONSTRAINT deposits_default_deposit_serial_id_pkey PRIMARY KEY (deposit_serial_id);


--
-- Name: deposits deposits_shard_coin_pub_merchant_pub_h_contract_terms_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT deposits_shard_coin_pub_merchant_pub_h_contract_terms_key UNIQUE (shard, coin_pub, merchant_pub, h_contract_terms);


--
-- Name: deposits_default deposits_default_shard_coin_pub_merchant_pub_h_contract_ter_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits_default
    ADD CONSTRAINT deposits_default_shard_coin_pub_merchant_pub_h_contract_ter_key UNIQUE (shard, coin_pub, merchant_pub, h_contract_terms);


--
-- Name: django_content_type django_content_type_app_label_model_76bd3d3b_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.django_content_type
    ADD CONSTRAINT django_content_type_app_label_model_76bd3d3b_uniq UNIQUE (app_label, model);


--
-- Name: django_content_type django_content_type_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.django_content_type
    ADD CONSTRAINT django_content_type_pkey PRIMARY KEY (id);


--
-- Name: django_migrations django_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.django_migrations
    ADD CONSTRAINT django_migrations_pkey PRIMARY KEY (id);


--
-- Name: django_session django_session_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.django_session
    ADD CONSTRAINT django_session_pkey PRIMARY KEY (session_key);


--
-- Name: exchange_sign_keys exchange_sign_keys_esk_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exchange_sign_keys
    ADD CONSTRAINT exchange_sign_keys_esk_serial_key UNIQUE (esk_serial);


--
-- Name: exchange_sign_keys exchange_sign_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exchange_sign_keys
    ADD CONSTRAINT exchange_sign_keys_pkey PRIMARY KEY (exchange_pub);


--
-- Name: extension_details extension_details_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.extension_details
    ADD CONSTRAINT extension_details_pkey PRIMARY KEY (extension_details_serial_id);


--
-- Name: extensions extensions_extension_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.extensions
    ADD CONSTRAINT extensions_extension_id_key UNIQUE (extension_id);


--
-- Name: extensions extensions_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.extensions
    ADD CONSTRAINT extensions_name_key UNIQUE (name);


--
-- Name: global_fee global_fee_global_fee_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.global_fee
    ADD CONSTRAINT global_fee_global_fee_serial_key UNIQUE (global_fee_serial);


--
-- Name: global_fee global_fee_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.global_fee
    ADD CONSTRAINT global_fee_pkey PRIMARY KEY (start_date);


--
-- Name: known_coins known_coins_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.known_coins
    ADD CONSTRAINT known_coins_pkey PRIMARY KEY (coin_pub);


--
-- Name: known_coins_default known_coins_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.known_coins_default
    ADD CONSTRAINT known_coins_default_pkey PRIMARY KEY (coin_pub);


--
-- Name: known_coins_default known_coins_defaultk_nown_coin_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.known_coins_default
    ADD CONSTRAINT known_coins_defaultk_nown_coin_id_key UNIQUE (known_coin_id);


--
-- Name: merchant_accounts merchant_accounts_h_wire_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_accounts
    ADD CONSTRAINT merchant_accounts_h_wire_key UNIQUE (h_wire);


--
-- Name: merchant_accounts merchant_accounts_merchant_serial_payto_uri_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_accounts
    ADD CONSTRAINT merchant_accounts_merchant_serial_payto_uri_key UNIQUE (merchant_serial, payto_uri);


--
-- Name: merchant_accounts merchant_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_accounts
    ADD CONSTRAINT merchant_accounts_pkey PRIMARY KEY (account_serial);


--
-- Name: merchant_contract_terms merchant_contract_terms_merchant_serial_h_contract_terms_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_merchant_serial_h_contract_terms_key UNIQUE (merchant_serial, h_contract_terms);


--
-- Name: merchant_contract_terms merchant_contract_terms_merchant_serial_order_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_merchant_serial_order_id_key UNIQUE (merchant_serial, order_id);


--
-- Name: merchant_contract_terms merchant_contract_terms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_pkey PRIMARY KEY (order_serial);


--
-- Name: merchant_deposit_to_transfer merchant_deposit_to_transfer_deposit_serial_credit_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposit_to_transfer
    ADD CONSTRAINT merchant_deposit_to_transfer_deposit_serial_credit_serial_key UNIQUE (deposit_serial, credit_serial);


--
-- Name: merchant_deposits merchant_deposits_order_serial_coin_pub_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_order_serial_coin_pub_key UNIQUE (order_serial, coin_pub);


--
-- Name: merchant_deposits merchant_deposits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_pkey PRIMARY KEY (deposit_serial);


--
-- Name: merchant_exchange_signing_keys merchant_exchange_signing_key_exchange_pub_start_date_maste_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_exchange_signing_keys
    ADD CONSTRAINT merchant_exchange_signing_key_exchange_pub_start_date_maste_key UNIQUE (exchange_pub, start_date, master_pub);


--
-- Name: merchant_exchange_signing_keys merchant_exchange_signing_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_exchange_signing_keys
    ADD CONSTRAINT merchant_exchange_signing_keys_pkey PRIMARY KEY (signkey_serial);


--
-- Name: merchant_exchange_wire_fees merchant_exchange_wire_fees_master_pub_h_wire_method_start__key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_exchange_wire_fees
    ADD CONSTRAINT merchant_exchange_wire_fees_master_pub_h_wire_method_start__key UNIQUE (master_pub, h_wire_method, start_date);


--
-- Name: merchant_exchange_wire_fees merchant_exchange_wire_fees_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_exchange_wire_fees
    ADD CONSTRAINT merchant_exchange_wire_fees_pkey PRIMARY KEY (wirefee_serial);


--
-- Name: merchant_instances merchant_instances_merchant_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_instances
    ADD CONSTRAINT merchant_instances_merchant_id_key UNIQUE (merchant_id);


--
-- Name: merchant_instances merchant_instances_merchant_pub_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_instances
    ADD CONSTRAINT merchant_instances_merchant_pub_key UNIQUE (merchant_pub);


--
-- Name: merchant_instances merchant_instances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_instances
    ADD CONSTRAINT merchant_instances_pkey PRIMARY KEY (merchant_serial);


--
-- Name: merchant_inventory merchant_inventory_merchant_serial_product_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_inventory
    ADD CONSTRAINT merchant_inventory_merchant_serial_product_id_key UNIQUE (merchant_serial, product_id);


--
-- Name: merchant_inventory merchant_inventory_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_inventory
    ADD CONSTRAINT merchant_inventory_pkey PRIMARY KEY (product_serial);


--
-- Name: merchant_keys merchant_keys_merchant_priv_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_keys
    ADD CONSTRAINT merchant_keys_merchant_priv_key UNIQUE (merchant_priv);


--
-- Name: merchant_keys merchant_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_keys
    ADD CONSTRAINT merchant_keys_pkey PRIMARY KEY (merchant_serial);


--
-- Name: merchant_kyc merchant_kyc_kyc_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_kyc
    ADD CONSTRAINT merchant_kyc_kyc_serial_id_key UNIQUE (kyc_serial_id);


--
-- Name: merchant_kyc merchant_kyc_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_kyc
    ADD CONSTRAINT merchant_kyc_pkey PRIMARY KEY (account_serial, exchange_url);


--
-- Name: merchant_orders merchant_orders_merchant_serial_order_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_orders
    ADD CONSTRAINT merchant_orders_merchant_serial_order_id_key UNIQUE (merchant_serial, order_id);


--
-- Name: merchant_orders merchant_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_orders
    ADD CONSTRAINT merchant_orders_pkey PRIMARY KEY (order_serial);


--
-- Name: merchant_refund_proofs merchant_refund_proofs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refund_proofs
    ADD CONSTRAINT merchant_refund_proofs_pkey PRIMARY KEY (refund_serial);


--
-- Name: merchant_refunds merchant_refunds_order_serial_coin_pub_rtransaction_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refunds
    ADD CONSTRAINT merchant_refunds_order_serial_coin_pub_rtransaction_id_key UNIQUE (order_serial, coin_pub, rtransaction_id);


--
-- Name: merchant_refunds merchant_refunds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refunds
    ADD CONSTRAINT merchant_refunds_pkey PRIMARY KEY (refund_serial);


--
-- Name: merchant_tip_pickup_signatures merchant_tip_pickup_signatures_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickup_signatures
    ADD CONSTRAINT merchant_tip_pickup_signatures_pkey PRIMARY KEY (pickup_serial, coin_offset);


--
-- Name: merchant_tip_pickups merchant_tip_pickups_pickup_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_pickup_id_key UNIQUE (pickup_id);


--
-- Name: merchant_tip_pickups merchant_tip_pickups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_pkey PRIMARY KEY (pickup_serial);


--
-- Name: merchant_tip_reserve_keys merchant_tip_reserve_keys_reserve_priv_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserve_keys
    ADD CONSTRAINT merchant_tip_reserve_keys_reserve_priv_key UNIQUE (reserve_priv);


--
-- Name: merchant_tip_reserve_keys merchant_tip_reserve_keys_reserve_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserve_keys
    ADD CONSTRAINT merchant_tip_reserve_keys_reserve_serial_key UNIQUE (reserve_serial);


--
-- Name: merchant_tip_reserves merchant_tip_reserves_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserves
    ADD CONSTRAINT merchant_tip_reserves_pkey PRIMARY KEY (reserve_serial);


--
-- Name: merchant_tip_reserves merchant_tip_reserves_reserve_pub_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserves
    ADD CONSTRAINT merchant_tip_reserves_reserve_pub_key UNIQUE (reserve_pub);


--
-- Name: merchant_tips merchant_tips_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tips
    ADD CONSTRAINT merchant_tips_pkey PRIMARY KEY (tip_serial);


--
-- Name: merchant_tips merchant_tips_tip_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tips
    ADD CONSTRAINT merchant_tips_tip_id_key UNIQUE (tip_id);


--
-- Name: merchant_transfer_signatures merchant_transfer_signatures_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfer_signatures
    ADD CONSTRAINT merchant_transfer_signatures_pkey PRIMARY KEY (credit_serial);


--
-- Name: merchant_transfer_to_coin merchant_transfer_to_coin_deposit_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfer_to_coin
    ADD CONSTRAINT merchant_transfer_to_coin_deposit_serial_key UNIQUE (deposit_serial);


--
-- Name: merchant_transfers merchant_transfers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfers
    ADD CONSTRAINT merchant_transfers_pkey PRIMARY KEY (credit_serial);


--
-- Name: merchant_transfers merchant_transfers_wtid_exchange_url_account_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfers
    ADD CONSTRAINT merchant_transfers_wtid_exchange_url_account_serial_key UNIQUE (wtid, exchange_url, account_serial);


--
-- Name: prewire prewire_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prewire
    ADD CONSTRAINT prewire_pkey PRIMARY KEY (prewire_uuid);


--
-- Name: prewire_default prewire_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prewire_default
    ADD CONSTRAINT prewire_default_pkey PRIMARY KEY (prewire_uuid);


--
-- Name: recoup_default recoup_default_recoup_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup_default
    ADD CONSTRAINT recoup_default_recoup_uuid_key UNIQUE (recoup_uuid);


--
-- Name: recoup_refresh_default recoup_refresh_default_recoup_refresh_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup_refresh_default
    ADD CONSTRAINT recoup_refresh_default_recoup_refresh_uuid_key UNIQUE (recoup_refresh_uuid);


--
-- Name: refresh_commitments_default refresh_commitments_default_melt_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_commitments_default
    ADD CONSTRAINT refresh_commitments_default_melt_serial_id_key UNIQUE (melt_serial_id);


--
-- Name: refresh_commitments refresh_commitments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_commitments
    ADD CONSTRAINT refresh_commitments_pkey PRIMARY KEY (rc);


--
-- Name: refresh_commitments_default refresh_commitments_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_commitments_default
    ADD CONSTRAINT refresh_commitments_default_pkey PRIMARY KEY (rc);


--
-- Name: refresh_revealed_coins_default refresh_revealed_coins_default_coin_ev_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins_default
    ADD CONSTRAINT refresh_revealed_coins_default_coin_ev_key UNIQUE (coin_ev);


--
-- Name: refresh_revealed_coins_default refresh_revealed_coins_default_h_coin_ev_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins_default
    ADD CONSTRAINT refresh_revealed_coins_default_h_coin_ev_key UNIQUE (h_coin_ev);


--
-- Name: refresh_revealed_coins_default refresh_revealed_coins_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins_default
    ADD CONSTRAINT refresh_revealed_coins_default_pkey PRIMARY KEY (melt_serial_id, freshcoin_index);


--
-- Name: refresh_revealed_coins_default refresh_revealed_coins_default_rrc_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins_default
    ADD CONSTRAINT refresh_revealed_coins_default_rrc_serial_key UNIQUE (rrc_serial);


--
-- Name: refresh_transfer_keys refresh_transfer_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_transfer_keys
    ADD CONSTRAINT refresh_transfer_keys_pkey PRIMARY KEY (melt_serial_id);


--
-- Name: refresh_transfer_keys_default refresh_transfer_keys_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_transfer_keys_default
    ADD CONSTRAINT refresh_transfer_keys_default_pkey PRIMARY KEY (melt_serial_id);


--
-- Name: refresh_transfer_keys_default refresh_transfer_keys_default_rtc_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_transfer_keys_default
    ADD CONSTRAINT refresh_transfer_keys_default_rtc_serial_key UNIQUE (rtc_serial);


--
-- Name: refunds_default refunds_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds_default
    ADD CONSTRAINT refunds_default_pkey PRIMARY KEY (deposit_serial_id, rtransaction_id);


--
-- Name: refunds_default refunds_default_refund_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds_default
    ADD CONSTRAINT refunds_default_refund_serial_id_key UNIQUE (refund_serial_id);


--
-- Name: reserves_close_default reserves_close_default_close_uuid_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_close_default
    ADD CONSTRAINT reserves_close_default_close_uuid_pkey PRIMARY KEY (close_uuid);


--
-- Name: reserves reserves_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves
    ADD CONSTRAINT reserves_pkey PRIMARY KEY (reserve_pub);


--
-- Name: reserves_default reserves_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_default
    ADD CONSTRAINT reserves_default_pkey PRIMARY KEY (reserve_pub);


--
-- Name: reserves_in reserves_in_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_in
    ADD CONSTRAINT reserves_in_pkey PRIMARY KEY (reserve_pub);


--
-- Name: reserves_in_default reserves_in_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_in_default
    ADD CONSTRAINT reserves_in_default_pkey PRIMARY KEY (reserve_pub);


--
-- Name: reserves_in_default reserves_in_default_reserve_in_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_in_default
    ADD CONSTRAINT reserves_in_default_reserve_in_serial_id_key UNIQUE (reserve_in_serial_id);


--
-- Name: reserves_out reserves_out_h_blind_ev_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_out
    ADD CONSTRAINT reserves_out_h_blind_ev_key UNIQUE (h_blind_ev);


--
-- Name: reserves_out_default reserves_out_default_h_blind_ev_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_out_default
    ADD CONSTRAINT reserves_out_default_h_blind_ev_key UNIQUE (h_blind_ev);


--
-- Name: reserves_out_default reserves_out_default_reserve_out_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_out_default
    ADD CONSTRAINT reserves_out_default_reserve_out_serial_id_key UNIQUE (reserve_out_serial_id);


--
-- Name: revolving_work_shards revolving_work_shards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.revolving_work_shards
    ADD CONSTRAINT revolving_work_shards_pkey PRIMARY KEY (job_name, start_row);


--
-- Name: revolving_work_shards revolving_work_shards_shard_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.revolving_work_shards
    ADD CONSTRAINT revolving_work_shards_shard_serial_id_key UNIQUE (shard_serial_id);


--
-- Name: signkey_revocations signkey_revocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signkey_revocations
    ADD CONSTRAINT signkey_revocations_pkey PRIMARY KEY (esk_serial);


--
-- Name: signkey_revocations signkey_revocations_signkey_revocations_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signkey_revocations
    ADD CONSTRAINT signkey_revocations_signkey_revocations_serial_id_key UNIQUE (signkey_revocations_serial_id);


--
-- Name: wire_accounts wire_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_accounts
    ADD CONSTRAINT wire_accounts_pkey PRIMARY KEY (payto_uri);


--
-- Name: wire_auditor_account_progress wire_auditor_account_progress_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_auditor_account_progress
    ADD CONSTRAINT wire_auditor_account_progress_pkey PRIMARY KEY (master_pub, account_name);


--
-- Name: wire_auditor_progress wire_auditor_progress_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_auditor_progress
    ADD CONSTRAINT wire_auditor_progress_pkey PRIMARY KEY (master_pub);


--
-- Name: wire_fee wire_fee_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_fee
    ADD CONSTRAINT wire_fee_pkey PRIMARY KEY (wire_method, start_date);


--
-- Name: wire_fee wire_fee_wire_fee_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_fee
    ADD CONSTRAINT wire_fee_wire_fee_serial_key UNIQUE (wire_fee_serial);


--
-- Name: wire_out_default wire_out_default_wireout_uuid_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_out_default
    ADD CONSTRAINT wire_out_default_wireout_uuid_pkey PRIMARY KEY (wireout_uuid);


--
-- Name: wire_out wire_out_wtid_raw_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_out
    ADD CONSTRAINT wire_out_wtid_raw_key UNIQUE (wtid_raw);


--
-- Name: wire_out_default wire_out_default_wtid_raw_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_out_default
    ADD CONSTRAINT wire_out_default_wtid_raw_key UNIQUE (wtid_raw);


--
-- Name: wire_targets wire_targets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_targets
    ADD CONSTRAINT wire_targets_pkey PRIMARY KEY (wire_target_h_payto);


--
-- Name: wire_targets_default wire_targets_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_targets_default
    ADD CONSTRAINT wire_targets_default_pkey PRIMARY KEY (wire_target_h_payto);


--
-- Name: wire_targets_default wire_targets_default_wire_target_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_targets_default
    ADD CONSTRAINT wire_targets_default_wire_target_serial_id_key UNIQUE (wire_target_serial_id);


--
-- Name: work_shards work_shards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_shards
    ADD CONSTRAINT work_shards_pkey PRIMARY KEY (job_name, start_row);


--
-- Name: work_shards work_shards_shard_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_shards
    ADD CONSTRAINT work_shards_shard_serial_id_key UNIQUE (shard_serial_id);


--
-- Name: aggregation_tracking_by_aggregation_serial_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX aggregation_tracking_by_aggregation_serial_id_index ON ONLY public.aggregation_tracking USING btree (aggregation_serial_id);


--
-- Name: aggregation_tracking_by_wtid_raw_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX aggregation_tracking_by_wtid_raw_index ON ONLY public.aggregation_tracking USING btree (wtid_raw);


--
-- Name: INDEX aggregation_tracking_by_wtid_raw_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.aggregation_tracking_by_wtid_raw_index IS 'for lookup_transactions';


--
-- Name: aggregation_tracking_default_aggregation_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX aggregation_tracking_default_aggregation_serial_id_idx ON public.aggregation_tracking_default USING btree (aggregation_serial_id);


--
-- Name: aggregation_tracking_default_wtid_raw_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX aggregation_tracking_default_wtid_raw_idx ON public.aggregation_tracking_default USING btree (wtid_raw);


--
-- Name: app_banktransaction_credit_account_id_a8ba05ac; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX app_banktransaction_credit_account_id_a8ba05ac ON public.app_banktransaction USING btree (credit_account_id);


--
-- Name: app_banktransaction_date_f72bcad6; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX app_banktransaction_date_f72bcad6 ON public.app_banktransaction USING btree (date);


--
-- Name: app_banktransaction_debit_account_id_5b1f7528; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX app_banktransaction_debit_account_id_5b1f7528 ON public.app_banktransaction USING btree (debit_account_id);


--
-- Name: app_banktransaction_request_uid_b7d06af5_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX app_banktransaction_request_uid_b7d06af5_like ON public.app_banktransaction USING btree (request_uid varchar_pattern_ops);


--
-- Name: app_talerwithdrawoperation_selected_exchange_account__6c8b96cf; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX app_talerwithdrawoperation_selected_exchange_account__6c8b96cf ON public.app_talerwithdrawoperation USING btree (selected_exchange_account_id);


--
-- Name: app_talerwithdrawoperation_withdraw_account_id_992dc5b3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX app_talerwithdrawoperation_withdraw_account_id_992dc5b3 ON public.app_talerwithdrawoperation USING btree (withdraw_account_id);


--
-- Name: auditor_historic_reserve_summary_by_master_pub_start_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auditor_historic_reserve_summary_by_master_pub_start_date ON public.auditor_historic_reserve_summary USING btree (master_pub, start_date);


--
-- Name: auditor_reserves_by_reserve_pub; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auditor_reserves_by_reserve_pub ON public.auditor_reserves USING btree (reserve_pub);


--
-- Name: auth_group_name_a6ea08ec_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_group_name_a6ea08ec_like ON public.auth_group USING btree (name varchar_pattern_ops);


--
-- Name: auth_group_permissions_group_id_b120cbf9; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_group_permissions_group_id_b120cbf9 ON public.auth_group_permissions USING btree (group_id);


--
-- Name: auth_group_permissions_permission_id_84c5c92e; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_group_permissions_permission_id_84c5c92e ON public.auth_group_permissions USING btree (permission_id);


--
-- Name: auth_permission_content_type_id_2f476e4b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_permission_content_type_id_2f476e4b ON public.auth_permission USING btree (content_type_id);


--
-- Name: auth_user_groups_group_id_97559544; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_user_groups_group_id_97559544 ON public.auth_user_groups USING btree (group_id);


--
-- Name: auth_user_groups_user_id_6a12ed8b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_user_groups_user_id_6a12ed8b ON public.auth_user_groups USING btree (user_id);


--
-- Name: auth_user_user_permissions_permission_id_1fbb5f2c; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_user_user_permissions_permission_id_1fbb5f2c ON public.auth_user_user_permissions USING btree (permission_id);


--
-- Name: auth_user_user_permissions_user_id_a95ead1b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_user_user_permissions_user_id_a95ead1b ON public.auth_user_user_permissions USING btree (user_id);


--
-- Name: auth_user_username_6821ab7c_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_user_username_6821ab7c_like ON public.auth_user USING btree (username varchar_pattern_ops);


--
-- Name: denominations_by_expire_legal_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX denominations_by_expire_legal_index ON public.denominations USING btree (expire_legal);


--
-- Name: deposits_by_coin_main_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_by_coin_main_index ON ONLY public.deposits_by_coin USING btree (coin_pub);


--
-- Name: deposits_by_coin_default_coin_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_by_coin_default_coin_pub_idx ON public.deposits_by_coin_default USING btree (coin_pub);


--
-- Name: deposits_deposit_by_serial_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_deposit_by_serial_id_index ON ONLY public.deposits USING btree (shard, deposit_serial_id);


--
-- Name: deposits_default_shard_deposit_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_default_shard_deposit_serial_id_idx ON public.deposits_default USING btree (shard, deposit_serial_id);


--
-- Name: deposits_for_get_ready_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_for_get_ready_index ON ONLY public.deposits USING btree (shard, done, extension_blocked, tiny, wire_deadline);


--
-- Name: INDEX deposits_for_get_ready_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.deposits_for_get_ready_index IS 'for deposits_get_ready';


--
-- Name: deposits_default_shard_done_extension_blocked_tiny_wire_dea_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_default_shard_done_extension_blocked_tiny_wire_dea_idx ON public.deposits_default USING btree (shard, done, extension_blocked, tiny, wire_deadline);


--
-- Name: deposits_for_iterate_matching_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_for_iterate_matching_index ON ONLY public.deposits USING btree (shard, merchant_pub, wire_target_h_payto, done, extension_blocked, refund_deadline);


--
-- Name: INDEX deposits_for_iterate_matching_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.deposits_for_iterate_matching_index IS 'for deposits_iterate_matching';


--
-- Name: deposits_default_shard_merchant_pub_wire_target_h_payto_don_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_default_shard_merchant_pub_wire_target_h_payto_don_idx ON public.deposits_default USING btree (shard, merchant_pub, wire_target_h_payto, done, extension_blocked, refund_deadline);


--
-- Name: django_session_expire_date_a5c62663; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX django_session_expire_date_a5c62663 ON public.django_session USING btree (expire_date);


--
-- Name: django_session_session_key_c0390e0f_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX django_session_session_key_c0390e0f_like ON public.django_session USING btree (session_key varchar_pattern_ops);


--
-- Name: global_fee_by_end_date_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX global_fee_by_end_date_index ON public.global_fee USING btree (end_date);


--
-- Name: known_coins_by_known_coin_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX known_coins_by_known_coin_id_index ON ONLY public.known_coins USING btree (known_coin_id);


--
-- Name: known_coins_default_known_coin_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX known_coins_default_known_coin_id_idx ON public.known_coins_default USING btree (known_coin_id);


--
-- Name: merchant_contract_terms_by_expiration; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_contract_terms_by_expiration ON public.merchant_contract_terms USING btree (paid, pay_deadline);


--
-- Name: INDEX merchant_contract_terms_by_expiration; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.merchant_contract_terms_by_expiration IS 'for unlock_contracts';


--
-- Name: merchant_contract_terms_by_merchant_and_expiration; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_contract_terms_by_merchant_and_expiration ON public.merchant_contract_terms USING btree (merchant_serial, pay_deadline);


--
-- Name: INDEX merchant_contract_terms_by_merchant_and_expiration; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.merchant_contract_terms_by_merchant_and_expiration IS 'for delete_contract_terms';


--
-- Name: merchant_contract_terms_by_merchant_and_payment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_contract_terms_by_merchant_and_payment ON public.merchant_contract_terms USING btree (merchant_serial, paid);


--
-- Name: merchant_contract_terms_by_merchant_session_and_fulfillment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_contract_terms_by_merchant_session_and_fulfillment ON public.merchant_contract_terms USING btree (merchant_serial, fulfillment_url, session_id);


--
-- Name: merchant_inventory_locks_by_expiration; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_inventory_locks_by_expiration ON public.merchant_inventory_locks USING btree (expiration);


--
-- Name: merchant_inventory_locks_by_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_inventory_locks_by_uuid ON public.merchant_inventory_locks USING btree (lock_uuid);


--
-- Name: merchant_orders_by_creation_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_orders_by_creation_time ON public.merchant_orders USING btree (creation_time);


--
-- Name: merchant_orders_by_expiration; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_orders_by_expiration ON public.merchant_orders USING btree (pay_deadline);


--
-- Name: merchant_orders_locks_by_order_and_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_orders_locks_by_order_and_product ON public.merchant_order_locks USING btree (order_serial, product_serial);


--
-- Name: merchant_refunds_by_coin_and_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_refunds_by_coin_and_order ON public.merchant_refunds USING btree (coin_pub, order_serial);


--
-- Name: merchant_tip_reserves_by_exchange_balance; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_tip_reserves_by_exchange_balance ON public.merchant_tip_reserves USING btree (exchange_initial_balance_val, exchange_initial_balance_frac);


--
-- Name: merchant_tip_reserves_by_merchant_serial_and_creation_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_tip_reserves_by_merchant_serial_and_creation_time ON public.merchant_tip_reserves USING btree (merchant_serial, creation_time);


--
-- Name: merchant_tip_reserves_by_reserve_pub_and_merchant_serial; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_tip_reserves_by_reserve_pub_and_merchant_serial ON public.merchant_tip_reserves USING btree (reserve_pub, merchant_serial, creation_time);


--
-- Name: merchant_tips_by_pickup_and_expiration; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_tips_by_pickup_and_expiration ON public.merchant_tips USING btree (was_picked_up, expiration);


--
-- Name: merchant_transfers_by_credit; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_transfers_by_credit ON public.merchant_transfer_to_coin USING btree (credit_serial);


--
-- Name: prewire_by_failed_finished_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX prewire_by_failed_finished_index ON ONLY public.prewire USING btree (failed, finished);


--
-- Name: INDEX prewire_by_failed_finished_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.prewire_by_failed_finished_index IS 'for wire_prepare_data_get';


--
-- Name: prewire_by_finished_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX prewire_by_finished_index ON ONLY public.prewire USING btree (finished);


--
-- Name: INDEX prewire_by_finished_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.prewire_by_finished_index IS 'for gc_prewire';


--
-- Name: prewire_default_failed_finished_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX prewire_default_failed_finished_idx ON public.prewire_default USING btree (failed, finished);


--
-- Name: prewire_default_finished_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX prewire_default_finished_idx ON public.prewire_default USING btree (finished);


--
-- Name: recoup_by_coin_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_by_coin_pub_index ON ONLY public.recoup USING btree (coin_pub);


--
-- Name: recoup_by_recoup_uuid_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_by_recoup_uuid_index ON ONLY public.recoup USING btree (recoup_uuid);


--
-- Name: recoup_by_reserve_main_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_by_reserve_main_index ON ONLY public.recoup_by_reserve USING btree (reserve_out_serial_id);


--
-- Name: recoup_by_reserve_default_reserve_out_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_by_reserve_default_reserve_out_serial_id_idx ON public.recoup_by_reserve_default USING btree (reserve_out_serial_id);


--
-- Name: recoup_by_reserve_out_serial_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_by_reserve_out_serial_id_index ON ONLY public.recoup USING btree (reserve_out_serial_id);


--
-- Name: recoup_default_coin_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_default_coin_pub_idx ON public.recoup_default USING btree (coin_pub);


--
-- Name: recoup_default_recoup_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_default_recoup_uuid_idx ON public.recoup_default USING btree (recoup_uuid);


--
-- Name: recoup_default_reserve_out_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_default_reserve_out_serial_id_idx ON public.recoup_default USING btree (reserve_out_serial_id);


--
-- Name: recoup_refresh_by_coin_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_by_coin_pub_index ON ONLY public.recoup_refresh USING btree (coin_pub);


--
-- Name: recoup_refresh_by_recoup_refresh_uuid_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_by_recoup_refresh_uuid_index ON ONLY public.recoup_refresh USING btree (recoup_refresh_uuid);


--
-- Name: recoup_refresh_by_rrc_serial_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_by_rrc_serial_index ON ONLY public.recoup_refresh USING btree (rrc_serial);


--
-- Name: recoup_refresh_default_coin_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_default_coin_pub_idx ON public.recoup_refresh_default USING btree (coin_pub);


--
-- Name: recoup_refresh_default_recoup_refresh_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_default_recoup_refresh_uuid_idx ON public.recoup_refresh_default USING btree (recoup_refresh_uuid);


--
-- Name: recoup_refresh_default_rrc_serial_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_default_rrc_serial_idx ON public.recoup_refresh_default USING btree (rrc_serial);


--
-- Name: refresh_commitments_by_melt_serial_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_commitments_by_melt_serial_id_index ON ONLY public.refresh_commitments USING btree (melt_serial_id);


--
-- Name: refresh_commitments_by_old_coin_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_commitments_by_old_coin_pub_index ON ONLY public.refresh_commitments USING btree (old_coin_pub);


--
-- Name: refresh_commitments_default_melt_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_commitments_default_melt_serial_id_idx ON public.refresh_commitments_default USING btree (melt_serial_id);


--
-- Name: refresh_commitments_default_old_coin_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_commitments_default_old_coin_pub_idx ON public.refresh_commitments_default USING btree (old_coin_pub);


--
-- Name: refresh_revealed_coins_by_melt_serial_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_revealed_coins_by_melt_serial_id_index ON ONLY public.refresh_revealed_coins USING btree (melt_serial_id);


--
-- Name: refresh_revealed_coins_by_rrc_serial_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_revealed_coins_by_rrc_serial_index ON ONLY public.refresh_revealed_coins USING btree (rrc_serial);


--
-- Name: refresh_revealed_coins_default_melt_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_revealed_coins_default_melt_serial_id_idx ON public.refresh_revealed_coins_default USING btree (melt_serial_id);


--
-- Name: refresh_revealed_coins_default_rrc_serial_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_revealed_coins_default_rrc_serial_idx ON public.refresh_revealed_coins_default USING btree (rrc_serial);


--
-- Name: refresh_transfer_keys_by_rtc_serial_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_transfer_keys_by_rtc_serial_index ON ONLY public.refresh_transfer_keys USING btree (rtc_serial);


--
-- Name: refresh_transfer_keys_default_rtc_serial_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_transfer_keys_default_rtc_serial_idx ON public.refresh_transfer_keys_default USING btree (rtc_serial);


--
-- Name: refunds_by_deposit_serial_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refunds_by_deposit_serial_id_index ON ONLY public.refunds USING btree (shard, deposit_serial_id);


--
-- Name: refunds_by_refund_serial_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refunds_by_refund_serial_id_index ON ONLY public.refunds USING btree (refund_serial_id);


--
-- Name: refunds_default_refund_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refunds_default_refund_serial_id_idx ON public.refunds_default USING btree (refund_serial_id);


--
-- Name: refunds_default_shard_deposit_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refunds_default_shard_deposit_serial_id_idx ON public.refunds_default USING btree (shard, deposit_serial_id);


--
-- Name: reserves_by_expiration_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_by_expiration_index ON ONLY public.reserves USING btree (expiration_date, current_balance_val, current_balance_frac);


--
-- Name: INDEX reserves_by_expiration_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.reserves_by_expiration_index IS 'used in get_expired_reserves';


--
-- Name: reserves_by_gc_date_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_by_gc_date_index ON ONLY public.reserves USING btree (gc_date);


--
-- Name: INDEX reserves_by_gc_date_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.reserves_by_gc_date_index IS 'for reserve garbage collection';


--
-- Name: reserves_by_reserve_uuid_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_by_reserve_uuid_index ON ONLY public.reserves USING btree (reserve_uuid);


--
-- Name: reserves_close_by_close_uuid_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_close_by_close_uuid_index ON ONLY public.reserves_close USING btree (close_uuid);


--
-- Name: reserves_close_by_reserve_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_close_by_reserve_pub_index ON ONLY public.reserves_close USING btree (reserve_pub);


--
-- Name: reserves_close_default_close_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_close_default_close_uuid_idx ON public.reserves_close_default USING btree (close_uuid);


--
-- Name: reserves_close_default_reserve_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_close_default_reserve_pub_idx ON public.reserves_close_default USING btree (reserve_pub);


--
-- Name: reserves_default_expiration_date_current_balance_val_curren_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_default_expiration_date_current_balance_val_curren_idx ON public.reserves_default USING btree (expiration_date, current_balance_val, current_balance_frac);


--
-- Name: reserves_default_gc_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_default_gc_date_idx ON public.reserves_default USING btree (gc_date);


--
-- Name: reserves_default_reserve_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_default_reserve_uuid_idx ON public.reserves_default USING btree (reserve_uuid);


--
-- Name: reserves_in_by_exchange_account_reserve_in_serial_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_in_by_exchange_account_reserve_in_serial_id_index ON ONLY public.reserves_in USING btree (exchange_account_section, reserve_in_serial_id DESC);


--
-- Name: reserves_in_by_exchange_account_section_execution_date_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_in_by_exchange_account_section_execution_date_index ON ONLY public.reserves_in USING btree (exchange_account_section, execution_date);


--
-- Name: reserves_in_by_reserve_in_serial_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_in_by_reserve_in_serial_id_index ON ONLY public.reserves_in USING btree (reserve_in_serial_id);


--
-- Name: reserves_in_default_exchange_account_section_execution_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_in_default_exchange_account_section_execution_date_idx ON public.reserves_in_default USING btree (exchange_account_section, execution_date);


--
-- Name: reserves_in_default_exchange_account_section_reserve_in_ser_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_in_default_exchange_account_section_reserve_in_ser_idx ON public.reserves_in_default USING btree (exchange_account_section, reserve_in_serial_id DESC);


--
-- Name: reserves_in_default_reserve_in_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_in_default_reserve_in_serial_id_idx ON public.reserves_in_default USING btree (reserve_in_serial_id);


--
-- Name: reserves_out_by_reserve_main_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_out_by_reserve_main_index ON ONLY public.reserves_out_by_reserve USING btree (reserve_uuid);


--
-- Name: reserves_out_by_reserve_default_reserve_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_out_by_reserve_default_reserve_uuid_idx ON public.reserves_out_by_reserve_default USING btree (reserve_uuid);


--
-- Name: reserves_out_by_reserve_out_serial_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_out_by_reserve_out_serial_id_index ON ONLY public.reserves_out USING btree (reserve_out_serial_id);


--
-- Name: reserves_out_by_reserve_uuid_and_execution_date_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_out_by_reserve_uuid_and_execution_date_index ON ONLY public.reserves_out USING btree (reserve_uuid, execution_date);


--
-- Name: INDEX reserves_out_by_reserve_uuid_and_execution_date_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.reserves_out_by_reserve_uuid_and_execution_date_index IS 'for get_reserves_out and exchange_do_withdraw_limit_check';


--
-- Name: reserves_out_default_reserve_out_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_out_default_reserve_out_serial_id_idx ON public.reserves_out_default USING btree (reserve_out_serial_id);


--
-- Name: reserves_out_default_reserve_uuid_execution_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_out_default_reserve_uuid_execution_date_idx ON public.reserves_out_default USING btree (reserve_uuid, execution_date);


--
-- Name: revolving_work_shards_by_job_name_active_last_attempt_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX revolving_work_shards_by_job_name_active_last_attempt_index ON public.revolving_work_shards USING btree (job_name, active, last_attempt);


--
-- Name: wire_fee_by_end_date_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wire_fee_by_end_date_index ON public.wire_fee USING btree (end_date);


--
-- Name: wire_out_by_wire_target_h_payto_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wire_out_by_wire_target_h_payto_index ON ONLY public.wire_out USING btree (wire_target_h_payto);


--
-- Name: wire_out_by_wireout_uuid_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wire_out_by_wireout_uuid_index ON ONLY public.wire_out USING btree (wireout_uuid);


--
-- Name: wire_out_default_wire_target_h_payto_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wire_out_default_wire_target_h_payto_idx ON public.wire_out_default USING btree (wire_target_h_payto);


--
-- Name: wire_out_default_wireout_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wire_out_default_wireout_uuid_idx ON public.wire_out_default USING btree (wireout_uuid);


--
-- Name: wire_targets_serial_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wire_targets_serial_id_index ON ONLY public.wire_targets USING btree (wire_target_serial_id);


--
-- Name: wire_targets_default_wire_target_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wire_targets_default_wire_target_serial_id_idx ON public.wire_targets_default USING btree (wire_target_serial_id);


--
-- Name: work_shards_by_job_name_completed_last_attempt_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX work_shards_by_job_name_completed_last_attempt_index ON public.work_shards USING btree (job_name, completed, last_attempt);


--
-- Name: aggregation_tracking_default_aggregation_serial_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.aggregation_tracking_by_aggregation_serial_id_index ATTACH PARTITION public.aggregation_tracking_default_aggregation_serial_id_idx;


--
-- Name: aggregation_tracking_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.aggregation_tracking_pkey ATTACH PARTITION public.aggregation_tracking_default_pkey;


--
-- Name: aggregation_tracking_default_wtid_raw_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.aggregation_tracking_by_wtid_raw_index ATTACH PARTITION public.aggregation_tracking_default_wtid_raw_idx;


--
-- Name: cs_nonce_locks_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.cs_nonce_locks_pkey ATTACH PARTITION public.cs_nonce_locks_default_pkey;


--
-- Name: deposits_by_coin_default_coin_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.deposits_by_coin_main_index ATTACH PARTITION public.deposits_by_coin_default_coin_pub_idx;


--
-- Name: deposits_default_shard_coin_pub_merchant_pub_h_contract_ter_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.deposits_shard_coin_pub_merchant_pub_h_contract_terms_key ATTACH PARTITION public.deposits_default_shard_coin_pub_merchant_pub_h_contract_ter_key;


--
-- Name: deposits_default_shard_deposit_serial_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.deposits_deposit_by_serial_id_index ATTACH PARTITION public.deposits_default_shard_deposit_serial_id_idx;


--
-- Name: deposits_default_shard_done_extension_blocked_tiny_wire_dea_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.deposits_for_get_ready_index ATTACH PARTITION public.deposits_default_shard_done_extension_blocked_tiny_wire_dea_idx;


--
-- Name: deposits_default_shard_merchant_pub_wire_target_h_payto_don_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.deposits_for_iterate_matching_index ATTACH PARTITION public.deposits_default_shard_merchant_pub_wire_target_h_payto_don_idx;


--
-- Name: known_coins_default_known_coin_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.known_coins_by_known_coin_id_index ATTACH PARTITION public.known_coins_default_known_coin_id_idx;


--
-- Name: known_coins_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.known_coins_pkey ATTACH PARTITION public.known_coins_default_pkey;


--
-- Name: prewire_default_failed_finished_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.prewire_by_failed_finished_index ATTACH PARTITION public.prewire_default_failed_finished_idx;


--
-- Name: prewire_default_finished_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.prewire_by_finished_index ATTACH PARTITION public.prewire_default_finished_idx;


--
-- Name: prewire_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.prewire_pkey ATTACH PARTITION public.prewire_default_pkey;


--
-- Name: recoup_by_reserve_default_reserve_out_serial_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.recoup_by_reserve_main_index ATTACH PARTITION public.recoup_by_reserve_default_reserve_out_serial_id_idx;


--
-- Name: recoup_default_coin_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.recoup_by_coin_pub_index ATTACH PARTITION public.recoup_default_coin_pub_idx;


--
-- Name: recoup_default_recoup_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.recoup_by_recoup_uuid_index ATTACH PARTITION public.recoup_default_recoup_uuid_idx;


--
-- Name: recoup_default_reserve_out_serial_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.recoup_by_reserve_out_serial_id_index ATTACH PARTITION public.recoup_default_reserve_out_serial_id_idx;


--
-- Name: recoup_refresh_default_coin_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.recoup_refresh_by_coin_pub_index ATTACH PARTITION public.recoup_refresh_default_coin_pub_idx;


--
-- Name: recoup_refresh_default_recoup_refresh_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.recoup_refresh_by_recoup_refresh_uuid_index ATTACH PARTITION public.recoup_refresh_default_recoup_refresh_uuid_idx;


--
-- Name: recoup_refresh_default_rrc_serial_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.recoup_refresh_by_rrc_serial_index ATTACH PARTITION public.recoup_refresh_default_rrc_serial_idx;


--
-- Name: refresh_commitments_default_melt_serial_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.refresh_commitments_by_melt_serial_id_index ATTACH PARTITION public.refresh_commitments_default_melt_serial_id_idx;


--
-- Name: refresh_commitments_default_old_coin_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.refresh_commitments_by_old_coin_pub_index ATTACH PARTITION public.refresh_commitments_default_old_coin_pub_idx;


--
-- Name: refresh_commitments_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.refresh_commitments_pkey ATTACH PARTITION public.refresh_commitments_default_pkey;


--
-- Name: refresh_revealed_coins_default_melt_serial_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.refresh_revealed_coins_by_melt_serial_id_index ATTACH PARTITION public.refresh_revealed_coins_default_melt_serial_id_idx;


--
-- Name: refresh_revealed_coins_default_rrc_serial_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.refresh_revealed_coins_by_rrc_serial_index ATTACH PARTITION public.refresh_revealed_coins_default_rrc_serial_idx;


--
-- Name: refresh_transfer_keys_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.refresh_transfer_keys_pkey ATTACH PARTITION public.refresh_transfer_keys_default_pkey;


--
-- Name: refresh_transfer_keys_default_rtc_serial_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.refresh_transfer_keys_by_rtc_serial_index ATTACH PARTITION public.refresh_transfer_keys_default_rtc_serial_idx;


--
-- Name: refunds_default_refund_serial_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.refunds_by_refund_serial_id_index ATTACH PARTITION public.refunds_default_refund_serial_id_idx;


--
-- Name: refunds_default_shard_deposit_serial_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.refunds_by_deposit_serial_id_index ATTACH PARTITION public.refunds_default_shard_deposit_serial_id_idx;


--
-- Name: reserves_close_default_close_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_close_by_close_uuid_index ATTACH PARTITION public.reserves_close_default_close_uuid_idx;


--
-- Name: reserves_close_default_reserve_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_close_by_reserve_pub_index ATTACH PARTITION public.reserves_close_default_reserve_pub_idx;


--
-- Name: reserves_default_expiration_date_current_balance_val_curren_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_by_expiration_index ATTACH PARTITION public.reserves_default_expiration_date_current_balance_val_curren_idx;


--
-- Name: reserves_default_gc_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_by_gc_date_index ATTACH PARTITION public.reserves_default_gc_date_idx;


--
-- Name: reserves_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_pkey ATTACH PARTITION public.reserves_default_pkey;


--
-- Name: reserves_default_reserve_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_by_reserve_uuid_index ATTACH PARTITION public.reserves_default_reserve_uuid_idx;


--
-- Name: reserves_in_default_exchange_account_section_execution_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_in_by_exchange_account_section_execution_date_index ATTACH PARTITION public.reserves_in_default_exchange_account_section_execution_date_idx;


--
-- Name: reserves_in_default_exchange_account_section_reserve_in_ser_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_in_by_exchange_account_reserve_in_serial_id_index ATTACH PARTITION public.reserves_in_default_exchange_account_section_reserve_in_ser_idx;


--
-- Name: reserves_in_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_in_pkey ATTACH PARTITION public.reserves_in_default_pkey;


--
-- Name: reserves_in_default_reserve_in_serial_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_in_by_reserve_in_serial_id_index ATTACH PARTITION public.reserves_in_default_reserve_in_serial_id_idx;


--
-- Name: reserves_out_by_reserve_default_reserve_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_out_by_reserve_main_index ATTACH PARTITION public.reserves_out_by_reserve_default_reserve_uuid_idx;


--
-- Name: reserves_out_default_h_blind_ev_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_out_h_blind_ev_key ATTACH PARTITION public.reserves_out_default_h_blind_ev_key;


--
-- Name: reserves_out_default_reserve_out_serial_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_out_by_reserve_out_serial_id_index ATTACH PARTITION public.reserves_out_default_reserve_out_serial_id_idx;


--
-- Name: reserves_out_default_reserve_uuid_execution_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_out_by_reserve_uuid_and_execution_date_index ATTACH PARTITION public.reserves_out_default_reserve_uuid_execution_date_idx;


--
-- Name: wire_out_default_wire_target_h_payto_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wire_out_by_wire_target_h_payto_index ATTACH PARTITION public.wire_out_default_wire_target_h_payto_idx;


--
-- Name: wire_out_default_wireout_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wire_out_by_wireout_uuid_index ATTACH PARTITION public.wire_out_default_wireout_uuid_idx;


--
-- Name: wire_out_default_wtid_raw_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wire_out_wtid_raw_key ATTACH PARTITION public.wire_out_default_wtid_raw_key;


--
-- Name: wire_targets_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wire_targets_pkey ATTACH PARTITION public.wire_targets_default_pkey;


--
-- Name: wire_targets_default_wire_target_serial_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wire_targets_serial_id_index ATTACH PARTITION public.wire_targets_default_wire_target_serial_id_idx;


--
-- Name: deposits deposit_on_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER deposit_on_delete AFTER DELETE ON public.deposits FOR EACH ROW EXECUTE FUNCTION public.deposits_by_coin_delete_trigger();


--
-- Name: deposits deposits_on_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER deposits_on_insert AFTER INSERT ON public.deposits FOR EACH ROW EXECUTE FUNCTION public.deposits_by_coin_insert_trigger();


--
-- Name: recoup recoup_on_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER recoup_on_delete AFTER DELETE ON public.recoup FOR EACH ROW EXECUTE FUNCTION public.recoup_delete_trigger();


--
-- Name: recoup recoup_on_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER recoup_on_insert AFTER INSERT ON public.recoup FOR EACH ROW EXECUTE FUNCTION public.recoup_insert_trigger();


--
-- Name: reserves_out reserves_out_on_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER reserves_out_on_delete AFTER DELETE ON public.reserves_out FOR EACH ROW EXECUTE FUNCTION public.reserves_out_by_reserve_delete_trigger();


--
-- Name: reserves_out reserves_out_on_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER reserves_out_on_insert AFTER INSERT ON public.reserves_out FOR EACH ROW EXECUTE FUNCTION public.reserves_out_by_reserve_insert_trigger();


--
-- Name: app_bankaccount app_bankaccount_user_id_2722a34f_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_bankaccount
    ADD CONSTRAINT app_bankaccount_user_id_2722a34f_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: app_banktransaction app_banktransaction_credit_account_id_a8ba05ac_fk_app_banka; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_banktransaction
    ADD CONSTRAINT app_banktransaction_credit_account_id_a8ba05ac_fk_app_banka FOREIGN KEY (credit_account_id) REFERENCES public.app_bankaccount(account_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: app_banktransaction app_banktransaction_debit_account_id_5b1f7528_fk_app_banka; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_banktransaction
    ADD CONSTRAINT app_banktransaction_debit_account_id_5b1f7528_fk_app_banka FOREIGN KEY (debit_account_id) REFERENCES public.app_bankaccount(account_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: app_talerwithdrawoperation app_talerwithdrawope_selected_exchange_ac_6c8b96cf_fk_app_banka; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_talerwithdrawoperation
    ADD CONSTRAINT app_talerwithdrawope_selected_exchange_ac_6c8b96cf_fk_app_banka FOREIGN KEY (selected_exchange_account_id) REFERENCES public.app_bankaccount(account_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: app_talerwithdrawoperation app_talerwithdrawope_withdraw_account_id_992dc5b3_fk_app_banka; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_talerwithdrawoperation
    ADD CONSTRAINT app_talerwithdrawope_withdraw_account_id_992dc5b3_fk_app_banka FOREIGN KEY (withdraw_account_id) REFERENCES public.app_bankaccount(account_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auditor_denom_sigs auditor_denom_sigs_auditor_uuid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_auditor_uuid_fkey FOREIGN KEY (auditor_uuid) REFERENCES public.auditors(auditor_uuid) ON DELETE CASCADE;


--
-- Name: auditor_denom_sigs auditor_denom_sigs_denominations_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_denominations_serial_fkey FOREIGN KEY (denominations_serial) REFERENCES public.denominations(denominations_serial) ON DELETE CASCADE;


--
-- Name: auth_group_permissions auth_group_permissio_permission_id_84c5c92e_fk_auth_perm; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissio_permission_id_84c5c92e_fk_auth_perm FOREIGN KEY (permission_id) REFERENCES public.auth_permission(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_group_permissions auth_group_permissions_group_id_b120cbf9_fk_auth_group_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_group_id_b120cbf9_fk_auth_group_id FOREIGN KEY (group_id) REFERENCES public.auth_group(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_permission auth_permission_content_type_id_2f476e4b_fk_django_co; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_content_type_id_2f476e4b_fk_django_co FOREIGN KEY (content_type_id) REFERENCES public.django_content_type(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_groups auth_user_groups_group_id_97559544_fk_auth_group_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_user_groups
    ADD CONSTRAINT auth_user_groups_group_id_97559544_fk_auth_group_id FOREIGN KEY (group_id) REFERENCES public.auth_group(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_groups auth_user_groups_user_id_6a12ed8b_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_user_groups
    ADD CONSTRAINT auth_user_groups_user_id_6a12ed8b_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_user_permissions auth_user_user_permi_permission_id_1fbb5f2c_fk_auth_perm; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permi_permission_id_1fbb5f2c_fk_auth_perm FOREIGN KEY (permission_id) REFERENCES public.auth_permission(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_user_permissions auth_user_user_permissions_user_id_a95ead1b_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permissions_user_id_a95ead1b_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: denomination_revocations denomination_revocations_denominations_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denomination_revocations
    ADD CONSTRAINT denomination_revocations_denominations_serial_fkey FOREIGN KEY (denominations_serial) REFERENCES public.denominations(denominations_serial) ON DELETE CASCADE;


--
-- Name: deposits deposits_extension_details_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.deposits
    ADD CONSTRAINT deposits_extension_details_serial_id_fkey FOREIGN KEY (extension_details_serial_id) REFERENCES public.extension_details(extension_details_serial_id) ON DELETE CASCADE;


--
-- Name: known_coins known_coins_denominations_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.known_coins
    ADD CONSTRAINT known_coins_denominations_serial_fkey FOREIGN KEY (denominations_serial) REFERENCES public.denominations(denominations_serial) ON DELETE CASCADE;


--
-- Name: auditor_exchange_signkeys master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_exchange_signkeys
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_progress_reserve master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_progress_reserve
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_progress_aggregation master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_progress_aggregation
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_progress_deposit_confirmation master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_progress_deposit_confirmation
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_progress_coin master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_progress_coin
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: wire_auditor_account_progress master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_auditor_account_progress
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: wire_auditor_progress master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_auditor_progress
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_reserves master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_reserves
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_reserve_balance master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_reserve_balance
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_wire_fee_balance master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_wire_fee_balance
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_balance_summary master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_balance_summary
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_historic_denomination_revenue master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_historic_denomination_revenue
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_historic_reserve_summary master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_historic_reserve_summary
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: deposit_confirmations master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_confirmations
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_predicted_result master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_predicted_result
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: merchant_accounts merchant_accounts_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_accounts
    ADD CONSTRAINT merchant_accounts_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES public.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_contract_terms merchant_contract_terms_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES public.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposit_to_transfer merchant_deposit_to_transfer_credit_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposit_to_transfer
    ADD CONSTRAINT merchant_deposit_to_transfer_credit_serial_fkey FOREIGN KEY (credit_serial) REFERENCES public.merchant_transfers(credit_serial);


--
-- Name: merchant_deposit_to_transfer merchant_deposit_to_transfer_deposit_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposit_to_transfer
    ADD CONSTRAINT merchant_deposit_to_transfer_deposit_serial_fkey FOREIGN KEY (deposit_serial) REFERENCES public.merchant_deposits(deposit_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposit_to_transfer merchant_deposit_to_transfer_signkey_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposit_to_transfer
    ADD CONSTRAINT merchant_deposit_to_transfer_signkey_serial_fkey FOREIGN KEY (signkey_serial) REFERENCES public.merchant_exchange_signing_keys(signkey_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposits merchant_deposits_account_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_account_serial_fkey FOREIGN KEY (account_serial) REFERENCES public.merchant_accounts(account_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposits merchant_deposits_order_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_order_serial_fkey FOREIGN KEY (order_serial) REFERENCES public.merchant_contract_terms(order_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposits merchant_deposits_signkey_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_signkey_serial_fkey FOREIGN KEY (signkey_serial) REFERENCES public.merchant_exchange_signing_keys(signkey_serial) ON DELETE CASCADE;


--
-- Name: merchant_inventory_locks merchant_inventory_locks_product_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_inventory_locks
    ADD CONSTRAINT merchant_inventory_locks_product_serial_fkey FOREIGN KEY (product_serial) REFERENCES public.merchant_inventory(product_serial);


--
-- Name: merchant_inventory merchant_inventory_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_inventory
    ADD CONSTRAINT merchant_inventory_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES public.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_keys merchant_keys_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_keys
    ADD CONSTRAINT merchant_keys_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES public.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_kyc merchant_kyc_account_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_kyc
    ADD CONSTRAINT merchant_kyc_account_serial_fkey FOREIGN KEY (account_serial) REFERENCES public.merchant_accounts(account_serial) ON DELETE CASCADE;


--
-- Name: merchant_order_locks merchant_order_locks_order_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_order_locks
    ADD CONSTRAINT merchant_order_locks_order_serial_fkey FOREIGN KEY (order_serial) REFERENCES public.merchant_orders(order_serial) ON DELETE CASCADE;


--
-- Name: merchant_order_locks merchant_order_locks_product_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_order_locks
    ADD CONSTRAINT merchant_order_locks_product_serial_fkey FOREIGN KEY (product_serial) REFERENCES public.merchant_inventory(product_serial);


--
-- Name: merchant_orders merchant_orders_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_orders
    ADD CONSTRAINT merchant_orders_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES public.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_refund_proofs merchant_refund_proofs_refund_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refund_proofs
    ADD CONSTRAINT merchant_refund_proofs_refund_serial_fkey FOREIGN KEY (refund_serial) REFERENCES public.merchant_refunds(refund_serial) ON DELETE CASCADE;


--
-- Name: merchant_refund_proofs merchant_refund_proofs_signkey_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refund_proofs
    ADD CONSTRAINT merchant_refund_proofs_signkey_serial_fkey FOREIGN KEY (signkey_serial) REFERENCES public.merchant_exchange_signing_keys(signkey_serial) ON DELETE CASCADE;


--
-- Name: merchant_refunds merchant_refunds_order_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refunds
    ADD CONSTRAINT merchant_refunds_order_serial_fkey FOREIGN KEY (order_serial) REFERENCES public.merchant_contract_terms(order_serial) ON DELETE CASCADE;


--
-- Name: merchant_tip_pickup_signatures merchant_tip_pickup_signatures_pickup_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickup_signatures
    ADD CONSTRAINT merchant_tip_pickup_signatures_pickup_serial_fkey FOREIGN KEY (pickup_serial) REFERENCES public.merchant_tip_pickups(pickup_serial) ON DELETE CASCADE;


--
-- Name: merchant_tip_pickups merchant_tip_pickups_tip_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_tip_serial_fkey FOREIGN KEY (tip_serial) REFERENCES public.merchant_tips(tip_serial) ON DELETE CASCADE;


--
-- Name: merchant_tip_reserve_keys merchant_tip_reserve_keys_reserve_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserve_keys
    ADD CONSTRAINT merchant_tip_reserve_keys_reserve_serial_fkey FOREIGN KEY (reserve_serial) REFERENCES public.merchant_tip_reserves(reserve_serial) ON DELETE CASCADE;


--
-- Name: merchant_tip_reserves merchant_tip_reserves_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserves
    ADD CONSTRAINT merchant_tip_reserves_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES public.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_tips merchant_tips_reserve_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tips
    ADD CONSTRAINT merchant_tips_reserve_serial_fkey FOREIGN KEY (reserve_serial) REFERENCES public.merchant_tip_reserves(reserve_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfer_signatures merchant_transfer_signatures_credit_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfer_signatures
    ADD CONSTRAINT merchant_transfer_signatures_credit_serial_fkey FOREIGN KEY (credit_serial) REFERENCES public.merchant_transfers(credit_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfer_signatures merchant_transfer_signatures_signkey_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfer_signatures
    ADD CONSTRAINT merchant_transfer_signatures_signkey_serial_fkey FOREIGN KEY (signkey_serial) REFERENCES public.merchant_exchange_signing_keys(signkey_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfer_to_coin merchant_transfer_to_coin_credit_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfer_to_coin
    ADD CONSTRAINT merchant_transfer_to_coin_credit_serial_fkey FOREIGN KEY (credit_serial) REFERENCES public.merchant_transfers(credit_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfer_to_coin merchant_transfer_to_coin_deposit_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfer_to_coin
    ADD CONSTRAINT merchant_transfer_to_coin_deposit_serial_fkey FOREIGN KEY (deposit_serial) REFERENCES public.merchant_deposits(deposit_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfers merchant_transfers_account_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfers
    ADD CONSTRAINT merchant_transfers_account_serial_fkey FOREIGN KEY (account_serial) REFERENCES public.merchant_accounts(account_serial) ON DELETE CASCADE;


--
-- Name: refresh_commitments refresh_commitments_old_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.refresh_commitments
    ADD CONSTRAINT refresh_commitments_old_coin_pub_fkey FOREIGN KEY (old_coin_pub) REFERENCES public.known_coins(coin_pub) ON DELETE CASCADE;


--
-- Name: refresh_revealed_coins refresh_revealed_coins_denominations_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_denominations_serial_fkey FOREIGN KEY (denominations_serial) REFERENCES public.denominations(denominations_serial) ON DELETE CASCADE;


--
-- Name: reserves_close reserves_close_reserve_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.reserves_close
    ADD CONSTRAINT reserves_close_reserve_pub_fkey FOREIGN KEY (reserve_pub) REFERENCES public.reserves(reserve_pub) ON DELETE CASCADE;


--
-- Name: reserves_in reserves_in_reserve_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.reserves_in
    ADD CONSTRAINT reserves_in_reserve_pub_fkey FOREIGN KEY (reserve_pub) REFERENCES public.reserves(reserve_pub) ON DELETE CASCADE;


--
-- Name: reserves_out reserves_out_denominations_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.reserves_out
    ADD CONSTRAINT reserves_out_denominations_serial_fkey FOREIGN KEY (denominations_serial) REFERENCES public.denominations(denominations_serial);


--
-- Name: signkey_revocations signkey_revocations_esk_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signkey_revocations
    ADD CONSTRAINT signkey_revocations_esk_serial_fkey FOREIGN KEY (esk_serial) REFERENCES public.exchange_sign_keys(esk_serial) ON DELETE CASCADE;


--
-- Name: aggregation_tracking wire_out_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.aggregation_tracking
    ADD CONSTRAINT wire_out_ref FOREIGN KEY (wtid_raw) REFERENCES public.wire_out(wtid_raw) ON DELETE CASCADE DEFERRABLE;


--
-- PostgreSQL database dump complete
--

