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
-- Name: deposits_delete_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.deposits_delete_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  was_ready BOOLEAN;
DECLARE
  was_tready BOOLEAN; -- is ready, but may be tiny
BEGIN
  was_ready  = NOT (OLD.done OR OLD.tiny OR OLD.extension_blocked);
  was_tready = NOT (OLD.done OR OLD.extension_blocked);

  IF (was_ready)
  THEN
    DELETE FROM deposits_by_ready
     WHERE wire_deadline = OLD.wire_deadline
       AND shard = OLD.shard
       AND coin_pub = OLD.coin_pub
       AND deposit_serial_id = OLD.deposit_serial_id;
  END IF;
  IF (was_tready)
  THEN
    DELETE FROM deposits_for_matching
     WHERE refund_deadline = OLD.refund_deadline
       AND shard = OLD.shard
       AND coin_pub = OLD.coin_pub
       AND deposit_serial_id = OLD.deposit_serial_id;
  END IF;
  RETURN NEW;
END $$;


--
-- Name: FUNCTION deposits_delete_trigger(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.deposits_delete_trigger() IS 'Replicate deposit deletions into materialized indices.';


--
-- Name: deposits_insert_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.deposits_insert_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  is_ready BOOLEAN;
DECLARE
  is_tready BOOLEAN; -- is ready, but may be tiny
BEGIN
  is_ready  = NOT (NEW.done OR NEW.tiny OR NEW.extension_blocked);
  is_tready = NOT (NEW.done OR NEW.extension_blocked);

  IF (is_ready)
  THEN
    INSERT INTO deposits_by_ready
      (wire_deadline
      ,shard
      ,coin_pub
      ,deposit_serial_id)
    VALUES
      (NEW.wire_deadline
      ,NEW.shard
      ,NEW.coin_pub
      ,NEW.deposit_serial_id);
  END IF;
  IF (is_tready)
  THEN
    INSERT INTO deposits_for_matching
      (refund_deadline
      ,shard
      ,coin_pub
      ,deposit_serial_id)
    VALUES
      (NEW.refund_deadline
      ,NEW.shard
      ,NEW.coin_pub
      ,NEW.deposit_serial_id);
  END IF;
  RETURN NEW;
END $$;


--
-- Name: FUNCTION deposits_insert_trigger(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.deposits_insert_trigger() IS 'Replicate deposit inserts into materialized indices.';


--
-- Name: deposits_update_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.deposits_update_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  was_ready BOOLEAN;
DECLARE
  is_ready BOOLEAN;
DECLARE
  was_tready BOOLEAN; -- was ready, but may be tiny
DECLARE
  is_tready BOOLEAN; -- is ready, but may be tiny
BEGIN
  was_ready = NOT (OLD.done OR OLD.tiny OR OLD.extension_blocked);
  is_ready  = NOT (NEW.done OR NEW.tiny OR NEW.extension_blocked);
  was_tready = NOT (OLD.done OR OLD.extension_blocked);
  is_tready  = NOT (NEW.done OR NEW.extension_blocked);
  IF (was_ready AND NOT is_ready)
  THEN
    DELETE FROM deposits_by_ready
     WHERE wire_deadline = OLD.wire_deadline
       AND shard = OLD.shard
       AND coin_pub = OLD.coin_pub
       AND deposit_serial_id = OLD.deposit_serial_id;
  END IF;
  IF (was_tready AND NOT is_tready)
  THEN
    DELETE FROM deposits_for_matching
     WHERE refund_deadline = OLD.refund_deadline
       AND shard = OLD.shard
       AND coin_pub = OLD.coin_pub
       AND deposit_serial_id = OLD.deposit_serial_id;
  END IF;
  IF (is_ready AND NOT was_ready)
  THEN
    INSERT INTO deposits_by_ready
      (wire_deadline
      ,shard
      ,coin_pub
      ,deposit_serial_id)
    VALUES
      (NEW.wire_deadline
      ,NEW.shard
      ,NEW.coin_pub
      ,NEW.deposit_serial_id);
  END IF;
  IF (is_tready AND NOT was_tready)
  THEN
    INSERT INTO deposits_for_matching
      (refund_deadline
      ,shard
      ,coin_pub
      ,deposit_serial_id)
    VALUES
      (NEW.refund_deadline
      ,NEW.shard
      ,NEW.coin_pub
      ,NEW.deposit_serial_id);
  END IF;
  RETURN NEW;
END $$;


--
-- Name: FUNCTION deposits_update_trigger(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.deposits_update_trigger() IS 'Replicate deposits changes into materialized indices.';


--
-- Name: exchange_do_account_merge(bytea, bytea, bytea); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_account_merge(in_purse_pub bytea, in_reserve_pub bytea, in_reserve_sig bytea, OUT out_balance_ok boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- FIXME
END $$;


--
-- Name: exchange_do_close_request(bytea, bytea); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_close_request(in_reserve_pub bytea, in_reserve_sig bytea, OUT out_final_balance_val bigint, OUT out_final_balance_frac integer, OUT out_balance_ok boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- FIXME
END $$;


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
--         INSERT deposits (by coin_pub, shard), ON CONFLICT DO NOTHING;
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
-- Name: exchange_do_history_request(bytea, bytea, bigint, bigint, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_history_request(in_reserve_pub bytea, in_reserve_sig bytea, in_request_timestamp bigint, in_history_fee_val bigint, in_history_fee_frac integer, OUT out_balance_ok boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- FIXME
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
-- Name: exchange_do_purse_deposit(bytea, bigint, integer, bytea, bytea); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_purse_deposit(in_purse_pub bytea, in_amount_with_fee_val bigint, in_amount_with_fee_frac integer, in_coin_pub bytea, in_coin_sig bytea, OUT out_balance_ok boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- FIXME
END $$;


--
-- Name: exchange_do_purse_merge(bytea, bytea, bigint, character varying, bytea); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_purse_merge(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_partner_url character varying, in_reserve_pub bytea, OUT out_balance_ok boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- FIXME
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
-- Shards: SELECT deposits (coin_pub, shard, h_contract_terms, merchant_pub)
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
 WHERE coin_pub=in_coin_pub
  AND shard=in_deposit_shard
  AND merchant_pub=in_merchant_pub
  AND h_contract_terms=in_h_contract_terms;

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
-- Name: account_mergers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.account_mergers (
    account_merge_request_serial_id bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    reserve_sig bytea NOT NULL,
    purse_pub bytea NOT NULL,
    CONSTRAINT account_mergers_purse_pub_check CHECK ((length(purse_pub) = 32)),
    CONSTRAINT account_mergers_reserve_pub_check CHECK ((length(reserve_pub) = 32)),
    CONSTRAINT account_mergers_reserve_sig_check CHECK ((length(reserve_sig) = 64))
);


--
-- Name: TABLE account_mergers; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.account_mergers IS 'Merge requests where a purse- and account-owner requested merging the purse into the account';


--
-- Name: COLUMN account_mergers.reserve_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.account_mergers.reserve_pub IS 'public key of the target reserve';


--
-- Name: COLUMN account_mergers.reserve_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.account_mergers.reserve_sig IS 'signature by the reserve private key affirming the merge, of type TALER_SIGNATURE_WALLET_ACCOUNT_MERGE';


--
-- Name: COLUMN account_mergers.purse_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.account_mergers.purse_pub IS 'public key of the purse';


--
-- Name: account_mergers_account_merge_request_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.account_mergers_account_merge_request_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: account_mergers_account_merge_request_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.account_mergers_account_merge_request_serial_id_seq OWNED BY public.account_mergers.account_merge_request_serial_id;


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
-- Name: close_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.close_requests (
    reserve_pub bytea NOT NULL,
    close_timestamp bigint NOT NULL,
    reserve_sig bytea NOT NULL,
    close_val bigint NOT NULL,
    close_frac integer NOT NULL,
    CONSTRAINT close_requests_reserve_pub_check CHECK ((length(reserve_pub) = 32)),
    CONSTRAINT close_requests_reserve_sig_check CHECK ((length(reserve_sig) = 64))
);


--
-- Name: TABLE close_requests; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.close_requests IS 'Explicit requests by a reserve owner to close a reserve immediately';


--
-- Name: COLUMN close_requests.close_timestamp; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.close_requests.close_timestamp IS 'When the request was created by the client';


--
-- Name: COLUMN close_requests.reserve_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.close_requests.reserve_sig IS 'Signature affirming that the reserve is to be closed';


--
-- Name: COLUMN close_requests.close_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.close_requests.close_val IS 'Balance of the reserve at the time of closing, to be wired to the associated bank account (minus the closing fee)';


--
-- Name: contracts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contracts (
    contract_serial_id bigint NOT NULL,
    purse_pub bytea NOT NULL,
    pub_ckey bytea NOT NULL,
    e_contract bytea NOT NULL,
    purse_expiration bigint NOT NULL,
    CONSTRAINT contracts_pub_ckey_check CHECK ((length(pub_ckey) = 32)),
    CONSTRAINT contracts_purse_pub_check CHECK ((length(purse_pub) = 32))
);


--
-- Name: TABLE contracts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.contracts IS 'encrypted contracts associated with purses';


--
-- Name: COLUMN contracts.purse_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contracts.purse_pub IS 'public key of the purse that the contract is associated with';


--
-- Name: COLUMN contracts.pub_ckey; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contracts.pub_ckey IS 'Public ECDH key used to encrypt the contract, to be used with the purse private key for decryption';


--
-- Name: COLUMN contracts.e_contract; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contracts.e_contract IS 'AES-GCM encrypted contract terms (contains gzip compressed JSON after decryption)';


--
-- Name: contracts_contract_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.contracts_contract_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contracts_contract_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.contracts_contract_serial_id_seq OWNED BY public.contracts.contract_serial_id;


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
PARTITION BY HASH (coin_pub);


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
-- Name: deposits_by_ready; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposits_by_ready (
    wire_deadline bigint NOT NULL,
    shard bigint NOT NULL,
    coin_pub bytea NOT NULL,
    deposit_serial_id bigint,
    CONSTRAINT deposits_by_ready_coin_pub_check CHECK ((length(coin_pub) = 32))
)
PARTITION BY RANGE (wire_deadline);


--
-- Name: TABLE deposits_by_ready; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.deposits_by_ready IS 'Enables fast lookups for deposits_get_ready, auto-populated via TRIGGER below';


--
-- Name: deposits_by_ready_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposits_by_ready_default (
    wire_deadline bigint NOT NULL,
    shard bigint NOT NULL,
    coin_pub bytea NOT NULL,
    deposit_serial_id bigint,
    CONSTRAINT deposits_by_ready_coin_pub_check CHECK ((length(coin_pub) = 32))
);
ALTER TABLE ONLY public.deposits_by_ready ATTACH PARTITION public.deposits_by_ready_default DEFAULT;


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
-- Name: deposits_for_matching; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposits_for_matching (
    refund_deadline bigint NOT NULL,
    shard bigint NOT NULL,
    coin_pub bytea NOT NULL,
    deposit_serial_id bigint,
    CONSTRAINT deposits_for_matching_coin_pub_check CHECK ((length(coin_pub) = 32))
)
PARTITION BY RANGE (refund_deadline);


--
-- Name: TABLE deposits_for_matching; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.deposits_for_matching IS 'Enables fast lookups for deposits_iterate_matching, auto-populated via TRIGGER below';


--
-- Name: deposits_for_matching_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposits_for_matching_default (
    refund_deadline bigint NOT NULL,
    shard bigint NOT NULL,
    coin_pub bytea NOT NULL,
    deposit_serial_id bigint,
    CONSTRAINT deposits_for_matching_coin_pub_check CHECK ((length(coin_pub) = 32))
);
ALTER TABLE ONLY public.deposits_for_matching ATTACH PARTITION public.deposits_for_matching_default DEFAULT;


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
-- Name: history_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.history_requests (
    reserve_pub bytea NOT NULL,
    request_timestamp bigint NOT NULL,
    reserve_sig bytea NOT NULL,
    history_fee_val bigint NOT NULL,
    history_fee_frac integer NOT NULL,
    CONSTRAINT history_requests_reserve_pub_check CHECK ((length(reserve_pub) = 32)),
    CONSTRAINT history_requests_reserve_sig_check CHECK ((length(reserve_sig) = 64))
);


--
-- Name: TABLE history_requests; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.history_requests IS 'Paid history requests issued by a client against a reserve';


--
-- Name: COLUMN history_requests.request_timestamp; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.history_requests.request_timestamp IS 'When was the history request made';


--
-- Name: COLUMN history_requests.reserve_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.history_requests.reserve_sig IS 'Signature approving payment for the history request';


--
-- Name: COLUMN history_requests.history_fee_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.history_requests.history_fee_val IS 'History fee approved by the signature';


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
-- Name: partner_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.partner_accounts (
    payto_uri character varying NOT NULL,
    partner_serial_id bigint,
    partner_master_sig bytea,
    last_seen bigint NOT NULL,
    CONSTRAINT partner_accounts_partner_master_sig_check CHECK ((length(partner_master_sig) = 64))
);


--
-- Name: TABLE partner_accounts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.partner_accounts IS 'Table with bank accounts of the partner exchange. Entries never expire as we need to remember the signature for the auditor.';


--
-- Name: COLUMN partner_accounts.payto_uri; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.partner_accounts.payto_uri IS 'payto URI (RFC 8905) with the bank account of the partner exchange.';


--
-- Name: COLUMN partner_accounts.partner_master_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.partner_accounts.partner_master_sig IS 'Signature of purpose TALER_SIGNATURE_MASTER_WIRE_DETAILS by the partner master public key';


--
-- Name: COLUMN partner_accounts.last_seen; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.partner_accounts.last_seen IS 'Last time we saw this account as being active at the partner exchange. Used to select the most recent entry, and to detect when we should check again.';


--
-- Name: partners; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.partners (
    partner_serial_id bigint NOT NULL,
    partner_master_pub bytea NOT NULL,
    start_date bigint NOT NULL,
    end_date bigint NOT NULL,
    wad_frequency bigint NOT NULL,
    wad_fee_val bigint NOT NULL,
    wad_fee_frac integer NOT NULL,
    master_sig bytea NOT NULL,
    partner_base_url text NOT NULL,
    CONSTRAINT partners_master_sig_check CHECK ((length(master_sig) = 64)),
    CONSTRAINT partners_partner_master_pub_check CHECK ((length(partner_master_pub) = 32))
);


--
-- Name: TABLE partners; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.partners IS 'exchanges we do wad transfers to';


--
-- Name: COLUMN partners.partner_master_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.partners.partner_master_pub IS 'offline master public key of the partner';


--
-- Name: COLUMN partners.start_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.partners.start_date IS 'starting date of the partnership';


--
-- Name: COLUMN partners.end_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.partners.end_date IS 'end date of the partnership';


--
-- Name: COLUMN partners.wad_frequency; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.partners.wad_frequency IS 'how often do we promise to do wad transfers';


--
-- Name: COLUMN partners.wad_fee_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.partners.wad_fee_val IS 'how high is the fee for a wallet to be added to a wad to this partner';


--
-- Name: COLUMN partners.master_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.partners.master_sig IS 'signature of our master public key affirming the partnership, of purpose TALER_SIGNATURE_MASTER_PARTNER_DETAILS';


--
-- Name: COLUMN partners.partner_base_url; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.partners.partner_base_url IS 'base URL of the REST API for this partner';


--
-- Name: partners_partner_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.partners_partner_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: partners_partner_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.partners_partner_serial_id_seq OWNED BY public.partners.partner_serial_id;


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
-- Name: purse_deposits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purse_deposits (
    purse_deposit_serial_id bigint NOT NULL,
    partner_serial_id bigint,
    purse_pub bytea NOT NULL,
    coin_pub bytea NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    coin_sig bytea NOT NULL,
    CONSTRAINT purse_deposits_coin_sig_check CHECK ((length(coin_sig) = 64)),
    CONSTRAINT purse_deposits_purse_pub_check CHECK ((length(purse_pub) = 32))
);


--
-- Name: TABLE purse_deposits; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.purse_deposits IS 'Requests depositing coins into a purse';


--
-- Name: COLUMN purse_deposits.partner_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_deposits.partner_serial_id IS 'identifies the partner exchange, NULL in case the target purse lives at this exchange';


--
-- Name: COLUMN purse_deposits.purse_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_deposits.purse_pub IS 'Public key of the purse';


--
-- Name: COLUMN purse_deposits.coin_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_deposits.coin_pub IS 'Public key of the coin being deposited';


--
-- Name: COLUMN purse_deposits.amount_with_fee_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_deposits.amount_with_fee_val IS 'Total amount being deposited';


--
-- Name: COLUMN purse_deposits.coin_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_deposits.coin_sig IS 'Signature of the coin affirming the deposit into the purse, of type TALER_SIGNATURE_PURSE_DEPOSIT';


--
-- Name: purse_deposits_purse_deposit_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.purse_deposits_purse_deposit_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: purse_deposits_purse_deposit_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.purse_deposits_purse_deposit_serial_id_seq OWNED BY public.purse_deposits.purse_deposit_serial_id;


--
-- Name: purse_merges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purse_merges (
    purse_merge_request_serial_id bigint NOT NULL,
    partner_serial_id bigint,
    reserve_pub bytea NOT NULL,
    purse_pub bytea NOT NULL,
    merge_sig bytea NOT NULL,
    merge_timestamp bigint NOT NULL,
    CONSTRAINT purse_merges_merge_sig_check CHECK ((length(merge_sig) = 64)),
    CONSTRAINT purse_merges_purse_pub_check CHECK ((length(purse_pub) = 32)),
    CONSTRAINT purse_merges_reserve_pub_check CHECK ((length(reserve_pub) = 32))
);


--
-- Name: TABLE purse_merges; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.purse_merges IS 'Merge requests where a purse-owner requested merging the purse into the account';


--
-- Name: COLUMN purse_merges.partner_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_merges.partner_serial_id IS 'identifies the partner exchange, NULL in case the target reserve lives at this exchange';


--
-- Name: COLUMN purse_merges.reserve_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_merges.reserve_pub IS 'public key of the target reserve';


--
-- Name: COLUMN purse_merges.purse_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_merges.purse_pub IS 'public key of the purse';


--
-- Name: COLUMN purse_merges.merge_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_merges.merge_sig IS 'signature by the purse private key affirming the merge, of type TALER_SIGNATURE_WALLET_PURSE_MERGE';


--
-- Name: COLUMN purse_merges.merge_timestamp; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_merges.merge_timestamp IS 'when was the merge message signed';


--
-- Name: purse_merges_purse_merge_request_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.purse_merges_purse_merge_request_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: purse_merges_purse_merge_request_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.purse_merges_purse_merge_request_serial_id_seq OWNED BY public.purse_merges.purse_merge_request_serial_id;


--
-- Name: purse_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purse_requests (
    purse_deposit_serial_id bigint NOT NULL,
    purse_pub bytea NOT NULL,
    merge_pub bytea NOT NULL,
    purse_expiration bigint NOT NULL,
    h_contract_terms bytea NOT NULL,
    age_limit integer NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    balance_val bigint DEFAULT 0 NOT NULL,
    balance_frac integer DEFAULT 0 NOT NULL,
    purse_sig bytea NOT NULL,
    CONSTRAINT purse_requests_h_contract_terms_check CHECK ((length(h_contract_terms) = 64)),
    CONSTRAINT purse_requests_merge_pub_check CHECK ((length(merge_pub) = 32)),
    CONSTRAINT purse_requests_purse_pub_check CHECK ((length(purse_pub) = 32)),
    CONSTRAINT purse_requests_purse_sig_check CHECK ((length(purse_sig) = 64))
);


--
-- Name: TABLE purse_requests; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.purse_requests IS 'Requests establishing purses, associating them with a contract but without a target reserve';


--
-- Name: COLUMN purse_requests.purse_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.purse_pub IS 'Public key of the purse';


--
-- Name: COLUMN purse_requests.purse_expiration; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.purse_expiration IS 'When the purse is set to expire';


--
-- Name: COLUMN purse_requests.h_contract_terms; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.h_contract_terms IS 'Hash of the contract the parties are to agree to';


--
-- Name: COLUMN purse_requests.amount_with_fee_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.amount_with_fee_val IS 'Total amount expected to be in the purse';


--
-- Name: COLUMN purse_requests.balance_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.balance_val IS 'Total amount actually in the purse';


--
-- Name: COLUMN purse_requests.purse_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.purse_sig IS 'Signature of the purse affirming the purse parameters, of type TALER_SIGNATURE_PURSE_REQUEST';


--
-- Name: purse_requests_purse_deposit_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.purse_requests_purse_deposit_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: purse_requests_purse_deposit_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.purse_requests_purse_deposit_serial_id_seq OWNED BY public.purse_requests.purse_deposit_serial_id;


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
-- Name: wad_in_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wad_in_entries (
    wad_in_entry_serial_id bigint NOT NULL,
    wad_in_serial_id bigint,
    reserve_pub bytea NOT NULL,
    purse_pub bytea NOT NULL,
    h_contract bytea NOT NULL,
    purse_expiration bigint NOT NULL,
    merge_timestamp bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    wad_fee_val bigint NOT NULL,
    wad_fee_frac integer NOT NULL,
    deposit_fees_val bigint NOT NULL,
    deposit_fees_frac integer NOT NULL,
    reserve_sig bytea NOT NULL,
    purse_sig bytea NOT NULL,
    CONSTRAINT wad_in_entries_h_contract_check CHECK ((length(h_contract) = 64)),
    CONSTRAINT wad_in_entries_purse_pub_check CHECK ((length(purse_pub) = 32)),
    CONSTRAINT wad_in_entries_purse_sig_check CHECK ((length(purse_sig) = 64)),
    CONSTRAINT wad_in_entries_reserve_pub_check CHECK ((length(reserve_pub) = 32)),
    CONSTRAINT wad_in_entries_reserve_sig_check CHECK ((length(reserve_sig) = 64))
);


--
-- Name: TABLE wad_in_entries; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wad_in_entries IS 'list of purses aggregated in a wad according to the sending exchange';


--
-- Name: COLUMN wad_in_entries.wad_in_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_in_entries.wad_in_serial_id IS 'wad for which the given purse was included in the aggregation';


--
-- Name: COLUMN wad_in_entries.reserve_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_in_entries.reserve_pub IS 'target account of the purse (must be at the local exchange)';


--
-- Name: COLUMN wad_in_entries.purse_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_in_entries.purse_pub IS 'public key of the purse that was merged';


--
-- Name: COLUMN wad_in_entries.h_contract; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_in_entries.h_contract IS 'hash of the contract terms of the purse';


--
-- Name: COLUMN wad_in_entries.purse_expiration; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_in_entries.purse_expiration IS 'Time when the purse was set to expire';


--
-- Name: COLUMN wad_in_entries.merge_timestamp; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_in_entries.merge_timestamp IS 'Time when the merge was approved';


--
-- Name: COLUMN wad_in_entries.amount_with_fee_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_in_entries.amount_with_fee_val IS 'Total amount in the purse';


--
-- Name: COLUMN wad_in_entries.wad_fee_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_in_entries.wad_fee_val IS 'Total wad fees paid by the purse';


--
-- Name: COLUMN wad_in_entries.deposit_fees_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_in_entries.deposit_fees_val IS 'Total deposit fees paid when depositing coins into the purse';


--
-- Name: COLUMN wad_in_entries.reserve_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_in_entries.reserve_sig IS 'Signature by the receiving reserve, of purpose TALER_SIGNATURE_ACCOUNT_MERGE';


--
-- Name: COLUMN wad_in_entries.purse_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_in_entries.purse_sig IS 'Signature by the purse of purpose TALER_SIGNATURE_PURSE_MERGE';


--
-- Name: wad_in_entries_wad_in_entry_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.wad_in_entries_wad_in_entry_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: wad_in_entries_wad_in_entry_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.wad_in_entries_wad_in_entry_serial_id_seq OWNED BY public.wad_in_entries.wad_in_entry_serial_id;


--
-- Name: wad_out_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wad_out_entries (
    wad_out_entry_serial_id bigint NOT NULL,
    wad_out_serial_id bigint,
    reserve_pub bytea NOT NULL,
    purse_pub bytea NOT NULL,
    h_contract bytea NOT NULL,
    purse_expiration bigint NOT NULL,
    merge_timestamp bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    wad_fee_val bigint NOT NULL,
    wad_fee_frac integer NOT NULL,
    deposit_fees_val bigint NOT NULL,
    deposit_fees_frac integer NOT NULL,
    reserve_sig bytea NOT NULL,
    purse_sig bytea NOT NULL,
    CONSTRAINT wad_out_entries_h_contract_check CHECK ((length(h_contract) = 64)),
    CONSTRAINT wad_out_entries_purse_pub_check CHECK ((length(purse_pub) = 32)),
    CONSTRAINT wad_out_entries_purse_sig_check CHECK ((length(purse_sig) = 64)),
    CONSTRAINT wad_out_entries_reserve_pub_check CHECK ((length(reserve_pub) = 32)),
    CONSTRAINT wad_out_entries_reserve_sig_check CHECK ((length(reserve_sig) = 64))
);


--
-- Name: TABLE wad_out_entries; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wad_out_entries IS 'Purses combined into a wad';


--
-- Name: COLUMN wad_out_entries.wad_out_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_out_entries.wad_out_serial_id IS 'Wad the purse was part of';


--
-- Name: COLUMN wad_out_entries.reserve_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_out_entries.reserve_pub IS 'Target reserve for the purse';


--
-- Name: COLUMN wad_out_entries.purse_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_out_entries.purse_pub IS 'Public key of the purse';


--
-- Name: COLUMN wad_out_entries.h_contract; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_out_entries.h_contract IS 'Hash of the contract associated with the purse';


--
-- Name: COLUMN wad_out_entries.purse_expiration; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_out_entries.purse_expiration IS 'Time when the purse expires';


--
-- Name: COLUMN wad_out_entries.merge_timestamp; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_out_entries.merge_timestamp IS 'Time when the merge was approved';


--
-- Name: COLUMN wad_out_entries.amount_with_fee_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_out_entries.amount_with_fee_val IS 'Total amount in the purse';


--
-- Name: COLUMN wad_out_entries.wad_fee_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_out_entries.wad_fee_val IS 'Wat fee charged to the purse';


--
-- Name: COLUMN wad_out_entries.deposit_fees_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_out_entries.deposit_fees_val IS 'Total deposit fees charged to the purse';


--
-- Name: COLUMN wad_out_entries.reserve_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_out_entries.reserve_sig IS 'Signature by the receiving reserve, of purpose TALER_SIGNATURE_ACCOUNT_MERGE';


--
-- Name: COLUMN wad_out_entries.purse_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wad_out_entries.purse_sig IS 'Signature by the purse of purpose TALER_SIGNATURE_PURSE_MERGE';


--
-- Name: wad_out_entries_wad_out_entry_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.wad_out_entries_wad_out_entry_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: wad_out_entries_wad_out_entry_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.wad_out_entries_wad_out_entry_serial_id_seq OWNED BY public.wad_out_entries.wad_out_entry_serial_id;


--
-- Name: wads_in; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wads_in (
    wad_in_serial_id bigint NOT NULL,
    wad_id bytea NOT NULL,
    origin_exchange_url text NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    arrival_time bigint NOT NULL,
    CONSTRAINT wads_in_wad_id_check CHECK ((length(wad_id) = 24))
);


--
-- Name: TABLE wads_in; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wads_in IS 'Incoming exchange-to-exchange wad wire transfers';


--
-- Name: COLUMN wads_in.wad_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wads_in.wad_id IS 'Unique identifier of the wad, part of the wire transfer subject';


--
-- Name: COLUMN wads_in.origin_exchange_url; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wads_in.origin_exchange_url IS 'Base URL of the originating URL, also part of the wire transfer subject';


--
-- Name: COLUMN wads_in.amount_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wads_in.amount_val IS 'Actual amount that was received by our exchange';


--
-- Name: COLUMN wads_in.arrival_time; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wads_in.arrival_time IS 'Time when the wad was received';


--
-- Name: wads_in_wad_in_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.wads_in_wad_in_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: wads_in_wad_in_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.wads_in_wad_in_serial_id_seq OWNED BY public.wads_in.wad_in_serial_id;


--
-- Name: wads_out; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wads_out (
    wad_out_serial_id bigint NOT NULL,
    wad_id bytea NOT NULL,
    partner_serial_id bigint NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    execution_time bigint NOT NULL,
    CONSTRAINT wads_out_wad_id_check CHECK ((length(wad_id) = 24))
);


--
-- Name: TABLE wads_out; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wads_out IS 'Wire transfers made to another exchange to transfer purse funds';


--
-- Name: COLUMN wads_out.wad_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wads_out.wad_id IS 'Unique identifier of the wad, part of the wire transfer subject';


--
-- Name: COLUMN wads_out.partner_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wads_out.partner_serial_id IS 'target exchange of the wad';


--
-- Name: COLUMN wads_out.amount_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wads_out.amount_val IS 'Amount that was wired';


--
-- Name: COLUMN wads_out.execution_time; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wads_out.execution_time IS 'Time when the wire transfer was scheduled';


--
-- Name: wads_out_wad_out_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.wads_out_wad_out_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: wads_out_wad_out_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.wads_out_wad_out_serial_id_seq OWNED BY public.wads_out.wad_out_serial_id;


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
-- Name: account_mergers account_merge_request_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_mergers ALTER COLUMN account_merge_request_serial_id SET DEFAULT nextval('public.account_mergers_account_merge_request_serial_id_seq'::regclass);


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
-- Name: contracts contract_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts ALTER COLUMN contract_serial_id SET DEFAULT nextval('public.contracts_contract_serial_id_seq'::regclass);


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
-- Name: partners partner_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partners ALTER COLUMN partner_serial_id SET DEFAULT nextval('public.partners_partner_serial_id_seq'::regclass);


--
-- Name: purse_deposits purse_deposit_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_deposits ALTER COLUMN purse_deposit_serial_id SET DEFAULT nextval('public.purse_deposits_purse_deposit_serial_id_seq'::regclass);


--
-- Name: purse_merges purse_merge_request_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_merges ALTER COLUMN purse_merge_request_serial_id SET DEFAULT nextval('public.purse_merges_purse_merge_request_serial_id_seq'::regclass);


--
-- Name: purse_requests purse_deposit_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_requests ALTER COLUMN purse_deposit_serial_id SET DEFAULT nextval('public.purse_requests_purse_deposit_serial_id_seq'::regclass);


--
-- Name: wad_in_entries wad_in_entry_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wad_in_entries ALTER COLUMN wad_in_entry_serial_id SET DEFAULT nextval('public.wad_in_entries_wad_in_entry_serial_id_seq'::regclass);


--
-- Name: wad_out_entries wad_out_entry_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wad_out_entries ALTER COLUMN wad_out_entry_serial_id SET DEFAULT nextval('public.wad_out_entries_wad_out_entry_serial_id_seq'::regclass);


--
-- Name: wads_in wad_in_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wads_in ALTER COLUMN wad_in_serial_id SET DEFAULT nextval('public.wads_in_wad_in_serial_id_seq'::regclass);


--
-- Name: wads_out wad_out_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wads_out ALTER COLUMN wad_out_serial_id SET DEFAULT nextval('public.wads_out_wad_out_serial_id_seq'::regclass);


--
-- Data for Name: patches; Type: TABLE DATA; Schema: _v; Owner: -
--

COPY _v.patches (patch_name, applied_tsz, applied_by, requires, conflicts) FROM stdin;
exchange-0001	2022-03-25 13:47:41.62703+01	grothoff	{}	{}
merchant-0001	2022-03-25 13:47:43.441474+01	grothoff	{}	{}
auditor-0001	2022-03-25 13:47:44.224533+01	grothoff	{}	{}
\.


--
-- Data for Name: account_mergers; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.account_mergers (account_merge_request_serial_id, reserve_pub, reserve_sig, purse_pub) FROM stdin;
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
1	TESTKUDOS:100	Joining bonus	2022-03-25 13:47:56.066064+01	f	69ca533c-b14b-40a0-a655-e43e4dd8f9da	12	1
2	TESTKUDOS:10	F2QYDXJQZV8T7AW4EQ7CRJ9GJXSKKWV1FG358VH0X41CR8K5XFXG	2022-03-25 13:47:59.653125+01	f	3e18618c-35a6-4f89-a734-0c035c1eea82	2	12
3	TESTKUDOS:100	Joining bonus	2022-03-25 13:48:06.595289+01	f	7b3bc5df-d37d-4001-895c-9de5e38c8eeb	13	1
4	TESTKUDOS:18	21WFNMX43A6KHJJB9EJTGT3DAFGYB7J2BD9G8RXB4RXW2KZASF70	2022-03-25 13:48:07.189753+01	f	404c1a93-37a2-4506-b1ce-b83d340ece09	2	13
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
a1dd50b5-979d-4d53-a353-096bb0b2eec6	TESTKUDOS:10	t	t	f	F2QYDXJQZV8T7AW4EQ7CRJ9GJXSKKWV1FG358VH0X41CR8K5XFXG	2	12
24d09480-30e4-4e4f-a56c-6a8f98fe9495	TESTKUDOS:18	t	t	f	21WFNMX43A6KHJJB9EJTGT3DAFGYB7J2BD9G8RXB4RXW2KZASF70	2	13
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
1	1	4	\\x578726c78d41fa9cffc87b9cdf76cd1a7c0b8ed217625676cf877160910c996d4bc528087d4be9541391aa4b38dc11bbe0c958896da42270d7f5b9c3d1b0a207
2	1	123	\\x1b90a6f7d4859ed3f3e598a4d95db32ddd69337708f5716afa001bf36df8edc07d8eb8b6ab3376619322c4ac8b609b2359bb6f2db329158e709ca2f5f223980f
3	1	5	\\x637be58a7b6f7f828a546666190dcac76e576cf4cd02542246a23ee4cc288820a2dab9de11deef4a15f9eded2a1e8401a38de96df8b346c6f8a28465af991b04
4	1	190	\\x2b15595e67a07154c5ddf7ef6335b3a4530e78951e2a694f88d6eaf3abd36f61c1f94f7a67000ac3560d8a9a33102b789a8bc018020cb3ea54a58a66a8d1f90c
5	1	127	\\x614d926cc3e2a6c00505f3476c60a5d091729ee4fe0b32d0d24e590cf8608767a9336b6ab86c110a0674176e1a1c1760a15c0012b40667f38a14c4f2321c8b04
6	1	424	\\x10ac5896256d573a03d463f73e97a8a63db36603da2528cd61261aae7d9ac14936cc8825b4ccfa1ceda8f03f145798397cd99b7c8ca53fb7c0bd41d9c2f18408
7	1	298	\\x8799abe56ceca320ec303837a9f1e1997ac7ec7af9c4256211e7fe2d6e3a8ee02ced50aacdc3cf3d7cbc895ee13d77c1c795c90086fdd8f3296067b8e2c92306
8	1	334	\\x9267a4a5e01abd92f5cdaf9b559a7dada7c2c3683db0d9493d2deb28e1c0143e0047a10ca83f1fb27c21f35be8f6b36ac4ba4e1d44ca34afe10992b95238c80a
9	1	198	\\x4ae1912c5637351e1df75651a8db5bcd8dc1438616acc57422fc95d1f16e03defeba8259b2f430f671de3091f92aecf294bd285992112fc23e868d0f9a10bd02
10	1	274	\\x7a8a3887a0140740d5874b1ed7d302153769bef2e30c51c5b4bfc588d04cd7c52e5d91d54a8f94d75bea2842f8e9c44d29c8ef31f296641f826b5e656e278106
11	1	370	\\xb32ebce4e6077800b4cfa10e3bf22bcb30cc56cd108ad33a3a214587880c6cee179af94a02885434b1ccd6297fd9c59b811d2cd9e519395e03eb84e884439206
12	1	214	\\x752ffe09eef6b375c7ed40125273e52ea4b61aba20a70753ccf665c141e495a514407b4a2483d1a7d7bf54d1755657b1634abb1bf071c4b0358e3b451d405d08
13	1	248	\\x514e6d4e102feaab165211e8ba3e1e02b581591f2234925c3485918de0de8b83cbc4df8d5cbcac5d2b469bb01c5bc9debb2b33b7ac3690f96c2a716157c01107
14	1	220	\\xb59c6a98b17042c46d99da23ac65c1f6e0160e6eedabab9b1b7b2bf7f438c5db854cbe9650c3eee47691a68ed62e4db7628c1c0cbef8dc991c9eb54a0b743d0f
15	1	25	\\x202e6a58b3a3ffd3d7d98ec27e9a57f0b381b5f494c089455d38eb09715dcf04576c1e4fbe7f7b2dee9df1d9ec085c0cac389fc2666d161533d5ce00830db706
16	1	399	\\x38662d4fc12e65c3c45e44029e7e8665d019c0e7dff01f2617f6c7b03e709be8f624e2cdc739f09edc485c72fa3cc91fe36b7264378716ec9926b8b8fa626505
17	1	287	\\xab15a351b54d03de4daa9c9326318398d5ac71cac570e964a4cea6ed857b2fc8a7e1f9acf02809e176ba2a1690b44ce1ab07ad67f98a14dc85f7232e23616f0c
18	1	392	\\xcdd786abb4b8720f060fdb6445f466880a36d74f00afaa358e1bd1d0c0cecc8a8f734cf8f1ef65e130da539885e4e3660ac3c44f804bc889e0ab55f3e46fdb0e
19	1	113	\\x80f8f801ce3b08e98a0df6b70d45b699de94bf4857b5834f3add07b2de217ed7ec716a982229cd4084d1cd6a30b050956d8cc89e657f48421c18a7bf8c32ab00
20	1	272	\\xe911caf8234bb56237381f07e95b4bc3edbfed625163abe7355dac0c11e28774295f7448cc743e0da34c281879d5897b5c8e133ac3b57fd9c0a1a281aac72e03
21	1	301	\\xd33e8eab64f73d44188737696235b1ada9a8235e341d2da3e6e343610dbe9454c611b3702b565450238ccab8f97e74fb802850e947e1c22c73c0917da9518602
22	1	360	\\x68cce5551aad27a5ffa57347c9b45f5be7516110acc9a2b980fb4467568ef3a03467435ed0befa1979be56e3f71c3ed4ceeeee75f22b7a1d77527c62a105800f
23	1	309	\\x198c70ba2a6044d803b85560cce63b2863c228321b6cdda7b83f5c903276dca657bd73919d45ff6e80bd55c4e5e0ea6cf93479a08c9ab8bc4b09e2a20ed08205
24	1	215	\\x9807fe2e89365a78c5cadc711f5e8776e975f81e7c45b3fba27a5d7ed5b7cab54ec6b98c258fad67b30d21128d56c5a86874c1d9d7be755be0e9b130d941e103
25	1	194	\\xc7cdbfb23ae819cfd373e63f9fdea376a9c8edf25ee94b28c3ba7aa15d04fa95dc01aea57d333eaaea643d5077a335509c6fdc3e76960a0790cfb9965daaf70d
26	1	254	\\x3c0f26be033b50d889f745bb274e090702787e8b6aeac1ff33fd13877e872762f578cdb9ac6c93546d9a54bba862d5ef0e06c0084ad63f80dd708a44a9cd0a0d
27	1	338	\\x67b3800dda70e34fab7df79bcac6e24942675d7d8c4404289d17e104f81a92552c3c35993cd6e30d06bdd31a3e0f84b6f49eb30339046914f6674ee56b0acd03
28	1	273	\\x86e19496bfb21a057a964bdf123b03c765fc190a63bc7a84b4352417bb22f3c3aa37ebfbe3e2c0205d06e0d02236ff4a75d458221694f9b86ec00b6e9d4a0f0f
29	1	106	\\xf2800dcf37547b9cb04c5d70022c52c8f4a0061f98e57d9c671dbb2a026a15cae9f9962855993cc9750b08eff9e8eded6eea60081da39290c2858109d28b0e04
30	1	319	\\xd9b86d1710a0e42dc4ecd2f7f998f73d8ac6e0038b837484fc4cc5ccd2f85eacc60d7d457e878ef2a04780a2ff556783c96d1e7bdca2018f0b3a2bbbb6b51406
31	1	414	\\x1b0bd72ffa66acf8f2ce5493ffc5f667984a34ee07d9014b4a923e66e6815a65d5dfe0a4d1885cbb96a9f6891fee2467cd9ea024c3aaf74770b108561695c70c
32	1	212	\\x784fa24b625356afac23bffc3207b8a048c626bbdfd4207553bea57683b49c3b4612f28e3fd0c9d9ca3f3d7d9fc005bfd953d2cbdc77b1ce5d1725899fe0010d
33	1	288	\\xdb8c923da115cae1d01826546dbbaaa02415cd37e011e5358951a0c1fc6c14171cb6a7b8491eb7ebd6db53ee21e2eb66edd6c31957f0256a4e269646a277970e
34	1	372	\\xc7015d5dae728b8ac9ee61b3bd7080a7fecda5eff8bf949fb7ad410bac66f2539b531bd595a339b0dc1f2f19e64fdc9272952d1b4393015fca0dc7ae7411a90b
35	1	9	\\x95e6c75927fb1569cd75864154ace38842793a838cec4aca7d77015994ee3ba2b95358a3d20624f5ae9c016547feed32aca95a053262240e8ca735af3e9f080c
36	1	107	\\x36d846d3833d0224a8eac77e8cf6c0805a5c8bfb8b6454aa509e2bcfe5dea692b0acca1dcfc47d77a0fd07aab9bacc9314df7df92433675029a6de4eb0fcdb07
37	1	224	\\xa9fd8fd6d1f40c027c85409182e02d481f37bf13737ba2960a8c9952fcd726fba094193fc238ac9e6e2df7759c115a11f6fd5218d3018cb4030e10ef76b6610d
38	1	285	\\x8ee047ded6efa784d818642226d84abb7bb4a901846ce0c60b554011285fbe07cf732133becb4056334ca447363a77f8559ef8cd5cd6ac861b8bccd6bdf17a0e
39	1	362	\\xdb08be4c81270a211cca720001524abad51a5a67d9d44109fc9a2b4678a6a2726bbeb6e7c39b94e890a0ed29b10302bb0e0b67c6fbae5ae89d4116eec996df03
40	1	77	\\x33784bbd9e16b3403d85f525652a17c9711d4a98207aeb9b2fb3e491ccab4a6a7761f179066ba99e8598b8ea9a72d38249ee7f1fc1b861791dbad050c7120d06
41	1	266	\\xa1f7f06433cc571867922996adba92c9e4f0abacb127956f165e642c77e52938a2d646430c8b3ae4a1ed46f077dee76eb28ded69055d377c002d9b80782a1006
42	1	29	\\x67e315a9225c1c3fe1cad59ab874d10d3fb83ff407ce5a721e467fed31d83cdd9a73a912d571573d76c82324ff4e07ca3c2c3d72362c84b9562515c85cce0b07
43	1	348	\\x277f19b150c65630db9c0d762d1fd30762864a0d68055f291d70832f422a5cd92aa1efe3ce1912a7f0055e285d0a78a4492df95c3ac35a89bef60329a5ba980b
44	1	67	\\xf78915cb64218368a4477cc9079a27a4bcb4d75e75f9041d190194b5553d3b7ce211ab64f8cf3a2fede6b242e5c31089847408a7ba6afe7c77fcbb2a97596d00
45	1	65	\\xd0b3fa1a59f5981bc4f0b345fe3ff6bce9ab4b0d695563b3713c31c63196eb10c79031371378a75c5bcb977bb5c635ef1d25c576bcd3b64d143769f7344d2b0c
46	1	350	\\x6f10123d8ffb629a8895c4a2fcd2c5994cad1c5db8f3b55dff719eebc4a5ab5c1aa7103382a9e86e1ced584382b62ca21ffba8f5bc9a4c2f6525a50043f73f00
47	1	249	\\xe4f3ddeafef523e2bd6cb07714eda0e8fa1d9f41d623475c3f43ab273f9b6c629bed10b92252170565f40523690f2fe769e6623aa19722b0ecc57fbdcef8b503
48	1	405	\\xf17344c1a53e891fed94e9e3f84a4e65671588821283dee8efb5b4a2cb0d562d0b3c6132984cac4f3f220ee4f4586dd3264e93bcc54e22b0212858fb4274d507
49	1	331	\\x9d60c2659226efbf9d5441165d7d53d1e710e186906cfa1de504724b2b0b35abaec9c5512c37e705dbf24c700777b0cb63274e829429122ea78f00c8906b8204
50	1	416	\\xec203398793464b45462cd96156512cd21a3661e493bac7ca9dee0bbbc97a30c3dd9cff08e48aa9dba46b10f57667a6a1212a0fa57f4ecbc6778042030d19009
51	1	140	\\x8ee56d9f8a3fe98e5013ccc5d05e4b9bfb8a70ee638c325de4cfbe60facafa3b04ea9af42837965ea7d43170a5ec2635fce2c7c20e978c098587e9774839d208
52	1	208	\\x360cfb1e66ac2219a9a3e7381211eb679e38e40dd395d5c3faba6ea8745b77efc6b28b23c4c791842008a67075dbf1d67575eab09804298b82e090da95323407
53	1	128	\\x85fe7c00bf05966991d9c9430caf75ec9bc022f6962924c803bd192f3243e392128b5230dcac19100e68733e7367a9eb676b9b380162622e82bb547872184305
54	1	211	\\xd5cdae15012f67c103c1854af145e03bc7a68f9e8543e21ed7c0d5a9b05cc6d0bc3de3578bab7052e44696c14686ced343b6c5e1a67bb3ce2d32bc322ab03207
55	1	192	\\x02f1e32554c4b2b57a3a4f2af9b44074786e942b92304a1491c393eaa5ea2509eaf29b765de447995c4c865db3caaab21cf99c4414f93816fb1f52b41c97d10c
56	1	279	\\x0b6e831f237952b25a6f96a37ea5667b27d6ea5123c6a0f7a962e853e2e40bfac78b78cbd577ff3650b1a4e47cd6258840c59651b8835c6b31bcec94cbd7ba03
57	1	263	\\x77c93851cbc4ad3f69fa0b8423c513ba57818af29703b678b137c10933aac40f33a145dfdb9cb9684da9212788ff3163a700d13996dcaf79afdf01c8424a550e
58	1	183	\\x97190490b305b7fad6d11320521da61e9d036ee0b058721fcf33148a6ac93646ce35e582fea9aaf42bf462500bd2fb1c52efba922a2bc7f9289c82d8315fde0d
59	1	83	\\xbd1122c49c0fea617f11442812b114d70c186b4d1259cf88a806f821be58531f10cfdb3ca16ea879140c80429eaec9862e634bae6381e9a2c15e0419fbba8c0b
60	1	313	\\x2c164acca204fdc7713ec5db3f3c0f83055c3655a7c5beeb6087264594ca80d0cc9077f73b3ec8e313a1e02fd304ea8aeac8e60bd17422af2431a0a5c52f4700
61	1	256	\\xd0e84dbdef1bcebe310982cebb5db6d67df6318ad9ff82dccd084c63be045c913c452fa35cb292ed80eb0166b8427f9db9e1b09393cecd624182a8d2cf7b740d
62	1	63	\\x89535033ef44d0b483fdcf4189444681fef94016d63d187056ae4f3612f18fa3892f9b34742b8d0e35184e51dbfd95eefe013b0702ed9cab5a393709432c030e
63	1	335	\\xa67119d3ac9f5bd302573fa4cccc989cb31bdff161855e114f624d5169f6dc6bed2d6f7933a3b3566deaf6e9766b264f53d8998b07b1ac5528722eb5bc144e08
64	1	237	\\x151720e4acb2b2b4622ad23dae7dab4873ceb1e030dbd5190d53aef9736e60cd5886829919261d0a5521035a83dfb08b996565714152739549f95e69cb076608
65	1	219	\\x8795f2d56d27daad92cf47a7b9484a4147847a225da7fad4180109c1f9be0679b223ae084fd8720f6f2b8f217f56dab8e405442eb83b3cb2de7a5fe9fc4a0c05
66	1	92	\\xcf989c8a3e41ef3bf5f16bf9b6cb88c259c17d7af9b0843c79e3d5deaf98e65debb11b8965e80bf34a01279bb82dd99438164ea25c70219c668578b3fd2c790e
67	1	144	\\x1e62f6738896e998d6e2ce9856d98ac445ba9e6f0025ed64cf471ec13bef08a1f9591f1d127026daed5d169d32c86ccbb938d9bc0d3e2da4dc8f54a2d7783709
68	1	242	\\x4fcf7fe7f515d264301a5d2954ec15a7bd4a3ba7a658192563cd09a1182876915c3bad46fec7d459716223b90bb9ac2fdfef8e89fee99d22808bf53a138ef101
69	1	346	\\x61e7507f6946ef67e11dd7ef968f387ce632e659e4a18993c8f682f897ea6bcc222e31aa9a20a194979796b7c70ae99f7836aecb0d0c6aa4ca0c516ff2bb370e
70	1	255	\\x25315d023728ad49b60bbe999518fc941e552453376b983b835f6e197ed90a2b6f500db7fbc8293cad472b194c90f17bfcbc0944e68a4d8f3e54aba13485ff01
71	1	271	\\x15d47ec84ee63b44b1ffb49fe66a01b819171b2486f79b341d43e87abd15027346c2669eee6033efecd3fc2551686d48948da8fb9af4275ad4dc254e3b820c00
72	1	156	\\x02309f4dd0980100864c48ffcbad8c7005bdf2fd34711645e9cccb67fddf6a52fd5ef8ec23d53ee9170249841b119d5c9768ca593110bd4af7f9db4cbd490209
73	1	72	\\xc83ee331f14edd29b7b3693ffeb3f1575007b37a701788f9e69e03089c63c38cd77cb4610867dbe36ab96a4ad189f2e0317737f35180a13d8bb9a15c4248dc0f
74	1	316	\\x8938f5a3e4da4be1d936f9e7a4ed961f66b0b68f2dad5a1ed214340bf56a2b2fc617b492e66178d131192434616e007041775783b90260420d52493033f1ed01
75	1	58	\\x861d80ed065ded474c8179e8725f4ded402161e07752e04be1c24ab2f254f7577d33c396bf733dc67c659c29e7d5afbe715744f2f8319c662fff3ca121bfe602
76	1	317	\\x4a048473542dca814b339e32930b7d2353faea38447f76a6e1ee20a70f3203890f6bbcdfefab63559b95c8897f3a380a7b50ec332b076a0dfaff5984ad265d02
77	1	363	\\x82d49b007ff32b875ab04b680d745ef47cc86291b5484272a9d11cb63d5987f215a06fd43254c6ab1c377afbdcee4fbee1b724c0ee276d35659140dd73564e09
78	1	277	\\x91cc27d4b42d0f75fc4c34766d61092be2802d1951f69fd2b871477fdc24e9705140f20c2a7ab398070e5cd16bb622515b09cd3cddcd8d58bb23693ad1d40505
79	1	57	\\x2bdf95663bfa5f8c1e73d49d90a06a2c13375fbd0286452e06dbc0aadf24e8712c4a1f69125253148074d3fb2ec2f3caaf1ea81468812fa6c3e17ac4a8deae09
80	1	380	\\xf36384e048e936b515f6e6bb2db6bde7a129768598821b80257a6c1d08c8857628ed9941cda54cdf430a660d59ab5e049a9eb21d78cd1b6f079456e99aa79c0f
81	1	401	\\xb0f119cbbb1877d8ee3f443d177be6818e7acc291c0054bee6fbe6fa4d7a8c8c934c8750b057d379387c314bd840da724cd36354c03b1fdd0a39c21680b41a01
82	1	410	\\x3f050b1c587287d7f0da290a326290312493681a5aca8f58cff75a6dd5efd37b758bde0a10861ec39256ad1cf066747d1501eed73f143f7c39b145d4d88e600d
83	1	294	\\xa193da2ed7ef64a3a89aad8d51c3b8013b4f678a4dc84f1aaec231492d4d902768bd33a55cbdc8f25e193b1b8ce525a5712d6515abd76a7086811282cf1bea03
84	1	74	\\x15679a648ec55bb4ac2687a5e2f2a54e2afb0e433a9badf2d58a42803bd32178ff9a8ffcd0d1a7aef5d0dc48e66f2c794ee6550743217e5fe7811edd1349a309
85	1	145	\\x4c49cc8b9c3bf56a8a5cc608978a9180376810b54d0319a063df987311d6407032242082f8a98e2cedf0848c2e8944c67023958877db4a5fb83227e10a1d930c
86	1	138	\\x43846a8fed9f4dfe31b0d333dbf9282b79a5718badb8e8e3dad28f41b9f46955db6bbc84bb74933a6a1b47003c642071ad3732754e4b2f66463a188bc5bad101
87	1	284	\\xb989f7dc5c82be7d41e9da3d39de0d7d37f276b193513c7760e5510a526e9aeb5e2768343cad5d7b7225d946eb800ca2c6d9e197cd22814942743cef1df14a00
88	1	1	\\xcba5804556a1c794fa31263aeee17bb717b3159bf927f3b7166b0d0bd3236db0316c2be8b19d6ef598259cdafd398fa00a96f2815ba2d9b970af8df64492d801
89	1	193	\\xb67004996ee1e343cfe105c812161781ad985401503b818b52a90bc009b456a3017a716d22e53f36094544e29229231119cee97e5241c9d63506682f335e1c09
90	1	97	\\x74f6b2fb4e8796090cd2c99b020dfe695fb7fe4e867f0d53d80248be3e217d5c37208efcb43469f27c3b080ec050ab92cba906414a03f6f70d0b6210f7721d02
91	1	117	\\x6958d8b04830ffd7527b533b276c3ff6c7b080c3f6748ea22c4144fed4dbb5c887847ba0ccb9e65b8334a8a2d8c7a8996e7d8b971960016b348b262b2fd77a0b
92	1	175	\\x062bbd5ff941cc7b96cc51c8823070bc092864350e89446f8828d68622df5be498779fbe094f6decf30b4444456bb54a1b2e28b826cebe9d4e40d10892250306
93	1	104	\\xf069beef19ddd8c7430e116fd5578fd4c463ec4e68fc235bda7986f730b27ba2cc300d8223d4e110fa7f2784ec4851ab7d339c1c1ae609a594255904903b7f02
94	1	15	\\x990c6dfe2eaa693dcb8ffddabb9e7dc14a17541b01aa707b8a23ae53f0c06e2044ab85c07d8acdae4d5523ac4c01a7bcbe5ddee132f72f267a083079ea30f609
95	1	371	\\x2078096bec865d2ac571bbcd3738c33153aeb192628110b9633ee7a9aa08696bbc3c327dac7644b173af757e065ebdbfa7ff5d2f1b6ac56134f4ad557c961603
96	1	61	\\x296c4707d00b9331f766215b738b0a9de300fb3f8d2847eda7e38a1b8ec77dd037425eb1b5926cff850f7174f60b75e75b352ba6a13e0a4382787dcbde26ca0e
97	1	365	\\xeec556a58f3295b44e105500c8348c41b81e52b9e8b1375b1f15bc63648f70de37b9b31272a0ac9aac3c8a6cf626c14192832c6d77115a8a2367f9ba9e940f00
98	1	293	\\x1a13c61cf44615fd0dad9436cfc3c33e695b4a4114e4b9ddde67ce730f3bf2339ff87f54357446a248209d7ab5d30a26f71d2d0f913d9fed5b2802212bcd2b04
99	1	174	\\xec022180600ce2a09291f44f5c808accab1b8258cc97e9bd5bdfa98374d0bf88522d898c50fee27201c657e6a0ca05c6930828d21a2c48c87d6eacd9fc31dd0e
100	1	136	\\xf993488877bc64e0b8695d072a9b237caabdcfb594c50f25f97501e701a281380074c22d3a913b83b6304e8271152d510e5bdbfb75c4675ab26271fe16edd603
101	1	243	\\x4b1074e67683d2ff9e4824d07ea461dafda6c5cad365fb8113b433d52d1795de89a62882ee6ee88429855c354c34be24df9bd2f10a085b77b024dca610192705
102	1	167	\\x730fc98f0f0520875a2e032df89319d268d8066af803a40f4e66f5b362f991ecaafc0a5c25b4e26f7c8020f113a4c459fda7f0997f5408c1a37552f37b08700f
103	1	411	\\x3cf27ed43846eabd83d94060906756bd26c46c3ffee665c220948b26e8d7bdfa90450e1ba5dad18d44a277697b95a33a1db981dc898e7571709e5844c0af5307
104	1	356	\\xc0d173296e5dd4a57f6aac20ae14b9a72a47ad5049f967c2d8d9cb950378fd665160a4d0906a64cc249f233a6b325699ec102b2f1bfc5a86fdae5d8ecd545104
105	1	121	\\x8f0474093468f6b1363d00dd593f9b54f29f9b74cf12035b00382e197e2ceb484ff01f117fb24b678c1f8eb2fd23ba0194d4459b6922dc3b106daf86d70ed506
106	1	46	\\x46e3840b504f0b9aa9eeef237e30389641424b4dd1179073df8c27f3ae828f2942030dd6266e1d4b3f08fc2a4e1680571cd0faaa5aea5f2b41d1237a860b5701
107	1	318	\\x73059cf5f4e495a81c21389e6486005ce8a573a4b0f0f0e945ddfe8fe9f374d2a9bcfda17054f208cde2d58c046a81bbbbc6c5849ac0c80521b854051805e901
108	1	253	\\x246f964a320be7f1f52bf51d713d23060fc315c8c67577b45c389cb19aa390fbd4aac05ac3259619cb849b93d7579f07bb6ed1b85d3f9b8af175c0d4d6a4f102
109	1	125	\\x81650d8cae8a401acc58158b560981b6f60219263911ca4b8fc595e7fab83ad1eeb60ee252d90ec62629a2f0af34b79164da7470285fb5c7249237082bbe840e
110	1	111	\\x5dc31178d640ffcf8a501e2a1e0f5d0d57a9cc1ba21811474899c9329d054a9b5c1592c8d30695120212fd53af547f53b565532cbe50c5d84b7039707945ef02
111	1	342	\\x6ca7aae084b39956148b6b8bc5621f9aae3f5b7ab0c4fa37697a4521bcf80a9bfb352693695f13861528532e53dca269af47ed5d7565bfb596865721f3dee60a
112	1	264	\\xfd8ff1cc2c24ca021183c47f639dbc4aa650cfaae6c2b1b89713cd387542a2c94962bd532df08c2efce555a433ab54d86a07946cc0cfc54ddecff84ed9a62400
113	1	70	\\x7ee6f220697b32a9ca13e45e75f479a7da860aa4d23bf94d26b45709a578a17721c673561ef268bea5e83aceee3718c891deb85591f6529ec11757143a889708
114	1	291	\\x593c0d4f9db69ce4aad04c596171700fa059207f05b2c5baadb752bb35c9464dc45bc4934c5768b54da8d5e157107eb48ae14343f5dae567958b7d730dd4f800
115	1	168	\\xcec89e7dfbdfb498552497dbb7b74d6aa9a2b6dcf43296ebe2a5d2d4c8bfb39233fffd0f5f128441dc4965b1ac2de72e816137717db031f74c50a58ea3a2f300
116	1	323	\\x04b0f993e02f32cfeb64af66ec689de7b0c3e87be9f16da75aef66602eee8987a3524eef52a68c4d49928bd91bd42a1fcdffb3d82cceb36da2fc7eb1288a860f
117	1	221	\\x87a5aefe9cee10e178efaf8c878d5aba474ba7f8cd73e6ea27956ba6ed38cc68f8619f2a3392f3516e6911eea4cd7c8add92ac64b3c605dbe156be4a244ace0e
118	1	355	\\x065e0aa9ff5f872efb0f1dba4a561229ddd7e7588c201467c30df756b8b493b0925ee29d7a3718b7806b137224170753c183eed2e965ef0c454fbc0b7edacb02
119	1	239	\\x035d411cc238ca9d4185421ded73aa2260f0fa8a36c6eb5231723452764171acedf6b0784c0bdc25afd0ab859645870c38c86de58ea67fc553f206c662dc230a
120	1	16	\\xee888aa6f550b9b8ca68ff956270b227919e2fffda81f42de3cba3715a30c72e4578238cf63621880e25aea9697ec084f581d5c215fd0439b6cd493c7dc1100f
121	1	115	\\xae85ce1a02ab793d8911cbdfd029c4a8b790f19c83d2702522bcf50cb1c4e2ab609b5aeca2e806cdf24fce96bd8780f7ee0fb51852b85b6f26021cd64f11d807
122	1	409	\\x3b675c3401d0f2c50a33991c0ba66c9537b1b8511cfd1f8bfd71e4afd1dcb6a7d6c4038daff28378358ce590f533a0cdf7659cde58c1190a7642713648ddfc04
123	1	384	\\x34ef4b94d1d5833938c362d8c6aeb49b981ce37159a5046e250ee65fef9a85d41971942983934347248547fc56abd3b534ff2ea8a78b06d691899472d3a2d00a
124	1	131	\\xa9b796743fc1b91cb300f64496d793fb8dd056770fca2a4375d63721d8b84bc017704e74ee44c7d9e0142f13429b8a11f6f328568db375511cb0e786bec0e60f
125	1	163	\\x64d033411d16af76a39c03e6d1351371d0acd30b9bff591cccf8b7e3816df751ffa55a79350ffcf5662bc7fc7737f9155e33a03c9edec6e29fbcaab891400e0c
126	1	268	\\x06f872f6ccbb63013b3d131e07398fb9c3cc84faba59e16bdf1517a311179e7c1dcdda213abcb853047b6e7cdd81296917110fd05047f62da6d6d86322859d0d
127	1	385	\\xf90bccd0d6c711f9ed7ba24151d00b739e1b9ec0c54852ac7aabd88040bd9ec9796e98c9163b98a335d315644e902f0bca9afdb3f2402bdb02d973fd4de17f0e
128	1	415	\\xa56697d4dacf2bdafb75e644d416a90258ea00938381d67ad26d27e2e9abee88158f0a62bd4b98da369fa490a213e32a944085fddd5a6d81cf44aa6266dd2d00
129	1	166	\\x3fb53d3f5ab682478199af3f71573d9306e9c2c4a264975c133bcd824f9cc6ddb5d1d5b9d5226478df9b33c504e538774cd7d1f90539889dd3cfd1afe1179e0e
130	1	290	\\xda01dd636067ece82444f30f602388bc9dde89f2d3dc294a1290952628f7a35187d824185a170eab1ee7697934b0837b55a45a43b2605d85cff87d35f4a46f06
131	1	186	\\x1e80c2cc14d28011e5c3e4dacb2bc066250445b8a69307bbd704c5f20f3f9d19663c67195e4240bc44e24b1d0ac3c85b552ba436637a357fc0e628a8bc932405
132	1	56	\\x4e20086e9f08ae1a883622788aaf712225e7cbb8ec00164e26ea8ddfa0aae06c4ac45a79c828a0a738676af9bc135b20c42e1a11ec5271f2248a03d85464ba0b
133	1	367	\\x4e913deffe24149142ddf6c3b83b4346b4dc34e8b3b045625d68bafe244fd9f350afcac8431b5c911f060a607ef836403f8feb81ce558a24b97525ae51b1b705
134	1	200	\\x62f88ad5a8c39ed46e2444b078c0ac2134bda38d268829bcaf5249038f38ef07a7c51d1f069e011ec81de5b3450a0480e5a4ec8bf933625080089724b853560b
135	1	280	\\xe94dac06eea5582570a29321ee0f7b02f7dfea8cb646370c92757ad4ffe3da43049569ed007c34a73f559acb315b77cf876eecdb6c214359bc5fce370d8cc404
136	1	296	\\x0345d233ae3059a6f104f27ff449e6e64766a183462c5ab2de486d7bdb4cef81c84261c64c24d3019c2ed2cabdaa22c139e5e926b370b05932143d445dbeff01
137	1	244	\\xefad30552bc2eb35633086d63d8cda388f7a92f38616234053266ce83bf601fa5051089e9339c61b655e971ade7780b9ee5a9780d821e3ad55dde0b9199c350a
138	1	103	\\x44cba32c43eae615e406304c2b928e2b2cd5e5377dc9de95de3fb73e5c5f112c726362a8575d6f3cd083eedec22ee70d1f9df3fd0ebc9a38e14dd3688b244406
139	1	191	\\x879ad57c41ce997846aa7c8eba61a8aefe58561bac3b896c06c0856f5ff5fcf57d1d271193da027de3cd93ec4b19e99d80753dacc663a47c73e4a8ffa68ab104
140	1	226	\\x2bf3e5969759deeac5a3269071c91d885042464d83c70a9179db9889f970e61eeb181db3889216d93d6ae6381d0e2ce241192a04ad4843eb1c6f30831e8f5b0f
141	1	80	\\xd47eca14bf1cdba15d48ae24c665a85676e42bb0431d16ed914954c0ba07fc29ac052553e2586ea22d66817030962b58d6cf659942ef785a2768c8428ca17207
142	1	99	\\x12e998970fee0acf5678c84ec43262e35db5cc3bfab1de125931bbaaae00c4fd5b68a130cb60b7821c8e1c2591ef173e7ba36e597dd78c8062874e21ab956902
143	1	41	\\xed068dfc8859e5deca694e70c0727fd1e4e89e9d58764d1ece8469a8c3e161ff1821802faee6209062e9d6b75f7e2181bac50c587dc23b1f6d34065f9f1bdf0e
144	1	265	\\x377fe7184cb69b790bec5bb6ca964c68d39b77d1bb4ff98cc693fb69389d16718c56ebb61c38b4128b5b61eae7127edee74fef98f1bbe3fd8d347d0e6598a106
145	1	22	\\xf37658e202e5ff0abec736b6168e9ee3564a23753a70341e97a5618a34a1396a3df4d2a936ff092df2b80258bb786c56f7a17ef12e601db0fa15206749a6f60d
146	1	85	\\x0956c9e0717230f998dc87869c37807fae3e826840acabcb3750c8e22ab0a14a4ce37fcf2d7834a374b5a39dfe83d71a4a63cc96fccb7ae22f29a29906a2d504
147	1	118	\\x7ea00801412e42de78c81de1bff4f351686512d767389e69c43493ee77edbb824c78025d15f9f9142fbaf297012b44d7b3ff2038a05096952b3350efc4018000
148	1	315	\\xb43deec4957cb103718ad910d71da5ac2ae92f48192c98c8a30396d1fabeef0d89beaf4576faaa97b9e73d5ae72eaa3317eecb15137c9b1982a706274871ef0d
149	1	116	\\x78f6e6ebfd6e8322e2c721dadc6ff1b084c987ec895ae9173f4dc584b76e7aef5e80fb3664cf297b80f4541e82bdcb13fd3466b2e2b2c7f7d1ba1a5d27716e03
150	1	261	\\x957dbb81b87917cf94968c91dc1b2e998ceaad1c9f3eaf34f1e7b49c944d604d3a022779da85d79ae1d9c3dea25a2e6abb15bc9e98d9b32208c60519715dae01
151	1	129	\\xe791906dc05909490af91a509dbf598bda5e7206877c9e5887f0d411bd380b209cd82eb2788aa010029adfdbf4d3cf3c9e4fb3c886440abfd0453de4c0b3b00d
152	1	185	\\x633c6c202c50e50f31b1593fefb90c928d8823ce2ecd000002468425a61a3f7d7941accc2f2e32504b142a77ba54feba5ba6a82cf4a28b68dbfe9e254507ef0e
153	1	141	\\x39fc6bafe02b8cafef5c2e8f9a4da4b5208865f85a1387e9b32ff11c89397553edf69bb7f5d2e79578ded903bda896c7b2cb8f9a71ceb83a46995bbc42746a0f
154	1	28	\\x56efe6e9772ca49c3bc48399b381983cd08ef2c852f102462db1908c2c54626b2675c8cca4e0fdcf839ed373c04821565f421314690396bfb10e4609fcfc3106
155	1	105	\\x70065fa7f20f33a12b0b64a1dea1883af07e88424dab659308623a454418738cbe6b29d304f25010500fac952c910a1f7a14b00fd8eea9043202adfcaa456e07
156	1	31	\\xefd0d86db0d5f99a559add983b33785eaf74a316d50a161dfa821c80154f2b81aed2b2e3eb44ae213ff4002d6c6a211d7b766bda5eff3f50b0d30edbaff8a20a
157	1	278	\\x672d9f4b9609b8a9e910d87b13732b9e9d15025507fa9cb2f2ff3bdc7107bfe01a8c328348a1acf963babafe4f65f85ee1c1cf10e9f2b14ce39f99c2e400d903
158	1	38	\\x222b444497f0a69d9c08c8e33de0bbfa9e97284d132c78afc8d48c15897e510410e561c673d2eebcce57f479c4e3b00f400377f04e05a642d5e402362484e508
159	1	171	\\xf2854b7acbf8aca147675eb91ececdf9a23f0016f971803118cf85d7933bb795061f3774f9b04efb32cc443c5edac8b23d36316e34e273d6df172c03022ee90d
160	1	421	\\x4865eb75f96c6da3749333bbe899962c6943518b204c88b4c8c0f7c7c9c49f5e6aa87d33f1373a3f7c0606981bb000651cc5a77cebe51077957cdc1698903e0e
161	1	396	\\xa1d02b01481377fc66f30dbb1583b320ac2441782d0a7fcafcf02663808c3fbf9c0d40f1b29d71fed4eff38377a2e289235773c30f90ce1334a1ff90b26e0107
162	1	188	\\xb83f70e59422546d756288b52aba3cc45511f6ed4ec966cc8fe871a387dcba7a3e5e053f252e6c698deb22c7824be9f9d32e397505bcc886e5a77c2176521e0f
163	1	377	\\xbbba0abca5784bb33d703639f28845339098e9ee3cc58fc74fb9e1570e08148cca8474fa202b27922093330b95fa8b82fdf9f9e0dd5cbf097cc44f39fb0e440c
164	1	349	\\xaabd4583739ddf61ab16ba76f58eb8ff23aae3f92d71af087a605425bb86fbd9785da8f64bbbae5e280ef4997abdc6355d0206b4c2d3a472a515b93a7eb62308
165	1	159	\\xdfc90488473f43a1b7ac6d95160871ae16f6d6a2232296d283a905245949f1548f9bea6891e28702127cd927376b16c5131880a9b69f4bcba21a798826c42306
166	1	6	\\x4c2b7db3c42f76a92e3465e45d4d89db8e25c167ee3898bc629c453b14d8622405a83a52bf2586ad5227f511619a0a17e6a0866233eebc2477fadabb666bcc0e
167	1	3	\\xf1ac489caba76ae9db0e98272eb19fd3a60e0104d1c776789ebacf5fa067479045bccf6147d3387171c9e1ef18c2a4755c111edf67047f28902555317c01a600
168	1	54	\\xbdffb09cdac9538e978a922cf43cb66d144cbf82b5903911c0a3b185725fd037d770ea4c38c76228bafcae48900f9ce182206ea723eb4a598b48d74a87995e05
169	1	282	\\x05c464b66cd5587adf03cfce7dc17964693bbda924eaae38361fd59e200d5ad76fd646227fb39d0b28ea097ecbfd599fc872953d01951e82e8a4b2609a073e0f
170	1	18	\\x679fbe947e7123ada329cb375e080e980c19868330e6e924817a9c41f2fbddc2c20cb7b165f22603b7e8bcca21d6b7facabfb6eb0463f0562dc42783b1ec5b0b
171	1	333	\\xa5b5e8d26398b3e46988e09759a89e6c7abf28b9d273a6fff4809a0f3b08690302f4d8c6bbac42219ab7a40fd512911ef98db7e76c87cf73b87b52c1078ce802
172	1	292	\\xdb55116978ba18bd4b60d7215dd8e205a81997c3504ed674f2365078f91a51216872edd89637c05e98da27f8fca646fb9662bea42b721fceee7ada250a38470d
173	1	252	\\x7112340bbf4f8feebd923b01fff70a56ab24c6e7976340803c27175c2c1981d6777ad8d62eeea4c462d93f94fae91729cf243e34548386b7db500304be105405
174	1	152	\\xd9c8fd0df62fe556be753b6a65759388e201ae6ada3a5a5ba76973d04ae9e4bdee599488127e7f6c3383dc1871699b374514841b2610ca86c1de35591540c506
175	1	135	\\xef6fe7f8d8acfbd7122ca4a1ac2dad5677b66e06dcc5eca4d3994662578861751b030c6cc436dbd5aaa565ef8271485e73882a89d9326164a6c029d20b73ee08
176	1	258	\\x9cef9e57868bdfe3b0206a78275ec4d915622d64aab46fcaad7d767f8cb62fbdd10fe87b73c4bda65ddf587779bad174095f7e5c18e6b532a80014cdcb9b120f
177	1	386	\\x2cd12d804d18c9fc42768300d4fdf07079317e7c0a958ad156ade15bfbfcdd975cbd0377e5b778e04ed02eb639bad6ea6b2c3eb0d6e720d8dc6433e3ff49320a
178	1	251	\\x15b4243dbf091b217c01b21bbd1125842a5b3bae3a131dda4f6ce6c9da54bcd64e59843d274e5d4a54655834fa05016803973da2b1b33839e7a489766b6e1f0d
179	1	155	\\xd6036e827adf0f5cb60991513fbe78ea4061fab0405e3a7b45723f622287c6beadd6eddc0cec8773c026a306e7451302cb63eb951313b2f47bc7bf4420461706
180	1	419	\\x85e8211699e3fb65b230170ee0482add723179e458ebb78c14249cfa6d782838b626ea3c8d5ce682176f215de878e4b6e87ef420c0a884dcdbb21d3388a4a404
181	1	142	\\xd350060a804fef5f46ddd29efa74206a11ba8288fad0a9be763946447dc21095d4cdb0f4e9be6bb8ca2094db4b12dac040d82f88fdcc286fbe54d8ef8cf17d0d
182	1	398	\\xd8744d2cd046c4a0452a2b03af4461b9357604f5a6b094613328b0cb3a61539829b4704ea124d5de56c2daf61eaebc9cbf50fd2463787ea8113fdba6529c4007
183	1	59	\\x44866a629c28473b4e620cc88702eb5f035d7a4b2688c721372f1c30cfd51fd385f842f6c19712a1d87304cb0127ec39e953afd7bf53b869763b7a721ce0fb01
184	1	407	\\xfdb589a5ee330da2071ee05d244d08f16417ac7e7fc46b0269451108e3f7387613960ecf581194da75edc29649ba69f5b1d155def38ddf8af2641dbf13d1d90f
185	1	148	\\x980811e57742eaed8e38b883eae27c78c11bd3183af76181317d878f8698485d25fc6950e1b0160909ec6caae83780f75b606c21d41cb8786f579cfde023d305
186	1	376	\\x43d0fadbbca6ce1ff2f8ba972cd5d3534dc707a4bf6386fafc29e1303e817e0e06665805ab6a11b777d7080c12559f2af0087875810535d5f32b05b5dd881004
187	1	20	\\x1becad9334df9cb109c5a4679571030c777be5a6b6d0ec6904992524fd8ec884e34ccdef6bda34a18c44f196efe72c85f5c7b247bc0adb2b3c4164e5fb65720c
188	1	373	\\xb6fb8ed068cb2f9926cab2a355f6943859e48b215742415d48d01ec8f15b7fcce4e1e498739d88d3cea7acb3f65da86cb03f05e9106c196ce001dad715973304
189	1	359	\\x1af9655939b971b98695013aa41298673143e0452a1e8b1d857b2cf2fcae198ed328fd0df41666ebab10ca094e81006d5adc403f142c88b2ad8379c93ea71b04
190	1	229	\\xcb1c1bad0e3e0a997cc5dff18c687daeb61981fdb98f0790a36213f20a71c6c941ed84e57ce8e4ba9ef7028e7157ee814f4fbdeacfef3a4db7b83e2db7552c03
191	1	203	\\x8ac4242927296b79ab6eea519f518d5a545c99f3532c446f891daa8d12ad3e079c259594be63a92e1b223bac13fb062f2796e09a0ed9ec6fa068757723ec0e0b
192	1	345	\\xbc03900fe7f9f507943aed943f9d01665ab15bab0efa0d64ee94a6456bc11f2ddfdd09d1d3ee8435469ecfbc50708ddbbd2020bdc526309097a68aa1f69d860b
193	1	238	\\x7cd0664764260266f21bd7c0ed50bb88e4f2f8b8d6ef49676c6f922ca2fc33aa7e7cf6633b90a0db28eb264284a159afb2146a7def191da81da2d0ab283e8009
194	1	13	\\xc9ba1c9beda27f0e02f3e6363218643d8948f0af43c96d4cfd2ca1040655d7098ce7e6c7b8ebd47fc37266cccbf3f300d83b9be1b89e2dc514f437cba013cb03
195	1	95	\\x671c9e5e0565459b74f170f5a50cb2ceddab4ae5c5743a08482eb59c4db9712f4f451fe79b7a58cad1eeec61a83dab126947a5f9c4b412565e2f17b417482d04
196	1	49	\\x5933530d7754a650ca29e705184aa48555980a9725130730eac14eccfa31bd3045f9b77e8d0ce44bd49c860f38042e9548128ad8ab3a116962e734b1efc58807
197	1	40	\\xb65a97edee0410fd63662b417312d94e9a565fb98f638f81ed16964a59cfb5a06f0949c624726ea595f2f46a96bcb0ee12ecbf4621c27e1f65722ed342f71e0f
198	1	306	\\x779ab370944100026de6d27546aa7e57786e7e8bd4afea117cb468e5726b48637509bcc5b00b66a204a7dcf4e4049cbde45d81a8816c9eda9924f4497f7eab0c
199	1	178	\\x52bc249020ba9c0252514190c014afdf1d28e83d007287c4c119ce3c39ebdf48c31002807384d58e9674801374e6bbafe1a3a4795fb0c2d477a016aaa7dba609
200	1	312	\\x7440575f65898dbbb6c28a1c8bf01c9b8eafff6f1bc1a64ab05b680d99e404a702d688425b7a0d8d031d8ccca12ff3bfb26cca9dbf312c526cefa7a0a2745001
201	1	267	\\xeb773f92f045e66521e98ef5523a149a2f2876520a45b3c744bd357e51e2851180aa668232af02bb8194bf23b6dcfe10b82e46a9cccfd30b7e4f3eb78a6e200f
202	1	403	\\xc411f29d19d0563e1f05df85d84296b9e9bc34322bbbcf51902b4f53124aa54846ffab95f7697358a522353d595a403a4f036e7dc05a1b942baf5992148f7204
203	1	375	\\xd72b737e28d4f1a84e60f60ae60869859af2ec63e6953b59410b881ac21b6d26507af097634da9ad9cfa25e9ce12745b57c25dfa46c3253d4ca985fdf70c610e
204	1	126	\\x72f2c37c5529b8e5f830d47c5ff9d9b9d11e1162011301c9d4bea85303de8e3f52965c7975e5869465a6e813fce386576b4197209f74687c0f79005ae6883807
205	1	269	\\xe833652c929f75d485be1df1e68b5722e50178964c07d504469b635483ecc0279fbd128a981f0939e1deb916facc444e3666409ebbbda13220adb2b3f9d84003
206	1	388	\\xee75ded0e0a9a9757cb7cf454b34eb1bd8b089c2435c24b0d1777f53338378103d32157467d887864b358fe7f24ac7a0fa7016e6ee3a8431d468d8eebc180c0d
207	1	88	\\x8b6dbbd6fd38d49fd3eb92e8569efb0288dfd046334bf44cf04dc59d92f368a92fc87d3b962a168f50a388f0b4441bd0c30cccc8209a226d791043d838825e0f
208	1	149	\\x443a7d8c22366f9a6a69007c4f5241b6b7492eeabaf13d0ec995a9aa3045c3f27d5935205c291e320408ed953aa72591ca5d04f85b40a8538f81fca9d47a8f01
209	1	86	\\xed7e9984b810785a0844b5e72652cdef4cede2effa0fc192df584e80413bec2f7edfc9eef0814864df78e1c356b48847bf5cd0092959d852e41f59ab0b990f03
210	1	50	\\x764cb893dd1add2261b1a2a01d64eced3bc0b51dbb0896c91116c99c04e8b78e10a3b2220151e4f97a00fa1cd943f4f1a79dedd2a7e6c6fa34575e149d19000c
211	1	164	\\x39fa7c25770a174c3fce2840da6bfac8ca1eb9297ffc9ef9a04c20b632a93a7789e33f367105c1bb29644f4af49b30af1bf445e7c92d050a7a8879e236545009
212	1	11	\\x530b4fb74fce2eb1506add1b1e6199f02f07100051a2a2434719d7a0da7c95b4e7462acf7bd7abb45a12ed4a5894ab8ac5b453aab5eee19d11fbd431b5b17309
213	1	417	\\x76e6f55df19597928374a5f35230b6b0d387d575a5939dc9d9d0b2241c2038560129e1c820ff915772090be49eecbf916ca4a8d419332d656a07ab62395ae80c
214	1	374	\\x6ba67373cd38ea6c23cd33a41cfcdf5d7df82c02a24641f0ab721aec2c5bbd1f70754ac2c8f91d60df53f479bd86afdb6ad5a5062753e3e8b176ec9483ccee0c
215	1	311	\\x24c1f3f341fb52cf5a8e0311f383187ce5acd0bbd903586fab98e18c315d3a0d373bf17963372d997342c021af30886e648d69de408250dced0cf8f9a950120e
216	1	84	\\xb3a60e8a468ec28f635f506593129bf14fb268074869c22d9a4382c7b53232586db33ee4afd1181d51bc7580bba2f81f81f699ee4fbdbf813b51d8c64cf4c905
217	1	179	\\x6640e9a50113277cfb56c11010993d628dea88342e2ab6adda79cc8ec284e8da1cece8310c448e57711ab6b7b46ee91ab314dafd418a341353c94f5c2264e70d
218	1	337	\\x2f81c9b2e0e5f19265f3db51c3366984999806a94a992f8fb595d46429c71a06993066e6e6b5efed1bd6cad9fbae86fefad9ce2b665b4c272ef5b2c9cf78f30b
219	1	47	\\x70a3cb46874b0b2feebd2ecbca1f067ef3a9b80a35f0d90d6ea8a1317755dd80bba93e9d95480fb4789a5a735be4d1cc8356f4983b3ab77c5289ffdfd6ba2a0e
220	1	147	\\x0fd01ec120ca9cf1655895ada66a2d222486cc80895f42ca7a539f621942df2adcf0a43a281e0a00788d01f23d026a7bf4060a41520ee68942d79fe9fea99906
221	1	222	\\x62bdd7350a34dfa775119ac5d5cc6691058fb227c6ac2b0ce254f629df39fc0025d8c06e56fd62e74042e6709b9c0545dc5b1a1524fe5a1f5482af2b2d638b00
222	1	358	\\x6a846b9ec8d6ce8e4d06816d8f4267f73b3d876d5149373acb84950106d9e6cabaec379ed69c54d5cbaf6e554b1b0251c661e8e8e031e4205b18cc83ddc9580f
223	1	81	\\x1e4586dab840f01260edf5eb9e29f488ea03ab53ab4e0bd53e0f0537fe00cb9102553c38cdadc580bb6bbf249c3559a754e3992bab367c5d111c6b7f45ddc201
224	1	153	\\xeb1dfa3cbfbcbb33a3b6f795c89b3449f00257126556f5301abd4db23eb038f06ac9776030168d64e6d45230dfdc674bccdc01702c319dc5e7a4653755cba80b
225	1	137	\\x6b2bf029e0143b0c6c5cc1f50da9e365babd7ba9572620dd1e118f880a1ef69b4dab3ed1a453997327a6f05653ebee399fdbfd20af27670a922376ce8aa70807
226	1	157	\\xe010763b37db4eac7cff4fa14cf5a67e85db52fa71e7abb38af7e8c2fcba6f5f3f7ef606caafc6926c8bf32926f3e1c306fe89f46cdb54352dcc35a240777502
227	1	122	\\x6eafa59104264ac70eb69c9261c2d4b9683b4d3caba095846c41e5566b938ecb631d910106f42a05a5f423c85c0da3bc42ccb2e0d059712bca8ea203bf903f05
228	1	259	\\xb9a0fc7c433eaf9b527c9f3ef7536b7635743d0147deff9951ebc31b160679f3fd3859741dd83ffee52995fe620548d50f8e47b99e0bb57aa7fbcf7d812f0b04
229	1	420	\\x4404f0aa8fb2c2d7fb9001faec48b59e6accbf8e52356fcaf43b27c91aedeaea3cf118d3934b77029db077e431816f2ca4fc8fe6f776f9bb4f17b329802d110f
230	1	184	\\x0c05a62f9a4cecfea663e3e4dfde7f995ec1c9114c3569ab657f2224c023fe207e2858aa4c1eb5cf00d5018a77eef61b1bed75522364a23671a9f3241034ed08
231	1	329	\\xe3b3905ca92fc5b4817e9b76e4fcfa4e1ffaaf225103670f6c37cfc0362679bb8bc7057f11bede5852748b274ab57eef4e3c9f9112de0fece8de7a4166b02401
232	1	53	\\x54232487379026f8e13f41bcd1c2c1f4e816caba59ad14281f3510504be444af9dd7e371581d398ef7992312791dbc4ed550401c69c10575d55bd773e2610e0f
233	1	43	\\x691f1dee75feab7cc75471ca036b40e5aed978d09d7128b0226f3341619c7fdc8997383acd4147759705da4b40f96205b6708560f13223173c243a9303908e0b
234	1	228	\\x00422cc26d52870d4447f4470465105485ca731deb6a03a538647d875fac39f7dc1fc90f3a68ef8a80ab6b71a8e17d1fdb99d0e2fbef9bfcb3a44b1129d76902
235	1	387	\\xec2d847dbd4f67ed00db0047ef035bdfae9791b79bdc72b73779c4107cc9d0fa7cc293586d32b998b5a202a2aa0947b9d8b09a58e21a65579b5e36705f21ea0c
236	1	24	\\x2847979b47e5228e88c77a0a443149635ecb75157ae3dd47e11a81e568d1d97de963eec54a0fc9616d2a2ae5375f883fca97b0e34c515fa737f085a55277f90c
237	1	308	\\x0eb42acee40d08b642f6cc5d36f16f96d7d15af2a878caef69abd91837900268638afd66dcc7401e8c9fa5692b7f98108b025b25ab1027087e22c5cfcc076a0a
238	1	393	\\x30f0377e9a191830d2c2397ced6d654af64399bdd1278c9e4f7fce8752b1cf456aea3ecbbe58898d3fa62d2e29df81d97ef965557c0d35ad0ec985f453a0260d
239	1	98	\\x858126cc4b7727f9139ebd4f2c2cba6e494b92f2bb6ae6760b0f2333159c614be5a2f7ebfb64f2c0807aa14731c72e7ec01d1ee129a056af47c1888b48a69d03
240	1	45	\\x330e20b4c11d5e512cd7e3d4d4c92746dae103ab930e7c9757fdef37121c48a1b236fa26f2e2f0c4dce50614856e88e19df22bc068f0abe071003ddc8fcdd20e
241	1	180	\\xcb7a38a26eb401038c4806ab4123d76f3cc828468cae69c72aed2b07abd5cef726779d8e96f4e392e7a738cb6599bc01dc3e4e6f081c27f89c718d84e66f500e
242	1	76	\\xfb485ca8e159984f5ba2456ca657a5010eaebe19d6ed4770fef2f71cbbb053f6ca2f7567be93039cdb2076f04adb18b3edd5f830fdececf42af0d822163da00e
243	1	182	\\x37ce82bbbc8eac0706a642039a9d0b2e53eab2e1fe099f3cba017dce58fb3d013f22c64bf740768c87c2822d35b46e7c8aae6ae5bc26bd232ba409e95597650d
244	1	270	\\x05bc3d2880e45f2130b6d074acc38ec92cf6666e2320f856113dfd518a9460cd35e1a22ea4c7f3b6b4f8b162ab7ba3491592b9f56d7657e0b2bab031eb536309
245	1	44	\\xf45a6700ef77da8f30a9977a1e87688825a1eef949f0315207557af0f807d789cddd43cd5565b88ac3a807e7abdcd6f5c947eedc3fb534a6dbcaff55a0af410b
246	1	310	\\xf822909cef47d52b4eca08d77358e92a448a38b19dd7cca67c26e9b8d1067dc50f2f9d84f0c390cc0124219e1f497587cdd5995b6626f355b5d4b40327e1ad04
247	1	42	\\xe3f6ef1dc62d948d0f0538f213bf23d298ff87aa56af194a92bfa000679a2fe97eed837b838ba39c3f69569dc18aa13a014ca7643f11680b3c319e24a9812b06
248	1	340	\\xed7da47a0245931e10a056b9de19ae9394832b55546e48792239a038dc4f9437fb6615a077ad323cc592c7fbce4996799e5587a4ded6704687c55b0826c1bf02
249	1	368	\\xcd5952a2e6fee9b1d8cc1570af5155fd8fd1c8dba8592eaa89ab90e2c7824689af54f53300c17554ad1f68cbc237b21d6311cc55bd79e83b11d90b07e1a8bc04
250	1	390	\\x2f734267ca8c764c5043631f6c11a6e396ce0f56fa2a14de549a54a33dc50d3e04ef452a62cd2e8146d1aaff5472d85253f51f5e8a3197bd97f22349b513ec06
251	1	68	\\x8753a3851e08b7d47aa8fe2a86fcc33228b4172ca5187abe8ede395c3ac8dc4966de40d2d0bb014e1f03eced23b67c7ec5240c1afba7b1efd26877d15e43800a
252	1	227	\\x250d1e0fef550b2363ef6764345b571e57c6cb6c48ef172a82761cb95622ea77783550f079d372f734369692ae7ac0084630d13835b8e93f1154ab0979008106
253	1	27	\\x81e546b7a7916c82ac1865552d7fc957b05169839637de04847ae0ea8f3ee0bac33d0dfc7ab9c06ba1abaccaec2839c0c44d4ef9371c322e8f19aad36e8def0d
254	1	307	\\xc5c92d7167235017396ea2a69e80fb67ecefbcbbb602c3c6d1054931717f44ea57387bff443defdc73d33ff90dd3b275637684b05a15180b003c5a9b9e8d700f
255	1	176	\\x3fd9e3e11353669579271de918580b03f000d2220d0d753bf6e470d5827ca230784758466a8712fdbcbc9b7f08d0ce78fa00575bbe4057a5d5f60b473c8bd300
256	1	339	\\xfef2430531e6f527bd7862a847a61ff0381398ac9e8956df871fbae869ece32a98edc755ad08306a8d0c79e62c6b6f3df5ebb2430389d58a02da13a4a659070d
257	1	89	\\x0c0c5d00eb6e72bd3388c167f9b0fc4dd6f55d370729ffc9ed6d6a2821d5ff74caabf62a3e19c2424966bc63fb423f200d1f125e3ab0710f7a624817d5041e06
258	1	37	\\x2e801834e85cec0f2ec8d22b1a7e4728423659019c16b1e9a5668d38a161a49da2e425dd9712e8f775589c7df13cddea692d33321d444e37b686861f8459fb01
259	1	35	\\x53cc4325342923517951a99e512a0c62b187a71dbeabc007d0456a95a179a7116da6a5e2d73fd2664c4312155546e9905a2f165e6e4f5f7b1b33d553a0230f05
260	1	120	\\xba8a80485e1463d07f6d4a6242920f084899d4823ed4e528996df36690685c38686b7b28ecb276dc996a033a4c39431d675e7022a717fc6e038174c09b975c0c
261	1	245	\\xbae9831e8be39660542d6472e1f928f9973b59bfeb2e9ff726e6b1bb00c1a12dcef46a9f249a96e4205ae3e9c07531000c099c570a8598bb46d1a48fd31afd0a
262	1	262	\\x4202ca4156f4a802085c072608a4608129daa2f79bb5a4604d2d5609be876e6105217e7bdfd875aec3779abfeafec8aef63007b32e9a753758c563451986580b
263	1	240	\\x1036f88ce66a027aac98bb1a867ef77deec9f77bc50c22d01efd399b6dc403075bc7af589bfdf7fa7c6655060d8b311ddf9fdf525002f3b00407dda429853307
264	1	7	\\xb3e4b86735c5161cdecae434fefe71b0d7c79897c1b10c2d04cedfef0069fcfbebc1103d376c21e2859f47a484d9fd8423a02e0c86072106928bc7b7ea186707
265	1	210	\\x9386a6262da6a9f87b68e73cdbff1b6f1cc20b62513fa30f52d610cc9c8acf4aaaa23de6b21ee340c7eea83ffecdecec8dd77d069e3faf0ac3d377d5524b4e03
266	1	303	\\xdc8021d6a59bc73875df3fb877c7cd9ee2d718f9c4d30ede5115cc417468d41ef930ae9d1d77538f3e7a0f96d981c47bdd9a1d6b0514b59163f00e1c116ffe0b
267	1	236	\\x14b53b133bfff8b994efeb1ba5521a83b8af28ad8890bbded834dcbb68e082fcdc45fda4f033e19145e6879baac841c40c47f1a516c2bb69da9aeb5de6d2930c
268	1	395	\\xa6b593593465ea5cbe221b3a9433a19608e1044cfcef9d78e806084ee19003eb51b45deaaccf80ad22adf9dcb056be63919d1f6db8d3512df65531f2d6e2cf0a
269	1	336	\\x9984ebe5564f320d8f00a1188013f7a576e0f4200356b5983aa5c507e90f6ea4117c4336834b1faffca5d2a7abac258da6d33ac0808ee6aa8831d3c09580680a
270	1	217	\\xe457ad1c08d2720bed24794d919a2c9d76951b7a82e37c97abb09716120833eeb1af281f09d53f9e66793594ca0335f154c542ae5c84be39c40c2dcb68e7a203
271	1	10	\\xfd6cae090ef691b96a36a82289528ed9bb19525edba632555c88e99547ebaa99eb514e7830365b646287a1386a12b7799b35032e5e2afccf55250fe02c90fb0f
272	1	23	\\x86aa74f1f4bf6192a5f5c8e3d9bab605395fd7f8ae939adb908d1989e998c0fc0af36b4b6bcb4cc179cb0bd199a75fbb2ae1c87c1862cff3904a71f313279b0e
273	1	343	\\x6ba099b05f80743851c598e754fbb6b7f4001c6a07194224b93bddd24fd6cc9158159d6356f5a58a785183653cd49df50f553341c8e4758c10a7c075704eda02
274	1	330	\\xeeb6ed563e81c596e47ec30bc7f1d6386bf0e7e84cfeebad6230ab64cde24e1b5a58c8121575798fa7fe90a008ad981efe1f6b77cef59b1c3a7f184bdba1cd0c
275	1	230	\\x6b22356d376a952f1b7948a5e16d77990e5c867faab1c8d64282dc52becd7ce5861238d723fc2bdb9c290ff422b70141f8fcdc80bda0c1a1ec063b90c1796802
276	1	12	\\x18fd725fdaded404a4131b34bc03a184b9f892fd06ea143334eba4814dbd9b8fda0014ae90cda387b5c8dd327141569de991aded0c2b10df0ddeb2ad027d2304
277	1	132	\\xf47a0807e115e14a8740b38d3b511278aadaaff6b2db82b024d0f69880733cc981860165a5999d46f67f4ffd6af3a0435d0e9c3abefa456631760c24a00c2e0f
278	1	328	\\xb0c09f33dd4a9e4f7d2d7b476976707f471fa073dd84b622a23355040ef36162956f68f46afc3e7b67f7758461a0cff26b37ce5a27ab326459ce1f68d340a804
279	1	195	\\xf713b5c4c7e856ed93b02cccf1bbb75d64bff138d6db8a1a4482f0c1df3876b63aaa67bae54059b16cd99f17165c9f25ad17792f79cd1ca744817495e473bd05
280	1	34	\\xe97b9f3f8601e031519cb72cd0d5f455422a053f7762dc431454a4637bb1af4af87a539c254a01e75912c0fbe9629efafe4c1668b84c663588f107a0fb303e00
281	1	26	\\xcb1cce7ec236334e059f3e9a92fcd242f5be1ea1bbc1480262a79fee90a183ec5d2b1f334362dadf61a5ce3bf1ff2ca9f2b6da65abfa25897f517aa52840b90b
282	1	32	\\x8f097558a374517f860c30b42f393e5ac7c6ff5b532d1568862b745ea7292cf86fefd87a2455c4318af522252884a9fe39d82c18f86771e9fb01e86024d21405
283	1	100	\\x6fb6f7266057757dab545c0afbfea4539770c7dd37ef622ef4bb74a82997d554358843e4306706fb8914e6a7ce83456abead606543f8e5cec813c263dabf660b
284	1	302	\\xf8759ce4b7dcf03e8775094162d7d0ee2dadf9203a27f2eebb6aa876c14ac84f4e2e635c8a405703627cf9dd0382d49316382ec39f41c030b57ca5c68fffab0c
285	1	275	\\x6e68eeb033df5c1513ed5c905367d5527d856e2781a68366273a47b291e7191007dfa793712bbf4d9b7dfcafb3f7d2b8394098490d216bc4b9c600bc8986190f
286	1	169	\\x110edbd04da567b2a9d4828cce80011339571dd70e400959029ebe1a855bf15ab5cd97eb1f727354467e36b9d66b2e4bb99aa6335658c5f78f2c3114788d240d
287	1	109	\\xc287e62f363f553b557267ac522b3e7bb327ea3ca9fead458a27b04ef2af38ad0c1a1abfa50e0883db5abce1bbebdcd4f7a492a89e7d6ddef91f252798491e07
288	1	400	\\x4d5c41f8996e97b1762594f0a7946532f9d58b21d6b4b66be133e44ac9513604123497e723525b91d926b0f220e7a24653e75f920e7d1d469cd955491d39980f
289	1	62	\\x1a28430f827f614d4a1c91d34c25eb527da0326c8dcf63e545666f7b5635b89c86dda036dd0a24a7c78791de19081fee1ed20f55e63cfa760366705504cd580f
290	1	366	\\xf5aad7dc5c3969d9831246ec696477ce6f707027e6e7594af197e1d1585a37e8706e9d0ba8cef92ee75d41a09c9d867225542a5d80177f35772cc911aba8b707
291	1	382	\\x7bce8af643bf5dd9c10a846e6a93c51fb8ad48cceb42661ee3a846224995fc9850d019e05f426ab69ce2ea122242e7e28af057e0d7ed8d355d9f070191e0d90c
292	1	326	\\x3e687408fed34e29113c0c32b1b1fc9ef7c4dceeef55260feebd5f4da63bc0f9280a52fb8bcfa590493516969f817695d5dad7c635861b6c0bf104006ab14705
293	1	320	\\xf21f70b00bc0074f6d663bfb17606f6f9b994658f39e304cb6c1d3dd5bf738a8f45e40a7765673299c98dc4b294cdb1cd4544e5ed8a5b6a030a22298f1b8e306
294	1	114	\\x1f8d637b5d600608c285c403514bc1696ae0e75359fbc09f3cde245c681046b3f769d8e94b5e8582adbaac02cdee4925dbd2df7dc77d87860d2b578788fa950d
295	1	48	\\x7492cc793a6b57973c69c5acba293d406b9e435512cf6e28c19c616baab0a811a8f73a8fced75a9e47f3b7ef7fbe8c803dd5736a9378c9c33bf01ef743653c07
296	1	276	\\x3ed77ff153af2d61248455431afb906fd1e3e83d70b10e300ce479f0876fd70060f2ae46d63a8cb35644c71404be9fca1ac2766adecbcfa9b480df84a5b0b70e
297	1	30	\\x7e11923e2d6a1906adfb7d7c439f385eb61a01859eb1a534cf65950b7fd9617a08942be2b67b5b0a5a7b28510651127db1673756ded670504d177ce195aa9301
298	1	369	\\x90d9e6257c9876d4e82bfa295e302c7ac0c036dfc6f073b144c13e375cbcdc6e5ab9fe0b9e4ebb21897a91c6be960b3bc866e013d7b17cd12d491410d53ee800
299	1	19	\\x55c4a7784df06c8e6aa8d057f4e94fd5034b67268dbfb7fe717343cef9edb6fe4b2f9fb8358cc4ab216efbd470a114ca8627df7141dec9b4862593bed30cdd08
300	1	204	\\xad57f2026fec33fe1aec0b5c04994f4b5266f5bbe43081d99da4f69af6c7ac8a7c852378aef3b2ba94c152a3db8133c081d6c0fc72e1f559bb49c6d0a2462d09
301	1	412	\\x6a28a18b57162abc3a739d12f8256657301f5e68de22dcde571b34de8d975e01a982a973ac0f17702f7f676c7a0eeb8bfbfb9b1cd173a973709a061d3b54050c
302	1	295	\\x3978b45b891eae307f3bb719c4783d1f70f60b78a188b70a8715c8a41ee4809066005ed0ec72d4e1826aa29b8f9e799c55e70d7cb6a79488cc12b5c6684bb70b
303	1	351	\\xcda87c4d260c1136039c529a80bf0ca1e876c81bc571243e257f2c991fa9aa1bcb2376cbed1eb6802801cf8041ca7e15999e02693271c7fb7bcfb8f544027301
304	1	378	\\x8952f7eb61741c2de476891ba1040cf4a60e7db058ce7b4a4190a550bed8e73c3cb94a148d738d160fea7da1bcbad879c6995231581cdff2d6934b9d0fdcd308
305	1	39	\\x452456d663923842169b6cc5f4ecff018791650ceb10c900ac4de818bf96b474911473277ccfe67db6f18dd2dd1e9af36484f4b3f737ab87a00add906f609e01
306	1	397	\\x75ddb3155a0d9b647ed5358b0682f2ad3090999d968f611397a5e1f3e3db251a259591d241d4d8edcd582a6f201bcc10d5db435ceb3c5205e5c266c4a361bc0d
307	1	205	\\x6972535e02b91f909ac2e8ea84681e7e6c742c0253925edf474914ff9f63915bb66c312fa9b3e09d879e2078cb55cba1aeb5d1d6efffb2c951ed02de2796970f
308	1	391	\\x4e93016d02d4be3be26a5140590d4f4c88609b782bd96f3ab43694b6efc98ccf033670494795aae066fbd2685beb3e1413d05686d56b64f6e9b02a5ab6dac106
309	1	283	\\x440705a141c8a444c58db1047ca2cc64e1b7b11635c0ca0b8638ab8be1fb7554395a8a8667eb9883ef16f58c6afc90d3e7e9e3d1ee786a4f7244d35a74e12b0b
310	1	332	\\x3ccd950e7c9f795bbcf5e9d83e6c0bf989a4d5447b273d36ff50d65f7da3beedc0607b80f6b96b651e33c7922a7f30c266a966a0270d5b37ccd5169cc524a10a
311	1	14	\\x9bbba9d931a1f18c5ee0230b5eb7229b1edabac4f3a1f659034f9e26253f3648689e869edfd80867e1bfce4d2798f043e6a4df6cfa67f9e04492810cd821dc01
312	1	246	\\x7579a347c0199d097927514ca41549b39449c20cd028d5baf0ae843f806cfc5c99cc6d137246b9c5f5d3e9f73dc862b01604b1a9d7b81ca5a02f26792b75bd0e
313	1	281	\\x4eb526c0c4d88c447448b67a84bcfe43b1dd080163667c6c0419bd09d767e99b4c979b664c75f5ff34d4887182dd89b9ddb66e183062b7cc893baf29b44f7f0e
314	1	413	\\x4ea02e5062f08bdc0af6169dd441fd1e44c41b681e0cc3060284687926108cf2b8a57ee210d1930a648df261f9f2a471512a8d6ac3eba92d5e07935e9d85330e
315	1	357	\\xce0b753edf472aa578f980b2482290987b6baf7425b711778f7706fa066f79699e31a0b5371b8827c41b9158b48c67d22c4adbf381d617d744ba99637b707a03
316	1	408	\\x189c51e560cc895df1048bc99b25cfdc387f4e0632818adbd189ae68b17bc2e9496aad9d08d39509ba1999cff20fba05af221d9a00da7280b6cb370206f74e0b
317	1	286	\\xa21b3fe7a8f2755403ac258f34831ab098f2dcdfa72c5a51406e91c7f1323e9466db67ece97c403ff7d7ff7c972e102a6062c490d6e67658031cce82e5af9506
318	1	322	\\x70ea2f66c9a762fecfe77c2f034c0dbbaf414878c29a86468401d3a548e5142a072e18f447bf14f0d51606df2c134368ec952cdfbc83679c5e551915d61c4004
319	1	260	\\xde7135e8a23109364aa0b1495069181ea44bfe0eacb1dc6e978777882e64559835308a7ab75a0a8ee41ccd5ee6a3c5ff612bc11d1e6b6f620d189c862e1c930a
320	1	257	\\x84590136616eba0e309507aa1a4f5c98b8f76763fa73baa2f502bd4bf994daf123188b2546cefe7a40cde875e6a767ec6b7f37f7af0733538a6a4c8ed94bd40d
321	1	69	\\xe18bf69e464f61fa5e69ab59fc3d27cfe9b4040b72734f39eb25bf7795ad77574c99fa3434054ba720cae26b95f6289211f5de31851e48f12cb0bb1c05935205
322	1	207	\\x43e81a14c3a7b683178b9ead58049d951d15da7a88e839dcf7c89b47e221ed338eb485101256e76b7531f8ffb0da98550380694459caaa92a00f9f86c9b0b100
323	1	150	\\x821914ffe1a350fa86afa851b24b2c3f3cb5f5bb67c666cb574fba6cca4d1e8c77186d461fea72b8c3b7ba0c8e991f4aab7020a3cfd03004d8d8b0bb7daf9b00
324	1	119	\\xc2d61a3abe4365e3a7fdc830d577c0165d9021dc26b31defa8333defad71ba2f72d8f208dd70d7839b669e1e1c954bc2f2b4ac25f306c4e0a1c7bcb9d4901a0c
325	1	402	\\x36b59749328b9ac04494e14c94c4eb4563136fab3ec2dec4288e4d2d46cad0230163a75e22b52b9856c394613aa38b0058c7c14c0e294bcdb423b58cf40fd501
326	1	36	\\xafca4491c7a17d514dbd0c5965777d4513e09d68c94b2940f3c3afaaa2cc3231e3efe67172632de51f9c200a48d111fa4490cad228c3c60b21c6163d0ab2f307
327	1	233	\\x6ac3215012d27e596a83d3273ad2845f1107723a1cdea85be1c07c77677931c3120b3aaa57195e9f1f6a00a15d0ab0711f9cba858845f4bea9568bae9fe3e60b
328	1	231	\\x098c8c2aab4decb19f641d9bef265f9c40dfaaefdee70201b9d2f8523c6fc29c9820257cf9db19eaafde3d49986716ac23db7f650d4fa12697b433ded879ae0a
329	1	232	\\x0b57c823198bd5d7dd4f14bfd936fb02c5ad0f7d5b8bdd382d3ec113b8728946efee07c3ddfc325a74a3b621684fb94ca1dd3f6907aa8857ea5c3dd4a236dc08
330	1	247	\\xbc5bbe92f81b4fe1d69aef8224add83ab070e8c993d98f1762ef247239d424e64abfdc512b89d93c7d83925468990c63d6d5122725c123a46044f84cbe7c300a
331	1	297	\\xc5529a00e69fa9af81f0c70bd8dee6d3c32b1c03763c2af902d1536e6f4b092a3398a36e4faf58a17663ae9ffcc91a9b169659c175ffbcc66a0065f7c0449f09
332	1	199	\\x32698f7a4fa4950f58c67856ef33ca1a8c43f6dc9b1360c71c53e2c6269c15fc54fbb5305d83b38e3c3da37ff7feb6d5a6104f4e0d25cbaf58c58b07deb8c00d
333	1	196	\\x8bc7971fc7462fe7a566310531041565accddc84b36c8830da901b93639ca407d6e980a3e539544e1ba9fde7b2ab6990847e7a8a1aa263c12c0ec8e51b1abf00
334	1	108	\\x63cbc701575f7abbb66b433529d1eefab86630e62ced6a4c4b15f3c184e6f0c975b29ff76b2073fbc9322acc2a21a61cb29df996d650ebf43280239317f0860a
335	1	354	\\xd38bb301fa067782b7bb44631937a7478e80a16e26d8af39e3ec210f788c4d1d1ba8a559a383846c2580569f8b60982765ab987d0c0a26efe900a9b599b47a02
336	1	91	\\x17eacc21fdb3de1078c1dccd66fe10d277d181ac89f8dd1fb7f5d459e687ed13fedc005dc8eb035c441a990b830f2c309874f579d24da66c557452ed996f8b08
337	1	55	\\x20186fc4cac9371dac859ee22088877c5f9ba4f3345ce3fbfdbf233635099696b44232c5945d937b2e03d3ba8e6d9e0ab6c758ad61a1e657e3375c39244bfc0d
338	1	379	\\x7e20c57dcb24a96b17347adcfa43c09990e83dfa7e3e11dd46c41e1eb4c6bb9355d3ae64ca4020900471b95e452609870a015deef9897e2bcc7721b832bad90b
339	1	189	\\xb9f83f5354a880b679dfd2f487d9125c1a525bc1cf2cb9ecf15fdd9690b10444774dd7c8c4bf1534e83f7d851888446e5cfd918dc223917ac43b22f6bb0fa504
340	1	361	\\x06383dac4195200f39c25da6154c7b1de2ce81d76c7bdbdf18a571d7fa451cc9bf4ac216bb1b5e2bea338f9e648941215c975826f807396347e2e6ab4026530e
341	1	321	\\x840e797993d907b252e9f3cd9f82b9f2bdf125669a0600ca2bbeacce83d05e7133ebc87104c02b7c2520f51dacbfbc18d6325c4e39e232f9f7cdeac47ef3ed0d
342	1	33	\\x233590532ed429f148ba0a64ad7d72433fcecbbb517716fc6205bcfeeb59b805ac7e2bc98351717d55b8c16ac7484c5d13e646780db36f135be88fc3088a610d
343	1	75	\\x598d031bca74759c54ddd23bd6233e7245f2bacbd3821a83f56435e74ab58cf73339d5cc7c5f50145361cea0773481b5d624a6b0246c51a4ea293f8766c86a0f
344	1	146	\\x7107184f43ccaf7c0262e39cc7ea748938eb252cfc2ba490d77d4c01f334fd99e510d62c8572962ecdba7adf5b7b5d5e335dfc27ba8a4cb4eb1560930c04be06
345	1	305	\\x001741975b8d776314ed0743f0efb846b263fe744376ac2322c98b78a0134b976223b40b6ad4081f06a91e0f9685efae54b78eb356f73d8bb3de6d9973067a04
346	1	241	\\x2e751be2c2f839ce518934b5eb6558794fcbf2d7790195088376207efa9ebcdff2ecd097e8671e99d941ae8a0f4930ae12c5f45c88387106236eae1726479b07
347	1	202	\\x2fdc57827a39c0a9c0b676888d324e4df4edbfacd3d538ae2a4a4c7c592287eaac0e99569181e358b762cd25ac42e30e759905b473b08834dc7120b539047108
348	1	216	\\x7d9724e7abf4af2699faa007c13d31846ad26a103dcee724991c57a95d3311c72123ce9cedd76c82b4c18c8bb965895b7b402f238e40a642392ed7ebfaae6b00
349	1	158	\\x428dacacb81d6681d0d8979e8ce4318b208a14a91f51434cb4f8a11a08902921509cd89b99a094f7bdc4a09b608baab67d73832eb90279a077a0620fb89b7b00
350	1	64	\\x9543145e30efe1c3e2afaa51c157e117bb23cec82eb625d3492070f2324c68587e9520b07685433894874cd646ebd907260c96102f406bbb043573843bbbd106
351	1	218	\\xf86e2b1aef1cdfb7634e1572ee20dc6b4283e0117bde4a45a8a78d999a52322ca5f2451c068d831a7cdecc6d4fd47ce1823b0f70a9374628e3ee755bc529360a
352	1	112	\\x76d1a7ceab7785417b34d031342703d0895382825f80f163dfd924e016eebca5f5c1dfc8a1078d98a32ef5b0226ba8f979dc2469acfd3513ddd5b53cfd42a302
353	1	161	\\x693576984560f5c05d5ce25b38bf3f4f3a90bf1a21a19428d32f126dfd8c842ea594a5059cc46b7f1f5ff6c2f0c7a84091c1c16f188fe250a760df49acc08208
354	1	324	\\x4d15bb1911d9ddb518d3a7c5afec3dbe00623191d031653d844ac3fc35614e285d76d8fbf0274ff031754040a90e77634beae0ebc3ab7f405d1e14402508a305
355	1	130	\\x0bdb4482355be468b56fbfb6c5f36cb49f31455874e7593c0bd0b73a0a2d1062514a2271ba88657f5ce2aba6b0fe188947d5579ba7a04257fe19575ecd69dc0c
356	1	201	\\x2e6fd3bc2fe1353364b04739cda6eb6ab728635b79f9f50343a2e61a40e293a475f1d40ef35d2155f8f200b32eaeaee4ccf2b12dad5728cf61ac2ab2bd9d2408
357	1	289	\\xebdc386c26ad87993539f36b56e41c658f3e03a9385bc9fcebfef0fb6ee472a59af526abe89be4aa3bfe03ea0be27884a8d1b6647bb33222c15d11a7c589eb02
358	1	225	\\x155f0228ca858c90d903c8a59445ff9e1ca01397961f41338b1e0c5b49c669df5c4c26a0ec0fae1ce7588e045f02132a02a92e9f9989076d10594e93fe18c802
359	1	383	\\xc2a78842f85eea24af1b2a91b5150a963ddf3b6b293fa318469c4074317b31a09ee0d3fcd9f8a80122f17f4762512fe367d29ffe8e1703026ca2b53f08d8cd06
360	1	51	\\x5150893125383d3c35106f19f3d1a5f4464bd071a2f05eb97176786873fa5843edfc91c0c07251a0da33cefe93b16379a8511d273747965fb7a26c858cb44d0b
361	1	300	\\x7bbe675b589b5e2e97c1ba4f239d111f06aafa8046f979e90b09f420943918ccf0f5019001d1cbf2fa739cf4987ba0e040cd5f61368db39ce34c96219eb6770a
362	1	93	\\x4ddd1b6f2860dbde8190ceedf1644fae1fcd9d37fbf9191c8f5558ef8f82fecfa7af36341e952016593a4e1ad6418cf0da74380180f0c5d9e73a8f259a9cec0d
363	1	170	\\x4bdd26b268f47b44a7392056ce139b264cde33d39e9c803f1625aae8256127ebeaa437329003852b9cde061e7af5c910080fdc05a05a21f2cedf4fdccfe7a709
364	1	173	\\x448e2596d072b0242ed9f6daa6b1310aa279565f81da622c5b9cb949663261878106ed7439c93da6a2c1b02ea509aa167c4c883ec9fc29913d76fcce19663c06
365	1	101	\\x71f1d2792accd9765f3329a0afade801ccd20135e14619b786a79939ba6e33f6458b13957b5667f289cb06ef8425ec65984c5054fe414f91de4d521ed5a0f500
366	1	160	\\x0cb33830168d7479abb21ebda078330195fa15b487388af48089ae7909931a350c7732d29a23aba5df8eec04bbd28f1e8fa92e8dddc767e81eaaa075e9fd1c0e
367	1	2	\\x342c39bebc80d90c05858f80cef97c94019ef59832bd1efc98f9f247a465439f9eeaf96a16e9ea56e71c236b3540b4ebb2f39ad2b70f81a852880dbab784b90b
368	1	8	\\x337f8e109eebf853a5bdc8971dfd3877f4110816e04290109393f23ab684c0cb960d4e44d85b53c4dcd63743ec7842f62b34ebe4746f1c68b932c24106d31b00
369	1	133	\\x6cf1930e3f60d712e20265250301efc713c6457794b474652600572303d2733244c6e7c34fc47356bea58c63ba000e393f872936720329819f5a2023ad58c807
370	1	181	\\x76934ce547f7da08a73a13987ea6f3921826f35adae88eeef01a5b0c973aef5e10c349e8de7346b7438deb9cf5d0c253157508aec0196dc237c9309fb531b603
371	1	71	\\xa41de9dead287403e2c7f7e6cc90ca80d3a37a8ae2ac105cc187ef0350e458230d0168a0639aecebd22c6f3a602d7a193d63cefba0a6c75a0653a95ccbcea006
372	1	418	\\x353330598797256ba7e9b46545b99bf39ab070b4721bd531ff7cf15812bbe2fdb924598310f44c21afe10440711881e81328a9878c7a1993726bb42e1beb8808
373	1	381	\\x596e4d51fe8489960264a8bac36cd5683c4d8a6c0b7434ab2b1719ef39bbe5242a0225ce1fd966138630f2be7e88bef1276e82e0e011deec9ece5f630a47d60c
374	1	197	\\x1581a62b20b9e4b6f2f9aea06ad7986489132c68fbe6d692feabdbc53a15bd2ff1cc7c223cf4cac63e5bef913b34388b7cecb1a79c54af61de1d7c9b9727f50d
375	1	21	\\xebd8dbd7858f8a333c54712c5ba8302c4467a0bbbc0fdbbc28072584eea390d0c500bf1b2909a3af8666f544d97e409013a7e42833c81d4a29dc5aaa7914b000
376	1	325	\\x2cc7a29f3652455e20a03480e12f17d50fced146f0e7b5cecd5fccb292795f7d1a448be6e3132c9804b12ae178a102b4e9d10fe70abb260feb7b2723bb804c0e
377	1	151	\\x4caf5807750e456c1946f1cfcc19d7cbcdc4716f87671bfba8c36ac35f45ad775725368af6af95d50386fd909f9b6babed93a0700f56a203a96a443adce86c0a
378	1	341	\\xb63e4a5c9ee237032955ecb3362f1c426413c35a8defb3c65aebc60e91bbf624e1d5fbfdde392f136820b7d59af65fcd90d9e63b6bb8ff860db26ca650cb2905
379	1	327	\\x219897532ac6baa49baa167e90f45b87563c292584103dd02e3517c3d5132bdbffb5113d0c26b6f08f5127a3fc997ca7b87d8e1501a059fd85a1f00e5b77ca09
380	1	96	\\x86c54d8260a9c03a55c445e251bdc040307cd1f8b8da1e029b77899530c07b14176fc3bcce6d4b7a1ab83fbb5d928465ca36136112680d2a8eedb29bef113b06
381	1	52	\\x13e8cdd1bc11fc25e09a6a89f38ac81b32daba149bb7293c2002de05030877f4a8bd1ab93f2746666a7ec8e29e8be99069a9aeaf1f0ded2b619564decfc7b90e
382	1	165	\\x18eb6d92bfeb207021e9801e3e6288ced8f99cead482732d5a147a00ded25324d304e719e04605021deeaac8968a6d921a1de58067a3c03c763f2e234230180c
383	1	299	\\x9b3cc77d93160bb6e17310854da08d51c4316b96a8e5372a87b87d3bee2873efadd9da2a3d7a34a2008ce4374a1f1889fb4e6b462c9e0de3e87fe0360ce99609
384	1	187	\\x1c65a134772e33d1c7cce4ea7d1e5cf697b5db27eabcbb0e8cb93caeaa2ecfad5c7f2e3933da686ce1f07520ef4ab86dc13f40c9bf6662bde4215273af068801
385	1	82	\\x4edb3c780b58b180e3bf5b1963cdeeb4e054a13fea947b3988c63e889d70458876ebca320bc9566da7a99e5e641ed125186772d19ea81bee5cc2654be518400a
386	1	389	\\x88a46dd1ce3dee4208add500e36820545826b624b4b8b32b4053185330a3ad64ef98d9c5894cd690a0ba531022d8dc7d8cdbb61f4a8f43261b0ff029a937920f
387	1	250	\\x4db36516c614c7c954504e5df73dbb9c77dea3f99ffecbddad5a5f43d09647e01e364c968b8833816b0984cb0db361b7ab31379d15e28748524d3bf90630b10d
388	1	73	\\x33787a83e2b4facc0645d89a5b680efc10df2f585b8e7cbfe189a40d8c175636146dcda0d92e94e94208a1e21db8c245c641ff6f1ab2a55c232121295077df0b
389	1	404	\\x098bad54ae4ac8a905aff2cbf2f22a7fd124bb6f5478888e05f5da49eb8c8b45eedd0b630d6be7a7591fe37bc60b75e36f561caef973f235659b20689f843506
390	1	347	\\x5500dee870172599e19c8094ad716f68a945fad67fea9cf71c2570e3bd0425e3708f78839ce38489f9b0e9e6703252a5bc98edbaa2ae74b1826cc5799b4cc103
391	1	78	\\x5a466f3bdd871f1a4f436becfd70d3492a6cd9176a673db8d06881747a717b2fec43b50bb3305b8650fc3c8dfea97a2788cb912dc51eaa514d594843ccfdca06
392	1	422	\\x87cb694a278ee4849708057f7a7f38fc0233474f14455b552c35b1cd8363a68121a145345cccb512ab6a3850f8e0cb987a6cf7821913008ca4c76f20bfbd790d
393	1	172	\\x4069e033e22a65d4f0e5f7a6790454fac447b5f5346fb6adb1be26a7e107b898a6b5672d7bb73ad24622084687a7b5ccfb60f0f26c68e4ccc55e4e80dc538e05
394	1	406	\\x7f03485a940c789765fc7fc7c8f6bb7c7d7d5ee7cd334c1dd9f9e58254e9a53fd35d4d7ada50c65eb6efbc9209bd553d5bcf308bea7f27205bcb76209d07ac09
395	1	206	\\xda9410660fa501a7a05a9bb57d6f499ec076878087340bd7b854184b6e781d9343412071279e6a04f444cf3d43eb97dec358aa71f37c5c3788ffed0c60cc4209
396	1	60	\\x13406d5f1af807ce1f14eb5eb7286b351ef5193ef8a28d2333b1187a45769e44df884add4cb16bd2307f4b2db3d64fae8b04445c5ffaf4790a1703d531bbf402
397	1	94	\\x0f73cfdfdd275ebb83ac20173edb486b2b6831cda19f34f712491958128311adb528b037d168f3340ca84a0faa2d2b98abc93e29c40abbecb973fac667804102
398	1	234	\\x390cb89e1eaffaeb9e97476ececb0a747fa77a0bc4baa73866ab96e54bb96c9c207c8cb813dde7235b74c258a780b056c4cb0f5e144efdfe89d612dbc208b10f
399	1	79	\\x8a9d63f3b8c37311e918e5129efe430afe41db0a82799d3d94487e39d719dadfc8da5e9a9e4fa58b883f8982b794c898529671efbf32f393db7ce755eb0d4407
400	1	364	\\x6c353f96f189eae7c857277a9a833431c4792be3f1ff4b8fa4dd0cc9dea531e3254b46530e159597b51ef6ec944c536435ef467ee481a0d93dd4dc62f0b42700
401	1	314	\\x2bc892712cba1da488d683e4afa0a89ca85f18d9f3c29401c9411cd72ffa0c1c1a37471ac78581ca49c415c378114f49c37ab500c669d57f9f0560ecf68e1e09
402	1	87	\\xbe2ea3a5e09de346917c38b0ddc828eaee918f0b6f87efd0e71865dee25cf3717d984f914b9ea257e0cdc8580feda15489b5395d07c567b6f759f0036638ef0c
403	1	423	\\x69faaa9700a1565713d63befc5947d89d9b9998b09e8024aaccccf98d8866cf895b56faa7fb83ce721804020d09cf65f460030c69a2046ee4116dbe472d43007
404	1	352	\\xe907f8558577026b3c314e50422668e51488cf4351395531bbc2f46c3eb1d75e201bd1dfbb72cb9e3abb68cbd9cd25ca6cbfeceff908e750f3b29d25f3de7007
405	1	154	\\x4d6565046c5ce4022ef2410cf4c9afab7602d5603d472ba6a8c60b0835e159f26e70fc514391c5e549eb2affbe368590b7fdf3ef4fbaa8da4049d3d520b4350c
406	1	134	\\xb81f5d43a6f9d0486ff818038d2e2d079ef6f24e5a40a11b2de5ed42d9179ab5bde0a0dd1ef79fba2fd714301f33e6fb9e26e9dacba22cfdca546a84f9525f03
407	1	394	\\x9e2c2e1446acc3b604f827ea5248ae809da645241896587e7c8d0d2dacd812fa87c79295e29c8b98c7d1def98c4163deb79a02a4cf250f54fa4235f947558904
408	1	213	\\xbde5e200db58a058d1c7046b07477f2e03542006cb30eac3a248dd290468cc8b45ded81fd51ca67f2438e1e3df635e4c720a5120a7551b92df0ea5c726cda900
409	1	235	\\x9583e11d5e1c85c49c439f4c701720af63078ee33a1aa209d63e2e47f5485b2bc46b7d97ef2d87d02d43e040b373146070d64c17b25ad3a8a944e9cb5b83100e
410	1	110	\\xc0e02336cbb6e327a2614abff25ff14e738c6b095c3c7ec8a0f1d66b37b6f636be20b8cd128a5fd398ad71dcd05dcf5e37cc4e0bb83e5084dd2e739a9c06300b
411	1	353	\\x015f628c3ccf210693f643e92f13582a4d858507c9afc0174d06820f5f7d751713d14a347dd040817efcbcff3b093a88908eacafd7128c7ee24f9f6c76081506
412	1	177	\\xa0776718f8fb42db6aafb2fb4a3140e8d22ff61f75868d8619ce1f409b1bc5402836da4a9256856470d8242d68ababe18ead95e6ebb5afc113c54fea669e0500
413	1	304	\\xd550f1ca511004705b5af9d7acd88c2d5b8ee7e3c6d441b1a2b0d34aadd9e40456e15afb81aa52d27748502418b001d4072f9090b1d503a632ade04678994602
414	1	162	\\x9cbf70e4739249f056f1c5ab143121816ff95e98eb06e8aa7eebe8c01534be17313d9b884fdbd93b876d2480c554d622caf3f10404ba378459eb17586849e708
415	1	102	\\x793a0aed0d923d947239355bdbaa74b9059a4cbe9974479cf06e9d708b9db067332a54acaffb4a991bd4210f92154f16edb10cf119d89a08e26ea46b1ceee80d
416	1	124	\\x81918a4576fa2a1cccd52340336b17ec125fb6b4742cc9630f56213b0cedef30ca548a39331fbdcf92fa1c0fd698731a36417978c43b292df90498aad73d3205
417	1	90	\\x17476c22a7b16d10d2b5a39abc4e138c2630f912b65c3f7c8c8184d97c0cfe9ab682a07b23481657a87dfa52c716546386c142d1c8068c26d7fdb7e8a3dcb408
418	1	209	\\x493dc08e6c56dde16523e297727f49282581a172cac06ac6929b8fe1eaef10a032aa6680a73ac90e0ec5346e09730f7bdb9a2732f1fe3eca07abb557745fdf02
419	1	139	\\xea7a589fe8e7af43a001ebe66ff1516456ac1a0d6342e29a6d9e98eb22b5cf05d70a76bcce7127e2616077c8be59bb72238038e186f9f3abe96f0ba81148210e
420	1	344	\\xef05af67b85e4b6c5519b89ef4ddd8bdb1dd5f329128dcc80201b38911d93949f842f2c4394a1daa9c07f4a6696547a6a277adacec9a709c53a4c50ab735480f
421	1	17	\\xc98760f7ebd619c28779fc3f2f4692227c2e15948cc091bbcd31d6463ca9f79d5e8087a666c1f6a54339f8e54d381b2f5db72d58a42b3ff223b71ae75178ef0d
422	1	143	\\x363ee3edefb049a8ed6ea3506a9cd21c6079dd265c6e20ffd309918332832f7f9983cbbcf794de71cd593f13b8cddfd50a3a88c6a982a1ab4f9bd8a3bd2fd202
423	1	223	\\x9f42c7c56c994ddabb0ffc043a1868d5ce780e5347f58fc4db746be45f3e17c877dd769f6d9fc05db9bb9fc1af9e80613787a08882025b6021587d26fe032000
424	1	66	\\xa99fd847581b7ad10fa621f5c754ec3a9d7b60d6a250b6a8da920aa358cdffa9a5d4b66f6da071223fe3356278f199f0b905e0335eace66619a35ad002973a01
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
\\x70f1e90eaef363c059494275bda7ead04a29bd10286274a6666bd6e6cf3b4aba	1648212464000000	1655470064000000	1657889264000000	\\x44250085013f7a90518aba97f7d7333970538c87d5d338b3b742ec4ae572a258	\\x1238f9b9ca5e855722b7b797bf5be8ccaec40e44aba10c3dbe18a104c3e9d2e813f07a90ceea922b8436d6aa2722dda13304a2de5ebc66d278636cf7ccf3280c
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x70f1e90eaef363c059494275bda7ead04a29bd10286274a6666bd6e6cf3b4aba	http://localhost:8081/
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
1	\\xb8a5a95137b13e12986a648a5a29374620bc0bd2bfc5a5527442b8333d035f52	TESTKUDOS Auditor	http://localhost:8083/	t	1648212472000000
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
1	pbkdf2_sha256$260000$8Vqi7mKVHc2BRx13J6Boyx$mDyXhol3xJDTh4E2/aMx1xcJV2vuSy+nEkpF7d81akg=	\N	f	Bank				f	t	2022-03-25 13:47:45.355854+01
3	pbkdf2_sha256$260000$dXYr4yM366zr8lmrvltEbQ$OXSTig5p5WUhR3eX+e6cDXI28qj/Mvvw0vzf0ZQQhVs=	\N	f	blog				f	t	2022-03-25 13:47:45.619706+01
4	pbkdf2_sha256$260000$B08s64F0RF1JhvWjeGmQ2O$RQ8szSRm/MaEmDKjQSS6pyHsasJgzZ5OzbBX7SYGbDQ=	\N	f	Tor				f	t	2022-03-25 13:47:45.747527+01
5	pbkdf2_sha256$260000$PmqbnLDf20c4p5O3Isj7Tw$gLXV2PJwBLYcI85W2WJAXzQCKunlpi49+jDhJMml0W0=	\N	f	GNUnet				f	t	2022-03-25 13:47:45.875883+01
6	pbkdf2_sha256$260000$qXwBnPeVddN9lZXRQoauNZ$YLmWskc4yC3Rxx7T+unb9FmUpHp56bSlITH4bWfFg+A=	\N	f	Taler				f	t	2022-03-25 13:47:46.002797+01
7	pbkdf2_sha256$260000$WtE4YMadiUCjNXLz7fP4TF$8evBPWF91eywxsEKqi7RfNjTd5BjT+qZ5kR6nbNFpY4=	\N	f	FSF				f	t	2022-03-25 13:47:46.140236+01
8	pbkdf2_sha256$260000$aBf2Rww50hHaCNC62Jv2mK$EoxD7RDVq4COxdyQS3rOPuW//kZ1RdXcWWtvgyWcFvE=	\N	f	Tutorial				f	t	2022-03-25 13:47:46.278501+01
9	pbkdf2_sha256$260000$cvQFlPgINHzYkJ2zNNqaKs$uekzIw6pbFB1ERVVnbjs39lfUGOP3LIo4/q13Lyqij4=	\N	f	Survey				f	t	2022-03-25 13:47:46.413243+01
10	pbkdf2_sha256$260000$4Nt2tgyCZZiQPI36MmSuwA$rqMp3tWSkfdHyb0zyGlEy+lCEWd5aXOrQ9Uno7eF42c=	\N	f	42				f	t	2022-03-25 13:47:46.904952+01
11	pbkdf2_sha256$260000$mUp1gmkkaVcbLkp9QxSeci$Hw5vLoyHz+NIsImYmbU7zKnu6Kc06FKCH4/7xm0B8Vg=	\N	f	43				f	t	2022-03-25 13:47:47.417468+01
2	pbkdf2_sha256$260000$iZbaPaYZVlNZMb9I9evSJi$ZVC8cqLGsK+79N4fAdOcmT80lSWduOzymjG5GgrPkqo=	\N	f	Exchange				f	t	2022-03-25 13:47:45.486452+01
12	pbkdf2_sha256$260000$5zndLnFidlZnH7Qn8wfdDK$WU1J1hhyDYJDml6eKmHfi+rYI2YlvxtcoaL+TOBIqsg=	\N	f	testuser-u0z5vjs6				f	t	2022-03-25 13:47:55.927582+01
13	pbkdf2_sha256$260000$qfACkKfNqqU6h0RwqG0tCf$qv+lAjyxIjBv9MI9S/pEciw66QdHvNZeR1xpo9bTizQ=	\N	f	testuser-9oufxebd				f	t	2022-03-25 13:48:06.459119+01
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
-- Data for Name: close_requests; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.close_requests (reserve_pub, close_timestamp, reserve_sig, close_val, close_frac) FROM stdin;
\.


--
-- Data for Name: contracts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.contracts (contract_serial_id, purse_pub, pub_ckey, e_contract, purse_expiration) FROM stdin;
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
1	\\x01345bd33ccdfd37dc4f855f377862076146847bf40b2ffa22b2e1aa4db59207b4cc9d2ccce8a4ffea2d0c88d0936302db911ae5ce71c3dbdf44ee93030217ef	1	0	\\x000000010000000000800003bf38f903ce50e5b4359a93d2b576f58124cae893d1847fca10b85c516fdfb0ab9fc724f73d221c8881a69e2a9801fcd7f52d5258adfa59711ce8e9dd360399c84f6781cfac534e444c100817380105dedeac238140788b5464a878fc86c2037fc4c454889378957a65570c28eecb71830a77f2eadd02b5cca9a891870a1c9d59010001	\\xcab859f75093404fc95143a8aa5fc267695f6c8177eb0890f298a70463f8873734d7ba1369a5f18bcc47179ecd53a9f2e1de51dc6bf9b8eb547dac760a846b0c	1673601464000000	1674206264000000	1737278264000000	1831886264000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
2	\\x023c29681ac8e581cc660990d1013ac0ab263c979d64a6160b374905bd98d06eba0c36d164e2ffadb472f8f57221f95c9a36230ea395fa7eed0aafa7ff2c06ca	1	0	\\x000000010000000000800003eaa5b9376d92a8814e1c835112bbb13c7157de76280e5c59ca1d2f8730c5209d35938bd4aca08241d4b9d0b36ac9bd609617e5f2681f01c6a11f526ea2140bad517924397cfa5cc04a8874f693bc1c455ebf4461c17c716bd1def12034c9abae7d4682100b1b01e98a1e8aee3f964dee7f127a8c27829c44a4fca1b6d4ba7183010001	\\x9bb3c679e04dc79c57ded96dda1feb563461d532eec053ccfcbb746f0e6a72a157e275e8bba98ca55e077b9548cf0f8d14a1b7e219a4404be2c85d16c463ce09	1652443964000000	1653048764000000	1716120764000000	1810728764000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
3	\\x05540d6ff2dd17b73694998b54ae515089c2bc1f858fe33729260e1cf7554465d7b69b2bcbcf4147950d73bf037a63c732bdfd2cb2577a299df13733e33c0d35	1	0	\\x000000010000000000800003b739f9bccb0bc7c60c83baf09dc8792ef0e342125419a7fdbedb10072bcc7788659af1fe5bc1109b93021a17627cf0a7617faf3ab47284e953b76fcd5a829f5e316a7f27fa6d204aa5ff0ee8360acc574c6e94086c8ef8711fc00fc2fff439810a47c584674235afc37c1306428b01455b1e0658bee83559bf4a429386932e3b010001	\\x76bfc27bb246d7857a69df00748d37db24ab9b16ed5ddcdbc0d05bc7a24b4bd3bfff87e9604008cb264074d02f8624d56f8b5c605cf6a9693c2bd16fef0e2e01	1667556464000000	1668161264000000	1731233264000000	1825841264000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
4	\\x0c206bf07242e16f481b0bbae84cd1e3fed513a934d00fc61e71548b6641af041caa37a44d264781ce62d2ea72678a091778818102d37edcc316f09f780a1a47	1	0	\\x000000010000000000800003de1d40c3a1013c2db49e4d352278d25be97a4deca72272ddc64a849bf7f92080feae1021663407c297d0d601e48dae277b200a405d81e659b750442c99c0bfb9f3f8bd58216dc0fa1648150383c7e47f903fa1c996c8e58f334265b06127ac0763443c9dbb7ef0c0d66a818471060b4cab3b748b4c363f6a8b55a11f2fabdccf010001	\\xbb55901602dc4e7d166ade8d843b81674f14584b9b3e956946486886f87a52b550cdafa6664bfe232fd8a61ed62b8b64fd0e2b9be89614a42dbf693af7e91100	1679646464000000	1680251264000000	1743323264000000	1837931264000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
5	\\x0fac050bb397db30d09391627cd3051bed3d95b16b0f79168230b5a150dd319a3515b5a92df928d211859f05d236b2a5f4e3e2d3ce888019f260676cb91c517c	1	0	\\x000000010000000000800003bac6cd59b47f898bb66a5d48d09b85017a2b484102328fbfe5c55dbbf7154a24e78c1e10beb41b9a6c8cf3289f10d74db62815e588cbba4462977dfdbf7c57a2cd96a0f403167a09aca80f498f0b4af3a565f8f479185e747e43377d2dd8e8008d3f6b7bb175183e6389a52182a6bd263997cb52d5975c9e94b93e1e0faf9fdb010001	\\xfad4879c42eef6c9a80d9586b1c78b3d0c4c82d7cd3867bd254c9705e2e36360131a3b5746313ded6cdafd9b691d932f56c29144817960a9bc9d193e767e5704	1679646464000000	1680251264000000	1743323264000000	1837931264000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
6	\\x1128245134490500cafc840a791f0fcf7c66cd9e43638d9916d80b3b78cfed5e95bb1c107339e42f1ef7dcf760d7625f3cfd823579c9fb50d12c24678079527c	1	0	\\x000000010000000000800003eadde606ee5bb1fe235c6926c01b34d7061d0b779c9f0702296bbf5013b0253658b53fc02772bd8c73c733e5bb4538dd3c361f99c5d0fdb5c06e28f837360077ecb1906920d6de3ef53cb3c54956b46b591e1241877c6d71866ca84c2c55233f41d3dd643938de8fbc6a6d8c8e02aa99fe700c707d2dce4d3552fb0aab738037010001	\\x72139e9ef66f55ef462f3df401441314b5f64b918493748283df32d18df0764554f12764c75e055a42a3c6aa3138cdc26b3e836a01747871b321d436097c7f07	1667556464000000	1668161264000000	1731233264000000	1825841264000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
7	\\x1390f513a01813eb5a2fe75f96a289f30ded3a346a8839edaba78e157ec5d960949611864aa7a58980fcf0361d1da1072ceeafc5dd03581f3b483d16b9959e8f	1	0	\\x000000010000000000800003a18187f7e9ea051643aacef6a32a0e9f3dc8f99c0711fab53bac0b41a1bc424353007766501c52803de0b6e50143262e60d11634dd39489a4de8c9310b8380874485a658fd37618201a733602674e25a8a54ce4421548fce585fe8efc85d4902a7b5613ad159ee8e16061a78cbe9472c0473877f17f1fb6dd986ebbb04717ad9010001	\\xe4107ad630be7cfdbf4ea506d9e2b725bf4a454c3e31e321106c7f411f90cde75566ab5ca003e95131754e97a8d61eb6013d0be8f38cafa4a7cc5571e0f7a508	1660302464000000	1660907264000000	1723979264000000	1818587264000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
8	\\x13005fe1202d5cd9d4341ebda883caa760de3acd77a4cbe333bf1a8be92e6719dee95c806a8377e8143dd94277abda5e5603a9360a4a5bd7dd4483d37d775bfd	1	0	\\x000000010000000000800003af30a01cf9f1bb55104b8b86a8b332fbf248133ccf370e2801a9420d31945750144b258a955b550ff944e5695b9e02753e6d12a5c85e8550fc655142a7a93371b6659fe5e9c4be72f39060c5650026e608fc77fdf3bac16e9ec23f9ae591ca45b43030a91bfa69fafaf8a99542e528517a55c20237e0a72cf013270e8b2c1943010001	\\x24e93dc8f3012a64eaf9f9cdbd5f37a2e6e6eca8e729ec3d6db1739acf0f2edc3f7354fc214d0013094629f9f633afadd7a4e75e864cf0f248516ee735998f0f	1652443964000000	1653048764000000	1716120764000000	1810728764000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
9	\\x1464708e7c8b11c98757cf101b7842ef5b73b8d86b07176d3df535a8dda21a8b97353d28037826367b88ba6d07f608abbbbb1520c4c0c5bc1069c43108669972	1	0	\\x000000010000000000800003f550b66b7c9f1b39c95ba3724296eb2b9500040ea87c16af5efabba254c9b2b6b8b2676d5b51316c894da916a41927635af3bc0c1c80cd9b551ffbafdfd2a352676194b79e4bb6eee7313e3b52425c453e22e186f9577039171e7f5389c9573eddb7d68d9bce034be4591d128cd02bd53c2f886bcc2b4454bcf75a39f4bc1eab010001	\\x1f2e53c1f5f3548f2e62790133da687228f1e6d6edb14c5a8bab38ae7d072917509fd52a7780636bd32fd25c2c929f5e69b02a5da2802c1f45cfc70e5d425b00	1677228464000000	1677833264000000	1740905264000000	1835513264000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
10	\\x17f8bb04c01f4967530139bf4e6b9e2f65cee6fe4832b8adf7e237c03ba0310d8267a0a9c1800db74d3331a05e6a137bd071544f25438077a4017cb0c9ea3956	1	0	\\x000000010000000000800003ab21f14115c4691e6f35a1e16e2834637abe333709c4211d5c2f57cc234016d44ed5abb6fb4610f388bd2e6f7cb2155545dfdc660184fb50732a98d97904a90476058c67931287fb81e180a1eaed8bb20e1b6dc971bc91eb1e63255ac56f079debfb6eacc2a95a5bcaf110003fa3dacca04d4c83f3e3de5b8edd8990afe1eae5010001	\\x5ec0e04c1cd9839aba830dd67a7769dea8b95e19b159c028e7c1976dab38b5589df2ac19a4fdf4c120396c4dd2840530a05653b624758b06cfd089210dfa7e09	1659697964000000	1660302764000000	1723374764000000	1817982764000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
11	\\x1de8b35cf402f15d1424beb89e524242c0df1f73a80dc286b9a73b012d57f251ccdc9195deab0d4d24e9be62867fa4f7e8517ad125ee50811bb8a46c042b287e	1	0	\\x0000000100000000008000039a4bb7ba0265f1e089d53458fc6a07d702d5bad64f41170ea2ad0a216db7521d7e44322dff1205f306d8165634b0ce5a8e78bad08146ca49e1419a4fbd24e60bf280ef8edd921d7c779d75725da134e20c527ce93b40442ded1508d88ea950a1fa4ec86e8742629a20eb5ccda033a465601353eac32392c9bd87bbaca99135d9010001	\\x8bf30f7bb64c04bb10899b1c611d0709dd2e4e5b912d60b12fe35bd927e0b51ecd41eb5e315efe09712410cce6ad5cea6285a151e26d130336fc160029b33702	1663929464000000	1664534264000000	1727606264000000	1822214264000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
12	\\x1dbc6545966546a255230e4e757c3958671dcd9e86e8858164791924cbb7a60c2ae944948b557f2139e1bbf22244c5846cef615aaa3118432b25cb23e9caa05a	1	0	\\x000000010000000000800003c6980bc9341921ea756ece846d544f46148d74a5e8d9b79014c6538614a23b662ac0640a12e8163dcd6e4c9956629c93b463e4a20378580b0e72dd3da0adb57a432f9653cba6df3b5934d45a3bfee6d4a5040f1eae549d037cdf4fa59f37e2e136c73b9913a30a24fc8862becd88b20aa094b033f52e7e4e810154a6c445b047010001	\\xfcb6643b336cef931350010dd441e1e299345fb27eae993068167720ae221a891f61f06ba2c2365726f95a15538c11ee26274d171560a24a87ff875ddafadf02	1659093464000000	1659698264000000	1722770264000000	1817378264000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
13	\\x1dc07faac6df0a469898fc2541d646f541aae584b1ee15241bc2aa188ab1edb9b41c7365f7ed4f539ccd9defcc8ca8b2a8ee096eafafa0eb79f125db6e3deb2d	1	0	\\x000000010000000000800003b371dc805bd6899c4f9874312ab38ab9e09dd312fd0103745cf2cec063e0315bebee2ea2ddcfd6b211e92a976b8e0a2da0f7068564b757aedce7606844ea2629642c28c2a590f1641204fd01e8c142d66a6ec80b12025a36aed9e77b691cc889976a622fdcdedf8b06ee3aed7cd98bc4b2fa34ec46c5ffaa8772501ec24eae07010001	\\xae165b3cd6b98a75c250508c9710b5b075aa0c934bc83c5cb0bbfb2ca7a612e15ba784d00d2d9362d7a01efa1e96e6b7c4868dab79a5e402bbdcbdb7142ba000	1665138464000000	1665743264000000	1728815264000000	1823423264000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
14	\\x1de46b2082b67d79b575fa16fa096288adc5a33849baed1b92edad56269413acd747a2d1274c971fd098580aa0ab670820cb32c6c845747d7beeb9100031235f	1	0	\\x000000010000000000800003ba5381ae98bb0b24ec5ebc6014b341d202ca408276de8fea2b04dff0b572211c4b051f16728250fae07bb65449d4b9bf28e9a391e9a4039adcb6a8f7212e3dd352dc838d57c0fecafbaa8e5d9725c280a7e959ed9aa88fe806ca6114f59ff148cc0eda10b7114c71d8ab96b0a096921fe746706e76f0f37231c6b7c31831dbd1010001	\\x5b9b0416e37c8fe189f904ec3e44f69993ea25937d00ae712613a005add3a70c786433a746df76bf5079e9f5eeeeaa43afc53e3842007666ce1fd6456ad3ec0b	1656675464000000	1657280264000000	1720352264000000	1814960264000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
15	\\x1eb8494f282cd4390b6042669a71a3304abd673ce1f0aabe2c4e696ba9845937d327961a9db430368bb21dbf4be428eb6538eff4aafe7d88f55fa3463026fcf1	1	0	\\x000000010000000000800003c3d1cdbc888e2e99cf6b29184a4d5b4ae60a3b0a94f469cd2a7c790ecaa1116e3b13309caa73234c75943cfaa773b6d49726ecefee2a190081d9f658dcf8ea4550c78289483c44355b9ba0609b16910221d78a3ee77f2a97e41d8293232b74c5c9e7d15593793f9fe82fd8c97d27de467f40bed3ab162f216e5ee42a0286aa1f010001	\\xb58076e70ad1c8d5f16f58897749ee51d25bb8e96fe37567fa191186371c20d086e118058911dd51f8bb27c3175e0b5c180e1b655936554c0e42ac0bde04f407	1672996964000000	1673601764000000	1736673764000000	1831281764000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
16	\\x22801bd219f651675595f560e732619875f03cd67e70efbd404bcdad68a44bffd0b84d07c703cb9a19a3fe4b4a2666e52070caaa9c4f507fa89b1e757573d0ef	1	0	\\x000000010000000000800003b25f68d0e793694f898096d1a9309489b08187b58ee5f4ecf8b1d51bf8fa1d5b7cad62f03853f89e7a6d2d732acbdce5b1d11193e60f48da22b52c6ace382c3e345ab214934acc3d97a7aa350948c6f095bb9de4940c3a08ffdf8fd5262c55242e5d7310d7294bc3ea55f39965cb9626ae714a275b5775d880ee771144ae136f010001	\\x171c5e390da2e90afeebf98d92be2aa48a2a984e8b66beef06d0b9176301bc145de11223bcb16db6eeeacf1e1e222f4ae32da291690a20be65e260be9e352f00	1671183464000000	1671788264000000	1734860264000000	1829468264000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
17	\\x2304846e83476bdf0fa4655f72b88adf89d92a2c65430c527565c986b1a208ca17befbb0dc91e5fdad31b9d28c84a94186e7ba5d6818b2704992b8af628aa87c	1	0	\\x00000001000000000080000394a160dbaa06246b9e3ebbd5195bab0d40eee7d6d13c065939a7194fc356c20bfc48b4051b9cfb215f11f2d847c628d3a4157ace029b9ec4bdcbc688f1917ec009b1533ae0d753c42b377493d5ae64d30e4c7158a6d36985e0cac1a22369a9f686cb61a80a29ec0596b5fded8355aea9a5bf312695fa514d4bee905a9e7a9dab010001	\\x5b90ddca4af37ccc971197ac865a2a1d8e64f913ef64d9fa766f2765313035b78c9947fabf8a541c2115907a0bc8c67595a58996bd63361f6e391c5c38495802	1648212464000000	1648817264000000	1711889264000000	1806497264000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
18	\\x2660a70b9a901e256125e77a690ece850f0b18b2b4829c6b4d6010c021510fd685bd831bf5efc23b7dee19c3857c8c823606cef108cd8eec019e66c216aec447	1	0	\\x000000010000000000800003e57e6653f724701943808ce9e60225ab2d1fe2f7f07269aab392bd344c8ed648e862877235c708cd36b4842d7a446d9074ffafd453734d75de1d62b4df3a3894000c3966f5dff9ce1d9bdec4c734c0cd9306db33ed21424eef14a86eb81d8de702c73811d0996edfa0295de9cbea5da8476e0a0fd41c6d20e2e05becfbbd7831010001	\\x76eaec5f2964ecfe62a7f336e0b7fb96f460140dde910cb55945e34fbd1287910b1387b666ca3d741ade1a7c662ff4d45e17f8a32bbb6280efc412ac7a93aa05	1666951964000000	1667556764000000	1730628764000000	1825236764000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
19	\\x26b4678864a87a764ba201c06c60b841fb9960594c91d6d2a23632c14f2751123069b26f9dee1b9c0da624fe6558565db081550eea955e7435df9e6691eebadb	1	0	\\x000000010000000000800003ac8b1f366417b96eead3b11ee2281ec7f5602b7fbc279e715b0f84b97c1b1a0071d4a9fc0491cf3d09e55ede3704b4c0019b6733286a1dbdb10135557edf2bc23a6b8d0bee616e8ff61978a193e50e0884c37f0eb487d066558f58c803333a9b9f0e74e709b4ecaef0c750c95889d3c34d16bdf61077b7fbf83a578aad0f8caf010001	\\x35e0d5cd11f953e9a4a8168736891a2c48d59b37aa46c367b05a2580621612204ce18f904b320b006c46167b63689948d23637a6df0297ff737a8853051fc408	1657279964000000	1657884764000000	1720956764000000	1815564764000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
20	\\x27288384165c78a0b6ce2c14d05f1ddd20d5d9e2c865dc6dd5aadfbfbc70f6acfddb324cf6ed55e97a498a7b68f6754237dcf3bbd1ff80d03938cf51d19ef365	1	0	\\x000000010000000000800003c8cc3144c08d8e3ec346afe9c6b33ea593fea0f3b7104b5f71772cbe57606e4caa2913fdb17b9e03a17a8836017f97d39e29e695a51c5ae9564c99584ae03073cd6a150651cb28d95d084aa9d431af4056bae2c0e21422703dcfe37e7833d73ebee188af317caa7f9da73182d7400f223cb8d0b8149a55b5733b23a157125525010001	\\xd4560aa5425bdc57d487861e11da9837eedc96527a6c3ea1b51fd6e81b36a3d0025cd2b5a9a9e2cd3473fabc664864597e0fa3b7084dd84822493b78ab87270c	1665742964000000	1666347764000000	1729419764000000	1824027764000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
21	\\x282493be990bfddba6c1d22d123adf4984ff6cbcf21248dfa22bd29dab67705e80a2b63c524a53b679148f432c156536383152504119bc4d14770eb7353c2476	1	0	\\x000000010000000000800003aa8c407a44039a70e913ed7588c00b7274fbfaea41b96d07dfc61ff38355aa56bb1144f69f5dd59ff89afbba6649ce9dedd914b91dd6fd0eeeecee71a66e884662c19ade6921ac7bf42240d3bb87e48543b894b6f32bae4d499d24c4e74ff7ab223e70cd6c1598fd59c849a3a809e67ed1ab9210f52273fa03fa158bd505f087010001	\\xc740ceb30504ad55dc9a6db39b9ad6125df48c4c28aac54449d8f3879a270817d8404463b9bece422ae68336a6c9eb8771a371579b7f7d566ef5274ecc9d1a04	1651839464000000	1652444264000000	1715516264000000	1810124264000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
22	\\x2b003f48b962050d36898e87d063cba34df27b58eadf7e6187a011ec0d3e81bc4100d66c441de202ff1e0b1c43ada965ec3442d4be7f94c5c68cdb40bd950c07	1	0	\\x000000010000000000800003a87ec517052c6c6ce1ecc466fd1bcec8da0576ce80e8014611387031059d145d2f36d8dc5b377171ed65da4f1c818b58e56eede802135d5d583b9dd3f5fd4ddf0fc4d2db51f65554517a7eb302b8026d0e7e618f3a0fdd9f1b20247f1d104c544854c94bc7e69455e886e8ddc254753ddfff24dd18b34123b72db20739fc51ad010001	\\x31dad39518d7c0c1a528e5a8bd775fd8e980a268cb2b80e0048a40c978e9e46659b161d44b41fb1823f10c1c2dd8848eb36ddfbde09768fd0f2ee11a4a2c400f	1668765464000000	1669370264000000	1732442264000000	1827050264000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
23	\\x2b00c3db94cdb25673534a3663e134294754d5b6b162e1f15ba7cccc78d5aeba1d8d52d197639009ae59f16eb3cb90efb8f4afdd655f263a23c7b1b3d5b97fde	1	0	\\x000000010000000000800003a1ec542105a1817287dc46c444b833d11f0852461e2ecf28018d7571697399fdcc7c708fb012a50186d3999eaaaed65a210376876081b7c677aff507980d81d67ab6dfb1deabc97c7bcf1ff62052ce911c15b5513c9684b5913c098f9a3589a90adb7c6f1a576ce73227de496fbad2a027672edcf99ef9bc32852f0a770e88e5010001	\\x3669ae2b32e97c27f19b3aa49e5e1f2910f975c1990a0436d402d559a9353ae005f09b0009928ccb51a6f625a9a327556df041bd507080bfa94bf03a427b5a08	1659697964000000	1660302764000000	1723374764000000	1817982764000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
24	\\x2df828c40e5530ff778ff362ae0cb26466c1543e6bb582e87a43da7767efd5b073c69741f54ced4d4b0a04eeebda2da11d056767a884bcc17b98dab5c1a3d776	1	0	\\x000000010000000000800003aea6029e73c98554ecb9d11dbdd3a00aeb101ad13868c66c39895e752fe21cce8caf1b1bd17acee3dc1bd834178ae3a4d8192e3f09ea9365552532d753d2970973fd39d7865b898d526a9ace200d9bec986bdc6cd9cffa4464b12942310f12de87e22c10f3c4e574fba8b74f504d0c51bf9e9fd739bb3c89cfe333247a44b9b5010001	\\x3f8b99671e34675ada624aa3adfd7b58adcaa3154e19fa446da6c846e440da27487200384435d7f27a6057457bab9be168c4a52b003e044fd4dc3ff2e151eb05	1662115964000000	1662720764000000	1725792764000000	1820400764000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
25	\\x2f78c141339805c5cf43f633bedcdcb0d324e1592578c8d1dc08f3ef9e5ba7a636b925d4ea8f857033bce521da109a65d0a5147329e4c19dc77e4ba0404a34ac	1	0	\\x000000010000000000800003d750376f5533cb225dbcab48a917831376002e02cf2dbbde8be7235e57eb56b5971953b6cf046ae84eb12611451e5705824e33a3bde9354ead73dfe71db5a5b20027ce8fd159b2d4ca3aba093562f4061c47babd6e1dbcd2e9092b5af25abbf21eb345a153ca13f80f723093a34f59f893801e0cc7c742dfa3c9395d05c8bd11010001	\\x86e6db9a4a3c5a67f5ff870be91fe3e98dd5ea56e3a1c55bb03dd6fd64cdcb4d7c574c2dd87225259fba09f9e31528477b523883346e6f1df96e3f5429541007	1679041964000000	1679646764000000	1742718764000000	1837326764000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
26	\\x3090c8acbea307320e09fa6a55cd351e44bb4e31ee78de39850d463d660af5668022961b09c8e7f1eb5c3c7323ab972f3d7d926a448b6b797777dd98ba11c823	1	0	\\x000000010000000000800003a159a8222f003decd7504f641aab0d93eafcb5efd575545103eeccc6893e609c5629bf3009c364079e06da5a3d319c63e204b974c7217aeb0b36134f10375cb8b7374e7601419ec401970d62e2559712199246b368ab8adb19991646301067fdbc3662e7e9f9ec7949946e0225deb571b7eae327ae5d8e4d973d6cc394f5909b010001	\\x54404400c8143a058cccc148778fab2e605e539b2faa36061204172f76739e1e4bb733f52f76638c4387f17d5c9d7fdb547b74c7b33a2af489a67cbc9ad48706	1658488964000000	1659093764000000	1722165764000000	1816773764000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
27	\\x3360029c9c2d07bb5202894a055e8faac36d4de6bd4012e4122fff98328997a0410ecc9cec54591c30177a7fe37f56fcca539dcb412ffcfa2f82a78f84971cd7	1	0	\\x000000010000000000800003deac2fe41724411d696ce2681c63970e2d61ff60dc934aa73c9421300509fbf71c7a4d89cff74f4e54a019529ea21c15b3cf973b7f4d13b883c78ac239604dc2e7a4b6037ac0ed8dbdbffe8be3d3d6612fa39d96ef060f12ebe0603f82c80f55514c00f326aa499324f8e7740b32c1c5dfa6767a35d5d7efe94d597b489da1c9010001	\\x37b2c517e788bb357e525183bb1beed8b7ad6efdfb8664afda77d28907abb6e2240fd973039aa9a63fa80289e323a0b5143cf5adf99486476bcba5b50a45120d	1660906964000000	1661511764000000	1724583764000000	1819191764000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
28	\\x34a432fb70c54e7babdf9bcc4e5340c98d14786cb199d1f4da622f8e53f2e61ec5952cd0cfaf510d556c481ce97ffae626e81a549238c412fdf8b90bda69b430	1	0	\\x000000010000000000800003f57164726d66e2de5cd436dbb0540a4a846eee81c2f56ddfc3b691d55c0575389ad045fe6dd924f0121d30d43cf69d588fb2935fa53f35b552119e4d95ae3a1819d3377aa46b073d1d69c24f109f1685c1664ba2f8e1f362eac38fe4c77c9c5094967ff2075b1592f7c85bbbcfb30e522a960e842f48c4f672a53e54ff719ef5010001	\\xd5ec1f9e6012c9a821b4d062040371b8e25a654fd620c2d5a6e1dedef14292a06fb9935ab790d3ae7cd7d83241d9f4b4cb96b6447974f66c6e93ab216ae50805	1668160964000000	1668765764000000	1731837764000000	1826445764000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
29	\\x37e4ae3514a76e72cf7522a8f8ba086f7b447766de5f97cd63886336388f234419016bac3e1c17b841d794a2aaa1c9a1c98d0e734257688d1fd98cb814e9de50	1	0	\\x000000010000000000800003affd728a65326b00dd60f15b4b57e8ef8e976a0a9c4c377d6d3a831b0b88782e97ce323fb0ee806de8025006cfe2fa4e41fa09f79911d7d4374af9f37f272481a51eb04fe46469c3d70ea0f95bb20bf6c9354363a6663409be9f299b6a4c49064e18932620b14f10c089cb1dec6c64d2dd3ab7d1c8faa6026d150f38c7a9de37010001	\\xe7ae8777253df9b2e4f10d6f36c68a5feadf74370fec1a1516ae5aacf69094488632e30e4b3a32d61a296f69c165d5eabc1b8803e091479c0d3ef78ab3a0b506	1676623964000000	1677228764000000	1740300764000000	1834908764000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
30	\\x39489acaae7e24d6c6551faed4eeda3dc244822ea6a8ba4b048e2d7ee54d438e66ce09c34cdea5542bc0d08c77562a7e8158fe6c46417bd2693fcef873c1c9ac	1	0	\\x000000010000000000800003f7a29df0cc6a0c65b5091527d8b32c293d2221e93385c37cb3baec86fb3b57dc7d200c38651584381c02eb59b0a10eb9a80ce51be9257778c6311f9fea5ed120b94ed12848b7ebb9b3f38afad52f5cccadda295ec78b755c6fa3fda13b279eff5de88e5d7db53d78f99163b8c03811da344b2e6a45e9c696980be4c628b4f25f010001	\\xe4b4cebfe8f746f5ddaf83be7c03c437ee2df968451a48bf93f7701e90c937a7285cd69f31adce0631cbfe2722e78a3f5e81cbf3b85a7d9be815550ca9b81808	1657279964000000	1657884764000000	1720956764000000	1815564764000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
31	\\x45bc42b269ef7628742ea3ec893b576782a074915fdae55404fa9baf8b87d16aa68b30de9a9bafbf0d466a86bb8bbee37d93c55d4c0ed5edba3d54c75fb0d380	1	0	\\x000000010000000000800003c0544affc6565be5edda63f16168f73cfb4ab444f4a959aff71f14395c83d44d46e302dbd63af44062c9f8d0a79ff41e793838880caa2e69cf72305730b9805c1e90e48195fc399cd73f512fa2307e12b1bc9642109ae300e37fa3975159ee30abec63fa41342e70fe13917a15ba69ad120a98db378029c741e5fa69192cb135010001	\\xfcdb25e709c92d7f74b775e3ff12d19377ad1572de0a43a3729459365865f97cc6b71788707036ecace5ea24502bf333ae1d02413fdd21f655e41c345047380b	1668160964000000	1668765764000000	1731837764000000	1826445764000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
32	\\x49d44da1d871a9a5dcb4a83c0a41d3daf48c7e6bb8d2848535de07f21feb7a79beb7407eb7d382985bded5d8f92423d837e435cbe7b4fbc9be7a6b48dea9becd	1	0	\\x000000010000000000800003cde5b4333623a3d99a750454b96a6a696364ae3eaa6103fe9e286f970008164ff9e5ff3b3cab5d165f56cee6bc44ba3d83e115f889cb7cc24488a9dfcddb3016ee344c2cd2ed38c7148cd26803de8b3ac930025f505467eafba95d3589bd3054dfb0c22f13c0c2aed806059c261d49a4ed9e269938a69874ac7cdd9e352c8a3d010001	\\x99c492adb8cc2fb96732e34239f7bb953f600445abb41c34eebd051a314c0c5e5e296ddf5d98c725dbcdfc26edd70a19df0e30d39babc358e857256e908fab01	1658488964000000	1659093764000000	1722165764000000	1816773764000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
33	\\x4a44683fe779d439d51afa8e5e28bc808ab175e0cb9650f86fcbbe4a422be6531d9c9fb549ac0d1cd822331e6b119d2ac3d904a69d5cc487a168270e0239e759	1	0	\\x000000010000000000800003f6f2e2a01149b8346d249129705876384545590087aa3d650651ca68e77989752d373b00ae649290d2e337dfe53fe61e8a6528ef336eb2c4d660c6c14adcb66beec43849fcc0ba77dd3b47cbe8db618b3a6b056470809f6a3b3971c62e86276f1523c9c0e299b7c0ca48ec4485d93df29734a33d43ee3792802edcc84189eecd010001	\\x59f92399918fdc1bccde67a0f9847d38485892ebd2d429de4120dbc5120dbfcba282db22369db22ff82b854551e0259f6e9c9d2dfb89a4638f69dcf734cfad08	1654257464000000	1654862264000000	1717934264000000	1812542264000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
34	\\x53a43e52757c3a1b01be3fb83b09df46b4ba63f4b04149e40bcf1e5f1ec3ba9f0e4017f8d9cf92cc7a58f9bd810eaf086934796071ff96b2415fb9646d257f24	1	0	\\x000000010000000000800003d5c56abf7f0b2b9cad7c1596be99855099aeb78a23ae18275b8ef04c0de5fa0e348acb056bd9b0d1cf5ce08b8fe0b2b3b92c3f51a7b67f91f1fe8a070c6efdaf248b212b33c71c0f6a56c0b4b8bd8576598d42b5d64cc48ad39a4c85353db701e352dfcc464b3d2d761d4165900a4a97fb9a6bb3f41a7fd60ae8dfbe71a823e5010001	\\x37fa17084acad28c8404c695d2160843b370fbc6f6f58f39edc9c1b125998d258486d5077c624950d013d359a25b9f1771d5cac3a8beb44bc898c1794327ea07	1659093464000000	1659698264000000	1722770264000000	1817378264000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
35	\\x54e840e39ab665c72a9a9e05d757a613bafd87c32a4699636b7b8f5fac2652e318bca29cffec06113e5523ec16df2986926d5ea6eae88606abef9c20a2912966	1	0	\\x000000010000000000800003b6e001464ceef3801d16b1a6e035afab26c76b7fc130f5bbc757f329d892573f34655bdda6864bf3a171c019d3e641e3b1efc5d949616100bf8dc17194ae448611860112a87326df66c8e102a1cf95c4d87ef391744e931f1373f770de89708566286fd650fcfda686fd69798f2c08f9ad3e627212fb012cc3270300bf3d6669010001	\\xf91830a71a3f63f86b6dc14c5819cab13dfc6412d293873582ecf6eb764099c7d3eb736159d909bce82148ab71cec7d8e01bdf34389075c613fcb36d0f630b03	1660302464000000	1660907264000000	1723979264000000	1818587264000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
36	\\x553cb566a092b59b3b90605d4598d660d22c04db49dcc3fd1e602451d7def3e5dc58d9e5f142ea8d9ee5138ae6681bcdf443318c441b5c03414bdfeb9e7e1a61	1	0	\\x000000010000000000800003b46033925483a03a6558594738ede7a0beb79538174e0674cbf85f021e4dca5ba8fa98f51c269e17a73dde2ece52a26332aa62c1a8b5ea413ddac85468ee2e6048beded4cbd32098084ea3d540c9e4faf5cd059a2d553c7de87b30fc03e193bb9b5bcf03cdfd584f20927f29c9fd10bd22e0441958dfed7b455f8bc93a4bf49d010001	\\x0ec319c742a3650f52ab0fc229da356513e44bf442213c205d75142b3b000d75f1b2a42c061e01e230afb59c2dadc9b6b5df4e3991b1efa19248566f9fa0d906	1655466464000000	1656071264000000	1719143264000000	1813751264000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
37	\\x5538f66ebb4b124bb9e8a0cfa9a11a8cbe8a49b6fba9e883c795ec9d891835700c7648c8973f0dd2e2ed529e4a4e25622f7275281cd1620e6e7aa7ed4b2a912c	1	0	\\x000000010000000000800003d241beb182f09720efe49536cc4c33e3ba9b00f2b54e2dabb44fc4b18c83407468ba8f5e1fc93d0965ec3e0e807d05f1a1123e4ae5bbc9ce41743323c55f69a846ead5b29772378646c5ee7fa7f41dd33e43ea2f9b7107835c9d5dcee82b7f6342ca8565269358a1e033377ed4986581357cab36461154fea0c13c107a107eff010001	\\x2cdd43d7899a032b104ffb027c05b56458bd34d9574a043437ab72eebe3920dbb9f20207f383f5e4ad44a756701b37c979dd6c287361aa784d5bcd1fad6eee0b	1660302464000000	1660907264000000	1723979264000000	1818587264000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
38	\\x5c5c88ae35f32b7927f9f18224f1fe106424bd6e0cf6a576011a43f14a2c4b09ad087b763e3f11597714206c8c639a8ca2b9ccfc6ebe71ebf69fcfcf2140ed1c	1	0	\\x000000010000000000800003c9418bf6af41ddd83fdbce7110f067c23cfc71bce3c5bce0d389e74adcd5caaa30ef473ccb4739423ebf8cbd2654d5ca63852b2249c1b79aec72c7210f5279de93007303d5cca24c916f9e6a7727f0375ce2daed261f57bedde2e1a99e82fc48a83fe1bfa253fe483d80cd6b57121efe3fba0540731be6ca3346c66ffbe049fd010001	\\x10b534257d631792efc19add40b3694be5eb75c337f6330b0fd6f9dceacf870fd3c34b736626f4f968c64dca264abe812757e5d48f21f139de9fea4742aee304	1668160964000000	1668765764000000	1731837764000000	1826445764000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
39	\\x60d8d4fbd5015ee5974121b2d45f285fcff8243c7ed39f39ca93b9262ce43ada80e4f8684ff83757d20f3b217792c991e01418ba11d64b33dd462d4546695763	1	0	\\x000000010000000000800003bae0f45137c92e6f19ae11d6bcfb6801ffce8daafb1464205bf370d9a713337b550636451f5af9436e769e8c8f34a9adfeebe1c731f055c505d189cb3ea29417e787d90fa281c8d4f6962c82a7ecbc2505d3a0d737097439bb4274b8b6e9152db44aef1f64a38a9f8fab9d73feb3c69fc5ecac9e2ea4cb461e40812bb50154a5010001	\\x40e83579665697776e0c50291cb4b0d87cd1b7d113a1f59d8983ca08068da5251808b248163100f3a243b146a0eff5fa527dcf0a59d566276810dc7baf180709	1656675464000000	1657280264000000	1720352264000000	1814960264000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
40	\\x6158c3a14c0b359222f5069bc9910114aea82a815ceb9bd7fd36b9639738572f3a3d6356b67900041f000f9eb1503b68b254f4bb0c87ee25eda39ff4739eeda0	1	0	\\x000000010000000000800003c4491a4d6f511dbd93a649743760121eac011fd9d846b2c06caf801096bf0fb904d0da384996b99b28e1012c9eda466b34def11db48ece324c2696ab9da5ff3957d1d17a07aca9a83f3d463672b2f3c15a938fccc9bac8d728fd113c6d58dce78f1079bff68bf55841fafd73d8364449751ebcbf8926ab19cae260fd85234437010001	\\x24ea734bbf2ce84933054f5054d88b24da552a47f606744b94e96421192550094e4194e0d36e90f2db6d0cc8aeb9c336dd423fcb8217c6e2c431df18ff94ba08	1665138464000000	1665743264000000	1728815264000000	1823423264000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
41	\\x63648bf53be02363ad3668796e7856de2cb8a815aae0f50e3e204f6ec9da7c9136a75eefd6696e62164da87da319d3306d2ee1a14f9325f78d0dd9aa69b190b0	1	0	\\x000000010000000000800003cc294fceadf17cb10e06553f42144da1a771b27d0818f78dac244c0c6a373adb7f960771cf0c88a46e411e1923194bc8b331592fec3946582c333feee1b671baf0fb5da16bdb522d42f10da926ff2a82761dd26cfc8e9decea7b8967d9dab3fdc42782fab085bf6832b6304ce2d7229585c26aef0a584c1282d0d9e92cdb16d7010001	\\xe33d391db2c33ee37a3aac5e164470ce1a64a62a63159bbb5b6df0ce71852df11b4aa168ee8ee2462011f51a960a9395bdcc12e1b4c8a3172086e89ef1b7c707	1669369964000000	1669974764000000	1733046764000000	1827654764000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
42	\\x63a43f76811926841ba6f5dfaa4a07ebb4bfd0c723671a89dc354e17ec1520e10b086520fcf96b6dae2c9059b0faac4f61c1a741df6a1c9e9a5403c32364c4a0	1	0	\\x000000010000000000800003aaebeabf0f737e643d4c2bd4197a1f33bc2d47dea4bf33e10adc3d7052aca4a88cc9f4972811b860113167c51cfed2161212a010416fb116aea9e2340abf0517b17ca71e43edaca093996e588e71349c933191915d7f3266a200764e414fcbb1e4e4cdf14af3f699896a10cf2d01972025c4d501369c0c075d209b0e72deece5010001	\\x7208a67b344168ae5b9d92152be054101ea053574335eab421a40fd569ea4a9a5724e38dd258c8a34e493c78e1e1ef265db8097e5d3d4dd1f7bf0311e4391c00	1661511464000000	1662116264000000	1725188264000000	1819796264000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
43	\\x6840802dea3720fde6978fe8ec429cfe8d92085150d18e136e2d31703c31e74df4e44d03802d764119220c89a6988b085fcc577622ed7df106134d54536c5500	1	0	\\x000000010000000000800003f24d4434061f983e6ed8a043e25b86c4492126a6c758b92014cabc6ce580b0c1ac8d89c08e9f6e5ba194f0bed18af7a5014a013e7eed65df1498afeae86decb807ab1d196f5fbdefc148bc3eff58c555ba724ba4cc1e899baa1c779bae27c9a2d8657bbd2bd8740f37e6856624f39a14bc8aa08022a12a8dd289ddbad287a855010001	\\x96f91484a8b5fe434149ff581b1a10fcd9bf420add3e04f277fc5a3ba81e80601057a4a97e6146437caf0c9585ecc5d05ffc49c0297847d20a631827e4b8cb06	1662115964000000	1662720764000000	1725792764000000	1820400764000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
44	\\x6990abf122e795c23e03079a81ff342e054322c84914d9c4f15c3e66d6f9b885533feb95a1b6290183d011b56c0c9710c66f7add598f999654a36d76bdd6c2db	1	0	\\x000000010000000000800003d8a802e39c40ff3489b6c3f96422f08ef874ab11c02ab4a2b705dc16596b997fe79a95f1ffc97a651af5001bffd4c969b09ead16dabbfd30ca3e0910c9e215cc0d1adcb247ccddef6e525b7a4430764b2cf21f2a91f869e0aa8b2f569a5e35fbec99d390b53c8f8e1e50dfe8ffe2338874f50cdf6f260e8da3bf13040c81e6a3010001	\\xa7f31f0301826bbb4750df6c531b5ec7963797745ccaebbc8ccaa60baaa286931b27c92499a678ce8d846ade30ad72250da0863e0c9a07645b1f79a06b22620d	1661511464000000	1662116264000000	1725188264000000	1819796264000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
45	\\x6a5c493f5700992b4a04da3af4cd961a5c57b4c2797f4e67838c1f294d02c7dc54926c89456aecac66476b4b6b1886a22509ea8d8b91d50512663332cca6568c	1	0	\\x000000010000000000800003c6f2e09eca5a4b67cefcddb19bb5a2a63b69c2c78212eee86988065a8bf00f4367b16a450c0d63c4aa3b49a4154f4f2f9bbd59a0cda3e017a1ff1d6cab3d7b94f8a3c5584a4ca589feacac1143b9a7746a985ea6906fb713b6ab9119b10d8463f55a0e34842d7a8fa9cf4c924ead6d443f16e725665bec6993c4eee3f6268197010001	\\xac0e7c8ef80b165c47c62dcbafde4f0c3bd6a64d1768d6f38e6e7ab63c5e7be0f98ae39607be049b25b60843ca99a65735281df45b70f93d59600c8604972505	1662115964000000	1662720764000000	1725792764000000	1820400764000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
46	\\x6cd866de0e9e1aee3531ceda4a3eeb7afe02a998b606385706ad931df5f0ef1c50812c8a807edd85810a34f38d811e36933b12c28f6bddc31de6c97d9fd387e7	1	0	\\x000000010000000000800003a67e4f7af1673f2afdf3731ef0c6bb3033747a1f172b2f8a7facd71eb48f5829e8d127ca21570ace5c6bd7eb8de9278031a13418122195493495a29b0c80a1df17212ccccad99bd11ba716bc9b8dddf2a7674c7a3e6f72a9a9a981498e39d1b55b27e168c732e4d60642b6849949d2c9cd8b2a4a22cc04a505cc0a76f0fc11b9010001	\\xd245f3dbfaa4eb2f806e6c83edf39d7af565d386f4657d11169591cdb353194522e7b966d1813d9de7f0d064fac90f036b7877c74f297178bc38eb87dce8300a	1671787964000000	1672392764000000	1735464764000000	1830072764000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
47	\\x7208941443e6db4c06d3bb515b182cf94d30a2dadd3605987ec16b9b0a39261df4514b18f8f170b6df5f9e34a19b6c377a7ec443e11b9348f83909b39117345a	1	0	\\x000000010000000000800003da9392f75b302ce6a867e5f85a102db1f9dffbf6101a850efb5e3bf49b7fe063580222876b96deefab161549edd71e6518f75c3b67bd1449a0ea2ee73f6e064ff155ead3b7de44291d06ace9f3e2e7af57a684babb681e6a24474905e080ed472089e39981e8a2d2589c6ecf19ccd9901b4842d405298bb7ce5c928c3877ddd3010001	\\x4d7a50e8add2e9b0a6c2b83b919dbfe25e5d26fe1c1ee89e3bac1079807bb6065777b5234f11f74a685568d8b1b33e6ce18b1d9fbdb607ceaee3098104f3b903	1663324964000000	1663929764000000	1727001764000000	1821609764000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
48	\\x72a46c9c004f61efe9e42f61cb1bc4d5bbf91db4aebc3bea0d523bbc528d4d917ea9218ffa6811a7f56a98944a615fe5749dfc017d27e04f8b78076782a5d1d6	1	0	\\x000000010000000000800003e15679ac590e2a4580ed1b3e8bf0060d4c0aae7d960e91d7678af278019a4fda6d0b874b4d674f5e6d6b070ea995e3af926a96b80fe1d26863357e8b00335614a54208eebd5b3ba1d71e2402ffa8fc457dfcd8432ea732482e53b764aa4fd0ffc56816926e94711b3a1aac8621ea6d2a8acdeadd94c151cc9fb7490f49c8d201010001	\\x1b578ed5c67941c727f9ebd7254877e0104022d6ae2b0590677147d80bf420d28badd7f135c1cbcddd3f0a5f55462c73becfc184c806540708cc541acde6c200	1657884464000000	1658489264000000	1721561264000000	1816169264000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
49	\\x74b8133b9b124402c840d854e33628ed0092af7c24529a1a44cd70f479a24e91f97e0b313c2ecf284946396969d32237074cd2f2a90fbbd88d3770d2be0b23b3	1	0	\\x000000010000000000800003c49bd00cf6d2ffc11423a2d60aef8c2f134be65dcccce5684ed01c719a8c593b62bb17a43bee0fabcc3c6642bf0e2c03657648276f665b039efa94b3ad995261f88f45e8f3ddc1928ea93db8c3aafcf3717794190e1468b05eb564cda43794959273a3bcb97818ea5815a6e18b7ad501d67f6e7e0cea2f05529b2408096338c9010001	\\x4375b35c62b2b4455e0a8d6f804742cabd8409e304671db4c33799cf28411eda025cd54a3291526b51a69f3a8d0c2f374dc93673292fa24c7c94ba4729c51c0c	1665138464000000	1665743264000000	1728815264000000	1823423264000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
50	\\x760c22aad0e059d86be302ace38d47280ad5ef04cebac632d47eb757f13c11fb52bf78e0cbf80a5f2a814929bd6917ab96bd4a8aea4aef3c3638ba78c0951bd7	1	0	\\x000000010000000000800003caf268c37677c3c19cd92e016eda80a3928a38cc69c858254b2b5de91939d0894fea86225fb29b92280984cd96cf7dce1ecc02c32fccd13108c80d6bdce133d85fd1c3eb1f2e8fced729cffb00b1b521576421d2247a5cd8038caec95dd4510487386e5424db7d776b0e62beca3e82e6fbc1da19d9316d1954343a4220c50717010001	\\x614384ae3f3cc214ac8152c0d49ac6ec8154fa126529c44f9fbbb0eb717cebba2ac84c0e7c46ce81baf1f2a5cf1f8b93196e01af25435581a9ed8deb05b6eb04	1663929464000000	1664534264000000	1727606264000000	1822214264000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
51	\\x76a0b7e1fd2e2c1884f948e8148e93e897988d8dc631773e01db432b01e01ecdcf8cad0d6e35ef04d8aa4d342fe07b0cdb78ff89775ebd35e70b14e21b968592	1	0	\\x000000010000000000800003d134709637dc4a920749f28d7a73d24184ded2ee016c3ed9534c4770eb229169606dbf6eb87da3ff142370358e1401d39284707915ef197edd7ada31f8e1540327d96ef5954da2ecda413a3581fd384bd80ecd79d64c150f71792c6c2c11d43b4920bbb8f6b1bb8ed04290c58bb4e3674f937f1c56be9f624307598f895cf6f7010001	\\xcc080a0d50338367ebdb95ceeecbbc68345e51cb2fd2a500be520c35a95358e217e71bdde8498d21723fef8c7d16263ed0c8a9e2eb898a4fbf8df1f60348a905	1653048464000000	1653653264000000	1716725264000000	1811333264000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
52	\\x7704562f3643352a2d7cc07f11fb25219684d3afa0b7425f4b54ea06ac45c108af787f78b78578bb5376e6e3df3e994c8fc089c007c6bba6b50d78bf3dc4652c	1	0	\\x000000010000000000800003b198c5ad3a39e40bc334ec80315086eadb6dfce909567c127123d50157d7a7c49f8680a8d8b39cd63cb7f32bf18015c5b7ff1828c354e8a26f63addf591898bd3e57f2c6d9fd7d7196c08eb99777ecfdf590888e8037d73632f43276c390807fd6f9973090e46097997a0923f1b010a48fa85d9b48e15eeec50b475cd5a2e2e7010001	\\x878cc9b32f02bbcbd2d9c96f5bde49984585da063d74634a6c3ad31b3b2c3b80ef573f1d85d894e7fe9fd2fea5ede6ab5b388e684517ea9f4bbe853b59000a05	1651234964000000	1651839764000000	1714911764000000	1809519764000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
53	\\x7adcf75009c5595de080fd4f24207a7706927780c8c02cd227f3e67015284483be1dae7c1cb111e66dce83e6a50427ae8a1d06e9ded1c1c5c3ddb5e3a9e8e80a	1	0	\\x000000010000000000800003e9c0dbb7e686ecd9991a2762ea5e6234fb72c618b3e11826bcd555230b95fc5c43f53198c7b9fb136f79e441cf80132a79b244fd7c8dc1bf803e1a43f3119ed8d21014aff9dc21a40c9262a2ef9138a9f96fd762ea68d0b73145d64fc4d0d29bcf29618ab00ebcf9225243dc5ca47bdec23d128968deeeafd6e7facec83cb9cf010001	\\x5a76ebba56b065c11486e4d815d5c93a80a657429ca725676287e1f9ff1ad6fe47fe9b3c1f4764ec1e35b6cba023afc98937d5c093fd7c9fe2a4c256fa1ab806	1662720464000000	1663325264000000	1726397264000000	1821005264000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
54	\\x7e8c9c90e6868273431ac5b74b7961fa45114df4e74ec8d422df8fc5caf683ab5d250ec5e4562aa6b28a76364c2ff8487bb0a6a904009d47e3fe5d8a250f927b	1	0	\\x000000010000000000800003b3f36d6bcd54d673241f4dfe2dc72a357d157657b1c8a621c1fac3fac7e6bb32ec8fce81764dffb3f3a3acafc674e0f9715bbb43be208d28ba4556ae59d900f78c9f7b470d0ff8bc957a8f727b6d6a57ec077d9a5430e7bc953ee70b37e02be80b793417409105f0aca35dd8b9c0a24376f4828ceca3e4fb63f69bfceed069b3010001	\\xf16d3c198b4b73abcb24d326ceda7d993e3d9c0eb86084b91c5f0c63ee0c6f4d2e635b3f0688c8a4c56b6bf810a6d6f735d194dd69467ff179ea71215bcd8b03	1667556464000000	1668161264000000	1731233264000000	1825841264000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
55	\\x825c291eb48f56044843a3b181a5027628384680d151fb28c37bb561eff658c96fc88125c05bda06e69741c7829e602a3ea1bac6ae4dc616abb67d84db4d75ca	1	0	\\x000000010000000000800003a56960a6059c91a43fd9d19695ad6efd3f22200be022db4afe7797a220cba384d37f8b8a9bf7aaf4c181fbf94fa08103a7bc1d2c03014860279b902b71927ae52861569198ce6f5e65e5fd8c7987638bd2acfe799e73de51e2e7a6aef9b22b21f07be88878b0cf416d4f61944954704fea840b58c70b2e67ce1c0121a90d6eb7010001	\\xa7ef8e27808208ccbea54c172feaa0697b7120db9fc5d1ceb3668b2c70a061a88142cc29ab39f2fb392025222c69afebf40b24a3433079b63f224673a619b00a	1654257464000000	1654862264000000	1717934264000000	1812542264000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
56	\\x83f0c8fe4d2784fc096e5a5e3480675ac8e277a415fc9ec53b56e9bdde9fe48e853b31ccebc48bf49f6dbf78898796f5787e6f50d30082d0657aee0f0c12e71a	1	0	\\x000000010000000000800003aa88ae8064f242d14f3003e72cb7bbc76b8a026e6b5cdce387f3f49c0bcc57f0f4f746d2f58fff7a32d22a3fac68ce95d7aa6013fc05e932851348f39024667ddda6469c4ccf546caa5e165755308a2d3b122a4f02117c14c961708f078a3b182fdcb9bb223defac2b73724079022d7426bda38a63c7b4078c82864ea113b2c1010001	\\x8fcd90bd0d9a702f6444d8faf3650d236750acd6ed7e63ff19d9b7eb361f824b676323b98529e0b315810c942517ce49706a1c82ef854c425c79aa4d5758b904	1669974464000000	1670579264000000	1733651264000000	1828259264000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
57	\\x87c4d0275ba8f40ea11b5215db8b7f7421f6bb0215c3a4d5f0eda9a96f3a570a422ded08fd261769d3d2933ab53a7eb329b26cc09168632b185136839e442568	1	0	\\x000000010000000000800003a8c3d2df2859b808268c15eacd11ce63b748949d720250945ac38cb5d1ad17ff73072165ef37df5f8f4d7ac71adc33d11bdcf8121d56092b623b166cbe6a13ebf4497d752d4424d47ff4d5e9591aa10c7120b884457c482e655a95b3dbd2ed693a69d067c41fe09d7bd55678abe7f28d1cc4e85f2ab6e1b1eba86263f1a0d787010001	\\xb1ff364de192e45e7175adfe3c48bb7fe8151dbfb6f51e8b5c9466dd6531bfd00999606a661fdd5e23e63df5a33e248ccdcd81419c55cdd4c5ad1607e51fd200	1674205964000000	1674810764000000	1737882764000000	1832490764000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
58	\\x89203f0d24368cfaff7e0f31d753d15e21a0931b3ef5ad59c96b532408fa8ff581e44ab35ceb8781fa7b72d5b9aeae4574834bcd7ab95fd1c6c8df13e33a8f3f	1	0	\\x000000010000000000800003f0e2891c9c1700fb62cd140daa8d89d388149872d425c7dd298dc884e99074bad98a27ad24905a264bd64e1a57911e5dbd253be9ea4d6b3e26bbc4b7285b49117596a7c219cd8a2d87a916c8e0e14358e951333c0ce0b70dc828fb7db08f11108233af31dd40d5061e923c677f9661e2f3ebdb8a8f8bb7c7a82fcd351a518f65010001	\\xb0e23d501bfb837cdd6405e7c3171407e031c6922205c251e3dbd908adea426f41c5f1fac5d373b654322bbd58e58726a15163b96bd524b22684788ba4e5390d	1674205964000000	1674810764000000	1737882764000000	1832490764000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
59	\\x89409f7ce81d988d3483a4f3132d38b2a6a3f0749b04eef93cdbd02ca94d038e7d41431af73376174c41d902c58e82251358572b9030efe214fbe857b49786dd	1	0	\\x000000010000000000800003da8bfbfd81e601a04e617633b95941c1b8decb318b8d132fe220ecfba93c4f1e569717886d722ca04bca6da0f1cf35dc684cf9ef7bc939ed634c030ccee27c3898073f32fae3526fe338eb2ca9092910e31d7ced5a3fc55f03ca06457a2d71fe67557415083e609d7a954afd5dd8d49b95ae6297b28ad6497e79aa4397597ea5010001	\\x275635ba808d764bae1e3578ffaf10be93562c9d083b54db7eb3e365f76c50c0631e3a7633e49cf27b70baeac868d49e774ce82176e04388dd433adc49d75309	1666347464000000	1666952264000000	1730024264000000	1824632264000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
60	\\x8b90fe8551eec57c5bb1952e7f0dfb6e6363a7c165055c0172cbcb5f4faba258a03b647432ea850cbd4fec103aa2e146b9e058c0708843202ea4c46da377ecf3	1	0	\\x000000010000000000800003b0c97528c1cb4df652a7b4a213475a8720b2873e661f2641986e691fc651c3d2ed646c5f707f3d25538e4ecb2a2349d0039d5db550c040b4142accb9228a5fcb9c7abdaac8c682d6f11d6c87fc5d5749f055e8bb42e29b24ccc6e4e59d6e53e4945fccad862aed70a3fd10cab5335b84f165b9e8389383fe24ed171eae06b9b9010001	\\x7392cc526231de4ed0a1075d1c1e05e6ac1f3fca0ce52930dfbb9406350b09fef7a1a49b27369ef13adadb1782d45340f3f457dfc859c6e19524e323c480e203	1650025964000000	1650630764000000	1713702764000000	1808310764000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
61	\\x8ebc98032014738e23696919fdf48b5c490260b6da223582c7dd675280072df9677fcaced018a784d0e93680629713c922b9e84a80ed76182883b0fb81ef0980	1	0	\\x000000010000000000800003d50c3477ba77ee018871cbff62fb0f94bf31940cb47499ff8eabe88e367099460a6cc6ffbb648d777027986e3cd400f233d09586affc7d8c22f542d0a0a5e12838719ad7e7d32a3a6c1f592b3589b6c2843d9e67b9e3faee80e83164c2271a75b365f51a58778e42b446c358188f8727824435bc2df162bc20ab16fa6bb287a3010001	\\x199d5b907b9d31a271fe8c0bef05c8ac91692c90d630882ebe770ce56f30c006ce9d3874a5c091e5e606d659b7c7b1ce347c900f4e12ac9aaed088ca20079504	1672996964000000	1673601764000000	1736673764000000	1831281764000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
62	\\x8ffcf43c8a5208acfb24b6d8a3dd499778cd9f5ac8827f6603be35ee4e8753542c2c59487d2f9e6c92a9cf9fd3d40b3cc6a0904cca8ebf21ef13826f4c837350	1	0	\\x000000010000000000800003bd4327c84b6eaa97ba17c7faf187563357936bd11d6b31bdaf3949774f49b37a22f9b3e24343c2dd35984a0c79b80914921d6eaf5b0eb806894c7576856c55e33ce8915874710e94d3ea62b721e4fe623370bc3e2dc910d6cd6b748f0bb301be56661348ccfc31094c6541dbe958ba896af3f0bf6ba7328290156fa02011c0d5010001	\\x7691600625f635175896b5d6f1ae399390a95c63e3ab86b83db95695aef56f6f2a8aa1028bf6a98104b9facfb9f53f167f1a3d117babd4bc15f25283595ae400	1657884464000000	1658489264000000	1721561264000000	1816169264000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
63	\\x8fe8be079e942d9db7c553296bb3e4e97f7bdee580b4dcbc751a04402af623f562870e50d992e28bfb3bd2b4e61928193327d2a72f4233df5f0cf751b2699767	1	0	\\x00000001000000000080000395e192b217c0b00178550f7f0a9413566078ba09627753d8cd7f721ae349de68c4dab7b7153429e2ecec3d7e4fff7bf4a98a8860d2026a04a9426259fb1544040541efc8ac2716d637bf23be2afaba26b7067ca3b2eb4ccb2c273c63f5eceabf569302f431ac1db3033696c103fc4ff466d7a98c121d9487396a9b9cd320c845010001	\\xd17e3a598fea00bec5a2ef562e937e45e7455c155a129fe9c010c5da9035c16eaee2616743306d7256de4cbf1ae08405d2cf39f7df21d3353a51d2aa6c35e40d	1675414964000000	1676019764000000	1739091764000000	1833699764000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
64	\\x902884d48b1a88c1398db3b7af062f5ebef8270503e6bdf50a2fbb1aa0ef11c509dfb44047e97074ee198c19cce7df4b786da841d37173b0358a99b87c6d121d	1	0	\\x000000010000000000800003b1411981113ef9e6cf5b08e199ba5abe3e4efa8a924a5d4a720a139251d9c8a1a0cfefa425123bf97d5f9d532bdbfde807aa9009d96ff4e1e135d12ef80358138da4f3a362ab7686a6b9aa07a8b7397c2ff900cc2a4bdcead15791e38fca55f0fcc93f26bf2ddfe7ca7c372f9cae2da6e216826cf32af63e4d72b4c63e4afba7010001	\\x969dfef5fb01166a68e699c4f01d69e78e690e0cd096024f21cde4193b21ace36c39511f2d8bad10622a5210f56110d5c288ed924be6c47687fd46ce80b46a04	1653652964000000	1654257764000000	1717329764000000	1811937764000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
65	\\x9114b052c608938f15ab89ecbb0ac53dc3cd581a7fde10d305813125f345a2525ee9bb1ce586a29de7a6cc282c3f11d1277d813ec35cabbb0cc34a181b62a5ba	1	0	\\x000000010000000000800003be6acbafd183bb4dbd2555830490d7356cf4543b8cd1022c08bfa0a8c430da66d6b2d9d2ae006ba63e23afe4d0aa912e621a46a0aad5f372a79948af161751ab81bcec58ab3c3c3db2dd7e60b569b7fe1100a750ca3bd8d6a1fd5aa30605c77b5ff9050598cb8e685a1238e59de0f89f55ffd044dabc199329e30649a9cd5385010001	\\xea9bb55ae686f9c6b00017682afa0a6d021636e5299a4ec3b8019fcada0a0e27ba10976c837372997034cb28136afb014ae72b3e4a16cd3e5ac1c3cb2920b508	1676623964000000	1677228764000000	1740300764000000	1834908764000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
66	\\x9550996fe6183ba0600c077009275a60bb340d02ebde1cd7a0b250c0cc746ccf26a96585b651c40b2c2570a18e2f7f79517fa0287115bc8064c5daefecd0a411	1	0	\\x000000010000000000800003b16808e3b49b52c7bd4ca66e4822ce452fe80aa0fff9f73ba4b74397a666c179251aa6d8fd89da2c08cc584bb41f6c35d84eb0db1f253fc3c00ecedcf7d7ee33bb1234a96810e0dc7b3f39d8257040f4542cefbe78d5249423f8b2fecd19919cf7288837a4d585b004e12dfaae046c4052ed751a0d0da088f94310da89ed3a15010001	\\x6e5820519e970ce6b3179da2d9d6479745706030fd464ebb2aed68b19c59a93d85d41e054c4f1bb28f3e1b278fa66317868d272c9437aac1101df369e499d50a	1648212464000000	1648817264000000	1711889264000000	1806497264000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
67	\\x9710bfdacb54dd85009b31683b6c3a29c7c41646562d6a3e5173c3415c7c225bf20593c9d16205d7797c1c2fbd89d2b5f06df138d94dc89cc50e2139029dae18	1	0	\\x000000010000000000800003b62a6ef4a5695aee03278793eca491a9ed1b600d27aea2fdd374bf0e243516bd00ebd5b0944d7a4a42247e595569551c01894320fc88d9b8c7aeba74efa5439be7367213feba169690412a61e2fdac3de1e8d4c67d46099ec4c271f64078fd07045c73a9ec4c17915ba8f470a585adca8ea5acf50751adf256206dcaa1111ef5010001	\\x4af1ca48b60d104f5fd994367127a050b8b28bb7435ed600969babf58234474db77cdd5aa6610aaa8aa8b5fb31b2ec5fdcf6634be33fd2cecc74292d094be506	1676623964000000	1677228764000000	1740300764000000	1834908764000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
68	\\x99d8dcd4051901b654aa412ba95b5fd49c389986517dc9781e5cd7011db4ca8c50a11e5c73575c5af93a1cde49a90af0f3cc2305b7d901033a853b7784de8f14	1	0	\\x000000010000000000800003ace9abb8cf05ee43f6ea67bde5ab6272035ba95904b90cc6d2c8b4f1125a8edaf3f4b513358fcd1bbd64eb765fb32e4464fa02e0cb8a49f64af95b10921d15e1f0434801f94259837cb4dfb76602937734e9374b43eb72757810ac8e08d37061baf49ff120f2b747a1ecd3646d76548a3cee45befba62182cbeab4d9aa478563010001	\\x7808a55395c8d5264c9137a07a288d0b1b5fb8aba2e5033ed733d14fd6a292bb350341b93e5dab82fff17c9b4de6b890d676f63efdf6931304d0716912cd6308	1660906964000000	1661511764000000	1724583764000000	1819191764000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
69	\\x9914ffd2809939f0712f7451f8be5bb365844bd4b2ce767347819103a67350e8843788f705cccae499bc1ba068a5efa6261e27f0ab50fcaeefc1c287cac72d7b	1	0	\\x000000010000000000800003ed1627360cbe7749afcba013a16b654e33eb2e5dc455afff9ec6b6069e39d1b8610426d94f5b60292dcf13c3b13e664c620e07255f8656f53daeaa56815957ead70171fd19d8359c41a930e28864ef4eb185c60f3a4fb3d0e95f050bca743271a15b5381a263c6478bd1937c0b416b9afe675b2d51afeb6174ff7cc9e1afdedb010001	\\x860ebd503b40e39465601bd5dc9d2fd163ba7bfb7edb87979bff4711dae26f9b418a60686a4e47f2145f9882e431eb2a5a8ce29aa123c51f0b123fb028a01c01	1655466464000000	1656071264000000	1719143264000000	1813751264000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
70	\\x9b08c4fdea6fc755500f0e769ffa22902e6940846e79c916ebbfc836823503519b4497c9dad18ad4cc4cddef61cb053a85272be9fa080c54f67189d91dc8e2e7	1	0	\\x000000010000000000800003b7422fd2e8b08f8434247914e394e98c0999318787f95727204ddca0857ca552e8670615e2f0b5653deda07d7a246674b7d2e2c6f89597bf87398be710b95d3324599600c8e73bd1d7f46fe14da691bc7f784a532139e19fa18ac356f5a2c963c5acc8246beca6f711d854f9fd80837905cd166e244a489fde13de1e3fe08311010001	\\xc3b77f8b9d94153b19350126fcadafa8dd75c8fd326b223c5ee9ebe10b7bb514ab7efb52588978d403ccad178a2dbee09fed13730d424ad10de85fc9534cf808	1671183464000000	1671788264000000	1734860264000000	1829468264000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
71	\\x9da0198eb1e484d1125c461822d4d0453ae94f5d38de973605e140f840b22da725c063b6c6484dcacae813f60af31ac504ce2853632dd76065b8d5e3d2ad7084	1	0	\\x000000010000000000800003ce0bbe9fa7df1be4e70ae2caa6bffbdc6fca8cf9a29d69b43ca452ce74ddc8668107e82081832d64ac1c2594bb76ac713103aa518fb977f49af9228b0c32c5f783b89b524d6c51fe0a421f3224c9a0ed7071bc933f6d24b15ec07c8be64be2cc5168f90631e4ecd2804b89784e52086d960cf6819261b0f13758859c572b5271010001	\\x5b2bc55dbe70ec0972115691c12ff65f88e12096761c21cf776ffd61113648aa8690b8d7aec259762d43bec95556d91e43486c9062622714ef800d9ffbca1108	1651839464000000	1652444264000000	1715516264000000	1810124264000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
72	\\x9d4ccc587c7117262846d6509bc28f5e9297f84e4fbdcc5f4942aa79cc4e66d595ca2fdb5a675f79a7886849ecfbfb3966205c9532c10e75b6534022306844b8	1	0	\\x000000010000000000800003ebe128d884043dbcb64569bd6560c9db365a9bb03a795760184db3b29af62097938bdcc257b981d17e308756ae3227dd6da37d59159b258ecedc33651b9ff04411a4f4f551995795433f363aa476a51b321784dd560f47fd6ddbac172bfcfc233d7d79c9e47050b08b5c8cc3a68d4651eebaa56a444921ee0193bcf728c3ddeb010001	\\xed2197758c5774350550f4fea1fa266b3b28b5bba924960a530aa103b805b3f3e6ea2239da414dc5d7d13d15bc4c0c7b5959eca0cac607c9dd6bcc6f64386f0c	1674205964000000	1674810764000000	1737882764000000	1832490764000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
73	\\xa0b41f6c307fc0a4895101aea95ea7f0ca424452342de346b71afe1a1666c91bf66919aa6cacf40d589098fdef37c5474305a3643a3049174f42c72c35bd3a76	1	0	\\x000000010000000000800003bdd2d38d9a67a89c6262668e321b4877ff8d34c4edaf4aaee1d6e5e46a52dc2b44cd9f09fd549e04578362290ce413f4c35d891acfc92820ff3e93f6ae43d7cca51b7bba1679bb32e9336360e4dbd7af61ea7a6cd48d32a01159585d432effdbac9b562607e23f688364a965708dadc716d50016030f7a564260f446cb24f259010001	\\xc7a9311a9fd5371391f4c4ea217b592944e03172987b23c9936e08ec36a2b6085369450927e9c716985399c5c1fd0ae273cf470c3cfcaf961ee771c0ded1c70f	1650630464000000	1651235264000000	1714307264000000	1808915264000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
74	\\xa03088af1217582b28d55cc45d8778be12eb017e8a696723f4af6e4a468d405c688ade2d8f50d29a4e6662e874ee04123284c41581d26c931ab515cad02f66fe	1	0	\\x000000010000000000800003b92d76cda4071bbeef92f61e935bed029013de7b8baa34d5d85f3e1c6f614a8d721ce0f7bc5be6c2f51c8c9baf1f0acc96d8cbadf3b00bf56efb0055e6408de9b5ebf4497a8b294e70ac1399fc784723e0fc55f6b3892fa97d66fac666d199ef2633771809dcc59b93e317b384e28b4660a3d12f9b845cc3b6e1917af457c43d010001	\\xdb7dd17f5b9d1aadba7f12e7a00648adf4fdfd967a94a9255943079c11a7760c614e4b3a4197c8758925674c82606d299e847cdacb52e103b0d679505133c209	1673601464000000	1674206264000000	1737278264000000	1831886264000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
75	\\xa7107a7952e82a228803bc91035fe73291a397f828f5afd8b4cab7884ca0f89ab434fa32e19869d9db883e0e5de5d98f854b01781e4c5d99c65aeba9c3c15bf2	1	0	\\x000000010000000000800003c93b8e887e456e60555de1e08e65b8b6238b1a761ecd00f251cfeb56324b6789eff476832bb2d559f398d892d79b1962a32e9d1be24b095c229dc58b06ec4a961184e74d510a9c4263071c9c23dfc4e2f15f45abad6d8798459c6252f5383ccded456c911c94ab9772d185662b7d2cb8b7e3f1c77b6a3ae895d153e4437e2aef010001	\\xff93f2aa48fbeef0736969c2303943ad109bfc1beb78753000e2909d2c5ba70be3ef22ce4d735a0a50c8ae5943a507d201d51abbb07d2d2712b7306d688e120d	1654257464000000	1654862264000000	1717934264000000	1812542264000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
76	\\xa8f0fec4933509aa5b1c29a5dec1e4f0b4a2bca27a8501992f9daa884c3a46a8922a60dff7f4c24ed1b4efa7598541f5dcfb5b4578742713c7b3f4dde4c82e99	1	0	\\x000000010000000000800003a86cb99092f582b4c3b5c55a7b30a48ceac9937f9de043a22c4f60b683dcf6f51869f773cbe10e5eebb13b41f4b5a3a89d3da9b98a2b5a624a505e28b818512790ea9d1f45ce2710953ab7783f8591b421cfdb456bc8dd85b84282737f15084cbe62766fd3bc55017a198848f878b6b8a4930d9a314505d546fe77f45c71ac6b010001	\\x6fad88540058137bc6a95fb394076e67bc5061453db1c7dc204f9bbdeeb15e9d7b986e07b38180b40cc20a3a550593f754d8bcdc90e1d3928e4fb9efed13d300	1661511464000000	1662116264000000	1725188264000000	1819796264000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
77	\\xad70f3fb4c82c26890de188644d04216fc75b93761b5eb89850e1958ec7f0be3e02f554373f95b80564a0755b8916cc06389ef45a204f5ef2dc17c902a89c9c8	1	0	\\x000000010000000000800003b9dd203116ae69218dd363325fd3f9e9f276d4d736c420d728b4e599ed01a34a08f97ac6ce76faa40ba4cde64f617ecd5abc70241caeab39559cb19416fc798dd6ed8d4e5976f9fb7036bf59a191a22a0ec9fc3a5f80c22a8827dc8ff73bc8544f7178b99caef16e5041dd016eaf55cedc6cf6316b079970f60a47bb39ecc2e5010001	\\x79cbbeb89c3f65e8ae41b4c9ba14e8206576e78e5bdf7203675a5c8bc996bdf7c3a58b0065df5d6d91d7a9dc060f668e95e6b718c1de275cda7a754a619fa103	1677228464000000	1677833264000000	1740905264000000	1835513264000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
78	\\xade4f9af4f6f983dc50c43ae5f14c292193377d93dbfb81ab7de9646088da25fa94b177c7c2e300c30621d16821cab2ddbdbacd981bd3d2132116829f31bd9b9	1	0	\\x000000010000000000800003dd5a26b918fd53b1137ce1c2cec7c9918b7dcd3f016bae7f4fcdb8528086b15f90b519ae9352e2f5bae952c92bebe5dd83c96a9eb601b9e28fd00c25f12641b9f19d68b3a911133d4482648481ac3ffb1fa84193d6ced3cdb6072b2cbdd7bc64d001b9d723044670fa63d55c619a56ebf0077e8fa7948935712a862422ac4949010001	\\x0516c59044cd5a0b4afc6c1389ebd72d44cdf5e0e14a804c7877554ecfee3bf2156e4e4deb83922ecc7a7561966c3d58ea2b04ffec9919079efba5afdc41ea0b	1650630464000000	1651235264000000	1714307264000000	1808915264000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
79	\\xb9d007027524994fb43e3a527c8016882470c6dd5f0745f554d919023664b207c17afcdf52e4d64cb965b2bcfde4322dd4e44b42296bcd48c06744939f1cae2e	1	0	\\x000000010000000000800003cb81e6313f4623d0004e1c54e9534f202fbd66e4f2815f59412d9aba89da4b7116773c4c6277399adbdababd701feee5b851967f45174605f777b10d0c25cfe215e452a8e9d63bfdb8542d26d4093b918644741d8b6b36cf3e3430a6b4ec8ef907d660d63bdee8b20d06ddf3fd8d35d88aef7aa16b3f8f960b56e602cf30b605010001	\\xe72ac572fd91218df01ca2023586c52dcf03bce032d91d93d277f1d2b66f0b8f5f2d780a94e96895d2985f1776ad9246a1ab722a834ef541b1d87e6d1eae860c	1650025964000000	1650630764000000	1713702764000000	1808310764000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
80	\\xbd68d6982cfa311b110930938aaf73944d254ee559d515fd34e9311d635ed0e48ed27a10941c6d93dc18323b0eca4e250a0dc0e3aa1e38f8924e5b9642b012b7	1	0	\\x000000010000000000800003a9e2cb8fd326a51d2af88d471fcdbe2a1838b39e4e23b1e04ea0f955185bd6d76788793c52925332f65244d2e7f87ccb34ffbe568a37f3df939d99edb03edc8e3b207d05eb5b483cd9d3cc3b9cd1e907ec70f5ce211fdb16ffbf9e0a4480b65101729acc7253b0140de35298bbf2d7e328861343d6b02da2d69b834a284523f9010001	\\x64ce8f0010ae06a57d1b23121e8ab8087e3955e19f2c56f8ce350c2ffb404000fb077f8bd63eb8cf32fb36a5c546bfbd5e3d61961822c1513dc421b6f2cc5e0a	1669369964000000	1669974764000000	1733046764000000	1827654764000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
81	\\xc1bc52a5d934656cb10cf58f4964e155d064d73619dbec71558c71cf51e075663a3af75aef8bd49089f345ad7a9b103e8f6616bf936344b46382bd2a2fbc6481	1	0	\\x000000010000000000800003ac1b562b2efbb521f52e4eb7b71fa57762b70bb057c3f8ed50df20b26446f075527cd869516c70a9c92e4d05cd3a1741bdf983b6376f8cabbe94116b082580fca0140a5b88cee852c16cc1ba6ddd2ace23aa5eeceab5819f1c3c7ae41a25c5c3f53a0f1e99948b8361b793f61acfea17b6f24b7dc539a4dacc2b950b97d93fc3010001	\\x12306f82179ec9f49f000ce1f79e9ea39c09dd3d0fb8f286718d3c786941436b94a2617c0ab279daddfffe10d540fa5d0630bd00f9e80110c46a6972c7812206	1663324964000000	1663929764000000	1727001764000000	1821609764000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
82	\\xc1a80163e93d4c4200c0ee73269479706b7c068e1cb142eb77f1a67f0ef60563ef8707994756cca5eacc5946c7a42acb41cc4573d169b85fecbf8cdf86c78fa5	1	0	\\x000000010000000000800003aeb371175b499c3fe538f67497d90ceeb6658b276ed4434d6dae9fe1cf5e3c8c2c704e23ab753677abeeedd50e737528a026e3746b3829d3394c957f659d004c6fe645e5b045f03d2f9dee19fdcb05dc5fa93d679241600eddccd5c6152b3a4d63f641f63b514b9ef1fe4e22e5a1a0bc75148ad235748ec22b229b63b2aabb37010001	\\xe990b60eafa99b649a1f694a31cc8289fa8149f2452d93387bf2f4ac12ba57114bffa0a160d5656a4b50ea089f6377780294acdcf593da43652a1e30531a3405	1650630464000000	1651235264000000	1714307264000000	1808915264000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
83	\\xc394e1bf4ad28e3f9ba5007c35fc8e314d53fefed44b9520de251b03ac3c8dc32f4dc623bb49596db25be0f3184c94d631e3e4996668ee75dea88737b06dfa30	1	0	\\x000000010000000000800003ba98b767ce9e5e4a208d8bf81b50158f6650dc36905414f9b4ae12c46a2c24e7d234741d6b09e81a6c1043c6efe16291088effd1262b66ec12e9670f6036f59d9c2a5a6c8571f808355c0fe9dd6438caae3af176fd84e7a7d35696d9d3f95b8cc9fe5f6e7cf124557befbd739ea494ecf24733eac2f1db240b15e16b7baf9237010001	\\xa57a9a11a6e5a8fe121673a7b3109be7ce9cfd13667fa499c47cb781dc55062e4c31317d0c7a540e0654848095134e4b6ba440bee1d7f3d0a50a7cb22a5f6808	1675414964000000	1676019764000000	1739091764000000	1833699764000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
84	\\xc6f0ce5c3fc68ea3555f4e4a7403a86de368f1cb99288a82198fe7333c9883ba53284c1028778d898c5dc69e9870e6cc13e957be7cc066aa61c47b93ff288de7	1	0	\\x000000010000000000800003b0d0a7a454f5a9a11f7cd9d96ef3084a5dbe5520076e52dfcae09a53caf84b840b37fc7c6de83daeae18a570ea7baded3caac82962f0cd5c49f10c9996e67e1cc37abe410e901d68037a554403a609adadda42bd981225bb559931b1b13d2959ae1d4f305ee7a38d295bffe61e4a605fc3363dc8cb2d26dac1a71005b13981cd010001	\\x92afa9103dae97d93a32609b4953366668cb4cec67f588f47d7f43b566a0bfdf91af9c05fe319133d6b6c7a09ffa0450bda6e360623b46d6b4366da1c69d7102	1663929464000000	1664534264000000	1727606264000000	1822214264000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
85	\\xc89856bff09287cadc32656f791943d6591ddee4c2d20a7380c8b43a37b390bd612060b8c13ff7e73511d36d0a37fd9d4b7dc7a957f3db9afec4306917298ac9	1	0	\\x000000010000000000800003d418c425fb643054fd55fadc45bfe9809a8542c6a85a93fc29c9c025f82b8baa9013a452bb2349717f020e566f38219a01955f9d43df36ca6439cb9c44a7a6599f176b663ea09839ed42dbdba5366d2b1ccc7458d22e81db90c97eda862af8569844bc4d55e2e91e07b43706736ba1d5d494851258fa91a26c1712a9050f6b91010001	\\x2d0fe0d6a10c29f22082b080b9a998b0452f90174014dea92d0887d915d45bd661189c46563a7d62d4ca98cc94ae9794af9f5cc89216515ad4f7eb684bcd8f00	1668765464000000	1669370264000000	1732442264000000	1827050264000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
86	\\xcaf8e3f47f9b7888e57403a8046cb03f349a9af09d7305fae0c1121687b72beea0b3f3e5651eb016c6983d4de069c052d7dc04ef443ed6e126363c62a9201e4e	1	0	\\x000000010000000000800003e74c3814501a52cad2703f76434bf05a3eb827eb96a1471e8925b1bae0e8e42c31483a3f24a643d07c5c65f8634c7dbab2fed353901b5606840a59fd5033623711c39dab0de25d54852345fb013c4e17538e7957bfacc3d4a9b7594ec5e0eae8fa53087a4719fa908fa62b11c5d80c3fd5204ce389b54adc33d4d8c6d1f22181010001	\\xfbabfe5b60e0539ab48881db64a4d24e33ea1c145810d1b79733d70acc504308956e8a2f2be525af7050327a13eed583655687aeab190f3c135a8437e22a080b	1663929464000000	1664534264000000	1727606264000000	1822214264000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
87	\\xcd3cfbc8a532e6a3820b5a3e6af70a5b0fa00a9d58e37f5cce1d08f0b6edbc97fe3d2d3adf24aa103d57e3b8f091d142911f3c2cf06e9e66376f1adfc81e9f40	1	0	\\x000000010000000000800003d86b1881d96d0e225ddc0a5ec18f082ab7aeadc21e1e3a051702f0c6f5520464a29dfb07065586708b08ca8b959d08019a24e38fbd7a4a90ed2494a9b9f4e86b0861943ff0ad246be53ced9f9ddc539b07a5cb65deb39e8114edaa5bf487bd17ab383851b86397ff55151ff2f4f77c516d8fd597436ced636f8f8d9c4ccfe2eb010001	\\xfe6241633bd62037b6ddefb44f3a9c995f778afe02cbdc3095b64fcbf2196b6e3c623ac5a2df09687f271ac8d0034c8732c99e8d659d987b16185ab0d3535904	1649421464000000	1650026264000000	1713098264000000	1807706264000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
88	\\xce7cb61989f624bd28d573572ec9cd47ac3c4e2cef0de79472f5189efd6cd837395a9a71f889d0f59c89b761ef81f46577a959ca18e0c7e8ed0b041edd82fa3d	1	0	\\x000000010000000000800003b3da8cd6cc69a2772bbc87e994d5adaaadf02e622d2ee1039ad5912482c9df46cc29b440eefdb0fb3ba6501d64b68ecb7bcc24f7cdc9bdf467c2afd94566bae924c560bfce903cc76740edba5fe558a19316a1a522f409782671fd9ced62f84bf840e7c034d9a403b11f3b827b2b77306020fdec5ceadc836e9d1745cfa8d595010001	\\xabec609148fe636268a4133cac578cd7c4e462399e8c2170fde910b938308409ea1b2d1684a4d05644e971d768ef0a4c68ce6c0dfec094def4cbdb65925a3b08	1664533964000000	1665138764000000	1728210764000000	1822818764000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
89	\\xcff04a111b7285ca079aa7fa469218125935fcd3e41ee07ec9df09110624149a382aca690c423ba55b6a6524eef0561b3c0ea6789b9db22f30a121045e03dac9	1	0	\\x000000010000000000800003dfb6d6b391e988c3dcef8a20a8faf52cc081f8e066efec2f4f8ddb1a8927375a37551e572ada9e5d7b64c734707b741ba37f4f836e0f267fe6c9198282a64c6cbf798ac93bb0858aa149aa695f5b1837d59faafa5f90a34ed4ca1f77f7a50fdcc24c6a840118d9183fef4e8e8ca969d2646a30e47d97076c47966fafe48a1099010001	\\xa81c4785b1e3298733705c99e4ec5a0c36e13f5ee14c17dece86b682efa4c7b1d42bbe2416f9c0834e3aedda15cbcee74d419cfde29c96da27944740030da702	1660302464000000	1660907264000000	1723979264000000	1818587264000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
90	\\xd1d891c96b03f90175c5d3309de4803eff1b1c72358c7f4fcab52c974a0d80dbc3be6944efc2ee50273f77b0a75da14207faf1e059d4833c816d43eb41209ff0	1	0	\\x000000010000000000800003e444a02c08abfd98646e3cce8cb8723b878230b1c0874bcf08e07953bc7fa7832a228fe9cb377d20796705d478d4a9cae92e8a9c1648708b317759b2177110116585c92691bad18e27e9f5d3ef533ebcf294eaffb42a971ab0a43bc27aeb9bd76c5484d199bfecd6a24bc5f33f7fd2929da6ea36c00939cc55315619433f106f010001	\\xd2bc42cd3abc4b1b894269b163a935e88406255615adfed412f8538af838dbd4b27ad21af750764c85981e9dee0f134f208eac2ee4eac9124de107c9476d3200	1648212464000000	1648817264000000	1711889264000000	1806497264000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
91	\\xd34461846e89a5d3da87ef3db366909579bcd0e9ec55a12ec3102c6e05d7b92f6153409304daeabc150fd2b26304711f8558da6e2d3cf62a9badf70da587a1ef	1	0	\\x000000010000000000800003f603382c841b9e22d52651873b633f3bd1f2fc7254cd45df31cf49b7457f0c6fb858a1e229826a4c130c9e410a9da525ae82a55f098920005ead6a4529180f86eec4558ec97c5ff0c18c9606adf7e2d87dc18ff2def89258907a686358b5e84279c8c9f0dcd3dbba50870dc42dcc86708cc527f08206512cf217ef1f33e6981f010001	\\x34473a7b7e65d5d0e4a902101dd8f53b64fa31d4bdcb91ebd923cd5866fad2c9316d2f15cbbb00e502837b55f34e7d876eac66ba3613991de485417974b38209	1654861964000000	1655466764000000	1718538764000000	1813146764000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
92	\\xd768c0459ccf76e51f60ef506eaa8dbff88afaba0fc1f6d1706e2ce8aa23b80417b2d1553ff19852a746a21529e8461dd1b956197dc4787eb571a48fc135096d	1	0	\\x000000010000000000800003c04dfa2594f17f15c2db0978f043dcae8105544fcda8078fdaf0ee08de79d8898dbf983eb93be3174bb77868cfb4809b4c5c5dba0da95133e0a69a8ff4e25d3dfa241c94d26905e1fe70b48eb94427edfb4d44afd61f7baeb39f77675f11d1169aa0fdfd68b5e408c6adc28cbc9e9c5ad2732bcebfc5982841d04825fdfdf14d010001	\\x5b8ecf1a0e5cbeb5203ed0a813c953487413506ac0c69753249597820ac64803d32507970919f983f1dde105dbca5d515b1779ae7320c984f76c777d6085df0c	1674810464000000	1675415264000000	1738487264000000	1833095264000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
93	\\xd9f477b275ff379b95d8aaf6ea294d35eb3ad94322ade9ffbcea6e31075112896ab648f887c5ae75475a59ffb361cab55d237acaffd78e403dd5db7a239a2099	1	0	\\x000000010000000000800003a347af9e5c01717f65983a6153f12491ec28c12e139ff97c83728f3c607489d25c7983d1682dc52b7b7c11aa436b0a7bec38cf4b82ea831d6456ab4fa6c752bb6542a1b94e0dca569281c35427badb8f234cd002a301a33c955c38ab4d6c0ea06c0d5f7dd4c5fb29f930f1cf6333837a4b1b5652c252aad95931c0892ff7b065010001	\\x6a6d47ce6d205406abefe7e13d59e8fdcc62bf4ba0b4bce2353d6f81fe7db47a4b03a86ce23f6a7a5b8fc32507be2c9837b62401cf2af0bbaa18d9b7e9791f00	1652443964000000	1653048764000000	1716120764000000	1810728764000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
94	\\xda106ebaf7e375e9d1b07e4cf3921a5bca819c2fccf8097ce99639852b0694134762ab6d92f68644b821f78c72a9e8d9db6e6736fa5c07582ca4de01a2bcb050	1	0	\\x000000010000000000800003afe418928cf5cde7fc22dff6a91f63583ac15febacca7805d62bb722749fd38ab852c645b588df4d9ae2d3431734707fdbee0bab1f61d59eb08d943e000f02d0974ac8cb10f4569661962ed10ce732b068eef76f76b1737feaf7545c7e1b34a03122048be7bf069b67e2c30d4cf736620be207ae649693549e1b8b1b4f1eb129010001	\\x15d5c50102a05cd1443399e7e922f9f296c149f553b786460526a07cf30ec438a73ce19189035256b031d2dca694fafdefe9e7df781a980397395a8b280b8a08	1650025964000000	1650630764000000	1713702764000000	1808310764000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
95	\\xdbc09ee51d6d4d51943059e45fb657136babdc554c0480621d19cd0305eb62f7a8d65e7956b8f201f66ecdb336c6390cdc810c1a4188cca2de08260cddc4d1ab	1	0	\\x000000010000000000800003bf767f824bc04aecf249b34e478ad6833184e11bc19a435e29d96ca78651e950348534c2a24f35f4be1d27a264961d5577f8b5e40e6c37166a842e867df78d6915b90b147a8fe4ab473206bc9c536aabc12fe7880d8ee5838e03a8683909b8712448392aebd0e95635d6685fcc8bed93f73bb498f0ef3ea64d6051a4dee0dd8d010001	\\x3a535e5bb5f719e0ae6840305928bdfe5941a13a8f13eaf916a4e70ccb8402f4e95cb65e5fa1fc60447c856525b0b5603a5976e3fecfa3bf739fa07ae70b7a02	1665138464000000	1665743264000000	1728815264000000	1823423264000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
96	\\xdc00b6a2d81a05dc4991a5d0ff39e4939cabc04ab3b75bf71a3bd84cf1ef811fa1318556ec776ebf0164a1a3689567d4dda22d72fffb76776f9389e6ddd1ab76	1	0	\\x000000010000000000800003d834b65a51630224563c6b41196d55e3242c47680767938a5e2487e5f163284c8ecf11d2370a2ebe4c1ed69e80d72fe4f33da3c4b326228adff2ce13d275a34bbcaafdce4fdfdfa4f12d7cb932bf853b79843be3aff09bee3ceb1754ba51c3ef6faf17e4f9da488146c410584c0684555297377f8c632933116ed84965d680f9010001	\\x629d12e4a064e3b12f087ea7b49b49bfe6ee5d21e1d4d2029eb976fdc2f05772771af00376bbfbbe0cc19181efc00e18b2bbb33acf22e8f0ce375f98a2243007	1651234964000000	1651839764000000	1714911764000000	1809519764000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
97	\\xdcf42de164f3762bd1032f05b9e0bdcb2a6b322ff24f3b2d5b4f0dd81e5e625412bb0e4ef0f2252395002d0e5179335c5e1c62b706920de0f128c4bf2a6755cf	1	0	\\x000000010000000000800003d2c03afe11f9b25969e02156261ccc8e604a78f67503f6bc2c83adc42c24adf8f2d6b072cb3ac12158c6d8f12b4d5ba508ce4fdd140890348af96cbf2ab1eea4eae326dc39a353c944c2b18acf39350e6120b1afe82d66e413f9ea0df791186e2f75d818c50f24f7211bc93f98b448f204b314dc549b0a280254ed676191a9cd010001	\\xa1c775de6ccb063fb939980f4571088f988d08e5078e819af55e92f05da8047a71fa6b200d53530ab53fd2197a0c2b7a211115a42cb220b79b3a7fafee796903	1672996964000000	1673601764000000	1736673764000000	1831281764000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
98	\\xdf482287d74118cadadbd656be2f41cd899842f6f32918459cd722abf97c37d5d26529ffdb9e4eb88949cadf866698f94c32ea30f3c5225e07391876464fc885	1	0	\\x000000010000000000800003b96a8fa544b6b70b3f7508d146ce2297f403e3e737a853e233d722802e9499dddbb93c4d1bcd259565f2d99c47f9017da82789276b270972f53addee3c942b9c86e27bd6a0b9f458cb1c2e904719c735f5aaa00882aafcac9ca308ecfe90b95dccdf22c8ad43c9845e53d63b9ec8280507af61b8d56f70b3dc4a66dd66bfd497010001	\\x352de24046e0fe0c1b946af6099df75cd028c7aa84c60c63761cfcb23b519cce4d11ef8d005a6226233b160e11145e307957d6b34a5c1615e67c255428826d06	1662115964000000	1662720764000000	1725792764000000	1820400764000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
99	\\xe090ab31380bcd9f023e989a95620f522e77c00a4854c6e63c7121eae8691f003da016c917a0e0b069d080ea860461223aa8d40e25aff21fe3b613aa3da08a34	1	0	\\x000000010000000000800003a2ea9160dd7be5c46d5e4cc9692f5e888a9be7807be42b862a86306a750356a92d371d4e92e20c8881574dfd072b0cefb8ce830f11832bcfd120e9483ddc0bf0a3a29b7d3e11b75c9bc9f889a5e89b80f688fb88da624f6b43a9d52b6604b574d4bfbf6928254518fb5c853a5629d30de5c6e1d5f8274adeea7e730f84f11867010001	\\x8d4db9d893d7ad31bdc20f520c2976e9740e221b69ade59f8f758c2b9aff7ac22524b6852693859d7365603819fa88c1fd68021fbfcf1c9861e5d0fb1857cd05	1669369964000000	1669974764000000	1733046764000000	1827654764000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
100	\\xe18c370210fb4354feb42b269546206ca67cda2b5152f86da94db11ee19038f7bd92b979c892ef862083e398e199b026af4d287157b6e1429ce102006e9bfc97	1	0	\\x00000001000000000080000396aebacb17ad888ca2f585014ed1dae6632b14c5d2cf0344f73119ae473234a9e0634c587bc83de1fc8b1b02dc76a02ee5587498ea1d56fea71179e72d0085d3fa38b4b5852a50d69dab97d10666c7809dbced96fbbc2344c4a67b283b62f1debdf169a5bfb9c0f436a395c584ac3eebb948f862861cca6d6702dc630aab2f35010001	\\x50d47a787d1b7c7157ad730929e1c956521b33481cc79d917609b7218c405ac9d0f2753625e3b191f927af328017ab25ac338b2e6150589970012c31a459fb0d	1658488964000000	1659093764000000	1722165764000000	1816773764000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
101	\\xe49833a00e5e4a27c49c00cfdaa333394abf0a0ed88982895cd0c295da9454b3636ea83812ecbaafd521cc96de75bbe00bbe1efa0ac5f770c704c5b8fef62994	1	0	\\x000000010000000000800003efbe13b55c01d1201ecc7e1c4ccda7347f082ad0ebc59fd72b129dd7dc58f2bdb9287bf2b9f89ab680ad7253603cc0647e880c9ae2c6499488ca2b7aa02471fa6d0a8df6084eaf7cc043f8bef2283dec342fe8ba930c48e9c2dc6d6da1c1e7bb763c0e0d13f65034303e3738e8953642994c6fe6da0fd9706e87bdc33952e0cd010001	\\x6a6721d7d386255d9c1aba5943a963d2047cf55d95b9dac380038b782d59f7f1df5d54bd7f02afe727cec5e9696c79b6eab639a286cb92c159fde5cd07e24704	1652443964000000	1653048764000000	1716120764000000	1810728764000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
102	\\xe4dc46dbd5213bf14e69e30743cd4bb02dba57843e74da7f6df3e5627d35f49c419d94f6acea8c3c7959444db18130864821b1c69ba52b1ca83a742b67876f14	1	0	\\x000000010000000000800003d6378f96de543ab636c319717ef3abc40b7d2c115eb41a20b06614e5f5ea02057e7222a1b7b7952f51bc326158bdb714d4dd567d36f071f0099f4bd5f211feb9fbb640346d39708a74408a1fb7c7193351edf67bbf7100196ff24a37a6b79b8bbc0cab0c14295d6e29ba43ef8b92c10042b175724bdcfcf8d5dd8a7aa104a15d010001	\\x5a6d0918df8b52d156fedc7a8a7ed1d80aa0cc9eb29a2ccd869aa63feb4cec17e54d069a6315a3c51af3bec0e75a9010dced72a149322523e8975817c62e4c0d	1648816964000000	1649421764000000	1712493764000000	1807101764000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
103	\\xe76c6b2142f25b98b7a37fef0253173e11ec904354f7ebd89d7e6a1add26b9d53c31e4084a42e986e492d931451406f5e78439a3f3cfdb0660d6222351060048	1	0	\\x000000010000000000800003c05aac8c9bf20d51b3b30101fb2656fcb0f9baf5b758a3c913794ece4836c40cc55b0c16b774bbcb27988f65e5568428535c30c6beae794902deb25bcada9570f81d37e9f6c2a1460f060224b9fc030cbf7aa8170d31094fec272f21c437815c5e0dce27223abdaffa3fa02e72976bf5ca4367b6acf1a6c7ead6fae6209d36fb010001	\\x46272a11f2301d91f3111a237255eee0a1719747c58277ff64e4cc99ea661b34b02240265d64e39a49d449e82dfa764108b6417a89acb0ff679d494487192606	1669369964000000	1669974764000000	1733046764000000	1827654764000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
104	\\xef282c0984f9aa8cf73e9b80b2c7a9b7a55cf0c5db763ea8a1d4de341b38c617ad72bfd687a9d5075bb2e15e107051b85dc42a137dc71c6eb3e7ac85790bd8d8	1	0	\\x000000010000000000800003e5cdef2b23d2341912d49394826c80701e663e1530d4af40036210d9b6b8d35aede385c5aec626da01822676daa4b400d52d52ec6636b32947390760087c65a508fc49ef5985173265749848df56d2a23a7176ed4d607818d3935c48f65e4a572f3d814fbf5e3af9829a8b0c6aa2cb3803a0ccdf72a16930d3667c4f1a7a7c1b010001	\\xb6189ede8c2fa280f8c4367ee4b66ac86c286f6d34523c541736577c633a53f7218efeba4addfe1108ba8bff3ad0f891aed5bb433fdf7e4f8b6b35051ba38b08	1672996964000000	1673601764000000	1736673764000000	1831281764000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
105	\\xf540e4d6938da5d9a7885dd6e5f2a128f5c813cc2a6d7c379dd7fa56a9f1b532f7bf4aa68d50ebfc920647cc3d2992cb3575d4639e2ab7bdcc1ff85d11bcc9e2	1	0	\\x000000010000000000800003ab282e8231d632ede23585921e4b06fb99343c1f1a29b93bbdd8fd66802bd6aed772324a35b49b531ebc05f8e9215d437970ae72c1f84b3521d377f17aa675959820e1a248dc6f5f44632e9a7bb88bf1fee54708d324b03ee6cbaca8f277da060b23f99fb8f89aea58729ecfcf8321e117f626346c634ae36ddc9ed1d922af17010001	\\xa586c814b78607577232201d82c646b58ffbfe3bc33a1330c438f499c010a8a13c6f0f484aed54b372fd7ec1a62523154ee4937c40852a43dfc8c06f0db8df0c	1668160964000000	1668765764000000	1731837764000000	1826445764000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
106	\\xf62ca1a9e7b3f151b093e0a4179e37fad25b1d828dcf888fa6f30ad8898f8fa86f875ada341a11bacaf1e5fba30c1e0a4ecae42bd3ce5745ee123a358542ebd8	1	0	\\x000000010000000000800003e08afd84ad42a7af1140a4fd3a3fc31483a350af7684837611a80201c7d043e740816a37bdd0722b1c015c3f3c84f2af5bd1834b2c05712bd14b362e76dbaf1684c67dbf5b6da91ae0a82baec052c40873838086249baa09d33005f0fd08d690359d583fa06b4f45a7e0f0315bf40779167adcd0853fd9be67cff72c8f1535f7010001	\\xc8bbb42cf63ec10fd9c361cd6bca7401e0a88fcef30c8b369394f2b0ad2375b030d864437ed3f04a63d7641f95fc895f4c76ddbfe0153fb19e91175c5bacd809	1677832964000000	1678437764000000	1741509764000000	1836117764000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
107	\\xfaf80361a5ab4c5eb4e225c7f0c2807f26a831c473e230ca44827c5138c50cad0a259058b97c259afa5a9221ea10b69f06f78c6080daeb5aface5f6b5d61c1db	1	0	\\x000000010000000000800003e65fe75f5126f44483de2de3e498dbd3bde304cecd0021948b214f40d6f747a3beb2284ff0f6bf90944690bae08456b830afe56c19c5de822c8ce6c1058190ce1ecb8bf59ecac544430aef03f3ade3915876255301e3fa0ebb0aefeb90813a781b6608b952c2a0b84c1e021c07081173ede1cee69c3c0af2a8ba3b0a5449e2eb010001	\\x34e51553bbd78646e18b71c08b4ba1011d578518a55dbf84627f54f20144374e6ee88617e9fcba60c5e93fbb7acd9b1cf57d4b5e098d149e6e0ef8d5eb05ce0a	1677228464000000	1677833264000000	1740905264000000	1835513264000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
108	\\xfbe81793f0f93ad81f136b3ce7237decc2c3d554a5ea92513a0e634fd30d38db3e98f276b3ecdbe5005c6499797ce08639ec755da798066db92839083dfd3e73	1	0	\\x000000010000000000800003d2587f383d34dd3f66b7daf81c91f1d3c8e20502f59d4d0c8546335730846ddd57027adfef5c380579a5bbffb92c7b5a1c8c6acebb884dd7c73aaecffd1e41aa32f90a90b40c987820c7fdcbd0322e51632d76e1508eeab69c1f463419414c86e5161c98a6fd090179d4108b8795ced7fe35b541bdb6be9f82cde3c30d2c3e91010001	\\x50075bc3a7d9cead6daf50af75823e7998cb2783bf363c44e7cd681f8e352f957a2a2da7eddca8a899c44ef1664554b3423356ac732b9f1d26ceb1e1336b6e01	1654861964000000	1655466764000000	1718538764000000	1813146764000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
109	\\xfb3899ab35248ee00c8309ed16177516fdc5dd924dbabae8a01aabf45807989fb04bf5134eb62a836121ac2ccd8e55466c852681c6ece19156037f64268a67d9	1	0	\\x000000010000000000800003b677ace977e13c92333ea305a2f306051f35f01eafd40e691ff0826043662b856983a147419935f355080066c978bff58df40931dea965ac3037b9018916efb9bd14b4487c2f4742a30fb533626d3f3545f1895ad3078e72ddc9ef3c0f3888c83555b54b613e3c5fba44183843206c6502bc861828df08a04e5943e090de414f010001	\\x6277eaf9b966d2725bdce19640dd762be64f8e2e4be883be6914fc23162e1e766fdbe882671ce1149c978aa7849dc186e93a1042378deb097c7a361693253400	1658488964000000	1659093764000000	1722165764000000	1816773764000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
110	\\xfd0023fa37d1da8b97c98a2485c407de4da434a0e0d1cf50a59cf712007da2ebbe304009c90de269198a4c63b33a227d66f88d630dcb4fc81f79d90efdcf70c7	1	0	\\x000000010000000000800003c94ec110fce3a33873a3bb247357fd92f773e46856a6f74b7c1f91adb9fff761536ed5db493f77bb642ef99428f697c8bd9562b46e0a3fd857f50180e73dc75c0f58986721a3d3d200f29b389a0c3a6d3e9c04912155f4d8ef26c7b94e565c438a75e7f75decfa2b72b78bb26a3410d9e258a67a89f6d41e450ad82ae9289f75010001	\\x8e84c99a3f7afc6598b232780606b9dcec652f806e44bed85faa14dbe82850e76c857b1b5eb3456d5c287332b9f2745e5e212d7ea73bd44914ec7f2416573d0b	1648816964000000	1649421764000000	1712493764000000	1807101764000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
111	\\xfd8ced942b0f144a6825573638ba4cdafdc32d0165957e7ac152d509c40a4e88d36fae6b4bb45ddb7690f4f147ecd637558aaf2549762a542152c8bfc3f20cc0	1	0	\\x000000010000000000800003a1c7184b7ef8abab9c40ad50d6429e22ebe8dade66a0364712ff5ba91507589bb6b256b56e195f8d3f641f3a95148e12e0323f53c8664638bea6a17980021aef3e751d62ab1802299385c3b9537df2433b3eeece5c08e095f9d325bf4f3ed250e151fb4a22e0a18f6dbf15bdb270201f4f268c3457fa08aaf9dc55f4b8cfbb95010001	\\xd69ff0ab2dba32c229329c6a5dc547f9153f4028f1e462f2faee14ff49815f267df09968fe534b09fdc6a1c0c84990c98d99555cd1563a73d00ea0cba318880b	1671787964000000	1672392764000000	1735464764000000	1830072764000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
112	\\x00cddca566838027f2c87c4ce3d0233d3e22a07362164886eebc44714aeff9a2eca92fef44d78e40331a5975a48a124f054a11c788b41eff22fa086e640d7c03	1	0	\\x000000010000000000800003b809d0a6a8a675e2bacddcadd409e3040b39e8bfe6b9fc21295d7500ae0b17bfb8eb14ccca0d4aa26ea3de8fc99a03890b312f1499e190bb4340a87d13a128185bb936bd3ce38e76f34e300983e303d31b9ff9c50412b2dda258d128fbbd276e3f1d85fcaed753f4bbe36a7966ca73383db5fb780a036d32636cf0b33157b60b010001	\\x2e0a251c9fb7e8cabb61513d8403375061e887e68bfad0ef652bec7e5f48b6bdcd55b56fa986d0a83a259887f9aece90ace8f03fd78638536dcaa1addfc4c60f	1653652964000000	1654257764000000	1717329764000000	1811937764000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
113	\\x01555fb1ff1a958724621d12106d04698827b4ecaef088c52112301a6e99e7f0f73f727537475b76da7a12e478232133871852de8b46a577833388076223e1e6	1	0	\\x000000010000000000800003d95c6fe5ae01a57bf42fead1cedd0d1400d8a26bade0b0b331401cb811014fd1834f95469feb8d0d9d8f3382e63b115076f8cc35edd882281adca8f16b8aa10e8f5bb4b050375b66a14d69e49c61c2fc60c4370639a072a7c33f254e9ed5ce1fff7c129558722f57f1e17076e8851fae68077ca80271dffb3933770069e5f39f010001	\\x23fbab7cba6b1e050e3826241d9528342a6ca148036bfc47a7f2d0298feb4e195473fe48ea7544145574b26cf2f85717812a0b2b671a6cf5a73f873fce292907	1678437464000000	1679042264000000	1742114264000000	1836722264000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
114	\\x068dcba9e4e38d95c701ebd7f5c2dbcf8659959760277a70237b6a63b520deaff718711015e3784ceaa9f0293e0d445add37b70f1c0f9ab6af7b40e4d4523a47	1	0	\\x0000000100000000008000039b39abdc6333f8e581d5485c2c079d7207198421624321b32b561c9d808ab5fe9300f094f3e34e93b066fe74d691e2a08f62a8ae7d41416b13b64194985cbb6cf0a5c2694c7c45116a3eebe7b84cb6d3e3517ac4b90e802b77cc83bdf1708a8228e093b124b989f3601ae114a28bb051f6fe3e364fcfabe6a16afba1d5d10d6f010001	\\x8fe9d1e27e0a5a3984a7801414fdd0c07b46fd106e3afce7ae7c7c49216709ca49751907e17cd10b6d408689b0695138b36710da47f55ee24343bd3bd01e8e0c	1657884464000000	1658489264000000	1721561264000000	1816169264000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
115	\\x074125abb6b743d7ce6acb60ff7cbaf07dfe9ed7bb199b58f6fd08d0870369066335996f687417fb1a757116133f7d058473ed545553a01d37df64b23e1955d7	1	0	\\x000000010000000000800003b9e113c521ed9a8a42ef0eb6388868c9d4a1575434e9e89c510a0e95515e9d276f54e22536ecd6a45f157c0348558c1b5d70c61191c5c4cf5a24b2fc9e16821d80fc381da4eba4f2d142da3f04c776463c0ec7740f5fd4709b3033cb74df89ab7b7a840eabf08aabb119df730bfdc454a9330cf80c3c4c5626d9418fd0d411e1010001	\\x7c342e30f62a862aa81f70ae4cb8f5458ffa32811d2804409eeb9fcfbcf3a4f9944c36fad5b5d6b87f904b16dc98e3e5c3c357ee0d502b717f9f2208d325550f	1670578964000000	1671183764000000	1734255764000000	1828863764000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
116	\\x07c585e88c47fca3c047583d38b15693956a0fba4003196cbc71170ab0856970632b37e1360a5b2065fca456f0d2650a55c9b8d5783d70ae0b4e0806dc328f55	1	0	\\x000000010000000000800003efefd86cdbb0bf62de0f325fd71f0385c5d664870c6817cd01cfbb321eb9813c4f294663b5cfd9b8139e76eafbf2d9e525481aea9e3797891a06016a1d936b95dbcc86f61b84e30ac839873daef5f9a9257fc5b09fdc592a0a89d1bc4dd8ae61c89d17be747a6a24089b32c05f12e50d5bcfde7869e9568c6ac7a2f1eae6395f010001	\\x6eecb5e142ed49b3f16683d318933fb0bc16a23705854134cb6bf41fe7c8b52863ecf846a9c8fda8a69c406c91b8de05c5647cf85d0f1201a67f416d876d610f	1668765464000000	1669370264000000	1732442264000000	1827050264000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
117	\\x094596921b5b6aa1f60f6cd627abf8d514c7f35cd47632d21f02e05f6de90136cb7fccc34195764e7b94de60c0cc6b17c3d0d6ddb23bccde59a584a5218f2ffd	1	0	\\x000000010000000000800003b39771ff0407aaba9cc280495abbc419f4afaf864c3aaa038893c2ec038eb19544211cf644c30a8ca09205e6e309ea1a3977c21297410d557ac6452a18764f13c633e7e4a0ace44a0a1219d8791ed5fc3a0706867b02d0275999e107091d4a082bc7997cb295e6fb9b25d0e9dd419797adfb53b2e100c2cc98b07235826d213b010001	\\x2d75eb541689582f8b17ee9f798e687c1ecfff6e83ef5d369760d38acd882d4727395a06f2735e6b54878a96a668f2833d03e4dca9cdba70ab1f978d76c7c905	1672996964000000	1673601764000000	1736673764000000	1831281764000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
118	\\x097d55d65e8505b81eabac46badb40729e0a3ef165d6a4f0ccbf759e6d5f5a15036250e9544e9cf2a2feadc9e1f2e349b4a2c7bc0b23b04ce1125151d20a7382	1	0	\\x000000010000000000800003ae7e8ab4086e81ede2be874cd0a0f2f20e92fee5e7fbc328f14169aa582324dc75ee433d9aa0c521c9590b5b3f33eac182c697b76e08159c1c16ce6a5787155c273c6c9b90c3da896728732f8d31df8307eda37e614b45dc425b86bb94472df30d24226b935c9193519fcb4df31c88a4c46e17e3839122c6ceefcf308e817e97010001	\\xd0a069a29edd36351d68181f2e090bf7e8270b468726b86d56f90cd7e1f01eda328fc4e60615ae9c1976173eb3a88dc1294d7a0a8acba760c042a52053447200	1668765464000000	1669370264000000	1732442264000000	1827050264000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
119	\\x10b1d5f2b8fdc374b28bbf13226fe85cecc56f944cf13082b89b1e79a5b75a2838647b4a0087664fa51b86ef27c5d70c4a2984ee4a9d7f4ad723185ae3223350	1	0	\\x000000010000000000800003dc36cfc7a1696c24d75ceb5df11eec1dfcd58413eaee6b3c5a2e166e9d025f34e2af9c94f75fd7af7b069d093c54409d66f5209465b6ad57ef776b2906de8abb3ad43f2e5161ce7194dc11d9d254e5067bd45da763f917d9834b1d89035149edabf9b2d998a6832c7560a19f9d3d772545ff623c377670e7a0f72fb9ce3bb885010001	\\xbf5c24bd682a94c0f2f08601621c0f3f67b34649fc236785c7506f389f7f6cee4a20a687bb2b1b1f0c1d5de25057c2e5f2b18d4be806e2b71b0cabbaf2ca7709	1655466464000000	1656071264000000	1719143264000000	1813751264000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
120	\\x11790bed17a573b3397ddec3e48a1a715ec4c18a04e20e9b510cb40505364f557745d27d11ec39d3c823bad5ba2cfb697420377809fd40144caa352aca6bf7a6	1	0	\\x000000010000000000800003b8ec7cd52d94085d1a925e23bbfbca78ac14ab1a5b1f295cbf0ec123437cddb74bd266d9acab8d295b64b9c4a9a76413ffe935e54217d7b7b182b329dc1a5a4056a3886649e0b0615f69d4933ba69577197a3db1ff280ef44e02f48da7968a7dec5a2fb1f890ee89fcfca333292390fe6c2f7ea6da650e44779e87887d1f45dd010001	\\xb7e9764714e53e0aa877c336f2f94677940a8b959e53447832492ce35c30cb545307335a6148ba7f353cf4ad93727eb03a646a98ea851828f96c2cc23b1ac609	1660302464000000	1660907264000000	1723979264000000	1818587264000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
121	\\x15c53da75219d7f7f83fddbdef70df1c6dad86452dedf3c09e37bade7e701d3606ffb117f1a3e18bff6642e33c3db37d0933e7251cf208c41c7cb6e5c6fa3ea1	1	0	\\x000000010000000000800003ad557c0304bcdb8e3c3d6ca364d7446562118deaa542a2cdfd8087c575471f6da24983fb4e8d87aac8de4956019ac57348e77d369a3a84564bed54e62d104ac82c0d2a771064a9a203aa8bb7b603f76658395db03dc30e24c32c732fe5bf720038d967bd19be9fb68a15b6e2c452d4194ba5a053982fd181bd8da1bd5c75ff6f010001	\\xcd28ddb7fa2cccbfe873c52868d90f31991bcf1fc552ace02c52653aa0221ea5eb5fefadad5d999bcb6eea445f65464778f0002495fe1407fb5c4ab2d6d2ca09	1671787964000000	1672392764000000	1735464764000000	1830072764000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
122	\\x1685b818d7aa2d8a59d0895703c581313c252cca71ff483988960786515d19444d671d2da51bb9b557d953db992c41891a28fe230c1a390e1000a99f23327cc0	1	0	\\x0000000100000000008000039d3ddc29d5ce8b8f2ad62b7154a78bb3476fcd26ce63875f26ee314d0699961b69c51ad67ef719604d5bd38ddcbba7848bf12af55f068537dd0953a82bd6c4f0a1b7a62620b59fb32af64f662f0796f15015275044712bd8e20ce144e202e23b767183e596ba21661011e7a5e732950e76ac81a61659096c3524728e5d9a6341010001	\\x5980bba74da2f339037af0511f800684fab7940bd72ac44792ada79fced5af3576a183b5488b79072ccffe0459364e6c7d90c3025829c575633c3fe691945a0a	1662720464000000	1663325264000000	1726397264000000	1821005264000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
123	\\x18e966b598c019c8f0531432f7be0b195e15f45174dbdf7c422da9a398acb361b1df823dcb5bb15dc97cea220d22e7c350ff1af462ceebaf651cc894ed72293a	1	0	\\x000000010000000000800003ac2436e4f816ca879213dc0a43f12fd4f513e764eadd32e381bf786f4ecce035c8fe432b686b15c55e0daa91693bc467a8888add45056f82019523039d80b537f9b86083d2e212bd3eb3ebd2b1d80489129506c4571786013210491806bddb72aa6e082113b187f5e758ef32c57450fc446c6990cfd852aa32de8f53c7569369010001	\\x4038c1a0cd0bd3a503e974dac0bfdf09647871af41474d87507d71ab9a23d5d6557d11938db30a7d70baf13f87e2dfe6a4f50d4b5283a0f42bbb18586196720f	1679646464000000	1680251264000000	1743323264000000	1837931264000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
124	\\x194536bc65b908829c2bb8bee2ea7611e844a0defa4436564c88877139bf2e7118004dd916adc6fe40d85b10ef71c540678f3ac9c8ee4466ca86fc06b18b23c2	1	0	\\x000000010000000000800003f2fd5104de97191b931ede80e5dca504625983be384b3e71eb2146731e4295c0f024b436463351a1e32567a608a78f3c533f2939809b17d69c37595fca9d8d1beb0396453fff82d0e047b1fb032632d3e4094b59cda6f1569ccf22720cc9937ab2ce06f16f1ce0ccfc88e18da341bb68221276c6bb9600b7d04ea84c60e5bb09010001	\\xee84ab9d829ac552981b1038e0d8442fac34597820b0be406bd575e3e9f77c3da134b579e5228b5fe62b19a1a7822b4ba5e825ddc0c96166a55f456e23901e03	1648816964000000	1649421764000000	1712493764000000	1807101764000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
125	\\x1ac52dd27708936c923ec330d884e1bf620ebac1d1f0148945034e06ec4e2f41fddce3c2742316803f42e242ec41ecabc4226d6fb1a6e58289ffee469c140871	1	0	\\x000000010000000000800003ac5e3729053a4fa2b25b6069c6db37527d058e2c29688c44ef91851e9326f44505b6ae7c824d8ff636f466a7c9dd3d3640ccf2402f9e6029b9fa81308d3b2190b72c9e336d479565db712761af6a0b27b6c6c4db80812faf188411a44fe88a193f73b666d65a08fb1efea6ce86e8026fc5ca09329220c635a336cdb6e94861c5010001	\\xf553e06e620280c02185f953a3f88410ab03c29af0dcc6e1fbecd3fb1fcb4a4e26bececf020fe5a93fda4f0e5aa9bee5fcc8ce628133a21242ba16a0ef7c8004	1671787964000000	1672392764000000	1735464764000000	1830072764000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
126	\\x1d1d54390d41fe09f2ebf9164460b49aab0db30225ae0b5b4d04f3655a5647d80df27cfb5f937afd75eaa41614874b4749b0be67b314464bef5272ebc86f3e41	1	0	\\x000000010000000000800003a1ce0ebcdbbbbe07856e561ab764f79e4dddcfccd4e9f8f0c9fae8357ece4e0ce70a86a4d9e0904be587100d72da957f8af45ca9508295643967e6cb11a13efd1257dabb8047f846ce7834c7fceba7c6cc082266f2b2992bb3e02ca5a27d7bb55e32069f538e28fafda0fc49ee9a9ac05e114e183c05d06f9e4d77015a6afce1010001	\\x81f35f6a8fe387aef2c95ce8ce24a9c479682b2046d60d63924cdfa298bf3842869b4bda9780c6e2256a40115f895594abaa8c1cf391644e735f705919c2de05	1664533964000000	1665138764000000	1728210764000000	1822818764000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
127	\\x22e1217e828fd07815302042c33124b293fe9fe50c5ba44b48887bd724d926c06610814166186cc97baed6e38e705e18c4acc968bedfa266abdfe82bb1ebc8c2	1	0	\\x000000010000000000800003960237ec33823b77e3da58ae84ea4b120702db1d144cd9c4e2ffe45f987453fd42bf6834ed79de1b13c2906ed5ac9f3cd509ef8bac5f0c0be277c55917994a13d68663020741eb5a2423b7a1c43ef53863bc6e1e61c89c37c810597fb3806f2f7c184f8513312e1e36a91e50e3d4acf641e9320fafe14ac062a4a148cb404a2b010001	\\xfa3b597e702a3ef68bfeada1adeca17f0e2b2da34d07e44dd86d10673dd7bfc2e15ffdf31df3126f4e946b504f2aba9d872486402fa3e07f9709e3269663450a	1679646464000000	1680251264000000	1743323264000000	1837931264000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
128	\\x229503454e2732c2dd078f60dbd8b554e3e3590d917b5b3adf05b8e054bb95a16bc4be7afdb925b128ac54b450468f83550032bebf1b07bc09080104997ff183	1	0	\\x000000010000000000800003c00dc6a588e32c3f7d91e1663d45292ccd4c9541a424b55c1665a351e6a230fff6f813c12a2ee448baabf24dcc08f31aa58423513eb1cd3935874b2976ab3be55e31989c52eb41a535d4b717301652c274440626178a68c2cabb54459265d764ad62872194c0ffa5ff7ec89c3e8592e271dda5bc3e3b409c9208130522abe081010001	\\xb872e8373631385752ee8c35644fed4e4e66a8c499d517134e8d16e590df905567de4babee0f9b25334d5f6ec10f636d471ec76cd78033e34b2ebaa312884806	1676019464000000	1676624264000000	1739696264000000	1834304264000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
129	\\x244d8aaa05d04a615b4b1b1ef5d1111e36939bdfc2f7d88473c5d5e5bcc3e350dc5f71ab2b35643f35a960b57f5796258265931d76d207791711ee29158a65e9	1	0	\\x000000010000000000800003e42696ab0daa2f37aa88d896c60bd131b0eede9129a3a7dc4b7fd590512f9d87ed0d4020ccdf1973df2f23b42b5e198bc602b62df29bd31299e36e2e3342729c195a69853f3d3614798db9e1ff3a405c00514807adf166549cdf73a251ab9f21604dabd3cea8ad01573c0ee406766c4e0bdbc7311401a91a389bfb3d733d7ff3010001	\\x7509d778b5fd369130e45f99916dee016f85a88307f93a910da24fdc20e9394acf06426fe98508b2df2e0f90960934b33f03d7b5713f299b1b5dcad1df1b3600	1668765464000000	1669370264000000	1732442264000000	1827050264000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
130	\\x2c7d2fcba2d0880f3fb2b1204253666c61c4a7387ac54a546a2623d8dce673cc9a9d26d00a4a858c297c3f83c5a6fdd1c9fab09df7640c8ef10f035378e4a678	1	0	\\x000000010000000000800003b768654601fc2227ca93ae14d7933a78eb3dff16ab9a8d70aea96479bd5a2ed5fd44ea9fe2fad1d98afb296250620a87d9d73708590a147e04295b084d39bb5df8c5b40f8fd149c38e0cf2be1ed7a1ff62437ce66668ffb39be866c801a743e93527297c747d5dd106378ea349f6b145902b298aa1312f3495dc6a0ead08f4c9010001	\\x7b631d19906daa1e84441177e86e29c7f344e5599832c4a4409eb66d42075d1171b76d22d96aca1b82329924b0edb427a3280414ebdc15114af24249e58e5701	1653048464000000	1653653264000000	1716725264000000	1811333264000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
131	\\x2eed6e78db8e129c540dd645d6e8c79b35f6cd2905dd88112717e3dfa6454b06cee9ed035d201dadcd0b70373929c9a66a70472ef72a2b4d9414af340ed89d15	1	0	\\x0000000100000000008000039bf24d09ad7c057675b60d8ea05be72b9c0c9305e1c66b78ad58420e8b09704f2d67b16ff51399b81f5be0aa29610614ad7216a97f2476172aefcb3943a00b289f4bc3cb57a0eab54bec52f6d69ba696d948c42c807156aefffd12b663ab2f878b2b4f9a1a4ca574d51de7f5385e4d69e9809f7c464a1606366aaea36ff60c09010001	\\x63a85c5e9400cfc4cd6437e318742c9542526b0ce01c45c4582001cc005759f7ca4d0059655eec284361326c585d4ddbc27d71020e0acf36c2c7eb4c706bcc07	1670578964000000	1671183764000000	1734255764000000	1828863764000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
132	\\x2e75e1fa2e60e141b033852411cbcd42eb00fb851f4865a86e11966523db9a813d2fdb53344f20203e068794ecd44c5c38504b0ec0715f471e34bfa3a2c63164	1	0	\\x000000010000000000800003c47a0e635ba88c6c48b4d627d092ad4d1446aef9911c23972f7efde0f344c5f1e70db971c73dead31cf7c8b3f86b75b666f5d949c8e3b447f3dc7816a656a47c0ebabb18a107ba5d34c9e2acbd27d50a4947ef47aa2edcb1b82dd77068f168fde27b411d2c33c2420be0cc4263282949d3d490c496566f9b74651bc44f405243010001	\\x078ba17df6729dcdf9fd0b25f9a99bb0d63fc0e4fa802db81fbd17f18c94a9719de77d72d53d0506cd6729f9441852f6dbbbd756a74e20e37e7c4cfd82aae506	1659093464000000	1659698264000000	1722770264000000	1817378264000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
133	\\x2e69d656fc196e926d29cac4016dd5bd3d41523a803df46af6c84d0314cd24a3903383f2286966218132ee93a89447ca3117e503534c93c4cf09e7c9e5875dbc	1	0	\\x000000010000000000800003be4486f6bbc2bf0f293df8d238336437c194aa4771d39fde3b12af97ae738fc94d336778087e4720f4bebba8038523fde3adb14a5b946a89fa40299de10a8ad2d6e2558a2a31ae975b4c8a807c9f51fd93a5a3d17fe79ff70199f673f627d7a00c2db9e5499c6cad5422589de27ecf3e09c4209b28c53cc0b6ee384b1ef066f1010001	\\xb33026d0f75f0e1a08fca7fe01b9bd4f2ab81c8dafcba0406449ce32989c39db9be1aa6d010f7154a0d8488a65be02984530f99b35889b5a904b48c9b805e703	1651839464000000	1652444264000000	1715516264000000	1810124264000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
134	\\x2f514f3f8df9cfac8f71e3d728667bb0b37c71c50218e4d5a5541004f6014c81007cd7ad2741e545b49492fd40835ca7e4f160f7ab9b1bf27ac295621a42c7c8	1	0	\\x000000010000000000800003b7bde167a8b422b8563402d25caf7c4cb7258b327808f3e69ba7a0e18b1745e4a931cc4d4178d635bf401874a73ad36dbd14272a78c07f0827dc50d7d43fdd84be066805aa208c83ac306b56fb8a5842a1adb71a1ad95285cd234bbe5a9e545178790857205174b96b164b968634a17cd406d2437ea4e9c9d40c1a5025ecb129010001	\\x9bb9e5ae1b519452c3594f322ae1ea395ea296120415d0661972adbfec6924832ef183f27ef9aa0b361487a4851ef1fd3a9afdd87ff0c5f679b684abfe2e1d0c	1649421464000000	1650026264000000	1713098264000000	1807706264000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
135	\\x31ed22ffff5c6b71f9ad5203f363b6a422e6afbee889f04465f23d0966a1acb8d5c827fbc83360aebc483cd58e4ccd31baf809a5fad49091cd3e53efa4e3021f	1	0	\\x000000010000000000800003d8f4222b639654ab702b1362086b74e85ad4ec710de67835c935cece8fe3f85144aafe75b6967ead5b916f10c7e537f68d9f9807b4dc5cdba0b14cdee0db6cac79231e679d57a095b012b0540930b960a9cfc8bcf6937e42125462dfb4696830584673d20938d619c81c230b3691fbef613e44d747aac650649d8d22ff1ec6f1010001	\\x321954e521ba337729bfb71de8b07c328d9c34e0b42e799a6ea2240410030d393fb4501e4ab7b20e414819a865ee8ed9c46c577f2c29217f2de874a552fa9f07	1666951964000000	1667556764000000	1730628764000000	1825236764000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
136	\\x327d1b1e1b28151afe97f8aed0053e44a7999f46902f8a0a1012cb75aa85443cd761d2ad8145e184c99c0880bf18594b2e333a1790c0e4cf0ab24cc78fde9f08	1	0	\\x000000010000000000800003ae3e06a1f7a438d2fc10bd04379c465ded309aeede19458555cad8cc4f57a3aaf847806c672b1ab02ca480e6e87e0e1e0117e9b0a2e910d21bc015f64c250e36511c4a648ba2c9cc11b03de8515d17b3e472835b9f1ea14746642439c7b13bbd1aea7861169fa5dce525585e2ad9d19a17d288c186d6db1fb4cc92ec402e44c5010001	\\x5ee6c20074f74039be3f3cf1c5a5a859fae9f718a276f7f0418e2ef2924da0d1cc303000db56079390a4116b1c5e3de28593a134aafa39370fc25fde0853e102	1672392464000000	1672997264000000	1736069264000000	1830677264000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
137	\\x3331dc72a7e89bff3fc75fa413dd54ed4f185b8247d7e02442fc3a1aaddc27899d08c007883fd3859ff22e49b51c31de3b1415f07c7845c1e00545319f1abc5d	1	0	\\x000000010000000000800003dae4be30f88bb01737c3e0abd0d2c4927960c6cb6098b2c01c578a86991f8f988b71551a9322724522d71f4686be39a42c3f166db362dcb5382cd7ad36bb83a28ebf6c5c7480d9e3dabcaf8a174406e82839dcf06b903ad840d1ad33b197398fbb5e18cb4d31a6fc73ad13e5259e4d05fed823c1416aebd7a72dcb79364ccf79010001	\\xcdf38582a9690a64671d19b7c97549562c26d33407db820faadaa06b9eef0a8c5c533aa08585ddf6e5b61bfe8957b2f08c9306044e55f1f47e9e55f16cc1230a	1662720464000000	1663325264000000	1726397264000000	1821005264000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
138	\\x36e58122f8ab7ebd689089fd0a8571c3deab073c3143b8054a98b1bce05e27c1998ae4e7b141acb40b8ea169504cf2439609f1d39eabbe2c7da9e959cb074165	1	0	\\x000000010000000000800003b4cfb6619b398cb52b4086efb43b37cea2754ec3454ac121fcfddc04856391a3b8bb60fa5bd6777f61c18f67769448f7dc392483667ad6243d8d44a92b742adf63cde9ec0d976fe4b4a41953e9dd34fed6afe4c6372cc45b42d31d24b618f0394063d00c7382bb38913c5ee96c247b29e84f025662e05d73b9612cf393884799010001	\\x1abef81527058b417c89507d4eb0194589f247dbf84ffeaa4ebc315c045015e5a232c8cc4900772dadd2117ee1e0d54dcea5a103bdeb02c01510ef873b99e509	1673601464000000	1674206264000000	1737278264000000	1831886264000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
139	\\x377d253731b32c94a6ee605c6d691d4f338c690a1d5b107ee915bd9aeb6cae8bd1af516a601687ae45d9c573177788e0fd20fc256bfa315f2abdf843a5461abd	1	0	\\x000000010000000000800003d3041deac92726d6f8ae61823581a2efae8cbd70b6c735817395bcfe4744db60c3f0628207d798cff4650319c7a5eefb3ee78ad85a3a0c56f51b7930bac479f59c93dd85aa9e890cc30a592a74a10dd54bef2d674325c78a06fb75655d0a1c47c4fda98a659ff89238c07a5aec8c7bf611933062d17dbae46f179a69a364badf010001	\\x6307498cc442901f227bf8209781dba2a678a4e9aa6e2f9753239b4f891b8fece61297a70912ecdfa1156c1f3d1da52f93b87b7c9e6b4eba51236a480dea760d	1648212464000000	1648817264000000	1711889264000000	1806497264000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
140	\\x3705109d9361b3089bdd8b0cfb470fda0d18592f2525a2e7d2b47e5af0f6d84a0881d2f7d1f60c24dce9a6982082dcfba59f9eb79b8e2c91d0acbae70e310e45	1	0	\\x000000010000000000800003cdef506e99af5f41da9e71303812d5892e17d00c1af1dd40437c2888a40c5dffdae443d33651f9c04ffe1bcceea88f6119f470f5081e03f48a3e9dd5a2465ea6b26d6fcc7d2b34f10985a5ea2fb3b44769830021ab2aed8eeef1af103830bd98a216ffc552455dd97e57428e69e04232b58b382a150c2f68a0eaff78bda71975010001	\\x605e32cb37e89c2f5d066840cd170b8951928b6bed0af9c3f196e78fae3fab7887062d65a63af5c897412fd5b87b5f7f3281ebe3f18e34c418e1c3a1d1b44f07	1676019464000000	1676624264000000	1739696264000000	1834304264000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
141	\\x373133f26ca7ea39eddf29150519bbc606d5db461b8532c36ce5804bc53eba572c70902768cc277a375031775e311d2a4e4fec1c437aa8a1146a62c663dbd649	1	0	\\x000000010000000000800003c5893d48769a59a4cd48f3fcc0dc0e1301558d0f88bc6fe13c60e84ded7c85a1ecad1ebb7bc230cbfa20db55faa17c41531d3d556a5985231d646cb162d0645182e129f2f1a901efe98fd76429a90fff91780406b67e005e885cbf16c800e7b98a24c7cc7f5b88b7e4980a2725da53a6e11a93486bb9714bdcd0705fa57ad915010001	\\xd0e046d92afa7e37604178a57746c93e3ba1fde2f071490b5345cf93ab44253c507c0d9e9570039972793bea6423076f148a915baccf0ccfe26c9d0c5f607004	1668160964000000	1668765764000000	1731837764000000	1826445764000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
142	\\x3c656779fc9d0578887fb73a639261977bddb0dd97319c1f19c80bbc0298c06a6a5dfdc40fb06649b1ae3bc4e651b57fc239eced2f61709e8747aa41304a5172	1	0	\\x000000010000000000800003cee67aeda8a9ad611f634373e711124134273f3eb9733771843ad22a05b519bfcdcb49b0ae14c3fb59b613c621a632eaa6db9b2419d97a1e5e6d0d08d6ccdf2e9d6810ebd0c9b10fe9e776b19bb41536cb1a686c7703df379efa5e88bae0bdc610e49e57407deffd83c848d73dd092022ec2a0c08ad6c3ff9b8092ff5bb25ae3010001	\\x240f3e78dc406d6189f84f7c1283ee20016b2ce01a5311a43d0b89bb53813908162b11049a2fc528a05bed7340167e2bdc0924a6339010ea4c2007f0efc5940e	1666347464000000	1666952264000000	1730024264000000	1824632264000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
143	\\x3ec551621cef1ccd6f9fb2e8de8d25e737cf0c17fa2e050a0f5f3aaa974cb896d8a493ae43a8845c676907cf5c7dec029ae4faba25c1f45a87557b720564c125	1	0	\\x0000000100000000008000039a17ad50d019832905e477834bf590565992d21fe63ed135cbc32344ea024555a3ea436ecc8894882c9b9a881c3ffa5d3cf326943b05dd86bd2f7b03312a762cb7d3213ea5f06223e2315368d498325d18f017687332714ccf08b070f97103f512faa141abc7453e6e608c3568f5898e6bca01b1648e158fdb1309982d796441010001	\\xc0d2caafb46309b7d5ba1f304551f3428193129febddad256614dc6abbd50e992e280f1ca5540f4359ad4a264cafb928eaf7a61abfd06147a63c45cc882b8303	1648212464000000	1648817264000000	1711889264000000	1806497264000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
144	\\x41b58ad779143edcb61dc0d3990a46f84a8f1b044fd9bd0120c1f9b8d59659b037369116334f410385085ab1b507709f5de97543c1465784dab02d3eefbbd044	1	0	\\x000000010000000000800003e751b0d07b8343c58b882ec9007b6626666382eac2894519514c44df69a0c886ab098adbd932701242a8ddaa38e55114dd77a988fe1dc096d0cd6b80ffe66d45e52958fff59e6281326944940e3ffe93236c3ce6472e0c0a84e4e94b41b15ca62f7dc6a24feb831e9713757e3e1e8e257a9bd1787e88f920ad0ee83c8479c08f010001	\\x3926f2ac03b5cd72449083c2be72fa93cfce32f01d842dd05d4bd4b9b225123144eaff0ed3b9efcb386004f2435e45a7e30691aff9774ff51e016f14ca4a3209	1674810464000000	1675415264000000	1738487264000000	1833095264000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
145	\\x48b5251558a313f5c3caa7b3b40a5efb63fb5a70fb2d40c8770b71beb84930825e52e57c169ce56cbe3522613ce08408976864a669090e805dbfcf54f2928f9f	1	0	\\x000000010000000000800003c0c45a424f00d1df736fab5ea03c0676837d98c594219a624465c45e173107a3bcc4376fa496904473fe5e8b4671f0ce8baef2003a8bfda52bb2c3dfb0fcb872308801e2245fd8a781723e96faed3eaf7f2f13c2742ac86fbb1558849f9ea3b09263d9f48e6c9a9715085df0ecf6c84347ab7eec3cc97dde38efb68d7a156df7010001	\\x2905cf5d835b4d6df7677b86b6872d873ba8fb0c0ac30baf129d55d0ac1910ccf03768c55f6f41f37d3cbc05ab9456015f02ca68cc073534eb7355355e8d830f	1673601464000000	1674206264000000	1737278264000000	1831886264000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
146	\\x4c89e014d86e7fd8fc19eef8a96d6f55e1c6a14523a39414c0acf54412d7c921ec024bf0b4c86da09c02ef3144b20df2e15d2351bcb99d6819daf9df9c1e8c33	1	0	\\x000000010000000000800003c0adb74ba63037239e1da68c7c28676e37578758e410d4970a0346403bd4fef74168974d57f1b2b393c20567084b7de3d6e1738ed9fcafd592b035acb102b06f527f97600fbd02c1ff6598832b74fcf4f7a31d7dbd5bff581934f9a29ea25c2216d0602e317327d4f6a177041efda17dcf094765823869be282df72732a1b033010001	\\x4da2cebe2abdb759660c76dbdb5321aa208fc8a183ed7d16015b08795e7ed7875b8e6d4d1a20ac0d947dcdcb4657b97d79198d19930b7657d84b1312a13c4700	1654257464000000	1654862264000000	1717934264000000	1812542264000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
147	\\x50a1492aa75b4619f076ccd98df263e801616d503d2b44123cce72f20a9dda32001f609f4c95857e2cecdce015c0b79c583bb1e1021503fba4d797ed95376930	1	0	\\x000000010000000000800003e58fefd5884e3ecec9772e6cce59141ed76bb045c79a438ff26b4a3600d2fdccc26651d1a0f45e420bafcb7590824bb7e02cd0243f0ecd92ddf0d82fea714e51aec021ad7616b03fd3ab361692760dd8578fb48f58fe523154edab66ef2fd19346df723f8d4685bef6626b289612fb691096e41e00e5f09e98eac9dd3d3f16d5010001	\\xc440c713ab7c87f2570e0b684896a3a3a7caaba51f91686bfd64d904cea65d6ee1fa26567825961fcadbdca0779246d51e58d0aac8532187e09619aceb71160b	1663324964000000	1663929764000000	1727001764000000	1821609764000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
148	\\x5935e82c98b32abfc7d37840c4602770ead69abd1d36a2c6c059b1c4c51149320181b6e9a4aa39bb0ecba6cfb9d7103753426b8c1dc503eb69fc24274e1f21ec	1	0	\\x000000010000000000800003c8d5908ea599147497248a0a956f99f525bc61b83b2df94975b3fd140d337be5461c8510d705f6919376aec7e2091b1db92d216104bab0b7fb8060eaccd686c2f12983c36f93782393e3962d8e728137a84a2ae1f806a2698edbb16c46d230613af6d40daf7fb1060dbddd1e0d9f5f0028f400395e6cc0f8bbaa3c6f1fc5f491010001	\\x1eb509d40d8043581f38fed47856a986a5fcb5b7d275d7823aa5ab454d6ba7da7839e4a8fb013114cc0f56bcb18603c7e2aa7ee5010761d0355dc40d0a9d1e08	1665742964000000	1666347764000000	1729419764000000	1824027764000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
149	\\x5cb18bd7a050ce60478dac1b1b0655501a8fd7b18bbfd8e57ce4c336ba5f888e2581062af0ff742c1a580fd6626359dd87f5a9e27a5114b89787b8e750bc2d25	1	0	\\x000000010000000000800003d228d587c923091732f720a2a13624e2f13dc36946f435d2c2eb9d33e0fe957da880eb37337455a95c455616350c347477537c07313f7649ee6d32822590e7b95a9a026e436c1b48a5b6f77c42236be33abdd09f7759313f9f505745a392c9dcfadfbc90ba36895fc10cb1a78ad29357ec6bb688b01bc110c8a25455171e1e9b010001	\\x2751e0e3a7b3113e9d7f1d90ea6bdd7228cfae7736f7025c3593f1213d99f007701ae5c1ff722765697e01e739f5fa25863b61c37ff7f4658473b896ced2640e	1664533964000000	1665138764000000	1728210764000000	1822818764000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
150	\\x5e89c29b02bf28e3478ee4704fc674f263f361f60ee6e2d98eece0ded8559076cbd2366bbc8944483c3583e0bb445dd0b1a9f9aee0157735daf8b819499d36e8	1	0	\\x000000010000000000800003acaa6cbd31e73f2971a3d6e187461ab43d9d8891565038ea9e7fc436a4e15b1880222556d2153046fbd81ceea984e3fc387af2d91a00bcbb140aca66e4ba4af10046a0b09bee25afea75580e2e2c793fb8f72890ab4210b963324a2a6efd677fc9f828bbdd4b2784c7e3e4863a0a852c97d38a06015e77d7c301c721220d0e85010001	\\x7f9c0e306ed743cf6c4c3a9f4785a807602713c278da4c3eba4d476362719ca5c7cbdbb394083503de0b932a7082d0e19810a9f6c42cf2d296b7ac12ee320d02	1655466464000000	1656071264000000	1719143264000000	1813751264000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
151	\\x6229da3f7e0f6cc24cf33f945ba62262d2db4bb0666630eb58f8356c6ef48ee4bb111cbe4ff07b2a88e7cf7a184a61995738d35a4c8078eda56efdcbf8b23d1c	1	0	\\x000000010000000000800003da4868f5bdc23bed158c4e7c8859afba6c909d1b4c654d2c8c3799104cb0b56443eeb2daa8e0079756f8e65f660eb827f0d375a7102b3ab52c986e1aae3780e1ecfbc3faa06973de8b7745eb298902e27933f5fb3c1a1af651fd248f0a0101533c61fe4107637dfe647275b5c9d4d7bdbff1d9f4367d4858e9f01821f83a6fb7010001	\\xe11a3f762ef4f0fa7724660528ce16bc0448f49bd7bccb49a8c5c00acaba6213a60a3b4d7eb3c61c2580490835b6f07f01b17d84fa19a56d7a427a4df2de4508	1651234964000000	1651839764000000	1714911764000000	1809519764000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
152	\\x65d5a4b73c69bb2ef98b23825cba00254a89d0d5f2111b4fba0b5cf828c6e41234a12fa6b48957ccb203e729c08d296b91a2b55b9def9daa003bfa0c5af0d60b	1	0	\\x000000010000000000800003dea4f0e42b8070f0b7c3321fda8b34a9e1950f5d35da93071449645d8d261b7c636b62df8bb054034cb201806c2311968e8e494ba0e9532c4f0b652dbb36228820f295afa890c93fe463dd0b7aa29d2096720c8ce1363e04659599e212a89509e1767cab35500e181ecdd1ef3f73701b7a159d66def0a9e319ac7095784f4d67010001	\\xa7a39a1e93a292bed8c89eb707d145ac943974fb872b019a81a15d350ee0134870be21f548ec9c97bdbda115b73b45e22447dcc03abc25a44db027b90b4a5903	1666951964000000	1667556764000000	1730628764000000	1825236764000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
153	\\x68f587df2d5b809678d292966371be9e1cc22cb814f017a6719bfc21a13c46a9eafdd05d208ca8efd1ea99193b44eb72c9c8d679d2738c13a87e193bb3e45a10	1	0	\\x000000010000000000800003c3cb9ccfb48f15fb8b214cf388713bf0ede8376c5378615aa6577c4393a90fc09c5e1e1b8d5f9094aff74a7f82fd599340b14869713459968471118172551f2072199aebe2607fc0f38c4b9b3844efbf9218f1bc10474e297a4a5c61330bcd8a1dee91ba6a3374900626ffceb42dd63395ce3e509b8c33773febcb291ab1d95f010001	\\xdcada3105e85a89cda6908af432d625d9c8008bf3922a6fedf2dff8c654b3b9ea8d5c8d21cc085755016680d04ab7bc418c6e0b03f21dcd4383ea47b8dc9a104	1663324964000000	1663929764000000	1727001764000000	1821609764000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
154	\\x6909f48f225625d344fdab1903f4a593b2696fd9d3c3c1871cd9408b9a65952f999b4796a288adaec97524039a8841b719181ee7df6648132a7867f35eaaf3c0	1	0	\\x000000010000000000800003d4b99b99abebfc772a55e4549505c135312e8ff19713dda806b438f8f85005a3d5a4260f1e9a8731462db0e9290a4833b40df747538659db8c281223f26ed66deafce80b58e6fc339942f88ee0d402a4e1b508ac03095cd62b65fde9e2575ed5f81169fbb61ac9094bd79e8143a97758f79d79283e525abc1ac7f42dbce5b079010001	\\xedee0e8941d4fc2d614dd2b79a9912fe6f539ac61f4e6521ad37a9fa02e32469497142f16ac69c077f28aeca97295c32aecda24cc333372ac1e19a6b492e270e	1649421464000000	1650026264000000	1713098264000000	1807706264000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
155	\\x6c2dc9939212130391b2a0c7b2d33cb4281062283bd7dba0f0682b9ec9d3527b6e6d2f78b223f280f8c08f0f0cb835be6cde5c32547d905566f609ea5c0b3846	1	0	\\x000000010000000000800003c9e83c0fd843d4c8a469b903b64165dac19d3f2ea6e6993ef138cb2b2b63c17a0be59cda36285c73afbf8fcd15eb6a88ce1e30df775627427f17f577de0a08500449eb39e159b0bd66e7531110bb667a29c6b1bfdce9730071fab36e821d1650f8310670b232ad2b3647d253b7de071774e08326bfe5ed0d5f5f24e7c22c3747010001	\\x3d29dcc1626eaea1fcf8075e91d25b23f752b7cbc0da8f4a666a58bec8c0287eb1bd836096eddd23471e061ef9e9ba3c86b63eb1b515e9c14ed5923982e1c40a	1666347464000000	1666952264000000	1730024264000000	1824632264000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
156	\\x6e1de14d869436a9c795c98e06a60923697d96ecee7b74d789f81c234990f9070e1c74066b0104efa5cf41293b36f5da0aa03dbc432d559e3f3b8582e30b260f	1	0	\\x000000010000000000800003b7511d6f1698a01725a145b8e9a4f44626f34b8ea4661c7e8e2ef3f2f10da804e3f483c556ca3a12820c099a405bad6e69a133add7ba3756114ef64bd9b1741c5ad9ae9dcf7cf027d6c357d818e370128bc5fb599ea013b7a31391b9aec7afe024f2e15b9355f31f05b83da52a2b4b9d8b316ccff13ebf9eeef1c86cf9fd14e1010001	\\xde37c0447f526bf23ec1ecd45ae35740331df035cc1717cffc83fef3ad3e63049b96e60344db2815713cec10060c769d913ea45d7413ce4eaf100a0b32185e08	1674810464000000	1675415264000000	1738487264000000	1833095264000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
157	\\x6e0db11ce4f9b9aee23d6329705376b9a629b96d3b46e75e9d9341afe1088108da8121d8d3effaacfff4739ba3141cbea70e5fc52ccf1cd97cf6282c1471ad47	1	0	\\x000000010000000000800003d19f27bc424fd8dfdf81f73769fe66b74d073e44cdd727b1be182dc492a8a1501a4145fb0ac3cbd7ba40f7f95992887e0db8bd35f4c391e3e791ce3fd96c88dddf42fcc02c88fcefc0c3a87c780b8c4b1c15f6964b08e8710899f6456f54cb3ef74079547b4bb5f7d3282f9a195ea9ef3d93d5d5ff039cb30a0a7afc5d789dcb010001	\\xf4d11b35e1bad405668787be7ac181508320e88eabec8f035355d6c59ff0ba93ed3e6e5a2089090a5a1cac2e487f3b36cb6306a8b45b8ee25415f48b78a9f00c	1662720464000000	1663325264000000	1726397264000000	1821005264000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
158	\\x70ed4fb4edad1d0616c12391cfbc2d7a99d803573dde540a7824297d1673e6fd4db07364e47b17745dda9b579cb0b76719f169a042fc6d538629259e08d011f4	1	0	\\x000000010000000000800003c76112ebbd19432e94b149d80b4db7beb595b9d07c4fef66fb1165a8c050bc2fee0ca5c215b57f0223dc4e9ca0753f87cc6f8e1755447bba8a50989f21682fb5a34264e0ca98b59461cae33ff801999c201dfdbf108a1745245c24295e583243894f578ec7c3dc8a8cfa92f5f3c7c490fc834d4ae5aed35f86cafda7dd195aed010001	\\x40212f305392e99682f9a24abf3e819eb09ccc9f374a73036d1a321f8d92aa7ca208334ae581204ce592122a9493309c3831e8a5a6de631ca769a016f740fb08	1653652964000000	1654257764000000	1717329764000000	1811937764000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
159	\\x7039ee5df43449297251c95d98a94b6f7f7f459534f2d1ffbaf3ed93c69cc55a937ea5041ff8dd467c6bb2d86065c99d03fb8487a1f882d03184e29da384d09c	1	0	\\x000000010000000000800003cf7c689edc1f10aed3582f16f18cb9e4d84643e5d513feaa0ddde394ccb32977c065000393230892fda32bfdd4924d33a9ed817c0c6b5982e22a7c3ab04bf1de09903985a95d3a6c6908ddf2f051eadd94d6186d5d70f5690b7ddf07c385170a6166a32403104eecbd78e8cae9a3019982da5ea1729374d67bf2dee538ccd3cf010001	\\x8b72ba18aa52c50136cfa5f23775eb141ccbb27901b8a0f63959bd40bae459ca2824e63ceb4a5f836368e4cbbda148aeff1ad0f8b9b9b571743ccb11b65a6b08	1667556464000000	1668161264000000	1731233264000000	1825841264000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
160	\\x73e9be0521f6631b90370e6e5fd13bbf560c04f390b03ba24e226598672abd896c1f30d51a60b7e8b5409ae22d63167ca65a15e4cc0e89d21e1f132750791f1b	1	0	\\x000000010000000000800003be9de1f2c7e4c07f906ef15ad7b9342abed3e13755a16cafc126759e972e91cd060166d3f6c05ecd8499e1ca0f9a47144cd364e09e98001cf77c3f7ce4476ec18ca21ae8cd773e43a87bc7a2ceb056d2e9fe559bd67e6220c99a18790bfbce3e0cdd62b4becff0b09d931bfa6db5c2981adf54fb091b236392f84372ef4156ed010001	\\x058ef5d851d4d766edb14c6957a2e0c873d563260e5261e76f16d88f4c4af6937fc71dd358092c7afbea0aaaf9cd5031680275aadb2fd694e91a93bf43c6c408	1652443964000000	1653048764000000	1716120764000000	1810728764000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
161	\\x733dfc8c566c99e89e5e4ae2d6485165641c62608a8eb248b3ef7b921f19ea08026ad0a79f82220126bb68065dcff6b94491844f1d4f0ba7bdbe5feebec14648	1	0	\\x000000010000000000800003f1cfa577c5e0a7af0b6a014f067aa8fce7a85b7c094cb600d271e09cd01dfd4f4ec16dd316252c0a5f5a98813d8f8827d1a8eebb65acd5db057caa7af1d494e71feca4fef53ba23f28533745266df114288550b7b240ee320d8f91fa97b122feef1cf7d65d518021e8cb5ee1666b461490e39bb02967bd0f0b6db07d83b7ead9010001	\\x234e0e5e4ca3b7b484b9655ffe5d1751c4b385c74628a0f646bc299b94e473e1d82254932624d416578d1618936c4f03e19de2d7035738eb599093d89b466d0f	1653048464000000	1653653264000000	1716725264000000	1811333264000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
162	\\x788987f4d0f6e4dfbd11f4e2a2f684404072d76f63b8d429bc6e3b45b04012296094ae85fe82af5efa04d01e6a27652b3d71d77c391564855b5c7374ad0dcdcf	1	0	\\x000000010000000000800003c9f8c9f812c586fa30a01efcc05ffb7623b879cdc2bf6f614e7625527ccdffe213373fa6394f4a42a8c2c9124dc858941d503d1b631fbf19b6183ee525f8f221a0fa695a26f972259730007b2b0b64c495164584319bc1d4c9e6bdaa5dca2c0442914d4ba950fbd5e51ed7199dcaccaa791c22f12b8d9b5d24848391ab61627f010001	\\x1b851dbed9605f2ec8c5931c55010d38270275205d40f5b509e8d7194734fecc50d186d30b134e9f14967afb9ffd61c013706614108e282513f380f0206aed07	1648816964000000	1649421764000000	1712493764000000	1807101764000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
163	\\x79e576cb2d9cc0e3f99da3ca871fc6196f4f8db1662048a90685b9cb25ae7d062d1d52a2a504c36c9452dba1edc4d6da927ad4ef6b9831b2c363246be8dd705b	1	0	\\x000000010000000000800003c7527d64eaa0214223280342c1ba21f3162b890d05e84fc272aa48573b7bee06a52a638d2888f1d14fbbff6270e8033ad00f16645ce2c70ea61018910af02055c3b90760b6faf7cde85340e4ecba403555462af3556442de77052ad05438b8903a9daa86fffdc03395bf673cd02888c3af015bd2ee876faf92b9bfd729644a0b010001	\\xace2d08879d4e6f722b6160a57cd1accefb0aa84e0363772d71c3de20ed002a00fe93f8d1b34fa4c8b5b78fb20a8b3ee7d3f2d341c362bbc28e0d06df953410e	1670578964000000	1671183764000000	1734255764000000	1828863764000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
164	\\x7aed0f6e5fa105523fa72cce095a0d7c118dba9ec520ca4d04238bc7bd8943d3fe3be45798808be4194f74a61fc13323ae605c3adc43a4105024d114c5ed3911	1	0	\\x000000010000000000800003b6dac8fbc605e481705af1db48bbf9dead77332b10682fa447657d7fc61fa49b56e23eaf7928f5c92fceab8677b8d423f69d95e1da401f6180485826453fbe1af156daae06708f47c63ae8a7c5bb9c42d6bd74f304a4baa383755585fe64ed7cf32beb0206e6044a29a17bc68fa747171cdb755ba73e62c3f1c990dc0d302da1010001	\\x118743021dd6953d4f3e732317825d792811ff03103f7860d32c1cbaa47ee0422baed98a2e5676cf02ed056f4c86585ddc1546a0639046c6dbeee5205d182406	1663929464000000	1664534264000000	1727606264000000	1822214264000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
165	\\x7a0908af6103ff6d867a32ec789ac83d149495d694bf74f93840332688329cfaab443c91fb2879ac6c2f04c42e88d237b2ce43412511f8eb58d79ab0ada7e3ae	1	0	\\x000000010000000000800003d337c96f298901b6a6a4ec6b388600892cb53dc430cd91c859489ca57e4e847cd616311a0c3933d70b48dbb86c86ba5376ad0cc26a5f41a70fef9a8bf30304a15f49b5db5661541fb727b9fd3b94f04a83431964f44250440f9197994005cdb5e27c5a3630642f7c7795528036c465a52f17b9de15cf3696020921e821bcb469010001	\\x8fabb43f5630a0f8df85249b9c76df91da5bc1496b202dded1a6abd93a3e040a2590ca02d400afa3a66aafe1b0e5c6035636bb7149f70853a148c03b6e52080c	1651234964000000	1651839764000000	1714911764000000	1809519764000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
166	\\x7e0d4b897ebd79811fde4a4a331a8216bdedef93005f7333a534a1460ca4681e1ccaff3d9370970293e61ea3e88b73c7d4f9ad662e0b182d907ef369a2cc95c2	1	0	\\x000000010000000000800003cd891041542ff7b7f9724ecaf350807974550644f028a5b151929aff21a13b6531228b2fb1e99373e4c789872d01b0ca8b7c83909edfe7cf614ac2014540c0468f74ef1ed15c804bb4a10f3e4fe759f70f5e7db392636f18e2902fb442b76e16b56407d8723fd8ee1fe7e1a90442d1a77e625abea71876467e7ca442ba01286b010001	\\xfd993ab38d72bf9695d4707c9278f66075d1102ab0c13fbb3cc654c5f8051cbeb6b6cf9260f89748a057c8a2545d98e70aacd6f7a5787c9d2721cca635ba1b05	1669974464000000	1670579264000000	1733651264000000	1828259264000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
167	\\x816997b3347a40e39b85bb7e7ebeccbd817cfd6ef2b2be56b36895ec0cc57b0e0ca46acce2d3413b45e9205aedb30dabe34f57775ffc727c9b20da752238ef15	1	0	\\x000000010000000000800003b61db849b8713c92e19d6c57b6cee93a988078d90f3f8464242446b1f32a5c208aa5c7b5feab0d043a9c92b3bb20d33687c21e749e46e4660f123ab77bcccc1ccbb23079129c9ba8f749b4d07d082c6c0e3ec1e88dd6899cf09009083095a8ab3eb6fd4c901a36eff416d31b23421bd2199d817753731c198308dd3e356c3be5010001	\\x8c3e18d5b94640e476a0644cb41ea528af204d6ba96be26d4bc8fa5d917d4e0cbf1aad3b57d480a2cdd374fe32b307258efb1b9d8d5e718224f2c88013477305	1672392464000000	1672997264000000	1736069264000000	1830677264000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
168	\\x817970e4acdbc95dc38186d0a2451d68cc07f42747476a64f9782d998ce04aac9b208c3e7f139b55bb5e28f2f0d39ae6dffe5b09126a926d8ecba68ffcb9a6ef	1	0	\\x000000010000000000800003a4f7ea1800ef7466f28628bde10276f64d59fad022bd85f34a825a905a5b2a6d7dbf2db830329c05403ac29e29d53be9ccaf1c6ad1fde174e84576271f1d3d6756a016b62bae9cf6d538f91d470634500c34d85839321f625924d9f2646b9db24184f1fbc0993693ddf4fb49587a07c24b20d416f446388118e61290635c846f010001	\\x0a506411ec0f5d5bfbe1078412badfb55cfce964489409f2d956f148fcfc31d842bdb6d3355079b2b51fa05601d9668905e5a3de769db9eade0694661dbb1201	1671183464000000	1671788264000000	1734860264000000	1829468264000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
169	\\x86a97c04868a2e81a5e3d6c75dd8e5d677e78357bb97a73614006829f14b68dda8dfafb7c90cb83badd74646fd2329deb23eedb6eb1cfe9c30ef9e9dd764c3bf	1	0	\\x000000010000000000800003b831256a948dd4c2702c19579b45f7b24dddb499c8ab8687b57cbc84920cc9f97e08acab4e1651edf15fd8c952b6111ab6adacc6b74a01bb211129cfaa26f0ff7fe1dcc5638c52b6c51a1b715fa4fa41790b4aebab1e86410259ed092be4492762f54915e0a4aaf7342063db44b0af67bbd9825abf3c587f4df4c73a0c6e74cf010001	\\x917431d136982e103825b19dea501cb21ceb091268eb44ada785f063babb50064a9a57116c6bd69b90e67c9d6e8efc67f5fc1e966cbcf5747c35e8bf173d2405	1658488964000000	1659093764000000	1722165764000000	1816773764000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
170	\\x869db1fe7658e6a555c8974907dc6b37a8974ece44d81c5193eb41e2aea70cdba72abd0ae551531d01116a4d080884593bd2d44eddd5171c800cc27e05b13ec8	1	0	\\x000000010000000000800003e251ab8d4c639d2446be799172baad31b1e08015ad61273a2eea7816770c93350864db06d6be2cf47e9b46cefb9da640363ec0e757791f49497befcd0ad183bb4a9c8f438608bc00c836eca2be3648c718f34cad377493fe6c7d5a1c8e8105c6be0fbcf3ae63c9346397634ac6f3a3749488105a2b828bba33b1a7c394371243010001	\\xf1ea4a5d12bb140c4fae7d15f1a61bacf9c787905eeeb1d8d94fdd61236bd0837f61564de2c5b543987a60b5b4a8f2352a1712c4a368fc78a1e2445ca5732b0c	1652443964000000	1653048764000000	1716120764000000	1810728764000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
171	\\x8a011466a63727bea7bcc1f800613016d5b2c3ee5504d20dc92b5c5c3791ab502abd9b8a0bba0f579edfce431382cdde185cd10b7478de08d1a6ba87ae9fc0e5	1	0	\\x000000010000000000800003b949d11c908ed3a43841414991bac4ef2ac4356bd3b960d24cba005f5bd83922af5afe031c34cea2258257c23e95c9a2b71440e5259c2e713d1ca4c50c060011b7f306ac865cde4a1bf2456ea99ae8d8ef2b8256894499d41c34b5d678b5aa251341f9825f27ec27df0e4797b1fd57d00b5bc682b5f0133f345ef90c9b223f25010001	\\x0911ba1d3852b3c9cf1bfd6f88e6a32ec12fcb3e4d9afc27a195b9fc7b5a8997ac3436091068e50788ccb530c140efb4dd9332c7374c960041cbc844d41b1206	1668160964000000	1668765764000000	1731837764000000	1826445764000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
172	\\x8be119c77d5ec9094a6f77152d49bf3e28410fbb90c7ae2a6fbf14f56b60cd27c2fa6884a227c6e9ee321087c65dc703d270e36715679b97b0f590833f5abcbc	1	0	\\x0000000100000000008000039d3d15bca5baad9b83c33b9b4172e7c3080a7ae70e98cb222591b7b52a89c9ded11c2e51c5a93d27a2804af1977cb176ab5cba6bfa99dcc4e897b94ccae1720835479b9ed8e5a649946090a6fcd5db3e8e095de59c6821876d458b955eeb3670fe2e691c0f9079cce65c0228f81a34ec8bb3a4c16e86586e6a8cfe02412ee219010001	\\x098162e4a148685599c16fb41f54badabfba9a42cbe3df6752ee0092ba3d8180c4b9fff2cd08440bb7f6d8099f6f437fc93edf9e5ef8892206e84aef024d0e0e	1650025964000000	1650630764000000	1713702764000000	1808310764000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
173	\\x924594921878b1e5c65c3567c018205d8604db5ccafa0b772e4f8edf9b3efca7a8fb74cf73f5894a5ad3f2fc14ce5eca0a2ed85a3a4bd705e445dcc2764256c8	1	0	\\x000000010000000000800003e5bf0277755d3e30ac85406694b28c2e932448bafb9c37d5b6c27fa0264d6405365ce876f967456ac89c08348438a656b422bd5c7560662ec0963d03d4024702db1804db421f53161f73683c641a32940be6ee9c6f189ed1ac18534de6022146e166ed72b4e5c92bb3a54cf32b3f07ae0e542872ca806b14871745179772a61d010001	\\xe01c9f1a7d1a854a2c9373a48a922b5ade683a7c563099a3eaed578a0c0ea933a58d40c9197cfbfc6e4acc78a9d2ec351d62a3f226859559236f1ef05e3d7906	1652443964000000	1653048764000000	1716120764000000	1810728764000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
174	\\x94f9c794586aeb0c474978ed06944f8f90166282b637bdb23614e79002bb9a7561c4b8903031c676571f9d5e90c3b686dce8efb29c415dabb339c34d33eb45e3	1	0	\\x000000010000000000800003bee733dd8ac4fff04e34c56cd9ecb1c9f4142b9fee567951f4fcd381045ef5f54f364a866f5920d5b853a2e7cc428f0c7be630c325489d6aefd081781d4acad99462e765c15c9bc42d95d8f4ecfedb802d4e7dba1ee75a0b2779606026f8cc3c4298c66342c09dc832930cf8fb44b6639c094158b908ce61d8032e42fcd2da4d010001	\\x44e51cccf6b126826b2f01bf422ebf50e44d5ce0af1a3efd5881ec90cb604e041bdfbd8f94e36842894856c59f0f2a19e538d671b074c98ff5223d9f306d2e06	1672392464000000	1672997264000000	1736069264000000	1830677264000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
175	\\x940d05eb5dc1d90d4ede64eafb8f9afd44741a7f6b6ffcfbb60edb7848d0590866190fdd9d5a4ce2094ef899e532e22b6d475bcd8726055566a12e331138dfc5	1	0	\\x000000010000000000800003abb35110479ebcadf4fecc89cdf1d0e4940304ca3419e07ea16ed078c51afcd82aea00e70a6ed4d43fe2ebbe37e5353c2c88342e9e204cab6f557ecb4b0fe93f9337c06cc19a49e995928a906ab308ba7f4cc98dff53b4a5c0686f3341743ecee7edcf0e5fc79c532cfbf3e15b68b4e9c2fe8083819a38755de6dfa8ea278bc3010001	\\x513670519ba5757a6f72bd0100d770cc1c72f074ddab0e93f7ba35e44db295acf31392320d59c55cbea98ad8d789f2ca4f831f349892033196e8cf32e3dd680d	1672996964000000	1673601764000000	1736673764000000	1831281764000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
176	\\x95a52ba8a492188bcc9f7e30cfb9105f8c908802887006938a7861111890aac8b4c45358df8c0a78e6318e303b3023abf34704094c3e5f54f132e7e9e04911bf	1	0	\\x000000010000000000800003cce5365a2aac048d445d889cb2fc1204df41c91cb615535f1da441150b648d3c174dc14c39822dae6b5aa4a632c9e97acee8d7adc1e5ad26abfc4de898551a0fdf2a9f3fb49f7c9ba65d9a2a0114ff5d768d923b7a574973fae1c79777d9dbb92dd0e610d1405503ba6038d6e02e08ef12d0db9a9dbb94b0c59967f340e9d153010001	\\x741f95c630031a31993a7a6145963af3d8151cab94ac8f74c05b69119acd84df5f7b34cf646f065308c35aaa203aca1cc1f473972c9ca420d43523d25f0a7405	1660906964000000	1661511764000000	1724583764000000	1819191764000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
177	\\x95c12ab32bb2c71e410a8fe0ed2560a385274841f3b3d38300c34dd8b60ffcfac1582a21b1865c27b2a6c160d1f96149e47c602ce07812151f884d0b6644239e	1	0	\\x000000010000000000800003c81fa4a487bb4651a8e0cd5f3a5e3afd02c2321644da223cb2935281e039c2d47bfecea2cc75b901a32ac94c890dc5247ee14df08f749cdf68e3260387d511cdea3fb69f8c10742149db789813da3e6bc9faa6e08743863e4998edc02a495bad7ca0e76a3fe9bc3fcc81e91086c0661340ba8ec79a9ad16675412a15309dcecb010001	\\xef5ee23ffc8a7dff4b666b79035065006e540be17ee796ea9b29adc1a1620ac7b5c0634677771128db298aef10eb883d13d90f98d7552a42dedde7b9a95c1c05	1648816964000000	1649421764000000	1712493764000000	1807101764000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
178	\\x96451194e46bd1b1f5d325df5ffa967dd6eee607c6407962b7c8d6c3d62c9780891780b18ee75779fd7de76484f2110bf876d1797e517e395caba0d18f9b3430	1	0	\\x000000010000000000800003e65c4e9c87a8d6e4978b63385b0a02e662a49f787901da1345e1737566bd166a9752c0e85e42664231f6eb73f25e75f23ca4850aaad5cad2ad628925c41b3cbc6b74712c21278cefce0b8258d7b6d0cd511dee87f3390fefad1e760554f39a1ceb3b076770b0760fa61aebd96995b1b69b549db02c4dce76e831509584ba906f010001	\\xbe86dfa3cdde403449552a0fc7f36c0c1827f1fc440cb61ed0f0ff179bb9dc0709d1a7e9add3b7c012d13cc1a69f99dd76e3d74e4d47d33096d2e146eaa99b0e	1665138464000000	1665743264000000	1728815264000000	1823423264000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
179	\\x9909f34113fe1c6eed3888320dcc35804f8967619155d830faebed29a280de67d5c6fb1090af59b50d1a2ed56a252c732b9160c6dd0c6531ef16aa7e1fcb0c7d	1	0	\\x000000010000000000800003c13d7e07c3b26df594a74ca2dd8ca4e69cb607a0a67d87d221bd182a96b81a9b4322854372df1ce130b0db6ae6056b9c7bdcc0aff3bf1f3130a37d05e1bd7d32d747eeabec0190666ed4fecf3e97c99a4306f00cd2f236bc4ffc10cec79eeb31c3d13a0254854f9ddf8ca5601830e3af82c78b3c716f552829c2549aa8ae3be7010001	\\xa846b0f77ca4535ac9fa2e9beb681c0e1777a95b008a435e59179faf58966bf1daca1e7c5cc335d105e3c23be05d4a0192b1a9bab5b54884f4668e818cc1fc00	1663324964000000	1663929764000000	1727001764000000	1821609764000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
180	\\x9acd71e952f89681d6d9de14a26277ef62475e4e7b2bb2853ebfddf94c6f4ba8928ce63f76a8724a3ce7b1e9c9fe1b19e0fa7a89b197f915c20bc0f23bc13884	1	0	\\x000000010000000000800003e7b3c3ab9945d8b78e3c6f4ed8ddc03269d90fc55b7119ecd03d5df4309794137bbca70163324f77bf0d80488f14dee134998021be96d65709664c1d030d4cfe7ac5873f94c6e5eb29bdea560d7d8c3b60e2e4def1d1315a415aac6a06b31431c2eb762882db40de1aaeab594467025d60ae974cf1099baa0ba43bb2b5c463d7010001	\\xfff3d4a22765283924c8663c63bcff2e3a2e2f12c09b752c43bcbe4d5b65830942a662f97127efb30125085811c80abbb2df7aeb2016b9e0c2a4921a7bec9c00	1661511464000000	1662116264000000	1725188264000000	1819796264000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
181	\\xa0615f84deb717dd5bd561885abb75a3e1b325d149fed861b9f060602ff140a57aa956da2a31705fb3c6c035601d3c41b9731eef2e1a378268e71875b942d8ab	1	0	\\x000000010000000000800003cd14ebd8c274b216d7651e08e57d80ba21178cdd969d180e5affe7e86a0f0d890e9c2a1c3f7fd09080f893470347c6a0d4a793844ff77a456e3b64caa9db166735f9cbecd225b0a7b15606a10df9740d1ab2e8ecc2483e1cc03790bfa124302cd6d44ccd4a16517a577b4a010277a0ed3a4372a459790ea67054b7cdf9a2a0a5010001	\\x5640d453ad88eca74cff0aba668245860ae2b09edaac6b59d3e20dfa85a12a7572a7f77cc4a00628dc2c2828b194675793eff7f49236af1dcfe68ef475b9c800	1651839464000000	1652444264000000	1715516264000000	1810124264000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
182	\\xa15992f1ac835e3f64e4d86069b6e651dfadb857bee49ad0faefc8c850edde26e89f9970cf69d867efd9a142314bec0c2901b081c1542da9308eb8d51a5eebcc	1	0	\\x000000010000000000800003a6e30373a0fbf22fab56b0cd7b6b7f2c870ecfc6756e5c2077c7971aa62d33a569f8d0c8f88e3c9bd15aa01abf5fdae69994ae717a9ce3aed3adad556470c32e666878cd9ba181f54283bbb58b8a0914a038bc89ead38c0e9a2a2ae6bf73cb38eed451a0705f0dc982ec0de385efacf918665fbb15728725233f9184ab74f101010001	\\x61738cf545e93e651490dbd6edc515b246fc64175e6ee6c9f668eb379316dd80fbbaa9bc1452c3807049297d2a24685f6ad7dd2e783496575c9eb9a093aaeb07	1661511464000000	1662116264000000	1725188264000000	1819796264000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
183	\\xa3119b732e8e7f3d1fd5881e67736653e7c6a98a9ff1661989cff8b06a634a6ec3e499ecb1221f263b039133e434a620fb96f61c15c996ac1d23d174d47e0a9a	1	0	\\x000000010000000000800003fe18bf30328806ac1f2f7ca9e94555cf90661cf9d23d2dfd2e5d7d888deb9ce9af582e81877b2379953a114125c4e41a2ae7d296789d1f7956237c02bdd28be3fcf95ed5a553a0dff254da02131a42d043a0c6a3c531ee7f98f4fcccc689bff643cf928db9b9c6e661bd0e07cd14d5bc066a7c566da786c441df3cda06282159010001	\\x80a480628645194b638df99d6cb88caa42d3ea4a9d68103c8a167d4da6e35fd31829c660e879e1169828cc0dd0a8cf36db9fc43d2439ae604f7ca513b56ab207	1675414964000000	1676019764000000	1739091764000000	1833699764000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
184	\\xa49d683c4597d7f93d98e9385a894f6146855ea51f97c5be49942e1b8aafcc8ee9b289dad00f74c15b7c95de5f6926e1a97c92c92392eb739bd9550572fc4eea	1	0	\\x000000010000000000800003bbf898c132ae0ddad8f561ba9592e5109d6fff6bae043d86f10f04fb39ed1e28206f818ba74fab51ce5a62166e82b75cefc35be1b15034975a893c452f4c21cff5beaff7affeca925c6be65dab44449413f70db7ff8d41fafd231be5e52647bedef496125861d6d544b112a253c10ae81e8cb0742c7b207f20b422a69e6dc165010001	\\x58910c451bca29405b251ee2b4bff136313ca45b33539e14e266c9ad67c76734ac84a8e4f981fb172e71af9a925dca14d9d2dd4919d5a3736430580a8e4c090b	1662720464000000	1663325264000000	1726397264000000	1821005264000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
185	\\xa6614c3798f242d15e7bb8d83772444a4c57a7d5418fd8625eb1471d8f6d5452b6f21c3964f8e2f7d84c05f71d8e9cc469c37ba774d822abbc290aa879725c06	1	0	\\x0000000100000000008000039da0eec212f907f3feef6f068b81698dcbfb473ab7aa1cfedaa3d2e5007acfbf1a0a66283190a3ceb63d9b9c5411bdc53b23c481287d6a764933c2d30654ccdc74dcbc89a7bdbdd3cd2d1bb9894cfc82670095089e9d8c63e69c9a2a258b4ad92b53371bc9d111d51a2b68b63b4daaa0e5f233b7434b35787a4a9f9a660432b1010001	\\xc407616302a6bb5544096eac311a0a39f972f7ae6280656553a9dc6598492ae83a9183244a6c7d14485a32ae5140c35813c47755bca5d13930da5bb9955d3802	1668765464000000	1669370264000000	1732442264000000	1827050264000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
186	\\xab99332e50c14e6d13492868e42f8ee45786fce9ad1261c4725c69c2c79a6abf75d6f317fd524078bab419f6894e37f3510b32a6e44104b3f580ff4e3cee23fa	1	0	\\x000000010000000000800003c6fe932480ac67144932e163cb56572a6a5e43a904ce5e5adcff548ba5ea466e13d4fae50ef19003e81197a6447a3126a8ea6ed37759d413834a3b911a57e19cee6efaa2934b612adeda718b2a6ba6f3e5b44606308b843e13fc80e7f8ec7de2ad304fcb4e1f5910017640bd5a02df9998abc3c4115651bef16b482989c0ee3d010001	\\x0496aeb8f9df56ef31bddd5f80b051c6010643c99c561fcc9aa8ccb6df401f70be873484b884a231cb3eb82680f52328857303352c7cbd87769f77ec4c171f02	1669974464000000	1670579264000000	1733651264000000	1828259264000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
187	\\xae61fe0280bfed0c961580a42fe6c4928fd8b9724c3b857bd653e316361855796dbc5076902456723ac752d0dc2744ec73b7bc22b3c2a5382997837795609d5b	1	0	\\x000000010000000000800003dd1560284b7e9487fd953314dcc69c621d7c4e902c3bcc22ffc88e03e999ecca18e76274003921e476eb78a9084f6baa71a4fb3d34e83da8745524cba2c227d896d6208b8e198d87f64d72ecc7434f6709d1f26ee8adbfdee0c3e1d063ae61e794607a7708d6a24a0ea86641ec66ea7fa5d64e9ae0ad57d8a45ab7e6e87dfd47010001	\\x5788ccf94a3bba4009dd97b5859a21352c5506219cc56e30fc77f8e10e0fbd97feb03d7ab01544285c3cdb6ea684a483a6a0e908e4ce7e98486a8ed3e2fb1a00	1651234964000000	1651839764000000	1714911764000000	1809519764000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
188	\\xae495b88cdf4486b4e5cfc01fefc3963324cae5dd94d61ebb22b35d6568f906385bf36c966941a3c70b8440f18edeb23a90e4431d123c30f62e1f57c48d35bee	1	0	\\x000000010000000000800003cc0a5c1e2b05d06d778133d38efdb017cc9464aa652a4726b12dad61331c541c874d4a9e3c6f3ed55a9f38d7fef803a62136a21918722f21ae0af7209f00660a18f684acfd7f2b7774d3d5628621c85179429b827886b27601468afc4611d14b66a4980bb0901a7919c0805c6484a3fffa3212b464f7d582514432b7e2ef0dad010001	\\x4b40a94c43f9dbd7552cbe8dcaac234bcfce2d4dcc53d55b6d43aa45f935e2caf78eaa797458d189278c4f75312bacfb1d92cb2e466068c5bf15a51337a44c02	1667556464000000	1668161264000000	1731233264000000	1825841264000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
189	\\xb0fd50a0cf9ec29c3cec9cde128d9068ec8349c6b5d0f1b217f396393eb52a0d47bd989c4a928e72579708ae538bd1226c986fc66ed3e1c134d8155298e3d74b	1	0	\\x0000000100000000008000039c3818e88c9943787a7701395df562a62047fc1eb6dfd2021f34c9eb682dc083ea3d5ceb6c86ebf6bdd7b5f7e80b90a2d6c04a3760e81c2e3beee8adce31dc44b5d499e36edf3110027be1558c4a496208ad8cc6e941d1ff958880dd1342c1d18c70ba6322224c75f2682b0f8dc1a094d27713a9db58b6aaf3e0712af7c1693f010001	\\xb65ba7d4358b5782c4712339f3b0f5602554d4e2714c437ab4005221bad779679a2692841c8dcb3fb65a3e9d95f53175e8e5d2f172997865501bb4fd28c2b808	1654257464000000	1654862264000000	1717934264000000	1812542264000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
190	\\xb2f124a18f2937a51fea5e781c532fe56b20bdd165ec5fc05643f47456d71351050215bcbff020e735103f8826131bd8ae4afe3f6b7d03c280d817c7ee80982d	1	0	\\x000000010000000000800003cd8d47b73c4360e11ee2c96c145056b0bed0f76acfcace189c98f779bb49a6f02b0e354334bb0fb60a74da67c3047214bc68760099ea0a43e272a4e1a3a982ae82b5eeecd7ecb7da1c23af138c68902fdbda47a242d93a7d6d1e091d75812b3fe9899da9ea3d61254bf1e95cec5604150f7ba099d193fc1fa346c39690104ec3010001	\\xcbfbfb644bf3e55351de02d11c313f27dda150e359a7227f8a09cf581592908e904c41dbd214b63986306be6669f0875155949ebdc99e909476f03faf96a4e03	1679646464000000	1680251264000000	1743323264000000	1837931264000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
191	\\xb3715f085a4df5fb2231b0bc8a7d5f460bd5580b0c9b404ccf22c0540f1d1ea2d86db795763b57f23c5bb46aa83f82ecbbf4b3cbdbd730fb0ce7e61b87cc83f5	1	0	\\x0000000100000000008000039442c394328f3549fae437dcf7ab261a739baff01148270d6b0458b177c6dfe32aace5b0cabb48b137aef46925634b3c070662ce798a3a5d13d34fceec25bb2aa27a2f3fc4bf0c65762420afb2c3222dff91195374aea7b63c858145893a2abce38d3efe3fe60fd0eb955ae34f6916bfdae7df8e377d09725e3554fd83d6e925010001	\\x97d88ba3dc84b18542f020c5d0009f2e02b6f434ff08ee24f6a264041b945be64abfacf947d0ba1a3a77efa6cde76823cc5d08cd015200588009eacfcc6c5502	1669369964000000	1669974764000000	1733046764000000	1827654764000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
192	\\xb7b1cfb0854e8dd3ede4bad320578488de5b22654e591f659a8bbf24b1a35d0a6d94587528e7cce113c6d4816355a8805cb900504d566b46630a150acace443f	1	0	\\x000000010000000000800003b744d73e7ffbc760281bb1dc859d516905709b9fcbdd980d80a059aace963ae1532c7c6bbc4c77870be4e3736c6498244db0365dbe2895c58060e28ffd11a09d8bfdd43a7614918feb4f1942bd26cb36c568d043be2b7b2484391fa125aacfbb641fe550198904ef4124d0f6d19102965fa232a2f3e7d61c99dde34f3e08728f010001	\\xa9e77ab798d8644d1076ae3528dbe4113fa44fb5560846587890333d48a8554dd433226b4ac26442c6f67553a9604c5476977f3c02e72657a00825a63be56e03	1676019464000000	1676624264000000	1739696264000000	1834304264000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
193	\\xbc1d9bbf845b0c14f78ab586b24aecc6fa818b8ec092555e746bcb694c013444df584966a2eba7836a4f0b7bdc20a454e0b4133cdf5891d742889cc819c36f28	1	0	\\x000000010000000000800003cdfb7ced49b5ba56a610397761a604ce57e6435a8589c85d9af05eae3f89c6f27c90c80f5a5b251361f95147aae9b5507f34d070938367f298768b43fa760479a59e2802751d1305c571240e7425499286b8b2764b5e79da7235db0780fc623f85cd50142576a9ee4691f9e0b96e1e317a435145edb97cd672e321ae48826f35010001	\\x8204618f192796fed23838542b3e0f69846bfe3359276e6052395266f5eef580a51247795bfdd01002a8cb53ae07dd0c6f6991908cf72037d127da836e8b010f	1672996964000000	1673601764000000	1736673764000000	1831281764000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
194	\\xbdd9438bd3348131ecec2da96ec40c2ad166bc42aaf2606983e48307ea157f17eb7a176d05c5cf81da1fe539794bfcf8c73a33fc4f283cdce81b52a9ffbe37de	1	0	\\x000000010000000000800003bf3476d9e3055bf22654e4c653339334bbf7840d02a087121d70a335f7934a25516ada7481369cbc0a607290ddadf7434b1a01f302047f003026eb1b0d88bd873675b97ae6df7c1e6e763ba1941d0c377841a1de03cef86eed40de4e2837c9828efef270a223c20ec408c85bb3375ecdb79a56d947be8cd63822e2b84dc93b71010001	\\xd8dd537b227bf2dc2994f217706b52f6f181a46f11b444eee09c22576a50d2aa090d68e8b06f20e06f64ab494c58a9cb805f61ff1a6953f344c50bfcde2a5606	1677832964000000	1678437764000000	1741509764000000	1836117764000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
195	\\xbde94f046ece7bfcbb615d91a189857a5a800c869576f807ebbd99020e19f1be176dbe96ce8a085adde83ffc6d6441915999af673b3b4ec9c606ad917b294ad4	1	0	\\x000000010000000000800003b82dc2cc26afe0f7c50e841725487a84a4b31a967dfba91c56af7a2fd3efe07ae04a3b03636f22ae989f90b7cee36a9ce310b733889a06eb4ef458bcf41451fdd84c136b29dd044043ce1057e06f91aaf4e819f6b558b4ed2859338a4505c166ca25d39e9dfe9c91abbc27cb5c8d2a3eb45c903f993bbe990d6bd078bc37bf93010001	\\x6d94839b76e6952ccb49cf04a7d618436cec35d0824f9cba8beacd3c9aaab92e48c84eaee7e94d8cdb1bf5af0da0baa5bcdc6b23393eaaf8ebad97e1fdc55406	1659093464000000	1659698264000000	1722770264000000	1817378264000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
196	\\xc1357c4f37f5cd203911ee0636e36cb412a0c20210b064b091c5c992d298879adf1a0885eb3e27336b6f28782a11a9caee0c91aa4ae9fec070f0c15433f0bd19	1	0	\\x000000010000000000800003c159f441fcdbcf4f8baf26796268a0ea103b8ed594acb2036243a00577d8c55f860fcf73da465d34955bd3ed8a866753c39b09f925459bdedf0892ddf976a41601dd67854dbaddd4290f0c02268dd289e713938795ae31961fe7a6475739ec8fca670d01c00fcafadb763eaa66d21974dcda591ed4770df115d1d0bce8c883d1010001	\\x365d795c58580aa20e9fbf69774bfd492a60a8dbb75836e83462ca56277d572a3f9096decca501f9b14516d4ebdf3bdb764d7e689f21a2e4dcc6dfe8a9220506	1654861964000000	1655466764000000	1718538764000000	1813146764000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
197	\\xc88131b294120473761c349b85e2f244b230097313d5282ddc2e8ff98216e0fb7bbcb25e05ed753192166962557ac25ac1654f36b6c6bc7779abd258b3b7a051	1	0	\\x000000010000000000800003bc2fd6b6246bddb2f013ecd99b108b9905ba0770ae1f0b5ac1ec85aca1b86454d9b79cc3ab9f9c280f8d95a4c13364d16f3fd18017ea3b6f9e6aef4c8fa20a7bf4bf369748937d186b9aa234d9e39febebed107ab21302ed34ecb0cbcad1355b154dd45e27216829e4b053b510d5626b18e9329bbc538578a74a540200e677d3010001	\\x7f0756d7c390dd11602216fc1912828ca7bb9c00114470cb3a604a744fd00c5b31a43138b3e671a72af9484da0419d07f2a755e5d2200ec52c9225bde63f3903	1651839464000000	1652444264000000	1715516264000000	1810124264000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
198	\\xcaa1bee8dc7fb78fdf2f5601b10af39587913f091e34960ab132531ae9fd92f65de655e05f549bbee97caee0ede2fef98692431b487693c5c5d00adf9bcd1e75	1	0	\\x000000010000000000800003bb51af761b60d18b4d0856c2260d4b3a023a7aa67eb1d5fea42bbf6acbe5d1692d42f03a91d143719c61e6fb7becac20a7627f87af7b79b845e046cda62b6fd96c8627fb3d9fe5168d666cfbb7340fb297accc4e037daf6f499edcfabc3fa749dc6b584727b2efc1e5b1ca4c9f2803cb38d004b0d38ca99aa0b21de038866c4d010001	\\xf988058f5c174999892abf5a8a5b26ccfe824596fcccbb6ef986a913999b04bd29e80a0ceb5db8d755207f5d404d56db1855168d5d9c50af5f003acf5730c30a	1679041964000000	1679646764000000	1742718764000000	1837326764000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
199	\\xcea171c2ca91d8cf04936ee92c48b20b1c46409ef82a6652567aa36f65891f83b317460c51065d59d83aa75c3a365029515c220108e658e80fa1c43be5ca81c6	1	0	\\x000000010000000000800003cd5031e9c399999015c6e451087b889b0def36bc1f5e9e625c7fe1ed1cf8a5f1ad67ab7bb7965dc36150f49812c0dde426715f204419323398d67208de6641092ca761addc7a8b4ebb1da915528a62cf66fdbb4e63c169f6937a41fa08cea2e0e3d5c31fe5aa7bd49cc392e450a7dae0e79e4718e59f99b0cd79448125229c2b010001	\\x3f2173e8409ef3c3521166d1689e3ef8603375cb536a424598ac58eca6afc7e9cd23662efca280fe09077f665263ed25ba552c20bfac1c6e0c23d4720d926209	1654861964000000	1655466764000000	1718538764000000	1813146764000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
200	\\xd2f5fe976cba4cd04760d375269b62f8adb4a681b86f9b985cd7e3f9f54ef4a77c673fc38618ed124dff5e08b08c3b0825fc5efaf165776494e5d4b574556376	1	0	\\x000000010000000000800003dff2c01733fe733557c8e89d82df14134ef140069159d269e94d445ac6401f102f7cbb86d9fc7e557fdae1b049a93e5d424f5ff83f13f0f924bfea2664813e5a376a58f3948747bfe58b3bf35419471b08506655052bfdc3a4188acf282b763ff757bebace77eb84fa2ddcbb3c55c404ace8f1eae325295dbc26c2b517280583010001	\\x5330e383fe349062c8e33132d1908cdb28f25e8f47462e2ddd87f5868a448535caa27890b04abd9f789664b411f2cd82d44f09a59f7702937a40fbe518d8c507	1669974464000000	1670579264000000	1733651264000000	1828259264000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
201	\\xd439f86775b3ac9fb277346dd9370176c5da18bc428a425f3e892a96e52d1fbe37af4800231c6bb1c12e2ffff5e79107a61fcb2450b251468787d311a5ec5486	1	0	\\x000000010000000000800003c8b00d513045a8995cd4ef0b1bc4b308ffd2d804fe1d6c0db9c98d83d62049353517b4a5911c3dc0ca2748b3f64d3160c0756e6eb6093e5e02706452526de3077c5a93d9f2814c9408dc221a8f3bcacb94aa736c3946db2a8c492868238b723a3b46141274baf0e4d125756867e1a9fb589adbd91bf6477a23cd1c53eb873b53010001	\\x9aee2f7e7fab0b101138c4d0c3e9c7156b66495eee3b4c59577faa05100fbbcd0bb46b577f883b8be9f3f7768fd75e9777d63687b95e2afcd7f7e5e1d0fda005	1653048464000000	1653653264000000	1716725264000000	1811333264000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
202	\\xd5b9b3c2b5da11ec30308d81a63858e973138616c9e2a24bb6c06b06ab9815291f7aeeaaa0ba034b6d1f87f6298f5c9717228c7ee47ec1fca737e30cb35180f2	1	0	\\x000000010000000000800003e59ded8665fdc583eddcee72ec7f914fb02f5e1323753734affa0b31569c7040099cb6015fc9c4c37b62533a8adf49fa273e1eda973d43eb13ff834fe7869226bc7dfbb9847a4ccd425632a0ae10a4c06b82cd186f77aca5cd22b5914be6bd52baebc4a4b28c58dd543c6686d3b20aacb123d9f02f5c2c15ffd12e0d90848453010001	\\x3b19205c6fe56f658ff521c86a9a36e79169ea15f5fa717e1ab02101841390e337fc559bfd2173793d24cbcf1bc0b252a4166056b723b58db445014b3ec64c09	1653652964000000	1654257764000000	1717329764000000	1811937764000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
203	\\xd6c95a0baa03961fc31a568cd6abe965fe33735a690cfcaf08a921381aecadedef78ea4a6c11f7012700c040c8917d2a171614df791881dd145b927ae748e909	1	0	\\x000000010000000000800003d4c31cb34220697de5750eeac28af34f6321b6a8984ff86388dcbb5bf52e842c4d8f3f2f3ea8386942c4eacf20d818d2616a1ac474ef137120f77fdff36e1dd1dddedd3bd822a9765a06bc20041052faf97b90469a101fe438136d6348ff931ca681827b45a0c27d47b7525a515391f9c228b873aac5657c88d57ae02c5ce3c5010001	\\x2514eada9ccd62a0c64f675104fdbf6280b2d5891fed7ddce85a8e29e347a91a675772d7511ea61a8881f894b4e1722c618b38aa86191e8bfcd95ce32d543b01	1665742964000000	1666347764000000	1729419764000000	1824027764000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
204	\\xd7c9faf82959d62f0f0183103016b810df5b7badcca79953757328c405a95bd374ddedeeab9c74a3ce963fcd1b6ce4aa91fe720eea416fd39526ba0cb15e9fee	1	0	\\x000000010000000000800003d0f0c120105633c9e9bfabdf17610fc3852fd26c8b96689c821ec3041ed9476d64b4c69446fdb7cc029d5d20fe0309694a8fdceaefa07569dd46baa8a65cbfea5d22494e87d656f8dab0779bba3ff60cd0c93fb6ae790605ee29d50cd4728293ac9e0d88b85d28b1d472cd6d9db7f142547ae29c03d5a8335d050f9f79736611010001	\\xc7809a629f455223ae5ecb2fc9ea5b87206cad4579c418eaabcb783d31a171e5c26ffc3f5c1cc4a9d71f4ad5a53d0e8a53e60c206ef1bc569e273c28b8f32606	1657279964000000	1657884764000000	1720956764000000	1815564764000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
205	\\xd755f0bbd1f47f119fd227f48e3af3f1c7586e90a8ba0d4072f2b69584b2ba09741947cdb025070b5a58135d60d461a6954afa0a2322a1cc3dce41bb6bed545c	1	0	\\x000000010000000000800003b8aefdf1ec298a9fe6cc0b14cb1373c881c61592ecdd78d8c3904e8bd25823ebbd3e6d1be2e30e888ebabead0f89f420c5748ccd62a9e8c4bdd8b7e62d1e7946656e63b3414fd6e6a212d71ee6f067f5f75a36d64775b3c6ad08b5f1a3a694f0f8b2072602f33ca6fc0513e6d48064dca3a6c93c7849cde3543bb1a7112f707f010001	\\x8c938bba5ab70d2a54be1e9285d291c11c762a17b9b2d340ab0e7cc1b4a927c0e254d3a039577eb6393d12da217822f4a733e0d38900dd942ecbdbf48cca2c06	1656675464000000	1657280264000000	1720352264000000	1814960264000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
206	\\xd8e5986339fcb1b1e6aa1ea0dad2143992ceb3ad2b29de3aa2db432d0809f5ef128c6903382c2d9dd1e7539ad9c3c58c066084c8a9abcbad4e5cfcac481e4d8e	1	0	\\x000000010000000000800003e408d380a193267be05f49d89593e814043e86ca2422bb1c5adf56cc501ac708a580fa81c094ed499df6a10c8d15eef889079034def804263ba3c02f9946827cb696ab044b05e3afb148db710573464cf62165daf4adf36fe491fd84b5ca1e1be8e7ef36c160882bb68221140733a71dccc5162b682489530a879071548985bd010001	\\xf9293f47cdacabc6c2139505aa20212947fbda79cf08a527cfb037785505f541ec3c47ef9cbfa61f70479b82d4465d52cea9c5fd94d89729e1afd4b27819a307	1650025964000000	1650630764000000	1713702764000000	1808310764000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
207	\\xdbd57a43bba2aa1c9cc97c060ae57b004a024d8730251531535e9665024496cd8a20ad7465f36d0de72970245b0ff83de655b811964b7823a95a63bde9253f93	1	0	\\x000000010000000000800003e49b9b8339c9413891a58cc08b86348b5d283ba56f5ad87af880ef42717805c0995491a857c8be9697c4fb8bd54119a58b1f535b2e776936fe1652c3fe98e6599d98e7f32fdb541945afb45c67ee439ea6409a7c992e03094b9c4e0f18fa34ac0914d655c985f6dff97bbb3ce7f7fbfeaafe786f356a54197e5bf44dfc29ce55010001	\\x2a3f02a614d5ea7fb7c2d1ade13f71497d814cfe3f27bbc9b5619f96590afc4d4e4b9a7bdb2d43de1690ac47b2a2abd74c9fb27279e42ba94dc0f8db57da4406	1655466464000000	1656071264000000	1719143264000000	1813751264000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
208	\\xde752a09519de1034e77994a038c17794e1bda913242a7deadf769eac8ca4b8693fcb7afe4fedbdee81ca952cc050f568849fd1cfde02fb6b4b5182b21b0fd56	1	0	\\x000000010000000000800003a3167058867d37b86d2dc7075dca1a056c546d7ad3b218289fbd3a1e7d572317c8f0202aa068ef8ef8dce8eef084d6392407f4d75ebd32fc1d451d40ed50912cbb54df3376c105861f5463f98aae978ef8251b98f4492b2621c077419ad571b431a0133669004e92c2d760b3b4cad86d5a5bc48d416f68fac0861c61826651e9010001	\\x4c498826111ecf8dad95e2eb03dd85a008e8c70ba9c7638f6a5c1bfb0046cf9717fc4b2977bb9a690cdfeb1bd6735f0fdd07754fe113648850724470b8bc6e09	1676019464000000	1676624264000000	1739696264000000	1834304264000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
209	\\xdedd744ef4cbde9ba8f48a992eb298b6dda4796a486ca21b5a7123ea88c3b49fb0773e2d604cd264001da0168b7270afaf2f30411ace19345be4aefcb85b7c47	1	0	\\x0000000100000000008000039f7f528b93db8fff79bd9ad4021ea0d10d33d8310be51927675fcf8df47804b2cad60e93a3b100f93707dc6649e2727bdeb513af57b2f3e03c1f9fe207c8b7503a3146b06605166e7dd9305f1b9b5bf2b19b971a5de4c906c9629d1d669f04697523cf692cc83599dab785690bebd284bd89db5e5175d874da89aa827facc467010001	\\x7b7bffa87d0ebabbd173196baae2c65760382708c76e97100584f18662256ef384ed7d5daa95d4456ea62a9787b3a1eaf6054438c7b8ee97971cee78e459900c	1648212464000000	1648817264000000	1711889264000000	1806497264000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
210	\\xe37d4ae3d6b4446bc04d1b4220b69b2b83c567e5d17567ff80987a7569c5aabb9c8ab93eba3977eb34290f110f8311d31bca9abcc9ca9e21b6d6888e81567845	1	0	\\x000000010000000000800003e9efb32a3649080f84d613fa3e4cab1046420aec693a25f2c9c4470bf92cb4e425a80091b1840494ba5295a8ade21f7ea3731470f468f0d48c7b4e574f8916db46c114b1911734c8de610b39d77bd305ea8da79d8430b342ee995f81b4151196582ad2ada0a764dc2b7d7c54e254306915d5463c9445afc072346338eb9ad0b9010001	\\xbe633add7506ad71e82365850011c618efd41974fd7ae14a9eef7fb4e59732aaf2c83e50d54b709b80a6bc01665243de68471fba10ab0383a933bbd70b2caf0b	1659697964000000	1660302764000000	1723374764000000	1817982764000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
211	\\xe6cd4bb245a396ea1012d8a75ff509c8c236e5d41c480a8a03c080a04d98e292ebe73d29b70b81608da907436137cda3f2b90b77d1e5eac719efa6cffa656bff	1	0	\\x000000010000000000800003d70f494574640a7be0a09cd19637d4bb3bb8c700976517619da814df979ffc8fccb70d50b22012ff28ae4a0487ce7b8b1c5d43677991f0938b152b02e2e8b7eab7cb2bd613c9e8d6a7e52d7bccafafed179105c65a197ccd96b29bc0f077057164bf8dc5e3596d3e0082048a6a44f52082acd472803d2dfd8f02f617c639d03b010001	\\x59661df379f3585b76f8ee946dc2b72800903b0e7fac4d9fa8f32db81b8f6711550888b4060ea7e5b37df02d840b00283e4af317d0c0ff6758411da4b8ff6903	1676019464000000	1676624264000000	1739696264000000	1834304264000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
212	\\xe955b3e543fe2c66c7daabde38abca24952084c064b0ca76b41ab23665119e17e156db8d645c43a36fd043eba9aa98058ca2b6b7a69959048dcc556eae87a141	1	0	\\x000000010000000000800003bf6c65bdd786d132fcb411b38cc302bc47ad3d56d9a7ff40d0700a3845520745302fe3572cf00e8149733a58aa724d614802c163f74846b3612785f1507b821b5b228af096ebd60a905b35e78be7aef4643b804733a871655e7f0887360380b2abefcf9d4fea0a33f855cf9af19b933d51050c833701da7f67c424b935ec7187010001	\\x9dc27a7e982255ebabb8771d6b0bff92eb0d7917b7ebb761c649d220e71c311a0b3c1f6f8839bb733ee30f83ef4a2accee51b03976e78e54dfb6193a4f9c4d05	1677832964000000	1678437764000000	1741509764000000	1836117764000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
213	\\xeb1997ec4d2a7901353041ce1caa243eada79911f9db45e7ac367c4a3f1c7f739648edf47408ce73813b0d39da605b6fefe0df07bb1ced1778d5f2260a8ab035	1	0	\\x000000010000000000800003e9b705e7c20f0a5d12ea316b80c3edeb0c0f45c2ce09d2c44fdac0eb3eb1145a654d9229dd7eb3018832074cb9ebc4cc5e035240de22c7d821337719db4eb73bf89d9efc5ca2572c15bc79cc5484727422584b1006e04dd42de4d188a0371f1339446e4e8ae5d4fd21d94b323b13b0ed9c2ed2ee3724217335ef457ea17bbef3010001	\\xcdb996dd2927acd039c84e50a0e251b39282e109bcaa2315841ba94292c77369932524daa28970f6a2fcc815c534d5e4dccb1552be3f78b706e4c1aae3079700	1649421464000000	1650026264000000	1713098264000000	1807706264000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
214	\\xec11c3cc41d8481e1cf64b551f28d23c1162fcf1ca0ad965e8c570e9af06ac62eec7fef429c07b843ce48391553bf1f21a635233ebff35a108aa0da2a5fc1096	1	0	\\x000000010000000000800003fa9c874cb952c59c0d003158f4055fc58dbd17bdb8b7bc90c336a46886a8de135c3b2ab0670a057c9f64144b9f0c45becc222a0ee0bc36edb725d856df243ff8acd36420481497eefe0b4a363135046f89f111119f0fab894fbdc77c9c9fd3361b56dbdd74a4b086aae819a08ba0505ff956dc04290b94952431f41937e9b3c9010001	\\x3ec25755b9c291be7c2ef0137e33627d267f4a35b1a8faccdc7ce88c64d75a7fe35af7155ec9b783d288a204b4754a7ef164b54bcb9abf5566a88d34c8e13006	1679041964000000	1679646764000000	1742718764000000	1837326764000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
215	\\xeedda60aa72e2bfcbf3b7b71517871641564801bde6c653a8689f539d4384be9a1955b3369c507939e3f04ebe9419866beae1341263d69009835a73d0d1a3a9c	1	0	\\x000000010000000000800003cd9a42fe93a11fab6698e5e9586787fea2362ece00caf4a01e1f4d1ae1a690275eb5a2f0ca0780c56d9fdb64351da293e37ae9d4b925dd098105bf6aec4480804765480c6bf55672b6a920cb8ff23d50892f82ae8e1ecf501406610bed451087cb7ed42583d30025dbcd19fbb5892978a60852cbf62cae50613640d6a3e29621010001	\\xc72050b05bfa24e5d625110be825c1b782e058b1727fc45dfcb62b731473be1adca4d4c9afd23af22983a0ece35113c0b616c4ee4eb8376d315e69ac562ec40f	1678437464000000	1679042264000000	1742114264000000	1836722264000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
216	\\xef11be495da94fba57311521af3cf676c6d6d7cb46473fe3e5736e0dff58e0bb8f32e4a167d5da454d1d08201604a310ab4eb2446b8c77ed91dcf4094bb80486	1	0	\\x000000010000000000800003c5b57fc32884da7cec3701cf8709168c6ba69d056fb4621bb257379a32207418e380f2eab21220f4524a17f8bf5f7c636971dd31633db8fa6c0a6f3305ce107f6e894fe11334bf02ec8b77b6d7dc3ac217a0ac6309524828feda07ceb8ca73810c1f35f1f866af6a4370887769bf8b0046c6404e6576d07faf45c8ed8bd6d34f010001	\\x3897312f1db19bcbb76d51d1734755d2fe818e6a4ae225f3a1b2d79a3bf165dd2904955665823025bdced69f0e817c9da095dc684549c67000c14bafaaf4c20a	1653652964000000	1654257764000000	1717329764000000	1811937764000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
217	\\xefb11cd25c98412a1c334e44493ac94faf2b1da9e261f34c56393e7cf84cfc6553ee05a8b3bfc4b252c1b323292449dc3039da0ccc02b048ab411b2200a0af7e	1	0	\\x000000010000000000800003b1c4251268de33d275abb0a69f6e4e25e19ba4d9ff2d1eca319d71f83eae1a9eaf721d99c7c86e5d51e990251dfbd5d0dd60b43b7b5f9ea53591e2107ec984d13f7a0b79ae6d23ce449388fe0896286c276e1b1777acf3f614b577299f6985e359ba36652643c7346c993687b2bdd932ebd752842174e13b244e45354980a0b5010001	\\xc0e07238bcdebf8ea4c4c9701a9955e09d655d27fdf6e628dafc7bf897e07f2328b695e613c2b77786522a1426e83132a6ca5c46a28dc76047d56e530442ad06	1659697964000000	1660302764000000	1723374764000000	1817982764000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
218	\\xf521bcc48f7542a429351468b36883b7c0c44c16e54c0db5619df96e366389883fee6e1447a9127a1c36862a4fd1b48f720c86d4a4eae03616395f3834229d5e	1	0	\\x000000010000000000800003c7c1369dafb910478f1d62d2c6c4152dbb1df3afc183dbac3bbbda2bef4ff0f388f03058c3e8492e1a1a018da39046451089c98b13b99c63ed647662a32c6860ce08460b92696c0b5dcaa8e910e0534404a921e7e13707f36d1760fe6e7951eaf07ba05d5e06537912f3cb8ac3f92cebb00b797dd135df70c1b083560e78307f010001	\\xdfbf8c071966dd3d93e7baf3f9cacd28e9ae4a8e6d644356332d349a56fa36d89f55660353ca86d3d9f448be6783e96876cf2440016ec99cc7b59848593ab60c	1653652964000000	1654257764000000	1717329764000000	1811937764000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
219	\\xfa8d070eae1aad6e3c63650b1702884cbdda4c3fe5ac94d4bbf950a0aa063683801deb36488738c673d628abda8112affce0d939d32ff3ba6faf12f7572f7048	1	0	\\x000000010000000000800003d04343255020548891db2c156dd5a986b26d73cf4c3ccc07d1b656f75374210d31829187f4d843d9f06ad30326fcaa198d008a51c581ca6dce26af7d1b3cbae25904402b23dbebad3c467941d6dd6a8030cb01707af1e0343a0368e87f1fbeb2a01c624f390aebb466854c9f6008abfbfc571e05d69a5e7feefcbc1574c54fc7010001	\\x628a74b4c4dc82a7cae613877c94de541e5f5fd5674bd4dc3562828cb711a5a24dee9cb6295f5ca92ffa43d052496c2cb5ff730ea2275cd386dfa696c093d004	1674810464000000	1675415264000000	1738487264000000	1833095264000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
220	\\xfc1d68c14bc4c2bf0661c692b5d462ba9dbd6e03b0c7be024ac6f0cdeedd8e5f59f151a9f7f2be43cf2b8b82d35fbba6af3378ecf6e5b91523e5e027a20f3ac3	1	0	\\x000000010000000000800003a154ef4d7563af195a5fabbb1934da8c5bb62009ad83b3c8dfd245c4a00b71dc0725f39b9baf4988e8bdaa404998094f6d624d92c19e1d8f649c96cd3c85471e8104878a4f303aed215eea32ac222cbc469bcd59264b9ecf2484d00269c98ed5653f5f38cdb0e0eeccc1bc2579832b2c69dd7fdd0e021513b266a72a3092a6e3010001	\\x0134811951151c53cf91259c40449b023cdd38146f3554a5e354b0202e291e63eba0896ff0c81f3bf208e4a246ad3dc1762345a6303ec442efd0dc157cd24802	1679041964000000	1679646764000000	1742718764000000	1837326764000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
221	\\xfec9bd00ca248fef34469f4c5e7dc65c503e2385fba56644470d3482d8cc8611405a14fb1b3d73b3e1ed24525a58b6453b1088b9596864b90061a360d9caf797	1	0	\\x000000010000000000800003c326904a0ef756af1bc2a71122d2a89df1b9973adf566f73a8042eb02c44fc0d02f9a85b572d5e8277b16686827ae9f99df7acba58f2412ecf8407efbfa47eabf37064f1a18cbaac629a5f378b8ecd4f476edb3f61cbe631c4a2abef12c461c12c1a5cf85ae918217bb0a19c03f8e3ce19e099bf45cba97eade2f6acee121033010001	\\x13efe6bcc06a7b1a978c1c4f3af09edc6b7d24d2a1173f8c45856f694b2b92f589e038f164746fdd4f5d396c7ab7378cb5b1a6451c432a7ef0b7ec3f84a7c003	1671183464000000	1671788264000000	1734860264000000	1829468264000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
222	\\xff0d4c321fcef6cc9e1ca37de4727a2c91cb03ce451b8d28214298d6df704603e75c78ff7424e943b4d9851ca5e6d1e882dad1d6926755e032d65f85d0d02bb3	1	0	\\x000000010000000000800003ded6fd5c922f3f3208a8e2695d515b1b11c22029c959587ad9380e4d4ac4056e24229b9760ff5ef96bc1048797ec4c61b3214be3bcd8acec2070637cfb5f55ce661015ac0c4ef9ae3b233a81777b647ea2bc3603101f54491c00754831256554a66eb4c8173e8a24fbc55de8ac9bcbfde5e1b522b7af17d27656b183c734a6a1010001	\\x14c5536ef18e61118f2911af4073e54b7b81a8a5b46171070a7cfeb0042b94f3c1fe6f8b4ed3eefba44cea1fad01cb3a57c40d43975f169db34de319f1020202	1663324964000000	1663929764000000	1727001764000000	1821609764000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
223	\\x02b6e33fe74ae3dfcaa3c567a31243ea7f72525f6ff3ad4e4ac9b3d54b7c3bf3dd50cc1bf39afd2232fbdc3766213ad936137b3918edc0a93e06efd8954f6fd0	1	0	\\x000000010000000000800003cba0505960e9b7f58d8a2cf706cf9d56dd65e736460e3efcac2370ea780464ba4167d1d4ee4169b8fa638b07fde6a46a6cbbc1033cae3357de6b9a73725d77e82d48943772c00eaed422be64a828f819c73f497c41b24ab93fa05cd6b2f5dbf984313894b756fe106ba987a2ff6616766a21548e21a9f18373eff36b5c9783b1010001	\\x808388fdf7560af78b9536900bcc5a5ee66694045817407875aea72b18c84920c90282c7d8ab618b3dda3f412f96f5bfcd8ad5f16dc05592e27d3bfd59cee50b	1648212464000000	1648817264000000	1711889264000000	1806497264000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
224	\\x05e6c51e9daac6508a6957e04530d89af2532d48923ce25d50459e9c404497ae90576fc31b6a2f0fac91eb2dc72c5dd4ab11f05761dd9718a78c815b9ce678c4	1	0	\\x000000010000000000800003c90f0cb9f3cd672434a9e06d2286d04eed90f59d3772b1036246f6cacf9e74953ad150a4c3f1d6d2d237babe7e9a47dd6575a78e1f8ae77bdacf294d844a722feaa1f3775c3a28bce42f15109379b114331eb27b8dcab424e8e8ee3f047d25a24eb9b9afaca547c0cb308130829f6241cd695a6806c2cedd0b9106a8ff6c691d010001	\\x0dde021c5266d5158d1001de7a1077cf798bbb93b2e1370a104748993ce91a652e79892c4e6087798d3d60ebc855e34986ddd59abd02b58285e7883bc0fdf103	1677228464000000	1677833264000000	1740905264000000	1835513264000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
225	\\x06760a5a62ead288c150ff67d246129c19c05e631559c120c2484535fd98716a6729b73e24e7835e0bc8b08a0e104ecdf49aeb9e09086e88a3601bf191fe2ed8	1	0	\\x000000010000000000800003c75ab8e8456b4605f77a2c73609105d1fbdf361b8cb72f6f391268285486b0d32b9a8fa061a2f50acffa9c70a11ecb7e518ced1682b44e667b9aef38e3a031b3b87378e880cdfdcfc7b72aecd2456ec249cc10f6508c5ff24f5163b22796117c0c041848cff9414f9b9d1c7d8140381cf33d305f713238d0a8bf3e1b795ed643010001	\\x65c3aafbf320c68053cf19057fa0376204cf6980cb23ea041c2ed96262d4c691f69c4e3295687340d478738072f4c5f0efcc56d250638e20b5caae9cf3c55a08	1653048464000000	1653653264000000	1716725264000000	1811333264000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
226	\\x0946cfc306d30c0a564d7d168291f68fd140c8bdf859ad99f368c3d3df1721823f8d720f87fcba0208bb71370c892304215302660ebb33c3fa0ccf64ec300721	1	0	\\x000000010000000000800003a52afb4952c1f976822bb3434371a96afbc9e0a41b628819cf0d3aad42a379897503c4952d4dc20e274043eeab3b982081e7f1a8361cb8415013520586eba68d33e9dda6bd9af96ed3c446a90c16b6208f8ecd5d1efc940e75805265cde7fdabbd91b21620afd02ce69cf58c6f9fd3bc57d5d81125af35e732399517d048c99b010001	\\xa2c8d7905087bf82926edf9e2040a50c9a3ddae30e49d57516c823849b72ede16b2810c709a4abf98700754a03b477a47cadd18baf6d8bc3f1243c6e4f441e0a	1669369964000000	1669974764000000	1733046764000000	1827654764000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
227	\\x0a5a8a86a6cf9b3fd87dd84e612aab3d2353a8fa2856e29db541c4be4b72d9f111c1af8fc0af26f9fc7cc7cdfc774158f9402d464df6988cfd90b1f7197616cc	1	0	\\x000000010000000000800003c25ee104b2b55e776568ffc20d623c8392a92c9c8dc27fef179b6378d7e4d59cfb86f21bf343e266c926aecd38a37c7e9dd4c7bd92966e0844eae793d9466907b130cbb9ec38c2e43ee15aa2101ddfe8202b3c2e140f4f12f6426581640f53b96f9ccf285e7772ce5964322e5b90324cdee8f1cd16f20e8eb81c2914796f0fcd010001	\\xa47610e400a0e6de069bcc0edd701fea7ce8dde6540a0ef25dbce0272c294f3e111acc6de816e10a6ae8bf96eb6a9b272b615aece4e0c6e29be2c615246daf09	1660906964000000	1661511764000000	1724583764000000	1819191764000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
228	\\x0b3e0c69164c034cf2c79f408151095afa49e274cb8d6b7f725df630813f1fc85928b2e56769f6f7566e8321990dbd907a92654bfb5bc2c2e9e507d72393b263	1	0	\\x000000010000000000800003d603ebebb1d718ae9aadf5a0b785cb016c4e14fc7bef0dd6bea3a0a76c08124b44358eeea3235f123847b9d85710a1c54b64753962f75f51b8e3d462f62276deacc99a3cd542b63e58e930bc6050561d16fa718590eb042ca2cc23cf456da0ddae313bc794927402975a98ba981a347fc34468c9f82da8267344c0b1975fd5d7010001	\\x2342fc9839cf1a285eea2a08ee93b33dfeadb944261494e7b387bdb09d23d5b665b33112497982efc9e29ad7e53edf6db75c99cd67bfd350b1d9e68cd4f3ef0f	1662115964000000	1662720764000000	1725792764000000	1820400764000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
229	\\x11eec5b66e5b09ea1984ac86c15cb487268fabe5234a9ab117286293842091ff677def381448bdef948e4ebdac873ce8c471cb2825c708bc8571c9376fb09f84	1	0	\\x000000010000000000800003ae5757ea7593a50c27b8272e11c1044cef602fcd65888e8088cd21347203243a613a0c5ca406ff379bcd474a7b37e4582d61914c3acbb1b773a3a5627e9dfb97e98fd2808f9ae9b9eff613b5acf64715174adb0af045ede53064ac086633d18d3ac4a88109bb589f2d4ceb02738216c9958f38c2e01064b942856eb6325407a7010001	\\x589873b93756f2ea8c5554f23421e265cdc8926fa9c1f4275424ed9fab8014d7feba3a6c74a7bed8cf3d42256553f6fccdb44d8ef21d73975b2f5f23ccdd1e01	1665742964000000	1666347764000000	1729419764000000	1824027764000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
230	\\x132a4e0f8c766825be5a266ff0f846d8ff951e2c82623cbce613d2240b459fc14fc5835ca052f95ce02d673274dbf1038561b38b3e2ebf8f304f93c8a37a0470	1	0	\\x000000010000000000800003bdbbbb99b2e5f856abcb48ccaf0eb3e3dd90af540de804f3a5429dc48f5fc52c0a98eab5856cd23351613aaf966d48c0e5133eab0326f11d0f18adf4f86b4131f8161918fdbc32f5be28b13ce5b99688d0712da25788e15bb25c75a7275d675099f98eb4b10478e1befdf02f14d5d50a71d544bc70485a5d9d67d3c501beea6b010001	\\x6a4f4348f23b9c17ab1f70ce44b0dd48fe981b00c1304d7f7bb2c2efa29cb11749e0f3b1272f821caf414cee7ae0f715bd5b53ffbb1eb48feb7026ad41459a0f	1659093464000000	1659698264000000	1722770264000000	1817378264000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
231	\\x15de47aa28a399c6b52c30714424ddf552d46846254599b7da9f0eca0bcc6d0403c954d4fb71b0e9754679165d5637a02086c884d7ecc3dd94a75210aacc77eb	1	0	\\x000000010000000000800003c07b601526fcb2fa394e5cf4baa585147f066aff5b83375156860512d25ce93b08350a8e765bff03fa056b0c3a99b5133a2d0875fa3ccc5e1c3a38eb98b405077450c4674dfe005fe1318ce82055cfea8da1a66a6042048bb3d315feea2ec5fdf75ba59ee94b2d206dd387a2647cb752403ec36bb8120d7a6d545c15bd0df60f010001	\\x4cda3877dfc1e8eb33eaffb2f0c01631987080fdcb319d26b4d4af53970921129370a72e5cbf532034efeced4aabe9a76cf174ca1da762b795029bfc92f0fb09	1655466464000000	1656071264000000	1719143264000000	1813751264000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
232	\\x18021439f66d2c21b177ca4fbb0c884e2c4f47edb9663390fd1b9a2476a9e5eaf00280f717fd8a972fb4f73a177a0f7651028ff5198d400d9be417f86755e842	1	0	\\x000000010000000000800003d26943cb34cb69afcd5bf4a670c252d702d1464854a6ff39936bb12742f71ac5f8bb3352ffb72b0330d36d45c961e42e38529ab32efe40c087fe735821492f6fa4302d32ca4ed6566170c0b3ce5830924ad215af26bf3dbb161e2b3ce744490254d811e705fd692944a3b787dbab88d53f9dba16fcc46f9caf0ce44c0ec79faf010001	\\xf6720298a15195be0be9497b188659333477bf2512bf5ce747ceafa3ea32d92257d15e1376d8327c79253fd53cd759319e2d2e445dcc4aa8d6dedaa55ea0100c	1654861964000000	1655466764000000	1718538764000000	1813146764000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
233	\\x182ea2d1da7a6d5afaa46403d88d470954ea4a9a1219ec6f7963a842648591968914d5e5ae3563883b88d16864516db0c08a96cb278743e04963b014b2ae0ee4	1	0	\\x000000010000000000800003d923da21de6e38d597cf5e52fc013374bfb934c923fc67d91b676dfa3075ac275c2ba6d829d39f435558fda636ebcca79fb21bc812c7d35174f6d624ca52cbea9c38afa87df99e98df00284d9837274f7589e00ea392857325f6236e1895a6309155007330835db788946d798ac762d80311925bf5680f9a76e6efb98ea4ab0d010001	\\x85ea83406d5e27b4ef995fe64483ca3db745ade4eb2fbf929af3af0839ad3ddc97d4a74849e423e4758ac4a7ebfe968e5048f0933de38bb2992e2ca80fb6ca04	1655466464000000	1656071264000000	1719143264000000	1813751264000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
234	\\x19fe08d03ff003dc3e24375c880399c0178ad8023ee80ed17b720f1c6d4d94a3e0ad14ed56ae93d51e8cb1376938cab0833cb23c22beb4218e01bbbf0602ba1c	1	0	\\x000000010000000000800003bacb5d0b341cba5f293183706a6d1f47bf6e05c2f6fc6790fd5c34e77eca4d9d3dc75f57ba540766997123a19b15aabaf5e6d5f9b8f6abbd984eff50712b655ae35ca85104a1316411b8829f49cb3c5a48ce27574b55901e368e9e5cb1ff0d2a27f791c5618981676d5b57606afd8d2a966536d8069118ad7c082bf277da1dab010001	\\x72c321743321bfa7516248cbbf0fbe51dfdd3ebe37a8f0da37cf435a33f572fd7d34203d4c813d341c877eed0bc001a142a4b631a7d32a4e3957098884330907	1650025964000000	1650630764000000	1713702764000000	1808310764000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
235	\\x22d29fd6ead81b18e1e97e9f6988618da4e28b682ad5e41bcacb265433aa496ee2bc6be14d485bfc6f2d05604295ba8259e2479ba39196fe22d3a9dd163655be	1	0	\\x000000010000000000800003e378782a05376bc2bc200c2bbdde5d23525d3d3725e49a34db7cdbae44931cfdec7230607e33bd8d4a11db351e23ac41b2d630888ea36e1ca25729e8762fefe780825dfb7dad1d0d0fe598a05516c93eb3575452268d8bac1230e0954674cd06ee79fd1d36b226f0c80016aa0ab30fd3a9bd305a416f444bc828cba18ebbdea7010001	\\xb29527dff8a02922b351d792572bb60ce7ac5ef1346fe643da6985986ec47cec23a2d3e5a6ab8328af60404fc15ee1afffe5a83ab182edf48fa097205bd3bf02	1648816964000000	1649421764000000	1712493764000000	1807101764000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
236	\\x2522e302af19f959bca6238368bf3273de4a25d5740e9dc590b2ec29af9549ad5084aeb482dd2db64440abad27ef3c56121751d3969c010925ee8fb949ad0ab8	1	0	\\x000000010000000000800003c36c0ab16f777b7011c04df16797bc6ad1d847c059a949da68a10701ed807b77a1ac744392b37d30ff26b9fba8fa963e4615aa4cc480199bc2f43e354cbb7ef6fb37ccc879901954a6f3438257e8821656d42d143720be8440fcadf42c588066a7af7293d4bd41e3a4b28f821cb4d1c9469247a46b329dae4a1331f1a1b5fd91010001	\\x46fb67aeac75cd1b6a3b2f43288b474802c37986a11a430d6279670bf133ed9cbb1b68659b57b37b41d20d15df28439e44d5b5d00b67751f2ad7ca32ec546209	1659697964000000	1660302764000000	1723374764000000	1817982764000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
237	\\x29263a7ad141107ac61e58066c93bfc6af87731d02e238fe9e153483d4caf24ee758f864c30b040a5ab11755546036f258b41f5ee75cb3e99e524a7587f34cfa	1	0	\\x000000010000000000800003f307c25dce377d743d5383255b363be18d6d14fb94cc50948827ab07c2f10aea5cf4d14d1eec4588d92364648d74c3146eeb5dd1b4f4ab8349d9b9c2234dac73122b837008f34cee2f706ada69805c2fe0645afeadc3a62a8da4ac380d0980365a356679f85a579eafc20c083ffd9dcc94ccd5f22d5f1ab27aaa04592986a939010001	\\x5ea84cdfbed26966cc5ebf034a9c2b832c3933044d3000db5741f493f2da8662d65ebe6c279f156288484d8c43af1c143b79bff83e6796fbeec7d9de5663fa03	1675414964000000	1676019764000000	1739091764000000	1833699764000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
238	\\x2e6aab06ac3a600ecb84865082cb7c0e52df4af40b2f2beebf32535e15a681bab1add4c9c5023db69c44e0e1a6919750865449b1a5dbcc585d9868c1426041c6	1	0	\\x000000010000000000800003b6b9d9a3697c6c3caceeb508ac95d9558af2ee0b0b6b8ca5ef8ff148c0c8d4894fe5e57e36b614304e92b85639926b075b91a1126233c56dcd18659579c3346d3041d49d016954c7a9428135c759fc170c8d9e398bff458300a4feb99324804704ff1930d9974b0f5e0c9779f7cd5c7be4d924268346be982f5f99dfee1cb337010001	\\x1ee12f8a28cccc36b31f586b2ded7df0f30c08871c2cec0dab93d455b9f33290088bbc83178157d07a84caab9316e6c10e46e59e1313cd34c7c5b6b859aa7607	1665138464000000	1665743264000000	1728815264000000	1823423264000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
239	\\x2ffeafbb8cd117d826bee2cc90145906d132b82b836334c8380718828e9f458c1e3fb0995c48a2174111c0ca0140b5158e592f77d94a40530991c73987574d40	1	0	\\x000000010000000000800003b5d3321b94191d296542ef1e10441df813e87534e1283ba7169d54495e407b791649043332e269ea32dcdf10b5df0ef908c204170665a225e9334beacf29d55fbcb61cc872acf990907780d1245d9522764d0b11bf15f82d64eb99497eb6f3ec98fb053af3833a09beddc52278a2f25f3969f9940e71de71c143bac023cea947010001	\\xb772f2a48717de136bccec9020e342e061470aecff4ace5c8fd5d1b3fcf37f580ce121b52a44e0073f0f6fe779ad294468e947a9f7f8e29498e9549f2b423a0b	1671183464000000	1671788264000000	1734860264000000	1829468264000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
240	\\x34564baaa0b2e995911311cc8a32b557320c564e2fd0ea82189f09a4d4edc5c17a2d95cc5e27fe53c72a5091a3fd052c610b16836d13d6e5c20825da15a63bd3	1	0	\\x000000010000000000800003c5fbb4127170ba3f037dd12421d635491f9a68ea01cf8e6fc3e49790439501cc80354edfc807ff5d5161dfc88f79c60bc57e7c61d187084e98fc83552dc57270dd5051967a1639864ed51abec6025e4ca09d3d8b482b411ea9e6dbed5f8a1d93455b85ff886375f4936413602435993b245f4708670da26120961e5c5b0c4425010001	\\xf55cfd3466551a540020a0d48bfd15778394d91405f01acfe7f47e7b0b2b2b3eaedc9fae4b7997c6ebc58d64ea7c52cdab3ca37357954ae199838ed722038e07	1660302464000000	1660907264000000	1723979264000000	1818587264000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
241	\\x36e64ac36b2608aa5803e20d93c2575e01758fcf9a407053068ec7693274bd83bc0648f79aed393e69668de1996c66fa8696be2576ad3c39d411b32f2f34e427	1	0	\\x000000010000000000800003d451de02bf4aeb0cc0e13ad1579d7191840fd2265b1dedfd9f007a858ff14ceb049b6779612d8090c8d664571d1c58fbe317cf1ef7100aee62fc9515816aeab5b285c170374da1102a59421971e4ccec9d853cdeeec7417a7dea9442ece6fddbdb1ca9a935ad9bec41d56b2eb30a9ad8252a9749185b5fd8200c5e866afc5f61010001	\\x26485da4d064e2d6ceddbd242c5353818ab01d64c923ac9450da57c492a191e6c3640390c9e34162c9b945e1e8f2e993284dda4c67dc9e96ea6f63cde75cad0b	1653652964000000	1654257764000000	1717329764000000	1811937764000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
242	\\x3be2083e6aa0b13a8b7377b043fa4d0d654c075e79cde1663da3257c5f6d32555ba629f7486b85d2f8282a736b8cf955015933ec9b713db2d888c480f7313732	1	0	\\x000000010000000000800003abc6c92b04376eac4f611fada00a48133c13082c17f401943db8cfbf80b82eaaf9d4038b833abe2c961571c021e8a0fda33841bd5c20a5d406ee3cc83e94851f218f7f0471658f35319dc457bcc464680d1fea448e1fe918440abfe6c6126b60f20f6cc8a900f102654a14bfcafaaa5ff2da75db80b2218db9abca85a480219f010001	\\xcbdb569bcf525fd85aff821ad5b6cba79a90b46e102f7415746159c9e7a4598a54d482ee44827a932c660d6f3b3b795b628777cc2ac68395c888b6da95509c0f	1674810464000000	1675415264000000	1738487264000000	1833095264000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
243	\\x3c56af3167cdc27438e0ff92eca43f40e30397167a6fd9827a3614b657087c76bb720bf95fd4a7dec834abd36d2faee93d62cf9479bf4fff101755f7c9d8986c	1	0	\\x000000010000000000800003d15180b2c06c2df0f3c75723aedc6a103e7ed9754bdd00e687955d2ab55f3b5e351bad8f20053be2b8ba2278575dc092a0147b14798f6e374477a2413e042459fdf79d834dc67ecfd780dacd56b9b548ef3760cfee46a6d575c11d4937085436f57b62ec5f14cc9bb72726640408ee95e57eb762d4fe5146e37cc08054b5dd05010001	\\xd8049bff6ff1e0644f149bc7dc3c95ec7129e37675715a296e9aa804ac0f48212dc14a73daf3094317588bd9fd14e3839cd4bc4d85b1047407b196435011dc09	1672392464000000	1672997264000000	1736069264000000	1830677264000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
244	\\x3d469a540fd9ee3a548ee7cdad555b0702fbe0da12df97b1cf9c07c5b12752b77b46306a01a5b93456125f74a7262b285ad4f319b73afa078d569de517cf7115	1	0	\\x000000010000000000800003ba0e3d9bdb83bbb7cd994da60983a25d43d21441ef2b38d9b690598243d7e8c1c162611371dfb650a11e658fa80689b48c466c960e059fa5be5bacc99ea8e5888ed4aec8a69b50f175348ccedb5e9dc97c62f5b8b5b9c834f831550b1c2873de9f48d7a6f0c496ace3005a2140cddf6ff7ce66804b370e20c23937cf37e455c1010001	\\xa999c9c936954c19e709d90044b6b75a3a13ff9a90343fe166ada4adb9cdecb78fe545df8675bcc2c2d3529679bd434b8e0b6a39f23f47786559c4061831340c	1669369964000000	1669974764000000	1733046764000000	1827654764000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
245	\\x3eba8b3491f3e9227e41be758400f7f938572e889035c2518d8cffe969fb6a9b2a7285c17e107abf8b3f1edf22d99e4453f845fe2f3a6088d69f0d96086f3c5c	1	0	\\x000000010000000000800003fb79b2906e261bb34310c04daab6918dad42d40c9e2561670efc78bfaa17b6aa59c7e61db881828100116aaf05ead990399dba69758bdc4239945739f6a3ac173a78696f383c1aa6a87bc027d1311c9c907ed6c029776018fc8d0a285976547668b29e91317882d5f8795a044367ea21cc8669b9496d0f4e6ef76df7604e91f1010001	\\x09df524ab9b8f03263c22e10e7da6bf7ce94b64c58992887ac9eff38693c790a15250bd0a16603320e48bf0b4a43c52c9f8412ef34524f40396f1c0aa24ab000	1660302464000000	1660907264000000	1723979264000000	1818587264000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
246	\\x4162923f73741eee68bff106e86b96a92182dc0dc4ac792ee7bb0a88089ab129d3074274a5bb3c74eaacfae8f08629e53aa1f0d3974c648ccc20da14ebc4850f	1	0	\\x000000010000000000800003afa20e8f1adf6ed07721ec49f74de0d1fd8f1f724622b391062ec3ded6ae6c3f8359d406a13d3cfe3159ae7ad1619edb29dae81d9fa567c4dfdb85bde9b03fff800d480015fb6e6251fe96023f4b2ae81dee1b6dccec6cd0146b8b4e983c4c3891ef5611049222e145d859701dd3551900799d56421f4b68ef1c42b1a638f3c3010001	\\x243c6d6721d6e1ddd94edca02f9c75556f3e8959c63847d96738ed216aca3064c032afe7928bfc30830347430fbab155d2bd6d41828569782d1c6e174377bb04	1656675464000000	1657280264000000	1720352264000000	1814960264000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
247	\\x424a9c12e3fa09a2ef39c947e3bb1534ea345a4fdbc0e010d2cbbd5638f2d69a0dc81664ae8a7852c96a55f5c4fcf7b5e627ccdf82d9732d76b01558eddab802	1	0	\\x000000010000000000800003a697b1e8d1919fd12b4a53e357427b3ca8ff2a162dc6204badbf4a6e6693af35dc717fd8aa3604a9cd363c9588231cc33c06f2527afa0f0b468fa7c8fc18019bd1fe79d939dccc91b0c82d56616e4b7e02362ee7d7f9838257ea3156e7db025bc9d3e915e8ed12b4fe1968a31df0f81a56205c54faede0dc1d18a7a87f8d6781010001	\\xd06a3288854445c1aaf2b4b17e6d17c4b1e3accde77f68f54e75d37b3676c781c51c1bd4d5078519d3a158ab9c17543917bdbbed25e110f7335f79aa54b2e601	1654861964000000	1655466764000000	1718538764000000	1813146764000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
248	\\x4412971b404ab094186465bbba0dddac8dac59ae7445b72ceeccf1f54a86048719342a6bb596593cc3298e6ff92f2210be8ba2c25b0aa500b3b884f8a6e21b54	1	0	\\x0000000100000000008000039e25eb64adf2f65aa40a3490ebc70f06c716f3f5378543465596ba6390741b4c7ef5509cb73a9f2ea920b706e3fc1c10b19cbf4893b15800fbc467b35492bf6fbabbf55c03fc7101e5b3fb9b48510c476d3aebd799a46db809e91d30f6a721463abac7916b495f8871a57059406fb7ba17d6a4f8e363bb65ea22318afd24fd91010001	\\xde9abea7e95be1a6f7f93079d3be26030a3fa62052c80986568fdb40b5e7d82679374bd522a6af972efadaa6c2906fbfcb0b5f2d11b9dbc3e6f7173fa66f930a	1679041964000000	1679646764000000	1742718764000000	1837326764000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
249	\\x441681600c693c55a4a351418199c4cb129ad335463bb0881c1147343373c09ca84c38b3b096ecd09e1fd3fae31b73c8d3bcb099317a1d1ce1b5015f02ff68b8	1	0	\\x000000010000000000800003db4fd2c577b43c0cd45116756834e80898587ce56177bc86fecdf5ace39e09e3f0759eb063cf7dd0273ecc3a698502ae0f075387f32ca7b645dc39ee9830a4c238ebe2eb0539c6362aec720f6718eff3f993088d19048235bfcf59ad928999d5b0b47fa4f3334e353f8da93003d5b6e7f90d6857d0d56ee2bc8334a470e13405010001	\\x1f44da426857a97f1550c017a887abae0d7ca43532f9d1b129e5ba37f883c0324f07dc783a10c75b9acc1453ed2fa4bc0ea81cd7749ab6cdbe0fa7de585fa10b	1676623964000000	1677228764000000	1740300764000000	1834908764000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
250	\\x510a28d02e2f8facae6d4be38bf9d7a32cee88c7cf2eaa7858447283186de22bbca617adc0a20b5048576c2606ec83a6a4795346cbc16b24da799ac697a36198	1	0	\\x0000000100000000008000039fdd435364d38a3756b10f5bc7143b8d888f6054674a8dad44629a6ed054bba4ab9cafa2cb2b4132d23bc21062b399bdd35849b33eb2cdd7b831b54552065c7ee4f94921d252346c9e6ffef37f8741c7bcbd786f4d0560b0ba7e6d2a112add0b7a2576d54a148b3ff76928850926d23040ec04666c2be45eb99a33f79ce73f47010001	\\xafd0024f85ccf71c8b758855f00bd9ac5c846234140972c1510759a3a97b0bde671b85030e0aed780aa656fcecb94201ffa9c40ba236fcfc6b8691c56fca130c	1650630464000000	1651235264000000	1714307264000000	1808915264000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
251	\\x5196b502d154d274a2420d76fd3ae4dda2189892a7bf62d105dd4f0f8f7464559a290021dbe0d29428d7f3cb1bcb0c1b60eb0b4ab7f346205756f084f3849b31	1	0	\\x00000001000000000080000395a48936c8a772c8e3f6101eb912e86c5474673e0adb8efd86ae6cf9ee84e8fb7161deb9229a23664724fd30eebae2a4e13740e56ce26ddd6c2aa766fab447972e091b195f4000664779ed693e5b58986423463800ae66b6598bdcbba68fac25ea04d0b956a9e72d103d94c18024ce10f7f4a70f0a4850c17532957813b4cb27010001	\\x8ffa8387b22621e61c26737aca854c6c18ff7a4ad48d7896d4664b0f11e232eea799ee3291b150897bb4e5fd8e27749821a9e840f0139b25713431702979eb0b	1666347464000000	1666952264000000	1730024264000000	1824632264000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
252	\\x5292c784533a8a118c3e8088459b7bbd25ea7b2421d6da1c8487b50e538651bb25f7e9cccc28049040f5210f40759fd281714ac91b19bdf36f01b5a5b57d9416	1	0	\\x000000010000000000800003be8ab61ebf3082f40c2a45cf206a82e30cb8704b6c6387bdb70fa75b3389f91c9de5ab4d42385d6124d410a2e3533e27c48e0c35a959651c98385b56e5c15e869bb0aae6302cc0d69405644006a268e5c7113a924d9d8726c90e638e5eb3c5341afdf8e04670d9142bc1c3a5b50b9372dfafeb37db17e45c3be852032b2e0c6d010001	\\xcf69fd7065f5d9bfc1cb58d8c143bf9bb4f624ccfea39c359f69970fdcb3f6e3387f57cfcb62af5f3ecc5814e9f96bf1cb59091ecba2cd9d8c0756215e4c370d	1666951964000000	1667556764000000	1730628764000000	1825236764000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
253	\\x53ee518186f9217d6f35bd747257697cbdd271f4b685434399c7868778407e06eadddabee45b95e910bbcff12ef7e75402fc3a3ef6bb8620e950b85b1e53eed9	1	0	\\x000000010000000000800003d6819b98342f7925076967e8fb53b8aca6115effc0e2235e82056bd545a6103b404039fa75303d582d62e65785539859078e1394bcfb7312130fd8694154cfc87d396bb69cfdf317972be866423376ad1c37b2376bb20704df3eae8c5619cd881c140c6edb7b7d7e6a74fcaba981a2cf9ed635cb740a23f4de6dd035092e9331010001	\\x796464e8e2258cc31afae11e59229ed1f46cfb8a18a7fbf2ffd7e57e2bd86c2e1680cbbf7b76437032daffcf0420904d5ebd8bcd95c3b919135731550710fb03	1671787964000000	1672392764000000	1735464764000000	1830072764000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
254	\\x53fa598ecdc9814738381d9546c30c920b8040a205660c79fcd409a3067ca74251e3a18658226cb7f2ee3dfc881b1ef956e2dd4bb40386ff710d478e9d34d5d2	1	0	\\x000000010000000000800003cf87dbc173f920e02fe4dace512233232d22e4d7ae1c13dc177ae46fa9ded1a8aeff6975635c19ef36078e6d846d222a397d26e2f1de28d16fc049cd7df55ed3ea6260bf401b5d69f1860e989d21eb78b79cd78dec5c2fa64d7c9e329c0a53748aa8946167c1ef29f1b212f1756431b37620bffe574dd9ff607bf171b7b377c9010001	\\xd1685ef4b65a692966dbd7c11553c9f8830bfd92534ad4dce5cb1597f0d0b2cfc8b2390bdfb8ddecb7f50c77514f13cdc2b7a7214a850812c0404466cb0ca005	1677832964000000	1678437764000000	1741509764000000	1836117764000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
255	\\x54da4d71b23cb131d57fe4396dc6d723ddf8f96259ce724a0c404e65781f461efdd6ee35e74c7cbd6d6f1e746285c1d2c548647ed1539865d8919c21557afb79	1	0	\\x000000010000000000800003a08a8a0d36a03bae8b6ad0d1fd815628d3bdbdb69ac5be401bcd19b15c58e30cfd9ea0643915d8501ab46ca319584d6c0dcf56022307218ad5792733d63195dd285fb2f6d65ffe1412fb0010ceedba0e69c16576c9b4050ffad8f7498962dab8f56773a84534fc4b9e16f673a2a6be4eef2f40244bdab8c8fafffff7a90f1935010001	\\x1010929aee11e204ca2d1392e86ec2775e3c57ffe458a2f6c83c5ee3d72581c502f50cee20f2fe53f9db5aff4c2644ff4b1a1a093940e3b9b2d794ecbd93ea05	1674810464000000	1675415264000000	1738487264000000	1833095264000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
256	\\x55321484ab62818040ef37324d88ec8ce73145971a1cc64a596e5bd22c2ff456863f1d8567c4ef5e720cdb6193bcadf898b4417808e16b6a9b9a9f75e8d625d8	1	0	\\x000000010000000000800003c8eac26bbb359caa578080d0c94c6a4d06078c3b3f4d0ff0474396303219e1bdcd15bf1682ff313068f60149aa32aae5b0bc560e3d7ece7c6e52e3a7b34dcfd16519e5c8997003838714884447be36dd31394e69ca29481518d81154b16b6e4b8d897b0e57572e24f0a81da5a89b54015778abc843812252775870f97f6379ff010001	\\x129d5020ce47700c40494286580dfc4751f6ab97f55cd8e4719b5dbee84c9c19bad306c2b26c236343647334539ebfa80eb51970b34b5ae30d31764a7aafc601	1675414964000000	1676019764000000	1739091764000000	1833699764000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
257	\\x5ada96fd00f1b47309c038d78210612ef926a0a9820ce5d9e99c55a75cb57114b0439e199de8e90d43b2ab3798c702c51cc09a46627761ec799c58f338d60586	1	0	\\x000000010000000000800003c4495be1994925158f40a1ccca9c14dcc719184a672893f3d19e71707b3616e2e89c1d3890b54d76e8f777dd9e9753105c075a13dd5476a3b43e2cd5a7b9e37bf5adff1f1e2bd78db0ccea3bb92d93ad5d61972543a67be4870f2dc78be5b67bed2d018e6e4659750bea991a0889b3258ec0b380e3cf369778ed3b26046d6155010001	\\x2a02177febcca02c102953344f60d7fef3d88d79c020096ca9f15a6b2de14ef181adf88d60bc9e9e1ca5c3346e6eb2d050292496c3495885211bd32f644f7e06	1656070964000000	1656675764000000	1719747764000000	1814355764000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
258	\\x5a4655cec80a9d311c2ede9380c333b7037a5e0c176bc58b9b9f688537ce941251bf975b53940611415a398a34a417fd91ef72689078c258df64765c285c2334	1	0	\\x000000010000000000800003bd68199d0cf02cc1539b52435939b3de4c0d149bf54f750f7d26707fb7403584f039336c3fb469bc9d43e4086edec87e2417188106c9513bcaea97a206c3c30e894050d49f53015a9d33924d00fbc6394c1d9d87a7b88f2d61c512accbb4e170cb115b89e5df7013c03005c2afd6e386a5dc0d7f83303278886213e1c10caf85010001	\\x75b054ebf405bb55eb8e67fdf7fa830db95a2fad0a1b71a674e9af41d33756538229bfab97471bfcf1599d7edace5763dd3ff86b8d6a6ceaa11f6c581ff99004	1666951964000000	1667556764000000	1730628764000000	1825236764000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
259	\\x5d6a2e0c86787034df8cc15006d13419cb384e47adc94445c714320d87cde24fe66fcba1f1fb06890338a6ecd0410fe7f49385b6d9b3d1487f7e38ae1b9c2cfe	1	0	\\x00000001000000000080000393aa314a21d956ec0b743da2a72a6f2e371b2bc54d60764038fb5ce025a4406bd966202281f7a8452961074d9655c21ff21857b241d75afcd35b8e74d38bb90c24c9cdb9ceebcf0a4ec9b5c1e3333d60d11c94aac395edf668b3b73a10643b2fee0258b56388df0c3516f3d1992c73c1c3fce87ce9338d273a7694b8a1e2c481010001	\\xbf9c670c7344388e65f64728da3c84255ca380d413906a66160ca65c388a7fad6464d03d22d6ca0268ad7865f109e4c74f9b54a42b5d7e42f8f72dd0ebf08605	1662720464000000	1663325264000000	1726397264000000	1821005264000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
260	\\x6332c16f386d861c837a2583b26c5333188d5fbc9a825b46d8f0f87c400f14fae41236cef4a007d669fc32f40bbdbb89d1dd56bc1dae300fcc2a71c9499c9f93	1	0	\\x00000001000000000080000396ca6264f2cddedd9d75e9f90aae6f4b7d51717aa9abf579db2d6bdb2b34e3eb1eeb348edca736491fc5a20ab94f62d7f3c5bfd9ff7515bd06dd780ffd356fec7620f13ffdfdbf9f16520454847882b32b29f1b06dad2ae28237fdb38db2a50fed6d6060108a15b3eb84e04a3d421bdd06437e0b3ef2ee8fa9ae5be9925c5527010001	\\x733534f42c9cfd58263f89cb929a4a21aa86e612f2d598de4501ae9b7c89df193d050893663ad462ab389644d4b79f95ad9bc96a90c45e730e330056b4c3f003	1656070964000000	1656675764000000	1719747764000000	1814355764000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
261	\\x635a202bd2c38fc30e3c12d52735049b9c63658ee1cf62842ec69d3c2b51c50abc05cde9ff64eeeda35b3d29bed155b78dba5e0f210e629d14bf83999401f457	1	0	\\x000000010000000000800003b6de1f8576ec0313c6b507eba9644981be72614a7f7c9c00fbdc3d66369d0056b979eb8a1b13e31713cf22dce54599033e000c5c53ff29ad37526ac315f00f5796edcfa08daebe4cd04e85ba5d497c79da2c1c7df4b7206db154a63a828700b9926f5d5dbba685d0685751a09842e9b2e1d07675693d41b153a0af4bdc349cd3010001	\\x33b816d14c3a0049bd05053d0264c31710f2109725dbfa8f78438cc0cc2030fb57d7d6f5ffd65d48733294d625fafb003ae0d8523037721e6993c1c0c3331a08	1668765464000000	1669370264000000	1732442264000000	1827050264000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
262	\\x6ab65e00fb63f2a1809fea78262ee94250cbcf541d098029106c56ddd93747ae1f2f5fb0b23888788fba985d1c703249eb8b5fcfcf483b7ef05ba3e040e0eec9	1	0	\\x000000010000000000800003a875ba9a3f040fc715d5590dea24c34ae49ede8449c2380673ed21d6c6db964dec78eedacec72ff454616e0c34752196d73660d7dce642ef7b8538c5422c6ce2db55ba52398983857d6f5c41f2074edb50fc62e776ee00bef75e43b62da6a3f86fbee9cfcc7cf9e18b2cf3377ad6efc6a2ed847aaa69e86021b0ab492dbfb2bf010001	\\x3e5b26ebfd39a9f9469173a13eb4b557a2d468e00da69285538af267712d10e0f8bb7f82628a1f009cd008dbd6950158f9fcd01e1a46c4d08382c0a702beab04	1660302464000000	1660907264000000	1723979264000000	1818587264000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
263	\\x712e7b781b587871723d4cb2bb1e0a29019a14269e7614f5606edf5dfbe395c63995dbf99cb210645c3e0f91f10117a7d60aed0595bc642b45cd233be52efe3e	1	0	\\x000000010000000000800003976761bdfddcb8807313ede3cc5bfaef4a61e87093c6e272746d217545cdabf491abd9b13974c23aee0040f10f30d618040f6abd978783886dfc86f7f7a5fd11ebf488405d90091e0053db705ab753ca4682a3aea97fcca9598993700d0871991549f2e5094519edc39e7243cdb74741295fd34f2ecc33592cc1efdee554bc6d010001	\\x320a909657ac92724b00e79cee087ac55531a0023d0b2ff89258330fd547cb10f83298e6bbadfbb11d6633c3fdc488f88564fa038e08410a9ffc672ee7e63b09	1675414964000000	1676019764000000	1739091764000000	1833699764000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
264	\\x721e0c535b27b3a94f2d3bf93aa029e362beaa57e05ecaaf2dc67d583385fb503e6fa33bc2dbea5da8add029da213728a16e95b1c04f5ba787175cf21c30a792	1	0	\\x000000010000000000800003b0883c3f839967d8a54054df23b99df5b2d58502ff522fc67e565954801068e46b18b3afe7670eb7522eb54369463f42d4ce5449c660fcdfec83f64f55b5f46f974830254827897dd97e06a259b724c2dbeb7c9fb334160dba0c82f06a697bbe5fc8584fd47a679f5ff31e9ee6d7acf9f079b494884249c69344c65da5f2252b010001	\\xbb9059f080f775b77011ed92386a8e52a1d89d642e9ee1577bb4b09aeaa85bb5f4462814286ab65fc0375891b5eaf1ee26008a98ac1190e97be4d7e7e45b800d	1671787964000000	1672392764000000	1735464764000000	1830072764000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
265	\\x723a620bfde0bfc7053c969ced4b1044a6092327556b82847116cabdbe3c07832bbfdc5463369f126207045ba9280a91679a8b5bece4fee8c49eb525673f84bf	1	0	\\x000000010000000000800003b442023505d3747ff918a1168343b8dc08e84bfae3919d0699cda9488e4da438c88735efdd9601e47f16f84c94430cff279db84ce54a83852bf537428d6833438fc49e77b80345ae4b997d0474bff810533ad881a38788e8162812f02a94fad593b8e53657fd7120b03a480d6cc818338fd7e38840e42e40344c767131ef8687010001	\\xbf56c76b5948529025ef7cef314c6cac04c3402c275c1f35b6f4ab9b4223d7fef63c5a85874cc1abab65e43e095e127a4de3f8458ea32d4cf89c4452e99d3f04	1669369964000000	1669974764000000	1733046764000000	1827654764000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
266	\\x726e479394bd86d7298bac6b3054b4e32fd7e06e86c0dcd01b870d15d5f56b9c1f91a6c3242a59b72343e1f637363947d71046f6ab33a5845b05439bfcb2f6dd	1	0	\\x000000010000000000800003d241d39e3ba6ad95ec37f40e05fc07d226f436471f5c2c7dd23acc8c00d9a9f4c7cd20d16060cefc21b0ec63d2d88dbe7b067ea0ae9c5ccb72a43151c8ea35641f8f77f78482e6cd868c2ec5f5baf7994e573ef018e21c3885806619f8ed61f8a3e00733cd19a5eb02575032f34a8d97122a3417e68b6bec18bc977d5e793489010001	\\x2c8f7f13cf2f50538fefe45972591c2feef454d592dccd4a151b73958204c7117cc90cbe2614d69013fce3acedfa1dcdfabe7d446fca2b97823c0db081535d0c	1676623964000000	1677228764000000	1740300764000000	1834908764000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
267	\\x73aedf7ec54a411c37ea9bdea90e9290d9dd0bfbab967a7441a7b8293578bcff25534f7a4bb8b6de9e2551e3aec1cbfae2475b9f76d265d56c8f4ee63ba3742d	1	0	\\x000000010000000000800003b8b65492448d796492ed23e30e3d81511d23753a8897bdf8426df5cb6814420540a3eeb87ae76ca0f44c9b2e5ab25212ed4c9330d198ff24ae6d3333fe6b0da54823cb0f771777f78c34acb594da489cbad8b7deccd10fe065847c574a827c7660b4c67230ffa0e8082095579a6d9e371454c441b59e8c47ed1ecc48078cce07010001	\\x808e41223ca945950713d0e64394b0b06ce9b2550419c27a3aa8f6329f22811cfb329b10ab41f65325cc63618ba7fcb7172578301e13814cebc658e9982b1b0b	1664533964000000	1665138764000000	1728210764000000	1822818764000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
268	\\x749222f642993b8c13003e325b2d9217ae705c3c8f3c7483878f7491375887a84752ff0e2db3a70debd51668c478f087b1917f04ad0e49680bf2e25d8b5853b2	1	0	\\x000000010000000000800003a0b9c17e7eb7b1b1ccc3be77635f567b6cdbea076eed6ffdd88ebf28f7b66975dd43ab5c2057b62364f8c9f31fd23a241607adeea7c8522647a57ddbdd0967a1b7ab7018bd24d556e60a08eb4b9020d68f7accedd3140dca7d04f5d905e23036488c8605d73f15b075f9c60a3c264b9b868465165251ed6b950a75e543cd958b010001	\\x6e8e83300d4a71b5c8865ad115a0ed12150e4ebc6caa2311a21c4c3c708cd4fbabafd41f196b9de8b6ebe6da0dd16bf826fa3264885afa5d777f935c15e20405	1670578964000000	1671183764000000	1734255764000000	1828863764000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
269	\\x7766edb2ceda401505a1925d7b0218a493d2c39fb096701846ebe5ab2cdff177686f643be2538bc5f87b5adeb7dae32af2bfc64b6d1de0d20c489c528322d7a0	1	0	\\x000000010000000000800003bed459bb02fa363b92d983e539395000047a0fed92afa1b2fe7bb2315e835e8a08f57f833bb0858940bd5e7f164968f2883d0504308a6f204bd45d6ca118d2f83a4c89c8e320d308af3f81bfd60e05e551306a0f05efdbfc725e7d3b1145e12119f355b37728287e0f4979c5fd0c27f2ca2694dc7dc59fc60f0f5c2171e82e81010001	\\x311c5f46fa4a92c4d0d367260ced017dc8a24751448484b76497093047f19527435e6b9b7a95308922bfa62cc7ffd9e7a5f516d5ea51d53b76384d3a42218b03	1664533964000000	1665138764000000	1728210764000000	1822818764000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
270	\\x79262b05dff4776db2100e3b155f0a2ae3ab12bf20edfc294954c9205c1c23e1eaea5711fde86131bddd4e6c51c3ed8e182333c327b03c6219644b9ee67b4261	1	0	\\x000000010000000000800003b7b6761357529fcb17c374b1c045717e93d97f2adb363fd1f1c449bf022bf6611ecc59142cf4bcd3dd1e60163d9551b64aea180953011749ceec28ad6ac6b7e7aafa9d0dcc3f1f145027e44912c8a9c33e787c15f5d62c16ba72ec356865414b4b554df9bb0843363b815f156d37a4da085c90f58b4d57eae3530b61afd59187010001	\\xd692aabfeb7be3bba2c3f1da80bd17f3ab82ddcbc1355d1bebc5cb4d8e42134da6ea05454a2910e9d222f6863e8593761772567b8324a10a34cd0b74a7417f05	1661511464000000	1662116264000000	1725188264000000	1819796264000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
271	\\x7b268fe51bd6222da8440b4f34c243f8b88579e848ddcb2e2f4f8447e7596dff3285f9f54fae80b1e9da7c22aad6f1c6a7774c474d898007cad9a149d99578ce	1	0	\\x000000010000000000800003b6ede0bd8f49e43b96c41998a0eda71d5a56b4e591ae8ab7b82a2d83c821703aa4002369a2c71ea572abd0f340490463b24a0afe3448afb0d93e36aa9a1814073dddf303e70fcdd6c420bd0264349cd96c4f5fcdee6ba88a37e795d7ca9f247c8aa7f743322337897196ede57e5b58fcf543d6527bcdffab47798a081da2e5eb010001	\\xe3cd896aa01823398c40df655cb7100bd6c6ba50e315a016fa76d8d23d1206988eace26d22c94ac4809aad4c26b9bddaa0a3c4b1875feae1d293fda98e083908	1674810464000000	1675415264000000	1738487264000000	1833095264000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
272	\\x7c6e8c6c8f11b5eb379e532ea256d895583032640b8a61f51d6c81be1d6b1e50db5e2d3acf779cbae8788ebc563116e9ffd5d71a0d56c1a18e7a2ae24cac32f9	1	0	\\x000000010000000000800003cd3c19959eece72c9fc16e0c6f9217fe66f5daff1b899a2f80245741f868cf521f92b48b8a505fb83086fc1e7f961c8a90eca3e78090c6983f2b496575ca54bbb9898680b0caef0d28177709e5df282f0a825a86d2ac2319000f7cc60260d1e2c4aed3930703b47b9a17bb6e88f448e64612b8cf46197cd598ab7b2c67216def010001	\\xe32c32cfd85ed209b77c765cacaea64a90b7cc85569ac50385980f58280c106d287744409956f79eb8ac671b2aa0fbe796818bbbfbe771a1e7df50f6b5b89b0f	1678437464000000	1679042264000000	1742114264000000	1836722264000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
273	\\x7d76fae4b71c54a27eca7b323ad8aded4b0dda82e7c4540204a2c98ba5bc93fc49058b0a2d4435c9032890ef7140af9dcb1755176c7579ccfad9a054a8a0a4e3	1	0	\\x0000000100000000008000039fc775d8cd2089cc19b1b8aab0253bb3e5d3f8c886f6e83c58e0d899b603c1af1f2a134f3e52d26013c380180b2aebcaddf3f7d1eb85dde4a021ada71046d8d12a2f49f9b4f584955c16e9f96e97e1cdd320bc5669cfd75e19b6cc7cdd4741616d012fb3cba821a32d53a6a0a1fb0171beb30e9dba66ed6b69b9765714527c5b010001	\\xa5043e0d18a6123ff6e12810c582a6b58d26860127560a8ead3a9038b217c732553d8ed56d24417d3098ef32dfe999a805ec1993ab61628b170c5b06b1798305	1677832964000000	1678437764000000	1741509764000000	1836117764000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
274	\\x808294ce0cebb2569451d423134e146c440ccb69ba00ffc7e60e302aa1793eb34cf823a60d35bcdd24e96ef55b0570bef7a22efad90a3eab86942aebb555e231	1	0	\\x000000010000000000800003d96cbfacf4699e78965133c703fc621665a2556fc5012344ef200b9934ceb500e4aa562061ad24c209c4005caa645c21b990c1cc945a1d04affc3b912f23edc1f0ba649245134c882693198f9f181041304e888fc7eb7efb30ffaa8a34b3848f2f2d71794a010cdde440d5a31f5f4face2d8d24e91f6bf4227ee76fbe0519a9f010001	\\xdb8482dc2eeb43374f7051a933f1e5548914e1ff3bfe9ba60f78161e18a506fb6b069210bdb4373a486fce49a27bbec0fe5cb38bd193906fdb831f172d1ddf09	1679041964000000	1679646764000000	1742718764000000	1837326764000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
275	\\x822ad322b5c7a7400498389081206d4cf74c6e3481d23abc4a4a1bcdd4cbc2f927153b6278cea96332090ae05320090dab4a852701baab18d81c4e3f295e6b25	1	0	\\x000000010000000000800003c05b2f1e33069d62d7d9bf4b8c4982e3b00b151f7031f6ad667375408f6f14507b37fad00fff2527999436571c698c4572b4b931d2ba60fd3e71b0c0d6914a2066a6623268ef226427fd4b1dabf8fbd1d1dcbcf4354a8900b837394f3f0c3feef8ff582f5a07b25cb847cdccb4c3ef62e9149ff2c2c3dc140652ad097b7f6761010001	\\x67ab0e26859712e1d6a49cd3f6b4fb9abd91e8b35b18c21ecf6865354b747ba2261acb297d672c9f0103b5b962ff54dc0b9de0b3f30c7dab605346b6d73c3a07	1658488964000000	1659093764000000	1722165764000000	1816773764000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
276	\\x878647b8143fcb8c1ad571a2bebaca5c8783c0afc4559b534097b2572d11e81e2608eccfbbe6da51e01499e1fc1d772df1ab35439eb07de2b0699594e8db8459	1	0	\\x000000010000000000800003c0f67799b25efa19b3293c578353d1cb8d403bacbd24e72a800603e0fa1fc83847e5b86e3e4681369ecbc269d29470ff8b65025467bb0487c5d4c3737aa116f622e25de684a7786c423cd02ae9c6c99f62a0c683eac798eb49abe014f6a8a0aa1922f254f58f565861e8733307cd301c2450d8d547a07e3a46b60881428ae737010001	\\x17bef5837d00a79243fa6cf2bc8fa797deed00ddc35adcf799a5e524e24b7f7c926e03ba918928c38a8af17b71013ce0873e6e9f8f466f77ee4045f492fc300b	1657884464000000	1658489264000000	1721561264000000	1816169264000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
277	\\x8b3af8ce5eea46a49433a4fa03cf29f927290817d5ec0e205cd73bdded2824a4c90b59114c52ae472a18a105137ea257d53567e421b2fb13e174c0c30d56fce3	1	0	\\x000000010000000000800003f72c520fa25302f070306df5ce59d66a860305fdeae22d7bb4270852b88521fda5aef13c68bfe474dd638e75ebd9b31b7b583f6860722dfb0044a13d3f82223ac6a119f6e9573d788cd49c38532a564c9f209d6e395063f4494f7ebcee08ae27540efff39dea8bb1ab3dd8ab22d03d20f01c9eb5776d030f8458875fdd710fcb010001	\\x246f76bb242ba753917c6b08cb1eab77fba575a5cfa08c7220a7ef34163fcc6f91c7896960c848f879cd206b88d969bcc7d1d3daf1b86620614cdf4440a2f50b	1674205964000000	1674810764000000	1737882764000000	1832490764000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
278	\\x8eeabc5e5ed7ae62f179151a767d817ff37b605fe536e2b0a0c51120f2fb2e912a7d1435511d18ec42987a747a64679cf89fd6629e29e8dd2a9d0e1083c129fc	1	0	\\x000000010000000000800003f009142be6d3ad9781e0032e44f0b3f5ece9d723bc4fdb5d140b2595414f5efc4c8cd2d9f17776bfc182a1b5e5bc46f5b6b4fa0e6b97bbe2ba9593feca9379ee64313816c5fdabe1e79b02bd5d744345f0db07f5c31de5ca7ef6e085bb67b0d840e7ccb9b7177ccb746eda9b3dac12e44403aed82294d4e73305140bb7202a37010001	\\x61ccd0ba4c4baae29913a11c85e2de58106da32800b90f474b89e4c5017814af86b45cc21f5522ebd0e53c1f6cc3d8f6ff1cbabb4aea7fe09725b52e08be5f0a	1668160964000000	1668765764000000	1731837764000000	1826445764000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
279	\\x8f6222741455edf0b5d7b06f34965a40ecdc436e2277b81e52276e78c30987766a62cfc08c65a3fde8876bb6c65719627dd9fea20a6646194cb1e02dcf322ee2	1	0	\\x0000000100000000008000039fdea0fbf35d9c263325683c9449bd2c71513f3d2eb685127673c9d1ee043e3999d2f9b41890243f47c8cd187730c9ebbe2e348bbcb8e74b1129e801ff631d735b7735ddcb8061ef64450e5a66c1e81a8a414c2633704704bbdb285bc0c0e8ec1c17623318e8187ecf461db0f1323e4f006e4e02f0934e3dd2cb583b1b54e0d7010001	\\xb57c6539919d2e50fb6cdc94908f16bcf4ef144bd0a43b952285577dfd09d9e37b1c31bcee6972386adc4871682a710381cad20bd8ff31c7ec60a478d779360e	1676019464000000	1676624264000000	1739696264000000	1834304264000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
280	\\x900eb36571416b38af84edfb0f67d47734012173f4ac3de229c0bb6c3808940192a8213c63917a0415a1045e831883b19dfecacb52178e168be0ad221a40f691	1	0	\\x000000010000000000800003a9140010dd15c35284e86ede2bc57941ada4ac0afd8e2b691cbf4262d23eff9abe40fb9f936a5d6f5226043c68acba76db074b835ab3d1969d521872e59efbe050195ff9553b10e9628b1ac9b1af1af144edbd9321dd0d5f50b9850f1b453adc366009c8608309811e30635a699440c8033e1df507ef20d0f93fd3175bacfc43010001	\\x8adf77edfcb5cd4ac15c0d8f720f3a6df1d7f32ff3fec52cb053f7f58d0fe57afe72c1a5b2dd608284a7064e4668a88975cbcf4ab38d9826c55faf7f6af0bf08	1669974464000000	1670579264000000	1733651264000000	1828259264000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
281	\\x912257eaace3dc81377819e9a6936292c2f646f374bfa5c9bf55cf8aed27731f1e0e8b59f40c6b5c6f957348e918e6bf8eaf2b9a371660a67efc2639ea1f7867	1	0	\\x000000010000000000800003c275163438f1194ba4f7986df6d81d679a1473b9f1cf28047ff719b9df018a69bcfe78a175427e667a2c11fbd10d88e04bbb793f0811ed2eae90cc8558311dda1931033c615e79199446670c8e45cddfdbf43e0a9bdabf56ea6fb1aa501d507d79ad65927970229a9b5539c577392f81915a54e9b32d7a9ba8f24315a3f42a73010001	\\x799c26c94c56216d8a56862d1f0718a7e77dd248dcea6b06107d44305b9ed35c3c5f4fb592da0e71ae8fe101e10200082213c81779025fd63689ad6e5d526608	1656070964000000	1656675764000000	1719747764000000	1814355764000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
282	\\x92e2c566e124ae64027c9e8b28b8c47a8f2be4ec2ffe8feba16b3ec266178ba5d0a6943d9a687fa15aab7942f4ae70dcb97fc59c8c5c1fc4762a1f62294e85bf	1	0	\\x000000010000000000800003d3df3e47e64319fb42926360b417b5b3722e5e6b519262671c67522ddc8bef0316ad84513562d15a67a9d3921d023a88c250458f153b6ccd0dcb71235b0d174f73c3d2c99b3f69e1c2b266f9d7219e20e47eee5fa913e9ffaedf8d6bf5083cd5249c447f2d40f7b9b2a41f4a649e4727114509eaf2740eea8bfa21d1a074b0ed010001	\\xf2c29d4ec0cda76c4a706cc66eb764fc22890b6e065e246bf7df67d2b155a871b4d4b662b59c4f0dd0308803c288966f623331c4e4ff4208e38ba11083cfd301	1666951964000000	1667556764000000	1730628764000000	1825236764000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
283	\\x94d6ad929a91a98b66727925b3018fd7070a023e4549a911e3b349a9edbe64f2580c2cc7f23fffa84f1884e3530d522c882e7c0d43415f3521736a3d42035eeb	1	0	\\x000000010000000000800003da3b0f5a8642f42da87c71185331661e0974de392865825534c181a486d4a0dc52bcb660758e89728e622a11e10b8be853e7e2c8a773affc2727969aa97b99fcdf10febf02ab1c3cbddbb199c777f1b4a5ee54bf1f18eac87ee3f61a5c5ae8e158362782e659957724431b9aca4dec5965d94b007efa03ad976dd5320829e809010001	\\x9b72125a25e50e9e69bf20f471e4f7ba4bfc7df60bb1d0bcf88110dbcfffad0e570eca702863b48366465c105e7d8f22c6ccfb77919b3f33a6d4214eb0101403	1656675464000000	1657280264000000	1720352264000000	1814960264000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
284	\\x9a8a89c4f721256bf20cd53b8d5afa74fac766a2bf6f3780ea675f552c5e193f5761d9aba49bfc545cf6363217e86c42d06e9d2ec1d54aa1d129f451141a38d2	1	0	\\x000000010000000000800003eb94358439612608e959131e0e617a4646941a9f4777e9a4b77772d3267df643c32a998bb9ad0649f116933549b0e36554b3d6940c5a82602a9525a573a4b27cfc6e256003f22f6978786b5901462ab81d0d6ee3f75b601a0b1e5e25901654c23e5ff72cca1d7e72866cb793ff46beccec7831f6fbd5ff969b0e8d5a29294355010001	\\x241c79f3dc3ecd844636e62c33399ab6ce5e643f381b6a284e0000be7d1868c9373c0cb1977008e7c46502e190390e3a7a918694a9a3b98fa16aa00ca4ac6c07	1673601464000000	1674206264000000	1737278264000000	1831886264000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
285	\\x9c624d6d031fa10fa4ae08f8c1e4169da17362a9442fb69b80f92cfa591244f3f908daf9c3b0867465e3b7ef1eb48c6d10dec7182f856e7589a61f3a0a18a11f	1	0	\\x000000010000000000800003a83f1d04dea99a31ff71559a012aabb0c2c053a5732e1107e7e4ec91aca28123d54a01d0922f9cc2fe1d06b63415078ad0e4433895a3c5f27e91559195e22e91ffd65a92044c0acf8c94700a1251ad2954594675f7a7f3f0e1a16a31998b66abbd904704cc225cf77ad7081878efd9c0970ed264505d835d6144e1527890e891010001	\\x81e7223e9e6c45a5e0eecaab20f9240ea1fd84619ad1a4e8f630a512120cacfde4a2ba7a3ca9d848d03c75114a3a0f4d4f04045c88842062c7ac8ca315b28603	1677228464000000	1677833264000000	1740905264000000	1835513264000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
286	\\x9cfe0a8e64193c794237ada4572aa89c1086eb0dae67bcec9da469a2afe417793c5d3f0907667e3d7c46e140b6c71bbcad47aa5acd0effaec58d1305ebe91493	1	0	\\x000000010000000000800003ade88cf657ad4805f9185f7f4e0c3a47df1ba521a9d58b1285884bb3f1bd686dcb96d6a5787c2d69a2c9d1a10b678e95a7d8e367b339a73704490b700b67d62ce3ae1d384a213d3859bd6155aed01190d6491ddac9b26a3215965bec55a674cb2933d38428c0a7234ce37d3e888111aa184957ae94dc6e6ec994abd925df021d010001	\\x63e4e7a849817f48db83c26b814dfc20634d2b33aabf3fbedceb02bb4c1e077071e07a76572158402a68b2bca9ea53ed4091b438cf05f7d0902defe1d35c820d	1656070964000000	1656675764000000	1719747764000000	1814355764000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
287	\\x9fc2b0e29c9c14da6cc16794351f87266cec83ad051b51fe65658a9ce7fd4e4bf89f4b7b87c74ca2e3442ac2625a7515971589b83b855a0e7d17768663a92cc0	1	0	\\x000000010000000000800003b0970cd155dc2c58e501701fc3eeeb56510656d70dc10e7d39f9fdc7359d176b2c3e1ad18996e4829834432c1030a979bedc9e0fb8c158ace087ce7062ce2dec84d05d0f21dc79356bd46ce8ebb5143e1456090f972a73fef11b8b8eb1f5af8d13c3143b6a38fbcb060f717fc39c1c6b916c2c76ed75ec901875b2c04101c30f010001	\\x9c2346f773cb53328c387f74d0a273c8fb5374e8ac33a30784b8b7d158de46fea9e5f59b3a9007ee38b39c1f419e05942c141ee08d165e5bc55f7ee8febd9909	1678437464000000	1679042264000000	1742114264000000	1836722264000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
288	\\xa2feba95999c77cf1cd477919603867d63b4e633537fa581bfb0e2c740a072a3d4dc07c1390c01c8731f7566ce36c8cef6ffbfed304051de2c58d102a49b43ae	1	0	\\x000000010000000000800003b8c4ec3951d94503f98c91d50485c743547cf606837cc99beef67a5ba80fe6adc7c718c02a3356ce1a8806f4c8d34ce4723e4476b83ac8bd2f72093e7094afb7e20d56622e0fb3df9cb99d4917d5879e7b6acf921ef46aa2e0fcb77d3ebf100062dbf9a85d688967d5bac5c87807bea8dda715513b482e6adb318b04c61bfb9b010001	\\x9acdfe21866936ae1c47bd3ef1115eabbafb7d666783ae396e0f733c76837ce16ab4d9643ab426e3173dbe6788cb299aa6c011826471f4d319c6d971df6ae60a	1677228464000000	1677833264000000	1740905264000000	1835513264000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
289	\\xa3f6f7dfaff3e528dd29b12b362c2f41f33bdc6ed7d75a038f27d420ffa3772cbc49885083f54c46e06e92410b009cd59b51e4df6c97e4d3434af8150ce5091e	1	0	\\x000000010000000000800003b1bbc9f38e525b7b7ba5bad58b846a9931f60bed29ced94abb7076b58070a700e830bd0a2e98f48472a1f097d6e6b9d306b7e668bbc2baa9f5d873cc3e157e8e0caf34d9d283413c75cea8b25113f9ec6a7a8eed7cf8b06fd9d05764f2b9be4d1e7d4106d76cbaa1d7ea257facdb587c972e731281bc6bd745d27f8ee2d8b0df010001	\\x63174b74674b3ab07313dd3d3e423c0790e27c56f24de43be1b39b3e487e740e0d8af443af70fe14a8d6c2736886ae362add45eff7d75cb57d4b1c75bbba4d07	1653048464000000	1653653264000000	1716725264000000	1811333264000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
290	\\xa7a28a2ec2387ddc582cd9fb8f001f7dacd7a3ce5c4ad353f360cf0a662e7a4c892fb89dd4009aa40f83ab90253e90a8eea6304b755989e8199da32111af1874	1	0	\\x000000010000000000800003a8ff1e1f2cc7ba3412f168be7759c472fd2a1cf65dfa80fbda30a0859ece841aabcd278377bae5de274b7d75feffcea29ea47375fe5e84391c1ee6b3ed83703afb6c73a2e359702f5446af9324e67485fbcd94402eed627a524fcb661a805e2bb0a8204d4b9fc660ce46198e29f2b2e9ea09c8c4fa8c73054177de305f66adef010001	\\xcc24f017fcffda27cdf08c9e7b85e21ab14c449fc51513e4d24039c9797279078339060b10d66a0984d942c82cd8c719ccc6cefc3bf288b626647f19fdeb9e0f	1669974464000000	1670579264000000	1733651264000000	1828259264000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
291	\\xaaba7b7760c237f8183063db2fbcf8d20259d3d1b440f2905349a169c6f48f88f773a50aa1b56e6eab3c686a8a5f1c5b47c5e6fdcb6eb74aabac9c4c9eedd98b	1	0	\\x000000010000000000800003cd0e0af173115518ce87cbdb57de47903e993bc56d5b3364ccedbda9b643a96161200ea1434c8c3938f3bc9c32959329c35b569f5640cb6e51a0747d435a59ea2e49217df74691f73ad78e66f0bc7c548712fd5b2675aaeda8654a7dee44f3cb3ab12518f6b9ce9fa4c8262dcd10a3b337e46b3e8ff55f6d268e235e2c6bfc81010001	\\x9d2029d30f48df4b44fac1a7195212d9b7adab65ba764fc46e77880d3025fb2546b56de8d127410f4efb6e8c7f72a00a2e97f82289bc06ca8dfc125bc12ed40e	1671183464000000	1671788264000000	1734860264000000	1829468264000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
292	\\xac56cfc4249793874a179ed4ad3d1456689b9d769103f33aed6ffc84f94d818ba3d1d83e42c94e8c07ae545ceb45466eaa3899537041ec521f6219c8bb4e6d47	1	0	\\x000000010000000000800003b8dc0d9d7fdf44e5913dc32eb2808e60fbb8529f2bf8011c5788610df572b6a9ebd675006dc73adf99566395363e680d4099fbc40381ac0ac379f573abcce8b0b9039939ee74bf3408cdf2d98a0b03499078b8ba057175ef5e22831774f6787067e6fc2e80b91eec6875fa501d53696cfe025d78624a2862d0fa4ace25be00f5010001	\\x23ad95673e7a1b3ad96f8dcc1e3129b9ca353fc628cb796d51f5e11259699329099e53b07da42abe240e5aee9bda97b7c2b79d3923b120c1d5e11c70be0f8600	1666951964000000	1667556764000000	1730628764000000	1825236764000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
293	\\xaf92f40b897c2f8565abd97b4cac2b36ba664ce05bb41c2d4fe521b4f38266dabfee8cfce1b046ffa41a7a5870dcf55e4b21c24e7c512da65660edf74f639b46	1	0	\\x000000010000000000800003c482777795517468eed02439c74ed47521fdb7ca6f344729eaafd12318eccc4c208ad4cfb68ed822e397e46912c3acb7b93159366f6afade6cc130f147e29e8332a5e66fa58897d128f8cadc3c6f401b171af3db18e4c350d525e7992553adb5f132d641932307da84c190106adee84c85afe1f2a79110ec28719d74063e3dad010001	\\x136fd1f475cefb277c0d678bfbf8eec9b7fc5110757f0e86619226dc4edf1ef096ea209539482e1d33324d9f8b1be89e259175f2beb06e22e780eecd03b8c90d	1672392464000000	1672997264000000	1736069264000000	1830677264000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
294	\\xb526818639a6ace1805e821181caab0058f8cdf591f48396693ed979a98c6474ffa77bc47cf717e218684083c25c616952624a00f547e5ad29037fef9162a4bc	1	0	\\x000000010000000000800003eaae6d3d134ebe6177d5eca38542344f414e5dcdfa115719f7eafe534e75e2e6274b7cb5e95998799c14a71bd3a5437092c11be403982ce802b3ac129f86ae257fed528f09215840eb39c785d777aa2184df28598232bb90c4bf02c0f677f552576e28dd5511bc8825a5f5bca8c0b6fadf144c33cfce24d0bb7019528491e21b010001	\\xd76351e0fa41139cbffa58dfccab6d422cb810765d1d2f18e6e3a3406382875fa35db8ed15ade22254ec55e7eb7eb543b669fa59595ea40ba45977150dbcf909	1673601464000000	1674206264000000	1737278264000000	1831886264000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
295	\\xb69e8e62443a1bc087fc527b8eb24971339ae7619312712186ae2cacbfba64d6e36f6fda185211aaaa4a9e82b6bcd8e0e0bed2a621ca89fda806f53ed71f5612	1	0	\\x000000010000000000800003b1c70ac11e2e93e89574f572bde74d03015d2475af1fc715f53e384dacc7ebf36caf1a5bfc03a581084975b97d1d4de3b5ca0ffef598343b37a4ca71e6ff467bb8a84b89960d822630c138b00fb56b2431eac4297e6746a1446eab62e82acfcf99231ff8f599fc8b728eaf81b691aa104cda08413b8748fba662d18d766f1b95010001	\\x6d8bc56de05851ca5678e1d5c270a29239363352210536945d7269f1928a90c344e26fc5da866177fae4fe95482ab2af614af187b8dce92c8bfa972306895108	1657279964000000	1657884764000000	1720956764000000	1815564764000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
296	\\xb7e2e2c4e15caa671ab242193c6f1a34eea856c94ba67c4cc9d3b4f017090e2acbd396b104209407919ec4d342ac11eb0d6e0ecb607a7f863789ea9ea36ab619	1	0	\\x000000010000000000800003a21301e94d28238efaf5e657cae274b35b632e2926402f60df36e71b71089a93922955f04e2d17fbe7eecf7d6b0f02adadc3cec0bd2527a07a6fcfadbb28d0af91ad184348962782e8052ec10b22e71299b0b842997a02e91722ca1bed402e4f50ac1451d8ee14315d752b114dbfda0b7cdfec541cc0bb8ce164846138f46b1d010001	\\x975263ca738cffd9eafb05e237e31e3a492960a15dd65e545eed630198442fa410624de5f60983f74ad5b4b8d068223e06b218c9226e25d2373fc6797b6fe30e	1669974464000000	1670579264000000	1733651264000000	1828259264000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
297	\\xbd5ec0eec9e261e3b68b9bd5c873aede94b9e1babe1b345286b5a6c28f3b5243a07ae46e26ecafbef07e202af9a0db7c533492754572111f14445ff607806b29	1	0	\\x000000010000000000800003ae582e769ff14d9cf2af553ddcb506a8000be0cd36c6c18c943a31effdf1e4dde1fb922904b5736976ef75b9bdfe0c672af6baa612bc3e8678ac6c514fa933f9db7498d3daedf6a0633d4f70f923001a9ce72576e9a29be60b40754b18853f83f1eeabbd7989e4aa980e7168f284063781fc036ac4137614a00c44059efd02df010001	\\xb35b5603e34d41729cd39d5a77cf247466f2aedccb88ef8f7d24dc1b8dbd62610aa713a43442b299e5fdc5c1dedf8c795936f93b31c54c6db46385e3eef60d02	1654861964000000	1655466764000000	1718538764000000	1813146764000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
298	\\xc13611c75701cfb12893d3b9a64fbcce9f015e02a520f8b199c0913f4a30c769d2b435428585d3c55b65162fa78c78c0535ad8aa9f5fe55d7e0e85c0dbf0b0d3	1	0	\\x000000010000000000800003a53556b01fd03904514cfbdfce8b558ba104818f400cfe6910b52377e746a00515df3ca8da246791ba0dbc2dc33509ae31279287325833aa6414fe6aa6cdc3608564ec971e27a47aae31d78357891f7e5430d7fdbc591d4bea98557f4940d94f4d267bf99c3ac35a468e2daa3fb6f0a64f08320bbb1aa75bcd4b9ed56c52179f010001	\\xc2127d25125070baabc800df73dbf26a60ae54f31d73869986595ab6fb5ca90ebf8604a4302152cdef8db113db1654099135a1581bcad1b486c096de117f3e01	1679646464000000	1680251264000000	1743323264000000	1837931264000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
299	\\xc57af84135ac96bb9bebd95b1a9e7be64f2ec5937e3017fc289316849f3a80e94b2f449547b6854fbcff0013c38f11588588b953a2ae98939149299acc69172e	1	0	\\x000000010000000000800003d5b3cd721613bc7f4a90302dc9261739b94d4668492f9275e3604689456178d3aa8e733028d3a61b6c46861f23e8592263b7f68a510e0054a72b93aac246f76ef9138bc8185b8926dd3194076046b8f843172503097f81baaa11bed433ed457076fe972796e00860f014d0e91835b085fc236935679bf76fee3b035f665408bd010001	\\xd725bc01cd8132e38520832bc58527daef2de9335cee549829200912b47cbb79ea1bcc94aacd2fdd6f378cd19daa935e9ae4a471849e793eb70fa864c142170b	1651234964000000	1651839764000000	1714911764000000	1809519764000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
300	\\xc8ba20b9e01994b0212c83470626e06254f9c5ef18aba1dcf55e62063848e96fd6e694d3f9dcb69be9be72c1864fbaf38bc6101230a8ed1d53a6314926bf3430	1	0	\\x000000010000000000800003d600c723d359119f95e1d6feed329c75d154c2bf2b2d2cbba6b0a0a55547360c004ef95aca14edc5052cf87ef040af6d1a2a6c7540f5281da1ec0d96a46ba9ea9563d52353190843c74e2d9638579287962f1d115bc63a13da93f7143aa5272fbeaf92baf81feae5edc3ba5e0017fabd1587b02991828d45ca08dd3559b44f95010001	\\xb62cb56b07c56b88d5e7fbb8de2d467eaf9df6953778dcf1bf60a84ad4d0a2e3811120bd64e7a618701182c005d14d152029170ecece3b63981d53ff75078f06	1652443964000000	1653048764000000	1716120764000000	1810728764000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
301	\\xcdba926139eb82adb97140927cbbec7a43e1abbba07b480906884513c4f64981f7f5acead8abb82f19f2d2326d6175b4ab9e54dbd26c2f8846c7a702a051edfd	1	0	\\x000000010000000000800003b90c5609b852696984d6a703bd4270ed05c450d4680b1fc67e32ac9686028c80b22babf1517bab979b13a681e314db720d2c487b93e156b572fd8ef966c1ab54781907a20250299c6dfd9c6ce7b8aecf047554c38e526b1df07c2f81390c8586bb3d81c5a52b64d1f635c2e66a58963ec672e08a3db8921d872a18ced25059b1010001	\\x2c9eec89229453044832a81cbe05131e132853b72812c5b2976ca728028e979097d11f0f935904ec32d318164eb68d068c0811bda1e4d2d78c88ba6cfe09d609	1678437464000000	1679042264000000	1742114264000000	1836722264000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
302	\\xcfd6da32ee2e87f33b9cbc72b6e088601328ca95e4ecabb2aa1f7553639026c8586ea4bd0d732a6d877af8ab190caa14bff95290ff31262c2428efb72faf61ae	1	0	\\x000000010000000000800003d787bbda0ecf40121c14b8e36acb8147148be6f3a1f94fd627bb1ed7c697da689236f8a4b31420966d5f33458a1509cde930101a9f824ea5ef96c49ad5d510e6bb93e2efdd85d12409859a2514250fd0a8a1201d9eff7b54886ec7de2f7d0b5ea8993c81f9c0ebde626e5e01d18e52e48b94c2f4f77743ec65cafefaebfac64f010001	\\x6b89532a2066acfd9acebb9e64bb45c773707f0e71f0b21f029ac1d23bbb336dbe396d1d65ec9664ee01bca2322a93ae05816255ad3d138412f0713cda89dc07	1658488964000000	1659093764000000	1722165764000000	1816773764000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
303	\\xcf962a9db174f79ae7a6a34bca95e4f71e8acf0dee751ca87c9b0099385e0a101d38c8a00bff3ed36c27c3eac44a9ac836c4a6ec5641887d83a29d3927c3672e	1	0	\\x000000010000000000800003d682b6fc69b09c2d52b13020b768a92e0669749b5bf6abea1d04f10f2172b60a3d6d4eff7de86d02793776c41696f479d06fe5a6cee1c608df3cbcb40fec098b12b4a577ba61654ede51fb439c81f26d089fb0a4bae85c47f3028c7eae436110a852222cbf638b25657abbce2ad7aed013cc29a7f47ceb5e6c380a5726f0b0e1010001	\\xaa8706d79bc6bfa45dcdbd4027027f5a618e4b8d438722851aad92f5aedfc1855d071e50dc936ac6f6500dae1a23a209dd2be3c770751662b7aeeaf74977440d	1659697964000000	1660302764000000	1723374764000000	1817982764000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
304	\\xd4b2de0d775d661948cd32d762a12993c5e67f8a297ce0261277436a681dc5b1e73fdb564d6b4c477c8911af9bda525a438b5fcece5b66c5b2f83ac5f83b19d1	1	0	\\x000000010000000000800003a87e24502a0d7b448cefb8675575fd89aaa051f1d14f2a468609724fa1b55632975ffcacf9d2f4af338717aee2617cdddcda51ec407b3c501993bf9401e834a9d033bd0552d0b54e8d2521f17179d420c1a7f07ca686b608b9d33a04b1627b514996da9dfadfce97bf29ce134819fd70c0c9c2cb7f671e7f2cdacdc92d2444d5010001	\\x43e080b3d1d0c3a98f0e9f5836b65d2ca313b5b1cc846e8a243dca470554fe6465ec9d680d0adc1cec112c428a8f10ffef3748bd507db8f1a4e4e23e29de9e07	1648816964000000	1649421764000000	1712493764000000	1807101764000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
305	\\xd5b6e925b32cf069110b7958e501b2a2f5043a59a088810ec0dd83faf6ab59a05a9c1834adb72855805607601286e3b50ed817c2e57221a0c3806b508fe57bbd	1	0	\\x000000010000000000800003c82230f9feec0eb1ab940c0d22f85a5dd1a1eff3646258b6c30c99213039303734ca5271feb63b383ca6fc4b762eb031e1a23246a95e2c8b2820fe76e03182e112f07283e62a17d1524257f1aa3d99606b78f4fe72325252a22cf4f37628744516c0fc788a0d31a75eacec8f4538e0c45c57aa2c31bb108be28060ec8ddf4cc5010001	\\x70182cb685abfdf2eab34747347a5b0690e1f7f22b6dba5802417ebfe160e67f139380ddb91eafb20f3529de53fa2ba7914aa928f6f52a0ffce03efbc745c200	1653652964000000	1654257764000000	1717329764000000	1811937764000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
306	\\xd7ea656fbdc5b92126ce63ac1a8186e791a1ecd159744942760527415d6b227843269f6f73a08ecdaabd954bd1cdd4f1beecd5599031f4d8cb736f83d705388e	1	0	\\x000000010000000000800003de76e00bd8a7faf42e2cde2175f970d35a4be3ea46510c14bb8809ddeafdabe7f5a86e2dd852d9bb02106b4b5fc730f452e701ef8cd9e2d01aa9810b89acdc0737cb3d849cc7f880b14cec492cfec829d3e2c463cc593d43323dc892afa55fd0c45e15a5590a7d95a767d5a513ca067da215a077b3670220e42d55104220642b010001	\\x81cc782f5b6cf1e52dec3b458e2f1a9490ee4ce62f85780e3a644af27db3a2b7e189d6b7b1cf3561040c4c658fb940ccddbd3ee26f1b6ef1776f576e85c17e09	1665138464000000	1665743264000000	1728815264000000	1823423264000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
307	\\xd91a572cf52d8bef0707c81dad0c549aaea895fa61d4166f80cd8dd7eabe9a1c5e2c5971475629dac70d3c469dd6d322f9dfdb780deb96db162afbfa27a849a9	1	0	\\x000000010000000000800003c36d2db659435d9c57d8bbd8a0cc988d907b49739566e2fcc860cf9592cd43cacefd150ae9dea741a0f6bc8e98d85394ea7221bba36bb34154021837a069e864fe51e4ac3533418ecfc6daf755115fbd27eb17ff9bbd4f1f4d4be9fd109e9ec621678aee279560b4eaaa0077b6db407865f229c14c27ffec78e7b88d5f0b8cd3010001	\\xf7e1f71eb1a2e2e9ca2267427302c1650ac76deebc87de8776e17ed904ec341cf1a02e7f5d4fe8d0c3d30467c183cc5bb8e07b3f0a21b1689373861f7351dd0b	1660906964000000	1661511764000000	1724583764000000	1819191764000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
308	\\xdc5e88babefaf0241e7b869185be8796eb7c19b21baadc054a58e77d6c6335f75f614b9e4bde9f5daca707afcc7bf56b6df76201e13eb1a1e3c3237502d888ad	1	0	\\x000000010000000000800003c4f333e156843503804a396429b1ec4eb0127210d73a78b7b245a6e4a3b6ad2708fe889f5d35c8e7540361da6679bf681697b5d5503beceb1b662810f48a15fb7ae1d58b76c57509d34d5c068aaaa9d764a9f01786f792a91d3297e1092fa3c4043c50e30298c80698ce14dd480a70bddb08c7b93266ca3002fc5f23810ec15b010001	\\xc0f49f5680e1160ffe082377a1e94eb7e32f9617a470900665a341954a5d4a24beba95c85fd01a946bb69f974ac185368b21925d9caec4addcf36b75b2169c0b	1662115964000000	1662720764000000	1725792764000000	1820400764000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
309	\\xde62a75ae70c49f9a134e964c5bc682b2cd396735e436997941ef798862552fea75cdc80311a8ddb1d2dd3cdcfa8ae157670e0950f30467e65c4d38cf7c8b319	1	0	\\x000000010000000000800003c8399d70048f40e6dada650ccc38e8a0b9b8e8dd90b783d7d5b514846f002d9ce6240c805bcc1d3a641871c337de72429557747ecfa0436b08c01ebdaaa110ef81df6f5726d31e0f4212563f01991135656b5865feba6c063dc5805f3bc2c602a118930c5aa659c3f92b072b208761ca6894f9ee72085d12631e0eef14f88adf010001	\\x540abec34429bca0f9b730bca1fcd8f8becd3f96c6212c52249c3832b459a5bf30cf7c76ad991c6827cb6119129efaa660ac7355a9ce5519199179d520548902	1678437464000000	1679042264000000	1742114264000000	1836722264000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
310	\\xe096ab15ab0a9fe21485bf16c360b0938e48edd415d0ef8d24bf61afb22135a8936cb151f15f08f49d06826b2dbc296627053aaa32200adcb11f407cbcc98fdd	1	0	\\x000000010000000000800003bee196b5a20c0925b71800d9f477971022162da8464512e9ef1e7870d6366b6ae8ed3276263fab78192d7fcf6a32dc1c0117d37138d4bbc69689070f0b8d239304987340b68ccf2b29f2fab3885f359264f4db6d8b0f8d1cd4eb3ffefdfa1dedc82fa7bd1b60a8f45ba4ba13095a56975184aac357cb0d256ff11d948b11df21010001	\\x1e50418db270893913ea14de8c1c3a75785b5ab1afc37751be2a91e5bd8d49e51b4c4b0ca8bfcca2b159c001b5eb3f4564c9cd1e26917bde235e8b5957b5420c	1661511464000000	1662116264000000	1725188264000000	1819796264000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
311	\\xe356dd48bd0262e9ec4f2f43811844cfe1c54ff832e58fea2e336b1b966d58bbc5c1dd732f584d0b5db9371ed4b6d538e6caa6adc04a058053682fcd9c55373e	1	0	\\x000000010000000000800003d16610dd4e878d0bea79b78f097c97fe0a5746aabb802641c9db65dac7d1d221dd20253ecf78ec40814b5220e6ca565ef11a9ac82fbf4616f04e44c6e4259b047446f33388983fbc22bc38ade8f1072d5bec93c1620fa3056eb80f972f3c7950552451cc2e4d0c8980b84d2f38ec1313491f989313d6a6d80265877ae97e8215010001	\\x6eb9a4ca5f27bfe9ca54e1689a6d9e1425b94894fb5e6475a071674c29f81dbb62a586d1841e2bd1d76b504e37b31d13d25b016618b1caadcbccd16ed7530805	1663929464000000	1664534264000000	1727606264000000	1822214264000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
312	\\xe4427cdb25c8b64cdc6bd53ee3f867fdebb28d7ba78f52ed33cb1c4646a2258503bfb72dd71128d92d8a8c44528cfa1593ebb309e04deb40f04f2e90a6638f7c	1	0	\\x000000010000000000800003d5b0645cd0ed282451beddfe6e46317a15fe9145fa9895092831e2bfeeadfe230de52233561898004187128f911413accb0a088f41e9a502db1c04dde0c4543cb102e550b3df327be3618328d5655d6dba3e3864edefe09b8ff9cf1d559cbccf9f1291315041aa80c67890730fff0c8d9d476fce946331d6787fac894a48f559010001	\\x6ab09f23162a8663ab761fe110e1c5fae0bfeb810da5619301a99c91864cc35b9a52b4c847b7a54ee17c9cda764ed74c523431e0d617d7cba7a5bd3caf381908	1665138464000000	1665743264000000	1728815264000000	1823423264000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
313	\\xe6ea25f7f58a7037b9c55a90e1cccde9ebc19f61e156fcde944800fc11ed6543bc9255dfd728ce46080de796b4e5831d5a39ff5d730aef4f91a0b1dc40554ffc	1	0	\\x000000010000000000800003c5f2bae94677304ffb1ea09d89fa67b622fc690fc835c4e0d0465d9dd631d0481598335e50aa9bf497c9739ed1b29d3b65d10c2f93d2d14c62dd7fe36e6ceb505069e4ec51b59f477488a42f8c3c5025050a46bcdd786d4f33e3a4c5ad6144d459d9401599586aa47bf58d685f5369ec1f14889b817886250fb4cbe8406a8721010001	\\xd7fc2d7ed223855069b761fb9af09fb39a3cf4cbc17b59023dffa31ccc129d3e96a9093cc049289dece2f6f590c3213a6110ebb879edaad6a08ef3c71a476301	1675414964000000	1676019764000000	1739091764000000	1833699764000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
314	\\xea0a7ebd307a8f666760a1554482b2ca1054007d431f116da7c9551737a5221f219f205e0dd797dada93be05e5f75ec0249c5237937fbd213a9d4d29548927d3	1	0	\\x000000010000000000800003b71818f225fb741675924182a75f495380fe5f323761da31a26f75ea53b9e4571d500ae27c3ebba773ad1fde860fd4c899a4610674c60e5da63e4b2646de9ce0d65ce2d6b5c14b25d715a7f32720a229ce82df772883b5bb7c3f5cc08b17b918e16f92e734c670ab22d5db1577e01bdeb54db6788b93896555b364bc78159f89010001	\\x73508b20d2c70c5f3d6803c88a82c03f512f1c3ed909afd5060ccfe2ea5b35cb7c3b50b479f4591f843c9269a29b3574bd33c4a7687d8ed828a6e161de650e0c	1649421464000000	1650026264000000	1713098264000000	1807706264000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
315	\\xeb668501c15ec6770a2521d001d402608b230d25254baf6f3e6ae5b2c00f5e22c13f48a9f86323b7e53a57d3a1c7abe8b0beb3bf16abbb2cfb85de8daf8368cf	1	0	\\x000000010000000000800003a8fea6bb0fb2ec97972a05fd5cd458880a5d7d20b628e65e73ab185dba257dc85692665a6948c961a1ad02a7a5f2ae800c2c036ac4a192afaf2ada51231692bbcf5d8c77b98be343c3c076e366307fac44fab97a6a22574890c6a493f703c8fc58b5b666facd0d8cdaef15622d97644b9213504c73f33b1d98199f9ff1de0657010001	\\x3e15671972bfe4d5a59f011e3174da82baeca97f42b7cebeb74a99bf752805ab6ba1757a89d6268db4719dec919a05b383b0b21e8c5a14b1f18a39c1cae48e02	1668765464000000	1669370264000000	1732442264000000	1827050264000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
316	\\xed5e291ac75463e82c6907856bf7cd6c16bebcbdd01123afae98fb74cc0c7dd02010464f5267b6b8082b34b4395f4c8a41319d77b34347b928dbe72a002d6d80	1	0	\\x000000010000000000800003c3cce44dabb1f3d44240a2ef59419af2f0f03f9dc7b75a8c56160574d6bed307e1cebfd52c39082f1d538d184be4f8b12a0e0d629821340e286c9603580bde7db2a39a2728ab7b8c9e5d8efdc5e1fcbc3a922bb9c805bb53005d8fbfb8c6be1ae3b7d07cdcdb13f6a4640e07d739800e7b5e2083f712fc8b06ec011d7d01957b010001	\\x128833b1156bb4a19199d44736ce17fc8c2fb7a578b5ba6e193ed270b53846c194c67611bd42292f2ccc0cb224e5a1ab6c614f79eea0c93cafeba6ba878f9d09	1674205964000000	1674810764000000	1737882764000000	1832490764000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
317	\\xf2ea3664fd2e01a699fc518a9c402d32a4e6ded6f5310f053432ff50cd7e4d06d53a63a435ba5b24bd75f28fcb69968e9d9e855f54f6f1c6763905f52f953973	1	0	\\x000000010000000000800003c13d225e5f087b02d8f66fe6eaf3c93e0684589787fc2d9f83357537e31f83544f1e8aa6eb22458ff999e1324e747bb46c17d2e21a1329c04d724e531ab21f2c442bb7b554637c34ce037fde9b713df8667e5e625cf6a771395421e989872ba0aa43ee5d1a508e37add2d168a3b335b8df97edd295ddc7fc802f07fb5881a0c5010001	\\x8cf016cfcf1ce4e6284b4907e2ed9c4e9c5ac2db49c8ee46786dd27df36825e75da963c52e0f9456746f14aad627d4a9875ea0054978c3d3fc6ecbd6a46eac0c	1674205964000000	1674810764000000	1737882764000000	1832490764000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
318	\\xf34a3a9702c6757e2e8407072ed908bd814971be2becf58338442e052a052ce78747d6201768b2e2858149e7f2a703bb5fc419aa59ab25eeb5cce71038750d23	1	0	\\x000000010000000000800003ac669dee9b0c712a5a046c6fa7175349ca1310c24b5a7112604434344cdb32fecc4be7a65a42cb48b5912e3486f21731fbd27c8cbea77fba2e11020f0861b16c35e81d0b851ec87efededdf69007abf8e79d631f6ee7408cdeb3bba6701e26f5d275cae2688eb7191bba4b713104da4a90bd930b6436a9508feb661052cd6eb3010001	\\xcef48bf9ae47a27922b3066dcf6ef0eb814ebc62fc5cc91ce2f20540f8d19f3b6b79ff70093dfcbde54e595712f1c33aa546ac27f5eb619b7f66442541752303	1671787964000000	1672392764000000	1735464764000000	1830072764000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
319	\\xf32ecc374e4f861241e32af0a486b670eceed76372ae6dd26eca3c73aa0e0e79c8f959678b96149056ab10d58a8af954a1cc3b0d451b01bdb22bcf69c732708d	1	0	\\x000000010000000000800003b73141f5ac5444a4010eb6b55d939d31d8733447c69e5733f3347899b107763410a058b6ee3a19ef2c5465de392b2f93ca2d237dd1a7c287557d89dff38d123b7aca7b2c5d13aae36c235a0bc585068cfda5b8c5c83d6183fa6491d88d6c390c82414d1d721356e791502c54e5d92642ac6f5634126d4bbe1b0e852879a94c6b010001	\\x9c34e6274744b24a9ee63d3acfda1918ab9a8b824aa4860c1a9a671fd534cd6df3ad8e4ed81704735dce5f1f5ccb23ad7b887ec1e1df9e6977a686e08d06d205	1677832964000000	1678437764000000	1741509764000000	1836117764000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
320	\\xf4d6c74c615ea64dc4584d7480b5ecdfc7acc7c693928739592d8778a22da2c648a2f27d8be1d3492134bef61e8a5fae886e8d2aa4a391e256666b8b28e14d5a	1	0	\\x000000010000000000800003c2ac287533ebe5dd7bcbfccc8f92cbc67ed6d45ab39920b5d10a166bed0cfc49339a842942e0e94d31e4bc9512c185fef528e107470076af378d67a28b8688f056ebfbba65df1ac93f1dffc493e19bcf98fc625db4ac348801ff55dc2f6b8853decdb5a6490a61f63fe9ede6072a44b2451c7ac0fd46d11f18936d8696050885010001	\\x5567ab8c16955d10dd4d4f71d6f8e565b7a89ee34abe787a4419426c25ef729f386fdc9b12718a866295e738a328838caef5584a61930cd9821f8507599f4109	1657884464000000	1658489264000000	1721561264000000	1816169264000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
321	\\xf5baa49265030425487c00d2c35859c780f48f447155da59bedf2c2607153605772733f4ec576c38ec8efe7f36ed8d8e0cf03128dab4e4dcdeb1581539eb7b31	1	0	\\x000000010000000000800003e071964fd58e1bf3bb5d779d157922c2a93f0fa55b7a84d2044a3456695707a0650b496eab1243f3085c8b6a95d89fbe36bb3d47a0b15b73f3be6bd177edc4dbdbb9fe43f9d2d7cff3a31c02230ea9073b15e9b3b17a8fb1ba2dfefa613b42e4c96a9a824845c53be8edf31472e5002d276650935fa44666bfc17b9da0ee2a5b010001	\\xde26c240e56cc2d39e9976ed93a3675faaef8fb25f966f85cb8a7303d4312a44cfbdb2f5ed38397bf1368de6ab426efe3311ab362bf35a9536c947127d755203	1654257464000000	1654862264000000	1717934264000000	1812542264000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
322	\\xf97ac06765d482eb8aa09550e78e85f8bc7b1975aa16a18d020a5fea50694921eea16774a210aff52ae255df73650c0c02e18f265d0659179cd369b318d556de	1	0	\\x000000010000000000800003b2c493dd67f29c3ab8ecb85854e3f9fe5533a4a2a2718d7bb078f4cea583a4e535d71baaeeb370970d59e5daa637871f79284bb0e2cd4a6a92a89af1e6d6330bb4614b989099fc8ce582123e6c47108872871d157b0caf64ab0089fadc175da08eec8493bdbcb13c82b38f0296aa56b2d4f4826b5a44e3063281c223aa742577010001	\\x01326f49cff49bb706856b84ed15f799b43873a008a6bc7a758773d12d7cb4544482c2e3fac7909650c525d64bdf7486b00bac8ebf757741cc64c97996109803	1656070964000000	1656675764000000	1719747764000000	1814355764000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
323	\\xfaaa2550b88088bd5da3cd1ec71886312195fbac72a3dc7e5d1ddee8effa9162498d930bb244c34621c55325daf5bb6fc6b6f8910f82e6afa55cbd60b392440b	1	0	\\x0000000100000000008000039baca4dd94c90beaf143172234c139e014f1a23b9dd93e51bb6654407df7cf10ca4bfa1654c46361fd0a54036ea64144487f9ccf6c5a75ae396a7970fb246ddca2fb669ca08e769ddabf6fe43a274d9c4b1a49b8822fd349ad967a19fb1c08483050e4dc39c5af8ec0c0a166dd5f820fcff8373d57f383a08c9195b55c269c39010001	\\x9eaca29366266a84b70e46d58a75bbc3bbfd85c0f4da495313b58dfa7b0768fa203c0c40702c39ad8c41e8d99068d2297ea46dd38bdab48b29b77402cdfb6808	1671183464000000	1671788264000000	1734860264000000	1829468264000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
324	\\xfa427ad8affa32bf156eac591298cebba0840a8b1f6807a64d20259486cb3b662a39bab3e397283a8cbb1a572cd0c0b6e5ef29a635dfe8af94e52b00930bcb36	1	0	\\x000000010000000000800003d42d2e917b2ee622954ce9a3925811245a50267ca01f71e18f78d56685f0d8bd287f98b40d1ce79b82fe5889cfa84c259d645df10b6fd00df2c803fdb480358fce91dbc42557deceecc8346557e48afe224e1b911ebc463bb099543c4ca3e4e4130afdb7c034e4d0ba05a2200f2226f8b9e9e1687d78dbfbe3d18f2372022767010001	\\xfab483887bfba6e11c91a050731ad0cd31293bf22df992a97e92285e25eddc7fae2e7d4bf5cf3d10a1b635ff4306f2e729c19ec8ee7bbab54ba42ee4086c090c	1653048464000000	1653653264000000	1716725264000000	1811333264000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
325	\\xfeae676a67a84f9b83d73ddad6f97d1bf0b9550ee4c673d51d58e05483720a55037b0727f75df3e998d32ffd10621e1188621b6afca9bf4ae4e75b421bebc2b2	1	0	\\x000000010000000000800003a6655e03b4717af70bc4cbcb44ea2b897f1934213ede64126a23b9deafb6c3a3450dff505e752ac9c5b1eafabc44bba76ee901d35d69eb5cc9eb8875183aa35fedff1c9d00914d97c42748a39c175871c5a7ef45a0ce4aaaae118f2d553d7f5b53d923832e11a61918e7df3a432bb8c7b1d7ff21bc47cf76e6d015c1ba918053010001	\\x5791c0982132789517962d75332835a085c6e8f691a46980f282fef3bc0e1a13a4b99fbdee70dbe3abbd676ddd60f9a3896eb36fd8b78db14b42f06ce212d500	1651839464000000	1652444264000000	1715516264000000	1810124264000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
326	\\xff1a628838259017bbca4a44e1b35478f0ea7639dee041300e0efccb0541c855b616d287614f126eaa8105069f0f9b5d539b09cdbd197aac45913471470fdf8b	1	0	\\x000000010000000000800003c209302dcfeb33108ee0756df7172de34c589e892c6875a44ca298877bfde5e547d7943fd3b5993e79f92dc3c848e73a6ef26897b40afa590095bf976fb8bf7827b8be1a4ebb9a077a4e174930362e8e951d672f2ee35c8c5d0d3b25476bdf83214f04932c42e8a83e404ae2f966c67f5ccb1a521ed00ca26cec4cfd06fc25b7010001	\\x7c60bcc103e9f46aedae303d0169e03df95dcf4a7227884c7a8a2887b416ffe10ba010c67791720620b6a38d6b64068ca5311692a821e31edfb650d3c5e3f30e	1657884464000000	1658489264000000	1721561264000000	1816169264000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
327	\\x01bb09bd1a2d3e666f748452bacea0e9a25fa5e2585dfc827248bb6b8cc40faf2e1721f528d90a75165785c2fea2993ea1b44b45d6032cd6536e587053cac519	1	0	\\x000000010000000000800003ba27052c4d11a9cb8ca401d951b8e5341a4141b55612c8afaa0afdcd3f62ef8302f6c578917cee52b82e4a5080095265831a837873c52993dc102030f5be8f5aa7f1de83e69dc7a1ae3ea25cd9c7777346d8c50043b6234cb7dd77fc3511c256bb63407c61aeff19d442fe3617d4de437c8d47a4cbaa889575f3b5217bd3a61b010001	\\x3938b298f5c25502adec69f4a8898df5252d65b79f4c5e6079dee686d38d952bc0b845b0f8900cf3f1f01521d30161ae965ed6e9023ac4c135eb4efe1be60706	1651234964000000	1651839764000000	1714911764000000	1809519764000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
328	\\x02ab5ca51d3ffceb5403a48222932c9adb2c387a5c87aa596967afc52c300ae6ef8d519c533b03c6445297d65628ff6cfb7adac25e19d54971270863aace4916	1	0	\\x000000010000000000800003eff017898096921188b3309e72d196936df52b6e82e757274e2c32dfe845863b09608e20e6ad357258e48a25f1066a48f1aea00984713e6b0f2353f3167a69e06fe2248ea91238c7782badac6c19490ca46dc880edad8c8ac1a641047707c5086f708383e5b7ba939a0fafa016f25fe17824ce1bd78b4552358e325085d66043010001	\\xfe48741ffdd2321d6284876e4784ca6af3e612a5779320cfa32543f88c543ed58168a54aa085d57cc9346c2152c279e4e5737d7ea8a706f88e7b35739ec3c50e	1659093464000000	1659698264000000	1722770264000000	1817378264000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
329	\\x05ebd5886adbd51b8b96c4f2bdbf95a4172d8a179f2e2acef5c39461c8e2c032d92f395b27bbff8f08d7c1cfab3ea0fa5572f3b02fdb7a29b61807d5a65ddc41	1	0	\\x0000000100000000008000039663d5ac7e4f94a16c976bce267f43f76699a78e017a61c5377f017458d69550f2b9be1545fe05a1a56cb56ae4fa7b12422e30bbafb53189d68345b67527efb84a3fb16f3e57563786e233e99c97c1979255855f6d2e1ca5d35b1b12ab53377c31adec9b778d9ae4ea60a38012ab1b5cf0bad1e4d2b39f97041bda61d1f4cb83010001	\\x8013a3ca4771f0dba246642f47194837b3d991c560aaaaa991e6b0671031bd4155dcff5419ff10306e22bc9541277678ca21db316064fc94307e8eb22aac800d	1662720464000000	1663325264000000	1726397264000000	1821005264000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
330	\\x0733d2cafe72e06a81c74d26f0b8029b53880740ca092568eb27391024494cff64338ab5115946b066dc34e050eb92aa0fcc09646060509cb890409f472d2698	1	0	\\x0000000100000000008000039f4bb8d1b6e7584d18f44f81c7f54335176a3a3a0512dccd373cbe3c978a1c90c91c14a319bedd111277b90a65ee535a25efdc27b6e450143d77303e3b617f5c22e1b8cb681aab1bc29ae020e909fd391376b07061cde43af0b90f655074e7f03793ad364ceb9bfd19194e403082ceef96fae8f1b7d10649c6012d94658693ef010001	\\x38cebeb7c281aa7053a108398ed279f6dee028d3d373889c59f495484de64446bc1b148a80f1c1da32a912a6451a823c3b9af5babab2899f7122f9c07a99bb00	1659093464000000	1659698264000000	1722770264000000	1817378264000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
331	\\x08db6017b213c06660f25588d345cace021cac1cf2673b80ace240820b8bda38502d3cee504d791767ebec421b9d02717d7d2b64f511fc9c91aaebeead175a3e	1	0	\\x000000010000000000800003dba5a1106f0fa1b0eaa169fc7684e1df4a5392fe56f41fe80d95f90164cd93d0f7a1a157ba5ad135140722d9e709a1748f7eeca5446bb17cb61d4f5c588db13ced16e50f3b8b850b0c6efca63f86238339ff40876318e71038d3dc6593f46c627bc69eaebbbeabeb2fd77b26540e28194172e85b30add86a6c6f7bc5c3aeffa9010001	\\xcc2ee51ad21c0b1745e738fbda0f81c06cfc3514b2f643afb1d697efdedc7202d8225f6d6c78efa7025afd6ded8e1568f67b4ae1beed414d491360bf64276502	1676019464000000	1676624264000000	1739696264000000	1834304264000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
332	\\x08f7ec03bd24f5f2c4b7fb310913941b717d5d79ad24f9dfe854722824f6ebb4db4d25d0823f7d31295a5f14ed3696bbc0c34a0097f9044269b69a95a43c8e50	1	0	\\x000000010000000000800003e29ea724a74deb77d4314511cb75dedd4e1a6811211179ca0d4429d0ccf017305c01cea0fdd293e51b0bcd40e64a0ede9e4e8e55ca0d195a56c4b6f31a25e35d9902e70a1602791db9984e83af61eebd2c66d37db752c92a9874724820c3163d7666fbb80d0032bf78f289c0d2504a491173872fbca6c346e997e6d0fe2a20e3010001	\\x64f6353508384fcb8ae6833f0013893bcef78cc7cb27051687bcb9ad4d4e0764c35a8f5523f5f19798426afed6f5ef84dc7175e3a06ce8afe808a5f94ac21e08	1656675464000000	1657280264000000	1720352264000000	1814960264000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
333	\\x0e23c60bdde1080740e836a89cc05d0c136299c471a7b0a243a2c4edfbbbc326688e2b745873ea556ac03f6e25a8e6242d78f0d3eb63138a32b0028bd931941f	1	0	\\x000000010000000000800003b6dba5c44d7056163796c4aa642d4577a2f85032f4c07722123195f6839690e9aa11959faf3b9981854a2894bb9c04d915c04a80f040ca1bfd454e33fe11d0233b861ce60c24378926adbc99077f43117e6737fcd9ba4fdd810572ee0e2f5dc6edf6a2638207474d1da6c700176601481dddb7ce5e7198622a28cb1dccc4fe3b010001	\\x927b9bcf316203bd472c42ae643988f7e82480dcf943f4943809acc6c331ac731d2767372d83eadcdf6d675dc9a7ea5a557dc4f49c5af67d8f65fd3a97292405	1666951964000000	1667556764000000	1730628764000000	1825236764000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
334	\\x117bea980a90e007217f0e5a2c433b40f92597c5dd0050d010921a9ea999abcabe658100b4072a6b1431a03e445e287445c02af5ea7346121068147bbc6b6e89	1	0	\\x000000010000000000800003a6634352a4d2f8cd82e4c29af7f5e1fd038af4a963e78ac46d5b03325b771f18792d38167074115c457b35811b83e7c3cde23eb099a287be3248547185c980fa15b45df78df2bf51b1142e43b987afad4879ddb08c86434e1b75a76a31b33e52fdd8a69b9e823286b334298ec28f131530a3b351bcb502355e3e52e68e230b3d010001	\\x5f254fa180a2f6a1b5b395e426615ea1edbe3d78997ff93117af4a9188a8014f0022f8890071f99a84c30efcdb7574fab640044f89f51d03df68403c7417f509	1679646464000000	1680251264000000	1743323264000000	1837931264000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
335	\\x151713305007e9bc6394f0b6ee6d6da039b1a867b305da554c23ea8157412fba0d9354d64b9b2c6cff2cf2edfcc2b2bebcbdc14652cb090af6c39a3ea1b21bbd	1	0	\\x000000010000000000800003cdaf609cb64e1e8115bd2cf6a3e796a65ea45c376837474a9e2a65cb6262e5cce5841db6522d3d4b7ececa202513fa07ee185d25ee66c46850db9e5177a7582767b067e3e3aa9f3af4a59b1e7ffea531ba1db98500fc180c6794f7bae7ce9ec47332e9da26607b70a5ed6317d6a2d7d1c88a9df487161c4f855b756fa7006bf3010001	\\xd63fe128658c9bffafc4aebff0864ff9df9c7b1a6e17786f3968bf0cd483edbefad35b216c58fd1187d7c0092fbcee00e13fbfbd4fb59e5d3c462cfe1cc23e01	1675414964000000	1676019764000000	1739091764000000	1833699764000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
336	\\x1b5bdc8ccb37b1ef0837601919272986d32d1723414e6c6a4e46583b232a4c074070b2fee61cf04594d1f8c7e3696ddcf5f6551d15cc2249b7db5a504ca243e0	1	0	\\x000000010000000000800003c6ac3a7ed51701333f7531134bc11146cf28bf16b7111a5af7449f22eae96e03095e87120132bd62f39fc94a9c8bc28e719905b6d4d56a2895f5c253aea245bbd6a83d94399f955a1ce59eb07973720c2fb6d0f94176f25ab8a08bef1ea03af92e9fd79a68a06180f666024ae1684810392ce7288c0c5a4b7c2c35ac5d06b753010001	\\xa69e0f8f4dd29607ba0a634927716bd7399e43dd57ef8ac8cdb7c311477d87dd74a74624e00b51281c8fd0745b870f343463b83c3e4afe9303abd8891bc5d303	1659697964000000	1660302764000000	1723374764000000	1817982764000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
337	\\x1b8f45b0b00448fe97f960541861b2f42192bfc5f6ac40c71d75154fe4bd6d7422efb3ad210694437bbb5569d5d6c595c2ad4ecf3937cf1ff7d2917336143408	1	0	\\x000000010000000000800003b2cd0c86b1231d66f0117120f3867c6366f2e94a228fe83b018a59789aa2ba90e6fcdf98ae880ae4783ce41db3b5ba3cfa0850f58e5ceb3cb69882716418b3aed836878f6b3dd93bc80090379a7c9978fffe89d718653bc6d6296c9934ced9e4b0bf3ffbdcd18331d17daf760f6d70d2b9a6ad751b4c149f5981c85e97ff5437010001	\\x54ab723fdcea6da9329d3e62cee04e42ad90973866bea71b0f0317bd6f431f6c656df0d7060f2e8dd1f82600ae5b7f05ff9d7aced4214bcc725c1bdaa8d5d90f	1663324964000000	1663929764000000	1727001764000000	1821609764000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
338	\\x1bdbfb2bc8c8eab0a31a7da5dea547df5dcdd5e3d44b827b3d5bd28885ec25a167526b336d2580d77648053b4b031f8b56632dda7050271b0acc49e371e0264f	1	0	\\x000000010000000000800003de627a85904e8d955ebb0ca8cd6dde3929d7f14e79ea5b365ca75f0cea7f6f694e219f51adef3cbf44db70e04c0f379231d8d616dbb262739555d7fd27ac5028e8bd97b5e0c894698d39b07a8941b9eba2a104d9893f055e9e4635e991b5740d338c33a43f0c08f7810a450fa719c6cb588145280643071516c2905be7198cdf010001	\\x36774a2e01dd57bf79c509f825ae37c32db80b5fdf3282c1797f02966dbbc5dedd199f1f27064a1fd38be23d80834f5a4f7b8a9d32d960a03dfa3f0c3071160d	1677832964000000	1678437764000000	1741509764000000	1836117764000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
339	\\x1c0386e7945d6a12cdc2dad071db61cabfb5bb5038e04814a267c244c5d4cf5e2e75ab1b93c52db051217654d84b0c349726078ff182c2243425f4a3afec9f3a	1	0	\\x000000010000000000800003fc794bc34f4977c5eaaa3326b9814a26ea81ac94fc7b1a236f01454d5fa042d876bdf7da222e6313b0a10c57d8109e816de14217e3074cd9388c11dfd63ff0e48b255d253a5456e74f09e47d9bcd7776b4f0dd91675c7f0079f315bffd76c3d572818b960a7cc2d4b7fd7b9911b69956972ce66baae01e59902a2375724bd833010001	\\x3f1f4f4719d7200c84ecfe9ec83dcd62d3813139da9856cfffee3c67429b003b28d99cbd4db68b32f941edb89a0db29e87b482e0c76f0cef02e1177351127e04	1660906964000000	1661511764000000	1724583764000000	1819191764000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
340	\\x1e93cd0d4f5f526ce4d0b9af08bded08b72769fa807ad47912e7f2c9a0220328f619a546049495e7545b8061ced69e6b80b66f74f1697da252550bcd8d35ec43	1	0	\\x000000010000000000800003c2232d2161c08d68cff3d198089de067f7b0d9e5c78dbebc37b2cfd625a8a17b3ff1b9e55f174f360c4135f8b80f21ad8c71c8459dde7e8bf2b204b6bca68aa540d84f570793d18f60ea65216c9dbb715df1c321d0ea41b0ba0a9abedac9a689e04e1795bc2bcc66b99e8f1eed423aa055d2fac0e85a90cf4c719e62c3870ee3010001	\\xefb21a8acf98ea3baf70dc773652a5ef4166f9dbb84c0bdb09195f17278bc9aa5cc5374bea858792d49eec2228b440a9d9d9d37fe276f4eee0a818b4764f6b0f	1661511464000000	1662116264000000	1725188264000000	1819796264000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
341	\\x1eb7ee3227849a8a374fd3cbff46d3a5583ea07de1cccc677cf3999e9d2eb556623041bcf732df9fc1cd317423ec65db0c799be7db32da86804a02e2dfc3ae81	1	0	\\x000000010000000000800003e49af3b88382fa2c49a62c7785ea57679959d61895348f70ea28c8daececfd94aeabdc3ce8d769249bf0e093a492e5226e37683b9131c35e2f298f5d6391bfab38a32c8c4ee5b52f58e8d49dd8e9509ce072f221eec98ac21583bd9869b774e25238f11d4a28ba887f674e3b39c4e56533c3a5b606179a765caa78b7d0b5e84d010001	\\x2411fec181f1dff14d3f23bf85e4d51df17bfa9fe56707b7d3de8da2ea053479f8fe0306a05b3c28918e68aceed6b4c2549ba6a128fafa23c568da7e8a055f03	1651234964000000	1651839764000000	1714911764000000	1809519764000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
342	\\x2043894431e2b2e500c9e285ad385a34b840270427203c2ac73201e65314b46431c124b551356b60b8bb0256ac1c3f91a1cf8fcf76627f9098a6d30e220f147c	1	0	\\x00000001000000000080000397d0bedc8ca294e04c82f43e3bcb05dcfaeaa903b1e1b15e9bf31d673b8bec396a7278733cd5526c6d89a289a02450330c2dbdb80a685dd8c639cfd6aca201e8d13dd8a32376e498ec222ed709b031ad0dd7baf3e5d95c5503f3faeaf648c6f220f4550dc205a5b1d8d078c392e6914a8ca949358973f6f45580cbf45dac2479010001	\\x6bc1e8674599eaa8ccc125905a92d97372a413d3f1ebdeae9c2623b7a5d3145ba30e136941d0cd96094cfbf53f556ecb148b288a9f61896a2ce7ca0050972100	1671787964000000	1672392764000000	1735464764000000	1830072764000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
343	\\x2653cf630a6a1fdf9b0de13e73fce2fd871442331b92da7c1551d9bd0905a74df2faeb23aa5a25da7eea804b1b289ac1e88199fa82947d4dd0ae63d76cf82845	1	0	\\x000000010000000000800003c341f33566f0e1a422c93426045016db69a1811591f1a8e85a0b9852dd4d9b17c23ce70f47936dcde5e87cc9dedf21ee68a46e613a188c6e4479640765a2574aef0e6bc345cbca70ecf719f4c214d1105764560e2f907140b0ed578e6dccf53d5392c10603346f4a01bed9cb9f77b0bd527d92dd7c54fc7774ab2ff8daf30529010001	\\x3bd471b87541c0476c0e418e7817338d215398fc77a3ca0f1894dcdd238938dba38d0eed82fc1329639e63c92074b19bab5d89cf9fb59a74be39c11bd80fd40a	1659093464000000	1659698264000000	1722770264000000	1817378264000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
344	\\x2b77b1000ea602b992cf2e77c579a8a133a92f9b592e1a3dfbc75015bcc1dec390646adef30fd8979c7ffaeb8dc051b2279fc221a303d78d3a9c2d84b376b15d	1	0	\\x000000010000000000800003c974f42bfeb092ae1e2ece0cfd1cc9f4b2c5c05e0acebf4194871122deecec4aefb162a9932214df83ae35028f20835aa459d9d34d1004d47c2da67fefd5cec0d3b3d5459af8b52a9aae4a6f1e6d5f5f3520b21bf140584c0702d959bd763e981a6be49ab0243ff139e51feeddc1277b83ab3c4bacb82b80b33d346fa970aeab010001	\\x971817bff00ea95aa3cf27bbdd300edea34bf3be179328832997acba3b5380634646223faa1423c2995110ed55b6eccf19915c13932bb3838914b635799b5a0c	1648212464000000	1648817264000000	1711889264000000	1806497264000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
345	\\x2dd7e5920ad4e908ca188f5d36b8ce0802d819c812c1fb11809a8bba7a1d7b239c1b089339fab52a49ff349292e47ff3ad5b617fed445d82ab2d00d927225756	1	0	\\x000000010000000000800003e0c32d161d8b6cccc8e5fad11486fb23fc8909722db61c769e1e0bceb6e71b9ed657049f6982b3547cf4a30c0f51e74f2c159cad1cadc64c508ff55ac1d8fcc6880bb724478da89f015887ff6e4b341f0683de43c78e02d6678487a840cf4013746ae38fe57738e60ff76a83b7a03cd5e9da160f34c276508b34495f2ffbc653010001	\\x6a37010f5648e4883911012184e2b49e16dc0e4d249b2a742424216ecc7828873069963cec1b2ff5b595bf3ce081ae8da862d77137149856f1c21cfdb375f707	1665742964000000	1666347764000000	1729419764000000	1824027764000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
346	\\x2fffc90aec39acb894a9d467088ce495ff5a94a5328d910f0c1fbb2a0249427c2ff84d25b763de9c3254b3cd07c7d36b8cd561118119330e75625093e683a11b	1	0	\\x000000010000000000800003eba9813022c1b9af10380151a676c8c0f1ac3605ef722978bb20f7794693eaa53d430bd510b50550f011b2426400124ddebfdbd2f051e70cdcbf54c482fcb920100acacf253bb0a3e6ca78033069492089961453e63021afc1dffbd9b13311c9e228eb046d90b58cb83f03d5167d6fa7b6c2d1e550a0b4718074896984f853a9010001	\\x9a64bd2a6902ce5a391529212ba881d624df9fdc00b54e784ac5235fcd2d891f95a4719d7887fd73c7e8106749ad30e628aa0035188b206aae7c7655d7019e0f	1674810464000000	1675415264000000	1738487264000000	1833095264000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
347	\\x31f3a8222d143c82f8ba0cc09db039164f010f31e29a3f961dfc4ce2bb1cd2fabbd465f4dfdc5e3b50cd65d2257b17ca37f507b44beee6492351e4a0db92c1ed	1	0	\\x0000000100000000008000039e02abbf5cf20001c8defc9683fb60546a7904cbc3bb18bf032bd565c99c868625a72ec78e393de99573181087a6e696470b5a6f1b569240afcdc178d87999c99ff33d014ad3c0298502221f1701c4040cc7db380318d44ddf3a3549f77ad957b05488c32328478fa0fc5a00002370cc0dbc0c719bcbf45f08ccd7fa5ee75e3f010001	\\xbda502c5fc9c848a5e94ffa752125c801980811ed87c8cc6baec83244e95f01e40b1531e938a09348054f96f46ec2dc05dff645e5badf8f85613c0706cb8cc04	1650630464000000	1651235264000000	1714307264000000	1808915264000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
348	\\x35bf026bc3ab24f9e5b58ab39c3c4a5ff3f97628d3cc7aecf93ce570df982c384480700a2ba6644b933b23e9da1079e71674dec6e482b9030e346586d8c9e0b5	1	0	\\x000000010000000000800003e06857c0b4a594f522a8a97f2cf3fc8252925080dc5fae97daa153b43346dc885a8e6c475f4e02db77c0ba58076d4577c8ba21689c9fe1c36741b8d70d91e6e8869a2dd9ece6ab7f57c72b1369758167b49e4bca9e0015620b0c967679684344672fc50658f6c7bbf3af7ddcb2f4a26cb3f1ce55982034a76dff055552600c5b010001	\\xd70b93d0c7e3af1ada5c0d78e09114f0fc6f37dc60f258c0dbe31aa059b1b97c00fb2b77b55eb90d5ac47b8015375e396180d271a8e5e7fc1dd941b7c2d4cc02	1676623964000000	1677228764000000	1740300764000000	1834908764000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
349	\\x35f7a2f7bfb260b0e88b8ec96dc907e63c7266d2f666b48f6b9bc5870778053a83b117aca11d97d7fcca2972bee24120e76f407e617fa18c02fdf5b4c6a7c504	1	0	\\x000000010000000000800003e6eee06a3d8aaef3a12e2953ca34111dd1a2e71cc3db4dc0d5f1fbd1a17465ed1a1323ca90ae269141a1f5b3502b0911c02588fb74a818137d88bc494b51da3a19864e3ef2d36526dc8af2db879889b6840242e5eef464f46e0ac6e9d4b13fd7eff02c750e99772ee05a413993f9fc1cb23dc16c0c615e59fe156041d5fd3de3010001	\\x74248d60cb062534eef3b9cba648882d8aad2765be63e255e78e262b1316e238f500bf8ea40dd44511c74761c7032d172472259aeffdf671425cbd789f79a10e	1667556464000000	1668161264000000	1731233264000000	1825841264000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
350	\\x386332c7728b1dfb89f88bbe04b7c5a6464beb172c7ef63796b578b7090af1a0158d3a18307c9b488743347ca4d4faba9689f312a8aa7d8327f6f4f5977c129f	1	0	\\x000000010000000000800003d69b12cab7a0c07a387a311ede38747f76ab1f52e935259a3c31e1320a97d3803a5b02aef703e0df2c8a9933eb0d1701e003ec91516e78940da79fcd830406c3093b8bf0ee8f0e1bdf0c51da1e5b3b10c7f282b5293fdb871b0fb5dbe3b29a258d9d3f14f7bd010803b66669f2b5b3c9e66ada4b68f5259ab7b8ec7871aaeb51010001	\\x2ad90d16a244cc91b9cec70b16f3a564f5afe595696b5f4d878e8ae8694bd26e78d53cc39d665ed02aa6646d4d373a4cb38b07e9f69872d73ac1ed2f3fbf4005	1676623964000000	1677228764000000	1740300764000000	1834908764000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
351	\\x3b77bbfec9cb98e4dd95d50c34b70c8b0113d39120b8b9f7b75874b08c5ff080c0af099af159feaf8c02c49e114cecfc24642550a723080c6094a1bb1c6c91b1	1	0	\\x000000010000000000800003d6fc5f3d3d44f452a92b79427b46f96264da6a45e4cac264a4258d36c64e77be20e3d1c1d133afce880caeb2c85c5647c647f35bbb08796be67027ae2931546de3006836a3c40827d84aac5aa95bf012894f0f15c3f726dbbb0d41d6681f58a6ea4f2bacee86fab0bdaf360d908010f302180c4096c8b9c1a376afd20db21b23010001	\\x7dd2560da10cab2bdfe40da7dbf1736cc21cffe11a4be8535fcbba2216b69a6f5e09c8c792e4fe14f3b7cd52b4211dcbda3e9899da8ff76dee51689b2d132302	1657279964000000	1657884764000000	1720956764000000	1815564764000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
352	\\x409bc4422ffcd2e8c4b1fc23bfbc3805be69bc4a97b71616493364d48481bd5589eeb32a84f9a24b431cc881e7e367168da40109bb543fca3ee93f32e6d1e55e	1	0	\\x000000010000000000800003ae60e5d10e81c459f1d05249e0266736bee0dda3508b44cc1642cbfd67ed887dc00769fc533f0f4f6ffa28779346ff0dffe1fb3892d7fd701bbf1f143dd859e9cd0c8e7696af95fb544ce80d2e8a8dae6b7dc111ea7b7fdba6a755dddbdbafee94e82e460d785bc4670e584a7fdc6c365c2ca93ec2c8e722b145e30f040f157b010001	\\x40f9497591632767320a77486771b05866c463abace6ab08f580cd7f6e151983578db0afeb009c708dd3df18d10f2d85a39e731655d3628f1aed55bced73e100	1649421464000000	1650026264000000	1713098264000000	1807706264000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
353	\\x4083765b9a3aa0f0c034b96b936f95d5867702a7a613fdc8bda5f1c481199a4104b7c6fa1ae734b3e9cd6adb05864d34b0e5b10b5c9e35903275af2fe3d943bf	1	0	\\x000000010000000000800003c12284c6ecf8593c02f7daf34cc771e07f9495a0b71898fbf9c678cfaf942ea88146d0930a5870774bcb6f7fd93d3d6c4683e3d4fe8bb180e1c1ea0edadd6251e929241c2e937a39eaf6fa1080f54574ba4842123cd768e48bd202e1169518ed4d5f48b9cd7d4c1f9bf89c1c36f5c3c2e657333e7b40cd4c094cd3a0551c9f47010001	\\xe4fb34a2240724f97c36b1eba9b5c71b968c7760d5e3c8b0dbf3cdd466de6105ba88dd1cd4aa0192be5439d1d5e41f6afc944c289f595386100bbb3923ae3904	1648816964000000	1649421764000000	1712493764000000	1807101764000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
354	\\x40a701db687cfd820d05c41397cec8bf005cd2b3d514d4423125d904b93f003a7df3ec4d38102aaaae33699bf2bd96b17463b2ab630ceaa4b6259b1f5c8b5fcf	1	0	\\x000000010000000000800003e71af2b2ada5ee9a2bb22c1cf81def84d0a89b0488d61b2e7ec6afae3e3b1b804a5635541ee16b19c41d7e59906cbd22b39614dc3d08678c1b2d6b571543a62c0f9b961e271f630cdfec6b03933cb2e59d5b4766979010ff5e5f74a6484936c0db5897a6eda10bef22b5d0113e7709108e397593780a370f7458fda3025fe5db010001	\\x0774efec3f565c715a29c2fe155f7c48b947e12f7f153c73db55ea824d89de495e50185a99b45caa9eb285f792de8ba7e148b04d562194a9732fa5f56650ea05	1654861964000000	1655466764000000	1718538764000000	1813146764000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
355	\\x4513be5f87192b8c43b506eb0260ab3560fb39e7f0cbd7722941fd6ffcbdd7d1fde298b28c333f41667fc7693e26d184e836a292e09384e5638fa328f9de3adc	1	0	\\x000000010000000000800003b9ce1666ad7a866d1134970ce4827b5545cfdab849b796e9b8bcbc926dd7fc4434857d8278f922e41a38e68eb0cd33a62dc58f44c1c8aa30221381e11994f4a6cc32b196c0410e946952f80bab3cd191b5642e4fbd991fe6f8b6a68b28fcff32d63749620a2a4eca2ebd9640bc0081291d75eb16f2b312efa9d24b0d57dce4d5010001	\\xd3a7f95f7709cfa4148acef6ec8f7db44a71945b1fc0acc7c4309866a0529642515bc539f26b840808b1a373aec904b0195bfce0415d8e1c9015c7cde51be906	1671183464000000	1671788264000000	1734860264000000	1829468264000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
356	\\x45a331632b4e069cc5b8a07f91501b549e54f09eccd37d498349f5538db3648ca4a64ff8a39826d427aee1196c20a3808bf9845cb236a69319ac65938ace2250	1	0	\\x000000010000000000800003df7fd819a42934cc3773199a70cddcd30aaa274e1dee39bef5ef9adfa48d36d4ddc760275eac04f2fa2fb1334338f866c4abb7bb367d247aff8e52da953e4025b12bd1f0fcb8ecd0843e37570da7b06303128400a53069189c0b98082830cca2d875a1a72bf4da64b47baab82fba7ca895a7a09a7ee3af37d37bad8df22802e9010001	\\x57ebda81535d54d240698c08986715ba8cb425188fdc1a8145a7361b404d4ec375fef5fc7825764967ecd3a77ece7fd127cd2825bb37df1cd2ba8d6715e47b0a	1672392464000000	1672997264000000	1736069264000000	1830677264000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
357	\\x461b89dc28b766c674d8f0352ce85c1c66c3cba06da45c2e109682f8bfd59e37b50cccf8f4e0cd434167f6fc5ca508bb07509447f3f4d1ff03882bef86cf512f	1	0	\\x000000010000000000800003b2eaf2d372d3ab75ac60481eca68d81401c1865625cf71d76b9cb7c1ba29a68e1430c4453d5c641795039ff177284da1a3ae9bb346d65247b04648d6a2224c6e3db33e0a38fcdf7fd16df2bbc8744fdecfe86746ccda858c51fb870672a8ea83fd77eaa1238086fa804f9b8672b9bf2038e627ecbc566a9163a20c31a1aae429010001	\\x6a71740b60a4ad1df3a7dff8fffe3087451b8763a47acea5c6d7193f95a94548ecc61dc630b93e52800780ebbc4c747ab811668ef2952c5f02f20d7209a9ff0f	1656070964000000	1656675764000000	1719747764000000	1814355764000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
358	\\x489ba033d391ff44bf02db6c9e9f6586738a57d9ac126912b7831b22670319d1bc43555ac38ea3c03ccc23c071895766e6496ef83dd8f7c0eb0b22a85f9d654e	1	0	\\x000000010000000000800003d061dde8214981cf416d114163af8c446aefb5ff575d75c106363411e0e9ff1ac4be443ce0fa7408dcec7d2af93a9a84fcaebcc20e71f980323b30edccefd8aabdeeeb539560cfb0c0863d465706985acda57356cc1fcf6422c9973dad1074f888ce380c49e89dcada1eb6518d9c7278ad2ff9eff45689c11b827d7e34feb3d7010001	\\xb761b8e791bb99ade5d93f0498c77509f86bc8309624fc58d73514df7fb436c95283280447980a4aa0ab3551def46b0d2b8ce2cf0d3d181fa4bade0d3822d90b	1663324964000000	1663929764000000	1727001764000000	1821609764000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
359	\\x4aeb8da04c3cf90148a9f4199347da2d1d8da886a0ad867f2f278b52f575601582079258cd783d937c6db9e4ac1f323d4e47c79769f3e4b1a238c980c3e07035	1	0	\\x000000010000000000800003b7c8c14ccd0556753292d50d17d03a671680ae3a1c91c8417a366ffa16ff6a8ab7c313e2bd679e2bf6874cf3bee2e6da2c9a29547ebef2665e2177567721626c64e476a58209d2c9df318af2ca501573916a005ab722d74b705b49d5355a8cd963c74678efd7bba8be2e0d44bf1ccc267e47e8d78660aadce7554623e747f2b9010001	\\xe36604f4ffb3b6d7ae763877c179a091378a7f5e72c033a2d7cab32c11fa3a6da21f28cd79ef1a70e429ae6d255a11f998cd68f5e39c093bee7aee456db5b90b	1665742964000000	1666347764000000	1729419764000000	1824027764000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
360	\\x4b43216a7cf1ff650f78d5ea857628221955162889fafb2f23503fd86bf60bdf43bce71f452bb80f804884a20a9a23d8e732f6a4bf0772e580f91fcba555cbdf	1	0	\\x000000010000000000800003d98022d8a1c411dc743e65123ed96a1d33f54877282b51fd90060c17741d06908f726b3f5b294f1883799874c538cf6c5f0214b4b477fde788f44555f609e36500fe1297e615b9b161fd028c334a01bbb1888945c78295277a73e52afb43c93a031123a1a63aedebe2f34136e148f2bdc5df8f16f3ec24cfb9d619bc0fcf6a1d010001	\\xfa4370b78d189b571e2400c9a80d58397f6e42a960f3027cb32d2f52b8f26e690e889c68682078576a74e1ae1f7aa99e73fc79db33b937d8c7d4611c5310a20c	1678437464000000	1679042264000000	1742114264000000	1836722264000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
361	\\x509b5fd101b2e2afbc73b3e5ac3362453c0deb24abc79cc6d2c1a4061aaf42d34adc7760e77c0364f0e3205c0b8b58b314f6d44db93a5a935e04d7ba11bba118	1	0	\\x000000010000000000800003d0d460a00c1df29290538a0d4fcb16391b06ebe40c458ac1c22c6cfc0ccae7baf296b8607bb407da83ddbdbe97b3dd33a0e7beea36337e7756913110819653a6d7152b5cb5e4815543afa73093ef595821b835858c8279f2fe45c8f13b871932a4a6d853e8c4b7598a03606b3eb8001eae02557799e6d3b4e4799587f98bc42d010001	\\xdb28790532b01a7dad67a390902940ea214f6a372451bcbf9ea074f9bf007af9d349525480ed02038a8c72e8bbff47d644e7bd89c1a5d3d52bfdc7f63507ec00	1654257464000000	1654862264000000	1717934264000000	1812542264000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
362	\\x51bfbc241c50442ed2b6533274c2219f397d90387fb5baec604550fe3e6fe0c03417502bf56c13b3d600a86b47074897a3df6a504a0e466f277db88f8a059072	1	0	\\x000000010000000000800003bb577dfd3b889e598e23b55b1199e705137376b5a9c6b14934ee900eab9424a6b3196dc06f51cdbcc336e59015b2bd3198a392e03e845af5c0d4a9fb632aa0f7aac3e1329f98bef68a230510eeba06715a0a7366b3d4f979455b187aba7068e55ef2b3d2d53b5974d8bf098cf73cd975b8e3218ed5e77aa7fea3cf1a1dfbce8d010001	\\x1efffda08c01e853135af9cab4ed4af53441aad8e9ef5dd25e9d574cb6a20cdf4a69e70d579fa4255b8790435c376594a53338ce8ee5c983fb75db2bd1ac1109	1677228464000000	1677833264000000	1740905264000000	1835513264000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
363	\\x539378d61cb16075d2dc26405b5456a4320160d72c007b5a565b0abc1f9257f8aa449637a9864e38a4ea921cf3959a24e1d9d87b9ca4d7a5260c6543ff803bf2	1	0	\\x000000010000000000800003b1aca0beb8f6121b93ec006cb2d51c54d730416305f60415860b21f91ec320f5ca18b0796da91ff6d16d3d0646e1695f46f5338943d29818b9178eca981c34d1b43b87233e84dfab5c1484f1d1c7664f0e373b0d508ed3d2d33c7db784458300e1a079f6e6393ee2913d89c0bcdea6b0e223aa9430eb042b2da9bb6592067a39010001	\\xa6c8f0162a6a3964d1b5fb09908aa5b9ac99e04386a14931d959286fc1614cb2d284a5498a53b06453bfb1979962b9b51e17220579ac57bcff3af379f3873a0a	1674205964000000	1674810764000000	1737882764000000	1832490764000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
364	\\x5477142b3fd7ea4517698d3a54d8d27966a51f9737985fa7457627c6fca29e684aa50f98754f0d44e1785519b49debfd7c98cab9fdc6715cc9d06eb311ba3239	1	0	\\x0000000100000000008000039eeb7bfa2557ca67a71adc7296e40a6ad99cd7f01a53f2632ec47c994228b53cc9bece84d07e9ac277916422036eb65f1de662b8627b275fbb93f1ee5cddb752dafb16807aec9060c78b49d85a1df4e0da30118beb9547f2e76709be65bcde6e03c25f64bed9526a051f16bd30ddda7e75c5efdd17ed988eca89c45903aa1f83010001	\\xe924f816025fc27ff83b90f9be074ec222b4f4997bbf61205514c49038297a9d7cc93e43775896624dc6ae2519702d732151137d5df30de256e4451cd2459704	1650025964000000	1650630764000000	1713702764000000	1808310764000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
365	\\x55b7680cdac48e760d78ef1c28136d4ac7a590ee0b098bc2d1b6d0dd7cfa85571462525fc0fa9340c74e3893ce5b69bc6fe40d629e7c1daa2aa93893c33c1424	1	0	\\x000000010000000000800003e1ddf85fa4eddb3853bbd8e9688f0bfc9775333f72684687e535cd4877af03f495ad8c2c696f7762d74202882382928f8a8587c0a47eaaca3dcf4ba0dc2b8cfdd84df5734ff105bbc72c49721608eac53dffc5363738bd25d620e7f0b3433a380f88d47b40c75269d2ea0725c5e766719b0d1b6a947734a22a1af44454076407010001	\\x37dc048b7fe02ff1986155a5b5c59596a3f4d9820a65c096a41ebc4542247a8f30c608d2408d187f6151b37d162ae62995e0a223756e7f08ef96f695de631403	1672392464000000	1672997264000000	1736069264000000	1830677264000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
366	\\x5743ea651a5cacf8339bf478c7b53a78b04f1117b7a0a8f4c855d66f5a8b582274e15eda01a57a4464502a3ce6a4250ba00d06f8dfda30940065e8ff64c954dc	1	0	\\x000000010000000000800003a141989ca00c0638c2fb47fe64c33e50b39a8eec61875862b1ed089ed8728057f50640bf831e4ac2036c431743474882fe11456eb2d851a078dd314b890223dc31ad3528ecf3d5fa21791f3a5458645f7f0d50e464e46588b815c7c423cccb9164c220a25ad94cacbacc2e4af964cb1c6a261b10db58eab20789bd82e228b805010001	\\x0dd969010fac8cbf4852fcafc5ddb8b18a4f96fe8d4d87bf589d30d86923ea88ab1247e9db37ddd859750d5d3ad1f2bcc54ecc6290bab13894858dbbea04e504	1657884464000000	1658489264000000	1721561264000000	1816169264000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
367	\\x58b79109c23e7f04742bc7652b7b02d6826e822c4ac063e74bd7c28ecb2b2d29271545391ff0e305b446bc5598f64c408d0a2c2bbe38520d0e1af48868bb5e0d	1	0	\\x000000010000000000800003cc2c26ae2425f285e92cfefea76eea0644ff5b06202c7ae0cd30abead45ddbd5a13c3ca36c6bbbd6f9c18c2724a9db82b524b4bb0f9496e5cf5fede91abea27ea8083b81341fdbaf28d9154af80683ec89151f546f4ef8e4ef2ac355486a6e2374122b95648dfb2450954a864981cf125442b348b13deef83cb961a8984e9993010001	\\x626f99f307beda3b2eab196c7682b62f796835bd02ad6bf7c82be139db22379aacd704f2e08589feb2d89c90c7658870c201db4bf2edd557551f05614942960b	1669974464000000	1670579264000000	1733651264000000	1828259264000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
368	\\x608fb0326f194f441a8d7e53d835af34d1f6bc71b0792e2c0f04192c2bbb38ae9ad51f78cab1e6981461110baaab70903501f1ab09f70b881bf562b9d32be3c5	1	0	\\x000000010000000000800003974335cdffd1134de8e5100458aa8e959bae05f13c3a8eaaf67bb7076b998dbf4f9fe0ff34cab8fd6d5e218404527441c3e456db650cde26351a51d1e1e90981b578431e8dde0290f66b6d064d51d9b055086d32db6329cff8349b01163a953d2984da3242339ca538b391b7076d19fdf548fc1a9962ee0583f25fdc0c833457010001	\\x758fd3ae8c5992aacab79c5bf399dde462cdb7602155df36af27e17fef4c529f42c1295c126ee27d1deea82b12dd646ab344fa7af8b8176b733006aa233ad209	1660906964000000	1661511764000000	1724583764000000	1819191764000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
369	\\x6283fec8b5acc0c2854ffa9974a73dc7a47d007ca89004a32c31b8a638c4f533ce631dccbd55029fc8103272b39811a6405c518119c9265251e75856e545c705	1	0	\\x000000010000000000800003db012811c0cf9c8adc4536fc920371510c19be639e12f367fdb7b051bcaca30edde5ed90ca6b9e88a7b0131f14447e6611a930dc62ce907ac04af67bac532a55df8c4ea3b2f3d4781bb7ff5d88b7981890a87003c70a38867adc92ca36cbaa2e0b9976c435650d9916e62c91f20779221f92ccfd740e8c3d882299bb58a764a9010001	\\x3a0939abd1a0ae2b2ff0ac711e46486fb6ae57c0224e4f7905b943d826cd5d7a28434be30af724a44f915efbeb692ac04e149c2e0aa1ac31d3494864ea07a702	1657279964000000	1657884764000000	1720956764000000	1815564764000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
370	\\x632b62d7eaae4557d8ed45f4d361c87403cb934094d6be188047524fb1f95b7379697def8ebf069b24c9368bd46ff5f4c0eddb6804cafc633c33375fc2081dc8	1	0	\\x000000010000000000800003d5cb399312a9cc1aefc4845ba404d231b30a239b1e183bd71ee39d09e61965e4c136b6fb3f97a65c0171453bb25a5be96800da77d1fb8be798fc34d0afa96f7b86eae715bec520b8e16d56383646e3380ce65296c83ff2fd54995a372799d5a4731933064f5e443baf1ab865d179aff264a8bbb6f83a08b5eff274bb7f26efcb010001	\\x9261ef38c6a3610598226a854eaf09a9aaed22055cb9ce946f1d4afe26377a9dc944fb9d98f176a678a2403557c680470a5beca1bd9667486575f6b4536f8b0a	1679041964000000	1679646764000000	1742718764000000	1837326764000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
371	\\x694720f7d25692f79da5c0c13d728fd017c3374453d5ae57b64c765fe6089092437c192ce0cb4cc634d78fb294d95e57ed28306b76f995861307a79b66233553	1	0	\\x000000010000000000800003be418099ffcff6eb050ce32b87f495436272b5ac72f17026700b7db4142ef5e6d47d26225fa5bda1e6d336d946d9775a527ec722c8d0e8c78044e814aa0bdfd8b87ad86cc1e59d718120a9acebdb059f6745822f29a3f4f99ebda4777880405d4d8012b8b3e7e02c8fc9b272f7a18c47c1dd2fc38e00aa664a89a9d5cb6e4fc1010001	\\x2f8aaf71088751ea669ba2a15f663c4d59ab9d1846e47cafddf31a725409f8ea9a40b2357e7d230647a280a45ec4014c08b34fe8ad6cdb65697db868472cf10f	1672996964000000	1673601764000000	1736673764000000	1831281764000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
372	\\x6bc78f8a772ef6facdad1bcc6b3a1db0741cf27d099ed7868551e1633c720512e9bc715202197bae67a42d22ea76e53170f734ec7a28d8e3599227bbff63dd74	1	0	\\x000000010000000000800003d276624a416936d983bd023639f81d8c98d294aa809fe89497ee17c2ed6e7f521196e2ababf66a9b5b1c99a1893727ccb24a81bb60ffd822149c684499875e28b725b32f99c5413138afd3c3de4d55c2166481ec71e9ce2bb179a40cd3967554819c8a50e8a50eae169597f0a5784521d544b4389ba3ba9bc3608020062e1b3b010001	\\xf601dd954650d81740faa9c58009ff8d9b4c2d8e2476498cc4cf07f941cfbed02b0eb79e7a31d820870c5be64b153b67f0ed1b6ba40302697d4a46c9e3229300	1677228464000000	1677833264000000	1740905264000000	1835513264000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
373	\\x6beb0632e128f01e44111e768e6b3db0b3fe82e46d85554d6c80a2d849ca0f410fba3a05496f93643e66732055e078f3e0a52251dbf63ff09f3feed1c77bb0e4	1	0	\\x000000010000000000800003b9dbc9b9a05f11159aa0601e3617d079984a41695c5226afad48932443fbc132e3d9612f21114a9043553ce8cf22c87933df75171a91346e82ceba4e7595c7a4ce779229b1e21e2e7c472ec84b69998639e6e60c7e28373b6b28849d54d14373373fa96b1cd2cc852290fef6c15718bad086cf2eda6418b674620d088570a64d010001	\\x046445fa8d5fe84cbbd56fbbb1ed41a91d34c34749be669ba8e785954390096939c1f0193283b33578eddbe8536d280d9dd10d70902b5092516a1ea6b3655b03	1665742964000000	1666347764000000	1729419764000000	1824027764000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
374	\\x6c8b7639b2df3b20c7da1bfd9af0e0695826ea4da72bf94aeb689dde505f0c73875a1a4126715728beccaee6035260fa22ef68214bf21342586922207bcdd15a	1	0	\\x000000010000000000800003ad365de474cbd9b11b971473f93cd68b8d04260243d4ba15f808153a05b930d1dbd0e58bd0ce0199c175f6459c5b625a87bd3057dc953e1658545a4b47eea0161fe27ae1298e8c96f35e52e5b672296feffe6f854c925f00f32c54057b76b9b32f98de936c2770147d88fe49b478316aea81a60398d74014ee7aa8ea0ccf4d99010001	\\x17f4d9c1e587e6923be2f92897bdebd2120cf030164b0e13e3a3a81950a79f2b8ce0473b46ee6ffa104d0dc8c139967d86a2b713dd3b23c94537ed77a7b6cf05	1663929464000000	1664534264000000	1727606264000000	1822214264000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
375	\\x6fa343b4b480b69076b5e744d26f60747d949b3d74f50a1695ec2dc7c9939b6f13a3119a56243733b2bd9950ffbad03b41ecfcd13e1dff858e2a7569769d640f	1	0	\\x000000010000000000800003bb523b30497c78af685aaeecee96893620b88e2665325e3869f6ef7682e8630b376b71eac70f22acc1db0731680df80f62892b40aacc6fca35656c89dd0d011c5776270a488265b198f9f3c73074b0f81a202aef9bebd2882efdb201093ac185bc063f70bcb79d08ed7e96fe6994db5ea4cc67d72f14d08d6fe2832f89aa867d010001	\\xa94fb1edcae3d910447adc99171dbef9824f5d816ebbdfcdfaf5b4e4321ffba409d964dc028e57f6da9f142dbf02bc4c36261a7725d246a12d63a840aa2f1a07	1664533964000000	1665138764000000	1728210764000000	1822818764000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
376	\\x6fcf60dd95369c1e7069e5e3bb566603b1688c25e739e1ac4d8be5f71fa53911f8c78f7a5f7207f501380c9221299f2eaccdbdca6cc84c784f1f4282972e1d7e	1	0	\\x000000010000000000800003cc56c0b18beaeb2623062914c74d6bfaef8d50d63f0ca31e14634a0574cd64a7edf2527343c39ae4cc7a274e836970b8c388c1c1b1a71cd285c38480f5b99a575eaaa56988c27fb0b59cc2d430ab2640121b065e32b7e2e55e9c422759882d0efd6e397fd970f1c218c95d4716ea95f75b3fba702d67ab298b488f7f92010db7010001	\\xc853512851573a57fcfd01821f202be6585b24de4e640f011436e5d04ce555255db9ce13c17c1ac1e6aeac1d02088d0aacbafe84e332b56e261ccc1242d23c0c	1665742964000000	1666347764000000	1729419764000000	1824027764000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
377	\\x70ebb1322c386e5781376a9396b363f3f3011b3804dc19f88d3dd44d33d4af72b1ada706892a276272e51c5461035602d21db4e6bb79f038c566742821a33e41	1	0	\\x000000010000000000800003bddaf52425976d8080b4bfc85fd5d05d838e8e437477a7c251a49d9d3d8fdcb39d961de9b33c365b0f5914a8b98f768b6b8c3d7a4ca3d7d4f1a2684662636824fb3028cf69c973f7556e20e5175582a8efd2144261e22f1bfaee1a2c03503ec24fcd0a556192c0fa6dd70431e9d9fa39e419c65d48ae52ffcbe71979027c0a1b010001	\\xb3649cc26f27b9c42ef0c2089b4fa39c6676889c68d90804dbade5c13d75e3840faace2d75b8e2db3fdd894dd560f96f697a48fe50af2a22659ad3f16e75bb02	1667556464000000	1668161264000000	1731233264000000	1825841264000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
378	\\x71df6ce1434091d98764dec0a3f313cd89ac861f0fe23da9f9c588f95e185dbec6d60feb4ac870b7ebb60ca318a523f679077a68fba59c352997edc269be4004	1	0	\\x000000010000000000800003a24ce147fdd22a99ffaf2916ebc8cbf9eb51236a3e8ac54cb54722379fe2c0cc6bdcb72a277519f154e0d318e0b63e4836a284bba6c4fd4b7f2c31fe792a707b3313faeaefb512c118b4064f8fde75475d3087cac92beae007ee711bfde70067cb1a170948c1807e96fcc6dea604bc793b14583a22cb545f74b169ab898579df010001	\\xf344d99b4fdce7de23ab4b70bd62af9afdc4bcb5e9c8cedb7e80fcfeacf9ab0484a64e126df998db0c8444a6f9632e179305655ea0d3aebaaacf01a553dd600b	1657279964000000	1657884764000000	1720956764000000	1815564764000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
379	\\x76c7103e5f823756802858fc63615f34a765f3d55b0423f4f1b79ceb59221713dbc1b626139c3aadf741b5cdde3ee14193d1261d8087ee36f220ecfff8038d8c	1	0	\\x000000010000000000800003b436b8d577301632cbcd3e9b20974850cd3b21e9171d2bf409563ee4e1c836ab3fa92a42cd005f6bfb5cfd86c0109361be29903c62bc4c12ceb470ad37e5df88997446b45eee21decb42d565453189e7190e683704bcbe1b83ce6005092295e9cb5f0d245ae352abcaff00d0512fc6d3bb20b5c6b67bba264b91ac8f34b09e67010001	\\xe42a64136bd7e85a524ea020c4624d910a8f6ba501de98f48b38b27b55d932ca16bd3b1a4636f7ef8a73fef8493417c99bb6f3f910ec69aa8c21f479e19c510e	1654257464000000	1654862264000000	1717934264000000	1812542264000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
380	\\x7657ce52fcb7eb93cca9fe822ff08bc0979c82ab9469ebefa88e466602d6e857d39cbde927ae9ddf2ab0ec04f8369be54ef618a3fc0bb361348b628d419089aa	1	0	\\x000000010000000000800003c85cafaf4f6a9fc7ed354c2d9b18638551dcc6e6d63b09f565429fa0c2cfcaf83a0e70bc3978675f10caddb5533ea1538cbfefa3a0c405671fc76f1a4396e80982ae60535250d40453b29b3e0d2d4e612153abf56277b8211c4107943b66598ed0595bde416fa7aca023ab4e308b5fac74a7d040feee963a964f9c2d0f40b869010001	\\x6af9b41b2e97a9b56165478710fb9eec7cd2b2d4f952338f4b385a0d7247f1cc01b07e8fb65cef81c7f2e824245acbf958f578e489dc2c4fe7050da182b72007	1674205964000000	1674810764000000	1737882764000000	1832490764000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
381	\\x77873fe4cade5c33ebff30af1ed3f3147c691fe6ce5af6d224d4b04ebb938d30dde4bbe9d712ac07aec7609849e680c73065a3de925577d35a967e17c85b1726	1	0	\\x000000010000000000800003d74cdb56c7d93a84464e1e34c5d323f57cdb1ada3f33ac7a6e75d8a67bd8089b8b1fe7b45bb77929bd4fc4f072e348ea8c56fcb4e1d09687fe5d6ff9337304489bf942fc383bb9b2cce73d3957cb46d3328fbad0396c561034c57a45f7cc19c0ec33c5b3112bd0ee16a33a2afa614241419e139415681a800ed6c0df07607261010001	\\x80bcf901eb3610adfc896a5d293a41a5f09042ff2891bec92dd62160fc59c21a49032be11b1687d1e02fce09b70a5431e2c05bb25d68dde9bdfd4c6997771f01	1651839464000000	1652444264000000	1715516264000000	1810124264000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
382	\\x786ff3c7f6d214d88becd24376aa0d4cb0381c0f2b68e814129ecf79851a032f4301a14b521ee84350047d90e2b31dcb27f1a79557dcdbe7018aa95162951dd8	1	0	\\x000000010000000000800003d2986d28706ff5f8441e1ec4f4bbeb75fb3a5529ed4139e0e34f253af3fb96e72e099582f777c511787699593aec267d373665878481650b6d4594b99696305b2c9052eb22d0f145b75a224cabd96fedb13b66481aa3b5c29ab05302396acd7e559526977427fd9a70f1e5657e6536bf5603e1c2af70b180f26a1375354b85af010001	\\xd0fe6313a1dfe1c732255e8bb17b117ffe28af4aae62a17a9b73b43e0c5d570967d7b8db3ca6c524b25d3b21f292dc3fdc7857762e5a0665ab4d45582a8a7d03	1657884464000000	1658489264000000	1721561264000000	1816169264000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
383	\\x7affcff7c3293812eb42a4cff61a504784f86f58e9e17d5c776c80623314083ef195520d0974f524c4b6c52a503550e793725f0b8f93b9762a97da84a32874d1	1	0	\\x000000010000000000800003aebe63b14a0fb67e5f853cab66017c5784c3d10ca95ecb864dcaf98d074e23c9fdfbdd55c50ed1532ecb74e15e394acea5914c7105c4a8689bc00e5257ac407430c081c50ac3556416ac4056bb978a002c72a9404b95bda9d4ff3fd0672d51727974afca7f001000439f9de39ded75f78a5bc03234a0512ab9e2ca4e13e3901f010001	\\x22d99e4fbaef47332790bce1d9d2321f588597f5dbe189f33b8b31f9a500af862a93708f051ba685aae04e1b4147ed86953ffcc53b7a94e72b2bc94ed4970503	1653048464000000	1653653264000000	1716725264000000	1811333264000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
384	\\x7eff42011829a71a2a69117ca10b48598f9ca591b6446c6ad6b768ef178243db3649b631d22a466d43ed8d9ab4957402e3d8f4d7da1422b78e8a9b445c06f5d9	1	0	\\x000000010000000000800003b0f7cbacc49d222adc3c47e79a459a01b83ac93562b5e59b2e0d168c09f418e63b2227e23cefc18d8c7a39e8715666ea793c24fbfb78dd95f728f8c201e210e6c22b532372aaed20ba22b7f372db942c9bf3d42caa5696d24ccc35083d6365fd3e4d51d31de9228d3de5562f675ec94c5db663d241da544980a38b77bb9e818b010001	\\x7c24433ff55a1bcf45a806fdd60515be1e459ff43af0230ce9929733ae9b3dbecca14d236f3b8f395c147e5b461573b35b3823dc8487e0613de7a74f9cfe0e07	1670578964000000	1671183764000000	1734255764000000	1828863764000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
385	\\x840bd6203567041469eea0d0a8843b353bc9453b6d6d97008bf231f268bd5fe9d535781d161ba184de9be1bc64b69f073f62360edbeadd331977d5e0b76f8cf3	1	0	\\x000000010000000000800003d977e7ec7bf4ca5e2fd8137c4332271fea46813901cb9fcd80d75349ebf77c666f2c693e594c5ea2fefb6f9bffc8c8bf130caa9bf769002b2dda12da3a98e89cad611b85bfdafa077dd9e924b6096b68d99ba4b96cd887ad3a0f53ba7acc8fafd66a5fa715a5a0e744e54825db86fbbb9141e2f840d39e120a5c7e23ceb29e53010001	\\x01e15eed41850946db411080b52bdc1ae825391dfb804b74f6b75ce14ac9dbc773eb2ed2390bebdb243e4b7acea003f4c068586e3889b399f2dec321c6a3970e	1670578964000000	1671183764000000	1734255764000000	1828863764000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
386	\\x85737b84cee49aed6caa389edee62593562a400c543bdcc29934c57925ee4e1fee5a46178035bb11fb27af0fc6713ab33f3a43b8c1c22200bb494ba0c367b4a1	1	0	\\x000000010000000000800003ca2ca812a597278b0f48bf8f180d3422240f09fbf9a7e9e71bfb3f09e3b16b487fed0c99e7d483a5319846910a6371dd3f9b05b78df9fcc5575560a10a1013cb58c6bb77787ead3044b1da23378d192c4705481705924d79fa50dbc3c3fca86a1678ef2fdf5b0101d27d2261ae307a02508afe087d77ddbc51e6c1fa1ecef631010001	\\xf975926453ba97e39ac40b14a6bcfcf59fa43782813c5246bf8e45678100338e536d9587612f8da92d7d93ede9e8f572931fa3cf6c90e58242ec619452a82100	1666347464000000	1666952264000000	1730024264000000	1824632264000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
387	\\x85a70e08a50a0a04b0e3e2db59d48e6800fffd512f8dbccf0418798aabbcee917383155424bad1881054a03e7e673a52a79ee2608a2f3c17041d0a2dc57914fe	1	0	\\x000000010000000000800003c3beccd01ded55729c879610bfc4f9d44450f6ed77c212bf8a0ced56e343a2a88b62675161769b91508b05ad391f9be81129e4ad28c25928a55013106a4911dbf1091aa447f3dd2a0e233de8ccdc37e200f54cab5b1cafce0ef5b1120433542e6b59fb8753ecc9d40a3178279bb442052075ba27b4ea24fc44b7826e82d7ff41010001	\\x70946e760ed278f29a3dca75a0459b9d75e32f695eb549e625d62448d91579403f5056eead21c5620ba535e6004490e1307d4157cae059e66c85879782e74c01	1662115964000000	1662720764000000	1725792764000000	1820400764000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
388	\\x897b66834f83a3104f1422854280ff94312a950f351ac1ddd961d2b237cfce38fdee77aa0827121af21c2dfc60e9d8e4d1f57d4ebd8361d25b4cc7ac20b9ff7a	1	0	\\x000000010000000000800003a1f4f19bed59a257c7a4af21482608c4b258672f3984faf12dfaae70fe739f1a8734ce18e302208928f7bcd1fa405d8e08c61baa125438ca5c0728203bc2ab2482426bfecbf7b69632e405319b2da1f4320fdc0ea4cd102780fd7ec90d1c793516cbf04aba04764762c1980c6991a37a559fa90e240ab8ee3dcfb8ce04f3db8b010001	\\x4a1299af45b5a0bece5bffb8dff50f3a1b440ec7585743d02cb83be1ff7135d6f633fe41e07e148f7602f82580464e55a656baed5a03f0a311b4f8fe54705607	1664533964000000	1665138764000000	1728210764000000	1822818764000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
389	\\x8a073e2e3a53c5304b8aaf08431082adebf8f43726ebbc93b17e97b1425f2d315720ea259a43fb9454b84a7dc900c734ca9bd259cdf64a0c5233e4dc59619aae	1	0	\\x000000010000000000800003fbd7d0290acd844f387bcffcc40128280f0123407a34cee38314eacb4f5d8501d9b50de69d87e49e3cf11bf47e1dd2735ba48438b35dc046b988361a2d7acd120ab5e61be17c617fc480568d9670b6a106c01ad6a08b660b7ec4002e9e5ecd96afc6a2f035d9289239774fdd80aba88046943b0cb01a9faf80f8f3c9495afc99010001	\\xc0c5fae3bf801a1b7fa9d53c33f4061707b3687f7b37ca7fe04ff5d8861b61fa3e1070d83b6a3d025ab11a232a70f8b98721513344f33c399aec575140681404	1650630464000000	1651235264000000	1714307264000000	1808915264000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
390	\\x8d9f14c4435511e81127ca2894e66ea3cd299c02e00e2f32c95feaa406c6f518c65274ac8856d53c493af5735ba5c0ecc3f414ebad3a4b05249332c07fd875a1	1	0	\\x000000010000000000800003c8825456ef3a9f59aa7e43264a0c885e72f80ccfd33d74c1b46ad4dfcdb0f06ff9b460adf99a9da30a3366f0113cd3860461bfa2b213336442f524bf10fee1c680efe1242fc059daf410d82cefd4efa4beec91c1b15c8e57629b4ab86198686361eb66169577b7fbfd63f0b58492fb7a131733d4df4863ba6dfef36a01e84685010001	\\xaeb8a55f050121d4d47b9883d0ad7951f450274586b9a0eb3ea54a0baa11250d297c171118d471731dba74baf2efab01df14da7e0221d4a9ecd50d3e54c62604	1660906964000000	1661511764000000	1724583764000000	1819191764000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
391	\\x8d432c5ae8e918cb5dea38768912cbd4367615ecfc35c026358fe7cefd0ec0a790d50a0bdba94a6e358225c94b74688ec5b62241cbb3b9ae69686c4808a4fa63	1	0	\\x000000010000000000800003cf9fdbf11db7d7c435cf6ed9674bbeec911728c1952eeb09badcf87cdde4354ac1ce43b71cef29e30763054934171f763731f740ee55bd8a7428b3f8a3ad909b8be753d161f869a10e214f793097c8dedfb53f3e17f733b587fd61abe5d357c5d670738a7fc4199246d2b42aa7e68d90f778ef46448b4f90910cb65892e44ff5010001	\\xc31b1ee57ed9a71118adde8029786b0a154b62a0226ce960f90b14a0d7ab4fffeb7d64f30b4c05bc7025824111d2e282b7cd100f3a3540dce765f50e575c2306	1656675464000000	1657280264000000	1720352264000000	1814960264000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
392	\\x9a37b5bb7b551faf67f4558cfde715963ab2ee921c777325d1647595c29f46453bac6f6ea32ab88b92cf86b9192abcfea49f77d9117e5ebb67a8cb8e1a0dbc87	1	0	\\x000000010000000000800003c4fe93e1a7b095728a38fa964080d392d763d402a72c5a86ebf8f7eeea13feae9f6f1ad82956f95b3e8902c58ce5d36f1ac32c28987674c8df5be3f2c4a88b4d7db0602c1b650d3640c3b113312c78b092ec19e599950013a4547fd17315de2d6aac86459194590e24e065b3fbcabf0953932658d5b78a0773a3ad837a0c9aab010001	\\xe53ef96bfad5737b513d2adb55d8fe36fc4c5c082715ae6bee732f3c84ea90fed9c797fff8c1ad1630026f7573c35e254a57d467d6e6676effe3761a77ffc807	1678437464000000	1679042264000000	1742114264000000	1836722264000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
393	\\x9dbbbc92642db711b1050761b15c9027e7cefba128cb6970ffeb39b7866fb6f615720c5bbfd744d332a95ad73908dba19b5b2f2367ea85c85c1bb8d57f1d4fb0	1	0	\\x000000010000000000800003b52c4cc5dfaf625b4bca43adeecb324a1c75dfdef69e7f95ae17c75cbb0b0829dd72eead06f57c3c5868b138b18e5e7c1cdbe765153c4ca8716d41c35f1d6362153bcc798029fb1b38aa7ce29ef417720f4821e04673e3b66ccb42cb06fa578708a3999b74528180992dc356e82a9ee7daf4fe1d40087bec4a751b9282e2c599010001	\\x2324547fd4a12dd5a65f9a7fda2d18905b3854a76fe34040e34dfbcb64c1586dfe727f412990743f11f9eb05d1cda90424e4b514d87c7e83caa8e093628f3c0c	1662115964000000	1662720764000000	1725792764000000	1820400764000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
394	\\x9defc02b2de0b5f0272bf130727947bc95c4f80e5dc8b4c5decac69c45b532104cfee6855bdfa009b465cb8c72a182a9e236701b0e503048380251b76b6396b0	1	0	\\x000000010000000000800003f87efd385f2860ed34c066b97ef37d51254fd463e68bc69d4365994d9577102e6173e52db49cc012a0385926514959cb80358b537d8b672df943430e08787a5c8e3694f578ceea8ce998ed6b59c0352e7a6c7d074b273a469e7a523b4c4f87646294622a1751c388e3fd21e95d5537570946778b3c892166b635bf93bdfe523b010001	\\x055fcbc8cd84e14c6b960fbde71272f78839c2ddeb0e0be24255e0f15cb1dcac9869a79fe7c7672247c1a9b2b4938624870b390a2263212e09ae089bcd2fad06	1649421464000000	1650026264000000	1713098264000000	1807706264000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
395	\\x9ec76d87ba59ee551ac9260aa4c7c4e0bb60a33532a08dcac339302e5496f96f3c58174dadd4229fdfead84006baa224b4c48c24225c05a4e54bef64e5b51c4e	1	0	\\x000000010000000000800003daf4fb3b1ddceaafe26237d624ac0a2a238037293bb6fde9cc080c5bd95f044a843003c774a0daa51c8be27b8b67a70560a3fc98e6a101b8c5fc8767a3f29a63958e50ff155e9b694fea592951c550d9bf264ffec20f985e9ffb383d42d22b0b4042ef99a26eca3bbf8f8442f0874e01d665d232c41255dbac02da6ee30b5407010001	\\xba5d439652caa80dccd27453f92470c05e30c550c3fcad401877a7e1abf1a8c3d5ebe6e866ce3589dd6ab96aa331b0b10ba4ffccae829c6a0263ba8059a8350e	1659697964000000	1660302764000000	1723374764000000	1817982764000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
396	\\xa3e35a8e75be4ab655db502fed743e9f9ea2a5236dae484ba8d296f4938d219ea79382c093e39aff10f8ef2db70f84cc2d7ec62a4826ac556d200ceaac247cbd	1	0	\\x000000010000000000800003c51acbc39c9302d318497deb881b14e3323a18d560c3281d81fad54e2b3214bcc8f97c8b395ace3c9246fd1946541da8708b026570ef5742001ef60ab356c80f4b32b349230c5f5e6a3e17e2e2d174547eae1ef24dc40df5246380a754674fb5a18b258d36e67a432304d48097bfebdf9573e98498532eb364368022294aa1a9010001	\\xd16c2e546cf145d646f61633d6467ed079035f6f9e71b8d01626a0bdd5e732783b81e66f6118ebcaed7476e59ab3b752d13a83f671868e5f6fad98bc0ec69d00	1667556464000000	1668161264000000	1731233264000000	1825841264000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
397	\\xa3cbf1058eaaee11b34fc8f2c2d53dde919c6d336954916602ca92daa14a5011af82e4c1ed83d7eae1a8be4bd399561cf52dc68b0420f567fa94ffeae9402b1d	1	0	\\x000000010000000000800003a35c5df6b7c61e4077c5ad61c067a6e26fce8c505646ef1e51e9fa643ac774ffecba6c1edd042760b481cc55f92e266ecc4027c55e345ecfde0ea69b27b91d4dd84c4840f123f0a5ecf3ddc4275c55f7c297a02075a23d878b1efbbbbb938e10953a8c7f1bfba655d151cbaba01513a375fee0a566988c7ddec3add32e527c93010001	\\x3edf37ee24555366d21faca9239e8b4b25e856bbfee956d9943865f79893ec252bcd7e947a2c431c14582f458b6871c5af1e91bfd6d68757b7f0f13f7e0e1600	1656675464000000	1657280264000000	1720352264000000	1814960264000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
398	\\xa7eb9daf5fca92d6ca3ebbacb054339deacc1c1c4a9479ed6ff90a0e09a05171e5642faf848e3a99bf4f73f61a57e548a32c3ab1f0ae4506f4931f0940c87081	1	0	\\x000000010000000000800003a86c880bdd79de86a079e4c9c6ead780c31443ce662a620e6e5d2bcc7cee145ea29ec9bec9f1a5d519a4235770c0aa81aea3ff1c769911bd2cc32176cc05edcd2d10ca60ddb1ba57b7267c22dad71930d853323c2238e58640b3a162fca474bf2233b5bebbfe6bc0584ccdff1aebe77a0405ef436105e4b3fede65c64e89021b010001	\\x4dcef98b61334c65a7c58c5421a00fddaed257ccd96f666e5cff06370a99aaf5d9799b03279b502e01c66ce9e18d5a8b40ce012c9916f6a1f4a4130ad2ebc304	1666347464000000	1666952264000000	1730024264000000	1824632264000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
399	\\xaaa7bdcb72e75c83d70569020a0fa4cf0ee4194ad3dbc0de7973cf504c51e0e312dc22df755446ff0f0f54596d8c22c1a8be462ea065a55ebd9c5ab3b044ea6a	1	0	\\x000000010000000000800003dca0e104ba40c66be6c98a56f29cab0022b97d12a968512efa6940686c24edd664fdf72c7375e06f2f085e72fa8fc5248a5e7c6a57b460ccac1bf95306b88334838a97e2410f5161b56a63a5f44b0ef9083e9533fccdd7dd6f39e54e55f878648f11bf40bf2e33512c89e2fafb7e026446d2475868d0756eea77801b23aec849010001	\\x727c77f292f2b33ea4b20055d9accba37578210abd7953055cb03051965fcdefa2424a9c4ae4d2c3b42d92893328141d45b1b969a0d266b302af9f5708327a08	1679041964000000	1679646764000000	1742718764000000	1837326764000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
400	\\xaf33d516f5a2d56efdffe52efeaa61a6b9997df0def0af31d4116eafac8a87f3592ca3c48453e96f57cd89eb029390c1a404f948cdb8165cbb7b98182395d9e0	1	0	\\x000000010000000000800003a991651965bd2291f55019ae398246d271dfaac9437c81d6879f977dc8268295c97781555d84987562c9b386723ba46bc48ca9c460e45ed2a104ee9c229538171cc06b8bfe994b518b4b2ccc25a915d4e120e47bae103afa801172cb99a4196313d5872bacd15df46910dd86aaf567ddc4353356cede5f221b8a1ae2d478c5f1010001	\\x7211fbf12f472081a26606dcbdbe092663ee49bee23e62f6248e823c487ddfd101ec9f2579e32a0d929cad9a30ee623409e18c056dcb9353b00fa7f575217609	1658488964000000	1659093764000000	1722165764000000	1816773764000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
401	\\xb42fa173e7c74b1e08106241b80bc78133e1395ad2b8277574c1229c2d62fa73ae67621fef04cd2895e2bde9f990485ee142569cb3c1242ea833e327b25b740c	1	0	\\x000000010000000000800003bfeb368a1894c00406606253903304e6468359a2cbe1d87f1077ea30ef9035b3efbb3567cf0ce17c4db4d2ce56a0d82b33cf1b57df27c274a546297434f96b0b9b8f5d9b4cca8987fc437c5ac105da42d0313778333f35d83706eba27fc4939f4a2c7b757897b93cccb5476b8538e933bab4604cbefc302a45fd8a5e8948079d010001	\\xdd4044a0f1e3a97cc5793145b01c07a4ffd318400a16632712e04d6e25015a71e694bb2bff8cc084912002f5f4d2f18c00f9df3512e4d6aefeb3089326b9700c	1673601464000000	1674206264000000	1737278264000000	1831886264000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
402	\\xb7f3e108df9c0bed377a2ba0b6d01f6035f497cfed67ade01e22e4d118be60a28ca6b990222f025c987c573137ba8ba34468057c2a1364583336c14072961c64	1	0	\\x000000010000000000800003b05d2ea42f36758ef83a2cb48fada29266a30be3ef1fd6438b7e15bbb6eef6f94e2ebd44da2f7b619db97076cba8dc642bf2ca771aa6cd9c8d7ab48c562fb21cf62e7ccd5959f7d297715bfaf0f4b7b25fcd5b9a7432e077a1f3c627a62352b566ed7b0fd054d601975d63cabcf8b7a5ece27fe115e096d61b324b979baae521010001	\\x5ebb805ebcc1b41e47b35beba28556a0a89da1590a64f4cf4448b8d6bc593393b4d495213cacc816c8c7a7dfc92af9566e1963a4e6e0a0e230d2f1e64c790e01	1655466464000000	1656071264000000	1719143264000000	1813751264000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
403	\\xbb3b82379ddf700c2f662a6318d3426768d8726f87ecda1a2ff4b234ddccd7617fdac34ad67f25d3064b6b973b393c656137db7b02c46fc85c74b0abc5e11d2a	1	0	\\x000000010000000000800003d7ae0614a5652bb6f6070a68a634943eb8f6762ec57b81937549b0e29d20385dc92fa0cbaf7692edac9195e85aaea7e56b7d5328b443e25ad51e8f4da58fc20654f1becedffdda29a317e096338d00e48a615c19c0ac4c8a8ce7c2282562d1c25daad09b78480d851081444bd7a63c62b64f1a610d707e09946cad8b3d9a89af010001	\\xf34a951f741352e4f1038cab2f981679b42a6af0f0ac288611cc235d5e30f8b09f14b225dbd8f776a32c420b883997348ec8bd01a4d3b166d4ff17f5f25fa609	1664533964000000	1665138764000000	1728210764000000	1822818764000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
404	\\xbe9f02d1bb5e682f2d13a1268d121954b292cdafd35f328c114d477cf5a238e5c1be03a70f82da65580c3d431b1fbca0ee5dd8c3a7d3b12b5214a7b297f8483b	1	0	\\x000000010000000000800003a6f588c5dfa9c04e428277e2e476f62e823df18320e564240c8b82be734ea7eeafe67660068faae6feeca7c889e660969f56bcb96534099e8d10067af44e3aa5be9bf378c4f3793d26d83f6c012e9549cbbda8909eaa7b31a81042bd692977fabe1fc20f5d4230a68a58a0b22a475a114251360c21a89481d0f6a2d699cc3a63010001	\\xdf2cf45fec9944cfff16c60b6180ab901de52f941d21bf8bd87134f74df3b22fde21d9e5ca044358434c8dc6bfe3e8ad7985add70ee8e8720d5b59255a158f0c	1650630464000000	1651235264000000	1714307264000000	1808915264000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
405	\\xbf93cc0e76a2c5f4ca53516cb680fb283040f956eda4f9bd1bd4af6f3516bf0323178b6a1139146ec96a15cbf9692e5af6adff5b3713ce8450f70da8bc687b51	1	0	\\x000000010000000000800003c7d7bbe67dc656003839718d56360662a48bdce15d1a5e4ea9c036093b4dd6709091b82afbaca520ef63b660f2ce71e515e3cd320757492a6d862324ba13824dc9e39b07c33b6127267bac8ac682676f57075b3b09ae7aecd603b3a67f8661714ab4787e89cee1905478ac648e4eaad28622b2f3f6bdf630cc711db1603679bb010001	\\xa9918d94bef459c62aa26a79552bf0b194c3d592c039e20ad97abd93c2f87906f5d09706419cb41a0faa7fd1c2dc730853d37bec5a0cd526504c99455ecc0b0d	1676623964000000	1677228764000000	1740300764000000	1834908764000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
406	\\xc38fbba321dc54589b90efe20b6e661e250791de62714c19e0286f373b07bf55c4d25c27af7c4669e3b466dd0ff80e886f0898a2d03402ead203d86213a18317	1	0	\\x000000010000000000800003a3e6e0971571dd5f510a96800a575aa4fbc39ac37ea49667d4ab698938ab81af5bf53d640d2adcfd6531dd61c7c35c1ba13ab5d0e57346e0d0f1032820789b447a00f49f063e6da6dee81b2625b0c43843230abffd760a4668936f0e04d9060afc12609b8daa79c3a209560d28b52f86f41c5a4b725da81f5a67b43171e20633010001	\\x26c98067ab9dd08373a9bc875d896058c74d6a36b8d26e0b621e05c0041818c1dc148dbd4fc774668b90deef05ff30653be2291f575fee8d9c7e704df6b4fa05	1650025964000000	1650630764000000	1713702764000000	1808310764000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
407	\\xc437dc4693da95b8e4548f345fbefff4bc87e55ebefe9836747b30c08d266bdae4b08a927832cf66552e68c3e607d79a87afd4936789e498e418a7d5387f3aa2	1	0	\\x000000010000000000800003c5dedb449c6eaade37ff98095e6d2b51de19063f3db7016e2569bcf7cd60637353bf8f8f017943021c4a1e85c7fcd2dcdf5ed16feb956ac149e5d34842f312fda3d5b1f12fadeeb41ca318d139c7245eac0d961eb26392e2f6f64619262c0533d6a2599a7efc2361528ee4503a04b45e8e6c38a7b3d939089a82e09ccaea121b010001	\\x948c39b8663419c2668f6b087d27361e6733d55dd8d334cb8b21f1eb5ae51ad355f050e5c777624f2ea74a6498e70f1792da9c08fcfe260ad624413e2e6aa006	1666347464000000	1666952264000000	1730024264000000	1824632264000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
408	\\xc4d32549555c0ba751f366c131f0feddbb63118eed996b0018210eef12ad423c9e49455bbd1b6a0593995b9d4073950a1af27367c2fc5c05507ec3b3e1dc837d	1	0	\\x000000010000000000800003a92a441200ef1b05cdaf14826b9c5085a39c557ebe1ea3e28ba43a599520dae22e33444286f78a825fc8da2ea44c7d3d7dc3009724395664078fca18c562d15c6e63d5b4bc73ab7cddaca69c0bc0dd42de0be623877657fb5d224a5bb47a7c019884ff6e0507090c245d19c3cf001fb8f8bf3e1e01e829348601ca1467b7edef010001	\\x167f218013c80aa8ef7bb3375ef4023c5f42ade5cf5e80440d4234f780cae750f83a1eac282d13d2a90517e6c3e0eb19f9eee634884db8e6acd974df72914f0f	1656070964000000	1656675764000000	1719747764000000	1814355764000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
409	\\xc7cfe29d112b09b9becef2bebce10e289001d27ac32228145706a3c04b374170fd8b0cd53a16cdee5d5af6478f60f915dcb04fe745837da5b21a0aea0474c814	1	0	\\x000000010000000000800003a74cd1070335eb4730901dbe2203a552aec2231dc6a7a27798abe26db1bf82efaefde4064967c10b47d5ba04308ff8f554b44afb86adf8e44d14a75773dc3942b718294bee040e4e9684b94a4df9652e6887bf766bae9844dea231397419bcd15eb091a182d7c0d8524f6bfb74265fd525b808ab8893a7a55c542a6f8a2d8e57010001	\\x5a0eddd12f40463662977c0a53d9f7fcf264c05bccf6367afbbbf2063ef947817967cc9eb6c8d1e144f63d041b1df5b96171e81c4d2d8c6a1c236cd6364c200f	1670578964000000	1671183764000000	1734255764000000	1828863764000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
410	\\xcf4312b9255ff1753c6f6db5fa3748ea4925f8e4994663b42bfb7a0ebd61d4eb224e4a4efe460b7e90790e34852fce94a85ecf42cd35223d4abbc264d02b6ea6	1	0	\\x000000010000000000800003a62f0db13da2f349bb94e3a2dd28cb204e482bb21d10bf1292411021af380de3a65b03540b6462344434fb7085923704ecd480cb4265dba9b4b572be98be0adca0e68b57e22b8e65a53a22583c81d4026fc2e1b48a6c4fb6359a6e011396b8393a95a6c868b4b261c83c369bb4061bfab5efb32dd91c5e95acc3209c5ea19be1010001	\\x11bfb2b8a92718fee4c0335134e80c6e8cd356af2c57abc35fd66cf7888aae0ec24e5c4dd2fb2080d4d7fcdd88f99369af84ab4823be7ee5e396b4e07405b70c	1673601464000000	1674206264000000	1737278264000000	1831886264000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
411	\\xcf2b50d85abfa5cbb659728116f92ef8f93fa64257ca079b84439a724cc5035843ae3a04f89d3c35a4108b6fb24867f50840d3d3bb7fab5738e3319f3e42913d	1	0	\\x000000010000000000800003b92a651667d8717eb56c794799ad8fb5ef19fb453cd370e3ad81e03091aaa978d4455f0a54c6fda70a6feeb92cfb1c24b8a3f709371c306625703b8b5e6954526194504901808145cb986cec3a8ebb85dd6d84aca29530310940147684fa4a627342717c5df651346e2079db32520e2cc4dfbcab8200a2071c878e5bfd0c34db010001	\\x605d7a687e3c95284e9e28aa61dc986a2274084b8a3cc0208201c2936c64c700aa9927dadb0e6d8f88179166e4085d94405aa02eb9f61eff6c336fbf9ee2790a	1672392464000000	1672997264000000	1736069264000000	1830677264000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
412	\\xd26f8e3706058b62c6960ebe3454a26e5fc2792c561d155cb4e2ccd55f50c982e3141006715126ba6ba937d7f5702b47a163595335ac3c4c5c86f5d7fc0215fb	1	0	\\x000000010000000000800003d136e9dc3964a1bcd7fadcfe0b697d798ec8754f4349fcbbbe1ee042d864333b30e9fcefaf02c47917b64f311e216bcbd4750751e7bd81730dc21bb64b9e457a6b8676a3c8d3585df9035a03f89b951ec59feac6116bb84b25670cd815322711e50e6f1675f94dc22dbbc6451c3cbc0cd00c367df60f579c408a79118d193211010001	\\x6229bcc6f06a79d8753be724dfbdf4101e9fe050d1bac6781cfb020af1dfdc13d5aa6b03ac2b17883ca90fb6504a74776990c5f0087df61801da1504e0d3d101	1657279964000000	1657884764000000	1720956764000000	1815564764000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
413	\\xd5aff1c05d51a9c369efc1f8b56e782e3236cfed3e3479b0090ac2ea0d7ca4b45b36412c9b18bf63f8c1919e7a7e201acbad357b97a04fb4e4ee037f5e1d7cd7	1	0	\\x000000010000000000800003b4cc7c6fb85f4598cedb0796486ce6b90a666cf0ba1c473a320ffb31ccc9b8a53c95f44cc91a917577bf2393f8002f71d935701ae05f31ff85aa49ae9eef6e38dab8cd5154022c3a275fc879009bc44819bd7c8cf939b3d4b45e458fc01cf89feb54d4ef12ce7265348fac6091f1d850bc9d251594de402b09c676e36e232223010001	\\x2912e3d36cc3926bcde39108f6e88a2b319b38d1c436fd0d2dffbe28ec5eb1806d5148b7d1fb5b6828bdb0d57b623f70f950e77b950ac4a3f4aeeb65dc7be80f	1656070964000000	1656675764000000	1719747764000000	1814355764000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
414	\\xdaef327d6f9c140b0f52817c7ed91c6e7d889b3e96427a5dfc5adc42ce2460842c2363190691d904ba029d063652b70b01300d59173af564abdbf2e8fc4e2d2f	1	0	\\x000000010000000000800003b7d702733f513106c32b65d89e2ce50cadf9a8905b949774b24f3c7372d9bb4ae867230458885064db1bc0fa4a866d6227d1f5e6f7698f8947690e747614b8150b6190dea1eebebb908be98bd24c1d340c7433721542900f27bd344afa503de3aa51079a69d4713c92142f6d7717d940c85f9f6c95b11474143e6fe18a034d11010001	\\x81686319a5775f4800fc2c34cb2ba71f2d22c12139fd448152d445ed27bff97a54cbe45f6756252b90c82eb1dad7c9ee02da84cdbbca15c4182be1b0a215ce0c	1677832964000000	1678437764000000	1741509764000000	1836117764000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
415	\\xdbab165aabe7205da9a659484a36250d19217a29c60820d433c9183237daa19f98429dea71ae06dade2f2b254e6366dd37206c9614aaeeb32e358f60108ab6bd	1	0	\\x000000010000000000800003bc593fe80eeb4ca3d4cf8a0c71f7f79ca9961d6d110e2b610ff0749a61ff2bab4aa90019c600118c134a48bae11ba7e4974cb0d7530c695c19ee2a10832f1eb91d6d05a28f6393ea6f234f105ea777921eb9bbeec68859d0334552088efad4cece938e6e67d8e399143475bc107fef984bd29afc4ff8e353059ac2819692c5b1010001	\\x154648ddb861733150402657f3a51eb648f457417a0a2278484556c0c475717953a5c1332db4f8776db1c75e19bc5afaed9519852d855cfb57ef1455a8126205	1670578964000000	1671183764000000	1734255764000000	1828863764000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
416	\\xe1ff26f6ef0950b0c6b9dfa84dbd0392491155646011d59330bd1de1a7d9585f63873df6f3664e1d1abae67bdc994087c50e23669e10739e8f5d251373b837a3	1	0	\\x000000010000000000800003c7a6106d4adda407eb976279e3009c7243704cd8608d8cdc85518f0956e96d331a259b78a61a818044ab7218ab0d3f547817a5ff7c6efcc2d0c11f44fac460ae06a43b12f624f29e61a462b928ecb10229853308910afb4be72c5c0a48f580d37be2206972ebf12804fa00e3a4896d33c68fa335f3c399906e53a949f0b7aa67010001	\\x13570e3e863fbb3cd515f6450c673b5445b545e717aebab937b2f8f348043e8ed3d37deb5e959aae68bde6a08e57192e37ffef7b1294f9e24d20cf8055c72e01	1676019464000000	1676624264000000	1739696264000000	1834304264000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
417	\\xe46bab85cc12983ea279565af5ea83b3af97066e92b8a6a045ce45e68a8f468d0af013adcd976f8ad229a2c7623deee53e3c624273fb8ad26e0712f5950b3410	1	0	\\x000000010000000000800003ca9c41f3cf892e911ec6569bc936ae786caca329f82f64ac21b6b5217d5bf319da04906b4f38b608e380eec7e95f1559ac0f2af7d0ce06a4b38988e85e4ce76dea528b9a935b218f73443d9e47b5afb2cb15ed19264acc53acc74d7745e9878cfa766e4ec006d656f4e218ae8beba00169af3b511ff6f34ac260d4e71a9ed3b9010001	\\x342ae8bfa602752dd7876377aafb546590640cc9d531c831d45078ede059f4af4b7eb696167e476702819aba6897e84b28575c3cffd8130aa72568b669f19d0d	1663929464000000	1664534264000000	1727606264000000	1822214264000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
418	\\xe723f224359d59934b22cbc4ab226b8805ece222cac76e81651962aae9043118396be51332094ab7049d40b04107a1cea99f2b6b14d3d336f587ef1abb1f0bae	1	0	\\x000000010000000000800003bd3015dfb6695cf91ea677823074cf3a20b9ac0e35adfbc7de3d7106dc98823bbf57ea3ee62bea6a2346330779850cb15c6438179d1b9698cd4e1360d267969ab9fb5ca7de2b6a650e109282a901595d98c3ee200fd93b1e88db5157989e4518cea4390c8a49955bcd93f48f49233812c1de2267f2f10a9be9fa8a29a610f003010001	\\x9f8ff8324658c7ffed65127870555898bdb934ef4766d8c570f0c35e1ef45924ad5b787ace73d028a3087631b02cf93ab460471b375f60ef78b510c8a557260d	1651839464000000	1652444264000000	1715516264000000	1810124264000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
419	\\xea0f582182fc544af5de4d5527131f6e822a9041f21888c02ecd28350262376879620d5c5686b07cc8d8043c846586ab2caf8b9c7751c629803108f1d4ed1075	1	0	\\x000000010000000000800003b01904dd7ea0779a7c90b5b52892019c644cf97ad773da41b404d41a053830a8487d7c5165557320b6d65727e684e12344276d6663858cc67d9331b64cd2f581d82330b81591ed852f15c7a66251c15db8ad796b788b0d8409cd32331caedd3ef7323c11e5344bdbff0589323fc59435e49dcb713297fda5f1f735eff2379ca5010001	\\x874883d5c27b175cb8fa11c718ce5723e4bf89176f004860d790199b01b7b3f2078e6fe8d4ef5b9eeca08194dfa1a7d73462c5b99f7f9936050278d15d99b702	1666347464000000	1666952264000000	1730024264000000	1824632264000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
420	\\xf25f8f5c5219a9eac5a89e05fa94dc6b1bac8a840ef8c1ca931d22f475e798ca25aa4c0af805e634341338c2c89678b545308b1a7f2b40fab7aaf85ed0e69582	1	0	\\x000000010000000000800003d1162c8910f2cf3c13125fdc6fdb1f46c9c04908a3a2287c777f1fc9339aacc88cae7ccb937c8a9b7cb661d7151f833cf3a55489b24bb913973572a796117fca0bafbce0f4a90c32ef54ea4499b0d49ab853a52c67e3411f95141a03936a854ab1a17a14b3b256889f8a0bf32d32c56382647fa7b999a3bfc1d568bdaaec47b1010001	\\x76417154f588acc215b3553ba0c0f5799b01ef2a4ca7d2c8cc748138fdd570c1d6406d0d0489d04ae89325ff55214bd6b6d2da2ca6ec9678501e5c6e3a55ce0f	1662720464000000	1663325264000000	1726397264000000	1821005264000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
421	\\xf4ffc55af2476ff75355cf4e2173ce873339e062d431e035580c2562a97f9041579125e6b6df2954a632a8a1325a8a2ac7010135a7174e74edee219876871466	1	0	\\x000000010000000000800003d306840c3642ad98183709ad4198778b46b3268216c7d41f6cba36b7d9e88f0c8e6cd81249294cf1533e4af6f1472adb1a18a415732d25235a4d114efaa510d145162b93f03704bea4e10f22a62c8af25bfafd101ee1b927e89dfc0df9b5268810c9a6d9b916dd748f1a4eae9528399a3d25f1d0ca4deef19200ea80e0321b99010001	\\xee675f97173effbe0f609edc8c138ebfc718972302a513bd8d65ac2c82b860db86043669e1d63035161340629f22ea81cfb87fe52e96b39508e4f9727597830e	1668160964000000	1668765764000000	1731837764000000	1826445764000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
422	\\xf4977317676b23e0ad759f674e520e1c1da863447b876422feee1721211f638e8d64bbb902025cdf527b5736cb3c166a70404f0eef7c0576eb1d1aebc6cf60ce	1	0	\\x000000010000000000800003be67dad0b2c7fb86f7a650f065fa9878c04d4c299654f30cae5549178c269169b9840749f0b9f5c0528e99af7042e8396763231394ba0813d48b315470c852fdd1dc9facbc6849bfb58a753fa80d734a0882353afcde11aac219d8573c5160c326d6d4f8c19ee794325a56112612795ef7f6ed6fba7786f5b6227769a433250d010001	\\x26d8344623bd151fcfd1725618387c9b00f9299b476df0f764b929028ff597f2fc8c80bbe9bdb63ee0bbd8190cc58e30398ac5c348f2a2414d408b5e0b242d07	1650630464000000	1651235264000000	1714307264000000	1808915264000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
423	\\xf51b32b139ecbe596ad0eb5340095025790d813b65162b8fe65f2ec110b58e061c9a53e40bfac5c363f15eba992b76d5208e4fe8f14daacd606be92e0d5420eb	1	0	\\x000000010000000000800003ba4d6e01faaf1b0f3fc9622dfdbb6c5ddb84c234088e018fba789aad430cf7754deb6687fc51ef53bb90df351417a139cd693fc541938c72df5e92cd857a481cbeeb3bee70c48039372faa04c2a0cef8306fdc81d12fae1e23b76148a193be6711971882451c435f188e497f165eb6a962212ae13ae836e90b49a8b00acdaee7010001	\\x6ee4a85195e9f222a32e4240fb4529cc9b7c7adf67650eda9ddef7db7cdc92077e88ea5aecfd0f388b8c0985381c2d3aa2e92d0c5c53a61bc31a6b96358bd804	1649421464000000	1650026264000000	1713098264000000	1807706264000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
424	\\xf8dff5593288e2605cc8d75bfc6a3491930c5c2b9231897f8a4a47e2652fa9c11bc84ca565e7a607b8a601888d4eae324aef2e6bf50e034d54fb8c3e081b8c4d	1	0	\\x000000010000000000800003d7a99f6faae386bb1b1d1e4b04819240904e4109d138c12953b8bf172b920652e552c6ca88b89c2eded62608ca8579f60b4aaf7d2665f4b9162c87c337cc779d500aae70f77a8a7122fd28e027cb8b3e971f1b501da2ace170033974411cd89d5f05f846974ba922bd89a67c3914747b7eabb52badbddebd6f653d859f6d3461010001	\\x4d3c078147f7f3983b71af298316ef5e3c5bb92c8d8d69e95e5fc49f29568ad6e264076199872c18b219852a0a80f91add3ab78ada4eb8fcdfb02b0498a20b0c	1679646464000000	1680251264000000	1743323264000000	1837931264000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x70f1e90eaef363c059494275bda7ead04a29bd10286274a6666bd6e6cf3b4aba	1	\\x2368636d536264ee4ec4d13725c77f38f7148b44804b9fb1eaf5699d97fb9c9c4f2fa3406bf887221af25a20fe941a55522bea1c03d7950104b43d6de79453a2	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xd5865969c685d468184c379cf4f081c1187f60fd342266e7b3d6740d24675f3c184d8ac8fa228cc6ebd1e59a50c69a88496e1b3acfc38102630a357dbcd7b6aa	1648212484000000	1648213382000000	1648213382000000	3	98000000	\\x6031b8855706a64334aa19dfdd0bc8e08587328cc7c78494c75ff0e3a543c2f4	\\x52dc4739e98c3c3f8c7609e91a63608181a80e110e8baaa52ca447cd702c4acc	\\x211af56c822788a5dae7c23dc3eb316966c97a00e0ac73458875202f6bbd9466c178ba854f1d908ef1d0cccba8a4764832d33a44e736f766d03e5d43175e4700	\\x44250085013f7a90518aba97f7d7333970538c87d5d338b3b742ec4ae572a258	\\x80d418f5fc7f00009fd418f5fc7f0000bfd418f5fc7f000080d418f5fc7f0000bfd418f5fc7f000000000000000000000000000000000000009c94a8c664df7f
\\x70f1e90eaef363c059494275bda7ead04a29bd10286274a6666bd6e6cf3b4aba	2	\\xefc4c7d9e7aa8fc3afce5331526f43f5ce38877b9b593e0265a22d764f2dc28a3a7adedb7d465b3c6a57b6124fc4e16fdb885ebf1eaf25d685d40cda958175ee	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xd5865969c685d468184c379cf4f081c1187f60fd342266e7b3d6740d24675f3c184d8ac8fa228cc6ebd1e59a50c69a88496e1b3acfc38102630a357dbcd7b6aa	1648212491000000	1648213388000000	1648213388000000	6	99000000	\\xf08b464043fa98d16abd5ad35caedf87b05d75f98b7e593f0f54faf3da621eea	\\x52dc4739e98c3c3f8c7609e91a63608181a80e110e8baaa52ca447cd702c4acc	\\xc278831c547eb11f504105172abee5344e0c30ff0cc9aa5c40d4fdd7f10cc6e0e62e47de40692e92029f15a3d0ef5e76bc5cb214423348917c8d7a3473ef7209	\\x44250085013f7a90518aba97f7d7333970538c87d5d338b3b742ec4ae572a258	\\x80d418f5fc7f00009fd418f5fc7f0000bfd418f5fc7f000080d418f5fc7f0000bfd418f5fc7f000000000000000000000000000000000000009c94a8c664df7f
\\x70f1e90eaef363c059494275bda7ead04a29bd10286274a6666bd6e6cf3b4aba	3	\\x287a5a5b78b7f1807cdcf41eea79842c418b7b2e7e85629f055700a1c9ad4ccd337b4f6749572e9a8736da3a197dfe0607eb9033345bd7434bc84686006f6c87	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xd5865969c685d468184c379cf4f081c1187f60fd342266e7b3d6740d24675f3c184d8ac8fa228cc6ebd1e59a50c69a88496e1b3acfc38102630a357dbcd7b6aa	1648212497000000	1648213394000000	1648213394000000	2	99000000	\\x5313a9a83ca66166b7fa6aa1d748869642ae098e5229d5850e26324072c9dddd	\\x52dc4739e98c3c3f8c7609e91a63608181a80e110e8baaa52ca447cd702c4acc	\\x9c4b5ff8ebae7fd3e4d0ad01a92c841753ac1dcc8f667e54ef730d415fe039112354941ceb03bc665c03fc815a9293f622e97fcdf6a254d049441611caca7f06	\\x44250085013f7a90518aba97f7d7333970538c87d5d338b3b742ec4ae572a258	\\x80d418f5fc7f00009fd418f5fc7f0000bfd418f5fc7f000080d418f5fc7f0000bfd418f5fc7f000000000000000000000000000000000000009c94a8c664df7f
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1648213382000000	1089432118	\\x6031b8855706a64334aa19dfdd0bc8e08587328cc7c78494c75ff0e3a543c2f4	1
1648213388000000	1089432118	\\xf08b464043fa98d16abd5ad35caedf87b05d75f98b7e593f0f54faf3da621eea	2
1648213394000000	1089432118	\\x5313a9a83ca66166b7fa6aa1d748869642ae098e5229d5850e26324072c9dddd	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, tiny, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	1089432118	\\x6031b8855706a64334aa19dfdd0bc8e08587328cc7c78494c75ff0e3a543c2f4	1	4	0	1648212482000000	1648212484000000	1648213382000000	1648213382000000	\\x52dc4739e98c3c3f8c7609e91a63608181a80e110e8baaa52ca447cd702c4acc	\\x2368636d536264ee4ec4d13725c77f38f7148b44804b9fb1eaf5699d97fb9c9c4f2fa3406bf887221af25a20fe941a55522bea1c03d7950104b43d6de79453a2	\\xbe71b81f80afc929fed6025c5b5795e223f0408a84182c8a9660318e283364e86d427bd54b07969ab45118221100c28865ae63d4927746567c80cfc91986b302	\\x3b91a2115e9435057656f14c7d0eedc5	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
2	1089432118	\\xf08b464043fa98d16abd5ad35caedf87b05d75f98b7e593f0f54faf3da621eea	3	7	0	1648212488000000	1648212491000000	1648213388000000	1648213388000000	\\x52dc4739e98c3c3f8c7609e91a63608181a80e110e8baaa52ca447cd702c4acc	\\xefc4c7d9e7aa8fc3afce5331526f43f5ce38877b9b593e0265a22d764f2dc28a3a7adedb7d465b3c6a57b6124fc4e16fdb885ebf1eaf25d685d40cda958175ee	\\xd077495a2e90c289efb6439749506347e910cfdaf32c76f48ccf8e2d57ab8964a6f184cdf92eef52029d3535deb45946a5fc6f188f0c0cee880eeba6b9847004	\\x3b91a2115e9435057656f14c7d0eedc5	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
3	1089432118	\\x5313a9a83ca66166b7fa6aa1d748869642ae098e5229d5850e26324072c9dddd	6	3	0	1648212494000000	1648212497000000	1648213394000000	1648213394000000	\\x52dc4739e98c3c3f8c7609e91a63608181a80e110e8baaa52ca447cd702c4acc	\\x287a5a5b78b7f1807cdcf41eea79842c418b7b2e7e85629f055700a1c9ad4ccd337b4f6749572e9a8736da3a197dfe0607eb9033345bd7434bc84686006f6c87	\\x166e0f792208ed39417efb00a85716ce9d84f5989994abdeb38b5f937b5748385644e0f9759770927183fcd84f893f1af80e9f5983544c9f0136b1d9d77f8700	\\x3b91a2115e9435057656f14c7d0eedc5	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_for_matching_default (refund_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1648213382000000	1089432118	\\x6031b8855706a64334aa19dfdd0bc8e08587328cc7c78494c75ff0e3a543c2f4	1
1648213388000000	1089432118	\\xf08b464043fa98d16abd5ad35caedf87b05d75f98b7e593f0f54faf3da621eea	2
1648213394000000	1089432118	\\x5313a9a83ca66166b7fa6aa1d748869642ae098e5229d5850e26324072c9dddd	3
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
1	contenttypes	0001_initial	2022-03-25 13:47:44.807476+01
2	auth	0001_initial	2022-03-25 13:47:44.971896+01
3	app	0001_initial	2022-03-25 13:47:45.107081+01
4	contenttypes	0002_remove_content_type_name	2022-03-25 13:47:45.123418+01
5	auth	0002_alter_permission_name_max_length	2022-03-25 13:47:45.134093+01
6	auth	0003_alter_user_email_max_length	2022-03-25 13:47:45.143503+01
7	auth	0004_alter_user_username_opts	2022-03-25 13:47:45.15409+01
8	auth	0005_alter_user_last_login_null	2022-03-25 13:47:45.162477+01
9	auth	0006_require_contenttypes_0002	2022-03-25 13:47:45.165991+01
10	auth	0007_alter_validators_add_error_messages	2022-03-25 13:47:45.1759+01
11	auth	0008_alter_user_username_max_length	2022-03-25 13:47:45.193302+01
12	auth	0009_alter_user_last_name_max_length	2022-03-25 13:47:45.203425+01
13	auth	0010_alter_group_name_max_length	2022-03-25 13:47:45.215945+01
14	auth	0011_update_proxy_permissions	2022-03-25 13:47:45.22558+01
15	auth	0012_alter_user_first_name_max_length	2022-03-25 13:47:45.235231+01
16	sessions	0001_initial	2022-03-25 13:47:45.269731+01
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
1	\\x44250085013f7a90518aba97f7d7333970538c87d5d338b3b742ec4ae572a258	\\x1238f9b9ca5e855722b7b797bf5be8ccaec40e44aba10c3dbe18a104c3e9d2e813f07a90ceea922b8436d6aa2722dda13304a2de5ebc66d278636cf7ccf3280c	1648212464000000	1655470064000000	1657889264000000
2	\\x36e674d57efa0ee80dbbdad6df0af8457dd35d2208899696f605710388ed406e	\\x36f6f34532438940c4aa2f2ae63682aa3e5ac77264f7fed2a31990389383fb530abdb550dc29f6b526a88a68d04b61ec0a4498c88652bf97e0684a3052af5c06	1669984364000000	1677241964000000	1679661164000000
3	\\x160ed6de8922af28a74f181bd3e4104b136d11c583c9f0378d43527b63a77c6d	\\xfe45f6d797b92e8a1d3298940ede0fd235ca4f41f785bb1cd3bedb8b658281a0a1f07305be249d323938bcdf5cb1ffd1942dcb6cfe4458bcf4e5f0c451cef705	1662727064000000	1669984664000000	1672403864000000
4	\\xb8be2f341f46eba6dd9f905cc19772f6c2b35b48ffd77af47a34bb2515de20b7	\\x1de55bb64e0419ca792b77f31bf7bcf436a144e875a13d021eac5838cb47a4ae9d887c46a22c81dff07be83580e936f9970d0b4713bf3f6a586f3c4e2ed28901	1655469764000000	1662727364000000	1665146564000000
5	\\x1fd662a810eade7b87d6e70b9e869df891ef5a80e5664176c6522abd4066a657	\\xeb5d06455a8f2220553139cd18aa2047d5e6b1bef87f2cd73266c05caf52fbddec4af8ac98237650f91832e1b7fa19396ba445c49d0c201561af881a30da2a05	1677241664000000	1684499264000000	1686918464000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\x92554f283120b24ae3bb98cd91d3353a9e0e24c915f250f8b5816c50911dc39f67c738fa05b66c09ebc4a02baab40a3ae9974372bd8ef000038e6b72f7d70a02
\.


--
-- Data for Name: history_requests; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.history_requests (reserve_pub, request_timestamp, reserve_sig, history_fee_val, history_fee_frac) FROM stdin;
\.


--
-- Data for Name: known_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins_default (known_coin_id, denominations_serial, coin_pub, age_commitment_hash, denom_sig, remaining_val, remaining_frac) FROM stdin;
1	223	\\x6031b8855706a64334aa19dfdd0bc8e08587328cc7c78494c75ff0e3a543c2f4	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000004747e575152badc4ce16feb8ddb4324d77da1821266b15ead1f7350fca6fc8845816a4fd0448eaf416d74a5c72f5d5986bb6149d77097e33c433fdf577c58942f4c75a6e9e575173b840d6b3492f9b6f5348f969d7afee2ad23cac534d8dbd574069329017b3ce3c48aa944e5cfffbb7af6281dd1744808df68eedecc0ca7f25	0	0
3	17	\\xf08b464043fa98d16abd5ad35caedf87b05d75f98b7e593f0f54faf3da621eea	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000063d7e3577b75f7a9409e611a54be7138c9c4d273343c7cc698f771bfc0a3cd4a5d81a81315c1ee0983a8e5797562d150ed92942e4cd5d4217660952a767aa1ee8541b9058982db8546a0151b02a6675726cc6770793a110c91ca0f50cc9e25398ddea3c7dd6dbcd3e4b7c0a59828581bfc9974e689bd109d765854ab32f7ba7b	0	1000000
6	143	\\x5313a9a83ca66166b7fa6aa1d748869642ae098e5229d5850e26324072c9dddd	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000002473c43fa4c550db7f2f9690cc0302ef5df4242bee9bdf2254c0f92e022db4a06d9ceb9c1fbd7d0a443063d421c159e17b019ac57345ce73b212bdc8694dedae4966a08d920782008cce7cc1a42215c690f293e5812789405eb3d20aae28dffeea589bf9721befea407dc8cdb3243a355e21822320a4cec4ac6764a7207e497f	0	1000000
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\xd5865969c685d468184c379cf4f081c1187f60fd342266e7b3d6740d24675f3c184d8ac8fa228cc6ebd1e59a50c69a88496e1b3acfc38102630a357dbcd7b6aa	\\x3b91a2115e9435057656f14c7d0eedc5	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.084-024533W3RPMCE	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313634383231333338327d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313634383231333338327d2c2270726f6475637473223a5b5d2c22685f77697265223a22545033354a544536475141364736324336594546395734315234433759523758364748364453584b545354305439333742575931474b434153335832353336365846385942364a4752544438474a4245334358435a475731303948474d444258514b4256444147222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3038342d303234353333573352504d4345222c2274696d657374616d70223a7b22745f73223a313634383231323438322c22745f6d73223a313634383231323438323030307d2c227061795f646561646c696e65223a7b22745f73223a313634383231363038322c22745f6d73223a313634383231363038323030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22453352594a334e4559444857305041393839545656395a41543135324b4638473531483739394b3644464245444b535639415830227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224142453445454639484759335a33335031374d484d5256304736305447334748315435544e3939434d4833575457314339423630222c226e6f6e6365223a2233544a39525839434e4730363958413053545330384d5656423243523139545a385232353439473836454347364e33374a4a4430227d	\\x2368636d536264ee4ec4d13725c77f38f7148b44804b9fb1eaf5699d97fb9c9c4f2fa3406bf887221af25a20fe941a55522bea1c03d7950104b43d6de79453a2	1648212482000000	1648216082000000	1648213382000000	t	f	taler://fulfillment-success/thx		\\xfb0116ebaa82f4e3513da3aa0bb64742
2	1	2022.084-00Y8ZQPJKS3PY	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313634383231333338387d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313634383231333338387d2c2270726f6475637473223a5b5d2c22685f77697265223a22545033354a544536475141364736324336594546395734315234433759523758364748364453584b545354305439333742575931474b434153335832353336365846385942364a4752544438474a4245334358435a475731303948474d444258514b4256444147222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3038342d303059385a51504a4b53335059222c2274696d657374616d70223a7b22745f73223a313634383231323438382c22745f6d73223a313634383231323438383030307d2c227061795f646561646c696e65223a7b22745f73223a313634383231363038382c22745f6d73223a313634383231363038383030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22453352594a334e4559444857305041393839545656395a41543135324b4638473531483739394b3644464245444b535639415830227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224142453445454639484759335a33335031374d484d5256304736305447334748315435544e3939434d4833575457314339423630222c226e6f6e6365223a22343159544a4636303358595148314733574d535047503738575039375145474e4e3134484141464b4d36543136345338484d5847227d	\\xefc4c7d9e7aa8fc3afce5331526f43f5ce38877b9b593e0265a22d764f2dc28a3a7adedb7d465b3c6a57b6124fc4e16fdb885ebf1eaf25d685d40cda958175ee	1648212488000000	1648216088000000	1648213388000000	t	f	taler://fulfillment-success/thx		\\x46f960d375b85f918b3892a5458c978f
3	1	2022.084-03C7BQMYXGX6Y	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313634383231333339347d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313634383231333339347d2c2270726f6475637473223a5b5d2c22685f77697265223a22545033354a544536475141364736324336594546395734315234433759523758364748364453584b545354305439333742575931474b434153335832353336365846385942364a4752544438474a4245334358435a475731303948474d444258514b4256444147222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3038342d3033433742514d595847583659222c2274696d657374616d70223a7b22745f73223a313634383231323439342c22745f6d73223a313634383231323439343030307d2c227061795f646561646c696e65223a7b22745f73223a313634383231363039342c22745f6d73223a313634383231363039343030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22453352594a334e4559444857305041393839545656395a41543135324b4638473531483739394b3644464245444b535639415830227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224142453445454639484759335a33335031374d484d5256304736305447334748315435544e3939434d4833575457314339423630222c226e6f6e6365223a225056354b4d32443731444548453545414b314e4a32433931515343474856363137505745544b315748533246535150574d365430227d	\\x287a5a5b78b7f1807cdcf41eea79842c418b7b2e7e85629f055700a1c9ad4ccd337b4f6749572e9a8736da3a197dfe0607eb9033345bd7434bc84686006f6c87	1648212494000000	1648216094000000	1648213394000000	t	f	taler://fulfillment-success/thx		\\xb772413ff487b8d1cdfd56811ed24666
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
1	1	1648212484000000	\\x6031b8855706a64334aa19dfdd0bc8e08587328cc7c78494c75ff0e3a543c2f4	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	1	\\x211af56c822788a5dae7c23dc3eb316966c97a00e0ac73458875202f6bbd9466c178ba854f1d908ef1d0cccba8a4764832d33a44e736f766d03e5d43175e4700	1
2	2	1648212491000000	\\xf08b464043fa98d16abd5ad35caedf87b05d75f98b7e593f0f54faf3da621eea	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	1	\\xc278831c547eb11f504105172abee5344e0c30ff0cc9aa5c40d4fdd7f10cc6e0e62e47de40692e92029f15a3d0ef5e76bc5cb214423348917c8d7a3473ef7209	1
3	3	1648212497000000	\\x5313a9a83ca66166b7fa6aa1d748869642ae098e5229d5850e26324072c9dddd	http://localhost:8081/	3	0	0	1000000	0	1000000	0	1000000	1	\\x9c4b5ff8ebae7fd3e4d0ad01a92c841753ac1dcc8f667e54ef730d415fe039112354941ceb03bc665c03fc815a9293f622e97fcdf6a254d049441611caca7f06	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x70f1e90eaef363c059494275bda7ead04a29bd10286274a6666bd6e6cf3b4aba	\\x44250085013f7a90518aba97f7d7333970538c87d5d338b3b742ec4ae572a258	1648212464000000	1655470064000000	1657889264000000	\\x1238f9b9ca5e855722b7b797bf5be8ccaec40e44aba10c3dbe18a104c3e9d2e813f07a90ceea922b8436d6aa2722dda13304a2de5ebc66d278636cf7ccf3280c
2	\\x70f1e90eaef363c059494275bda7ead04a29bd10286274a6666bd6e6cf3b4aba	\\x160ed6de8922af28a74f181bd3e4104b136d11c583c9f0378d43527b63a77c6d	1662727064000000	1669984664000000	1672403864000000	\\xfe45f6d797b92e8a1d3298940ede0fd235ca4f41f785bb1cd3bedb8b658281a0a1f07305be249d323938bcdf5cb1ffd1942dcb6cfe4458bcf4e5f0c451cef705
3	\\x70f1e90eaef363c059494275bda7ead04a29bd10286274a6666bd6e6cf3b4aba	\\x36e674d57efa0ee80dbbdad6df0af8457dd35d2208899696f605710388ed406e	1669984364000000	1677241964000000	1679661164000000	\\x36f6f34532438940c4aa2f2ae63682aa3e5ac77264f7fed2a31990389383fb530abdb550dc29f6b526a88a68d04b61ec0a4498c88652bf97e0684a3052af5c06
4	\\x70f1e90eaef363c059494275bda7ead04a29bd10286274a6666bd6e6cf3b4aba	\\xb8be2f341f46eba6dd9f905cc19772f6c2b35b48ffd77af47a34bb2515de20b7	1655469764000000	1662727364000000	1665146564000000	\\x1de55bb64e0419ca792b77f31bf7bcf436a144e875a13d021eac5838cb47a4ae9d887c46a22c81dff07be83580e936f9970d0b4713bf3f6a586f3c4e2ed28901
5	\\x70f1e90eaef363c059494275bda7ead04a29bd10286274a6666bd6e6cf3b4aba	\\x1fd662a810eade7b87d6e70b9e869df891ef5a80e5664176c6522abd4066a657	1677241664000000	1684499264000000	1686918464000000	\\xeb5d06455a8f2220553139cd18aa2047d5e6b1bef87f2cd73266c05caf52fbddec4af8ac98237650f91832e1b7fa19396ba445c49d0c201561af881a30da2a05
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\x70f1e90eaef363c059494275bda7ead04a29bd10286274a6666bd6e6cf3b4aba	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\xe3ae32b719661eab2a9e8372beb06bca6d1239fb90ffea9230a1557bbfa547adc8159146404f0608cf5e9352d42ce3bc554bb553b3551df5395ad44076c2880b
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\x52dc4739e98c3c3f8c7609e91a63608181a80e110e8baaa52ca447cd702c4acc	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\x8437c740f3297a68754d8133cef0b86cce4d35ef002caec6707942e9cc048f6f	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1648212484000000	f	\N	\N	2	1	http://localhost:8081/
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
1	\\xafd987b879a59da7d4802fc5e2a9d20009e380e9c35744e80aa3a6f265a9ed070b73e660dd1a86416797ea5fbd1dd51caad8c9988b2ee5108f8bcde3bafc110e	1
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1648212491000000	\\xf08b464043fa98d16abd5ad35caedf87b05d75f98b7e593f0f54faf3da621eea	test refund	6	0
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
-- Data for Name: partner_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.partner_accounts (payto_uri, partner_serial_id, partner_master_sig, last_seen) FROM stdin;
\.


--
-- Data for Name: partners; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.partners (partner_serial_id, partner_master_pub, start_date, end_date, wad_frequency, wad_fee_val, wad_fee_frac, master_sig, partner_base_url) FROM stdin;
\.


--
-- Data for Name: prewire_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.prewire_default (prewire_uuid, wire_method, finished, failed, buf) FROM stdin;
\.


--
-- Data for Name: purse_deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.purse_deposits (purse_deposit_serial_id, partner_serial_id, purse_pub, coin_pub, amount_with_fee_val, amount_with_fee_frac, coin_sig) FROM stdin;
\.


--
-- Data for Name: purse_merges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.purse_merges (purse_merge_request_serial_id, partner_serial_id, reserve_pub, purse_pub, merge_sig, merge_timestamp) FROM stdin;
\.


--
-- Data for Name: purse_requests; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.purse_requests (purse_deposit_serial_id, purse_pub, merge_pub, purse_expiration, h_contract_terms, age_limit, amount_with_fee_val, amount_with_fee_frac, balance_val, balance_frac, purse_sig) FROM stdin;
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
1	\\xbab19460dd96a76411d6aba88cfd3ee817be88e86dc6a2f10705a1531f98116e104d073c29788eb0c44b44ea68cd7938ca58b5b18284b6c79c2149bd49765064	\\x6031b8855706a64334aa19dfdd0bc8e08587328cc7c78494c75ff0e3a543c2f4	\\x75fb1a38359a203f57ee794f70c12d7725be8e52a62ec980bf32ee2298cc1ccf9f275fd1325533f259bf3d3844dde714c8bb195d3345b288c4280325b06d7502	4	0	2
2	\\xd092c30db3397436f8dfd4f7b2bf53a54f61ad05b2e8d6e21bc0a7d3ab251c494224a313e210695cb566852d340ff02d670e542e828f0a5ea61665cff489df9c	\\xf08b464043fa98d16abd5ad35caedf87b05d75f98b7e593f0f54faf3da621eea	\\xccf875254556ca03ae6d3a69c0cb932ea9e13e83d035b566e614d3f6735c3c03621c33fef6de8aa521b53615fd8a1394edc273a881a798351fbfedc41101e901	3	0	2
3	\\xe706373f2d2ef490fb3178c287dd649e545d965bbe418eb1695bc6bcdca13ff6fed0b2f7677c5293fafdfd27de3dcb3961e610c29746f2538425b5a4441f890c	\\xf08b464043fa98d16abd5ad35caedf87b05d75f98b7e593f0f54faf3da621eea	\\xc6dccc1c66de3bacb45ded1c094368b41e5d3a187c1149e12ccf3bdd2aad9d4d33488c57825d3eae61c941979bac1a59710c693e6faf780038c39d1b5d13fc0c	5	98000000	2
4	\\x5f1cf4fe4a8c79d9f69238008a1d53b75778345c9060dd67c13d687f3b5c28db6b460ca7ccb50503cf4733e1b012ff4793870cdae44059483b8a6c34fc839c2d	\\x5313a9a83ca66166b7fa6aa1d748869642ae098e5229d5850e26324072c9dddd	\\xdbbb63c4f90012c77ebac413d8e80d34cdf834cd889cd0627184c0af0fc345bb799f3c52803a33402a631c498852aaffce9666872f117007c79286874721f208	1	99000000	2
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\xa52c29a503cb56e5b19b3d48b0300f6fd332426e6756642b4d34450d8c5d2c3c2842c47ca89ca70ca562bdbb9b08618de43431c40dbdb7e1c8121052769c6805	90	\\x0000000100000100b1d4ffe1eec976dca3ce51056def06fc444d5c831eac4d3b75c94b24c6f0cfda5d0531338ac17afc8b09c15e424cfb9518459b1eb40fc98b2122d27f8a80b875f9492919a041ffd749d81934977e7e3227e8d8473e01d8c8f61d51bfdaa0ca43068b6810bc5ec58fa7bd056bf3fc1c92fb15a24559c21ecb83c9ff52ab85a987	\\x44505cdbbc586ec3662be605001d711f3c4ccdf0cc524c957b6a64eda708eb98306c90630533fddf740f15b72e015dc0f98891d70c0618467eafdbe780ecc5b4	\\x0000000100000001014aba3fad80504b4fbcb10d4fcb817cf558f1530d17a25e058229700b25f1baf09e04a502203e06e0207442c19049ca8f70fa4b99cea249f8c8d9eb9184bae634a9987f89c4322371b468c73f309cc4641e161f4d07e3648953ea17a30cc7ff20b648f7b913e08f4973b8da46b71647ff3862b16764766087911130a951b63c	\\x0000000100010000
2	1	1	\\x1b855ca8bda296bbf694b2886ab278c4c7aef051c1df6ad675b41c7e85cc00318eaf26845dcad16983412f9b90b5d3b67a2e10690dcdaf557a90d4717027cc04	66	\\x0000000100000100491c6781cd8d1f541f7e52f62b083fb1d5a3ff1645141c403123b12ce47487dab8ee542e3bedddc626831d95ebc870762543e6a616f846d1802a8fd15edc04810c9e1c8c7b76a782cdc1c24eebf8a71217c9386e7d80e6307ea1e1b2c773c746de50648bb67621d2a926c04385ac355d4ea15db47cce6efe0197f53684d736b7	\\x0d71f4295cb6cdf3e90d32699ca2a9e65a5fb75ea4bfb1073c50b3aaa5673a8081cdb8ff40e0bae2ef2a07d57f4d4f363af6b00a8cda1d9367d67188f8f7e651	\\x00000001000000010775fccf67adf553060e8e5e9c60d44c496ced56796063cff8582f8431184714003fd7f30b7bef575187efb57a17aef5af1d2482823f9d6a9c54b13a7088a5cb6de025b013b4f97f3e52525cbdd745b39382b261766a4b633b4e02f3e59018549acaddbe3a076bec3347aca168165f8b8a9b61fa9886f17d21db0097bdb2afb2	\\x0000000100010000
3	1	2	\\x2f32c665d9c201cd52995270e8ab7c34cf654f9158e30d16b5acdf75a61f860bb13ee31657d97b8e02f5081f66d3bf122a03c204cb0e637df06ba4f20adf1a07	209	\\x00000001000001008f3c856483a1444bde597ce55294f20a6cac329721629e90012fbebe516121af15c6d3e0fee711622be3ef5d8658c1e0ddeb4397872aa7edfb9b9b918905737699fb7f56b49063fba1c31cb13f0e34df320fa34867733d2aaebc96cb125054113308aa97e4b22cc6aae626772a8ab14f9d8cf24eff8bc26083f7ab412812dd99	\\x8bc70e18ed88230a9f6e5a0c7b453ac48f3da45b8bf97132ac38a9e2e6fc1f519845ed832860c857099dd5e0135b1f999dd9465d22d3d5c8e685ef9834a116b8	\\x00000001000000014d4517834674bc7e29bfe4fbfd57ee61acca57d6d325e7cca14639029b37c03d94431e83024ffa628270b221806f8fe5b8450345bb31988b4828e08ef4ea83a93cc9410678854ef1c6d071e0c4f6450e0914be5aadd6b3e23ec688bd828e0dc7bfbd6c326819b8194c6bb75418245b28afb1a4b65a110a2927a39be83729b4a3	\\x0000000100010000
4	1	3	\\x205b9af962688603a1c0469ec822a1c0ee05ec982e9cd1d36fc3ec9946e0362a6f0402b69f347c16f1ac5f12dca2eef5bb2a9e26008d1113cd94dd524eb65900	209	\\x000000010000010003a5d9112ba3552291e33bf1f389a8b761737593cdb6e0d69a0341c031e164828b0dea865ff754037cb879206038782b8e40c2e2652cc8e596aeb9507da112cb0004f180da73ae1cd7e579a25b40a8207bbf76ea3895f6153cc0095ab8f4f552b77e7ffbb7533713af161a225da29ddeab591671f3f92002409032110cb86e0d	\\xb251655a2235be679720a23edefab099bc3ffe4a7db953732654e957470328b9d395d2723af67c9c12810b98a4cb6257419f3eb6f66891f5402d5cdf362f5bed	\\x000000010000000135584726599ffd267f3ff5f9ab14b5d145bb79dc7a91fc57155cf96864330bfe4882ebe1db46b2754cd8472b5563094d151de4babf55128aa3ca67f06d3f69097267907c1d78a92883901f8742d2234819da0003c922084a49161d099edd842e0cb1c40ddbdef9f9c628e47dec5803dbf9599a5596738b60c7af12fbeeb784c6	\\x0000000100010000
5	1	4	\\x946d6c7ff165077bfbff088546cfd7231bfac2ff220fc75c16398e4054e284add8a9bd67a69525433bdce24ccef61338b63327548d3c92eb4c2ac50d068a440a	209	\\x000000010000010052dd13f1ab6eea0530cb0258c686c0fc1cf805d618d0c7a0e26e771e68ed763e6c26b1ff55bd15962693f001dce6d420f91e189cd451e97cdf4a36da512c3fc5e5cbeea6dcac6ef630cb010d4a99879c2faccacbf2b817cf766ef84062a50f2d03e33f909494598ced27b19045358fffc10e43d05f4894296108e9c9caa81170	\\x770c64e2d6edab15ec49c08fab8dffe8ceba50a379bbc95d48fffc7eef0900ee9ad8252ed1c4804fd08ca3473ec0b2da76da3bd44ae81345d32abdb65bb0f75d	\\x00000001000000018b34c66a9522de3a83852fd5841d73397628ef3aede20955e22dac7b5919cabceca00a0a58e46e8050c9d1d151fff28998228bb7e8dda08573bc9fd0b9fe4528d9dbcfc32dc0f0c712a0bdd0e68edda2e4e283ee9362d9a1e9546ac62cd20f4305912136bf6752feebc29a982049e6a7301290c6f246cbb1ce4ae0528c1acbf0	\\x0000000100010000
6	1	5	\\x0f1201522d0190ddf565dfbb76b19164b34f1fad48ef6c856057a14d4b414e0549699cd73f77e69f2933a95e8fe3400b25a7c3eba9cf6912debce29a5295c700	209	\\x0000000100000100165567c6ae4a31738139edcdd0f4117401f37c0b314919ac01916979f4cd1a224b3ce3660b5e43ee67b9d9bb3d5cde5372d6a8b8cee51405334e71762b494f9dbe344dca5aa2876b9e155184d60a46f6b32b46b93964327ad36d645229ca6fda0ec0008348e3bbfc8de8e4b11533d70e368e07b33229280eb98e9dc510e56eae	\\xff8f84d9d911d8c54a160a18a0dddb282a2297e797bdc2eff508cdb130daa2dab093643f7e5e89965cc15e28312ecdaf26e33adfb55832bb549e7ef2fde71887	\\x00000001000000012ca091a4c0f69a96b2122025d7da4884b8d57571e6cf935dc8a0c93ae9b07b5bffac24c66c30102914dc543ceb3597bf1587694fbb84186ef164b8b8d899f55c7cad5d946f271d12fc5ac11e9fdbeb53a3bd7e5ec43e52c72b9da1612089425876d23351ec8345bb9579cd465237d2a0355f01028be9243c38379035d0429fc8	\\x0000000100010000
7	1	6	\\xc31b694fa09a12d8d2b141ca13b965d8d69382fb2977cb65e0a3650950785681a4271f2295c6b8a9077833f75ae1a0f107e86a8cbee644d78a449f6bea37870e	209	\\x0000000100000100347a0ce8b1257926a29a8d63fbe9941c2cd8f4fd6e4396ca49ab19960286c29e186d6029bbabac29089aa6660648a796079031c7720c098afa07ad2194e663d8b40893d6b10f79429bad638a6083edc1129a1e52a7afeb74934e4106ca3a862b1cffd2f944bf16b260456abe536263af7ab534843a7e1516c07f66d693a5e0f0	\\xbb637c6777869ee46df1262d7ecdc2a5027cebd971765d1a7170fff4c5cf186cb2bb967daaa50f3bdeb4397b3fdf0605090c05b0b514c0799330f470e5f904c8	\\x00000001000000012bb0a268f4e26dd0c96a8b2c93f983f4571d89014e9dfaa43938112833e4d070d4918962a3c6a89f046c7f1fde502c07cdf666db8b0601a262d1098acf967e6dc0e8005461c8bbd23e0157db0e50bb13a72d3d68edc7cff78bfa0afab51bac53945f08a76fb54b41b34bf67c93a6d133185a5fbad102ce080e8543a488743897	\\x0000000100010000
8	1	7	\\x0a5e2754cd1a6ad555cbd0fd8733409e9ef635ce905ca3cd8840f8b102705c56ebeda9dc2afd5918043dfbc7db779a666745530c5935debad66d2c630907920a	209	\\x0000000100000100021b0dab89ed66aabe34b17b1550eb41e2d0ab0284d1ffe2624798c033e8ec781c19fa67a486ab1e0ac46c5f58179b8b16475157976926683afbab3611e6a5cede703c76e22325bc03031489c05ae09e9a80e660364088b92c30a041f70aea1b103df42d3edbb41ebe8683d46bdbc864389a0a51c2133a4888507475f5da788b	\\xa99db38d1017e0313ec260207425f1c2842acf4f030f2271290396596e66e1727660a447fb4153ce8a7a0d7ae6f28c74b467596d00ac1f01a0b2e2ca24c77e56	\\x00000001000000017161894dc17fa78d8c4361eaf1a4a74ad90c69c2721ee2a55d3298ccd6ef801667e3b44d6a948ab15401dc39780843c683896b4459d5019dcb603aa538a9682d084567df30c0a109ba4c107c48ec85f6eac5510f3313eb3c109d371c5623521af05686a9e54f5edbd8b8389b86106dad408e3288464ae5e4268a692609ba33c5	\\x0000000100010000
9	1	8	\\x0782167c0e2f8a0dad344dd5d6181a8e77194a0bc05f4913e1a3c38ab0d07d8094c2842fcf84add389809ec63dffb7aa0812c59b0528420faea3948ff31d3300	209	\\x000000010000010033fc0863505bfdf1ead55841bcee7b05c208f7e6275a9540e097c4d66179f132caea20870fadcd9c5727b8cea34a9ae1f7cfe3ffa071b37c42c7f6aa3fcc0c356e45db9dc279fa5139cc99bf59e8e4bd44f7c5dba99fc0002e493353ef9b8d203f406c0bf0e9064a7b606a524929051e6051b8ca246f9bd5444fabb4d7ee71ce	\\xac1154292456e39a8d5bf3dca1142d150a90c4c6837a5fca199d3aafdfd28b5d0e8ceb4f5f36aa1db2fa4f6f1b30d07c1895ca2a5ca8b4632931c74266d0351d	\\x00000001000000013bf0b27a040c0358f0b73ea68c8e92d84b6b0d5b09e57750037ff34555dfb03ed043f1cd50be1c721d2d90b84181c6b34c9cdd267c2cc7aeabaaad87a792cf87f2e8ee92a972c1795e564d95b0b56eadb935bee0c1cfa76a490fd2926ed09fdc7478427bdc98b40023bdd78a45092cd63359cf84cba2f2b407f8c3a23b01bd0f	\\x0000000100010000
10	1	9	\\x706ef8da714b695ab38db2d2977d656ae040b2fec04c66c44dc28cce5eab827e490dd080e4e42bdec983615362c453c50cbdea831f6ea2498cd0c66316631509	209	\\x0000000100000100889c3a6d5daa02bd9d6915f57da821d3f37d880d627695438d7ad983583c093aef7cdf8923c9f30a804ec493e7c4ea4bb678f3e607cbae42bea49f28c0d27fb34a29ac55b4277bec368efd25f469ad50c8bbd4b9b32390b3dc8b8d8521079764919e5d2e238ca491e906a04027f064f44c9123738a6e175216a335fafaa6d9db	\\x50f28e224e29ccd2a3be936dffad08307dfb4d9354262a1e947ee6d886010fe8ead82de9f99be497aa4725676cf3fc15e4e5d234af41e0e858a993772b32b186	\\x000000010000000122d8611d7af5ef20b3deb132b8e52d768dbe49d509c95283ea03dda512e5a21841f3037e6276d605ba1f3fb236851912b73d076520402520464066cbb1bda97790a5827839ffb3a1d06929d89fa84e8e1bf741898a563f12511397961587971e309d85b26faea94c2f6d7062791f8e8f381f32053e2ec0a1d8683159d4cb79be	\\x0000000100010000
11	1	10	\\x1b8775cd09972dd9cc995fa752d6961f530c3bf645700d45fa2c145e5537cc63d600ff8547b3525a61bd82207a2b8953425ea777f121abafe08598217b6aa308	139	\\x0000000100000100603bc068bb9186e54ae7da1cb5794a11165324830bd6e9f470a6da8e8e8277ea5a60b8693db061e2a44ace7aa71cd9ee1b6bf557b8e113d958e1209157589538491f719f3166f0be784cadfd78442b087cba0ae2d94d82857fe8178d111f41c50a12379116968ae6414d428811efdc0e2abdbbeb588a8ccb7efe81a9298929b8	\\x349d64dd814728495e9af4d3b455ad393881e4c38765e84d7de4206d5f66a148668f81274904adb683346f495182d9d1827bd19493d1d2719319b39e2b475c22	\\x00000001000000016868d51ae9484bbc410558dd6a1617631e829015926124772b6b02dace43ac9097e6f2f8efbc57f68388b1ef1e508dee180fbf366fd03b2cc27d0a5617e78369400d009d54aa0621329681d229c54a625cba9221a46715a1d05368aeb8392c1fda86768e4dca618815d4b2ae5c5299a992b90ac385c8f70fe31bded0a5d9c4c4	\\x0000000100010000
12	1	11	\\x0c2d1baa30088e4a54d5c35f65533a002328e5a80968f5e4a55ade8e6b80b3ec1dd94591951b5fc9b5d78305a4c3b1f2f1a32053c73590315379ed483bfc9200	139	\\x000000010000010080306c02c386d8ee89bab38bdc0422b475d2df96f6258ab6f65679f7fc3dc65b8fe76281a7ef3f5e7337877258ab73f09303a1031c420068adddc4200cab65fc765e05c0457560b0f5ef0a24427b9c2c660f98df39fb02c8a39b33aa68d384799ea7cb3f78f3bd8e2e4a8edea65640446cc48178838a786833109f3994e3f65b	\\x934f9c197cc67cb26ed66531650edc9ff61cce8677dfd0c493e83188e4f98d5a3e9ed5bf255f4bbdcf77caa86e84877c69213fc5873e57a784d00092526bc40b	\\x000000010000000187ab9114ba765e0abe6c3e95817493353ae4fa85baa53d49a866da4e90a92a3e9252b70b58857487ed995ec6bdb20ff53803b2b830f0682f7cabef4a6049402f3dbb976d6c3b82e4462c608a117504054ba3137119485e90dc95cc45d8cc488a795e1e3351c23e7f0360fef66d98befca4a199782c9e4bfb9abb165a49814f72	\\x0000000100010000
13	2	0	\\x6607cb86bc8000cf5007c8b4ce239c12c13b6761766ff5955ea538310694ab55158f4f41b9501e73c302bc3660b904c145d0e7f09d2e599a663bc3e6a2aa5f07	90	\\x00000001000001003f9df93c647719e1f23e8ec282d9cd2cde90cfb21d3558c3bc176e9bb6d238d4ab4d362202b1d2e29d9a7cb0c62d06afbdcede3bc1bf87bda47413de311a9deb0d57166e7ba6e054464dbfd36bad4420bbd9b4f5ce5893f1ac88bff1c3baddee93dfd906280ecbaa403169542145c90a9023cf0525a1149c63d41187d49ec7a2	\\x3fe895f2dc189cd0ca6d0e7b858167db927f9329e6a94642197460cb7257f679ba0a42c978d89cba6cbe564070f92f975cfe8c918be48f17a5bb677b9e3357de	\\x0000000100000001440cf41dc56e47a9f3afd4bfe81de2fc2466def7aa8e35344402a4e0baa1e6fa18afdb7bbe79d78ae37362321a35cc24f6d2b596bf980bfe591b726a8ed93cbecdae1dc1034449d4d2e9fbed455afe0332f9be6ed98d467208724caea4686d8dfde18c71fafaea8b7982e5bcdd7e3533c68e32881f20146fc145955ca8b56001	\\x0000000100010000
14	2	1	\\x9cf9f9d088e9d193dc511318947b88974d815deda4bda4426a752643942dff428094bcc513be440040ef0f4f10f91a25082116171241c81512dc402da9f3080f	209	\\x00000001000001003bf45d92c690dc465675854900e518b8712d9c6353d51f1bfc9df3afde5da3203b62968a817544845f9ede53b35cb5d5c7f6f175b66db46ced6da32479413f7d6afe22b75230e46754c516d50f297197f47a9ba12487d1cb82e5221ec46bd888b9ce4d8929db5374d9daa35db790e060fad17fda5ed33d0afb8b80406551a090	\\xfa35ad0975dab756fea160c7e371fb7ae9240cc281a1aa3e0ab62ed66d51dad77823485d78bcf27c3af699bb69ab47f067991b6c0179b084c4fcfd6740b5cf5a	\\x00000001000000010c10f1032b6c3d5b007d9b4e0efc460d58ae97b67c70ce5a3d7f6ffb5ffdb9c7f70abd19ce73f483dde1f8883d5a691879b1a0733635075c674f946e62d44c4e7198adfd9b9dee75c5eae25feeaf6a2b9b24c8d90baffeacb732d7c24b02f8e34ca7fef5a151443296bebff9efd1aae6e5705af59723571813edad56615c785e	\\x0000000100010000
15	2	2	\\x23ef7c72a093eb45155ada67e854ceb144b073c6999bcdc4a3423fbdec6af68eb03e47baa524ed006ae51543386bcaebf2e74adc5893a135c8ad757597126b0e	209	\\x00000001000001002d356efb2c016d3f28ac8887f3e8be20daa5fda9f007202b19af9f219383075fcf9497b9a4b5d3c0b02067298339b4507eee31b1bfbb65285ac7b8c30c9fa189c9dc02911bcdb3a1dac07b8cded5495023dacad84209dbf96f713235ef29609eb990e4e788b072a91d523f41f81727a3943c27cbe9e5437602bd84175f478f7b	\\x7f23a45594ebde0a3bd954b6867ab6e293f8bcc5a0a84adb8c25607978e34f64b5158a7564dcd19f49709d1b03cf33c06c323491877199896bf44b08402d0f0b	\\x00000001000000018eceb9d7432fbfa747a647b1162f20b6e666c2b7cc94cdda2d29697eeff3321391a8bc4d0d0fa213c14e55d31ff4c9b35216812617ea9f667c0fa2f5f37892921874cd2d148c2606ebb76af1d02b5e04b671ee9cc0b3b151efb6c6f3fcc01c3766362f3970329d983ee68788e5d4ebaaef3ad1d3ade7e41486390f0b722a92cf	\\x0000000100010000
16	2	3	\\x2b0d8e16fe762599e3965d2fc34e7aa151f4ea5daf8732ac589d05224cafca9a480255046eb42119547f4ddc0041673d110b1bf3e3e10736eb1ac1e190720906	209	\\x00000001000001006aa1af45425baa2982cc082e3da52ba498f99b6faf9c3aea81b40464f1f7ed0ba90a2d7fb266f2a35a70873ff3382f2c59c744dd2bb5a5c5a442b036d7ef78b1a6c6abe117362ca6b4919e339cb4bad6200cf5c05c723556356ae10ac754827cb73f2e17d9b3cb0f2c308365601ea428fdda5ca0500882279bd81c0c7feb64f0	\\x9ff5e9c1b81b0366ac802b537ac5511544956977e5865dedf3efa078b1b9b6d5c8b56ede793198c729693307f91ff43261feb1dbb12af2cee8f34512f96203e3	\\x0000000100000001925ce1ec9e45307de5cac9604faeaec931527c3b1cac18ebda2bfdf92a9dcf35c2648dc37d844bd860cbc61073e28847ff70212e0aaef962f5750166aff58c56d98fda651192f2701dd2e870dae9aed2760adfec29e2667d5d365d1c51409257526b03d42fad623f79dd6e0d96deccce2709dc7db574469f56f2d2bac4f9deb9	\\x0000000100010000
17	2	4	\\xed3100a83815f7f56d9d003921496cc107823dece73fdbae6d711b7de1dc859a84627652b20b62a717244dafff4336f00841fd9cd903e36c234bd20f74afcf0f	209	\\x00000001000001008c1bf449f4c93e40dca5063fa671b3b5c870096f14f0232720df611551348ea62e14697af9b0032611b22249e605aec2510e844e8442387346f32936a7ae7c4f0fef74553f5c2541fd13229bb8de1817b78984dfae1a1fe96fd212f19e996aac647a5fe53d26ecc30f37bd15dbf3497dca9abc2d1e2c3573fb88ce86bd3c0279	\\xd65499afe9cb8a4040ebe1414616b984a312e7d943981fc97654a8d552b297eb11e3861bd3e798ae7cc5bd140726828a58a504e0224aa7138bc4d680c3a5cb8b	\\x000000010000000115a550908bea4528ef8d7e6ce9576e37308a25f73b22e127a487bb639ce2a4fa116ec2ee23d2c7a35ee984da81fc15cf8e50903e58af738c97fd1317d789327327df94e0f11373a4e2ed63951264415ce299c2c76b7cae35238b928896a8fb2e05d46862ca771393b5a2e79bb4b1f5588adac3a3c672f638c312ec943e8d53a5	\\x0000000100010000
18	2	5	\\x8858a1635284abcc4793debaff959941b1b5e776fc4d57fd140341bd7d89d0e87cd2f01cabe8807e4b5de8b8ce263b90fe2680b9aa3ff83db0e034554276500f	209	\\x00000001000001006157c5ab394c435ebbfa533b864fcf2e87dcca19670674220245f57b5fd09d1daf938383e2cda2965414483b679bbdcbad264afe8e53fd2646a3d8e92125b647477ac565eefa46770fe6e5ae2b8cc8eddaf097297fb41378187deaef7639dcdadb6d0f340acf0acc964821f1d072f4a1c58994ea77c175320746e9885b838bc4	\\x43ff8e789402b536155a7a8ee553bf514cc7a37f63e464b18d853a8e066fed06c2d33b07c20702b2d6911b793b8063d1ff9d8f69de78747f780e5c00401fb2e3	\\x00000001000000013f917e9f2686e6f33525288f80ec143dab1c90582d1e7880f9bbe6ef587da4058a2655f7e3e8707c8a074382f802e954aafb48d770bd7e9addff94d06187202c82386be83ec9518d37e7d22ca2f3f805f821b9e2eab96ffeb080ae8b4aa9030db19b6569a584e387b5d4068ae26a72a5731a4d353284464518f4a665fec66062	\\x0000000100010000
19	2	6	\\x565c22372034e681a0095341ceb75cb7ee3539e7eca3bef5f9d202c6341341319de6f4f42a3433b96bd17d055cc1a38c128e45eb9bc56fef331235c88e157d0a	209	\\x000000010000010091242d83e58331cd51b6052ec0719e4d238a1361f45eb7eda9e15ca8b08b17e2763213a8440414d8dc26f31007c4ffc5912e45dc905512a6dee338256edf2de7d7133280334c0bb44b0056563563d1179df3cb2e3f275f9593202876220339b488cb0021f8ec2f8223d3c8859c3434455238e8f8fb15abe2d4716bf77ca7b5b3	\\xe8a365c93aa921735d95b07bf62a687ef3a8d4cd6fc285230108323aa15181fc4bac59d5264219d91229bbf75af1b845ba04327ebbf795b691168c0ad35a9ea9	\\x00000001000000019038ce0b6141fc01d5ab88c964f4ad273e05a39c38e4c1b76cf06e9630958da759c971f70ab3efaaefef8a2b0c800403ec0b252dc85d2fce09082e3f72cd2d2540274d5456009893decfa3d39552024abe3eb1aa3c6c677b8d2ceee3811afd8f4e4b5c212a699cfd8357b9f0e61626a4c581c0b9c5237a7ca854ebd7bbf5b73c	\\x0000000100010000
20	2	7	\\x7f61b70ce04e16d8b5bfc9100ab5c670df61ceda7c3927f88a71ad271d7865b852102826356c2650a95038887d16b2f258561fb9e53406d7760df6fc1cdaf203	209	\\x00000001000001006bd191edad0f3f6bb2f35dfd8b52045ab4355e978391fd81725400e0fdd422f54e7d86de808ee772c4def855755b2d92231a1aec43f3f36ad0feeeed28faef1d7c73196635210dbe02f5e7da5c6eadb8b4713db339a6f00e77fdecd3562ff43f78f73c12d96628f3c454ef1677a5d7c4249034db5605a8af72483ef4b341f19a	\\x10de2f6911dfccfd8bcc8984039cc0b751d114c8327d81787792c04283eac641b7c301f3a22d0570bcedab9ac769ad55b12e93420d5e9ac0d4c0d1d844f0856e	\\x0000000100000001111c7fe0d24a1f47a9134e290887568b7870f1e9b25671ca622daed3a20fbe35062dacff004388823d0eb772dd7cc2254d15109ec8ad658cbd34d5578e5edb96da14304a2c3c2d85e006a7224e300d41c3d0df304f1b88402e2219a8ad6557391132fb6f167bdd80c2399e971263c405117255efe38a97dd27ffb3fbe938b1ea	\\x0000000100010000
21	2	8	\\x2b5566e33a2ec052d24152844c5a02aad94fa944c19e43cf9e2042aa64ddcf3714be90050d392bd903e7d060e6ba734d4d7ce0326aa149e0b52a645680c09e07	209	\\x00000001000001005bf16f504f4b4dcce95cdd466e485d8a8ff1600fd2a47ddcaf84c6488bfc33ba6cf06e38bb9d5a1c8618a9cbbb2c630679754cc8f3a054f0d75980c574c851448a390d08f394c6ff2e40fc04bd0d2e6a1cc1b1b899283e1296cdd95d9f3241b962544d755683299b000ec4eea0143fb9787687227ad10e15e4a379ec82c66a4c	\\x544fa76a34a4c1fa0af78984921d5553f22ef04043664cb97cfed843e9661137a8070e18bb0cccbf6e71de7a5d7bec8754b3ad98d118ce5222b3f6d72cdddc5a	\\x000000010000000150999b06dad6c9ba6f4feee036a28a212f5857c4ad08986c1655ca981adb79a6976db763e15cd4ad4812e491444d2c3395f2df504911d3a602e95980d2d0ee0a65ecb431b06444aa9261ea87185652625baf4bd34098c50fa700d5e9b466dd94fdfcbe05082a73b9378ea597a2ae2221352333be0dc730fee767eef7f472bdb9	\\x0000000100010000
22	2	9	\\x042a778b0f95d0e3e4254dd4f0854085011612ed337b64d3b0b1792a67cfbff6386fefea2f1e273a7b3a7e8dd2495d72ee5c282da1cdb7f3df80275946c68400	139	\\x00000001000001009514bea65406a41fafdfd18cfa63817993c73707f681341a9345219a394b22a1d139ab627e7820484fc765725762fdcc88e334c21d6c36b4378b5101e349e457fd3d44f41fa14a1027aa8231fd22c9bec1de72e61fc1be29ab9e6fb0ee848c8e98e8672408efa9d8139890b807e457d7c79a24e549f0cd95e791c32c1c41bdc6	\\xac3abeb802d33f4b03e5779781480ddc39abe3a2d79875e3b0b61db4517f9c982a67f805c8443df6e6378cd3c5401c5b586626fb37e81cacf2cdfebd782f28a6	\\x0000000100000001b8b0fe8c3504ff5bf5fb7769190f67e983a5bfd630f9332a7ab9a951095493d557fee5a0d7e8d3406c310374f6a07144bdacc9eac9b413b1ae2336520f871825d5e679e8e44ccddc65d53930b087bde869235e97621a0753a7c3a6027d6090a1256bbb079dec3a6462b814f30d4e4609a6092c00afdef7766da87828bc3a3baf	\\x0000000100010000
23	2	10	\\x12f510c34ea13217da3a857171fb4769ff4e9b59b2b6813c8a470edf2a88cf0ee61a002a19167fde2dc5c846b7ddc0d58fc1e48dc4e15a6e97d517a777f5780e	139	\\x00000001000001005f50d05ea8c575f3d44d318a064780229ed634fe4954e37436e57af6d0bc6e6fb9e06df5a65102b00da36e45d4fae92afa9e641349d4ee4b191c4200d2f99b60d29c7cb5c266d49cfd54468bd99dc0c854619f18c48d7c9bba0ea1462dcc2bee8505db3dd0c2ca80b68fc742fa9d5d3b1e518fb54c41b813b2b00da164ddc4bc	\\x17d35815ff455f3a6d4b632ab7ccba7abf3ff83d31c95879ed3cb05b47f39c1c8b63349288fa1eafbeb675fed9c15d6993c07ca29ce17f033c2324f95f73bda1	\\x00000001000000019056a70d000b2aaa064a9c1b5bd0849bf47d0582255b1b767698fff9e3d055871b87e4874b838dacb934ebbf889bcee6597dd57b1c6413d92c9b7271791ea5220b4815a36e0d2eac1295b32b6296ce272211738029d6893f49d0a794f0ae5b4d632b9937aa2e501236fdaf5b0bdda62313da3ed3c4723dae0e71710f0f51e9fb	\\x0000000100010000
24	2	11	\\xc6699dcf6dbc9315be1f2a5779bc2e973645790ff7b8553c505d91ed30331e2a97c96865c23f35120899df72ce2225c6497facff943c754e2e67c5090df09900	139	\\x0000000100000100223c730e3bd1b1a47dbd38986de5ef57d30d648b895570bc4ea0152fa9cd738883cb2ec543297b6bb8f72351e1edf69d1171a725fa5eead29779f1858a71b415d76a56351210c2e1b4e9373d6455b45d57c1898987a52deaec66f46a92e6bbba59d7391c2f88f9b76414b41357be958ab9cb91d94dbc9ad7f54d3f7cde11086f	\\x970e7dab3a6003333d8a5dbdc6e442bfb4bc898a5534135da07223e3f2f4b6339b8adee244da267083054ca8d6e357ef2e7ea0e8f7e1a9b513f77ecc041601dc	\\x000000010000000139c1e15a1c73e9904bef0e79a8b9fb77166ad534dd8cf59cbe462e3499977268154ca3f3df1e2a2663a07214701a6530e07315131dde5b58e4a8bbd33450ef96a02e6166c355ca201905bdc48b69f0dbc052627a71cec38918716402d84d077a9da337c8b425cbf3f4c59fdce8358a723bfcb10e63cc247f3b46066521220328	\\x0000000100010000
25	3	0	\\x0ff1857cb03b65adc52724d8f7bc70c41f5ac7c44a12e25247a476b3431accace3668e65716ca09de12932a17c23d04b3da9d436f98542bd0f7fcb9114e4cd0f	143	\\x000000010000010066d302a38933df46598a0b56439caf2ab9459edc4772a8fe9d12b2015b7053f7991fe7cd4db00fbed8039ea92b672e4b15487ff274db9b76e09cb25936dfcd35f2de0fec8e114632c334d0e1a548b96ae017bad1c38cea735e380d203da3bda7e9700cabe3ceae0c0a3356a0c503bc97b7e42eedba816a56e3a3c47ce768043c	\\xe9723b97c54c61ec8fbfb5c0f6e893e1e2e0e0cb6607b5cb590db950fa173f4b59a47665924738e1b3c2d93c73cfc718c04702a8e61e4557d4bf02db0cb449d1	\\x00000001000000011bbb996e3f22bf7f3a5e3a55d6023431c2365e7e86b7c085d6348136f24d781ad0122eaa8c2f96b3b781cbf3192118e0113ed0cd05177821a0e726de348b662ad76d007edd31928bc3dfa020fec7734f9d37a4f006e8a2e470bbfa0b40014049fc1a1bf5b45331485c19bfb5ac94ac724da285ecc4534f12b54e1e5763f05ed1	\\x0000000100010000
26	3	1	\\xa21b0130fb0607060a44b47f2c96a30d68e654730e83fe1560548e233df4703077c3e22e6e772e9a7ea51fd35145a950500edb5b70ec06549c73f63369d8e909	209	\\x00000001000001009e2190406a8550c8d03cc9f8e45876ec2e4468c1afe464b14d6d51b983d1a4f689ba17d63557d6be0267f36d7c48f1ab8a2bdc3133c70ccbaba607794e202aca35b3dd4e9ac742a522e76ac2f698699fafe51280e79aba426dd6da0c5c083755a0da913aa012691020d385935c1c6bab4da8ef52304655ef863096ac3287866b	\\x370d89d42b10c155a44a9bdac9e5a6d10f72a7253b4f4e1d4a77beaeabdee6e2ed0eb1ddaa65ae76ed147578db675da4ea3b472f320dbc0c8806be5f85daca73	\\x00000001000000016ba90491446d5b513c0f949dad0ffc22a73b9cee050bd68f08cb4573bd109136c8f867ec3224818167efea8915a65bbaba2a2ddf3e5eabd5ec4adc0e829065b9bb25e503de6e2a040722b72d6b7182956fc3dc2f0a236a4485a5274edca4ffb9548d766ee20070f947e09c5f6a2000258a0655cdb41b6e2b3924a96c3fdca79f	\\x0000000100010000
27	3	2	\\xa5ba737dca8447785bc71557cf39530a6229cc891ff04c3dd9b2337bb069ac2636419d3dd1931f16a05f787736ba18c070b559aa6e0fb6d3b0e3eccd6a27eb0f	209	\\x0000000100000100425c57514f571257beea9413e7676e68a41aaf22c944c12aab075e39f61e12e976d83965571e9298b8ff04dba4613b111f74cc9dc00c00ee546a7d537ac5ccb86961c1b29288b1fbc588f6f73592bfe7c001aa615008669ccbe0a16db17b0c6ac2491cd8f62aab37da974d3a8bf0c5a421b9b5de9ab8a1d6efd425249c213710	\\xd127564803e891cea37b0eb43a42429db34e19053532929eeb72bfd2c8f34252b9ec17bc654805dcd38582cd178494c86e1cabcdd8599631f736e69a3590927c	\\x00000001000000015a650d420e0e87e99284485fcd9c23ac52ea58e3985d05d34864d04a988f18ba06fe1406637599242936ba5bc54956a478bea4519682746c6da1234b318c24e6deaed2f3eb3cab4fcd9a3ebcc7128ab8113eadca011b4c8375ecd8775c64583039e6e004623b17a82492364dd86ecffcec0d08173605e587040939b30388a4a7	\\x0000000100010000
28	3	3	\\x8ae1e5449a71874f831e246395db727f93732555ee42301cc590a0234fc11e906a24110791fd1131c5b02f3368d3783c946adf3b5f4345592e4d46d5dc871409	209	\\x00000001000001009164a8eb2adb5e1eeaf776d421e9e764adf491e7287cdf99ebf2913a306d178c116784480ceb908fa56deabf91605cb2fb6345a41bc0b29bfc488ade50a3c32c347677362ba9f52e1ba7eb4b8a9dac6682a1cbe7371f11bfdbd01542c109219be1f96b6661e14b40bedc6e18a3bb816c89500f673bdbfc550b67c67041831a49	\\x47eb755886a93c986b1e91845af749a19b73bf5de7fbdd222d31ec0440ae945da02488b6b13325d386faecc13610a63ad930ca431640a3f2352ddf17df0937d5	\\x00000001000000013c3e749245fbc0cff0288bae00fb4da2bbd0bf9cc0c0600a79d0ed5bd36f9b377305d12448f1306496e7a71f8dbb22f0b0dc908b66d9f006837f9b6c8400641cb3c5c7cdc8b71f948a50b0d13672a4c2f204db451368b8ac5a11aafda407bf54c24572c9d5a9dc60336415c62dcb0065e7ad5cc2080b5565f38fa9ffd58b0bba	\\x0000000100010000
29	3	4	\\x004317f9bf84dbb61aa522612077bdef2c00d0bcf1f8ef1601e12ab518aae93541d9fd4d82df7fba04a1a6ee29a311876a65b61e004486c7ec82be13b0bad500	209	\\x00000001000001001ce9c88067671e1852da388c4dea4e4bbbcb4b9aa882cb5b99508b67e81a4c5b8a6348f5fad2b644bfa71bff83bdd320ba5bd88d3ab28a655c75d076435c764295342db2c9a5f0b834c7b3c5a7898163e7bee78d7de907067f685c20d89f52e81654bbf379a9b9f37fb41c82d0571524f4b9e2ccee382c2f8a8ea4c9bebec671	\\x9ff55503ac4e2d1ab87631bce9d8ca2acef917514160984c6defac82d30a33e191be77b90364caf7a6b51e69cefcbb5848899d16da88cfba75086046bdbcbe0e	\\x000000010000000120467a54d3644ec340ba25778de045e1e8e674f4411e59ac19fd99c053dad206ae5efe3d0445079a7f27b886aa92e36f66d01190da108931cfc31eacc2c8450db9d932569bfff370e6e16fc32d24c3fc51998e056e3f4d058ccf98b703200040d3cf36e46a7e7817451f8d6e2f7ff61b352e50d41d71c3cf9c91a87907a76e25	\\x0000000100010000
30	3	5	\\x616618e262d497ee68d486dc2195421fe2991e2c6f00fdd83a9e72414b855cc199adfd7c78a47e0bee09f26da68bcae18209076f571d8812489deac01bb85c08	209	\\x0000000100000100630a46eeccf44b4895aa1ed054e86cfabcac849237a926f3348441ded2e9d1e9ddff89fccab3fbea4e72d1c8cfb901336d14313fdfcbd99dbdb6c8a254fcac7fc4dedcb8033dd43e92b1aeec9d81757cf45742e9883a9b27f480ea38d0d48e49dcbcf7f258772391f32f29bb05cc11681aab0f0231ed68088b139fe12e14e876	\\xacb61f9a2a7d900fb8e27a60b56dea15c10fc555e374dbde677295ff42afa154f9412b76b2eba08591a131fc6308818e41ccd69d992cf66b47005ea85abd039c	\\x000000010000000154b44f20b3a2fc730becba9fb1d5489c09af56ea7ef0035ba333a35428fd2d3316593a3e73b4f7fe8853c2d911746283b76fad3ca71f461bb12d2b3cdb092677f00efe03764d2fe089363bf1f9e4169eeedec47e0a066a7b055dfa001d19c554a750582db3675b43ee7a4950621909d77ecfad898e343e7357b83839b766ab1d	\\x0000000100010000
31	3	6	\\x265d3ca45b2c8ef3050d6a1cac0cb40ebc95984fe0cc2aec1774acd37ab59b993260e49486ca43e53a1e490907ab89fe1ba4d25c464a000a0113b36892b7da0e	209	\\x00000001000001006c84fa97dba2ca887f63f624c53e486bcd4d2199a49889d4b0aee7d8225744e1d6f24a45b50453aa75fe67102bbf4f344070c2159af88bb5d739b1c02047204fc0c30fa78c1bd3995995a4fbb41f4fa5fac59bfb5f13e9edefe3e13546dc6ede062d57022278bc0ffa980fa788d9b15ef4851ee1fec3ced8ec6b4ea9d8a3e03a	\\x2c47a43d3369f4e80a59afe7c701d70e7a28878ebe2caa7cab5c30d426a6c62a676686e4cb96c68350c63d8837b1ab83d84cf4ec6e615d1f17add7e8aa604b76	\\x00000001000000018f9b3baebdb9953b94ede303166c6a9218dda7b4dc4a82429284c5daa7a0e2281d3a8b639f6793a741796aec146265c24d0a5af59e6faa426d1db65f1682130d29730a0434b2c125c0fd2f4ac046eed5774a88fd357d83f0bb849b7c10e4a206565d3a00de3a3d9c8e91d798d3cf6e30909e1274f7091453ae7234d1196f95d7	\\x0000000100010000
32	3	7	\\xbfb92cd88b113044d10431099f7dfa148cdc095cb9930364cad242233be769d6369aaf66523c4e39c944c0625d20d0b2e40d57ce91d74b7ca8e3efebe7d5bd02	209	\\x000000010000010044ca551c63a1035a6da16a4e3cbba8c353437849c4ae494254e686213ae208d269db15a3948aa64451b2ac2e095db800e668416842149edab9d2aef351cfa78cdad846089d82f974e2325d3fcba6f24a17a7442c80c8d47ede0e1b39965ee9aceecb8b455f58fd82eb94fef7d4cdf6db2858ee1e68c89301d108f645b69217cd	\\xdf35b2fd7a775cc8e9ed41ba066f3543a5171e0fd38a75204871dbcb3b988ce81778202c874855f5d55892488d7bb29b42394cd93e03f4e1ea956075e90c7afc	\\x000000010000000112f943ecb88d1b9874660f952718d6e4874f0f74d89cdc4d2731dabc1ce09fa56570643b9336f9ac8f9762ffadea6670e8cd1d23d1471b99ed1182f49566f1d3f7656004ccfe763fe21deaf4d47401157a358a9b3eaadf0506bbcca46eb5e595154bae251381c2164864e26f56aba3d6de70632c47ed538531d2ea9d3f597e98	\\x0000000100010000
33	3	8	\\x756887494405e695a8de315d0cd2297808201bb103e98e566651a1459bb726accb04b4bd6712ccb1327dd9a6448e213939a2ad330e56c2936d83fd4328680e09	209	\\x00000001000001000e5a21e1e363cbd97c5894301473132dad76ea4a0a7417efd4b143dc578530663a6cc534d8b7b716ba0818bb3481cbb797494751af1982415ec12eb8e48ae1a8bb86f647e7fcd3331ef326a3b8dc6db2968dfc57ae02122492a0dfe37b3a85357cbada89468caa4ca57dd49994110d2fcc1258d26b4dcf189db0b64b945720af	\\x7f75b51aad341b233e3aca6c1dcbc9a99b03846a98aaf68edc8f0b742e82fc803b7f5a59bc57cfe058d17420ab63a811861c4240e6b0e4f1aac9be7307c16a4c	\\x000000010000000105a1cd004f4e0ba578bc37144eeb2843bd5879d2d425acd2ddb90f5e58c1fc2ebd6ed5a571493ee83b3f842f7f3352d7bcad7b29a76410f7be2323795c963bce5e1b4c54b75832ec53e45899992203e2632e6f904519eecb8dea54da683ac7d7afaa8ac7dc76358b2069e9003daf26eb7c028ff44a15e0a0dac5f929cf2f929a	\\x0000000100010000
34	3	9	\\x028cfdb86cbc7650e1db3d062d3db8ea2e6fb586ca34a902c3a3ddb7f9df3bf9ca39f15ad56ee825a1d0a5574ed29b7b18979e1afdda21222119f745b8b8c50c	139	\\x0000000100000100a14502acff12a983f7ca80a5f09e3cb23e4c0d1c0a4c2d4615d4cec8aa2f164a3b85da249d1cae93233ec4bd3b99e8a93cbed1432d3bee968184abacd5fdfaa20f82ab6a91a9ea5ac3a46ced85d86593be9369ce70809623b2b43440a5237169594aad1e877fca06cd03ce5af24e2facbd594dca3cce87f78d7035ee616c8f1a	\\x09692589408f39270a9f2ff4c468435883e672c4d7d8b3b4fb9d491251ee8290ca2151e834fc365e41bb172d9227d400b98487f0ce45307201613d7b3dc96f93	\\x0000000100000001b5df7003957e68ddd36739d9ae3e12a6998642951794b616a79f366d41b9b4a7757c300b18386cf88b2a7f55d2556a035bb237a6adfedd73f716646fbcd37236d51f406976d87a688891a39ba8fc83d16ba2221613440b24a094aec8dc14f6e5baef3fa0b327a1a0252ba4ed06d4a4e3b6d73ab3e5038f96d80429ee2b833768	\\x0000000100010000
35	3	10	\\x0cb53149713d33d8ddcf041449b3a3cc5bffe33dc751dce7489f3c0312e2b5789e4d53ec218247ca24988b6c9938f6460797128410945e4509967219d3d76e0f	139	\\x00000001000001006034964cf55987f3729d4e40c7ddd85c469ec0e78180eb15bd832641fabada1503006012d155e94e6dc1a5c4a07a9e21a04a4703816efea84918add9169d5a0dd57aa55939c3861461c1168ab7f1b7ac4359ee7f382ed5faae72f21d99f8e24d543700b173bffffdc3dab4d4dd4aea07cd7fa4b4695aecb600b48aa4c427825f	\\x82052d9f586f36ee192976c5efaca653b84543d8158ce358d8916ddd0fb8655b25ee1f21b62595cc5de8aaae60ad5d17c0bace5aceea19fc45db8c856f1741de	\\x00000001000000014d77b0c735f13df34b0808a87814b33a29645b7afb09e8c6bfab4ad7ef2e6b31ec6983cb7e58bf9d2744841e704847257f7b57e68b14f5fffd711d884444918f0ebc3ca0469bb574373ed0f6e0f8f07b0d88d76115a90d8b36d31108cd643bf3890c8c945276d76ede3fad8946fa3c7e4d151f3166240bb1170c4e857716cd73	\\x0000000100010000
36	3	11	\\xf3229f24a7054d21e1c29628e3a47c0b828fdc4e396d264136a378bccc2a8ab192e8cc7ec8ba19044f06137015b2b549a7e33e1444ceff8fc1e9ab460b7afd03	139	\\x00000001000001002d5dc5d002127b9094cf440f11e17ede99cee2ae1b44d4c6948538b11372b2a2b575beea6b4effec647f0d620eb220628222a6d95c6ab2dea061937071a951d18e05fa0d8c6724bcc4b210df7f91cda4e84def05513b31ec605659235509d7e7f4f47529040e545ded918004a42c23f213d3b6d5124a2b846ed03575af92bbbf	\\x701e786d0dbaa0f911c1a9eb749dcc9c6aa61dcc3d332356391925ca8aa9e18407899c6f4ee2544995d6c90b2d96878a9bdccae63c6a2cb3851e7bd84aa0573e	\\x0000000100000001bfa04c048f9c66ee0b39a9635b4fc097c13efe58613fd2dbc3c30a5bd3ded930dea785ed9226f09c7e234fa4a69feb29e4ea7e6a2981f2382f3689650491a6e31bb204e70539926343f4140ce29a44251b18cc72afc82912dd81f67c00c91d111ecbe881dcf7056d56719f663ad74638170ae20d0726752aabb3dc22db275564	\\x0000000100010000
37	4	0	\\x5a4cb587d76e9e467bb02cf834cac08897d1b76b2f12eb656d4c9ce03b439bc410eb58dd66ef4f4610d9f47ad40ec32907bca6b27bb3526a3f00f4880ed7b503	66	\\x00000001000001002363273132724bce69165630421a00726221077726651614a4264a9308562ef121e4d4236fc0aec78a10adda7eac2975bad921e9193684531b1077f6b18e92a514790512d77a839b86af0dc1e3ec344cf139f63129577ccb659777820ae1bec0fd92d2492dcdbcce879933ea0d9b81159e4723640ff165de120c410a40adf5ba	\\xc89bc64229a7b4a60fef0fcddbcd82c9739b0f99c20aba1031027ae5f647bbbbc232fa6d700a96d27dbeec3661ba2c009768e2b087e3dd3c478e7880b6723df3	\\x00000001000000012a8861fec30dc720a5e5af2df9a06355a83e99a0db5d77afb6ea9c19dd84ac1eb1085921f702e3426ac6ad7579040bff8e79e92f4a686a9554096aad1c466e8a82e6e066721e5e7a88badd9ee62d6f638c281eaf1c731b5298b030c5e0a88b221c9a549eaf5c4ed8b4c1d5ef39805ba8ebed750d993c3ccd3c6a766d067b32c8	\\x0000000100010000
38	4	1	\\x28d27df97d7852e7aa2c0fc6b2c367f5a7d9fbe9c1332ca0c875fe0b34bca7f94be760af1a23ab01266c620cf78a6c31d6f09cc007a078fc7af9f662c0498e04	209	\\x00000001000001005b703f3994395bdeab44a34b38c4610cbda2d3e3c66ce836ec2bb497d27c44cc4b825ad85a0ee56f5a2e91cd2912ad8d41ec20c405b53257a0dd46929c99996686d512995d3a9002f89b1f1918765a67be543e4f3629a48bf85a4eb9088d7428ad562a9035b52b6574bdcd62487193f956c6811a386adeb22df0062152eee90f	\\xb0d740b7d0c7c6fc1b99d206ab336b11981d1a204b6fc83b7fc8bf8f7c9ca982daf62042f3b7ecee96194a723bf37581385ee57b03674ad37fd6f21c81fbd92f	\\x00000001000000015142b5639c8e6c79115e469165386b1673212201d909c654209f2b34c79a3a8c600b594f884838d4dbace03bdeb72afda396c83ffe0f01a25f580bcc3ddce25c5b086019500b1395f6630ca0a4a738bce9b7a59b3bece673aa2e617bd76d73c80a99b612c606ffaf3bca18e89a27217584edb8e51c1e0549dcc60b9c30d203af	\\x0000000100010000
39	4	2	\\xd8c48dc2e8ad0a4896dc9702cb65c1ea5b86c42eec78c506787b98b422d4e6e7986accf3c04030ab604ca99ac45b76cfa5755a69fe4ebde9145bb4ff8df76b09	209	\\x00000001000001004b2513ffc9b285c0927dfde54ca20c9e4e2959ae934ee1301c12ad9825ecb46c13911457d55fe89957cc1aaf7bbc44d6d6d8ae0ed822f21786951001a2ab646ee0fec8df2d465b4c7953b06fc1f33353f76a514a13e950b48d57ea14a171ab7209283c87159569b4773d9b7ea7e59b0b65ae837433cc4f2b7c5e2f7139222406	\\x9767657b515ce471e90cd0956c7ad4819408197ad6a60721389f5694ba6905727216f03fe5a2605a421030fa10914f6cc86f2022dc912f73b6331edffc99d948	\\x000000010000000132f293940b85ba66041c55ef0bae2381be1cbb0c73c1102d15d6c863c8366c0c2709a64ca48eed421ec5b206e0e780767e9457fb2abca2e9831568e4ae8d7e032f4182ad6520b19ff2d2d779586b70be182aa2becb73be333ef35c7b4c7b5deefb65234d53662e31e2fd20ccd8d0364df002410f3bc1b7d1b234d6b98884b26b	\\x0000000100010000
40	4	3	\\xeb7fc0ec64a4a984674f5ca252410c9dd71c26b1ba9bb5a9cbceb7c18f7a601682d818a5f0b91c5e5b4fb313a4397fc6458c4118fd04eb5ffa952e59d636f102	209	\\x00000001000001005f47cb88c770eedbfb5466d6c2394b81e275ee41c98bd633608fa8feba014934dfa4ff2d0bc6119ee4fea5a86b6425d6cabe38885c21a6e5d528ee9f64eb3da6a656a8795b2414b962cf9f09d0b67d573883ca86c6dba46c0a1f19a80a8d7fb9683e4ee989f5ba7a7ebb4935565094d2df7ac857906be0f3fe0c7da7ee61cde6	\\xe0b033b66fa84803dea9bcb3ddbff505c9efd0033045fd110ab85870ae95cc1fc5f8db28bd9660d6462f3df021f0be9719968f82d51388b008cffd10bdbb613b	\\x000000010000000182c09dab6cd20cfbfbf47ad52353dfc5a04f671c79a7923958c24f2ea48345109984e2197c0e24ab21c9ab0e7f8f32b0c413906889b685ae863447b0d7056aadf2435929693de18bb32ba723a0048c8e3dee3c41dafd423970b225e4d3b661a05609285fa5f701f75f45355c32c23e178bfb64b82cc7149b2fe89903dac59cde	\\x0000000100010000
41	4	4	\\x636337dc7f9d0d85b4b1b698c8f0d558a3272c9d35b108de07dc9050f2f70c4df4ac8500b04a0f8450c37540012466463eae96b019364c5a54b28d0055c1b009	209	\\x00000001000001005e401f78e56b773a81fb3b7ba3f642c31a8a0ebef953222ec61f5c0342c2a60e95568192ae4935cf06d3abd360db28c88767383b736b3910a98e61dd41b3b1260e14effae813971a224d2513041059658402485bf1b3dac846ce04aca8f84c6efc47b800400cc00f24293563d2360da7635101a952ddc6b861ab4d3f245f2296	\\x4ea5799c0f0b5346e33159542a32ba61763e6c838d3f5cb223994d2282f621718cddfa1c2f410581e7efb69f847e197e7138cfedb4d014e0e499e06246eaaef7	\\x00000001000000014735fb235608de36f78e4bd9832f36522bab9d30a660bf4f410f39bf28635c6584e9af5e2fb0c4b59d6d409bfe0c41084873b4573a8f8d50b5af97f6035d8845664864584ecf96ee9e82636b29c969c4f5d7992801d697f277107b18b89fc3a058529b7e7ad47698cd42ab402d3634ae2e77e4ea35312921ce1e9903fd7d2dd1	\\x0000000100010000
42	4	5	\\x501c251c1e62d47f575205340e69d8f4af07a0c9975064b876912b0f77d4af87608629f1928ee5281e2ddac73926a0df961c7ced8fab1c27eda7e7cc2610f704	209	\\x00000001000001009dd953c71da349c360d42fd1446d4f453e90c304069236cbaad806737dd7967ebc32578d03e81c3eef8dc25e82de2871ad75f717556276f14a96aa12e87a95c1e9f70246a769e54a78e38dd5138a092c02f7d0cf8d0aa5f0e7edabf8f80ac8ad6bded3d9eeb013882bcbdb9910ddff5424e9918efd184600a612a5b57b98af12	\\xc2edd6b429d3dec110b6d1567f8c6c5dab88f3ddacb33ba4d708e1ad2b2849fd8702eaa1aad42189da2572e44b83913d5fbd318f8511c55a3b68756222138fcc	\\x00000001000000017b326926791aaf78e66b46ad104dd0de1f7beaac256429ab92b9bb282cd55732f381e5a4e85e171855548e82967042791675d98f246774028bb34a079add9d9ec8c54b0842e525c7d54d578a810ba0040d9ec9dd51a6093ee9a24a00532d260b2606e2c9608f6e09ed0664f729ee5e710cdba8e6d944a952fc212f2e05c60be3	\\x0000000100010000
43	4	6	\\x6ff688b11493dea3f20870c3d751e41749c931e4555b8a5c912dec3a02f028a74e172be9bd103cb87c96dd9c71642224a126f0a02f846e03d4612ac855031700	209	\\x00000001000001007a108bd25fd4c08957f4ee56a6a27039916d7b68ff76cda39c12461ce8c989730f191f3f3581b539821533520836659ab591c5620b4bbefe99f5799e32c092c724560e116c1544e9447b135c946b253a9e960fb556039acd1f1f88a29ca816e1b1877a3f3601254667ebd2931e8d4df64d92c864d3564e230cc1e72b0f5963c1	\\x76aee31b2f6b6961150d4027783c998475ee804a80f5c8272fdd170d279794403456696ae668fea1d533e17099d129370c06bb0956b3e0b6cf6f89a3dd27a0b5	\\x000000010000000188bfa8ce0399158e515530c9eab7b6782bacc089afea86c8d188c9a708b3f3086d06dbcc0e5340823edbc6fa350b138e853be5af12691d1bb70fb3c5e1293cef667596c0162cc5a775fa3e66550699e73fe5e0e51955bf2a3491a4f91775d40668dbf4462d2907aa31ffc8ae4f8e5e102dbd3d7d2f6851b93ed44f89c98ae623	\\x0000000100010000
44	4	7	\\x45ebd1b16f5bec4ccd8e25f7b54b81f585fe4b1f5fe1b79b474e9bdc5f1cf580e0cded97f20f71cb52d58ca606ff7df9934a376f3fc0885d098a255c49bbbe04	209	\\x00000001000001002bdf54b3dcdf71488636e345a8d6cdc94fdd0f312e22997288a4df8b75aae06ac7687f27d9dad39110e453241a918161ebb0e2da1cc1bc743550de99e0dcb030f4857bc611c5be212472c0664e1c8727a19d78e40765f85cb56d05895062f1a4971bff3b594e11caa0831c3d6ae07e79ade363b5a797640097d84ba70838f4fb	\\x7e4d62398f1557f79030f217d4da34119dd463118b9483d6c8d69c85b14d3a0a7f61afa318ee9fb80bbb609a74ecc40399a01e9e5ea9711d14b4594c26cccad8	\\x00000001000000010a7f0014a6405266ae4bbc509455178ee1ffafa42897032ffe82972fc20ba6851b820b59ea01599229b406761ede8552ae79f572dff5e3346e236e040abe0992db388cfd58a0a9f9824739c53d87c03d99cbb814d475a7730dcb1fc64b49db159aaeddc6337a24d7701dade8f62dc47354e299ea3490588060e62f5d2290a7d2	\\x0000000100010000
45	4	8	\\x950a58ed1b752db8c591e2b63f89a8490172b641aada050f0a459ce8166b0043411377effe7f4f4af3a0e50b13fadfad74e3235e74aa93b76f1b7bcf0762520d	209	\\x000000010000010038e982e5edd1ee2b9607e90b76b47cc566f51352730c9936d93c887338e9cfc50b60e3efff74bf9aa1b86e0ad2e7518046720f8991d1ced28faead0ea508e8bb3e18c8a7f891444afef85b76e1d5a096c599c89bd10cb1e675200279fa76332bda36540105e5b04c1deed12f2bfe94033b29a515eedc6883a01d37850ef0d85e	\\x8538524f7cd56d2c124a7a87da313040ebd2e799f683de7655af836fb1c399b44994bf365d196adf838113d4892128794f4b523743d7bdc04b5b04bdbe709335	\\x000000010000000121a99cd0d2676cce261f7fd715d821f5fdb88ce023e03ea6dee3f5eafbe59f4c289977de5477b0b2ecd0d73abc928fcc2ce8ae268bd84f9082491b0e865960e09f56ab798bafd1a70b41f7734bca71b77eb47091ce62446a1f0f0b892e2ba4fed78f4b786e5d5faa2de888988c530132fe4c3b58c90c53552ccb88a98985a72b	\\x0000000100010000
46	4	9	\\x18a450a576828fd1aba56f79e071e41f4b8e79ca9d109175460940f513abdf5e9e85cf276c297a33d9fc8418d209a0600fcd368ebea296e01d072c5eef14a707	139	\\x0000000100000100793416816d4c763d7f5f2c21e8e85db93d9f3f7c511264c997e1b5eae18acb7654094f71c6225dab67cddab22523202996422b54a9c3310aa59eac0ea483e4b1aecc8ee292e43a184318cded6ad7b9a76f8dc6c00bd7e40e2ed8fac1487b0f1894a478ce58e7c0798c615b817a82cc95202e19e727015853c9799a2a12b34e4c	\\x97dcbe9d0172b73976cfdfd25a84c1ba4e93805e50f4ab2a64ea561ca3f09ce257c96871509f2a6f1cb731ab7cae550e081790376807fa284926eb13b99a486d	\\x0000000100000001b2282c93e0c010a2ee5182008f7c417736208e5565f876e7064fb53aedb95bb0f9bddfad14256dba973f0a4c07739b47599a1fc5b9f6e4f3c65a1cb972f7830e264527938373776a452785032b68535c66454ad7fb423cf963a79e08e04b12fc82ee70b6447b1bb8b26f476faad484cdb258cf9bd59b34c23739e165a8039b4d	\\x0000000100010000
47	4	10	\\xd65b43053eb19c63232cb662747eb5793e29e1ebe119f89a9ccf07715b623d8c02803f1dfbd690b613d78b4db0976025470df13caaa84680b385b7afc474740d	139	\\x000000010000010074f79c1fcc2f0b358bbf34978112003f5528681daff1c7a939965f509bc6c0da356582a2bf44ba04dfaedfc91e4c042b459b51c5dfbe49bf0bdbba0c166325f4bfd66a22feda178a9be8a0ad0d9d9f985a1634b1941b86b538d451c04f200d6a5b075b03bfc8c52358798cd69892a7408106054c8ce796d051446f33c98c6e0f	\\x6b04a7b467902bd25d1292d6c653217cbbc16777f2b9f43cb7a4df2a0ef04190482191a4f5aa3093fb4971f0e98fe53febb28cf9a11595acd678661108f94ad6	\\x00000001000000010e79b410326566d0da4ff77aaf748760c6f3e08fc8a11c6180d6cc37d301c925794473cf626c02fee694f073fda7bad7e10522aef2c687da14adc72b545309f86b2774c162cff0c3c09b364c137a415af0623b6dd3f5f28ad4f66e66b2eb1bb35cceaa4c795ee128e07a18861876005867ff2da5bdd3dfe76af27593002a9611	\\x0000000100010000
48	4	11	\\x17a59933ee284c680dc98ecaaf8acee6339d8ba420c97078a55d0ef270e31be960cc5a96d3bf66ed6267356919229e53403068888ae3bd16c5ef97ef49dbca03	139	\\x00000001000001000af06e089f79ac4bcffe760a1e5a9b307db2fa45e97b9f8fc318042a165ab50f1e4a09e35de577ab0072844e9567916ddebf04023d66e6f1aa621838e7a61d06401406e90cd1ec8171d30d8343b4470e0b90258bd606884c58d8eec7ca571b8d0e2e806fc637dd687f9d2a5b8cfbfcda2b251d8bb0dc3b72481fe4a729e2cebb	\\x619f5d83e1271fa3ee288524da0ddc05805a9122faf163e49b884265e3904b376e990974727bb5794e75114f03c93082115d00b9ebdf58f113f13894bccc2d6d	\\x0000000100000001710fbbbe59c4433a4ade3a0d86d1f99b0fb515ae039351989f241e404b9a0f7170019c3f0590d872b062ec5f2b30decaa29cc2b02ba3bc09a7d5335e9c0464c9716b8ca036bdcbcb8f5500b1e9cf51e00344105f1453dd045685828591e42b1e96df536cfc2aaeea5c0c97fec164c9d8b50e6e732289ff7f1211781cfc074fc3	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\xb0829dfe6da3b4a018d90c6ad0b98875c1e11c0b589a407b8f5433c35cb9f242	\\x941c4dae63db1a52035810d6068bf89fc8c35cee447da64952bc4a7f83e5c6babedc399b66feea05f3d7e0429a563cecc0481ebfbb4de1a6e2171ac326e9a22a
2	2	\\x4de860899fd262ff54f6050a86ece8a94789feb0fd43ecbfa85da754491cce00	\\x7a2b02bf9f4631b5c2943ded6a4e9250e6dca3f1c74a316a2fe4ca247c08182a0df493f27e8f1dbc79c2c9f19374e5b209a6a7debc637e0d85d5af72a8c22545
3	3	\\x9196f271f2e29b7834468e5edcbafb3711d14e70030aaa8c478ca85cd295b312	\\x6b0a43eec38ad2387186592ab958ac76f1e37d90d99cde18485ed79780038a78bb3d430d6a31e76e268f93786e6bf35f1357effa3722b46977ead9860a6365f4
4	4	\\x6984d40a0ad11beace40b887012369c3feb500e23ddb02d69c8a64530572af73	\\xa6e73d17b3488d5621d8ffbb03d8e38a44dbcb566e66d7e213ebe04d7ec942ea2432b5a7163330ee7cdb80f25fe75b3ce93358cca0895b22f9ad7a1ad109b1c4
\.


--
-- Data for Name: refunds_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds_default (refund_serial_id, shard, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	1089432118	2	\\xf088985ebfafbae06d745d9bc71e26b0d4d234d1ec7547db8b345ef5f1222c6bb69c04bca6b86ef6c9a1dc5320d09923c5136104082676a259fc3aa61bf69d0a	1	6	0
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
1	\\x78afe6f657fed1a3ab8475cecc4930977339f3617c06546e20e902cc2265ebfb	0	1000000	1650631679000000	1868964482000000
2	\\x1078fad3a41a8d38ca4b4ba5a8686d53e1e59e425b530463ab263bc14feacbce	0	1000000	1650631687000000	1868964488000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\x78afe6f657fed1a3ab8475cecc4930977339f3617c06546e20e902cc2265ebfb	2	10	0	\\xbaaa78d5fec994783cceaf577c61c5825062a0e26b6a17986ae0c6057f6da6ec	exchange-account-1	1648212479000000
2	\\x1078fad3a41a8d38ca4b4ba5a8686d53e1e59e425b530463ab263bc14feacbce	4	18	0	\\xcdcfc7c3750d80510aec41f27bba7c202456c4c94553beed812f0141143c73d9	exchange-account-1	1648212487000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x61d2e17d95a5ed835989d28bbcd2862285aea0c1603d517aa39272365bd84b572dbbc0512b799011422d401f43517009b43baac05986dd79335330d4f2de0197
1	\\x322f57d5320b4a143a67b14b58b58664f80d82094c5f58e111b8bfa982d2a068ba508fe542b0bed0696c12a08de48286dd4cc34e8b56649a87248d44221853ee
1	\\x1adf491d60447d484609e9aea06c40b828f89d4bd642f99b6290d676c08dd087a3297bafb4fb81aa6fb4dd55a63a59eb0a3ad83a841c794768e719d94f159d16
1	\\x34f0eb355d8f8caeb5cf68bdf432b4844060cf27f612a5a4d81954ce88b4c9a055d7dba3a371933d7dc26d1535f6d4d97362d582ae04c1606799adba1a6ad35a
1	\\xca318c946540de0a9ffb7e89c6cb81754fa06bb780f680df1d8df9c721038a8ae45f5286803336e8203d07dd4ae5932aa760bd3024b286d8fb4a922015fd95d3
1	\\xa6606904595b4691b1670d96a8489aeec84fe0c7c1094d990adef81e7b9f2b697d3f07e59bc2a6009ba7f0974b556e3b6958b15cb951c1ae65cf09e031dd1388
1	\\x9555960fe57b2ae9619ba84ce082344da02d1dd4c96a2e5a60f133bcc5303e5bef3b1ddbfd5323bb9ddd972b0f8b6a30d2873da98a8538c0d0bc19dba0ae8eab
1	\\xfb0383785e57054f979cc2529e27a6c0a0de5d72d7585a3a44de9a12ec1c80a23919a2e0d65569ca4d46232853feb3d32b654af657ed3d6ce53f6e889b2b2708
1	\\x61554130844c4932b6e26f990a40083be641aa59d75cd7503c710aca97824a6d9a1196ff822ab81d7e62f05fec7f63fb65601234d0d7c1b3e8c8b5bedce0ec76
1	\\xe7cffb3204eb1a95a16f710b8ccca27924fa50286748cc70dc5f56cc4b4d07e132a56a684404fa33af6f68426b3028dd357edcc9544ac038e8654211d1eea757
1	\\xfdbd0d879d561c94071595ada5e7fa08b4eb746ced6bf5c34e26ab1f5b557f17da09aed4277e070f09b6fd05bf45f9caf2c7e292f369799b655f6152644c3259
1	\\xdb4680cd20247b979fbcb050bd23d3c46abd503931f2d1c2492ed64c7992e3763759575d40a58d87d80651f16b6697b3d1fe397255f895273fbb432cdc0e3a5f
2	\\xcd228885bf2a83daa77624176ef0a89ba5a73d32a78ead4100c1150471a1eeb2c868115b311c4c9fae1d798d2d9e10e0523b5f63a2d06f6370fb058c8c0feb9f
2	\\x71f62dc9b98749c10bdfb079ae76a9f8e559c2c36843c9fd26ea7e5f60725d4f4622512b5aad55ac9fed738ff9302d5ca40ae81d118355f3fabc765e30b68176
2	\\x635c57027ab139e5dffe7e279c98d1d2e9eac317e050ce2e00b11c022a2916a273cdefa36713f7377c00dc7ee87bfd0ca4074ee3002693f547a4815f11b4aecf
2	\\x58bae492c575a6406b379f1563d4355f5f9cfdcd593c440057def6d28638141bf5d34410bee4e617262cd712f2f719a893ede70409b478f5c422494f59473d8f
2	\\xcdc43f9b63a314442a24769c94a7953c6d031cab443ef896c7f84752b44019d75fe1232f97d546dfebcfcd33d972ff53b4affd255160331a7434ff6ffece8bf6
2	\\xc64ebde0d4fb1cc8053b5a40a8a820fd64a6a091c6e718b3a3134730ddf861aae7ea926d4f7bfa42b60c0a9c4648a351bfbf16b630a19d805e198b1dd7d53cd0
2	\\xe733214806ea534d1842caad123c8d29802a3e9dda3d341571fa7304f69590b05eed74842bfac244ea3de78d5ae65a248e3cbcb650eb4d5dd821003c54d4a7a0
2	\\x68ff83ed017a64fac386da5bfc8252cff33848f73b5a25f15694fe937c2ede4cfee5f22da2fa1cf8e8bce63305ae59c786b1c26beaa965459c9afd4a98dbe2d1
2	\\x474934848f9b3a477f796c17c6930c64e6c6cc7791a8532b20f275a0778d88ea146df9eafaad17278c47d3f2db53bca709077c18aa2e8b251c891c65e649409f
2	\\xfaa6d049c87c776aa7bcb79bf716c51881b014e8709693ede3ebe5568e3be9933f7bee99dd5098242b7e7f3f529981cc28677d1c38f68df0f2101920d5007ab6
2	\\x66c7b0ecdd270383c60b571e1e86ef83d45e47a1c754288b28b4ec9af40920b5e074e0f461fa1fac97e6c6a9cd6c840cd6d616f1d95368ba979bb785eb5ae814
2	\\xb122841f83f3034fac00e290e373c1e7f93799584d957ad13be0798c3fd96aa42e21070481c66f81a138970a5bbe0379d5fa7d21c8a402b7f92c1227c1f25423
2	\\x8defb91cfe157bec8085af3ab37ae425c3d337f0e3d91fa48017c9fd42896c73eed22ae9898fbcf7c350041b41fc8525aeb1aaa0622d252fc1c8ee3e38360457
2	\\x210d642789287a530e9893859b25555e16ad5b996b1dbf410d8c54b850eb272b28d5621838c5f16627e787408fb089786eb13a32c1d37a71e6c46768fd8949d4
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x61d2e17d95a5ed835989d28bbcd2862285aea0c1603d517aa39272365bd84b572dbbc0512b799011422d401f43517009b43baac05986dd79335330d4f2de0197	223	\\x000000010000000117bb0f57343876adb3c033d10c1559371d54ee811ce34ba85186622114b07444c247feba3247e833ac8f4f32bf1efdd794841b4984502ea0cd1509fa616057766da68814e22826b5ba8dd6e15c582c8c54ed81e105b8da6340356fbb005e1f753acfd2149863c97e32b304cce388762fdb918c0cdbede902ce67d34ece8b0df3	1	\\xd705154c79d96cfd8c9a9b200e2992361153b7c4f5d03f3b70ec34299995d0393a4452ed94bed5f9df7057efba939bce51d03cc706db15072114af59cab4ef02	1648212482000000	8	5000000
2	\\x322f57d5320b4a143a67b14b58b58664f80d82094c5f58e111b8bfa982d2a068ba508fe542b0bed0696c12a08de48286dd4cc34e8b56649a87248d44221853ee	66	\\x000000010000000182ec1c853f72e38357c413165f5bcc5d8f5edf6f391376090751ed2770613b84982bfa2668e4ab3bbdf1598b19c887fe71810d10ea79e4821366eca70cb37693499d56bd707310b3b419efdd018e8d5667693aacf6ddf1fa62370df18a7196f7f0245e7f7a77f58d5ffad01c66349e6d4b9ac203829d907d88d046868b2b6a27	1	\\xf9455e4d4b91f1ab6972dc317feec69f68e5c8c6763a760b2a55bd097f0730d90db61b1666aadbd614757b6c573717ddd6953db0be3bfefadca54026bf2a8d08	1648212482000000	1	2000000
3	\\x1adf491d60447d484609e9aea06c40b828f89d4bd642f99b6290d676c08dd087a3297bafb4fb81aa6fb4dd55a63a59eb0a3ad83a841c794768e719d94f159d16	209	\\x0000000100000001620346fb90b0b310343e30f14d7a18dff75623a35c1ba888128496e1fe11fc8ae6249146e77ec25dd1857c7e1fdfb49346677d1ad00a3c766fd8f98b1fe67678b8e315406de7154d295fd728f2df95d52003abe9b699a65b4a89d92ea6fa0a0b203fc637060dea84a119f50ba881f82b865157dc97388aa0c464735e45e7435a	1	\\x7d9c849b3e6a54922b4d8c071839d0d1dd8e1614ecfe226052143ee1221837813c68aa5f8367913e586728390290e209d6e85763d342affdcc1bf953fc92f50a	1648212482000000	0	11000000
4	\\x34f0eb355d8f8caeb5cf68bdf432b4844060cf27f612a5a4d81954ce88b4c9a055d7dba3a371933d7dc26d1535f6d4d97362d582ae04c1606799adba1a6ad35a	209	\\x000000010000000182e75c5c1569c9912b982d1f8498fffcfac15c13ec39f3e19b46c7a97dab7c4f8f3e0acb0da1f0a4cab73934dee7f9a30198f111f2f56a145d17bc5c69efa2b057f68afbfc0020b9f5d7711688c8601ff8320014c39d4e334c538925429919969056aa2ac6f1f1efea3580b43c9d173bf47491088746c19731f0a86aa5c7157a	1	\\x05684fdde12dee018b866a6e49e469b5b9be161b3efb48d2ac484039a7ac173357c866e78055fb7d588cbbea9e368cd7097c813ab38f2f4bd1fdd9b6e51cd00c	1648212482000000	0	11000000
5	\\xca318c946540de0a9ffb7e89c6cb81754fa06bb780f680df1d8df9c721038a8ae45f5286803336e8203d07dd4ae5932aa760bd3024b286d8fb4a922015fd95d3	209	\\x000000010000000101ee6a8e9cd33fdf6aa66d0edc7014bf1449cdfa3be0bb7a9022f11f826a137d76555ba4742f25aac40b4ccb172e1fa0b98159f3184c4d5348185fdfce7602d9cc4174691d6fb1aef88fc6eea65c1bddc15efc061dfd3d78558f9c758b77fb7d90e8ae66ed0cfeacd97d78e3944dfc4ab047f736c6310a64b724b742e0566ab7	1	\\xa7b2d30c4b4f4f748416fd1ec9021e3e04adaadd0e229bd45306a5d06fc4e34ad9b32318332ff3dc08158b7eec25f41b557f42c4aa7c6172c84902eade22680e	1648212482000000	0	11000000
6	\\xa6606904595b4691b1670d96a8489aeec84fe0c7c1094d990adef81e7b9f2b697d3f07e59bc2a6009ba7f0974b556e3b6958b15cb951c1ae65cf09e031dd1388	209	\\x0000000100000001404dc9f21d17c99edaf28b62aef6d7131b3e2b1ec0c79539f5161172c405d04cad0b9fbc49c0e154de8ac90e9cee6dd9350b2ac1c93396555d02b5b6732805fdfc9b4b85ecc12108174b07933d36e3f4b9ec6a34c4eeff5a2d4e30658b2e4f537892b09b9c7829bb21401a41c95f6bc5f2d003d9c173f9af89d1213533daf227	1	\\x87d1be8ed6b967162cbc8bb5d98ecd0467df33064808aff0b8d750b6b19bb05ed6aba0f58a660723aceb16dc4218e0274ad931471e1bf2dbc5c56a1cffde7b0f	1648212482000000	0	11000000
7	\\x9555960fe57b2ae9619ba84ce082344da02d1dd4c96a2e5a60f133bcc5303e5bef3b1ddbfd5323bb9ddd972b0f8b6a30d2873da98a8538c0d0bc19dba0ae8eab	209	\\x000000010000000117f392204e97c7820962be585066b3dcc620fecceb7b41b639895218a8e843c7305b2f85baa6bca1ab03e6a7a74cf68b5e0b83d872b41c8a6f73fdbc7c1ae9fa04ce52969ffed49a8f53c036944ec3f3a755023355a2217d1528d0bdc04a59f19d1513d96ba0cfc70c484408c93dcfe5295129d6cf8586748e212afc7aeb6e3e	1	\\xf7637bfa33a253adcf4fb16b025e53c7f9b2463df837a7ea383fa538c3401daeb1db28fd0345339c505bd6fa4e951c342d8bdf089930b022a18daf00dca4d406	1648212482000000	0	11000000
8	\\xfb0383785e57054f979cc2529e27a6c0a0de5d72d7585a3a44de9a12ec1c80a23919a2e0d65569ca4d46232853feb3d32b654af657ed3d6ce53f6e889b2b2708	209	\\x00000001000000014b66dcacd7d1f0aa2850459c84576f7e8545127cb5b4b13a976497985158e1b6f1b491ff101eb26674dab2ad2434668e7c1c8e1cab32a85ad5f513e6ae6540e50a5da89ccc002bbfe4f7cdb9c5b86bbab1befcf6037a9525822c095a7b0593130b558e4aa5667e4fdc157fba1d700dbd9900321d1d8df7206f22929e80de4e8d	1	\\x806314dc0e59da12add22022ee8dad1799d85c2126d7e9a4c9d97c5716640657ac7bd141533777d8d876d7949175c39a896bb8dd59debe2c24907fb1c0e7400c	1648212482000000	0	11000000
9	\\x61554130844c4932b6e26f990a40083be641aa59d75cd7503c710aca97824a6d9a1196ff822ab81d7e62f05fec7f63fb65601234d0d7c1b3e8c8b5bedce0ec76	209	\\x00000001000000016952682debfbc4a70d120271fa4ab643762c0a807d042813e3dd4f3265ae7884466c58482a68be938c22b842676a1ca10fddd3a0942bc25ccc14ca9f97a8ddcebaf4a5f8cd7bf4c94c99fabbd7ed9f3704a877a7275b7f89778ca7b7a17f0e2c21a5e8a02950c600186c71266ce299e195177551b695144718993b67e487dee4	1	\\x580d488dffb1a17e4a5c052c8a5b4eeef6be6f65c8b2c90d205e7f4667f5070cfabf5dd84470758a23b1b5f1011be0caea2f6e0c26b952efc95672116f47940b	1648212482000000	0	11000000
10	\\xe7cffb3204eb1a95a16f710b8ccca27924fa50286748cc70dc5f56cc4b4d07e132a56a684404fa33af6f68426b3028dd357edcc9544ac038e8654211d1eea757	209	\\x00000001000000017de4cf5589d36d3308a8e3cfd200086313a1cb444d06fb313417b2993dcdce55bf3451d689984c93f87457d1f25fe972e4cdbe49344f6bbff1c0976e6092c56e16eaf7b5820998cfac880e7c87429f6c7251c4c2b2033ddba8e150cff64c30970d8a3879e2f1aba39d1de0b8031def0445a2b208de06e6d7ddeb435cc72015c7	1	\\x15e9a56e848abd0bc1f3084dcbd74766e3499e818be5b55cccba7c607044be490cdcc9cec8a56f3c47baeabb471c9ca15f65520953ddb727916929e93bd5210c	1648212482000000	0	11000000
11	\\xfdbd0d879d561c94071595ada5e7fa08b4eb746ced6bf5c34e26ab1f5b557f17da09aed4277e070f09b6fd05bf45f9caf2c7e292f369799b655f6152644c3259	139	\\x000000010000000147568db1230dcd2d092fb020c7d872ccc6bc9a9916a28db13244da52e0202b76d2428548dab72e8ea14f46bf09e474c6b7b9ccac009ab6e0a232c4972b5a19534f6d0e99c0f9fdef077c685069921e42b0a0fda6b4eef1bc7a9ec567860feb34d0ba05015c91b87b268dcb29f24a783a7ee9daea239a1b8c7863c56d24f7dadf	1	\\x69656502be192eb88786b077b503d643bbd1ce34728f3c92fc14dee62039a285e5f879187d7dd45c23e6bae3a8bfe8977aab7d97d1619723240be917e7e72a0d	1648212482000000	0	2000000
12	\\xdb4680cd20247b979fbcb050bd23d3c46abd503931f2d1c2492ed64c7992e3763759575d40a58d87d80651f16b6697b3d1fe397255f895273fbb432cdc0e3a5f	139	\\x00000001000000016f104d3599dc939b028e9f40524d4d3fa62eb2c9085a43df6c335256340b86d4a0eae98d0f9b12f5e5a2ef38179ed6580927d6bd526977de19dcade06afce89f3b2c14c374f60227eaa39643545ffc2b2ae4db386b2c5e73b8100ed64fc952b6931adfd8a480a8d370f9ce4cf6e1dd2216a571eb19115c1ab371ce3f8e9b57f5	1	\\x5795c52f08b8c86fd139205f973c615520a2db13bbf82ab6b2606a4ab58353a443b5800a2eff3b822187963ce48b56474e5fca8d7ba7602131fe9bae0b9de802	1648212482000000	0	2000000
13	\\xcd228885bf2a83daa77624176ef0a89ba5a73d32a78ead4100c1150471a1eeb2c868115b311c4c9fae1d798d2d9e10e0523b5f63a2d06f6370fb058c8c0feb9f	17	\\x00000001000000015cf48721496746701c9694800c5b8f2abc640ee640ca6e7f57bfd7f6fa6cabb763b67930c716214fc33fa306c883976648a3ceff613912043db09e0c4cb4e6ab917df7c00df2f4e82a8c85c39a1a5de75891cc1ab00f19004fb6e03d8d56268e76e3574feead777480f09ce243b09593971f4bc0d1bb7faa6583c998ae05ef34	2	\\xde55c746df988c4e148e46e8ef28d43426797ff32a872e7e035ad55b1a6b369246e425fe507ab3b21d02d996bf9fd628ff54ea0ffc9a0ef714aa119d47e32c02	1648212488000000	10	1000000
14	\\x71f62dc9b98749c10bdfb079ae76a9f8e559c2c36843c9fd26ea7e5f60725d4f4622512b5aad55ac9fed738ff9302d5ca40ae81d118355f3fabc765e30b68176	143	\\x00000001000000018ac3ffad2a82def51da671f89ac26902fa626d8a8877fee23ad43cb0a078d7b6d85f1fe1f9b96613291ff62870593608f3364313e35ad98edf6da80b5c99b3f8f57828272564055c797b32ae523ac7b7ad0ea62d36759d0eac19d7045e3c02a040f339c6f6511802adfb17d98ee271fd75fea4d5a7efa28ac965ebf6dc360a16	2	\\xe6805b8a30c658c847bda3454f310fa271d4191770cc7f652cd28a914d92b82e0ddbb9e582d77528f0e18d51bbc15f3dd654c792a827e901cbe1ebe5b458f50d	1648212488000000	5	1000000
15	\\x635c57027ab139e5dffe7e279c98d1d2e9eac317e050ce2e00b11c022a2916a273cdefa36713f7377c00dc7ee87bfd0ca4074ee3002693f547a4815f11b4aecf	90	\\x0000000100000001c1ae4f02091ba5a17730660d04674eada2bc9e2f6edb3a522741137a191231eac7efc856fafed7f988a114b723a6625a1bc1896ca43f1bb9bc0e5c2bbddfe857094df33ff5433eb38c7b5d945b82616fca22644cd4d76c9b397c20667ef62cf39fbf9876e11df00c233a1c989961edbd6cf3dec9b9b1e6ed4c53a65545b1d605	2	\\x5bc3ebda6ace33969e035cb52af14322974aae2f62111e3812f535bff07f029cbb353d96d6b1f7825a61fd3c6f5c034aac311656b700d1265bb740bc194a8e04	1648212488000000	2	3000000
16	\\x58bae492c575a6406b379f1563d4355f5f9cfdcd593c440057def6d28638141bf5d34410bee4e617262cd712f2f719a893ede70409b478f5c422494f59473d8f	209	\\x000000010000000126c07aaad778b83e04548d5700a6a62e84eb8d5c99d8570310908d3a5de7fad185a01e896cb0027773a0c2fb2e3660a1bdacd68c84a9cdf02ba5701645d9a7c4bbb7c7c89993218f6dad8a0381b5fe32dc60429a8970d5eb6d84d4d00b470d2178dd27403708c475ed86b432ab392cc1b925a93be76cf149e1844fbb2cceb0a5	2	\\xde14227b8640ce04db4f2833b956b4455892c7e37449f8c3122ae0fcf83f881087e65ca8dbb101a79323162293946bd01c1660ae76fa6988078f640e3bd3190a	1648212488000000	0	11000000
17	\\xcdc43f9b63a314442a24769c94a7953c6d031cab443ef896c7f84752b44019d75fe1232f97d546dfebcfcd33d972ff53b4affd255160331a7434ff6ffece8bf6	209	\\x000000010000000152b91f3121f0d9e7c17e321af4d8373a4445b651ddb8f7c7a4b63bfb3b7bb798a0b73699d6f7ef883ebd853e78a06ff592abe31a1c1c8ebaa1ae98ebce254ea6cc5214faaca32f22f69056072eec2547b3a827e57747be34b89b03421e88e80769c8f291460bd1df742bb8279ec0487116e4a04c440dabb70585d81c7ba15263	2	\\x0ef6d2fc46f52b0162720f76654b797b0a9ce7308553f773a3c9d9a4ff09407f5855f4856c32d5f58fd8c08e03b5b8b402ad0536805b66bb96a5544b074af103	1648212488000000	0	11000000
18	\\xc64ebde0d4fb1cc8053b5a40a8a820fd64a6a091c6e718b3a3134730ddf861aae7ea926d4f7bfa42b60c0a9c4648a351bfbf16b630a19d805e198b1dd7d53cd0	209	\\x00000001000000017ac6a6ef78a27df7c29844220068efec0d7e6bdc0ee474c308a1e60c018403591be47e9038d245a253bcca6581341f35521ad06cb7a17c9109e9dbd7bd54775ed2eb31785672a82fdef0befa0f6fece2c09f41c299dd409fffdd685b13008ca4bd174540f5c832f77e080f722a96d9b0eb6a63dded41f873d1e0ddaa2a24f6a8	2	\\x91b82b5f2b897b480675d40608d083a684a9d66f1f4a24fd7702109f03a32b84902c4c01211b9efc66ee7e728365ba98561ddb7b1fafbc117383b152ed90d90f	1648212488000000	0	11000000
19	\\xe733214806ea534d1842caad123c8d29802a3e9dda3d341571fa7304f69590b05eed74842bfac244ea3de78d5ae65a248e3cbcb650eb4d5dd821003c54d4a7a0	209	\\x000000010000000118249360ebd4f81780202ef5e5c0b8834d5c3a79533aa1bdf028ad65cc59a8d15eea3298568936636e2465c6264949c3c9bc400a4c878d8f70b49f646c94a36e451a2a822a91206cfc208721c743f03fb3bf3c51f9d935b6a03564e487e581a551608fb6c748561861ae4355cb363cf2b0e922a4fffe1503b30d8c965a2e9346	2	\\x6f5842d0bdea5488a796f4fcbacd50c0bf9fe236950d138d5b2ed7fe42d767d1cc114cf35797dd9ccaf649a31581835e5470304831b83c9bab9e68742933c90d	1648212488000000	0	11000000
20	\\x68ff83ed017a64fac386da5bfc8252cff33848f73b5a25f15694fe937c2ede4cfee5f22da2fa1cf8e8bce63305ae59c786b1c26beaa965459c9afd4a98dbe2d1	209	\\x00000001000000019bee35f23bf328c481e6635e68b6870970bc75084b80625d367a43e2f98196d86e34713f3a169a7a0c9e87c63c59a3e9308cc2a410aefa170b4f2dd3badf05c47b3b6a62baf486613c734e14f4b1a2211fe4db06edb27ae39317b513b0a7e36cdcdb454e6cc13964a929d8847bb2e62a4e75c357119331d25d1bfe31fc22fa8c	2	\\x6cef4540b3ac3be9577165833e0340981899faecc0c7f521eabc5e141e8317b2f68af817a2a6b9d3c3c5dc3b091d3b0e2ad61838c039049f03a32eb978347d0b	1648212488000000	0	11000000
21	\\x474934848f9b3a477f796c17c6930c64e6c6cc7791a8532b20f275a0778d88ea146df9eafaad17278c47d3f2db53bca709077c18aa2e8b251c891c65e649409f	209	\\x00000001000000016395c31d6cb9be4c43e3283df0ff182334c9ed63ab82c119e4113f4c21c39670a150927dbca6d64841e8693c7b0154033db94b2d8ce15bb376db44e00de1ec2aa8e0f8b4fc55efa6c1cbd31f045713886c0016f8c3cb19a831577b20266ed66ad7f824aa8d2d310d2de2f6a5491c80b796e7c94669025a9fbe46fff2352c6696	2	\\x7c9f9156fc543c272d73a2ce688bafccdeeba41d84131172925287ddbcc92801064736d5983cb75019fc90250977f5a990635e68643ec3b53116238d90bfb402	1648212488000000	0	11000000
22	\\xfaa6d049c87c776aa7bcb79bf716c51881b014e8709693ede3ebe5568e3be9933f7bee99dd5098242b7e7f3f529981cc28677d1c38f68df0f2101920d5007ab6	209	\\x0000000100000001605f39178fee8de70e033405066f1556577d2c4f0905f5b5ec8a7f7693789f0695f255cc4010b47aba5520174168f453e640254a0081e9521c697648862434828571207f2acddbf862f20f09b487a473d7226045d50a075e7ed63110519ba242c6a17023a4e9a7e64db7a445a130c10994846b8351d9f931b5e6fa693c74a95b	2	\\xa6ee8efe2c1906f15e11becaa7c6532a22ffb06001177cdcaf4e06023bd31c755f8d58e730fcd6b56079b4808313e9904fe3511300bc62784a7b064867101700	1648212488000000	0	11000000
23	\\x66c7b0ecdd270383c60b571e1e86ef83d45e47a1c754288b28b4ec9af40920b5e074e0f461fa1fac97e6c6a9cd6c840cd6d616f1d95368ba979bb785eb5ae814	209	\\x000000010000000158bc511b9501a2db2a08e22fc8af237d5ec0821210ae49c63cc579848e1c5423884ad5dd969f73e7d1f32d7b0c841459ec8a7d6653aa264e0669a421ade72652e69644ac73100d39dd52e8b1d5d86ae8cfd51965ef54cbbeaa369a4efcbf3f669b465d5b152592dd4648c30b1e934c94fe6bc5993dc40f02bafb7fe16aefa8f3	2	\\x2b723e5b566ce5e817f7d8c4b1c94aa70686346460fecccf478e3c4a016b248f1ecd51a2a33325f6f81b3b197dfd4047e3a3c7691eeb8377388e21725c819002	1648212488000000	0	11000000
24	\\xb122841f83f3034fac00e290e373c1e7f93799584d957ad13be0798c3fd96aa42e21070481c66f81a138970a5bbe0379d5fa7d21c8a402b7f92c1227c1f25423	139	\\x00000001000000012eadf90425bf75615bf7a7c84ee560b52ed78554b523decfa05cf9d9b7364db25173c238860f3e92142fd03cceecf207c837271f46a4d760dad66e823243ed55972a213d2f41bbcefed44ff67584c77d57a4f45eeda3ef13f9e487778ff3138542333fdee8c64b5f299bc2c56fbdfab978fb9b1a39c4d25958159b97130485e6	2	\\xddfe7f2fc56d14065dec6271e9ba9e689f2babe27b3ba220ae5f12c762dc00a13212fa51b5daf3d83b84522ce5808627747542f4a9d23ad5ecdd7ee1a141250e	1648212488000000	0	2000000
25	\\x8defb91cfe157bec8085af3ab37ae425c3d337f0e3d91fa48017c9fd42896c73eed22ae9898fbcf7c350041b41fc8525aeb1aaa0622d252fc1c8ee3e38360457	139	\\x000000010000000150137b0b9df11f439476f0fa99ccc6cb38cf5c423a61979d826a8215aa0224764587f48229c2763947d6965d83711ece89559fe92f1a1af7dde8dce175236b3dcdf1a59fa5399c7a4fd4a02ec16d07051993f452b0d93cb5c521d7cee9e73365c45c6af8d6c92e46d1f932a5c5650ce21f8abaa735bbfbffab05560b2eb8d6bd	2	\\xcd12a96b9a6b922c1e110c1d25c3edda8b2d6a8468bad3f238b4467f432c8cbae175279a461eee8c176ae994b324696beb41104080a038cea22151df66047b0c	1648212488000000	0	2000000
26	\\x210d642789287a530e9893859b25555e16ad5b996b1dbf410d8c54b850eb272b28d5621838c5f16627e787408fb089786eb13a32c1d37a71e6c46768fd8949d4	139	\\x000000010000000192860b4559784914d6e5167775d983a3830bc8ef0a4af490c45adaebd5b5a4580ab88f6acb7ff0f43e22de1b0791e12286cfbcc71710c88b3cb89a86046b5325abb3504a3f4498a85ff7707176b323aa99031aadf29c63d989ba51cd7414b89bb03ac83fa8d64b932784bbb4bb32f19908d8327b724f68e75d8551ffdd58346e	2	\\x842fcd0ca39988325d858c9fbaaa912f1a6cf5904d9548b5c9823ba8245eb80cc533ceb60f20feb65107449eccb2a654e6466286f2e60586d701b65d80fff107	1648212488000000	0	2000000
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
-- Data for Name: wad_in_entries; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wad_in_entries (wad_in_entry_serial_id, wad_in_serial_id, reserve_pub, purse_pub, h_contract, purse_expiration, merge_timestamp, amount_with_fee_val, amount_with_fee_frac, wad_fee_val, wad_fee_frac, deposit_fees_val, deposit_fees_frac, reserve_sig, purse_sig) FROM stdin;
\.


--
-- Data for Name: wad_out_entries; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wad_out_entries (wad_out_entry_serial_id, wad_out_serial_id, reserve_pub, purse_pub, h_contract, purse_expiration, merge_timestamp, amount_with_fee_val, amount_with_fee_frac, wad_fee_val, wad_fee_frac, deposit_fees_val, deposit_fees_frac, reserve_sig, purse_sig) FROM stdin;
\.


--
-- Data for Name: wads_in; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wads_in (wad_in_serial_id, wad_id, origin_exchange_url, amount_val, amount_frac, arrival_time) FROM stdin;
\.


--
-- Data for Name: wads_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wads_out (wad_out_serial_id, wad_id, partner_serial_id, amount_val, amount_frac, execution_time) FROM stdin;
\.


--
-- Data for Name: wire_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_accounts (payto_uri, master_sig, is_active, last_change) FROM stdin;
payto://x-taler-bank/localhost/Exchange	\\x6b1a18a1b53ffa8633b274ab06f3940875b43e33923a3082a19f6fd06fde3399332e1b739c53d808a7d003a412e6ee0c2952fc7520b0b613fad7672ced38a705	t	1648212472000000
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
1	x-taler-bank	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\xe3ae32b719661eab2a9e8372beb06bca6d1239fb90ffea9230a1557bbfa547adc8159146404f0608cf5e9352d42ce3bc554bb553b3551df5395ad44076c2880b
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
1	\\xbaaa78d5fec994783cceaf577c61c5825062a0e26b6a17986ae0c6057f6da6ec	payto://x-taler-bank/localhost/testuser-u0z5vjs6	f	\N
2	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	payto://x-taler-bank/localhost/43	f	\N
3	\\xcdcfc7c3750d80510aec41f27bba7c202456c4c94553beed812f0141143c73d9	payto://x-taler-bank/localhost/testuser-9oufxebd	f	\N
\.


--
-- Data for Name: work_shards; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.work_shards (shard_serial_id, last_attempt, start_row, end_row, completed, job_name) FROM stdin;
1	1648212464000000	0	1024	f	wirewatch-exchange-account-1
\.


--
-- Name: account_mergers_account_merge_request_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.account_mergers_account_merge_request_serial_id_seq', 1, false);


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
-- Name: contracts_contract_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.contracts_contract_serial_id_seq', 1, false);


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
-- Name: partners_partner_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.partners_partner_serial_id_seq', 1, false);


--
-- Name: prewire_prewire_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.prewire_prewire_uuid_seq', 1, false);


--
-- Name: purse_deposits_purse_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.purse_deposits_purse_deposit_serial_id_seq', 1, false);


--
-- Name: purse_merges_purse_merge_request_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.purse_merges_purse_merge_request_serial_id_seq', 1, false);


--
-- Name: purse_requests_purse_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.purse_requests_purse_deposit_serial_id_seq', 1, false);


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
-- Name: wad_in_entries_wad_in_entry_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.wad_in_entries_wad_in_entry_serial_id_seq', 1, false);


--
-- Name: wad_out_entries_wad_out_entry_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.wad_out_entries_wad_out_entry_serial_id_seq', 1, false);


--
-- Name: wads_in_wad_in_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.wads_in_wad_in_serial_id_seq', 1, false);


--
-- Name: wads_out_wad_out_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.wads_out_wad_out_serial_id_seq', 1, false);


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
-- Name: account_mergers account_mergers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_mergers
    ADD CONSTRAINT account_mergers_pkey PRIMARY KEY (reserve_pub);


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
-- Name: close_requests close_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.close_requests
    ADD CONSTRAINT close_requests_pkey PRIMARY KEY (reserve_pub, close_timestamp);


--
-- Name: contracts contracts_contract_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT contracts_contract_serial_id_key UNIQUE (contract_serial_id);


--
-- Name: contracts contracts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT contracts_pkey PRIMARY KEY (purse_pub);


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
-- Name: deposits deposits_coin_pub_merchant_pub_h_contract_terms_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT deposits_coin_pub_merchant_pub_h_contract_terms_key UNIQUE (coin_pub, merchant_pub, h_contract_terms);


--
-- Name: deposits_default deposits_default_coin_pub_merchant_pub_h_contract_terms_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits_default
    ADD CONSTRAINT deposits_default_coin_pub_merchant_pub_h_contract_terms_key UNIQUE (coin_pub, merchant_pub, h_contract_terms);


--
-- Name: deposits_default deposits_default_deposit_serial_id_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits_default
    ADD CONSTRAINT deposits_default_deposit_serial_id_pkey PRIMARY KEY (deposit_serial_id);


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
-- Name: history_requests history_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.history_requests
    ADD CONSTRAINT history_requests_pkey PRIMARY KEY (reserve_pub, request_timestamp);


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
-- Name: partner_accounts partner_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partner_accounts
    ADD CONSTRAINT partner_accounts_pkey PRIMARY KEY (payto_uri);


--
-- Name: partners partners_partner_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partners
    ADD CONSTRAINT partners_partner_serial_id_key UNIQUE (partner_serial_id);


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
-- Name: purse_deposits purse_deposits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_deposits
    ADD CONSTRAINT purse_deposits_pkey PRIMARY KEY (purse_pub, coin_pub);


--
-- Name: purse_deposits purse_deposits_purse_deposit_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_deposits
    ADD CONSTRAINT purse_deposits_purse_deposit_serial_id_key UNIQUE (purse_deposit_serial_id);


--
-- Name: purse_merges purse_merges_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_merges
    ADD CONSTRAINT purse_merges_pkey PRIMARY KEY (purse_pub);


--
-- Name: purse_requests purse_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_requests
    ADD CONSTRAINT purse_requests_pkey PRIMARY KEY (purse_pub);


--
-- Name: purse_requests purse_requests_purse_deposit_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_requests
    ADD CONSTRAINT purse_requests_purse_deposit_serial_id_key UNIQUE (purse_deposit_serial_id);


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
-- Name: wad_in_entries wad_in_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wad_in_entries
    ADD CONSTRAINT wad_in_entries_pkey PRIMARY KEY (purse_pub);


--
-- Name: wad_in_entries wad_in_entries_wad_in_entry_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wad_in_entries
    ADD CONSTRAINT wad_in_entries_wad_in_entry_serial_id_key UNIQUE (wad_in_entry_serial_id);


--
-- Name: wad_out_entries wad_out_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wad_out_entries
    ADD CONSTRAINT wad_out_entries_pkey PRIMARY KEY (purse_pub);


--
-- Name: wad_out_entries wad_out_entries_wad_out_entry_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wad_out_entries
    ADD CONSTRAINT wad_out_entries_wad_out_entry_serial_id_key UNIQUE (wad_out_entry_serial_id);


--
-- Name: wads_in wads_in_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wads_in
    ADD CONSTRAINT wads_in_pkey PRIMARY KEY (wad_id);


--
-- Name: wads_in wads_in_wad_id_origin_exchange_url_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wads_in
    ADD CONSTRAINT wads_in_wad_id_origin_exchange_url_key UNIQUE (wad_id, origin_exchange_url);


--
-- Name: wads_in wads_in_wad_in_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wads_in
    ADD CONSTRAINT wads_in_wad_in_serial_id_key UNIQUE (wad_in_serial_id);


--
-- Name: wads_out wads_out_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wads_out
    ADD CONSTRAINT wads_out_pkey PRIMARY KEY (wad_id);


--
-- Name: wads_out wads_out_wad_out_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wads_out
    ADD CONSTRAINT wads_out_wad_out_serial_id_key UNIQUE (wad_out_serial_id);


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
-- Name: account_mergers_purse_pub; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX account_mergers_purse_pub ON public.account_mergers USING btree (purse_pub);


--
-- Name: INDEX account_mergers_purse_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.account_mergers_purse_pub IS 'needed when checking for a purse merge status';


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
-- Name: deposits_by_coin_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_by_coin_pub_index ON ONLY public.deposits USING btree (coin_pub);


--
-- Name: deposits_by_ready_main_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_by_ready_main_index ON ONLY public.deposits_by_ready USING btree (wire_deadline, shard, coin_pub);


--
-- Name: deposits_by_ready_default_wire_deadline_shard_coin_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_by_ready_default_wire_deadline_shard_coin_pub_idx ON public.deposits_by_ready_default USING btree (wire_deadline, shard, coin_pub);


--
-- Name: deposits_default_coin_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_default_coin_pub_idx ON public.deposits_default USING btree (coin_pub);


--
-- Name: deposits_deposit_by_serial_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_deposit_by_serial_id_index ON ONLY public.deposits USING btree (shard, deposit_serial_id);


--
-- Name: deposits_default_shard_deposit_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_default_shard_deposit_serial_id_idx ON public.deposits_default USING btree (shard, deposit_serial_id);


--
-- Name: deposits_for_matching_main_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_for_matching_main_index ON ONLY public.deposits_for_matching USING btree (refund_deadline, shard, coin_pub);


--
-- Name: deposits_for_matching_default_refund_deadline_shard_coin_pu_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_for_matching_default_refund_deadline_shard_coin_pu_idx ON public.deposits_for_matching_default USING btree (refund_deadline, shard, coin_pub);


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
-- Name: partner_accounts_index_by_partner_and_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX partner_accounts_index_by_partner_and_time ON public.partner_accounts USING btree (partner_serial_id, last_seen);


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
-- Name: purse_merges_reserve_pub; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX purse_merges_reserve_pub ON public.purse_merges USING btree (reserve_pub);


--
-- Name: INDEX purse_merges_reserve_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.purse_merges_reserve_pub IS 'needed in reserve history computation';


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
-- Name: wad_in_entries_reserve_pub; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wad_in_entries_reserve_pub ON public.wad_in_entries USING btree (reserve_pub);


--
-- Name: INDEX wad_in_entries_reserve_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.wad_in_entries_reserve_pub IS 'needed to compute reserve history';


--
-- Name: wad_in_entries_wad_in_serial; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wad_in_entries_wad_in_serial ON public.wad_in_entries USING btree (wad_in_serial_id);


--
-- Name: INDEX wad_in_entries_wad_in_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.wad_in_entries_wad_in_serial IS 'needed to lookup all transfers associated with a wad';


--
-- Name: wad_out_entries_index_by_wad; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wad_out_entries_index_by_wad ON public.wad_out_entries USING btree (wad_out_serial_id);


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
-- Name: deposits_by_ready_default_wire_deadline_shard_coin_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.deposits_by_ready_main_index ATTACH PARTITION public.deposits_by_ready_default_wire_deadline_shard_coin_pub_idx;


--
-- Name: deposits_default_coin_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.deposits_by_coin_pub_index ATTACH PARTITION public.deposits_default_coin_pub_idx;


--
-- Name: deposits_default_coin_pub_merchant_pub_h_contract_terms_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.deposits_coin_pub_merchant_pub_h_contract_terms_key ATTACH PARTITION public.deposits_default_coin_pub_merchant_pub_h_contract_terms_key;


--
-- Name: deposits_default_shard_deposit_serial_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.deposits_deposit_by_serial_id_index ATTACH PARTITION public.deposits_default_shard_deposit_serial_id_idx;


--
-- Name: deposits_for_matching_default_refund_deadline_shard_coin_pu_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.deposits_for_matching_main_index ATTACH PARTITION public.deposits_for_matching_default_refund_deadline_shard_coin_pu_idx;


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
-- Name: deposits deposits_on_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER deposits_on_delete AFTER DELETE ON public.deposits FOR EACH ROW EXECUTE FUNCTION public.deposits_delete_trigger();


--
-- Name: deposits deposits_on_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER deposits_on_insert AFTER INSERT ON public.deposits FOR EACH ROW EXECUTE FUNCTION public.deposits_insert_trigger();


--
-- Name: deposits deposits_on_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER deposits_on_update AFTER UPDATE ON public.deposits FOR EACH ROW EXECUTE FUNCTION public.deposits_update_trigger();


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
-- Name: close_requests close_requests_reserve_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.close_requests
    ADD CONSTRAINT close_requests_reserve_pub_fkey FOREIGN KEY (reserve_pub) REFERENCES public.reserves(reserve_pub) ON DELETE CASCADE;


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
-- Name: history_requests history_requests_reserve_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.history_requests
    ADD CONSTRAINT history_requests_reserve_pub_fkey FOREIGN KEY (reserve_pub) REFERENCES public.reserves(reserve_pub) ON DELETE CASCADE;


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
-- Name: partner_accounts partner_accounts_partner_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partner_accounts
    ADD CONSTRAINT partner_accounts_partner_serial_id_fkey FOREIGN KEY (partner_serial_id) REFERENCES public.partners(partner_serial_id) ON DELETE CASCADE;


--
-- Name: purse_deposits purse_deposits_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_deposits
    ADD CONSTRAINT purse_deposits_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub) ON DELETE CASCADE;


--
-- Name: purse_deposits purse_deposits_partner_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_deposits
    ADD CONSTRAINT purse_deposits_partner_serial_id_fkey FOREIGN KEY (partner_serial_id) REFERENCES public.partners(partner_serial_id) ON DELETE CASCADE;


--
-- Name: purse_merges purse_merges_partner_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_merges
    ADD CONSTRAINT purse_merges_partner_serial_id_fkey FOREIGN KEY (partner_serial_id) REFERENCES public.partners(partner_serial_id) ON DELETE CASCADE;


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
-- Name: wad_in_entries wad_in_entries_wad_in_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wad_in_entries
    ADD CONSTRAINT wad_in_entries_wad_in_serial_id_fkey FOREIGN KEY (wad_in_serial_id) REFERENCES public.wads_in(wad_in_serial_id) ON DELETE CASCADE;


--
-- Name: wad_out_entries wad_out_entries_wad_out_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wad_out_entries
    ADD CONSTRAINT wad_out_entries_wad_out_serial_id_fkey FOREIGN KEY (wad_out_serial_id) REFERENCES public.wads_out(wad_out_serial_id) ON DELETE CASCADE;


--
-- Name: wads_out wads_out_partner_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wads_out
    ADD CONSTRAINT wads_out_partner_serial_id_fkey FOREIGN KEY (partner_serial_id) REFERENCES public.partners(partner_serial_id) ON DELETE CASCADE;


--
-- Name: aggregation_tracking wire_out_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.aggregation_tracking
    ADD CONSTRAINT wire_out_ref FOREIGN KEY (wtid_raw) REFERENCES public.wire_out(wtid_raw) ON DELETE CASCADE DEFERRABLE;


--
-- PostgreSQL database dump complete
--

