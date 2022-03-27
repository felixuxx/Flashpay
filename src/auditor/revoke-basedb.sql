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
exchange-0001	2022-03-27 14:16:30.349377+02	grothoff	{}	{}
merchant-0001	2022-03-27 14:16:32.194639+02	grothoff	{}	{}
auditor-0001	2022-03-27 14:16:32.95522+02	grothoff	{}	{}
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
t	1	-TESTKUDOS:100	1
f	12	+TESTKUDOS:92	12
t	2	+TESTKUDOS:8	2
\.


--
-- Data for Name: app_banktransaction; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_banktransaction (id, amount, subject, date, cancelled, request_uid, credit_account_id, debit_account_id) FROM stdin;
1	TESTKUDOS:100	Joining bonus	2022-03-27 14:16:43.360786+02	f	e56b89b1-8a6c-4e58-b6e5-205293316c4f	12	1
2	TESTKUDOS:8	847W6D02XW48F6FQ55S2DCY5XP1E13A0JEZNDE1Q80G5EMBTSDAG	2022-03-27 14:16:47.16805+02	f	f6234761-cea8-44a5-8144-1e8a4882d216	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
a5ebaf4f-7e01-40cd-9afe-20ff25b6facc	TESTKUDOS:8	t	t	f	847W6D02XW48F6FQ55S2DCY5XP1E13A0JEZNDE1Q80G5EMBTSDAG	2	12
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
1	1	114	\\xb92915f13573029441240e20664a503eff04b2a11e0b2806a931ad51c36fd98d7eee4f698b23c8b8556909f03cc609d58f5e0f29c7dd6c2470a0b63a32a43d05
2	1	273	\\xd26f46f038ab1c75d4d6c5e51a0a6bed567892160313f419c2c72f8a0cb8dc649471999194b3044bc099ee0e34392ab9d3d1e6b4084082312d9b9b49b29dd50b
3	1	129	\\xe13ce681c56a6077859456b01b0fd88d0b7e111f0ea41c693718818a08b354ae1bfae8ea9850667ae9ea8c07a6ce1eb585151d7874bcb9bf44527cd3d531690d
4	1	231	\\x7fa4f02f1fb4cb6ee3fff412410ce1a3ea7bde3fd6f52c240f241e110c52b7fac17c4e7905e7a39b8e714e10ab0371e5979d298d780d2441135f605e95e92b05
5	1	135	\\x1079b88d22107dcd4aba8cf5237c8d6046590f2ede322d0f8aa133f77bd1a010d92930e442371c5de018b05586ef109e423ac6e92d37c642eb0b8aa2ff855e01
6	1	158	\\x7bf882b467a564285949c0fcd0928ced1a0d0cb6ed67c2cc9c0be31eb07a919b15ef1f6343614c6435e9317f03c744e7fb4bb9854a160e7471d3645eb8939403
7	1	370	\\x8e86ed5f339ec637736f86c6f8dc21c2547760fd24d10e88fec564e7127980efbe092f728abadff4ce50fc66de86c6eb239e898547e485f7da661a3cfff7e303
8	1	378	\\x5bfdc81950a3aead23b0fa5e42bf2cdf35e4cc08fab202e1e126f85ada5fe583ae4c7ce84e38a621a342215f6372fd50f53a662a25ba7a6fc47aff6326151b0d
9	1	280	\\x22830d50d0a23ed80791a1b63a553f54a4a73b2fd6dbbd69a471b0e84afd996a93297f74ba6abc0e939f654a96ddbcce214a5b43e317e95836887d87cf1c7a0f
10	1	178	\\x7f13cec1e23db44ce6db7d3f58a378b919278861e519c8f14ba9b25007fe7df0471d4861907f3696cd101656cf98337830197504f39aa3b40232ce592d8bbc04
11	1	127	\\xf23265e1c0ca4a2e5082936b6046a07f2d3db62d45aa1d880c2ecf09025c3f720528fdbfa3ac142d9649c26c7c60aa43ce038dc60cf944612d5d01b78f2abe03
12	1	312	\\x51bece8868fb60854073a852b70fd45b2950e622912a6b1e2406d04cddd445186563b779d871777ddb3bfc1d2ddf963a466bc05cdecb913c56e5802c2da74203
13	1	2	\\xcf7cd16a7c6a5cf7739b6d4662349b991c584ad5f2d6d3a829a1c76e7d2edb0b4c20b0a90c640172b95ae9d016f3b67a6efbe8a24fdf03a889180ece66cbe401
14	1	39	\\x5a294352dc772a52def62102a29b9c9e5e1a5d1892264fa8d90f6fefc52bba9f5fd45417088690a1ba6e4dfc4daab034ea950de40865d2f2fa599ed678fa7908
15	1	82	\\xb29528b0aa3e29136d8acb700e97a42f6aaae119c1ed1c6127319c588e9845210dcd6e2300a4d02d45ea649b42292639dfbef65a0ab81f54d14679467eb9c10c
16	1	67	\\x397a6a82b2bc8a37789d94635a36d12254da1f6a032d0f8a3651fa7c3bdf936b029cd69a5f9043927721d2f3bcfaf3cbf107f2e3d34c01481919a86b62762606
17	1	77	\\xe1f407677d7929c4fe347f5e33d8a0e9d71ba87a4f9e96ca20778dc52576d71f320534776be7894288be436566635ccfaa2ee3f4cbaa3a5002b33e9c0feb7d04
18	1	140	\\xf90272e1bd4e2628cc7a155bc1c329f9f9952c194566cc8ce4ad999aa36c773901e6ffcc9c0f10ba0f6724fdf6cb930d3ce1c73001c00f3bfa8d7c6e7c82510e
19	1	95	\\x2709b7b09826d2ae0c48b57f6a556a9b9d322187f5474c1948f8bbe00083bd086789ef8a38261efac98d4b8bf6847bea695b7ea850f693a6307cc8f53e5fbb07
20	1	262	\\xbea20bf450be6f232d6229abe99b6667fad45d7aa5867ef1b5add511b802030908183ff20e019d1be70feb1df172e15bd4d4a66076d387bfb091f666f29f4f0b
21	1	69	\\xea125fdaea87c1df9a8afb4bb9ac1f8fbe985d4466f1cac4a0592206adc02da490b8c9cf8aabac2be2f7a5bfadb2afefb3dffecff9af8ce25f8a53157215be09
22	1	173	\\xa26fe527d7c52e8d063b03b921dd36215d581a8ee73fed577f46d7aa65d12526459c922f9a85af3de5c41764a68ed0be7bcbda361ba49a2d8112454ad6f64a07
23	1	79	\\x47bf538abcd68369a75132b5edb7a05238afee8d4b3906faba3ba885967fbbaa00f24f3d2a770a553cac258f2c4bfa8984f02932cc95c708e65da2d18445fe01
24	1	290	\\xbb9165c29df581dc59fc55a19f348c1e63c917032a28ed9cf17ed2a8e8d2a31784dfe98c7deb9d2ca1476e079623f60c3642722c446e230c05759982886e9802
25	1	296	\\x04336b8d7a1e90031c4904523a536f038408fdc453a783d5271de11f675e39eede7e908a8e0a663dd566e661bbbc1f0c0898d8c213fb00928968456ab0f74307
26	1	284	\\xd9f58eac9413401d4634ad26a43fa4dd9ea723d183f78e4214d70444d3d24fdf0662433e536ee42b8d4c9e69b8e816707d42c480f561efd74f48dbeb6669540d
27	1	410	\\x1c3143dbb5e44272deb9d3c9b108f993b72dfaf17ae05a8dba2b2a3dea816685c6b5c16cb242036f1a8892c9253cbb9584fd26f54a92d7c360b2a2ba67129b0c
28	1	10	\\x1e845831154d6898f8fba60f51438785af38d01b4cff06dcc10183e93632aafa8c41ad8760291e17cea20cd50a4cf9598bad75c487afcec6048ff12839608f0b
29	1	302	\\xdcb6a94fdfed75bc42857d2b884c6844ffed9bd4fb109d2903cd5d4e2a5089ed3aa761cacc95ca2e86990d8cc78f4469d9785cf43ae86e1ca45feee64e8d6500
30	1	366	\\xb959bd2ce9ea86ad41fc8499a5e6e9674e2153d59d58091ce3380cd6b8338d9605b89a87f3cdc001a6561c00cf75dcaa9e7ecbc082db40e2a2f1a81cd66a9300
31	1	24	\\x80011115b19ca3e5526d36cf303de3fed68c043c34d7836482d58fe395a2ffe9e7f4e052b78ed232db97595483bf8d9d5ff7409a4d0e23fd0344e5aada2ac50e
32	1	49	\\x7c9ebadaa37e5f7c812e428ea756cb4e4f95577edc24b9f5d594eede06de9623866439707e835a529f6f5dd0588389e7a9633478edacb8a5a89945981733d302
33	1	246	\\xe316f69e910e2f1289282f2f38fa2444b316e424b4d9d519225ace92277cf340bcb133cbc056329a43a220ad6986e412a453584111451552c643914b2c205507
34	1	75	\\x1dde10a10c6cb94589aee9e61ed0cd96c821ee8e355b028423c1d105c6bef4032692a78e0abe45cc52070eb34685d8ce6985525a9d5f6192dacd8be0d55c4205
35	1	117	\\x36a8969d86b74d29e783d5c3cb23699e7d5ba30334824f4717cf75955bb6b84d2f7ac65b6a819fe856c6ab02b95599ba4a76910d8a4c6a5c2dd98165fbbd8e08
36	1	418	\\x46238d24214359b0a0f9c809df4d2c04ddb8f45e6ccab4b7f935c077a5c1bd9493bb608d7e982267cee563b12f82739416bca10fb48306d548417dbe305c9b08
37	1	365	\\x7dcad8333b3f29194f14d44d31e3e88a473101041726b5d62f20c64e6a9e268b937fd51e6f9ecad27f64d0fc8958cc4452be176cafa2baa425bb70f34d6e4e04
38	1	182	\\x888e5df0ddc01255d7171ecccdf8e67ed7be44c8c5f67b6c76bb42ec65b7616cf36198a0e407ce49232c19cd226b9a3758954d57c97db002498765ddc2e1f60c
39	1	72	\\xe03553b8cd70d67f170c21e2f0a2b7760d39efefa6025759aa58389fafb352a8d44c234e351dbc798fc2c8a044be9c6a40cc5248678ee076af97444a20aabf0d
40	1	398	\\xed982b84834ffe09b43dcb9b63609b84572a72191b698f02d617e4d7e0dc09afc40aeb451d330ebfd1c5fe96eb7e55fcb415617a8ca667d4a7141cfa19e04e00
41	1	382	\\xb281978dabdfdf78487be2f76d37946af0f5d99e197b6f8aa89129f49b883cdf6415e2e88b556b4ceb89b1f6994c1146c881dac0708dd06018e5ffd3f009bf0a
42	1	212	\\x177029b2f209601874cf1fa94ff9044b9958ff10f8cdfd0c44b2a85d4db08b08233da802a9b1210cc3abc79c5d2d3b955336d27bf0d375ae27b3d6a782560a0b
43	1	320	\\x383df6f4bcbaf301bdf8c4ca461a621c6d5243f2ce234352db44132e4daa6d8b267ac8f8a6bb997ed5e8e5f9a866ff68e193bd05a60b42eba7fd8c2b370ab201
44	1	23	\\x91662d6ad2a312e6d1b998d75409dfa8fd56554a59260cabd86cc40ea103f7f11394f4bf4496347926791ff793b7c9c81510e9aeb49249a32ead141c94ddb20e
45	1	228	\\x2b1672d412bf34393be540ead86a8e2161d4b4b47bd2fd27dfd1f72d1e0a39a7eb20f3af56d81fea4d492bb525ea9ba3462fca115f4002f5f41dc923d0394a0b
46	1	334	\\xa5bbaa9086444fd3d9cb377b0b6b25280707357cdf021cc438b1c5d02b39ca2651744a35654dac801ed7437033203347b639865f2a0929313ea76cce13218305
47	1	240	\\x4146d409752ef92088ae22588c8955c3102760383aeebd16556514136334f5249e84d35201662d07c39a22d72a9731f5540ca3ca68e0625523d74b05e3179f02
48	1	230	\\xd439b52f1d1618aa971304daa5557e43cdd265b2ef0b974e5f7fff9df0e37b39d5dedf5d7b4c2d98214ae2d0e06da29cd56bdf3099278e4bb59869b0cb4c6c06
49	1	414	\\x694755991be8b931f275cc06b2eb91228754822267e8a5b219f4aaec07a2bb1b291423b0f8c5f8a51dfcaf735bf901def1ff549a81c08b57b8fb2a23e0297403
50	1	394	\\x85346d693223c62d4f8dd9405406bb151fccdcbf34a8c581ac45157b3291f232e913dc0ef1be818ec252df300e462d9fc38acb0d54b4ae22609b51cc09676302
51	1	190	\\xa3d84631bfa6b243577dfa8d8e7a3617b368b93feefffecce6b29333c0de462bad54ca628f7ad5d7e810e00e11a93582c4d0c0b56dcd4bbd44d6f63297b85709
52	1	372	\\xf2ac96a627057198a3a933c77b19904c2827d8d3a6a542b1c0160f96804db513d4c8dfd083e0729584dc7279682e186e38476385d945cb2da8be898290052806
53	1	222	\\xd906c2d51ddaac036878e017b5baadcce384e59ebe78dd5b994f657eef5513415d52cd391a200dba7abf1d130876cc47ca27ae7bdac69bda187ae00422bb040d
54	1	91	\\x6f759cea806502cbcd050298aedfd0e7bc76593adee36d2efd5bb79c725dba865b62ff87d3b6839a74f702f7a8063a8fe10705f481deba10187bd66f8687a30e
55	1	31	\\xea2ec0f559a9b6fb0ad37d631b3de4dccbe450715e8a66c48eefa92d56fac55f968547d771e069ae2d93ca98204139a6e24b280751dc973dbd0c94324043f10b
56	1	220	\\xa7797765034d11bb0cd6f450281da38be227296c53f89006fbbc46b492a1b3d2b2a77f9b3d5aca258f51ce4d41b2ba5da6be40b5fa7f8896794b4ca50951f105
57	1	255	\\x35a20d87b2b2882fb70eb853f15a8a6510efd6a881cf7d76ae3faf0daae2f1f6d004b44649cb463beda125d0cd1fa9a5a8bc62dbdc5267b38023766acf9cff00
58	1	59	\\x938ba769c3674049e49d6810e1f0f5ca5be25695149880aeb27cf43a3c6edc710f83803badf99145b8ffa1c911ea0f65d55381ce33bad205fa9bfa90e4f31907
59	1	209	\\xe7ce93d471fcfc5fc5d6d3e259bbd5a0b98c05d3dbe76457cd1b7cd430845908c287c4dec516952fc6791ebc9909153b3ab5bbdb8b0c62291a915d07a762800c
60	1	118	\\x7cfa2601c290fd08d3ec8f8be202bd89c0756c1934417ef1c344ad6abdc8e90acc128a7d5bfb9950836929bf89afef4cbc39aa1e64fdb0fe06831249649b540c
61	1	115	\\x3fe97b2d7f8a215f79210c5474f72a64141351e033902c6b03a614389b86018c665b0c9d096d05153c5627c4ed4abd8515edc80d213b9ae107102dabcf88840d
62	1	289	\\x4e92cbc3cf9f0e4989c62510c50fbd29106d57e6b472f436934049650fab030e62aa4f0523c87d6a7d80a8122572a1407c3f5da6c2cdde59a8563bf98f138608
63	1	380	\\x49e93a774c8b1347beafe7d9bcd082a11a601779853df76726b745ca01898efae435e027be73680cd904bf22128a9b43618a4aa329bfa2c1c24b083dab4f9908
64	1	22	\\xcb3dfdc3ddb9dcbfe14b89d3c0f1c261e921a1e0eb242f4c9ca5ebf434b97f4fab89f4f46106ad889afdad8bde9de2de3beb7120679c1f6a81b8d67ce4160e0f
65	1	287	\\x5f30ace7eb18015d3a19da36c7559a82187176b90e7bba2464d5405a95e746742068284c7553253ff5c8c708829471400405acc2137ad8b1d2995c7751d0e700
66	1	305	\\x4cd6951fe5e3ea1a82d736ce70790acffc46311d64584137916ed69c7b45d24409167f4ba855a051de5dfd4f8b9b97898c886f952082758eb3632eb56c845d03
67	1	43	\\x8b6ee6dffa3f77632a5647b904216ca34174026f1e5df2f753a956ab8de1fbe262fd8145164e5cfe1ecd1dc873b68556fafd5998be6b6e9d1755435ac75a6500
68	1	193	\\x96d7339bf36d0062319374c18a001e2d58da911281fa732601e03ca4cf6d1480ec03bda7474215dc47765f11802990f4fe23f8a5a5e5e17930c98aac60f26e08
69	1	300	\\xf6c55df761bf162bfd7fb43a62cec1a12c6833e1dd0a722729a12d0c7bfaa80caa6dc2e325e4ebfc9758174ba837b4a6b52eebdc4f1e504ec597d710f554b309
70	1	110	\\x586f6f10e4dcc9c73c5f7e8dd842ec494661c9d942872caebfaedbcbbeb9cfa9750e793b6e789feaf01bdff3eb4ccc9471bca2b10e52b526db3e2e331eb25e03
71	1	384	\\x336682ca793d989caad692580e0e3a7abd1a6397ca4b0de092ff385429f16d5475eae3473d86e531a5db96cc89445d11245e42f9325eeeeb55c0a3a74095750a
72	1	217	\\x727237cd0f55848466e9f1d7456cc570b2525a35ce9a6147576b5d28cfa9a069cb19a52c60a115e0910fb1cff7c0af91aa92c579a42370f1ea541ceed655b402
73	1	106	\\x4d1aa629f67dab4a11ad8fca0976f0a8719a7a76ed5818d1d86ece7c3bfeed0ea4b3bb6730093554d2b57460f643006163faa3e4b6fc5f06da84f006cd780f02
74	1	261	\\xea0d314afd479daf3da79d9b358465fe2a6e12b745aac09e8461f414d85933cd6be5b851c75deb22668d88cc0d1dbcac2ac71389c617466df89a2858eebf8205
75	1	283	\\xb845729f5e1c8970c9fea1b1802b3d0e3e8bcb628b42fa93b919a444d2597f530e753b488da4210dd2938d419025526f1eb5357a0de02f93ae76cb5b4695d509
76	1	111	\\x846c33fa8247587e9007adc5c9a7e7261470bd2f503677f38177b2c4a7309f3b048924b43311c71978ac19bb6eeadbc9a923da5a08fa89b1905bff45db6d5d01
77	1	21	\\x69522e74c46a71ae39c7557e8f00654a496a34a51af64f1c4f0c5c19d84d7eaf9f488849cea7ef91d84ce3928e041e842523f2891af25e3df685c485a69a950b
78	1	177	\\x780d54e39169c01427b629fead615fb87b6e2d89fdd8ec10b56cf165a4dea08741134886131357c71fbfdc04630f80ee6b810a489a24a2c4d25a178180b16507
79	1	42	\\x41e03bb967726379b7b2469440155a92bfef9e096a07783ae929399538bc4dc8bd39bfcd975842d5ac09fd63b50491fb5ad070634d149c6bf5d91ff3b27c3c09
80	1	165	\\x19c8f733ebef0522d551721bbcf7cac3f042342207753db1f495e929b88e265b30197c305abcab08af22ea5cbdd5f30440602d045194a8d523d45d037def6f00
81	1	86	\\x4a1e829793f2db7ee80052f1557827581d4f295fdd1d8bb4f76880e3d71f30e8c69db772f19fae685a5ba28b3f749d2d653328543b70bf7f29f0302227941d06
82	1	104	\\x0b99a1680ed5a83c395463a1d6da35d7cd643146214f6185871bb0d68e152f4ca6a9f02a80e15e6f6ea169699bd0208f608d7251e654abfb0d922eeaac1ea808
83	1	221	\\x4a0348034d817b851a30312540291d74d2b6dbe1fa50c182b4455a53731abe5b92cef444521e573e75b493867ca37f398c2ad2f548abec68dce4e236ca17fa09
84	1	12	\\x8476d0aa0a42e38c578d9214ba82d8efea51ef8af43e637f3c0bcc41d2b9ce67356fe195206cb16ca64c26e1a45d08359b46fccebd6da16e63fa5f0d71f1680a
85	1	354	\\x1811d8d341f57d67c6bb479efda1c63b5a393f9e9035a4679a6f9cc2eb63e4477a25e4327859508ef1fcf51d6f9b15059e37d22c90a7b9079211a78cc97ac701
86	1	383	\\x025a180448aaccb870a966fb1ee34d7fd98b37facb897fb1aa905e06ae06c40431c86f278e715f619b95384dc29aa4607120b1778d076bc17b8aa8ab37fecb0b
87	1	292	\\x96e875216c902840668629bde1fd686fe972211a6006befa073c10bc02644f66f375ce31d8e989477c73364061385aad60190dde7acdaaf06034298667c54f0a
88	1	28	\\x3918ecc0b3658ec908b9a0bdbd41deb1645aee702171ded3d6214a80fe8c924cd0a6f9013176da5cf3b1aa18e91c599779b04ade8c80f4bfc8154b222bc62c01
89	1	132	\\x1abb12d9de228bc6ac81cae2da79c05a63989a20d54682ef74b9524d7cd1cb9d60222ce7804898ddd4b8e28c2904f7cc689256646f9f0dd88663f4fb8a385508
90	1	247	\\xcf10419cb16fa511ee22af8e15319b2ba6b43e9f24aeedeba4e3639b3cf277fad03c0de60d5a4118350186d5997d9b094976a9a0b8f60844624a2afbb546040b
91	1	70	\\xd2013cd8824958beceebe0278d9ce1309ea52461a9e2274fbd43f72ab4f4567c72249370e7b5ba51737bceb66fbe9d094bf2bb2d874b5885ede30d7aab219504
92	1	175	\\xf9c27e63321b848e121480a527e1369f3be87065fc62bae6250ff04b02d5f306c287fc3a0f7ec361dff7519f7ea12a1f1f0327855aacd8f491eb5a843026300a
93	1	41	\\xf8524503cd4d2e7e5681c2d23deab3651ad1b306cf4476eb7b75af627e387082cd6fb31a7dc1bdc1544eca2c2eb3d6f2d6599014b1a6f341510b63e23e366204
94	1	379	\\x3c9db77577f09bab413456007b3ffe5375127c0a04ae0694800cace0bd1e61b35b5e5562b352dec7bad8ba4311f33c1ca901e80f71a9409c581a4bc2e742e004
95	1	29	\\x43c5f7fa410d27517de3a7f58a2fcdfcc26fc5df38675a03e25bc9a040cc71ec8ec00422c0a1fc0bd432e83b2663949b6de9177e0e152d5e09b6b668ec33ed01
96	1	263	\\xa81dd9a77b87ec6016cda4b1847c5d90a6f781e2fc08a296115332a795786fd36bc6485caa80adee37a09c694758ddc82644a15513e593a15936c514c3e6ae04
97	1	376	\\xee2643fcf86ec7972a15430c55243fb53d90a59821f0fb65e98db05fa74161cef3aca8b00aefde085d322aeed163cbf93afe1eb12977876af7afa6a1f53f2907
98	1	226	\\x3d1c0b929258619ebddea26f219ecc4238dcc59c3221f5cfda659c1779c185f33ea4a907168a04ad4ef6f9670128e825c79e4cc2300787e0707addd05d538e04
99	1	333	\\x7f61d253f067605856b41acf5cb15d4e35ed7b42e7962643960c60c51a58bc3e9e591fb39eb20d323573cea4f1800f5cfad0925121e05caf25d4960d921cbe08
100	1	105	\\x3bd84679f80344f8054b1c0d6acd0f3cb1e8a01081da36c039c38e516819cad859a614ffe5d699da42a9291530ca0cb24f2731f4f203163cb741ef0bf9dcc704
101	1	338	\\x126e1c6c9663f7ac4d46ddca4791067423a9eee168b1fa474dfff91e9950adf4c8854a0344b81090ec3f762aefa381a8978ae86d111a08217e2d26fad5f4c501
102	1	192	\\x1ed0a0045b0d37f1402944594d656e1fcd55bb881f93421c7026b52ce2730093f580cc1ec0bb2d603154b7ad39d6f3de3562627db90d10221950e53e1d93c509
103	1	167	\\xfa7a1e3b9226512657a4d528b2087309f1410efc5536014d93b3ab6ec6f4c7279b5fb5c9b5294fffc53807c33ea2ccf131551fce838d4819f9b6c4e2cfa11d08
104	1	374	\\x347eadf671f0aea1d0da0824868e0737c979b30ef86959e9a39bc55ec4956e7f74d0cf73a73cc62121675458f86e55345e20b5755d647dca2930a5c39a554f0c
105	1	291	\\x615c28ba87a5106ebc541dbb51eecd30e24a58e91b17f4e26b5a9e8967c56097c2ef5637c377b996f3ac48358b54fd2825081e818f0c51e35f849a21f359cc0d
106	1	214	\\xf911c663e193bbca098d4aa035bc7e58b960a07fb2d367f18f1cec5805e15c23b0b8a8f1e1527b48bbb8dcd39010c86b22cfbd8628e6bef7b34e62eb4373d605
107	1	257	\\x2da2099d31dc2d91f1705766e3adf7b4028f5a49eee0f4acd8264e66754de0917698acc5ea97108cacf8fcb805dd31ca3e9a3c332698c9ae9dea743e7f39c20f
108	1	322	\\x35fe0eec9fef4544211ab4fb6e51976ab23a0722060778a397772de6d2f025c363c78cae3c583e5dc8446c171dbb84d9d5c95b5ba6669c12c817c2a78908a302
109	1	150	\\x384fcbe836abadc9f50c7c6492c975e76fa5fb7df0a2601ee8e400b56af81277e5bf79ba76c0348696335edf52d05be8bf44027a046bb8f99eb0e21159f35802
110	1	349	\\x4ecdd5c6d0de7444eb89c18546f82875cd7f56fde8b7b387bebd438ca7e6e419651577e6d7fb8795ce7e1b5de171dfa6f0ef2213b15e591ab94b508611d6c706
111	1	371	\\x8bedd20794ac81555402267e98faf7de461dec09bce4587e1fb282056b9fd8d831cbf8bc1b2f9f66c5fda6bdab992e4b426a875609de2a2cf8b7cdd77269170a
112	1	336	\\x141c06a9217ac3b32819ec817448ad1440a9be36a9c8f9694c12af5f7a75074752fdb518682f6011461e36310478ad93e1abb94daa53c1bcd9188d01c14ec10d
113	1	369	\\xec42459bacb457e514d06f296cf7927c981a0a9a3162d26e3c9a84924ba689253bc59a86c701045fc352d357715ac8849f41b0edcab0223480d190220d78af06
114	1	89	\\x31fb939e4fb17c3fbf5685423459e1f03fa20ab8740c89286b06124f8d632df84e892da8b207965836b801f5c293bdd5ad50ca81aca832d6fd60e0a59f2d710d
115	1	252	\\xaf4b4ca1edd4d835aac9ebd60f5145bdafb30b6603be8d6d3fce8bf9e09ba3e76694a8f8a2dfa5ae279219ab8c90c55e86464f1c3313d6d670744b9472c3380a
116	1	253	\\xd185603fc44117b02f7c15e1539d109c2810033f1817123ff8f7552d4431f99ef744eb2b7f375da2cee7186f65508072b384a811a15d636c5424c0eafbd23e03
117	1	40	\\xeb9034fe996c671ade55261dbf8a73bf0880dd820eddaa73d1bb175dc85d4f10a16fe733e734d9a2381d2c464d60f21cf474090ddf4b4c6867156584cf97880d
118	1	121	\\xd74d7a7339ac4c58b2357d084f6e94be0a16eadd2dc44d43f7c9124aad249c9f0431d97d2b46799ac5eafdc50ff36d197e6cfb3942c473cc9c38845c9c2f6303
119	1	373	\\x37f4ac9bca75c255f4feb138da86487e131891580c3a30c87db5103d3e84de40d46d6bb591181643f8627d542f5128102d1e34c3f294d3bb4e4baab0f4fcab06
120	1	60	\\x88a39174292cef9243f2bb8c98778c2bcf3c383794dd21e1405897e5267de444f65b326b8570b22f6f17f1db33b613e83475b9a5ccf467a257a5d3970aa2d30b
121	1	164	\\xb6c4158df48ff5656f35cda0385e4cea439017aea4efae773f1da9d13211524c6bf3baa90862915b7ae947259b1fa82dad0a52f020fd4f60457d3ca9c087df05
122	1	316	\\xcd587512e7b97f110deebffc4bfbf1b645497a82a74ebc846a33ec8e08b3fd98888048ad6b9000177f8710d7809c8148f5e5ca1bdf8e3d854c987d06bba72005
123	1	210	\\x0767115ed5794c05db00551ae55602aabd08c2b663dd9ee608316de76381f461a6ec38597d97a293b6507f841698905c45416874330df999df233f71ae81a90d
124	1	381	\\x43e040973d362d927726a3881dee3d6c3870817cd09249fa2a40c45928ae35910cbb4281bc58fda7ad4f47f42335a0294e5a77865edbaec3655f4b20f2c0fb07
125	1	208	\\x50ba66751450b41555baadae8328f7f9f2343d69c29c73c79f880e3b4b812752f4efc7b3e5d95422b3afa94d1b488f864179ae4b8f722ff87460457d9b349109
126	1	342	\\x1a5317822cc5964b9835e572566341063e958da69a65847dabd81ea4608166f3cae57652e333c089f05d75cdfcbc5f24ecccd21eb9badd28a13bf5c38b349c0e
127	1	14	\\x66290f7fd8535ee2f2f94472e33390981e6edc7869aa11e5aeea7cab551dd3ac33557de5999c46285f9cad09726382d3505fa2648a6b491b4fe1239c2136ff0c
128	1	120	\\x74ef66f23632f6313660a0cd7dd67ab0b796daae2e82cd37200689692ff13861fcdb7532afa32e4885f0d8210924efdfb914b0d3b6038d6cd0a3141127bc5609
129	1	335	\\xc1e733fa25daae478069a718c4c05ebf30bf9f85b8ffa99b7b51f804974a13eedc98c1ed2ceb005012b9807fcf5a772a8c5e461762817c0f9e49f57302facc0a
130	1	144	\\x02e4c3976dce87151a4bcaa792af901c06cfa9302955ef9afa45dff7aade4c56ae075a736e864e8ba861ba198ab9a8d1bcd672d6a43258da052471a0a8f33703
131	1	250	\\x444bd7382322d8afeb0d25ad2be7879a0bc85e912490a9d93fe64a47df65d9ef8db76ac1479cca681dcfac106cc04f3520e241c6177191b97667fca2fbcd2605
132	1	51	\\xbee686a6b22a3d3ad8c3eb906c8c51320379192dc49e0cd126d0d4208a857b908910d98e2cafc10b11d105408f8ead434783ade953f812ba7d4ed581d9f57909
133	1	267	\\xa9ae4b9ecfc3ffdf3f7527adb18e723714cc2f7141990ac45eef6e1098037f4390e7c6d670edba7de9e120153d55c5d4a2e6933d83e5ca779518d8fab914a507
134	1	148	\\xfa17f87ecc7376f9e32546c2edc0421b1883f99e8a53626bd922e2ce914f909a68c4b514532354598551856ad8914ec5b5150f9d53ef5c0c88e94b2a5f79f50f
135	1	200	\\x5d76fc0d58d523ce16c63e81db18bab8c7eff4334f20680ab0b128c6ba34eac080e51490c6fd2e131a847cc2124e31e817ea57b35dbd36204d2b728bdbfd180b
136	1	154	\\x3179d2ede28e471206540dad674ec7e6930e8344aae43e0cabb31ef9f3c4f52f9969414390f1d3605fa164783bc4a9968db51ce6426f8092afcf3b5d11bdd406
137	1	185	\\x28b6b6fe23838728f4cbb8810c99755d78c9142a7f5f96efe46bebf60c52911e2964161c95f9fc28f2c5245e5426cace7f9e5d4c944ce13a7218c3a62b2a5c05
138	1	375	\\xa5285e9e0a9373393401d6580588a432af8609838af164fda32d624bf68f4a1bbaf57b9add943617d06e2eebb0cbf747e8dbaae96d73607b6a1b0cb8ce68280e
139	1	288	\\xe31358087606fd0f7eeaa979c7a59f51cc992f79155dcd16f313ae681b4858453543cfa38efc7588b36ab5a4e1a60503f8d40da8b39bc9e2dda22398ae490406
140	1	5	\\xf17b9f4a1c121d3b3a5dbb20a05e9c08acdce9dc65d8b620cd611319e2b7b158ca09d15ca0035a3837f6b178d353f2d4583e64e28d0fea8d10d621c9b608cd0a
141	1	408	\\x981d109f14bc9184923fce3879975efff9b46e7b7f55080c8fc88d816f09dee014c47ddf3af2ce7a7adfeb21a338e3f413f012a093b7714420261d5c3200ef01
142	1	387	\\xba8f9ca7c2d162a6ef803e21d6edfd2f6bf68db029e8c231ad1b9bc648c59eeb3d27de4739ce5538ffe260adcc1890a454e3bba0f166a2c38b1bd6be883bcf0f
143	1	399	\\xdbfde5d1991f6ebebce35b74b20c011cee5f39c5f57e16ea5a3710628f9cd6a414b6a1181132f171e434955b58eeeac5c5da410a9e6e168e82f9cb0bd75da600
144	1	189	\\x66b28ccbd20ea8dd48f31cb4f3274db489708eaa00a79150fef183b4d5748b78ed1b5ac257837014115f9992c6f535bb1d4dbbb81f98e74e3283e67aa4694a03
145	1	285	\\x3bd3e34e2cf55ee5ff3bb1ee048e9606544980e8d688f1c6113b9f3453ad3d81122d960c52da3a9222e6ec5f850c663f8e4d7c1d31872033ce10be89d3e1f10f
146	1	310	\\x0cc79997b17787afff1a3b8af446c08cbdfe4bf5b020db617ee0c4abd87505206d5e4fffecf478be5256d507f7cdd4fe4d24298cafc65def3ffb7e7496bcdf07
147	1	421	\\x3fba0e75688ccc95445fc52439ff2b2d142de51c424c3f4b1747cd0244be9ebb3a5439e2c9269df00504aaa24261bc35e6ce9a943c8bee73b2d199592d197d04
148	1	238	\\xdb04bb3ce77fe4d7018cf03e074e966651f67fb5f8beea928273c71e4cad0ab9222455bab7d9768d99196038ca304f389f4362547068003f0ed3a663acc4290a
149	1	274	\\x02395284242327eaf74b7f0b83fba4114b0f991148bb14be89f9dfdf69378fa8d802f68066b0494f41a43ead7c30d0daf3e371823ba0642b384059429d4dba02
150	1	345	\\xa2bf43532c53ac4d61886ee6097e0f6d8c772d663cb4ce8ffddb1d645aef281a7eecb33682f727ea1e622402232d04e310f9614cfd84a0f58b1596f1b83f3902
151	1	232	\\xebb25514034524bb5aed5efce24669751346748086eae77426eff7bc35c9169b92c7a348db958c5ceeab8e84dc2da0736d9461105989eeb39189e52681515b06
152	1	159	\\xa9ab9cacb66a0d37664c27a1f08599a307fcf547215ba3d26aac9d0cfd13b0ffcc8f1fc369a73e37b879096f65d43be37b5ced84faf60b5e9d41b4f520436a04
153	1	155	\\xcf3c8c94d76725f1a052de521152f5546c4da6595c2e93573d98626b490e02d8b63918935354e29500429693d58be8ae7a26e0a89ec5c3bd4373fe4b5624460d
154	1	313	\\x422c9baa397252cc49bb61cf57e7e95ad82addc4c318dee5db4e959d002215f8499a596c3556dfdb8af705ff2e6af63fe568385e9d512a324a5ed355bf26bb00
155	1	295	\\x122db75cb3cf39322ff2f91d75053bdd1bef2057a1aa86477627cfca36bf33c999c053d6d084967bae6efcb50dafbad54f6d9056bf940c9f647d049ecaed6103
156	1	203	\\xdfd7ac5af0a77f72d789864577afd41f9a744b6f635576458a91b0eef8535546abdcee49e893204725cc150dab86423f71a36ddf00535c076e48dc4aa55a8e0c
157	1	239	\\xc0c770f4bb09476a0006c25c8c0aba960f579e70ec72fafa5cab20f50eae7517c31f10bbbdd2aa5b1ebfa05c01dafd8b794d706fdee34d9822dae4eeaac69c03
158	1	17	\\x4b5900379042bec556ff5d1b9ee804f222121871ea8e850b8e5120f7d8d88ec1d2f967a5c3e62404f0d5b9e6dddbf7d95d8849406da84c847d116fbf5c89ba0e
159	1	9	\\x0c807ce1ace7962347992dc16291d6e3ba9651bfc71f4a004596dcd8055d096674bc2b44f55cf5ab3962a83ec1c27d03b26de6dea4905c6aeaf12b2d7d6d1e02
160	1	80	\\x3eb2219611f6c4128b17ab3813fa2508bc2593f0ecb836481d9e013855df8c834b764a2866b0fcd7d4daaebd39aa5e0aba1995fcddc5e47dc759e2ef687e1c0d
161	1	112	\\x14cb56c0bbb624197247179414d5c7f2245e7fd631c9c831a995d9c3eb919dbb731e8bc19ceacfca0beda98e63eea4a3bb299aa7218831148888dd49b68cf40c
162	1	397	\\x0fec890b61787a774a0ff10f34a9b4f8bc9165a298752ec910508c5105b4da92b999f074b80d7bef401c6fdee763e8866f7dc30512b6be9c6f52f3795356440d
163	1	61	\\x4eb023a269717cef80f6f5ea6d4baf090496c68cbe8966fe304f089f506ed79c43432e1a5852e7bad061a100825c5184aea47ad20a758d3c2c7d5f2de35c4a02
164	1	368	\\x6dac40fab2dd6f9fc7b67c3aad0e8ee66f035d3e8f7e6610d63adc8dd0ba0ae2c70cb544d1038bfc6df78710a3dce01ec1ab5e3c4a265e47144f55b0c6bc9f06
165	1	319	\\xe215ddc52e8f28d4d58f063ac575c0cd010fdf53afe2a3217b25703e326dee643c04f1e20070c9b54b7a0f6bd6d02398bc27ac5fd1c3c83d8769e286d1d16f06
166	1	293	\\xe925e790e30461532e2c4d4e26d06f5898fb9372a2a28ed089d113e9eec76cc341f7c0d63992cd6fe0da37a867980e0b6246cb1ac37eff1efe4b3f8cd48fe20e
167	1	272	\\x293d422aeb5fc1f8852ca11a7f245ed652e0663c276f13969a6d355005c0830b504c78d302bad992cbbe0c51a40e25f9d0ee04a2744920a34e987dc0dee61e0f
168	1	16	\\x1c84a05e3fda3564f7311597819ba87f6a29558f0659a5f60adf366dbf4b98c99e6eb3ae9d10ace041a0e954fac6d152841233853309712f7b0a2921df67750e
169	1	407	\\x16d650ad7828f59f1f25ada6f3cac25e1860f23e66e7e70b85676421fc7902a5c6d7cb2e6dd10d30feb44515749c8a9adb8d8c87b52acf28f6707dd71c652803
170	1	11	\\xfe7946044df1f28aac5d8198304acf6b5582108df0bb023ef2d813e2b072a496297217dd9c95ca7a48c0389619b8a3ee0b1da8907d345170dc4e06a0d022d206
171	1	306	\\x42c2427bbb096387ffab819f4370dc50d26702df137533ae7bb318cf54dfaac7183854028d93b36975710fe0061990f6420a50bdca1e93ede7eaabf26e4d8f0d
172	1	19	\\x1f10b2796822f1a8da4f2eb4f921bb7e3638930586582eedb953d071f37127edd4c1c73bd8c9fa1545a69dfde994afec7bc473db56605277a6a94ecd8c3f850f
173	1	143	\\x658cfcfc30d18c1f1e6efbc1e336699386230ab715e7a787b4454a31baca623f79cb46c6e478a4bc4a539ef89ca0307336ebb007a3cbe4ef93dc1e7b89ad1200
174	1	139	\\xa99c0a991c85a0c02aba64cb7e9d119589ac008e744d88817b73577809c789ba21e652f87a0ebf9bccd16ca763a7aa15d2e31149d2476e32eb9d53d918b9230d
175	1	170	\\x34704af9681d40ea89eaf121878dde316d16ac2a562e0ec9b73959021fa750321ccd77fda22b2b6aa47df68fb34ce8caed16f737ea8d7fa521a68f904651da0c
176	1	234	\\xf70d434de8b88aea65bff08a5950d3812b65fb5879da6d23d673d7ac3a9d1cd5d7d71779f8b34d5303b2af3456f4f5132f4bc8512e8a0730d030b22768181b06
177	1	133	\\x1c5eb0779fa2e657357d52412c8d65b897c0dc50fb6a9217aa1f6b71256ba6f8a90d71ba9300de080a8702e62655c64c615ae6b574746cefb19fae433a5a5704
178	1	54	\\x52df959f4bd38e0638da43de4ec5525b919e7e08ab0d0ad859bf72be4d857f7c072b85d7d905d25df49cb5de60e2fee0452b5b2877838fb8c7db7d39bda79f05
179	1	359	\\xb33e3193fdd3902c40c014267cb4ff3b3b48a77dcae8425e56690dec561feac660ec2c359c3e39794fd8ea7aac67865fbc83b80f22393ac3f51b54e398fe8403
180	1	136	\\x0036ca077f3749dd20ce3739063986b427555e08ccf8a85013fa7b71db69fc039178a2eebcaa15ac6af5052b81b8d3553818a2cfc855d7a052fbc5cf7b56840f
181	1	64	\\xcc89a3de72406a82f79c5f8a5418d2a9128b08f66106cb8dacce05e24c56e685b89dc6a6a31df1c87304a29fad193d0174b6625953337afe040cccd729829d02
182	1	216	\\xfca449b89b05f5dbcbe5c5992837ec91576dc74a892bf231c6c8824860bb9a57514bad3ac3196eed866e340d4bb4f85c6a79d54f1364767d4b7febb3e8ff9105
183	1	187	\\xbca733d5a745d556661125e15030d3c20cdf4693a4fb5e1944b3f60f44f63256285919b4133ac4202b0f167c1a8d337291e8ff24b49ba22f8bde52a254c24f0b
184	1	423	\\x57bf1257d77f3d65cd8c6a1d56fbca433ccc48e8c912dd01f847742d34077234fec48bbbf752c17f1e55684e45b9635f3fc4d521240d5d62c85b5034d3279a05
185	1	400	\\x22aaaaeb84d9e60e198b7e92883fa247b3042d75cbdc6a2784182bc246243c81def9a3a2d0d0e35bb1a9fd7c41a63b4f57682ebaab01f3916f81a79e6000fe0b
186	1	184	\\x1b61a8bcc189ec32e0044bb033df7ae83e970c11a4ba39b5efb891cd605d13337fff59f7640509106e8ae185ba5cba8224d0852e80429cd4c368a2ed5d27980c
187	1	168	\\xeedc900cbd531c3a88a1bfd0d978dbc06902ca7308cedc81fff5d0367dd8972a07ca3f83b92cd836844d4f12a9dac48264cd797daad608a474b6633821783d08
188	1	197	\\xef064cb725c0052128ed870a503d39fd03fdd403661cab9376e7d5a9446984b1c51c5716fc8ef7bee649a37797f1521efdfbc10268d8f33f0775714fd8730c01
189	1	301	\\xe73cf1c0dbbd4f68f3a16486aefdf9dce20ff9922f09ef7e1a1ac3710d1201b81aea3f6142a45019c7b8f73910cc05ab2cf7a1e3fe6a5a9cca72373342ab480e
190	1	37	\\x90d98f300f65d9a507858e7fe23b182b529098f911f772a08310051a74c0cf40a58a5420d964fd00a7af0176d07c7018fbb1d8f4cc260abd422d7c898ec70000
191	1	176	\\xb18ce3be81c7441d299ee8b497b13b21c6becfc9f642cbb25595038749797c863079a3f16164093024dc2a4bc9473c766bfc5d7ba0065053cc0779d685202502
192	1	409	\\x50392f9d027efdd1378b4d38ef853c738dd4cdc477b9b5be04bdd83baae088d53a58a3b6593ba3da0c0212f1c1e7cd544507fcf542fed43e98cfa0f13721fe00
193	1	318	\\x82389e88c71e56e5dd350be07a67c155dfe26196828f27f003ea8005d4070c80a57723792e9229ec59fc5fca8d19b0d7d97c6d7fc45088b4cb156f824fdc0906
194	1	20	\\xd5a228163d6d81062d149e24ce43e195a3343e642afa52ab05107249faf76bf6113a8bcf992a8ff88166dc3078e665072e495a8f5d3345348e8c3e4dac49e509
195	1	113	\\x4d12ded1f8d80cc4f3cf3ee24cbf3219d1c5b6efcb167d03fa550ee7e23bd2344d81565d63d3b16b571e1edcdb6cf7675f4b503b1d18dffe64a95ea8207b1f09
196	1	348	\\x1063a333a76a1a1b6ba94d8907c4807d0f502d52b4db8458cd8c02b233e42898a6809050a4bf5a3aee59c525a588f2c33ab7b898e4276adc34fb27865125f109
197	1	277	\\x56e8b83377d82a057a1901ed7a6671ba76ddc6bfcf5319e90f8b2b8338b860daeea029d2a0dee1376c5f8e5e540625d9753d1e1643fb9cad91b46aec12343b09
198	1	405	\\x9430e6a76d2a3f34a92d08b2aedf372e82ab055507b258b149d6ce560cc88840b86bd535bf27fec296bddb197f6899190bf58b2b1532120238c74f12e2aef000
199	1	343	\\xd8aebc4c46f3533da4dfc5deeabcaa8ff8c55779b396347921b2724f38c1554a1db9312cff04f71d5d29cd53feac2d645c94e1b7d5a4467f5769d9fe941c230b
200	1	281	\\xbd9af48fe8fb06729573a959668d61f4fe0e47b80235e38e26648d43b1eaef434dbdffb03a1b01e5c7a15a455e6be21d31b90ac291215b005467273ea69f7003
201	1	341	\\xedab359e7d68a7113e753d4407c63005deeb0fbaaf9570fa7d84ccd0e92fc697818e0cf0c08ca3aeea5b7442fc483285593a778129966e78b9e9a1814808c103
202	1	259	\\xd178205124d71e72fe7aba4f74af384ef52bd7c559c4c313f53dbfd9c190dd686b48aa1b1c3f1068a9b84502236c85ab0ace5b3e1e0a98e0a1516f2058ff3000
203	1	330	\\x9aa2ee8a6cf4e48e9de565099b2fb399ae88d1816bbd901bf7b7f52b8bd2288e595ea978504c361c16bce78c935d46fe5706ad53d0d8d4bff50797cfc6760b09
204	1	84	\\x9cd47b9d07b4e46389e2bc5923b9c753387e854f902d3fb00f77fb976ce2b2cc66198b5bae42b36408d3c5decf08dc08ba7018bada0b46f87a61a92165d1ee00
205	1	248	\\x949031cc85cfde9d47667f54e2ce92be21d8b724899f9b0e33552b29514114f66a90daed0dffbdad74d2b48a40cddffc2b5790354551fb888a8e71ac56d1a70c
206	1	25	\\x5ed3404a558d788b7de5542edc78d6b4128ccd3ea807b5d42cc7ac7b2fc8e40bcd7d3f5687c0dfaa50c82a63888c9c716e37638beebaab1e1b2b4390e45e6a08
207	1	297	\\x2008e9a489786bae2d983648cbdc1a42f299d00a5b039107463d1bca9ff18fd3dec4a2ae65657b55d0e1d690c7215aeeb20452c427f6eb6af920b2f24af8ac03
208	1	52	\\xf000f395573efb3e2924a5f5715b06940b4c2d289dd151f6814dfff85d6be7be254a2b513af13b6a7bb827a66e876b4304440f0bbf1213c5e976dbef47b0750b
209	1	417	\\x027731fc7dbd8c255c7d456d4c7cbdd3c82fbd41fc34cef41a543400e26f518f281fdf5333f60999a3f813633385d3e093eec19003a884599c85ffecfb96340e
210	1	87	\\x3cb9e8acc51fdbc35df7019a434cbc3c557c290a9a98022448515ab517aee8daa77adbd253747fa56dfd5f14025bf1ef6028552038dacc89e0bba29ed39e3009
211	1	128	\\x17afa7b30720a10be1df6e25c59e4463f5b8e65632424f2c62800bad9378ea25e92b4538de3561d732281935c28e9007673e11f774c98c1eac72b678fb9bba0f
212	1	145	\\x31beb7d8fb9e9d5ca5122b9f0313223de25d49d2236551dd75976ca217d4b5accc6dc581053e858eca07023d8e4a62eda9c2c95cad8a2b1eddeb10f60b618f04
213	1	265	\\x72d9a819371812f84d4ef5f89cd7f1e9474bc014f0389af6799ee904220fe8937774eb9e0b2ac4216a46165b7ac9fd3306582db9e2dac939871b7714e4c81609
214	1	160	\\x47090b28c3b623ec2f191580a0ed6d2a082e75769a34439b7dec5de52eb41021650059fa48f469d7fa14dccf4c3ec1fffd21b05a5ef17e05ac6963c2e81a5f0a
215	1	163	\\x19fec45928f19ec3f7fa0b296838802551fffd0b8db0a708e5f8b026d5d32401a7a8f55822726430895ac27050e9fdc7e71a16434065cf14e980ef2c92ee8506
216	1	360	\\x6b3f4a01949b9cdb9917541f974e3458dae93675b7ec3cd4b637dadbdb892daec16af2f32d2bcca2d42d79c6c16fa244434d62e7b9d892e13ec03b24bad70d05
217	1	249	\\x3897d751d57a7499c3d54d80aa0014e2855cef543573fd4f5923b9b03a109c62afd947d531c0bbc33f574665384f9f1c6a57f2990b3e04ef8bf4830f4ff51b04
218	1	57	\\x875386e4b5793c6fafa6a8db2cb64a5dd67870ff49c73fef960a04a7ebea8093cb8d270949e4ba6a0ec1bbe84e14ace2d01d832cd1c6ec8b7751268fa830dd0f
219	1	85	\\x422687e2e1c1428d1ed3acfdc2ab1c7b58619acb479ad00308780b4dca33d574e55f86c35a8c544f4cea6a5ce27f2abe0f5d0eef87ad0c9380471aa9afe58902
220	1	47	\\x1b140b5106e7f6f0029ecaabb95cb15fd652e157e16fec3db7e8d91d43c910d58dc47bc2ae1f77f3411e151b1a6887e992fda067c7be6158c009e53c13beb20b
221	1	213	\\xd2ab07a6e79af54631d96e805ea5e425046fd3ec3d1487d6a0d2af13f710d8200eb8ccc5a503115bc438c8d04d5835e1bbf832caa07c995a1c8f182a24fd4606
222	1	315	\\xa6866acb0afbf662140517b727cd9c011ab1f0df5402132a79b34a70649b72ec25e8e2fc59aa10671660ca043fd1523033ebaf28138cb195820ca88f29d82900
223	1	396	\\xa5228c83c96bf36f379f388912e8c2fbc8c7c81c0efe094a488eb7b0e71e3ac6b33284282d0e762da7a814832d750b945af89e25386f35b2eff2795665f3750f
224	1	412	\\x5aa368fe6141d0722dd9f12fcef2e6433943297c38796df2bbba1e10f9fcb58217353db0bbade9ca61025a8f09017cabd32d19b3e32c2206b7ecd104d23c9d0c
225	1	361	\\x6d13aa21746c5f40eb6422abce4e7257c325e9512763a8d812fb7d3e0bfa5d121f521c639efda3d88fdcfc058d0eb62fbacc98d1dccc2281d9c8d1c6310f9509
226	1	321	\\x664481f71affac45ee9412e66e532993e1a773b8822fdc194cc0a3e14f6ab8cd47d06b4b7aa519dad7915a542222b1b7e0f6a704d8eb6416da545817cfa3ca01
227	1	390	\\xe23397966f332e44bbc613b8ff04fdcb8a51caa71e0835ddbcbeee77b35882ac074072fc5428f3e400a26580b1af9196c0271fcc93f98f772a03e4a8ce501c0a
228	1	347	\\xbd908334cda0a5d5668812530d9254155c35e5eab8f083b10bfac3bee186753caa265e9d09c7433bf8d52b26c03d68e72165b919096fa0c00ff87d19c9341b0c
229	1	416	\\x2908f01c1556f652d7e361c508ab2fa7e07384aa695e9cb354eed62323fc4c6821332f71a2411eb9ee3438d8461a06de6dfd9baace594eb6bcb52b57f44d230c
230	1	385	\\x6840aafd89aa576678dd8ea462a230506239a29918262e8d28b08762a6ba24d05178c408fa5e25f9234e9c23f136a949b49c0ed1d791639c55e75e9740bca10e
231	1	309	\\xd1249fd62c180bffaaae581dd2efcf5a9020e92f120857673f9348fc08ef904221ba8820f8ff014b27d8f5d6bcd8aa4417d93b1ea9b5d583333990e895a7ec06
232	1	326	\\xae7b6b9eca9173a53e226e6901979b19af1579773aed91d6e94c069eed1684ef91a9518a5710356544c9d60667871f439b4f87d30550dc52c95ea635e20b740a
233	1	404	\\x8527f14f4c4049813452ba0b4bf591ee9738a51a1319798e0205973c59d72671fec9e15bde556ed5674f746fb1bfbf11e86b13260a3329889ff48dc7ceff0e01
234	1	393	\\xf26db281c69630af02b753f609fae16b5f9f2d0dd18da7adde88506f993d1389d269818471b936fc650aeb8d95a51e0499090aab304a1720da01da9e0823ba0b
235	1	218	\\x738d5d1b58c6d3a53988a12dbb958c906b985985c55881ae41f9be3671a0de0e5d58c711d8c77540fddc2f46bc72b8c997498b2baceef580da3c88e2d935430e
236	1	314	\\x079d926c71e177be88eea79e336264831dbf9d22275b168dbf18bbb843ab5fc776c3e128d5591294ed4b47bb2a4a3667b1d3429ae6e275b5f024fe86aa13160f
237	1	311	\\x31d45930d62ebee41dab36e6bde86d5f1c9edcf0a10687649fb6f117fb8223dec08874e51a41b4149330bd901784d02d1d689dd561a9b448b91579fa7791e307
238	1	44	\\x1245f9a289340f8e8459fed13dedd0ac98537c39c14e3df1ecc561ac74062103f6b09d76b4caf0ef3b9661eddee900f71352320d788c35da8bbf9fca3a74080e
239	1	130	\\x3d9857abb7e14575a9cbf816e531e65d327fced871f0d5b54a18d063b7e366e3fd6d1a545ef67040ef134084c7a49ccab7776f3fb17bb1a6a4c9618ea811860d
240	1	156	\\x80032378edbd66f20ddaeaebd1820b65dc30ec4eefa1ad18d7a70e31716dd1fdd8825875029065814c31d9c64e7b1259dae2c8524afb859a2821635a60d4a80e
241	1	88	\\x002790d5a3da6ca5b89f29af090c78a877aa2ceb6f0a39f356dc1ffe33526555e3a43923ed9bfa84cd8d1a76ee42e68689b9aff18c868353e3f91974416f8604
242	1	151	\\xf05428f1c98c1e10e9bb6725131e48fcf0e1c72ddc25494dbf5cda12c5622a6927b8195f4bf86d5d26fd10bf1593eb4cc22cffaf3e4e69a025675c69e93c5c08
243	1	141	\\xb980147c42674fc613fc1334e314fb7dc82433201855a02e651ba5cb65eb33c1f9b7e693133a5b49504a0cb5e0df7496ee874cef12acfd4b3fc0cd42b5e92d0d
244	1	63	\\xf43440b1e18c15751c98b3e06e9eb1ab9aa047c9a11c28eada5329642277be2fef6d4c9da2fbb909e114777e9c63755920946239dbd86d22231a4f09a1f8d600
245	1	183	\\x58978e099e044508838597effc7216b15743636c62a3b59b87d00456f8c35c0a9b79ee2deea91931bfb84c451742f1799266b0ae0de507ef5607d28396aa4100
246	1	251	\\x5676cc6a07a94a9820c8922e36a48a28b81dc1c2c7f30e587623e2a4222531ba9a9324da42286cad6e3da962a82886021a821078e437fa3386cda122e04db60b
247	1	15	\\x0230506e5bd7a44705185d465b0e6602907a6b542297a8507d2ebb05611871bdcf15ec38bcdce31ffc620430635f7624336d078b127e234a34290aea97be9108
248	1	62	\\xd49ab313b507c706185bf98101bf996640861879048d1de581a8f08282d4268d4b3d0d423f54779886fc180b5116831db31768094f2e64726dbf5553fc1fe90b
249	1	157	\\x8fd4e0183d9789918fb39f2349ca71dcfb05557ea992ef2ddc343202dae0697fb54ccebf60de2ad2a3fa5618cd82658749ad7ef7b1b99314a3b5fc1d8b401001
250	1	198	\\x7fb4ac5bdcf8881fe24259b762264b0c334e21157e336e4f1b6579e8e072b0bf0d62d3ec16bffdbf7931123ba20d3b3ec43f3908b31e44b60fc3d89942e7530f
251	1	278	\\x4923f58c2d5701d1764966a5c9e6f37ab3c9a98440f98b99556c79dfc41e5cb67e127e52e0d6c1b09323b246271f683bd646b0e71866f7beacbe4c9cb8631f0c
252	1	294	\\x6ea8fce760dd646934e876e4d9c20f54319ff77c45d0c11bec340ea65c0a15cfa0048ce54feaf50e293aeb8b1ece81ae1749b22961d380763d4dd4d86c0c460b
253	1	340	\\x7e3d4c32a92e3c43c760ab7c5bfb1689809769d46796c83754d94f200beb4c559bbb69454bed491818ae6ebe8095c8ec47b07c4ae1b71bf012f37f1cef719f0c
254	1	260	\\x6aac5bbfb84433ac5961f506c1fca31b0842ef82fd44f84faaf0588772e82c6b9833b48e5344e30663e2ee93898761ba9cbbcfe047c40e2711029393a4013c09
255	1	206	\\xa39a297d7ad1928e74f5bc267d30c5580675a968514213dc5703adaf44d800f2f4a6d040c13b0065977af343037e71cb148b7c9f65e6b46d44b33a7dd9730404
256	1	116	\\xae3bcf7cf632cd4dd9bc53c45426f2d3d8c283e146e48bcb257f8f8ddcaebd86b65cdea3333f5d575844d33fcaa57a61121a5c2594f456ab0ad613cc4574d508
257	1	172	\\x9df9fc51cddecc8490d9169b2b49f0b049aad719d8349af8c256b53306d8b593534687d8e4656e930584fb5bf76113a3a7d99c822187f37dcbaea20fab856e01
258	1	401	\\x80838c6f5dbef5206eb8f5b7ad1df756502385361a2f41dc3b9b80b40c1b71f1c600c294c2ccbf60f87e8b8e3b02273433aec68e5a974381701687e719f89e04
259	1	282	\\xff365f181df91d540ec8f0fa5c4140c45d331819be71755281d36fe3fb0b6e10b1f323de2e546ec2285fb3150c038d75005e64b8e6b9c9ed37d806d1e6cb1108
260	1	233	\\x09f698ffd7a36615f382073448354b50cb0981de83e0a6e3b4ddd54a6721cccae2715e59bf55c8dc4682f6d0600419948c29de82d7d7dc2679f7854c1d050d0e
261	1	356	\\x90312b7c17946b59aa0e5df805c16c1bf5b7987a861d640ec86465edd97e5b46b4bf0d80c84dc1a45ed1ab41f11fbd1374debe748df70a7b146468589929dc02
262	1	308	\\xdfbab58589aa5002d571673758eed83babd236343f4aa9b9b0e43bdffe28d0d4ce24ec204a75f524e8f759300855e16bd2780a6f9ce6dbae851791e57562e800
263	1	258	\\x67a17e3b83fd49bc66f88856f23192058da792387902e0b1bd39fea2802bf32ec57843fc9367ec34ef8d25515a2f85d1d46024395fc69ee8b7d3d4a0da84b206
264	1	411	\\xf33823bd3444bf3e3b9e97b1456db960b51d65e13f28acf8fff62b5052f3934d8eda5e7de974a8d0d9ee05bfd54b1159ecde81aa347e189bdeee2e06d8851105
265	1	78	\\x4e389e943739ae1c0becb95b51bf3dc343d0e0bbe0f65444910021b78c715c8632ef909b277af1fcc86ac3e9ef17943db056e23adeff3564e94800104dbcc509
266	1	90	\\x5e235a23d221c6418b88bc2453d139681161885b40f166c1cb3d9875ee7fd92bd7fb5d4b1ef8c29fea0bc0a618af9be184553485592c384e0628785a0b6f1a0c
267	1	162	\\xab84c44600f9eac0f8fa5e4958a07c49b38e98a15aa020fc99ffaae41aa25f69158eb0de5f3b23313d76fb76eefbf4b44b18abf7517c0934cdb6e9effd97e506
268	1	186	\\xa8af2f5b983f2658683e3199e3f573f41ec17ddeff1c4e9152cc89ef8224144e08651b4b466b37084dbfcbd01af4b788b5e877e32696b5bef352d0c5c55e1a01
269	1	74	\\xc02eb00b7a51f336d6459cb7f57ac80061cc8943e79270813180bb85c93080b9ce98c51c0350eb3a9e11b2beabb05006a1e3a10042c2673871628826c8107806
270	1	332	\\xa293830e817dd70ab740818ab376d697175ec914f97d7a17116c04940db98118c592ac90902116c337894c6b0325e32f9793aeb589999be293aaf7e495bf680b
271	1	304	\\x37001fae8c3d4ef5a18c6b35dd121b505db2eb35c906c107bce9670064782ce7c31e0895ac2bcbb875ca58007b67ecd91d23d256bb4d8e8c5b0bd3bfa87d4a05
272	1	303	\\x44dd78b132e37bcd530acff2c807be9fbd785a8599d26ee540376b7e55820223a9fa1f80e6510c7b2dbd9eac1fabe0251c24f5956d359ae75b3a13a570cf8b0d
273	1	219	\\x57ac8390cbb738fe6485004c4502db2bc20abfcbac5038f09e4a83ecb9020354a15a74fdb2621fef418302620abab1a8506bf2690c5caf86e4ad92e1d4832906
274	1	299	\\xc87aff4864b9d11d7e884d3e174d86f8c08c7947740e28db5f5bc9e891f6dfc9793b066f7435e18720d4466169ddca9846a949fcdc33fd54c8fc1176d3702c05
275	1	6	\\x714a0a67277204c5ee67d0c2546220682c146a13bbc035c4c3ab2a026f5f9ba7f904ee3561210b5a10d3df636dbd5538a73a1a52993c4193ff0896f4215a140e
276	1	107	\\xbf3b90683cdae43989cb68c2835ead433f47a7b8c657b340388ece8fcca04c6769c808ec91f2095f83b56decece583e2f5007882dd2af286ed3b2cc574bedf07
277	1	27	\\xc8a5c401f527e54e2bc8c224f43f28bab8d57e0846b342b95553d3c7c9bec2ecb57d745bfd9f2b76be736d9e8348cdcafd03769a12abac2aff7edb6c0479580c
278	1	327	\\x8e2b5301579e1c28db9edc9370bc7cdf4962bfbb5e6cfc12313d9eca434027d4408891aed3479010195d87f36a6fe369d461e466c61e5c9544c5705b8783f207
279	1	325	\\x0e53ff0b4bf80141c90a0e17f85299b782639d51fc90b1d344d33a323d1093f020704ad3fe46cf5a5e8e343e9f9ad6c5f775bd23d988e35ca49a5f688aebac0a
280	1	317	\\xdf6365511f72f60d4c767eba72a3b1eaf48ade357673608b80ad8092f7ad56eebcff868eb9931ebfefbb24a40956353c409c4669306e21b7a9a1487d39ce0a03
281	1	68	\\x07163dbc70316d20c15b236d1af06e4d63a43edd089d51fe915a2a95e5f32b8d6380e3275e7bcfc66a5d1ff7df08e9bd39f440215c072b35ebbcbac12aebc501
282	1	147	\\x78a9bba950a96bb893cba180ac42b5bb9ee08ec543b07d4d9ae09412a10222ec5fe29f620ebc346518146ec3edab6798d6d8ef06e2d094021f1239bac4445400
283	1	331	\\xd28feff00404f4a27f7fd2998beeafb16d69fa07964993916b5be1ab6e197141a32759975d6ac469a204d3a935affd172277516265982004e3f5367a8870b204
284	1	276	\\x20af780fb782934309456d48f2284e0429fa9b83be39880179e9d37894d8bcf756fca7f10d4a25b8d356cd4742de646052c088c737728ccbb7fe5b994d065404
285	1	94	\\xe14127eb2012cb118d9ef644c01714a8c277c74c3acf6311a838d5be28426ffe4d82b18a163574a95f4c03c6e04a382fc8e2bc97d1f262f5721c790fbc14920e
286	1	353	\\xd5bee174e40307ed3f7be28ee16dc3f8550d14b2722fda83ab6fe1c24c193c3622e6c31ffd08a4f403cc3fde555145dc59f748037ad5a1e0b70df335f702ce0a
287	1	33	\\x1664c538e9fcd1b450e0a14f3410d3f0ded82e3dc93d1bb25ae843699bced75da82f04bfe363761f8c3c8cbc47fd8f7912a4e18f0296eccee979fa412aae950a
288	1	152	\\xfc8d57a4567db46fc8b39f54aef7cf6d56af79a19eeaff33b09e4fd8c0480f373a99a9b5cb8bf8392c96444e6e1ef7d460ba60750bec6048b469bd9a3de5a301
289	1	171	\\xb3e4b07f85de4cf6a18552e76959a2479971c556f1b5550ec9ce772af9d206bd4f11e94d04d20efaf3bb240cf7f48e981a374fa70fa7ccf7379a942b38320502
290	1	26	\\x8c5878b3ceb6e263ab7d9511cd987eedcdd3959d1e30d5dd247bc10f035e0a91fb8e62e56f6a9ad0f84404aaf7e3c6a43794903566354807ba2746d15d92f209
291	1	275	\\xfd91764717b22289b2a0f409db5ed3e52f7c81d309af30cea5c42da866bbffcd73e001b168a902295060417739f78a2634a874a1fda4ca4498f23a688fc6a604
292	1	131	\\x51b15891048f08cd82a93980439525a346e29ccfacaeeb097593c1bbef4f6986fd8aaf4371de43cfc31d63c3e809f77ab3aada3ce137737e7a3245a7a90aca06
293	1	386	\\xb0bc1f049f7154df7ce4c95eae1ffd48681614ad8a06b00908e2f9d3fbf706bd40f4ff65c7ec9f8e3882a8de488ebd4b39d8b39ee229f115c2bd7c6544649803
294	1	256	\\x59ba5464ce191ee73d602f9278f8b55236d1200fe26a181f1a25c598990867d2f0526d6e7538076dfa3cec82ba554cf79239047b07c313c51cea23343a9f8003
295	1	48	\\xb6bc268adfbdeffe5490cc7dfe0ca3f88f97607fce734d250054a5de3aa13882bcbdd1feb7c330743e42f31484f10f9799e352623a99f9b4e5a1ad184ca85a03
296	1	199	\\xd9274f5e65eaaa94591e66395d44e583e81173849f146d65ea2236a85badbf16199de245ae215a8dd4277e395b6bae33510cffefdeaa7e316a6ae9cb8290350f
297	1	149	\\xe366f66961360dd0401aa59215f27d22c95fee2bc16cd904077c05e3b2a5954a47e6128ba8ae5e057998bd21434bd37fd637c715082be6b4f590ae21640a6a09
298	1	138	\\x16cd42ebeb880f7f3403acc5d868dff70ece21f259498ee5241e879be588cd036305bd776cb9fe3173313ef21b1fa1607bb396b422e74cad3c371dc478e28b05
299	1	179	\\x62c56e8691f88ac70a20ef7f6ae34630860c6dd3bee06b7929efff5357c8b00bea151f01224f21ce3d42e2033a9bdf069ea79ad6561e3bbe0ecf4f8a35e6a709
300	1	18	\\xdd466b91dd4e62637df40b4613d570d5186a12d0a4570cd7760e026de9639261fc3b2d50cc71c588365d5a268c75b1649fccb31487d78d37fe53c77cd79c650a
301	1	122	\\x9a54d2762cdf8419032c6bba389baabf55667b729ab0b4db9b9e642ead67d5d9ea9c1e8f76fa2dd1e6fed4dcdd1584b1a9b0f7fe966d5b0cb0a81fe1b7b8900c
302	1	73	\\x3630b84f79f659257ae8fcc9a3b163dab562a07431bc4d8e56723974b4809dee39ebb2291eb7c9119c8a9d4403a8cc4610da13ae10deba3192c1e1c1ac82450d
303	1	45	\\x23bf46b72bd604e0503881723d0abb86adb714e5ebb0fb9bb1d04a77194c2a0c4d777d60d30e8c52eb447d14b3dcfa9f35a5203cc52224def6ea71fbcee1630b
304	1	66	\\xbc09f7132d4be801e9efd766b0200b618d9d276fe31da1d50bb1206e8c4824ddc8cf32acf825416e3c7a421f4e6ae528a4fadebf41f2874d61bd3dfd1393d70a
305	1	3	\\x5e5ca0d0b5efc26620467518bea79dfc635c8237c90a71ab95fbe9b47d885195cec9c921a9e3b9d105a08d98a21c6dfa60dda3512db1b47e6ae70500ff55a60b
306	1	395	\\x98a52e06cccdee80df5e02b01eb6643ff5588fa7f31520509bbc3789727d74c33e3660e7f918d71c6d97bfcf864ddf5a6869588fe26444bcff7de801d395ce0a
307	1	351	\\x0e2cc0b30c80852b73537b58b55d1f89e7030cc3d375131e666c2fafd28e799822306bedfbaf486a01ac3a47abd12381baea5a4e2625c227213d240e6d3bd308
308	1	391	\\xd45ca9a202248517fa892153c2f09c93d375f7ef90fc5699520c9347632fcbe41b764a1847c57a3431c0577eef012735b342cf99fe06d6a5b21aba10f7913105
309	1	98	\\xfa7e63acd7723f8c370d984a6315356443f98de8b4c7ac783eaa4b06ce43bb90e14463408acfeb49b980fc37892859af7938dc7d86cd70d5b5856866bb7a0107
310	1	224	\\x0ef914811c56aeccf089c71f26949a8e26255e58cc98d7cec1a25ff3713c167fe063c03bdeb5cdf5d299dab60fa037a8134b9e2c7a781712c9f9f4fe009c0a03
311	1	4	\\x2de93b6b27f7ef312bfed0c4c0edd6c567409f7dd77e45e23ecfcd1a969b8f99077b28571a37203b952d33dbff7a2053bb74a23dffad34d4b24c09195201f603
312	1	161	\\x3c9a35d6a310eb32b251c0704bf126e431414a92ca133f9398a7b23982a56f7f8478078699448d321bd4b2a9da40f2f81720a45af1eee411d23fedd8e71a9b0d
313	1	97	\\xdf01686f977010c52eec0a22ea8fea2d9ddc26e95b11790d8f4fe7f93ed937c652ed259d06ac2b4d1bacdca8c4c95641383efb6691006770b6bb060efe48e00e
314	1	99	\\x7ae0ea4b2ef1c146e9dbee6b3cc606b74f90a3cfd173e0a328629dd388526879d46eb096c8087f78a2fdb22851de5757b48da68b8bbd8884402a6c9f73a63e0e
315	1	355	\\x57fc1acf74c91487aaf73af85ce5a13c34514deb6ef8296ea33ad66a10a8656e2df3459cab2f9d6fed233a6b55fc30214d45073531406cbfb16ae1df689e7403
316	1	298	\\xf1fa5715f9e6595075e092596f329f69e96276451340b0e4bb63d8013d19964715a86c4831086fabd5d9c0afe58cb404c815c3b31ba49ab971147a0149501d09
317	1	181	\\x8b23ce601da1c731035f50722cfa6314842a8591c806ee23c1ce8aecda34d4527aaacdf250a8715301aa95d3f45ae88e8bbaf4d273b8362b606cc40a2fbdc40d
318	1	245	\\x498af78a225079769b8d3add1bfb09594fbf7d254a10c0951498ac8d096fd8d370d402043f472b907deaa3a25091cad9c88178ce9cb47657d101bfb309fb3c08
319	1	191	\\x2df036efe43dc3b3ece308d76722c16a44f2274edff28a9933f661bef8a05e456a4915733c641596ea6194a2895790375ef6d64d21abeef7c3ac39e3ade10006
320	1	207	\\x667265cfd0083a341968d3e238196f5e5d3e1957e93e53c4fb1ae6366f98c2ebf962b062190f5037aaee0df1ae3f02f13ce491b231c8ee2f56804489bbaf930e
321	1	377	\\x6f71c54282ae86fb4b29b681118da536fd9437ee3ce78af989b5f571630ff37f4f11f90a291f42245affb408522a8433e58ef72805cf5715bf3ab46e2951e301
322	1	242	\\x0004cbd6f1357dca65ddf6e76d10ec776e68e14a8c4cef1e4aea250765b081531c625d99647d7a5500e2120a61e744c06607f61e13a3e1d7d48573fbd8a0b00d
323	1	266	\\x643e48d071218b1c68f473672acfd48e311c4292c677f6c7e359f9b98f1bafc57ba1f9a7dd3a3b850ec6b74938ad5e5e6251c007472811811e54e371b2c40503
324	1	142	\\x649458b1fb0b304f6f955a5b18e1bd68444a3f999cacd6720bdf4766a4d88c23aa951ddf8ffdf1c637213089243e6763353f8dc2efc13bf534217eb1cf035400
325	1	126	\\x115170d9cbeaaa0775888b0ab0f2f062dfa4fa1c2355b27905daef173d378ef97d1fba38f90ee03d08644ee23634b8522c648cde5a28908c1e509ae30204480b
326	1	415	\\xcea1a7767918834d2fee1b46af91c3edced02aafe76b8a5f09e43cd79a630a83d1ec6e929c1c8be5814fa6416fe1d22880b8cd737f00e522ef13e3faedd9ec01
327	1	108	\\x7f39a8e339bfd0249e96f192ea2fb327a64e7ff17cb6696830c98dcd279e8be35d78670457bc8eee9e1cb0928fd31430d8007632596c4cba172ae05796072707
328	1	337	\\xfa1baf3027fc5b414ebcc2eea799157864cc7ef0445dcd0804c06c96fcdfc1af03fcaf9cf638f0a8a7abf46d6565f3a0553f1581ad6f067c1db8f761ca15a20e
329	1	32	\\xebbc4d7d7a026a896021648b0b9dc83e2c8373da05c4922394872163643553773fd8deaaa26223e777ce20f6e6ba5abfc3f4d622f67aecfed3e15288aeea8106
330	1	36	\\xfe2deeced1fa545915684d160cc31520731a0a6e18b0b6cab6802f22c30e42a2e9606c2569802c43f7acd409fdbd0354fe2e9b234fa917ee0a917217c5b2d804
331	1	174	\\x3dd4ef869c5526771a6927a649576355473c9bf559fff29a286ea9da2df2fd7627ddacf011d5a370f0f368876c8ba4470bca1cfb22c3e9b5fabc9049fd2e7903
332	1	211	\\x5c0f1839fc6c2549d76d497b85eec2484607315f2c41752461ebe9bb287404dc3d7bf7d100e03d730eb7b0d72b8ad825070f810d8681b662362a26ffb653030b
333	1	367	\\x4eec779350e83005ca601c4dfe44af5c4151074015c3c153288911e2d5cad9c03ca4b680c4134c37af6906ddd846db4adc0078b9d121eda06eb41e268e2d2105
334	1	100	\\xab261a7d7762ec8e9e234fca1177d9f5a220346f01f9aeae644fba40570968417e213ac427eed2c7db1577080c2cba8d69cf0ec892219bf257e57365667c2f0d
335	1	34	\\x012e2ed9809ddbe3a7429d698884cf794fe09225f3d4e8962ec3c797454a531adcd3dc416c8ffda9e0043329548644a6f1dd2d328a9e8c2c82a4d5e597c99200
336	1	81	\\xa61ab069e944a01c9241448de26e5906aee5ac8e4e30f7e85721b9f327f9b8c9696f8a28401d2fab266eb09939884b9749316079ca9e590e60c4168686baab01
337	1	392	\\xf875999e5c2b8df27f94fac5c331d53b7061909eab1b41b22bf87b23866216cabbf67604ca12063acd1194279fe2520ed5d8cc50d22f3df6f5b2140c9497f102
338	1	229	\\x37e1b6b23d11937806a668ae29329cea049a42495bf4d6d1abcb150861942d9d13711a44c68fa182ab6d427cc497cc3a9c95f00a8bf4c5631f6b8ef31d0d2000
339	1	237	\\xa7648707ed8c67b63c15f79662bbcca6de54fdc40600fe40df9056704d368779f7c95d72c07d4a54822699651c0a38e311199072627b9f8c3c2b0f1b65046707
340	1	76	\\xcb8eacfb3edcfdf3e8b3fd31352244246a8d66b86551d18ecd025606659e3e4550c81aee4c39ba5921b83e07f7976c0e45f52792e862bc6ff825a4765ed21e01
341	1	7	\\xde11a6b375cc894010b707f21aa6998ab46a83d703d0a2dffb9fe14faa1f792e454839fee3a5e30521f645ebe0dc2cd7458d934c202aa82999aec74226300e01
342	1	244	\\xe9b40b244eaac3d60ce421102fe57b5a92ae32d091f097845f4c49ea2eea3d78cc987e15ebef1e6f43e020fb572e511961a536d9ad305cbd16d8d0b615f84f00
343	1	83	\\x7764d2bd7b000f459fa5eac0717d8e574cd92ae5dbe7d1c0bc3ec871edafd58c16c96775af947f1d963c747e8728fada958794d086efda188ffbe0ec4baf650e
344	1	102	\\x68a8bf26f7f26657f5283210e6170ae406023abbb6f1fbf7bc12e75e5d3de942afa3878cf90eeabbb0520a6dff16fd9d22c72e1df9bc6c8a41e6f00749b78b06
345	1	364	\\x06bbafccad27013eb4cbd2d615e8f2922ba667044a004da666992462e48541e9655791232ebd08f4d6855925e95e463bf8a29a76abd3a59953d308a513d28c05
346	1	235	\\x758d5be43c474b683670bf3df5cdb4af926803a63f8b39db8f2fd235b3637d292e422bd7ee9e7455e3f592cb0a2aa5cfd39e538f28603c367490b14e5a4cb407
347	1	56	\\x73a8b62273c092419c70d0bd7ffeeb9c805789c80a66f060a8c2553a9c2a21c4bd6ec03964a45c1d7b23b57daca2420d73cb83502fd209fd39a6cabe531a6801
348	1	419	\\x1ef0e38d8c16768ee8213ace9c4c700612defb206fa6bdd49a4135450d594df9ec5320b97be3d1189fdf0c6af803627e470cd5c37764c5271469535bf25de207
349	1	286	\\xccc6330898a8f8d660fbc238bd558fff7ff2c2005c0c5262f2050d0fab2cf583dda8bb054e79110259fcabe0332a1b55737adad06160fd015fa0b36a614bfd04
350	1	53	\\xa860f5a1c82919b958143826f7692444f39a0038fa76291751bd132114a331b4db233798a269e5567c976e49ef49fb1333cbf4fdc63b212e91a63ddb6dc9690d
351	1	96	\\x73baef634377d1dacc8b09b692e62870e5e6ab120c76e0b9fa9ad9672a877a51315ea9e835fd88d2649ebab6e16bf964aed40b649037de91945d5d8b57ac9709
352	1	134	\\x5585f69f4984604437262ef43a39e5f08e97c52ae6cc35be38aa3ddd68c6e1315bdcd4bfb2b3167b0070bb132367110d5c220ddb8dd887b28d1207b34e59d90d
353	1	109	\\x5d0d925b8fdf0f413890d95cccfbff881c226b8f3d2a77720f35603f8a399f52eb8e56198bebe93d1bca1d2a32b378b24ccb10d03692f6af4ecd463129f98703
354	1	204	\\x7d5b58bbd8bf478dec4719de43464441ed6457724c0dea829b63d83cbd1e0f13340cc12689d6699a2d24f35683fbad5cf589d28be75ace4e52281f4d14339f05
355	1	166	\\x02bd481774e7e46850405cab41918722bafa6270011846e5ed9bb472fe6ce471b6eb5f5f787cd86121ad5cf975eed179660635abfc985dc1b8f3abef0ff3b80d
356	1	241	\\x1e361535a1df294ad4f37d74c2852bdb5327d3d24cd0384c2b9181a8d753d9deb14a99030008e53b8e4510192075f5f66caa2b542102f4692300840a9ad39507
357	1	93	\\x65091e350e1d60154d6e9838de9cb886bde9277ed361cda05b57f6dbf21c1bee0698c7daa5f4791bcf407e5e328d4ce69c1cc3797cb619e399bd868c39d35906
358	1	92	\\xa36e59e8181ca96e72f01eca5cf2ed2b199a1ad81ab75858bc469890c45774c3d65d3b76bf962d057be6e2a46305b80641d279713ef6f64b0d1cf058913cac01
359	1	146	\\x6a0ea9a8ce2a4022d65658a4ee3d1537ed96e520bd8534b726a7e5dcc9ce579f718cf7bd3724841b55efb3dab10a2d83c109c325d8795c7665694dc0c9397009
360	1	30	\\x764e6f6213fb4ff1cae7b8921878856bb0ae44700638c6820548e749598f271495b1c8c72ce564e0e37d2cdf5b4ddd3b4ec4b7521f3577a097fcd20be7cb4c0a
361	1	243	\\x3fb1a51f89ddcc38d0effde4ad16010a63b82e7a1e72a9728ef2bbd07c3a251b4e639bd8f735c5595173f330ee9dd3acb65f0dbef043ca5c459b2617c54c160d
362	1	352	\\xd27d61e173f654c37931bceca3af3e3a6959053e47780e251f65c17ee21ad50875289762f7d94c17cf5f114a44d7b603b15c5f599523df6657ea98cd6f9d3c03
363	1	389	\\xbf0058bf4ef5070bcf42cfdd9630fdbc196e29544d5a5b9669621605ae06db515a93dc52dbb74859bbde7dd7734f208dc68bb7dcb5059a2b00b5d53ad2ce6104
364	1	402	\\x97629cd08ef24b53d9f63fac6e645ea9d2a56eac353458ced281e9692d9ef76cbbee7f1ee963d9b6f1acf68cbfff9f8f7ab84411869a119cae36e1ed9e877b0d
365	1	339	\\x553b492f9e77d0137d8eaf38697cd73bfe5274d0115ff5ed701be45d4bd36b02aaf3c3671eb462e0618495cc5a953d248fe695ff1b0e5192a1312f52468b7d0e
366	1	188	\\x867d84a4659ae3bdfcc5b90e5e8be57dda96a0d4f8e152e314404db8a91cb0ab5aba288291be0039decee83d0a7aa21c41d4cb97e3a902382f8441a722086a08
367	1	236	\\x441da16f1a456809b26eae14420440955a37575108edecdbd265169a323dcd691afb7b5fa065dea265ea10fd9100b5845137ba2e092c7171b4e28764fb012107
368	1	420	\\x4a30081fbcee17d70cd0a586762394974a9b6a4d2e9f0ddadd018042fad6ef1f7e472c23fdf72644934c97b1d1b0df3d89946fc85fef4e5f310599b43cf29603
369	1	357	\\x317737788f392f3794f05b8bcf6b2808f4d0062ac8a759566aa416f6b7a62e5d3024c11e0297cb591d691c2ea41a1d6e43ee00641e7d926c28215b92e5e0d500
370	1	137	\\x8b3284603f2353e24c5d2d296d708494d0feace09ee49143cec4d415b706828234a3270e598d594ecf1bdb7d92dba0263f725f70000f0706ee09d14bbe538a0c
371	1	403	\\x9d3a9db9159acef8058b677f9ac385481b1c441f8b48e5f6b1958c766ba102b6238af50b4db0c36368609c7d4620f37c2bedf45b81fd741131077a8dcb352e02
372	1	55	\\xf1fcb33cc7e679fa6e640cf3573cab9c83ad504d0912c7392ca5b288396c7992af1328f881ca0a6d9527e70a5659ac1430e6d88245b632513718dacdc51db601
373	1	65	\\x4917d1ccf1ff1331ddbc4dcda369e177d482e8db0185c9be7d51c04b31478b9d901ef3532e2b893ac238d87e5ed2c35d12648dd73cf3932660dd7a0e7937c30d
374	1	227	\\x17e7c00efd1281f2a701a631281b463c16391981721a4a5669ea540a323f2febacdb9991a0de838ded4d7f98499ffe10d139d2e12342e6a9c0ecd5fec1b3d002
375	1	329	\\x772ee1e56b7fb0adba622b7b760d5514c34e4bde024fc7cf270a65bbc1e5e600bfe011c34d9df6023e01b2cf5a6c3f37734a8a54e62c5c63b252bd6162bf8f05
376	1	271	\\xeb93245ecda07e496a8f25243cde871af2338f92af782e5eed0924997a5d2a0b91c63883eea919bfada493720053f00ebfc4abf8c5f18d00939a49be1cc2a90b
377	1	424	\\x9d6cfbfc0818d052a81a06e9cc9e567cc4c82a7054da9a9c13e446e9934ece19fb1755900039c2831daf51f3c0f753eb087c671f4cdaa6701f5d8c0f1b00f30d
378	1	406	\\x54a31631f56c3293e70639bdab211c06757ebbb983fc5df2298091dec77b3d500da1eec41e3566dfb2b37eefcfe587f9a67908260693ce963231738cc3340d02
379	1	350	\\x15303a02972e9019e672c86459c3319bd4f552f755b62b04c0fddd089e86b42574a80d0e9d11b594482715ffe1b60d4e6754511c97d770f279b3aa5fc9c5100f
380	1	270	\\x5b979bddd5501e8baf7b5a767d4be954bd109d25b6d9a8b967c123741be9fac2b53054ad1c078c578e6aaf2ffc2d8c9459daefc252ac97dfeda09242f09cf809
381	1	195	\\xc4c314774c40f52f1967478d8d8a5508b7d5fd0da0922c61e8ff0a98559d53bdb571c7fcc64d5818bfdaa747bc63d52069aa2919d1dfad18261cf062e1c8a10d
382	1	194	\\xd58cfbb2c69440713c6fd7c70024169585a258182de98883ce63065288e4c8caa9dfd98fc0e20c43e5c6edc99f43c07349462ce90bf7235cd536c14f3c574903
383	1	180	\\x7748df55e72b0d6731c062e6d47e03a57101372e5300f33e8d7ee3efca16c8840b8e5584fed95f76edb7b503d1600c6435906fccfb4de033b469767ef528430a
384	1	344	\\x0c1625fd71399c4e028cac4c27440e349ccd413dcd1a3ef55e1a61e4172faed92b21a85a1435664a0a5e18e1de0ca867a063570b5f4a331ffa85a238c8f52d00
385	1	254	\\xac72fd1501c531100d085160526fa084327aac9c48638f9baf4888febb980d4235a128324dd5b09c442852c669a59880898c468ff4d398966a447a9e6c00890f
386	1	101	\\x1032421e1bdc85af580b4942f58dd209f507c4b2d71e0b7c749474d9c6fccbbe92e7ea7c05d1fbe3eda7d1c242a835b29491447aa833f36af63d489dc9b1f103
387	1	363	\\x4c57f4fb8c59c982c97fec6fbb6ac8d9d12026d06011b94150c2fede5caf9f57b3f1d995b98388d4b43e4db10fc17b6b76a4f929d7f49d6ae362786046326609
388	1	38	\\x836ede093e8859d0bb9f1dabc85e1e20d2b6681aa411615fc574300fdcd1d46b50a87ae60580f680b3d32077f948ec01926ae6859bbed3d897776654bddea207
389	1	13	\\xaf747383d86a5f744ab09bf3e3344080cdb7b78dcdd201dd3e2656d5930d0677741c4c7597f28272bb1bd7acfe292a5cc3810f07778fe26d44995644c1aa2608
390	1	169	\\x393bbb8920d22122b836dc581de2c9730e53e8d78e0befa2ba1d8bce02427166d6ce911237a7a19f46a5ff6ddecfbc4e10aa66fec45e21fa4229f4530fa61f0c
391	1	223	\\x61e9bb284b81b4e288aa56b40ae2b9ae5876417411865fd79410d65dad135482efb6e40f33329ce822f6a65cf88bc1d6a130d2d952b5342ea5701803a8fd590d
392	1	324	\\xbf253c78fea4d784515f4ac3764a5e0105913645dd1a7c81fb1beace4a6836bf5c9763391fedc0e785f8be7accc522124103e9624a253f904cc8e9f73e908c05
393	1	196	\\x4700cf0104584354a8d2b3e82a8dd94faba3be3b64e2c6e061bcd0f06758de2fb846b986622ca01bd19b11d598ed0d17fe5a907ccb528686c22b4d6a7d312b0f
394	1	119	\\x7d3e73fd810623a4f2a7854f02cf244e58ec2935a4de9bb6b039a43107cb4fbc6370e78a1eae50cd1f0c70c843fbc0a3dff9071c76617d324b271d029b7fd702
395	1	362	\\x1588d2dda35372211e41d06723a89c056210d411435f15d17c082bb18ed50b8e0fe86b774a37e327a8bb403a7e9d709da37b23604602eda15756b014a50a4e03
396	1	103	\\xe816c098edd86a409a492d95619e538a8c07552f7d6ab9fe2b397ba4b667c24d98a5f7bd5d050039f462c9f71a28106427a16c7e49686dc88cd272ffada72304
397	1	205	\\x7b667e746de6909541f3d62026544434c460338f3bf6d59e0c846259121738c312cce1f73d557c680f230b0adeb2970f2f04228bbedd745ec0df4408839a8407
398	1	153	\\x0c5c7171c72542acb249f50c7e0e4cdd20c8413eeefc3c8fb36873df0f794e7fa4f9af619e436149441806474ea1a0dd016e84b7a0ac04f25733b0ddf99e0301
399	1	71	\\xe73690f63c6bea6fe69f450a0cae5ce4706adfc7c967f717d6250391e00c7fe871c6d7350832e6408be69cfcbb0446ae01fb604a5aeb4d8f2b73e2c198b6360b
400	1	225	\\x15c76b487bf82e60d4cbb44a68f42b9998e620ffb48b556aff38c408c1272851b2f63189f3ecc7113f0481ad30fab1494ff4deb3f1b4b66854f5c46aa95ef60c
401	1	201	\\xbe07058de943cb466519ecab3eb13eb259175c4e3ff395b00b67a0dac0d4448c540e7c28f3631d11507ad972558c300047c53e8f5d95bc74d40cb2385f47f307
402	1	264	\\xaa7d16abe5526c1c795776bc448d9e86d8171222166875a82da34a323a16693c2f453224bdd4711610634ac7235c63ad1752be55e744d31866c0b3bbd7976d0a
403	1	35	\\x4e6f9188876212375a142c4e5f9af126379d5edc96645e0753e27f77313635cc84921420c60a31e3871b61d0ff6ca6391b8870e290662e10c93bc4e7a174c80f
404	1	358	\\x3c2d16eefdc1c162aace268e7c7cde2863cd36ab6164b8aa829689eba45f8f7ac730fbd4ae3ff64e5fcdaf986fca78a3b67a57ff026014715963e635b3d28f07
405	1	346	\\x6fcf020bebaa122fb619b5a8d3de9053b7f0e225e61a1176c3b88e4497e130558a477a03622824a5c19b4d33675777853b83ddd35bc60131400623ba1f088307
406	1	268	\\x452dd53986076c9e6cbb0af1a6f8cac97402b5337e8a4d9bca0af35d2af8ec4a9068bcaadd38bc8093c5a98e0a2aed304bbb48741c7220209e10ae1b2147e90a
407	1	388	\\xefb086db4a51b2b48723a637d1118f986d096e973dfa8533e1f1d398cde92955304bb6f189e640fe3cc45bdbeba4222ceb938562bee218bba32c91253820720c
408	1	123	\\x4f2b367417d0108aebb5e11bf07d8ea991e3ada2a231e911d283272407fa07312ceead3739fc0709a7a01c869d12aef92175832dae979be4433899ba48b94f0c
409	1	46	\\x6007a7531f357b8f2ae686d7c5488b28081c8f3d368cb86a95d8e2d7a76b363a71d9e680da133e93f0792fc6d42c61666b26a151547dcf9848e6d1b03768b102
410	1	269	\\x36e3622e89a175df5732bff7b6f8cabb2e74d5cb02f8089ad96aaa1ab508e049114209ef8618c2dc29e0385500d1cee0dbfc8664a61f86d9857ee985579f4f02
411	1	328	\\x8c46a0080789550629ef406cf6bafb4816c94ccda4410d2821d9c82c52f39096537366d6d858595e14f5ac1188514ae1315d43ec196128097436230f9827d705
412	1	1	\\x493dd91678c1de839ec89a5ec02ca9f9a9e6b457f5f550ced77b0734e45a06b2280061b6c50231b710b431df7eebb600827c01d5c8bafb60f8789143a995510c
413	1	125	\\x60dd364607e98eab6d5af5577bdc06ae8db61f686256a8d891f0f6929ee7095c51c02fc54f71071b9c074045aa116ec78c805aa89cd78b902090a2de205d800e
414	1	202	\\x869ccdc1c724c3c2e8d306b6dcea8eb518e3054400ce184f0d5b1b5cff27748bbe01cc0a1dcafa041e40bfab3855a9bea1d89097f84fe8f1e8f048647c80860d
415	1	307	\\xa8c7b19f5ec29c64fa91782e7efe138b0b0976aa5787c913073d47eff091617b05dde87e87964a1f9ca0c4c462d57f3a5e1c84a121fda43e82d72f6b344c5808
416	1	58	\\x0ca8700abc8d245bea3eab88f2e1c2a7032fdd2668a667a64173f4aabb3b5cdaa21f17bc647c0d429b0a58a384598110eac587369398baeca2aa425b29c6f506
417	1	323	\\x1f957a7fcb6b4eee33ec427fb8966410787df5d0c5edf7e3e16f9eb573571bb8faeeafccc36ed50e0458bb08ad2b7382237d08587ca526f46c15382c8d7b7502
418	1	413	\\x83b5029c76dcfe6d47ab2939e28223466fcc7685cef4424b728ae7bc531646f426790c73007dba61f1b49b7a1753c4f611d9f7c951a9e469b61e88e5d5d02d0b
419	1	422	\\xd3c2b6c982d1aa9314fcd0f76519ab33b35b0b6d9b7c89a4d662445ae08c85091f2286ebee11105dd28c97f5496424af923b791576c924ebbd33ddd3f153ce03
420	1	50	\\x3e7a75edd056eb01d22defd627e1178a8d71749d7e13c107e45f18a85cb436ba5b029ccbb75bc9e74c033aff1be40fef82dac5b4e7e943024c9f80e76370f303
421	1	124	\\x46011f52bda0a7ae361c0e2baef9249e74054718b2f6b84dca970c7b936252df29843bf4f3df0ee1bd02a02a16382827462aea4f07e2c831ace994df097cb703
422	1	279	\\x6f227a6d83495aee2308a7df7821bfaf133016189b1fc5f7c3d9237d887a42d0f582506a0a43fe0eb58f06ab435fdaa694c290eb2a8e550dc4c24e167aa27603
423	1	215	\\x9055a3a70da8fef3c534c34ea99c6a071ec82b5baea1619fb7e49b93f3ef794021ca1eccf2467688292c2d3ce8f5742fdb2f56fcce2119b77c30d18d51b17007
424	1	8	\\x8f55f990829b50a32993469f8e07aa5f9e8d00f93ac17505b05030825979b1a340930e5a23eacf06171a67364784ddd1542a99ace638fa4e3f97d24e3038070d
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
\\x74175231b10c949a77973b7c17272cba1828d55e1e9a9ce2f1c5296cedecdada	1648383393000000	1655640993000000	1658060193000000	\\xbd413315b061c030627e4d29854b5da20b7d61b575c38f7a02668e5437efad07	\\x58c2d5f009420f46a54e92230dbda0af8da387ca0cfe4e1d0da513ca59642e034db3497004b1b441fe7bce5c262a9ba6aab50a385b013d914dd46207d5047d05
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x74175231b10c949a77973b7c17272cba1828d55e1e9a9ce2f1c5296cedecdada	http://localhost:8081/
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
1	\\x6635eec97619a7c26e95d31b4d08881b5e57a515a3b97015da5a5eddc26ef9cd	TESTKUDOS Auditor	http://localhost:8083/	t	1648383400000000
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
1	pbkdf2_sha256$260000$QdC9YTTcFMJPb8ZwWASCNx$pX7EQ9/At26SmyEwhb0v+/qLU0+TempH2owdoXC9fJU=	\N	f	Bank				f	t	2022-03-27 14:16:34.010443+02
3	pbkdf2_sha256$260000$CMgyCl2CNaZIHfKHfWmcGk$68BqEVlXW2Fmai8Ul4W6EkdBDviBQhhsIPr0smZFRqo=	\N	f	blog				f	t	2022-03-27 14:16:34.249105+02
4	pbkdf2_sha256$260000$PO5BAMVVOokFFX4Zsx550R$N/0ro9wk34dYnH1BrFHsNWizc+z2lFokl/9Hhu1iSr0=	\N	f	Tor				f	t	2022-03-27 14:16:34.367583+02
5	pbkdf2_sha256$260000$L0tYM0hzodnKbPpQ6q9vu6$b7P5fTMo/mAaGfUZ1A8bTeS/aKICWguw3jVJxCGQonY=	\N	f	GNUnet				f	t	2022-03-27 14:16:34.486824+02
6	pbkdf2_sha256$260000$ZLA40mytf1T6tCd5vvXVRu$G95oNC4iF2D6OyH62Wz2QGsMQ7iR2BMZuLFXG+FBvO4=	\N	f	Taler				f	t	2022-03-27 14:16:34.604847+02
7	pbkdf2_sha256$260000$5R6Q4JJv2W1kPERjj4Yq4i$oCfRPMyiU0qQzUZG+dn3C9960nvaDjY+DiT1XC+glJU=	\N	f	FSF				f	t	2022-03-27 14:16:34.723486+02
8	pbkdf2_sha256$260000$bLQTx2jK7OMIUKWl4obsjT$Wk5rqdWoV40lGwUOFDEje/UykCRgm2xNwTqc6yTFdZc=	\N	f	Tutorial				f	t	2022-03-27 14:16:34.842219+02
9	pbkdf2_sha256$260000$nXqs1KbDnoN2MINRPqIXPQ$JpwAGUUAunmyw6sn7sIqe9rwQh2/ZmvfiegBiF6xJdc=	\N	f	Survey				f	t	2022-03-27 14:16:34.961036+02
10	pbkdf2_sha256$260000$SySdYpKTMEWnjTS0RqSuZc$1ZnW2mh9hyced++V7F6RQxVviE9vSZF5QKQ319OiMYg=	\N	f	42				f	t	2022-03-27 14:16:35.386392+02
11	pbkdf2_sha256$260000$Yr7oaKLjYNRwnlPdPFonS7$do7UNQlQREN/N7apxEqcSIDdbNjc4XMY5NDyMDDbnIM=	\N	f	43				f	t	2022-03-27 14:16:35.822645+02
2	pbkdf2_sha256$260000$ROufGKbeLgSTNKA2d61aSx$jf4aI+MSy4IKxz8Mn5xYV7GRqmCH2/nnzraT1XfP5SA=	\N	f	Exchange				f	t	2022-03-27 14:16:34.130237+02
12	pbkdf2_sha256$260000$R7Mhk7XHkxZUIrffHhqa8w$Qu+MdjZjpoMoyKPEzycmuAqSgPV/v+SFGO8/4bSiSGE=	\N	f	testuser-doobfhei				f	t	2022-03-27 14:16:43.238425+02
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
1	422	\\xff45e0dc24946eddb7674fc3c4db97cc5ecd49746f5d152bdd9478c4c1f570ab91741eded8dbd2fc1d955b17ebcf0d0e715764c76383ccfdecdf817707ee1405
2	125	\\xfd588a2ca0b50210be6c59bd5780e2a4e2453c334eb643d9de5d57b9d7713b227e71a0126783701ec15b041ea4af41429e73725fef490df60552c1606f1d7002
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denominations_serial, denom_pub_hash, denom_type, age_mask, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
1	\\x01805943457d9a680841f037b0d20f496ce85e56dab5f69f64362c2302bc43f2f78caed65029508a655f416858e129b06556ba59622253818ddbf92cc681fe87	1	0	\\x000000010000000000800003c3a0713f67e5c820510b770867a19ad0a3050ac5441618686df030cb253aa6ebce0bc6ea294cfe6c8b0d20bd33ea2866d12718d21f490cd8d11e28bd6b62ccd6b06be3c7cfb6a5405d4d3cd1e0b8fd281e62a39b726b0f51865d5bce45d117ae7ae8c6318ba4a8f587df0bfa3cf971d4998ff3eabb5d9edb960c63cd8372ca87010001	\\x24d4aeda90b3eda346a72f69f220fd6c3a41ebab5c5daad9a9f99a3d5fc9ee524e11a71c6a81e2d9dc6b216305a68cc1e6c2aace0e9ba9bc9dd1e509d2224402	1648987893000000	1649592693000000	1712664693000000	1807272693000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
2	\\x01442740293d45ffec15d7c7599dfaeb7902e5b039b1c5a21942fdcbcc1fd606a74b7a7027eade586a8237c9246542b0b9ec178f3968f46705e0075e7a038905	1	0	\\x0000000100000000008000039cf7b5fb7e3bcabb52148227981f8cad4b5b4a12ab198d4c9cb92585416ce07b0e330c5d7757e5f4e799c4980ccb4b4dd88d4f1c18b7f618a4fc26c6b809d7dd38fae209ac4164e5626ecfda1c12af728db45a189a9f773cac7c0617e499e22b1a28d1495638818bf370616dc0dff4d5d5f9196b21b2f1ec15b72ecb9d14abd9010001	\\xf0867b86eaf5e1f132bfa1990557b8c73e81c890f7501ac2b26bdb241285e422c50dc3ceff163389012246a09e1e510a8ecf7c670541029ad10937871161400a	1679212893000000	1679817693000000	1742889693000000	1837497693000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
3	\\x03a44d9c2748e72d925a66db33359b9ec2f86d33f67bc9cbf0c2f0dcdde8307e30b5bcf80ecb33e12d1233ba3952dbcfb191561ef992b56a406ac01c726195a3	1	0	\\x000000010000000000800003a6295e6abce680d3b3d2e205b1ef536620d283c5a6132d44c18240b47f337fae3c71594f1836f76543585306151c97d5d019f5a89e1e9b84a01556d53aea89c1e2a73a1fb4b4191e6e5779ef10e017ab0d78d1b5e404f6637be2eb8aad9edcb4ef0ad121aadc2f62bab93ef807933f789c30a13d81b81fcdb1e230f5735efa33010001	\\x151e86b46b492e44159925e1ad8dd3f482451bc2b5a58b341b116fa78922c4198a331a125519c655c31b0f7eff6fe8c446d14078a2e8b7ca9131eb2c9744b90e	1656846393000000	1657451193000000	1720523193000000	1815131193000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
4	\\x04acb328b31f3397dc96d78bfc2c13577e187278057108954869a31320bccc96fa090c2605990498df9f744964cfa08a31c82ea176567895405461a6480fab36	1	0	\\x000000010000000000800003e9855f0a29e184910d3dbd76171c33f8e5181981e1b21ea718042f00ddf9d112c9a30267123ea0bd31569c9004718ed719a53ad93e409e737f9b61e7c4f96741ddf45c94514837dc6efb1f9197d998a28c0ac7abc2a62793591c6ee71448d9b7787913e063cff5a675811d2d31d70eb72c3479833be50cd276e0ced14625c313010001	\\x3b4bdffc42a873cf6a5c67320fdd9a35a20fbdd1bf8af2b34c84043128336fd69faf0fd5e1dc054ddcc7c2133f97102cb971dba22d37ed8c07abbeb17b609506	1656846393000000	1657451193000000	1720523193000000	1815131193000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
5	\\x044ca625ffc795e2e9e230ad414374dca6aeae2d1f92aaddb9c6494d01e7cd716021498943e9d427e2fa4980f95d6301f20588ee85e5ba8fe527a90378d53039	1	0	\\x000000010000000000800003bc2d5e0fb37753fffdcb9c77a48713672ef12b61e7b887aa019c7c24be2cfe9d6932fd4ccc7c01292595c3d7a6558bae18a34552ab81eb740ada1124beb34ab72234c23cf355cf6408969ce6b9faaef8a7bb372f4b7bd3d98031c3bfdb44b748f07dfe1ae7374e73d4f0ae9359b38457ccf804513ffb2b27213ff4896197a121010001	\\x5f6a081aef70df73ff978c11fa9e746a145475753a3aab6ca6ad2830cba439ab367c5597a707abb196a9539ef32f8e6a58f8d7a4989623f197ec96a5f989f301	1669540893000000	1670145693000000	1733217693000000	1827825693000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
6	\\x08d83eab84fa56c2507cc1d142435458e2256b3c0d2f4263ea3fddb4d4f9701c9c7f19b6d73d9c3706675a7172a28efb669852884fb3b1faaccf72a759ba8bf4	1	0	\\x000000010000000000800003b82c2ef703f762495111730786a5eae8b476c1cefebff136b210b45475493576fae65b3ca99bf6c975a542f2fae76e66b503abc69e9ae4d25aa98c7972ab6bcf0c0d9a29ac706beb4da460b1380191e39e832ec4ba746797a787bfcef996a2ec5e0c530ffb6ff310291436b3f157123458ccd72b7da91b38517acb27822d6363010001	\\x1c522b58b15250ffa8cfa57a246e6ebad8236061428abc386a6b392eea58a74815d11e5c01e2c83722b27944cb9075302ac18a565ffc963968e863ba3e1f8b05	1659264393000000	1659869193000000	1722941193000000	1817549193000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
7	\\x0af8d705a4ac8fddf7dd5e884fb9b45120ae12786bd916e352001af0bbfa6e973069752ab78da549fe60dd9275f4f848b407c091578793939c5448567edd3475	1	0	\\x000000010000000000800003d773aa84ea1f51ca294bada7d883661203b32ae3e6839535fb96b6cfa13aad1ad57e375be31bbae4af2f6f4688bbc38f9732dd7d02405c2d1227e5503b30aae57d3192e986a146bff4c1d382ab2de6223ffc669bdd1a1c7ea6b6377dcdd50e4e5334796de0919b0b8f9ba7fffe0a3c7c2ab42ec0350c202d431615afe25a3277010001	\\x5d78c04d3bf9ed847e559dc5736f9d38231dd4bb4b1dffa27d783ba5bb4b882f3b4533028c11fcc83df5c6fe7007f852441cefb273f54a87b01c307c8e86f10f	1654428393000000	1655033193000000	1718105193000000	1812713193000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
8	\\x0a401a61edbf283ba4f5a2f4cfe0e05069eb0dd0e4e7f33aee0007fb046e7b1fc2a61cadd6ec3936edce18e512bc23377141091a8e38711f6ac5a0f2eb414ee1	1	0	\\x000000010000000000800003ab3d469bb429b151d7862d6abccad3cfd0c767a1dd9d0f50c88c5da801d8c833ff45db2bc3ea875b34ad6f4af6691c8122027d088ef3bbeafc090ccf93fdd6888b45e604e987de99839cb2d0c3736100dfd8c97b8a91d7f50a45436c80422e697c90fee8f9cdfd682ecb5fa6b5b0824ec363044efa9cfca5886cfffc6f655667010001	\\x3d1c82e807a5776afce7c1282e3aab39ce997022fc17720b7a23736ab305e5fc22fe8a20a0fb6bf32999b88736ef578503f9b3d48bdb79fd08512fd9bbc95203	1648383393000000	1648988193000000	1712060193000000	1806668193000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
9	\\x0b28fd2779007717fd78762179e4bd12d5c7292fda7be244822d9a736ec8d99922001c1814665bdfb98110f5fb94f1cae173bf23345a47b50fad0f5dd901436e	1	0	\\x000000010000000000800003dc05b287685a69a94542297e42219fc72b53521800bce461097afa46311b4fcb0c4889a4ece3918f34a97c1226692103093b967b47633e8b96b90646de45877a6942d93e5c86b14668eb92d618fbecb83529cbcef1f54bcbadec763d0cb4c884cc6051f1f6eac31cc0d8466a90787a7e1e1374c8dd83089b89b98f45238983cf010001	\\x12efcf9cbf54b281a335589dc710984ac86a75214e03051a4e8b0c79b1ab7a175c72e027e860ada6381cf2648c54e95cbf7f64f07ef21df2a1622827b9ab2100	1668331893000000	1668936693000000	1732008693000000	1826616693000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
10	\\x0ddc3922eb909ef135d1cf9ccc6e2264b314f92e20d158586f8c6c496d3245f7f1b27f5908b9944578da1245d17ae2e39caffaf322a957b1d6471b3eb0c0bcbe	1	0	\\x000000010000000000800003c91c9833e5dcffd4b691dad53710c8f768f8d1be0b7c25b1623697095a9ec07c5a2758775ac4cd1999183dcdea1ca542326f56445434f15ab5d5f1d6c34dc1d802ebdbc4c1dab657c411539bb0905cc13827760ccef5cd1511abd229a6f0c331d0bb8cc0fb1cc64f62cc482db7305e98af22d99fff576511cc05b329c427609f010001	\\xfb62d57052928455100e68fc4e277b38f08ec48c4826eee436c513b4234748c85372b39ebda8a0b73c429958ec3fdce8d50b6ce7393fbb2b44c36d4603bb420e	1678003893000000	1678608693000000	1741680693000000	1836288693000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
11	\\x0fe44209cb296236dcda29a36868623c9d1af27cb2ce84ca50b910b0d8288fa23aa805644cdf589a7941e61d820191ebc8c69f665235573fa5a36524539fc4d7	1	0	\\x000000010000000000800003d89e14f56b8039163a5d6775493221fc4e86e2e5ef61a12584d3161b1d8f0db15100471141b7e6b6739e3964b3ce7af530fac810cee1ac677dfce0c6d485609340c2e832dddcded870eb78e15dd4909fc49a334f3fba2f4ea5056bfb067b267c779d072527e1968e7e2d6e65f487893a3fe6088f35300cac78d81c76bd67b215010001	\\xad4241df384fe4e8f23d868183acdecb6337059b8d0ad7d9a59f60820004d7567fc8c47294b30f3b2c32b03b2e81413cbfe54c946a075ef00e5b0b37eecb0c0b	1667122893000000	1667727693000000	1730799693000000	1825407693000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
12	\\x0fe42d3869edfe8e0a7d3f89a22f523de431682ed9072f421bb6a877627a62c1282b954e14557698c822065b5891f2d35eb259025de1cb305612f2e042749620	1	0	\\x00000001000000000080000397b2ba93ecc9ad49363668b7c4c0188bf9e829ec45f75ad8a00c8b318beba2827f0e0a8a5ff784cf57cbf1a874f93e4fc9d4b15b5469619dada0f9ea82c3cd663c18ee1dd98a0813d8e317fcdebea18fc47a0d6a8724f9abeee844ce413dae178e63d25b8191f33174ed2bccb43a1724c5904abcea67ee99128235bc9614b633010001	\\xbd8c6731c845d562a1718d42e348fc32337043832448b87ff5096b6e2a10b0260f47408409e37afe58b80a32130baf1fa2612c14d5e777ff6a1d397512d39603	1673772393000000	1674377193000000	1737449193000000	1832057193000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
13	\\x10fc69eace15ce0db2392d90f0568721e20f7c906c3b65ad7e725d2c6d9baf960bd7d0af6dee6ec5b70c56f799f0ffc04e337d682e23bd3a2e86ed007fc225ff	1	0	\\x000000010000000000800003d4551af352b579772c9791e4768402dcd7734473a8cbf6778259f60d3e0af3984971f4bc46f651cf34b59ecf0d9c0c664778eaa6e7a87c720dd4b4ad31fc649f00b7687c8778f2e7465f51ce23fde335672902b481446e661c35158a0b1b8fb5e9a01c72e7a652d00ba9e73b857b7ce1f3293dbcad62d08212c9800431bba557010001	\\x3aef6bbe00d7ff15f104f12c72a6c108a169439bb7f0c0de5cf71a0e568d73f0d83430561edc2447e71967ce23731e19457b13b536c58ce5a1a62fc26d10990e	1650801393000000	1651406193000000	1714478193000000	1809086193000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
14	\\x11ac1994658d056b4fffbe85d4f24934d182144fdac309b5d16cd0896e6922d4ed6cb0b1c17e559a14c72a780e48220e09fb6cd5451a9e1d91097824daf48aab	1	0	\\x00000001000000000080000395bde88cfd1ff3c71d0df099f2582b42c8c40db7dee44ed68949f9e13d76790a131c4b98d3616acf1307058ef7ca05f13f50de3fb5a49e56926d66f62ee3e490c135a92477369d9dccccd948bd286fda6ebeb0f0a9ca16b2c63f1de29f0a0eb82050b3e37bc25282074bed3f922d8a22a4372010e2d6e7f05812f81d6138c0a5010001	\\xe71b1b5a109c66c8468d27e7b6a117d45bd88d064cdf9ab13159ebab897c8d63eb9613b213aaf1cb0778a3adddd05d4a32d0ded42289add2e874a66f26fc5d08	1670749893000000	1671354693000000	1734426693000000	1829034693000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
15	\\x1554a10089aa69d9ea19194f8e3d8d0050092c26f59b660333c0dd06bdc8ad6539bc735c90fda60b0dae9a823e710bb9aa4d61b07ecab476f36082b3851fcb15	1	0	\\x000000010000000000800003afe1051031c7bcb9207b97e9501115540b6770a656fbb21c0fe58217ddd2a33d92b9d2c8630eaba44952c29deb5fc5a659a29c99aabf80d832f181bc0614ceb30d2e6582250ac5c2e4d8413ff5a317abc82d0bc16f343734398b94c30b9d8be37dc4d3c38ee7a43e6860a777f393d52cbeef98543ec6f7f9e1d5f12a7bac1c71010001	\\xe203849d83b6b739281abcaf7681116d7e32b7f37d5de7d5628b0bbdf395012a7f411cfd1ff57b4bc8d863dd95b611cee8717195cbee52e480aa21aba5be9b02	1661682393000000	1662287193000000	1725359193000000	1819967193000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
16	\\x1698fdd3a5a22c4cc44dabb9720b9585c4ea35aeda9c3c957116519a7c7a039aa3c3dea5c4cc65142ec83a8236f75a6169b0dfa5265f82d3cb9f4d9697606fe8	1	0	\\x000000010000000000800003d4af402b5906bdc4cfedb098f2527221bf09e0d93cd784486d08bcc324f7d8d115b306566ae77e685135e0de1d25f88b571b643236db3307580cd926dc3e6317a31d18210f2942ada7283702d5bd4b1144225d620a56c7a25a052fa67ab560b0273b0c5e1134283b5a6575216fbbf181e4ef2a82b0e793c40e551e81d3cf9c65010001	\\xa60a9843e1f5453b90c00c2e998aae7fd8cfb5e4f33e4251514a9cecd4e6a972586589e687609925fd5751e6bb1aaffe5a240bb5fdd1fc9f80aad10fcecb4a06	1667727393000000	1668332193000000	1731404193000000	1826012193000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
17	\\x16f8190a12b397b602afe00d95288c7ce1aa7be8bd4620336f0e209a43d10c4bb6dba40f9d4b1baa074c2cb79becfaadc10376198170345c938041c31551aa08	1	0	\\x000000010000000000800003b674391c9667cfcd51f2534a4d4008c4f766d553a5ad39b78e52b317ed79fe412ad1845ddd4bd79c1cc7ab3d3066716ec97eb17682cb8279c1e1faf99bf5f27bd91a80de8396f881519bfb41dccae5fa17a15f248658442af77a26eb238c7d3e04e8e0d839e8a75c551034de2d38651937a5b4778b7a102239ebe44712c6d343010001	\\x76f578fd2936f85716c5426a7c0dc33211b4d3bd250f706e92d180d88ab7114571377bbb724be4957c4123fee9152f7167f0cc4b427f6c99a34894ed21144006	1668331893000000	1668936693000000	1732008693000000	1826616693000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
18	\\x18186dcc6075c5fd838222409c5c5324fee6b731c6399a53101f935c9352eaa9d861ae1ca58c85c038ef613916aa6e59375482e82142bd674f30291dfdb62d83	1	0	\\x000000010000000000800003cd8c196a0ee781b3b0943cf60807bbb59004035db8ce9daf335f87a73e2469fb19bad63c5591f9a71beead45bda11804989050c72a3a653e15001fc3a3d4818546483616354e84631314fe68b39bb947992e04510c54f31ae9a4e28ded0b5d706a1ac8b176f68a0ce327bee87874b120f527d5f5daed4fe9c8382f650d3e9cf1010001	\\x02741982100e54f42554689058adf71820d1dd96695863f1d1e9f09eff46fba9ce4854353720711a18729ad5bcb480c3d840accfd7a0bce04f73fdc1c7d02306	1657450893000000	1658055693000000	1721127693000000	1815735693000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
19	\\x1a6080148ce84393b777ee6e99be44a8fc55c7794d35d95f9ab0a5c21d9249920e6edec01e3c3aa7cdfbc093a71cde994115a94626da9137666f139522bd370a	1	0	\\x000000010000000000800003d79f09be1f8cc13a0a346c3010bef47ec348142da337c92ced609a962acf254677de032359fe75885a51802f92fcd68209c88127c133fdbb535c6b0051f646bef2c4bf39b5af393fdcad116b61a37d1a340c9eaa03c53cf5af0a4a32a896da6725a6aeeb174cf08acdcc7dd29d0be26c4bbaced311d611172598d4bf74dc345d010001	\\x37190912261d1376a7e4ed17b849156fbdcf6cd0f382fabab54365f592f91ac7d03f1112b509bccd0b8bee7b56dc56d63a310324a06d74bfc41d257ccc2cc50b	1667122893000000	1667727693000000	1730799693000000	1825407693000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
20	\\x1b6491a8182e049a23249ee31d9c951b7ef380563f1127c3954cd7e106e6d9838aed5a895db93a4b60ca2c8706fb672817d1e68dddecf4eee6d3bcc1a9332312	1	0	\\x000000010000000000800003c029f56016c99b72b66dbe9da287d98c06ecd74d7509000299da49351aed448cb5cf17cc4833cb254585cd31d59e04f1eff56958b55f04a8fc13d4113dc687b33be68ff43ca26480f178fad315f01ccca4634dea1b2bb7952dce2cf47867d8a9c295cdb2ea4ff619e1e05e4f411e7e60710a712e286fe153a44f09ef2b888fc3010001	\\xdf869e48300c0e82ae15413b3461e92537fbd848c279505e3e6e2814efabd40901260c306224eecc2009b512502d28e924a266345d1a4b05d074ea0428cf8c08	1665309393000000	1665914193000000	1728986193000000	1823594193000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
21	\\x1b588b4169694b61e5adc7fb2b603f5ee27240643ed2de7584ae1bc58c8d6aec794167f2dc4a1968ec1bc38c5790fa05675413172c1585d2ee63f16a0657efc2	1	0	\\x000000010000000000800003c2f612dba8edbb1de029894a74d338575becadd46a4d82b2d52f1baa83550e96319efdd9d5273d034c687bc236d5c703c701ac3f2ec113998523da626ea2886b0b974b5a661a1d1ba74c73b8fdf247ec07d267bb33fcce7d329794eac0ec3046c81055dec31ea6472852fd2bd47cd8a09048cda47966f9d951b43ba4ace64a29010001	\\xccc477ca85743149a63b5c8533e5e00e5c99432bac5d4a42d94ea2a51b5905025b3122224387e0dc7ec988d6ab949ba96217ab56d42063069967d8a1a67b3f0e	1674376893000000	1674981693000000	1738053693000000	1832661693000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
22	\\x1d68bdeaf84585bec1a8ce001d1334789fd928dd0e54f96917e8b6dabf9d2050af628819731ce51233817fca48e41e878ea916e188864b885852aefc32b3f09f	1	0	\\x000000010000000000800003eacd075a457f4e8fd876a3f2d68457652636e208e0413210c7372e5d771865c534abf21583bbda04421933d91995ead6aa946b6b6e1e69ffe0acb9355f939848dd694b030454fb03b2361eab6aaf19f596240f3808b042be21fd897a7854ec50991d2c80e25bcca64a65f9f5fdff4da75d4137ebccc364755cf53a67d2447fdf010001	\\x72e83e0acf73909b9f39486049c34cbfcc25dd984177ae69ac35695badb2d7340d0689d0f95ab149fc52a4a63d03f9abc3420c8121cf87aca382e3bff2b1f70b	1675585893000000	1676190693000000	1739262693000000	1833870693000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
23	\\x1e5037d8edb7de5f3a58a324b99fa5e9c59485a84f9397c892c87d5f5d9f12d74daf4895c4afda9350ccc46b6473588436e5ed6dc469c94d3a3617d22ab39542	1	0	\\x000000010000000000800003bc8968bc137d508e385958093afc75c871eeb206e1b7f609c0c2c949fa74760ccc38af8b875303bb5189368d7f73bad2d92b2719d6bfb434277b49203e714636c556f377b82a483d3572e0da22f320a06a6056c474885495740923b662cba6520bb9225d9b04f16ef583bcb98e74d26e2e4578c74c058e077b8f2bac116afb13010001	\\x93ebb56940d86705f643486d005e1937d47460c1bd4414f2adb05192e6b969600db340b2791a7ac386bb16f3a417e06ad5b2b5c8a118431ff29874f2f4ba8e0e	1676794893000000	1677399693000000	1740471693000000	1835079693000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
24	\\x2440e5b39ef4783cf670bea40b6e956543726b3c0c3eba159c8f6a8ff6abf2a5983e50489a275045830699fde79be901505f136be7667bccb29266931972ad80	1	0	\\x000000010000000000800003f4052b6d2aef39c75e5a851e79c21ee4d12756065c941b94f8497e09bea4343dabc8b2f6db5429ff1d1389dedb5010461263dd80a464fdd19c86061c819f551168fa35ac4b0e43db3e5fe23e858ca1f520519746c3be6aeef36df1c323fd3d49b3dcea52d3a69651122918f49a1f3a3ad56c10464827aa840d2aba0701d6491b010001	\\xb08e024c6da1729baab5ea2d6b4e8d18380f091f997e709813d00f1c73eae8593d790daeee4acae1ff032bf5c1e845ee27c1d9c17ab6e7f5f29acfb813d3b501	1678003893000000	1678608693000000	1741680693000000	1836288693000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
25	\\x2444ddf92e755a6de535252785994e7bbcd4da39d060e8419027844845924451f97b69bb0b650bee99eb4b6b97ee875a7d5d25779b8877e45689542b0fe8f0cc	1	0	\\x000000010000000000800003d3e60b3065b56d6f364866b42d1890ddb4b317239ccdb671823841bec4ff3f7221e471fbdb5f460b5d5fadc6f335052555144de1b48ec3b20ae9e4da8f752137b69e5872844fd122a30065de6c9a69bfd2aae81f85a39edf39b4bc219e443229e911a3bd4901f0c6d2590898aab9eb2166188ec520072bc73d935e0ee53af38f010001	\\x9266116adf9a4a23e6fcaad52bb213718bc85870bbc6a8297fb7c6cebd9fbc4da15c315e3071cb91bc5a87d95cbfc9d7cb941357d013c64cc12a8cab53f76c0b	1664704893000000	1665309693000000	1728381693000000	1822989693000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
26	\\x2608b4558a1344a34bb9f64a4ac3031cde4b6892ac84e0a57737de5783f036c3752b6f973042a66e24790d5bba3b434ba45af2ad868243d678c17fc8a56178f3	1	0	\\x000000010000000000800003ad7efa89f40281f8fee941974b8f51ff2d474841d17756a9f17f58aa91d2fd997f14ca3b4b19e21f6912e1bf4187b3b2061198441c40f56904267560b9b73adda8b614d47d396ed156b3c55fffe5b51e665a0fdd852dd81a3de6060c995db27e657f7d51791224bc2ddeebd42cc6ea8e200bbc1d7bcc1e52be5d4f1826fca33d010001	\\xe29459158af8a61af858329c6a51eb520cbec09616a7b0a08519db60cdec99dbb9346a071de1e647bbf6265e49b6d5929285859e82ea7fa40a3b6d978349f704	1658055393000000	1658660193000000	1721732193000000	1816340193000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
27	\\x27bceaef333e2bc8cc233fcc2a0c8584f9f3821cb6f66c3afe55514fe6e3f2cd8cdef2904f2a6370f57de6a93aa6f53354f100bf0f8fdb34c8ab5f402ef8073a	1	0	\\x000000010000000000800003ae9f70ace6599b9d4c9c8321738788af0c9362eee1154e2649b884abf1b2284aa58edb98192a24d87f02008453599f98eaa8255aae27dae13b31c87403ffe77c899e6990f2617a124171ade187a45c0deb3d69b8fff7f19be1d14458abb2cc6d9188837ddb74e50975e8e7c606cfb3570d723f977bf123706f49ba6533c3ef05010001	\\xa2381c204d05e452efeba6449df0cf352e14ec628aa6ad8e7c27b0cf09b4b91708b6ff5676c261438c39339a1ce2f9aa2413f57d3bc4bc8a797ab65e44d12302	1659264393000000	1659869193000000	1722941193000000	1817549193000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
28	\\x2820cd45b8cd285bd094b1d79ad6d47192bdb033f29767b4a77b2415896a9b6509affd1886d13fc61d107eab9ad9fbe0a94cf6a2799efea36302b865e1090b86	1	0	\\x000000010000000000800003d18ba7930164a44da6cb74d65837b27ea5d32e475a56e39f8c12301c6463ec053b6310036dd74668a0355ec9d3bbe891f0276aca187d2aa6bd9f84af52ecff8457a4dbcf44e9f0fff65f73f38d82659dc8d308e620d5c7f21126baaf20565bace78828192fcd926b0ae028e561e237eea9d129988e95a9a87daa9c18f4a0ca35010001	\\x0d13f5cefb0fcfcfe1f65eaff5d7002126c467ed119d2aa96c505b58fc0a40b1631b32ea92b1b1c6735c129520cd4c129c3b3980f31e51a503d050a019b6cc08	1673772393000000	1674377193000000	1737449193000000	1832057193000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
29	\\x2a40e6542b815f5a8386b2c7347a8d62d762f1d79ffad3a213e2521be7043e5ce9ad9d92563716fb2fa90345a008c5047947070624f5bf767b3f22d3615c07a6	1	0	\\x000000010000000000800003e6cf6404aaec23336297b686aa6d648c63a3757f7c664ffdbf4a46e4bb3c70307619e3911ff9c0845eef487cb96c0aec2b8f43ca4a8deb6d841f368744a7f165513b3a3a1428f4c1a76fa206bb449071a5df70a777085089b3a95f02b000d7eafd4d1f1c3bef04ae857c777109eeef31dd97322c4eda6e140a19e8255e9dd90f010001	\\x94295bc18d976d193ddcbfc0c498b766b301a041b350537b03ab6f415db755a401e6620318afaba0a02e243cc1b20a0807c339be2db26db5a34d60c55ad7c403	1673167893000000	1673772693000000	1736844693000000	1831452693000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
30	\\x2fc4108cd55fc6f50c71b0621c042c6e83befcb4f763d684098c95dc69b3111d7c1bc4b4995496f4f609fde8f204eaee81fc5a80647ae2161fccb41394c794e3	1	0	\\x000000010000000000800003bc2dea08ad85e4589a5a2a0f61479ab079d7586f4641f2a75087d87efe4b48b5344c0442f58ed826ee2dda3d61746721221e62970c84821331fcf696a7a74b2c8f1cb059ed44aed58c7f8b0632c3b356275475f484a23415f07b476f873ee8027c467976d3c4242036bf771bb159c560c1b0f29b08459236f51253180412ce5f010001	\\x22d3beff3f1ebf0d6d8c53abbc554c6705030edb49f707cfa0a57578ba2df1dddd119436ffcb100d67fdfe0754886430d3d26fc234ac7b3cc65c5db219a5ed08	1653219393000000	1653824193000000	1716896193000000	1811504193000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
31	\\x3080cb175663f736f62c3a828cbb1f87458469ff73601a89861f3fc0632b79a919045c3be711f01ffca9b9e61287220837cf8da92c22d80cccf5715c5de96086	1	0	\\x000000010000000000800003b3959dbce7fbecc3da446b83103e4682bdeb4597559a3c0e52a86dcb406ac81766e5637f5181bce570adadfd04dcc265416547ab796c4404330126888ca38b381506c2b0a7b05f66b0d477587374ae9ccb8b7a5ecfec362da658df25f0fb8d77f1d662272da8be8bdf2fbc982a5976b196fabbd8ffe601ccd04832685a60a603010001	\\x5fe288d0486b9f17c0012ad913222f94ecce970ce82fd6fef25904f3ec2dea02e01dee87be647957864f927453220406ece8cf595079fa909195f62b2a9bf00c	1676190393000000	1676795193000000	1739867193000000	1834475193000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
32	\\x3380be00a30147a171cd99797e7798206ec3f80c3cdcf2de565f1bb36c4c906f3a71806de7f4370904c0fa49567911b095a9ff8f6644a00c191abcc3b08b81bf	1	0	\\x000000010000000000800003bc2c306434e13862308e4ad5819283755bb1df40010c3cd3bcf910505e23838055ef0c10cb1b0aae3486ddfc4ae6bc86b0c651a5516a0471b71131cc30c7dbde9d89f738ab9df19027a8648a516241ff5c180804107009551df50527ae7c871364dce57a5631e39726519b9066dc183ef4573e975cc7b9c33ff21fb911fba56d010001	\\x8f65ff9479721fba8ed52f65bc1f4cf8c6df7f66dd747aee7005c4b00099212b808e3ee61331b40046123d0c83945a9465e0b328e8dab6d94d235395e3255805	1655032893000000	1655637693000000	1718709693000000	1813317693000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
33	\\x3770c039864d55dddb323ad829e38cb691afa527a273683ae364142c5f736c18ee06bbb7ead0202aa21b26e959ef5e6bab8d7935ac005f071692df47cc35aad9	1	0	\\x000000010000000000800003bb8319d72c67ca8c0fffd3cc4ce70671168a8d7653b8647b3293fce282d91f890eaf04b6791dc895fe1d892837b45f276246a2870b5c5c5b608462d6791313d1a95392c4bc0cbe3a45f152969ad6c0fecddb15e93f557dfae0904fe5a5bdf05f32300f5359edb396a1e95684b8c4d1569264a93c90bda756c9cbdf0d5f143f5b010001	\\xdb8b05d76cc8d1a134b141b55c2a0defd4789d78a35ceea237211e1ecccd97752cb061902efcdf76bddbe54ba3615758966a054f36fe1311c1671560c117630f	1658659893000000	1659264693000000	1722336693000000	1816944693000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
34	\\x37f8e65c792e24b30269446dd48267acf7fd95991187ea3ab88bc97c4300757be04ce89415978dcc391470e72a636dff66633963c20494fc7bdae7ebcf1df518	1	0	\\x000000010000000000800003c2fe54e7a061b3d691754612a735dfb4c4c0f09362709e8520d6aa56c19c110e6b2cc4f1596a0e6ed7712421aee67c8de556d60026a1d9212b8ac6c0cc62bb56a5269c59e051cdddb682d51c4f3507fb8e13474af35067c677db5aafcdca6e76a2b5715f8b9a7a28c8831ef874dc414b4b99fb80990b2c8851ee0b23a9058b73010001	\\x0e5e35942deca1879a13990d6c31fb900ee45b7e9a2f656fb868c3698333be4086cda11724a5bd88bfa3428390b9778e93034d612335263f767cfdc192cbc809	1655032893000000	1655637693000000	1718709693000000	1813317693000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
35	\\x38d4daaf4752f38e56814cb928c85ac4177de6fc645e263e2fad2ae09f553ba60eb1a7ff797587ad3ebe69effbce35757ee36c8aef62110c2140069ef91f9f2e	1	0	\\x000000010000000000800003eb8e5c7d1bdb5b8e8e08bf0fcb6dc1adc99e015b06253fe16397acb8f3bd0083e78fcc7f4582482145059f8731d4370817d671b79fa6c5d544cca5c825c5b220901683d8d29475d64a7a57d4194593974a44178fc6d88c43cac08ee9702c2cba2b2140b57ef39e7705839d5c279e7a7f087fd71078a5ac7c101cbd1e690258f3010001	\\xa7fc466c3eddc58362f5e0eb6e95214d84841ca55c06307a4dfe41ceff64051a092ca838badd92376b038320276661db9966fcebf4fc1e15cebc063844c0670d	1649592393000000	1650197193000000	1713269193000000	1807877193000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
36	\\x391c6b6b435b42d88611e4c0de035781afd8a0217a8e80d57411cc67883958db3d52cdccb659d08cb114cb7237d274c0d04a8a8cd49ca04c44441fca14aa939c	1	0	\\x000000010000000000800003984cf0c1bb6c635733a91a3764b68da1470df072826aff50f7bec71e015c250ee73e1a0733a10e96a783107a5ea3708f169cea91babe58d7142e2f64a0fd6e22168596f4ff4512eb8d5f37aa66bd7ac0de45008c95b29a571a7d4399dac1531eb4de69f6023949ef8707d3a79678c4efcb532c2204a68b79c46cc1b46b85b3db010001	\\x4a852c1b32d2fc9038239fefd7d00325e977214ce14033236e89df64b82aaa0eb5624fd06f849aecf9c2fb9bb14d40ef4d1527c92a65d1d0ee7cc94e0c67ee0d	1655032893000000	1655637693000000	1718709693000000	1813317693000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
37	\\x3d2cb6aaf2d739fd5e67e0afc3eb9876f5de3eac12a95a8ae008eaafe65b7a7873803555bb7624f2d4f3637ed761f75d2e2b66ce674cc23246129a0699b2687a	1	0	\\x000000010000000000800003bd3fabed90b06b8e277d04614e2d0a8129873d7a07a3a770fdde45241da9f636be122f65dd97085026ac48027de28aca2b15c494e20f0b087c100960b0a47c7721336f5417a144424a3072beca2a5fe1626605f0acb62d4394923f67ee954e0f9d415a46b3aebe8e38681373681cea38cf573fb5c01157256676833936516abd010001	\\x80aa2052b41ad8d2df8e215b3be6978a673f38790b28942bce2dd55e23c8ae8ca9f29370f1ffaee877e11e72af296c9adcab1fadbdb00b39f1cac438bb3d6e08	1665913893000000	1666518693000000	1729590693000000	1824198693000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
38	\\x4000399fce93bea369b9d90c7ed51bc60c34f6bacb0785dcdfeaaa023cd490a2dfda776bde97ad9c2212dd167311212eb7a4753504c3fae3ac3c3fa8b99ea547	1	0	\\x000000010000000000800003a9db484a9e15559b7d7434cad16154869b907ab5d5c79065c756e644f5f5ea0642d59b86e2266808b19c365feafee530a90bec59045f38c8cdb8ab283b0e8642b8dae58f05d3ebf83c508736403fbcd44dfceacd854729559235b3bb8bb3e5243657d5dcbddec39924cc5dfa53db0726f167da65aafe3f20046a1528b300f0a5010001	\\x83b4b100fdd5616e0cefddeb0278a2a79c029ba1c85bb999043e98ff7661662b6f9988e526859bbdee8164dd09a08bcbf7ecb2f3a3e8dedfdeabd11f370c1b09	1650801393000000	1651406193000000	1714478193000000	1809086193000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
39	\\x410040434806c7acc07ecc9d5dd11e22307581d384a556f7d2b8f8735a84f0d1bc99dafea3f4de1822c4fa156bf2931acbe791ca472a428190b6426ce860803d	1	0	\\x000000010000000000800003bdfc3be9ecbb6b82cf96045af2adbda8c681bde16df642de2d0e24d2686d50aa8dc01a3c9cd10db32ace381fae6e2c55582cacd814ae0b04b5c695a330c0f75e9ce23e0d558b17afb9f379e66c387b192cd354d67452726fa911c2a48717f2fca4edb02d80afbc9ebcda1908c6b44d6a5b68c2cd222624682c328dc7514dde33010001	\\x70fdf483309c85577c7c6eb609930ec35c6d7feb8269d52eb0be8e3e1882b7ed7b423c469cbfa0183df25f8151eefbd2c7f2f67c7dd7295a233d19d489f28e07	1679212893000000	1679817693000000	1742889693000000	1837497693000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
40	\\x41982fdf485b7c537d9ad24c0729840ce8ec78b7753bbce742fa1180c7103838e25b5170557a06f3be4316d6f9fe01cb9c0f1ff0b72ca121cf12e1b021d38beb	1	0	\\x000000010000000000800003d269f75867990945485aed00a01a1bcb3d50ceecf5eaf8f94bb02ffc06fabe267ce0781f898ee08f7060c30101d6eaa3264f55b4a1736cd56d144b3d905cdfe47865cf920cb31a55fab394d3f092a563cc1c475a2f3fcd34119d5738f92b6a7ee69f5d75c2db4c151034ef94fcc992c2a4a873ba0bf2557363b787cd57be204f010001	\\xbaf7a23155dfd2b4d8b6e68f1d1e03b46f9a8249ec7876b26f65ddb3050b8adb41b3c595a5ef02a1151c4c46eba66cc12d6902796eaec7dab61be8c6948c3a05	1671354393000000	1671959193000000	1735031193000000	1829639193000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
41	\\x4440ceb3841ab8f5a2f053f1bae790f0d30d7e68135245db2ed9aa89295c93bbe8dbc2a97cf73f705bf44bc99b9d2015a49379af07b11b8bd8c4e2c57b6dd878	1	0	\\x000000010000000000800003b49742cf5e3ac203f93858efb0e85f8dc7972d47c2f5db5bd8e7860efaef2771c34484f33c0e926c46d75d09d644b692e1107c15c2af1300a5b7e1e9e4739c8eaa6f3b0f0649bddc62cbdf97f5e8b0904f24696ffc787151b25732753d8d36c58c7d4b58b809de66e77dd134cb65393a8d93a136bc2e0f3e85f1c55b52b0b48d010001	\\x353dd236e19e7f83e1c84a880aeb16f7b1c39d472dbe3433b697d9ada33333d2d3def7a6ab30488b6989d58bc358f300c9245b26113ae8ec9e0b86fa93497109	1673167893000000	1673772693000000	1736844693000000	1831452693000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
42	\\x4a1c0174d3839d2a87e4828992e189e70152711e96d9aea2d715803a353e7dc1ece83b8d90ad04149df0aeea8d76bf0f236fc71595807f7ab160303a5f66dc1d	1	0	\\x000000010000000000800003bc4dda41ee32ffbc524ca1e3577d1f16d2ce1ab63ee6627aaac20246ebae1b98059ae65a8ca01ca9c00af100ecc6f79640043d30048980e8b0a16755b8f1828447eac9b7388fdc4e652364650af1a3da05f12c36a73d75ff491fa7b01c18a5825f18c1ceba91782d2d6ad5faec6fe0d32ac63eb6aed76773ba6eb66fbad09cad010001	\\xf947c304aa143021bf1bd6542606314f1f4c9acbc6b162012c1f0023021eea71800f9c7d88a4dcf808e439c8ce9a63c33509e5b8a40edea8ed8724d46ba33504	1674376893000000	1674981693000000	1738053693000000	1832661693000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
43	\\x4b7c06c9034bcf33b145677442cbb20540ee4d3f42b3cd10a710ce4f41648067dea5afdabb2be3121e14dd7e29f816f988c97dedd6aed22a3ce6df5b1e163963	1	0	\\x000000010000000000800003c89073115a7579e4282b12e1a6e0700254373bb1fcf02d2767e4d30c55f42c46a19746fe8f6c5d9c10ae6387818812d70ae2edc80c4335cdc5c8ad713341fedbfb1329cd8e75c6eaf1033a8598358d103c424372a50de380cf74c0b14cd6bac17b11db882b8c2db6859a41ec00c7da4b69594edf15587189c243edb0ee22c1e5010001	\\x02138e6b31252cfa77467ac6301929a0ef3ba4c228a4a98389aa7590739f526d5eb93c81adcf06b37393ad9927b9e387b71bc7d6e40152ff4e365eb07db29906	1674981393000000	1675586193000000	1738658193000000	1833266193000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
44	\\x4ba0e56181af7e872063a1c99d0c2a4f33d7e83842ca8e21e90280f2045f065840a919c4e985843d563aa1cf1f237a31c66eec7de25e8e980116549a1f06e4d9	1	0	\\x000000010000000000800003c50c0ff82bb03b7e4838aab7ba7b5d8bf7219ac0edb98c6c14a28020aad5bb0737627241e09809208711cae22f01f18c3893c5e63185b04c97676e695b33fd7a23c67eedc84248de8088b9ff7880e6e83740c44c71adeb0eeaafa061ffc55d8002de9e7e01b54f8e2fe349be18384d71dc890d63a60c2842a0d336a1971a818f010001	\\x9f61e0309bf949490c5f3885a9dc16926de4e35be7f0d57c9007f63faf84cb64a711c9b27b9eaeafaabfce44cca9581ac76fc8d4a6a442855296896e8c84ab06	1662286893000000	1662891693000000	1725963693000000	1820571693000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
45	\\x4ecc57d3430e3ba3d1ce9cf32222bf7af65c031abd0a9bb281779dbfe9c9e4bad8fb8a1ccf8665a2c6a09013d781ac16180a743f3713ecc6ca36f1f8108e19de	1	0	\\x000000010000000000800003d0569e38f6b73366d8c5b353dedca5b4651c6ab81b28b7ee5e0209e8757b08678cfc17a185544c3cd3f488da33d36b258bbed8ff15992ba5f12cc5239a58a7c174e20b41fa30f27abf201a625c4c64a5e7dc571ce1bfeb9b4bd40d377a96070e17056878a2afd5203088e8f2d243673b64d4d26cad9ca1c462379d55f47b4e05010001	\\xe34d234ffefe7c33a0ceedec06da10103b9a073e6aefd9e83e7168f8ac078485575e223bdbaff7a0879ba7c3e84e1770da485228d36ca10d9039259fdc0c040e	1657450893000000	1658055693000000	1721127693000000	1815735693000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
46	\\x5080f5de5d95ffb93539b39d49848466451a4b0f88d4f6809caa7f4d62a425c3389ffc9471f1360c1635e74623748c2139550bb881f10f179aa18c24173a1b54	1	0	\\x000000010000000000800003d1d49a72accf71053a377799a03396a2644bf9a408807bd71283d3f311f1d5fa6750c0b69adb66bfc84f0585277a4cca10cdc3018e6842bbcdb4cd8f353441d1cbcac17630faa14ce2975193aa37e3e29564e3553936880f6acc33b8a8151d550695d057a91fa52bf3b8ac7ca6dfe6846388856c02ec4a4b066b16888cb7a115010001	\\x022cc460cbc88c63fa61b1610fa6748927aac199720dd722529ef0cd1c7bbaa4278e90a112bf7193029800bc592ffcc146c3743421cca78f6ae1d4860612350c	1648987893000000	1649592693000000	1712664693000000	1807272693000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
47	\\x51a8e5eb2b4a43ea939dc345c647136dd6dec268fa2b60cc139534fe63a1c863df47ede98df346973fa412c3cfe0d81d606b190383a34ea223343394619b814b	1	0	\\x000000010000000000800003dca2f742712260058ef34b5fc8ab69f41646f69f3c49f33d731b1afd92caefe5b33ca9d97b38caab78917f35b9b55f63b79f0bf0fd541d6dc8ff852a9d9ad85d05235b356ae2530000d4900355919043aadde60994c6f26a5023b0aadcbb6a7ce22bf2a90a46fa0d0aac7f82344a67a18ffbb350d4a4a17f2648541f6f8a4573010001	\\xca9b6dca7a32029eea19c1aec83c5eb851adfe3c3c381b954f23d978aa32d18447eb4daeeffbb07a9ecf7a2110ba3f460f98644db2b8eb05c0679f2c1ef9320b	1663495893000000	1664100693000000	1727172693000000	1821780693000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
48	\\x5204067c27be88cb554568209baac22db767f9b36556ea08b8bad4d6996be64ec909e0d6fdea266cb96d67f8a0ced5b780c42f9b36e46898da249f49271447af	1	0	\\x000000010000000000800003b7937af3ceeb807242aa470945c4999a0fa8f09e7c344febd4772ded1ba641f7fd3480ccb58258ffdc37f2bd6f6034b5b17f8bf604f9979441d3e558afbbab355d04a97e52a158062830afaab88934d41df5a97d80fb1584a880afc9540ab57f5957503a1bcf9747f0a9124ba8309569bf50e7a75d3512519aeda94fed79fdd7010001	\\xbba9c754ece331d297456ee3739299da04834de4a825abac8b6a9bed8d05467e115c030d67692c22c1376d6c146843f359c6994f1daf8662b1443336265df207	1658055393000000	1658660193000000	1721732193000000	1816340193000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
49	\\x5490fdae117f55d9a912a43c942a488b9c4eebaeb26a5121fab2914ad9af5f718e9f9be37601b98e66bc4af298f2861813d4a7333754b3b46ef9d1e5aeded2b6	1	0	\\x000000010000000000800003cb364919b9a4db326603fbe7a6a86e41d57aa7e1604b84f39ad017eb3a6305e7011e354f6e4e15310bb60b6b14deb111cb7e92776aa15d9be907960433b7f24311cdba4fe4eccc268eb1b844bbdd10ef2f8a13b236a37ca7099b6973b0d22baf468302be0470b937a7de16046b6df3a9ca8488222ce189dc78ccf011639f1f07010001	\\x4708084ee70842dde3882c22e5720bce5a77d6f4b31305141382e9dc857d4846b287bc91208c7ec60e5521feb28571f0a8a54a0b20959ab29ed431a078c05c06	1678003893000000	1678608693000000	1741680693000000	1836288693000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
50	\\x55100e8f1f1a1289336bb6f281d3c1ee020b19ad433fda89d7a39897138db28a1ea8d1c44377725fffa82932b5d6a834a3ba4e59f2bebb335cb7387a70aa0e92	1	0	\\x000000010000000000800003aea20c4f9c75b093eccafa6496e093f9273f48f3a4e8ddce640481c1417cb28b98eeebc8ec3f4c7612b9248f2c1f0cca4e3b6a4b740a3401b2fd98e36c0f04d5a9cecf1de22a65eef936082e7547bfe4b6e61dd8941c61307f5d0522009b620d5615186e23b6abcb95af88c9fa3c4691207d4b1167917ff43617d6d805ff4749010001	\\xe55c1aa7c866fa096092e4021460025a3e45b1c918678b92ae68412aa12aa3070f183c1ac22bd46bdf291338895175ffd17229ba9eec51f5b18f48c365ff9503	1648383393000000	1648988193000000	1712060193000000	1806668193000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
51	\\x5b1c5115a4439af738298af9d9ef3dee370c95a2698e5f75c44d7aa39fa62abdd22cf8dffc6cbfda566a0f8cd1a14a54abe3245cd5675848050d8447ef397c70	1	0	\\x000000010000000000800003e0484ef572b7680456895846e3fe001112261f141ff774ab5b6a57f40d30bc91622e58ac035b1ca9f8fe6a8f0916e15bda6b667430873f6dba29a18621a28512d75452bad80ffbc25688130b096cc346622bfa92d8d8233c6da793ff8c518779c216ed49563b7aab4f748c95cb3872801b8f23e15231f5571842880f528c1573010001	\\x4ae9c9062867805115cc9972049f264bd158931ecf6233b7404562a61492a37724abc8bd441fcbfdb44ea89bbebd999b3c5e8807fb566c6b9d17341e4df3cf0e	1670145393000000	1670750193000000	1733822193000000	1828430193000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
52	\\x602cdf303ce56f31863ef85302701820b6b9149ac329e05b383dc412b88920f6ab13a8cbc9d8fd781223948d41127d0deef291813771c77398a6ea684cc7cfb5	1	0	\\x000000010000000000800003f6438d1b0c91d3f7417e2c910225831029fa9992050e1c019546f1a097a6ee8e55d3b8503192ff80d3de8aea2ac1a9d69e555abd343dad0da50a1802d7584c20db04a11c80e29c1fd2b6e0fc4c69a0f74039c66fbdf29d66f800bc84680760c2f2b8e56eb0decf594db35bd735017122e801cec3317e00f45c894fd8a98fc635010001	\\x8b88b2bc89c0586a8cd18b8d6c2cf425d87ed2441947ca4ec191dcbbbb216d47c59f5b9b5c66f1bb04f839697243ae796a427a7a586e5ca9901f56890fa33c09	1664704893000000	1665309693000000	1728381693000000	1822989693000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
53	\\x63ec0058fdac0a75604d5e30ece3c72fc1f7b80fdd73781790f396a896699c9f8970431396c915b0672265b7b75316bb8375410e817ae6856954acfba43f2072	1	0	\\x000000010000000000800003ca7efa45cbb928182d682d306998002fb69bddbb09ab505e3127434462d391297607bc3eec161c4f68a097c9960a615da535040d0e3bf373bcbdfe497c77ab8ab8a6947a6b3951b6c4aa09450b7e21259025ef1c6512eac91cc21cd137ec1907a1c5bed87a62f1e7341408219888ce1195f86d658c43a9befb21f8e3641347d7010001	\\x000a95e521ff5690e52ca0801d536a1e3b1d93b571a5d59fddcfe089def6beb6565b796ce35c36897ce2f42c5fe08572fe5302f772e0fd30a871c62d6414500e	1653823893000000	1654428693000000	1717500693000000	1812108693000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
54	\\x63aca638cbada2d250417558e8301cef4d4c79200b9c1929861e0938a499f623905d8f6ff095b9db42bfd2fa06e939954467d84053b20599b2ce380da38bc364	1	0	\\x000000010000000000800003a6ed257234c7143fc78a1243d29a087da069c37e07512872b74f882a1ac438acd0fdde2a553b9b44e1f62fed55013b3d7c7389262b1b3d0506748d6288ee89728939cf315dde6877dabd33d751c599989f6a3b177f0412749346069642205000bd502baf17a35fff16ef0d166eb6febd31ab519d22f87a677f4e900915948135010001	\\xcb13994cdcc4fa51736214f6b3ab7f240eaa9cffdf344ff0fc3b9c46fae89c6a2a6f429a5fec221d8e9751de2688d9b8f5586b4a6e534b7f4099a3be504ea90d	1666518393000000	1667123193000000	1730195193000000	1824803193000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
55	\\x691cc64c779a84241308ca1e33ed70609c8480c114b499fab8b1729c0e9a9369b59c677c19e3c5f3b8df796fca2f0cc2f80dc688caf0be8a6ee626a443113910	1	0	\\x000000010000000000800003e17d079f3c94aa6672e4d24c8e0369e1c846eda8102dcc8e17d5e6ab4b21a16e6507943ad373a411ba79522faa74f75e9fd16e252452aa1d08aaf45aa240f689f536ac2e58a29b292790bbed14dd02ae1e70ff342bf149655414420992a61d048744a9d39de27f14a4971b77f4c2873e23822aac3c198164b0e18642455896b1010001	\\xee80b17d6aa4690cc777882c83be7a23967ebffdbf13b979e02a864735993fd533974cfe3877f6f56adadf6befa8fa25bedbf030e9934895c9074dd248afc009	1652010393000000	1652615193000000	1715687193000000	1810295193000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
56	\\x6b1406c4ab6ee53049f13a299ee59cc5a7660eda483cd3a9c5f563d463cfc8cbd4e8a116ead7bb6f5192e629581622b938bfcb3bfaf6e14e895585447ad84d66	1	0	\\x000000010000000000800003a598336a7783be2ad39df7b5f7702b5711d21f2321c8bbe05f44af1ebf242a2ace2c1e859b33ac402c177aa6c5ce98564e2e7f499d40df680c9598e9a35dadb9cd7a53ccdb28c976cb7579a2abd52af135456c970f9255e71b9f27d79b3bdabcbbd567f7791e5924810f84b90943b6ac36b56ff0b9a234c93b90dccc60ccaf57010001	\\x19013344923932210f457bd4ae3cb2151649e9e732400cb0a010ad79e5ec0cf5e629e8d159974de1e601f99b24fa7e1bc7b9d06f38cbd230ba1e83924643020d	1653823893000000	1654428693000000	1717500693000000	1812108693000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
57	\\x6cbc6fa0ceee563b22a83025562445bd67a3e3c058af0cbbcccc7e1b613b81297a4a01e6cf55c2b447965c0dc28bff177b3076f48e71f44a3a3cecb7fa530b11	1	0	\\x000000010000000000800003b970e7403be48e186a28a856c841875ea3ce1fd20a0d6d8c46deadfb0c1e0a0dbe6d63a41b2fb6a88774388e5c33e2f8cd7ce7ed7980cacc4eebfb2a120eed96305dd1a488cdcab14cb1c66a3f645cdebd7729e923726a2407e95fb04ede36ec2b1c4d4922c28b5f66ce0a7ac056b463fcdf0d47231f88f551d8d38c6b619065010001	\\x0fe721a5c4906ffee18b2f1860092cbd59b02864d516ca89e0084e1a4825a8830b4bd52bcebec762988c3f1649e6b33aa068b50403a211a1b069246ee2f8f905	1663495893000000	1664100693000000	1727172693000000	1821780693000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
58	\\x6f3072ee61500920270f90c8321d10dadbfa2ccbc3ff11013561f50412e8bbfc2f7f084cc3a89d72c93de0eaa3596cb870013dc9eff7d6720f342e5ab7c37d5b	1	0	\\x000000010000000000800003be2ef48fc734ba8dbbab67f46b6111516d1ac84c125e3c5c0f9871f99f109c4c9b3fe187da1eac3a387ecd612db00ab4d97ac4f10fa5b9113c6553b120dd9209d2d126cdd8a719151e599eb9e5050224b3d659477a61c743b9cafaf7173e76216a2e40d2910128a2bda81396fcaa5508ffdb34deae9ae3d68332ff5149c9f2ab010001	\\x5edc2501e6119ad695cdde9095e4b9b7424f4cb617929e4f475469e55bd3bfb2efc127633c6ef2944cf432a9dd5e407af470a2ee1e91630e58959c3b8a1e420f	1648987893000000	1649592693000000	1712664693000000	1807272693000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
59	\\x7058893120c6f6a050a1d4a369cac6e4c9c4e4b01ecabd99d548c2b8f152cef889b670c373c013e824788018b0c0c8fe9ad48f4c7e372b375f33d07f4d8dede5	1	0	\\x000000010000000000800003b1d8638dd1a5885fbbb0331a24c0a94e98098cb4ca85a9572240dd4ffaaeab96acfdfc9b4ead4ba0b26262eb46fc8a32bf8e66dc48592ef239ee490a16bff04d33a84a5db2acddf92f6f7f940ea18c0bb4e05b361dae24a29ddbc9882afcc86254d87303aee5b2f6468c2a1235d09d575c680e00c1522445fdb4b1c0fa0b0071010001	\\xf4d04adf746e16eccc5109b4a5ddf1ee11bda47e750fcc377148d76757219dc6e19c0bd72e629b02154f528c5644371dfe3adb8c3b24ca0d2e47ca1e8c33860b	1675585893000000	1676190693000000	1739262693000000	1833870693000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
60	\\x71d8961bdedaf3c152d25d8e9c0f3b1999b9f12a1facc07529b262838d3ae20a6120b2130f2e399b7e7b26484d1cd9a3c94cd24b38ec7bfb7727ecc0527db189	1	0	\\x000000010000000000800003bcf67b7af9565740afc72c5481f11acbb3b7d363a9f724e34e75c6876cce0028dfac153e62f61e31bf13fee2d3a4c633112b7cdedaf15310e1eb13597a2ce4be26080951b8be6ab5d8eb599f0a60aac64f887dc90f676042e70b6ba0f15a5e03312a091e0880e75ec3a5f6de82ad7fbfa865f5f8da5224b312e7b5d5e025c06b010001	\\xd2c7f4d8b36c66629f86f88743a7735e9ec8bb0ccc13fd7f3736af829b9af36d0be3a3b1375b9b92303cad8f4e96c3848278cb6512d72e1d9a1874c9ac055002	1671354393000000	1671959193000000	1735031193000000	1829639193000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
61	\\x72e052f718e280c961e5b2e48338f952fe00b9475e30e58cc9dd2716a2878950dd01b8ebbb25ab22f50eb079453cbf5152ff8cff6c9b31bfbc77c3269d30a21c	1	0	\\x000000010000000000800003ce5db60e2b105c375c7c240e68d88d96cc734767cd87b74eb4b243d43a9e829d6c54c3024c7625b82200c37471765a0df1fb2f4d19021f31ae2027e56e2bb718dcaf7328f1e5bfdda2f9e5d8afb9ce400115b0eb269e12d46cbf061db7f136651b2111847bcb12dc46150e60e9f65ebffc16bf7a912d8f8715488a3f9327f2a1010001	\\xf846e4aff1209ff9469906d127d7c662aac2aea85a6a8e2235a4dc325fab98cb7a1cd85db981f21138f3bc52ff6fab71ea4f953eadc3703f9c2b199e1ee7790a	1667727393000000	1668332193000000	1731404193000000	1826012193000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
62	\\x7438b4c38ae762c810617495771038ee1a87f14ee9a303712eb650513d621e436e1f70f138056b8d9a90cff43a8f561d7648f309139360e72db1bab1f846582a	1	0	\\x000000010000000000800003b1a9256313f935067096ed34b68f7efd1ba1362d321e5bb2b7781e5cb8ba6a21e50b0071ddeaa3b7e3521fa40d1ee43d0dd3a6d67474f484e1329b6146185d3d21ad8ffaf4a38621d727e3dccbc282ef4f25711bacf05563c1f49dd854069db16c3632e81fa8add6b47dddbc96aaa1377bb38be1fc8688f495d3c9967da623a5010001	\\xb7737f04e38411d1e488586406a7ad68354dd77bf6f64500db7b0222e92c5770b32435dc68d7cb7c3cbe865bc11b00feb55e8941ec3ae6207061504df125b004	1661682393000000	1662287193000000	1725359193000000	1819967193000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
63	\\x76b07791533ecfe68b022316e9096c8c2b469cb7348a23d301da43d07c9f37d635d4bcf4386858bec32f9bf8145d1138f305443ee824af14ee1a36654ee619a0	1	0	\\x000000010000000000800003b184bb0f29444853ee86a1cf4c373a883a24aff1323f81df2a36c2888bcc64a21629d60f19f7af0dbcc07f76f66866e59f281f2224c04d5a30d737a06c723bd7f3ebd959c1dd2af146c54f847ca504b07053e481ed218281c9efd7b246233d5a22f6809dd7756a29df6499915a1af8ccf22d3afa462c5f609d2c92617cbf26bf010001	\\x059256dc5e2aafb4d5c3bdcbd6c98c1641d9fb75dc5ccbe1513048ca0c320e14be35d06a86bc738bf68c803f1a93001b77655298f19de3ad8c64223fbac1b70d	1661682393000000	1662287193000000	1725359193000000	1819967193000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
64	\\x77782276133c43e9c01bd9e22b63a2ece680821d28a6f02bdc0840c3cfc0eb8bc8ee390ae9ca8e343a176dac2d33700a6bf2d4e5ffb4f9f54f39d59675ab3ee9	1	0	\\x000000010000000000800003ccc8ec111c45ef716468fbfdeece634ada5f2a0c675ccaeca517c2a54728d6e1594dd82a683be364570e6fec6cc0aef32cf789cddf34ff8f90be3bd2f339d4c2f2a7cd0d18cc2ff4112d2d94a300b91736ee6a424da617595c0825b7cee2533d7f4a9ea1978491c5d897a5b729c310baf955110faa5e2dc06013ac9230bcc07b010001	\\x1d59222623bab7a1bb7a14de3d3ed5fd6a6b5265bcee3e3b837f5737040742d1891f501ee36e859db2ef5c68aa21c0a2ea3629b99080da892e06862e23bbc501	1666518393000000	1667123193000000	1730195193000000	1824803193000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
65	\\x77d8cb3a0b3931d77ac447359a2c8f7e62bcf1e8040188850f60c642304613c5b2a4d28c35608cbf23dc374466cb5d704b91d54849fbea69dbec547618233f73	1	0	\\x000000010000000000800003c0b1d8cc966a76726ff8a12156aa1e40cc570f28befaa90d8831d574a5c13806222645f51f2176ac4ea637bec4b5044a41ac265df23fc598eb1fc33780417992b21e67c922ee08c0bbc63c04ad030d8e8765112ab340435707007d9e307605a65c1ea3ecb4b09158e95f7ee2b9b198b05587fac0e20aa743b2e2ec87383f57bf010001	\\xcaef0ee111a95d6b8fa624233ca9948e14b7891c65d7ec909d40ec5a66b8808018b7a116b95daacf892564011e6d1fda5af47b039e41acb12fec87843463170a	1652010393000000	1652615193000000	1715687193000000	1810295193000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
66	\\x7efc88ff04883ad5d97887f565a081aa89d89ae8bcf6d026343f9164fa6bb39dc07e8fdc8657b5025ae751d7050f480f0cbe40399760f3d4066837dcf43a89af	1	0	\\x000000010000000000800003a0d001ec4d3f96007e856def410a9b4a0e98841e2ff94abb84dada50d8054a74aba46712b65c152b39ad2cfed0c6f396871eb501a90d52a35ec8117003d4e064a21aa6d12bc1d8dcb7b49e33e19199bc476226f1ff46ab615bf14c98b5b2fc23b4fe735bbe4a165673909062db666efadfcef8bd0b0de64f86086faed480708f010001	\\x174419fde362a7845abad767b2ce6dca825ca1f6d296a3c6ff3f42e4ec1dc17d60f97202682ef335bb8e5176bb2d5a23c1d628e9cf7408a02331d5b21df5ce04	1657450893000000	1658055693000000	1721127693000000	1815735693000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
67	\\x7e006f0bed7406f2228bab1ff41c099e174d178215f19ce264324e836bb197c9a24637f8e2702d7b1ae9a2056ac6aeed9c8cada712d7222e13d5b509ed25524c	1	0	\\x000000010000000000800003d7656ec5cf0f911d204f93c7e1c93c997df333905fb12bd4545a88f15d47ad53ddacb9adfbd7dffe1cc5a5021573920747eff4b0cf773259b4654a8f685b07166d9820f01d03fa98e7b9b7eb6ae838e34e243cc96e821477cd0ab9f65add2f6009fdba185594664e3a18faabf6d502107570165796da9cbe2c38f7e55db2b0cd010001	\\x8c0528cc840d638ea6becc394a20cafe924356804b296855f6aabeede020dae1840bb4a7500f54e7d67b930f862e5f264cf111ddd0b9ee02b30b7fee4e776f07	1679212893000000	1679817693000000	1742889693000000	1837497693000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
68	\\x80ec6028bd901cbd8bad8f7df4ca51bfcc741a8120de269c68bc786c942647ec0f7cbd53e58d575c157398f7a296b1f1178610dd898417e05c74b65c76e964f9	1	0	\\x000000010000000000800003aa78fa11e999f9391662cda9b7cdfe4d022e3efd3549f093f956da1f3b7fae125053f04279f8b89537978ff8d69b771e1ef37492f51567248dde51c85901a9dd2c89d91d6d55db07940cf27a7a40273d1c532894da489c7bf0404e18a2bf1ea98131559b4840644c7ff6673afbde84702de676836c8a4a687e3fc44f59dfa027010001	\\x452beeccf800afc6e821461e6dd9e54d4bca36c0c2a818233f80fdf634cf3d203d014c63a684be096edc6814700128cedfd22d3c11fdfa574358b38b79e35507	1658659893000000	1659264693000000	1722336693000000	1816944693000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
69	\\x8128fcfc059e71effa064c2726ea806f5dabf0d043656fcff74ad247931a82f693d7249b8e69a14df43e18cab59497cba3743f6fc35f8d729183c3c87abe815b	1	0	\\x000000010000000000800003b3ad70c9b3a9ec02627c7c18e51e3b3f72579633240033ff6b5ed951ddf2377d071800645e140194601548d4f8e2674b4a7e526dc6ec76400cb7a4c5be2d155a5e100dd7feb92a1555c1bd71a263dca549869e97d752819a38f9004a1c6211f68a85355eb7884366b29298d2adf1f4e2e3afb0df2654e8d86de4c1be45c0975d010001	\\x1ec27a5f2713c5f3347a03629a8dac12e1432e731eb895571b6ad2572bff459aad664ab4c084c85ae9ea3ff5c024a8a5a2c4e4c4868bef1de4c924329cc0500f	1678608393000000	1679213193000000	1742285193000000	1836893193000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
70	\\x81049bdc271e340797920700dce043b9b730c72cdb1996042179340d98ae2ad4d6c8f96b9e3c5cc59acd04379ce8ee5abc601078b4cc253bab70488ef6bd3b05	1	0	\\x0000000100000000008000039d1e7b3a87e127aaeebe0a55e8a6bb8edfa77cf173ae9a00da56df1a2b43a973bc07b2ab81e1ea1ae0468ab25d00183d07287e49ac09d49f463370064becfd455db5f98ce3c480b96b91da17feacc28e8d74f63007aa0170d261b831ad0a703c7fc5a05bdca9827cb611ed54bdbaf2dc04c4445fbc769b0aed0c5f539c16a0dd010001	\\xa443078b1b097544e4908a5417cb42ce1670e6f67fe1af0694bb22f6e622accdfd1b0d6730a73191dea45ffa69fa02de7eca3f7d6d6b8e8635fa556bc13ee30a	1673167893000000	1673772693000000	1736844693000000	1831452693000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
71	\\x84341fe6fafa811e719824e8ac84ee161529d79bfea82434cfecd5f9e25d56fc3d2a106087ca1b9d8c73b9f034721c77d49577b75b2c66fdade41fefb51ab3c8	1	0	\\x000000010000000000800003f0cd93261fd8c6b818f237cf53e16b4237a36c2ed5bc0b750ef4bc691d500e0d52c5e024268c342cc750ceabe1868010abc65ff302d11cfc641e29d58e5f5d42b9e50bcf79cf7e9feb4b6ea139e1a03e406e281f158ade7d709868cb70b8b54eb4aef825ec2915a38ab53efdd16bdbc258c5675021167fb336ea5ac447b2c8e7010001	\\x190674ec68bd890452cf8f274dcb8056090695f817e2debb58cc4273fc3bbd8a12a3fb1375bf57a398c391c8d8dc3ee7c671631a8b6e7e906b318daa67b48d00	1650196893000000	1650801693000000	1713873693000000	1808481693000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
72	\\x85f0e4287f54c8610946ba18da89d973b17f4def2514bd11b3eb944de78c5cdf417cd25377a7baae4d2f71baaf616dc401d0f2d6635d18645433b7972042e537	1	0	\\x000000010000000000800003d6c897c31415fa7a1fe1604ec017730bb5b5ba152076bff06a115a47580418f6845614c542acff54653e8fffc8c5b9a71ed149a7edd3815b4b74ad3e997f1f6de2962e6beeeeaf32207cd56565d62edc54e6dcf48201ee83e6b73e77ec552cc70524829c8aea5aed0d84821b35af245b08558c497aff91b30ad896617486a09f010001	\\x58c236b0efd6d658e755f07dc7725cce3465ea13c58ad6adbb2f7c241a8bd9a7a89f7d026778ef0f7fb11b9b55d31fc88d51025c0f77323bee9573d3ce6b4a04	1677399393000000	1678004193000000	1741076193000000	1835684193000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
73	\\x8cd4fd2a907baf1304c98cfd6a71b4e9934f1375600ade9572dafdb5e33a7f33b135739b4f77f965fe58e3fe7f70552595edd9ee56b10ab2ea8d5103054aafc7	1	0	\\x000000010000000000800003c526c49b732f646cd754810c0bcf559fc15568fb08edcc8b86792107528435837e0767eadbb722dc512918ce546049acea33394ecda4fcf23e7d5d007424acd978599c1bdc44c7307c25b0b805a28a1ad3043baaa7018f8af1bd83bd8874532478ab4035880d26983c38882e4684460b98cf9955f09e05250e51c552fe237ea5010001	\\x087efa86bfcfe9b981946f3930b70034776be40bb42013babb7b466555951bf76e2b409040b6418ebb72309fd6cc4c18e6bd5c5118f6b8ca291962b43ace1c0e	1657450893000000	1658055693000000	1721127693000000	1815735693000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
74	\\x8db8c3a13ffddb47919d1ae64cca50b5d229e5957ff4282a209ce97a8462dcdc000aad0453154e74e58757930db4e8df6f3ae6140998967a4e571bdda71bdceb	1	0	\\x000000010000000000800003f0d93894b8f7b42cb20d2de4c322a9d09a2319f0c3a38bf79177d748a615b3fdf9f1ac42fd98567b2bfce1ccd735f8d1a47c4d7f62f7dd221f2de9b0824565c7e5ed60a89822ac699fe48edcba8bc3efc225dff16335a36cd1c903a8e9328c134b8b6bd88938b9d0d0ab5f081d4704d82513ee8c88e4953626c879489b8c180f010001	\\xcbe418e7742b3c66e7a2f22cfee55165cdce0b5aa998d1f00f453dff5d138a39166489e006a0d282596ddc5e26db32ad776915f30626b5fea4678fba919d900d	1659868893000000	1660473693000000	1723545693000000	1818153693000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
75	\\x8e50110a83d383bcfd382fac72010f78dd6eed9ce56d1c9acf026490f23ac7405f62d6ee45b43ee98ded79e4383b809a3e361251b2d1338588d6c1ec3a0bb123	1	0	\\x000000010000000000800003ae10635f6ff55207fa29ff1a6b556c31e714c10d3dc0fa81daedaf712f4c7af373f290c8988c1ce46758af18347a9135893b35d129f8f72279be84aa6f6fe7d848023083f54bace8fcbf2451f3acbae3ee484f302573c1b9039480fa019aacc8aba24fdefb919e3678bcbc0543b2bf5454003db0ae015ebf96f9a469231e52f1010001	\\x7dd5032b79b7af90e93e994d340a4764ba88958e66eaf536395aa700b101f5bf21f27dde177d088187734bc80ad64767de5947dad9cdff8dc4545612fcc18e0e	1677399393000000	1678004193000000	1741076193000000	1835684193000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
76	\\x94e034791875ec7c734a3bc526ee95007dc04030816b1af93997ced6015622dc9473423fa88041b76d9955538a4e12790fbc633abffcb2e9aa54e6eb84387076	1	0	\\x000000010000000000800003bb5f6ea1a31e7c88cacb9c2106b548224e81117aa96264bd2fecd45887d8d336accb1eedbc573d46fa023812a0134a40e7342ca4a956dd97f4bfc6bb4f14f8ec02f615e1dbce77cec6a8475fb49041a8945bbfe90d2f5d0e9b750475dfd4e753dfa430366b6d4effda3bd43579f20948b6f7e8946641b46f2ed39bc847751501010001	\\x63e9ef943e65ba62a007f0cc64f76563c1e19d1c9ff1a6d2ca85f95760b0f54c1fc8d1ad3112ec8bf788c56fc83ab0193a5ca493ceec194deec4f52ea3addb06	1654428393000000	1655033193000000	1718105193000000	1812713193000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
77	\\x97e4de7d34a094a88d07515427e02c3c5c6a1bc30c2f007a46848b85a702a15b485e208007dbb2bbdcb17916d8134a5599dbe5f4c9f4671d6fabeade352bd734	1	0	\\x000000010000000000800003f9a28d9e4a8e50c24f78a5bb189a74fca9a6af31f4af93fb0d39c694c673b60b0f0c99f57d2d978df89262b1d5f8d8a2fe464d448b0cedebccfe681a657a9c36fb2462aa974dbb43eb486b411bf90894eb20427cf39b95bc672fae9c532faf0d894201ea150a18292b8047ad5a4cafecb254093c51278e9de7a9218bfa9f28ad010001	\\x1439afdab8a51a0c9db1c68427fd374a2a5c47086090c13864fc83c9dbc1ed01a3920de2b5fd0a5a1782a154e91490d09692c0bf696a81cafb15518ade3fbb0c	1678608393000000	1679213193000000	1742285193000000	1836893193000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
78	\\x9940093421bf607fc2b5a8feba053ab86dac79e381370baca37624bf5b89413cc3b3f50271fe0781ab646a416e4345bf76384294f723ce88bef34a9e504d4d70	1	0	\\x000000010000000000800003b4807b000d407a12a51f894c070c7985f0dd854171abf6cde859ae5d1c2a59a59c586c029c047eef2e2f3e9185c0e95d5075711f9a0d895da7b3becb9c5114784dc1cc7209690e56bc7d1a3acfb39e5f4bfc031feb1fcb262f8f35f17169b7f3e2f19044f34f483276b0ce190caa57cbeec651bffb72aee3e4d579ba34f637cb010001	\\x9fff22535bfc8be2922411e48c9ee503fab40d70586a765b4fd4b91dc75c0ee4dcf79216400a396f51a1baba7dec46123c744165f8711086bee91181d640d208	1659868893000000	1660473693000000	1723545693000000	1818153693000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
79	\\x9954404df20c445441c3985c60e9cbe540c3dec4d4cff33f8f72b82746dd1c70ad5189c8fd079f6cb3501d795424caf0a4284abba92033ec8469e713b6393c0d	1	0	\\x000000010000000000800003c12c8baf1d30f78647fbe6db3c7339573354f987b1ad6865e1f64c403a202a7db9c95c4a3b55c4bf3151d3a5fa348d464f6937789b58b92916671bdb7b0a5844db5a91e3feb8cb9949af8b864c6dc5cf9097883b0fa02bc07d5d6de5e721e718aaab0c6dc6c75c0b3b497c6ada6f377bea08f7c6cbe4777c56fe505ad696ebc7010001	\\x88a45be7c6240426a6d6db939f64c193da54e853129b03040fe23edb678d8daa540326d70eee3fbf261cbb75bc6197b2939cf2c8add951cd0c70af10fef82407	1678608393000000	1679213193000000	1742285193000000	1836893193000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
80	\\x9a8400899763c68e1c3644a64ae1e8466069467cd621b0433250f3633c49ac45064fd5355f915ba7505d3cf67f3df253b7a88d9e948cc646d6a2a2029987aa67	1	0	\\x000000010000000000800003be080fc86cb55943ae2219e78ba9dccb41181e9b847fbc109b9b5f0c2738d98b788b6767957764dee324ee6bb80f1f27e9b3e13d9594190da2650b48d6f19997dcb4d625cbb62bf14799656464dea422656c392083bcfbc96a3c32f8f9898dca1701f76f524d3cb0dba11285c3175f72cfebff2f851dee33b54dd78b8b834823010001	\\x0fb92435296be5f190e0b0eeaf5c718f33ae39060da8858ff02023eaf129528b400acb7ae5e2474af1d3ba3c429ba5df27fea986156f79604816911f84d24404	1668331893000000	1668936693000000	1732008693000000	1826616693000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
81	\\xa4c00f6fb452d227ea0269253fbdf0e506886a914d0585201993d23e97ead8fadddb8bfc9b322b0f0166e3aeac754e7ad0f105dc84cae233be6b8d91071344ae	1	0	\\x000000010000000000800003dad8e78bbcb8e6fa987b8f5355b28ddcb6dc51c9949ed6325b3c02fdf1197fbf5e51216c3ffbbb64dc61392f42ab3548d4e8688282ef5c1617d139080e0307490b1a339bbca2a259a7123de45365c3e5673b2b15ff31342f985b49dfc777519d25c88e182eeb252b1f5780987867b7e05476fc90820b1e6f3e9e77777af23ca3010001	\\x5794ed84229ea1a77b6a1f40b731a18d2cbcc5184f0cf8ba03a4c2c1b792fc4c716cbbadbee30d00e1abc69da5d20e2a1041cf51f9fe21d878111bd320695206	1655032893000000	1655637693000000	1718709693000000	1813317693000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
82	\\xa520122bdff6e6f7928430bea72662af0246b5e8acdcb48640d216df32b26788ef9bd97c914272b62e70e00e7de0da2d325bb5dbea97303eaf3eb3c725b114d3	1	0	\\x000000010000000000800003c033cd516f37bb081adbf3d33cc86e4fbb189b3c6bff069a87ab27cc486b85669dcd9b7a77578333fef461183e94a077a72067ef89e7b17074fd0dc9e810e71dd6218e509f8a542c9d2a9746015646a3ca0cf72b24526a8a5419ce692b5ced54ddc5373ff3dc989e3b442df5c7defaf06981861f33f9232765a92dc1776e2691010001	\\x0e12b6b643d783b8221cfeb0e78ca0b03d9cc01b35c255bfa7d57da66e656f47c09789476ef1b8ccae9201648ee5d86f4767e5783c31464c6a4e4ddf60d8710f	1679212893000000	1679817693000000	1742889693000000	1837497693000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
83	\\xa9d8ef6a3d02b69c107cba5ac44dabb16276f270b1b4ccedaeed36b5a58c7e91d4806566b377ff1a494c0fd9fe696ec45ba5cea431dc608b48d8f83858e69d49	1	0	\\x0000000100000000008000039a532916440c7e2804434a0274af245cf616faec389cb2782e05ceba9152056bcb0147a45a416c19053b3355739d502b8f5393b0c13e261b46af23a5062bf9806edefec1ccdb91df1bfc18b32f988397a48621e90b5ddd6c26a416bac7b17d9956b97e2762af35357e0cb0357d7639321eff5e3488ec52327540f74c7732e4bb010001	\\x7cd973851609359f66050a4650a54b9f8d01b907a7243e8da080897b47882b298b54ada9c2371229aa53438f93bb09aefb46e4428959414b22b5839a7443a908	1654428393000000	1655033193000000	1718105193000000	1812713193000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
84	\\xa980877f685270d79d4550b45c730045d2f5256a3db12d2daeb8b73c58134e34cee8b4d2b991e8e269be7c55513afb7f15cfa600fbcce20dcf49510f6f3a48c2	1	0	\\x000000010000000000800003a4598d8fecbbe636126b60db44a1b154f70c277b8f5577dc7ebff7cc914c36656b6a2525202290bf368fde659b334eb8865337630bb078c52d7790ee472605a22a74d78cc8c79100031b2fa145f46525999ea261bc2e7a17fa24ab2ae99e72ac0ee4cfec4d3ab55194af0d690df95eac95bc0d0c1d4cbb299ce5bc2bd2e70aef010001	\\x2384a8b28fd0333e042adc4869e2e9fb379ccf03bd692202affcda6fd07cea1d7d34da4f19e03851f97319c7ce20517fcd8783f896c79bbff041c3e1ca5a700c	1664704893000000	1665309693000000	1728381693000000	1822989693000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
85	\\xa9ac2bb5cd7c22d90fb4b5542062c80ab50afd78d043da8be857780a7c87887d6d2b78e695ddd669f0b6bd22b5c0a6fec57b50c73298f3031eea239ea99de082	1	0	\\x0000000100000000008000039fad4256f2068d20cacf4bf7a41f593ec72f857b6b23ee76c6a3f3824107ed7e204cb3a308b7f06dbe7f00e40675ed99e6d4da631e2ab793ec516c5c73f709ff5fd9af806f78ac51f831c205d2e6722ccc8b4f0a9f42125c18f6080a005660595c024bde95ad28ea425777dde1f928a651ad072d8a0c92372a6dd48b6d2a723d010001	\\xd0163d8a31f407698d89382f90fee6857e3a71946b40a2749541d7cc2e828c244c3eac79b9eb937342ac8b146b89605df8f782dc061188befee2df32c9e0760c	1663495893000000	1664100693000000	1727172693000000	1821780693000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
86	\\xab44435cc4df770989aa86456c16fc666ff193fbd38120f8ee86f364c200094ebc48ca186fe7b7e26793c83cf8de92436e0b9de6f78e5c037eb411837ecae180	1	0	\\x000000010000000000800003a9b3b5f407e17e1df08469ac2c6be525a1b6d0411fb51659e8228f8590edcd4428c820ba0426cc5c289e5af48fd482c4f2bdf9c14202ae4efd4e42a0be1bda7eaa8a2f4b150a83158ccfda9ed1553ac776b2b2136f51d2275f52afe9443297390106cdaf5cff2672a648ee69679833d9e7bdd65d7b110781564040839c5aa2df010001	\\x5d51fcc8a7206a41dba349ce55776dc5228005a5aec4bd34cb9f855bc6f833f8ef10c9820192f88dbb0ecf3995e8a7393cd8f1f810938a47650b58da608a8d0c	1673772393000000	1674377193000000	1737449193000000	1832057193000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
87	\\xab8cd5c97495b16abfcb7720800a1a10d4e85fe6fd1f950f35707d4dc7dea3312d0bed3f06660ad53d58f64dbb1e073a073978338441b9e3d5d7cd0b509e15b9	1	0	\\x000000010000000000800003e762e86bc73e6d2c3d832c366f27d9b52e65230d207acabf31b32de51a2e80d014cd4f95519439df0b62b0eba0c9d8f8cdcfdc1c87669bb37949cfdb38e601a7577488e2353d69a34b8ca791e420ba71ae453532c433d300bb95c0f83c4124add7e64feb07c2f1f88e771cba4d7d848d3468c0b3c7c861b5724f5b39392a9811010001	\\xf8230a59f6b3bded8700b52f30438077811e8549bdb2c9d6eb3b9f735d0f17543a1959ee8a5e847346581d454651f24a11a3cbbebf06f00bbf5cc13a66601f0c	1664100393000000	1664705193000000	1727777193000000	1822385193000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
88	\\xad08b5c5ec398ca0c6db6ce77987cf17158184414c95812bcf297e17788c42e95aa9953a17250c140eb7dcc5adb0fe5d8076fe065668ef9fe9d67b5414764579	1	0	\\x000000010000000000800003b30298ae70c1f6a4bd3b7ae1e40911c5ccfe32b1b280b50d2e48c779a760f4998a50f609013bcf2d2b94f29edc31f9248749dee1a3859b6584339a68c611f5321c73eb26c36fa43325399ed48efb373f73dc2d92eee79efbe676800d9cb3848d489b576e1b9b3983e699e4231eace0f4077fc1b20199ab24639d5a36489284d1010001	\\x52674d45c0d72f11ba3a7e07b43ee3f56e09d9ec6a7d56a977d04303dbd9c118f39624fe289e028817512379f199865d6e560d355313db7f43e5d821c4048d08	1661682393000000	1662287193000000	1725359193000000	1819967193000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
89	\\xb2d465a2b6d84a7cc082a097f932213408338050aead5993ff0814ddb02bb2a3e0d81eadefbae618cf7456a55ae68c43fd9a05ddd3b4271b3cb9dfaffdea5b96	1	0	\\x00000001000000000080000395e16776e9c05ced12eac5a09251b0ca60d7ede035fe338ef68694ad68eda35c6f07b4e14b037df366eedcc3b07d58a38c9ddeefa5cb6cdab55a80329ac0227febde096454495cd84cf12f657291fa5b248e8be95ef46441159eac54f35e9f14df0c7b1aa850c2a11a1b1161a885f678946e1498bfe97db43dfc00f64a5dc719010001	\\x00e3ed23e427da05dcb479faa3279c570ec5e3d257c4c3726493252a4a147f8f2fb90be55d253c0455e7a4eda8210a56ccc29732f8d73df1b9ba215ec9239f0a	1671354393000000	1671959193000000	1735031193000000	1829639193000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
90	\\xba34127fe17cbfd56f97e916d244bd333060fdc2dc809349adaf95ab5d5b62ad13e52f34aabfd85780eba9c74f44f173dd6042f2788fd1b7c4681ea2c8fe6645	1	0	\\x000000010000000000800003c5e33f1feaa0adb0da96c12e00452d6326c50c262dac1a807e40d17f64f6117382696ed841187755df6cad0360b899e26c05dc0cc04ffc6e9ba2b5c85cbc3f4b777e485957cf8f89e514c017880bece5f8ead0aebc79a3cb30b6c93d3acc9ab61f72d49e153b8b151f0a5eec3e26f9446c4cfd2ce81a97eb2bb289e6304f75dd010001	\\x6f5119ed65e3523cea1cc3be7192e1fdc1c6d7055ae61a2c8207dc17b9a24b691952d4f716b223b590c2382c3412d6b993ae085dd5985e36371d059cdb17b908	1659868893000000	1660473693000000	1723545693000000	1818153693000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
91	\\xbc9017a84934120c64d6c2df22929d47cbc54962cbfb9c11f1b7b9a093bb565c925b2df3325a1ae77e08d3eed802859e21549ee73bc520a8024243dde2d1d533	1	0	\\x000000010000000000800003b1c12b47525f47f1679f9753258b75506c56371c73178dd62c43c98bd2cbb6ff37ffddd014aa5fd6c8ba0c0d3b6cf153349d1cfe49dbe80c5869a2f0e7b383060229c871bf6365a8935875f68ff78bc3fe091e29cbfaea03e1a2fcdbaf13c22ccd3b547706d94cfbc71e6a25950c6d37cab7e218c872ce2d6a00941d0b241b5f010001	\\x409f06bdab143ac459b77dadcbfac1586ebf7dad5d2ae72a09798c1b45d23d826eb40598c2982723a9a34208b1ed5815973dcb486dea56893b3f9fdb4a87660e	1676190393000000	1676795193000000	1739867193000000	1834475193000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
92	\\xbcb833c8de6f32c191aa5af47934ddae290b261052386e768022109fca95527d0a721f9d50b663c5a4b5c592e2701c444616cfd47a630c82f455b6709680f40e	1	0	\\x000000010000000000800003ad417db94ec113dfb70fb012d34a66579235138a4a78f1c6cead72c08ab12e0ea7c4221065143b5392f22bf385ba4a799782e8601d23fff40c04bc03e441e690cdd0457f997bf08bda001b4d05f433ff57e4f08cd27a2983cf9b96f3109ff69624d9237dbb09cb25a3cb0a603901faf02f6de2b2bba6625b910915310c6cc5f3010001	\\x52512d807134f91b593e9ab5d6d65dbdd958bb2d948cd9c4de33d83928d8595004cfe628de367635c3a9c39ebca8e35e4b6f9488adcbb22c21f812600edd6f03	1653219393000000	1653824193000000	1716896193000000	1811504193000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
93	\\xbd182967cdfe3fae083099b453107c59a3a537cf27c98e06640ff6050a40f9cf35117077e31087c8d372fac01c0b0f4e4cb53085ac7e0a241cc302b9f23c65e0	1	0	\\x000000010000000000800003bc50faf2a56d5946e31caf4ec68fb8ce611ef3d7325d14e717909a1828cb3ceff53809959b6d795ff0d248b5d3543e5a533709957cf725dc279ac1691497224e35154a0ca5b675bced1e3f9b877618b01330da701b99b04bcb97ca9b2c0d74b3a57a2a0063fc01fc45446b190a5793d3451be477d7905f723a3271bca1dad515010001	\\xf8a1cee549607b9e7a5e420fb64088a89dc2a09de9fcce2f7781c298b906f89e2743fc86cb0348398173fc5ffc3476a9c2980c2da7921d02fd0e03a245953808	1653219393000000	1653824193000000	1716896193000000	1811504193000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
94	\\xbe6c28bca327e6fe813e6a2b96b0a806f92b9eea6b193692cc66e3b0d544e01e7ae882bc6d84e9819db6636801bfefbdd84b8e2f209c718ffd8e249a860aaea7	1	0	\\x000000010000000000800003d5a14c8b86dd580b73d25c02579abd8bdebc439bcd26818d9c2ee06c0537b321e28002f9cdca70d80b4dcf8dd95eef34bb212043625f405f3fdadf7ea96a9411f5ed3d057b976f4b31cdfea76d3289d1099aefcc9b61ee6dea313aadeb8ebce977f939b88d689457f064cd018f141308e1f0bfcb539cff7bdef282ac70b2fca7010001	\\x51753191d68dec80f8393692720218a9231080ff6520712cac5760677cc5d1878b767d64fd684f8b2518518d5c304aa46d34a4676aabd056668de6d3c60af70c	1658659893000000	1659264693000000	1722336693000000	1816944693000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
95	\\xc4a0e6685481dd80c2c76a8db7329a57a474ee918bc9b9f751b51ed7446ffdfe0d2f50d586e773150f930563bdacb90f55f6a599c5f1ca52fcf29ad2efad4f66	1	0	\\x000000010000000000800003a687b61e53a3049bf040b2f765f37f0b93ab1d610cf8989054ffa48658aa9020dcbc954e5cfe3435ee5f7740d750cfbf052a095dfca84a47b6cfc4c5e92f7ea88cbafdd3382b0c60ca221ffd3e3baf6554ceb384bb56407e04e0c8fc1f0460ca3c8018e1d98d7fdc92e56c5183e4a4972956cec2c074579ea4b70905013e94e7010001	\\xc051ddee07e50219fcbf8b55b5ab6d432aeca521bee65a302a621bd86bb2e4e3ad5091c501773d0617fb5076baed901d660fbf8625c5d9dfd473f8b626274b02	1678608393000000	1679213193000000	1742285193000000	1836893193000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
96	\\xc5d8953ada5af03144f5380cc1e11013babf3e625ea15d0f2e4272b0ddfb51fc7d9fcf187e9ec43d21be91e6d24f8f70d55ce6700dd10676bbaee84314add130	1	0	\\x000000010000000000800003ce734d2c86d71e50d04eb290dd83189db41f775caab4be90808a92d9170fb3e1b17e18d9c3539a19a2c79747d9d82782e6a66cb04cb5b0b8c9be1de1ace95f2106c5b6ed712d7871aa253379e70e8f97c678b65d0d959bc5c1dfc9259f78e93e0ef96f745c4f0684fc25b4b011398edeb0ae22f146f71b18c50e3bcccad7cc3f010001	\\xc2c8ec822e018d21163883d9be63841cac0942154e01e38463faf03d056d89683243b874f15b7ad00dd35a15c90a766c534bf2e3cab2cd5072248c35344b3f02	1653823893000000	1654428693000000	1717500693000000	1812108693000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
97	\\xc6881142cf516f6160bb30d4c201ba670f47f35dc229b4773345f51232c6caee49bd1c4006d2d1174a066c5fe471e179f94bf99c379467a861372fd37dc16a56	1	0	\\x000000010000000000800003cbc8d9e08e98db79b557186a4366b22927275ed33f34286ad81a9397e260d443d09c94a94fb87e7300e1f58792ea946e1ce96ab618d5e0f1b2d39081e943e651a4285d9857015bd7b41f89bc18d177cd8462bf1496c03340ea3817d2c0ebb508cc174ee68bce18fccc44b64c551236849fd5770ef8732efbae2b210abbe7a4cd010001	\\x270134b177414038d723235cd70d0ca697c878927580f6cd848e9db89d17df4f323f491f1894bd235a6aba19e0c07380d79a5f1bd1d5bbbf6ad60b32b779570a	1656241893000000	1656846693000000	1719918693000000	1814526693000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
98	\\xc7000b65f6b4e42466914f7a06ec36a654e8c89316ee25d17f98af213ff24bb5d4f5a73881adc7bdd7a4579c8e4862cc2b3e45fffb123c6763fa3d3e9ee7b8e9	1	0	\\x000000010000000000800003cc4a2e30cee5f321c72de8a76f7a5aef1f8e44a12ebfdeb023027bdb4a5c4e1fc9e7bfff0820595f8be527a482749ba7ae08ea702205b51f9eff3108cb5d1a1c6b4f25b30e12ec7969f35dba12751103d22bdc8dcba7dcb0b5a2f34ee89143a003f338e05792f83444b861cfac67bb9db5e86966c5dc39f87a444209e21bfe65010001	\\x88787e22096ede0e8336d9a6ebf2216249b56331464c3707b89d1c357009ddb3cd78eba2c79e66bfc6e3c2ff5f64fb85867c32a097d58c90cc95eda9eb8a0f0c	1656846393000000	1657451193000000	1720523193000000	1815131193000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
99	\\xc918685a463e722ffea85f9fbacd4c8097ce747317ecac72aa2debfdcba914898de6704cc075a178d6a20ba7a0d27b94a665ca4494115b95672ab619de99a8c4	1	0	\\x000000010000000000800003c8e36c357a8039363677dfd72327041b95ab9c3bc7d22190ec376127f695b4e43fcc03670eaa7b75b049586a76aea20d37a50862871ccefd42394a0dd23f896bc473af02bee64685c930b8458da1ec1ed4b34e1037846e7eb77a215e311d6f7757629b9ebac604c083349dbf5c9dba5d793e7289d9f4b6d494ee09bd6ddbb8b1010001	\\x83f5646e89a649cbb047c8a6353bb54e724e2aee91f1e49a0829f82e4e88628515a1c24133e3db13fe54a67cb3e60bd69f77277fd550a47a397ab9a8cadc4807	1656241893000000	1656846693000000	1719918693000000	1814526693000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
100	\\xcc7c8b440f64e5bc4d7a83853054d271bd95c25154c2867e78cf11dc3c3174679178fcc8d45e2cf7d64599c41ec321cbe82d57e6aa1a83e9fa70f47951d4ef12	1	0	\\x000000010000000000800003c30a868b2c8a234c5089fbf9fce25e6acc0f83d148aa13529e002a07a750e1dca6d66e7cbc3c5157b9696a602a13f7868bbf37c6b52f259b2a94f384cf97bb6f5233f5d89f0cef3a1b18263b43bf0694f2d4b446f8296e09d89ccf1d953840198812ca1d6f5eca65802ae30afc29a38b716ce22854f55af2f08328837523ee5d010001	\\x3b03f9ab91bddc8485fc05718a9f4ee3ab9f1efb142afe6f3a09bdc1174263e0bcb4558729bd488f80b98b8e36a9d433bd98c836754e5739d35ceb2612bb7907	1655032893000000	1655637693000000	1718709693000000	1813317693000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
101	\\xcd1c158c8d29d006063a8cd4de0d3c80bf82d98ebfac8600628fe73a399a8e305619260c52ca45510362ab18b310102ddbf0e0c9a80d2f660eeb71ad4e857604	1	0	\\x000000010000000000800003a54c680f009c354569703665d810ef6659c33a450f4e23ed08ce0e517acb3a97278374702cde95c095e39bc741d50ee5a2f372e0e74c6ec89620321b67d954cb8be98e5bd902389db178777e48d3da5c6b1285f5b2951be85263261c73bc94a89ff5c9e04dbb1bdf13d023b45e1c884498ad751d9d35192feb51c4ee5a899df5010001	\\xccdb193463d7e2112323bb4341c6cd426b5da20dcc99b24b9affc28014d819790be9057c6ae916234e7cc1611fa2e3ece6deaf2802f1b867ca394d7da7abb302	1650801393000000	1651406193000000	1714478193000000	1809086193000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
102	\\xce48eb7e4749b1bf2d4701a3a21556b59b03e2d995a27a6b753e462fb9dc7c774f174985685c85887f47929b1859428512cc92d93a863a3f50c062d12c4d387e	1	0	\\x000000010000000000800003b26ba6d597698cb8ced83f07691830d60e3058cc276e4c31716c79d5093a044b2f9eeab788039338931296ae71bef62c34296da8e6b5e46969f8c337babedd3946552879ef1c12d002ec17ac529d5513a530bf173064e963fea6a8eeca1a7b1dca1eb931f0b74e1647fdbe8747efc49e210c65dbe1cca9feb22ec9acf94c481b010001	\\x6a4d21c1721e32eb237967e13e8d03ef1f85452e9f6e59e7d79dea7dc68e31678b19718b8fa3dc13d748be37ce7cec56473b6ef0c78c96de7a6129422eb14f0c	1654428393000000	1655033193000000	1718105193000000	1812713193000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
103	\\xd3a80c154952991156223c66f7fa482e96fe2c571e813144928e04e82a4796edaca34f10c9bd9fac24f7e99582d8119a3d6c8fc57f045c19cad0c3230a3e52ff	1	0	\\x000000010000000000800003c4d482d1454e19936a5976f05a5002bc92700abbc201010b743dba1fb35b7bd499fc643af8341de8e522473201bf0ff4b22c1724c693c57a823773989db8b753c6317f0b754af39e0a4351f118d6f4ced8ed4089247fe75aa8b490c08b03a88e65b0ae6b664797cfc6ed274d075c405a97a30c8f0a2aeffc6deac2dc90c9de9d010001	\\x7424af3caa02789ca11b9e039eea53c082975242ab821a32cc0cd1c0a86f57521080b54a852f54802036cb8b6379740cbeb58788f02ee2cc02ee759d32cb3f02	1650196893000000	1650801693000000	1713873693000000	1808481693000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
104	\\xd424ef849d15878d2a88d38ce863f9df38842328e2845baa2368f80c4ce7a368d81fedaf1236592ed07e47c75fcb9e78eec8f63a97636d577923a561e9e46500	1	0	\\x000000010000000000800003f718dd7cc40e5fa18b954cc229d4743c90a000dc0de7c6bdb064c915c9a7d910ddb5eca00169bf5469319abf8d9e0b8aca7886a233522faeae98169678750f28f7e55ae14a47047798f89f69b73f9cba2ab51da3f22b5286b3d0025b44bcd68bfbd24efcbca68b497a7f6138216be907244f67072d9773fe10d4b916948fe53d010001	\\x5a5e341213d77fb28b9f364d0d5976930f0930148e56335d7ab37015422c8b38b0c4ba741231b33f10ea27f3b15a29b6537c5db6c824a30530a27b30a6e6f205	1673772393000000	1674377193000000	1737449193000000	1832057193000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
105	\\xd5d0e4aec3136fe8ec6883e5404ccf1bbe2e03f40b5f4df5ffc3c95a821c2b4b73c0d05b812ea4127e4ddc8da2c256cd0dcafa96b265f1a3860dc5ab79f79e7e	1	0	\\x000000010000000000800003cf44afd6037760112a3bdfe0e4514bc6ee985b81acf000070bbfe8f128954d6e2edec3c198418c0d8a981aeda6f0fb669aeabc943a8f0369247d0d90c5129b7b3a905d250cc47e386e08ae0c1711978c1d9c3e309dff817fe602504e1f8c3ada4c38ace60831b57b35fbcdcf7bcd6207e2a0f5529bc9ce592100430a2436f54b010001	\\x38039870d753b2b9a64872b965007537fbc0e5c5175d361ada94e6b050f91ec02a5650fde664966ab5431d6e0426354807a07296d243d367d5809a4b1cbcfb09	1672563393000000	1673168193000000	1736240193000000	1830848193000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
106	\\xd620945d649b8577f33ec31aa73415d52a96d81bb5d8561498033af0f4c47f10cbdbf9314a5ebf66794791f515924d22e3b89d6e0c2af112b4325842f395a3c7	1	0	\\x000000010000000000800003a4bd8d7656f8ea3f2e6470828ceb051342888dbad88f0fe06a355f2fc410d3ea77b72f69e7e2603551976f7107d5a86f68779cdab9ea7a52035d8f4e462c2d96c8ca58ef005ed4479f848e0226d8e919278e5bfc92514fe5bfdde886a061e90cedca1c901a0ae810afad21f4c011ad90f1bdd2204864a0990d18dc896bbeb2b5010001	\\x293dbede79494b1407015a43abe862ba550bc33414c1a9042b0d972e7f1a00adca892bef2c7c44a85301f86e5cf6a76d48503cd34a3a2bb10b2a7489c801af05	1674376893000000	1674981693000000	1738053693000000	1832661693000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
107	\\xdb98a45b0e5cad498f976d16e9fceb6b7390e1f3add44b7b727c789212cb131666255b930cb981c6a6cb35e035a580d879ecf119ac72fe82f6f7c1b50941f4a1	1	0	\\x000000010000000000800003d2fef07a9b488974420332e0f89056a0a193b5abe724a56599c1f70efec1f6b538b74b2148e5c0a7e3ded0f26fcfb6ea4890fe6584cfdce3838e5494332f892f43bfe59cf6468089a57ebdb83e7b664242bb194e67a1ddf3604aa3e5ca6314f69a6274d5efc57e2280619f55e7bff74ab74792ac3a71c35dacbc40c5f0d71565010001	\\x66a408e5e0b48051cf423d27fe5ba5d834b34e4f869233e23532f1994872049e8374207f4bbb746737eeead33564a78ae90b1fd2ecf5c8ddb2ef10d32dd2f802	1659264393000000	1659869193000000	1722941193000000	1817549193000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
108	\\xdd10fb1bbec516e17878993614095fafe3276a5df3df344704efe27c90d2e574883d303360df98540830ce64c6e36fe0cdca924c9f93ff8fd53053e4e5f12985	1	0	\\x000000010000000000800003c679aed34c66676d30d6b3a118b7c08635747de3c15433b30e3cb9c1f4e8d5349fecf8e23e4f301629cc539074bd1bb459cc98c2856e0546473366ac1ab8badebdc26d935f5f7e7ffa6aba4429dd0d02fa7ed90b00f50c3f8bf4b5979e137ba68d11c4452c0db6eb9379e7e274f757fc0d2e798c04c2cc05f441d78d6dd60725010001	\\x1d4ef0d029a8a5ff27a3b24d3032876a30c9ec18e0126757cac53d648ae958330c30237a8ba7991d21f2f678554416ae02ecf327e8b89306f9af3a6aad8dc702	1655637393000000	1656242193000000	1719314193000000	1813922193000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
109	\\xe0e4c5895c49d536c3e592a68b6c9d1ce6358403203107eebc7af09d499f8c8d6bc90b9e99fa339c3de47655ca87a2490ec7f9b058d7a5c0189590fac9e28bd3	1	0	\\x000000010000000000800003d8d32952349caf25349b230b36c5d7eb8e209fa15c793ff73edfda0b44442d9c806a42037880b40583927bd4b36194bcc96bbca7680cbea92f5197aa4f026586bf5c9533f3831557ed5b30d0b037ff95c630866e4fcbdebf3262d46b3079395cc1f425011e763c27abc4599c1de69e466db6edb39d967445f350ed8d59855403010001	\\xa8171d52587dd6a7cc5416c8dfd7368dc99ee63c78764186640131f3cffb937c0abc6ff4f0be4bad0ddc8c182337c22584bb8ae8df9dce7f9c487601a3e9390a	1653219393000000	1653824193000000	1716896193000000	1811504193000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
110	\\xe0ac698d7a745b913bc3a344e6b48b30fc916d9af7674ca34b5e04e4120cd4a7f391255abc0ec5d460b2f49dca78f0d3ea9e9b92beca1f77711fe697a08b6bd0	1	0	\\x000000010000000000800003d17c0d0c7db6082ae389a839c4412295eacd1638fe352ce6939326f32b47fcd4ade0794963511a1109ac14955ce17bd11a4af294e4da3fe3cf75f2823d6fbc9bb8a560ee65d583db78ad1ecd0c17915418ab3013ff17794dc6263efe93c825759d11fb9b1c6befc5e55928e7b444d9ac2eb9b823018cf8be28ae85993388d153010001	\\xe2510930af0febe566cee29b98fba0c2d69a5cb85009e1aac05245ce4bb66bf9c3a642c1b7f341066397c2f604670e82252eff5e66bf5ebcb3bf9db0dceeee00	1674981393000000	1675586193000000	1738658193000000	1833266193000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
111	\\xe2d8d1ab18efa8d3ab4ece124ddd3da75bfe57722076dff941f703957f3073efb58cdbed6388b205622c8e5e41893537b72e3688b3d053da03f4caa6df799166	1	0	\\x000000010000000000800003bff948570fdc65564ff3630bfddcf9685e5855c0d614f3ad913f83bdc204f0a1440f8fb72218671da3529792cd48a75b87dbca721e2a6ffc589d2156fcf806be42a42f3c92d8099c61b2a9868ce2bc7b683a4c6cb8e3c505aa70c9e4a866da18d6312e1c8adef083cca57b2dd9c85e4b790cf8b6079f911b7ff4dcb08687b821010001	\\x9c2db428678acf7c4b7fef74341e4f2e64c79e8b3be481f37fa2343ed5b056e5da0116d9b505c224245a18fd38fdccc6b12834fc096df934ec42ef2ab95e1302	1674376893000000	1674981693000000	1738053693000000	1832661693000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
112	\\xe3188ead13e524e8d29a902411099e5e7a61a505abb611580207414a7255ace8c5821ad6c1b94115fe79cc86c63953363c2b2055c2aa1bdce3d159b15c5e1ff5	1	0	\\x000000010000000000800003aefebc2623267400747df74d44ffe6bb7645cd188ee87d1990b96fba391bb1f3e583dadad8d1a2e32eb718abf9f5af46f03d5b41de14bf7d986bfd13f6491878594107a7dd9993acfe14357625b293fbd72f7e0c74c5a34a092f5ce6abeef0999150853dfd1b82d050472776e6297b0fb30be06d7c80193b42bd3ad5f1a33aab010001	\\x96b1ca9c8669299bba11a307795744bce296b43b5d82def6929e79bcc72804f436f61d8d591b5a37920020058e1f08aab456b69301d78cdfeca99d55e9ed020b	1667727393000000	1668332193000000	1731404193000000	1826012193000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
113	\\xe3587537bdc573c4e27f60e69796e241c64502025a1f417e2c7b7a67cd139a3f7688d847694aeab6b9f453bf5a5edeb5f04defdb3a653167962cd3b3e03aebd9	1	0	\\x000000010000000000800003adeae0235c2f2b0e0b4e5baaa0ae88d1803ac6ebc70932811bab0fded23cb9459e8b977c2dadecf50d03e060b95b611628fd6fdecab72727a4ba869eb63d73d1f5bbed5bb9d95917649ebf84e8905f6db5965a514de2542637f9693f5dbde732d7bcc74cb66ce373457148286da1753b0030e4fc559d46c61452e7311e91be2d010001	\\xd005818449d82fd3af97677b6ce6aba0aacab84cbee93b0a0bac450a6232d07241195c6c33c2499a3f599a63d583b673502e3040cd3310a0fe2e64ab5080c601	1665309393000000	1665914193000000	1728986193000000	1823594193000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
114	\\xe468e74e78801c5c9a954843c82c298f23a210c3f9cdff92e24cf9c5737f2df5f907d9b693767281942060760532a1d832ba0218b878cc3079fef14b43698690	1	0	\\x000000010000000000800003c5f107e12f7f0adea41282cfe027edb1a14c9ca7389537847abece57d7415275897e8ef089720aaf67f33abe41b09214bda8b33115c6f7d2b0b67879e4003857afe301e8f389d68e2a27a20b9dd71e35d32f5da5b861520dd919fce5ad871792bebe07f33bb485b7f3e52b8336cbc1c6998732058aaa0e20ddafe674dcfcdeb7010001	\\x800666e31e5ecf56b8ddd54f713d7373b997c2301f4030fc78d709649e5b14647da9a9f0a5606ee9ee4c881628c5a68d47b6c9f061e027ddac6ebdf92a085604	1679817393000000	1680422193000000	1743494193000000	1838102193000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
115	\\xe6042d4765da632cb0f4cddf9ba9ff74668a74e53160cef10e55469a056d6962e55bdf52d38794054fe32bd9f8ccf7f0dd6fea9a8ddae13e6f81e4447de303f0	1	0	\\x000000010000000000800003e48b97c48f09a85f3143db23c79658eb691410808fcec3e0e6339d1453492e8fa99a2f98dcf0af187c2e773efb52afa51814daec8c1bc13e77ac6c538f99b5e2a25f56f02fdc1164bd7cd7a909976a3618fc355857cc95721c1a1a1d8b89c558d73af04dfd888b12bbca4e7660195eb7654bfed65321b92f9dfe405c573252d1010001	\\xd23da8d9a8aa18bec7574c2b1f0bdfaf647dc5df7a53efca8a26953701abc4aefa329cc679983e6345f9f247d62bb3a43c35a7071454a7f4f176ee1295d1060b	1675585893000000	1676190693000000	1739262693000000	1833870693000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
116	\\xe608c8a65a5a7a3b809878068472c79cdbba2401a137a963bf140109c4ad17870025f2d498f36b0d2f8bfe3faa03169465e861f47d0932f3b2c4f8ce30223bee	1	0	\\x000000010000000000800003d9b743db914d15e1f92f76aa6d534354857ec14db70b4e29cb3a54f28b82721e8dc810b693de20f8dee934e98f5a9e7cec6b221782f1331a29a3de11282e05f3862edd9f1c5b070f342fcba0d6c5165cc39b336f7fa3b221463ac9221ea48e2ba58e2e545948fcf1030a2a1b7f41cc98eecc97f44ba9ef8af8020075a652d529010001	\\x6343f728aa469005f09f59fe9d3e8d49c0d29294107c3eebecd42a50c093654d16c779efaa64d0b0d4ab57b6a322e89d349e5dd53dd223f5caa30ca9786c8d0c	1661077893000000	1661682693000000	1724754693000000	1819362693000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
117	\\xe77ccce2f6136478c18ebb936623011a8cbfe7fa8ae3dcbf39716ec705ca6b8b60e732141ddb9738e96e459bcfd041668a827c942864de8dc328718ffec87988	1	0	\\x000000010000000000800003ed595260d146dd300e4b57a21474365cc0d509c219acfc9e096e1c303eedf26e0ee470637abd1ed882dd4640ec77a94349419f534ef25ecf5021d945aa3e4cdb68b95dd1a0dcb9fcdc8e958f937e27c67a4cc2062103abab8e208176e982ceb3dfb6fa13c51d5b28cbb23b3a6305004713f1efe1038c2d6be90902e8fd8fdec1010001	\\x4045caf50999435a96975c385010559f4314fdf8aa8a45fd5ad5fd2081f00ec2010c0ac460a758da519ba9aaa789926f4d72a6c6bc36092dbdf16a77aa22af0a	1677399393000000	1678004193000000	1741076193000000	1835684193000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
118	\\xeb4c51c20419025bb5a269fc3c6c5658f310c0c0af5cd04c14b871a7da612fa9bafd1add47ff05879b465f64746424aadf485acc9a920f527736fa3aa9410bbf	1	0	\\x000000010000000000800003aa59d20c92f27371687aa7350f8c906c49f42c45183d890f6cfaefc39814943360ca87d8dfd2dca21df87b8c69b8075a6370d9aa5a84cb6af13a4af4d38f4d817d5608cdf32e126cbf0da1d211b19305abdb653a9064a4ce156ef1f42e7731585d281b4c5c1b391ce8409d614c2ae86590d63a3dd23deb697f7e264f7e246dc9010001	\\x638e71d3f3abef0445e7ae9e63d9a6b092bf620c0b50530caac014486334c15a55f84ec7ed2ecf0408b30e5e0aec936944419e2b5d01faad08f512c296880a07	1675585893000000	1676190693000000	1739262693000000	1833870693000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
119	\\xec7c11b9605b200bf652b1fe21a0eab4b1291c1fbeefa117c474fb2963289e1c2bed1e7d88099d0dbcfd69c366461e939b298f7c6fe5dee873f7edf5bb9a8346	1	0	\\x000000010000000000800003b0c5a4f69ba36b7160ba071c60340a73be50864fecc244ae11c9f0ee3cf78108e36c23769e823732ffe9aedd7629feee32162b06eecf2486d31cbc49973f234611a04bfb5300c69223b73c8f7aa2f848141cd87c1fd393ae655bfcd530e66679beb5b084d516c1e2e2ca72c4d69577aa64bb43a496fb26fee4619902ac6efd05010001	\\x504c9922a161aad056c7bda41dd008218130745fbabc3c917bf299bfd7cf65d0a67a469fcecee689dc3c62870aa304ee56e6cbc5ae7cfae93d75f97c1676a203	1650196893000000	1650801693000000	1713873693000000	1808481693000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
120	\\xed44ccb667fd4ae3909c588e4e980d398db91d8d366aa555e653bf0ef5a74db64e0d7776d571fb63224141dbd32cfa9426bb745b7aba2ba0754518e0e8ee42f4	1	0	\\x000000010000000000800003b228959b427774f4167a9a24e60a8ce7557629406258c2291bbe8c4ed287d8f3924a94d159e60582634f36795e077bd725c7d919f01dd1b82c72d2730ef60fccd4c5aa7dc33fa307ae8354177658af38c4e5f78431032707524f98ea8590b7c821a420f3ee4424d2ebd1a084442e96b52c907beabc8235f16606272f0e82a71f010001	\\x2d56125cec6b36f2907f2e8e6e6503cac24ddf6891d272cb89ce6010f525a16a04fc442fa8fcf4c6d105daba94973c2f80a6de1e0bdd34b70f0dcb418834e90b	1670749893000000	1671354693000000	1734426693000000	1829034693000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
121	\\xef14cceca261250356307a12db1e57d773d4a2395871dd4d88d40d6e0c04789ee11815cd2383b539d0a3367576d7a8ea580437cf9eed229bf50ae197ae8ee1c0	1	0	\\x000000010000000000800003b79196ab239ac4b49f483e08f5596d6bbb05cfffbffa61986a9770ed61b6680ed4d1e8ea9f1a5210e8fbc7a681b53e141e27e6ab0848fe72b2faf07c1e6362045b111630bbd8d2117f4925c2999f707e88d28d428cc9c4052670c29777fb39e7f12ae0e2b692a3a582119283ca21552f96675537dc605396bf9b557030c3632d010001	\\x34f049cb956682d1e52ab4ee34d552b0880cb6498d24b07c2eb8ac40d0ff2f0aaa38344cec123b64bacb0e607627ad643225603938fe0f97e8eb9a4fda767e07	1671354393000000	1671959193000000	1735031193000000	1829639193000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
122	\\xf194d2434da38c7bd9a4640401718f577e2ee3447dd0b3adfaa031b68f63350d1a83c209c5f685d76c8ead6c577a1973233951be0f9afad3878c514ef81d0ea4	1	0	\\x000000010000000000800003e0796bff09928a935579e91eb473cd3ac9c3f7986ab5932737834edda681b04065181579025e1a43f50e723aef213b370f125325127bcc78b1cc1f5218b5fadce3c85c2db789de1d5766c5d0bca2f705fcdd975605beb476efeb4c05cc83beb1da8b177899aba1b68d721ae397d61fd856319bdcb1c1d61ae4126e256f04b379010001	\\x8e3b4eb12bc4d5a1a3136c6fb84e6baafc3c74474cb468f7a417a232ec2727518f6fb00f557168c580449a819135e2a709d7385d6918e5ea60bce7a57fde6004	1657450893000000	1658055693000000	1721127693000000	1815735693000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
123	\\xf220d63ae3f8c86cd3ad510fe273894bda975824816d3048b96e867546097c18b67ed5a77009152749c4c6a9889e192d169beb3c45aba16edd49703651aab316	1	0	\\x00000001000000000080000393efbb33c516cf8db154ad0064e0a75fd4691f654f6b0bc63d45651d1b2ed92aea32991419ec699eb4c7fd280305f851e82a5fe64bf547d70110bac10de64396774ee266a9d10d6394ce83fc47e937762ea4d92a7cc141496030730e6519f40d767bf6654c162dbe8d9be3a001b49691bf40da9521f3691a444c39788198fd79010001	\\xd7285a8a5008c4ca755d73fff757a2228c65fe49e18fae156a7f33accb43bd8ca68897cb9729f2ff555d1e365874ff904b88037f37a007adb52a7beeb372b605	1649592393000000	1650197193000000	1713269193000000	1807877193000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
124	\\xf2608d61aec29516f357f9c4964469e0685950d18060078ef2c13108eb38d16a485f6a3a23de75d45615034698ca1e4b277f4212d6150b3bc20e562cbe883054	1	0	\\x000000010000000000800003bc2c45086e0e6fbd032a45d1cdbc5ced8ec6a1bcd3813e725065dbd4d333f6147957180883d40a098874a0371d74f7db54e3af13f97589b66036defd492d4d19b9eb0bdf5cf62ec7158c9a0204c587231f93b85a744d016bc9ae01116b08ba78f78c9ff40bb12c16fc1f562f5716d2583cc1a720a10eac3ad1e3c2f0a1972a7d010001	\\xc12fb64a873224b5b99f525d277f39b95b768fc38e5e9232ee734905a90109f11ef8f0337a3c35e877e8132f1a5385054dc800c2078adf93fe939de7de157c0b	1648383393000000	1648988193000000	1712060193000000	1806668193000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
125	\\xf2002077a8a62bd8dfcc903eb83cc65d80ea72cc28215e553a75a0ae3243f0337e5fe9ffe7bfd7e45c72789e6d27d4d5a2dd4f2fea1bb04e6c1011d0b8f8be49	1	0	\\x000000010000000000800003da5efd96d8a84a007c806bbce0623ce580cec3f3b59daf4637fe921c78274ba6a5fbf9a6b3cd98d9a5dbf1492f09e4210e6398c4960f32d94aef9bd8499c7dd8241be7f6915ae43e56faaf160263e2a47780d0f3b9d09040ec77429d075ab80ebfe8f02d24eb4d675ab6cd87b0d242cec30141b5ce19070e49736451387113f5010001	\\x74ba7feaf8471cba0ed63e0a500c126823245ae2d7135c0afb3872bee744a7f092f944d3524add2c1c823d2e8bb65ab4581fe24ec67cf39514fe397bb847f905	1648987893000000	1649592693000000	1712664693000000	1807272693000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
126	\\xf56408e6348b20e31acd438428a6915f496ed7d73f476e4bdf97d4c2c960d368546835f01ad14dd4eae321ae0b39213a9aea592a0ad3054bcd7bbcace87167f8	1	0	\\x000000010000000000800003bf568665fe5c4a9c32263ccb9ebf738beb111f64bbbd0936bff0302e203a60f4e5545216495b52dc21512c79ca9b0171a0db5a4af370527a53b276b16383c565d20baa069bf478bc8faa90ac1dc2d40c4f6699b192579e2a088c29237380df3e009971d4aa0807aad2857d5302a907a8e219dbaa5dc5d9075ccfdb857b15dc1d010001	\\x6a686b9f3e3ae42add875c9d2d7b40b16b752379f867b819d916655bf441d62eb778bd1bd89d62b46e19017fc108e0407c4904bd228eff031a0ebfd5980b1908	1655637393000000	1656242193000000	1719314193000000	1813922193000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
127	\\xfaec41c4a90b24585523268b613cc9fb4177e181bc8488b691505cbf7bfd4055a3bf8135e863921e6536602009e98f30612e85b3ee289d34cea653bd8ccd320e	1	0	\\x000000010000000000800003af5d0682b507b76e7d739b331a0131fab820cb64af5313751117aa9df81cd11e8ec7587572c7154cbc42bfae0ddf1e6825edd3e166cbcd953efe92dc208fa61db473f4b4d8f57beead1e24ce3e25720e35023394a3187a0bf004e7ae0e96fd036f0cc3b7a0b229353800447919eb001e65df86e93432cbd25820eb75d077a603010001	\\xa50336c4de26f9089b841cb4ad3044cf9a5bcc25bce7e37afaba33d251aa90d474376622011536baa802222d8ec17269c00c9543d15b93b6d82de2e1b232d401	1679212893000000	1679817693000000	1742889693000000	1837497693000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
128	\\xfb58bf76d00c14501d6e73c5459932e582cbb5379ab279ae8e8586ea7d3b532b33a66c651298670d2484d82f2e74126a506763d560e6583c8b2ae93b785c099b	1	0	\\x000000010000000000800003b22e5a11d6669ba2305cd7f9944436820e3c305218623fd808c564bc321ecfcc6503f28d9b1865e14e94431df3b588a1c5a95100b071b0c26f1c7243f4ed54b7aeb505afee6cf4210cbfa73792fcb06a8734e80d269147b6e385612c0897a6b8b3af1fdf658f5bf7ab302002c70828cf8d9a79fd203efc57ecc62f784aee5ee5010001	\\xc42cd8d8c1283062c4b67b2fa6fe572ddf47cf7c1d4df60cddfddb1ea8dabaf7d393acd7b2039087b0e2953043fb7de8f998e659f4b972ccb47aefc9f0924908	1664100393000000	1664705193000000	1727777193000000	1822385193000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
129	\\xfe903682a0872edc5ad0df41cc237084f19f2cbf19e58f7accb2e50d351ddcadb91849eb7631ab7cbd87c8720c190901eca1f4146dd2dcb168bb2309bb9a8080	1	0	\\x000000010000000000800003e104f16e8ba3dbf359c61a3662da2e5f03d8c2f0e823e4041f2ba8d980c7bededb405f97721068218dbcb258e8f8e4137f2dc30ff485f53d1a362932dd80d0c8f9a9a60969eee43ba3f0e68578d8cf6f0ded826355d268e5150b2e1dda4dd7f8946346191da952d5c48ab8c072c949e019ceb9683ac8b304c6a169dbc358b971010001	\\xea17fdf8cbde516601a0ea932212f33cfad1561a352fec97653f11f0efaddbc7a8a1968e2d65eaffea4a4e33123394bc05c6a8a4c37897803df267d7d9651a09	1679817393000000	1680422193000000	1743494193000000	1838102193000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
130	\\x02d104bf5edd19ad136cce6edd16bcaed965ebab9ca8a8e6660a29349b03f2a8e227cf3860f2fd8880d173b2492df2eae40e0d18c72decd66fab02cb8e0249e2	1	0	\\x000000010000000000800003c37b326561ac4eda197c320f48daee56211c7b65c7ca13da2ca158c3621e25f2f3f6b654a255457d23474f03d7354c02cfe92302abbd9ef40ee7f1ca31cddef9e9695a64c5cebd14b5f80605bd3a3c80f7e54dd9d69f0288b4b93b574e5ade6324a4c30cd264b2f81d789f986fba790dbfcf008be014b73af73bc6a598388577010001	\\x9c495a22e6f5dc923422a034bfafd9edb9ec78519d14e577ff9a9404a2bef9d9c3f4ff92002193ca1ffac787bf29091a6f9e9c367957290a229ed59e2bc3640a	1662286893000000	1662891693000000	1725963693000000	1820571693000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
131	\\x03058730b98f1a797633fa87c44826dbc30b3fc7639cb4b49aefb9a391702e2e6bd23fbaa45232f40501b37cc94574824e33da9a3a56bf72d94ccb7b80d30f1b	1	0	\\x000000010000000000800003b362ed55a4e2ee8437210aa9acb642d377fb0da0497dbf6e60397a079a9803d89e8c212fbbfeadda655d88286a53dc3f65a8361b800c80d345d1997bd7a30b684c485a607903a29012b991b22b787caffbb521e4b0d186b83b3d964c45bacd37e89738d71434f00e7b1e48da4c550e810546e684c40ca2190ec0e05226e0f7d1010001	\\x460a18de8cc6d82ef1f5ac8a154377fb5d0e7ce4e583561a244f6dae6bc6b245190d372354048be32a6d17681a4a8d6584d0d1b9743f6471cae05f6b28ffdb0e	1658055393000000	1658660193000000	1721732193000000	1816340193000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
132	\\x07b90a88b0328c6320e8987d3a5a4fa678d735074dfb2a5a7da69f51b08541ccf42d97a3ea0f2a661b488f749c2d5db74d11893df420b19a38e96d80e8a0103f	1	0	\\x000000010000000000800003cbe24c3aa8161295de9d00c545af275449cdb09b817ad8d872d043e2cb4e2e84c3d9e54e0c7566ea531096fce02e1d232342b09653886419748d842feb3548c1da074791b5ff5269a76e7b7418c1990ba9ddcf72990e3374bcf0f6ffd8e35d29b72e441564750a2a38fc734e7a0dd15efd059d7a50ea32e04d4d09930502fa4f010001	\\x108d5c2d0fea160d2016fe86e3cdff7b622bcbeafa4f4dbf0b73af84f9fc546b7fb62efeb2fd1f3b1f946a220798646cd53d1579abde9ec0c5735e05f444a20d	1673167893000000	1673772693000000	1736844693000000	1831452693000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
133	\\x07d994ff5aa4511603e815817b45ae7a200a7c2ba831241ef2f096a53d78e841d828c007ff564719d5214492d1cd1c9dad8b8f8fc32bd52cebf575e1c78e2d97	1	0	\\x000000010000000000800003c80094e62dd68fcb0193fd0925e7876f1334f016e3ce31b437863824049f43949875c89ea50624165bc0638e8d955a899dc91a9bc7f85b127478f7e0dcf7216242d7ce2c8be6a7ed56be402cff10273b1d07472ac65e0bc3ae880f756f166d0b1b60a90d4f036081c8a79eae4af049afdd901f9bd59a7e62afc197e9e0f7d425010001	\\xccaa97d5d842caa9920e36f30516149da500502c35ff8b79adbd2a2b6632973aa1274d55f87fdd471b8a41a274c82d83ef6e87161ded09e78aa6384e97425804	1666518393000000	1667123193000000	1730195193000000	1824803193000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
134	\\x0d492db7eadf4abb43cf6acf5a2c148aff448e4fb3b7c8094730ccc9a710f7c91e6c409a014a9f14156690c7be385e640b097eace96ff8c1e7c76f3ed6e90d93	1	0	\\x000000010000000000800003df2d2245f7f7df979c0e31c3ef5edd363e7ab18e696d94b598aadf53e4ffb28a9755322f2ce161e6d533bea30ec86cd0be160b51ddc8e1c8d942046596a20a44f079c2c472c77907d4796a24e19770d85dc784094114732f7e2a9833325df55c3d2c14bd054e645381c84f04a9a0753f34cc4196482adbbd6c3c8b670567f8c5010001	\\x169a531f4726b1a3c7b532bf35f3721bc0f9b4a56799ecc1805122c8afacdc8b5991ebd740596df9567d7e2fc8d228d38a9d37fd2a13ba11fae81e663e62f40b	1653823893000000	1654428693000000	1717500693000000	1812108693000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
135	\\x0ee94dff984f50fba9ed0e4968d58f02cc92f3b0f9bef37e262f9be95e1d64eb2f13a15aa0e42241ea6a39e122fc3a138a602d038ee1265b5677df8fab3393c3	1	0	\\x00000001000000000080000399f85c898d939d331c19f2e6b89ccd9bc89355128d7380854cf00ec7227023f2049903118338a006972ac89465acb862b1f09b6d11c2f5a458a9cf87325e1258148e02615c95939e92a2c31f3910d6659be1774243deefce2881fd043ef448bcf10d839e12feb810d876e2986da66e1e0412da393355619e69e64afadac4acf3010001	\\x5000b59aadd2cbb702bbe24150f9ddb26ddd1e3716ea5d63d93752d9549c7bb78a0dd4ee0bdc9b9859a8a9097834d3944f0cc46ca450116215bf47cc6928180f	1679817393000000	1680422193000000	1743494193000000	1838102193000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
136	\\x0fd59cdeab1aa01b7e8d83920ad88a4501b4229b4f286982418acb7137d253ecad8da94f26bd4525d5aacf06f634748595ddd3ca26b18a5092537d9104e95eb0	1	0	\\x000000010000000000800003b945d73a492fafa89f2ef65e891bf006754405344e64e171eba210cb422c609f249afcf584abc3f97208cff31c856af409923830a55f5a3c1c613c96b84c56661891d5b1bcccb99527845e104bab423f8949506c3c94ec6672e05a292342dd73f9e2fff643d397fa9abff36f85b392f8435bf6a2519416ebdca0a1ccf36b0ca9010001	\\x70ef915c771f8333ba726b3551f82dd63bf8f9f2d74b796a20955a9baf49fbba107e71bdd53c007b81c6ba4a71b68300bec9ba2f06d01bab389c7b4fe984130c	1666518393000000	1667123193000000	1730195193000000	1824803193000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
137	\\x11cd81178372d9665252604df7029c76570258055fb4d164f33562c121980f9e110d2ae645a1a505ea148db57f8799349a251e69593dbe6dd6947df6dd4278cb	1	0	\\x000000010000000000800003a1f5d50c366431ef95d11e46b07b394968c4f979e3d6011cd15a6e1f77cbaeb32d199bdfe19ee80add47d83035dae3dd518613c10a4d265d12c1f280164f6e12a23d68ec5561c43cc4b2aefcd945b2286f5418aee04828fce040e6f35ada25516af0d9b2a6cf5e5437a6114216fec98ba9d8042d9fafb5236ed65c5627c8e497010001	\\x0fd10e6dbb6ae1d4f4bebec24f9e7c894ddced0e250083d09e7604f840bdd9f06251f86927d9ac76958811daaa8e19e4ca514218b761f52f69fc22ed41d66705	1652010393000000	1652615193000000	1715687193000000	1810295193000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
138	\\x1495e311111eeb7c67bf56f854764972c2ccf550b924ab9f0b357c8a285342a8ab557edaf4d78316943899ea42adf616e91ba2616c0e5737ff5de420398afa24	1	0	\\x000000010000000000800003bb0dd5bc843101a4a7fea37a50c9217d0973dc344a70b8fa57c04d25581ad50325d4af49ea0e86cc74abdc8f748519da2737dffa078f5d2c4a276a30308e087ce192ab8de577350599002c0bbadeb24600f83085c453d9a997f7badbd359947b3bd9350daee65ef58aec11569a3896aae1d8141da28242aa069bdee47f324d9f010001	\\x44c8e45b17d81c487b32c0929c63698ad8cc991e1ac786173b3699f3474fe8fe7b61360b98136cc69375b8db79403e908b45c8723d2484c888b514ff3e5c2501	1657450893000000	1658055693000000	1721127693000000	1815735693000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
139	\\x1679be885e5427d0eff0c072412a33068d3405060dc3988d71efa5cf652dcc4b1d06fe3a858bf35bd286e5e6afab075d3cbe1559c09d5aec5daa0a8eaca9e940	1	0	\\x000000010000000000800003a76ac75efa4219e32b382a09fa1a6757d94e86514f18307581fd934a410b1f80a8c71917dacea663e1b5b3d850e4cdcc34ae3326c9a747a0f23456be8e63e3621495f92a3fc4b2cc45f3308fb3b336a9f03cd8a8a0d90568889884c3ad1fd993893b9123bffab076f8d17326ff2b4efcc9df8e9ead434ae04a9b17791c7aabf5010001	\\xaa264c4d7376ce98be47983518bceb788006f1ba58e2ab9bc51d070695ddb739f59fe4c0a27acf57130cae651cbe154c6342135a8d8e75e27c95ed6907f9c70b	1667122893000000	1667727693000000	1730799693000000	1825407693000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
140	\\x179d92f239f67876b03f9a4eec0d0cf16ed00c2c0806fd0aea4169c06cf56cde7ab51b3c82e2a4ba13f7caa12246a54014e38c760cafb61c0e0e39d4494c5748	1	0	\\x000000010000000000800003a9ce9752edc857c936b218fd8f8c296dd381ffbeb22e3b50e3cf0b00277354a73659b1134ca4d4ca877695a1a92c73be65db5c13b2a3aad49ed9f1778d74618ccceb3984fe71eb599f41ec124a5cef3eb73093b19d651d6a4bbc5086168fd66df869ad5a2f1c4d174c7e7fee7c0c49afe73361574cd3b26f0dd193e0c346d123010001	\\x0d3b45cdcd6c724c60e466258935cc87c9af48c077849370eadd863618cbe988b146a7457634fe3497d046cf8a2ad156e5cb6f580935ccebdbdafddc3610fe07	1678608393000000	1679213193000000	1742285193000000	1836893193000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
141	\\x180572c573edd5b43fb44694235b0607b4b1ee7257d4c3c48bfef1aa1c8753e118d87d8faa7c75ab6d26ad1ee4dd1d312e13b82fc38296d7121e5a5445d9c615	1	0	\\x000000010000000000800003eeda14de31d33220e1d5343f824adb9ef09ab5e87de57e508395dc360162881564dfc36ce292fd13c24eed26a94103dc4e7f40784ae791b6abab72c9ac6aa67ca2070615b5333e45d178cb737ce58f149bd154a2a76e7cfece22dd8b7df0e64a4134f19489513473b25a7797de0832e9f6ee794d6bd26a2ea3e87ae081e36a47010001	\\xec1947ef83b1686a8d25e00b2a1eb3a79adccae447f27e0617aee4750d3609090d79a32ad4762aa68d2849df5af1e732bf8c63393ae11da5e58c58e347d3ae0a	1661682393000000	1662287193000000	1725359193000000	1819967193000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
142	\\x18a17e7adee9e110bbe16cceb9ce1a6e81ea5af8fc59b7bda863501d9bf97dee2a1c96dace1845c2b42bae0bb4132b605e8d0ee4b30f677e8a074dc2614a8436	1	0	\\x000000010000000000800003a53c231710303076693250f338dcb7bbbc1b52a50b1cfe15a16dfcf7d527857314c179ea48e62365f2e9ca256a5d3f0fec1a690e46c71d87d514c9c7ce124c4bcd10bf0cf9f5ef1627dd4a13b54107798c3d3a78cd025bac3cfd76e9b86664b89adae5db48bdf40154b2268cc52bc2ff32522d5c1c9f06e726a556be1f4524f1010001	\\xa45e1291d5ba6f667b9b6904d7c7538d2a73ab0bafd3fc3df5cb61ea211e8dea480bb153488fdcc822a320f4d969d9cb9cd747f93877162efb9423b26f969d03	1655637393000000	1656242193000000	1719314193000000	1813922193000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
143	\\x1935731c4c48be968de681b83be6b94469ed8a1c8d00142a3efe531d1ac5fd4260b02c8784c4ab2d972aeea593a2db67edaf534a4a014d3840c60bd234f0a1b9	1	0	\\x000000010000000000800003c936ba1b39b1f9aeb41d326396f6759ec040e57b87d63241f9394d94fb3d3a0ba092d81a242f1b30a6bed85f2e15e3fa30f8056342c85b95b3dcf1e3183b9b8e53aab4f53508f1390cf90807c932c3e014b5d4263761ff8c2c2e36ea951fb166f21ab7c79c8819d8a909a11f70747202e1ceb8556cee594b65d4c802e4a48771010001	\\xefa1e7a796d544d6ae9e9d3ea31fb4ae992f5cedfd25534d5cd8173d2745d2590465ff36992856ca6392ccb0861f83e10c679a8dce2d32db68b270358400120c	1667122893000000	1667727693000000	1730799693000000	1825407693000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
144	\\x1ce59e116e3aec9de25739f89fb803cf6f69e47ff8cdf7c158e24afe25aa7758317293053ec06cbd0e2352e44bcba3d3f67ce6e3bc23291a0ddcacd9ea2dcf1f	1	0	\\x000000010000000000800003ab76e63507982ec3881ba58532b8fc6259fd368085560e00f15245855667ee80c0f42709d5d4bd50c7f1d8562f403534a66decafb36df346602195112c34f1db058ba751dd7b97d9869f5aa65e1fc9966491d0e57c21c5f84c42c66f21db259d5f96ce42e967a19f4ba9ef8df57b8d6877e7560469fb38a4e1af3d66cec84ed3010001	\\x1758da833211258c53b7b7a64513a241674f7258d50a2c6499021b66faebfed7438a1b33d3c51c9f75e82181ff05c24172406b966aecc1e616e6f5d7bebf9c06	1670145393000000	1670750193000000	1733822193000000	1828430193000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
145	\\x1e39ab27535115663c54381d44b6d44064be7429106641c0d91e5ff748a4f8f2f897eb960d12d6123a26b8d86a01fae0e86d1aa8e7feb411d4e8bdba7f43d7c1	1	0	\\x000000010000000000800003c4eb424c81bf5b45cb4b6a827891ed6d470a4c1acd56ca52f71282edde6c59b59020f98cb947661b2336888f9029c40d2f2f33c206562ef6687be53b83dfc9edd66dfc833c3ee32522aabcdf7b938656327085bee103401b64fe5c51262258d46c9d0d4c756f64d7db3c2eefd2174069486b1bada46ce7c8466c6f71027b0d8b010001	\\xc9a77444b6f2185aa8650239cde6d053bbd16feb384802fdb8c5024256fdff5a88342fb06643f60c0de37320fdb3a7f239e8a9136fe631b8e0c22cbdf717b30a	1664100393000000	1664705193000000	1727777193000000	1822385193000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
146	\\x1f1173e7c31b819bf6dda8be1a150aa2f46f08d27453c26497b80d98dd03a7f0848980049b98421f4b30837ab7c519338a7d525708c54398b65ea7b1efe02535	1	0	\\x000000010000000000800003aa82ef3cfc22cd1bef1ba7f7f7939fec7902bd74b595ce06ae674d86a2c6e4264e3252d6a0d29a88a8be42a69c4804e0893fb9cd7ab78a63992823d4435215c7a92b2f4b5b01b15fc442daba65af18957ebe6aff718132054da32883d4b7f2d73ea28cf46789d298c2c110e22d6921a691d4645c923527c991b59a7db09b7e85010001	\\x0ed47e19b715c44a974c205721dd4b4799b4fdd4dc9bb0f51a1e3bd66cfece326c8d52effd38dc5b861dd64396de705c25c1b6b1557be7bef96872d6aaeb4009	1653219393000000	1653824193000000	1716896193000000	1811504193000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
147	\\x2001a767e708dabe0bc7eaba141367a09a9072361a9221493bf4a98ca8755bfffb1b546f0f6bf60ea3b6ffc43a044bf085c9ae811700941d305c08149cfd172a	1	0	\\x000000010000000000800003dd5bd073f1d36f7ddbd16522f1fd19f98691ebb073f5eebcd3119b2a00b4b723586dfddc7e680538d698ce92b0b24fcedfb783b1bb8636f4f2d6699d895e1d4b562bfc3e41f54ec4d684fad8d6ec9d4a7f8df3414a14c0fbf6bbb7a42b3acff64988693b0376fbe24eb996147ab3b6ab01a1ddfe81c6a934b7f42544a1e96db1010001	\\x498f9dedf59b02766df6d13bb852cf78926584ee41f41331cc7358e55c0e613564139316cef6e00484278da169459d7dcc5eb426308cc8e9ffbfaa1c745f5508	1658659893000000	1659264693000000	1722336693000000	1816944693000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
148	\\x223597bebbcfaa08bc49f6bda95362a9babd2273deac3b37487f324d6d1112548b6faa7680d49ad208db653c561086e4652cdf7dbbc6b854eae523be1d1fb707	1	0	\\x000000010000000000800003c51292f6c605954ac0e67265de2be65693d8668df90d0694107be8dd4147d16c437534ffbcca0fb8e172a9357d0e4425d06c6feb36862298d68655b4ca4ec623b24444e53327a74c1a75dc7e2838a0ad431afd6dd6df319d0de41008950cadc6ef9f61fdbbaf4bd740a11258b1a3ca163b493da59cb29c5486d3eac37963f691010001	\\xf4159f0de89fde488349553b0d3811f4ea5eee4d944a6de21244704687a284746e5eb001af263cb4e8fceec0dc2022fb8fbcddc1011b6d2d3fab155a40023802	1670145393000000	1670750193000000	1733822193000000	1828430193000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
149	\\x22a5db5e4252a4aa07b1340d394211e9c26f7e74385f7957eae60639e73ebf2affa3cb48807ccdd878fbf5f942331608af9cc61b139153e747e2ed9682b7664b	1	0	\\x000000010000000000800003c4711fab7cb4e50c1bf1ad509f22de38de95e63aec71b3955b5b22563383cf67f63be250531a4ed3dc90c782956d53fe35f17cdd9e944d9771e3d81f037d1c1387e9440e28d77a50b74cbc956a183bc1c914c76300b6bae9e8677b4bf81be7f3cbc50ff33b3ca63f28bd6854ab716c1032ea2aac3696ca0ecf9ddabbcccc6251010001	\\x052caae8be907ffd9e032e3033c34f4cbafbbd543afbb3df48ca076a95ce2ba07c3a49152ae94bdf9763886ba4aebfa3f36178cc0fb3eb366352682842f62507	1657450893000000	1658055693000000	1721127693000000	1815735693000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
150	\\x2259c63c3cf35f0e70ab0b59a4fb73038aebe5a2cba2ab9b1ce453b5cff237d854b611f106e11f5f7af732edfce1f64371eaba561613e871a8db8b611fc136ce	1	0	\\x000000010000000000800003997402418a5553c493ab3a69656bfdf1b58a152c0acd26e71f81ac0da81425a2adc5a922d0d1cfbd42e39a61d62441a37aa2fe39d1e0960f5cef9b8dc4abc8f185ea2fbd8fed4b3bf6af733c7a6e7a4ab624cae4f678067a6edde96f078488047b94d992c07de7955b2024fe72a47d73079b8fb35e0099def221203669f13877010001	\\x9f40f594b8143469a6930e5c18ecb92a5fbe7d2cd3fd96a6191d58406a3eb27a3e4bb15ca523d76926d09560bad0b254ee33c8e5ef02791e29efd491d40b7809	1671958893000000	1672563693000000	1735635693000000	1830243693000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
151	\\x2b5144bf184242a6a8c988ead0a7872dd0ccae2280a10e0b3e4070c33a1ce14ec92552b862932d979a720a71cdb1f1fedcbe3eb37ef3fe447923b809185c893a	1	0	\\x000000010000000000800003dcef3c90176a8c3e08b793eb358a7c017859d6391ccc07af9795cd1ed944582c8b010d20af0e7898d5beb0e88fe17fb1565b51abef32e44385191265f34d4ed7feab9fd08adf24d888979326553088c3f567a0dc57d0546eb7404773229b33fd78aa4e52cd2aacc237da2986345f5b8c9f0326267361afc6474a05eda0f9a04f010001	\\xb32721919925d5adeb76b9be1b31e276c10e9dc7a28f50790ecd39bc7f0a35bff36d95621df134d2fe7b54eab7f6f32e782fec0f54c291568e2ff91bb6116100	1661682393000000	1662287193000000	1725359193000000	1819967193000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
152	\\x2cb58a1b76822493ca389b6f2b04cc1b0821c7a3cc386b45f73c6ba41090748cb921599483141bf6ff63bf3c65762cc67799f0ca561ebb69f9c99da471fc234d	1	0	\\x000000010000000000800003c6139f7dee27e173e6d48a8412230f38d079d9b8b1b1e1a7408855559b415d8f1eb5b0a6bf2ac4a4777abdfd725a2caa14528deba936c8bd428d909c1ee213690cf1147d2292f9867705e40b52d59b8116d6b11960955cf51db6164351a3abe720272a1c7e544e6ad91eefae2b8c9be6c05c10b41b209925fee61c85d0d52de5010001	\\x5aca954a9c52e4a3c48a8ec70848dbe37d97b8a6c0030fd1fc612a2ae85366dca2595ef3942a87b7f520aaba012d39b0bc56697f9c0634cb0d97c506a3e61002	1658659893000000	1659264693000000	1722336693000000	1816944693000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
153	\\x2dbd009ba3c36e361b349081c18b34902ab2b5ee28df0f62e8b3998ef14d67226fcda4b104590d6c32ddea5b99d4cfb05894e5ce330b334b700907a97d6da4e5	1	0	\\x000000010000000000800003eac57475d4573b7a20dc8dcd2ca61a41851d425243429b6fdea6083966179d2c93fd83df6e1d464794ff1282a66849952ec59e96f52775d5bce5368b086e73735ba35fbc19178fd1557487fb7b5ca579e08f2d28f805532411675f9c5700979a7920642fc93555d51a9a7ef35e3cb9a473257b1b7e0780ee386ff0a5fafb9457010001	\\xc2732cd07694d5a8575795fe190ed58f794be4a975d8506a0d748020c0034054a3577daf3a8b38d531f4720d4c6a2a427c1f5ee4490351db759f42a87ec21f01	1650196893000000	1650801693000000	1713873693000000	1808481693000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
154	\\x32e90da84a59a2d7c91f712e4eaa7b8513660084dd9b83531a37f0fdb3eddadaecb1681a190e33d2d88ebd226932b5879aaac918f06f9bc6f1ea88bdc9c14bae	1	0	\\x000000010000000000800003a7a2d7773bbbbb4bcf88be0b3a16c3ffeb5c2f8268e6aa3e1ee1f717a67f8dfa4bd48aeae7fe1c948ecb32e9ff6adc9f66a9c24dd02947e05c33e71bc536b68fd80298559f29efeb76adda5ef7bba4b5d01eaf3afbc227ca7c69c3af46f3b4634791d645fab5323f4629250011dd5597d7920f37d1eacd8adb7c0a57b518c9d3010001	\\xc36c0025eca0a820f57094cd8c0a360b7145ee725015df62a27de81abb49dae949294f1d58f0926c39281a5d0c98fac72778883166569361ca7d7df0468f4b08	1670145393000000	1670750193000000	1733822193000000	1828430193000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
155	\\x33494483f860ffd2af3101b4a72084a347629cec1a4716add090e8904ec516335e7cc90be8f4493307597792eda7a70362583d7ef7645cb2c02474c51d5d6791	1	0	\\x000000010000000000800003d83c00ee75bf2cfa6508fc8a561beeda7353e65f4825545613a75a062341b8d6c80baa1d37bcc5a318d3297cf6bd08a4f8690eb887471d9427770ed5d7b7600bc2524b6af30e355ce3042b7408869e03d1face7be56751786cc649c2bdf926c57582f3789bf60f9a9375aa6c1fc7b20186873244d59b56611b9a1b102452fcd1010001	\\xfee5b490ca4fe97119506cd435ad3d6d4418e15908fb297d7ba58f5b57e5f8f0704b6cb1a3523e12f63956ab062cc94972fb585ce418cbe457174e9478847309	1668331893000000	1668936693000000	1732008693000000	1826616693000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
156	\\x3419135be598d9d122a6126e8a8cd38594de336ee0974cb29b7241e112a5d10cb737f64608901ca4864e9fc403b2a32d0a06930f0a2029ca9e1bae80517f096e	1	0	\\x000000010000000000800003b49b1928b1d0559a2533cd1d5f783d64aa344a913297a1a59874e7f63d9cb159a5fac5e1f07bf5645fa8fdbb83b4761d1b50b17cb293ea08cb55cb1b058fec495cf8b096baa350715bc7e8b180c557d702aadf34ed666112e8b8beb130143a60276b919860d31cab6edce229e164b210eedc34a728926a98ef9922e9dd36186d010001	\\xd90975f9e41383c49698c61b40e00863954bf9a0b00441d9f361bdfa6c31b747708ca5e96ddc03b3c180e484a6b7a29c432805c86726a463c50e4800e09ef609	1662286893000000	1662891693000000	1725963693000000	1820571693000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
157	\\x3815be73fba994633c44a1c48545d8c3e7c97cbab1ccbd0f80617dea62e08fb9286c35bcfe4703a9ce6133ab86058a5477122f30f24fee1646de69e45eafd3fc	1	0	\\x000000010000000000800003ba38c906f713b83d454f6eeddb3665825ce9ea875ad9e44c5f2518702b88ad3e33a4a31edd6acb9c6973ddb990ab6732fb2dd192d7b4977ff9a904d8502ff13506772c2da6960432e71eba7cbef393b2a40014ae84ff2ea9c7da90f6b2ee89a009bae4dd7749342cf1b6f61f835a9ddc62e65f0c5ed6987d022486280560a1ef010001	\\x0098c0c047f27ced8aaa2fc7b67955bc17765cac6ca4a747cfa1c75642b63df074439503e06221322de5d8f36beb3bc0cfa0538ef8c42310c85eae141b6e2b03	1661077893000000	1661682693000000	1724754693000000	1819362693000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
158	\\x3961c5148399ad74a7f238b9abda26da41971220be385b4d9588e0bb4142f09d17c53f0a04ca89e11bfe09ce8d703c8f83a79f92a1e50750cc8536c652c975bd	1	0	\\x000000010000000000800003ac3bf45638b4abf5e5af1d3338855f6abb0e8d36b7880c6cfe1164033f1a024f9fa5de322db58c4ad21453d37f7abdbe1aa0f54eec7f39948ed85a50e5493256fb273bca1b00f376e873589837a2c3f71d80bbead848bf3a70a64ff4a988740dd881e2d471f4086cdc972d2ac83694b6b50126056e90e1f8d8cbab0862c61cff010001	\\x5c0d9e3c178de1d1494ee125aabbc87dbd983e00a843e1e3e87699db759a25e7d2c257dc554d83ec8157c58dc75db13137b70d60bad782e9e031b221d5a34103	1679817393000000	1680422193000000	1743494193000000	1838102193000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
159	\\x3cc51b31379e5cc0918b26237ad4d4eefaf7994bffd386c6ef8d29553252518786de8cdf236aaea139f4bc87d745327bfbbaf0c522a657646df7a26d0511213d	1	0	\\x000000010000000000800003daeccdb9a4b8398b9a7f9fba8f1bd47a1689c3fb91e34f4cc164d97fcfe97404ada9899518f0159c8bdae4b8b2cd02c3f480a35b2518ef22c86e52cf005d3d4469f20421bf421b3c5a8ea7bfea013a58e677c40b0be46d157a981775e9df77e783e2c41aabf1f922473bf4cc733ad3313987159416d555f96b16c88eda1e321d010001	\\x538dc65730777bb728a72195cc128f5daf90f8cf6a6518395312cea8729758d78153ece1506876c967eaac0b74097234044cebfed843c69f518beb23ce649304	1668936393000000	1669541193000000	1732613193000000	1827221193000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
160	\\x3d815505493b22e251bf3a45a5fe286c6f32ef0d50ac629e9af3009855fc9ebe2e08387d6b75138b036b4c24bae63cc0166cf1255287e89bdc891b3611024707	1	0	\\x000000010000000000800003ab0c4ee347a66b6199abacdcca9a858c7b770f18a782f029d5f80f48f527900368de7157a7a933f999849dc2d20eace61e55485971d2e40cc9745f11b6833bdb50c119e54dc67b6ecdd832aa0ea8a3d4165b2be06a09d14e9a7a1bc13e7972280834b8593efa08e1f0d42f5df161e081af53ee09ef6408e1eb5fe263656f85bf010001	\\xf45fa66475022776e7522a4ea924d0316d1a891c7fa0275e6c0512016f71cdaa9bc237d240b264d7652ba4e377b81ad00de62b5a607b804605675942d86eca0f	1664100393000000	1664705193000000	1727777193000000	1822385193000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
161	\\x3db548d3440975371b89db0cf4f88e3dc3860bf64e73e2d4e917a6e1c4a68d3f9c315a43be22aba1bf63662ac7135a2e5c63fe6c050e4c4c7d1dba1e468e4112	1	0	\\x000000010000000000800003c7facee63e0edb24378e9ff84038ae0f432b32db8d7574e49c1e26a36b77b1c2e05ac1caa8a046e3f474b29568848151e7e3628d91e550229d626c6177c79b318da558b3d699667107f44ce6b9fee22fdb1dec490a890e94f6ce7e5a05244c8299a6f0b4874c2dded253367b8474679ff4788e3c56528fab255e1f2b328bcb71010001	\\x5f940f3f8f39a63862d442a9d42111a7f84791c66d53e41ebec2e8fc285f86d88ca7bb0f70d7b8d183eaa2a39b7fd4fb4bd63c738d9599e99531a9a25bbd490e	1656846393000000	1657451193000000	1720523193000000	1815131193000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
162	\\x3e452b29f941e48c8be1bc59bb67673092bf8a2bcdd4b83a045c26c0124d7efe21deb84c8190eda23b084993091c08c6a78a87ae502f59f6aacd82fc06819928	1	0	\\x000000010000000000800003dae5b75b10940ab062f3996c48191ae879f1d69d020926dd9878323d9855531475eee9d43b94691bedc035ac279c4d502a04cba2ec743040d5fa9b239d9ef0ba6d6a94bd06736b6f51477fd89ffe90b895ef368a2383db06ce88116dfea005ec13c34f503d7c233ccc4cd986a32387cfddaf7b2cbf61ccf3bf5707cba06154db010001	\\xc224fc3afec67e12223e0176bdedacd552942f0b4152bd149f29c16ccd1dcc23960c4b8fe0cb0766c91456dba9b648787505e93e78a18d6da7fba55d03d18807	1659868893000000	1660473693000000	1723545693000000	1818153693000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
163	\\x422159edd304d97bfb9386d4c53961e4f8fd7fb2d9a3ed1d0a074ca825d0c6a04b741553220ad544da314f740645fbbf3a08e38fefbd1f5dcfaef6ac68025a00	1	0	\\x000000010000000000800003d04ddcbfc4f4ccdb8707bc49e95a674e18f8541757ddcf86e7074abe119e6f1c3ad93d8883d91212cc95f67e0ff644969f279c330b9da345cd9d1fbe2bbab8bc47414092536e55081afdd2cb469f790b5e245670d1f9de778fa1403c3ddd1d2075bd4cb87ce2f70df537460cc9fcaf631ca06b9e16da622e963a34d067e4a775010001	\\x90f377ca04fd78594a673a214a9c262db581e13058b168b2420e66a1ba821639bb5fded8c16542aed38683af89193f6047b42d7dcd0ead8b9a6ab1e49b9cd701	1664100393000000	1664705193000000	1727777193000000	1822385193000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
164	\\x445183d260e5029a504457fbd00f2c39642b82e4de836ed6bd08d3ce1c4c44c88ada300e7139907c3ff62f2dc212a89eb6c7e9d872799cc1646f77721d0114c2	1	0	\\x000000010000000000800003e4e42657eb7f25eafacc65f98da1a404bfbe536539f8e5e0ee654ad8b300648eff1ddd504dd1cf7babd66d3ae5a40132638b6064833c3506037d2e15290cf3b8fbe2b263b6499342475ea748767c923088e5228e0a4f9b0c8adeb663a5ce5751c85e5eed9bfbb57e8cae5edd8b8b633dfcf29351825349446735fef49d057747010001	\\x11c076e61fbd1870f87f83ac39e1c5ac3b1f692b9ad4e867b2f00eca8a1d85d4975f43edd6d604f3eec86a11a57d88791cc77e9ec256d1dffca0dd5c060f2801	1670749893000000	1671354693000000	1734426693000000	1829034693000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
165	\\x478d6e67e2c959efd64e6e3ebc5308895bad7c05db6e7786520b2be624aa09a3f742977aa979664309c8b50c7f8aa77fd6abb437a146a4b96d349c3e85681d9a	1	0	\\x0000000100000000008000039a69f68cd37e1eeb446b0d14dac2980a23f93df0195ab74f89a283c6ede38ac71d9e089e878abe10d63cef8b105aa4f5f637bc3145ce5a5b332eefec5b64ddb01d4160c164687ef98a897da403edb80f652664bfcc316db0da864be7d8573202fbe0172b82fdd0af558682adc37844d6334fd672449b53f8fc9847d2e9f7bedb010001	\\x6cd43951ef8c46f099e97cdb730f4c6a71493b16a3de1f7430980daf9e9aefeb4f6f604339fdbd39794fbe6b0c2283f6f305ecb85e3086115df41e5a4c29f50a	1674376893000000	1674981693000000	1738053693000000	1832661693000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
166	\\x50c92a52c63707ffd904b30473b10e9ca357d3cb43f85b0afda3caac1b8318ff14d1bf0ed69667d4c069df14489cf9e8ea428f0305d366e617fce0189b85ed6f	1	0	\\x000000010000000000800003fdb583f26fed1215d81e3598b43af6f3c61438b1587fa20249cd53052f6d973f8247559470c18ba2d3185642399890a4830f97f2db86b8448ebc03e028435bf66716d346e151ee0be984380202bd03de5461406b8d906275562089047cb1280c26a7d6aff18ee75388d747fd1db7290770f387ba404fdbe02e7ebd1349eb8f31010001	\\xab7d9befcd12b32c059d96051dd01441d90ed14dab083e5e70ae9d41b46b2b7b32c0daa517f3f982ad1e77dff51d449a2ded14b96d95fb037cb247f2d05f4002	1653219393000000	1653824193000000	1716896193000000	1811504193000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
167	\\x55bd5a8743b5eaad653745cbe0847b9725f44f5f193025ff91af768415a5a058b20ba683f797f3ff1e6d486edb99384dacc17aff58a41ca10c458853c7b132a1	1	0	\\x000000010000000000800003cb5e24588427041b9882a5131a0b974283bc4578afd9650cd63f6a9f6ef6dc4331fda022215614a500efd35e694b55e327542cba569fc7e04038ee54f001bd44dbf25cdc063938038f2a9dcb77dedc5895da74266d8c32f6b012fe7fa27ba0af38b144d750336755522a54b225e5366b930eecaceea229371ebeffd8755de3fd010001	\\xda3b6973ff2df56259b3d54a69edf43f5531a6bfef93b99f2e236d8acfc0301cba34e5fc6c1decc8c4cf02ccd162f3b214ce319961bba89975068daf1c5f2806	1672563393000000	1673168193000000	1736240193000000	1830848193000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
168	\\x563584d77e851aeca1b1866ef85ba0b37f2322422ff5cbc3986d71ea8e0ffab2bce2332e02f5bb629a71e98c89e9b1f6fd6fb76302a9cb1c75b02d47df3c42fc	1	0	\\x000000010000000000800003f9605a7d52d666d16784cea5e86aab74471b2292b20e3f122a2bd041b6d8c36a722d3a2838b94fb3a40ebcd58fb6e78854530b459ef856255edd87a39f1a6565118b8f95a13e0ffdb54adf902862a502bcd1e14a20d75fa6496742bf8daf40c9d53692b4f76c3d2bd4c1beb1c758dc6983166cac69944136ce28a81358ab01d1010001	\\xf01db606dd971813922ed21e9bb046395dfd1c6cbefeb533006c6ab9536ca73992c15e8df3fc27ab116ae7dceff91575e74fa645371c493b8914f699a174ce08	1665913893000000	1666518693000000	1729590693000000	1824198693000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
169	\\x57d95f3fd8d7bc2ac3bb50de6f2647485e15deed2160165fba5fa9d0b450bb9375a75e175b270b83958d326a0371a1bedf6291fb842a7fd02e6c954a17254a0c	1	0	\\x000000010000000000800003a97ca9d941028c430ed5cb42761b00643302d453a2eb6bda983f6054efc62b3f1647910e149a07e8c50b54dc278463845650c91fa8775c0228efbc5275bfff6e320ef2f625c3927325ef7e0ecc6b5fddea2c58d8ab0c21d61f76dfc08fae3f9fadd9d27fb4275f556caf18d56616682681988e1f844fec1aa675271f9e39974b010001	\\x9095ac10d9dbc3c7f3d8b9cdf674983d5691645710b676e77682d8509ff7a11db44e756e4b067329a548b2281e3072a5ca958645da8660c0360494e68659e809	1650801393000000	1651406193000000	1714478193000000	1809086193000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
170	\\x5e6169634aff5f864309ff4aa48f48343abcefb590af090bda83101d65bcb4de4e8d9b0e7bac06cbb7652b3a870309e58b1ae740772943f75e3ace3c2e285ba5	1	0	\\x000000010000000000800003aa620151847bc3749963669eda3f1553de005106cca276ce60cc492dcee8d73a8fa695980faf5b5259040f12b4cfad9e1f360300102ba21260f78e3207110d69d40782fa16a63ed61f2e64129364f7f2a608ae30f2e01923c8fac7b52a675766470d6d3fb66379181287cf219d6a1f3584b01bce628366e9bdb62e0da5f11303010001	\\x402eec3d6281eead3fd39709ab661dc61bc004ffc9cf5c3c04958fb91bca8c76e856acefdc5b3503a4f8a6565bc2abdda08a417ede4016ade753741074e3a508	1667122893000000	1667727693000000	1730799693000000	1825407693000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
171	\\x5e69a4874605f42b5ce8dd313ba7c7afc4cdb7cb1aa016fdbb190e0b7b02ff4d766529623e528f796504d8f125ee158140e82d016a7811bcc1463797287289eb	1	0	\\x000000010000000000800003c99295459d0ae465b2594901e8c2ba5ffadd80711cab729e70af9a1c0d5511d4ac153c9def0028042776686978f4d4a60ce2f7f67488dbc6ea9fc14fd3849644e044900e2aaec5274d19fc879ce5d5dbcc5b51d022a384fcd6e87f201a9d72658104122c50b21178882de784049fcc53154253117b7e61bfa2f8b22b874d75c7010001	\\x06d649b47e4d6be3d77de7a1829248185ea37347a24b2f01b1b7ba8e2c56abb80b9b993160568290f4088985544afcd24067a0c96985d6b8871a4da789f3420f	1658055393000000	1658660193000000	1721732193000000	1816340193000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
172	\\x5f0d442254fb903bd6a298fe65a4ee32299bb0e41bee489dde80335a083820a9fa6e8a0d3c6082008ae9e0e34ac939a496abf7c4b15a7ba7373cf1a87b95e06d	1	0	\\x000000010000000000800003cb68db7f6386977fb9e75b6c73fbf2e0f5011333c64ee0c16ae9c2e6fc682d64a9fdf07b8193308d507b7797782f997a219cae4f8bc018bf11df72dfaf8c2d54b15bcd82939d7342d376de9a678b3d5793fba5814f426eb8d3ec789a492b51bd776282ea8dbe7b8eb66ea276189cf6f1ce86b7c28ea21d241c996613f15509b9010001	\\xf02040380b49b549440a96d2300a81ed6585403803cbed1702b63df7b181314b1d051658ce9ec3e567f68794040c80c1e24844d6f318c106de8c71fd43f4a90f	1660473393000000	1661078193000000	1724150193000000	1818758193000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
173	\\x5fb1e46ed72a8414306c33d9b91ec3fa2c811ea75ab5602eb0e4c7313df5e50fac7a4cd2d9fa2fc2d0743a356320275fa2b396c480aae1f22feb721a51d09e75	1	0	\\x000000010000000000800003c8567a49b62618fc5e98aee8ea07b10e6c3e95007af61f693b44ff9b4e786d083beb0656730afc190f993b7d6bd259fc339f91c75ec987970ba2354e72b4195dc2669be2ea3b66f4aba34d630d5110305860b2c8a7f36ee0da49a942087d1a5ad47b46ff7e853ee9cf5d32da68246ab561cf207918da426a1058d1e4b7f26aa1010001	\\xc3f555be1c51d162946ada46fef41f8d6e820873b6cb1280e40c4c64cc20330cbb4233604bb40dab3590f8c5950e9dc17975e9989788de745194929f42f6d907	1678608393000000	1679213193000000	1742285193000000	1836893193000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
174	\\x65b1874eae449783d48de4bba0cfc8c850293ee273adc1a6b83fe8bd67233ccb0b06433a1d717f4c9153c7875261c0cb8e9ac1b2068a20b76ecca6a19e55bffb	1	0	\\x000000010000000000800003b0fd12668248c880e1683ddc060a43d03a62fc377df3736dbe29c2ae80102e236b8a76c106215ba93fe94aaae461a44d21228f61722d93556b754d65fdd0b65ac2fee9436a9ba5fda35cbe8261ed5112d38ec0248143591181657ec4cc7f3cc3f94d3d6cf19ae31e8058d67dec88b59fab45bf8948e1c7b5c5460509a8fae8d9010001	\\x90683ef993a3f173a7c2586e6c7f971ecc89457db6050db33e6b3e135efd3a49f93ee3022c3488b7f4f48adc4498f4e1e54552ce204549d936619b2ff0ea790a	1655032893000000	1655637693000000	1718709693000000	1813317693000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
175	\\x67997c37898fb9979b6c052744b20cedb5f14055a0109247d7cc52b80c8cfd249c039ec95f62dd2bc5b5efdf83a539f95773e179affa1e0959c51bd5e9637e76	1	0	\\x000000010000000000800003abb2cc9dafd1b9dbfdb30f29c83e919b221dac13a3f3482e789948d6bc0d81976c0b507f23aaf04ea19bae4491da4ec7a6796cfacde4c6b5608fc6bf5b311cfcbf7e0eab967323492ec52733fa47dc3f9ed630248b04fc90bb129c123cebeb42a9f2d902b3087d8f07462291a9b41bf858da0e3529fac89f2d2c77391d458859010001	\\x9314e2ff083e20a552ec9442c4e7a885865cefad3588d3b2b6c0d58877138278aa2899f69a37d96c66fec9f88b4d5de5aec6b869d4094c25ea5525e6848f7507	1673167893000000	1673772693000000	1736844693000000	1831452693000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
176	\\x676927c171d64b19b0921b8ea58d026bbf756ef94f1c94a8d5d05639961f4ef83cd150bc721d71eb811805ad511f1585141e6a70d7b15ed8a6a2e1f339f6f419	1	0	\\x000000010000000000800003b88554db4214e2afd984adf0e7f7630a25aa5e9f29eea1b4b3288d2bf51de8f1367470724a8f2a34be56c833057910aa7449f0dfd49afdfc0d7d48ae71dae5d2c573b532535ddecdbb881782336aca00206024593e9589b0837e36c45f4ab73e6a97f64e59549909cbf10dc4b318bd450b4380c41ce9950e067429158d7fa6bf010001	\\x72c1ff83bc73324c8a557548973e55e079f592782cdd1703bdd39741728324e4585d333b1a10a0816b7ce3d984b6e6f733c7e24628b4bf4721f8a93497ddb803	1665913893000000	1666518693000000	1729590693000000	1824198693000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
177	\\x7385a242238f25d1ca37e51c99995e191a451007b739caa646d33eaca0de24616dfa8f7d827ae8e2e4caa8cc8db15e34f16eb8008cbba9f21ab5e2a49fbbb1da	1	0	\\x000000010000000000800003ed11bd28d5f2d48f67af81e145baeee2679655c55b8134056062e2271085e220128ddeb5e62baca9b758cbc3067717586909342dc2df66e15caf5025813b9ddf2c1d6775514e9d1c3b360a1387300bc6cdccdb626a26769d5f0b1c9d90b5ec4f893dfe817ad44cc529d034009386e663b4846213c8b5b3a7a4bc7f26135ffc6f010001	\\x9810197a6cb9f307b240681f8a0aa2e83d31f9531941acf0d442e22b8755f4558a544e85e74ad340cf9a9a166118e39cbac21152f3bd8792b8adc631e633b80e	1674376893000000	1674981693000000	1738053693000000	1832661693000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
178	\\x753d56d009bad732b03bffd870fa9395e6aba874e648290fbd1eeaac1c89018e8eaeab752ad5a133e53b9953dfabb2ee15ba8e8ada77e157f568afb6092548ee	1	0	\\x000000010000000000800003aff85bd64592540ef0f0763bd0415dd1293dd8b4dc26f748b29604a2bcd2650ca755464a45fb55c097d8e6e68cb81f546b626d4f67d079d2cdfaf249f697a761cac548a943fa0805a3ee0714135272f243be805795afe368a9a5633afc056d9d6abd03253c82ed5640d1d7e11b6627ef10f6a60d8917318df2b2494f0d352a85010001	\\x5b12bf8a1ad3fa0f5ce8ef911bc833c5e0088306f8ace9e05f7701af8b8831503f51034f7ef762f70bb1b39d11f1d81e4b307673c8a7d14a2058df2d74a9fd0d	1679212893000000	1679817693000000	1742889693000000	1837497693000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
179	\\x77798dfbf47569597c5264e09000ebd222f92a8a22ad2326df7f92a14ebb18762e31af49e3a8b5afbe35e33184e74478997ac24185580c39849bf6536113c1dc	1	0	\\x000000010000000000800003bbca2f23bf1b876362c88992f49d63044e657ff3931f504234f2966d0e0535be0f910c6342d8fe758e134658355d042a624dad5515e5b94ae8f9f241ca7da7da394a7857e1d6e37d1f4409b09eea8050229a45551f5553470a13923b95fa46352534ebf54ad99f9fafdde48caf3f13dc29d6c2962b277104de679e92795f07ff010001	\\xeff311ae8ca29182e9fadf61cf44fd861bace0ea56b77fc9dcd1ae5c85cb004a674eb1120b29d7aa96c3afc98c9a5a7379546715fa7c779f6bf5699ef574830d	1657450893000000	1658055693000000	1721127693000000	1815735693000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
180	\\x7a998d7f66c91bb43953dbabdfa2ca8e0a99066ee028d519301df45570b7f269e9220c925838f7acfc185af05494ff22c42785315fd68ff42287fdab5eea9841	1	0	\\x000000010000000000800003af2a5c0e230bfedc6d164750c48cbca11110bf317690c3be2ee09c94b0c5effd6b8b44759a667ad679d05c975c87fd243ded7066d7b268e1b00b48cae961bccf78cd9786e9de528074d7e1f0ff1e3180b6db5750f07b9f6d442ccffc30bff68be319a1cb27c0cde245238fe779b053e358c2dd715b86021c657e1844a31d6b7b010001	\\x38b08d46efe406181e598637f8a3597524f96ce4b0fc7755a389344d5ce378b8e15398e697736d5546d4a29dc8ba4fc05f131017b3e1a18ab299478321370e09	1651405893000000	1652010693000000	1715082693000000	1809690693000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
181	\\x7b5594c0ee3c10e550a0a3bc67873181d35593837cb5ba96164fb6a1d891da6ba31cd80de922a9a31966d2c17a5c4ffedf0890802fbe8fd24ce7f00955ffe5a5	1	0	\\x000000010000000000800003c7d544b4d5ea11347c81c651ebedd04abe0db8c8ec82f4b48097a1449c3fbcaebe7cf453ea27505ad232828c0c80da88895ad0ac32d8379efa697f075131c01902507158115726a62111d55abfc71fc7270b07b65d9e9b7129d9a7833aa6b7b3c29a19e852de74960b6a60d6093a8d51c163ccafdccdeb7fddc2148aea5d9b1b010001	\\xde7135e1cbaf1c8c7409ce4463070d676a21a8075e848190c630dfea3b25a007dc7e76c255458537b35086a2a14b3532f5eeddaface8ec02238f17929da2d601	1656241893000000	1656846693000000	1719918693000000	1814526693000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
182	\\x7ee914d7e113a9db4378472aa5887e61bf546f4eebb439ed8c49b7d1cfcdb565dfde34677373d611424f9dee515f91fd0f613a8f9d7ba45e28eb3ad2838e9d87	1	0	\\x000000010000000000800003b704a5897fc830e1beb7c788509378025d709dda1cfdfa73ddbea515d0ef57b3deebcfb3543bb1a4fe7440afc3dce9da30e9795e69c6b0e6e2faad762a890e103509131ef4025f69749f4353a22852a806bea1aaf75b8119da32a5c5bf0b2382be3f0df1e0d2aad0154a89e17709dd712d44f18d5f208da2cf445c2757e57edd010001	\\x8ef780b42d2a82e7bb8de3c4e1a740eabcd45c7b402ac5f355e9e553ad463f56f39b8b8d45af889dea9c6738cbe81ba2d2b51c8f2d407bf08dbfcc33f8b64106	1677399393000000	1678004193000000	1741076193000000	1835684193000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
183	\\x7eb5ad6b6da54b77e8d62ad287b67c069f812a326e596120993a572165e002af1d44d2cea692e0d774ffdc9de28faa9fd3531ee206052842eba61666a3bcb7db	1	0	\\x000000010000000000800003ad912c5ac392dc2ea030117aa2d89dc4e81e92a0f2febffc1c538ea92d25924a55f7e116b9f77a7051eb3098916c61f08a5e664d32f53648b729242abcc9ee3e2c1fd02bda48c12b0a9e58566808441d4fe33d10ffc0d3b28cea5ed0877477859c2326e589d3f7778d89471c180a8460fc8d74eaa224c3f45e801c719aecf275010001	\\x194f79317cb38118b7cb9a710278fd26fd737259b7f6434e4378937a177ed301de7fb09bcae66981879f8972aa4233a2d99aa31fe9ff630e6d6301cb4ed7a00b	1661682393000000	1662287193000000	1725359193000000	1819967193000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
184	\\x8161cf28edee21a8788c576bfd01ae732b96a68c0b30e8547abac834d7dad026d41605bcfd9523dd4fbe5f5a58cfdcd6fa7cf81b757eab3869530127fd566544	1	0	\\x000000010000000000800003cefe34b1282aae7128e4779704fc4b1f83e6b7b8fb8a7339380b1ec808260b726590a3197043758abdac523d65237cd05e00127068751e3239c24b9d53df206db3d8269bd592402522fefd7dbea31ee2b3c627979db4ae08ec952f08c0ad8ff1c20bc030be10ec33676af87f2bc0b44e31c5c599db8382d503880d1cc4968175010001	\\x8400697311190ddf311eb93d8d6a0994c6e85e2119160d8645c198e65b80731e78be451d8ee39aa65ca415c6db226a22c14e6a034879709e64492e95c7ce580d	1665913893000000	1666518693000000	1729590693000000	1824198693000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
185	\\x8419b68132003cf54372f4dced59f15ca0fdb5d2093ae434e62c6095de41b5c7fb68c2920765cd78e3dfa630caa9f0da7040f917ed6b57d6a0f07f0028fe41f2	1	0	\\x000000010000000000800003c9026eb27026057a0477b291801399b0eeee7bedc0f54cb80925ce1b983bbcf1d02e436cca90854ef4399f30ab79e56c2b26c38a8f9032b5be2bbcd106d6631e303acee4b86db831504dca024abe023576e40b4793c9b4daca141a45e96e4168d42fcc72c8c4faaa1d52e5f388f8bed2d264533bb731bc28f70595ad83ebf3df010001	\\xcf3f33d1e6f4c10cd5003f224e57f26030e04a61d5fbd5e612ba930834784429c4e999d4343050270f7bd19304120f7fab764b824479a80945c42ecb9da8a204	1669540893000000	1670145693000000	1733217693000000	1827825693000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
186	\\x84b1a5f83547210106af22e606b67ef40b434d27ec5a1dd234358d9f19afe10a7b88665c6c433ff6fd3025bb15c9cc098a5546b90f1c6eda1d91a4090a12678d	1	0	\\x000000010000000000800003c47c8d960bea7f99a562cbe6edbe8f955fcb107772f42521b09df733ed39d63c79e259c2ee68b2b6c71323f93d3488a4408b673db0101065db02914223fdff68e4c0326e7a5ccea5fcc05f399bfc0e4dd2217ff7ffa292de5ef2c31fa0b0b09b5639f9513c332d4d134c471bca521eaed4f205e6d7a2013a2caacd7b73b0c6bf010001	\\x6127725fae5a1898ca1e0371562e80dfd96e63a7868053d4de4519cf21b4c5699d658bdf1e99e97c8cdeba65a2b8f54ca6784aba6ca32c644314df93007e4b0c	1659868893000000	1660473693000000	1723545693000000	1818153693000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
187	\\x8b1df28927b8b716c2f823bf0d03b1481cd495d12bb91009f680574107037e3bc9876014ea86ff80037d75acfc2509e61c046be631bfcfdc3f7b5327c44cc851	1	0	\\x0000000100000000008000039b6bad60f5bad805814915ff90465237b36eca911f065d5d596cf9a82cd6e6bc8d86582f80700fb1dbe7e3f60ac19394c22a9a983cb915805a067a41064fdc7bb2e1bbf7d2bcb7eae05ec38a347a168f62f13fe8fe21d57630c3798963637780255547ea708ad2a00df919796c1a1c59e8bd70935be765f93c950363cdbad6a9010001	\\x6a964792fcb7291d228de9b213ac1310aaa9758ccf77dc7a78458aa4cbfa00ecdb7114aa477c84d312af862c41eb6faa36a24681734861978870f0b69291a40b	1666518393000000	1667123193000000	1730195193000000	1824803193000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
188	\\x8b11c5716a2371e69d44df3d9e5db0a949d8c4eb1a00b855fb09e8b7b738a457a591de0b08b80ab8b4acd0959a43fb01c5d0ad42f99b59a427e02b66bda4828e	1	0	\\x000000010000000000800003bce689a123d4752f7b35a3f3e4e3310ff490000b2d24904423e81830fccb15eb1679b104d485bd4b37602fa42cda9a96b5d524c3a6447217656d49d63f940dc5f63296985c598840d798de68296e06e63e48171871476a8837d9c5142968f9c12b172f8bac028b04cfd0ae1cfde9fbf77e77ccd175c52609c2a7c3839b307e9b010001	\\xca70d426f4560457e7cc4a7ff06f29ac9505455f54510c59e163cb32233436c599c300e00955373382ab4905750be0c05a180184da3293f11a00ea9b4596c903	1652614893000000	1653219693000000	1716291693000000	1810899693000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
189	\\x8f2520677630e72b6a69c92e7780f640e3418430f122c01eeafe2c745eb002a76f7a397ed0ee241f792588de552de407f441ed4fb7dda92c57f5dc97f9ca6e7f	1	0	\\x000000010000000000800003bab4c238a3bcd2157c06483eb9b1960938969b6f7b45930d77bf1903eaa56617551e0adfbaec68d437599a52ea56170bcd2ebdc0b44bf854e896c65cdf3bc7b99d56f8d6d51f6d7978b5a504f289c1d778e339f3f41ec3e674f8f89cf8dcb10b412b17fedbf2a9930a599ef6e50c139d96dc839a1e606faae62d8d9566d2fafb010001	\\xadcec58c0f413b16cc3d3391fa18c5200d31093275f4a07b599f04c0daceb07cd738368f86ae7573dbd4cae9c99aa638417d808ef08574613157cea0062d4401	1669540893000000	1670145693000000	1733217693000000	1827825693000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
190	\\x915905afd4a88c2a3300fd1f560e080f52a11228bff6ed50ce636d898d0f8af68a49facfeacccc4ae6cfc162461a92dd1ae4746e02d74217df3f27c632baa540	1	0	\\x000000010000000000800003ae1b59581bb60daca04b4422e305520a98ef23bc6f593f56cdbe67f4ac639950a8f106447b15b581de1e837a77a0df6388a6b990474d4b28110f42306abf431eb3ef364bd3f82cb5154b91d4a7162b793bbf8afd2639658129db9c910fb2acdc346249dd6d8d1396a23288918a6a747936c054dfc43e07c15b337619edfccfe1010001	\\x4f90ac7d2bfe0886cd0cc6b4521f740eaea806b857ffecbc08c6083c5a50ce894954a33929eeee0299ff996e625a2fd0c607543ea75ee7aed61c2949f08c6301	1676190393000000	1676795193000000	1739867193000000	1834475193000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
191	\\x91714538dc8e3edc2e2ea35eda912f11fdef4e3c58b9a4a049c67671c00ddc68d453c850e956ca9df140e15ec55b66eac44cc21c328ab3f868c8a43b5d77b6fc	1	0	\\x000000010000000000800003fa3ac760152edec39dbb64df0717c5b46b2ac5b70fba6c662ce054845601c9bcd57594d862b13394413fdca573a5f4fc669548c5a4ec2364bd9ed43dd1e4de4c9d0fbd10208f1b156da9d2e23a90a00b8480db604a87644fd5434f1573011de3b1903100edd05e440d7b48c9db6371e1e57dab796deeb43befacf5d1f19aed85010001	\\x397748109bfb70e2ddf437701895bb374f7fb6e077bce32fc72b189ac06ce8ffa564f151e6721c94b85e24863211d001e3c8c5907ef24beab0b6d883e7886f0a	1656241893000000	1656846693000000	1719918693000000	1814526693000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
192	\\x921da3408594979aac4eb65e5a7eebc2d95db96651027c51ef529b3ae4aa02cf6db91b71bc27e2b073e5d44302087ee2f519714201f6773d26098ef5528a9d3f	1	0	\\x000000010000000000800003d063ba3f0bc0ebcd8969663aa755916ad9e75a4b1bf0e154c44a223a069574f471c7ab0d76d0d37c310abc6a722f2942b3564e825ea73b5283e974f3bcb6197402a8bec0a9bf85d88dbc1ecc53e7c13322a3cd27739b3053f00ef4db1783c6e273b3d18e58f23b7ed2a03f2ed2eba60cca5542c639b5f953f67a8463db3ba10b010001	\\xbe37e5d7c57d1a3f2e97c5c628677a33442a9b4f0eebff85e18b53a134d122165c829f4397a749463a2e0e4f0b598e1daa42c3681e2a9ac91d09ef04d18c3308	1672563393000000	1673168193000000	1736240193000000	1830848193000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
193	\\x95b960f67ea079e4847cc9168f6ba08a5554521d338aa211748ec56cfe0fcc97e65c293aad76738af1fa36dafa261eb2cfcf107d698d73ac644c80db8f2fc825	1	0	\\x000000010000000000800003cee1a7c23abe9a6b3a10a6d9dccac9ab2d8ae8d4c4e877154cd8534c074912418e8a73806be7a8b811bc932885d5909c707b983ab28110842ffddc3a471af74dcddd753075180b595baeb894f576c37dee5866c7aa229b7e16a4f31b9d9ecd4f79703a856b4450cf2ba521d8d12b909f3b414783aadcea71c84fbf71d6351ec5010001	\\xae7bc2a073ee64549b82210015177c9314b0ca95a11456ffd34abd04840df0007d53c9ab3645f3f034c799d01eb8fd65931377af2d115647baa8f4b056cf460b	1674981393000000	1675586193000000	1738658193000000	1833266193000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
194	\\x966d4a422a60d6373581612416f62c183fb81785c4fdd57c1299b22741b958bdd848c567d7cc55c4781090545f1eacbd980efda3d4ccab33fc92e7d74ed27ed6	1	0	\\x000000010000000000800003a9b0e3109e447a3892002e18551b2c89193e7ad3b8dde230fb5de13bf7715f4e23cf20d8e5e9e9aed74a7bbd0517093661238cdce0d8509786d890665155ef0b66ea976cf80fe1770f6f874900df85712c891c7fdff1866ff520010b2f8bff90239609eb6bef3264224be4982167a5e929b33b56589fa28f5830f58fed538339010001	\\x203570a482ec74052a17cba9ffa4f5dfa6d5763283a7652a310f14ba869465336f4778479b77c7e7c2eb7fc2047296c13c3bcacb56fe154ff24d507b0dd8e307	1651405893000000	1652010693000000	1715082693000000	1809690693000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
195	\\x972d2068e0171bdf9d0e28af6f9eb8c537eb0645232d422d1fee89f8d7a73634b25c1b7e6b5083ca6387f7f21c310d3dc7966590db4ee0a84082a0bb8fec15d7	1	0	\\x000000010000000000800003cae1326be567ad1be2621676a9e36ddad65fe96eb811cf49910d83c71e49c0f97920460886f34ac319deacb987eeb549067b36666793216a2763e5923b707423b7d567b90546016587839c2e5d910a92476b4601cab04bc17d83ec21d35b4ba598d5f7b3f0447cfedb9cfab7491561ca53a4379071438f3bfe6edb507dd61d41010001	\\x01a21285f9307a59887934081046fa5686e918040bbeff889df12f5c7f2072387660eba6a0498c584564c63caa00b839c4860b0a7bf4c56f49c6ee46f630e905	1651405893000000	1652010693000000	1715082693000000	1809690693000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
196	\\x98913fea2594538cf972c108e6df04babadf681c07fab99a660c6862ea19bacfd8665984b6cee038c6ede6257b6bc4eb4498f8539bb1c3584c0b76d16ce84c39	1	0	\\x000000010000000000800003c785c3e253fcd4f2705686858eac9c1c1175a95c15e1259ce381dd0c99028f864823bb6b2bb8a3707998f03f7c6138443da1bb498840cc3c2afbe6a4b811fdaa29823a5daccd5b4d8cb6957e17db13ed1e7665de4a7783a5894cfb15c16a69b01d1a86e03c6d43cd82f36ecd61717ffa0ec113574cf4f0bf9258fa4befad51fb010001	\\xeb43e4e7aabd2ceb66b1c48be927bfb38ce31a879fe2996e64ca7e5b4aece2f05c5448ec012f055cf9bcede1bfa7c72087edcc7400db85f2d626a45121fb4c04	1650196893000000	1650801693000000	1713873693000000	1808481693000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
197	\\x9d857eb116115ca6c2e5e079282e063ba62bafbbf3b9c740c4e202b45a000f155dc5dc911a9fce8e0015e3401af5199a78bf58217de926ee359666818b5bb116	1	0	\\x000000010000000000800003a9be261356fa9333c945113296bf900430cddac5040092336b232f9a8b867ea5ab4cedb1492c2169a45107c357a5378fd296c9b7e6e5347970f18ef9d73e5b8cb65bcf7a68539359c50a1cded400282cad9ae5bd71e373a333bc63d6e8acd78fca477f1c071f15c44dcd0fe5eb9398affb857500e1faf72d7dc50936439016b5010001	\\x7c5a1df82eada69983d2e7e7abe83c500a407596d2d959eff7eeb0e671cf5e99812c4bdacb9666984f63b99e5b61493c4eb70efd3be19454523b487c626da000	1665913893000000	1666518693000000	1729590693000000	1824198693000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
198	\\xa08df56dcfab00b4567a2f772739d7cacf8340f523de4b1108bbca4df5ab13df68b0153afc1a76c64a226600312407c1292c656073911901fb820d8c0a763da0	1	0	\\x000000010000000000800003c2e9cb17905be87172cabd018eb3e93e5662e95d38bdfe7ea8c919f1bc54741d87b2aa9e32200bcfabb73eed017d23a686335e8e964c61ebbfba05aaee426837b85dbf25fa1ebd4eb09925e634c3d6d4ddbc04323a245407b753b738743788b419a72946f417e3eeb490d46af5a53313b2dfd14e26d7ca7e80ac7ce9346ef211010001	\\x21c789e83f571feffa729d62e82aac94d8dc18e3f8d0320828275ef0db83c29550f1bcf92c5222da9812cf4b919d409fb7c70f6dbd24f33d2efa54e5f452a404	1661077893000000	1661682693000000	1724754693000000	1819362693000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
199	\\xa285020064963faa0dc4216ac4b10ff056024edc8d4f869a8310509c828a51c114381e698c6c8bab1dc5139b0ee9f3dfe2853f4327c84c0ba99cf3bdec669e73	1	0	\\x000000010000000000800003ca3f12c4970a48651f5cd12819087e7b9c7ce5c1118a1412534114ccf788f0650fdc0d028b127b3c613d944ac2dc5e329ea08e3b1cd88aaae3281ff8d544a468aacafc5843a7287de3b73ebdbc62350f8e8c1ea07693149aa98045dd9b6cb584072b9e2bfeda4d99a8738711d15cb88b04dcbbb534b0d3e65d3bc4a5150f4baf010001	\\x203cee3e9c0659bff0521446a0a9804db737ecb7377c262e3ead2afd441cdeebd3e18a64285b9692f1ded9a7f186fd7df3789d60512d04f975b325190cb04401	1658055393000000	1658660193000000	1721732193000000	1816340193000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
200	\\xa341a54c9ab27f31f8389a7f48f9732b7087e4a0f78b3c7f15391d3ced05063506b3e53c832dcd6fbd5c0a50581534c6dbea497fec85b7da35583134bc0ff71f	1	0	\\x000000010000000000800003cd5eda013c5bb1cf338b0e5007402db42abcf8796f2f874b8bd3dfffed1fcf3ff679d12016dee7333dbd95f0b7eed32024de70de33be7957f67a69797c8149e9f7028538fa28963075fe9b3f9ca85879c3fc6af34936517abf9d5a129adde81c76ef0737fce0e773b3afac5891ddcf16335af41349bdc267c8b60d35a44312db010001	\\xff84eef92f5e36da5e219e5360c7cbff115c42dded831801f3d2bf412b1b306a7e1c391d1f9fb2a367a5e7b489158d9e748dbad0190d76e3fbb74daa594ed704	1670145393000000	1670750193000000	1733822193000000	1828430193000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
201	\\xa41d13cfefe1de00495d0dfe0792952bb4b6929dc4923fe544f9087a5d91a1fba709119c0e4c8def866b8b426393c3708a4453255b4a5895e08472d984c48cf2	1	0	\\x000000010000000000800003affb1f8d245a6c22a1809d7e262260ae10d0efab290f4ea2672d44c67fb860a784d23176b43320e3aafbc1e5b76595cbe3ba983b2f383d2644d39a8aaaa4d68c8b343fafbc88da51b929f1c83f226584773db2e155e02b8d618ef9ab6d361f094f3de52d0c2349f2a3988567c56ced1d07c1978b26cb3c5d2f6d7635a77bdddb010001	\\x97a4a5deed2aa6fd87672b93d0f2bbd96073f0d10c01dbcc0217a5a7f4e5537d1648c57d722bd289f5cd101830e67e35e20579e96466b6a9a2b30f7b7096b300	1649592393000000	1650197193000000	1713269193000000	1807877193000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
202	\\xa4d1e3e3143efcb32348308b9b41d4cd052b8c3b9ae949eef86556f907346f3f664983b191f078f39c34002451cef5fea5177c7db44756dc97538c317140a167	1	0	\\x000000010000000000800003a69fc0ee9f34acde2c9ae182e16da7060a39e60ef7731be991713601a816040c69a916902f9c6859fae9f2cc58c39447a3871b06d0d19d0580cc911395a632e83cdec865ea9b4870850b0570f0266bcd9b08307bd6b15ec91ca1c4de902f69ba6658fed885ca38eea5f2b17508406654e4249cbcef5119fb1609f96c0adee415010001	\\xf807f0d2061ea915e2cd785b521379ab316e4be7321cfbf7d1b496935a28dda1f5ae3f5c5cd7d26f0e1b9ae8cb7eeb3a5e001a0e63c125fe8c8bebea74c77f0f	1648987893000000	1649592693000000	1712664693000000	1807272693000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
203	\\xa59995376acf26fe28aa2c634c65a63ca61cbc4e5757f890d3a7f233dba217ee9a7882ad4e3852cb8f5c1a83d7a90e6ae1cf0b791ce61220fa687a63a596f0ba	1	0	\\x000000010000000000800003e51e584cfec5a1127766009271245b8497ae3401c637e7193613d2aede7c9fb22c05bfccbf04de1c4ae8b180c77f0a611064f986af4f2c05949cc3370b8280a25cc1c358cd743a6ead9b27bb8d7ed24bd5d7b813d34696f8df33809f7046e66a998c8dcadff208e4df55fb1211003e3b8c41dc81e1743bbfb5bd05ecdb54b7b1010001	\\xd538a89cc239b6c5e6b5fd2093f0ff037a9d2baac90ceb11daec3bdcecfcb869dd64a60cfe0eddb0896e28f48a1bb6d5889389e60c114d8e6c7c6add165ca00f	1668331893000000	1668936693000000	1732008693000000	1826616693000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
204	\\xa731f9ffca939de78563f6524eb728ad6131ae2bd556e893aa56b2cca085419c70dc49e08e47d61a0a8f6ffbbbdb9f4b06fa4e9541bce3a2a967ff38c925ff67	1	0	\\x000000010000000000800003a4eb122aa0aa58663754927121d64eacc6d1a49187110431511bffe7e7561e129140e926717d862aea427563de61fa3f4d5982f11ef9b07ea14e207480db0ce808d96b1664940b42f7d51a18d964ae40cb421f6d80b9341cbd6b3c5b0755761cfe6e6f520fbe06b912a1c3fcb2945523500cafc9003c29470bf1d8475b6c9f85010001	\\x5ed62ac38e6ff541df91d8f96aa0db2931f5c3a4838edf2de7fbcf7f123ec8e4d7149d5ef45db2b1400dd1ed4d8f721d9ebfd154b1313bae6a1011c7ba1cd30b	1653219393000000	1653824193000000	1716896193000000	1811504193000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
205	\\xaa75a3532fae7fa8bf736f1f8d41d448112f75916e9af768d12a7d9f306bfbe0289f9ecf26013b1163c58487b87bfaf18a9dbf8aedd6e5f33556cb62bd069032	1	0	\\x000000010000000000800003c101094d0f2fd95a886940207a3534b8fba9c9225be0cdb8a1ff10385f1317c2daf3ce0150f96645d93d1b92a8da98daa2c03e4e6afc7bf1d8ca13dbf0c784b4af7d87ece9aed447ed2c48a745058832cb078f664ff88d1bd881dd8fc93ffcf2010bb45d7dc89b4748e1bdb47124a5fc7d0e56fff7895c02d267b712d188d913010001	\\x221f538fc744d78c71edd54d77a3e57daac96f30ec35944eb5216575b400abfb51a61462b9067712df109ed91d3ebe1e5556d2a5843e8eea6525e010aab6d904	1650196893000000	1650801693000000	1713873693000000	1808481693000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
206	\\xac5d06fc400bb1c505b20498113afbac68ecd8292e881da4a93babf8ae0879d619204817d2f53600649eb1491df13df7cfe77bf7fa3748f9795a1356190d1ced	1	0	\\x000000010000000000800003cb5ad011eb6aefe799e1f5db79d836eb9be019d268e25f50e73c22989a455f418239d685796ecc537abca8450bed440d3d975e55d1a688fe3d825dffb8fb860791b07db56fa09440402b6137ce330069cc0e92ac1a7ce544c2290a967ff2516d76531f51499ac04056dbf1dadd51aeece2ca69953f99fb27fef4ee28aa5c13b3010001	\\x04de0a94b35cfc504bdda7c4a630863983fc72389eb715f6c9f5161a4c36c21e95c86f3a29bee113403df2c099fc4e309148f1d9e8bd71cb244cc2dc48f6b50b	1661077893000000	1661682693000000	1724754693000000	1819362693000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
207	\\xacd530a19d402daf8e32b8618882ba4117ed3cd3d9f367b7c4c04b497f147bda624e9b9d50dbe5b3937a8aff71d94f1af9a14f4b138916950746ee9ceaccc4d4	1	0	\\x000000010000000000800003d35ab463e0a4f1edf6bdea6297f45fb9b4029d9235e38c05ae88002df0c341a50cb1f412d619d79f3858ba3925408141346d04ef28c2a351ffd9bec892cfce361dd740eecb125cc29a5b7e9d5aab5e21d5a7953903bc3680a36acebfc99e4a213b2cd1a991549d1b99063140cfeda63743cac7399133d401db99e69b78d3d069010001	\\xba8d23e2e6501d245b3ed1b857059e9dd3f5dc3acb239224c21c7fb180b568545590ca6507376c7ba6448d1d4504e39755ea8c1f788faabecd3b10557460950d	1656241893000000	1656846693000000	1719918693000000	1814526693000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
208	\\xb0dd20e4ebbe4d57eee74e798de94357b3349a68a2f60a847b27de1c3324fde0c1e8b9c455c2ed17bb21f09b79129534e6536cabb1cd41e5a2b8ff046ffe820c	1	0	\\x000000010000000000800003e06c236d44f57ae305122f801c11035e28ff86560542ff5eb7fdc87e47fc146232f44e83e0a69565f8cc1df7e1767bee8adbdf20e436b7cfef57607941e33e21a6e1a418ffd6474e40ba2f77a18cb3df64b38447b6bd0ff28caa90db0485c01e80f01969a685b74bf724e9749dbbe2e5cc24fae828fd42ad5d113ed16c5ee98b010001	\\x36674888241a161c37c416fee3fb27ae7a358f52cfe00187fd3b280f165ffc03109af230d97c76b01deb013bf74dcc8ae3fe06148e382f9fbf8d7280a28b5009	1670749893000000	1671354693000000	1734426693000000	1829034693000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
209	\\xb02945c2c971179b2648f737a0387bb658a480be25cb05759799404099b511b80a341bf20049391985bf7da0b32a0936db2f68e6f316735145b44c7b2084f58e	1	0	\\x000000010000000000800003a702885ba6933a6c865465c06893fe861eac87b0e0399ac6b3c9306aba78c402081ff9d36a4caa76f46cd7bc006f22bbf8fadf8b0a2e6a7b3ffe43ea1a8cb2141e23eb14ed31d351a24bf6b88a2fbb9ee59e331192a80f0ddc264e86e9e6ebfe8c859872e711b62bb463c89f3097d26e561c8e42c8964f9f22242625e2d18e39010001	\\x014533dcd69843989acb2f10922deded697c6aa6cbd2265beec285b4369e5bdc27d736eaa5c9b856d6e52fc7fd93feeb7e58f017423fd42c753a05cf8cba370d	1675585893000000	1676190693000000	1739262693000000	1833870693000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
210	\\xb3058cce5591523c1725c8163414814cd63608ddaf5547c90f348be030a021c3ca3b87b5970482155d9477e0ae2c5fdccfbffea43606d2fda72abb9bcd541346	1	0	\\x000000010000000000800003e281c0565ddb729928997c9bbf0357a399dafd21751d3b7c05576dd93e4edd6d8cce92efdbadec705e1ebfa34dcf78ac21d288c0bbf731435338453270cd5a86df00a2bbdeef16b28c2c2908117d9da630cce529cf4bc81075461116c15faff39ca58f5832657ba5c7f664685a9373e0eb61b00dc2ab37e23d55d098fbefe3d3010001	\\xcd5e532ecd06a22946b6cde4d68b2bf4df6e26895b5131906a439d0d8a3f96e310d3c978eabb9ddbabc170a34ed287810e8967a534719d6505e2ec8b523ddb00	1670749893000000	1671354693000000	1734426693000000	1829034693000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
211	\\xb405d1abcf7ed1f28cf9e8bd37cf3636ef784cfa3194c6f82159d9a4b13123dc82a9d477eeeb447bb2e9e7d05ea59403a695fd61d0485ef865e6f8843bc011d7	1	0	\\x000000010000000000800003c3ab44cc8d07bbb4c0ac32f54d6c057f42584c3893aaa8bafd63ccd4b5e23e5ae01e8546e1ed10d6d96cdd953ca623950a47cf2e97e3f4086fb93fdf10fa51eb6ceecc678b9736b438b133d8b3859ab72b580d60baf0db934f8ff132f367940be5dc8f5cb58f9cd37450c4a19db3173c2dacfd28f691dd8d44da9c1f906f3e23010001	\\x7b180357db26a632062edfb7ed12809435dac7d89e73048210a465bd4e854502092a746cd73d2dd1dc53272fea731a0bdaf650c749f192107b1f56826d04b107	1655032893000000	1655637693000000	1718709693000000	1813317693000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
212	\\xba41fb0e9273909370210aa03293b762f60629fb8edae17f2d959785bb1c1ec748965317127d9da32a1b8724c71d30f5df7ab22656833b60045104aea664c35b	1	0	\\x000000010000000000800003c6c07dca964df0ba0eb10aa882bd5fbb14075faaa93407924a350b59dca045802082394079b9cb002757f3a794ea45162833bc90527a6019c0ab679610231094f0fc589623fec7854efe19a71ea51f4b73fab296b6d0c9d1a0e4259c8fea4d20fed099456564db2e14d83276382872baf2b8947fc082a1c82696be984a89d2dd010001	\\x60198a4b63888a1148b9ff752491f6bae7db0335ebea79be0cb5cb9929e4d7b58d6df0aeba2fdaefb7401842e6f2e35ace316e731a930359c3a5f53d81376c08	1676794893000000	1677399693000000	1740471693000000	1835079693000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
213	\\xbd098b25a71dd3f227c23df4172acbd316784f52086a5d3b23ab5b5bcb4d131186ec278081d5f87286be545ae18ddf643595eff88f2944c4c4298d037cbe3489	1	0	\\x000000010000000000800003afd7e73791d38ebbf07e199bd852e6df0b5863ad5a66c4629678880de4a17fdcc06afbf8defde017f0964170e5310c329d9bfa55b22011cc472f9c0a052e9939a40c7482722ba74fd3c9636d01f387103d8112e2561cfa85353c164eec1b04e6699877d05a2d0403281447df828069c34dbdf3bd4504bf1c6997930e76648d75010001	\\x7122063e5425a914f2de0a0ea6f12d0cab5d4289ed9eb82422600e6001532d30e28faf5bdfdc6228ab50d29e4355a3d7adfcafaac75612daafd93bc0884b3d0b	1663495893000000	1664100693000000	1727172693000000	1821780693000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
214	\\xbe9978bb8c260c158dbc83605327f9ed25264fc373b46751e3c6b6017cd155ddad087297a40697194df37293cb8a7ca554e0f51df4fb489d3230acfa7f069d13	1	0	\\x000000010000000000800003a993afa51208503560f71019f4eb638eb24dbed9c5f7f82a701aacc173fb79836a1fda604c147a0d3abfc4e963ea86f6068e524ac54d5c9bf92526d3475afe00c91a1771b0965c411a371069207d63244abff6026173ece1b3e6b8dcbed8beb79084d5c6c601019ecb5ff6f5e80c0f5749b63269e7107dd366731595dda1ac73010001	\\x9b28aa72b7abe44cdbd1bfa7962cab3b099a17abcf972a505fa1fff3a19e7987424678b288b881d66395275a952456ca21dc59a1c47744decc642ca6809c4708	1671958893000000	1672563693000000	1735635693000000	1830243693000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
215	\\xbfdd4557cc8ff7cb211ad112fecedce444788c01b3bdcbdf9cbd8519c8d244b77f9f859e03d095fdbdaca9659950c9d7e6c371d4097444e8e29d9680b9051b80	1	0	\\x000000010000000000800003ecba4a10ba6f6bc6b3898961a8db91799e97e68f9659ab4b65594c6425c4ddcba34326831088c4bc024c7cc1471ade0af237b27befef111aee584924d75292610998e2413d694fc8772b257bf8c713c9e76ced6ca09acf5fdad6b116ee60aea306e06682457bfd04d5ea315e1f42835ee6cce29bb84e0e4cea72af9553f4eb1f010001	\\xed2db7647d1c853584105876f12ee66fac03b9c68e7402e0f5e4817220fef6e5c5b421735d715d96ca8e59cce53b5b2f29e81253f34f6a7f09d0c6e9b3e9600f	1648383393000000	1648988193000000	1712060193000000	1806668193000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
216	\\xbfc5a2f13e0d2e5180c85beb264a44b7bd906d18faab23086ccbeb4d3a0570073ae782a155ac5f46a9ac979e3ebf4f81e540d9faf346dbab4eb04938da651a11	1	0	\\x000000010000000000800003be065197833fadc5a30cf696cfeb98f7513b6a3ee9e85451d3a4139c773d2c0e568fe2b43fc6f380107c8cd16160d0e8c398afb0d82e0bf14bf5d21875508e5cd47368afe9f1c3c781576f548b64d7d8e6d1edb342a91c65b5dd7acd2840f280762d82813dc56aa1ff64712db6ef679ed390409a429fc98b592489d179bc0a49010001	\\x16cdbeee7392936befa993aa43ca98b72754b5c32f32aee36b2a090cf5f839a4da862d3299c4f23f3ff7ab92344427864a592fd68b8e6cc728c4b94e80ce9a0b	1666518393000000	1667123193000000	1730195193000000	1824803193000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
217	\\xc01553b83561d54f308413e95343b3e1c8317bc52c8f986f14a7ae358f9df0e0379d1a3221b8acf8a6ed98c820676e8a392490a0176866a059173106a2346f8b	1	0	\\x000000010000000000800003c26594ba842336249eb39f2238f598830d3a7ff7f44bc3f894e21745d749e8f3ea6fef8b2097e48c3394dd9921c934da87bd98f90a1f25a446d9d074a6ea79ec53964fd0926c01cc8887dc0158f077979e2337bb8f56824486d411577d78c4ebbe9eb636ba50d6f732a1bc895326c53dbab64d17848194250065a62bf4650f95010001	\\x214bd09363478c3f0c1a4a3c9c08359bdbd01b3d101115e49ab969804fe550332b940bfc02b4452f430aab5077a6a2d966e27adbf99f904e93a72e8242610302	1674981393000000	1675586193000000	1738658193000000	1833266193000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
218	\\xc2bdffd694e7123e588f4f1ea8465a93edc8abf47fdc97d225be3e064da0c22dc717760df60a24090d6a3ebc8955b8f8fbd9dc847e4d4a642850e48bdd80595b	1	0	\\x000000010000000000800003e0a9031942ef5d9f6b97e201685beacf61ddf6eac73d584ae8cdb265949a02e57c071d04012df3351cab5d1015b31e774c61041f4b9bbd1e575962bb5cd5209bae77a5b41deefa125869fd82f7b38d517e37275ea78fcb1d22486c16ce8d7f6638c094572ab6a240014fba61504ac518d9aef5e6e2a7aceae390e65f013202ad010001	\\xd20bc8b94b8cd1b6749d15b295aeba81eeac8b1c9a6cd001a50e5cad1f3887a8297e848e1e41faef6fdcc3bdf3664d81aeec26dd8f0f045b32358513bfc65c0d	1662286893000000	1662891693000000	1725963693000000	1820571693000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
219	\\xc6690e6223a1a7441e55f29d5b9bcc809aedc6d025f681cbc39c050862f17533defffb7839cbed0cf36337ef6e296c7c374896e2c307d186652e110ab5adb1ec	1	0	\\x000000010000000000800003c65d83090feaf922be63a28c11e5b14b2a24223f564fbbd53503f9ba5c1a15b73e8edb99b5bdf88e70914016328d4b54c0bf70c747834d8c668b94f3159597ca57ed443d15724aa8f47f231f81808e0c4ac04992d3b46b48feb160572120b5e29d0b344d01517d828d0caa39464ee55f104b245bb21159bc4183a794144bd70b010001	\\xb34588b72c9461ccf5dba879cf13ad4641e218a96f9d0521b4c5a201620ed0e4b1301a59818e3a716883cd6ed3afe7a9790a2d7840ac5261c9da902598dab300	1659264393000000	1659869193000000	1722941193000000	1817549193000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
220	\\xd3d1466d995d8b363e2327a2523206743de1a1e46ac39520c1db453ed83bcb4d82dc4fe2a9effb77944f2c912690b62709de70b58aa5d8c4cbaf8fb184bee6ec	1	0	\\x000000010000000000800003e83d7084affb4df1c9d6b751993c4b0cba7ff1418df9cf84b731900221e003a6c161386ae6a3d77e76856f7206acaee2c98510e4dd6c17a83927eb610e32cebc2f7d04f0c4562cb3dc53633f7604639e70e80ad90d635ef3202ebf753292d2a403b5b1dc0a3f68f98b5ca6afe1ab63f11dcb7db9109329c026e8d5d2370c802b010001	\\xe8122bc619e7937c6daac6ffbb41cef58ce3900b61fb8643ab6e85ef65a2c362b85e24ec0605eef586f4e6050ee8da68eda7ef5e2bfd4856cd83547b9ee2770f	1676190393000000	1676795193000000	1739867193000000	1834475193000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
221	\\xdf2976405d7410ec332e638b67e2027a77125a1171ee7d78ed7816dd421103ed73ee20de644260a72e8cfebd4ae6433194c18ad0044d08e02f271194ea01bbce	1	0	\\x000000010000000000800003d3d768150d901d405fa3ca8b5473a9f33764b4af6520867865e3bf210699a029181e899758e0a925121cb202764dc85abf668e78d9d2213fbae2caf6a3eed93921bebbd0283c4ab1c968c16d72ba877056680e5f55eca487fd950237ecfe634127a848ab73ce947dbe787921e9a421dda85cc844786f564d313c9fb89d7836b9010001	\\xc5ef5e7e776e1542cb73579efb9d43c53d8a0b558636e7945dd37d2f69aff9030de1bd3215fcea276c22926f973da8f481c5f19c8b903a5796c2c759d4d90e0a	1673772393000000	1674377193000000	1737449193000000	1832057193000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
222	\\xe16139f8aa191758b33456f6eed68bcf586eb1aa40e7d7d2635592d4632b7af46157da177a3a1679700886300ceffd2c89842b8c8234ef459aaad7509f1e4d15	1	0	\\x000000010000000000800003dd160cb61516abf541fd645a4e0b420e887caae41fef20281836fae03e75ae504ec249e6d19f2f0d39e749dd301e19607c60ee21ebeafc69303875741d44ca4fae47bac7501dd1b57cf760ccf90e18069e9a736b9473eab0a35467be76fdaddea09e30eb099ac21cb9dcfdf2d26c192b3fc44116eb066c288b88df887ed99b23010001	\\xc653f0bc138abe486ca000a3b2d5019c47ef0130e32c16ccf9a1c8b5f19083315d0403f178cdc5ac758aaeaea3dd07908b75b646b5c5722267ddc782b9823709	1676190393000000	1676795193000000	1739867193000000	1834475193000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
223	\\xe3ad88dbeb022d44db05905d8bbe8a45c057a64c32f86c3c3bd71763f6f8a7e3ddf1ffa669979705faa9781cc6b1e5ec041a400b32c23c09e8ea8ebca3abf31b	1	0	\\x000000010000000000800003c2b723f243ce79f211ec6c593bac99fd2e5283d7f10a9d5abdec535e266aa391a5a88ab5cfa48413371084e571c225f957f2a1ff1d20e93f710f87c37488db9004913cfe34078a60314fad0485f56cad863fa6cc6d7958e5fcf8d6b416eb10f1bdcfa36d110f4a949dcd5e3c126458627dc965620fd81da5e90ea9bdb1dcfeb1010001	\\x5104a507614be26f1c0d02c69d7b30bcae6fe3472f3ce747f24298d87de97c8ab533e38a76674b48e90509ff919f12f58b61dd41664d8d1346609c9cec01e509	1650801393000000	1651406193000000	1714478193000000	1809086193000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
224	\\xe4b9b17ea0ab6cb21889879491a8e9e83d17ee3788ffd00d496c58628225e6414e46e1b831ad72b15764ad2388bec331bdda7fc319428a46c79d0c055a91c57e	1	0	\\x000000010000000000800003bc17e93978d6cd427051405e4dc35c7bc4e876419041c1039cdee90f9c8ab7bd643dc9ef560581a7be404d78afc6c112701345bc452db07be9713d0f6541a4efc838511088991ecdf202de3d8f1bc686868375c7ee1a3e483d7f016ccd3a1a37ef09cb12cd9b642226a55202942f5ad04dffa57484f89ed16df1a121f9ce56b5010001	\\xdf57470c16999f9eef5af97c795802d73899a4d73f55c39f7b9f6a4abb4a564356ecf5e1f76cf7b0ed717c484eb7265f305a6aa68b4a8620f3f68da8a4721107	1656846393000000	1657451193000000	1720523193000000	1815131193000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
225	\\xe4098643869c02dd4825c7fb40ea09b3c63ed0b93ae753d2c0e28f626c41d404c47e13bfe8281a2f026c4be62bab898d3d2690382a2628880fb15f07be4e3626	1	0	\\x000000010000000000800003cbb04a0f995a9b44a34db71bc1ecd6343e49d9c2f65f0c0a6d350202df2cd1b197a58bc0525ddf67601fbf52b4958f6025933ebc96f30b4ffb1b471f4de8ee1e050835865fb5a7e05df8fa321d6ac15f025744b83be35d5367177b7c64568b384bb63951b9530caa2d3a8a3d7041bae373566f2555312c83cc37d814e9d50cfb010001	\\x106e4ac6486b851a15aa190e51556f4ed23c47484209d763c408231640a26f9ad4a6b3bac52ffc7df77adcf66cf8d103ed51c4c5efd2bf7824f86eb7fb156f05	1650196893000000	1650801693000000	1713873693000000	1808481693000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
226	\\xe59d08c3df2efdff467e7cde97f7da07c3290ae34b127bceda7100920136b417f1cd04da066a65f6efa2667379cb5bde217b19af0ee32367747b934ae7c2383d	1	0	\\x000000010000000000800003a2d9e644b99fd367826397feeff4631f1489e6141b4f0a0a1940c8887048314f7b3353b691fb51196eceeb26f85743220c98c82d746bf2c4da49b7786fb924ea22e9e0197dc1f4c5a804c62a1d2b749024db5382c83f2d845974fdbbb334ad200d5c41968e5660897465e5cc6bbf8d8006a191742d8dca7d30da3704e598ddcf010001	\\xd651d5f181a1884debebcd3402484be6a38af3b9d392dbaab081ba8e1bd46cd3269d99da8dbf0adba3d94d2d7bbe166cd1fbf64373a0312bc5275850870f8907	1672563393000000	1673168193000000	1736240193000000	1830848193000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
227	\\xe5c9b497d5c2e3a72b573382aba69f5081356f38d7b5b7f3f471a13552a4b640e9eab69cc896f7885f85dacec0f9d3eaba7576c20fd82d2fb6f6eb67b16d345e	1	0	\\x000000010000000000800003a5f2c817db1fd8119a92497291ba27a6abaa89aa8f37ed6ca451bde87d254a8bf2b0b1bc3d12e6e17a13edc22473ead6e71862001e113e66a3fc32c4f4ad9e0e3ee58c9d66f04b2d60070ba6b5ac3bfe3292f2471d106c0b57e0860c506a458f01267337252bcfb3cc687264fad9a7555265fbf294caab8b5126456bb66cb559010001	\\x89d1e0b6f67654d19de01c78c7743386affb3daf332aba71295cc437cadde35895df9bcfeb6bc7194320482fe83cba53a3d52b734a677ed1046433a223997c02	1652010393000000	1652615193000000	1715687193000000	1810295193000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
228	\\xe6c9bf43e27999f02fe29a71b7d6747dd4446fb9a708f787c1bc90eb9e14ff2352e51926032bcb518ea68e52faab6f2afe7586d3e386ad97c581015db66c192d	1	0	\\x000000010000000000800003be6a9c00fb9a5ada98cce003d815e7ef4420ad6c3b3fa8b417411a2514bd75818c1451f178ad3deee456ffe1999e3f8a003dbe4342fe258630ef31077d6d19a56e684f494278cee69b292af4ab2d53f3858d22d8b3b707c62f8fcb49cddd38c3ee500eedf51b02a78c1c7a6e964b0076deccbe8c6b6401974f244dd018471747010001	\\x3da980ccdd02ef578a107f064ee11e69760f1b41b1b03c9a1af38feeed972420c31c46b7d4bb7277d8586ef680dbcb8fc06f99908365a93536dcb5ca3cdead0e	1676794893000000	1677399693000000	1740471693000000	1835079693000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
229	\\xede14bfb79a7321860256bca23b325fcf5cff28a5c07aa1a88892e3c1d12b78e2feebca23d1d3b2dbf86cc111106de4991eb35b2da95cece20d09ac65b0fb260	1	0	\\x000000010000000000800003c01a3bb56a52f3c55f59b37255cfa18258520c0aa73479abec1637ec7503c429080d26f93a8f75715901644df63cd680891381e2deada7e7a1a553aa345f5d34c52f1476cdaff4f9c40225fe6df34ac17d28169d9effa936c3ca6b1d3fb097ffdc2dc20e36f2d5376860e27b1514d7c4a738d51564b30213bd9480c649f26f75010001	\\x78e1ee909a805e0ff71051564ebaa54ad0a3ed930ccea9e6cf170d426b166f767bd33ee71540660c7a2ea1f974e751d7267bb9c00ffd79065a0240744538e200	1654428393000000	1655033193000000	1718105193000000	1812713193000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
230	\\xee610f5f11ae3371525821a763e32a22c0bbd0d0c7b08b8051ca7094d2ed61c8745896b24e9ccaaa8546a8695b0d966d8e648c3041cd5db4fc39566d7b1f59af	1	0	\\x000000010000000000800003ded8fa4ca264a07c3184664bf504e6cd0acf6899da5f86f068c630b252691046e6eede5e6c347e9e55824029328f7194b4687b7360ceb3ff133d0ae4c52da326e4cd56aa10e61afa822964d1f88f796cbbd6f989a062f12af34ca65d57a0be167f8d1f58b85f845ef8b8084e149a21440107c3a95f535155a550dd675ce23bbf010001	\\x0b6a9990a79a5e78c29d6d097542b58c7d62027c97bf79e2362fa4458b0402488cbeeb5d6a3a0ba79c999634ad5ef51c80650d642f45c8a8a58ca85965cdc604	1676794893000000	1677399693000000	1740471693000000	1835079693000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
231	\\xee1dc373695089344e2f26fa1bd56322a55422a231e09490286241c59675f3cd60880e216c28c29713136b535cfa4a908d28ad29a646d74622e52b256b6869cb	1	0	\\x000000010000000000800003b5a58b668f9aaa6bcbfe9413a4d657819be6d9b88cc39e0f417841bddf81369860c63da6a1f3c417c1f89a9aa78c10e58ecde497ced586225e528da32c88a7ff8a691bdc634c13ff8432cd07736f8a5dded01dc5d0b5333bdf2f955e5087a7513b274d31a4604c3488d3c5032eeb6b27d259be082fcff246cb8f3375c704aced010001	\\xc51158a64784f0c0950601c71e6626c71707eda93fa016bd0731882b88034dad0c96d9547dc66d776d806df34a44689181aae1cd4538b4bf678314dd3890e406	1679817393000000	1680422193000000	1743494193000000	1838102193000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
232	\\xf0c9537de2eec503e8be142ce513bc7bb21ff0c0ad34c208641a379792c1ec70e41a72eac751ec085f4f063cbb5b6161a5e499a1dab3f0194464a76e0081fe42	1	0	\\x000000010000000000800003d338848b74877ec226063361d72906f58628a24a8a5b3242160b0d8e70256c0cf8b3569aa7909bee7b9d4b2dd56ae3a79433bf36a8cd5947e46cc1155b5432197dc7214a95900609da083290f04e18ff0542ddabac731972798fabe4ecef8bd39c080d14b821530f1cedb3073cbf3b9aa92ce0b8842dd0396a0fd0406704f985010001	\\xfe1cae44cfb22f99d4eec1cc681474ffff5dc2614d8f531ca54ac5ac6b3b84e2c71ea8ed79de2c3f8f8298dfbda915f82223c6af7be9ca9373338c373f448609	1668936393000000	1669541193000000	1732613193000000	1827221193000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
233	\\xf311093e48910b5bd89a724ab5dd5b53abef1ff9471510bc5f32b9743243e3af2557bfe83cdd28d8f22c913183ba0f70aa489cdff2761111c278491cc63134b0	1	0	\\x000000010000000000800003d4979dcb632d4c2df0cf08a413e6940aec12b5b34bf87fca79f2490bd992eedf435bd58a1490c69d02e8b47802e4294f5ea668eed6b0b32d536723ec694208bf6bb6d0fe32d5633c041150cdc45f381e78e2612dc3c32e5cb449f994d33c4a5add8f489067d61a15a5fa33f14c7fd620178275edaeef159f406f0a62de092905010001	\\xef4780dcfdf57d5d469a66c15dd9e9d84d68b27d243afaf71bad656d81ee4f44ae6e236b30ba0e2ae3e0756752683816f8b55c8add24b3d209aab9016aa5f90b	1660473393000000	1661078193000000	1724150193000000	1818758193000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
234	\\xf555e9e005a11e37428ab42fb4f95c11453feb0856762ebcdbe224ceb2178793c241b33b17d32ce7f5089973ba4c63df41be31325d9903f01182dc6ebf357f1e	1	0	\\x000000010000000000800003b9dd794207a6d542dc5b97f38620f09ef1d756751f30a2e9e151dd501b1af651278b097facca6d623403adcb5ae74185b18a89800c99999b14ee08655d91bc6f9cb865b53f08896dd05bc048c574a010befa1fa244a3326b40e4d577cf579c8455b788ec9add75efb6c2b994e201994a52d8c6882a4a0466a18587467971ee1f010001	\\x4c8d24af8f8f5d80250990e930a53dcc7c532307d572500dbdb24a93de625f11aa7a27d295d4de84851bc89f1de8d75213d9198f4b53b73f296057b4f63f2f0f	1667122893000000	1667727693000000	1730799693000000	1825407693000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
235	\\xf751418e629fc12f607acf3acb3f5f20849b63a2f8ef1487acdcf4c2fdae2179804c0e9c79e89d75198078fcf385bc6b4369c9af7f15ffa426d0f76edc5dbd60	1	0	\\x000000010000000000800003ae4c4df1ad9cf31126991c01876a73a47052bdad302b56b9036c0ab3c5839bc7156f28fec89bae174ee8bc791c38bd56621150d6ae9f6e4b16929db0a0f72674dcdef9f1b1f97696bc5d882cd8dcd66d91328d0bd9d91721c822236e8f623a5f6999a73199d4e2b5e7ec71d84b591a429f2d651bc734ff04c984ab0972526187010001	\\x3408cc48002735d34eb1022ab7566f40830e7364887ab8fb68880270bc7f038d28446433be602bfe976eeac09d084368d42148906c4bed57c03e339175c9e603	1653823893000000	1654428693000000	1717500693000000	1812108693000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
236	\\x021e7f3efff5d9ef9e30637339d6fcc57b08b571a724393fa3279f6268c999e78aa506c7b28e5cb57b5c2af9b48a25a578b3d1400500bb00d580c33f3bec5109	1	0	\\x000000010000000000800003a6fcaf0076a323ce0efc0d723b4852a3cb136987ddfa6f59b9b2fc201469b1658b46073990466097d7eb4e33ede324a6675bd9ea584ba04a21e3f547ce7581e59bb9286bad5cfb3972123982d00e110d6f13c0a1d469701673a9a5e6e2afac8ab4f5cc5bfb91252e5c7a158da7dfe46314428335cd6b41f75e618a1db2d4401d010001	\\x94d42c7e8fb1a590c7e4d698c8bfa32a5baae288c50527dd6656e7be2c8cd1aaf6521690c810ea2d6b78cad53580ac483fe7cac66c4666b149cbdeab3ae3fc09	1652614893000000	1653219693000000	1716291693000000	1810899693000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
237	\\x0412cf2b1b486fc92730685a953a2db305d32324daba4d0a1f61245686dc06a6bdd5a3f215e3930e36845df9340627f5de0b11bc799e26bb04c2b7897a70da50	1	0	\\x000000010000000000800003bf8aa496753c4c9dfd2bc3dc7c5ded7e800ffdb889f63da717004d92e70efe8c75fd9849c22f2250b6fa90f15f772d4d290e117a838ed6981daeb40c707e2880a887301b31c4cfe0ad5d614657e2ac0a6768aabd868e975ef717ec1fd6e89599c9a1cc414d4e954edbe728a082ec819b91c6cfebd1f346992bea1e6b84a419c7010001	\\xa0643356e421970ea8dd465ea5f644fe048b46c0fa996b5307a0e16e5d395070bea0f107e9886e263aa6ec1dae3dfc89b511bdb22b3ec45fc65ea6bdadb5a90b	1654428393000000	1655033193000000	1718105193000000	1812713193000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
238	\\x08aedad4a4734b7261e37faba7847aace936d9c05e4fb92c97cee80887db5ab0e95e40bffe20735dde332451453c8e2a57617a260278416a752405ef51e5f3e5	1	0	\\x0000000100000000008000039a03904f6e728b9d94ae87bdedfd272b38de8a63d181a9d1dd98844705c4cb867b00ca1c19ad43ff9b61630760a6d7bb15d64b9682a2cc745118962513ecebb8e3deb3fff86cef0a6d50a7e635b438e2582818bf0d7d09cec609b711e65a7d4b22489a90512c662e5741c034ac5fa31faa157b93b0c76b7ccc6af71471606fb7010001	\\xdf23ffc207e12d9729f9001b212e5a83bf80980d012c98f357ce9e6b1c7da17f5a4444d4958fbf8736fdb3ac4081be7d29bf53a485c75fadb0185fc1a364a701	1668936393000000	1669541193000000	1732613193000000	1827221193000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
239	\\x0b523cddce405ef270ad8c5863492281a05b2f3e079bb5ce2520c987e5ec210c0ad806e5396325fa80d9f79b3ba14daea33ade9ba5fb53aa2725a0b1fadfce4e	1	0	\\x000000010000000000800003abc4638cf704ae2f4be40c73541fb868515db277a3d45d475acdbd9e7499a076650bbb79099655b3d8355b17b7749eeac3096698361667763b70d8efc0429bb5e8fbc1b477224fb71b17d16869dce200510b2fca8b21e39ad6d3a552a4f717b37413084d555e786be4f3b6f5bd042642faa81fc6cb2f1b889a65e89825d3dc37010001	\\xef02b4d1e1bb59a02c45429964b266c08002cf955efd351f38132746262e5daa18ea2d53fdf93905d2cdd196ddba49843ebd49d2920b5707bcfc821693d0140a	1668331893000000	1668936693000000	1732008693000000	1826616693000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
240	\\x153a71ce3f0c4fba110af4f09f56a692e3e132057c761272cd6b0a42e5173232cf74df62785ed9e8a4467e89a555b51aa8fc3c26a6ebc180c40baba99485c056	1	0	\\x000000010000000000800003e21165bef23fe6feb70ac07a17af30d1a1bce977a8b03525ae23f6fb0e811ae9448ff4eba588643f47a7718f55823992ad2b4b42b9c06c7a8077cc1e5c77e352edec2097569d3984f375ec8ed41cbe3184b6492558fa164531905a86e89b2534fa596d6a28b3b840d7c560909c18ad942299ad7d47752256f25460ebf91a992f010001	\\x03467ff8f734e39aef131dfb89a594ad9f8577b62ad8de37d3507fb287fe55f6ffd942970c01a3c517f5194571eb63ccfbe6ea975e123b3ec76d8aa17da46f01	1676794893000000	1677399693000000	1740471693000000	1835079693000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
241	\\x15f28393d7b590de0238b0638942656e7740c25b796b3dffa5c273037fcb832b10ef89963566e3d2c76f8f39377a19571170d88efcf00d89fdee5b6732698fdd	1	0	\\x000000010000000000800003dec3545f7eb968c5eb626fdd2c3af614e0ce2698df91dc041eb71d7053772fad12e3b22694fe24889cf0de145860f002560d20947a5e8e8546367cfa1b7f4685641c616dee5fa0516a17913996ca7ab98d9be4eabc8d7fb2e6381aee8f8fca8c2bceb82b18b572d904980ff618e5bd70cc3c00b39b82e001c2fbfa4d71749f7d010001	\\x1cb755061adda0499f8978d79ddf26d631e1267748928364a361a178cfbba552537c5fa8fcacd0a319c4d0cecc140ea424b5ddaff991e0316610dade35aa6808	1653219393000000	1653824193000000	1716896193000000	1811504193000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
242	\\x18d28ec0359a0b36cf06f2cb23d3ab6b71cd45e9d1c72b324f228151cb1f9f11107a8357331e71f0e9a20e900e972ec540908b299cc08031d622c64d876490b1	1	0	\\x000000010000000000800003becf6a71eb55a78aaad555e84c3f94226e13c888008589f1202fdd22837696530c67b2345980231812aac1c9e5e18681ad1f8cb6cb1ea290da566cc3ff73d37de6e87f2c6398e4c80fe62dd08741d12c7a49e2b1cb511e0de20d1b45e967c5b48db5f8b4f3d821176a7252c5bf09084596ccd1351bb396ae3c0b0f1bd6a18921010001	\\x74205715db9c745e3ce5244f2ec4954fdfde70ab8739ca61704ededf78f6768b045b0aaab98fb0a0033e789ce8465b4df5660a3ea0f1b4c8de76672b85b57b04	1655637393000000	1656242193000000	1719314193000000	1813922193000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
243	\\x1d06a5764ef38f81eb704d1a37b8a5d99ebe80ba9a23b20e6a907ce24fc9bdb66a743743c7aa0c8c523dc7f4edfe68dd9ef33815c602512dac7d0d98f81eba00	1	0	\\x000000010000000000800003bc1d3e5e9a454720a303a160d7cd6217724bf7d7ac95ebecb4a5143f0e27501831cdb9d6c42a2e691c8c6631ec09b89b889424f51ce3e18509edef7ae5c1e9bc3c455a1cefe038967fa2f7fb083f670c8814133c3eb50119df56b5144e4c3dea1a36b8db4230090e2c4ee97cf12b7be7d198a83f768afce2424b5fbc5b72dfaf010001	\\x008ee8998bb053b7b7d5fcbaa8ffa3af0928bb46adbe7aed05ca2bc9912c122cfed4c34e4aef86d2036b0f1a53f7d99123b03816c46e2515016b9ea5cef58e0a	1652614893000000	1653219693000000	1716291693000000	1810899693000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
244	\\x1dca76fca05afe3cc84758e92878ec9b5995f77825504168bf80df97081bd8a30c6ae8f368ed966da4c97f920a5b7b5923130e77d31fd9f40059478a152f945d	1	0	\\x000000010000000000800003c5a26cb24a1d517c5bf7125c7c9875e4ce8725ce9325dc4e53171690fb621370d81c1526d0fbb1d4dd99a7861db9222b7cf258354f1ff34159717fc17ac6a2d12cd4f61d768d1f806fd0f3ba728f3259738a9b2cd7cb33c60eca80928a4a698ecacb8415059263d9677b2f33a1edd55c0d163c8f8cb609b7742c769226997c91010001	\\x2caf7c56b3714405dde971c1445f81a801eb6be33a0efaf4a40be1120a3ee6ef86215aea1d1bc090db6bde04e26418f1c72bb5d3be78e60fc02ea18b96bd0b0f	1654428393000000	1655033193000000	1718105193000000	1812713193000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
245	\\x21fec3d0d7e21beabf39946b52f83f541bbf7ecb7b01da1875fa3648f36934ce59769d13b693b5360e5cef0afbb370573962183960104f5db232aba66c01d350	1	0	\\x000000010000000000800003a98e5bb66e74ce8fcc8751cfb34105ece94b9b39c27f9967a7024f85fa662a11b5dee8207434752c339bcbf2f2f71edfd6c289d6556f6cdea4b913900da1470d7cb347504e80d775d36c135357837d89f44bb6465a203ba4a6b0294b2694fc752d21ba5a9ea952ca7045a40cb0344878a0bdff07cbf67d2d58e1f4253d51e305010001	\\xd1d07258faa113b0ce189993ea98bc16aa03ca41b3a8d748e67532824b5a8f534f3054ef6c770019712e405301cb769f01da8b788570040181e608bc8b46e307	1656241893000000	1656846693000000	1719918693000000	1814526693000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
246	\\x263ed1782d1b1ac198e2f50d9fa273df75e21c005d1bd90817d6c0954810dda19359118971c930015ccbf91ef01c1cc95da9aa59dc0ba2c03ee085bc7cbcf248	1	0	\\x000000010000000000800003c3d28b0787f6d5f24f7f28fae145ae7ff93057e332158d2e07714256feee1ec8ad075c5796e862c4df8e979c8cbbc44edc362f5d069e36ddbbb51961a0b737a4f706f277656455cb1c9cf6be00aca866bf7e69b2a337b84f5c4487f0a0667ecd4b30f2e419535e3f02098a54133bca3bcec898a3353dd7e70239fca1d85fc4af010001	\\x5d86bcbffe9ac52cd5a0fbf1b05e6e8798644d70f5fee31b279c1d9958023d8bd41fcedc1bd52b2fa2da9e00fb91aa5584864d79d89859ce7ed373d02ac61c00	1677399393000000	1678004193000000	1741076193000000	1835684193000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
247	\\x2aba3c99df15d69ac619829c796ef06fab424888f909694e71fc6439e0ac575233fec6afca9d135215d932d135009a15d89044c1034cea022255475623f1c07c	1	0	\\x000000010000000000800003cbae3909fbb7f6124c59f95a73018802cfdc309bbff41b30b349749d2effbc9f62450504639cb1d038aed6266d47d6ae22685918a4666344af195810903da22ad7a9ed7fbe107bafbec79179625c54aa33948334a1a4dcfda45357e0aac90b34b0c0e081e8c370550e2740e67edb6443925edc4901473d2530b6a3bc275bbacf010001	\\x72b667da33fd5254387a5f8d52e8705ca53b44611da18be7dff5d436d1c034beec15fad4197878cd44ae45329f63c653772f1e3b6ea890b1353c527c0bfa1f05	1673167893000000	1673772693000000	1736844693000000	1831452693000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
248	\\x2ba24dee75b2927d7390e335a3ed68a8144e0f119c4fed67c26929b8bf803dd6f7d06f899255259a186db9b27e91fbc3ad99e28d3023639862f014eafa20a9db	1	0	\\x000000010000000000800003ca76dc6b948bd759cc3bf986cb75d3a1e7da2384fd7740e5dc5589411683918f003527076a17113045bfb72ae44314ef2b471de7ae3be2b48d87b583837c1a5cc86478a5dc21cffbbca03db2af2cfa382b04f22dd30a5d43062d1f23a779bb0a45e0be24f136dac41fcc5ae66f962dcb9a847b3a76823102d6cc1758895aab6b010001	\\x74d6d183d03206cb83aa62ea2e5ccd8ec7c49fa6b4468c192333d939d8e65703e37c8b4a204fba2ddfc15a35640736a299af2a014df9684badf7a1775b875303	1664704893000000	1665309693000000	1728381693000000	1822989693000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
249	\\x2eb691ec4e9580d93c4bda93e03f9d30f30f9dcfeab18d1ff9583fae2db1124ee384bdbcaff255ca42ab4cd73bd9399d9202b9e41842b05fa0917a4fa1979908	1	0	\\x000000010000000000800003eb243bde06b05f3f41e4e0e1a3873129e8e39ced1fff8652c8ef846523325d71415898422021905aa549422736be28efbae01c451ae71db6f7a0e309424c7da4ea1e358bf7a77719a3f5508c9730f491eca0782854fcf27222a5f583f20d7e7d7fb7aee9656de6975342f34e4aee250b121c302c54d31c06a6044e155c945677010001	\\xc81ea12e231abe166348457701575934defc858a0a010f0004ccf2c01af9420671eca63e640f1715397840537b1d223eea3e7157a4b4cf3df0e2c8360226d203	1663495893000000	1664100693000000	1727172693000000	1821780693000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
250	\\x31b6ec3d0d452b0ff90b8e1d124c975a26ab7b3b5554345a4936492eb266e9103446196bda90fea06f3e28bf6dd5f40647ff7f5270d65a8520d9b52a52d9dcfd	1	0	\\x000000010000000000800003a549180ff620caa87f15ef7afd83d1e5bb7abbde73c623cc2a26ce9bd449e299c0de548a24453096f48a786eedbcf728ef90e55b1d2df2fe842abe4006c7af86c9a7a3036637fd3412188bbe1f41b06354c090a4432e26006b7fe6e954978042b59212bf79af8460904973b9c1225b9883e56775f699805b9f4e26d2717144ff010001	\\x863f3544011fb86ec56a770d6396ad4c5182f416fd95bad13131018f6452229c5f4c95050c868960e020b4a42a57b26063ce9ecc4f1a7a84f0acb95a3b5f4200	1670145393000000	1670750193000000	1733822193000000	1828430193000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
251	\\x31528502c1bcfb79107276b6a9fa3945b63979371cc4cacb6c7ed4d7c955c00903bdad75072b47e44f6c98130fbe59ca211d4395c10faed5eb97c14c53870a12	1	0	\\x000000010000000000800003bf5c780bdb6aff05878c6efa68d1ec0f694afaba0d8008715a1c6ef7afb88ac2afabc5a1124e5ebfb93af69294e9930c5563926f8ccc541aa57696005d756202564f1476a5fccb6ed915f6483fe8ccab41ca654ae2c9754f517d1f4b27a3986186987eaa7590c3fca6b91f7403baa3d62c10925887bc094586d225f25886da3b010001	\\xe6667e67a3f7fe35c7f784c9adf3f46c2df9734405cad2bcd5c8326cbb6fc60bd56c8cad4a435f7f7c7861f7c17a07c1f286b1cad6469e7b8f53143339487403	1661682393000000	1662287193000000	1725359193000000	1819967193000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
252	\\x33be6d4da8d395f4b3b78972575e8212561a32cf053bcabef68413d7a3895e3655088be455ce3cf1432cf3c2e0e527a668ec3d5cd07804c6f9e26135804ab295	1	0	\\x000000010000000000800003ad6d2187ab8b7892c85850712b8d9b15ae2847b9e227f14d857306bd326165e0d778d7d1d2e8069ba26b654a3cb2099e7ca0f147488d08aca05df7e5d30e829ce089a5f8e864cf3531c7ff2177f7c4a7230266b5a353d2207791006efeea9fc87adfe631fad003d403d940e01e1e30f4d0f264e81e1e80ed00a9a4d97ae7e2af010001	\\xc9916368f31291b3b7b86cc76b4fd2e3f97652627f3c47fe142bb4fde1e94f241287cf08f7ee1797f51e7d0cace65ff1256491a4a53ff5b8fb08e954b24bd305	1671354393000000	1671959193000000	1735031193000000	1829639193000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
253	\\x38e6558da420f2681b81a604450f34f2691168e98823c2a5f2cba306c78450e753b808d8f6aaa8336f36c4b1c7daa18b92bdd4d669e6444fbbb433f3358d73e7	1	0	\\x000000010000000000800003b38c5c34d727a299e3e4386fdebd75550cffacd9c3b587399ac8e9845008f55dc99404e241fde8bb6d7a2ab1c4f19e7e685685cd5a00e0bcd52172153b77a7ef74a8c30119efdb1f167e61a4732c524a21d5957c36605403d4f01fc9cdf825ca64549c085e8b6d800cdcdb56056847b11c3636ba2ded18784892ed62789e8e43010001	\\x8bb5e830e1acd8eab6c599cf18a40d45ea9b9f3c21d8f858f7feff482754814e8ad968c66c536a9f78b3328be575b8008f2f1dbd8a6fb73c79d31a6b52d61a08	1671354393000000	1671959193000000	1735031193000000	1829639193000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
254	\\x3996b5eb0c30e700247c5d6df6c8dc2a8489ce0273189772bcebee84f9c2481b3d1506d1a3ef63735bb144630463dff0d250303f0a6a744bab0b3b9d761313c9	1	0	\\x000000010000000000800003c9719792c4d3ebd597ab2361a81c330c8cc12644cd140dc79349b4335b5a20ecb58b02eef604b7a592c6fbc90d312a4d2aa12a4307fe365ad7625aaf08811ae960b2b4dfe6fb94752e51acdccd180cfc06ebb1dfdbe104ca558264539b2bd8fe767adb8e0169262e928e3341842986e9f5e38e71eee3a05fc498c763c36b0675010001	\\x437cbf92ac4c493914cef0e53e201d2da33ca70e57474c20b0f345d01f97795ef6fa5b366c28bde2cafea12f0d60d5a64116113e5b408cf74ef8c7af765e500e	1650801393000000	1651406193000000	1714478193000000	1809086193000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
255	\\x3b3a03839da9115108bb0ead476b87c7a1fa186164b4edf6e8b099f6dbedaf58a9a2271ff9c8bf938660963fd74f493fb211d4080d48283a3f71a3f4a060e30d	1	0	\\x000000010000000000800003be6a20acb79febd8a18a36f7dba6b3f146584f2093e4afae139050822a805941b4de40e34f8b1a040206260bf3346e64f108f90c081ce49c5f6ac90fec2a88649b0819476222307a4c65bb654b8368b3b3ccde74241a698f2f6d13513456f4e9a0ffff421359fc694b6fdbcaf0b1375f517baa2149375ca2c0b2e827203024dd010001	\\x5fef371da9465ac6b900d4f0ce70b9c3654045cd7b4001c07dc782b68b5b4b98f625ead76519f986e718be17048990e234b37b6145b84acb7b5f3907f979bc06	1675585893000000	1676190693000000	1739262693000000	1833870693000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
256	\\x3b1a46148331b925b2d25ac7bda18839cf61bf9ada627c0a3ece799db1dfefd15f24b6020de311f0078607ab7aba5719b0081a55f56ae2a63d697d3d6f76b837	1	0	\\x000000010000000000800003b2c1adf1c9e6f58b46139ec8cf530aa5bcae1e0f605ea778fb999c287a76f2f8b0688230c47b07fbf822887ddef426349c474d6acd29b854003c5063dcab2f4b6713e4c8cb26d4fdb79b104805bc88eaf73e34c5d188029c2e6d5ff05657942697fa2fc81f2cbc970e6588231463d8f05909d39c7f3d221c25cc03907dc532b3010001	\\x8fdfd2c2e2015e88c518b410f5218bcdbb2d6ed3883cda7dd74837b5d426d60f811786bbe346fac0acdc128fc75b8d48471e4554538126dd9e55aa32bb782405	1658055393000000	1658660193000000	1721732193000000	1816340193000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
257	\\x3be22da8020876aba494139f87ce2e643c1967a4cc0e9652df69f907cee9134b2c529687267dfa253425aabcfdc4d4ad8c4cc1b61bc9844db969913403ca32a9	1	0	\\x000000010000000000800003f8a1b5d41a1db897ef216de5271a1121092604b0874774bcc7409552cf45e7f51db82cecc2c9bd92396d34b4c22c8ef479d14a5791b443ecf80ee2004008f41d9812447a65d10b1cd7a8a499da080cc57e5e0a9a02b019ebffffd43245b63afc6629a250c2c14eff2aa6515e98a4662a0b3b1360a4176e4e6020132a00e42035010001	\\x8cd1e50878329a4d97c6c2700fd6aa93353c220b6dc877ea0c6da03ffd97494b61d87295e262da96660f1d5af649c6f26bae52ac6b2733d6c6f3baf9b0f3d101	1671958893000000	1672563693000000	1735635693000000	1830243693000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
258	\\x41aec0fa69a773a96b671bd10bd56a9671346bbbaac0c607db3388d3493bea9f0f20d8f871522b8c50d4d2419ee443891f2fcc45868bccac383b160ea05f63df	1	0	\\x000000010000000000800003ccbc8d69d65632afee02595be9074926d888472fda34a830974063f0e19c2a1dd8a95c69a92c6f64680ee99b30a35f3b090e9d26de051e9ec763a726d2199f3e174bcda5fdbca9f921beb6c7144ae6ced625f2229d23b78acec3e1a99d155dfe97c30395eeab995a79d2187f99b5cd526a5f6bf3ae7356751c476470bc5260df010001	\\xc172b154aaf0c082862685bbafb9be72ae4805d9e7efbc4cf34343174b4423186650217716c6dc225053013fde575dc507df08f124bc220f2fa659208b0d640f	1660473393000000	1661078193000000	1724150193000000	1818758193000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
259	\\x42c642de41fab85e269c1891f9e385a2bf302ca7c926fc8a977aa5421db5be258d418a5b9bf3dfe4967d3a493c7868ac7a80c5af5931c779f47e5b2175b18510	1	0	\\x000000010000000000800003b7d6b450cf1f4915ced228933fbc8d7a403c0add85e3f8e36aeb87905b5c37493bd578b738e17a5897ad6ae5bf9750f2ec2b4c98047ef8fce0dd75ce1d8589799866ae444a752cf6d141dd35b7cbe9a1b2e5e2c1326c986573c0b8824ca75f5593b1e316cd8a3b6eff3f01b425fe2cc20243aeb9e6baa4bb87a68ed25cacb991010001	\\x22d1ec560d06bcb7f18544fb91ef9262ee13a46f29a43d5cf303619599c3bffddb16ef8b48debe8cc0ad66578b3859788386771588f698f6581f003db9dc3a06	1664704893000000	1665309693000000	1728381693000000	1822989693000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
260	\\x4d76a482ba6bb4815a2d8bd29be1c11c9a1db871d14bcc9337cddd651a0258a372fb614706affd9c8fbf202f52bc30fb479ca3273681fce126699d12f55d9cc2	1	0	\\x000000010000000000800003d6f8323ee3d03087ea4ad6ca68a4dcb00fce638db28e01d8e0d1e714b2b6690c9bde525e59d9c31743656167e89282543f6b55d7cda10d915caf6111e33584a5f84cca0c06af40f234c948167fe7a60c4485a785241341ee11084c51be2f994b4690475a9adc940fccb04b115b99b1064218a65c0bf9ccf00a5dba1edc2fe509010001	\\xb44d379a873b8f0839d60f70c600b2b9f0d9c57caa4a0b64256b72e5c0fe31f6312693c9361f4427a56e68c13336ef058b23c9b9ed7de4939312ed853c179d0f	1661077893000000	1661682693000000	1724754693000000	1819362693000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
261	\\x529e20b96d5aad4db0c8e40216da4812e925ba20c9df3555069598894744e14bf877b8eb765e073292817ac689ebdef0dc5a0d4e65bc40061a5e6383c4db189f	1	0	\\x000000010000000000800003de28d6da0d1234d111916dd2aa7812e30bb0f3e22d63d377f6a5bd940d06adcfc21b55e05e0b421f31f1864083d6b774766c588a92d8dc9668f8973df80ee28e6a78ff7e9c1dd04052a727a1d639bbd6000314900694d403521a455fa4e773d926326994e3a67732b140bcf7105596e23fd4a5964c296777e8bd70239d80a055010001	\\x7c603cb5ce1e2796223849d2e98171f81dea817444c38b3987fc55cf649a148075e64b4e18322fb0a2586c4e5a80f6a31b285b12e294a25500c4ed6fd9facc04	1674376893000000	1674981693000000	1738053693000000	1832661693000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
262	\\x54ce978f8fbf4a8cb5c70ce6b2a6b06d032bf4e6592a10e9fb7f349f604fbffaec5465ca45222af689421e9a9fab5b680ea8436af883d9334c12930770ab4053	1	0	\\x000000010000000000800003bb32962aaec506215331ed603e64a8e8cb98afd9d1e5b99bfd1e60aaeb104ad530b6476bafcfcfd527544963a8b962578b1c9234ef6adf8dc1f6a792164f1ca482625dfb7191320e2c97403a7d2af375b3447b75da709560a830330c2077c490fa6b1bc1092d4d6db43cf60ed7439f008a564b15b318499d2e267871480af13f010001	\\xafc997a6d60985e36f5048df3bf6cc2dfcd3820dbd29c0428b80cc6500fb6775f80fea1e02ef5017518773e7b209f9107002901c62b1c8507a6baf5d6b564009	1678608393000000	1679213193000000	1742285193000000	1836893193000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
263	\\x5476c3aa29739c7b1842da2742ff7fca971fc59a1da6c4bfbfb9c04dccfe047b56d19a8fb02cd2f7876bd0763a1b68ffbb3319d3fc6850d3e4575f06a40ac222	1	0	\\x000000010000000000800003bcd728806a1741a1d35899b8ade24d213d9e5d2e95d707838b84ef086e1c0f5ee223499a252bcc9e3adafa6494b8d5d5b637967e89930823850844420c8548d5a53e0f2e26910b986949d46986998f51c0a94091276a9424b017fe99d2bbfc59817cfeca33107072427ca6fd1b11ebe8e42f0bd018eca777986e4cbb3ea33837010001	\\xe91ba6297e59acc3818e4490b3990c667e61fbcb876f5fa2d410a6f22237af8af9c605af92583d340a22ce4732636104e13d08a9b1a0a90be038e71d1c4bd105	1673167893000000	1673772693000000	1736844693000000	1831452693000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
264	\\x57d232d1d42d90d4e55b0858303a550e716fd43547114ae8e8171c837c248c41d013d767481f91247f7897b17ff25b7822375efff2f372f3291ab65f46640f15	1	0	\\x000000010000000000800003946c5c8ea43cb2cbb874546f8eabb1650a1c8e46be177f9470d487fa7f2cb83cedf835b9bf0c6d5b9c20a10d31142342410eb8f1f643ef629c5e7b58d0f896055b917021a8fad579c7f6e8de21b9fd47adb2673c5d59552d382f9124978ea7696a48f7fbb2d3c213e625b4aeb15e02493d1e86e318b9d1b06c2d1698eb84dead010001	\\x051fbfef28dfbdefb830da550b919871a8d054864360c90f7393aae5244287a42049cca540e337389cee36ae4edab8943ce6dc4286d6f326c9ecc9a1b05a5802	1649592393000000	1650197193000000	1713269193000000	1807877193000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
265	\\x58ae8b12b75da901465208b2f368c1da7215ce20bcd7879b7e1a0e22eb7713086790d3cdd172016dd0d052d722ff9b18149ef83a1b722e4175f89f7d76275cf5	1	0	\\x000000010000000000800003c0532902bad9ff87446dcfdab25a6e5d95d1d6482a46730c6f531973c1e169c51c032569a0969a045b62ead89237e1cd638a5ba38b5ce0af79e6a3687a2e1500d3411c87aa6c603fec7b063264c3c6f60a323954323e63f4d9d61d6ca2aa35214c5853225f9a3760ed4075dca3e030b63ca799a355ace0bc662194c04e5dc08f010001	\\xb64737ce978c300d24e134bec9c14b4999be95e20be73ab24c01cb540fa201352f653877ffb37003f61ce4c46d0ebd89e0916ed59cdc30e169008f02e555a804	1664100393000000	1664705193000000	1727777193000000	1822385193000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
266	\\x5906f57b1bec4d55a06d317a1c615c73a121425dad02dc32cbec04d267dc6b426f76eab1a3534f9f341a0b0bec5569101070a2cef37784522288a21cf5cd8a7a	1	0	\\x000000010000000000800003e026a125485c67a34c5af118aed4e0f4ada015602e4fe54ca083bbc032089159bff6ecb68a1e3e31c231bb8748a910860dd721180454d78210233a764cc647332e13f65cf1ee52a79b7df3ef26a4ee3a390a4bda3f1aa16bf22bfad8f271479a68ce3a42fe42f01aa62ab9b62fbbaa29d7d42dd2af2d7877beffd41208838117010001	\\xba269beb24dbce309708afb6d5f68dffbd33ae7fbd20512c50da45db175f6f07ce399e49b1fdd89bc57de06d63fa3112f6b87db68d162392fc78b1ac6dc86b0c	1655637393000000	1656242193000000	1719314193000000	1813922193000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
267	\\x5d7adf12ab1173c7a4458abbbadb8aeef12016c4f5992bdd24ce7f6e942c1372fb64652b48249381963f71846b83dbb3c92a8f78de1f18e6b05b1ec2ca8fca2a	1	0	\\x00000001000000000080000397d136a149ccd32695d980122654a1318e883f8543ca86ecd896435ab8690d0efbb7c525156d162ec20486b0eb1d3c544dfbed257f2195e584c7843fc475aae5c7e3f667c8f40f134645ec013f1701bbd7f483dcc75f3ac04c52b9fcf84e9a959b97a7ca08e9ad76ae57139ffd2ccdd0608b42f94a6ebef0000960d27b02a465010001	\\x1c99244126a9863a6c41a160f8b18081ccfa324d5c63c6a9f1d51af149fcbccd499068f9358646dd1574b8b395aeaf298146dfb02a1b7dace93641c7c4d2830f	1670145393000000	1670750193000000	1733822193000000	1828430193000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
268	\\x5f3ecdde4a32767a1dc3490e3f3700e7c3b6f63c6b1a4518b23488959775374cea481af5d1e493e97101b46dd7159580769d7ea843069a7ce6c9c53b7244c232	1	0	\\x000000010000000000800003d0235307b533c541f53dab28c2f2749dbd1220b6adce005ca9aaf20005c92faef9ede44359583505c328ecf4f9a898d6feaad04ca2ee4940eb59220b4a8f2e48af4402254ebaa7ddfbbb8c174552ee058fe7de0b426285a67b2e0f787d4c6dc6bfb5fba3a748a45db2c4772452a9ef3e4f63205bfa44ed5941ecb1a43a455eb9010001	\\xd84245dd10a067de41c51b7416324b2503e8216ebcb4eba5f4cfd8552d6baf5a9735ff81187a5c7a3b4990446b55fa7cc83b7534080cbd7f7111261179cd570b	1649592393000000	1650197193000000	1713269193000000	1807877193000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
269	\\x5f2ee7ff071930a96dbe5f285a6076a1e76a85f17e617cc5ab572760389f8d2b3eabcd916f2a756f88398cb787513e0a510f0ad7733e951c9bcadfc83febe8f6	1	0	\\x000000010000000000800003b1d56bae74f71a5f882e82ec3321134347b24c1ed0e3d18988a9753a18e0edfeadfc84d7752c7a7b1250220e83adfe3ada0384706388f5b78bef271b3ea0e9d5be71349caa19d87cc1365ea2a783164b4b8e2b49fbfff4bfaed14772906c7681fb5d8bbe66d7bf4ed1cbe860bb03cfbbcae45fdc80c18899b9c2c8bf3f224b7b010001	\\xd4e3d0db15f568385f4af61b2f2b29f5a6bdd1daf8f5af82b618757f8429b9e8abe7c3482d1913ca51a0f70422f21a41afa7a9503e6bc0376e435f4392d31604	1648987893000000	1649592693000000	1712664693000000	1807272693000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
270	\\x61b2db0ff5511e9dc203e29a910b6ec2a30ab14b80c1489f60679c648422925bd22070393e141e09f99b38b33c2e8bf595a53a8683da0d7a2924c308bc8179c2	1	0	\\x000000010000000000800003e84eb6455ff55793f6d4b143ce101a6d113d8a1266cc70ddb57b3c81c808893f230c82eaf11943427d3b3a3ecdb46a120caa2fe5d436aa4ca423e7230cc4a5f266a0d45eb36d78bb42d93c709fc2b6f411728845a6bc6c9d0156aad991e749f7b274392168f31794a3528a8ccfa0c12bbe6cdee281ab5adf2bc45a18ff082541010001	\\x9f683289fd957cc1cfd1c86af7b4e9cdaa00acd07a80e4b41f9bffd0528d5b95e7131a95cd686c7c40d6cf77faaa2ff505b4df7e362518315b41c009f7c2ad00	1651405893000000	1652010693000000	1715082693000000	1809690693000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
271	\\x6a2e18a87126250a3c607c3962fb67e69d0e8147c86776be2d94dabdc14d4849ad96d2d5b84453d6a08ca75c4024f5ca770ec9e0c7cf5589f3f953c52c54a429	1	0	\\x000000010000000000800003d8578a70bfeb0a588ca0496c0966e9a7c5fbf4575467cd6b33647795d6c60a3011a97c5019cc5426ab04b4868177261a63949f5fbe5fff4891deac422279c58179f0a239973c1ad1a0294ff50f5f3178251015a0b3ce96df6da636a3136c4bb72f08c28dddda253b927edbf46028e5384748537413b54b43a85ff8f18bfae95d010001	\\xdb8a4379ef446a146eda9db83b60dbd384855f41ac18e0adcce719b9dddfe55aff3d7b2937e7c754130ce074a9310c13386f3aee47e0b390e71f58d94dd6300e	1652010393000000	1652615193000000	1715687193000000	1810295193000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
272	\\x6fb6a674494f99f0198af5de29a5d675cd604ab3dc5b659c8bbd659b2521e772d0fae1c9d89c4d4c25cb3e92ad6581d646f33ebd9bea51f7db0237151d3b04e6	1	0	\\x000000010000000000800003c553883b8b5fd3d233d991304941335c70de4734ba6ea90a726b0d8b835f077932be4dc9f20f41245e5553f5973d72e7a106e6ec574b61e27ef82a32595ac93b2dbd6d0ed104372de8655cc36a4e178504dbbae435ae81984512c645d0c50317c167d323ed2f35e7220d5f0ee49beec0750625fa0ce56efe5735940173fbe2a5010001	\\x40ff1a77a6a2da14a2c89a51f9716804d582bb3a17052efd49868db4193b83af7e41c40258fd484e9f5a0d0a0335c8f31c6bfeaa6f5e210710bb7f6d2c774006	1667727393000000	1668332193000000	1731404193000000	1826012193000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
273	\\x72d6c6aa77d860a4e487679f0cda9cb24637a7ec86ef00bdf15e90ece7de0e27199dbf9f06a5340428eee838c3fd40e7b73039c2ea258d09fdf4a8f512374dc4	1	0	\\x000000010000000000800003cfdc26b1886febe18d4e898fd505ba763154aa9b1165699f6167fb44620a884f835b85a16fbe1fea32c5715023f3d4bc86e157042f4942a8dba68ae79c9d3f76e95517a82b936ef9edc9f0dce823e71c34566ea3d6c14b65e2bea9612d553bbaa9fe68a19053bf4335f35db4616187c5d63ec18452a3b60d5713807f400eccdb010001	\\xa18994a80b52d23a869610bc5dad046ab65e5201643ec5f165cb75a927e3fed4790043a02a35267ee9179f8c9e0134ab189ee349bbd8f301f1f457a1efdad40b	1679817393000000	1680422193000000	1743494193000000	1838102193000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
274	\\x739628e10823c9239c53ba09dce51c667aa59cfe62777bc2f4922b334a95233473acff6ea290a6532cb2ea272eda3dde10c65b7825ce64d4a35b7ed467c42c86	1	0	\\x000000010000000000800003abb6f2f2350c12dc739635b146112145cc6e9d0539d7caff27aa2717ea7c98bd081023780386766859e88b23aee76085fd7d25ee2044d1a5b05940b415ee4b899fa2259a2d894f3562f1424cc800d1051966e00565f06f17391ea700e2997a92abc06c801114cf3a49e5aacb7ee58232c65b8bcb8bf15abddd1e428056a2e7a1010001	\\xc7f548082a1c6348c4af84afd5dba6e3cb4ae99cf0d0e5d20acb5b31e690e7680768c5d02c1df61cb3fce48631718eb427ec2ca504bf12b10b50d4acc015f801	1668936393000000	1669541193000000	1732613193000000	1827221193000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
275	\\x7516b9c04b473384b6add56d9a5ea5740e81c4cd34a84a783d6a6f597cdc71cbc83168036a3319a9d350be40f7a969932e43a8b22d40cd0daed4aedea2f750ca	1	0	\\x000000010000000000800003d1332b665eb58399fbf68d168df0d39a7e8afd83b495d230b521f3e379e48fb116650050b878a28726b353235d9fb5933c4c765aae153d8abd530ed03a25c52f4a7b73a4c713346a3dbf4e5564643473e8d26aece6b059cd8a90cdab979885fee642603ed9f00c21b3dec3ae0d29d6e3cfa92352b9ca46fc5e9a945bf0e039ef010001	\\x2bc378f174173e214de1144b4327a1a6dbf88ecb15e015270fd546034d1f2b12300e827bf28ee088f600a3dcff3af912496bca8533ec8ab4bee8b76441e22c05	1658055393000000	1658660193000000	1721732193000000	1816340193000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
276	\\x79be5a317fba737d41ad962162ed802c5bc1afb579c4d459ffbdf138e03e5c8683ceb0f0372505d5e7df3e4c2b261ddd4c27e3494dfad1e28b2534c2ce8b80af	1	0	\\x000000010000000000800003e5751aaae3993b4e325c65fe32e91505b2138bef73a05eed2c8103389bdf3967a0c22cda447f32189506228f1ceec053274d0fbdaabf80ff8d1c847ed6d83f73f8050cf285dcf12894ea529d1bcf82a1394cb2476eec418fd638b9b01e7edafe81f22f854ebc1fd4220d0695f359f1659071e7dd875595e15b6623fed1309da9010001	\\x862e2dc6aaa54e6a04e11cbef2e0b3da2236761c371c14e7ab6b2bbfa1487b7f018a1ca4c492077d70abc7d042dff7e6ed8f9449aa999d5e3820660493a19a0d	1658659893000000	1659264693000000	1722336693000000	1816944693000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
277	\\x7cd6bc09bf6b5c9e1e027ba4f8302b41eab0d6acd0b13afdd0b9009f9e9bab4602b746c2943199629250763f1b2029e0f670237433a6b8e7a65ed772a77dcffa	1	0	\\x000000010000000000800003f37b794f08fb593ce7f4da41f86f1234dc12ce72e7ec7bba4757362b811397ef31a8635b18b975c4f881a75bbe9ff743772203f991b09edfe005d3f61f1073f87763f7891f6e89610816894d3b8b2d44326666a31503b8360cccc7eb98feee4b428e93b40e6316d4335464a0eff855924e16faa06ef8efa3b25bc9866b2960fd010001	\\x28d299039a5d2213e73c7ff6d139e2e87ca0205233b70a7f2f791dd769f4b4c8a6ebcc06cc6867dbfa145def450292b81b879c748f792879568752633bdd020b	1665309393000000	1665914193000000	1728986193000000	1823594193000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
278	\\x7e82bcf7cacaf47b552b4307f22724de97d2c265f94dc5a4c9201ed317cfc6732cd0272720af4e24e5bfd76b328d0ce95914d1909d6bca22911f9ca7fe87385e	1	0	\\x000000010000000000800003d7831e32b488db90fcbcf48d8514fe506842c8ed98e757f5ad90fbf78cc637f2c0b1b55050b1870dd3a771e5a044e970d2a562f09eb712494693cab785757aae8ac79d8e6d8272e02720a517c7d40e249a9eb4020b6ee7b0db7efb7196db684213bb1ca18e48f8b1f3ea7a80a3553f8d3eea72d55ea3b56dd76deca70e106f11010001	\\x4054006c5b6915d44e18aa6c1418b09b0be599f3839404e114821d679393df45bba01abb9a0e938e6e85cd8979c08c2079fa9a35af88d4fb88ed8a91f5c2f007	1661077893000000	1661682693000000	1724754693000000	1819362693000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
279	\\x8142f9c52d6929e660da97daaaad00032c8a40263f4a1ef868551e1e9860ef29fa9fe46a29b95f8a0f3ee0d34f4683ecd51c216b12208d6a90389dba35a354d5	1	0	\\x000000010000000000800003b05b4e9007eb4566321979d3cbe08975510cd37f4d729028671cb692c76ca3aa1821119269675e354ea8ce1509480602978dd5bef3a25c90ba3a1ec9ccf5dfe15920d577c706c7563217bcf5a195360dbd7db5acf6209b7642aa25ed2ae4478122804f9abf7bbd781e4af7a71b18927448992d2a57ecbdb3ad3021c139bd356b010001	\\x15ff17ffe3adf1e049cf047ee043b69a8959f1c2e416b9299aa6f68e9b53835db937a21782170912b8f16e23aa809f82be6544f9568290aadfadd8d423d2710e	1648383393000000	1648988193000000	1712060193000000	1806668193000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
280	\\x837e17dd386405264a8c112ecb42565532a1978fed8208e068fd0744307ad42c9e7b65321125bbe72626aad29663a06e7c82493ed62b2d5f07db85eb0b05620e	1	0	\\x000000010000000000800003d0a7c011729612e6accae85bd461f3f2b5a6170099a905bb3c1c56ecc7d697b6e0baa53adf4f6f235860bb863e1eff11001837b72e463dc4a68414e320a2c3d0f9aa240eed86cbf96094a2cf6c1e718aa23426a0d2a46a5da9cf0af9d648959f022f8ede0079e46c7b7627fd74598f2cc914f126325ee0bb6a16b17f02e4287b010001	\\x0b3607798952daaa94b378985ed5d5b3be661d069294b08f45e7c5008df6829e74aaf7d6884beb3e94d32053e40ca185d97c9034b977dfb365a21cd42f1fab08	1679212893000000	1679817693000000	1742889693000000	1837497693000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
281	\\x866e589548e5ec1c5d024856866a85c081a4180f0e28e7ab0b007bf4b5248041d4712168a22d33701b78af603965b69ae9b5ca1529aa911cba2c5e4ba9bb55d9	1	0	\\x000000010000000000800003ae9670bc1e6c583062b0bbb0b905ce8df1a1136197ebbda42b29b197c9edf62da023f6f52831c12b371177ced9619021a5ddfeb35495301fd3157e6187b203a3ebb157ac577c46ae0f960fb6606deccfe4839370b18ba25d6017698c6a43ff6f927bb3239fe1b7346132bcfb89faf35758d6754b6b4ca4af4c1b2cc8d9921a69010001	\\xb78d56e36a53cdf8ca469f3a38782a218e961d471a75a7f9c683aa6f6809f9811227398721b46dd50ff65b4170460c92c079b1c5abef12eee8b02aec299d590d	1665309393000000	1665914193000000	1728986193000000	1823594193000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
282	\\x87c6796c3e7b7cbc48b8e707e4ca8de645af202e7655f20bd99e662ffb6c1a74daebc2382b2b3c9480db99f57fba6d8b15715832bd134673fbef301bb5c2398b	1	0	\\x000000010000000000800003cad7898b2a52400f379896cf792c67f76966a7e8d172de848e556d2a0e107c2dc37f6790e0c1d834440d8b3bf1c4e8caca83d3a29d04a8b73e2240f7558b6078b494657270f9e32c752a91b3d032ddbaefb70c75f33f78435e6bdfcc67c4ba7e10cb7c6c6ae9575456c5447220de10c511abe831ed1d297f966bc79351024819010001	\\x5a5dd291d3671eb0a39d5deefe3590e1f5c33882ea2eac17e016d784e41d0db6e7b960deffe4f3152fd4631c4e661213e8d8001e6c4788b6cde156128ffb2e00	1660473393000000	1661078193000000	1724150193000000	1818758193000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
283	\\x8932fddf2b2ae4eb56656532f836facbccc60a3229ce5a0f4e92b02ce889f571626148e4d65dc49701e4124023d9c609818d14ed41461d2ccee208009d66cd6a	1	0	\\x000000010000000000800003a61aae83b41cf4fecd9e731e6d7db7afd0a93e956385ef52d00afa05bc983f8a46045d959474846f9b9ccdae245779cd6e068fb08bdd35f4041f939e52cf89b62e16128ac5a12f624f59ed6ccf089f8224faa93db0a78e85f8ac9bff7f9bb5b2f18f8eb97b730ff26edd0402db615b92423ca59b9a23fa642320821886b5fcab010001	\\x06907ed1f2d9220a6daa088b0574f69e5ad3986609f46f6b1aeb6fce9af27773781c99cea73e0397794609eef5e41835104835dcea753f8096793e0f43a8a30d	1674376893000000	1674981693000000	1738053693000000	1832661693000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
284	\\x8d9eded36cac2bd8a338280ffcb38825e6c1577c20e7230aa4d5db6c2fa5c2435bbcb6b531f17b4e84093816518a34c35d0789cfe75ad73f09b8be46f390383e	1	0	\\x000000010000000000800003c6023d880ad487b09d2f3ef52c25e5ca32cf63ac230597a9fa8d305b84ded9cb004ee982c4d7733b8e8c30f19a1e06fa31af1ffa3cf64e7d9cde98cecc2317581e67412902925a9c6c8494d11b95bf06bee4b00702fa1cb994302e5b843696a65f76a0053323514dc68772d65d6d6587a4b209a44a8b9d9c96a7404e4c2c3a45010001	\\xb6354d4c242a4921de999832a4621a42905f5d8fe7a611dcc55570ce6812749e901614a4bdac99d3cd26adeb5cc0a076f10442767dbcbcab6ab235052d231b0a	1678003893000000	1678608693000000	1741680693000000	1836288693000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
285	\\x91f6d28e216d8da314e569fb43b34865873fc0b64b3ceeac9f0ff36ffc695a351237fa721bd59a10fd1eedee1cc3587533e75832fde2f26572c6cbd0f4c6f985	1	0	\\x000000010000000000800003d9b504dfd5cf2668781c5bc4c4ba1b5ca38b13b39da638be8b960ddc47aa28db9a7525c22dffe523fbed43b9db7f7aba1b611f8b2f38a1899920479b725ca45122de689ac8b70fe397f47e6b5ea271e7661e1ea20fabeab26a2a16710f9e7b21f1827062cfeb229f9b9c081658f8d91343512f813ae13e96fa5198316e4a5283010001	\\x566bcd7513e7b88a43857f13116ed7541a559b28b46dd600edb79b75cfb5f6deafa5479ab1f07d6c30306338f2f09c14442c52f941a2be8fbc0a4947333a7d0d	1668936393000000	1669541193000000	1732613193000000	1827221193000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
286	\\x99fe3c97fc9ab624604042d83b252aa5a1d46462617bb7db9a5a9adad1bec2f640cfe3972dd0b1c15f966459111e8990345c75d46b435dc41af7f61f09253345	1	0	\\x000000010000000000800003d4fd1dcad0fde43a1a4ba6cf2262d01672fc6f02612deec1d5f4aaa00179f715c65049b2f6c3ff1c95b64e06da825eebdc66e3ca27a2fbf513785d920af6727be11cc27b2d10624afee0278bddab67b9ccb288a30811f785678106cd254505c952af6f4cd16c05be84656fea01a8d5d23785b95b9efd6ee9c62d521f490722d5010001	\\xe4358e8cafb9f88306290747b9b1eb4105843bf2c3e6c8516a5aeff62d0bad066de496f02f9c4164469abddf898b8853275dd1f9606307db4a24287365610201	1653823893000000	1654428693000000	1717500693000000	1812108693000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
287	\\x9adaf6a1a2eb75339323440e43403edf62db7b592a41c34ca3676edbd58411a4457987c64d64b2e6511618ce8275d1474f6d23963bdd761addd61eed93631034	1	0	\\x000000010000000000800003cf5d4f4ab1b9f557b4ab593ff4158cf1e75f9f4d3f6cab6645fefd21c20aa96c513607008ef11d49b7737c16d991957ab89af62dee68af04d6d0fc0ef8449717db4942bac606fe8290af8b34acd710fffcdfc3f7af42853a59b449dd3f1d2fce88eda8d46009c1fd5cd00540bef0b4a4867042d59b80ce028617bd77e975f355010001	\\x50f9f5636f4bddd89ba9abb4b8f89ce8923fe44cdf081805b577805de83583bd1f78bbc13672dc3f47f443618f7d4d2e71b03eaebd64e1ecf7179636464e7909	1674981393000000	1675586193000000	1738658193000000	1833266193000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
288	\\x9cbe7812e5c8bcbafa7d2f43a945f3586818e8945ffa2c4d6afae3a0b7733797f05ac51caecf459ca0ccb51dfc3769c1e5442608743c3971dc68a20c411200d8	1	0	\\x000000010000000000800003d844de8334c9ee4ea7c63c96ab10e18c702e35bc6a02813a6bf7ee02d91adbd3e6d788909f1243b73288151303a480048809e4379ccd03853b5504e13b039682af99c4d1682579a918e0183d0a0fff32284a669e0b26ac9182916be924d942e5d5bc9399aa3c5bed5773a4a0583f96d187c4633cc3ee8495efa0df458e057dab010001	\\x6eb1bdd07b6e076fa3b94bde5fe518ac8b0c72434173de43df2651f05cf295c59ec4fa50c7292f81c2a3b903e46f8e77a0b6905d9adf9c5ceedd2408fab4ea02	1669540893000000	1670145693000000	1733217693000000	1827825693000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
289	\\xabdee7036eb44376fbac3ea3fa58571da2b1dc97abbd44d4941204e00abad451c2ef2bae9a7c67182debb04fb45e4453215c477121b4b45bfb81b2573ab5f744	1	0	\\x000000010000000000800003c03df6da5fe537ce208f6f649b9f438534222896582744e21f646ce13206b8cb96e0b646da286dc0f9980af3e71216174ff807f3c19ca38d1db22f2db4dc65facbc7119fc63b3af9a2d6a95f100114a439c9e60baf132104a3c7acf9f2654ad90efd1150f01929470295468bc40703e39acdb30b3a90dcf02055f0439125978d010001	\\xf913e7eb242cdba8faf478452a87aca426c168446b9f8b313d4dadb67c0c5613dd9198248d202a5d62c2fdaac86a646f11ff790b1eecee7783fd68905cf63b0e	1675585893000000	1676190693000000	1739262693000000	1833870693000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
290	\\xad021a012b1c55723bca0e4a3e8e0b48411ebe71aaeeb2644c195b1a497324546f0bc1fe2ab7f672cc846fc86e44833ae9d7c61d25642baf92fdc464994b99d1	1	0	\\x000000010000000000800003acff68eb0b06a93af38ef6ca36ca41e2b4a7b789f3a59125d5c29a2a6ac9c3a74b5159a93d02e23c8b75b0ebc9006dac0c9b4d928ad1c2ea90a0561f4a31718ddc30c966551583d7c5b1df4161f1eee2c9bdd3fdaf02ccb6c81afd50bba4724e8a94f1f4bb81c1156484f165dbd00d7929c15d6d7639c28c4b00c4718b9aa301010001	\\x2886852dd5ea17995f0865a13c4fe506fcb8e5aeb60a3f96da1defb202d6ee9a84ecfed8d1797ea4ad5f9cef711f40f258f7c9be85ddefa4982f29d3d631b402	1678608393000000	1679213193000000	1742285193000000	1836893193000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
291	\\xadda0aada0f89149723fb2e39c349448a6ca767e9f9d94e19fcbcff5ba9c1c9f575a7edd655aaa85b5490a716bfb6445d576ddedd15566d0b337b14474357349	1	0	\\x000000010000000000800003dc21433be8fce2f4a28254c3bd9780212362f56958d4c2820a5c9d765507b3390bcea33ca932159f8a5e52ebf38af2c6429cd26d455bc5ff17ee684ed5fd2116b33360702b6f6632c841824b12822e90913562c3f77b74c72db424ef5abd6d93d844e2391e5b72df4220087fd00c9be1631d1681c297ae119b272b2761bf4ccd010001	\\xd34703d45c5e1e43828a81c375405504211bbb49bbb220ea6f4216f514bc0ea49b2df46297ad7b13e848d10fb542fc532de2b76b3676b004ec8b6fe53d069b00	1671958893000000	1672563693000000	1735635693000000	1830243693000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
292	\\xb21667617ef60cd3dbb32167357a7524fcf9e921d95a4b43ecf254cae6937e29115595c7a7a5f3b968080b722c4be00b593e111ab6521d803fe7e2f8f8130ea0	1	0	\\x000000010000000000800003be2b5bd7374828d654a7ca71b75c90f5e6c7ec7e8294f10b82725fb029ce4170aa12ab478feacdcac5c7b5df290c578389279cff3b26c96b30e5389d0ff65c7c0e40b36324aaf6e59ac72495c65d8829ac878d7658894bbfce109a150e3576a2e49963ce5c44ca20cc8075e31a1e7c21c23a43c16c1bb33bae4bba3788246a8d010001	\\x9dab6871f7550fbae5b661c545461f7f7c5d694e82bab9946d7e9c2b7bb3ad6829a427077d74b545ea3e3c2eb79baa14d0567d42b52fac7c7e9a13bad767350c	1673772393000000	1674377193000000	1737449193000000	1832057193000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
293	\\xb222852de2f9e57aa336e1f987c911c99d8857478c2609e2544b4700d9451b1acd55f356fd978710f0eb73efe2872b460e420e9a51a62d56bf9f91823982325b	1	0	\\x000000010000000000800003c4c48cd532b81f37b274fe3c19318eeded3d6e098944f856a021bcf0a62a9ecf07dd8585e9a97d1a3da7bfec504a93345a480b817d18d0d467231a9a9670361eb21a39dc43f33ca66f430a84cdeb146a40898692ef6b85f3fab74e5788f1de1257095c942d02d6539679d137f1d28589ad25192bc3625f7b63865c945308271d010001	\\xea35141e07bca92919041ae79f681871c22b03e51a388eaa62d0e94459a2bc44bdf5abce1b7098c2268b6db779f21749b52dd7a4c20098db4173d59cf61a5804	1667727393000000	1668332193000000	1731404193000000	1826012193000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
294	\\xb3de110ae18738bc54607cd22cc03f7bd20f1db8463db4245517e2bd202992b2fa411099e2b3c6a19403b1f6f3911e78c794906f649e966b9d2c387872a7e10b	1	0	\\x000000010000000000800003af0e07b8042b34c1c2079aa5c526175ae2fe8b8eed334b701f95cfe7b7aaf4538023caa2f48e7bd609affaa1d3e74f07bb8890de921701be5962bbdd85723a4a86b64ec2873bac7b53c39c52247316bc68a0b5908cb268b4564237cd57409d4e91ea2f92a2cf1068e420c9dc02a525c6ef14d332ae1e4a22a86ab0e821401543010001	\\x9d51e9f213b99d32e9f37969e2b46343289b7b548aaab6031e02427705ef0c68f42ef8334000ca013b91b6333931b46cf83806d33e7fc57c879159797a6dd30a	1661077893000000	1661682693000000	1724754693000000	1819362693000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
295	\\xb60a349f61697b43d0f591fa1e85499727206e211af5b4b004b0552d7509cc1638a965d38627c94f2de87b763facb9b1fb24cb535d045e7ca8249b39dd77e51d	1	0	\\x000000010000000000800003d77ac6dcb6e3029999bfcadb9af4dc4b3c338533d568851a4f57633e1cf2444159607ccc43988296a84c5ce2d1fd299c5760f32931812d0ff7ab009295055644277f343804b5cfc6bfbd873bf550c473621938a2e0d31328fe3834b1a4555ef40814449713f0e46c3c2f6999ccdf4511e942ae6d3458ff809c84776f8ea7c82b010001	\\x700cb301b173a4fd3eeedafd9b0e7e954c5c2a28c43b50ecd3a07554dbaa38be72da50c05a261eef34fc966b69ed4b1c13d3a65762b2d2b14573b7836202a904	1668331893000000	1668936693000000	1732008693000000	1826616693000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
296	\\xb78223d28a4ac18c964c6cdd53eba9febdd1e8138612bd68c7c623f76ef0e6e0fef0d9a42853ad9305ba2dcebb57441c5e1e279b80cf48f35f3d0520f13cf5f6	1	0	\\x000000010000000000800003c6c40a4c45e8ffe3815775ccc4febff2bc043fbfbe38d8ce8820982dd665a19ecbae5d19d18d9ac884d045931492e31fcb513cad76200e630b9c7a3aedb1d7ee6d442f04f9222823ad29c39a12cd41c7eb74c030d770addbb619a595b54f0c58af6cdeca1246a554e1c96fa3f84ce6a1c8c2004f17bbc61221f1e1f346c8e501010001	\\x9877c7df0ab2634c943858a00e42048947a0b01c9d53a5822075ba4115e6c61887a605ba3dd14c0628822c720adc9072b2b3890d0a64243be6dae357aef1b300	1678003893000000	1678608693000000	1741680693000000	1836288693000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
297	\\xb832a3fcc3581ca2c10871629e5c9b4aee0ec35bb3007c94348aa46d56a63800194ea34a622eb42c82850280b3f6509349192806587829225c98d647ed7bc47e	1	0	\\x000000010000000000800003ad83aec773c60ce5253818b029a64f6dc5dd46fb3d208b1e49ac69ffdf7f68c2dc8601732ac9ca61a82ad1a61ad559b4cc2bc746ae5084f953dddc8eaf607fdbec39941e16676324d0ac8f014480d3c7293ef5cc0710073168ae9a3615f266a1336c7d8f91e3bb2d89d21402eef372520f0151e50527d33e6f99c10bdbbea2f7010001	\\xbb28dd6d95a56ec05002c3915d7dc4fd0d868c99617bd9edcf64001f5594999bc606816b83ed4f9ca9bdf90aef20de81732533745bbdac7ba09a08cd0ee5b306	1664704893000000	1665309693000000	1728381693000000	1822989693000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
298	\\xbceae1baa96d8910c64842019038dc88b7feb3e1308e8b441ab5dc2f9d531f71f5173702ef20a66fc31f20e3ed7ab3e421caffff33f9ce709e7bdb254f41ccf1	1	0	\\x000000010000000000800003a43e918ee52cf356dc6fe522e255a57150cd463427fdf158c79b602cf90886b2224a341a6d12a16a92f34161df15b0a619e95911ee490da5fc57fb1712b65f844522bab14e2846af31596c2340322870d1307b1b1829fcc924c8d46b7b6b5479e6fe3a28e74c3a318ad354475979489d8e7747e7fa01d2229032a04c5472fa85010001	\\x04889c6d16e732fb736728fd0234437a638f0d1fbf8a0386466631eca14b3104eefa8ca9ef6536867a1849d3161e38d0e5f92c50fd65f5a9446250dafe996109	1656241893000000	1656846693000000	1719918693000000	1814526693000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
299	\\xbf6a7fb47b93825c32c3fd4842a0a2cb9b05041ac555e256a0e17c8232e8ee603d52412cff99f8f508c134b192989acd5eb62ffc62ddc44556239f7ff40577d2	1	0	\\x000000010000000000800003d57e16d41772cbb25e57dde7c09f17641aea895f859f41c55acd82f74cc6b739dbb5982111d60603e6fed369e2991b781d4e4bb550c33bd59fc8bcf6569d61768ce6d3f5545646803990f1cbafa31d37bc1b2932c143ad5ee27281972bf34017eac9669e99ed0c70225fde32470fa5548a0a927ba0b3a8821cd50a9404d87d5b010001	\\x4131cf6c777bb5f38d788823f49ba5b313c9cbc6d1f8ca20560977d069d2d3c9fc2121a5eadfd4dab3dc9dd3a7174e5cf76649f4b9c12c01abedd2bdc5333605	1659264393000000	1659869193000000	1722941193000000	1817549193000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
300	\\xc18e9f8126589083c7b1852f6b8447f2385edfaeee31d1a33152ff544f2f06f31ddf17e2af95ff697ff8b8da8b35935e1b95231c05a1cf10c687eb3bb8d3ae84	1	0	\\x000000010000000000800003e2cb51b8932f29ec2c05528c6440543d6a5d1797b8fc4fcbe38deb7203ea7b7b13d13e80d8bba2d793f4a9185ac60cb6d4abc535631f273dfedd956a8b2c2091858cc9accf91cf3214539b63bfdf80d50f20b92285f86ec1ad300f27fda483bd005878e50d7e359906ea57c56abe804913247e85d8fcfdf5c5fe162ac989e401010001	\\xb91c07e7d0dd08ad8f3f501ce7edd00ff2a55165b00a64137da08bb84794474f13fa7130bdf8fa1e005923898b1865964ba8271eba7396365a9357a6f9cb1704	1674981393000000	1675586193000000	1738658193000000	1833266193000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
301	\\xc15e68f5808303732b3555548f9546223b22fa346b7bce55768e563f5a28afa65ee9a9a440496629ef3641707261e13d70a330c02e94a323a2847ebb3fc794d9	1	0	\\x000000010000000000800003e3629a0750bee26d48651b64ffedb7ac57ba11ff37c4176858dd4a7cb7b4412c044b25f94c2a54e7390ba6a223efb9b5727fd079dc26765fcd28392145903381a6e298bfb3af1aeebd5dc7130b99896ed556a79e8df39edc9e683f9e907d35d227c238ec0899660c04daa7d0e0d04587ec8537f7063a77feb7b9baaba0b59145010001	\\xbeefeff60ecf5edca585c33f87054896487a103a77aba078e0ffb782715457f203b80f62f4d0fe7c9d2d5472fe17912bc7e4326e539a614cc4517610f4296c05	1665913893000000	1666518693000000	1729590693000000	1824198693000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
302	\\xc172fda7dfde5564ae58bd43187abfb877b4e8ac7b121e99da812bee5fcdabfd40faaf0b929925bd8f43318246cf869e07c9baba49c949aa452e44c8d773623e	1	0	\\x000000010000000000800003ec8c7492421ce17618f745270367034ef86244e165fa95a067d608cd4b4291ec094211dd1a04ff3f42b80e60f8f04bc2b845b0a6597a1beff426cc99032b34aa32aba49379563077f3548b38e815edc502f5b21f0b7171e9e9dbce204ece0d4ce1807889efd7fa0bfa2019be86679196e099a078b5ec834d2729cbb44c220c55010001	\\x80c587cac9dfff339deac43e9589c4bea954c4b3cf990515ff2d67bfe79211da3fd9a17977c40bf05e0f658d49411b562725fe1dd3be37e94159bf0708ba2402	1678003893000000	1678608693000000	1741680693000000	1836288693000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
303	\\xc7b20068ca6dee06ff61469ec6d38cd67ae66a583a4945f48942f9405eeb3b73a91d67e3302956b049c6724a3b59f9804b1998e363c66979ad43a82e7a468662	1	0	\\x000000010000000000800003cf9e0cbae72d5cf31a1f8c23d82ac943f1731e824ccda1679ccfb7f326f05366e9eaef4db6a18bd1c2dd32b0c57c4232e0ae37e8ec9a733e9913846d82baba3f1e8d1d98fbb90b219e22adf9a17a5a92f5d395b441becaa3931efe609e6fb885a1eae27691997fbe11b3e4fa8061796147b50949bf95404b3d69f101f7b106bd010001	\\x3c1e7acecedab8c4e1f925f85c9b5c50a4055b7d77333627c09a13837654d4b9e6e66d5aa07718ed9cf1b348f537b7bd47d78e5c9aefd1708e63660a78b84902	1659868893000000	1660473693000000	1723545693000000	1818153693000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
304	\\xc95aa708508482ffa708777f7ad3584b8ed1c22b51036e5a83fedddd41180db603271da9036c3af57c2e404cc4aba830aa8ab894456d2b3d9d5b272e01dafa59	1	0	\\x000000010000000000800003cf26c2ab8f0b7672f5024d55168d694ba80a0f4b62b2b60f181b176fbd53403551e2b6da8e2369efc6d86c1d694b30c3fff876737d3958fd741e2fe435b17b38eb7de3a2162fbfa7ffa578add831c85faf9d0f25c2454958fe0c8a3e7c663effe0a5b7e8064779ce3fcbdf826f3418a012fdba92832d623d45b4c447591c46d3010001	\\xc811eca06d0f846c7ae3cde6c5c303a644b06d4ce1c60e9fb2a1d119bb34a3a110565985e5f32db6fc04b3076d4e20a9ddc3bfcb5a3185f01abbdbfe9c303f0d	1659868893000000	1660473693000000	1723545693000000	1818153693000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
305	\\xca3215f2ba3cf2e33b537e7910858444c4cae383adf39454ea191316d4b548661aad3078eee0583dcc44d3d4509c7c1e7c3e451ea75038d7f1a0bde73f2445c5	1	0	\\x000000010000000000800003c4de98f7752e9dd09a52464bd1910406df5c3e721f1060ca0873b476a09dcf4523b197d3c98488b5a2ad426c7c7a8421b686224cc8e1cbadb18b9fb2b0158856f249861051cf5d723642203d89a59f4851f2660df71ea2c5dbe7ad6fc6bf9f07109e3f2160dfd4a8244c407ca5203013748bf69a3e989939d0ead3446acd5889010001	\\x5ca61b7bc3a4595fae6133e0cf379da26160fd68fc047614f441b9452a173dd8a50964aae361991df443c1121b7e296bd26fc940fbdbfe59a18cd3eae0291605	1674981393000000	1675586193000000	1738658193000000	1833266193000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
306	\\xcc06f7e7dac02e06f649ac22503a574d9d8d8e2ac0de2d1f695cf87117c43c9ee944ffbecd94b2d6369b1e60aa17fc2fc23ef46677abe9f7a56d63385eac22dd	1	0	\\x000000010000000000800003b8ad045226bc868e291a269f53d67ca6da53cb31431a5455f1b8767d8b8ecd534143a19f2e81b26a84e8228d9934da7b4c669c6b767357a348ae1a9079d64221cced98fd5d350b9767977fc4c9f2c78f45419146b9dc8ac501dc0117fe4d1f5744d54dd2e8494c6f881785b0b241cda2473244484ce63148e6cded6cebae79bf010001	\\x5e719684abfe68e5cf4aba4c7eba909aab32079a6cecf54a36032b52fdd32a80d9d23a762b7055a8784e416e3c84385c717f430ba0eb81c11fed815b4864bb04	1667122893000000	1667727693000000	1730799693000000	1825407693000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
307	\\xce3ea5e62f1108a40343f04186c7676cc1d47d3a0994e9e7e2288820806e87c4de1b3b3be09914b7311df401a837654ecf4003b1d8663c7b7da60a10a4bbfde4	1	0	\\x000000010000000000800003bf896b0b2f2915bcab0ad6df2b986c69e81348816f35510a11c1a3cf105f6edcfd38d17888e80a361164347df8a8bd659f61c6820f0b113043b8a5fcb5a7a78700e62b4eb93312de4028acee2c648975b974febef5a5cb5f605eb9069a3e77f7989d60e5a8b45432400c1bc564f175847f3f5192bf251ee9db6c7c18c2d08ad1010001	\\xbb37c4979e4b6aeda0e46968801968f5886f21c9c22aaa66a55735baba5556fe76ea392bd888aa20a8bac011b158c7489c8fa7f25eae55d32e7ddf920e6b5a07	1648987893000000	1649592693000000	1712664693000000	1807272693000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
308	\\xd1fa5f2818af4d413fb68d4653255f783852e480502edc8728bec446ada4dc1bf16807430f4dfbd57bab91d031d9d82f7b1f44bc6be4ee7b66502af3dd677053	1	0	\\x000000010000000000800003ce602a9278cefa4cd804d10943a2e5daa4511eaac5889d939226d78cbd3f38033eeede88d0025bea56c12c4565b0afd9ca11c5923e27c908c42f04722d3ab3402c515d8f1957dc97285c7be6f66b025766d6933811148c864416e8e40e2acad601bdc46bc8c20c7133b99e62cc1b2e34195c8e94dd0e3c56320a0ed889a00519010001	\\x7146ec3d2782357ef38abffa588f04fa591d8053a2924f01ccc8748e17f9d13ad0ce409c7ccfb6433141f74785e1b4ee3b7704bf587168c59605131d95239609	1660473393000000	1661078193000000	1724150193000000	1818758193000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
309	\\xd35209bb75178deab2ed1cf976d493d9374882bd6544842db1685f1fc048583b3f06d745c5153e4261030da564b8261d793e95f30f9a97ad824f7e70248e2d41	1	0	\\x000000010000000000800003d3823ef3ff3d2554ed18e56099db33b9e132fc5c398f6bb9c2e1c7c59b45d2a79268521bb2f605afcecddca18a93176c00549583552cb2d74639cb17a194e5a7816d2799bebbba10ff3085649da79c257d0fd7e343acbe32ec3d93526ec5abf46d9d2e34e4f68c99abbcf295ac66669b85e5e41c7d3224f66772348954d39ca7010001	\\x871ef1bc268a0e748074e8b0236eb910f00be8a6884f80d0aaf23182c31a15402d223afb6c79d4e48956c988a51f56d9f80148a2bb3672346f6397a5ae8f3c01	1662891393000000	1663496193000000	1726568193000000	1821176193000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
310	\\xd53e46a70fc7bb346d2b027df078bac4f5975d3cdc5eb2bc336a729332882a6add681bb68890c56f67d39c0bd1ccf26141bf62fc6f5206d06f2a10da9c63ce53	1	0	\\x000000010000000000800003a9cc5efd26feadd2c9620eeca1c6b67b1577e4e30a449d955ae9cbb2c98c66caf7d41931987c446a666325fd3debf18aac54229464afe6c5fc41ebfa824961c458a63df781c9171528fea82d7779153d9035e759f9c67ca7b2536a1499297c750da4c82856a44a6332983d4205301858aceef45a7a094950bbd7daafd3bcecb5010001	\\x6075bc67880e68f1c7e1160dff29d6f8a7dee181c03ff3f0139649028cf7d1af99f2f49967674d526a6551c9c9e10035058d191eafc635b80e14266fa807850b	1668936393000000	1669541193000000	1732613193000000	1827221193000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
311	\\xd666f2c359f67839b151e886d61de5b6e843da8e85906806f832dd84e248b41b1357e181a36287adfd9de1917a9dff2748bd3b8f4d2bac7afbcd7c774356aaf2	1	0	\\x000000010000000000800003c2a6ff3067d065da8665cecb0ad9dc21807943da5bf09477bd3369c713ab0d62e4b59415d5a5337fd3ef0944b44608e6d32539007e981f47bd4abe0ad27022eaef6a06ef6a038d32b281ef3abf4aa937403749c8d668364562ad8d750c111b1ed580d25f304eb62601646a9ae3227a2c5deb1bc4118461d5c55f6051723017df010001	\\xfe5679c56504cc0ccb50599445ad4dada3247301f7093d3e101bc6b4a35a574f7e63d26d1a6f362a918f1899ff5795cd14702fd4a1578c464ca37d581297f50c	1662286893000000	1662891693000000	1725963693000000	1820571693000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
312	\\xd746db16088e13dda73d955c99686383f52490802b4c593fdabb2fb6abd340231f330a0831dd928d22b1001d5036f513ed640d226fe7734ba7a7e4e200de37e5	1	0	\\x000000010000000000800003d4aa6afe5154e3b7fa54f75e9cd9b48af60a8d94a9f9eb62eae344f34f42f79901dd1380083879797bc23479fe3fe2a222153a8120b0e9f42e07cbcbe7f4b4184e00677d6df3e25048d9c74bf871fc42b448d14749f2fac695ce6197bc34362cd621e1f232faee6795649457b785fa3c9ea8eea49928a67659d00cfe3e975351010001	\\xba76a449555faf7837783bbc6929d3d005a52b4a7f164522270750b5cfa0a6659381b21ccf081851134819f366f1a81ef3d21809bb23d5bddbc2ccdf1179060c	1679212893000000	1679817693000000	1742889693000000	1837497693000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
313	\\xdca6094fcad038d2365ba98abacac5887e039d492f835e0abfc00bd96d528a6882e983e070d73e128102971691fe243da22e8ab01ea7e2ded78d957687906fba	1	0	\\x000000010000000000800003b5ce4f10c515158ff4be0fd323d5d816fe3ef8125edfcf6bdd92242999afcad2d43f2966328d4c9786eb73c79f680de140a33a6003fbc9cd0ba4bdde6d45a753eca38cf52f792a97e3acfe7486ec8adbd71aaa36b2520b601757bcad8584cee92973c6d9f3b1eb01593beb857f27ca7298fe116c55541b33c0abdf620a87327d010001	\\x97772339baa2add35067f1f3293b9c2d9b1c96f3a09aaac6aa4c2bb562f37b33a33ae8c307faea74a4b5256c4df0b9f65e2b7fa2dbf5d720104d1f777b7a9701	1668331893000000	1668936693000000	1732008693000000	1826616693000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
314	\\xdc7ae0acd06523b0bc63c1bc44ab36f09b08e738a8dc65326b1aa85cee078709cb57d3ee1a41b989ac114c487cf6f31665875fed30148681a9dc1631cbdb53f1	1	0	\\x000000010000000000800003cae276f48b98cb4c45a1a7f2e18179e5c9d101343c0c9d7d2697dbabb85c96f09aa9c2bbfd7c32c6be9bd9d410aecfc0364d4b5f4fc3f31231df7b60f0fc505c8437e683d827ec9dcdb8f312e2b29047e0f3720a83076e406b011f1bfa434d08932503a6992245e2d3db78ad551469414fbae36924c0a5177f18181aca1c76cb010001	\\xbf31261b769e130746bf6853ecba1bab9a48761852da815b6f3d4ff3d397322fa7be925af0902511b742f67994f2c63ce7373944ad5e5094590572b423f8fd06	1662286893000000	1662891693000000	1725963693000000	1820571693000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
315	\\xe0ce85df1b6747848b40b02c5f596c34e1eada0bdab3424e67ca4d1f5e318d5bf6f876233eb4350476dbc6056d6b3793a0b74762f3fb487fb1f67c702646239d	1	0	\\x000000010000000000800003d5b704f9952608f4ea5e9c3e57fb04487e7077d3999a0bd2e0ee72c5467fab0835293dbef61cca8e00d0a096ba2e703cb536ee12f2c0e532ebcd28631d53b54f2a3d4861846fe0cfaa6e34237c8907001f678bb30b51568e38d8bf7924b0a7baf93e2ea31ecb02ccc8cb231d6dc454a06710ecfff1f14296359cad32bd809dd9010001	\\xfed96a3f6dd5eecdfcccab14840ea7ed6febf73b5e20a29cc0bb38c8f973ff9853f751babe7e8e6638f922b8a43df3175845981ff14224fdbdd51e84a9affa09	1663495893000000	1664100693000000	1727172693000000	1821780693000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
316	\\xe18ede4fc08baf4cbdf43b4de357a586a0c45ae83cc491a58c7f48508da504e9caab24306b0efbc719b356fc3743c4d8b928fc6d904ba5c07dee28e786c9d8ca	1	0	\\x000000010000000000800003b0bfb8ac876ccf03c641e87e90cb8b2ba26ab5d1488064e978fd69ce75530ffcb6beb4524636d1cb7e04608cc72e0197a55bf50062858383cad906dd1bc0e4547115a70fc4f3bec40a32eb11156548a57a91376fd76097fe1d726b928a869615b116286774ee5c31016b149d278235da54c3f89b717fc2ccb752c43e7c0a07bf010001	\\x0e895dd3447d331375f61cee240d2d2c808d3bd5b9aa0ca82cc06da003c32dd8900f69e2e715469d14ef33af3e3c7061c501eccd203a99bde668daa80f26b10f	1670749893000000	1671354693000000	1734426693000000	1829034693000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
317	\\xe3ce7c337716fe7b835b6916f86713e4ad777ca316019fc3bd46791465412220b650e2692e0dec9d3a3a2f1e9691243d33a32118b0c5f3c9e2e84d09d204a2bb	1	0	\\x000000010000000000800003c5ba74d7842acac1cf0c1efadc12b8c0581bb1c436e3266dc1899f2e7af4ebae5d1e110d9a78ea882cbd78e1d9b11b265a7a9a5a8966daaab789ba4b16747a8b926a8a2771ac3598a584a23b2b526caf29692a301f1c0987af711adfb3f3789b4c7c1fea84d3403dbd260f8edbaa7264237e6bc2ec5e7d8fcf59fca6dc988cdf010001	\\x54ed1644717ea5c154837bb1a20d0082860d074909e9506da1a74511ead76797e20784e7c61b023be6d7db130bd6588caf9ef7df16645f9475c9c4613a55b303	1659264393000000	1659869193000000	1722941193000000	1817549193000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
318	\\xe8eec01ca9d30ec1b45e185fb554184039571fc808d11be1b13a138b7a32bbbf4561ada4b78ecb028c34dc96b04a1b499eb585a92756c329f59ef7a15b594c9d	1	0	\\x000000010000000000800003aab6576343abf4d64856e55019a49e96501e711cc9602b0412671ee5a16c53d194644ff7afe8c4bb0de8e30f5aaa37a4bb1eebef8fab3345b1ce2e8c4d6fe9bf0d17350998262ce8b06a69e4e32d17fc52ce930aad86ca6ed046e01737c2452993a58a1d6593c85e543b39f3862d60ef680b2d42ad376ea4cb3e46974137d923010001	\\x0fe90ad567661f4708136ee4c16ddc65791182841454f6a3962e4955d074fca207b43ee77505bdc954660899217e9ed8fbb9d57d63e255f7c798635cd7010d03	1665309393000000	1665914193000000	1728986193000000	1823594193000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
319	\\xec06ac6c7ef1a3768ce2d85628531f42977cb99400de5fa794b3324571adfda03fca3c99c5c97773617efd448c7f360e7fd2079a3cdf072c15296d100ebfb23c	1	0	\\x000000010000000000800003e6d845194031202a8ec9f30f8d6104666dd5aa7e5f48267edcd9e507f6715596a1f279d58416d5bbe2988441a4ec0cee06a2928054c41cc383c2768a9771c57e062d88cebb5b0963bb7390c8d70bfd6c5d3d75c3a443729ad6994820adbdf9e380e786aa338f6f4bdbe482b49c90a0ad0fb54635a9e3d351c5fc0de2513e5e47010001	\\x63247a122660313a06a310e8b37eb753e3e0e9ff6b6a9f7fab5990e19ba24c244214dbd0521226421e605d728abc0dd2be9468a5d94ef21006179270d47a0f0b	1667727393000000	1668332193000000	1731404193000000	1826012193000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
320	\\xedba758ab564c8c38cd5436b01dca39e2a89a3c8126430a86c3699ef34bec2f1173e1f7b424fa6422b8dfe0dd53140fbdd0add3977bed565cd51d864fd16afb0	1	0	\\x000000010000000000800003c1ec6ff2bd7f034393c2c2d6a4be423e931b7fa286d33dfa9ada895db4a151ba7e1d7f3492e6dbdb7161e6045b0fa97bb8d90b70645b3ca8cabaae3ea85dcfeb109a53daed087f1c33c04c465c887399a9af3728ad56358a0d01c5a377750b509c3d9b7d70bbeeb7fdd825bd4bb46995a689577f97d3dfa9869ee87674a4f4ed010001	\\x92ad22dd5f6f69728ec55102ae949434ae11230ccdb7db2f1994ce25bab6552c3f76d3de3abc8254fffcb3c633a91798b0ee658fa4a0a11bd499f034181f2d0d	1676794893000000	1677399693000000	1740471693000000	1835079693000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
321	\\xed1e95bf5439a0014dde74dee9d68a78b1711ec750766bb3270a6169ebda928644338e171af496d2c7c6f394b6e904bb2684f2ccde4389ca6f8f5d3db9ac1916	1	0	\\x0000000100000000008000039661657389f056f7ab25909fd8f3167ec9fbde0014797b836c0808f2aa39f4be73964e46ededcf0cd13acfd8137ea94a440add1ec4230fb0b567fd3b004e66d324b5b7acd8a543ae225db7c4033f62549abd5a5fc4f03c5a4178dde45b4404906978acd0567a2b33580b10d885374b4a3276024a12b0a9a0c7b46d67407ea38d010001	\\xa761571c7e72e3798741580a502a7f2e07bd6fe0cb7b54f781d5dbbaffba2cf16ec48a4ea27802cf4c1f5e1c115d37412c0bfddefe56472bfb1be44aac138f00	1662891393000000	1663496193000000	1726568193000000	1821176193000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
322	\\xefaea7107e36fbdd6458d9482f8e6a452dc7eef77a19a33c9e6b102ed95e216255daf503a1283bf25a45cf21665019f51768ecbe6c689180bde60d8d15e5372b	1	0	\\x000000010000000000800003b8f249bc24fa3745a6696e3d604eca69458465860bd3961d1e4bf835b5efeefdb22c13c39fb5a44b8c931d5ac7ab8be89a6ddad01aa4f0cf69a22254593324ccd5c1b0d1e817e6e8a6b39404deb18cb84eed0f1116d13ac3d53051c64cd327e2825674f2525858841a4be803b29c46b02b27ad42d617d3413f2220cf87538979010001	\\x943cf8a5e52afce7a238c5764fa0349f0e20b78ad5959a4e0ec04faa244777c3c251ed4096abf070fb0d832edc4f55f0b6914984d45b081674daf58b3e3f2f08	1671958893000000	1672563693000000	1735635693000000	1830243693000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
323	\\xf0c258a07a188489cf16a220c5221d8833e7d7883026b7d66bba184283a1f9f324d4211d4854be1d10146ce12f177698821df51b49e9f91c9b69c72038284172	1	0	\\x000000010000000000800003c63d035a48ead2896ff41a5f0d6ece85f4c5075f1ddf27059e9db40e514cb1267235e69edc6cbf9dcf9541acdc300432800daa099b9c3a4367213f1d1576b40cbef9283188ada16dfb35f9d4d4836b1b95b04e0af0dfa5707c037e15f6c7dd5d98597ee2896005152f033874b228d8f6a67fb392308e684c52293b4d2808657b010001	\\x368013a0405a253bde261739fce489399786696c4c3e557b55d57806ca6e33e8ceb089e91782f0dfb93d1de7fdd54c9b3211a08b17426594b1bc42c9df993d08	1648383393000000	1648988193000000	1712060193000000	1806668193000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
324	\\xf1329f746d56126a062845b1abf25e06e9f14a22d316cfd077f315dfa3eb2b93cd2fba55bc4f6e8a2c99f186e351b8e35ece2550bef2ea016935ab62b77aa058	1	0	\\x000000010000000000800003b3c82fd58a02589a305e949c25ecda77fac68c121dc857219bb8751b8ef68f930b310478371fec129fc38e00aba223da2093441dbfe0b0a5f07b977bf606bac0c2201b3626426c703a41a8a02c8ad735fd511d4509329c5e5273c27804b3f9cad6d25b309ceefa6c35f29a41d0decfdc7b98ada0bb745e3fad292088cd127ab1010001	\\x178b8f087186fe30d07ecad7f1f0de9606300ab62a66bdee2a82f49463e265bd878cd215b80093cb221b2675e94aef0fad39da3013536701572f32856441170f	1650801393000000	1651406193000000	1714478193000000	1809086193000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
325	\\xf29621bc77ac565003ce0343cde88e5e942328935828e72b3c156fa2633409ec1d91884c8e47393277a668b8c2a379bc2b5db6453dddcf7d19ff7e4aae9cff4e	1	0	\\x000000010000000000800003c253a6debd3b191d7495e2b71a6e50b118f82ff2d52e679e415c3e52cca1a62f4ec9adeb0186596affe6355246d0bdacbd2eb11a1797908bf35f07b8ed59410ec6573603f980e85c5afc2d9809a0405e949ffd1fe0e37abbf3f9d6cf7b190d1e688d34d7084adb7632ccd77b98b762b2684fd3bcd191197bbad35496e0133181010001	\\x68986b96abdf164e3969525b1e4ba9614052637ed6e68cd7a90fbdea2408afd1bfb2231fff590e1b77cf8be08f46278271d8f5261371d5beaa66570f74fb8108	1659264393000000	1659869193000000	1722941193000000	1817549193000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
326	\\xf3c20ebaff53ab86bc2545f334d6020eed3a26bf795058099a8bc655eb770cb7448bc29e7f9a7f6fceeddebb6b61adfde785fcb45f9101619493dc289919f141	1	0	\\x000000010000000000800003d8ed3bedcab1b8b83d03f05b663be9452b3013500131e81931017e420f47dd4e2bcff3e3af8c6da493cf79035ab47d9c23f76220cdfbdf8a58b45e41ce3a2558b49af8c033e4b29b2263ece9e7b7e0705ceaa2b9936dc70eda0da9b5e8489ddf88924d7171ee72317a6af39ad2c604e489262b2e447976fe2b8851c6b6beed55010001	\\xaeb66ee086f11cc787c51c7a71500cc3f163a3393a1f7351028724c4e317fd44ed1f1e1fc12f413f8c6105568dba425167cb4029474a6294c15492da142ce00f	1662891393000000	1663496193000000	1726568193000000	1821176193000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
327	\\xf78ac129d0f2dbd20c32d2490720ad325f83d3c71ae236bc048e47fa51912c6dda9d3d898488472de7091a84702c49116935ac69bff6e29048b20e0b3cbe0921	1	0	\\x000000010000000000800003c88e289af37da49fef30d4d398e22eb93aad9aaf0a99952337967b6837804eeafbd1952ed48504add5d3f3f4060e1cd52e2e5dffe9d7073c7d3a1aa47bf7d777d3d31412f5a7ee7b7326e6702c2f298121d328e0d0fa26142224930cf906fd9c0754fb2bd84d69c56850de00b75556ef8fe7a8b6aa72998c48761ef27373ef1d010001	\\x8aeebffe1f5cb64b0bb69255e00b6a7fdcc63395660fe65922a8d5bd02dc45bcc55d39b1acd65284cf02156ab54a3c510c67ade1e542ff3d70035ea851f58f00	1659264393000000	1659869193000000	1722941193000000	1817549193000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
328	\\xfce6c13f2c99fd51d619cdf82183653ece6dd1403d6812c5602a5ac24add3d0fc1b41f9cb0c703f006a728b26b9944b07d938369226e5c28b1b31b687dbe13e8	1	0	\\x000000010000000000800003cc14539dd52264d180f05c6ee81805d08d1537c0181063e0a73837f41e3f369668fe90773795256495eadc73a4b18be01638496c45222745dc7db3a4491f2f78b515095ee11b711e6b7e784eee9bfb9b75a759de3d65dd46443f7c7c15ceab56c7ce290f9d53581b3755875e804ffca1d3c74ac56c0d27b74f1b3d12936b8689010001	\\x3bacad2a8819700c5a982920065445ef3fe389b979c5a4b9ebcd3283960292b9ac19fe575b0e150eac0c3c049152b4fc11eb267625fdc043d518bc5000c7400c	1648987893000000	1649592693000000	1712664693000000	1807272693000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
329	\\xffbe5f5e6fbfc5d4f2ef5091c37c0527133a987a1f02c5e78fe9c27fbd197c558ec0ce1f7c7b2018afd7dea8fa80b2c35616049b71f36c5008b2a0799ce7f49d	1	0	\\x000000010000000000800003ac46ea55e2053b0baf0d0ceae174b9c4bda0182a29adb83d45a777d60ea03de2c5282e8583af4977123b7a92cfd29ed573bb1e6ae561b23721da452df97a72b653dc921484bb5e08714b2c30f4de2218181cd664561433a363e9c458ce7dfb29f5809d6420599ee0985155c181b780b22fead960fd4d320b0db8ac281f73ed21010001	\\xc14c45d9bdef2d4a432f0746585a3c05fd9b3c8e446bd5c449d07600ed85a7d4adebc942215d1680fe78b409ea4ccb1ef9fa15b816747e1c51af8db4d5943f02	1652010393000000	1652615193000000	1715687193000000	1810295193000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
330	\\x03ab208dd2b517dd5f4b4f598466eeaa453ac311dbb22cfee34a77c2852b196f032f90ea2e7e1165c3ba36e587ba7bac2d3c9360a1de6bc54478caf5448dff4b	1	0	\\x000000010000000000800003a8c62d039a43926c3291ea69694591fea4f32ed7af2577f6773750768f6ba319b69df654b8f4603202d9b52517b3c5392261e6217190de06a8ba89214600d220cdecbd026c8aa4bff99254a9fa101b6683e17b37a10fd13e3fcc4abdffe806af5155d3ed7cbbbd66e66a9a45b2dc99f8d6d65190f097fe32075d7867e113a3cf010001	\\x6b4e2508b56559e9498729da66c9c28438832c573114fad8c1334b0e84e8db79770831ac172fdb59f163114a0136534df685e22249626544d5d0e1841df1c30c	1664704893000000	1665309693000000	1728381693000000	1822989693000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
331	\\x063b2b6c325233bb65b2b71c4aade2b7540d0ffff6669020fb203555ae57a1d92be89af0a6be781391daa195e6bc9dfb79df8d3a7f8dfcdd302dc05ad04258d8	1	0	\\x000000010000000000800003bb1048016280415012a6e3115041a19855d898907f2a55cc3aa8572b4d67f708da5fcd8ad2ac9a3e8b237a92e66a0e6c2efb31e6aa4627969ca177f7781e4856aa606afb1a780ab46a90a0b5f661d17e7d53eeca4e4ecc3addbcf5c8c18d4e670afacc2663ee8b7934f1e5177f7e5996d041194e34cd558d669f5a9fe302f6ff010001	\\x8c9eb338303578473fa856af1b3338cfcd1458fb4f38b452d2b3a493289fce8d99b84939357cdb85874b25e459abe16eeaf3df8d83eb651cb763fc26e7294406	1658659893000000	1659264693000000	1722336693000000	1816944693000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
332	\\x082bf2750693769433e507c68aadb39f2f9f22624b42248c73cfcc902d49e2de5933cbd00779577f2b037ba8038538f9e8a58366755ec7f2b172591613e30855	1	0	\\x000000010000000000800003de38027baf1c4dd7393dc39b3297cfdd07c8a5d94704cbc70093028fa82c80836ed48f8e0af900a9358b3c42478a2e77ccfb419c3dca7722d8b1db55c5ae3cb642504eeaf8b98770ec12d93b25757ea881df154a9ad14cfdfe41fbd947332db615698e9067c02e02a6b6691c4a3e5083ee810c0579247f23edcfd817ea8f11c3010001	\\xaaa15e3e8be91405e2d1d172b39b42451daf95123a43c2817e05878e2c739e3bbbb4b6b76769518040194411229df9bb07727ea3db707cc96a18a23b03b5ac01	1659868893000000	1660473693000000	1723545693000000	1818153693000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
333	\\x093b5bb16e634e4a36caaf5b603f0f7c5eacce0b76140a639d48a7ac88047b9133cf111c60758c059137ae82d239bb6402c3bb88035903d1a3963bac74003b98	1	0	\\x000000010000000000800003c7ef6cf25f9b8e001ba0ad14c8a9a2a7ca4539b244763ee567f67d50dc3c023112c52cb75ece04d7470c9e84b844afc7cacf07c70ac0b5b55a7a50f518ba5458b6de9188bc56ced4022b5c41755b240feb6b37070f893fef0b328acb2ea7fbc4d4b592c11a3310311c6f203c92727bbb464767a9348e14522d14f6abb15f1c5b010001	\\xeecda4eac549e9f25135ed3d252e96b26ca635ddf58b1d72fac2f13e4730ba8c78dcf7297b587814b1c8a5eb565f814e0bff712185b05b10e9b64b3152c60707	1672563393000000	1673168193000000	1736240193000000	1830848193000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
334	\\x0aa335b390cc413b3d2e7cc5e48495e441a5620f40c1fc1d79565e1b39b8dc9323465ed23bccc7fba335b3e26a065e557817a12f4d0d8d4e9435abdb6582275c	1	0	\\x000000010000000000800003b7bb1ed12dc567c96c331009f091e5eb59b701d93c250e14d064d86a4f9bc877a7661bf08bed1dd31ba6696fc9a757ad8efad7d82b04c244a79ba2fc15a2bdc747df3f42e0bb8d30a20900d4fd02809f5f78eff27446013dd67986cdda3c0c67f9ba2cb054a2c78dbfbfe03cc78417f9c66b325d50f38c9677ca0bb128ac5fb5010001	\\x35f563509bb0cc04bf2fa3a3da6cabd4eff60bf81e092cfef041398f032874c1dbb8b8463125c935d6e5da946ffc100471b086cb72c75e46d35927ac906a9308	1676794893000000	1677399693000000	1740471693000000	1835079693000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
335	\\x0d9fe51578e78302d890f6b87fd3e3e0fda621c98417baf8dbebd31a2f5437c1014e0a9763274e7261a1dec0e2e8319953679101f4233d23418c2c7202083937	1	0	\\x000000010000000000800003bf08517e3beeb15358967734457edbf980c7ad6c9c3a65a1468ab2106f6ae8b25dafa62467e6ceb1d596e028c3e4d56495e311a192307eba6f6535c9de8435318dfe33c27ff57390653c8575bb08a50989dfe3469268a40b8692828c34ffe76c6b9dc5fa9fb107725f7a4933435ade5ffbfc57fb93b1a9a30d1ce5f4195ea795010001	\\x5e2af03d4a3a3e816e8d0f640ac62b9eead34fc67e2a86706fbc55b9afa524dd1d1c7ddb5b584d066c56026affcb8f3e1a93d4219de4efed31ec8514510d4a07	1670145393000000	1670750193000000	1733822193000000	1828430193000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
336	\\x12bf905bfe4c143075cc09a5560d0ac5605d54b8eb8abf09d483d33d459ad601f935729cafd2e6a97c494dff221121c317309269fd4acc1f80947e628211aa06	1	0	\\x000000010000000000800003bb4ab8c6e58ff4c96bd62eef0007dd84e1617b4467fe2c53b18b07c7000d4f93cb97a51d57ca05bafaaf4532aedf848242128e323fc303f37e79cff48e6f6d5714520bc88004196b9c92b3df8531d690fff133de10f154d3b72538a836cca476493700d5d810dc9b1ff598300d7512a8b3fbb7bfe00317df50dac8c4dd20f1b9010001	\\xca7ad132b034deafcc67585c99b9d38c46399a81cbd5d8209f2bac61d39abe9c4b0eeedd9f7fafc1a75e4fde2918aab74f9da3a09e8aba2ff4338603a286ce0c	1671958893000000	1672563693000000	1735635693000000	1830243693000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
337	\\x13e78a3aee258240fa73015690b1135fc951d5521a7791e8c1117bbbc6dcf53505bd16d6c651f320393babe0d6a5905d39fa7c6e115c1ce01ab9c12d93430317	1	0	\\x000000010000000000800003b5e04066a259d1d7390d34fa34cba91cc64d4ef31fd6de7d6dd9a82cf30d2237425f3407af63e2ba893477760eb945163d18c0e03d043a2955c2028a84b29bb6d08d7ff014cb231a0c5f5f0dafb65202955c02b0a3285464039253e34206aa3f48c3572cfbc2f5a36eb20a3fdc5909740ad43d835b9031983374b54da7825f1f010001	\\x14f7fb44b2dc448599a60735528c2d6892a49f4dd72b73e73ae7d383f671047e6f22b8411bac7292fd877bebf049c0bdc52c64c49c8183b37891ea6802894c0f	1655637393000000	1656242193000000	1719314193000000	1813922193000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
338	\\x14a777e06a0a793537e93d5a8ca8cffbc96e9ac336ad43ca398265dda6a327f751f541cdbdf56ffc2eeebc79374342407590155463ed4dbe262c4377a942dc01	1	0	\\x000000010000000000800003ed788064e4d11ee2c8c19d564c0d30ca18caeb6a8afdf49be8d4cfaa78047156cff5c0c6ee5ee00136443b8557edb260285d7099aaf889c7303ade89ea36dc1f4b4a5eef757822d54f93e369e17ee883713fc6e7836cd3ab61a00e9dd21b738e7e6e2ec577a5899342070b95b2717074b0f177fa536c112ae77ab63f8b86f379010001	\\xb391d7ef962288e9c40669c3fce39fe9d7fad12304b0872d234e69d0e1ecbbeaf90408af46189d90b7a3af3586e54658dec3d41555f72ea62d312dacc861ac05	1672563393000000	1673168193000000	1736240193000000	1830848193000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
339	\\x162b85d275083bf6a2a571a1f888d774391b28b18a263eb4cc856d48134fc5c14c7d3954f76f667c1d191af01346428f8e8b98e31c904ef9062f5e68817556cd	1	0	\\x000000010000000000800003b9fcb4eb0a50f2888f361a5c49717652f21a804ddac6819a7b4bc8616e16f1cdcdbe59b9250ce8d0ac2df65f9f32fc6ca89f429006a3e75902fef06e4503568f540153822b6258fb4d2fa603d9a4f28c6ae6eefef09ef0e215aa76c2896d197648437db8e2a78c858c083cc72eefa9217486ef7ecfdb09c6368baad6b359e5bf010001	\\xc95c1ab53268acfdeb52b4569efd4b8965a588c4dbf827f01ebf9778328ac71bb6a2f2329a2bf71a02e77434a9d762ee97536255b22442bb6f6f2d0cc83aa900	1652614893000000	1653219693000000	1716291693000000	1810899693000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
340	\\x19130304e21daa5cc0d6e6590c416e84dd50175b6e5c858f7b1a4eeabc797e08199bd3095750e0d337f35245c21931c0aaeab4185920fe7496a39c51911f3127	1	0	\\x000000010000000000800003cd2a214801c9fb52f0c783b5793ffacc688455a073a81fc27da121199fec5f74e36d400533576125e935c163f268d2d8533c018df6a41757e3d5f64c7ed777edc38396b81da9205a697ebc137693e1b5cb94b327c6ed4299cd7a9a77c51109240af76464bdcce01ca2735dce22bc859ad7faed0e8946db49151efc3a31b9d67b010001	\\xae9fbfe4676438c059ecf93490f81b4334a7a20ef73e980c05b84ffb0f3087bef0736612f3f01dfd135cbdf22843f47f5f7716699205ecc4687c15aa98ae2a0b	1661077893000000	1661682693000000	1724754693000000	1819362693000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
341	\\x1a1f21d83a8931fb41599232afc520c85f77823c9edfa98255efd40fd0b71af4dd125d575443f03a7ed2ee6a43ef76be9eb5d3ddc173db6b1b0b64a3d5d00a47	1	0	\\x000000010000000000800003ddf2c8d2365b528c46166f063ca7df16bed99ac0cd5d5423b67ab96c25b28bb42b485591c8567ab99f45c9da889ded6c8759683503a9956f4479a5d0f80c5f858e1519bacbc6b1d114214e53b7e4059ef05b00f3b2383c111f7cb41c31e49a9714a5f01f398a219c2bbe5d558730502fc85325c80cc14de18697a75ff951e6bf010001	\\x6dd6b6d2b38f6293598d7dfe37f6305f8def5be1b6fb2bfec15bb2c3a61f196fcd3890f8a5b496d1d960d27d2d4947398b44575c4a910f95de5183f76a451707	1664704893000000	1665309693000000	1728381693000000	1822989693000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
342	\\x1baf778d3840b6df439f93eecfe1591e9e8c96b64aa8a3f2e52594177f0d8c35b2d3a95d7a735e0b33544f46533d4271742923e7b9d4ba083759b06bd3383f49	1	0	\\x000000010000000000800003ac232cf35a8b7f20058854f8fde92f136ea8544899a8f2a042aef2c98d3d391e12ab3dfdcf69b4e538228737b5d7bacdfd5ba3c8e6d280e51b8a183cbc49c18acf40edc84ca4e55f8db0195ccf00bcaf2b2ce252a7e961b56b43e3a8e90463156ee9d66ad69e3b366d99d13802f5475c9478afba6b4541285d33a4982b97912b010001	\\x4ae6d665d6e1c8c93e876d225a68d94620a3a9d6ff06c6ed3b48f66ddbbd7f66542d9ee286fb33b05bf45c50b29a1a237e94ccf0a9f21217aade8b593077b805	1670749893000000	1671354693000000	1734426693000000	1829034693000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
343	\\x222baa2142a715369beed936140ff8f76ac58417048c647f84bc4573fde411b4177c4ec13efea9b304d7b2f02491920440d559ef0fb4235977e21d630bf8ccdb	1	0	\\x00000001000000000080000397d5ab91274a0d763f32c837936cf94d51f1022d029981464ca8294b92b4f45a8608e6ce3267a7445b89fe7283af444340d28d95da4c66c3822d1bf8149f51b11e8ebd4f3adf9934d03061663dad322062f098061418f8860918ee95d4766ba991aaacecb9c8bf2316cd1c3c0ad031065e876e29a35a4a2a1270baae1149786d010001	\\x507eb9d0ad2e1ea90b86436f833aa869761744b831db22dfcbb60e545d7be88e9e90c45e8676f119882422bbe5c05f6d1e4a1d3f361fc73525f14409e140ec0d	1665309393000000	1665914193000000	1728986193000000	1823594193000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
344	\\x242feecfc284e464ee0d95b1bd8dea854c5bbcab600194ce5759a8bff261d7e1e76ba220b2776abe58726aa0089625dd385350c0211e35614cf5d8cf25dff92d	1	0	\\x000000010000000000800003d3a26b23b9faf1a97c0f49d3ffe8c6e413ed2f1f6600f228000630b6d8ddd6658eedea50258541d8715f3c5c5759e1ac99474a417532be5f06abb1e1386246612b7519cb22c3e0dd1610053738ca4fbce55bb389039a563239dceb2d62a7435b9278384111aac8fa195b20095a866fb013966d4723aae67d56b4fa6eee096675010001	\\x211f29addfdc2aa1f39449bb9df6a468a92abb05962a9dcd4aa5c10c906e2fa1aeeffb664379d339d19f6f6bf53c02f67024136cfe4a9d91fa2ea444fff02a03	1651405893000000	1652010693000000	1715082693000000	1809690693000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
345	\\x2b0be205c6399bb65f87289faa026113626f34ece252e948722e0946ed0404e84d984adc31fd110571b7bf79a589742e32ae1db4ff2a722f4c749d42b1d0369d	1	0	\\x000000010000000000800003d99ed6c599ca68c7440d48bde7ff49ed5b50b5197f51d325a4b8b7b276e1515cad7b29cf04ad8b536ff09a3d9fa7818821b8dbd00802b22de701483f1bf322dca4fe85d021d1a99b78d129a95d808602a80fdf10db7aa4fe5c1cf77bceeac0e98ce3722b21a4c6afbea8287d462847619a9871223f79eb6f2f63c0388e8923bb010001	\\x7ef57c6f6c95623b31a3d5195c2951f8ac4cc68010ff28a63e2caaee0035fc05c63adbceb4e4b7b6712a016b222d389004e5613712220c14ff9c594236614008	1668936393000000	1669541193000000	1732613193000000	1827221193000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
346	\\x310bbe972f095dfbf9412e93feb3659f73d0ca3b5e3fd6d3182f1c1ae977d5b414f7ff907e2a13e403468456f90805a0ac4e574d66bb9121c32e8fb295763aac	1	0	\\x000000010000000000800003b1910c8045f1b943955da4835633c95fd1928a9395ddd15622ad3a0462fddeb2e16f45e299ada1c95835c166c44a25206f8957cc0475428db83d49b5632594b374d0d75598a9b3fc186d3a981ea7d68588f9aa05ffc44a0085f86f221ed4cb78ad7b7060bbb297bfc74c9b7af47d4820c60d9563d58ed3ec650748cdf40782d7010001	\\xfda8c03de1c4b329b7b8a1b1b27cf53601a7f195d9fbbadcdca2914cb8d8f178ab3a5d88752f60a46d57274fbf859995e57e68121cb6192b4902736db7303908	1649592393000000	1650197193000000	1713269193000000	1807877193000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
347	\\x3b1b92d02ff3d6d7a5dc430ade167f5248e17d1731daa54bcfe7a8e52e17487ac5f89394fdca061361ff1a40949d56d3b02d8cf470d9321b4b0c1683f7ff6d02	1	0	\\x000000010000000000800003b5774cffbb0edb86bbaa2e76b7fccc434a8971146f3b99fa03bf5a4ea0b838a544018c5fd5b94477779f56771f76772a793f4e043c7d68d9999484f7f72f322b6f3e10315a2dffb56b96de9726a064dc8d1a486f52eafddd08b049be72e2f8681c66715df09847e1910405d1c7d511ddbceb77f733893f9a99e9991f7f00f489010001	\\xa69e4ef55790688f1109b845d2fb49bb7b53bf5ff367661cd852d84da7e72365ee437c06fdc839871fc45b08842b0c4a243de6eebc32971f85bcd3d2db9aaf06	1662891393000000	1663496193000000	1726568193000000	1821176193000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
348	\\x3b7fcc013bd3ac15bd605c17e8a6c2c181aac69969a1a43405dce1ac60da5173f61e5a75fdc50e6c20bf2f27fd9daca06b8f5218a1827c524c07102a3637a507	1	0	\\x000000010000000000800003e48778e8ebf5370c7cbf7a647792ba77d6606510f63e08ebe8494d0554ae11816df752fe1d6189ca2f572a6beaff017b6f3558a33382f3153e0ace20ce29a1b7aaa64a4d0fb9c0034cff3ee932ffca8787107fce12eddebb6919f33372794520adc9dd7d00a910a477eca431d7ec623ea69b6479576e4f60ed83b26a15878307010001	\\xee415c38c4951aee2af02b1010a6e874f90cecb2279652be77439abf958bb3825f6b591b09f9287f94990213a83723b57f083163de4555cd29790ad1ac5afd0d	1665309393000000	1665914193000000	1728986193000000	1823594193000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
349	\\x3d231cba423adad19ee1ce74edfab9ac09ae5ae51ae770e9e919a5ff7d4fedf5a81ad724231dfb7beb82e20103091b70092133ea7d2fbdd581f51ef11d9f9740	1	0	\\x000000010000000000800003c53970ea4fc77e804f780ce5434ee476b29c40a1f2a018f03ca72433cc2915bf04219e00381112d96cb8f2cc413290098291c00b45f38dd5043b3fc9d9d286c2aced5cc8408f937443816893df466062a7bc9fd9c0874d83ad928ab7204a95ddb759bba12a8734852d9315aef4e4170d7813df3ce03c4094680bea5c0f6405eb010001	\\x8c531dfe392f02e69b955e3495ca4f9f561d6415ba422d22a14239e4ab96e0538dbbf5389183953c125b2dfc429269ffd256c7caac7a3ab1d2dc2c6641b7e908	1671958893000000	1672563693000000	1735635693000000	1830243693000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
350	\\x44b3eed9c67544b34e6dc0dc571a0c53e6d3c7388b6d8ee9e64b63928f2ed2a1d56376e95b98617dac55bfc568f4fac232595c291ab8e32d5b3d0639785055ec	1	0	\\x000000010000000000800003c054ed644a04a8cd0854a5e3b1894e7ebe2623eef204996cb8365cd9ba375c29c604f133d4e123403c9afbcb9ddae0650e86ea721d66641c99b9317e62fc415e79ec723ab7dfd94b9366b4cd3bf140807b541721050f4228689873d69d8fdac7627c7816cb02f255e1819ababf023c14fdc9c7244b2a7fbed784ac9039a48b99010001	\\x4264b5929e153e82ecee9886a0b76b81027c634ea6960cfe0f68ea7db17d8b7cd02baf7696bf11a8b2a3386ad2514c41ee9ca48c2dfc4d3292fe0e155b7ff40e	1651405893000000	1652010693000000	1715082693000000	1809690693000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
351	\\x45db629f0b952b397d3b88579b625b84ef878f1133ce928267ca05379817127cf237be9b242bcbaa6c98460b4230f0902a8616339f020af35bede25e3f66fcbb	1	0	\\x000000010000000000800003ecdfc3a3adf6404bf27130f85c330de038ecfd16e3b3f2b029380461a814db6d0efdb1cbe95e3edd38e5c52c73127c105fe7811bfd3a822f82dd7bf98e87d7ae289de7ddcad403a66ba9143229147856e0ded3dfc14f7585ef7f3f3ce573937fa68fd3f575e7200d43a34c6b2f2bbed00b9520a2f1e976f00f0e846cc1a91aab010001	\\x8cc03a10c4a4419599259c536e826ff522985d080d78df186c3ae1a7d62eeb67ef354dae1600c55bb263d82fe7c0f077acd6f826e6b80b962918721ca34daa0d	1656846393000000	1657451193000000	1720523193000000	1815131193000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
352	\\x459739c73c3ca843020ca30656c96c926c633554b572a38178cefbebcde4c7aa9e7b2015ffcc9b56778b10820684cd298a1fafb7d6b75ec900ddabb014dfaf7a	1	0	\\x000000010000000000800003f78c17c0d95f322dc22d83146f129fbe96a7a2ecafa8664e891e9ef8f41ba51d9652f5426093ad0b6b2eb6edf3155e0dc167931f85e212d275db44db96ce515e000e4ae094769b468d20fe243a0dbba4126148acb145de7492e62f2adb7fbd5dd6519c71ed2e0351ea520224c494f242f9d34139d6f35a8646f12a1562bd85cd010001	\\x1865813d02dec6fe26fc47835e5460ae53f05dc78623af7b7966b7b560c1c010827423e48dc26b234d462f4ffa058c26c61e5535401be76e2331d8cefc126f0e	1652614893000000	1653219693000000	1716291693000000	1810899693000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
353	\\x489b8f83291b32bf405f70b0398a8908d0f46fbe5781dc36136555661e3f6eaa8ed9becc1c47e466eb6c2d2af3d689bd8e56d6f465f8bb40288c8f2b601041db	1	0	\\x000000010000000000800003ab77fad13c11fbfd6154d2aa770c2fff9708eef245514408f6821b72156af8cbdccd925ed885c0676838510c9ba8493d9c68ebb7d0edf05fe016bb9e26d983a8987965b9693216d76320aaa147643b3435539a7461dd1bdea5716e844b1f249c16c955c6a89a3ec0df47e2f07069554ead0e3dae9e536bb725698db1ae1e99d5010001	\\x98ba40ab6d7717cfb96da56cb2c1e5e74c94978f7dbcf4376eb6eb3f34b3712428dc14265dd7b7a23a3f00d11d5100e7840fb3fecb7d772d335452985ce3750d	1658659893000000	1659264693000000	1722336693000000	1816944693000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
354	\\x4803e13d1f939d59c22e70d78c5db0d632af3cf37a466c10d3da257cd6d412e0213b95553a8ac32375aeff8f972eea59cf03a8f9cdddbc1c04e658fd51fe641a	1	0	\\x000000010000000000800003bb3d4920aad5ef518c93443925264559e227137515cb31f910af1feec7c4139afad0ec3fbc374491d134051d35ef9f7e641342603bad2d254f109df6aa8ad3a9e5b7fd98727fb7d94b177c174ea352080cf1120525661a2ab677824fb7b0a795a357c4d336e061fbbb97227b95708d50dcf808604f3ef3cf1653db13789e654d010001	\\x18a857b38a71a3dae6beb162a27d520881278e36d7373448384844e9de382c02313f64df94e48f0f36320bbbaa65a8aa1453f006dc5d2c32aadb13e092ba2202	1673772393000000	1674377193000000	1737449193000000	1832057193000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
355	\\x4933679ce9223de5fd2f27f929a9766cce06385413cfc7183620f4c0a2aa258a44c6b71a051703aa3fc51a359aea517e612f9f66ee2190c281e7431dc4881cb2	1	0	\\x000000010000000000800003c554350c3abb913bd279a625f4c7a83bb34d250f48220054c2f14941ca87da561ac9bd5cd47de395900e8d3608bb7248367dcaf6a6765f6990c56bdb9cb3e532ab8f9e268ac90e37a27eb8d9a233f2c0ca6046245622ceb5091bd16c2f8b0a518458f56fe2c73ce8f91d35117752fcd373d5350fd534a03c65b36e3fd3845319010001	\\x17470caba74147727a9ae182ce3d3ad66f4883050fb72942af85ad9576ae122b2cf60f6c15c37083962b88944e19cde207a0b16c22f54451e440c596666ce60d	1656241893000000	1656846693000000	1719918693000000	1814526693000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
356	\\x50bbad2c2f2d3082a3a1135fe594615d760919fcfed4201f68fc0ea9d4e3b1bb3b316681a5a4d3a560d71d24dcd9ce715eb1c96333439a85e8b9317995aad0d1	1	0	\\x000000010000000000800003aac2d655f9afc6db4f2f160b997bec9b0f1f942541bc9f191889f1341c4d7e316d160d52cb101e6966232dac9026485c71b79222b2d76a51cd0977dd2dfc745085440265fdd3d768fe335358223fa1a4d2be75cffa71765dcf1abf2c844dc78cd11237027f10aab3e4c491ff147f1fd41a04609f8141790a132421a314fac569010001	\\x792cd5d193566c4ced748a82eae920e73274163720493835c4cac1c000c3166bb2ce3ded6870765c2f65c85015716ee92b803f96657cac9b680f4a2df300ca05	1660473393000000	1661078193000000	1724150193000000	1818758193000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
357	\\x545b2c65dec4e41b47e29339fd1e30d34b26c12d5edf37de16b790109ea17da208e6f3742c7f334b28f454534bc2700c41af1af016a8b0341c80b95c16c74a21	1	0	\\x0000000100000000008000039a63fd1111143562cd86797b82048066121c14ce69d4293b02b34abf018293419f94f3014102a6f77db13bc72c3109dc09678f9162a89e35e72ac17b83d8153b46219d4f93c0619420dd85f767b840314ffed10d73045e87e6d04fc047b1e574ebfffbda2f21f706b19dbe2ab997bfd1485aa3984ec0d56131b4fa6c304d7455010001	\\x3f23e345cb2faedd7f03c9a3357be3ec129a97f255ce20c7a44187b18b7932ab507de9da1fa3b32962b99c97404c93a1b4ae7f743e12c1d0c92779730840450b	1652010393000000	1652615193000000	1715687193000000	1810295193000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
358	\\x54274f6af3235631d6fdb28430378703ac46278137d0a93d2141b50931e73b96a6b81673d0e7152b1144040418d97a77e5f6f4dcb106d61b50cb5e118a81c67a	1	0	\\x000000010000000000800003a906483665d1b8ec615dd99b656aeca3e8dea782fb48f4c3a32b2027936e83d42f67281367cf1c105911d5d465f8daf225d50d4809920c1a227c613ec0aa029d6b0def196dbfdaa448210b7d40e7313cddc5188d6ad6bf784f5f92c1b65b95237e97c06f7ea2fb1a1856b5008124fcce41273bf1b4a9037165bef5bc882a990f010001	\\xd3d583d719da64dae4b8622ed8855c5c54c5fbf4591de981318b322977521ac294f22c360be6d8ef03ed87bd0e1628a77b0486badbd5d80d9f8fd0fc56316603	1649592393000000	1650197193000000	1713269193000000	1807877193000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
359	\\x569f94a45650491896015e314f32ac04c88e409f9133c7da852704cf0f3fe59d2e7ae60af0ca89ae6e7b2374e2a6c6d58c9194ff1b52446ca413cce786dcc556	1	0	\\x000000010000000000800003adc22f9387c12f7bda4559fb10a9230ce662eb25b33327487190032bffcbe913eaa16d249d87ab50fd2686e6e2282ac2d15f1b829bd9cefc688c1993b3baeb6a8eb8716cc5f0b80131ad4d90c31eda6ea92bcc31edeed8f52448952867afb47547a9758a547b86eeeab24cc751f32e45a45d48caa0490902be86fe5060577633010001	\\x491073493a09103d5e861f7beee818363f07e6260f82cdf7ba46e50ced763344c932c4cd42bf6d44449f210f75b58be59496da4eaaf2a3fe8d0af4f040e9eb0a	1666518393000000	1667123193000000	1730195193000000	1824803193000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
360	\\x59b3f305790fd4978122368f29183843f7f3cfd076988f19560bccc598ec0589d92eafbdfb64080859c1aa4cc70a3122f9778770d6aac34e85e03e1bc77dd4f0	1	0	\\x000000010000000000800003c262320d1fdd4e57bd8397278bd910f12a1275c2eb2ee3b3cc4e81619ac6a63ffe89c68090e4a3dadfffd3858b631e399bc0fca86151926c9cd49c7aa884faa1f8cfa5fe2168ec3617abcc3ed91befc7038f0b69692760bcb42666f2c320ed701244e0c45b7be9f6ab43246410b165be3c74a3539d466a50eb22933f56f2b197010001	\\xa1fe6b869b88ea3b49733095b5ed9bb78a22379d415646af1bd5e5418932e2e44ab2c7c7d9c996f7f5096386ab672e1d9450a23828ce299a2a36d5eb1a22350b	1664100393000000	1664705193000000	1727777193000000	1822385193000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
361	\\x60330287e30a636a3a0111093ecce8719fdc608e1934662b56f434e6ab2c4d9d9e4520ae88a72f3d898c12a2c98b4472f9b51445c681b7bfd429a1a5e30961c5	1	0	\\x000000010000000000800003c6f0ee8a016565be64f4cc6f61b2916122bcf2c6c91b2b39a5c516bb38246bae5b9d67e4427ccafc703247eb7583fea9140332744d35daf4f427e0b5af80382a57094bc2a8f84788e653e818349d41f9a876100c349800680b87d2388055e51e016a40fc6e6eab4e89704a02f61434cc137dad3932fda49a0e783518302245eb010001	\\x03a1c054d9c4aff5dc00151251ba3485c141a90c3d0650e0b71f4d2e705c65281245763f72264b8012ba6b8810cffc211c65d808cbdb87b21fba71974c3a8c06	1662891393000000	1663496193000000	1726568193000000	1821176193000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
362	\\x61bf66b8b810ef1cf1aee14872ce9fa406161f4def4f9fe693c2cf92fe99171ee2eeb81e96d85c6369e5533688fba19e36f69443d3272d76d7f87154811d0421	1	0	\\x000000010000000000800003c1ec6b6b1cdb8ac7c82d2e63752bae8891a71875a144393ffeffaa8fc161a8c7418c78726218ced9304648e7f78a6e9526c833a2e09b726a1194d920baf1a4d23916c8530dd8854df38f4c1c3774bf7983afd789bec7fdbfe50910640054c29e72102e39776a6caf57963a9f2349d4c2decf8fff2c48a01d6434bfdbeac534cd010001	\\x080f52f80de7cfd4fde74d433288a0b604e078ad8f1f1b98600c106f671f676300553fd5fabd426ab110763beb605a0037f71dc0bb71e77dee21e7dbfd223209	1650196893000000	1650801693000000	1713873693000000	1808481693000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
363	\\x6697a6448f0879f82e9b83bf63177387d6be3384972d162f3cb76d42fb33f2769db3d6a96476c34345d142249842dcfc3561b2cce0cbc871f26a60c2ee4a948c	1	0	\\x000000010000000000800003f334364d4b182da3db7c8817db1fdbfd82cc0df7dfacb0bd328586c0b203547c3f5b3c5c4fded2cf59113b9c3d3962791f52ac5ccfd4909f06f882d187d3025e12804375e9bb0e9453252962bd27aefee6a27837cdaffc0d15f8794f429677ad529e1e8f8115e1deba739e5016f6a2b83e55b931a38511280b6fdb715dc6c2b5010001	\\x24f7fe328d2e5a1627e0e780cf967b7d961a55cf7baeac1faab1a6d1b8cdbe3d365556a6efd19f96cf28aec17625e39c78904fc267838c0a22f90349c183df07	1650801393000000	1651406193000000	1714478193000000	1809086193000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
364	\\x672b9a912b98d9fcd59254d4fc443d20cd9befac46a03a99a3544d7578a0df39efce9b469f73c8a7517c0e3a1d87c820db4f94b7ae70bc1234d658e1480e751b	1	0	\\x000000010000000000800003a57f4bb7a0dea8cf302a2a400c9c5b904917c9b0fe170a64be831e0862a733db379fa0dc656e074d7e998053ed26c9e27d1748d40064493135b9e14d23dc5b66f0bb3fe799cfb48a6000dd44b830ab0dcaa591bb11d5a6c23e6d6729a3b16b5f785899696919aaa10e6a23996da7d0665957a427862b46e88b66ba9a12fe6013010001	\\xe3c518a5780a8734f8dae02d4da4f01ef4e75913e708fd9e66c1170b9ecd54f89a40d2d25e58e091159da4f5a5c2b3a7476379bf9cc5cacdcf00cb706ea23f07	1653823893000000	1654428693000000	1717500693000000	1812108693000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
365	\\x690b725a2217de24b019478367d4a7ed2da1c5e6176c4223e9fabd173adb7a258bf857406ad8767eaf01ce27f36981befbfa2f4614d5c0ba0ce04e9914a6693c	1	0	\\x000000010000000000800003bd20a18e0698fef7d5c24e010105b76ce2c6e5734c3f052cf9abc02222ae24b82b46f5eb29ea1521c30b825e4cd32b6dcc7abd70f4f044000801296af32e8b7e8c2a4c79981d392b6e265c9a7f7068701e6ae8cfb0bb278e795960c4eaf65b51b60b3c28a1980cb28fc5a8e431f63f0f0842ead0992102c616669a6bad2d5591010001	\\x68a89e40c0f4125e0d5d26ecf56a132e67a5de4f06842cedb0355334549da03285ce258dbd03d24c1bce9dbfbf151583a47242e9acc2359c3cb14683324c6807	1677399393000000	1678004193000000	1741076193000000	1835684193000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
366	\\x6bab12f39cd122aa1dbb9d4f65d40e9578464cec235703155bfd32b8e1fdfbe833a9dd1444d9deda1a91780e63efce41cd50312a9e87265b9a80c43fdda2ed50	1	0	\\x000000010000000000800003bb7ecfc328a12060553cafe7f2be67ad9624ccac43eb4efd3f41e2ebed8fe1caaee32f132120ce2725809930bb8a10798e97e93b5b3ed7958ebe77e27be7beb704c45f85a5dbd334de6f78f6661231e895fed900a6bb7c4582ea6261ee091514d46bb2b529225de4b93e1ea61fe4bcac159c59f833c8a8dfa28fb0fa23c44f25010001	\\xeff59ae25e9c24072b8431f6e6f40f830d6238e5d87153bfacfe9a0012d95cdab7ab220cb72289ede7b77ad41e24bc6a04dfd4a03426cf0e26614f1c2dbe6903	1678003893000000	1678608693000000	1741680693000000	1836288693000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
367	\\x6ca727811f8666323bcc125acb241e78c2712af236990bd3f074a93ef10a07753b07e2a0f5079fec9aee5ccfbb6980ed822d8a988c9c24fb1df07073d34ee1fa	1	0	\\x000000010000000000800003b99279beaf43e33e52579871d38bf1549ed05c171e39b758b3b4898b0732ea7f4ecadf55a8912a423ec6ebefe5f12e13c8d2148a05fd54e22855bc5927960cb039e9d1806f231e5f92fc140a31130122b82553a57257961fd1bfa39f2bc49cf5c244dde1b2d7eef387aba94c1f2bdfc5631978596dd47e064a5f17866ab0f1a5010001	\\x613cb5814437ce0d2d53c064a68e74ecda037b30da921d012cd49aa901e6059c578f6c249d109e90d126a55c3e8e60fb631a6a0853625c9e6affa9d8af41c500	1655032893000000	1655637693000000	1718709693000000	1813317693000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
368	\\x6dd33216dfe4d03a0a23208c2b7fb7cecbe3d98029399691b5f3f0ee6092f5c3504a6e992d522b200a18a9e7acd433e8eb35c516154dd425c6b271393abe458f	1	0	\\x000000010000000000800003bfc556c4e820aecf4e4abae254cc47c6e4a49adbeed869faa4e85616f6b6360430ed2668ed9ef30b616a3d6a736bcfeffd8d070f7b488c3ae4e6b043e23648baa2adeebb3deb4976e5b4e6745abfcea441a920c1a06671e9da0771a9bbbc0db233d38e7975d673a807a744d3816885e92e0e16b8766857366e693b4090e515d1010001	\\xb70ff3b5b5aa45881e877d036ea70a134679dde73c87ba3fb1eb1f1fd479a326f7cedf5ad4634cf43cff6d24cde398be68a40e6c68b5711de4e27f3a5cab3a0e	1667727393000000	1668332193000000	1731404193000000	1826012193000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
369	\\x6e4fb6d7861db9f9ac6ada75e994904ec572e3175d6efa992625aafcbcbd56cd151fb3a2f0ff26e4df4ba617691084fc866e44981258e6a033b4a98fb070f5c6	1	0	\\x000000010000000000800003d5f6a6ad7be93af6ca3c2cdfdd321b20fb1e7705d90e2f2260c119031346c40e188a1cd1e227a7abe29cfd630bc9d1c3e8230602bd12cf3a78cf32d728c18c37fbcb0cc0b09caf44e4a45bf4b02d339457789f9c55bbb4cffd510cd283ee009a00eff14e12e930d805492e08ad267899347fa83efbc3aba7953586606d717705010001	\\xd21d0b8b492e8386b6e10dde6c1625bd97aeef44028cb6355681679e0a32b0fa9f9ee5139d35edb99f6178efdf46b46d0178838657563da54e690d8106c2950f	1671354393000000	1671959193000000	1735031193000000	1829639193000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
370	\\x78b76b260366cc8982d5f2737ca5fb7d00dbff0b4b8649979a4259f63c51472607ca07b9221e82c19c0f99ef2ec2780015f95a941978fd589baa8c376a1201e7	1	0	\\x000000010000000000800003e0b0db63218e05c0665d6e7c2ef4dbcf0f4bef9ddeb71702ebd3c183f13acb868e1dc2c810716d35e577b57479b5921ef84e7392edf7d635c56f55d2b24386de8166591d1740e18bc7a2d2eebbad46000844dd13aaa7f89f65ff86bd398fd14e77af03a9ad9a4ce2cbeb625b0b00e10fdeb2964eb1ffe1aa3497b5147ee402d5010001	\\x27a8575b6dc15dd40001490f313e8d22162e3f03600fd0751e04e67b21a5851309a9a79bcac9054db21ab4e81f76f4fcc0e45055d446ac35661d003b6bcddf07	1679817393000000	1680422193000000	1743494193000000	1838102193000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
371	\\x7db723feea956af05e7e20c32833d17e8b1b7c1bb9249b12e09d5f053677dd3a081cdf0fd1702a2691192f2db4b1f348ac26b7fd2261866c736678b648cfd3fd	1	0	\\x000000010000000000800003fd4e78884ce7e681833251306ca6b7cf146c8766ea530457c280e478929e2f91a7b7a2df56201e5c92dfad112f89392993ad0e9c4c56799cd92e79b223a10797d54a71eebfddac078ddf98dd54fbf0c08cdc6ccdab6c539acb1b63644833daac4ba3262e0aaa6709bc2c609fee9909d9c073fba5d2d4f8c5cefca06924ccdb0b010001	\\xfa92024dcc2f0bace4b78327bbf5eeb3dd2a8b4e2b41440a9c97d71c797a9fba6774b486708cee9727fc78396e5a49ace4ebc72b3ea3e278060f2cb13fbf6408	1671958893000000	1672563693000000	1735635693000000	1830243693000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
372	\\x7f1bde002e60fa800eeaad9fbcb9936c020746c6324b3c25afffaf88b15ba2931613850196df37c6737701d59b0ddc683bd6b73c252cb2add2d13dde877fb116	1	0	\\x000000010000000000800003aab1063c836fce158def3c185ba6d2f2f85d5e20f11b76a9f1169240197ec25f33c9a8af0044fe7bbe3df1a6d7bb98a9e7ad15a6ed07a1f3d515767358de25a72812e7e273e0fcd9b86372a1e343eb30eeeaa0b308dcc4f7e99aab667931bb3aad4c15152275be49d824838cb8ac79b077171aee47ef79ce2f0489337b8b2b11010001	\\x1dce04b307cc73eac7cbdec2d17d881e5be522fbe4863e4fd2564497a7e4e3185ad6705ca28186430a4430f2ade759f224e8b5e774c944b8638c6c0aaf57760c	1676190393000000	1676795193000000	1739867193000000	1834475193000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
373	\\x7f971ad9a36b8c42ecd19b4450deaf9b13acb28e47e7ba07f08822752f17f1730b6579542a3be279c04c8be7532953174d33339f7a63ded162ae0730178bd71d	1	0	\\x0000000100000000008000039c359553014c07fd046d6d6a00798cce262078228bee92718ca1edd78c13d6c67012c7f4e0123277a05d8efeb539c51c900cfa4dd2ebfcb7bd5702df0b6ae7b940fcd92c20b819e3b5a8007ac51eba33980ef0bcd1d88b12c9831ee69721eecba46df22a3a4a1c0de7b312e8c09932bfb5b19935b6241fdb15764eb59bda3157010001	\\x46d09784c3c61338d91c05329e43243d7e64a5accfdb21ef12cead863be445e0114b4184bfcf041771cdfff528f70b83d1eca9dd225802e7843715b077a20b02	1671354393000000	1671959193000000	1735031193000000	1829639193000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
374	\\x83f3b92fcf9cf70722347f5a8caf2d8cf6e8a69aec7e5168ed6f035e73c8312e2433384946d6b2a271710927dc6193e2ac6fbf3676d6c1621ccdf953e8b67c04	1	0	\\x000000010000000000800003dddeaeb639a463f5bb224fb48ff1a4f1ddf651d8b73724e5b75886233c486e7cfb3f655b3cf689890f2a24fcd4d27ce36c26991cb767cde43928e16d0ec4c7538921e607d658da28bd6d5fb2615ad83dbe9628cbc5b66e239ce032b7c6aee521a20bb02f6b6690715d7bb111507377905a056932784a44a92b237631c2fc4dd9010001	\\x5a23bb0ee1349e540cb525e82d95244f8216a919bd6ad25e2726113d1e043158381ab5844ab25cc166704464e9d3c010a5a9a88208c7f849850106f15e941202	1672563393000000	1673168193000000	1736240193000000	1830848193000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
375	\\x8547572d45d3a539b52d08612aa61375ad4f1ceaad2c99e581e29aeb61dced649ebd5728ee9b0574324979515dbc5152bcca2fbc5e9a926e7b883473e7952e2b	1	0	\\x000000010000000000800003b00a38684fc1301ddd2394a73256a9f1abdeb5a947be451bc0e4b0c84486a27c83569effc728ccf95c3b9f337f05e60fd7f0935c3d60a877a00d5f78ec89232d2d81cbced8e7a62bc4ca0bf1b919ef4bc56b51800127fd76d0457d0a54dfd5a386c09e943124b602c009076026a65b57401dfd7ae2a15a31d829cb23d10cabdf010001	\\xcbd505ad72367ef44952132707140c31e3f3646c932272cdb4ad088b9f31781e79f754559e20271216bfc936fb558e435b8bbb0479b78668f24bad65a719ce0c	1669540893000000	1670145693000000	1733217693000000	1827825693000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
376	\\x87435a2d191f42999d1c9affbba80563586730face21283d505969b7cf44278d84413cec769b523702557da4b41b20e89b06320142345d54be7d2e9f8dcd596b	1	0	\\x000000010000000000800003c32e1f5b37db73ed59b91f1f863900eed4f002e5018b69f202e5cc2c1acddefe38ad040821b25814e4bea86c91f74896183e8bd839f3eee13bb5a23f9869aee4dd0b628e8160564a2a4934b44075b10b621644b4d28f11a36836276cc0101e0a636a4904b49a8330db354580d0e7d6baecf97a5faac266e64cee3f69d4806ef7010001	\\x3a6772a8ec3d1d3311d032b53f466bf21464f4af3b3d871fcf2abf02fd5930a4fb62e038ffe9f0b1c9bf274ada36debb23ee2d7d6e4ee3fcf5689d6fd3614607	1672563393000000	1673168193000000	1736240193000000	1830848193000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
377	\\x88eb17c0bce02afd7e46427bb20d5e2407c70440e0bdcb67dc708bdcc68ee0df328cf7d6b7d27f41da6bb7d7ab449b22de53b76089f80373be3c9b03efc34614	1	0	\\x000000010000000000800003b8dfb0e046c0935c79155b93b490874f9c9d69264d44124ad7fdd9c7f6ab252e7303738e636b69e36ad5552376e5a010707067da832db0f24a5bbadc75059edbc82a9e0b24b30a22537317cb745c06fcc5ddd96902c3dcd0bd0275c9dc3ccaf9f8e310b2d1e8e39f08b62b4da6a8bc41d10c6f7babd2adc0f0ff21d623c26ccb010001	\\x80f3503d74fb9a9c0b9dabca83b9723f6c681622206877b84d29068db27e5ce4e866d335a2dff8ce636fccc3d0dc9139da80d9e11c9f8f38d85eb75e1e33bd05	1655637393000000	1656242193000000	1719314193000000	1813922193000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
378	\\x8ad7d440d736695df4760e376f0137a7e75587b41e7f3c9a11ffc148152a5c2c3fe4cca198a2acae03a1d5d65c205a153c9667aece91c15fa91d468097d337c5	1	0	\\x000000010000000000800003bc0a9dbd750b702b5a781c1a2d32e6b234dfb1c102e864c178f7f481a5f25fd41b802c7f38393161de0d2a2ac4ff8bddd4913be1e7679d759ecbf1ef1fd6889e710d6f8f381656d6ce48cd0092a981b2ca112a8b0732c2542edcb88a8be30c7fa8f74aa409794a7cb922201eaf59a1c8c6c9688f4949e3e036c4c558de3213a1010001	\\x9b6e72bca0d670d64b2e44c93e04486ada99b9849804b87fc64230d439e7e3999c21e0d5f58128e568d48b60faf67687934cfbbd5cde40c208d09d3e534b8906	1679817393000000	1680422193000000	1743494193000000	1838102193000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
379	\\x968fa1fd49ab4aa5d146c1c2650ba825d2f5d17d38a1daee1e7ab415fb230daac129fd8c485f594c7865aa3098ee14b23e1aa35fd8f44f0de7e3e1110a22fd8a	1	0	\\x000000010000000000800003e40f1bd30c0fbe360c585bb0ddc2e4e157fbe04f77f18f35223a1cc9514ea0e83c32b67ffe8f7a0f3cfeb501baad2d2151447815f6ef7aa8a6d138318d1d9347d2a0f515ebd561cc416d4c7c13c5f47640c22d0b8948a3b7a4af19efcb4f2dca63afee83d5a98c1fb25f5cca81cb2e902d174a7bc9ac2b3297cc1d88aa49a455010001	\\xd70b6f523c89442a5a630cf50edb6d3f5a4e3155a3cb3b5681cc56b9bce71d6c8af63eb272929a1479bbea861135ed90f4eb0c36429add2dd37103b263184c00	1673167893000000	1673772693000000	1736844693000000	1831452693000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
380	\\x98631d70b59a8ff258260152cfe921aa4ebcf5d2d9934b886b1eebe6510c74a34dfad5e2621b36eba84c847ef26a9d99c5bdcd9ca297c5356b388467d6adac95	1	0	\\x000000010000000000800003b765f6da666a31c6489de8c3eec0fd66e052ad2ca6572c2bf209a0c8530679d385fe30213f1384c1d34917c5e6e08b236d72ec105b80219bf87f4fe95fca078ea81060334575b55f5c59bbcb46662c6492674c2351f2005361e749f7cdb661e9a29962367fc4fca0efe220fc632acc481c78ad606fdccb7a5aaac6355dd48803010001	\\x56d3ab1819ce5f60eec84b07fb6803db2e9d100fa3690083305a91854106fa0da38dd5b2b1c9ef4b0bf27d09fbe973d42dc5497a67c12f79c4e865a6e74f1806	1675585893000000	1676190693000000	1739262693000000	1833870693000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
381	\\x989b617d205de7c0a88d95e628627d96675c1447916f0086e1bd8134636bc5e49a95d5b4bb31244f3270274ce5d5c148ee670aef1107267c6dde884fceb1ec45	1	0	\\x000000010000000000800003aa673c38a5c1b04773112aff804cc9e6abb3ef7e88835203f7115d12bb4d41f370a93f05cf62c2b35e8bb8a9984eba52bd8a08284263501e6c689e9df428667a2905c168e5f7a53cf8a93a8dae606be304b28a678c51f722f19dfae2b026b1324813c17b6b5503db2a3503debc60cad8186934ec276f7a90f7a650180c442285010001	\\x530ac4aa82e8be71b1a873b8bd479f67e87c41bb9128b94b4a9b6caf249d873a84254e7f7b65d18ba68587357fce9c69521169a5d1c713c41c46dd7885370403	1670749893000000	1671354693000000	1734426693000000	1829034693000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
382	\\x9be3f91fd3cf0b8565089f69ba590b4c143f67a63b4aec30fa02c553583ae503236518e0d1bda3ed8379bcd09197e8b74178c8faabe82683aa63b669305a7a77	1	0	\\x000000010000000000800003ad0ad65b32b44d0f9a74bd1b52aca0e9aa3779f33cf06cbe81f4c77d455774a3062e05dc56e383821b897a065c3947b1deffb574d59732c1bc64f048908401bb5a31b61a18d8a0f2392e0578bd1cece9f06eb3984bbef71be1942c1947d3fa1f5244a63b66cb83c5facbd239f80b95de1f8a3fe0c5aa7ebdebf08f358193544d010001	\\x1dc2cd02ffb72298c5f86430fbe261cf6cc7890f40961983ac071ac3c17475b67abb9d965a7c1c62919bf4e044ae9cec2e6b85bcb78291be7e0db49b7d98020d	1676794893000000	1677399693000000	1740471693000000	1835079693000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
383	\\x9c43d916876dae020c4de655fb8d74b301724dd0055fa3adc0d0ec8090446a15ce801be0d83ad45684093f0cc584ae3a8b8721a7e429e3c6e0dc3f5ab33a0e06	1	0	\\x000000010000000000800003ca10469c9b6464544ce3e66ec26d568dc9017ca99003b018b47c6a25e82d01604695b54123979d2079ad98003f62d96646ee65b3b62d06afa86fea19c4fa772274ae4468a31e67508233f080f547060b719910d0d3d5ee63978f910c823daa221f88742f747b5060f1daccaf2a0cd45e9b95334498f19fcc29ccec67967533df010001	\\x7ec30aaf54ee6d4640520b87bba6faaa4c5f3c62d3f1a8cc28ecd6dd69151ece3c8451f0323d155c60423dfca6b97c846819a7d74f39e92dfe745a96042bf10e	1673772393000000	1674377193000000	1737449193000000	1832057193000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
384	\\x9e1f2f2957ed0adc55443485718aca3b40c7ffd0637dd0d7dc117ae5d9f186f03737891c7314cc6410975b669e45cad32010562e058366dcdafe4927f84d32a9	1	0	\\x000000010000000000800003d6fd262e42d6a3a896abda7ffc1dbb5e5e9153d6fdd94e8546052e5b048f0929016bffa4c6d16197b9471fe647a85d236be968002095da9e37c691ec3483df6beb2dac6a66b1ce97e1e704ba8415d27a423a7b58dc3c0165cc4b3a4716e7c90d4216289631f3bb3fa53ca705319a795e818581b7dc5d9cee7c62a0ca8f511095010001	\\x2ca44aa1611a005ce3dbc017ef039ed3e1a2a6a20a3f7dd16645c4205cb450c464e1ab41ac9e1ded836f2fad134e1ea6430f8aa56614b5819b8f406c45a4cd07	1674981393000000	1675586193000000	1738658193000000	1833266193000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
385	\\x9f9bb6f46f75e14508776c0eb654fcc4e0701ecb9260aa757dd568984343244b5593ccd43687a02b7eb507cad054e92a0db723cee5726ef49ad9f581836b6850	1	0	\\x000000010000000000800003adcb46337f8045d48cc127ccf55c6cec695f927e4d6a4d030cad60793622446cc6895c487b27fa864a1ee3303b10766377aeb261597df90390d70a3f983fa5df07a846d88f8dfbc81193e3fc57ff390b988caca062de9fbafd7f84bd762736bebdd01ca3760db850140ea261acdba14e3b42f2af8a627dee8be8875ab6789d05010001	\\x354d6a4ebb7ed3847dab2a0a16e59bf6d938f2acb67df084cf7d59437c25c7f407afe4b62576661f43f51d11a2ce72a96b9df838894be98f25d5a8f0670fa009	1662891393000000	1663496193000000	1726568193000000	1821176193000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
386	\\xa0bf308a82f0aa7f49f3f3d1c7608955e0468961ce6c72d677c67c246160b2f365a06832a58d2fa56dd356b27d4a3f1a49e7194c90999c178c26749ab8d4be3b	1	0	\\x000000010000000000800003f13058f553e463e259296a607285f2755cafc49bd818e43db384fcb0744f83f601934ed4d06899e3c6ba1680746cc76360e9dd0b08be6434e6d4497a8726a51d1d36f7ad0bb7e73cbf4702a793afe48e1c3550d9f73717198c2adb765f085eb0049e9200754af73ccbd89a4e5e3622e82446e24ca2668fa5aef2e2b87cf88867010001	\\x4162f6e797293ac597c3497531664f4b0b71aa39ed23ab499c1e17ef8cef30f863d59cc96ca01d40951f5c92070a267c08fe1fbbb39baff4e1a9944f3c684800	1658055393000000	1658660193000000	1721732193000000	1816340193000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
387	\\xa10fb3e99b05b8384566723b47806cf7444f331da345243aa1502851725cf1c98fbf1475756dd0f370677596731f25de2be1d05cb5e178dd45cb1ef37cfaca8a	1	0	\\x000000010000000000800003a992ec3f1d1f484a470462de54ea33ea55b84617edf2bb59b9654f52a0eb66aa8df9568cd5110441ca431d291237ecc5a469838bce2939f49b74b0d06f77d18650f612925eb1164b59a8a92b01dc1b6895d0b4458aedc3d4b5644ec50e45b137dfb479e29b5a64c27d1b48df273c1046d91db5e3d549716423bf191603eb6341010001	\\x0de82d38ac5ee41703708739c1901c35bbd4b67da8c50861fbd22ae1ed3c05293e28854de5a2651dd584b55dda37aa12941596c672c8e01d4a534bc73ba0b002	1669540893000000	1670145693000000	1733217693000000	1827825693000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
388	\\xa2dbafced246012ce063b38c45500e9e08f55f52161a10fd06cd3d87ab6e7342689a9e2f5f258e8b5ed67eabcec54eb08f491b62276bdd0e14f90ab968411d4f	1	0	\\x000000010000000000800003a875be9bfef70991c4b32936fa8b2e93d46a35aa2057ec8ff4c0f1cb11b261701bdfd5943aa6bd1fcb281144eaa6f6a446d61ff27b00645bed8fd46a247dd2d80098744ea59c205b9f17cf11a5d7e03241b560b1aa4db04d582dc95b19e5a1e3d99fc42e9e467b7a0c87c0f53f6fa717e586c9c275816b4a2d5012f8f0690c55010001	\\xc34594eaa2967f581dd05a20f6e7b47d64b39d4d5462a61e5f8c5d3f03f45bba8c3342060e358e46ace81ae4b95a8180fad28aefcddde1d0b7557a05ff568205	1649592393000000	1650197193000000	1713269193000000	1807877193000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
389	\\xa26f11a4bd55419d1134912e31727da221699de1fcd982f7d112f61e16c404e806a218e0d15b0f6d70c8ea5e9b620bf775a52f89417cea857e988624eb83772a	1	0	\\x000000010000000000800003d7e21daf0467270f08834a391b9284472e4ad6144ae59955f3270b4894bf65f7e5de3a827364285b06ac0d0beb664d7bd1f6e754656705d83ab78ba97215df5193bf6b1506a4d175d183e725d7d89d8f7b7e6cfe6458b3e76a3c2443f26f7287274443daf2673a5dc89c1a8973ef104f709276f117e5732bc8b18a2943728be9010001	\\x8d17fe90e17a1159341f08fa8a6efc08ca719466db1a13c6142f73402294b2ab6a0f7c3410452009d79bc3de1b27fa2995622fa5de1540a3af763f59574d8a08	1652614893000000	1653219693000000	1716291693000000	1810899693000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
390	\\xa48fbb56e748b6908660d4e2a1ccedf0d449128cde588577c8579f6d2f8bbbb824c68a823b0f95b7a20eb3cde68e5a23578fe8ea95813e1837ed313d3b1f9dae	1	0	\\x000000010000000000800003d54f21ec61f0417403fb7520dfe05bc294432016dd7c3ce5e83df6bfcd6426d1756ef1187b1ca416d4ae86a07fab2dd3329f7cf3c1bbe7b1d6bef01d326575fbc7caa3cd82a77f50e2eda17c27b6aac8f05fb5824d378abd245568ea6060f3557b0552a9cb627ba4761aae80fc10b2e5c5649e9f2fbfeda4ffd183c73e8ff197010001	\\xcb86f7d274f082983c570da0342b9aab44aa7c9aa0a19bea2210bcf6cc1c631dde510b6e4cb0f59ac1e6f7826af2011029cf80295ecd1d3060c127c715159b09	1662891393000000	1663496193000000	1726568193000000	1821176193000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
391	\\xa4c7d736cc5f3ae9ea1b54a99ea3cb0b9aa80d62c2b72ac2ee6a9774eff3eeb64c8b60bfab1540dd2d0b974da111caf4968dc7ae0c06a8bbd4f1fdf3ed537c05	1	0	\\x000000010000000000800003f134314d7148cafe9b59579d1301dc5e237d4d784831ec6479e0daea4dfb7017fa8e3173da444db015116b18475c76e0d8641138941f8d151fc1fb007f85a52f605704e4ccb0e858143ea5d8bc729c460bd6739ff580df5fc0753b33b965468a6a3e9df35bd89ffc125812debbffcf36847041c2463420882677d6aacedda22d010001	\\x51fb929eeb917e63d93ac408a2ac4eda403e09683507bcb04304e2097010941310f1ebcfdbe62244b8f3ae937e1d7d9f97ee019f6d9b855f8abe0cfe19f5170f	1656846393000000	1657451193000000	1720523193000000	1815131193000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
392	\\xa77797f122f87a5fd0cdfa3ef85760ff90451d142edabcf743e765716924bf2d36c77912be7dbec2acc46597d1447f3acb88e675e690bf28659068ef201376cd	1	0	\\x000000010000000000800003c15b0c7ebe59533a25ea4a1319b684eca2e5c3c4232eb95211bb4b36f97661bd24958332317bea4aa971acd9cda1d7b86189f6cc013627d8f2cd2def7d348fb8da291ed43de29beacebed5c80c7c930af13dfbd761151fb634e54f61d3146e7d0f7bc5c8e99820557043f81790d7a6150c4e8bf0e0055d5a04a21adfdc7b8e15010001	\\xf540decaf4f02bda76024a570a890279d44ed79a82f714cdd35f7dd13604f2ed0cee652b09a9ff1139924f40a580322cf15ba8fc0ce23fe4232ed46b58c9b706	1654428393000000	1655033193000000	1718105193000000	1812713193000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
393	\\xaa474f522c080929d005a6f9e5f6e3ccc4e139c77c5f7ea23cbbaa65f85ace551d0a68f74aac1444123c9a09daba7a71a00ef6162bf52ee9dd96ce660f14efef	1	0	\\x000000010000000000800003abee6045126f057ea3fe779a103b041c865950520de88c6e2f61b44f92c9789a4157ec84ef5661a66b3f924e3316d5ccad916555ec8fd3b7fc416f0600a407e03e7e6cea97f3153147ae09517b25bfa7c7089471522e8acd85b3d60320e899bc190fa95e6c8a934112dc0f982ef68a3d211741f81d9e3816f1471f9782bfb275010001	\\x530d61a32d0f38dc7c526b1b19b76427f2ba68df5fc0373e51ec334494e517fd63a42550a5da199d0906c7f6d44037a11f0e76407515243725fc793044f7c00c	1662286893000000	1662891693000000	1725963693000000	1820571693000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
394	\\xab73e7db7e0f54747e16ceb4124973bd694b5abf2faecc8b367a32728abbf2ff4ac0aa6d3dc4c6d512de0174e8a4404b409d9c1e46c2c5ce61bddef913aeb5d0	1	0	\\x000000010000000000800003b78313fab121ecff1ac6c39b713ec6020ab4b704e9ab3fe9a82586d73a417e1ba42c2cc41428a3009769b03c50585a0c4c0a60ba8c3b4320a867ad0ffe89a3bd92f8ae31c71d2990d77de0d3f1afb49805334465d18b117ae17810e6fcb932120ee39735d16e91efe54df4649ced8361a21907410e75c6ac566909d637a8e22d010001	\\x921c7308ce5121eb5b0b56085dcf24a717834a631a40a4307b4273c303ad9f47000cae224dfdbba4d9ae550f1439c8cd1723b0d76b7f5c1e4090ae9f06c63b0d	1676190393000000	1676795193000000	1739867193000000	1834475193000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
395	\\xac7bf40c42c2a71cce17d34476decf4f202cb8596e5e97dd760562870eaaf7574365607e8f3b77846360b770f02aa58fc1338de4432a498060f6e9a76b2744e8	1	0	\\x000000010000000000800003c30cf00ea85dec4e8778eb50852b133b379600ac61328c29f97bf7bc911f96051127548922a0fd68c6907b299b9a9d6eee0ec7ad827a6250d4ab375a0b4f71dc085fe80a6968d2d8317ee2599eb59902030cf1e96a2052e7ff89df48e18609ff61adfa1a2b24267464ed43a8a1e96144412545b41a4137242fa571c8d48b5bb3010001	\\x31d57e933b1665c811214fde6824763868ec6c967cc366aab0bcc16b1e90508825f528b5be5ed20a0ec07b3a0cf7254ad668bbb285d44b57b50051d25d7bc402	1656846393000000	1657451193000000	1720523193000000	1815131193000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
396	\\xacd7adc03d236bd9a02c9385d5dbc470884727f014e67d3ba1a16350ef51a6ba73ece5489861921841da52f6b788d615aac0d00eddf950337bf15d98fc11cc98	1	0	\\x00000001000000000080000394a0c1ac4b075cc2f25c67d41668cc20dce4d3c9656328ee7f05cd10e4a74d8727ce6adbaed4c9956c51f3fe83c31e1fb64d8a83511e64b5522099550ce61afdaac5b7a3e4a620f09b1e48b664696166874a4dbb299485135164f9a174ee390129d4230ace36f592a0f4dbf535ff62c761c388a813605d6d28f9582c9f5fc477010001	\\x95700a1a8bd5858fd1d29ed54203d8970b76b4fca639fbcd0feff9c57ee5c3664d73fc72f95c1cbf4fb28b11c6e6b2834431a2bae6e22ce1921225718b54be0e	1663495893000000	1664100693000000	1727172693000000	1821780693000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
397	\\xae4f0d02f9650818f76d24437916536ba2064ab4dd20c65dbc6208b62f88407ed9df5bec52687b35a784ce68eac9c4b95072b636aa3e73bb188681c7d6b55fbd	1	0	\\x000000010000000000800003a8be3d1dd9fe0a23ddd054374151e1a189b77595231ecb66d7c16fccbcb5f97f726dee6ec65f48ffb0147e6bac66844ade45c09c61c538e1a0db799b6d1581319cf0b30e6a8711056c834b9fcfa97f352c3c01eaf7663efcd560d9a874c13d4e26ffddaa8c39a7ed17111d212016cf0b9ae1a99935677dabd7053d5063101e51010001	\\xb2a5d7460df9c3018772f62aafe9d2d76d6c8c89b17297b2e3b4288be0251391fb2d94a1631d57bad6e0b79ba66cdf3a89be9124d70751f01095bf19dc604b08	1667727393000000	1668332193000000	1731404193000000	1826012193000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
398	\\xb03b93219c721924e25626e73ca411db755623f0bc78944fe91cda990280f36a61a45308a1a520ffc4e4cf0c842939f510ccb3f9da49f1c725264ed78642cda1	1	0	\\x000000010000000000800003b6af961c5ed841c827a4abb9e0afe3a080c95cd6200eb43292ae077528e97359bd1ecaf7dce6c36be062e0deddad627d22cc4307f499621762b7da27cb5e95bed4ef808c45a97890bf841b68abeb7ad498c54c42e1c300fd80ce3547b1eee58f3c9f14fa3cc872c87a1108f05a119aac9788406b2ac6affb3a4817b20d55c1cf010001	\\xaabb9867dbd6c6ff2bb802b62ececf16fe5e79287cbe2126da8cdf33bd7626d00f2bd2e42c5b8873363b9e61165ddde43f493eb9b2e0b3e6c87c4cc881eebc04	1677399393000000	1678004193000000	1741076193000000	1835684193000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
399	\\xb0d3dd2a786bd8757300cf7747d164d178a020eea0024933e9bab8827a9fa77c84461b9ed129bcf75e0f875c2eb922e1165610bd094c7553472f3eff6599486e	1	0	\\x000000010000000000800003d0113afe2287d791c4f1087ffdd2a38e4bbcb40039b61d7cca1927beec4442b076fab30eb01d6651eb8d07d0bd4004c93f7a442bbeac270969ee832f91868bcde53b0950050998a85135216575ad83eaf3537b90576ac37a85e7c65de5a2a77cfc517ffdacdebd312eac2972583823830b9486aed032599d27ab48e4f6ccd5e3010001	\\xfd2641c22e3962d6f0da6d9c47f37395656ff4897755e76d1eb569684c8d0857c17ea1339c7fe7099cee0cb46e6ae5ea79050142d772ae186642a38f4bd9bd05	1669540893000000	1670145693000000	1733217693000000	1827825693000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
400	\\xb1c728dbdbcb652d7fe1eff906c4347556752fe59c838fb3d0f7b49e777f0d35766dd68b8ab5049d2037142a382752edb64c1d70366273cdec54839298bc450e	1	0	\\x000000010000000000800003ddfb2ee8fa0c3675c5f6f00727667d456a0ff72b7e305602d06039abf2f9e0b9d474e6e32ac4028c7f3b855d16f77e2895ca166f9234af4cde0485930ed3db851fa6422ef50df8fc7b8ad3fe6ac9594ca4203532cf9583a9831bb24a6a97d9285e5384734a7933d63773bad51ceb06e6aea5d908eababb9ffae1feedcc94ba9d010001	\\xbc80e162625f77638ff8af5b00aa5b0d8c8735d744dee56208f31be6e0745e86b0b50f54f4b959fe6d33c0b6d8d650e0a35285df7100bb5cf0adae0b1924e907	1665913893000000	1666518693000000	1729590693000000	1824198693000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
401	\\xb277e6cdb2c8ea9165771b45cdfb8c4a90339994cc36703045cbc394407136342a3590db313fbdab69d9ec000ff9a656f570b7a1f5081b3c745aad562831bed1	1	0	\\x000000010000000000800003b9072fd05c919e85d2507dc6a47c8a779ea480a5485b101be93615c921b9c58a3a2e3ef4e9ab854469e1b722d02c2f88d2773f729ab849c6c9ed95987cb5c3b90661efc313831fa98e768bc7d4ea6c3aa147a2c16ab146f2fc6cb2648333bfb448c3663d24dfe6e88e6a65f94104045bbc5883fb66fac7f2436a31008c56a537010001	\\xc093212063b1779cecbb685abee8ab16d2880f0aab333e5415aa7c6dbe33c5a0a6a6e06909ca2c1bab00d0c85707f3e78cbc5870d04ea738ee56d7f57e59a303	1660473393000000	1661078193000000	1724150193000000	1818758193000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
402	\\xb4bf1796a65fa07a530badf614567bc34d683c88290e6eb842ded516aa9a3513f609b1508bbe0862aa63d59ee68303da4d3ad57b8649c9bc4b5d6748d7d62e3a	1	0	\\x000000010000000000800003e75a41270934b59effda74c5020fb4381973d4d7efbdbb48f94ed1af0a3c87b322af30060694ea838a7334a024195b55b217c970f3ea0625d776a7084976e4eab2dc062d276e6c086552dd4126b9a3620ff0f715e8959f65a3935982965f02b52e88b9c03c5ff4e37685484994b3890c82edbb75d4a6365cc8e5e12466172ced010001	\\xf5501f9027efe62cdcfb5975bc0e890cb32c37ab4394cdfd6025b322c41cfb72ff86875c0fe0843a7bf5ba5477b58923f7339769502af8f6565a731f8d109905	1652614893000000	1653219693000000	1716291693000000	1810899693000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
403	\\xb44f25377e91a08ce1e6a8a0875a623b39639440c71dd4bc380195268f0d6c476ef0ad30696c17a6bc4da9ac2a82aaeba7822ca46224e2fbf4e6890811a3ff5f	1	0	\\x000000010000000000800003af3150ea6297840e2be5b580cc97f9507daf085160ff977ef0ec2542e99ef6c3d79b79ba0ecf57eb515cb8ccaa31bc7886325efb1b4e943260245d1bc47129fd85e1228bc047fe11ec61b00cf494583da080c23c76421f7fa56fd3d7405459447419d3076bb6d8157b85157a9f3ccbab212ce5373c842b16822206f11ffd80cd010001	\\xd779f704a80cb0d58010b70f2756cee3d48d3a04cac58d04547638f133d4de8d7586d5f9098d46748c90558956726e6c80a706fe075d3a246e40656dbfb2e508	1652010393000000	1652615193000000	1715687193000000	1810295193000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
404	\\xb5374076d832f67a2cbdf4ecc0519b989427f4581322769759205d2517f23d37a7cc0116a75a9547ba474956dc5cd6e0397b90be0b5bfbac4bfd3bc5a1a26640	1	0	\\x0000000100000000008000039f249ceb461c5b916dcc565bbb6326169431487e9ace6bc24b14e3ffe9e4072858ea858e33770e8a5f54b202854de0068275e6c5d2061f3c6a23fb633c2964157adfdea30c488f1f030437bb374449a427a1d403d12add243a438e8dcabd18d843207fbf3f0e711070e527438d2d1a3727c5e53171cbdd3509016c035da41911010001	\\xa496ccc9da09f8beccc8a3122fc9debe7e605144514400ec9a6871b250d3b7b4f738984290b72b65d0abeb73113158c4bb4b45a805fcd6b4467708075fe32a09	1662286893000000	1662891693000000	1725963693000000	1820571693000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
405	\\xb78b8724ee81b8c55d5f06eafc9423e945947e3f67a1d8cc927ce2578d84d4607660f29e9e1c3bfc40308c1f06bde43e4165ce46c64e8ea8413ee528b2087b1f	1	0	\\x000000010000000000800003e50ddd274bee92d46fa937e9aa430107420fa6bcf4d00aaba699213f9ba7d341269313c4971b7f38222663e6dc054d4649571d2127f55b1a15cc7fb687c1bcc2c1f1a146dac67b76d7217b958ece7b3de122786dede4cecf7135fd0b3e37d90fd5a6fd7d41a8c60af12c729770a8c4a55882c623d3a2020bde9dc5103a8b185b010001	\\xf1b2749e02a061f450003c5a442fc0833e196bc078dcd69062ec96c2b755ab4b079d84f83e06cb03d201293b6be9a7e7fe9f4a23bd9621ee2b60915c07e77706	1665309393000000	1665914193000000	1728986193000000	1823594193000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
406	\\xb8270319149be2263e21ad8e69cdd670eea17abb23f29a74ae763f9f6a110da5f64625acb4f450ebd00ad2b7978a51d80cfff9b550e87cb067cc33a344b15d03	1	0	\\x000000010000000000800003c248acfd8a46f854ea9a77190228933b4a74a861e881934cf4d8ecf2905a27abc55043bdc753b5f10a36418e4c34e3d2e3016300f0daed7265ab58b5985ab734dc47fde997d0ba646b2f1126b94fa820e9d9a421e967935b7331e02f2a45ea8eedba8d85edbeaefdf1b404095f7e7aa8a6f90d473d2832da1c26a28155004cf7010001	\\xb2d5f7d165eb9ca32efa1dc0c692f4f2fec2007443a1dd5258a5edd4fe141320bd4edc0e762c56e80714bb36b698702c113601c65ec52f92abc9c3f142b6ac0d	1651405893000000	1652010693000000	1715082693000000	1809690693000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
407	\\xcdbbbe51a8c44ebfd3e2b033ad7148d2f40ffb9498137bd465cf7e9d578a382ee0f2d4b8e74ea7d4905059d1aa03c43b4e85755825b9f87211c86ba1ad7cc9df	1	0	\\x000000010000000000800003b3ed3b1f2e1c40db6031e6eb23d80a230f4b3e678cfa40c109dff82ebc4c4d6dff68b3aca33fa7ddf030e15c99de863762a95b441e1644357223d019d1235bf954c43e956386038d506d8743d8baf673054e5e29cccb3458e25c56653750b2c22b7cca0ac9d1023e318b649f2aaf8d6a775e24823c2fbf7b7501486160b97443010001	\\x504a6e2d62301b667568f4bd6c1334d57da57f166231be5c6d1837984cc1811c4789114a79e04facc2e43c62c0f2cc1b5cbce0e64853ecdca474891a04459d03	1667122893000000	1667727693000000	1730799693000000	1825407693000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
408	\\xd37f359e367e13d72f93fae83420f42a51739e865f4ec7be77e6e215754b427dafcaee029b42346fa5a153e1f891ab1f936582f2a1ebc8d07c8dd205a8b42c7f	1	0	\\x000000010000000000800003c21a96d55b7d9f512dbb13fada16c21109c0e47b0ef29f6722f9f97d1d41442176e421b445a6fb58eaf1b62d6bc1632f759aa4ff238ba71dd3a558553d13186ef9d136f24182a68c7b5c5a744babffd5876b1f05cb9fbf101a761eea164030a87850f44e992b83e8aea1074fb92a9f614b4a1a671d2f0b01ccb6797cebe5df91010001	\\xdb84b43572fc1837044fa77c1f9f51ceb920f02f327a2e301f568e3f714599fbcdbe5b2b42c9dc1aa3b5af7267e37dfbdcd47a02275242dd4aa69520ed90840c	1669540893000000	1670145693000000	1733217693000000	1827825693000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
409	\\xd3678510141bcb25a913485a4bcb640821c5ac3cc27bbbd363e6b524984ebe851ccda1cbb83d6e8ffae6880de1d64efb3e971e70d4a1533c199bb718d08ed625	1	0	\\x000000010000000000800003c923e9a3752adfa5b34a065e8cb7d91d2701abc62f28a6148fa4d0fff794906eb4e30ea2c00b10ac74a1f4f4ec3fb381419cb4790c4b427b60bfb308e5dce6ee208f5db80127eeede5725883be8bd19a511f9aafa07a393485a2a1305037c7ef64dcca931260a77c9dd4761e913216f87ba560d840e777c88e297bb70035b47d010001	\\xd5b5ae6db290ff0906d7bab7f69c42eab9254f4bc2fb55657ba06924bd474e56769a190017658126ce76880a199b0d82024fded874b5fa4051c946f0f4b01e0b	1665913893000000	1666518693000000	1729590693000000	1824198693000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
410	\\xda5778239b384cd2d5a96d3792572977d74e5d3b8090a47b46f86f835e81602c27cdbf5291bae9772fe7d973d6fb44415e85112fc4c08d69cd9afc5e0fcc171c	1	0	\\x000000010000000000800003a299a6d4713a94f27d983617eae901dcc3988ceedf4d81c2d8b7f7d09fb114781e93998718cac4615d9f98871cb57ea711088d8d17022506097cddb18c8f6f50617e75ba6ce17ccee40b63af5bef335055b68b67aac1f3a9a508f8b33bcef6ec2a79e00c40d25e14b394f8e16756fe8bec375a8572712502dd3ad5e812384caf010001	\\x19dc41a13eec521108db2184191964831b315170a65b09efb28abd110cedfbd4f847f4a98991da50449401e21a4dcc11d7f2fb03a1f46ae311e38c57137c6109	1678003893000000	1678608693000000	1741680693000000	1836288693000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
411	\\xe8e3cc41502eaa851e66c9af15ae051eb9b73b8fb7751f14693de7f05069a75aebc8a47880023fbe95e83b35a93f3ebd178f8c68eac70104d72d087c3d0b0867	1	0	\\x000000010000000000800003eb283f37e6685a06b91824c1d9d0344aeb888b5e35f4384f35c58c4a0e949e23f9927eba9e928b53539e57fd98606283dbbfc607bb0b85b935da16fd3dfdaa38ba994bfd5274f0258a605be36809d0cf5c18ed20985d498d2dc98efca824d5975458d35bc25b5f5abfbaf876307b63c5f6b01e54f9d0e0df4c56af4def67bf15010001	\\xd2e6362465ebd78e1c13a130ce7cd249edc84d14cf48995a91e6c90193b9d1e789d162d73c493676f6d5990887172204c79f85d9aef7b1d6abbb9805242d8d05	1660473393000000	1661078193000000	1724150193000000	1818758193000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
412	\\xe86f3bf6bd861d3d2e7f963c2c286195d65aae03bdffe6a5160ebb7c110fb1f86028e667932826adb394bcdcc0a270eb0765d3e071cbb64207968bb01879d725	1	0	\\x000000010000000000800003aee8cbafed8b30a6ebb8a4004dd9bca7f316aa12bde504f1a3846325807b6f82a56a394b2a7668f164c0fb528bd41b3adbe80f96b142c3e16e3bbb7615986ef90da7f3e9d34270c8bedc48d1434e04ae98a54d9ef9cc3c3617c41d1df1b7f44aa3608408f22ce89e51bb5d0a954a1e28b77a4bdccf38cf135d2a901cc9aa3e25010001	\\xfd003b765ad56198058051513d8d267d34977c266089de3ab46d857e9b4f86740f57c6384c6724c455f8712543979feac74520f1f42bee15c7abb3f24ae6fb0e	1663495893000000	1664100693000000	1727172693000000	1821780693000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
413	\\xea377c313b88981ca31d567d0d3d4c8c3d1f995601e708bfc5466efa26b045a2accb10305b1508684439cd2633ae5c7bfc8feb288c3732b40ae6c3b8a0362098	1	0	\\x000000010000000000800003ad50d7d0c0fe0078c38608b7aef3f115e1cef3ad0213005c14038214dbf97ae13b088ff68f73409746e1fceb7600305ea59d1f3d7ede01134d352726703ef441a4b5f82849e4ba3c8cc289fbb7c88a4a2bea7d08fdc8175e7833c124dcdc0e4c5a8e3b8f5f51b0c61b7268d7bb6276f253ca31221567331da38e01f58601772b010001	\\xae03cc4238a342066236a2b92e55384466bd330ec6b470044dc23e0df825d38f4c7425d9b938a888e0e721d0fa87b52a855194bb5b15d92f444fa1edebd6cc04	1648383393000000	1648988193000000	1712060193000000	1806668193000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
414	\\xeb473bff7057d56ec75e4d820b3ec1ab12015d1c19ea730d548889e1814ed7b592e2a39dbdf96094328b1a18f7680c7d614b8018b2351f21e7b285889f20d806	1	0	\\x000000010000000000800003ed39eabac0d897e507f96a71609bcec423f6fe797073b0b5ea712143e002c67d7cd41730acbd984056349790fbe58146b4544b0f2dda4cb353812f96a85350c695e0ebc96071ce716b906f6700f8a0e87882c8a9fae805472c40bfad90442365c5e4892d7239d7bc5e059982b22cb84f6fa197ac6cc017afc700b00ab789a7cf010001	\\x1c0f108dbc97d56c0ee44acbdcf3ce1b92806f58c40a144e7344a28ff623fd0f26717938c997891771335fbfba9671135b78a0082d2bf176b0e9162b34a1bd0d	1676190393000000	1676795193000000	1739867193000000	1834475193000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
415	\\xed33e17ed008e553f3a24b46b6216fb0edb6630c8edd5714e0251d3680210b96db1940dc03e401fbfa30c5fbe86181ce3bbf680652f287e5af765c06cff87983	1	0	\\x000000010000000000800003d335ca89dc688bab2d4e8484f2b8a28f17039a3dfecf753f3fe7e6f4c86d27568489f76447abdc3c5eb09de5d1ae3160fe7da6b6db21973133c9932d42ae719a8751310bdffde5df2b896149e3b60b965972dc452190118d009119c6d4b04133a7e52e609eefd1242eb995d2a08124a015b188109e59300dbeee167379c8cb2b010001	\\x17d4d6e933bc5d09d1f7a165737c7b80f17c5a0f3baaaddb534ff31c804026d0cfef7c01d0e322513896b2bdd8ecb1be361303cbb2515e9a9f65090dc6fe200c	1655637393000000	1656242193000000	1719314193000000	1813922193000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
416	\\xef83b6174ec395e5ea9da0c21b6335de4cd871502220be44516bcead23ce0fe5df2bc78123b3e959034f1473d73afeb3a88845ce11e0c98d2f150734f1f66280	1	0	\\x000000010000000000800003ea364966e01d486be6e061762c6831d4ce1c131e138d96a7e2a2e5a80c685be7649aeae6c5f31d84855c6500b9db335d667210d53aa89e441ab95addb28d8f1f69a8b6046f04294ce4f26941bc999e2aecc737b46b735ea53d08abcb378fc850fc692b3edfe68c69fdeb9c67cb821d09bfe9097e12c6652b48c31ef388ea2ca5010001	\\x3be2fa9a29a8639bbdca0794c6423e8e611b7dbefcfacdc1dc61313734bbb66d0fce9eff3806613317096a3ce411ac57f959d85c7288c80af7781cf5c65ee407	1662891393000000	1663496193000000	1726568193000000	1821176193000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
417	\\xf3ef58983c06c49721a412f6825cab9a69ea4a4474546b6ca171ac2d3129fde61b9bb8da0bc8f7f8f47badf83df744926ac328254dd2c7bef6b707aab93a43da	1	0	\\x000000010000000000800003c20e9401fddceef80b21e33faa3d42442ae20e2e358e9e6aa731a2df40b9a36687e72d94c7196cc679aedef2113cab1e9a11f8c8b22e4acc95af06a0163ea6cfc0321075aba250b199fd7a217d05d2715adaff84fd939ae15472f7eaa0507d1da41a04449778fab5cd3b8d9acc4c39702e1f58feb5289b1a09822c396b991d5f010001	\\xab1f211213313c8d7ca6178bd6ecf31977ef6537da9e8c56f9432b887b6a293b499890afc71b339317b6df60c4099fb1ab05587fb7a78fd8cc07a4c276cbd002	1664100393000000	1664705193000000	1727777193000000	1822385193000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
418	\\xf593147d79b419076a4c0532cce3a645c8a2f150745af1271f179ff66575e6d69cb3ca0ec386a18d22183e32dfefb7ba9894f228b13a510d28445520b048c040	1	0	\\x000000010000000000800003f2e845fbe8fa383fc9985d5c457edce4db8b3c11cd3374e2170e9aa419062b8b5f75092aa92ebefa2a8dfaac6accc4257899d223fce6e64c146c5eca584e47699a41d8a52b00003af04af0022cfe6c8f0fbd31eeb1c8e4c1fa8dfcde2aba703f42280ae9dce5333b5e0e216d86c8a79939a31e84adf116fca7a03db58c7754e7010001	\\xc71dc585d810c0c671befea71a09f04c8d48883b1cc81d02381e9c159d54708f84887025a905af305f933b7c04f10565cdfd2f005c2ce9c9f1f25eb73564350d	1677399393000000	1678004193000000	1741076193000000	1835684193000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
419	\\xf62bd69a264ab27ae82f7e8a6d3272955ba9407b4755f226079f55267a1aff834d8b75af554bbbe1957eba0e280667c3a8a5e535203b9fa94df810a27f81666c	1	0	\\x000000010000000000800003c1c3c93e17e9350ec76c8fb499d31c2eb98bc5968b2d23eb6055ee68dae3ea8a43e4f3321ab810f5ec2a34d35708ab6bf5c2ca0f857a972bb4ebafc80bd1916c650d36e84db625f9056d22c58d2690a1721366b10634ee8d95b5e5194ed4172670bbbd897a5cb2dc04bea35db43f34269220e51df9b94428ede35c139cfa58fd010001	\\xa4316aab8e42a9c49fbc711245730388ca6fdec90605f5620a7d5d9a21db999fbea737bff68f87ab5436d50db2022992e9623bb6cbd8cb17363b642418e84602	1653823893000000	1654428693000000	1717500693000000	1812108693000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
420	\\xfad7eed97416c0fa7062242c425fefd569a3966b86c84e617ed1b396f38e454fdcdb895bb2c206d0e61d1565e47b2ede4308f157ab568689cdc974761fd65bff	1	0	\\x000000010000000000800003ac4177ec83b96108029c8fea9182bafcdc25091f062924b8b5a83e92383a3b12ba569c2b02ab84ea562351e2aab789e331c3cdb9915c4774c48713507ce15fe66cc1e83e0d022526b22e85502e3e7bfb5653122774517fe6cb1f9fdee1d1b3ba2c47e26da092aefde6fa7ec5e151d7b344072100626b76588fda673a8bdca66d010001	\\xeaedfe8db3c0794622f7fb218b2feabfed256315abbc4184a9d68bd8bd44e87bcf4dee78aee37866189dc33409c405c801864f7a4c747eaf71f5e8a38207400a	1652614893000000	1653219693000000	1716291693000000	1810899693000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
421	\\xfb8384f67de647c10320ac566b695242e59ce7fb5b8a6c1e184cc45f5acc548b1cfaad5c4af5daf65853e741dbef66b0db9879872becc198f7185916ef17c311	1	0	\\x000000010000000000800003e04ff2f1d6da3cc112ea177831a9566ca389beeb3e89e85ab02b3968e35e68c9b9c7d2a6e727033a0fb51c10c00966c572ac267a75eabd3fde9b8d0c020c16160c0010cb14b03de2f77e999d00880c6054e0b2a8cb9ecccf61a21cfc54701f5b3bf2287efa8af9ffc020f0c4e1ed79c58271ff66d17d71f4c57b6c90e0dfbd59010001	\\xf29958e9dbf3c29f5bbe4cb020723849c3ba4ea68fb0c8dce8547b1acc1a0e0bd4025506d40e4882dd40ec8f8b889b38f854cae918a95fe87c20044fd34afe08	1668936393000000	1669541193000000	1732613193000000	1827221193000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
422	\\xfd5bd94e35cb203ede2835574d4101777e1fcf717d9bb88f337969cae014c85569ea9568b54f1ed1bec8f76d1cbf5e61272a83c3f38a35c8c0a99d0cf0c40b6c	1	0	\\x000000010000000000800003f6c42466ff7bfe6ab9d2c094a442be2e032acb5af947066306c7389cc96138af262d4b2e57848ea7871f02cf3e9a0399a2fd6c91adc91db730f79003632da1d0936ad63f3cf5506f94c1fee17fe39f31b866ba76c516e943796803a85e7d969bfbe9b9f8ecdf11d0eec4988b7d71a5718d34b995217c1f689e92a3dd4456c18f010001	\\x926b0c9d6032cac78a969c19118eddb76d2fccba2778099e58101a9c6363c71da13bec7f8c9f50b03ac16414b760a558fd9f7759031fef941079a60f02d4be02	1648383393000000	1648988193000000	1712060193000000	1806668193000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
423	\\xfd6ff48367bbf9b72e9f6775d3e09e5f2daebd48ac135db00e76e38ccff9c38becf349a93b6613040e76991523165ce7ad0071ef1d787b3c7f92597b3c9ce2cd	1	0	\\x000000010000000000800003e31cba5d7c2e6aa36ee852dcdbb92da26800eabfb0c7e41422a3c652b35c72db8ca87f11a9e01de7b7607c3066dfefe030c8a519762fff083edd3b6c48f8ee7b0fb0ae28717d4dfc626be360eeff5397dfbf22da0cd060c0d94b6d96d6e5a321b43a848e9918f889e3625c8ee05bd43a9761f3038a912ac46caebc70c93510c1010001	\\xf9cb38a64429848ed9360631cd3485857dbe6a125467ecd7c71a011aec11bdcf29251d13f225cfeaa092e07e4ccdd253886f7d2e807e5d5e163b9e2b08497705	1666518393000000	1667123193000000	1730195193000000	1824803193000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
424	\\xff9f6211a5faf8938bffb3707cffa6b35d96cc0636d5c87216fa1aabb2eedc806bd63f5a148e4da651fb4a5f4990bc8fc984b35e0cd63127b378751d3fad7dda	1	0	\\x000000010000000000800003de51cae48d32c21d0867c7d3fd5a50f74b1bd6e02cc4d6ed24319ede678b0700568b6bb37557c475afbba2a1f5ebd0a63e63bc750d127f6d223f3faeb3e898e4e1e428ca8064a68e3f38f8396be847fbb8bb8ce2c5e553885abe61a68cc9f7c366380ef4348b50f3a87914cf68ae448c2dd3d755f2f292e17d37e6b72669a447010001	\\xa35b355277017eb91d9f230e1713958377f75933692fd7fe303ee36e90477712e54566e74c8b86da9252ad1c2b35eafbc9ef6e3dc38b0fa4f3de9f1852e30404	1651405893000000	1652010693000000	1715082693000000	1809690693000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x74175231b10c949a77973b7c17272cba1828d55e1e9a9ce2f1c5296cedecdada	1	\\xf04667fb9c6d6e89066f8a82ff0f1210eb91cb8f950d52bfc15833d7b0ebe1decd80834e9dc8fc31ae290d8168c8c57e1215792bc7f87371a71ef5bd56076b9d	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x61935af6cea0befc3e2933aa8c18200b62b84ff770e201c98a873a39ee86a6784f827ceedee7e09ceee399ee7fecd7048a52612aafa369f716b481dd0addbbfc	1648383425000000	1648384322000000	1648384322000000	0	98000000	\\x3c69a6ae34fe8799b9b6b26beac61c938d7afcde358afb7ebfcb141d2c5f9f5a	\\xd88d6fdd40c01d5856e776f4e5312251147f2742ce485f9c441eb2b1b40a8454	\\xe942e4102c3cdce010a02865c4a00e12118126ac70b159addb5805d6bfc8107ac75ca4d56c6c754ab82b2a0cf830def31b7cc841303ec409675881125b2a5a0c	\\xbd413315b061c030627e4d29854b5da20b7d61b575c38f7a02668e5437efad07	\\x003a003a20006e756c6c007472756500646be26cc07f0000000000000000000000000000000000002f172c738f5500008060e17ffe7f00004000000000000000
\\x74175231b10c949a77973b7c17272cba1828d55e1e9a9ce2f1c5296cedecdada	2	\\x64ae44ae0d2b8a50b2b01f885c8648237936b4d0563cfca51747ed10173a5905675c41e281359687f024a1f0b5773279fc95b77f2b2494a5234e0f90b1f37e4a	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x61935af6cea0befc3e2933aa8c18200b62b84ff770e201c98a873a39ee86a6784f827ceedee7e09ceee399ee7fecd7048a52612aafa369f716b481dd0addbbfc	1648988259000000	1648384355000000	1648384355000000	0	0	\\x025d0d3eb779395e392c0e020625995d34ed3f2b12e28bfb49261235a786eafe	\\xd88d6fdd40c01d5856e776f4e5312251147f2742ce485f9c441eb2b1b40a8454	\\x8a062c9a13300ab31654df565ce84c03beed8c7e87668d8a7c1fa97b240aaa283dcd5e5ecd79a6a5888fd9b0eebe86f3191bd8ee9db4758075545881ceb1fd0e	\\xbd413315b061c030627e4d29854b5da20b7d61b575c38f7a02668e5437efad07	\\xffffffffffffffff0000000000000000646be26cc07f0000000000000000000000000000000000002f172c738f5500008060e17ffe7f00004000000000000000
\\x74175231b10c949a77973b7c17272cba1828d55e1e9a9ce2f1c5296cedecdada	3	\\x64ae44ae0d2b8a50b2b01f885c8648237936b4d0563cfca51747ed10173a5905675c41e281359687f024a1f0b5773279fc95b77f2b2494a5234e0f90b1f37e4a	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x61935af6cea0befc3e2933aa8c18200b62b84ff770e201c98a873a39ee86a6784f827ceedee7e09ceee399ee7fecd7048a52612aafa369f716b481dd0addbbfc	1648988259000000	1648384355000000	1648384355000000	0	0	\\x1403ad55dd15e3fff72c9f461363a1338c784d214b208e8d7bc46d2eb13bbed1	\\xd88d6fdd40c01d5856e776f4e5312251147f2742ce485f9c441eb2b1b40a8454	\\x0be9f362797474d26126a959732703eb4fa2d07d010976f28e1bd533c4e32196d485868e05a0f9d5c7f2253f9cb3df18b9d99f147649e73d4d3217e14a56dc01	\\xbd413315b061c030627e4d29854b5da20b7d61b575c38f7a02668e5437efad07	\\xffffffffffffffff0000000000000000646be26cc07f0000000000000000000000000000000000002f172c738f5500008060e17ffe7f00004000000000000000
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1648384322000000	2101382338	\\x3c69a6ae34fe8799b9b6b26beac61c938d7afcde358afb7ebfcb141d2c5f9f5a	1
1648384355000000	2101382338	\\x025d0d3eb779395e392c0e020625995d34ed3f2b12e28bfb49261235a786eafe	2
1648384355000000	2101382338	\\x1403ad55dd15e3fff72c9f461363a1338c784d214b208e8d7bc46d2eb13bbed1	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	2101382338	\\x3c69a6ae34fe8799b9b6b26beac61c938d7afcde358afb7ebfcb141d2c5f9f5a	2	1	0	1648383422000000	1648383425000000	1648384322000000	1648384322000000	\\xd88d6fdd40c01d5856e776f4e5312251147f2742ce485f9c441eb2b1b40a8454	\\xf04667fb9c6d6e89066f8a82ff0f1210eb91cb8f950d52bfc15833d7b0ebe1decd80834e9dc8fc31ae290d8168c8c57e1215792bc7f87371a71ef5bd56076b9d	\\x133a619b7c5aef396922a8b0f516321f02db69b29ae4a5c2890029ff1d8f81ca9470e2f9d43755ee426715e9f9b802d8d33fd10b6665e73704b9c14ac9cf690d	\\x9e62d87d5cd2c881b9673cc662f145b1	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
2	2101382338	\\x025d0d3eb779395e392c0e020625995d34ed3f2b12e28bfb49261235a786eafe	13	0	1000000	1648383455000000	1648988259000000	1648384355000000	1648384355000000	\\xd88d6fdd40c01d5856e776f4e5312251147f2742ce485f9c441eb2b1b40a8454	\\x64ae44ae0d2b8a50b2b01f885c8648237936b4d0563cfca51747ed10173a5905675c41e281359687f024a1f0b5773279fc95b77f2b2494a5234e0f90b1f37e4a	\\x380141acb702e64d13c2e5b6dba5f1a6b0f644653081ab226ed2e4543ab91cc5c44a004fb796c4df8cefd7915664d6e5aca5e8a4ef18f6a0ab48bd07785ab10e	\\x9e62d87d5cd2c881b9673cc662f145b1	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
3	2101382338	\\x1403ad55dd15e3fff72c9f461363a1338c784d214b208e8d7bc46d2eb13bbed1	14	0	1000000	1648383455000000	1648988259000000	1648384355000000	1648384355000000	\\xd88d6fdd40c01d5856e776f4e5312251147f2742ce485f9c441eb2b1b40a8454	\\x64ae44ae0d2b8a50b2b01f885c8648237936b4d0563cfca51747ed10173a5905675c41e281359687f024a1f0b5773279fc95b77f2b2494a5234e0f90b1f37e4a	\\xf3a033d6241fbc0babbcd45992ebe0832e71949738250da72f5dba5ffd8e1cdf7bf44d48d96f0f5458fb8915d5642c17648a0cc827c3303bb3dea743c2457b07	\\x9e62d87d5cd2c881b9673cc662f145b1	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_for_matching_default (refund_deadline, merchant_pub, coin_pub, deposit_serial_id) FROM stdin;
1648384322000000	\\xd88d6fdd40c01d5856e776f4e5312251147f2742ce485f9c441eb2b1b40a8454	\\x3c69a6ae34fe8799b9b6b26beac61c938d7afcde358afb7ebfcb141d2c5f9f5a	1
1648384355000000	\\xd88d6fdd40c01d5856e776f4e5312251147f2742ce485f9c441eb2b1b40a8454	\\x025d0d3eb779395e392c0e020625995d34ed3f2b12e28bfb49261235a786eafe	2
1648384355000000	\\xd88d6fdd40c01d5856e776f4e5312251147f2742ce485f9c441eb2b1b40a8454	\\x1403ad55dd15e3fff72c9f461363a1338c784d214b208e8d7bc46d2eb13bbed1	3
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
1	contenttypes	0001_initial	2022-03-27 14:16:33.52792+02
2	auth	0001_initial	2022-03-27 14:16:33.686627+02
3	app	0001_initial	2022-03-27 14:16:33.812463+02
4	contenttypes	0002_remove_content_type_name	2022-03-27 14:16:33.823933+02
5	auth	0002_alter_permission_name_max_length	2022-03-27 14:16:33.831928+02
6	auth	0003_alter_user_email_max_length	2022-03-27 14:16:33.83899+02
7	auth	0004_alter_user_username_opts	2022-03-27 14:16:33.846654+02
8	auth	0005_alter_user_last_login_null	2022-03-27 14:16:33.853538+02
9	auth	0006_require_contenttypes_0002	2022-03-27 14:16:33.856661+02
10	auth	0007_alter_validators_add_error_messages	2022-03-27 14:16:33.863696+02
11	auth	0008_alter_user_username_max_length	2022-03-27 14:16:33.87812+02
12	auth	0009_alter_user_last_name_max_length	2022-03-27 14:16:33.885372+02
13	auth	0010_alter_group_name_max_length	2022-03-27 14:16:33.894598+02
14	auth	0011_update_proxy_permissions	2022-03-27 14:16:33.902096+02
15	auth	0012_alter_user_first_name_max_length	2022-03-27 14:16:33.909287+02
16	sessions	0001_initial	2022-03-27 14:16:33.940634+02
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
1	\\xe08aea34b9d506863d90c6bc019b1756a922d957bd1e1a331359243e48c0ac9e	\\x562bacbd5d530e8a92eb4994ed83b3deca55e303c5282dee130519c144ea169d1e9c317a8142b99c7db834d217cebc98452320da7dbfaa2960fe6256c63ece0e	1655640693000000	1662898293000000	1665317493000000
2	\\x69a44cbdd733da4dc033047465feec7310d7e76d9e58b7b59ee1253b191f843a	\\x8621bba7c675d255a199d7806ce13a9b35a51290fd59b5aae8171145acfdbfd3e4bcc5344576388e7366568bf8e8ba9d5fb4e233d91283c3e63ee5bfde74ae07	1662897993000000	1670155593000000	1672574793000000
3	\\x2d714ea6747f7878b060aa46e01772b8ccb772ec401be55face02bbe8b249441	\\xafa861f8e017acfc111b00219703379b2571b2bc6d4200a9deba11e500caab9f9c0fd416307bc6f9acd85ad433ba9c2626da7a596e6c898a60de8b06066c4704	1677412593000000	1684670193000000	1687089393000000
4	\\xdd6a0e39637a86e7d913e2690f54f8d680cfd124f5350a9213b6a328a844eaa2	\\xcd5e471c6e84f6d78d12ac0b02dec2c37560b9654bd9690cad2016a79047eddc69d2cc568986b81e2b099755107916b61e71370ade777651dddbfcfa4db3f30a	1670155293000000	1677412893000000	1679832093000000
5	\\xbd413315b061c030627e4d29854b5da20b7d61b575c38f7a02668e5437efad07	\\x58c2d5f009420f46a54e92230dbda0af8da387ca0cfe4e1d0da513ca59642e034db3497004b1b441fe7bce5c262a9ba6aab50a385b013d914dd46207d5047d05	1648383393000000	1655640993000000	1658060193000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\x00f457c31228c54e56472f0cc6350ec1063e81c7a5dad25e3521624ef900a280fe9f08eb3abf9c330b176a96886268da68a415d47df5bfe4a133fd1e06490100
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
1	422	\\x81f6e7eb56d3e0249c7552e00c1f57f72452464845c8e6dceaf848d4c678996f	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000d69768458416d06a0b33280e4540acea0a3388f3c205aa50aecb4310e9d9e98cc4fd50491a50c7eaba084bb2394d8f848aa869245a5ddcf6e6d4e50f9a586114ec6e25e9d0877b41fe512ccb6506280925fe7e510df5f3add803cfe288a03782a0069e7e49d23eda13f196da6f287f5ffe5477c0d6a45eb32e32b536545bda2b	0	0
2	413	\\x3c69a6ae34fe8799b9b6b26beac61c938d7afcde358afb7ebfcb141d2c5f9f5a	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000010afd2bfb98534ab907edfd0328c239ed962e3dfeaf96fddf45c9bd707d998c69bff4a6da0433e13b1ac625f727526fc378ed1fb439f8cd10389da9baecff5644c79f06269a2cc9a8053e37224bf66640d0bdd85af6c35eaa8c73d40dccd58a2a9da57e5ee603a105266ffb8bb2dcf55953bc044c11ad23cb72cb50217251aa9	0	0
11	125	\\x1eb120347ed9aa5cd61ef66a085cff4326dd285dffb4e70e1c9070f29be3b58a	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000004b453ff9b9f41a148b1a7d34873e30af6505659b6821c62a26921835545173c7b9c5d9fd21f0ab0910008265e064a7223acf408a6b9fd6969de4e0d0eee3c38ae460820567891a28bbd17e120431725c1d71894cc69f7cbf54345fb48fedb8b6bd8be8968d3d7c69f7e662866f70b9983acc6e000d32648c5cb64d0fdcc80d2d	0	0
4	125	\\x154eb435e9e74c0feecef9707e0bc6a8043a3dcfc7c7044c7e09711a8f462660	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000011d96aa6195ef32dc3d9d232d64b130703e02d218801d82a9228d8f590b46a8f578b22148f1dd3ef18e5f1a98f2423c1b27d9cdcbc193604e76ad15ca95ccb2a59b06d283fe9a29ca8e8d8622381d4d154e11d6ed4b273ac2d950b8063c361ae6ce12a77d6df7c4703fd7dd0bc5a58259083d1d895151a1419010f7bd0b62f1c	0	0
5	125	\\xd5281a7a6863a27b0f8d282861f703ac7ffa8e32bcbce6db690a9b9d6179e705	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000156d9e7bfa7f1ba128c54b5f1c85ccc4714c9438f8de00a1f488024d995d75031baf24d88b201a656a4216b7a24ff249f95c823f19358fa26f422f151fff71fc9d97941712c8070d41a2cbf8b696ec4a22df7c2abd0bf0570e990545f0320300f44035778d79e1e52be57fcda70bfede4003a3e6d427b5b18984f4bf0fc42bb8	0	0
3	124	\\x65a1099ffa47c6d27481b171a9977977f90e854f20ee726961d1e2c56d3657ba	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000009fd322db791362c286ef91795e4b34ff8272537dfeea085ba3afbbf938804d14de04dbfdb24a55baf48ee7f390e9d0dfe4f473ad7abdaa39a61515820e274be1c068e0966b1dcfa0e801fc224ce769f581f3f9652e78cd43e70765b24b06233e42f14cfbb5ce9ac8077549af4f4155bc0a244f5451ad5b2dad3ab63228a0cfbf	0	1000000
6	125	\\x609f4fe7f18271732bb05d0ff16715b5bf24b58ee18fef609d7f2608e392de7c	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000042434b580db30e073d43c7627a1a709fb04f8aebd879cf945da5c3630819c6d679e61774eac14aa2487a611904952fb64b2d29eced1971aa98cdd5a4f82eee427a892e44bc38ac86e1c14bb14147354b9c5730aeaef8c2eca7d4ed5cbc0135295456a25992f8b8241dcdad14bf6dd2119d805434fb11eae4182e03e14f34052e	0	0
7	125	\\x9dd4b35f3798ee0957c355368a4ea26ab1aa5f745cb7663fa11f7a9379ca2896	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000bb31891bf4d7ebff3dff90e01149fa80037da795a746c014fb4ded7087c57b5197406becf6e33dacaf6338d6beefe10c29d0fe43f52b1b18ab9622d03b344e2aadfb14811d42cdce7c8e8efac708dafb9516e3e763c020b5b6547a0bc76c1549d95f6f586e4ba7da1f34bcdcd5f5395c93b1b6c150b0de01289887c76673514f	0	0
13	328	\\x025d0d3eb779395e392c0e020625995d34ed3f2b12e28bfb49261235a786eafe	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000253f4b25949cd2c4549513186db74809b82911be5b646658cbed48ae975ee53c9b47a929c3fffb3e35b83bb2e169d118994257697e4eb799fada4fc4d0f8f5c891161fff5812c2510cb21779220572e27e0c53c34eb776e4540789a913e878bb2326b3cb6e93a0b580ff81a613a918349eb858dc8f192324b1b415c8c2ccb4fa	0	0
8	125	\\x931a0d44b64b028bb9a78d4f70708bf71a6f1179633dc27cc21f9c4b2b6a7ab3	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000044a6c3e9e59fa9a7425cb51b49415fdef33e030a3e0a28ac8bc1dcef974f057972f2eda9b83bb30faceab1358b0c5fe230ab7deb56c09f6d5ad23a69112d63e8095cf1150ea6acdb2b0d067e4cf18300bf55ba4c6a1af0f26bdaaf4c15e87447dccd8bd96347c1604b91ba4c99125dbf986c44cd1d351ba875c2f8b30fe39a90	0	0
9	125	\\xa1394352919b28d4aecb5be6c3db9a21d36733dae456d4d229221534aa0f4e79	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000063f36d6ae717d2f5e5c1b41a570fc18d80367e4f96bcd7eed73018abf34357aee6de0cdf60751baf496894f2cd02d108245ea0e897e2e868a7231352a7a9e965d485363f285430bab88fe6b91240c045db67265ea773ce637a354435d7eda12e366bceaf7550558f04e8971126a520320f5dd86bc5f7d1d422b049e9d24bce51	0	0
14	328	\\x1403ad55dd15e3fff72c9f461363a1338c784d214b208e8d7bc46d2eb13bbed1	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000009996de081ad0513017e250d82e68c88e3cfd5c01725a78730a63ddc7b254518e61d91d32fa24c05d45cc55e95f3a3d6678f3612798bbe9c1330209f86c2118f728256cf58eaa95650366fa91fe9a38a2886305cf8f5935870e8502632f1a7f04741aba8451ede63367346b8c3a3dc26feae7dea2001788c430cab82aff5b94a1	0	0
10	125	\\x3ad93c3c2b303ad85eb5847a90c78ea55b5d7f398087f9dd62a5fa3db9ecf312	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000218a5fc690eda3f194841f3a909b074532ac0fe7c041753f80114730de40ac4806e48effc4719117a3d0ad05583668e2c93e4562bd26a4169876e9849ca583f0a9311ea153d25ba36a6995d98a6404fda46e13ca4abcbe0f2f7b378d89821235db9da0a440b268d5b44a86dec88cbf291bfa288618e6bfb5d2609440a37bebb9	0	0
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x61935af6cea0befc3e2933aa8c18200b62b84ff770e201c98a873a39ee86a6784f827ceedee7e09ceee399ee7fecd7048a52612aafa369f716b481dd0addbbfc	\\x9e62d87d5cd2c881b9673cc662f145b1	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.086-00R1XGDN2Y7Y0	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313634383338343332327d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313634383338343332327d2c2270726f6475637473223a5b5d2c22685f77697265223a224336394e4e5850454d325a465246483936454e385236313031444842474b5a5145334830334a4341475758334b564d364d5357345a304b575856464546523457585648534b564b5a584b424739324a4a43344e415a385639595742423930455831424556515a30222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3038362d303052315847444e3259375930222c2274696d657374616d70223a7b22745f73223a313634383338333432322c22745f6d73223a313634383338333432323030307d2c227061795f646561646c696e65223a7b22745f73223a313634383338373032322c22745f6d73223a313634383338373032323030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224547424e34434448314a41394d585751374459314539534351384332484e41593354443953525148524d4d505356464356424430227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22563236505a5141305230454e474e513745565445414339324134413759395432535334355a373234335453423344304147484130222c226e6f6e6365223a22365054434648545a414e574546414742415933384a515638594b4653444d463551515a363536523334324a323238515136544330227d	\\xf04667fb9c6d6e89066f8a82ff0f1210eb91cb8f950d52bfc15833d7b0ebe1decd80834e9dc8fc31ae290d8168c8c57e1215792bc7f87371a71ef5bd56076b9d	1648383422000000	1648387022000000	1648384322000000	t	f	taler://fulfillment-success/thank+you		\\x4eebe4205b1b1060f9936c2b1fe69a87
2	1	2022.086-00P2FAWRJP9NA	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313634383338343335357d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313634383338343335357d2c2270726f6475637473223a5b5d2c22685f77697265223a224336394e4e5850454d325a465246483936454e385236313031444842474b5a5145334830334a4341475758334b564d364d5357345a304b575856464546523457585648534b564b5a584b424739324a4a43344e415a385639595742423930455831424556515a30222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3038362d30305032464157524a50394e41222c2274696d657374616d70223a7b22745f73223a313634383338333435352c22745f6d73223a313634383338333435353030307d2c227061795f646561646c696e65223a7b22745f73223a313634383338373035352c22745f6d73223a313634383338373035353030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224547424e34434448314a41394d585751374459314539534351384332484e41593354443953525148524d4d505356464356424430227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22563236505a5141305230454e474e513745565445414339324134413759395432535334355a373234335453423344304147484130222c226e6f6e6365223a224d46314b5851323053454e4335485247333758563046525030534633345a535a3258503654333950514435304350434541384847227d	\\x64ae44ae0d2b8a50b2b01f885c8648237936b4d0563cfca51747ed10173a5905675c41e281359687f024a1f0b5773279fc95b77f2b2494a5234e0f90b1f37e4a	1648383455000000	1648387055000000	1648384355000000	t	f	taler://fulfillment-success/thank+you		\\x69953def207bd0927057b90396d20d0f
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
1	1	1648383425000000	\\x3c69a6ae34fe8799b9b6b26beac61c938d7afcde358afb7ebfcb141d2c5f9f5a	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	4	\\xe942e4102c3cdce010a02865c4a00e12118126ac70b159addb5805d6bfc8107ac75ca4d56c6c754ab82b2a0cf830def31b7cc841303ec409675881125b2a5a0c	1
2	2	1648988259000000	\\x025d0d3eb779395e392c0e020625995d34ed3f2b12e28bfb49261235a786eafe	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	4	\\x8a062c9a13300ab31654df565ce84c03beed8c7e87668d8a7c1fa97b240aaa283dcd5e5ecd79a6a5888fd9b0eebe86f3191bd8ee9db4758075545881ceb1fd0e	1
3	2	1648988259000000	\\x1403ad55dd15e3fff72c9f461363a1338c784d214b208e8d7bc46d2eb13bbed1	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	4	\\x0be9f362797474d26126a959732703eb4fa2d07d010976f28e1bd533c4e32196d485868e05a0f9d5c7f2253f9cb3df18b9d99f147649e73d4d3217e14a56dc01	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x74175231b10c949a77973b7c17272cba1828d55e1e9a9ce2f1c5296cedecdada	\\xe08aea34b9d506863d90c6bc019b1756a922d957bd1e1a331359243e48c0ac9e	1655640693000000	1662898293000000	1665317493000000	\\x562bacbd5d530e8a92eb4994ed83b3deca55e303c5282dee130519c144ea169d1e9c317a8142b99c7db834d217cebc98452320da7dbfaa2960fe6256c63ece0e
2	\\x74175231b10c949a77973b7c17272cba1828d55e1e9a9ce2f1c5296cedecdada	\\x69a44cbdd733da4dc033047465feec7310d7e76d9e58b7b59ee1253b191f843a	1662897993000000	1670155593000000	1672574793000000	\\x8621bba7c675d255a199d7806ce13a9b35a51290fd59b5aae8171145acfdbfd3e4bcc5344576388e7366568bf8e8ba9d5fb4e233d91283c3e63ee5bfde74ae07
3	\\x74175231b10c949a77973b7c17272cba1828d55e1e9a9ce2f1c5296cedecdada	\\x2d714ea6747f7878b060aa46e01772b8ccb772ec401be55face02bbe8b249441	1677412593000000	1684670193000000	1687089393000000	\\xafa861f8e017acfc111b00219703379b2571b2bc6d4200a9deba11e500caab9f9c0fd416307bc6f9acd85ad433ba9c2626da7a596e6c898a60de8b06066c4704
4	\\x74175231b10c949a77973b7c17272cba1828d55e1e9a9ce2f1c5296cedecdada	\\xbd413315b061c030627e4d29854b5da20b7d61b575c38f7a02668e5437efad07	1648383393000000	1655640993000000	1658060193000000	\\x58c2d5f009420f46a54e92230dbda0af8da387ca0cfe4e1d0da513ca59642e034db3497004b1b441fe7bce5c262a9ba6aab50a385b013d914dd46207d5047d05
5	\\x74175231b10c949a77973b7c17272cba1828d55e1e9a9ce2f1c5296cedecdada	\\xdd6a0e39637a86e7d913e2690f54f8d680cfd124f5350a9213b6a328a844eaa2	1670155293000000	1677412893000000	1679832093000000	\\xcd5e471c6e84f6d78d12ac0b02dec2c37560b9654bd9690cad2016a79047eddc69d2cc568986b81e2b099755107916b61e71370ade777651dddbfcfa4db3f30a
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\x74175231b10c949a77973b7c17272cba1828d55e1e9a9ce2f1c5296cedecdada	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x67e8991c82acfbc9c0913b4ba9bf2e5a5796a610818da173d87841f9dd9561f914207c26a8d93eb5cfecfeeeb435d23358a983a15a44c6702d529097755a1d04
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\xd88d6fdd40c01d5856e776f4e5312251147f2742ce485f9c441eb2b1b40a8454	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\x0ad2f49fd17e6e6d52c62e03eff42f7950c102c96f492744af552aa9750c84e5	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1648383425000000	f	\N	\N	2	1	http://localhost:8081/
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
2	\\x81f6e7eb56d3e0249c7552e00c1f57f72452464845c8e6dceaf848d4c678996f
\.


--
-- Data for Name: recoup_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_default (recoup_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, reserve_out_serial_id) FROM stdin;
1	\\x81f6e7eb56d3e0249c7552e00c1f57f72452464845c8e6dceaf848d4c678996f	\\x90d15f4245bfab27f0194809e14be2a8172cbb5b2aee8ea7a1d285f41f9c0dd58ae7ef5ef8bbeb9e15785d18e4c4331872d6e6cbb4270ef66a1382a4983a0805	\\x37115ade0bd6e107242c45a87ecf66f91ca085aeef0986ae446c7bfacfd670d3	2	0	1648383420000000	2
\.


--
-- Data for Name: recoup_refresh_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh_default (recoup_refresh_uuid, coin_pub, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, rrc_serial) FROM stdin;
1	\\x154eb435e9e74c0feecef9707e0bc6a8043a3dcfc7c7044c7e09711a8f462660	4	\\x15586e84202bc6c2cc180fcff7e3d0a3b9534812fd82d52a7fa17243deb01d0dd8a28cb2b9e8ea68891f992f6525f14cb616ba6b49b7b8f8c0784c9918a34e0d	\\x7db9c408a5d3ea1d4d446db7eb9ee836c6d71030d96ebb90dd62b0dae0825c85	0	10000000	1648988245000000	5
2	\\xd5281a7a6863a27b0f8d282861f703ac7ffa8e32bcbce6db690a9b9d6179e705	5	\\xd858723de1be84c3543ac781c09424131f2f79e6b34cbbf850e5320466b95808738af5f9bb3fb16316a7e962bef53b7612ac05a118340bcc3e078d10c0606409	\\x6d8c021ac79def8ccfda42303cc1c3bb633a9060815e82fb49028805872f792e	0	10000000	1648988245000000	7
3	\\x609f4fe7f18271732bb05d0ff16715b5bf24b58ee18fef609d7f2608e392de7c	6	\\xb07f7773654392e62045a1168f0270ca3eff9d7a9f74422fae141ae2941382451acac3a0a2243dacfabf786cd965c8ee4f7a6e176f207303af6afb8bdbe6b602	\\xee07a726127352bbd7435a78b8b45522d68b254661c61df3ffff952b7ff73335	0	10000000	1648988245000000	6
4	\\x9dd4b35f3798ee0957c355368a4ea26ab1aa5f745cb7663fa11f7a9379ca2896	7	\\x25ad3d73b3816c3bcd16a2b7c20f028e7bb5fadaa363e610fa75bbe3337818f315ace5492daba9f13c7edf41af4f2b41f80c18fab47d5e9b53692ffccdc2740b	\\x53eb659ef314b58a710c872e061ff2af34eb094349da0ae08486212105dcff2e	0	10000000	1648988245000000	2
5	\\x931a0d44b64b028bb9a78d4f70708bf71a6f1179633dc27cc21f9c4b2b6a7ab3	8	\\xff92f4f4ddbb8612306140b83c4de0df167d7722f1ce0941942259b424b5f5a898b065ca6f2919ad6bd246a167a6aee8449a7e656bad379ed6fd29ea8c60430a	\\xc1f9347b7188752ab6b2237b01523abc7e72526188f9619201922a80c4d75d78	0	10000000	1648988245000000	3
6	\\xa1394352919b28d4aecb5be6c3db9a21d36733dae456d4d229221534aa0f4e79	9	\\x2f43a9ec725b8d78ddfb2d2c15a11cbdc819264d26522e6782a319a07272e3eb1c46fc2d0b20d8fb7dba805dedf9a71dccc574e514fa7bb8865c0e476d4eda0e	\\xeef52d26ce4faaf8afcd8243bfa36e96685c5fe42ba893823370eabcdf6f7515	0	10000000	1648988245000000	8
7	\\x3ad93c3c2b303ad85eb5847a90c78ea55b5d7f398087f9dd62a5fa3db9ecf312	10	\\xd8543caa9266ced87f8aa6d1c5b4721a532f15429587c5e3b934e091563299beaae66cc7511d59f64bf949b8d554f85171c6ff447465b2c9013386c84e6f2e0b	\\xc98f078608681358c94c85d34f8e8625c8db6e59a66903c1ffbacc25cbd89a15	0	10000000	1648988245000000	4
8	\\x1eb120347ed9aa5cd61ef66a085cff4326dd285dffb4e70e1c9070f29be3b58a	11	\\x4d48b50771683f087fcba905046925499e889f8dcccfb36735274472e28db9da72ee605c015303d1b04f2b3e5063af814191f8291bddf958bb9a60fa5b98e801	\\xba4659df1ce9985e8e3eb1eb226f70deb0a1a5f28bde52a04e5cf285dd7b64e0	0	10000000	1648988245000000	9
\.


--
-- Data for Name: refresh_commitments_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments_default (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\x9b113bf1907f7004f1c0e428566bee8b577dc41efa5b9af215f45962da974f3f7d51dcb5fa0440ce66f755e5557103634f865641aab837f9d76da8be77c82067	\\x65a1099ffa47c6d27481b171a9977977f90e854f20ee726961d1e2c56d3657ba	\\x83b894aeab108b1f702d6ddb539c7295d8bf3ffecd898d16b195adda59986569f7004b05771c8d1653ede21a4a6f5a6774dacadd0523fd7267b9b2b905fc920f	5	0	0
2	\\x11d16574f57f2539b52caf088a1af87e88e0b1ef8b398d035ce8e5c7bb41f26fc45cea3149f7b6b379014cfc683f76384278f60774d8d6266f711934644ef137	\\x65a1099ffa47c6d27481b171a9977977f90e854f20ee726961d1e2c56d3657ba	\\xc7633e4e979bb932f9009374e89e8d2c573bc7569e618e80399823f8a254498cbed9a47a98f11cc69477d7bc3640cb0676f788cd2207de2e830cde99f6ca9007	0	79000000	2
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\x355ca34ce1d3adadc0b0ff3890f36294ce6a9b9c486741e114337609a388ac4947e6bd7d6ceb4a8e61b80ae68b5e4d98d59c3a1a8cded20e73afd4e786fe7906	307	\\x00000001000001008cb0689a82a384bee4c15e1f5d29b06c4469e3a4ea42b0ace1e9f49eb8b0ceeb1ed91d0fa7a1eda12d28e358ca0f75c1d46aebc0fde8665e37ddec72dd4493c0b43d57bf43f3398495b9288543271d6979f12737f8c21e60604251be889f37996c9330199d4d6e3bfca99a65777de6f568c14f4199e2966b09167ee4ce8e7271	\\x55fda41a2bcf9970bfd4ed4534d65f59917ff79fedf38df49ba5796f63b42c909f17b63a08f78e35bb1a1c267f07cd0fcf00997a31e87cfebdeb8c705e9c8b9f	\\x00000001000000010e6a2768c2d73eb4c85388a0b79bf9b5e76c60c4ceb38c26ca0c00f4706e7eacefe2065f57425ce15057e06234726e3ddd89961460110bd25602665ca7e2720a3bff89068019e3ee6aa5ecccc6d181f863a277ba12f1fe1c0d657a2108f3b793262c52ef9a364c765fe7c3af3de03a12a9c3db8df25a83e028b2d42fb6030af0	\\x0000000100010000
2	1	1	\\x8b4e5671024f7dcbffb4016255b5efc94474b824ec03158b91343a9ff0648a5d9d1c5272b95c208373d1c7241531b5403a769e0be04ca2d3258ec09053612702	125	\\x0000000100000100937332313a19eef50112bb0a5fb1fb0be5916e42ea7dbe3634e82c4e2a3fc74653553c1b6001684f517fe5da9bdeda9c72e269361c3612d3889add8e649eff1f01dcc11bde40d8fbfb4da21e10c355ac6aa0a09412bcf43333f82e2d92021827cd025bfd734789dad0a777401d770c9090cf270bf35f959ee01ec584b29452b7	\\x50a18df658c5141009623e0cf99b4c0d31edad8ff1f851c61e0dc77245c9e79875ee637feea42c63b111d5d4f7018b7282e572301ce0ba997d0a44f6b4d35668	\\x00000001000000017f43b6e2688f4fc58be59502aff8e43500acfcc532c4345f1b07108ece35975edbdcd20b4fbd4b09b1f0aab82f48d1d44a1068a7b79a57f3f971e79c9c9dd476c35cc9108a2f2ba05c514dccdf9ab33b49b7e12e3ff501769dcad07f691fe38dfdbb2f0d8f882c5d7d4bb35787bee123cbacb30c210ee806fd8fd281d94ae455	\\x0000000100010000
3	1	2	\\xbe00d29b9d108c1a28481d3d392844c19400f104aa787958c3789b12c26608add17921e441238774b0dee93595e4e711e60f5d45e84f40b11969ecbd12fdda0a	125	\\x0000000100000100ab5ef5b6762593c29d80d26c89e37a20bee72ce44b10851c536dfea6b98344d33975b9ec72028d63d3f276e734ba307f3818f40721ff6f27b6c7185dfbb8346e52cdefb47b3f4b2781112c9f197a4236a43ac55ce4f808a1367ddbf696c8bb9154139418cd2ac71d65315f83598d1c7385d8c86969d9bcd6ad96d7d90dd7733d	\\xd79470d47854d0307dcfc6046cb6c2e0c6cb34e4e088d8a9e35deac244b0648db069062892aed503929dd20d8bfa69de14b93882742bbb6b845c5ba9c4b1e080	\\x00000001000000010d252da1597b1219769d42a032ac145d64f7df0badae74734f45074510dd9103acf5f48a7e53d2663096a5ed9b56db99d02701d9e88594f6bf269af9a81d767c656e4655a9b72eeff8f7e8ee78c1e15b078f6d17acbfabde7650ead3b563ef168c17e66ebb26d9752146eff3a2ab3c1174125a6b8bf5c3722cdc5f22b058466a	\\x0000000100010000
4	1	3	\\x9b24907a7df67908e8c28b8921a3d44ca463d5e436a70c441bd0d13f79bba7241d44948be0ec0f9ec90e84f776f83832c274cbe27e352ea621266abea0e6a006	125	\\x0000000100000100a25db99f364c367e7678e91185e9d9a7acb0724f976af2ffb0b9e25de29f14ff9dd319dbf4ff185e50b807c887d03137eeb756adcf9dbce0c86e6d4ea7bbabb77fe72fcf244dbf54add970bbb66c77a656b29edf78969e9cd9e0fd7eb610e0fec6cbcd272180b69b6399283010fe589496808a754a1023dba4fda5adc2bb7eda	\\x1d5755c8c6bc9a3c5966f382bfcc3c744ba8220c2a15f92a23a068180a89e187f52c68fb973a8c18cea7a0b80e18f935a89577ac34afb6635e8b1ebc69611878	\\x0000000100000001b48d837751a3812a312b17335c56433346cc04406778f097e7adc193660791a8c9442da6e01b6054c8826d3a11ec53f8b8c58c035945a9408b54dbaf84833ab038771235befffc256d93261962432622b8ff2dbc9b7f843e20e888c710ebacc3da99b2aecd390ba7518153134b79a100c8c54862925f36ed00d4631a59b78d8d	\\x0000000100010000
5	1	4	\\xd4f3ded382e82818bc524e94bd912048bc0b7918717449ee850b6f89959ec2d39482c8fed79f19f7fb330f73b6e095828547161fcca5b32028955464947f4c0a	125	\\x0000000100000100ba62c12936a73a48d24b7375abcdbe59805953c3665f274d1b959642d049076ecca278e5a3135921f65699c682b1c143678ba1a6d1184e85a0afa829f87aa985ccdce1a6e7953b7af84a3d0c0eed2a98811bc8d34d29b74a467ac23daf76495b23330b8c61ae9fdcb6bfe39c28911f9f278c89a008d1a0393a7f3bcbd3356079	\\xc91ddde201f4927be5594a74b7c466a5c99a4e58a23cdb50f770cacaefc236844ea8c1920df69fc72738cbbd723d89b3918dd392943e830cb4e9df8a150db838	\\x000000010000000102f717ef81a0ec4256e90e16cabd5e3e6a00ee6b33d34a94d6aba42ff590190a5036e3e33fdbc29bf78810d13200ac6c97fdeb601e7b4abb2e0cee9974b04b28c03a26ce6cd2c38e6cbd4d345e06a6e78e78c87e98e04db1152e2ceb1623b9101e8ac55d97b7e757b2427fa0d557f5fe4e052405fc67d377e2b485f2fa822a57	\\x0000000100010000
6	1	5	\\x486a86e157af0b02fd13ee3c4c3b7d06af45690d5bb340c567b0b9699446740817a20390eb8e27f77223f613ea5b4b3ad2bd2279ff4e9e1860a9789a6dcd840d	125	\\x000000010000010007713fb72a16afe77a833eac1531caec77345eb227b6217bd8d1fb08de985036f7ae55fdfb808cd418547f70f9a1f317961a0f1843c7abce2fbf6e0226727c50ee7bc1046442c98db1f439b755c41bf96bc82762fdef95bfde09f143c3fe014877b87dbaab824b3ea0752432f3a346e8ade4761ba2f5c0d86c26a4ce81c61c03	\\x6be2de6671c4697375a726945fea9ca5af8b9afb35ee7e7fe8450e621a93740f06fdbb2569fe0b1384c6e1c6330359bea1f2dd15bcdc9251d52ef137dbda77d1	\\x00000001000000014fd41cfc10fb4ae5a7733c0921d28ab93cebf316bd23cf829212af0be35800d1e5e6b0672630a5a09a52caba455f5d9c988ba4ee27bc6138a6e38f2c14fd92af1681928387469616d009f6a52109c46d5f3e390c3abab5dfb0b50c33a721da44772f23117b2219abbeee0e9157fa1acfa32a81952070f179341637058f7f8a11	\\x0000000100010000
7	1	6	\\xae926003dce13ec3bf1556470567a785ccf1b24aa228665ecad8d6c936b98afb370c061faba2a5468439582f10758a1b3e97f32b515f94163c85d5fe26c7520a	125	\\x0000000100000100172884273dc2e51ba690644746d91c2d0aacd5b03e3a526efe0544051b7f7442c64277b3e049ab28ab13ed74df11e92b76d01e8c6bcf0f4e4153513cc23f6a54dd9a2f00408596081ecbe229ae01a43a3fc1eb6ef0efada83b9d82222c1da457352dc7fb0bb9a189ad841d79d9cfbdb364a6f52eb29771a3cfbd17e878e4c7f8	\\x9cb89bbf2604072eb955fd76e889ef0e8f556a84516a3b6e60771b30fbd8a19a7363c5b491d68e6606845e2c7cf97e993e992091fae01431a50ed8c46de91f76	\\x000000010000000197dd5c011ea0f7775575e85f53dea09f7fa95e8ef613ab03a52d9e0cb753253b8e0c685ea8d5bd06b50b3453386da97c21f2024441b9cd61322a8417c2e8a6d9c58eb7ce2281086678a665eb80b36e2773ab5fc33e2863996be20b46faa2e7117bb0502f18d6df2dd185a9c440a1dcc99daa52363f8fa8a9b23c5fd393dcae5a	\\x0000000100010000
8	1	7	\\x182fb28839b0483699fb03cf604a2f7f31b3d17e82fd8aaf6c9e69d5b6feb221c6a1dfa8ca77b977bd53d92e83c0c6df0b6766a088e0c1ce0a341770f928590c	125	\\x0000000100000100574d11881131171e3f390e82c9dd5df3f0dea3e167b4d9df8b3b6f334d5deaf7fd134515ce66f22d4d0589adf54965238b817eb6632e0814ef1d798447110ed53dceeacc6ffa32b997f538dbff7cae9c2f1007565ac434c71fddc7e231d9b036c01ada3dfe13fd8f882c024bf74cf2982080d0b015b5e498dfc7ba50bcaddeee	\\xa385c1a4ad6c6d39bb867c83fb584fc54e23518eb7a625b2e0dcbc469d933b6df9385671f6855203ea49e20a0120f465222e0a9b1a244ced36d15ed69541511b	\\x0000000100000001b2c7c6a9ba4af012dd38b8d3a2c45ae788df25973da43ad43a42b5d31c8fd89d5cbecfa433091ea33bec7a0c2bde17f80df81521c81eb3d883705a47cb87dc99a2a36cacd8467985482d2f27ca6df8bcd88d45471262dad0f26c810f76f8a69bfd9dea5b50a7c55bf605d96cc2048d7da8759c62eb10055331ace301247c6066	\\x0000000100010000
9	1	8	\\x7a4e279485b8f8faa46ca5d22fb86a066ee77bdfa7f550b7243610ba726768503b8f4cc3c7b422b69e159f73cbb59a82338590d45d3a83829360bc231f82370d	125	\\x000000010000010083ad03d88db4ec86dad859b3035dfd7d1ad3b36729837dd764bf04ea3f9111e0f6b6bd0edcccc03328b1f4d996dd625c34c2224f4967d88be5535733243fc51f93a90337be4008128331a775837d83473676c1c9e43c7bfeade18aa3d1a990365330efa4ef07c080d97ec903d78a85c4312c49535296cbbc3f4413abb45e4cd1	\\x48b154b944675817ccf024d8cfe47b32f02d5fc4258de539c7cb18b172908510acc6c709f5c5cf93f683be30f7548ed242782a3f646b504d714e0c004513497e	\\x0000000100000001b26ca092448966c9831ae90bfe78cf508a0268b8e11d3f598373ea3027ef803b9f9bbd26f07a7bb1747eee35a3f26aa1a001a07dd7149c03bea092ae76a63e2fc06d1e34eab218a0588c10fc637c9c825417058569f36aebb707e00615320671fd209b44ce6bda6ee257c98e877c37315b2e3210cd47caaba18a4efadbab5fac	\\x0000000100010000
10	1	9	\\x923ebad84b671d1060217915e4d484213badc9dc5a90e7ce9b7b2c454fd8307845011fe8af09d7209badf3d592a890f5ed74b5411293faae6bda4b5712413401	328	\\x0000000100000100ac3de5f1a88a62cc0b8e738514d6ad70d5e2fb7e64770cd3687fa88ab97eadd58a5a32670515199e1ee1ac271800b64e7f8d77eb867219d8fa5409e2c0d38f1d339c44f03e01e47de739fa368e7af93a9ab7cf321c9a17b064a98aeeb465ffc89477e5763c25d2da4acadc230035f39ea2a219f72b679918c168ca02049bee61	\\x8f28469ca7e6fec2c2e276dd0465f0815e12c4a50e17ec4fb6014ec49e1b3e28fb216cf064a4c4ed471faa370f2fa11fb0384372a765df201437b1f501ab34af	\\x00000001000000018dca390552c3366c46135f34a4e19aab1da78611615326da1c9478431c1f1e9a6d669d89f1fe1af735677f09076490c8d4ed5bddf1fd62453395e5ac2dc51a28b86712c088d284eab3578b3e8839b25e42d399729af55c4c50b97a3139116ba9e69d15b63f8b8037b7b265583fc8a819c3a378b87e6330d2785ebcb972bce0dd	\\x0000000100010000
11	1	10	\\x913079bc0548e311a88fb369050a9d98e1e091c4935dcd2ed07f37b4c93045fd192d38d13ef0118d5b70845cab715dae2636143bf84b7e2e8cfa798888657406	328	\\x000000010000010082d0cf02dfcb0e3121b72b0e05d0a2de2b5d97a207f6c445a049e401c8bb73430433022d4c30b5b88dfce5700a534d52eafa2d4bed5523a9dae04cd802f7b04e63c09bb881b85c6ce6df0357d0f5b96d7dfd9d904c1b9a2b84cb6664e56da2cfc36f705a086247208bd08135babd7b2e71f21902d6a007202744a7aa2b18e826	\\x413ea2e70b9c0a48c0e554c6a8136cd4f7a6c46fc5330c20e28ddf4352946dd52cf8cd6e28b0eb5622180d35a993297b4002ccf3c8c695a64b4b70c43b2f8b41	\\x00000001000000014db5dc07dda1252965938fe35924cb194b7549f3b2cafcdb1e8a75bf35577567aa7ccea15cf76f7c7c40b2b400cb637977d66455950038416e6cd52933ffe70cc3a9550a0d51e7cbe60756650bd726683bb83d96d956f27ab0752c31bfda51eea048cb7635aa55e708d7565c56d58b3b2d7f3d0de0926860a6804bd8b49f8fd2	\\x0000000100010000
12	1	11	\\xd168ee346cc33079ada4d3d271d152f06e03aadb57cbe4a9d3e720df117763213f5a854fb972ac44447264d668b2b9493660b2815eb50a4b9801ac723e3d8b0f	328	\\x0000000100000100424e3865d19eb35a8a13569dbfa0c775c26e68dd00da3f494b00050647b86a38e977247e3f232a3acd8c476e929da3954a550fbbaf0f7080e820bee13e1e4d45196a757a4a68c9549c9c8a16ca270206af973078dd7ad29460aa504c1d26030d2d83a259359e31e67895b13dcb835ee3fc1730bff6f1747ecde8747672de8e22	\\xf9f3463c0079ed24cb517390559a4ee3959b0c48ef01f26bff9c155a8ed45d986e2dc6233f08d5aa060226ce1ce719ccf742abedc99eef087955617f6fb4d2c6	\\x00000001000000018c3ca48534c61c9f57bde6790f02fc18ae1524b73d27c51a4df117ea64911d7c6182bb17c84168bc1d495c977a41aa8676a101b22be95fdc3bd6499ad4b7103996192b7890b84b88479bdb649b0d8fdd9e6fdbea2f93e457fb5663cdc6d8ceff8fbbca9bb2a0c167abb8a454975588a427fdbb8c71fed87c4e1d3faf510b7b91	\\x0000000100010000
13	2	0	\\x1303d5b4497313d145a7811fe29f8b162d63495fd2ee71d3e8b05ffb0df83a49d4d14a988a5f08e2a7c53f41a340a677d6d41ac6cde8861266e3f1103e2e920e	328	\\x000000010000010001c3c507e6c3194b3e335c3d7ebc47b1c80bf032862a5cbe2cc54bf7bf27acdbd9e26e752e839f7eeb91795b095eff46d5e20e904d7dbb43e94bd627078f396cd5fe3f7361bb688f91963afcfebf6b1399b3825aa7904097f7e250cb8893af48825cec2555397070045025a544641f1c141d1535b9486422688f7b05b7fe41a3	\\xc2faa0cd2cc6851aa908173e96fdbe9fcafcf16e7f00cd053e96b1b2a762274e77761b66af5020aaf0c6e542ec00205fa2bc15be66a9bf30baa6e429bca3dc5b	\\x0000000100000001abdb2abcba1d0acb47afb5fb3789dd3eb5c0be19e39740e999d0f2514b3e44e08b35fb14acc762d27bd8c46bcb74dee3118a4b4772d597fde8e924474aa23cb755f9c7d1eae10f0e6ceb58a5616ce99cb4170cb72e08c3998a6c4712095b3b7925a89418024ed50c7901bd03e6a7e561dfcc0039a8c2d7f9af7169f78528c70e	\\x0000000100010000
14	2	1	\\x845b918359bd2d8161858cd4c5027cd92a523df04ab8060533077d8bcc84e9f5951460b094e3955c9bc22e99c1b6543287164b46fa98e25ce5b803a628ea9509	328	\\x00000001000001006164af04c4d7db0c8e6c8f308f6c208db199bb393ed065a5bac302256a54b06ee02206c539525d160a3c0b6b619d17303bb251a103ee6d34ee89dd6d17971010fd3e4a0c13ae209b4f64668203ba23c5b1eba76a78a2a359bfb76a63a24736d3605308f58c54b69d17667412da5521c246970bfad7ea68d41efac13ea6704564	\\xa08591c03b01ea99e68c42e24f927e336fae1e2c1984f65ee5065c1b0616c313d8b2b111669c179b7ba0d3685efe078cf3c5c77221ff611b44f868ca8981502c	\\x0000000100000001a98549435f6cec10d23d88e7c86d5ba523d5a2acd50aae40ba35558f950eae4b9ddefec6674da62623b227f949cab53e6893169e473b44903f14031ef1739622f2ea1ce912df73d796471c5b86a4f329a4d26fc069e11298f1b5483031fe535c3fed54ff82c2298e3a013bee5b40b01db2cd8da625f55af4db29cb94ea471307	\\x0000000100010000
15	2	2	\\xbbb2cb18ba439721da457c83a20cff170b7284ecc0ed64a5b6aff1e8f4794e65864df3cb3faf303ecb13825e4fc71b19e24be3e74751a1a8eaff204c9dba910f	328	\\x000000010000010037b575fddf86c7edcd4a83c86e202ed4c82fce364d0d4fbe6879688fd228dca2974102cd373b14e2fb2137583e33591e7be738b32e146d6d679a3f560576c69e846830974d67278d01017ad760dcad0ba08de07fbf572398693a2db80c564b1030bc2adbdf478452a6ad55c66209f74e00a1e1734a535ed674eed95e0e77a08c	\\x9e1fca14bbb44cb8ebdb3a8454f10a949389858c05f922f59750a48751ff7440d0320a08e03bf30b61c7f77f45affe2f4eb3e6f02144b29b216389eee703a3d4	\\x0000000100000001bd3d0a04d0191d84269dc15063576419e2c7e2a724844287a2e3d282d23a1633eb70eff91153fd26010a0a13e4734fe7047ced169a3398d53c1a3d810575ab0c78297ac954a467036773c45742f93874a684a29bbca0c1d22c440eb8f38b4a805fbdda34ecd7d00e9991908bb97495f4207fdd778de779eae6987d6a3c8f38d8	\\x0000000100010000
16	2	3	\\x3fbd0e90c1f185ca34f687013e3615ad513d8b1a32046e749a8c03ee5180718c834f6388b5c6e777a8e5efd6ef39ae4bf015562482f1ff3858f65813e6c7e607	328	\\x0000000100000100c9145dbd6b39c1fab57e6b116e96f96c701be01c68381f5e28e3f070ac9811485ffc3ebb97262ca5529f9acc044802804b4387c63b598e80af7902b83e96efb72bdae8b31a12b79f25003c7acae4c954ecc18a8b44cc0aee681ec9a1dcca98966d8765b3d1c03a047307c323c2f13f8b88355fa3f04c0fbe00f7608608f5ed1c	\\x1a35f9d2a408f17ede652eb17624b58e1ef99b6ffe5e8570ea49fc4221e2e59cbfc77e5b1f38babf4591f1577666e83431ca80ab524c86e9a4fc7fe3f76a9c2a	\\x00000001000000011671c56a8015946383d2411619c2d91661e0af606eaa7cce027a4c524e6d445738ff360804bb553911ec73e00761f71796c92907afe3c7da53a2bb9255308a211a8783731fd61678af810a609bb520b8c8a6d9bb0adb4f61a4500309d88354b5fca7ec390071c0e1b29f71fc0773461f8c988d08c5823456cb827909dffb3f45	\\x0000000100010000
17	2	4	\\xabe65a6e034fca0773fb3a8b9b4fac3652f4c991c174f3c6dc29644a79f30bccd94b9a1632968d59798b4e3067aebb3889b0c82e970f37d541a88c161c711b0f	328	\\x000000010000010079e30b9ecd5c6d0b6d172cda7e4d19e24184703a04f3d94658cb9ea05177e15687dcc5c211bd651ded665b8e5040c7c0c009cc31279bd1c532c16e73db5e1aba0f82c91db53c161375d468a21369d5791b258f01f6758c92ef3663927d2eefbac60a8d263d1165fb084c832a29073ba72cc32a2e2c08f06895eeae14acaee95a	\\x801e9a5f48f4521d46ecba4b7068316c29e9b722bbe2ad6dbeb092a3b28fbdb1b6fc5e48e4382a8f127bb493f10601b390695451e799ce4b9d19c2d5c03433d3	\\x00000001000000012c12a39763ae47f03e214a35adf62637f320849f684ce724702910c31ed76777e0bde1d955dc5b0f7ff3d882ad5190b539727b0e96a1762996964169a293291670a11f769fdc80c765dccbda32e321b8329e3ce86edb3e41e3ed73b3d9a6d2498196b1a5f97d17af1eb899e92e5f0aa23c1aa0d300d8b64c8cd246c06036ff95	\\x0000000100010000
18	2	5	\\xcafe8a488ecceb20b2fbc02302d106e671238094425e7dd3cc7cc6d8a996284b1cdcb5b9ba0f08746214529a8a856a79688c768085b5dcbd660cc197a8906107	328	\\x000000010000010055cafd7c49139b7ec6cae70f8506de7ef656be2da0ed8b4d65351840b2bf8197943fdfadea34e385f78283eda9259a872b137ce2843277151a421343a58e126ba47deeeeba2858d27551a278863e79fcbe5ea33c87766059924f799da216f8e245209e954cd867686bf74acd9e20e038e98ca40763ce56bb662d3c995afca58c	\\x4c3f331390dff013e80c4f21acde9df3edd114848a338e547da23f689bdbe85f4cd6288d66d3ecf5650e229f61eaa8fc4960205efcf429eee41941a8d827eee1	\\x000000010000000159611013af8d05a9e269ef4332ae3a4902fb888edb0f7f9611d6cb237ccb7d4221bb6b7d086831e890e14608a93939867e12be4d45f71cef9174ee1756287915fcbb1a0a391e4073337e5e890ce8c9c2b93b82d09651721c0de3cf08eb31ab508cd57a801dc7f40655a26512874bcdb6d0be1ff069660e59799f2708034ef5ba	\\x0000000100010000
19	2	6	\\x54b94e3b20acba6cfd7bc96ea7c5345a842cf7140bf9e27fcb802577c626e6e5054aceb3b82977eabb833c296e25cdd378814da80c9c52e399ed9b227efc630b	328	\\x00000001000001007025e10dd2db25bbf6a069b23676ca0996ffd8eb660d53158719cc4ede5bbb7dc9940dbe7601095f6ba3ae87cdcdfb5241f7f8fd8fc27e32edf33dd5545b549eb32827f2b909ff1c328c0a424d84745675d1b0c71cb5f3f790df39797304facf89f58be3d25148a7efaa33a77c145d574b982cba089a70810cd307bf775d7f49	\\xc41f720114a73f0898b6957ecdca2d6ab0a2c0c1187c8641b7a2673757ac06bddda39b346838d622058b9a326e4c81c213b49905a34c7715d12f3898c5840bd2	\\x00000001000000014313b6a7476a4822acb98fd978b9fbf681616a7cfc297527706e8184dfa64b97e8e7bebc0a5dd1cd611db06fb2a56fa9d0383cd7d2a4ea760ca2709c3310d247bef55e95c1dc79d924dc0fbfb54521b7d951330fa9094a3b871ed197916dcdba34ba6b20a3ea20e7b245668db0dc73e9250d397ba760a1053f479687ed047048	\\x0000000100010000
20	2	7	\\x405df6647c1ee3cf3fb12e647cd2cba9c201f14e9b9721ad4a2687bc83328798c0be8cfa67220a6ff76794ce84b5d12bb5f455b7dc777a9188d18275d9614b0c	328	\\x0000000100000100bc3a156cb7256b2eff804da3ee4d9fab11a1a974d3c4cd628e7174d8842c4fd6ec35f28197d107f705598e018ec9651b47f2682f1f15fae930bd96009aad976f711e7b6b4df24d20e67dda0f2360bfd83cd65a93e625dd717980edd03c5214c10e2acede525839a017fd55518542b2bffca66e59fc6e0ff14ea9bb8a466781ed	\\x51d77da50436eda2fc7c183c997fdd1d58deccc977ef97a585146fa3d20fcd5a50907ca5bb16ec5b85b65549031de5dd673b79648341830b433884578fdd2139	\\x000000010000000102a4b92aa55d5d8e5ca89765893a6316f64c8a6cd61a670c067ba075b5206016ce6731928f0bb1a4fb3457d7718fc5ba79f8ca046ff81f270dae2b6ecca3c1dd8c98f1a35d39de2d76f843f11aaea3a4a7e9da918bdcfd6bb4e7164657c29b3b8f14e73548cb8a5ad9a4b506bcb166fd260542c0e7bcb87915ebe4b1d8d8d33f	\\x0000000100010000
21	2	8	\\x802702b4644e2c3d8b592139c2283d15ba0ba699c123742a9c523c9c9f7ff1d982a140b210662ac46722a3c4d94a0ef5164a22320acf7b12d1bef9de2cee8505	328	\\x00000001000001006ff43379504d8e51712d7611756186c6a3f9f7e7d33353a3dfa0db70b7057b777d6f56493137618b258b9601efd4dd4a2c962392d2add288caefcef54be9ed54693987683818bc07d8186488e443b466cc8b100eed4bf61b03107cdf898dea32bb876f8c312e27796614ff3752e9c057515cac40e933a912b50461c6d6676146	\\x1c1e1232c31ffcee849ce5d8fc5c130753c32351cca632a4730c065a82a59dd27db07f1a64f3cafc522e1983f2fa49452dceb51ec56203307bc607d9ce6a1a8e	\\x00000001000000014d22bd7cdfa6fd7856349103fe326e78b28ce3e6d15a8d650f536912452dc84a2e4ad1224cb62a934fc8fb0826b59e18ac1c3537513dd8999674f67ce6aa0d85b577ce031cf0d166a61af53922b35653fc88819aff871623f00da17e91fe4714b99820ed0bc6624d961ee2707e7bb67f88dbbfe68878968a2db8c71e1f431c1f	\\x0000000100010000
22	2	9	\\xf6a9152d996f9af82977b0a8fc4f44ae2c7fbdb8baecda64b03eeb89bb68cfae0af1bc1ee94129c784ded6d3710359084c3cc888eee4ffcf2b8b25938ab4d500	328	\\x0000000100000100aa8f3696088307a47dbb41d96b700a373e0682927d9959d4315c5b887bcf35c79e5f73250281d1550339fb2d6f8d8dcf83c3ec1d0eb514985150f9403999a12f58dd5d480a834ab5f1746226d6205fcb24a69e67bc5d3c7e70d3ca0a48ec952c0c676478bd30c5d6dc493ef1bbbc28f6d974a30114b488118f9b609cc1da14ed	\\x44d1ff536f8d7f28f072f48e3281c646694c05717e3b9bc49e04ddee9df1d445c8102fd93a7a63b0902deb9886cad775385c79a0702677d60fa7039c871f38cf	\\x000000010000000139fff48caafeb786b27f6204aea62597fb6bbdfdf45d70d8171a50447cd9e0b3bf2dfd8fef7daf1a1113d91dadac3b3ec641973b02fcba644fad619c2270fa4404fdf16b6a73510aa6c1ec4bfea7568c35b7fa716c3d657a80e831917cf0a3ab35ea739e792bf8629167d3c98c40846642995b70ee5dda38d7d3008905a7989a	\\x0000000100010000
23	2	10	\\x87813edcd9b31aeeee1c6f3fcc3220959fa6f88cb9ad53f8d9f53aa0b985998c0ac19affc6961ad72819e73e964452f87f717c3e4f771a143dd5b5da1967110f	328	\\x0000000100000100026ba26e3423142cd2c46677da064ca703002ee101ddd2aff21f033ce10b9bd299ff80e4639447ef3d35376854d838dc6f9d110f60eb47919e31253a022986579915617b784173fdaac34ec85f020bbae644cadec3925842309fca2a893ac62811000d4c1d038615c6d6696d2f33c31a8125783a317a20fd60e68211a897ad87	\\xa03575defbf824f1e618bee2ec6cd4da0f6e79c37ee9365e507111ba5093458b0351ba899db21a94e2739a0285752b9e0d2c4aa67190a460804d1e0fc7456035	\\x00000001000000017ebacd50cbc2b3e2ec4e1d9ff3e09c211f143343097e04e0ff6d1c9eb3b59dd5244d99fec3fc9cccd947dd9fbce2ef6afa74e82aa4bdb16d95a0bcb2e01c2683fdeeb754808374f429ba3526d0902ccbb8a7c6c03f35d39b62145690177b4662138ce765df84a5b8b7b5b80bd27c3e17f0d53418e33ae9942a609a3f0ac74c86	\\x0000000100010000
24	2	11	\\x1f2a48418228ae79ec505ecdd330a035f55e409787a15e860010833d406475f8873df692bc65000fe59b23bb7eb6cf0b62cc06878976e2d1cf9f0fb4b5965f08	328	\\x00000001000001007076370de67ca4163f8cf81dbd501add799837aacb7d79c1d267305a9c3531537a3f8f10f79831209c28b7f8febcfc4ea84f63ee6919d5a74b8a49f7045807ccc188cb3b36bed3ab862196bbae134f8a07f040cc4e1f264d08dbd5e32db0dafb5a4c5329b7ca206c11e8cbbff19c535f05679a472744f8e610225294ae5f78a8	\\xec5f002be02fb5f3d5088fc34a9d8e9c135209e9bdd784a3c34d8abb04b1fa0f5a9e3a41888c65d2d9aa8b34cce684e0723e2a9938c5ba5a5abdb6578ba32b10	\\x00000001000000010c3b2988ad08c6c70246ff2507a512261f6b0f4474629f28af8ea64d55b343c71111747ff2f6b2505aa402970b9774580f58b43b71cdd0b9539c7ef4aa1bf2fd36fc49bb0927b50a4fce06a5faa323a65a5405c39c0c2ef31d88fccce9b9cfaac669941cce36c0645dc962166b1990983d8a994c975fa8ff58c3a9d1fb09b3a1	\\x0000000100010000
25	2	12	\\xfc73ccdf54e63acb745badeabd9f24267c46a103e1e56958289e09fd9476722d14ed2e064617aaca705cd9d385cd8848a3beef7f5b10d879332f6abed0922d0c	328	\\x0000000100000100ae39b9677e286a177d23aa70a29d0fad64e09766f882e82c5c5473438a0b66447e7f6db2c4c33e6d3c6f4ab6889d5c2e0a8206d857288b4996407cfd36d9dff55b0d13f2edb5964f12e14c2e28f5888105f89f54dacd267b97ee826ff098972e3a665f7b16fb80e0d344952da841c5b7d2dff017f8b728151ac0bee80e10a605	\\x913c6e68467344734440287017762017317512db9bab84d1ba06a516e8997c747a7fb2fc63205a33e343ba4d37e0d1c71052e31bcc87d60cd133ed7b229aa0c0	\\x000000010000000172155339e78f4c4385756881fede4e675318816151ef15511fee9d7535f2ad5f996cf50ce301a2a7e1734cbd7362b4120ca9bc53c7b91183373c35796d3782a520eef51afb817f7a91771eeb87f5ba6d4b250892f571f750616e410d783192f1543801d46b9979440c25bfdebab4eed3cd5c10e3c044fee3f05b4ca3e9263afb	\\x0000000100010000
26	2	13	\\x5efe9661788ddfd887adf2bd1c8f5d544b6b4d8136d7918dd625476208426b42884a2d234813bdc195ff5faae59434a5e8d4185d8ea726b96fcb33787215ab07	328	\\x00000001000001005bb2c579d3123dd826d0910d89921a7d6de472bb3ad75e691bc70a312a34bc860479867143187ae9744a034b45353441719f14f2ed661ec36864fef278cca4c10c682cb88993b6213138ccaba878086c8ca68553cad1864b31b8e4450d79ee5f3998cb3711c6a4ad3ba3d88169d2f187cb8138eb6a2673820cb4b841a61cf093	\\x0f7e4b5121f4c1dba03756c06d9db2bad3dfc0d5bb67ab5e746efd983f1619b3cfbe609c609e0948280be1176bbf976b33e1f8df5e4819e0e60ff7b57def0f4e	\\x00000001000000012f5c38bffa7a6e4c4366c490feb7e1db8a0a3dae18271a3ff723bd2e32eba5def404f919065eb1583f7f3bafc5217d2407cfade117c7191fd29f0f3d2ade24f2e038b3cf809901796efce9e615b02e710dc320fc9aa646302d219509a275b3cb3e2a4f54d2c9851c16763fbad3269ae4054e323435b886d677ce9521ebea7ab3	\\x0000000100010000
27	2	14	\\x12bbc6655f445bb01dbc031889f8c5b9e2ef3179319cc2e7cedf7dd29e8241a75ee399565d913f3a2bc739aab9be269fe8b423cc68386b493560151f7fa65c02	328	\\x0000000100000100054bb22a737e76353023865f8ab36b96dc89065222f1f21031eb764d596c3dc16e142eeef287d67a2515e796aa71b876ed30a6a14d82187131e8e5df13a7380b814856a820165758fb8d0ba467215f5b6160281ea3acd0a5503acf7213df6465f4d74a3f92cfde743e41c0023f8dfee496315ebe010e78544e35cfa5688a9c73	\\xdbd82919396cfb6e811a1b0c4516325679167509e77529b6d822ee27dcfa3701808d9c94da06680aae7f6edcada585f34f99c7ecbcfc13c112ba493543f70982	\\x0000000100000001a28f17f805956ddb3364defe89c612be384919321ed1fef23caffded7fc0d345ed9cb3ffef3f97e8587ff283edd3a242b42a2922bf97a5daf6f36c3b1dc40acd1c81503282505b90b79071e6ac8bfe8a9a00b1fddf348ff88ec7f910191262b66704c2927dfd4d190587390afb31931288505f7a495fd17efb2bd6db7c13136d	\\x0000000100010000
28	2	15	\\x46a5312560709fa4e75ea80dec548c76e83a3cc95defbf52ccd85a5120983ee0268a7fe2dbaf4490c392a0689d91e8cc5cfa3c1a052e448db51f79b8e33b740e	328	\\x00000001000001001265ed90819427ff53b5c6831c6867d27aeafc5b4df35342ef8205b5226ba34baca3e91d9b2a5802ba82bdbedee907c65e8c28954a0578b805d4a608a20beba7532b9a8bbd8c9d470d8afae43f151bd3ade42c3a417893b7e97766d19f89619ca140024a63e8f2eddc9ab7c97f28885cc5b65b5c291f41101b99513abfa166d5	\\x2024522c60e5743af71649fbc4d351efa380e3fa1bad9fb3d81296bef5ab9c8c554ef394f4bfae087a365abe781c6b1d0a9085600ae29819dab93675608b3b25	\\x00000001000000011a8627fd6d22bcd61287dbd9ddcbdb9696f0443522cd00b71d275f468d358b29291edd847a7ec735c83a391419b0ab39bd793399f04c51141c434bf863ebe4871522517415b93f303b7dcb490e52aa6c6aac31e797e843db44870c89783c855059a057ba0bf65813b721b8694e546b7a2fb2867aef46cceb419d1e004d2047ee	\\x0000000100010000
29	2	16	\\x0ef2760ef95f1b82c6c56051ed5fc22652bae1317ab032507dd54cb16a2d3da18c15690bb354e1b731bccde5c11b0e5b6fe80596e88a73c04c059f387f589b02	328	\\x0000000100000100ad04e694448807cb5178f7e248b65a04b8fa3d14f5dc721573c9a585e3868207df441a3095e814c287eeea17b572d700f2c8ec7561b4dab5beb17ef94d9f6cba81d61ef88e8b6f17bf238bf1502999025789f56f2d79ce4988aa12238504ee71f931da956ea004be34a0c70cca324ceadeea15f7b81543e4cad97f86dafba5be	\\xfbfea1fdbb9f6a611d394ddfcf2fcdb7fc7e0f06a312de1fa841ca5c5b94cffa4763cf8cbffd17a3387821dfdfce460970891e9d4485d7d04ecf297cecc0f660	\\x0000000100000001361afc9ecf2db9ffea047179cc12c1648a01f942140719579c12338a9ffc02682bc68032af4e54cdb8b4d69581017a50a6300e730bd839aa1661c9d03f8abd96d78b8642c382f9b75612a6fada5e1d667eeb90042111e971b01f933050e0f83ba3bba5c5ffed21b57a4493ce12edc91e23939906867902d0068128cbb1b70c47	\\x0000000100010000
30	2	17	\\x245f203fb4e4f08d7c78785def6dfcd66ebad0931f69a9fb720bfae14b2b1a3bb44b787ef6628dc4f3892760711373e837a02d236c2e349b7726c541ab49ea09	328	\\x0000000100000100b354eba13794f13b1b4456411faefda7f01a5c12b417ca5df43dd7fd842ff6c1315882f948f030ba45403859556e8f5f1fb367326bef93c88a6b9e29eabb29d47d7534933737442f280c236f4cd9040d662f0dc561f01f3620f431d938ed673e01a8cbd56dbdfdead1a7c07d2f0840be08c62277473bc570f67eeba70c16da36	\\x8e63b97eedf68ed36bd8b8f8de0198fc62af5e4475755c395e68a5f5ae618cecfe4eb67aba8f559d034d08b969962eb92602af87b91a9ce21a27e27b08bdc2c4	\\x000000010000000128c5485ecd78c1830b970cf34629c49fd96d9bf4179cfd44c8e14276ce342244e162beece0192e57bc8184747b3feda1ec746ceaa2c6910dab1da2e68d8e44d93368ebc4ead66aea248c3e07d1de29635438c2334a834113ac6b35a4c2885e03d4a3733cb53f4267056e7573f73a28f8675a8711b87ea26f72767760137f7dd0	\\x0000000100010000
31	2	18	\\x09d0bbfdab1f58efe837211f7ddfb5a86ddd28d33b451c3ddd0f7ed4f116c1e599a722e639c1ebf7ba5744b64480f9d029c17e28e66b56aeaa59da4d0d89cb08	328	\\x00000001000001001ecce78f2bfccb01be10c1900d59c57e80d1d32863623a6876a4c12471bf4c9685730d564daa9a33e59ec4b9ae5b7b1fd5ac00d54acc6639dcdf84072b42333407af529aae0a6e17407ae2ad384d704e592094addfd1a5ec008fab5538ffc6aad2f7b75b06719b69c6d202d19a94980fab52eea9309ee7681ff8c09b6f059d50	\\xd960a329077bc3c214d17db75970d510fd58a55abc17f6627f55c97275a9b503e0187067d2d078c23b9f8c52f9c2276b06ffb6a7f51ebc966e7848113671b367	\\x0000000100000001941c80bc32d394dbdf0484d931fe13d2dcd5522866b8a21693993ac1f7fc3881817dcda251f2626c840067046e45b8db51e030590b1d8f27e94f0f562a4ca382e531826d6f78fecdfd727cc0dc7f109f7ef942775f4b1f0e622c99fbe46bdf6bc2ca11b24226fa1434c899ea26e0ff5b553901b6e637626fc4449567b6702c37	\\x0000000100010000
32	2	19	\\xcbe3ce24de168cf9b577117e3fde8385cfab46058b0d365faba94e35ab750beaef3a674e734e3a7739b39ee228fbde161fed23ffb8872017eb547df81811380c	328	\\x000000010000010033a6e73d4631b67de48e1e99c07af35665999fea39eac8dbee6bacfe354b3f7469167fb732c8016689e118eaf8d8ad3427469515eeb6f6bf578d9532052a86ddd12f0064daf779a201d6ec132942851d949bcdda7532d3c2eb50d0818dde0133a4dc92bce2cd977756e6635939fca463407eff9ea436e6d8d03621103d9e13d6	\\x1c6eac85c147ccf358b7c712a5aec2d2bf4bf49c1e9e756303643e354821e71e66455a21e6bf6eb04431b50c8fe9378620b18f346899d2c2d171d2cb5af3387e	\\x0000000100000001a357398d6fe4ce1fb4f3b2495176e33d4e74339f2add980bc93447a0ef2831ea3636ff99055c1c79fb4f723bbd5e7e6a62b41aba4527b0e5ceb3d09b90180fba2e55009efa1ebe2c7c6824db8d55da6adbd7f0fe21dbd686059067b21aa33001d9ffd1e23af88dc592adb7e57d5002fdba5be7692495efe1db8e90545416ca9c	\\x0000000100010000
33	2	20	\\x972c9e85ad0699b7d9fb111344de0be5b766bc69b83df7f0807f8bf18188002b3bd72f45ac062f6c2ceab4b80f80813633283aa8a7abd6c2d06444410d473607	328	\\x000000010000010080d088153c7156ecaf41fde0fed66e6cccf312431e107e250f848bfd6ac54b127fde3f60174cfcd7946fd3b2bf72523c399dff3ad628c975c991754da1b818d0f41a8cfe756de1d0ba221e27ffd41756a79ac33299f7e442dd15c20dd12d12a27ded33408324582dacbf966e6525d065accea9521240d7aefc589101d71f7d93	\\x2cdf896236bfde828fa3c299f0e1a13c507e1d5923b6406f608ba6ba97566c075e56c102e9ca5af25c4d163f6018bd1fecd4c5af75993b1b6fce003aacdcaf20	\\x00000001000000018cc443be704c9bd2a00b339b648d0f6be62a94b4e0d49f0d14ac248ab2e918c63525b08fde64908c5b82b9edecc66387cebcec911d6a8ac74bbd5951d8c5bb3103849e723a7151423aab3b6ed5a0ebe5329a24f41907928305e102421b93df97f41e7fca980ea8032984ae73d9b627f0139be57ca5a1de2e6c2f142f2a0f0d6b	\\x0000000100010000
34	2	21	\\x3084b2c3b06040e16c52c45dd27be3c93e830a112fec61a2cff1565db49d171d4b3c8f13709a5a041997d49107187bddf822dffc58fcba236324921ec1166402	328	\\x0000000100000100bd77b5552327801247ad66a2fda1ad50eede3497c1457d8e549b654cda6390ecbaf03bd88f9a17c24e783b5d36b9a20da8439ba2560a481873983377ce619d0474a26ba6ff579dcd619127c1d1bf6e04f567027720806c60ab02b39b4296a6c8de57693d0735454a26ae5fbd9c9116e219cf4942835b0528275acac548e54faa	\\x71421c7c1bab608f372b5a00240e081fef3e83548da603ebe7d2e8212f7ff59cf94a9cc35ba39ab4a743586d61194cd4ad9cdf1cef0853aaf69f3d09df604ff3	\\x00000001000000014d39641f839346bab77f0b57eaf08b3603fe7d17227c993e53ca2e2e7e673007339f7ca16a322112b17e9be5c29b6545f4168ab9e7c4bb2bdace1f54249ff700860a2f28bf789a66b9652b8a169c9a4e75750382c53226862dfa7c8e11cd2e0f8be35346aa8b506b01a540b2a06a722f8749f84a718a7b8dd095d61d424fd293	\\x0000000100010000
35	2	22	\\x428b85c0c0d4cfd132bf53e4d6402a2dd05f8cd3c0c0fce385c2eb086edac728df0932847bd60c4c1d9ac603a4674eb05ce383630480e74dbeda098b05b71a07	328	\\x00000001000001001843a966bbf3531c34470f6f9416d02ef5d3447ba2ea4612cd6f154b1f04119a1ecf0a9e6a5d0e1d37cfaf384a6295e15054efaab946f4ac0f9276a7d6d381e77f57927f27d5c9d775180c39b51a9a22bb624f61d0b1e647339f97b97ac711bc983042bc3d558a7bf475055295ba1e3c9f5acfe4cd5a0b531d0050913f17dc0e	\\x9164b856260527976943bb513fbb937b370437f3c5809e8f1253a96aaf979e94897a45e975c68243fe392822cab19025048268305a418b53700cd0cec3a0e167	\\x00000001000000010a5f0d17ded794176cdc8bb54b561ff8eeaee56f212f1a0ea9e93c25c38a6e6395298c4163dc77ade71f9a23239e084362d497c88cc94e128756a52ec0ed1f2cac05cfab6c593e97453088ea607033cf325ba7183189c21b3cced800cbd02531d9946011a50fc55bd3543d51dc12553a52cb1676bb69b08ced64e2e546748fd9	\\x0000000100010000
36	2	23	\\x0ac2204af3c5a6fef56023a1b8d276b92cd966bc87cba0ce80c582faf8fe52c8ac32ca3ce2e972286f6948376580fa51dec820fabbe594053b44e07627af710c	328	\\x00000001000001004cb793c1d7687aec636bccff4d00074f43a90965f22e0112a6dac0a81122f0921e4e8c15f61ef9a847076b48151eeab3237484657cc85f51cc5620d48b39d8010c0292d809667006d19e6c8c789b487033b06dab4dcf577ecdfb614841e39d76e5394c50825c9267a6e15a40fdbc513c314911eff0278bc2bc01f8374c61a6c4	\\xb279923e9eb65843dcc5d06a8a43a3c7fde9be074d83598f572b3e3fc6e2b98950bee7018fd0cabe70c66d422aeda912ba3650802c1908de66c4310f9754a4cd	\\x00000001000000019a8e91b3ef810ff2568cba4efb295dc8ef12aaead149a16687f9bbbdd769573cff47bbb4675dc4190acd04271e215ab0a722801c51f3cbd0c92303ebcbcad85b66d3d0ef52fe0c4df729dacaf742a82669f7ccb268c0c30df8fc12dab45d0f064413ec38392a92fc2fe241a8af0443cd588b4d9987e242bf1b48e7cf0d762e0b	\\x0000000100010000
37	2	24	\\x8ed7c282446f463d4f021e38eca137fce9576cf7cfdea1f322f81d2f69ac195d3ea3748acaf7038520b81eb1494d6b56713d6b8de017e107c0158a30a0d4500f	328	\\x00000001000001002302c56bcfe63cea149bdb37bb7a92d1324272f3a93b4e1a22c73a54f6f6f3bd3085c23c0402af6c2d8fc5004813c04efaa0b95bf2adb2113fa57f9853e6b635c490c5a6e363dfbc489defe5fd08570af85799c761c3640e3bc1a20c9101f940fc2b173afcbc7681aef2ce431a0faba03081c2fdb56e2abba26357671376326b	\\xce92628a9006de8a389126e4bef86fab498fd4c9b470c0f33c6d754cb1060b667c07268a0b1c360e03e2e244c169532d1b5bb6e9735ef70d0f01f7015d74cf73	\\x000000010000000188635eb0b375165aa57355f2d89a7a9846ae9ae640146864ed595a4be51a82b9cc57a2badd004c935a5ab3cf5b71b4e7c94b9e341370378a48186f2813c7a6a6f988c8d784567481a9d59c3f5efde0ec338f0ff5059b6e08fd86588264198ae33b75a250e635eb25466650fcea11081f3bbbbf1c51c17e00aa062b1e39837365	\\x0000000100010000
38	2	25	\\xd8271b425b28b522f49562c53fbf35327e31e43193e314c84f385737df56b18e0f62d478441d3c9eb90de36dd2e70e27d102822eec0d6abff482d62d2a363f01	328	\\x00000001000001006c6d4baf61b9a1fe1d9ea30050441c8a6e3703857a8fd0ec7d73defb648f5e1f9dee2819bb1eaf69e93dfa281e596464f8f7dd965f8f72e90439fab704d4ddbb7ea2a921fad6271de8f22cbe3a3719be59c9b9ab26d9f7a8494e9f226a103b6ffb21d54cd955d3ea06124502258fba18dae65eaa2abfe2d88fb3e2a05498d89c	\\xbfb2cc3de347a619b87d1f4f89793e4d96d448c3af32149169d6e330d663c31d464b6902063864d27c65373cb980416e2dbba664024587fecff45456c9192e93	\\x0000000100000001960a2b68b55df54710479a175b0b7a2380c869c806bc42416d1ff885e06410a47a267ac202e6e1b64a71860ce070dbafae40638710f5665f065cba062a015ebc32225fa913a5da35e336b28f57b6f44432caa437bd11d17c7aaab1686840a56226f0f6c81a678b17879797af50ad529e7a2d71f6baf4f96d18fc18cdc404afc0	\\x0000000100010000
39	2	26	\\x0ddcd73cd56339a78391184c3e64d2550239c8a905e49de233892a4bb2d6956b6ad90d3334c1f1a98d251d54d4787635ca818495d60b6240ff31f3bb41805902	328	\\x00000001000001000ca8b098211a3899ddc4b40bf48ec15a0cf9a1537dc662d26c0c01c2a02ddd09c40a8db6ba83451bbd8736f0088f9d2164badba914dcd663d0a8b2f1dc9535634a44ca4f1789f2bb0c423d482318a5288cba88d2b4cda519723e212d21d00a7eaf8e4cc6192567d531dc98d70ffca1668e86b1b30e931de63d4f4b9cc0b97efa	\\x955132558d14275cfae6603ab05a8bde15baa9e00f0e4545146bcaa24d6db4403041d27af9058ce37a61642d36633b1a3c7692c1a6bc35e94129698fb2ac9503	\\x000000010000000196e47b9e488c89236dc4fa84112c81c830bf980443ca83836fd9d8a25db1dc0ee272efeb3a0135bc751449a144882a634d36144f467bc639f98c288a88690b95f49b0c6a9e16792f14dbdb1480a246d0dd9a245da8f79e3b44eb8059df9115cabcb8992e0d01cab503f42569517cfedabd63e60ea8e7259501e65df6af015bee	\\x0000000100010000
40	2	27	\\x31c96538a4445831ce233738084f65041f3c62b90b46cdd9a5af0a72186bce71ad586d00fd17e647ff8d47bf2c8273bf3724f8e6310311c5fc93301e59192501	328	\\x0000000100000100c9ad30ea48b9892fce03906c9b499ca6086580b850929b16ee42284ac99fa5d0e219a345aad8bb5b5aa3c8eb2b140001a07c199e8f4edf60a4292bb79fcb907209ad769cb594f947bf9035fb0e6a33ce1fc4c58a15908e128ed7b411183241a06bc45682a53dd2e8a97c26cf1462ddf384eaeeb6987f1055ecd8c519a9967693	\\x958e0aef43520bb7012ce9defdf23df9d15863c061d6c4c795d5b7950f1ff0b13deb56bba0fd46c671884aa080fd72883ded34049d17d0900482b30a1131d3ad	\\x000000010000000101b55d24adb9e50f6cf66dcf9d5ee29eacdd124d0a3a8494d933b3c42e4efc2f5004dae37392a1c46a060a9c761ff6f74cd95b45de5ef0e22b2bb8f18bf38b4bd92f1560bd6dfbe827ad4c080220a479a090cf6975758ff403574a0a77c648bd3427216b8d0ffa41a7dd94cfc1c11967f7c94e48217e2bf398214ef5227d4717	\\x0000000100010000
41	2	28	\\xf688088d836e24020a412ab84b67e2093ef3c61580fd5ce4a905e5f55ac21bb836669a52c96e3734ae42fcdcd51c6aa598fd2f9bd61994e369cfa20af0370d08	328	\\x00000001000001000f5794f14254ca79994f1ddc59a18ac96342b9d691ee316dff770bf8a8c8a996d6f9792739286e0c9322725aeb439d41609b9ad010741f200a2be79becbafd8301fa32f9afbd73e9699125fc1059e46af9362545afaa2a8a19776db977d5c22da1181161949f1ceea8ab115ed4e84de0759aeda208ad2219d427fa44dcf264ef	\\x778e1bf2aaeca9985550245da46707b009e0eb6e74db76fac765855ac72fff293f12afe83c21c653986ec387284525a5903a9f782565ba3319f8d976a0dc3d03	\\x0000000100000001a87431d704af1ff787eeb0842f8a94a753635fb8f5a13e4028ac8806bb4c4c983a52b213a12f4819cd6bc09320b9b760c368611ed30ba647e50ebf40722b60baa74691ecab717a56a82bf436f6723ca899c6f27e6d8266042c095ab5c4c5d7a590e87cc216f74f4687fd6fccb989ab31f5e0ba6bda309a6c9c36204befd5ffaf	\\x0000000100010000
42	2	29	\\x4f5b49f4acf3a9b3ca21eb0e0600cc2604b9398fe56175fdd9bef1dbffcb068d3a74c56ab0ce23c6f561f5a9b23b53f14e5a713fbbd225c033507fc79135670d	328	\\x00000001000001009da995fcf9503958fc8693aa37cd3b535dab991a476ec49ae5857a94c06c75d578094a8cff7ac3bb55ae11b4f7b26b86938a4128c6c713a6d3aa0751ae55ab79fab9f5484664e613745095fc58dfc1704659a4db56d8bd65862ad30abdc4ec09fe11334b842835d7991ec755bf2e3f389b1202d40570a1d7b18928c5aa4e12da	\\x855c23112fc5a3f75bc4e20bd6543abd99bed400c328a50853485ced97868b0e33dbfafee51a2c8c75a90ed14344536289ee7feb45e223762d4bbbc0d8aee3ef	\\x000000010000000135287f8cca79996e3879dfd8971cc6407b11f328253e17f6d86ec183d3a2a58ff4355e6e66b048bfc51771be73451097654508c770e0f98adef5669b30799f5c3ac524862749bd37b6712e7489127600601a972608966cd20aec6040d4bc95e807523067747a575906f55369d076eb31c2ee9ed8a499b99477f8fbe3d074565f	\\x0000000100010000
43	2	30	\\x9f7ac8aab44765eee8463dd08ce4db1ac67756e8c47214b87cd0304559f287852813c0a75495e3fde42862c07658932b1b5694e81059f9a845f1f2681a16ef04	328	\\x00000001000001007ff24fd740543863a9371598d9522e9ba887ff1c0b5f8d2f016e2ae4592bcbdb4113588520900f9d4c5ea3b8058cd7fcf9a9cf135e32f368a81ec24b85101d10e5b52f7a4ed261bbe996010b1e72b12e69f33bee9d7018c7c663d98f557bab5bb43b1a925b96e3e65eeb3ae1443a5a09c2ae1e2870148a0b9599184965747bf0	\\x76d4d1f9fdbccda38286b8579b5f3952ba0d6afcd9b127b1add184a49ba6a2f00fad853d0e00fdc21a7ac5a856710ecc7c63d2b9e8aeaec834f274e70ab37e92	\\x000000010000000155e4556b3a6ef449bcc111911a2c61e64401ba02eb0c00b43ff352268db69b0c1c3c39d378558a77e193db0d4736fdcccae059a377fb17c3e2397473b5daf2642e39359c05d9780270e20f9e72d34bf7144e027c794bff95d29e215876c3a5b6b7099557b59815d50865410bbda0a7e62ba166deba4d7f0799ec5a9112dab375	\\x0000000100010000
44	2	31	\\xe229f0475801565a178aae61166ec5b87b6159cef1f85c8bcfeeec56d3c2d8259ae0d2ef8cd10ef1dc379c934a2f83688160832a663201c4e8bb0fed8f084201	328	\\x000000010000010052e4f275849d4342d715676bb63af9af14bb89d0901c455d94885c6f8090820b91551bbd592e53d875cf515a2b38de50bc3ce4ed69fe50a79daf434412804028fe0fabfb12acf3dca166ded3bb0f84cc1636afb22869645256b16a7a7d300756d83aae3da46603b302a47819cff3b0117d2c57c32bff091da88b96aa5ca28ac7	\\xd1d9b0243ec3486b9c53bfbbfb4ecb327986aa7123a98e4c22ac10bae212e95473ad39145e1187697d37eab8ca4d3be508483646210b70c053dda5ced76d2558	\\x00000001000000018365df6dc9f1341d93af793ef587a5ee1fb515c9bf58e511ed63a022e8abcfa0575dbe0da38692b292b483bd74d6ddc42e163fa4de59569187f77884b976440cc3d92c60f961a60c6f69e469b60f41d01fe84b1c3c5a2bc4410e144171da366ad8f90bcf0003cc359b50cb774139addccbd0e38714ec7ed42dddf57093baa9a5	\\x0000000100010000
45	2	32	\\x3e5d285b708039306008e1f68e6177f4ee1bc3e031eda0512f843c3f1fadcc0a19b5877c816fea245e21f6ba3d095f5e974e31646a36e90e3621ac4c52b8180b	328	\\x0000000100000100940fdfe338d03b5ee1bd23b68365bd929e9e3ff05ea15486de041f25b51a9f8709263acf65b297dc4cd3c64abe10adabcf89b952f745a840fba13a9b3a4428e0aada17877c581e128e9f1342af2dae8b2d7c4f556b8c67198a11d6297c17e7533c53886f05d4e5ab1273f90e0551d519bc49b5cabea4a1a3804a46ccaf044017	\\xe62e894205e3a6fe11508bfdeaaa177726010c24878255e9feb774edbbfd1534fd3b0ce60c3b3fbaeab1d0382fd92bfc75dd935ba4ffec812d740e32b20037c9	\\x000000010000000199c731c73bc98190e80a5b57bc5dea23cab4faff7b497bf8c7fc8bfb6a6cae8b5a93df8bd5bf44e42429a0e82c00710d4f44b0135d88f521bdc73fadc6e71f2c474c6f536dce80fd7e157078bf1eab42e2e55179966a5412350978c9b55c6e83af20b76d4ae9416c4d2455c27712a625acf6ff8adbf7885eca4149360a593f8a	\\x0000000100010000
46	2	33	\\x9a92ec68d8989c948370013045ee5a484c58df9313a1d1948b6b791590a872be5373ddc01a2e64089873e45246922eb5dff78ec38098d8faa7d2d39f79c2ab09	328	\\x000000010000010065bb31674866fb710986693b635043803f63abddc983757113816cf625e2fcf306b05877ea61cab6085351a76be0d8d7b23d46651691a468a526ba1b089b1ff6a7b1eea98a2457ffc6c7a093983c40518bbe4fdf2fdc59216808aeb964f94da3fc950f617e636b741b03024b9ebe67ff49b24fd1d04b7c970c1ff1c183624ab9	\\x94ca9ef68d6423fccb355bef78290b50864f3b52ac93b07f5022e49dc9775aa8e7ef56ffd66145c58e5c87e21adc0ec835397920c16b65b40f6ab8a1e1f8b349	\\x0000000100000001265979f7ddbaeeacaf3eb79f757a015fa4ce17fbf1de773c1e2b935a20bfbc9a22062c81964719ec326cbd84e41ffef3d3bd7d4cf07577888d31014df74290ee07eb2139b3473f00bd2ec5cb16db627a3926a3c2924a64d493f72d995bfa3e60050124e1d2db8aabd351654883535c4ce0038883fd3b4d094566aa6a89794d0c	\\x0000000100010000
47	2	34	\\xffd0e347e3283033095560be44afe6f8b935ed74d38687022fdb4f87372c5740c86777ef53422591ac7c6628ded3e4be0ac03ffa4651f1c0c02c8b9417ef0403	328	\\x00000001000001000893a6cb14aff9d0bb37b176c47fce0345a53d6e56365ca36a92bdbbb58b54cfb920c7ac57fb153a3dfd8e19fe92dbaa64e77721e9ad245e1f0d91152377171dcb19de0a19a9d3f7227517f6f994dcf005a2e28049e61dd24b20743f51d38913185643f35961de8b44805e15dea4d2518ccbd59cd6affee70230fd4f851422a5	\\x1eb329a730bac9c55a123acc5623451b490e252b29189bb1bf3d7c7ab40c07e779a4fe2948cb1fb3aaa77605548bf46542a444466b5e2ada47b9da689344e6b9	\\x00000001000000010cff5561fbc3ef8e3edd6d4c98abc4f4458e7ee7a533d5770a1682199d7c76ff1b70edd8901a72a5f775fe6b83699ab5bb66cf080f86d9c66d1a4a8275ad65bd89afc7bf319bd94e1f8c9cfb336461204ffaf90e898163123cf9397f818df872775c38f3bcf6ccfe0c0e0e2d56a1584d98813e57967edeb472e8a8a26bf1883e	\\x0000000100010000
48	2	35	\\x7365e83ba04085ad5049cee9e46f55a9b3ac7b9a74ec2d531d8f9b4882ebe00ef1338f66a95c24ab77b7b9272efda2f883ce4c99895cb7a24abc09651a0b4d09	328	\\x0000000100000100ba77aec7a51ba4ba5b8a613431767e4a139e6d2011ebf0c7c68c8dadc0c3c6a42147a873997fe9139f73e66e049a50e4ce61e30c04e993b1e8644b753fdefd4334b6090c5cc0684ff7c23b392347ad060ad07f733f56c31321206dc29f3b7e96d6952def4be63afdb6262d57c715d637ff601b4172c87e18c5a63f04da13b12a	\\x3e29e7727d687da6721cd4ce7c7e97352852951baecb4a5463ac510400b9e6813a3f1cd3cf90b572165c3b04a09a2c5df4b681a2d39528cb786862d1dbd788b0	\\x0000000100000001c5c02f511de1a7f24c2c11e43f650e05372415947087afcbd7a73ae6d5be4191388ee9ad7831a9491ba2844dc7a9e5fd7a6d10908948fec4dce97e2761c5525c9d6cf85fd7de4a92093d6611e62f8cc774856b6dbdb04548e5ba953274ee75a0551ae837ebf81a4f2ae2b33749b3391d84b21996a0985e30c69f2922a198ab07	\\x0000000100010000
49	2	36	\\x10272613a0d800fcd46f6a8f0d1f82a52a0072c661c07d8d617217182138d15c24667dbbd05efcd521327d7828d2b62f0af314ba5c6eec23aa2501c55c3d7804	328	\\x000000010000010003f0a22ab4bd8abfd364b3838b0f061a902307a7f1697f010486bdd769e960b74d4a6f0dc93361431cc3f595236f5f4e7e78eaefcea5c5fa3499bf6a3558a665d853d597229ef8267607ed2d9ef33bf241802c9639e93d7154329534e5a3bc0c30bb31038dacb1032e45cc58fe3f0f39bf3a8d2a264bc67d68de7ae8085ad70e	\\x35e3f2fcb9f52c36234935e2395b449b88149851f671befa1f03f4fadac472c620686a7dd50e55134eb15bf2ee852982c87852d2e24057309af1dab3487f5a6c	\\x00000001000000010c42f50eb784180de72776d2d581379d5ccbc1247a9247cc2c1500353890f43965813f897279110c9921d4bfc5c33e7ddea5f0190c1a08d0464e77cfe5f3cf63be59b52ec34f5a0f2a53f922678fb9f7f4bd2d6dda6ed89b4714a64d8f1054ea644cade552c5fe4eaaf2b72796cd82df814efd042ffa5cbb3351c8095e94291b	\\x0000000100010000
50	2	37	\\x833fa4333e3048ad9ff002af100b89820ec0a69cf704bb85edaf0c884873ae03b76de36484ba73de4446219fa5a26faa6006c4333d374d1664c3df703ff7f907	328	\\x00000001000001008998243895323985570dfda4147400f6faae952feb9471049e4adea92205ccaefa2b29d112abeb9caca7f363e37ea18751e657212e4bdfe391f73a7b1de44003f0683adf7bcc67d8972b57c2fdbc989f5789f46683d52a104a805ecb5084f0cda27f117e1583883cb6deac93da38660fad5ca0c52776475ed5c9d02e14731400	\\x2c79e830a9cfcb1557689cc86e3a989ab068e8f15510492c7858deea39016deade370b53d02bc11c63a12a5f3e419c9d88c633ef469bcb38b91806a37bd6697c	\\x0000000100000001672a18ca577ea49e4f92f6aabc1a2154af2cb2e064b7c7ecb772564c24865705088428814c688c9f022d5ade40d400a05e021e07cf68788d15fd7bd258a59b5d9d207f56273363cae6cbfc1bdea51bb771fe8b109828716a31ca902191776457d91012fcf1ff671ec3d2844dfc26748847d8b41ddeb79056f9400b36bc89eacc	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\x5d8785d103ef4224f170470c3f8916bfe0a72375b6750ade759ce6f42ae0836d	\\xfa0a77789ec9b59302bd430ddd59248bc8620a0542b229614f28dad5fbd74dc66bfe76ff641ed30c9e7e359cd7c2553d4adc805533ed1e76c0794061a1cbd578
2	2	\\x1174d38e949b9ca95e4c37f5b9bf7061957c1e3062b78d677cfed7050d7d4278	\\x0f0788125e2b0ce929da86814994b1feaafcfde0f4d86a1003896f69adc9ba94aab40e37b89eccecd1039972daf14f099fa4d8e5e66f5cdbb23b6ef89bd38223
\.


--
-- Data for Name: refunds_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds_default (refund_serial_id, coin_pub, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
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
1	\\x410fc33402ef088799f7297226b3c5ed82e08d4093bf56b837402057517acb55	0	0	1650802620000000	1869135421000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\x410fc33402ef088799f7297226b3c5ed82e08d4093bf56b837402057517acb55	2	8	0	\\xaf0473aa50c5ec20d9bee0ccf076c0a442fc0c0ab03a16e7e726a3dc18681434	exchange-account-1	1648383407000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\xd847f773cbeeef2e270c9cf7d483da6ad85db29cf7e3ab5f96b0f5e50d020de4a78e185b0a27eed4e3e430117370ade6d03e2a8c6eb386c60be6a4171aaacb1f
1	\\x3217631355c8db653b8fefaa1eb169493ace9858575904224dce40f6f0dad1d0d16203c1b6bf2e91ba0f067ad3d29727005ed90e287dcdf066d766f6b23bd833
1	\\x24b8d59ae10503d149f1b0e920d2ca2c9ac6f3507a00888b1e649fd661bd8788d5a809c564a4f42091ee2dafd0d6a28d4f378dbce11865eaf133da354a21b899
1	\\xe249468f6bf002352d55da26d473b39b09924f292c6d65d58feca69e7cb897a9ede1ec33431751d214931f6b903ef6d59dbca2ac6d505cf2f8eb2ba4c41e5f1a
1	\\x999bd1170529df4d51216e806e80cdabc6972ac1dcaa6fe63c06e725127b3b0076f281cf625f36f1c065f3c39d05e2022c24ff97d6981a19ab7f083abd9bade2
1	\\x41929f0cfcc66fb0d58096b98e1bee1d9976e3bd7163461821502da0b72f8d88a67c738f7ec2de4e80ea37ee0fee86286b6e55608e6c3d05505868c47f214731
1	\\x96c921cd774f97483add10b5becb0e613a2945aa5b728d044a5eb5f320986dddac0b8b2256791eda22d232c6efb86cb5e1fe19d75c7a7a1c0964a5125064a380
1	\\xdd16f08a46abbe4b91145d2d0481dcbdf4902ac85c2543cc923dc37147e1d1714d073541ee9b01c07c19a5f0f51e799e48b6347ffcb55c2225d661514d14b42c
1	\\x7fc8a990e5aede8a013df9dd2c4efcf1a7a22da3bdc419a3087454e9053c9e021a75f8a39ffb2482c0fcb9d9a24d5595c6d4cfef09300f01a94b06eb92001c51
1	\\x3ffe9ed91daeb94d1120ff929093590f7777ba21f46b6dca607ca050577b50a04758f09b24993584a7e3f53b47dc1ffc05b7b550c0cda10508b2b4f9bb27a207
1	\\xded930a7b7194ccdf439e688429312c6abc698dc66be760b7bccc5db34989e44659dece686edddde8971413386ac29a524578adba08348146eb4927c576b1f9e
1	\\xe3f1f98bbf1844512fffa09da11afa3cd489003e6c15643e63f060a736d7704890ee8fb854ed833551b489a653d61868b75a6bf670580c6c9bad1768854701b8
1	\\x7898941c9de643fc5c7ec172024bc6859d59fc0c20e372cbb7abeed29bbba6b7f935b4a0f1ed624607ae0a30985272c65057c1f748221dce6781638d4632b961
1	\\xd76f94f0e61e473ef73f5f7a3aba3447b8dbd307e3ec7f15e4cc8d45d5749d24ab3c3181b9a2e8523bfdb7b4764772d95d40edaf26c3baae107c48c25f7b5156
1	\\xe0f0c3fa83910a09af7a347943d58477baabed39ca264fae72f10b900359653822eb6f4d5bc1159f71e8f8b38b6c8141e992cce6fcbecde4961bbe80b55afbbb
1	\\xdf67204d394558e935ebf178559f9b6dc0aa688ccdf8cad4d5985e894a0f9510eeffd79fcbf42d72cfff529e0c6a55d3002571edacd5ba67fb890d8bfd42e2db
1	\\x470e238336eee6fc32c4f8e91c0777425e58535602d915ef51514f425df645efdb1d4d903159698fadc0fd1d8affb87d03d70415c617d1aed461e500dd2894c9
1	\\xb7c00481432552908e6b93b071c3a6d412cc6460fcd100d29e8ad0e607a090c5b4f5de673e2dd5176e5134006a9d42c795dbb8c9f0ad33f75f95a38b7fc3ea6c
1	\\x4f5f7b7f72af3a90def1f8f2bcbc5684aa3ffd93ba79356cd039d68276ba42822e22c0e90f3bf5dfb69d91b90825ff95b878d5dfd73dca5f125c27378001c3dd
1	\\x4e78f6173d449d1b59aed3ba7ad16f5d64fb4096a276d9bbfc83ee01c30c9f1da3803c139009f4c07ff9e5763a822c39d635e465c9e6376468f46c55003b085a
1	\\xabacb8543a17c4b95e54ba1504546a4cb3f56eb6ea4c0ad67eee6c75ecd980fa67723164e1135fa9584fd10f50c127d3a248f63536fe26f7982250cc6c2cc274
1	\\xcdd3aee32bd9a976d79d4f07e133ddd5206d4faabf8477466b36e7e4c71662cf74dc4e50d5ecf4f99eb44d2d5b03a2a14ede27a06d93e828a6945d3ed8c1b095
1	\\x241bfbe86464c802205304a744ed0275ba45180e6cbafe1354e533e772ef8b035b999f280fa1a8a7a2a6088e55046c34c39981df0bcff4fea47d197a0ef82098
1	\\xff44f40c50f5e9c724b90084f0c541665e0a1e70203101d79c17381beeae36e2b5e578339f0e04f5732664b3d6db044b03cad3f79ab81876f8c5a10b44b4621f
1	\\x36184f7bf51de4408eadbed7da0585241f8c9cee66584a764baa38fc9933ce98d3d7d8e8197184597b2f0605591fcecb168466a75c6cca1296706aa1a5ed9f4a
1	\\xd26d750c34895564868cf07e49d1a851813c7fb5981b3b36de84c9bd34a96a510785bcfed4437962327edb04a2ce2e812ba49ca0d2ee63860cb6cfac1c51b187
1	\\x8cdde0275e929fe00552a152020402cdb46ce2140dd3a02d466eec55ab0bab9fb6957c8a3fcc96276fdd71b86b222a000fd466e67c8b5b1377bce30cebbcddb1
1	\\x8928402f867abe110697bb4e89d5ad653cce421875e8e72523df7bb1aca7f5dbf6526639ca8d73dafd969a17f390aa71241f780f0136d5a3b245a417dcbe25c7
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xd847f773cbeeef2e270c9cf7d483da6ad85db29cf7e3ab5f96b0f5e50d020de4a78e185b0a27eed4e3e430117370ade6d03e2a8c6eb386c60be6a4171aaacb1f	124	\\x000000010000000120223d093f04dc9a788855be86ab5fca365bba7a8aa10448fd812b07761f9fc90d4269b9d8ac4d9bcfeac4f0b8319b7529674f3f2a9fca9dd375091e09394c4173521b93663bf4c5cc2887fe2a9ee59f6422558b7f8b8b621af294f8bc75f5820e19974e2860c6ccb22470535b8e3fb3b61de5b456de80f55816ad14017adab0	1	\\xa6fcbee1ab8bad2a9c87cc528a3cbbcdd6891d2541091bd983a55128fac4ce83c73b707306ca4b8b3624c404fd1f64a6344c94226eaf6850c5364a7d6b4c7208	1648383410000000	5	1000000
2	\\x3217631355c8db653b8fefaa1eb169493ace9858575904224dce40f6f0dad1d0d16203c1b6bf2e91ba0f067ad3d29727005ed90e287dcdf066d766f6b23bd833	422	\\x00000001000000013eb560f4864c9d2316a081c3ef6babad8a3351cfaf56164df6bde0218af6398ee2d2e0351aaf2e99a55c6ce0e9770fdbc57e6b399febbb6302b5564aeee65af4976b745dfc3d6eebfef8a36baa1558f4bcc27a66e4dfcb11caf98ac28adae9b0036e507f1d6efb525cb824949ef6045d3f557955b547f9d289dba162e49720cd	1	\\xba23a311d954a5e9ddfd4c0daa1149c53a39b55445181c2584f4860c4b5cbed13cac908184d2320742536e9ac3714f6f6ceb59dcfd4e064700995183559bea08	1648383410000000	2	3000000
3	\\x24b8d59ae10503d149f1b0e920d2ca2c9ac6f3507a00888b1e649fd661bd8788d5a809c564a4f42091ee2dafd0d6a28d4f378dbce11865eaf133da354a21b899	279	\\x00000001000000012c36b02ddbfe8ba6cefb1d9e520bdb2ab64cd69604b79698c66a77dc4de5c744031009a3e82c4a482d1f94d3ff0f1e07c0fdc1ac2594dea82fb3136197099ab65179b493b39b8bfce46b1053865955b1fbcd003c8778608d7ab10847ab99ab136211b89c4dcbf82d96d8396915ee8e2fe424ebcb9f43cc4cf0c16b3e919cb1e5	1	\\x73b5476f1e600fb5bb894e57aaa5e128d54c18191a22644a912650189fbfeed7ee3806f2b69e62b5310a513a5a975a2b7b00f26490ebec4748310856c5ce4809	1648383410000000	0	11000000
4	\\xe249468f6bf002352d55da26d473b39b09924f292c6d65d58feca69e7cb897a9ede1ec33431751d214931f6b903ef6d59dbca2ac6d505cf2f8eb2ba4c41e5f1a	279	\\x00000001000000011afb85e5ef23f2c7df15e61d069369a779a5e0ec55d28cac8c94a21b1ef6d143cf0a2e8ddf14fc9dbc0b1a71d9130face35b1f623ed36adf5e8d93b088431cbfe442ad32d9c77653a41f3497e9050738ef4054e44099a4150e31d1c474ed1ad60b2a65c4ff05555863fdf035e7b098d64787d6b61907417fe37b4379f69d86a9	1	\\x9c5274567a453da4568f0d68bbcb0abed9a06e5751f938c9663ec6b0e3dcb7446604ea476d4db6b2d7b19ff074d1dfc53f44d180ca27b8d1e97fe1b89f04cf0d	1648383410000000	0	11000000
5	\\x999bd1170529df4d51216e806e80cdabc6972ac1dcaa6fe63c06e725127b3b0076f281cf625f36f1c065f3c39d05e2022c24ff97d6981a19ab7f083abd9bade2	279	\\x0000000100000001575299e6ea46f21c4103c7f8ee56a476b033c911d92b660eb5d8b49e520b01147ae53921e95b42dd8c64a08951ed2eaaf04280c88edb870d1f7d6c1aaee11792f798cb0f986765f8e67b5b82f81e07f13c7cf61385527cc7f13de5421a4d6ff57fb960bd8e0bb3bfb422e8332829705b2b55999c3ea1f37a5906ac88676e6d4b	1	\\x85ab820283a0b69dfdb04a7199b735c5ff442a1e5d531052c9dbabbefce4762fee715c9fd21d216b9398de3b4f2ae379b364d704106cfaa2e7d712ba9d346003	1648383410000000	0	11000000
6	\\x41929f0cfcc66fb0d58096b98e1bee1d9976e3bd7163461821502da0b72f8d88a67c738f7ec2de4e80ea37ee0fee86286b6e55608e6c3d05505868c47f214731	279	\\x000000010000000197ceaa8620c7f4331856016cece280b46447c90e2f4c77c3144628e8aca26a2f23b4fb300a3099a89a4b2ee4ce5573903f29ea8a6aa44be46758a96081ced205b142977b90ad3ddec6d0d372649a0a6d127fd74dd2306c34befb9c8231e5476724efbd24ea63712a306f33a979d41273907d8da0bf30b597d575e76b86873a52	1	\\xef40c513b6353e4818d517e57c3d61496937234b08d8da7862bb17759501a874234bbabf9fad7b9b5c06c824888b18470d3d9c83cebda1a397e2fd414f80a50b	1648383410000000	0	11000000
7	\\x96c921cd774f97483add10b5becb0e613a2945aa5b728d044a5eb5f320986dddac0b8b2256791eda22d232c6efb86cb5e1fe19d75c7a7a1c0964a5125064a380	279	\\x00000001000000018cfde32ce6babaa766f84cee4fe4b231de2a47f0fa904038f6926a7abf796855d87f79df266cba98df3bebd1f804fc11f8be68288ffc32cf2ca15ccb69ea2746728f63cc21cdc16dcce7da821da7423f4e0ef97509bb5295444da83ff671e5ec45e141afd52e873b8059553aab1bebad341d057d20617a77e9d1121c34937856	1	\\x0073f52a1a03d0665c00bc42c4a7b422e3674bbda764e06f05162489f01da879df65025edc4aafbec044896709b8f70b14261625946f66bc7e983db941638e08	1648383410000000	0	11000000
8	\\xdd16f08a46abbe4b91145d2d0481dcbdf4902ac85c2543cc923dc37147e1d1714d073541ee9b01c07c19a5f0f51e799e48b6347ffcb55c2225d661514d14b42c	279	\\x00000001000000013d70dcff4ccefe932d7f5f3ded6adb2aa4151d5c6e0321f70f13ab070a0679f9152da556ce9c196b914bfb3f7b8ce3315456382119fafb29d82e7a772c896b317e0dfdfcaf41e38736cbffccb6720444eab8ccc13bdffdcf8c1102e608564488552a22a3de8c54d52b3b09df249ec92df5fb400df9f37fdaa3a5a481aed4eb45	1	\\x5277a9e99877852f280f579d9c3f18e7d1099e5e3a74f34c1a122e011115a29933722ec98f564e111c95c97e5fd26b2f4ff0390e1f22b81698676ce87100e70a	1648383410000000	0	11000000
9	\\x7fc8a990e5aede8a013df9dd2c4efcf1a7a22da3bdc419a3087454e9053c9e021a75f8a39ffb2482c0fcb9d9a24d5595c6d4cfef09300f01a94b06eb92001c51	279	\\x000000010000000138ca460151b50d53ff9dcfab37871d078888facf64f2fb535b9891110468a40b71b1a0d743da14a1c8e30c54584c1b12e4ca986b13088674021c869e6a67dcbeb07269f6d0631c65489781f08dd459fea95a9377c190e4b0fbf6d1ed6ef7b376c8f03b665cf1cb2c6f9b34b7026f38620c5896c185b350aee5c9c1e4752a7fdf	1	\\x7773b2c5b6f94ac1ba1139ed25c259b9e7dfff8e55e6f40d1c2a2fd8e2182e5e34715fb395d7bf65d228d0ef03b8c70b8038542b4bc21dff8d166125e4de9507	1648383410000000	0	11000000
10	\\x3ffe9ed91daeb94d1120ff929093590f7777ba21f46b6dca607ca050577b50a04758f09b24993584a7e3f53b47dc1ffc05b7b550c0cda10508b2b4f9bb27a207	279	\\x00000001000000018c6c60a817f39e1e54dae359850186a4545f13022ac74bcea34501f5bf75e92e084ff06925b4bc4d16f91396937d9e0d587159a5ea90c6d103aec940251816d32138ab0aef027622e4dd6746c7be99413e59155409b50f0c029ead7ab37fb679a37d958c661328ad42c5ce269e1bcb9b762eaa0a4ef68e7bb6300780fb4f2717	1	\\xba6267b49628d3c44473ae144d9ede8f592879a129924e74fb6dfb864673d2b57f6ba4ad49fcd32e0aaa31440c48f7409ca993f4de273fbb8137f7afe09b7307	1648383410000000	0	11000000
11	\\xded930a7b7194ccdf439e688429312c6abc698dc66be760b7bccc5db34989e44659dece686edddde8971413386ac29a524578adba08348146eb4927c576b1f9e	50	\\x000000010000000169f4324407d2cabe66694d06310c62b13d6e33d74036c792d94ad03440242ede92270c299d0087023d10c9e74e4a2c9b9306fd1c8885608a83fc2bc6eb8ed2dc9d5f24626d95c28232da33430efb8af249e48060ddd72524693cb73a7a69bfd96367b4485cd6db3a1af1d072f271c185c8372fa3d53b80e2ec6952cf035fe8f5	1	\\x72041a397c0c1454876f8a81527f3c53e09f0dba448b0e3f4b55e62cbfd69b06a973de84f0463bc0865e4a209d408d0a1d95c1be236148f3e4a7406838de4604	1648383410000000	0	2000000
12	\\xe3f1f98bbf1844512fffa09da11afa3cd489003e6c15643e63f060a736d7704890ee8fb854ed833551b489a653d61868b75a6bf670580c6c9bad1768854701b8	50	\\x00000001000000012fccb56ce75eaced8f3ab61d367e4442ccd39d8147ec8d8e9e036f7b39c9b4d9330782ce03fccac5eba6fc66ee50db05ade5d4ba201da986a6f1bff5959b8bff5e710d8aab4e75b437634394e697a10d98bc5a00a77c37238bb862f857b5ca6b6664bc7e89e1b8326135efdf17817e0cd13a2b0512e9e8208eec944242bcc87b	1	\\x82d9a627ee0bfdddf6c4d0a2f8233ba0734828329f7220aa93cb5c70ed91ba4269ca27fc6e6e18f358dee01fff7c244bb4adfbda65696e7b20ca451e9c64e50a	1648383410000000	0	2000000
13	\\x7898941c9de643fc5c7ec172024bc6859d59fc0c20e372cbb7abeed29bbba6b7f935b4a0f1ed624607ae0a30985272c65057c1f748221dce6781638d4632b961	50	\\x000000010000000191210b64ae2b23263b8416c0616007f56504b57d1a6a4669076d68ccf8fa31d4f6b3e73ef225cecc920f5617a3ba17ddbc26c9b8a193f42d34a1957e83824be8227ce20b25a9b0cc65a9121ef860c249f2f6c50ecf5aca9f30be02afe991cebdf4d68e18e320455449368af587113c02c3cc3b0029333623399e467c14038297	1	\\x9851bc404aa9b38be9f04ed448951b8b855882b3d5ec4c0185dfefc14ec4821a2cfb680ecac3a157d5270f67193a322610840f51b76f079de79910653c15ee01	1648383410000000	0	2000000
14	\\xd76f94f0e61e473ef73f5f7a3aba3447b8dbd307e3ec7f15e4cc8d45d5749d24ab3c3181b9a2e8523bfdb7b4764772d95d40edaf26c3baae107c48c25f7b5156	50	\\x0000000100000001a6fc1c215fb9e7e7dacfdade7cfa28dc1f4b613d46d1acb7ee064c4694ece0cbe478388ac3ae6f10287d9b5fd0247b2cea7332cad52937d27ea056937ca394bd6bf6e64b480dab75242a1c3f16eeceab1d981fad8866287de435ab6eb4c4ef754be99e70d8ae8e13ec46b54d15b012a8e607cacd82d07382947fb8f21be6b9dd	1	\\x9da65757a19ae5ac5c1f6749960576fa1a65c0db5bb416406f72b87c094d48dfc90b94889a76b2b01c6ec4379a98d9c51d41ba3bc61376528fe96af84d2d5200	1648383410000000	0	2000000
15	\\xe0f0c3fa83910a09af7a347943d58477baabed39ca264fae72f10b900359653822eb6f4d5bc1159f71e8f8b38b6c8141e992cce6fcbecde4961bbe80b55afbbb	413	\\x000000010000000155f6474cd3d935cf312c21b506795be84dbd2d02a00c77365cd7019b8f459872cc5d22b624260ee8fbb3ec44799dd745004298f288f562f296ec8da0d312679b86f887c00f0e96457e9073dec3922e7be2a10c8c7538cc909a75d5382b9ff5e8b965860f7e6f49220d01e1d5ef93dc3de619e59aaf196b89dc6bf724ad1be8cb	1	\\xec945d7a0ff5237d80193c76cad3613c8d82318fd7c93160864dc44c6f1e1fa22041ac06435edc37f8173de237882a3248224969a9ad8a6c6988b0cc0c21b906	1648383421000000	1	2000000
17	\\xdf67204d394558e935ebf178559f9b6dc0aa688ccdf8cad4d5985e894a0f9510eeffd79fcbf42d72cfff529e0c6a55d3002571edacd5ba67fb890d8bfd42e2db	279	\\x00000001000000013804739a9649967e5cc8649f3d823597549e8de1483c66031bd7d38d3be0064bba71f4230234b92e5649c30fb5f9ffc35e33ed039ad6af8f901aefdee00346ac4471897aa884a7a50d47863e9db1d449c3ac3935dee35e8f7b590e8557fec2b0ba960a1fcba32269bac9f10bac0b705ee4dec3e97938c7779504e2c859ebd86e	1	\\xd7b9bcc20ad21f3748d7677531253d5e23cae80f3738a0615de5c7f34481cad1caecd26e18f9c800a5845ec6964a5d6c4cf215bcfc08224c40b68e8d2a2edb0d	1648383421000000	0	11000000
19	\\x470e238336eee6fc32c4f8e91c0777425e58535602d915ef51514f425df645efdb1d4d903159698fadc0fd1d8affb87d03d70415c617d1aed461e500dd2894c9	279	\\x00000001000000016fbc493232dfb8591e32c72b988defe50bb9460fa233d799ef9bbd4e295587c4ae3b4a0c5aa831fceabd54bd41e8fc81774b4c83b4fc02b7b1768ec87f6c8053c285e117e3b70804610ff0b25971931d04dd20848f72883227e3197ac6d2523cdb9761c7d93f27951267f19be23c83edb7c4dc8d9219ada1afce553297186e45	1	\\xfbf26efa131b739d973d5d969f45db881c6f6b17de45decdb7fda1146bded5d5a4255ddb7bce8ea20d55441ce2a642830eef3974a35325c8c7c66a33fd0f9d0f	1648383421000000	0	11000000
21	\\xb7c00481432552908e6b93b071c3a6d412cc6460fcd100d29e8ad0e607a090c5b4f5de673e2dd5176e5134006a9d42c795dbb8c9f0ad33f75f95a38b7fc3ea6c	279	\\x000000010000000110850c07bb869c678633fcae0e70f56fb16e4a579794c1513e1652bb8491cb4f8944fc06670c5ad9d6dd772b1c87dc9970905e227622b9d1bf866bb521c509af1f2f749eb208004b2e1385ebb0ff3ab06e3e6912cb6010dd20a9e441ba8131b496f65a64a26be73b9e36c805e0dea09c2e940cdf11d62226b5e01dcec2e788a5	1	\\x08a8c28438e10719f499fc9f430ee8250f6a124fbd42da6287acaa6b1658e2f6b846ba1e3b3417b231849b9c62f98283a6b7e0efb663d7e245ed7bf268dc7b02	1648383421000000	0	11000000
23	\\x4f5f7b7f72af3a90def1f8f2bcbc5684aa3ffd93ba79356cd039d68276ba42822e22c0e90f3bf5dfb69d91b90825ff95b878d5dfd73dca5f125c27378001c3dd	279	\\x0000000100000001a5e9a6487756dba58ff51aa82f378f6e4f0fe4881bec5bb8b7d6ed091bd89ec69acaa2fc131137215356a256cb6b94963d0445c1b9a2e4379af7089fd01ea9cec5c2fd9871e253d8dbb8212e40c7ef113b7b3785b06dd35dba2841228ec3f477d29a6b580cb6a8a1c9a657111e38e3760b48d1708dacba64130409ee46f19710	1	\\x19b794d62f5621cc5916103e1e84f21d4d7748ee5ce32ca29d8c5a75b2d298f1efcc598a6ec2f04b174e95137859637b283b7a8767431abefa87fdfae323b601	1648383421000000	0	11000000
25	\\x4e78f6173d449d1b59aed3ba7ad16f5d64fb4096a276d9bbfc83ee01c30c9f1da3803c139009f4c07ff9e5763a822c39d635e465c9e6376468f46c55003b085a	279	\\x00000001000000012eb516bb08c13e7845fba24e9bd5ca7a195a984620b4d7409838e555deb8a6c6a203b5c82d738c356f99192e27115d7c08b4141838928e236c90a9ca1685a672f24e8fcffd4ad7c73f84c5c6546994ada51beea5e624299201242bd2054424161562f80cc47e758091704820a49e4f5d10fb14fba99332c8a12486dc6d0accb3	1	\\x66262f05db70cbea47c1434b52bfd2a4448151e65f9c9e4704e8baf74a02dd543e300a96190cd1c6fedeeda17fdb64567a1151fcbc7de29c4f2363f28588a30b	1648383421000000	0	11000000
27	\\xabacb8543a17c4b95e54ba1504546a4cb3f56eb6ea4c0ad67eee6c75ecd980fa67723164e1135fa9584fd10f50c127d3a248f63536fe26f7982250cc6c2cc274	279	\\x00000001000000011cfc789d9e569da692097083dbeb54a5da82cb134ce9165256394ce2adcdf55cd447523a68e45c7270f1ca9489667992215c8e121cc51965ea25b9f01e9b9509d91bab634cc0be7624ecf5d5dd9ad60ad83070346a848a7bee4bc58e7fc45f2bd36720c32c145bd19a6a93efec9590e2be4155a5d08d13aedd952252c6ef93d4	1	\\xa89ed353eaf96a7e44564ec12c4d3e1b533b63324078692f4087f520e0e407ed7d9c680d224d196a9e92fe2591a0c06327c78970d48827e8526413cc5b8ce90b	1648383421000000	0	11000000
29	\\xcdd3aee32bd9a976d79d4f07e133ddd5206d4faabf8477466b36e7e4c71662cf74dc4e50d5ecf4f99eb44d2d5b03a2a14ede27a06d93e828a6945d3ed8c1b095	279	\\x000000010000000120f1400a0f7421bbbb70d8e6eb99426422b14de7e9080737db9fc1b8c03d46dca06da9444eda4ae683e07306986866ef430aa17d7d5d1b8aa84b80054d4859c8cbe5955e15eec31a1831b27a76fe91e93d295619f5784d23324644f7ba66c0253100e907e723b055bc76c9b20e3db5ec787c32ffbbb3ec5e766dd351b6115f4e	1	\\x36f67e2c0e7d352b8398067c27450be6c040ab80ebd1cae015a5eb3f743f3d3a0c16aadaae459b3c1be928b7d2832d92f28ae37447554bf4b09f0aff215b7f07	1648383421000000	0	11000000
31	\\x241bfbe86464c802205304a744ed0275ba45180e6cbafe1354e533e772ef8b035b999f280fa1a8a7a2a6088e55046c34c39981df0bcff4fea47d197a0ef82098	279	\\x0000000100000001793c2eab6c95bffafb6c0079f0c465a051fa7dd24d3ae8b5abc41846cda58b7910a650a68b47cf5e280e83e06395e6f48e91670b66f18b01edde3bd8f5c0306a4f92f072e9606c2f6cfb5c45aa7171b046ba19838117c70466e9633f260782bf45a1c28cd9cd7dd44e55fbac9a099d8a610512782e3144f179ea3935e6335bff	1	\\x644bb5b997096b43cb17664f764452313ff8afc9323f4a64d32c82cfe3d078a023ebf85b7ddbe9d6d892f24909109a1f1cf562f772b55e14730f8dc3afa31c04	1648383421000000	0	11000000
33	\\xff44f40c50f5e9c724b90084f0c541665e0a1e70203101d79c17381beeae36e2b5e578339f0e04f5732664b3d6db044b03cad3f79ab81876f8c5a10b44b4621f	50	\\x0000000100000001673110410368213462c2b5edf3d7a626c3c4a01152bb23e1ea4472d4f573ae478b456733828bb07a11510d30249da42aa115acf547f92ac0e655e4febe156c985b118380b38d4f8944fa706211e43fbf89d639aae43bcf2b7a29f1d0f6975ac96fd14d83033bc8dc4f79a00238b9018d3a00a3f00ef5d8bd943c9d9f9bdbaa8c	1	\\x1db2f3cc6c4d96fdd29715d53a84c37b069ff52ed10e17448b2fee3601c64efc8efae0f48d0bf5cec4048a64bda4862ba16577f47ac15a476a41982f2b547806	1648383421000000	0	2000000
35	\\x36184f7bf51de4408eadbed7da0585241f8c9cee66584a764baa38fc9933ce98d3d7d8e8197184597b2f0605591fcecb168466a75c6cca1296706aa1a5ed9f4a	50	\\x0000000100000001490e97b7c185b250367758ce40aa7f2621bc1bc6a11e4f8cd52c43f1046ee1f0da91a56bfb49f25e737bf58f3ca594badfe0156e7041c3d1d9af4f4f105c886b9144a6e90a42d3e82c57fbc909cbb151abaab552b10d4c4ef7f3b97248afb17e6d8768f24a23d1954f5cc19ee6db00a03a4cbff84a5e60b399cf1fb2795133e4	1	\\x159f28dbbb749dd18dfcd5fd968b23428e1abf0336823901810c11646130dd569251d86162003a2e6d1113102a6739eff405370d2e064e9733acdaf275487a0d	1648383421000000	0	2000000
37	\\xd26d750c34895564868cf07e49d1a851813c7fb5981b3b36de84c9bd34a96a510785bcfed4437962327edb04a2ce2e812ba49ca0d2ee63860cb6cfac1c51b187	50	\\x000000010000000110c445c8dfa6e050e51f9a11a483a6f521e220823031664d0336229a77fbc722d22fb0e4c309fe8f42ffad4ce6c2fee350574b892c9acf6f6f4487325bba099087233bf7258d1e9a9a8b3c438a98a405fb1ac3e3d467d8f5c880cf12039ac23626db14826f39871d8cf86c2f987f71e4c1bd252ad539b9e3b13d575f7e917a89	1	\\x06be5f3b96b03d3676678018e0601b2422cee6fb57eda12c8d2be7872fd85b5acdc59440b427d44b99659304782cfa5765d795c5b3b69c953f5fbd18bf45470b	1648383421000000	0	2000000
39	\\x8cdde0275e929fe00552a152020402cdb46ce2140dd3a02d466eec55ab0bab9fb6957c8a3fcc96276fdd71b86b222a000fd466e67c8b5b1377bce30cebbcddb1	50	\\x0000000100000001348c11e5a5d9f0e95c4c64764c7c6e4fa96b69f21cf696271a7867967d9b0a318086a23bf524595b72ddd35206058748c1194830e4e642d8644775f62d8b12bce2ce6c7cb69ec0e425127d7134b62a661d9d2591a69c1635055d0095fb4b516eb2b41bfc38ab1128b80e29228fba57649275484520b2085d5de9dee04afd0792	1	\\x5f21879b2abe15ce842defc3658d5fc3d6bddb3d3211da542b80a9bdcaf64f9b832333c23d323808a680bde968f5be7b088c1b0d21b5e5419a462aeb7201990f	1648383421000000	0	2000000
41	\\x8928402f867abe110697bb4e89d5ad653cce421875e8e72523df7bb1aca7f5dbf6526639ca8d73dafd969a17f390aa71241f780f0136d5a3b245a417dcbe25c7	50	\\x000000010000000107b6752ff3b2152041da88206f6e6550fa8468d7c8eeeb9be6da4f63d06f260f8604d9159b6b884d405d457642e8ea6c64d13e5d5b415697451ee52cfaa5167c44a90a23d6f685be8506df9f62fe6b6f99149a3bbb5c887d1267ef56d23b35f8d2f4d7e0bf6c202baf00c83c6afb3f1091e8d6dc5282d0d1f3b3ebaef3325ca8	1	\\x9e3f94682f20415ff2827c218fbd10187bde055555f39b8cdcdc9d1f617561b31de7bfaa0a9827cc2dd64ece0e21145aebfebeaf3d4174a71955e096d3ab780d	1648383421000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\xef3338ed1a44393449caa0435dbdcf4613f616607dee82ed5194abb5de7c129131396b8df22d2433ad5eb867ed424f8a67a2748f99e563740c1cf5683b875d0d	t	1648383400000000
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
1	x-taler-bank	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x67e8991c82acfbc9c0913b4ba9bf2e5a5796a610818da173d87841f9dd9561f914207c26a8d93eb5cfecfeeeb435d23358a983a15a44c6702d529097755a1d04
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
1	\\xaf0473aa50c5ec20d9bee0ccf076c0a442fc0c0ab03a16e7e726a3dc18681434	payto://x-taler-bank/localhost/testuser-doobfhei	f	\N
2	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	payto://x-taler-bank/localhost/43	f	\N
\.


--
-- Data for Name: work_shards; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.work_shards (shard_serial_id, last_attempt, start_row, end_row, completed, job_name) FROM stdin;
1	1648383393000000	0	1024	f	wirewatch-exchange-account-1
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
-- Name: purse_requests_purse_requests_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.purse_requests_purse_requests_serial_id_seq', 1, false);


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

