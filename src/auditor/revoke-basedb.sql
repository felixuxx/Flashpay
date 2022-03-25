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
exchange-0001	2022-03-25 13:50:15.334778+01	grothoff	{}	{}
merchant-0001	2022-03-25 13:50:16.919573+01	grothoff	{}	{}
auditor-0001	2022-03-25 13:50:17.661998+01	grothoff	{}	{}
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
t	1	-TESTKUDOS:100	1
f	12	+TESTKUDOS:92	12
t	2	+TESTKUDOS:8	2
\.


--
-- Data for Name: app_banktransaction; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_banktransaction (id, amount, subject, date, cancelled, request_uid, credit_account_id, debit_account_id) FROM stdin;
1	TESTKUDOS:100	Joining bonus	2022-03-25 13:50:28.929272+01	f	5b8e754c-287c-47cb-b354-46c5ae844f86	12	1
2	TESTKUDOS:8	A31AXWPMZQ1HGSNT38RK10GG6SR3BRYAQNPH5ZSQVK9EM5KMBZ8G	2022-03-25 13:50:32.488033+01	f	a39b8068-d880-41ff-9736-3af3383dd834	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
b93cc405-812f-461a-97dd-e5350c1b6eb8	TESTKUDOS:8	t	t	f	A31AXWPMZQ1HGSNT38RK10GG6SR3BRYAQNPH5ZSQVK9EM5KMBZ8G	2	12
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
1	1	11	\\xff29c7c8838f4578602e0184d695a860eb5315797ef9b804c0811c3245c97d82cfb078666dd46ed1a73463014fd632ee62c753c776bd9dd1c143a9c0729b5002
2	1	277	\\x9d51eb67ea7fc44b3e55fbb72df0d7f2eb25d0346cf801231a585da595c65009a6f960bb77238ec8aaa9a01c7ccec10bc3d4b83dbce2f158970240615b273b01
3	1	321	\\x4aa0747fdcfaf9c0eec34e1b74a1ac607cb991b086e2807a09b1b94cd014c49aa7c0a38092d231778622c57a2d453d6a3beb72110a7fd9fbfcd28a454b95d50f
4	1	351	\\x21faf7c677fe35dcb7305e45bb160cf10a47faa2f76ea91e791ac21363701f5f32d2e95458e3fd59bf1f1799a05e39d7b1a8f303cfe433163d7930223eb8700c
5	1	22	\\x61fc05231e64d79c321abab5b667a6695b9fe0cb0ccb90ccfbce54e9e144683f95615672994809708a5cab08c4565d24f2457fc758283faa5a759fbc7c441305
6	1	129	\\x70bc781e942149da1e38564a5284ce6f5460c308e7c7c03fa8a9849e3a21268ea1e65b26836d527a7e600959a1b08226118d0dcc704353355f006725e9fe6e09
7	1	380	\\xab86b39ec3942c63dcbbc629b010f8e06c374e8e2bdee69bdbfa87eb4a51a31aaa00ca845d0c37a2b183cd8538f6db8057b39f3ddf46318a4bdbb63ece8baf0a
8	1	420	\\x9e3524082da90cc47f72ae89124b18febda9580b144534cf4d53af594681a2d8b132f9316e67fc8e5290891e04a77f165cc0e73e04237afaa9e1c7b0a8976c00
9	1	15	\\x98d5aa446cb712e92766b55604b64bf20772d735f5581db27141f531147ae72f012f2e45ab156749ead9a3038d39321a023db3af12012cc702af6aa371b0c901
10	1	286	\\xf218b4e522c6fc1df5edc1d57587e7649b23719b3a9820eec2b900ef7f9d717e41ac05dc044197a3a020195c9216d3e692802b4c0939ba1688ba6c02b867d007
11	1	32	\\xa8b99ba0fda3476123cf31e15b57ecf14fbc1d02022e902e7f38c12dd537e37e93ddc71a1852e4a431e046989df879855f486042f8edabda5dc3cdc2fb73d20e
12	1	170	\\x1f9a1f61fbb9a08d77ef16f0bc27147d3f86f9d57f17954a4bdae956f4450d7ba2d17040a117fe79eec49f92fd914216431b83bd00ce56e1ba9b504ff80cfb03
13	1	157	\\xf8042287ff7880d14090bacbf057b286a4a5b44a54b538b2362aa5234be6a5f4d94c92393f507f16f4caa37f56d33088d171d4baf0e595e233b39e94117c1508
14	1	207	\\x2c0ac9680707ed906f4b4c635531fa1bee94662bba881c6f07f516e94da57ad7ff87113a7ef014f681d6e8bcd4f049ac035a6f98a0650d06448a75d7d6da8e04
15	1	330	\\x4eff42a5d66de0ed65a16c63662a42462df3c6533cf1f802b0b794c2671c71f89a1801d2235e64f16252c0f6d0303a55e7021dd0e78a689d13ca84c8cab9110f
16	1	371	\\xc52239e892b83fa7989781d1104d38e39ab876cd6fac559f4054d725d79df7c7c08fb9bc993e238a3a6e78fe6e28980fbec348b148ad83ec5bfd974778ec9505
17	1	184	\\x3fa731228c02c9f4cf926000685cf94f120429020be22f6548820933f7662f887bf29fcd0a0c0556a986683390b99677d501bccd1242e66a03265320fd725603
18	1	421	\\xaff65b7edc0d097607a6d7279e44329b52942b2cfe146ba96c0f60dd3ede953ce7f314ee6646f2ff513f65c5a5fe1484b4f94946cd4cad8be6994f6a1cb44700
19	1	124	\\xa4273f4f2a07f64aa4c201836714562b760c6996f7c8aa4562090355bda77da10947bdac2c0a43c74aa4b0e9dd80674ce1a73f04355e4d2678f7314224c51300
20	1	364	\\x1a89718403724b4a700c7aec368bcb89bedb0fcd20cd127a887c2f4c72330bf33f765f96219ec32397647ab6fa0d8e2c2c97c793aeed74b39d06e8ce351db803
21	1	312	\\x91b6169fc03b0eed4e9582e53b371fee6011f45bd4a08610d7ee086a17de875ac46ce1b7e73de9af681830cead258431172d31553995bb6d3bb2012edba8aa08
22	1	322	\\x5fdedf9b0eff6e02b861f399c8e1455c052137fc1a94792407b54bf3260c5953c7285ec032bac20a2cc389e950a4c833dfe9a9763ee61053e822312d17daef0a
23	1	41	\\xb2e14582d27bec7d732cd19b0d50f9c84a945e65687be72b96890b25567f80f7e9e2df1d0af30381c672cd2e75637a6b8c91efa8c0a8c4c6bfaf6244962f1805
24	1	27	\\xc47d0ae338296f478654331db1b49cd4a1c088d03c09dfcc3a771443b695f06253ab4c09390a255d4510d7f7bcb38f84307d47f53e96b86faca65e0aee54270c
25	1	202	\\x43d07697807d820f07c872a43cb9b0ae3adfdcc23bdcdb8e596c0691daa6ab9d10923894b6e177503b486b11a3f92a638858ff112ea46c1d99b2fda93c6cb501
26	1	136	\\x02f9caaa23f7a59e33d70eb449370069aafc1afbe9c5081f237233b281c680f01969391420be27e4ac45c6e735ff7d194b333cfd7c17e89234497ad13ad41203
27	1	218	\\x6a6c45657a2a0ddd8da53bb7136483866b7a2189f5955d755402c9ea401663fac914f87ab0896dd5034f3797e62d6a14aad022ff38aee47468a6fde51243e705
28	1	116	\\xabac3343d68e26ab293d3a3cf864cebb7869ef77cc716008938ab32db9800e543d5045ae8f6eec82936e42a39b04892bbab1d0318cd6b2bf2ce7b28bcf081304
29	1	226	\\xf284c948fecc38bfd941d24426997c228bc4e6588bc1b530a3e37437194f08891f5c079bb178aa30ba0ceb09081d3441cf0c68adf832344aadcc999fa7685205
30	1	123	\\x15dc383bed9c100c5f87e3dffc7ed70f3bddc1265e6d5b95607135aba654ce33b90f83dbf4d04a7694c24a0ba1a8abcd4d2935b491bb809e05f06b63319fe60a
31	1	44	\\xd345523524effc05d2765fffd3c47730a0f052eb2b9fd798b68e251c269f38e687f1365188154bab962c3bb74d1aefcaf54b595de6cf2541ae074ed21eca3a0f
32	1	87	\\x8d451cadb71300392be8a1536245ae2230ef2b121cb8b090dfb059540f51a8ae39a0272a1f037f7343846339f045b237c4955bc9f1934c742cfe4ace981be404
33	1	298	\\xd43fe69e1d5190fe38b279f072fe69825704261ad148d9adba7140fd1ffad53b92eaaefd4bf9e252e82e4d09a4f42a74f968e44fd9b9a79d742f317e2c85c10d
34	1	301	\\xc01e8a2f4c4dcffe0b9b26f19870dadf02daaebed167fc8034641aa47d251e9f909c9ead8f5ba31e7a4be6af4fb0251db864cd57a8f005ef63297404d3feda05
35	1	373	\\xfa59815af49fe1d4bf1192f23289111a8cc00e349b672c6b6b24a0a8080b1df41e0f832a44413004897c84f80a4b6601e8b21f4008ff91f850f6a790720fee0c
36	1	175	\\x2f55eccf2b5602390393741b817ad784349c4db8fc34b5b04d788aabe87856ee35ee7020f16d40eb7cfdd7b2db2993055e60f7563713c1fbbbe5ea68a7785f09
37	1	313	\\x1e1b824e555cbdee66e39e2885b677ef3b7fce4c9f25d1129c7a9f9535d7e82e5caac31f743f0fc41d68ad19d2768ae686929cddb85f29a4447f79874933f409
38	1	329	\\x773f1e6a1a742bc4b3e2e02be4dd492fd2ac595664e313e8caaed09063a441a329ddfc5ed0700cd64338c65a3cec482ce054f730a0adef834aeefbe72a9b2707
39	1	17	\\x55b87d76974c943c54f796ac169b76b17c2c5a7de53cac4ceae7adfc891c13136f4bcd1846aaacab4405f5c0ac2470eb45bf4c616d8e342de66b376830f94b02
40	1	50	\\xe27debf7f84e099b75c217f2baf893a59287c52bb8391daeeb0e03086c43170f87d0a72f77cbb2173c4a185413b9752c7eac4b2c01daa355cccf0303a8e59c0d
41	1	396	\\x9e9ed4fb1295570ee571c2bbd85669a5d456308e9066064479c2a6ddf2368a28e68e0d7534be94a07ece9a69c855282c609da57912591810ed15f3e561f93809
42	1	414	\\x8657011da08ac642d8699c6eecf6b77c6ce72cefcc44de0a66113c1a749866a590ceb08a0af301c1d0fe52528ec80d841bd8194287fa4a20c7b982b399fba903
43	1	60	\\x8112361bcf67046082dd74047c9bb568d63d4761d14be5a629dd7e5da1bdc08582c01f8b3e53c1a35ee0052e1253f4bbac727b4ec549f18c8d5ed8b45e6af209
44	1	305	\\xc5b877c802fbc17ab2f71edfe4af356c7cd28103dca6688162ac0e7acbb092c8d1a443e5d385ac65acac0f9fd12cf2f52266164ad152aff44001917015332304
45	1	244	\\x102dd27d95f417c54d0e5f66accbedd91b8c0e0cf3c2c0025f1c81d75ef51fdec45172bc07039f393b8df4b22541592fbef05f8c2696f55c8478cbeff5f7b506
46	1	117	\\xc32ce48f125e7c537932c7292a7cbe4dbab750cadf2ffdccbd4f35e02fd6a09e425285b907da2838a46dd493358fab7f0b8f8f4b0132283f07bed06e474c7104
47	1	174	\\x435c944010f2b01ee3d3d32b3ca9a167bd6512fab533c466994d4f9c487f4ac2125db5bea59d95c74269ec2a85bcd032a5a0cc01c602e488d3843001cd494a02
48	1	168	\\x1e4126fef46e5348063f166823c7c3716da1a402e34b37c300556c92b2886f4a3b9452875383112f371ad5d983270ae6bef968f88e296293500fd7165bf4b003
49	1	268	\\xa806a72d533a92c6512f7b3ad1bb1fc28c7f3462f9df1dd4398d8d02390f278ee18c3187a5fda2d9c4730ead7f9e06be86a4f5a091bb3f02d633ea59955fd70d
50	1	300	\\xad51855e09af2373bbc0e3e4205919a925c37b98ccb97ac5883b36df3efd5d13712d3d61220fc9b672aef2106a5c35e94466b1bb6d2a4a62b749a93fc5494c0f
51	1	121	\\x8d7f46f79b40db75eafe3d765ad6e8201b86a59b5b15403d0a6cae008385025bbafc9dce6a0b8f3667e4c5182edb6405a4d6e912dd3b194194fd80377c1eb203
52	1	316	\\x937062c8cc0c5ab558bd3fd99cc94e42d6873382cb4a031950b7d3aef3997ef144ea75ccae25e2c4a941293881e4adc98aba9053aad18f0ae1cd11ddc100610b
53	1	308	\\xfe476f27ac1d0a645e8de6de1069990b110ed4807c6fccb600b63fa53a047524d346689f84f76865f79aec4f353e709e6e661536e16c28486254fc00e54a9809
54	1	229	\\xead97a128230a309d8418535d07bb4ef02c66a3937cec1dfd36b90a2347854523b8ec8dcd3b78598a85307b46ec8b1537c0d73bc07918be01b2caa28a01b6201
55	1	220	\\x1ea008c2c4bd5b62c5e3667b6caa5b4c90945b0eb3cbaa39a2d83c5f4d48158a52067c60256dbd2e61dd0602f307db8a169c37dc43eb083d7b164f5ab3ee5305
56	1	68	\\xaceba193de67f8d4b977e4e5e15c3ad80b8389b782d22e7d61cc0735a83632dc44de2c17978ce999a906d7c310e7568b5e60f76f21816c72f026749f9481ed0e
57	1	246	\\x75d888708b622590dc70c236942c1172358d02594f0e4ad669d9c1046a537f0fe93f9c6830d1ccb94702afd9b033c40f00010756eb284c657bcc30d5e1f92306
58	1	395	\\x7a929814c33fe330a80d1cab71910dc271e3c0c03c55a5466afd0ffb5928d88b9c2136bc9308b4df3afc363cf71aaf281b93ae40ecfff3e9f5f50d7c77f6540f
59	1	98	\\xe0ac55a3b71e6dc344ab6ad6737eb239b296ccfdb9e9b9fb8d4a0c9422270847b6238422104ac262af46574517f95f8373a5129d23dae797da4e31ac6f47f70f
60	1	304	\\x0823cb05969567980d71b0cae10d3d1f39f2f5dd7c7903e02b126c3ed34ca3e4b4bf0f9837025027444629680f5aa45c29cc7e32d571ce9feea6c1e32a2d9006
61	1	28	\\x903a8336dd5c96d1c82cb4818f1cce6150d4497d02d63726e693e6549e77e540b788fcb1588f435225b5638acff8636675b41d14c8d47a98cb687a92306f0604
62	1	295	\\x55915c54f26f5043773448ac3b82da07164407f7443b3a5d75f7fbd337c79443f80f422ddc6d7ebfd459abdb85480e5f57fbf04bf3c42341217d6b4fccea6d06
63	1	73	\\x6f77e6ef1ccd3003565139703910e8366e8a1dc221e9b27453b088fe4ca3638ce54dbba8425b15ebc38de918adb6b03b4957ac6e31aae02139eafb19dd083f04
64	1	240	\\x8cc1422ba9d470dee7243b17b1002d8fbc5b0b9ae729408d76259d759e7a6adee99b5115304e103e5ad97bdf2269a98bd1293ebee64c24af0837ee74051d570f
65	1	113	\\x32a57828cce13ea8533fcc40a90ab43eef355a146434bf4f431cdc4e22e1ee473e2b5a056add5362af928258c6a9cf2db5cca7708ed700cb2bb5aa8204b29200
66	1	388	\\xb138b8e0eac1923a2e9aca8e716be82724614250843bbc6b21a23b89b1bb8653239f239e96bd50cd3a4c4ccbfe8a536ffa375d369b02eb7b403e631d4714860e
67	1	29	\\x02232b3dd3041fb9e669240afdcc2458f054f4ad325da6d70883d808bc43aa5bf4c93382100f9d3a9d0b6fc5e0dea54752522e5d6123645a33a328fec4a86c07
68	1	213	\\xfade0eee87751e47ec66b1671e03a8b114cb9849377cfc0f495c01c6174e17d9cee794b3821bffc66b370e87442895811cdded1d0adedabe4ef2a643223e7208
69	1	180	\\x62d185af3720d06187042aa9e2ca050c0f53b21a42c6ac3a81d47814346f65c448ffc45fa23065917eabca9d9a547cb204edb4596702e1f69fb10a261140350d
70	1	411	\\xc9f69111e165c90ac14ead02c0334cf54a14f3ff0eb253eafda448c5ef4e747cc0fc1f5f338c65c1ef6a4e350bbe34688e11ba9c8565b9d4596017cf18e3150e
71	1	183	\\x32e3c31955e615a374b0e2a37cefdd61cbbec6144abb6268f781a5f78fe6000951795f8222b2910e2e96715c5e0d299b571484b3be1ac829a079636494cb5401
72	1	294	\\xddeb5b58633a8477a97a1633d46c8b988fdd82a3a946126fd3669c99b2ce51e21d42633b58cefc24ec40b3e7a2e4aab1a2d7b36509baaf6ec44571edc4f1ac0d
73	1	367	\\x51c1992288fcb0e9b05787075b693b94797add46526f87b94e75ea44933b9b917651a2e337bc6d2e9abf63f32153faa6f5868e6454a1772978b508fbb3eddf06
74	1	201	\\xc77c787057f1d56cb8c9dc5c54ef9ba4eb675f56039bb0368d6eec5dbe6d253e8a06376595ca4e05a5e9fd79161216fa7cb51e323faa78f92d85ce1666bc3104
75	1	303	\\x1250f038b1c4f8b09c8f44a00e7874a5ac1dcded349e30be0def2558594faf7986b7512ddf9fc424ed84f0d78324fa8db006ed8383e2197008ceadfd2e361306
76	1	387	\\x25b9e7709c79be13cf2f02ff829378903d1763f9acb3c91414c0422a6876f8fe0d19e0182c726532c50bc83cb88bf276b8f1c114db12f3d3b4521c4f52d71201
77	1	147	\\x77a207ca05f8f5dccc5d60030b21d0b7474dfaa1228d29e1386258e50a525f3510a665362d420254c0be4e9b4c5b350deeb21a64b4db14b2a35ffe84744fad00
78	1	66	\\xe80e4ef6748579325eb800b0ae24aeec8373e62f272a5b747640f65504d7edc52cd51130f7588480132985e724560a7d662181a5471d852545df4ae92fe4620a
79	1	141	\\xfebfc45d563135461da069e1a176b7df2ab9c7a9c823b12d2f19470dc026fe696763467ea5ed359c78fb6b245c322f6afd0afc3e65d6bb2fd891bcd1e905bd09
80	1	383	\\xe1237c332e4f5d3094086bfd26d28a09006fd0c0a491e5629ddbb110cc096673754ff7c811920ca62164c5ff841c8955e342fbf03386f4408d788dc604b1d50f
81	1	392	\\xf632be5b06b829610edf67c62c313d9f555826e41f5d4c19eff598e3789b789de7329a380ae0591fda84ca08254148eafd88f3dbc3442ce488230e5c21bea206
82	1	37	\\x0e296cbbf6fab04bb30ec8b3fa32f7d80842b446c613f824448e8518c3cc6edeca5199d5a716d13adba0e597614c5d0e5397d051f3312723f845730b1cc10b07
83	1	138	\\x5255e7dd74e95d51c15431905fe1ed74788b561f41e3b6430d7430fa0497452cb999a9e39bf0d2c19c1577c9201eb823e0af22913a26200cfa509600e6835c00
84	1	227	\\xb48fa62ac92bc7e9b2e5fe7f29f2a14cd06e94c67b5751803f5bd9bf7a8c1bb85bfd95476691bc290fad6b33c09f9ed05bfa3b0643f2c53d6ae1134afad7680e
85	1	267	\\x183deaf21b8c3d3113abfa4735b614c1d075c60adc09ae619cfda99e539e53fe7157dc23d2f6b3d8346c9ec16502f558b7d75f659b8f3b9da862345a83e67e01
86	1	9	\\xbfc612a7114843628382d74bd29e89b8b749faf8af03e65d906bf61ab0cd2740d3af4b9464807858a619f305b45fea5664c026c2355559752b8191cd650a750a
87	1	193	\\x129421efd9b845d8d605a883961df1b3e25413c1191a8b6b4eac8b5ceb8e3f79684ff1540fb202a91a6e93dc4f5f7d2cc3ad35d4da05053eaf06cbfda2f89c07
88	1	36	\\x2ba44ff7a8341eb313e9aa776b25a674bc081d370c8ea64d1590dba94f0b88125ce79387a68f6bbf5a5e8c8298782e5331782c8ef9d1fede555f403dfbbfdd09
89	1	57	\\xf1862f51f653238570c612f7a53b929862fe5ea8f9a0069e41188eedbe4f22bdf6fe2c4ee79b5c26f86174bc9efa92d09bc44aa06e9e8164e5ec5d8924e6a804
90	1	10	\\x5eb93de3e1a12d460825580847b9ea34cd539587ef106491d9b3bb931ab0474efb6dca06e19dcc9e357d1577ed7f5ab78c5dd7866bd0eb69a50f6f575fc2d302
91	1	187	\\x20cf0c35d7823694db78275edd8a4aac6d655f8966798c8d1bc048227a9875fc34aa35f4c460f71880c75101b5030c69303fbe30a53350a9d1fcdf1e3681c109
92	1	126	\\xaab4de06f46b3c1d09632b50266b6fe66bd1f60d11cf056030046573edf6014d42600ab6294b3356b59a7b87f625da1b14c462d8ab958ef5c45bf6d2634d4901
93	1	368	\\x9d7a0ca3d4a1130d9122b4b4c0f89bff307152779d44976f9721aaa6b04555767628a2ffe2204ca77ea06ae29cac0bcf18ccdcd312f02709edf9f6ad20615801
94	1	163	\\x3786ad1cbf1e94aef75ebaf1f5d0cf9ea25b872cc236aad4c314c1b96842d76a3cf9bd3480192f3b65ec2c119725114db93a80759b4b3dabc7a141ceb19b8004
95	1	164	\\x72905ee444ee882f4086399cb3a189eb75c96e35238032ccddad1b4e96498e869b7fc7a1f4b9b3b6b83b99323b8add4405de64dbfec1e173f27ec3ecf8d0a500
96	1	70	\\xbfcaf566bdfe48a005f9ac0491a9f7dbdd6cc6d6ca8aff23ce4d030761071247fb8248d6cd45b967794518f0cb74c1eee45ad7f34def5e65d875d9bc18e2c80b
97	1	172	\\x1c8a5871285b4d63672ea547ac963c90163c19ab3bf6930f25f6df82a0e9416dad3b3f5211e74246f9cff91cf9a0757149609d2cd932960518727a7cd4288a01
98	1	352	\\xde721525eac5fe4519201f90abb138df13d16eda7116287af24e2a7bdbc36d5b4e284356875ee549643ddf85a28653ce4ab02108654910d91b1055e3609dab0c
99	1	198	\\x2f16b722fdae3e5d6b7cfbb6fac38c357884306948720cde0fb07daf293f44656c71fe85a00ac4437d776157a70260c3d8031dbc2d0922218f7d9507b5440b0b
100	1	191	\\x2f2db9986c67b30a26efd3b804c7cd21c972608d4fce4275bcece87864033748491c88d031d205b82a2d0b02c5bfa95edf83b8fdcfe94523884711f7422b6702
101	1	210	\\x1d707c5dcebb741dd97c22a3517e041a9492f1cc81615a1ced9cbf6767642c69671a21a53d85593689f6bb39a0c50cebbd920fa65efb3c2ad275f41bc64f8d00
102	1	111	\\xe3452e667962d2985074d48186df062be957aa4bb7213d2e32362ac4eea3cf708fd86b4e23fa6a51584c8953c1d1ad88b4246f4e0bed14d7265a75f24e1c7409
103	1	97	\\x56b5cd0613f96ee5c510096b2e0caa7d1f71a85204ae7ecaec2a91e055745b8b8459ec7e27440583a7992215aafb7e6dd48b21f9facfedd68bcec89588b1a505
104	1	288	\\xf7a66978a53fb889313e9c7eb7a127ea63e57e675f9c8b300f3c36148e60585b9583be87f4010a4b3eebb97da5befbefd1e57fe322e3c852c91fc18c56c42d0a
105	1	235	\\x306911db7d652348d89dd810e702b4fca526df22526e391a3d5ddf0169709badff6df8ac5d8bd8c4109d12a1a8dd31b25401fc62bfb9e550b028cdef0c366d00
106	1	109	\\xdb8ab28207452310ac6856ba7e8c796e42c554080ffc8b318e3c15f2378928a54c683935aa4023538a869b142e4037200123e71697b9734020ed92dc0d664c0d
107	1	56	\\x384a0530ad4764a3b15008682a1db82788dad0ad6d02466590c15c3d4d6ceb515a02bf4c324172dcecf6f0badd8027a3961ffcbb737e73cebccecc3dce0b6d0d
108	1	381	\\x5ad06f2ba8813c7a517b9702f5ca506d84262bbc57d08373999a5454430c7334072f1fae514115977a883454f86edd17dc06054f0d4622e4e482fe3e0075d707
109	1	204	\\x63b30e7fdb3e06ccb677562197ffe5351be224f13839b786d450b1abec74d38d49f6d354a7b7c5c6fd67ee0de883bfa9b86d77901090bdcd353ff88af8479d0e
110	1	311	\\x6bf12824f2cfc05a0232b880e5a442363e55c9d9f13674ebfbd721831ff34de3132d28b9b956aacc3c65082f08acc83fb201262c3e06b1d5f3906f031b5e9e04
111	1	16	\\x1766246fc148b9ef546448ff8c43fe17b3f725184ce92b7fb92ba6ea6d4687547a87cc9503792de9b789ef5424b3cb6a467bbb1a0d9e44249dc536250efe1d07
112	1	155	\\x9eac4792196e4353acbb4662e4100b6b4b2fd6b5645d0590755381bbd9486ee5ada0f50b1dda9fe1b1875530bcdd9125283c1d3babaf4e16c227554905827400
113	1	54	\\xeab011732137d86d53af295e3abfeaa80c534765671ef64a903fc3be520d96d57ee7a19ab8e59fb0c74d10f47fa2820fa3f299a0af47ed2566dc97bbce9ab10a
114	1	23	\\xae969c8341628488c6386b1e69d92c3b4375b5c1fadf5ec9874808d73e70e0124b2a2f9502a09e8db131da51339d68a5d3492f99c51837a8f0e3d77245804a06
115	1	154	\\xd5a0457331aa17f11eed900289348817598c99bb08ed233b7659aef0f3c13401dd3ecd97ad2b729b70c9dbc54634333cf6cad2da75dcad00ba9e54711e903b0c
116	1	331	\\x5298773e079d443c3892c9b25aca6e8f20cad65f8bda3b37b32e8b500c0aab205304bbc2044a15557b166c8afad007db78197089a8df46b8af50c62bc88da80e
117	1	315	\\x28506ae41fbf42ebd7d65b0420a6ef4aa81841f27499421789593c49a8fed83ece697928f3a27c57731f88758635ce54d644ad30aec93748039120cbfe545e04
118	1	338	\\xbccfc6c1a352c1af1db89055df727a1920b93a7d83b0b2fc79f0bc8df2af2654078583e1a10e0cb5f94e58eaee9b284590865e411ac244e417ad488025de8d03
119	1	185	\\xaad5a7450f7af39e8f5ee755fa03d97f33103ef35f5f29b10503ca188f91868e671c0424bbc5666c9d3010480bb15ce04fcb5f4fcca67fdffe0d4272ea1b2c05
120	1	107	\\x171d832129c53083f71c49b72c1d2cc6cb917392d715ec59f33f9fd84a5cbd35befc1c5428a5804adc26dcb2b5a8339015cdb94f87058e4528ad9cca54999e01
121	1	399	\\x8992cfc33d21a79706d035d83213351463091344c18b0a24f201339e0bbaf3da934e6550ac3c4209787151fbff477d52689cbea2f44ea8075ccde1ffa4da520e
122	1	200	\\x53ed17c32d01fcc1041b045ac2a615c8f6510f530f72ffe053fe5b4629b55be8a9ef30e27c3e392870c0ee72248a63000217b38e5b4598cacf773619e37af603
123	1	255	\\xf618965abe7c8eace6c2f5b38d1ee642d5822a9f3db4cd6befd7a53054bde0d223402d3726b0c6932aa1bf4c272bb4fc37b162ac34747202557a34ae468d7201
124	1	256	\\xca3b7c0d0fdd08bd087247198a7e920631da87d4c7f3452225d26c3a53ef48cb6219101c76e0538c02bb8ca9bbcde03ab6f428e2ede1b3bf52f474c6f2682a08
125	1	153	\\xe4379e1dd99cef84185a434daa3be26de4f3f75a3f7941d0f9ec5d6c75d2b759817d35fc92aa47ac3edec4aabb902d9fb2927c2c09d156fe764382ded3696b07
126	1	167	\\x1f86d95a3c05d968361b82614a1d1a4ce87fe5158b8a74743ba3dec00e10699acd48cfd2c7c6bb0aa71afa973bb4d04012d8a8d95d0efb49bc5b8134b350e507
127	1	293	\\xb756449aeac248cf6779b0159d5a57dd85678471bff0a4795c2e0b37c7e05ebde0fca3ace259f56cf76b1e88ec0029cafffe8a9d840077f8db2839b36384cd00
128	1	398	\\x9888ae1a6b9c75b96aca4a9881802541e3b8af985b065d941f4d287f685319d9b6c433ca6f116ce55f1261cf7fbebe75f0d05d11c6e8a805a8ca2f62ac53ac0d
129	1	125	\\x315dc3e83043c90f940fb8bcd2b3a2f4f4eac78e530d586a063744169ea991230a8df4e2f774930c7f5bbc5d1b95c1e309cb3f5b685ac6de0095115f36649906
130	1	146	\\xe4807a62b1a9d6d03ade5e0123ef70834642e02184c465838f615894fbb8f431329ced997bc1ac9d38d3db389c94ec29727828b0035ce6305e54d5f2176c7f0a
131	1	42	\\xceb742986a8a5a5379710d856a9a0f5e8251a16c4166c74afea7f46f55c83196bdcbc533710b1425aa2de56212b8f1d99a987e63b22950b1b6ee714d9c8b9b0d
132	1	334	\\x3b836915d41ecae5b134902a2142ceaad61091d7111b8ef09d6de67b22255d0cb6bd830bf5f04f291d90836d8594a7429f3d9e611a067acfd0a403f3b8028209
133	1	135	\\x72607d1e57a5e8233ad3669b37c86fe063b6d14026d125f4858afea365d9837ed8965d79458e21ee65bf74bd45646642ef4ba495a66d9857d7f580b246f83506
134	1	358	\\x65f46c6ffb32adde5a34b6f68dd6df7c731ee8ae3ffac7aba4db87f2bb575c38f956ddebe0caca8e7acecc16892492b741920ddd7a8b5a8295c7da60d8dfc50e
135	1	7	\\x2f47152761ec84d6f8672052cc82247aa3c85a3f0f95c282a74fcbbb5771105312204506969091f4bbb304628c6245f3ba78c39a3504d060e3e88b877814f302
136	1	194	\\xd3884475cfa695c8851426a332db49ddc67c3956030232569855cbd0c076f28999cf7db3ece54399552a5cfdaefd6e6580184b4ca6ff1a5c5669dcdee6d5760e
137	1	158	\\x78f57b25287c9514fb5df124b754e91e25ec0abc4db6315921e498074a01eab33d566f21c253626cdf703341e11735d0879ddb7265b4fb9d36bf78f5070c2d0f
138	1	339	\\x2de2694844207cc5f43499c2d1fc66ebf75624b56acd1c579e1375b829fda0a95cf0431bcdd9997800e2947ef7b3f675441bfaa1a57283e3073425ede3b07e0c
139	1	393	\\x8adf5b3428cef33b1fb4ee1d1f65ff4e2dceef98c8dc3b96136a852606934becfc3942bed6e8827e9f15b79d8090206a0cc2b536508d06581858138472126105
140	1	360	\\xb98b21da3a17b0692b280803c8d30ea3fba22178dbcaf09fa28d3b6c4f7c7f896bfd25f831fa9f006c81f697e5593af59528b09dfcaa792c74cfe3682132f20c
141	1	366	\\x44b105d716bae5c153c9dc2248f7cba690df0b73172ee8a7beb0d0d2367164b3aa614392e02254376bb922f164a75b42327590fd47239e7db45690221dc70500
142	1	401	\\x9d980e252942f1488a92be790bf3b40656b0a8c12ac9dd090b4b9a802a74f10f9eb9eb72bf705663e6234924e2f1132c143ed0193962aaefccbc1b2cac5c5808
143	1	239	\\xfc3194a2d3ede615ce3051d85ceb6062bb21cd5500d69ffb5581dc0ef93d3b3bc5b1503eb0fb19be58b14f2ae196bd4a0e614b09a89eb6c07ee3aae24ad26508
144	1	279	\\xd6480a05ba10ec8e81e827e346931d5ad7bb00a4a25d7323ad631818aa3d337ba9695627ad4dc916f9a49cf83250cbc141c6cbd056115d8f3315de1d087c3d03
145	1	151	\\xbc93b1065848ddc45ee2a8c1ed1589ada61ae3a678e52de1e9ea97adee89e69cc05d7fd91f67a5582dc55dffb00650d095200e115d69f8c7e97fa3538af6370d
146	1	86	\\x51c0e14e76ee1895a2f602750a0c55febdc30254f36f83e89e24d78147f51eb4d99c3bf25b17e184311eadf21a71c1c918286d4033d7f6d83607fe1a585c960b
147	1	13	\\xe9c418f0c476aebf9634104b2aef19efe071f45020417a9fd3ec705faf63573f5a9445d0e804ebb4fa11c3343a55f9d1939f8ed326beb762414a4d6e0cf1440d
148	1	47	\\xc0a6ee91bfbdeea5d72b44065f9c5ac340305295172fbd6f6a9561c9790c00087f28146d125fe8a489787ff7480066f97e48f5ec481d6f30fb6ee85dae5edf0f
149	1	81	\\x450ebbf2a72030be14cd3151cdb2771b35205a41241ec13b51b0abe5940273868b592b6fb5cc42edb3f78496d97f367eebc110a91475b5059ccf10461a65dc02
150	1	216	\\x1e3901384d4c482efebd649c76ce2d8d042647450537268a087d83c4414f1120270a3e99ca6736b4c8f3e3cf4b5b85d56f3cc82bffc7f464a56e0f3349612f09
151	1	278	\\x0f00ee06a3df8e0a762c1c0ca368711da56f8ce6131d98b5011a3bb7f5ffbd81c16ebcee0d0e20e4c62d6dbdc2d98577699f84bd98502061cc192a8e22b16c0a
152	1	199	\\x45c976e76bff355588c04602f59e95c6c9e4b73ac9a846032a0e5158ad5e6bfb1ee884564db8c00310caebf0845b114bd93e0c5378d4ae469abf33d997ef0e06
153	1	402	\\x5bff0f55d5aa38a311718b576fff8c9465b81f3faef00f42f12219e4430d4ae4c5277a5db73250f89dd23a066dfaad56a7091d58571ef7c5eb63f7fdc249700b
154	1	5	\\x515c3c1dfb6f266fd66caaf4c961ba9c8fc1a0b651031226597aee80c2eef5398cfea7d13e4d209839bc95e5e40eaef90a1de5da77e0d6fd8c27d860be987e03
155	1	292	\\x961bdd1a8ba6f63849b258f2177a26885bc7365307739f68a1cab12fb062cede26a4493ddb96f0a8776a21ce63b6da7c4504b3e83fd68d0abb4792831f19e30e
156	1	223	\\x38c743eef0f04f580dc079ba673b5e32c69489828ec0e601628ec37525a2d81b982843ae6e8773a0823a26ea04872cf77e8a4e90c23e3e1b86ea4147a78f4805
157	1	342	\\xa00c10ff79bf1e66da1893d9e08293dff1dafa4738fbbefdd53dd54035eca7950847da7e7b4d738446ee9b0d53aa781dbe355710fecf40e438c6c3c5d9e41001
158	1	53	\\x394a6acc03d41059ae4e0d275e9f9e0a04a13cc0338f2898989bba3734f6d2fca96084eb0c2349f862c34e07ed284b43125b274f307543a89a26f2af716a150d
159	1	186	\\x0809d437f36698e01ee82194d897cee5e16c91e3d1ca59a503151da0b6885bb34cb0d53ce0c7edca68e3417deb32382b369e6533683cdf55d1436844af319709
160	1	289	\\x5d634070ee4ebff031dc3647975cbf368dfb3c2b431350d8851895f0c2dd436871c7e13fa1dc01cfe78990d0d529e3faf7e246c22f9b7d8cd8980a9634d7af06
161	1	83	\\x1b6f9349b0141e31cb39d8f570b55865ad04f15e7d7ee64577cd8c7da01309bf443b2ec2b01191133cfc1a839ee99ee7e8ee935783dc6e909a8d1b007a58e207
162	1	314	\\xdbfe623a317e46ab2e25716d3132a048709fe4aa6faefbf60664fcc13fa2806e1da6f131d5b8ef0aaf88297cda4ca9f83140cc3832afda247f523b6f08d9ab0b
163	1	195	\\x64d25a001fd86a688ae8de58cdd4e96035775f61f0b8a929f224157cdb5a38b72c49816dccbda669022b908cb2210bef38a499d2551985fc3722f54684728105
164	1	30	\\xc671aa9991c131da6f037965b467dd43404a02e32ad86bef0203df048757cf4b6463f2bd0d0e13c9c83ac2900c49955f14c26318c47b9ab4e2eed4281580fc08
165	1	249	\\x84ce68ab660aa61e5632dcc665e04c2e2cb190c017593cfb77a38a8e99981ef1e4a80860c486edcec553d72842f78d7b231293b22f6e21ddaa6b3f77184e1003
166	1	355	\\x4ac1e96c9221f3ff23af50f14b0d3f99034e33c24aa1eebb20d2104009b5d27ae3693ca29e6704f8e743942169abc8ad1b0077532f1e396b43c73a532595110f
167	1	325	\\x9df983a9fa8230ef7a9c8eecf4d316473ab1f36fab09a3ee1d3375ed9969a2db707c9188ef1b5b437c5f9c638ac5268ca363c91d1603090bdb22f4e82727030b
168	1	34	\\xc0f7a3cad944ae53af73a171071889eed400a644fc200f7e3492d9edd088f06694fbdcfb5a402dff43d3302bf04b41266d44be1723830145ac4f3b831110a609
169	1	156	\\x385a44e8a81a7bc59c38b84c52c5926cc36fc1cc625bbce4f309b7babaaef3e99c2b8b406a885844daaa28622ab563cfcbda97b594368fe529a2f9d1b560bf03
170	1	91	\\x5cbe3affa65152ef83e5ea3c49c67490f56d33eb4af69ba86d9229a1d2344d76c222ca6bc54594f591d5f4c20a0605626998340f215d7a33ab4387608d62e502
171	1	94	\\x6aae4b42e2badd4f4817e456541a0b648a3514d59ee0acd3f0c89f9c8dae244e93eac9ea42c8223e87c1536d0bd964731172625ed4db06583466e862e4591908
172	1	161	\\xa7f307572b241a4ba03915c4bd2e6c1675d38ad17ef6687a6f0b130e794772cfa330f372a223cbbf22e2b622c4bd7644ea4896c928a3fb9bc9cdc5e6a13bc604
173	1	173	\\x2c2a19adf50b1a056a9c9bb20c52115dfe4b3ffff2508d27f500f59ba5431f7662c8018386b759067338171ccfb7587bcf5760b5e146f593a5420a6e3deee60b
174	1	208	\\x811a190ee682ba4cee8fd9ff5f32d76e86fc560771e1f9bf72809b8a6fa74df81f1b27a5a728a19e1c9accc388fe3ab3798bf679f1f0f562f9862dac84f62f0f
175	1	197	\\x07e605fcece90dca9bb15571a6364c169f91e035a25a74a3608f2ef411803866a1311e9d70e983a306487a6b9a31983a1db4421a668facb16efff8f81c7dfe06
176	1	71	\\x80c5bc6d1846917b47f21b4b2f0af6cb123e1c6fbae2454a75b216be53d278033c9a8532126fe25c3388f25413fabadffec326a28f1e03c8d78ff75f9295d806
177	1	162	\\x6fb4224ed9886762f302ba21ae873124a605ddf2536a7e1fb886801e9f81d445c3a752c8f24876cb0954a51ba6b43051a16b6c81489dd69dbcbff5dc8390a900
178	1	149	\\xe049a8ae4832ebbb6819fa7df49f4cf109270fd3015a66c8c70805ce7406fcf927600378a166145925ab125de7369f551ddf0fe856e82d7b7c7b037aaa70e104
179	1	128	\\xb91739ed98df02b753a145d6f85b50e4b1adee9e08a9c7aa1de091b684086a1a225c3c809da33f3501dd6555184ca2cea08bd7d9683a3fd2edcf85bc6ea62402
180	1	248	\\x40e6343718ccd3f30a9c2b1cd293360f4b8a23af07dc0ecf6046b0c33f42382611ec7927eccf47dcec723397e27617bf03c121250187293d0f7636a0ed5caa05
181	1	375	\\xf45e34303f2266971b7110a75cd0ca9fe5c50cbd51518f0a1d0c0da9de5972ba90a870203dc2f0ad231e17e97bb7d6c999acd2b7a6e9d16ea3bf0971397f6b0a
182	1	363	\\x880254f89213ef024905fc517ff0500671b0af181de25c1e8e3510b6115a163aa8a5a237d0db172e2e561d9a2506255837ff842b720cccc24f5777c44a719c08
183	1	374	\\x12e4a9ed8dfbb6eec54f0a694aca34dae4a93768fbf08fd7227d23b336e21facc248e5a89b4f5c21f3d913bd3528f791b3b292a71973f996577a90c62ab27100
184	1	85	\\xd44b3020c1b8972ef747972df67b53b1f43b15ee801c4f3d2eaa106ce9727b735b67bddf4d60183ce6005dd618c6c499df7f480bbc46db465f6f4199a3e9600b
185	1	306	\\x963947c1de5df52d63d40ef92a122a819ca2a634d41a2c7d96c7baa52b9184acc878f0166345c80782fa0ba329adc7330d42a4479325c7ae1795ac6ed4a6620f
186	1	333	\\xb6b2e4233e40be587375af50b00f715e5f061b7c5ed9a6b6432518b103d7b84d7252009922d96228b337d5733e5721267cce515e5c6141f434f5e097d723c305
187	1	423	\\x34f3de4455649b65fb24b2a36bcc604b43dbaa302d8ef45f846b249d782ab267913a7e19d39b8bdcefd273b5a99ff26c623801c059a65bcb7bc528bdca641009
188	1	349	\\x953621ec6ec1c1ae34707211ef538464c372032f6bbb4977ef24594a0a655e832fb3ad37a9b44ecf46fb3afe6e0fd137ba01550a62df2933079ec1a970e8ad0e
189	1	203	\\x56e22f767979562404fa712e1b2483b9e6915d49044e478bf83dae84f17741fe02e7544e1355bf6a34d9875157419247a1c8aa293a8c7eefbf13f5f47d692808
190	1	335	\\x17d33d6ead2799c2d996e4f23b8270b70fb40d6346abb4bed638a2adf5adbc99fc56d9d8dc8d95420b5c16530e5420e867ed65ef08f332495e2bbd871e39cf07
191	1	238	\\x1f1a682651e4afe3d5147f89eae58fcfaaf7f7557ae326317b679c3c3ede8ada7a3ae6de976c4e301e836ba468443f83502ad4fc5b5b77b00783a6911bb88a0c
192	1	35	\\xba64b8bac7b2aa4c3107689be1d2227d7045638b1c5e2f22c1cfb8ef4e31e20cdb70ae681cfb7c74d6da3c247fa4a3cf90e4d9798912ab26ad0329f341b6300c
193	1	78	\\x286f838207fab116604cb1ca6296e7185e7d7d3d4585e515ab5c68efe1d2fbb6299d709013c304bb561368acae16399cfc8ab15ed5423dcfc44714c90c13f801
194	1	212	\\x8f60e69639bc9fefa2ddf39243fc0f3390e1f0b6e97bde4147ca836619ff0516c2a9a190564b143e5a7b693fac53188d000aa18edb5581dccf5551ee0343de0c
195	1	382	\\x5cba6fe85aa877506fe7876d8bb2fa0245ac490777990fb90ef0af641b6ad4e18b41f71ec23b9a6acd719959e9c3321dc2d2e2c4f3022ff7fc5c677faea05300
196	1	214	\\xb42161b2ef0d69c4d13ac298e63b6ae7c4576d6c60db7a1372cc2815cef3a65c6e3f34c212bca9ddd3dcd327616ef98ee04f0b3d17e289b2f6896d57663b2305
197	1	253	\\x13fd91eb548d9430624a68573b85d2d41559c8bac6170653b10c96b02f72387d2f0cc110970e8501ca26febedf0252589e8226ee113367b8311a65f294807707
198	1	224	\\xdfa886ed80eefc1636f9659f6a41c9326dfb3aa6d653f3a599b303ea33c5171c548985effc54135ee6a9dbff3ba0f8d87a4f705302cfe6b20d8ed6a7f385080f
199	1	115	\\x0d4244e5cbc446c909101ed545904de405912b109a8b9b30867959aea65e9359b8c10cbf0b67894cb80dab52c768efc1ca1b06df1a859ba92681499e7955da06
200	1	386	\\xdd084a6647b2861e791247c05a385c9cf66ef8ea553a43bd78ea7e69b02293105b1f2ee09a1c9de89e159696e1fde4e44c7b197c407bfbc639804ac217bb9307
201	1	385	\\xddddee62ef13c6e6b5c6777bdca6d30e9c5401972745bd5f72a9eff3f7b2963c8c38fb8f86145c9c1aa8152c5de77230a070147235078fe0614e7a857e0ca40e
202	1	40	\\x224ae32c15f20a17c2b1bf339ade743902447b080803335a5b5a0eef18345cc746414883718e11288e4174cf8001bd16e8ef0e5d59ebb457d96c9e67564ab104
203	1	258	\\x9304ab5b35aeacf336bc235a85e509459d582c51d1451c11d24b7c82750b71ee733c584b667b5e524e0ea4e17c54f46a3831db7ef4db820b9530729d1cf2b208
204	1	144	\\x7e3665243497edd2f6c240b9534b422a32f5e8eabca45db55288f5c678b99d04510c56b8a9c174a312f36a392fb82becc8c53b6356e87a539cbb309e04603f0c
205	1	265	\\x09993e60ee2bcdeccab7b7d50b42f7b733a987f16a41116ccbd7668ce6409e670b75208a35967e5225e877c21ba18d391bd2df19a16beb677bb16148987dd60e
206	1	104	\\x676cb0162735e7956a77ea19b69ac69b1046d544abd2dc6fddb82e4515355819f51a3f72c7941fb4621971e1427c9769c203d4c70179ef85076d2f9015eafa00
207	1	236	\\xa48081b7cabb8e1ebea393f791080a7f5f04237a36f1810926f78d41788d425084541a71bf6aec42dabb57ef12edf6c2c9ed8b254069a21cffb68cb69d959502
208	1	211	\\x31e0b32bc5c0de1c336b18243fdf870a95d448a38ec12a12a0fd709d3dd84604ff6cad11c651ea7308f01545dc4baaadf214ae2d7c288774dbe53eeda25bb206
209	1	3	\\xcf4dfe6d1a0c91afc7f7a25f43f17fecd996ec95b6f1c2b6d3e2b9fbd4cffbf660cae7b16e6889996e1b71785128e5d7ee6c61eb21f8a3089a3e579fb4ef6d04
210	1	409	\\xfdcfd88ba21b1f9c5a25f84c917a96e1dcd7f4318237a7e4e0c5c8e35795ff6b7dd1259b252bfa60705fe8dc89ad5f3f016e8515a57ba7693cdb07c70b4c3702
211	1	242	\\xdaa8cd90e0f36a1f6f8f1ae79aed9052bd3ea37a263baae215c5e782495bec7ef9b5fdf895c17f9861ba41765bd97a310f73b884aebaab12b04d40003b4b2c0b
212	1	260	\\xe4e44a0b7b61748103d1b25177edadc77d6587f4a6c3e8d5c6dec3f952515ee41b396e35dc8753735ca8513c139292382b67521f2d135eb61eab6761a2745000
213	1	132	\\x1deeb03e4491ccb87fe0640950f401dbdc52ea88170d0f3c49a226668df6527b47da8d7aa1c68180f5ea696486425b4076bddc991b1dff938560297b35501903
214	1	114	\\xc10c1647871b641ff812c70df8603a43c7a57f397347c343744a6608ab85714b2d7064fe8af80c4f2f91ef870d14f0d35689d6e45be3dee80f462d4f0f6eb80f
215	1	192	\\x20a0dc9fa0eea59e1c0cff97936f1edb5e060959c88ed55dc267c3855032d64f72c01473de76de83834ab1bae4c39f0bb60fa3f822a9090601dc0cba0bc95c0e
216	1	43	\\xf680302a391a55c9a92d7786cd8cb353894ccf3f7a4e3f7bfbee2abaeb99b351f098aec58615b29caef517e7cd293eabcf61b793cd3c73a2684bbf6ba7fdde02
217	1	252	\\x469fe9f823431ae0909ea997b7afd533a061e975426ec549ad21e16609cd07904961f7d32007b2b2739676d398f668fcb9125e3dbc61c2f3818de1f913535d0f
218	1	405	\\xa40c2c723caf11dda4e10e05dd3d44cf9e20df68b6559419acb0113670228e42ca6408ef306621916012bd5f5a215dfd16d0a1b8afe10b983f61633f799c5906
219	1	247	\\xd3f27ca427919bf3a91d92185bf413e189f727d8e377ef5037993c2a4a3729c3c567980ddc6a95c07890af8715319b3bbba96709f998ea526bd1bbf214b8e805
220	1	33	\\x719cfd86e15c26f09dbdfc5d64a6d0ca6ae736462b7ae2efe7b56896b7fac0dba7fa95e66b15f1c8a95d0b06be495ca4f5923a534b6303893ebdaf3dbe96eb0e
221	1	280	\\x171aca39c395f539675dcaa30557905df0347fbae146a81e75bbc72b27a7f3ad02e42fe1c8b7cb8abd5bdb73b03a6423d443ed0127ba879be52bf00acc64e809
222	1	234	\\x0a2dee1350cd5cc404dfd2f1f6cfda66e7b2cfce98eac2a182f155979888a6dbf7a21b194aaa6099b04d811c5425e303b1196e5359ce9b54cb7aef78a2930806
223	1	1	\\xdec39e8c2a2127b883c75c45ee195ddd94411edf4ec1aaa969b4d17f3bee6017ac99563bf9ccd632fdf2ff926acc9bc6f0de6af69afd963d1db6fe170fc36402
224	1	12	\\xa9ed1b5e1c57f01a4bb4baa1fc5d984d86d35081c34e2acc33838a25eba7b4c5b9e69f7bc2c9fcc57904cccc22aa00bc7a18e71f96650f54c4d9c2a9d90a4c05
225	1	74	\\xe66e40b4aaa48e7e7611693575afcff7d0bab704471d1447d7303db9c2124a4643347439c31c29f1b1c23ca3e831474638ec4f695df8199c5b78dec2a3a0550a
226	1	79	\\x310aa04d77a1596154c05303bc257aad50e6825d3e6b2a860ea65a66da7d40931ea8d00da68dccd495be900999b295eed06a704b1b54e9bea4fd90cba5457606
227	1	345	\\x00db4ecaab0adb33a0191779e180484b98228fce17b8191a95a8ba481baff97393fa35889488832829055c20252d539f0e079714773e24fde9f56d23d9b62f0b
228	1	101	\\x49f9125259fd4ceffbff09b29b311a15f7fa2d148e46fe2ff9a63484c82c4112f6e9f6736532661c8d7f19d30d78d5d7c635034c6222872b689fc1d78d82ee05
229	1	82	\\x4389d88d8e4b23d07d63c47ba4cd9daa1329b9fbdc64d2ef83cd8ec5419c32dda4bbeb388b7f3c22ec93b1cfd7deb5b1da2fdbda61fe590d56e2948b7e4ce30b
230	1	291	\\xe244c4e0f81cfeaa35d553835d2eea00aa47ddda40eedee24dfa7697dea553c5f0d27c69053fcf6383f40a77c82b59338df0dc3986d2230e4136232520097700
231	1	45	\\xc387e4b09d9694ddf627bac64d2fa10e5e3bd7466910b82aa0b2b31bf4b958e0fff951c9023c79a6945a6a7928f31d24c6a8ca99dee5272cb51a7b3faa2fd906
232	1	412	\\xb053a6804238f584a9febf9600665663c1fd80bb24dc303abc720e4a2be15df939ebc5e75249dd76041e22aca924344d676736bddcfe19affa46f73c72d2210e
233	1	250	\\x5a870c7e33b7fcab16212593e5b0b805c1244fab38312c2de689ea51afa0b23479f8edfade1ed647a7c427173a3799b315d8a608eda1753351574cf8be48b10c
234	1	100	\\x3d700092b06ed9b89bf830a3f6c12935ff11046c3135265fcf7c105410c0444778aabd7f617f2e776fe57f4063166b911ea526d5307ef889aeb8280834938a09
235	1	270	\\x51a726b36f84972a41e317120ff01422000ba57d9119205564db2db3e5bbe306789bdad9ee9103b996bc4b7bc1519b94f74424ba6a201db28b1ad93c53a66102
236	1	362	\\x6eaf448634c6625fc430e0da0f1be12434b158daa7a4a2d7adb4e9c6d7fb6a80a2f04edff972ebf730b8d04628da84d90ff69472abd8e5a218442f1f5d8d4b01
237	1	110	\\xb8bd75ef76e91b1596b80fe96927975b2c08e895a428647257b7015a402e59d96f68459cef9908b6c04d8e9ba07c85585a50a02307ff86db45a52b1c1b73ab01
238	1	415	\\x16145020564a3a261bb6b40fd90e25ed09da7b5639a8cdfbc7ae502a3f493f3ccc7cef6c52e99db5f153c5520aa40fba3e34d2793d2c625d46c54abdb431a10b
239	1	328	\\xa33560c7f2dc12b6194e6481b770fa935f22f8c16e3e5815783bfc44c85e71d422097694ee10193f45c3f62c2d22e6305c57440a55e56e67b4f58da0584ceb0a
240	1	343	\\x89269a8eaaeed1cc2d24ebf1eae8250ee5c656f385fbf68d242b4797e245c0187d1662ba105b74915613941821b31859d661fe3345ec5cca3617b645596cbd09
241	1	379	\\x4c5dcc7047e67bb53a58b16cf11eab2af645e951a883aa6c79fbd0c3354592511fe22cf3592cb0a4482767077f0b1ab321e87520ed37b4636fbdc0a713239005
242	1	176	\\xae1c55aae807921a075cfd41a678b5ffb0b98e80886fbe3478064fac4477764bff2d9fa4eb631a7b8da428c0a64a040c300d2c469363b5788ba7e41f8e87ed07
243	1	38	\\x3accb9920a8f1d954ac297090b7732f0fd4689c60d8651ab3b441df003ffafa4b1a3534b7ba1923667b4dfa714406d953d57b8a743a8806479e146b08f3dd50d
244	1	416	\\xbaa9b21775ef859f09bdb2d340d74b4b0fdd36432d969c229850f300359b198a4bd340b7ec5a2a9dd8d769b2e82283057d5c7954f7409141401db6372d9ad50a
245	1	269	\\x8bf280413b0107caeabc192015c618fb0554af4cd2774b4d0b70865c9f673aff8afd7f0636651bea6a03ac15d8cd75f0d7e6e47b47a546ad6239245c5af9b002
246	1	215	\\xb8885b51b2c04ee1ffece923dfde58b11cf6904c9cbdb4ba0323d23c528ac86ad0e32d5f16a266804c02e1ec58c006433031d665fee250c3bb4b96ee9d74e202
247	1	88	\\xf65f2f5ab7fc5d7cdf4e9dec7666c249e280d2193db72727e57a58543ce875e65d6c677e221b17f7e768f78c9409e64cc8b219483587ae6e206fc536f0353d0f
248	1	169	\\xc337caf1fec77cc3f40996dcb31409922b246b0a4d1583d147bc7c3a6954b855aefbff5115b6bc04d24ed1c45d88103dfd125d67013534b8f2947c0a5766ca05
249	1	273	\\xa479781ad310e0d7fdeb1de9c8a058432ee7380bef03ca57994e3b6eda0710fbe176fe698b6dc5b66c3a8a4c95ff4e2a73bf2920f9f22b97089533fae466db01
250	1	221	\\xfbefcb196dcbf1c54fc28c6a820b167ab9c4ad85c66fae3c6859d18d15b6ba2a8621bc74771d41960adcf2ea7616629407e61e8894d05615d8dc56f39771300f
251	1	372	\\xa16aad3b800521f13e0c1fecad49f3cccd5822f7d3387fe3cdf33ae404b685d9cca8a21ad7ebf808e53234d710394d2dd1859b40f4f44614bf7a55099c0c2700
252	1	299	\\xa69aa2de120754ffa48475995d2a18a385b975bab04c0adedf681ad6c393cd012ce72cebd6400741e6a2f2700d51f82ef342eba756c1fc47a6b70e9cb68b3c0b
253	1	413	\\xcbfc9c7381a660c78e99f730e2de12e5d371d5d4f73f8cdbf036593276fd7b752a966adab9f0cd305f50626e79f06e5c13e82f6bd99ea62f5b7c7ed4e0c2430a
254	1	336	\\x1a4b3272102bee41fe3859764831ffd471a3538ca0c1542271025a7d01956cc448d8a47baac3d82cfaceec9992dd55a56c7b04e70624ddcecd25a1f0b3dbdb04
255	1	324	\\xb7aad629a15b5974bc7dc25869b49a044b209101191510ca2e0cb8a9a773a522390e213a13e556cece697137706469a241a49ffdb9d7aa73c6b60032233a8001
256	1	326	\\xa5cb0144ab340b9171402b14acebe23c2009cedca4f1978549c85b5116b53dc26c4338f8324ff78788692a6f4acee0643f0c753633ae1782b46397e74f6cd60c
257	1	112	\\xc0b872d84971ed7bc434bbdd4b32f95d2bc76349469855270052abb45081b86c5937d7168de2537031a4a5beebb41cbfd6ef30c0094b6ad3e02b72b569199b04
258	1	259	\\xfe5696264862b1f0d112209d211b3666526cb0f6eb678b13bcf47bc2b6bbc75eea97ff29e82411bc36b857dacd095f4dcae3dd1eb2ebbd5080393d535b484607
259	1	418	\\x9079f77d1c3a61dfc1f0bf97465300789d1f53a776c9f7d69f1e6e05e7897dd11726160ac1ab3e8f926776f4de8e59c09333d686594584c4376027924e9bf70e
260	1	251	\\x23aebc00f644cc27d7decdaa870ab039ddc6708e3be5778951d4d76f0d89643f17474b8eb9b5ce858f0e14cb46ac583b00c944eeba7d7df4d783429c8340ab0d
261	1	403	\\x41f14130471f4dca252092b49a467ac7a707618d4f379460d68b0b7835511aff5f5cf9fb5cfa8637b4df924480eb2f5bf515e47ae046911bf427f1971f86cf03
262	1	359	\\x4f4f4996ce234ad85a62edf9fb0760ea4cf79f49db4f1b6c5378573428190d2a033be018d4737bf184d638b794d23da3e33e94ede3253d0ab5acd727c1239b06
263	1	142	\\xec73e646afa2e8c9291ed3e8099d729bb639cb908896b4444ee7a3f9087f9c2cc54ce2ea1ce7785514460ce760cdd9fc93c3ab1d9146660c69e0b7c0daa1f40d
264	1	92	\\x534fc14e1403a580782795f147625f8b54d3e130020c8c4617c1c821e61b11c17dcc955e625e39b948992c2dc161af1dc3d97f61ad4c221758814ca1547ae607
265	1	348	\\x5759473ea5d55b8c7d9a43e09b9a5dea9dfc0064ef3cf35cbdad85531adf5853241f8a9ea11cef8d9ae24333571ecd129e9ff8595c0145cc0e21805e2d315c0b
266	1	14	\\x99f04bb53a88a27f757618d3a3a6ee8007d3e986c50bc0d0e6dc0b7db3018ec41d7e5c1d2765d711b222a1a5b1714f14d549d3d1d90f30a65f2f0a3717902b06
267	1	75	\\x462d9c5f1a4b5857780e3cb12f5fbbcad51b2ee360b3b36266dc8fb93291b8de510553086413672a94889995a3524fc9e11426c8999b9cd6b084b478da298e0c
268	1	323	\\x11e56a3c8137485ddc1bdcd4a196e9b437e30ba1a4dd68e94c10fb78b2d9e20813ef38ed34929a5179f3b06613972b4bf2d4181a34fab3006edb917d4b2b6708
269	1	282	\\x6a89c28d9dff5c9ed7edee0914d0a5153e4a01468af4289a14580e44237eeeee56bc1c55fbc65f96f3e4e6fb2ad5f8c29169eb7956d724275c8030c2fa02e20c
270	1	103	\\x5c1c0287b1367b2cd190ca97c3516a2cd8817e1db9673db90d5bf2890ced9b4d496cdd13c4dae52fa23a151060cfc999de6512911bdd5d85c739423bd2a5e70a
271	1	179	\\x12c7518640331073ac2dbb130a06370fa5ca43564908f0360638cbf4774a654d77898afd664384c279cf4794c77c117dde91cbd7bc418f5a15db799778d8f207
272	1	65	\\x73b17de982d3f0f3f25fbbd6ac0cc0928fef7d18ba7102c57e956f6f6c8f4844e93226573b562bf96a7a2ac20b042dbdeb1301c21194eb555520acb8f37df403
273	1	384	\\x7be1f9a46f058f4e75a50af3139c46a499995516cd6c9e697d28389e2daa2a386e1f99960d97f6da6cd78591dc63fcf6b8dee439274c583796e943a96ef98f0d
274	1	18	\\xc26354d90eae07ca4dc95d7940c5966952d47252033367b06ec05c04bda5ef1ac4eae22f5f36b078b71b8268c5ea1e44e2b73496dfd661f3727da9297fb6f505
275	1	302	\\x4c4ee53d8597c48ec83e02d4ea35d9a8801a795de4343eb87a6693de911627b914cb4c14227b5c5d6f113b28fe13f8dac1318bf9164ca09869ab48b91e1c4004
276	1	150	\\xaf3cb19ae955677505a32d735b6777d3f808f64d180d5452d24ab94bda0a0b6f0a9293c15567c08781c614e93e29391c7c830ba8e2edb201b19ad35d21820401
277	1	76	\\x347f8b8445c374bbc39d755e54bde3cca0f4346ec686abb330a9277f64091957e72df69cabd1a19c651d7da38ea719e889f6414ace95de88c3e3bb1f37d6ba0c
278	1	276	\\x5c531a560cc399a804360c55a702c5cd0a8c63f9a9149053129c5f9c1c527f92f7ecc263e0cbbeb498cf5d2881e46570a796f34a020c3fd87eb78d9e2f0ef30f
279	1	95	\\xdd571d921a2af503c38604fd82ecdd4aae1b8486dafaa4d95980822e8731ee3b257ff4c355a8576347897db564b47e34de5bafd385b167b8c739509b5bca0703
280	1	8	\\x7638273cad9093709de6e8cc2600a5f4372c380b8b1cba9f95cde8ca9748cbeb3726a168049d396103dd15844942bc8fbfb1c59816abe258e0b981286b02d706
281	1	309	\\x18a584a7e32ef08fcfbfda8ae555b2d001e622cc2361682e1b2d723a4df0b7dd6ac83f8a284d6e8120d8c9fd10c04160f353ae81711b82a908b89bbca1cacd0c
282	1	133	\\xa9ff1d8c0c49e25cd6a9f3e85a53d89b609b62977b0f83300e3824fec469c9608fb5b8b6ef23ae2cd4bca20b1fa37721508ec7b7110f8e84cd4164786df83d0c
283	1	233	\\x422cd3a35cdfb14a2e40c34f2ce1b217933d8cb7f46e883f38c674ebc8cbfee682cb6dbe0258c27661e9ef7eda5ae13effaba3b28cbf18aa6494476021670706
284	1	171	\\xfb8247382ba84d585f0fa628a5881fba893ed9c96abe358581d7c4613e990d4960461f1d80585c7669f851fd36ff2c4a4e7710c11a027e769e272f4d1dcf4007
285	1	205	\\x109e60638c40cb480d286fd9c0113645593a6c85d92dcd696e4ca192f55c6476ebdb3a26e348d42c81a5b17a0f65e475be9f8ba03147e60939e09b334737b50c
286	1	137	\\xff831a1f99c773de629ec5bd224f60563c3c8f5c820ff6cbfa2c8b28c3f97eeb0aa6ccef6006f6fc4f14ec3341ca555fd4642ac79f997cf4096d04afba690702
287	1	350	\\xc0f3f3f1d17321d3d451e7aeb40880dde5f3a21c672f49f43c9fe1cb655064ed57f1b9669c1b99ef469866aca7b47b3fe3bca9b465522a16a33927211dd23a03
288	1	272	\\x9068db6891a06966c9d3e3497127f8e994faeca5395338aa1086f8df3c06615b5ce6f47f3e4e0d5df0c4e44315c72ed261dacf4b806df441344f61d0bb1d1604
289	1	357	\\x19231f3afb582b091127a42a82aea9fe7f729f92798796473ba442b3dc4d3f47485b0c51ad97ac117e696d8535659ca5ec5ef70d0379ab075c08c15427d06d04
290	1	48	\\x7669534fb0bb29d9480e347104e35929be835e667e3d53c625959ed98e00321ad5bd17eefefa619b15fb92e876467026eb371047afac8865879d875c3333230a
291	1	120	\\x4c8c72263697594c7c055203d0397483b94e01b67381c016f2f4013f2733544e28476977f9d3fb1519f0d41df939fd3691e3c27629ccffd47f301782b9329901
292	1	96	\\xacf40c0a7daa690405c66efc7bf79081741fec904e95368bc19c7c6b47ee5b89f6c95239c27bca4541c2570a44801bdbf6df06c8faa1bf3579355cdf34e1330e
293	1	232	\\xf50755ec11089e10de1189685dfbcc46dd9f19cb882301f9827b72b0a90e97044e4ed11dcd2208c08e2096fe78d666977a3354f0458aecd56a1559b1a6c89504
294	1	90	\\xce4aa50840edc4e9337f04ad1025dfa58efb80bfd1b7e11869d8d3de18ce4a3af533f70abaf423890876736f01459efe9a7f9731ac7d4a64dd9f4257de62f406
295	1	134	\\xe5d5cc8c3c256f3372c7d2f5142b0ccc90b8d83e8bc35117327b3f9c8b807db1fc3fe851c82e7674302036a4efdffa3bdb3270caf92f3076a8e819729af2240f
296	1	84	\\x900916b1596adfe2ccce4944754ab29180968454384796406dc44c5a2735714f6abfee46baf8f8da32fe767fe3c7bd71a07b17636f641c5ab2b44311b09be608
297	1	318	\\x87eac159bdf7b5f75d2cd88d90fa6a7b56fb5ce468a3249fe1918da43388e50bc1a1ecf03f97ccec4cbe7317366f79973fd650d29249d2e29a1ef74cb803fb09
298	1	262	\\x43cc575e7d5f954199c5d0597c823156ae6278ff1d0c953f640da5af72226f40717ba8731a33169b81e197c2a322112d471a4b2b6d55887f0f9958c8e3f96a07
299	1	159	\\x4dae6ca5513d233cb7002cd2020685b5efd3ef42a3fd8fb4a319e4193bfa9841232cdf3f5b97cfa1087807535db8d483ba22ecaa358d872edd148f7aa7ff5104
300	1	370	\\x211fb12edb9128134098931ddf467c12fe867f51a73dc32a4bf039c99e4adce4e81adaf73ee8ff3fed194e9d2c0f8ab56d47967a9c73e0c79a9fc53fd801c900
301	1	231	\\x6558ad390d41cd5415e9b59f25b0aaf1017db7da38a9b925cd06e9518c473e5ec272d3dba23f7a0f6b2bde5d21bece92a2b763486751f47035f8b3775c6a3809
302	1	241	\\xa9874334f580c6bc6a6476f0abb5f7e8f706c1c5f05ae1b48e0047c5ff1459eba625b5d1ee24d2365fb2a76d8dc71997e63ac870cacfa0d9507db8b9dde39002
303	1	389	\\x7993bc6425c559673ed7a74f386519ff1f54b71a72f10f0e072472534189638c0175651dabd5dc17333d938b905ee4b6dfa98f028eea90aec7b33508a31d9d0e
304	1	296	\\xb658143c096d90b00883b7b943f6a0f4db2edaf9c7d017c4f23e144ce184c84efc0c06021da3e98de3a18cd3edc66f575d1182c0e307d31db89f39dbc287ea0c
305	1	390	\\xdea372ca2cafc668fe05e96c975ebddabf4cdb3edb7d0eaceeed7c877ec785ffc0577a4407f343602cadf546c9de2b15737c7f4ea763d91d2015b9787ac30b06
306	1	319	\\xd4359ea2726873cbe9d39f4263169c1ce638ed79c40e870d36b25660734eb069281b6340e706744d700babfab8d4ccaee0d93463c6e81355fea6ca0269425209
307	1	340	\\xa31fc966d23fd9d182887c43e837e572cfccbc79dd0c1968bd0d77c76755ab179a15d5b51c276789045856c1f9af5f70ed1dea918f5ab5745aa315e400bff104
308	1	410	\\xaeff938291a0237f7a7470ad7a6a74ee1446cbcc4d75b2c94ecb2881b7c848fb36ad9856ca693bfe844ac7ed61b41e4fb5106c688bcaff39a10823fbd1032400
309	1	419	\\x4eb1f4846908f8d233546953f9ee69dcf5c6b38a93188535505f47cf9bd93a524ffe1fd91af807b55deaa7737c3c43685288759b2be03c0bd696c5676b5d2c08
310	1	341	\\xf34010400435d64ab9514e6fe249acb6f7245ab4958aa04eda80b1af5ed16eff57b8b6d33feafb044e183a9793f85426b530c8725d5a6bcc1b99b9666dbfc204
311	1	346	\\x3be969014b15d0f6bed4165e70f31ad841ab95b3339acaf5e28bd1fbcfb7546f552f1605232005f6d6ba0452b6801c7ecaf44cf7709da5950ffcebc797f65e0d
312	1	119	\\xc6e49f76d3735360f1602634022ea451eca0c8aaf936d4a8d908cbcfe8d06ed42fbb218a71f1c3fa7d140657725d12243239b743af20991f900297c0fda9e202
313	1	26	\\xed9387353a4c7db5f0f0a775cbf2124fff87bf052617680ceeb65bcc3a1fd66e3a26f1c019efeda4acee3d9089a8f9205a7d29c24804e3673666af30d63c2f02
314	1	408	\\x9b8997f59950866f052976662262705547f2985daa4cebd31f9855b65081ebb05a1f6532a826429f7ef62cf285449e7ffe94c7e677cb0406bb66e7149a095e05
315	1	59	\\x16bd0044a941a48ae9e3413a6c332d075730ad4c706d15022efd76e013fa1ff2e68097d4735c3886dfdb20e18581e622646173395dbe2bde4aa566ba558d7900
316	1	284	\\xf30eb89a9d29f10cf81cf7b56e12467cebe5a4bc02986a18b630941c07b7838a1887e279006219f26922537fe4dfb955efb46265e5385689f030daec01ab2301
317	1	317	\\xe1bf685b9466a540a46a1fd4bfb24cbc5c37a823f0c249074a8a9dde5c82ee9c784c9d5b0d8f494ff5f89f9303adc11b95ff0dfb6407eb1c7751b4a51053a500
318	1	407	\\x2acd463be60ec92c00b8d02c743cfb5329cb58b37d306f9fbe2a2c333bd0ef5bf264017d3592eedb4c03a53a9e595f6eb56c6663f02ad7803bc42a51cf7c3503
319	1	2	\\x72ab96aea3ad0c913b6b6e357d94f08d96d7497d53ab41316525cfec332e9b1abd5349f10494a3d42ed527bf7b87b4b7abeef73435e8dd077251f47fc1107400
320	1	206	\\x01c8741cbbfea3ec30f27cffb21688d7061a452f43e28e62160d60c757ffc7345c3bff6dea90827a23bf0c3cd45527647a984d166173d1f72520f3ad5737920f
321	1	376	\\x555ba9fa299d2ce9a704a6682b2b9acc7ec47c1b120ed03db61f926ff1eb0aab1583af3a23795868bbdf1f4a235e0bd6c70202ea7a79c18951951957e7ecb40d
322	1	89	\\x574f2a8a8642411ebca586d143790ecf2ec307974c1458e0125f483e2489e580410bed3af6302dad49c98c2d78e38c76fd43226bfed8955816b77773704ad901
323	1	400	\\xa3e3d86110026d4e652c10fe058f3f19ca77638ca5974e48829455fdf022a13bf262770cbc3adffb989355511facdf7f3f260996dd5e9147ee9e6ef89106b407
324	1	283	\\xa8c161e8de47acc63d10fd9dc3c7e8652cad80b2fc95778b017ce22d96627ff3f829be05cdd6ec6c63391b7585e8a0b2bf357ac10bb50204f22a196753df3f03
325	1	188	\\x2f6a7834ce96c2d4d4ba68be8194f80187310d4daa45b5e109468f28416fbdcacf6dda37d50e8909b96cb5d8457cd5e562bc4134618f7c35da3a9133ce615206
326	1	354	\\x21a24e5b7b704d73bf70e414684ea8f11ad5a518b6ef40ec73e44d9203b225692ccfda8e2115eb7b250076b25bb526c91e099cebe4c701b101d14b71f271d309
327	1	148	\\x74de64a18f65a146731dc68c057eb5d46ca12e6af3153a3d472147e777e48bf141b36e22d3a0a2f37d40dd455bd5cc51969d63b40b91acab12226cbd1088c50d
328	1	181	\\x2e769a635d64674757145606db8bf3fc4ffa8d6189d44aa6ff58ef2676280937773c3c9148072886ba5e8241fd0a97fa3920bcaf06656bb68911abe63ee00305
329	1	160	\\x5ef1c8d974ff2bed27778620c7a415fb72c3f91ee012daa99287559d1c7004121a7403acc9045ead2907b9b970142ee297b5e51d6dfe7a5e8d8d020fe9eef000
330	1	105	\\x7f6ec558a6bba4cc226032d6bd64f75693aea07e3dcd9ab16093fc0b8fdffc94fa93e4905926293c17d0a9e3bdc7a76d97c9cca88288dab55113cdd34a52a30d
331	1	52	\\xe83c6037b0b291f9e15d68efb672d966c18e652975257a9b49f1b29075cdf9eae69f2e52e8ca2ae64784a1944d44a27d80c379eee2b115ae2578475716a0f603
332	1	51	\\x8b07f7b4ed45070fd75eb461593fd3c46659cc0384d7225d724cee821e36984f5bbf521afe74a672a6c35d34a82bf328cfa2aef8a7d87946641cc867c6a91d03
333	1	243	\\x1e0a119256b4c82e768d32941c37921a848018d7f3fe69e2c66fa76d302a44cd3d7f4c1ddde24ed742a934a10bcacd3a8e30d2959a03b8ed7a72fdd782707201
334	1	20	\\x3cb0750db4821a15151f1252d3f38335293a2245abab6c537868c68b4ef3b59188a9d7d3851b5d2ffdedca0913e8cd575b81eae6c84862f2787b884a02f1b907
335	1	177	\\xb205f6c61bd7be7fc501070ab93eba903d512d1fcb0c1367a6b834fce6fbbf0f5b39c4f010f60682e8f7ca11207e9bdebcfafa33aa2573ea147c362e660f7a07
336	1	80	\\x9fc592479adf8034b30435ed69699837f800a2af55600a26c9f1c4712c8e4d018f21252f1e7a921bd5709503f750fa2d0b5b97cc0d82e6918ddd6ff86af50501
337	1	424	\\x51d20252ea4bab88ec991223cab9f1c71b2f944c8db8daf1e80014c8e8a7eeb96bb12a255fcdf5af98518f238673361914e213c6079d8b22ccd86a2ebe778d06
338	1	178	\\x308be5f4d4db9e43aafea50905794b1f10a5608da802213e5af4b9854ead22c49cf76b553b958e7faea6b042c4b1f0d3585c5a3af95cb0ee716465a70856980f
339	1	4	\\x2e5fcd1e6e5f8040de559d4c8942a14737b4d65e5eb8181e0f2d50725a1b44205508f638a9102bac838e90f47979ba93173bcba1a9f6baec596f40d28662200f
340	1	222	\\xa15b52894df4918ac636735fef2d740770e1a154676325e8273f2dedf09d9c8803a9cc58e25a7304d89eddbcfaa927cee8838de0ced200b8066f045e702d4104
341	1	263	\\x85fc269981d7f351c71961567648a6fb9e110aad47a0d36ac1a08fb383222da16d25927cdd863781ff8abfd38d1052b0088a2ed643b970b112e56c4d7876260e
342	1	145	\\x502d591162b95be05ecdb4ef5ecc7f7e0c244574e902a2dceacbdc96d91102c35547f59e184f9e45c70b846156e33c208b26c08d46d473863d98d21044059402
343	1	108	\\x1d4c7f5941ff2acc70cd58603dfefc8f02754beaf4f41330c26ef45cc15e90cee0b336e3754c3f11b809326824e0bce5b94c9d07cc3b9e996fc87e0576dda806
344	1	139	\\x1ac926b61c06ebdb9dd04d3b34ffdd5ebc90be34850dc68ceddd70dc54b16027d882564e3bdfbf41e2638fbda9463280c479104e709b34d8ffda4d46d7396301
345	1	356	\\xd359410751f989e3918c9ed7080069cd1b4f669e6da21931a33252fff4d08793bcac1a817d17a5d00b20af652544232f0264abc7304bd39ef77633a92f77150b
346	1	377	\\xac3dc6b4aa2daa9a5bdc78098d9729ec8d64a9f63396402c0a65674ad8cd51d9024b3bc0e48a329ccbea9ab72f0583ce9c3b55bf593adf32e1eab1b5353f3c0a
347	1	196	\\x5e58c0fdb650045b40d21893b603e98593b7e6a3f3ceb0d91a9b3fea70af775d34be4c061864f6a1b3c2ac508fb090e092f12e8cd68b3e0e23f6c0564642490b
348	1	46	\\x95999c8df6ae8eaeadd3a252e46a6459c897fb74a340bb2e6d1284441de2a92aecf084f28f1162f31eee408129036c911fdbf5fac9235c0b405623d306c14503
349	1	182	\\x45495893e21811b1ac362c44291723cab2fefd3ec0173f84fe75f9928ba91629b721ca310a4b97ba7345fcdd6921db603845734a9710f75de364371e76d5de03
350	1	106	\\x33edbe9f8ae149e5fdd5723069d35b9246586996a6ae833facec94da2ddff83d4a5e01be54c3e38d7d9edd4a03edd10f6c9fe0908dc711eff48259fa04557304
351	1	310	\\x05010766151bf7817c93370610b7337abbb05b2fb3209e080127e2838e20a3b6c54eef14972364f374e574b31f54b9c74540370f3d94c5a8fa617d6849fcf304
352	1	365	\\x38822c8c2984b569ebe8f9550660f64613754544ddae2d326269b8df959970ea3198ea007acb834db47e929c7c99a7a54908b91d8bfa529eb74150e15be48f03
353	1	21	\\x50c9f89930272eace67ca335762c84f4d449d6d406bcb0e6a5e5ce51ae4c4d502518e3aa2b783ffe38dbc9d2196ec6f675fd0ec311f83ace84604d5825f6a307
354	1	344	\\x7721dc6883c634c4e0151608b7e6036e4bc26a30c956d8bcf634707818186e477fd54549c954adc31155fb6bc6542cbcfd8c4a5f9305b5e325467bff298e5b05
355	1	55	\\x165a5033ca46843b002b1282d7879be18a6e755efc938cc72a30ed769842d724fdb08448ba2fc73519358ff4ab7afa059529313e254bb75b7be6609df34df00d
356	1	245	\\x290f842a10b755d90e8344e24d4b656c635854c3971e0d1badc27a08afb7ec18218f1e5f243c39d3a34a70029a51bcc99e55c098b6b03b1834b83325527cf30e
357	1	404	\\x1c85a81645ac51e380474f4b492048ba4599eb07e23359aabfa9e8f5094536766efb6aba01ba5714f0d09b2796423416c6a3d06aea5f7d8aff059c9a23d68407
358	1	391	\\x69a093fb14fa6faaaaf75a06a678efcda23355f25c7c7dcc435f5497ddc3f77981343840613fbb42853d86eab2c6afaaf04bf6be9a7ef9c9b5f7b09078c2af02
359	1	143	\\x1316d051d850bb41759405520d3ba7ab6435dff0c3f34cea0619e2ae918b382de53971aed32587118285f897fb1d9cdaf17ff82fd06e15f5dcdb4b0c2cab6406
360	1	347	\\xd8c69f98bfc012dce3636bce6e54f7e6174afcc93a0c5e613660237327147e531338dcc4148a70c2dbce2e7104ccc4c00be3c4c0488a2a7d44b8119c15e2c20d
361	1	230	\\x0cfa52b82f9b1f662f1a3245d97683d82170a1bd096b7118daaacc830d8745339048a0f580fe0af64bf9a4913c0c381905b35ee1e92649b63d5801e756f3b10b
362	1	397	\\xb578242b959140fe6c629ba07edb59c564b1c85aa8ab78446179ea8e74d5767464fce8fb3f9b45961adb0f2802936ac336e58096b1322620af7f5fdd2e259309
363	1	19	\\x26fd9f5c96bf46f34b07cdbe353fcce9677789bbe53c2786cf4da4032d5b1be6e7a1c1650b04261b576ff822df6ab42250ead6ed7e56f2f83e68b71ecac2ca03
364	1	266	\\x16b9bc5e34d0dd318f78a69d741d2325ed0f12c30a39c0b48cd536e5e8e0002f6a55bc0227f71fe7ef05fbcdd583c1a41cd3b90d2c1dff3a59332eae697e0d0a
365	1	118	\\xde1bfd09a2b146cd639886b0ed3010a8f7b2eeeecf27a978bc082c835f7802e038341e2b45b01cfd482627d2839d68c5edd443ccf0eb42b3f226aa605e0d650a
366	1	39	\\xc6d91cbdb59a933b8041ba8070f3c9bc4bcf094c6378956ac3c3a06db04b53a2ad5ecdaa4bde57b8b4164d34b49d5330766fde1147be9c0942fe7d06e75faf0c
367	1	422	\\x5619f79c7ebdcb8dfdff231327948e3cb316ce3502e13b6f45bf9206c753f71f8d9d8d585c58ff35c21cbeba9d2e68ef228d6803f80ea52fb1acb6ea95f9910c
368	1	189	\\x2882b0126addd0f7e69dfd202a4df4f3b444d35fd6e13099807b13a7cbd64e08c0ec8d324e75877cad77055858042d3b3702e1d73877f6d4f65f2b5b4a346704
369	1	49	\\x31ae32710b30992adf55bbd3eb9ba4b331ad997cfd6d94136ee196120936bc5d58f9d4a8e497ae0a807b96fed41a9ee2b9ebbe27f823fb95c97035566ff58e0b
370	1	25	\\x4fb66d7c773fbf34fb7b529e69cf271c06c46d889d2282ac5b6a10c97c0ba2c31e8047cd80d2dc4d8dd59c907f410dc2a208a5fa74c9ab4350369b2791008005
371	1	77	\\x1ef2857dfba9d88dc7df5f8bae45b7f9be00c176870a15e48679eba340573cde074e92e908d402cc2c5f5809b793bc2ba3c9b7096cefca750f1b2c61df2a6609
372	1	281	\\xd1503437208955f4a74aa80bb7f95b7fcbd715e57f9332b422956930b45ccc402119e6d2264910ee8a57397b2a5e0e3fe1240127a2553ea5bff17be435bd8e08
373	1	257	\\x7ae896c36dc8167e9595ac6cf10cc4376d2f0dfd427e368dbbdd589d4ff40feb2aa3337247e6dd72dcf7091efc73df79da7b1345f74b3e480e6e337f1089900c
374	1	297	\\xe5e9ae6cd19c18c2ef1bb095048e76cad843fd39d7d80be5e518ba8a5c009fafccb9ca05fed47b3eba0c84f9b005dbb5160f02fac2e0f2b37946f5173fa44601
375	1	285	\\x6631ac6c3c0b4b3204ae957bd43ec7cd9e117da03d9364b8e20de45851757595e4974b53595e62540e6618526d9d2cb50c633fbee3554d20e8cd9997bc7aff0d
376	1	261	\\x7ba58104c00a22bb11c3268f979ab36d9d1251d63287e9fc31d7048ca6dfbc24abbb13053beb08ff06531acc336f5ff9e885d80f5813694a3c72030b8e8d9700
377	1	274	\\xc1c22579cba9eaa67b6058ec30e4e18ca7f20c2831267dfcb6f27ca36c36e64f0fa856f4f4988b66d153808e3a70a3443b929adf20b2dde6003e0816c446370b
378	1	6	\\x3b659724c7bcb33bf273965950e345bbc1df12301e15c0c3351825921bd77f3f3c2343ea4526e58efa5cd626051b06a5485ccf02361303982644e288f863fd03
379	1	332	\\x8f042520b0ca36a35588781faed042a789460210f6b81355586547a819c6673dd63de53126964afc0c90e3f6b7d916a8ba601564222d029d23b65b4d055c6604
380	1	378	\\x9b8a9456df9271dc35eb6b62daae857d6afe557bb2e3d052129ce2d152dfc5b8ef64a89771889cfd1c0385998c84f264f4a07ca58ea64dfa4a9e37820ce04208
381	1	62	\\x29006b48ad2ad95d9598478aa33188bf00300ddc0bf517fe32a2ec057fae0b842d5f071aef80266bf7b2536817354f231e34bb09297aec4d607fda4ccbd9d308
382	1	327	\\x5e7b4cecf44a10f08b9320401675af30a67fbff9a68dd436cf5c713d7803af0201617269005e7517c1f81e3dd767139012dd22d9f712af0f26baf73d6cc17705
383	1	237	\\xeee259039ce78dc76456035b5c1495389be6f349e95e034c553b1ec7320e7ac3ac43ff97df303276e1ce60e0aa959d3b57533c1e4a88b74c6fe7f7e7bd5e3506
384	1	287	\\xec066807b909fae9478e171922ae199de5e309207bf96c6e847126f74bf4ed4ca54fada06410776336a3ef618d61fe0c2ecd1df313fc1ac2ad0a6bd4dfc75f0d
385	1	394	\\x13e45ab9afa4cdd67b5f6731059ff67821e804f4f175091bd4666bff02a71320141ba64c62fdd15922178430b98c49d3325b07629e9d07d2fd1ec04e9deb8d0c
386	1	130	\\x75cdd8f9a1a4aa8c0f102c4e7c79a5cbcc3398ffbde7de93a9d854bd813a18f9ebac93bc1d6a8a3d71ad7dbb6e7424d1bba65bb414c25c4727daf28d7beddf09
387	1	417	\\x66f6b74c220be2939231253e33a8bd4f7db01119579416b24b51acc6b30ed9462f61c2b6fbe8a50c33d0ce10dc8ebeb73b6513fddb10dbddf0229f62e4033e06
388	1	165	\\xa4d6424cb19f90e65aa7c7aa79e3d8f569f11b4fffb0aed816f8fc43c786ed3f5a9bf80e9b9371c575983cd7038b3988d6f492f4dc51742fbc20acc1d795050a
389	1	152	\\x09dc114b75632c3e02a6cfd249f24f52dcce18d1fc2ee45b607095b7edf546439000c347a985a75808e34ae6f4a7c41241dbe507282f759cf3706f2fbd844300
390	1	140	\\x174e463a06b43fa1c5d9760ca0c20e3810f17ca698554930c027af4370e68d139fa60ed4b2d78f0376f502af021b5a2dbf7518e2281fb7523fca663941db1707
391	1	307	\\x5bc0c234957d2f19b5f64202432e41f473d196af8f7aad8a0da39b31120e00e373cf8ed5854f313e1c41cf738e8c5862b5bd010a993ed2e0f145ddd1704fd80d
392	1	58	\\x93f8e115191fd00014f13ddb910773eca3ae7eda2ed60854d43a03060133876d4ef2127dbbf7b7120c3639eefeec65c76c32b8f12eab3ee315a1c812ad0ecc03
393	1	67	\\x10f0409fcd8212239ca7011a309e2b88be0731788eaa968bcb0d10e3251efd97b0612420340676d44d0d32105b56af70e11bd170f7c3e272fd5feb265aefab06
394	1	122	\\xa41d8deaad957c86f9152326cd40f1b506dae26a8af31373a5755750458951175581819ce42ed5b4942b805cc0c6e0aff2091fdb54f246809a049838c9096c0c
395	1	264	\\x35bef8093746f9a6adb7693f50ad19998d82017f54c92527e1db82d6b29a829aff9d99cd03f10fa3697769460ababf8fd2686b91ad9d6841251c72f49151e903
396	1	72	\\xdb60ee385a2ad28d1fb0b146ea522933d5a8360c572521829eb4e1fcde1a8589dff261779dc771168c4390419c1c3c4eafcabf6c6a65a6822cb3b91e48e9780d
397	1	166	\\x1d3b0d3de29fb79ba5caab82fd34aff4bc00098813632327136c991a7768a51435bb4d2bced4eddc3cacb8e5fad08b85eb196355b286dbe289cd8ceb95486206
398	1	61	\\x6e2f0d82326f127e17bc5bde6bb27b9fc95618ef1ccb47249f9abec83f652b611a2ba5dddef4c5d14111a71a651ab39c51ce6210989bbd1faa925e26bebdf909
399	1	102	\\x9e57b04b4ab0b39da4969ad2f53646c1e5d90e5b124c23a6e3a4a686551da1320824bbb00d9f91e042a488d4a58af34d2dcba90314e9afecd8eac2c2fd440409
400	1	337	\\x61e089b7370557c990b521d0f409afab91f3edd086648137711200ad9a5bd175ac1ab286feb228c5c014b42ce264314349229027bc8460d0dc3c38678229880b
401	1	228	\\x7ac723a2b932b72b52691e64a34b0fb8641f02367323da04b9870df6a56d366acddf08a68d782edc01b4b447e17abbeb75c62a8b48edf7d54676addcf4877305
402	1	254	\\xde522659321c81ae6abf2395f6b247d7a91d0b61ce722fc9b2165be914baa74e6ece1620ee306e960dd2141f4f7e805f8a5f18b88b37704efef245bf35399209
403	1	361	\\xe96e308568000ffb9b5ff2be3097386cd59175a83dbb1dff3d36eb1de0284fbe6f06355aaee918efda77daf65d85ef100b626776e7534cd86c9a12b54eeaa805
404	1	127	\\x384715f7d6eaed1add4d296202d8c8b90ff589338ca1333613240f9c1ed172cc2fbf7e3255e28bafb53ac7a8ad725c21e0969d142ca3f23a33783864a8cc8a0e
405	1	217	\\xbdbe66a8c56c2d3512156f1af2bff226251b8e08b984adbee8eaca991558e2df44b9498135ddcd5505e6a4a851d38be764c3662d72c0f6308d06d451e929a304
406	1	219	\\xbd1f3f97640933d21121b365e1555ac56870c545c155f399b1943f50a20cdba8e36cc654b34f765d6bf295ba232b11d6b791b2920448b1907e2a8ea6d6b07f0c
407	1	69	\\x48193a372525288b701693fb1ea2fbbc7f35c56b6b32971b912ea196c6396719926a2dce6d09d65ec60037b456f6e922cdc19d261e85ad2d0b8e6f5728b08f0d
408	1	225	\\x8f4081641b6ba4b6a36258e51d35e19bba51c8190ecbcf4f15e30bc80108e4bf99f589b313ae3958055c668eedc331d937d0b49502145417e450107408961206
409	1	369	\\xada209a80b6960256e173d3d7f0527fb1d4d0ee0a8e40f15d6565b8a0790c0c0acba65790076757322f1030daaebffd0d14226cef5c692fa5646fafdc888470e
410	1	93	\\x0ae4e847bb82e1bcd31f17cb4f3f08964051dbb4cd8bba605cc8d1b52d1819f16d4ad90d3fa8fc3b9910184a21376be839c8b25d78dcced4c93e9533dd37e605
411	1	64	\\x149a95f00acd2fdfe1f630a2207874510094739522f7512e733a0afa7ce07201d4a45c061b66370d7ddc61f232c2d95f0b7c0599c29d62df75c475f34bbad409
412	1	24	\\x23e2d5b659a11fb565832630431751b6993d126c6b7adeb0f476b5bbb60a8a03771ca6154fc4e742d169ed5c9170d8754dc51a45651966354230e03e74e68e06
413	1	190	\\x9f4fd0c78535ee80b4a541e3c9888b9d185d5338fc2407ab2cd72781590eb71e7adb4139d5cd21df3c97e4c02d0092e08c61189ed7daf1e15107a6a24db26701
414	1	353	\\x07697ce0dfc3fb51f05bf714f998dee8017f196641ce7c7169e1f2129420eba5a58f0a7fbfa1cfdb53274cfe64838d1c025550d3df4dc2f3e1d711fbcd6f0403
415	1	275	\\x8e5fe63bed9b47065954f9626b76f566495d20c11277463ecec6a17af55932025c7c93b6815a552e2f712edd126faf93d7b4daceafbe2e11e0f9293fd837450d
416	1	31	\\xdf275ee88eaaba845091181b8496d12ca2ef242966db576785fca421f42932c0d120588c1679758f5334c99969c30837071f6c7c3a5b9a04dc54fc65ec82d200
417	1	406	\\x5dc4635eb329c1c633dd576e5816d0b18ff97bf0090aec6da43dd011bc844c74701a6093937657134d9a0d1d595d9e7d338fa07f29d53c88fc1c605fcc765c02
418	1	131	\\xc898ad5b869876bda8255af1c73c7dc8a1d3aa1df58b35be49c056524a07c7418b37dfeb454187efa5620faeffaef813df79ff7c8fac54656e4b0281a7892c0e
419	1	99	\\x38d014930e70d2d575ba999784d5c4e488f2c0699b990d179b69b7e81595439a033547c2b80ec3cca24707cd7fb312033df45d72acb567ae38bdc25d93905f0b
420	1	209	\\x253bb65c340f41366d162c116cf023a2b4e70ae14a725acea6717f08dd580bdd438f6a3f19861676d56ec1bdbe87c87329a86153c5d84367df6bb0d590fe8d00
421	1	320	\\x7f17b10bddba4044f7fdf5c47978cb33ec709b3d63dccd3f38e6a5b9e54a8a4ebaff03ef30c180d193e9d62a366142d5e9340346139fef8021032b96f64c8f0e
422	1	271	\\xbff439cd8df66bb02ea2f57f03a8c4b5e263ec6056a563160dccd7c1420652a92e15c7d794caed4ef2c88bbdc3a3b7ac7ca7c4d8823f30cee5d48b1d60b1c701
423	1	63	\\xc228e2b486af41d92bf3c123df08bdc423ecf940e83e6df85984353f1fd2cf1bcd75dd685628e5743df54db1f37d4201f786c2428af7f98541672acfd0958c0e
424	1	290	\\x93383ebd2e9642d6f0ecd83fdda5d531a2620f88593ff2d182e1dceff436569e24e4ea784b4af39da7fcc3220c87959cc59b26973747f4ad39c3e6e9cc28c804
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
\\x25d64024b99941e6dbd052faac3647296bdad019a88b69bf4b70d808e39f18c9	1648212617000000	1655470217000000	1657889417000000	\\xbf61e2399960566564ff5dd97c8e6dbb3ef5e081242ff8ef6b23ea2e6e2fbaa6	\\x09e0aa98a0439f0201432588dd06a0095105c7b043fb85e2537de0aa1b93101e98a8d0b4d5bc1f803ebb41e5f6ed4155144406b5fb2959d2de6c763351db9f0b
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x25d64024b99941e6dbd052faac3647296bdad019a88b69bf4b70d808e39f18c9	http://localhost:8081/
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
1	\\x696736fad3dfbbd34abea82de698655e61a2cf6b5181805ca36209605e415c04	TESTKUDOS Auditor	http://localhost:8083/	t	1648212625000000
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
1	pbkdf2_sha256$260000$V7N8CobRzkZPHVZVEBYpgK$FBdC96svzVLiRIGNJu1l5vXXNfwle2MMfrftPJbgUig=	\N	f	Bank				f	t	2022-03-25 13:50:18.772027+01
3	pbkdf2_sha256$260000$NGlsu1KOFAvX4V6VOwgSJb$VP5VrkOG8IQvKINvAVirO1o5Vd+yqLE3+B6h7BB92Hc=	\N	f	blog				f	t	2022-03-25 13:50:19.035757+01
4	pbkdf2_sha256$260000$aMUdfg8Cgdg4vzxdhyp14K$C/CZRnKsCrf7r72ozYZCazO/NF24bSkwSj6tmq8LkFU=	\N	f	Tor				f	t	2022-03-25 13:50:19.194213+01
5	pbkdf2_sha256$260000$rr0osuxa9BaGbCqUtmfNAD$H2uJbsnDjJiGTd+rtEoKxBSIip5Tmdx5nU9q2vYmMlc=	\N	f	GNUnet				f	t	2022-03-25 13:50:19.358119+01
6	pbkdf2_sha256$260000$2HBoEJBq9TQlPlj4mUCRKM$vSaqVJ4O7vjnyHzFf1cQiKB5QfuhgFcRxA3pY01UIuM=	\N	f	Taler				f	t	2022-03-25 13:50:19.486614+01
7	pbkdf2_sha256$260000$MU5vjAVNTP61yu6h7MmXqh$4cjbCpIthscdOeuMtKHDzlyVlDqYcTmlzNV6MxkGnlo=	\N	f	FSF				f	t	2022-03-25 13:50:19.619957+01
8	pbkdf2_sha256$260000$OXxZd7yuqIBwyzgtCY6Ckf$9P8BA2/SUheF0U5JzBdGGAHviqFLIr1kG/UWtydTq/U=	\N	f	Tutorial				f	t	2022-03-25 13:50:19.789772+01
9	pbkdf2_sha256$260000$PZSAgolz3UkvoXNviQk1jK$M33n9NpGY/eDJy1O1pxGFFvMBYaorHU/RJiYa8N90M8=	\N	f	Survey				f	t	2022-03-25 13:50:19.914665+01
10	pbkdf2_sha256$260000$eHbGFZNUsma3emQ6KtysuN$4Xkyp35uTZikkPVxWZqRLExtqRKVtLVmHQzs1gBc8SI=	\N	f	42				f	t	2022-03-25 13:50:20.360173+01
11	pbkdf2_sha256$260000$GbSLu6QQdHq9WAj2zmYqYI$8080fkoO1M7QPi9tyBx2uoGwztrco85cU2kTizeQFw8=	\N	f	43				f	t	2022-03-25 13:50:20.803003+01
2	pbkdf2_sha256$260000$FxM2vUfhbjOJskZUInnFAv$/YKLrIYZTag8gHfLlqY1mHl+U8VlmNv7tMDgACguMHY=	\N	f	Exchange				f	t	2022-03-25 13:50:18.899538+01
12	pbkdf2_sha256$260000$LGt8RlskQfDkZhhnQsUhH7$fA1/UBaO31f4+ZuSt2PPRP9LMHTjVDtoVo3sAL0s8R8=	\N	f	testuser-b6sz6tiy				f	t	2022-03-25 13:50:28.800997+01
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
1	99	\\xb0dcfe6f9597ec50932a794fad854e3c0a37cf22d54ca71215a8fbc8ea7dc15acc96c77dfd13dbe54e46594b343f4ed1e73f484b0cf734d5dad6bf0104edd208
2	64	\\xe9f5e264a4e8e8460e740af73d092d0d3cd89e7a1b3f675489026a86caa30c5824aabbe0fe5c17b8ac508ef867cc5d5973071b84a6d6a3db3577265da551cf02
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denominations_serial, denom_pub_hash, denom_type, age_mask, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
1	\\x0258646110930cc0e23cb1f02edd01c0b684797b7762b557e5523ba6936eadd8991b6ad2afc635acf859b795bcb6c0e5c92700eeb6fe3cac49d6cfb1fb425fc3	1	0	\\x000000010000000000800003ed78412997ac5ab460307b7a42b8a9c02e5b7f39cb3ba27182e13ab94a71214292e673ce557168f9e0d56bb7c6cd923332ed742b9001279efddd5a35a1eeaafaaa96c3dc4b8f45c28024aa13b5f6db11fbabb70d23b9e0e83b73f28f629018ed3db4e06b95abf7b35c14ad15326e65b34c5f13663bcf16a220a23d1e49b5a94b010001	\\x348afe3c6a198d5e4723eea078ba9f430e3f330b59fed0d55f93da213191d700a217adb74ece61982c9dd3c5846a1bcb9199c893b0d58e9ce08d997a2bb20405	1663325117000000	1663929917000000	1727001917000000	1821609917000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
2	\\x04f4710423f8da6e1a1e7d63012898af830731c80187b9f7a683d1d096661827588491a02e0267655b36a178a8f739a56451f9d4a8cc9b84877d691da32bfb35	1	0	\\x000000010000000000800003c8de57467c8ee58576e483bdb883c2d2bf24d7b307718754d920cffeab823911bdf5c59470f07e3ce4e2a18f067e847091a980895164b0be6b252c5c3a30773371d22542ca437e64a5eb9e10b3fcc0f2d0b7a9757a2884c442f911b92453a8dc58298ecd3b30a325303f12fcb89de837f34cf9819e673234bc52ba6e7960920f010001	\\xc771e7d65de42c3fde03b3093e36fd4e6cec04b18c57ae55bea077c0b3ff6f4988e7ecbf2829949571086b3ce3daa63f614b1f6ada72db7a8af5f5493e79930c	1656071117000000	1656675917000000	1719747917000000	1814355917000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
3	\\x053c1f2fbd3bf7b0d730520b2822d234f50163506a514e6df6693b6c0cc01b6ea979ceadf663bc1eba764f3efea2c61b0115960fa27a998d5a60dffe98857796	1	0	\\x000000010000000000800003ecb46c1d7b987aac85d299719781859312fca870194de8779d95aad7f4787270ce97596bced6fe725b628d29fe26522f45cc731e048557b3352b458af7050dd03473c72d0c948fb6f8c0d3a4509be251fe6aa4943b7579c71007338216af480fef1a621069ab5fbf0fddced7f6c414c16124211cd30b1b1ffc66161177b9d025010001	\\x2bf8427c7b3521e54c0ec9d9f1da0c6f10ddf15077192083c5cfb92e2aece407f9fdba20efa27ab47e5e6059d0f5faae6f56e4216c9335a0eaa7bf3774a47c05	1663929617000000	1664534417000000	1727606417000000	1822214417000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
4	\\x06dc4b48c2755c2d3da64a61bd09966d415b853180f9146688a67d50943b6c40142c17933d2dc0983431c2eee207b82609c7baf108841d1c8c91420b62481b9b	1	0	\\x000000010000000000800003b2efc1bc570777f6262a20c96b7047ab4b44d1f56a76e0373b0613ffa7285dce4debb680ba64c0937c104a8f226044a70ce4478b377f2cfa5bcda2eb53152194fe9a1a4b200b2b383575fb44c39fcc14e5c4fff4b900295ec97312aa6682ca5864f468d9be8c689aa17226b765d2ad3eb5cf1d5f43281dfdf6f7aee2d6a7cc5f010001	\\x717d07146aa16d0f897e2cacff3f262e258da488101ee780166e5fd0f67471571834e0df8ed01b3a471c49f74dc4740e10c5f22e2cfe73d288f98a1dd314cc09	1654257617000000	1654862417000000	1717934417000000	1812542417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
5	\\x06204d0ec20e95b5ada1379343c1099ed9c4e66f37e7bca34f8f7dd46ba594315aed6d1dbc61ee09136ee0fe5f9f650ce60d7a0883948ec7fdd585f523b5816d	1	0	\\x000000010000000000800003edbfbe8f47f6bb830b29cfa1584fe97e6bf5ed9d5cf7cfc91cdae8e9b2afa2def9882d0666f9fddebf815d4c011dede02a0e8aa15c1fcf5379ec3136c79eb7e38c7ab509363f1dafe4838c0296a45c577759d6fa4e83399ce5368de67aff59138c123031e87376788affd8c915891fdb2a580d8674d25b64bda37c9184a2f1e7010001	\\x0e2f4508ff5400171b1ac4638c142b3d73a90677255476eeeadd7fff8f05d6174981d68e9bbf5a7edad1abd5a43772ce2b31b96df6efa48b2fdcb1583a7aaa04	1668161117000000	1668765917000000	1731837917000000	1826445917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
6	\\x0998af5e5da8b50e6cd16cc7a563aa57c046de7edd77e148dfc9eee9d57b89917898507027ef81240627ea564922a6d9479e2d7eb7ad2f1f00c49a5305f9935f	1	0	\\x000000010000000000800003c1853515bffe1122316d22700713b7f5bacb251d5a46a73626ec2df29e23a7f4d82e7c19c318ff9685416a2304ca0b4e8ec4ed0434b3900040f653a86cd8e764db7305400f01cfbad0004ecf80c920160642c2d414e550f5a54e2158d7c0b8e7f9c03a3a9d632bda23247bea4620f1ba15b0a5949bae24fac2912e4015714c45010001	\\xbf059ca280203909be67fbfed1d1c763a4dd0f913e842cceff84e1aa7a2a50c181eb04b699f45873e9b12be6aef0d630142cb96018bcc32194eb90eff5e70505	1651235117000000	1651839917000000	1714911917000000	1809519917000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
7	\\x097cc790604203485a263a4790ec4181e805f92e36e32f59af44ae6809a4913837581063f2396da6db8399e77e4265a24b80ca136ac4719834699a93f67beaae	1	0	\\x000000010000000000800003b94eef0883bf40936f1852535cb0dc68a67ec9ae922d94b20343f8f03335d2dad2692fa9584b751344e7bfc6d18cd216e58d6320e383a16b07a97c29c8131c9d3b8bf2747846f55aa7253cd655cd62792df2766060c098586d51adaf2561b2a68994442a23f018afa065d49a2dd7b701ddd8d1f6185bd7389a0de0469288e0db010001	\\x7d8edcc6614e6705837464ff180c7d3e97003a306a40baf2a8625bb51e1cb614dc0a51143af2178cef459707fb5501f9660d7df85bd50e09476d22f916f8bb0e	1669974617000000	1670579417000000	1733651417000000	1828259417000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
8	\\x0ba85d3c4b4529b241cbfe00f36a7c10b05b8da7a42d1ee87b3baf1f6040f1c7e30db0ea050b8446c76cc33d4b861ea2acb7d3fe2660267af57e28203e64766f	1	0	\\x0000000100000000008000039fc51e1476ed69ee671ec2a8bf67e1e376e1c55b320c9f11ffd0b683d8fc0a8d94491108040d9608832208ab36ee0adbbaeb64304be7f202982d5e4568a0a9907438513ea29f5327fe381b708f4ca2ea697aac23dbfd18cbceaf63fa02428b9020ba23ec7907a76125e8f2a84b11163f1900652687d1098444be08e4b20787c3010001	\\x4ce3abab78a36e5a5c68e78cd92116cc6d78f0f8df980921c0592703a943fd80f2e18d5e05598ab01f5d5962bc56e44d58fbb6515bb62d00446be3c54eb7b701	1659093617000000	1659698417000000	1722770417000000	1817378417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
9	\\x0d6474df58e79bbc4b512fa16a482eed645c8e0873ce48a4ad9c6fc020648f73a14d5d70ba46046b5c280f7d5a628e59a0e418233dea48a8f620683100eaf017	1	0	\\x000000010000000000800003e29791593adf2ff688ae0a12bf25419d1cad4bf8135ad939e4bb4a9eaccb74b367e5f9b4fab1b04c7ed64a9ea175e1a21d6a8fed5cc65a7eaa2d9925dbd585216903b52b3a055a58d90c85c4d23f69782e001ee934dc4731cd891b18aed1b9a8c0adcbfec454af436f4cbe2f2467f8633224213bc8c3ca96275db5924bfa7f4b010001	\\x2938bcfc813c04a4d9c8e2f2f76a5cdc8a01880862584e135dd1faf2f0b16bdc15911fe6f4732dc956b7a556d662a1cd87671a508d46417de28d559a2d41630a	1673601617000000	1674206417000000	1737278417000000	1831886417000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
10	\\x101c44052605d97b5eb0ccd65bf705c9d80781d2f44d8f56f60164a863169c81f70bde62f02109ecb4b436a0ae31ad8f54364889fdb3732e2f5aa575c337fecd	1	0	\\x000000010000000000800003dba26006dfd805723d136b4c553e9e3adeeea303c060a953d4717aff42fa7943978596b6016471d8fd260c641d4fc6bd3e735c93f785a722c3e9cc827f66a6d81e76938d1d8312f4e787c391bb7232e439b1d50373cccb1c5a49d61dd8b30fd634f0f68d9804fef3dd234173720487dac1ed5cb2d249d62cc9156abe88b2cc81010001	\\x25a2ccde4b5c6b6a4979eaf34bfa43852355bd3f1e33f768239c8f4c9b8e3e9cb62eea65510c15f9a5fa04c661811d2fb2dac65e44e0f6a1011d905e61af5c0f	1672997117000000	1673601917000000	1736673917000000	1831281917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
11	\\x11ec6e5ba09beaab215daae7dd0eb6b084342511c1adf678f06e15e283c2d7efe767b691f1a1462457928c55f2e883bcdfeed85d7470fb364e26dc33ad4516ba	1	0	\\x000000010000000000800003c33dc5b67a1738b5eb12a4c8b88f0306105e7ea1603e4399f91470591c49d900b7cd9fb0be695df8eb09dcc4488b4d8f9c600ab1434ef7770f1c32269a03a2e98b750eb47895bff9c3b70a18753661a37ddbe4993e84fc8e37e720e245ac923881158eb30b9319a2327ec6daf365e616f3e1e7005210c0ea64947a3d36007219010001	\\xdb50952431dc7d6d7d27fbcd5f7a2a80b61f11b708ee6bbd4d95b6416433ca5f65f98d138c783ca725e331f3e665476141b3e7448a776bce56f877528ab69000	1679646617000000	1680251417000000	1743323417000000	1837931417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
12	\\x11e00643c1ea9d673ecfafe1078d93e24c1176f32bc0705da37f29a1751523dd49148da3b311f31853402b69c02657dac95daaa03c3268676c23913cbeb82f82	1	0	\\x000000010000000000800003926043fe2dc0a88019034b23b2faaf27e2913107d25868e3547aa0c1f6e5e827dcc83a5636573b488577f72c7ee96df9c33c855bdec5b90c0db6b9c62e1c2f27455feac0a218f68aa813b7a97f76ac3c1425cee5d02b6479e8b9b3dd862c111fd84ee07079195c9e8f874a1aa53359677516f65fc1d37b35322cf2b4a9498dcf010001	\\x79a3ab04c720f234dd151006d57aebb450006e515820f19cae07a37ba884ac2526192f3c7ebb8b8806b0c4b7b8d9c98f676ab3e704107c6486d6b37a919d9207	1663325117000000	1663929917000000	1727001917000000	1821609917000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
13	\\x15c0478a6b2aca3305f7e4f490e52ddc8d07c69bf76dd0e42dac55ca765b0234986eec801c174b62688dc017dd67005611d97a3b7658f32f7b44de1cc3f4d8b5	1	0	\\x000000010000000000800003bec03c93c0fc3770ecb57b27932b1d4caa880ddf38bf8652653f745cd06b9fb5c4f7330fe9ac9a9dcbc411ae169457cfef3c3d069f0b55c529ac3a5649c16592da422d04bb4ff0149f3ff38cea61f8a1d912f51ed004094810f07b60ee04d06b4b47cf71a570be19f8ae0cddec48dec1c1603c780c23e05ae45d28cfc1cd2061010001	\\x20fd64579af0797f588c126d89e2ba76ecd96312d14414f669630805a9898ca3f6234e38d5154c050d5445cbf682fbee9e26060b06ce1176123d9d7af17e6901	1668765617000000	1669370417000000	1732442417000000	1827050417000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
14	\\x1630dd095a7c784b3ec4e15c68d22d3ac4972fb40c04d8d15ea8e4a8c3d17be6a7eb20b66289b8b469a0b6e1f62386a1e6a6d57aa191ab8de7e5f50b94eab5d2	1	0	\\x000000010000000000800003ca8a9f251d8682cf4e65723a0afb981962c04ea5a7595f8f2bb276d0f2dd6707dd3b3ebd28c96a564641b5838b3b2dd9dbd1f1cdeab5fa37aff8de006a47271a1e5e1d98df0ec0c0ca036ea4ead87700eff738affea43533bf495e6152e5d94964aceef1f077786f69f9508741698f3ba187faf67918f39984d0f2ffd0399613010001	\\x6fa5b273cdfc27395fc93ab9c343c013e6bb5b08eaa34dee7d36d571c9a40fe48c03d7d0eae86796d4b11284ee59807d39812b9da885712360cd40ceb318690f	1659698117000000	1660302917000000	1723374917000000	1817982917000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
15	\\x1aa41bdd96fa6c1af42d4040720ba559d04d5fe45a298f8627cb691cc6a9de00619482bb97d16cd220cae4450d0eea5a7bc00ce6e05c009d7d7b04d44a13704a	1	0	\\x000000010000000000800003d14838fb606d8b3dd2723c9176ce1e8018f53a92092f24916f9700abb4841af8d22a7b2c9eb8f61ca51e6d9fb15e2c1bd7e29b07ace8b3c14ea9e4b1a64ccc34f40fb7f7942f3fde41803b460484bd98ce82713df5c721a1ca8f2664a10844cbaa1c370da5e1163de21ba7f282292f93828b9b9538bcee69c1a4084f3018df51010001	\\xb1b5749a14400b9f232de545f383321b00c4814e11b2097fd24a1b9d313905af4f560aaaeca04eb7ab9e4ca5990171a4fb2c12d524879386b79d375d06ff680c	1679042117000000	1679646917000000	1742718917000000	1837326917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
16	\\x1becb2b97165f560f17c3bb9dae7df772194e385457820fcb5ecec5c899eb2ceaf29647e41347564f96fa55421979ac6f24a87862074fca20baeeb56f9e09144	1	0	\\x000000010000000000800003bc4c89d83b1dc0f4bd8eaec1fdff7e2633e3f9cdf40e280051dce35123ac41acd6ae01fa95c472e84d1b03e42c59c5ba320accc9098e9153a71ceb5e1d1d5cf4a614e2e27718b8e4677e8ec88420ada8b94a7605ca3c7fc21e1cdac7af792eddb5e172439219b08021e7fd35b2d1331f32661ab1b1758cedfce82a2b0505ef09010001	\\x3ad8ec5d865b58d8ebd663e65f21153257aa3bf99adf547b4aba466f851844ac3a328110de9a015489d0c43dc0ccc3e762c4d22824ff7cd45c56fc36c3094302	1671788117000000	1672392917000000	1735464917000000	1830072917000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
17	\\x1bb890f539301f73aaaccbddef6a3604374f28e0e3084708822133a27183e0b6b6456114e6d762ac14a2d345ca0ab02eba708a06536b6e599a0024c39288c85a	1	0	\\x000000010000000000800003af3ec33493de042e423d9d180bff12ed64c0eabf2f1b43cf384eff464701093c2aa49261bb994fd2d9def0039d5d9671472990ef507ee92582debb3a1ab3b653cdc048deea01045269a9998200490039ae5a5b0255501c256b0e3aa5d0ddaa4dc77fd85fee27968ea996dafab225afb4fb684ec25caa8d49d5f774fb49e3f277010001	\\x09510934cb426f08540fd1716381e7db92451b867d48ccdafc97be72f1319b3ae8466ebcea376493eafc9b1f213e7d9adcaa39ae63c04b0f18867ee169e82109	1677228617000000	1677833417000000	1740905417000000	1835513417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
18	\\x1e108ce3b0ef0ca17419395da7482133c3c25c3f39780ba5c29c9cbbc5ae33a474b647841717805e27f419baed8d66705e063e35c928d0c3fe99f9bba274fc77	1	0	\\x000000010000000000800003a9634595ecdf31dfc776f369e8a1112b7abf216ed13ee5d405ef2e1e15dcb72d23749aafca970e3e0cc5f3af252d00325cecae1b4977ffe865b1598a9afaaa64ed11ac45d840f9c59fa4e20ce35e09501b885c53632345131e2024477a3da63b1aaaa92e84b6435f1e1b402b155df9d737412ab34d862c74792222d657ecf4ab010001	\\x9d9e352843fea5025cb68ecea68c065e3a07df1ffcfb5703f38cbb02af37e0232e5c09418002c3bae5dd70920482242e097b775335b9936e92b4ad84acddbb04	1659093617000000	1659698417000000	1722770417000000	1817378417000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
19	\\x219855a015660fe9e0c42f6b96e71545860703af4f1bc2342285c6d35ca809ffdf631a83ac0ad3436bfbc891f6166fc902f6b38567545d1daf6919c5bc80d70d	1	0	\\x000000010000000000800003caa17f45d4148a6c0202ca38048986edf716cf83a778b1fe5ea5d0059dbf60a085d0ee7a7e136fe10ccf9e42e1f728258eff83378c53c9723e356d7464b219f09fbdeb97eab64a404642fd4225b6815557840ec3c1896187ee7c5ba74c9ac20a16c390b74b6b7e5c79084ccf71dad61f6dc3e5e63908c92017621303a6fb30b7010001	\\x0a87e1122b6cd6e7ef2063afaa205c6dea9b6ec07ed512187fb0a53bf5bdcf6b6a265c742b3ac5fa156ed30ad4071fe84b518a84cde34ecab70a5d4f8734510f	1652444117000000	1653048917000000	1716120917000000	1810728917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
20	\\x22d84fd5ad6b34fee1edb9a017ab9995f3b7fae52a1c8d6e884019968d46ed086e378320aae787e30c959635678809ab477e960ac0d36c6b8f670ac1c7bd5ee2	1	0	\\x000000010000000000800003c6b0e8d2cf604894b75df4e16a06859bb3728cf504b3193b7d88800be677601e2ba8493d2986f3f7c3b67b5f47274fcb650dc35c8b9e8ecb3d5df592b9f99c38422f28ae352f7861b5711035e7da32e07d6e97d9f6429a4a512ba9c2c4d9d0cc0edb17cead28e3cc25cd37734b06e2ea8ac4559b37541b3b38da838a9e914c1d010001	\\x9c9b73d4072290a8a607ceca4cde7e5ad10c16065e0a1d3c0c182819ec7771c2d1fd86eb6dcec452d06039f8381004ed538904a8a620047695f9a23256b88b0f	1654862117000000	1655466917000000	1718538917000000	1813146917000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
21	\\x22342d2d0d2f2030a1620db39755baaeedc6106355f233f6417c73049a80b1d41e32baa1ed44475a2f11b0abb42228ca3f3a3c4224070d0b2b846090353428d1	1	0	\\x000000010000000000800003ceb7bf87e3385904987dbce839ae63a7c62a709c057e3312879b6d24434391ea508a8b9e0ee6cd7c451c58e96209aa1fdefaefb9e2101d72332d30d369a4ef38dd811c9fca995752118b2c4767fb5cca1a0920564eb7d480ec2971fcb84b3a616d7f6b69c829cfb9051288cebab71fc15be24b288c90111054bce343e93a0f49010001	\\xd695da23005acad4e2ac045ef1768b7527dbde55ff4b7034778f7461f4eb3eeceb3a8ff6f3599c748f57424cfa0961954c8cf9ddb7751a710f04233e0d452f04	1653048617000000	1653653417000000	1716725417000000	1811333417000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
22	\\x24a81482584d71ce1699f514671f9f1c52c488b9fc25abc7b9cc405398cc479853ec47d4158a5e33e47d1fd83ba0c07e00c2e7965146d935eae9fdda9cbf6159	1	0	\\x000000010000000000800003d063ce285e4e5adf5b334f71e97c30650fbe34b055be1f4a0b78c1d371d53fcf79a71d203166d0449631eee6515a61075f3d37878dc8f286c2ec3fd9e5ebb17558742c47c2b12104632adf4c29e635697c9cbb85ff4f5f976dcedebf33a91bf6b285c159a265dfa49e2d97d300b5f23cf01a12662a413950cce9f41ab8d6af8f010001	\\x267bb636be4fe0a217c952f2fc14b27f2664ddea8a55524431784c93879a7a2a1288a06a614226650c4ac2efd1b386a95b9658619a74e12c8b4f0556ba80170a	1679646617000000	1680251417000000	1743323417000000	1837931417000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
23	\\x25343ef1199b903454a755cde1db78551d4616441fa6425c6aafc302ca63742399c382bef1a445f19ad505c4fbbee91b1a835eabdab32ec271b10defc474d213	1	0	\\x000000010000000000800003e07afbc214e12e6b9eaef2586a8836a41d47844f5e331102e2259d9aec709c742a1be9b1bf600fcd1c591e3931c110639fd5be3a62c567e21d3002abb21fb5a4c7b25726ba6c3cf497fa14bd6f1780fa89345ee0c0cf5169e0e6e29b2c1eccc890e252b3b9b63f70f84364175fcc322348561ba0186b9e252ddc7e8326082dff010001	\\xdbb662aff517f6c62c80ba67337b003f63251948d3172711ad21779f9dd47882bf639baf1d8334b14502906e2db354c4d932a19649f58892a8b9997660cea402	1671183617000000	1671788417000000	1734860417000000	1829468417000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
24	\\x266cbf888380774b1bcef2c1b817361a2ee0c274fe252922bbdc6a5bbefdb40bf564297dc882c8c7595a7a29f900c5b2438d9b465486f0a5569382e8a10a1bcd	1	0	\\x000000010000000000800003ce73a03cb5172f106994a3359bd6273483b749928f5b822de270de2646d6baacd5dd9ca37deef5ecb8eebdda8918f87a8cda8e6fba0b7a7ce26a1ab73e9d3d742f3f7d25835207d595a121de2e955a19a8f5c64b7d4839955ef5f27a6728acaa6053ce25b729d926fd409002ef80cfab0a2fb2015c694d089a4afcc864b69363010001	\\x4219d8a01a0a573c3771b81cc75afdda4a4026644ef2f1c8ef08be597b8d7b1b6e588060ff9a1193b2859afb2e284836f0a4ecb88fb20291f89e173d9cbb0c02	1648817117000000	1649421917000000	1712493917000000	1807101917000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
25	\\x2a64b268e0abcf7b28145e3708fbabc9d3cb8d8eb9550c801396afdfeffbb13eca30d3b658eeadb6c3ca882b1ea7329db4b68054536171ea5c86928a722d5826	1	0	\\x000000010000000000800003ca1057f16065a384daec0c801e90383f102e2e9c302f62af9eae21e50f2730d4b0bc8052661b504be2ded32263cf61b2c6b056fd2810281e2b52e1bcada95c83765e60f10193abf81eb5a7cfcfb00aa783406f818dff823f52272eb7207c21e3db19523c91264bf9154744fa9994dec5ba3d56d20cc58fc22ce21d75fea889e3010001	\\x5dc6ad0bc55b72dcec7bbd1396d65a8d0519f45499dfa1a90be6c631ebcedc8ced832d83735c5c68abb1a0d6ea744e7945e9f6450bef7f894cbbbef17cc06700	1651839617000000	1652444417000000	1715516417000000	1810124417000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
26	\\x2cc0c4c7f93f12cedfdbc110250b37f30033476d9347193083ba1daf3e012e04100aa669911d38ce7236362791bd9d60ffeb6dc9e30eae76ea1aa09e42a7a673	1	0	\\x000000010000000000800003c3b11729bef8ddb17f977deb1a80764ee1f20a73b1bf86ea6883a4c7f65902ccb2916f4f0f90832b3e585699a05cd06faa7787d39ecdcc7d21fa4532bce63e47fd917bb720d08899c9f9dccc8241682a882e7b329cff31879b08d73394960e3f14757fc284cc866f06c4c3f868f2e0cde21024c85aba0375bd8f0f904035187f010001	\\x65e37542c2aaa3f6c6be85a1f0c63732c3d8ee65e20b00ad22ab85992943edc08784038196f370b51858f340c959994556d62d956dcc44fa2c55e9d706a21b0f	1656071117000000	1656675917000000	1719747917000000	1814355917000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
27	\\x344c9641e79e8c864e3ddeb34656725bf03ac0f4991b5dd0413ad154b46a1232568da62e7039fd9ac4f503b8de0c047e319f30adf925095f5002f4ee176e0898	1	0	\\x000000010000000000800003e40a2ed4f54413e8d0ba1786326e6a36412c1d360fdcff5b94dd77f04dbc03213a105e4d57b4319b5b7b5b18d2487edfb118677cce63a004a1d25427d4aa7addc8209c95c5f5361171f42888da38612951c3fe1462ed479f6091e415655a39133354108c09fd1f2e9251534ad64c8fc1278f4d3694d92b0157d883c4c217742f010001	\\xda44e4ac51a3ec15bc5f2c792005b4fb4e01e3326a0a3213a3d395846128b7724e23cd98abcd6d1b70d2ba59e396d8decb77418b51a807938e8a13671cbf3b0c	1678437617000000	1679042417000000	1742114417000000	1836722417000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
28	\\x399c7702c3b35b50032250d77ba4a0cf65d426e1b156986f9c7c999f191c80cf103c155c276e1358221316f7dfde3ab1cfc08cde92765a172c152b7d525ad59f	1	0	\\x000000010000000000800003ac348be3d05fc6e99c4f3e95d6ed2e55c1c9f30f899297a31e0972ce06d846623fd26b07f7e582c0f60accdb794505f2721bd1bce668ee88e28879fe6e22c8c60412d41d39151354af12c2c083fbde55abb7294fb481f34b387265b0cab06deeebc8aa72cad94f081871404dceab868a0000010b994c7230d79a3e45c49d5177010001	\\xcdc4287891522815f3260a26672c7660c51ffedc67ff4ec58260b5af0f538868ec6b2c434068ab5395b7260e6189d5256d4cd100616db1e28dea204b930d090e	1675415117000000	1676019917000000	1739091917000000	1833699917000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
29	\\x401ca0143f1d6d7d7125bde678e5b05a3c880af3bf87e8f3227fca8f01e67bf1083a0c36b9e10154da4cf2f07af2e6d0b26ab39de687054283b0ba9d79e8f784	1	0	\\x000000010000000000800003ba931faf5a108111adf2a7bdbf260560adbc3ff5b4fdc035330e4e5ca973cccd7e1e6a33946b630fa0d2eefb6671287be2d4a7983b77bf4e2c6be842c899f0468e0aaf86ff03bbf9f3faabaf602244451e956c2c1b64e19aa68dd408a050ac32dd16cc3e5f438b105458448e7e7e709f145e9fbc373f2ca1038cfa2928fe3f07010001	\\xb5ade1308d74a2653cc02e3232bb10c9721e438cc4b10c3c6c02531ed9be3350af56ce8589f34c92f8c5a1a07be0a79ce19b15636133215c3ed4e0bd81e06407	1674810617000000	1675415417000000	1738487417000000	1833095417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
30	\\x425c00ba315dc32c16a11423b6dfec54beee82ee18c8153647a806328cdb83a548ee62e9a2814abc73befbdcfa5e8397af0cc42cd4e862e623452f037c6da471	1	0	\\x000000010000000000800003b9bdb9ba6528929d2eed0c93d84e9d596cfc7e1bd63db8482ff24652876a63d1f8c81678ca453963e604af0331abb61fc6a4fa48e83940e59584eac89192e5e13454107d10317c4b1c08d944083130f5253dff797c40c662321526ed210905a2ad8993d2200e2ba2aad7d048b8a209b71b3e422f8ede20a048cb459225883bf5010001	\\x4fac57ecb93730cf236751819d6cb668f0ef21b9180054614bbff3ab44450b25e5461d16aba92c3ab3754aadb565e3b549ff68f425bd1ef0402190a6de039308	1667556617000000	1668161417000000	1731233417000000	1825841417000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
31	\\x466824c6352369c28ecf983177a270346161e1a24eda5ddb4b2032a090778433784773c711e3fa91ab16b0160bd08b0b3f60d2fa261e8dec13ca4b4a6c8323f0	1	0	\\x000000010000000000800003cc14cfa3428c7913d2ad1816f3167bf56caf852ace749bea5e534840c6af4992fa53dfaf7c311983fb181b2b929fa419e37fa1712c8978dce687526e7befafd5f2c3a3f39b95aad73c52fd9e8ce225cbeac71a4e6576c3bb39c4e9494ce19be83ab474cafa1c19dff885de3bab4e5f46cf91fe87392eddab601e9f819a2f3af5010001	\\x6b06fc648ccc5b83c8dc503da9f7804eb84a23e35f1256c3d06d818bd6f19e338b0f7525fa6ad4f8c5cf27a4cb7d48f8e15b5342a337645ee73c21fd303d3b00	1648817117000000	1649421917000000	1712493917000000	1807101917000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
32	\\x46c86b23c34d3f52066e710060b50403b65e313ddc08724115c96fd09d2d6567f1185ab108f569cd3ecdc809c5bde8e7e3d6ada976eb03d05b5eed4fd50061f7	1	0	\\x000000010000000000800003d0b53cfaa37d50630b7e8b230ccd548c1260347d12773a785e3efad5a2db94b5b7c82ea837f679f07538440036d199479621b6ac79cfd4e8bb8afca0ba6bfc666b63e6a64ff728228ce6e861dcc44615c509badd4b115c4b8ebf728f6624aeb00734bb2da99e78b4638b89cc7bdb0d36b7df5e545934e49f87c72bb6d8c20b41010001	\\xb16f0fd4149174f80e7d613cc6458841d5babc9710a3c8b65af92d3cafff1eb83b9c6962d80b722b134fd2304415847e60ef3d3dec419710fe5ebaba42b7690b	1679042117000000	1679646917000000	1742718917000000	1837326917000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
33	\\x48a80d93828440814f7974a77129a0e716bcd63287d856267b891365c7f66f437f5bd5ca7e4c6026354c0bb54644b26e4c70987fbd07c06dcff25d953d588733	1	0	\\x000000010000000000800003a934d3a66de17277db84b8313d8762ffdd2575b751a76420ee7d8064208d53beaed19c635ffc79bd70c45624df12cd732643fc92bda67a546a98a39ff3c36d2a342ac2840fc329ea103f920596b23b56601f2806d0d38d18ad4b5bdd25c2d2a2f2cff81b3f8b70a09fcd7ea7b50b3af16222731e46fb674e6a1c133d0761b9a1010001	\\xca434d07ef2e30b9645365822d4aca89cab91261060221f203ce612c8f21498e796f203ebbf6040be400670026b8362acd7f39280dfba20a2648c43770920307	1663325117000000	1663929917000000	1727001917000000	1821609917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
34	\\x48fce9a926acc528a1ed5a1c001ede6734a00601f7bc45d876441ce0bed942faa303ff570a2211c00e8bb6b52ea3cb83c734b02a8d0fedbbabcd92798ee7f6ab	1	0	\\x000000010000000000800003c3bf92b91ab3f6bed7a8d22b6676ca0f5bfbbd3798a64c51a826d30d887f63a825d4efd8038b048bd05213b10cbc98ff8a3a8ea6ebed311475aeb45d13538bceecb7eb5f7b125a0afd17aac8723a3aeb8af7e3094a5b08989c9ef6e82701955cf044e29399febdbd326b874fcfa9c004591d95016e71e573404c0badf0270c9b010001	\\x6a6fbe4b8226f7bd769b8e1e9957d20403d89bd1c8d437128b5a37d9dc480e585110a71450995a0ecf54c58a63932285629dcdd57f6a3354ef360ba4b5a94005	1667556617000000	1668161417000000	1731233417000000	1825841417000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
35	\\x481c48312a8b6a3a68125886ac850e9dbc700fb7a4ac71a26eb62b574d372bffe548853d0bd13c46f0a664c1ddc824effc938910a9674f4ade73e562e30e826a	1	0	\\x000000010000000000800003aa3f98cbc6134f25db1527c63a4f84711f2bf61a4d92d2b4527dc47975986eca8e4828c285ca449c369fe8b0640c21bed950c195a82f45be30f7dbd3522ef478c2f90f64bbd18e23c852433dd4737bcd66b26f7cb894d25149bf706b3b9b5e037c65731390f472a14514231409cd4a370ea214eb900f9fb3460c77c7bbd80e71010001	\\xa335d2b70523e5ae9c3678b1e2ac401ff2ce490f0552b80540914b33753af441d0401c97630bb866726773828230e0c6819c3e286b980f76799fe01725f58603	1665743117000000	1666347917000000	1729419917000000	1824027917000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
36	\\x4980a3a2313e8cefe854a9242006094ea31e5252b7cef4c5a22ce31c531532cf20ef5f7cb284f0903e328e9755da644288dbab371c7ac0ee97d626ef761afc84	1	0	\\x000000010000000000800003bb2f323108a5730d928fc7458ee2700ed99518b6c0967200daeb07968a07f0aa31f9179f37ef86a53854ba3d41995eeb1e3bfb568d2dd3fd972e7ad03b22b575ecceb6c8bcda4750e4c7dac39b0af165d4804665be41840c0f3b01581937e50db99996ed7a3dcd0576cd84b6efb045a2f8e8aa1a5930f8a3842be7f8202cb59f010001	\\xa74ea35b471475ee1188fef75a43817cefd7262c89cf53d44ef5f017268eb4fcb88e200d4e1b028c17785e5c2002b588d1a50f2c5b1b64304a1d7ffebf9c620b	1673601617000000	1674206417000000	1737278417000000	1831886417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
37	\\x49a034ac775e956c92ab7a32e8daa800687cee1172ba2ad4ce8a8438df5c588f290e712f6079d3c32383f3122db1616e11b90be8ecb9689c74ab536ddd7102be	1	0	\\x000000010000000000800003d4bb7a5e2cffe36c5b9d98e6d5d888912b0425f6833d41cf5cfc98bda59c0015f99d6cc4bfd8d224dc80f2334ce67e060ce95cd97928e26220fd83f4b6bfc50a807f5c2d2631e59ea1bd0b9901f4ad79fd915a144f0dea271dfd20d996313f6292fad13d99ecadbceefa85630e7bddbbabbadc400f1e7140b4eff13e1789d27b010001	\\x13faf5e581ead915bd9d2b33439f7173f57f0ce04110001c8e39548126daecd5b844c4721d15300d47a3b2215a84b19e1a9f0b2538a485aafc8007ecc6663501	1673601617000000	1674206417000000	1737278417000000	1831886417000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
38	\\x4f147f0433281a0908168a11072acf55ed4aae9efcb6bd66265cd278e710409e836ab7f7d1799c0e48d4bf94ec9604b69346076de95fcb5b6b4c173a5d580300	1	0	\\x000000010000000000800003cad7deb34184c612f7b0be79ce13794d2ac7ce4f9278c62926b342c0e18eecbbfa38c892a5e474c220526c87c082f5edf7d1abfdd9459df104c01a05c053ff581715d825abeebca19e0f6de9b3cfc3482bdb5206954f3cc8b41d849d990e4ed72c3a90fb1059e7ea4122adb92e8d24e8124d6f700af8050e21c69da77b26ee6b010001	\\x3efc61ebeb5ff80c74a39bcee9e45a01d5396ae869c74b720c7ee79c831d6a85793e80e7d1d25ae249c6f12c2b7a9b6e752ea388e07c90f3346ecd3197792d05	1661511617000000	1662116417000000	1725188417000000	1819796417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
39	\\x4ffcc9ee7c11d4838ff0d078942fe44fd8747c8522cff2971e2ab8943d7469d6f411edb7daaa771fe79e0a09b1ccfafd61d47fcd45389ff3c9a9f76b4789c0de	1	0	\\x000000010000000000800003a58cecf5083772dea607bd7639689e83601634d2990f8e1a206a06da028018890ef7621bbacf10f64983aaf7c01479e7b5f66a84ebf6f6f2fbfe547f9816c934bf6121aa4fd9be19c9b141da1ecd4b0272e831d75f85bee8bb7025c516c8fea01e8a02971265f167c9cbc3121d1f19ffc1e876f1fddd5bb2d6e2667b9a5c0bd7010001	\\x6cfd34505f8f47281a65e58a97f2de8acba1d1958bc52ea99163937235748f3f103829a51f85a58ac49b6b5ac4df2d20fd3f6b6dc391ab3ed22612b89b91f805	1652444117000000	1653048917000000	1716120917000000	1810728917000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
40	\\x508cac0761c432c86d67b5d385cd71998ae8e11e07c142915520bf578487b9de41a68b2ed172a30d2514c30ade789792a54d594dd2dfe366942a4cc5eff652d8	1	0	\\x000000010000000000800003b47f27a26bb42459817d04a0c740db84dfcacac6af8fcd148323616de8759a25036bc5d25bb0cc39f838fd7581f97a1d4761711acb439444d33036e9fd8ef990d144e5aab73291cabce2aac555ca7694ded39ec5367193bbf0d5ab451f378a93220073c2d30d0114e214449bb8681e3498008196762aeb84090ae44a24683b25010001	\\x873954fbf01ff68cd4306ede7a02d6a7208c844f3f7e7c0ec011d98e71243c9519bad6c62845c86b70035bf7dccbc167f000cbdce0b864515bf341bdf573f100	1664534117000000	1665138917000000	1728210917000000	1822818917000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
41	\\x524c22dd2899b0a621793191561c03fd20da95d0cf164792ffd4a1438b930675508d582338ed833ed501793addd5010e231592d7264594969465481537963962	1	0	\\x000000010000000000800003c79510f779e11e7cbb62652b39fa50ae04f449235d7269d13fdf3d380427d14cb0416a33c1c41bdf681c8b35208f8dc52bc50f3fc55a789874ea853d57a11323e32edf8f6d2658755da5595f6ba6aeca4b77e056388364031dea80121b99357623af6df4d11b4b20558c453654fd3749bfd085ac9820c2b8e211633acdca5a69010001	\\x1b90b2a563eeed00a3e68f3dc9377c801623cc0984db64108f9be32d9385b3f1c6be2a43692028615bb0c7b4f22b3fbaefdb7f3e19c4a4c85bd482873b121408	1678437617000000	1679042417000000	1742114417000000	1836722417000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
42	\\x545c4587dda17d39881ad61cf213c9bafe623de678172f87e76873b7f580b681e035b393eba7409b969aa6df609d775cd765d913a4448faf0d734e87dee2b8cb	1	0	\\x000000010000000000800003c3f42bc9a2fb6e9e9ffa6b7af7819a556301a7781fdae8e674a529ad68fc4d91719e740da26dbdeecaa7f8e4e4a31568bfa5052f587ad60a45a1b74544db9b7f4f0d0645f6a9320ac566e1f6269d113180ddf018790e490bad2012d3f9d8574caab46d8410fd1c7b5af1c83aa12486c5c4ea60c811ba2fc6190b306400f8e823010001	\\x43e3c3b85bdde7ee648355a0afcb340b1553664c76340a2c6010389ea53a4905b7cf8b29ea49db9e0d95d61dccbc6b6a0426f8f6db685ad22486d4376f525c08	1669974617000000	1670579417000000	1733651417000000	1828259417000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
43	\\x55801655f3c470dff5209f5bd0c5f9d0dfb76793e4130a54fe2b5a8cfe902776d5ca833c160f04a4eeea3c4c3c129e14d0a095d9ad5f0b7aac9297f640362086	1	0	\\x000000010000000000800003e5bc54d05109f8f05b3b7fd677684e1f76ff1f56ac2604f8ab0b332aac61726f03de0119cc239da125e74372445f11625287265e1686955d1bc5e3d3b2bab9d6fa94e48ddd5a49a9fee6d4090761512564047c3e498ef12d6f3e969d94d93d6660d8981bdb526181733d66f2916cc69c169c331e2b80e1e24585697b6a889d73010001	\\x7fc4ce81d725098ae4abcd0f0e5608800257b7098155ad17fa65d693734c31f8b66c15cd8ec4100fbe4ce97c9bb7b0a6e31a55fce9d8a78c06ac7be65aa9480f	1663929617000000	1664534417000000	1727606417000000	1822214417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
44	\\x5644ed5f43f6a49ee06b0de077da50e3161bd9b94896189ae54598b150ee1307f98df09a4d12f47c4346f30cb6592caf5c4325fe2da87aadb05e5e2e5dbe0c13	1	0	\\x000000010000000000800003bbc972e43acc8a68aff7cb43cd795b83e4cc7de3462c1452cf731f51ec93cdac9145612e9577cfac08a0e547fad16a6f189dee6f6e9868b8e3030b61921237e05aee8c35ba461934651f523899b7c4e8b19979d089be0ef02b2af8249fba37adccbfd73ed1a715ba9ccad9b36a67df4fced09c5e1c10c89cbd8ed9c702616ff3010001	\\x9d0a35cc492f9356ade9ea0b4c33a051cb8406b6568292d1b56c5378f481074a33a537d562375e00be916e0c0fd606ef391e932603da65bf18926f8c0028b201	1677833117000000	1678437917000000	1741509917000000	1836117917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
45	\\x5adcbcfb29a521282a5c1f60e5858976c6e98ef175b2a94f33a89ef93b94eb6b33529f5f47f13f61f9904a2650d299b397903ee13a3430fe9a8827090e0fcc78	1	0	\\x000000010000000000800003bbff147df0a45b8cab1fb280558ab6178ac0fd679cdc249a8745cae11d1bee4c75e8fd5a6e32c75ae89cd357b5dadac8111ad6511ea4e4f2ec12af779c736eddad6e4058f068a549a3b0069949bfbf38b251154897b68ba42a29acbbfe37beefb399391308617b788b99af03d1613883feac98b4cea6d4d43ae5c6e1aa35517d010001	\\x6f4ec3d0c4131a7f26093516db9031f33062c99c9b208d89c84c96f2db13ae2e4462ceef7658beb839f3895c6414f3ccb00f24cc78e4dec9aac15d13f75ad20d	1662720617000000	1663325417000000	1726397417000000	1821005417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
46	\\x5b54ae1c0f9d7d67a9c9bb5bcce7993c6f80ce8ffdfa7fc5672383b754ef4a6eb4c4be777b593e96776d3966b048cc532472f39c76aa2103366ed88b3d9cd62f	1	0	\\x000000010000000000800003c2b906a6044e34cfa574fc6171aec7170221aa9377da029977774f1f2bee01c57330d503844e2556be29cdfabaae27098b2b583b139be3023931a399d484b40142d856492006a37ca2eb12e6aa26b827fdd5db443cd71e3a76b1e3f0a48042aa2eb6c2f6166a378a6bbb013af211603ccf5ca2de6c5fe9bb535899269db6f9c7010001	\\xd455db04038391847ccc2f19cbc931df204cd8528f069996d7ebbd749edd224dcd07e11f46df4e7d7d429221479b0f19957e92c8f34a722bd6b958f0eae2b103	1653653117000000	1654257917000000	1717329917000000	1811937917000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
47	\\x6008309ee3a6ce6edfd87f81419850e021b31f89a2f90231e3f4cce75a86b8c5295992b6b94f3d05bbc7500bcf1451312078863ef513787c1c50b0c55a076798	1	0	\\x0000000100000000008000039b0a7f13d4af5bf39e1b81337fff35af12d666c6e69b17b5ff7c7f2b8fca0d0ef85e02513850cb0471f2cfb0d846f4f4f7130d376f6a87e5bcea41e6355f9db6f8e06837fb37cfe20e26517ea2984b46321d18710aafaa8dcf3059e7754a0e115e78e2ffafdd232e42554ec2e37874745fec8e14f01d2555e494d47973ebe2bf010001	\\xde72b2173006d04de765331803cdb827e663177087ef659fca0544e77e47167d2657d74762b4afedfb195ea1e93faf9a375c873f6bb6ae6d0759733f65777d0d	1668765617000000	1669370417000000	1732442417000000	1827050417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
48	\\x60605d6c755c7867938ccff89f44dba7bafb5f46d632c4633168e67dbe1344b3d6925364b3e83359603a7cbd9044c3e8bdd3539ef47893b70746baa187f1c9a3	1	0	\\x000000010000000000800003bfec5db769b1a04b5016cf4865547f65f5252e43f52ded4126f82fc19f60fb2469d9d6aa45f25d81a6e4dacf68fafab94b189cf330ec18f3628fdf22d0dbe9313c747a2ac74d453652162a304cd863d658e4b938bd335df60d6d9dc50e3f872572089c4f5735d424ad0d5adfa7b83e640e9da7eaa4b2427e1e29e1cd61ee00e5010001	\\x5c3d22ea00bfe54f3079c50124b3d887686626f3745f0a8d359d9dba25f1120918d0f0bac934e90b77c6cdec696ff2b1ed2bcdc9d1c0d4f0a9451e6033ed8c00	1657884617000000	1658489417000000	1721561417000000	1816169417000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
49	\\x6354339ca89c35cddd62cf4ad4d204138054494db7775bd14449e55e3b5d4d233f32ad1781803cfb5cb24567b69f8749a82d150841dee0517879f2f37f6aaf4e	1	0	\\x000000010000000000800003c13c110b73802679e2860d5bb66c9222e67ca494289aab5bcac7684f55355daa126ac0a6dbec36425a2b78157729749237130d1a780e84ec3af290edaf5622418fbdbe1d8361a3ac6995953d92fa113e76cb22251a4d0493b0b6609d87caa7327250e0bc55bc8ccf2c397c6faacb7e77d7677eb284c39e4cb21d12c8e5312d1f010001	\\x2970be6107e68384a444879d52d016c9c74f75a813f5fb59fe890828ec5240142845cb45deaac33c9cb3354cd2fed650782d8ae90cf4d9402c6e5a28f265b30f	1651839617000000	1652444417000000	1715516417000000	1810124417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
50	\\x684cb34204c4cd86f25c05f978e23f16ab94f1e36d340cdb92410d8a0bff536a2c4eaa7ef4877b037db230298eb42e277589fe2cf6418567c4c46458913a302c	1	0	\\x000000010000000000800003b6a10ed6264d687398ceb6e3841571d213e9dac38ae27e8f3e60772268877dff8d2122c8fc997ef5f61ed6ffabfe96ac4a764ff1d7afacf5eedc4cbf0a02e643a8b7d07757f2fa4b832f579795e88561a564cc694777c30dc7ff1cf9109ba3f2237251a193a5061810691c48b4bbd429064ddd4db8546b7090d390df3bf44b57010001	\\x7611006bbcaa7e9fad7690e6bfa3c2b302fb5611b2712ed1b12c07b5c9e6a5e6c05da16ec0c7188fb11d6656f0dbaee6693682665a3bc879045c5ff4614cad02	1677228617000000	1677833417000000	1740905417000000	1835513417000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
51	\\x6aa0e59d253185bb3eff9828e5fa83322e3490b7e12fa1f07bee27672eb90cac79df0eeefec1a1b5b9930e0060e36fb47eff71b270a5b45f710031eb0f47baea	1	0	\\x000000010000000000800003c01ef9025b5b671f34b5d5ceee7305b2b00045ff30baeb2e11bf034ea404bd371437d5b3379433050b30e4777ce1cbd7cc9de661341ea071568c9cb3f3058d7f35a3f0e61a55fd0efa20d5fbfeab599d88a5af6a68b0b07eb35b73610c984c973bae2006a7b70f11305ffc5cdca1ba0133506b93222766dc883f46d899148c47010001	\\x6339edc76f5c8e9ecf55ea38e0d3109d39016b534ed6d2c7f52ac4a3abcbb3f93f4ce13defe4719f3f7a53d4d3ab631c524d4fb1eb4997ae9690ec38a03a7709	1654862117000000	1655466917000000	1718538917000000	1813146917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
52	\\x6e5c6cd739170653322230355ac65d872fed16b3d7895d69f49de902f8f4b8eed3a20ad77cbe10042326585d5bc6b16a3c6e3e93577b8bbdc2ec9e1e239437d3	1	0	\\x000000010000000000800003bd101d233785da0a1c702c7c0206808404971799284bc66ce6e3b0ec88f478b7c5e396b9ce9a45d96a445f60d4ca0106e00cf1c73ce52541b0700c120ea68161c397823ff86f127e96e6342132cecc22d563c66d171d3e70fe9644d27f6027e9514f417a5a7a6176330991087661a30b97eee3105bf87cc87a0ce43cbc77aad1010001	\\x754a647ca1f2deab5dc069bd09a76969e410e703211e359385ac78661f3a22f0dece0c8dd715ae7ba55ac69915acfa4614d1cebfd482dd464a7592d52c55cf07	1654862117000000	1655466917000000	1718538917000000	1813146917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
53	\\x6fccd99a8427761b02b889047d05e54eeab29fdbb50934e423be491dfb0be9f992cd4de37e452c45e6548aeef8f272635bd1000b2df7bdd6c520c3be5156d9b1	1	0	\\x000000010000000000800003ab73bb5c3d2c8a4e2638448d4c522fac23115bb2f91adc3e20421ef07736d9188d7343b41cab14d8e234b3a33c8c23643b89a5eefaee86636c8667a674cad4eba966271fbf4eb8790c8673be07437895f8e1b0fd9219b7abf3221dcbb6f40d62cac1c5508b3ed98539b25652ac1447c4c507781ec59e35e5d650ff2b9fa7bd67010001	\\xe72e709ce62df10589ef66ccfe7ad9613e552029beb0110df42fbee1f88d885cecd0001f36825dad4596a73dc4e27eee9838368be6329828580faaba5751b607	1668161117000000	1668765917000000	1731837917000000	1826445917000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
54	\\x728cb897060300ffade26cb445b560fc7d0cb39377597a1d0cbb52eb48bfedfdcc9067cbc261130131ee24889e26e059f0f4375bcceb49d1e9964e54be1c0688	1	0	\\x000000010000000000800003d41d64b3d2740f6db2c685f324bfddd37aa95848736443ea8dc6d77205281089b6693b27f5f11b10f4f0f7f54a5c076ac68c401325dda97bbc3d5244318ab5899d8f9523ec695c0ba2110fd93061fe4c4f633dbf5d6bc5ca13bc0b177008bc0177e6d509a7f991df87fcf9ddf370f41c5e3ad38cdb57a7c263f2ef385a55edeb010001	\\xbf2cf4824c3376bde023d9bc449557933a30f42f4bcf25ed306f41b93f0d9089bcc70d4256eacce6645e724247b82d1d9ae45418cafa59a07a7313261c8daf08	1671183617000000	1671788417000000	1734860417000000	1829468417000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
55	\\x7220c2298caf9550012b19c116ef5e19f84979b30182ecad4359f0dd2c622458f9d47e12c077960dfc5a3f03922ac31559df15cef0c4043854d58327965288cf	1	0	\\x000000010000000000800003c84d9537ed8014f38ed76595461a10483166464bca9b1f2ebbb43cac541c7d663bf463214b5f4a8ba4c77ff7e23f65c9f89fccce948ca2773cbca493dd245600ee4dc931df092debfdd263c3cb0aaaf1e6402c87d0102688f9775ce4444f1e44848ddc331959abf7a706fa5eb7f0db8f7ba4b0feb7ab8a13b48b947b3ffd0967010001	\\x773cc671113455627f2a716bb6feaedbbcf1daf79bb0c17e05cdee64c59ffd2d901b2b58e04626c4afa8acf56cacd188d371b535854089a839996c27444f860c	1653048617000000	1653653417000000	1716725417000000	1811333417000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
56	\\x728413043758a3d52d965176d2aa192af81843598f764129e3c3625e264373929ca8c6860297430f96fe3eaa2e163088e18d58792a634d9b393d22dc718f2c5d	1	0	\\x000000010000000000800003ab00b6db4e3f07e3dda1d81f30ee798392007e9de7508cb4b3937867f2d774e0ca1389175675e5fef0a7108ae5591b1ac68dd203be6bc812bea115413f8faea45cca3771577f3cd921871181d64bd1b01f28ab4f2683aad138885b288000ee69e342c9f7de80325f65cfb86eb8f0a9139c9f5488c7109957dd032016961b91a5010001	\\x17aa2a18ce09e15dba3a0efd168679b42e5cc1c898dfa2f055058855286514dd89d85f166c0bdfac5554afcacca8f99f3d05bb87a7528417f1a3697ee750ed0d	1671788117000000	1672392917000000	1735464917000000	1830072917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
57	\\x7338cfca8d825c71f35931e5bc321802ae894630af3a8469f4d1b327f8f3852d2b9683e446595e59ee8cb20ce7be94af9d0e8948fbe438b175af5fd7f284a7c9	1	0	\\x000000010000000000800003ebb9d3268a8e4eadadd3cf24aea555ad3ce6cd0af7a399611cc250eddddefa39beaeb7b1e2c9387a2d497db7df62f13a6dc51a6c815446d18e21c57fb075fdb42f2bb9f514b157ac936e6e8dfb8ee0f8d513c3275d277fc337c16ce3c23770f3158ac21743bef4b527d22df37665ce3786bc4a01b08cf689f6c742878c2e99f7010001	\\x66d567ec67ee323214afd07d076273879f2b4182601cfb82647c75cce7e07162e98cdc4cfbf6f6f507e34fac6e0516fea9ff4733e913c829d1489fc98ccf5604	1672997117000000	1673601917000000	1736673917000000	1831281917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
58	\\x75dc3e01beef70610fdb74b8ca0dca4ec01474a07cc365dafa4d46f17935081972c720eeb30cdd5cec0b4246b420d6fa69276e29cdd51646b5bce3b58fe82688	1	0	\\x000000010000000000800003beb10ba08411cdfdde81362d84a5da3a775017112343fd33815a383d443af6dd33585a63f322926d7e8d7969df7f69cf3e052cbd0d58a5aa907434d9a9d6bf2d06ce99c6a8b5cceb5c2f021d5faac65dc9cb80e5497c7409c3e96e2c700c875541b723f6a8ed25a6309d516d5134f757138171e28d053582cf01635cb40a87c9010001	\\xb00634ebd7b8f5e788a0020cd8d14277361509334f5aa5504fa77a0db172aab35b885b782e5ee439fb30cc990c88d9377f41dd957e63ef98f7994806557b210f	1650630617000000	1651235417000000	1714307417000000	1808915417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
59	\\x767c5fdfa955269998ed79fee43b7de49e0d93b85f579f222bbe0c93d650de61672affb6b6acc5ec90b2a0d087ef2ae7742a6db04286eb8299414f0f4c5ad22e	1	0	\\x000000010000000000800003c79ff91959a6d3a79e7e6b7f800a78a07abd0a2e1ab95d82304ef83b7d8adcafdb5731a95c341d513546b0d85f32d0b5ca491de00c8961818008086c3eccc289366e3d1cac1e1a2145e8c49a6613621bb93de149d88628ac50c96f62e0a4cd6faacaee0a12ab4e7083f2c9ad2b47416794ed7c844a22f3f8b134ef3660a227ef010001	\\x45c85b898dbadb2c33416f3eb80f459faf9ad29da08f5a11ef768a6236cc1e1327a91d8d32ce0371db4b57a2552282b9aa622988a86cadaaa35c35345990a405	1656071117000000	1656675917000000	1719747917000000	1814355917000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
60	\\x77c4807b18df08d97a3e569ac8a574a71a195f841164f0efce26f8aaf1e7dd18a6a5e1855b3dff5c6f7ff3717ed768948414360a08a74b08d81907bab88d2983	1	0	\\x000000010000000000800003b455711b43d1166a2e10c699278f09843b16ff21594d409d34badbee8a8f7039e1b6d7afa398f7c306bb152840c1b75d2c02cf326667d2271825ff480db47a8c2ecf8cb3fab2ea8fe7c62477839c3cd1261fda703901b9903ff74b3e170df0ae6de18bc2c645e3507e5f7ecd7d2c35cc2bcfe39f5a4bce5be0b2beca76fc718f010001	\\xa26908ad3a145d4faca914af975aad73922eb36af5d1b5c3a261d4dbd75f1cb21b5ccdf8299656388667118e1847147311a757f2870af3c470db3658e8f37102	1676624117000000	1677228917000000	1740300917000000	1834908917000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
61	\\x803c024316e01249aa74b4de9c6f5c610d81b63b99c720c22e8d5903694ba99ad530750257a1e2d01411e817aae5996ea5d8732ea57699a11cb5ad3dec2d48c1	1	0	\\x000000010000000000800003c123ee555f2ffdf3633582eabd8afce0f79c57adb96c586fed6ad31f6298c6431e0be208b711f8082b700668810bf8e50766ffb8727455475122ec9a69809824be13e999dccd41c5cc5aa9c1b7010698ee68b884339918e0eb00d47698efd1d43fd0bd9b8bbdab38d78ef886f17b7d9e93d75ec426ec4177c09b3a8c7fcf854d010001	\\x5a6443487e66630d110d72977abc489eee4a17c40ddfbb92a12d01dacc2ea55b6b57bed5ecde103fd4c2031062435aca0a5a4bf70ea4dea104d3d60602502108	1650026117000000	1650630917000000	1713702917000000	1808310917000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
62	\\x8274dff024a145031b4fa06a179bdadcaf031b88454a2d2c410ecc55a79900a460b835b146bdadd4b412daaccef6155968fad739358131c77fe23ed06e587914	1	0	\\x000000010000000000800003f48b1eb0bdd4f36ee40ad9cb881afc9bc4eb63c3df960e9ef9c950c57aaad1fcc9e135497e35999f333162c3468030d6e4203dee39ae59fc2555e95435b4d598fe1015d663ec3d70eb7c63ba83bbfeb519242807a761ab065004d085276ca5c1c8f641168865d8782b4af1553fc9651f00a19da7a2770cda2dba2b8f6e8bf9b7010001	\\x047affddc753670c9decd9d4f2b632445919d7e7ee1ec7b9f50f9a0d5ef0a25a2b52b4c5a9e35b9accfb83eb592e175ad7597ab7e71577a6f0b3a4502a0c5303	1651235117000000	1651839917000000	1714911917000000	1809519917000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
63	\\x84dca8bc99ac4bd60b9145e1ada8f6988c452b00e24255638bb4cc1d33af228221a53940f4dd534ec66ebdb4dbca08c64f59207c84fcbace12d0110a9b56b392	1	0	\\x000000010000000000800003bf40eb0771bad3a898fa9bfcf546ab7312ad2908b5992f468a1534a877ff11db49222484c67b1a13aab2e4432c34144c0aacbfe1113f2ae3e93c5f115c4589463b8a5c05e8b37965a684ad3614fc7914bdd34b85d5e4b8e3bd0c6bfd08f1fe95e563f8b63c550530eb2069c0fd32c42c173e69746e354cafbc96bad1d11b0979010001	\\x1c733da0d72dabea698c3ada30324ff5fbb9c40b02316e48823fe8ee3cb9f9c3b67b44570031d51644800dde1eea09336fc557b826eac8d01981c6999b17e706	1648212617000000	1648817417000000	1711889417000000	1806497417000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
64	\\x8464868da78f9ae31f41f62daa1e64ac6c967435fa678ebbab1697c6b701c6f401a1eafaaca69c07ed05ff23318f2aaeb8f87368504a37d062b9278f12ce4a33	1	0	\\x000000010000000000800003a0b1cbcd3a7ca122a3e7ffa3f157207822bdb670b59ea4655876b56b892d99979490a4a2f0c512fb135edee40323913c4c3c2f2e2c7d484232bd4d8f2b1d27b8f6c5da4be4d77660abba797da10e85ffb44a78c41e9c7c659a2969a4b3d05b570f753ddc3af1f680a15a8e4c9fe055a81e2318fd74d5875ed67507c065396569010001	\\x0b12e847c096972c4f4fc346163d1b1f8321761c4264faa95c01e8c14356c57575585cc620c203ed014064d21e241722edef416b88ae008d5286674b08f1350c	1648817117000000	1649421917000000	1712493917000000	1807101917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
65	\\x8fc8c144aa589ccb8264f50ace8eb9196898373c495ed307562ce2cf7050467e50ed5053baa04d3352a0e220c60e0ba66093ae6e3f82554dc6420ee926825214	1	0	\\x000000010000000000800003da3cc7730ee62aecbe7cfe8743c38a8bc3d323df4ad0e9a1c6eedcf5a20eef27e6bc195ae6ecc23fa6ac8601d7bb27ee4578733293b31228dbb33794084599271c3c00a1f47ee573721326522b02ddf3dacd4e11d732cc5f7910cfd8a3ebc1b0a581d28cf7c072bf5edb41ec2c9ab0e986629d1a4980dca7a1a2abdb7dd501e3010001	\\xbf7c94b3cddc1dbd95e634431a937f98c9f2c335c76a2dbbecc7b8a13e40fcb55829311e6f38cf69a0389a0c7adc1ddac898fb068c1f6ca648f407d9e0483809	1659698117000000	1660302917000000	1723374917000000	1817982917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
66	\\x9094a955478e614bae6c0ce0c3a99cff1ac1a4ad24c68744958d60158a1985716011e6268a522a84559c67213735626e8eda8265a68ffe87bfd6b876f6bd87b2	1	0	\\x000000010000000000800003b49a08a695418e20bc737f3aae56c28db3acdaaaf446148535b545f8f7d8984545c4c50144ffba805dc29a8b080420fd2077b83ab40c78c9e4765ab71f154f3362ec4da7dd785d6b9ae86418d7270e81435f925bd6d2e6a5f3e1a10e6be5bc71f5e187b2baf733943dccc429250cbaaed62dbf2ea04a3c33fb2107439882f603010001	\\x85c8f262b13a023d00c394a0a6e62f071f08511db2c5f6a4c1dc8c03520108f021dd04bc7c8d9eb1961f150f9a7c2047317b2bfc40d48f0e0527997b4e10ed06	1674206117000000	1674810917000000	1737882917000000	1832490917000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
67	\\x90b42d227cb952fe924d1cd420bcbb412622568be30a715ead7abd91d2ad0da4d092c33b1bd186a9a7fbcd5940e32d78c37c41432e1d3d3293b9edc1d17446f6	1	0	\\x000000010000000000800003a4705e2e6af990841ffa726f1746ff4a231e0ea54befe129b8c513684aad9e2635459a385e4be7f25e1e69bbf1faed8e0385d4792662719a45b3d3c36160aa0c1b7cdabaec3003d0922551f691c4eee425744ad3db964ba95377b941cc038b5d52e0da8ce7f28367f60df4d1c7e7bf8490e2eec7a61cb31a1678a460e1ec96ad010001	\\xae5e9b7c285e799e39ac2e0358072c275c012ce78aeea28c3463b7451284bb35c09429954b9c8d7425bd8a2490751dde567190265b14b0d69f807bd26e45b80a	1650026117000000	1650630917000000	1713702917000000	1808310917000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
68	\\x9558982e2664ab1a60a325a6db93d2989a807dfd5a2bf07c00e0f3b2d14086f5f4edcc35076b195f3c058a8dbc54af0373aae27550efabc84d919f709948c1b2	1	0	\\x000000010000000000800003b44d177851b6b773a00ff90e90673f1b887abb7e4516edf3671414dccacb6868fcc606022b35cdab2e7826d1f3da468e7579cb663380658a101558471e693d6281182d0d8e4d3b8ed8ee59b4695be9359ad3a5980c5652184d8d16b02955ca6c0cd908b0fe7b52990ac8d0949988516da30f6af3194945f110d17315ac3a1441010001	\\x1b6966c8b97b79662e12c8e8c43208c5ee55fba054f1c556279a91d3c915c50b17e5732a5a8d7acb248d5d6f8f62d8e2a7a83d5925f3371bc1e995754a38540e	1676019617000000	1676624417000000	1739696417000000	1834304417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
69	\\x9654716f8ac933464d88efa2f024bafee160c2aac5e073d7c62706c5eace45059d25df4623848f4db9bb13be8cf5b1ac32f6e468da7c56b97a167f520c147525	1	0	\\x000000010000000000800003ce5ed79633df89b1999814650b966e9e3285c6b2b885e097542df9d1e7e6b3fc32566a6afb34bf4c64646d00367e76e0611f93462eb325d8961b73216f02a155f64ee656d12150a398da0dda7e6f5fd57fe488fa63218565c18b0ed476207e4484cf67d966f82f096b9fd829805056428466d9a59a7abb3789ccaf593b4d2183010001	\\xd8d5da609ac4f7c5fc8235844ac8eba4d97caf0634fcc38900f308ad3e55c157d9559ab53c42b8f1dd2a4fa3b8211c14524a13bacec858ebd5ce4b40e44c0703	1649421617000000	1650026417000000	1713098417000000	1807706417000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
70	\\x97cc61ae716eef17f465fb2168a95094fabfada1270e99db292475477bb20551ec834a8e606b135b1f6d2af8310e11abfe2b257d417d718afc673e4d5eddc797	1	0	\\x000000010000000000800003be652cb7c1e2c375e9967109eb55a5f8e944dd5f8df559e7ec5a85ab1963a40568d9abc3f69757880c3d630cab4323090f58193e1c1ba3f0aa2c94a2d9e7dce160805d6e1bc823306245324cf1c26d2b79511a4ea82eb5b57a2e44b9ab3d38af6f9389b9b7a4ab66eb8c13454e7e6642cb9d610e4cb9a9dd25ab5692cfb422fb010001	\\xe0bc1c2bc57c3d9e88fbaef86daf4db444af3325563bc49b3e726c374c097254785630aaf12e098ecf9688cb8896a0a56f678930462e41c2019655c00f05d20b	1672997117000000	1673601917000000	1736673917000000	1831281917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
71	\\xa244b85c555e06aa87ce22e13358092fb2adb735ab3f82d3312221a0f2f41ee7e7a9e84d9d8137315b92b50fe3a3f0f717424bfc5bb5ebeb14f711aa3cf1d3c5	1	0	\\x000000010000000000800003b159e2c66ced09f728a12310f1e0609e720e46b9294eb49f5760f1e78e716e870ebf24bece6ce090b4c57b4d569ddfaf43f9b167e6cb1d9a38304f4427e733a123f69707254a26116f984035ad4daf2168e498bfc4462ba9251c3bf82e4294b9993a3404504d6cca60a9a6cede4cb2ad8e12496fdbf3331eb310463bfae3e1d9010001	\\x8dc3133caa5d7450eff60f581058f58558ff780e5d9e62a9a50541d03eab9b456f532ea1273d10ed787c5df2182dd9dca2e65e490d6238bf902a96a977dd6706	1666952117000000	1667556917000000	1730628917000000	1825236917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
72	\\xa3d0517c32906cdeda5d120f8b9412d2a5632a2957fc1e65e9962ec901fa803e5876652110dc775590c1de22b037bad014923d20c69eaf0e2d887ed52a2ae959	1	0	\\x000000010000000000800003ca541bcaf3c5df23d2089308c0d140c77d83bdf9a984852ca722c73a12097c1acdb3cea265e52d3ad934cce5217600b5cd98310b0cf3a7708e2af73537800368c16055162581d3af919077336b2b43282c86beecd0eda6c487df707b9bbded4e1bbbae44f3fd032437d2d38a36f6ba080fd3dc50545f26edc334b20e7eb586d1010001	\\x0e60fe44a56fb0bd2f2461ad89b89944a5696f714500f0914ece08b64fdcf0c21d24e6ba127ec392fb8ad1bf064c0ac78efadfc9b914aa391036d193a4fff106	1650026117000000	1650630917000000	1713702917000000	1808310917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
73	\\xa5d82ec34b18530dc6d86544392d0b3c301aa410b3bc6bf24d247139d7497b207e82ce95e3261a5a67ad19a135dd5f6d5314699dbfc31f0cfbad69fd76c97040	1	0	\\x000000010000000000800003e758ec3f1208f0fff8972e69273330ca7411fc517c25ec18bc62bbce30cd4d4cbf78f32e3dca436bf12d9f8dfb75f93acbb184fc782b347d1fab3696a07a8673cb13cbef7f959d452044d8212eb25a19e412fbb5a70e0d8973a59b78a66a3452663377e6c0584f99947b2f656f7f7b7d5caade9c8613be42cf5b07b635d8dbc5010001	\\xfb2e315d63bea55cc6b4cbe4499c878ddbfe4ec08f97ee0e70d5da2f6abaa419542361ae07433a2ebb8b0d779286bdec53c8d9578a8d17bc4004d987dec8d403	1675415117000000	1676019917000000	1739091917000000	1833699917000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
74	\\xa6fce5403fb7d5b51c8ebdf50baf59ea18fe7a1db115d73c61dbdfcad13bd2c31858da65d7b17eddf28cdc6b8c8ee5bd14a0a641822b0fecf95e0676318ec8e6	1	0	\\x000000010000000000800003e714b461709e0f6e84aa75e1106a928db24f920169183dc4e5758f4d4c72073e8564671914f1792b537cd0cbdbeea0e16526dcdc23e9aaf31469ec42084b180925eea9f6e7078fe81dd4df9d5892ae4b3da144c9c070c5dcdd512cc9cec452bace0e33119a7c2b52ecd079672490e0ff474d77db4e4f453a4adc2d29022aa5c7010001	\\x502b1449d4be94160a4347856866523ef540b28634897c7114e54b21629ade8d223c9e28982be7a3afb8f7fc111f302a9a811e4b8c50645c9e87f767b9694603	1662720617000000	1663325417000000	1726397417000000	1821005417000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
75	\\xac24eb984398c864c2e5637bce9c04ecf13501462741fca1437f9800ad85ebd1dedceb31ebb82c0c85e5d4bcad3e53faecec196a28a45a74006b55b3c000e42f	1	0	\\x000000010000000000800003eb9ef0245a4c53e9fb46c74879d688bde986158adcf892515023126c1c1ed673b771ecf8c3bcb211e11d4a3c7b61173bf2a634fb7d8a293f189d1b5ed7cd856702c18f1afc91bc1af5d4165633fbc52af3cf4cd6c72f4f72d1f16087892e5ee89fa42dee080d121f0a5d16d3aac2458b677fef9da7d4e4d7a935bb4743e7fab7010001	\\x95d462d207ed24cdbe0c92563e4747724945ae26a403d746a7976efbe9fb491032f4629ba2722b7b64098246bca9bc418b8cf28755617afbb2c54f9d36289800	1659698117000000	1660302917000000	1723374917000000	1817982917000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
76	\\xad0096d8de6920c0bbff2e47a067ae66e391bc989b652a974f8041ea860909c9e8ca20d6c84531a6706768b6946a27fd42d4d0a11ae49202190e6a67991f1b7e	1	0	\\x000000010000000000800003ea3db24a25aae023d7bb5a43ed819a53119ec02d167bfa4a38cc20580d752d09dcf6d7289db3447dae2c6f96ef367f9dfb370a4d985134dc4714645c8a4b5c4ab8d9e638dd57dd2a27cd74cf87d812fd52b8e5baf3b199afd5a84ad7dc4e7874ade4abfe1ae03eb6e4f65eb0bc9e98d89cdfec8513c42776da2b9f07dec41059010001	\\x60f6032e66c55ea0718a2cf9f1ea735e4277395a5e6380fa95a5635afaceda53d9c506da6e6e153c1c56181f25ffbc62eee3198f278d9f7c06c039370bad140c	1659093617000000	1659698417000000	1722770417000000	1817378417000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
77	\\xaeac94ee8eacbe919ca74df2d00e75c3ff4924810538fb4e31ab830a8949b37f7902a9334ac49ebaf7b56ae30cb9a5ba659b5f37381ca01e6b326bfbc937f445	1	0	\\x000000010000000000800003dc9c1113879ceb648b922a0fb4b8e72d9c931b8a90951141f0796bcb9a4d88c9a6d680646f72dec63bf8c82309d7af480b182e13dcd92009f735b659b1e3cae5ef522c41637a384edff0e951be9b6a1785ca083db7e07aaf42da67a3e1fc45fd8e79d35e20228241d12b70e6e0ca7fb20f5ff8a3bf5454466b20e00af5dfcdef010001	\\x83acd361e6a281afafca7119c07d3c6674cea93d71febfab0ecb20f694a443ae5c0cd64439947a740a9979b17182b8883f8a6d973cf98ad3f1b358d1a8d2980d	1651839617000000	1652444417000000	1715516417000000	1810124417000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
78	\\xb050a225e9f64a79bde545c46f5a782325592aa264c10c93c9ea803e98fb9ece6f1672cf486b197947162aa12bf789bdb6e3f30e78619df2b5bde31ed58959f7	1	0	\\x000000010000000000800003bf51478fdb2a30ffe54acc285f7507a95bf53b273251423cb290e44db37d508da40a50ba8b76d32d9293e9ed284c1a4896d2d8409812a0f1eae441d49612e9be6a9eb661802ddead6bd404e4385c3ecfb5880e1214727a3480d95b733c013a8a591f78ec88e09deb5d0ef7e2a1ae2c52a91bb3def0b50a468edd0795b5395a37010001	\\x7c9e569e25d601307c330de6a368c3924ba3beff69476c691e872e5a229f33470ab791f68fb931a1675bff4c812674509620c421920fb5ccd9580b4b6fc77d0f	1665138617000000	1665743417000000	1728815417000000	1823423417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
79	\\xb1809eace03d2e24e103c75b333dd86b738537c48aae882c9e76ea4b257e94104be81e281e9e2f2a4e85fa00c8adef596ce5eacf97b8f6f66fa5a31f705940af	1	0	\\x000000010000000000800003e18db00f114e7cc537b94498ad5217132efc68037fa84ddcc454c112865d68398d469674af61ff55ef908b14e491d3ff6ad324682bfee9e61ee81597db4a5fffb5b56c1188d882822a6121118c40e5f60bdbbf3600abda84748f54a87f1b9cb60a2d8c5c44ddcadce79e58ad5af9a3adf89e34a39d78d51355d7ab81db5d72cb010001	\\x5de13c850d8301ae44adeb3778b0787d51c81423f6eac68a28a792a59286a774a2ebe98aaab8fbd55df9054eaefeb762a5d062bfac18ab95e8ba043764b67408	1662720617000000	1663325417000000	1726397417000000	1821005417000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
80	\\xb148a46c651a809d5e6bcf4374e1239945bea931eddb549dcfecf845d6e382d5ee6d81e43fd529e122ba202653cc16eded2f433c0cd46c9e8ed5f5c49231a9d2	1	0	\\x000000010000000000800003d9eefeae7b2a4798f31bf670f3f8ef99daa1b710aeff36f22ed71360ce6b3646490b045764a0978ca1e5ac0a701a63d9c05cb920902ba6a8b0042ba2a2a5f08c46551a1e529cc603beb93277dd4aeda495f14cf5a1e88a1228a52e746c1c12c81e3c95ac158b32b08c34596059fb348b71f4ddee65a2905a8bc2d3093569df4d010001	\\x47655fd780689ff3f5876cec47fca52266bc190024458b32a98b4eaaa2f17e4a3109fff519a19449e2afc0c3cf5cc2d594e7cad76b9c9b0b80682cabd90c5d0c	1654862117000000	1655466917000000	1718538917000000	1813146917000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
81	\\xb304f0fff23f46e5f938291376c1e16460b83c0ce214b00afb62d6ac0958abf8d3eae41daeb48ece371e70240a087cf23f51cbf189d58819b50f8296435a96b5	1	0	\\x000000010000000000800003b79a5c2e4be1ece698984e3b79ff876fe1053280818890e942dfc1becbefba82e3e366b5c2ed127b9545372f1843eb66a4ac1402924800246466af8cd8bc5bccdf2fa54f479aa32c4e6b77e4d71ffc44b621f6392d324b357a85ffcd47d717ff857abf9c581b2bfe4fa95ef597b413beb60eb2e72284be4c669fba9dc04a5df9010001	\\x0605242a4132add95e9a414275aba7dde903a7699edd52c3d91595b7a3f538f1ba33da96866d7520bfe0bd0ca37b67f2d93435ac71e85c0ea74b15823572070b	1668765617000000	1669370417000000	1732442417000000	1827050417000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
82	\\xb62879b5269ff1a93846eb63d0d0b268bd512982ecf3dff294470bf6cfb2d6c97676d55fd61cf34d4fc60563a47d22abc4ca2f5cd495436cf2ab27e35fec4cba	1	0	\\x000000010000000000800003be25e2d59abefb4b8c1b21e4b1c65236aca3ba675f9513cda91a445249979257100608535b7aad2c29efb1b3270ade5d267b6f1e1598a3255bd596933efbff16eee01e0c100b648695a4dc0e4d0b280f5f5ed18edaaf402f3392e31560b05c87c98b59256d37152dd70876454329e33a982005467bbdc765a9e04b7f89aa5d2d010001	\\x8395c379395485cc2d202f438bf12711a1145d6680339e18c323506ea12ea1b6cbd2df57badf6816cc7549d1dae13fd8306e1ad90ec18e99e476211b3abc0f08	1662720617000000	1663325417000000	1726397417000000	1821005417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
83	\\xb70092751928bc8fce64bf2f5ede31a51ed27ab176cef2b125bfae8e6d17c1678fbdc306f644cdbd3e54d237c6bb1a441057fb390abe15f9dde72f5d761ea74b	1	0	\\x000000010000000000800003b7de3bef6c057c596424304365464d385065422f48378afec9c49a4e4339c76b0230f733c903a3b7c82a4e5bad5b4e1e2665bfff0d9443c1bf5e458433f436a48e83cbdfcde000ee99e280f175f6ca2826831a2c3240514eb508a09d819830805cf38ff989bd637ab058157a993a07bb15d20a9df193bc8bcba7ee787918b1e5010001	\\x857584ef8857482d9858b55a10e521c64f0e612fd5c2de60c1998b6dbf275f8c8567d303ef30a1e568d1694fb1c61b3bf3a06a77b387d689c5426de5d5f3b009	1667556617000000	1668161417000000	1731233417000000	1825841417000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
84	\\xbdec6b2622a80edc246a1e75a47baada0248ca374fc53bee2e234950c0838af6fb23e0a0104a74c40b62ab395f7815889ca144704f17a3c2722bc4cd55ad475c	1	0	\\x000000010000000000800003c5cc4d6f6189f2056d75e6daafac85d93773f8dd93020a7963846826a18639f5de22fbb28f13ee7cbe4ccc215da247b070d34e15fd1caed08bffb8be539bfae7b2f7d77515c17fe1dea3b194c6b8245a150c81c5521c669b04a9f63c2538ce7928b3862977c47332a4c83a87d40d002505892f1147a9abe9ba84a04c046b9c99010001	\\xa421b5af501cec64e3633325f21bb4da8ce065f6b86276b9d6f455499cdd38ff0e7f6f998d0468b5efb90d0bba0e9055cbab6076d2ed003d646d0b7255643304	1657884617000000	1658489417000000	1721561417000000	1816169417000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
85	\\xc11c16023c8432534559e574016ea272632afae7cc8878e168b52a2bb5b2f7393eb57219b27389a91ec4694d15858ef52bbee4e310dc409e18a734ed083f8393	1	0	\\x000000010000000000800003d2ec8310c78bba0c732da59b8f20de140cc1033b704f959caaa6179016e86bb94eaccadf75fab05d13a426942759f5ead44b55e510d46a49d33964fe834afc4513afbddb37a1b44a5b5ccfcfc99320827b12a4dbcf2d9e96ecc7090aec79d0428b9104978a3aca8c55dc5c9afae955759a6ba382bf8188b24f7505d5811db8bb010001	\\xfad5ccc8189294ff0219bf9becd7f49cbcf9597576e985d3651544028560f2fe34b0373a22c252c8364f354bdf392e7985ca0ffa87d8c4d22a2de7336d680d04	1666347617000000	1666952417000000	1730024417000000	1824632417000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
86	\\xc40c684877e390fac6b29bdf72910c1b1d8195105bf8e6daee04f63f43d473ca5932b614d5b5fb624e251ba4f669e96081a64500b7d5d5b7201081b2a6cea5c7	1	0	\\x000000010000000000800003c4f1ac2587cb95b12ac69e1a6b974b80f0c8335d7cb006c0abd83a54a3b9eefc61dfd736b54a5fe829f29191ca6a2f14b68073e8552ba5506880465d33b8a765557ccf59014147cf6c54f8231297ac553a2055a7748f4006d34c44655c0a8393c8b12f7dc58a0ffe293d64b261a872f875c4744f75b8111f00a39d14da3d9fdd010001	\\x5c03eab7d66e5fdfaa20f30e6b0c48ed0f18e9813007bb07a062467810e0fa95937ac08daeadb702bac3e7ef1064549dedd3a7766207fface5d3aa2115674e0d	1668765617000000	1669370417000000	1732442417000000	1827050417000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
87	\\xc43c9137d19623a0985b0e9933066a3bb73c45014ec640ddd8ef8aebd1cc3662c6fbf8bfc26e7c96331b6bdbf945b2627f3224024cc7799294aa2b92ed5529e6	1	0	\\x000000010000000000800003ca5981580831988dd75322745bc220925306f03ec81b4daf030ab893f42e49c6959b25c3bac206edd8332f2f3e021c6c580fe0cf8466ce30503513c0ccb8531f9ba867ce45e6a13fed106debc71fe55f57979d99d29925c6f088289a0fc689ebdc3c35a0f2323225ba5ddd037d1ee97fc85bfddc5a95a44e0b355f16728cdd47010001	\\x33ac640f1f5237d018a0e14ddda4eec41a98b4e853f2acf902b38ab8b3349d37ebf249a43afe1aead0716a6ec37912e8a5597d824ef400265fc76c3ea9db370c	1677833117000000	1678437917000000	1741509917000000	1836117917000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
88	\\xc5803f0d86b88fe1b0100fd3a587b2ba3785cbef6d6b5bf7715d605357a17e3fcfb911a46e16f1b129b29ad7abeed6f8c6d9db91610a4cae817d7a834dfb675a	1	0	\\x000000010000000000800003ab98fae6c9ba99b47ecc58e8e97deec5a26519b656f52b12a558656049e2854b2752a4a6623a24d9efd213388d0284e792cb771c5a1077ca73f1f8a4568038be652e33a0cfa7e57d99c3dbf1feb0574febe445deefbc767b1e9bd407f2c9b35d69d7689a95e05c3e276221666e3d8c2cfceaf51fb1783071cc24ff1471bf837b010001	\\xd3486cb744feb943081484f42ca5524e448263ce1c77816cd0fcc6894252078c7e19a8968ac79476ede839e7321e22c1d3ef6ea7255c7b2b5ec750b995d2450e	1661511617000000	1662116417000000	1725188417000000	1819796417000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
89	\\xcffc25706bc1c5010673cafe048bbe6ef899b4b61d7513875ece81054f32a571d73edd72295fae884a55f616cdee38bb91babcbb357512d9d293e23b8bcde55a	1	0	\\x000000010000000000800003a837f1f9bb9f1633e5bb18d19bad2afad06fbaebc9f8ed4cd0176134db841b051158c32f61f0300618740840ac909ae5c414d4764b88e58a2a948c96807157a22375e9951777ee0ec078ce0c4114dd3eb1515e862b0ddb81fd092bb7f546c46190fe9d10de178f124b647fc108fe0549a803d9b1df2c9d90ce8df98a2721dad5010001	\\x7430f9fd54b55fbee1b68400fc93010c7e65731437a15496b169f3580a0da6f4c675919d010d5333ecb575fe06356dc3702ee924e7b446927cb811474feebd02	1655466617000000	1656071417000000	1719143417000000	1813751417000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
90	\\xd00c07a3d2b5e62c2ea31667e96e8ab00a83a770b378861f595957d4b43e0bc83eaea14ab099410151ece7a4e03be6cefb1217907416726ec68c54801b3a434b	1	0	\\x000000010000000000800003aa659be1773b9a2b41b3b7775dffc466ca87771bb1cef0ad941d06cd245838ae43fbdecf117d50cd356a4eb9788cc433ee69e689fd643292d4e5a06fcb49ca637af3a6bd9901ac7c90192ee07ae0959a1ed4c3d93d9045e14ebd8cef65269d3f31b6abd22753413203a9e4e1c90725677cf0d5440dbe93fa8b21a6cba0670ed5010001	\\x140aebf034c1551ba334900f4b057fd3eb298f86bec3783acbe91caa73c294492bd3df983a852c65cd8ad14ddda5f30de28c8273018d8f927435057db785b003	1657884617000000	1658489417000000	1721561417000000	1816169417000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
91	\\xd15c27c5e8c141a5ff20f4cf1f431d811e89f57d3aa8a865a5f8b89085a6f290909082ed52934ae411e9af54ae536102731ab49a48db2b217ab5605bd23be103	1	0	\\x0000000100000000008000039d5fe7649cb7924c23d9897e04650177010e041718b66f8455b0d1c5edc882193a22964b97e7b868e734963d90e17e6d81e91219f4183fb8ae3ad764fcda015f259c7acf624d85c0aaf0f50ce301ebd4bc03987dd521f884f401fa1cc2a9fdc2aa524673912c7ad76ac3443a45f16cd6ff6d837c153006ce6f785b71b7ae1ea1010001	\\xc3fa48a8889178acf754dbc99b92c050759acc3b4c4834c360d802bae18578d60ae9721d1725410c5191b50d39cb5ad9c9873a21fed81c43668c3bd2a8d08109	1666952117000000	1667556917000000	1730628917000000	1825236917000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
92	\\xd19c298b7795b0db6ecd187e9e5ffcbf9e882a7923ce98d341707d323d986c9ec75d20acb28517b8ad892ab3670da381c7e6fdd872071bdb0786018a1923324e	1	0	\\x000000010000000000800003e31ec2232edae77ef765f50d94b38130aec2b941f01fce556110d8b6fd6ea9b9e37c0b3f75cfa8d612cc73b80aaf938227b1d230e37d1406e9b0bcfd878daff0a3ae6e539c03f459651fca2853029b1c9c48c16a4588298c3549ae1c7f6bbbd9bf03da7cc016f0fc6e4fe55f03f582950e347751a716616790bfcdb66c1f32b7010001	\\xc52e4f66975f30048b0b21fb0bd4796a5953707efc813f5bed23970fe6b201d6f441070833d55a312d786934923fe338855cffb5ac6f15b76987f9ef1dc03a0c	1660302617000000	1660907417000000	1723979417000000	1818587417000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
93	\\xd44c5f753f3cf2ab27dd095577bced6ae5ee80e6d783b8951c258cce1594953597b1e71febbce7c3949fed04d40021d55b2c5ab80adf3fce2de87b1ef4bc710f	1	0	\\x000000010000000000800003c798ecab5d846482e55d64a934b4d5d476d9f8a3e6255edec4b2aaa72e2d52b81b2ec4d8e2f38b373287a9f12510d13d4c6e78cafe8fa03f31b536b2296f7718a8f2cae907cb06eb1f59e7035328d086f31da71be6a753a55ecd55a56d8d29cefac0bd6ad27291b4b600beb99510c66d2e0ee3b82a0e8ce5ed877847e1020bcd010001	\\x7a7ba7a70b5fff474a95c3c05383426ed85dc4451ace920795dee913efadb6facda43c96cdbee13ec3b3b83f39bd5bc419ff404611dc0efd055c314e8fc4ca04	1648817117000000	1649421917000000	1712493917000000	1807101917000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
94	\\xd578dfd2739ad3d668e8f4155b8dd96238d3bed03e2bd41869a9218d0326e56651c029155ed2e48af44fdcc014d6ae711c18bc57b0e96570a76913e9eea05137	1	0	\\x000000010000000000800003b61d2fb47840a0c582b80ee0f985f046953c0dcebc60a45644414ea0be293ef1cda306e628ad9e1a60fcfc6fd2cc49e96ec616e47a34b1194866b26a44584854be89e9af603f3608f3af6638c214ffab24b820f8a6eb2ea1946a43edc21b12d369fdc6418ce398c92f8025cf5d74466c649b68a9c0a5b4adcf609b82981922df010001	\\x3838e853f2d6ead3b0725c72cd4f8fdc39e7a69d714537fbedad7a5435fde443bcf6a80f79c1ddba5ef5a47a111ddc9205646c9b99b502ebdb18f5462dc5930b	1666952117000000	1667556917000000	1730628917000000	1825236917000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
95	\\xd6848caf8d2876ec7a16ea38e037683fcd8c156200beae0c81a5d028a8d13a141d63ca37317039124d7b661ffe2d2438657d765023cfc5f727fdcee1e90ed527	1	0	\\x000000010000000000800003b4daf0daeba0433ee5b1c96a82db9eefe74380ea0558b642d2b8f211feb8f315346aa76ada1728832ad55bffa69e094058c07233c2e73fc5862ae126394bc2821784d25a8401952539c91f17a6ec752b28078438b1e7d3129d24b113b451d30fb13b4a08a02e485c35bb749d4428cb45bf3d84275d689d21e11ddc4a5832dcd9010001	\\xb2d4e024c3e58767611cbf5ce910be5aac982da5cfcc7f497a90f9bc20c25f91c8d20d22247afd1593c608ccd05b78b6615847eeefae3aebeb586f41e93f6303	1659093617000000	1659698417000000	1722770417000000	1817378417000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
96	\\xd628af7433ae7af98ea53a48110b37d1d791bf1e475d95a88b6a05f5a77d54bc29bb55066c7e2206527856a1cb13eeae66dfb20e447cf09a28d23a3a66933181	1	0	\\x000000010000000000800003c6019aaa756d1c3d4be3e91a46fa8a9448078cc48c441ad7e6aff7f2cb100aa55f4881293377e9765bcd5ab9da480870f963aec0088f445b600fcf93fcbf13485dcdcd6b1042ccee45b6d2c7caa213108257638df20aa7ef318f7290ed754d860ec6f106c97ca65d8d5b6482b5853158a63c80fef269a9e95818929da6cfb59d010001	\\x81ab49dac80390337abb90e76aad7f391a8bf3ae7ff0ff582c8e3eea8f34d23bc6717f8bf49e4b04102ba9f2bbb3660e3ec8354880b6e8650e8652220792f303	1657884617000000	1658489417000000	1721561417000000	1816169417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
97	\\xdd305f7fac0192878b8d3d6f4cab298b8e100eae427ff6ea7ccb50011f67ae3f38cb67a3e07eec5a9f043b2d52b49d05397b4298352eef2eb98aa4405917659c	1	0	\\x000000010000000000800003a4a33428e9bc5c7de18f070589e69adf04acdd424fea6e0a5d815103d46c35466726d1977adc58b97d49ac1ca0d08e70f232e7b0cdb80c0848656168611b5e850db0f46ba60d3dbff34f532fa332c84d8f9da78c53d69302ab35a19f96ffea9af1f5a2a6dff35649c808a5f066d38b715d9ced96535b2696b0f52af7e3579edb010001	\\x589b1ebd989488046bd4096af6eec87bb777d99e3f62757d32c491c400089ebb161529c63d71cf2d912af47e956a0b98d307e0b0514abe7c15f3c0595fb30905	1672392617000000	1672997417000000	1736069417000000	1830677417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
98	\\xdd30847c704b341121bfaf574ec3c9418b115e47cecfe8c87623577c5e2557293c7a7d3641dc8264381ac09aa10962a19936d5784b456138c5405e04436bba12	1	0	\\x000000010000000000800003f36cfb987fe9d859557fbe152f9d5cd790d14c035d2436a2df13426881016ec8c8a938d4996967b1e04241656df0ec8b3860f3207689846bbc2b9641f30f10613971e0d8b990e7ffe2c29001171f51ef733393726bfd6ac2d141e0e206e1ec0bc10024826462265414f11fc93408a8ceb8a5a77c2a05ec69f03e012c2c80d823010001	\\x73e0b261d66ebba715c32cc8a9520ab45acf1d4cdcaa9451a2fc7d6dd8ad64fafa3d1ecbe9c1d6f24cdc3bc41304b00aefc4b533e81193afa9caa1aa070c260e	1675415117000000	1676019917000000	1739091917000000	1833699917000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
99	\\xdd7cc0748308e49b55b90b37c9b0c3a2598e2845ae2ed43ccc8f33d715721dfc4ca173c2d278abf9061f0659f9ceb8be5f6c1f69d6e2576c78cd55d5a4820c75	1	0	\\x000000010000000000800003e7e2b2b788795a24c98bf446d0ec4a3ecf3bf7f294d4d625254be507404f16835ab677b5f0adbe7405965fd10f53ad3ec395b257e4a477f78473766f8918411b120498972b417920061416d2147e90422f2c2d8577492d766f201cc1b32cb2e895de4aaa2c4f548dd2e14023e919726cfc5055f504eac7b86271daed58a09c3f010001	\\x23c74d29bb9a529597fe7cd617563dd132996893ed83de258b541a529f66d94d305ea6ece70b836b0ecf699e5494e8c869db15297344169ff92b1f5046ce1603	1648212617000000	1648817417000000	1711889417000000	1806497417000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
100	\\xde84a1d8d32ebeb243185cb5d448003a6b558d7063e26effd55fc9818b662aead69ab8961f85e4e53bb09632e2598b1816a41772d3620eeedc6ad19b577bdd10	1	0	\\x000000010000000000800003d01dd6f6e9905c6123e1bf1787812770274f96ff8713b6a875cc6e5f04b825400a3676a2f2c885ca206134a57a14aa174462200aeba68475a7a163c24c7c8ca1be2fb0230d58ec218c15cf3211e2b1007b7fdf62d04895393203f9edb5330a3cfec988d3da471cb004b7b1dd4bbb14362f00b463f320da1c24c5b08dd1401c55010001	\\x368c928beffb34994bd0557fd8e8a1b9c3652108e3610ea91b1def7ab9a5a48a5810faf9a9ae0e9ebde118bfa711f13a6a65f0b081ed4cc16ad99ee77623db0a	1662116117000000	1662720917000000	1725792917000000	1820400917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
101	\\xe5801e16f8c1145f1e15c312810b31d5c85195c7794cb7e1efcddbc8999ce527d3fb606d8c01dd29c953d4ec482c573d9bb2f7b0e34b9f68d6d205098a5c651c	1	0	\\x000000010000000000800003af774c8d1ca40df10794e6a2ae6168485f69df44ea0289cd181127bd871131c71fb4ae50c2696d7b6164a1ff59607fe029ffb994dafa14ef58ab3cc2a0e8819e73dc07941cd7a8aa6e98ca9a26d2bf2482861f73f009de2bde29f251a2ee58067b1b0f465237d9bfbb45ba47684c4750c078f0a2fdde51d8cb51c9a3669518bf010001	\\x7b722a95345feb6c93143242bb27be7ea303401c618edeef28c11ecc2983ef6b4f7339ee5d6f9f0d6292e76ae77148abf1c4ffc5612a00c092d7fb655911e30a	1662720617000000	1663325417000000	1726397417000000	1821005417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
102	\\xea90a7a52b32ea9aca1f2dd77ec9349f1e04458e60dc6f2e3a8f6440c15eefc3f736630c5f66e6ca3d2ed75fa00279aa91f78ab58bedc3c231836532efd97d23	1	0	\\x000000010000000000800003e0be8bda06462552f544c8be9eed91843f88c1f190412ed7a8f357457fa95c788b1f02a118b167c3f1aa9869d6a464ed5e8d7ba895c2b73923064d2efebac14ce2c8e2f92836801dace0b3b9de1c1477705cab6be3f1f83c424242069bdcec5191059c4dde70d85a0ddb14dd6abc5d90a66058d7c4feb07e68aa2fa7468d1a21010001	\\x08b82e92a734cf5d04076b653cf9b32a9a9c645ea0c05d718a2da64aadc726b1f78669cc9a6fef8e0a4fc0b85f9c0fd2b826bb891ee9bb9d8794671464406f0a	1650026117000000	1650630917000000	1713702917000000	1808310917000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
103	\\xede41eb7f0b2609a2ee9766d4e16e0d9a686d45ec4f3195d40bda585735976542534aea960ca65be786ee36f85f4b61f8e9825ae30830a3460fb23b99976eb15	1	0	\\x0000000100000000008000039b8c974d1a94e9397f6cefe594a9b4c0a2dabf73b7e7907b18892c4cb189da3b055a30eec4ae908b95a2a29998b619117e80b20c81467f1d64a7559245e85da69a918cca3148cf0536a984c497da035720e128e6af3f368d76279903f50fef93a5e3de80fa2b354a1d80f15a083b94f62e224cf152241b39bcc433eef5b9d699010001	\\x19fd3ace482e4f53c11c931bc7367c1c51f9e2caba515711f717bb25a537ab4ca6540c97345b749b1774dc48743d694b77031e2ef178be066bbba77be46a6606	1659698117000000	1660302917000000	1723374917000000	1817982917000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
104	\\xed08c2dd55c50420e2a3a1fb0f7039bce0d844f8de9f5ef48711790725c8560da19733fbaec8e903c4099221e01f274763690469e87683bc3aa8c8ad248761e0	1	0	\\x000000010000000000800003b500d602b2843361f18b4c3c7ccd67f694a91beef4b872d6d77b00a414a4d20feec25f2862abf176c0e688029693cd5fab75a7d0c987cfae5bd5675fc6eae97b3f1d38bf7787f0fd4acb587b9b17586838882664aab8bed957479b86fa2f53ccfc28d366064c643e25774241096a173fceb89f7603cece970698ca21b70b6b01010001	\\x3ca1c977acaf07ac5728c0872dbfa697bd6cd013dfcc70c20ccffb589e06069a10b5e7341bde17aed5949729183fa68a83c3da60489ae898e8254dd112c7dd05	1664534117000000	1665138917000000	1728210917000000	1822818917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
105	\\xeeb4cd563be2e82e28018f11a2d2a9a1094b51f01823eb117966ab8a30cc5d429934979387a37f119fddc80ce25b5cc3465d5ec75d413e0faecd55317c159457	1	0	\\x000000010000000000800003dfac25466a44e29ef361b6c0282d5a0a5557644055914b23820b325065f9f255ae2a221b9b921d83577af45dc81d9b791bdaee1caddfa8327a45f8114de5089c51c364fce0436e72b28e86bc1f65068ec7cf651ee8e7945606a95d74463d335c1dbee525520d2466c2ad0c2fdb9c5567ce2a84afd82cd096deebfdb0709ded57010001	\\x7abd1ab2c89d2a0a37293156b44f28e064ed4bea37d683d8bbd60cc883b48f19c6985a1e1a38106b0e2272a5bda926da0f073cd1a99c62f9420948a0e60e1806	1654862117000000	1655466917000000	1718538917000000	1813146917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
106	\\xef60ddbf8b31eb6a49aa98afac9cee0b2b0339929aad1d052972ac9cb5eb8431015ef7e52cb629acb8683842a5ec439173ce0728eb33ae225998b4df13a547dd	1	0	\\x000000010000000000800003ef3c8ea3d43ac2781aebe57580b6a17283609265df9f80fb6509b4d60de85ed8006a0acaea17d5435b9fd7d132400f11287e0b20c5efddedcd8a5540fc5c1e77cdabaa4378f7821ea63265b993713f4b8a757e5280f5fb425697d7ccdbdc36aef7cb78e6355066364961a0023c6e655e49205ccaf51f70c2923b99deb469d483010001	\\x081c8bca27d5b4accb83d103f1bb9a05578b0d895bd671760adabe7670865685b054d39f57ab70c0bf8793693515ffa6774d7ca4d2ef4831bd45cc2594bdf302	1653653117000000	1654257917000000	1717329917000000	1811937917000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
107	\\xf0d895bd0688f867c754d46f2e5f16bc084d8db7417dfe2eb43672d38062f9b0e70da640c309d6c4a43ea6d617f9985f2960ed7f8c68971e6d54f2ab305ddfb7	1	0	\\x000000010000000000800003e1713bc55d1fb2312b3b1aebaf97cbbe1de4d4444d6e98dc45ae57afb67e6e709b4df844e26f0f96eebf81e14f8af0dc62ef3b5daffd8957a9fb9f91a7d4ec1703f108f8fbc95169129710a96ac67e2808be3c974c0395c3b10b88bb206e9976bf383c1d89020bab598e9375f529b313ad962ef5b9834b19967330ce87c2f1ef010001	\\xed6503c52a070638333b19ec22512ddef9e0b85911c74526d950cc302e28b520f00965dc59bebb958e1de86336698d6c4743911089c008c719ac59d45f97d004	1671183617000000	1671788417000000	1734860417000000	1829468417000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
108	\\xf2404c0a4bc8abb3f0af401129fc89168314846088580a8ff28eb8278c6f4bcffa6b61449e7e62237bcfea3237e9e174c80f5a7038d737e5df69fe0c4c56601c	1	0	\\x000000010000000000800003a11c1d8f7eab37fd2ff0e9e9f9dce37f45cf3bd4b09df313b1f67dc897cbe1115ad5b20e8c66560ceceb1671049d601c12be2a9c8b06cb521d361eaef9ec704aaf1d420a7c4773201dce6e8310874756e8c9c6a3ae5cb160412749d36ca634092c260cb4fdb56b9326c023667e1b1dbf2c46656dbd7c98e146c1d4bc217b8fb5010001	\\xeb49e42854748c89c08a9e5e237078356284c0e021622e6b301980064bb20dcdc55949c07615606e22fd293b6844facfbd2d0274b47245a29707c2eca5f4ae01	1654257617000000	1654862417000000	1717934417000000	1812542417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
109	\\xf2181d547abb0440299796dc0a7846b39810314433ba1038fc0a6f072e156b46aaac9236737571ebe4f2f0e69f5fd3d29720934847bcb44a1f139a5a99443666	1	0	\\x000000010000000000800003f0e5e7f7fbeb91231ff8b9c3b65ede39ccf43bbc989a39b5fe33551727db74f53464e831c0555443c12603deaf16182112e0ba4b3592e2ed7b73ae5c59f5263799a85703c61825169ab1f26b76722f6783b2982599c7530bf5a6b6f88645897a27cc514f7c2ecf6fee433803bb63aed59e2f8a6001759ce99ec59afedd41a445010001	\\x3c4a9371edd00995ee38d5f0f14222540771ae1cc87e40d00e9969fa1ea9f88d7e1aeb4a6d58f8e66199d900dc50c56fc3d73623cbc9ab45032f850036a90109	1671788117000000	1672392917000000	1735464917000000	1830072917000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
110	\\xf77412780953e04282c404907f3e7b9079eadc9011efd1f9d46fb5a99649fa0221e79b849f49ac542beb2cfb292283c74befb0456d9a0f7bb4101ad6ffc00e07	1	0	\\x000000010000000000800003e8402f88b85b9eda37f1bcc404c644b709f82b11a865aba5da1643b8cf93c7e4087ee5aa336e70d7f79e43887cc806070492e2644b0f85ee1b40aeb3d9ef904d043eabd0fde562bb5e4b1e4c884d36d33c80f2bf82fd755ca66acbeb80b53f381fa67b54c86cfa7bcc996648e5c4c7a8353cfc73f2294d2ad63e237ef8a27ac1010001	\\x4ba53d9be577a34e29e67bcceff527d6b2cf3f811d25557126b7bf6373c76583b7100c9528f6e13ef7976b17d31d247a59473ec27665a5d815175b6448239403	1662116117000000	1662720917000000	1725792917000000	1820400917000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
111	\\xfed460ec3e7cf2ef5f0a1133d79763b4fc457b8ff5856bfe958e7ae08a98ab6ab2150eb7fe191c006f2695b6ea147c05d9a461d94630d7f5d1cb97105c2077ca	1	0	\\x000000010000000000800003bd64a62a66e147450a93bebcb0b1ef91505bd37d5b778b88641eb6a99401d7e606d7fcaefa8a48bbd6a9939765a19d0b521589aa64e0526e54919d9e256ca30b11fa20e7a4b879eb360627fba73cb255319bf6d685dff721ec8dc82a8ee515e0b0a599963f893eaed2504a00f0e6c71bd3b9e2a08ffbdac385332aa76835dda1010001	\\x385195315b3ba5776ef9d5a064c83c42b0df4c5ed4c1258fb1366f0d467206c12ebb2b0f0bfdca96003da52f5065ca051ddf53e67acfd62cb9c9330aaab1a402	1672392617000000	1672997417000000	1736069417000000	1830677417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
112	\\x01cdadbef9bd997a96619e38b81a58f0b931204cc3193bb0844e553d62de28a78eb2be15b227e74f38f796791fe1274e1862d5a86e17737fe9e34aa830099b02	1	0	\\x000000010000000000800003c3eb4d2da3ffbf417961a243588194f7c5fe97aa163e62e6a94b9495082144e4cf636d8b8fa273a62dca2932e2fdabfad64f59731d9dd79f0cfc486acd5ae9b09407f3794561fbea9fdb90085714037355f12b7b90c4409c9134d69dded2bd0dfc20a634b1b4f2c108d6196893632dd0a26e186c1904ab61ae4282626b621e1b010001	\\x416679ca1f8df1797fa88a05c619d222933d4c9ddf520563479d998182addce5e5113f2fb00215d0d15102f4da3fc298bc3ad559bd2020b3aea8633d816a6b0b	1660302617000000	1660907417000000	1723979417000000	1818587417000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
113	\\x09850a2a89251324da9b96f4126c458e14ba1b5e56591a15cec881419a44087272d89582e6df93802ed70465f4bd5b360298e85cc370a36c920c21f9e010a9ce	1	0	\\x000000010000000000800003d0c668d76b801fb55f476be8f0c541dbd6f9a13c6143085432fad073ff7164442a3e8ac62226fe19f108490fed97ecf0ebd9f5cb8ab903cb970a93386dfb37477c2f96b92cae21d47f12d507e813bb88dbb96396fa87b96c6f96e0721727e0fa744ce11752d4b2acbead4b704431eeb59739a0dfa30772a60fd6a96b9645c873010001	\\x846f824345bd257d146245f8a7570f94a031a35b96117a95eda1b4aae99c7be8f5230c734276bc82732e1a342787986a7060847640bcb285336444d0c224ee0d	1674810617000000	1675415417000000	1738487417000000	1833095417000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
114	\\x0ed1d5f3055aef462f634e233c5114a8c7c5585cf86df6b63b2635491ccac351293b08a67f0b4d0311418fb9e1403b7733d63fb5bad4df1863d34dd3d582b9bf	1	0	\\x000000010000000000800003a87107c2d5ce8d2095d765da1d54630e9654f311fab309f3405184b5512089fd1da934fc8d8edf87e8d0b1dfb53ac02ee409a1d8e56972dbd2a6e1092f518aa93781873d4434dca686bdc32b8495dd1de11b62212c5745a15d500e93936ab3a11386f893b8ca1702abd3d6040d25b45676b0157fd6158fc49c3014deb0779b79010001	\\xfcc60cc39d4c07baec249f26a8aa829e9ab1c8a932b061865ce62471e6b4641f178e2d2e1b35420bea080661d4bb1cefabb2ba663e84ab5d5e5ed0949fb41e06	1663929617000000	1664534417000000	1727606417000000	1822214417000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
115	\\x10bd8368b7b09bc9e90b074124494bee652feba9c81949a6199cd119e05f4c1924d4bc5a115b7083d066bd62b8fa8ded1289c8f88c6ce7ca95cc6f7a94f8b1a0	1	0	\\x000000010000000000800003c33646157bc8efdc3675c5a64279571f999b9b0726f54692751e40c0acfa4ef1a932ad639fc4ed617a3bb99dda8488ee8d7a0c37e741323a068b31b4859c35c136a430cc40c45c91a1c863d501138cad3e5844a38ae7c0bc9b1ac3c4098ee618a9bf88b5512273c0dab41621c0bbe6e5a27191630059be27eac87ecb093e7bc7010001	\\x7791972ce72cd545247823c32c7ed926cfdaa667db2bfe58023c0e843ca9ad9b85236f4c03539f089ecc3ebd312430478d9d9adfe5ed91ac4d6436318649940b	1665138617000000	1665743417000000	1728815417000000	1823423417000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
116	\\x100d2095c1303d247eed1ee1d3b5fb8447c0d55c10129f7c48e769d6b3991798ba9fd189a3bd55a96d95aa9b30d67f0a6aa6bbc3b1b520a9bffa0e8dc1b1d095	1	0	\\x000000010000000000800003c70a3a1ef3155fdc2359e6cd5f2b45d0ba0b12a1a8cb9235729391e0bb1b2e9462acabfc2ad26f16eb2ed69ec2c8dcd866c75b811031ea47eded061947bdb9aeaebb10c2ccac7bf6386170199dc06f9f8fa87e16f28bdbf3c680d4fce3fb2ea6ef301369bf84bcce9157c7d0ddd6c63c0897e3e659570d96046e4c90d48350a7010001	\\x6b501d50a84390e482f47987744d087290f3e122c58c4d1741945dd699159a3dffaabdd5bb19bbd70b888d221f29ab2161e392e99338aa6bea8ae0ebe2760c06	1677833117000000	1678437917000000	1741509917000000	1836117917000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
117	\\x1119071309c1522c23c804ea973ebf46f9dd48a2f46ca471bcd5ec9dafb5dcece7fbc512260e9faeb6d4726c329155b3b34a9836816085e11b661cb5bd3c5204	1	0	\\x000000010000000000800003ad94177012657bd4772fc552bccd397a42639b9b9b62d896f1260f46fd637a2d4f7929b769a0a304a0804e30007041800c6928f2d6da5e0a50f2e2f6c67bc92dfd945080e8a1d31fdc0733488b9e4235af2391f69abfe6c074223a7d4e472e42cbd8b055afa82ada892bd837727020cd8899ffdc79441833e98c20acb4c997df010001	\\x48b0225467829f96f26cddf884b5f18d627ad98ebf42ba39bd19048f755f22c2c9dea634f8d66e8a0a1db2b3698f7fd3d98de9198f2ad410ed4c20042ec94808	1676624117000000	1677228917000000	1740300917000000	1834908917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
118	\\x1485aba66dc8188413766006e279646e27c06dcbadc8caabebfcce84e8e7dc09f2b153672399e7d525028c67010a6e7fe6b6f26173697fc93a6699ec8922199b	1	0	\\x000000010000000000800003b357bc4cbd76f67f336ad1600ae9e6e8e49ca4e1928dca060b81078b61965e4d85c4d0f2b0a5bfb798f167bc90bfd85fb0a6007c841d374fe6ab8bf68c8056cc7d4dfde3cf5b6baa2e940277a648518777316ab6203652849abb23fa60337fe0fe67c131bc6da13064b9756df381c07a2194bad2d004d189e0b14da0ed902801010001	\\xb0ddb019a800939a597e9631165abf3dd859e648eed51a713290f8ddceb3cca14ae497599fdc07b4d8a0e71ad22866570bbf9c41407c3b652546564841acc605	1652444117000000	1653048917000000	1716120917000000	1810728917000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
119	\\x151129176ae6e1a2f95b58383fe0d31ebda122ff61ce4d219fa8e46232238bb1143522f819445951a944e1e71be6c1c76601b5efed44294c30c1020a3970e3c5	1	0	\\x000000010000000000800003b421d8d5793f4eeb8cb8caf48eec2ee1b7374370d955de6c1a4acb276891a11a4b2254316537a82f83fe6ea1d8e09bc34d58014661b00e63bab20e8f3011544c6b48ba34ade19582a16e5eed582a43f03d9ece3274f20effc13ab3cd1926551f6a424ef670c00a9ba30c20b9d79ad987043289e8aaa4b87be30a787a3244674b010001	\\x37374a0a483a4cd3c744579a5477d4f5f63d78351d82870a9d29d99961c98b083efc930c07e353aee23a27961a904e170872d69cb33b2da3b38cf48e06131d06	1656675617000000	1657280417000000	1720352417000000	1814960417000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
120	\\x1aa9edc7add33930a240d29e55ab8ee5de6c4c5cd316f6569ab6cd0dc078d5bed0cc1451c47282f0c63b372df0e5541e96036bb057c9ff7de99baaf1a0d540fa	1	0	\\x000000010000000000800003de83cbd376bbb6ce8a13b0d9efcb40718acfabaf67d2f3a2eacb246440871fd7e298a964cad0a55144c92047d2238c5641f92530c29ca7d75d83f896165033f80cca7b4da1ace0927aa23f1480cb539b11fc6088880a74ebbaf161ff023f193d9ecab8bf2e4f25f9e4b22b29d1b8ce9e4338e0a023ed0636e5b142360504f211010001	\\x9dbce66054b06a0ceed18e3ab9f5634d985d96dc624c9204771ad9741bd4afe6e65e4722c7fc19a69c8b36425e1697266984c051842dc6a0297cef9341242d03	1657884617000000	1658489417000000	1721561417000000	1816169417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
121	\\x1ce9414ff5757b6792daae2fbfd334669910b4e94cfbf2e670ded393d8f0dd223176d35ac75e7d754c5bcc2e1b65c71f0f3ef4a9364260df521ea37bc1640c6b	1	0	\\x000000010000000000800003b9a5746352dffa08e6986684338549e18b3618b23a30bd76a8a2f6e8f045e68a928484203236b6005de87bff5036934e6e0abf241f6a670859528f65f15b23be8d1236889ab658eb83b291c042856cd9a6cea136c0b5ca653ceddf4ad39c4c9f8204be1b4051176552111e84ffb32bfa2964f9adad30baa01f8d0786dea6669f010001	\\xeb7e059ddbdb5c63b3432f239c1c180c847e9ca4e070cea6a4ee77a1237a6dabfe0384e30e2167b9d3fbccafd97b02a2e3e910004829970c8befe37543f4e502	1676019617000000	1676624417000000	1739696417000000	1834304417000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
122	\\x1ed5ca3f85e52a975d49750f886ba123e629ced00acd7e9fea8def3c87b3017eb446d787c2a3bc00d07c1ee4045b52f5b631fb7f1971ec06a00ccfc1fa2c6f82	1	0	\\x000000010000000000800003c98afa12c1e7f2d054ecc3d2b54aa2b5f838942c36eae1448bc6b50b224d8cb0bc8289db85325652cc5eed9f66f1a89ff18ddc7e6384bd75eb07616b128ac378b1fe0f898c1c14469ab41726f966a03a9db18a3cf7ea3f6b156ec3ecd58527d0a3ff2f56ce76181164a2f1bc55f8363406d06b4defa5972159b1f23ae7473e17010001	\\x4961360bf03c151a85d25a7ee8d59e7249ca4932b8904e7af42be8f2f758467df81f49f9d5bcf13942e3714f79e64a9debac51e020eeb6fcdd9dfe7942426800	1650026117000000	1650630917000000	1713702917000000	1808310917000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
123	\\x1e8140e97263273018f8e0f291263d01307ea1ab4fd88c2223e01919a61f395eabeda6f3eb0aaad0b01e38a8dd88c988a5c7ebce2a8814a80edf40cd4eb50ad8	1	0	\\x000000010000000000800003abf9329e06ef5f56ccaa0e1ac8d18507607c3880a521f080db60f359a6cf7cc90320cb4cb6306d91a2bc05ac375788fa5ef7dc9b777f66d4091b877d49dd92d862c30b643db137850bd9104875146b84713ba2ef518532fe0d21bb87106cc0a29e62ab07e64ee7fdb64d170ea2d9930d50cba39428385d8cea71dc4206ccb1f7010001	\\x65f681b71521a2a5cb1699b751c6dcec80391d1348499c3a46f93f65ab35eb117b9064748733d795e06e3766e2cd4a1b6b3e30d0862a0d858d3cc0986c4d7009	1677833117000000	1678437917000000	1741509917000000	1836117917000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
124	\\x24ed4346ecba0618402ccb3f8d75ae2ad1db43d89ed5718297b31be224554778c75777182ce7a97ffca48eea51b23bc85a6cbb19b0efe3457fb8a32d2ba26a7d	1	0	\\x000000010000000000800003c0b083e2e49a99994454e7eb98cda116bd35a71223e6c8c568e26a7f059d8770976b2abb13ffef04c8b476102baa38eea7249a963f3be6e9a5dca69e91038a54466e9fc1bbfa8781a67c925cc7cae5ea8912291af8c313ac01eb1f284ef58814e65f3c30e2c6ffa90800636e1370feb0df5444469037769e6e5692d75a446d7d010001	\\x1f1f2e045f3cc33f9e4827762910fad6aa752da9981fc217405addca4d61aedf4a0a9e8553e1194f0f13a03ad3696e490ca6c316f1a78821424c788890f4be0d	1678437617000000	1679042417000000	1742114417000000	1836722417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
125	\\x2521534881cc22717a8b206d0c5b916b02830e5836f16c33911eb9ac1aecd93e6a7aec10dccf23ef773e4d012ee4cd8edfca3bbb391382fad4f9285f8981d0b7	1	0	\\x000000010000000000800003fceb3f061d3d4d2d8e8d4882304cb2352f9d68a533ce31459b87e8440c7d267e55230ab8b7e8c6bdc5d5ccdba16174b7844a91f633b328ffab2d83399a721afbd6c6d4f33d1c8712d3e3783b9b4a0459666b315bb63db5105b4ed4ab05fb2c920db88afe6052c01e30bdc3975cb4d052d7ebed726d0e3a7fc3f0674853ea8c31010001	\\xf3a00ebabe3a3c4723fb4795077bd5ef44e99cb145b37f812453936894e32a13c2fa2ceb615693fba3071c28ec82594ded9f6a4106b9c9ef50542f454db3660c	1669974617000000	1670579417000000	1733651417000000	1828259417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
126	\\x25c9bd69ff85a49a180581ef497aa7a63c4831e7d6ee3d49df62e0e8f968aae643d2771c53e5ac99da5a19c57e53811e38223ebee939578a5bfa3c201afd6243	1	0	\\x000000010000000000800003b894dfc275fc52d7c4161f811f915eb9547a4dc3e6c9ef99575ef17dfa829b8317ece3c64a1c74c5887eaa3ddba590ebff1301c4d9eb1e5d6d5219bfc7a6812880f777dc7aca5ab7ff8c007c1c33b16d1d2c1c4c028d9a599028934681fd6332e72769def17c38233626ecfd3625f2e6217fe6de8e07dfba561062d56c04e46d010001	\\x0c47a3bf162b1b19be0e5330b3d92c6c21537b4a36becd59809df5f0d7d4274cb699eb2088336b05ba50dd8913a288d0179b2993a6434b3fdd8997e23329f103	1672997117000000	1673601917000000	1736673917000000	1831281917000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
127	\\x26c146dcc3df50691a2466aff338b617701e06ef1a01bf74dcedc5588dd5ad5ec7569ee5909fb2dcc6e360028edc07aa37e95f624c25c0a6a8ffbb826aa39181	1	0	\\x000000010000000000800003a9dfaaa4d785d68ca8dbaa1985c79aecb06305ebf9be54999dca59dd8bb6cb652b105a4aa5c5791de802d54f62754f307819fec9f7cf9b1b1f01b0e481244cb425b3f5c1e944d9280dc4b35ac4d926f212db5250ae88d1cd53fc479c97e0b7c63b10dc9f61c5b4f176d687661323a497c7a9cce932dfb6c614bde4a4480729fb010001	\\x3b5d59b085740bf012cd4d14f0b0ad820c5141e40de363f2530e73e2d4c7774dbecc972643676ef0a5ae9ee56cd309b68841c198a03cd09a6c334252b59a8b01	1649421617000000	1650026417000000	1713098417000000	1807706417000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
128	\\x2959687d3bd8827afa38327e96640879893e2c9b22959ff50e5cfd695344a26256ad10ef7fbff824212c38eb7d2eb22ad9df62a6749988857fc87117bf069160	1	0	\\x000000010000000000800003bf0d411b7c3ef56679aee82651c35fb9d1aa7d226cc4b47ded763196fe597b8e15bf6c9d305fafa4a564fce05bd74234ee84548032ac0379d7536c67469228aead4d288586372e6fea7395646ed77aa7f9d8644a74a3579b0cf5239036294cd5b256417d4c6934210b10e5981afdc5f09eece20bf62d9b9f994c33429ef36883010001	\\xaeefb2899748451370e448b8aca89a3460d4994c7c613a88b5cafd533bd3fd024030e8849158b24c542add2b2350f612cdf64ba23dfcc4c83922535e573b2305	1666347617000000	1666952417000000	1730024417000000	1824632417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
129	\\x32b5b521c44cef22a7623738934316958b51ae6b0e883524db8986d3123ba3562c0c67a9e38d8db588e5f467c07410c164aa082b8c095bc96e813a04dd0bb841	1	0	\\x000000010000000000800003adb39037bf284af4a7f00123bd9c2967f7053446350fa17ac42b5fd778481ab4bd12c5369997581d90938324fdf0b7dc5e865da5d1f03c705b01e38ff375ebc44220e0f7b6e63778bdfe13a2aa2d8d8d442de3061db0977ef084b3eb0ae4bde21b67d35d40db9c4bbffcdd2aecd3e67ceeaea72636a3e7d1ab6e700dbb264cbf010001	\\x8318cce1ec12c3c6eec10c4644fbc9d68416d7436e2985750e57c6f280f724168c7e879dd5de49f2637ae0092ba7908117183c1d28158029a00de616bb10a207	1679646617000000	1680251417000000	1743323417000000	1837931417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
130	\\x32658705e7bd26083774717496824f9237816e2ee8cc946502ae23856ab3a03a0982b2d6784af98f2cb7a8e72e1c10de8370bd8d8492f1bbc8ca3627ed5a58a1	1	0	\\x000000010000000000800003b4947d9502aa94aee6e788e6c5187d1c779bd64bba7c3f5dd88be6eb9043386c90bc10120033b0e50c70ee357492da14feb0230d363a46075fe22d5e1f0616dab255c650ab1410997ba9a81180985acb6be05e404e189268cab1ea601af9dd7bae820fb18c5b296aca328c181f95bf38f5eecd8b7cbe3af7b91e727d2327cd17010001	\\x602601584e15de339b95e59ee1c3cb490c479d041803678b9bc192faf8f95f06efbd7ef37e64fee86cc2734b2c19472aafbb859cc06a761ec14e24ee32573e0e	1650630617000000	1651235417000000	1714307417000000	1808915417000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
131	\\x34457793538e9628ac6f4390e0a8a1f3c4febe03e35387387c8870d1897022be0ff8e9a0951a2ce90b38db1c5b2cf1471d965bb4638c4527380bd3c85a8c6dc4	1	0	\\x000000010000000000800003bb82bd47f8908151d1c40cbf05229d9f5d9aa49d32f7e53e5a58b5323e056da74685eb5db3f2fae411cca7b265064f2c2841142eb217bd6d4fc63e5b8aae89d7d6f533095ef06cf1835ff17a8f3905c9a504c70b71efcdaf1739754bc994267a4c628325447e8c2b77f78b5bbe69885fb558b3fc7187c85c88785d70eb3ac159010001	\\xd2285338163d1939dc442df7d59d677282163c7e202ed6fa499d9976e4c91ce7479ef42cd878a10d96a11a58d758fd60c4fde27b92339f9e5b91d428ea5d4b08	1648212617000000	1648817417000000	1711889417000000	1806497417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
132	\\x3579bbcc3f14daa40f0536f5af80837bcaead7322dd0d5514120ec76878e045fdd1a5a7e674baedb05e5c24b7e38efc42af10c6423be2976c0d6efa0763ca480	1	0	\\x000000010000000000800003aec55331b1311f72a65c996754bff3121b0f13a306d6a735bb951aaee006d078c337293788d51bc1b2a251948c9db559858d50c63f60fb109dd3205556ed9a970f14c593c872491a5c34a84f86e1b3ed7c567c90d662e0f5d56fb18b50d9ac77591c8f52cab2d30ff0d73ad8b441ad01986964a5cdc67d576cdb2e8cae9a174b010001	\\xc2e5434e32784c74089fe8aca422cdebd7d3c3067eb4af25d803a126f61126349fe729ac821f2d67d144af563a218b82d1396db8ab7ad2932807346865b4ae0f	1663929617000000	1664534417000000	1727606417000000	1822214417000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
133	\\x3715607d2f1ef3eabaf60b152335f67f9a680e577f1ab61f531307a9acf24aa29df35d91afe56a40cec7b6a9e54a3b4a0fef829d0b0024bcd8c5c7bf148e2670	1	0	\\x000000010000000000800003be1cdb732c90c635f796ed5c49a95c1f86d7e45e8061d7b4803f4be1d7ca91351c601d0fe1130a54e9df30cd70a41053f3d35da793f0b45e482c332fbf392a117e6298f4c66ac5d928cf2debe7905ee9b99519aa13a0fcd529881c61f75036687a89bb6531e6bd7bc3da4408318717cefa4321cc960780b354c016b77ab1be63010001	\\xd5db93956f06c0e6ed47bb41410bbcd24c247bf42d0cd2990146b1f25d5162c1210bdbba7db09a1abcc3f2335d390782152ba3bfce467bb2372370c111c9f801	1658489117000000	1659093917000000	1722165917000000	1816773917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
134	\\x37e54f38630a32c1bab0b82b4bf46df2ddbb01c21b497df3a73da7d76596ab068151b4997b8730be1eacabd635838ae1cfe2a3b26bf0c26ad057e4f404228cc2	1	0	\\x000000010000000000800003e8698bf6a5d0a2eb6648e7c66fb93bd5a43ace846067147a66902cb008752078614646990007f4687d148e12225e8401d65bae93b32c7c47939f7cbd66d14898f598ccaf207c52c5713418ccd49d49d662593aef5ffa37918070bf3594175348b7833d4510b222dea49e71afe9628a341eaedffbb916450311b52f9917831fb5010001	\\x6b55a3a7c6895b1166cc8886a7916a6ebe07dc63d93f8c671aa1a4614525000a93047eb8806b246a2ccc21c9db79a3370d257878e516a6d9e9284ff22048510d	1657884617000000	1658489417000000	1721561417000000	1816169417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
135	\\x3795a812d45c8ddac51acb9b4164e5e84fa35703455bd6b6f0575568de31a7418c6a155299e6bf1bf6849a4b53eab53775b16cafea7c70ddc1e5b1f4d4cdff45	1	0	\\x000000010000000000800003aaec3431e43af1a6ca7242469aed9191fdf3fadcd1305b634b199496cee4121eac82a701f8f7c88f667bd88db821b39fd0d77e203be616eb976b99337a1eef5c903d84813653d6f457dae185cbc59310c8bf3be27e5742814f6475761aa00f692414ff5a705ae07c9aa6406fa24c878430e1b9ab5d2d095e048269d55636efc9010001	\\xe3e9b267987779c2a77383e8d962613901e6c017a1f97ece9f7765501df72492fb5ff28ee7ed7665ed833d3663c21b320d0d1b3783cd6759405cf7f9e5f89103	1669974617000000	1670579417000000	1733651417000000	1828259417000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
136	\\x38b169d4f635fc53627f315c867a5f5f1b41ff11a88f2262f041c8d6a824168a87593c74dddacff8c38c4a87c4acb4094bd3a055aa7d81c5096fe89114a0528b	1	0	\\x000000010000000000800003b91e01a6dd45b7c5d64f25732290cec5bb249e418445ec645b7a5b251c0c3b779ae5aaf291bb49ed6855b2e542c10fe9746ba1ee1c941697981da037348d3a9f7ad48547059d5d285d1f16d61963a9be98ffedb3b333350cf13923c3b85c7151ff4c9ab6b769eb60f660ac3c27208563dc599d80536f47106097047738a78887010001	\\xb115a417da91d505060b59a32a6dee85e8fc6c83cfec0dd100b49d6e1098ce18d888b8dd936b301aa526a55af9e1a039b70e99e7e3af3a9aa7e32eae582c150c	1677833117000000	1678437917000000	1741509917000000	1836117917000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
137	\\x392d5c690d930485c1802f11a69d1d544b85785d5e1ecf392c0afdf77b3f817cab2e60bcbf92bc946a733807a7d73c748830450cce9528fe4af87d4f9d520ad4	1	0	\\x000000010000000000800003e17be4a4dd5d9827160ebc72f8ae769d0e00d1035e17c97692b1a32868084386ea60bb5935f9b70ac583986848785a0688d971f1fc2bbd0315109f43227f8716846b9b346491279d5f24a2313b6c5702b7625e1e6236ceeafa61d26bb92e439b51cdbdb87a417eadb6e5b6c131498f98c0817803bdf7c2801b6cf4599fe5dc1b010001	\\x4a93505a24fa7b990fba185c7f69f259040fe5a1115d7ef7fb4c1657bc66acba80b79346fdad2b85a7858e91f024696e8c313ecf1de96387fe65a3b3e46f5b04	1658489117000000	1659093917000000	1722165917000000	1816773917000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
138	\\x405580fdd0a6421715f074de178b7036fc655fb623109fcaf36f59a4ea15212ab75695ccc178c5315c33efc7935c07a8cdfc2b50e15d0cf1c98064d2c62c06ac	1	0	\\x000000010000000000800003e49b1de9d13fbe67c28321e35615b2999bc64b75d9c00b8ea50511ba8d7e4fdf8808a060efb39c894292f7cb4352ffb2a218bace8dccc3c2af4375568ce58d859b09bdbada21e74a03221f053ea472ba596f806713499858be5f0671675d35170b6abe4bcb3659ebe73c725538a35b1b80454d15d6406dea55ffb130899d3977010001	\\xfc76765e8234c86ebb6b92dd01e1027555cbaa5b892cae2da5a7d9865675d4a86e699f910d2f200b58be35493d045cbcb331970bb44052dbb22040786189a701	1673601617000000	1674206417000000	1737278417000000	1831886417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
139	\\x4385ab141a3e46e4b5b53272a8fe750609f2d014b92884be4e78a6cc3d26450abf539aef65cd418077820fea8a7c019cc2bbb2bf8003cd60efe88b00f02e6610	1	0	\\x000000010000000000800003bd37af6e0d27bd5e8ee9a88d2406515d154ed6dc4f6a9527fd0a2c75095e16e698c34befcc94e3bfa89958c39768595b0993ca43080d9ab9e543882c2677b24eeaf65ec3a40e478d53728ce686955fac2e4bca6254d373e2042b32983b17b2a88554c72cf7d00a4a96b8410bc8968861e9376d2e3efd9851241d50873c7e9c09010001	\\x483ba9c3bd1e2d143a1268a6fbe6759adb850e6ef79d69c3abf371521deb021dc4450b559704d4d38536d7059d41e0db0b57c7d652832faf93cab4774243b008	1654257617000000	1654862417000000	1717934417000000	1812542417000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
140	\\x47d9afdc6e24e9500285c370c1ba58903b4abb089481a858dcc1745ca62cc045f780fc4c7278717dbbc817f92df7fb8e481534333a862a0ed36a3a622b3784c2	1	0	\\x000000010000000000800003e4808aff6ada183d899ebf48dc7215991c50a37b3a30cedcfae27b4ead8cf52252a981422535dc06e23c8d41ddb9356aa02769438b06a7dee904c647d7cab325b7dd06805df6c6d3e1008f16f51d02a45103aa9787096e588a668d772af116c912cba6711bfda4ff456ea8d3d57b87d7eb7d1fdbbb0de3562133b7555c3912eb010001	\\xad6f6c485e02b04498aa149161e47bb4b374de770508f39454619d1d14f3f7a715692bb3c1c9a75f397e67bf15246fe9c6920b37d807f1d019e26fb0f6e58704	1650630617000000	1651235417000000	1714307417000000	1808915417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
141	\\x48a1728086f86ebde615dc6ba2413ea798af9a3cabc2995e9a75dea808eaef4087e333889774efd99d954d0f1b64847acbf675e67d4efd66e65bb63b81f7bd5b	1	0	\\x0000000100000000008000039e3b46a3cafc8a45c26dfd202b47518f51d0d176a9d804834d0f99b0cdbfaa537c27b842f55d1b5f3231fc6adf48541769f9d9997700356dc5a5acb902aad971ad9a0b18dfd7dfa9d5d53ac4e9e3fcb6d9d38bff653862c005964ab0c976cb0db1d867d734aefe71fae018992343720cf49e52cbae1ddf1e85216444144e3d1f010001	\\x213fadfb5b9163ea473c6b2105e0979662c99a4a60dec1497e9fe9fcb292cd41eb7297020213f0898554616a321d49b0743cd74fdf129ed71fab2679476c0d0f	1674206117000000	1674810917000000	1737882917000000	1832490917000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
142	\\x4b7dd9aee56261ac2de5ac034dcbe43e9d53411c3c9952597805e9cfaa3a196dbe86d54178fbb4338faeeecc3fe9fdd95b261a3c33bfba0ee2bce27c521c6879	1	0	\\x000000010000000000800003b545ad9d49ff9b9e9178bef54c5b5508ed5109f6e1b19e0f311fe9c6cecc058e2138525bdb9c7b4c7bc84885c90970fdc59106f2c69d6960110a42d857f0fccaedf2c7154b84479dd47e307afe11db37d16af28f761797422cabad0e0a7a9187a16a84f8f725ca14a6f6f0945216fc4d0bb0d56aecd730e8c78826d63350c9af010001	\\xb96122387a55cb3735c0a710d7e74446b517b64b88fa7ac4b51c050d8c259f208534f423bc8c50fee7c836073cb329ca78c4aafcf66d6b57bb079586773b7005	1660302617000000	1660907417000000	1723979417000000	1818587417000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
143	\\x4c21e8f10d85579d33a0ade8eda045a448849e673221077e6f1436be3c12904dcca9d5b29ee37d5c68516f32cc172f4f1c2bc4783471f1089be4289c21ee06bd	1	0	\\x000000010000000000800003de1670be828f38b039703337f929c179638d8ef8a36435b3b2a01735eec66ee69d2d0c96245638fc2fa70b9266514838136b229322c129af1565d7f7fdfa7e78a55151452d669a2f2adc08ca77b7ba7aa665f47e8798e4a018b6a03203f43bcb1e302ed2437354eea25760da83abc2761cd74c366e17d0bfad6aa4b1bf93eccd010001	\\x8f0de78f22fc0a77e3891b8e4b99d6bf6f785f0ac406cd89953827c6bf0aec48e80b35ad85b9c0b77d7210b8ca63c3480a4ce849b4bc74de99268d6edf1ccb07	1653048617000000	1653653417000000	1716725417000000	1811333417000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
144	\\x528512cf5caca7d1112053bbb8d2ab1ee739f39058bbdbe078ff881ce40418a085b643b92741c02c40d158e57c1038b40e161a2d954fe494f5ee5cb592502590	1	0	\\x000000010000000000800003c1f2115c9db32d8cdf112045530a37c88b8d7813cee6fee28f5a4d4f388a72cd49eb01c962ca87b4f0d26acdbbed0ff93bac1def17565ff87f36c425c7b7ebf11b7697fe7b69d1b6ae9e51e56acd8681755c5cf144665323e32726d6ff6baf379bc3f846ce7ae9bf7b520759a553e421d634f49bc7da0550dc9c7d8d566b9861010001	\\x235a87dd92070db49738a1c55bcfe837f976c8d9674169b5b7b99e575737c7d60ca44675d98cdbca57c77c6e5f4bc13e8b88a30a2293e4642ae8cef66dc18308	1664534117000000	1665138917000000	1728210917000000	1822818917000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
145	\\x54f91e61ef50e5804e7e42f5709c5890608b4d2746f9d93851057eea0fe71266707d2c43fed79d776239f60fec358b7bc95ebeb088e7f43c5a76d39d9fb2a309	1	0	\\x000000010000000000800003abdafa814b6506651813148b94986699e03cb00a29cf4824846eda4911589b57c4b74e55d473055cbd97faa7d8cd9c8cd6c2f57c7c0591a1e38dc87437dac747403cdc596ba2e4552ca415590342b5ae4ff5e617870bd66438c1adaa70e761cebbf815c978ca6aff2cc32f8d42abc0e7d4737a67bf8c54920710de62855941ad010001	\\xbe46b025080fcca9d30aefb420274d58bc4db7fbe00581a9f0333111b11abd26d3bb766a82429fba9b37618863a3149e08802c5600b3281edd07ff8a8bcfc60e	1654257617000000	1654862417000000	1717934417000000	1812542417000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
146	\\x571d8688b8904f1c1e9ca3bfbeff0b39b833342547efebce33bdb8675e4bc7aa8fac038e06f459dca28040c149e5356ce0281daf622840b7f3747a878b541871	1	0	\\x000000010000000000800003c00e18f571f68dc550f5ec4b59b88c46fa4009a08e24f34c8749e97fea775330ed1a80e32e92144e6d3d7b3fe1e2e2e7fe2c3b7311a6e7e86e42458e39ababaf966837be141ae846b253f783bd07dbb0e3d5287e2ff2b9da5ea01afb0ed14bd8f12b6667c7c76fa0826a63861d0ae097edcf6470f0aa56044ed53502e3a2b11f010001	\\x9ace8ae87e0443eafafe39fa57ace27cb2c559ef4d8683848dab9f8dddb2b97c9ad3842b18fdcab6656b1d4738144aaaa7b65215cc9eb654aeec38b1125c6f08	1669974617000000	1670579417000000	1733651417000000	1828259417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
147	\\x58d53557dc96dd2e7534539a640e8443882c1bea1038b1a7c94352738e1550c8120949afd9b0a33cd1d8caea3585a8b8790a9785bff1c979444d4950c012ccd3	1	0	\\x000000010000000000800003d2337bb96d243e048415a4d25a51d27e8f2191a54f71585a28721e7810718144a389fa6088cd13302fda4ffc510e30366a63a8e67740d5887e906d8bd4c5c7ab086a8657d09a01b8ce04a23eb2c088ba3c2b8f887a062f54f03c99ffa79278de919821aeb10eb7694775c75e82c4dc738d277a3617973908a3d7db044fa19b37010001	\\x2f2308bfac7a76f91f6dff31fa95b5b8f2749bf9bfba4eb2c329b7b0cb55eb0076532dc789e308edce5c437ec23840f0caa38e190bbef0ce7ab93cb2f0ef060f	1674206117000000	1674810917000000	1737882917000000	1832490917000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
148	\\x58752e0baa550c4ca096c97ce0f0af55ad2286c3a8cc298312d1379549f27995441c714c4e15bd3cc4d0f6004e69e6df4b5dca9eb82b956a45aee6360293d067	1	0	\\x000000010000000000800003cfc5b657d8a0e5d7fc37fa1415881b3aeb25a246ee6f276873f4206dcf24e79d82f3bebdd99e4ed7a319eb7929521a997fb0194f471f2e4e3571f393bb71f7db08ee2fa2a9c59bb9173c4ba064eaf23cd100ea86fa3e553a7ffe093c1710b98e289352f82aa8bd3457b76f8bf7dfd308a366c38d899f572ed427e30c1fa185c1010001	\\x8fe230dbef20a8773ef216f90238a740106e67645a6b250873e64d2d0c17737f22a92defa50de041b4126fac01fb63fd892a1b9d24560841e3133bd8f9a47506	1655466617000000	1656071417000000	1719143417000000	1813751417000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
149	\\x59d121040b024261bfa899b6606dd4e89d13a1bfdf65dcc25764a7a24f8dec9280b866eaba59273f90055761abe700e88c9eaa7495bfbfc1c097fe094fd638d9	1	0	\\x00000001000000000080000395f164bf32d6607a182ea200e057bb49910e927c6868718b733e7dc0be8665eff8c08d325ab8775f9f2056e56810152ae92e28ffd7716a57dc8286224f3f7f38f24db8e9dd6585378b44398bf9a18beb5a3f63fcea721c7fa9752e644966b804bcc00fc09be8fd9c5296abaf6b154f84c822102c6e50c58522ea1e1208318d13010001	\\x59b3d9d9498b93daea623782cec805e2c129c2f7cef496e254343e8bf88b0ebfeedd01463dd7747a6804e66e31794f1a456fbe0efcf0b0998fcc98ea0cd1f907	1666347617000000	1666952417000000	1730024417000000	1824632417000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
150	\\x5b8d7c9ab34844a8f7dab90b734f6d549ea239884c87ab01a49571c40cfa44f3f33da0257580859ef4f644469a57ff446e00214cae012905039b2dda0a2f9054	1	0	\\x000000010000000000800003bb3a484a3ed74c7077177fe2b255ec4b5b8d8c8c402564b92a75305d481458a7d55344653861c2d8e3b1e2ba378e700affb77701221e124c282b1297df28b7076ac045259b191c8c9ad3c42e7fa766881394a3930c3e5ac22ecaf4ba808453abe6ef9deadc29918d2fe5b23ee3f00ec6219b0a2e0e65ef7b6882b5c21c18916f010001	\\xc9955cd5a2dab5f57372593666397e47d3630516790f5917849dfdf6b62072528b177f65079cc71be323c86ebe84d5e51fe96b6c7f58122d163e00b04228b009	1659093617000000	1659698417000000	1722770417000000	1817378417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
151	\\x5b21f64392f3bc8005f217d0ec3ba878f7eee541defb8a699a1f4bc00c685694a37aacce21b9c0ff88d39e69510fa0e10aa03f9270a20b0fcd825eb9be29a693	1	0	\\x000000010000000000800003be4785260533b674dbce60a3964f68c8a6088e32ad84efb5916e7c0d7bcbcf82c536cbcfb83af41dd1cf9badefb83d920ba12d5ba3d141a074d9b8deed083d32b715aa90b2788a1ae0797070dfb4ca9ff6978c8a2368e60150f19e659b5efa91dc58337fae278b78653f9eb7807c52281224ac8072c06d74a8071d8a5343b69d010001	\\xf0446a34c60cfcbbc697c7812a33184bf39a121ea98509b1b3fda2d4fe05f79e6b5f44de91cc4a7f1c6f0275a033fcc4d8d3304acd4a35a9a711e89bb774530c	1668765617000000	1669370417000000	1732442417000000	1827050417000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
152	\\x5dcddef257a78559a224be89401407c480b011781bcfb17dcc4630be3b4c0d381d58bf2210df799f27ec55a00422535909e0e2867e753655a8b4bce09bb8ecb0	1	0	\\x000000010000000000800003f980231855944119ff60f089f03f1398d44527aaeb7503a22760cd7a2f34ddd6ba36eb9a551a38ee9d67bc090ec1ce63fa2f9036ee909fad5a84690630c09516778ddb66086fe31c6e27acb89515e77c0da0b6104b19a0ce79325c5de622e72bf8714ec4e4c61c232154b190fda692c586542fd39e5d070321dc8f484c797ef5010001	\\xb64e9b0e16efabade2a63583803e4a35c1717d540800a65cfc81a7c8029a6c6fa2f3533962f0f6ddefcb7a7c6a7661a7630ad305f685cf12b40172dc00c03a0a	1650630617000000	1651235417000000	1714307417000000	1808915417000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
153	\\x6051fd30c735f628a499a2a41a1fc8e87cd46ca58648d09f22fca229a6fd640769ff83a06c3555d1a3a265106c69241920f27bf7936fcc6898d85ab747b50ecf	1	0	\\x000000010000000000800003b302e0d3c0954cdadb4f5964bfb6d9a4707c1da293f74339f9b02965d4de2c0db25d65eed8fcc3b48cfe1341de6fb7d56c0289138d2b48377cb550e90cbfc949c75bae97e882a1871244ed6fbcc1ab552b54c04c0b2d51e30269a7b050233d3bc2f186a3813cd012907afa51dcf7c2643f12d5787615b7415a59debbffbae2e1010001	\\x18ef493b536ff2abcc910329e208bc7549f232d50e2b01d5dc8b1acd2c6cd484ead88257f29afa2458a2dc816e708904ec8f80d435e62f62df4eb7200a685308	1670579117000000	1671183917000000	1734255917000000	1828863917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
154	\\x6709d30c3143d92c8ab9ae7218d5fd68467248cc656e146a85079c771a3d374db0e7e95c80ec0b3d9ffc4c6c8cb45acd5dab3f4efa2ec35e3397812b3e9b07fa	1	0	\\x000000010000000000800003bb998dd445f267b0acea24d8e83c59579781d7951df3162986cb9e2fba949892e88ee2f3e3dd3d589ae3fae2a42fa67dc1a3466d8ccf53cb08b0dcf1504e8ac94bbcd03da2767835a1453c2325169168ac0deabd473bc824bf977fe3ff9ec6f8cba6c275d7fc837680324fe28edb8e2b6673e2082f2789f65720db2c015dec5b010001	\\xe5da44a0a3afd7b3a6f22f8822df9f74362806cd8010f82c45ea04896263656f43a3319a417c0ec59c271098937b4b769f3539e4f741c6c5dc1d54e255cdc80d	1671183617000000	1671788417000000	1734860417000000	1829468417000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
155	\\x6751b53eba765eae2ad7c5402b7f0af90d23e2f3a64e3ced964f896629b88cadb156e6ca5845453343954457b17142decea371ba4f5b2377d3138133b293a3d6	1	0	\\x000000010000000000800003d0e74ab54878beeb98dc8358d6ae7ed6e78ac893dac7206a85a9127498ca83a14c733e9d8bce1677bf322977632b9b1b3244cc0f8128c958ffd9a96028394f2939a789e51eb84eb07d2abf6bfd4a1e88f331e4261b483c951191ab29a4b0cb469c169aefec5e8b1be39c4376dfb09c87f7d9c97ecbffb9c97df986355b121e13010001	\\xc0d168ce1a3fd1de48be92dbbf8e295e95e5539ec25013ab8e8724b0681d08064da500c9a4972a4a4b1b26f2931c12d68d805e18db1583c7f91f312752d9d80f	1671788117000000	1672392917000000	1735464917000000	1830072917000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
156	\\x6a1d473b5b868e5e6a443921d1935e878c340a22ba6b16060c7f32b90ecdc8544122cb709067dd9de5663fa3143a7ea489afcb8f92973ea11d04d44f6923695e	1	0	\\x000000010000000000800003cc54a7977c838c5381dfcd4dc69a78df4cdede2192a7c429915c004d5256663aaee2a46f764978c7acd77a31484b35f982cd86da33441c4026412da69a9d21bd84e62b93b2f28bdcb9d96bae8d46acb03644b60ccbc80eb2867a72b18575af30518b4f52808f113fa97dc2a6361914512ce8fa8c7608bd28c7b05bdb24d785df010001	\\xf88673fe591b6305eddadb5eb35ce35865a8265e6564fc7313c853fda992de3fc54a0e59c687696a4e76bc92c6142cbcbb66a86c15fdd71217caefdac1bb7204	1666952117000000	1667556917000000	1730628917000000	1825236917000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
157	\\x6bb5f10aba60944270420a1c05d06b29dbe8c72d40ac51a1a1b3a9309391d69436c43c9a090d8808ebc66a57e5a3dfb1538afc4ac20a907a33c392e22107c860	1	0	\\x000000010000000000800003ceb1df36f74addb18505d6eaf105cc1452249b0828d8a6035b137a51f6e6c4c71a41d543f50a1ab804dedd053430e7832d7764de18b5d23ec8769cf69ae15405c7a79771f64178e1660e4b26bf2fd8ec512483c55013962b83dc8612a35c71a3bfa215ea9f885db5600ae09e8d0d777902cbbd1c0ad92db914ed56d5fa537cab010001	\\xb5daeed1f63586f9aafd423700e709ea3f35dc5527000bd62cf548095cb8674cf7750d0e7434d5820ce923e619aa5a49ccbf905056ab7fc9c62bc002abe3aa0f	1679042117000000	1679646917000000	1742718917000000	1837326917000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
158	\\x6d79c68bdb96541faa1af810d8b9f755a1c0b628e319a3ab5a81d16a84e2c25c82830b747418dcae25a68fba9a2a6c948de6bef849663ef6d6d40a19e984baf3	1	0	\\x000000010000000000800003a469ec47ba8a8bd1a501d50013fac614d3cca9bd4cae7a88be599f9436a62a084f729c4375418bc71e09a4a1dab66fa4ab06ae4d91f5adcb9227638242716a9ead2fa7dc88ca9ed063337d56553c44c742aa12a92a9ab2e4c9fe3898a8a9e645470819eb352902297b6bc203b5c9e40d3ba01e0c0071fdbc5117c53120ae0401010001	\\x54c1247494febd1a21b3648d3f247e0df807ea9208c517ae6896a2063d2445706925ec9ae8e52d2f5309998486a79f1791c781f7eb620fc54009a18fec6e850d	1669370117000000	1669974917000000	1733046917000000	1827654917000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
159	\\x6d25ab5434ca8ce01ab1cb3583f46c0f5b4510f0ec064dfa99f3912ba002b6c6bd42c4e246b5c4874e00f3b262af407622a03e414bbe4d1b3ce497baecd9bb7a	1	0	\\x000000010000000000800003ce76584af589fcbde0c3c38fc4be5ecb5c8f38a8c959cc8e02af76c3a3108e2b0f761584546ce4c67ab9a2a9fbed4f88f34de7616e2d655b366ef96015d002e79728a380e143cfc0c973a8228ffb40cd785e66bff1e486ed967e445c79d0e2ba4033f095336adc98b037bebce71cbef1699d351e8fd1d176efc3b11aa20dcacd010001	\\x4ae46db36b255ab72558df1f92fdd15342d983f041875e321cb3ac152f0796c519c474915c4478629cc9cd44167df744dc5ff3d3b67c076c0a6fb95bababed0a	1657280117000000	1657884917000000	1720956917000000	1815564917000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
160	\\x72f512fa62d782424ac1bb499603bb11738469fdcbed7a8faccaba312aee1886ecab30c979197328ef5dc5da2a3839bfca2706d19d64f5695ab201c69988be05	1	0	\\x000000010000000000800003a82e8e83571206d683dd528b13296cef50a0293f0b997e0c2ed5c3781ca2a796ddf1fc2bdcc7340755995365717856f0a6c7ca06c0220bd8520e68e399573531fd9129fc8da806c9fd55e213569fa8d6b2447ff3adba255d69dcd6b2a847480ca47841db8e69bb71552c4c851b4b624396f1018195ebdb344ebf2bd27a37479b010001	\\x4082307b938fdce8be8cf47b6df76c0da5f2d51807996338f37848b3ac37bfe14ee0574281b26bb7557a1c95f25e882fc43d4c4232ce4bd42accb943540fff06	1654862117000000	1655466917000000	1718538917000000	1813146917000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
161	\\x738d1a6b32caae8a98c3233eb5264ce68b3ee29c015200d04eddf28db7bef73d27266e55c5c690580d3216d2a67567249a9fa85aab2e848c45e8ba8f96b8afab	1	0	\\x000000010000000000800003ea1cce15d38b5f58d6cef8e422f219ff3ba899c39b57b72afd628b00e625c1b13fd6e77bca5c8e1ee8b0ebaafd5d8d52d62053fbeb57eb346045c51e58a161a67ac3f2d89cddeb34be106474321d9f871f0a5226684849479f45d61d14acff31ade7d1b921370d6499a851f9ee73b62b631f3e29626ff80b5b1e76e18804b70b010001	\\x183f56bcf0157171c62fcc0e4533c7836b29a7406ec7ee583fe19fe52f1a130e181b225f6a1a525a99d1180a1845bedb26c7c4f8083507005846219726429106	1666952117000000	1667556917000000	1730628917000000	1825236917000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
162	\\x7379123699d8e895b7a8a2896addf1b85e128798853ef20a069456c81393d9290f6302efc4eef56d1f8e8ccc230767c109d04920071826d9134f868014fb35a1	1	0	\\x000000010000000000800003e6dad9781c9fb6c5d3c867e4e4ce0f632b843d7f1f1113f13d44372d136127ed2b7dbc0c9ba17a189298a09c8783e18c4d768aa78f0c94df827409e5f5e55d4480edf5a393991b0507ac30d98786d3005681b49a0cce4fd044e1c5cc152c7117c1ac772ad02879b93215306da03ff1bb4595679d63f0f2a22c316f717e23325d010001	\\x0653f042994056eab5e89153bf7a9c3b470ac8c05fdfdf6557162548b90aa642ae5058c82d8444bf5e5d765ef0895dd9769628ed9ff3a60bf713434deb2eeb02	1666347617000000	1666952417000000	1730024417000000	1824632417000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
163	\\x743dd7ca49323c076bcc948a389111c2f3d490faf550ee6af2bcbd1b3256be3479573d33a3ec43134d079d8776cc651c6c7044f21996421778523384f6ce6c96	1	0	\\x000000010000000000800003ce709e647d0a35b7b3486cb1dafcee46fb5475545275377f56c5f48cbb3ac2fe5d5a393783165d1b8bd19b0a1a01f11d9fb81296a6e63ffc97d0ec319fa0ccdfc5c33e41bcc679bd9b45ec98fb6507d172e5505813e15d1360ce0888aa9a3132cb504e8e411f682e6a07578d3850113a0d8051b111f4b3e4b055549e237f5285010001	\\xa5003a6862beeee76cc5fd8e1228544391c10f5361acd80cc1eb90899bd0fca645e4d88dedebc6af838371034f1b49b47b11178ff70607971fd142c937b21f0b	1672997117000000	1673601917000000	1736673917000000	1831281917000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
164	\\x78357173b996496c0ccf1780cf0505637babbb81c99d7d2bcfa216ecf30c9ac200b1e56d33542893ac867de210e50b31c9b1b2bcc20c28b242a2c36e70885064	1	0	\\x000000010000000000800003b87004a3118c86b1ab40b6d869c715b7925531b19349420cb033fc99db751a4c7a5c862f82a5b147485680178ba7356f41b5a9c0de57122ead2eb48b8ec73d280915f097d7aa6bee3d29e257bc6e02ef7ee59311d271e8bbc389af63a8ff226c5831c7f78ff153c4af2b15915212f7c72ee777c0059d0f24e4cc7ed2b54e0b21010001	\\x6a31749d5aa8ebaf63ce0f549cfaa7a41ecfd72484fa698974e66cb5a226dca5716485e2253403ba27c98c81b82a4ce7fc0d31776219290d19b6e9f40da3be05	1672997117000000	1673601917000000	1736673917000000	1831281917000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
165	\\x7e69adfa49fd607e0849bff48385cfb41296b410cce3cd2ffd6d582114632ae7f4fb05a6e069ea1bc503308cb9642511bd4c98144d3dc4e15184dddd5cf1691f	1	0	\\x000000010000000000800003b2d03d8401b1fbddf9c18e89d68ce02fdbee016c7d89d838c22ca17287d351833b61a782e309694ac0986a047f6bcee1fe8ff14ca1d3786e7944b1d938212a42713ffbd32ea4b21f33129962c68035eb7a60f98134fa3f4d61a7e16b6d7137177fb66b6064743a420d282fae5f3cd45a3929bf8f92418912ffbc2853cad956e3010001	\\x2a44e7f4316f66ec5a004c0d1e9125bf69c710c95b068e5ba96a52dbb79896e08eb3580d0f8b0fa8a40a657878e5cf937ff67f99dbe9ae9e86f41ceff2316c0f	1650630617000000	1651235417000000	1714307417000000	1808915417000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
166	\\x7fc1640fb2cc4c34c2cdbe94df69be29f2b4791b9d7850fbcfdb489235120851a61fd4f63a3e93d083090c3c7d973419d1c1b50cc5037aed5d2596379d5ab112	1	0	\\x000000010000000000800003aef4f3ed761a350c5a639653dce0c4695c0624410b92ddcf452ef944163758cda93e873fd0a3d90cc875cdcfb442386f3b51a30a00629cd2d1a3c261dd728df5fe9a285f135fe13180246c48f33e31c4a354f9831c9af0c12958d1449524e9e4daf8f26ebb469161734fb8c79c6208d7163009fa2733afe406106fd0a4838c21010001	\\xc7a32a8478d8f923d426036d75287e481fe449b615b9682ee080bc9023718894cc11de6846bd2b8828164e575ba7840706fd4c841923861b10836b4780064d0c	1650026117000000	1650630917000000	1713702917000000	1808310917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
167	\\x829138aceb24230efdfb6b6ca535fddafaaad583e343c1e506dffe98ab84bd2db55b3e550bc6e45efa188c0b52ba5ea5f546486f40e1dc77710b3a0a9ff4c5a4	1	0	\\x000000010000000000800003b163877e21d1258fd52537352a4d23742e90b6a9efcce0ffec7c53de1318ecce22d9726e1d62187e6341acdfa79e3e806bb653a78cc419dbf35573da5d7ea5851542c4e01c73ea8f514e39bac95e1cce16ecd2ef93e4a9dd7e47ec8046c8989d1b4a82fa5f4643349a5d8fdb77a1b2646d8ad5e23fca8b74ab1bc54adacd9851010001	\\x9d76e6e56fd5e0051a8a55c447fd53316fce3b62b3b9e56410e7f1cd894c2e1e5e6c093f065fd2d45bfe935f50a49108c349c2637b061d8f0811f68c65ed2e06	1670579117000000	1671183917000000	1734255917000000	1828863917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
168	\\x83691025a3c85851287a296ca560ee663d4e68200adfc1a2950e2ae32f3f7fea0525615cc03660b5dad1660ea240457d91df3a9274db1a8899bc3dbfc8490a43	1	0	\\x000000010000000000800003d7483eacdb90bae529dbda3b058deb8c488af742e20c5e1ac62314950c8f279e46d2a1a744810a3b8f5f1ed977e06b8717fbec3243abd2d5a675a3add67a780c007ef86ab3293340388db45e2af621227d30fdbfa4e3209512c947ab7bc6f2ad653febedd350d45240ec01ee8e00c41f516003eb9ab9d480821fd4e2d217719b010001	\\x0f6dff1177b21369a10d708926de0e8a05783a14d8a24782fc437972259723a954da6a9ef271a9c7cb1cbff09629c054bc7bc7b43b60bcbc6047492fed3c6503	1676624117000000	1677228917000000	1740300917000000	1834908917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
169	\\x85d5bbde1aff1d70afd46c6478ad9520c5133395d5f7aa501867e8b9bca7ed7f23522affdf5b2c8fd5c47045d9fcc28dc8dd93fd49809adc892ae9de4cff3c32	1	0	\\x000000010000000000800003bbd8c2b50b89fc9c2b7cd54d2d0637fdf6fbabb3832a17f2020bd728d229a148d07578b2ce9d900ffa16f20d97ac847ee18b2d6dc9874e98ece2b2fcda1e694e43f114dbacb2bf504dc94713aa8dbd2f9dc785d02492569e97171f3b3e7dde7d77de01624ccadb35781d404d60b00342240afb526926decdb5d7380fd7581859010001	\\x064c31d0f2d833175522f324ed836f0cb6ea4c553f7b982dc8930d6fd16bef7c1b1ecc56a5e8135626af992828f09eab71e0c3867ea6c67106a1b2d45d32ff08	1661511617000000	1662116417000000	1725188417000000	1819796417000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
170	\\x87ad6052c89a4c13f9d1e6d35d6283f52b7c20cf51e4ded4a982ff2f271ffe67c44b59e0399d886aa89d08be0cb0deba5765151115fd5f3e98cd65dccf2a0234	1	0	\\x000000010000000000800003c99d851e3136c9c60a214328f6a1f55d612874491365a670b502554220b3f68aa0f6c97571122bcdf0b4b22202beb77ea68de9b69a521d52449a2658ff388490b708b0e26b577ccb2a14de3f11141b34d2d84e23aaaea27c70c15e927f7b7237d0539e7dd98330350d32f2e731efd7f9ee25d08e41cd66419d861c7371602659010001	\\xd773c27381c2d76209ec9eb30ca84aadff2ad03704c896eaa948e801d98d01b8597bbd0e7f5623e0ca3f2a3e16d39565f584221a16a390071e7b9ff313a40802	1679042117000000	1679646917000000	1742718917000000	1837326917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
171	\\x87cd9e496dec5e059295034883cc82d01d3244cb1ab71914961c476925282d3edd0653c0e5cb9e0b00e73d12fc4281051eb7905c06318f7b2e2d92c5978d1d38	1	0	\\x000000010000000000800003c7c50a937655dc35082a9b1353615e22773371c4dc5889207d205fe3e28b5e4ef9ddcd2589ab1759d4044884ad10c4e934ea913988a950d060a681d0369f754abafc773117603387d74093fdb2251de13217dc5004c19e5a95e6a8c6b3eeb6cbd81e1a7d05bd32c54b54b20f44a64c82a680dbb5b2dd2223404e1014665982e7010001	\\x5e5a2bb61837aad335840ff4057e41004150bac33a122ca39445ffe1018c33a00eac348c06ed24596bdc35dfd6b89fa3e61bdeb73dcee811cf0175c7477d2703	1658489117000000	1659093917000000	1722165917000000	1816773917000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
172	\\x88b96b3cbf3dbb2d26feea12955033c3d3cd57e361d16dd62fa45655470aaa64c13043c8fef3d0e4fa0b3b744c80b654d4c0f8ca642fc31da4739a07234e12d1	1	0	\\x000000010000000000800003d7002b6c7ee369498cbf33d02a6eb3bf91b04d20029fc36670b44c12af01b6343ae2def054e6a58dedc021f84a94f01da251842a0184b4b891ae6ca7d0d914af2e21e045dfa83537a3a34c94b2ce2d7d353d2fc99812ee8ad7c3de195f3fba5dbcd91a80d075c6839714f92d007645c607d4a2b0f508181f35207dc632775351010001	\\x91b6cc3ea2b5ca2aea6234f5998861f8b2ef40fbffdd2e8d3d6017cd9cb2dbfc5b9403cc965e7e3bcbb8ee9d4398ff4ae3589bdf3e10ac79030935fa9eff1602	1672392617000000	1672997417000000	1736069417000000	1830677417000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
173	\\x891518b1bc6c93611fa15cb4f732e5d1dd90d09072b479131a2c70ccc2cf205fbbb36d741dc79304135ec2e639f1296d5e773b3f0b6d8fea6dde78743f02171f	1	0	\\x000000010000000000800003ae80ced80cf38f5bd86ab86e5be56a43e98d259a0cb5f52a8d3a9535e8e985d7512220c43181ec1b451c3e19cccd197314c3f86493306b729b4a93438c1cb3916ed30962088516625ff83b8146a10c1aef05022653d53ba1adb5f8a603bcd6b1f05a5539c163a45e8da80fa662fc05aeec8000826ae3a87c6a9f11e057799d51010001	\\xafd51bd639f8c148a6825c0a617548eab5b7180d1f0d5a820d6b1b5143bf2b65fede00601b5f5c61e08d25c92656726b54e4df5a5e9b10c92f902773ddebaf0f	1666952117000000	1667556917000000	1730628917000000	1825236917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
174	\\x8c85b886bd75befa152fc94f3829cc8d0e4b03e45ab6dcbc1dc4b944d34ceb7c2dcefb7ab52fb87c3d339a4767e356990eff7e23df103de3c0362ca1d7f3be62	1	0	\\x000000010000000000800003e6c57566d093eb6a10f43d62090e39d04ef15b301842857b7efe1507a0ad38fe7735d812b923eb1c21f4e4174b3b10ee239a50ca991db866783aa8c353053ddfa8642fd852a05cdc060049c65eabdacc711b3f16ffda517487c747aac20b33534b211b51965e126e78705e1e958aec025b4fdf7f793977817ff5eee3cba0a153010001	\\x0603dc8bd14089b7a1bbf79613a993ec5e56f301e4508e4d0403e657ffb78131046cbd0d83d648c9493349b51838b1a7aea425da7d1e61f7c8a48753ffb0a006	1676624117000000	1677228917000000	1740300917000000	1834908917000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
175	\\x8d592643f6a690a4d3018a1fc4e628a8b56f56383855e538e27fec39e1bfcad4ee6cc1777dd78be0922ced8ed78cc06ae6df1ebfd0b151688e8fd5a49d6231e7	1	0	\\x000000010000000000800003d4a8be33948236f5f2c30e5b723706c3ad6ee2be974776c2780037952365b46c05855635bf1fccb71e5f7227a4dd78d9256a59c4b9d2be0cc8603b9798087bef6e105dabe7a9e6081b86a858a53a6c84129cc6dc65fefeb8d3d07ebb5c645b47c5bd159264693f95eb926a5c340e3915d66c268ba318dc6314791f33b0245271010001	\\xcd444e32604e322fb38c2110362cab47b01c9bbf4ae59f923390a29c71abe377136cf273182db7841b0da9862d14af8ef4d2d8251ffbd23225cbe31a0e80e300	1677228617000000	1677833417000000	1740905417000000	1835513417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
176	\\x8ec14aa99c3d57e8f1c1762b7895edfd17924d6eaf07c30c67eceb1fad611831b4484281874802bc0e23b3ea6864f00fdce1345e1019053c70122f112c6fdf3f	1	0	\\x000000010000000000800003e6d33076d948a1c8675d1d8003bbf1d054983f890cf3a1c23967fb5eab75b876aad1b9d7df2d7c1e48041a115f9a70c7c33bcab48dfbc1020a99fbcbbab1eb9874beb4fa0a9658006441e1dd20d496c1828df08fd51a5cd1fedff053f39c5efae6e0d7720a2ae996c322c92ccb4361af37fb33102358bd46a876266eedc91b23010001	\\xc1ebbce3c720c20700a8e58f4e913c4e0b05ad40395e8cadd72cb41b3fafa5c6f7d395a548cb36889733eb86ec5bc067b049a6fe6d9e8c22c62e0944e6579d0b	1661511617000000	1662116417000000	1725188417000000	1819796417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
177	\\x8efdf374357c6d413450e38c65379d1c5d59340a2dcc0a5e6a9c289665790c2dbe908d6133a4bf52ae993dbeeb364d4fb1640a5cc34cb9f4352ee93b5c86fd60	1	0	\\x000000010000000000800003a1d408419d43c66b28d5b94c1f249829be87c95465ce750233fae6e888d629fea52623f7c30f6a72ba2308ecd300824c3a548406992fe7d1360f7eb16837e6012b92e54e7c0fe3b47d6342f3279f286163b477bb5e65a3952c736b22c84e52e9618cb6affa4af40f670c82dae12bacfc310cb7743f8f70402fff23b404623dfd010001	\\xf0adf8ea020ad41a781fe03424a04065502c0467d2e905ca78748d6a6f6279d7dc0cca6c7941f127025cd31cd748e2f8fd1fe07223bd2e884a7cd2244e3c790a	1654862117000000	1655466917000000	1718538917000000	1813146917000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
178	\\x9085629fe7b6975b3393db1df7cc98be98f81608d24951d441aeb328aceaa80ad4224bfa00a1b66bc97392aef6b6d08ac5ba5b964d07006d1011008aa5463659	1	0	\\x000000010000000000800003a6452012140f9578783c87aef8ad5a6292f7bdb00b16d3a74979e556ec8c26cb19824c08fb9923b8f37e4f23f2bf0d37b7780f3454d07e1a9cd57b4be1a18dca69b1e6f5492f72b1c0eec174d4822e0c1420da95de583778433e82640a85c07153d7c960ccbfc2f37e518c98e07eb17d896a095ec9e4d4ec3b357b459eb66487010001	\\x415a0974e2b23abd9eda016db784657076b96d0c1e7be24e8e5fb7ba9c68ff2774a748122c397bf45ed62e376882439f15da8c2f8edf0de21366338bbd9c990a	1654257617000000	1654862417000000	1717934417000000	1812542417000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
179	\\x94f93f6c05f7d5ff869578b1ca6a819bc2b6c90c3a7a6fb5243f54e43ef1bbf958459083d2c7a50f4361a174c76ff961e182899fdf19cfb83808b72343089894	1	0	\\x000000010000000000800003bf463abde4cfaf96b0a38eb86b662e278e6d5196befc7f2df359824dd0cc960d99a847908e5462baf40350a5d02f46948e1237dca4ceea273dad612ba33bbc44a663618b61e39862078e1350a68e536b6c676a57197f5ead4c8fe41bdb0cdfadd1eebf83b6f72dec8ba4bc8cbe845049d6247033ae778a8d6da65fc6428681cb010001	\\x24e3ce6f39936ccbea32b583bddf92146b076430fd36599ecc4e478c0f9459c0f9ff796dab843f07e9c408a4ededaf5ded9475bbb08b9d856637841f0eda9908	1659698117000000	1660302917000000	1723374917000000	1817982917000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
180	\\x9455c2ca8a787ad139d2052c009416b8b2b449e8df6edfcc0d28f495232052e65db143b76602eea30aa8fb648c7396d5839925c6d580c7ac71031ac4eb11788d	1	0	\\x000000010000000000800003b5f69db82c2ee71d05181561b3978fe25fcb02c161928798bdc8b5d5a87d5917a49c3ff8509ccdfa7153661c4d5a6cd8297621f7b2374551315ab3b3677f1851e8cb0a525d91f1bb5467443bbb52b43a248693882d80f5e504662067753a15bdaa2dcdce8d704e9501f36cb1bd3152c3990b2b8bf24da7bafbc3ca85981d91a5010001	\\x3399dbc85ea08893e9914d3a3bbde313685a6d016286db901bf35b0a5b361d6bc647abd988f279e288edef97e475cef54cb75c6e4dcd5bc642d15309996eb402	1674810617000000	1675415417000000	1738487417000000	1833095417000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
181	\\x95958b5ae06545953b659c84495e2996caaef333dcd1fff0d18d71afb098f24c637f7e044d1dc463240b26d92965a335b18b5d0caa9c9e6bbc9fe05dff126468	1	0	\\x000000010000000000800003d8cf88a4a33803d54362aef9b77013e40d908ed9a630b9d18424db2c4231105ba6d9da5d7805a3cad7621f86b5f47e57c279c4d4904ae17c4e3be4c4659886e6d9c4eff0900cbbd1fd8a8c65b70776978810ad510e78e8a2844ba83e40411b85533ba199ec9c5a5ed12f6ef518ffe05eb2b379f9da427f3029a4843157420a99010001	\\xe151064f5f8661c6300e45754563c99f040c7f93bb6c582af4bd186270ae0ccba98df4ab03bb8e93d4896fc7f2e6f94b97f9fef4e8ca381888bc64d38e19bf08	1655466617000000	1656071417000000	1719143417000000	1813751417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
182	\\x96d131642bcf097033d6f065b103ebfbc3b145521c2cc51f501bec33b063c3598bb7867a45eecff1838f19154d2b430defc227612c252c750f784bcc3212f0ad	1	0	\\x000000010000000000800003ca2333012cb4d5ffe2d1fd1f4a5a2bffe16e9866cd9b39c3f91b14ad96937417695280e4f3d071cf623caf9d8ab5cd757f237eb158c07b231e168a18a7b11f33cb06caf2eb0d93805369ed9ae4fe67d266b0cf0a64d20c1476d383541e3c13d5c342a19c914848345e411eeb39c7978a776e676e7aa79077bdd4cd30c8f60055010001	\\x2d3570ae7ad3f4ca7ffe7f64ac5c4781905b50e99934d30da4272416e5d737daf52796767f9eb975eef2b37e0c35c83a5b2c3186a13b611c82ce7cf2a1656205	1653653117000000	1654257917000000	1717329917000000	1811937917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
183	\\x96b9005256bcf0f58a81f362f43d558614a1cbc05f3de01b31bdf6a67a798305dc9f9913f269741f835c334d5d0b890c0424ffb31ab6a9208ecf65439e37427e	1	0	\\x000000010000000000800003e52c891478a8902bf302c4446e2a80912c2427e2f70f44ab14aec135eb5192da538af6ba3ea038b3b7ace49d6ce98d60ac36d0157f876d4400b244ce7e2551a414f68a7c6f45a158a71bf42d81d6836d41597fc460161c67ce26e89adcb6fef46f22402540cad3c306d754f2b9e0389fbadd20c671912f222cd448075e735837010001	\\xc209ecaa2975f92888818581cac13ba4f6e234f8040e017e3506ce6949ccd9db743b63288950995a6c271fc33d0e147e8eee5af66204f3feda0df4119a026708	1674810617000000	1675415417000000	1738487417000000	1833095417000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
184	\\x96b131d29847e8367ff894d037ec932ec6396981125910bf59a934d37854ec807b31e9c2a6c03c29e9281564b8651392beb20dd8e095c36940a798728b963089	1	0	\\x000000010000000000800003aeadcff9dc701e50f32a64ae0c0073741c33bc90dad0a3c030d6c9dfcdd40429c11cf72e738db3a4d92309205d1efc656444ea0f580031a151a3e5aabcb97751dd5cc4f752138c7222b2167298a76ce83119b0622db62099f02d91a97caecf372516543bb4f9b49272309eae6624bcc24c2e5c3ab950ec212c76286e58e740b7010001	\\xa4de11ba3ccfb449b441048640c0b2cf308e09a190c5fb4d3f87175d5f64a29292d0b4624a5ab6a0aa58776145f9e9ad8f8a82511ee804c41723ac5af6237301	1678437617000000	1679042417000000	1742114417000000	1836722417000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
185	\\x996dc2f14f1f57f6cb79d2da371c708a44307784d073f9c474b9e1888773ed246d2225ce9f0db83f68b84d32bbab3771b39fb4269bb71a56459c3adb13f9d393	1	0	\\x000000010000000000800003c0b520b7cdee56ccf457dffe38efd9c43ff08506c5f259d42ddf7fca8d3b4da07aa29a19165afdb24fef3537797c0567675718be821aa3add8dabc3546a5b06faac9a1bdde123a13dfb7abf84064675d87add5996d597fbac9ca79327d3f201fdb8ae8e274a1f7a8d0a3e0875879fd43d1ca9613bc44ef3f3f21f9ad8bd9beb5010001	\\xe0672596b4a1e402fb803bfe4a2e75436f23e2baa5746ac3d0ffedb3bc9c0618baadd40f5dee155d59a1492f9135a87604186a7070cae0947175c655dc6f7a0c	1671183617000000	1671788417000000	1734860417000000	1829468417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
186	\\x9e6173071626551529ef1406e8bfb21532915a0100f5735c967844d36854a5ba881920dfa64bd2c54c15cfd1e55b2d0fbd9a39e57e80a6f2fa956ec8889b789f	1	0	\\x000000010000000000800003d0a425c1e17ffe54bbea9d470a4b714424b498c68fbd3af7745166518f5cd25be7e71c4abe8d5e3c0125eecf8879ce71ef5d63aae34aca5345f131e5d2c002b09c03c30eb57d9967b072d5efbe36af2964ac9d3cbcb9c9b694c2ce5937c891f20dea9ef62b1f218280edbf79bdfbf0ea0660bc582751606622859993e08c9deb010001	\\xf70159b14cc9e57226d74962288b32ad530f0770a83101a86fd236b5163cdacd6c419db2a56a84b160b4ba09228f4077fc2b2af05bb38f3def6e2f56f63e6106	1668161117000000	1668765917000000	1731837917000000	1826445917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
187	\\x9f39c3135cf9ee570d5a3245cbaaf6a12e3b71fe07ba5a96dfbae776371fd83531bf4690ea101ca4d505ddce12878ad64abc18dabe25f0a27adc1d41a5051399	1	0	\\x000000010000000000800003c3ec7b996ac1c9240945f745503cf22cd07d2d76773c0dd22fe444af0b44b414beb1ce51ca3a3536ae184d1c7f12ee99e089e8a593b90c5b98d4e6ee29b76a9865ca5968365ab3f54cf038a7f11db32db19fb523725515c7bad4727c7c489bf95079fc6bd159679c1e27b08a54297418a91a13eff9e1281e0a126704f2cdb115010001	\\xd490b60af04a4ef830f551bce9e4aff9586a441e04f12f8360bb4e83310161a80ba338928313b2dca78260b23c7fdb1eb8ed5ce5e12730ba60da20f97422310e	1672997117000000	1673601917000000	1736673917000000	1831281917000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
188	\\xa955ef669903dea11fb21a490e08f1c62f19db7c116cb101c6dd652c6665e384dd861c7433dc2e8ff025dd1c9941d585af70ec81acf6d3ff9ac65a39bec88327	1	0	\\x000000010000000000800003e2daa5214b7257b98b888fecab9fbd3628605664712a044a313faab389c3a6d681fce1f091edea49833e7ee110d11a8c7638fc7a49d711e07725e1c029489dc29075c4fdf6f254d5cbb0998700babc514af3d89a07fd84a5bdd02470e3a21ce1133665e668b32e3a8f6836b92f24152a1b04ea4da25577dec08728520a5730f9010001	\\xf55682fd64ca7cba292115ec07a61bce237cf6762d365cfb0f606c7dfaa9c2ea674c8d494a7276491aa4e50d1efe227f198a34d69d292692a97f8a88106e5201	1655466617000000	1656071417000000	1719143417000000	1813751417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
189	\\xa999dd7d2d476e4c07b37dbbf1c2b7470f5ee3f595e0f0ee87a0321d51ad912f8bd8e84f337cf94ea5744aa410503cbf6894848e384476512b2edcc11f4943e1	1	0	\\x000000010000000000800003d3e67a13a1bba11247de3510a62a848a18e0f57a50bfadc95806093a3afbf7795e001e11eb8f14c0cee98f6c4a7e2715f6f765f00892e3a8b8acc1b62c811350561f798db6f97bf74c52e57a169a8b5aa2e907f07b5f76d424bd9ff1b842f403ffb90f4187daa6e1c51b6dace6be5442679cbba5a7bf7343a5785e40c9cd5e5b010001	\\xc18c8027f2515e8b2d200fa7ac57afebbd45c101bf12dbfa56f506eb5d02a1dd38c78a2e80d46e3a096b61419cee3fdc1449dcb724dc522491290c98c3cfdf07	1652444117000000	1653048917000000	1716120917000000	1810728917000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
190	\\xab9d57fbf9fca637fbedfa2ccc97155b5134cb7d3db9814e2b81e6dde4d34211261c541a7e9d8f803f328b319b9a9b327f111b9cbdd91ba75f13eb0ab4c519d1	1	0	\\x000000010000000000800003bd039b9b92df3db29d5a622217aa1fd55aa2d048b021fd9d1a6469128764642d91d9ce1bdca088aa0a0f965efffaa0b010857acbe499c888885bd618056a733828d7bfd5e9736ab2edb039561504cf063369a34f52e77b202360bcb092ee4fc4e4973133626a9256d3d8d0f1bc10c48f63347cae87a3b360023e742ebf6907ab010001	\\x1629b4fe34184c6d6c703dda424236ecf9b0e8657b22ea70fcf58652c76d513ddac7d8b8b783ece7022d114c229eb6dd9234a44198cf1a0269e6df0dbc72c303	1648817117000000	1649421917000000	1712493917000000	1807101917000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
191	\\xac31be503856a56234ee663db5433f9cfb3de06d2de1a46c4d75b0477e22751fe576974f68b12eb52f9ea2cac78d1b90b2b2a5637fc8d6698de4bcf1c36836d4	1	0	\\x0000000100000000008000039ad65632c48d492cefcfb4d17e441973441ed946c0d3167022e4a396066061d73220a50a9e517959b6d9776dc879e719fe720d30118020076fa6431c85ae57060e48f8e68b4cc209baec869cb10c98edcbb4d9228be64f6ffff6b7776a38758719d3060deda911a77eadc357cb61f13be81bf0b9c0dac261f7bd54f37ee5fe81010001	\\x8e6b8c2a332d31b618550fa69113072cd283401e289f511b0118ba90d8e07ffd820dda2e18b6ac207b6b1366b592315f2747102d3419319759b6e1e23a4c3805	1672392617000000	1672997417000000	1736069417000000	1830677417000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
192	\\xadc1df8a2090209df2def913a96eb4e1e1f28b499111b8a65ea0bfadeeff09e04f48265f7b98c1e54f565fe3d47bef7d88bdc737023c52c56b66adfae93b25a2	1	0	\\x000000010000000000800003ba6f152939281b8365949aeca74833ee2e175b3731bad81e352ff4215005e90b890d556ff8efb7b199ec2f5979a77112ab6c256b6f7a7a46e224a1d124f4cdea30fa95cdf88393935741cb05af32d74fdf575044f9729a8add21e6fc9923095f52b4900977e06c1585f9a62428bf5c11cd6008c22db3a1944932ae1b97d460d1010001	\\xbb22dacfd479f81216ba8fb25329151e8108ab2650a400f7c6b66dafd881c9c95b922e02c1882c0381d7c9345e625cb1cb7e9f04761e5025fc10c32d93920a01	1663929617000000	1664534417000000	1727606417000000	1822214417000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
193	\\xae9d133765d06908ec0b58ae4561a02e7c00a29e8e325481f6b87b4b29e18207afbf9c65036af95b37f35d71bbf38234a9158ed4aad9043936914afd2d1a53cb	1	0	\\x000000010000000000800003d2dd96e9224f53d6f51e9d02f8e653f74908c5fcd1eca8a805942692b27f5778a0a66283f4a56b5fc46c8b0756e93afa9153debc246136b4c5558f6d28b411b32a7ebcb41ac3d9b5a2bf74ff582bbd72e4bc6b240762f6b8a0288836ba5f3539828af3d842ff476c5f24a855644361a822aa0c8c3d9f518abbdcfaec72fac949010001	\\x6e6e08cc93eb32c3e1f2342fcd38f460a7f3e5156c5c756f30c583808dcc0137bd03ecbc00ea850b63f186aa65c53d21e1993d61ac2e4f9535acf9237c05cc05	1673601617000000	1674206417000000	1737278417000000	1831886417000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
194	\\xafa971449c7c3e2ee9387568d680588b5481874ffbfb799284a332609543d191685ca503d13ed53647c48cb3f9b8f0f30f4eaabbaf12522bcc810d6b012ef897	1	0	\\x000000010000000000800003cf547f194b98f0fc77f549b77f210d8a004653654b2c3057cbaede497e925c5d2415ea416f945e72db200c64ae500f47a714ceb8151a6d9ee53a011cfa5e1e0e349770b8ca4226ec31ae8602b750e9fc3c2637c1862718a4eba198fc1465bde49807a388b6c2e90a3428e5e52993146c3a3d9c7203e084733351aa95bad91bb7010001	\\xcada777122eca9e907616c4956b8875fb832490c5391bc51156a0af639c20c62f0c8dfbab9fc23cf2480925adbd83c2fb84d50bdba1ab07b28ff5eb2f9cb6901	1669974617000000	1670579417000000	1733651417000000	1828259417000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
195	\\xb09199ba46fdc1bd85f9fac6464c72e64327810590a5f4fac6edef20af8ca09a804f20db2f5b55645e54e1534a455a19cf3259673daf5921e123d1d037cbf1f4	1	0	\\x000000010000000000800003af8d66dbed0deb25c725152c34290b60c858fefd0dfa5d649c74a1f38525708b278f2c3d643b2481a3735617da1cece1027961d58245c114d9b1ec8e5b57947548fbd77153c608fa3fb41a32674d45c67951f06f2f9040e5f4682f0f7516aaa0af10a2298839e9948d90f91096f8308eba4b9710b1b6fd001339b7169b6765cb010001	\\xa06733b58fdb4a1678a7bec591bb6f23031385b89ad6f4a2e630627c251ed19319ea63fe184628082e0f7d1cb5b08b7df1202da7de423f1962958a860b7eb20b	1667556617000000	1668161417000000	1731233417000000	1825841417000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
196	\\xb519b18a1ad7e011504d2a087b5e1ddc13fc615f9f4fc8a37550dbf20d92819368ebe7c1115418281aa17afde5f9aa3ba0ad65361a504b0cbe9f30f10a87946b	1	0	\\x0000000100000000008000039bcdb2a1ebf26fe190c3828a4da4899f15233efbd51eb6cb4dd40b6501f1fb5f66b10dd132332bc781ae04b2d1a262a12f3c25d794117da33219161af5f543e20eaccc5c040c3975f59ee08c714b8c225a222df378d9ebf42bafa892fcadf0a2b2e67a23ddd5a6f217bd8fe2efabd95f70aa2523671a54561d0e0176767fecdd010001	\\x10280263d6d4a1a35af71708af063152b98ee61cdd637427a4f31b7f5b1da663aaf6af3cc1964374ebd60d7f99672fa0f64092526b31a31097e53b2dd33d9d04	1653653117000000	1654257917000000	1717329917000000	1811937917000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
197	\\xb549c442ee29d2fa6e13ef62d7f792206360a48ef6b5370f78f4b20fc83d5f3ae0cb98e1ebe92733a911039d4c80556b490f630e4ed58d34972798a05ceb4fc2	1	0	\\x000000010000000000800003e1ab8151d52841f844bb8698b4876b7de9eea8600414189b57888ec47a5b7fcd8a0d2365e2735d596687cbf634d7036d81cd44fd014d9475e24ae3bd4b7b824649ce5b40ee27e87d03ac983fe38d3d339f6a250b0418974bc9abc2fef6e6415662515a4ddeb05bcac8d19e19b2393d1cc1165b3fde075574eea8710fa9451c13010001	\\x2faa2bc322e7c327b340e742e561dd53e84afe29e5182969945a0eca56a2d6bd92db8ba59749f896317e194d18c2806f671277f0cc5b700993871b246dde2b00	1666952117000000	1667556917000000	1730628917000000	1825236917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
198	\\xb57da2cf6a78fcbc11ca2017151c85b3150a0db519df036a343af793684982f2c5c80b36f99cdf1c8ddc19699c82bd15e4ef9ee7dd4c8dc98cf9cc06897c6293	1	0	\\x000000010000000000800003c4a0d10c7a4033b7c70f5d21d1a23d0aaffa9f33df267c014e14dd09a37f3190911fbc2c138a2eac6d8897f7a9391559814eff7494a164b4c48d154997f87a06abc037603dc8c7d476e6ba05c533bbbef8e477d497a3335bc0699cebc01532a00f71a055cd604f65c289355495670ab17ee35f124945c894e5fcab87c7806521010001	\\xd03faf242561d8d3475c971988d018d0a58a58f0b382332c2ab40512c0ac146fa2bcc6299fb7936ca4a220a0f8a1bbce047e67c0b381995ac49bdd6a377fc802	1672392617000000	1672997417000000	1736069417000000	1830677417000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
199	\\xb769b710916e92b8963af8c8453fa2a64a0805cf4df0e0f1c4fcb6c54197f78640e90a416a123802389a7c89cc6eb8e26602ae0ebd926fd74100ec07d6e57017	1	0	\\x000000010000000000800003c29739d4f68440ec14fcab8391321805f2125883c06d2d8f39963905ad40488e2be16a73150df1832fa7c8cf49a9249ef62aac07318be66b495d5ae3a76c9e680e03aa502f1e49240c9333ca71bc4bbcd2ee6d841cfc66efd0752845b8e56bc9990bb613c63f64802ac8ab278c509ecbcd24cc32e29d04a3a248d56b794d0045010001	\\x9c0358e79348187396768546570f5838e73eafdcc927f321bbf95b7fcc1b5fae1b21d6de6e4bb9a07ac7100a1edc9db618b30c0217cb70249118f03fb95db60e	1668765617000000	1669370417000000	1732442417000000	1827050417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
200	\\xb871e0d62355f7d35fe312f7384e243934130344f3bb7c046abf6d363ac9f44f20079a63535dff8e82f4552c698821c4d1e3f6156dc433ad212795f2c1cf6e22	1	0	\\x000000010000000000800003d8758319c79fe20fb8b0b32fb9e11173199739e8a28eafdcf076c4d592b4450ff48b425101b9956532e8b4ca154b188f47ee275d428ca26baaddc8d19782f4015e58c63ad7e271a69a9c261d66d40832cb351f6e8a3e0d278a8f1c76dea871e7d61a52dd3004f1096812a4071de95bee1ce8bacad247012e7e9000408157c177010001	\\xb81fb20a03f7ea89f1f694396360df1b23f64eda90231f4e3ac0a0a8ac7519ac21af42c329d4c8a75b5cd9e25b538a35cd8649121504e1622ebf34b6eed4f10e	1670579117000000	1671183917000000	1734255917000000	1828863917000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
201	\\xb9bd6f87d4948f7e63a634be4765658975555b02afcd7b215825f4c226a3b5eac595014466f6364d3151d740d001e1f268427e94684b0f521f8685a317aed6cc	1	0	\\x000000010000000000800003a2955042ba3a75805098ba3abb50c8610f8f0b7d16007a35da85c65198ab54841b73d23b0c250a4a3e40b25f20da69ec3defd0cddfd4025229c05bef5aeae933bf76f1ba810c087b968bd2900a10f6a3fdeeab353cc840e2993b385075d04ad8aa47fe6812fb16cf613168fac3e0d7705e8074b0879c17791d85dd9d70c2fbcf010001	\\xf73fa21e9a0d0131300c44ccc16147d8740083090c5d555d6782b815f04ef0fa388d665657ffceebe950ef8ef152ae36175d4487e2cb6a54e292f70b63fd8501	1674206117000000	1674810917000000	1737882917000000	1832490917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
202	\\xc049bbdc2d14643bc9cc9888c1fa18ec9cdffa06e73a4d2d06b6cfa64f6de3541305c8a71e01642ecf6043c9891083b0378ff6260224981cd8aac619940a7761	1	0	\\x000000010000000000800003c2c63f2ee2eb23637e337b592cf4b5ebcd179e16c18db5d2ae0e9ced71eccb2043fceeeb52b4fd561fe5d92081c71537c17f5b609e9a6b0beb47a0628283c184afc960a1c9cee29744ec0b8ad7eac1b031c137e7c288328701fd25b7f1aa7dc1a9807e9adbef67920d5946038d491ecdf3a4b7db0ef2db263daae38902bd65e3010001	\\xaa61d0647238c3ac87b68f19390b2deed03a274ce66eb4fa4bed47455c100bbe6211f040256ee371c23d393b2d16b2659b03de0f509034671625517b1dc9c206	1677833117000000	1678437917000000	1741509917000000	1836117917000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
203	\\xceed41cf8000ba7b5872c0c96dcf171e9d8e74423e3134bb9aee16cbe61e1f43c00d9b952c66a9ba758f6e08c07f7fb53ee9e40f8ee74b7e701bb9aa155a6b93	1	0	\\x000000010000000000800003c4c826455eda454b59fe97dbaf23ae4717365495d83f950d45fc9d13824733586e1f5cb519b2430510251b572b5ec7b6fa89cfa6bea6128f0c4f64fc4503323eddcc822ae34288fa90c0556ad1c5d81cc6d8cdc7e43cd59870b7044b4485d50ab30377ca2709babd6993ec5269321fa5b9517bb4ca8d8efd24ad394c8979d407010001	\\x2eba7cc725cedd30a3f627a6a789fdef7fd05643ffb4f8b847325216c9e57c3a1db75dfbd9a13e0aa13b9201a635c3cbe30f8708b956f528a9164f0ce86d1f0a	1665743117000000	1666347917000000	1729419917000000	1824027917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
204	\\xcedd55238b7b65a6300d292ad87bf11f13962dc97c68d2b4b5a165a605e686befd1cafd4db314078eaa7d766431aab4ca89e30421e936910a56abd77c76fcc11	1	0	\\x000000010000000000800003da31cb9e32f6d73da81a9e9da7786a6446d34a626b52e42bb4a46de0924f64dd5d92b0aa3b23fe1559f2b456f98304b5abc7e463a04b2478b89c3d93d3de963037b109deb0e8b245d9db0090141f61bc7b66f87959cd518145e225b3f14d74b55b259ad971d79746ab8c5950cfea4ac84ec2b7a66835ddac04bc52c0ba4fcf37010001	\\x947e37b6bb242e1ef122d71aedbbe066dd1b745f487bad45de808f8b8332563edb44dea023bbe9f96ced7386d787a1fdc41776db4c38778321ec5875b5b4bf0b	1671788117000000	1672392917000000	1735464917000000	1830072917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
205	\\xce51407bde75e002b03572dbecabc1013561965ffe533de753760441f0323d460847725c136db5f6f1d5c7fa04e7a94f427974f795f1cf0e91535d86c4cd5cf5	1	0	\\x000000010000000000800003c12ccfd46a81def87f0dad0ee89897860a6c2f393f1aa203d62375a5bba9628eec7774bbd6ab75d8f9edddec971ab9f0730b3eca7894a5962619c25dd68de8f1718d4866c45478dc829e0181f9e3444daa537ffef2bc854437e23a36b00ceba36fb6b1eb1ff5e0dc4e0ec0b9390bc00a60636ac1404e6d06094aa82dc8f89779010001	\\xc49a867d3dcdc4fdc96a708431f4efc9014cfde14a8924d6d74370f8b15d3395c5b55a23b77fb60f95e58744d357620e234e3af7bac41cc72b702b99b8c99409	1658489117000000	1659093917000000	1722165917000000	1816773917000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
206	\\xd15d5804a86a00b1381094ef17df8598ce33e17f2bc6675552cd40d7ba5b72f6510ee11e1fb17affb4de52847aa68ac63cf1450ff0495e62a409e7cccf88ddc7	1	0	\\x000000010000000000800003f0a7c4355816b1672fcc826032527e8b1073909600770ba62396287ef9d839cbe2960eb137eeed8a220abeadbf8ee726bb4d4e9f6c53371d63f60f3d3741a3102d3589f1e24d51c0777320201c81057b4522c1e9b3b979db6399c1c3ac1ba0028fd4d60feb4ed1dfb31092ca48c29a6255537da9a08bb7ef04bd827423fd7187010001	\\x29b92ce83b5ccf807fcbbbb42f5b4fbc7f5eaf6692e4f885edde28e7c812a4a91e9a82c3330295e6c37eac4b84152207587e054171bf09295a3af3571f61dc01	1656071117000000	1656675917000000	1719747917000000	1814355917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
207	\\xd3a94b061a2547c784030ab59435c52dc350f2daa4a20d3291da3d9e3bac249890a65c07dbec228ac98764cd1b799437b9ac46fed038aaff7a9f060843556a9e	1	0	\\x000000010000000000800003a1edd6fe31bfdc3119c03dc793f7a70337079777ac84a40a9490ae4dbbc2798d82e03258e1a9a86cc81ecd0bcf1e9f2167a05f65e5d1548b82546674997bbc2ad4732ff48e62c72d4a83760990a14f75ba91213271793162cc73fbce890cfabe0f954cc9fc68ae91181c670532bcf30a6aa2c20673b9884d8f8b089785593011010001	\\xa0bdc035341c55d879faf6e8dd4c443d76e8a91c131d0a29929d270846e7e56361becb6a9cca8ee2ad14bc3c0413266a23526ba20bf45b946fb4017ebeedd803	1679042117000000	1679646917000000	1742718917000000	1837326917000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
208	\\xdda5963caaea0fd4371e7de2269492f9e4de5f1d7b8fd1a30d990ef99085a09dd578a5a9a069100e9385a3ee6de719ed2f905c6c4afe133252c0467e78670f57	1	0	\\x000000010000000000800003c4c3529ea343280d0826cd9c1caedde68b7c031f5d637e6d419dd9d38308de62167f796abe549f0ebd00e02a8207051d19ab95abe32674952c09ea9c7a8948e685f98d48ae20fb03618a1a3a40ec4d872f34a304ca79b59c6e438506d314383d416d6eadf1ce7f609cf49f241b9dcbfc8d353eddaebaad7427577cf76c282fc5010001	\\xfc5a9477ae42812c1f0b2fda29b28e09f9011ed8c9f4dade7b909c7744ca0f957d77726d3fb1228363c62699c03baa2a52412d4778703f138a586f4159b66605	1666952117000000	1667556917000000	1730628917000000	1825236917000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
209	\\xde05e81be3136205967483daffd666570b8f4f3c05c024dbbc69fc11f3ffde50d4d09da5b6c85c8a9a7d99b0b533f111ede851a6350473c982b42b362dc69feb	1	0	\\x000000010000000000800003d538dbe7ea008e84134ce7aec183f9ea9f894e58fe178c423f69a740cda4766f30056e721cb494b35aceea512062773ba39a4ebf54de46f4da546e47751f76d1d6297296e608bb5dbec29c769bca0831bbe823b23b032a66248f015ae31d6a4233a977440a97e071361ed7bda63122ed2bff3960ecb323ac8b10d7a4eced3041010001	\\xe804f7a3bf4daab75d3de0a47777e7b8fbfc1acff5104ed7f6ac9292111e9ac1a645d92aef400a39cff069b790768def99b6ceb91af35b90119e3e2dc1761d04	1648212617000000	1648817417000000	1711889417000000	1806497417000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
210	\\xe0c9dd7e322fae33aefaec4212668f06d9617f298910752006c8e2ef33a90156d8411bdcf29bb3b0d1e069059c9b58a24e0bb275fc403d30aa61e11d9fbebbd4	1	0	\\x000000010000000000800003c1a0a1632584f1fa1c10d191b7895551a2b9cf93a9a89f37b3f15da4fe8e665108b7f2be2357438b169719648c9e2aad2144106bec66b2ad5670dd556da7ff8b3c931d5cde73f1388f8fc839a07253a3ecfa78f07cf22e1f3334eb344c8ce7c92a40750083f4036852d767fe9402853386e92c134e517c82a11cc469985a6d0f010001	\\x6c3330d1343df796750ed52669b60c3e70f11d117bbefbdc006a233e87b4d8411c9d1df085d9bd523a2ac95aa958156b3419f36669cfdd16f44429cbe6db4b0d	1672392617000000	1672997417000000	1736069417000000	1830677417000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
211	\\xe2495616a96c30ee79ae056de5a98124fdcae27502d81c859f5e8d3c0fe82d536f3dbd21fd00a18bd7425ebacc811f4e6a18375c5172b0aab7a95f5e425a779e	1	0	\\x000000010000000000800003c2e200daec51ceac9b2156bfbcad5d9ebcb77523b6e647f7e495041cc606427078d434e4689712730c4d18f371a6b1fedfccb9d262575a5379dd24e8a04135db57808dcdf7fb5c99d4e13e3d3b9d48e4975110d3c80a04a2da5a2b5e49f549661bfbb28df4f8b6678a821539664bda65b8ca750a969175aea318400fd3d7b819010001	\\x03e9e74924e1aab8defe461982a1c509694b6a90ed923f1fd31a9d8eef9fa3f0b18e7733d45d1552202833ac67aa5470aea0a863f6f2885ca01ed48d4d93be0e	1664534117000000	1665138917000000	1728210917000000	1822818917000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
212	\\xe4f99ca7c9650a151b70b23524a92cb72c9de14df52d9282431f27d20a25c202442ff69271e6646c7922ab02655016cd4d10433d309e5f3d40c051e1f123304a	1	0	\\x000000010000000000800003d84ade81c37f93bbf5bebadfb0d944e3312d46c2d1ae55f8ea7f6c9b55c20c944e58152ceeeb6ae5e7457a55a00a1fe91fe60c64890382169d0c7b36de21153a50ecbd489d41cf7f5f00efecd9217960873844042003452e2911c6e160629a5f2bf3a68abb1c8deb1a72b62ce75c0269fda27876cd1dc74b902c9a63cc292fc1010001	\\x0169d155bb4657655e968a14447c6148c543fec3ba9174649998bec8daa715f2eb7a42b8a16bcc32ab93ec2b0e6fa7ee48e5f6b9eac7084409fcfe9b99589201	1665138617000000	1665743417000000	1728815417000000	1823423417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
213	\\xe465dc276b53bebe4996a5aa25c06d8a6a724505588704e0f31b41931092dd4495e5c1792de2486ec869260459f431c6904889fab37bb66ff3167626f6cfcf74	1	0	\\x000000010000000000800003bd8aca02c57428a6457e00351219144a29a4bc8e7e6f2f69de90ed10225e52ffe65b278518a0af8e52f942df3981d230d44c410da9f03882c0bd793ddca53f61df90639cf480ae9356da8f90ec4777e9a5280595fecdafcb9eccc4c43e3352e4504a562cc5223206129750f045a8f1071e7576af68f031445977ce3decf080df010001	\\xd1a1e35dac233c88d744f6361daaec21b125915f76ddb90b75da295c8070d26df31616c8cbd9990839b7971f16ac7cdd972ce0c1187b500f26350dfc93c0a509	1674810617000000	1675415417000000	1738487417000000	1833095417000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
214	\\xe615fd9d608c2afe4b35680611258f7535e4ae3d2bccdda15f5ebe27098d90221e30723121fc5e9043c2b2c90b72558f5802487b8992c052f11b7a0efb76a5be	1	0	\\x000000010000000000800003bda453575cb106b9a00673d96343f42b2e9167a6a47f46c1b7c216fcb5be1b667cfd287845b777b2f67070d794844aea7683e40464bac70d7acfc34f749bbc3c4a9b2b33bef778324b1e8489b1b7f3263694f17d705dbc786388c7be0b838ba013184c5999ce3eed7953938af9fbb8852b02b0b0760f095d7257442bdf7fdc97010001	\\xece22bafdc8ee1424fd7d7f56882b33516ce4413828042ec6dca81bb81a3fd95586cfaa27fffe2335733935d482a677a2d643717785c4967162091c8c9fd0600	1665138617000000	1665743417000000	1728815417000000	1823423417000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
215	\\xe7b11f9068fc91a21b38d9633498c011fb16cdd1dcd4904c9951f86952605fd0e52e04da77f9f8b619fd4c4dc3f80a97655e7217d244dba34ebd5a8781168517	1	0	\\x000000010000000000800003e9349c04bc2643a4dc49c2af624cf221fb5608249169fe41baea6f51e60ba1bf414f02f29a36ec7501e61e8da2518b9efaf19befe675cfcf7c3d22ee33f3bdbf15b448b440056e6cefdfb2f3f215072c2d150042ffac697dc5304c3d9a8801084aadd8779fb092340ce6ee100d0f554f112198e3880e3866b4e6d9e2fde97757010001	\\xc4695c6fdf1e2d4c6ddcd4b5d8fe10415366bc40d39f0ef533d6aba1b7ede2899ede886f8c167f7baef7ed54231845a32dc3b9535376da4c792705b56bc9ca0a	1661511617000000	1662116417000000	1725188417000000	1819796417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
216	\\xe909bacbc1c48d7539e211db7dac92455f51f1a4068f2c1ab6feb3d238540724373e75b6170463fd3f7867e60135b0ca81363bccc8e1e962f1aadb4689e990c0	1	0	\\x000000010000000000800003a195c1f74269cad872f68ada101ac9dfa8b172109f20680faf2c4ae215b269639a42f932a7d9a4f46ec87d1f8b978fe188f8fcb379594ad205296d2b79e7ab2a0a4f1bf4eb3e8b4691f44b1a45618cbfd1c7019a657b821e6567eade9ae29cde7de6195adbb97aa0f80dea165df3bf608e06ac2e515456e64e7d6064f054528f010001	\\xff8f8e543f9528b49b0c98f1613fb18c8aaf70a79092881b9eb5627a27d4d14c253739bd2fca2a2994c1ae9bdf36a616ef9be5af9a6df02d2f8d6c19fad07404	1668765617000000	1669370417000000	1732442417000000	1827050417000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
217	\\xef61cef4c55f17d8f8ade3ce813cd27492ab1315144dcdb0c72847bcb35516239b997a8ee43fccfef7ca540e1fa34c85fd8bad4a8b0792b3966d27e2f5b3235f	1	0	\\x000000010000000000800003a2b645d555867155d026637b5f7809297d89e277ee07b4f2bb4316f3a7d9dfdeae2b232eb12081c4680382785fb9d0e811141100000b87b7826c9a33060303f4409d037c84c47bf82871dd639ed9468b180b921ca43285d2545a97d01a787ac404b416875eb701c7fed4f7283376ecbf8a1f0dad869403028fd2b4b5f3dd472d010001	\\x174dd5c2da42eba6a5745e88d8c5b3d0548bd055397be88501e2c31cd78f7f08477b262a970d441c75e404ad5d5653d5e2db024902c05cea25d81b69de96b204	1649421617000000	1650026417000000	1713098417000000	1807706417000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
218	\\xf201a41ec776a615e815f0cf1e8bb19044eb300aa5b472bfe0a19951f8dc0b05541b99e0d09658a531d15d624f4fa278a452d8625cf488e3d5a209be22488d18	1	0	\\x000000010000000000800003c72cf238d91cc3876239cb32b164436ae454c5d0d828f7c16afe615be6e0e56eeb07c47f2155f3dd18b9e210292b14bcc11712a2b192ca39173567c6067ebce205c7f0ccdc5f03f135d04ab3d9e4273eb5a8499341334d74dca1b8a10852fe712a9b3d6c475d86a27ee3199651c4a16c6e7b36bb049189468e85b03506ff360f010001	\\x10873f2a850c9113d0f1c04039f0a829f87da75be152d10a42a211d8cee7427cc50bc6ee5287784204b6d429a0497e0a0fccff56d29ee3a5fa387b2537af0a0d	1677833117000000	1678437917000000	1741509917000000	1836117917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
219	\\xf3b58589f52428aaf2c534176d78fed4ea84f8ca5d4a04e864e78ed029c55509515a1889899577942de337b3b1e1923f7c0c60f7b45c712b9e12a81cc7dcd384	1	0	\\x000000010000000000800003d9dbdb9728422d882b137a871fd0597f6304a08245539940be2c488c37eb00e5359e2efb2cee352d7e468a15f5bcf4ceb2116411c0c03a14edf1172f9d794b95f0939a9978934395026c3f2d757dec011510adf21bc1c86edc293c39945608093e66a32f0392bb4f11902c5dfcfa33db21aaa3d9a88954673a57323021c93c4f010001	\\x712b6f83b01bc00dfabcc8552d9d0bee8f4090ca244e8bb08476a99101522e273be6cfce4f47e667d054d9f0255bde47d95a53ef13d81eb7d6726b95e55a6203	1649421617000000	1650026417000000	1713098417000000	1807706417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
220	\\xf59941892bbc392ef9199b9342dad57398b6d5a93203e056e5af92c4d6b753339259d976b7e5cc26e6bc4aaa6caef13cf83970bbba96af21a742f58dd5f48a07	1	0	\\x000000010000000000800003ab273edae30e91965f35c06d3e21ee1840f72164ab1fac83b61a1df153689fb4a4b97cecbc0c18f83f23402167a74825a0c2f766404275ad9adb4ee2560fae9db1db407949f20d28ce76ce29e3fed815c4b0700c58e3f04f1bf6983c9a9b9af465069bd23f3ad90fe5daa57b8d8ac0ac73794a3b7528fe8990bb2df42012e065010001	\\x53fb98f75ccdf911797827d7fecc946a545147950409bf6548ba3f3d41d5a6e4d08c945e8e4e4ba4173484d873427c5691e662c1c9c73758f813a018ba16ec05	1676019617000000	1676624417000000	1739696417000000	1834304417000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
221	\\xfbe552a696bb7f4b75850946a398fae2a0a2192389bb90e05fe6ba62cd660a3846c0fedd9ac53bbc4c26c77e1e700cd2600bc84fe0e9f786a96e729f204f4b52	1	0	\\x000000010000000000800003cc4b2ea9eae33357db5da8e20c08e6db0b27e34836c57c7380504116ee5b706b3bf7b44a6078c92fb9465b486d67f1e2dc2ce6b1b794b1f5247b9fda5be62b49b397cf401d16563bd0b82676a9ca4e07626e39d9dfa32806304aca9ddd3eccac09a70af745c574aa7522e230ac112d7f19b2f4749b88fa4d9d30d833b7210ded010001	\\x7088d9fdee2cdade1b8ee7f16d3f5b2da06712780635321ef6f87d151d85a2297ad94c302c7f08c64c2a1bd949b93bc6e3534785de873eb1de5ce2d72fcc9201	1660907117000000	1661511917000000	1724583917000000	1819191917000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
222	\\x0022934582843366179de5c13c353a724270173497e03c0db701f92b6f057075610432f30ad606df24beb7c99d7302f9b8a47d05eed3a562dda72a6e55dbb72b	1	0	\\x000000010000000000800003bd1f3ab2a9ae52ec310e3ad033024a76256d02276a463d61f3755b6ef012c9dcac1b9dcae260da763bf5adc0fa0bfd002e58b1ee331fcc7b79fd9a8260cd10f514e56d92e7c7956616ef87284cc3ba0af0d58627fd0656927ae05fc22bcce4bc79d662ae4a85ac1eeb094e10d3b9ab7595ec15f84f29b20c1509e5c836fcb37b010001	\\xfa1568233f3126e79c9e8fd9895e40caf9bdff3cb4615c0634dbf728001f1cc70980d6548812a078764cea79c6a0bfc8a80d9e9b28dc2bf73e6a0f0a6863e109	1654257617000000	1654862417000000	1717934417000000	1812542417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
223	\\x01feb58184fdb4988b2f4954bb703384351ff1d76f9c5a14b996beb5f8874af342f0fa36e1304d54666ed22f9d01c72548755bf1fd3bef1518f2d5f22d5636f9	1	0	\\x000000010000000000800003c84fc6587dd531e6360a7ce07d8dba29f15b5912b54361333c17d6579c0d744e1d21a73d24ffe05251104049aa5b1d1583f3a3400d6edfc332bdce4e5598cf3eefbdb5d13de8229b0f9c9f06c2069510f65400f279fc3ec6588bc9c59a7d3211b92daf6fe4ae03ac5e11bb4a06ec85a49d680a035c1dbd822357b29082115785010001	\\x53883effac95f221c66f618ab9881566e03eb38008ab970b707756edcdd7a452d7786f3445d3afe8fdc8a73793e08473dc1001d57de858f2f74c0e9ee8a45f0e	1668161117000000	1668765917000000	1731837917000000	1826445917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
224	\\x0b1e46d2ec3c0a95190df04cd6dbd02cadfc93ccd38123accaf22c21893a5c46fab603d5562067e1b4476609ccf4250ce2b70b310077bc85f97e0b91c7440bf3	1	0	\\x000000010000000000800003d5eaa865a01ada07f4cafecc4a135c129652ecda7ab8d37e155065ab788b0c67db8478283166a71bae901140f575ed42682bff6e21917b34342b919008f1d8fb1b389fc4c8570e10c272509d22619c484f7823c1e001dc21d09dd5251efc1543d2c8a45701995831487c63033abbb5174ef35d9b7b1278d9f1ff92182c73063d010001	\\xe8acd1b74a6eb4519eed56e689edf608c0e30d57eade3f68d5a5debd87d9fc89ec8f3d525aa2b73a57e7c4604fd8611711b2139a2eb70680edeb9cea7dcd750b	1665138617000000	1665743417000000	1728815417000000	1823423417000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
225	\\x0b4acac54537a2cc0d2fac8468df5d84b2122713b37932d597ea2f566981996c1e5340c681bf92df65162d743ebd6abfec957be4405061c345d28c818995fe57	1	0	\\x000000010000000000800003bf10124e8e9154c7646032c80a82db59a3a564914e54a51a5c912eec13c3a7e1bf5e3b61fcbbc56e7c811ead91c17ea4ea6dd34de7ed7a1f46b070bbc8d88b7f1e26ad1679dc8bf41035abc16cc78447bd1427e1826ddc914bbf0ae6546acb12c8f820424c4bdcde68c49ca137fedc64a3cf806745dde27a2d0307518686f3bf010001	\\xc34d39431505aefc5d89a20af1917ae76052ac9725606a28e25b24febce8426c2dc11e992b16dfc8ee009f52f9558606e9cc59ae0f3d38bda06349c2f83f9103	1649421617000000	1650026417000000	1713098417000000	1807706417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
226	\\x123efbeedd895030fe7a9c60c5cdf4930324021756eb9ad4b8e9500066f34416b87d913e2e6030210b84824b6554b131fd44240991df92072f33ba2d2646980d	1	0	\\x000000010000000000800003c6bb9f42db2fcb189889b5abaea7f644d055f86b3565a8c231b706a246ad922da42470c07bbc93121d68538b157e2ddfe13a9942116036eaac8e032d614eb7c35cb90abaf7b800ab146b843f8094cfbbb010e5f0a551bd8b133ed8a051137af99695a3e5a375c8985f367e97e4dce67c8e1ca3aeaa70607396d37a3d42829511010001	\\x2cd5160c6cc698e4f7cd674783a3c2ac5d9c0dfaca260bed26cad009741ee2a123a23efd937dd757b9911101183bb87d8015863e0502399efa86610d5ac94204	1677833117000000	1678437917000000	1741509917000000	1836117917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
227	\\x123e6800954de247a756feb140a56c134a7fa82d1df42a2f49b09978f456f627cdc0a222a9b202bd4252dea03d3a27a8fbc63ecab58f66d22f884750ea3a9b08	1	0	\\x0000000100000000008000039f50320d6763f8fd68dca7ad768c65c011a3259f677e1ea29bf3e7be62c37c839310c1429fb189566609371ea510657a86c321004616de6c9b477fb1a394d71e348dc8bfefa21e85c917947b544785efec1d6985a810e0c9d8a360a93c18f045052d533317a15c5c3e4ff3d4c01281833a26a7daf0697b5ca0052317ce313235010001	\\x65ca0b75d46f4265ced466332ce92584af00f4b54818e0ad0a9ed5b4f6b94626eb1f0cd94da1aa3f0498fcbf66ec1b604ecd49e3a002c62582f0265438a95602	1673601617000000	1674206417000000	1737278417000000	1831886417000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
228	\\x135618e5965a2a31eee28c84d122aac9fdcc2a459129332f729d616e50f89bbfa66f4e1d65c5b473d4bfcc49410f73e065006bdb06e6517791b1e4c7983da964	1	0	\\x00000001000000000080000396d04fc0ac6d8f3a86701b970ff4131a8858e64ce75dcfda135ecaddb0a821ee47db704f810cb9c71d5f1df7544628b6a49ac8cfc4b047a7ba62352904f4fd7e486b98fac20c542c296c94bf61734be362c638967a95c2d1a97dad45443e06b42f027c3ddc99314b5dcfa046a210f0c40091532b568c0a3a81d37f02aa944bdb010001	\\x97c4c988ae2dd359be17636afd8a96ca1ad67790b6c0d946dee430f584705c472180514bd96790b0715cc71986ac83232866c06f59281e5dbe8b0bd7177a7e0f	1649421617000000	1650026417000000	1713098417000000	1807706417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
229	\\x14464c608d69a88f54ebee299213a2cddec2f8feedb0fdef9c4e0cdd6b84deb275e65a03a59613ca017c1f81628ae9917027b11f9436529dd8eb0cf49a500376	1	0	\\x000000010000000000800003c27b574f8ebd48b2567011c3cdbfd55e8124c3abd5824959bc9cee1154b0571e3b7036df1ddee1c9ba0b051d7ab1165b437dedb2af6d1901a42967d5661a4e0fce3402c98eeb00ddac1cae081a42fcca285186e82baa6c40bf417302665cf71df50de0e369ee76d85c743e38e63fd9a5687bc8de1c8af1fa608d2168ff338ce9010001	\\x7eced4f85fd6a9682e3f8142e60d4be17d18b63ddcd2d17b8cc306d7d901ef86666dc61c7a9fb53200156a7f6037c646a2a37a1813bbcf9fdd7a9ca95efb800e	1676019617000000	1676624417000000	1739696417000000	1834304417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
230	\\x150233cf874f985f65a1e6bee5296ccfddcd139a10d10fd727c5728571869737d9c65d75230ef812079954ba4b96e575db5132df69666a7b70ca40cf45623430	1	0	\\x000000010000000000800003b55fd430c8ffb6487f9713e7ae0ba96eb27680c61703665d78f2ef1ba8722776ed9b0ab6a8032fa19d81307c11674cc899b5a5e948be94ab04187974df24bd37a1110418cb3e907bef63d955c2e4802ef9e31532a00dea040b1e181c5af4168e00602e3b788c2e7d4dbf6bbcb9b5df61163bc9fffa335229573ea9ff342124d7010001	\\xe96d99594f3c24ee8cf806239b9ec7946dbc6cbc877d5bc9371eb23bb6945c4fbd7b98daf769a74b2db9f4058dc89312ec6cb7a9f68385bc682881da228cb600	1652444117000000	1653048917000000	1716120917000000	1810728917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
231	\\x171617f9a37af2f3a3e88c7f87424f22947ca5aa355c4dac8af37d712cf0d5564bd00a1fc811f0e0bfc361b2961ac48657eb920cc46c7795c75543e6bd867838	1	0	\\x000000010000000000800003ca0a69b07491e1824c9fd1b43ddc94db7f6bdf9c952144f67d36192338c1695f895906a639235e53ab62d74283922215d400239a250b2f760a2f80b6bf302ff101b3aaae3d2bdabe9e9704492c5dba30b4e1053fde815ab86d2df15b636a88cdf67b4158cca6e6939ba22ca93866751dd1efd6f467e65ea173bc11dc1af2b391010001	\\x0cc8fd6ae3f557b3a61f510ec9da3b69feb9a44f3723ebfd42fefe486abb52607c24c3b1ef34149323c882bd71f025dd308f8fbb83ac29fd467a79e26e986c08	1657280117000000	1657884917000000	1720956917000000	1815564917000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
232	\\x1a4ec13330c453ce206e310c548cadbb7071bb6e2a468b7de65e52d6957db0bace36d382f639510a57785297ed8ea73245ad9c504e74c5115dbec2aebafde4c6	1	0	\\x000000010000000000800003d8b4df392ab9d6ea167371aa1ac610c94c561990b44409e309f11594c118fbdf0978852ec6d482d010ac9c54763b0a9d1892782c7dd34fbe4bb02dbcfd9d48f838b91b9ef6e89221abb6510a23c4ea8b683ea9bd15e97f3f89670a6c19653742efa75c8c06379cc5995edd85f6be0d6d724c22cd6a97034e355c44219152f59b010001	\\x6e4467e5091fba8ceba57d95ee4348c0c489b6402e92c05140cec67550121e091277572a541f9f4a14086f989d6a51e0269689bab8d77716eee8a8323b7f3a08	1657884617000000	1658489417000000	1721561417000000	1816169417000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
233	\\x1cea6c12ff03b9b9ebccaf47a79da1595ffb8c6e90a4485d0c1af2d253ca79ade38970b6e5ed1cfb4019e60eadcd56752ddf91f4d18cd469c4b187b3e073782a	1	0	\\x000000010000000000800003b93df316813a3950e70f5327b1571d8fba3a7349182bb4de8ce78e856dcca3ccf118d30cb77474f57657c509a283be1d6bc6dfa4024577448ee358265ef8b54706c0593e7a54adbc18ba980f0cd017f4cafc96b80b00cab1491cd91edeeb84e53741c68cf950f9183e2787725b736f0da5fa543eba21b8a704aa5bd159b32583010001	\\xfea8d6913be7e74f8966e4072494302e5226aaf3ee6b716c48a26c090e5abdae77cddb71d57d9f741cd0848a684a7e9d2d9b1d54b5aecfd302c84d2259eed00c	1658489117000000	1659093917000000	1722165917000000	1816773917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
234	\\x1ef611b2ba41c656ae48446dea8d1c78a37aa35baf131b0714281b492a56ad93ad6255637bd04b3bd33b5f167f8292b34623dbc758c2f30c52c91b1b1dcbf7d9	1	0	\\x000000010000000000800003c9f62c1f21ae8b89beaddb671f414ec2c9f8a2d5f44c900088d9d22196b0d1e28e5c28762e76e2ca23295ac398eed8daf875fb47b97204c167b0c9a6973adffda9a4076c55c7601afb47a68988d7c1a712d6b18e045ca8a772807431b20bcfcb656125b9bb7184f82791ec1fd9025d446cd1e376ce7b26ee4f4523f41938716d010001	\\x88f05b0482414b88e9f3778ecf6c2e1f64305406499e8c6826fdae3bd89512e548eeef74de30946e27536f990c0fd9a699c5d262111bb6a8858fc860a0eebe09	1663325117000000	1663929917000000	1727001917000000	1821609917000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
235	\\x216e9d176d3f9a65a5daa467d339857e224dcf075d4588d30293fd7a4a2c21f4a660d86a63cc8681a79fccfc1f8efaab9304091abf2f0fd50cbf137525329460	1	0	\\x000000010000000000800003e523ae2bc9ad570ab46e04015be317bc7c10c618139cbd1f93261fbf18ac451441442c4035eadb1a4cf8d093148b265728a247245f958a511bb8fa33682dafd5ec55f80f954240b552d8fccb391f2268fd24215059c7bb35edff5ef9d65eb8687f7fb7aa8cf7a5747e158d005200e85d384f33067095f3084ec3a2f4cc30d505010001	\\xdf748e9a4b6a1c82602dab3fc149f267837f1a47cd8ebb6892e673052867d6c6fa62894496b61411ece51006a3ef7b12951f5f25c9be6f11d6782f1b2715ae0b	1671788117000000	1672392917000000	1735464917000000	1830072917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
236	\\x23de53d777a8b613dd975a86e00993af286160ffcb594bf181ef9bad344d13e2a2880f354d9ff5b16aae2ab4da6e4c2414d4f7d9cc3f09bae0de66064535089b	1	0	\\x000000010000000000800003bd6fe7e9957ad9b6b768e22d5f331399d98657967b549043d4a4f11634c4b195438434fb130227f7068d4d8e492496bb63de5ecd5ce772ff4416cfc4a452e2a756cc49b586f87b0206b28180803523787690ebc61a4da7703fbe447513f0453841645f3e5cc6cf1acaae65cd66d316cf4fd5d988c8b7ec2dc553526985d98bbd010001	\\xc66b5204002d4312c3d4058c0bf0878125cfbbee14ded7de10c2648e9610dac7ef8468719d92e454424815d4a8afc82946db6b20f144351e4b046dac52ac6202	1664534117000000	1665138917000000	1728210917000000	1822818917000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
237	\\x243ad0e067ee4066fa49fffe6e63d1e9e68b41132a5ff4d8116b31562733086e7483cdf7d3484b1f67185c6e0f73f5d849f5410b587bd46bf9d296f5c407e7eb	1	0	\\x000000010000000000800003fbf85381a3ed5b244a76c76821849a1db1edcf8bc750c4fffcb14ba505a796640363dc7d2fc93bb62024fcc7e3f842688fb4c81a1963a7eb4e55385a1cc3fb3ffbc212b3f058eb6e9a0e9d167f462f9324e1a78b7b23660afcbed6be12b4a5f86ae88e7466ff55b80efb1e679ace16f6ab89c19bed0482c218efece48a073e65010001	\\x2e8e62e52645f370093d3e48a0502f39b0372845361866591162c68e36153445438ff1b1e64e0aa611751f210328d35eadd12fb83b6e2fa022d3c6e37963cc07	1651235117000000	1651839917000000	1714911917000000	1809519917000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
238	\\x259e5c2d0a707fa8adbe9a4af52cd5b5742f88e680bf68872c84d7b80a0c312ec276666e1e32a3bb1012f9a62a8d9afc29265f5a1f96bcfbccc6033ea1037226	1	0	\\x000000010000000000800003c689bcc0d812bce8f5527d9e8355400b737896e360ac7029b20e7d38177d5591f496958fc50374d19f41640b4e2a8608ad74cdad97e69514259524e0cf9c1613adb3676f0373c3e83983634b32094ded470596f9e72cde4bffedb800baf41a69efeea4c0ea9e71a24ffab442ce6c916befef43c410fc7fa530740b042731dcfb010001	\\x70b10bcee27972a321d2ceefebe3b7fafacce27ec09f112167ef0bf5cd0f165e68d161cd024d0fd1924d75e63030b05298a0692e9c8a8c7294960df426700507	1665743117000000	1666347917000000	1729419917000000	1824027917000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
239	\\x2a6e88bcf1abfbe9cdce57913d63036381411a038e7ceebc9604269e20b7b70ed86a665d215c7b50d8f364e54828253a0cb2a1e5f9b0977a237693951cb65fc6	1	0	\\x000000010000000000800003d1f164aae51b5279d08ce89c209a0b24418770b397b0b4239ced16daf48e4a7bf2bea0f88decb20c103240bf60b6ca88a5fd71cdfeb1ddfb5a5e45b60426e529b490d8bf1e227aa22e48a3c065885f5d4ca822fd2e841195a17c9aca0d2c67fdcbd23f64f2e67ab84e3ea10cbb078e17268d7968094804e46490f9dba8c95d8f010001	\\xa8b650ec4030008eacf82cc2c6a939fac4d4d8d4f413a0eb6351848c8c4b57c840b0bf99cfe032844a961192f24c59b6ae2d7782c53bb05c7909cdbb99b10c0c	1669370117000000	1669974917000000	1733046917000000	1827654917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
240	\\x2a66ac4023f439956eb98691047047ccc6e1e45460cbc7e84464c68977c0700e89027f022ffb08ef4167d2089d07b0e8759bbf15c4763aaabc784986fc0b7ab5	1	0	\\x000000010000000000800003ca0f13f51c67c537911614b6accc2b79ca16c306712e9b5f2c3d83fc6f36c50f8d0503cdca988a8e67c41fc83f5d03adea4ace1a415f387da738480b967dd26008052cd83127b4a2ba1ed7ff8fd3a8373fcb814d14f305e968c12e0030b029cad371ed4aef268af44acfd2ee48dd119f9f3c9b4e97b9f868ecc982bd94295363010001	\\xa6496642a9abe5551606fb0b3de9d2209add740510780ee82557a62003b0525720577e879c8017e6286347f192e7851fe3172cf25deea63614a48c536e446a07	1675415117000000	1676019917000000	1739091917000000	1833699917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
241	\\x2abe60156566a43cd137c445446c049c1c679d2e38cbbc7c224cb9bf07f24b708e043f04512ad983b31735341b4f9f00f44232ae6ec58463b689e02d83397058	1	0	\\x000000010000000000800003bbda3a85a652387e3b97f432143a7c241dae0f70cc93398a9f03aa320bc3e27a8bb79b9885daf8c5a629b1069dc4d80aefcf2346bf746beda6a45359f71cdeb48b92bad3c93414de6bd0ffcb51a6a79c4914d977c2f17d63e8174f4acec1a5f6af56abaaf0e9b03d7092fbf19f33be995daa034ba85a155d4f273f41c297fe41010001	\\x2edc2fd1c601eea91234c46522925164e37546b8bc2167f777b90c359855829bf5a68a2f7ad7b579f784c259a6edf7db192df617bfca21f453db50fbf707b808	1657280117000000	1657884917000000	1720956917000000	1815564917000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
242	\\x2c2600045012ff4a0217f2d60870e2a6dcec97fc9b3cdf7ec1208df75973ee11ab89514aac0d730ad2836c069e7c6fd94990774c736426bd16967ec6384d8d26	1	0	\\x000000010000000000800003a11504317df9087794dd85513af9c5c21d41f2db0c619aa714cc4d9ec35140b9e82aa5393e65860eca8459a4ef1ed751f59a8926234d1a3e6432c103e3128b9ab0d407aeef59c3202f3893f1b54b62a554fb0e60451a9d20e5aafe8571babc4d6252986feff91c9b22c97562258c50b9f9200e0eae729535069ed23db03e6de1010001	\\xeb6737a0e900b597f63fe17ad18ba2d4f36f2f9bb1c01c8e2386a7b2f005b26198ed0a1b6e8e80f64dd6ecf9bb75a2c8357300fed2617392b9d41da283f2e70a	1663929617000000	1664534417000000	1727606417000000	1822214417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
243	\\x2c5e0dde7ba9f8549824a7dc8255dede98b6cc685603a52aab7a2dbb2710672cefe8cb55365816945c04a61444d1889404a04a851891c4db3bbcb81e03eea65e	1	0	\\x000000010000000000800003c0affacdaad92bd3acc06be25693e3bd8b30d862c7ccfdf7a14e5900a0fa550783cc842e8ebb4ddc178f69b36c0f1e8e19ad28713fe014d858682f88e78e63b52cf072addc4b01ba9201ef5d89d1a47ab00739ead2eb792bfe547d5d5303dc1ead6270f8b658d5d8254df7a9a70db1eb4c3af3d6b71cc71dfd53b30da6b199e3010001	\\x993969d1ac490728c97aa053db420b4bd92d39a3c4738dbc1be94d9cb22b88cdd26ab2cb8fc3aa1bcf4170d6ba37e6a7fb3fdc33863295ff9c3b12cfcdf6e90d	1654862117000000	1655466917000000	1718538917000000	1813146917000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
244	\\x2e520bc046a0152bd2dad7385e68619b63716e6ca6e2163a494ff20ea9c0c128acef40dd0e0d043390fd61a0924cd8097e2ae48727edc0d2db67a4fc7e0c3706	1	0	\\x000000010000000000800003d61257fc77327a14360783f41ee02f5473604148770a2533a8ad9d03d053bc86a4c5fa752ff6faf1a3c9c4ab4c9497bcdcdde1f7b60f540731eef5b2a4f05e0ad416d9a880763aad403a72fbf8e022f07b042f3a1e26a6745bcbc069cbeccd03b2a0ce8cf344b92b2a588e91bc53e18dede473156118d42addda47e07962c589010001	\\x96fcfd23f03b6181afe62c1e0adbccce15e0dbe1c815fb8363d9d6ad863f830a4cf5705009ff945727fd9e5777117c92243fb405a8589f2a9eecd5270b1cbe06	1676624117000000	1677228917000000	1740300917000000	1834908917000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
245	\\x31b604a89c4bc3ada5e4e9ae548d42a0d4eb3bfd4fdc49d67a9162e841eb173ebb7c78f09b2edeefb2a4b859ad39fe0cac9a2a07c8f61eb6cd5dcedf7b89e29b	1	0	\\x000000010000000000800003ae004e6fe740ba0dc8943a91760d4ebd6ceaa6127124906a8aa51d34e28f2b57dd197ad48f97484ff62201bc1ce7561f1283252ee318793d7181dd5ec76bd48a6eb7da8784fa72af7874a52a4dab6aa05380ea90e2dc895ce538c52d3e3226f0f8811432061ff0ee97de3e30b709bd2bf7c4ea11d9d877c460547add6b566c97010001	\\x98e887103f2fb78e506c21810a72928ccbdef8f6b8ceb0ed19c322358f23aaf8b62099b18f35e3720ac94228c0bb5b89794dbdf75371a9fa7f8ac85e1980290a	1653048617000000	1653653417000000	1716725417000000	1811333417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
246	\\x32cea1bbaf57071a7164f6d71ae7a2de87c25aec8362408cd77bfdb4b678b2db89a8a9399bb8dde086fccf024744b1f9048375aa70c7568c424089f80a91867d	1	0	\\x000000010000000000800003d3a4fca1a0064e387f10a7cc9d79e7823662402613c17c7712f28075aa22b31d1f04d339e90679600b15e1ac5ba4a90a8d0b7ffb1132a4c87b9bd1f3ab0c0c845e0cd290f4411b1624319d1cf243d62ca55489f107d1f63b17ce3ca7043b3ac884df27f2c5f0ea3cfc285c2d0b8d74f4d11a437029a9fb8e5d121a4be3774c97010001	\\x4040afe0fd00af99de222b93edc3f28d34eab7e08b1f33fb5128e7e31c6f9210d4c798a946232023a7002fdab2b459b8567591c3e4d1bd14ff8a7bf93e3d880b	1675415117000000	1676019917000000	1739091917000000	1833699917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
247	\\x32babbb697c97c2f98e564f847cf181ad3fff266276fb8a6d75f6b7df984bbab9d7c3e48efd7df1c315903603143512278c78c2fa09021976d7a169fbaedacbd	1	0	\\x000000010000000000800003a2583f8f0c5c4bded5bab22888c0eda8c7a7d217060bd5196c750aa19cfe52712996916808377445631b1a655353bd41ebda4bcca16323801ffe4ba6b4059ebf5b3dfc823c3bdaf3c71472421c74960d2ab6758962d6a95b5872c321059875a7dbe4d8643f4b9aa3242952f80a475c3ad0528c2d2738507795a49ac4ea2abb7b010001	\\x11bbdbe25b7668092eeae8f4a407b61578266c712b29eec051dcd2c027c3406cf658cf11c695a6c8a2a707b684eb30964c92eebf2ace602760c7e1732bee1f04	1663325117000000	1663929917000000	1727001917000000	1821609917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
248	\\x35823d324f27fa3e2f62a0a4530d3a59b187bc22781126ed5dde5d782b69d51bdd5f377cfa78d522259c614dcbb2293065156b904b1dece964c427024c1927c4	1	0	\\x000000010000000000800003c96993250888a00d1fcfa58901bb60e7cdbb20cb3fa40ee07c331b22bf2efe0dcc56bd8555a186d7dc2a876883ff5261f866a031a6a352c4b60910e3e8227b5340d6d56f6ff2fa867204546720dda72fa5f659e57e476bd8a874b7bae40cc2b73815ec2644720b2bbda52454f4a175f0114ac4ee33841f6f50570ad1dbc76301010001	\\x53286f1a6e58297afd9cf37646f941b396e4ba62614ded17bd9138ebb190ffffbbb9c491bc605caa9e570dda84b5e4c165b7c7542d0b8fc1b0ad446f10eaa10a	1666347617000000	1666952417000000	1730024417000000	1824632417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
249	\\x39ceb04cbbe2b3e3adb99d8d0ee4013b075a1c3d41e7cacf693125b545c5c51e5a15354bb4e32de12090a1dcfd34c3192a1b5d89b9ff7b5c2c9a6db39cae1d70	1	0	\\x000000010000000000800003fc06efec31db1a8ad76a8d7f3806d0894ee801b22e6b1f18880a86dca6d92a08d90f5498371d39f3a8c9f38fa30b4e68179bd248d7558a72d321bd041abf78e0eb9390b351060c39ca620ce7b77919ea4c0d6220b9a48bd23d165c64626b82f3f2e6d2ebefac15e186a9f2bcbaf8afc60ceea234780e479e5b6237734c6d84dd010001	\\x1d1fe7bbb6864a344ef3367e246685d1fb0ed800c51fc23308e3c4cdc3c362f9ca82642036abc1b4750736033ffc42be67290da4d7c092db8d822aeac5d58604	1667556617000000	1668161417000000	1731233417000000	1825841417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
250	\\x39269f27a06482a29d5c91299aa767cc7380da477809971d83cfd457898608eaa160d258a535fb4013dff2e8aee1071746bda47789b3538f155cd47b32c18c5c	1	0	\\x000000010000000000800003d75fdbfe36b283fe153dd7584b494fc46e306d67ec48c4a6ae86c38051ef275d3cce658b68d25fcff1deed713ed51aa031c9c68eb5c1adfa627deadddf8ea8f02f65d29508bfe4a8a4ddba30b77a8ffe469fe54a7d4fbc3a638cca25e8a2d615485268e6f80e30767d3522b983d471670c2cb5f1c97ccd1a343eb8b8fcfc2c1f010001	\\x08e458b0cf444438a0bd64bfebbd518f5f414c6af6bd3a6b1bfd144f75138fc661871b3b0c451ae5348f1c9200a9b226495bf2c3774056c76a263f9543af6701	1662116117000000	1662720917000000	1725792917000000	1820400917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
251	\\x3a26bf33c6bb07afe54c35ccd571426cb1773bf71b80eeff4ee14496a114ba834e3991d9314eb7bceb1d7a3fa162bd47e244648c7f3f781932752cc3bc67b2fd	1	0	\\x000000010000000000800003bc4f12bd9252b021a4d9e7b0b11aa41c54840cb20ad1ac3ebcd93fa1489c10c858bbdafc03b81667c3636bb44be9bb4e2ad1435e812dc67fc90c2d91905f77dc35ecb34470e51676154915fd38ab84a538571d3e981cdc9d5ec90d6ffde4cd45d915b05aa4891ead696c5ff8621871f1d8e5973063f37cd73a603de006e1ed1f010001	\\x9e7774bf6318f943b70055725e04626c59b10b0929cb87fe7e1e2c8d991b2dc15745350914363742a738210ea5960cbba02ad339b6dd74f9ce361b608464b708	1660302617000000	1660907417000000	1723979417000000	1818587417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
252	\\x3a6e7e707bee49faef6ebcda22d2a53584896e2d972837f1f07c960cb0b163c5ac2599f226ad59ee7872f02d45b128203a08da62e47fbfad41077d7b31d8e442	1	0	\\x000000010000000000800003ed12ed15279a59266583623659decd085546601025736668519808fb88fd450ecb9eddfc75599115f6b6c21972e4abadfc65e287170beb985e6d789e0dca0fe6544c21146c5c42dc1192e4370cad1df434e03a52d456e831ef85b23add481092ab2571da7310f50d92e22da780c198e55b965e04c5449c22ab8c94d5cbf2c3c5010001	\\xb720f63ed5da0a4a1bda7c2a3bbf0f5d9f8eddcffdf20c6091c5b10c30c9a1e2c8eb30be462317f0bcad26202a12e53006623cdcb91a4e42d3b08c7649491308	1663325117000000	1663929917000000	1727001917000000	1821609917000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
253	\\x3e3ee7bbf39af5e98ed9c767a60232a7e990c930d778eb381d5ea931f3b71a4a5bcc7495f67d0c2d74b75d8cc8574061b031ad2d9b3015675d75709b32554e18	1	0	\\x000000010000000000800003c1bb2f148fe95209382fd676d685e52b63abf193410a14795153953dc2d28e9e6ca8ccb928715a752fed2adf944a9bf937a2090ea022278cdade24c40702eb13e7092ca55d7e085891eabe610016d505ee38868b4274c9f5cfabbe10afa5d830bff29fb9a3cb7e0b4204af66508ed70e5bec44403d58804e928bc03ea1152dc3010001	\\x7490805f38a6dc8d237202e8a1e902582ba030b11af5fde3861e6b003d3b0da412ed1ea37b57f4727d0544849a0829e7fc4ce17dbe15e9c7f3c077aa2894d202	1665138617000000	1665743417000000	1728815417000000	1823423417000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
254	\\x43968bfad56aa12bfffe5a6548d81900d558f70706ab000bec0626ae22e5d8d1953c659b0ef0153fd163be234179efe6e6bf1c7ca178ef7148d1d5f7be4fa654	1	0	\\x0000000100000000008000039f786efb4be3dcd9a458ad9758d301950c2d21fa2940fae0c991a253698488816711c8bbf420f0651558c21e819fd240f47d8f6cd456160e906fe27e578ca87267547ad8157f8c2e1a97d12ef98a4498f6f516c6dd411d37e722927f3e10ded302395cef1c95f3d705b9f797867f76ff96840b182255cd73c6e92c96b30660dd010001	\\x9f8289a973a47e00b5bb0599faa883f011e638e0b5e79804548533e40e95c99dc387200018dcd861ea4055d3d90dd4babf3a562f07b3a9a7e0a57ecef9964a01	1649421617000000	1650026417000000	1713098417000000	1807706417000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
255	\\x447622dcdd6b6c9d668e9bdd7a1c70dade983c3ba6d243cd6706d34d91f052673505674743aa6067da3766c1ddaa01ffae067fd92dbd74204dca52defa9fe628	1	0	\\x000000010000000000800003d998638b8f3d0da6947727abaee1cb832216b5d8cb60b364c3601c7ff00cb63a5dcd912f0aa09ee75aa5bba478c9dce9412b0c7dc4a7152dd2b75ad02c4f5bfadf81f597e413a8518e6ef4e51944797597cc5d581dc313ae60940466bac5fa4f621051c2b1c93a9b7ddb9b986d19779a8369608455ba88f1801cbbf405d9f59b010001	\\x45b9981504c035d6deafe5635fc720b77fa63b2af81104b0dd4c1d0c67d0127f372e05ab9a41449e78cf7cd0af8884a3ee1cdeeab423891953a56972d9970903	1670579117000000	1671183917000000	1734255917000000	1828863917000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
256	\\x44468489ffaa723485919274182c27bc0a1a072d12d602eefd930663c5377e527b35cea7cb96f7fadbff2c5e4dd46968ccd0b05e4342f7e3c23f2c6746f2e0c2	1	0	\\x000000010000000000800003c4071c7d37de8ce2485a1dda29f234a94913c07a313c52131a4ddc561f7873841c34c3eddc03472405a8d3c2c3a39c830220762cd91c924bc9aed379959a73d21419da675aca7f1605586d2f0f22993f4edfa114460f937db7fcf558f5fcfe77485ecc8ea51779c3bdbfc4e505aed77b4e882099048e35b2982eb3aec8e6bf25010001	\\x1adf6830c27ce04b918ed9ee7dd05acb1316aea512fab1f61cf85171c98d1b9ab65840c069b06fa4213d9222a9084bd16aa90b697c14032a0a92a5f4ce7cc50f	1670579117000000	1671183917000000	1734255917000000	1828863917000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
257	\\x44bef13eb5c9e4bc2037ae87c2df4ad691310b8521a51b055f60d4f79065c9a02a9424e7a0c310ce9e5429ed08d171255aaf8c3738ff894fdfa599cac414bd80	1	0	\\x000000010000000000800003a7a4de0e4e2f37c6e3849b626e1019ce16721e1d1f02a29f5ba8b0dd3fcee74caf42a4efc5269cbfd236e1272ef454bfcaf04ed1941c236fac2b6569756eaf71260d3f0f919edbd191d766afced815f9f540cbfbf1c7997cd8fbfa91821866e75e9144936dc679687b504af6dc27a70b89b74f7d19c92f000df7eff2b7b04ecf010001	\\x07ca8a780a4d2f36d506823556b9182d4577f86b6ed1c9c009151d52f417e0eafacfd978614718f3b9db328b608ba1a6a9d3bfaf70efc078621742282018fc0f	1651839617000000	1652444417000000	1715516417000000	1810124417000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
258	\\x464a6dae1a620b92094ea4abf471a8314cf57bca7d0bc1483f94235fe63347752edb15984f61d1d40a3763686a36c45fc2593d9bcd20eba22267c93237f2fd3a	1	0	\\x000000010000000000800003c36cf2905a2c6644053bd932ad390ab690b1ccc113a605e9d3556e522e5e77a83bf707cf30fe0ffd0de6a7293dd3d9a20b02ede60813f4864a6bda18493d73803da5f0718f4d4291d0762b8cd905feb5d0abc18a9f3c1539c67b2718a899ab09237b18e6b342fa62c2b338f9f411f4ba7a8ddac2a7448a315b98e116fef45c41010001	\\x4ce9d4c8f6b42b7214a1a8e851d0a8bb2ab66c1b21179bb55cd8e62c9b247a4de718ef4fb2e7b123fbd6f8cb6be9d60a367887694275833410b3467d4996d600	1664534117000000	1665138917000000	1728210917000000	1822818917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
259	\\x47120a6212f1cce90409e51fafc81358acb1480bc99cb24b1910d8df258d111e6962d08b6c32c28941bbc4df13efe16381886e9b662f8b16d46921465bd889c1	1	0	\\x000000010000000000800003b620a5bf0d0df65c93ce45b144aec238c8cafebfd5aae1034e0b31dbc2dcc7abf766bda3383db1edca8bd8588b627c2e9aa19d757e2529f6eea52758bdd405f4703e3672958d32b6f351bb4e0396fe975f19151ba3f9b3c49783202f4a4d219985caa19cf3c9f8d0c61aee94414e989eee458840a6eb84e1c1090d705aefa919010001	\\xe44a98bd900fc0d4e3e4e165c5385c2234989ebbce6b6d3ecc18adfb845f3bc96bb0ef2c03ee9354f09650627e3922d89bd64ad2a21c0fd954d270fe58dd560c	1660302617000000	1660907417000000	1723979417000000	1818587417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
260	\\x48b67e0a43323b0d93ef5b6fafbe0bf184554537eba47b6183912dd1fbfcaff6cb270f112d385986768eaf4998999147bdaf6f1d2ff00a5ae8828a95625d376d	1	0	\\x000000010000000000800003a8d026344cfe4af10bace189c7f3ee7a032645004f766873289610f3a6aba8a4af8837011c0001b59f83a7cea349931170896fceec07c9c693ccaed0a2c3ef67ba9e410eda5c4fb94f1693131e79c78e08712a759a9ae76d55b18cbcf42f67aab0976a487ebf29db675b2a387ba3076097ac21f1ad1a78ee5ad14a6693a8b76d010001	\\xee0c8eac56ca1991698a9447338ec12834242b41422e0f137c6264942bd5c224fc053407de13cefdf9ca31f4c8415938b616a8e8df0040f6df0ded6c19cb7b02	1663929617000000	1664534417000000	1727606417000000	1822214417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
261	\\x4816bdebe8dd1d3cf8cd8533c933db37d5b53acb2d1ef48b2f883932060face97344b020266be49fd7a9ce9e9e2d76bb08d37642f44f1d17f9fc560d628bf848	1	0	\\x000000010000000000800003e2b8a5a7d9906a52d2e4dfea2d7a1e89aa63d5c6fffe9a0e87d5e903d6ba2b73969ff87266c96cee1e22499cb8d8fefcd47e6365163ed3250722b78978fbba4af05a1a1a745ad105e98959a4f8361a5b9441712f5edbedb210c59defe8a619f1235a6fe8d6febf6f94d0521340c2910310c6182db7700e27fcc8c45e5b0513cf010001	\\xd4283e3d4916089aa96b6e72bf45e88e9a64277d02b79cc6d91c59ec8f9cc545cb0f5ee84b078062c5caf936bf788da5dff996df1d10bf07376c2ed9e25fc00d	1651839617000000	1652444417000000	1715516417000000	1810124417000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
262	\\x4a4a855eef0ca1045775424e92a598fa7c5417e67841d1ead2a5fee4a5b06bdda8c95bb92287b52bbf5edecc921394de7ee76c9793065b845a7947bd59b90aab	1	0	\\x000000010000000000800003b1b17af51abe98af68222649a93f906ec6dd3bc469a3bba4082d0d51ef01d87d992297170cc07042cafa44ab74061fa9ea4d863e7e1f63d4c6a7c0f9534f7f40eb87df9fecac418882d8c1c30ecec9514d3b356db258e2089e50f24774966b34a71cd089d45255cbad0bf31cddd218ac521661df2d1929c8f4d79acad2067759010001	\\x761432c4ea89c4a512fe045334bd310d74dcf425d74f3e68c5dc8a9dd7b3f52e2caa7630ee682d0ac20d967d5bc096341b8595a8d51de085cddfae2bc2ab3608	1657280117000000	1657884917000000	1720956917000000	1815564917000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
263	\\x4b2279668225bda3f9973cc9a33228d15789bef68bf503a208db345890744b4751d531d59bdf88841bef1ff2e8f8ae93fea6e3c4dbbe6334fc77f12f0c9f5b80	1	0	\\x000000010000000000800003b975a9fd6dbc02b2b14fd0cdc856bf7cea47fbaad91894f55cdf6cff4d14b0b206d47265f72e68da5d84910cb86cce7bdd223d9b74f9d3253bb591938b5d422d783e3be9b3b4c0517ae1c84c3331cb77ef9cb6541632e1fb23a33a8f437898c4c70da6aec1c1479435b071cd1b21cd437c1bf958720e4dbfb8b4b5ad4e92eed7010001	\\x2a85d042fd7eb615ba6e0f45c5a91f0eafcfd3d12ccc7af5059ad860f8cd81d8873572e9186443e8a42198dddd78386d22170dbb4e80f8190d13a9fd0be1db01	1654257617000000	1654862417000000	1717934417000000	1812542417000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
264	\\x52ea3a1b26f1de3c5f2032d6ca4485390920df7225659541243357fcb509ce78b22c675172909b0bee6616436b46f16ac0a1acfa899e0ad7d9b8dc656831f318	1	0	\\x000000010000000000800003c3bb1b1ac9b0175ccfef80e8eca3a741e99b9210cf00da08b3eb52a646232a209deb3db5ba766afe13982415901ffb4d1fd53bbd77715a4adcd7020b36fae00f85a53260c7da67effdab4c60e628edb5bf427aa67290d93d191e88cfdc01b4da9c4911376c89c77f48ce3b42195e4cf4b00fae1d3a8c6ff510403388acf3f3ad010001	\\xc9697288192590eba25d98f74469e28c0369e5e76171365439d00c4ac8847babc850465d7fb6395998ad6ee93853f2ed5e0e258d160bcf50c61f9e635edef90a	1650026117000000	1650630917000000	1713702917000000	1808310917000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
265	\\x544a57bd451a3a7a9eb1c2016ff9d40e47cd72e68241bba8ee2785116405afcbdb1c10a44f63130e3ed3824ebca082403d0e1c9e422b6fde99eb59c0c42ecc3b	1	0	\\x000000010000000000800003d0de4e744739bef3e60d87db59424a7d7398327f9744afe64ef72189044743c03a5212bc818303daeaabaae2378094815ae5987c02f9312205194c3a4f9d68bb94957fabeb20df58bfb6af7d4f73527b9caa951f71945daaf66d9323a987361e893f035c38703ee8a4ee717c356114c94c889c2b034c30478a08736a2cd5ae6f010001	\\xd5d5eea1d6ac4ac00256311308a0fe1773daa61742d785764d948beef3328341738233d69736bd58d0a53dd5bc3cdefcb1880cf38b3f8996e7c5bea52052e90a	1664534117000000	1665138917000000	1728210917000000	1822818917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
266	\\x58a2827918545ee0e12f2ab03856c7921decbd1d1d944713164d706af84aac11a5a8a9255c3d83a9b5ce1a0e5b6726d586f5b6603e1fc4cc26a93e31c2f943bb	1	0	\\x000000010000000000800003e45fd312e1bc4bf22710e96e0a515f00d14d36c5069898d4e0194d22380de1347e4952286d726b528c2b9a86f9442bb90ed1965872155fb62ccc23ac739cd2e7de74c381dae3f53e933ff7d9b697705139989d5cce4e6b3c3f51f46740dbc56237b2afd028ceeb11aea5da6f7b2ab34e503e604f873c8c4f121485c1015eacc9010001	\\x06f96721c1f18a751188d307205e8894e006604df2998501ff13eb4eee877b2baaa3afef6ddafc4380b55d995e8c516c4c10eafea145c7135e82605805052d0f	1652444117000000	1653048917000000	1716120917000000	1810728917000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
267	\\x59b275616cc969341da2b59e5d40935b2ae4570dbc9be8a0dcce85a3a613147d303e5cdf0c37046105088a56dc2f33d81487f8f6bc62501c67043aa044045505	1	0	\\x000000010000000000800003dbc2c87d892821f1459580cb4bcdca80668e0845a47b49bbb0b0ccc1d75772ab81ae5abfb4734feded40302fdd9be6dfb22237606d99092b378ea7e4c5c5ebc19b2788ca7e7a355ead9b47ddbd4cc89dbc44bbc41caf4df6d4ac059c88bb58d8621afcbb3e3088511da5c80dc16062347a0071eda43738a1e44b29f7c2659459010001	\\xe1f22bea9e8cde34be47032209e56b0da10767080f18668422441e9ca7b929a9493bd9a40262f2bc0a97a9baf51e99bee41c221603128734ead95d7d35f9ab04	1673601617000000	1674206417000000	1737278417000000	1831886417000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
268	\\x5ae2f269982457a35c73df072456f848b851cd74f711eaace78490f8194dec06992a19a3696a303253dd47f7666adbdaf9bfa234244a1ba1f961139c91aaf95a	1	0	\\x000000010000000000800003bccd43476f12395acf8aff31a173788f51d80e0b8b5d420549f832f195c1ff8c0083ed786e118c4afb67a42cf3b80602592c97ce9db80e6b2fba822e29b18e4fca6ec1c9360333f8c9232432b7385dbaeb97a47bd620b4731a9b011cc3db00c12f436c57aaa8dffd730b03a18128380781ed50f373ba26e800b6e558fbee4275010001	\\x1b67cb44c71a501129583f7535a5ba8191104f9f50822e7cd832d2f9f12c189bd132aa7884b1e2dca1468fc219b8f354b5d562099cb8ee8f587c37550704270d	1676019617000000	1676624417000000	1739696417000000	1834304417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
269	\\x5f2aa860dc0732964eb8b1ff908fba8aa9b942c7af6ebfec4836316668020abac886494ed4b3809d89c2ef36618d37d23b43bc4b24a446545f6f8076821b0cdd	1	0	\\x000000010000000000800003ac9cd289125771ccc73e02f667baa221133a09774d3ad7ade334d526da8064c0e145f9fe0c7d37a5cb1c359beaa33bbbe67b00a71eb3ea0d55e9f5926cbccf6c075215bb34ddebf9e7a835142d8f31ffaa8042c784dac1b37b0aa146ccd268a07a8588fa9df5290ebb16c09a3907dbdc46299b0c9b5914dadca68650d81c2fc5010001	\\x4c33f53ba41f965fa868395fcc96d25f65ecf0d695b9e3285b39fdbf595bb140b561942b2b0feb6b10097b634259e129c81707a02276671d9b73c44dd3075c03	1661511617000000	1662116417000000	1725188417000000	1819796417000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
270	\\x5fe25b63d435b3b2ce5abcb2d5e8c92c96530486088454d410ba8e074bcf412189cc0e254ec0ed8c4f57261f7274d6e156815f64200f035e7e91e12e6a4ca894	1	0	\\x000000010000000000800003b6673f1c1b5f92da5db8bdba854e1165abc53b44d336a57055d7bc0170e72d9485cff55c9a46acaadcb391b54ac20bb52a32b0a2760ffc956d0f7e85704d9bd04ba81316fa9622a39334b6b0504697664c836f30741835b547f1d367b33f0b46fba9440954bbd239881a0dee5a7382590ae2efd1e794ed5ce74377abd7c139e9010001	\\x9d5bceecf8af2a6e1eed94372b43e1ba996cb1217eaece4c3f2f057053bb51466ba36f62b72cc694046d6a8f52c9f8cdebea094d70f9a18a3158900c3779dd06	1662116117000000	1662720917000000	1725792917000000	1820400917000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
271	\\x5f52845fc1c0e215dfa17cf5ec7acb71002143293b492cfff21cd338e2e82851ce75b16cee00cd2f6a89ceaf4e0fb59c5423e8cd47e8e24ae9786ee84da9eddb	1	0	\\x000000010000000000800003b7c3cf8d85a67f91b7f9378425affd5121785d390816236745c7667c9f9b9480cbb727335a61aebb873bb613e95286be491698c7a4ba18b7989ffc08b81adf367072bb497464fcf042608defcd735c109949fe3c4e45cde153509acf18dfd28e2009822ecc5a1d2b4672ff4e1cc45f1f13a784349e5b8af23567424dee85c183010001	\\xfec4af41bf539a273821aa517fe7cab7b68a30dfd6d9c04574b389ff116da7b7fc7fb0831151323aeab2225a7510044115b1bbf46937d7abed2124d8fb1b9a01	1648212617000000	1648817417000000	1711889417000000	1806497417000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
272	\\x616297baa9c6801bbabf0e199ea1d15b501008ecb18e56457a1d6925411aa196ddb81d169a750cec7c304b4b724bbbc693a0595880e47e34786ad1ce7aa9e0cb	1	0	\\x000000010000000000800003c3f62346c27ec123eeb04eecb06039d376cfd66d27e66e6b0c42e54466f2a586c2104b9134748380322db7d456007266abd43d364709d5e3db3f35293ad8d72515f9f768f9cbf58f1a739af2865355ca72b0cc7a172a0c9c8192692ed56eb38b419a7d7df6b440517c421482c9babb4054d804c4146e08984c4e16253b1fa205010001	\\xf8c9ae26487224fdf92ef53e6f3a676eb8a59eeb04175a1e4552a4dba901f3a01e9c7256abfce9bcd6823703f05a00312dd5980a3dc55371114a536ea6e4cd0c	1658489117000000	1659093917000000	1722165917000000	1816773917000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
273	\\x6126fa8286a3e90ce237d72429a91aa17458a247d3a43161887878f82acb1cb6196de6619088c57ee120c28d16ed50e83b03d1683d1e25839bf4c983bfc1f533	1	0	\\x0000000100000000008000039983c8a80a4219414cf1cd13e1d7588150c1a1da9e1a710ee1c160ad6e5b41c02fc561229afc9c01e0238394d5ebe91cee325f963edbba0ee41717b6aaef3a4bef8a7b673b5e772cb43622b6e2dfa804bb3b5c417745a57628da2783cc789fdd60b5e40d791056e75d7ba9cc9cde656aeb80cfb266a0d1880d99eb1468d48473010001	\\x0f35551dc98421b8ff2e170ea8456dca44ab906481146591f487e174e1d58aa4396b5d2c83ada71713a0e72cde276156bb548aee10404a05cca18a33ac9ae602	1660907117000000	1661511917000000	1724583917000000	1819191917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
274	\\x6472e7e8455c5d8938ba327a20b3fc53a6036045877a7b16ab6292dec395695808e63d7bcd4683e5f273ed4a4a4b279aa0b203ff806d513342963adef3eda716	1	0	\\x000000010000000000800003b1c89f415de303d8251bc6716841e8bab908adf007e0916e968db5c94f2fce8361c1a32b1d7332c715b38a2fa16e083c3165ba658642d6e0dfdaf33dffa287f056766995f0b7d3ba5afc1d8621e4bcf7d08cc9297c86238e570197ca8b8af24d22a63983023f80d627153fd6eec4a72eac94955d68c61627747e9b5b41cbf579010001	\\x8157d19652c2fd7bc466003e339c8ce3919d454cdc2d593ca1689a522ec8d3432165cd3053e9038b430106f302b7b87cfe760433e3ef42d8c6bcc5366678540f	1651235117000000	1651839917000000	1714911917000000	1809519917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
275	\\x6b0afff6e3054fe5824d9711c6540ee7f4bda726c817f4c0a3fad73c4e250888ebad7041ca808520782127258911857b8835d28063570f31acf834ce6a9425af	1	0	\\x000000010000000000800003e070a538218c1f2971327f30439921fe3eceb1a0bd29e25f8310f4170e94e0bd9785956b56e3c6b591174e3770afed4a9e918d87cd16d48755bfda6c5bdc21c0c3825779220bd4d4e289a6c53a97939992e1c6a94e8e164f1149c969d4cc4a08eb8316e5e540f5896eca7975637ce0b5fe80ce29050a34b6bac557d87f0b5769010001	\\x2d2898ec93a4ce0aca3337055e5ad6a60b542961befb81e78676ce024da3eba1ed6d57fa46e88a6ef35ffbce43d1d1963e7d1c72656da5e8a9d983b4c070240b	1648817117000000	1649421917000000	1712493917000000	1807101917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
276	\\x6b4edd77e1c6dd524c075332f9d8d9aa2dc4e095e61fa2c17c7259ee022a38e1e0c6c1a3f5e4f9e8b7eff202993cd9d59fc0854cb8c901565d127c83f7dc7961	1	0	\\x00000001000000000080000391903bd9d33f24c82a06fd11b9a646d2efb2ed7ea7315a6a4e6f8bbc1d6ee919d0cee0b161f3abe9d101b1e14bad2ad29ab851051ec0432ed1e28d1151feaf2a79ef20168b6919ae61a2e03753f9976476aeb7bb8d5c1c369431063b5a9df6fcd2bd84d67a625a95eea3935a207e59dfe9f3d41ba373567bb7cce033687843ef010001	\\x65fdb6d06a1c1368dda6c97623eab9512275b5bf295642c245c5b17bbd9f83133692b937a4484b84ce608893e73a403335d3224b6c335f816bb58df7ee322006	1659093617000000	1659698417000000	1722770417000000	1817378417000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
277	\\x6d26e660c16c58428ffc5442f9b3025d3844b5140d36c2de4a5a481aef51407ce8757441be3aabaf816d79b439fc7c9341c817fe3e07ac4b3efd2ac308276a58	1	0	\\x000000010000000000800003bc6b9c0606b823ecbf4a039611089b11c66b07ed65e2fe0c17d4d060fc7cc12acc2cb913fe72ad5e1912a33c01ef7c65ef8eacb88b904fc0861a61789d5abb9df9ded56a3a1a33a9c397b7df4d764377e9bdea2cf01662d180b9e66b68bf62d702fb8fc1f6af4dfa11ad46d93d1d88691080ae9bbb06c081d5b7350ea539c2ff010001	\\x3db78f9f4a4a4658acb21a0bdaf008db7974c9df87ef61247ffd89daadd02a7b37ee287ae4500a7d423c5d66e9da6ef58683e228094578d723fdae08f3e2df0e	1679646617000000	1680251417000000	1743323417000000	1837931417000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
278	\\x6f5a29ab8d813ba0edbf2c1cdee012865ff9b85f1816643fd7f688dc0c3788df8708d97bb90433cbbe9b4ef8f6ff90feb695135a469615e04dd818905e456638	1	0	\\x000000010000000000800003a6a355d8e992ea476a34e73207848ae8f455f504d4b60691e20fe42cf23c386d68ec988ce1b94689eeab513b369f7429ccfaa9c27e8deacf5bff7aff7c5c439d9dce14ebce94c328a248f52c8f19cf15c00f01f05459604d22ac73928a23318d0916ee4b0278c1d0e317b11a5444206d1ad8d541627aace69ce7409d42a35dad010001	\\x32c9ae5a7813d24fa7e8c8b03a0be82987e6a2cc76fa86e223e668112fa58b63013c5ab18c0c9084c394025949c73aa20965c5a3c2f015554378b739a3d8630e	1668765617000000	1669370417000000	1732442417000000	1827050417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
279	\\x70c6ca23cdb5dde1f822597199dc3331713cf04a76e0a8e3aabe8bc25df36d1eaf291b6f0d8fdd31e5eb9ff6f3fde41d4d28553c38083ca608765483a4fbe24b	1	0	\\x000000010000000000800003c192f797f3d2210647a83d0791c2151cacd29259bd507996855a83bf22f68338c88d6ac9cb043e3e0871ca5fc29091c2870ef244ff02cf3a38b020fce76061e0a27f0ef0b87e47b7ab65a6b81c33bcbcbe0b747196c49395d4f6addec5590a1f631afd706e3f67a917b80de1d856dbacfcef5f5a042fc6baf68ee09fab08077d010001	\\x7ad5a81cd2dcf54fa51796b833804eca5cd10e18e6ce5b9672e9bc0ad49300026285fa4b69dc139606a58887ed757ec65236881d65e4f29b225871bc64c8100a	1669370117000000	1669974917000000	1733046917000000	1827654917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
280	\\x721aea47eb06bec94011bebdf230126f641fe2ab41e02da3da9a5d8a6486eaff07f4b80f692d7c51a89b66b0fa4ca1ff4ea121f65d69dfab0019ca17bc36fb24	1	0	\\x000000010000000000800003cca91d3302c09659c23c59f6e3f099f8bac5be892ea7142df54893db486c810859b669cf2c4bec657b6cb6c80f92575337ad739f883278323b2c9d98cf71ad1037880d04f0dad8b4eca4c301f72ac300840c202b48064f4c5b78b5bae32ef125ebe9e32ee2bb370926d3fc777e065ecbcdb1eca2b4cf8bccfc0ec152156bcfe9010001	\\xb1372383b1c1bace9e305c4cbd960381f2c4a57d60d44d7588067fa2f1436026c0bb96e90032f3e6a51090bec351d0f9ed436ec1d57ab03417d76f2c86ae6006	1663325117000000	1663929917000000	1727001917000000	1821609917000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
281	\\x721650dcb9eb18dfd41c04a8298a3bab5a4f123a44c1119de2ad3e34b88832cfefd0797c45319f4bb84ce7022395a885639662efc3e07b7a1ad5ad4820f617c7	1	0	\\x000000010000000000800003c707748d8d3a7e66442331885d0ef8025d0368316ded4ca88a6ddf40fdd62f865af11b9818065d14944cc7ddc7ed8e179e3736576aa6686c4c6c2961385bc79786dc814ccc52f037873126a1c514482b70e54c91223e4ef63c81c0b84f5b0912d36c196866e9cb68ddfef1884fcbfdfc91c989b13dc4894b9e1471acf9afbc01010001	\\x9ac4b163605c6968e295ff38fb4e2f5af84cdd6b42cf76b83df2e4806577ac465ba8f47769346a7ff6a713c7355ddb356f0632c7cb6402faaa003d650bda5703	1651839617000000	1652444417000000	1715516417000000	1810124417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
282	\\x752ad6955728538d578a5660061ba6ff2983d22a89eba8937ac8f9a96990a940be23ead90a319ba698723370138ba7e579a56ad844a564bfe31bed5b232283b0	1	0	\\x000000010000000000800003bc44d5eff6e792744688a5ead38773a8cfb322b22e29e3270569587f066cf27ab75b2c18a50c1dd09b40e85ba5cfcbbecc65c4f1cd87ac43ff754d7dad3663a4fc644f71b3c49b05f747e9bec21434a67644d0e8bf714efcaa2302401f4f751fc5c0d99214b02ba505728e2281bcf7665924c24c59f9b38772c8ad0b3e9af131010001	\\x33d77ff082e66890b6dc87caf548b0a586cbff04c46bbd6a5db2813f2eb31ae2fbb70c5a2905bf5724e5a85a508449656977109e05866bfd56b65f1447e9ba0d	1659698117000000	1660302917000000	1723374917000000	1817982917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
283	\\x7ac2f015361db2356c54d26bc6d15c92f3be13d6ed7507bb94c6f400b9dfbac193963f899c61da573c14afde013ffa4abcdd4d9eda8e256ac78c958f4acae6e2	1	0	\\x000000010000000000800003b88741fa57b9907473b61be38dce4eebe3964f80cf3f6c374a58b6ee4d80a91b353b557f70d1e1df5a66d6fbe75d185880da05e02491baaebadf2d512d6176c2651c2c77e9ecab3f2ea1e73fc5a62ce905c1e18a26d4acfa1e9348c9c1b43eb936ea428589cd5f8252b03d56a293af9354b9233cba0302cfb47872b62dc39189010001	\\xd0561de815522a1f9d785664c67a2dfb9bd2503bb8098ca25f99e080524bc5bcb021c3a4e8c0ad48beb04e405f4e2c7e1236507564e099ad7c52e723a021150b	1655466617000000	1656071417000000	1719143417000000	1813751417000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
284	\\x7beefd7962699dbb892722fea42093491cb2e6fa3c6dfc25f7e7f674a6aaec98cf5eb5b4e78424ea976fcf2818ae5e11826376df00d7c9cb93bd650fe2198098	1	0	\\x000000010000000000800003dcf8a58ba2246cf675fc766db727c09b33ec0b23bcdad631389cf09baeedf6c0c2a95af932743d33a2146611a6a9c5d7fda130cdec2790697ff0f2d005e17a6e1f89a1883860f4c9b9d4b2b975396bce3d4994539a898c82c47ac54e55777cc115dd0336fb79b9cf722d8323b1b97741db485c06a03e0fe205837df73eaef2af010001	\\x27a54ce552a5760737faadf569ef87e7db94d4d5907e33925fcd904c30027c8a8915c5ab1c835edcf37a2b209be31287dca41371887b729be2e2a3727f439004	1656071117000000	1656675917000000	1719747917000000	1814355917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
285	\\x842ef03b795a4161e07b3bfb7c4922924bf27d0b51da51d575c8b2771dd04c679e7a4ff2ee9068279901b358d4bacd050b2c1eb5261831a97109d7ad916d5d5f	1	0	\\x000000010000000000800003bc7134913280ec97aa898859cd316df2d80cc8a3a3663fc481976941eec749d133dd08a836f17207a06815d920edf67ffade9222e0056c4fc724c2eebbd18725f726f1d06454059dafef17277a5db8e3d24db0e26d8b0ee554b645630965ebfc3445663004e4aa6de08ed4021f0bb4e882a6ee08ecae0b5855b9d857012266a9010001	\\xfeef0f12c4a63e87dc7d8eb4beda594c9d3190b25b136fca4cecb15fc6b4fdface9cc50e9ef32416a513380a247468b1884e37e4c62cdd60ef3a206bd0e08703	1651839617000000	1652444417000000	1715516417000000	1810124417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
286	\\x85fa54c340995129694beb83107016f96428dd486411e570d15ff879f3f03aefe9b7dc8f1a1fbd16f6b5b65aea2da9123dc4ca80f1350e93e1a5ea5045ab9d95	1	0	\\x000000010000000000800003a6c9c5175d19cd90ab6b7b0619262ffa377364ba8da5c957560520119eb2bc20838d30cc68e2693457823e16ec6ae7d8734db4cd9a2b46870fb9d6cc8e03551b41ae6994d243c0430a3427aaa5beb03fec5e5f2d5d112e705e0149d8bce7efe5ac9bc5564c79566d4113d29065e9622c7ca07c6622076d158450eaec51489e21010001	\\x5de73047a14b393958964b0d865edfe5bc59cfbc315993c12a767c9bfff9d96d24c7c4801395cfb8c301e0c101bf85c9cfb123eeb9bc66fa8f1eab8dd060d006	1679042117000000	1679646917000000	1742718917000000	1837326917000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
287	\\x85c6fb489ae7c8eea772323f1704863a14473f05b34b1d5df52dd06a64fdcd8de1ed229a5e57a7432632d8f2d8bc912653f607a98025d7b43fb83561c738d69f	1	0	\\x000000010000000000800003aa6485cbb93ee45fe341860a95cd53135db3036b555ffffc5e960192edfe5e9f207ce3652caf1ec1632d361cb79e90f73eab95a8de623782ef4dd0ed2d21c9b7e8686ce7e2e0d325f344c7ca30ec681a3c01fec69dc13572e29c0135a4ed89668a32f1f4804bdeab2edcd39874520c95c9b8f3f6caa82f94a7f0924f20dd0d87010001	\\x05e4139068e025cee4a888efe7c79933c97e495c4f0ec4a82855f6d382a04246a80d93714a0512e94dc6209124055ca6c5f59d22a369c18b0804864316cade0a	1651235117000000	1651839917000000	1714911917000000	1809519917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
288	\\x888e965bf4f97bf1dd1718cb5cecc3addf1fb609058c82861e239e49b0414c207a921c12a1ff61e212a7540323a0f703fa7e3a8c153255e0cdea74294d8eaa34	1	0	\\x000000010000000000800003d80e50e05bdae154fc9e353c4ba4a9d763ea2435172a61f73ad2e2898df66b862d96404111f3ece6564af849dbb8e2d7cbc6cad3ca6dc20f930f7da50f3f5a435c92d0c0323d59c6e60b7270c0381c895a79d212be60ecb29ef2e10e2ec425b94e6fc4952a769e33e0954967f877536bf10b88a7d4c01ad9e74720ab3b66d7af010001	\\x10f21cfc43c9dd2e92c8c2cfa613631991160d455f771011f702676c3eead893efacf8411c7205d1ff26e70ab42cd9bfb9c590204d3639a0702f03750f757804	1672392617000000	1672997417000000	1736069417000000	1830677417000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
289	\\x8d6a59cc70fca5d6197b80fdc1a2e864bcb61680b59ff5d14aacb8ca627791dccb39677968ba6721f7d5a65a28f8ddf0e9195fe0913a3d1c3bec230c321c0ccf	1	0	\\x000000010000000000800003ce7e4fc4ec4dddc6f6b87edcbfe3d3e8dff2ec59aefb77e279cf82cb76ec7954dfa3be8a69440bbf5cd30651cccd395087e6119ab4c380d9a636e6921a30c5e806817b9c41ba51ade30813f164ff2dd2422b57dc86db3d9b149dc4bdb19f0fbff5ee9ef80e2d4fd7afc6f95dbeea2f271203ba68a42e0942d5563b4ebc5196ab010001	\\x2675d400ee3a5b26c282d294b7609fe20c255860eb23c0e3b0e5b1f7586aea19b7003f2a84338051ca6b7c5e8b086c6343e600f6ca6fd4e92626389ec8777b08	1668161117000000	1668765917000000	1731837917000000	1826445917000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
290	\\x8faebd439e051d4a69f8f509466794cf77589d3a08fc9d64581101f4f44d357d2305d52ac3322671d333556f04d3a53fdde853f8949c1a96f7c34a919942c8e4	1	0	\\x000000010000000000800003fb00582c1cdcd3d6234d04698a05ea5a3a600c1b6d406113159793d5fd89a96a46e559b127f7c233facfcc23c362d43e290af15cd818648ad2bb8c3a679800679a43345038d9910092f263b8201253f08b31d33e0a05d00ec97e258710aa6298422b996077ce1d35317457982bbd9b426e621893bc72fb2496a5ed29ef947de5010001	\\x6ab7c22e0f31b9dd037cbffbb27104f233d11ddc408de95054c398593d68763654dde858f39f478ac2ec992423dbe7022284b3657c276d7a05ac44928f02940e	1648212617000000	1648817417000000	1711889417000000	1806497417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
291	\\x8f826ece13d58752380fdd41c736a81deec62e990628b815b2f9e40b9dfb1e8f1bafbf76245618c82c93f0e0f723525b4c3981d915360b3ba1d4a0578e719d95	1	0	\\x000000010000000000800003958e59ec759be4821dee51cf7be815c8db26c59b55b157e29a8be46a081c93aff0261d7afd185e53fb8dfc86f829cbe7e65afd0eda4b5b0cbedc6552bbd836ce771a06ef6310a54c691aa3a63c9eddd7bce015fad3ecc2fb025908d8ef1f24b061873048dd953f1572fb1380b19c84ac3ca5430a1b27b9a6f0bb21f99e32420b010001	\\x0c3af778586bb8d3c5786ad6493f55630b4e5148a14c25c3663ce5a55f2b8d63dfc6ab758655377f903866877534470924fce669c8378ca86d5b61c7407e6803	1662720617000000	1663325417000000	1726397417000000	1821005417000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
292	\\x90ca3aa56d2c8bfa833747e9377e9ad11f657091bc356cf5ac760a0804ba6bc83cd8ae07683dbe7371560a525e5b2aa6c34c9760693ea9884d1a56ac7b9ec378	1	0	\\x000000010000000000800003d6d1f79dd792f9923eb000bfcf4f35843af04139e3419f86251491b991f0f74d018cf770172d921d2b95fb6abc946b515e3a1d86117979b2f064f4e28a59085bde194dfe6658546c66c60b61b8a72ce0a39a0af6f0020d34ce6fb26cd3b2a6a1453f6b3acf796091ec92c06cee0744b972f95413553bb3c9c1807711f5336de5010001	\\x22a2160aba57039c287175f086509fabbca6b3f5f5c6df1393a9dd570c377f7d7699dd8e2b0fc2403128fc0fddd101edb9d70aa03cf995d78d3ea69053980006	1668161117000000	1668765917000000	1731837917000000	1826445917000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
293	\\x91c6d559a086cf20ea16eb01578dcfd4b32706ca2dfe8266387248531272fa4c3fddb7f51381e4f7ec65b7de179274ef6219aec0b45528d9a5c6b8088a25b649	1	0	\\x000000010000000000800003cbf4a6cff7ff392b76937f4044862952ececcb33b87839c3d8c0039f9743a6b8da873fdbe3a13c3a980da12f2180646e16396aeed87a5e841ae29733de23216777c63b2797c97966ed65268fdfbf9e296086f071ba85b0a025b5f80143fd5508f0fb39390818a7e1c36af8e8f626ec5bc15789e50df399da9193f8657c7cdab7010001	\\x2decf8821e7829fae1a97a4b14b4cca2ec04998b86e74ed3b719174f37d3d4fd1631a1f3063ee7a7f9629e1b4d0ba4adbaacbc062c4555d29efb1c830cc50d03	1670579117000000	1671183917000000	1734255917000000	1828863917000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
294	\\x923a81dfaba8d1da9487a353b7fb312f465ffb17c200b0f36d6b5ec3c899cfc1f80496884d82ff9a05455d734621f30beff5d911639e847c63f532335e2e3a46	1	0	\\x000000010000000000800003c81dfe7e6ad38f438e7a7907c98ac783d882e1db7a91ab2d98fd7541bf14faa6f65afd6939e46a49350f1577013db28f61b45b936a5230a31a988a9568dcf5a783c775a46bd26cb7c7fef8f72aaa1d69658e28d2d70c9f87d064c7803878538c64cfe6c33c291655c7500d57b2eae64657a4dc0a998b5e8582ba563f5b86e88d010001	\\x8b7e3ca7cefd23e08a9431ff75972d5b8af93b0947d11a52224c1b7ba5f092976f8edb89704145c984a7c5cd3faab08e0cad9b229969b865b2d7ff5fb4154306	1674810617000000	1675415417000000	1738487417000000	1833095417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
295	\\x959e23a6ecbdb2f9fca61d48cfe38f1497606b89e8dba06e60ee4daf526ac96992d09fd06c3e369c215cf0235b3f68a53926e352a907264e940ea41d566b664f	1	0	\\x000000010000000000800003beeda724b14495424bfa53786154636620edcf327a7a2fcdbddb09682d4c8744ded605328751dae72c4b009f263676b89b238de470557f76d031380e8c86ed44ee0113e67edabe2a68c304f5fb9be6400fba3c98a3b9c6824cc14bd281c70eae63babe4aea76f7511c62705fbd0ed89a77d894c40f62e20b2a336d1df1b1aa85010001	\\xfad26c9b1d75f817d8e88d40317b0c43cabd9ea5518aa0456458fd86baddbcc8d154b85fe0f2171c049212094314d36db79493e44ae4ca9ff66b600cd47ef304	1675415117000000	1676019917000000	1739091917000000	1833699917000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
296	\\x96da443c71eeb566bc1764df9bfe660d38492fcc46228c928f6fbdf2859c58ab3c6a600762e383777eee52f788de38f63dd2c6b23ff19f9fee2d1d0d5759e09e	1	0	\\x0000000100000000008000039367aa2b014e88859bf986d7edb51da640e44d845ceb7046a8e667eb1a5ec9f880eaf10cbc061f3bb5cff3557d539f0020d5653feb75ae338c50533f3c16fefac8da38a9a0647444ce5f199e201efda19edd1a1d690283431595c09b20aceb3eb088cf803a6de0b50af1629bb27975467d159a133d8c8d26a4ceec2a3b4efcdd010001	\\xdd881de02c04fe88597d03fc3db6bdbf648e5bdc4ab0328feb54038b97bda2be622e245201c0aa52ac58223ca4db04931579cefbc8fe7bec5f70f72ff943eb0e	1657280117000000	1657884917000000	1720956917000000	1815564917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
297	\\x987e51eae17b074314cc0b9d68164602d34ad205d71c980bfcd0720c1900be68b1917292a7196c9452db3f0df64c6de607fbc87704b3b00ea64cc2f19f508800	1	0	\\x000000010000000000800003c27eda94ac2dd47f12eb3760550795fbbe901041b56a2ad4e3268536d8b21dadf28d3ac1e57bc98029a17c80cbcf6b072107a06f054a8640a5a2d93e9b2cd163931d7019d1220312962da9958c88d06c0489252100b44edbf3126fd1675db5a8838519b6e4290a55fa2c2f71dc13753947e05f7c62ba16a94c3b2a375cd08295010001	\\x5ec033057d0c92c860055bedaebcdcdbedcd9c20699623aa9255ec8a9215a6809a4209dfaa9f504627b07d28d6db93d8fede7f1e26b43e99d045f8bdf7f8cf0f	1651839617000000	1652444417000000	1715516417000000	1810124417000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
298	\\x9a229958bae178172dbec5424a78eaf25b865d7b5d187595a6eb0cf2359b03726cfc7c32aa9d40172ff483a15c90663e871a01215884c46f7054a90993f0661d	1	0	\\x000000010000000000800003c52c559dcff0230e14481de0aa354dae4c530234b29906a5b95ce9a95d917923a00da45047071f84b081bf36f916ad16af9d36c497e5d5046c0ad110f585f338009343c53a3a85ee845cc1363ab7bc6da9e331e7d606a0c84b43081335fc1c5084f6c9c298ceba6b664e45e8cde2635806192271e5f96d0c0bb7a9a0cbf9112b010001	\\x02e30ffca3187ee31db96c43b6849a120249f91dcdd7498c6cf6c7d3097610278ecacf69d2b47208b26c9da7144de42f37e29060618a13568824851266928507	1677228617000000	1677833417000000	1740905417000000	1835513417000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
299	\\x9baaa72d353e1e383e28d50f54e6be28be06a4d0895fb2a40f927dd161dfda3a2b794602666c54ed73cd64f619979f99bca79cfce57a567f1b99cf5209234f8f	1	0	\\x000000010000000000800003a7cbffd989b62ff67ea3ac7fc0bfea0627443cb03dac3221390bc4217e3410b37d17d7db67ff0f21e52bd4cfde8d58b115eb9f26fddc2105da3bb45ab3666c20476242376b35e1e0256832e20d8845e84ca84bef3f5b7ff110d7d6a10c738715b9f7f1083ba1ca4437940e8a25927b1c284e38f3bf916bd14e59cfc9d7516bb7010001	\\xdc8a68fabcd4e2258fa77866752997f8cc2c474de983d3423b1e8617f025867b1188c395ed1b280081c1fd2cccd176bae51f85b7347bb14be8706e0b2b05a502	1660907117000000	1661511917000000	1724583917000000	1819191917000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
300	\\xa13212217b190d7b2046d17694686fa5bb0fe74eb50b3162776b484b8bf986814ccb08a64b3d2bb3bb9320e1848aece7c916ee626f5c7b096eb68dcd8ec684da	1	0	\\x000000010000000000800003a54bed9095f035aeb57bfeb6645a68b328d5acd169b3693bf0cdd78aaf0f4fef13bfa68f29f813ed4d3c7811b56b85f15f2b197f4bd8743128e7b303a3ac38c2074dfc909a6adae3c0571c320eb012dec2eadd1f8b1d799c7906b591650e3ed8dcaea4a8bc990f265d1fd1cf9fdfd6ca5397ad6df3b128276e6f38acb68bb537010001	\\x1780f69a587daa26b8b4bee6df2476c67b651f9a274b0a8396dd1737581cb099378d9d0b9a8d7ee6135f08008fd8447fb37efb93b95b019eff6a9c81a9c1810f	1676019617000000	1676624417000000	1739696417000000	1834304417000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
301	\\xa74e9de33ad3155b326b4062d85d78b4c1aaabaa1cf007b4138d20e6738ddfcd50fe5f32d5323d9747865123e4287848fdc3280350b761b2e20643987dc519a0	1	0	\\x000000010000000000800003d947dd810f5ae93cbea17b40bd824725c1a5dbb0757b3a50a6302ea6a68531f562f556fff978c25836d560f1250497672c2ffbe93fb2537f6642851396064d397a58d1e2401beb8ccc66f6c649c86b6dfb8d9a4af69054ecf818f77ee1dd9132ddc200f6579f1e25a3b0a976249d0ab3e20a468c4777de5f8b4faeaf0bec6e3d010001	\\xf237d95d12c14b27aa54670dfa9d6c3f3c8db3e42d3296ec1ef48cacbcd071c9abd2cdd9c58656b060cb5bf3ec974b49147b365ad45bf8df045083f62313de07	1677228617000000	1677833417000000	1740905417000000	1835513417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
302	\\xa84e6c86c73f352e090a7ba49f2295d451655f6b472310914e85523859415758cfb4780c6e754cc47cbee18374e4fdd851e53e3d83f809a5f72c098a84f83dde	1	0	\\x000000010000000000800003c45ee2b5cf7e4a3848d26f8a357f429b402f3abb9de2d60ad8752fdd1bfb70806ffc684f8ea2dd081be2392495215e1e8033f7c30525c378b1ed496488002790ca41a21b68ec0c082ffee2ec9f74e4a547f307412692bfeda969bfdbce97feb25f2ef8f799172f6cdffb5444a358ed7cf47274edde41b2da1337b455aaa5ca65010001	\\x4877091c0934092a1faa8bcb910b10369a36382c103c380f256b7076678d9211cc32083ef89eb55ed14e095a8c2a2726669d99fae4ddae61c51adea32c9b6000	1659093617000000	1659698417000000	1722770417000000	1817378417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
303	\\xa99e5dfeca8fb62d222ab370ec9e39cd4eed8a744ede7f090c42bc7551c8bcf3f9c131f0d82dbec4d643dc9d2ceb20e23dcdc3c7328455543a1e8ca6f3530604	1	0	\\x000000010000000000800003c60e37eacc4b2c2cd8d34b1609d354e6985f2e88c82c53d93343297b886499c5795613e399a2592f01f8dc57b341e62be4811a436e8cfc5bcadc828b95564e1aecf29e35eaab855c92d6adf9f937d056cc04e10bf94142efd887cc7cd017d414bdd008d978434881e6a5266d0cab49ba3605664cf6cf762228ece70c4810f5bd010001	\\x6fa7204f0aa35b7a3e50888add31d108b16acd0db00207c380f486e600292aab4fef355882fa7c9c967c12ed208013013f068348f151d4a8b2a45559d6e32002	1674206117000000	1674810917000000	1737882917000000	1832490917000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
304	\\xb3d221a113e229111c0757985ee858b97f08b79142b98e4c1c49d254d222be158c23d2b55a16693d705c61291d06a6ba6870f697228e64654e2f406ac34b98a0	1	0	\\x000000010000000000800003aa42c7bca9113ca62a0077c006870a477a0a9688b9af50549cc4426a407bae5907165955a4c42d820e6ea7d681b9897b157fc5ef9339ebeb24aa3d5b3d0261ad9f701aaf2fbbf575b0749dae970012e70f744210e203e69baa82f6660cce9c0bcecdf3db38de1c3542abcc058c8ffa430e76cf79761e392765a9fcf8c5f0f031010001	\\x39cb4b917a2e53d56af5c20fe8e7023fad123f92ab7cef1d788cb3688ca9c17a1a1dc9edb467f23695b44cf1225978dbae0341efbc293d503df258b67d2f1205	1675415117000000	1676019917000000	1739091917000000	1833699917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
305	\\xb426b90d0a589d9fc2326a3979fe22216ee81bb35da9d3f5a47e133b3eb3000c0c15baad44c76b5083f16572ba79720076e67e2bb3e8e36527fadaaeb74f3b88	1	0	\\x000000010000000000800003d29f87ce558d920e9b0ed99e25de3ded75595eeeae470ca247e7d7b2daff3273e1f3ffbffeeaf9c5458c6509f3f6eb84dae471462124f05bda6830da3852a0f9523c1af482327986d2b79fe28e1cf2a23ea9adad4b9e82aecd1ed375195c2b73ff0c29f6ad7d5436d3412c67cfaeeb8b5635b50ba00aa1dd8a70e3ef10769a43010001	\\xbb013ecc81b2e9e2c1c2bcbb9079aa0dedcfe2d9b5762944468cb791437daa715eb6ad1e20aeeb57b1cdf853d97163e22ae5a18c5bb7d63e4d51bec2c611d004	1676624117000000	1677228917000000	1740300917000000	1834908917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
306	\\xb7d2acd9a595f28d16ec8d061c46a51995a989d179d9a85e73c5b88a78b55b08b6374aba1017b7ef4ec54665b62525c51738abc7ae3d8bb41ea1e6d991a7e71a	1	0	\\x000000010000000000800003c83d2a388134f92b6849ee5b3cc9d2bedf40b3dfb7f62949cdcbdd8810cc701d07468a1ddf30fb8a1c57176f346f4b58b0796b178e7a43b111ef09a238945a00c7021316c53995fb5f928bca5d6f100f3ff15825822f96f30a362c381d9b911b3746f91d107b963ac4123a8785ab492771c3aedb307d2d7794af6ba0dbc8610f010001	\\x9936e532449a2f2a684a1a984d2ca6f12ce368607b95e224328ee2dd5036f8bfa8d0356d5957df870b95aa9d977001ce75d15cb9c8a8aeb362dd09bc4ace300d	1665743117000000	1666347917000000	1729419917000000	1824027917000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
307	\\xb8327d2a32c13a93ae73f296fab9336b8fcc529fa7069e8f177b1cf68d0ede0fa3b548ffb7c5f4b98cc9b1ae6695932ea5b0408e8558b4e5f06386bb6d726021	1	0	\\x000000010000000000800003bf4d517f1b04598e0de95350bc5f6a9b66447d1652e8c944e13423157612ff0819a3e87c9bfda66e989b3365804c69efa6ac6ebb8773164a4631e13f4e01d1119ed23a9986234ed8d47eb11fbcc849690e3ded350315183fa6a6e5e6fd99d2a63bca83623dfea5bea14c7d621832f26593d4f1aa1b3b465fdae0655aa536303d010001	\\x05d805b587a291f5b6d8dd1076c79d6d6f9f69d7e70c6ff2f759c3f8caa563ce871cc00eba08e7ae30810d21fef317b784845d8a179332a865cbb54dcb6db102	1650630617000000	1651235417000000	1714307417000000	1808915417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
308	\\xbbb627010bfaea0a5f281be403aa300eda75cf4a8b4b908bfc623272238e8a3bb6bf7a45ce49eae71334cd9a4f5abf9b914b364eedad778113a2290da673b01b	1	0	\\x000000010000000000800003adec27a2e2e69525aad7be99d58c43d7d72177fbe8d967005e423a99474db69cd06286a586cf6a072c9aaccb44555315385e76a6910216646e0ebeca6146a663f8ee3ae82084364b37df6f9d8177ed77e8ea3a06685057ba238423b54cf74dc479729b4c4d5fad4f486ecb14358bc0e97f70d0efe0750d2b5d1269ec8600b681010001	\\x96fc5d3f36b4641a8e8558debdff9cb54989e553a58d90af24243423aca6d054ecf567af2c1708df3c8b41aa528206c87a289d9e13d4796a85cf7243271ee00a	1676019617000000	1676624417000000	1739696417000000	1834304417000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
309	\\xbb2256bc4e5d54c3da8ec27482fe7622df6afde83f7db27f9ba14bce947988c595deec73484591c4ee1d3254ac4299b3b08708b9b2b1b3417d784b1ade0820ce	1	0	\\x000000010000000000800003adb1f4cf7e512690fbf9d643ea264dd1ceccacb2f4ff0502f5f0809659a5b91712e93edd64736ede773f3dc8e6615f0f87a44fa4700160a87cc93e91e19b807b12853d5ce5d1296c3e07bc70770a5a258c478a8e6e846840adaf19d06723116db18bc695e92040d626cbb66e0403c0520f40cb40ab4d22255243ed6c4f502b21010001	\\x98419830f5ec972a7d94b2e7d449c49d1190e796e0b82396b824931781c38d3d55562b71345b8a0c0da0ec370c4b3317e5752be1a4ee02975283b091f53ce30c	1658489117000000	1659093917000000	1722165917000000	1816773917000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
310	\\xbe4e4ebb0fbfbed1195de9a5d32bc6376f554806c9da07b7c2c67699b977b5857bc9bbf3562a6c3c3a4fd3f99593f2c9c337038eff61eb48d54fb850f12c2a57	1	0	\\x000000010000000000800003f481de28c560a20f2b145395f467f6b1c7a733a9c1ea408489e366dbef676110f932a9ba7a112921eb6814bd28ea4897fad3d83460b4d3bf24d50eb9047de31d32d08d1b323c6b7b5f2f15bbdeece6f198c10558c86270721bccb7372610b8525746fc7326450747406fbdbb310828c78c94370e34337685e65b626a4187b563010001	\\x17659ef86e1a5ae40df85dcd1336b3fcf6a70ded22eb30a0ffb4bce3cc1e562cff9e0f6244c8430a00423c6fc53b027b667470a76d6d7cd2417feb167294f40b	1653653117000000	1654257917000000	1717329917000000	1811937917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
311	\\xca666251c5d8cab84a649573219aac195a9ebed4db381af04d068a3c1f0a38c44fceab64fe59162e5232fbcb752e9d4224a4eb4d7206abf92d0def41ba4451f8	1	0	\\x000000010000000000800003a2581a807b389e0f33492889f7ac20ac771048bc0e1ba14092b0528897c9c6536750ba5ec8b0f450532aa1f57eb3e46f7d68f0a58c6095b7285f1622a0bdde2db249e88ccf8532b3a6842ba5c2eac45f8c4e8af151d5b76d372ae26ba1835e4cf4f86a3b8935942b0cc1dfd19749c5f223822592c2e26aa4b4d5b483f46b5381010001	\\x07927be2b600a4d2578676e859e38b148f59d185188be489969c07e891128c4ab1b2f3a80c92c34ba6989aebe7a887de62bd71747682a0761f11e7a3492d2e04	1671788117000000	1672392917000000	1735464917000000	1830072917000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
312	\\xcb021a07290a1e3c635c43cb6209f2eb83995f91cf8783694d6b1af3ec42f85ed67df5e93fc8c1cc65562801b1b08810efca526b3cb72f6236b391c3be34ca4b	1	0	\\x000000010000000000800003de2e5ddbf29a0287d619440d7d987a0d8d3bfe23cb7af0172e82aeff28b991065d42250f0edf380777a0d242619bc671efd5b5e53c4cf9a04744662e84e1a726c1436b5aca25c7b5edff9df8a6755f6cac04f351693b95a9d3e9e9d949486ab17a422bfdb02ddaee34a813d910c88b1d1924ac6234ccf2b4c6ad5f423d67e7dd010001	\\x2dd4281856e53d3f6582dcc900f20cafb62571265af860e60c8a56b28096ddec32690e4dc374f1527637184bb2c77b38628513cd16ffed7b58354667cd09b30c	1678437617000000	1679042417000000	1742114417000000	1836722417000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
313	\\xcd3e9662c726037c69ae491f1c9c9dd750f2e7eed437e35c0352f4657993f636d176f0c48f884319068c3b1f2e94ed66456229e622644d48bb3550c355c4fc02	1	0	\\x000000010000000000800003cc2170730f9e29ad23860b6221b4513e6fc7bd022a0f3cb2bccba9c272c20817cdb59fc480a3be538c81da9ff37b4c9ed84da99e1f930435fbcc3e290e4d97a2b2e4395aec7bce9da2d0bdcfc0fd4e87701330eb8a4bcd9426ad3c8d035e2fa0bcb15b3c957748c07b96ec1413c824b0dc6d9cbb0616e1dce1955340f777f4b9010001	\\x770bbfe57e52dd3986efe4db3e566e2a47d09f555f5b609d3c7e3382eb5ee9be3c47a01ef5c0434b3b1a7adf6e0db490da70799125850d1c36f15b432924f50f	1677228617000000	1677833417000000	1740905417000000	1835513417000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
314	\\xcfba1dbb81417538eb88e95c29966c4adbb8b461e5e829fff9f3e542fe051b49a5713f2554b430860817132c3c0cb12566022baa07009bddec5933f9a6f2a87b	1	0	\\x000000010000000000800003d869bb9eab366d04eadd311fdb193152eb237657094fa123aac757b92330307eca156144750166a9c6821b089e733c47bfc0d04922f73b26544cd849fe3da893ea11e47b1bad03f4d033de3468105bce29c95857b4067b5f857bdcc310d623c3db6a5af4595d8d7b2c2fb1d889d79516b37b4a7921eebe04e44e9f54a474323f010001	\\x086905f00a86031b1aa63617afb9ab3289fd4a7178d1f9059f001e7bd394f182a83e854e2de020f4bcb143f8e5af9a8b0bd51cc92d9fb97d916f75785eef9905	1667556617000000	1668161417000000	1731233417000000	1825841417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
315	\\xd77e5a98d3407a172fe3f4913fc5c5c5cc76df8eb65f136d28952223f4c37ea3318929140ee235ca8d4a47bd211c2978f12db1d3c7ef471650303618b369e0d5	1	0	\\x000000010000000000800003cb439583b3282464ebbc516f49311381379fbd158a5256178f6822143f52ab2691b727898fdd308fd8df24e506716f415367882a8c5e6167da8f091bb1efe50faee7628892abf37c4013926f38a32b69840f8c671f961bfda0314414bca479939b66271e9c8631c302f1584bbbcec54516f8659cecd0afa9d9de228cb7f45845010001	\\x6e72ae8a0b94393c6012295cb6719367e2f084a74456d2bdedf765e42ebe1d9e7a7d8f7faf4db6e6b27f5be09a09201559bf3d5174d5c835d247ee9eafea5f05	1671183617000000	1671788417000000	1734860417000000	1829468417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
316	\\xdb4681d033e38d0f07a3079b845b5ed7e3844b26ca8657dde66e3f20901add4c3d927ec4bf1861ffc03503a3e8ae1e94d836bd6a014f4364315b274a43495cf6	1	0	\\x000000010000000000800003b577e6770129ead99635769aeb423d5247600cd29735a7586bce1395989c83942f8b0d6bd1a62ba54f607888f7efa695ac68c4f92c82c6573b4407bbfe950a1ce86730c17d7fdcd87e813d546f0d92915d6c8c71a4cd12885008e9ae2778ec2337a139527ed0fa5eab0c03441df708e739e06056caacd937b01c0a909372d3dd010001	\\x7c64ed116deac6f3fef742019d61e5a61144e3a0ac61b3601378c062ba6b806a3cf5181e91acf651b69d6fb992812999a2d27c91ff8562e0cc980517cdac750c	1676019617000000	1676624417000000	1739696417000000	1834304417000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
317	\\xdfdecb522f04e30bdb83520b91cf69e038daaa48f9d4dd080797e33f79a85b81d62bbb79da0abdeb553e884c930b70dd55fdc38c65c63a536640d7d972bc9549	1	0	\\x000000010000000000800003e0f6423fba70643d6fa444c66680ce569791248d4a0fe76fd543dc9f4990f92f28676af6807471ce5e3310be0ca6c39ee49703e491d8d9f216444e065c381c775ed848e7514476e35d6caa43403ef7555ce16043a2e94f04fc86ec1f55611bbce20bf0687de52656b87e7927b972eb1bf8afa9614f74103b5489908c2382e56f010001	\\x76f54624dbbeef96977d810daa4c4452e5ce4b8328ce952d8791d3eef69e56c644919485083460589a5b9925fadafd0510e80b8da516bf9bf7e4645d30443c0d	1656071117000000	1656675917000000	1719747917000000	1814355917000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
318	\\xdf8e6bd6a68103bf7b8bf07ee11db2fe7e94da3f33993e43ef62181b7972e4a4d76d8cc2fe4b7f5bc6fc2ed10a20e98bc32125bf338530e9c02990823f11376a	1	0	\\x000000010000000000800003afdf467943df519bf604d3b507bfb8663b9464b12dcc0cd4da4b935815fa9528bd248658383b7b64e232a1caa899b79e64a19f6e0a20c1bb7223e426429e9df2a23767169d0e55b0a38d330b1d5e8755c1fbd047f126d63b267373ce8cd2111d95933d46a8cf431e34dc21194ea0d6bd756fc43181fc343a6f567fdfdf923297010001	\\x3f3987f8801daeb98f829075c266e192f62a4b4a75c96f8318707a02b2fbe385cf7a2589d5ec955fadde8be047949dcdf03fb3738f61f19473dcd420ae558c02	1657280117000000	1657884917000000	1720956917000000	1815564917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
319	\\xe1be731338a61b5fa9e2bfbe87877b6b0d5bc8723b56473300fbd52bf939a5c3b8536c5e5b91cb5a72715654dc1ff81d64587e69758882f81ab6fbadc9e17ce3	1	0	\\x000000010000000000800003bbef9453135ff81529895198df111801bd8642173312154878690f6c3ce5a04267f3f4194e0b9a681958b1c145978f7e3ab4c0bd5c16959251911e08c7ceb97bc3d33f94bd27ac4836418b60d9233055aad6b9d7f262c917664a90199f69394e925c274ba84e62463529c0ddef61472215f1f958219a772132744e59ea00019b010001	\\xaee58f24b106c49fb4ca6320bf58ea8c912ddda180822f11c6f359ea06102e672c0507a4672be2d0c043316399d3a99ce8e6391698881cae0c8fe8b0ebe1010b	1656675617000000	1657280417000000	1720352417000000	1814960417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
320	\\xe5e6b36572a3fb6619ddd5c2576c3e2da88e9b8ca7706e9478f759fd362f44fc5ed6089bc7b433aabac7c8ea185f61839188874c2792607c5dc02ef2da5e1d8b	1	0	\\x000000010000000000800003c481c4487e6491db6c0f4cc831cf24dee4146e6622f45eadcfc88415329abcf29d4c0c92c1e776e68c10aeecd953f6d607eb3f81bf136f4b239c1f1f4f62415a9209b37f26a01dee09ad2777d5afe0d0db66d52df1b573e820ae5f4b94f714cf92d52bdd1213c0514735ddb5615183d68f7ca81c1fe4599cee2b77ff3376bfbf010001	\\xc919662ef584a0dcfdb17a774cbeb0dbf6c01a7654a32b9f1a206ed8820036d84e42665f6b05cd85a535d8b48e4f96fa7a84d5a8477be452eaca391a6709290d	1648212617000000	1648817417000000	1711889417000000	1806497417000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
321	\\xe67a58e968b74bf6fa06d3f1f26e8adbcde7309a2165f5533c7f7182c55c6f32e89b03e4e86b5dd10fd5812f57468e65dfb688e4814e5f936ceffdd234cfc759	1	0	\\x000000010000000000800003aa8ca5a64f7965c7eb9fc779604b3a263a72c7ccb8f59899c3837b3b8fac10f95a77136ae0f2829a07e7cd37df08da3c26e116cc6c7968a45eabc8e5963a2cedf764f14420f57b235a17f94b4c6f401f35c403ef7b49049c86b7fc1aec6a23cbc85453ff15b6f5c9c639f36db1902bb2428864e09078e542d698416968536077010001	\\xafc80d1d361135a89f69a50c117430a17b8bfe4157c19c01434067946d6b60032830a7c59b2562c44d427762363d748dc9f07ccabd73edb8738af19975015104	1679646617000000	1680251417000000	1743323417000000	1837931417000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
322	\\xea6a5ea27b8531c7de27fd8d69f7dd248082ffc213bb357dae3e1154c6bc60a4a155883debf493abe70114fcf2138adc767231297eb434873bb54d0a21501882	1	0	\\x000000010000000000800003c1b00b73bc676706b369fcee41697a6396428ad1afaa1e3f766a1b80667241d82cba0ff1e2d7b550485a7c78890d2988a269d617e520ac6a53a20a5bcd621f33c955268875beb0b98abfd8cc2a50a3f6148c7676586a58cf21a0cd8a657a2cfc616ec0baac6bd28770f808629bc2df2724b766e149f9a1f3af20d2a81f1e013b010001	\\x031fcfad23d09b9c5b00b351311bf51c673755ebe0b3d9ea4099970953266c34f5157754fc506c9d6eca85ac2412f1ae435ac3b5e89d363f78e84092e13ef203	1678437617000000	1679042417000000	1742114417000000	1836722417000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
323	\\xeb1e562f7e8ad2e962961b5bf0465cba710c5abc696ab5e778b4013ce7c5b623c2dda7513b54992fbb809f25e81ea6dc84bd2ab3367b8a0b4f3bfbab24f221b5	1	0	\\x000000010000000000800003c3e6aa7edccec4fd4cac5adc0a93f985d4fb8fefcd6bc4b89beea47f5e2ee397b866f978ab14b1c7142954e72a0e7468e6a6eb215761bd98aaf4dd3968e94a5a0d9f9af7dd0512c279578a31249e2485b8f783a8d09e014ba890bcb5e3a1e2b9ceaf676ffd79e6169a09f50feb920fe3d182a768dfb0e17a339f4ddee0ad32df010001	\\x993646029d4cab6a66058f3868e136ff9d720a1d84fc14325b3f59effe584f5515b1737ae413ad80f92a235b264d7f01fa77e6e0f3d3ff0923667f0dde92db07	1659698117000000	1660302917000000	1723374917000000	1817982917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
324	\\xeb1e2a0baff4c8af64b952d00c08a27420a116b362d4a3ebc49649a2e8c1872e28bff27a73561c67cfb81100c7acb193f639fd1a2ac702f882f5611be67ed0c8	1	0	\\x000000010000000000800003ce7ffdd18d44f1697a8a237bd87191d1c5044215fa5a47c9fbbf85f20910b2d4f932b97c060a964550a551c6fa3b2d7404fc16b734ad999031f86a37e5c1b363472b876404782f558d3619902250f14923acc555157365c127f8caadd7876af334acdac24f86e1cda9321a0dbebb6bbbd2997c25fd08f00ce64c04d9af706643010001	\\x232f04264b298468825b986b21108b815d456c009daf696e740d7f3c2b294270473520de7e8e579273915387150b55e8bd89725c2a5fa8012595a3ebe7eb3c02	1660907117000000	1661511917000000	1724583917000000	1819191917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
325	\\xed764fa376d3cef731b5bf1132d02c5b69a13b0d65b1cf5c6cbce1b8cb4c860e864b8ebc2de1b6454c99fb181277a6238906f503393c8111e524e2b2fa6d0432	1	0	\\x000000010000000000800003b6203b9d4bdf8b415503af9a5f38ee65995fe3cefc07fdbfb6ecaf00fe9ee671005243138eca3896cb0034654b24e9a80c47e1482198c7175bd9a194455e871d632b6533c1064fd8ca4f0f06d56612de35b70f2c83e182ee4611f79aa7d2b3bdf58a0fa07c6e98c762eaa0a5dc344b6a158765658832e18877b3a2775647f693010001	\\xddd11082578a75baf0e90e89cc931d297462cb86e34e72dc9e96542dec2b629e2ac6090681ffe6a893058de67ff56ab1b85137ee5d0ec4fc9648e658682e700b	1667556617000000	1668161417000000	1731233417000000	1825841417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
326	\\xeff2e159387c3d37a4e9f8731b33c22b176e2b15a6d5a7fc4a945061de4a4973891ba8470563732047424f970702d367fb4835222c1c60b8be12699f7d7b857a	1	0	\\x0000000100000000008000039d9b7d437dbec49e1e407ba93b8e385f8fd9626fba99fcebe616c82bbd422024488f1d571cbf53354d4887c19b1bc4573452931708a07457a6f831f953d8c138905cb4e7d42036994e6b34ba71877320e263a30969691ee209fa545c4916df4922ff9a08127268d0a5dc3a2ca883d372fe66a090a14ceef0605d7b0c82310a4b010001	\\x97cef775b774fa63f0f9ce0235b74c2d3c2462815279c557e9f0a796f0ba797cd5d9e755537574fd823934e07975a3b1e2fee123fe0af1b3fce19f8bd73b2900	1660907117000000	1661511917000000	1724583917000000	1819191917000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
327	\\xf2deb43f5101050e4cb536986dc30d75d97a6a409815fab98ab293fa3632e3539ca80ef40b4527d8add1ceda8a99107bf58aff54e66a96105793304c605909ec	1	0	\\x000000010000000000800003d68656ccd1ebec0ad80f8209cf2b4639c8307c70b5ce62344dde9855287d94351f3bfd54acf5f37d60667603855808faf96d6b7c595d746a7ea9dc9e18f1096d4cee05a054eda05cc2d0d7ff9527dfbe537ec52b4c364825a14fb606b95bfc1092c88a78b248ee568e12836109e9c5d0073f27af2b0870d0ba05c3fabf1f0a29010001	\\x4692c6eb9df1bb071a4f4d97e225948ac3a7137aeb58e66ac59389a63e5385a35507086911ad9f017a09b8dd939b70ad04b17c6fe21fe2d37cf62aa6585c4506	1651235117000000	1651839917000000	1714911917000000	1809519917000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
328	\\xf5de42f9abbda277eaf38702e5a52a50141b201c76ea8172c303f2505cc316f880ed1d24591768a0893a723a71272a2468573bb350a437a5e129769e29245de6	1	0	\\x000000010000000000800003ceb9cc71b2044fe323b886d9cbf37a0fe1533b45b9e4b5c03290f4215a70bd78693a4ec801494b3f014f810ff0551f70a3a4eb01e080327d49b36c00ae35666d79e82ae34ab59ac9fd26a15c7530331f841d237e5810eff85ee84d7011a2ab7b034a93ac8ba9c1ce879bfb5597e9ffbcbc0006bfa6e0c253432f2b4fdf76ef2f010001	\\xdc661177b64e53e4217407764c23021086771e23a6eb5af0189205e9d27af6af29f943c70a48a793f00b3fbd18ea4b217407cb3e8e16d72a3a3b3c4354dbfd06	1662116117000000	1662720917000000	1725792917000000	1820400917000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
329	\\xfa9eea034180b37d26609b870232820ed2d4f5ddc1b207330ffa161bf60e83ed5a59991fc5159a29aa91c6f920101ad29e5f3faadc5c1eb02ed886dd7041223f	1	0	\\x0000000100000000008000039b3dcb7421f0dee2ae9d8e055b31f20f1a4f2f0a9c7a3a0cf3e2a3bd73ad71e1867cf04073e7bb8929cda8e271aebca52f9ee009396f49e7cd422fbb218d8348719cf2714b70f370d31cea3e491436803c4c0c292b5b6fe161e16e1f81d47d0dbdd73648ca0fbc91e5943786525c1df025ab0e8dedf021d4d762ea49cd3dfe6f010001	\\xc91186ad8354ef1ed7b32ac1c384e6588d07a80944a6e9010eed8d23eaf97facce2e25c0ca785bdcd5558312c4411eca3ae80cf1fa07eef2019c2b98808c500f	1677228617000000	1677833417000000	1740905417000000	1835513417000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
330	\\xfdeeef8227458a31da65699f424a39c22a8a4afaf61da06bd0f8d779f75c394053a402a7f39e8373e162765f5c42aaa0573670bef2115e105c4981540ae91052	1	0	\\x000000010000000000800003c2fea976c15f71a55bcb20d4f8326da24d420c2e7629a51e903c5ae53a38c21d47628ba60f9b879997e8265010c446e5987df81a28c8afd0cee86919e0a308c52f881f5198602fa703c81686d27b86787ce01a79f775909c4b317b20e128ca2d4ec17a40572dd0db6c3194e103204c51c4e4cb5b05e4a7738069036c26b0ac3b010001	\\x062b9858f2fe4807ef184c705ace4ab7dfc8da34ade3e80fdc8f079e869d9c275e6bf2cb5e382cb6cbf0c295e4db6c2283ff693a24fad7d9fd584569f6872003	1679042117000000	1679646917000000	1742718917000000	1837326917000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
331	\\x025b7b1ae587cc5993d4108d9d843fde8f3e07a34e9cedf7e12b74df7d8f518167cf37c27e370baaa43d0f69b259dfc1184840e33e0c042bf9a948115abd7b01	1	0	\\x000000010000000000800003b861334589826ac9e29750ee4efe3c9aec4058b266cb57a9b25571e14506e689b9188d123034e5f8af9b5884e4f0cb2e0be263f8f404cb60b381790d34e4eb336c39bcb1a70d99655e6a9be2fc63e5b0923ec72edeb0b2313fb01faa1b102d2d3a438667b1ad288a733a5b78d5a04f865ade137a8e38de39677496a00be1d641010001	\\x35ce1d49466e55d3b78488da71f5d03b85fe29d20f57a0bfa822213b013a902e7fb466ad86ee2c32d4e1f742a12a468961015bfe5aa7a3196052543eab72c009	1671183617000000	1671788417000000	1734860417000000	1829468417000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
332	\\x0567475911bdbffe887a73763b1bf854d7c110ddb825d8205219570f3a38dc4e36b77b6332fa6ce644425f11301d995c3be6acb25c738db8ec6046f14afecf9c	1	0	\\x000000010000000000800003e904dd60a8853483155127c2ed21231c4e010bea0230717ce9060c4825fdca320dfbcab78c5ece4857a436cc06bf05bd717ebdc07c1c732cc3f5495a1c3faf69c475193798df943f75250088db1473f69023c8746c0b539d29901940b1a250ab210b6bb082c4207dada244639b94e517b4650bb1bf2b56005dd02f6370f5b6f9010001	\\x9714e61639849995ebc56d831f76f98186661a1d6c4972af7e2e455bdb53e8513314ecdd7a692fcf567273f3eb0c47154a72eee25866adec30f698ef1a034b02	1651235117000000	1651839917000000	1714911917000000	1809519917000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
333	\\x057f33660d0f92c28b379bb039af0ed7ce5dac0366cc67b6245b8fed2b55dea285c40b229b91217305e9f6b17e3618ffe4a468b5a4038c4df390b84f12376d49	1	0	\\x00000001000000000080000397a0bb668fd62c783be8c2fac354f1f0a5e7aa24973b49814cf26054aed39b7e77185ad3da34fa768ffc4315854935b3102a10ac6ee7fb7a870b8771fa0f14f2db9c72a2e38c1557bd9a5d94bc9f619bb8d16e8ab44a84ea577c879dada2bb389e505a85993689e2c4e96a756cb77acc77a01a86a5f22c6955cdfc2b2507a379010001	\\x00054dc62051a1d1da8a63c6d79ba339c6a9dbe6710c604463e4e4dbf3f34fd11f59bb6e9d6a84c6fa91e41538d52c8508020d90cc650f14eebabd8169c56d02	1665743117000000	1666347917000000	1729419917000000	1824027917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
334	\\x0657e0da6a9b35d30fe7f1ff155ba6818ebef5dcb7ff31abd5a6640e36b022c92013bd50f4b94948e989ad198360223acdcd6ee164b57f2bcc52b6d5bc3e1441	1	0	\\x000000010000000000800003c50e10ea09ecce900a7e6849698e8386261f5b4c8caed33e9fc977ce3cb7f291629d23bdf48ec9c205aaf11f336fd2a83919c12aba2db25049232b7c97d229fed5b89f352e2f22064734623027ee70f03e9dda52dfb192d2ee11b1bdb77840cf65636f9c3ba3e92ed55d746b3886b6905ac5be96e96c01ccdacbd7b7d7c490a5010001	\\x371f90f85594818f7be9c212dbe9527a19718a5be36cded10940284415a9080d983b044d20c33e4735a19b510522dc598b0b47414325ab9aac65829f23634004	1669974617000000	1670579417000000	1733651417000000	1828259417000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
335	\\x08f716ab1aa7d0f92fb7a340730d48a4894f161ed925de868b3a3254ec5d4a718e9c888ab10201673b1859fdd037977fd197de7f17ae56e83291393055ca6235	1	0	\\x000000010000000000800003e8821cc3fe1a7c158acccfd3d264767e6fc9c93fdfdb05b8d3ca39a372e792760922eece82ec79654a9bf573e0647881c9a7b4bbdf03bb064447dd728ee30bf56776037efcf77ca1128aa4eb3f5edbf963df86122a07c71e39f17f50e7911095162cc4d81a5b842239dd72f392c67febba03d95cc547e3127576bd3873776eb3010001	\\x8f320e0a83a88da8117db2f72190ff8acf22632fcc99a71f2ed7c1ec520f4f059a5ad8ec060071548fdc13fa6a72b32eae6d70f966d8b0fabc8ad6a75fc8050b	1665743117000000	1666347917000000	1729419917000000	1824027917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
336	\\x0abfd50fc6d90e849bc6c734fa9c46f6cb9e16f7b36492756d6099450ce997ceaba090e567fb28bbe143a925660272a9ff396ba59783c68aad9f8814e7463603	1	0	\\x000000010000000000800003b20c618d759cdecc4e1b9d4e7aa6dc3bf943058ced732ad5e1023f7e0e1c65e9bce0b7a6560b3ccbb3a9bce47d4a7bccb3778c40ef4eecd5f00bdf368d2887aabc941bd532cd6b76c1e6b94e145864e99fd4cef1283ac33241cb679fece31617d458ee8b94450718f21cc786d1f07f315d234dc8b762500fefc09f9d32e4cbb5010001	\\x7761b477cc3c98b44deb72a5998bf0a557aff0af724f4e6c353dca76ede4b6bcb861aa534d5e068942ca74d3808e05df29daa20ebcc04dab5af45ed5d192fe02	1660907117000000	1661511917000000	1724583917000000	1819191917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
337	\\x0c1769deb1fd20707356e16cf8cc94dbe05c7d2fe734fd5e59ca1ec0fff06f164199435cf18cb96bcd186510cb31e5c8ddd9c8436ae49c88cd22b47e44315245	1	0	\\x000000010000000000800003b6b837be3ac9c0a0d93f87d5b0661e185884f6ffe15288fefcbad486aeb3929713b4158180d508813dc31579f2c2fc812e2431cc9f3864a4f55cbe24377e1b13d20e5489f3d6c5929d85111bcb0b8e2aa08119741b2e1646de2389a68732435b697755a2110b5f497bac02302e0da901daf6e0eb8f960a758c65568eff981b8b010001	\\xc260f139a28872afc90b7ebf7f1ca98efde77afd76c0f8d9b8146d4a5c23a771bf10c34e7f66e01efed52f9f4fbc573598a94ee95e9a8ce37250bee841258c0c	1650026117000000	1650630917000000	1713702917000000	1808310917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
338	\\x10cfc39a54e5d71b83094776081179084475066223e8e7c587851464232e2cfbad104165b0a8457295781c031f34feeb0794d7442d5b2f9c85fdffea1dbfefcd	1	0	\\x000000010000000000800003e6aa5b03a3eb474ce78f34755dab2a6955b0ccf8d0275bb870e96159785885f26842aa6ad1c434b47a04167d7a0fe60057568efda92693b956300ad6173e5f91e19bcefc64861697287075faa35ac8058d639a0fa48877089b6a689072ff52656a6abfc1f0980353e5586ca947ec7190d965740b10a8ff6a13d84ba239984a37010001	\\xccc0922c19c7e617ecc49750fb2389949e6847a4faa401c3c5767b43b64b18a9388e651695fc8adfc191a9159f4e9afe1197cd908d055870ad161435d825870a	1671183617000000	1671788417000000	1734860417000000	1829468417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
339	\\x12bba469afe0fc154a929b4605e1d86f3cae2257e67097fbc21cb0a470dfc105090520c1fdacafe215e93e97e18e4d59f24769e67b1231cc48ebf63b966d9367	1	0	\\x000000010000000000800003ac1e743c81ad0930b6b42bfb1626fcaf75c039ca2014d250d6aa6e730d3c0453e97fd647b7462460801c52ed6bfe220078e24eb57c3d9960415d0fb37a1f1d45620d791ddc2d603fb76d43d3f70ce3ef63be5125788145430ddd21e140e9575d90da78c1b541fb6941ed85472c5b77bd69a029975557e5578676ce048bdedf23010001	\\x45b225b42f056f2b1354ed070da30209a71161a109b54571b0bdc0c01bb9e25a17773bd2775761727ac2ee417f039445037a42638bab5a352831b35df39a9f0c	1669370117000000	1669974917000000	1733046917000000	1827654917000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
340	\\x1a7fe47e49ded88c75dbc624f54524d8b1d2b9d5fcf85cf7ffdc6805c1f030024aaa2d8d15ed91f4d68b0d99d0e53030044bbbea98574f1b0e1be04ec4c66ce3	1	0	\\x000000010000000000800003db13c5ff02f7fcbb0f171e24f28cef7257851d0b99b274657f540e33dc1c0038201ddf24845efaaa99632570ced3f9cadd6ee63d090a25702144fc4d2a085ff935c227076bb90a37c4ea835a93f7e3c72b6d734383c4090bdf3a49f2dfe80c5625f17fc3ee22e898ed16637218fc602041b225780302f6a40ab09c25c77adc23010001	\\x910ee9a2d46e842da251ab7f116421d6b336039fd849d202fd4976e9be4e8648307bf303c1492a1dca41d78a106cb45b956466c9e649567e2441b99d4cdc2407	1656675617000000	1657280417000000	1720352417000000	1814960417000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
341	\\x1dbf7529743a9097deb24019436688990c924eb98aed4ff6c14902ae624489e0eab013dc385e22bdc9db02b2b021571ddad90385119aa23a27d246d27cd0c5e1	1	0	\\x000000010000000000800003a887ae33c1926000b1d78f0253db62fadb37774f3614ddc180411670de91f4d708afe36d58d5592b4af36f788a8836ccf78cf39e32821e77bfb17afe26be15a45c628c004a184071313fede2d8cf1ed801a32e0af19cad00bf492db764757933203e04fba0569829d5ea6baf42f3b5ae522d7cb2728e83b77cdd3d93424d77cf010001	\\xd29a892dcdfba4367b0361c5b020ce4b8e9e07c25458d70e9abca3fb5e8f2c5d6b8b92f0d74494e0bb75bf6dc3b917be16f299f16aa7fb9bcb8f910f05d09805	1656675617000000	1657280417000000	1720352417000000	1814960417000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
342	\\x200705de4dbecb295ed2e780bbf065c18e656685cad8060ea9f5cf71936b27937b1690bb3ba4cc7d2a1aba18d941a4591537417a2bc129c6c33576ece59cc688	1	0	\\x000000010000000000800003b2e8eb3aa38bb3c9ba1e9a820fb31599c0cb8865d0bd8a631dbb291009896d26403d5eacba338355da15fa1b26cc6a91706f648c39e3e149dbd8d7326784604786d6fdc946d1ddc4d7dc7742884f532f466844b00e9775d68478c94ac3c0f2cfd860eb89b2e3bea5ec2d5315f72629593a9fe6a790b2fdd973380deee624251f010001	\\x6ecd175c65181f275f1044a8440fc320f433202a00be7dc3736d1709876587656f81b4e99ad611262843d2171b270e2c946f75192362a3e6cbcae1e8a81f9f0e	1668161117000000	1668765917000000	1731837917000000	1826445917000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
343	\\x2273e51817025fa794162d44b2977aac2c2966c8f8d760a35fd68d655a989af13aaf175b45bd692b126a07786b2d80d421c2a10d4a13a4d70648fa1bc9e60402	1	0	\\x000000010000000000800003a84a1f77f7020bc5bab992c8fea9f20cad05624137692920d14bfc392c338862f4137cfbc77e3bf5a3b4ffd2adf88842bfb479beb9f9c162b7b323fa60e4d35cc1e486d7ae46450b2f333005fc4f2fc5deebcabd5e6c2fad34ff6011937d7c4a007a3aec61baf77a1fe3972b8d4ebdffd351398ff170021075bbbce41e276aed010001	\\x2e5d81bcebee3a41f9fcd42acca5656a54600e615af1983231ae04d8adbdf9026bf7c6f1c8efe9461ec8e3130dd4fa796909ebe76ad91af5ca2e2310eacd010b	1662116117000000	1662720917000000	1725792917000000	1820400917000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
344	\\x279f285c866e8d35c1d2a9cd6873666304afa0714b4ef4608f21dc69499580a3feb49f1715c3feb8989d499f2691b9d81f18fb3852eab63c5c69e779f5aa7955	1	0	\\x000000010000000000800003b6b277d84bac3607366d52c129683ae57ddc4b66f365a53c91fbd5ac8b7d63bdc422f6f3571cabbed6579f95ee6ce78cf5d5407a2de3d5043773becb64005a92f064e7b64596a3a701d8f396f790d16be845e665c551e5b8f33b92d71491c6c74dd681c837ec495fd07131ed200eb5cbd00aab433062889dabc86922023250cb010001	\\x086a592b56ac04c4c6f13c979a44a2fb66e1ad1215193933093b2d6c68757e1485d59bcbcf9ba348eca68c9bb0883a2d9859dcc7e76bf42409d0cdd7e8e69c0c	1653048617000000	1653653417000000	1716725417000000	1811333417000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
345	\\x28533aa73b72ddbe43bc176cf1496f6cb0547275f9fd8495d3be4a50fed52cddcbd0b58bac2d2cdf94c4292d9ed4d638d68a9fecde67d178a516dc8af967d661	1	0	\\x000000010000000000800003c702c33827248d205064d5f4c0fecf2a4b1247022df1a7213e1c5c6c879b705b107dc677255522b8c91d1f60a8cd0e1459e601fa975a0767bba8aa2268c2caa4bd7f4b75fe71c6880adc0a1d6e2037c4d293ffecc65898e7a937ab6ef490e291420b6f453063ecf80a36802aa7f028784c5b87e20d0b6aa16ba3a5c178936fa7010001	\\xb66226d3ef4d32c9f775092d816def59286af43d5f68fdc8a4f5dc5eb7c52f7868eb3771a85931612d9dae0ffee8c3a41f78b56a27c64cd404b7c53030c4df0a	1662720617000000	1663325417000000	1726397417000000	1821005417000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
346	\\x2ddb1ffe8b1d2247b592e34ae18dc54f964e5261d23064af68691e56c7bdfc98ec2754fe6a52d6483da2b77021ec39f4ee6466686657c0c57c65761a8e733e53	1	0	\\x000000010000000000800003bba9f59cdc004055ba77adb8b2e5972a9aeba2d20448ff847027dffe27c9e65696a478533ca97aa021c5cc6fbf9d4f586955af0f9ce4697f3e4d5fb63cea37ebd47116e5e5ed31674250a6ea87f352fa8877edbec4ff258ba564efff315baa3afe544dcac2c07d36fc04b23c852f7dd9dc1fa19af1c807321bc53e1ce29384eb010001	\\xf06514646ce3d0134d37bb1f1570d544c95807aa5fc795acae31183307a42f272a9b64ebbbb8d8f5c7097b03beeb15071cd10bab63093941fab7bee9b01de501	1656675617000000	1657280417000000	1720352417000000	1814960417000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
347	\\x2faf9e09b4f9ef2e419938e6ef0d6cc7381c4c93c2d9c5cc56a47e09c300af6adfa64fef386c24a6a0c5912181d3ec4e36f206515f0878a64ef451ad1872c42a	1	0	\\x000000010000000000800003df46a94d3be7026411a99019d9f6babcc38e363564cf3abfcc559d6000cae89ed65a64bfd8d0f6459f4e216cc0ef28da909fbc9d869c4e23bf5f69b05c194e3587fc34427fe3e6611247d443f6eefbd62c9c5b328395c1b1f71d831270c31c1731ba44515d25ec520fd8324577ce7c87c376eafc0b78e206e30a291860b76dbb010001	\\xbf0f9b95b007aeaa4ef3382ed573cef62c0d4af9de4056d8a2b32adf36b52d20fd815135f609b024c4ee9af5a1bdd0aa51620e5b285ce31a8921858e2f47aa0a	1653048617000000	1653653417000000	1716725417000000	1811333417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
348	\\x2fdb98464e2b93a5acea0da59a7263d8059586d292a80fd029136631906836499d19fb7f7723e895cd3dc064118a3fa15d99432dce04ed2b91fca8d64d1ad70a	1	0	\\x000000010000000000800003ac958b0d9cd14d0c42f497b0ff1db9fc4be0ced387c4ae0bf7be668b232a73d998d4b4f488a5d931456c561d5f6eb8dab0f972de2e730368f60ca215a854967de9ab576378e2468e4bca1773c62b5094e535d28b185c69808830270cc290b7e77faad0f72063db3d1ffba18bbccad54510a7cad6cc96a83a167e4665a6739a0f010001	\\xc1116742bef8955a0f4adc078a75d5128ce6501245681f53291b63adabb12e893abdd4a7a2416509cd9458d4de120604f8021524f52f1bdcf82abb53abce3c0a	1659698117000000	1660302917000000	1723374917000000	1817982917000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
349	\\x30b399272abf77ba564cdcc4d90e6c6d1502d3162776d8bd188f46acede42ae26db14f43a909dc2e73e3c808b5736bf6cf52d409287b0a468270139448a4835c	1	0	\\x000000010000000000800003ac2082997645545198f3986e03bc561215985f38be9aa7e56ad059b449d1a1830e472b4a41ceb3ebdfca0cdb469360879c71ef3e8051da9b8abdee2d499c6012572751d6a04622e9bde6ff745de6a105f82354b72b5d6cb2259b86c75d7c0d8a4478406ed6b8ae5d5524a91145096f6ee7f208ca144c3370495aefb73f87448d010001	\\x12a2dd94ca4109f8b5a57b1b56d807339078e77de08ff0e7a6f20cc6ee792a3ce6f0daeaeeda38c6ac34f9b2fe452a2322515b20b7af039d2c79731e3fdd9e07	1665743117000000	1666347917000000	1729419917000000	1824027917000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
350	\\x3153e15c3a84abd0d230584ec309f176f89fcb9d1b88e551d64abb4c03a48aafe6e987a2a1e838b9d930743f7a4c380b14de844a7608e2ac7d940c33175f3625	1	0	\\x000000010000000000800003ac885d89c8d17cedd72bec596498687d19f490050d3d8915b062d4fd0a493ac48b9f61d52d3623b5488f5a605b1ab0f8a768d0d49b87541b3107643d14ff984a27e5b2558acb018fb86417a2620a40f9ade33758b4b62a662d4aba78ccb29ea39f08fc3093958cffa17b60b0e0d17d31d80622b31e37b51eb84930a6ca497b0b010001	\\x8680a6c356defce16170a50bb2bbc2f3107064c1115dac27ac05e4287ba8f64ca3051ebab30e4e298f98081f4b63d72ad12712f491ac4315982b40b985dd7b05	1658489117000000	1659093917000000	1722165917000000	1816773917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
351	\\x337b051c1c10e0dd85bbd7571ff6a418269ae9afe12b9ae4258532f3c09ab54ebd2554bf846fdf831b27ca75ac6d35741019e45d807b6852cbfa78aa2ca3c02b	1	0	\\x000000010000000000800003c7e1b2944259d22fe4570c70e9076c0e4da1fe7a58e7893d3a6962305acc575ed4a4156a05f0309c05579929da857ba8ebf381aab5734500d04017d0b01dc125ec376d04346ff9def966e3c2a7ff9c2833a22d00ce3ca046cea86bf91ca8c1de3640bc8a1a92e7984e54faa60d5c5a6bd07f4cc6078f28272f1fa2cc1d982b29010001	\\x0d5713e26e3e6a189ddaa228a2c5784065d8c9466fcbeaec8de1d64b188c442843a54d04d1d7d89a48f34760685e812ade380f0f483d8c7b3959b8b312e91307	1679646617000000	1680251417000000	1743323417000000	1837931417000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
352	\\x347bb5704ae14a7294cb469895326c7b172ea2d731763c5438c777d1c5b936df37ae210f846be7e84f12a79b256c4039a130e7e246f665c6d187fc1c76a3de45	1	0	\\x000000010000000000800003a837c91f3f5276f37d9aa64bd1836eb886ac8898606c13dc979163520c1a654a96cfdfafbeead05e683a8f8d78dda69356dd82c62132b021c4af8337a69ac049527d2db2430ab3692d0b7577cb005864d122ef4f777ed8edef7951fe52fa6bbbf5ed902cba3dfaaccbf3893c33aecb314f14721f7c2f209e23b5fc299111eaf1010001	\\x59bfc35989799ba86ad2312978c51c10c3ffbea78deb7766633fec6ed054a6484c7c9f5e6c4f65204de90dcf92cc53fb8c0da21e6c5df39d3d17ec877bac240b	1672392617000000	1672997417000000	1736069417000000	1830677417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
353	\\x3a435949e073e0dce09a1df05fefbf4fb279ed03c35cdcb9b8f0cc7245c58fc6d3a4b66c732919496124dbba6f636eb418e4c659534e77d0cfbe60ae177db32b	1	0	\\x000000010000000000800003ec08b965f802eac26a16e1f32655c1c470d6198ea073037c4818d0384f3f61cddbb93a5534d7426c7a64cc4bccb7053f914dbafddb0471d5b655d5e1a3a4eeb7c796bd00c4020e095ab4b0add07b1bdc456af5f4c9610b86a2c166d28200773d6162b29104e41866673f3f52e2226804d83ac94b136c1e5ce2c9c5e75e424f53010001	\\x4a2de20c518519bd88c58c1cb5ba8525e2ec044d2ac714abdf035a86d222af3bb94bab557987bac8433920e3eaea09fa45e73b4d3f84090ac1c8a4a70dc4f709	1648817117000000	1649421917000000	1712493917000000	1807101917000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
354	\\x3f7b13f16350d972e90642e5965b02787b2c3362812529b659f91aa717fc4892e283b06371ab4b22bb31d70be5f550e6ef7ef38d721d38ec41562091c11c5f39	1	0	\\x000000010000000000800003bf1134ac06181538f3c379983d7a6eef3d6d1af432d2740605bb8035c4c7b321ce83ee8f2a1c6f6bd3f1f66222e096ec282ee625f7c86bb7ca8152e4d1f9d5ad6f6bbac3f2f58606682b07957c85139107a3665a470d1fa5d36e98095f9b71a9dcbf7b3568ec417a461848c8267ce094b38693bc8d5eae2cdf80875550c3c6d1010001	\\xa4fc59dc1f5011956d2e8ee6efbebe37235500414bfc6c5b4ec71cb426bdf89c3a48ce5b40fce1ae75067086d553d289eb653b411e7f269c07342916dff50608	1655466617000000	1656071417000000	1719143417000000	1813751417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
355	\\x43b7a056e60ec1dc555b966c06a52e15e54825f6bf9aa34d2a7af6ee1a40c0063d3b243a8f5c86e28693e67b7d4f21596d08e4830eeb513302464b44bdb8046c	1	0	\\x000000010000000000800003b3b7ef4df0928c6c78c2f24a4591c5aa8b7c41a719eac97e351591ec7c7a2bc17538be1a0a3a12586dee9e3e59d863bd2fc37205c1caf70b98ffc563627396074aae6e17347512be0d96f6bb7510a41e8dd5b1d9f666e139d1c2a8bf43556339474648ba5c074805f64381985089afe8cf5c4efc48a8fb921444d62b2a2e1cd3010001	\\x6c45f1f033b5ef3fbe9115cda39f6a3a8d76d833a9e1044f9f78ab5c82e2eec24c588aeceede2dad493b2a582a4ace4d382e73fe69ded5eef7c5a9016c7ed505	1667556617000000	1668161417000000	1731233417000000	1825841417000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
356	\\x4443d14e22bab6fd846119063f0c23002259764ad76ffa5156cac07ffca50c64975da8af9170d03ed49cd6aa589b7617e08296e2097f7677c67950505bbef41e	1	0	\\x000000010000000000800003b1e6b066fd4756a6e8eb308a6ef6f3ef9e34272495ece1fe6e010093a1c2b06442b1591650c1b4463cc3d4d00fb3cb908d3e3a6cc6f66ee99706137e7e1dc10dc0326f897e1f887659d65dc42355bd777287e66db407f02d4e7b98df4c18b1ce60a3cd8255540a25e5880df4f36029b2105937b746af12ac71a5e38b283b995d010001	\\x048ae96a31d930e97ee4686d15649858cfd99e3d544b1250ea15b8d753389afc1b6416796ae31dcef78a086739a507672a12e48ea379cce6dd9ca925ee64f405	1653653117000000	1654257917000000	1717329917000000	1811937917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
357	\\x4c7f470a15aaad021eef5239c7c6e0e49730f92acd38022d66d88a2bbbf1bfa8370ddee4a7a59b78c0030ecdec2b60b62010d98d2b5bbe0ba8158da05f19be5b	1	0	\\x000000010000000000800003ea3e5affa506a2783c17c7890f3a8ff4e6f3618d6f911358d8e9fcfce855d5b443a62ce8bb428450907594fdd8825154c9cc3159bfea7def90db66badd9fecff3982930916006e14dace46a759e398fee9f1e9275fd52f54a56fd2c4de6303753c8bf9186e8e2860a1dca64ddfb77abbfb218bcdb62cbc6778798184c13ae749010001	\\x344ae6468b280f777223321d8256bafd6215c209bd6289be2f98a2fdd35f91d24b9e5447f37af6760c645ed30c53966ea66ac388046a640c8329ff9824143205	1657884617000000	1658489417000000	1721561417000000	1816169417000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
358	\\x4d6350d817d333ff0468e3244b9f344e1712e26b9a2c13e8dca0cddcc9a552ebe3c65139443925e0cdd13d364a5153d3c0c63020844845b7b1d06343bcdbb51c	1	0	\\x000000010000000000800003d8c2c566515feabb027b1ae2fbb7e74ed30fdcdb0c204388a895c4cbb14ef283d11892af28fb79ce608614263c096bfa8315fbf9defbbe03794f97568081e16c36eccd8f623c4cf908f5d3ac1d349efd73709dfdb99265109307dc225f0a300699a4ed38d7043ff9d220774d66f6e2e2cb6fd142d443a8e077a490afc2437463010001	\\x06e858c81c5c025e5428b276b6a2d717f53d198bcb472fe407f91e7fec12a445c4d953f9c7ffb860a835ac2f8f3875006bb1e5b524bc2d23edfd0457faa85708	1669974617000000	1670579417000000	1733651417000000	1828259417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
359	\\x4d7f0b2fe1462e6832bb66e6367d32619840374b8b78587bbdff09b49117af15dca4f63714ad7b28654e72cf65607affaa5f5968dd302ceafa4e8d48d3a3c511	1	0	\\x000000010000000000800003d7667bfeada5469f6e58d5423b4a4b0f5bbcd0252fe7e7a156c53fa04d54c2b0fffab2d9bfd96dc4ff9bfebd1bc13eae1a17c813a141dbc01661f649ec6ad64d9eb2eebb41346a571c4ebb37ec7f78c2bc4d1329ac16d09f8d2162cd372f5067efed966ea6cba3aa88aad3c209c369bf68b77e8040c4aeb58b791f71dd9cf381010001	\\x2a612a368c7a87215d59e1303bff7650f60a84d0b330b8c6c151f7ad88e8fcd0e334a0d192863a7e8eaa67c0100350c1cf6f0906ea555339b8a3c0f3c4bbf501	1660302617000000	1660907417000000	1723979417000000	1818587417000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
360	\\x50fba776572c56345b8bb50b71fcdd1e9370c06ac68ad72629f69d6f92bb88dfe9842d764c271127fd5760e18f4abbea62d2f722aaece9926527b264496f40fd	1	0	\\x0000000100000000008000039d825874d5b0e33df3e0cc0a6142bad68a05f9c1e1e7b3bda6b5d747a36eef79bcf53fc03c433baaed717c2f18bd57d1a543232730e5f96e416bb6fbe50239a0f19e4d301f752bbbfc3fe4d35cc0a744228584b944a597741e5e0783b9dd93a9303db59c0b7586e4c708ec0d338bf8de794bb111ae681d268b29e0fa31433591010001	\\x53ccce7bf31533181ea05c91119df0f0f7053d501b2a30310728f37beb5ff1456d4687dab58eac45693f478b98fa6170b54a8996b4ae10c581fd0d9d548bf606	1669370117000000	1669974917000000	1733046917000000	1827654917000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
361	\\x513b1cf086e078eceffe4f0c63c9a19181dcb82f9473a3965d46c9733f858e07d01f99c7673a1d94f63a60b4604e8950b8654998f1a9459af658f1d27bf19e84	1	0	\\x000000010000000000800003b39eee9246feb00bdd40391661aaa81a077e78de0d87914e5fb35d7276b4085433b050bc7a09ae2bbeea14292804ebc13bc3bf3dc40e541005106ccf4c8e158868777cdacd4a3cf98cb57077da62b42a3870b06f81c98912889a3d2401355bccc329a48359e220bb35778629f808bc27e8120cf64010dd0b067e5a4b501c93ed010001	\\x701a122a8662d1e2bb3a8ad1f3c9ca0130a8ce90cde4911adcacbbfec540076f273075b76e9a9ccc6d15d910f4f1729112e29e4e360fa3aff9b8e3615dfb2006	1649421617000000	1650026417000000	1713098417000000	1807706417000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
362	\\x5af36a6c52bfd4946d5881ff77cbc4bb341a937103da6f87c6f40c71f77e702999f67700c1252df667fdc14cc37b1d4204fe31798de36728cefaffee12db0477	1	0	\\x000000010000000000800003d1b796614b36feea8f1e2c57934d96910765a4eaa3983c0252bcb80ea626365a0a40c8c63c6188e005acad5419a899fbe2e54b47eb6a6a3b937cd276e7b8840798168141cb22a78a4076aa985b17645cfe186dc4350f00518f56e6a9626320ba0bb6778833039c8e8b2c802b5df59d6da9a0a13e1ede9539dc4443949bff610d010001	\\xbe32a80910220db79e58c32ebe00a134794c82a6f70b3a6cd13bc1f2ccb1cd46aae26ba04c05b10b992b6a9053d5edbfcad7feff33fa09bbc64d677d095cf900	1662116117000000	1662720917000000	1725792917000000	1820400917000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
363	\\x5e9f366f0a7e51fe123c2a1aee4338bd596ec0b9b3021c37827806c14f9dea0b3ce7586736355db3d5793e02c84c2bbca513195e01c265f992df7fe28babf93d	1	0	\\x000000010000000000800003b83833489e11cb7a6a35a060c6c4c329a3e2d6e92631085a0577e1a648ef4aede57235f867ab03adba0308063e73f65c899c31b0e4dda5ddf3c20e40ec8945b75143d2bbe04911e0671641500751e7f2e2279ae9c2e7d95ea9b219f557caca44f83e150ff6f109c13157727d24434bf4e085d269ca0bf0c7a9925d4552243157010001	\\xd4d16481aaf42e5caed718590df6adedd555b7ab8542df107739455bf07b5789c08c6a5931f6032671ef6dfc64625986b29b6d741997834dab2d976421712102	1666347617000000	1666952417000000	1730024417000000	1824632417000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
364	\\x6193e3f046b58b908b7759b2e56b187161196d274b8daf0935aa0e86c539a08554654a41ac9eecbfa4ccfbec1b1f50bc57b073671d70f371f923f4e4f7d55f2a	1	0	\\x000000010000000000800003d06d2f5cefb941edad51bd942d641059ab180fc27c3b9aa74bd42e3bf41bd069f4acc1d8ad0826e0bad09efd43de994b9500a89af4fdfdbfbad8f674111a2d3cdb2d01706024b8ea0cfdc31492433906e2b62c3bf4244f50c860c5f9531a3c7057ab8b367567f7b220c0cabc79d65ca598855b5893cf88fd467419970bd27d17010001	\\x74dfe91da982c097209614a1fc91c15fbc6439c8605e406275a86d56c4911dd69144a6a93dff6845d6837b39eab66cc52e7525e573eee102026d85a82711820b	1678437617000000	1679042417000000	1742114417000000	1836722417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
365	\\x63e7ec4dbc480e7c9c5ff310fd5c6b8c5e9c5cbe774671d3efe1348839b683bfef9bfab026dfe33c9db24986e25809e04fa71c41f896b48e8975d388a2efde48	1	0	\\x000000010000000000800003d3f029dd1292da0fbbcb3851041da9d0669c504929a662a55bfec06573b346c0ad05887f24cd085d49e34035ebd5e951c220298e25d4a8da9ed4aa2b007159c3a68cb8e512967cdd177d5a1e03268fcfcde30a62e7dc197fbeb8fe4925e522716b549d139f518feaac4f071ba3d5c4c705c35e481c7708fb1230be3ea8d248bf010001	\\xfc7aef5b3210e0384ee39c6190f52c312e8bc0401025938345bd57e3a7e0a64f1ca080edb55e0d77a26b1e9aba712c76cc15e5ed3499baadf87df5b2e787cb04	1653653117000000	1654257917000000	1717329917000000	1811937917000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
366	\\x642bf268de92529a49d0fe2b1c9a2ce9e7af54ca071b13cb0b8cd5eb169cf5297652322fd4313586526f4e70207d206b649d9730435d9550106d9a9febe7cb12	1	0	\\x000000010000000000800003bed6261713672332acee79e6f4be8a229530baab12d6b071bb576d74e1c2e2e9644163adb59c20138e8c06fef2bcb9adf471edc96f0d0da9e8a569075f32781c140949a066a14224f230ac7046ecf004f0e197998756c14b7914e9d6de278b187ebb9844151a9e4c655861815c867bdd7adf5981a6fc14ed2af34db9fa525629010001	\\x3bd4959a52f2618ebb4445f05d3cd66ee9f97365b9392ddfdddde3f0a964fd114a3c88beb59edc152c9ddd5c09072ff14653ec0b0f3f47c3bc5175d2eb914308	1669370117000000	1669974917000000	1733046917000000	1827654917000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
367	\\x679f3574490a5712cd732daa453714a373d73d26f5bb64785ca83af66cdb97fe23a70a9ac05c28974396170d39439361c7224e2bce24e0e9a46230038e8034aa	1	0	\\x000000010000000000800003fb558ebd310832c235ab9ce93026a21f7e0b17a8411da396ef266af67fb58bf3b85014e9fb8d9b91d54f6b080f4051ea7b68c4132da0568a25263ecfadfce0b1492604bf647cd2b15a8a5ae3ca01b8a620649d72afd4ace2c64510318c43bdcb5bca431006f51712cea427104b7e5020d8967916a6119c0234e49790e1530bd1010001	\\xefa5989974b169983b1ef65321119e82e9333c592633370a7d6019ae793eefec313496a8a1639daac7e69d3c8787cd7e3adecdccdb10dec24691c9b174d8f503	1674206117000000	1674810917000000	1737882917000000	1832490917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
368	\\x6abbbba3b788d276d1b31377ed0b85babcf449b04a3aa48adc604471302d71e622ee79c4930d9177fd42da174e42b9f77e777072ded75402e8f03dce352d6451	1	0	\\x000000010000000000800003bf0c409c1cd50dd0fc4ae60b75c3917fa22c4583c9db001b305332a30bed16e3d4219bc5642a3edbc3c094a98148a19682858b669631c869365d57db2e37d855c85b885fc516ed3e50068c7c5493e9d8bcc4c5fd84bf2e26d9c43981d74816036812fcb3e1be6adc28dd4d17f28c60e68e75ab271dcbd9e2f376ac51f0bf8d13010001	\\x079131ddadfad48dccc1a6c19349af5f274b03f79d9b486a55b4422aa0d009c3fb078b0e4ee59ce7d70b021da4ace613ba092c38894a48382eb9b755ac8d1708	1672997117000000	1673601917000000	1736673917000000	1831281917000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
369	\\x6c2b55371fe999496b70d5ebdfe7fad110d3479667e2f9d8a225b65f80f244067043b7db0aaf4f936b4528f4f693ec91f6b36cdfb8eaebe0e172382d52f4a6ee	1	0	\\x000000010000000000800003c77d1da4b050d9548b6f873ff745947b2c4f45a2330ff7bd07de17c74317e9fb970b3853874beaa1a4a9f4ca6f358aec6e36f44a706540713f2377fd008465f1eb6ad9817403775c0d7aa76f3bbaec5481fe213eb0b7e28375d761d596f3400c7a8389a837fa081edbbd2534f67a42742d11b9bcaed0f4f6735aebff35519faf010001	\\x8b9d77059f77b28a06238c1ad1b62e368908bd6495fbd51d8de6b56a615a237b0c0e3bfc1fad7b3d063e7d131c60cf34935fdb25d752aaf6d44385e57956ca0f	1648817117000000	1649421917000000	1712493917000000	1807101917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
370	\\x703f2a3e85776df13107ed27d6f6a11274b87354449cd7c8e5871f379d7309e30256841054900ca44264317ef30938e70981319a50478a8250596ad5d2205948	1	0	\\x000000010000000000800003d6cd6b7a6b4822c43d64011a575b847c830fa07a50b5b37514f66f815b25c68663e08ef6caca40bc417636d01473611b768e27248f4e7eb091a3a777affc9f37b40a8082d90d3f6e0bb83279834c73bf9003cf30f8ada89fe427c54bb33be9bc361ce74556ad92703248b129ee6ac86730244f14d8bd96eadcb76c396a6d8c71010001	\\x34674a90d6de3cf8d0005909f593a849b13dfcf2b3afb79335f3b5142df64e8ea67f722ccad57f598d851853cc8e953fbc40a8c451b5cd63bf31e41529182909	1657280117000000	1657884917000000	1720956917000000	1815564917000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
371	\\x70ab0fc43824b898f8350bf9357849435b5aeea1d100aad5d690a0a833f985e4fff680ad4f41e7ec4be8e82e9f8416cd81c04ee9df64d3a3b2d64c7ea6c455fe	1	0	\\x000000010000000000800003dc332588ee70b7869533147b06c4fca13b84da5d8c01fea2d31bf650ca983c803ce5d68d658a4abfea593f4c2f2e22f452c580b2211460211455f5fb9b4b97334afc235ca26a476a5055fdc92459d8e16adba868d4e57632a499437b7ef71ae9ea640bee02887a0ca9adb0624a1282a20e8eb05f85b7f17d0e7a9b78f08b4427010001	\\x4ed7eb215e1b54f089e9a741d4b7a56ac7227a09713b1b3c7e113807a6b8bc141d0ca79070e8fb0f897851b218b6a2bf3136d1adb379fb3f2258a4e8d2bf2301	1679042117000000	1679646917000000	1742718917000000	1837326917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
372	\\x72c721a200dd7b48c4d81ac9c6fd6fbe78f77ff433ed3d1f04dde42bede0fd6fcae3723ff80547df92a836918c3cb916a7a8d42dfc2f0686bb47640b5ca9c924	1	0	\\x000000010000000000800003bbf72d072b9f74cfb22d332a37364f68ab7368331069e9151055a9964cd4bbe0508453f3683f087bd30e9a10aaae26847a64fefed6788a24a6453e43672d79949ecdbf443725f4371e7e71763bb5bf0bf0f4c5ddb35f16b57bc4849f1b3e179a60dc2392fff7afabfe7167ce247cb2adfeafa8595c89a18ac1a6e303677941e5010001	\\x82779fccf355a14ba113fd09afd74c252fb0ada6dd6cd52b65de30c213f6a9d42439dcb6fea863188d8b318b957c7c688a827cbd973371777dc445eaad9f8108	1660907117000000	1661511917000000	1724583917000000	1819191917000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
373	\\x74fb9e67a6925eec25daba997d56856ef82655586d9f4a61305ee8fb75466bda4b7dbe0cd5a7365a1bde66aa7688654254d02474ab4afa15aae94721cc36a697	1	0	\\x000000010000000000800003bf5363d1da1fd36c1d6064ec1ee7d4b52225df6cfe6de59f4232fe6b5c58861cf174ade9a928b3f92f078cdb25d8ae8e9fa905d207b27f320fc6b62b30456279197978e5cf9eddbb15b048a38c17d9ab4d2c12d5eaf5d63272e5153fde1044da15027339b58e3227301fafd3eb44223e1f07bc8598ee0c15b801b07797243989010001	\\xce96e97d7b12ac3e87cb5b9049ecf6a9bf14d293ecf5f38e9b3025a42fd2b93571e6674b1dbeb6d5ba81aea9453a9120c550273b61540e10f87607b282035a0f	1677228617000000	1677833417000000	1740905417000000	1835513417000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
374	\\x744fe8ed1493415d7674e96bc90e06210bf40c3870dc05967ead3d3ff1c3121509628e89da384d7328e5aa515a37a88e2b5a91506fc61d61bd022a684780a998	1	0	\\x000000010000000000800003f63ec4ce4e7438c6bb7562239cf59784796e1c185780978d18dbe624da6734757f3aeb923fbc049d008f987f932c871a0c81983aabe71dff4fd30308ab29ef4e9094b566ca826c864ee1198b40a55d843f2b41c008e4074ffe9cd3ad1b617d5cdc32d26eda937c5ba60ec2164b595f4cd6e7aafea03eacac18a35dbc5cc49869010001	\\x1b9fe517bcf38bde96ed437ab2a156b55af5fb4933030b1b3314a7c408af89e8b68875c5bb9c79c7b44f01b59ea913b3e774d48eda57ddf9baeaaaaa1aefd80c	1666347617000000	1666952417000000	1730024417000000	1824632417000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
375	\\x75230db9d0c912415672657bcc3dfcf3528ba05b5c45326786df1e6c5e1bceedb880a38a6f4748f64d8e9f94f9d67c260fad7caf5ba9e772303c231a86321f65	1	0	\\x000000010000000000800003be02f181965936f3627ad3258fbc74851a75e9aff03176c9520b5a976dd75f38d2f9141ee7847a312502338e95affd58e2e1919c9014bf18ecb347b99efd316a6a95dae6786b4a68dee26f64eeab9f6e02ad971d267b7a66028c33123e5d6ddced220f6f0344aa014941fb665db8aea7f75274a4cc80ad8dc9ff2aa6296f79ef010001	\\x6b5e1cd41045fe9c360fe0eccc152d4f76a14df6e5d50d126f771a90910d1c514e36f45144a1e5931e7e525304117cb98ee588c5fe6d462ed24dfbd9f7c1d709	1666347617000000	1666952417000000	1730024417000000	1824632417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
376	\\x75db588ae1a59d34421e6cd1509500472c33f4674cfed53576f979471694eea0e609b5b49ec5a51647d7fffa715ff6eb6b7b6a65a020aef8c8b4cf4346536da5	1	0	\\x000000010000000000800003c4fcd0a1070c4170fcaa91c5c14673cb7771b644ce9bbc120bf858baf4f12ac96e782ac1550dedf6f7695f50e1751a00366fff79acbb5ed90e6a0bcfe0d80261ac7c5be728927502dd2fedf0fa1eb9197e293645b051389a92b5a6eb61e3d74e3d58bb55f5a7c6d670f8c4f3d594d94acbf2930c0bb697ff8aef7db7972bbb79010001	\\xbe505a77e23916569b27a89997682bb49970187e76bb5a00f1daff806014c35daf3ac149009e1ad547e69941f1c8aac43e9480596269ec7161b830e846febb01	1655466617000000	1656071417000000	1719143417000000	1813751417000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
377	\\x7b1f963a2dd23a774efe1b7d10e8821000bcdf40caf54a9a55db18e06410b44c94a82340f97df46ffd8514c225feb33e4c326744a2b3a5f17922a6b9e1f17cf9	1	0	\\x000000010000000000800003ec64dec08dc98d573fc5153e837817577a14bccc9f0b93bbe1a240a41354bc97d99874bfda4641e10e4e4f2de1c646a4a9d4dba025624d3430cb320ab43d3e423c1e559e7d7f7f8eb3fb53b922948f4834c9056a74838f31ca5c3ef2a4e72595128475e2cd06db250847f9de5fe063a8d851fe142348b81d512b3a275dc12e85010001	\\x27bce42cb47e7f70fc8296691814ba4c0e6019cf2e4083b51ff360545888e2082cd31c265c5ceb88a36b63bd23f8529dbb0b6d3fc7953522255eb8803f24bb01	1653653117000000	1654257917000000	1717329917000000	1811937917000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
378	\\x80d36db7fd65f25b64df31dc982deb6ddc1cba5c3df05197199cf4d7c2ca5d11e6bfd3f77d8493ad9c11dd65ce3ea32c3e8b2607436cf81f62b000b6f2636fa1	1	0	\\x000000010000000000800003ad8b2f238ae6455d000bf7542bbdecddf5d8dbf0a4fa01653b8953b9f9ffa2e84eb90f907df095005202648dbc82bf93f4efbee8bd73a34dcea14037225caa16e300658640fa40b69163845af7f5ae35994a90ebffebcf00f9d7f99570777b6ef574461713f91c80a211b5a42d025a3714cddace4a672e831ee3589d891e1fe1010001	\\x183b279a3bd3299a8cd1358fcc2aa9867ff8efcb510ebbde2999efb95520f1a2373c1e37dff815e9bb644a583b88f4e3788b1f5b377df58eae4258f4228ad902	1651235117000000	1651839917000000	1714911917000000	1809519917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
379	\\x81d75723379d93beddc6dbad5ab726a159fd8e125e16a5fe57fc8cf8b10a89813c6195e28d86aba27d4965f7a83c9a3901c377e8da280cb619feec0f537edd52	1	0	\\x000000010000000000800003bde0c43178888836d87cbbfea8ad6e81b0a788d24e9fe891572daf2eb9287932cd44c8068cb676b6cb04f7c4035d3943692274bd156a97708014c23ba6a5a729154890b802ac9a5cf39a03bedbb638b0e4272dd213aee5bace35cf5e2f9a57b415a247ffb88400174c63fa384ad92d21fc3d59577f5d8a8f6b2fbb5b27ef4efd010001	\\x7f0e3579da6e33471985d9f08303f71b7a33a6a313752a9e12f95d633eb0304ac0cb7d6c5e00d57d296c096aff0e4638cabacdb025ec5fab4e4f8147560a1208	1661511617000000	1662116417000000	1725188417000000	1819796417000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
380	\\x82af1503ef976a538e2a0cf34310e48687133c0c9aa52051a196c187c5d0e352e6cd9712d4245b7e3a8f7002e058085e149c8e11d0aec7e5a762e342d4c23012	1	0	\\x000000010000000000800003a9efaab842285da17c44d4dec71b7302c1dcc512e3474af29ce6d2f0c5d2e45039c306d2552b6d292a22963870a157badb8a7ede5611c799cff9b613b3abcdacc8d12c77c64781e6264cb663a361c13f97ed57bd0fca8ee04c56d1a1fa03a65be829c899b696f5764cdc1021b12f591eb87ff44b358a00f896497e595cc6b935010001	\\x688874b52176ec6dc57f1d39e1d41780fd2bb4e5d3886cd386c34b5ba34923a1346bd0482fcb4093fc576d93a4d0af38318b8bb138682e83f674a1c176b5690d	1679646617000000	1680251417000000	1743323417000000	1837931417000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
381	\\x894bba7a3e05206f13393845d3007f262ca99ab12f03d1569c7180f3b0bf7cf7f8c1b94bd7ad3244368060c2ce73e376ba7d6adc48cb94a111c45079d303d354	1	0	\\x000000010000000000800003f68f8c68d0890f94ad05de89e5ee566ae35bfab2898057b13b0035f4f35c7aa14729f2b907c58336b64155bd512d6a3b24a6318765f613570576417e563f38ac0444f795a828851c051979f35d033587f31e1534958e1c343a1e4538b793530d44a8bb70dd1755babe32e7c2c14cb9dfe226aca5cfe20574ae1c089bf242395d010001	\\x84dc8b850a5fed9f284e82899e5c90b1cec679c000cc63ce39e1c25984753f97fade63072cccab8a6fcee7231d9e4cf1b837f33beacd6bf87a901a67614acd08	1671788117000000	1672392917000000	1735464917000000	1830072917000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
382	\\x895bb7e2e2097d058dcae10b75ba9a5d9d12074722c2205ad740f1b36a45c37b29230a786f174195b55f3237584daa0a57641fa4948ec690248c2a9513d924cf	1	0	\\x000000010000000000800003aa0bbce63352d3e7c276dfa3d7855f60aed6179690a52b865b0cabcf5b8c273393be45847891ab3726669fd00788a2e348b0c6b18a48899277ece9fa873c46643f4d943bf97b747bff9868a08e4996eea64dcc953ddaefbbae5430e2e3014f6b6e7459cec3786efa7b9d182c285fde3a6e7a5225b3700bc9f8cff747b3d1c5bf010001	\\x871f83f6524ebec169a58054840a2b3a0073a8b0079a31071bff3e914f21af3d6f45855fcd7d83cc7a016a9a3fcd9489651ba36e572ad295c7ca609b36f72908	1665138617000000	1665743417000000	1728815417000000	1823423417000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
383	\\x8be7e639dc0e8e6b737371b1dd9770b0197f39f268ed39aee7d78fa5a52e01f6dc60b0f275da417604abdbe5996152f573f8ccfd1d5cd2eb19594a4b45399dff	1	0	\\x000000010000000000800003b614831395b7312bc3ecd671dfa2cc547314558e236a9e8e44ebb64e7f46c60ecffd0a7b2f3826ed08344f10a440ade0dda7aed3050857f2e7b7649d288a8692c0637e4337fa552ff883bdb098625dd84ff73876538301660fd9a02fdebfe15b26a7975a85e168578e24bb100f338366ab7a49bfc541ffae0a3b7a17cd65bc25010001	\\xc457edd2af622f34cd65b595cd5593cfb058dff34597d540271be15e1d6c1e03a394cf506ad38e80364439eec75515cd7d9bbf13c078378e31d49d05f695a803	1674206117000000	1674810917000000	1737882917000000	1832490917000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
384	\\x94ff119c9de84f636b0c89dc6b4611b6ab296c54297e74156148622bc05b30cd065be7820ebeb51251f199b1265d859bf97d7870d0e53eaed77348af7047d2f4	1	0	\\x000000010000000000800003def09e676266326120c3bd9d7cc4ba85df185cfbf58875ae8f13ac9fcb41ca793cfc5ce6b5defc940a2f242d3f4855bcdd68f3eb24c1619745159f5245678ee8216e0fd100e6931616b7108e715a7d179aa6c9a8604a0f16f8c9ee31dbd04faae1b9a2456dd63d2a220fc2d3f4b6ae5dcefe72da226a31e408e27584178c7a6d010001	\\xe8bbda930615fe65222f04af283017f1e11b774f13c35f9bb4bafdce619032df920343664616feb79449880e18c31f8db8ac6180278fdce8773d693dcac52a08	1659093617000000	1659698417000000	1722770417000000	1817378417000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
385	\\x99d78ec163187e2adf601cc6be598ef7852e183f71710d867132370a001eefe577e62fb210f433ad4d231e1f73275c5be33501695377e418dc6cdc08a704f6f4	1	0	\\x000000010000000000800003d66f89d956f4a25b7d17f7ce529fe7374ac3e1817ab793aee24d73ea67b4edd07b5e89105335cd893e9f7b826132e2f209140297e807cb564fe6a3cf867f5d497b7cda9a905e1233967b70847cbaa508a44fc0e0aaf08374d58714c0e61cf2229a177df45d509215efa2bd0346e4e687b7c1d742b6d33e10d7dbcf53ac612029010001	\\x0786d69af23ca626c80b5873bc0e0caa9606a7dd5df75f0392e680fe4d8dd5316166a7fa2b156d1ea47ad68a9b1841c095738235bab7da5e53d0f6b397fc9204	1664534117000000	1665138917000000	1728210917000000	1822818917000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
386	\\x9b0b986006e6d22e8607e6dfc8ea31906595e0aad5d9f7f80e78f06066142ad0c13f8c8e62c6060dbddf8dc8905d5b65051ab661e90e338861764ded1a40e509	1	0	\\x000000010000000000800003ebdededeb0d330f6d3d6afbf7cacb9082d152a6406d9c642337fda0a93c9c4743210a5873ce4fb290b496eb198768e18642e109be95811abe7830bab8c8c88b5c4da834aeb3782af12379bf3f621e7ad6cf44da2cb701c82771816e4477d701d7845ebb28fe4e8acb401ecc0b613eac8ecaa07e96e79a3d88d956352ac7e0b6f010001	\\x87550ef45f52d514e5714e233187a1e297033fa69d31dc75a7f3906b7cfa0ba6de29cd4c28216bb5d4dcca414f5485655be0f19cfe3fa5ea6e8d26f2b8e23d0b	1665138617000000	1665743417000000	1728815417000000	1823423417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
387	\\x9d6376d32f3c19d0a09c260686d2cdfac661d0a0af58fc647e5c0451c58c6eee6dfd44bff678943a77cc7dd375a94c5d57bc41509bfd282b9ab1a1aff7e6334c	1	0	\\x000000010000000000800003c9247d3c41321d9c228205cc2e7d08271d4934b5ce009fbb85f5bf8e4f71c2db6892d68651fd66e72fea3c99ee5fb537b435c868d7a7c8648045ec63aadc577757c4d43fd59570064489fb9ff6d4c82c2f8fa595d23b5e66339c33853c437abd59b7dcbd92e8fd347e47769124cf04469ae75f0b8bd5a3bbd8fe773c4321ff57010001	\\xfc2e3e7e5d4dd2e15e49c8c9605421d3cc8a12fe71f9d8b334eeb15e3671269510ef34f4d7233c759dad1443e4f08d78c63d0ebcec8718b095f0ae64614d6e09	1674206117000000	1674810917000000	1737882917000000	1832490917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
388	\\x9efb9eeaee7c91f147c312f3cec00dc07b86f7cb74456016eef00822ab5ce70a92cfc21d84285ade8628b5cfc97b2c8277a3061dc6411be75b16c279aa6dd400	1	0	\\x000000010000000000800003b105bf4f5f9ec967eda167183449d4e3d6d8e1e379a25a89454d228f864237d4215fec459ba417e77b93ebaacffb966863de74359c97dfdeda39c2bd73497c6fe349e56893a913642c5ddafa7ce399947aa192fd4239d5008ab534eded14f5dddaabf00337afb42b673dd6ed494395198957d64d854c8d55d2274d687bafb455010001	\\xd609543836d189d0a88ea1a5b68539c7a86ad362cd78472d8e5239da6bdf66e9b0e814bb7e88334f5d33fff52080df59d3ae19a0d99748a13a4439f8803f050b	1674810617000000	1675415417000000	1738487417000000	1833095417000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
389	\\xa3cf5f2ed2f04a467097e8df01457aa714a7d768cb61d05ec2f995f49fc00b578ff6053ba6d587c54c47bfcb14649a2baebfbfa4f439a1c6e0d6bb92c57958a9	1	0	\\x000000010000000000800003c34a0401b30b54cc9654f2b979a1ca2ff2e6580d589cfd5b3a498f26035e2511a7475fa1c6f2d6cbf997a47949895d7f74c37f1662a7c2b065ccfcc7fe2367569083331abbb74ca1cf37291e6a023803c216e77df5936acfcbd2e8e0ca7ea60c6cb871486affb61411732ef7a48cd2771ec2a38ecf1693fc5f2b6b189755fa2d010001	\\x62ec94eaf4247b24147df91918cafcb98a135bad534ad92235cfeca6d47c7ef95975c83b29c0fb11ac9f6a67cf389f85f1e0d3dc35027ccdc7741a029df3a103	1657280117000000	1657884917000000	1720956917000000	1815564917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
390	\\xa60738061b3cd69b18cc32157eda94cd2666262a0d4765feb073c5525ef23ceff4409c42495697c4101cbdfdf966ddd1ea0ad56b17458565e053a9757d21813b	1	0	\\x000000010000000000800003dbe531d4f839499f334e892b9ec33feae965486c09faea77e40514eede95a79c44062633cf123646f74b589024dd47ba6bfcbcfa1d551c66c95d1d1589a0bc853a0617071bdf22c1c74368820e77196a615c4a63e49353b89f7ff616d0dc104127498b5871d6daa4fe2e4dd4e8505be6af2155209bf810cfa74e779bab915303010001	\\x7d32683bc9221872eb76f0ecdfb1ccccc8299511f8289375ddf4e4378a9b6791272072434d38debd58cfa981b27b7d3bc0475f4462975392274e6118e62fbe03	1656675617000000	1657280417000000	1720352417000000	1814960417000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
391	\\xad27e0606472a08aded52a6ff37dd42cafe6a2f278a215bb914aeb663d08693a9590ba2ce6b4b7a66d52373100f8b77a4bb8c916856c43fab28b17f405faa9a6	1	0	\\x000000010000000000800003d245a482c5704ca7a59444928b995f40f210c107a599d1a91f47ff235c6f32c33b8ee4fdf96046c0176030cfaaa6cf4ba24532a6333d64de0aa0336263dcfb7560bd5ca0402e909bceab0e355ccaa6eaf3ce4b4c949affec8ad91bd0cc8ed1ecdab12ba8c9fcc9c082cff0705fe1c2a76bddc33debb54c367934e2b4c22c2bf3010001	\\xab0c3a6c2e54febf1be236773e1f035e11b1c7476149618db691b24b49723e98ddcfa97d36c5bbcd7c3eb86c24e1b4f5df96f3a196c022896fc5173ecf2d950e	1653048617000000	1653653417000000	1716725417000000	1811333417000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
392	\\xad83a589f6a223a7dbd81bbedff64ce09ca2d7641f399a21d3503560e7ef7b7348526c6173d7fccc8dfae56abcca29aa72f48b5fcccc133ec7ee8206226a1db2	1	0	\\x000000010000000000800003bd178db2ae33ba40357b1e005f2774e350fbcc390685db1f6217db994c758c743635523edff49a485e5169224063c6dbdf69e981b59e681b4311fd52599883fb4b90bf1c79e44aeeee841ecebf47d899b84177d25e524d70461fbc8f1ec3f167876e20201b3277bba9ac4046338ee700e56cc619fed108f95fc7c257bc021557010001	\\x1c8acf9c1532cf18b0cfb0f6ed08e5d71559dd074c515633c02ff1a6bbfd002d32aa555a2ef092eb3a9d368ea75a222f976371d1848684ff5d6f221b440c980c	1673601617000000	1674206417000000	1737278417000000	1831886417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
393	\\xb283e1fc7a5336f5e1aeec0d024ecd854eb08b555c8ce4329f01c6646c517c7cc27f6bf977b4b3b84982837d83d45917daf1129124c65528741738bf4fabe1f8	1	0	\\x000000010000000000800003c0a057e84203362719d3c8dbfd28ae321603aaeececb70744b9296ed68589f3e90348f4860a07b079d676afc82fcbae94c4e82c7d8753071c7e1c8585087900448953e93f70808793c13908dd7954e0911b8f4624a95647d2c9117d82f626d20946e8e265d9a4767e27031d039a479e4a76ad15f748f46a25d0dcf1e5825b4bf010001	\\x7324350feea1a5367f9586f1c14f09b0c51cc57b707cf06471dd120583026384de06a0ab576d6b3110d4df2b5932e42dd46399b935d9fe7ec090ac9e48cca70f	1669370117000000	1669974917000000	1733046917000000	1827654917000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
394	\\xbc5bb8277f84ce95adb6ac00cf5c77a4eb1af5e88095fc57f7e8c225e1a9239ee35d19de45985b4be5d930b6e38a30bfe4bcc0191ed5599f325ce899414290d4	1	0	\\x000000010000000000800003b9bd5712f953de9fa66faa94fe9f3c93aae24aac85847f03d5dee06ef675793a773e16d7d7f5f2bacb94f221d30a22ffe2afd1e794bd0f99804dd30b6a6a0e09771475dfdc6fc92365589b29506550f7a812ff45e309477b0a8b286ef9dba3b5975ef3f10cb1a32d20b16c04716f25089bf78a7706717dd4c9ea5e006b5eed5b010001	\\xfdee1d7e56d13fa56fe09822ad1ac3beb8b845aaf23ab4e908d0b7693bcd532d11b4cdcc0fbff2dbd7094497a86baf8b69ccf66c568e2107f66ccfd273f92706	1650630617000000	1651235417000000	1714307417000000	1808915417000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
395	\\xbd3f433e3916d9976000336475116cae626eab465da601b65f5dfd364521bd6dc9039c5b30252aa885744ce7f3549e2fb506961914b50300aca1582ba4504256	1	0	\\x000000010000000000800003af96e6979e8acffa7018661495de6b3be61a61ec131275fa7ba011e9d388ca3d24074be2c75fdaecf6bfc563fcb4920d7301f71a0c5dd12d0a3c25f67adf577569063f1358a285dbc1d45ff2ed26580d9c3a20842f8cd865a9ac86e1a7b2ae2abd5d5b3c433796b0027c04f57cf6a8d2d719bc40b0d94d0d998979ce3c0c5535010001	\\xa657da2294bb78bbb8c448ae6a79c4b385e135d129ff70d52f86d267019092a138f0d9e83e6fc9ea376b09a2152320f512983c090036ef7195b816eb8c4eea0f	1675415117000000	1676019917000000	1739091917000000	1833699917000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
396	\\xc2cb66594fe6b682944454007b6442db5af6f5549cb293e67d59333407ad1e35e688ee8bf621aa833be7d1564d906a07bec4c3299f53d9c1639fb8f5e5517182	1	0	\\x000000010000000000800003c4a98bf3fdefd320c48df0886c0f670dfc4274982aba130995aee1476785c076336f65038bf89317736a45d67b10d68c6ac6f27498d2289883b7152b36e2d113e618d95439bf79ac9fec4fd23a88b8f306712151c1353fe6e24ba7f4a86b6951231238427c7905a3c7e689e5b9671dafacd3b72dda0895316653a7fb66d2c223010001	\\xc7cb49463f947954c83ab7a656ca3582fb71db9a4461cd1cc6aed0ee5e0fb8a403fa8904e2fd4224b5de7f0426d4c67c76f3481ccdcec3136ebf78eecf586903	1676624117000000	1677228917000000	1740300917000000	1834908917000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
397	\\xc5a71f85de8a2be38dfa917a9f8bda27043aef93b1fe02c1e508470c3a178e7af2146a738088f47f9b3f8aa539119b323ac274b96765734e4466933084b2ebc2	1	0	\\x000000010000000000800003b812dc30e2ee43cf7129090bc20cb8bff5cea33764d07a822e55303206788de43053d0c0b07b2e29085ffe9041caec2cfa45a90f3e5fa6d77ea8e090138f83fb3f1458f1476c578d0c0cd058adaace3d4c48048a5a6736ffdd007a0123b32d933e0d3d66c52ca2caa0cd1e184a7370e8358f7a8c3ff3e3c7d13b3d0d4429d0c1010001	\\x5a4bcda7801bc690b517792e8a08fb4340a23d3628ac3e05123992035c3e53b4c40a3ab29d618b56f271f9106e8576490e158f583c87f1d36a39d5a1ec69f60e	1652444117000000	1653048917000000	1716120917000000	1810728917000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
398	\\xc62f7d1bf7a0bc5aa284c9ba4407a6071429f7e5ed27790d7ab77118a3d428e90a87cd0af22bc07a98da744b9ee2f801502ee3b2f9d8304af9d902ebec863571	1	0	\\x000000010000000000800003a6bb6aad835473a5cf7fca2fb875824dbe37f429a2d75034dfaa14247b270cf98397937e2b7f497152fa486f01c5ef0b455eb0b4ac9b34557e92a42e5676d40fe5670cd16b9a59f401a961004ae7a8556ea32593af597ffb38919f51a02c35a9f4f8143b9855aa3b5031566b11d5302effd60f01850996eafac980742dcf8e9f010001	\\xecb03b3662e3ea05f965150e997218f5f62f8e5992ad2071f69d508902f0a76e47be47a6bef9ce99106ebbc6fc042d9f9e83da2115f67b1765ec16c316234701	1670579117000000	1671183917000000	1734255917000000	1828863917000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
399	\\xcb97c762a02cfd392fd2e24f2827bf1558ae5dadc5ec721faed7a63c8531a81b00d8d7e32981837431b9b52d3165f7394fe4b07215400aaa8c2a0d971fc8574e	1	0	\\x000000010000000000800003b4caad7dc0b6d075720449e3ebd32fec53106464abb287705888ded31c01e99e77ab6d4fd3178107043e4dba7bf603b2d11a9ccc10edfb72d6b4fd7abcde6fc427b17c319652fa8dfdfbab3f625abce7ed192fc49856118cc4f80b8c18b8bd0b233432b7fa17f6426e3548741ce9342cffaaf5811915a0dd3b817aea109efaab010001	\\x3dd348d066e75c941bb4876fd9c3f21fbfa0c7da25fdc1b5732f46d1611a9ff968acc4cfe5b2a366a82ed668e34579271b73ea7a59fc2841bf86a5e5d246630b	1670579117000000	1671183917000000	1734255917000000	1828863917000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
400	\\xcdf3dbad9291d4a68f090af8d702c7860ae4ea1e7d8298ede93ab6b82333b32a042765a388961abdc4cf4b4dc0fa7f35eb9e354345623f6a3b761a84acf6413e	1	0	\\x0000000100000000008000039f1edc2a568efb99ddd6cd6dfcaf9fe98224bd2543b3f834e890888d4a8d2b670d94490950aa9ec444268391770aef30341be8d6d8d3b5e3582b4d2f08bf778d2a30d2a983ddf4d77ea28c8570eff9777c4d5df8e4f9d6b0b1df0ecb3aa2c1e7a406391e00d2fccdc17dfbd5b301efce28b7f668f9aa55ad547238924107d509010001	\\x8e36b4cf43688f9e6104828b34b2a874f981729a7a51a9c32b3c3aee98f165b4f73ed652bae34fb1a9ba04d015ab47c43fa0ea206241094bd150078fbae93200	1655466617000000	1656071417000000	1719143417000000	1813751417000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
401	\\xcebfba04d071d85704cf1b5261f3df52ce2b62cf8a10943a32ee3be0a15ea6bad4fc939e98d3049f6253b87a67f6d41c7959f59c5fd23b9bc82cce2ad732fcb7	1	0	\\x000000010000000000800003a26085c3b2a98c425099413d9b348bd00970891edfc2300854bf4004a3c89726672c907635c9c8c98cddf7b3abb87bba7805bd9b030dd42fb79af57930da6d7a966b105dd2d16ebf87f84cabcd54619ab7677fab6a27f0f96e0aca64d8b369e48798d4fe6ba314bd2573d52d559cec485fecf207be6149fd105370470b606805010001	\\xf7778a570f87cf27715f2f25ef234fcdcbafba26f48bf116de10a2b937e45dbcb66c0436ebe5ab2ea8429403d6ead26fb4e5bf459a8746ef699c4b7835a9e60c	1669370117000000	1669974917000000	1733046917000000	1827654917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
402	\\xce87b200faf5f840049903e85bb03be0ca9e4ba64be6189ba56a05d55381cc69b0ca4af4baa95f8362f76821ccc3a1d8adeca91988610def52f5a92f1f87ae43	1	0	\\x000000010000000000800003ab0632fb6c5fdcddfc12dd80acd44dcc08ab9f4182168bf05c633b3469b375f85aa80e028a6859a854d226baae364ff447c4805690c5ad70d23a39ce60af642b618ea48734c1d70472f87630f2f6d8e4476e6e6d0e48393a7ce5952d3e1972ad49c8e9dfde7c5bf76105287ece60e5d3fa2a555129ebf8b9b6fe389ba1edcc19010001	\\x4a6b05bc1e4015b020dde8230c789548ceefc624704cdb018e5b92fe57990865400706f00956feb3da51662364f66bf1d41d388c27cd583bd7ba605a1ace9002	1668161117000000	1668765917000000	1731837917000000	1826445917000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
403	\\xd1af0ffd25b4a73a1903293ef12f918c663b537a35fa18cfb625b5fc992fc6ec6cd4d13eb9947f12270b5afcc3002aaed1fe6d74069ece715288913dfdaf9580	1	0	\\x000000010000000000800003bfd0b613b077f8f7dec7f54a5d8ad7f54a0504c1822241c77ed94ba6e1aa38dc0d666611d233b6a1520988272e84fbcee1d4d711ac57389fe219adba4d42c751d6a3e81a785b32443db9d28493d1ab08f5615abe9123c63ed632297e8c0c895108edb317d7c2b35d7b28adab6141e12d5154d0da6876228f3e0caf0786baf163010001	\\xba5b0792ed9c4fa90129d0e63255366ce070f986f9284869a18cf3bd4d756398b32362965449a06bc333b4d258947b5de50e5c9bd98d4b42a6e78248215ccc06	1660302617000000	1660907417000000	1723979417000000	1818587417000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
404	\\xd2fb9622f3bd9281dae902d3ec1f7a229be101d270d590eebe7e59455f7c0e21c91c9debb65ee6459c5cea10534dd471b43e985e0eac99a605c56b6c84767e6b	1	0	\\x000000010000000000800003eaf6614569b95e2df8140c58c82dda0ce1ecb1d96d81aa41c8ddcb04a007a203954fa80475361a87ea166f38c3e108f80f99c8233e4364fab3015faf4dc9e801e069967f227f09a8ea3caccb15000c5cad8d28210dcebbc3081e2c7d8ad3057fce54612d10b777b682d7b8e2085dcd5e690cc22af42770119b53d322d0a6e9a1010001	\\xb6ad66f7bf96d42d8584482035cb3605af85fa12109a3f5444cbebf48b0f55a6040843de8dc2a67886683612f25b38210cd477d278abb20cc4624a8d0d93ae05	1653048617000000	1653653417000000	1716725417000000	1811333417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
405	\\xd58bb6a9fc40e91521e0ac9d5713821f28bef75a166abe467a7fa8a328ca4f9c4d6ee83e7a134a992320dd22f270c7ffc1d7f66800537e4a5ab42a87f345283f	1	0	\\x000000010000000000800003a706c07cb1a4b9da1474f7d881d9af5609370392a5ed70be18486f317737f855af7533c7b4f6ef4109623f7e44d4580007e963b0e27cd0d4ccdfabe00cd3dea611470c0c7b67eba6ab5cac7a6f10a0ae6c9d8928629428631e4c55cff15358e5fae9999bab3f66a8bd20a2f66c7a2293b667024fabcb6e6d6a7958298b181ff7010001	\\xa5351bcfad12ab2f336c56e760053382764a5ca6cd60631c0ace752f462790b4cb411bd309db341dfecde60693315bfa19d0b0fcc9036067de10e6971a4de109	1663325117000000	1663929917000000	1727001917000000	1821609917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
406	\\xd777aabad5b2f37e54ebb11674784102052b15bd772b82b22347b3cd73dd95787a59bdd6b3993ca933b6dafbb8910fcbe99e0cf739107dd5b37426e6661c59fb	1	0	\\x000000010000000000800003f1814c7745525daab940638580e7093682e242eff77761d2661c3ed37599e2bd79d367b28efd1029be8c36b1251332443c7c9a8c2407aa8c3d4b1aaa0c39b43c3663080b7aa1285bf3cea123db6eda81896867d12d502d2ebfe7eed8b8c7053ecdc6028aa4937e1976e38b0f96bc5bab5e66a11e5247a985ff4a3b269a3249c9010001	\\x19cca46bf492fd27d45d2dc90374bb08ffee5bc303922fa311122563306523730b09932a04d618990eb7bf1a4f3e556b76bae7d3b4e46f35b6cae4804da00301	1648212617000000	1648817417000000	1711889417000000	1806497417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
407	\\xde1f2c592d15ab1eb7a80f582a04076a77879ea3f4e90ddca024d423f42d8b6c3bfdf92e7df2e296b819274b9490ca0d69250e057d4eafa9e682c91347c95ca6	1	0	\\x000000010000000000800003a88822fd6a903cc26a3b96ae2bf3e11ca33d4cdf67d72289104308b214234eb9fbd3fe63dbc74aa9fcd94aa13073c984b2432b87fe6ee06a84c8d8e4ef73daa6602ee00f1403dc2d4b46ab5945767c8bd35899670fd6c0468def00bad40c804a023f0f59bd1a46eb4e4d82194128216f8f543dac30a84d2266bac30f61fcbe85010001	\\xf055e9688cb36f4079e95977eff1a25611823cf74f6d85a6b56e717e52d22019ea63fbfc5297c87961c6aca2f7babc87215f860d63fa25c6b17c06255fa23204	1656071117000000	1656675917000000	1719747917000000	1814355917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
408	\\xe08368bd6771c6e5ea19a022ab47b562c607c4ae8495640088d337dd702d83942e8a813ecd8c64c8ca49eea21fb09227db8685c609987cf26fc3c7967388f4da	1	0	\\x000000010000000000800003c47eb3cf8af10d85c8b55e0167ec09dccb387ded16cbd75652bc80380eb1aa55fad225f6058ebedeecb83cb0b10668ab1acc08bc09766382c0f37160885eb723db4a6bcd53efe5a61262d9c4f384700aa53d10445a835eab5e32f8ba9e7832f6e96a26fbcf6daa663242aacd1a2c669e4e246c0b76f967a20257d17f1ba5e899010001	\\x9feffc7c7fe9f18f784226bb4bce56a1ad3b87889926389529e3d0bf0307e496caac8275d4e704af1472cfac1342e4c402aad5af6c964c4e9640a0d0e174bf0e	1656071117000000	1656675917000000	1719747917000000	1814355917000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
409	\\xe10b645362f1dfaa7fee86fc50d3a91cda0e98679ca392719a54f8eccca9d691bb386fd5b301e3464b61005ea9a7fe1897e36859d9873ff6b06f60c8f847b60d	1	0	\\x000000010000000000800003c1592ae5136471469a22dc73bf7da6ca20620fb8f89b6b05d6ad6202dcc2494d1dbcd7c56298b87214ec2887432d1c2a230acf1ae1da4a80a1cdf8135439055dd626c0d68e3247ed67374db58709cad47f15ebd2c507b85883d1da1e48b24b39e26a97b09f3c0646ed0ca67f35df4012e180ddb4455bdcb0137f721cb16b1169010001	\\x7401a9553ac98eeec14de52dbad3c70a60c738fffbc3d2b4fae2ae81919460863ce942abfd4d7b6cf5d38157c11344a03d3603bed2ff1f94f0ad65602f88ce0d	1663929617000000	1664534417000000	1727606417000000	1822214417000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
410	\\xe23fb9244e9f5a767c4d3febc7e2ed2e5064ab95e60f3201511e5b03a45cb111ef9063cb934f18b0e17b792235a61f72aee5db663caf47d186224be5a88ceaeb	1	0	\\x000000010000000000800003c2a65b22ddf229a105f844d8f03e1674a1da3bafda3b3b0fd34aaa3938178a20cdcc09cc80d6fbc2c5a0cd8399bfd4e3e060e4d1bfec2f933d7a855b092883e98215ad90118393d462d33f0eff2ce4e168e49a9850529126e46363a32c08d1e967de74a362f3709c711a3b16a225357db9f2613ccbbc3ab7a169e1568154c2d9010001	\\xa7202882ffe13ea2ed6a88a880f96210f2ad7255ed965a9066a96acbaf4ae1a5141b192e5d76ed27c450539fc7957c6c8f226f3556e2e845c5eb765b112ecf08	1656675617000000	1657280417000000	1720352417000000	1814960417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
411	\\xe51bae68ce70857e654ed46f2545fbb5c2d8294f572380b90ac8a328de6c756c0aa7ded3c51d611ce28f12fee11541d6702d3d48084c9430378a121b98a0b2ff	1	0	\\x000000010000000000800003d79bc35ae123b6d435fed631bc06b7b24135d57148455030a1ebf41676e2c910e41a8d76618a073b4fc49be46e99fdfee8126e5bcd4cf319a77c035a670123b88162338288bf976c8a03c35b8b920fece03bc3bc1c17b13fd3e9f61215e5266a07635ac1877108e441a75ac07a1fea35b632f0ce46946ce2b9c8ac1c96cb7363010001	\\x6ca868b7455741a36994c371bb79ac6b2d3da6feabd04417a3923374a5da1350e4fb889ca96c223b7277cf8d8fa92f72bf381d3fa74ecb5070119e3d5c68c30d	1674810617000000	1675415417000000	1738487417000000	1833095417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
412	\\xe607bb2a17a2850d5316ec67cc6662b5a568c6f18a4e15ec544147eee26fb6110e4a57cb03eabf84ee9afe0d1d3704e9520b4f9cc131f7a61cf424e5f319cddf	1	0	\\x000000010000000000800003abb726d37297ca6ae483e9602177d22bbc89d42fd743b9a376ba867832460c2400fe985fd26e389ee30f0b3e4fcdc6e4d3004ed46f9c0426d61f574fd12562269f0e06881413a591f35dc4c9c92d0135bccc97dd59fbb37d9c4944adc43e686d4ae39ddd75b319895881527d5c516472e3f0702fe261a0aa8d44b8f2f1c192e5010001	\\x32149df78461105666a3d5fabd3a4a681e197319c2eaf3f7653126c0d59c9663fbd8bcca0b4dbe6b131844d8263b1591b6ccc27b716ce2fbaf8334275a98570f	1662720617000000	1663325417000000	1726397417000000	1821005417000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
413	\\xe83f70cd7bc44f0d08043f118d5b9487c9797dba93774291764456819badcf823a9097716dff22c1ec86bf8a252b69932c8a3a75d5c3fdedc26192f8e4cd11f2	1	0	\\x000000010000000000800003e2a6e2bcf4d9d86e621ecb068a07b929bb51201464a0f75e92b5b5a6625d10cb7a57090964a477193d0e88766ada152d4b60b466cbabfa8ca41a2783ad76cdb5804c498eb675b86156c272f6c50c2dbb800b5e87f363c26cd35e20386750809145e8d5ea6d77b827de6f9d6e44ff329c2000bde5f44ecf3395e0984831724e15010001	\\x4b09acc6e47fd116700ea2aef772ee652473c46420f8c68790ae1f3466982f6a8326f4d92b47448aac264dc6930163c6bc36cbfb1bc9bf27ec3aaa0935808d09	1660907117000000	1661511917000000	1724583917000000	1819191917000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
414	\\xebd3f1d9643bc9566e187a8472ca6c8d68b7da7b2df6249c652b178319f3b1547af4eef8d20e3710447cb829c204520e6d7fa9a2cc2012e6a2a138a165f06e2c	1	0	\\x000000010000000000800003e1813e2f233b3a691d42fe1092432e2ef39651e353df0842340332eb1d93f2120633a17146909cc14fda58489ffe878df3026348575b92618e1fe55af4fe7ae15be02b9ca8d92d21348d2f06b9c23f4cc7cb1f0184f15eed5a4b9c39f5e4b75332fffcbe0f15928fee3cbe3b7d17215a22df91a157adae0064d301309274ad99010001	\\x48694b05565d2e09bd72fc92b351bea03abe83bed1383d37167aca6271ba632d0c32a274ead3b04fe3ae4cf6f8a55bac87b44640ad84152a0d7cb5b0b2b9d30a	1676624117000000	1677228917000000	1740300917000000	1834908917000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
415	\\xee1b20b47519a6c5a83b0dc950aca7aefada6ece6201471a302985b577170302ecb40ea141e3b1aab1436f4ff5b5ff115a9c07add94b5318c7d35512d24d9479	1	0	\\x000000010000000000800003c52b5cec20fb0935ce16a57bb546fa57718fbd80bdda34acaea3ca3ed4067d7a1f960b0fbbcf02d8e6a7f2346d6dfde2968a53b5d32e27a0fc5098f73a3ce2164521f685fae533be8b920d5437ab114a552ea7b32b8c8e0daf87d6acc94d8fd3630f7b0c73c1049068bb9a69c512fe299c61d1172ed06091abc0fe586c031d9f010001	\\x0cb2b8c6395b51235e2acd6723a5556f2a89a799170b4442c408f2d86054d17c6df4fcfa6408fbbef72e175068669dcfe2560a56673db77efab7150a2988f305	1662116117000000	1662720917000000	1725792917000000	1820400917000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
416	\\xf2c3e98c1b6dff6309dd359707165bd07ec6518b3e06b68f6a3cc987f285da0e153e219f58991b71920b89aea285c36cb6630f51831fc8b72068af1bc3eb2f8b	1	0	\\x0000000100000000008000039c190c82210a72e3b555abba18fd15c266728d4335e069208de7a245dc2ec3d5d4803ba2b6817ef7e16f900b6c1f24c5ad0d9d6f2f635ec3d4fbc9a90a01d18302a2512c3cde4f07c5f0633bfd3b9eeb1be4f41e567fc6db118b3de5d0f09e98db4f829e5bf36043e7de90c9ceb478dbb66a86b1081967a99d7af9662f3e7f39010001	\\x5480540d4593204295a99fb129bdc8ebfc284a76e2317435ef7930a0e457b0e0fa5a3e33c9d46fe0c55325c33ba9beb2ffafd0b5a549fbbb7593e7866cbf8500	1661511617000000	1662116417000000	1725188417000000	1819796417000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
417	\\xf3c3c4f562ca33400a8b384d15debcd23d493038b68178ca9ba05166d3640b448e39efc277fc24d0b655d9aec5facbb021ea91f784bb40bfc7934e87518d7228	1	0	\\x000000010000000000800003c67722b90d02b6d8905948db93de94c6c0bdda494688578e32b253dc23b09410e96a9d758259b508cab9fe4928eb36dfca2dc38ab46f4b5bdc156ec6150cebd7ee311b043bda3ffb2d8579d6cdf109ac047f013ee0d38fd90db1cac764c0da02594cf6c1eca498bafb520e18ca9c903554ec55665ec90f599a98acf0e0e06e19010001	\\xf7efcf961fd0778e970811f0fc12ca86197a54d235dba5f51a61fbab9d4856c4ad17397cec9ad4a9552bc8774c4b99c34ff556b62ea899c8cbacd5a3de625906	1650630617000000	1651235417000000	1714307417000000	1808915417000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
418	\\xf6bf02b98bbe8efa6e8096de8381baa0ffb85f5629176d3931c1e8f22e3cdac6159100dfe1d78eb994e1c8fc017edfd2572aca9c91aa749c9b57f255baca4b87	1	0	\\x000000010000000000800003d579df9ff3e67daafdc4503c163fee601d036a89b7102443d44ffedaa487d76c7a9ee4677922368b43962c44eb993cba05f36403ed8cfb037e82d02bcb1f4d3d286a71aa56a567f3fe6002db47d59f10039d4dadd6df11cf2c7cba4b40e692e3c57f81a293bcd059cf31bc1f5ed80b14db87e526ff205261ec6b8750cdbb7b01010001	\\x58d743a0936f7d49738ee703aad7d9c2d19e0f79584f08fc89f1dcaa59ddc3b9fc79c9f7b74c92addbc99687c2ee2b3042d42ec70fb2b2fa58c70544be120a05	1660302617000000	1660907417000000	1723979417000000	1818587417000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
419	\\xf77f1d112b1df13ed343cbca1d7847eec047001d63b0b8c58e02cfc19056f1bff35adbea044405b65bf0a4ebf7f96e2a1a76752d7d59d8c06d912c7735fced8f	1	0	\\x000000010000000000800003cd2858982d3dea4d41275fa1dd72e3860927493de6469f8beab03504c5f830dc195de023148e196b25eff20be6fbc48d9fdc91b49dd82a6c499db76c330cfa36297f6678a92e80e5115e92a9f7e4dcb288b978445db9e1fdb61530c8b328599799018bda4bb939eae939bca9e940d5b064bc824e6325816e000af3d0f7fa5bdb010001	\\xa86b9c9c033b8ec8982b4f370049ba9a5ce8d456aa0ea224a55993c38ae95f3eb5e5773a9762372cffd2cc3c7af87366c4f96fb94127bff28aa727656aadb90a	1656675617000000	1657280417000000	1720352417000000	1814960417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
420	\\xfc9fa0bcea628bac57e5d381a55b4254508b3f5bcf2ec5ba37d91c49a0013cc082003a43b4035301e829f9f93c71ccb934929a6e5ad2ca290b312c515f42206c	1	0	\\x000000010000000000800003affad66fa4c95b47853120c91f65878179f7186fc4c499eeb593ae60f437d4b52df9d786ebb2091c19181cc6cdf93c943a89a904679c179d4bd6ea25db0b7ef876734582c712bcc2625210e488732c820a6522531b386ce94e5ec7c191d1102817ac9ffdea86f65a7df0458e7e3f05e5918468a7515f2808bd27b33691bc7715010001	\\x560e4542b67d9d75c7deb9744b70f8b9e2f54982b426869ae82ba2814e866237f2ebab1d33812bc68cef304f91729287d514538f80361e1422e2fb0c487d200a	1679646617000000	1680251417000000	1743323417000000	1837931417000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
421	\\xfcbf538f9fba76c45c80b3dd51de38a229509798a964654e0f01b4ad8c66894ef8b6326e36a502adf2023f1e970a0a9bc3c251faaf9d7c1fad1a4d92aef9c2b3	1	0	\\x000000010000000000800003d6c292140c567e16055334d317f9870e6583f65fc896b066efe459ed32eca815b465c85fb7a3f1b20255a079382689b71613129fa347b61747b319eb0c58c84e3a20cff3d832d60be3425fea302724ae4a34aa04727c90079f7708c7573ba7a6a71c6e3e3a66c95a8a2ea925f3c06973933072deb3178cbe6c15d8ccfc6f29f1010001	\\xe7799136c4790c51f1d20482d15a69a79424a7d0ae937ac1a41ceb75ccfd0cc7e88a7a2a137d6c0c27b1b29ecd259adae110774c35d149da658d340396f1b408	1678437617000000	1679042417000000	1742114417000000	1836722417000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
422	\\xfdcbef44618da6049f51e954fdbcc6453a199a46eee19fe0b90e05b497855a2900ee18cf130afcd852094d617d7271f085a847bfefe33792d97a0f8b951c7128	1	0	\\x000000010000000000800003e0b7f1da694b26e2cc60c8003e71b44fdf9ffec79f38a3c8f5d78bdc6c03bc34e3e8ac4f33670e58879cac6b4e4a7b1f41fc850fef76a37d5aea660e8ba1e879e0adaa227245622a947a58328555e811945418970f03e79ea7cc21995ce402f3efdaaa99d9c4c762b5c65daec31116e0b72fe21f7527618bbbb5f5d836192675010001	\\xd74bf2947ae0d4d3d8b6a542d0fac811ff4200a0103cd0c0ca2d4dac272ca0014af781e39f17d287a840e1174c52222a218a5e68a7872c03230feffd124b350d	1652444117000000	1653048917000000	1716120917000000	1810728917000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
423	\\xfff75feb53690af489951bd9def8b37ac286a6699ffac23027c398e7ff84038cf89c147854c23b71e9ba5a1e6a7215a3e13b428d028cc8d848f65592eb398ade	1	0	\\x000000010000000000800003bd48f66ac484c6555e2256cd60a778e2e85ab0226d982df7332ecb152ef9f21868b7833d64e6f4388487d1e7118bc1ee4ebc6e3a6ed6ca227538b9b47e2d1cab437888b579754a57075e91a8f73a1eaaa5d7545e5c8403a30d755288bcda59489d465775f2e7ef514d07a5356da5473fdaaf77470231e745d5e2cfb159293b55010001	\\x9dfc26e1de1c318e267e614b7ecf02763781e1d9e518d591e73fe00819239b77d3841dad60270e252c7d78b91d4529a58d617d3436a76eab0f23a6e574f1ee00	1665743117000000	1666347917000000	1729419917000000	1824027917000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
424	\\xff1789eaf15f2b395372f02cc89d8cb701e5fb458e4f76063f2d8bc3c4c92c442f2fc53afdecfd8c50d18f60c08ba4ac790f16889f6c6911f6e5109ee88fcc3b	1	0	\\x000000010000000000800003cc546156820a9d1f97945075da50cd865877bec539a3fbe25fb8b2a6cf5c8e61451175b7adbe1224e91e47a36dbb67fd5518cc6c884b0fc3918e432d4e10ef2b52a0f98f4c58f31c7a36ec38348536228a05e9e22f9524a5f9864a833fc11f06e285bb57b59bb9b095b889c13c66afdc02c3f87ec166ea5ebaea3a8d2c474a33010001	\\xe128664dec78b937e90c88549aab4c12710757e936d89bdeb57b6aa72b12e2c284c3e2da6e14d9f0a209338a088453a753be292e125a77b0738c186ff422a70b	1654257617000000	1654862417000000	1717934417000000	1812542417000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x25d64024b99941e6dbd052faac3647296bdad019a88b69bf4b70d808e39f18c9	1	\\xf8d2c7b383961cb2999284c36464f478702c9b0d4719580229b901bebdbba6d588619dd45e72ded263b500a08881687db5771aeba960f3fca80bef394fbf778c	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x4f02d682eff453d2c4a371ca12e0eba699dcbc7ebd2182bd431450050e68aae2a3d3d339570e17ffbdfca065c02614f2abaa23c1b6f7f06ea84a9c84acfc6ed5	1648212650000000	1648213547000000	1648213547000000	0	98000000	\\x2b54c55e6666f9bc033caf50d363eeb041590a949195bc830715a5e9b5312006	\\x5775fe31de4f7240fc4ab7730bffe93440a08585aaf8f91ab2599a58cd1d8cd7	\\x9e1d4069e51e8908bd9d6f3302a8b691ffddda6ed9f0f486f6e7c6a00befbe0b4cb691c39efb678cb1f74c4f809270aaadde3a9885d97d2e5c01e96ba07c0c06	\\xbf61e2399960566564ff5dd97c8e6dbb3ef5e081242ff8ef6b23ea2e6e2fbaa6	\\x20202000000000000000000000000000641b71f9c07f0000000000000000000000000000000000002f37d88de0550000e0003b2ffe7f00004000000000000000
\\x25d64024b99941e6dbd052faac3647296bdad019a88b69bf4b70d808e39f18c9	2	\\x5d8b25abd7d62511b219b6c935d4da57c00be767bbade4334da5ac54de8244755f56ddde225f7e12b31766d14320f40eb1f18b26a9811cd863f7bb5adcfe7e75	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x4f02d682eff453d2c4a371ca12e0eba699dcbc7ebd2182bd431450050e68aae2a3d3d339570e17ffbdfca065c02614f2abaa23c1b6f7f06ea84a9c84acfc6ed5	1648817483000000	1648213579000000	1648213579000000	0	0	\\x097444bd5e8d03750413f74ac73d218901e1626ae503d80d1d12cf1dde64d632	\\x5775fe31de4f7240fc4ab7730bffe93440a08585aaf8f91ab2599a58cd1d8cd7	\\xf2e9a63bc6db5e0df46ebf1a6f4776c0d4005b951800cd8aa3babfdddedb3333d195b719c0555b65eea799126d3b6a06515451a133bfcd9cfbaa942d81310206	\\xbf61e2399960566564ff5dd97c8e6dbb3ef5e081242ff8ef6b23ea2e6e2fbaa6	\\xffffffffffffffff0000000000000000641b71f9c07f0000000000000000000000000000000000002f37d88de0550000e0003b2ffe7f00004000000000000000
\\x25d64024b99941e6dbd052faac3647296bdad019a88b69bf4b70d808e39f18c9	3	\\x5d8b25abd7d62511b219b6c935d4da57c00be767bbade4334da5ac54de8244755f56ddde225f7e12b31766d14320f40eb1f18b26a9811cd863f7bb5adcfe7e75	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x4f02d682eff453d2c4a371ca12e0eba699dcbc7ebd2182bd431450050e68aae2a3d3d339570e17ffbdfca065c02614f2abaa23c1b6f7f06ea84a9c84acfc6ed5	1648817483000000	1648213579000000	1648213579000000	0	0	\\x16cc29697891267d91ae49b1592cc83ef7d2a1901a18648e1fcfa42a3e7ac91f	\\x5775fe31de4f7240fc4ab7730bffe93440a08585aaf8f91ab2599a58cd1d8cd7	\\xb6f6d14ece9d33873bfeb4aab080805d58c59f16a36db80e7ed7103d8d5288a86555066548d1c70896790dd611bc67fcf8256d59496251808e8d361244c66808	\\xbf61e2399960566564ff5dd97c8e6dbb3ef5e081242ff8ef6b23ea2e6e2fbaa6	\\xffffffffffffffff0000000000000000641b71f9c07f0000000000000000000000000000000000002f37d88de0550000e0003b2ffe7f00004000000000000000
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1648213547000000	1859700393	\\x2b54c55e6666f9bc033caf50d363eeb041590a949195bc830715a5e9b5312006	1
1648213579000000	1859700393	\\x097444bd5e8d03750413f74ac73d218901e1626ae503d80d1d12cf1dde64d632	2
1648213579000000	1859700393	\\x16cc29697891267d91ae49b1592cc83ef7d2a1901a18648e1fcfa42a3e7ac91f	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, tiny, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	1859700393	\\x2b54c55e6666f9bc033caf50d363eeb041590a949195bc830715a5e9b5312006	2	1	0	1648212647000000	1648212650000000	1648213547000000	1648213547000000	\\x5775fe31de4f7240fc4ab7730bffe93440a08585aaf8f91ab2599a58cd1d8cd7	\\xf8d2c7b383961cb2999284c36464f478702c9b0d4719580229b901bebdbba6d588619dd45e72ded263b500a08881687db5771aeba960f3fca80bef394fbf778c	\\x7071c15b9a5fcc4998f4a3409a9e2ed8fff2b660e80c1b7418017834fb73deab37cc0b90e4f9f20f754152500a8c235fad3bc169c4aefc4c498d280b18174409	\\x672f8134dc265e4ff61bebe87f236b6c	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
2	1859700393	\\x097444bd5e8d03750413f74ac73d218901e1626ae503d80d1d12cf1dde64d632	13	0	1000000	1648212679000000	1648817483000000	1648213579000000	1648213579000000	\\x5775fe31de4f7240fc4ab7730bffe93440a08585aaf8f91ab2599a58cd1d8cd7	\\x5d8b25abd7d62511b219b6c935d4da57c00be767bbade4334da5ac54de8244755f56ddde225f7e12b31766d14320f40eb1f18b26a9811cd863f7bb5adcfe7e75	\\x5128c4f58b887620d35d86dab35c50dfe02f29d9ec35085df8aaa49e2664f472ac293945c4e79d343cfc86300af6b352395dbee807e5466f675189d2a708910a	\\x672f8134dc265e4ff61bebe87f236b6c	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
3	1859700393	\\x16cc29697891267d91ae49b1592cc83ef7d2a1901a18648e1fcfa42a3e7ac91f	14	0	1000000	1648212679000000	1648817483000000	1648213579000000	1648213579000000	\\x5775fe31de4f7240fc4ab7730bffe93440a08585aaf8f91ab2599a58cd1d8cd7	\\x5d8b25abd7d62511b219b6c935d4da57c00be767bbade4334da5ac54de8244755f56ddde225f7e12b31766d14320f40eb1f18b26a9811cd863f7bb5adcfe7e75	\\x1752d81e5bbf66f19eb1b4f37a0c5f6aff55014d742ea116f1ade945b48fa33739be5b3388e92298ce9abdc27bc2a107471c33a9ee0a0fb9fa90a331e70f4104	\\x672f8134dc265e4ff61bebe87f236b6c	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_for_matching_default (refund_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1648213547000000	1859700393	\\x2b54c55e6666f9bc033caf50d363eeb041590a949195bc830715a5e9b5312006	1
1648213579000000	1859700393	\\x097444bd5e8d03750413f74ac73d218901e1626ae503d80d1d12cf1dde64d632	2
1648213579000000	1859700393	\\x16cc29697891267d91ae49b1592cc83ef7d2a1901a18648e1fcfa42a3e7ac91f	3
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
1	contenttypes	0001_initial	2022-03-25 13:50:18.244677+01
2	auth	0001_initial	2022-03-25 13:50:18.412595+01
3	app	0001_initial	2022-03-25 13:50:18.555762+01
4	contenttypes	0002_remove_content_type_name	2022-03-25 13:50:18.567592+01
5	auth	0002_alter_permission_name_max_length	2022-03-25 13:50:18.575856+01
6	auth	0003_alter_user_email_max_length	2022-03-25 13:50:18.583556+01
7	auth	0004_alter_user_username_opts	2022-03-25 13:50:18.590969+01
8	auth	0005_alter_user_last_login_null	2022-03-25 13:50:18.597411+01
9	auth	0006_require_contenttypes_0002	2022-03-25 13:50:18.600329+01
10	auth	0007_alter_validators_add_error_messages	2022-03-25 13:50:18.607086+01
11	auth	0008_alter_user_username_max_length	2022-03-25 13:50:18.621356+01
12	auth	0009_alter_user_last_name_max_length	2022-03-25 13:50:18.628301+01
13	auth	0010_alter_group_name_max_length	2022-03-25 13:50:18.637236+01
14	auth	0011_update_proxy_permissions	2022-03-25 13:50:18.644945+01
15	auth	0012_alter_user_first_name_max_length	2022-03-25 13:50:18.652288+01
16	sessions	0001_initial	2022-03-25 13:50:18.688088+01
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
1	\\xe81041bc9b0020160d96824dc2b11f11c3bd2303c60bc87399856e8e9829e5d6	\\xddce260ee9e454e7fdc8f57ce198c6eef5d55a046a7f451802a29dce2b42ba91d7170e9cc8e84d364b94e9f98a01de63c47fdf25206f8740502410edd2d80808	1677241817000000	1684499417000000	1686918617000000
2	\\xce903bc8c5c476fbae32ea224d59953738f6db8e7a5e09c2cdfcd783b8184332	\\x5ea687dde068a903e0a4c852e96a519813e49de52682e19e032db9fca6d97e8f7a1bf236c75962adb342ce72f261e7c5e71c7359b61964bbf118605e7dad4e0e	1669984517000000	1677242117000000	1679661317000000
3	\\x7bd2e8d8e0fe9e6c29421842737e58d2b283616816614a6d4e1430bf65dbc817	\\x6437893282a6ffdcaad7034c026dc7d57e9c936e7dc6cf4d7e00b265752aca2734734ba0f12c95d8ce5ac77a722030acc61f0760ab8f91dc53a6a9af1f41d608	1655469917000000	1662727517000000	1665146717000000
4	\\x3f78921744ab551251b426c30330110f0eb954f69646f81f20547fe32dd9dc92	\\x83df6f6c162b4a09cb478d1d0883c0d35a5e2f872d246d71b7859f37a3b08531d3dd74fd6ab810c7c6877bbf1a01aade9fdfdd759ad332256abe1174a1996704	1662727217000000	1669984817000000	1672404017000000
5	\\xbf61e2399960566564ff5dd97c8e6dbb3ef5e081242ff8ef6b23ea2e6e2fbaa6	\\x09e0aa98a0439f0201432588dd06a0095105c7b043fb85e2537de0aa1b93101e98a8d0b4d5bc1f803ebb41e5f6ed4155144406b5fb2959d2de6c763351db9f0b	1648212617000000	1655470217000000	1657889417000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\x35e59b17496b075ee99bd011c0a8c61c5185349170a921d87a0275000f9b962ab9fe970cf6b7ebf3951af3db16a4d6c31ea2d33b5651a03a4c25361715f48700
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
1	99	\\xec9c35ae11ca3b80e0903fe9edec864da91495ef944b78e76c6a3d40b0bf67a5	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000095237e6b17eac4f6c1a2f7ee5cc8538b2f072fbe060f36b1d82d77456b3ff464491804f45cf91b599cd3d7891d1a9ec3be5d628aad163105ae2acaa7cddeb9b16807dbf1951c7e540d680be37b195ee3957d7c126e31f6a427bc1188363ccbbc840280d6ecba57c93667c907fba10d6530466bb86b66a838a96562fee5cb6fee	0	0
2	63	\\x2b54c55e6666f9bc033caf50d363eeb041590a949195bc830715a5e9b5312006	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000002108064e72f4ed31ee3f27f63de9c032e667818b7988498cec394e9a355e6d1c52aa40772e047893ab1d9e31eebc4b99341def2da9ca08f2a81cc97b1c208060cf6c64ee360b75f888c31409e87e319ebf5c109aae021b976dfcdad236360f02f09735abab9f2ca233559805b0b7fe2da62bba20cac9a00b289ac65378597635	0	0
11	64	\\xf958ba83ba2ef440351da41d5457cbb95715c93c8243d36ac07e7880d3ce1841	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000007b21c18afd9f4057f3a429a779d2f3325d809de1ad11fda63d9677baf786dc193c32f4d602a4d4fae662cc6d71b4e8ed6a34a69a6b67b5d9be122fa4747f56980b0055909ad4684ae5d68878bfac9cfa483f046fb7c708c65b6c0326d2ac319713b5ad8254294204ac88f6a78521b677be6c06aec046de4cd41650f0c89334c4	0	0
4	64	\\x178edb6cc0478822747e961ee71f4ed266764db1198bed21a3591417f8c03be1	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000014f79d458f69c01af71f3958bba0ad40b84aeda42294ba622a8bd3ba921af7798565779a978181c82b0a45a4779db224e911a9c1fcfec3583146a518b699d4f9f78d32ce17df42eb12ee0e41230165b650ab3c35812d6160ba40e36c21e5b81730069e1838bfb8990618b8700e15cad55d5532ccfa3391ca8268000f0457e079	0	0
5	64	\\xfa94427359a703d426d3a86fa960fe28ad348b347d794f2884e62eeeac665c17	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000077733b938cdb7d3af43d066f66bba7a2a576999400c1e17a356577e9db20962bfc2098c22be0aebbb574ce07b7dbe77af57737b06d38b13f3edd6af40591a8e7e0646756fa3cc4e8554dcabba263153f034fb0a71f8cb23878e8dd86b66671082f10c2e1e9fa9d52b791f02aa4b198723b948eaf34c6cd77b78b5714d0826f38	0	0
3	406	\\x5885b45646d72908f9b4a6323e17e11dc5d0ae644a454fe3a327699773048458	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000b9f9b2d2c464b62fe534d001686a2489bd7994d9ccbce7295469e2f4778d665371a4a8fdd38a0d922f280ce4f25609a6228d6be4e82295e6d953db5f93c93609358b0fa642ba835b4bf339e8083ac8fc175b372734794a16c28001d16859e5a5eb1e3ca1bbd7a6c23ad708a5db9d836a3f77dc06dbdb4cc7858fb4cf056035cf	0	1000000
6	64	\\xe20007fca30e1460f1f92f181f9415cc8fef1e8c73da03fee42fdebc9d4a8542	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000008d2dbb9bfd0659a7871131adda2ba388e8250e0dc90948abbe13a6860a75ae169fced7e3df3d2a83d801f75c1791e04dfb3bc584f7a0562d9ecfa085573efaefe8f96796dc8e2b36815196d8ebb058ee5d12026d001caa37882a8bfa77de5f58b9ca131e9cf7606d387202e72c5cf73d62c889b65075df403d68e4cc27b7f373	0	0
7	64	\\x7f0538ecb67d59067e8be00f87c89fe31a07ecac101faad5fa4b560bf6cd9616	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000009d2888531a4e59d007b52aa6e7e8048e240cfe22c11b9fb7232f44839e5eecab7ad70ea699f42a17b04373acb9f1d520192a9d1146f866e8a43f9175d75a0a0cd3fc96e7dabd33598071eb29e0700187a8e22cc0d3c3a7171a80a5b6904cfc59b1a17246154ea330285365b51bd71345f76cee2bf40b995065f7f451c274bd09	0	0
13	93	\\x097444bd5e8d03750413f74ac73d218901e1626ae503d80d1d12cf1dde64d632	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000000bc02479a06fbe8ecd3896e6c41f8157c7ccd0458aa0e5f6f33012f8d1f71e7c729945be88e11562cf274491816afb4b54874798cc90a838580230aaba71db2231092c7e73e050d1c451cf620683116ca882e8bd6319e3a56271c174bbe0cf00de15e1f2e7bec6bc7b0a7696b17ff5b6c8d6740c7c07817a80444d16de001cd4	0	0
8	64	\\x510d741b54437acee93b21000815412f12287d99c2ff25d8d3b4466f4fec7b62	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000016d2e46053efafdaff070614f3830cd2acdc0cacb65f60240990c288923a7085d2e58f8ba580abd45f0fa7cdae3c2bbe4e817236cc9a53456e0d3706788624a8a53577e02057a5f2989c76a1be40b8d6027fbc693713e3a0607baf81ca9a51c9c99c67ea18b76a36291afa7f6418f223069d8b775459ae4ddc98aa06a92dde7	0	0
9	64	\\xd9fefc57a7bb593d4af7b0bff295caa032d95f21d8e141314b1bcace2185cc81	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000009a4c50f413e2f32e4bae7d91da2c7bb0581e39999b5d5fb392825aa22005109ae7ad715c19c3b338be731cdc8c15094d3c9ee02c6b42e4fdb2fbed4b7658631324f24ce6445b680df4eb2e551f6fec7b72dab732abe30af0a72b6f9686b9835c8102bba06101ca4a3f5937d69d4f48f63c04e516087ac58cb8f1eda522580e4e	0	0
14	93	\\x16cc29697891267d91ae49b1592cc83ef7d2a1901a18648e1fcfa42a3e7ac91f	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000006d39688b1fb675da6f37400ed2d9c7658fb5b1697a606cad596252d8d4b53295e26c872d2b3c13fc05d075cf492faded431fc0f2c3b44d91e9f4a9857245cf98847a9a6c50592a88ac0dec7615b188697b8b83e04521e2553fa66fdeed3ffc3315447b45f5888a4bfd64feb634e7975a697699fcf83a7e1205b9a6ec271e3cb1	0	0
10	64	\\xe9047beed2a12be5574de56d89a7daa9ddc25459fe1e06f0737a6284a128f657	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000006977670473a3b29378dd3c0c8c1cc7e017152f41430df1da0e9fab0117e3b409c0b1c33311544ecfd226a7a794ae9edd4d3b5ce6396878068a4243e0ab0a3aed0ce0f07f8977a87556a00bb78b2a70df86b39a029672fbf28505a2e57a0520c03b465ce8fc00857a7b775a65c3ff8bd116ce53732565d8f6eecb4343d38ad968	0	0
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x4f02d682eff453d2c4a371ca12e0eba699dcbc7ebd2182bd431450050e68aae2a3d3d339570e17ffbdfca065c02614f2abaa23c1b6f7f06ea84a9c84acfc6ed5	\\x672f8134dc265e4ff61bebe87f236b6c	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.084-00070PGFZWVTT	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313634383231333534377d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313634383231333534377d2c2270726f6475637473223a5b5d2c22685f77697265223a223957314444305146594839583548353345373531355237424d54435853463359514d4752354641333248383041334b384e424841374d594b3735424757355a5a515159413053453034524146354158413446305644585a4744544d344e3734344e4b5936584e38222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3038342d30303037305047465a57565454222c2274696d657374616d70223a7b22745f73223a313634383231323634372c22745f6d73223a313634383231323634373030307d2c227061795f646561646c696e65223a7b22745f73223a313634383231363234372c22745f6d73223a313634383231363234373030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2234514234303935534b353059445059474142584152444a3735354e584e4d30534e3235504b465442453343304852575a33333447227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224158545a5743455939585334315a324150585347515a5a3936483041313143354e4257464a364e4a42364435484b3858484b4247222c226e6f6e6365223a22304757424a56504e4b5047545759545030583245473951504d4b4646564b4e4147544158593057584b52434a434d35414b333030227d	\\xf8d2c7b383961cb2999284c36464f478702c9b0d4719580229b901bebdbba6d588619dd45e72ded263b500a08881687db5771aeba960f3fca80bef394fbf778c	1648212647000000	1648216247000000	1648213547000000	t	f	taler://fulfillment-success/thank+you		\\xffd17e3466b70afc913928e5fe7a25d2
2	1	2022.084-030APHMGVXAJ6	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313634383231333537397d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313634383231333537397d2c2270726f6475637473223a5b5d2c22685f77697265223a223957314444305146594839583548353345373531355237424d54435853463359514d4752354641333248383041334b384e424841374d594b3735424757355a5a515159413053453034524146354158413446305644585a4744544d344e3734344e4b5936584e38222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3038342d3033304150484d475658414a36222c2274696d657374616d70223a7b22745f73223a313634383231323637392c22745f6d73223a313634383231323637393030307d2c227061795f646561646c696e65223a7b22745f73223a313634383231363237392c22745f6d73223a313634383231363237393030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2234514234303935534b353059445059474142584152444a3735354e584e4d30534e3235504b465442453343304852575a33333447227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224158545a5743455939585334315a324150585347515a5a3936483041313143354e4257464a364e4a42364435484b3858484b4247222c226e6f6e6365223a22334237434d56473037414b43544a484452545141544e515a4534574b415a3054445439394154534d4a51563547594d4e34535730227d	\\x5d8b25abd7d62511b219b6c935d4da57c00be767bbade4334da5ac54de8244755f56ddde225f7e12b31766d14320f40eb1f18b26a9811cd863f7bb5adcfe7e75	1648212679000000	1648216279000000	1648213579000000	t	f	taler://fulfillment-success/thank+you		\\x2dc37ba61971177dbaee2cddbbe787cb
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
1	1	1648212650000000	\\x2b54c55e6666f9bc033caf50d363eeb041590a949195bc830715a5e9b5312006	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	4	\\x9e1d4069e51e8908bd9d6f3302a8b691ffddda6ed9f0f486f6e7c6a00befbe0b4cb691c39efb678cb1f74c4f809270aaadde3a9885d97d2e5c01e96ba07c0c06	1
2	2	1648817483000000	\\x097444bd5e8d03750413f74ac73d218901e1626ae503d80d1d12cf1dde64d632	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	4	\\xf2e9a63bc6db5e0df46ebf1a6f4776c0d4005b951800cd8aa3babfdddedb3333d195b719c0555b65eea799126d3b6a06515451a133bfcd9cfbaa942d81310206	1
3	2	1648817483000000	\\x16cc29697891267d91ae49b1592cc83ef7d2a1901a18648e1fcfa42a3e7ac91f	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	4	\\xb6f6d14ece9d33873bfeb4aab080805d58c59f16a36db80e7ed7103d8d5288a86555066548d1c70896790dd611bc67fcf8256d59496251808e8d361244c66808	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x25d64024b99941e6dbd052faac3647296bdad019a88b69bf4b70d808e39f18c9	\\xe81041bc9b0020160d96824dc2b11f11c3bd2303c60bc87399856e8e9829e5d6	1677241817000000	1684499417000000	1686918617000000	\\xddce260ee9e454e7fdc8f57ce198c6eef5d55a046a7f451802a29dce2b42ba91d7170e9cc8e84d364b94e9f98a01de63c47fdf25206f8740502410edd2d80808
2	\\x25d64024b99941e6dbd052faac3647296bdad019a88b69bf4b70d808e39f18c9	\\xce903bc8c5c476fbae32ea224d59953738f6db8e7a5e09c2cdfcd783b8184332	1669984517000000	1677242117000000	1679661317000000	\\x5ea687dde068a903e0a4c852e96a519813e49de52682e19e032db9fca6d97e8f7a1bf236c75962adb342ce72f261e7c5e71c7359b61964bbf118605e7dad4e0e
3	\\x25d64024b99941e6dbd052faac3647296bdad019a88b69bf4b70d808e39f18c9	\\x7bd2e8d8e0fe9e6c29421842737e58d2b283616816614a6d4e1430bf65dbc817	1655469917000000	1662727517000000	1665146717000000	\\x6437893282a6ffdcaad7034c026dc7d57e9c936e7dc6cf4d7e00b265752aca2734734ba0f12c95d8ce5ac77a722030acc61f0760ab8f91dc53a6a9af1f41d608
4	\\x25d64024b99941e6dbd052faac3647296bdad019a88b69bf4b70d808e39f18c9	\\xbf61e2399960566564ff5dd97c8e6dbb3ef5e081242ff8ef6b23ea2e6e2fbaa6	1648212617000000	1655470217000000	1657889417000000	\\x09e0aa98a0439f0201432588dd06a0095105c7b043fb85e2537de0aa1b93101e98a8d0b4d5bc1f803ebb41e5f6ed4155144406b5fb2959d2de6c763351db9f0b
5	\\x25d64024b99941e6dbd052faac3647296bdad019a88b69bf4b70d808e39f18c9	\\x3f78921744ab551251b426c30330110f0eb954f69646f81f20547fe32dd9dc92	1662727217000000	1669984817000000	1672404017000000	\\x83df6f6c162b4a09cb478d1d0883c0d35a5e2f872d246d71b7859f37a3b08531d3dd74fd6ab810c7c6877bbf1a01aade9fdfdd759ad332256abe1174a1996704
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\x25d64024b99941e6dbd052faac3647296bdad019a88b69bf4b70d808e39f18c9	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x900eb6a9b646d52b7ef6c2abd4377aeb32b9019bfcf868eef4405cf659b8b3c15f2ce279a5f9126e8d0466f8ad215707c23acdc43cb3e4537c3859e970da0102
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\x5775fe31de4f7240fc4ab7730bffe93440a08585aaf8f91ab2599a58cd1d8cd7	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\xb7c7f5f642b1efeb4e315036e2d704d033ebc31ea35667e1a7e29a43cf4624e0	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1648212650000000	f	\N	\N	2	1	http://localhost:8081/
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
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
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
2	\\xec9c35ae11ca3b80e0903fe9edec864da91495ef944b78e76c6a3d40b0bf67a5
\.


--
-- Data for Name: recoup_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_default (recoup_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, reserve_out_serial_id) FROM stdin;
1	\\xec9c35ae11ca3b80e0903fe9edec864da91495ef944b78e76c6a3d40b0bf67a5	\\x902cba0868752795fd85ff0862b70ee179f5ac2da9d73b6a6061aa60d447c86ce22ef226b357f5b88bf8a0a0e9f4f2b4c15a7b896b410cd365b1c3812d39410a	\\x676a2d63373147e321d22794ec64a28611c8aef85098ec1742f2bcae89a1bde0	2	0	1648212645000000	2
\.


--
-- Data for Name: recoup_refresh_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh_default (recoup_refresh_uuid, coin_pub, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, rrc_serial) FROM stdin;
1	\\x178edb6cc0478822747e961ee71f4ed266764db1198bed21a3591417f8c03be1	4	\\x32a95f9b5647a8471c64a544afe8e9436402e1eacaf53f9a0e395f31e12b9aba786aa649b61aac853db9f6311ec301e61a9360b925875e4050c0718997720d01	\\xf3535dd7954d15b2e86a378591aeba48c08b850fbcb6bcaa4dba3415119727a4	0	10000000	1648817470000000	4
2	\\xfa94427359a703d426d3a86fa960fe28ad348b347d794f2884e62eeeac665c17	5	\\xff45ede1c62881b3c1d60c828bfb6e2d2bf9deb22ae67adc5f2661a112b7521effaf10b82822f48c3b26e3e89d1467e0426a9ad0ff872aff687aa5b5c9ae7807	\\x5dab6efe96167d90f7870af111a73991c4ff618d3916f18c4c0222f0ca9b9f5e	0	10000000	1648817470000000	6
3	\\xe20007fca30e1460f1f92f181f9415cc8fef1e8c73da03fee42fdebc9d4a8542	6	\\x491ab43e106e069b334767e73a1a322cb0ed640700df57fe8f75671bfbd6bb5230fbdf9c5efaec3788bb9862b71e5b75b8a8ba88763b1ae1392e007231313f02	\\xd2605f1070b4118f58e08e726c84fa93b01d280a9e709c8508fdff3ee99deb5e	0	10000000	1648817470000000	7
4	\\x7f0538ecb67d59067e8be00f87c89fe31a07ecac101faad5fa4b560bf6cd9616	7	\\xba3b46626bb1f422903cee6c6042145e231d69c4f0b85ec9b742e2d91529a9653a3e29e891df5d1b3b1554b8cb4aa3077802a441f0dc5e096da2ce95f2865202	\\x1333b9b895d50333d6f32c4198b7ed06d693856a1cfea84a0ae995f96514ded9	0	10000000	1648817470000000	5
5	\\x510d741b54437acee93b21000815412f12287d99c2ff25d8d3b4466f4fec7b62	8	\\xd8fe9dcedcff1ccfa50183459cd1bf4924d08a5e0b77897880f3fb70e8062f036048b5f5f4efe3163808d3a6da93730012241221cd2a931a1235c595ab95fe03	\\x576fcd96838b02f25b12121d69f40a7f70171ac2be6e5128e1d0526c6a16c995	0	10000000	1648817470000000	3
6	\\xd9fefc57a7bb593d4af7b0bff295caa032d95f21d8e141314b1bcace2185cc81	9	\\x7085fafd5ade272579751c916b047d96dd04392ad0aada4055324140d23aaffa57246ec44ecd398e36ffacf9aa81f0ace356a45394b3fa77bbe4dc75656ac709	\\x5860df477dc9c97beb8aa2c3aff8aeac58caaaa892a0069c95fdcb321a86f2d0	0	10000000	1648817470000000	8
7	\\xe9047beed2a12be5574de56d89a7daa9ddc25459fe1e06f0737a6284a128f657	10	\\x5bd562b9889b1843f7e48eea5a832237e2a4912cb2b47b2eeaad4195810c33f08f81feda6fb5c412f02dc11a8d8837b5e098430df31236abbac318484ef50407	\\xfd463d2b06be6f6cfe72108760b3d08198b96750148d02c447d114b66c784732	0	10000000	1648817470000000	2
8	\\xf958ba83ba2ef440351da41d5457cbb95715c93c8243d36ac07e7880d3ce1841	11	\\x636c2103152b548ac99cf13287419754c05af7f0b6ffa103cbea08d9f6682e3a6b589cea624f2635ce217d55efea9b2c2f51738a5ce56c8fbe62a7580266870a	\\xabf09cea679b52aa3f3e2beed54154128fb1d9293d34e27e3a83422895e7f65a	0	10000000	1648817470000000	9
\.


--
-- Data for Name: refresh_commitments_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments_default (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\x91ad35ce24854cd6fd050ece307c22690e92c206fb72e4a37bb392b286d23860ad617c17b2948533d886ee502e6e95441457decf88585a422f150ea64e1345ce	\\x5885b45646d72908f9b4a6323e17e11dc5d0ae644a454fe3a327699773048458	\\x2a6022d3b1f92268030bfd436587f6db587ec97f243070c835b7fe81fff5a3eccc2285c9fa6235ab07a6ae7edcc150caf3c30811c6fce30f412f4c2de3e8c801	5	0	0
2	\\x4d0947a262c098a23648655523033075316ac9a651fafa6af4efc03f0fa3478be071b9cfb42eec8d05cb8e06b5df57468ea6e92813a9ac0f1be19a6ccb21380d	\\x5885b45646d72908f9b4a6323e17e11dc5d0ae644a454fe3a327699773048458	\\x76ae5c42e1c60d9a63da6aa668986bf1d056cb56d5b683e79070095014e6bb735177e29738353cac8e6a8de007dde6d152d335a5e1f397bab5cfcce1f5ba2b0c	0	79000000	0
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\x8d6d72bbdfa81d83e53359d64e978cba76c00d8c2d9a9b7994ff772a722e0574df615f9a72298eb451e166b335ce9369dcb5d95f664552afb020e38ec5954c07	24	\\x00000001000001000e0fb5c7f89998e1a5274d87b0b67721f085d651c96ce5d502fcb2002214568360866e5a38d526a3af78e621724e47c972e1e27d88a1887bb0c83071a9f19e323a58bdc869be8972e1738d6c21893e58fdaf216d024e24834f5531fc57969f785a949d17e6d15f67e1d62f35f29fbbc5e1328ac7be732945ee2bff7215264905	\\x0656dd063782cf8602442652d2e6bed936f558c2961d270921787a6833f91cde09e594c1d8dfd62eff2db91063fda0759858f9858c15ba4c01f457d08d4a98a0	\\x00000001000000017804923ee9057cccb7efaf5ef503fa5c1dc1fd64d314c93bcbe4fa24c4f4385eba002e37ab381ddbb645acf3473aafee63798b65fe434854bad846d0c9b2d15c8b3a5b2891563d4932dd0e9c4d3170becb93fd93c1074fa0e95880c70c081dde63d1d8028e05c82b8be635dc1b1c5d4aa5ba2f6edee9129481ec0b97031ae944	\\x0000000100010000
2	1	1	\\xaf13e538e2f0e1475cca130b06f8d52ddf4cad2bf32e4ce966b21361e61090ef5eb5aa5a021cbcf0d117d38e0b650f2a938379f61764232745e9e6e104b98e05	64	\\x0000000100000100153e518675667a24f1b5abae2a629332649d1daef6d92c4dac205c387a35a2dd5d1e4179a4a0483a2bbd8578b38be8348a399e5f3892724724f18c444ec9bd74d0d3f13e760a4d712144c02beed2f0ae2fe98ff50af20b4399506ef50e1750a49cbb50c637266372b4f70e423669b68f9ae08aefe5a71d53791ec8ae961d427e	\\x43c87924451c3d78f2b54b0a3924e0dd46a452c8748567b18c6f0ec4030e063b4fa0f932a5449943f04c6e9f8d6e1f5862eb3d02164efb59470cd2b4ac9b27ba	\\x00000001000000017a79dede46bec9b77e8450ca733b2e1903b9e68a37ad10931437bcef6e1589cab61d0227f30577d59852879ed44a88cc5c935ccb95deae8a7ad72b52571b05d11b3a2c2d515b57a35fb193b9261af67e31edaca7e2f61f86ba4c715ff2637bb19fec6da056a5778cade6e40002f8c200c969c9c83545025f274f61d282033196	\\x0000000100010000
3	1	2	\\xe383f8c9453d8ca17a7f7cd56a315c1144196f7576f63aa77c4dcd9b7e51e0da0f52adb5559a29674533641bfab18cab539b6650228bca7daaa226672718250f	64	\\x0000000100000100938475a638144975616e78d24d68fa5286ab64bb0c3c488116c342ef93f54d6abc647cd0483de3502c7d23de0c667841495ab0db7a7d18df6d93c2eba45fb793da918eb405b284576df50b359365be412ff9c5b6384bff7f138dfd3e416bc9c20ccfc88a82bc756ada9c3953c9284897cf2b8c7b06cfca87a77cb071e533f5af	\\x4a9998f500931db271efbaa4d79831d9ec1437fa6804502ea3684b454df42129a2d2bd6c54f90e63410ecec54f915bda3bb9b2e3cb1760f0baf69b1018caddc1	\\x000000010000000110ce3bf9a6eb4e72bd48fb7e4a1b060376e406c535d1feb43b5c134c141f27a8222640a572efc411939d239b192cf7d8e2c46eaf14dd5baaa3cd07d769da811b97d1c9a7320a8063da2c50d6f53f3e277cec10e3cf646cf307e9a2f38fe7198a3e39418611472639dc36490f5b644fe5bc70fb4929a428c0aed608975ba57c4c	\\x0000000100010000
4	1	3	\\xa7bc4bf9af1cf57faceca7cb5bd1d5908e297d2518a806839a36586941a3cd6578f176c78a0afc85c2ab3eef330d9935982c4ebc5aacceed8a30dea8fd132f02	64	\\x0000000100000100baaf1e68e74bf21b78d04cad6f68f56f91fca09798c8ef9db9bfe36c2ee0e07cafe8bd2a13285c034e02ff871c648f7fc076d014ee643d9d2a96515cf34302e5790ab0c5a02506a5623eb53ea8b5c22d6902f7594f7ffb0bdd3382168f51287bfc7f2f5bebfab423b3422d1454f2b442fa1e581f3e754c59f2d7b55dd7f861	\\x156c5eabcef0af205e364c4ee08ab550628c4becec78af6507c087415f6029172732de493a19b0fc91540dadbbc1e9add306d81f46b8cdd8e4c01255d22e1db8	\\x000000010000000158ab829e6b395339979cf3e1905133cbd53cfbf1155302e903b0a1ca3aaa5c159325bde14a16cfc5da329b86bb94bb43b38637775b37f4ec7ef9d99e523054e9c81578513ff71d91c2997b85902722d6cb09e3a1acfda961e525915eccaf60dc0b64ac8cc476cf1391f3831716cbdf9db6483f8be4af1d339f3b729b73f65c96	\\x0000000100010000
5	1	4	\\x3cf01166312323354856b97cabf37e69e33fb5390939a4de2e32eca03c18ccc8c035fc94c06f826309af660c8d804af9d294555bad088566dda67250a0bda60d	64	\\x00000001000001000dea5161d7c39a5a13ad3633edffc217e142dd1dfd7c0a2096960414b69df3c5d4db694201abd706e9d1d399c7538a798d481f6ed8c4fd1a40d68b5539a1f203118a899c007d5a0d8fbd6471a529f00ef7e665cfb40d4f50e57cabe827f3b3268d67800bd6b3826c461d50d88b137e9237114a0e250e2352288c78b0c9f14e3f	\\x197f7495bcf8e386a819c1737ebd19dae80898d54cf80f4b8b7879e86c3f9b8b4806e5c46f9d4be5835a45f599c5d109720a322f436a9ca883fe6e312510ad23	\\x00000001000000015bbbbcb23a5badb9c399116ad20f9635ab4f5d111455459d04f0539d1e2d92b2a443247db10e4669b9a808f01bdb5179173734682e232d4a2d0f2cba77c473e493238cf1afa1fc31267359673ce33fd272ef3a2b5309cced51ae17b94f7781af10f1eb2553f180678c1b866600151249094d109293f7cf6efe49ec0dcca03280	\\x0000000100010000
6	1	5	\\x84b63c4555630454c26791af1904b1e1e6625916f04eaee73ec9d34c7f9f0d73d4efe3a5a26363925e547e86b10150be07248ffe4588a5524de3f75898698604	64	\\x000000010000010008065fc0f819ba54fa014aad22b55d4bbc22c29fc2b8c45db3f99ca3a3aeb84792be18d721e7bf5b0de041a61193d4fe2d19e08d2251a359122a83f9360630fbf39c8450c055c6141478e5b5f6f5e869de2b4279592f2c88a3521376893c5276defd02d41684679aeedd47ae5b4070ec755d07863bb35ae4e28bf63830c579ed	\\x8eac11b85c0ce4dc7a30032cc2af9e4d519845d6dd1b5a2fc34b8d6b190055046d42dc22d4dc2658cc56ae6908163e4b6f7411cc4f7838f0f4ea391887f49477	\\x000000010000000164b95ec8221cd2d1dad5731bfce8f90f70b0f70dc0c9a562b5ad8a0c89244dcdd1dff2de62df3bec3394d8dc62a1ae600a039ec1668cdd1907ed4a808f67eaf4f8a8d94e298fb43bc588f4cfa3db4bdf19fd2898ccb54aae9bd33ce546954a7c47d56e438d5e1f1a4478752b88c2ac0bff06da88c5e439dfdbb0dcd8400551fd	\\x0000000100010000
7	1	6	\\xcd71026852cde6a98d80a018fc9c0b4df257d4c8b9515cbb2804ba06e59d8ea2d206311d55706d6b535a343e462c81a5f727afbb537cadbb4184a8fdf22dc10a	64	\\x00000001000001007eabdab43987b036addf47770df774da6d7d72b0cb648cfc4e986851a6ff0f75855577111c9313ea6b2c773021b79aa5942372622582da30a91ce26d0a3f40b43361594ac0dae57d62c5305072ab69fb16484492df8b74d81faf45f5d1368fa6314fc74fbfd9846021897ce3c17d8a06be69c946786368da9d4bd8f7184f0729	\\x09076ddd22b3babb11e277f586690a05a6d603d1e31968657bd33a3e173b2ca45470e97766d337306ca19e4244835caa7d46d94be5c977b358357606c6a47bbe	\\x00000001000000011f937bc54e6884b87587805bdd5dddcc71366d26e741f853551fea0f64a3d65e21c8e7d4f0d3e12b21534352890877c24efdbe9322f4c6695aad009f89c9434c4b21649ec5798f170ba2f7014d8074613ec503ca7c99df7dbaaa0a7f0adc2026599c33e2b87df59b35914ae57b5f685026f68982bbd773e081978f3ab6618429	\\x0000000100010000
8	1	7	\\xcecfebe0a086fa4f8f10c9ac0479cbe09ade019eb33652a350c41aaa9fed42cd8d597b39a3f081bfa75681e5515e6212948a7ab84085a3a1b58e9d0b44096007	64	\\x000000010000010044f5cc23fe8fa62852d08450fcd67a2dc876f87b4ccb2b1c6787cd844e9a5cb6a2a07da9e74d943e2e8dfb761d1ce8f5e7ac42c5dc374dab9f18b7871d79b5298527316d3575c12123ac26a3a065b632db00171cb4339c15b01d116bb668b6f9c479df50329333649d14783cf1c76d7cd58a4b8f4f83ec2d095f4c2e0919854d	\\xdd31132458b2232156a0e6f8dbbe3e3fd55d6f5b055ae0e89ecea5b886fe95deeee66cba125a01666ed373c32682cd22ca3f6fab4a46cf98ea104955c8ee0d32	\\x00000001000000011320bcb5448754f2659b969a8e6735265bf5f74a05072edd8d46b063c619e14380734ae5315f9fffd58747c8fcab8fd35fa6793bf24a28a5f228fa137b11b60d976bd2b3f16df78ff629c9fa1c49ed179b115096a30d6977976d873f3abb2aecaa6e7e3fe7a1b396625d56b977b6b5162dbee2cf66a7d5b7a7145158456cf76e	\\x0000000100010000
9	1	8	\\x0a59303966cc5cf0b1c0816f1974ab2a00d23d32a0ad4702a052ebd43033712df7391c5577c3984712feb332968658e83497cc38345d3604517cb38c22eb9e00	64	\\x000000010000010024a296a75da898eee87fa1d0b03c602f8df8095ad2a3cb48aad5407072cc9d70f49b3a655aead411964ca46362d4114be66df05dad0c1851786dcb073af33da73deb318cf111ff1ed3a1ce179a4b283cbe44cfe5adfb290a9c5c38065d7cdf67d3cfcd9422c26ee62a3a987788065827bde1212d5122b4e15da127329ad7a2e2	\\x7a24a69ca162e0ab0cf28a350bab1c6f3a5885ee010c3581de8df7add365570235ae5e3d16190ca3e63674cb4c7549ced1bb6a3f4b6ca4a3b61a2dabb65213dc	\\x000000010000000180f4db041a1792c510234191bb54ec7fb122473f605f15f603a90071c1af239ee9d0cc9441bb467965ee2b9acf9abccdcd876e5a5531bd6b1f731b273d9f3cd587d2529c536f84914345d1121a3524ee102b7af16c70aecfcae511eab67032b94f5bba86aeee47381b133b1a86d52eeb8f36fd4125813111c230a98c218df969	\\x0000000100010000
10	1	9	\\x06ad20d076a411be2ba3c86fab17349281483eee0e7c72bd2f348a9b4f39c837106c8ecc9f3bef7aee3f9fc93ec4cba437c1cee51753503b919798c1ab280900	93	\\x000000010000010054c77ccbda867912117ab7430ca58828330e8472d1b1703693af8077cca2da2bf7334bb8fe3969785f357e346931c101a0ac91992e8e95faf8ebd15a180a6c51be3486f855022cdcdd37665de10998ba979ef40a4b8e337ce0e20eb0a7cbfb48e6aa0a927bbd34b4822f1c9e9cf16f8f455e8e502e5bbf74e91bccfc0f5ad46a	\\x20875fb0f416ff79b30ac43e38764621588c079171359b7bac13fa30ab45286cc3c9b05f0c5ed5be844fe0250b2ee24bc5e8cb38b5404ffeb2d44a72c9313a00	\\x0000000100000001269a2e4316c1381b1e11148f1d72ce6c5ca0f8106dfbd7ae312bb5f24d03b372bb874c4da2141c4cd5bb73e106b4cff0dad96de5885e74d2ddbd11ad7b4d213f78b88f63e11ad10ba3675b48b2ca56d8167fd056c1744049047d43f44d84844382ca7d66232a854a1f2a003c597924609b0f82eacb06ff5f92dceb12c174e7db	\\x0000000100010000
11	1	10	\\xe651a6d732461835c5e8d1c6fb02f8a1cb206b6e1c290271976786ce9c06d3c93713e4cc3ad756c2c1302e04b14044c788ca21e140fb72e8512c752d5cb14e00	93	\\x0000000100000100145cd67cc2cf37a1dfcab0502c58ac27814afaeceb56745ee37ae1556da8d52e5fe2184d73779876cd0e89964a5e96433b822af4f0eed70a37569617acc17f9f3886a668d5e38ed7072f82e2b2ee1f77ca2b051da45218a3efe0e3f6bb585455013d5120d0b99e3747312001ced5c01f05ab687ae7e70587b0af261de1ae463a	\\xb47a99aad5d17adac5d600d6425692b724353fae0f8dd52007d52493669eb3c3fff1c3192f61bee86919a4787842226e108731204249556606a492a498c1b6df	\\x00000001000000019a980e7b963c17549b1ef1c3a960a6ffecdae8a5616bac19161422f1fe114010feedd57d6e197e664d357379ecd55a357710a880311c0c0d5b3a880ba62f99901a5e4641595535690099b30f3eb376654af24689dbd833c1c4a02d8094c8b23fb3c84b630443f28daab12511b481546a08902838bf1f184139d85afc2cbb72a0	\\x0000000100010000
12	1	11	\\x63de383af38fbf1bd3f6502296ba0c35f1aeeaca48f4eae02c496480a6287e44f47aa7166ec51bbe460a693c9caae35d77e61fa45e5c2aae646cc1e4390c9d0f	93	\\x000000010000010024df15ee4657f9bd956b49551731f834d69d87ca211dc27a1b6d2f036714d9ac0f2f2f62d9dde2a51c1a9b832bdf86a48884b77d08f1231947ee4afd60561abfadeb51ac8c1aa11399efc0958a91fdbce5058c805fb513fa2b7904f56f8b5a1bad1fd430bcfea23b79f77f9701a305741b835985e8c49ca84eb1a72230ffdff8	\\x092fe19ca1e670bbce9c83f0154fe97c6a618ff5a0a7d6681b9a848062b8463e30862a8c24ad7d0bbb972f41cbf42976cd3c888a96d446418aa85bc6918f3e42	\\x00000001000000014085ce4c02d7ea0ca2c8cceef7b5d3cc6a03b0def1f08167c882b20666b91059c03da93eacc051c4bbcd9be8e6e974a0210605628c6af5c881793adc2129aed3f45e123448dfd2c44dd977294d8bd109bedb4c81e3e0cff010f1ce1d614b455dadf161055d12f4d33a45f08eb6ccd2d3cedc175ff563770d037dea01c1c3d13a	\\x0000000100010000
13	2	0	\\x7a82bfec80bd25b9aaa3044026caeaaee9fce37529d7bc41d9e34a1b57c43bc53f21454e441ee2f4ae1fde02368704525d2276544ba86d9ad5cd387561551601	93	\\x000000010000010062f7e3df58a09201896d627d37f63afa0794026b9e41c3602afb500104d0eff06f8621149672783a92979b1fc5b4783a3122bd02e1f3c28067811814ec6cf9e2eccc6587468fb1830c3f25cf54748514e7bbdbd6ab321ea18a84e8def82054bb70f2476d989cac1911482e58ec046162dd818174981c3ad6bcfbb41e5084cd9b	\\x0ae3cb70cab753d7fe89bf145f069f6ea5876b7796d141793b9fbe6169eae15c316d340f2070c245e7d8a510c241d15d2a57ec57e30c590b5097698ce6d94c44	\\x000000010000000158dfde30e35ef0764573ca6144a90b0d2717f2db635ecfaa451c03f5b8d482f00d9942875c17d28225322ba05416b9eefa6653738463bedaee52c11299eaab09a65c889892f34a5c5e5be25e9a976493eb9b7e3a611b5f41fe77a9793f7996a55cbe19211b89466bda728fa71658d480538a24c66ea9dd0569d6e96d28a9c66b	\\x0000000100010000
14	2	1	\\x573fd1dc9a1d50e402750e7a34d34eec6aeb8309e385f63e63686dd7bfa04e529ebcf46c8ea856c89a2abcaa30924985a9229f9b4274131ee2f8a32edd6b630b	93	\\x00000001000001006b9a923b0e37c59480c07ec7404e3a37f5bba030c3411889694e8337229ae29fbbcb4ade732bbaeabb64c7731b1d5e6c07f17264e7763ca0c8fa1bffab2e117d26ee840668554a7a52af9d240240e4dd3438c4194bb317746400e2aef5f0cd6c319232a775623ed4d164841370365c226582810d3720ab2e57875db593dc60c4	\\x4bbe44293c61b60251abfe28e5beb2783dba203492ff034911e7b3e80c53fbe2dbd86c294b52ba2f4a8b04c0484add9d3f84dd2e97a625251d5282059d3cd86a	\\x00000001000000012d1392ae021349e0e62fcc0b50224efdadb50cce2032c18051bcf826e514c13fad2ec1a5f0dd65276c9e476a566dd70173567378a8fed99f07f5579a926693f765983e03cd874d2d4c2cb66c2fa91b04f19cf8244d415df050741caed00c4fe43b0ad2c859ab8621556948eaf2a378c251db61534cc75241e02b72afd56748fd	\\x0000000100010000
15	2	2	\\x035f75eac535c72c6ec38205ef1d3c74fe0c22e2325e2c99bf7f23b71024c6bf475d475718c70202e040bfb99ddd4f220ecffc5f1f0bb500b9b96ea76886fa03	93	\\x0000000100000100ab334ae37dd4a84d8c0710282703548787f8f585ecc9894c48088d3e2346fd27f2c28752839252063841ff0e2bd7b3ba6e78c8461e7fb385b38cdb9ba99fa3c3e4caf0a74aec7cb722ae217cbc0e4ec9df25f248f66bfb159df6b5f0377c85f3195c4192c4069737c50423c44ff45a001dda33e5732681ce627d71a6406dccbf	\\xc5b38d5ae40576160c5763e271ba5d5bea7c1a23dc24cadb939efb4c7842bf410e2fcc71a7d54149c85d740cc4372f8bc27e9d122c9e79a4f880b1445446b21b	\\x000000010000000143108acb59354d0ee7e1deb0d5b73f86af0734a746cf1e9d20d316c5d90e28898575cbd4cd1554d3cf7d83bd79b3c511c66cc2ff5c3af2878f71dc89cf86015ec47ed85a03d4801d45b4271679d4633a9af986c5109a4a7baebd04d48789d2ace1a66335fd5fe1af98752151b84397d380f4f48f8c7c8b19bb0c342c3c0c166e	\\x0000000100010000
16	2	3	\\x61218d30b3374c1e8f1fd347f9e3ea2e51fc65ceba1e7e8a0b33b0aeb59347bc66baa233a9f68a85107013c215b5c62cf77fa8c953ed2488762c54fb7272ae03	93	\\x000000010000010021abfeed2daf7c30aaf522ae3282c4db0d114eb7f45fd91fbb7f2a554567460de4393c09942324ab8e92585b5ee19e5a4ba2990f31f6adb15ca9a9358f0ac2e064d9ca1cbf0ee87f36a677a7676bbb81d8e62e1479c1222b1e76fd67941a07d29ffca90259eb83d8d942257efadc65de564b4a65491f17a93e7bb51e81543075	\\xcb047f52143f49577a82b0187be4a736978eb6a3f17d80c2265b97e62ed92496f44c7613d5287711f3243fea439c7485e0b9c8b1f72700bd74bb2b062bf7ab37	\\x00000001000000018057e707c0dd864d9d5255ee2878e25083da8e98ecfb2f3bcf2b0cfe18faef051bc76c01203600429bbfc81d3791e9ed48e113ac8872d93b80549d8a0e1258e544c967d5166d8b3b3232fa7c07ee42126a1e73cf1ab1ac462fc5812e8a1be625fb12f3578ea7763cb81c89ee007e86895be0da69ec5e2adbeb28096f03c9a7ec	\\x0000000100010000
17	2	4	\\xdeab5c51ef3d7fc013f3b5687e87f364cad12a82eb93f73eda3eda8403fe8b70d692943aaf158c0b0dffb09ce55ae7aea7c54e55f68e298c61045e39c00f9200	93	\\x00000001000001008f7cc5c4d99a2e6d06fa1aa2d70c1b8106c76bf428f78ac5dc676ba48d4e3f390bc17e9eccd8928880d46b44e3122cda506c80f68315c8a47ceee469bd7a2d92f2e3a37134f4ca0f3524b9e7419cc1b10e7bc9249c14f555a3ada8f6037693976862563b43d5d7a0a57a027f55a09c8a332636fe9550982e438630ac2e061317	\\x303dff1b8b6002a5754c40dc16a00c225f2359fc066d0154fff5e9cff7566c6a290eff475456d9263b12b1b344686b3af3a7ce856dd4718d8b7e10877b788ed6	\\x00000001000000019159634b36cffc9663261f62e690d63489f3c91e5bebd1a140997ee339b66eeb7617b538d6a02451689cd9988a0f92cd3b81c0469acc4d65c345abcca83269dca182961c57af7178577de7cb6e1ce25f1caa7974c9c9718751088e80eaa27a3cc79c27e3dadc361516473830adf6415465cc9b8d0b963c12c945a5f474cd1910	\\x0000000100010000
18	2	5	\\xb714b8c03d3fd2802cd9a4b84a552072cdcc88733a7c59d2418c3bb0fbeecf27ac7b0d4ad4c96cb9680df6631a5edd38cc0c3b2c0d743dd2bd4fdd7e878b8907	93	\\x00000001000001005564841920e2eb66273b83bded0aabf8d29425ea325c82a78bd36de7f0cf071d4bfcdc7c97e320edf93470f05ef52f63452b3760cc8eb969e32aa94949c2e664d358d1c375de0cde122e2ff884004b70c7696e8255664111b3dacf7a3738ad513dad3ca9136b9b370c70b2643b1379b96040e9b58152a64551c4e914040d6892	\\xbe060c3e4c7cfe38ae904099ffc6bd64048786b6f2368b472676940c51fa739d6c0288f8f68c3e59c1f4045ef042e398222dccf96a5599744d48ffa6e8e14dbb	\\x00000001000000014afb7c4a5e80ffe5cef6728ac0eda1bd8454ed1f5b32d5ecbefd9728f1e63317dab796f919e426571c474887af952aebf43874c75587b8e670e33bf6aa0ed3428cb2919db62029f1eebd0b7b69095dab418c5361c5dc83b69c9524e081c2543ba973d5bb1d758b9fd642ccb260bded3bd5e6bcdb7267b452f774b0fb596c6b	\\x0000000100010000
19	2	6	\\x42eaf020a98e1d358614eb3f9e754d28423255cece2e2ae1d6c5c46aef70425cf0ba9a82d18023f75decf0852129f5b18540feb366df70e0db00da3403b47506	93	\\x00000001000001003323d16cef0636b732ab29f11dd31286783a80ec12bb87f5776a8986618b108e675bb9f165a7cb4d06d83c3fc81cd69a1e40ceece4b521345450b7e21440583abc5c9002841dfc2050260f4ca1f4fdf867fe4c797f45060148ae964b0b32fddff3f33ebdc92c96d69f0c8463c84d1366785d8e7e54015d6ca41dcec9304469e3	\\x7539846ff3e655eabb9755eaf9b0fc80e5b6570e55a6bea753324d3a52461ad6c86b91c045ef8ba5dc403a0e03afd72f9516405df8a537ef24ba9c6bc80c5d62	\\x00000001000000011a2b47759c8746559a12a54d7e1204ef869d00fdff2cfd3e48a7d66e8ff2802106c3259d63ac93957c689c6d887940b3399115e888ae72b4fbba9bffa71a14b9043828c671ce5728a84379fd11dafeb1c6d865515fd06a076addde9383fb10861ecac7d4e9e56873c88fe9562424199cb309de24c9828f2d391cf18879b5062c	\\x0000000100010000
20	2	7	\\xbbaa790b20e608535adf2e7a7c9ece71376a09b1b4e471bb51b889a55da782165380210e92fdeb2918b6f2f4575dd75a097bbf009716ab59f6dccc201c46c901	93	\\x00000001000001001bee65a145b6688ac151f3ce03fec646ecf977877cf98aa59b14ecfe4ea53c9491f9b9086c90884980ef830480952551b6e9040b01332f514ac10945cd27a04111903ad3eb90fd2e0e18a28877e8316014a5d5db241c5d33b1071277008fc6df70c7dcf02013da493031639a1c9032a8aaa012222a498445e1a3af884e1f30c5	\\x7ac89817768cb0d2a82eb21b7c5e67cb1f8fe6a11de75caf2ea126e85166c897219bb487deae6e3f59fd73098264979b141548ce4ebec2565a51247de292645c	\\x0000000100000001bf3bf5e237617b6f1463bb4de700a74b7d84a5e1800305f5629676ebcfc912c59df2d3459e2f6caba575c8c913b09c6df1a1a39fb0a0a0c03c8fccdea8fd41613fe38ab1b25e1036322f219f383fc426e2997a04a9046fbc97fd383069ec24d76b8fef5492610efcc7637df31119320dff0123b6d416251b139d1672ad385272	\\x0000000100010000
21	2	8	\\xa11b0a4837726128124d85c9d4bb4a479fe76fdf977db5d0a6ff370307ccf47f698c6e9f24f0e54e0c4619275ec5e7edc146a0d63d55ebb77630246d584c0207	93	\\x0000000100000100b4cd48ac819e2e49b186286e7b191cf69204ce386db7dd0a95328293fc1b90e59f31fa031d2bbef0362fb18634c1806f178b9650aaa1d0d6c5ad4f8a82a5b7c16385937fd8acbd470066b8bf7b6cfe19f8466dbf7c27583c45b464881d3836ef886fd95515bd0619b6656b98cd3998bbe3d17389b7f3106c2daa39135b8627ba	\\x4c11fe65f7b79677b0f84c5e8083c8fc974c4f1d4a7054be204679cca933131993ef547cca1f8660c2e63e8a1c93fdc14e0c9ee769327ea865dd1f1ffce38c37	\\x000000010000000120292b58c7bb2c4342de08ed392f01801e9d02965064d2fd8ab1fc11d4cf639d1f6580d96038f6913ebeb58a0a14a645ce54ce013a1d8364bd36a702f32c17493bb28deb55f6bf4c7829864045be9e3996a00bad9e323e3c14db0d2b038f515294ac1829889d56cf1d520796f169ec890c59e2025acabcaa3191f818e733d486	\\x0000000100010000
22	2	9	\\x630316944fc792e15e427c4c4696681b3ba0999e2b9cc395a5f580f635623b085df6be04ea0be2042003ebdf7580b46ce9811d1ad293466d3509fd15a9d5e902	93	\\x000000010000010092b660106342208bd36e18154c2ed741ba8ae800d33dba714f63780b1c0d6bb17a58109a36e3575aabd4a73da991a2ee9acf949308dae6ab19e5a51d53fdbc7f4de3e558a8b2bcef16cc9d5e51fb8ad8df595dac4b9967e4e3c937a719bce4a0ab08e0c534494b5689c857e39f232ca46aada1d0df9980e1f7449ca281f3a673	\\xfff3f9331f20ad76706af871a99617fb22046d6590e982edb7c143ccfa0d646e295c79e8abffd997199c17ef268fe8707ad8842052d9d5815e5b01f9fbb08fe4	\\x0000000100000001183e4e79b8cfa1883b671876074c2f1cfc3229e9b51b91c029ede40b15a55b660202ab5d56e6ebb08916136222f34d5cbd3e80461b00e623347daaeac9f661a4f344942b641bcbd83ec8060123508a9d7ffe480194e8d05a5474f5a90180eb6665f66ada3e63d73715778e6dbe654f1ae4152ca3754d205af0653ef00cd4c122	\\x0000000100010000
23	2	10	\\x19cd1c60679c3333e33af947d5cd2928b2e5d74c9497d67e02b17385cbc276e3ee18fc87895973277858e27f17e2922a78ccdea210ab6dc508d8580ecb287407	93	\\x00000001000001007ede75e09b7a1ddbc9adeec683217fa1058d0e60f3662df899ce9be864b17fb484dfcad1bbdfb7461c4f39f655ece741e2810e40dad96d689b3953ca404c993aea8ddcfbd0c330d0aa63018432218e55874099513c5ceb565bd5f86be1a8d8b0b05d3954aa71e33a4e6d05b5c61d40ab864e2a79524bbc94fe552f7571098a0e	\\x1d82a7f4449a9233d9d8265b8d4e6fb698a4913cdafcd46eaa1430d1dc407052249dabe2f2e89a9bd71c3652606c21919a6ff6d4c0d931ffe1b379d67b4c09bb	\\x00000001000000018489dfd3d9489d52977b1dc2fea181ceb5755c4fab730e17ba58367a20e1c537085fa351dd53da7af8723bb2e997fddd2b24ce02d4f14609cebefe7e07ef0f3ed761f40dc64e2bbf1b146be846d7d9ef83e0d3d15f6e4b357d2427bd29307236d6f771f0f82dcf68acc654f52d9d19c8b897611745b1354d28c760c63a3ea194	\\x0000000100010000
24	2	11	\\x8e4ecc1c07a2e07c5720456239e9fa98ddb89dc024843fa5222562d7a8b4c7fcd4a4a8fcf1982ba21b580609c0d674f55f2e65f530a27642fc8ed972e7d14b02	93	\\x0000000100000100a4561054acc2df7584bc3dcb6c208ff683987d975fe0be3787f083e9d4227a27763ede0cd43cdc415369328541f2fc45307391049a32b297af0a6c99318af5b6a389b211b4abc60657e5861ed339b666c53f0c36adc25c2bc9e2b78f3b15d422c410a2d61c6b41dddb61d3331898894dd79fff263fce86912a53d582ce8e6d16	\\x214d5ce0c7fc1a4459d3dae89f7e7b3e415a481c24057ab729ad6e50c4e4bc6a7ba78aecf1da08bf00d0642ac91660a51c4faa62be2b99c142e390439f08cf95	\\x00000001000000018ac3a60bc1a185ae7836367d0dc062d85c474be3e2fd05801c786faeed8e38433798fce955709f597d5fe834a6f4a226c3773a0caa85827e30cf21a1d8eb089e22b56df9fa74979b80a1390c2cf8f182167a4636dc5eb5464e3c49f4e00c56141bd2d9a57d46cb744d7c0a1edc72b63bc56cead4a07f8643216d969b5a1f3019	\\x0000000100010000
25	2	12	\\x25309b0ef7f576fe638ab68735554bf7896d38fa6c6cea3523b719e64ee9c1dd0e750643d8d261a60d5ffc1a5b922a4e4ca7058ed1073e1c2e5c35efda445100	93	\\x00000001000001005a996537d901ee23e5cc82c5c8e11eb9bd2c00c8be5490f19b92acdd6f0e1f1979df4553f02e0dae49c92a906ed776989981aa24c40e893fc276238cad80f75b1d83b8b528b390163df2ff30e03703320a2697bc446d5132b5b34e4ec68a40b06894033ad1dfb32ef7b02018ee5269010d82909d3179f3c699f90895b9f636f8	\\xd5ccc363be9c7c11f24f462f571260d6cfa9771debe4290238554e79ad0d289aa045e49085bdda20f180ea23825f0752825a05dd4f94313a8cd2f88118d0c9fb	\\x0000000100000001463b24879e7de46b38763533358ac2136ef2b58121e2631c01b7b9e26416de3656457a80ddf06529068dcd23bb4e76c3fca20e572cf6841e90ac61734cd50c1e844aef16b40b45867069d5a56e10f9add64dbbbbbc79ad82ac2bf9940c8ac1d07d544cb7a0c6444d18d6b7b0eae2b45f36add50c8d53bf687e51952bddc6a5c5	\\x0000000100010000
26	2	13	\\x09b75f59edaff531e435c1ed1183d0dcb836ea47814bf52ab2acb1519fb5cc1186dd9ffe8217b730737e7919a305573e027ea396979f997b52ce5459ccfb7903	93	\\x000000010000010007ad909eab5c18aaf5233829159c927da6445f2a462b6dbcf4fbd07e0150c6b890df4109cb832575ccefa64d2bce52af2acd5e6640d329667e2336d44517ccbdf2889652876c206f0586e4708b48f47b4862928b2fd492b161408995c53b36c83264c9a4828dd9744aba4a78eb960424ef96636155b49b95cc651680c3abacba	\\x02c53f2dbc76d5040b20d307f2a7e6ead29f4dda3185ec376e67fd3a895968498d03b948c56dc9418e12a042925127c69c8ce2a297c0fb49f5077182171f30e0	\\x00000001000000013eaa14ff203e02c93039dfaa1f615dbd3d68c4f4ac2dc912ff58ce057774b1be5a2f61ce7e71ee615c931054b740b9efab76f78ae8215cf711aabce8b37a2cb1120310f7ab8fdf89487d3e01af7e4bdb64692db0093cf5822660c9f57aea1d041f540b0f634291b08cb7e118e4bc9c2d3ebb0671c0e2846ac62a897b9debd4fc	\\x0000000100010000
27	2	14	\\xd841e601380a9ef0559c5d2076eac99d7e1190d9f5f42cd5a5b21dc65ddfda2cd6c4ddda1a027d3f9bd0116d740161d78464fc12282b08599284764df3f2a808	93	\\x00000001000001009760e0ff993a05532bb726d300e192c60ad01165ae81f27050128606c4482b197130be1a10224d38c49f987bbcce60ebd795554d857991db134c8a3155fae5fedcaaeb3bf49ce3ea86ced549e9720bafe4b65f04b39e926d63215f878557982729e72ac9af186d6a2f815885d05a930d6b2f60a3dcd483c58dc307cd3a31b086	\\xc52d18845310a4e0c999d7c30f7efdefd44c6dfc54262af30c95bdaddc025deb27b8aeacd44244e8329496013700dec9286f41c1e0175c1142a55ae495fb8227	\\x00000001000000010cd8f7662ca2500f86e8ded82ba26b3e771c4a79e5adff9d196ce75444b99183253f08b1ccf9c2e0ebab68259b36a8c877d6bc8e28021bfa762b9cd4d58d8471d67f3a3904694250dd087a8d87aaf178883cffe59b7be7af0a9815f7080d7b6cb1bf65758c778768f3ccdf8259cfd066d97c67e22d903fe4bd16569bd90c4d64	\\x0000000100010000
28	2	15	\\x606b639c5e98040b9344186c128edaa1a9087dbe6eaef2c98d5b36b50d387a014569ed13ecc4a0de32715aa986f3b7b168b3278a13cb0b800a9016ec3a22090e	93	\\x00000001000001004e14026e44442f85d39c73b3dd6cf8d27d619f905b9397588e482d970ceae838af4a70a3c8ab6b6689a1d98f53dd90909cb7595a3a97050a87eca8b5391a6f5989a7b8dd6b66d0bad89b08ede9a0b737659954b5b06b6c0985a415d376292dda609247d234da58e66fee10f6f6b9ee85dccad28a6e5d21dd5ad59f2f4f4fb269	\\x116c12f3d6b55f6b0d765c08852ad7a9bfdc0651179f53baa3d9c8fd44dd5474d1f0d12eaf6cc2eb25a22d638396b1b34b13c6a9d91b9ac8ca128355eeb1b5e5	\\x00000001000000015d4d8d0e0fd42fe24e190c6bfa1c94d00d5afac8a06c7b4cefbda6795ae7c6f17b394831b60d88088a42538e308c41a430271208175de7a941ae6bedc4d9d653bdd058fbbb1d81072c0a2d04e0c41b003a94d93bce42f82247c635969b54d49a9ea31736e0e52ae893cd07b6cc24588def3552023e3c4b01e2f0755722834514	\\x0000000100010000
29	2	16	\\x89fb14ea5fb66baffe3796b05c1463e78d5fcdfec2fa67a335d00804f108feb2b41f002b1871b7f8fd95454f3d9ff04ec106604c148bdb038674f48924c5a10c	93	\\x00000001000001003478d33f6f2726c3cda4c8fe48751b5712b792adc3b6137787c029bc435ce0afb1403b2681e81cf822005a9175e14f6a5eaf90a340c9e23f2a6c444007838058231cc092ac8ec44ae87eafab199408b665960ff1349860a36766f4b284867605c36109a6b384f356005ab4bd4b6e191798df30b7a053387ed99176d8e964b0b3	\\x0c83a3f509f3dcd09ee2dee9bfda33513eef94696cd31fe6d053576dfecd664d27a5504c64febe7ef7c85d3289feb675a1c426d466298410792f4d814577a85b	\\x0000000100000001444e046a66ffb622758c5dd7a5cf09e88348d61e3d79b303586ec34a36b7bf2d9824efa7054431c38bc28220395182d20c37bcf86eaa1c29ff577362880c1a864b607dfab90980910d96398e321e700b3431250cf88c653199915e8fa4023dc08feba4c130b9e8801a0ba4eba33bf1a8a5044dc5a5215072649bc7163cbe35e3	\\x0000000100010000
30	2	17	\\xba6ff781ce9b8d1c19ad78b6c70d5bf3026b1dc1cda6f2b4ff097ce9bc15cc85a07a787927c1f1edeb7c424b35c5f5c77ab860609f828332b1547bf873252900	93	\\x00000001000001001b9cd22ec42c0b38a4eb949f05add1eebf639b8ea2a31faab8de3c805fb3b5ddccbecb8804add7440bf80e936f12e9481cc04a4d376acf49394428737cd8454c93f54090bec6343f539314f04ea182ccceb218dd5c2480d4b55600a3683e9ea2b264e6d0a6f7bb4658a81527c85a7b1904f8ee03a28cc9eb07ebfaf04d65b1e3	\\xa4fc26b0bb2476fad601e7de9e35a0846340805245faab4ddf48208147d78ab8d964e63663bdaa588fa97a041209823977a46745d170f88930570a78f3ad056f	\\x00000001000000011f7f4faa6ef374aba71218b1d4f20c5010cd5e4151e1cee3df68de0b68e98b149edbc0c726f7b7bfad1e0ca64d8eb9e846c6c7dbc567f4a21f62a4f1f23220ca2bca5f8c5efeb93ada32ee581d0b2dd0ffdbf1e2b6d7d21a86327b94c0629d596b910ec6ce06dac81f3a802e2f77b15970c359cc42f20d37e0b69397d6cb7a1e	\\x0000000100010000
31	2	18	\\x61393157985232710205098881f0c925eadd45527d5be4f5e19615b84c04a734bef5a8e67f2a9bdaefe096ce1293a87daf6fe22bffb3633ace86ee70ecaac503	93	\\x0000000100000100c018c0a2e75d1178f7a6af06ff78c1e38ef98900611a31fd6e81be345464601dbcef9252d5819842fde7deb462245ea8b2f67baf823b98ede58018d639c06576c3e538f227ce691758fb0deb5ee76e6ca68bc4acc2b2416bc882ee416aecba056540b146b439ebbb24d0c45eab6bc433785753b862db1411500ad0b05ead3625	\\xd30c1aa99d0bf0f86fb3176c104dfc204cbdfd2de05649db57184a6eb94243c1e48f3673b2191c3637ef8921ee0a4b5252d6fed7ce55d32656e359e8b5ee5cf8	\\x00000001000000013c1092964851291c696a5d412c3a336ba3a50384736f9e928644d459512325cad936e8b332f2aa0fd4b4728b5e5acff04d990bbb76ee0be192ed3476cd24316d1e973f44880a82e8f51966faf62b8c0716fcb3ec69afdddbf9cbed6cfb2d0c36daf0e0e25a4a5bea5ddf8edf0324b83965eb87dd7a820ce6582c2ecc2a4bf06a	\\x0000000100010000
32	2	19	\\xa1a7e7c09e2958f81310846a061ab27de2ed1628a04d42e9500b7169976ae41bc0c3f7692304af50c4cb28ac405338c75d7bdceea620f72d8bc7191f9113f907	93	\\x0000000100000100233db95bb0fc570e327693914d46800d6eff30bedd10b6254c249eec00403a78f739f3eda74029e437d4925dbfd70eeb76f9308dc4dbe7223257d48ed4827e736e20779b9d86b1a86ee6019520274729b0b3e633f52fc62188e0c7c19a74741d808bb2d5ee847185428cd355cf32e0b18a619975cbaa0877c5b0236b76148bb6	\\xbc695650520d50826a2462c3988d8e444ea17cd3df16e7651fafd0a218653145136698a63479790465719eb5e6cc0f96e20e7bfe8184973ca657f3b595f6ab37	\\x0000000100000001643c32e92a12f4c906f7feefe5dd20f61238e90b923580a484af5b1ae966a7acea526380b9617b19c8a14adea182c5e2725f0a9b68479d45459c42d2535db56c4113a1fcaab74bd65f69c2e7659c8737e0e2ead15e884ad884799123c172f4823354e956c470de5c3330e7e525277cabb70a28029ea87d5d4bc70b7695ccf23d	\\x0000000100010000
33	2	20	\\xc3d3fa3f19b8f52520bfc065a1df6e08ae7967d8c017dee98993d270ef6304aca1816b397f8f02ca98d0118a7cd9ac3e4c4b2519a8235f6ec095a0272e45360a	93	\\x000000010000010081c05871f34641008b29aef0447e7c668bb9f1c8e375547f6e9aeda4cbccfc094892ba99af5378ce2b1e4528cf6121ec3a851f6dc1c0cf4f59a9a29b46ce714885bda2db8285b9a78eb7fdd60353a5b7cc8f22c746cc8a97951f96afafd409ef000a350c204cac069033cbb1563fa48f5d5383f3dae8a5848898e606988844c0	\\x5f703a25ffe0e36ebdc0ededf07be29b0282b54477b94623f064ef4c31434465d9eb1f59ba8a7a2d9197099fc5651e30f31e9f39f65dcc403cd23aa463de35e0	\\x000000010000000123cb37cd919e05055827bb63c15aead5224b421e686e9f113bd63eee56cbce94d8638827f9d693bebd846e682d44a41ad47b1033f93a023418aa49ec64dc90a9f369130685068b69b499087ca7cb6ed2baef93f2538cca97d6b2d6f7d970d67aced3990d90cbbbe9e47a945e5a77b25f2a6176a3aa8bcc5f1a7bb1b49f5e87a2	\\x0000000100010000
34	2	21	\\xa0634fb51589a233598ec73c1cf74988006644939d96b57307149f6a45c4f9f25fd04fc973236020488aa676d0d0693105e00298a5dc16aa58d340019351c70c	93	\\x0000000100000100a42978905ed977c20e91e217fbd0ba4064319e6b5fe19c23729d2b37309be08b78e27a4b24a0323948be368203e8a4558a54a80517b7129951215fbdc47ee57aecd68ee3c7b980dae63115348d1c809d9725e87d4d09173d395f180cc14918617950b6be75667d349d625c6ce3e5e40a2dd13942d5442d3509f52dada8be39	\\xafb37b1e253fdb84baa042c41dd98ddceffef12d153b2da2438e85708a9176b4d47216c84b7986d4168a9b7a83e1731325d71da3e48c0dc8e2f8562c563de559	\\x00000001000000010c8c48403d0eaf60a4e09c195d89b66ad920413b1f3cc335b7cceae9a19f96276adf7319f924234ad73b8bef85a7200a808952f51bf6defd28b1f2cfbea99894b9816885e41c87b03baa5610c476a5511a0f1138aa9fe5ce71fa5813caf0766c518e23c51e2aa2b57b8fed96aa485be08d3d239cfffb7d87e01b9bfa1dd4435d	\\x0000000100010000
35	2	22	\\x6846534cb4d52348a21ece5337e5b0c165c39bf61e814578157ee5f4e9f5ace86a2973da3e96d07efff20a677edaa10227e0ec8bc00e4059a2183ba9f3eb7b0c	93	\\x0000000100000100a2f610a784fecd25d7e01f7c4de97ddf4f7cb03ca53327dc3560087e65dafcd43aabd161ce2cea82db05dba40b41707b6b7ceb96804645b60664b7aaf4310fc8d26c9e901abd99fd1fc4342cfc98908990c7b29c20819e42cac1d12640ba4b6e2389b7d439db7fb40226a868329c2b8153afd0b6b4bd7b64a972eef93349c68f	\\x280ebd3fd350d11c65b08dfd1465bf742fdabf3d8c292090ca9739c1f541df1c0b08650f5fd076e2fe665b8377913020daae69044844ef0208591a0205a5e16f	\\x0000000100000001c0c328d794cd082f34d33fdd91bab554cb76df8d86cd546c4d1eada50b3c96e0d6e807d88a560264010081cb4445db5486bcde67db059c8c26dca37563499efd5ce34316b8ce7d2b6026ade8f90f9fcdad7391475303bbb3435a125e87218d7c0928fa2c9c19101dde11e6982df4e68cc38e0513454897053d3b10a72394401b	\\x0000000100010000
36	2	23	\\x4fe038f9e4c3b3fe1653ff2975344d70f4d10f9a159e684dd1cdd905885517317b28b40808683a5eb9b0b28445695d55aab6527701ffb92d8827f12514dd040d	93	\\x00000001000001005d36f39c2dcd18a69bdd9ca71f9d9ba6a8c10fc36612b0b1b3847c8102f2e8e004f9cffcba56fd523513f3259950e4b68199e8ec68892a4a96b065c1ab3439abbb3dbe3ba58507c179110e054a7d05a253f75d1216b567cd41d043bddbe0d8b820128961afc0308333ffa6fd7f756ec7df95128dab89b4afd3b54096cda476b5	\\x6a8562f21b2753923eca5bb305c34da86cd6518d25f237ec9eca088081e2793c94ada944abefba68071dc2bb37195f20e77e43695c75ea67279cdd88ceaf0cb7	\\x00000001000000019f16f6898b37f8b8b8c1c4308fcf237504b5116cdf05003864a067871a785a357adc8065b9e6d8e590582e8db8c7b66ce9900ca71acb8191dccc84af6fc0c41af1258c655f851942ffdf39680717ffc807c7c3b9c1dce6d945b9b49a9c66bca61c7e1b0e75413622bb1bc9620a0042698a099ab1f7014029aee6712301611b44	\\x0000000100010000
37	2	24	\\xd29e9948bf58e0ab5a24c3bf80977823af752d397a0fbe9c489528417ebe7b98790ca41c5adb1cc351a971719635392f474d2f26045dca2614900612eebf8701	93	\\x000000010000010090daf8b701ec8b14283a9af2d2e663ab5ec91ccb6e63b46a4fde500d0313db0f827f38c1b42ff642f1e8da44d801c7cee07f42c0cfab83df2a10ee123b625a9fc0f06b6b26237e1b1809eeceaa69bc81b0e842e27192651dfc3cdb458c34b67c53f534fa122c854def576e3e7282660e7c14329cd15d5fdb1f2a351af718ec83	\\x028535b6b702e8e9dd9b1a5870da292dc81e53c8fa510c2e36aff2f904e5b9fb90ed21f0f96dec44b82e97df305133659b6061f17a1210aa9315e37948ed047c	\\x000000010000000105875d726caee46984e2d47d47c2f6a705387e7f6e6a3200054a7254caeb2e26979b00cd24d69028e05c9058cafaccfee04005919fcbaf06645fa08ddc1342e0dd9461bb4e222532bb720809b3cce487de32086eccb939ba2dcd83d529addd420a70afd143ee84400889d5383484e38c32e005c9ae2a86c44015b9fa35ab3c04	\\x0000000100010000
38	2	25	\\x37859e999fee383e73f4566dea4d1dc329797483e8e1d1901f2a41bdfa72b4d81ade4ff3fe517d577ea21c6c06f1ca2e6d9aa042921070c39fa71ccd7c326303	93	\\x000000010000010017854d9e81be25e40461bf4d0d881d52794d72cb432dad84fea72cbf76b0dae7db37be668a884691596b884928888398df1c28d1a3f6643290ae1fc95706f90fabe152eaae8a0584ced179247fe956dbad05942839f746f06ab9d89668aa585e08dbd64ce62f12eab5c48b4bbbfb3d9e479ddbacec2fbdee69e298478dc6c65f	\\x20064ffb0bb865f78c67531c00d3266d951b6b82fc6e1e57f893b86eb62555850f3ee86425e4ad343c18ce30efed379649efc289e89e74e354af1dd6a1276c55	\\x00000001000000019b3ebc6decb1a4ab264cc65c0fd6a93830599a20de82749084ed625e72e64975dfd9401ad61e34ade34c31ce161b7acdc4a94c3f7b0093f34bcf588e73d0e80c7c0403b9abbd20108d5706d4f54524a158ec8dfa29786056a996de79b29ade28190b50ece8f053c5212d2b054c08c64173e2e809a9a868f1430fc16aa698f5ae	\\x0000000100010000
39	2	26	\\x4de346d769f31b0aa082a9af3d84b14624e3123ddb4d8dbf8965ddf5894d86d41315ac59e6b214edba3a0aa7de90aaced1cf6a26795d65f830415bec381fbb04	93	\\x00000001000001000acf31c0657ed242057ae7021aefd42b2a913a57df8ad4afbb674ac36cc02082e2b9144208fd108f1575318b1b5d981756ab00a42e65d5d17e21eb5d5fbe26a8e24e67c4eb1e97ee15358a7cf7f96a386d01f85429a96cbe50acdfd11f3e4d1f0f7ce3e486c3ec14ff60abd69ac987fac27041536277463858c8c1d5055dc796	\\xd1fa6e5d8a501e363859cfac87f22c6c61847e9f1b3910af96f13fa037e46907fce536a27f0054bea219d3b5743940b93189ce4ececb949777b9fd6d1bf8b4a6	\\x00000001000000019667586a9c3bb9effea3cbd7fa51871cf4c1382f82a36c557888779ef49d10b71b886c304b2c28e992616dca7fe40121bf0c1beca7a54ba8f8e80231833e0f7bfd16bd62656a375d67755fdaaa7668f5f5254aa79c026bf1744b11af7d4f822596d5a206c86e3c86288a27ec4c7a3f3eda4f04c8c20013cec79e9592c438f110	\\x0000000100010000
40	2	27	\\x7390276d3f20258ddeb2b7e2c83b9d2dc1f3d916b1945c4490f299ad2b6018d5c3a9dc27d2aacce9d80b61fd8bfcd2de1c051f4a5c3677e862a8d623bb22160e	93	\\x0000000100000100a995b35a3241f8505fab043132cdfe9a0694a56e68a714b167d8a8e5f59c326941118ca546cecfc5063e2d0e3f4b328cc0f598c3e631bad0edbb14a43e54600b3b2e27eb5513dc4952ef1293bbbea7ca55ba722fcfb3189514112382fad93f3a90940b68e17ec65a83b78c1048f6864f1a9c9ce478385d2f1b6c1c90e6423fec	\\x8e304d4b141957948f46a8b1006cd3793e7d2c56da0b48d5e4c6e9f0937e00fd94325cce07ebe75bc6cc3395d7df30d6529b0bc6dcabd30a6c4094b9d338510a	\\x00000001000000013aff7ffa15199c388da8eaf372acd6a0aef4331e6993e29aef6c3b2f7a9d0298bc99f72c2c202a4ef15ef00dbf3f1ac6d2f91ed6e34bd9ea4308b788e8d43a45768497d05652f10d877f0262fac93e54501e3daba1dea5f2d1ed53e666cf93a329827ce63d5a0ab8dccb41d5dc44f2ea708e76737fca09bd6dad35cb3685d4f6	\\x0000000100010000
41	2	28	\\xa15e43b08c5ce36cd77c17bd6eb59944d057dda95380fb6c570e8f589dbc3f0ab2495da7486b46172eba93feb4f4bbc5c3d9926a396c1e58834dab8efab4fd0e	93	\\x0000000100000100b342fc325a117614cee8a9f2898535812171f39faf5a82fe5c99a6cac03329554f6eb78b80561ffd1ab23eefb9444a1da44a05d70d285cff2c915d024c7fa227371f6b457c6a1be0855b45b83a7d49495c4fae636f4b663a11f08553d068a24fa77bdb7d785fe1af99f0adc859b9c51748c34bb72499610b5d22c3558d70ff3f	\\x55915b68152f30a86afd6c4bf795b77cc56fac185fb35e9a61ecd352332281934f48890e3ecc65b9d2aa505f83a9aee3cf6390c0d96a69e2f8875f65f30babc6	\\x000000010000000141e6286829cdd6ccb349351353adc4d5e64d4297b2811d9cedc86ed1e749431e925b26d463035bc44395cbc7a2c7daafcd42103ff2dfeb44e9b73c53cc989c41bea224c32a104cbde0c1e42868d90899ec4e1126911dd41b316969c2439735448db587061e307af9cc1887b0bd1ec71139919dfcc5eadbd907a8aefc65d5f44a	\\x0000000100010000
42	2	29	\\x794dd6bb017bd7372294e269194fb65885381e97b2424f7f6fe138fc8acbd75a565b94d10f6dab4ca7f2d56715461edd7cd9460c1cfd8c4d2334baff1b4c830b	93	\\x000000010000010022b5b5311e5a0477630f3217a99151f8feaab0539a10db07666f3d80b9d0596423363979d91210c367a115179ecbb93975c1d936d86d4408a9f0499a4ebe545a69b34b6e741e50535784ea4d375259167a033d92eed4a2dc1ef87698484e10ca8892315446924f89b3817a515132df65f5205b5bb3d127a2c8a7aedfa8859091	\\x569746c3e0ba3e8a74167f6459895241381a24971be06c70f275d62b271eab0e48907657ed5c2d9920c6a44e8ae55920db3764302c0cd29b85959cbf6d1a412c	\\x0000000100000001165a99dbc079d49e69eaacad6ccecedeca32cc5156b80b2b58ee174f58cd08e16d33a4bf350c47029ef97fbf002b5f286a98c05df614448b565595069e9c610c376bb1c8ec8037cc0c2ee01410156b4947a4be69b1e893157f3f29620bfadc43e34207eed68caa4202f4d6eb52263f0ca87ba2fbe19e71f2ada81fc7f96febdb	\\x0000000100010000
43	2	30	\\x1384f837fe1a97c8e1b78a0b0aa87e0633b10bb0d02017d6a46478bd5a7fab7b83c6f10f4662512366618fb5e6846eabdd6bb079aa1e9f2271728e8216867602	93	\\x00000001000001008e15c5f793e654ba2cbe6d840213c3fadd03e7a9f19beb91e600db9e872494bb96a2ac55c88a5b22c39846092f7207c765f8aa3020262613468302a51f0c207614a04f674773649945890324ad629e1ce2b78c7d150687a4528512dd63dadc2cad078f150c3cfeb48ad1779f9aec5a280c071465cd94f9479112b22c3989c778	\\xd3c9f69a147c574169fdc759ead47bb9559d903ff329af280c5d6d27f2ee7296390d9139634e189de5b5f63272538fa4532d51415d3a204f3411657db7311895	\\x000000010000000135d4c8f92196268a4c73abefcff834690ac9a18af30835d82d0e71a15d0deec3b0ec9b8190f7e47adc79723423694075a33a7c44413918545d299a0bf0829c6ca6494e9aa07366f739f23ced0e4d24c8dedaf693c513286c9fd3a213b9dafac92106f13e9c08551dbd3c0b66c2a49ede7b289f20927679a3d11b4a5cf67063e2	\\x0000000100010000
44	2	31	\\xbf7cd10a6ce6e574ddc28995a7928d96515ff8c7f3ac04db8c62853c9673d688e46605e743dde1597e8ab3f331224c6a0447573fb763f85fda51f0c09a350104	93	\\x000000010000010013b1fc36cee759f4b156dc0b39c5a90b239bdcdf78899e6349ddccc4e9c947fc224d1db6cf08190f26943a5cea47d25806a3f14c6f2e6a994ab7a02b20dbde9fe4e254d6cf0c69759bb820b718161cb0def8448142e8b381b0aa5197a786676f378ecdbedcaff0790efa7f85dde4b8e8903325d8b97b7ba32ea01d8a411bd3e1	\\x41fee2d8cd4db9e2e610f5800d9e5d2af700cfa6b4167b0d5e46638e9112134a9f69e1e16da707b3661eb470d1687e3b21e18da7215d0e32761231d10af42a29	\\x0000000100000001a765eef4372bafd01d236304d50f6ccd64d35833c8881d92c29863d659512a89169948acfffa84b95023f0ff909470a16553de7861823a0106afc8e2d4e2ff91a273bf2f95c20f2f2ef2de37362da2afc915b9d99d60b5e34bb9520906e451dbd372dc752303d333d0f7a665a2edd3a965a46e483e5504d2b83b324178d28214	\\x0000000100010000
45	2	32	\\x5f61d56600cf074865d89d20840152999055b18903e58bd404239b25434a523a4c629bbaa640d81ca109b2d5f9e3421d68166803ca4999df7a699df353efa201	93	\\x0000000100000100ac311104f448a46bcb3ee7b8c7fc0f3e9822f2d5117e0a20c44c0bd365b519786423739d3d5659b0cab66e071f99c70bab513eb849145c7757bbf55e607f10ced0562aaac784ca08aa6bb624e6219398db53213c79967726937c8deab1575566279c1cb4a85ed4feb24c82dcb928991153ffd390d8c864b722da36757739f47a	\\x8dd91d26d987b1cefd8b2fa1d38a0333eb4e054af329ad20c80b7f63c62c3dfc1ea135499402e841ad3be88fe3ecf02bf14e283a48d8c9ed2065c280acab023c	\\x00000001000000018221d0341640e92227fd7a14ee14eb0b0026c27de8bf6f7332ee180568c41095507858f86413b9a4930afe850c68e0b036ebfc299d0530a2ef8820181ddfab0aaa625c91fdac412cab1368ace2298c82e7fd4ce18e4fb94eceb3057b24d086dec940b8d0d1803a4b3a23ebe91d26664d3c51c04a40efcf51f8926fb10abfba37	\\x0000000100010000
46	2	33	\\x26d3391a05de12b422200cccf0ae05891276055ca13fe732f876e4e0b64ab54e0f3ad43c97f6a31546f41dfa8021ca2858c96f6def8614a08023b6719960e805	93	\\x000000010000010088255f1bc7479169b6c0ed9861b6bc45d26216592b639010938ded43f01df863b7acb091ff30a2c8c068a4c71be5a3b9bfd1163f480eb55dfe13e2caf7c5b15ac81863ab61cecea3a99b95dfcf95a52fb7cb4941660c9525f7118618ad510032afef0a0ae548eb8854d32ead64f9f6d1c778798ff482082bed24ab6d682e5668	\\x525b8ccec1426679c296fbbc8610fc6022ef336c1224fcc25192991ac7f7aab373a67e8553d627b8ecbd2c6b313e8dd610ad114bc5226b3d9424e13351f62ee5	\\x00000001000000012b7db2bec559f9bc696cbce0cbc63370c3638f95f77d31c316513516789f55663ce6889d2f4cca717f74a6226843e58a45132961acdc8d2bb015ef8a1d6a84289953b34607e16cb8c5db628baee6dc82c7d82ba58023fd810f191ed0277ecf297983d0577cb4e4908fd686e71fcaa8e957fd2299f604794fa658f54dbd4e920c	\\x0000000100010000
47	2	34	\\x86e59f2f81eb01832466e6ca19c5b63a6e0d430901c3c3c2f334860cd784c6c11b469f2c87bbf3fda4a5ba113471fcfef196f57cb086b17e2f814ec0e5223808	93	\\x0000000100000100c73acb990ea37118aba58f6d44ad6e18546d3ae5271f580722a0745f46f2ed3a326d4f5c4ea79d41b7d446d06d3a0ee3e0793e22e7d2184998a5a0bc6eafa0977da4ff1c4e56625d7e72c99da6d9950963815b39c66b0f49edc8f2438f4b3f449ce7c14a82e7c67dfb6950678137171ec0e4921f4b9d5893d9f4d51c9c2d3b1e	\\xfc6fb3ca16f0d1e00d6cb1c3f46837c215c614a6c8cd72ccd6c78db8d2ef5f383bdc7b987de76b4e83427f8d25b2d560d1ffdb8a78cb56bf2cf6da40f0dba595	\\x00000001000000019025aaf5ce2715c73cf80c54d50d16ffa1b1f3e3a3fd67c87903c225e7f4716c6d14b1c618c560d1cece4f5c15a29a3bd3b194185b7136f17111037d9f12dfaf286706b54c6ffa50ec0d0d72e0f5fb5b3ab3f4435d8d16202387728736318e4b24ec210b74ca638a29e130617fc64d5f8be3e73813fb0c709acdee7991c64cc0	\\x0000000100010000
48	2	35	\\xb95488ba2e3520ec8f7008c32841f9741b4319e4032d07927f93aa244034b50e2ff04b790bca748d630ff84a481e2e35be1cbd2f3c5ffbffe0116996795a2b0a	93	\\x0000000100000100b63e67d098a83e636d2026b10ff195845e109522456457cb8980958768c232973fc932808a80b5a177c0d081a1219b4523c09d9c74361d7b20def665678a8fff4f8abddb7c012b6c1655186ccc45dab048186259560838cb6627d6523a253f4ee4d8711328a551da963f8e164fd11afcac369a9246eee6dee545a20795f8cce3	\\x35c19551e53f8b86029212ee1fae7ed2da418c8017cbce735a725eb4d57f597d7c90cf213b14d493a4b480d753ab21c3d4c9009c84c26a081c3c196e8b9158cc	\\x0000000100000001884af5b242bbbed09437db40e5cfe079609a824635a5dfb565fddd557471ccddf77c40416d735dfc802e5217e294c0c8bbbc4cd10d6c1a80f3b0a25400cde01da797df453861e0a265d97064cecbe9c8d8d93ca3876efe36c4e810d72f786d7b60f062b9948ea4ec43c598546a66c14c4d47601252138e4b32c96c22ef58b47e	\\x0000000100010000
49	2	36	\\x09094b50d1efa09e66e83d5e3d2cb71e3c356fb84e0fe5fbc77a77e301ee556219eae49e77bee4dc9d4947f98e6cfce9631cdec94c198277e4b8341116ce7002	93	\\x00000001000001005c6881251bd9b0a82c50c8a9af89c235d9df6f022e00e8de893d3da90fbc8d84bb8c4c1e2dadbcbadb293aced06bdb31f787eacf19bfc0cf471acbafbd1782f91527b80a459605b2b72b2ac1b25bc0627accc2faa85eedd26fe6e25934e5b62394bd6f72bac7344a7826d9f83c5f096aa0bb994c2d8123c777447b150fe8f3b7	\\x33ab627b71e0cd51407d9aadfa7fb58ac92f0632c672541e74c1ba7aba6f85b95f0c887b92f5efb324d87bef48908a1ed07740e5728399c167bda9d825290c5a	\\x00000001000000013d50fea0e94686fc60224ad46a21119a6d8021bd436a9ae5cccaa279a90203387798ac9c2969471b00b91321ed5c59d052468c3a9f64d1705052d7821482e90e7a7c28e336b934dff1e312cfb4897a9c2a14830fe13126008a5c631a1529c8f8cd016054eb48664b36341b24f788fddf6025c68b175d2c58c049e9499974a3b0	\\x0000000100010000
50	2	37	\\x5e5f53383c9b10e45fb8f7c25cc83d2fae6391acad626e68cb7532a1ad43fda266423143eebd86e51a3444d40dde81ebcefd372e08f81ea49373f8091dca1302	93	\\x00000001000001005f618bff93a3f42ed246019fd53c4079008a8cbfee36ba7384dacfc3cb5e9982d04981f3262a247acac7b6006cc07e8ba2c32f467c6f1726886746ac88c0698dac3d1494e36bb00fad00000f7beb73d5d6d20078c2a4404bda61b930de5385b20b52a0ad106cfd31df8a60a098f2ea2a578349125767e5e132f7557853534375	\\x96bd91e44622625d03fee83ed2f6a6bd6b58b84f426e244c8291b2dfd91c713408eebd5a416a4e659c080d986b5bce991b1cf329154579bcb3b702272dfcea96	\\x00000001000000011fcce7952af0e92cede3a2ee077ed67aa52227b9fe090b6d48d679968eac1e05408c006ce7e72ce37a25dfdd8a06a77ee148cbbab927f75f9882af3a9bd0d7bed9b83a4a2d0a9d04da96597a0cf9a5dc72c77347e52402327a704ef4cd35e8e1cf7b653321dc225eb8f34bcc8c19d0c63e0422c51653bce037b5904fbe9e62a1	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\x22cbd53311e9af3e964d2e957203d515359d881b2051fe720624933ea1221d20	\\xca052d315cc6310288033d8339b73038f9b4ce0e256ad7b6382a50a55ff6645994cc43c5b44a44358673896462b575b3f3d2c9c28637da23e4cf5a5b8dc0c013
2	2	\\xb00fd5aaed212a27053147eed5b90980a959af30f1231e5f36c67ed2d404f623	\\x2922f957d664aa9b268295d040e7accdc59bfbbcab9e2c456cc9f66b9aa62f720b7a923526035b5f46a5c15d9e9047a48fe3a6f82cffb9e579bc4aa0c1b5e5f3
\.


--
-- Data for Name: refunds_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds_default (refund_serial_id, shard, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
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
1	\\x50c2aef2d4fdc31866ba1a31308210367035e3cabd6d12ff37dcd2ea16745fd1	0	0	1650631845000000	1868964647000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\x50c2aef2d4fdc31866ba1a31308210367035e3cabd6d12ff37dcd2ea16745fd1	2	8	0	\\x7c7d30f9b925d63005df451b7e107c8363e981b0b058ca13966748bc237bdf92	exchange-account-1	1648212632000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x1f2ac6536d51758d2bc777bfb7240c7e5d04053b83bb0cf73a2cefacaae7c51302fc51b37a39bdbe811a0b825cf2aa5dcb1ff8fb1615e6ded5ffe43e43f751e9
1	\\xe4774e6807e92490be3531734b0bf6e0a77910edf0a856cf71eb0643fe3566f5d7c75204fbca0040cfc16d9caedf131807327d8c9c67d8c99b3b095bd9caa119
1	\\xf532301dbeed49172bf684d1ebd20aa3a62750a31270678aacd2a4f02944eab1479a631c26ac99d38f0e8c594c67447b56da8eed046a96aa0e405a79e2f0b3fc
1	\\x336d6477cd0c9f96836b00a7eeb4196986f6ca4fc4392e1ad3f70a7fa990776ffb06d62d91b40a0f237e7042df0cab0f3d8ce90e289a437859f5bc6342b0d83b
1	\\x0fe43ec41a090af010d958435433f30a054409322fca2e57c7d9f6ffe528af0e10fd243d4f2e897048836d91a13eedc6c1fcb47310e7b476cc7f0af3e06df857
1	\\x66c8e125de7bee26fb9bfd8aa9248e84e4bb3f2e78ce4f9b7aa617c46d1b9f83321dce7aa9c649fbfb08044a59a587b186ce423b82eb003908b17d70d165a50f
1	\\x0be9ee8609d9c4101e1c2cbc7ca78c75aa9f137a0056c1a33d0ca84ab60c961bf4378422d8bcab0d92b7600a2f49128017626132ee06ef38d62cf1ff742dc0e5
1	\\xbc0b720e54fb3a6b59d1d078715aaf3bdd09f9003d343f295a2fbbeb4d55930e9d3442ec5012b963d37936fb7a3d12866c4ff2626b5c5d5575522158b759311f
1	\\xde11fca7f1facb21dd5c52e05e535fd045136622ca8c6b0355edcb6e533859cd8598ad4ae8440d6452c03386fc68b97d5195f3914e40b576b78a9c0c050df0e1
1	\\x3a88c185e001007e243884b6015f83a05f0b1856429e7885477429b6efd0cc9147a66d56078b6fc177eb952f24d186f02b0c9dbb817b786fc5effbf8e4e27c2d
1	\\x69d910bacb8687a222bd53a26d5e0bd1ac65c6ebe40b2fbe7ed083ec71c44b6c3e4deb8eb9adf7826aaf4ad37873df71e60fc2a119e8c66950c88c94ad542d25
1	\\x5c7776416afdb2d97c1db8d48db2fc77d539f761c5cead139c7e97d0b3fbaa745ffb1768c153a81b8a9d3dc9ea494a4953c6f12b8ac92377203c9e7464a60f09
1	\\x47d6fd99d20c78075fda598bff4e5d9ddaf3e5c921cdfd74dd4def0749dc60221887dd185f1420165728e6ac8eeb7faf89d3d10cf29014fb2441c0cf6818f710
1	\\x8024bcdf4dc3e1d8835578f0bde1f99e9aafa78bafa74640b1a7a59f995fbcf610bcf4f41154691331ec07c410be8e82055765e14ead5d96c6cf58dbc4406ed4
1	\\x75d5e7f83ed37453fa5ed4671a82e13306d8aa035a396c03c0922804be10146662ece081c03f7f5ffcc75b0cef7d141cf510008155e2ea5867f6591aeb541bc5
1	\\x649d89bfac5dabb3648b8f9b27bd4d4fc5b625c86b3d699228f40b9126f06e7d7d7fea449ec5a94b5f2dba9eaca878c2de1487c56ef49477da1fd90c5961a71f
1	\\xd4387511f000c26d23e6c2e13932c56cc30b2eea11b87cc18cd14ec25a235a2c978c44d13454ae04d44b5e4b2c95a5ac3963379159614645f22481585f75c607
1	\\x4d5feab3cbba0fee4778807cb1fcc7181b022f2a7865ac34a9e25d90b778a71cd8d7cd245705ca74521cc4fe59ea331f3e9b6074e2643d0c94f35872ffbe9572
1	\\x7544a344efd80041ce0becc7528ea9d0f4f30b75eac1cb6c2675d15c07ac554caac3f9deb68a67b620d78971b671bf66847ec21e6decf09e409f69ae54fc3ae6
1	\\xb430a20bc0e567b2dbed6eab0aa81f21bd6d64c668d84f646468ffb9d735aa41fb508b0c4c3564bef1b090f5e4d7c29e159b5c969d86b0b23712e7f27192ce4f
1	\\x11668232b7c9a0c8f76cb63688f662aa6abf7974e30d7485c483f823c7bfbdaf461d3ceda0bfec8d9f422338a9f716f7119aaba568e52e3ef8b2aaa21bf3e3c5
1	\\x6c4ad95cbf3c79d42f0967e8c141b5b7f96244af8e3d85fed7420752a7d920823eeb8df586b3dc8daef652f38ffc78382285181958129e87d58014c4965fcdef
1	\\x6850f943c266d8655f98f46766d8f38d5aa0f400948fa9d3cdb33ac6d8d2f0a6fa4159bc729b1427d3d7b6f3f770b2a8761cc1f234c8969c816bb0d9b1ceaf79
1	\\x062894678f50ca1dad56b41f731604ca847b5e044c7a7c11b5ff495df31b095068de57ba3824adfbb7f34fc551353d3f187ce8d8aee5736e707b9a3a019ea1ae
1	\\x2ebd34746fe7bce98aef6266c35c5c32a57316ae48f13e9b1432806c888a1898daeba6db4164ff523eed8c98e685001f838ccba15e133c43829afe2c4a6e8a02
1	\\x8a540a3e76c41879387956dab3c83054e0e51479bd757a4a5852af23fe02446be1dfa8ed1f6a1945577c98731434fc6f35ad98821cc08305c4d3a5e6a69dfd6d
1	\\x8bc0d179a111ac8c154152c1c5cf5433097982bd7ec41875f1a0a3332dbf589b484710a9e60145a5d67228aae08db4b4b65a0cd248cb579c7eb3b1b07e11e9dd
1	\\x504a289a34cdf49e7139bf8ccc85ee520339c6706a7e958e90798dbd9b162b2b52fa7d4b8a4b2229a60b419f3da24f1ee62f21bed8e19858a21f76354f2a0a99
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x1f2ac6536d51758d2bc777bfb7240c7e5d04053b83bb0cf73a2cefacaae7c51302fc51b37a39bdbe811a0b825cf2aa5dcb1ff8fb1615e6ded5ffe43e43f751e9	406	\\x00000001000000010c0ef664893a1e3d135350a4a6da335bb3b2205823e723d80cd45dba24b2483bf56ef08eeebc29d5d28f8cd552879fb88a9cec1029e985b6e782621aa7780078acb89f778e7038f8c2101a41be43c5baf4534516fa50d21761803ea8538cbe667f3a15e5f7b29df27a4f2440e8ebeb6c701d765d6fa5899faba35296d583206e	1	\\x894530787507a62cd6d2c5288b697650f51d1b4d335369cbd56b295a22fc360111eef0854b496b2250492d3ca6e112ebc6330a4303ac7c92a4a6f085b489fe0a	1648212635000000	5	1000000
2	\\xe4774e6807e92490be3531734b0bf6e0a77910edf0a856cf71eb0643fe3566f5d7c75204fbca0040cfc16d9caedf131807327d8c9c67d8c99b3b095bd9caa119	99	\\x00000001000000017fdd245cadc150092970bd620174056257bdb0f5479e0fe95b7df81a43575260d0362f7f835b118f350474fb6ddfa51c92b27c5dec7df7990ba356aed071cc2aa35d0f0e5b3ab5fb7b6a22a1b4a901fd6a77b57090d057e5f7940db0dc4d7cb658d62f6a00852bf91a1530767ad89210e8b164f4eaccccbc5905a71be1c590dd	1	\\xa7a356bc106e3f8d8f437b565bc13097d9f4b672a496e27d3851467df33a249564b5f1f7bceb58b4e4dee96c478f1af53fc9f08624f57e41cf15939bb2080f07	1648212635000000	2	3000000
3	\\xf532301dbeed49172bf684d1ebd20aa3a62750a31270678aacd2a4f02944eab1479a631c26ac99d38f0e8c594c67447b56da8eed046a96aa0e405a79e2f0b3fc	131	\\x0000000100000001940f35a809bef45eb15695642935229c11b7943c69979de035dd05204058056ed51af37114b6d2185445b8da1f0c43a59258452ec5b5adb3700ab4141ffac426bfebed06491e8f31cfd4c9615ed0b53a5fc8c724f28aa7e6f413b1b6ef69dfae2255fd4733b9a7a16936bafb02cb26b86dc7ca54346deb5eb514a5775789bc0f	1	\\x13ebd0839bed7bf9eba447b0fce4b6e91459d9e458faa3dde7528e6f750d123d85b80291fd715daede45c01f0b984dd2a1a8658e7bbd0b791aa1c719eaf2dd0f	1648212635000000	0	11000000
4	\\x336d6477cd0c9f96836b00a7eeb4196986f6ca4fc4392e1ad3f70a7fa990776ffb06d62d91b40a0f237e7042df0cab0f3d8ce90e289a437859f5bc6342b0d83b	131	\\x00000001000000015d98aee403df10df45b5c6f2f9e117ccac595a63f8e44698cbdf0762d850dc4985124e982e713602366ef8001250f6dd797ec8c6737ec63b446a28e97f1bf00ff916ae656550e868cc90e65872383fd847d84e9b349c138bec4a4c1e52615821cd8d68b9d30861ab37773d3e25098fb845849800ae7b89d5b89ac3d477ae6385	1	\\xcbd4d4190ca9285f69e8c5fc84bce43afb6300cb75ff35c11b6832e19c0de9d617b9b6edb98c49d1ca1431824945a8a84e2f23eb2004fd94826f1728312de002	1648212635000000	0	11000000
5	\\x0fe43ec41a090af010d958435433f30a054409322fca2e57c7d9f6ffe528af0e10fd243d4f2e897048836d91a13eedc6c1fcb47310e7b476cc7f0af3e06df857	131	\\x00000001000000017034b18e4775e85826444f0ff828f93224819110523a6eec93f53171f92456a800b340717ffde5f151ed4c98cd313d235909a77819e0adc79057590dbe913d59d406c26be71ffc8255f98ccb69e5fe8030a435f94df7a07b127c71d1516fed6adda7ab38d6f55c3db8eee15e38f1368c8cf04755346fb925ef59270b8740c190	1	\\xcf877c430178d4452e922991448da88114b77edaa35c260ad990b22dba747ae44d69f659ff234d58abd131806202e2e1fea6d64c43772d156bdbc462aa7c9b05	1648212635000000	0	11000000
6	\\x66c8e125de7bee26fb9bfd8aa9248e84e4bb3f2e78ce4f9b7aa617c46d1b9f83321dce7aa9c649fbfb08044a59a587b186ce423b82eb003908b17d70d165a50f	131	\\x000000010000000108d7e04027f410f7b5ee3acc7affe428ed75df1568900b1de2f950ec76b7c7cc57f0e9b861fa967553a440039dda40a3bbc3adc436e987f7593bcf9df1d0dc7c2bf047e91f4f3aa79f4293e67dd3eb781a62c9541bfeeb9e849ca11b9bfbb0687a048b964fca3af6414ff72bd6c6fe14dacda4fb5d6e813f5da2bb3087aa61e0	1	\\xae88ca9dd1a24946e74e7189bba71131d4d5dd3825e65a9890810a2dd5b6a772e3ed640d024a3882b09674b2d900a044efe36d6d986aebdc649adee7c23b350a	1648212635000000	0	11000000
7	\\x0be9ee8609d9c4101e1c2cbc7ca78c75aa9f137a0056c1a33d0ca84ab60c961bf4378422d8bcab0d92b7600a2f49128017626132ee06ef38d62cf1ff742dc0e5	131	\\x000000010000000152f19fe93842e2e6b558149e7ab382c3ba8efbf6969e2f7d68d398f4967b29d836e95bc45b67828ba8f156012a07330e72a4b4542bfe4dc14b7d2ad4abb410280f6833d7daf13de38c81b6900a8bb155328faf44bcaa70fa40c39e13b9c3272452cd3ad8cbc12f4eb4eb1cdfc9d58ea41c92887f6df33e8b5644ac5df86ae531	1	\\xcb17ed1830233345189d1cf29e5c93ceaad385e75b1a167468d9d096b94ac0e977937eb6f12c16c5cd0dc8546f66b9f8c56798c9839a2516afdeac9ea7600204	1648212636000000	0	11000000
8	\\xbc0b720e54fb3a6b59d1d078715aaf3bdd09f9003d343f295a2fbbeb4d55930e9d3442ec5012b963d37936fb7a3d12866c4ff2626b5c5d5575522158b759311f	131	\\x000000010000000153a59d9d9bc8186eae5a0c9782b89894b47c11019327634197eac63266a737bcfc2ffcb0de1906e08761dfb7ec926f2e08adcac0f950e573033db9736154fec8a24113c0b13e554c9c9617faf381d261ebc05390cd3bf5de09c8a72d1407f44f75635d2c0aaaafb949d51f90bca4b08dc5dec0a8810a4c5819a50c31c002ff65	1	\\x4487611b8b2fd2c777bca571b1e39f07171b8b03a2cac702ebf06c52ab8f7225c671d0de31675385de919c7fa46be8d94ab9227820c5fb606983c6faa574fb03	1648212636000000	0	11000000
9	\\xde11fca7f1facb21dd5c52e05e535fd045136622ca8c6b0355edcb6e533859cd8598ad4ae8440d6452c03386fc68b97d5195f3914e40b576b78a9c0c050df0e1	131	\\x000000010000000149a07792c3937d4c8b4fb2421cb4140aa23eceb1b3f860fba99a24a93ac7abafc0a982ca6cafb4ec32d9112b946801abeedce1d7bf1eda228ef8ca441b780aa995374d398e788d94e206041d327e4d1ec37487e4b22f1288c55c512df74ea3ce6c9dfde5049f9a507c8ecee6e03021f25c175872133149a3b2034107b20f900e	1	\\x6f3b9692f73687d9fa0dd02128746f0f9bd1b798217519e6880dde6448509aacfc40be5d35d62fbebdd876f7288b437917b1cfd54d7f4f72cd28706ffea18005	1648212636000000	0	11000000
10	\\x3a88c185e001007e243884b6015f83a05f0b1856429e7885477429b6efd0cc9147a66d56078b6fc177eb952f24d186f02b0c9dbb817b786fc5effbf8e4e27c2d	131	\\x0000000100000001801cb04e9445b4269cbe9696d3573eb6d99482aba4cbab73cbf5f45e6fb2c33da11a0baff2edec932a9ff9a5bafac123f525d4a456efee939eae427a14312a0c5a38d922be82d66cdeb1f59377f64113fb011884953a354b0394a380a9acfdccdf7a40c902a463baae41ec7e446c7b91e2f6a92930aad4aa8aa13c7586924721	1	\\x653a52f6b119d6e5aa4f8e76d63256d20ce254936c27ae35c3067817404cba8b602f5073760242595941ca99b588b9e6bc169f608a113d7653eb0b35962a1d03	1648212636000000	0	11000000
11	\\x69d910bacb8687a222bd53a26d5e0bd1ac65c6ebe40b2fbe7ed083ec71c44b6c3e4deb8eb9adf7826aaf4ad37873df71e60fc2a119e8c66950c88c94ad542d25	271	\\x0000000100000001ae6d43696de0a2449a526657c03a91d9397868672e7cac5c30224fc69d00fecea89fff54638a2ccb77184781c4a3851655733148e698d32f9df017aee9995055aa63738b059be491ea7d74a0aff194555ee04c400d0482e8f2457c3347397f6ee911cb99bb669188e4c8113d6fb0bc19791c74c62715b7ccef1316b350c6aec1	1	\\x2c082f7e7d29593cf070917b7d3e51a3ce77c6bb2d518da7d3589540479b90ff5e8e978ad7af89208652bb3d90d242be4c442fba4f1ddc274808570548e67e05	1648212636000000	0	2000000
12	\\x5c7776416afdb2d97c1db8d48db2fc77d539f761c5cead139c7e97d0b3fbaa745ffb1768c153a81b8a9d3dc9ea494a4953c6f12b8ac92377203c9e7464a60f09	271	\\x00000001000000012102beb9cd62b9472da3d788791d3193fbae0d7b7d9deb5ea09b9476059a80fd6ca9a88f6af89c9dbfc07ce6ea39ac9ff3e90aec1c50bd1c3853cd2e98e82cc5c26f939da27937d0afa3828be824e003707bc2f8756ec497a509bb7eb08602a8bf2afaae6dd30c47c4d44cdad18490d436c83392c4ff25e0ede8fb061e107e5c	1	\\x9823ff64a1ad1b1fefb779639914d8c48d6f7ac35f4cd8f2872c918af2ed0b6f002e542aaca19e20d060bbb82f1419c81297645fbabf6de3e21d960f1c4e990c	1648212636000000	0	2000000
13	\\x47d6fd99d20c78075fda598bff4e5d9ddaf3e5c921cdfd74dd4def0749dc60221887dd185f1420165728e6ac8eeb7faf89d3d10cf29014fb2441c0cf6818f710	271	\\x000000010000000145171152fe6253ca9c5e955722a48f3038693a9606bbc3d9222a41ef3510b72b4e50e614629ce75166ef8373c8a88f63ea5471d3b609bfae3d035f885cdd085a8afcf22564870d06b958929988b82527995c9951caa9984ca4a7130fcec6e71041ae2ee2db85d8af581dcf286f5a8ba985198e1b56966e1ba7971e19a57cf90d	1	\\x6cc551fb0024e294617ba4986d1bf2729205eefa17c7867311a99c917b0e7a75f35cea2136810d4694b9c98cf2b49af696a70088290d158fed1cd14245a0bf06	1648212636000000	0	2000000
14	\\x8024bcdf4dc3e1d8835578f0bde1f99e9aafa78bafa74640b1a7a59f995fbcf610bcf4f41154691331ec07c410be8e82055765e14ead5d96c6cf58dbc4406ed4	271	\\x0000000100000001ae39b63dca8339c3bd24588f58f18fdfc3dd9542f641a994d22ba57d08eb1ea52ed2f7c503b5cd395daf0a5f5dc694634091f28b8722c157ef5370a345a1d59227233a6d4537289c628ea988f7323f35a8e758bdfbdffae4daaa1e0dd354de0693b1c93dd95ee28731dc22163b873e33a5ed7ac0c8d5e5e3ce5f251a27b1cc94	1	\\xa5c040cff527f23845ed828ee4d3306c5e5da0529ba7044c836ba788cabad60b634844ee5e5bb028ac6680de9acd39433af7d48baf01d3d98f5bc6b9a480ee04	1648212636000000	0	2000000
15	\\x75d5e7f83ed37453fa5ed4671a82e13306d8aa035a396c03c0922804be10146662ece081c03f7f5ffcc75b0cef7d141cf510008155e2ea5867f6591aeb541bc5	63	\\x0000000100000001b429d8e999ac6540a37d2ac8290b3485869471822fabd2541ed3e89b7e524100c46bf1ed9096b5acf199614bc16909d2652d78d465c84268d51f376bb022af2947915d3463e1abc83460318ac2880a1faa201d16c72eb1603cdda62622af129405227fe66e1d91c756366a3d75c3be37dc3deb630884a49a0aefed8b55a0612d	1	\\x5ce57d2fd3e3377159cae405140f29f20c0b4b654ad0d2fa16d8a4cc19290cfea4f20f65ba0d4b5e0aa750bdabc7e257f99b18c8e943d78865a6a6b632ae2400	1648212646000000	1	2000000
17	\\x649d89bfac5dabb3648b8f9b27bd4d4fc5b625c86b3d699228f40b9126f06e7d7d7fea449ec5a94b5f2dba9eaca878c2de1487c56ef49477da1fd90c5961a71f	131	\\x000000010000000162debc450fd06a981c3d18222b03052474f770ec0d2ae765f3175423a93c6633243f0a12fefa60c7492801544b4211841acd68eb5d8e51867167a19de5c9798c981dfebbf4c4773badcb01bb59af085d8f6addc87a48106353826df87fed94040c55ab739d960a4038c9ffead6df738eca2050eddc8bee1cde93a6dcb8ee0bee	1	\\xf318d9a8e901b48dacae7634284d75800d0380af4f909485e5c8117d8c6dcbbcf90430ac09873d83b70a97408c346d34a8732d7627186fc2b56d654008edc305	1648212646000000	0	11000000
19	\\xd4387511f000c26d23e6c2e13932c56cc30b2eea11b87cc18cd14ec25a235a2c978c44d13454ae04d44b5e4b2c95a5ac3963379159614645f22481585f75c607	131	\\x0000000100000001b4f9059abc01e545887ea03e87934b3ed570d4e90dc2fb3802b4698bfe734aaa42525a36d0d05e4d2b521392649ae181167370259624e420a14429021157dc35478e770ab036bfdb3f3577818c6d93656431f583cb97744401a9c744f66f3bcc803b8c3368c83b7cd8ec12673f966642ceb4e8328a23dbae64fe8852591d0045	1	\\x2f30ac4fdc9a4e9e678c6101a453e6ade05def26939078f6ea05c26f97c44bedec46a397821f773821bd41957e55500e8961ccd4f90df30648fba12e8b39aa02	1648212646000000	0	11000000
21	\\x4d5feab3cbba0fee4778807cb1fcc7181b022f2a7865ac34a9e25d90b778a71cd8d7cd245705ca74521cc4fe59ea331f3e9b6074e2643d0c94f35872ffbe9572	131	\\x00000001000000016b945d40ab366da1f2d7ec89473adbd09bef1adc3590857183d3d89d1139c96a278a25d49fa8aa099853e6ce883388cf483d31ff7e1c23fcb1d0f1534e826e1b846c0c53088293b77d2886e1f0486cd4605538d7e533c75cc349ca5e53bce3a093087d180d182f364b8d5017d5fbb5675c8cb54b8f24f32818c492e2dc115b61	1	\\xd88ade6884d10f86090f82ce176d49b235c628230a4e1ca8698a6ef505a4e56caf82205e4c181fd1602903fe3e4d4c88ea6429adf26aa6f1066a9bc5d876030f	1648212646000000	0	11000000
23	\\x7544a344efd80041ce0becc7528ea9d0f4f30b75eac1cb6c2675d15c07ac554caac3f9deb68a67b620d78971b671bf66847ec21e6decf09e409f69ae54fc3ae6	131	\\x00000001000000015a3e594d6e87a7a1c78c9878931294bb8748b45b7f26654c9a0b67b580bab6e60e8aee9ebbdd9ea9cbffa9b018c5689aaaf093d62789d8491171bfab215ea8ec877709055c85f7c08c2f437bdb420e06d1dc8020d59ff354b5670475fb262777d19f7d058835c2490372ece34dcaf43b8cbfaeb6d187e6db6d450dee52dfc9e9	1	\\xa7f27af2d49aab34584732573ce1a5c8ba8e416bc630abc71ee1cffe38e17c62c1b3ac4bd80150d81f780546b0a0f34834b302b4cd082ade3227e06370880c0f	1648212646000000	0	11000000
25	\\xb430a20bc0e567b2dbed6eab0aa81f21bd6d64c668d84f646468ffb9d735aa41fb508b0c4c3564bef1b090f5e4d7c29e159b5c969d86b0b23712e7f27192ce4f	131	\\x0000000100000001494cbf1241ee1dd913d8e7b94b16cbdb74edda6a7051fcbe480a644045026e4bbb9d4e71a0cf826493b677a63ba00e70dc28600638936951db5acc9abafabd1d5fdfe5f7a873d10b2e3cb99f4a9c2cd4136639dc141e110f9cf46e09cda80339a49d5462f009436e0dee9640476abd806e5ceaf862f8eef057c2a78d8752e83c	1	\\x12545ce6ca6091eedfe217eac09ae8c60660dc45c86d9838b0aaed7e229967252aeed8f24519f14b781d25406722430c2c7c03e5c5bb0a7cfce4bd1418015707	1648212646000000	0	11000000
27	\\x11668232b7c9a0c8f76cb63688f662aa6abf7974e30d7485c483f823c7bfbdaf461d3ceda0bfec8d9f422338a9f716f7119aaba568e52e3ef8b2aaa21bf3e3c5	131	\\x0000000100000001bac15ad7d344a7e2a4db6ddfa71d182015b04acf1754663c7fc54645899c2aca8d44aed12e211d19deef923ec79183bb0301b4b0c8938157ed4475d339e9c0190f465e12a5cca6eabfe4f6f31f134b31db8f4cb853f3d0265c05adffe331f5309bbe6dd62eab744c57ce82ad5388b0ac5a54bbdf15083421eead6d80904fdbd6	1	\\x5f7cc49575f217c67e2fee595f8360cfbc413bf89bfc072bc3949be33257c58f080740cd2e1e90afb9617212fbd810af6ff509ee5376386166fbbc276cad1f04	1648212646000000	0	11000000
29	\\x6c4ad95cbf3c79d42f0967e8c141b5b7f96244af8e3d85fed7420752a7d920823eeb8df586b3dc8daef652f38ffc78382285181958129e87d58014c4965fcdef	131	\\x00000001000000017b359dc67ce9b23baafcb87907c765dc21b8d845c33cb8b3a36d049118495d4848c5efaefc735583101c237b76e44f431a332516dca30e1f023024af7cbe2686039b59b85ee821e9e20bcab689a23f0540ac0b53f6f6496cfa15d6607697e7a8b9669d7889f3cf7629a8e9ac2e52e6a3388f6b89c4283f5bc520169bb85fb18c	1	\\x3a048f333e324b289ddeb231138397af6a9a3b87ccd9c562f9efdf286564bd869488d11668a52d54aa25ae34a091f6f7cede064c1456821a7803e9c0bec8a904	1648212646000000	0	11000000
31	\\x6850f943c266d8655f98f46766d8f38d5aa0f400948fa9d3cdb33ac6d8d2f0a6fa4159bc729b1427d3d7b6f3f770b2a8761cc1f234c8969c816bb0d9b1ceaf79	131	\\x0000000100000001470b6ba832e4ee7b78d4d8fa79deaa643d2cb1fa18ffa448167534cfb5f63dd3661e572f844dc8530c9bd5503b24dfa4dbd57fde95a7d1f2ab6228d3854b20430346329e95c526c264dfe452e2478de6583670096415be6ec93575fc13021a19250e991c7acb188bbd8293c95cef48dee044a27718d896eed0579538239b6904	1	\\x59203b0e6ef2dddd0920ba13d7c121bb753cc79be52a5ab2023b8faed32841622d1b4c7ffb6c15a7402e4e8eeecdb0df3b5bb772b46c8a425649dd2545e78c02	1648212646000000	0	11000000
33	\\x062894678f50ca1dad56b41f731604ca847b5e044c7a7c11b5ff495df31b095068de57ba3824adfbb7f34fc551353d3f187ce8d8aee5736e707b9a3a019ea1ae	271	\\x000000010000000167783ec53827b6d3553107a2166fc0127df4f127264b71bac76476f953e3e7d70ed45127761c2912b35e48a16a95dee55efd4eeb54afb8068fbec7bc17c1df55050f0f890cda9ed90b564498d8addb62ce6dbbf3f2ea8bd9368db2a6d32b97e243a74ef2b10ab6f6576348aea07d2489d3ee1313f646d2bf5f17b292a8de0f35	1	\\x02a47d8f78bacf3fb3396ece1c17ff2603852760de69c479696e529c074264cb67b021b63ae695c35203dc7df3539068ed904eb1daf42584c1ebde05c50d3a0d	1648212646000000	0	2000000
35	\\x2ebd34746fe7bce98aef6266c35c5c32a57316ae48f13e9b1432806c888a1898daeba6db4164ff523eed8c98e685001f838ccba15e133c43829afe2c4a6e8a02	271	\\x0000000100000001072fb70a0d2cdd636326ecd0747f8e383423376c54b82a5dee90a92142704a1afd5ccfd4ce006180e783458fe82078f0d221e0f40170509ba6292872079fad7b6d14c4513f014ee417a55f9dddd86a2eb007f07d85a38ebb1616ccd61086f49b420b5b4b38157476cb361f240ae65661982bf5de3a8e4ab17b6e9f45d8c43216	1	\\x69fdd3a3ae499bce2aa521f8b0666b46268bcc7489cd616c32950c77b88e2b286a5e991bc6b0d90f1a455f90b26fe0945c5f4a762f05c9a76b1c9164183c7d09	1648212646000000	0	2000000
37	\\x8a540a3e76c41879387956dab3c83054e0e51479bd757a4a5852af23fe02446be1dfa8ed1f6a1945577c98731434fc6f35ad98821cc08305c4d3a5e6a69dfd6d	271	\\x000000010000000188dd53b8a6f64cc369b8a40916d98dbeacadac059a5d73c07d838e8adcf77c8a6a4066d5a9fb59d1bb5dbfc785bfb4bcd5cfd8a81f393bd0a70cb53111191200f14e5cb3aedebada92e4df9ef5d1e8a6222655cb08fc961c2d12a87607f3dd22941e3afe401c2f65fc0ecc50d8b6c21fdb73c05519df664de9c06a5e0714ca22	1	\\xa3a28d2e637c77dd45496065af0aa109121c152295d8e6c9b8382e9cc338ce3ea4c53c3c5b0048da8f00a21a6682702dacf95604ce2df0755115b555fe11a705	1648212646000000	0	2000000
39	\\x8bc0d179a111ac8c154152c1c5cf5433097982bd7ec41875f1a0a3332dbf589b484710a9e60145a5d67228aae08db4b4b65a0cd248cb579c7eb3b1b07e11e9dd	271	\\x00000001000000015cb654306f540487091d6ced4d065d546dfb41444a98e8d93fff41a3bc1bcfbcedb2b7b8de3e5d3d9d96decf2263e422ea628b98388eaef5d97ed909bfb0bf1327580b0c45e991d849e3188568c01a4d43d7f672eb6fd5145b1937da9d39db7abdd958654900475fb197a7a765befd58beb7559dfb63a8ec8fe141e8dce10efe	1	\\x29b5cd84fdd61594ba989a7cf96140fd9a8165a0fc642e64677e5fff30f2f1e4e8dd9676b0acb2e1d43f17e750ac5fe24086ea5a00383adeed7e52651f65ee0f	1648212647000000	0	2000000
41	\\x504a289a34cdf49e7139bf8ccc85ee520339c6706a7e958e90798dbd9b162b2b52fa7d4b8a4b2229a60b419f3da24f1ee62f21bed8e19858a21f76354f2a0a99	271	\\x00000001000000016d98bffbc3c0dea62a9800164f6d045f689c5beb315a241ef759f90d5e280011b0d561ecd91009b7a2f416480f053d76f8d4844c4c33a914ff97777a77e8772923357318cffe8bc5e2765839dd0cf6abe3e73fac4643603d875526b604ad9efebca3aa6ab0d665c45a586ddfba8a180adbfa7681a9e5b4c951c01e093162003d	1	\\x647fcce620897257391d130deb6afb7099139d6825803e2930ee226351e8a25d5315943d8ff872ca26d0bac3420a0fc4020d54028457a9ead1db7d393a10e00b	1648212647000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\xb6e1ab401db0013e87141e7a7d8d56309d0d4fd88266ea2c810d644a8968b74851519d94ca981676f982e2103be4720ca55bcbb36a6ce59dd386e61703767601	t	1648212625000000
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
1	x-taler-bank	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x900eb6a9b646d52b7ef6c2abd4377aeb32b9019bfcf868eef4405cf659b8b3c15f2ce279a5f9126e8d0466f8ad215707c23acdc43cb3e4537c3859e970da0102
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
1	\\x7c7d30f9b925d63005df451b7e107c8363e981b0b058ca13966748bc237bdf92	payto://x-taler-bank/localhost/testuser-b6sz6tiy	f	\N
2	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	payto://x-taler-bank/localhost/43	f	\N
\.


--
-- Data for Name: work_shards; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.work_shards (shard_serial_id, last_attempt, start_row, end_row, completed, job_name) FROM stdin;
1	1648212618000000	0	1024	f	wirewatch-exchange-account-1
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

SELECT pg_catalog.setval('public.app_bankaccount_account_no_seq', 12, true);


--
-- Name: app_banktransaction_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.app_banktransaction_id_seq', 2, true);


--
-- Name: auditor_denom_sigs_auditor_denom_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auditor_denom_sigs_auditor_denom_serial_seq', 1269, true);


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

SELECT pg_catalog.setval('public.auth_user_id_seq', 12, true);


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

SELECT pg_catalog.setval('public.denomination_revocations_denom_revocations_serial_id_seq', 2, true);


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

SELECT pg_catalog.setval('public.known_coins_known_coin_id_seq', 14, true);


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

SELECT pg_catalog.setval('public.merchant_exchange_signing_keys_signkey_serial_seq', 10, true);


--
-- Name: merchant_exchange_wire_fees_wirefee_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_exchange_wire_fees_wirefee_serial_seq', 2, true);


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

SELECT pg_catalog.setval('public.merchant_orders_order_serial_seq', 2, true);


--
-- Name: merchant_refunds_refund_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_refunds_refund_serial_seq', 1, false);


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

SELECT pg_catalog.setval('public.recoup_recoup_uuid_seq', 1, true);


--
-- Name: recoup_refresh_recoup_refresh_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.recoup_refresh_recoup_refresh_uuid_seq', 8, true);


--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refresh_commitments_melt_serial_id_seq', 2, true);


--
-- Name: refresh_revealed_coins_rrc_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refresh_revealed_coins_rrc_serial_seq', 50, true);


--
-- Name: refresh_transfer_keys_rtc_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refresh_transfer_keys_rtc_serial_seq', 2, true);


--
-- Name: refunds_refund_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refunds_refund_serial_id_seq', 1, false);


--
-- Name: reserves_close_close_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_close_close_uuid_seq', 1, false);


--
-- Name: reserves_in_reserve_in_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_in_reserve_in_serial_id_seq', 1, true);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_out_reserve_out_serial_id_seq', 42, true);


--
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_reserve_uuid_seq', 1, true);


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

SELECT pg_catalog.setval('public.wire_targets_wire_target_serial_id_seq', 4, true);


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

