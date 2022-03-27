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
-- Name: add_constraints_to_account_merges_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_account_merges_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE account_merges_' || partition_suffix || ' '
      'ADD CONSTRAINT account_merges_' || partition_suffix || '_account_merge_request_serial_id_key '
        'UNIQUE (account_merge_request_serial_id) '
  );
END
$$;


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
        'UNIQUE (aggregation_serial_id);'
  );
END
$$;


--
-- Name: add_constraints_to_contracts_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_contracts_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE contracts_' || partition_suffix || ' '
      'ADD CONSTRAINT contracts_' || partition_suffix || '_contract_serial_id_key '
        'UNIQUE (contract_serial_id) '
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
-- Name: add_constraints_to_purse_deposits_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_purse_deposits_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE purse_deposits_' || partition_suffix || ' '
      'ADD CONSTRAINT purse_deposits_' || partition_suffix || '_purse_deposit_serial_id_key '
        'UNIQUE (purse_deposit_serial_id) '
  );
END
$$;


--
-- Name: add_constraints_to_purse_merges_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_purse_merges_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE purse_merges_' || partition_suffix || ' '
      'ADD CONSTRAINT purse_merges_' || partition_suffix || '_purse_merge_request_serial_id_key '
        'UNIQUE (purse_merge_request_serial_id) '
  );
END
$$;


--
-- Name: add_constraints_to_purse_requests_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_purse_requests_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE purse_requests_' || partition_suffix || ' '
      'ADD CONSTRAINT purse_requests_' || partition_suffix || '_purse_requests_serial_id_key '
        'UNIQUE (purse_requests_serial_id) '
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
-- Name: add_constraints_to_wad_in_entries_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_wad_in_entries_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE wad_in_entries_' || partition_suffix || ' '
      'ADD CONSTRAINT wad_in_entries_' || partition_suffix || '_wad_in_entry_serial_id_key '
        'UNIQUE (wad_in_entry_serial_id) '
  );
END
$$;


--
-- Name: add_constraints_to_wad_out_entries_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_wad_out_entries_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE wad_out_entries_' || partition_suffix || ' '
      'ADD CONSTRAINT wad_out_entries_' || partition_suffix || '_wad_out_entry_serial_id_key '
        'UNIQUE (wad_out_entry_serial_id) '
  );
END
$$;


--
-- Name: add_constraints_to_wads_in_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_wads_in_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE wads_in_' || partition_suffix || ' '
      'ADD CONSTRAINT wads_in_' || partition_suffix || '_wad_in_serial_id_key '
        'UNIQUE (wad_in_serial_id) '
  );
END
$$;


--
-- Name: add_constraints_to_wads_out_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_wads_out_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE wads_out_' || partition_suffix || ' '
      'ADD CONSTRAINT wads_out_' || partition_suffix || '_wad_out_serial_id_key '
        'UNIQUE (wad_out_serial_id) '
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
BEGIN
  was_ready  = NOT (OLD.done OR OLD.extension_blocked);

  IF (was_ready)
  THEN
    DELETE FROM deposits_by_ready
     WHERE wire_deadline = OLD.wire_deadline
       AND shard = OLD.shard
       AND coin_pub = OLD.coin_pub
       AND deposit_serial_id = OLD.deposit_serial_id;
    DELETE FROM deposits_for_matching
     WHERE refund_deadline = OLD.refund_deadline
       AND merchant_pub = OLD.merchant_pub
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
BEGIN
  is_ready  = NOT (NEW.done OR NEW.extension_blocked);

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
    INSERT INTO deposits_for_matching
      (refund_deadline
      ,merchant_pub
      ,coin_pub
      ,deposit_serial_id)
    VALUES
      (NEW.refund_deadline
      ,NEW.merchant_pub
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
BEGIN
  was_ready = NOT (OLD.done OR OLD.extension_blocked);
  is_ready  = NOT (NEW.done OR NEW.extension_blocked);
  IF (was_ready AND NOT is_ready)
  THEN
    DELETE FROM deposits_by_ready
     WHERE wire_deadline = OLD.wire_deadline
       AND shard = OLD.shard
       AND coin_pub = OLD.coin_pub
       AND deposit_serial_id = OLD.deposit_serial_id;
    DELETE FROM deposits_for_matching
     WHERE refund_deadline = OLD.refund_deadline
       AND merchant_pub = OLD.merchant_pub
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
    INSERT INTO deposits_for_matching
      (refund_deadline
      ,merchant_pub
      ,coin_pub
      ,deposit_serial_id)
    VALUES
      (NEW.refund_deadline
      ,NEW.merchant_pub
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
--         INSERT refunds (by coin_pub, rtransaction_id) ON CONFLICT DO NOTHING
--         SELECT refunds (by coin_pub)
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
  ,coin_pub
  ,merchant_sig
  ,rtransaction_id
  ,amount_with_fee_val
  ,amount_with_fee_frac
  )
  VALUES
  (dsi
  ,in_coin_pub
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
   WHERE coin_pub=in_coin_pub
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
  WHERE coin_pub=in_coin_pub
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


--
-- Name: wire_out_delete_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.wire_out_delete_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  DELETE FROM aggregation_tracking
   WHERE wtid_raw = OLD.wtid_raw;
  RETURN OLD;
END $$;


--
-- Name: FUNCTION wire_out_delete_trigger(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.wire_out_delete_trigger() IS 'Replicate reserve_out deletions into aggregation_tracking. This replaces an earlier use of an ON DELETE CASCADE that required a DEFERRABLE constraint and conflicted with nice partitioning.';


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
-- Name: account_merges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.account_merges (
    account_merge_request_serial_id bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    reserve_sig bytea NOT NULL,
    purse_pub bytea NOT NULL,
    CONSTRAINT account_merges_purse_pub_check CHECK ((length(purse_pub) = 32)),
    CONSTRAINT account_merges_reserve_pub_check CHECK ((length(reserve_pub) = 32)),
    CONSTRAINT account_merges_reserve_sig_check CHECK ((length(reserve_sig) = 64))
)
PARTITION BY HASH (purse_pub);


--
-- Name: TABLE account_merges; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.account_merges IS 'Merge requests where a purse- and account-owner requested merging the purse into the account';


--
-- Name: COLUMN account_merges.reserve_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.account_merges.reserve_pub IS 'public key of the target reserve';


--
-- Name: COLUMN account_merges.reserve_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.account_merges.reserve_sig IS 'signature by the reserve private key affirming the merge, of type TALER_SIGNATURE_WALLET_ACCOUNT_MERGE';


--
-- Name: COLUMN account_merges.purse_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.account_merges.purse_pub IS 'public key of the purse';


--
-- Name: account_merges_account_merge_request_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.account_merges ALTER COLUMN account_merge_request_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.account_merges_account_merge_request_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: account_merges_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.account_merges_default (
    account_merge_request_serial_id bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    reserve_sig bytea NOT NULL,
    purse_pub bytea NOT NULL,
    CONSTRAINT account_merges_purse_pub_check CHECK ((length(purse_pub) = 32)),
    CONSTRAINT account_merges_reserve_pub_check CHECK ((length(reserve_pub) = 32)),
    CONSTRAINT account_merges_reserve_sig_check CHECK ((length(reserve_sig) = 64))
);
ALTER TABLE ONLY public.account_merges ATTACH PARTITION public.account_merges_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: aggregation_tracking; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.aggregation_tracking (
    aggregation_serial_id bigint NOT NULL,
    deposit_serial_id bigint NOT NULL,
    wtid_raw bytea NOT NULL,
    CONSTRAINT aggregation_tracking_wtid_raw_check CHECK ((length(wtid_raw) = 32))
)
PARTITION BY HASH (deposit_serial_id);


--
-- Name: TABLE aggregation_tracking; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.aggregation_tracking IS 'mapping from wire transfer identifiers (WTID) to deposits (and back)';


--
-- Name: COLUMN aggregation_tracking.wtid_raw; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.aggregation_tracking.wtid_raw IS 'identifier of the wire transfer';


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
    wtid_raw bytea NOT NULL,
    CONSTRAINT aggregation_tracking_wtid_raw_check CHECK ((length(wtid_raw) = 32))
);
ALTER TABLE ONLY public.aggregation_tracking ATTACH PARTITION public.aggregation_tracking_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: aggregation_transient; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.aggregation_transient (
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    wire_target_h_payto bytea,
    exchange_account_section text NOT NULL,
    wtid_raw bytea NOT NULL,
    CONSTRAINT aggregation_transient_wire_target_h_payto_check CHECK ((length(wire_target_h_payto) = 32)),
    CONSTRAINT aggregation_transient_wtid_raw_check CHECK ((length(wtid_raw) = 32))
)
PARTITION BY HASH (wire_target_h_payto);


--
-- Name: TABLE aggregation_transient; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.aggregation_transient IS 'aggregations currently happening (lacking wire_out, usually because the amount is too low); this table is not replicated';


--
-- Name: COLUMN aggregation_transient.amount_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.aggregation_transient.amount_val IS 'Sum of all of the aggregated deposits (without deposit fees)';


--
-- Name: COLUMN aggregation_transient.wtid_raw; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.aggregation_transient.wtid_raw IS 'identifier of the wire transfer';


--
-- Name: aggregation_transient_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.aggregation_transient_default (
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    wire_target_h_payto bytea,
    exchange_account_section text NOT NULL,
    wtid_raw bytea NOT NULL,
    CONSTRAINT aggregation_transient_wire_target_h_payto_check CHECK ((length(wire_target_h_payto) = 32)),
    CONSTRAINT aggregation_transient_wtid_raw_check CHECK ((length(wtid_raw) = 32))
);
ALTER TABLE ONLY public.aggregation_transient ATTACH PARTITION public.aggregation_transient_default FOR VALUES WITH (modulus 1, remainder 0);


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
)
PARTITION BY HASH (reserve_pub);


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
-- Name: close_requests_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.close_requests_default (
    reserve_pub bytea NOT NULL,
    close_timestamp bigint NOT NULL,
    reserve_sig bytea NOT NULL,
    close_val bigint NOT NULL,
    close_frac integer NOT NULL,
    CONSTRAINT close_requests_reserve_pub_check CHECK ((length(reserve_pub) = 32)),
    CONSTRAINT close_requests_reserve_sig_check CHECK ((length(reserve_sig) = 64))
);
ALTER TABLE ONLY public.close_requests ATTACH PARTITION public.close_requests_default FOR VALUES WITH (modulus 1, remainder 0);


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
)
PARTITION BY HASH (purse_pub);


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

ALTER TABLE public.contracts ALTER COLUMN contract_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.contracts_contract_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: contracts_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contracts_default (
    contract_serial_id bigint NOT NULL,
    purse_pub bytea NOT NULL,
    pub_ckey bytea NOT NULL,
    e_contract bytea NOT NULL,
    purse_expiration bigint NOT NULL,
    CONSTRAINT contracts_pub_ckey_check CHECK ((length(pub_ckey) = 32)),
    CONSTRAINT contracts_purse_pub_check CHECK ((length(purse_pub) = 32))
);
ALTER TABLE ONLY public.contracts ATTACH PARTITION public.contracts_default FOR VALUES WITH (modulus 1, remainder 0);


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

COMMENT ON COLUMN public.deposits.shard IS 'Used for load sharding in the materialized indices. Should be set based on merchant_pub. 64-bit value because we need an *unsigned* 32-bit value.';


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
    merchant_pub bytea NOT NULL,
    coin_pub bytea NOT NULL,
    deposit_serial_id bigint,
    CONSTRAINT deposits_for_matching_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT deposits_for_matching_merchant_pub_check CHECK ((length(merchant_pub) = 32))
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
    merchant_pub bytea NOT NULL,
    coin_pub bytea NOT NULL,
    deposit_serial_id bigint,
    CONSTRAINT deposits_for_matching_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT deposits_for_matching_merchant_pub_check CHECK ((length(merchant_pub) = 32))
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
)
PARTITION BY HASH (extension_details_serial_id);


--
-- Name: TABLE extension_details; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.extension_details IS 'Extensions that were provided with deposits (not yet used).';


--
-- Name: COLUMN extension_details.extension_options; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.extension_details.extension_options IS 'JSON object with options set that the exchange needs to consider when executing a deposit. Supported details depend on the extensions supported by the exchange.';


--
-- Name: extension_details_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.extension_details_default (
    extension_details_serial_id bigint NOT NULL,
    extension_options character varying
);
ALTER TABLE ONLY public.extension_details ATTACH PARTITION public.extension_details_default FOR VALUES WITH (modulus 1, remainder 0);


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
)
PARTITION BY HASH (reserve_pub);


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
-- Name: history_requests_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.history_requests_default (
    reserve_pub bytea NOT NULL,
    request_timestamp bigint NOT NULL,
    reserve_sig bytea NOT NULL,
    history_fee_val bigint NOT NULL,
    history_fee_frac integer NOT NULL,
    CONSTRAINT history_requests_reserve_pub_check CHECK ((length(reserve_pub) = 32)),
    CONSTRAINT history_requests_reserve_sig_check CHECK ((length(reserve_sig) = 64))
);
ALTER TABLE ONLY public.history_requests ATTACH PARTITION public.history_requests_default FOR VALUES WITH (modulus 1, remainder 0);


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

ALTER TABLE public.partners ALTER COLUMN partner_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.partners_partner_serial_id_seq
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
)
PARTITION BY HASH (purse_pub);


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
-- Name: purse_deposits_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purse_deposits_default (
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
ALTER TABLE ONLY public.purse_deposits ATTACH PARTITION public.purse_deposits_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: purse_deposits_purse_deposit_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.purse_deposits ALTER COLUMN purse_deposit_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.purse_deposits_purse_deposit_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


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
)
PARTITION BY HASH (purse_pub);


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
-- Name: purse_merges_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purse_merges_default (
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
ALTER TABLE ONLY public.purse_merges ATTACH PARTITION public.purse_merges_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: purse_merges_purse_merge_request_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.purse_merges ALTER COLUMN purse_merge_request_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.purse_merges_purse_merge_request_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: purse_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purse_requests (
    purse_requests_serial_id bigint NOT NULL,
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
)
PARTITION BY HASH (purse_pub);


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
-- Name: purse_requests_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purse_requests_default (
    purse_requests_serial_id bigint NOT NULL,
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
ALTER TABLE ONLY public.purse_requests ATTACH PARTITION public.purse_requests_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: purse_requests_purse_requests_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.purse_requests ALTER COLUMN purse_requests_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.purse_requests_purse_requests_serial_id_seq
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
    coin_pub bytea NOT NULL,
    deposit_serial_id bigint NOT NULL,
    merchant_sig bytea NOT NULL,
    rtransaction_id bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    CONSTRAINT refunds_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT refunds_merchant_sig_check CHECK ((length(merchant_sig) = 64))
)
PARTITION BY HASH (coin_pub);


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
    coin_pub bytea NOT NULL,
    deposit_serial_id bigint NOT NULL,
    merchant_sig bytea NOT NULL,
    rtransaction_id bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    CONSTRAINT refunds_coin_pub_check CHECK ((length(coin_pub) = 32)),
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
)
PARTITION BY HASH (purse_pub);


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
-- Name: wad_in_entries_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wad_in_entries_default (
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
ALTER TABLE ONLY public.wad_in_entries ATTACH PARTITION public.wad_in_entries_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: wad_in_entries_wad_in_entry_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.wad_in_entries ALTER COLUMN wad_in_entry_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.wad_in_entries_wad_in_entry_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


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
)
PARTITION BY HASH (purse_pub);


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
-- Name: wad_out_entries_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wad_out_entries_default (
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
ALTER TABLE ONLY public.wad_out_entries ATTACH PARTITION public.wad_out_entries_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: wad_out_entries_wad_out_entry_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.wad_out_entries ALTER COLUMN wad_out_entry_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.wad_out_entries_wad_out_entry_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


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
)
PARTITION BY HASH (wad_id);


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
-- Name: wads_in_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wads_in_default (
    wad_in_serial_id bigint NOT NULL,
    wad_id bytea NOT NULL,
    origin_exchange_url text NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    arrival_time bigint NOT NULL,
    CONSTRAINT wads_in_wad_id_check CHECK ((length(wad_id) = 24))
);
ALTER TABLE ONLY public.wads_in ATTACH PARTITION public.wads_in_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: wads_in_wad_in_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.wads_in ALTER COLUMN wad_in_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.wads_in_wad_in_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


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
)
PARTITION BY HASH (wad_id);


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
-- Name: wads_out_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wads_out_default (
    wad_out_serial_id bigint NOT NULL,
    wad_id bytea NOT NULL,
    partner_serial_id bigint NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    execution_time bigint NOT NULL,
    CONSTRAINT wads_out_wad_id_check CHECK ((length(wad_id) = 24))
);
ALTER TABLE ONLY public.wads_out ATTACH PARTITION public.wads_out_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: wads_out_wad_out_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.wads_out ALTER COLUMN wad_out_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.wads_out_wad_out_serial_id_seq
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
exchange-0001	2022-03-27 14:11:27.353787+02	grothoff	{}	{}
merchant-0001	2022-03-27 14:11:29.166808+02	grothoff	{}	{}
auditor-0001	2022-03-27 14:11:29.91207+02	grothoff	{}	{}
\.


--
-- Data for Name: account_merges_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.account_merges_default (account_merge_request_serial_id, reserve_pub, reserve_sig, purse_pub) FROM stdin;
\.


--
-- Data for Name: aggregation_tracking_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.aggregation_tracking_default (aggregation_serial_id, deposit_serial_id, wtid_raw) FROM stdin;
\.


--
-- Data for Name: aggregation_transient_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.aggregation_transient_default (amount_val, amount_frac, wire_target_h_payto, exchange_account_section, wtid_raw) FROM stdin;
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
1	TESTKUDOS:100	Joining bonus	2022-03-27 14:11:40.644173+02	f	66160ff5-81c5-41d9-b452-3abdffab7856	12	1
2	TESTKUDOS:10	RN0SH8GJX2V9Y2Z92X8BZW249ZR1CRF1CRGSDHHSESQ63W0VB4K0	2022-03-27 14:11:44.469317+02	f	978d39df-469a-40ff-8922-050edaff20ac	2	12
3	TESTKUDOS:100	Joining bonus	2022-03-27 14:11:51.562837+02	f	bd68e91a-a740-4aea-901c-5f111d8c5dad	13	1
4	TESTKUDOS:18	PJFN3RYPRCQH2NE5MJJ7Y6Y57EFCRHVMSJZ8NBND6SH7MFJTS4M0	2022-03-27 14:11:52.157523+02	f	1087c8d5-9dc9-41b5-93fd-2632e3aa2335	2	13
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
e5c2ede1-f81d-4536-858e-1e3eb806bacf	TESTKUDOS:10	t	t	f	RN0SH8GJX2V9Y2Z92X8BZW249ZR1CRF1CRGSDHHSESQ63W0VB4K0	2	12
3331aaec-4a52-434a-85df-10059bad46e7	TESTKUDOS:18	t	t	f	PJFN3RYPRCQH2NE5MJJ7Y6Y57EFCRHVMSJZ8NBND6SH7MFJTS4M0	2	13
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
1	1	33	\\x0298ade070a41f1b7dd867a6561d7456c0e346209e0221baf5e8b403d08261d95926ffb7a46e5602ce457fb3200873c228cee05422cfb1ecb5a9a0a4b9d8c10e
2	1	137	\\x7ce02dd82af002703ff41b6bc9a687e98eb7e8828665340295657edbe5deb954228d0bfd68f2bc20f19d6c853928b8f797595a9caa3692f4080b0bacbb239204
3	1	38	\\x35b8b5729ab6a5a778c9883ca44818e8d0ec5c50e097c82e8e7cd8b78aed88f0329fd5f2ccde128c36c4b0cc11683f35fa3489255c838937f6ba0b954564e90e
4	1	59	\\xe0cd3f18033db7d198f7d8e641472ba68c3f256bee8dd99f1ad4b3b8256cf30feeed91d9575cfcbca62930dfdf8aebb55a5686911ef2df81e906d86659761e0c
5	1	129	\\xd0a8caf04d7e5eec0285a6549a8f38bd072d7338fe6065164eca2388e3191a8c931f80586f377c79451b990144028fa915f352c6db649171227db884c72e3000
6	1	340	\\xca39d387212a4fd1f8f2e27afc0873d61ca0288b77a33c5cdc87e9a93fca90fbe5cd2e377ab2cc61ffd68c020457ebd7cd3572c45d9b9f91280e30ca12f79c0d
7	1	248	\\x7ecddc6d78721ded7d71978f7adc3d925be171c08455368d15f5624f5b304d08e45766f0e02f46abb4e9694effcc42746382ea26cb154c57a17d98cf57c7ac04
8	1	170	\\x039e2fed23a9fd1121ee2c53466671c431f92b2dedeaef4282ea04d6b63d1176b59902765c892947786f268252b6fb1ab3fb57d11da7d55d9c98802584c74e05
9	1	221	\\xc9e359d45158dd1a1bc702ed99d11d5def5b025bec84cecd63539bf5479f877400385022fa32ad8f708a3ec2c778050dd74dbe373da111bff1306b6033e1380d
10	1	288	\\x7a36389dede33e2979c2057568797c6f401d68517aad54099d4c1c99f504d508aba56ea7300ad361b09f8016c60f4c7f3d87b649f097164400e663f860216c04
11	1	307	\\xeb6d32f18a3c8ce5efdd776c6082d1a7e4c423d4f57f9db8c4ee7bb6fc6093280ff0d1626c70409a0361359f4b28b3635ab3e81d2813537f903829470b58f30e
12	1	259	\\x97a0999091cc3044e468d62761a91c52d1336651b69ee748963bf47ce8cc61180e4313263a249ffc8a9d9b360ed321446286381b6def058a91aa507ee8b80600
13	1	393	\\x61b27a560076d0130da66c91454ec788081c6341baa243743147479c22d3fb0114393a3b4814a775175dfb7b735f00bf814883861c2902eeab9589fb890b120f
14	1	22	\\xfbefa7d6fc195383eb88d94d1282c8e285879f62af721917a6c09eeb72a2352706caeba2491a86cf973b7a87ac1fe50545ad894a06a74027bb635e2fe7356905
15	1	23	\\x916d2cfd42e6a9d5dd5e29c7ec05d0d3b45f8e326b37687f583f15b5721ee51edb52a33cfcf2c861954d300403d7c2f00d90418cab372d6f54f94a3a8c6a690f
16	1	97	\\x4e6cb26353a0e959b9e678c93ebc34f1121161c2655a263929dfd0d7ac196607e709a53b028d542b41498ec6d1a174e7a2ac66ccaa0103f10b748b8c2ebb8c00
17	1	49	\\xb1d25e9b39fd1e3f8f847ec097f752da12f9c0e84cb3c8371904f20ae221df6e6dd764f73231513b30e28adfb37e62e6fb8ecfd979465ebc4e68734dccab930e
18	1	118	\\x4c3dee8732f7004c3d3e9585f9165da0eb4c3f1e28d6437d93273ec866ce0f71873b2b0bf56f68b0aa91ca5cdd379f15369197d97a5d35538e72cc9099435c04
19	1	73	\\x04d0e9920b6d2cdbee679db42567a0e67ef2ddbff96c9ad72e8b4405a39df33d321ef9eb446de87cf507529a91c82769afe39c60cd650ade760efa973e9fae08
20	1	58	\\x5d416b96b6e39e0a410c4b800107097bfc982395f777aa376218449808ac6b9a0e9ab28b6b92e11e26cdc646c11b58ccc5fbc7c3fd7035a401748b246a07710f
21	1	103	\\x2e9f9d3a20680113085d9f7234145f36693028a4e3ba6d44a3705b9c22313d922526a09f724b3c936378af550032c06d8395970eacd508694d95a8dff6e6ea04
22	1	242	\\xeb922dfc4413112009e13805d0e8c06857ae5a8bea3fe92286a54289a7c841a77cbe42e4c4a53eb89957ff911865ecb95e49d3105ed0114688985df15663850f
23	1	44	\\xe3267c2fdc488d2ee57553246778e10eac298c191ab434cccb651bddac94a5b496869bed831fa29a1c37ef693567f759c6629179c0b08d1e00858b7ed3eedb01
24	1	305	\\xe1c97fe2391fbd9bf88339e15a30513dfbee3a3e1356ba0c4b0d29e46e5b6f0f69d2b1282e3f3b623d3e910459985371f0f8e2f501477fbb92c2d9838af4bf04
25	1	417	\\x827cfe8454b2acb6bd4aec3130a14c1354c64554d10d5e18b5b985c3a3394dd059cbc8123c7d82a7877b0438ba472527ddae5243af8e95e0b055c6d64c467b0f
26	1	147	\\x48c1fc92a93f0d334a5527adc09856e114372abd83b147857c641db86d26948013c5f540f51834f619a69ff9482215554cfb364e6b3e120150917487226a8c0e
27	1	136	\\xd29ecbdb0d63906ba9d1b4c51218e3a65fb67ecb8364601349a511188fe5d50f9bbae0a23361111fde8cda01f877289c81fd853cf3cfeb7bef3899533611cc02
28	1	255	\\xe4b0b61aac89d9beda6317c63f809c51321a17cd3a227d54ec4570f105630ef297704a62ea7320f0330d9fb357e617d3049b0e24bac60c27ef792970083ff409
29	1	401	\\xa8dae3feaae35544747b6d6fadb07b8eaaf8cddb1868b07235d5b9fac03f65c647908fba3c15c769ad1ceeef9a6ac65c5a5d845940194b01732f993e5c9d1506
30	1	1	\\x34626a5b73b7a0320a7f92b6c5b2b3e89ff134ab2907779819ebdc9bd0782e1615ae2790d651a70bc932466126b9a06e897e3ba4a0c32f1ed51ee937cbe44e0a
31	1	5	\\xb8443ef606baf629025d8cc860ef76e86e802cc7bf5bf11175243540ba38b5abda9d9b2d6e824b4d21f7872d1dd8a169745bf002abb41a30f0245acc64385807
32	1	10	\\x593ea54a6f730a449a0b27250c97f8c5d415bf899de70774d7b66a839de9379fb3edf75766ae8384b8cbaf96e1afbe0167399c1535b2533a976f93d210d2d403
33	1	244	\\x1ae649e86e15dab0dad1e22481048ab61b81ec282e1401330c7bfb943c508d4556f052806b87f02e0ffc5bbae2d1d36dd4110794df4b28f0338a89dba3ce0e0b
34	1	231	\\x665ac13c7d41d3011a8fc3ccef446e230192c801067f8179f09dd87ba68d2592c5972dfcb85c78b6b34ad6bae2b4bd1fbecc01a96b57891b4c01810ffc45e60b
35	1	411	\\x9155278e79ff57804bc7143fcb0ae480bc48c6532d2de40da172d03fe1ee69277c3f05f46e64af34b4686847d8874f6f585f9577a6cb7b89e5e936fb48812703
36	1	127	\\x8e551fa7f8b0f59127c32813a8d97b44264f57bdda7f65094aa13d60425bd4d3d7a70d845400bd04619dcc5351c87ae0e32038e3616311eb8f1657af6f2e6d02
37	1	167	\\xee50f9d978f8df1ff3032b59f329b7af656026d5621e17ac082bda36423a045947b47e32aef3223c0adbd3b8e75711206fab714a434628fe9d5efb8d1be99003
38	1	292	\\x79fabd9e9f12b87acab528e6ac19b06d4a624ff828720cba0506c9eae9806494fdc81ace8ac1bd784fd6d515d401fb972018167c3774b7721286b665db70e00a
39	1	318	\\x4955c5f905393d264b5dc7595e090bb667e7a86385f522025116845e1730cfbe92229d506ef61bc75f96c4176dcc96dca3d6ab21209c1c7f16458b682fa96307
40	1	241	\\x01b504ffacac3fb3f4f06ef03ef44b1e3943c9acbe4b51e348dadad20162a6c996f160887291b86e814232586d83bf6d6c18914e64fcbc221d61cf17a7c6640b
41	1	341	\\xa0945fbb66df713efa1a1f1d73638b9a615ecb3c6a50427a945711e0be1d708f542a14ed5d0f17b8e175794201187da1d997f4636ec66c47cb384ecd0776f809
42	1	81	\\x5d6f1695e024f5b764815db8684969ba2ed7a87dc18b24f739317629fcf64ba45c8d0f8daa2629fdc8f57f4de5268aaf99b890268573f06a4046c51900aa7302
43	1	135	\\xabdf0e2a35dddf73e974b0e1ce92c7295891433543643316f4baed782c09ce9c875a92f5abf959aca4a28b53473adbccdded90f76b0a8d17741af2a34169010d
44	1	168	\\x309d834a4f10548b42af4572f49ea09c8b7a2e35feca769cc21f9d588a31ed5815dec9cf2d77d5ac897206fbabaf982237468532b9383449ed5bbc018b81f50f
45	1	345	\\xe9faa037cb6a7244e9ebb721b10c771ecb3729278f3f67d2e9ff8f85e7e9949e0747f09ba20d85fa0eae1a70b0ea0e0c4fec0e5979269864f667f315a3d6b20c
46	1	266	\\x361a1fb4c77b75043de768df15b88362548ac63f4e9d056b762074a26cd21310d5455041f88c56d3eb17c5040c857922f655d9c2342fa9c8aec9fece95ec5e08
47	1	395	\\xfa5a055e73b9137f3ba9c0363ae8fcadedc0e3b92a7a35fff037006a9a27d78c8facd95adea761448421a19facf990a9c0ee2728bc5c2d975d8a09e8a764c70c
48	1	191	\\xd809618af939c6fd0d44a13d789d8eda53622efdeb856c1031d8f48c20c567bf35cc414a61390c0ab8cedb3a454ea0604e882339914e3f93883c93ec8066a504
49	1	64	\\xc71f50dac6e5ce3a44415d60a62aeaf7b335916be921a3b03ae6d5bd6fb5be8c55b2d14a6f9bb70272fd7f8c912bb31e4a7e2a962127901453ff286b63bf1f05
50	1	227	\\x21c8d970a03436dbe89ace47fd55829a3d6b553ac5f940296cf42d2af4f0cf852e934cb6e5e118c786800c4ecc80f48d9a06ed991b9f16bde4a8d50d2bce4109
51	1	29	\\xfb10afcab1a0d96528ddaee7173f9a3a03f35077e261a9c9fa61fcccac7492c085134984cad06a1faea6e48c53fc26609f65fad1aa1d45a2cc0613b4d5a2db0e
52	1	209	\\xc5d7c7124eb1a943a472d7a79bdb3b007de12f07d61baa74284149ba6c08a71a6c19ed3cb3111f1af91add2a8c68d1626fece21721b6340f4c0b3da850bc3a0d
53	1	230	\\x004b5dc76178bb9cd4019754760e6bcb39a2f1c6ba4c2fc6e924c0f6c18f49236f555f8fbcfb3eca7f41940fe66a2ff7c2e028506979822006b92e5b409b5507
54	1	262	\\x90b190f811d6987ed6767db85a37509354a969c98b8171e80c26754b51b75322c15397e48b55964b13e6d808f86add66fe4e6c735a116892744146d02f2a2307
55	1	402	\\x0f0c373391523de3b8b102f72515bd9b8885ee97f67fdd4a8a21bf8f09288c329412f6c2a1c54354033a0bcab46b2252b03367b86756d8cd6c41fc111dfed30a
56	1	237	\\x8e185989070e636aa7a9d515c93e2435c5b762dc1a2d97539678e0e259e09c56da61a30ec3cd5e4f4badce666783c5a08b6087cfb9b184c2d2f0296f4dfb100a
57	1	178	\\x163b23168915edf2ccabb4bd36f51609157d0e4d7d24c9a0b30a427c5c662369eab4083d9d0899bbe8de17f2fe5bc57298d5ec9ab13504556ed12846d36fb306
58	1	65	\\xf5143ff9e3e0a6d1e63df4b906894581e05536517146679faefe744ee01b360fd12e156df12f3bc5b141fd4bab26dc3c04b5434fb4b5fdc3ce4605b1c9e69c0b
59	1	320	\\xd7bd2b7d5f0403150ab0e46e10216299509ec01d315c238b8157f611ff019c7910d73751fbee9976098b7e62e64775e4cec037fce6e6fde3c0197c456ec3540c
60	1	96	\\x0cec529da44f5a80fb5f620d6e2d43aeaa0ed212e874d73e5239c569bb0254b9f589d1c4657c62cd204d20a4edc56449c1d0d3b2302225572811b409940aac08
61	1	128	\\x56e224f11bea7abcc5469d4227f7da7ee16706e21ff0ca4d995a636ab44fc0e0c42c049c2aea2d65c5019ce9b246b4d8730d573896a1c51be30212c52ad76707
62	1	102	\\x44678482916fc14fa74991fb31d0fa070c0eda7aff760d65861473eb5dce7ff32176d2b9b21a2d91a0f1d7b937f17ef938295fdeb6d355562e21ca328e9b4c07
63	1	28	\\x9866300600dc09cd882dfaf81f19b913bb0625f1ac598956a12a3aeb70b08d704b56010add3a29fb43b79399f776a94916e64db3c9ec9753ca88ac16f46f1808
64	1	116	\\xf0c3d4168778122794565abe8361e746ae5f6004ba14c683edd4256f76b43b868db95afa4cf8cbbe8be51ac54fba9e23cb42b5cc07d925fc31e3b2e87be79f08
65	1	362	\\x38f9985bc5a9454e6811eb6c8a26afc46b0098598794e142d225ac30be2d2752cae20d5457d9215417e72ebce7b27d902c65ab2a5f472f8c7ae07276630fe50b
66	1	169	\\x3745a10577f1f5838504be77887ea51ab7fbe51d924afe4debecc18de44738cf49f31f5b627a9fa54a110ea1410f9778ac85d05250ee97668d4635fccbc6d00b
67	1	269	\\xe5135c16bb945a8948eda2275bfd38d03d038b2795c7e74121ff81e48035ab1c91c042f44d7ec22c8502b9fffec29f8c95281399691dd2655799f7f865049f0b
68	1	353	\\x86a3d84b59ffdfab8ff59f67757eb1f6a8def627b14f09946daa3c41aa4f858562bd4d50315604a0f25d5c54f0f218396d2f47c5c35ac761cb45357cae66b30e
69	1	333	\\x490a603a2eb382ec2e87faab3452396413336127364bb71c02e897075d9ffdbe99202cf42c8a522f83c5067a0f1d56d8bcfb90eebf5b277914db77f1b93e820a
70	1	391	\\xd5107e64636559e210d3998e2c96e593aa7c332f00a96dedce0734aa68afb459ef905dc30c18347d1358f9ec5abbc45bc3118969f3271cf8d128104a3e887f01
71	1	157	\\xc0658cad057676a422bfb9f535486d56c0fd5e49abe8ce746d7e919fb989c025f3da4e883d71886242d4dfaf38cede976b4578dc167874e49380906e89fb7305
72	1	398	\\x3a17d8dfd3c46f783e95f8cbaf3da819a71d448c513bf0d9e9e92cc2e254ee42d73fa0a76e4a92c641a5d5b54bcfe4a9365c2e130e00169ed10c360546263401
73	1	421	\\xe529dcd7c273eb3615e273c2509cffe2e27ee00e71cd1652f6fa25bf3cf1369c9d05b98196815ae255d32c4a22a701867f009ce8c494d1af26607f78ab0f300d
74	1	243	\\x70aca46a550264672e1865cd66a44114c5025a44054f8558f45581d4e50d0bf8b4ef5e858d18695592483838c5be5113ddadab48ae01e348fac190e14e1f1109
75	1	53	\\xbb45df29da8bc686c0e7a543be71c6b10feb6b9d8f3489d156aa119e3250f4f5b5632a0f8111c981183ff4f85363edfeeca4ca545f0d413ade677d68101ce60c
76	1	194	\\x58f487ac9ae501075fbb7cd33faa5519569b9c88b902f10c7f6ca9a322da4e5c0c43bfd7733808dee23c4cb27e1c2cb2bdb3e475bb08292dcd6048272593f30f
77	1	413	\\x3d6b61e942c7e3bbd2de18513fd543db0a53304634aefb5d1d8e998c6caa18736899d072f6d7cb2916c33e7d9f9fd243b24fed956708cd9532dcd4b2a2234c01
78	1	272	\\xee3a799f14ef4eb7cf3275c30e56146140e0c181ae2bd9c560c83d93485789a780ba2a48313b471fb73e45b623139a08bb93865f2aff223b36c90c515de5d600
79	1	31	\\xfd659e9b87109bfccd6727d086ac44aba914f0e4abc2f692a339b76331e4919e237cb9bc1f1f713979e84af69ca5afb2ff30e558eee74527fa7183dddc823e08
80	1	267	\\x8973ea5325b01f6c357be2dde1eda95dff8b9fcdefdff02140a29862f3ff23a613de307816e616b6e2ca7619349580c2b06c31e94b4a8dee9e6ec10bb891740e
81	1	39	\\x533bd246f9b662c0d9b7e450b9872af236bbd0ae383b97528f197c265edfc5639c5d9499f2c1a182daf627f409dbbd341803fed1bdb6fec155fadccb1eebdb02
82	1	347	\\x35e7d76ec7d68fd1d5bded4768feb20224f285575e9978cdb1c1101bf8cc714503fb2a32812584118c18bb751c6cc1fff388b97e4c48cc4e170920341230a009
83	1	35	\\x2eedcae474f59aacaa7b9d4459184964ad9e0d3da1ca6c391da114f926254afd4d4177cb28df02b5298abf79ac8c7ba564c491c0f8acd26e1a4fdd3bbc40b60c
84	1	125	\\xce1b6899441cfedd986555651790c5ca882006c9071a13d8c19c59c90a023996343140cf4a2bd63e8df6c0e59e2cbb859561841b982125163f0bd841340a7208
85	1	201	\\x59e74386c9ccc38a5b959d3410d80717ed34bc3187815fb72fb9961eda79ba3408f44d2adb75d66dde18d72ba9a5e9de479312970071e869d7272a5e3dd65e08
86	1	416	\\x6543ed45539eb6cd65732ac68e7299ac18716c80e3fc0705e3cbf86a1d7d9b2145e7fb76ba761c10bb1441ca23e7bcdd4c68f538c8349a141763a75b1335390c
87	1	264	\\xf49c707471d1ef34cab81042d484b8e9b111eef5943c6543470268a51265acebb8bed148925e5cb7b1f446fe154448f470fe42a4692d7ba89d5aa44b4f3a130a
88	1	281	\\x2f6768e8d325151f9709970695603b204bc73644b33b2cfd2c1f7f05500c5734ea403d2f17bdae76fd770a164c0980f1523a1fe2668838ed880c4d011026460b
89	1	361	\\xf98b744369cc74209788c8056c70225255bdb6608386190d5aae28d9cfad05daf939993a94c4c5d6846d55ac4123ac39c491ef7305f637fb20393c816346260b
90	1	138	\\x48d4c98cf5695dd2ecd99bf42e2ef5e941223aa2228339bdfc216ac52c817b1f39a82bf2b382319cea9d054ba8bfbc402ea24c14c35c397cf53682c7753bfa0d
91	1	25	\\x9e799e35188f34dee689eb2666a79e77f8ca11d2e1c7994f11881520cef2bd4979a2be0fe8c81884ef01c2ce92bd0f441dcc85955a579e61236c929dcb8e6a01
92	1	199	\\x9ce681d1ee8a161b9cbbe2db11c6294c86f792df4911d0e457b4033b23ade766b63c3985a4fbac93f92f94007ffc1055ee4e008a17a0add314af0f4e3b0c560b
93	1	11	\\x3127762086505f96851c18f36255aec76fa06d777dc89a4bbe45500b6f464ab64fbd974efceb0a98df7b65c9d428fe17acec523e40c5879b3a7feafd10d2300c
94	1	376	\\xd6434957d7149212c8b4b9726302072f059710359fd57c74e1e144665e52a30d81e4757d71f77f1f2472a957981183c889ccf3c88ba274abeacad85017168d0c
95	1	92	\\xdb72e898659ff06ac52cdd9708ae56ce18c37bc72f9362bb91e7d06d82182f9d159be5d162172743b7372b2b9077dc9ea7904fdb0e047c7934b3c1f05e5e7c09
96	1	352	\\xb22d44260b3a746a73867cdc276eab0634eed9ddb80a1b748badc9ec242bce0659c7d323adc756d9ac6393a9a00a2099d739c3a8fb9e6d6598a7024e12e07d06
97	1	46	\\x74e3d0ff5fa8436c1be633d24fffa991215f96da973564b09efb6404b840c0a4219296de6daeef8357e0a255dd5314eb81b411ad853d85b90ccc529af2e45009
98	1	251	\\x333352ab19c71b1baa99c6b98a6b2713365523add5fb1177a0e3b3ffb521fdfdb93322330902f462e5a2a4ae3fd7c8646b59419582e7453e5d3ed282f122110c
99	1	12	\\x49d6b8c6b10067b08acb9d15cb84c45c9dd3f0a4a86086406e5de2702369e96f4189d07fc0b195a646e85c343a13469e640466dd5257cec6186651728bc8ea09
100	1	213	\\x7ef78e043133cf9aa2fd3d20b25fca3cae08d771a2b064a250f734cb828b359e2900ebce05b6df1488fc9314e6512c69e7fff29ac473b495879a89affb942100
101	1	66	\\xa021ffed91f32e775f6bc2e260b854a2a8d150c809e245ebafb1bf7163282911ffdc5272fa082ff3915d1be4dd2891d916eae289a24e13261374231c531af00c
102	1	74	\\x9d2c53193dd4e12a876b39fab09a449fc6ba209be75cbc3377d01c38f0f1fee3ce2da5e0d1233729fa5594f4bb557648d1b46913936d998e647ccebd5941e40c
103	1	132	\\xa4ad407ba7115e821f468417802bf564445960a38cf1ce27c0dd5ee608b8860ea13ee0f9e2ec4e5a764a4b9d94c42b1212b362e86537297f731ec363da45e907
104	1	183	\\x82c3fa1fafd34ff749415fb8f213a9dfccc11ba0ad344903300b57d791a9ef8450c628165b8be96c3a3620af1d50199bb3a28fa9bf7d764d954b0d88d7021603
105	1	52	\\x94aa924582e1f43623b9dda0d7adf6c1af38591bd420347c475f73908b759170c8774baf4175d500a75190f4b332c9f5b12d2f4d293652b4f2c2a1c5dc542204
106	1	414	\\x6601715fa37ae973c27e8d28f4aeb308ab1c110096842cd7e4dc2ea6a902f7567b165b67ef3f17288f312cf0ad246cedf82cff0cdeab771817762917fc21580d
107	1	236	\\xb0a17deec577b12583ae9727048c8c1e35c6cea87b5430500888c07104fb29570ee8fe14f742877d988b0df32932fcd4b8b1b0073f7936455dd2e08063f82e05
108	1	355	\\x4ea2827dab2b6a2bfa4aa9f7032d8806690b1d66348ded7dbde19c536fcbe2396767b5d23558dfdd7eef1beebee0c147c054a03fc5662b3fb2da6948ccbf2e02
109	1	166	\\xc679f511bfcd9eb9932ea7e9c238433ac2502603a9c312e8b2980b8bafc7e018c7ceaf1115942e6551a9f34ac952e488db18183f7fe0467c2001b7796d6e2a07
110	1	13	\\x1feaf891af8779850f888c20adb4d8fba8a882fed8f96f64d3939842cc6da29b84c078f68691b53293054c08704e1e748d04c60f7d005fc93cd50cb5b3c05e07
111	1	331	\\xe20e46d228532d884d98e48a6e78ce84f4fe2c91255c78ca2903c4836a6b4f4ca4aaad3fa5ee4bf2978f716201aceac8b4f5384285cb79d2eb92848806230404
112	1	370	\\x9d7edefde7433c7f7bcb5bb7d291db4e405e132b61e0e767f55068e803464f926d7172d6a28bf035226de3a352a31ac6a2278a0f741c1d3223f4bf628b22030d
113	1	328	\\x4684fa40e6025cc317b84eca91ded610c08747a36c9433851188f603962a68cdc3788303e7da7e644474eb9da66b0c0f9d36ca804652d9fa7417427ee3fc5703
114	1	406	\\xe300eb0994fde3bd961406d52ca6f151c368539c90920c540645f2603aba66228f2da690e1c0009a6bca10f797fb413c736bd26956ae824fed1d523f89d93405
115	1	334	\\xe62f73271ef16a720a49fe8bdb8bda2ca1363b366e9520e5979377adf260f6bd3d3e935402c5828ed381bbd89441fbe6a7b9b65fa01d649c13b7999644f94108
116	1	153	\\x6f92c8e362e4a22f4c79b1841066adec319c5caf7452242fb3f594e4013ba26a291556b8a8bcd7d34d6573d69de2c90c5b6df2537f48014d13ce17e06ce1fd09
117	1	61	\\xaa3b45d02e272389523b874e8bd0ab24c45bf9404bd590ba2f22a9a1925580df08b654d5c3dd4aaaa2aeeaba1bb8151aa88289efb37e4aabb6a361b2e04b0600
118	1	359	\\xbf6dd587273abbbbefbae6a1f0a5b91c55a930276287bf9303020b0f9f11e41919ac97626d8391d49a279ce12b8a462d909cf2cc9be4bd51d5525ec2966d6105
119	1	42	\\x2f9dbef1fc30a858370fbd16dde62868b6085713bcc6a9ac7ac797fe4e17a62467893360e9b8ce90f81401a3b10255823177ae1232a1f3e01e97a6a993bd8e07
120	1	54	\\x5a97d47d04e62de5d1071f26581238d9c1563771e3599dfdf4846851dca65a63cbe3b3f9aea32d85121fa2c99b7e35bd3e3971228f3f89cbd56f239b180d730e
121	1	346	\\xee305dd979cf6d2191ac0ebcb6e0e3fc0505c55643c15735eb0ae2b3d5f4190386e04027a5dd47c70473f655d908d9b52f6784351e8f29203be76dfd378e900d
122	1	190	\\x00555e5785e61a144450fc121a1f7f432fc5187b1cb481798f14a0fc60895856c44cc39543d9e4643781551de1eb7edbaa98c7c015917ead422cbc466ac85707
123	1	101	\\x593ac40b6edc8d048417ab6a270d42a30c755073cf55c6db0735ea77ceff8d2399e67d98bcb9a8861c8ed7a3382fca7d93bd86bb38c073d686878f7ecf81b007
124	1	197	\\x288ab7059f7622d1c7346db08237197e070ade1ef9f95c6827abbfb4c0497e2d4a041c5c5e2723a2e429ca612a0ead598c3c47e2f2417f95e390a0938b101c01
125	1	234	\\xde621bc366d852705048d7611cf45dd52dd17dd70e2d067034ed9cd8939cf38392b901c214e96ba62d4c361316c4afd49e01d03c679f5377357c10d08ac30a04
126	1	332	\\xc1aaad6f998a26541da47aa7c2f1b8c16bea1237776e87a79d91d0ac300dd9654128f4b8416829dba9f5a69b555dedf3a5b0529add9aa7dbf9348f2a08363d02
127	1	257	\\xd6a1aeea779932e1c16ed389d693003162df26a84f9b53f69199e438b9408ebbe6a1f27e343312761dac84c3d977b6c6676d2b1a9c4a6d93411335e6f681030e
128	1	32	\\x86d16d36a7d2c8a8ceb596860ba49d4415e973fc1a8cfd347982326249aa97df647ee765dc7878d4f7abcf6a57839d14a0270e65a0c911c271fde270a6f0bb08
129	1	206	\\x05970bf1a5221115dbc76dd9d020b16c2f41e17541671c4dde2a425603c8b5c249510112f2a6fc031feccecbccaf8c0ac5b5c4196d765c7afe003811ea18aa09
130	1	40	\\x3ccba14b2469025bd91113317d04ad11f00a2d5a84b06ff4ca1e6cad09fdd494f6bb930b7966ed902dcdb3ff75d24c64c79bcad339708fb8068d9b79f45f8b0d
131	1	208	\\x5521ba4682b09ab54433931ae04473c3e864c0fe14d3cff8c06ce1a81686b9b8c36ec7dbffdb4722c0be7c74a9154e4a7a9e92a924880dbafd0ec643ca4e8900
132	1	415	\\xb0cf380a35d2f2c225adc14ee69f571dfa7e3fc8f7bffe33d215d4d4adefb5d5fb9f66c467f07752cd4ef542e235ac04073e047036ecd15e5c9046443ff4cf09
133	1	246	\\x4b549db57c72b44caf0e8abd3f690c0da966186453243148695869231c023bf0e2bcd0f2e71a76ac2255f7fd71e93b1263c3647ea89aa47a9e2ae2bcba430f0f
134	1	404	\\xfce54d12777b599a72b03cf5bad5535734dba0ebf4508184a66a651959a3b8e44c1e2c290090cf11f004903ad04a36f6c59cd0cd8eda7bd857486a1c735ce804
135	1	263	\\x951f8002121f54ffadca28cfb10f46e0c5959d95b23e10c0a5cc26b48059449342e946ae1ed0342b0b7cb6c612519cba61099118062c33f0cf81d7eabfd19d09
136	1	254	\\x753d9cb1b14b3a794a07a09c00e5702cc3dfb8450943630ae8f4224aec45e4646a165a185a84c546bdd3c4e640abc4ea9edff510c54d5377e29d1a3c5aa92e00
137	1	385	\\x047bbe32256ac463b5211b610edd35d3cf5cc62a5139573152ce1ea46c5ed8c3e7e6a61a6786fb6ca271495d588755e5eb2106c54227a9eb3bee2b03b4c21d08
138	1	239	\\xd2159e9619a35440cbbefa077eb5ce98c0dd1908343120f8fb158addd61c9eb9e7c4c131688dd05280faf4a04b70f49038386e3e5b54ca1a132f1cc4c995950e
139	1	371	\\x1028c728707db40fb8436db41b265909fd668b69be4deb22aff68a7294860b87aea821defb5d9ca3fe6f11ba2217559cb030c1698fd25f5159ea645125c31806
140	1	308	\\x3c6a2ccd3df547a4e9a8431e04a0ad1c58ff3ff073f5abdff7298439f3aa2acb3e8fd311f943108c0e902b34ce6dc95f51712b96523bc3ce1617136425298604
141	1	204	\\xb0ec2bf02371bde21560a285a12f374a7f6225a3992d2d7d91b24155164d1729a486ed5dbd6017d049fe3aefd46fb5bd51ada8b2159015e9c2a644fad72aa405
142	1	151	\\xad5c8ab56531a73d5108e22cb89d03f778f5b49860ffde9df9a8264dc5a49198bf5b72496e2e2737d9cf2371915971d66bd53a3a5e970361c6a12d71bb46b20f
143	1	41	\\x3b20a481c26166ad3ae689cea9a89746c783391891639bcc6d57e476f792b1c00845d2bb799b37313be10edd1be0e68a1554ca3bb5f53d03d3fb1b3b38b13101
144	1	315	\\xdafbf08c206858b66f4a47f43b135989845f8edd8802186f63ebfca1e947160328f04eae9a91e1249c706479328bc310a0e902ead5100f342170386ff295bb06
145	1	156	\\xad04284feb1917c1efc48c3a53eb50b13fb3eba930f66470cb9a617c6e3715db9578b5f63208485e1c8bd439f1ecd6c27b6d6855393e6e1d3b7d888057361504
146	1	139	\\xcf015f460ad8d81e413dc1b1c6cd6b23ec1e77cbdea3ae245216380dfba33205d85f4c76520e5a8a940e08b8e01aa28495ceeee1fcf9ccdccb4a64adae8e8b06
147	1	85	\\x3e063b450f21d727be2b6883e234139a3743733a412ed56fd80a4b260a2165c0a2be51760272314ab8f5ad21c015e494af86c70a739c605920d96ee1a1da3f04
148	1	144	\\xe19ed2bb282f9dffc1a61be605c5b865bb7e62ae27604f3e2923e6a62a5f3ff528228603cecc31ca669155bc97afc3d940aab729960eaeedb92b2a5b600fde01
149	1	313	\\x5ef84720df024c5b6ea96a6db3eab356856a6ec36f4307b7af4931e0c0007efcae45a9e0d5bf1d5b18397495e426710c55d830895c0bb523ef592e47a7235302
150	1	268	\\x162bcdc59b523482766c35206b1141c230e0bf6dcfd5176a831d0a85a12222ec65f231ac65314b5128ef44fb6d72ffd459a695ed0d46c0f2928ad28dde012803
151	1	163	\\xcbc491cb8de90110e724d388f441f6cf947d840e018bf3b1da1d792f1aec2e26df8714799204b087b30875304c81ac546fd226d3d7f9f7395061903e0cf5b003
152	1	159	\\xac13994456c057395d64f23d73fd5aff0f95e631065d3e33e265cc385ac2f1d35c184c1e923a51e0935d9dabd63d359da858e2b9dea8f02dada5b030ac0add0d
153	1	126	\\x45fdd4504a8919f6a68e992ee4a00dc47c5ad1b635e64ac2bf92b716a223a1eb127b3c86a10aecfa55bf32e29180bdf243f4e313c89316cb0d28a08257cb4603
154	1	285	\\xa61064297ece8f67c1bb3dadcbc3747154c5804764c81cf28f788725792249dfec92ec2c11591fae2f3ab1afac2cdd97be7afceb516e6413373a335ac378b504
155	1	15	\\xf3f397f0cfc1276a3169491d024119b92646d66e48fde36c408e74cae2c278e99da9b346aed7f5421cb4319a3a6f5a9a18c8aea377a2a06fe902759d1d5ff107
156	1	323	\\x6ac7952db506bc0e5527094455bf97f8e8b6008e2aa80ffd14fb0a54d338fe41dd549344f771fcfa49cc875cf996d8510ccf5daf2a1040a4b6331de82ef01d01
157	1	252	\\xa2ae6e45a0b839c52109f2ad70cfba7be115e5e5d85260a017a918483a475f3b4e80b5b52a960f81038167c12a1372a5e26b28f7e25e786380bef7091abb260f
158	1	37	\\x68c0a30b09dbc4a18d629a674bb6979a61b1009e2596ada5dd43d36f3cfc0bc5fdd6e38371ce0708b80f1732445b01a892581bcc0dd442ec2e2308e31450f607
159	1	177	\\x9ad816f6b52b5f4373b9ff224e992a9fa5a8605c3e1c7ee760a466d3a0f5cc137dded455af36b6c6a2aa440096cd1b71b4946226534e08a4f690ff0d95bced0e
160	1	238	\\x60f84edeeed925ce36ac6f978f6f5ada6c47929877f926b6190ee7ec8fc2a412d09f37ac884b494ebdb0e7e3c3a12949acfde60ef79fc5e2207873c0d4cee106
161	1	384	\\x68a458243aa5449e23190c5b7d2ed38f2444d0f083d6e5f5daecf4558e3622526b7757a38af26e7320b2d17aab34465983ee74f0b1c0c1a63730b9c9402d260f
162	1	110	\\x5048bad49ca1a9be1f19754bf640f6dc10755f42568ff8f26a0ecec3d506b2ba00ee78ba02ed189531d0d92af09f68a2ace96b00c702e364b3390ba2ca024200
163	1	240	\\x346cd94e9424a29c7abebd774ce6bfe79d145794e30941f7b21871de7634d17101bbd5b053a44a59154c94a3863a41b7fd269883f156a25ddf3401d6d43a6500
164	1	94	\\xb776334e475b16d9f4b8d48c4980d907d6834b0a99479d0783f72972fa6228037699443313301dcf74ce38fbd2956d24ca81fc56ed739359ced2495406f75801
165	1	277	\\xe9740fc72d3647bcb5bcb0c5216ad912ee25c7008e693fc8284c28e947ff69e341c3b284084a0f87cf9f7b6a7e95b0b5352669d2e21f002e27c6651f51bbfe0c
166	1	77	\\xe47602fcd8fc1c6c9e43b68d62ceb5c588ed9f2314b70eeab78965194f4f2799348abc25243c1079704c98428c1b22a0a1a3bb576fe78df8c78c62ed17af3e01
167	1	176	\\x6ead9db3f4f33fa72bfc59387fac545e6d668a2669c0df2bd6e4dba68601a1d318bb6f1679e29419654dd9a473a26af108462a8ed7ce9250936770ca284ad50d
168	1	214	\\x3d9b78d372905eb474e6a4be7976fed1d319f8f04f7e52ab1f2def66262d4b06fb76c0359f6f5bc5a822d767da19052191e3c32f3a74f9de8f917dbc6aca650a
169	1	160	\\x7341a5227d6a0d1f4f229db1fdb7f937ea02c7893432eccbcba96d15dba57d6eee1bfc64bbb14d1a9e7223dfe1a8fb8b4a5b0a0f6a45db6d3a94753c77f85e09
170	1	260	\\x9d9586e8cbec6c41e69dd7e5cf31e87efb93ef8d77dc1aae1a49bd8eec73ab30dc42bde8db0aff9db6aaffa4183b6d63f2ead9b7b2cad92349a99615ada60e0f
171	1	409	\\x2fc86a20b78700c3263721e8f812893889a9e642588c76a2bac7cfc191e45034a29aaeabfea9f2c7261b94558638ec49d1818b9850ee07528bb590003bbdca0c
172	1	423	\\x6a036a829328c244592472f4b39ff4dd0edc26c80505dc8114d8280164d698d362d6bc5368ec06b8da28df4904ab70288429ed088f773b6a805d5f828b2b5207
173	1	184	\\x7c6279e99a754a5ee489e33ab8185f5ad07a5e737ececf7c6cc74788b57f5828e46d3e3ac5ce9a242a0cba123b3b35540af7df45a4b201ecb6354e3e77ef9a01
174	1	354	\\x959576d1f131fea6212800934e9d1fdc7185ede81c7d18a2ee458ad465d705485bc1cefc5f4430f7734bd136ec30e81635735afc6d48ccc71be1cea15e4d5303
175	1	50	\\x422bea48d099d6ea2d49a4d89ca3ff84685def80d33978eaf1067150d56651e01ad98c18e5e2e3b4632ef3deaedae4ca7b08ef53ce7f45df761c1794f6a63a08
176	1	185	\\x8cc6e581823a0fa176af123430b2d237b63777e1046114aea635f5b27f5437e2e42bbaa6d2acc991462a36a9d9102d6724806ac2dab1daf87aea545b02c04804
177	1	316	\\x2f2b04f76026e2dfe556cd7dccf106813c9fe8abbc6054e1cff9253ba39918f0fe9215959259edbb85a460ec2ab9e1577686b00ff19d73a40c7dfb78476d2d0f
178	1	211	\\x7ae1cc35bbbeae3222940eecdbcc5bcdf4df4f3251e12af6b58ab8bf7a920f9ded9c9ac9c8281c08a4be51340224fdfc4a9ee3f3bf70eef99f0d41e190fcd604
179	1	69	\\x5c50ac215d0a1d4ceb24866730f9400a5798d41d5e0fc25b7541ff88eb3cdba60b0b89d9f7090a77d6ce562e885e3115c817a31b0e4ef7829012f72eb1f83f03
180	1	336	\\xd51d980530d42935a1eea0e09d50071723f949ca0a9dff6d5d26133cbc4044e3f6c8e92bba097f1e32e8acb87168c3d58dc1aa1b929f18b95e62aaeb28f9e100
181	1	200	\\xe292e28887e95135b56fc3634efd1dd75b1e9a715462781f6de21bed6cf8f02e29c251d04f1eebbd68200b984cb7ee1da9808f854847407d99d8293c5d99a00e
182	1	70	\\x3e7da7f37c8a2c32a5d87ce6c39ba435aa161b8a76be8509a63466742efdb90da702a2a52b42c0cb01fb12cae21f1d028fdf77cc007c0855f512780f1910a901
183	1	47	\\xa168b6ffa0691b8379a020ad3ba97b81f07d7189d3d799e2bd2cb414e79585f45e6422562f4af354a2e12107385fe1186e1d3d6705e24972921fd44c52641a03
184	1	76	\\x2c49d81d403f77745544fbf237f1e9102f6be65e8295b8fe927528d777e633b98c11074e636e3145fc7399ce8707a5aea0c1dd4bef855c06eb41656cb6b76d03
185	1	152	\\x7c70f89d6a97fc8a7662c06d6c7a9122a2861b13b8d7fc5fa3a100357773995e2e4a09f0f8576db978677766b28a062fefe1f087f5f7113eda3a014e4eb72708
186	1	24	\\x280aee43678e592b4e1786e7a630233b5613d78eb5ef15f35350a17a050566ee1fe7ee60425b98ecd5c4e93e7d1f34b76a73f8a503207928f4b3164cd048cb09
187	1	192	\\xe852689038a99584efa1ecb50e999ad448af489f6a448e66d858ff8a7e5b5e888b7eebbceb9b3c0ec5335065a862a44645666e06054f6d890fab8d6afd07180e
188	1	278	\\x461ada72b0c15ca7f42dabd90d302a4059b32218bcd9513532606b6d49f3293bfd73256cfe0dbe30be7aa27746838bd74e5e06a0d449c2626d75409f2cb4300f
189	1	142	\\x34b7d84e3b5d38a883fd15266db1eefdac575084235d5bd10f313a0b5fa20a939e9ac3335d55054be12225b4ebc01b791ad7e747e14c7564f28eaa1fcd11140a
190	1	356	\\x4f3fb91965ddebfecb56736f8685b2e854c67a6e40d046744f3e592893257e934713c14f458060a6b087e03b1f6338ae46209e17d7ff3520b57b4a64a880a009
191	1	134	\\x32e7c7fc24f8c1a97b31f1d2de64f17c54d2f1de6391b736f38f4bbbe303063a66a87926aa9c8949c693fce08043bb5f68c8fc56855f85e35f2254d543760e00
192	1	253	\\xfd1a47b0cd714486fe865554326d85228d386235d42f1b5d390959198fb1650f189b93bd801395a0ef2dc7c4cda87f61e9f90fc77f811bce6fec389400c8d706
193	1	9	\\x95d4988084604469d81900451104be2c51701f28b2d0f85b4c110c2fdafffecff99461f8044e5ebe8fcfc630194977b601a3527baaa39f6cb48350bd2fddad0f
194	1	360	\\x205af9ca5e221964883bd177c0cb3ee7d3a20263abaff2aea042fe24a04fbec157476ccdcac35c89a973e2b96456a6b0ee31145a3695bc4327766ccb287d7c08
195	1	380	\\xb199e70d0c58e8bd1f25425cb0ca8586e38fd8b16e5dfdff696cb4ff1d3d8fcb907c020f986b5b0f941ea316d55687a3152f1993bba13d7b62892d081aaa800e
196	1	84	\\x605e56373cd5a72b4c54f7103b101b273f9f03113e2030df966b5bf2f74a3f3bc4696877a23bd8e3cb2da6e9982fafb2ed2cf8d82914b061b2141dbfeba7bb0d
197	1	379	\\xb273c0a40839f654d54764a7a346b9ba1173f51bb4486ce045b1df321b5d2a8d05a48ee1e09c12c8a2efc950c85e25b5552f1585705ba7cd8442eb88c63c4a01
198	1	424	\\x6d45a9003ec0350cf2ac5e52aad2daa3a7f0fd8dd7d34f96422eb24734366d2012f38e6f417ae2c7f91b55b78c4c43f539f8b86710490f62b1c11ba781185508
199	1	399	\\xd9a196ae66151c6b7f3491bc8114b5f819b5e36bb9d8e7b98090c2236ff3083eb217f0f71de7d4b66c263b9a738e49017a87c513381337a02e75b4f2e5147605
200	1	17	\\xb8336de6d3086b32705772a19c94cc730714baffd019789b655c20635e3e83650ce6909ead1601114d2554685ac0b4847f42c8d19cca1b0634c19b9eab5a4708
201	1	298	\\x1e3abf2a5745f97ac5db458662f9818ce2728ce18192d8861880658355205406d60e00e15ce6eaf0c7d3efc9eef9e4898bfd948b1a04edb9ff2acc8b4c953e09
202	1	325	\\x920cbfd2be90b40f2f3992bb822a2514f27ea1024ab5c85a43271ec49386718cb80992637775d75edef6dcb9b3a337fcd0274df4d9911f938766d851dfb7620d
203	1	368	\\xccc4b37e9085ced156fa63eaca48274e26744c4a23e59b70ff2b96737932e1890403f4d934d8df7392f9b2b599016c38f226849577ef122216ab0aaa1f491409
204	1	98	\\xb56ee72d7e129c4fadf87fa0d343674c76082239940b8e71946bf18e32da491badf4b7b03c4f937a037f455e6b0a4e5db2ca5860eb8e0bc5a63c933798657f07
205	1	30	\\x13a8d7ee08971d705b065c1722c44a217d8d6776225ffae799316a03b7bb48d6681253e2a3cf74d7ca7010c503ba31f0777481ca99cfaf9fb7a15f4bcc8a4a03
206	1	123	\\xc82727309d97323cd828d10e60260267c1ef944ab58f17b1c5ec86912c6e54d4ff0446b9023adab0f9d3cd6d92ee560a476f8683b063d311827daccb28f69308
207	1	196	\\x211062e31e23285780e9a14b5f4678a60c504a781c590e1a3a45f9d3313c053ab9af263a6968c1d581ce6d16f3c17c3acd4d7e0c43ec52e010b3f2faca1a520f
208	1	171	\\x8c90628381737fd36207f8a01959b3fbb67e1451d64519f7cbde3bf89108c1b10fbe9cf3d301d0fee672a84e8f825e3f6264dae221c231906f970e0af4ac4a02
209	1	115	\\xd090c119ddf11dc116d3e82c341f05eded8e2a8b4cda28098cb509698e037be560a0edd8d69e314fe8d90dec2653c5c9994720b8bb68a564774a71ffed74460e
210	1	271	\\xaedf6952f5e22875fef414821ec5f531f16549467520e6fd8ddcf4423f8e41e972fb54645fe0e9872bfd231b38e61759b54d7928a2dc12d2f674d94a74b8880b
211	1	145	\\xb9b48426370d05c2a35d5104c8a70ee2aaeaee49df18c3f8e2966876ba7125046700386305020c6d59a6f4c127c3fc273c8643f2ee3349299ae0f6525527d00b
212	1	296	\\x1bd8bf01623109f0092282f31ab760c795e827bbf4a1dd74e110a722536b4a7c1943e689f6ac23c0ee15d1f3584e9a798dff43f9b28a56942f306b9e93f4ef03
213	1	392	\\x4dab12f0cc56599390bce570227b5a77974fc81f62d723f146cf7017bdd0e4de9c0bba40d52c7c28464c1b168445ada368888a102c0a6654a41567fd095ccb0f
214	1	344	\\x2b05bde1a4b9d330c9d517454d0feb6c34a6496c483ca5e99af86847950dc23b69e41d3e5651a6f1ea2d66ebdfcb9fe3367b6c8ec71aa9a9d682d677be86ea0b
215	1	20	\\xa80d0beebf15f6108f7828ad838aba83fe34b0da7f439dc83a0b35629fc49271e6d9f72d10cb990c58762d484cd460700f7579affadd44eec549fca8af0b5102
216	1	210	\\x04fdbf4d3a6b04df39fbf8f9ccb03a25a191387d1e48c8ed5a10bc0c70c5fb4dc4da5df6ca03e3a0745b8271715742318755d11f869ee74de35e61bfd8599d06
217	1	247	\\x9abc0fcfe4763d7d5eed7bae05a8031f0ed6148a4de88e2f8e4425234e3b8d97f248c52060398b94b354b7c24da70293d93d7f1fb6529a0dbcfb58943ecde00a
218	1	225	\\x459898666da03e39df338d8bef31866002de2c112b74e2f4d80d4a8bce4cc97a113c2a1ea55ddfd527060284beca3e41ae31a267208278d2cc6d7a0c918eea0e
219	1	280	\\x8a4e4e57385f3797399f8019315a6b20464762988a18c793a1d5b209fcab35048935df3e59ef8c4a2df288a0e7cd8093613eef0f1ed051ccec1e6f61213f140f
220	1	342	\\x926e6ca38a6275c90b730206341c35beb4b681f6d6c9a42e3e25b5c6c5e92b59016c878567117139f8304ae07db37f3faf088372be19f75e1eaa907ba2132902
221	1	372	\\x37ca414488d81bfb327175c26fdd63e8455a815d697fbc611067293aef37981400d63b81784c4cb3bee16ffe0aca5d180a408d3cdb8241a78002f2a5b6811007
222	1	130	\\x8802c372bd2610ce2558701e96822139adedb833665fb5c45380d0176db5eddcc9328b55593c340f18c9e23a7ccce402d14a0cb6b2b180b7044fc64b78898f0f
223	1	87	\\x5ac3b8b26ccaf1ab21388b099f7e95e1aebe73cecfcfea86982590e570fb9c9e09f5fdbb9e3fe3e25e085d7eefa8d5e60ba5a27be9d3c5c6ddfe7c6c97b4d807
224	1	300	\\x019504d214d205f216819951b4f93fcb7550520f6b7f8ae17409113056739d6e09412ff1d33c5ff1059ae29cc91239206e60260ec32973f160e1f40035b5a305
225	1	275	\\x381e246c61cec72d0090ba9f6319903a18774d2ba6a108679fb1c563e88a8355a281dfefeeb9209e2550ee867f9764fbb3a8f2f1294986ac95db8e953f809b03
226	1	182	\\x2092401fdc1903aad64a4a9895e586c5a6ac10228dd6125cf92721b086e527e2a3790f1fe714144641a84a90894a546314035e1c8232b2f5eb1be94f07fcac06
227	1	388	\\x1a1f60bc4db662aafe37584fa7080321739ddaa6434dc7bf509d5b9dcd4603e6c98e3048577bf7ee25700a6ae4c2aba3c7ae9f658b5f76d623d5473ef3eddc0d
228	1	312	\\x52e3cc36e7d0391b1019742250c91aa5547e7a73002aaf76aa488762bf7a05f46c69604c188021f62bce0ccdf39a00a16cdd1d93bb2850e45e2de075993c060d
229	1	48	\\x8785fab435c616552644c6581f40de973419541e8de95db76c9f9dc9b2f6b1fec3ca365508465cc85eceba4482024b46dd586cfab55aab80bfcdb974eba38301
230	1	78	\\x24bb242ad3574bbb38400efcaf4db5810207da0cdec2624e11b3be82c63314ddb8ac837c0d06dbac0f6421325f0c1a19f3d6cb69ccfcb59f7c044c981cb6a800
231	1	188	\\xd36d6c259487b22538fa8cb1bd63bfec6a2b17deedffe4365bb4edb8084c60501678c5414e728dfec3929aec2e9f63b42534bd5a0fec49b41329deffdc02de06
232	1	140	\\xfc78f845e1e2ac4a45007a8a5ddb26a7c6658b951114ae8efe31e201a50f6606c1b28345145e137a8b685ff96067f49d1d948b6386bd211f7d8ce5fa5c889501
233	1	2	\\xd4af82869bb7958df7fb2fe3bf6601b37f8ff337d15b28466aab77ed4207922983b5ea6dd924e84ff44f05d708df6a30956f60ac1cc6a4dd5e86aa14427d8202
234	1	203	\\x8cf9215b7165f97230048227e7275c2ef5187b9986f02f84d81af6242c4db6b90b2ffc6f74672eaf799c06c9f967545618c6d410d9350903863edbd712d6fb01
235	1	276	\\x652686519479dd049bdb8f9c3a26ffc0aa18b481fe6e4e66d61fa93d0b63e7bb00c2bb9c2c70ea11a986303d81db9a30b9d88b46faf161bd5d85e9c14cdefb08
236	1	216	\\x9dfb337d614f0af400e9a09ebf861c655e3ddff5a74d4decde12fc7d10b2ab1a346fe0007529c69e746c72f06a3a30e5249a78b3da661c318e8a4b89392f5f01
237	1	186	\\xceeef7b0338f382848082f37a6d1356b65b0a3b40b997b5c2a4a9d562f4119b5d4579648e815c341bd8b44d52b6a7873bc5f231b79a2a42112db46c6a5ac6a0c
238	1	229	\\x89d827ab5852e2b02bf2f162506e8722c84c612786027821775942b983064fb53f30b2fef384b6d3ff29bf5d5c263966e52ef9a7c5ae8637fc28d05fa0f88900
239	1	322	\\xcd5e4f5ade727cf7b8a7b6b06527dd2366a009ebc3c6a2106a1a22f0c3bdebc4506865711c642bef45d2a7976c292498c4bdbee912df58140fe8e035d3359203
240	1	338	\\x9356ad3781f112eb8802b37e80711bfe36ad145a2f41e6fcdf880250ff449bccbd530f3e64fc2dacda0bb6a1e74bd0b11281b3971c2ba5b658ed87bbb9ae8b0f
241	1	329	\\xa6da15c9050804afb0b798e9985d4fb15067ecaf8874b339eb3ac65fe8c92a172774d5aa91fc90cce2eec12a82483eb09abe73ae6a6d2345a5ba7def8e0c6d06
242	1	365	\\xbfb930633cb2bb3cd185cf8e8e5a05f5bfda8bded63ba0a8b9bb1ae4c9eec16af968d8c08f7e335cf240685e8c5482bd8fe4a6308b4ecabb482e392fe3d2fa04
243	1	18	\\xf298f399e5c63613b61115152b48a51da5169e468f952b796221e351f74f5beebcc101a183bda75a890a2e03d7dbc13d45b61a8f6f46a66ca623ff132d0bbf08
244	1	79	\\x7db419731951ccfba611966b8f74217f3a4d593fd0256f84304d45664667e2cde7bd3928f99d3520e233a15318dd6a898f669e3d3fae9ccddca54583ff9aed07
245	1	150	\\x546783ad49ef9fc145066407427fcfab55aaf804b1dc12a5337615f5ef21aa8a10f9854f2a326af26c899b5ae455a0e3646d2b3e970bcc09a4d2d82e5ce3a601
246	1	407	\\xbbc1b7aa085bc31dbaed117601c0895cd24e1693a37252cd0186a9341f11de44985d65b146fed2769f03932bf8116c03001699a73a77991e089219731e64f900
247	1	357	\\x46d11662d8a420e5198de8a5e55014c972b756c4d7d1b56899331101230bbe84c2bbae9267c7c59992885fa185843f20b6d01656a1086c1ff746d4751bd2690f
248	1	212	\\x58bbfb21fb6a87c78fe343213cfb41dadee6795009a15e353cafd9053d062bd9f83826febf218718611524bd3f461d25db786a01d7329d9ded3757c4f44f9c02
249	1	326	\\xa605402720b1fc04ca7f0430a21ceab051d50b280adb0eba05bb657efcc2f61affb8978eca8b17511ea191fb59af9c6e0d7c0b5cfdb1be629765d1b37a19f304
250	1	16	\\xecb27e1f2319e31454b69841e09e5efe1f778493b5c351ed92a249f1bc130c6e553f01d4be36e1ecde38cbcb8ea1bec480683d7f41cc10ccb5019c84ce02d008
251	1	149	\\x695e9955b3bcdf35d27651ae554e3687121ca16186f1fab292d5e6f499a8dca4e189fc047a608ca4c482c36949dca14cf019b207d7b63a9de0392a4b68997b08
252	1	369	\\x035389fbb3bceeb892e8918e1eed1296a24320c92afef69aedf840e8fcc92588112871b56834800d6bc41e77797f6da6c2d7ca4f2dc061449f1d8887c8f15f0d
253	1	256	\\x841af91db610ff0b87a7481eec1883bb6828a168a0fcf713ff16332a3194c4908b5f35d58aae3b8f61e470f5058ad43309dd4313fb3b889875c40f4a05775800
254	1	270	\\x6ebeaf677b83cf184b8bade2f69c651d4c2ff17028573d5d87e12fc3468d2a2e2ef144bd9fa9015027255d4c4b8656ea273ca171dd19c42adf2b1cbf169b1509
255	1	82	\\x53a59729a7d750dd80ba2b0996a22636b17ae007681e9fb3f74384ed17cf363d1cfb18c120d07962a4040892305eca8093a6bb7ac8130e7e0f10e421f7f56a02
256	1	330	\\x5b7578b576db9520fce65bb61746e79bedca0fc55d4529a1cb325ff6f9ba76669549c7fa486a9e66b5e382888051e0e08fdb2e80a8cc531e41bad60007321204
257	1	396	\\xfb4b5325046c4af31072525fa7aa4d8835791a5ad24525bb24c3fc101dd60bf054aa805f316294f0750ce27b4093ab47d92bc690c6ffdc3fd231a4f2e876f20d
258	1	8	\\xe98e56a6c1dcb5ff35e61ee5a25573a9959c3f15798de2795846660d3f63aa7ad89186dc71ca74acf3eaaa6c480de2565854ed88fa2edf66b67a3a9c1c00720f
259	1	155	\\x625104e757d5e544c8a78c27d9c8ae7ad9d824b2716a23c6904c95d384dec64a12121d7986fc86e1327bc37a37190fc61ad8fdbff09846cc3f24956df3a73c05
260	1	306	\\x09a9c39663e6923f715e115469305754c2e0de43a94564175df07a5444fed8bd0be640e64879b53355dab797591c2b5ea6a2ded0ef5f29807b3efcbaf33f1a07
261	1	26	\\xf4b2259aeed0c9ac7acd318f254a6693ea6d958e0338551288ab8b56147aa83cbf8f0f918b6b5be8d55df03bcbd5a1605a8dba44dc69c5e1ea14ec60d54aca03
262	1	99	\\x82ae1ba7beeb6ed8ea262324426b0ccf8f8026569f280d73ec95113b069b9b72ab77381a14daed832757add44d6943096c2f26ac9a324366d57b135f42bdf30e
263	1	56	\\x4f062720c492a5bc22e26d912590d05fea9bb181d54ef2d8914041d36c9f400e3cbc6ba2659edacb44ee517191a7488b16c1fd0454c817b6a199aca176123c06
264	1	410	\\x216c788cf3557c884cb97596b2061bc6b36b914f475f97bccbc01aac264d93d7490cc4ba5bb1b915ce11b7616eb31f2e528e21da062c05256ef3577968986e0e
265	1	207	\\xb1f35efff96a77e2b5fe86a3761ec643d6fb4e98fb7be49b487ad6f1fa5d69c9bbea1309641230528fe3b523f4643e55441028b302b1b1588feb3067186b9109
266	1	63	\\x1a2ebe53c79c95e3380bef4958369fee70e6f85c390bf993354b950653a77de88e09c2524c121e0abb909051ac895e3aa7c25fd0734cfe6259a5ebf8a6a6d30c
267	1	179	\\xbe78b56f3c92ade352f15e4832074d3256d65d270b7ee7e66c4f4cae899cf9a934fd7169e76f1f59e95e905eea079fcd341598b4541bf71d104c7d4c709b390a
268	1	180	\\x64be51f95064f1f7920da01d17356c0a774dbe3b7b3cd2e13485df24bb91932cb5a15efbaad24ba0bd376634e13b8c293587922fecdfefa903a923296e86c60e
269	1	408	\\xb056f202ed4d83650d9f6ce2909b68e40d1e69862c14411cc90abfd45db518ea9c12eb4f9cbf7e6f25722213114cad7c1acd8f7d28b9a45bda50393720965408
270	1	43	\\xa4b1634cc1749d72fea128aec6de9e0b9bb6e2cd66298af3d76b10ab4c26ba9176d222db9f11cfa3e5541c24427ce1589536c2e0afa0efc49768a02c42fd800c
271	1	146	\\x1f09bcb010fe10eafe33611e2a4ca95426bfd3c60c71bcb22cda1918d67a7ad93b4af4567c7f94a8874d171b09ab937dad822b79f73f6352a56f27ab252d9c04
272	1	400	\\xe5b7293c23d52430f44f59c26ffe392515d2e0e7a935a79da686c6daeb38297571c0aafcb4843496e3e36513cdf7e77dd59ece8f41ecbecc2db31a9298d5b306
273	1	181	\\xc55c044b4c93b148be21386656c383a05fbb12983738b5232e59e12ab7def4997c51fe4d14756b8fc12f62b365e0dd5b657d447d838a9692e63fa7d7916f7703
274	1	68	\\x03476bbe934b5ce91b978191bc2a849be1e8e532dc5df1027e38216da230ca2dc1425e33d4614ecf4a12c2dccc58f964aa2cbaa3e778fc002df7991bc5acf103
275	1	327	\\x9703575fa9249d493737177c4c34cd84064a871274cc61ba08bd51a09ab6aa68f3dccd7b07f02f7220e0a01174e9dea4ac56498fa4b5dc8184a20ba50f53f90b
276	1	324	\\x257acc367b70987495bc62cc3903284c6bc71ab3d3087a9810ccfc3eabb51a5b51506c3df39ab6862bc1cf3d80858abb677c7c6ef1ae7b1f84117b673b00ab05
277	1	6	\\x7b89ff150c8b734d6acac14ca41badc1d4381954fe2282c14d603a1acef317d0e14cd9b4095332a11ac1f23921dd5eafeab3605ec5b396993648a3c0d33af408
278	1	120	\\xaaeae1346c9e8ad9e49e4b9fc56bf3721099a7e78bd7e7bd429dbb67793c10f1ee6047c0a7a6a0d1d28e81fb182dfed244af10e9e67345916f633480f9174b04
279	1	89	\\x4e6853bb7b56fc686ec39520f30d96498c47deb56b54a0f956e22c37431ad7199af0906f854a76381bc79a5184649bdab2c7189616b64456ad29c58b0229680a
280	1	173	\\x55b6f1a6841bbd4feaa90f6edc407afffee31f37deaa1cfc64ced20a625fd8f0f08f352b0f55bfcd4df6c5f2649e96db2c16f44b44d1d6191a9bde4d6b616601
281	1	274	\\xa41087d42fa5c05a9d302dba54fc7bb6b1b933dbfc2f644dd46f782b300edae380dc0b1c914f2fa59b30f7927af42580535e352ed51cce08e569db604f7e230f
282	1	131	\\xba0740d264ef30fb8eeb4108845e906ccd4ffe914a3edb11a788fb084f5b10b9c8d7dd41899065811f27fad65f8a8c1e9705ce35c7a7eba8ccc6df8775b40009
283	1	109	\\x5227db8e4be983c33077cdcc4a331315ca37abe1876fb9a34fafb45c24e3488e8436f36069e614d1e8dc9476abc841c72cb985f8bf2196e434bc450bcf84d40a
284	1	121	\\xbd4a96c764272213130558bf4f2650801a9873fae3b5bfa51bc9bd97bc8e677ebceb7ae1775667fdd5fdb779bcd5aefcaf8b73da4f8a1a1d593937b060223b03
285	1	293	\\x088effb0dac875920467e97d8356a162940843753d8a1cfbda2401f9367f70ee630a4da176ee9288195424d9efd15a068b7edd0d50b2c99be70172a1304efd04
286	1	133	\\xdbaee42cc8f7c7cde482f1e4568f841835373fefbbedb18f5886798945eebba95530ddf5a8f85efb8b93b8f153a7c7e20e46dbcac8cb852308aa1c6b48b13f0f
287	1	383	\\x83a846166d70f78f1e634591347138cc3f50376d6f675ce305186caed5c838fdaffce2c052f30fbe5529f29829e1ba769df5427b79ce715cc7d68e16ec4cb609
288	1	217	\\x79b549597dbe5879c62511bce11be718d02441fd5d169d4ac586e01add73f54979f81721c21fb410a9e17b447a2baf01f57a10d259e16e376697d2ac5282c208
289	1	335	\\xcbb175c68fcdf2cab0735535fb06387272659c53dd9c69c261c24d8ce155f6fed7f114b25c397c8f3e6b345e38c743f08e4768c1750266e13aeedbd9878c700b
290	1	235	\\x886009fffac2180ac469c736d707c16843445988e1713f79fe2c2801a99630dd2d9c412834fbdecc50036e01723e5d4b78f903072dad6409798daf79f2f2c104
291	1	397	\\xb15b4ba42e25dc75543f430afb60b16c71fda2c04eeea68de642ff19b15ada77f1f9cf07f9d50ace4ab85cc50648988077bdb7740b36f59076155b863f02a205
292	1	195	\\xfdc1e6d467c4476c128565068b22ee7d43e7feaa156c492b0b355e07c72ad128718994ef69befbab048fca7bb50240b2258215291413da46cd1db021477d5908
293	1	88	\\xce127ea6e274aafe4e543a0d1f700993b6eb4f2e234615705c6635f438d921b2cb215caa3403cafd596fd22fd73e265ced3c198f5afddb4a4cd90d9be80c3302
294	1	403	\\x1cfcbe43ebdf9e9bf31c1f494c82de179b546178e40e210a43b71596aea3c6a5db8bb6e3fd718562b5e742bf3de74cd2928f40cbc445240a54eb5ac2f0367c02
295	1	175	\\xad6879d568ab846736dd862c136579ee42ab81677555e5f4c9c65b71684d30233f760a30cd8dc167c76564ee381739965eea0225d70f8509e178afb944c36407
296	1	375	\\x76d6fe55f1e53f2bd8917ce561e7f3f8128621ca8755b0005620967b0f45907364098e27ab92464debe154535f6af1981bfcf44bd5c5abbc808d800535babd09
297	1	378	\\x553c4b6819b488bfd9780ff80031fe1c93884db4abf21de62a711c2187c1aba4ea9650990cf428edae2016b007dd27812b477c07432c2e3498b0980d37d53e0b
298	1	283	\\xac059b108c840e3577864ddc8f9e66c90c8855e542817d90edc70fe7c80298597b7a672e877f965ead5dbc61e0a05211e25e1f07313548b589deb0d00e3a0702
299	1	412	\\x3f8763d7f0eda7c70d5d762efae007ea7259b17bc3e2d2afab172ca8b78beec0b37effede3b2bdd0aa477d251f7d35dd5c5d7363083e91251eacb8525a668304
300	1	72	\\x016a116d094a97b276705440640071df890dcc0f8c2e7e7a1e3737f57a2852e6ff60fd4b3f9822cf90a7d0fdd9f473a87254765274cd96e594ddd60fc4a9b20f
301	1	117	\\x0c1648d12e874387401619357befaaf5176992c8a5ce331aa49cd902bd47777169760fbef333d0413b876737441934f5da683189a5adb5bc758be5c39574e302
302	1	310	\\x8cc117a0d8069a9743f2dff9425ab4f9b3eff951ad5ad3dd3b16b6ce6762e11a2778c3032b27aaf21b8d210e2f9f35351bb51b3694d5e8f30c8952b2f7b61206
303	1	202	\\x615d3a51a87766f3b19e4432c3461eb130c13fce497c593fad93d903ca2a456c292ea9dc75f7bddfe6e6fc5ff228704d098393f5ff62d84e8783bb77b2efe509
304	1	302	\\xaf25149828abce90e996e0bf98bb6ca765e8eda2af91af5720838e182233dd240ab498bd7d514e35f6f3a213ce4af21018a23aa2f76ac3a31bc050c3efc81d00
305	1	162	\\x4efda8ed0df67662935fce51fd41561c2f3b7aa843bef024137a59233b75b205729564447ca976bd613c0c96bc5886bf73c051218a3279829c2e270512a8420b
306	1	232	\\xd5d05f7edcdeb7a46923d47b90d95d386036903ab05c49b960bcbfc2db4ebda55603ff4e17ba61a02b7730a85a4cf2edacdab3b584e76f58dbf442d2022b1402
307	1	284	\\xa78bbc83d02675cbc7088d002de10e444bff1b958aa424a557582aa3abe720307bd33d7e705abc3f9db082f4b33ed027dc18eaa315119b633b41fac436721107
308	1	367	\\xe566653a190ec9440fe947fb088fc916a58de07d8d10b17eef0446c6c61be69492c9b9374229b111a45ce3311e5a9cf537e43975ecbb70fba855617908a04b0f
309	1	366	\\x770137e5a44855cd916eea39cd419ec6073ab97b1de76a1caa8491188e6b52eb0178391ea305dbcbc2bcf5e7fbb5d87efef40fd247930b9f20c2f4d06c4afe04
310	1	60	\\xdbf18d64f620fdffd9bc1734c2b2fb8e1851b078291e0ad2d6dd7f22b2a0fc766edb987eb536b6df5c59cb60fd069b724b0af2e34715d8ea59519d547bc0c50e
311	1	381	\\x04cbf552f86faaf6a0aba73c01853d51fb5a34ec92a75fd923ed9c44833180d5ee8b2eef3bfa68ed97783366c20dba855ea8ada11504546705dcccd3eb7ccf06
312	1	418	\\xdd67f01071496b33e8f485f333677eb38fb0d00f5667e7bfa1ca832cb38a29335b6ad6e22708457c41f3e9aae6d97e8659182b419b5c04b174d180b4cce8b30c
313	1	141	\\xb7eb2bede9f2ca98ab08d8f7780345047d97227251609e86285d3b3b7dc3789013076cec14abbd7d96c96bb42de373ff83f017723cccac7cc553b42124f74204
314	1	86	\\x369aaf9dae6c8bd67d2324b9f6100b1e3857c9bbe9837015a7230c85112ead95b26d53a2cc6e4414a1fd36b42bbcace9bc97836f5a2482b637b9c4be21a5490b
315	1	55	\\xe2becc6547bc852d52727f3b67b77a0f268277cbfb298d5e7928945caff81a3ffeca9a711e1faada26742f99e865da2dbfd9a8c2d97abd68e3bfa3495218ba04
316	1	80	\\x6179d33323ea236e3faabdd37a25e2bb49f432ef13986c1051fa4adef5bb4df8fbdfcc9ddb0bd032285b074035f960320379649ba0d124492433e16af64efe06
317	1	67	\\xb702402351bbba1ef069bf33d560cad1c269e7f633bd78715e04a307ad7ad326c55c6df074c1756c3ea921f9de2c4a30940034c756baf6b13ac499efd04cde07
318	1	321	\\xf53ab80e7fc9e3f2ec5a5588eb3a615af929aed01a0c1b18d1ae10026460301c84455988bac4e7fe17d5fe1c9ee79b4fde5b1bd8dc207c473207d9460224fb02
319	1	339	\\x0b42978fe3f0f4ce98ce7c2170827c4f0f98025df5d12979c016b0e45dffe8c68a6ed2586cf83f727fa9c2d155f3659749c4148b226182ffbcad779406db7007
320	1	174	\\xec4414f997999bc6689670211e698e40bf766c070226325721ac7d677e9ee8c1c755d0d05775383a3058387bf414c1c4ae8d81e255bc5de3e1290fd511511f00
321	1	105	\\x6d2a038d6a23363a0f9f8d8ef29e7f3d4ba5374e15e34983785ac077ef62efbcd4f165af387cbf9112d8457b923a712c4ab974167f1e94101aca24604f03d009
322	1	7	\\x7f5b1737b5956ce6e3082ae54b53cf7bd0f578f4e043ae55f9d95d9352dd9576088163bd0ca92b03b639de8aceea449ef58a0e007ae5ff3183f752bd164d5408
323	1	14	\\x15011d979c6be30a8e8397433a9d0f5db13ca68da15f1e16d0f3e1da50123d60df40c98169e8137de08188989ce92a78a48a5f6df7b1f43afde4cc7d6dfabc0d
324	1	218	\\xa84570fb2d58dd2930bfb3bd40fa9e0bdb13062a3b25d03b0a57188e8e58bd4ecb7cbd66a5fdf321dfb329d5f54320e1ef8cedb9a02875858cd6c3262a1ee40b
325	1	215	\\x0da0e9c593f7df32bbfece7023a80dd2ed76dc5a78d0e03bd0a83edcda2a2c0b9d61615bf6b07c78a93bbd0359908be250a0f2605fb0e148671b632994ff050b
326	1	373	\\x5f194ffb832f0b5a3a79e3bbd3092ab9395691f8aec8707110ea602417bc01a1dd281d3285f2a0d108f2f1088f597ce60655db070c74d4a2032529dd3c39710d
327	1	91	\\xd8572b152e2d542b06c26fa6b826f110665964f63687dc7f9338424622fc622e149e8585228827f9cc6c7a5ba75155b40545c5a8831c908ddce765a52c899c0c
328	1	297	\\x575922bdc8f4ed2e016c9a6c97c779b7d6179b23a9b3da03f15b6d29ddf3a3d6718f9eff270f866b12ca28ea68135731c3df7c8351b44ba63262de2ae7df1802
329	1	161	\\x3f83038abb5b328246ceb2921093ea49ff60afc47d2d1189c8a868a0ba3a54ea5255c64d2183b78218fefa78b70ae89cf67d9fb227de314df6dfaa9e08ca1300
330	1	62	\\x6958295e4503ce2dce78a33a5d161e7f24b8e3f5fea01c4cd64024a271597e5246b29e0bdc27bdbcde867285f571ff57fbe4a2049ecb6dee97c8040a82dedf0e
331	1	420	\\x5e10c126fde3bff91ed0d668f2a527bbe13314408d7858a3c277c677f9dadb0d86ba90ea9ee63d472bfc985ff5a6d6ce7e7094fff6154c83e37a889b5181d60b
332	1	386	\\xd1f1094fcbb3f3458ad3c9dc8575e519e43dec66d5f63be01a06ce889c08b348bee4d1ca08eae9d8ce9829c212d95c19bac43950ad5147123dabb08cada2b907
333	1	245	\\xa470c2a1676cf76ac97895f65af49863cd0d3d0ac104d9c111d2e9df130ca0d2788d0bd56dd35f24dd41cb3e7b50a8379ff6592539defd103e690a46671ab40b
334	1	337	\\xf55b6cc174b281f08041f9cbc4c7e1c10ac853fa8a4988d46a62165f282666489d9727105380616d996b43448c4c2c41d5cd2af43ecdc1af65981b9d17f7cf0e
335	1	187	\\x02c29c6391b948b13e45a0b9a416624616fb65146b712f391b52f5a9c538c0f6fc2d11796efdbf53564c5caf53feabc6adb136c13e138adbe92f5eac7580b903
336	1	189	\\xed510475c0530da47d3d195b1ef24020cb3d502a151c70c028d3420a6bb6437df9b60aec394e21864b1d4894e1082b52258fa74bf4eece6a0aa13bf40c707708
337	1	419	\\x6e499099563d450e3d4abe84970e2ad5c543127b70d96ea3a72fbe7566c06b23176d11ed5798544630126e723a9fd0d7639b68e5cadf4ca3c1bb504af0087206
338	1	377	\\x432be3a19d3bbd0daed7004f57c7f9f8a11c08b1dcbf7d1e02e5bb9eed3dfe768a37849d8a944ce44ac45febf0a7a8b259b1a948861f5c979005bd8ab939da0a
339	1	223	\\x0f904e00804b7d0186bc247df1921b01efc96257da81a2f993b0319fcd063ac1b23e0443d12ecf0f6aef6cc1848abf62d729852649d19b196d74a1a203313600
340	1	265	\\x0a1ca99012713be2b948660ede90f92d1b29982f2ac6884ed283ce253fa425cbaec58a86d698fba559981f1aaffb93cc1dbd3d7c213badedb693a644b4e8370c
341	1	51	\\x3e88a5e26355761c80e3cb50b2fa4136692c4c5d651d801893df60ea1a73935644aac59ce90d5e846590c407ff6d1ec16ba82c0ab036cb79e70958deb721e90d
342	1	122	\\x799ec593e3cd923da6116d352050136bbdb72edfa8bd1492e8ab5feb55e5e5f01962ed1a64500d8b5b0fc0c977e0c9404a7d82e1c994d9a1d2d050b9e9f7210e
343	1	95	\\xaeb361a141b1266be84197787c7f144398227d0a5c21299d463a8dea0a43f585a4d7600f6829fbcb23240300eac1674b7479c33bdfd34d47ce2afd0cd102ec04
344	1	299	\\xf1dc5ac2b9d6affe4a53725f79bd977425078e2e3bea6305da2f3178d462414e953a598581ea331a0b497ef7e0208da74c1643f848e7ab41e4d746dd0b81300e
345	1	382	\\x451b14356bb1e2649a829dcd79ebe1bc5624134333b36d0d3e103e7c19df9cf76d5dcdd2857e82f814ffb3821dd1a0df908062d02a08681d5b852d5b83d9e408
346	1	45	\\x79f86e0eb42c00082334da8f96d51e1f0a14abf39b7cbeba4a32ac64f69117246689941e1a3b814a6074903f005fd686344c4115180b1aef78d9ee310341c004
347	1	154	\\xe4cdfa3b9c34f06f574712b43b5e222c75b924ef6226dac3f17cd0a1e872a636fa374c378aede620a923e03bb0390c7f51505e2d991081d31f2b185faa2bf60b
348	1	290	\\x28061786e063f377554b5e7e538051dd55e3239affee2a4ab6bc935db701843eb2efd9d0be3598fbd344a75f580926ac097bec671770f40fe64a3800bdfc6809
349	1	226	\\xd1174c1e7625295ad20160c9e160b2d770477b69d7b7175996966c4e49b2636bf4ca0960b4bfb4f6636d0bf9f6fcfe346922527e03537de81746eb66c178fd0c
350	1	303	\\x542cf3613045e9cc3e37d515bedf16d8d631af09470eb5db75de3eebc920bac5b90d5d5b1c3922cdb079227aa229d3007681f85b8b10ca35440c8a71826ac107
351	1	374	\\x0350dcac8dc8c22063cffbc6d76063823b5ba8dd655eded4131b4bb6a3e87818f9555a028d990f0a9716c602e653edb635ef7bf8987913af868f0c6920bd6e01
352	1	309	\\x407b5e3a3857a4d592ff02bc75bc97e30a658eb7e3aa35831476e66f496a90ab0e7f5ef85659ff1b54724827304c587c4a611ba38163a4ddf3740ba75063d80b
353	1	304	\\x3d4d985fd3315bc8cb98921e8f10d8b554b20cf693e447ec12175482d0a2e2a9c4e65e78688abde685b21b9c097757d1c81606b8417ecc6be710026d0104be05
354	1	27	\\x4230119c7e59e01e8f5a8b1713b47878fb086c506c5c06380018a00713a53365fbd0c8c431b9f66f5a7c4e1b13bd9bf5143f8fe0817112a1d23a0b9ca8137c0d
355	1	93	\\xd170f5079d8c66d4e409eee44845cbde2a306dc873c9c2fea1bdcfaf7b21a73739b0c9404e7735bd0118a131fe86990e15771b7d274b59938c2847ce66201500
356	1	4	\\xa979d8336960bbbf30e5263f48515a8c945dd69538bc3159b5806e3f2200d9e4a2bac9a02ec0e5ad166a73a796ce6b1d0398342a06903c55c6658782880c3c0e
357	1	249	\\xd869ffeb75fb903350149f291927cede80be239436410aac2d6bbc7143f7dacc062a216e2aa8ee0d62daadd5cdb4792cb22484df99b4496d3ae83d9be667210c
358	1	349	\\x1058a2b475f13830db186674b67cc9cbaaca18c38820ba0a3a40571445ed98b46c71e3a3c201220d8c5ef816771846eb6519c7bf70055ff2d712058a9c7a8a09
359	1	165	\\x98ddb8ea85df3c2f6b762643e9ce6ff4dfc9aa7658b70c810b7be382f088a17753718bcd96b1b4620f02c6d709e164ddee87719897599a75d62cfe16c90b4100
360	1	143	\\x2b11a674c54386c70e66ba9aa7f1d665b171764405b7697b9f92f2bf79c37f3641cd32b8db926c1a76acf2907c73be4b93e08efe1f675522f81839d4f2ab5e00
361	1	108	\\xef2918a31367046a67480169a812635afb20b8ecc12db12fb9c57d4193e222078ef9f94ad3fdf179c39beeaae1b11897721ec64d09832767237afc9e6e27fd03
362	1	112	\\x1f9295d7dd4ff64649e7349f7204d6fec6d9e91dce1d2968a3ffcbd402a2576458145b75a622f92d6ec796e0b5265195a5d0590cbae0b4ab6547926c4faa0608
363	1	390	\\xe9377b6f447d569726f84225c6eea228063b1dbeb598907e3e863fc18e5619c21547d358ebc1574ca89f87151d7d99b2cddcfccafc22359366a76bdc1d24be0d
364	1	220	\\xec3e48b20d65ac24e7b157a7845bd2defb3394c7db00b737e310a079175f49428665027f03aa8e9350cdb14459726cf397d1955504f5ef690f57e5eb58c84609
365	1	100	\\x6a392c26416eb1f5c7fbe67a7424d5e7dc5a4196549f4aba72efcf547a9bcd79ac8e99d48fcadbb9b98bda476b3b5659c2093b83e7fe42ea226d9c322fa7a201
366	1	250	\\xb4c92b7c7fae1a3733f14092a17751c8e205c01a02a7b88865ae6807c41c3c645f662c483d900c6f4502b5aaf27e72396cd4bd9368a1a7315cc506d3399d410f
367	1	314	\\x10d36ee1e9322df7a6634cfd6d3c53ca12b0dd4f2e8fd419269b3243463e5bda2a46f3d148db55e887acd7ed03810fe5a3d10c2501836ed65a777faedf41940f
368	1	301	\\x3f40ad0be939cf5f2dec074289d512ee24e6cef30cfa3eafdf54bf576a3f2c8a2bf486a787d338753455cca136dbe383e6b6d922bd9793474ce4d0844fad030e
369	1	198	\\x37cb1c2cf3764eec2a977fbfa8f5ddab947fc855560de5e6e0e261879e54970d69fc99647b9b4dcd52cdbbb37136f94053dac3de4844c5c6ccc6da939c090d0b
370	1	224	\\x2856971a38ebb0bd5c2123a1764ebc9238c82bc86ace1ec08bcaede07758f7e971b011e1aa018db5973c0c7f8778647b59108ac5fb9d9d4d03748ca04c46360c
371	1	394	\\x4a89d1a3c69d61f4b7bf66dea39ace6b554fd83c57f93eb8d84015a6ffe8cd0e2a31344066600be9a49fea8ccc1302b70ef076ce551e77175cb1c6dad5c4c50b
372	1	233	\\x88dca1bebe94ee4c95e6fd5a69f5e3a189343df0eb06aca05fea70d76ed7bbf3cdfd7d860e1497028f9706168ba91c3a758744e0bd78d4fee1bc77aadac4750c
373	1	36	\\xe1f4057da0ccc7977e92c44f0b0b45da6c59bcd8a2e6f00788e9dae72cbc7f13142e18089194da7ea5ace712f64fb24e06fb444b055d2ca6ad6ee0bc8be6c40e
374	1	106	\\x449fcfe9e3a25bd51849f7e80aa1e51d794f4a64f6528b5028ab1f6878697bbe8831d9091ecbaaf6af2ea2277d119808575e42ccd2426c86ef3d26c35f244a00
375	1	319	\\xbc64939537fe0706ce3c3fa932f1346ace80089cac3cd8d4ce51b7daab30f5156b8b6de4f42e6032eaad84a3bd2ee36ccfeb1d5bd8ae890f3b03b883eb1d6804
376	1	104	\\x4a4433017ca3b4498842464aaddd65492436d775267ef5f4dbde7dba3467e2b97283b576218ef34a90e4957793bcac11614fa156b49244056c2d96da7c413808
377	1	57	\\x7c9c820fb20e55bbebfd862850a97c2767b90dc31a928a63ba968556c9c330affd821df74227624672ccf01ebacf6f6bd3fcd626c95134650afa65d4a5ab8709
378	1	273	\\x25f020a3285a9c5d9302c8a47e7af52d159bb0b23f71b80edb17adf0af844ede6079d6f2e2ec2f2976f14077599dd419d5855ada2e118c16c042fc697d1b6204
379	1	351	\\x6ca1b4a50ba9d67a2bdc90d304658a47583000cf140d513476340a8129cac7c9824c02d2362f209bc16eb876041800d2cd11ba722c77ff6bf5b6e925efa4fd02
380	1	389	\\x4d7f0c9b77b7833dd1de17f3b09b8c3c3d5913d157b7826058b94ed32b13c3b2951436c12c310f2198ddd9f904c314e23472ceb6e98bcea8ebc525a278f6ff0d
381	1	287	\\x57abd14575f36886026f3230cbcf30b5ceb9595398c8e5ec10f40508a1119c88be5f1019413b7bcf80977f843f95bbedbbbf2cf8472793515d908ba317916007
382	1	158	\\x6c5f1ddc5cb4e7870e0a8b5714c2fc03e571a213bca1703d89cb826542559073ef6d3b88cf87d50745d3f1565164257cb2733e732fae64c345eaf4537b1c1604
383	1	172	\\xc97fc65657d90dd9014e14094ecd77b3c2a2c7b6d92739e52d36b8b577649e17b4c8dca6fb424aa3e519f211b7feb9267c44e989314a1c2549a4b00760b1df02
384	1	343	\\x8fb78a7c8e1d0a78a4aafaf66224e6d6bcc724280042f1d088487ece6323156af98d441d48babbe66c3281e034a3fe4eb2a6db92af010a1233789abcdb7b6a0f
385	1	114	\\x2507414ffaee47e18d2377558ecdc737fc68eb50feb70edc0425eed11cf5050c62351ba10783df936030c91371255174be1981b56b02fa6291ca7fed397b5609
386	1	124	\\xc0703e7e269f506520c29f2a8d3d8923265b4692675fa466e5d6c95e21041833ff33ee486e1176e8ed8983e3f01340ed9e441e2d1ad491975166fcc1f34eb209
387	1	317	\\xb822192bffbbb7b577d128c573a26b3a8ebcc76bf13ad9331b4c3fe34354103ac13db3a7c35ef9755aa6a8b461deab07a9dd146c84a7bcd66be7d3d272139607
388	1	387	\\xe65a7ee07b2d5379a69f64b8091ce68a436a3c00518217e6685e26f31b2ae4c22707c37da4b08fc523feacdddbb4918095114ef3c65ee588124df49ac4e8d20a
389	1	358	\\xb05953bc2505ed2f44c12f4b3c434943471bd879acc261e6fcfd25ac0b696786197bd97be30b065e212f8afe5646bb7ad4e69b53504b57f1177dd14f45a35b05
390	1	34	\\x34626df5645b3f0f2f8a78414d823af035b23f2194373931cc136d1548e16f45824b1234c51ef5db16a2a539af50f7467966a743b07dd85cc74b4fc91e1d2e04
391	1	119	\\x0d56f7f972ef94765fa8387997d520915fb84c3c17761adad94e8d1c5c91b0b7782a75c72326ca697eb94d76317e3621c18bacd81d90658b9e2c22f5c5fc3006
392	1	148	\\x33a9d1f811d7e8d4c427723a6f3b4d32468d66b608adc1709808a473722bb7e4199c4ad4a981808ecda946ef18cc470fdca318f3c39d52405c9c04f9b5cb9b00
393	1	261	\\xdbe85a7d0a2954d2419fdfbc1741aa7dff38bb44b8b50d96fe1dac25e7068908a1683fae3bf08fd6bbfed9ab98a5efe0c5fb98d7c2c8091bed5f0792eced2b05
394	1	350	\\x0d5ad3f3ed98d651247e3179a7540c8f660fe34843e71e98daabbb571d3c0b949f19dd782374ec93e079e4a0922e14c5531bb3f807e78a3971efa8b87e52c90f
395	1	3	\\x1519fcce4f3b53c27df285358a54fe5f8570d820ccbc9c465a8ea739da8de03fdf82fd79a2c1063975a85f7b7db2c9814f2d7535c48edb25c510efc5df05f506
396	1	348	\\xeb85da6d0d1aa241e8716c14c905cdf4626c68d55a8fa3281c779775cb2138a885856c069a15b2c7174f2702b8f3f4ee734d41384cca64f32af87938c33c9700
397	1	294	\\x4b88da3754a12af35c40de13cf4c0169eff2c8dad3e0079de96de55c6833ab0303d8dfeae58e8a4a066182acc554980e50c83a5b7366b5bc3a36053604657a02
398	1	279	\\xefa293d742538c16d752690ada63794d859bb04d7098bbcf3420751dc29ae8eb90d8bbb4600e347bd844ba13b1d8ac34d342a7aefc3dedbab30d6b887fd66d0e
399	1	90	\\x1bd890ff92324e465507f6265b1678a38ac01fffdd5c8bf6c1e92939d9ea91a3a5e44e099e43f8a55adb226e99b96f2f4b21701b041c1db04f2adc701aab1b06
400	1	205	\\xf3d5a4dd916affae90bf4107d2653c0fe78b8abe44bc723c5a4d53451962e991af5879fec5da609f4824e58b19fbb531ebc9d8b2a09d38bc7ce7c038b0c38e0c
401	1	111	\\x028bcc464d4bb5136757dd5d842b523869a539f2afcce7bdab77795a9c3183ca423c320a0519a5b407fa05b8c8591f2dc4a8dca13676a19471b3f7e9b2e23002
402	1	164	\\x5626607133588ba57520d3d413e1c934e3e80d91f67a95d8ceaf0135ca63c9667d7eaf01979715a49c507d01d916043e7549eca2a75818e80ce8285afacbb90e
403	1	21	\\x07ddaa01b6ecf25b034938d1add7651b9adcfd6d080dd4cd8913cf85afddf0b9fd22dd3d1f35199f98511304d86dcd9ed0017895dc85d5bc6bcb76053a09950d
404	1	291	\\xe319f9918b969d41da360a62d3be5fbe1cd6d12c37542285f026a3a0b6c0b8eec2cd91fd4ebe74f19e7385bf6750d43667f8c47ced5c7358f303313555bc2607
405	1	75	\\x4a779785e4c95bb6f3e47405870dbf2b9645481d332e09d1b22df9380705a8e382e530877a59623f0823b5198a03fe3a7a398b503a61b3e334d2946e64c0ff09
406	1	113	\\xc409fb4b5f19fc3311a83e505e5e8b2d94cdf448e260bdc8804a98502b81c7226056cc889d64c469f013276029a737fd454506bebd5d90931ffefff05ead1702
407	1	83	\\xe0a9d64ae4e71fe0c4c067c2f928ba450b865ddd5651a4ca8a3335fd3e88fb46082aaca2bab56c9a0fb343ffc977c0c4abb85ee274b3f08eac5750f3a37e9d03
408	1	258	\\x0e915af2cc2607bff0354d7094799514c21fb854c48927a43854822d2895b4bd5d3562289f87fc0a9492d22e585f71fc7ff152069bea9b1368388646896add04
409	1	107	\\xfa47fa97ea09509a0cb4058c8ac337bcb1859bfe75008fc97c866a2be64b9d6f871c9dbe77241471c37abc21aa053a17a220da18077288a9f1a6fdeac869b30e
410	1	363	\\x98855811f63f215e189b1c8720735caa19031b83f36f512dfc0dfbda20d7cc68a2352438767a13ec09827d4ac2775016d02baa047099a2ae5532f5045d112e0b
411	1	228	\\x2af7fa2a7c1981072d3fa0d9d8b83841fb3ab770146906f74b94692caa65ad0bd19ae506f6705945884e169fbe62777369768b56c2faf5d8f7d1760f973ca00d
412	1	364	\\x750695b6468d67ae6b85e0e9eceb2663fd914f9b8701ec379b5950b1210ade4fb16ab005803ade57f114470d5173a1f78a78ea69c9b503ff2887b9ea02ffb100
413	1	19	\\xe799ddf8a23e47c564f664956557f95f7cf7266aa00001c51e2497a062fc4e6e89d689999a9be48d8f005f04749f0c777d3c00d55ca64cd16e031fe0ee6c9f0e
414	1	295	\\x81ef282361661e1303b9acabd0496f3863ade25d783dbc4df1d32b75f1a12d0ae34fa42f3c45dc8486e1d67a061aa28cb0280db84ad9e7a62c47bbfc28100600
415	1	405	\\xae46cba606c84093cbb3366d6a1432da193dc27d9524673e757991968613ad4ed5d227f84f33d059f0ef3b32d7d0520570b4bceee0fde1144cd342b292798802
416	1	219	\\x372300cc4e30fffda5f216e2bcdc5e67097b1bbd7a84f2aca47e92ea22f855836e44badb28d5598fce202c30379d3c2f95fd29d84331808dbca0e4c61811c50f
417	1	193	\\x7c7db53fd2a4a4969527f8032317116c7285bd6b92ce9762fa1aa1d4f68a5aeca7367db56967899aeec43ac67e045013ef6cf2fdf2ba08c6ddcb45b137e65f0f
418	1	222	\\x263b4298334cd0da11054affc564e15a7437a6633c07452dc7147a90a9d7aaa055c66112975e6e39df08a198487276bb61323ed3913e6c83aa9dad7509dbac02
419	1	286	\\x5d9e79751c12332405b76ba30cfbaf54d60149f4df36ea9fbbf80927dddb9bd063878726d9eb69d4c2c0536592a83f47dc71e64f7229aa2e5bbbe6b0a4599702
420	1	71	\\xabc158b785d3649bfc5300b5be50ce311d88447c14489e2a7c690a8808f2891e35ec317bd85cd379288998c5d57d24676ee8c1cb5a00e6e1be95effca038c404
421	1	311	\\xdd4e0f61241bfd86ee537aa4011a6e71ee49b960434a823b9ad54c99b6c0ea458eff8be315cc37b145bc3ebee22d8d044eb893387493a5aab15ac09501c4900b
422	1	289	\\xb884134ceaa91adc5dab7ed3a88a1269715f209a930c0562d3a0864b66df66b30fe967af2ef5f68d0db8fbe6cce6211da2e1d107d40204af028c029ebb8df10c
423	1	422	\\x1a8f296fdf683873b82727e976d1d163df6a82398f37beef5af2ddd6c4bb669dc60b4099843aae90673718161e7ebc6477ab413ff8aa015618324cf318d8a605
424	1	282	\\xcfea66c341513aaeab905e7a220e614da776713550a7cc1671fe264ab1c8e8a97c407694f7372487f5617247d799b386d226e9ae9fcbe806b7f912baa4bd8308
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
\\xb70449afaef34ce9d6d1c40227642fd8fd9fa16d71b1101607c60d54b51b67a7	1648383090000000	1655640690000000	1658059890000000	\\x9e9ab2f41775a8c05f6258d23147a0fe348e3261c4dbdd7e67b378883a0a7fd9	\\xc9caf8cffa338147a917aa6958a17998948e7cbe377838ae9cb1a5ae95178feb77c0b2927960c3328c1eaab0a18e4188ca4e4f65b1f58de1f938a914a05adf09
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xb70449afaef34ce9d6d1c40227642fd8fd9fa16d71b1101607c60d54b51b67a7	http://localhost:8081/
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
1	\\x528612593b995cecaed6ae5f292ce91e73f8da96161c345cb0b1cbae57aa4514	TESTKUDOS Auditor	http://localhost:8083/	t	1648383097000000
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
1	pbkdf2_sha256$260000$Rvrq7XwEjO51NLkqm4pjwY$AgowNt2Kndv9Cm8Q8bJv+MXS/RYp01wYHBTD3OVtwkM=	\N	f	Bank				f	t	2022-03-27 14:11:31.004658+02
3	pbkdf2_sha256$260000$CIqIufAWB4DoBlgcRMt9DD$uBqb/E2/heqIQnLWVxFeKoBBuMOI9UiybDrXBo4aVqE=	\N	f	blog				f	t	2022-03-27 14:11:31.27099+02
4	pbkdf2_sha256$260000$WXd5Z6BdwUwJgY7XwyopQB$ks0AXJiEjaqiUr3qY5SfebFCYaxbfeH099M73z499bE=	\N	f	Tor				f	t	2022-03-27 14:11:31.393632+02
5	pbkdf2_sha256$260000$KmA79sttVFKrVLs8ZJjbZ6$uGrxbI/ghi8IIDONiTpozt4u6f3m9KHs9AlZLauNI8c=	\N	f	GNUnet				f	t	2022-03-27 14:11:31.516258+02
6	pbkdf2_sha256$260000$E5D8EC1kbreGZtCKCwClUT$YdxbRjAzgTFYrlM2vJWbb3vt/ilqFQoZb6baK660Dic=	\N	f	Taler				f	t	2022-03-27 14:11:31.633905+02
7	pbkdf2_sha256$260000$1zGAWZMdBQUcMh5CivpuI0$/VgYayvZwDXEYirx1PXH5z8DAJtT9/LZsoVyA4+W4FM=	\N	f	FSF				f	t	2022-03-27 14:11:31.759146+02
8	pbkdf2_sha256$260000$056ja47RNlZ8vEdtmxkTjp$7DE8Irj0VZWy+jE3qY6mcjRzuXsyuCok2dzrcXzYnrw=	\N	f	Tutorial				f	t	2022-03-27 14:11:31.885327+02
9	pbkdf2_sha256$260000$0MsnbGWM7eB7Gti1eiC2Oy$kuBrD/EMrpEZbfiQNIojQtu3+QHVn+tGIg8zd8zEk/A=	\N	f	Survey				f	t	2022-03-27 14:11:32.012521+02
10	pbkdf2_sha256$260000$KDmKhjFbQJly06aYqmojwA$d93YdYXrCtbLofBfOJIMPuaIiDY9acRNIA3jeuVy3Zw=	\N	f	42				f	t	2022-03-27 14:11:32.421174+02
11	pbkdf2_sha256$260000$eiCdiWqW0S2JYHvUNVN9Du$SmoQ0PpqdpYbj36sAHx6dRZSkTS8cEx6O+JQId0VEjk=	\N	f	43				f	t	2022-03-27 14:11:32.826787+02
2	pbkdf2_sha256$260000$VRIKhk8kHwgpBZBeHLNJVT$8yWkt76ygkwVtEAC44Tu+oSIwKan2FLUl1/YbfQzEeY=	\N	f	Exchange				f	t	2022-03-27 14:11:31.142269+02
12	pbkdf2_sha256$260000$Bu7Se0qA61AQZUIZYxEWFr$eM2qoGf/0DPeg5lQvxhjcntf6YQ1xZItyT9cG76365s=	\N	f	testuser-5pnyer1b				f	t	2022-03-27 14:11:40.518449+02
13	pbkdf2_sha256$260000$q2QBc0eFUFcyDnCAu1wOpY$i3i2Tc0C53aGNoEzfsQZTBWod9Fpcg2d7pT5J8PiHFM=	\N	f	testuser-t65bdovs				f	t	2022-03-27 14:11:51.441035+02
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
-- Data for Name: close_requests_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.close_requests_default (reserve_pub, close_timestamp, reserve_sig, close_val, close_frac) FROM stdin;
\.


--
-- Data for Name: contracts_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.contracts_default (contract_serial_id, purse_pub, pub_ckey, e_contract, purse_expiration) FROM stdin;
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
1	\\x0ac45c0236473419dd839a22110e2d263db10ace471e662085cf97b6da7f08f665868bd350c409b63c9ce19e2546536b80ba4a38225d978edfe912d95baaeda8	1	0	\\x000000010000000000800003eee575906817b21a44639e4d20742f6278d4a1d13270a66715fccf2e05ae51f171cdd70d1e3f3e4e94fa97981e17ac8fc6186776849fea107e75c25abb24136d815fc0ef730aea28469fab84968cd92c27059f3e0ada011d632b8ea0bb15f581ca2fa5df4a2def9f71c8c0c772d9821784f5baaaff71784a0de2d30c8f9a45d3010001	\\x255daafdb11c176a14571b234f44b2804cf75255aa75b597d64a15c356f2ac776073bb3747734ccf88b64f4fb6290ccca47fa19e8c37ab8259e2c160ccee4101	1678003590000000	1678608390000000	1741680390000000	1836288390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
2	\\x1134f9273cc6c581962b187704c0d209ffd687ff4fb6a9a32107d28d8e89b51ed3985fcd352b5bdbf7e31df7f14ef985cb02bb48019e6bcbc12fd77395afff3a	1	0	\\x000000010000000000800003d0d07cf2e34fa5afc6b09c7e5f0ecec643ba5767ab96538de26dd33b4fcaf6acc3597c98b3f642f00b20e1764bdf68e9679458716956f7db9e876518a3fe0252fa5163a92ff2442d75f8a7d93fcb306adde0aff4a17404e930f418c6e1fc678e1b5fb5b0ee1644a25df6336c6bc8cc6c2ed1f2c80b5e7da9e1b5139c4e094771010001	\\xad3ea194cbd013f1a71f2431fed47ee710e59abefb46984908676a918224d0edfcb89e5c2607de5bded5878c40ccf67527eed9a28ef11631ab193ef785a99209	1662286590000000	1662891390000000	1725963390000000	1820571390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
3	\\x12e8fdd8291d80a9adc1dcb265068ca9365e1b1ce5a72aadb75dcf26f4caea3642a376e806f8c2b533796bf843cdeb79049b6d7b0d9af01ac4c7ad9cb6ac1bae	1	0	\\x000000010000000000800003acf70003d2baf3a4af86a762dd3c573a65120ac081e0ff39fd96a6c41b31c3bd45f5b2757aafcea27999ee7ddd184caa02aeca0d565f9d197fafe1abf58cdd0121eb8935e845658cf8696cb5b6e15ea36ca688456ad75dfc114be990570b4352898bd5a77165d124d32e4b74f566f1bee452e000cd3a535cc9479d30388a0b67010001	\\x529f1f05614711ab8ecc3ee57b07422660010a06e68d1a55a3d152418b877961162620cb683239dacf7b1d2191ca09694d8c2ff5cd1d2a4a6cabf614c633e704	1650196590000000	1650801390000000	1713873390000000	1808481390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
4	\\x130c1d290fa75f2cf9b7cc34cc8ede7a8de4e1f0ff83490b2bcde1c31680570c87883bb7321b31905f086e1c393043a7e8659ed11837372322239fd429069f27	1	0	\\x000000010000000000800003a44b7a623355c85593f010200b618934de47801b476039e71b701f40de7b9fd2e7c045b62bf16cbcc002808b472cb4d88f91269aa0ea838a48d231ec78da6cbcbc404450696954d85f3cdb09162823d3c2f6f0f1596faaf5d28611d1a8c6cbeec0c7bf18aa71bc5b2bf805495abeaaf33e8f8e5be30e11c72da066477fb88ecd010001	\\x94aaa1175b896b6c27529b96a9178f2f81756c9124ce8f48650d8cffd51f81d5998d0ea3c9fa28eae9a2df3b4554ab0fa6f3823088af533bd3db22cdebe9be0e	1653219090000000	1653823890000000	1716895890000000	1811503890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
5	\\x197c16adb5f0a733228fb9a1fddfa38a1a4b1c0683faaee383a93515768464fbde008ac0279188a54b3329f7ede9b59a8ff10b0ab1df5f4e71bc89712904096c	1	0	\\x000000010000000000800003d31b3df0d0b1bd5315502ee71b8468b3411f41f472fb54949d199b0137cee7c94fcb660d32138209f4f7d7a2cdc423e0ac9955504c73bd14d30d0588954d73b902b9aa8758617775600117cdd8691077b4855b868835f057600448df2837ef94e73a8d13d3b1cff29f179d7744eda5d8741c81226bb4941981c96adf29398013010001	\\xb13edca1e3840406071f2ef4cc167fe1ded3150a13384da46da0ac851fd4a349a04f3d1e969393aa385d5764eda69bdb3c005b8f879773a00f8eb23461a23502	1678003590000000	1678608390000000	1741680390000000	1836288390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
6	\\x1b00451f4d3283eb81809d7268b1019624b9d9dedce22ed9652cf91e00df90afb39aa2322653b5bb23f532c9a837ff2220ff3f3b1baf391e9198111ed5e7912c	1	0	\\x000000010000000000800003d557ddea9d7e7a2e12943e29b12d0f1d6d042f8b26f3c1bb9fe54ba0e7938861f8c064b3de436046c8c4e621406fc5875629f07e90d4887098ba2ecf9ce0e94834e8850ffa6e64f9d55b928a6fc9f3ff67b4266f56cf52bcafda39452c513912f1d82cc7a30a639d39676432908e30ceb00b1a179c71be5a372e16902ecdb4af010001	\\xe42dd94a61b4a7d6d830cd8d80c0b4f281c2587cb1a49e314e1224223cc7c4efbf0cdd7ffebe239ac24296b3b2eff0f526a1d5b997e3142f143b0cee4b86de0b	1659264090000000	1659868890000000	1722940890000000	1817548890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
7	\\x1b10313bedc0470f6225a1b9a5e509022d52f0a402f0aded01c6d0a45ae0bb83fc6d050143a47c7f135c97ccec6777babe97b1128aa6c8b17efbf9533bc7e73f	1	0	\\x000000010000000000800003c674b5e9d3e14ce2294e8b58f75d5031b295e87fa0818113eed37aad66c7942ec007764cc557908d19b8eb9f1462717e60191c2cdcc580da4dfdfbaa03436883c4c4238db6c8e9bb05cc2c1ed088895cd85ca9bfd305afd67390b88311998514da4d4a47d4d47755e3e69812748c25edb058f81a4991eb9fd7e246af728a5263010001	\\xb4c82117719fd7899d7f5137cc4e4f4881c120a91212afa531d5dbf5d0d55adcc2fa7cf45c1f5bf7f3b448a567813fb7062ff1bbd1a497767d20f0d23f7da402	1655637090000000	1656241890000000	1719313890000000	1813921890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
8	\\x1ffc56749091fbd17454bd84f6b8b8fe24f4da64d115d98db6385bd73fa529967ee85369115aad5ffccbd339d2341958dcea078c4f388c4fe9bcf0e3556b6bea	1	0	\\x000000010000000000800003a0dda51731b4925eb5c283048a193739b0cb1740704fd5daaaa5ff7c2db10efd04790ee6fc5b48802e47ae1d260fa43c02d916d456b8cbf6984f21954cd46713830d2c1e5db3d657d5d787533e65677fb6de21c8b32dce45d04a3ab5eff9b57f8450a06912b61708dc42c08b8792d63802612679157afdaf66486cb2355d2a9f010001	\\x0d9d50e8bc708b9a255bda411882e11568f07220ac34ad65f3454f2750186c60d448ff85341caf6da443c4a471506d1f5fb7c38bc0fdf242f87b5b3f9f9e120d	1660473090000000	1661077890000000	1724149890000000	1818757890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
9	\\x229cbd966f34007fbf812a87035acda91edbaecde6c98c28c1234374273686efa0ba8de45d50b16d08b0b777e69ce2e32fb425fa9afa9ab0327374383c8b1ab7	1	0	\\x000000010000000000800003c84864a0002f10839f6d580e2ff6db17e9b849a79f0d3ac04b8838b540b1720fa513096dab6705b004ce6097265356a82f53f326fb597694712bc412cae3d11c89a26acdd6b0291cb673ea555d56d1b478da13a72362cdce093bdc07270ae1ef6f6de39e7b2f8bd4cda2785795881fb3fc773b16eefaecfb8b622328c93b012f010001	\\x18316b375f664fa49c04c6955c7441ba5b737a8a682d289592acafb1539281bb18929b0f7b14a79680a040f495e9aa02866afecab26749dee4a3d0f8cb0a0b02	1665309090000000	1665913890000000	1728985890000000	1823593890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
10	\\x24548916bbb568e92f65ea95c00e8ee5cbb8570170a85168e96d03001e0d1c1c26376c88f27aae94c36c30ee08f96c2a9f0738024009e989eb974366523ba6f9	1	0	\\x000000010000000000800003b1c62cf30f8d2660a94b06b5a0eaa7e53f7ef318c93d9d13787bb4ef89f1d4e8d94ef15338c13f074ac9318ce262ab8a028e9cce95e3030eab710149da5890c04178275959a40521e6ca82b97e8728078baa323e1f090762d5f19c63bebd773019736c6a00f4a8c1e4f9744a62d69c2931ce10e283dcbe2aeb9b98617cfeecd1010001	\\xfe3fb965f231bb9abf941fed9c99de82ab7592e92003871d83e446e02f16d8a279cebd9c553ce3e641be7fdf47ea13543f2402b47642cd2b1f2bbd33c3be8c01	1678003590000000	1678608390000000	1741680390000000	1836288390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
11	\\x25d459cd1b446253596ba4cb20f0f7f141ac1f358a9cffde159dd2b25cfff90761059ae2854848c2ae8e1c9dce702472f4bf417217e961669f31776cb26e28dd	1	0	\\x000000010000000000800003bad05368e4878962b9e8d6f3975b7f5606af300cebfa3b0ccc1d961d79dbd98fa292e11826fc181cc648c2c470096b4168abd8b6ab63ba28c89ee65d4e9fc65028f56ae4a40b73250606cb956d50225e58146cc12630db5823f44ebe94eac290708efc5e0569bf00ab5e0b3674e7777768e2be959e320d41a9250173e1af11f7010001	\\x761f06ad1572dadec2d9454dd05134bc1b34d09ca43f8a27bb050846daba671d8e7c1f1c3e7b30d37237e624c0e60fb8f800e772b6b5f4f6c4a4a52cd82c470a	1673167590000000	1673772390000000	1736844390000000	1831452390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
12	\\x26acb47900bc5951ff6a8287b42f9aa7d081da4e40bb2c99f91e0d6ddb279f224cbc8af3ca9ff187fc3ae8cfacf9c1f1c23e063f6b3ed537f3a0c832d077b2e6	1	0	\\x000000010000000000800003955037736741b22c3afcf1ec2ef2305c86a0a051b742a3f7fa1811ef8b7c8b94006d1ba225df8d435244a392f7e6322da15dbcd4f126b3df551fe4a007488a3a827bfb382e987da37e954306cb4ab7107959bc3cb20f7244b61031d936571c504e39541b9b4e866ea27f22190ed25f0594a872ffe91151d4cd76d9882fe949c3010001	\\x5613f3341c7ee1c103d7d6c108c6d3dfd83a77750dfc1eb9343ad715349e5424dc813bd807b02c821092819e353c829d5df295b13baa7def5083aa644d92b108	1672563090000000	1673167890000000	1736239890000000	1830847890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
13	\\x265c8b293b1aa73b935fda2e6aa3138599954a19a9f50c0f899b77b80e46b9d2ecf673f1d52986cafb05d0e14b4a31f7b6427db8e84105271cd85520132612e8	1	0	\\x000000010000000000800003ccbc3d4a5f8752db925de3459adddb1e2d5ba6ec63808fadf43f9844c5f2c7961c365bc3f0ae3e7bda536564f8300686a96cc2d67b90b40e5598cd6f2358d12b251de3b3df017cb4370203149f03b1cf6600e7f153dac41ea7a05ae01adeaed43e6925368e21dbe943f7772f08da8a9af417d2027d52569d78da86b472ca4e8b010001	\\x3b21f5f55c2698fe2abf8d06720ec2875b3356f94f1eaae3f0e8d1201be0c2fa1c95abb96e615e14c8e6f635a3c46967ed3583155a4d5d8f59704ac0a983ae08	1671958590000000	1672563390000000	1735635390000000	1830243390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
14	\\x27f8efbef48f19a607d60be2d9e43e05aa408b28609ca79610892efadb53f80aef01e65d38c5ca066f29dfeb37a44e3bc3e91e41b0332ecf68dfbdeb06942659	1	0	\\x000000010000000000800003de128059cc9ac6a9bf0f06fe3ea36e49df31200173b899e90a131b73ba9f4241d5551a252ea837f322b56a03df07b7ef5796317dfaf372c2705b996416914ae9cd7f880011aa35e5de873e4e720b8ada3b03b857b02c18bbeb538e2de83fbb3f276d76c9c09e9902f2839ce083af0ca4755232ab67f33febfa516a3a17f6a501010001	\\x44f0522b63d99e6891a72a555125b3d5aa94c301b57d723d3d54017af8fdedb92f3d69c4d39f63ea05f9e94d8f50aa3d9a1c7911d5f4ee1c0ea6d57b0691e20f	1655637090000000	1656241890000000	1719313890000000	1813921890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
15	\\x32a4acba0ca7d64fab7e4a1c6c826192c4c421ed009c37a5cca05869958e9697fe4869a408ae98d6ac70cb1e8c672b3daa0831462a45725d0b35ff4fcbe6316b	1	0	\\x000000010000000000800003bdb9a8941e5367adf90fc3dcf21d714f5ca20cc2e21740ac44c2925ed01b8ce5a72735896707f68469abf55fbf1406a84b4a26e47ddb045efe8ba329a451f2da2340492679d737f60ce3b14d13ed65eccdd6e989ea0b1f3215205f0fec541506d647aae2a9aaea52408f0a30de63a9b21fee4eaf147c94828fcffc8796e726df010001	\\x01eeab4ea0486486d2b78991307771bfb5b3c24f8713151db88403c0d2b81d5ba10b774f2ec48f96fa76d1ea1b00e96633d47a7154c5590766f35e82f5abab05	1668331590000000	1668936390000000	1732008390000000	1826616390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
16	\\x33f47c113636f7d70180d40dd5d65f8ee6f60d545d4c00809a282486bd03e3bbc50cd875fc6f987dce83f03911a4662d5e2be626e9e85dbb92a209e4cffc0668	1	0	\\x000000010000000000800003edebcdfbb9262769fdde72f8643859cf53326870384cae2a289bb3650c1b862b301ce997fc8314fdc03168908ffea8d78ef8d50477e9278030b26f543b36ed3e34e1ee2646fac1758db360828951cce655f0cc4c5b29efa7fc74e4ff9a3b47ef270bdf97d59dc0817f5a8263155e8456afc42afc12260dc9b5f851e68cc87f13010001	\\xe1e0bd6d1dbb5954a3f0ab9ce30f73b621d003ff5e31f1760157b611892dc9fe8f0497c778847ebfe2b5df8c98cfca9a13ad7715729d1d12cb81362c38123309	1661077590000000	1661682390000000	1724754390000000	1819362390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
17	\\x38f82bcfd892e8dfe1f61cae0c626a47b91baf8bb14bb3a7147ef7a635d7f924dcdb66bbbc112e52f9bc4a12f6e2905ad2b712fc154945e92502e905712d6295	1	0	\\x000000010000000000800003f34cd6787f1911f75b1ac62c08ce6062d3d1f0e3ff6906703ec746fa24837e12b26973e5b77c428ab09e2b9db28fffeea3a0af5573c4facbab5319816671d3162ba0f833cf1104840155a96f224210db0adccb482e3b4066a31f96b1d7e56016289853e519d2308c6147669ab4c96c30d96551cf5177e646d4435d47a6263f09010001	\\xa96cace1d6f4c569e9a54d3d872991ff8a6c222e0b4bbb8b2b45c343e4148c8985ae96dd6cf77ce5597864bfc4bcc4b81d01ae5295794767dc059102b7b27a05	1665309090000000	1665913890000000	1728985890000000	1823593890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
18	\\x3c70647d10f3bb98b030e9494ab0f32f5cb50c273c19fc5f49fed4503328529507548e14a70463757700d9d3227d7ca1d410e499eadc4a2b7bd5d65b0b7d5bac	1	0	\\x000000010000000000800003cbaed8001d441d115672a87f01f4ae06459d8862d67c6f76ae5fb2a5b08684075ccb524d2a0a6748dcaa6745fd7376e9019d9930819592605a79c5e5c646f589a27f7f1441ebb281d752d6ccd6f5ba0357d8dc0b446361509675ec3f08f3d275f6ffb8a3bd0f0800c77195646fcb49ede8bf869e686135cb66bbe8c7efecf429010001	\\x22564d615ebe2c637448bdb1f731969f5e2bc876cb4412dbdff2bfcaaea254afe68438303e377ee38e37e4b4ec0385d20b3651a1d4b46e97a93c375ed7976b01	1661682090000000	1662286890000000	1725358890000000	1819966890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
19	\\x4584326c063b1216ff62fd0f2cf66786b4e233e4e7ccda2da1c383b5d12c04ba266b49c1966aeac790a44967c92b97efa8050271058f5ed89a9802bc39f5128d	1	0	\\x000000010000000000800003efa08f36908133475c2c6569ac6acdae7f17fa2a3399f0d6da00d25f3764acd98c131235b798e4aafbe9b6da3c800202bc22090d1d308a1031ed5a225b573a94652d2b29c9de90dfca337233f7c612b5e341362d0f82910d52c39e474445b93a0aa83c39016709801d47784c7043b81b89d14d4241cb868726fa3f3fdbebbd41010001	\\x9471448f51a35bcfa03e454e194b1fe925f55ec670bde818dc701d5922119b7baeb260a7a0a73f9c4b01f99aea423f933e799c552b48aa63e5f8ee1adb209403	1648987590000000	1649592390000000	1712664390000000	1807272390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
20	\\x45f4a5b3175d048aa5369e330388a00b3eb8f17ad3fe41b0f060047f8ebeec8b4c26ab56f58ecfb733a1b06edee35aff4b470cc3f6651062370ef91f76127b28	1	0	\\x000000010000000000800003f2b6089f8c49a953d23bd966a70404705e7c0f2ac55ddb3bea998e554ad33f4a1e385d58f6003c3358923643486eec08795c21c1e6eac887101dd44e67c493c20534b88cdc974e4b0cd39758038aed464b53325e6873276b966fd75ecb91a940bd4cc1e44a60d4b262683d915137b685a75159ba5f88ad952b1060dfa12662a5010001	\\x3758a5f4e6736930f7884479675af4c7366d80194b475a199d7dfb2651a959058179652c1f318aba4a75547362092c4d9b6a9e17abc6c4a82f700d9f0f1e7b0a	1664100090000000	1664704890000000	1727776890000000	1822384890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
21	\\x46b466d2127dceda9fa269f685629afbde809e044f0c0e3eda7d006804604fd69243a69a53792e21e029ebbffd4cc6838e946aa0f2d82d5e09df0f66e8956c62	1	0	\\x000000010000000000800003adc6817959a40fcbb9b51719e3b2c6174aa2f970455c3ade7bc0a0519e452de9955337dc02c4827c95e94fce3542716dba7fa0cedc6d01f4a0e179c60ea471c5978f5d3213c2a7ca2eb047ee637ee9fe659f11fe158a9dc02111b1365d35df9443a18c7146fa2adc97afc4c56b0c18c108d847eb2b545986ca8c071d4cc6e33f010001	\\x3cc2ab2a20d24b92e4066bb1c839250e70e3e891eb5150f5c1d8cb4752c1fb7640599c518ae067d26474ab08479c11e6e494e4c0972fe65a8cc252bfeaa13205	1649592090000000	1650196890000000	1713268890000000	1807876890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
22	\\x48f46e31268ebdfdfadadeb411942cd395b753800fb146a03ae64cf2d60872461b10cbcb6b5f288d0640c8c85b88294ddb0285efbd5c90e979da3a86d7a367c8	1	0	\\x000000010000000000800003ce0dcc6f2ca7496eaf3df3d2ddccdfa999dd1a31f58dcae5fbda06d9f3112385b1262a3b7c35412d14d904257076cad6e4e70205b57e1b5011f51c82563a8be8ee82a633901fbf77885f491146fa2230de320cef7a094d9014a35867b4f218f0f098d23acfee56966c4667944160d6753752bb4ef3d90b5c8e2ceed63b5bec69010001	\\x32c072ff566e6c979b7ca9f7d2e6563c1f765e9950ccbf145e4edef3acc9f1503cbf5bc15e70b13a54b10274302c198f42d7249e7e423ac32939f978c47bc601	1679212590000000	1679817390000000	1742889390000000	1837497390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
23	\\x57f4c11434fb7bc0efd2bb28cafe60648316245d3f83d1a67161bfb6ae1216e19f00a21570684de180263949271b6fb5fecb80d02debf499636a62d2df32d0f3	1	0	\\x000000010000000000800003d3dbf0d362a2691963164ab73d41999936754f2c4d8dc86d22890254884ed9bee4389df3a84daa7c1526e29edfa72c4dc1b001591ffc36878c693622e02c5c61489f7ae6d379d00375a727577cac86e1dfd4a5027536fff69070b53d3e99bf14bbda1133fa2659bb0a6a2d4454273c8fe3b259ff3dc037e2a4278664c2cbbd77010001	\\xaef7c349ac19b90426af2018bbd14b94dab10385a4f5204370cba248b7dbf884a57ce593a4770aa006a4a9486d37960db8e88f3c99dacb79cd06bc555de4f006	1679212590000000	1679817390000000	1742889390000000	1837497390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
24	\\x5abcd515862b05c714a018d4d847fa8f9b3f0d1fb901df7c2a34d02a8d2915ed4d06def8dfb6b4fa2278d143a3db4360dd47654e37578646a1a192ed217306fd	1	0	\\x000000010000000000800003f391da80a1e79bd87379fa49861ecb43b7ff06e105a0a694e87c224727b9d5fd4218cdbc0d6223939e95fd99fd698240b9296ae42bdd17989d99bdd12d35994f65aef213a09c6dc8bf5c6c8a1ad20bc21d6c386d0f830356b8dacbe5765ebf5aca3b13c0fd076277b06bffe29b449e5ae84ab337e438dbd7e471e166010d4ec1010001	\\xe7644213fb98ce1949f02e520484b360e5fc7860f99ed36c9942d404414ce87a736314614eb9def53beda15afba6d17eb4799a4937d073470be8d60358fc2d0d	1665913590000000	1666518390000000	1729590390000000	1824198390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
25	\\x5b509670e561e7d11468e5654c4cca674cb1d713423e5ee9bc90113eb1219365f6e84fc796285c687b63401442387a2a8f368fdea547c90f5d4e9ceda8c87933	1	0	\\x000000010000000000800003c87edda4c6177d316823c501238628ee90cfb45e4a7f4bc7d199f406cbc613c0d43fe1db9cf1d54dd57d9a5d3b805c9c1998453e48008e2a9e8717ef27831a08ad533e5530d4c075ca24a1f1b64ada42652e9bd3bf1e55cc1cde5496e37b5ed9909e092be4d93abba9746f47ab743ab4fc9444135bc15ab2790cc03b6677384d010001	\\x16603e91bb24f9e5a5e5c7e4d36ccaa3cd84154d7ef0d99e3447fadb09bcff7d43595066987bdbf81c4d4d2f447b415a603f10fb7070c56c6cb2d0cd3f6bd302	1673167590000000	1673772390000000	1736844390000000	1831452390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
26	\\x5cfcdb9f0275ab056fc568ef58d0fdc5b0e70bfcc7ab62ce768b9c2835c78ea2acf7731d6b4cf1e860dc197bf5b68928802a59212698446468a674050f3f73d6	1	0	\\x000000010000000000800003eac0ac1b32a41fbb0eb291390489503b5258673c9345cc69ad6b1e962b371eff2995da4db03970382d076202463214eb1867f249c509bccb9cc70d62c4dfb37cc07d14978b2cae46ae9b8fa7871fe31f9c90df0fc97c7fdf930467298a9ebc73cc87b75f437160cee13d5b573d02e4a17d808c8e162b5f8a4cf31090f609f415010001	\\x513e3faf3b136727415251c1ef3bb4062c0736bf16f23d7fd39e14d0e91e329a7c1e8dfc7e01e4f0e0a67ec9d352ef53e5f4117375035dc89750ac4cdbe1c303	1660473090000000	1661077890000000	1724149890000000	1818757890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
27	\\x5c7c5fdf557c432ffb37345fa272fb7c8fa82efbbd1f0751b0aa38b2ca9a0ad092ba2793a6a74c27e66d5038e904fdf3cf51cde43e269c1e404b04081b0bc7eb	1	0	\\x000000010000000000800003ab481d970f2c6407d2b8d22ddfab4c350beec600bd33f1933b5ec42138570300997004c5bd7556fbcf2ade566852b543a6dd79f696537c89d99123f64a70241e72fbc9b33a849f51fbbd0ef37baafe8b5ff1395f79e7d660190379df8fd28021e1fd69a8cafbc0386df489c5bf43ad3d710692bd1f18c337b5b18805ed76b4b7010001	\\xedee40fcbd5eae364ed2d48d878ee8d6e01ac81cddc8d487c26887c23cbce2716a990ca35c3de582316632d77670f3f45c26792b856afdf7475f6cdacf82e50c	1653219090000000	1653823890000000	1716895890000000	1811503890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
28	\\x6134597dbcf435e4ec299cb357b0ac2b40049191b5874f86265a4ec11d5aebec45294a606233d96591cfe095a8568d3f7e25a45d0ca2a8c4db81e92bd6ddfaea	1	0	\\x000000010000000000800003c2b02cdbd5e1644247faaf6be16fd2e5390432dd1e14591a9326ac93fa054ce3351631cb9179f8a506f3b41d74b4db2b8b4201fea2a95fa992443b091b0357668392d461bd853c396745e40d2e1761b10a75ea362c1a4c4a8f517b02e2861d57698f11d2d3f80053fc4570216958d7a70d046d1e52f426eaec854c744a74f2ad010001	\\x24dcdc4f821ddac95aeb17fd09f0dfa5074d4404d73907e7c2ca4f23a6f506a3282b49cf6167bbe7f2a54106dead3fabd5a8fde05218319d6df4e76352572d02	1675585590000000	1676190390000000	1739262390000000	1833870390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
29	\\x63fce8467d11ad95f98723b68240b13ef0e63251eb0225dbb22c65ef3ba995c9342810651916ae26b8fa3eb5ce7be4ddd1569474f8e0b10a02f54cdea6597fbb	1	0	\\x0000000100000000008000039efab26b53930e87ca3487202dbe58baf90763cd596ca1572e725f50c7cf1473b864ba571c1170247191fc0e794d40e808107a027a74b4eae62c6c7fc877b760a2d74070947acdeb5bc173c0992685a0039362e83d4974c2eb4fd87c521ea3a78ab7af3a5bdbb353112144d46b2d579155b64d9c597d2e11922868471cf05f89010001	\\x49afec0d7507e75d9405eefa2fe0f472acc8e51d1c0a91c14b740a045d1c41415e0b059d12bda0573f65b865200feabd60b5629282844f2e42f00bfaca15920f	1676190090000000	1676794890000000	1739866890000000	1834474890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
30	\\x6310c56eaa7fd4d5664f72c0c9e8e412dd50065329e19ed7474c4938e62def36264d8d7dcf12aa988c5a01aa4100e94c8519dfa1773be6f8a7f0851f659aa325	1	0	\\x000000010000000000800003d4f3b49f8015d8388d298cbc00827f060cbe64a009508dfd894323d196504a2814ebca58ea08f5122b55c4f1a8209a706851a5c5f139c6bc5f8c275e2be1c7d0911691bfaeaa325e89e19a9fc29363f2edc46e848774354ae0c79f92b2c45cc7d04452da589289194a19bb07c48e4333f610fbc5c40164bf1a43a43bba7cfe0b010001	\\x2f71fe935d59d7ac5d08056d94305f91a8e07da671639162b69e47adc0976f4812e3f51b5123c4cdfd15a80eb62a9c722ad2aa3c43b5ed5af523530e45eb2d0b	1664704590000000	1665309390000000	1728381390000000	1822989390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
31	\\x66700349ab7132a1136a2e3d0806d95a7c48586291d11159b9cfc5ca0616e27a24ad7993a320cfca506d8b29d66204d2909ec82786ec64ea3b50550e70a2f023	1	0	\\x000000010000000000800003d19e4008cc3c4ee5b1a2c2b98b7a77e02ea9e5390693d92f6a610721bc607144bef33a9a58b808c2d878ccd84ef5da5ab258b62b212448e77e297b2e840a6946060536df74ef6bebedad610c7b30339355a98286fafe9dcfacc9090d564730f94b488fc17431a9c9c07016603116c66030e098f39c09e16057b4decc82627fc3010001	\\x56628ce0a96cb994126c25a0cf4503af2a3fd0209a25e111d05a7130998c25619fbd8c23b95253d46ee1e8ec83d6c3bdf2991eef1d727dccde312e76e81d9700	1674376590000000	1674981390000000	1738053390000000	1832661390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
32	\\x66d42aa3a359f22b91d8789f380b9f62b9895f035b065e0a03adf116c3684776ec8c8f92a52ccff1acf0b1a1b3769b41df7294876c01e1a5be337b036604af40	1	0	\\x000000010000000000800003ca2307783ebfdbeaf2faa68d0fd93b14c5f532ffc7603e9b7bc194c09fa5180308a595310570c049a84c148882332c176fe43c5da892717168ccd063367d8f0650993de2e3fc26f4892cc5ba0b5aab0cf5b6cc95d429e2c0aca79cf715d74a1a5931dd12d2334bd13b9ba833360a2582019a9e6dc9b6600945fd19530c098a9d010001	\\x72be7ae5565700ac535417d0a6fe83e265b6b7de1f39162c4fee678e98c07aa8615ba5c62e0c0328c8f12bc9394c6b9afa448690c4ea9d95ca553c0c0dee2404	1670749590000000	1671354390000000	1734426390000000	1829034390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
33	\\x6eec8545db6d69dce990214d314a44c649efde0b4ea18b0bebbd9152fcacd93c6597511c9d78d0bea976c9ff8ac32fdd18f4ff09843811eb110dec34aa9954a3	1	0	\\x000000010000000000800003e8502b1d46a2d968e199f6dd4ea5edd09cda2cac3ce6aa112c864b865221178904307694add6814e4353be0b5ca3a2c238a8887ab535a0e05137820ba42db4027c400001af45203c90d70eab34d5946b020814a2f5f403090bf5398674f75b34dd7609a56304f99c5001c058457f61efde2be7488f4961b178057250079cc80d010001	\\xdeed83ff26cd7d091ff16bb9cc97ef8beda73fa103b2d157d60291ef9d06945be0444dadeb73d001defb4f6e6c845a47965da6ae55e55d72d0f3e912935f3e05	1679817090000000	1680421890000000	1743493890000000	1838101890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
34	\\x71b0db7fd0a6101248271a2413d312f15f616c963c5c7edc29ddf9209483b9318e82399fa164db517042815b934e0968a177f1e93b49542f371b5ee1edc641cb	1	0	\\x0000000100000000008000039f623721d9fe585a574e51ad1464af0ba964d999caea70f483458386d5dfc31d796664479222c37dd7c1e4af4337df02658f127366a089ddbcc2a69dfc8be56938b2697b20557c18fac1b5f1bffcdc4670c00d77b6ffec9b1c7f8a43b82d04901ec851d680544af20a3570f6129798c424bea935556fae88232c62cd75a56cb5010001	\\xb3fd448dd8c195a957debc2e9f99a9fd2ce3ed6a5a60bb2f795c50697f2c8dc05b465cc2a9451c7387e76d7d14df0a78129300235ad8339929e851c9190b1609	1650801090000000	1651405890000000	1714477890000000	1809085890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
35	\\x786802a2619d77374e971ac5125d5885d812a01d7cf2ab0c2b31eec220a93c2519e13f48a7c9256eaa0feca9f2306e69181cf80f97402d317e1650cd6a7095be	1	0	\\x00000001000000000080000397cad5213190a1be4323a25546de4c0f01dc06ca93eb2e944761737ba12d354dffc95735aebc939e449be2ec1dc4fdfe2c136876edae37c0546725955a9f2236d6d7bdcd491b09b1d013c29547b0b8b547066678a5f2c650a17e766482c909d73eafb5e15b27b97fc227b02384ac174cc4a3fbc2e79b0cdae72960d28f718369010001	\\x00be3688b495bf92a5bbd05aad78af0f36919ee7509dad266b141d9e8c9051b819c9d3b23668dc157bf6a92ca0d0f87f4853a9d2b6c8a070598d65da584b4c0e	1673772090000000	1674376890000000	1737448890000000	1832056890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
36	\\x8060ac6364e09c8c46d6c6adcdab59854a58933014a0ed91bd00d1869e7b23f5a42a8b617425ed4564b01cbcb7d1340036966ba425c4a8320b7cbf96284f6abe	1	0	\\x000000010000000000800003c7f444504f5169ad4327496a359c8ba1fc05962a299dbad6df44e30cb9e185526ffa91c42dfb2eaecf70b61697b7f4b9cf7704e8a1561dd8c7089dbb182b37f080992e8edc35c850859c56a5eab57437ab8ecc2ebd7856ff9d98c1b96cb49b31437453888654d42056cca16670aa9349b04cc9fc6797732f35d67fe0bfb68c5f010001	\\xaea13a9c759cc1a7f406a6ceef0b4ac5f8e35c15bbb4779b8b615342b69a6b2306923a2021f357722a3cb8f44228d4649d06be82ffae80f4bbe523d80956b200	1652010090000000	1652614890000000	1715686890000000	1810294890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
37	\\x81b00d34b5617b32587b1e33b4d5f3cbc3f5203046a31a9d22bd1d3a325835a1bd6325ef1edcefa8a2c4fb42b58d72024020e7d46089df7a16b24436a4a019cc	1	0	\\x000000010000000000800003d26a09468f514f88e35db673b02c3622532a1b74ed9a8379db4cc408713ae919f68491569986abf448ba438385f0a241982357afd579a260855986175648af036cfa1cf34a7f6c01071333eb8069cd97c04733275ffa1e8d28db3a7ed436a3226501cb91738adea92abae683aad4113ded42c840b3d7b1ac5cf2a33670cb9d65010001	\\xf998a51e8ec48cb478977423f11960b121aadd5e176ed950d4d2bd4d1a86ee3b9acf6e37c2ab5e2c5ec95b2ff92517d7a3370a3fdeddd95a354d0359d1ce2d01	1668331590000000	1668936390000000	1732008390000000	1826616390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
38	\\x8434a95927b39320a933e40a965b14c9eeb6b1e48636443cca46a6a418c5a9258e66b48546fb48d37e63bd21fccf8d944d0dd96ceecfd0cde4c8f1c53ced56ca	1	0	\\x000000010000000000800003c8f479ebad39204cb41d9da69eff2c3c459ce2935b1153ac099db6238936407760fc0499c490cd870c32a94c94c9915f9e256d7c56e9d18db8eee406b30ee71516f9b0d5499075e2dbdde4622da10b19e539ac8e2954b0fe81e5dbdc898ffbfdae8e426c5f5c16d32d1cf1a47a566942985575cb2fa265c78ecacb3cc10308b5010001	\\x0d6feb94aeec5d516285859c61cfd21b4d9a2a674ac44382f83d46fd084de4e94cd37949b40deea162660938de1979d0c157a13316c947bf0cbbf91e6bab620c	1679817090000000	1680421890000000	1743493890000000	1838101890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
39	\\x85a8467684a73fcbe720018f3d1289f629fb6f4b4c3c2065ab48495c4d868bdff9e008b2c80d7cfe32ceace6f549316fae3343297160a4cd7ff50516457d3bca	1	0	\\x000000010000000000800003ccb9bf2f6b778bc09c3440ff34cba76bcbd9b4225854114b87c365a793c694b97982b51260f5f1d19c155420b8933bd52e73a436f80bd16848ac5b76d838353c5e3af42ce3cdc1978884a77498407a435006af41606f6a12a866a70d72d50e910d4394eb5930e24d291ac34e4dc9abbce7a4d82eecb17534d5ce398bae2c0787010001	\\xbdc891e935b0ea439ff71bd9c70e51479f2c0ac281b3f504ec67c0650b20498dcfbf6fd765edc5bff027353dfee7ea6da4ffe8cf96846c6cb6f3fc3bd1c92e0c	1673772090000000	1674376890000000	1737448890000000	1832056890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
40	\\x8690653f68b0a2fec54f1fe14ab720eed1595ae87f56fcb4315109758b442aac965ddfc4eb97761367c5eb3a80f3d265da2043ab5006bd1e4058e7a5aced700d	1	0	\\x000000010000000000800003c6d769866d103013c01059ba489f09bc21cc656a37f7b629cecbf003524465ec6415f022c7c81d9ee23cc976a0378a1c8e7d8d5ec55f459314ef34c22fd705bc0fa1dfcf1d02fa4851a3117244862ac8494c644313218b9ead918b74e533b50cf01e6461258f6b2a22f6a06157033ec0c1e5b1fdbe8d95a38b0074afdbf50045010001	\\xda67fd4b8a87693c442b0a0b99931fae68ac353174d685143ba135ed811fc7c27ec61e3a4ef370d81a49195dee9f2348be1394c14b1f5cc759b4774096166506	1670145090000000	1670749890000000	1733821890000000	1828429890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
41	\\x875413a31405972284795aa0bcbbe340ec708372c673c6a99d2b5effe0d963f9da120f07376cdfc00bc5b360bf4354a493a060e00478beb5797fa73d7902d69f	1	0	\\x000000010000000000800003c346d1e4bcbfe7fe9c1079779df473811aadf0a50c1956efd52f85874a44b09cbc46366e29de9ead1f2c0c3b00f885edc4e6fef991934bb9146e18982208df8ba72cf9e2f9fbd7604928878932b5b660e823caa1a60b0169877a7013295b320ff76a61f3cc72c8af32c2bab913b025ddbc8d246b9b6877fadd2a1d6cbfd650c7010001	\\x4705baa38dcd82de558c04b7678e79e95c482ab22cb445655ff40753f9422c3eb8b967290a45e3e7d62d6aa82b0367e3b050c2bf9ce48e1d7e8b0b741707420c	1669540590000000	1670145390000000	1733217390000000	1827825390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
42	\\x8d38b025e5fd5be5b7130c66fbeaa734d8d11ee305214e9f635aa3a576fd84c5f42722b6468b31a96c3662e94a43880987587320dea65a29d42966c8f2bc82ae	1	0	\\x000000010000000000800003d69cc76a1a7e579570809fd62048e3e786ac13c72cdb9887a689333488e2da0046d733c10275619bdb856a01b3c897d48eb646fb5d516ce25c147d880122c4ac8dc1ef4573024aa3ec59d69104791a6544736ed876bfffe37f4cf01ab223f59cf62ad8ec18332703cabde693a6338f337643dddc15e8cccd131b48dc5b2e0273010001	\\xa57e5f6a87ce56e3b56dad870eb832aa4a9ebe9ce2d2388d24b8ae612be89512cc39c499102e10b9cdd9b1a13498ff59a032e54701851637c1a0d4d9b14d6002	1671354090000000	1671958890000000	1735030890000000	1829638890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
43	\\x8d08536e93931c8f6fa4c796937081ffaedebb8511aaadd502ee42057c58b7cbdba5f2e2eeebe9ec86f49ac7431890c94bfca296333f2dd54e2fc1afff185fcf	1	0	\\x000000010000000000800003fdb2a4faefb8f0c9e6cb83a7ff1ad5e2d10ba405730b44a8b62e44bc4dcb178b7789d83e4e6e9d8f150d8b8b80b5ef9a92b32765101516c2c1cafced87507427a83a8136b6d21f2742e8b14d1f3deb6ed4c8cbdeb796faed0acad40cb90db579e95c23bdf6b99ed2f17e74bebffa9b72abbb04c972ec464fa41bd98d1bfbbfc1010001	\\x3cbd897aa3a77affcf92addd979934387fc3e56a0a4bd74695afc5414733493a84fd9ab5bd0c86af6e662578710c3eec7ae1ba097019bd971aa17c9696a8fb0e	1659868590000000	1660473390000000	1723545390000000	1818153390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
44	\\x9350011e6107baaf48cfd738c0e25890430b9627138a8370b04ea6eeff24c852aaeb41a4b51185b3e47787cd35216bca0727456c3bdc47e0b8a796385f5f746c	1	0	\\x000000010000000000800003b6cec635d52275334841971e444d74a00195bd05d9ab0f2d2fdbde9dc4456aa4e2e82ca76a3ec6c6164f2d77d9ca6ec7e882f4ca883807698907bd7c6a6f867c318ca47eae23e9be0e1e35c1d0ee316255eb6ad93946ab7574a6316683d04b3403c530a63ca0bea4b70becfc8b90f91788c84f39cc3aa65bf28b1ad145e9a19d010001	\\x152bfeb96fa11b07f8624165106ca4fc50387bba2c3c53fce5a18d6f0f4601b33f8f7f8e4bae4acf214479aac57b52e06444137b995c3194ffd394aa5ac9c305	1678608090000000	1679212890000000	1742284890000000	1836892890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
45	\\x949cc089dad33d0a5549cf8bc6b0e12fc5002b64c602b941bc15cb4275ba52529879610e64a42d43ad1fe83ed6a16531af5ef97aab32239b7773c840b1cd9be5	1	0	\\x000000010000000000800003a346633224ace8764f3ac3357a32c062b4c538d4fdf42c09d87d8f7d68b785931124529e07ebf81effbaab4949a136b2578f9ada45f7b5111e09535f106d858a7d00711b7270aaa3c349a07fcc47ae463cbd3a4f8a139148b502eb422fbf7d49e85abf1afd4794725f15ed7575a80ed692519acba869f88f1cd292b413053f61010001	\\xb87f4721c2b319f7c30927d152fd2b31c18dacaedce0986f14b82b96db4ac026585dd5bbc9256ff601bc3836e358eb6597415ab3e5603c5225e6fc9097d1540a	1653823590000000	1654428390000000	1717500390000000	1812108390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
46	\\x950c2c6bb4dd95e5c03c415bb7c46b989dcd1d91bf16dd35f691715b9e63c6b69f371b31fa4665d10162e4c0d5e966e9ec7102f854dd529fcb4ae7b46520b720	1	0	\\x000000010000000000800003cab502b076057ed37e4dce4712e2012e6f152ca7a5138e485441530e749f21a431d73ad2ede162e4df69a4f6788d6120ce059d2171df951315903846222d777973ec9d56f12323d2e5fc2a0e4fdf35f16eb42258621b995d5c1833a795dbf31c50eb116198b5cc748a79e331dfdd9fa445dbf17f703ca93fe343fe3e1a2eaa25010001	\\x2e9b1d50113eb3f021b4cca4f076b7a9be8441d1ec716ad70002eda5511b710a4c2ea50dfc443f02e5ad6d053841e304277a41273675cdd2402220d37fd20705	1672563090000000	1673167890000000	1736239890000000	1830847890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
47	\\x980c3c2d46d799317fca4ec2c4d1beba080ef99226d4ba4baf0c8f04edd572e4f4ad7e13bae2940b4250737ea866b9be19ddfe8b979356f9f5e4de3278a69a38	1	0	\\x000000010000000000800003d690f1119f67d0efd4d08036fc71a77d7fe5e93f27ac15bdd6c5c502b6fa5c7e910616117d91e26163d9c4bfa4829b077ec14d0b267746685c06954cca34e0615654b3acb012137b50d17e7a40e35889aaa81338c1f2493027cdecb197b47b83f059ca9ef881df18400dace8f2da81cc2bee5e7d68ca551e44094a8b9192a03b010001	\\x7ee0d202da20321438154eecb60afe97c8fd3cf878ddd49266d18ceaf070fc0c52cae313f87c745243105554a9b2eb73dc67054af80631b3d1b81e12aa70fb04	1666518090000000	1667122890000000	1730194890000000	1824802890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
48	\\x9d102b1f5affdde2e037bcf2c66fd3c376edd79c3b7071b590c44538b3f801ab2483fe0c73b008fb8a5bed8e6cc32953e6f4db11a296c5f2b03c85f2ce99919a	1	0	\\x000000010000000000800003c84ca854dfcd031f5819ecb5dee73874ec6bc3b9b79a66be788be69994dacee9260311adf4d33d198589b6397131b26d717196a56531ec2ac2bcff97847e148282ffbeb1a6c5515f19180a5f54eef87764f6aacf49028d8c32f353a92297e31ca40afb33429191dd29f00064d0e9d2d26de69d8ae5e144b8affd4cfbf1a21a2f010001	\\xe82d9fa2220406a94a003d24617d36e371e0212f7743bedf2951128942870225b8afe7569628cd6a578b3473fe3220aabc6ce8f85fa64521d6b66b5e863d3a02	1662891090000000	1663495890000000	1726567890000000	1821175890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
49	\\xa5bc448ec4ff1e6001becb515b9676eef792a5b5052666329094a8f77908a445358dc2fafe5981630b02a65a6ee1255e5d921ac3f90ddb083d12dacb787d7b9f	1	0	\\x000000010000000000800003bb5adef78cb61171777bf4829f706c1ae6b0d0e5781f43ae4f7af5c338571f45f20de8c503f6ff37144a835d60ee18f39e20fa8f6e44838e735cc0e819852cbe0cc63982d7a3dca260447fb1cc549461cfdfbb441fd81e3fba10863249e6b0798f197b21e42d326067d8dbf2b99468545661f85acd0704fda2800c8ae08c674d010001	\\x942e06c250816f1832d3268168a59055dfa741c7f7ef5f6d8d9fe176b12beb098d9c435f181442cb64a274383723903031a8f60209d943087ceea9ce7de1e30f	1678608090000000	1679212890000000	1742284890000000	1836892890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
50	\\xa70cbe73ef217e7d1d2ecdc2eba4e895c624ebed9cd072716f0b11bb1790a0c27e39c868c3bcaebab04471b72fbe883f118eebb538a914c65dd7bc7f5b0c3084	1	0	\\x000000010000000000800003beed85ee56aa4e51829d89bc951785091f08c22335fcb3093375c81a33d78e673e096171faf9509cd3cee390a0840aecba34b7f939ac5d5dad901ba5b274dd13b86044b0b18a9e677520073c46a8b212bf6bc77e9a7298d3441b553bb4af3bb2875fd02cebe14255e368f10e52dd086d71f836b3b4cefa417a8f1298b120212d010001	\\x6e68dbc212897b1f9954d85c8dd3e356a3cf4ed7dc61bd9201fc7b31cd6ea13896c168f2e488d78fc7a5d32ed0bfdbd2d5327333d04e2eb114e6e90f201fc10f	1667122590000000	1667727390000000	1730799390000000	1825407390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
51	\\xaac02ff2ac96f8d26cf5220e4b95695150574129796322070d3bea2e6e04cd7711ba13bdab1d948e073596a5868110df4442f3a38303c3f231f69aeb03d230c7	1	0	\\x000000010000000000800003c8b2c16c3136594c6e8567a6d07d5d3191169d732d9644b32ca356f6a846767b8107f7eea7d9b4517fdec3460a0cd08fad0183ae9ea454cdcb69f85ba390de24a223fd9217b9e6755e0aeaced5e9eab15a70c7795bb5c58bd55e1735befb9595bfe059ea2f7ea3543e6c634fedb37eddb7b958e18e437915d82c03398da8b799010001	\\xd59003f196d7363577328e55f02f4d767dcdc5277126f320213f038ce49869fd01578a2b86f10beeced756eb312cc8554ca8d3475c656c17ae4be6c2fd46f106	1654428090000000	1655032890000000	1718104890000000	1812712890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
52	\\xac50674e9aa4c713c32a0d61ea24cdf4b8fab3942cf50173bca9f198476f6aa74961463d4c01464f4c8c070d0ea05155c575f5690647bf4d694dbe9967a51982	1	0	\\x000000010000000000800003d26cb6f7b5be0e670f6e89975f030cd31be96a4598e46abe7972b78dee425588acde798fb1a7f6157fc44f5d2e125da8b925bbd55991b112a64a2e5bc9dc44d2513de457f43bd82de054c92783116810096c6f8a880b2df58cd4f96051caedcbf9b34b7611a2df148896a63aeaaccf156880945717785340937717880092ae93010001	\\xb80ee3166234210438e4e640ddfe4111132b30297fde4037dcac42d4f8fdb5330d582272e2bb8f3932055ed2f536562e9d7bbec732ef674b8d6df24829711207	1671958590000000	1672563390000000	1735635390000000	1830243390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
53	\\xae18a407c035ab93440f91ac7b797c6293d75e2a1ffce6be237ba7616a4a2058109513719e3811bff1248cd966d042ae62687dcb0b23165c26b19697f6064cf8	1	0	\\x000000010000000000800003d241e431d4a4acd82f4364ad3a6e702ffe97ceb366dba76fbdd3f8848a2917cd54d2a88e5bcaa3856869042ba5678d4a0e18f1e2fa12325bef9a347069da42a79e39e22d8cf3596a27d1e28a863ab97012605312ab3cb538dd663aac1ebe7f9a127bb48f1c6cde96b53b54973ce212f1e2fe1549d6b38c470b769edaa1149b51010001	\\x7c27f70dc5ab55e27b1ccb0b8f254473a5433d404976f4cf96a1733586550041cc3ed777e7cfb967bd2b66ca782e55b6cadd3c728fa3353612c7fe1069760d07	1674376590000000	1674981390000000	1738053390000000	1832661390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
54	\\xb0e0d399d71ee2a345a59488bbdf740858cb4fb0c76cdc591b1cdef72341eac02790888ff031b7b02131ce2db543f3cefc888559bf66620dc55e7eafe4991f65	1	0	\\x000000010000000000800003c2d09df409e01cb718ff5a43b91fe46202b29a079570206490d3fe82ed0e84049afa3e60757d4fede1bf217f5e8d90f2a8b51a7c50836045ddab7451005180b8c1ba25a62256280450a2ca169663911682a8f13f247d8cad286629302fa26a4a8d261883120054baf09f93e4c0fafec051813df2accf46584f1287e299d118a5010001	\\x27118d8c6046d1ad7173591cd3d6b00e19c234be7c716cf3ec563fa0088cefd1833f8cd985027e5d88f4b509f600c87f848c1252a9e7369d8588f8aef629c705	1671354090000000	1671958890000000	1735030890000000	1829638890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
55	\\xb1702ad2afbb87baa3bbf87ef9fa924cfd7e336ce615bd759356bccd9f62f8714718257003e54a5f44325d71d0525d8ce962c11e959a05a1a5185c87c8e69798	1	0	\\x000000010000000000800003f88eb224bab67d64ed52a0017908e64abe4ca3bf1acb1f65c61dec53636f56778c9c4730b8d0a5c071af9f4e03d41af397f6bbd26ebc51d6d2d31cf3640dbc663c3f50ce467936c27f3f6ea0a61d47c2ecc806298ecb5b755a8c898a99c8841aaa3cab1a4c6009a867428e45ecaf42b02813e61499072fc8db124c0f2d57f32f010001	\\xbc62b2e619f8b38b4c4dea897e772360aab925bfe519e76a06ad5f0e84fca466efad19ad97e0435ce55a3f650d85978c1d1af649cff71b27be0a0dd3ffa0bb02	1656241590000000	1656846390000000	1719918390000000	1814526390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
56	\\xb5ecc7866ad295bd2bfc4e132befbb343c2a8800be7cdaf2318d2aa5d2c90df9eefa528d8a304db42d674a92dba94ab83b4d85d6690dc49d87ca01c6f6abac8f	1	0	\\x0000000100000000008000039efcf3a393882b07497e5385812ba0cf517551e56544c8c421c1a42889a01fbfcb6d9618ba2dea9304272b0fda41a1dc645b8e82f9b79c7d875f5dcba8859697211f04d62c692074120a504f6eabfa3501ca99a7bd6a1c188745a6e813184663d2f17952119412a40aa571703695708e90cd12398f9628d39c6a9387a36d8d13010001	\\x9f3c864b1eb164bbb1b6238c948f5b456e98aa79098745ae590b326e94f29c84abf34579e7f58cb36505cf5eb548fdbf45152933887901c1696c528fb792a500	1660473090000000	1661077890000000	1724149890000000	1818757890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
57	\\xb63c166b49cbaefd4587fa7dce4c45a18e7eefc39721a3c756b8ca58cde2573126d27d800954a28a7e9d821920e311acf16784d7c971da368bc91783b7793544	1	0	\\x000000010000000000800003d643b810f33358a105311502f9a199705e70ab142cb04be99c9bc7014d986d2b4c5b283b038b8e5bdeeede8413e02ef84918901a2b5de3ac2bdf7851786920c1133aecdb686325456384cc2700d98543f568e61932114865a7ebd1506b522632547462f514cc4f3a71acb9adef76ad95aa8b1e6915cd6de2dbf48c8748e38541010001	\\xea7abfaae3401ef77203bd9568aa4188ffa62279e9f2b8ffe401df74ec0bd237d30b1be4b8fb1addbfc6ffd5425ae99b1254e6c0a5268f6eec64a087a262640d	1651405590000000	1652010390000000	1715082390000000	1809690390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
58	\\xb7247f93865a40504e942e3b8f4b5a6c63b14651fd941b3d355588304820f1f7bb34060b696d089c7a25556f956660eacbe0ecd036f09c508888cdf504cecd25	1	0	\\x000000010000000000800003c4f24772fd4fff61214fe30832cd04a78bddc1feb563caaf967f20fad4af9018f66bd735b29c584b1f3c53fa25602b3b6025e6e06fad8a4105b575af6cdc87ce3454708cf913a0ab3f5098bb222fc7ad000b944369f15560949096e54894211b8a9650a4ac40cd0333a2d79d18808208122cd275d9508a8e5f71c6ff94ee7efb010001	\\x1bee0455a4effc027e9d70ee23fc608991aa40d31c9c5f188c9d8c5df7d0693e6aa0b823a7b19e7d94bcdd7ecf6736befc5a969996850d34e855857c3947500a	1678608090000000	1679212890000000	1742284890000000	1836892890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
59	\\xb74c8b7e3b7038c58ad1aa5c06e2c0104ac4a06704a85bb789fbd39a8077b63b477be301244c04563ce23f3b48eeb58b65a979d3d9e9171ab3d22c465d145bf0	1	0	\\x000000010000000000800003c8e9c85467bf4a9dddc1c107fe6a7d6a4dfd9716876c2c78447009f804d531346b2ecd6fcb89171768eabe4230800a5f7ba3d00431d740777d0bffa019daff2e3d5fb98ee38270a7a7689035b50b7b25af56064a16bb8f3edb779dea02a7b22062f365ac64bf4fdb85d7e98fada2fc0a6fab8e865fe8c4d6bfe7969f3c7924ab010001	\\xd1b13b35d8094b20d7b4c45b738d05325fa70433ee96458ab559916c5e7a2caa775fb76f25dfa8c42dc88ccb8b91c9b9b515360818413f2270cdda73357d0107	1679817090000000	1680421890000000	1743493890000000	1838101890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
60	\\xb90c2b60d705a11166ce35cd9fca7e3cfbd7f264a79f9be0f5bfbaa56d70b7d635906f8f894724e336632b57db3ed0c430f6166439eac0cb80645f9dd1536fce	1	0	\\x000000010000000000800003bec44313afee6f5a370cd477cfc0dfc3a1993032a8e1d481f757f1a77e86b3d78bc09853adf8b7551a5da41f6b2ca1eec37277e7c24f394407197a356d3b7ea5b0bd11d230c427c3993ef12d3c840d57940c28ec0d4b45bb6761499c1ae13873392512b8d47579d4d0bcfd8636bfdb7e844a246f33454775116381154cd3cfb7010001	\\x6bf9f100575dfdcc97eed0aba368d9456f404c832c21ec3ee811b98a0e490618afb844ccbad290bc9e95924e2af880391ea0c7b949e2cda9211f9e12209d750f	1656846090000000	1657450890000000	1720522890000000	1815130890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
61	\\xbb4024f70ca481fe2e66d79039f292d8ac6d5b490813a34f658204a3a8a1523407345bae468cd4d79e342ffa6a6e819da974063a9120be1eb211ac9ebd243146	1	0	\\x000000010000000000800003beae9edaeb43700a4f437be99260dd53910dcdcdf5e0a4bc053498128afc5fc61732a205a6d2c25e1084cb774e9e53323aec085586e620305fa1904fffe977b734161a2fbfbe20867bd83f073698c6c994cd3e222c35eaf131762a9776de92d4e77b5523262c857cc9cc77ae460175629b2cbfc99d1bcbbf0ea79f1a33518b05010001	\\x5b15695d752e1cdbf122f29a33ee23f52ae80d10a50bfd0ca58256596d467b582395485b88a1ee9e087bf8c6ce88f48a297790e747771a6e248392fb49cd090e	1671354090000000	1671958890000000	1735030890000000	1829638890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
62	\\xbfb88387e08a6a452c4b4e2dac00a2544d6337608d7eaa18a0bba39362b937e6cb8631a0a6af52c1a5364d608d6abdb4626a99fd81335e4d140f4fcd8d8c63d3	1	0	\\x000000010000000000800003b1912cee5f070b1034205123ff0842a531a853111753698ae6a753e5cfa48827651a40036789558c0234a64f54277bc8bf505deca79d9634a9dea2c17825ad8efcc4fee2f201ee28c1eda994b4e0ea3ae9815119db5a8b4f88e9cffdb50b0eeee76d6c25b14583c8c6e72a2079fcae85381ba6d0cc81fe12aecf928f9c6f03a3010001	\\x3a2d4db6d4a367dccd2845a7338a664b5be3d5350f130c789bee85dc3bbeb977d9408154fb28e12e4436d30d5068d5b0d482e8bd800bd900872e43aff51e4404	1655032590000000	1655637390000000	1718709390000000	1813317390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
63	\\xbf28f4f62e1488ff09fa8eca57029d3e7cbe8d4b30347c0b26a72f7f73dd206ec9146941defaf847a0f713d4b5fe201e51b55328d8e16f4fc1d3193ef735ec87	1	0	\\x000000010000000000800003c6336fb029b53a35875bbcf9ce3f5e48675998f0b50f1f2bc7d1321355ff7b950530111321facc82820e184c0ced00405875ebf8e7ac68f2a58f26e1e702171c4643182720bfd37b6253c1c3b6ba981b9113cf17b51bba2df6a02b9de5635ec5bbb6486bf0ec4c23f4721ec84a1a696a40385ad99713958f1b54ccf200894561010001	\\x0654c192feb878d567ed64d958cdc604948820b827fe6ea5488ff1c0c120084912be9237ce272bbd9ff17c174e1e19902ec13e334bf481f26ee194d2f65a460f	1659868590000000	1660473390000000	1723545390000000	1818153390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
64	\\xbf90dd97e7a476ecef06584528f42d4faf5a4350919238ff4c627672014b9204cc21e0d7437bad9662248c4f2b6c21c0c3ac772a0ca7df58191a0191f586d618	1	0	\\x000000010000000000800003baabc80d8d62e2a5895bdd0ddcaba193e1f4dbc7710cea8bf2f2047c30ae5587152d70be94d8ea37a50abe67de5ca28475b5b85014dec2b208254a48193463cde9d569124f5884315e7f47d48d959869133fe8a84fb993ee4fee19c54e9e3a681e632331b4b70d482281d173e1d032ccbd072972653fa51f29cc78ee636c0a3b010001	\\x2d500e5d9d5f902d747c83950a7295dc45b3505aa3a59e59dcc78cf4d659d07b90daac4e0ef0c5858d1d281b29d6743894dea1e68faa5f8c42d765a2d001180f	1676190090000000	1676794890000000	1739866890000000	1834474890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
65	\\xc178a12ae8b80766a2de16f4e0f2c23bd635937d7a36df49197d4f3d4f130e76cbd6f885a12b716940376f8af76e1248ed25945ac91e88fccbea1de419646c0a	1	0	\\x000000010000000000800003bdb697ae81940f2cf425e9f688da4998a45b2dbcc90935c7bdb9aebf8ba04e4b62651305ba26d0d2e11cf90b90351f267a203e4a4b1f10794c1f0a741249b18f55124784f3a42bbed76d6e638b785064a274b33f48567493ebfc8c732265fe258674b6f7180a947a38fa91cf83443ccc473953dbed01ca4fe819e0cf1e91aa65010001	\\x2c0e11fb5e66fa4187ae3b1e57b787d7607da8b0a93837813d67f33878569306072dbc93850c0329c7f367bb78a9cca3b6701cce082e88efd9d56bf2653fd509	1675585590000000	1676190390000000	1739262390000000	1833870390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
66	\\xc334f59ab84e2f4ddbee50219679840ae89255aa9b391416bd63222880e9471b8044a2aed7b7e2e1403fdade85249b4a7b4e7e73d9f23a0f39b5e29b73c742dd	1	0	\\x000000010000000000800003c79fb94dbe133ed265d0cd35672c2345710f07df26cc62acf4636c79e357823a8a5459dac67188da05ef2c329aee07464ea81aa9a90c6c4d49bcf3d4708a892239060de55b8567596178159ecd690be00abc2caf0d60f625a4802a87dbfebd5b6e00252c9476c00cc81f3a1ab4bd4450b08d3e5e98fbad4da1b3831122bb7c5b010001	\\x1e771d2bbd2b8f655b1a4eb3481e1052f4fb1b480ab609be940e28d3f65079ada38d5811cc61ce13056c88bf34f0ab8dae28b165d510a065dd4abbf6a8559e05	1672563090000000	1673167890000000	1736239890000000	1830847890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
67	\\xc80449a41f659f62dbcce3144c993e2e1d8fd8f2ed64157f5d93cd57c25601f4cd9f0028f951a2052836c134eb54b638feb320cec98655be834566181cdc9007	1	0	\\x000000010000000000800003a5c318c5a7ebd944c8fbe1d15a5e55350a7cbed7f19dc17c2e0fccc65a7abf67720302fb76eba5bef2ac02b2da7931541c4cf5e6814d084eb798737220d26fd818898dab5c4044620f9a6da9e0a97b2753e7e688f231bbbf2645c010c0b9ac9df150c430e5b831e3252f7a364a50cf3dd1b75efa91fda3fd04a52094f12efcc9010001	\\xea97ae234a569f7fa27545602bac94612816d7ca866d9b0054f6bd63dd489b42977626db7a661396b72e1d53d1c1bce6e347b2c12c9c87120b4082d8d966610d	1656241590000000	1656846390000000	1719918390000000	1814526390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
68	\\xc864a69f3c29b253e2dfd41470f75e6c0f9eb977859cd7fd98a87571e65a696b732996317ef05c53c52dd44281f2bb966dbdd226299b94316b63901adf726435	1	0	\\x000000010000000000800003c43aa1b92758d0db51021f9fe62aded5a830bbab46bfc3172ab4ff0930714d68d961148364e7bbdcaaac1826813cea69c19ca2bf7a135a9fde71deb62ca4a4a6b87e8fd807d230730fe61932b06117fdb110a33224fac4d3bcefc41af2c2bab9a5d6211ca3ea7fba9ab239ba2e2ba601394c5c45599c355398a166630f92028f010001	\\x502bb182fa7ed7e45ba4a949671494e2478df39f77a3f5d9085c3ee48d57929edd8ecc024df2ccce1e73bd0f655804f2a81f521eb3d910f9edc8d2a6e001730a	1659264090000000	1659868890000000	1722940890000000	1817548890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
69	\\xcdfc1a4c4fda4942c1b5bf70586d4b6269337de48bedb651c0e26053ed4a8c13bdd098b5a00fc2f17a6615830428ef675e528cda8bb63e097697bc3f52657068	1	0	\\x000000010000000000800003b53704e69d2de2890a983df1a07c1d6a234279791ea997f5eac7651f61ba9b65fbf3e8d17969e839fc0b14e96f414b31db9e07cf6f60963695589cc4897a28e75af45b7d5f988d0c10463914af544695d277276c3f5655191290e20a1e81f124eb2fcfde0dd254af64fe394e4b0c4472cc8754c0a5adf2502c13eca8144dc307010001	\\xcc42d1926aee79bda8519913a683d4ffe2665da1899198d2757253c022f143b7cc4519c376cfe5a0502c5a9dab5beef04ca063e23f568896b6fa924000bd350c	1666518090000000	1667122890000000	1730194890000000	1824802890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
70	\\xcda828e3b752f10b11e89ea38f22932d2967cbb9fd6f3e4cf28c21c2a0b20fce0c87a546e9faa6ca4acdab241e82c66780c36e05df031a9c7c58351c195baeee	1	0	\\x000000010000000000800003aba76a5b69ab41804158cc5c6c5a12c0b50f5477d8dca9db37c27f502c7dd5de7d32d9bb97f7e07fc091650bf5801ac0479ea54d8154a02aaeca09d1c561913eace71386e7332f342f7315ec06d281aa253b32d79ad1718eaf53acce74816f763ac28c224851775c42ef7acb4a9a6a60278667e111588bc3fba7d38025184011010001	\\x05ee1a67f8a5e8afe36b6d4fb6a0bbbb155f3458a5161779d27eb43a9714fea6b0bf247249e2af78df00ef32d5ba59e166c562ab0fefc9b70f608f76647f0b0d	1666518090000000	1667122890000000	1730194890000000	1824802890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
71	\\xceec9bed8e10c646a46e1e0a486e1af78767fef2a369a39fe2e4948ad38a26bf621679604a350652048644c67df340ca696ee6a971cf0cfbaf6fab8b2e1730bd	1	0	\\x000000010000000000800003e179cdd13b79a471976f612b54e8238c9f4e702e1a9ca804300cd7d7b4113749b38e09e0b6ca8b6d496117df04fcfdbec5f2e5f909049bb6bb8f75b4c998c5da0b9aefa9fce011b29ca94198a86eda69f7623095e55dcbb2a2b91272bde46e8f5cef0657c24e2d6c8c2124c09c5f6d72a783e02cd67244e3f6d8246b6f972213010001	\\xc5e6a8662f9a64ce6ba9dd62871674115f06c24778a5daa147681c35cc288b6dc7ec1d21501ab232c07f357dbe808bf56beb9467d434f35d2d993a3927cc2c01	1648383090000000	1648987890000000	1712059890000000	1806667890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
72	\\xd7a4f1f00258d5b2baa06394d09ac2c3b5350c5b5e7bc90accb2a2c6e0b8ee06179064797f88642e733baa571d4a71df5af7bf99d20a9b03da16f424ecc8f959	1	0	\\x000000010000000000800003dde91ecaa905a835829765d6a05501991dabfb503e058d5c95bacf82984b7d7753da3666ca2e919c20a3b53c1921cefa03650d2baf5284270cd8a4df8867074e1e11fadc079c0d54432724f72ecb1e5ff2e49b75a6879e1c3abf111381ef96499f6e9145dab7c82d10258bd787b704a5073594f7f39e83d5aeff9a16e19fb887010001	\\x87c3d188047d8cb869acd207a3de8d545624fe25d55aa77d3cb80f77f28d47f120d2767228062c3648845110e0547f5504803e44f03d08a1e958cf927e961b01	1657450590000000	1658055390000000	1721127390000000	1815735390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
73	\\xd8885a5a62cd546583ddea88e00f8a2b1f65362f358418d580c95339516b53dceda8c4aa73cf2725ed859cee8f61c3808e7b9270dd87ca32432c056dab707a52	1	0	\\x000000010000000000800003a60dc52a4e8437d59246109a5516a764144816ef5a634a1403780ebf313d67d6cd095b2566ed2c58df52e99a803e28528a826d2ac1c4be698f879762bde50f40029a1fae2fabbace210d9a9a522a158d9ad400bf7bd2fcdc69bef6e6014f42b4872d13c099724fccc29642c7d3c817a9ca36de35b5e26636d40d6044131c791f010001	\\x4518024f0b63dd95be5947f107304a94e333cc614e79dad0b8be3712a65fc09b1e6cb9d60a0f86ed685490fed45ae80daceb18e6eef667b345a6d0f43427dc01	1678608090000000	1679212890000000	1742284890000000	1836892890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
74	\\xd860be925fe77e68f418d179b9b7a76c3a8a6f47b0b0df115d518059c61de2208c4cb6ccf50c25f01ceb87d7a8fc14fdd9b0dd06828a26580b3a243f8e78b096	1	0	\\x000000010000000000800003dbf857e4312b62af27f3e871fabd4792a577afd0a8b23a73d56f8f0aee8be3fb7e8ce8f8034fa460d41ab575830cfb83a151eaff6887cdfb63e139ff4c09097a890cc861f9f410153fb113b0c12d65d144b8d91adfd9e9d6f6acd54fd1b726b6f0b2b5faa6bee75f3725644b22b444562714952aa5392427faa2f89d97eb40cd010001	\\x05ede3da1ed503071b27bbe9344f1b95e4c160b710af48c6009b1ab87ce5a4be227af16518a00302e85e9cf8459133789da86460678849023f7456b2ab758503	1672563090000000	1673167890000000	1736239890000000	1830847890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
75	\\xd934ed836edd46c3487dfd9b5a2508b8cca8a29f9217f34bbf98bc61b9602e33ec5086f10445af2aee0efda350d63936224f13d4f34bf2abfb1ff23cb2104aed	1	0	\\x000000010000000000800003d653ace8df45aa691691b016daf4befebd0a4977075a3c657b7381af43ac2b208c7ed60b6220d495d4b9b47b1b4c678812ac41cd43be9e9e91e42e8493c875599d87dc752aa4ff9f3eff61cb0342efc479c2d8e6853624f511098c0905ffe446626e327d25e4bf3fce54dc36028ebe3fdb87239d3cfce3a014b2597e6a5bf0df010001	\\x476f3998c7b1083c58eeee5e28a8bcf052acc8aa518c7ce37bdba7ca83c0e644a30120c1fe0c4a840089f127c148d44bfc3ef8b08fd1e6fa85beae09fec2b007	1649592090000000	1650196890000000	1713268890000000	1807876890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
76	\\xdaccfffc0adbc37a9fa3fbad868c564d577895dfb970b6bf3d50d46259a87152015db9690f4c421f34dca9540a65427dc957de63ec9600ba3228ce99979559d3	1	0	\\x000000010000000000800003f3ec93f557e582b72b412e74204d7c2955a8b4303469943e76aae38b5998f4d19147a63beee1cf7c87c2b5fb914480e21a0cab8bc209fd4c945af5016cb20a4a744705fa8678c9d929b4512c121cbf55b7614174b832dc21d87ac70430eeb78025a1bcdefb4f14666031618333e729d0c88198c9bae7220c3a6dee3cae6432b5010001	\\x9a885fb0f45987b66d72b18dc1ea33a6325758433b2c9c3dc906a912e991b9a08f03ef17506c0247de74f70c7368c995c9142c654f6321f4be0e32f8bf25bb09	1666518090000000	1667122890000000	1730194890000000	1824802890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
77	\\xdb24d68a116289a304a8a606b13d61aa901c3c1b745681a945eab85f4d2fdfd94b083591f0bee26cba2c51ea5a3f56bed8356d1f1875139c3fa4dc15efa59d82	1	0	\\x0000000100000000008000039b155505ae678a0ee27b053e44dd875e290eeeae8243888e9be8bbfcc4386e7bf5205031245b388d5060c0acee9e9e4bc13b07e5bc7c9448499ea8e7d7c635c98f312683c68667539ec069dfcf3e7d4fff44073d0d711077fa985df66853e89fd3ff11d4548a5a20e2783fbe19a359f1be8a8f4af9444d311a804d3a2e203f6f010001	\\xd800d4c1dcedcc0f69f3d706e50266dab0ac298782e711fe2b15d056e1a907ee73043e7a7f4ef141ed5dcd42e77737bc73f31212f6f525bd10e72d848373f705	1667727090000000	1668331890000000	1731403890000000	1826011890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
78	\\xdc38df1f368387ea315f3ca7c5c229b0ff7ec1642abe6b43397de1f21c80614f6ebdf323ef856e5ec0b352cb72d33f62ce7296669c5805535785b1d917aad59a	1	0	\\x000000010000000000800003c31f1321b23563134581441d68a11ca2d75e1ed131c99530682b517f1e2386365b6072c1adef71e8b8664d11b37a684348a4b944eeba8f890a7ce760123c1b7a8be0a32fe38647b88490c4e86af696d338a51c8f96a28c941659d09d93498566b5ac07a02f9a709fdd9d2d5538feafa6ea97c49f8cc6b8a21f1868b05c721a33010001	\\x96e479ee55f07d77b19605ed61208feb7c51de323b737f9f48d35db6dd83565304eb414fbb68ff6ac6c201ac01df8739bf717359f6cffa903ad5b1316b89f70a	1662891090000000	1663495890000000	1726567890000000	1821175890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
79	\\xdd58a7d6208aa1d9c22687feeabb880e0a28ba56ff2340852457b3eb16691ee3b05d9e004e586847f6065729cc069ccaf41e056944be391e470b27fa86b1221e	1	0	\\x000000010000000000800003b7e9b4ebd56dc4b48e75b9d28eaf608895ee87ac2c65aebb5e532451e824a352dfc69e9ca02cf3f6fa62374910b6e8cb27aac36764b7da5c05e051f480276af65f24f43b70beeb6170b0eac9d776dd47231c27c0aa2e68b4a31df4fdccc983b08d32e8674debd2cf831cc2ada6e65ee0ff1ea9c3811d8d73926e891b2f223467010001	\\x146898cfb178cbb33d59cb06a169fb08ae74282f4eaf69cd24ff53d09861d02226cafcd43663b799e580e65399502c848415585e556715150d7c13ff06b98305	1661682090000000	1662286890000000	1725358890000000	1819966890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
80	\\xe2a03bb2172b885551b5d7167fcf23362442289f6f0c2da9a8a87af2ec6de83ed0b08134b540b15e631888ba56d4ea720a43ddadb7297f7b157a98104a6b9150	1	0	\\x000000010000000000800003b3f60e6e04559dde1d8282bc6439d52177ef349655ec652ed7191a5ff550fbae58821ec518afdf226226b03026d4a6cf7492e3c5e4bd7cb4a38a3bee1232707b4ce81562bb56d8ace8227dca81bff52d102589b202ac57d053267b5554e3b9f384e3417a86fb86956ed0f4b1d2ca2b43049d862c5eccad8a257d5fd7f3344bc7010001	\\x9cfc1f105076d3498ff5f5383afdb76be89e9292f76ac7e6f6b0907ae94a33a0ef0ecced6320367d118f4e4c975a689c389c4a4734d8bc4babc1135ec09d0f0a	1656241590000000	1656846390000000	1719918390000000	1814526390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
81	\\xe4686725c3c8c6d19915e8dae9f14151bd28ee24490bcfe6ec1da83fa76e48580f8628952c675f6c0be8529f50a771f5f7f5d4b8275a2cbacc144abe6b9e3556	1	0	\\x000000010000000000800003dbac2950a10611179988de1e9f7e5af2defec036803b6bec3632f8c35c1841d2ff02573864e5514facc508401335135837ad4b948a38e2c4f3c3394a4a12ff645d1d041a472db2c51562896ed6679dc825f4cc0a2d49b327390e5c1568d6579d8093c244ed455660424ccae576a3fa65d07f53d34aeca480487cfe4564b3a891010001	\\x44ba46d85fe200ef8711c41ffcfe9f255ae0820384bc0d26b4b7678694217ca337be5429c9cf2f29a4be4ec25e24c97a16b3a4f3eb17a37afa41180ed2686106	1676794590000000	1677399390000000	1740471390000000	1835079390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
82	\\xe4cc43bc54d87eec786543484d69948177da1f90eb6bcaea0dbb1e18145ebfe387e00476270a51b848b409237a03ab958c7cd001dc99f306d8be172a4e5feb76	1	0	\\x000000010000000000800003c3aeef0ef1c03570869bc8eb83111ce8f1d24d8c90ad6273098fca45693736fa815c071548f1e036ff630f85a291433537c56244d47653918f9177a8057351f05b118a1fa3b9738ba76c48c8dd84638c6affcb91eb3317414307bcbdd8843fa7b8ded20bb6d39220c996d3252193087fc409a475f172ff18a292bcffafe29311010001	\\x098177a51dae6de4d0dc5cc70052d44a4ae1d86ec9b72a33b391c7763c85c3f61d5a61cd7c6526c84e4f0ce908efafe7d3672c1d1e77d14f7624d82eac19dc06	1661077590000000	1661682390000000	1724754390000000	1819362390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
83	\\xe574affe89e37dd10a07b3587a6490fa851592cfc6110104b31784729a75f952e30c639b0e1c98ae1b43af012bf3fe23d432279633f7563f63c6ea1615d50fdc	1	0	\\x000000010000000000800003cf73ab650bc203e95011450982fc9b6e264e3588da5bc305f2631c76b080f6330eda9f2b5db7e762fcf20173e374b025fd6b3c5d41511f0c2d280b8a9e267e7dfe3db4192782bdb8d63580e31cd46bc7c3b8f79a40acdef6a011c7a5f9e17823417a396d6b2422f1a83896e6f5160837038976a4701529e9bac5984915dcf25b010001	\\x80067314d960079c1713fb15ae281797c524a3fe78be559d9d65ec751d7e62649224ae58f024dfbbc6f1dc6dfb02122db28abc16dba69712f6a7b8cc80d48f0e	1649592090000000	1650196890000000	1713268890000000	1807876890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
84	\\xe65c531b1de595f8c43cb90bacec55bf83c5a0779ee755233754c847d7d4b5951d82e90e1999a3a2c0e77addeb0a7b0e65ad7f11a83c013df0053ce1849284a8	1	0	\\x000000010000000000800003f2e2a868f89161cf44861f13d0e8e36143c2f0f5b68536f919acae0ebe50da53c5bbc1b69b6ac02566e04b09c7539698ba59f5135c81852561c10824170acff26bafadd12841d9daf497cd576d2287a1b93bb1d87b946eaf0bfee0ae8dafd7d0703bd24853cc098f4af97e8339222207fc9c00de37367e7897f8c82806071323010001	\\x972c2038ef91a1612077c8336bf2dfd536dd911e75db72af6502f81d0d0b19f7c883717942594dbb433834e57c7ec2e6f88141484542ef33b575a71770fc4101	1665309090000000	1665913890000000	1728985890000000	1823593890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
85	\\xe628f3db42e1fe33ef5379cf193e18515e86619829a4571499862aac2beda162658cf8a472796f0ea1f384e51d784f4ac2070b3b8557d0510efbacbec763fde4	1	0	\\x000000010000000000800003c01e456f2fa70725983f5b65d7e09ca981b4f96c7e659a9bd1d29cf36e492e0e67e6a4615c5add2e29025791ba1fda23444badc738603c8f6d8d245b226154e8f7c8bc3c8bd281073449a287ad4356e0769a9934b5ddade4309f636598073394e9f8d833da298980356a49fe8848410d69367cc529fada7fd3589f6ef2fb5eef010001	\\xc18bfdc278a6e5159a9c6e6c4133991031204fcffc9207ee88fc1c28014e7f0dfcd79e04d53627bb7b60fb494cf0f7931d81238ec88f5d7f852fad8a8f694201	1668936090000000	1669540890000000	1732612890000000	1827220890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
86	\\xe6ec8d3f036bd8ff16401019a0bb0c5a10f1b27d398e0b7323ce2dc3338792ef1d2b69c398d45549ba7b5998d46730270869ca778ae1792881c294b032f64a17	1	0	\\x000000010000000000800003b64d41de187a6fe27072c16f68b99f3374a5fa1d862bed918d95aaec86eec09b8c17c350d9a7a528b1346b15ef662fe6a063ae9177a075a1ebf7fb0ffbaca2bdb73c66d90fdaea1eb359b9c4eddb95c68fc56b95583b1b64571c6ef8aa58637cf3c607c100fb775448eeae8bfc14c9863ce65061518866bc7c98dbdd760e3ff5010001	\\x1669ccd795ca5bd5024fbda1cabfb4f71ca4282a62c1d7236ae48da870694308714ad298ff8282c7164d58d8f6533897efd1a282eaa797eda92aca080284a003	1656241590000000	1656846390000000	1719918390000000	1814526390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
87	\\xe988fab30b7510ac42fb24ebbb523d7112ac0227274a1ac398378f80600d3959aa66bcc0bdd03defaef81d669c0e7ea68d5d3a488bc0a4a1197dd04de65920fc	1	0	\\x000000010000000000800003b4bd392d3fbb8f855fa12c95a40b2878bd6b34d4a9e67d9c3918728d3d1b54d804e001cec2fd0c3d2d3e1b66de3df7d92ec4b6ba8a078632fe596a5c9f9c7783859e524b1d896008f157bd96798bca2e70122fb06514354eb960f87ded433473b4dd87681d56d76adeaaa475ce1dfebdf259bff27ba5f2e0d6eb16ef7eea73b1010001	\\x2f00db07240169a2257394b909d7c9aecc9a6f51c4b5a8a3054310548f32d75e9dae65a310c09fbe38197f794408558590e79c6c50fa3f54e69a1290a4bd8606	1663495590000000	1664100390000000	1727172390000000	1821780390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
88	\\xe998d08bafa99db0633ce177e6e281ddb3df5fa0507b07f593cd6df87f0bf6f9c6c388e8deb84d839a2b4ca1c070824275fc043aa2a3ca89de22deaff15f053f	1	0	\\x000000010000000000800003ea6b85cc35a29da091950e82843bae5b683b8a7f8000357f54ceaad662d253c4b7cae71352d146d7fd2cee47cbb1cd9313625f602fd18405b5aeaa4eddd75ed4e7425ed5a24e616c94e8693f616efa916d42fbaf1aa0c0ad7ce95549fed2368e6a64573df32df38cd91f73f907d852774e7754a5756fc8f53545f21bf5b3259f010001	\\x32577d28f2db0115f36d2449f1d2e05b2b94efdf3c5ac82650bbd6cfe4d85f287f2bf527674b3f87145ff7f54177f8d24ef6e0181cde1ff897849a0d8833d003	1658055090000000	1658659890000000	1721731890000000	1816339890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
89	\\xebccca89561fd48acbe1c49283cc832818eae3fa850eeb0ce584ea9198679c244c726f8911a2b0ab29b8eaf84720448b0cd849ba641bc0fa936b5b1f3e4c1b21	1	0	\\x000000010000000000800003b53c4e134dd9f08cbf13878bbfea2b03803ec26c440203335b467a951ddcbe4eab4086812434036682c8befd6158d5265770117c6538e37c7e714c8b17e23ba2df9be3172c3328045f6fbef1f005ad935de58b5650c7a554485ffa1930d1faa18f181ed728ef27fb193e95eeb63bfe2720862eee620123dec23e2031362d1639010001	\\xa3ebe41df28e97183e136e042b7e983251774a4e633f8516ea033d9779a42c295008a6a877eac538d52706ee4e7cfd7cf21191f66c15c0bfd18b4a76c754b00b	1659264090000000	1659868890000000	1722940890000000	1817548890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
90	\\xefd49b0a9309cf543818f1d950a4f3a1ffe49c7826fc3fc7e0adf90975d6e4fa07aa25760fe02a72c3850f51b6d553b529f282124e863321ae16ac39d88425e6	1	0	\\x000000010000000000800003e1456ec82ede7bc7da26f661159f5907cad2992ba2c8157d65dd5cc0112e37812820987b960a1a5e257cd2c541e08bafe93a3ca0ab2e4ed957eb02d24300178fcc5ccfd93bf21bbb9b6ae85f9946f5604e537bc09d4744aef94e79868d9c8ac0444a0a24e6d40441d675e3e628f29c16decb096930ecb39a15059fc0bc68b373010001	\\x738c5bdc0b5f1c02a36d5a9635d55d3faa1707110bafb9a34e8739cb363327143f23c79cf903688a26e8b13aeb8162c3682aaa1ccdb3d09fbfe07f9b1630cb06	1650196590000000	1650801390000000	1713873390000000	1808481390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
91	\\xf110ec57802d3bb470e91f0b26eab02945dfb977e1918b606e511436d6e483c4faa826f755037fc7b250f02b1ab0971a9868ce396c3a37bcbe9db56fefa4b763	1	0	\\x000000010000000000800003e3872c33346667f837d58a6a56c66829257e6109978887df2f085242272681201304f3328e894bf2295ef983c862218696c5e01a5e21809f52e0d48e9102c7aa3f8c767099ffa2f4ce23e1920713bbc64a6e41f37fad63b62d99d5189a2d12381f542d573e926ebcede982a409d6017e81386c74b53722e6e5a93790d5401ed5010001	\\x4b0a585d39a929ac3077ef3af68dac7e37a044b1222ab9c17398eb394306f3cfa8715db1ffe68c278b9a262a62d4c2669b0c6967addeed7756923deff0866e0c	1655637090000000	1656241890000000	1719313890000000	1813921890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
92	\\xf2d0ef65f4ca7ed23878d99e82ce73d2d552709025f11852c19c3189430e478ee080831179bc6ca6ea322006fcc114f1841f475e7db2713ec8bcc748e5d00041	1	0	\\x000000010000000000800003ba46ed538e526c0c9e6fdf165fb340f535b16fa3afb2c95c56661f5fcf180735d12e56268443c0a47df26634223675fba3968566d085d91143c009a1e1c7c06b1ca6f2923d5bd2dbe6d4db56c9ac388822329091e5e08615ea2f0fddb5aaa749e963d0941e636b0e10545fb821da6d0645caa9481553a46a13f5a4b6286eb3df010001	\\x828515370eb850e7faf6afa16d2591d2efeea836c3da002cd7eb58c980bf47eb41a5885e5648d8d015136745b77a193afde6fcf6ff82d46c9ccd90dfabf5d003	1673167590000000	1673772390000000	1736844390000000	1831452390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
93	\\xf2982e7f85086b044ada7a46113e526822872d451c0e6f3cb1047c782f7428c142a3e493bd65676608b036e9ff83b803ad33b7e408464e289b8243f6dad32650	1	0	\\x00000001000000000080000394acf51bf3db010c615640243bcb10a3553de997d0c705849284fcf9cbcbafa3784205481b1d6e9facb51aa0108cd4d5033bbebb31d7c93b3128e5378e390809a672f11204588cd1a29c8d16fafe281e49864184f2e5ba2734d07d6e07b5be29601453bb89101925423a4b9925b98f324bf38eca427146b88e38a869c6ff3f1d010001	\\xfca8ab30fb33308e08739ea1bc8e9de786ab65dacd6ea078f9a312e87f4762f83cb8e98fbed4156175f6164fe83b08ea3f0a1e29d629ac3a0847e1ef8e91e103	1653219090000000	1653823890000000	1716895890000000	1811503890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
94	\\xf464bde02827d9c07d012de9f3ecd179545381e0004fc0382ef0307c747d858da11c4b40f6cbd00cefe5c49619dcffd0fbb588c92c6443185656acdcfc4149e4	1	0	\\x000000010000000000800003cfa5744235bcc6b29f56d217b1c7f3c9a22a8dda66cfcd3e397cc06457aec64c5caed5930b8817e2038b3fcd0a907a617f04e685aaec135574e02b13dc2561c6a5e0261641bf4b2d48f4ed3c13d4c10f72ac76c687ea02017632be00493249435c545d20812f6ee2b8480ced1cc6b95d9fbb333e8a21ce0bce513266bc4863b5010001	\\x45ea47beff77fa32be670454e05cc201f718aa7e5259fab0736e2f3f137ff9b769582fbbad9b3d50c213e041f344bf162c745286d4f9b27e4e0cfde552fbb20f	1667727090000000	1668331890000000	1731403890000000	1826011890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
95	\\xf928ecbb57e972929a17f52ad18bc74f6e24ccf06ab594cfe3e1dc4c6515d8964b741a5276c331dacc291823785d6d58f68955ec1667844842d4e9786b8985aa	1	0	\\x000000010000000000800003d3b75d94aeedce300641790e523f9f0200187077145bf5da5b4afca227ddef3526c7de93da3bc80672e883fbb3defca7cda08267223dc2aa9419401fcd6497ed6150ea4d24dd10b2454ad5f818bfc7b72b1cbbe08b68a0180850199995ecdebfee477388a7bc80439adc588f6cbf0607a30b6ebd3ad449f3fd4c7f14d72dc47b010001	\\x076efb71f4ed62bf4eb0a7ce246747800fc6c4067b837d7d26e06162d80146466a40ed6bd8bb06bc49b4470bc66a4a3bc02003b1f7648124730fb303049fe10f	1654428090000000	1655032890000000	1718104890000000	1812712890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
96	\\xfa30790fd497a18de20b7bb170d9bd8ebf65cd4ba6cd10177a1b4a7bd74af0e78367e82434b91139a62890afd6ee355ea722c727011559a80dd416a4b2b53037	1	0	\\x000000010000000000800003d54a07a1dfcf6d81f3264c17c7d6e58eed46b3224d3267ec6d287c6e80adbd8cd814769e6b69695a83e5e6aa3b534d5a764da6fbd3c4bbb489fe52c61b68148023132770133d6d5d4d867d6efaa872542bf00a6e426efbbd628b3ce793816abcf5267680f77ed42bed70f0669b1272009244d3fd497b95d012f298f0b2d20231010001	\\x170e9d5f15e72037150479609b5d2b4d1ba0b932236787b2d4ce9be3c2b75c049f7b142eea4d4ea1b81b8adfa298abe9473d54ac787d99748771ca0327dfed08	1675585590000000	1676190390000000	1739262390000000	1833870390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
97	\\xfcf80733905a328144cff6c2aa154a684a98801fc097b81f4253df609469eb0c5d76d7be2dbd99b62b0d871c810e21ae6fccf93386aee2e44b5b1222a2bf7614	1	0	\\x000000010000000000800003be4a152b5579f31f8367b6d24e23ac57f6444e0cd13cbb1f5626a01cbc0ec85b08e6abc69bb91e5373608c3353141996bd46696caa30c44bea709ec38043ca8737bf3bf2259b81119a0039707479409bb951b20ee66bc78e8754263cce3184168894d9364730ee5a2130029b32d1e6c2da8644558c0db0e473e98caefeb9574f010001	\\xc41916471f607ce49ba650e8ccf82092f07ccb145445ea7d5676a22c1ff3f05d1ba901ab14c782c9b6bd80cb943e20530a4aa5cffdb50fe64bbc5e0419062e05	1679212590000000	1679817390000000	1742889390000000	1837497390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
98	\\xfdf84170e9ac7868d867a6a5f86b3305b862543eac002d0619ee37b1796706a61a37b0d4ea70254850f4e0c4fbe1154e0aa2a0d2f868000a805601868ca3ca68	1	0	\\x0000000100000000008000039a46e92c40851985f45f95d387634e870a5ab836f384ab9bfc4991725fba0e31503d164316890a1f9713f268d8ef36142e9b24a576e6f1f3127b0945f5ad37d340ecca82358c41945a78ce8bd7e68ca722a4ee3c84e1030abca6c331eb8f82e8cca6df97949c3317a309b1ec2cfe712658d9fea5b1b89cb9e3ac39f0cf2a0c81010001	\\x71b80163e4edc82a27201b62ca644c421c3d242296ff72199c4e8e307f8c66ed4d9d41b0b1f05d73cd5297f61c93fa7967a9b1baa060f3fcc23ee77e16819b03	1664704590000000	1665309390000000	1728381390000000	1822989390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
99	\\xff206073a22539fcbbd64cded32f99f2cee4962f3e6119d356263d4dc41c3c6c3b72b660b202c4423466b4e5d94e5eb8bbd20b840f1bb1866b171a4d208ab81d	1	0	\\x000000010000000000800003bd38d20cf6fd7475ebe47e1f1f240a2f9fb8a0e4391b3934dfe3f0a45181e2b1f5686734de64216d4c2bd3ab52c4a5a0b298eea6e7837d18bdaa1deb05645f9637b0ba23797ba6872e2fa65ab52eaac363cc0cb063d7b012579b3e0c654dedc393e299cf6baa87e0ff2d26342f933b28c7666ee79baf7949b01def543d586e69010001	\\x66db8d0b9523a1a258dcfc26bbd690f83d811c8bc751b28ff1338730a95164acb8cbde00efca6d6fb2b62d559a01a1295909b06bc120b0fd7c7974414657bf06	1660473090000000	1661077890000000	1724149890000000	1818757890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
100	\\xffe8844d07fb7601768213191dce19a9437138190eee446dad06bbaaf196216f9fcbfb31cc3fdf7a165410caa562ed9837e12784bfa041766969e9bafd80459e	1	0	\\x000000010000000000800003b627cac7aa0556d9289d5465d21efe4e997a0df1f9e3f2ba23bdda520ef8176512e665b2048bff98e3197373920228f95085cf443e4746d7a4210c2e43211eadc102fafd1155c004f9f7667c925f66c6b52a2b7e170e182ddd4417900f1e09db8644f8ebe5e9b5bb7a6d5a5a44e34b0bd3ae3b8f64045cd5557bae48178acf55010001	\\xe015802011ee2bfa34f8d08d88b3702d05c29c4e1666ece5b4efdb257f72e8c399077282d8c41a281d760fb554ce2965e962eac5f5890faccdd6e0aca2ce9202	1652614590000000	1653219390000000	1716291390000000	1810899390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
101	\\x025583e836a1f51824168f3b55c2f9da05c7e13b6293da38ab15747a429f0228aa8093d264b77e4656d63a2ac57f5f76bf67c0ca7c26a7aaa4f0328256d87b68	1	0	\\x000000010000000000800003d4e7df6d4c66e36b6129426244bfdf7f8b62a9add37afd235b55ef4956d3b2e1e7f6e2544bb67a51311249e5d99a6ba671009d9499adbe0093c9fd8bcb67f159f017d378dadc53cfd11ba9775f0b36702098e9b7161bce6bafa9893c2fb26b85f5d68e662adb6da45fa83d5950df32bdae484451ad6d565e5f4a3ffc1144658f010001	\\x5393a69e0ead1a6e79cd596b8e7ff70260a0c2c01d27941589cb14ddc8dde40a949b21a52c1b57ad61a7cf8f9392f966c4a10ba8bd846c71b6cf618fd4863f05	1670749590000000	1671354390000000	1734426390000000	1829034390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
102	\\x05397c9d8d0b90403e9f3c4e20cc7d1b2caf28ccb390e3c81ac766678c492a5e517f2a8992057e8079b030c8fdeed9b3fcbf7fdc419d7b3ffe68485e2d31f8ff	1	0	\\x000000010000000000800003d29d7f8ee8708c21b2eb9e5484884d3e6957658cfc787db24f0e570c9df3fdb6d3cabcc2afe95da85f40b5f028b68515cba1df1c1b1b2a61f18008a9393271e60b8a2e5dd95afc0a649e86801d0ae14f4a999c4ff339c01fb28eec0a6146dbec5b443a2ec384480b2e46c36cf1d78c7dd54e89d7372690a01e6acb310799de7b010001	\\xfb05dfb903db2f714c291b95332761cb612f30e0b59116acb296838f3dcedd38ae91b75bd28ce4a4fe3887d461957fcdc48fdd34d39c8ac92f6ff4b98aa8cc08	1675585590000000	1676190390000000	1739262390000000	1833870390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
103	\\x0695f4d304b7c4e1207b63005eb2b5044734a002234e441ed3df5699387b014bb2890eb1d67627b5093da00f2d2d789833784649b841edb5b955bc0a2a0cb2c8	1	0	\\x000000010000000000800003bf3df4018eddb1208625d7378f8d6f1292aa42fa8363d3dfc3e46a632b93bb34393aef4cd616d57331a7f1d8523c05ffbec554332d361062782b682ab0b50daab9294f75352b17a7a408920bb8716dbc6abafd291e911f4f32a3a4d61fd574a95f191a182f281a1a3bae3dce751dc68aab7f5b3b3878de4e09fe4cd42916001f010001	\\x27a36459defcd9e844a6fed7cb8bce5671adec04f3f4770c513c252655676e08a06cbccc778e23f055e9ffcbd6b7246ad361905034c4bac885b99db79b08b80d	1678608090000000	1679212890000000	1742284890000000	1836892890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
104	\\x06c56b3f6ee77a493d490e350e5e1f9d9b2b31d2a220c9398e629b42d440ca48afc5fbf663e6ffb0e2ecddcfffa64b30d29bd2aca4ee8489bca87c087697f09d	1	0	\\x000000010000000000800003b316afe6a0f836d166ae67654d0828dd2b1e7c4a9643c797cf1ab44f6d0487e4d4921962e301cd5f45edc9e598816e215de1dca332685183b87d694960b931f09b1b8c226321a2f2e0adfc2be192462c8237301b1f533f8850abc9e917fe63635aa5b655a19358f4d1f825504cc5840387bf80080bfa272501b20e05dce0a039010001	\\x34d64815b2aea9cc3754ff8cf6a8614bee1abdab29829ac4cffaddf33df32ffc3b8f9cecb6d39ead96f585ec004dd964b7b0e67d0e604d58e60e5f588061e009	1652010090000000	1652614890000000	1715686890000000	1810294890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
105	\\x085dc89bb5f242ca8191714a3d06a9a39eb9792dc0ab936c944d6904d5e9b03a96fe4c9533985024bd1968631662b50332a083cfd30f1a1968a04a753608974a	1	0	\\x000000010000000000800003cf4f7fa181a0b71ca3d0fefff0ca48259f18a22a348f81b6523323716cea08dced7f5c45680e975b7a6747e6c6764aa1ade155433854038c7a41b9d5106a00e95afe8e12db5ee4db00f932a550b5794c94213a2fbff72dd96a7ec9f5b15f0141ab833425ea6ca53fe96b51d419ee174b9068ae70373da79e24110e3e6e8175d1010001	\\x90e6574672972fad498e31aea8bee69ba644cec12b09ca9bb05b033825bef39ccf189340f162ea5652f2625da15a36d6ca71bbf6db3ae38b5daf99fd9433d903	1655637090000000	1656241890000000	1719313890000000	1813921890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
106	\\x095d697c664c61ad145f9a81bfc99a871c090b01c6b779718e0e9e18e78a7c82959dd7884a2c760aa92e293d307a07f3d1c2154f62d151c92c7c4bfb91e1d7e1	1	0	\\x0000000100000000008000039d1a8133dbfb6af3c1adbbaa7837b198dfd3b81295799d00d31f83a9b0c87faa76ff805af306440f6dee400d860636016bfa8d00d425821fadf38cac81b99b4d87bcc28450aa7b2206a1c57addfb90fa9450254f4feae76ae16dadb38b02a0d4405cba2ba83eb7af4f074b002bc690830bc1aaad9d3d78db1f01a677e4f9ce4b010001	\\x47eec2e29b08ad9dcacc0ba0641b14bbc9926823d9fc0ebe74314ad815acb045567907b385a0a63fa1a15f484585aef196eb32f98a1d2d2ddac88b77bd7c900e	1652010090000000	1652614890000000	1715686890000000	1810294890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
107	\\x094d4e4eb5b13093b12bdad3c262e1f288f7f3fd622acaa929fc4065850fad914f45abb648b3c1be9be2a5dd06f30044ff6458eb8c25085ad40e296f429a3145	1	0	\\x000000010000000000800003ad2fb423529d41feaf1b12f166d09eef75f691cc96038f345dfb4e048919837bc0df5097821d9b936c5cfcdd44afeee9db5761fe63a1b5a1c53cb8c33efedb94d9824b9bf19e6e0b58a77cebfd0d3410dc3f101d4f8b6191dc9c14a22ba4b60faf693b257e9192dc9e38b514e8ceeccfaf54baf5ad5d141675182bfd12a05893010001	\\x10545b90745bcb40d43dfec848f0a53c0182711f2507aaa6356a1b0543c1ef863b3ae7ec0a2a43aacb54e1d0c21d78333e8532a20ca34abff0dbc7738afa7004	1648987590000000	1649592390000000	1712664390000000	1807272390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
108	\\x0a41485de9cfd391596e071b2018b832211e9661103d2e2805d9ba4ae690c2abd335e37a237a351583272c66ab3fbab7e83e73e7586d87ef83956b67266b1a2a	1	0	\\x000000010000000000800003d1f099d125a89101aaf2ab1e8f668d2eb4fb9df1df03ad5bc91355f515c27bcd5b291a16a350b2198d58f82158222aaba5e3beb77fab51e845a302863cf60ade65b3b320dc6dd43d75ef6597e7c2586da83bba1c1fccbcde8ddd229c2599ecc23ad804956be23620a2790c5c4c2e9d96a60e93419b140b32d4d6fa4f7f7fa9d5010001	\\xa86a1f489f054b5ce2add789e4d9b6962a2c8f32ac09fbdf17629988aff1a1464580fcddf2b2f98fb392cea95ebfe098e0610323cdd38acd07811bcb5b8c7b0b	1652614590000000	1653219390000000	1716291390000000	1810899390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
109	\\x0bed80b0a44f4ca27d9643d532be4afefafd782f0cc9c4dd877eceddb99fbc68656bd21591b1844d5e0ac8716f5b74d6e0490db47d5445f11dcc6d8215718f30	1	0	\\x000000010000000000800003ead8e959d03e602681226f3a51282c9fddab236c5665ad41a9915de2b545d6aedb7cb08fed877939bc542864dd734b2c5badd71390cadd69988d898b6bf4f98c2d0ca765d27a8adb6f76e0b3d61e80a5be539c2c734a3cf2937e6e13c8523c3fdb87cdee03c5f925094b591244d759ad3beb07ad3ee8df5522fe322f659b5c71010001	\\x32ccfd3893c34488556c52e256fa44995969e9698da179b664399eebc012bda6103d426a7c1bd52c0f43e9975dba1f58fca64e2bfadb5743c5acd40b0f95100c	1658659590000000	1659264390000000	1722336390000000	1816944390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
110	\\x0c7997c9348006cccaa695ab61fd6d4075c942c98f4791f4aff63ca5dbae65dbbe2d1eb2406e0bd0ebcf62fb1d76ac7637baaa2be752f7ee277c4ae0ee6eddbf	1	0	\\x000000010000000000800003c9dc60c169fcd620714401d71b0e1e7b8b8adfdaf3c08220b6500a79864430fc2fe24eb5eea5caf9ddb0e394107b8c6fcae2ff531be66ebe9c7652712a9894b774ff87717136a299a88390758fa963321df79fe7fc120c2a3a4780c90dba8f5a818bb54c902722be1c84917652439b75071b924ec986ef414fc81d9f2cee13d3010001	\\x4811800a2bd8d09415385be534206150c0e17b855403b7e2cd69f64758f6a41819f66e30ecc814bf415e0d5af81a7269e93f09a4e77793bcd16faab9fe980501	1667727090000000	1668331890000000	1731403890000000	1826011890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
111	\\x0d5dd0788407589ffd4244b6020e8655609b1ad243f34a7e8be70dcd0c892085288416d55d3ae6724311fc6a63237231b2534198c60e8a2f74bbf68f2e8f37ae	1	0	\\x000000010000000000800003b4bbc8bd9a52ad897ade1630570ae22a1bbb032c839b74f830235b49aa0ea08da289b54577aa269010338219f26c86e0b482d82d301419abab04d22abe5b3247685ec1e39431d92ff3ac48223584aad3b4680cd288f77d59ebcd9436fdf849e0968e83b4abd01d2c529d5c212d1811b4f561613dcd6c5921fffd36a7eb3493cb010001	\\x739aa208cbf67f7d5cb7d9436938712570f08b1e3db7e2632ed1fb31a0c24ddf61a0b749bc04c2bf0ec240a7c0315919b877048b36de04b318d4ed018fdfe503	1649592090000000	1650196890000000	1713268890000000	1807876890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
112	\\x184136b6e5c40a4177121ecb31956dbf263926cc661d607587df217dbe524bb68a1a4b151831d547cd2f748ae3500186e0695b72e75cb4361cbfd3b9081e37da	1	0	\\x000000010000000000800003c4556a72fec2b7048c0e5582e9d64e08b1858064f15c93f644edf7a1bac04a6b4e45ec0fc10acd742da4bed33a4879fe8ef2b80d837b424fb1f741c5597c2588a7729682e4757d46dc60f1920a51971474ca45df9804e885bdc28fd156d9c6a1102a26691354449916f04a1fabeca722929453bea75e755712cbc6aaf9f1da97010001	\\xec9d2822a9bdb4a91388e2242da5733251b6131b5b256bb2647d61bcc0018cf3cc11bba14ddb1abefd973ec57946db9ca5f4845f875cffd9fbb8eca6a0b2d900	1652614590000000	1653219390000000	1716291390000000	1810899390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
113	\\x1a6513e3f5e7bf5823b9f619cdc64f26696294b55f62da15626ecc3f6698ee5d88a4d659b923cac58d6179bd4c71d37a08a941e9e8dfa708850eb9d99286ae49	1	0	\\x000000010000000000800003a3a29b4adb40b59c05e9bc5bc3c6e15aad283080aa7fc56100d2c9c74708254b1bd77ee299d25608afa29e353ada3c809d760d10c03a1d1414918d596ad3fd58f11d728fb15862562e48116cb6ace642be7cae47a9e1983cdb712da8f6afa204298d30adf64f18a3eb7e8db7f13bce5e6bcd08508b9ce141c8448845aa43ce11010001	\\xb4471c8bb1fbe4cb64ccb5288466d0ed2e46bdb3a1695140d9b5228c243600278bf9ef33ee05e11a55bab40fd171e777903336ab13ec6edcfca665f0623f0a0f	1649592090000000	1650196890000000	1713268890000000	1807876890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
114	\\x1b49ac9e98d745e507eacc49c520b06f5230fc46b200974230bb0392de0f064ee5446df3165f75c731fe90e218d60769c0b8fcf13376d9871a7d957067c8385d	1	0	\\x000000010000000000800003b9a3d2e65124b481251cd6d1496dc508b07a756cb528a2747fd47c3781bc3d79f13453b17a0ea715135aa69170d986258326d7beab4c36daa5de741aa16db44b07c2c111393c8ca96a4b026232c0d72ee0c5a9888c00b6c169b4d4a32b4e773059e78f5e4a62fb631ae9f92efe735d47c655efc73b253459514dec30c932b80f010001	\\xb985480383cc3ca852ec13043bf8bf500d918beb5b798a920228639616217383c8c09765d513f20bafa05d040b81d5268172f412ed5584badddc516f1d28670e	1650801090000000	1651405890000000	1714477890000000	1809085890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
115	\\x1b0585dcfd88a47260e2696f32067d712e4472dc217c7f7f457eb0e259499fdaba5370b425cc97a2bd2a85624e8c6e667534113b07503afb1b7a71942612f727	1	0	\\x000000010000000000800003dbcf95cc33629fcbebaf74bdba9d0ee51cecf8a5ccb15d7ce5839e2510ccc736faf7f21a53a2e98cda50a81c208a04563ed239569dabd46efb489e655123553665836f7550241f479859de75602d6ea25e447afa2c57438eceb0e0645dbead05c525706a12c542b3834b2ea6dc67e27b4276a55f637b316fc8d6581118e23323010001	\\x307a201310c67e0935488275daf699f2f664e3fa5fc59b729e74f5a73e99765abed9eaab925f137e913aafe5a848fc8fb1b73cb2c6e7e328be7ebd7e4422e30d	1664100090000000	1664704890000000	1727776890000000	1822384890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
116	\\x1c79089aff7370e950249c04abc12e83199c07e8956b31584e703c48f5b6839f19be5df7935d97acda10899fbb258e5b567dd44f491940233373cd80b10410c5	1	0	\\x000000010000000000800003bd0c15f0c9b837e2d946f3cc54747080d316450c1696d84281e244fa1a206d5a991026de26b0c2854c52af3b3fc3e48919f5ccb8e7ed27f0c756ce6aae68c6ad61bd095258a43fd8e3d059f8bcaa25a520b7f81ef85914d9e6d9bd859365d4268324ba07f874e6105b6e358c41c6091de6dfb2edbf11e36108fef436553dc163010001	\\x364d7509e599d59f23efd7b868a57be45387623ba13d03760af291ee757d5d4effacac37dd5454612bdccc8c3c0f481b41bdee2b04dde4a2c1a655dbede14800	1675585590000000	1676190390000000	1739262390000000	1833870390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
117	\\x1fd1abb1db4e89466633b8da223d0ad432ca54f1f60fcb577c5a28d5ff243d1fda372b40baf2da5cdb8ece472b3c4f1e3dd819a4dc7eb2aaafeab09359eb8081	1	0	\\x000000010000000000800003cc6b1eaa9afe71e2ad36f8cc6f2e02c9d028837cd11875f673c13ed7e6cbff7334a4d66bd39e5855fe7369754e01b7be847abbe2ede376fd6a83df1875c66f9148e342866316a9309252e4a2a97f008074bd01e73513418780be994136a55191d9262fdf0d05563a7e6ca41be625337c3796e1631a3a20e3d2c70adf2b01f315010001	\\x665aef8e0fbe6d51c1e1a1ea91d93fc51608a115414c8bd1a099cb9e5067221f504b6e0be00cfba4ee71b634c71841bd5563bf7c4573e2e8f38d7b9745e62f06	1657450590000000	1658055390000000	1721127390000000	1815735390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
118	\\x208976fca3598b4492b914dac08b11b5caf71f76cc7a07f4d8a29d5961daf3269b9d52d0ae82e466f31c4a519bb4f8605ae9c6741a7be1bf42d6cc6e482a96f0	1	0	\\x000000010000000000800003b7f26e00740ed559f345eb0830b13b16d568147d9a4f89dee5e2be024e15aad82fbb16a15f900492c2e69f64e9374c2bee7de193d945bef1b1ba776dde0b8714f29f6d3391afa9224735f5b6f8f3998c67098f59659cf33f49ee63b787fe8529b9cc4c8d12bfaa728d4dafc919fbcfa422dcab350e4df62b8c159d16ccc4a82f010001	\\x4694df1d8a5ee98c3cf96c27dfdfe1d0ea213780b369fa61f78a9c190c31fc2ad39e864e7dfd66ad88af76be7c26072c27f53d638be5b9f4507e95a272d2fa00	1678608090000000	1679212890000000	1742284890000000	1836892890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
119	\\x206d0896399338f64530d9893a9c9b81f5e3f58ff115e7ce310087a408aeed38cb2f49beeb1ac155e2e87718ca4f3d122448509fd149dcf0e0cd51bac1bac7e1	1	0	\\x000000010000000000800003a12d6007b9298a5b4a24c9ef801e1962539ebe6ca84bfe7aaf9d837521bc334058c0c4b4ae5e225b93c192f2cf98d0648b8c0814069aabb30fa94645340fcbf2f7fb8077cfe6dfd5fd1fe646d090722b0fa105304c0f00af47891e0ddd8b7653e907083f66597bc688c735be53ce7d376078f82b13bdf006c301820c250f874f010001	\\x8d457b70b56872c6c21d28604c5bf3a32c736749f459efec7b479d9442482e07e3b7f7e4b40d2985a33900a5ab5977fafb9d0ef424a5a9475658d84be15c3e06	1650801090000000	1651405890000000	1714477890000000	1809085890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
120	\\x22356fbd5959c06beabd50fdfb80dff512e38177d4e155b37a28399466347aa6d3dab6d1204f0819e28585c5cf197618a638967864cccb3272dcc5d6f0b0c08e	1	0	\\x000000010000000000800003dfdd0205a61bcb56a2a6e2054abdad6779f34a63268b6b56e6f0beb2aa46bbbbe49392e235740f29511670808eca228ba5d1ea6f3a0cff5cc0095f8b05055225e32c26f69c4718b3d995ce2568a9926d232b546062008e54228a2c3d05f5a36f7d69cd39ecb6aaebd488b802298180c03ea8322fc94a93a977e96869461dc6b9010001	\\x10f982184282aeb07b7c9620b22a219fe75abd4e1795c36e7a45020982ac3abd5e1949c3dd482935c8e2e8230dd53d8d3dbce3277785c672282962105a5a180a	1659264090000000	1659868890000000	1722940890000000	1817548890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
121	\\x2a9ddd5a9b84b8ac599b84bb9de83dc1d0719c03e03987988953b55ce86292f5c8e64b51e56f19600cb99a9b7483fc5af78ba23a39c061f37b3fe0ddc944504d	1	0	\\x000000010000000000800003e591946649a29c30a1192e3483e6029e80bc4385b69c81d7d9ea745edbb1ddce95d21e5bd6cba13c479146d92bab12be1f6e24dce55c680e0201e91415a5d2086ee6625c95a94d571871508fb56121ec71e9ed3ec8a1928c513b6b75efa93ee16030fa85939b08ce9528d7a30f2f18ae860f284dfa1f1b53a83a6ec2cc388cad010001	\\xbdedca514f97e7fe5405f552c4afa32688a027cbcd67ab73c7420ff8b8e5562f9d1f115732b3325e0d42459fcce0ca49787c93947a5f1709cc386404f455f20c	1658659590000000	1659264390000000	1722336390000000	1816944390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
122	\\x2d5d14b32448dddca8d029b250cc348fa9681587cabfa089a036961a3226303ebbf211a53aecae7d2c3ed99832cf3c585869eb6469ee62e335bd124ca6a4c3b2	1	0	\\x000000010000000000800003c74d00dcc19ecc909d623f1851e07cf731b18f02648ff6a24bc24b7af5ed3f545200c789001fd3c751764ce18b9741e16782ac4adbf53634ac7cdd475ff70a902363be4f283b8f316dba78ad173cf51421419a19737171a9bbf2caaf25153277871bce8d5b14a78553c5d1a6c73d194011c2caa4acf526f8fc2ba31793ade891010001	\\x3f680445fdf5a90dddcaf0234d7d682046151537bbe8f78eba0168b0b78e42d7f007294f85a00da507ce3114a8e1ddf2f5fe6966353aa73df2fb78a7d1730c06	1654428090000000	1655032890000000	1718104890000000	1812712890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
123	\\x333d348fa0cd69076ed6719fb1d7b7805fbb9a3ff73f0819d81b54affc2e8ccf2ceedd8435ff1190c1b083217b418d457522c00f3f73f99e042e9708a1c9d85f	1	0	\\x000000010000000000800003d210aa78aa6eb8a911bd14a26b4cb0cd310fa3a3b41647ed787413bf345ff5a673576f335b261908810d5ade8ec3d258577985968682d2eced58e193d3d42402680069abcc75932a602f288dc45be78b41786c55b5e858a324bdc767a2f5888e86455553f2627d325b02e0e02a27cca904f4c3063192e86390bd3985fa6e6bdd010001	\\x45c24cded20f6d2ba9c1803383d6681db0c656e9a6df4f813910e74f84ba627279ba1c237ea94204b10b6c076da6bef526ad98842ba5b27d2364a5540d79f800	1664704590000000	1665309390000000	1728381390000000	1822989390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
124	\\x35419aa9dda691abe4146967086b65cccc5613e6a967a9321c8a9ac12a6513d17f35bc56a28f0d6dd2c50664522a67f1d78c3b62d77e994a5856636e6ffc4da5	1	0	\\x000000010000000000800003ba680e0b8bc66832aa6db30b9ecae6c155b877abac1854bf774c793a22986f2748c261d2aa8dfbf1bfd38b59c355e4ff799aff19d68cd358d47186c88d9f61bcea5d3525f357f002db9ac1aff74abd95e3ff6b1251263d4179483b3889b3721eb8ad87c13ef0e50b89410e5bab84c4a796708f889cc526bc253a487b77c30e7b010001	\\x4306a90fb63154a609c19eee532a10ff6fce357b5901c44af248f47043ef08878abc367e339917129718b58c418ecc2b4ddc6718b11eea7c99d16c8fdc4cf105	1650801090000000	1651405890000000	1714477890000000	1809085890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
125	\\x36692216dc537582d9c3bd5ed97669fba26d238cabde9ff2147e6d7b83de16ccae7082ae0c894059164b5d4a6a4b9be93edb82f3c913e98b4747b6ffe9f93a4a	1	0	\\x000000010000000000800003ae2ecfe97d4093b7112e6f99eb5505c8438b496a8e4a87354cfdfeeb96d24e6e9df00dfd506dbf5d21d0275ea9f26d2112354c9ee6b109e9baa7356c65cfc56ee732f552a2cf6e85b0679f8e65873c9d27616c32707501766816f9f14068d7481b83aa0570e731d72f4d58671f453780df0537a5464c5d57ce34b33e57750d03010001	\\xecd4cea316c7edcbf8ac930af4d3f3a1b1931d5bd94bc22f40086ea7e7217eb8a87be850be9c4d59698647079120b6791d4a709ac61fa6b3c74766bc5247a50b	1673772090000000	1674376890000000	1737448890000000	1832056890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
126	\\x36b1330c9fe3d35530e534b20adac5bf98125982ea055310d679b81e91c4e5aec8eb7f7ce0cc81c6546b9996201330a1dff66869704791a0394b59fb6e2f08c9	1	0	\\x000000010000000000800003dbeae7fe9c4f836d382f4c9c08ffe803b40a673ccdf7de14bd2351cec079e8c014129cddd619d2efcd2e5c51d7ac79b05922eee84886bfd0674e1f640fb3b3c92394077a4e3c803da361913c0d5e227047386b097181c586fd9fd2b3275c164ce1db500ce0a2b9e25d347cce9a9d3388e3f58d1b6f27274601fd65f65c79fbe5010001	\\x9b32b612bbd79c1544e86d8b0abb7b8998b626974749cd91ec1ff59fdac3cd7a59d2d08f3ecb91133b717f15ac2c5544c9f432f620b58ab11bb446734352a80b	1668331590000000	1668936390000000	1732008390000000	1826616390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
127	\\x3981da43c9cce612a6adbfdfeb118e22da4ddcb2ed54ae5b52856564c2016d19994ec2088f80076d061138bf004a8aaab846d43a8c4ad1587ae2929f5f3d3d49	1	0	\\x000000010000000000800003e60b6c6743349623555d34397970db05b4fc2203bd23a1f6539657acf3139d72799e504ce40c05e7c4ae84ad8fcc1e83351062e90e10ba6d9fc3084ecc05200778f90323dfd73d81db0330655e023dd83bede313b04fa5ce2d329de783d49b69e273298977c08324a55f007aa755e108b7d2a5dc2fb59dddfb3d72787a8c5d11010001	\\xcdb1edafb2811abc086994bb4d5b5886edde79f66e32759ae5603e97079fc8658f3bba5c0865c22827098fdf78ef86eacf6b05388d74c17e0beed8e0d337dd01	1677399090000000	1678003890000000	1741075890000000	1835683890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
128	\\x3a3184688c6fcdbd3216e6d26a9cabc8e5ec9f7dab4a2d4b23db014da60dcb9dec1c839206bb5e518c9a618ddc17ab551813b8a81c9e6434d475352a2dbb8eda	1	0	\\x000000010000000000800003d6e246dcef5c2e35fc5d052ef90cce9bb2816fe201f03cf652e5d476ba8a5237e97ea4e410997c00cc281bf2859d9f1651e46b2cc2bc61d030818afa4530eb9e6ef278786ee5e290c54793bc6fa1bed4c391b1889e1c06b5e5ff77aeddeb0be683c4ebf9d776d4db5027ae61ba18b54e6ab99cff6c4710a40c47df5fd73a150f010001	\\x7ae807672f0906a0f9045e04107ddf454b126218f1e6aeae2f6f03f4e59bc6f43f94986710584ec5014018fbb1430ab8e49396a10f7b7eb52c7f65621785c003	1675585590000000	1676190390000000	1739262390000000	1833870390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
129	\\x3a81aead372e49e30411f11c7a21dea254234e0160976970f895ef128340996a442d4c240c1a3dd78d1144ab9e2b71383d0774777726817fb0d355b857f10556	1	0	\\x000000010000000000800003d30c4b74120b43fed647c9c4ede371abda02e2d961090895f82e49b8d8d11eab58bf07a9500ac280bda799f1af832461679e7c80ba377bc9d5157a3aa093f98b0417b1702539192fb99793f782a80ecc317612dc5b7dd6ae68d2a05c2c15ae1e865e3dfd1cbd40cee72af9677e3fcd0af95bf61d3964f6f079c611cbd47e7cb1010001	\\x0919bbbf66c284cc2a8622706693d1f4d72ab2173e8dfc54f189ecfc785faaff2eb58a1cae4f4529c72522055af9571033456bfc98ddf730678a409bb575a408	1679817090000000	1680421890000000	1743493890000000	1838101890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
130	\\x3d05a59b77292a16245581a120b07e1465e28d4205101cf889f7ce988fb3ea29c22593510b6cafc9d0237a6cce6918054035cad3f8f5286f909b946380f0c3ce	1	0	\\x000000010000000000800003c18142c631e7199287ca0d72fe810891351ac4aacdff46f920303b022bde65bf67da9be9df82aa047f233f5fc6e723c3783b56bfc1d4de17b9c6fe10cc0a9ecaecf964ce4394e2c0519e0a801fd48f8ca5a3dc1d3d4df1679f0ea792e27d76d27aeedfbaa23123bc9a661eb648066ab1ef3ad509b051b85e4120ede23b975c29010001	\\x6da704619ee656715593214ebed480f765d5af621cd087347fbf6da3eba78eac34a920579f4d31d35e82c6caade8b11dc7d1573d9f53ece9e420b75d9d5ca20b	1663495590000000	1664100390000000	1727172390000000	1821780390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
131	\\x3d4d0df257ea99b2efbb064a2e9cc0c609ca9aa120e71606050bf75888e72fa01ed1a2f4fbb98300b6e5b25ae6e1178bec99f559f7488a7099388d483e4b79c3	1	0	\\x000000010000000000800003d6ae524064a05d3cd2f6ca111afe28c2eb161ee1a3c7748d8acd2b642e69bd253c514aee38460cce304999380e8916b6fabde687744a21f20f9f9b15d813271a22ac79b8464dc3932c2143a658e68b89d265cfc441e1ddfb123302b5976698e202204629188a797be4fa6c482395a14e2c7c93ecb38162a81eef6c24a42d99ad010001	\\x7e50b7c19623d3406cd548530ca63be1822c3d87c09210120938aa8d2938ef093b2cd61e171cf9158e571374520d01d6a827640e8f528d78100ca8b7015dcd0f	1658659590000000	1659264390000000	1722336390000000	1816944390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
132	\\x3e1d862de87e0e96c79baecd59561aa37d879b420335752f8aacc3ca817b6ba7e6e04998f2654a6d792e921041b5e3e6369a108773e8cb364a7d2ec5c8235bb4	1	0	\\x000000010000000000800003ae94d23ee1ed718cee8273042f34222a540f8daba6ff9e406e55d6fffeb65d699b7e21fc85f01cb9f1224ff2bfafe0da40fcb6a235c024ac13892712f9d9598d59522530bf8baa523cbde53601b82dbaaaefadbd306162355c52067aaa281322aeb1b55079116cf95b906732ee86181e02e55e83214d1037538f61ff6b9d98a5010001	\\xd0b522076533ebde59f839255e041829fb2d7c53f2373561afb360b99bc41a5a200c8474e5bd4ae7d2ef128cfc3521f48fed79b61ce7c7a98bdc2dd173afb30e	1672563090000000	1673167890000000	1736239890000000	1830847890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
133	\\x40bd2ddc086aeb7ab9a31cfc96d48b2f97642893c39763eae3461d198cabaf613fad80b4cda29aad96eb15df52e3e94da5be9b19e24d0294cfe1ce84a741a297	1	0	\\x000000010000000000800003c6896cdc32f5df6bbaf0d131814b11d0dad1a671cab37650d898e34ad1861dcba347cd7961731cc7d6ee1d15d5f8edf9d6145d7da63ded812f7ba25d2906ee56966483e1747c72857fd2bec0c92fb2fe2f730fd16a2229c29d5c78c4aced98c20b79f90aabb7e4038198b428f0af55e872425c603917b3ce6f9b168b7f8c539d010001	\\x51dd94ca7dc1192b918149e863d097d409c7ea4061d5f9428cfb391c300f98e6eeeb0b74494ee92dc8695d7dec71712ad7a4abc7a968298eddfa8fe0069ba601	1658659590000000	1659264390000000	1722336390000000	1816944390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
134	\\x4045a9dec24bcee2aa6eef18df49377107d9d59654799b3c99be56ce06df5814adc532c292ada4b0ab14edfdd0a6751a4aad95774b8f8a2ea0a24f75c7f6267c	1	0	\\x000000010000000000800003bf21d6dc032c26f576600dcb3ca4a35e3a0cdc9cc4369c545378bd24f45096800171ad0cfa578e1162e576503f99660f7e78389305681dc594ed9cc912fe3ede4f9962bfc9535ae7a2ee421f8ed2166f399a7779639db98bed0c51a18871e7f08f176b33288f97aa09057f2a39fb8304be7c662eede47a637c95f07c26ebe051010001	\\x52b2efff2f62169a4d699446d94a1bb5007c24a23f4f46dda9432d71cb2c649410d7e929f9cd10f9baac67fdfc476dac83e9ec08b9c6f6f80879e40f17342300	1665913590000000	1666518390000000	1729590390000000	1824198390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
135	\\x42cd8a2f55672623ed4b5682f141c6fd11b75dacb30ccd5067a96c911f9676faace9f5fc6e2e66c457fad5e0782b48f44e60d0a57c4816f4c07ce38baefd3ebd	1	0	\\x000000010000000000800003daaf060c92af70d571317f451d3f6bc34c59e29e9009c0fb03577efc18a20649b7f4a6d300e659b1537ac9d73cd9197403bce50b26cbc39cd82391712a08e84f358447d9fae9bbc6f29abce11431cbc5cb1754a342c2339a80cb661018c9561044e75b088dd73604a4b0f9b33781474e08d93d6f91ab4cc3b690b32ccb79dad3010001	\\x4183eb108419424dd7510634abf03485ae3b56a7fcc97c55cb057f7b0ffe082b303b4b5a07047246a5ee4fc20dd86f267863cf28cb2e42050012e4130463e102	1676794590000000	1677399390000000	1740471390000000	1835079390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
136	\\x45018338f671d424688b5a9d07bef81f897dfe9358f1e0593689ef523f7d2f55e44eb7ff0a8beb39e3459f9d9cd03a63caaec9732085ffbbea5bb9545877e170	1	0	\\x000000010000000000800003b40ad1247aa6e709dd6dcd0209f11a55ff8d29bc820fc36b7245552a50ae0c730d2c41e864a7464197a60a5fc55dcdf70d24728cb9ac27a93b74c2cd8373eebbae839762d559df8b5e80441a4cd4d0c83b91ea48fecc098734b275d5cae9e02f5d2554f31cdda48d52e38ac4303fee269744d84f7d7c009f9b3848166be04585010001	\\xf60cce469119890167b8290894b095f00b27f725f2863e657bca8a91183db1a452c242f92d0a1d9dbdd6e94a9a8212f3f9448ada51641abcddcbc0fcfcf52b00	1678003590000000	1678608390000000	1741680390000000	1836288390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
137	\\x46d1b65b950b514982e7e620341cc614317620a2623707639b47a216919fb40441533e2ed9e15b7291db0644ae8aa229669898a8a9cb7990608b32fa0b29bc34	1	0	\\x000000010000000000800003e8bf046ac8b057de6c32c27e4803d50dfb25e0109d03d9299e38b40b7fc196fb930d35d9c141ea925a4cc42d25c7d9c7471f57154cd9d8e2d7816a4a887da5ea4855cdc5db867c68f8613003fed792578e1d85d72afee05f6bd8c573b226b83b6b042eae79cea2663e95147f8a7ef0fb3b7b8f18263a4175ddcafa64f3f550f7010001	\\xb57e5599bef19da45ae4d2a86c19195eaed2f2412bda1af5663542b973ce1ae41e91739959c057fca797a2ce4357a783bd04c53f55f1aaadbe958cbd47d7f40a	1679817090000000	1680421890000000	1743493890000000	1838101890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
138	\\x4bf94626a8db1d328bb4254d8c60c3c2575772f65d39777d15747efcc4a76f2c5a184d84653ce43cc2241263707b1df7de1f90d8c7e60a1b39d939bcd14cc4d7	1	0	\\x000000010000000000800003a2cc848daf059a6f41123d71439cd39b39867d9cf151acd581186e9275b032e9ccebae5e9654d0e5ed107cd3ea21fd478bc0f9dda37d89ff9be69b2365ace4effe15276f6834526cd27d798790e177bd99fe82ecffa8f202cf9ce57ead6a758731f3f2bcb13e98ceabd524ea1536cc99bce276bf27c0cfbe4a5792de9251428b010001	\\xc46289b7d68107ddf74cf3a4630548c2f2c58546771cc23be83cf7c86259beba3ebdc9d9297348d0317e74df44e35739fb0a219cbdddd75c15347f2f53dd570a	1673167590000000	1673772390000000	1736844390000000	1831452390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
139	\\x4f9d6db7aef29922b4e45e07ce3fff66c0950c9778add2021519d1579f6a68c31e03b7192dce1912910541a2aaf14b72fc61067feef84fc7189cabae23e54a14	1	0	\\x0000000100000000008000039cdadfefe3ad40907737d6b6301a6e2e38eb3627101cda8295df807a6809531cb84daa472c051c6779d4b4c2407dd7c606af1ecea715fb086e817c4f614f6e0401d153bf77a80535467900596b74ffe490bb7f2e7ad444fa888e105dcc7420b7fe1000a73c44fb63198569ad327a9b51e39a438ef654f3b8be5104df75c3a851010001	\\x512ff79179168ab6dcf209df802ae1044b76c4d695dc0d662bca610148df046129b2ae4d16bda52e5917287da1668da27f5877f37b17cc3928a8d40c17419a03	1668936090000000	1669540890000000	1732612890000000	1827220890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
140	\\x4ff9be8c41ba7b6c524ef0c667210c53c55a7e571f64a562a86d1a546e30bb6199fc9a63dc9b562042962fffaf4b2ca43d89d054a83c02bca930341e8fcae298	1	0	\\x000000010000000000800003a94f8dec399028f90eb267565b54a82eb0a46e7d04f1ec06a5dfffb62eeba42b74f427f6251974c2cc466cd98e2e187ef6e204145882db064f9da2224f024456dead047680663cdb921fef50450a5efba07b643f21ff9f68cd0cedf0c87b7d40a81fa018996ecf2fb0e7be523351712ad636cac361c092f8da3a8c5d9b50bcbd010001	\\x8dd70fed54511c06ad2cbc869d80ce38ec073a921ad551c6c1e8d41dfcf70c04ce027f0de5dcd2cb9bcf35ab2aceaa1e50b716df8a7434041bab9e30b9cc4403	1662891090000000	1663495890000000	1726567890000000	1821175890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
141	\\x51511c0109bcee199e42a0eabc8f0a46d3bab5181cd534aec058fab80d611e8d118979bca54b26d3cd7ed4defca1708fa71581edf4e744b5be244b9edcde7e9c	1	0	\\x000000010000000000800003a3f9fb7adc85e1fa1cd0a08ba83ccfa36e7996c61cbc65da20bcacb33877849745ecfdcbff32c13dd8e6c294a5be4ecc25d8d15a4873a5a68f4f39e46b9fa40be476e4a63a393230a9b6f2308a5ee3507657f0e806af238542591d265acc2f8664be6fcfcece8ddfb63ee7805e7cef2313819d99901f4efc2562618ae07e5d85010001	\\x5fd20aa8a1b614393b89701db1268d4e5f1591c237c95ec5ee8c6d38566bc8871b081112a837b01bd88c3c83e317cc5f978434081fb2662ff394c9845f6b7503	1656241590000000	1656846390000000	1719918390000000	1814526390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
142	\\x59f989cac83d0ecac108ba2fbf89d9b57d79392a671e98b2fa122ee8479076fbf263e313e2d3ff51ca78fd0e9c52595bf572ded75ed320a7b2e9e3906cf59246	1	0	\\x000000010000000000800003bb045adac30f122a47b6583b1f54cba1082d5a0fd9aa2e2039846e1246f1b097bb31d87f4ab6818529a2222b3392cb09c58ab833c29b5efdf7c229b7cddd903a7c6c68999eb11918911ef665a99ef739a2f150569ec79f8392101988c86ddab2f019d3f1d6a14de52b249e4b5715f191d1e64eb520b671de410e29bb61ca271b010001	\\x2caab64e21b0f1ebc7141546d9fc8e3c7f82b7de8b1dfdc59121f1d8adad50c568aea9678782ac594c1d85a15530b467365ae42895285dfb37c6f828756bfd04	1665913590000000	1666518390000000	1729590390000000	1824198390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
143	\\x5cf10b56b6bb41a77ad0b1618e60a6c2f6c855803151ddf910dc6e791500e2447a90dfe8275c3d49922ddfbd5e115a727bc90f7389a124ca9eb4ca68b0a5d5b3	1	0	\\x000000010000000000800003c501a63951d2c9f1af9918cba4f6a513499c09605753fd7c099d668110a4950f36f659d99987fe7015be35a57da5d23b435786c088e85909421e1eb17dbd4077d3a4043db1ac7800405d263c840d473399bcc2cf7b0f6fc31156b82c4ba1cc9bff475d3bec5c720236b0ac64acd25dde0b1bd04ac0d07affdcfab93584405909010001	\\x9d7b5a3608ba84f306aa4bca097202b7bac1b085a7970d167b7c5414461a1d699ad4198e3603124376f787872a9c9c742a6ce9aa3b92d1dcc1c7c904eab57c00	1653219090000000	1653823890000000	1716895890000000	1811503890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
144	\\x5c0589678cec697a03cf2187ce229978462c19e53cbae7f5e4dcfb4cac74cb411c68fde1ad155270f6658ad32872ea2d8b3b449bbb8e7eaaa369da9694aef537	1	0	\\x0000000100000000008000039ca433764c19c1e2781c7d9158dbc6e9bbeca9d1c97c5b770eacb1651abff97e9ae2bff00356766d2526cd8c33e4a2fc94bbb40efd6dc2380cbd39699d4cbf86cd6eaf117f9952d72ad1b68ebd838c5c70d7d6956c35533546132e19691d9b765fb532e399f39ad1a1cdc412ae9bcbb3cf916ae1cb476c1d88905eeb8c7129c3010001	\\xd44767bd30c3f9205b075594b1ad88bf30bcdafb4889d33c2aec9846456242810539926ebf17c40b2fa981ba8b760e5482a7d1a163e88a63c39a3e30cfe47400	1668936090000000	1669540890000000	1732612890000000	1827220890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
145	\\x5f013d4b638a5751b10924f21f43155947e5b37f0e80d85180df7fa112e7405124ce573da4391cb296f7ba933589a5ba2817059916efdd734c014ec769ce862a	1	0	\\x000000010000000000800003be3da9ed4271fa43211ee3e8a3f5e56d9fc53bf82c24ed9bba2da7401a181f60ec9f82e27ffa7ab4463056c116f5eea6748d160b84c0e2691add39de3cfa4ec1db66eb1ef377ad18ae3a2967d9a2521ac509a0f164571067c479b1a4a0998ae09e10fc14335f010d0e51ce7fe1cc9f7ce5c4187b205f4e65145c1aeee720306b010001	\\x3173771f77da9101b08ceddaf63a8ff5e5903d4a86d184611a32bfa718a01ac8214fa50a43c20319bcb9e5eea7795c3b4712d745c58cd23b6c40c65a5ba5e00e	1664100090000000	1664704890000000	1727776890000000	1822384890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
146	\\x6369281c4837bc948a52ec290c0ca34351838341cddc7106de9134e7cb6e3fc9a251ea91df59cbeb15b7831383199890d3ccd6ea9de9b5310d7b349f18142c63	1	0	\\x000000010000000000800003bdbd9f62e16296a2f64bbd17eab26d9fa7dd93c171ab8dcb7e8055b8dee0d565e88e8a00fcfe250e036601bbc46209b68b22d55b4cdf41163fc56789ea560c20c1a417c381b7c7d631505287a0bd8d0c3e34515b4cf9b6aaca6cf18c4e206586f1f6e577d6ea27e88b92ac44287a81d33bccbc6b3606408c15079a58948245fb010001	\\xb500a88d0aa26055dfc6173056d9efbdf5c2077904f6b79c081dcd4779b235a0a7d7f4e029727516b80acdd7de8a7c388bc8705615333d97d3ed0f76467d3301	1659868590000000	1660473390000000	1723545390000000	1818153390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
147	\\x67c9136e195efd5afe29fe7e379c634653ceae9f4d990292bc755c48f2d1a2ea0cbff5516e304d142f94566280ffc949c7b815e5e094865dc590bc6d907ded74	1	0	\\x000000010000000000800003c24a13246a41db8b605d10f5741f6eaffeadb10f74c1751329b96a6e9e4ae07b15789ff4978e35b15223b936fa9e8c4e419b324305407e2306d6c0832edba8d505dbaeb816a7c1f482833cb778e564be57e63ad8bd0a1428cb3828ffae0b2a246cc8c6431e62e8f3eef0e27850d2e01f623a018d904494dfb6eefccd51a92cf7010001	\\x38ff6627dd8c5c902307b023282ae12f408490f7be019f21f48068a92ec8b4969437d9434e7d6ee05cd84d99e9aa5a629c4df58c81b723d09b472b5fadc15d07	1678003590000000	1678608390000000	1741680390000000	1836288390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
148	\\x68698b460eed5805de43ddf67ffdbd1dc292845089dfc211a1c44d175b5dee019d87dfbfc29e01054ed26e1c81de388d3aa9ccc750e76250b4adf091105cbc55	1	0	\\x000000010000000000800003b8c526b442e0b6714a66dffba3097ae0af395999117f80f0e176d49d88a9a57f3a4e9b7b798e9744daf58d13252c1741aa449d49a078b18850bd91a5e9aaaa093eb29176bc23bc9046450f89fd37d329dfe8846b1013715d2b3748206549e9970884a1b6a5bd8d803bd873026df253afbdfd9d4788c5f46ec575a2c8f23a3b79010001	\\x1683c2116bd258402054e4be6f8e4521a90182fde6d0329d23b323ea8cf0a4106c65e73fe1d0236cdf4d25f9e8ce504cfb6a1df1dad08c0297ffcb351f6b0207	1650801090000000	1651405890000000	1714477890000000	1809085890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
149	\\x6829954588db55ae78d5b6a3dd5b4c4e36c3bf2e9231f5113deb830cf3abbf73ca328a0c7992b21233808cafa8ed7077297978da101b098da414e212ec1b2e2d	1	0	\\x000000010000000000800003bbf0d6a732eaeaf482de1c9ed7aede38f5e801c867110e32c1242154cba9be29d1a635d1eca6568832f3b86cc08f1ca1abe95c0c07640801dcf1311c2adea88f5e76d7efd45771813ccd4629b3d643c3d46841a50df1d3e80568d7e49a5ccbd33308905b870ec6a19e41697ae0fa7557796a2fc38ef283b3095dde523005daf5010001	\\xce6b0f52063fa4a5e1eb8b10f900bf9acb9fe6e0ae8f681c3fcbc9908df97246a51bffbfd61752a6419d916d8aa09ab0f233d010c84ac98fd0e3fa67fde0fd03	1661077590000000	1661682390000000	1724754390000000	1819362390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
150	\\x6cd9f45874a9eb49835ec36ee8f7e01f224d416612a91936b42aeb7560587270530c53e2f451c386dd1fe9114c500feefa0bf24df39b88b0802ec819b488513d	1	0	\\x000000010000000000800003b87236814cd91a6d60c53fc7239e05012b24b9a81efb241a25c25972395c874f9a3834de3a95560547b5c2269094e2ed4d957817f6b1e2c68f6cc39107f47edb126dca449bac337b37cb871d392c82c858963b3a617f08d122d47253ed068e5f8e6db6738a70486fc51ac429f8105c919839687f8e696333074d564a79116c91010001	\\x51d991f376ba90202531c89b5d16d64cddaa3d7b14fcf983f94dc65b29cc819735797321c0a516fe756a76f1e3acf22e1b38142d9c193d55b51635ee0eb56805	1661682090000000	1662286890000000	1725358890000000	1819966890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
151	\\x6e69dbb83e56b32a63f9b65a2d3f0052dd2d18361d378dace8744bd7e33646e109ecaa54811f333ecdbb747b6117a62d489d3012d519af17577e32a133560ce8	1	0	\\x000000010000000000800003baca2146fb6e9dc7c8c4f30860e87f4a1dfd090b8cae454bcf4ccfa3f6395e7491c997f292010af88f1409495c29f5f8ccf8cfa29e8824d0df0ba509d7314605f27789ec9b5b694abcc075c616809f99547942abfea9d007188d41bdbe02b0c9543d04a231733784348259d3e6d5e778a915c1e10afe7290a39e56222e67ee39010001	\\xac5c7e1fb9d9ecb7ea6e7e6c79b4f2534504e2503d9e5909b3e324851bf611f4012cae4ae91e3110c840e3c999b6f5c8d0c725b98b8840d0b85fecd53182530d	1669540590000000	1670145390000000	1733217390000000	1827825390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
152	\\x7a51d83a8b45125c133065ad58931b8e8e334f242324fabfc8e0f4994a9975938ba05c0c312afe471997b45edcb45cefb971af5f9f764470317bcb74cc345af9	1	0	\\x000000010000000000800003f5db483f044d774d1423dae7c642add4c4330412f79cf4f735010d2d1c586223ce33a7a1af6640fcd4d74a0345bc88387860e23ec06c2bd30c18a06eb60c521e607a2720b3fd1592bc3d24462eabd172ab35ff8fd0d35f055eb571fa0d6860951e082334db7eead0f6dd4ba79557ac6b16416b2871592a05512f04b8f36f1583010001	\\xbf8e00f1b958f886892d5c570161b034aea7e7bb6e0d0fead8b113288d5945cb26f812e32a2ae88e633f05348caf67386430382998a6fd336cf5b7eabef5ec0f	1665913590000000	1666518390000000	1729590390000000	1824198390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
153	\\x7ff91de63f4fbf4ff6da61a87c80473321d2652fe9c85df191b41587ee234c4bcdeda52b4188945d313dbed2dfb1cbc582299a9492f8a37caad65bfe4c911360	1	0	\\x000000010000000000800003d66c193cebe392fd51729d652a36b76e2435fd79e6b01a765377cb201774e485d4b5bad8d098d02541e10547400c3626e63c524e464bbabed0f0fd879cddc78754c974b5afb3304845da4321d45257b23a8c340ca4dfa28e268b789a1405d6546eed7963ec8805fcb23b8468de277b72a0e2d2ce89dffa4913350deb1e61a38f010001	\\xcc5121c32cf23f2c4922159c963b01c0c2177fbf6e5dc384fc39b986b4a313ffea79e3b1479a0dbb62b4e08e35ccb42b832c2d7366c2e49e1383955e5fa0a80d	1671354090000000	1671958890000000	1735030890000000	1829638890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
154	\\x8055e03f4668599a7d8ea387dc462639f62a34580d23795e7ab91af93542002abcb3a000f40fdfdf3e83d3b90aa6d309c7c446f7006261d569b15690e0b75965	1	0	\\x000000010000000000800003aaaa10273a1295b969af631bfbb70b8a4593a050b78d7de7214dcb23584855f7396fb60244632b20a36be015808fbac25e8945763aeaef21e604102b1ad21853b2937e525da3fb3892c1b2197806d84f96a0c9cb61785651c8a1d13672a80f6ef6e8ee0e80a7c575938643e6ade3823b33cdeb6ab81b143c37437c4ab92d54bd010001	\\x8dbf4b3ccbecae1c4f332dbd4923c9f786ffbb69ae6990958eafccae8d9b0b6f397219c7e97822dccff977ddcb9f66cd54123d76d7b622e15ea68ea58d791003	1653823590000000	1654428390000000	1717500390000000	1812108390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
155	\\x81dd4f8bbe61bcbdfcdaca27290f354c15922d74f0668cac70038b091d67d16aabd2ec22dd6a4b03ae7d435b079171987ea95c14a908f1ea3eb26178d34dc51b	1	0	\\x000000010000000000800003a62ef9a9df79623b21e8db004c05d82217ed2cdcd3940831b0e669efd114fb918aaff0649bd8dbf149a9f4ef64380e4110507913a703839eace015d21c82a434430e638e2c080d2b8ef9ecd758a63489ba9481618798e1bbe74d3174bfd44708e38aea2cd22ae7b32679a979fe9c03bfcaf4847b6ef0a3a1caee5d9f9b29326b010001	\\xd5f0043a4c264adcc2a989f24e65f1ab496275b1ca716e36e9f03ee56e55ccf692d333568e931b83342db39f0f9ba686d7271a9f38c9c5e7e02d6d916204cf0b	1660473090000000	1661077890000000	1724149890000000	1818757890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
156	\\x8311e208a15385d4cae5e2b5d774d6c98845eb24ec35a523fa2c69bde7b5a7467cda6d87652f90db77428c481c45bdef25cbd3d0c5501ecff147b85ad73a6f4a	1	0	\\x000000010000000000800003e62bbf499c4aae1963c47b8a9df3667a93e14833e0af4d71b955bc7406b5670f0fcc1692bba8c0449ca19edc2bef599a825f2cb621994821cf2b1bdaef57cf7365b9bfda24d055f3f077925f6a969e6ffb3c51b91c4a05abbdebbbcb7c426f486350f242d9df0e5047704afb8b034f3b246af25b0264d0e96d99384f7ce9337f010001	\\xed763784d9e974f4386faff106df110a968a7a7ee190cbd4128679fb0eaf978a95bc8a38f322c44c64a892f7ae2e33f8f14992bd970edbe1e33dd2e56dd0e405	1668936090000000	1669540890000000	1732612890000000	1827220890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
157	\\x83a99f362e2ddf17baec9e197dab25dad57057e4c2a024c150c942faab3fd1ac68d479708e91afa0412f464af17b92b0c68afd9882fdfcf7f4757bde90ec5783	1	0	\\x000000010000000000800003ad48632c3c27ad4089056d632c2699e1a86b8a89e2a62c84e8a03be001ca5231e0cc769b4da88a8222a8deb313518f89c0d00187eb16dd2387a4429d190a64eb9df3da8ba79e4ce31dbe2c46265bf3d60d68b7b3b72d9e0613adc3c47533e6e9c9f2105c983c6c13c366941daad95f25565a8d1e383cbe2923d521fb54e0f50d010001	\\x76e76d6c515abd9bda55ded270df4c21594301c0cbccfd3884b84d59e664ddb850e947d0c9933f77367a128c5b3984516aa6630a43ceeba2068c7aca030c6a0c	1674981090000000	1675585890000000	1738657890000000	1833265890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
158	\\x83c13e7de7e95bef35b139cda8c44a78f13087dbfda5993f889c2e8881c3fdbf158669f716f29d9ca15320a70ee799f205f9a7e4d4d323038b5575fc6641fc0c	1	0	\\x000000010000000000800003f484b79aef9eed77936c77b2e7cd6d7f1468a9afc72c5b129c83a6ce478c36ec7aa68e036fa9141078b3fd4ee9ec81dbbe404b754b62658ef86565fbcd753037e3c8feaf179ed3e061329cdf2c7cc9012ebe8031e78b92d7c6f7d5f1b5eed8f80762682122b1fd7124b85a0441ee8a312dad8ea15ca3d51006b1f6be91965a09010001	\\x8348a1c7366dc3238c773fae644bd7be05067e4716eab121f8304ea490ef52b426258a487b73ac5138f11de922b98773f4782c1ac15278c31e635a7d7add4802	1651405590000000	1652010390000000	1715082390000000	1809690390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
159	\\x875d9f22325f917fe87a5f029137a49f723e33f081d070dc4c7dc80114b60aa30a6def0e6de5f69f74a1e8e066b6fcf6600109a27136211820c8145472dc459e	1	0	\\x000000010000000000800003ccda13b4574c3c3c9f8ab72d9206bc2be5c31974efbbbf33274aac77e5a9c5d9034722b3ecf15015bf1caa7bc6f942b43f0ff661ef4d6e111ec53a6a5bf52fa440f84970a8f2ce73b5dec2d88a371f1705ccc1b4926f19fbf2d1c1ac9055497ade3e30a0503db7f093502aca39edee8c84c1add8ed8660e57e791d1d0eb6c5ab010001	\\xa6ddbf568dd7453a55b21b6a4a6f2aa07de97a2f8b15db98d87fea155f35ea1232d559754d01a9ef67c1daab580e0542ba40a73d71328104e151d8df85972200	1668936090000000	1669540890000000	1732612890000000	1827220890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
160	\\x87018c83dd1d88e1ae9acb25b74207663dd08926fc1aa2acd237ac6b788af467dd3d92038074f8ff95258af1e2eb011e733293083ed3d3ecf6452d4bd5465293	1	0	\\x000000010000000000800003ee7ed92a6aa6fc9cb0e27d84be33d95117010076a6b8b81ad2b76e3757ce30221028fc9da4e355fe322aba46846552f25f7dd9b339edecfdd39147b8ecf59c76339c50437d6e7cfd63cd90e1e0dea2aaf9150ef0e4e838b7b8a93a92eb1c988840e5698917a0206f4f4efa80082b3919d25f9128f2ce6c69ced60bcf41925803010001	\\x13ad897610fbb36095c3f8f7dcd952e5e93b570132605564c3a5aa548937f19c164338df1315114e436c69c93c791716b7c6e3f6a72b70f2923f7b8351406907	1667122590000000	1667727390000000	1730799390000000	1825407390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
161	\\x8b25f42520bce847cdd303c339b20a0d79cc80a4fc08b038fc20bb45f5f1bb6d09c5653155d791e45a3270f777438e133c6de25deb2216a49d9603d531efc416	1	0	\\x000000010000000000800003c839d9aa10cfa98a64632cbd504822894dbcc83008170dd4078446c5478a82bf764f6db9111d0c65c2485e8613d44c91b720e8abe55e0929bacc16428bb633b92a783dd7703163c5645af7c86a9a3bf0e521a72bb5ec729b12f9c5177da3f08404097b4bac9907d8cec395d390c112d09851314256fd933de2834b5f2ae23405010001	\\xd35c10d69e92bcd819b500ae96a6dd1a6a1a520789f13ab1cab9ec65d26b6c3b54b175d7fb5e2cec486461c95041c92ffca68b30c5e7b1cd04fc49e34592df08	1655032590000000	1655637390000000	1718709390000000	1813317390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
162	\\x9019677d86004e7c0b7ae8614f873d1d5456e4c2d7152450e5d2da9480b6d9ff2b8707bc62d78f038ea5c20499c054672f8e1abb1eb4885e6e8bc97302022df8	1	0	\\x000000010000000000800003c6540a5b2624afc13a9989d017dbb4671ee0bba8b32a84184318c2718050e3eabfbe83376c70a767753537a088727c07539c5421db9c959800bd308bcefac06145915f72ee32a2aacf137fde9eb9c52e591a4a6b019961f7672a5d359722d3a5f10650b2b539b5bb7138e42d42fb2f3de41b596515d3d8dcdc7f0e8a68f1ba2f010001	\\x5d6d15928287825445a7c5c11fb25dcab1513bb9525f5fb31dc546f138ffb30e2d8b715cc5a5244a9239979fc2846772123727395920bd17041b2e8e4d532e01	1656846090000000	1657450890000000	1720522890000000	1815130890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
163	\\x924de50f27a9e318713dd02984248c137f19ab27a6481364b494c2052b3376f84e247c34e2b38a22d4433a456946a21e2b445191bd946619d9daebf4c711085a	1	0	\\x000000010000000000800003ceab4a99faae542dc995cedf29ac1336a83ff5861cc8509f5d9bfdaa1da4fc049ab4d9fcb8efb4c5ec0e0280b59c01fee7d74e0da36dabb16945bf3a630d60cded8bd9c3002efdc1bbb4e908693418f1a424db536a63045fe9ff9ada940c48ec57044ac8056c9bfdf91a3dc61bb216fbbe3e798d93254f1d24627e6ffed8c263010001	\\x8f4dac02cef33d3600ff222cbc59689e8ed9ee5e849b3882530e4fdaa538133721dc713eb79862a0e60e40a16afce0ef3732f5ae96957775535bf653a0719d03	1668936090000000	1669540890000000	1732612890000000	1827220890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
164	\\x93f9e2bdc565637b6215f217f7b85474fd2a4f9e90f984578a54d995b0d4a7efe4ba032b9efef8f121f606b9c5f03d5b03ab8f9334b886377ba089d250956293	1	0	\\x000000010000000000800003d38f53e6613dc77b913d690566dbe4ee4871b5a443c23a67ac53b1f594a0d6f8a3cf393e0cec1fcaac88792d47bd2e93076477dffee9218dd79b053c4a1c858bb2d98885ccfe790bc2bb154c51a712a984c653cad9ee0506eb5ea58f713fd522f9edbe2571cae9d78336752a19ec0a7b2abfc89092f4fe6da7f6eade305387f9010001	\\x22f82909baa01b483b0a43209ce5edc6912544855de3502bf638e18b99c29c8eb163c9b0892417f99b563144568b2151f2d5d79d66c83114cde2fa2a2c698f0a	1649592090000000	1650196890000000	1713268890000000	1807876890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
165	\\x93bde932aa411423c4d81d1ee225e11ee42894786d1eff738a4073842dd4dc149ca4687a1199dbeb44a7c42ac75689e7956456d50eda6be238d6f5ef1c636186	1	0	\\x000000010000000000800003c23bdefbabcaa495faa7311dba2ef511a70b2980e89cbdab37c229320d4ae712ce262ea3bccd651ea0835afcb3c40651c5c5bc3cd5ffcbc88f293cdd1f85742ebdcea047d83da27e11c54267234b1ffb23f93e6d25adccc4128c53a6ba32bd88c56ee628eac973643cf07e8eefc2cb43d15830447e08156f79d3640d0016bb5b010001	\\x6d0ee191c293fb2f945093c9198cb64af989919d244b128d4a33c240d15d4493eff26666693d164a40435f26769c9899bad524da778358a313e42df543e74f0e	1653219090000000	1653823890000000	1716895890000000	1811503890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
166	\\x94f9e3ccfe86cadaaa29c13cb348f21c40c882aa8bcf5ba83023b0ce50f44fd462edca5a5b545a5f7e15e5aa2c825816bf0c1ef61ffa6e553b9a02a3be8b3e0b	1	0	\\x000000010000000000800003c374b0cc6d10e08d7ae0965ff862c0b5de9cd04ff3d48fdbe0ddf7cccd89662a92c40b2eea9e2e30d1257896a392d0a65da9cb9a8b4e17de31774220af6ae2d5892adae7f83d4321045a9edb4d3b170425de779138d997b00ecbff3d9adc3d866a3d6ca087bd06ccfdf2445e7fda96c454ad5b2e557e97866db4da9dfa2ee53b010001	\\xd466f3b98e66dd30262189b2c0ff959aa1ada2a9a1be21ae60fb75f437322dc79ce1e5595a1dc4ced7dc9d0e8582ec4a8cdcf83996e6c9360c6c49fc23c5d10d	1671958590000000	1672563390000000	1735635390000000	1830243390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
167	\\x9451d09cf046e514166f23355f740dde155b8754126d695e6aeba82a1864c2a8af7122b253afb29a7b601648c2e7afd78f5be0f2a6fb5b744b9ecb0b6e3fc684	1	0	\\x000000010000000000800003a5cc05d9737fc22e7fa15d9861764deac3536efd7afd5e0fa09474a1a1f1dfb52d926cb130569b70d1190d256ae39a3202c8c413c53af83ee8441539342553f52c53c2b3778f77ff24c2c8cb453e5286098f36fe0def80e1c3dc3d26dd1dd421b0019fd7e82112972d8f1369735f8faea2a0da7af7210dd7c182b7840e6f3a73010001	\\x701c8c38692d9d5a9e29b7b7665358fc75181610a8f9a3fdc1c6f684cb75132b80d5e0aa45dba620a6892a5bc64c1c5e90d146cc2e92b00435660d5f61909f05	1677399090000000	1678003890000000	1741075890000000	1835683890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
168	\\x94b55c150bc6c4a64f2df627eb8d39f2170c48b6a79e0ae691ba8aa1c99c7271bffe2a4b324fdac11e5e9cf5ebd81f37888cf6dd5979c52233a301449e7fadd7	1	0	\\x000000010000000000800003abe5305957fbb472c757eb5e809119882b61b55a81decf4eaebdc998bc77a5fbf148ebdca406f403502cab4f49416ae381f626a52c227ea70f006c9c0d9b648a57687b87c8ba53fcbf1f8ad0c3e07fea99cbf999aa3937bb33b46af7d549c22b1ebb9d3c2192614542062bc74d267eeb6dcb724164d92b00462062a6db8efb37010001	\\xde9e98caeb8f2b65f982509ac9d5453a2919192de8b826fafa2a1dabfb9f6d75fc606b0c4f64649b798921810d9864568ea33f0233124efde58517f39c558306	1676794590000000	1677399390000000	1740471390000000	1835079390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
169	\\x94d14ae01a5f25c6542f9c5789340ff8db28b400c864c78fb61bc24b0d83f84a82e3f11027b134f53f16efe40ba168e7737ef74ac9c8a23b557d7ddced166c14	1	0	\\x000000010000000000800003c2270305b9816d9561ab1d25ecc555bbcdcbf95da3051b00a598dbe52787ea60895c5cfc964caa54ebff32d44444c90b7e780fbe44441027ccd654de8d53d9da9027f4f79e1fd50adfc697c59c799469a9c99cec05684f3358c2f3f03c185a30fa60fecec494188334d4ad2957e116a647a1e927063d739e73a6bfe83fcab2eb010001	\\x1becb122581862095a7b49d39616cc4061efe2da46cbeb3ed2e0f6f7749bedc0d7ed92fbab0f7b1af41126dac643f5c53586c7831567bbc1f61b946b6a780700	1674981090000000	1675585890000000	1738657890000000	1833265890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
170	\\x9ed1874de1645b6c1cecea794abdaf16d0c9004db4d679c689547a2735e3445f075a3b79368fdae43e4acae9d91c93bda9e2a8d7c1dc7bb1f8db51143c0065c5	1	0	\\x000000010000000000800003e21707a71fefeab52b57a206f9eace8b9f919d5596fd7d6b0b4dc6f4b959d82e922e8d13b0a41f239baaa4e53b52514a5b8998c0f5bad48edff9e1f90b3b5fc3f99b331b15ac2cbee945d6a67e77a7806a2c1ecf5643819415cb9a1257a7e69dc617bfa23584ea9c521eb9c8e9139b435060ecd7eb6c8b3c2141548dbbbc6393010001	\\x4167190f537fea432774ecb152860d1afad9c6ec0209c4a5faffc236a4ba3d4cb354bb6464bb6b5724a454d8b384c890204a803e9f0e9b1db41d023be94b2d0c	1679817090000000	1680421890000000	1743493890000000	1838101890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
171	\\xa6a50b83e420a38760df46991a9e39463522303ab4c3ffe95455b210e3073d27fa95e228532b03c74407664d9fe521e3e00789965a1af1b359be266b8b824c99	1	0	\\x000000010000000000800003c07980fc7b00ece6608d909dcad2069b5713612cea313151873bca9f3105da5245453832e6b684e5d0e92e0819668c325b936822a7ef6104e2b0bed08d95d73ac4e35e0228b10aa822dbdf6afd5a41a2f0606d40e7ce19d3e3a9f2a08e444e39db13ef6830ae25b1d203a5064ea1cd175268caef298dd2b3d4c705d030be2263010001	\\xc8c277fb0572a0826d8698304440cb4469cb50ca6077a4e181d0427bcf8bbf83c5765cc0c8d548962004db3418d526192c2fb52b7ec309f6bebce8719c4db500	1664704590000000	1665309390000000	1728381390000000	1822989390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
172	\\xa71daa651007f2ab106ec03b0baacc12f993745aeee07d12005390893ec5871cbf4d5178922dc8d33b4ce43525dab4c1b423fea89e8d74207b09617d2f386c20	1	0	\\x000000010000000000800003e75c2915c7325b06107ec56a09a1569b04802d0aa31cc9578153179f8e80a6a17cef593f6672ba9aab85fa0ec9ad7561cfd2e7659d5ce4fb823929bcef7e88f59cf01cf5c4ac40b7dac4caf314952bb9e8df83fbf69329c936c50144a0ecc837ece7efd3d5b76475c6b700ee68e0e8fb32fe6c670d236dea368730d77b4fb66b010001	\\x6176c6575a9b700f9c14f1e465e3172f14a1b360ec4ac06d266e244baef987336b20d3f31da0fe50981721a617166e39a4ed59ee328bb5c8b5ee694d826acb0f	1651405590000000	1652010390000000	1715082390000000	1809690390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
173	\\xab5d7cc0e25969b1ff459e941af5d78bdd9da66572afdaf9c18a3985d1229df712f97df0d350d6d72ffcab3c763285614bc4ff77c16bba2c1c3a579dcb5a68f1	1	0	\\x000000010000000000800003b7d5941cb8dc0ff4b28ac09a3f773c8e24b56e226b21f74abfe0b6ecd84ba3a07d1670a942d6914ee769229d4af33905d09d23b12fe02da802e680525b9f280c951f2d2b67350818433f1ead01456e371cd7914bcd84a804febe3a11711738679e5daa193b7464f4460c41a2dedab8fbfa11ccdf45e5f7e47cab8c1d3e899fcf010001	\\x0082fc6ecb05f47c49166e591d7c2772b5ec2efd519b60c91c72c2d3a14d5852471b3ca2e58e6350595b35764b4c6e6eb2efc02b40bb43ed43896ffef903400e	1659264090000000	1659868890000000	1722940890000000	1817548890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
174	\\xaced56242184c0cc2c87cf6d054d2a81eb51ae2c3ac8eb9efcc5231dec89f73e3eca98f08943798b6fbf2a8c6697471558fc0c0fca373f0fe680a972dea1c691	1	0	\\x000000010000000000800003b624ad48e748c32f5c268d1c244816815ba43cd495905bae248afcfd3293d46da22c733467d45724df66c96fbc4be03f98a8d418dc1ffe0d54ea17f4bc4205a05a6328834284d78ea185acf317c5ffd02df2a56e22005c091b52b4df1a17f46fb9bac9f93ce074d08251d50df7e29dfdb335ff70a876f44d507428b8b808c85b010001	\\x583e0a7abfe2a52467e34b76c154ac3c392b2e8b65883fa6f2be21cffd79f487acc73af151b38dd73cae2b22e7802b4bd7453ca5122ffe938bae6995a8ab250b	1656241590000000	1656846390000000	1719918390000000	1814526390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
175	\\xac4d92259fbff2957bbc4188722d69f141c77fd0c31944c8e525267aea41299f8775bdac7b6b9d6f2df4b10537e01351cd28a0eaf17265cef6ddc370a9d5900f	1	0	\\x000000010000000000800003bf5d579d05c25eaf4c2823f4f7c8eaf67a49c23eb54385b914d60132605ab6a0d56ac9de31b471be88f53793033a72c7389c50f3d02245c5f2f95bbdbcc13888e75eab071aa07e738bc30cfc4da0d9b5813eda2c8c859af53f69a37756542680fb3acfd6c9a8361fd2f063fd5e2edbc05d5a589dcd7e98eafcef67aa5189d569010001	\\x86e3b695547f952b348506513986629b171f246b855c2a2f22c41f0bdeae1e3210e88981e93e01bfaaba797873716636e50ae2d38240c485b12630d3443c670d	1658055090000000	1658659890000000	1721731890000000	1816339890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
176	\\xaec5efd7c154ea8115889c4c6547f460ab8fd62c992c58caa2eb35ae39bccd5f581c3137c6d14b8ac1709a0cff7f868e83dc7f8f899e6b90839a7d0249bcd6f2	1	0	\\x000000010000000000800003bc04bd90645e6fd2d056fbbfdc3f9ed4c48ce48d0389c44fdd14b9ce4df74e82149e6ecac9b05a134176929fe695ef0c17c810c2cb04781d76e01eba6e4c2e713a82dc6c7aafff56a0d198ef8e40d4bca0afd86e418bf8cf6fcb89c8cfdca1f24014a6f51fdb94ef1870b764f82a4bc0004809fa6e387234d2c1d3dd9e944c3d010001	\\x5d31948adf7aff8d1ecc3bed6a01119686e043be1872770089666da9a3f6da5394c137393c0ba6f4f3659ed8a2b383095ab6450df4bf953ffd2aae3b65b28e07	1667727090000000	1668331890000000	1731403890000000	1826011890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
177	\\xb15d7d9b821ede6f293f8d86192aebe651771931d2152c258bd51151e64f6dbc7f550298f88f6292224281c9ef81538423369ef260f3aabb16e539795e1dd2b1	1	0	\\x000000010000000000800003b3e5250f53a8ec7f73d75acfa2e850cc08da2a500a98da3c345428be7adff53e8b28360ca34d3a0d84febd4a620bfee2c42d64aef507a0636c89c0a57a9d0d9b7345564eceb829d2e3fbdb5b6c2fa12d30f167895ace4734f50cd87e931279a608b061ddc847cb7cd6fc4d045e3ec94139946d34ec0f6b6bc0953736560ef2af010001	\\xd12564a017c588be530ed70c0801bfc9d042860ac0e94bb9b78af41116ee93b9df4dd6025367bf9a0176cee4b4fdb65e00f4b3fcfd63b22f283560e129168b06	1668331590000000	1668936390000000	1732008390000000	1826616390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
178	\\xb295a61b4b21e54c227bd8598848cc708d8bf1bb3fd6809775c82e84e603075c7dfa23ce175cc1c4116872b084d9033ea7ba475b8fcce5c60235587246c55148	1	0	\\x000000010000000000800003be229158f513b0072df1f95609a64793a4ca46e223e47b97bc886e3e5a3d9fb2065e2bc1136cc70f1bc6fcbf26e6854dba4c9ba787db713106ce4b602c6afd38efd539c31900db94294d21a4b2ae5dc5506744a75ae0ebfa0978bb287dee027c7050d6a9084228630e9e1430c817a1de80632e1896fc28cf6860cb94a3ecae6d010001	\\x7474b724068abd709d14e4a8833238d628c791d6a897c48f0fddf58aed05a740f64cb698904846a58b884e31c23df59ef8b7dee0ded2e75e84df411ccbd8de04	1675585590000000	1676190390000000	1739262390000000	1833870390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
179	\\xb539b3ca85953338173212f21756cdd38d467a6ad949728becbaec842a259f56e21bb5af3e7bd3851ef45d75791daaed5da4ac16fe3a8fdf8c3101d044d4e252	1	0	\\x000000010000000000800003befd71e3f9c2ef10b483817d4429624bc0706c11998eef4b57d16fad5ccab7d4dd620acae82dcd0cc09d0ae09173531f3bc2627452407345532d1fd1c4848e2a68272c70bf1ee0cd3e7baa261c495b14c49970fc6d256eb6328f7442743756bd5a3abf8e65e0e87c33dc0676148d0a36f0bfcd244d53cb543b9935b9c3d3073f010001	\\x565aed9f27d4c28d2d6730db86b1999253ff1cef3546ce938343eb99c684cd817731b48c789fa21120a11a695d3cea7a3eddfbb556ec1b72c60bcb9dd57f240d	1659868590000000	1660473390000000	1723545390000000	1818153390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
180	\\xb7fde0e79b6248a69671a1e366a11ed8c78a3bb4c84c0cc5283f0a5a414d449c85f47385942b93d9ae41e56c798ed6d6f6da997864f750c85b686f601643c1b6	1	0	\\x000000010000000000800003d302c930b6622e59af5781178ee974322303cab0002757024e6694c520a801538167d8dd56e50cae6603169f992fe30f2926747ea0f3e0fb8be005946eadb4557faa3ab844a75f0456944a962e243223e1ee43b39b45cc143fcff24670d9d46c0f45729bfef70f2a17e31946c0f3b890d75da5bd2ea6df32ac7c4d569c213327010001	\\x45701291c8f939bbef10cf55f578785cf501e915ebf7993510d868c3e25cd7f24cb982f8ea9610d6a3e0e8d82e504ca9d4bfc884aa735d43ef118030996a9509	1659868590000000	1660473390000000	1723545390000000	1818153390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
181	\\xb7314d0be3b58bc23b450a3d38c35a39f5effc361b5e5d46a4d0f0c404212aeb62e81413b453f6a4dddac5084f0e1291d71c7b183dc5b332861eb0d56550bd6a	1	0	\\x000000010000000000800003aedba5ab60e5a98b4414d537329ac084c17c19b91f4156b8427e3e373d88df79a508a07c896da5c7a18e32e920a72733448a366189bf70a955c1f0968f3a64c333e40354336a448860793d974e5c15947e74945cf5e390bf5eecde663ce59b138d15bda31791fd83aee7c8f380c4f1a508e841318f08cfa7e7f573a0a976b0c3010001	\\xa0ac67a14fb87659ba4ca2f761d38ae4670e00227e920801093798ccb8aa20441a82024c16713730271d5289e72e5948fa559c1ddd24454c3eea2630fb7ee105	1659264090000000	1659868890000000	1722940890000000	1817548890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
182	\\xb735778977fd1681ee18136634946f796c99da768221eb79a4b75440376510a46936d4257cbd4388f8831f921cfae6283e6460dd32da580f295b3c59087eb890	1	0	\\x000000010000000000800003bd24a87ae914606479398b5d0a1ea27402fd48c2d880ab45e91c2644f065cedca1ad5193221091fcbff1e7452699c8bcf30b3d97f27ae6899820435edb69e3eaa6effa80ff9802cc2b7ba7a5e11e605edd03a609392c3f913db1e9dbfc4b1615aad106424b60a8ad03e5a6b901b8da558e5dc564da57eed67a492c877c735a1f010001	\\xd9217da7066db0f579a294f8ea36d1133d5a5196f5d8757ff8e509f009805a9ed0e9c7626c3a903c828b2ef31450ac566a3453d940cb2bba8fc09a04bf20ad01	1662891090000000	1663495890000000	1726567890000000	1821175890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
183	\\xb715423c5abc08c7638ccefa5c006cb1e11003f10db68e026b534416a5ac101f64a4c6ffd8c6957b3fa09ccb3da470e1fad8e74330919be1ef76bb706f35dd9e	1	0	\\x000000010000000000800003b2d37006efbbad25e7d9e4196641bd273747d8fa33fb51736b3a0d839820c1f0c3ca9b7acedd7b56921b0ac78dadd60edb5616a1f43b9d4d569bd043fe6f59183d5a34796703cef55ae7bf0924bc6292c72009433977c453c5b639481eb4c1a6daca41954bd0ca57286cd52e6daee34cc25d844633292978801698d7558b9983010001	\\xa984419c9f7bb8009ce210add85a61011fb2fe349c06a7a86d1152fac64011a71595a17d2f79dbfd32d8d96889b541fe77631670ed4f415155155eaa18f75402	1672563090000000	1673167890000000	1736239890000000	1830847890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
184	\\xbaade6f5291b2e310651f5126903025cc299d45dfa176b6d8f843ee521f6b4f879c02a24257248715305ec9dd671c54f94e3bcbb3f4bf1503f06bdf05b429201	1	0	\\x000000010000000000800003d1c2121ee4d70694490d08483add0a0731b55932f43ffdacbcf11ca0974fec08ebb8fcde582d1ea01414014cf8bd62143605d867a504bf09995e78cbf93f1a82f5f750c63d18cfc072d35d2cd1e67255d91389795652d6128044efc962afe467de60cc40c499e86be23660e7a770ef26fb9dc5cfce8ef5ed487e78bf29546a8d010001	\\x256c3c254b0069ea445d48ad5f1bfc156952c7e47bcc305c423b8dbd50d9b938b4f4d320394185029c0100f2042efed3dc91a6848e975dc99d997fd2a4ba1b0c	1667122590000000	1667727390000000	1730799390000000	1825407390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
185	\\xbb51df8564769131d0a6d05089f4e289232f0753d09e23e9f18bf56ac907a8afcc3170f8a25fb95a1f71bf06313aa8aa19ba61b57ef70f590f08f64c5d2844bc	1	0	\\x000000010000000000800003daf70b7306621a3a98c6621749b6395cf365e21f7e1501128e1c49a6df1a351beaadf1b1accee75217ced285924cc26e0b9405750333adb6043191ede1dd87319c2d80da3aece1c7dacb533d2c760966ee5510f8e34bb9263bfa38dfff7afed63e028cf19abc16cbe4d4dbd24b5d0d513861749cf5561a16799bc2093c2ba823010001	\\xe0cc5da10bd6f39e15841304673e58ce128f05c595b2335b5952aacbf0d8ac11d8813085c4f7a5bbf31edc603b8b931b05f264453fa11e073becb0378966750a	1667122590000000	1667727390000000	1730799390000000	1825407390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
186	\\xbba128690e8647da2e606f9f82896a2934572752f934fd247db45a6d87830fb91da9fc846822e878c1b2ddcd314e6730409f5ed31713d9efc758617120ac6010	1	0	\\x000000010000000000800003b29115a177e30c7e82c592537bc0e1bf8d0673b08fba66fe464dfe4f8f58adc38563395805c7376db5dcc94e51afcd562d4d6400b63f4ff5ddde17084a87446f99da14935fcd3221b5539a8282cf528582ef0ab35122abc9bd8ed82901c90818c0a3d489ededdd89cf9a76af5443411a7740d9d28b7b5489800eb467edf38423010001	\\xcf40b17f2aa29088ea7df13fa38670e2a81b0522d5c305355e356e2031b95e28d12c38f2458e7e6dabb8d9010114c2e2443730f175f49716f38f4d8ef3d23c01	1662286590000000	1662891390000000	1725963390000000	1820571390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
187	\\xbd813e399b662b9d441ea48bcd1325424752d5626902819c1b5ddcfb5adadd3f8db9651a87ac67cb640061b114f2627a36aa15e9d85160a2cff3f79c171ede36	1	0	\\x0000000100000000008000039e01dfce19feb54c0c54ba1899d60f1a5db704c738d7f577fa64e20654f11bdd78e539d9376a0740c290dabb9eff21ef94d801e8e435200b26ade343d8d6ab831a2d26698767086854c30e42396357201df1253de62071ec5cd2b5c79b77ec2aa7dfb875f22aca1b0247d443570dbd0150e9156544bdd91cd635b4a3c37423ab010001	\\x3eb09b5fc512bbb9d813c04054a7605744b2d5ea9a020fb2f74e0933ae83f16c42570dc471a1a6e26ed76d657d96746c2da4c14900a3e18a56bb1de23d567108	1655032590000000	1655637390000000	1718709390000000	1813317390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
188	\\xc0fda9ea6e147570e30fae44d3fe19a46aaeb1557b01bf59abf652048b8664a67a389069d40bd6d99928d60327bf4a9237527696ce6b73a89696b17ca90a8fa9	1	0	\\x0000000100000000008000039fbf10b41c94faa69d796fa3c82d247cf5744dc7c32493b749eb715504a90cc5214b9452c8cabaab69ed7f2bce2f48d16b10831d6bd728fab0cde0eef811c14e9a86b47e982937e968b1911b91f1e8a3903b5016d9ad6f73a13e1b5f72d8192ab1a441dc76f31436c4568f9714e3a2dad4ae82714f33682d0461c0cf5b0c886b010001	\\x0de9e72fb3f22c707401a3d28ecf3b934f68ee259cddc256b484d358d2fce824146c44ba1d654ba4b95cc96582b0d13c7a98e8e6ee50c1bbe5d3db17ce1de205	1662891090000000	1663495890000000	1726567890000000	1821175890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
189	\\xc18d796d59386926632ced02549bf4fa6c17fb2869908edb5b5d7c636a411891542f32f3aa1cd54ca72345974045a45e939edf880a1c2dd107bdc853713bfcd8	1	0	\\x000000010000000000800003aa98b6de8b3944a19b76ad6d06d0bc074ea947a00fa37af3568f129c057543bcd4f1bf8623e07f6fe5e021f2117a7177a14cac28f5c2c1bd7b49a980ce338a4a24aa39428fc9684617b05280ec8c2335f4639cde6d9ca403e1feb0f35a90b79e649fbc244a8af49b57b3b1922538b67beeece98ef3b1da35ff7e4b1fa28f2f71010001	\\x4bda522d3c386e1a29852b304cd402712f3c9c3bfc01bcd27b27cfd5d0e391fb5b58028abadd2d02784f937846837510bdd3017e82e066bff8090cca96832707	1655032590000000	1655637390000000	1718709390000000	1813317390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
190	\\xc4ad6ba0dad5f7b54dad9fb9647859d39f61d4336b96a0dcf668fe69e3fcfe877a4c271976a544b4121b55ff4e808bd6574a4034c189e9d1f57f57cf01411f61	1	0	\\x000000010000000000800003c7333de51650bdb854046c3ccd75e360162fe20a3c24cbc2125b08aba06c93eef47e8a1fb455a051e7041dcfcf39c8471c4937da143b0559cf6a5a38486e291b32f6e805f707c72030b45c41dca62146db7ab313e67ea290e1cfebd140b93086f3bc619d0a358db0df4069c9c60fe4485620f21015da43ea83c2cbcea0dc20d3010001	\\xe5a98299550ea81551efdff8cfc4a20699cc06812e54446771ed9250b368f24e574d7185e7d6538d7520b66e3cd7a8f70163e8c6f83f798e48211dbf19d6f905	1670749590000000	1671354390000000	1734426390000000	1829034390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
191	\\xc649e110aec4c724807b1ace13b594876fea4cb7c23398f751150d672973f3b7bc78e63b2c28310c46db37d31f4b637fc9b17689c95ffe82680e2801ee21b208	1	0	\\x000000010000000000800003c6717694f71bc25812558210a7a383be89c9f2b36f90b98c905c3eff860e4757e6bdf02591962238aecc2d8155a806bc04966d91bcec1040815f585228f1e975a582bdeffaa19bdc2ec2a192070699e4da3f7e0c717efdfa900f76002cdd87b5afca31685386b46b522abb23edeb73a58318d94389474855c0927c5e9782cc9b010001	\\x2df542dfbe3322014da0359006cb4e0101c026ced51003bd192e5fba1c94b2e145e2f69ccd1d1955d2378026a0931213cc4169fb6f8b2db9ea42df51b50f2300	1676794590000000	1677399390000000	1740471390000000	1835079390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
192	\\xc7198bcb2125ba8de1943972df7c5a677112e5b98ac7905d17217d3ed8f54324e78913f5cd6796899a8bc2986b150684eb41a64d8541603520469a0d1a53f30c	1	0	\\x000000010000000000800003aa1bbef04bbea162ffb3a5eb277e0534cbed90e10507ea1f71874bfa1eb1418c72502d99f4d4134d096350d2e98fa8153e7f6548a29250b260111079e91e75eea8c00c0f6527996c9e1ea0ee4d5148d37c0e9c4d323fbd6f71a06dee11741a94e387e3f262129650a8460ca95688dbbbd73ef71160a6f4f8f73d565b43860577010001	\\x4bc108ea4a8751d113654dc06cdb9471a69ea9109b7326babe9d1dbe3eb7c3063fa0ec42c2311a32beae3826d1b64024f279bca07c88aaebd41b548c23a59f00	1665913590000000	1666518390000000	1729590390000000	1824198390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
193	\\xcb315490476b85c0679b70237620de9e7acefdc0c1ffabe4ca924eca89a0bcfc6ca98be538084362ebe62ebf7a06b7a9d9f00efc59eb5714d5f65010b5a69066	1	0	\\x000000010000000000800003ba7548853cb589cfc6c3da47571949d43098ff58aca63a9b3bd0007b271eaeaab957f2b7e805be491d2af6988b4c8ebb8538b767c2aa934cdd2ee89858ec224e7fffa0216d53c365dd3d5be440e59ca369a4bf0ff4ea8fbe22a4601c65886013be02005e89bcdebc7801b85da57c45bb6947fac6ab69506c613c99f147592edf010001	\\xd081f20097ba663b8dd03fc134e5bc3aab53a611d3c9ff468ca41206e8df439e92e78c705fec07d4310633aff32e9f64b80e8d949055947e0db82e9d97575901	1648383090000000	1648987890000000	1712059890000000	1806667890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
194	\\xcb4df192523d813536afb8350be78387262423aa553b50fb66eadbe1f0dcab09bd38dcde0c33b2e3ba3d31fc5895038d51e7617299dbc3bd921a89ad0331899f	1	0	\\x000000010000000000800003be41ada6df3f80e39659b9722a738aa07693c06f1eb34972f9c924e4a75a99b67623cd376a208f6ff488b6a1eada78c0d0c81a457013abf8ac5af1e3d343e7a91277e9f425e919e17587c4f4c734e9f45267c0a2e940f8dbf924c8f38391dad56470fa09c5ba3ddd28d0a6ce7e8219536666d1f4cfa314744edf33123ce76d5d010001	\\x50406d76b52873a78f449f06f100f86a42345aa5bf91faaa0d1e61c16a6f0cefc705798037ad8dac7a39211ced0bce7fc6b544f37b7b229628991d8efb86dc0b	1674376590000000	1674981390000000	1738053390000000	1832661390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
195	\\xcf09357b80e8b1378c913a38fc64677ea9b509ee57672a35f8f486cc89214d61330f4ed1eec7eb66a226e9b427de7bb1a068bbf61883ac07d0f17dfe9ee22839	1	0	\\x000000010000000000800003a6c2f78455d29975f594ce235bf2827342c014c46a7eabb159504e89d2498d362b45bcfd8dbd57abfd136d54006c90da3d2dfa3d6ebaae09e6c169da994016945ad1c8e26ba9ef556d23f268cf3f7657c698f1cb2d2dd4795b761cf6b65679062ab10b861fc1066b5670ecd51f5effcdf2ffd8730e4114a01df720fe31c0c249010001	\\xd47fc2e85e13d3fb808796a9a8c40af460d4ba0d44289387994b536aacae58137e7e575be0eb6c6aabdd8edabb79dff2824945db6da78936800ff948b29d9208	1658055090000000	1658659890000000	1721731890000000	1816339890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
196	\\xcff9e95e8c4c1f9612d5aaaee1db5732bf0598ee4fc1573871713c0a20d9b94b6672becdc96644caa0b790150e176b7dde4b4c74e8c535ea4ebc7e8000a99815	1	0	\\x000000010000000000800003c7e968cf2df95565eacdc62e9c8d21d531d706357372def991cd6ffbf901f3bcad77021c9fb6ce33cef8659492d00f0f9bad6e8703dc4e8db43fa7569f91f8957f1f36f2117c5e17650b4217f91867c80ab23c9f17a36e62e0a4682def651ef4315f7b2678a58bbf46ecf3fa63fcea2bfb68b13a146bca2fe2bd2c42a596850f010001	\\x7850a5bf4bd43502d20c7f1f098b4085ef7ba057d9bab4f643ee40256760d98f7581740a77f76c4340004616e3ed29759d75a9dfd16285e6a31e662799ae2f02	1664704590000000	1665309390000000	1728381390000000	1822989390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
197	\\xcf3987d1eda99ef50975e2e1d6155f865c9421ca13d7ebf0a9e5e350cee1e4e127d5ed3c4d0285e38286cb03d3c7c304832a679449143ee17963b8a1f25fc122	1	0	\\x000000010000000000800003d09eb60a0df5b9cc8f3972da448a781e046ad6f42ea33cf92abc830a3ebfae05b65db668519c7e1b3edd86f72be570fe8034ae981a5e44f933d26c8627c85e85dc6e633fad33f848b831937df1bb07904fd652491494cc16db9f1ec5af655dcc7b8413bc5622d65f74299c58111ac5e6200c349dbd071ea1a46b16848b3f1635010001	\\x006fd29feba1dabbf1601fc8ff4bdcba8952b13366ba7486bf2a8739232a118a80ff9142085ef20dc6f9bfc9b878ce839381557fc896bdeb7807ecfc8b988901	1670749590000000	1671354390000000	1734426390000000	1829034390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
198	\\xd0912ba350a58a29e5b0e49e184a9f5c9c94a3d21da81e987e1ee36769ac18f2fee7116d3cdce1717e6b25b80461a661ea1b576458d15b527880435271cd17b8	1	0	\\x000000010000000000800003c669b13964101f137004367779aae3f039d301cffe4fa1ca6342844f8ca4ad85717d6012440a8aa9e267c1fa1bb9f99ac6f6af6938389dcb41f9081d2a9b03d59f1847191642763c9233963006175f7762f28b77250e6a2d6ec7ed6ce0abc958b0202597df0baea23ae9c635c326f0d26487cd905bd2e5e31ef338c755f86f91010001	\\x83cb5603407dd6e0bd2688f6cde45d8e773d642cbeb7086d9f8aa38c1050a1f54f57ede97977804a3a9f4d36325adf13b921b259b0729e4a9470cf6089f86707	1652010090000000	1652614890000000	1715686890000000	1810294890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
199	\\xd5c1c8b4469075d9f8a4774a97ae237c2adfa631559d5a0956a9f577c51e481dea88301e87961d62c1fef1b20e89f6f16da7b219da48a9aadbc0cb61d78c84bc	1	0	\\x00000001000000000080000399762af0571cb5faaceec22ce5840f30ebd4e5d4f6ffdffe509928e00fec4518634cb7e96582db101984f5d538e0a27cb1d578e32db9dae3c1bbf3cfb5d8a12f658e772de82b7dd944a9323b9a5fee0fd854a99d81f89e063e1b84ad25c3ec1fbe06e185d6369eb136798e2dd54690005051d516ba73aaf055d1c3b674ba4499010001	\\xd4bc0d670929603b25a7b4a839b01b473c67e07a4b99afb66462f2c86942c272ad80d609892ba7d61e1074711f81542f7be84d7a4bc18e883c03abeab9eefc01	1673167590000000	1673772390000000	1736844390000000	1831452390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
200	\\xdab108c00fcbc888c2e647ad4dd27ebd7a30b5405e75667e304d61b823fe323870e365d2185fcfa97f2e2468a52b02cd7af2567d24a8afafe8b1a5ec95b636ac	1	0	\\x000000010000000000800003ea1b56d1b16e88211ce01744dd52b3b522e7738ddaed9ad07b6b252c0e206de8c431e32c00dc6b47e1ff40a9f12573c1571774f550dbafbe0ce78bb1447dc413a6a414641eaf1d0c76b5917e49af1d3c79840cfa2c51ae8919cae9c01db40357c08b688b3d461d5e20dc692e9bc1fa1cb219d20826ff96a36a950535d031bc1f010001	\\xf088db20ee0d579f8c2df9666f98cf667e251e823efa608c65594ec61b33b86a95d2b2a205f5626c800b31e1c54edc04f264d58f54d5ffca8f5e5fa4e1c9cd0e	1666518090000000	1667122890000000	1730194890000000	1824802890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
201	\\xdde95d6968ffdad683f783cf5abbc8d3517bc78d56ba46abba52797beb223f13c327bba54057bdf1c167902f06b4ed982540537685e8bdb5db38cd9a32a3eff3	1	0	\\x000000010000000000800003b010436974327fa0780db019f1ab70212567243501a7be7583cae4da543ca067b69cda8d5514fda27f8d78bcdf417ddc0ac7e904dd805b2723933b5680a498a204dcefa1fc378afd566ef0de882289be4ae610e70315d5a4b2e1737481d5cb6751255469ad6bf7cce798767e2251c87ab31ac58c9e455b58360c7762833f92d7010001	\\x8f32b8f5ca97f1372216bac088c2f1cb210940011dbc4dc71a1932088abec3b952203747e5ddefa2147847152a6dbb1ab1dd1efc62fb8170db8606e37819ec0d	1673772090000000	1674376890000000	1737448890000000	1832056890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
202	\\xdf591c18fee977556df0c095944dd34024eaca9fc3b849a0136bb9c46fd078160eeca93337756cb9d5b41b907909d8af23515de1d17f38bcf7c090b9bc14751f	1	0	\\x000000010000000000800003a5d439879b973608d3220202226644d443679391a0bb39bb7daf0ebf4d1010f61a363c60dc0a504c1cb3bbc2d02261fda4bdbf380c08c0fefaa279b5110d7a77b3fb3abfad580bfc5c196dbacf699f97da30e11cfc796106f801e0588f37499743574f041aea7a5c392a6d976c960efc3752951e2f6a1557d75500701b845fe7010001	\\x30dbb289ccd17c9d9224fa688af5682497e78aaa3567c4982f4538a78143a11719971b012a44cec34353f5b26380994d4d45f5f96e3741e65328d9c3e0ca5f02	1657450590000000	1658055390000000	1721127390000000	1815735390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
203	\\xe315ea9569d52940e344812c9e81b61b7636bdc28e254865a87a1eb1c490d4998d615f9e9d0d1c597bd5d3e56692892fbb17ffc2c96f7b2973ab4ae2cdc2d06e	1	0	\\x000000010000000000800003e3a39bcbdd54e204bc7af26a15166a396754a8f695b4d0dcf5d87697d44d097cac471f2ba6867729efe4e5cded28637ca1507337d3975daf0275c77a8d08c3a24c14902cae17064ecc393afc9b8a157c8b5db5e67fedb550dad543c8f05febcbcb4553f1bf39ed2443494c5382b3af2f3755821178195b2575ac1b6055cbc2cd010001	\\x9f140b4054cc9dd4d17553bf9d3ca0ed8dae92f880fa2b14a81f7d2698ecb711a07bd31ed76d855db3f395d685bcc456537469af96f54440795724eff63e2c08	1662286590000000	1662891390000000	1725963390000000	1820571390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
204	\\xed5d65d5ca2f94b8746bd936ecb392a909fa32e85dfd1fb70d01bdb51c539394da29eddd19ad951d740417e71530a8d55edd542a17596b0672fdb4919d0c60ac	1	0	\\x000000010000000000800003b0a88e2012974e5a6edec53e71c780a68631c48050c6a21a0361d37d82c5a9c5ffe1bc5835e16645d1420688d7e0b14204c33ce782e1a086133a0b7e751a32e39d3354777ac3e79de3b4c48310ae3267193f68f10ee94300ef195290b600fea1d12b6f5fb37497096b334780a94e1dc2472d4f30b7e522c8bca3c65742084961010001	\\x1a496530727a6c9d4e9cf305382368ff370044ea9cb55a9f06f14d34ca4c5155fec66ffee1be5eac8627bae3ca13961863b760ca5c10cfee99f843abed159d0f	1669540590000000	1670145390000000	1733217390000000	1827825390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
205	\\xee2d3b8777e3e8a37cdbf7fa46b5c3c678cecebb0a28b28ba5798b65fe99c1b528e928f4b7eda141485792a5913f8cac295d86c33802b37475f95af6ac3fb6c0	1	0	\\x000000010000000000800003d6e86f5d78a6255eaaf3eaf145e02312b63fbca2020bb1a5639981a544ad444128baa119f60fedbd808851e795672da3ab2b10d2f9d9c448b40bd7c1ca837b46d9603f81f9ddd68288d3dfb349990fc8b9ba4ef578c5fc689cc83f19b5b010e434fe6d847f2fd215b93377d92afe2997a092c60c3ea5121928eb360473db28f5010001	\\xba57de6d548d8ca4098be4e1ab2b3f263aaae02b37cbcc37d1bad187f99bb98adfd53975d7e0285cb11f92afb1466e39c0b12951c5c597eade3d5fc1a125c405	1650196590000000	1650801390000000	1713873390000000	1808481390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
206	\\xf06d967fbec941d7af3b771e32d88d759cfcd4dcde2e92b83e376d73276ab1c4060327ea94eb56e10e74f8ec405481a11fb180b1fd07a5bbe3f02e0f9970af8c	1	0	\\x000000010000000000800003b4fed20f544f4e49aa386af5384dd0efd22dc99936198177f06607c4bc6e078018e9b4ad71a7ea1afc78b0f8a759687b43467726811c9835ab8c35ec07b3711670c178bf17d004b22dd01d3e90bdafdbf32ddeedd4ab23213550d103bb01ddaf52542a1978e5d1d3f0875a49e877f3f5a47791d3795a27f7b76a0eafe4d3ef15010001	\\x30b22dff2ba74e729cbe55726cc54f59f2a1069c3cb2e8606944a136bb720524874b8f33a1d76e60ad77b021d337b9017bdc5a0b90078c14e16110c89b6f470f	1670145090000000	1670749890000000	1733821890000000	1828429890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
207	\\xf235c80aa6ade0639a96dd8842d690fb59b7b58656c3714c684ba5357a908624e840ef45850e821fb8768b40cdabaf2662c56b35c6cd4ea134fa584b701b73dc	1	0	\\x000000010000000000800003b7c9f6ecfc1b7b262becff8d48a8da54579cfc9d80905bc3d6012f9b0d4ecd37282979098d20e971c7c08785804b29d51bfe816706d6c2331ff3527a54ebdaaf76989e206fe53c2437625931fa3a1b2858b7f4ffd4724201e6be64c480b19563fbcde847784adc8699f7d2fbed8f608d74275fc07a15e092821acf2a1f8a71d3010001	\\xd24875fc0b38bc2b4959243f5f90cfc9cf5cf46769f6d9460c885b69268298e7695bc1e572afb2c78e5b012d48864997a973059255e851d67c2b425f1e7e8708	1659868590000000	1660473390000000	1723545390000000	1818153390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
208	\\xfae996d78189e46b16fbde72e643cf24fa8e95a499ab064179c625d894e9b383824b619250d766cb4878e5c6e6e36b624a1afaea19f481a94434fa5305f88e3a	1	0	\\x000000010000000000800003cad70bb8212630cd079c2df9e97c25731ad1d8db36ff540f3b0ffbc6d88d9c3c2441e1996e33e718dab4895a38cd91114600611630b31629b518ac6d085e29a9ffac0635883f5a19fdbe77f26e32cb671acc2c53a6618509a72b89ef6f497de2c97b91187e55bbf8dd0062394e20df27892d473a4e8072de130622a300a4a74b010001	\\xe2fb26d40a923a5963d8e3ae6fc620f8458bb2d623e5de237a6a452d25ce5d2123fd623123907e03ca75db1f7232591df537c2e2d4ae5e5ea6d1926764959403	1670145090000000	1670749890000000	1733821890000000	1828429890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
209	\\xfb4dc7a9cc99ec3ae9555222386cd75278b1a4b43c1376d51b38c5d49fcd8dd33ee24fb2d8a1bbf726d2eebbb2e29ccd47faef3b217a14861f0f72be64402ec5	1	0	\\x000000010000000000800003a4a7f9d99d2cd44631f18f8496304b909a4fa7e5c33259dfc70bde3edcf83f80149120fcd646cd42e77769061cdb66dfba75608856a9fded8b14d031667c4107683649f7efb08ca01971da5efc3a05680d6684ac270ce932900cfefc8ff9eaab6ad8ba28a7c86554ed26f4bd685e89ac5b39d35558daec94a30ebcc3449b30b1010001	\\xb5b6c54245b81ed7414fe9deb82fb00e142ec7a4656b54132dfce72bca92368b8d703b60b8410fbf5493001981090fa195d6edeb0590ce5194c5fa9628eda30b	1676190090000000	1676794890000000	1739866890000000	1834474890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
210	\\xfc1dc948d4eadf259b8655e1c6a738e60cd3264bb736b60b94695963957a3894e9534af9d0c8bbaf151e235554e34b083147aff23adb4642e51ab180944d9476	1	0	\\x000000010000000000800003ba24f35864f76574000397d3191f64dc2afc88c9bec453f76ee49e77f07c9ea5de926fd0456ed0eed8ba2c2dc27f1e840c95ab9cb6233e5c88f33e1017ed663987914125b6c59141ebab0b69924832ca733ea402949f94500f41d3f9e17bbc2ec2ae46ecabc7708668d7048283ab80648d5bdac923a05ced3357003fb73a9445010001	\\x29cda082ea58e3bf63740bb16cc54af8465bffc4aa25a6d306d3127cf6a148b047c8561f886a56e739b9f51283423a9d098794febed43f3148401f21be05940c	1664100090000000	1664704890000000	1727776890000000	1822384890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
211	\\x019e0c078a81705289a684a3802f194f4c8326e04d77c07fa7d4aba07e604a860c7bc5f6d4d478e01b61452bcb35f4a19e00383fc307c5ad0b889a39cbfca822	1	0	\\x000000010000000000800003ceebbf87b5ecf9fff026a1d9cf80865cc6e67749b226e31f360158abc243a564d5eb09950bc811815ea1c41f0a5653e83438a730609f31c6eec8f08f7a24085fec86f50f704ab7c373e6a58347ffa94fe026783defff882f809808de5c0a63bc7ec006e57d60b672ba5ec053fb28a192f2eda02e225558d4f7e42e4059c51341010001	\\xd2fe8b9957187a92f75bca0c41dcedaf0eb74cddc94c6b16d45be244a3b9c7b3525cddacf5bf0078475b7d1661d3c86c69d8edf9900b4fd3813e9c8b975ccb0b	1666518090000000	1667122890000000	1730194890000000	1824802890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
212	\\x01ce7a405802a337a7959429dad056d90cb5f13e18d0e0f02905b4e3ea6b38766474df50c12817964585a5e403fe4439f9574a5ae16fc89a2517366d2e5ce304	1	0	\\x000000010000000000800003a8717112ad0a7ba290171b96b477edf98bc3a0ad06d1961e674bec061d1060dfef841cb2e491f65da5dd3bcc51a1488e354966697ae70fdcf6707074c2cb01a5e289bf9bbba087a87f793f5f534420a4d0eed2ff177126c9fc82169f5d3ca94ee462892318acdb1b5f383678f044876978d40e66e0fcc72fca56c51e4e287b2b010001	\\x62ac284b45467f516a0789ceca9d4be737e18dd9f29be14faf5f65cd76cc948660585a306e630812dbaef063a3e1a8341c052bc59a00709f628f09a8836a0204	1661682090000000	1662286890000000	1725358890000000	1819966890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
213	\\x0272ca55448e46cf8153a8c7110fd53860b6d17a3c874f315c1dda3a8a4ffc1482b8a0fcbcc44c55672acb1bd332bc54977d7dd5d2467a7b4071804cb029105a	1	0	\\x000000010000000000800003bb43d62069a6e6e3e4b27ae7b97d27cfa16b0cdd6b8c1e0b6b1e863d99a1306bdb97a1fee49ec2a6af4b5ef5f44983ce20218280555f5810444fd6d3a04661080ae026d5ab787131140d53876e86c622416c9385b1095af005ae03f60f701c49d27b305a3f7a0638f2f502142296764dadd1aaff4af068a3ad1cd5106fad23cd010001	\\xd6f424aafb6867c6bcab2936cb1d6bc88513d011bfa5daba408661127d3dde02417b7cd2301d85d2414340468d05772da9d0bd75ab07daa757d3a14d9cf79f0e	1672563090000000	1673167890000000	1736239890000000	1830847890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
214	\\x074a401c45cefee8aed31940827364dbf17a7f8cf9f7629e766057156bcae4b8d450c2694164602b1bda36171373f232c4418f7e6ade5177df18b8d8eb701452	1	0	\\x000000010000000000800003c7175d83dbd73df66fcc8636cb22cf4104140697dc13583a6316dd87b2b384674d01094c7f39db5550358d738cce837bfe8e40649bbac3ecff9c9bad8d4905e94cfd6d9c7ee37d76ed2840009e04d57eab6f82343ded700ad80fcefcecd1e12ecc7b40a9de01afc33a56448708e34c5388f666eb1bc6218e8032e3552d647861010001	\\x555d5d186d17c255275c2262fdac313cffd1c28be2d6ea652087b4e0ea4d747090159490ddba7629e045effe6490eba463f504d67ab51ec3b1c5aa235ffe9c0c	1667727090000000	1668331890000000	1731403890000000	1826011890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
215	\\x0bd23467e7789c3854a15a8c934eb1e9cc124743ad07a39edc38bca7ecd7926f137ec42f7553215b2af7d8f199a6ec53df31182202807bf3ce4f2ee5b66981ad	1	0	\\x000000010000000000800003bc0ab5df4229ca3db9c9eb8ef6356f1aaa8e978b383f406a3d1506d0c06617989bcaf1c6a67fa4e81a2956d6811ff221e61d38913836b6a71f8a5271258233214b5814a10839178af54415d4c3aa44f2d5b91c782e44c27fbc6705d99edc3a40b65dcc7a70ca1709f19836d55af759b1d9e72642d76b6e79566e83206fd662e3010001	\\xe706f6cee5346c49c8e70c9e19465247e40437ab5db837e4ebf7bc78ca1baa870ecb0f9d38f13400e0972c6746e2bcb1547eb49462588ecae178b2454b780407	1655637090000000	1656241890000000	1719313890000000	1813921890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
216	\\x10ee46318c9d7ce268c5034149b2d3240bac6f86ec32d05719384e8c619089459a4bbdcc99d70a8daf2a92751a77c573162ecd742ff08b423bb0e8271cc2377b	1	0	\\x000000010000000000800003d8f864506b5cd6631b5018f8c323b5fa81f06f1fbe154001d3b17b3121b849806b1f9caecc3dccb897a84d46f3854f6ecd912cc8019888f3fb659398084b3b5b1c3a69e0f81e8eb1a15a71f86bc43f75585faf8f47a2743bed641206c80e77a6279fa44c69ec0615bf6ee35b883fff58c2615454c9f27651097d7b7777b8478b010001	\\x9518bc09a5ff8bb0493700478759b94036f07a611eec07234854dec4ac8bc2c47abde96d15d306c3f0d121ebec1c1515620927b9609116c80b510424b9f4640f	1662286590000000	1662891390000000	1725963390000000	1820571390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
217	\\x1102d66d28bb6c9c0f6872e4a6e17e1522a727a29a6594d1481d74364884dccfd1f6720edfdd42a78ec03608c8a049efb502dca50de96677843a901db9c97e73	1	0	\\x000000010000000000800003a98dbff53e0737f1209e8c4e2a2f8d5d9eb82d07bb4c5c956c7f2ce7b8de217e381809a705e001caa8508027f85b1374382c4cfab17f7104be7e31bcbe51909a9cb49ce8a1e89cd6650733d4ab446a3eda061372296168d1fbfef46f053b8ac9373632c28e59128fa568ec77ab3ee0ede0331ae3b0cdeb04ea8ced80f3460fb3010001	\\x66705e3fafedd53c06a9d5bec8d471beb30d3a404d17e5ece6fa367d34c6c86115d415dac3875ab76b89565027e3d708117d02dcd586e9ae560c987443ddc803	1658659590000000	1659264390000000	1722336390000000	1816944390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
218	\\x111a09713c78de00c0b27502cf9f8fbec5a9223f1dadd970233c3a0e8a8312fe85bd6eff3ff1482485232ddff117db201e296b916b144836835516e19610e68a	1	0	\\x000000010000000000800003b009a74704fb46c4c779775bbc6b38bcfd0c2cb10e623a457feb84f4b4d3a2d5c64e43e23c02241279aa7194a44a9db07c44be3ee38167ff045263f9c6368a0d1a8a2fdee34ff959168f81651e321d561842e16479eb79c3d5ce32e8967fc200a65da49ec3158ae1a040667c2ea4b1bfea1873d876ff2a60ffcfca522ad4469d010001	\\x7f8e6293b4b23f0d08092e0d1e9b632aae25a37b02339f75af465073760a8712d90723fd0127d5c8edf3ec98ef9f18caf9ca9c97a29af1aff1fd408c57402e0e	1655637090000000	1656241890000000	1719313890000000	1813921890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
219	\\x121ee4ee86276e91d7c5cf080d70e207ded90bc8f6742423a2426ad372a8735d55caeb5009fa259e2b11e3ca4fcbcad2a715a46aef08de163947af3f80bafff0	1	0	\\x000000010000000000800003e0d40c4058bf8fe4074284802033c533d6d2a5ddd11b45fc1eb744eb91492eb56e702bd8dd562a252e32f81c98a4b2da1b32fb823af082af86ad8a8f1cfd8abe158a40af974e0e328d6db2dc863c785bb95fdc5d7ae2c2f2b0829a9d34a77e9448d06830f440ae8688f1359fe3a91676aae3d8e7e45e9af1758d35761fc1cd47010001	\\x604f83bd31d1b13145fe2faf0c331c412fc55de06a05983b1c6671732b7883d236f93332045a24d9e3c6665ef9279074cf2cd9e1ce0c342b52f3ee7b10dcac0d	1648987590000000	1649592390000000	1712664390000000	1807272390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
220	\\x130a4b8cb84c2fc4c3153b603b46173b65d23a9aaa25c0925323fd1eddb37f9c34173da84cf656a9fcea1de85620008c5d8e6a88f62544ee461cdd950a7b3f5b	1	0	\\x000000010000000000800003aae03b0d4b8c666f596adb9cf76db60ba8f828f5bdd56fcfa92d5f4e6ef55cce1b752889f221b6defd7b36b3a0d4063dfe96d35445d336c581751a3c6e6a6cbc72ba27b57e5feb5d0d2dc61b0323a993709623fd9e17f5501bee99cf68619a3f9bdcc2ce0fcf556b52bebb25efccd9c0aa277591bbc94b16e65eac72720a6dbb010001	\\xc667ca805d3eb4493bc89fb5db0669073236d06b67c989ec7177551d3a25453c70ec609d83579cbb4e629fd9e9de0b4f975d20085b9fe2f96a056d60f6b07f0d	1652614590000000	1653219390000000	1716291390000000	1810899390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
221	\\x143a9d4921bb2d636482255cb63b6aff21860cbf1f0e3956cf7c39e51eda21c8f892c3f9a22ff237848a0909bc05d1b55ba269bd062977b21b601ef04ba071fc	1	0	\\x000000010000000000800003d24e80e8c0cccfb8ca2ede30f3b32553442e0629f02bdc505f2fd6d28f670a216cb5ef4bbc569527051a43d14593c6257a5264799f339fb803fa9ae234e5be5e028c33c5c7d1f9d675cc62ea81150a85378f3cae6b070bf6faf223a3e8ce612fa9a9987224b11291f84d3f078ce2737ddeb3132fb353541f2d2e9ab1432ddc7f010001	\\xec9b88872a514a59dea42f444321f1f3b0bc99499ee4aafda40786eea13ac3ea4aef90dc3dd5092d4a554145dce31c7009731f3c4601264df11676157b9d220d	1679212590000000	1679817390000000	1742889390000000	1837497390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
222	\\x1776e3751b039ecda448f689255246b4acb5a3eb110f66bbf91c54bf5cfb55d1a25afbbf4ae0bc3a8a83ecbd5bae98a955fd6fbd5232cb04eacffd8b30bf926b	1	0	\\x000000010000000000800003d3d0b02735f3b401c83d3d1fa4a28d366f6b84cd95a9616b1bee7c3fc5ab8b7b44903986e8016201797d85af4966febd571376765f30f72af7a38a8b2687558a924e707863c94f7e8023a7f97a8d7c7b7267aa69dac0e38a84db139fa80022e3a0b88238f713200f47e96f6ae713320fb3bd4e05e9380cf47cb90b14d4e975cf010001	\\x44b6173c217fe272b400f27230e8b33d99a6159f7607382c4faab2cb89d0bf76e083ddbc437f9962475e905e1f5b59b60d86956a699f1d804d3b51fd03aa1508	1648383090000000	1648987890000000	1712059890000000	1806667890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
223	\\x1aee1158557444bf5e3c4b4f144f78b9afedb0c7dcb30a2b33599a187a765c75120206141bdd5bc6f61b0037c8de2ae3d996c804318fab54a5bb89c73aadf964	1	0	\\x0000000100000000008000039ea83fe01a3fdf9b55d808f76c63c0b96f4826cdb049ce149d706a8db89ea8cfda810210a58c3170b01a811a045caec56a06b639635f2b5cde5e53e388de18deee1dc28d7ba47551f2519a1c8c5e973964a07c7e572e045a0f18e346a389f09399535d5240a11a460f7ad2572e84e7ee5aa911c8b95318120154fa2f39f2686f010001	\\xea63223193a8f73775168fe067a97c04c5226ed6cfabc3c8c398e6aab9972f7239ab5319a950289f4e238ffdfdbaf177840e4fcdcbdffeb268d189c98114be0b	1654428090000000	1655032890000000	1718104890000000	1812712890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
224	\\x1b06e57261e0a315678a3d0845cbf5955e10e3df7f93e1e7e71f9dfc7227a65552cedd501d4f66b18e474258e81835f6f1dc7145175b148b9035d737a8f9f41a	1	0	\\x000000010000000000800003d586242fe25cbfc71f4d18ec2c2ac0ad182c5375b41529706afb0e027c5e9fa4a538aa841f0718df6cf3da7f0985b76fc3e1e3ea295586d6e33db982252e00a02a1ddd2f354fc975aa1c67bad595f978c4d9f8b27cc4a79cb7993cb29234cc180dd137ad22fed9739f110a9abcf461e5c4eb469d40255c99d964508624a0b1ff010001	\\x58fa1bd2966c6af4a55f3da899eeed2cf1fa09db3c9cbe91462ed9fe0ca8a49ded4e0cbcc552edb9ff2473b16e1e48eb8ebaf19d267cac5e5335bd4e76ef5b0b	1652010090000000	1652614890000000	1715686890000000	1810294890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
225	\\x1d3a19aa8223271982d9409cd05bcbf3ffd92efd49525c2f185a4c5224ca09fb04c49b9a89dbe9b7c9f32f19768b5a943c9d3767f0d434039ff164e2e9ffd1c5	1	0	\\x000000010000000000800003cb7c456aeefcd53b449eb52b276b7d53f9b7ef435f4b64ddf1aeec3cf6f990cc42e5948eebf7885c8ccdcc4bfef9458c8fb81b3990fa174fa5980a66cfe3258a3cdb1d27536a3879681dae19c9eb89b02467ceaa967a476335dae5a288ed235f31d8b22c0cabe4786324583a65dc005221fbd3bf0374f6f01b4bf5712dd5f0bd010001	\\x3bd188b910a8533344290c87e6879d6d08ce169ba66d7a020ebe2a893c7453a100a7a7ccd9fc188fa1b613758c1ac0bcdd45b73e749bad79f541f2d7b4fe8001	1663495590000000	1664100390000000	1727172390000000	1821780390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
226	\\x2022a697ec45182b48a9fb75067ce8aa0332134738a30a0d23d2fa4cbcbbca9abc06a116837b9800c3a2e77ef3e56cf54a0ced71825dfe636fa352090e47dbd2	1	0	\\x000000010000000000800003d864968760aa1f9ab1115d2ee74841b3a2018e07efe63c06871cb959a8579edfcbb213484f5da2be63041cbd26ddacefc0c969d6c89c18293f0789342a7b01b198f82d2838ddf0481fc8b5bebd9ff36000cb0f18c881e09f12e793dea5de687ef333f61c8b178c6fe0626a7e1454632144ebe4f0dcf335ac1cdb46ec5b955f4f010001	\\x177d4cb6144627a0c15e6237fee3ca91b2d24b68af40c265bf68ee57f26af80b77fb25e95a1d9141c812e8fab5e67584a66567b110d2cdeca92e23c4caf1bb0f	1653823590000000	1654428390000000	1717500390000000	1812108390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
227	\\x25d2d82c82e2cb6bb93bc54312020c541d01fe0f58b87179b40bb4081a32baa35655b3600052e81d2f6351b625a5c46d23a7ee85f047684dceb54ed1c5fe4532	1	0	\\x000000010000000000800003ad2bd15527b44d79db39f0e3ae2b8c11764ece8cea69afb70024272a9dedaafbca41e7161c65882b96ab37275f7f5cbe89a808729d609e48f0bc81f42c733b004e9a0aee32888ee6eb67a0065e2ce61bd6e197c12a8d5a6544f701b2c98442a06115dba76f6f3a04c8bd0c6abc597c8ae044be8745e3aa0d0da62d76a4c291c7010001	\\x59b1718d9816edc06954236ab33b639132df93f92b9cc7a349c20344aacc49667b01c53d693c15de7f077e1ed51bdf6a98f67540a4580f8157636e0a4977f30c	1676190090000000	1676794890000000	1739866890000000	1834474890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
228	\\x26f251644f96951b64adbfb29e717ceb5e4cfeedfe8dbd922060292c717ef5ae8a06933628344e6f26ddb525a20b76a4583f1c992d81b2ef9c0b994fc5d4f3b3	1	0	\\x000000010000000000800003e3861209084ec4ea2225a0966fd0b40ed832cf7213fab3f91b8014c49bcdb69d91d6300acaad7741830859a8843f1f70f7c0fbb109144626d659f54973508a334b7bdf88d96e6f5db1fb2d4f9d8bd95da4a739c731b2be300052a4a06d116334074d4c7e22fc09656e259c754701028199ebd9f98545c24f6bba71ce490d3aff010001	\\x86622c7e3d2f30116f023fbc21f62f88519379c2a7fcae4abdc38452f4b909c85fc4bd9f5094f11a59083a1a24dd7d1a9600e1991e2402fb9c237859d760a308	1648987590000000	1649592390000000	1712664390000000	1807272390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
229	\\x26cad40bdc4b3032524f392ed4c59022ad6a83652d7a76d66b0c3be3318a5f85b22ec400ed09b8b6e2eeaaf079f2fa08f0981af9fe22908d78b2d95b14c4585a	1	0	\\x000000010000000000800003c348e6aa0a300249e3792438f9aa03455ff8ad964a5eecc2948b80a11e01e27b6e9d0586e9b356ac9fc60b8ae2a72033d98b01c3fd58a1bad6d726f41c69357533bfe5fcabeab02eeb1a3669040d62cafe6f9e9816acbbc34edfc358eda082cf83c3cc5884e38dddfb797e6ba8ffeda633c168fabbd5134ea3307de6677f4a99010001	\\x8bf257da75c45b371a2a031d1ad9bbbe07c5087adc5dc0d903e206e88847f609ba0c46820f0749ff8abfdec78390a99819197927fe94d4a14ba5bbf50605af0c	1662286590000000	1662891390000000	1725963390000000	1820571390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
230	\\x262e5196b0f8be7f8ab30ee314c2204b634f9e2660d356906f776ef20cadc5bb0a3aec753471bfdd7b810666bbbeb8994560a2af19b4d22c76b11386222ff730	1	0	\\x000000010000000000800003c52562644be0a51a09f1c50901ce2dded173ab56ab3967535c0c85a0345c34d0dd1ab6d5a17748ed23a37ce8b7b19cabe0db1d340e21454a61786b97b9b4e33adfaeea06e3ccc9ecf308436198c8e186c36cd8b9beed2b897a1f17be00b101fa282b47a969ba5bb1ba67102aa89e9231706a631f2093c301f9243e94edbd95e7010001	\\x8ea5995ceecf58c28253ce00d9ede4dc9dafb2700a22265959b4d4c15490261d707557b3e3849f4c32167d24224fba35e2aed7ae16b0489004aa72a3e50a8708	1676190090000000	1676794890000000	1739866890000000	1834474890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
231	\\x277a0ee84b3969f63059d47e6b112327a9c7057b8f81c4d72c73379cce26e09999a64416f127c60ee12c5b7d969aa37c71cd5937f8bf2f2d8c396da91dab3844	1	0	\\x000000010000000000800003dbf1a91d25159ad9d9d2db9504fe186c58d4aca5ea2706a4b2d0a5b4a4c5dde08758ba28739cd7d2d28b33debfc0c446034c079438c369864726f3e972e758770d6a1b2ac4c2fee96e15238333fcd831f81b9d11bef49ebef60eeb660f5de542fcc2cbe9d4783c012fa6432a334175c92ffede1c772f331a1c7ce3c8dacb6ddd010001	\\xc62bfcc49892144860feae840c3e4e7432c23ac8829e668061d0b8defe8d74cf7a04669f553beef7600c8e71af4bd37cd90ab1ae762913f85603682d96aff605	1677399090000000	1678003890000000	1741075890000000	1835683890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
232	\\x2806918cfe1333536ff10df36ab101933d03fb9f48ca4848524d64b88917d06e0bef3048f6b3e4ba4fbff404c6b1bcb30a0e237520389527afbd3ec2b8fe160f	1	0	\\x000000010000000000800003bc3a7285c4f9c6ea2bee678c0493d360d78e93df54644c304269d519a26fcf05d8a3e34045417d9d8df3e342474f8a55161ad710de6f905dd7b15114717b81fad29656b53f82b8a6ad7b9df3cd147facd515548179870315c073007d7fc9e4fd3cf0b1e97a9c23b141d713c61aca967a6b93d26b9522f9b9129fd899afab1dcd010001	\\x147646f6d70e082628c329beefdcef2a8e05797095026b4d3e9e41cc69fda40ff06192a94cc92841e91fd70607945679492fedcfb5ad61f5cfdc6a61bcbb9700	1656846090000000	1657450890000000	1720522890000000	1815130890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
233	\\x2cfac12235f43505726fd5deedb391e63545b5c1f0a53ec2ed22f935235c3ec0903d07341e96fb481908b1121f0a98d1e2d9cf8c9728805d1d5d4c729fbbc465	1	0	\\x0000000100000000008000039e102de6246b2b12e6938154f03596d21bd682eec8a821c9fb836dfb66a04dfe78ebe6d327b8c3758db8b6135c5ded0888a30624cc2eef91c1f48690d95d6d566c1f10b5b6446c8f20d4734eb13c207ff8d0c0c6b64c1a2d0a7ded9fa959957f8e7be1240b5b9705e3a3bd58e5fe714d9094f31e7d6e8c907f91fedd75aa5605010001	\\x9827784bfe264d9ebf0d46e7a81112d9f84fa8d9001c5e3ecee9f39710dff76d03c5171b5181b81ca1106d2fcb46640d7ae9025f07c6cdb37fdf5ae523817106	1652010090000000	1652614890000000	1715686890000000	1810294890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
234	\\x2d3a00627cd113c9f434c0b2f5ef8ddd9d178f3fabd2652bbf6eebae145cb7cc2873376d3418111537ff23b58f2b11cbce1546f7c9ee590c7dc4f1d4467dd136	1	0	\\x000000010000000000800003adf639fc9592ee146a26ce5364dd6e6a0ce7c5afc8e3c78aa9f99f7c550ae870c8a0ffa4fc0930f1348a97546b80b245de31b36881b23edd84808f4df67ac70c09a2c12b64252e43c76e8edd3289920e57c79463b2c4f19891dc95bdb144059c81392a5b1b44162b9809f4f9242db633721089159ded13e545ffc32b86d284c3010001	\\x315a557d5694baa9b546f482a1a2ed6d7f7d3718b64d16f3ad223573f772cc569f1bae306ae7b0aa4e76cd565cf77ee36681296825d459e5ce13078ab3594a0f	1670749590000000	1671354390000000	1734426390000000	1829034390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
235	\\x2f2661963fc7cee8ba7d70d571b2bbc851e1ade947a506ad343ae7e97be4e0e23e27fd608f91383fde2d5099dfbfcf79fbe8c0da53e1c1b08093454f533d80ac	1	0	\\x000000010000000000800003bce46c2938d3bcd48f37d3e04e537d1eeb78de82adf082ba0aa48c4f79ca655d68e7be61dad3175cfe36e1d69a28d3867ffb16c46c311eb86066cca01074f3a6a4de88588216a6716132a6e82131f02ab7e01e8798bd013e62f09b9a64f2def584d091d6a7b467b2107bb6d591c1800bbfe636e1ae3b1c096a268915ca9e6433010001	\\x441a7ced752c675adcf855426f7167ad695ab2fcfed597d8b54e9242b3b4c340331cebcfc2287a060eb0b6e9d711fb0b873788f064129262bc051b8316cf4e05	1658055090000000	1658659890000000	1721731890000000	1816339890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
236	\\x34e2e272eda7b8827f071e03be22c650c5ccc1145cc373fc9e9e5db15fd7417e1c5ffd7518f0eeda4aa3ca798cd88d2e79cb05372bb2829c4c194d606b6890f9	1	0	\\x000000010000000000800003ee5950d8bfd1ddd28bf3159847439c3b7936984dcba8091f1e0b1fc132edb3c0c05ac04f5712417ef7642a161925dcc3832f1af2d4532f89897d204a0634d7b512560f37f6527214583cebdfe6ee61e8aa966931fdfd2f6bf06516e29626e8948c5ef367cfc7c532d2cde26380a69aefa85cadaa7fbd45bd1457fdbee32929cf010001	\\xedfcb85d2e74f8cf712593e0ab4bc29aa98f10e519fa1dfecff26d6ea3d904c80f6b8b44545f4070f90b09f908e2d0bbb124ef1f890f839ff6049c53921cea03	1671958590000000	1672563390000000	1735635390000000	1830243390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
237	\\x36c26f1e0617993a9c92a08c2581da4f319d003088c18deb821d3a285af3d8175752de442c5480ab8af0fdd49a5f42e12e0c6ffc8667ba93dd344aabe373d02f	1	0	\\x000000010000000000800003d5b1306d0056fed4e5941c1f7c499b6b859f16d55fe20e548501cd72bffcfb9e3682a3ed25d06943aa8af4360f2498e93f90bb7a7621633c1f820ae5c6c534ad3c96b17cd9eac3ef889ebaa50d23e8fedca07707c523bcf18f955351c8fbb11b69f1b008650699253691b74b5b9de82938eaa807933b742733707fa5eaf66d29010001	\\x19f38788fd2b7184d172f05427fb27fae5d89512b3947b808826a87a0758f487cadf82edcc03e29ce2d1f791e4d7fe4a6ac133e3f830fe3dcf5303e2f7a8110f	1676190090000000	1676794890000000	1739866890000000	1834474890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
238	\\x38ca6c2012193774a911dc5c80ff0f8fe269295e42c46296937fe059c8d6aba87d94634c641ff97001f89f6a8c8a478a48a0145a8bd6da2e700cdbee4bd7b956	1	0	\\x000000010000000000800003d32e69ab155629d4a13407963bba0683797684b45191b3f4310fcb610407640ee76441762d527a806ccaba36ebb69a37e8635d3df2277be451bdf73ccfe5e6621e2184fe1f4dd661b3bf0090716e28ce22a4f0038b73a5c9c1369e677328849a443fb0ff175834e919e544d90a2d93ad57c361e987ed4d6072e21db9cf96c2c5010001	\\x5cb110c3646eab5fbde1bf12f0f2e86841369410d1d7603f1683dcbe047d84c5962d14e64f7fd0eef5cbe16136ea58cd8bf77e689d3288fab8898df7c864e608	1668331590000000	1668936390000000	1732008390000000	1826616390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
239	\\x389ee4a3474ad652dbf0b6a9959f94622c5411f062a9fb2cad7993bc693ba6adae535758847d9295aca3fc01accbeb2ea8dcd1912ad4f6de3fc1b8381ea68b03	1	0	\\x000000010000000000800003deee16fa3f318de252e26f6d87bada0960285895c988ea1d6f947b893aa128a78708c207f68a9493877577be329b77d9eaad3bf325cab0df2fb711936b567d4260e70f4d743b54be446cc689ba5c2bdc89630df58d9b240aa19b94f1481e263e480d2922e99b6f962481744a2b31dd6a1f6512469c1301d86464e458db7f917b010001	\\x2e4d85845e16f12b6925443a26216bbd978d94e4e75c21f160cb6ad99ff78bf3ac28caf60fec010f3db871c92e03732c201300f7c0a5428117efc6371aad2f0d	1669540590000000	1670145390000000	1733217390000000	1827825390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
240	\\x381a5fc7b7c5121de9e62d03b544c04d7921525c7b3047fb7eab95147ea1b656958949e456dd9983dc519ac2ef8acbdf6d8accdccab6e63d40c31546337d4265	1	0	\\x000000010000000000800003a5da6201438795263c325e2d8c5b324f61ff426e4c842c82bd346dd03f3b5d43fb730265cc1bbeec68671180ae1ed9aba06cf5ba9ba4610ac95a3227992e69c5ac3e80ee71e0685e15d0d20e25d14a3a6e84edea186c295cec1ef4c58505b0b1ba603143cb3c6390b90e2646a8cbaa899dff2ba06461202d54617577ba267523010001	\\xeb1c590c5f80ad0d5406bbe52039815d80e93c20bcfebb926d154908796a48b445318c03133a88f9d5fb7da1a29a186f946dd7b38d16373a115ffe294403ee04	1667727090000000	1668331890000000	1731403890000000	1826011890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
241	\\x3b26fc3e0d873e51fcd46f2fa72d4b5dc98fdaacb2e2e8e7eaf391b3365e0ab17e3e3ff46ab1fb659fa4cd4dd3601985e3f9ab1ef3d7ae9709fb39fc64b8d3f3	1	0	\\x000000010000000000800003ba53285980feefdcc3d8d33a1cca829168f0e23c95b83e58f1732d76db095388c9e3930e63e7b744b269da1bfdaa64f7cb6edf2074944279cbf6cbb17814bc16d14030ad3fabd501f841a538400e81d0395a678950479fa1b151453eb3c6fd3004e0754cf94ca046476c401414a501272b213333f75d3d3ffd6aa5b84659e9bf010001	\\x065e65e02f2cc53a7cfe6942cd4a4ab5b20a100f9a2a2401878602a7be0af0bcfacbbaf2efec45cd6ddffbff6872037238bc7540c281a18372e06e40aaa13608	1677399090000000	1678003890000000	1741075890000000	1835683890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
242	\\x3b721986e18d7b5d3524b439b8c26c4c18948346b0eab9d7388e4759cc8b4f0a5f0d860453e6459b13a3aaf443bbfcbb2d03edcace49890dc23bd7c4ccb8a392	1	0	\\x000000010000000000800003c63118b02c5e5d5b34ae4763039477c58ef8f54d39dc88e892ad6e7b2f73d9b29f553f6aba93c22c11501827ab4fe8b53b9c834e829cf838c035e3422afb022ff3916da4a82a785f408ef9614e91f07c2fb914f9a472ce82259bb093db8532339961336702ff5c615340d04aacd375c73b46e9339f6aebfb9693c75bc407caab010001	\\x5adb318ef8643996768355627dd24ee88b28fb92ddaff7117c359c6f7e212e202a5b3e9a6879841fbaf871cd0b8a96c8b42665a4232a4f6e34f07ab3d146dc0c	1678608090000000	1679212890000000	1742284890000000	1836892890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
243	\\x3c4a6f8b3474aa129c118803636e4c8caefb6e7701dbd97be1098387c07a70770ea8e183238a77134a5fde5044e08125c3c6ac47dab17d6df8b1dc7c198521c8	1	0	\\x000000010000000000800003ce338752e95bed0908df6ea6f2f26117882cca2795265ad8dde775b16fcf545c8e88c82769e7f3bf053327bec7e1deb0df162df04c748a3acfc9c198508b1681e29b82f136acdbe3897b2df3361028d5f49a1f7a86d559154a759dff23a3fe57cc51c2c1d5502e0124a7721f527a9ad1d869abb9dd1d3c6777f1b611a5a672ef010001	\\xe5e97cc3459e80603734f62c96dc716af9bb1ea4322bb33caa26b5e7ba60fe51edec8d7dd367b815d93dd81e0279bf212976305edae721636848137387525409	1674376590000000	1674981390000000	1738053390000000	1832661390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
244	\\x41ba4c6ede474a7abfe6b0da9bdc687efc22b6a5140b2b2531f9cafa6bffc5955571ddcbdc99871a38b6b48ae8bcb1ee35d698fe78a795b82c3fb81f44a573fd	1	0	\\x0000000100000000008000039c20134ee0ef39060b3b7770b25094d71cc3f2b05026935f3a77278a4ee1aa83c91d7e5049a5963c90e583b7931a5f6f1bc5de7a36ba91b383c6150b906bba7d1e373a0a3b412b37e58ac51f6140bd49a6664a7d49b397dfb6753f884e9bd17636bf96ff1d2bbbda018e00eea98b05468b74e3582f624b72afd9eea0aa6568fd010001	\\x6b3f00b84f090ed9cbee7d04c27a1e481e0563adb4f489c9d18a9017c2e6dcd801f6d8c0af10d2ca8358ef8b1a40a68a8b559d79c5f8ddde609ec5c50829a80b	1677399090000000	1678003890000000	1741075890000000	1835683890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
245	\\x42e648843e7fc83ffd1f550a579319482aaa9ff4233c16d34fee58d18bc277a1ee8c2a5554971750e5680ca3d77ae1f9a1aedc56ba8e92f1c9224ba48057eb13	1	0	\\x000000010000000000800003def8be3c554ba34dc00a54343a7fc753bd8d6f743940e0f3cb242bb25f06731df78029ced449c234e05a26ebb3fc8af992ba71dbd14770118d7e94c2c4396ba3608fb0c3ec666a4fd6e4083790cfda35d715b60dcd46ced035773c6dca7e8c0da5f5fbef8ac74dca4b481a7962350d038381f6ada6d122895b66329f18b2a30f010001	\\x6bd59ba3abe1c9cf023b8458d4b7fcd3688c99ac491ced4cb5c023426db03697d4c10719d109dce03d349baec988df562e10d51cb6f4d8fedcc475f3f48d9909	1655032590000000	1655637390000000	1718709390000000	1813317390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
246	\\x42e269f981750bae653653542c68c11ebe4a459acc687392643b55a981fd2ad03c3c6f2aea232c73ee3fbd61df1a6b86cae6eeee5a17269855db61e2a4f5a631	1	0	\\x000000010000000000800003c543d5eac7d233df897aa115adb58720356220abbf88a2e57c6354570db8481bc9fe78634cdf7a37c137f37fedaa3402b62ddcf02bccf40d51e4db0d7c9cab04a82145e82d76668db75c0ec1258387c199e07f660c68e83435951cd88be5efaed6dacba1e30822b0ab2109754fbc798aeaa1a4c13edf958f7104e8d1a363c81b010001	\\x8b1b4ef57e8d0af3553db8c852d3d8a70af1ed945c63e6bce8b0d9705b11cb186f14753f536d448d1be5de7bdfac3723bfc47dba69f3b25667067c0fc4130b05	1670145090000000	1670749890000000	1733821890000000	1828429890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
247	\\x448a21e65566473aa3b58bc2e24a497f7564fc91e135ca49c8bb9213f0fbc12559b49cf6c6ef29f63850cad8b427ab5ea7b8437bf629da2132fd29e8619a35b4	1	0	\\x000000010000000000800003fb7c3a63f6cb9c10f5e79d5b458dbd2e5593c5cd02e03ccb6e827f75a24680a7318f91c959baba58e800edc0b14872a11fd3e5bae1ae8cb47f1e05d87144b704f61679396e43337b533de155647e0223648221bde65c791133b3124bd2f24ea0727bb742f0e2917050c62ca43b9447d257112684b47f5bad81a012b6c845dc1d010001	\\x71a3a51cae278a72b3a12c67536a517cf65dcd7917d89968543669db24896acf0211ca3df310f4e3be9905a857e9fcb09cb8ba8572c8eb1c64ce383187b50e02	1663495590000000	1664100390000000	1727172390000000	1821780390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
248	\\x45c2407a6139df28dd8988298f871ddb513445d74df218ffd1201f4bc63546561cfdda51f91fdfe75e9fe8cc95caf0f01b0ae1b592528d8f8df490f559bc137c	1	0	\\x000000010000000000800003e22b15d645f481ea33b42108b1291060a32999be8607a490f75f4ac58c289cf39c9800bef02b5ee559cae02817004c25022150e56a96fc6b389eaf9aaeacd180b92658b932c4b645f04215039ea47c3b3fd24396bd37181186182b4d7f7ececba7b9444b47cfe81a9ab30e60955346b2eab4d5ded71cec25e4f9beb8506abaa1010001	\\x1801c75f2fffc43b0c7ce7928bacfb3949351b08fe2ca7f429e2de3d80a7491eb0b1c1d195de75e81f0659ce195e01c1d835206499dfa38e23b4dec1a2251b01	1679817090000000	1680421890000000	1743493890000000	1838101890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
249	\\x4686f8a15be26dd65ba51902c8b9817a942d410646920d0cf1af98353cee2bd539a39087c36a89f65cc9a83837e65c3cafad05401ab1093b32b936bce8d80474	1	0	\\x000000010000000000800003b3a9a1743d5c8382332c8ce1d010f36c54e2040789ab64c6653dfca32e1c464f8415ecac4d27b2ae673f10b65fe60db2a5127e88209312ee2461338c73f172be03a05dee5fd35dd8e30114adc1fb5e4f1b9048a857420d7532696df12b9f5e3246923162a487f1e3a25e4e2c77e8dd5818b293b382949cf50c12a1a3091b4b6f010001	\\xca329417304ec730fcdb216be1fbef60c9ecfe7038cd70f86f3dc633f357739ea4d5af67553562cf0a71d5b76555f6ba7c3357b9b961bc954dde444ea080c50a	1653219090000000	1653823890000000	1716895890000000	1811503890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
250	\\x477a74f3ea06a2fc04c41bc877c7ca351879213d9de48eed952f072a707c3b86aec954f44e816687b475ce9ef8251db73240a4a8004097cf6430632dec804a7c	1	0	\\x000000010000000000800003e72e0cec140a39bd96482b4646eb3187a7f2aad0acee075e7664cb3586a965973e6ba4c3ca7f0832d060f53132457edb83a739159ef7ecf251f4735a132406ab29c541ef9cd2b74045a127907b5e115ee805dda8de66ee4e45d23a93ebf4d0545fc409a4f5f4af6590653d177915c0599de422cd74786d4d6606f9ead2104f29010001	\\x3fc0e2cffc8777fa461b9af102d87bb51b27bd833f6cbb36ccb7c0638089f04ec9e37aa67ee8a5136041862c2f40f366b668e528c6eb4534777adde032d23309	1652614590000000	1653219390000000	1716291390000000	1810899390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
251	\\x47f6a2d978ad33e1f6cd83b9602a1faf7965bb4a61fde3209183a886fe1c970178712d42888399a439a7cb604f7abfc288bdc02eac3ce55bfa6ef31d6074d745	1	0	\\x000000010000000000800003e6a28a44beda066f652c2d0461bb60eca62145c2bca83e163206486a4663373b6054ce12d3950beb93bde62998e41445511e204a255699e3ed8e730ef4ed113bcd8de540a985d0255839c274c49baeb828db7ea029bd7cf468cfbfa9d377a095d0ddbebeb3637f4dbcb7de6354a2d822215ca6a43b973a5f37edbfda3d28e8f9010001	\\x4b8e9912afcf16b560bdfecdebf9f732f23f9231d70430e66a093f4c940c07784dfcb704515684219b5fb7e6063459e7f36d728d669f545ee0a9df5d1f68310c	1672563090000000	1673167890000000	1736239890000000	1830847890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
252	\\x485e5012fe499bc790606bd52f4fc53f0bfc6a2de904363c5493e1e743c555c47328c3342b3ef941944de0e84d4966e402deea877585aeac6345340fcea3eabe	1	0	\\x000000010000000000800003ddcb3a02b1a92387b627fe81fb54f4b486493f6f73b04d415ba0ccac5540b9e536f6a003dee380fe696ff01b93ff1cb43318dd987bfc112ace0b29bb4ee509f3e648ede509460724889d184ecc2d49bb81c445eecebe819369a4d03039397811dfcd73d5bfb2bd20ead9507c2ee6dd52a1e9a9c4cf7ded004f075288457ab401010001	\\xe80ee8959e8d67c380e21296049d03b407bc2e2d40e6ac97952e789569c8e010ed91c600c83768f5c9abcd745b26355cc62c1dfcb51d21ff3838347dd6eff90d	1668331590000000	1668936390000000	1732008390000000	1826616390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
253	\\x490e825b5ca031b88bbe4d2d6e1bc1f6e3ef19ccedc08722890f23eb7f8440399162cb363dd4211bba174ef2712cf1eadc664536ed427532716325db51fedbc8	1	0	\\x000000010000000000800003c178a78fe317c04b74382385f285c197ace3cb19a830e80d156a287130b681f03a80da0db701396f53b7d2fe742592a704332b9fc08ff9e02895854bb425c40e8eb98230bd08a72d9198d983db0019895c9ab048608d5b7557a74c4d6813faf4ff4a90a815dde39bcc877cbfe1a66a3d9bd5b47256ac7ba5ca5dee5e268cc779010001	\\x97f28395a748644c8f70915f551fc38ec02af0ca6cd1583d22dca30afa50bc1796441b6f551d1d1f2f53d74c39eeb41cdebe165a07d0c8ea4aa96b74aa1dff08	1665913590000000	1666518390000000	1729590390000000	1824198390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
254	\\x4eee31f2c121ad02102160be0283167747f0c012d83ed7f732326c9e8a419d57262b445c1848d513392f14f34e64ffcd14026eec7da433ab7bad7ad4ca4d22fa	1	0	\\x000000010000000000800003ed1cfd9874598e35ac2d5eea37d204f1467f22c54242c58860c90484d9212b97bd034fd14adbb5d17b747374dfd71a2a1c68db7a80edaebd38658f64ee59480968f7f00d5c0956a5da8590946d20ec07602943327e47ddf3f6f78457d62024d8b3b0394b19822c256ae0b4b2bf2095066da3a1eba24a4e92c4f89d71830bea13010001	\\x78d61a1831674281749e28e4e46497632f59000567c51eaae357025591ad36c97e165b049523ad5f34c9807ce70bf927451f0e573e898c66468feda0b9bfb308	1670145090000000	1670749890000000	1733821890000000	1828429890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
255	\\x517a782ea9c6fd2b64f186d825f37f3f3fe595e52926d8a0a5f3056aef16ae273af778a2c32c7ea86403f0036c569422532d7ac4b83c410b8ce6a8c8dd2f405c	1	0	\\x000000010000000000800003db2b56e226d4ab783ad84e1f0c297ee7e8371cdfe3383c9e59223e4dd6b25432a1bbe81f793e11b61fcde5faf42b1f4d30dfd137345ad6eb2aa26dcb48afac973c87af3f44fc033d903cd349cc420cb752a5c6e6f45c9fbc9e87886a2f8fe56c6ae4cc89a6b56f9435b687b8e31641dbc4322a75cfb9fef2bcf9fbf575992719010001	\\xe6aaa4f15dee47c3567962cff8a5a2b9fbc1df41e37d81d8f6aeef22b3a1d36f03d5e91424d35311aec9364c14944bdd500d0ed2ed5b50dbdadda0735392e40d	1678003590000000	1678608390000000	1741680390000000	1836288390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
256	\\x54a23b0d0997b13b43914da166b421df23fe71994da2670141eb74d4c3c4541f988b8fd50aa9f0647a168011f31cfbe6e56aa45440084982423e57ad1f1468a7	1	0	\\x000000010000000000800003ee7bc1322bcac9fadb3107e862cb3cb59d8c6001f706c749306a0df98dfe2fcab997ab6c1aaccfe55d683542456a763bf320dec8b4fa6982b05b5a9c5e225ea2999310a87e52c8e899387e8846681dbf84061875e1d58f0d3591be3b7c451d080f03d997886baa2977173f54d6f6648688c3f6391beae4f5e9d08da1e0546913010001	\\x6d78a34158d3cce7d06d42a88e927aea900e122338c912552ab98abe8f24abe8f0507b61ef050b5e6e9bc3100ce4e2d802eeca4dbb0674e2ef7240b840018d06	1661077590000000	1661682390000000	1724754390000000	1819362390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
257	\\x58b2945cfeaf9611509c1cd427b4c7f04a5770a36c18d28b7e4fa3166bd46aa531e173f110d6f560969292b4b58bd65a81f3d792c05ee129831aa0df0f11f167	1	0	\\x000000010000000000800003be8a8767f9526a7be80ae3f45f1d2927e562a4477a6b3f75100a80c31cc274b59d1957ae10948c3e1fb4891fe6602ab1cfe0096448ffa436fc0b01529c56b42da9d12ed0edf2e1e42908f927660bb147a4c1e4e17488fafcf15cbe5ac032b55684f91902b046479f4e9558d255beceaa8ade606f199965684751e601a181ad11010001	\\xb0f6e05972045325e3c13254fa9b3ffd9cd2aca6424ebb0dbe59a956355abcb786b6b28b01a327805cdb4bfeb76bd60a943f3792548c7321ef72ef0c67a66d07	1670749590000000	1671354390000000	1734426390000000	1829034390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
258	\\x58aaa25fba6397ee9756e4b45408e9fa61028f2ad00921f8ed9396a7f0f871352a5f2a1451e7b1edb105f32423d309924d84461c24188e786c1f01ac65922d31	1	0	\\x000000010000000000800003d05f9762e87f9d9f4a2a7583317cdcc6c5bbbffee2044c3a485001c6b603f913da74eab4172faf01aacb3e2727cfcd0b8da6fa3c4079ee12677847158aef8acd938ca515a1d261bd3885cf03784a160e675fa81d5a82de8b67254d616aefca71d82a2fe9b357a1c3336e2f656bb46257bf7263c8f6d37645bcf348563d714e57010001	\\x4fa2cb88e2aa21bf31fc852190ae38d33125f38a2cc2ac4496787b0965e7dfc09325bc95639de0279d4b3c3573e635bec5dd5a3507d90925054343974a33000a	1649592090000000	1650196890000000	1713268890000000	1807876890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
259	\\x5afe92da1a42c2a80e920995c80e38c0626ade476d929ad3e2018c979065c3647a3a25994619f14e1d60e786c606bb204870953788c5971944515959ba526b20	1	0	\\x000000010000000000800003b4eee102b24757cb57eb6392dc259739401c1170ddde446d4cf77ea120887856f3d5b30638af9e2822e9d47084166f1fb5e3d0cdc96286a64a42a55f6e749a7d729a36c326db9dd5f92b2f492f50292fec19dad866bfd5f7130f5c108860a8cfadd919581552897503afbf3a01b7048a3d80f54bee251933beb020d0890525df010001	\\x38f9562bef51af43aee0e73543a94df7839cf6966592f7655d1e0ea4281c4e9c40f58cf659d3aa5bbe2df9e279093f3d20b3466eba370f612436cc7209780603	1679212590000000	1679817390000000	1742889390000000	1837497390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
260	\\x5b029357bf61a689e98a6946d6b780e1c1548097ae44f880a64a844638779587636664ed20578429d5389a856078b63bbe269153818e4680ee9823f725456045	1	0	\\x000000010000000000800003b959f4057b98822cbcd4c1e03f2fec33d9a6e983df3aa002fde608ba92fa1a58b00cb63f2fabbc6abebd8a2d06b6a892ead54a57909008f380c1e260c61798e503fc485ec8808d89000a04231b18517592fc287dd994b3ecee43405bd6d0e6e322ed6d23aac802ef2190150b607953450a6d0fed1414eb3b0e2d8a67736d7873010001	\\xf63dec8fc22d112939a1dc55e1b4a9a663a54644722087142b9a11ae9f027ce7db4627f06d8865d4c81fd4e57f8ab009973a2982a52099836f0f66dd64b5f104	1667122590000000	1667727390000000	1730799390000000	1825407390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
261	\\x5c66b15d68f54407927eabe8df07482b57fec9df0b199b83ee7583a7bb41487e34213b51da5c68c1f701f5f0cee9b34dcb0ae5e3221b4d4b539f3d46503aa3f9	1	0	\\x000000010000000000800003c4e5476a53efbcc72e791d2e3ba657f2205ce20ca94c1d73a267313944000f97683adcf08c087077988fd87ba12de50b8cfa47005963f4e57cfcf46a700b1a88979e415df7f9f7cb1356ee8ac1dbd8b257ea695681e6118e3863e6358af2ecf6ea7b56b7462fb9f92960a1ca292212498711c225daf6f000290d8506bd3a2bbd010001	\\xf9a0774f2f824d1c3facbece098767993d603fbc66ba2b57e55bfcdabec26a73e32b3219cbdf2fa29f455f3714818e4b82fef761398421f5d439733171fb9806	1650196590000000	1650801390000000	1713873390000000	1808481390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
262	\\x5df6f63e371b6858296e0854598e06d5c9847be6fb0bc7b9ab018d1745ecd45345e14fa094983ed3c1082bc82e1698be5d6e5923b2ef3a9bf70a1b3dc408b01d	1	0	\\x000000010000000000800003ae1f6aff66506e7ba1a2a05836ce9a05c5a36f8b45e8f4a20f34b4a08a405c089230ea9eacb40b0b486b216a1dd3a34edb4a5b599efc93ae1e7bab8a05a90f17767860ae24023205b01e7b09c4aa2c2423997e743cadb5fabf42eefe1e46898b17c85eb5e7321dec38c081d0ee30069b56af2797bf6c138909ee8a92846115f7010001	\\xb8c3a54d5d26451510d5c2f53390f85add44ca6bab979d8b78b1257a814c7a900255c018787f26ec29020a04fdd5ca46b3a76a8cb815a12b87abadd237682903	1676190090000000	1676794890000000	1739866890000000	1834474890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
263	\\x5e3ef6f2df5b1f5c3d6a4092606173146cb9605387523afd0b52b74c23a539017d6dd3826fa12d3bf2a2a4dc9f874603823116a2678dd4cd14e20cf440a75159	1	0	\\x000000010000000000800003eb979fe7cbefe18e34ea8fa6d6a33f3a15f32159b5e0f63f9e08fe0a1078a3c52dda5b4458d2a122a1b5696a932fbe5cce549ecfe4146ae68f455e9934421b5d24cba53b6e1b8e72ef735fd0e38cb58ab2153e046555968c4040e7a649aef4fcd284cb9144a0f485480a3831f232a67b0288b13cec253a694cb558f2aa07951b010001	\\x3c061612feb185acff5a199af52187dc04c9ed8ed948f5be6479e2b0f0437201fa8710f2055d4272fae955e1711c63c3e95aa7bed3881834e8d907530016c00e	1670145090000000	1670749890000000	1733821890000000	1828429890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
264	\\x5fca7a8cd18c36768aab5a29e38ecfd42c8e2771110bf5147ad5d8c074caee9c2607ea4a484988ed236dd8f3271358665fb595d84434bdcda3e21cd9ec21a347	1	0	\\x000000010000000000800003bdc7ac64c1b30f71fccb1467174387e750888b2fb526cc2142aec7c907ba1a42e261070a36ebedb8f53f86a0e83e6fe23ee55f10f9e5eb658120023a80e202ed11039ddd8059b8efa4cb51fe3aa49540c07e1cf14c7eb08b64b1e7ffb527d95dc454c81de3b432795590efa5d5d2c7a8a42c808983fd6a3907ac52f7b1c8819d010001	\\x82f0357584c811cfd6805524c0e8af5d77390ea85f984ba1bb8b5f8100aafc02528436ce6b1ad28ebedc973f8121c26d686e76e9c86e56311d5093c61a4d0407	1673772090000000	1674376890000000	1737448890000000	1832056890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
265	\\x5fa2551f2ca742f2b7bb920fd4bf53ba176100f220d69e4e8e4767c3c3cbebcd307cedec2133ad3e06cfce168c5b36eb1edb660f5d4720311f680732fab6ba54	1	0	\\x000000010000000000800003b1f8d93a164d07bdb2956feecf8d83257542b18a0990a5336012526df77a78563f6cbea5a62a50c53f4553fb37f053f039121374609348023d968e50b11c9aaca179d232ef8ba399854a1613a23f8e7bdcb46036e837c0b0060161b11b8a4e7648cdde38ac8d281ba1d6731e7ea2abf5cfbb36a6a2a1f72d9e9ad225b3eea65b010001	\\x30e14dbb3860c633dcb6fbcda3b3cfcebd5fe8c3596d010807d6d0ba9a39ed7fd3c41725a095f61c2de97eb3f9ac21676edda3f6e0f3a26d1ce95bcf37484503	1654428090000000	1655032890000000	1718104890000000	1812712890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
266	\\x607e5fc00684309eb4de51416aa7ea580cb013e62ccbf3b400cc3320251aa33af17956bf4159280cd1b132c0e5d088535116611b80b4b645d5aa9c3dc1b13286	1	0	\\x000000010000000000800003c9e2e55d5e1f233ff88b57305ae04f85b2559913645872fc7b5ea29e123e2ba97e3d85c8d5364342412f2e275954a298e990452e51563391710c01f7d4d95eeccbab79b4f9888392ba0fa1f48bb0e15ee9e20a4aa088c09e1563f882d03f5738cf123708e052d49aca45002cca8419a7e015137cc2238683d98f809d14ce8a25010001	\\x4edb993878b03d8e3422fb993f2ca07c338a6a39d3d646bf9527bf6a7340d0dae285223020c0bf23b090d8b2de33971435e11194dee418a09421087b1b0f0c0f	1676794590000000	1677399390000000	1740471390000000	1835079390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
267	\\x602a3612a4eac99e2022940f338fff8dec1fdfe19873ece18a64e04cfa3654e7ce64d8291f7f97155669b28223e1c4cba04f03b77b5411bc08b83e207847358f	1	0	\\x000000010000000000800003be096a87673da797380d45782941ba275808886a8c946c70a7d7121075604e837c0e6812241237a86e9afaa015e9916b936475469b0e8cb821e154534e342f6ca22706f08e0ca6394823e2e16e2e4bd8c09f003aa62d34da38841465be83db8d5f4bfb5a9000ec0c95bc479a0353255dd4d054b2d01f96bb36d8933443cb1aef010001	\\x9675d328bb8a361c2087c49dea726c5df78b477040d7623942349e29eaa4b1d4bbb4e57398d5c552c98d4bd5631e146670c8834fc1e716c75ce050d70544890e	1674376590000000	1674981390000000	1738053390000000	1832661390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
268	\\x677af8b9e15be49989c55e5d875454bb7c1b03e735f15c9882893f82adfc1b8d6704c18d671fb2a1171098f3951be7142a4304955850eb7236afb79ca9a8bcec	1	0	\\x000000010000000000800003d100568eba542030dcf3eb45c9c49969bc5743cb459863b94fda507d04bbc05a6fb5c5d4dab0a2315f0db02ba6ebc69df851962e9eb7ea098b4ef80e931e866caed5d8bc9b88c1a40fb8fe7b873f9574a7f6e3a62885f014fe3e07463513a914428047fda813be040d41ff2aa37c611267a16a7447d6512acb6a0937818c2985010001	\\x18ebc6297e91cb65b498df81e7196f8b70786b2ba6007e35c2497485f6e23b2293f457e0f5fd446e94602483bafc2e3d4c8b9c5aca42faf726ed111c26016100	1668936090000000	1669540890000000	1732612890000000	1827220890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
269	\\x67cea3143d17e1fef43a3d573bfb6704d69ba38b7e4068a0b5515ec50abb77055f36aa3ffae0d05a1a34ebe9df5ab0c365441e9b4836226133492add63e5f164	1	0	\\x000000010000000000800003a7cae2e70f82e3ca342e29387abfbc21abf60319e8adf7be9442e3bf4c3415644e6ef5c926f1eff1bf57294acf3bbd3aec987e5ac79f3da1000269c96bc4659225e6d57ffde96f5ee2460689898dbbde58bede09c6dbef08f8242ad3dea42215bfdca857ca467fbf7076f93f38e40796bdd9ab0ae55184e522a1ff26afd59349010001	\\xc967c10de8573c66e2f2b9e89d12f37b7a0973a87e7457e4669daee72286cec411718f3cac1720b057ceec90cd0198d98214db4f30611feede3fa54ea0d9d701	1674981090000000	1675585890000000	1738657890000000	1833265890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
270	\\x6ffe9f7f1175cf23ae4183812a96dba5f156d04596a377a64000ab9e92e4d85def8a4a79c57ac02cc4269519c2b92272f86681ea61cd1fe5bb0ab62bb9cc3441	1	0	\\x000000010000000000800003d82e96472d7bed1b9cd1a2d13077ab5f4ee177fe31e5a77180b5827a892d3b8b9dc8fe8968b59d668ab81cc5a016442a6516f4986b2673d6dde17add4276aaca11a44019fb6890fe0fe6d52d9eb8d6b03e47e79b4b3fd0926a648bde62684bdea7b01562e3765e0f821ff7d1e77411679bf42165c18060b89404f1f037fd26d5010001	\\xb72c5b2059d393af372c62ad5142d47f9909605ff29ea256ba4bc6a97ed32166b46a9e943cbd9809393528db6c36e4f689d1df81a56f6eed87c0955af5441909	1661077590000000	1661682390000000	1724754390000000	1819362390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
271	\\x6f06aa842442a826cbbead9653852607f02a95b80ce8596c3a8802fbca4182f899cd17ddafed694493084ca5e7ccb61ed0bb475852e89c1e5c0a60b289754093	1	0	\\x000000010000000000800003d4ec304ff05070f8bbd8347fd59141059bb258448409b4f6bebdf2e64ca25f5c7e24a617b37b72c5d0fcde3a3cea32ae9a42bcf10b56b9632b0d0c93b06fce22a233d6db325a39e30e4bd2ca878bcc580f4bcec32eb8da921ec1fa034eaac98c1c4ccbca8ea615b3f30d25d01f6235c1698f3092dc1c1b2607ef83cbb233d2fd010001	\\x2e7a6a92ccc234e7b1dc47f417cacaf6c755fc0d28f1b2d7806414009fed8a6ccd91000416177fec6c511c539d8faa6d3170aa4df87b6229a56a89cd99c5590d	1664100090000000	1664704890000000	1727776890000000	1822384890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
272	\\x719ab5d7926cb9e674603fd49d007fa2162b5ed15ea1cbae08154aaf4624250e86cfa32bc27c8ba7b4e35e76fce4305e96ff78f906b11c853558fac2a5937465	1	0	\\x000000010000000000800003c9f617f70e0c1426a93c407dd1af134a15ccec09eedff251fd5e98a5b83af096c8f9ac1ec0382cf2bd573b0b504e0622c46c75a935bf06e0a0ef2ee83e780551b402ec7521631f3440b2a2123563b1a38a5f14f97bc8c6f4f31f7fc30190864095a1cb4158faa58d7e6d0ebd82d6a1ba86ef12075c5bc67992912cd122dbfd0b010001	\\x17743996a5d72da6945a4cc5692b955d82fd5182e20ac3ca6a922e70b1e66cb8f6fe3ed3359a49ec518ca4b1387d7a76903cc4c9ef671df560f66663df150a0e	1674376590000000	1674981390000000	1738053390000000	1832661390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
273	\\x72b262720b0de65e5b62d7752ede0266e5297db04da3f50b06655de92d8a4a5d05243fa18493a4ed61924f4e57352671018d120299d6e4239b3f781dfe1f3177	1	0	\\x000000010000000000800003f1bf1f5434dfbb818a2969e988b85054a1ba3622893059b1f1d6b10383bd2da88334a1340ac8d3cb01c30e49ca5f6c4daae99dc45a527e0b8f52d55778dbaf56a1a56f2aaa8cb86042902c2b16ae1ddae5cccbdb8877a20ecbf81062b91e2210c1562ce643dff9bebe30df967278fd03f0cfec6433cab5834f018fc75edca259010001	\\x9bd5a5d084046ab738ce3c710d22001b6738f01af421279ab57fb390bfa8908140a0f527f7dbdd61037e90aa0b5083b9a7730127437852526af8cbfda15d0507	1651405590000000	1652010390000000	1715082390000000	1809690390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
274	\\x7a6620af388ebe0180a3f6c306a9e7ec82f07dafd9635c723fd27f3f5ae62e723fedc51fc7276814c2d32f21e41ee6c88ad7b50e7c2b622f0cf20138ba2bd581	1	0	\\x000000010000000000800003bdaa6b292118a1bc4c18f56fc161fdc55759ba5176cdab1e8f2131eb376585b593d01c1d2420ff88a583936d6990a28a3ecfa012ee0e8a868025af4e02e8681f5e2b7bf6b78ce1fa68b1789e20b12c5046e6151066752e2eb1bbb0b9a2c3a55e3c81e063088e7ce8f96abec775af13e3daa0bba13fe57d4779aadfa5b0630c49010001	\\x83c6388bc09b19632f9a3d63c09f777397573c2cf7a691f0ea085389cdd660ad6aafa4c1a46bd01f6fbf0deabb8e0878181425aeebe7f48fba51db423da2e907	1658659590000000	1659264390000000	1722336390000000	1816944390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
275	\\x7baa18772f278f8b1773d3aa754d6374704761165abb751cc338e015edfd9f86c3532a06ce6e42d7d788dc3387bd7eaada0eedb90909f7ed873e243ff3bcff1d	1	0	\\x000000010000000000800003d3ec07694e40dd143691d4ec98396820c6c458c1c4edeb6694147021c4e35c0ca8d33b20587fe7b6ea8149725e8ab1c569a5f1dea68a3e3e57ca1257797232063443ddd0ab69dd9c14c22419546fd77a1e9cdd14937a337997588413d5a79f90e3762e3731ec448d806fcc9b79e694d46762c6d6b48a62cf79501c7823bcc21b010001	\\x56422cddd7438f892f2d41f54dcb28974b56a40afcbec0f2c19061a03608b66cd4342a2bd6e9d6d7761839d9c9a01fff434f55ed738e7b7b04c599ca7d5de404	1662891090000000	1663495890000000	1726567890000000	1821175890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
276	\\x7d82141dfe6c3178f640720c8dfdffef329e526919296e779dd0e95cee86b500b1c47b94e8cff49490ab723645fa1a9bd3e22a5e462732a2896b25d20e0b89cb	1	0	\\x000000010000000000800003c484389cf474f00a142118f3d71b9a6496dff4db22cae16e5e889c117bb10936db747661ba77360c7d9c938348ffee1e3e1eecf044a94a2c0be991cbacf86a586eb946f03938c2fb695565c7c14e163e5c5febe6af241158a5c897526e2f9cfd3bd7972b1299fd8ea41b7f94fbb4bea12be318db20df9af5c0292ec3cd4a8d21010001	\\x9dce7e532ce5530feb97ee2213eea0550ad16e27d2cdac7997f238b2c21301eb28bcedb449f66bb787e3a1d77777f229559799e384fbdf4e04ec871657440705	1662286590000000	1662891390000000	1725963390000000	1820571390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
277	\\x894e8161cfa9478363a6b52ab4f4e9abe84e87357dbce89b66d7ad781ebcf3a29ef05c89e8c94bb2435f198468ff342a0d54227ff606315d4740cec0460d01b0	1	0	\\x000000010000000000800003db849dc319e37509c8d237b2acfbcbfbfc553980cb21165ea1c1d9c12c7ac1e2958261f07e171dda818a354d47bf11dbabb7501bd5e1af2bfa38969bc1d0ea37e94463ca3a3a133f1f3cebb1288f5dbf50594d3abd156f53a19b3bbaabdff32ec5eec273d00b3741a07cd5ecab7d6e033310f3769da45088c01ffa2489344333010001	\\xb4984e26b712d60bba59207850b60773d15ab56a2dc5b7a8266105d1007cdd18a69d2dc63ee83e29e83b277a504bbb95d019394db84415ed103f0741a5226801	1667727090000000	1668331890000000	1731403890000000	1826011890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
278	\\x8d367d57f59a75c83fcbd63ee9bae66bda8f39a04b500ee11266c4fd2dc8c191e38a35f3c04cba6899483c6d583adc561e86a286d176af365229507d6ec1248d	1	0	\\x000000010000000000800003bae444853ba22c0c82512bb6f4e7fc28e03b0db946bccfa33aab29cb14b557c1c2fb4fadfab365d7c5f993e364792db61c6c870c409a06845cd87ba3a9eb3be27a06fefc3f99691fcb28cc8ec10186134930c106aa13c03a023bd5f7fd65529f0256d1db9e05f1dddf5c97c58b9c8c6218e1a9cb44ca73f12306ceb6bbb74a45010001	\\x9d9d03403f171d5badd0c92e10069a803dfef26c8a9134bac3df8db602fed5096cbd2de8c253d9111bb73c87ce5fb3a52278373bd0910fdc1cd06207c7c80b01	1665913590000000	1666518390000000	1729590390000000	1824198390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
279	\\x8e86c96b1c9827a92a02ff67a4b25add475330d040e0882504abe6aa1eb0673d6219f2ffb5c9e243e9f88bd206ef9bd02d45d668e4fc65863adaeda5eb8c6d36	1	0	\\x000000010000000000800003bafc4523a9de7cf88b0fcfd97c0acb9ec40c6467ed825852a4d2586211b80e9d9fac169344768e7f0a6044d11e66622c3d3495b61a2f744dbce4e3fcdaf812003376d3b0e36b89d605e6cbc2dff2d46e9ec24f29f3eaf2dd1d99634d5c0e9cf14705955abb13931d66062409c0c5c6d1e368845f4520fd0d2c6fabffad72c25d010001	\\x282564e5056e96dadf7676123803759743e1be95dd2f5be23a0cc5594898ba5a4130e75b661ca7d634993db107ca48df4a333935df074d112ab0d7a96743e801	1650196590000000	1650801390000000	1713873390000000	1808481390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
280	\\x94267b1671dcd3e9ce300c94b7bc39ba1ca5a447cf9f50c188ff29c8e091d10ee2faf9e414a53a2cb2d83fd1c123cfcc60b3305f8deffab074c8e36c210cd727	1	0	\\x000000010000000000800003c4e850d475b06b705e82d60f797d7717b449ef93c3d37eec79b560fca14ed16378c6c6a9440cd2c591faca6f951c0c6132d71b9bb50130b3b91de39ed2b0de15a7d271aad7cb46849332dc66d90193ce18c947faf5900b49d45327e7e70e4894276394fa8753b0914902da723e3286249d740c9023144dfdb9915e2a710af64f010001	\\xc8e4776281f22d4697e9f3c961d6f6ec567b4a2c6163aa57e884aa62b697f07f9b7ba9302bd34d0d5047a23133d5caf3e80b76b966ff29973dd4a418de152109	1663495590000000	1664100390000000	1727172390000000	1821780390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
281	\\x9832dd74ca6c07ef4650b5f80cb45546ddd0c781181bfd17a67bbf53537e1bc7b69682aa60915e41c39157616635c016cbd0a42477eb86ce5167fe07acf51dfe	1	0	\\x000000010000000000800003b2141f506d2fb89ee0ca1c118caefb5e8b7a45ca346136506a92e5ed3ce34e07d37982ae1637e8a9b3deb04a24eed69609abbbecd939186b866132c4f03b95a7e84ff430306e785ce392e105e8ef41ddf5958354f6ac97dc15ac774b8e7c2357a9cf2cb0f3911adffd9126cc466078fe861539d3efb168d896ba08f12c3eeab9010001	\\x750af7736b2ce889d2afe057386b89298cec84adf5121e526818e28947f33d9df5bc8d2359a1800d7c1219fa8fdfed2d3208c8f9feaaf6492f0fabf0750cb907	1673772090000000	1674376890000000	1737448890000000	1832056890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
282	\\xa0ae8770b63ccc1aa35f62f8282fcb0564d6e633eebcd32e9b2262e1688783cf2a05b634cec190161e41b25e4a62201994dd7689cc89878e17b8dcbaa1af51e6	1	0	\\x000000010000000000800003db9d4d998faffb61588a3c75f22709b0063f7b574cf4bf3c392c02c0c47a471f09a2f56a6c6a6bf47c4c0b22e5378f23c472c8486dc46647710e13a557b120d403ac1514d6baa235c3dbd042c4a7df6ffaf77dffc8ec72d410d7d09d2959f8b095374a7b8bcc2410c40f3f2518cbbce126c8332663ddf5130a647e0e4a764a9b010001	\\xcc2693b99098a240c43853ce0c032b4df3aafa59801150ca71fd5901e77bda86ff1edfd10521f8e6f0c8c0352158f5d13466e9d231f150e68f8a3ee42d61ed0f	1648383090000000	1648987890000000	1712059890000000	1806667890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
283	\\xa1521ad673678b98fac878e1f7ecd0da21f8b3d43fbb388252dbfc89237367a674dcdc6082d18d9394470e53f4629b72a1bb752b111b61f9eb99ac5f4d507df0	1	0	\\x000000010000000000800003a646ff8b827440cb754e38b85b59af98bef73b398ab038c476807dfc30b0b884c7ea501d4738ae213bf49245303f905fa6cfe3c88218c284b27354754f3fe4bb31a08ff6e6bf2b7cb7922696a35855648438285b4e45449fee0f27c6ac4e38bae886dff139f56164bc77c8f463fcbd356851e8244052b15c5c8b7018365cd7a3010001	\\xee5043f72a5b83baa7cbc99142a871284f8949387259465a0fed57aef8eb9b17ed7057e713e3d8106830c183fa532ae02b5b8f74b477ea27b794ba3d35131d09	1657450590000000	1658055390000000	1721127390000000	1815735390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
284	\\xa7b2a8645a2ef388478dbec715af8658d78b1e23160f88e6a588fcc5b33bf1e77df0d3e2b7ba54ad131ef5a4d857a7af07f2681f0e123097cc2900156253f42d	1	0	\\x000000010000000000800003e259c39d1a39219808789a001a3c4a52e97fd12f7cced671006ecf1d115c158554ddb22d518f48454abfa515561384ea8ca86feea93c332518ad3018b5f240eca44b5fc838dadb53155d54419d8449ef4be01591b064df90537f7283f753c0f0c08730f2f940655653c65ce26ebc6da567d175dd38df636229e59910a7c9128f010001	\\x5983d44cc6de6a3b639d1edcc582bd76b2ccd86f7786bdbf2d856967da52b385abee7139437ff93222c8262b164c942400fab99c5960a0cbd93ee85e285b4405	1656846090000000	1657450890000000	1720522890000000	1815130890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
285	\\xaa46e188cea74e07b97608e51c971d6a7e913e77ac4cb49b529deef23fd70323baf974b4ec5ac83c03b367fb53f8df57d9eeaa0bb3d98cc58b143ad870295972	1	0	\\x000000010000000000800003aee0b8950ffb29587389462a118c55b3e85d7626b57ef4c929f2d986d9ebc44d39b7f3fb52443b4aee35e013a521dd3a3b4d02a05d50ac276f0bf68dc25978e8188191c0427b200fbc1e4c1c081200c7704bc5c8f2c774accba77c83e576ef137d78f7848f1af0a4df2c973329c52e9bfa70057ec898c05b39446c4da5562b95010001	\\x887ef9982f69051967723112a7ca12099c2517273a258caa55d6ff6e3a2a71f2f5a5fd62754b3608ca1336f3dd219735abb2441a3509f61becd092158b84e908	1668331590000000	1668936390000000	1732008390000000	1826616390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
286	\\xb17a251b642c520f93ebda7a11f070d7b51bfe477759d90c51bce1b8946e8bf0dc4df12ecb3376432546287df354177bbc98d4e701ce1ceffe04071d15f76548	1	0	\\x000000010000000000800003d4ba5a31cd602e11084b3f8b6210e84618193e204d6f9c002c84de72b7ebad753c4613c615d91f3444e98fc506538caecd2528250d63c61279b6cc2a48b9c57b839d89ee75818d5b52d7f4303fb829c25cfb3ac76188743899f75286ca823dbd5abb2a6b71759f0973a7bce2d27cc387d4a2138f9245655e5ae5e9c8998520bb010001	\\x092447ecd5e692ffc1c5f19ab5168665ad5c3e52f860a11a5443886bb0dd48982f600468fc8b58666d58febe76bd17374c419223e52c85830f9654a3e3029903	1648383090000000	1648987890000000	1712059890000000	1806667890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
287	\\xb6620472dfd0962a66bb298b861ab2713b886cefbf4f92c6779249b0c1b3b112ec196de7955c8a79c1b7d6f6b6024fb372f4c9577fc1b712264a5f5116e0bf34	1	0	\\x000000010000000000800003e53294e0196a69d903a1292d55639edfddc8982bca59511e993c3d440dc7dcc2962183afebd7bd23b49aea84af1d0408e9f64a3e68ea6fa27b5af36568479221925a69581b7ec3810a9bdcf8ed882fb550e5d3a6f6628fbd4df7a0bdde9f27b65c9187232524b97784cebef557eeb8344210979e21f8d7578d42f6bbec4bcaab010001	\\x0270652efc5a1ef8de91866bcbbe655ebf72c9d448e35a4f4a4f82ebe5db7d7458b9e90f9edc16b375e194fed30a67bbaa74416c446bef201e7cea10a833e603	1651405590000000	1652010390000000	1715082390000000	1809690390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
288	\\xb7024254db6c28729f602828ec75e7c569e02396256c0dd4f012e47dfc12edbce23c54d27acb4ea6963523dc9cd186817227f9f78e9e436b247efad6569f37a9	1	0	\\x000000010000000000800003aaaaff7749235cc633ca1c39381b4b7f45a3a5e005005d586837a90daf4def6353a61beb1b2617da99757065e8fa3e690598066b0c5c3659b52dfcbb367c2655b157084018def761808b2e6ee831805c1da1245d67456e559f1016f43086bbc8096c952dcd06a8de7d0830690ed99682b2713a533a53e05f231e13a79af24e25010001	\\x291a17bacf2cd8180d9548d67f4a9afc54794c1ff452a12a66fc67cbf0337335f5153dafe90aba60fef873f57cd186ae4ff32d8964d48862aeb0f609af4b1601	1679212590000000	1679817390000000	1742889390000000	1837497390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
289	\\xb9d649ee94be8430efc968cc03157dbb2f11ad06176fccda95aea69d8e9fedc988abc5fd594c55b0ce8c544120ff11b1a4a94b3e5f2859ed94e2af62d0a74446	1	0	\\x000000010000000000800003c8fd8eb097a5b5b94d5bcc409b12631f704a8c98773ffcc33043feb7a374290ffbd44b3c1f309ec6fd7309675236db19b48e0470e6982a88669a44aa902a234b5877f346a99b9049055f78d2915efd8c3b3f5f991a563ff0ef3be37b5c4f9ba7c7d36b528029ea4ebdcdd78eaaed1dcc0b297fa8e1b6617dfbb059adeb161af7010001	\\x268bc51fcf7a78741478159d906760a262338a9bef82e63bc20abb69fd80344bb2cd043f0f12184d30b6a6bb9ad590b26c9954be40296437689cc41295c68400	1648383090000000	1648987890000000	1712059890000000	1806667890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
290	\\xba02422d8132166cd19f265bd9823bb04b9ca650a4c35d47fa80afde7ff568cebe1427b0f6afdae642ec49958248b8041eca164a4cedcd318bdda767610b34b0	1	0	\\x000000010000000000800003f2a5caa1c9e7c7e8e862408ef1ee550bd91bba7cc252e5a076bc93333fc456fe625105dc15afbc189c60fc742b6236ac3205311611e81cf80e69b83af2275140ae7ea0ce838f38dfa717b0f4d14c6ec55183b213ee4422ee2e696f6ae5e73fbc734425d7240cb52227c6662d591957c41a9c2ecbd988d7905ad2ce159a2ed9f5010001	\\xdcd5c71e537febe8c64c4c54124f128c38760f28fa293b958291399dd8de39fdc380f63ebad43919b2c584576f4bdbe5784da00328de06e55235176c50673600	1653823590000000	1654428390000000	1717500390000000	1812108390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
291	\\xba0a93bf98f53a6c56b0ea2c7de6ccbd2d17dfaf9aea24200d73e897aad9c5d14ba56add02c9e5e081a01d86962e16464b294938572cfc6d14aa25e8dbc6f8e2	1	0	\\x000000010000000000800003d09621d7598a7f9964bc815f0689df0d8fb3bab7f62535d4a8a2e299410907b31e8ba6ac7e51df425dc5dd9edea822f248736965ea89255e6705f22667bd7b4e25e7e09555d18b07f29a72a35c413ce5eb389edf41631ea240acac292ce9fd809dd84e8090707767759e9524ec406c69c41bb307487856bfcdb3b3bb0bc95823010001	\\x9cad3da0b5ff6dc0dbe65f790381a2673d4f880f5b23216c9d433f7c8d4012afe2655d81f1682caa17db1fe2ff6a028b12308859eb35f0ac996a231fef509203	1649592090000000	1650196890000000	1713268890000000	1807876890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
292	\\xbbce79b5d034022a8886b1b7dbe960d4054db18e1c34a2c3220504e72618264ce6ea4460913b4362ebf2181f76c6dd8b4d14933efb356d1354932ef41864fdd8	1	0	\\x000000010000000000800003c816524bb1b3b32409162479722cc82a638a9dc70d55376e4df80e58d99aa672ff3332ca2c01686d954f7dbf5c8c417408daa89c3687760a7c59693918c66e08fcfaefd31b61176ec17d4b57c70cafeabffd80362f2f2c3ae844e3f6df9c72ab3303d26ed8f56d131119d852ac90c32084574804b66483aa7abc337e64a9e16f010001	\\x2a51b06f769672e0c069a9a32d6de75d98159790ebf5eba62f313ad067cc703fcaf3c1b45e7af24e3e3a2a7aaaaba17bec94cec17fae7edbad7fa621b6c44d0b	1677399090000000	1678003890000000	1741075890000000	1835683890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
293	\\xc026071cf12c54adf23ed42eac2772aa69eccc89757bdc51b41dc94406c3725d54b1dee1651f99c7adf888125bdde560a41d6d4bc9653fb4f6efcf3c1b39803a	1	0	\\x000000010000000000800003db3cc63d1481d2b8a8b555328047c17ff24fdd6f3e474d90a4362829254bb8972f273c14c2568b7ef00503655e0fcd786ddcf6ff99a2bc7ad0c2eae99cb0160a95a981596c03b76bfd2753cb9e7560dfc851b4e3929d4d9589c14947644701a31f084f1dbbc49144544916a0a80926f99d06c38d9016a03ed2d06d680f07c27d010001	\\x1a3260556ecc8f8b59b1d401961e4dd841be768580e1b11f1d435369eef06ac461474461c921087156339cf45268ead86f4195aea7dbf4cf4eded77a6f6ddf0d	1658659590000000	1659264390000000	1722336390000000	1816944390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
294	\\xc11a48e56e5fcd8673ef6d57f235709fcfb35f01edef8e1c2d18f20efbdba6bb9a36c45c0de602213cc6bc68bc6e17a102fc4e4ae2c32dfa60e26202879f1c1d	1	0	\\x000000010000000000800003a9322aa9abed97b52de8d0a8abf09f3b6eed801b218a3947719964a98f06f396d7ca0dc31d349ed24f129fb506901063f01e0807f55d71b0370353d298bbff1ac27ac95762ba00a26636c0e2aed737362583c753923b79c5abaf1867dd62da6ba770d3780802514ea2275c5c5fef4c8942b44b3e5d9ec2505bbeae3cfd58d7d7010001	\\xfc6f7d2936c78c24887e2b52b96b30b7ab90d35a02723c992adb60189ac169f9d5891fb2f13c7bfe9fe10c309a5431eb845254fedb9ed436049471f7d441f003	1650196590000000	1650801390000000	1713873390000000	1808481390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
295	\\xc9321d02aa399ee878c6cc06d56f7de3f9cbf12765de134340d75d594182a5b2943510c417d3ef3a0b34df91af2ab0e1f16ec7d3d82c12da1976873444444843	1	0	\\x000000010000000000800003e0dbe27f690ce0fc2cab8063a40efae5df00703cc68b13368c0e798293bf2cf96c597a1485d16b98d274cb07eebb47e56f03dee7f76e68e8e9416892eaf4262b5c921b81b686fb91b145d3ecb3e3d6928a6aa5885a1a6eb10dcd36672458504bca1c1cc2b06ba569909e2e928476804617930c278068ff3b231cfff1b41bf323010001	\\xee6f1f8f47398c877426645304c9901395bfcbfa7abd3412590c3d68c56ab01cf63c0c05592f0bd95868ab2322fa777e61c1b4e980c07c173f8771831f50b70d	1648987590000000	1649592390000000	1712664390000000	1807272390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
296	\\xca3e08b34da3765d7c631f860f862a36c61f0b719f45e53dc39e643a34dd931a5c28385b57c7e6b1164e3078e1d93ee58203204d75516c54e07d148de5394320	1	0	\\x000000010000000000800003adf265cb1e1f3c8877c81f89d1953a9303f38c9bbebb7d4e7f2337f4cf965f9b7dd285078684edb161fd673cc6beb61f11b7085b0a452b318489f34bcac1c11f6357f0ded6f1418cece1c4c83c4a83d5456b6311ddb8d77d83251ea4c7cba18a333a8c75553a45752a42fc94caade7cd8a167634642b62ccd8e985359bdc8f2b010001	\\xeee7ec5e5ee6ff0de9780f3f116d9cca94287ec90517ef7c8a191a3b358efcdcb351f1d7503707c6256f36e49e1c41326a41320a091d00aac653ed7f16f61b08	1664100090000000	1664704890000000	1727776890000000	1822384890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
297	\\xcb0e5d6ec83f034f5f6fbd10a859ad9878f55dc61b3df8ae51555f4ff4234e0c7adc7e036291f7d18ee30bcfaf9f2f23580d3d33e43d752893e650f2d376e55a	1	0	\\x000000010000000000800003e30ae4cb7b396d4768a6240115c3673d5b0ab3841207f9e91f8e2187af3022c153e23870b6f6f8b80cb7037ab5e141d8a4a3a4d068091a12fb9d22eb4a48125e644b860f72ab58a3dc43879d944ba2bb99d39accae4a4028fd12ebc9e3573ebaebe02f42fa1ee0c63383d759c6c32aea635436675079d2ab33e4d66781484e0b010001	\\x91d4ffe2524021c096c2dee14bb97411f18cc60b347796fb791e17a072dcc4d655903300f60d0a49b881f2f21c8e858e91166092dc55cd56f3d6926eac5d2306	1655637090000000	1656241890000000	1719313890000000	1813921890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
298	\\xcc026f4afda01b22f1a2627e556595714a5c5e6b331ab7b082fc7ad7146a42413e2dbdc659ce0cb6f025148ba329147ec164584f7cbc2ba92737e9da958988c6	1	0	\\x000000010000000000800003c73e6ebcbc8d4c002330be270ddc1a5ef56ef19d6ef8f7cf58fc4f7d40accf80a5e23e314de493e46ca34b618a4a5bc0bfb0e230e64c86b0482027e803ea0d8a8e2babaa894b78296117f5a24d46f8954049f8a02265f2422edcac46f05cecd53028f0a8d117636ce8d2e332d706c0a3d5dbabb15a4ade19020564fa3e0065ff010001	\\x36680e18db98a552749b4271b142d5890b785ea4d17b8fc8448cc9c7ef6b8f3d975515327b97fe84c3cd06862b27df9c75a7eb538c0b56d3bfc3ad8db6baf408	1664704590000000	1665309390000000	1728381390000000	1822989390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
299	\\xce869b44218f741d4c8790654a3b693ec26020b80399898325c64bb11158b212f6cc37343e3e1264405f6fbd1dd488a538e8d129d5d02df06b0e0009f460f9fd	1	0	\\x000000010000000000800003ac11a01d87844f2edd37aab8a45072586db6fd27b15d3e7ebbfc5df18eaac30e6229c77b1f7db12ae8d5497f189737ef1713338e185bc0fc125621f6c5a9077559293cf8d622f142d702cdbf060192f757d4bde45ab2ab947f95ba380e5dbbb0b46bc5992894c6dbbb9860d8a748cdd21d9324742b8c5762d2a81193d199ca73010001	\\x9ad0940ed11685fe3a6a780221301956d02c5ad707f877c5913a3081bd6c847064764325264ccf2a9eaf4287c234343f908b247a93286b1997ae46bc3dacdd05	1654428090000000	1655032890000000	1718104890000000	1812712890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
300	\\xcf4e96fdc187caf296918b2a00451ef1a104267841854cc0dd8cebce1a86f65ff1d14e65958af97769e1cf5afb1172d7f89407cf9ced0b8bf7d66b8ecb4a0008	1	0	\\x0000000100000000008000039e70e170105a744d5c3f3191922a772e6f3e67d5124b1c3a5c15d7af7065624935c499bbc7c541ab9b647b5c5f15e2c73fbc1fad3bdcec37b76a4321c4b40bac81446b22a207076eb7051ca0abf3e96ea16f0b97cde98f0828133a7cee143410762ecb13ae2f34db6d9ea8256fcc75ea8ad53b42fb9a1d8e4d9318e0283c6547010001	\\x2542c8043c78a53de79c347806ea44869e2637755f4397110a282d79e991aaf2dbc5949ed495bedc9f483a95d98ca872c2c4eed2f069cfa818314f6818b5ad05	1663495590000000	1664100390000000	1727172390000000	1821780390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
301	\\xd082c0974ce6e1d2ddf62ebbf62fc885aa6967ba3e794ae57aa1b15e6840703997734e9f82a1953674357aa08f425d393a31fdccbed8d797e5555e689652cccd	1	0	\\x000000010000000000800003bd0512b59d9a89e0c6a68b26f785a2e305738e1a7c9196f5ef0ba607e2cce985deb4011bae851ab9ce021d6e062c9986ebc8da40d9526bacb495d16326ecad7b7d7f27320bfb559544c56883ac12db9a194644ae221b71407ffd42c6763d1c95c40a076784195c32c06e4eb52b4106bfbbc86909a6323be58471a5cb802c3d13010001	\\x234bcfe410375369dd76f7582f144b89f4a8ffd3e628f624f536936d0eb230041bb8257c70b78ace007e146a6f8f1e019c6efe1805b98282a57b7aa57e38dd0e	1652614590000000	1653219390000000	1716291390000000	1810899390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
302	\\xd4423dd9aa132a55664fe49b62c36ba32da4bb3ba837d61222e861893c3980361c7c6c23be6438bdd33b94dd098b8ad87c5525b6d7e492312878be9a15b5710d	1	0	\\x000000010000000000800003b55ae282bf39d4a22c6de5f7046cac3b1b046d70f883ee4631dffbf598ebeef326af246e7f1bc14e8a8d45b5588f5443dfe2b80c6d45668649b68a08931cd5c4c9a15c914118756195f9d1101d4838934b86e149004baf2efd8dd45636b129b8011c5fb62c88324f3434baabce8eed4c57852b6d114f215c3c9fd8972d944c03010001	\\xe00e85c3c7894fc96d32024ba4b4a8f60d90d5bb04fe3712458a06ca8accbc226273155ca0f8374c6f010b89e76d11cefee89b5a74362c5688fba403c9122107	1657450590000000	1658055390000000	1721127390000000	1815735390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
303	\\xd536e7a9e4b8899b5ef4d5389ecab601eed612970bf2dd01df8fe9769f5412b728344372e1edcd85d49f39e07a89b63d8d6424c5ed83caaa5320f9c2bd251977	1	0	\\x000000010000000000800003b05bf26063193b7b4fbf18de873c8d9cf6ebc97b027c06362d9507ac5d71414b09a2b81a44be5e790335a89f29c15a92d5707bc5a8badc514800599a030623a7b02e2b94c55d2db0b5232ee5b2893e0ebc298b671cae2ee4763a499c5ba4fb4a16e18f0feef051832a9a18f43f55ee14c0826244152c952ec3493c8b17bdd103010001	\\x96012406edf996cf93768abae7ab716ae2afc87ce725b584b89adeaacdf2fe6269a4424be5dc8930d1f704426d2c4dc9511e6a7dba90cc4d3ffa0a73830b9405	1653823590000000	1654428390000000	1717500390000000	1812108390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
304	\\xd7daa72f093d3f6c8939c0f1c34bbf692df08239f2730458b9dfaa9140e1924c50e587c4ec06002001f4954f049c733d962817183a735b852c683ac59d6054ae	1	0	\\x000000010000000000800003c76cc706f39680309f4a50e6e943a78779f0f641d4410bb919f4d5abfba23ea164d6713839120a2ed2bb649f28781199732b8ab20d40367788a1c50e5dedad424c1c30c97195a40077b86dce2eee2c2dbca966f96387c134af2d23282d84b32efe04b192a31ab52adcd28d2c729c77ac2ab7224c8583f7a146e17b662d633569010001	\\x405abe7481bb2b492f3dedd58174c4d3891e5ff647a9159ecf55c4e65dda8b47ef637301b9c4723cb74ef8eac38a64cb3f2064be4d749a49a40c656292436e04	1653219090000000	1653823890000000	1716895890000000	1811503890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
305	\\xdb164dd79cc7759d4882e68b69192f5c4ec12a2cc095eb328721bb81a4b8f7eddd45138ead2270a1879d947c83d0a23cc996f0774c70bd728879ef75597a1074	1	0	\\x000000010000000000800003caa0b262226de7f8c15ffe80d169fac3aefcf3bbe7b5022af49d634e2b7954397dadafe06a04a0920ef1533485e38a7ba1c4130578790cdeddea47d98c649dc088c77c0b30999763a135f4a8505d8b942599d35c6b8d2bcd3c8c57aa3cf344ab070097adc7e96ebf172176855042101de7678fd946712fb431a80f274bdabf97010001	\\xbfd10ced5107113be5a519171a950a2fb10db880ac7e0443c30cc1bf60769c52e4fd05514628429d1618046210083e5bbd5d828f34dde698f38847a44e5eb90e	1678608090000000	1679212890000000	1742284890000000	1836892890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
306	\\xdbe676674850aa5044b6df771c4400d3cf23f80481f3addd30825367840cc391e5c789012e4619dd68904d21d8310ec883cb7065a5d27a2d9017398f2d4c4cba	1	0	\\x000000010000000000800003dcab30d4752dab8a629fe308f093be23a42411ecc65f2bc630dbe25a4110accba733955b08fe60d7b70b874b76ccecf40a56d6c4b96652e8f6926feca5a2c602ddb356224f29fd2c4ad5e02ad1f7c347ef7ee983e0534aea978a8e65b10061125496b22b21d3978d0c3be47576cc50cf93e79fa1951925babee5f1bd8dfadbe7010001	\\x47ff4cbf8e7989838ef16cd84c5fab26bcbc64e55a4ff6ee0d0bcd7f731db01cab2c19a746c1c8e418c2fc007694a5e267dba8f7fba954a24913178786074b08	1660473090000000	1661077890000000	1724149890000000	1818757890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
307	\\xde6e5045a42832918d7c706748c0f17e4cf392bc4e77dd647183ba4929ed23c0b42d78b1bf0e22d6710fbd57e1af332b458bc4e5b768bb3e7506196d55fa78ea	1	0	\\x000000010000000000800003c1152bd074e6f1b4a2bdc239e897dda312001f49fb49d0aa6e001cc5527a57930cdd7f672f512e106e56575ed7803344048e646da879bdc0059d8239865d5907cd18c02a1f33dc8fa8c71f886b364f7f0897c0e8ef4e0c4810d339e9b63c32aeb4d9d8c378b4adbc5c1c0a6c7c220d5eb307fe17c150d031aa0a77f1b3b86717010001	\\xd9e3b4ee8d9dd96c9eea6b5c84f1c604888c3cb6e7ce9d0687f5b7f53958a387646774f212ff409c828696e4f73347fcb83fe7a7f0fe8b5440a2de604699aa07	1679212590000000	1679817390000000	1742889390000000	1837497390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
308	\\xde86e8fb3a2175ca3b8267878bf91b87399b01582c4b7418d06573e696070b0b0234a75ab8e3f8e3b0e7f7df3efa5692bc35d711e097a4eab75f12563d59655c	1	0	\\x000000010000000000800003af9395f22295567e16abee4487009742d84f984246f51df35bf01cde9295ac1b175420d376ba14403016b703385910b1b45e4377a623c6407970f128df10c4bcd6dbe026220fcd38584a4d583eff66cccada637502c55688f38ca929ede34e70c1eff0398d97b454e8d6aeaf97779c2bb28b31b4672166e9cae7c165449e7e1d010001	\\xd9117e7c7dcf707e7dc0f4c8f673150d3982590098507b4ed598d6d160246f5f306f05a67ae4076e75d80b7a8533c18144d5de345ec525d2130042aaf640e40a	1669540590000000	1670145390000000	1733217390000000	1827825390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
309	\\xdf3686a8f7bc1548dffc7734f964396f0812cc1f4c9ea7029f2f191f960dc28b7e105710f8de6852de86d2dae5cce30fcc5b62fdd761fa539b9f7c13c74a411a	1	0	\\x000000010000000000800003bd2b27285298a85ffe1f29cfd2defbac973d25eca8464ac8d465272795e18042e849de73691ce36ddf4cb6c4937b59fba5320ef1a24def4609a75394c11927456b1c919a3351f61dc35101c9af1a2da0d9b8ffb6ddfd818d30023d5ced7862fae5d26813f6bf19e1525acdf0e16e2d4597a034aff29ab0dfc5072ce8a3b80285010001	\\xe68423ba6f641b9e5633e939da4c9bfa88706e99c14b3eb0ee37026b6fb8f12c838c25816a9eaf12b853b2c9c9b8fe839b2f25c3db803568a629afcafc360c0f	1653823590000000	1654428390000000	1717500390000000	1812108390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
310	\\xdf32daaca43f424712ef1af9709068b21e0e3c22bc832d86a95152cafdc1ae61f4ca7bc9eebf0d845ee45f0de9042206b35b30642b725a3081c37adb484c7572	1	0	\\x000000010000000000800003e578ab23b79acc75b6b138d16bdc8fcc991fa390baf339514f884f53d6b311a64296e3a1afdf83f840aa0aa04650a519a6043bcbdcb3d31e8b24e3d82c40a4bdaf4f12d081cd8b5a439e35adbd7d17b75dd455f7ed8fc9f8999281127aba1dd7500b276cae46567fdf31f1169c5f4a8006ed0a11b7b777e72956a43cf7162ced010001	\\x743fb764d3ebfbc45393aac7dd49bbf3828c01482321e8a070d14dea10d03daaa5492df14d00715d7c8a62fb4109c9c0488da9f514685d32be89ba349bc7d703	1657450590000000	1658055390000000	1721127390000000	1815735390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
311	\\xe43afcdaccb8128b47cc03677d8089d4dfe38903629b688191037b8675752e2fd2922f82a1dcfbb31fe396ecd24661268da27c0669f7eaf258b5215ea3b97101	1	0	\\x000000010000000000800003c460ff4e518e747e2431af68dfa7e9901b5733a7058d3f82d7bc1240ec686b115e9895ae6572188487bbdf9a2b8b62b4ea2a09ff7a6ab3ab36ffe9369b330033bff3f8d36a0395839d317dff9fcae8306e3d44cbdb7ad103fda9fff429b600666689b0d58b97d188521f996d8fda484dc720f5d34a7fe44c8b2da4d3209a3235010001	\\xd4d4f7907b1f9f0e1cba496d1d9f8afba41f72132d404bc526dbbcca3be1e412541d47cb32ecca91e956ec4ce24554903e4f01590692550f954361942635690f	1648383090000000	1648987890000000	1712059890000000	1806667890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
312	\\xe54682667fe42da0700954cb46d3ce3530da9a5c2e8865d821fadf1f3dd817b5d513ae52fa59c714127bc9ad7ef97e3be0cdd3eb2f56fbd970e5401f8851f3b4	1	0	\\x000000010000000000800003e3c12982264619e9027f4425f509273aa7ff099f93e38af67332f75343f82bd7ef9e682c8fd8e45ca00a219845287a08f0f1e69737cbba0eb27d8c77291333e09fea026cd99da6bf23280705230c40c1a478d2775d672578745d4c6a4153ea33652f4f101d27ed24de62bbcff5fc39b8d9fbed15aac7377a49d285f9dd039b63010001	\\xa24954569ac81709f0cc70ce9d48621e1f9ba8cb9bf4b61b0c396073d6748ff7f3b164730d42023b7e38c67e83c6b6587cd8e7aaf51bd128651ea80d52197407	1662891090000000	1663495890000000	1726567890000000	1821175890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
313	\\xe71af11d5415cb3f88cb80693d3418679cb6d6dcf95a0e24a7728445a9202e55c156d42b476fa91451c9f17e20590dc8771e96fa05f6cd8c96e2b377cf788b4a	1	0	\\x000000010000000000800003b3443be752e8861859ca176a93b067f4fc5c44b5dafb5dbc4fda9c89e14104e38304caa9518535bd2215cd34e61bb5be005705e6c0f19fd3869380e6e42421b16a3c2c1165a2055de827a888985e26d69f6cac12d38e55abe81dc873580f22414631210dceafd65b29ac0580ec3ed3a8bbae259b9a1b038ac6977162d00125cb010001	\\x469b3f801135a6aec7c3337d2a5cf242e960faeccbe44e1ac44e95930b460d88759470e4e84de45030bcf233e6d657f79900b0fd12f8b3b0d39c081d45eee003	1668936090000000	1669540890000000	1732612890000000	1827220890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
314	\\xe7c6620d7ad8cc6914a1b7d381c8e30861109a177ac7a81baf1fd37ef23883480920739ee9e82f2cecadd29658e3399142ae592576d11f15e7cbd081af9b4f60	1	0	\\x000000010000000000800003bd1964c854877d3e64aac7883681194fc758bbb6904db7c5b67676e999a3789d97bc2e9ed3961af2e9fb96c0d382ba9e04e0bf841680b157ba0d4a4d5a51abf1b6bf87b046058554e754e6e3a8d88a0498d1c82da616cad630e3d855a5afed6d7b7faedf68ab2ea0eea9667a0830b7684ab5289ec453c08a231173116662bf25010001	\\x879be13005d0839d95b62dec692fe7e65a6efdab46ad211c46a462c097295882d282c17692a9c76b34df2a4c895cc9bb73a38f9b726929125175dbcd4af2aa02	1652614590000000	1653219390000000	1716291390000000	1810899390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
315	\\xe81e750b2109df0699f413b9638c90132971f99554c01c1ffe58b3baef22ac7840ce65a441a904e73f72b46a0435bf04e1cf64ef38aa1c5ffb00549151903807	1	0	\\x000000010000000000800003b67fc932af4fab54fa23338217d2b6a5467f280fe5a99154b9f6067f544f6dcf1d0f39b6a2107ad12a307599417cf8be7f517092e1b24241a533dc44b65cc9633d2cb4cb42fa3eb99f5238d0f062a23ab11c12171d8661a63c5b6fe253e0727ed796e4e21aa315bbbb706f8787d7f7bf37a08ee370721dd28a10b7917176ae65010001	\\x00b12a4040ef9c10505361bad2bcaf7ab8986edaaa82d9339198dc3cd96a2ecd9ba4ce30dc0c4225b2d29556e085751c396622717818520d074498e0e1386806	1669540590000000	1670145390000000	1733217390000000	1827825390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
316	\\xf0ce2f67cc20af897cd29002e2b87cf2a3d1fd3fc68801d2c36a477a41dffc1f07b35413deb1af792e9ea068f6746833a17898bced19f91c13f64b1dcf010f6f	1	0	\\x000000010000000000800003adefe1302334463a69c8ad89e7f5e988ae9102c0b025e5b255e34266cc72bb4020870f4be8b21a34f15b4cc55037cde2a7e60c9f0880e23b91376cd85c7b81b8993edc4eb5ac9815f0b72721116685d8a3115547bdf38819ba66d8f79d54d045cba0ff9f616a2c310a0d94a9d3414551d7df40d2610327bb93705a66b8e9a339010001	\\xe510c9a07821adc9da9e68d8d246745fd2f8386398eb78e6229e77405b0599a5ccc103c0fd25901a3277938f8166270e5be20fa797c381be86ce3130b4816903	1666518090000000	1667122890000000	1730194890000000	1824802890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
317	\\xf36e11534975aa3d35f025931d48bf12a23212f630cec9808f9bde77813d8beef8f731b92042b32884c8f51705734c6ce45e3092c76fe972d04111b297f78b18	1	0	\\x000000010000000000800003e6b4fb24a1fbc9d3179e36a8698aeae3310bb01394a236f809263e2a3a1590d920e1fdb6eb3ee8c881172de8f0d346ce4464843378b038f338219711fb809017de40399a892712f30334cf37a688e60a2619623be74a8cf19e690dbb517d921f1aff75779035e3ebb9c15ea3070e3a7468944cb450a004b5edaca0007f6c3355010001	\\x2b8fc6cc9dcb3a8976c8b5af9a3e0aac02f2ed98f81f5bef95f2936d94d77a62f62f06f61db8eb795c9b8f3d3da4d75053d5687a4f0c19ed742d02bd5ca14e06	1650801090000000	1651405890000000	1714477890000000	1809085890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
318	\\xf7f6b76bf7d9df13d5e1005a505489dc0bdb9193cb2928422efba479072562368cbe830ee675983e7d809d32a37ee0b89cdafa41d8e44aaa0bca84efdc56f839	1	0	\\x000000010000000000800003accebe05121bfc2bca262d6f40a540fe4f297b9e22d6679665e182efffcc8fca385ad096958515f31889dcef712d3f7694cbce773926215c8914ef113fe079d289f6652fa88247d2a8fc1ce3eaf807768b13cfc09a0914428c7e3acaf915ad50b0504d8121bef801b37bcfef69cfb184710b86db1fbfeffa69adb789fc07244f010001	\\xc858a68917e7b5420ff6d7858506f82eb0671ec007635cb58eba3aba9818be9a90c4dc0e41d4a0140532592d60aff91f09c7e6437ec1ab0383dc35120d1e1201	1677399090000000	1678003890000000	1741075890000000	1835683890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
319	\\xf782317fc86d423242bc2c79f979707f4c706d7fbfd6c8c2aed2323ce27b3af8782b3189381d06eb0e0044ebb486eb41aecca5d7ae73aef157733942087ff654	1	0	\\x000000010000000000800003988275b4b95f35cd5b8deae68c1c271d2919a949a3bc7891922fa4ac4ccd595d8d4daf0eeab279569c49fdbc382bc9b51c152194e7262d8bf7a7a5d6a78d51e98db07cc8bbed779b36ea5926a1d2814995c346f9d1fd2dd5fd4fb8f24d6d22aa846a1b9486232d1bc236f822e8e8eecf181060e0210b6c79a1a62e9a04cd7097010001	\\x3895d4afdc9e69857c2f5e6f567011c416b970b27e5ef6c4e3fac7aeaaf8f45cc158294fa9bd3ae49840c8de27e527fe5e8a6673b0dccf81d1afdfea6555970a	1652010090000000	1652614890000000	1715686890000000	1810294890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
320	\\xf962d76a896cca8e0122ca46ca43a3ec87ed5f457ff127684d8b10083007933460bcad39c7eeda830f9dda7e0ddda67aadb70c53aa25e77b109200296a049987	1	0	\\x000000010000000000800003d1cd94518595151d57142c387b7296bf7c21c0a7d011bfe0b2144efb60e68cc4edd64834f3dca664305f0e8f25f78f3df492f07015aa2586ab77279c0cae032d064ff54aa0bb8eb10c6d6ea266076396df6e136e961b3b5a111c4ad502080db94ee6611fd4b7e77901cc7be35aa02c497371f3771751d7d1df4a9df1d1b6a8c1010001	\\xa8ee6f7672acd9d0ca583451d1d1d4f9c2b25d3881b223b6faf658e8ccb15740072616fd55bc7239d8fd80e318074788e77e646bbc8578013615cce0d3bec70a	1675585590000000	1676190390000000	1739262390000000	1833870390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
321	\\xfafa7b2285e2370d4378f258abc846476f0cb58bb168eae8c6fd7dfe60821c6cc80cb625fbb6c6f102649d019224759db3140504aa8c196d6655ec5c8815a12b	1	0	\\x0000000100000000008000039974920e28f1b59e23aeee1bd9c6bd6393230d93f18aa826d721ad991567ed9d8c7bb25f6a6b2c0ef687b87f51b48f44aa3f29173f8efab3fcd09adeb757b3ffbb4f23d189e793f7a51b931b302d878f38d860d44026593352c47e4b25ceef660a5c1b16984d466b3bdfd994a7c2630da74b414a3c1285d76e63ba3391d122a5010001	\\x1cfd43bd79fc1687a757f1dbfc7ec96f48fe6f65180f0838fb670d340cf099b2666b3e8554b5b06f90b6af19b83fe7a87c5bff4b79ddabcaaae4b9670613e10e	1656241590000000	1656846390000000	1719918390000000	1814526390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
322	\\xfd1e733a03b1825b91bb7cdd2da2e54d5a465942a49ac09def65f49dea8b26494163874f3daa691c32f2a3fea40cbd721b4180932ce087b5c63a38d25ae69aa7	1	0	\\x000000010000000000800003d85070528cb3c2eb2702f78c52c8446e37a35fbcaea2ba6c8d37a543fea3f4852979ce313ff126052e4b30a9a4c28d9d7b004ece8a09c37e9a7c53c7cc9676ad647176a80174bc01ffe3ef9739683110bfd4bf5a6c14a1860e9a71c4adf0528f7317e3bb7f26cfede671e97bd7ef8bd1c016b7173ce8d3547ac724238b480dc9010001	\\xafc4cc881e1016b7ff0716242fb383382165e9f3b6b39a6066583eec3bbe60b55430c31296c117a9e5f64f25fa607fb9281ac9ed915dd056409e38c790ce210f	1662286590000000	1662891390000000	1725963390000000	1820571390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
323	\\xfe627a1fcf048c419395dda2e71274c6e5218160b48338df5725bd46988dd2a42a5f218687c138024315508e934c09b42ef5bad478e77f0e0d0509332337760d	1	0	\\x000000010000000000800003b8365dc92a771111d8265804e434e451632a46cf4fecf129fce9525344a4fb28ea781789bd75d89a9991d6dc169b951020552686b9d5c4f013df4a8b03728aa827e0e47a04c542a0bc86df105942f8ac10c8649b9d93ee2bf4014813da7d99fd59dc0bd1b986576f57a3a384f7ae4bd7d1ff7a00bc9b6d31f8baa0284207aad1010001	\\x63dab52ef72c3755eb0e2f68ca9301f5aa10d49b2183fb9436f7bdf478fb7379de9fb457cc79470bfffcaf8496601fcc4f5a6d747ba0da4090a2ba325e78e302	1668331590000000	1668936390000000	1732008390000000	1826616390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
324	\\x03ef31191862e494a42488864db9ffd334a5007f661a93202891fcf62f95c7935ec4b0fbf13d299156ec3df5937a4c0fefeed44b21b14ab5a772b92a5681d9c2	1	0	\\x000000010000000000800003d6ca46ed118749138270c8bba811c720927876aec137b7c363b01b6e8cdbf74fec624fcdfad212ffbcbab40538d36c3837aeab26ca13b3fddae713355a80f65979ae7c83533743d867cd52650370207888495ff1ea69ab6912342bf1f5f0e7cbf0f53559a0690da9f48a3772cc54db5f22f17deae716881c47eada901bfa846b010001	\\x27a1a1971a41afdab99df3d0cb8dc2e74fb298957f9bd7fd66b9dec2f660613e04c1d328f8bdf906cb4611915cae139df35b5faa7acbe148c805821d08a1ce07	1659264090000000	1659868890000000	1722940890000000	1817548890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
325	\\x076bd53d878f74124b37f3dbd449afa2b4daf05d50fd9c0b5ea10d1f43a777e2c04f1b79d7a6ed869231db03e65d7b7a0d57429c4de5640a76bf00044f81ca66	1	0	\\x000000010000000000800003afdeae1d4ac2b61554cb7ee68ba7281165be74c1bbcd5fdd2808e568c7f2dcd3f51a9596ce0e52b7010441fdd7890606711a771fdd32fd30016d43e054e8cec31e66f1c4a3e08851dc889617b4168b2e217f91c0a16842f1c15b849b09e01607d73c100821b18a7d13846dac0e40261456dcde788ab2c8e8dce60214c9ad5493010001	\\x436fb548ef0584db922832799f080b594a74f6cab376e2363af00980b9c597748c6abfa19082d8e8485b3aeead507e8f2ac0d07bc41add857dd4e2f211ab2104	1664704590000000	1665309390000000	1728381390000000	1822989390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
326	\\x0967a2b7db3279daef04c0b11afe5a47bff964cd8452aeb057a7332ca0d7bbfa35ef770585adb01c41ceed270d184fa5ca3bdb3b1bb0ecac43997763aa2d5b3f	1	0	\\x000000010000000000800003dcef196b0f1b2081e1a53c49648b1517ab30ede2ca03012d1806158ec7bdf528be7b4e0b1509ffcdf321ac6c91e9d1fa9316ed451e62073771e71d257417e1aae18fec3c4512e984efd51e9bb30e480831e5942124c55533241080ea0faa323396b6b6108d1363be06afa153442dc00fe86727dfd20f997fa983f4269091bd71010001	\\xe4c7b3852f50053e374a1e6e2a481aa11f7c217578561cfd7d78e0e14bd69bc568f62f2a83d242f52febaf4ca9b01494fa2c4f7134a27748aa11e467f8573f05	1661077590000000	1661682390000000	1724754390000000	1819362390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
327	\\x0c6fead9d288a686d6a0ba39ff02a83e413d0de5daf7a4ff086cf99152df818c5b2804b7b8012f34ea78ca13d73a5a19bfc8ebf9ed3a2a2cf5817b7034465dce	1	0	\\x000000010000000000800003e59b0d36cb52cf20b7288480d049d51d6aa6a1e388079b797cbe86fe85a52e3b49dec223d79a3349caafe33743db61d90064f69923ef8ed8e9e56d26d89d8c89ed6e304aacfc1c6dabcadfd4c8773177823236c8a6bf01e8adca0693987ad97bb434209cbdc9420fd7d47dfcfe6f488a9121813d40bae563419bd68a64e1b4ab010001	\\x5374639b981c6c2858b0580e56e5e117885f354b839deb9402fafc26fd654ff84834f3d2ceb1a542b29891b60bc463c215667bcec9238012394ecc905ef25e07	1659264090000000	1659868890000000	1722940890000000	1817548890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
328	\\x0d1bbc51ade21a30775de8d93ba374cc743eeee149a05bd9d3f8b9cd3f0029735122d2c470f21fa68cea52e1d361ef13d899100ed4254c9976ea3ea59e3ada05	1	0	\\x000000010000000000800003ccc68b5e34c179e5b6bf5a783cde8b60034f6ed7dcf4e923f31b64de24357d194ec368f27f1fe93665896d194dced63fbc212d3ec7b4f700343b269ab33b00385238d40cfaf7e3d6800b168d9606a7b089cbabde33b076435610191a90eb976623a608928de60909fded6401f4e7f64a32deab30558a2874ae12af210ee3b4d7010001	\\x7b107f1384b4059db09f6bbce94b40cb43b26180d8ac376e461e970bb710f61835a0ac006d1d9caf8cb5c602c6e5d7fb0e17e8185ee5ac2742ed023271c6150e	1671354090000000	1671958890000000	1735030890000000	1829638890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
329	\\x0e6bde08137b1140f0f576c90fc5ca4f8cd4cf50c28768fb248ab4e10f80b714ff0ed63bea614f9185c6a68d9d35a339a61d2f828ee736704d0629f80051c5aa	1	0	\\x000000010000000000800003c7fd8dc259517812fe94a2ac1a7c4eb990286b5d34a952628e0eb0bca229b554eb1e8571f6f75d47aa1b012b4b8189c88888652a9edf80cf89aa275da8edfab392fe86e91e8b01dd0fe56a7a1e73ce184b07c0b9375648aea789a127f0938c768a6fa221ea04a32e4f57f351627caaa869c5e496354a048e60177ce806d2c0ad010001	\\x4910f1ac0613200ce5fada4756acb37a142131eec5e0c881e76392cb063660932bdb41211f08f2cb5b739f3f6ec8774b7270da3a91b656f98a914b3ba1ee7d00	1661682090000000	1662286890000000	1725358890000000	1819966890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
330	\\x0f7fff40c176d0fff66760abd5dfd51f631f992ac451d98237408da9e0347d5e3652b7e7d30f990c6f5668bf440edaf5e4b37c3a0bc74167fb49d661635f17fe	1	0	\\x000000010000000000800003b75ec8652d16056427aeb16094b7597eb8d86ef9875a01ae18579ed5a24568ce626439037cc5e99c71d2e66b736e1dc15949e62e3c1f75bcc4bea567f447acc21d0b873d5f8ad49e62a5fe10d5467c9f7b2194935187d3805c685cd57f02d26d9767231f0820422331d5dd81ae2b7d77f4da1a101ea683167ff86312d6fc2265010001	\\x000458b599ae3b93437b9d1a0a88e5929a4e36811fc3b5c26904605747b4a4ea2cd73b72f4c1d30c5342db95220e1a24c49b215ef2dcfb57f65ac8ab0998b10d	1661077590000000	1661682390000000	1724754390000000	1819362390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
331	\\x0f33db67c326a5fab4f559f8193cea883779ff0b598b55fa1e749cfb302aa5d1da63723ae14702024a545487b1a0591e10c539a6b6889c8d14973a30e8b7e9a6	1	0	\\x000000010000000000800003f17567e0ffea500aae6bb8a94da6b24e71014e7f0ba737213d6974a78f2680b41f35a1a9d274f927274f5fe2fd1cf88d87e5da6b61fefd360eef3c460ab08abf798eeb83120a3e882c65e8e709c46cb49a27b9e9e1acdda0fddf7e503b1a884376022154cf1b6ce52284c88beacb8418ffba29e136aa5af4f1cfc2ae37279dc7010001	\\x306f1a129464a933083d91886eb41f599398d7490b3eee7a64c78b587a520bb97c7ecc9f8af976eb2dfd26abc6525daf622dc9a67ddfba1203c2f486de516306	1671958590000000	1672563390000000	1735635390000000	1830243390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
332	\\x106b41c47da6f6214d2f2244206fee4469dc3f33f715dcb2edbc65263e4adf635357e4ef8d3f7286cbe540f6de8bf92160fa40114dbe9d8a4d0f9e6191424f93	1	0	\\x000000010000000000800003dc5a54839b47223baab31235cf9cbd1f883fef56531f3f8c698ab9b23c3542b4b23d763b2c490c668fe4b751f923a4f3a6c9b6c8c970a50c10d5e7bff72adfdef66fb188df6e96fbd66e98b9d8a950e7c2aa8da1241c137ec0166143aacb836b7ac1c0e2d6287e7d29ed9c3fa49ca248452c5ff893af0a814f27c73037027013010001	\\x1445dc6bd686691239db47d57b07ea30da7b9b6632a31a745afffa20456cf727d5facc0ee52eb3e08a98983d12ea27a68117bd35fd8c6d0f6152fdd458d0690d	1670749590000000	1671354390000000	1734426390000000	1829034390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
333	\\x140fd51a96c08271934008de9beb2ad742886eac023608c50072fe0b5e37c29ed71f34f3bb302e687cae7df1f0c15349fb6af41d07d125c103e89cc858dc6156	1	0	\\x000000010000000000800003ac8b883bf544d14175f92d1089d3377959f1de77957b780d6487edc9d514e17508da3853e9d6e6f6df62d240fb071129dc974e87e17f6464a3f4fba328bdfcfd115b4d295307b8e929c39e8daca3d20a714882abbcb2b66dd00c0e8571a3749fa04d4ecc2a8f6b000621e91a04881f243d983289a4d018ba00eb8c4311ef73bf010001	\\x1f624ff2c63e1d228e84a500a49eb1920e6d1bb25b6bd5ea9a15f485d989673039cd8a30fd57052bcf1377c606b02236b8a1855bbc49e441557cebb5482d9404	1674981090000000	1675585890000000	1738657890000000	1833265890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
334	\\x16b31e3514fbde97f4381489112f29ee9b41908e9db29baedeab4488bab418a6cf8d4323090f2e9b8d3eeec2d062ad0ff93427261738ca5ffa91238f94dfb422	1	0	\\x0000000100000000008000039ad8dffbb96199d743141b3e935b1a2ee5bb932106bb741ee18ad0499437681c5ff34ce8a65010fa5a19076a01dcdd9c4b0f89e40532b0a2c1a6108fc9cd310d05bc9b481fa8f3c2dee3903b252f5794e35b54fc7390be60df85a0721eb231a43a2c324814b1703e6617082cf6c3605b31f3aabf4c04fee455e290a3aeb4b9fb010001	\\x7b4ea59405ef22d8f5d9ee1ed291af898e4871711018bd3893654d1838c0ed55d9b66ebded8ce24fc29767f5400e0720388077ac6ae886b8f0489be87825a00b	1671354090000000	1671958890000000	1735030890000000	1829638890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
335	\\x1d43b58ed7458f3ca787e9345eaed6959f85f3c975c8680d2ca178812da0c7ecb60a321caecf6dad15303486256297e87f23714d593b6854baa94d92770d624c	1	0	\\x000000010000000000800003b975c6176e7dc721144c4ede08917f9e0599f64b0ffa28effc1154c18f0f1805910150a44149fa4fe23ab7daa15588a422a7fbdd6a76acdfb6fb932835cc23a8a62f3386613ef956d9b5a4798d687ca53f34ceb23ca18292b50cb7addd18aaf50d1ed1ed2148b5a3afc84f14cd140144ad0d4769681cba581f28acccbde553c3010001	\\xd6c2fd1ed01bde58eeed5e2721871be78604d796e7858ad653f6f4d0ef2b8102f0afe25399113647fa0c4183cd169dc67fc661761c29e618ba923daca904ca03	1658055090000000	1658659890000000	1721731890000000	1816339890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
336	\\x1e0f3bfe869e05994c393017bcb00a7fa41f7e7fc3dbb1036946e56fd3ff1b361af5a4b7a406eff7b57df8992f1d049216af1467d4afb09115109af9767a2a70	1	0	\\x000000010000000000800003d9407bcbcd88a90c80e6079aecb791a76a9092a140c3e6def9ec80f66abe5b26544a3fe1c08f9f4ba80947458bf652870d297b7a7fb0f15d1d5154ee54b87ba2a4aa422821ce9d17b6d0121aa659d6a14f4531ea13cda442fc8b11648034051f4fcbafe152f3328249434e382877789e3a48320b24fc5541552e1098986dbd53010001	\\xba168f3eed2923068d0215964c0d9e85d7b6e0e1c13c5f726fc5c27e22844e1ffc5d4deec4d6196f14a465d174c32aeb796fe1b1474dbf7590020ea6fa97390d	1666518090000000	1667122890000000	1730194890000000	1824802890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
337	\\x2093cc38c29b3142355f404d66cb71ae8a0f63af7369bed267d05e5b94078bcd976b3f5b64864a41851ceb0a39c1c5c20261f44c000fa4e300d09cea10573c76	1	0	\\x000000010000000000800003c23fda232e5e173180191a044b9b81faa2aaa2af5ea78c70b0d3111b9bc06ab1071486702c5b8c9893f8eccf98fb6afd6396740faa165915d8281e3b565ae278666e601cdb24260eae058fe60f84c7dec0b498a7a0c87e03fc03346c790304f70a6424c9f88f6acab2994234cdf17cce10295d46e36bd1c65301d90f850d5941010001	\\x192ddd1c25bbc8f011406810e4b8c0401c2692e437115b046dc38a231d3b79063336e0d801d968751d266efa7b9a5e266bdb5137e2b386bc42996f148eb47301	1655032590000000	1655637390000000	1718709390000000	1813317390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
338	\\x21e323fa9362779714acf66d014888b239dc351f1789fd29663c372a5d0716042b826b1db8db2eaf5cdb2c1b182306260b4c5bd4122d283981639cec395c01f3	1	0	\\x000000010000000000800003995eeb3fb84e273b52002ce3b8803f7bcded27ba0bed15b47567371d165d50140d68aa6e621b587846291860bcc2d3408c20b31cd8bbb19022c51d35bf92a1b071d6b038150f672794afe4d7a17425fc6f80b1dc71d534985a379bd67a55e6fdcb4d8c4e8d4d47756da8563f14d09208d4e1fd5e4a98bdd563e6a53dd3c13d61010001	\\x7e186d6a4515f8c66a914105212fad0f3858eff9f92628919f6ad3237cb61f2c055b8b3ed28e1bf33cb4c5dca01a58b71756da984f7aca0efabfe83efb367d0e	1662286590000000	1662891390000000	1725963390000000	1820571390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
339	\\x22db9e04b7b1ce38e34369d352218c4763c02858a2fc99a4f53fd4cdf014e6976563df59fa0f613d5e7770cc279fa862970ed40e681d3506dd78fe71c57ffd60	1	0	\\x000000010000000000800003ab1b16a76e1ae8ec90e6f52f75a1dce933fd1d34b06a7597cbe62a21adaa0db92aca1229dcccbe6da37979183b8713925db91bbabb0257255b09598f6f8ee95ccb9f4089596825ebd0c02102f5a3ce5126572da6d1cbb8570dfb0dbe3798d6b3aacc3b1696200f99b8ee43e8d8694b796765d5a98bf7365980adb99e0d66f597010001	\\x73bfb5b067b92963abf63b3daa22c025c83122b10c707a60ecf262b386e1b1e23a74c7eb5f2ebfc422fab9270f52fe59d94799b8864813037b1d92f09abbb901	1656241590000000	1656846390000000	1719918390000000	1814526390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
340	\\x27db5747858979428ac2eedff3bf416f9f3268d8d65ef6c19ed1a05680a7f8719a520d1efdc5f94decc170647cbf4ecd3c9a353f692b4ab8b4c8677938811e82	1	0	\\x000000010000000000800003a8a8c0dbe05ff1ff1e74afafc563ecd624c73585b105b4b8b88ff6b1ac8a736bdc73cd365a251ff7e44f8c4b1f696ca9ce175218a9088ca252055323a88e69f235c00548b0ac3af33f6b516a27d50e0a046c89818c82288587e878f56b252c93ea2e3e91a040df20bd5310a3a4d63517558d7a3462aee25fab45859d703fd2f7010001	\\x9abe8f57950c3df3fb2c432480202d7133f66c12a8c3c8ea230ea3c64078ed25e3bb122e469f7fcb5da161cf8cb8960243c97a8c608f3c930681f2a176b6890c	1679817090000000	1680421890000000	1743493890000000	1838101890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
341	\\x28a3cf28403fc5cd30c89f57d85b245fe1359db2c33dfd3f8d72e1db012b533811edef415632bedaf83807b4e79a66aead9aade443aa709e180c7c1b0a2c43a4	1	0	\\x000000010000000000800003a8d64ab69e1b9aab2801718e7dc541d2c55732f6c90d38645b4cf12c97d06b02bcb0107a6f4dc0e9437355c7ea47d4847127d4d7de2ebdec989d5711230c6cd3ad4b58b612f7cd15b2c81f5093970fb7fa5496a8da8e35ad98b518a5d8aaefd3f437a9a26106736e7ae02a5055f19dbbd2ef7fff777ca5771fdfd4225c7c77a5010001	\\x540211a998ae0ed48387f094ba638463990d73db50f10b8400549904ad1a7757ea44781832f880a31ed03d0d719ff0380f461ea684171c50cc7dbd92ce022606	1676794590000000	1677399390000000	1740471390000000	1835079390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
342	\\x293fd741f66bf746345a8cad178616f701970e55a33fd2c33bcf063d4b07f018644c1b8d27d103bb5718fd47483a3a72e7c3679a2ebcd8d39a40a96f7264efd3	1	0	\\x000000010000000000800003a5ae9172a0216f6abbf1ea4f8c96935042667fd92c500dacc2c03b11cb9bf94402b491c8854ad607840b3cc1346e3cef1f53c442e4ff26ead7fbceff4ecc270b689d6b3b61c18858df0fbde0598ac21a55ab3556b7be51a0bd00186f9c1f1c87b4882fe727c1d3061dfbed9f976663b95502e5bc5ff5d119229ec2ce3850caab010001	\\x705f2c8a458ba15f3d996ad09489c3c5c8b7d2bf1d638d0aa7c658dd65edef8f6c575581a96fbbbecb563eb1047528c13ab3ba7c1198a6201188bd8ad3d5c50a	1663495590000000	1664100390000000	1727172390000000	1821780390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
343	\\x2ba36d7a7dc873dfb882e9ccfd2fa75da0c50a494a386aacea9869183f3bc3884cc7c085a18ed7e0ba87be5e8039534d2b426e9ae60e90bffce524c772e11821	1	0	\\x000000010000000000800003a95c726e2a22e9106246c8704ffe0d11f76e1cda0e4dec7054f633015ca6c94d1c449b1db980820ebcd570a085be036d6d62a2003bfc861c0a5efc10705b71e9a480309858f4ed17c2d8f276e4997f2808cf0536a0ff96dacc5bcb78cc12844354a4712460ea434fe9eb625f2df3904481b250d90ad2f06b107d6d03cf902a43010001	\\x01dc283ba36bfe67f357e05d0bc8f7bbf424b8348e1dd03f973369d5ece8c5df496737c7fa0012cccf364da6ceba9d30358269fa3feb60d62fd07c97a8357c08	1651405590000000	1652010390000000	1715082390000000	1809690390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
344	\\x300bf34ab0ebf4c780e0306688d1e24c33daa201729bc49126420c633805dce28848fcc209b2f3664e3f88a9d93da6c8746143f14747fb2d4b959f3e45e151e0	1	0	\\x00000001000000000080000399522b46245b412abbd0dcd6c1c84743e6381b2bdfdaf21ba5bdcb89e14d3f0a262a4397726f6429931245e797bd364b7a24584743611e91ea4c78d3693aa446366c3a76e4b955be26601b164f2beacad96cf44b77c9c30c1fa176fb0c21e4dda2da0acf5a681681d07723f7309e9a3ec862bee52b4a644f95b771136972762d010001	\\xa47985abdcfa9b2b31a6a3a65d4a206831676abe097642819f1985c50e7074889729e3f6f155c6c9af3fedd261f4837df1640a61ade8ce34f8cd3d6c89ebc103	1664100090000000	1664704890000000	1727776890000000	1822384890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
345	\\x3133b0103a3c87fbae8301fde3b3204ee7dc5dbe2cc1b81e88a30dee8d25af9385a834aeb228b1dc76749697aebc45878d60f81fd18c1a9d92030e269b1e01b1	1	0	\\x000000010000000000800003b0efa15254135075a5a4dd002f03e70d78ccab0423b61801afa959949ccdfabccb0a40efdcd5cdeb94882095acc17231f57361ad5836c1557b6d0e09ecae492b5edeb2bf6238b9a8573ff2ef0ddece578eee118dc87687abac2236df84ac1d5ade7466c7a8b0745056e1ca304f7c0d3346e73cb52da449b060812278ae02b1af010001	\\xc02cfb766689ea3a06af8dfc911cfbf917a04c47bb5844f18d307b2ff362853b8f163fe0a33c37780213beb2af734d22a2d03bc18e980e2e4a6a115335399a0a	1676794590000000	1677399390000000	1740471390000000	1835079390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
346	\\x3297e7dd6781c29ebd32db07ea8a8e230589461bed293eac238030e38d3c4503563b7beaf5b2e6934bcc6273298e8008e580761c2c762a6b1b9f0711290038f2	1	0	\\x000000010000000000800003c8accae87b3777e4df8a79afecbac6fc73019582c30b8216b54a6aa40b9286b0f7e06622a1f7bbf097fc4177dcc4fde50a85243b2a76e9e802fb277b6a4f0dff10eaf872ceaaa2f728e3bf4a5f9d839e9cd511c91f0f6bff4f97fa29e65b4fca4a9d12aeb4ede9afd5ad69e0d14e0d2ca6ebab94dc25afb7e056f4be4c603ebf010001	\\x6f2d61f133f917bf9c849a59d98a17d59f139d8d68c3c7e8f75e752b9c5f3334dd538f4dfcbcdf4b6d15959e80af176bab0ab878e642ad693966efd0a70b0107	1670749590000000	1671354390000000	1734426390000000	1829034390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
347	\\x33c30b1c831c118ef087038586f092fa2e125a08e7c3724d41110fd9d116eceb0943fc8a40d78bd1f77deb1678fb4bce531a5264d033198ba3bbe7a54cc09a79	1	0	\\x000000010000000000800003c173d7cff77f018f13983e984e9b0be1a8ae52ad87730cdbde9380fdb6d53a87d3d84122e7ce25c769442b5da2a5374ca2dfa112fa1a90906a9a2fb4e59373c0bf47335cfd90b4b2db9ebfd2d1376801dee7f05c03e726660ad5610e1f02e24486fa3e48b3a4287ebac9428c3755590f07090b858ddc128125b83c468c9182e1010001	\\xa70c9b8cd43d128f202f8767433ef8d396def59de6ef487364975b63867d37d7874a7f3f73df9489471e89fde9042417d66a4e5b3f0bb34441fd25b47fad0209	1673772090000000	1674376890000000	1737448890000000	1832056890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
348	\\x34cf174d56f9fe243d1bbf7fb7ad62018bd7ecdf344ee32af94eb3852777eaa7aca1a2ca2fc01234f26142cbd4346bbbb2aff3b6ebc4dd2413103849f3781e0c	1	0	\\x000000010000000000800003bf1074af667b1ec69b67c7663add4cf40bb3bca37caac897b919e8d41a2772803af3d2b83b84355b26183ee8a366c32e354b80dae6a5dbbb02d3db42b87bc4c3451b0e7be339a6d1438222327cce1e24c1ac7ab00fc7af55c232ddca0c1c2067807ba14b3767613fffb7038aafe1c01ce88afad74aaf9320ab5b9086bce076eb010001	\\x868af9faa44ac5d25cc60dea97188e262527dafa656ee84f80d5fa4b4820d386be39e8f23359e3d088c64a53bdc10f3ec56e8ea4626becb159f36063255ecc08	1650196590000000	1650801390000000	1713873390000000	1808481390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
349	\\x3903c799d0c93c2ba4c05bfa231ac927ce82cbaf66114da0366631cdc886a5cfe81b4e6ea85862de683ac1cca6d132d48ac40a873b27d17baba20c8c1f313eb6	1	0	\\x000000010000000000800003cec72e9b757820e376679f79622675ed63a9a7c2f2fed9e624a075d52f9a9e38f90f7535efc46dd7eb42824142f3e129d0461a22376a04e5ddd8b97cb89c912aad4245c8bfaea1a1a712f5664f9c7cd75e367cf11ce00865dded34f7d9fa47abbbc6d983d130999b68eb8e6f172fd05510885763ea6801547fc21f2fda1ee51f010001	\\x45d5cfc2dfa61068e9a1cde3a9efd3f1188a56ac2bf7823684784b5b41e9c231d1625f56d2802ed60e5393464271a4961acebc4b394d9d988ad3769bb628480b	1653219090000000	1653823890000000	1716895890000000	1811503890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
350	\\x3bc3bd27bf10c93c48e2e244fb0169df46083b6f8b3ffa08c80091c11c360604ca0901cc78d14bf7be169524609c235032fadbf296a4886e3e4a9fb6d17676e1	1	0	\\x000000010000000000800003b83bd6d8cf2ede80b4d5066a3999d905bfce8bbe3a29b8f495f3429ad7a92a38b5ffe2daef80f95df6ba425a36db04a680f4623310428ce78ef0525e128cd9c143f7068215c0a1fe984adfa39cbf1d189cd4822b9c6c709ee676c98fa64a644e2fdcb7f2b4f46e88de5913b090bf53614d93eaf7281f9492632ab43511a2929d010001	\\xb16dec01e92cefb499dd9d57c0e3c899f86abfb2709d58d1def1ed25c3867a342a2544149a925dc290c33fd45eff24da65da08b6cd48e2c8841991932dd12104	1650196590000000	1650801390000000	1713873390000000	1808481390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
351	\\x3d375b8a5b60b5cbbceb7fb5d4f22f04132d5a1932c26d7fab1bcf795c71d617f468a0eb1df44d725dde5b3a1411604e12a76e57741ebb7c98cf6c9d4141502d	1	0	\\x0000000100000000008000039d5a65eeca20bdef5b4e5ca39b9cabc51f6276705aa42950b8a439b87beab349bab33b8919052eaa1082660df1ebcb51a2e0cc1cfde7cd495cab711ae6a5da4d89f7ce73bef7e452fd66a78873d0942299c402c065813175c03b74ba2bbb77373a80c04d7564d80b7ce84103e06702a0d669ba69bb9c1520bc49d2a9bb149cbd010001	\\xff1f2e4be4bb83d9b5f5a732a69c3f21879c248e77c20f4d09f36ae06bef297a09fc46210a243cabbf8b75150fdbcb32eaa9163f58cf27691619f3d2fdb25c0f	1651405590000000	1652010390000000	1715082390000000	1809690390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
352	\\x422325830081d67495ad02ad4e8748529c6e19e505daea610e683b7960234b9719d0c033f2e6705ada26ae3b8a39aa57abf58ef28239dc60b6dda3f46a9bf6bc	1	0	\\x000000010000000000800003ada8f3edf998900f1f09bf1c1437f9daff09574817fc42d345d0b7227c8964aa4baf899d4a56ea2c6ba354fd8575e32d1e836ef7af7d016e64bee9d33a272e6c5481662feb2c2fdf3e1957c088a1ba93a45068862201da38ca93c91bce49365ed943e8ac561cdfbd39c267e18d9901be1f8b62c45856b36324d1cfb831e97ba9010001	\\x7bf835732f61bc7225e19cff0e97c9cf0c6fe20d97b9c850506696ffa469cd10548af0a7501117708bce368d874b731cda03b34c1f3c6d0886f59261465c7709	1673167590000000	1673772390000000	1736844390000000	1831452390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
353	\\x4373dbd7b24192b0003152f5b02f05236de34eabfceea8b984e29a98b43c088a8e40dc072ce3e187bd45800eac55933b58ae7fa9d29cb090fe9208aa1865e34e	1	0	\\x000000010000000000800003d6813227294693e6c46f3fe40917a37d41b4c1fdddeb9742b08a121e17eb6ab2ca6a564f4e75242e5184ae4d64a0514cfb5f989d98e708f02ba7913e556db02d1b52d869ada92f17b8b060b43b94ee9936a0febc588d1e1c615142fd56c8b94bd0397ee323f2d6f21a95854e14e4212e5e2eb6fcaa3874faa5b7a2a69a9cdb39010001	\\x96b0c59657d20d91aa6503bce2be8bb0e12da96528ce12a07d2cdff700a52213a52d596d78f27aac30100414a8d5ea951e337e4d402e366324bda0db961b5006	1674981090000000	1675585890000000	1738657890000000	1833265890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
354	\\x46c3409f682c8d199d5ec71110ab2368ddee69e8ced54a006e9b89579bd6d9bc33641fdef1c17c5407883451673dc5df825663289f96cd1509b9767372e58388	1	0	\\x000000010000000000800003d4fc1bd3d58ede580669d2033b3a9062f400169c247699becd21d6ff7914e5c06a66b379c59ab19e3e46d5c32f173bcdc1ae23bc3db09a0ef14ecec33620443cb981a357d7d7ebcabbcdce847c65b1bc2ca797cdd3b1fde902613fff13bc79dc0c516823d2e079e5413224204a883aeb17c9ccdf8b30300a2cc8ffed2026771f010001	\\x6ff74f63cf82f28ffb34b68e4feae8e560936aa6635c100202207619b3122b6eda7802d11e93e8eb4dca4b1912e7865b4e4479d5e8d2515959e74fb133303f0f	1667122590000000	1667727390000000	1730799390000000	1825407390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
355	\\x47cbecb8f98050b12aea625d8660b4d2b2b6f83452cb22082b41847925e03050f386a2842d7f067be946f0add9c520fdc844ec22d6bd0e2c5beb3195c4dc44ce	1	0	\\x000000010000000000800003be1f982bf8a20069302a0515391e1d6ec8c8929427e70e2f731934247ab0cb909b8978c65d1a47d889277b900f0c3664f14e719e6a4c14ba80d58057329c6a9d4e6f5055e8f32941b0a9d809571c71a5e995734f3c1b48eea94faab541545d60dea7a1830eb0f1e2f0b27e49dfbdec1a87b88b67e45db85714d41b21db320031010001	\\x97f0c2ed58225d88a691596a0ab3bf576618cfb3c3c6f1081c8d82c23ef937f81cb8f63ff33ca70cc9f896cb799bbe0f4c856a55ad02bf5587ba2af51fa40d05	1671958590000000	1672563390000000	1735635390000000	1830243390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
356	\\x474330865dd9ca152e2d91b3d8cfe4fcba2b89767748f35b3579f4a571614815dad4e49fe26d7d6bee3e618d4b940164379279f500d09cbe3fc30829dee3c48a	1	0	\\x000000010000000000800003d0a954a3f2e88b4f42d3e2239fad0821c438e83c5b0cde6fbd56a21042425eff2cc94277d263654862b1e3117d49846c1e38f07ec38110bdc85eb23f286c07e4e10360f0a8b425428b89c3e54f9722e5317aa86e6aa88358daf89301f43c29f04e98f8b70655cda8dca531329272adf09abfce4d1485dd10d9206ae6b0e7bf7f010001	\\x3c31c938a8fdb0db2f11e4bfde9508252647db3a0a9be65f2790b1eaee8ff0f64872d323400548483bd1e82cb17534d12fa9837cfd6c817411626541b0538b0b	1665913590000000	1666518390000000	1729590390000000	1824198390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
357	\\x4c4f0469db37897a1e269b30aaf08aefdc0f538aad474c93761577fd445ec658a5bb5d68242aa77a934d9a3a85450ce9939f522e386cd72c6b35bec55ac41bba	1	0	\\x000000010000000000800003cdf9adb9dec20e82612b52f577d072766b1642e44ff82a407185e9e9fedbb25691e0298e8214b5d8904b682d58b21f77cf8347b6b7615aa30a65234c7a4936b92a839e78f0d1999001816de18769f65a618f50965756d5b76460b4f0466c50436bb5542ee49cf3cd0fdd446ac6efe1d047351048db4f530f598540ecfd37424f010001	\\x9c16033044ae0ec9a4ed8e3ce4561d90fcde86305d2e098f64ff45c38de48f798094f24300539742bc76a35cb714666223ae68b23bab6a347f17427f404f7008	1661682090000000	1662286890000000	1725358890000000	1819966890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
358	\\x4c43f6f27545f7cd6f6031cd1df722e9c18b0c91846368f780ae71f0c44ab2a358344a99e8de3fa1ac2dc07f435bf916544292b1baa3938cb350a2a7e6c671be	1	0	\\x000000010000000000800003b1fb896f084c65bf8bdfd94851cb2249de03c92114d2b21e7d65a13d4de94a589d811b60c87942e34cd30ec2f52969c948a08164bf68ac789fd83490718a9004a43c51a520f04c0c1480105d046f3a334f9696447b7fec3b380bf811c8849b67018618bf299a518b0b5915c93df04008b34852793d8ddc6b88a6898fc71f7cdf010001	\\x51febd7d40640778f83d74034fcb08e600eae6f91b012b1cf78543c30ae4bc4575eb6830e482233a4408766b4ae3615ae9435cfa44f3063d751b2aacb8179202	1650801090000000	1651405890000000	1714477890000000	1809085890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
359	\\x4f77c01def2c4a6d12af853d20f0c812e054a102c1d1acb8fcd8ae44d0ee4bafb86c88cc6f174707940dddeb205e62f74228fb2df7df75641f507b71d5f62394	1	0	\\x000000010000000000800003b981815349e55fb04b5adb5a1dfa3cfc0e399322bdc5f8938f0fb47c83f239120dade5d1f1b36151152ace5bd19841080da69f80df9d3162a072c9dc2aa7bce07b2a7694b210e030cdb8003d1785ba42746f5dad3c17a07480cb42ca93a988468ace126422db9d3ef6394a98761393c44373926fdca9676fc1bf0cc1f66334eb010001	\\x4938e76c1df74d86c11d23924c3796deb278d6f9105979f91bdc22bbf2fd4068d72184707f481e2e1bb168a541002b01bae03d079780cc16d07814ef632b1702	1671354090000000	1671958890000000	1735030890000000	1829638890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
360	\\x590f7acb0d3e268c1b88c96f1e09dd6b26e516afd0552a3f20b7f9e8cb30c239a4ce265b06ca7abdaf9f12934d7a499d70c993d0a96fa8cf4a293aab2952ec5f	1	0	\\x000000010000000000800003bfa7749c451d047872d7a16fb1449208b7e254b4471e87bfbbd286e204c0801ea1682bc5c05a22c8ecaaa4900b85d3e0c45732b839816326a36378bfc8560d718c787229984eb4b8c80902f33badfdcd8f757964a086a8b9685a3da95a3c1ca45f6effe50ac2d26dbc9d2e79d60b6b045ab0c00e00d8a3dbc8cbb9968c25b20f010001	\\xd0a4e8cf74dae32446588877c0885cbbdbd49a81adf0b009ff0c7af61224cc6baa9b27ca5d3af10446d2684835357d2ff7bb0f4a1419cdb91ffa610fefec4903	1665309090000000	1665913890000000	1728985890000000	1823593890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
361	\\x5f2fae9077ea0220d26b11233a1724b31f4dda0fabfc7d680e1d525f42c1f8bff2a53f9bf8a23cfdb935fd3a9c3c24122f63d8170b27d4ab701452c88dbf811b	1	0	\\x000000010000000000800003a77809293be84dd6dd75c3311d053cb2b29f5238bb91bc261ae676721e886016ed5ed797c76d3f6f74d9dae08c50772c37e751b2fdcb58f28db039dd88d7a46b8dc17603f22add755ec36cc65b00f2e539aa02418ef5abacb98ee1b42040baf7cbb8f3cff6274ef545fe08195e5ccad72162db31392d62f0fa0e1b43aa34f0d5010001	\\xb5b9af79d76a6c5e151459db72a6bc0ac9c4839935635a2fcf85f56cfabf95d4a32833a59675e9b865f62e985aed33fc484b266f97c87ab52d87c66c53a5d80e	1673167590000000	1673772390000000	1736844390000000	1831452390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
362	\\x6547ca5e78697b2f5b2f17de1263cfc3b5e6530da89c73b1937cd358fb6e6d74cc5e5c2891f7b5c57f7c27f6fcab4c789c4d6560ff9786fcec72f10ee27dbe12	1	0	\\x000000010000000000800003b59426bdc6436390eb84175fc05a7c9d629d215bbe4db1bb51190001ac447c9460164f50edab7925cb1941b03a7a81c515eb0cf11d9b6048d765b24cd47d59f162fc9d76386809708e40e95dd70243dfb41f803d192966cd70bcfecc4bdded5ec0a1e2fc5d761543a65f45b368045a075b52b7b8f77f67092f05d5597ac6f1a1010001	\\x17ec07f0fbbfbad7d2b02b09acf71086797843df8afe65982532d814cd60d984afd1ce77d64f4c3417d772551dae7ca84ab562e234278712b75e2b056eed0707	1674981090000000	1675585890000000	1738657890000000	1833265890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
363	\\x6f63d54e2a15ded6cea16c39033b7e91e39b956848eb0ee65b1cc3aa3f45ce809bd8b3afc20a195b664b5cc28a9062d4c7c19cd153c247ac5a1277573ce15c40	1	0	\\x000000010000000000800003cafd598cc187666a8f2d2ce4db99d969b00fb4907a00e988f235c869408f688efe53e0c3c9dc837bdf0bc0fbf0e451ca3d714e356c8b3b9dcd2b6c0aae08642c02dfe99d17fbd21a99401e897e89ac47cedf6c4f765dd34be7e1b7c69eeb259c411950265a2081b958b26f178ce37554f5e70a766d5b8cbc20282625e0e0405f010001	\\xe57db8038642bb544eeffdb2b9162e8d9545f82134f29d7edfb05efd0a64fc2c43904757e2f7bdcbe6604db6e8b586ea067eb4f7af3d3492aa8d5ff929f1b20b	1648987590000000	1649592390000000	1712664390000000	1807272390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
364	\\x71079911a3ebbdfffba1bd6ea450f3d60a82457097ea4f08169f18c56950adaee14d9b9e2728c477f6f45a56e6b85773c6a429b6eec254a39ec654bb670d4755	1	0	\\x000000010000000000800003debb11c7b50af182d87cc6476713022cbc034fad5d8e15f47283027d9fb971e64e0bba72e25ff38856ed405134733e9811aa8e73a96206d56efd2e381945ea6f48b67ad6075af18cce4e3dbd209d35d5335f6419b218cd4cadca7923cb4a32509c342432ed214df45c08cc03c10da3a034dda8401aa071bed8e37074e58d8fbf010001	\\x1251c4caa801de9c2354a7bdfd4b4bb536f6b45105312dcd7ed9f4dc22394a78e39bdf1660ad4d31201f92146f198779f3206c07d39a9a1ce8abd13598329504	1648987590000000	1649592390000000	1712664390000000	1807272390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
365	\\x74e7cdec64acc2d0f20945791268b86f0df78d49d8907fa734c53a4820dcd8da80357292d95495e7eff8894cb5e14cf59a3cafdeefba0018e88eee34e1a62235	1	0	\\x000000010000000000800003b2dc82447716fe1da4b8923ecba4a879a50bfee52b32c3b4539bd002e98777437d23dc8d7e474d9338e955d2ad450764497e2a6e91082a1eaa89ca52049d49febc5925b9090a9c38b6468d11844a57c8634af29f2af942c7fddc92c0369b482ceeeb1f4283925d1ac868011b8a2e823c1ad9a2f9d4b1d40fa143eaeb64e10573010001	\\x520f4851d68d62176b50165d0c17c5daa3a5fd95141f7324400bf19326611ae94146bd207dd1bae873e144e11a90ed3e005ad83ac418e025f877cd529cfbb706	1661682090000000	1662286890000000	1725358890000000	1819966890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
366	\\x743b3b145026a8b9e4d648627ac7f6412c84d28130aabef17fb6e4ef7ab7f43bf76de25599a19f3f8034686311f5fa83f5f3a72fec7979b98215434b02b3c79a	1	0	\\x000000010000000000800003df9de81da534cb247601e58b8dbd36bf8d4bd75cac9a40be95b4788f442eeb4ed9cb12835c193581d2b356953a24369474ee0b49ea615fc0fbc280cbf27fb54751b24c5d1d5842bdb4e163670236b88d9cf1d8a930e44dfbe5ae646c0979c5bf43ba8a7ea08b986d1162b17a37d92e98e86e4a110e253ccede7a7620a58f4631010001	\\x063c22b7c729603e0c1882e02b7bd4e7467ba7bd985a9999aff734654aea907860460d2cce14dd6f3332303473f600cb4e91cec5d2449de21459e6fe0d0fee0f	1656846090000000	1657450890000000	1720522890000000	1815130890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
367	\\x7ac3dceee9f47b791c7d10e1af4b1f19edcabf91bc51ed7a5e995aaf92ce4d18cb4e8fc21fd9a14a4104cfb5e98523d2c7b611645b37f990add95376ae93a843	1	0	\\x000000010000000000800003b9a44e64e31b88182bdba8b5e89bae3959cd6966eca748da3a4f6c11922fa7a2650ae40b2fe5720f45727bdd8dd2959fe3d13566b1fb7a5d9fa1b64ec58f3156cf8de4ab202e7358e253857de8aa828af6a1019c4e9ab6873a53ef2dce59493fc61f4724e21b16170d1015c8ac09c1c526cf7b5e6a4be85df3a1c553aaddb911010001	\\xcb1233f2792aaea19d2142e6513ce36b46a7ec96ef1ebdc1e018da664d7d3c685c3d81171dd0f20e99e168fc6b848d822e06d8c859f42dd66d3ace785e56b90d	1656846090000000	1657450890000000	1720522890000000	1815130890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
368	\\x7e03e993172247dd3c4185cb8c41e5825ac5923fe2396b63400fc9b86f8a0fed4098ecca7a8687c650914073fc8f61df52a76f3666f4c4451a2178fb4e7078e3	1	0	\\x000000010000000000800003c710f7b120226029d6f1768f6a8a1c395b2df92c31a53380763e060f2d6eae01967dba23b10f3169a8c786c0baf5495c69bb45d235c136998e97c71bf78e0bd7b39a35217188e9f161ce1e5cb5186c161838c2133e3807fd71bb434993a3a753b5e01ebfa8bf9523b892d41079a98fe1c63efea069a485f999e8487dcf78f5df010001	\\xd2b49e10ab30c66080c9295be526370f8a9166ee461c333ccecb0e017739b8ad60048110feb14f0cc9a6b80b0103e927890c0f3b10122b955d55019a3911280b	1664704590000000	1665309390000000	1728381390000000	1822989390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
369	\\x80ff6e2ed0fb5e77d2e5c6a188f26e048cbbb307bee63c8c0f5542fdcaffaa863bdb215dd4d7cc2a9cd83dbdf9af65e40706715954b820472e3ad7c842aed0fd	1	0	\\x000000010000000000800003b0f2252ac48d0260de3c1f5ca6a54a86018e7d24754aed7dd5f02bcbeba62c584b94d6b2565b8a61084fc890c12b8adff4f62b1eb7d3b0cf325aed8185b2f6e5806428d77ee24ad172d7887056f851ae06f933594ee7b6c523e70efa54b7da6251090987e0efeed6be8015185c2062fe4ec30a424326212d52da3f379e191b63010001	\\x1703f224a7b480930859b03e2b96543989ef5c0ad60bc584f69e917b4d7e9041e0d827b567247a14f8de0eac3bec7917f9ebd09af0216e13d05324116cf7d20b	1661077590000000	1661682390000000	1724754390000000	1819362390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
370	\\x81e78064e12588535573a3ada7fba8341409a0e446a90636dc846aad5615454efc2028b759771fa709132ce435bd426da3876197247803a3ffe6664cee1ea808	1	0	\\x000000010000000000800003e0460edb7cdb3cb977170d19a1289d67bea9538506f0568c305fe2dfe92a885200477ac11ebc3799aa456da7429cc29bb34004a535a3af2c5209638ed4ac69f54cf3adfb45c0b8c22f998d031478545b0cb1e74eabfca29d3c797d4d5b73ba32fb86f99d570f9028325c734d166f42b7bbfcd32ffce16e2c37d4893ecaa92667010001	\\xd5a8bc2f4dc4187faa9c544323c5b3030cea5abc72bc460ff0e3f9b8cb11c1eb796a09309fbcf73ad2380e9a5d0da14c316b9bfdef06e05071862112ca517e02	1671958590000000	1672563390000000	1735635390000000	1830243390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
371	\\x838f1d3fae213037313cc30b45e0a9277a19391c5061d01988932b3d2632b01e023583a621e0d96b22649f7b86ff0bf0fb4ab4238c36f1fb84b2d76d5384895c	1	0	\\x000000010000000000800003d584ffaa1f20f41d8c6aa802520ac49dddb10f473b3f130296e8690d7292d26580af1b5688371e6765e754f06b0b914bfd08ae1662cef27fde3ff91e44549cc17dc26008e93f416f4d1d546694686eddfea449b05a560a3994e7b5600207a2f93e6cf83fc62b4af3971436f4cb05ace442aa5bdd2a2387374b15ea9b107b6a6b010001	\\xa73ab478edaf4d9e94bddbac2b18f3b545019367c94678c4fa692d0d111b248cd64feb646ffa5e5adaccfb42c2ac5fbda172c86b459d4ee6ae83940ebb08ba00	1669540590000000	1670145390000000	1733217390000000	1827825390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
372	\\x84c756695bffca3d981053aa2785e95efbf8e1f67a306b761b68210573f5cfb34e191d72c282a1458d5badf212830966bdc9679b77024849c00e7ffe5bb03aa8	1	0	\\x000000010000000000800003bb0327e8ea2b539be326ce0b2321ffc679bc70739ec0d508b503b953b457d243fd4cb500a5054ae5125ba9af31aa0d50c5c1c88af8bee2d20360795728e3bad04add6af8013fec7d177cc30db0c4758e4b6c72e6a64ced4c1d04dc7027c1fba4ad26476a983da5f632ff468157f306685c8f060f3593f22825f7f8b47d5e2a83010001	\\x1d73528e3a2d244032cf91ad494cb2d12b53d421243b47f4bb5e4a9073142fd47ebdb3b4eddbe30d02c191395858fc0d1cc6f6ba6072d8b9ec07ed9747d71f00	1663495590000000	1664100390000000	1727172390000000	1821780390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
373	\\x843bc4c0200ed42ee07b9d672f25a5e14d87225669fb4c70ac3d883e7679947e85a238d41432145de435d37f84079f9b01b492237047c7d7701d8d234aaa6f9f	1	0	\\x000000010000000000800003d5e553590dbdcb2970c41074519ed3f43a37496c3399ea61dbc85ea3e934237260dbb179c82926e946f634771236f35e427d1ac9fc04aec462e5f9c0421dc79de3f7f8a1ee4ca7c166a873c1f4f30e7a0750e0ae8a00f0bed0dca939577bc6f82afafda0066bf0c8972c024174927116a2170ae5c9dd7016c62d7bc9ed6bbd07010001	\\x9bda5ce132a2eb7be58380eee8c78e904fc384d8773bffe58541cb4e783d94cdc0a1a691948b5177a73445549599f29e92f8640e122c09bb8ded2476245d2304	1655637090000000	1656241890000000	1719313890000000	1813921890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
374	\\x85cb3f3e00bbe7c78a207bbd713193a6e1de38afb0f92c03942735b6b6bd041759db3bfa1d4ede3d78344f8f74c26321fbe69762a4fd5ba53b5b65d422168f4f	1	0	\\x000000010000000000800003a66a0f68fbcdb15844ee6011b034dd63ed7995beefd0c75f6619ec2122469720cea73d8ed6ef8ce93b34a8f14fc921bc0cc9b7e2cee5097fe4943828c4d948ba29c3a449a23db37b8c6a8652e04196defd808dcc622adde93de60f3f1af59c7fc8a7d173a2a28526b152db92191cf232be161e49c36c4cd2e07324db3d9901cf010001	\\xc106252b00b18a4ccda18a39963a654e9f91ce71265eff7dc64bad2035992c826279f1b14e7036ae873ebfe7ad27527b7d7094282ee769c268fb6d3ce9e1d404	1653823590000000	1654428390000000	1717500390000000	1812108390000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
375	\\x8a37d1b5a7df26885c8815dc472c062d5a9b1885c4a2ccce69c434071a7b949cf530f207977d2a7a61fdb7b0587a2b2e7dd1ad4abc4ad13da197a5f710e5340e	1	0	\\x000000010000000000800003c436bb2a957b6a57ddf4a41f3c3f6abef693b686ae10e8c3d38e1284094579066888a033597d43a7b20686671edb0ab292d30e59b63a15558bbf0b628ad7ff8bec69888d6e5a5dbfc7e7bca07f8b8c65d8607e047294dd7e37ce5fe2209140d360a8abf2c14fe65039fa30d462b3644eaee9268365cb454b77d2a5b3a9e87e79010001	\\xa8191319e2813218cfad58d0d6dd88799696fa83378f3b2b708e1d675fe64d7015d8506246f574c50c554d09b088e486196929b43646e0c0bca2ffbede4b2606	1658055090000000	1658659890000000	1721731890000000	1816339890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
376	\\x8bff65543ba0470239e69304ed81cbccda2d75f743ed6de2773a86888645211af129b728e191b01928bd7f666ad7f6b5d19166221894b63fa291c45e8b3f5ee7	1	0	\\x000000010000000000800003c1b1e5f3bdbfceaa40ca2056df83a9ffef0c35eef133841fb9d050db26a3a678c48a240108cfa5e93b996a91b1c6b89d87490d4c69ce23a361aabaae9d384b3023126b0725b3f2a78891b2198e8253eaf0e259e34a651189c32690a23c2779c4392a1b6cdada441bfcff76f25d74006bca46cadbe250bcf3ef3ce713aec377c1010001	\\x7db5132c6bc457ea6c31cc0019896f07b920b55440bb94b35c2c3f5e2a4cdbde2ef55697fbef53f908e5e44b570372d3a03d9051fa0fa647e6e6b8d72e9ed001	1673167590000000	1673772390000000	1736844390000000	1831452390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
377	\\x8c5748752dd9dc6e978262a0b9debb1b9c9b53d2b59c06771ff94a42b1b9b8e46942514fa2365a0efa979eac7fc4210b156cde0d3c7adca2c1cdfe1e022f7c20	1	0	\\x000000010000000000800003daa4c2ac502bd98933fddb65bb1e6d0ef948a1708ebc25bf7c99d74b895146ee1e0531ef702d51c485d31f90fae7ecbf4a3f3a1dbaf319e35a623d561799505eaf15e6203981010a44a77330a1dfc2332b0a0b7ec60994d2ae090faa53ffbd84ee47283b5c8f634f23d2830bbd3c4269a5d64ed65e8a181bbd8b69378abf359d010001	\\xd3b6728c696886f0cee6d930c4eacba00d3c93d20c392fe69dbcba91c2d9331bbf740b54b86a2726190b20e773bce2f705a21f000207a8cd6c5ab447f3369207	1654428090000000	1655032890000000	1718104890000000	1812712890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
378	\\x8deb88272e9b9ca79f1014c8f309ac01acfa1d041702aa4af5f9209c585a8d290d2d442088ebd51147edeb727149e7cfce9932eea68e393850321e557552228f	1	0	\\x000000010000000000800003c283f92a47491cfa809ec23b4ca484f1cf7f619372e8154c09b199e98f3a912244288d8169f1052de8b03ba9d15d524d76c9975d9d628e93f022e48df3b517453e680c2c40175e8bf7e38b71e9d677ab128818afebf6e562898d47ddfc22f6a30c3ba4566242a573fce87ac1406d0fff3635848f754a8089addaef213e1f7057010001	\\xb8e8a07e6c56b73f87bef57bf54474cb24a4e2a88ade9aeb3f76108dabf776a0af9d8a3a060d3b498c4eca6d9e255c33045f136c3a93ea8dd9eeef7643f17505	1657450590000000	1658055390000000	1721127390000000	1815735390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
379	\\x912fcd636ec843ca4d6f824e84bb0c94a0514104496ec30e7a39d6558c81e9d2a7f17e9d52b6041f9be81b12990caf57d2db1c7c6dca4e85b805d6415e61bc29	1	0	\\x000000010000000000800003b878c1c3fb8c44affad2d7f4f89b134d2e42c2b4a5bbcbea7a642243733855b2727e9f2a6db5f345489e62a04feac0151971d2c07900f9dd0539a1b67081204848652bb6ec118a2bd034567cbb47ee8606655fc02fe9754dbf9c38634fe8ba69e5496fd4efb2b39c2bac600a4af7fc2cde367220be2751d727bb27eb33da5741010001	\\xb427ca439c103592ad4d4db5e49085b4694d9894f561b34bb7bf02eec20f932a5ea265cefdbf89d1c2bfe468fcb06616693dd5d9803b47ea58e45d2ab4bd0807	1665309090000000	1665913890000000	1728985890000000	1823593890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
380	\\x932fe1c946298e7456ae2a60ce2b5662224761295fe5a62edfe2eeccebd1d0bd00904e0f437c46164e76fab168256011a612a8d26e385f4f8b71ec6ef7e468a6	1	0	\\x000000010000000000800003c4141b07986b2e4ad9927320326c94909de34211ece50ab8af2481722c71de4bd0b7f0b25c262390da6a53a00300150a66a674558e559c8369c2aeacf5ec6d1c8768e10c90a16d9165ef7847db6c7aa9dd542e78f914323ab8785ac9842ad08a5efa398a31df14cd26bd61e5178f53156454265f2e9917e8a36f14d2b58ec299010001	\\x71cb6ae76fbad319e543edde123d40b80ba1d1f7a2a8619abefa3038620c0717edf8a6993083559c829e2b2298fac04e742c13665557a76bee3f970b7c7b1503	1665309090000000	1665913890000000	1728985890000000	1823593890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
381	\\x94dba238e64ac3cfdea83884021c6dd54be5a5d51cd25fea645bb1998f77fecfcde2deb7a0c12bf18621efa03bbca1c0b7cfb270b1ebbf31fcf3ab111e1354f3	1	0	\\x000000010000000000800003b12efb67c7b730e473983c0c8fb92ebf9a0d210c95d7d1dbc88c23141b049f6d389a158cbbc8021d59e313c5521f28d903d78ea7b6dea90aa7bcef4e74ca270a2b37bfb3d38ff9e519f350703567213c492551d2dd30d2ad57d2631f4bc1ca9b26233658ca6e65fee8c09ece2707b93b6ad914956645ce96f68250e037b59501010001	\\x85be7e142abe4101771a1a16d9070510a29862e5e737a602645e59a32e1420eedd51732a077e1109e6fcf2830018578982834db33f937314e12a3879163f9f05	1656846090000000	1657450890000000	1720522890000000	1815130890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
382	\\x96ab195a6ad914642873431a2f675a0305dbbf35514e2a6aa872813b22bfbf1225da0de43ae3f19904bbc2205f947c629e7e097de85617ecd8c44d4bda3f9f39	1	0	\\x000000010000000000800003c79c5b4f64e94c39b3ab85cb622549fd9045f2aa629ef23fcc5e9a2142a1a0dbd057f811a0ae42889df425004da93726230a7f28bbb427e5bb3263b4e45beaf00ac9efa3627f778ac2c053ba1d61387999ef19b10e532123ade35dd1cc7816cf2ffd6438038f5857ea50b48771ddfca269ee24810d8da5c419250790e7649a43010001	\\xe841b79c3787bd0ed62af3e43c15399f1a91f49b228c56ba5588ef72ae4169999edb10ab346f1a8281b4e7db2bfbccb6f7a0f6274eff64a3a4f4372242f85c02	1653823590000000	1654428390000000	1717500390000000	1812108390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
383	\\x9be3d264958963f39d1b0434604a07532804899b1b0286af4a6c6468f25a2f358376d35f6c23c713ae638ee6d52a16835940395492477ab4016eacb426a927a7	1	0	\\x000000010000000000800003c5ec65e213edbf91ffd47410ae66612cdc7c4fd8a85dd6fa9b9652cb1e770f54948bc82c9939ff3e183a5fce569a857dfc6ecd37d205571467fae4a7c618450e5d5895b9707d03074726e6acd7e7cbbc73ceab7df32b7e2478d1ed8a5ad21b2fa3377b8e7ad94d5b27b503d10513f3ae0f23cf96d0be7b84ba81b9843983ed53010001	\\xd21b96e0fc677b0867b9ea643713d8d1775f88b99c134941178dcdb858923ded9b7289a9bccdf052a581b2d94d78f9dcfd6f694e07977316e30572bfb3c1a802	1658659590000000	1659264390000000	1722336390000000	1816944390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
384	\\x9c3b7eb045bf47e9b11b9004285ce9be5ef8b810c91dfbf8fe4fb6c7e36284826e5b0b7e8eb2419dc1a417aa9240edb9df7365dbde525e41c11677b81741d209	1	0	\\x000000010000000000800003c16d23207a35a69b09ebe64b4a075de9795fa757b840597e339d4a9abebfd9e15873fe2cbd6e22720718995c644f8d6a9e8df6e69e527bac00217c0ab3cf41f1d8b15a67de84ad76e150b044242c609c5a0b712c9cb3a636f328233f190f29916a58b794cf7c0b44c37a7efd5339fad39f2b0f7ca96ad94f26e6b8181f02c131010001	\\x3d0dc76be1a9307005e67a2cad6973fb5372d54f52b2933aedce175901b88b1a52f6edab1480f13118ce90d2903cec1fa3d073b6f2aa7890d25640d025633e08	1667727090000000	1668331890000000	1731403890000000	1826011890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
385	\\x9e83d53bff4b13e66b9797e462a2ac5b2a8f21a8ec1aeb6fda1effbd61ab329bb732bc7f83a9c726ef57ea35f283c12cd31621b413df56a384ad8132c548978c	1	0	\\x000000010000000000800003c0c8d45a7c0b0dddae933c4f2ca08fa28c8625164bea6d434e73be1e70b5b7c60cb0cebb07ef65287a44ed54e4f1fc2000ec233bb9b036a41949ad80633facd99a6c586ddd58987b31483c9b8f7c4335a931f692855d8df5e83087c5ad0b1e02324428f6e03c1f7e2a4a4640c6a770750519670383e2bcaaefea74747fc7a179010001	\\xbcadeb0657e840bf82064c57cf076427b77741dba3f4a6c3cfa76e445be9fe1f0bead9a90eb07d3b2574b474ed3c0d9726b68e8ff6a3c20e0aff779716fe9d06	1669540590000000	1670145390000000	1733217390000000	1827825390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
386	\\xa03bb03d459085f6dcd9f3a1decee12f648d995fe13298c6cb60f3a663ac6b3774e3bab5104e2c50ef2820464d7138a07771090bce173db338fb15b48f2dc590	1	0	\\x000000010000000000800003d56e0ea3481261761b1e6204126a921e131b091f5e5ea79c30caffe935374bcadcb2e9d47f750610f053d01b2f6ec3cdbe5f60fb63cda5f514ada76c0833e9a16b19bf0db391214b2f9c3b4208beb9864aee6d66e62ff912cb6dc84341693aa02330b9e8441bee5f17013795e206908472f6762a11e2056adfd4422d2b403cd7010001	\\x94c8d27ad38957da119acc5170886a26c8147b82311d814224e0490cba042e439a881b56d4b779bb922477768fa93bd20fe30983f7795c252f34da98aa763108	1655032590000000	1655637390000000	1718709390000000	1813317390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
387	\\xa2df38f92e59cd62e2dc82c1058738659abf05702dd1a517abb3dccff955b3cbebc3be031d0fc7baf13bb54f15b34f246cf3f5a68ef470f34ec20679c4b16253	1	0	\\x000000010000000000800003b9311cfdd481c44b2940c6fd28575183bd78ca1986207c8bf1644d43545d1153aa28557b30549a832c4aedb83989bb208285fa7065e4d2c13f4e15efe309ba381c20891cebb0fa105923716646e7eaa6a6cb1e8f22af959fc34774d4e7faaa128f2ab98cb19e3d941f9ac587e86f9b89897d81623c794ea5503c6ba0df24757b010001	\\xcc132a2d26c4f5a4d02ae18f237573345135662aca2e5a28a64afdb1ae3e78115a6e5db89d58381a4531081e3340c4cac0c682525fc0954908c0be65b09aba0e	1650801090000000	1651405890000000	1714477890000000	1809085890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
388	\\xa58b32ce8e67e59efc9dad2a842e8fb850e7cf8fa0878fd5c5b22a3b3420f0508309987145397ec3e9c8049927842fca9c2079efd2ad5886d28bc56e94014de6	1	0	\\x00000001000000000080000396dd90ccc14e85beaf713b34344bd6d24e9f8e9c4ac071ccb4ec92821128fb8f472ed0caedfca03927192f6b56ce0db8de7918630782a84617a78828086ef949ab7bc8e2d5531787c598025387e0d776077300aea63191d1a674dd90600e05e6fa1b9ae1c565c863c2112619089d421b269e072ca2394629329b36838e3f62b9010001	\\xe039d4422b03c904410e7f40e97ad8097813c200c75a3a3b849c6ebb69aaa539a9d6db130a2b478b32fc3a1549eaf006a72ebf0002a8e76153c6e68f91a81c0e	1662891090000000	1663495890000000	1726567890000000	1821175890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
389	\\xa517755140a976e5cfa190e8f397196294dee0ba452f5bcc1f9420e251ca68ebca05a697c689641817f0abc16ddbee02df6722f11c9b20e01c1abf6ea4c13850	1	0	\\x000000010000000000800003c12a170a941867181214d4adf14a98968dfd6aa2e661e20df3caefc8452703175264ff80ef813313bd4f8e4702644df69df6620cdf85493fada71ddcc10e24d4001590e878226c5e2ff0c3751bde4894c49f1d9b4b5f792b8e6ab2aaab8bda71d2be7a715c557972be7b329b817ff338c1d6dcdb741c9ed3a31486477e0af6b7010001	\\xdbcf10144c703c902f3ed447b99dc7b78dfd9eceaae8c655ead451efa1656bdc9129ecb3e009a6e38a5673a26fa147525e40a85d4a9fc2df440d632eea54970e	1651405590000000	1652010390000000	1715082390000000	1809690390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
390	\\xab6ffca405211acbecb92afa4689c323b3e2f3ecced293fc2764deb10c9c7b95950fec12b3cdb7146e2a6b4baa6d8b043bde194c127e6c3550cc4590c5bb9188	1	0	\\x000000010000000000800003bad18f647fa60ee3ccf4777e12ed776cac996be563ecfee56ff11c053a02be32081191b9d5347f11fe1b6249875885b34e118fe9f4b845d2a8683d925fb742f758654cfe1c00914b9dd324d39c5e3f5147085432ea4606d1aa9ec2a4bede5e52c884dd397b0da4a4bf195c64fdbb0e6d5b80478742804b56a742020cd56a8bfb010001	\\x7cd19ca10fdc817ba55bf56f4e6fe98978002f57c74b25721010245b9eca832a2911c5c7a76278dfa9e2b48d1bd022e6a11f048fdda7c32a407d8a12539fb501	1652614590000000	1653219390000000	1716291390000000	1810899390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
391	\\xac9f36e9cde1b77ade0177515af6b5a8c5d198820c3acf76e36e36b2f8f3796d65b24346868834c8769ab5044727954c914ba85f2eaca9340f2836cfeb884d3e	1	0	\\x000000010000000000800003bf31256774dd0a0416f372f74a4c20925f24f057abcf716bb0e6d6b81ad50d7a064f6d4ff25c3c56d84d94d3bd38f2e69214efd373f52481403865b83b2d58badd2036874d7811cf5af9fe41d79acf9a7041791911bfb9b89c0f70e6a8b9bbe07ef405892dd4f8bb03ce11dcbe88a82912b97efdc763176fb45947161c17e92d010001	\\xa5a6e5f71fdf582215909d0e248bd1765dbaab2934dd0c4f1e96ab78af749cd2f4dd270226903cfbb373d687d6dfc981319aa92867e5dc123718728a84abb20a	1674981090000000	1675585890000000	1738657890000000	1833265890000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
392	\\xb3fb4d71caf36d829547f746cd022770f96ae6e9d9cc5095e37a68c0ce932c9aaa831c4014321ee8f3c44f7bf2969d21f066e721cd546be92a1715de66bfbbb0	1	0	\\x000000010000000000800003a757f0d75a147f7c3ff01f4c824471a4bb280ac8520ba38d975196ae48c0e337356826d9a78ca714ff260aa242f188efc973ce5ad4ed0dac3d9c4c39cf9c5abb13f5eb8ba73c87205af617c705472f2a9b7694f4efc1a72b8944543dc5752625e7c13d36dbc63063d6cb502684fec589a563e4cc8a41025d50ee4641621cdb2b010001	\\x6a6c0fac7185fcd8ab49194364011b86abe98a077fb5864b4e8801fbcbd899baff4eb31bc5c42ec236485faa5ecbdab34bbce4d608bb3a402d346f60a3509f02	1664100090000000	1664704890000000	1727776890000000	1822384890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
393	\\xb33fcf098466951f24ade7e2e930182cfd5a0eeb297088fc8b72376c0f7a352b8e8f40301eecd47db6fe18f7a6371cdfb5ece3f6f53379b50bde7ca226923535	1	0	\\x000000010000000000800003ad0ff8a1c5dee593cd4f3f8b1766ee35c7279973c08fc9ae6b2ce422381d706b745fed8590c834bc1761d99a6d0c0f5c1e5e7c41ecf210a9bc1d8c8c70120c66b2a7214c2ce91edf8333f1e14e85031ab2fb422d1b7063e676ed484a6deb40bbd1657faac8194d9c28a475697d078d9db56926d6925803e3bcc4a9956ea49a51010001	\\xb7136393766e41c05d7ae49a2565cf8f844e9defeedbd1af4a4f05f17ab0c91537e97370c3d958a5633805e91bfd60a34bb6dc40e827873c7cc37f083f7c7f0b	1679212590000000	1679817390000000	1742889390000000	1837497390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
394	\\xb3cf70420375a5b4736cce9dbd795c479fa3dad6bc33697ddbe1dc50614e0fe18160b0b15d221fe0bf1008d3f33c7157e697a573f7e753c9d2a8992100762a9b	1	0	\\x000000010000000000800003c6031b33f9119288f0e221411608d02521cadaaba6214c4255262e7dd7d56fd0f06d2f7438b63f133344f1a0eb8dcfbf5e9bde926f721d49342745dbe4d814078fee795349caa2c608b52bc44225447c190c2baa8de40e6ebcfb41597c9d1320cb9165b47aad2d9a5ffea4e2ea30c474cee21d1009138fdc4e789612a672c071010001	\\x7c7a282512ab2cbf680a4bdb1da89049e5020c411c32ba75b20b84ee2f005a9ce9c2e23f257c954856b375e5d5cdfe3c047edd4b5fd46be501f201737d3d680f	1652010090000000	1652614890000000	1715686890000000	1810294890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
395	\\xb5c79d8cb3a26bb211677b32ea56c720112a5c74ff1c4b2b1e76395e33169fc69d8d09af69109886488207a1da887b4a493ddaaf916d87e15e9ec2d48e361d7a	1	0	\\x000000010000000000800003e12e71e9e5f4b463b87c338421aeb891f267f508ebde60d55312f1de753523b66ec12768a25b85391a128cf346102e9ea5196bffeeabfd7ad7b527ebb8fe09463b7817c8ced5f4a478d8778c75aab330d2fcd98bde303c25f5fb5d48010707baacbdc3ffe2b7ac1193cfcf61cb0add32c8538f8618f099e8cc2fef3199e280a3010001	\\x3d31af6849797926b5799c00370678810eccb321b56312837bd14f42c6c1eb06c8330f18a9c1f431e44ed155805b02bc6b4ac00de8d09acecca68d0508cdc00f	1676794590000000	1677399390000000	1740471390000000	1835079390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
396	\\xbf6f59352c1d3d9ee00bf8e0f985c847a636c5a1978325365e7cb0631db758967ff10e36007a76071a298a1f3818b3fe40fdb731a68f199af37c4963ae04acbb	1	0	\\x000000010000000000800003c4d423f7e23d14b87d3e5a8530d053f006772e0faf0e06b1fa193ea8db8513bcf54f596ec1d181be32c79cae32fb36589298d0a53fb4dde7a26f3a65e8757838a1dfc96a1b08286961bc93d23e2f20bb823fc35227a93779e3861323078dabd67facef69890ac52807838beaebce452e0d76664e515126b9a7664fa52353e931010001	\\x2902de13c2b35397c8957c78055457efc62536df408d531f8da602d0e4a66b871292976f59a231ef697ff1426c2f8df8c03a9bc0c0627c1fa996661127fb0e05	1660473090000000	1661077890000000	1724149890000000	1818757890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
397	\\xc2e38e8c6831aaf32d6d2fa1e623c8d686ecb0bbc972a83b5d0857c7cb202098921407f770dde4af31b849a3d01b39da85ef6f8a3a03fc01407d97ff9aad1cb0	1	0	\\x000000010000000000800003ac1883ae31bc284ab017ae784aadddd9fd7fc3b1a0bfa8d432100ea1feb9f9c665f99b35bc526e738443c83196b0b79aff137db034c1642669db9811a4966e97b86f867eabc180bb1a6f313d2ed82f95ebbb29ccd14d10b4e7fb5733c5acdf9887df5234b9be643407e90ec80dd972954abb3b026e0ee6c9fcf379df7cdc218d010001	\\xb19a3bedfeffc839b86bb7e2871a2483975e8c8727c5c168687e1df8498dd8e59f5fea87ffe6506e397b10c5e7bdeabdce400b52a44f1eb4f0b69431b8b4ab09	1658055090000000	1658659890000000	1721731890000000	1816339890000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
398	\\xc49b633fcadae6767efbf9c1b3e8eade7149aa3ca7f74362580021c60a14b41d20ebc6696ddbc83008e62ddcba8b5283d35285e6df0c8758fbeae159f52fbd6f	1	0	\\x000000010000000000800003c62889cae3806b81e406df73437051407ce73a1f5fef9363bd4065c154b16ce3ca2c570b8d3757432f1049937d819a39bfed65ce4d33408d1727d2d37c2b0a31c7033aad524ca5836413bd91d4093e7611c7a31e589b58f65b25311e44c40c1d0c6c7419eedb64e9321ffefd3f9210be5e07acbb09fcab6db2e2e3c7b54c4daf010001	\\x3361bd68294d72cb52412f28593d9f2eb5df4308e042b52ab7b9505829159a0567aea09bab7bf0fa5c5288bdb5eb82c0e587a8eca06484dc082943efc8bf7a07	1674981090000000	1675585890000000	1738657890000000	1833265890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
399	\\xc66bdad68c3c8eb7d5f29762e11e1acd1c744b44746befef59fb8a50081b7dfc5a62d7ec69ead37c594b700649b8fe14cf81f4bd47fafdcbe0724de9841a2abe	1	0	\\x0000000100000000008000039c17552c6291c90b76efd1014302a9ec93548a9dd17276b2aa978e06fe0105757e2416c11afdc2ea36b35447d4477cc9211175debfb66c45b67939f93169cf1a0ce7f947880ba0130ab57dfa4a5db6daf04982185801a2bec43963222a801f251a87fb6c6553eff915dff349abea677f311f55a9ee5e9f359aed24e9bad36a5b010001	\\x5948799db68fccd0c74d1668a4ca487516e5c5530904b5bf4063361f3887e2beef9bab8941b8860459019d444b616c2190d7798592fa04eb616adb8f0d4db103	1665309090000000	1665913890000000	1728985890000000	1823593890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
400	\\xc89f64fe1805009c976406b949ede69f97a8d87d28b6e54c326e1c27acc3f7d70a8075e7247a30e988bf3dc2464ddeceda20038a751360601c074bb9600dd782	1	0	\\x000000010000000000800003f962f89f567241a6f084bd3c4c57cdf30b55a2a640b0db58c63020ddddf6284668d6f2153beba5a2c29caa2111c163038dc48c08efbbdbc91a5a0fab44ae3fc4fce7b69e76e69bbf76d2a251b8f11e15eb534e22067830b785114211f1763ea3fff25bc437ff884b7e5d3690e07108c07bdbdb9141340b5e49286020436a0bed010001	\\x272160a5b8cdb01143f1d257ad378154493fb8b33a2f29e58be1d72573bd00e5f30391090b011fa9648f05b3dd78644f3ef8c6d84649e5bf02f69f0c34feef04	1659868590000000	1660473390000000	1723545390000000	1818153390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
401	\\xcca7c90af687f682bf23918521feea2c87186e7e8e7b32a82ed586c57194577edfdb063523eac0ee35d5b0d2f4512493892874ab13adb55ecaca1fd2eab3ac42	1	0	\\x000000010000000000800003b2e147fa48c3fe3fbb1d88129d2a363398efca40ef38c67498feee67f21037669e19f778708c5da9f19ccaa9afc519773d2c14e44e7afb3d26861b2a3da30cb425dc071059f0324f490176a917392173a80891cc20ce7effd37d6e9e8bec3967e4b817836f98e23334eab55e3d27f6cc65cb2c8dc7c590dd0c2fa79768d09359010001	\\x81af6963e0aa6c36b2d7fcd95035585b1ee9ccb3f5788e23cbf3d1e728b73d97db8ce1245043b35c3e3a3bfba4e5070282f197b2373bf529bbfe48c4448e920e	1678003590000000	1678608390000000	1741680390000000	1836288390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
402	\\xcdb3dff0cf778c64ce5cba95bfc7f5a5f73502f1c95ed3892fd6ac45096e1169566a03cf42285e49d96883afa082c5b3babb9dc5396d469f80a69c4bdcc99b9b	1	0	\\x000000010000000000800003cc85f43d2486e1db1b3a7da4d08ac306c6caa234430a462330de6a7e2a24b49c379286392a1f61736c53cd42667af297525551e67c2a9ea5e519144d879bded6634f1d1648555b39cbab607348233f2111adf213628edbc2898d99b3922bb965783c42c017800190c1941cf02a04a9f75faacb3db7e297bd8fcd51923138f353010001	\\xe16513db3771d88eb32f1f9812cc66657634aa7239687ef270149c267c0a919a7d61c6c76d1fe1cacf63c368f510e7f5d624a9de0d781309fdcfd167f4346204	1676190090000000	1676794890000000	1739866890000000	1834474890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
403	\\xce8ba313db8b3211975362a65a2c4a8d5c53aa229ac154423e9ad8b36251bb33cb2a8a4b27acdab69e0b6c74fbb083e500a03b09c20bd5218cd7a994fddd50f6	1	0	\\x000000010000000000800003ef6584bfd82321d0d66ed71d609ca30974d43382d261be7cad09945aab954822fcbb7854633a99420c89b502e2f80059c71e48d7893783196e82198e8583f10eff19df310101761b9eb4a2bc30fa2513c819d960982346098747fcf5abe6e44524ab141336de6d5103bfde501dbceeb6e64816cffea47396ad914f3e69865f43010001	\\x0d0530ef9e873cbe93354ee2f22b3d543a3becc5a94f04f8ecb0da97a0434b012f6869c25a63c6a458299cf65cc894576fa2d8ee6db9d426778372880402ce0f	1658055090000000	1658659890000000	1721731890000000	1816339890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
404	\\xd0eb82f2145c8f7999d05b2cb0d4a47a7078d7fc5ec3cb7a5a5539ef7e854f2a7519ac31f6809998f09d96e69eca6ce05f11449e6e0ced3dbc74a4a5d50e6ed7	1	0	\\x000000010000000000800003acd13be74b42f4458720565749c627e4afbf6b7e4362ea08fe984b729876ffc3356b1e6212699d51c7c0e191400385d631beeae82240027ee21d30dd7f5c4d02f94cf6b4178941c3c98f30d0fbae0bd7cf4a5117c1e21f77e67fa9ea212c05761a68ad7a0fc51eeaf1f5eb14c077ffcd51571c157f4fb33cafcbab1d16b647d5010001	\\x43fb271684c3a2925b6ed9adf20afe171661917d59aab6e7ccdab63c6ef3e50f904ba3da221ed93153fb08faa3bdb16b989e9e1fe35d63a8ab232d07327cc201	1670145090000000	1670749890000000	1733821890000000	1828429890000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
405	\\xd313e05f9d9ba4f6d1be7bc915b95fa497642507b3bd893b8df214830d516e670705f57a79fab636dd31390dfa5123a9f93a17e654a4d7271a0cb4d250a15f14	1	0	\\x000000010000000000800003b1df3c86613f325a2898018d20e259c441373a34ccade7e24235c508de1f26ef164340e2dacf02e17279d24b62c03937fb0a43e5b0636525f70bc7cdc2f14ea786f7455e26c08ac5aeeac466783c834fc74dcc9f35fcb7eab9f02b062c8dcd54e2661cbc8a392b79c3c229e11408906432a2dc134b3b3a604ba5c3867d3a2fa5010001	\\x311945bbfd3de570678b64b9f3b545a9a7cf8add6dd282b1d516cd5706ef667a3dcbae899046f8d6654d36de63463cdfcf7942d04884a24e890bc793aefeb703	1648987590000000	1649592390000000	1712664390000000	1807272390000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
406	\\xd44b342a81582bb93d87131f1dacdf50af9116ec8aaa6715ca30181a45ba6c9b2a5d4916e662c9e7ce351534cc1f84a94a16f6cbb3a1d4ddd6ccbcd478bb134f	1	0	\\x000000010000000000800003c7375bdd39c1cff81f1cce09a2de2e971873fa521a677cbdee20d868a9e6d8b150ff51a999d25952bdfa150a43e2c90d2333f39b5f71f8f1e964c54a29d13fdb90b07278e6a0b302bc3b3591cc5175682cd737e3d34a9fa85e323f2255a0e5d1e19f0f5d10f74d27a5ab9abfb88041255b5e6256dd360c3992210660790ffcbb010001	\\x56f6a52551afd26bdc68439dcac25c636819e33b6a30cece077ee5439ee04e961a20b69e178589c411c188c0cc4d58eb746ea8e57f2269d0e792b5d853f5330a	1671354090000000	1671958890000000	1735030890000000	1829638890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
407	\\xd667acaf49bd33a251dde71c2fd4864a6a8c699ff10e1bddbd94794b63c2cc6ca30ca3717ab2b36d8bf59a3717f68dabd5b18f8fa7d79d662df2dd0510f943a1	1	0	\\x000000010000000000800003d2a569a070536ff2717a41654428c03708bdf98c29311b61cdd416ece431ff76ddb45f2c21d52cf809dd21894f17585fd6f77d098fcb77c295d69667c66323570b38fe289862b175ec0f2b27efbbda43bb384568c2b144e339f04a7bca333fb6154cbd16f3345370867069504ba86dcd933d0b97942577c502446bd926c1408b010001	\\xaf93f3b9845bba5579b9c9e11b6f5afcc9ea725da86a2c50b18cbbcb694acc1a96f7e80f887cc0b2c48a082beea507b684485f6ccd319a8e940ed883ce26910b	1661682090000000	1662286890000000	1725358890000000	1819966890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
408	\\xd7df62108464251dc3ee5c2d5074e67b4c5d2f44fc2a097b59617eb0b2aff15f1fdf9ab814d0dd83779eb71ab6a3046dc0b5403017e0a37cb5d4b2e0c0b40b4d	1	0	\\x000000010000000000800003d043a637c5084a8b0b935b4e7e8c5c6d31257b66ec35c1271a3b7251bb290a639745751f61693025f8f90256fab63631650aaee59e6f6dd98047343cfe7e87c24a6c73811e4b2eb5364fee53ee4865597fb665a0e001364396fc9f43f297d91684e541590640d2bfb00fb0ad6f825f84d25bbadadd325a31163678dc3ec2e9d7010001	\\x740469547a485297f86756f9dce4343628779895d4531c5b8441e2bf4e296113e12c24c2d75aa0d967b8515cfa736025b44bc4abfd4fa769c48b129ba3811c01	1659868590000000	1660473390000000	1723545390000000	1818153390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
409	\\xdba7acd2a4e11c635607707ec5515c4569d9e70ba7059826063136d89bff5c3841e034d437b773a74b71a8a770b77fc0b1b82ec33512c7e0e6c72542e422a1e9	1	0	\\x000000010000000000800003b73caed569b0cbe4455afe0769d23f34d1405ea1cfb9355225f0514f644d32ea73e75534c77b87a9c22685f7e9538ea58c60de68c640d12189b50ce6a7ea612be7d2638b1705b7cde6e7cd21149af87de255327663942743356ab4ffa4f1601f149a353232812ec7bf8b211ffba5a739f042bd5a591e06fb3a78d03a73c6e1c9010001	\\x2fa78ff53691338f23010b1700069aaa5f91d28f005695cc176e007198e27c1ed653f4190e43c95fc62234c57f32721f7ae1b224ab6b4601aa6ddfc336e0e10d	1667122590000000	1667727390000000	1730799390000000	1825407390000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
410	\\xdb4fcb06d71bd4cfbad05dde63604bfd093ba0e410b5f5e4ae64363f638767e9d07d2083a89f5d3e949ff256d1487b233eb501cf978ae2b5674b71cadd866c80	1	0	\\x000000010000000000800003e012baf19325d7a2ecd2d3271cf36fde720f457d371817868a217e957078e7bf49e71e8268f0938ab2c710857bbbff1ab581a9e840ce68070a90e979c6b0f0884e270738192d6c3574950f10977b5fc1cbc29bbf953d5cc4a93eb6c63ee2d71a58605acaf4d684c9b155dc0e221d406ba34ca7679ded13931ebd5c740368c78d010001	\\xe2e0653c59176cc901618968c63632e73fc2ac1b8589e4a3a6a54ca64706868d7388b32505dbbc2f3f8dbdb554e8c3e5892f362a3f2b1ffe638770c6e237dd08	1660473090000000	1661077890000000	1724149890000000	1818757890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
411	\\xdc0f5d16f13ad3ae37623df3e324590bee29e3336d584a88aaa5d67b66ef361cc91254d4a917d558a2c1f4a442cde46c03be6f526c32c7eb38ba117f645d7207	1	0	\\x000000010000000000800003c3804b65e1a7b926807d5044840bd521ad82b659ac8820dc508145750b2922326d9a65f95723dd2ac76b700f706e1c1284f5c01b4443d34f1411ab8b3e1d3fe53e1e520dc07a800155a0f09e736528076cd2239b649151586335917a74aad20368c8d229ca5cfdd970eb8d3513f71c7ace4013916552092f959167b9c46a7ae7010001	\\x7aead1a5fad95ef7959417ba48a3512bdd651e21d9459bc20883545ea2570048094b7207306dfb3b86c0afd769195be893daf28c49617ba2b1f10aeb9779b204	1677399090000000	1678003890000000	1741075890000000	1835683890000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
412	\\xe0bf9e329d1307594bc661908c4037ba22a7dcbef8e19375867f01f357157533fb5cdd3fe91641e2ffd8613604b1793bcac62d98ebf9bfbafffcfd434873c636	1	0	\\x000000010000000000800003df9ebdac323cd7aabc3ec436766d746a2f19b71011812726d4fb9842496b940228b3fa9118ac3586c37016f79ea09bab1ffaf1e7789823ed5ca6cfdb106fdccd8c6b15cdde762b286734cb28e05a4b732cf86de8e7ae95ff8a40acf54bd84507c89160d761f1ec9faebca740d63a364225d313ec933cd1fe546a939144d5ea29010001	\\x64a0efbdc89a1966b6fb3a9e1206abea36fdd2b03f0bd233b850bae0b9465fe60f742f67133d5da44c8e5d2389174937b248db0f6c7acba25cd8ead4a9227b08	1657450590000000	1658055390000000	1721127390000000	1815735390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
413	\\xe43334d1fa4e32f38cded074fc00f3c80efa09d9343ce699778f7c18950ba742cc989be55953749e7777982e9008be63f43a853c224081c7197e65eac91842fb	1	0	\\x0000000100000000008000039d8e1b90b28fd311a2b31cbf00e7b3f731e3e9e75e257eaee331518151846cc8111db85837a247bb1425486edac248762f9c8ad716c9a9958a1f71c23f06e3905b03bb4bd1733f1a80f953af00304d30c86f66bde3e5bf37fa54ffd770d54cc5d3e8b97440d30f21040eba2c4f8d4aa508f1027c41270a6539aef4bf6651a0a7010001	\\x360861c44defa9e1a886112d31a9036547f785099de5838331bd24222920a66d3e4ba772e49346d1d3b91b8554c81024050444f764b796cd4bfd08e69840630a	1674376590000000	1674981390000000	1738053390000000	1832661390000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
414	\\xe5af039bac90a79407dad2faa535d2d5fce264b895d7dbe3e4e53d532ce4fe07e830b73ded967ebc3bd8c0d9e94a8a035672b4e37167fe718068418a8ab68aa8	1	0	\\x000000010000000000800003e093cc0c8758cade96801674de94f4b80b5bb2d9f52a15fd80d57fcbd0499c30690b7b1ed9f411644a3eb30edac5ec79a3512990e6261e542925dbac01863c43650d5ee16c24656171c1ed0bcc2038d9c9a1c33762e9d4b06755b0cde286147090be0f24d18413076fb056c7fa9ee13e03d8ffc3acf451cc94f542307ce1f1e1010001	\\x7d1c9c1cf60ab7d7d4e92d0140cb0a793ec04557931091eb61a15d257ed4da6543c2b55062053b7a179c525104269da9b6a3c4566acd0ba5d1d277095f493408	1671958590000000	1672563390000000	1735635390000000	1830243390000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
415	\\xec57234641bb68386f638bc0e8de17dbf07f1599073bcfc8f4c7152c6dec60fe5b9a9c2221540a25712198526bfad8b42b811f2a6e9dcbddf22c40cc908f2b44	1	0	\\x000000010000000000800003b967e2e7eb34aac1d6eb36afa7853a78c50c3e9381037a83e4b987c9b82af77f073e977ca83b1e3ece1be9b080b567efbff8dca839f009e2ea0592e0959b1ea39ae4f654ee2883ef1829830df6a8afa7ee70b99460b8c1353ae927022c73f636088ef14673d1ff6085a0de0249bbdf5d8714fdbb98c3ccc96e400e70b3f425e7010001	\\xed6cad2b30e7450ec99474ec9e4831b5c79cd5fff0077747c539391f673784a6597c0c9b1f6f19cc5bb2d3511c835b6363c2084286011c0ab071bf5560244504	1670145090000000	1670749890000000	1733821890000000	1828429890000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
416	\\xef5be561391a98bc8c968bf71df87f9e0c50df8615cd0c2586547ea44e5a411f5a6eca2ca3ee2dc9eb7ebdfc2eace8de589eb7986b4e2cbab29057130e382f1a	1	0	\\x000000010000000000800003e0912f10ca63248e6fdced4a6e633fae2c7dc53f2c31695fa16b23f9d99d45b74f4609d4de372e94a0e607b4fced22cc1d03b83594d0e01f56c153d09f4184050e247267d21a38398445c99e23bfed6c2c5ad86d251b8deee157666bc55be4f97201bb4610dfffaece98fe7b71e8c887ba85414af352cae460afc0ef2857d3b5010001	\\x45bdcea4ce746ed8150c2d71260ad85e17aedbe3a49cf3d16b4801de578b6750c81eb5af710ffee2d3b257ff781349efe6bbcaefabef68951cc49cf1bc02b70d	1673772090000000	1674376890000000	1737448890000000	1832056890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
417	\\xef2f1ea85698c89aa3e20425260e358e55255563e6525a2d8824e8276d6521bcd462d7f09c4beec8c1a29ab970c71de61c0628e812329340394b7d1d53668cab	1	0	\\x000000010000000000800003afb9d6a7c929c6698bb4b4df398d66dae4e3e958133c7821dbea1dc20ebae2922a1928451037204fd859a434feec3910c8ddecc02a38211747ab3e1a420c9aae5dae1acf977c7f5ec33839cbba9e4a8fe31e823cc09851b5ff1fe89adc42747f80101f6f8f0ca4e8ba897c680db90e01f0392af0be930f1b20f9808bdb6e1abb010001	\\x302f4741072aa7c9d08726c23b03e7d6e8b0d299c6d960065a26e3b603c2ca9a585ec1ed9076292f8e1306c9388acb117a5c56458000d0863ea7f2d55d637102	1678003590000000	1678608390000000	1741680390000000	1836288390000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
418	\\xf06fb3a4d158ba00c1ea521466cc6f03309cba660dd7ee55b6b8b236345c1dc25ef9ced60785660be34100ebc0e717e79bfd22b04204f66034fb214f63d00a48	1	0	\\x000000010000000000800003a3641f65b2cc00a99dc94a8efe1034ef73066e30df58a201137a43f33a7abe1bd75d6111614a5fb44e1ac525998d6aba45ba11028b01dc00399fd51d3c0f847186225c8545c1ed67f788e79e3cd9a6267b2eff85b6ae7471d4741ba68626b032e595edf24ecf46e65547431827c079d2bbf94b41a1426a489aba3d571f996089010001	\\x16180dd1aba87682632ad99d850d014f252c3a79bb4bfbb9e9ab3a0fa5da601916eb3d4bd8e8c28b86071dd1e7b55f8b85a378c9f02e5e6d48ea6f5ed9fc1d07	1656846090000000	1657450890000000	1720522890000000	1815130890000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
419	\\xf02f38c74106f100dd960bb026c43758112d7baba0729f5ebdd6b3ae01cd9073dddfeda8892fa3aa8936a25e18a2a6acf36c8b06abd1d0f2de86bd67545fca61	1	0	\\x000000010000000000800003ddfa33e5f911c20bfe66d7cb52233ff5fb34015c8cc40708ee638a91b8f6e6d15fa3a2267cde15b94ed41a61c2cde0f7b3f107cf40fefb4429b9ba3086df99bd5dfe24b7fec406392529634527800a794a84ec54c6cfc81ea4f061b8c63785a4f97987d3cd9501536af9381950b826ca80245fdf7948bdcf26fd94c6304a12ab010001	\\x7b47de9c837dcd937ec3cba0e0af557e5ff5a2d234c80a66a8bfd71b888cc319f787ec91641f3f1c9db123e5fb18bf5336d4f2e3c2cf359fba5f6d7fd2942b0c	1654428090000000	1655032890000000	1718104890000000	1812712890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
420	\\xf283330f98e7d1f08b2196a08552e44c0e835c3b8c071f18d0b09884ae316607097fba423393e89ef8254147c70522b81452d7100109da9fffc65c1ea0adc240	1	0	\\x000000010000000000800003ccef9a3fbe0a4733377c234c84fe8a56223ae16f0b5de823bf2af8d053618b9356604b409bbd035bb8d861049107a4621af46703eea8d7523caac09b913c72cd094ba089252c0d68de00f09865214ff18d72e8c2bd8d2bda3b95c2aee29a831ce93c2d5d94ca6715ed9a33d5832026355dd242d81595a8e6324bf1328a1997d3010001	\\xf09dc0b4104d0b3fd8f453d008139b8f58906e0c5a00967a816a8b245388b681f21b228a9c75ba1ab9437a0ef8bd494a46e7f23309ace1a7cbc75d43c1a0980d	1655032590000000	1655637390000000	1718709390000000	1813317390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
421	\\xf22bbbd67c6f71de4224b9638b31ff5e8e6d4075840473855869d67d5120b0f2ca5bc59331cc78e0f60e1f8fca11af2665459dea0991c8ad0bb502c9b5bf70fd	1	0	\\x000000010000000000800003b4c5b62a49a0edc84d8aca775768ca5db385eab172386d80dd90297d5a23376885444f270dfd406c5da5e36e19aef2c7b4fd3800ee2a88b1cf0bf0f12648c97c483d7b7f7d2d7b8b6012462fefae38d0cee1e0a5ba846b241c559f3f8f13a1431d1298e94d671a770a33ca8c92e17817ba97c5d1d979fba04672486fe907ef05010001	\\xadcafa72a7d11b3082a54c7ac9d3ca44404ea365cf769e5cca28e7b71d8bc5bd4bdbf65e3f05e63c1a95cbec8558f311949b8f094111aba5f73a52e48dc1ad06	1674376590000000	1674981390000000	1738053390000000	1832661390000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
422	\\xfc6b1822bfd98add2ac2fc26039f1ceaeadd9bb28813351bc3b2e9c08330e13a73d77ae24b2d924412753f9920f12485e2bb5e7bca1af7f59884f9206aaebf59	1	0	\\x000000010000000000800003e7f6d63553d21b3869e9bfb3f99019595dcbb02ddb1544c512766282866329039bb57eb7a708b2bde877ad02780d512a2d4adeb13af7f6fceef7fee4523b7e29d0412a6db55533c029df1fd773a9ad48ea9ed21dc5531ae3960c8942c54409160c474f44e76a2a6d51911d9505f0f990c9dad0375c64fef28bc78a4117077899010001	\\x196e1d5bb81623f69040db5a613cee52dea556c794a81ca91246c08346003827bd6407f29371696475c9202dddbfdfdedd97ade2ef3dc6c3ea2371cad3885008	1648383090000000	1648987890000000	1712059890000000	1806667890000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
423	\\xfd876a854d1f78f670a7269b6108cf8a51922671273fd3970c4b9889fbf934a41328bef186ddd8404d03f078e93f0835aa1befc3f209abf9b18397876e826b7e	1	0	\\x000000010000000000800003cbd21d9357cd0c4db8cd624abaa701091260a7e1487939ab64963618873eea5783cb35483bb3a8454dd1e64add11326815c59aa887ab083341a00481b82181d86917053590ae143ced12c3b15330415f7604110d45aa536a7861e90d557b07979376ad5b3ff27fab923c2cd25de695271e3a8807c43f569e328e46d9ab606509010001	\\x745d942a7c777c9e951d7b09216b5abbc6d1ba11c7ea90dbd0e7b225dd60bdf2d3080d82ff7aa8589f7b7309b1308d62676446010a0bc0f11fea0de13947ae0e	1667122590000000	1667727390000000	1730799390000000	1825407390000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
424	\\xff277da963d9f806297104560a0ecf08dfc8770b1c48bd45fc393dc0590c6b09349c1f526d5482fa568fffd36e3c93a232fdd7d380fc6469ce956b1a074ce662	1	0	\\x000000010000000000800003b9a807aadb8fd232c49f60c290e85a33dba4f43aa8ca722c46b2f23a791ff4cebc914edef478f98315ab88638a80a3459455e6a60500580dbe6b33b787584c3c7fdb4b1962fe8cf041094180e37127f4924eac78da495e6156cade0c2c265063e4be6313bb26f5ff1035b5eb99d38b46c0014b2cf45f6cd0c606abfc65e9fae9010001	\\x95f11d5cc2193d3f0644fdc7f4111e6947ef93b0f855bf9c18d1ce747994e0ffac6dd1d7b1c33b3c599b5a9fa2837b23baa9c03994002d9f7855c43307868908	1665309090000000	1665913890000000	1728985890000000	1823593890000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\xb70449afaef34ce9d6d1c40227642fd8fd9fa16d71b1101607c60d54b51b67a7	1	\\xd1bfe8535b65150e61ba531467320c829a032de3a6404f7d7e42fe55885209e1afc7739dad8ff9a7f2fda8ed33058dbe3000fd2b5b092de9b2b044d87a246c57	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x35c8334f5beae514cd701fe43e7715749ba93c4693f09408444862f74024200fc462a1d50cf39f7f0c8f6d90b13dd23eb0173b2d10943e63cf12c3bdfa5209d3	1648383109000000	1648384007000000	1648384007000000	3	98000000	\\xee7a4e8c55eb89ce91e05718a7ffcf101f7f545c052443dad652549338717aa2	\\xa753fb1e9a538dd93dd9091d9db531bbfbaef6ca726e438e73268d892373ad6e	\\xdc9dd88afef86ce2a24f3c2170f9bd252b5fae2103ae96f968b36371af7f40339eea11a565d1e6b5a52c829758f9e79c22d6778ccb52bf0e1861fd36ed7c1d09	\\x9e9ab2f41775a8c05f6258d23147a0fe348e3261c4dbdd7e67b378883a0a7fd9	\\x30cf08c5fd7f00004fcf08c5fd7f00006fcf08c5fd7f000030cf08c5fd7f00006fcf08c5fd7f00000000000000000000000000000000000000de7b6d2d18fc85
\\xb70449afaef34ce9d6d1c40227642fd8fd9fa16d71b1101607c60d54b51b67a7	2	\\xce7b5afdb1d4b9b312cfef2965acdaa9224ef87c365f3cf6f25237cce02efa01c292b7b41637011371af074788cbe1ae6240f03473a8552942f5de521da2f71d	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x35c8334f5beae514cd701fe43e7715749ba93c4693f09408444862f74024200fc462a1d50cf39f7f0c8f6d90b13dd23eb0173b2d10943e63cf12c3bdfa5209d3	1648383116000000	1648384014000000	1648384014000000	6	99000000	\\x823c817cfaa33cd6bc286f8daab3c7731b581276c0a1b67b9d45148f4fb112ce	\\xa753fb1e9a538dd93dd9091d9db531bbfbaef6ca726e438e73268d892373ad6e	\\x17f81c03301bd020e3db15736be8eeb5d4e58a7ad0856764b52c1395317d53db13d2787fbdf77f83d88b9897c55b61dd2a3bfd3186b12919ce32dcc8490ba70d	\\x9e9ab2f41775a8c05f6258d23147a0fe348e3261c4dbdd7e67b378883a0a7fd9	\\x30cf08c5fd7f00004fcf08c5fd7f00006fcf08c5fd7f000030cf08c5fd7f00006fcf08c5fd7f00000000000000000000000000000000000000de7b6d2d18fc85
\\xb70449afaef34ce9d6d1c40227642fd8fd9fa16d71b1101607c60d54b51b67a7	3	\\xdb03993d97f7b24e28faaef9c70391229babcf7b0ed5b28587bcff64902bb081e94d5f1e23c3af73a76b8c868efa4ea13a912ed85c7c4b7b4a5bfe9a2aa4be8c	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x35c8334f5beae514cd701fe43e7715749ba93c4693f09408444862f74024200fc462a1d50cf39f7f0c8f6d90b13dd23eb0173b2d10943e63cf12c3bdfa5209d3	1648383122000000	1648384020000000	1648384020000000	2	99000000	\\x14f9c2d8c0f66131f8fd05a5ad6fc9689a4bbcbc57ff0d12280532555a193fc0	\\xa753fb1e9a538dd93dd9091d9db531bbfbaef6ca726e438e73268d892373ad6e	\\xc8038516841989225cf0675d862855ff0e90d48cefcf85471672f1bd6049501fe6e8e52783d055616a431678319186f85a6db061da1408249ff26a64678cc200	\\x9e9ab2f41775a8c05f6258d23147a0fe348e3261c4dbdd7e67b378883a0a7fd9	\\x30cf08c5fd7f00004fcf08c5fd7f00006fcf08c5fd7f000030cf08c5fd7f00006fcf08c5fd7f00000000000000000000000000000000000000de7b6d2d18fc85
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1648384007000000	1220384548	\\xee7a4e8c55eb89ce91e05718a7ffcf101f7f545c052443dad652549338717aa2	1
1648384014000000	1220384548	\\x823c817cfaa33cd6bc286f8daab3c7731b581276c0a1b67b9d45148f4fb112ce	2
1648384020000000	1220384548	\\x14f9c2d8c0f66131f8fd05a5ad6fc9689a4bbcbc57ff0d12280532555a193fc0	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	1220384548	\\xee7a4e8c55eb89ce91e05718a7ffcf101f7f545c052443dad652549338717aa2	1	4	0	1648383107000000	1648383109000000	1648384007000000	1648384007000000	\\xa753fb1e9a538dd93dd9091d9db531bbfbaef6ca726e438e73268d892373ad6e	\\xd1bfe8535b65150e61ba531467320c829a032de3a6404f7d7e42fe55885209e1afc7739dad8ff9a7f2fda8ed33058dbe3000fd2b5b092de9b2b044d87a246c57	\\x6973cca53630b85ca72747e05610fedd56d0860ca36f7a3a0edbe55db9991689b1ca38043d2674c6c2aff2dd351ce60794c5d2893bf742639c0097119a5e8b0c	\\xcf3c8c5254b8d6fd0e25c7c7064ad978	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
2	1220384548	\\x823c817cfaa33cd6bc286f8daab3c7731b581276c0a1b67b9d45148f4fb112ce	3	7	0	1648383114000000	1648383116000000	1648384014000000	1648384014000000	\\xa753fb1e9a538dd93dd9091d9db531bbfbaef6ca726e438e73268d892373ad6e	\\xce7b5afdb1d4b9b312cfef2965acdaa9224ef87c365f3cf6f25237cce02efa01c292b7b41637011371af074788cbe1ae6240f03473a8552942f5de521da2f71d	\\x2ad01cfb95ebb607728c8dbb9b8de2dbc90b3a3636edcd0c29843d8248318e9aff97a94440134de21e3f8d01afc60943f233113089c5308c5648aeb52566b906	\\xcf3c8c5254b8d6fd0e25c7c7064ad978	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
3	1220384548	\\x14f9c2d8c0f66131f8fd05a5ad6fc9689a4bbcbc57ff0d12280532555a193fc0	6	3	0	1648383120000000	1648383122000000	1648384020000000	1648384020000000	\\xa753fb1e9a538dd93dd9091d9db531bbfbaef6ca726e438e73268d892373ad6e	\\xdb03993d97f7b24e28faaef9c70391229babcf7b0ed5b28587bcff64902bb081e94d5f1e23c3af73a76b8c868efa4ea13a912ed85c7c4b7b4a5bfe9a2aa4be8c	\\x1a98473c2f410fef976ba405ea23a9ec417c9d8ac97e41fdf6f249243661bea9cb26e631de6113f4db65f337034ac1a41865ae54b8e25aab6b96608fe681cb01	\\xcf3c8c5254b8d6fd0e25c7c7064ad978	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_for_matching_default (refund_deadline, merchant_pub, coin_pub, deposit_serial_id) FROM stdin;
1648384007000000	\\xa753fb1e9a538dd93dd9091d9db531bbfbaef6ca726e438e73268d892373ad6e	\\xee7a4e8c55eb89ce91e05718a7ffcf101f7f545c052443dad652549338717aa2	1
1648384014000000	\\xa753fb1e9a538dd93dd9091d9db531bbfbaef6ca726e438e73268d892373ad6e	\\x823c817cfaa33cd6bc286f8daab3c7731b581276c0a1b67b9d45148f4fb112ce	2
1648384020000000	\\xa753fb1e9a538dd93dd9091d9db531bbfbaef6ca726e438e73268d892373ad6e	\\x14f9c2d8c0f66131f8fd05a5ad6fc9689a4bbcbc57ff0d12280532555a193fc0	3
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
1	contenttypes	0001_initial	2022-03-27 14:11:30.509016+02
2	auth	0001_initial	2022-03-27 14:11:30.669826+02
3	app	0001_initial	2022-03-27 14:11:30.796147+02
4	contenttypes	0002_remove_content_type_name	2022-03-27 14:11:30.807732+02
5	auth	0002_alter_permission_name_max_length	2022-03-27 14:11:30.816485+02
6	auth	0003_alter_user_email_max_length	2022-03-27 14:11:30.823718+02
7	auth	0004_alter_user_username_opts	2022-03-27 14:11:30.832124+02
8	auth	0005_alter_user_last_login_null	2022-03-27 14:11:30.839175+02
9	auth	0006_require_contenttypes_0002	2022-03-27 14:11:30.842514+02
10	auth	0007_alter_validators_add_error_messages	2022-03-27 14:11:30.849862+02
11	auth	0008_alter_user_username_max_length	2022-03-27 14:11:30.864569+02
12	auth	0009_alter_user_last_name_max_length	2022-03-27 14:11:30.871922+02
13	auth	0010_alter_group_name_max_length	2022-03-27 14:11:30.880938+02
14	auth	0011_update_proxy_permissions	2022-03-27 14:11:30.888462+02
15	auth	0012_alter_user_first_name_max_length	2022-03-27 14:11:30.896278+02
16	sessions	0001_initial	2022-03-27 14:11:30.929252+02
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
1	\\x0bdd4ea01bf3b8b54aa7de9e023162edb33d483603a6199f53d7910fbe865978	\\xd41b0f0e03f809f61502ca05a208f99690efe4f74668b437f4a73549953d5ac3e8bb9958ac18cdc6b8c571efc2f7af9845a7781a89e043d1efd64a7f848e0e0c	1655640390000000	1662897990000000	1665317190000000
2	\\xaf493eb79e5f9b1f3ad26095ead55b2185fd41b68e46e1d2d9f89e7de12ecdfd	\\x612688c4c8378cccf740cf16b2cd979871298e45154307c34050caedb7fb6c8c73f3172a1a3417d20b5ec1c5a5b2e8f126890684a312e3c975b06e70cba22a0e	1662897690000000	1670155290000000	1672574490000000
3	\\x90a23985724626850a81ea2e080ce18d9b499079310c7d2b85387f2d2e06a935	\\x989d39610805d15724624cd7771d27e310ccce7f4eb875009f1b2b39f507d9dfea65c114b16279d74c8ae92930cb6872ccb4d6d61da55b3e06d54e68ac3ab00b	1677412290000000	1684669890000000	1687089090000000
4	\\x1cf660be71b3ae014a3d3beb3e766fd8830e75e361ae90f9930f5afe8864bbdc	\\x300d54fabf9d635d910591bf392084e1205130a5e44d10005756d9acb77c85fd3bd515c93b2d93303a75e18d69432fb43c3755e26cec937905a52f5777161808	1670154990000000	1677412590000000	1679831790000000
5	\\x9e9ab2f41775a8c05f6258d23147a0fe348e3261c4dbdd7e67b378883a0a7fd9	\\xc9caf8cffa338147a917aa6958a17998948e7cbe377838ae9cb1a5ae95178feb77c0b2927960c3328c1eaab0a18e4188ca4e4f65b1f58de1f938a914a05adf09	1648383090000000	1655640690000000	1658059890000000
\.


--
-- Data for Name: extension_details_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.extension_details_default (extension_details_serial_id, extension_options) FROM stdin;
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\xaa51c51427d6a466b1d3e447265d256a28efe167f86d6c8a2b98d09c4b8679e7ec80ae54129d23683566c15ccdb44ba8d2e92ece5ea7fbc9ef91dba1dc4cd20a
\.


--
-- Data for Name: history_requests_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.history_requests_default (reserve_pub, request_timestamp, reserve_sig, history_fee_val, history_fee_frac) FROM stdin;
\.


--
-- Data for Name: known_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins_default (known_coin_id, denominations_serial, coin_pub, age_commitment_hash, denom_sig, remaining_val, remaining_frac) FROM stdin;
1	286	\\xee7a4e8c55eb89ce91e05718a7ffcf101f7f545c052443dad652549338717aa2	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000034545747bce692faa496d44bc0232bf9a3226c87c5f59813a8a68cb4601be44159936110dc468e24a478d31a5d905808ca5eec07ce82af1aff08688133daf7a85a6f33fed944a3830c9e9787c6511f9e482465b39c640fed22e7233ac1e358dd26c003f37e6be790be171253fb3a6e69a3d45b6fcc4e83b64e8a597be65bdd8f	0	0
3	71	\\x823c817cfaa33cd6bc286f8daab3c7731b581276c0a1b67b9d45148f4fb112ce	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000001361b4879e4736dc22760582b04aa45da55bf8e124ddee1ec882386c79cb9a0a067a575d82b49b874a293ba5517f01e9d2ba9d5af3d7e63d8b1fc1b977cd023aa3fee8efe727637f530966a8d9ed2d4d4a057ae568f1357e45d44ed24e02d961aac805c327a170e2dee1983979d8e1885198fef3fb7df28783dad34c61a45fef	0	1000000
6	282	\\x14f9c2d8c0f66131f8fd05a5ad6fc9689a4bbcbc57ff0d12280532555a193fc0	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000299fa2922e2495756c882079c7d1447764995cee5a87562d7441796de5c22b4546993edab39ab9b9170fcacaed91e6dc04e887fe630acc5ac9cb3c540feda6a78cb2d006b5eb52cf2e69437cda84c377ac44a7c699fa0b567126573083a077ccfbffd8ab28413bb78fa31af76ed68f76e2ec115d59f2c660c11033d871a48ad0	0	1000000
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x35c8334f5beae514cd701fe43e7715749ba93c4693f09408444862f74024200fc462a1d50cf39f7f0c8f6d90b13dd23eb0173b2d10943e63cf12c3bdfa5209d3	\\xcf3c8c5254b8d6fd0e25c7c7064ad978	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.086-0105MTMZ40PVA	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313634383338343030377d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313634383338343030377d2c2270726f6475637473223a5b5d2c22685f77697265223a2236513433364b545658424a48394b4247335a4a335758524e454a44544a4632364a4652393832323439314846454731343430375738524e31544d36463737565a314a3750563435483751393358433051374350483135315943463748354758585a3939304b4d52222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3038362d303130354d544d5a3430505641222c2274696d657374616d70223a7b22745f73223a313634383338333130372c22745f6d73223a313634383338333130373030307d2c227061795f646561646c696e65223a7b22745f73223a313634383338363730372c22745f6d73223a313634383338363730373030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22505732344b425845594436454b4e50485247313245533146563359535a38424445365248303547375252364e3944385643594b47227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224d58395a50374d54414536584a464553313445535644394851465854585850414539513437334b4b345436524a38564b4e4e5130222c226e6f6e6365223a224a5041354d545345544151584635365a4b59363859595450515947574146334a56434d4151433154353243564545424d31583330227d	\\xd1bfe8535b65150e61ba531467320c829a032de3a6404f7d7e42fe55885209e1afc7739dad8ff9a7f2fda8ed33058dbe3000fd2b5b092de9b2b044d87a246c57	1648383107000000	1648386707000000	1648384007000000	t	f	taler://fulfillment-success/thx		\\x4df11e66b1a7f61cfe19f6fcd09a48c2
2	1	2022.086-01J27QG0P88PY	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313634383338343031347d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313634383338343031347d2c2270726f6475637473223a5b5d2c22685f77697265223a2236513433364b545658424a48394b4247335a4a335758524e454a44544a4632364a4652393832323439314846454731343430375738524e31544d36463737565a314a3750563435483751393358433051374350483135315943463748354758585a3939304b4d52222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3038362d30314a32375147305038385059222c2274696d657374616d70223a7b22745f73223a313634383338333131342c22745f6d73223a313634383338333131343030307d2c227061795f646561646c696e65223a7b22745f73223a313634383338363731342c22745f6d73223a313634383338363731343030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22505732344b425845594436454b4e50485247313245533146563359535a38424445365248303547375252364e3944385643594b47227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224d58395a50374d54414536584a464553313445535644394851465854585850414539513437334b4b345436524a38564b4e4e5130222c226e6f6e6365223a22414d51434a33374d3544465659435958545231544742394a47413032444758475a574a303959484b335932524a4b583550384847227d	\\xce7b5afdb1d4b9b312cfef2965acdaa9224ef87c365f3cf6f25237cce02efa01c292b7b41637011371af074788cbe1ae6240f03473a8552942f5de521da2f71d	1648383114000000	1648386714000000	1648384014000000	t	f	taler://fulfillment-success/thx		\\xdac020e533ab97f7eaafa88c9829b195
3	1	2022.086-01R9X0QF6X7W2	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313634383338343032307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313634383338343032307d2c2270726f6475637473223a5b5d2c22685f77697265223a2236513433364b545658424a48394b4247335a4a335758524e454a44544a4632364a4652393832323439314846454731343430375738524e31544d36463737565a314a3750563435483751393358433051374350483135315943463748354758585a3939304b4d52222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3038362d30315239583051463658375732222c2274696d657374616d70223a7b22745f73223a313634383338333132302c22745f6d73223a313634383338333132303030307d2c227061795f646561646c696e65223a7b22745f73223a313634383338363732302c22745f6d73223a313634383338363732303030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22505732344b425845594436454b4e50485247313245533146563359535a38424445365248303547375252364e3944385643594b47227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224d58395a50374d54414536584a464553313445535644394851465854585850414539513437334b4b345436524a38564b4e4e5130222c226e6f6e6365223a225333463442343754415348444631374b383638583144464b505745364246373048514b485956434b325053453859533044443047227d	\\xdb03993d97f7b24e28faaef9c70391229babcf7b0ed5b28587bcff64902bb081e94d5f1e23c3af73a76b8c868efa4ea13a912ed85c7c4b7b4a5bfe9a2aa4be8c	1648383120000000	1648386720000000	1648384020000000	t	f	taler://fulfillment-success/thx		\\x5a15764aac1acfda9d7956b8c5b1f904
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
1	1	1648383109000000	\\xee7a4e8c55eb89ce91e05718a7ffcf101f7f545c052443dad652549338717aa2	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	5	\\xdc9dd88afef86ce2a24f3c2170f9bd252b5fae2103ae96f968b36371af7f40339eea11a565d1e6b5a52c829758f9e79c22d6778ccb52bf0e1861fd36ed7c1d09	1
2	2	1648383116000000	\\x823c817cfaa33cd6bc286f8daab3c7731b581276c0a1b67b9d45148f4fb112ce	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	5	\\x17f81c03301bd020e3db15736be8eeb5d4e58a7ad0856764b52c1395317d53db13d2787fbdf77f83d88b9897c55b61dd2a3bfd3186b12919ce32dcc8490ba70d	1
3	3	1648383122000000	\\x14f9c2d8c0f66131f8fd05a5ad6fc9689a4bbcbc57ff0d12280532555a193fc0	http://localhost:8081/	3	0	0	1000000	0	1000000	0	1000000	5	\\xc8038516841989225cf0675d862855ff0e90d48cefcf85471672f1bd6049501fe6e8e52783d055616a431678319186f85a6db061da1408249ff26a64678cc200	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xb70449afaef34ce9d6d1c40227642fd8fd9fa16d71b1101607c60d54b51b67a7	\\x0bdd4ea01bf3b8b54aa7de9e023162edb33d483603a6199f53d7910fbe865978	1655640390000000	1662897990000000	1665317190000000	\\xd41b0f0e03f809f61502ca05a208f99690efe4f74668b437f4a73549953d5ac3e8bb9958ac18cdc6b8c571efc2f7af9845a7781a89e043d1efd64a7f848e0e0c
2	\\xb70449afaef34ce9d6d1c40227642fd8fd9fa16d71b1101607c60d54b51b67a7	\\xaf493eb79e5f9b1f3ad26095ead55b2185fd41b68e46e1d2d9f89e7de12ecdfd	1662897690000000	1670155290000000	1672574490000000	\\x612688c4c8378cccf740cf16b2cd979871298e45154307c34050caedb7fb6c8c73f3172a1a3417d20b5ec1c5a5b2e8f126890684a312e3c975b06e70cba22a0e
3	\\xb70449afaef34ce9d6d1c40227642fd8fd9fa16d71b1101607c60d54b51b67a7	\\x90a23985724626850a81ea2e080ce18d9b499079310c7d2b85387f2d2e06a935	1677412290000000	1684669890000000	1687089090000000	\\x989d39610805d15724624cd7771d27e310ccce7f4eb875009f1b2b39f507d9dfea65c114b16279d74c8ae92930cb6872ccb4d6d61da55b3e06d54e68ac3ab00b
4	\\xb70449afaef34ce9d6d1c40227642fd8fd9fa16d71b1101607c60d54b51b67a7	\\x1cf660be71b3ae014a3d3beb3e766fd8830e75e361ae90f9930f5afe8864bbdc	1670154990000000	1677412590000000	1679831790000000	\\x300d54fabf9d635d910591bf392084e1205130a5e44d10005756d9acb77c85fd3bd515c93b2d93303a75e18d69432fb43c3755e26cec937905a52f5777161808
5	\\xb70449afaef34ce9d6d1c40227642fd8fd9fa16d71b1101607c60d54b51b67a7	\\x9e9ab2f41775a8c05f6258d23147a0fe348e3261c4dbdd7e67b378883a0a7fd9	1648383090000000	1655640690000000	1658059890000000	\\xc9caf8cffa338147a917aa6958a17998948e7cbe377838ae9cb1a5ae95178feb77c0b2927960c3328c1eaab0a18e4188ca4e4f65b1f58de1f938a914a05adf09
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\xb70449afaef34ce9d6d1c40227642fd8fd9fa16d71b1101607c60d54b51b67a7	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\xa52c37a48cf4bcda753cdeb62b90ec6dde16fe2c00c30450002c2f46f8eca87f1b7ca3f7b54d71ea4e0b87ed3fe62462b69985a0f55a117e8eec3735468f2d0d
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\xa753fb1e9a538dd93dd9091d9db531bbfbaef6ca726e438e73268d892373ad6e	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\x9f8cde2ab579901a27608ca79818e48379fd3fd7771908a0a20eeffe7f2bb2cf	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1648383109000000	f	\N	\N	2	1	http://localhost:8081/
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
1	\\x6d42538d299fde588d59ad21b717be7723f63e2f806b5212ac1f755771db71727f39c76eefe402fccce7f1fd2d2d4a2deaf8699bdfc98578953085ff2369f902	5
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1648383117000000	\\x823c817cfaa33cd6bc286f8daab3c7731b581276c0a1b67b9d45148f4fb112ce	test refund	6	0
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
-- Data for Name: purse_deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.purse_deposits_default (purse_deposit_serial_id, partner_serial_id, purse_pub, coin_pub, amount_with_fee_val, amount_with_fee_frac, coin_sig) FROM stdin;
\.


--
-- Data for Name: purse_merges_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.purse_merges_default (purse_merge_request_serial_id, partner_serial_id, reserve_pub, purse_pub, merge_sig, merge_timestamp) FROM stdin;
\.


--
-- Data for Name: purse_requests_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.purse_requests_default (purse_requests_serial_id, purse_pub, merge_pub, purse_expiration, h_contract_terms, age_limit, amount_with_fee_val, amount_with_fee_frac, balance_val, balance_frac, purse_sig) FROM stdin;
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
1	\\x9abd6a10f631d12e3688c785914706454be85cad43b90b30c6c9fb3ef1fdc285f051f91d68ac071a1cb490c98bd0ac310cc8d4df1c501c461d0bcc3b979a6f26	\\xee7a4e8c55eb89ce91e05718a7ffcf101f7f545c052443dad652549338717aa2	\\x7686de4b9eab6ca2b0552c7f1af900521ceca1d3e3a729756825966038811d844cb1a13452c201d9665b244a2fb0c1db86a296a62d4304fe1c9d4e83beead30d	4	0	0
2	\\x5b875d7b8cdaa7b9ea78582d8f2ff83ef99560762393b3ad924cdb05c1540467b0dc411ca732716ab628b258d98587cc271cc201c69282c2fd6ff79620fdc445	\\x823c817cfaa33cd6bc286f8daab3c7731b581276c0a1b67b9d45148f4fb112ce	\\xedd383f65aa9a9297d704dc4fd35f09e1345450d53f4db9443dcd15a5b9f1a45d15b0e27c30c29adcf63cbaa15c621bb8ce8a7a519b910539c08b6ef900f000b	3	0	0
3	\\xbb48ba65af9b75c72f19e62307d718caad8ae4dbdd4ec909a93b40dc009ceff38464424c56dcb76ccbde65d27ddcc9df2b1783bb2b7d440ede1a48c176af2a52	\\x823c817cfaa33cd6bc286f8daab3c7731b581276c0a1b67b9d45148f4fb112ce	\\x6038e6c16eca6f1e36da7aade247c129105048cc0a2c0a39bcff383ca5c6a960894d39d4aaa36912720b12a66d4eb636903ab59fa2585b1d0474a1f5cb09530b	5	98000000	2
4	\\x1602052e9ee69f032ecafa5060a682e37a512295bb9724c71e8b40f821a51e27733cddc56d984006ec0a0e44dd6ac0f6b721be6bd3aa8a165812a49b88c4d381	\\x14f9c2d8c0f66131f8fd05a5ad6fc9689a4bbcbc57ff0d12280532555a193fc0	\\x43252d13a1c7403d63c0801ec6265f81645e0c1fbdfd873ff9e4146de6c282a86bc0bdea865c5c19fafc36f2dca8298183ea045046d835e2c649609055748409	1	99000000	2
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\x7b19e3b662f8be94592eeddd9b60dc03776f50a77661bec3d75d346428ae27dfb404b2275fffec1c6b50331c1b80fa7df5c83a5caf59d8287062cc0789eefb03	311	\\x00000001000001003de4d3d256f189f7e5ddf4f8ade0c9edd12d85bf4530a04736e0427729038516245d00aed6556d89c4c0e98c43dde0ade0bc73dd90e8b7074523295361cab3a630c0fc837e9c5cfc3b7bb8951372f721152c528f2bd28d892d7344a1a3ffa41c40a3dc497196dea639299d3f88d100fd4fd36c5073cf825bd23a76be69e4cdf0	\\x4f9ed09205978b8e05d2a889ceca94bb245571c7ce9ab467ee4d97c0639f5f368fb63594a57fc98b5fe88b0d8057f793f57e8a9d14b7f99123f7b794ee9cf459	\\x0000000100000001a3ebff960384f19f69942047d7e05cba4d2fa1edd952e5028674918fd9e5e84e741795d46cf915da765c79e5e5e1469f962ea437c0544d38cfc331d07ac8351c327ff02c2f8c3dc2b247668749d13b85008be78a6f6d9532ccb01daede1f367dd98f436384b70bd4d83bd5504dda10c437ca2442e7461c760af31dffa8895f59	\\x0000000100010000
2	1	1	\\x15ed531434777346e6aa1dc599a2e0eed6a310558b433940f21d419b53bb95bd94eb19c60e640426588c49be79f8268423c79aff4a55eeba0e0605a344a49109	193	\\x0000000100000100a49a75d93ab3ee9597ca1b68f9a92a6549739e06a5955c19f22a8664f9f539c1265d928fa71bf0a15ea8e9130c5956db33e67282340d739a1062ff4d14aabc57d06a7771ab5b524e6ead12a8e46645cacbeb68dab953c7980398e27635139dc6c14c3634047a47650bfaa3258b07a96b4c89087c183963fc7fb873517e76a41b	\\x4f2f1de23d8dbdfd2fd113588ab19c3021995d42387b133c9387e842a02f07f9b19532147a24a7cb8016785f6570c266e5e0be36167f83ab96e151cc2fa4e8aa	\\x00000001000000019f958051a9b62b82c773aa34363d23173e7d06c05c793dcadf38a8c7141974b3cd6a88af7d981e5a0f625011fd421089224d1f51b31d6c33ce543e3b314df93383c9db8f64b00712c228b067336e3ead8ef85e5e572ecefc94bb31d8b723b5e93b638d43448fbd9714be46e9997aa8c9399c058353d9b3f2a03b95bff5be0b1e	\\x0000000100010000
3	1	2	\\x7503109df8fe38c60f5f27621d404ec5c2c789eb1ad40f7bac7fac65b06e057a7310b46f21c3ea446e195dc93e4546ec862fa85479e8c241152cebeb572cc40e	289	\\x00000001000001007f14436d232ff74512d2c8736899166a1c475886f35c3597d96cf9664c0ac2e2d1cf1b95dc3a83c41f6edeb747a88b330fad3fde6a23c6e7926572b17f2cb10b55a3349724ab898e143415cfbdf0105508c7905eb3f549876267af13dcee1a19678a8c6306bdd047e9bed014139d86f10b103f9cfecdf212d69dc59d349018dd	\\xebcb28124a7e9247106fd189aff15c994c0bee58edccac129cfa431e6e4cb857194e5c0ae78291acc73ae32f89530cf882141a6ed2dd1a2f2dc296fd75778089	\\x000000010000000122a37e2e795860c2a90c5a5cf28d50a47eb78abd8ec2107274a2c7a5df9c6bfdc22453b918b45628dbc7f8233d4a1909ccd837bfd9cee20972b9494ca380c36b60e68ad47825a217527e80ee1addbeffa6d3a12781091f8449d0495a799cfa96f51789733acd57250ec2be76746cb491b9b175cc05565f413ab1b334d4d83adc	\\x0000000100010000
4	1	3	\\x545d32fba1b49617975dee42f75fad7e5859a22052aa4e7b1084e9a09aa984b89cea7f98346cf8ed59b96c8ea00ef8534a5d420cd3e6de9b64917564fbe0a40f	289	\\x00000001000001008a69fcf4ba784b51060c26d4283c50c7790f17ca8cd45161aef86b577a0a969f5018635bbca01f5ea0eeb830af9220c7229d352cd1eaedfeabe0ee6ac1da2a045b8a65e9a6b827aef308150f87b31b425a89287ae65840186b968f1627cdf876ee219e8ce4784a88cde2818ea064e4d00e50fd9ba74960d628d6a3c108562642	\\xd1a32b67c3359c61a00fea0332255217a1145254891da5d2aa6ef0e72f786becc80a69a4a3bb48d79b4aff1755fb2aec0ca1846c45ed4c324b06204239f76472	\\x0000000100000001c03029c0a6eb4d1d4659cc8760c4f6257962cdc2432739131d3add6d7f968646ba01641f66c57ae211af6bc75ba604005e4cb1013d82bbcde0bd3086b3777a6ec2db3124635283a65e4b1bd8cc54718f8fdb2343642a00f5914efcf7c8b7090f7aa0579ffe41577e746b256934de75cd7bb0a7cd1b8ee02a4414bc94f8283209	\\x0000000100010000
5	1	4	\\x11727308d22f81996e0588348bd970ffb5d151b17f3046f6419b0bda3dae516cc517316a7bceaa4cace906548cb1c84aaba6ed428cb81ecffe45e50640ba3107	289	\\x0000000100000100739914136daf43b6440b055f8dcc5605ce7ed70a2154dad6b9d515892d28a2e727c7ad85b7dbafcfc77d4b150f84c595cd9cbfc88be5597c5424b718039d86412429b2156c596efe2e2f48b5f44a87dd110c81106ddd379de842c031c3b2e19d1f2290e6e46353d65b5b55b97ea6501d0f910b6631dc57b02bdacb794e9a274e	\\xd4e2949361824c65166cec772a24396cd9587fc7da0dfddc948aafc0f921506a26cc9f62e14e5f5e57a10522b73f4f4717a884005c58453c6c72359fee0db5c7	\\x0000000100000001c69c944b66b8118b54e0ca8384c53094a9b9d4a957ba08bffa7b79125ba9eda2a8e55eab3603dbf823e6cfb2fd3cf4c2661a1a6862eb04693dcbdbecccc062a6df7e84b1d4aff60b15570a76e44a4a28d425d9e1f3d0dbde93cc0ddad6299bd2227e9770c1000bd6e57029329d0ad8aacc0b701724dfc097590ad069a500d876	\\x0000000100010000
6	1	5	\\x9b7f7636835d7d529be47854b82602cb90801da3753d80c97eb3b6e4a210127ffbf8b4e155f095095606e2114c3299b8afe5016decdb9068db2296fafcbc6903	289	\\x00000001000001008bb74789c81d017c153d7bc2a88f874b1702b8c6655853ecd5b61f0a3128b443ea067db383faa92388f46032e72128f9dba442951122ed62a3d7c2649a2a23b73e369ffa92666c042d57173eadb04587c31a62d7f679be8f5777d6dfa6f1310df08ea388bd737b0a0dcdef5894ee122513c8666f2400931baba13f9038fde85f	\\x0821c553d903fbff50b8584a24aaf9148010a2f8694e77e094e4e537d3e7728ec31d972d04f02f573fed27eff98379e5e9b5446ff5be90f5cb8f25d5200f3328	\\x00000001000000017e7d18b2dd70eefa1b859295ba8b2874092a947fbadd738332ddd9f711ed52d39f7661def6e4d0b70bac8db39af043c07c46caf92c52316e9f7a9b7118482c26a734a039941ba943d0e33352b3008076ae9863728de4f4c6df0e152cc44376f65df4787f14b77c25707d46cf1942d4f56999f6ed48def2edf7322ba3c2b79f4f	\\x0000000100010000
7	1	6	\\x864a0daade688f1d7aa6c6018319123c4bc404ca662118210c0122caeca6599b8abf5b6a126858583eb9ebca5b49bbbc6fc13dedb11d299436de05964a33570f	289	\\x00000001000001002c52546b8d05ece088ddb7305221facdd2fa3f5faef5f50ea2a7444240d307c4b1fca98ead03ce7b4c3122686c57dac91c1498e120b7897d75e33390ebc73c5a0d8660e50f981ffce9c6612d8b333d6383989442502224110fb21cd84238802a09e0436a0d62c58efbadaedf369b68ba031e4af5e1e38d8c90cdf00a791375bc	\\x52428de87dab3bcea113f768ac9b6e233972dde6d6bd02afd4db16b7dee987760cbf1d780eb5f3f53835918ff3981f3c910dab1fcdf6d9cb28ddcc6fb2a8843d	\\x000000010000000157c5697df38bd5353549299422e204c950470731a978a715e24a61dbbd750608fec5a60e14280a7e91b3ae0318f798d1bc37f91f1633bf5f2cfd68b35bc70d3f81afb4f28d908b056913a579316c931eeebf60635c4ab6bc82418dcac68650d84db8174ba27ed386698b3ebf9a047929b5cf78a827a6f5a103720dae8b17c7a9	\\x0000000100010000
8	1	7	\\x0c839170c7ba02c32d5140928aa28d306e1c0cdba6ee3a802034892c6a2ddcbab780cce600c3f98ef506374387308c541ba287a769f066bc9d82992777227306	289	\\x00000001000001002538f0a57e149a89481d7da6f0e0240af1848d4cdbef59933b9e8e3a1267b26e1a352904617a7a3736ec416d23670bec9ca01e0aef0baef6eefe459a37bf71543406184b6b0f78b2539b18949bc2a4c094c7ab15d9032674b4259241596fe3add7fcb51a2476f958a724ddc0d0b7e0e931ccb447917c02b4b523168ae8a290a1	\\xd546da1453a5d07d0707dc0e54e69910b3c2b1081f2dc1b4d458dbca7171799ccafdc3c5931f9c6f058d299ad4890fde3d30d6008742d1151549e9e06d3f20ee	\\x000000010000000194e8c39a210df24ba00eee77f72345722ecc7f901814591ab8a992cfad5aa0e87279fd51d4a347a7d938970e63df4ba810a05f402e7efc7ee0a44a3c46bfcef96068ecb36e4e9cedd93517b31efb8c16a37e4f8a34231c1046bfc9e446ec12165e03fe2875f647c0bc88baaf8e2aaa48bf9c5f58174300221b0bc93cd23acf14	\\x0000000100010000
9	1	8	\\x8ae6cbec9d8f5727c28ee635d5d5ed772956cdda475d15f233c7e9d8abbae3624c39b8181d6c74e10baa008517932c4478afe1c0dda7b5b8b5f95d5461400704	289	\\x000000010000010084e5fc181d51bd15735b8a64fa0caa673b93e1bebb65bf6f9f0f066854c5a9463d0a402740731ba6393f0993c9ab65e2e27233314cadb13825430899320a2f42286317b66cc2e76e5de2d5a085dc93fd11a53c3b4190422703cf9ee6fea1a9662db2086b9176fdeca9bec716f952bb2fa9c129e77fcc3a45f37515360127dfa5	\\x8047b6cd0f90635d6af28b3b8e6253577476df8e643cb246d044159362520c7d0b493d48ab533ee63b9455312f10f0a93dd9b69ea9677b8ff7189d0282c019b3	\\x0000000100000001954e1ec765b6abfb96574589fdc52e7e0400b35f28080ed06f2d22c2ce04f52cf096a7ab7edcd58793f9fd5ca38cef5503ae67859e2361bde6a6fcfd25f7a3ac1825632c550d052b5a6706d47ae2c6fe78c8d9797d3aed1558ab5282acbab1f4a7bd3830bde56c23e7a6da8fef32c91ece97c9debc068d0600e307746eb4a260	\\x0000000100010000
10	1	9	\\xef92d7ffd5ed2b2a99c2d70b1b38fe23047c9c139685dedac421ef4e2ee1f4bf0e0ddf06d0268a5149cdb04930af20bee25d840114d6090f8f676f0c955ec60e	289	\\x000000010000010006134d15e621f387e82180134bc5a9638f8e31f78b8dd2bfc5c848d0af44429d3ccb185ba03f98bfb939f01bd373383ef23d1d25ed80efcf36d4089955c989e5b20d5456515ee16bccf36b96ea01bc52259f2bf1be55f162c38ee19e467e0b8c9acc511f12da115b92c93b9ab9d1763e38ce6e811a1732a363465e3842cd857c	\\x9b7b031d2e35057ac615074717f8d7c3b95eb90907996808ee0780054c3833a2d01cffb6136770a5cec7e183c6fd08eddfcc0ae16c2b3f9cf06aa92bbe4d5502	\\x0000000100000001be70c56fa1f32ba043535d9744572bfddbcc45e030dd16d5868b8260ea02922c99ff1268358b2a6deeac814a66558a18cf14f2b781ecff1f0b160d40428c7f2bd1e84d85263052f9a6eb6040bee4a2012126e0762e63689d15032bdb999fe7e12321498bb29018ba7616161cade1b67e149139437833a32864f7b94c1581d7af	\\x0000000100010000
11	1	10	\\xf8ccfb773aad2b397b056bbd4e91d625a7f90ea78991597a0df58757141d184176cf29e91034d67cf71cddd06e6c0b11eaf81a5fd9ac2b9269995c47ac48f40a	422	\\x00000001000001003837e2cbdb04e8827180505c80fa51ea78dd7c6ccabd5f84518dc41ef85504a21e62dfc8ee3679d61b50b413f61a107a0471565e9776acaefca0c1e6d73e81b06883f9e539413a1cf3a367959010b08d18f42e2bb800aa5fa540e68afd319eec7c61f9bc8ce8e6fd38fd5d949312507da7c49ecf9a86fb650236d305c1213e01	\\xa03e771a3391fa9bed14e5718cc93a594b85d9fe90b16a55c41349a4cfaf0f0054b6af04e7450a918b46f264a4848ede8feb2ff3525610746fe4d2a1f5691ba7	\\x000000010000000141284a6e0dd3bfe5c3943c67f0f95d78de06848811a0918021793728ad88861b2adda29e0d9fbf9314cd63ed04822d663cb172fe7ef93045f49c59e47110e4643600391132037f3035176d0134e14d8200b9db36653b15e2c0967e99beb10e2296f144fb9118a1bd3776af14810f462d3890dd6a234a5ab1504708aa80260880	\\x0000000100010000
12	1	11	\\x59da8ae0eebfb88e71144d6a8a9dc534e6f6e2f4a4d39172305531a7ee13c8c44e5e7aad581b26c381a6c98e72b120541e09f7693811e6b24f5552c56a3b440b	422	\\x0000000100000100e7457184c65db498ff6577bcdf968d531d93fc4f23efe3c459bc5ef81782a79dede2d4b6329d33d5bb757856685d04b73c098440d418def0217ccdb5c8c29e349b5797eed79d892b178b459b949b6067b4024aa7774122b19ece352d9232868a489d2dec74aaa82b491dcdfb5cfd885c45c1305aa02b97cc98c038545b8a7bf9	\\xf1b6b5a5b2a2c434eab36e72329c3f57240828659ddebe77e1d2fc066b278ad7edcaa880c92c0e992a3e979efeda5e69c220f30931ee6bd5857f7d33cde1993f	\\x000000010000000127bec963b8c144fc463a9a34399ba22f5ca09e7f603bc21dc8242a0fb5274f7f544adba2033b1dc9c58656f38b489fcda8100a5a58a95b3cbda2d79c374561003fb35dae709cac55ebe4bbe7afcf7b4d1c8ae1c00170026ab2f7dad8c4e03771b2af03b471421c5cb69887b4c36b23a8ee4bd93271293a7bbf946a7981e3375f	\\x0000000100010000
13	2	0	\\xa5399343c42227d5887bc292942281475de7a8a508fe4f7772b4f6c330cb59bcb0812dcdd36ef070c1a38bc0169b56fe90e53c2b171a0e6bec9ae82294ee060a	311	\\x00000001000001003f3054b68d9c78544fbea62ce063bc1204194c982435274c4771739f03be00b0478792dd2e2edff9788b859b3ee0e4eb2cc31bdb1134d780980319bf2d9cfd1c58512a94efa12ad8b22ab83eef91acc2a37dbed92b0e9df0edb06fdb167776481fa9a9132c29c63a3860490fec76adf43db0791b685bae2abec2a7376158974f	\\x9dadfa4d7543bba6f573e1bb1a3c4980330c60099ca0f1943577d57e61e634980f9b6810f81282689e96beaba2fcd64c362f7dca72c78c8705e1f02fdfcea253	\\x000000010000000131ace61543290d02cd1b3f8cb7398e37eacd1b274c22eead4ed3984b0c73b3a20b9a14dcfed0451bd4d05a775b2084b5979aa9c274d8abf89cf54d054321216c5925feafe05f92e07c6093cb677e10dcdc2cf61c95f0a1d16c304ae402408083c3a3daedd53e8256bed71c0f25df05e80e529e0e8a6210d22f9cf4fcc578bf2e	\\x0000000100010000
14	2	1	\\x02028e6db63e1b073d9a96de98a59d2fd9e099fa713d98f15801ce202a0b12df4fbc8f3b4519348bc391cb80b50af170127419573e1e47a9fcfdf9ab1626d306	289	\\x00000001000001005b8d98dd1ec2f1d1701ad9c688d9b042f532026904d796470385fa146b6d3ccc5958931bd065d8ec6c1a4cf784729d6b01886e56018b17541bda1aa128af548a5ffc9e2af2aa96f9170aa64ee446463cd222f02aa9cad59e08755dcfe3a79169fefe1a35ed7f1242f2aa1dd500355430eb86c23cc6c9a42ad8348e0968627285	\\xfa477bfc8f05bf51a1dc716aee4088074c9fbb1809a896ef5d0ccdc9f51d6818bc136071b1e14b8ad1994246571f9d08477162eb2a0bc05731a3bbea99b6f3b3	\\x000000010000000130d6a74b6a5ab811dbf0d0e53768760f0254bae7ad1f28ea59570bf85da69a50aee3387fd9571f316ef638175da9334886f72a33ff236065a97a27bb698fd3fc04f697e55faff18a15531cbe0e91195d794b54623357e11863254a9b26465f7f784bfd9d82642ca17f02ad9b16f6c3f1e7586343d42348e85c9bbc934ba8afe0	\\x0000000100010000
15	2	2	\\xb435b605d168aa7330c2129e0c1b1425403442294f586ceed7f7e50bdd4cac20bb7b9b40d672af159fc3ef7aa12315e6953031c8a84f59f907d0ef31df9bed0e	289	\\x000000010000010030cce92469a423ab9c3db758e96fe4fc57a4c9f3bc117716ba786f1a54895f4f1177bbdf97737c4732b1e445a68e886677ae734e2036635cc98ae7ea16f4370aa19771d14cfa3e16c87bf156a00d1257c4a07f50002760a1cd89ad4b0986a1ee3398d720502c70130abe885394578c60d4afe6489903be72f3f586bddb1610c4	\\x8069f712529df5220d3415957a1270f675d712060a97752520c504aad77023a8122ed75d127cdc486fb64ba3b7159d2cdab7eb086d2ec9e6d9c2b9896bc4fe3c	\\x00000001000000013a2483c7a9c4ecfc8b354bb8c16cf82c7a0dabb67bf7de7e05d15a1d7173cbc6d6cc996418355aa84b0a2748b3e4aa886c4280e2c2f27a68c602dc958eb5401a74431a376319464b5d9bbaa25cf3103ffdca8852827738f2a5ee1f4b0311cd432736fa36c88f95e4c012e761d0e61f9e3b1e5016b4b96c091d45777be19252a3	\\x0000000100010000
16	2	3	\\xee7e72a10084b9aa94b105975019ccc09009e08b3bc240e2f3620c0403b8c8ab297da6c4854e85f34238408db52a01552e07d53b967ab458e60c271ec8c3af03	289	\\x000000010000010085046a023600ff498c44047884f07fa1c5a2dab2e3482c672f32a33d72e3bdf3c79dab594a1200ec92fd1ed701d290eee4640e035a5c57192e2e2d3cf7ab978f31342b0f6f622efac3ee36930f78f0bb3a8c9dbcc6f82a0a9bac9d12f275e0f8ab3af29baf665efc09dd95c577b0b7e3e7e6f2303817cd61d35ca1e26ea2e957	\\x231c84cf69a94fea6d9aea3e7fca911f3843416be4991537e4499f04e9df7a0ae9d8608bf30c9efaa26de40dc650a2d4a7b168d4583dfc419ec8a655b6bd190c	\\x0000000100000001b39e7d4ec6b6dfae55360bbf3a0fe1b7607a98bd99582fc29eaa34fbf51f8972e540e110c4daae5d3eab9c6626bf247fb6139406516fc2b6887db77c5f8e6e84c21c2afd814885f1dc1687ba065a643d45f831c426c29027483f744ab5cf8bdeb854079c4bcda8639cfafa524ec82f871f99052b622682c11fda94ac42eb49ac	\\x0000000100010000
17	2	4	\\xb0f8905bb06600e1bb36a40db042476da6afcabfbf07812d7ce9509d7d6ca1b373ac7da88d275446e79ae7ba705725efa430328b2b9f8b7b2a263c961e57d908	289	\\x000000010000010035abcc0d18e75690e22ad75ebb62a961c7ba7bf0bbd3a81160de82ea167ec19a0a209b223bdc234529a4c323d57fb737aafc9b4d65afeeaad48f4295e63c39e4a2f8a7a90b2b229c25b3ae07ec146e4b058588c6cd53121b7257c5c0b92201a043fd528bab8963516ce197e92be1ae3de9eb1683d93cf92d756ce6f356d62794	\\x86dc4d3189d9bc465b29779ea7a18ecbcb1114ab8171433d0e791847d8d2f85a43efd1e06dc239f08447d6adb6aaa733e629f06a709b884e35ae8512bcb39c8a	\\x000000010000000145554efcd2eff9f7b420f3d62046996c857b286071ca1c4f1314f8a0f15369f3891d96a617648d73d7f7387e7c1a921ed8265dfb88c2552129d217313c3efd737d7d23347ced883b19d58aeff4db3978637bef0147bc57ad50624a6c36ef1f173c99d5a547c1db99903a19f2878d2500fcd65c4267a39fd25d9db6a7077426a3	\\x0000000100010000
18	2	5	\\xebc2585d4ed3be0df56089d5b25175948be23912e94488830ae9cad6d32f9dc654987f065cd3c4f9c3c2e04c6ac771e4e5a5e7d09f83989500426a5b0722c300	289	\\x000000010000010028fb7eedbf32a56b1ec2d1276d6cb9d4d3466a83a85d09c45a69c357e49db5cfacd62b0c3587551e9d2a088a54de614096d50d66b31ed82cd4a77359995c5d08c7f6abf5628b6a28203f1de1b8e5e2579805f56fb181c6265ee895ca49a86fba59cb2fc5dc02ae40898a3d629d2f930a9bd8d38c85a1ac594cf9ae543a6b8a96	\\x2e688e32563f6a7f023c85f3a2e03293e7a1aef8e51630f03c9ecda54e3d50a29006c4b66fa52c3fc0f542c5bc08d2caf1872e7b1e5f772f7dda79b303f53fcd	\\x0000000100000001193c4faf816f26bbcd2aaf0855f7fcf790160e94fbb1cd3d16664b81881d22e08f35778176dd8dc40f2a5a8c0074b3c99b556ac1cd4fc43c8b54cfb71f88bcf7f8f070bd2ff2c86ee4f384084162872f831f89b0247b0cc94d260ecdfd8e9afdcbd698878b1a6985663b192c12312456c0278dbe2fc9ba606dd99d9b061cf848	\\x0000000100010000
19	2	6	\\x122e911ea1d30c2ff3abfcd6b3cc9a96c2c0bc5936441496c789612406eba26fea3c58f79e7bceed52f02aa3cd5c14231b96d7d3f0fc4930b066c39460da6f03	289	\\x0000000100000100673a59fb789a0013ae6d3c81451cac421a39160000ed22747ef7a481b3070437006fb02aea9f934f07aa9af0a8e19bf249a6644bd3562a38c650e236cd089c3b13d9d7d2244ae833a30b7c797c87f4cf7d8bb41c620c6d480bc5074ca0334322ae3bdd1a1879a58b547d38b6530d44bec5323c10f9202f497a2f84cc4e745e3f	\\xcf52c77c86be8fffef1fc806952fb49a6ad3d7d686cbcce9bceead1530de89b907189c050af68127f9b0e48f9a6e5c9fa5ed54b21d04378283de248ba83fc719	\\x0000000100000001be361c03fdb9b86488c60a25ab260236d60220cb1ab37729c38c0bb17a909642bd6cfc66ac43d1fd6728d1cd6b3d0e6e91f1f7df937a2a038be44e406b4bb4f4b0c8d627e3a0117b483bd1f578d05e41de314f5c766a1c2660dbe133d1bfa747dcdb98f30e0d680a821f7c0ab1febf3ce7f4cbf8bb05149ba78f5702466d0bb2	\\x0000000100010000
20	2	7	\\x24c312e09290dd5af5c9caca256dae091cf1a35f0ce270e4cdb24f50a98116b33c46951edd69c84ff1d2aece783f4a594fc7d2c29519dcfccf038b49f8288a08	289	\\x00000001000001000373e5377e8a2234a3fa6ad82e7bf20a4763233bae57a98cd2f418bc117e08db64142370e51da3cf15d63b00c1a051f8f574a474b7bc088e083fef7ca9c962d39b86f5034cd2bf2eb40edac87dde0bc174e2f95919eae2c621cf43cc9d44b3e962d71c027832ff81247e3221d67162bbd42c035f1f1475e8752a488be73e4d06	\\x69f84c7ae9585f8e93c6a13cc2e5960fa154d7eb7c2efa513f1dbdb91446231ee06c15fb458547328a388e9a7e2336ef66f5d5e78a1c22bd9cec9b5e4f09bc37	\\x0000000100000001532d9142d25c7b3bbc91ab58eb0956f9dcf735b021fb9009157304a85d4852ad9a9cf1e64bbb136b7aaccdc98b152b1f938250f6104135e6c933c428ce2f4471e55fcad5c3a5f9e7cc886d469680036101db7e7353bb34705710559538389cd371b9d57ae23561e642bd63a634adb983a2e9bb9a5e8d5e40babec9d7612c5452	\\x0000000100010000
21	2	8	\\x7c0dd0563bba65f120ccccee89b131ec74e5fe5142c3c4b9f15a27bbc358041028c0ba1e6c6d55742a3f21acca890938b3de221e59f39f0325b5bddbb1451406	289	\\x0000000100000100417fc14f05c6050205d339bd53b79006087b2ff5f02994d34fc30386dec20d896f63d16c9ff84f38332697f964de6c8140f1d1a2d8d76d034a338f8c1e38b20033ed9f4c4cbe51dfa035a72e325c5f79263e2ad873a9982be31afd0f1fd078fd90a9df7e10d80d74314a22a96aee229d4f681a1d022c7f4ea9e6b71bf399c34f	\\x4a98036d891f6960b0bffa2697b8af5e88f298335a01f640c056d290397213b8e07f254dc34c02816a16a6a3d74f0b6093dc4dc5425fb9e64684577d8f69ea89	\\x00000001000000013708dacba89f8a7124208d92e4109fc1053e7ed686012d028d825cbfa50ad8e3efa576caa98237a61e25293a3b5c66f42a589295c7ba5904c52e8bf7e10805c3115a9b2db5890598afbd31648f42527a15df1e0635f578fa1d177e802bb4cbb1f806178091fb1755f9c04027bf6bccfb0a2d151559eb24295b2c870729fefc2e	\\x0000000100010000
22	2	9	\\x18b084a832ab91fb7866328443d26ddda59c2545db7afffb155330b36fe4f245582200c6ce78ad0fc658928db0abf892d271fad1731c183fc4e4f9b61c80660f	422	\\x00000001000001006e3fec391f073e34de10561ee6b8826688e452f71d82554b6670a37c21a2acf02555fbb8139afb365d9d510fa942334166daa142b412b5ade3b911ac0ff0a0f1eadadc278dd8acdc972f193a0d349ff6d844ee53497d0c818561b11eaf71faeede445be47b803da7a04917781ebfdf750dbff0267cf4f94663333ea1c2981a4f	\\xf7731cf257f996de07f9c0da402d5647f3c43be9d425c1dedece1301107747696be5dd192659f4b6e683c27ec0c81df3f1deaf2862bc0b12061f00b14faf655e	\\x0000000100000001cb686d22b724881f8d6166056985f785e7eb679f4782dc2b5b0209f9a35c69b95a4b93c25db96a6c02407922c77900aaeaed88aa64d6e0ff08013848e723b38dbd8c2f21d6bac3142a22992db73147e7143eec87103923de661edb055146e454398d066e97aa5016417a52ecb5ea49051256aab318f70b952adce45ef364e330	\\x0000000100010000
23	2	10	\\x952de92f909824ee87d25e018de613bcac06f66cf860fd358dbde13c2ed921e34b70bf42eaacded8dbb50e0357ca754aa19acb7ecbac5968837f3b3a12306a0e	422	\\x0000000100000100d1e264974b842ecc8af47d3085441b41836875e6d4194e0a3e012762f3a9863b1801a25cbad0493e7b96c629cb0eb2814ca20fef50a9cee34ffd587ec72c0ea9e472a4cae5e059a3297bf20e74dec27f8d40664af784bbac1bf35b86b32f84aef8ba99a4f475361eb87623073e4c335405e14b16e16478bbf1b415873a7f1aea	\\xc1cfd8174ff967fb01e17a97e26214c8bb4f52aa74a202e2451a46a45d954c172569cd5bda741ddac3ae04f9c2c18b5308e96f1524610b0e2fceac440826c26b	\\x0000000100000001cd8d6ece04a8da3c11867d82fc6f7fc8a32ad024195966ebd70b43432a286486ae08a92b261a368508be1fdd588036c3eab474d6cb36c520410b201a0e81ff0803a7d00f70d8b5f4d04a8f52707281bafd134855c6313212829623587ef91cfd54a6de74a64c1bdf727817ec80480a9d4e286e824013ca6ea7eef5ef203aff45	\\x0000000100010000
24	2	11	\\x3045582bfe34dfabb10a30b5bcebcbced711f157248e8fa2a64d3fa93ed3b35075c7fdd806f88ff15722c49dccc500588f010c35b8ea8b7627bba8cf5ef94204	422	\\x0000000100000100b0fbc9ca0d0e3c984d4fca118eb85ff7618e31bdd4815410900f9c0ab92b6ba8b1d2f6390b248c0c14e9f87a090c188a9c0bee69bf32515d6bc7f80e4f6063e63ef73295819e0a0dec83e92fc8b544a5ac088e736421877b80f1c6e2d8fcb1ffd915f4bb01cf1ce3cb51f0350b66b52e26eca31b7974a64494e7776bab0abc93	\\xc2f167844326bfb5337d53ddfe526eb948cc391faae0acbd05935ec868cba5a01dc13c3179b20f689d6b480c4eef7b9bab2d513ef438a8c70d84a48425ecee69	\\x000000010000000167bc3aff6983898ea9e6e7aac8c9056da118ca3d20d787d011203174bbf2cf453989c7723452ed037158d3c07d943eecf505a58d45d7955a9e0a49edca2ff97a1cdfcfe083fc1a497903adbf1428eeea2d098ce4cd66d2bf2a5508c5b444855e939c6cd28575c3963a2c0bb3144c2be42cdd0a4e8ee6f9c3ca35cfddc4ccc8ac	\\x0000000100010000
25	3	0	\\xa31257bf456c4070c99ac0f5fe5c3275faef296ec7fec12a70d728aa0a7de289861d21906362162e7c6586719ba7ea3d421aca0880bc51b06cd2eb5a6c267a03	282	\\x0000000100000100a32b74dc4fa9ee3c01fe4537e52f5ae1fef30b1582bac74c0707499326b02f2dab4fdf08588691717afadb966fe1124141c099b44ef844cfb1cf479774353f4608f219a338982ab24477ec89546b56ba95da2804cfbc7fc698cc767efe4857c9ea016af0d44829e99086ce90cfb8779e2e26768c478c3d0a739187eb232605	\\x8605a2152950f4d3e4023e5fffc43849050c617321b0c26e2f5cedaaa24ebfc5e1cce42c3b8122699ebbde4779392bfc3e16bb4ed03fb3439c43aed8552e6433	\\x000000010000000196d800ebc814f218c1f7939f4d9fe1730c8cecac90e6c71cc54df4287302bf0c29797bc0cec765d8039d8251c07b1e0bb354dcccbb1a9bc95eaa9dd5c77b0b7607e98aba12492d575add496f6ff0794d75ea5f0da0fa3d44734aeadb453bf68c8b30418a003fce5c35225d0a08c8eda70ad82331f1b6c7f476f3d642365c9f	\\x0000000100010000
26	3	1	\\x3eb0c83d3d496ed1d828ed764e3ee15cfb31114f67c74ca46c3a5822e50e5ee38914f93087d181e7471903bcfd2be64110217f30adfd674efce8615e010adc05	289	\\x000000010000010039771a76236ebc69b548ef3556246201ae958edcf24fd2c33f6c47d630ed92a8f3f2b67a6d2f3f13123f3efb7d4147890df00a3aeb1c2a860118ad466b7c8a3cd33eba9b68148c67a2dd85ab600f89421cbfd43c4110fe7e054f76072943001a538988b929f8d95893057362f57503845dac924538b68f5499666691ebe25f3d	\\xc4d90fe0c184dec7797d919e0c8d137103ba809ee8aaf51b2b8ad7277da6e647ecf440aedb44dfe8665955fd6e2dad2b632f1ad3f0d92b29f84ce7502378eb1a	\\x0000000100000001955a5d1dd3d0f4152874c07a5fa067deb7a4b9c7ca2fb58f4ce21eb128d7aea95b66e8334cc9ad7dc2a860c3afd9f5c31b0a522beba6761f95bfeb2b9b627285034633b0ff27de0db561bec66ea8b49117dc9bb658d76f6760be60b5aaf18b0521793feac1fb3eb7bd5a022092e8a5dcb83d8723d7f4edeb625b75f77879d9bf	\\x0000000100010000
27	3	2	\\x39577b5a079ec1e72fc3f4ef95e944258ae99408c0072eb804a1ab0d23589340b0798cd87350521150e34035caa76cc55dd30892a059b2ae1b1ea0c084074109	289	\\x00000001000001009f6eefa4cb4a14836f0af731da8e6bbc48856c50ed657b6464c94e383f2a113059d09b9e536d2175c30c510e552df1629e80a1730cea60db37d712fc47d1968032c54a29fac502cb09bbd8a28ae2a4693ec9761877d51185ba57a8bc6033221ddd6671aef848c070202d5c95de098850d15fa3afc0663f2950cf65f6ffa3ceb1	\\xa307f9099a7acbd020d67d2584a41dfa11cf342c06adb60c3e6b5ec55b6dc63f4c78610d4adfbf702b7350916adb0239aa2ca0c8d8af6e46100476d533d01513	\\x000000010000000122c3a756e2eeb1f778b2975af874e3e8406c8f71b5c418728fa431e5517bca7c5ea69dc20ce6ddc84f350cec12380e9751a94500f36beac3c8281301d5350e9b5fc746ec9ecdcbdab9100380e108ba86254edea1e1f634d356f56f4167c37c3410e4b92d33649c0eb009b7662e0552295c16a874d94a69c7ac26dc9eebaab622	\\x0000000100010000
28	3	3	\\x8b417a89abd86c9ff52000c62ecbb7562429b676da21bf34d551bde7060c0ab659350f9de75cfb493137a549af51e20a69b60791d6fc41014c98da8b4468f60f	289	\\x000000010000010082409be503864ebd82823975cd406bbbcc17c8b1629954ad2c18982d9e338230430783758746275424fc682e654093a87c6c26a0ecc9a123ead2449d078834dc43a0cb26ccd8a5451b771c69042302ff2a74a27dbdb62e222d065cd2dd699e0cfdb6510c1f4f242b0f70bbc72795659cf671b3fbbdada3ce55d5709b0d83c0ab	\\x7deb540a223c4ee30ea6b16d26cb632e1f3df3c38586c7114c3d8396df81bc743713634685c0e761fb2d8190f786e879568c56d35074457ebf97869dfabe61cb	\\x000000010000000119b61a3d58204332532e3111c81c97a47f5b327699b66b4a268bb16b635793a2d2f3c59bf16e51dad804518ec1f5cc462c70d4ac2129f5d9338246b310575010d0c260b506863b0f72a2e267e7a1845a54578bd3fd0e741c432da76214310bf1b0cbf7b457f231449e9b13b1ba279a633ffc6a446e0b47df5d3ce005e9d11e8d	\\x0000000100010000
29	3	4	\\x9c7f9387499f5c7d4502f5738503555ea57ed856c06bc059439d347cf5abedb966e98d3b8129d9914c30e83c136103b2372a514b1f6242c775a7490a23caec0e	289	\\x0000000100000100834a9c482c6d20208431274b1858412bf4925377afed3ad60172efe4a05210083334f27a84855a5cfcc103acf6f0544aeb9540b699cd5fd2d21372ef334c6ba18193b5c353973fd557c77755527a16e20358a9ccc7542284cf3082dbcad53e19287875e75486c5684b31d014b6edc800bfa3338d1225a19575937a3c9cdaadfb	\\x6a72ecceadb62f5dfaa8959fb95b4381585f1734e86bde4a1ec9d0c3e92b07f5c57f1db6c3a8412ece407999500bf19a274bff8300d4d412d127923ace2e8f9d	\\x00000001000000010bb61c37af91f5d1e708fe0a313541fe497c09b1be8ab8402a109b6aa67573552383d954cf7f8dc9e8844dcffae9f989f11beb70929ef1a7dbdabcdfc7c2afc1bbf4a29914732dd04ccdf777b160cceb28b94bea2141a4753275331860b2cb0bb834bad55d06a8f6ffb7f4079067e734cbe5d2bc4a935adbf76adfacb6bfc287	\\x0000000100010000
30	3	5	\\x965c00d62e0baedfe155b79f20daa2c1cfc181b00644e7a738ff1d2a7dfcf3810d4265975899be31e412ba8ef88bfd683aa57a3b97bd44c24c5d934cf7aaa90d	289	\\x00000001000001002466c0030b9260f9a9a191b1069eb8ada2e330f279bb6a2047bed5cac561444b326831c0a5f4a0a20dbb328a13edfc4d3934240937a4303f46f08c9138fcd3c1504800e468438099771bd78adea4128a762ee2cd7862f2eb3da99fd2662c50606a7e44b1e3763427d66ab8cbd9e14c25316cd3dceba58ca12c20341bab87ba98	\\x959b70592af58da7cce00e677d91e2b2c2a1d7dbe464963c9b0ed7b202c9b3dde0a0b849b92af9162c3299e6ffb567979722a180ea2e8dcf424846b0f3470b97	\\x0000000100000001adec0d00ff93a7842d5d99d2b8cd5b8ab6343e90e1cfc632920ef22fe3ddb091997a4d960a331a656735f08bb825303e9f7c752216a348dcdd43503d0582bc7295414de45860c4f37e45d4f3697c2dd499fe77266acfcbafcc17c652b010ce0cfab29e8324cf27ab35da180d7ce052fde32d6aa2656b08dc7746fd22fbf17043	\\x0000000100010000
31	3	6	\\xcaa75f0603b97672f798655bdd41ac1fb8d787ff3e0de15c30ae9d2e962d8a17d67b191da76723def5c8fb69f8c6e9c888c99b5c45f4a4bc245a8995ea5b590d	289	\\x00000001000001002fa225ff0bd045af9714e2f5f40c1031f0c804d0a5b6ff662d7c837b906940edf19e8680d9811eec4c52376a36ed1b6cef7cf1e7f412b0eccc0f72a07d21ae0a13c9cd1585a427dc385a378f1f288e526f3a2da6ffb6841ddf1b6fb12c72424cd433ba0e3b52907027584d54e9602df9540bfd82c4d7fa383377dabff6e0dc4f	\\xd6a0d091a8d3ecca831885279549e5e1030ed8451eb55a3b9c8608abb031a1bc23a5733bec5f8f3eae5e2f3c679a5d0175194a31e4f9deaa46fcb5f43578d3ba	\\x00000001000000018eabc442b1876e593cf728817cba9cf850dab6a5d6b537bea31142e0ae1bad565df789818d1000a35c8711a13572c454c2e76f332b1a263148edf5672182dda5bae96a2ac11f67e918068537c096c196c3e0dd32843eb0bcfd9107aa7075dc8012420dc0fa812ce4eda1735a5005c2675f7cf87364b7655000bb1f6aabea3cec	\\x0000000100010000
32	3	7	\\x7802a0d072134cefd4f102108a1a8894676a1ef61f9902823e6fb7759293d396bdd2da59a3c5ee1c9b8e0138b019bf1e340af06e60dfe97d333f34ce7daa6204	289	\\x000000010000010069de4274d22da2beb94be7378ca2de51339e5974370e6862d5a20230006d20db0902aa24efb4f7dd392e8f30b4e29adcebf1eef2d6eb16672d4b215a9e08fede61d319f2595dc0f03625b768d8539c9dd7bfa626570bc4d0f58f405259105d06dcc6d2ee39572ed1240c9561c9bac4da003648d218927daa0374e161b8706406	\\x0ffc60b026cf0f0636a3c719daa487888b183789cdcb93db140e2cf959c3c9ba4c9c91bb316baea02b6039b005eee8d891cc88dd06977e29e0699b43eef59cca	\\x00000001000000010b2678201b34ee4959811e7e42808b98f02886d71fe84d374323881c0a1a712376d3c301b301a095d5b4babfe67c51e825a3aa50ab49ac6d9364b6b20ed79fe9537a4fd85c1e8203cde18300793d62ab28d8388a4b205bdb3ccba54645c5016bf3ce7621c656651969b0199162ebf5b7f5686b689289cd0dc800ca68543dbc32	\\x0000000100010000
33	3	8	\\x8d8377f92c3bf316aa41e4df0e738733e47d51912d68353c65a9d7130d2b4212f6d1e0d0530b8e18b0e31eeaeff2860738d80b85e3b7a3a103efd93f726ce801	289	\\x0000000100000100a71e4bec0b6e9da6ce70cfc9c0fddb47edd6df20e8cca9871828790071a17b263980aab0a6bfb326c9353d799fe722b4d2fb49440aa560a364512c1e4294a9c80adb4de76266745d25e8bdb19294ab45a3e359c5b60457ea2d758f67a3defa9166ce9738369d20f34b15d89d11867589132e4f0c24d7785afea4a70408185393	\\xbba98981fc346aaa1e1115702b80a9b95ec7701e79613e4c63a598e739ced324c1061da5ba3e45974d85e072be3dae985b5797db6e6ee58ae6e899a728225306	\\x0000000100000001c00f119c58692dff450348be9402ad6348fefcfc93faf97e8acdd925b99cd22496a9c67e320a0409fd9f8965c5c3ac06c14e224de913d872e507f05dd49c4b77e4d9928a6fc718bafdcd1566fde41ae58891eaf274fb6a5a885f454dd41b0f20f8704a824900b8f2569d22d87fc2b896138c39e854ece5b24f0a60c1f2047176	\\x0000000100010000
34	3	9	\\xe34f507c2a18c3736493bfeef1c182fb6d9d5cff40e1eb439f7199fa1f92798caad1f253263f0945b6b806daeb62f34b4a5c635485596d2ea2c9755b1ca9df0b	422	\\x00000001000001009efd27480b901b2a786ab61ae42a7382e147ee7fc4fd49c3101612c2797e5a0af6fcbd53229ae37fd47718a6ac3ca96bb996f87c0aeadc2765f4fad852a45ce459d4ceb9f1299c337c9efd7aab0721488c94ff6b4ac8fd1eb267b06a7a12227b92d48ec3de56b2f2e45af73804125043b648fcf94d088a2b9afd9f80b2b2915d	\\xb3b9d388ee64a8c5d0c2094f6dca64772b66491d7cc862fa7abf9f2cc41b6935c13b57b30bda3246c930fcf523bcd5b11275745f516f1e4e11ea61482b5a5cd4	\\x00000001000000017a77a948258adfd3f1f7814bf2c97622db831a96184df0108207feb04fb2884f1e0e7f745744bc026a79025c3181651c8cbc2af986e1a118224cca56cdd82074422bc2ca5ddf30ef9e5abcf7e6f890e5ac52f1d3f4950be2a66cc5b3bd6f2581a69cfd0ea2e161d61df6d35d56e360122820a54cf72fadf8999aaa94ded383c4	\\x0000000100010000
35	3	10	\\x8466bad3d0fe0a3cbe1a2727cd1921b9cc0491acdc7859d30eb90c098396d6d3a364ab3eeba12be0d8747c569833dd42bf943a33a2bf468b5c58ab65a5927d06	422	\\x0000000100000100ac5c21639920ce94e073d073158ee3fbb101cc8f693a7dad47a982649707d92534a48417e0c86886e9bbe9f499ddbd4f9cefd26090fbb190ddcbfa1f76e02a293e814819a073fe061fe3396c318bd83a253d1daf6948373f2ffd4b9c0344ef6fb3de4a9896229073926085564f3246938ca79273c5dd122ccc926feb4ae69f79	\\x4332cd6c090889353bfad43894108cba80e496f00aa4f533df99d8feee0006eb9e19f920769004c9111e151ae39f24f4c284a2ebe07c7e8ceca0d6baf92fd139	\\x000000010000000139c51eb5e977e04795b8df1ff1999012149e1881ce2830202dc070b7d9bfd9fb588415a578aedc2351d5a14916f8c54de373387ebb9bbfd97e9000c19f2859ad4b93abd34c50325b0be187a52bc9c6cfaa87b015cb349bc43fa208ab219834fcd15b1cac7eeae6034edfb0cb045a06ad8c9c6815bd2d32507a88c9a0c523429d	\\x0000000100010000
36	3	11	\\xd0178c35c442776b612da2f50e7a0c9538be184a68229ef16f50b1f26cd72cb9f0d7571da160a70f0f662b46d9247f4b127b52c3e1320d2750bc65427b80f006	422	\\x00000001000001003780e7ca885e17797e5251407402799f7f0144925defa3849b635a8e1783678a1c1ebac5ab904cbb19b9438225f94c42335b5be001c31afaef9ceb06729a3714d421694f6997a50d8b1c29902c091e3c1b9bd1918aba8ca904fbc36f7788159d8e7875185c4b0449552006be110cb4900fd28c8625895080872f9f890cda8930	\\xa951700531dc3f456593a855fe8ab7b42b2f0519f341ee6ddb86e72f90c3e4cdc00a3bb9cd9612a32a61b7e9aa35b3a8b7f8a46500c6e5ebeb2c64c4b49b2186	\\x00000001000000018323d3a59fafc614f1fe2a2adf7421e7745ac9f3b0d20df219303c6923e0a780da2083f95f27a19a39afea9e5a885c2635c5cf9fa735f60f9118dfa8cafbee60145a4383952af27dff35e89e93d3c6779d6ab4cc8570767d63215847805dbe528ce7a762cb85cd2303a922f9fce3cb3b1b163fa4f5997d97a40de999e5045a72	\\x0000000100010000
37	4	0	\\xd357ebe0409eaf0f33c69a9e7ff31c812461fd9723f25ef6e3fa1543aa29da95b5b1548b28160aed44a2742d9c663d34013099a012ced9a04704beed79e6fa07	193	\\x0000000100000100414034998489f76b9e9b80d6ec3595edc9a82efb7a9f11a6a396f394abcd7070396a555111d2047d5e88f35c33369c3eca211c6e209c4cc2238cb120c9a3655965bbce752f2299fab1c8f33caeaafee17d0a5894528eebff005bab3e9b052252746c0b6ad5afc3700978a5204439dea8e87e2fa65ec0c63b72073275438873df	\\x8c979acfd734b2f4d43ba5975bbc21db14f89cd8e85a29b32548ef4f6463a20d812b11ffbdcc2f1d8025185d6c890c9b058cd22c748e0f5e4f6575dc21fc4026	\\x000000010000000184db4d31d61e5c15c1249fe863dcca5cc5933e847587db7eb4577eb06dad77a41f9e90e69d1121b3b183b17a51db86b6605e3727a5cc66da9958cf41ec8e04b3f0ba41a4e3cda56dca15000e9f7e904c37370cbb10e552fbe3e8513d7ca3c70cdbb3af4f601c6ea3a4483c5d477171e87e723e5eb8d6243074c43ea21bbf1953	\\x0000000100010000
38	4	1	\\x7350ee7cc69741e496c3864c707ada7db644177ba29c4051032de903db8686143edc118848d4888f5ec3f02ff75821854aad23defbd34c71115354915299e307	289	\\x00000001000001007a9265c3fdaa1e2731099ac37d163083088f65c89b1554185a8a1a7e9efe1c6e4dff6349b246cd1033d2a918cd2b44d2ba7bb702b92eca977fc089590d16e3e57fda13a21d714a6632cc97adfeba8e37bda397ea13faa51ded048366b04b89531b92450689340f795372ae06b4135c07c433ef7e1e8df7c343621b63284549c3	\\x0c63e453e9bae237ff23e177a2ebe79ea7c0e6dca36d798e62d7a2abba5319625b0e9cbcb2abc5399bfd74451eab622bfda3359cde024d73b4cde882352b7948	\\x000000010000000130071b35a841343a5be1cebfdda5b5a61061709c267fb1cbd90aba1a4b39f8c350000b8effd11da449040462b2e0b6d2a072cae9083d21da43b346d68312335a500041d76b3f53cc0cb6bca76c1b1fc933c4f35989260048a0ad892be15de430990e44e2e8712a186a75e77811395f93b331e7225d15d2fe95b61be6638a700d	\\x0000000100010000
39	4	2	\\x657e0835a264692d8dbdc8a468880102fd067c9e285872f690cc03d5e897d8f09f66cf24c3ecba979df6a6f9f88804bc477da12d9ad29ec6677d501f15e8220c	289	\\x0000000100000100964a40af4765ef450d50d7840a73a52ed5da868d649e9999512b12454fec206930e487d905e95853132b5d17d2284465093cf38903788bcd47a889853c5d486b0779073a363d7bf2b1f871a98f7db6c7bd82df14803ca7f525f148d5c18e48c2522c6739331ee8c76f227d9f795d31c4073ed0f0aa1dab266bdb0b79259df3f6	\\xb3282b3a7c40e8f6dfcf5c9b9c19a3f1a5d67077fc0b0b92e1d34f925a51bdc8e8127abd2d0f58917038ff71e1e9e95ad977d2444e6d09f391160047aab11f50	\\x0000000100000001089c72a445c25382e074086d312b4babf7252428c19a8e173481a552c0958d48e85a1ce22c673c097667dfe5f24342380486d34251ded1a45222df729d2a43ec95ec7445997f6785e66f1730e56235ed8dc8c544ccf67b895bf4905ba52b49b3be0ceb574459fa3c23827a3674cb2c599c5654af4a2a8f5f48bb19a86d635bdb	\\x0000000100010000
40	4	3	\\x41235c79afedd2160d52312f0c0c26ab60e08b3d31f908d4574be7550549ab17892430dd36283dd44a0c4d9cb6aac5310f180f900b50d3a9ad384f10c839170c	289	\\x0000000100000100351483abcb70e863baab8d0a7ebadd4e234d437fedb1b2531f2c060c0ab2fc97e12d0ec5012e637b4c7eee714554d4b1798d759c36072c9e04f14d3c9b37a914dfeacf8450073bff93a6412b7ed885f4660bbc7026919f08876eb4fbb79f7d23abc0b3fb907d395f3f8952e0f34e765eec6a1ce892d4a759cfc583dfa3a1100a	\\x5160e3cfce577c945ba26d7a7917e097b06db489c4d84b1903bbb11f7932b8ae7cba49bca2458dcaf61d2956a558b52e8d3e9ddb0d23e967995b7160efdf61c3	\\x000000010000000187f79bbb9ebe699e19cc85aba3ca60c683d08786efd8af64a81812990566bf23048cb398b12173d93e06a072a98f4540ac4a2e944764485a1120a3748738e20dd16e99facffea610fd49367af99eaeadf9b824021c671966da154e65a27103ea4c883eebc1fda18cc61177cdbaf97f0103c3e658f85f94ae9a1073438f83b7c6	\\x0000000100010000
41	4	4	\\x8c1b2d454618257cdb9287ebaccf6365ef454433cad3193910e18707164efaf608547f6b0f06a396b634b37c814513cf86b73cea2954028fbd9c8e0f82730d09	289	\\x0000000100000100b57e590f15ada9e96093e95ae8bc7e270ac315e70118ec9369e61a14c3e7f27a454fb07b3086eb890a8e4fcae3d36b0b6941607c4e330b405c90a489267c3a45f765a41f448df50b7a748d58031323f25a20310c05f8a3d668d564029f982ebdbe17af94bb3c0666f01878e3429243b1636b13db53e715ed623318c2efc0c013	\\x77689c01b9ce7bd7ae8cd6a2c996b55d14bbf3d197872c03c0b48d425a5e713408a34e3886429800882f61be9759b43d69721c77d589ec17593d368abafb60ac	\\x0000000100000001bc6a21544c8410c44983c12968b12f88fd7cdc1a757ef6b1feccd812fe97fa001ed957d3a481fe21d090e578d4c39866e483b6d892dbab2b91c4da78d7776e4568050521a8590079f0c166dca62d85eea4afb088305d9e88b7b396c85dc6e215b611b2e3ca29499727f0a27036ba87b4e51f62dd7651354149938c880a552583	\\x0000000100010000
42	4	5	\\x20165eaaed79c6b8c218eb2364dc0171be20d9f5694c3ebd0c483a70571b6fb9e17dab599c0b80a06a39937106b216522d5f0e7857d4294d80e86eeceb6b0f0e	289	\\x0000000100000100488cea6b90debd79dcee82050b602cc9fc6b5b7659476f14cb2ef54268ca4a90afb331b6f236d1257ad96d6a24e1411bf0e6addfdee470d6d5e1aa8eb8b94f8b87d95ef94a4016cdeb68d4bf17988d4ef853d53a419b07f39e6e2b88fd0ed67d4baa149b57edf2cc53064909bda20b53e911d6c99ba9c65c61ace81e0da1c7f8	\\x8c970bdf52868a1baeb5fada283654f9219c8816d996fdf166d8411725410fe496c21eb492cc90ffaf3fdb39f50acab71530cfe80421d5c33b2f1739abcb77fa	\\x00000001000000016a1172f4e99f69e3140abe10fd6eb6f633b671f81f28adef2a1c6615f488145e5a1ea86f1ba2d91ff8e210297e46dcf7ffc5c58d62fb21f2bd4b41307533bd84855e265dd6b5edd7960d0f0505a9c74cba26fd482f197944c889df2e43e9ccd979892ce8a3700a39005894aea755d247f18b6d1e0fa327b1b74af475fa41f316	\\x0000000100010000
43	4	6	\\xe0be452441b62fb85e583e13dac9f7f812e9c1f63ba9260b8af091c9f8064c2c28a4cf44ac5951b1a13babd5431cf85be4f4191087fd6acb1e97d45060e2420e	289	\\x0000000100000100b58e42f74eed9d0bb3de4db67bbe08d68cfb36a15be902189d1990889761d59f741522efc0cdca0956c52ded89d54cead596946c8c5974cbf1d5fa020aec69e0cbf08ec7a159892a596e998caf5e55bb2662e1d201b440669cc90fb7ad3fcee2bb0100dbd8ec3618a8fe34ff6d3de03e12e0bcb6a3f930e9f4d01326cd619bf2	\\x2c0617a7771acf56cabee8e6cdaa516d2610368cf17f6d04a858f867e3df5206b0ba520a497c6aa81caf59b7aca503f0bf7a41fd1bc4dc7ce3a63ea2b02c5830	\\x00000001000000015468448025c9c9e72636977127e8a4744a62021a15b9ebd047b0dd8d1fbccd403e85bf2428f370560e578c1c75e1e1aa98627240e579cf797eff853fbe2f602e9cc131dd255caa01cb94ecf9c200295a89a8a70cccefa2103f0f71f9da4cf3e3a6544ccd89eb10f870793782ada993df59242954ffb8bb20881bc7966750efd5	\\x0000000100010000
44	4	7	\\xb62c9b4466e9c3e157452560743f10074acf41340fff598e3963a22a47b8e4b5731ed14802d7ca17354370a8f9842af3e5e073f9e95bd071d7a524b60319f00e	289	\\x00000001000001009fe312544f0c68c202623b287ae7271f27175d07ef3ad35b944776f688813a5d426237a241cd3b99b6ced0b2692a64c5891434d69594b870ad68ec09f6e68cae3ac19b369952e0b524144afefab3261b296622d46aab99c21fa94b3056256477e58b8d085e611ebf2277346eaa41af8208c46a3d19d2f9caab3de2c6cd9386f9	\\xff604600f552c3fb5f3d85695a15393b5eb6343736bc163c50204395b03b9b4f8a84ade246011d2e0dcb11599cccb3e0e8a83257d03400b2737586b81e599f51	\\x000000010000000128e19c98b01606f10237726ff81c845c1e639fb7adb150a8c6c6fce00e37ef4e3366bade3afbf57d79b51c3de009867aa78c9337e07a5e3239dcb0ea4f1e7bde963d3889bcdce5e4177cfdda05f41d7b47fb903914626a92d943b3506fcdc4dcb3b9da04d947225b9970d34e52ba97b7dc804b837aa67d17766afaf53433e6eb	\\x0000000100010000
45	4	8	\\x739c9bb4b6c6df51b612ab10a36e9be92268793fef250170e6d2dfd81019d4859efe5865dbbc3b97060a4401c142ed639c38514688c1d756842947a81f9a120e	289	\\x00000001000001002babc9010bb42113caaf546252adaa7d11c60609661aa43385b4f20b6a1353b3c5018b70a1856a855f700bb73b7d4fcebea475f5dcd7ca0794e335fb2bb4a4e282d4217e2e73bf059733694de9082b4740cbd4e3886d6d78bcda80394dbe21c69f30e28c33cf68dc5194e3c58d4d454b24550429bb11e8fe4c4bc93f1c8a7015	\\x88a860e2eeb74059c1a53d0a364a5beb0dfa294fbb6054cd5c1b73ac0a227b865aea8d1226bcdc114006e2062b0bfc32cedfea721719a72b106f770d8ebc7d5c	\\x000000010000000192299447dbb6f2099888a9e812886f05f30e78ff345a87e82c662873697c414190faf487243ea7a578664fe13b4811646c0d1c8ce48fb9172bc085b71ae210a43ec796197344ffc1a3f46ea28986383bb6b298e9fbd05ec2ba35f8d8f7b433d57eddf0a2b6c9a66f0737ba8123dd7613cf9f728db67b7e0046f867ece09e4c69	\\x0000000100010000
46	4	9	\\x62ce8f3830753c9507fded1c3354986729007fd8e6c69d2eb26797ab388abf84eb572ada5a764aa995771a401bc2450c48b1db7b7cc69b44e709d542c72a3107	422	\\x0000000100000100433cfeb1f33add5d039fcf41b4b966a1f00482cfb3725535dac9633d5d09e7adc2f0d52c09ac0af7a30755a1023469401ac175db1aeffdbb1fc5b37c02c8a45398baffb92ad79e3164a8644ea64e109f9edd5f38f06edb894c4be2c4949c6d8e996b89dcd2c8d5a51ccb20b16e4685af2b62c7f62072a10edebb7901652963d0	\\x0592dee040f98ba3563307385e14e23f7c9bbbb4deeb930748c173b433aa5b68c4db687db3c2a1315ca3a0988bbca698c9b92152db5cad5735059e6d3f1dc86d	\\x000000010000000142e4ca88a19a32edc93c10382a6c1875c4c8f9e94f85a6f0f7399b0c76e4c07b99c876d68a4bd6868ddb7b180b6733d8531902af5e47094854547505467984a0c3646f477a2983ab961b8f2836c7793d3659be60fcfd991f0698923e6733c010c12bb53c5def8c10275e6f5f24bf386178440eb9767e0040ff2dd90a9a8ab9b5	\\x0000000100010000
47	4	10	\\xa8a702413e86ece90d58812f31fda09adc5c4dd977a537d2449887f3876c65016ac53d028da1ecebdd7dc2662eef89699f60318291ed4d00ce8b0ddf2448ed06	422	\\x0000000100000100b7642f124c6aaaaf64f8888e7b3e3e997953cc1b474f41d5d765fec7341a78faaf59f95c71959fc719241f33f2dbc8af308fd49bc2cbae37c6a3e6104b3d975bcd2f5345516a865f89655ca3541ceaedc7c373915e834f35c819432917c8d76f8a2047437758d18cda7cfff79881370202ece7a7c447f217d3b7518f39d3ffe0	\\xab7ac2321c91b88c4ee6b1ebe3dea032123f940e181c39f7583836b32937a6c312a44611b082b6107fcfc6be38eef2fd292451caf630f334f704376bc751df3c	\\x0000000100000001e7e1ad0a13a922531a4c17015c928d35b294c2fb656b1bc99aac544a7182f1e2dd993e46ed7b6f67f6b77bf2fda4bc3d32375746043cbe4b5ab2fc32946d7c62b881e8c4f18012eb8f03c75754e00290eeaee16b2c3fe009587a4f501481ed4c73048104660343522c311bcb70d59663ec1c24dfb4ff21399b4c82fdc6c7bb1c	\\x0000000100010000
48	4	11	\\x7f7295fac0d59766c3427700b18e06ed10b304fa27b9f488a15572eb63a642ad15fc6b269b0394d733e85d4cac33213a9bbecd2bac249b0388c3c0b9260f7e04	422	\\x000000010000010022ad33f9962ab2e8b348e0c6c28e7e9824196a467801f113f1159d38677814cf13317b53ccfe3da7c9d480017fb3fc80230ad2e010c8cf5cbbf41d63dd52c58bd2c4f665608ae9d00c6084f3b3352fe10f52252b17f601a214fd45fa35cad93619454464ab6bc4d965c7357170bf5e1af9f1f7dc69333a33459bdb4a18483ced	\\x4320cc623329724064f9b8de76f7bfa6168bc75117e4166bf8cc68470e69a1c051a9cca61d241a679b7c58f5156dadccd981f8216c77d70cb54df42370fd1c11	\\x000000010000000120a54c8fc8112682d5721c414e42261bd35be956e3985b210c820400ea40b6d5000b3aaf272ecb3580ed41a554748de77aa2f43d3b12532b087f72d9b84bdd45f42d63b75d7070cc26e21a1e4c94ab87f3af9dad202eabd7df7b5591a462dc8b3b31b62016830b52ebe19dc79914f4d39432f11b46bd32b131abce17cff77323	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\xdfe8d8ff09d8cb4624dd818407e8306ade822d467e48e616f1ca3c9e7b650339	\\x50b89e0dbd37a45f78a2daf5af9de2f40df9aa694b30caa34b161befe7e58d21bd110d67ee6c13a4dbcec00ec49825ca0b5ab3c1eea2247ed1ef31b3038be38a
2	2	\\x15303b9a1302dbb9f88a2ac487d8c5cb63f0a82921713a03a150d5700162357a	\\x1f927546f8d0b0fcd4b50d150471ace29d3dc4385ecec9531eeb51a1fee64a16c824fa211c351b6a91dd6d12ad34d89bf8dc0fc19069d75ba1366760a45d1968
3	3	\\x61dbd7e94977b2175a48e82305d3728469298e305df04c2b10ee1f097921647f	\\xb866ce2b3ccbe5804572fb4dcec1adc9afb7c5e569bcb881501b3405b6ff8280f132b20a5ce65b465a9f356413ba6f3a5f2ac7748f38327b8c26352a862899e4
4	4	\\x741952c7c0bacdc55da31cd6a92a15902c45970ac08d491a2c3b1681b0e97a7e	\\xe448a1b3947303f231ac2046b181adf0bc234bfebec234d40e70bb8ee366582dce58b2e338248cf7e93c26654e6551edc4edcbb3e48baca33d986ba80411b46b
\.


--
-- Data for Name: refunds_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds_default (refund_serial_id, coin_pub, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x823c817cfaa33cd6bc286f8daab3c7731b581276c0a1b67b9d45148f4fb112ce	2	\\xef2b5a7addaaca61cb247118d9748e84b96c20422c44fec886d810f6c78585c8163466404c1c8eee0eefe405461112b5881aeca754293dfeec9de7d28f59700f	1	6	0
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
1	\\xc54198a212e8b69f0be91750bff0444ff01661e1662196c639766e61f01b5926	0	1000000	1650802304000000	1869135107000000
2	\\xb49f51e3d6c32f1155c5a4a47f1bc53b9ecc4774ccbe8aaead36627a3e5ac928	0	1000000	1650802312000000	1869135114000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\xc54198a212e8b69f0be91750bff0444ff01661e1662196c639766e61f01b5926	2	10	0	\\xacbae3fd71f533032dfd746e29aaf36db6926ea2630d892ee64e89f5f80dc4d6	exchange-account-1	1648383104000000
2	\\xb49f51e3d6c32f1155c5a4a47f1bc53b9ecc4774ccbe8aaead36627a3e5ac928	4	18	0	\\xaf2ec8bc3f9948d2356d0321bf0c26a3d61801f8db9c14f118abb29693d7d4a6	exchange-account-1	1648383112000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x105c5fdde2ed2764845334dfa45a398636215d698a630b1e97ff73daf74bd43b9737621eadb7a57d8f2160a9a240f863f44580cced9eb1fc220fa5d025e5044e
1	\\xcf11cfbc7fb389af9326425a43babc5fb453143fb840353c3a61a033aa1f611eba8121c666dd821a927171c40684e7b84090a584065788f860b4502db030ebf0
1	\\x0c586787e99b500ca2dd430453ee6b53decfb0d74fc7c40090a3a3721663991e6369f50ea120d85061be75feeb40a8a321674e682f7b27d9a7a1ce340d3121b9
1	\\xc4e08c19f49902923568fd339807da546699a0fc5198a087e69c073287b8c9979947b4e831dc6562882d6705daecf607e0d7988d685d81ba351a037a69e6fb50
1	\\x0d41e0d364472126e8e18551c507ee28fc2efe94060e4b81a6bfbd0c88e6bb0a41933b215637b267778672e4ac4ec89ec1ac404f909ca67d5cad812ae30e45a4
1	\\xd6aae10eabc17bf7ea31b7cb874fe42c22f0aa7e3d1365d17d5f457e499f0b006592264617530d7ed2958c45cbb113f5cdbe276ebaa122020b039112d17f4963
1	\\x9d49d740e00954582373126453c4921b99d7fe3e2b9abf33a5efae15432decd6a41cc55312f35dfa51be4d30b5d287f855d1da1ccdf56cf79f7a14145f87addf
1	\\xef5503715377b9dab643ac45ccc9eb6fecd8712717f47e296ff62105b1f930d7909e18995f7dd7ba0be5f39f58abc9e6c123bb97f89f55baac842c8d495b081b
1	\\x70c32002280637f85469c20abfa6c822b9f505c198192b78cbe0dc98b0175ac8cf7e1f1815a0afdfe260c02bea92fea88beacbf5f366c6b8ab4f40ce7f8797c6
1	\\x57551af8cabfeca53fa7aa4895df382b7d9f0d11cf64034c1ecb18f24468d41822840913b6c85c7e0ec40a81af03bfc073db1cc19008055f549dfc425d5e2b84
1	\\x7167f62fc8932497529d464d6d0f1672ee988037956fe46f62ef11fe137dffed8706c5840e3c71006b416350434ca013e7797cba8b0c23b1e59dc63ef19123f6
1	\\x9d2d662c6550614011ff13de5b948f14f816e7fe3b56b7af777dd8cf82d6a7423e205210c13295c762361cbd624df20bc8669c68ccd56adcc135e9ed2fee17ca
2	\\xa9d0b5cf2be3c334c9a91cc6a1ec0e875239885a128d9d94db21ade8e065d58c8fefbac2f8228ca8f31221444562239af27706a60583978d43f1c54216f20954
2	\\x1b7ce23484aea1109c35a3f16db229f01dc11a8a9968701bcd802c83fcd052c32d52231ca6cca015328edff97b31ea7daff78a7cec5e405102260e22d9824f1c
2	\\x45e76504a7ef07a32a693613fe554ed0c2b9f7b919e7598702f20ec3900966bddf98e0abfc34f47acc379a46ed7af89dcf24e0772ce62037eff5172d254c49f5
2	\\x497db2730a543e219fe2e628a45aca702ca44a315a8035820ee932a7bdadf0a6a391f75bd69371673bace411ae760f9b062fdb97f965347b13fd74a5ffa3acb2
2	\\x4dd85222f4d5f5cd7d736d126f2642822bb18c690187e8bd9be3f51c2b6cb1d422693939aca5d9d7a3e00675c10598e4d6854c04d57aa01314c780a86487d04d
2	\\x3b640d4af67e1be19df5e8a672bab62b22d00a238416864dcca8abc4655eca49c2ccb33d795abd3a0b50637e81e55e634eee58464d8bafb5c667525c18ee960e
2	\\xf44530d5d9b6b988622b12d581ddb1085c4ea2db87c168ebc0a3a1962abccbd6335b704a2ae7f4acfc0c1fb8c8139c164fe0b8838bd52f8aa9ae0ad6afc68eec
2	\\xb97ddca813bfcc59f770ca65d707e4a737fa2f07da862bf91aa8fee9156422be9004f6929f9b3ab22cc1746998d8f27d1124bc955ed821710349faf94eeb2526
2	\\xc9b11f9280f20df90edb320c54df52ba1c74e2d61a086aa8a9181e7358618e2f2fbf5c9f473724e73f8dbd7d8a5f584cf58bdcb34da35e7c2186ec5917e4f591
2	\\xa935cae1b478a760fee4fcbad17650deb70500def8db4d81773ebee07204dda8dc66e0f52f026f5e04bc3e8d1347d5fe956c4465fd0aa545279b53b94fd9c5ba
2	\\xfe35b2a9a35949f7c3f036f8fc007ed7ea5c50a150066ec5356071746cf60223f30bb8b5bd13bacfee9841b0a45e6eb2db8370993d43bb6dc51133672c7e0b97
2	\\xef80669783b97e101bcc3d4d35fc615503357fc1592a72966e3f644632a9be19c0f17504af4d34aa503e99d6865593305b229eb667c95ef99203a9c83e4dea11
2	\\xb4c70c1bd61bf10aac06f6a88591d4ab4452ae16c038fbc777e3fce379792639976b44ef53eb6bc24c7c211a237479586eb8690ca2f6967a51ee1dc28e07fde3
2	\\xa29166d1797a19bfcae077a130cf0f92906b09065fe323aea0127e1f334799fddb6030d9316f803223e73f499a4564d764a40aa38b0d39c9dcb888319e9307bf
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x105c5fdde2ed2764845334dfa45a398636215d698a630b1e97ff73daf74bd43b9737621eadb7a57d8f2160a9a240f863f44580cced9eb1fc220fa5d025e5044e	286	\\x0000000100000001d1f75e91b247cf842277d84a8142451d13c2f94c22f99663c503535f5593f32551567e1f61c3512d9e0a790f1d8af7e5f8d5a4059fa8550e881f22d8a09cf58d0d6493086a87ee85c1f5e33c39883a1c844cea12115e39497ab53d0c21146c6f749525a1feed45f4c2e182819bcd68a438e52361e0b9f5d3665273a63f5be935	1	\\x56102253e5ca7dd35e01c368cc3be948d5f86b37087fd04556f2cdf430f5f146ab0435b7df7d91d9ec2cb8c48c1ecd2b41c1cc78c07268ef00b1377b2ac93d06	1648383107000000	8	5000000
2	\\xcf11cfbc7fb389af9326425a43babc5fb453143fb840353c3a61a033aa1f611eba8121c666dd821a927171c40684e7b84090a584065788f860b4502db030ebf0	193	\\x000000010000000162339e32f6166922b55a0f82c3c77edfb9114b57241c01acaf40bebd8c29c962320f3183fbd926740f7bd979c5fd95d42caac1b7c4479756d0025fc07ab9fb39a8970cb78820d293f26b784a0d19a64182a458bc6ca91d7dfff2b42d2050aa40ed982295ed3de4ca4434da2a8ca637db9cf1698e1955ac7e0ab0aa308effb98e	1	\\x05c791d1e38bbba54094698face85c84ff061a216c8d40c2bf3e06ada71ff8844b7a5deea5cac26c5959c794f06f2cae063ffbccba07125ca9504d76510a6209	1648383107000000	1	2000000
3	\\x0c586787e99b500ca2dd430453ee6b53decfb0d74fc7c40090a3a3721663991e6369f50ea120d85061be75feeb40a8a321674e682f7b27d9a7a1ce340d3121b9	289	\\x00000001000000018bca56506fa919ad70bd98fd247c0c429d667fd09373360eb8be2d1254acd81989cf884c74d1b6181bf8b896bb8196451c1e44337ccfc352bd6c575bc4e1c47ae5d2d8828e7364470d19786b48b03de2e88e4dd85f6176d95f89a6e1f1bd1f5e1543aa30f62640c51773c53b3f547b4e8587f62daf1fda946f60b98419974aec	1	\\x1ccaf49751d5edcd7639f27f79bcdcfe468d2fa2724e5d02b798d8df75edb1dfc3314abd8fa3a372294b6566534d2e103fe52fc926cc5325e4d48d1805c94007	1648383107000000	0	11000000
4	\\xc4e08c19f49902923568fd339807da546699a0fc5198a087e69c073287b8c9979947b4e831dc6562882d6705daecf607e0d7988d685d81ba351a037a69e6fb50	289	\\x00000001000000017a7de9565ce14ced2f641ab42977b26565d66764eb5a8ef4c1700193fe43ae31e79ffc4c8667808818e010b40f4e6d8023a7a38101b74b8e2a01bb83ace3daf9f53b75e459a2bd35ea8f23d20376dc8c7af18dc33fcb53600de8f7adb9351d0fbb3a75f40a8b63e642cc63815b8aa21ba5c5ef79f61133c755ef3d7a894c1b97	1	\\x9798d56b8fe20357e4ab71588ba32614b0e0074316ad74ceaeeb0b0f1b9f718f5dcd88439567e3849052fbc5a4ac57a81a3c7f57296f891dc7cbd0a598a85c03	1648383107000000	0	11000000
5	\\x0d41e0d364472126e8e18551c507ee28fc2efe94060e4b81a6bfbd0c88e6bb0a41933b215637b267778672e4ac4ec89ec1ac404f909ca67d5cad812ae30e45a4	289	\\x0000000100000001b36c653fedef58ce269e7c7fff51746b0cca8066ba0e4d93129340778e8d56b61b3155a6db6daad89381c3e2f1efe688e6ad76dc8508aaf6f1b84f257125f11f29606ed537c25647f19015139a29d7a5b8bd8f526cf67e8d59322218536516391ad5bc12f75fdbc5e7da2693aee889e258927afbd9eeb1840119c932a647a8fa	1	\\xaea9425fe01bc8b1595c53e9feeb88ffc21ddbea7c4336d2316ee8fd39f360abaa3fd7fc9f191340fbed3f14b2f2b960124a030ef6dc8702049632a59ac1ce07	1648383107000000	0	11000000
6	\\xd6aae10eabc17bf7ea31b7cb874fe42c22f0aa7e3d1365d17d5f457e499f0b006592264617530d7ed2958c45cbb113f5cdbe276ebaa122020b039112d17f4963	289	\\x00000001000000018cc5c363e7723a94c08d170503d04bd010c2f2f184833555aa2b0972027db2cfecf54df9a83fda00d2084b17f95e86bd6aeee4ea38fc20ec2af314371299da4f322dac944bf1875a429fef6d2368a74534b13aacec066cf9858871464b675d55abc51e62271809db5a03c9148ea95a5bb98e55e0b68399362b415bb1ba8cee0f	1	\\x5118875b60787344ede388200c9b8e96f7bd8e70b2ff693e3885b22d39b021e9677e2d833f787ffd0dd77e355edd86883b7e51ad8feb3b4930c1307dfff7880b	1648383107000000	0	11000000
7	\\x9d49d740e00954582373126453c4921b99d7fe3e2b9abf33a5efae15432decd6a41cc55312f35dfa51be4d30b5d287f855d1da1ccdf56cf79f7a14145f87addf	289	\\x000000010000000142e3e6697d37dc01f1458eef452ccff83866c354a61ea70bf765c11d999ab75d25cf4bb4c90b304fef71e8ada8ae61928b59b67bb536bbbb6102ba1f62ab76bbcf3916da5d7e4ede7f9fcf06f75a8cc26ba77d02f630f7d3b06faa28ce909bd2a5eeacfcaa8f3fc90aadcf84b58feb95bf2afe6443cb8e35f9eef31b4ad96868	1	\\x2c849b6746e5e719dbec083323dd83865d06522522ba087b29ada29a3e54050ed0d554d1e611219d2825a7df86f21db9d6e40b80e7dfd4473d10eb8fe0749004	1648383107000000	0	11000000
8	\\xef5503715377b9dab643ac45ccc9eb6fecd8712717f47e296ff62105b1f930d7909e18995f7dd7ba0be5f39f58abc9e6c123bb97f89f55baac842c8d495b081b	289	\\x000000010000000114c92b31ce6f269fd7cd8e33a7617f920fe2d05e313f8be31b1afb1a546f092282a97a6be9ae974c88b3acedba3081be72f2f381b12de697efee00c3f5d10f8960f41dfcf2e6bc99f618581af8b415826e47a5d44b06cd6fc6eb7800c98e8629291ef8d850877b13da69bbb105790d3fd49c7ef69ce6e2286ab36f7852160ac8	1	\\x4414ff4b7680b45ba2e80ea42bb87f0b624915c86c1bc118deb3e76b8d883cddae0b5e30bd9858151a4cd73db367cce23ea7b49877a8fccf55b3c03f4a6b1e09	1648383107000000	0	11000000
9	\\x70c32002280637f85469c20abfa6c822b9f505c198192b78cbe0dc98b0175ac8cf7e1f1815a0afdfe260c02bea92fea88beacbf5f366c6b8ab4f40ce7f8797c6	289	\\x0000000100000001629019d4604348fff594428b9245d1ce8074b3212c674abce0482b3eb05b0105185c983fa493e88be9a5b9b2d1b8eb88c7fc016dc0c1208d31ab8c026231492fa2fd8495e0c6c34509a23bb18167b4a2421605076fca48050f36007e778d29dc8e36f603c329c250cc2e8da027ef177a786ca2019260a86f55ffdb58e1a9fa93	1	\\xf348ded582d756a619d968004bb8edd8358035d9d6449eff3a771bea9c0032df42dcba4ab0fcabe08fc54fa826e5faf437c608b0bf7600c80dc0e16fe8a6d706	1648383107000000	0	11000000
10	\\x57551af8cabfeca53fa7aa4895df382b7d9f0d11cf64034c1ecb18f24468d41822840913b6c85c7e0ec40a81af03bfc073db1cc19008055f549dfc425d5e2b84	289	\\x00000001000000013b0fbb79cfa878828ed9997a2ca3ac6ce9d447ed66a8396259609e0fa405a2dccbfe2c056d04186bccb606247c9f3a00dd3f0d03f4ada55f8226e08f71ca9265585dbf1e61b0ab2c21cdb24a62a3a517fcc214416358cb13c893c8aa2631978c1059f303f27352c46927bb3c40619160ceb020a933f16218e3163437054a83ee	1	\\x2208692c53e1aa2ec6f0936659d748f851ab9854dc958e460e2eba303b99d6ac72f0aa93139cd535fcb6d913f3e3e4727048b59e7cc323d3485e3249e7768f0f	1648383107000000	0	11000000
11	\\x7167f62fc8932497529d464d6d0f1672ee988037956fe46f62ef11fe137dffed8706c5840e3c71006b416350434ca013e7797cba8b0c23b1e59dc63ef19123f6	422	\\x0000000100000001b1a084728610ed50ad99c5e62440645e3667ec2d7a57a88ae042e4b17d62436153f8f8b584605ac09afbfbe90f28931d205d5778971906e0520917710d9d6c7650084907e62ef6b32bc229b2a57411e2854bc4aecffec0637978252064461c7865fbebfe486c0e7c75bee0413f4b18ba22bd24750e393c8dfd94a8c6086713cb	1	\\x9eafee84fdf1c5aebfb842478af7c3c1adbdda5d7a05eb011216715843bf07e776bb841ada831d54118a06abec16eed8cb38910cb7c2670e6b25cb037497a302	1648383107000000	0	2000000
12	\\x9d2d662c6550614011ff13de5b948f14f816e7fe3b56b7af777dd8cf82d6a7423e205210c13295c762361cbd624df20bc8669c68ccd56adcc135e9ed2fee17ca	422	\\x000000010000000194aa4b20317f7823b67188f91661723ee65623c1c540789cf47bd320ef6edf243e41626001e74f9d915b4694c27d5738746e44506b0547ded8bf2f528c087ff3416443f2fdd2f13c2f60974f06497e4c83dc4d613c7c851213353d0a335d2794cc9d973daebdc2e8ac784f24d420547182edb58777dcd26f3feb8c81f17e941a	1	\\x3a93aa7bcfeec7203be7a70c76b25745a5021e6ce4650838609ddca31c681763ebf606b4500da407f7cb9ebf6f530dfae1b1c3e5e816e72e7ac1caf10ff8510b	1648383107000000	0	2000000
13	\\xa9d0b5cf2be3c334c9a91cc6a1ec0e875239885a128d9d94db21ade8e065d58c8fefbac2f8228ca8f31221444562239af27706a60583978d43f1c54216f20954	71	\\x000000010000000112ce0302d7aa9534f5f3e5d5ac3bd0862dba8475caafd7450d5b02df31535ccfd867bca7d54deaf1441613a0846ffcfd3399c13d8e5d548418a37e628da9e9c756e7ac53b6d5d2fdadced48cb9ab3accbb919ee6c19a161dae3dbed3d08c456a162ee54a0834c6252ba3a99d9004816415366d506378e291dcf22075aa675c19	2	\\x168b3f0e611a3cce00f1b55c0f63c4be7bc19c5548c25af139a165d732b0bab13b145b8e94c0f44b4b4e9f3dfb3e9a9123194ba190ce28b0cfcd477b79de240d	1648383113000000	10	1000000
14	\\x1b7ce23484aea1109c35a3f16db229f01dc11a8a9968701bcd802c83fcd052c32d52231ca6cca015328edff97b31ea7daff78a7cec5e405102260e22d9824f1c	282	\\x00000001000000010742d57ee535c241d2ba7531fc980db8450dafb0add877d2f8a66fb4369ad032c6c81b1fc8f15f1e57a7723c966207d44e8079a2cf823fb32ad9897ae09d42f9d2de8e696242d0ac72e3756a9713cb5148a075ee099621840ec7cb0a2d0e9289fef45d888f12c6f7659d173c998a7bfef691ce7fffcc09bd9bd71b4d620d0720	2	\\x411952458020ffe2812c3e4c3d26f74d560854ae6e0523b4addfaf7d6583313a01268ff47cd231983f507482b8f4d200c6a3d51910d00b39880d6d50d0b5bf09	1648383113000000	5	1000000
15	\\x45e76504a7ef07a32a693613fe554ed0c2b9f7b919e7598702f20ec3900966bddf98e0abfc34f47acc379a46ed7af89dcf24e0772ce62037eff5172d254c49f5	311	\\x00000001000000018c449dfa56fb0592b15adac8ba0bf019f3b5d63743343abc7aa3960d97bfdc83d51853cc37faf5c63fd51a0032dfb5314281a33dbcdd4ea682a2f2a3c066c9d3b6905efc1c808f43ba4154b0979f1b287d68f4510741f0dd1bd54ac8c65af4a95546b588b59fe41728fddbd7f2ffc941fda1f5ff10b806552268e88386b0bb4f	2	\\x08e0e9210c1feaf6ff37c2a146a862d5cb6d84387e34b324dc80133f3860dfb308f2315edc5f02466cce8e0cd22414926f3c076443bdd0bf505349c8c579ca0f	1648383113000000	2	3000000
16	\\x497db2730a543e219fe2e628a45aca702ca44a315a8035820ee932a7bdadf0a6a391f75bd69371673bace411ae760f9b062fdb97f965347b13fd74a5ffa3acb2	289	\\x0000000100000001992566af4fbd3287256df11e6e02b6873a93c37c57be03efe41f14af38ca7afa4b1cf826c2d0271908325fd9ef4f4ecb0cc3f31c1fb3d688d8bc7424d3378ff865306b954b3e6fe98ac91b434627fadf665dc457a603c34e8a6f0a1009c3bc8fd9c768462eeb3401d0bab1b7cf49a338a504f682ca9fb51d9e4fc6a58564c076	2	\\x0b38e8a842afb402b56fa02bb5057a082b67af104221fa78c7f63ba5f4df480b9f4fc98af37c26702408befbb50f90b92f071f40d22453274f4f9448850c880b	1648383113000000	0	11000000
17	\\x4dd85222f4d5f5cd7d736d126f2642822bb18c690187e8bd9be3f51c2b6cb1d422693939aca5d9d7a3e00675c10598e4d6854c04d57aa01314c780a86487d04d	289	\\x00000001000000012f240fb985817f06a7020fa3dfe50dfb072f6e366a1f96b9d289feb448d39cfc7d01b6b422664aa1eb3b3fc9e1cf45f5f5bca4d0f3028fe61af557e07200553e63d0a40b21864699ffe7649d58dba556947a2b1d71bf929e4390fb7b53a081fe70ffe7d8a5cabd4ba0717c6e0d8ec51097fbd17566702cd0eff97ba3cb612c3c	2	\\xef4ff229772a1a4a7abaa0cd09fe9f8089edb5dfc1ab8a1da0021c698aca1a67a92c7c5df0fe32321b4746a3264411d8552e87306aeea22b895ad8e5c3a4640d	1648383113000000	0	11000000
18	\\x3b640d4af67e1be19df5e8a672bab62b22d00a238416864dcca8abc4655eca49c2ccb33d795abd3a0b50637e81e55e634eee58464d8bafb5c667525c18ee960e	289	\\x0000000100000001a1549ff9f1ad81a5caf7b8260244c0e9f2e69dedc31c3c53f6b8df2a4cc0cefe58ef392ef0c1f909ee0220a183bb63f972c30af760fa054b35cb58e36a05dbf4ebdc2f6282db6b26811aad578dc1edd023e669b96ff8baa8d125b4ffde016672b4ebaf981635bcead91a05f165204e89372e7868f10a4f25ad6617db9675aecf	2	\\x2157cf362386ef861345fb57a465e18ad37fc1ad627c75af32c3faf074ff3a39815a9aa4373e8f0414204d5bf586aa7eb562851d663c2e08a99d4a48c4eb3107	1648383113000000	0	11000000
19	\\xf44530d5d9b6b988622b12d581ddb1085c4ea2db87c168ebc0a3a1962abccbd6335b704a2ae7f4acfc0c1fb8c8139c164fe0b8838bd52f8aa9ae0ad6afc68eec	289	\\x00000001000000012f0a172a0f4d84979a0a21be7f00d9f71251d762d5a7cbb6ace774520f8e04b5eb875b4184ae484193b62c48a47318b0e000680347c92b6c8741b4607deca828d3f0ea2b767841c8acf5b4be7bc8b3a9a53d08e2391ae53ac8bfa0acad80fc4fae9c9d13bc9f95ea14ee1e62260d0790c498f927be3bc969cc41a843137a0aa3	2	\\x6066982f3ec4b603eb8e24c549892bfac15df05aa074226733e51e943bbcc1aa9a4600d2d56442788e89f6a0098ce1707c055fd30886efdd242215bae7a8490c	1648383113000000	0	11000000
20	\\xb97ddca813bfcc59f770ca65d707e4a737fa2f07da862bf91aa8fee9156422be9004f6929f9b3ab22cc1746998d8f27d1124bc955ed821710349faf94eeb2526	289	\\x000000010000000191d2065f9b036eab67bf35db1b56d68749b1043e15cad95c0ef7001b038c52f88124f1a4bb165aed41b678d8a938e546fe02dfd1ca1f75dbfc3b06c7fb20b4604d0cecbf7c51f0450bf47fe0ae0f7ca2ed3d86679daa5716701df8aef0f02a70a2e9490ecf1f29942d850919029bfb96454af4f0928bc1b3c999a0febd13a725	2	\\x0c9e2189c8bc236fb15a181db1f6babf81ebea390d0fbfde813616fa275b4e549a67931af1d0fe04f234b7263646d89497eb8260c706df89646f944f149a4404	1648383113000000	0	11000000
21	\\xc9b11f9280f20df90edb320c54df52ba1c74e2d61a086aa8a9181e7358618e2f2fbf5c9f473724e73f8dbd7d8a5f584cf58bdcb34da35e7c2186ec5917e4f591	289	\\x0000000100000001397b7ab9598d5deae1ed7d8518528ec4988d5bca0fcb62133156ad10cdbe077cc876b5b465c96dc718d533c8079c4bf2190eab84dcdcffb2469d62d5757db16c944e348fd82836b7e98915c323f014eb00c39bd5c5dd9be547c30295eb6ac6a1a8c94c8ff1301184f072622d00acf87911e2177e8b0e464c80b1850dba1f893a	2	\\x4ec830cbedb924dd88be115ffb8d73cb6a8a855150a0b228d4c69ac148c67da445a9d0d6e09d1fee811abd509fc762a5480869f3c10ed9a184ca839e94e56d0e	1648383114000000	0	11000000
22	\\xa935cae1b478a760fee4fcbad17650deb70500def8db4d81773ebee07204dda8dc66e0f52f026f5e04bc3e8d1347d5fe956c4465fd0aa545279b53b94fd9c5ba	289	\\x000000010000000117bca3c568bd12199cfc662d7dc35e4fbc9872330411fdb262d50c9d5f4f700806e708209ddd89e94ee6aba5ab721a6d9375fb9368efcc4edfae9fbee7754dea4d8b83e893171dab329e4a61c4e852a586709bc442a3a4060cf2e974edd673e06391ed684d257b70565392a6de02911248c6911d39805e39029f912c417fe099	2	\\x1576afec8ef635051fb1aaec72ba8de9e01bc272a72a1aed9353bd948b7d2bd5545a8abd8908e7b8112db6e8ebed9c18ff5ee8ba7ea1960c592e86d937bc4f0a	1648383114000000	0	11000000
23	\\xfe35b2a9a35949f7c3f036f8fc007ed7ea5c50a150066ec5356071746cf60223f30bb8b5bd13bacfee9841b0a45e6eb2db8370993d43bb6dc51133672c7e0b97	289	\\x00000001000000015ccfa7c6e57f8d24ba129fbdee3a7b0b99f45cb59482f4ee406394aee9c9728a6923d160d91085ac52d11aecc59c3d5b050bd19156810593b465caf3af4d5241fc1cd24410dc1278e6f3b680a53015bedd61d7afd8036a2f3bfe997a719475d2e938bedb4ec441a8f0c9763ef64e705d621cbe61ef8eee08b0572b3fd2349056	2	\\x67d5566ce565a762d8704f30f714a52ad365ef74e716185cb56de7c227b2ffcb9dc4ac09973a6bbcff674c7bf971f04e9101c8c677a477bbd4fef5e3984a6a08	1648383114000000	0	11000000
24	\\xef80669783b97e101bcc3d4d35fc615503357fc1592a72966e3f644632a9be19c0f17504af4d34aa503e99d6865593305b229eb667c95ef99203a9c83e4dea11	422	\\x0000000100000001d525756731d399000bae46def61b77f0a9e5c33f16dc7c4995cd65825051b796850ffa4cd619038f08bde715f3fe45b3cea8d838b7aeb56bbe795d0c4cb0f581ca23c7819bbce3e9bed6b5870c2486ca5df2714bcd17aa922602d02d5698da9bcf0ea2a93d3f0fd270226849d723bd7f173df06ae00c8646f2f1e362e1581ff8	2	\\x05c620b515d3e24deabf2bd42f49f2b85b783d26be3a39a4663a747ec9315664cd9189393b0ed8cc03d4ef017ef101854d4d5daf2e18d78a33edcf7fc542bf08	1648383114000000	0	2000000
25	\\xb4c70c1bd61bf10aac06f6a88591d4ab4452ae16c038fbc777e3fce379792639976b44ef53eb6bc24c7c211a237479586eb8690ca2f6967a51ee1dc28e07fde3	422	\\x00000001000000019ed44505a4ddd2230176a51338ae025e7c83320d169567ac32b7f91d14e4c545a2cd97d856588f44deca52d073bf6ed798fc4b8f96dfe3d71c69304f0536cd76e33c343c5c1ee802ac09cfdf22d892514ace43cc940cbb41a0082e4f21cccbea3d53223a7b82cc6aa4b1d3e74cf9e4982d6162bc19f1c41972cbe0127720a1be	2	\\x31c5f52ff7b1a05fb23bd943bf68d64f46cddc2e166a0dd4575845286483286e4939170e9569145147a91a28ab66dd3a9e0767ee2339e5ad86e5969c3981f10e	1648383114000000	0	2000000
26	\\xa29166d1797a19bfcae077a130cf0f92906b09065fe323aea0127e1f334799fddb6030d9316f803223e73f499a4564d764a40aa38b0d39c9dcb888319e9307bf	422	\\x0000000100000001168223e7a7eb89072001e9e1aa480bcc2c89d89bccf85ac5f1656b71e808663481a7ef020b5197bd3d3b3542eda5cb7559ba13ec9636921f69b07cfc11c591b66f0fe6c8262bf5dc4cd8ae8398eb09d94930a77b45fcb22057c82b6da899c10b41d4dac59e20bb5250846f40744d38e46c651d1667c0284605fdf709bab5aac5	2	\\x07e546a15150a9310def027d05114cad93380b2a66b20c3d43383bc07228600b17db75fe150b3e204a7b289b0a669abe4ad88caff34025695db1937e5fc8a400	1648383114000000	0	2000000
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
-- Data for Name: wad_in_entries_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wad_in_entries_default (wad_in_entry_serial_id, wad_in_serial_id, reserve_pub, purse_pub, h_contract, purse_expiration, merge_timestamp, amount_with_fee_val, amount_with_fee_frac, wad_fee_val, wad_fee_frac, deposit_fees_val, deposit_fees_frac, reserve_sig, purse_sig) FROM stdin;
\.


--
-- Data for Name: wad_out_entries_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wad_out_entries_default (wad_out_entry_serial_id, wad_out_serial_id, reserve_pub, purse_pub, h_contract, purse_expiration, merge_timestamp, amount_with_fee_val, amount_with_fee_frac, wad_fee_val, wad_fee_frac, deposit_fees_val, deposit_fees_frac, reserve_sig, purse_sig) FROM stdin;
\.


--
-- Data for Name: wads_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wads_in_default (wad_in_serial_id, wad_id, origin_exchange_url, amount_val, amount_frac, arrival_time) FROM stdin;
\.


--
-- Data for Name: wads_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wads_out_default (wad_out_serial_id, wad_id, partner_serial_id, amount_val, amount_frac, execution_time) FROM stdin;
\.


--
-- Data for Name: wire_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_accounts (payto_uri, master_sig, is_active, last_change) FROM stdin;
payto://x-taler-bank/localhost/Exchange	\\xf2a9c33c22621081fc300f8fc0e6a5655fe8555006ebda714fc375b7bdcd898a1ee485453b887c040f38df9db5bac6690b7bdfb3a30a7b3f728dd4d1f0475d0b	t	1648383097000000
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
1	x-taler-bank	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\xa52c37a48cf4bcda753cdeb62b90ec6dde16fe2c00c30450002c2f46f8eca87f1b7ca3f7b54d71ea4e0b87ed3fe62462b69985a0f55a117e8eec3735468f2d0d
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
1	\\xacbae3fd71f533032dfd746e29aaf36db6926ea2630d892ee64e89f5f80dc4d6	payto://x-taler-bank/localhost/testuser-5pnyer1b	f	\N
2	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	payto://x-taler-bank/localhost/43	f	\N
3	\\xaf2ec8bc3f9948d2356d0321bf0c26a3d61801f8db9c14f118abb29693d7d4a6	payto://x-taler-bank/localhost/testuser-t65bdovs	f	\N
\.


--
-- Data for Name: work_shards; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.work_shards (shard_serial_id, last_attempt, start_row, end_row, completed, job_name) FROM stdin;
1	1648383090000000	0	1024	f	wirewatch-exchange-account-1
\.


--
-- Name: account_merges_account_merge_request_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.account_merges_account_merge_request_serial_id_seq', 1, false);


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
-- Name: purse_requests_purse_requests_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.purse_requests_purse_requests_serial_id_seq', 1, false);


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
-- Name: account_merges_default account_merges_default_account_merge_request_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_merges_default
    ADD CONSTRAINT account_merges_default_account_merge_request_serial_id_key UNIQUE (account_merge_request_serial_id);


--
-- Name: account_merges account_merges_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_merges
    ADD CONSTRAINT account_merges_pkey PRIMARY KEY (purse_pub);


--
-- Name: account_merges_default account_merges_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_merges_default
    ADD CONSTRAINT account_merges_default_pkey PRIMARY KEY (purse_pub);


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
-- Name: close_requests_default close_requests_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.close_requests_default
    ADD CONSTRAINT close_requests_default_pkey PRIMARY KEY (reserve_pub, close_timestamp);


--
-- Name: contracts_default contracts_default_contract_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts_default
    ADD CONSTRAINT contracts_default_contract_serial_id_key UNIQUE (contract_serial_id);


--
-- Name: contracts contracts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT contracts_pkey PRIMARY KEY (purse_pub);


--
-- Name: contracts_default contracts_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts_default
    ADD CONSTRAINT contracts_default_pkey PRIMARY KEY (purse_pub);


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
-- Name: extension_details_default extension_details_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.extension_details_default
    ADD CONSTRAINT extension_details_default_pkey PRIMARY KEY (extension_details_serial_id);


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
-- Name: history_requests_default history_requests_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.history_requests_default
    ADD CONSTRAINT history_requests_default_pkey PRIMARY KEY (reserve_pub, request_timestamp);


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
-- Name: purse_deposits_default purse_deposits_default_purse_deposit_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_deposits_default
    ADD CONSTRAINT purse_deposits_default_purse_deposit_serial_id_key UNIQUE (purse_deposit_serial_id);


--
-- Name: purse_merges purse_merges_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_merges
    ADD CONSTRAINT purse_merges_pkey PRIMARY KEY (purse_pub);


--
-- Name: purse_merges_default purse_merges_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_merges_default
    ADD CONSTRAINT purse_merges_default_pkey PRIMARY KEY (purse_pub);


--
-- Name: purse_merges_default purse_merges_default_purse_merge_request_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_merges_default
    ADD CONSTRAINT purse_merges_default_purse_merge_request_serial_id_key UNIQUE (purse_merge_request_serial_id);


--
-- Name: purse_requests purse_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_requests
    ADD CONSTRAINT purse_requests_pkey PRIMARY KEY (purse_pub);


--
-- Name: purse_requests_default purse_requests_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_requests_default
    ADD CONSTRAINT purse_requests_default_pkey PRIMARY KEY (purse_pub);


--
-- Name: purse_requests_default purse_requests_default_purse_requests_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_requests_default
    ADD CONSTRAINT purse_requests_default_purse_requests_serial_id_key UNIQUE (purse_requests_serial_id);


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
-- Name: wad_in_entries_default wad_in_entries_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wad_in_entries_default
    ADD CONSTRAINT wad_in_entries_default_pkey PRIMARY KEY (purse_pub);


--
-- Name: wad_in_entries_default wad_in_entries_default_wad_in_entry_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wad_in_entries_default
    ADD CONSTRAINT wad_in_entries_default_wad_in_entry_serial_id_key UNIQUE (wad_in_entry_serial_id);


--
-- Name: wad_out_entries wad_out_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wad_out_entries
    ADD CONSTRAINT wad_out_entries_pkey PRIMARY KEY (purse_pub);


--
-- Name: wad_out_entries_default wad_out_entries_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wad_out_entries_default
    ADD CONSTRAINT wad_out_entries_default_pkey PRIMARY KEY (purse_pub);


--
-- Name: wad_out_entries_default wad_out_entries_default_wad_out_entry_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wad_out_entries_default
    ADD CONSTRAINT wad_out_entries_default_wad_out_entry_serial_id_key UNIQUE (wad_out_entry_serial_id);


--
-- Name: wads_in wads_in_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wads_in
    ADD CONSTRAINT wads_in_pkey PRIMARY KEY (wad_id);


--
-- Name: wads_in_default wads_in_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wads_in_default
    ADD CONSTRAINT wads_in_default_pkey PRIMARY KEY (wad_id);


--
-- Name: wads_in wads_in_wad_id_origin_exchange_url_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wads_in
    ADD CONSTRAINT wads_in_wad_id_origin_exchange_url_key UNIQUE (wad_id, origin_exchange_url);


--
-- Name: wads_in_default wads_in_default_wad_id_origin_exchange_url_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wads_in_default
    ADD CONSTRAINT wads_in_default_wad_id_origin_exchange_url_key UNIQUE (wad_id, origin_exchange_url);


--
-- Name: wads_in_default wads_in_default_wad_in_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wads_in_default
    ADD CONSTRAINT wads_in_default_wad_in_serial_id_key UNIQUE (wad_in_serial_id);


--
-- Name: wads_out wads_out_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wads_out
    ADD CONSTRAINT wads_out_pkey PRIMARY KEY (wad_id);


--
-- Name: wads_out_default wads_out_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wads_out_default
    ADD CONSTRAINT wads_out_default_pkey PRIMARY KEY (wad_id);


--
-- Name: wads_out_default wads_out_default_wad_out_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wads_out_default
    ADD CONSTRAINT wads_out_default_wad_out_serial_id_key UNIQUE (wad_out_serial_id);


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
-- Name: account_merges_by_reserve_pub; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX account_merges_by_reserve_pub ON ONLY public.account_merges USING btree (reserve_pub);


--
-- Name: account_merges_purse_pub; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX account_merges_purse_pub ON ONLY public.account_merges USING btree (purse_pub);


--
-- Name: INDEX account_merges_purse_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.account_merges_purse_pub IS 'needed when checking for a purse merge status';


--
-- Name: account_merges_default_purse_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX account_merges_default_purse_pub_idx ON public.account_merges_default USING btree (purse_pub);


--
-- Name: account_merges_default_reserve_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX account_merges_default_reserve_pub_idx ON public.account_merges_default USING btree (reserve_pub);


--
-- Name: aggregation_tracking_by_wtid_raw_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX aggregation_tracking_by_wtid_raw_index ON ONLY public.aggregation_tracking USING btree (wtid_raw);


--
-- Name: INDEX aggregation_tracking_by_wtid_raw_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.aggregation_tracking_by_wtid_raw_index IS 'for lookup_transactions';


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
-- Name: deposits_for_matching_main_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_for_matching_main_index ON ONLY public.deposits_for_matching USING btree (refund_deadline, merchant_pub, coin_pub);


--
-- Name: deposits_for_matching_default_refund_deadline_merchant_pub__idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_for_matching_default_refund_deadline_merchant_pub__idx ON public.deposits_for_matching_default USING btree (refund_deadline, merchant_pub, coin_pub);


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
-- Name: purse_deposits_by_coin_pub; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX purse_deposits_by_coin_pub ON ONLY public.purse_deposits USING btree (coin_pub);


--
-- Name: purse_deposits_default_coin_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX purse_deposits_default_coin_pub_idx ON public.purse_deposits_default USING btree (coin_pub);


--
-- Name: purse_merges_purse_pub; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX purse_merges_purse_pub ON ONLY public.purse_merges USING btree (purse_pub);


--
-- Name: purse_merges_default_purse_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX purse_merges_default_purse_pub_idx ON public.purse_merges_default USING btree (purse_pub);


--
-- Name: purse_merges_reserve_pub; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX purse_merges_reserve_pub ON ONLY public.purse_merges USING btree (reserve_pub);


--
-- Name: INDEX purse_merges_reserve_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.purse_merges_reserve_pub IS 'needed in reserve history computation';


--
-- Name: purse_merges_default_reserve_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX purse_merges_default_reserve_pub_idx ON public.purse_merges_default USING btree (reserve_pub);


--
-- Name: purse_requests_merge_pub; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX purse_requests_merge_pub ON ONLY public.purse_requests USING btree (merge_pub);


--
-- Name: purse_requests_default_merge_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX purse_requests_default_merge_pub_idx ON public.purse_requests_default USING btree (merge_pub);


--
-- Name: recoup_by_coin_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_by_coin_pub_index ON ONLY public.recoup USING btree (coin_pub);


--
-- Name: recoup_by_reserve_main_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_by_reserve_main_index ON ONLY public.recoup_by_reserve USING btree (reserve_out_serial_id);


--
-- Name: recoup_by_reserve_default_reserve_out_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_by_reserve_default_reserve_out_serial_id_idx ON public.recoup_by_reserve_default USING btree (reserve_out_serial_id);


--
-- Name: recoup_default_coin_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_default_coin_pub_idx ON public.recoup_default USING btree (coin_pub);


--
-- Name: recoup_refresh_by_coin_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_by_coin_pub_index ON ONLY public.recoup_refresh USING btree (coin_pub);


--
-- Name: recoup_refresh_by_rrc_serial_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_by_rrc_serial_index ON ONLY public.recoup_refresh USING btree (rrc_serial);


--
-- Name: recoup_refresh_default_coin_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_default_coin_pub_idx ON public.recoup_refresh_default USING btree (coin_pub);


--
-- Name: recoup_refresh_default_rrc_serial_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_default_rrc_serial_idx ON public.recoup_refresh_default USING btree (rrc_serial);


--
-- Name: refresh_commitments_by_old_coin_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_commitments_by_old_coin_pub_index ON ONLY public.refresh_commitments USING btree (old_coin_pub);


--
-- Name: refresh_commitments_default_old_coin_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_commitments_default_old_coin_pub_idx ON public.refresh_commitments_default USING btree (old_coin_pub);


--
-- Name: refresh_revealed_coins_by_melt_serial_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_revealed_coins_by_melt_serial_id_index ON ONLY public.refresh_revealed_coins USING btree (melt_serial_id);


--
-- Name: refresh_revealed_coins_default_melt_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_revealed_coins_default_melt_serial_id_idx ON public.refresh_revealed_coins_default USING btree (melt_serial_id);


--
-- Name: refunds_by_coin_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refunds_by_coin_pub_index ON ONLY public.refunds USING btree (coin_pub);


--
-- Name: refunds_default_coin_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refunds_default_coin_pub_idx ON public.refunds_default USING btree (coin_pub);


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

CREATE INDEX wad_in_entries_reserve_pub ON ONLY public.wad_in_entries USING btree (reserve_pub);


--
-- Name: INDEX wad_in_entries_reserve_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.wad_in_entries_reserve_pub IS 'needed to compute reserve history';


--
-- Name: wad_in_entries_default_reserve_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wad_in_entries_default_reserve_pub_idx ON public.wad_in_entries_default USING btree (reserve_pub);


--
-- Name: wad_out_entries_index_by_reserve_pub; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wad_out_entries_index_by_reserve_pub ON ONLY public.wad_out_entries USING btree (reserve_pub);


--
-- Name: wad_out_entries_default_reserve_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wad_out_entries_default_reserve_pub_idx ON public.wad_out_entries_default USING btree (reserve_pub);


--
-- Name: wads_out_index_by_wad_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wads_out_index_by_wad_id ON ONLY public.wads_out USING btree (wad_id);


--
-- Name: wads_out_default_wad_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wads_out_default_wad_id_idx ON public.wads_out_default USING btree (wad_id);


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
-- Name: account_merges_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.account_merges_pkey ATTACH PARTITION public.account_merges_default_pkey;


--
-- Name: account_merges_default_purse_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.account_merges_purse_pub ATTACH PARTITION public.account_merges_default_purse_pub_idx;


--
-- Name: account_merges_default_reserve_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.account_merges_by_reserve_pub ATTACH PARTITION public.account_merges_default_reserve_pub_idx;


--
-- Name: aggregation_tracking_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.aggregation_tracking_pkey ATTACH PARTITION public.aggregation_tracking_default_pkey;


--
-- Name: aggregation_tracking_default_wtid_raw_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.aggregation_tracking_by_wtid_raw_index ATTACH PARTITION public.aggregation_tracking_default_wtid_raw_idx;


--
-- Name: close_requests_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.close_requests_pkey ATTACH PARTITION public.close_requests_default_pkey;


--
-- Name: contracts_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.contracts_pkey ATTACH PARTITION public.contracts_default_pkey;


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
-- Name: deposits_for_matching_default_refund_deadline_merchant_pub__idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.deposits_for_matching_main_index ATTACH PARTITION public.deposits_for_matching_default_refund_deadline_merchant_pub__idx;


--
-- Name: extension_details_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.extension_details_pkey ATTACH PARTITION public.extension_details_default_pkey;


--
-- Name: history_requests_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.history_requests_pkey ATTACH PARTITION public.history_requests_default_pkey;


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
-- Name: purse_deposits_default_coin_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.purse_deposits_by_coin_pub ATTACH PARTITION public.purse_deposits_default_coin_pub_idx;


--
-- Name: purse_merges_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.purse_merges_pkey ATTACH PARTITION public.purse_merges_default_pkey;


--
-- Name: purse_merges_default_purse_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.purse_merges_purse_pub ATTACH PARTITION public.purse_merges_default_purse_pub_idx;


--
-- Name: purse_merges_default_reserve_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.purse_merges_reserve_pub ATTACH PARTITION public.purse_merges_default_reserve_pub_idx;


--
-- Name: purse_requests_default_merge_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.purse_requests_merge_pub ATTACH PARTITION public.purse_requests_default_merge_pub_idx;


--
-- Name: purse_requests_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.purse_requests_pkey ATTACH PARTITION public.purse_requests_default_pkey;


--
-- Name: recoup_by_reserve_default_reserve_out_serial_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.recoup_by_reserve_main_index ATTACH PARTITION public.recoup_by_reserve_default_reserve_out_serial_id_idx;


--
-- Name: recoup_default_coin_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.recoup_by_coin_pub_index ATTACH PARTITION public.recoup_default_coin_pub_idx;


--
-- Name: recoup_refresh_default_coin_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.recoup_refresh_by_coin_pub_index ATTACH PARTITION public.recoup_refresh_default_coin_pub_idx;


--
-- Name: recoup_refresh_default_rrc_serial_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.recoup_refresh_by_rrc_serial_index ATTACH PARTITION public.recoup_refresh_default_rrc_serial_idx;


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
-- Name: refresh_transfer_keys_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.refresh_transfer_keys_pkey ATTACH PARTITION public.refresh_transfer_keys_default_pkey;


--
-- Name: refunds_default_coin_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.refunds_by_coin_pub_index ATTACH PARTITION public.refunds_default_coin_pub_idx;


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
-- Name: wad_in_entries_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wad_in_entries_pkey ATTACH PARTITION public.wad_in_entries_default_pkey;


--
-- Name: wad_in_entries_default_reserve_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wad_in_entries_reserve_pub ATTACH PARTITION public.wad_in_entries_default_reserve_pub_idx;


--
-- Name: wad_out_entries_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wad_out_entries_pkey ATTACH PARTITION public.wad_out_entries_default_pkey;


--
-- Name: wad_out_entries_default_reserve_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wad_out_entries_index_by_reserve_pub ATTACH PARTITION public.wad_out_entries_default_reserve_pub_idx;


--
-- Name: wads_in_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wads_in_pkey ATTACH PARTITION public.wads_in_default_pkey;


--
-- Name: wads_in_default_wad_id_origin_exchange_url_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wads_in_wad_id_origin_exchange_url_key ATTACH PARTITION public.wads_in_default_wad_id_origin_exchange_url_key;


--
-- Name: wads_out_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wads_out_pkey ATTACH PARTITION public.wads_out_default_pkey;


--
-- Name: wads_out_default_wad_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wads_out_index_by_wad_id ATTACH PARTITION public.wads_out_default_wad_id_idx;


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
-- Name: wire_out wire_out_on_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER wire_out_on_delete AFTER DELETE ON public.wire_out FOR EACH ROW EXECUTE FUNCTION public.wire_out_delete_trigger();


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

ALTER TABLE public.close_requests
    ADD CONSTRAINT close_requests_reserve_pub_fkey FOREIGN KEY (reserve_pub) REFERENCES public.reserves(reserve_pub) ON DELETE CASCADE;


--
-- Name: denomination_revocations denomination_revocations_denominations_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denomination_revocations
    ADD CONSTRAINT denomination_revocations_denominations_serial_fkey FOREIGN KEY (denominations_serial) REFERENCES public.denominations(denominations_serial) ON DELETE CASCADE;


--
-- Name: deposits_by_ready deposits_by_ready_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.deposits_by_ready
    ADD CONSTRAINT deposits_by_ready_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub) ON DELETE CASCADE;


--
-- Name: deposits deposits_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.deposits
    ADD CONSTRAINT deposits_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub) ON DELETE CASCADE;


--
-- Name: deposits deposits_extension_details_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.deposits
    ADD CONSTRAINT deposits_extension_details_serial_id_fkey FOREIGN KEY (extension_details_serial_id) REFERENCES public.extension_details(extension_details_serial_id) ON DELETE CASCADE;


--
-- Name: deposits_for_matching deposits_for_matching_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.deposits_for_matching
    ADD CONSTRAINT deposits_for_matching_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub) ON DELETE CASCADE;


--
-- Name: history_requests history_requests_reserve_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.history_requests
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

ALTER TABLE public.purse_deposits
    ADD CONSTRAINT purse_deposits_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub) ON DELETE CASCADE;


--
-- Name: purse_deposits purse_deposits_partner_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.purse_deposits
    ADD CONSTRAINT purse_deposits_partner_serial_id_fkey FOREIGN KEY (partner_serial_id) REFERENCES public.partners(partner_serial_id) ON DELETE CASCADE;


--
-- Name: purse_merges purse_merges_partner_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.purse_merges
    ADD CONSTRAINT purse_merges_partner_serial_id_fkey FOREIGN KEY (partner_serial_id) REFERENCES public.partners(partner_serial_id) ON DELETE CASCADE;


--
-- Name: recoup_by_reserve recoup_by_reserve_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.recoup_by_reserve
    ADD CONSTRAINT recoup_by_reserve_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub);


--
-- Name: recoup recoup_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.recoup
    ADD CONSTRAINT recoup_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub);


--
-- Name: recoup_refresh recoup_refresh_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.recoup_refresh
    ADD CONSTRAINT recoup_refresh_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub);


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
-- Name: refunds refunds_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.refunds
    ADD CONSTRAINT refunds_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub) ON DELETE CASCADE;


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
-- Name: wads_out wads_out_partner_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.wads_out
    ADD CONSTRAINT wads_out_partner_serial_id_fkey FOREIGN KEY (partner_serial_id) REFERENCES public.partners(partner_serial_id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

