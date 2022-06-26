--
-- PostgreSQL database dump
--

-- Dumped from database version 13.7 (Debian 13.7-0+deb11u1)
-- Dumped by pg_dump version 13.7 (Debian 13.7-0+deb11u1)

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
        'UNIQUE (aggregation_serial_id) '
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
        'PRIMARY KEY (deposit_serial_id) '
      ',ADD CONSTRAINT deposits_' || partition_suffix || '_coin_pub_merchant_pub_h_contract_terms_key '
        'UNIQUE (coin_pub, merchant_pub, h_contract_terms)'
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
      'ADD CONSTRAINT known_coins_' || partition_suffix || '_known_coin_id_key '
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
-- Name: add_constraints_to_purse_refunds_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_purse_refunds_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE purse_refunds_' || partition_suffix || ' '
      'ADD CONSTRAINT purse_refunds_' || partition_suffix || '_purse_refunds_serial_id_key '
        'UNIQUE (purse_refunds_serial_id) '
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
      ',ADD CONSTRAINT wads_in_' || partition_suffix || '_wad_is_origin_exchange_url_key '
        'UNIQUE (wad_id, origin_exchange_url) '
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
-- Name: create_foreign_hash_partition(character varying, integer, character varying, integer, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_foreign_hash_partition(source_table_name character varying, modulus integer, shard_suffix character varying, current_shard_num integer, local_user character varying DEFAULT 'taler-exchange-httpd'::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN

  RAISE NOTICE 'Creating %_% on %', source_table_name, shard_suffix, shard_suffix;

  EXECUTE FORMAT(
    'CREATE FOREIGN TABLE IF NOT EXISTS %I '
      'PARTITION OF %I '
      'FOR VALUES WITH (MODULUS %s, REMAINDER %s) '
      'SERVER %I'
    ,source_table_name || '_' || shard_suffix
    ,source_table_name
    ,modulus
    ,current_shard_num-1
    ,shard_suffix
  );

  EXECUTE FORMAT(
    'ALTER FOREIGN TABLE %I OWNER TO %I'
    ,source_table_name || '_' || shard_suffix
    ,local_user
  );

END
$$;


--
-- Name: create_foreign_range_partition(character varying, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_foreign_range_partition(source_table_name character varying, partition_num integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
   RAISE NOTICE 'TODO';
END
$$;


--
-- Name: create_foreign_servers(integer, character varying, character varying, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_foreign_servers(amount integer, domain character varying, remote_user character varying DEFAULT 'taler'::character varying, remote_user_password character varying DEFAULT 'taler'::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN

  PERFORM prepare_sharding();

  FOR i IN 1..amount LOOP
    PERFORM create_shard_server(
      i::varchar
     ,amount
     ,i
     ,'shard-' || i::varchar || '.' || domain
     ,remote_user
     ,remote_user_password
     ,'taler-exchange'
     ,'5432'
     ,'taler-exchange-httpd'
    );
  END LOOP;

  PERFORM drop_default_partitions();

END
$$;


--
-- Name: create_hash_partition(character varying, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_hash_partition(source_table_name character varying, modulus integer, partition_num integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN

  RAISE NOTICE 'Creating partition %_%', source_table_name, partition_num;

  EXECUTE FORMAT(
    'CREATE TABLE IF NOT EXISTS %I '
      'PARTITION OF %I '
      'FOR VALUES WITH (MODULUS %s, REMAINDER %s)'
    ,source_table_name || '_' || partition_num
    ,source_table_name
    ,modulus
    ,partition_num-1
  );

END
$$;


--
-- Name: create_partitioned_table(character varying, character varying, character varying, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_partitioned_table(table_definition character varying, table_name character varying, main_table_partition_str character varying, shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN

  IF shard_suffix IS NOT NULL THEN
    table_name=table_name || '_' || shard_suffix;
    main_table_partition_str = '';
  END IF;

  EXECUTE FORMAT(
    table_definition,
    table_name,
    main_table_partition_str
  );

END
$$;


--
-- Name: create_partitions(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_partitions(num_partitions integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  modulus INTEGER;
BEGIN

  modulus := num_partitions;

  PERFORM detach_default_partitions();

  LOOP

    PERFORM create_hash_partition(
      'wire_targets'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_wire_targets_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'reserves'
      ,modulus
      ,num_partitions
    );

    PERFORM create_hash_partition(
      'reserves_in'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_reserves_in_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'reserves_close'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_reserves_close_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'reserves_out'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_reserves_out_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'reserves_out_by_reserve'
      ,modulus
      ,num_partitions
    );

    PERFORM create_hash_partition(
      'known_coins'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_known_coins_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'refresh_commitments'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_refresh_commitments_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'refresh_revealed_coins'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_refresh_revealed_coins_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'refresh_transfer_keys'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_refresh_transfer_keys_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'deposits'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_deposits_partition(num_partitions::varchar);

-- TODO: dynamically (!) creating/deleting deposits partitions:
--    create new partitions 'as needed', drop old ones once the aggregator has made
--    them empty; as 'new' deposits will always have deadlines in the future, this
--    would basically guarantee no conflict between aggregator and exchange service!
-- SEE also: https://www.cybertec-postgresql.com/en/automatic-partition-creation-in-postgresql/
-- (article is slightly wrong, as this works:)
--CREATE TABLE tab (
--  id bigint GENERATED ALWAYS AS IDENTITY,
--  ts timestamp NOT NULL,
--  data text
-- PARTITION BY LIST ((ts::date));
-- CREATE TABLE tab_def PARTITION OF tab DEFAULT;
-- BEGIN
-- CREATE TABLE tab_part2 (LIKE tab);
-- insert into tab_part2 (id,ts, data) values (5,'2022-03-21', 'foo');
-- alter table tab attach partition tab_part2 for values in ('2022-03-21');
-- commit;
-- Naturally, to ensure this is actually 100% conflict-free, we'd
-- need to create tables at the granularity of the wire/refund deadlines;
-- that is right now configurable via AGGREGATOR_SHIFT option.

-- FIXME: range partitioning
--    PERFORM create_range_partition(
--      'deposits_by_ready'
--      ,modulus
--      ,num_partitions
--    );
--
--    PERFORM create_range_partition(
--      'deposits_for_matching'
--      ,modulus
--      ,num_partitions
--    );

    PERFORM create_hash_partition(
      'refunds'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_refunds_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'wire_out'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_wire_out_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'aggregation_transient'
      ,modulus
      ,num_partitions
    );

    PERFORM create_hash_partition(
      'aggregation_tracking'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_aggregation_tracking_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'recoup'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_recoup_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'recoup_by_reserve'
      ,modulus
      ,num_partitions
    );

    PERFORM create_hash_partition(
      'recoup_refresh'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_recoup_refresh_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'prewire'
      ,modulus
      ,num_partitions
    );

    PERFORM create_hash_partition(
      'cs_nonce_locks'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_cs_nonce_locks_partition(num_partitions::varchar);

    ---------------- P2P ----------------------

    PERFORM create_hash_partition(
      'purse_requests'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_purse_requests_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'purse_refunds'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_purse_refunds_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'purse_merges'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_purse_merges_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'account_merges'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_account_merges_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'contracts'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_contracts_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'history_requests'
      ,modulus
      ,num_partitions
    );

    PERFORM create_hash_partition(
      'close_requests'
      ,modulus
      ,num_partitions
    );

    PERFORM create_hash_partition(
      'purse_deposits'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_purse_deposits_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'wad_out_entries'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_wad_out_entries_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'wads_in'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_wads_in_partition(num_partitions::varchar);

    PERFORM create_hash_partition(
      'wad_in_entries'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_wad_in_entries_partition(num_partitions::varchar);

    num_partitions=num_partitions-1;
    EXIT WHEN num_partitions=0;

  END LOOP;

  PERFORM drop_default_partitions();

END
$$;


--
-- Name: create_range_partition(character varying, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_range_partition(source_table_name character varying, partition_num integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE NOTICE 'TODO';
END
$$;


--
-- Name: create_shard_server(character varying, integer, integer, character varying, character varying, character varying, character varying, integer, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_shard_server(shard_suffix character varying, total_num_shards integer, current_shard_num integer, remote_host character varying, remote_user character varying, remote_user_password character varying, remote_db_name character varying DEFAULT 'taler-exchange'::character varying, remote_port integer DEFAULT 5432, local_user character varying DEFAULT 'taler-exchange-httpd'::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN

  RAISE NOTICE 'Creating server %', remote_host;

  EXECUTE FORMAT(
    'CREATE SERVER IF NOT EXISTS %I '
      'FOREIGN DATA WRAPPER postgres_fdw '
      'OPTIONS (dbname %L, host %L, port %L)'
    ,shard_suffix
    ,remote_db_name
    ,remote_host
    ,remote_port
  );

  EXECUTE FORMAT(
    'CREATE USER MAPPING IF NOT EXISTS '
      'FOR %I SERVER %I '
      'OPTIONS (user %L, password %L)'
    ,local_user
    ,shard_suffix
    ,remote_user
    ,remote_user_password
  );

  EXECUTE FORMAT(
    'GRANT ALL PRIVILEGES '
      'ON FOREIGN SERVER %I '
      'TO %I;'
    ,shard_suffix
    ,local_user
  );

  PERFORM create_foreign_hash_partition(
    'wire_targets'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'reserves'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'reserves_in'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'reserves_out'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'reserves_out_by_reserve'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'reserves_close'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'known_coins'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'refresh_commitments'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'refresh_revealed_coins'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'refresh_transfer_keys'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'deposits'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
--  PERFORM create_foreign_range_partition(
--    'deposits_by_ready'
--    ,total_num_shards
--    ,shard_suffix
--    ,current_shard_num
--    ,local_user
--  );
--  PERFORM create_foreign_range_partition(
--    'deposits_for_matching'
--    ,total_num_shards
--    ,shard_suffix
--    ,current_shard_num
--    ,local_user
--  );
  PERFORM create_foreign_hash_partition(
    'refunds'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'wire_out'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'aggregation_transient'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'aggregation_tracking'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'recoup'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'recoup_by_reserve'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'recoup_refresh'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'prewire'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'cs_nonce_locks'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );

  ------------------- P2P --------------------

  PERFORM create_foreign_hash_partition(
    'purse_requests'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'purse_refunds'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'purse_merges'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'account_merges'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'contracts'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'history_requests'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'close_requests'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'purse_deposits'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'wad_out_entries'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'wads_in'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );
  PERFORM create_foreign_hash_partition(
    'wad_in_entries'
    ,total_num_shards
    ,shard_suffix
    ,current_shard_num
    ,local_user
  );

END
$$;


--
-- Name: FUNCTION create_shard_server(shard_suffix character varying, total_num_shards integer, current_shard_num integer, remote_host character varying, remote_user character varying, remote_user_password character varying, remote_db_name character varying, remote_port integer, local_user character varying); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.create_shard_server(shard_suffix character varying, total_num_shards integer, current_shard_num integer, remote_host character varying, remote_user character varying, remote_user_password character varying, remote_db_name character varying, remote_port integer, local_user character varying) IS 'Create a shard server on the master
      node with all foreign tables and user mappings';


--
-- Name: create_table_account_merges(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_account_merges(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'account_merges';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(account_merge_request_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE
      ',reserve_pub BYTEA NOT NULL CHECK (LENGTH(reserve_pub)=32)' -- REFERENCES reserves (reserve_pub) ON DELETE CASCADE
      ',reserve_sig BYTEA NOT NULL CHECK (LENGTH(reserve_sig)=64)'
      ',purse_pub BYTEA NOT NULL CHECK (LENGTH(purse_pub)=32)' -- REFERENCES purse_requests (purse_pub)
      ',PRIMARY KEY (purse_pub)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (purse_pub)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  -- FIXME: change to materialized index by reserve_pub!
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_reserve_pub '
    'ON ' || table_name || ' '
    '(reserve_pub);'
  );

END
$$;


--
-- Name: create_table_aggregation_tracking(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_aggregation_tracking(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'aggregation_tracking';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(aggregation_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE'
	    ',deposit_serial_id INT8 PRIMARY KEY' -- REFERENCES deposits (deposit_serial_id) ON DELETE CASCADE' -- FIXME change to coint_pub + deposit_serial_id for more efficient depost -- or something else ???
      ',wtid_raw BYTEA NOT NULL' -- CONSTRAINT wire_out_ref REFERENCES wire_out(wtid_raw) ON DELETE CASCADE DEFERRABLE'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (deposit_serial_id)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_wtid_raw_index '
    'ON ' || table_name || ' '
    '(wtid_raw);'
  );
  EXECUTE FORMAT (
    'COMMENT ON INDEX ' || table_name || '_by_wtid_raw_index '
    'IS ' || quote_literal('for lookup_transactions') || ';'
  );

END
$$;


--
-- Name: create_table_aggregation_transient(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_aggregation_transient(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'aggregation_transient';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(amount_val INT8 NOT NULL'
      ',amount_frac INT4 NOT NULL'
      ',wire_target_h_payto BYTEA CHECK (LENGTH(wire_target_h_payto)=32)'
      ',exchange_account_section TEXT NOT NULL'
      ',wtid_raw BYTEA NOT NULL CHECK (LENGTH(wtid_raw)=32)'
      ') %s ;'
      ,table_name
      ,'PARTITION BY HASH (wire_target_h_payto)'
      ,shard_suffix
  );

END
$$;


--
-- Name: create_table_close_requests(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_close_requests(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'close_requests';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(close_request_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' --UNIQUE'
      ',reserve_pub BYTEA NOT NULL CHECK (LENGTH(reserve_pub)=32)' -- REFERENCES reserves(reserve_pub) ON DELETE CASCADE
      ',close_timestamp INT8 NOT NULL'
      ',reserve_sig BYTEA NOT NULL CHECK (LENGTH(reserve_sig)=64)'
      ',close_val INT8 NOT NULL'
      ',close_frac INT4 NOT NULL'
      ',PRIMARY KEY (reserve_pub,close_timestamp)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (reserve_pub)'
    ,shard_suffix
  );

END
$$;


--
-- Name: create_table_contracts(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_contracts(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'contracts';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(contract_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' --UNIQUE
      ',purse_pub BYTEA NOT NULL CHECK (LENGTH(purse_pub)=32)'
      ',pub_ckey BYTEA NOT NULL CHECK (LENGTH(pub_ckey)=32)'
      ',contract_sig BYTEA NOT NULL CHECK (LENGTH(contract_sig)=64)'
      ',e_contract BYTEA NOT NULL'
      ',purse_expiration INT8 NOT NULL'
      ',PRIMARY KEY (purse_pub)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (purse_pub)'
    ,shard_suffix
  );

END
$$;


--
-- Name: create_table_cs_nonce_locks(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_cs_nonce_locks(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(cs_nonce_lock_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE'
      ',nonce BYTEA PRIMARY KEY CHECK (LENGTH(nonce)=32)'
      ',op_hash BYTEA NOT NULL CHECK (LENGTH(op_hash)=64)'
      ',max_denomination_serial INT8 NOT NULL'
    ') %s ;'
    ,'cs_nonce_locks'
    ,'PARTITION BY HASH (nonce)'
    ,shard_suffix
  );

END
$$;


--
-- Name: create_table_deposits(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_deposits(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'deposits';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(deposit_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' -- PRIMARY KEY'
      ',shard INT8 NOT NULL'
      ',coin_pub BYTEA NOT NULL CHECK (LENGTH(coin_pub)=32)' -- REFERENCES known_coins (coin_pub) ON DELETE CASCADE
      ',known_coin_id INT8 NOT NULL' -- REFERENCES known_coins (known_coin_id) ON DELETE CASCADE' --- FIXME: column needed???
      ',amount_with_fee_val INT8 NOT NULL'
      ',amount_with_fee_frac INT4 NOT NULL'
      ',wallet_timestamp INT8 NOT NULL'
      ',exchange_timestamp INT8 NOT NULL'
      ',refund_deadline INT8 NOT NULL'
      ',wire_deadline INT8 NOT NULL'
      ',merchant_pub BYTEA NOT NULL CHECK (LENGTH(merchant_pub)=32)'
      ',h_contract_terms BYTEA NOT NULL CHECK (LENGTH(h_contract_terms)=64)'
      ',coin_sig BYTEA NOT NULL CHECK (LENGTH(coin_sig)=64)'
      ',wire_salt BYTEA NOT NULL CHECK (LENGTH(wire_salt)=16)'
      ',wire_target_h_payto BYTEA CHECK (LENGTH(wire_target_h_payto)=32)'
      ',done BOOLEAN NOT NULL DEFAULT FALSE'
      ',extension_blocked BOOLEAN NOT NULL DEFAULT FALSE'
      ',extension_details_serial_id INT8' -- REFERENCES extension_details (extension_details_serial_id) ON DELETE CASCADE'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (coin_pub)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_coin_pub_index '
    'ON ' || table_name || ' '
    '(coin_pub);'
  );

END
$$;


--
-- Name: create_table_deposits_by_ready(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_deposits_by_ready(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'deposits_by_ready';
BEGIN

  PERFORM create_partitioned_table(
  'CREATE TABLE IF NOT EXISTS %I'
    '(wire_deadline INT8 NOT NULL'
    ',shard INT8 NOT NULL'
    ',coin_pub BYTEA NOT NULL CHECK (LENGTH(coin_pub)=32)'
    ',deposit_serial_id INT8'
    ') %s ;'
    ,table_name
    ,'PARTITION BY RANGE (wire_deadline)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_main_index '
    'ON ' || table_name || ' '
    '(wire_deadline ASC, shard ASC, coin_pub);'
  );

END
$$;


--
-- Name: create_table_deposits_for_matching(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_deposits_for_matching(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'deposits_for_matching';
BEGIN

  PERFORM create_partitioned_table(
  'CREATE TABLE IF NOT EXISTS %I'
    '(refund_deadline INT8 NOT NULL'
    ',merchant_pub BYTEA NOT NULL CHECK (LENGTH(merchant_pub)=32)'
    ',coin_pub BYTEA NOT NULL CHECK (LENGTH(coin_pub)=32)' -- REFERENCES known_coins (coin_pub) ON DELETE CASCADE
    ',deposit_serial_id INT8'
    ') %s ;'
    ,table_name
    ,'PARTITION BY RANGE (refund_deadline)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_main_index '
    'ON ' || table_name || ' '
    '(refund_deadline ASC, merchant_pub, coin_pub);'
  );

END
$$;


--
-- Name: create_table_history_requests(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_history_requests(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'history_requests';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(history_request_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' --UNIQUE'
      ',reserve_pub BYTEA NOT NULL CHECK (LENGTH(reserve_pub)=32)' -- REFERENCES reserves(reserve_pub) ON DELETE CASCADE
      ',request_timestamp INT8 NOT NULL'
      ',reserve_sig BYTEA NOT NULL CHECK (LENGTH(reserve_sig)=64)'
      ',history_fee_val INT8 NOT NULL'
      ',history_fee_frac INT4 NOT NULL'
      ',PRIMARY KEY (reserve_pub,request_timestamp)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (reserve_pub)'
    ,shard_suffix
  );

END
$$;


--
-- Name: create_table_known_coins(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_known_coins(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR default 'known_coins';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(known_coin_id BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE'
      ',denominations_serial INT8 NOT NULL' -- REFERENCES denominations (denominations_serial) ON DELETE CASCADE'
      ',coin_pub BYTEA NOT NULL PRIMARY KEY CHECK (LENGTH(coin_pub)=32)'
      ',age_commitment_hash BYTEA CHECK (LENGTH(age_commitment_hash)=32)'
      ',denom_sig BYTEA NOT NULL'
      ',remaining_val INT8 NOT NULL DEFAULT(0)'
      ',remaining_frac INT4 NOT NULL DEFAULT(0)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (coin_pub)' -- FIXME: or include denominations_serial? or multi-level partitioning?;
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

END
$$;


--
-- Name: create_table_prewire(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_prewire(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'prewire';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(prewire_uuid BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY'
      ',wire_method TEXT NOT NULL'
      ',finished BOOLEAN NOT NULL DEFAULT false'
      ',failed BOOLEAN NOT NULL DEFAULT false'
      ',buf BYTEA NOT NULL'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (prewire_uuid)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_finished_index '
    'ON ' || table_name || ' '
    '(finished);'
  );
  EXECUTE FORMAT (
    'COMMENT ON INDEX ' || table_name || '_by_finished_index '
    'IS ' || quote_literal('for gc_prewire') || ';'
  );
  -- FIXME: find a way to combine these two indices?
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_failed_finished_index '
    'ON ' || table_name || ' '
    '(failed,finished);'
  );
  EXECUTE FORMAT (
    'COMMENT ON INDEX ' || table_name || '_by_failed_finished_index '
    'IS ' || quote_literal('for wire_prepare_data_get') || ';'
  );

END
$$;


--
-- Name: create_table_purse_deposits(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_purse_deposits(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'purse_deposits';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(purse_deposit_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE
      ',partner_serial_id INT8' -- REFERENCES partners(partner_serial_id) ON DELETE CASCADE'
      ',purse_pub BYTEA NOT NULL CHECK (LENGTH(purse_pub)=32)'
      ',coin_pub BYTEA NOT NULL' -- REFERENCES known_coins (coin_pub) ON DELETE CASCADE'
      ',amount_with_fee_val INT8 NOT NULL'
      ',amount_with_fee_frac INT4 NOT NULL'
      ',coin_sig BYTEA NOT NULL CHECK(LENGTH(coin_sig)=64)'
      ',PRIMARY KEY (purse_pub,coin_pub)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (purse_pub)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  -- FIXME: change to materialized index by coin_pub!
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_coin_pub '
    'ON ' || table_name || ' '
    '(coin_pub);'
  );

END
$$;


--
-- Name: create_table_purse_merges(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_purse_merges(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'purse_merges';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(purse_merge_request_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY '-- UNIQUE
      ',partner_serial_id INT8' -- REFERENCES partners(partner_serial_id) ON DELETE CASCADE
      ',reserve_pub BYTEA NOT NULL CHECK(length(reserve_pub)=32)'--REFERENCES reserves (reserve_pub) ON DELETE CASCADE
      ',purse_pub BYTEA NOT NULL CHECK (LENGTH(purse_pub)=32)' --REFERENCES purse_requests (purse_pub) ON DELETE CASCADE
      ',merge_sig BYTEA NOT NULL CHECK (LENGTH(merge_sig)=64)'
      ',merge_timestamp INT8 NOT NULL'
      ',PRIMARY KEY (purse_pub)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (purse_pub)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  -- FIXME: change to materialized index by reserve_pub!
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_reserve_pub '
    'ON ' || table_name || ' '
    '(reserve_pub);'
  );
  EXECUTE FORMAT (
    'COMMENT ON INDEX ' || table_name || '_reserve_pub '
    'IS ' || quote_literal('needed in reserve history computation') || ';'
  );

END
$$;


--
-- Name: create_table_purse_refunds(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_purse_refunds(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'purse_refunds';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(purse_refunds_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' --UNIQUE
      ',purse_pub BYTEA NOT NULL CHECK (LENGTH(purse_pub)=32)'
      ',PRIMARY KEY (purse_pub)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (purse_pub)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

END
$$;


--
-- Name: create_table_purse_requests(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_purse_requests(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'purse_requests';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(purse_requests_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' --UNIQUE
      ',purse_pub BYTEA NOT NULL CHECK (LENGTH(purse_pub)=32)'
      ',merge_pub BYTEA NOT NULL CHECK (LENGTH(merge_pub)=32)'
      ',purse_creation INT8 NOT NULL'
      ',purse_expiration INT8 NOT NULL'
      ',h_contract_terms BYTEA NOT NULL CHECK (LENGTH(h_contract_terms)=64)'
      ',age_limit INT4 NOT NULL'
      ',flags INT4 NOT NULL'
      ',refunded BOOLEAN NOT NULL DEFAULT(FALSE)'
      ',finished BOOLEAN NOT NULL DEFAULT(FALSE)'
      ',in_reserve_quota BOOLEAN NOT NULL DEFAULT(FALSE)'
      ',amount_with_fee_val INT8 NOT NULL'
      ',amount_with_fee_frac INT4 NOT NULL'
      ',purse_fee_val INT8 NOT NULL'
      ',purse_fee_frac INT4 NOT NULL'
      ',balance_val INT8 NOT NULL DEFAULT (0)'
      ',balance_frac INT4 NOT NULL DEFAULT (0)'
      ',purse_sig BYTEA NOT NULL CHECK(LENGTH(purse_sig)=64)'
      ',PRIMARY KEY (purse_pub)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (purse_pub)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  -- FIXME: change to materialized index by merge_pub!
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_merge_pub '
    'ON ' || table_name || ' '
    '(merge_pub);'
  );

  -- FIXME: drop index on master (crosses shards)?
  -- Or use materialized index? (needed?)
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_purse_expiration '
    'ON ' || table_name || ' '
    '(purse_expiration);'
  );

END
$$;


--
-- Name: create_table_recoup(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_recoup(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'recoup';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(recoup_uuid BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE'
      ',coin_pub BYTEA NOT NULL CHECK (LENGTH(coin_pub)=32)' -- REFERENCES known_coins (coin_pub)
      ',coin_sig BYTEA NOT NULL CHECK(LENGTH(coin_sig)=64)'
      ',coin_blind BYTEA NOT NULL CHECK(LENGTH(coin_blind)=32)'
      ',amount_val INT8 NOT NULL'
      ',amount_frac INT4 NOT NULL'
      ',recoup_timestamp INT8 NOT NULL'
      ',reserve_out_serial_id INT8 NOT NULL' -- REFERENCES reserves_out (reserve_out_serial_id) ON DELETE CASCADE'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (coin_pub);'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_coin_pub_index '
    'ON ' || table_name || ' '
    '(coin_pub);'
  );

END
$$;


--
-- Name: create_table_recoup_by_reserve(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_recoup_by_reserve(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'recoup_by_reserve';
BEGIN

  PERFORM create_partitioned_table(
  'CREATE TABLE IF NOT EXISTS %I'
    '(reserve_out_serial_id INT8 NOT NULL' -- REFERENCES reserves (reserve_out_serial_id) ON DELETE CASCADE
    ',coin_pub BYTEA CHECK (LENGTH(coin_pub)=32)' -- REFERENCES known_coins (coin_pub)
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (reserve_out_serial_id)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_main_index '
    'ON ' || table_name || ' '
    '(reserve_out_serial_id);'
  );

END
$$;


--
-- Name: create_table_recoup_refresh(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_recoup_refresh(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'recoup_refresh';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(recoup_refresh_uuid BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE'
      ',coin_pub BYTEA NOT NULL CHECK (LENGTH(coin_pub)=32)' -- REFERENCES known_coins (coin_pub)
      ',known_coin_id BIGINT NOT NULL' -- REFERENCES known_coins (known_coin_id) ON DELETE CASCADE
      ',coin_sig BYTEA NOT NULL CHECK(LENGTH(coin_sig)=64)'
      ',coin_blind BYTEA NOT NULL CHECK(LENGTH(coin_blind)=32)'
      ',amount_val INT8 NOT NULL'
      ',amount_frac INT4 NOT NULL'
      ',recoup_timestamp INT8 NOT NULL'
      ',rrc_serial INT8 NOT NULL' -- REFERENCES refresh_revealed_coins (rrc_serial) ON DELETE CASCADE -- UNIQUE'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (coin_pub)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  -- FIXME: any query using this index will be slow. Materialize index or change query?
  -- Also: which query uses this index?
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_rrc_serial_index '
    'ON ' || table_name || ' '
    '(rrc_serial);'
  );
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_coin_pub_index '
    'ON ' || table_name || ' '
    '(coin_pub);'
  );

END
$$;


--
-- Name: create_table_refresh_commitments(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_refresh_commitments(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'refresh_commitments';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(melt_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE'
      ',rc BYTEA PRIMARY KEY CHECK (LENGTH(rc)=64)'
      ',old_coin_pub BYTEA NOT NULL' -- REFERENCES known_coins (coin_pub) ON DELETE CASCADE'
      ',old_coin_sig BYTEA NOT NULL CHECK(LENGTH(old_coin_sig)=64)'
      ',amount_with_fee_val INT8 NOT NULL'
      ',amount_with_fee_frac INT4 NOT NULL'
      ',noreveal_index INT4 NOT NULL'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (rc)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  -- Note: index spans partitions, may need to be materialized.
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_old_coin_pub_index '
    'ON ' || table_name || ' '
    '(old_coin_pub);'
  );

END
$$;


--
-- Name: create_table_refresh_revealed_coins(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_refresh_revealed_coins(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'refresh_revealed_coins';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(rrc_serial BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE'
      ',melt_serial_id INT8 NOT NULL' -- REFERENCES refresh_commitments (melt_serial_id) ON DELETE CASCADE'
      ',freshcoin_index INT4 NOT NULL'
      ',link_sig BYTEA NOT NULL CHECK(LENGTH(link_sig)=64)'
      ',denominations_serial INT8 NOT NULL' -- REFERENCES denominations (denominations_serial) ON DELETE CASCADE'
      ',coin_ev BYTEA NOT NULL' -- UNIQUE'
      ',h_coin_ev BYTEA NOT NULL CHECK(LENGTH(h_coin_ev)=64)' -- UNIQUE'
      ',ev_sig BYTEA NOT NULL'
      ',ewv BYTEA NOT NULL'
      --  ,PRIMARY KEY (melt_serial_id, freshcoin_index) -- done per shard
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (melt_serial_id)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_coins_by_melt_serial_id_index '
    'ON ' || table_name || ' '
    '(melt_serial_id);'
  );

END
$$;


--
-- Name: create_table_refresh_transfer_keys(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_refresh_transfer_keys(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'refresh_transfer_keys';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(rtc_serial BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE'
      ',melt_serial_id INT8 PRIMARY KEY' -- REFERENCES refresh_commitments (melt_serial_id) ON DELETE CASCADE'
      ',transfer_pub BYTEA NOT NULL CHECK(LENGTH(transfer_pub)=32)'
      ',transfer_privs BYTEA NOT NULL'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (melt_serial_id)'
    ,shard_suffix
  );

END
$$;


--
-- Name: create_table_refunds(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_refunds(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'refunds';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(refund_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE'
      ',coin_pub BYTEA NOT NULL CHECK (LENGTH(coin_pub)=32)' -- REFERENCES known_coins (coin_pub) ON DELETE CASCADE
      ',deposit_serial_id INT8 NOT NULL' -- REFERENCES deposits (deposit_serial_id) ON DELETE CASCADE'
      ',merchant_sig BYTEA NOT NULL CHECK(LENGTH(merchant_sig)=64)'
      ',rtransaction_id INT8 NOT NULL'
      ',amount_with_fee_val INT8 NOT NULL'
      ',amount_with_fee_frac INT4 NOT NULL'
      -- ,PRIMARY KEY (deposit_serial_id, rtransaction_id) -- done per shard!
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (coin_pub)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_coin_pub_index '
    'ON ' || table_name || ' '
    '(coin_pub);'
  );

END
$$;


--
-- Name: create_table_reserves(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_reserves(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'reserves';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(reserve_uuid BIGINT GENERATED BY DEFAULT AS IDENTITY'
      ',reserve_pub BYTEA PRIMARY KEY CHECK(LENGTH(reserve_pub)=32)'
      ',current_balance_val INT8 NOT NULL DEFAULT(0)'
      ',current_balance_frac INT4 NOT NULL DEFAULT(0)'
      ',purses_active INT8 NOT NULL DEFAULT(0)'
      ',purses_allowed INT8 NOT NULL DEFAULT(0)'
      ',kyc_required BOOLEAN NOT NULL DEFAULT(FALSE)'
      ',kyc_passed BOOLEAN NOT NULL DEFAULT(FALSE)'
      ',max_age INT4 NOT NULL DEFAULT(120)'
      ',expiration_date INT8 NOT NULL'
      ',gc_date INT8 NOT NULL'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (reserve_pub)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_expiration_index '
    'ON ' || table_name || ' '
    '(expiration_date'
    ',current_balance_val'
    ',current_balance_frac'
    ');'
  );
  EXECUTE FORMAT (
    'COMMENT ON INDEX ' || table_name || '_by_expiration_index '
    'IS ' || quote_literal('used in get_expired_reserves') || ';'
  );
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_reserve_uuid_index '
    'ON ' || table_name || ' '
    '(reserve_uuid);'
  );
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_gc_date_index '
    'ON ' || table_name || ' '
    '(gc_date);'
  );
  EXECUTE FORMAT (
    'COMMENT ON INDEX ' || table_name || '_by_gc_date_index '
    'IS ' || quote_literal('for reserve garbage collection') || ';'
  );

END
$$;


--
-- Name: create_table_reserves_close(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_reserves_close(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR default 'reserves_close';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(close_uuid BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE / PRIMARY KEY'
      ',reserve_pub BYTEA NOT NULL' -- REFERENCES reserves (reserve_pub) ON DELETE CASCADE'
      ',execution_date INT8 NOT NULL'
      ',wtid BYTEA NOT NULL CHECK (LENGTH(wtid)=32)'
      ',wire_target_h_payto BYTEA CHECK (LENGTH(wire_target_h_payto)=32)'
      ',amount_val INT8 NOT NULL'
      ',amount_frac INT4 NOT NULL'
      ',closing_fee_val INT8 NOT NULL'
      ',closing_fee_frac INT4 NOT NULL'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (reserve_pub)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_close_uuid_index '
    'ON ' || table_name || ' '
    '(close_uuid);'
  );
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_reserve_pub_index '
    'ON ' || table_name || ' '
    '(reserve_pub);'
  );
END
$$;


--
-- Name: create_table_reserves_in(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_reserves_in(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR default 'reserves_in';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(reserve_in_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE'
      ',reserve_pub BYTEA PRIMARY KEY' -- REFERENCES reserves (reserve_pub) ON DELETE CASCADE'
      ',wire_reference INT8 NOT NULL'
      ',credit_val INT8 NOT NULL'
      ',credit_frac INT4 NOT NULL'
      ',wire_source_h_payto BYTEA CHECK (LENGTH(wire_source_h_payto)=32)'
      ',exchange_account_section TEXT NOT NULL'
      ',execution_date INT8 NOT NULL'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (reserve_pub)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_reserve_in_serial_id_index '
    'ON ' || table_name || ' '
    '(reserve_in_serial_id);'
  );
  -- FIXME: where do we need this index? Can we do better?
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_exch_accnt_section_execution_date_idx '
    'ON ' || table_name || ' '
    '(exchange_account_section '
    ',execution_date'
    ');'
  );
  -- FIXME: where do we need this index? Can we do better?
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_exch_accnt_reserve_in_serial_id_idx '
    'ON ' || table_name || ' '
    '(exchange_account_section,'
    'reserve_in_serial_id DESC'
    ');'
  );

END
$$;


--
-- Name: create_table_reserves_out(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_reserves_out(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR default 'reserves_out';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(reserve_out_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE'
      ',h_blind_ev BYTEA CHECK (LENGTH(h_blind_ev)=64) UNIQUE'
      ',denominations_serial INT8 NOT NULL' -- REFERENCES denominations (denominations_serial)'
      ',denom_sig BYTEA NOT NULL'
      ',reserve_uuid INT8 NOT NULL' -- REFERENCES reserves (reserve_uuid) ON DELETE CASCADE'
      ',reserve_sig BYTEA NOT NULL CHECK (LENGTH(reserve_sig)=64)'
      ',execution_date INT8 NOT NULL'
      ',amount_with_fee_val INT8 NOT NULL'
      ',amount_with_fee_frac INT4 NOT NULL'
    ') %s ;'
    ,'reserves_out'
    ,'PARTITION BY HASH (h_blind_ev)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_reserve_out_serial_id_index '
    'ON ' || table_name || ' '
    '(reserve_out_serial_id);'
  );
  -- FIXME: change query to use reserves_out_by_reserve instead and materialize execution_date there as well???
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_reserve_uuid_and_execution_date_index '
    'ON ' || table_name || ' '
    '(reserve_uuid, execution_date);'
  );
  EXECUTE FORMAT (
    'COMMENT ON INDEX ' || table_name || '_by_reserve_uuid_and_execution_date_index '
    'IS ' || quote_literal('for get_reserves_out and exchange_do_withdraw_limit_check') || ';'
  );

END
$$;


--
-- Name: create_table_reserves_out_by_reserve(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_reserves_out_by_reserve(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'reserves_out_by_reserve';
BEGIN

  PERFORM create_partitioned_table(
  'CREATE TABLE IF NOT EXISTS %I'
    '(reserve_uuid INT8 NOT NULL' -- REFERENCES reserves (reserve_uuid) ON DELETE CASCADE
    ',h_blind_ev BYTEA CHECK (LENGTH(h_blind_ev)=64)'
    ') %s '
    ,table_name
    ,'PARTITION BY HASH (reserve_uuid)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_main_index '
    'ON ' || table_name || ' '
    '(reserve_uuid);'
  );

END
$$;


--
-- Name: create_table_wad_in_entries(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_wad_in_entries(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'wad_in_entries';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(wad_in_entry_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' --UNIQUE
      ',wad_in_serial_id INT8' -- REFERENCES wads_in (wad_in_serial_id) ON DELETE CASCADE
      ',reserve_pub BYTEA NOT NULL CHECK(LENGTH(reserve_pub)=32)'
      ',purse_pub BYTEA PRIMARY KEY CHECK(LENGTH(purse_pub)=32)'
      ',h_contract BYTEA NOT NULL CHECK(LENGTH(h_contract)=64)'
      ',purse_expiration INT8 NOT NULL'
      ',merge_timestamp INT8 NOT NULL'
      ',amount_with_fee_val INT8 NOT NULL'
      ',amount_with_fee_frac INT4 NOT NULL'
      ',wad_fee_val INT8 NOT NULL'
      ',wad_fee_frac INT4 NOT NULL'
      ',deposit_fees_val INT8 NOT NULL'
      ',deposit_fees_frac INT4 NOT NULL'
      ',reserve_sig BYTEA NOT NULL CHECK (LENGTH(reserve_sig)=64)'
      ',purse_sig BYTEA NOT NULL CHECK (LENGTH(purse_sig)=64)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (purse_pub)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  -- FIXME: change to materialized index by reserve_pub!
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_reserve_pub '
    'ON ' || table_name || ' '
    '(reserve_pub);'
  );
  EXECUTE FORMAT (
    'COMMENT ON INDEX ' || table_name || '_reserve_pub '
    'IS ' || quote_literal('needed in reserve history computation') || ';'
  );

END
$$;


--
-- Name: create_table_wad_out_entries(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_wad_out_entries(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'wad_out_entries';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(wad_out_entry_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' --UNIQUE
      ',wad_out_serial_id INT8' -- REFERENCES wads_out (wad_out_serial_id) ON DELETE CASCADE
      ',reserve_pub BYTEA NOT NULL CHECK(LENGTH(reserve_pub)=32)'
      ',purse_pub BYTEA PRIMARY KEY CHECK(LENGTH(purse_pub)=32)'
      ',h_contract BYTEA NOT NULL CHECK(LENGTH(h_contract)=64)'
      ',purse_expiration INT8 NOT NULL'
      ',merge_timestamp INT8 NOT NULL'
      ',amount_with_fee_val INT8 NOT NULL'
      ',amount_with_fee_frac INT4 NOT NULL'
      ',wad_fee_val INT8 NOT NULL'
      ',wad_fee_frac INT4 NOT NULL'
      ',deposit_fees_val INT8 NOT NULL'
      ',deposit_fees_frac INT4 NOT NULL'
      ',reserve_sig BYTEA NOT NULL CHECK (LENGTH(reserve_sig)=64)'
      ',purse_sig BYTEA NOT NULL CHECK (LENGTH(purse_sig)=64)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (purse_pub)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  -- FIXME: change to materialized index by reserve_pub!
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_reserve_pub '
    'ON ' || table_name || ' '
    '(reserve_pub);'
  );

END
$$;


--
-- Name: create_table_wads_in(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_wads_in(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'wads_in';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(wad_in_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' --UNIQUE
      ',wad_id BYTEA PRIMARY KEY CHECK (LENGTH(wad_id)=24)'
      ',origin_exchange_url TEXT NOT NULL'
      ',amount_val INT8 NOT NULL'
      ',amount_frac INT4 NOT NULL'
      ',arrival_time INT8 NOT NULL'
      ',UNIQUE (wad_id, origin_exchange_url)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (wad_id)'
    ,shard_suffix
  );

END
$$;


--
-- Name: create_table_wads_out(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_wads_out(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'wads_out';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I '
      '(wad_out_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' --UNIQUE
      ',wad_id BYTEA PRIMARY KEY CHECK (LENGTH(wad_id)=24)'
      ',partner_serial_id INT8 NOT NULL' -- REFERENCES partners(partner_serial_id) ON DELETE CASCADE
      ',amount_val INT8 NOT NULL'
      ',amount_frac INT4 NOT NULL'
      ',execution_time INT8 NOT NULL'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (wad_id)'
    ,shard_suffix
  );

END
$$;


--
-- Name: create_table_wire_out(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_wire_out(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  table_name VARCHAR DEFAULT 'wire_out';
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(wireout_uuid BIGINT GENERATED BY DEFAULT AS IDENTITY' -- PRIMARY KEY'
      ',execution_date INT8 NOT NULL'
      ',wtid_raw BYTEA UNIQUE NOT NULL CHECK (LENGTH(wtid_raw)=32)'
      ',wire_target_h_payto BYTEA CHECK (LENGTH(wire_target_h_payto)=32)'
      ',exchange_account_section TEXT NOT NULL'
      ',amount_val INT8 NOT NULL'
      ',amount_frac INT4 NOT NULL'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (wtid_raw)'
    ,shard_suffix
  );

  table_name = concat_ws('_', table_name, shard_suffix);

  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_by_wire_target_h_payto_index '
    'ON ' || table_name || ' '
    '(wire_target_h_payto);'
  );


END
$$;


--
-- Name: create_table_wire_targets(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_table_wire_targets(shard_suffix character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN

  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(wire_target_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY' -- UNIQUE'
      ',wire_target_h_payto BYTEA PRIMARY KEY CHECK (LENGTH(wire_target_h_payto)=32)'
      ',payto_uri VARCHAR NOT NULL'
      ',kyc_ok BOOLEAN NOT NULL DEFAULT (FALSE)'
      ',external_id VARCHAR'
    ') %s ;'
    ,'wire_targets'
    ,'PARTITION BY HASH (wire_target_h_payto)'
    ,shard_suffix
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
-- Name: detach_default_partitions(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.detach_default_partitions() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN

  RAISE NOTICE 'Detaching all default table partitions';

  ALTER TABLE IF EXISTS wire_targets
    DETACH PARTITION wire_targets_default;

  ALTER TABLE IF EXISTS reserves
    DETACH PARTITION reserves_default;

  ALTER TABLE IF EXISTS reserves_in
    DETACH PARTITION reserves_in_default;

  ALTER TABLE IF EXISTS reserves_close
    DETACH PARTITION reserves_close_default;

  ALTER TABLE IF EXISTS reserves_out
    DETACH PARTITION reserves_out_default;

  ALTER TABLE IF EXISTS reserves_out_by_reserve
    DETACH PARTITION reserves_out_by_reserve_default;

  ALTER TABLE IF EXISTS known_coins
    DETACH PARTITION known_coins_default;

  ALTER TABLE IF EXISTS refresh_commitments
    DETACH PARTITION refresh_commitments_default;

  ALTER TABLE IF EXISTS refresh_revealed_coins
    DETACH PARTITION refresh_revealed_coins_default;

  ALTER TABLE IF EXISTS refresh_transfer_keys
    DETACH PARTITION refresh_transfer_keys_default;

  ALTER TABLE IF EXISTS deposits
    DETACH PARTITION deposits_default;

--- TODO range partitioning
--  ALTER TABLE IF EXISTS deposits_by_ready
--    DETACH PARTITION deposits_by_ready_default;
--
--  ALTER TABLE IF EXISTS deposits_for_matching
--    DETACH PARTITION deposits_default_for_matching_default;

  ALTER TABLE IF EXISTS refunds
    DETACH PARTITION refunds_default;

  ALTER TABLE IF EXISTS wire_out
    DETACH PARTITION wire_out_default;

  ALTER TABLE IF EXISTS aggregation_transient
    DETACH PARTITION aggregation_transient_default;

  ALTER TABLE IF EXISTS aggregation_tracking
    DETACH PARTITION aggregation_tracking_default;

  ALTER TABLE IF EXISTS recoup
    DETACH PARTITION recoup_default;

  ALTER TABLE IF EXISTS recoup_by_reserve
    DETACH PARTITION recoup_by_reserve_default;

  ALTER TABLE IF EXISTS recoup_refresh
    DETACH PARTITION recoup_refresh_default;

  ALTER TABLE IF EXISTS prewire
    DETACH PARTITION prewire_default;

  ALTER TABLE IF EXISTS cs_nonce_locks
    DETACH partition cs_nonce_locks_default;

  ALTER TABLE IF EXISTS purse_requests
    DETACH partition purse_requests_default;

  ALTER TABLE IF EXISTS purse_refunds
    DETACH partition purse_refunds_default;

  ALTER TABLE IF EXISTS purse_merges
    DETACH partition purse_merges_default;

  ALTER TABLE IF EXISTS account_merges
    DETACH partition account_merges_default;

  ALTER TABLE IF EXISTS contracts
    DETACH partition contracts_default;

  ALTER TABLE IF EXISTS history_requests
    DETACH partition history_requests_default;

  ALTER TABLE IF EXISTS close_requests
    DETACH partition close_requests_default;

  ALTER TABLE IF EXISTS purse_deposits
    DETACH partition purse_deposits_default;

  ALTER TABLE IF EXISTS wad_out_entries
    DETACH partition wad_out_entries_default;

  ALTER TABLE IF EXISTS wads_in
    DETACH partition wads_in_default;

  ALTER TABLE IF EXISTS wad_in_entries
    DETACH partition wad_in_entries_default;
END
$$;


--
-- Name: FUNCTION detach_default_partitions(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.detach_default_partitions() IS 'We need to drop default and create new one before deleting the default partitions
      otherwise constraints get lost too. Might be needed in shardig too';


--
-- Name: drop_default_partitions(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.drop_default_partitions() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN

  RAISE NOTICE 'Dropping default table partitions';

  DROP TABLE IF EXISTS wire_targets_default;
  DROP TABLE IF EXISTS reserves_default;
  DROP TABLE IF EXISTS reserves_in_default;
  DROP TABLE IF EXISTS reserves_close_default;
  DROP TABLE IF EXISTS reserves_out_default;
  DROP TABLE IF EXISTS reserves_out_by_reserve_default;
  DROP TABLE IF EXISTS known_coins_default;
  DROP TABLE IF EXISTS refresh_commitments_default;
  DROP TABLE IF EXISTS refresh_revealed_coins_default;
  DROP TABLE IF EXISTS refresh_transfer_keys_default;
  DROP TABLE IF EXISTS deposits_default;
--DROP TABLE IF EXISTS deposits_by_ready_default;
--DROP TABLE IF EXISTS deposits_for_matching_default;
  DROP TABLE IF EXISTS refunds_default;
  DROP TABLE IF EXISTS wire_out_default;
  DROP TABLE IF EXISTS aggregation_transient_default;
  DROP TABLE IF EXISTS aggregation_tracking_default;
  DROP TABLE IF EXISTS recoup_default;
  DROP TABLE IF EXISTS recoup_by_reserve_default;
  DROP TABLE IF EXISTS recoup_refresh_default;
  DROP TABLE IF EXISTS prewire_default;
  DROP TABLE IF EXISTS cs_nonce_locks_default;

  DROP TABLE IF EXISTS purse_requests_default;
  DROP TABLE IF EXISTS purse_refunds_default;
  DROP TABLE IF EXISTS purse_merges_default;
  DROP TABLE IF EXISTS account_merges_default;
  DROP TABLE IF EXISTS contracts_default;
  DROP TABLE IF EXISTS history_requests_default;
  DROP TABLE IF EXISTS close_requests_default;
  DROP TABLE IF EXISTS purse_deposits_default;
  DROP TABLE IF EXISTS wad_out_entries_default;
  DROP TABLE IF EXISTS wads_in_default;
  DROP TABLE IF EXISTS wad_in_entries_default;

END
$$;


--
-- Name: FUNCTION drop_default_partitions(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.drop_default_partitions() IS 'Drop all default partitions once other partitions are attached.
      Might be needed in sharding too.';


--
-- Name: exchange_do_account_merge(bytea, bytea, bytea); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_account_merge(in_purse_pub bytea, in_reserve_pub bytea, in_reserve_sig bytea, OUT out_balance_ok boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- FIXME: function/API is dead! Do DCE?
END $$;


--
-- Name: exchange_do_batch_withdraw(bigint, integer, bytea, bigint, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_batch_withdraw(amount_val bigint, amount_frac integer, rpub bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT kycok boolean, OUT account_uuid bigint, OUT ruuid bigint) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
  reserve_gc INT8;
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


-- Obtain KYC status based on the last wire transfer into
-- this reserve. FIXME: likely not adequate for reserves that got P2P transfers!
-- SELECT
--    kyc_ok
--   ,wire_target_serial_id
--   INTO
--    kycok
--   ,account_uuid
--   FROM reserves_in
--   JOIN wire_targets ON (wire_source_h_payto = wire_target_h_payto)
--  WHERE reserve_pub=rpub
--  LIMIT 1; -- limit 1 should not be required (without p2p transfers)

WITH reserves_in AS materialized (
  SELECT wire_source_h_payto
  FROM reserves_in WHERE
  reserve_pub=rpub
)
SELECT
  kyc_ok
  ,wire_target_serial_id
INTO
  kycok
  ,account_uuid
FROM wire_targets
  WHERE wire_target_h_payto = (
    SELECT wire_source_h_payto
      FROM reserves_in
  );

END $$;


--
-- Name: FUNCTION exchange_do_batch_withdraw(amount_val bigint, amount_frac integer, rpub bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT kycok boolean, OUT account_uuid bigint, OUT ruuid bigint); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.exchange_do_batch_withdraw(amount_val bigint, amount_frac integer, rpub bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT kycok boolean, OUT account_uuid bigint, OUT ruuid bigint) IS 'Checks whether the reserve has sufficient balance for a withdraw operation (or the request is repeated and was previously approved) and if so updates the database with the result. Excludes storing the planchets.';


--
-- Name: exchange_do_batch_withdraw_insert(bytea, bigint, integer, bytea, bigint, bytea, bytea, bytea, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_batch_withdraw_insert(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, ruuid bigint, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, OUT out_denom_unknown boolean, OUT out_nonce_reuse boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
  denom_serial INT8;
BEGIN
-- Shards: reserves by reserve_pub (SELECT)
--         reserves_out (INSERT, with CONFLICT detection) by wih
--         reserves by reserve_pub (UPDATE)
--         reserves_in by reserve_pub (SELECT)
--         wire_targets by wire_target_h_payto

out_denom_unknown=TRUE;
out_conflict=TRUE;
out_nonce_reuse=TRUE;

SELECT denominations_serial
  INTO denom_serial
  FROM denominations
 WHERE denom_pub_hash=h_denom_pub;

IF NOT FOUND
THEN
  -- denomination unknown, should be impossible!
  out_denom_unknown=TRUE;
  ASSERT false, 'denomination unknown';
  RETURN;
END IF;
out_denom_unknown=FALSE;

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
  out_conflict=TRUE;
  RETURN;
END IF;
out_conflict=FALSE;

-- Special actions needed for a CS withdraw?
out_nonce_reuse=FALSE;
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
      out_nonce_reuse=TRUE;
      ASSERT false, 'nonce reuse attempted by client';
      RETURN;
    END IF;
  END IF;
END IF;

END $$;


--
-- Name: FUNCTION exchange_do_batch_withdraw_insert(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, ruuid bigint, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, OUT out_denom_unknown boolean, OUT out_nonce_reuse boolean, OUT out_conflict boolean); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.exchange_do_batch_withdraw_insert(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, ruuid bigint, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, OUT out_denom_unknown boolean, OUT out_nonce_reuse boolean, OUT out_conflict boolean) IS 'Stores information about a planchet for a batch withdraw operation. Checks if the planchet already exists, and in that case indicates a conflict';


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
-- Name: exchange_do_expire_purse(bigint, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_expire_purse(in_start_time bigint, in_end_time bigint, OUT out_found boolean) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
  my_purse_pub BYTEA;
DECLARE
  my_deposit record;
BEGIN

SELECT purse_pub
  INTO my_purse_pub
  FROM purse_requests
 WHERE (purse_expiration >= in_start_time) AND
       (purse_expiration < in_end_time) AND
       (NOT finished) AND
       (NOT refunded)
 ORDER BY purse_expiration ASC
 LIMIT 1;
out_found = FOUND;
IF NOT FOUND
THEN
  RETURN;
END IF;

UPDATE purse_requests
 SET refunded=TRUE,
     finished=TRUE
 WHERE purse_pub=my_purse_pub;

INSERT INTO purse_refunds
 (purse_pub)
 VALUES
 (my_purse_pub);

-- restore balance to each coin deposited into the purse
FOR my_deposit IN
  SELECT coin_pub
        ,amount_with_fee_val
        ,amount_with_fee_frac
    FROM purse_deposits
  WHERE purse_pub = my_purse_pub
LOOP
  UPDATE known_coins SET
    remaining_frac=remaining_frac+my_deposit.amount_with_fee_frac
     - CASE
       WHEN remaining_frac+my_deposit.amount_with_fee_frac >= 100000000
       THEN 100000000
       ELSE 0
       END,
    remaining_val=remaining_val+my_deposit.amount_with_fee_val
     + CASE
       WHEN remaining_frac+my_deposit.amount_with_fee_frac >= 100000000
       THEN 1
       ELSE 0
       END
    WHERE coin_pub = my_deposit.coin_pub;
  END LOOP;
END $$;


--
-- Name: FUNCTION exchange_do_expire_purse(in_start_time bigint, in_end_time bigint, OUT out_found boolean); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.exchange_do_expire_purse(in_start_time bigint, in_end_time bigint, OUT out_found boolean) IS 'Finds an expired purse in the given time range and refunds the coins (if any).';


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

CREATE FUNCTION public.exchange_do_history_request(in_reserve_pub bytea, in_reserve_sig bytea, in_request_timestamp bigint, in_history_fee_val bigint, in_history_fee_frac integer, OUT out_balance_ok boolean, OUT out_idempotent boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
BEGIN

  -- Insert and check for idempotency.
  INSERT INTO history_requests
  (reserve_pub
  ,request_timestamp
  ,reserve_sig
  ,history_fee_val
  ,history_fee_frac)
  VALUES
  (in_reserve_pub
  ,in_request_timestamp
  ,in_reserve_sig
  ,in_history_fee_val
  ,in_history_fee_frac)
  ON CONFLICT DO NOTHING;

  IF NOT FOUND
  THEN
    out_balance_ok=TRUE;
    out_idempotent=TRUE;
    RETURN;
  END IF;

  out_idempotent=FALSE;

  -- Update reserve balance.
  UPDATE reserves
   SET
    current_balance_frac=current_balance_frac-in_history_fee_frac
       + CASE
         WHEN current_balance_frac < in_history_fee_frac
         THEN 100000000
         ELSE 0
         END,
    current_balance_val=current_balance_val-in_history_fee_val
       - CASE
         WHEN current_balance_frac < in_history_fee_frac
         THEN 1
         ELSE 0
         END
  WHERE
    reserve_pub=in_reserve_pub
    AND ( (current_balance_val > in_history_fee_val) OR
          ( (current_balance_frac >= in_history_fee_frac) AND
            (current_balance_val >= in_history_fee_val) ) );

  IF NOT FOUND
  THEN
    -- Either reserve does not exist, or balance insufficient.
    -- Both we treat the same here as balance insufficient.
    out_balance_ok=FALSE;
    RETURN;
  END IF;

  out_balance_ok=TRUE;
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
-- Name: exchange_do_purse_deposit(bigint, bytea, bigint, integer, bytea, bytea, bigint, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_purse_deposit(in_partner_id bigint, in_purse_pub bytea, in_amount_with_fee_val bigint, in_amount_with_fee_frac integer, in_coin_pub bytea, in_coin_sig bytea, in_amount_without_fee_val bigint, in_amount_without_fee_frac integer, OUT out_balance_ok boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
  was_merged BOOLEAN;
DECLARE
  psi INT8; -- partner's serial ID (set if merged)
DECLARE
  my_amount_val INT8; -- total in purse
DECLARE
  my_amount_frac INT4; -- total in purse
DECLARE
  was_paid BOOLEAN;
DECLARE
  my_reserve_pub BYTEA;
BEGIN

-- Store the deposit request.
INSERT INTO purse_deposits
  (partner_serial_id
  ,purse_pub
  ,coin_pub
  ,amount_with_fee_val
  ,amount_with_fee_frac
  ,coin_sig)
  VALUES
  (in_partner_id
  ,in_purse_pub
  ,in_coin_pub
  ,in_amount_with_fee_val
  ,in_amount_with_fee_frac
  ,in_coin_sig)
  ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- Idempotency check: check if coin_sig is the same,
  -- if so, success, otherwise conflict!
  PERFORM
  FROM purse_deposits
  WHERE coin_pub = in_coin_pub
    AND purse_pub = in_purse_pub
    AND coin_sig = in_cion_sig;
  IF NOT FOUND
  THEN
    -- Deposit exists, but with differences. Not allowed.
    out_balance_ok=FALSE;
    out_conflict=TRUE;
    RETURN;
  END IF;
END IF;


-- Debit the coin
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


-- Credit the purse.
UPDATE purse_requests
  SET
    balance_frac=balance_frac+in_amount_without_fee_frac
       - CASE
         WHEN balance_frac+in_amount_without_fee_frac >= 100000000
         THEN 100000000
         ELSE 0
         END,
    balance_val=balance_val+in_amount_without_fee_val
       + CASE
         WHEN balance_frac+in_amount_without_fee_frac >= 100000000
         THEN 1
         ELSE 0
         END
  WHERE purse_pub=in_purse_pub;

out_conflict=FALSE;
out_balance_ok=TRUE;

-- See if we can finish the merge or need to update the trigger time and partner.
SELECT partner_serial_id
      ,reserve_pub
  INTO psi
      ,my_reserve_pub
  FROM purse_merges
 WHERE purse_pub=in_purse_pub;

IF NOT FOUND
THEN
  RETURN;
END IF;

SELECT
    amount_with_fee_val
   ,amount_with_fee_frac
  INTO
    my_amount_val
   ,my_amount_frac
  FROM purse_requests
  WHERE (purse_pub=in_purse_pub)
    AND ( ( ( (amount_with_fee_val <= balance_val)
          AND (amount_with_fee_frac <= balance_frac) )
         OR (amount_with_fee_val < balance_val) ) );
IF NOT FOUND
THEN
  RETURN;
END IF;

IF (0 != psi)
THEN
  -- The taler-exchange-router will take care of this.
  UPDATE purse_actions
     SET action_date=0 --- "immediately"
        ,partner_serial_id=psi
   WHERE purse_pub=in_purse_pub;
ELSE
  -- This is a local reserve, update balance immediately.
  UPDATE reserves
  SET
    current_balance_frac=current_balance_frac+my_amount_frac
       - CASE
         WHEN current_balance_frac + my_amount_frac >= 100000000
         THEN 100000000
         ELSE 0
         END,
    current_balance_val=current_balance_val+my_amount_val
       + CASE
         WHEN current_balance_frac + my_amount_frac >= 100000000
         THEN 1
         ELSE 0
         END
  WHERE reserve_pub=my_reserve_pub;

  -- ... and mark purse as finished.
  -- FIXME: combine with UPDATE above?
  UPDATE purse_requests
     SET finished=true
  WHERE purse_pub=in_purse_pub;
END IF;


END $$;


--
-- Name: exchange_do_purse_merge(bytea, bytea, bigint, bytea, character varying, bytea, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_purse_merge(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_partner_url character varying, in_reserve_pub bytea, in_require_kyc boolean, OUT out_no_partner boolean, OUT out_no_balance boolean, OUT out_no_kyc boolean, OUT out_no_reserve boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
  my_amount_val INT8;
DECLARE
  my_amount_frac INT4;
DECLARE
  my_purse_fee_val INT8;
DECLARE
  my_purse_fee_frac INT4;
DECLARE
  my_partner_serial_id INT8;
DECLARE
  my_finished BOOLEAN;
BEGIN

IF in_partner_url IS NULL
THEN
  my_partner_serial_id=0;
ELSE
  SELECT
    partner_serial_id
  INTO
    my_partner_serial_id
  FROM partners
  WHERE partner_base_url=in_partner_url
    AND start_date <= in_merge_timestamp
    AND end_date > in_merge_timestamp;
  IF NOT FOUND
  THEN
    out_no_partner=TRUE;
    out_conflict=FALSE;
    out_no_kyc=FALSE;
    out_no_reserve=FALSE;
    RETURN;
  END IF;
END IF;

out_no_partner=FALSE;


-- Check purse is 'full'.
SELECT amount_with_fee_val
      ,amount_with_fee_frac
      ,purse_fee_val
      ,purse_fee_frac
      ,finished
  INTO my_amount_val
      ,my_amount_frac
      ,my_purse_fee_val
      ,my_purse_fee_frac
      ,my_finished
  FROM purse_requests
  WHERE purse_pub=in_purse_pub
    AND balance_val >= amount_with_fee_val
    AND ( (balance_frac >= amount_with_fee_frac) OR
          (balance_val > amount_with_fee_val) );
IF NOT FOUND
THEN
  out_no_balance=TRUE;
  out_conflict=FALSE;
  out_no_kyc=FALSE;
  out_no_reserve=FALSE;
  RETURN;
END IF;
out_no_balance=FALSE;

-- Store purse merge signature, checks for purse_pub uniqueness
INSERT INTO purse_merges
    (partner_serial_id
    ,reserve_pub
    ,purse_pub
    ,merge_sig
    ,merge_timestamp)
  VALUES
    (my_partner_serial_id
    ,in_reserve_pub
    ,in_purse_pub
    ,in_merge_sig
    ,in_merge_timestamp)
  ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- Idempotency check: see if an identical record exists.
  -- Note that by checking 'merge_sig', we implicitly check
  -- identity over everything that the signature covers.
  PERFORM
  FROM purse_merges
  WHERE purse_pub=in_purse_pub
     AND merge_sig=in_merge_sig;
  IF NOT FOUND
  THEN
     -- Purse was merged, but to some other reserve. Not allowed.
     out_conflict=TRUE;
     out_no_kyc=FALSE;
     out_no_reserve=FALSE;
     RETURN;
  END IF;

  -- "success"
  out_conflict=FALSE;
  out_no_kyc=FALSE;
  out_no_reserve=FALSE;
  RETURN;
END IF;
out_conflict=FALSE;

ASSERT NOT my_finished, 'internal invariant failed';

IF ( (in_partner_url IS NULL) AND
     (in_require_kyc) )
THEN
  -- Need to do KYC check.
  SELECT NOT kyc_passed
    INTO out_no_kyc
    FROM reserves
   WHERE reserve_pub=in_reserve_pub;

  IF NOT FOUND
  THEN
    out_no_kyc=TRUE;
    out_no_reserve=TRUE;
    RETURN;
  END IF;
  out_no_reserve=FALSE;

  IF (out_no_kyc)
  THEN
    RETURN;
  END IF;
ELSE
  -- KYC is not our responsibility
  out_no_reserve=FALSE;
  out_no_kyc=FALSE;
END IF;



-- Store account merge signature.
INSERT INTO account_merges
  (reserve_pub
  ,reserve_sig
  ,purse_pub)
  VALUES
  (in_reserve_pub
  ,in_reserve_sig
  ,in_purse_pub);

-- If we need a wad transfer, mark purse ready for it.
IF (0 != my_partner_serial_id)
THEN
  -- The taler-exchange-router will take care of this.
  UPDATE purse_actions
     SET action_date=0 --- "immediately"
        ,partner_serial_id=my_partner_serial_id
   WHERE purse_pub=in_purse_pub;
ELSE
  -- This is a local reserve, update reserve balance immediately.

  -- Refund the purse fee, by adding it to the purse value:
  my_amount_val = my_amount_val + my_purse_fee_val;
  my_amount_frac = my_amount_frac + my_purse_fee_frac;
  -- normalize result
  my_amount_val = my_amount_val + my_amount_frac / 100000000;
  my_amount_frac = my_amount_frac % 100000000;

  UPDATE reserves
  SET
    current_balance_frac=current_balance_frac+my_amount_frac
       - CASE
         WHEN current_balance_frac + my_amount_frac >= 100000000
         THEN 100000000
         ELSE 0
         END,
    current_balance_val=current_balance_val+my_amount_val
       + CASE
         WHEN current_balance_frac + my_amount_frac >= 100000000
         THEN 1
         ELSE 0
         END
  WHERE reserve_pub=in_reserve_pub;

  -- ... and mark purse as finished.
  UPDATE purse_requests
     SET finished=true
  WHERE purse_pub=in_purse_pub;
END IF;


RETURN;

END $$;


--
-- Name: FUNCTION exchange_do_purse_merge(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_partner_url character varying, in_reserve_pub bytea, in_require_kyc boolean, OUT out_no_partner boolean, OUT out_no_balance boolean, OUT out_no_kyc boolean, OUT out_no_reserve boolean, OUT out_conflict boolean); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.exchange_do_purse_merge(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_partner_url character varying, in_reserve_pub bytea, in_require_kyc boolean, OUT out_no_partner boolean, OUT out_no_balance boolean, OUT out_no_kyc boolean, OUT out_no_reserve boolean, OUT out_conflict boolean) IS 'Checks that the partner exists, the purse has not been merged with a different reserve and that the purse is full. If so, persists the merge data and either merges the purse with the reserve or marks it as ready for the taler-exchange-router. Caller MUST abort the transaction on failures so as to not persist data by accident.';


--
-- Name: exchange_do_recoup_by_reserve(bytea); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_recoup_by_reserve(res_pub bytea) RETURNS TABLE(denom_sig bytea, denominations_serial bigint, coin_pub bytea, coin_sig bytea, coin_blind bytea, amount_val bigint, amount_frac integer, recoup_timestamp bigint)
    LANGUAGE plpgsql
    AS $$
DECLARE
  res_uuid BIGINT;
  blind_ev BYTEA;
  c_pub    BYTEA;
BEGIN
  SELECT reserve_uuid
  INTO res_uuid
  FROM reserves
  WHERE reserves.reserve_pub = res_pub;

  FOR blind_ev IN
    SELECT h_blind_ev
      FROM reserves_out_by_reserve
    WHERE reserves_out_by_reserve.reserve_uuid = res_uuid
  LOOP
    SELECT robr.coin_pub
      INTO c_pub
      FROM recoup_by_reserve robr
    WHERE robr.reserve_out_serial_id = (
      SELECT reserves_out.reserve_out_serial_id
        FROM reserves_out
      WHERE reserves_out.h_blind_ev = blind_ev
    );
    RETURN QUERY
      SELECT kc.denom_sig,
             kc.denominations_serial,
             rc.coin_pub,
             rc.coin_sig,
             rc.coin_blind,
             rc.amount_val,
             rc.amount_frac,
             rc.recoup_timestamp
      FROM (
        SELECT *
        FROM known_coins
        WHERE known_coins.coin_pub = c_pub
      ) kc
      JOIN (
        SELECT *
        FROM recoup
        WHERE recoup.coin_pub = c_pub
      ) rc USING (coin_pub);
  END LOOP;
END;
$$;


--
-- Name: FUNCTION exchange_do_recoup_by_reserve(res_pub bytea); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.exchange_do_recoup_by_reserve(res_pub bytea) IS 'Recoup by reserve as a function to make sure we hit only the needed partition and not all when joining as joins on distributed tables fetch ALL rows from the shards';


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
-- Name: exchange_do_reserve_purse(bytea, bytea, bigint, bytea, boolean, bigint, integer, bytea, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_reserve_purse(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_reserve_quota boolean, in_purse_fee_val bigint, in_purse_fee_frac integer, in_reserve_pub bytea, in_require_kyc boolean, OUT out_no_funds boolean, OUT out_no_kyc boolean, OUT out_no_reserve boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
BEGIN

-- Store purse merge signature, checks for purse_pub uniqueness
INSERT INTO purse_merges
    (partner_serial_id
    ,reserve_pub
    ,purse_pub
    ,merge_sig
    ,merge_timestamp)
  VALUES
    (0
    ,in_reserve_pub
    ,in_purse_pub
    ,in_merge_sig
    ,in_merge_timestamp)
  ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- Idempotency check: see if an identical record exists.
  -- Note that by checking 'merge_sig', we implicitly check
  -- identity over everything that the signature covers.
  PERFORM
  FROM purse_merges
  WHERE purse_pub=in_purse_pub
     AND merge_sig=in_merge_sig;
  IF NOT FOUND
  THEN
     -- Purse was merged, but to some other reserve. Not allowed.
     out_conflict=TRUE;
     out_no_kyc=FALSE;
     out_no_reserve=FALSE;
     out_no_funds=FALSE;
     RETURN;
  END IF;

  -- "success"
  out_conflict=FALSE;
  out_no_funds=FALSE;
  out_no_kyc=FALSE;
  out_no_reserve=FALSE;
  RETURN;
END IF;
out_conflict=FALSE;

SELECT NOT kyc_passed
  INTO out_no_kyc
  FROM reserves
 WHERE reserve_pub=in_reserve_pub;

IF NOT FOUND
THEN
  out_no_kyc=TRUE;
  out_no_reserve=TRUE;
  out_no_funds=TRUE;
  RETURN;
END IF;
out_no_reserve=FALSE;

IF (out_no_kyc AND in_require_kyc)
THEN
  out_no_funds=FALSE;
  RETURN;
END IF;

IF (in_reserve_quota)
THEN
  -- Increment active purses per reserve (and check this is allowed)
  UPDATE reserves
     SET purses_active=purses_active+1
        ,kyc_required=TRUE
   WHERE reserve_pub=in_reserve_pub
     AND purses_active < purses_allowed;
  IF NOT FOUND
  THEN
    out_no_funds=TRUE;
    RETURN;
  END IF;
ELSE
  --  UPDATE reserves balance (and check if balance is enough to pay the fee)
  UPDATE reserves
  SET
    current_balance_frac=current_balance_frac-in_purse_fee_frac
       + CASE
         WHEN current_balance_frac < in_purse_fee_frac
         THEN 100000000
         ELSE 0
         END,
    current_balance_val=current_balance_val-in_purse_fee_val
       - CASE
         WHEN current_balance_frac < in_purse_fee_frac
         THEN 1
         ELSE 0
         END
    ,kyc_required=TRUE
  WHERE reserve_pub=in_reserve_pub
    AND ( (current_balance_val > in_purse_fee_val) OR
          ( (current_balance_frac >= in_purse_fee_frac) AND
            (current_balance_val >= in_purse_fee_val) ) );
  IF NOT FOUND
  THEN
    out_no_funds=TRUE;
    RETURN;
  END IF;
END IF;

out_no_funds=FALSE;


-- Store account merge signature.
INSERT INTO account_merges
  (reserve_pub
  ,reserve_sig
  ,purse_pub)
  VALUES
  (in_reserve_pub
  ,in_reserve_sig
  ,in_purse_pub);

END $$;


--
-- Name: FUNCTION exchange_do_reserve_purse(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_reserve_quota boolean, in_purse_fee_val bigint, in_purse_fee_frac integer, in_reserve_pub bytea, in_require_kyc boolean, OUT out_no_funds boolean, OUT out_no_kyc boolean, OUT out_no_reserve boolean, OUT out_conflict boolean); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.exchange_do_reserve_purse(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_reserve_quota boolean, in_purse_fee_val bigint, in_purse_fee_frac integer, in_reserve_pub bytea, in_require_kyc boolean, OUT out_no_funds boolean, OUT out_no_kyc boolean, OUT out_no_reserve boolean, OUT out_conflict boolean) IS 'Create a purse for a reserve.';


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
-- SELECT
--    kyc_ok
--   ,wire_target_serial_id
--   INTO
--    kycok
--   ,account_uuid
--   FROM reserves_in
--   JOIN wire_targets ON (wire_source_h_payto = wire_target_h_payto)
--  WHERE reserve_pub=rpub
--  LIMIT 1; -- limit 1 should not be required (without p2p transfers)

WITH reserves_in AS materialized (
  SELECT wire_source_h_payto
  FROM reserves_in WHERE
  reserve_pub=rpub
)
SELECT
  kyc_ok
  ,wire_target_serial_id
INTO
  kycok
  ,account_uuid
FROM wire_targets
  WHERE wire_target_h_payto = (
    SELECT wire_source_h_payto
      FROM reserves_in
  );

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
-- Name: prepare_sharding(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prepare_sharding() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN

  CREATE EXTENSION IF NOT EXISTS postgres_fdw;

  PERFORM detach_default_partitions();

  ALTER TABLE IF EXISTS wire_targets
    DROP CONSTRAINT IF EXISTS wire_targets_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS reserves
    DROP CONSTRAINT IF EXISTS reserves_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS reserves_in
    DROP CONSTRAINT IF EXISTS reserves_in_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS reserves_close
    DROP CONSTRAINT IF EXISTS reserves_close_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS reserves_out
    DROP CONSTRAINT IF EXISTS reserves_out_pkey CASCADE
    ,DROP CONSTRAINT IF EXISTS reserves_out_denominations_serial_fkey
    ,DROP CONSTRAINT IF EXISTS reserves_out_h_blind_ev_key
  ;

  ALTER TABLE IF EXISTS known_coins
    DROP CONSTRAINT IF EXISTS known_coins_pkey CASCADE
    ,DROP CONSTRAINT IF EXISTS known_coins_denominations_serial_fkey
  ;

  ALTER TABLE IF EXISTS refresh_commitments
    DROP CONSTRAINT IF EXISTS refresh_commitments_pkey CASCADE
    ,DROP CONSTRAINT IF EXISTS refresh_old_coin_pub_fkey
  ;

  ALTER TABLE IF EXISTS refresh_revealed_coins
    DROP CONSTRAINT IF EXISTS refresh_revealed_coins_pkey CASCADE
    ,DROP CONSTRAINT IF EXISTS refresh_revealed_coins_denominations_serial_fkey
  ;

  ALTER TABLE IF EXISTS refresh_transfer_keys
    DROP CONSTRAINT IF EXISTS refresh_transfer_keys_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS deposits
    DROP CONSTRAINT IF EXISTS deposits_pkey CASCADE
    ,DROP CONSTRAINT IF EXISTS deposits_extension_details_serial_id_fkey
    ,DROP CONSTRAINT IF EXISTS deposits_coin_pub_merchant_pub_h_contract_terms_key CASCADE
  ;

  ALTER TABLE IF EXISTS refunds
    DROP CONSTRAINT IF EXISTS refunds_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS wire_out
    DROP CONSTRAINT IF EXISTS wire_out_pkey CASCADE
    ,DROP CONSTRAINT IF EXISTS wire_out_wtid_raw_key CASCADE
  ;

  ALTER TABLE IF EXISTS aggregation_tracking
    DROP CONSTRAINT IF EXISTS aggregation_tracking_pkey CASCADE
    ,DROP CONSTRAINT IF EXISTS aggregation_tracking_wtid_raw_fkey
  ;

  ALTER TABLE IF EXISTS recoup
    DROP CONSTRAINT IF EXISTS recoup_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS recoup_refresh
    DROP CONSTRAINT IF EXISTS recoup_refresh_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS prewire
    DROP CONSTRAINT IF EXISTS prewire_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS cs_nonce_locks
    DROP CONSTRAINT IF EXISTS cs_nonce_locks_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS purse_requests
    DROP CONSTRAINT IF EXISTS purse_requests_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS purse_refunds
    DROP CONSTRAINT IF EXISTS purse_refunds_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS purse_merges
    DROP CONSTRAINT IF EXISTS purse_merges_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS account_merges
    DROP CONSTRAINT IF EXISTS account_merges_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS contracts
    DROP CONSTRAINT IF EXISTS contracts_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS history_requests
    DROP CONSTRAINT IF EXISTS history_requests_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS close_requests
    DROP CONSTRAINT IF EXISTS close_requests_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS purse_deposits
    DROP CONSTRAINT IF EXISTS purse_deposits_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS wads_out
    DROP CONSTRAINT IF EXISTS wads_out_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS wad_out_entries
    DROP CONSTRAINT IF EXISTS wad_out_entries_pkey CASCADE
  ;

  ALTER TABLE IF EXISTS wads_in
    DROP CONSTRAINT IF EXISTS wads_in_pkey CASCADE
    ,DROP CONSTRAINT IF EXISTS wads_in_wad_id_origin_exchange_url_key
  ;

  ALTER TABLE IF EXISTS wad_in_entries
    DROP CONSTRAINT IF EXISTS wad_in_entries_pkey CASCADE
  ;

END
$$;


--
-- Name: purse_requests_insert_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.purse_requests_insert_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  ASSERT NOT NEW.finished,'Internal invariant violated';
  INSERT INTO
    purse_actions
    (purse_pub
    ,action_date)
  VALUES
    (NEW.purse_pub
    ,NEW.purse_expiration);
  RETURN NEW;
END $$;


--
-- Name: FUNCTION purse_requests_insert_trigger(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.purse_requests_insert_trigger() IS 'When a purse is created, insert it into the purse_action table to take action when the purse expires.';


--
-- Name: purse_requests_on_update_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.purse_requests_on_update_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF (NEW.finished AND NOT OLD.finished)
  THEN
    -- If this purse counted against the reserve's
    -- quota of purses, decrement the reserve accounting.
    IF (NEW.in_reserve_quota)
    THEN
      UPDATE reserves
         SET purses_active=purses_active-1
       WHERE reserve_pub IN
         (SELECT reserve_pub
            FROM purse_merges
           WHERE purse_pub=NEW.purse_pub
           LIMIT 1);
      NEW.in_reserve_quota=FALSE;
    END IF;
    -- Delete from the purse_actions table, we are done
    -- with this purse for good.
    DELETE FROM purse_actions
          WHERE purse_pub=NEW.purse_pub;
    RETURN NEW;
  END IF;

  RETURN NEW;
END $$;


--
-- Name: FUNCTION purse_requests_on_update_trigger(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.purse_requests_on_update_trigger() IS 'Trigger the router if the purse is ready. Also removes the entry from the router watchlist once the purse is finished.';


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
    wtid_raw bytea NOT NULL
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
    last_recoup_refresh_serial_id bigint DEFAULT 0 NOT NULL,
    last_purse_deposits_serial_id bigint DEFAULT 0 NOT NULL,
    last_purse_refunds_serial_id bigint DEFAULT 0 NOT NULL
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
    last_reserve_close_serial_id bigint DEFAULT 0 NOT NULL,
    last_purse_merges_serial_id bigint DEFAULT 0 NOT NULL,
    last_purse_deposits_serial_id bigint DEFAULT 0 NOT NULL,
    last_account_merges_serial_id bigint DEFAULT 0 NOT NULL,
    last_history_requests_serial_id bigint DEFAULT 0 NOT NULL,
    last_close_requests_serial_id bigint DEFAULT 0 NOT NULL
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
    withdraw_fee_balance_frac integer NOT NULL,
    purse_fee_balance_val bigint NOT NULL,
    purse_fee_balance_frac integer NOT NULL,
    history_fee_balance_val bigint NOT NULL,
    history_fee_balance_frac integer NOT NULL
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
    close_request_serial_id bigint NOT NULL,
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
-- Name: close_requests_close_request_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.close_requests ALTER COLUMN close_request_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.close_requests_close_request_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: close_requests_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.close_requests_default (
    close_request_serial_id bigint NOT NULL,
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
    contract_sig bytea NOT NULL,
    e_contract bytea NOT NULL,
    purse_expiration bigint NOT NULL,
    CONSTRAINT contracts_contract_sig_check CHECK ((length(contract_sig) = 64)),
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
-- Name: COLUMN contracts.contract_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contracts.contract_sig IS 'signature over the encrypted contract by the purse contract key';


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
    contract_sig bytea NOT NULL,
    e_contract bytea NOT NULL,
    purse_expiration bigint NOT NULL,
    CONSTRAINT contracts_contract_sig_check CHECK ((length(contract_sig) = 64)),
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
    history_request_serial_id bigint NOT NULL,
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
    history_request_serial_id bigint NOT NULL,
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
-- Name: history_requests_history_request_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.history_requests ALTER COLUMN history_request_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.history_requests_history_request_serial_id_seq
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
    remaining_val bigint DEFAULT 0 NOT NULL,
    remaining_frac integer DEFAULT 0 NOT NULL,
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
    remaining_val bigint DEFAULT 0 NOT NULL,
    remaining_frac integer DEFAULT 0 NOT NULL,
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
    website character varying,
    email character varying,
    logo bytea,
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
-- Name: COLUMN merchant_instances.website; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.website IS 'merchant site URL';


--
-- Name: COLUMN merchant_instances.email; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.email IS 'email';


--
-- Name: COLUMN merchant_instances.logo; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.logo IS 'data image url';


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
    next_wad bigint DEFAULT 0 NOT NULL,
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
-- Name: COLUMN partners.next_wad; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.partners.next_wad IS 'at what time should we do the next wad transfer to this partner (frequently updated); set to forever after the end_date';


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
-- Name: purse_actions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purse_actions (
    purse_pub bytea NOT NULL,
    action_date bigint NOT NULL,
    partner_serial_id bigint,
    CONSTRAINT purse_actions_purse_pub_check CHECK ((length(purse_pub) = 32))
);


--
-- Name: TABLE purse_actions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.purse_actions IS 'purses awaiting some action by the router';


--
-- Name: COLUMN purse_actions.purse_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_actions.purse_pub IS 'public (contract) key of the purse';


--
-- Name: COLUMN purse_actions.action_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_actions.action_date IS 'when is the purse ready for action';


--
-- Name: COLUMN purse_actions.partner_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_actions.partner_serial_id IS 'wad target of an outgoing wire transfer, 0 for local, NULL if the purse is unmerged and thus the target is still unknown';


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
-- Name: purse_refunds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purse_refunds (
    purse_refunds_serial_id bigint NOT NULL,
    purse_pub bytea NOT NULL,
    CONSTRAINT purse_refunds_purse_pub_check CHECK ((length(purse_pub) = 32))
)
PARTITION BY HASH (purse_pub);


--
-- Name: TABLE purse_refunds; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.purse_refunds IS 'Purses that were refunded due to expiration';


--
-- Name: COLUMN purse_refunds.purse_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_refunds.purse_pub IS 'Public key of the purse';


--
-- Name: purse_refunds_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purse_refunds_default (
    purse_refunds_serial_id bigint NOT NULL,
    purse_pub bytea NOT NULL,
    CONSTRAINT purse_refunds_purse_pub_check CHECK ((length(purse_pub) = 32))
);
ALTER TABLE ONLY public.purse_refunds ATTACH PARTITION public.purse_refunds_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: purse_refunds_purse_refunds_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.purse_refunds ALTER COLUMN purse_refunds_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.purse_refunds_purse_refunds_serial_id_seq
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
    purse_creation bigint NOT NULL,
    purse_expiration bigint NOT NULL,
    h_contract_terms bytea NOT NULL,
    age_limit integer NOT NULL,
    flags integer NOT NULL,
    refunded boolean DEFAULT false NOT NULL,
    finished boolean DEFAULT false NOT NULL,
    in_reserve_quota boolean DEFAULT false NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    purse_fee_val bigint NOT NULL,
    purse_fee_frac integer NOT NULL,
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
-- Name: COLUMN purse_requests.purse_creation; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.purse_creation IS 'Local time when the purse was created. Determines applicable purse fees.';


--
-- Name: COLUMN purse_requests.purse_expiration; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.purse_expiration IS 'When the purse is set to expire';


--
-- Name: COLUMN purse_requests.h_contract_terms; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.h_contract_terms IS 'Hash of the contract the parties are to agree to';


--
-- Name: COLUMN purse_requests.flags; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.flags IS 'see the enum TALER_WalletAccountMergeFlags';


--
-- Name: COLUMN purse_requests.refunded; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.refunded IS 'set to TRUE if the purse could not be merged and thus all deposited coins were refunded';


--
-- Name: COLUMN purse_requests.finished; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.finished IS 'set to TRUE once the purse has been merged (into reserve or wad) or the coins were refunded (transfer aborted)';


--
-- Name: COLUMN purse_requests.in_reserve_quota; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.in_reserve_quota IS 'set to TRUE if this purse currently counts against the number of free purses in the respective reserve';


--
-- Name: COLUMN purse_requests.amount_with_fee_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.amount_with_fee_val IS 'Total amount expected to be in the purse';


--
-- Name: COLUMN purse_requests.purse_fee_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.purse_requests.purse_fee_val IS 'Purse fee the client agreed to pay from the reserve (accepted by the exchange at the time the purse was created). Zero if in_reserve_quota is TRUE.';


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
    purse_creation bigint NOT NULL,
    purse_expiration bigint NOT NULL,
    h_contract_terms bytea NOT NULL,
    age_limit integer NOT NULL,
    flags integer NOT NULL,
    refunded boolean DEFAULT false NOT NULL,
    finished boolean DEFAULT false NOT NULL,
    in_reserve_quota boolean DEFAULT false NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    purse_fee_val bigint NOT NULL,
    purse_fee_frac integer NOT NULL,
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
    current_balance_val bigint DEFAULT 0 NOT NULL,
    current_balance_frac integer DEFAULT 0 NOT NULL,
    purses_active bigint DEFAULT 0 NOT NULL,
    purses_allowed bigint DEFAULT 0 NOT NULL,
    kyc_required boolean DEFAULT false NOT NULL,
    kyc_passed boolean DEFAULT false NOT NULL,
    max_age integer DEFAULT 120 NOT NULL,
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

COMMENT ON COLUMN public.reserves.current_balance_val IS 'Current balance remaining with the reserve.';


--
-- Name: COLUMN reserves.purses_active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves.purses_active IS 'Number of purses that were created by this reserve that are not expired and not fully paid.';


--
-- Name: COLUMN reserves.purses_allowed; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves.purses_allowed IS 'Number of purses that this reserve is allowed to have active at most.';


--
-- Name: COLUMN reserves.kyc_required; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves.kyc_required IS 'True if a KYC check must have been passed before withdrawing from this reserve. Set to true once a reserve received a P2P payment.';


--
-- Name: COLUMN reserves.kyc_passed; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves.kyc_passed IS 'True once KYC was passed for this reserve. The KYC details are then available via the wire_targets table under the key of wire_target_h_payto which is to be derived from the reserve_pub and the base URL of this exchange.';


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
    current_balance_val bigint DEFAULT 0 NOT NULL,
    current_balance_frac integer DEFAULT 0 NOT NULL,
    purses_active bigint DEFAULT 0 NOT NULL,
    purses_allowed bigint DEFAULT 0 NOT NULL,
    kyc_required boolean DEFAULT false NOT NULL,
    kyc_passed boolean DEFAULT false NOT NULL,
    max_age integer DEFAULT 120 NOT NULL,
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
exchange-0001	2022-06-19 14:06:05.845802+02	grothoff	{}	{}
merchant-0001	2022-06-19 14:06:06.801597+02	grothoff	{}	{}
merchant-0002	2022-06-19 14:06:07.218735+02	grothoff	{}	{}
auditor-0001	2022-06-19 14:06:07.360062+02	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2022-06-19 14:06:17.194631+02	f	a43af79c-fad5-401b-889a-a363e36aecac	12	1
2	TESTKUDOS:10	HRGRTQAX05S2Q8P881TJS82Q05PSXSVZJ7686REZX4YK5R47Q1WG	2022-06-19 14:06:20.752813+02	f	7668adf5-d217-422d-92ef-cd569f8018db	2	12
3	TESTKUDOS:100	Joining bonus	2022-06-19 14:06:27.794023+02	f	cadcef48-6d5f-41db-8c31-a09a40d9f932	13	1
4	TESTKUDOS:18	1DCW1ACQCWXY35T5PQV1FAB1WJDPJE4AHWQQEKGNE8KQ151K4FEG	2022-06-19 14:06:28.454299+02	f	16cddff4-1bc6-439e-97a2-70fab6ee18d2	2	13
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
1c75882b-64a2-4661-ab39-e41a51ffc059	TESTKUDOS:10	t	t	f	HRGRTQAX05S2Q8P881TJS82Q05PSXSVZJ7686REZX4YK5R47Q1WG	2	12
bb82dbb8-93ba-40ed-9f04-74d93682aacc	TESTKUDOS:18	t	t	f	1DCW1ACQCWXY35T5PQV1FAB1WJDPJE4AHWQQEKGNE8KQ151K4FEG	2	13
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
1	1	81	\\x5e2ae1c64a2c1a432404d23c3041845d1031c6898893ae0233b2788c18ed1736690774c83669fcc8020229245aa700b4c94cc3841eae15545bf1ebbc38c74003
2	1	225	\\xadad8526f9cafdf8cbd600e63987ef4c3b70b27891c25013df07524988b9b6aa32c50ba6ca8b2372f33c07579c876bae93ad3f50e39ebf7286b36e426e2c0903
3	1	96	\\xb524870268d6946cf49c3458e1764b82666ee7f11afe519ef5f1281fb9176e89cea68fad579c1ca40019803b6bdf5b3ddb0f6b491179e3e9f51060ff44599a0f
4	1	126	\\x99ab1fa3ac26bc637972de6845e8f72e0342a5db99dc75aa2c27e39616408f16b19cecbf796aa430dfbe2b87d582a87ffe8e754f1a4f3037cc9a2ba84928960b
5	1	245	\\x7e3bb08189693d75009a3133405deb2ed97f092c70f223bb78d982881cd3739cdff2d21b8f1e60645ec2ee7fbf479ff0246d9c8db535984301da6e00af8f650d
6	1	110	\\x721e44c6b056c380bbe22b668a5799ab3769d60b41e3aca864b09765c6da9d28b710689d6d82841123d932282f10227f247e4d2c2c9904cbe5038fe4925cfb0d
7	1	324	\\x0672a28f9aa91962acf0c190b4ab167a4fa88616475247171d1a547e62261490bb9a995091d241387a326089bf7b5abb92ae74954f58fa36cd870207418fbc0f
8	1	121	\\x5145ecdc0f55d97a7e133b394303afc55f665a9ec1ed318fca6b4e5e69dbcbba4e5b9a28faa20cf832f621b5a1eee1407ea470d159a99845995e90e8d49bf603
9	1	200	\\x7c22cf64e19192d254c16b46323fcd36b265fe6161687c2414cf99c26b77a02c984defb9dd2addbbc509ddb398f92856bdb9b5b9e3c89c1cd4652205f31faf0b
10	1	224	\\xb1d0036178e1fa74eaab101e2ccf44c07e0a69758c8dff16fbb5a85dcda18a246fa5d1f894af7f184f9ef930ce4bdbc325437386f883d01ea7dab6403b10470d
11	1	244	\\x535b0e8a20b20b8adf1fb7ec0f1ad611cd0c6f8f0f1bbbd739451976e2b7a7e4bbe903e09bf1d286efa2e4208d1a2c68b3d70896692c68b7f45138fb0e88d00d
12	1	170	\\x2a70764ea0889074b13da192230af5e9a6cf4fbc7e28e3acf2672b594c6075099cb01dd99fcbb8dbfe72f07193ec3e3619928a9095d1c6970807c1fab0798c05
13	1	364	\\xcddcf82bce96d8f20e00beb30dde66c827719915e45f68003c442bb000fb215db4534dd7bd0229cdc498297b56492eb512ce3d0b850d874f5a37ecfdb3cec405
14	1	23	\\x556a61324a8f57155988c25c1b02bad03bbb5b2f396e430effde1f006c3da8d256f7020e4e8f081924366f9021a375f2054699d8f66503dae7d287fe9847b308
15	1	67	\\xf28085a47106339be3ffd9421a39866b58a2f34acddf869a88fe38df002c6a83a82ed757665ffbd63779df16c8801fe2e7ff6988c8d28237a7339bb4974e980f
16	1	74	\\x75e9d9d51228135f7208f1a7a77d3c66e0b29876d9ff3861cb6e1f4586f54528d96172d35c0e567913313169b90ec2e050af1343db2596bf254c030cdd9dd003
17	1	33	\\x468966d06412dff760ba704148d346b4d9286646b157fd0859d6dafc5e82f37ac587c549b2e786a3b8fd404d7e61cd5e4182ad2c19740eb3455578000039df0a
18	1	195	\\x0c294f297559680e73e5945cef01a6206c74613de77b802c2a792f413c7198fc315277d17fb0a6eb568ca04c733a7d01556c4b4b3d8bfdc88e3df85a810a6707
19	1	41	\\x1ade82b3faa959a5e34c820c4c7a5455c31454e520b3eb753225eecb99340a60f77d85c5229ebfaabc438da2b50381a8875c221c84f78d44f8626ac80078e106
20	1	235	\\xd2bb1d4946c003b7f33f30502ed81659ac5f99477da91e0d86c4a0fb475d344fb03aaacbf198d7ddaad0b3bf6672ba640b20792fe372d6b6275445972b8e510b
21	1	419	\\x5c8abe0250d7f4316c6fbffbde1e4165b5b1e05cd9eba0f872969caf29f788e44a371cbc01deb1471b3f76c9f158ff98835d00670609fb0a8f86f502d4b1be05
22	1	240	\\xac46e258bb6a104afc8c8fc19f6be5b9bd5d73a7ac90fa8ff9ddb9fd86d1c469d3081e9bd003c9ae44b02f2848645ed73cdc3248262ea6a10d1739fb0db40800
23	1	395	\\x1f0041524e4c7c5a721c757c88438f05cb924d3eabf5e3a040a9dd99f4128a19891565e7d37bdd7efbc0a05d08b7397fd7fc1bb18cbc045f465ae839d3bb060c
24	1	98	\\x739a786b40b535301eff6ec3fc2b4abe6c6ee13716fec256b39595e25760a0a8b20b93d4670efc6eb168b626e5df1c6777f0b1d5caff8e20a2d639d154506001
25	1	340	\\x5cd78229d21ff8ebd8cccb1d13ee02d127555920f865d91ef289338492c8ba3fd8066148c84cea632e612986371e6cc35a1f7fe53e3d731d64537c3707487304
26	1	270	\\xa103fa757c69a1ee20d6d4766e8f0a81710737e4550845ee84008300940445d82e162600a3585774cc36932a1a438a79bdfa2b27816412b4704229e28ddd460a
27	1	129	\\xa706ab23872d2a3f09a279071af0c07a652e3132d4db06133f0634e0173d2466fc32a682d7ec931a3d706c0b6c6851ba90fc875098c4b7f11ad6c3f0b1c85e05
28	1	139	\\x031948742c78dcf41b0c2fb64394aff794e6f30f404eae914a0b27df95c761b330d6b614866b5a19a67fa0e2abc1dfe087d9b8cd2eb281a6d51abd4be9289c00
29	1	390	\\xfcb21a5da1dc1e53416b24d4f009556b6b3f6582a76b502b4a4e71f432ae1959d403a34781691c41e7296e5c42ac5fb40d9736cf9a38c97b5657cea3e28f5001
30	1	140	\\x1c2c66a02b49e6c51b39b397a302cdbaa16e999346ed000c1b18ec687ac6fcf700f526e820bdf64fe51b51fe3771e9dbb214499664d9d520b5c9f118cecc6a0d
31	1	19	\\xb3043958170efcf3af2f849b7c81db8bc0429e041d8be644ffeda4d17f01b1a93b5a18a87a6b7c15e1388eac19de357fcfc9238a1d34465228d19ed4485b810d
32	1	157	\\xca60b054a3f9c531493d4b076a2a89f01f7bc2b437c67741ca073c65b84cf0b0803fa16c2c4acaeac699626239b0d73074499cb355cec58c8507c972409ece04
33	1	54	\\xb6667ccb86919d21bd96a58601f725b2aa16e53d8badf4e82117e29458e5d56d01161813665356fc8ce0289dea35ff3d68cd845689c0bc5592e80e23ffb5530c
34	1	198	\\x5be3995f33533656460ee6f8e5055f4f5c1aff78735601682bf703470949780676fc114ef640bb46e9d3c10d71c25d8299418e43194de44b73dcf936c2704a06
35	1	52	\\x55fea0391d0279ae0f87042054656d1debec601330c2a414f50e68572fe012e31086a0d54c83776dcbb17c47ef828d316ca993279676985ab53c133784e4780e
36	1	278	\\x1e7a966fa019e5cc116194e0c018d09850e0e8fcfb59de7bf88ad3ce7a7481c47cc1b3ff04e0c6a5b05c470d649dc4c1b1872966d561e01378080695eb0bdc09
37	1	299	\\x9ca4a69429be91bd19dcbc0a786b7152b35babbb7558c36bec3a5c9b9d1067d7cea0b4df494716e6d1d31e7dbc57991ab7e392c401c835a639fa7881dea1c306
38	1	150	\\xfad6eaa9e06538496a15b92ede51616aeccd700ca0cffbc201ecbc9da98c96a64057a05e14913a7725d0ff9a12b83e72525b9b703f89f5a95a873eed6913a007
39	1	231	\\x336372e1afb326accee1153fd28a7f5173f63d09fae9dcc8eb34e30020830a081e51b6d070a2cf99af4865948ec4c0e8fddbfb1156cbd306a4c7757379f0900a
40	1	349	\\x85086347219f6402377d82df4ed672d57f7c2e1a2e6e0dec26c1807728795814ccdddff12897ad86c2a0f7156370b11e7413e99a4c1d163075bea8ecb2255902
41	1	298	\\xc09a6ca6c633ba63ee855aa2041cee5551ac358b0f617d505a448970dafa5007f812468c431d4e430f23e6e220207dda8a0233df9fd63af30fe5940ae44b630c
42	1	160	\\x2faafe1b53f6d53d008369403100566af0e08fd6af0e53bba5699c600ec8a0961c5bb3894269e6f7010466210d68f5669b1cca82b6a79ee9229e438e3e4f3207
43	1	327	\\x8b7ddfba2a5722599fb83325c914b5a9f6c50e3e1edc07894d141956105de311af6eddcea0ef9b3ad16003b73df2e0554a05c391f7e7249507b6ef3c95243f02
44	1	264	\\x7ba2027a291cf55337ea8629ff7fb7389425fb342839811b1f1c3dbc2bea8abab88813099ab9e1e3aa50d41dac2f9e3dc00b4c53dd489fb3ce99f0ec3ee8bc0e
45	1	331	\\xda8fcab64665fbabe49f71701585a4efeb8b4624a8dfc90f5ae6b718aa691bddce3cce514e5b8eb25f7dde831b629233dacfdd729592755101f78a9eac97c202
46	1	164	\\xe741c1e0b424ceea9d8b372616ac7f406804d45c978a7717ac806d24a2074510fcaea4ce07cc301508c13a5cf6076bb3bee7f3c035af69e9813b4327f4986f03
47	1	97	\\x3bc084ad32ab9d856a3f78ca704a7f8cb203615139b2fd7b942f1303ffebc3f8400b8b5ffd4ab9321524168d411f34627799f0372bbe623b706f22587b2fd005
48	1	115	\\xbdd269a80429559e2e13bfa6f25a00c4365a9f5df00185c34cc1f3655f3c50ae23ed04e0044590fcc9ea4b5b29ac5aa9c963fa8ac2409231439fc3f53b2e5e0b
49	1	197	\\x1fef5b3a3a9a9075d97143674efa156b40e5a03c5b51a50ba62522a6accda2285b9872464c758b0783dad7fabf448a97b0da3ada834f8a5ffd9d4ec1d0a5a308
50	1	268	\\x7d0c3053c15b4dadd9667f6cffb4d3955f2133d42c04f2726f2f3ffcccf695ba00b2461c6294527bace3f0bce6611f53bd3d5ad71ecfc2c801bd4c3709070e0c
51	1	151	\\x33cacca0311ad773f3bac91c90d87f2cd4223871386607bba6c21cea6f8b15632dadd80a36d8482633dc4d9fe91971a418d8d9d0ed857952300c1d57718f780c
52	1	102	\\x587d1e9e376b806fc136e05438a70eeb653a89849c941b1c576346dac49d7030b82de087e4f5a3b91aefcd35145f17d98861ef1703a865fa24f26258ede5cf0a
53	1	203	\\x45abf364d1b6948ef922b20972de9cced3bc2f31a3296b7b5d112ce1233adb3f1b672aaaff26a149994d800d03c0b458afe96ad5c55b41fa38d5e3a18df55701
54	1	232	\\x1cbbf812a250ec093715aa492efe3acb18718d315c1d784f0e33a0ac4fc5fb7680e31ca2633bb666c184dece355983947178e183290d3dabda360a35d038b604
55	1	329	\\xb09b39d317f4e4eaea9757d3d1eddfed230b88475db259bd482908924452ba0b0e27d5ed6f854ec9d44ab3e9a2c745d7d5ae340567842ab6231a2536dd0be504
56	1	173	\\xd877e0abda526820c6f07df6082e4dfe44a2e8ef9094cf69d776e0aa21bd7a48c2eab5037f8a19732b1c0a90becdda96a2b45c4e8b0f8f6b2f585ec71054d50b
57	1	134	\\xede1ad426861d61cd21f0dafef6e59ee2ebb021d16e6a2a1312ffbd163dd97569b438bf980ef45ef0757fbac3a388a826009dcb80a963a8dc021bc57ee030a03
58	1	123	\\xdb17ea5e47ba915a8acf0ce235e8f1e1e35e1e02cba13e2ac2a113662a557430f06675f7e17e1c64d1a86566c66e08f412981a2db397cbf9e34eb224acc69609
59	1	103	\\x3092c063bedeecf60e6d57b2bcc3d9e44fc2c39bfeff789855f0d710e553a315019aa4fb35221ee56b3b96d26ae0ccfe11865fe87eeed1c6fad1952c67acd006
60	1	86	\\x987746a701f9068b2219d94e90206d0c878b25a84314f59a0104d3ba31bbdd88e3fa2e3d1f0accdbf4caf6f2c07f145481554a59d41d4d3de15762ab007e3304
61	1	184	\\xb00fbd56e33eb2dea1812bdb441a2afea8e48c92f4bee0e5e0a6d3db7b247066535bd0d1a2696b4ab6d06d2cd66d5a3095b18a34a2806ad9f54565262092b909
62	1	47	\\xac33cbe4c07dd0bdcd9b73c4b1771a5b878f823be9d657e1713f60c35a2325bf2489ff571cf7cae1065fda86734336124d70a6893e1bd2d14c7a87ac5dd16309
63	1	209	\\xd586bc920c8116aea2138d3f9031f2b046402f3caf8c630daa8e87318db3bf2aee66240eb724ba3241aebdfca1a02e86d30761cce3e26839da080336ef6d1500
64	1	206	\\x15b65c9d8aa6e50d9ecf64da412ef6ce3e5ea6394c2c8b7ee3c4893a580ddf1b4ec7640da3aac2fc266386a599ca1351a068e0288fb8951dd57ff5d0a216ce0a
65	1	204	\\x00b6e85d285a1c8284aa6da37f6a3977da56c75b85d4ea5bfc8966e352006835d69a2911d1de857b6072bcef5368810c4ea52bd9f4fcd6c0c3d23913fa0b9a06
66	1	258	\\x4c8119485f104f1bf020beae5085d49b74e9347b7cc1eeedc0dfb6d7ca9ed7128d217af915a8d460b984eee5d8292e3dea2a07611eb7f1a54cba7a4ab70fe30c
67	1	302	\\x2ed8cbeb549ac005e1e0affa21dae53cc52c936b44447645151d61a216f5da6529f2534441fcd4ee79affa4c260f07cb2eb9949df04d4da984a21330b4e4a806
68	1	130	\\xae5bc1f0226aca5136e504506ea796a875e1679742364403dfcbc984b0d22a535c562bd29c9abc8f123f1d3660fa2f5205e2fadca0c41e2dce48dbcdc4219909
69	1	159	\\x2dd74854fdbadc82e720e488240418127395d01946f5e2f5fc2f7a565366ff0fcc2c474590ec0703fd57f8d61b5946c2c64bb4f7795861d0387bdc05a4872f07
70	1	175	\\x403318148a4a45facc9cefc5e39ab82c66976780889868e7c61409e76bfa11571dd3640ee66b6364b546557a29e515ef183dee7bcfb9805da9e43f616bea1504
71	1	131	\\xf44e445aba8fa818df3d8460103e7b7e6469786cd473c19f93c087aa955688025ee8d041fad0918642c8883ec261ebd229985e804b110fa5c31a5f2c7fec4d0d
72	1	205	\\xc9412a74c4d671377a0f2da9fc950d35c6cb1694fafae83ac1dcd058bbd7c64fae0d2ad781585e01e376a019a8b19d41946cd2f3a42da93c3506a93e27730901
73	1	40	\\x293a8081c9c1e63388f010bb55e4612f33265cb7d2b76af292852bcd1fd384fb2567d8fbee5fddfafe45b1c0195475a39763de11e8e31b1a9bda10ddf1d21607
74	1	363	\\x304b2f94366aad4e9815fc40227b585be5683366a18bf4afdec5c42dea324908fd0ac637079834932440cb8c572ed8eb2318e2847361cab2a3b2b57b81095a02
75	1	70	\\xcc8ef960f32335adb4d3127852b4d60dea91a06a8cc64427c498bf5b81e480f5a4294aba5a38c09211a6834004f3d0116db5f29e6f23c0b9a545b94dbc6eb40d
76	1	413	\\x10111b9918697f5fbd199da212ae9f3183d8245fc2a9a5d909a363ffa8e5afdf104ed743f89e1eaa1bed4005266db18f865417ba82e6c02e8abfbaaf6b2f400c
77	1	177	\\xd298b4966c5bd112c2ba7cf128bc8e01e97ca907b7d1f0324e5af784d103b6a3ce8fbc6c29f9c818994e563251519681015f470b429c34502603d29da8d0a202
78	1	5	\\xb4882b3db6b542add726e9abe9b13a20c270fa42e96b87bd29941d4559707676373ed57ac505c689c7700144773d0222977cfa414abfb9e531d9beca2c08630c
79	1	16	\\x4bc6146ae728f53b22bb2f9071a671919a23b1923615222bce3b944070d09e97e43f360d79fa04303c21e3ca9bb6d660e021b5bc5eb67c77a812268edf87930d
80	1	122	\\x6cd26f81c089287d54248ef92a6be9997752487a2e317d070435edf964454faa642bd9dc060133300dc8dcdb0997a667ccf775262191077385e1e80f8246f101
81	1	17	\\xc97f1de820927b6108b2c21cbe04a46f2730dc6aeb5d840afb9a140cabd0ccd660dcfdf422d0289410452270a61cee9e4c25e8e155223c1b8f3f993127c9a002
82	1	57	\\x1147af51ba348e2bbdc2f5635d09e0fcc7dd6c402245c70ee1530a90b52b1ca2a9a2cece96718dde2fec998c618ed6cf63447923bc18a6d471ac8155a4c87f02
83	1	269	\\xd19876269e5c1d82e6c4c3ef684c772e1d6dfb27c76e6dddb9f1fda36efb9a9780d2db1915e36c21ad5dc60ed03ff81ab3d56e11c183d736daf0e56fa068b300
84	1	166	\\x76499abcb322073da74822a06f41e43f0cfc2b39c4519b019daa65fde1b22645b99e6f31e0ba0cfb8d16c7b015d75c4b6b3d594d5761281858bdf93faf25f905
85	1	236	\\xcdf02e9ed7ffb1e1b09595a8b79761cc076c1ea9838b85e09b570de1cfdd38c9d16ee8bc222b39d7f96ac8530b64ad822c63a559c303d512a527a0b744c61308
86	1	279	\\x84499554cfdee3e2fcaaafd1407ba8b4c3ca5a9945dbfef07b072f8a6ace4e3575f09fe930fe5a3094c57ca18ceab3fcfdc0ef051dacf535e85b7b90c2d3c90b
87	1	176	\\x475c672cad74734d2d824858db4c58f06a6c10b815d9e6ee86d0c091c5a6120ef89b03b0351ca96dc1a911408341fc352073c04847300b648640f628bb784a02
88	1	371	\\x9609a3dd04f23c19e3bc3cd5ad9c2800117c545b201522cd7a6007f42ed888e3791b7d713e72f619d7b2b7ffd9e9a342d1114f5d2c6971171a1466158c13da0d
89	1	249	\\x81a585b38b7c4c6ed1ff38f7bb204812e8d3985539d86f3e40b87ee54ca66ec13295a021cb32d4e42d28e9423c2d4e551874606f3ed93c3476dabe719fd2c401
90	1	25	\\xfc49f6afc06ddbda59c97cf721e9e0aed4eb00a3457d8447b229a04a81063fe0f3e6cf2d151bc07d0392f7f62cf933c07a8a089b201aa3ea9a73c420ba992a02
91	1	152	\\xa4ef236692d4b4d49940e9da1c78973294393b25b0572de95b0e016b52fc9339a2cf316b5c1eb7e69cce1696099c8eb16d42b1c86d317478d74d2051fbec6206
92	1	368	\\xbb8754ac5491accd8038f8f81806f691279805ee3b7c8df129dbe348505bbeb3b27630971761c6c23b3cc0c223dfc7f74d05ad42d1f621dc891110d01bdffc02
93	1	161	\\x59d52e8817ea100de37df9325074cdce50eb0ac4bde3a95a7d0dbb33d7092f2d9bcb107103de987bfe4ce6a1d7c6938223e1763a257365fc5fc5e5aef49fd206
94	1	37	\\x292af2ed2a16ff32e160c0d5392c545f41e9ecc939e95da46a5cc63a70ee6331a0d811a2e64ae82ba9305aacc2f9a03d7bb16e0dcef2516d01c4cb2a63e3f509
95	1	310	\\x8e3622e1742997ba86a82f865a09f427a96cdae0f5b1ddddc0039e2c71f50930479d0e895f9cde79f5fa2741f9f8eef7c95b594b29f38ec4cf2dbd0bdeeb1202
96	1	342	\\xe7c8beb326dc83bafae9cb168e847a86ea2f5ed8fbf86c98c404a644e1c58c946755dc083b25e248259ed6af8df97ec0168fcff019318fe54a6ae00e6848cb0c
97	1	295	\\x3774c318f2f7e7e29ea6cd511a2e659c6491e6bf3f3a2ffd0df57fd435cef74c08fcfabf3ef093c41ee3eeb79669f17527978502e79cde9ac5e8dff3d902ff0f
98	1	420	\\xec315f89a0e4fda63f27067ffaa68c2f9076c985607f21772ebd98b1257332e4222e47c393fa2cc26c920d577dea52e734677b2465de846552382af2a794ad00
99	1	24	\\x193137517f0e75ed6e9ef22b0e505ad629f4769ba364e9a0c389f3087a092e366228b0de535629a46e9bf3e1f6762c0c111bbea1314f5b9433dea6f4b1fcb509
100	1	38	\\x66e5b84191457a6bb5cffe177926c07d81d08db34f61444fb9d37b5519deb3d0c3efa1869cf754f49b02bdb76ab24d2daf7cdb8d5b57d5cc04cd704f5fc7ac0e
101	1	399	\\x92f556b5bb3fa83e7221d5e576de9215f5535b325fd9d6f39186e89393664da920f798a43a36661318fc831956eb06de2a042560dc2137902143f04c07c08f0a
102	1	114	\\xd3c8f2042cba21ec89fbb63eedb0d2484bc9816237f1cb38fae120e0f2634e01ed5c76b7dd79c63ac8fd72fb55717f60e8e6f0e84d70d0257f185ff0f49dd60a
103	1	155	\\x013eff58fb4bc6e9ccb167bade34e7d016906f3a6634fe9204002c917e3dc810d61ede4452d222234b21e9bcb7ac486dca6463dc86b2aa4129d87dfba80a4d06
104	1	116	\\xb4777c146648cf8a77579f83fd8fed7a3b3f2c26dcf6b7c48fc62b13c71258b3d2ebc5f25b2e7221cf2d8403bb4067b4d6ad96d6080d7573fd9ba5cc1bc3e209
105	1	190	\\xfcd097cc749539b498640853586d8b8f88b68e2cfd1e23ad2db492d5cef2d7f0f94e2e74c45c38ca45d5f73b544062ff6f17c614d7e4ba9b2508752c01868503
106	1	365	\\xae537096a182174a0f705d441005b85a8121a0fc28eb6ca1a32534fa11b3fd88f44c822ba2e2d8294ae2935ede3bf7f5667be2427f46a0f687d8390aae7caf07
107	1	148	\\x4cf2aaa26355a96ea367ae11d52a2d35ebcc2ef5e915dad2cdffabf0ba155c0c13599e12fb5b73d78df7d6bb01af9195ba12ad8d1772b8bdf00b60dabadc3d08
108	1	61	\\xa89152522c7c80838e97dc3d6290d7dbed9263f2db734dd2a3cd1d5fca0e012e63c43b406452660b509e89801c5667390d749a04fe9f0df9eb72f8b65899770b
109	1	171	\\x8a7dfb68a0a36e22880b0445cfb2398c77753809f3f393f5e80b98f7b610edb6c5553956785013e8fc0e786f5ae1a8923948c2bb6865bbbfdff8d84767ccab06
110	1	144	\\x8e9172c021efbfc8b530e415540f0ab03ea35f0dbdc1fb0fcf8472ea26a47c1644e09c3def1874ae96236e4aca7401cbaa636c0bf40e760991016156befcf70c
111	1	280	\\x23733d5f27909d06583e468a611eb1640681f2df42405e1801a6380299ebb3df943a9b464c412188c6856c2bd611fc139b81a9d9d2b6cef1797056e53148fd06
112	1	220	\\x40dffefcbb2acc17741b8cb52590e2622eb7915ed233852126605053c814f47184bc21572634bdbe46a2e51ee31dc9538a86f32c430d92aaef635026e87dbf09
113	1	172	\\x3deef9610e8d74edc2d8c71e70a8080a3f90dbcd9d70cda332085fe781723e4e781aaa04c1a7832f36c4733761df1f3e1a77f2a5e7209c65587d2b7c7d6c620d
114	1	360	\\x35a1aee149fd937f43dbd82b0fa55c85c3c95f8b9b1b02b62d40d6a0fc0c20fdb5e8696a06d522d90349e55b0b262bc360f8cef35530bf1a566a3795a103de0b
115	1	398	\\x6fcb9cf5787f53615c8a14387ade9dc81e794a1b9b08de6c01b1a4a81f372c40e3ea1a6ed19a3aa0942cbadd23fa1377af1bb5efcd5118e92fb295cc1ea27b0c
116	1	228	\\x3f3a4b20760ec9139cf6755dc92038dd5e3a4b3f165033b826e90524a7280a458110c104865a61fd6a0bae1998e5a94b1ffa273d9b0151ba6e8f23a87169b50e
117	1	90	\\xdab7e865494234f15ab5c736f76099ab435666e4eb9aa27f42b4043e23d69f5b1b3adaa051d43aaba356ec83fad1e909850f6634a8fd04d4bcf67fd5c8c40a06
118	1	253	\\x0a4e42f1c5094a5c1d6e47d28da5d461b1295fc565a6286f5af0e8fc6afc70240e5b92c5456ee39c8bd459ed8a878c3a724ebd2fcaa45207f6598027df01e308
119	1	179	\\xf8faabbcb8732d1b05c8c96bbf9048e0585552e2716862dca25ee9807517067c8a90181a45351d06ec8d6a66121230cfa14096c8177c09703cf1e5241d7c8800
120	1	45	\\x4a563b876a6f365371502de3b9f22ceb0ae2a793a8964982f606f1a80a0d8b4d7ef65929ce51726e9a61753f838c4a7cda32d2f4035e498aa7b581526665a008
121	1	277	\\x4d327fd42dbc4c62d3f35032005053a7f8149513a2aae2452ca272fa2abd74979536e3b92c5605339068c63ea8bc079f7933a622307ca46cbe0be185ea1f860d
122	1	284	\\xb90cb53a770cf18825d2e9116001f722c189b9bce2da12c08c2f8ffb3259dc6b604170a7c51a6100892803fbaf90be31b03692f6ce15db481fbd788455494b06
123	1	234	\\x6af7e44b08db815296903f32f3c4c93877e494cc5ca9521370efbe634e0619c0dec1f747a90c504370442682dbfb3bf2d1a6f6a2bbf6172c18bf148fe8197e0d
124	1	53	\\x7b6326f17f11bd18f5e5b9ea6a747e747b4c4b8772e07f65e4c7563e71033dbc272f729a2358b7fc6acdbc53615b75eb7d97dc48f28a74fa95bbc5d838631d02
125	1	95	\\x8ea7452ad6557e1506aa167f861e9be0f81676966f71707679a31b370c0b392a03f1550d7ccb0e46229c07180f78543a91734f486134f91d6d3851aa16055f05
126	1	281	\\x63c5d2c002ca6ff05e81ed96276343871fcf8c430800bd8c6a7be22daf1c4d9adab9b43d595b3cfe954538c3a0a1af0d80a13fb359f1e590e16048ff6c78aa08
127	1	353	\\xfa6779bc51942bd488233b214af8fa0e9c3a58c5d00f230a60c0c69d7ff4c99bac7beb616d3601c42339389095ba868d5a8d0b806ba5a6051b17c7f6e0af0607
128	1	217	\\xc6d373974154bc15a4da491c2f217f42dd8e784a66b95dd660a3317241fbd31d768bca607b51a19e81cbff22002c5e609b1aac918e1284bb865a335c776ed006
129	1	156	\\x7f96da32d0f3d7511f96ba188beeccc648f4551ae1e623fe3b6f31db86b269b78b48c682c98c7c0d325f2b60be7017102b1ab7abd737610e2b7ca87ebcd55201
130	1	250	\\x5b35b714683623e2a0c6ce15e573957384274e0f3be20e7abee31307da80ca33fb1589e5574f36ff07ee510bc46276528bc19d220b4044c1582f34ffad015a0f
131	1	380	\\xe4c704a48005624dde50d05a6ecbe7ba8bd8b0e9865b3c25d7bcee83311b95939e1973cef23381639ab312b3da912b7d10701e42e8b77c0593bf65f477cae800
132	1	136	\\x07ec39c322baeab5d455d422f4056f91d4b9288fbf86c011c89fea49f93cee568e623e74faba27ddacd8b50c3f5973f33664b94a4100c7b7fab27cd95af82008
133	1	337	\\x58d4c27864c3252fc6d097f909a8d2ba438ae2773454580af43667287fb8e282c2ec5099e12110f15d567c5b5d70f2ed185eb0a774fc71e91a3edce2017ae907
134	1	294	\\x360bab3efe612912891e351982662feeb4a2d5f371284158eb9f1d5b259db92fe37d90c5094e960bbdf17ea56a335d354a62633863320f5b5409c4ce22eb7305
135	1	286	\\xe8b82736ee20581c8ce2c032319767294c97ec3d48fa2916848870a3525bd61906cebfa0e2d806bb647931530f642331e11a32ee23691ffe0565a52af8e8a201
136	1	296	\\x6d1d3a04131d10d4caad5a4d7c6c530778f97561722a3a0d14224d42479ab190d86e9747a018ed4195938714726c6c7d33e79f04be3304123a8b214cd7ee6f03
137	1	251	\\x73b415eb0bd462d1d27a855fee5049f7f517f482b8f7711b0fa0ddad34eee4b0bd02638e7439cf193a9390d7a2e1dc6d4b9b694934d293603f6a9cf591f78304
138	1	149	\\x872fc95a5b9d6d4e33b356960590bbec48997908e40c402ea3164d7ecba7a6c1010a4e27735c537ccdcba7c28b625a9124f8d07214c45d9b8c076f4b33cec10e
139	1	196	\\x3062df479d576fb14276dda35b2d736f8087b10be7642a4015b90db0ec87147f3069b61138b37252856a105e02b8e7c315ac3300fb59f2f6502106b9b67bbf0a
140	1	29	\\xc48d45e2510af07e864f23d17cf34e3c1f15dddcbe20f14a18ea8b998002552c3813e12195e61efade81bf98ea30a37633b05660ba7a4302293ba1025d675a01
141	1	154	\\x6fade8f89114ef17f26c37b26a111f42c1ac5802db4b008f42805ef180377c81673895c8103a64fae21a62b468bd37995ab8ee646e7cc0f3a9d429ab8e7f1904
142	1	355	\\xff092e359b782c6d930c3e7bad08254863acde3f710b322b43ee12042ffb6da600874515debe3c9bce8af31acbb7c91134d6dcd9a1f0de833fb8fb623465e50e
143	1	185	\\x8cf5ef75ce9b21212e9eb12c4f065309a354ec8bc40d83933e7a384e13d01f13896a042eec1b501819dc425e773d424a6ab61ff24e8d5237caa115f5f846a900
144	1	101	\\x06d6daa85c23fc58021d6372980f269d9d8549c8b6a39c8393edb59044e21555622129629a221c4287124e070be0dd2f61d3726f3319a7c8dd146415a4743503
145	1	213	\\xef8c48a52e4802969fc90526b911a49c1b7651f88302ec5e4f1bd0b00cd027739991373f9ae526862cfb7894977027f6019eeda126add6f403cda1379d78d506
146	1	247	\\x88ba83b4e9893f293015c2199c17d60cc8a8be93ab103725e47a609929b9561b3f9d4e6035233922128efa55e24eb3501a10e2b83e37ebc1f67c4fc9c57e7e00
147	1	293	\\x2e864dcb5060d4cb98a03e13a0906ce7b65bd3b30af09a020a74a28dc69130107f9eebd339fc671212726692ae34587e114ef5ec16910c7cb5026c2e115efb0f
148	1	135	\\x1f645d910348ccd3f717eb06470f242202e9f8f333dd33e307dbbfc551ef97bf0bf0ee3a51e61b0cdc87d864bb3fc86f5e01903b17f95b49a24cf0ff05dd0901
149	1	357	\\x5e6f69313268efee9d5ed9c137beac170867aece7370111105f97541dee2108ecd09616002a4d3bad9ae9b7609b97b29782fa1c9b5b6afd60eec511bfeb67208
150	1	22	\\xe6d3ba57845787efd0be7f2d1f7354a0e8681c3c9b88911cec79400c44ca87f8c22c2848e64452e21350be24c333eae12a5847a15d67a723e00ca29e41fa2002
151	1	239	\\x3a10759ca3a627b00446249b049afb85ff072f964162f14c8ac21eadde78b4c4d16af94591627176d52eab124db041fd40c3f14a5832f6afb428245387a8d003
152	1	262	\\x0cd3595bf0918eb5456022cd82df62c677c0d3a447e43651ebf5b85bb753ec1d22ebf2d482ee7646ca1cf87e345ac5c05fab6249f8ab897fed85cecf07f5160a
153	1	285	\\xa4e96516e5e20967d49fb8ce8f0cd013262fa38556097a31bafcd1d868d974c40913c423475ce21616edfb932c10c3fa1d7c503e72f8778b8398facf72103507
154	1	263	\\x60a1a443c673d983d1724b5d2433a8ee3a356523d902fbdae0b01e356917577ec74cf9476dab8ba7be67e6de06ae66b2d540ed4efdc4ab07958f9bb81bebbe0a
155	1	352	\\xd363d63cc9f47971a3167c6de5f72d93a2fe7d7214c8970019db641b850fa9994e4edc3582a7fa76cc5774a0be82369bbb5f704980849857ac5a141733431903
156	1	80	\\x1c5f1b612af7b2b8be6b75a36a7f1acb908b6357694c43c9bc00ead8597e21a3132e51647f43da608596f59421b27ea013df234b249c93ae146ba15249b5000d
157	1	393	\\x2b58f41410c5160341656abb80b9220a3d0ddfcf28d3e4973f68544175820895cade5a72c0a79a6d7b81d4518a76d0b65bb5b3a82d4f65b21c903a269ad2f701
158	1	305	\\xc360b77015ac3c382f74cc61a7261fa15495fd9f569a0f29140f2262926725ad5762086ca160e9d6f4b7d5c1022c7b84deb419d5facb542200bb8c90e4c1d004
159	1	167	\\x6b093f220a6966f8668e369b8b3b6f669263a8ba5e2f8aee82f2487fb6ef4f80c94e06bbe6ab4cdebbafab386ecfb5df934a10e54782ad2c5397575e472e580c
160	1	339	\\x4d9156c1edf353a5d3d9e89d499c389f8e11846e2f5bfce3b3dce82993f2886fcc2e6dea21e1bbb5ca6b0c083f69c3571b67b76539e72367e358e629f88d780f
161	1	362	\\x3a2dc3f2f1a1ede2e22685c78a4a4ed8b0538431f9d0ce95673ea2444025da16354e8b779b69eae71b9b6fd5bd6b2f22322b034d2db47177d70fc4916ad71a09
162	1	138	\\xd68d6525b678d68f4509c1d1257619841b7d7dbe58240c63286728f6e0e10372b1e70812c38f9ae70de6c6c0010a1f68a0784cbbc185711cc6cf076b5062fb06
163	1	76	\\x500f0075af712dfaff7c88534b1c49d39f75e59ee9d9e1448f3ee3a88cdf9e3a5a2610d6b99df3596a93b919dbb8dc3a0d1da89bc8f2930d19ad4d3941fcd604
164	1	163	\\x15f5e8d2f0db9f16c09366a3aaec6d8bf905981b392830f7919427443db3e746846164bb667b9bbdfd3fa5a414f299589e356346147da5cbd693000ceccd110f
165	1	66	\\xe35f91a1fd109aa6b7e9be5bccfec423841b938c9d15484f18b060ba2f373a8d72612c9e86e46be6511ea4e80827697416baf874b1c0412675f6a6176fe0930d
166	1	314	\\x4f20343ce851459ab380ac2f0b78d17bc94ecd016472b35e6caa8fd3706bbceef063dea190eebb6592c873e8cef98f56bea6a5c8d2c1d506d2f298e687d8ef0c
167	1	400	\\x538010e3902226d16349b4c5393619c8c502aaab140f80e20e7dcac75e294eff46e2c24407f491354e5241b1165f79f856c66e3230cfe5af08f57d53118a170d
168	1	13	\\xa5121e894063c83aca11b9b6cf8f2c5a52483a7d5ddb62447693d7530afb299c22acffed80ef23a192275ba7bf7c18567dd6191d26c309b53dc1975bdbd0950b
169	1	128	\\x038ea07c154db88cfe4222c14b148b5326f5192caff640c2d9d1bc1b4a8ad44e46bfe755d0653b275b3333dbb50cff756f88b3a3f3d1542b4db4c54957e4470c
170	1	229	\\x111171a650c77d6cdb1ab6ffae5ce13accb73d85336eddb6b8221617fe889e54fdbcfa3789c482580cf7f518a2e839a515d9fb6b832f178147fbc48ac6213c08
171	1	72	\\x3d4ee0ac827cfb805c35b02db1a94091107fba7f1d2afd9f5d9dfd44ff580c182bf4a78c4d3cfd3ad0dc6e382f71afe8bcd202fb652f90a697c8e38d94c24e02
172	1	104	\\xd827ae75316ef2e44dadea30ea51d52a1f709bcf4d5f7c6c906549c7a811b46e91f2880dd71f11c0960324440ade3e1877e9c530d05785e5b985b26815b5b803
173	1	311	\\x0e3e19af02ec8651e68a65d6b2ed06e896ab3f7a57ef127d6361d5a99e2622c468268d0c2556cd801f95b984259b93fdcaf3b4fcf48c97829224b5b5e5c6ad0b
174	1	230	\\xf046bc7ca6a2f735e1b0651b69d2ebefab06850d1a3fa24fb33c8bcc0bf9ac7f376f87df8f02a5918ec511100e04d4ec12ce64e273fb9f82a4b2652bcbe1ea07
175	1	174	\\xe4f48737dde0a9dc5595c154fe3b7c1e38f2122684bb6dabd7fcf4ff08b36cacd8acdb0e7843e52411eb39abe0148c4d80899a67dfedd629e4eb52eace342308
176	1	132	\\x82716417755023a0fb8658e19d78a745a5279382e8d3d5d7c73b8a67b49be3e8a5bac1e9ae6bec896c66f4c13945fe22f47a8727646895a3d515852d81534706
177	1	199	\\x19928b9ee6e205a5e5ecb81a7170d3c062718c8ee6f441eb07e967f104c1dd275e0ce728c7cf79d1fa6afd0445e87bd31afb8e884e4e9be5f6c1e9fc3a7bbd0d
178	1	402	\\x194ed6da8ec1232c48c65a493829c07fe1d8997db469cdda0ece0678bd37219c96e062cc0048b97374282398524a30ab4592437ac95e312addaa74daa9d52f0a
179	1	62	\\x196a87859cb79a1d3c93729d3666a77c0aff7420e268ff28092b4ab79d85c45c16b3b4a68cec1ae6b87940967f97eebdf28d2cc4d28ccd038e698e2a70d0da04
180	1	266	\\xe6ead3c5f35217d776ef6c17926a474ee95a1fa4c0b494bf327518ed1f2fd0a7cde3f8be89da8344b3710be3d563329f64227ed1dc53833c730b4882029bab06
181	1	93	\\xcc99eb886487180163b811f1016e8e820ef1a6f3c6e1a22f05677aab21ac786da87f64d8629e4e9eba6f75a856c121a8fcf83ff74db70f39e7ed4ec407cf940d
182	1	288	\\x04d1d9e22a068ad667cf118167506e83229f9828f4c4ad8bffcbec01b181bad9d9d58c7f14ae90655e63294ccad6c129d86151ff802658ab61c384acfb506100
183	1	109	\\x7dd9ba9293df0e18c89bea8e5b88a8b87a8c06eafb85ff93c30b3c794a974fb044c98e2bb14124a690e5b0b22f31dbbe728eb7970ecf93606269fda53340660b
184	1	28	\\x0f0b4dc8b5878d0f8d342e5d9ebdc462d4763c02fc8605d6f69f129dfd16293978fd82defee559cd166852c4b2d0f8c3be553f6c90b311241a03d1a310890a0f
185	1	51	\\x1d20748b3d88504714bce11531403f289fd9aaa55c1ebbbc2e7640a63e954b6c81d4e05d8d373998039f740188de5b4e73f1f1b6f1886498ee1fcb8582294c06
186	1	421	\\xd265c19f0125100a1ea93f3040e47f09036f8f49162200eaf41995544c7b30a03c17dd03022dc7cbded0d566321b5dd0ae7db3c793f24dedd7a1adc1f29ae202
187	1	30	\\xbbae106a733d5f596f5a997cfc028337ea7a9cc4e237f6cc19d62b915f861aebb41e3c527aabadbf6e2b3fbb3ab446cff1129f05674cb28b034b4d7649a01909
188	1	112	\\x6a6667f21dc0bb131de5dfcfe0b7a7d06d6eea98c7a2e79f7a9a29df3ce306ed8449c57c14111254049922bcbb38edf91cb0894bbe6fcd9f7892e6007c37c002
189	1	64	\\xbfa8411e5f6671633644336c3e1d079af4a617aa10c8d91f7ee82dd78e07946468b4b96fc234f08949899951e066441aad284e4e572c67309a267181a711a705
190	1	275	\\xe05afa31cb2d0b297cf031fc609744b60dd9a38034223b1147aec6bd698cc3461f35d8ba2405ebddd70de5c96bd30db124ba603804ae718d0bddf621d1293c08
191	1	265	\\xa27f79578c5f117b5785da42116ed16438cad4d652d022027d1f1f3251fc54b2de8d0f0edf781f753a526a9c2aa3d21fd3774d5cbab4ff3183d5739c8e88080d
192	1	351	\\xb7565a1328562b06e6b1b772cbfdfd51986afd81ec6e7a1e76c3b78d7c39a42b1c2bd6d2e750d3f8b26320ddf8b9afecb80ab8e41da76dbdbb779cf62322080e
193	1	238	\\x6a42d1815a339b159e127374e06f43034509d50578ba2b651c4ab240e52a4f6d0526fa4f23757fbdb11f5d04b2e82ce8d8d6fbf3d81dcdda1c529652b32e770f
194	1	267	\\x46760d1271698615171e5ed1b998f3dda87ef417c916481671bc853b984252f846e27657bfedf25f8e23d1115a83ad58e7cc59617680109d9f86ce1fcb1ef805
195	1	343	\\x39a8ea25644e06aa3b746e2b48b97c402cef66ed167468c3103444e7d1b9b757d42b954525a1e2b31366d16c5d402ac43eb852e285c89966b52ff1111db2960e
196	1	69	\\xdecfd74ff01caead593a3ef6b59232374937bbc18095d3515210b796e6b2adee967f66a46bb3ee66a8e8f8f7ec20428939ffd563d37dd5edd3764774d56a3406
197	1	272	\\x2bcc40e2bcecbaffc92fd5271eb72023879c2c0f92b0c891d41c3bf3baaf5d22bd4f58311087a4d22f256f99a3a7ce920e8bca4f4c1b2f82a7f3189021bd330d
198	1	282	\\x305f0d0b072b475276cb6aea4bcb748835f0f7d270bcd6660f6ca9ffebe323852999e470a228216f7db743b7d661a043fc5b59cc032c0428c998c9739f5d860f
199	1	407	\\x02a195b3740522b6d0b27a5f3ebe617b9174954d8e0a18f03aeee52592988fbd0762bd81aac0aef5ef6b22b00f50b9d3f7f0318bd1e9928c7676c329c8775600
200	1	333	\\x0415f706523ce3e6f058d19b13cff560734a5b52cad7c2a94a4db6abcc359d23ef3afa516652f7987828147d950dbec0bc27e1e5c952f15abf09d3dc23606503
201	1	317	\\xfbc81f222620e438027b65c29c0257578e0c4c277b66ba44cfb56bbde61d3f7d2c02ab2b323f1a26286ab40045a428b5885236e5b507c6bab14917b740e42a0e
202	1	369	\\xc4e433de8a507ecdb862e8bdaa5964da20396c5717fbe05223bcd380495f17d3bcadb5de526b6e7f4e9b4f7e66e06cdf43dc42733b860715d454cf2d6d97e208
203	1	414	\\x4a98b723517f11522249d1caa820ce8e4d7829c4c603af9ee13126176f44edc699e34fb680eec2f7b14a3c7fb2ae86e21a7088dc55a8bc69786aa493139d7906
204	1	320	\\x6ab1985ce7f91efaac57b962aee162378abeeac9902368990ed1a41afb3f5025e0da250aed3613c0553d56e936ff66eed02234d19d04c859f569a03c94f7f10b
205	1	186	\\x540b7857933a581a6450fc10b4154977b1a744443f5cd5d401ef99b676fc49f7870b2ddff15e8b104fbed216fa1265828767702cf12426f6f1c866d7191c2a06
206	1	392	\\x9582cabce9e09679e052d410fd5e028f6297c2671ced0d72f5516fdb825cd2264f4935deefe6b8ba244bafde6fbea4119cab0540888fdc042c85f60b559fed03
207	1	233	\\x9f56bbf75fd4ddace9c7cb6527120dffb70d77d54e134425e89cb0e21b7d1a8cfbea860a3ecb400df391b2c99245b9fecffc7d4b4cddc36d360fc89e50985301
208	1	46	\\x17ac2bb08eaebad053121222c0885eca57f02f8b583ebf31c094689ea26817318b65380d6e88570a952c0f175fd51f6efd208ad8e652ceeec32e14948cf9af0e
209	1	273	\\x0d68e858249337c4e13681e5e5abb99e321d0632748e86f9f2884afd6203ed2c7360aec3004cc10d883218fb5d2aa5b90a4636782263166912140e4cf9219a07
210	1	356	\\xcdb90561a4cb91ad0ce3f91e04efcf1c073636619c76c8e22903dc2fb4696b3e57a0123b8e580223cf97ebd75b2949b2e50914f36a68d2a67b34f92f982c3e01
211	1	336	\\x277ca37e58ca26956f94ca80441d826a419827f514976d0ffee440b8bfd88cb0f4788f2c7b03f72c7d68cae87b87e57ec086eaf1a6844b5cb5b81a321fce5008
212	1	367	\\xb0bd843ea9182c60de74145b9b011db771e23f0312c14beb290c3e5368c76cb1b1d088c6cccb1579854b5ded94a7f634dc08baabbddbb659c5400891e428ac00
213	1	124	\\xfbdf55774c6ea870b30b38176bd41a8a16c01978ca3060b26027078c2010a4fcf713599cb7f3495e83da14af725fdda5c92afc50df39f240e2882a64394c6e00
214	1	212	\\x5480e7e72040a3ac911b0727d1d0b275b77e2923bf0c1a74256684df89e29b15f10478229701cc6679ed029f31c81ef9b9bc9fa23f45a7efe287340d18464401
215	1	377	\\x30ca73f53cd53c42794b4ca51d5dd2953caa0b3005d0a044be7aed4d48a37f2e2d2bfac61d2fc0b737013e03c7fba77c884cbc77e9895ecbd8bebc4b11040c07
216	1	326	\\xef05dc88cda8a9e5e3681eb21f1182ffc7112a93cc8b84a718fb86761aff88c17807b2b8958a16b87a1e44e9fa1b3bd7e88af7cae0bb4c308258adf2fb719a0c
217	1	65	\\xbbf54f64742a5e2074bcd743b81d9e2f9aee518bae0e65756e3b7ec3d293a09191a6f2d958a0adacec4214543ddb074ed3a99e338d7e18abce1d43e85a402508
218	1	192	\\x12072462a676eb0d2a4ec34023a3d9309278bfded23491e50376cd88ccfc66b7cc9a856c04a8bce236b6b442d642e9bc423c01f6cad51255e504382b188fd108
219	1	100	\\xd529fabe53cf14da649561527124c15b9f4eac63c2d71e9389f70ccc709d72b6d83ad06d8de2641540442cc92bb5c6bf3dbb95b7752ceafe9dbb25837c83c607
220	1	12	\\x5a9d7329dfbfb2d9f590eebadfdcc46ff4b1c3a18fc59738aab9ea80c3e88d600622ed887510a79b2f7b6cca74e90076b6eb24160e7b3d3527ea7df485096d08
221	1	259	\\xd8ad5687b2e13edfb0eac7ecbed46924b6e40486a49d8f615c502eba8d4aadbd5719b7c07082ea84660f8619613a0997b0ad400c67fe14a0b79c3a57fe3e860c
222	1	287	\\x4483fb23eb6450aa09fe08dfe4204615ec59f27ab77264f04f5cdf340c8c4a25f242fe782e231f1ef8283cd75485f6f4678003b12465e94d70ffb44a944bc30f
223	1	158	\\x9d5904ac5ce218107735c68bec261b88aa071a553c72a639c0ca0b89c681a39718c78a00aac20b1bf906a77a40936fd5c43a2dce5cd2ec36459752b82af3b102
224	1	375	\\x1c93185d539456b62df2ef8b08d9e0fb23aab1b16e880f2d86206a3ae29b1d2ae053663eced5fa75a67cce673bf5a04f81fbc4291ec3b6f5fea4cf30ee14410c
225	1	322	\\xf9eb26f3f492a7f3ea5b7efa5fd7de97842cd3a54d003c991a544ab0f81e795d12b489b08320b6ddf36e4642f1f4ba16df0f5469a220214de85a0c79ba0e8101
226	1	243	\\x0ee22485312510a08220a4a11688dbc1e7f30660fa7b65300bdc9fd4e6d10ee87b8e49661b3e2eeb21d67f7f400f8ae0c846f9abae6ccb18740d08add5ad2902
227	1	246	\\xf515592f34b6b31a431829c2ce77768de64a6b9d1c448cf994941f7224ef9ac0d0167190651ce13b80299c1250e354d3e5b89949c7325298fa9ed9ed3cca3302
228	1	378	\\x2800f73eb34fc98717afa993deb1797cc2a44f7c0c1e3031d6dcab9f8268241ebf6a4df3059d7cc52dbf3745bb27235ec31062576275918794ba4c983fdeee0f
229	1	381	\\x89bea7fa7899712cf882b12e091ecbd759a3da8dbec16c90eea7420b31b56b9d9424a69dbf25708300c82d5b7eb7fb1b10107375f0b94a69b2e5aa96d605bf04
230	1	145	\\x71c3d3c4724f372a5c782165c73b1ec2064183a1e6232dfee67da3dfa84059ff30b8028d820f6d54f22848f4e498cac4520ab0d004cc2e361a6ea393ec98490d
231	1	71	\\x26be5832ce2b2d118f00bee4546a4cc296c79af3aee34e4379115a3894b21b1ce40c1117b453ef6dc9be4f7c344b93e5baa76989da8dcc9f3b5a7127dd699308
232	1	388	\\xbfa3cd9ebc86aa3db2b28b8b3f160d479a7b4763d5adb4285a3d597407a4fc804a80a483d506f03e9cdf51ad946019e27c3a0bcb18be25f31fe6ff6cdd71e005
233	1	111	\\x3effc64b68bf4b0e3fe827871a965701fba26d22374db045956d580e9fd17f4e1c522bcca995fda7d19998c05247090fe81296c5080bf628cac3591547cf6809
234	1	344	\\xaed6fc94af52866612209eef2ef35628bb6f9a89669558eb991ea04f99c03dbc4e254a3770220f3fcb29a8f89185313a2a783218a3413c53f0fb38cf6f170c04
235	1	147	\\x08ca8c4c396f5e90c8fdfee06ef95f8271bb55cc2be51dcd6ec688eab740ee94d6b3ca1c525ddf2188545143fbde8bf94edbb5aad4aa67d3c60bf5078b9a3c0d
236	1	168	\\xae971ec0107d5b015b06d018bae4dba6dbcd91759ff2a8f4cd5907e2fe417ed59e4eeaee13b73a9270722e9796baeabbba05e566e2bbb331ef03f3045d59ed03
237	1	226	\\xb93d65e43ab2a730fdbb006d43b50fc63f109dbfb726d8962d30411f64d1317b0dfa0042cbb71ba244673ad790ff07a7a00c09e5fed876376c854c32f5083d0f
238	1	193	\\xc5e8caac48e53e2a73519c639b9c68b9c806c822f1d4aaa0b6915ed5b2eeb501a270b847a0a2178d12a0c00db8a3365db80683d18ca5347141afc654d29a6d01
239	1	376	\\x0467dc373769eb82983b89dc855991c60aec389da6b38c247bf64bdaf254e54e2d4ff969412b727629f16558090878ccef651bb7467d818f02009fd3b257c600
240	1	404	\\x73a66e5b3caa8358ac1d9cfbe2785e18a537a8e7439c4b4b4022098aaf3dc9cb21af62e33c670c500b8aa276b91b16d1041856f46d62d0a0ce17b7139855bb05
241	1	18	\\xc41d09ca5f7195f09f42ef5b0e8b0634679d011799c54df5bd642729e3f2af8a4b0a3dd15d767bd1f5eb4403c150c95ae4d3701f420b850f2cee77ad9469790b
242	1	91	\\xc695717d15dd8f2186d403a42790a8204330cf997f414164d91a554456b60bb09aacdbf165e13543838ad5d5a1e6948440ced96b0aad97156838044d53a6df0d
243	1	94	\\xca36a35ada97b119b7877a07eff74dae7ad94eb89e9574d86ade8eb837994f0c4e5fe096c1be19da1746c4e81f498bc11f8ad3013318793c1553b737620e5f00
244	1	401	\\x285b1c292d9318638384aaefbe925312abcce398fa9beef3faae5014f3bcf4f43221a3af69f82347bcfdc55d67f00c475535728aac092653f6c22490de9e480b
245	1	92	\\x7cfe306099952361878233f0773935b288c15f9a03893828be28cb8f2f93f2dd33fa15223b68482b3fea6fcf40f49a97d5e9c51e63a5f71f9d7f780e55fe1c0c
246	1	108	\\x5d6cb52b38908cc1666b3b79dc49af655cd1946f42965b16c3e60354ba6c934d24752e803610c5df078840f9164e2a8273ef1591d7fa97bd6ce408a5da4fc808
247	1	394	\\xeae0b4c686e005678aa00e37890de8a7d52d40013aa84b444afbbdec77850fedcb9ba33534275c51e59fa028087e2dcfdb9960319425396593d26a3a395cca0d
248	1	143	\\xa9483963cccc1c5eb902164d56d51878822aa3754730cf472f552ed7a9bb9d7ad98b928c6a3be0f9143fc37d86a9d7a5b3f85c0602ca0f4a02fdb0440824840d
249	1	55	\\xd87941f3feae46246503b20a4e85b37bb8af5b493e4863cd13848d4f64ee7d8ff1835cf89d4406e8d5ffca497067c67eb027aad6b201606b93cca8fad9628508
250	1	207	\\x528489ae0eadb2c1054bf51a8dd07d907c098f62cc3b2ee9d28be329595c3b4234997a8ca0d1fdd6d359b855aab215459b739da43a5a419b376926be4c2e2009
251	1	391	\\x01004df8322a1ae41fd40ca317488c024a9fd491ce5798cb19b9ad7f015ca266483dc9f4155e94ee245d76573eb7adc2244ea3f144111f5467378017831b150f
252	1	361	\\x6a55fbe7e5616495728942077f256002eec52cc524a4d58df290f2d9f2d40a9ab0c96c91f54d383bd424cf5856733a3edc14f0de302856d490a73c6a98634304
253	1	312	\\xcbe7cf73e129e7c2fcfa1c33ab4c83f0d6c5f2836be5e842150603aeee902cd10a32a32a6697f77395c7832b54d35da35b067669caea77c0e0eadf979ee62907
254	1	274	\\x10b99e849f40e3e31c5dd2cdb1795e2819ad754a0a6bc6c531624b154a9f48c3b1267064681249ad910c93fff82da7798cae736422bfeadfde516561b88e3a04
255	1	416	\\x876b30279032160b29a460eed20b8d45c5a0b649b4f55dbddd1ebdf020e5d87483471fe33d7a8573af138dd3591334c80215555f4944d5be44ad05c3799cff0f
256	1	384	\\x84bde94e2f074394a886b0f57f4a64e014d80fb68bc8da90379f3f83691b1efaa86837ca2bfcd57d2bdacdc6c1b20dbac3a071057e59e0acc6a8bd8893781007
257	1	9	\\x0e881cb20fc81b6e549271a8787136bcd0504a3fa571a3af6eff938b15756ee7afca71be2468657c238aa96df0c015e8ec9b93a10e32977f5627fd9cda042000
258	1	301	\\x099a1ed6e215b095fe4ec8ba72f4257ae61c02b7b0ad709239e44ab5f40cb9077be5010c7893f33568c333f954d3569b92d7caf0f101e0d9395348947f1f3408
259	1	283	\\xbcce9c1b158e8baa7fd1b769350eb2623426ff6b89e0cd4f2886448dab24e6a3450ffae01a68d4a1d8177ffcc8be294afc6aeac6cc4b2306b61cb4e6d982520a
260	1	118	\\x6a35eb2e993c6a6d43e5a1cb587f231fbc794012a119366177643b2d1ac5d22853e892b8f75d9f47c6c25de2b182f465b1b99193bdfa52b00ea7e0bb038d100c
261	1	338	\\x0abda3341094efecef5b9ece8f1a4ee2c0d0c6a577fe940f0a1058127ee286115e11d83784f5575bafa38fb8f42f319ccaca06251387a4cb3999ca713b774a07
262	1	242	\\xe146db68808771e852860c1730c09007486205139059d88ac7ac55c64ea8634c936a5cd70ab4500fbe54f62489a64e8b9b5893ef829661a0e763fb25de72e707
263	1	256	\\xa05ce7163c05efe42f584cf99c5f371977d58215f2debf91610fb3a0191b5fbfe3314b885e2ab8cdd67bd4fa130f6daede302564b452a916746a60571aac020e
264	1	39	\\xe2b1d9b6d2e06a24d086330092fe16006bf5389ce5e19cf72d358b4f7fca20e2a49eb54c8a554180e13e8b1cb4027eec35dbc22ce34ed3d77272a848d7434a0b
265	1	383	\\x727419377145042dadb7f9db6fcdb31c5661b83f8bc09c310c77be12f568f0a390c63315efcf7bc401f2218c1a0c51d14c4ed49daba2eb8f23722559a95f8c02
266	1	1	\\x3f5c18205f308f7b00b877d6e0920ad4fb0f78ca5fff12274e49bce4b7e5124690168282d68843cc28cc1a004f8e3d37b43743be9e57eba4d6a4129cd484de06
267	1	50	\\x792211e5a1107cc7ddfbe7b521155d5cb32867de699d4539201aa7b15e4e83443d190d0eacaa3f01eb621af1fae990db386ac689f7937826cd8918c98e637009
268	1	347	\\x8229a3fa1c1ef9dc4c6fd7ccd5e9c135a5ec5b88302e48c72be279b1354a98a852f9db1e339c025eeb2631a9ab2c91115b5ef83436516d8ddb2df2989b0a020e
269	1	73	\\xcd3a13718f390d62e697dcd63d40a58da75062689092ac7105ab564537889350fbe4e31ce6cb92641021cb2f0d7f1d0cce85fe3985ff32041eb7a3d53b5ebe0f
270	1	189	\\xcae82c11e720c5183b436232c006871a8c119e48a92bf34f135770fdef5531dc704fa3e01fe0bf6a4c5acbfa373c058bd743d8fac0be97d71d01e787f369dd0e
271	1	418	\\xd792afd515b9a4fd058b747ea325f30d80eba6236c6415e4fc6d880020ed6204b6961a0414ced015ffa8dfa4705b566f36476d0cad2cc0fa5e2227b09027d101
272	1	60	\\xd3ae051c19969d41a959db3d5b54b2eee098bce0baef0c6a0521bf6cfe053907b39b29375e267e8475a1cc615de82199ce2041fd27ae362fbed2e90188f93a05
273	1	241	\\xd4b67b07a9aa6adf8d420bf0f58bd125ac6423b96e59d754e48912be3f17c64760c3d11c6e70a9ba89b073aa8db331dcfc4d0244bb471cec45974c59a1825f01
274	1	303	\\x7dc57ddc06c7cf73e9dab639458e0acec0805d1b83f91bd7919fedf491161a4c47b65e5b20c96bc1854c2fa5ad1a37d68cd471c88b32d69a19095574ce096f0b
275	1	127	\\x097155ef693033eac864fe33d68a6bb5cdcf02ac606e8b81dafd8e2467ca3a92166d4e8de7beceb03d2d77aaaaec9a1f9eb1604d08cc5acf680999a707edfa0d
276	1	165	\\xd152f5c0a3d0d28e3df561b9866848dd506245ed70b462021ef4a2b915d7f2da21b03894b235680721521f547966b5a58997faba35a89974989fc1697dc1fd00
277	1	254	\\xe74a88a60c5a639b862956a485c5aa203872627138f34e95bf4aa7ed0ca489191290775809e853120cfe20928e4bbb39c0b50b22808a498031d6685fca0d3708
278	1	188	\\x756efa53c2ac07781c487690a2c35da425b845e44dabde253e5df281b966dedcb6aed9be79169153cf5a0c5d3861bfa1b8b972e320bb110e2def2b1b5c94bd00
279	1	36	\\x34f0bfa73be6e7af4b82fab52136fd1eb98aa883f1e53ac10e7262f35671a0c6eb1abf667fc1852a1f6eae9c5d11a099a278638ceb6b334a6f14d21a55f74d05
280	1	325	\\x3d793e9119f4cba85e2d6a5a64ef304105c702ac46d15d9de9b981fbf8ae17a588fe4a213f5b2870f2b4dc7dfc41d8e81b6920bb02eb1d7cf40814de26852105
281	1	2	\\x8839fa5b128c17023fa3feaa60d60fea0196b97c7c8e50fca4d132dcfe7104026d58a24d538ffaae867942c0e3689caa6d9253b09ee6a8ff738874f30c3b8f0e
282	1	141	\\xee0c7999133df00e766ee17cfa7d125c90dfc442bbe7db8ad497b5b38cd0644ab14492bf71cf4509f124af5e5e902a90c560117bd4520a301876beb67444b501
283	1	237	\\x3d0cd128eaac6daf4f67c82caf96f3676d534e6b0aa1db2b6e373809fade86aa565cb58afd5d2602cbcbab62f9e4327bc50c4d6b05f54ed36631ffbbf52c7600
284	1	315	\\x62e7d3d10cbd51713a2c3724b5ef8b2effd96f36c4bbf5485734b11630bfd77e4343da94006fba785125891cfdd0471ad17c696dc58f6f478e998a76bf29f909
285	1	345	\\xb20df19ba45be73d6b63f32521449d1f3959f8981ab6c4662b0e9a39c8d8be075030e436bf9d099d6d63f504fb8bbfa921bc5beb8f7105874f9ee26bb60aaa08
286	1	330	\\x25be0a1b2db06bad3bf2f019e04e6331d38f8a399a81a708e70d80390ea3e45cee516810164c04cba1718c100735f05384ed8dbd617cb4812a2626abe67f2107
287	1	85	\\xdd8bae45cb1ef8a34b1c12a1ed12c8fdbf1b0b2edfad5e0a1b89119f699caa631208958823126db733de7160e3078ab30e2c24a33194537c6a0f7c6a239d450d
288	1	373	\\x0adedb9ca7e36b453d6a109885e9999e21a3bacdb9655bfd47453590c4209a5fe7f8f5b36f89a90646a4dc7802847b543834fd7a1517444bac99e685468a6d04
289	1	142	\\xf0c2427ef75927401cd3425a21a332a7b42ed68c6ef6ed7cf3f4a71dc2f7fbbca29a96d066662b66464442a2b811a101363b2c9f38a78149b2e24bbed63f0d06
290	1	162	\\xdc9fb850a137da530cd74751cf2868bbedaed64fcc4f6973c64335096cb0b7635d28282d9784a317b3cb840ed748b7d9b16f4b83d94402169694a8c71243d40a
291	1	297	\\x853eae3816562a7593467c01851cd1279f18448deae112843df2826702212fe129f2421bd1ba1ba797d90ebc07d75b3c8c11f0a61f80fb01903e54e9dc7b9300
292	1	321	\\x1bcd3724a8eac9f395f692c0488b68b39da988182be312a26bd09851e6b99685606cfbfd4ceae0de22fa6b2fdd349cad107b603e7ceec13ef8fca19990b91905
293	1	105	\\x7778434b982546ecc7345458112f914120dde39d0efcbe06778835dcd1ece86542c7bd54a5ac7ccf5782b47b8692369e2418a46d380996e39e63b34c63a2ae0a
294	1	257	\\xb70a74a947c1722f47a6d5b65b9dfa1a06063c188ea6fa45ecd5773300a6ee015958c035b379539cfeba179299cc770cf3307bcb5591b43730c6a4797991a607
295	1	27	\\x78cf4da07339c3badbc32575f433b0fad71f55e1c1063e706b152c4a724bde541f7b4abeb6c177d252f6fdedaebbbca12896a9637cf9b1479797d45a041f2d07
296	1	214	\\xec548853a172d389230c1042b3975368f5a434bc2700ec6b7613d13450b61b1e0d6e5845098632cd76ca6052b47d125981cb2ae6861f16ba141ae89b4bc8070d
297	1	350	\\x760053901d290075aaa23f90c73d14b40319da51f6cb02d3196112915c23e6183b5833bd5959067d2a245777e5d3ecd3c07e96b1b5e595db74284213febb8d0a
298	1	372	\\xf5e489fd301581e2149f4154c584925f12051a14bcebce596c4bb9814f7116c04fb61e8ef83ba54013965970460f66e0081943244f4f6963c59b25d299f67d0c
299	1	75	\\x9b0698edc0e9d6a967a609db25ff4e0fd0642ffa2f969cf3ce149e6e123c5e6d2e81e100016cee54deaff6e3a768b36f995cb484fd6f969b4bf1af159192ff0b
300	1	201	\\x8d8cc027de9d6b90865045ba09a0cec5777b81f897a0381263201b8dbdab65872dffd0522a1310cd9db494ba2795ce936f5b780f99869d30b1b3853ed8fee10f
301	1	68	\\x0b5ed1077c09c8fbd5d682955edbe250d68b3e2f1852d0c712881732737919670165239852306c4a2c0701d0fc9865c4242816ecb9dd72c52c688f5d1269ed08
302	1	354	\\xc3fca7a38a0997a32c0aabb7b1483e431f72a07c9783a08799577c1469fe13d448ceeec0ebfe56c1f3ed513c4079f696c6ed2bf2208e0e30c64c866aebea4b0c
303	1	26	\\x90279d6bfb649c0401603d4bc743dfa768207760a81301eae6f72050d9298633b74f8fbb16e2708765e50c9e121d6e731a9887a3ab0a72e10153b2e0dfb4bb06
304	1	335	\\xfbcb785cbad3f00408ed11410be4c12f73690e00eb54ad3181228c8be415cd67eda90722d6c0a939a89dd7fb8e7a95d0e8b08af5d1725f2aa22211f343454504
305	1	290	\\xa91074b8bf0cf0cc9bc9316904b867d0c887da4572eb8a0684160901e840b909b3da2c420e7aec8977943a74872e4843a14e56ac9cc0cc187c3631117aa4f505
306	1	410	\\x8bf6b9b8ddf476657f037f647e423b1850b388af550fa0e42539449e145c39264356cc8965f7fdee9bda929bcdadcbcea162d4248fe83f8ff6ad106cd7d6480e
307	1	313	\\x798bbac7d6975d14b1891fd2b96782192ebefcbdc08f6a698d90e18a7aed54cedd00434972fd50fb85dbeaec2809f23b2dd7bf1473d20143fa19e9124341680e
308	1	389	\\x45df91ad75ae1b13c34c592150dde5d336803144ada5a8046b25fa691f10a801b79b18aa48ad7b2c449b5b4e82293d7bb913268ac765926e2341e5cdd329f209
309	1	323	\\x43e002e8d19b0a86421d86c2b8bd4d234bb2895a8f5bdeeed8b517b40179ba97c2ef24670e53a53be33098ced5fc0b46f79342b62520c54bd472cb6ed8f37e0f
310	1	44	\\xd06d205bbe11a8bcea027f18677b707524e0d16c8138f02cf0b6712525dd56218c38d78508e10a1c5c34dbada42957f76d3a4b487d43b216e6ddceabfc98db0b
311	1	210	\\x52d860e24496938c6c032f3efd582b70ea779eb905f6a77e82662095ee78ed8a06cbbdeb2455b1a284212795a9489642502754c297849c3b53f6c799d4caaa0d
312	1	153	\\xa0c138245bfa88c34334bee4d972d1ffc10bb6b5d9c668a348b6b696eb0d13677ffa1f080c4b186fe10bdb2aa38d4c582ce88c3c76c5851aa2a83719a5e4c80b
313	1	133	\\x6b8f8ecee21339e5ad25247a1ef9947a71934a38c0d226e69c483cc43b5d7fc5f11f9fea39a086749b1484e85c1f2fcefbbde2b57312c405fce01eb154628f07
314	1	106	\\x14c554841cd0c36d9e3e2c62f35d2924e588293a70757ec560751f7b83c64eea684f13f4e54dfb1d82a306f81c1aa72df175eff8527cc9e892580d3b0c4c890d
315	1	261	\\x84d9137cbb0a38d76a3b20ca9673596b6f17239924dacbe0987514c64fb2b21d0f0fa7b61fd5ff07f9a6a67c30361bbfbb7932b923bf3bf91f71905833458609
316	1	34	\\x08eeb0b6cb89b9dfac4b305451890307372e18f7b706fcd7ac5136729092945286dda886cfc45f3e0d86b52c71d06e228aeb8f44752c37b9805fe49160c89d08
317	1	328	\\x49277e12b0c968c05c17cf717cb005cbdf9d1c50bf198ae5598805b96a9a8b1e793a799af93a03cb4c3d294d39cee9dd8b9e9869e134b62d81bb877d334fb304
318	1	211	\\xbfb681817f9e2014db5b23ca61fb69aa634b0f65fc734618c359eb464ebabdb6907e2d71e651e199e8641b782a9e099cd5e25604e0f5679e6585360d3ab6b001
319	1	77	\\xfe43e99a1d83098e740fb99d4a0105fff155c00ee68546a2ff78c0230433c60671c95f416f37e133eaf59a71b004206dc69682d5c7907798d57320b041a3c80d
320	1	412	\\x9a36b752bad7f39ddc855282080ba61a9c1a92a9026c22af39484ec5c3d477fc6916c49a92f7cab14e2bbe63714830ad7d85cb957bd97046278eec4be9c97901
321	1	307	\\xae34b47703ce3ca807830b82725128612a5b090b288d75e1aa6ccad6886783b30bac261301682006f8a99e59d9d579fc35dbf62b53b911c7a302b5ed1113fc00
322	1	187	\\xf00f49fed6fda79da30be4bcf4698ef1634c5bf088ee05bd8f5ce167d04042bc716c1fa6fd5bb39de132a7aa9e71359a7682f4f6a9baddd7fa6a2ad4b2a13000
323	1	422	\\xf30036ff32b0d9dd163d3500362175951801bbcd62832d54332ee9382fbf9a59112839c009d21d017e4f343d82ed80046109c61cecd99496a994e437d0803a07
324	1	255	\\x5ce60615f78ae4b9e4a294d216e3c56339a837498466b3f49e018fcba04760e1864970442fbce15a95d13741d5f6231e710160e5742ea65edeea86284d6c190f
325	1	417	\\x792892ba802f2684dc9009703956d3508af0ad8f5b70cf80a96764b2b00a9c3ffdf2d4c31b586655639551923caa39454e6942847d1ce5a95516657debd9e403
326	1	8	\\xe14a58e2b507dc2b2f7d49476898da22ed8d3d22fc393e90274269dab3ce6052a38e55eb9019c24fa6510d56ab5c22e7e663476d32744136269399fce7292105
327	1	370	\\x75211a612811d0fc3ac7ce88745e0c6fc2f2652ccd1e8996cfda8de716b6fc654c640d0ab267f70c001278acf214a01992aed7f59e3349bb8434fc7da840a109
328	1	63	\\xea91966b20925393be3766b2ce70d34bef6353b3cc08ae54c9a9df1d4d5ac8a9456aaa970f73bf7f32cfde86e66bffeda5bba78bae63712b0f75974b8e569200
329	1	194	\\xa3fc13c79bf2cfb2028456666fbc7d2e41030ee4b266d24ab9bb7ba4e7a56d25045695c0dd98c8855d53100c0ff9a64e0a3b5c55ccab56d351242415b8530107
330	1	6	\\x84ed6299ee4827f749c5cf0705619bd8a634ad3dddc181389ca57a6f3b8850a0ffd3ad5ea6deacb9d9f01c90ffd2be237e81b9a3449e107d69a4fa9b04034e04
331	1	125	\\xbc1bf4c23e94214cb6cf9e25246a79b4aa0076758fcd1c87625f52dc4e6999800be3187d1d245513f0934411c83e9b193bf325db3e8a5a1fd4aa8bea84553806
332	1	87	\\x75db2b0ad46e01ea81d963ad63dba6152b1a93a8579d5477720a3b083931e4a02ca61d65ce3c4b82019a12e0003a71cb6413dc0b0f86e205a0518bec899ec108
333	1	379	\\x4b8d3d2c50d1a561a10a3593d522287ca0e72e16f90e61e64205d731c7fb7845fbd24547a9bdf87cf3133a1807186f2aad7271ea833e035dbab2eec4da74140c
334	1	308	\\x8f70e49859fd8a516f4b388e621eda12384cd494a77108aff447aad08aa213359febd2d309ac648a2ac41876e1f6d23a818b195a1179a781d1901ec5d40a6001
335	1	424	\\x54a056307d28b998a0ed3340f5092027c001c31a79117b8613ff89e3656a55c9d084012558b10f596b973d81879a87c2c4c93b90a1b96d65736ed4f6de323202
336	1	382	\\xcba8ac160f695fedd8736fded816de642abccff4f5427f78f5111a04e1db631f6efddca4a85819ff4b6ea0bfa853a44921cb6c3a568051f971556bb36d9c440d
337	1	117	\\xbb70d4c97499794ecc251b4fd59159e0f0357c02d2169ecfbf4facff9b998ce98c7ba3b0e658938cf13d82b0c292576361dfa4360ab4601dcaa1448c728db50f
338	1	181	\\xb8934b96c3442c9b9c64a2bb04fbd285bdfb86f28b88562b5beb685bc55450064328d35111b4cb3606c8e61c7e419e3bcfeadf178c793295c9b94960dceaae09
339	1	319	\\x44f9f9c68e893d4934436d6372e18a3a7b3672edc9ad93db1f340423bf8892493697ece71e5c2881cc2babf6a4ba7366553668310b44742129cf6aba3c9b320e
340	1	227	\\xecee394ab88e496287f6b293fde9eed964a7251f5324043b91af6ff7a152e0c971bccc60b3deba3c06f9993541e01ded2fe06b027b347543daaf538253f66800
341	1	218	\\xae0bcbf1b126a760465bf112ce7bd73274366a7da7b64d3e0d7bc8587989b5f8ed6ecabac15f0a8460fae9b09173d811249f81c37c96ffe99dbb39bcc470e103
342	1	334	\\xa9ff39bc95e6eeef6153060441101ea113bdd87fdd1a54f5f9cb2f195243743e42f25edf7f6d89c308f40b281659e7549f692916e95016d2f5f30fedd5afb604
343	1	408	\\x99493bdaa59d918abe36b20052bcbd14875a8a09a96939717f201d695648148e243984cd31127acd330fd46b4eca6ae36c2d6b676d5ea810aec77c7e73864c04
344	1	271	\\xa14d7addf3909aa8a34f967809945000ecd7860a49d5708e4b154cf39305e1e8bbf583f326827078203ed7f9471b0f8a380040f2d0529fecbaef6cd45a8fb205
345	1	35	\\x9f9f3992b48d9d835075a7d54a6289119b4ffb0c37560111eaefe19854af2f44c6e7cb6cb661332470da9caab056cc417503b674c743181afe99851f2f7f7102
346	1	42	\\x4e12febc103afc2c2c9f380453e1630cc2d975d36099a5e19b9efee496104f6241e43ca484fc7bfe54b1b9cd951265515a7387a5b683c4fb74e594ad2e254a08
347	1	341	\\x71c75dc50e4f865fb6374234ddc49b577892ba546193050f24fe7507e405b2a5e98f0a0d2e78def0af9054b81d25059819f3b7ecc81a8755f3d536181f5b7503
348	1	304	\\x3cd653ea9b6575eb3e288b87715c049026c2f863a6d3015a23af14213d5ac7f80b909ba03d0525fd0516e57bf0fcf6d878df6036128e6ac6801ba595ad61cf08
349	1	191	\\x65a31048110b8a2022500468d15ee2e3a1896ca388c6cf9feebc55eb7f4153ecda305a82e47ae0d450cfbd2620b0409ad981f0a8948e7a09964272ae94c99107
350	1	406	\\x25d463163900982cbbefeea1f162637df406fe556f9687a6f0c1a2dad68b4756f81ee12c3f46ce0eb9f781ac0658905469ff276af9b27b4577854bb5f9239f0a
351	1	396	\\xe43492200de7c6a1158332a38d4832bdf19796513a89523983026a1c928b34219ab9d7b2f0e9eef59f6e10b2b8608b62a474b8e34a706216434a46ee3b040e0b
352	1	183	\\xac151a1f17e0bd37061ca2405b86dbb28636d15f28cb5abdac549f92ad5835f9a63ae68e54aa3878f1ccf56e8e4a7176f24fac84d5b9fca3358b635572b4b201
353	1	182	\\xa3dd60939b5e5e74706c1a8035ddf2b3e6862dbb8aad794bc9203b2406bee198fb4e90699ad6a2769ea2fcc7121386e8ff391cfd6a848a546f8bc71c9e932100
354	1	82	\\x922a445393c815d5f51daf23f970720a191baa717ebb8c10891631fd9c0c9ec95a1922b714f01055171aec9a85b14a7d08a346c4a9e6ced27d77f917fc7cc804
355	1	221	\\xd28effdfefcdfb1290dabaa268af4258d1c419f7c56736a5870a4e2fe3e3b71aac205c1aa76558a5617b4951d6767de26e1bfa266456a54839a2c856535b5f0f
356	1	219	\\x593011412b5b9f46d519ceff14900678989f8c1c01b3dc5d50a8cb0b1e454b6b25934423d708b7cf0f619957138c8e40417c6b03be1796a431e66ea29a97d400
357	1	3	\\x7bf32e22d110da1d7cd2ac77798d2cfc005bd3a53c8ac8376c147f3ad5a095a1c68a30dcf5fcd57354aa0c132aab15579a935ab252efbeb3495ec6ad73fdfb07
358	1	215	\\x39345b1c7b0542223ccde877c7874ed5feba02a5b596142c753878bf32b7800d4a232a8faa20c50a81209e3e47736af932a216014d611db2ae1de1258f560a06
359	1	56	\\x334c5f0a37733da2488273b05747396615adec3225cb80968f577fd8961814654514408249297138e283157457429a8b417038b68b2f086d7079561a04960b04
360	1	359	\\xa283dcb7bfac3644805961812769173ecc3d9aae7844c02f4d516016ce0395f7b5568e2744ef777baec9336dc017e28c4015c339a56394f26d8f442fa9e99e00
361	1	252	\\x0f9adbd9aae500a0ff8ed1d4efcba6e18b325b87ef0fc9b6a57d2aebf9b47f0f09f59ba7f022cc2de20a6f1cf51a04a1299c56600e83cdd6868abbcf891acf06
362	1	300	\\x4659cfa80a0a62e5c58fc62ff01101ff2985f45adaea036d2366556fac84fe5439b9e1124e3c83430484d075159074bac3a39b4633d7ccb3764fa16f29df2b07
363	1	358	\\x08b391fcf24b1337dd47b372c145b041327ee40da06442ac0037a69e0d959cf0c18ce05836dcbe8d05202de8a5784d7413ad3f2c53e28ef178c87fab38a5610e
364	1	409	\\x2e9ece322980a23f01121a3e7d031df81f57639c7cd91bc2ed1db2bb151a492279147f881adb8f82c982d1734341d1ab67aa29d91c54f02ae66c802382ae5109
365	1	202	\\xc3f8fc853e1ff84315b2393dc491c46c686c41eb348bd81498835bacb6cd5f6c96473798a5b6cb8b26d292e3f812b23f311b320bb82bf3e449c787bc77af520f
366	1	348	\\x9ca1829f5d24fa205daa14a73c10190655c3a5db150773cdfa06aa717bfb3d1c40b5e9eba3a08b9b4e3680440c1f1eb227479c350e65e0ab145b168ab73afb04
367	1	180	\\x2ed20cb8380b9cd49af3bc6854b6d4410879a356b447bb0595f894fcb3f3d4c028604c7b0195077d46f9ff7dcb0b26e69dafb80f58c190c41598d0991c74db0e
368	1	21	\\x8dc8243ee995c0af92ca4c38579e7bc9ca5eaa5525300bd029e6aa774bd6f2e62c17a534d92ffd02e03520f7c74ff57178b6e07f64157dbce10f1eaf1e505302
369	1	222	\\x20f2365bd2136d1712aef7e726c0a080e9bc96528e88a2508ce19f08fae2ec78a33a143e6963ef3241764de77c6c184c40b2d3742b8ca59daf04030b9e9cd606
370	1	332	\\x8ac3e2ea66b483901404c1be554661ad6f0be79766097c9a58273a15024d3618bf7336f9fdd282c835b28466e3d5f3018d6c025a5cea3827666a995147cc5208
371	1	79	\\xd82c89f9af962e9c29b7f52ef861dfcb1413c46d970a75087b698d5663ebc3344beb0a652b2c421978d05959c2095d4dadf71b93bd904c0e2b12339409c58507
372	1	88	\\xbd5916b9f43946f387ffc9bb4bfd8ddfbedfefe15545db6f98eeb29706ba99935a8a8c6c708593ee143c404d2679f80a04509e82fbf2d2cea0abdb5b30085609
373	1	7	\\xdc23355ca42eb90bc74591613262f15cf58f45219c1e556379593756769bd43ad78540546f570ef94f12b6b77986f72bb378288909d5ac4caf97bc9802420904
374	1	405	\\xbdd0fb261a434dcddcb967851079787c1f15b05893ed9f2e31c564788953492bfaa678b8fa38f247c4653f4ff6e1d195d7d2b802179621d4ee08eca8a144960a
375	1	386	\\xc3f8b9910444cc8d6f3225d68c33db069934bed04588c9f857186418efe50352d54207eefc3edc8f20c11c8ab2378d2da8e14e7d5bf3c8da73589f1414096809
376	1	99	\\x2048ba15a918b434ab407c7f5ba690cdccc5a550c68e4caccf650f2454e7f405a7d043a7c8c1d9f42586058ba4424f63423ba63b5aab478fcac459ff0a335c04
377	1	59	\\x872a91865bd0ee7cdcbffe9e912901cbeebb0712c9a7cb78b8f0b8ac4dd896939413e365f9f47a2fc28d7b576f18bafb508e8511ee35713497ea1bbc28d38f07
378	1	411	\\xf69b775d3079aaba6a2310365a0383a131747133bda395ca071922547f8efff8fd8a6491d970bd99b4653cfb3bf422e755a024abdf93e305d5afe252b3af3904
379	1	78	\\x9714f3ed8aa3a5c0e4dce4b2f3f39919f0e1f45908eadc0a3ed582404e0473d49380ea8c59e17d12771d82c83f6c3b26d5c12b7b5dec82a7ef9eae75d6a2760b
380	1	309	\\xe3cc41e11e71910c671d8ca4eff9ded5e522e7e6fdb76021536de1b1b25535d1cdb980fd980327bc69b2dc600199177ffdc821e62c6d3c8a381eb05798773d03
381	1	260	\\xf18f6b12dca5f39a0e9cdaa6375f4402822c239a31d70bfb85ed265efcd209fe49c592eaf8b179e16f61b853653df1026145e7c16062083b6be75f63a76c750b
382	1	291	\\xb2994a9bd16f25af89fa454768af6e4f5489a28a62fda75d4d8d9989a8607a88fbdeee33c87fce28464a7a59a4defae2958723d2b03178dc97182aac54399700
383	1	107	\\xdbe7496d9dc1032d296230ad3aaa69f3e490c9cea69527edaf3c38559566c05adffb92723f1b2640e07d93ad613071f21883365aa2d30855640881f6f88b8a02
384	1	216	\\xd36e4a5eb2dbef27027468845917be310189b07e5f6fcbc0a4e087d8a3585978dbc500662f4904cfe152ff0c162e3d08e7a70bc0b8fa0d81afd09ccbf06c4e04
385	1	43	\\x60b55e1780ded89a366c52ca58aa54adb644faf0178663c045b52000cec083fec94ccc20ec06299b4826b82ab79001cb7b5f391ef3c12266bbb9e33540650d01
386	1	316	\\xc20f4c4d52173cbf700c843ec3e27f64987e0cda287b566585eebb22908f4d1321d33ed9fb05f227af2293e2faeaf14a5594a247718632e4957c84a90a091c0f
387	1	223	\\x98bb9f57155280cc46d61554c7645330a33c844a6741e35d75d9840cb0c354c8b3c044302c5c1c1c784c936853f9e638d433ba5edb2dcabf3859a603c22b0c08
388	1	387	\\x1f9cd388884e23c2c1e030cae221c3a3819bbac50f988a57dfc96f856fe7f0b5af3f4c42660c88561ee3351190c9330c77ebb8dc77af0c5dfa77551d9cdd8209
389	1	58	\\xd47ddb8cb0ae4903e0a2f4b2132240600f303af3830e5dafc9d678817caa045608a7ea482b69505419c89724b545ad25c582d19934de8d4c630650a67de9df09
390	1	289	\\x5e854160ef2c19eef036de7c75acd80d75fbdf5e4ee51c58e1f315f259ae0f9b03bb392700db24a29baad41f19a89d9b115bcc359b91352dc764f1b5ccd4e008
391	1	49	\\x659e2e78710fe26c028e3f8df6ca8ee73e2393838cf1abb7f9c4eb8737549b7806f716af74b93154635875f262e2fc959a3dfb99cdb1fcdc1f5c6289cd8a2603
392	1	15	\\xee6fd7770a17a9f7cea153557839aed9d0cf97844570ad003e2a32112c4d893c3bd13be9fc0f5bce09450c83086305eebf58b800726b640448634d5c2839f00d
393	1	119	\\x03c14f4e907d150a7329761da3c181ca1acf8aaa8043a97e3c6e12e590137cb29af811124353c8c2fd9cf79067f6549833c4f0f46c25111169412616b439c404
394	1	120	\\x53258acd2c1fadbd7a40c83de108bce5ec5488fd7927146a44ff13ad007ec350f569f7d6928b17436658cdf54ebcc6a9864c77c27afd1cfa4816f44992557e06
395	1	397	\\xc325d5e31d2c02386c398dc84929b89b6f3fcdaffa468c5c8cff48e6b42a1249baa7097e142ef010d836a2c24e158a3e5e803eb5ef57392a7723ade051810902
396	1	20	\\x3b100474903711f1e7ecd8d46848b698f2f2fe67c6ff653e3d63314b5c2c683f7b69ad1dfbbb27aae1253f2b19bb0dee0ec97951c17c5aac0c97fee775d8de0f
397	1	169	\\x196596a4cccba5337f9410e0b9c8409b5b4fd3dde645c7fa7fe5d89f735843d211db907de9eecdd77325d063bff0e024a76bef3bf1aaa52b11549a4b968eb10a
398	1	83	\\x515da605baa3c569076fdaf89c9bcf1d37869b7085c7e065723d7cec997f8e5534a541a82ff3adbf451d6b2dc3c90ea1706058dd6064b236f6b0f9233a702f08
399	1	146	\\x5398b2988ace36a540fb9b54cf8b0686e15fe21357a75a5175106664f53d7a1a34e9f602855459219820d92f82f9e26b694714004cb4e2d9ed7fd94188e3b809
400	1	4	\\x7967a96d51b64974a1f186a8d681d7165baae4bf98de8fec329d50d514c4dc40527c1e6a8191d9c5dc466e548c50b5012fcee2380845258e27595df2b213e806
401	1	385	\\xb054314bb68902b0ff49c1c24c116be177a6481a039ee3ba53c245f008c81d84e3136fdd9963b804f82434db2cee049c32e5d566307c64ea00968a149de4d90a
402	1	31	\\x3f090ddd00da4f09373091382980b7cf3475df51b98054bc0af8b70ffe15f30aa4ba43a803d8d6a94591c78a781fa5912191647eda6ae8763a0743a1acdc2402
403	1	32	\\xc26d9163f6f6df8f0b690b1e9a6f60f97cc8593ed0bd25cac343ec9d8e8a64eabb0046ec7fe27ff93920a4c9fe052676133a0385ee3dad46ae5dfd6c9a51dc04
404	1	292	\\x950dc2b770b8f6d4b9c3dd7c4423668b2e12b87835932dd4ce4438bb71c5641fc5f549d3c77f83f0b266dc5de506a58e4a73216b6ec96f5c35685e203a417c00
405	1	318	\\xb91e86b5b6fe1cfa64b4ced85512dcd38ea932d5f4123123d171fb5c7b4d85e5721490eda95e4e0ce007a6155278fd719c7a1ae5b69f2491faa29cb973ddd30c
406	1	84	\\x6949cc06445d9c8338f8db58e228a71d46d04953fc28974305b5a903681c5dc087d9ed07fbd401411fb49064d7fd7cbaa809159159e9078e4d8b04cd1806c703
407	1	113	\\xd73b11a297dff4ba8719a810abfd89ff1a7b54e0001daf8ee2a830d7df2cb3305fcb587c03deca6e4f1cfe94d051ee6343dc975295516c49fc5fab147ac93406
408	1	137	\\x9aa181b071a5afeab66ce1a4813b87c298103cfdc8950d4b5bd174bc191bc7ab159a59a953dd0a375015bf66cafac7a2bf4c86d98b59b6b080a8f0297318cd00
409	1	415	\\x4c5441303fa07a10ff04174eb032142255b408312a8e25cd1e32354ec448effd4a762a5f0853e7ea2e6783149a2a136b2defd087ca905ba8965523d620615401
410	1	10	\\xb0c432f2d6e10d0e48bfd2e61fb40d586abcbef3775aab047ad8e3af6c8ad56c057187e4c5cff9106c31ef92e4bd90231a2b6a71c1122c007ce955b680349201
411	1	366	\\x51f01e5572680c84ba223386cd8519ebb1334b85f5086c90c56b2beb5a2caac24191589c96a892334010766f6cd213d28989fa9373c50b7aeab6776be6bae60f
412	1	14	\\x0d7941dcbfbeb0d10722512b28fd19f28af9c1de63cc2d79bbb9e8f77796e40f104fe251649b736fe0e4dad8e3b280d08c59e5abf31b3b6bda5041cf45769e03
413	1	306	\\x1d818037a21e4e7026c7bb1e242489d2224774cd3150e980a5f216de35ec6d521fef94853bab8690a4a637a79950a620d95cdd3ab00a3d843ada76d0bb06ec08
414	1	89	\\x8e8f82f5ce0492d7f47166fd37876c7928364749465b6917b75e2d277c71e08b7f44f63aa984f335e1c68d69b571dca8148fc77199a0298b40b755a153b19f0b
415	1	346	\\x2aab1421bf380edca31f8d31e3080457215a4f5f50c063de24becaf3abf75cca3b52032cb23dec52f7f77e0930d04932c916f8df7a3d68cd5bcba0e55c6ffd09
416	1	403	\\x438d9b414d72a5793fc11c9dcbf5204a3e325bc0e6a5022b78ca962204ba8a6bf72246adde142ea95489e01f73fd14492f3ee73d964c701813d750febdca2f05
417	1	248	\\xbe2e624240207795fb63a63e31a04aad75e8df35243d03998d57eb9bcb23ac81eaa577cab71af5a1182e972b831e692e74a1b1ea62f9c376a5add9efdb5c350f
418	1	208	\\x62adfafff2c8afe4eaf8d83cc8de0c169a1aabe6422a104064078fe46bdadeb3d0726b4b6324e93d0d36bfd8e41db548333633fe4921d14022a00675a0e32201
419	1	423	\\x33cbea90a1cc345f4b1598e96b07dcf15049e016817d445ed1ee26142b4f7f797f8b0b8f788c827faf58c0b127b562ef8e549c3abd82616fbf09e7d24712700d
420	1	374	\\x8571ce63dd839ed50c5a609cf04eed6b878d41a80b886f342fadc19415d60ab25166d76b85be3b6f52cf172fc8ae67ee103f4404a0cfd3abef6e4ee123e87906
421	1	11	\\x21daf4a716ea3eb3d720a54d2d27deff95cb721b9d9816a77286be812fb0fe4edd7e56a71ad1f82cb6c0c8216b6805acc5fe3eca2444f9e1fbf5f085cf76e300
422	1	48	\\x1bd62f3dfd1531c0b24c251554d9470f0b0d23a60836f1a59c8c10fef58c1edabc17187b6713fd578c02fa0c892d1542f922a91d8ec8098b4e05c1b2a34c6d08
423	1	178	\\x05de6072205b2c8c099ead9b12ce0582c9a3536ab21f164d92ece1bf0d2afae20b7abc675ae93e3475b6c18c0851bd3015532882f41f18b3fde9663302f38207
424	1	276	\\x58e6f8c747769d2737cacd9545cec884f8810614d32f81927a31735721776903517df464e042954ed60120a1a9134395866eda6bcd279537f16af8d24bff180d
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
\\x9501597634378d1f2ad3171af88e2d909c99ff909d06e03fd8d8b638b34b1b6e	1655640367000000	1662897967000000	1665317167000000	\\x9bd85dc28e06af0b1bec2d0927025abed8ddd199cbcdcc41cfd996598cd4a83d	\\xf94cdd1c684c1e6a736bb5c5aaec3d5c4f60310ce02f2702e35de62f9297a9d623bc474fb42bf174eba9a0938594151bd7cbc5bfc4b70987a2dcdd8cb0c29a08
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x9501597634378d1f2ad3171af88e2d909c99ff909d06e03fd8d8b638b34b1b6e	http://localhost:8081/
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

COPY public.auditor_progress_coin (master_pub, last_withdraw_serial_id, last_deposit_serial_id, last_melt_serial_id, last_refund_serial_id, last_recoup_serial_id, last_recoup_refresh_serial_id, last_purse_deposits_serial_id, last_purse_refunds_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_deposit_confirmation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_progress_deposit_confirmation (master_pub, last_deposit_confirmation_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_reserve; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_progress_reserve (master_pub, last_reserve_in_serial_id, last_reserve_out_serial_id, last_reserve_recoup_serial_id, last_reserve_close_serial_id, last_purse_merges_serial_id, last_purse_deposits_serial_id, last_account_merges_serial_id, last_history_requests_serial_id, last_close_requests_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_reserve_balance; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_reserve_balance (master_pub, reserve_balance_val, reserve_balance_frac, withdraw_fee_balance_val, withdraw_fee_balance_frac, purse_fee_balance_val, purse_fee_balance_frac, history_fee_balance_val, history_fee_balance_frac) FROM stdin;
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
1	\\x38eb29aec4a464f408e49a10f271fc9d7d49a346a6b2e3463ec9b8c00629f44f	TESTKUDOS Auditor	http://localhost:8083/	t	1655640374000000
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
1	pbkdf2_sha256$260000$pcpbRoDT4RG48YNgFpZ1Px$gxYivSss9VE7VWTO7nu0/k4/Fo1LGMVjhAdtP7cvRss=	\N	f	Bank				f	t	2022-06-19 14:06:08.27175+02
3	pbkdf2_sha256$260000$LlkPhswpnWf1lcXeNjw7F3$5CMiNC48CHR398j50/yZObaUdVORXWbsgjwByLERFu0=	\N	f	blog				f	t	2022-06-19 14:06:08.455085+02
4	pbkdf2_sha256$260000$YQ6RaehIWOwvMOmg97nJiG$GDdm96J0SsTZS9TdQ6XBd4uh0M9cY8WJNgV9cJjBVRU=	\N	f	Tor				f	t	2022-06-19 14:06:08.546014+02
5	pbkdf2_sha256$260000$Bbfsk4StqT4rZVzfDUtAzi$OFG/u52Wa7nvdAAAXlfkNSrxpSEvP7EXWfExxI9UQTc=	\N	f	GNUnet				f	t	2022-06-19 14:06:08.637378+02
6	pbkdf2_sha256$260000$iLn9Zz6Sci3B6PxjmlZOP0$iwGWeu0/yFqGSeS8E2VKHHyvDnq6TNkDmrC27BX56B8=	\N	f	Taler				f	t	2022-06-19 14:06:08.727175+02
7	pbkdf2_sha256$260000$y3tQCIVmtF9lSIZWMsYjmN$m7EnbugicRTyQCgzIZFNtXmNmHRmwDFgj3yYiKZf+1A=	\N	f	FSF				f	t	2022-06-19 14:06:08.819347+02
8	pbkdf2_sha256$260000$Vtf4mJKjXwgOVgC3tL9hF1$5ijyctqb3Ma7ru4rLse0/zhrqRNKXiqU/9L8lQZD4Ro=	\N	f	Tutorial				f	t	2022-06-19 14:06:08.912558+02
9	pbkdf2_sha256$260000$eLzhn8z4Cl75ZvnuFWUiAb$9FoFghWMvcQb4AwE4cVzUcfdcwxkxYEPeizplbQSrQc=	\N	f	Survey				f	t	2022-06-19 14:06:09.002011+02
10	pbkdf2_sha256$260000$jhNoBHQL9wqMA2jNVJfST7$e8L/3T23PhUlN628d6QRrN1HXMJkGRPZu79aQSMWTGI=	\N	f	42				f	t	2022-06-19 14:06:09.45234+02
11	pbkdf2_sha256$260000$Jk6SLrSajOSkNcy7hW0hjA$rYKO0oJBegZRi5oc8kqLMK0HcK68l7kvbYYvOTowQRE=	\N	f	43				f	t	2022-06-19 14:06:09.911245+02
2	pbkdf2_sha256$260000$UVpOACZUylhTNags3wzLnC$ZZO2K9mysdtC2jFNfYgBlchQCy46Uh2+C7zUaYPrJN8=	\N	f	Exchange				f	t	2022-06-19 14:06:08.363938+02
12	pbkdf2_sha256$260000$SwmEE5mbf5UoIsNid1htpM$xXRHpVXKgjHOX81oMC/fAbL+Mh4eb68CpirZHwKE9ZQ=	\N	f	testuser-gk6lkeb2				f	t	2022-06-19 14:06:17.06455+02
13	pbkdf2_sha256$260000$bzKAIysOtJxIPtS2t59N8B$6MR15gYeU2MlDgd5viLMvo0K1yXwsiWjywXxAcQn5Is=	\N	f	testuser-bbpholtl				f	t	2022-06-19 14:06:27.670786+02
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

COPY public.close_requests_default (close_request_serial_id, reserve_pub, close_timestamp, reserve_sig, close_val, close_frac) FROM stdin;
\.


--
-- Data for Name: contracts_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.contracts_default (contract_serial_id, purse_pub, pub_ckey, contract_sig, e_contract, purse_expiration) FROM stdin;
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
1	\\x027095cca0384f53c7029b7827af4b2171daa4ca15f4e7192bc615a363046ab473d7f7108145becc279899586e359cf9e3d36e65e40482a3725ff97d6f6204c7	1	0	\\x000000010000000000800003d78db7d9f7d43b2b973de3cfc0bea83822f5e6e3d7ba0c18638ed32298cd37545612e784163ca3f4456104729f8286a43c41fe3fe6f483a100b76cf81cf4b2525087e45d56ec17f34d9e3c040f0f66aeb65823049b20d0a1f1f2fe64f2c72f48c8bff22d41c346cb21fbf1eabc556a5c8fa370ef617b874b109c5f1ed67894b5010001	\\x0e899a551d03f930514e30967a0d8699166a6e067ef35a32a7daff578e135bf342e48e41b34da8becf98404102c0d41a14c8fabdca4df488b8865a876e77d40e	1667125867000000	1667730667000000	1730802667000000	1825410667000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
2	\\x0620ba03c684f707bfe8a4c5c3b4a498de3e163968ece698cc08591326a002330b96b002b8d9ed287920e303ebcb43b0beb6b4f156ad33f9661260ccdd7bfa6f	1	0	\\x000000010000000000800003b64c33185e6ef0b4e3acbfd00751d51e037f9ef180c81cc6b35d7a833f02917f93291e28dc391e4271a1167ce65a8f88d55e23fb5a723f19814a08aaba8f0bf564ed2299f3c31c0bb3227c46e0c86be6c0e7e0ae2e7e45fb86929232212785e49f73f492cf115f8171161875f0bface61174feed659d4c261cb8a9a8dcba762d010001	\\x73aad1055b93fb4a2995259c53023d2952131576fcb1e58a1798d0bc176c8b4a8af38667dfc7b100d578515fc6a7c008a5f043523b0e4bf0dca9a5a12a4bab0b	1665916867000000	1666521667000000	1729593667000000	1824201667000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
3	\\x08ec100740a819e68f6706528c948c86540f3bfdc6065358fdf5e85e87ed608f9cc0996a25cf85f17ed7adafcbe64521643d90cb1f65806af8c1d090824ccbc5	1	0	\\x000000010000000000800003d260654a90cf372c1dce6d09697b3f58fe0223f1e862d072779fa16e835ab8a173df4f6bfbc98b324473d8bf6455345e5495ae762e00299893a2c60102f6199c7c7f3d6f124577f02ca5f86c21a60905b4d5976d2f1dc0b83994a27e3d8f37145c4ccca2594ad90983d26a98d96826bd8fc50b48a640c029f0b89ff7cfe0f327010001	\\xfba134eb7ad7020f0a8436d0d83e08a8afb94c1e9a3d8babba084c7c30db4e9f7bf3f587c4b46bddb4892fd2fc600e8062c23eb4331464aa1625dc2e1d65d104	1660476367000000	1661081167000000	1724153167000000	1818761167000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
4	\\x0a906b4f6a79add9f98362b15446d08dfc5f293b3db757368f13582f2af36f343a944bef32abbbeb15c7075b86a10fcc223aa94623f5184cb15f8dfd6816a5d3	1	0	\\x000000010000000000800003bb7ae60a3c4af099244eed03427824848724bd3c11f3bb8d0a52a708c2b23245f839f6df32006027b2d82ae4ab5532f797721ab5e483b4cb7b705002d403abd38a0d6117421c1923109934f3be7aa5be1a7beb00bd1c528019731df6e018c52795263d4d71d04786e5cc7a80240988113f7320ef51b9a90adb607415d7746d91010001	\\x942d2cd9322caa12ff72c170904fc5f5bf296b60cc8fa9681dce6f4bfa26c4b2a3296f5a7a15f1939f9092be63232e8cdf173e771d18eb94523b86e2dad0230c	1657453867000000	1658058667000000	1721130667000000	1815738667000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
5	\\x0fc0f90e46e4e5710b011cd52df7e4abdd6e766ac0a551c7bc34b50af7f93d5d08107be85053dc264e80d43424e41c0de79b3d2ededb837b263ae2d8bd51ab6b	1	0	\\x000000010000000000800003b192c67ab1bf257198e98367adc63d49ecf66408a77b4809d4aa899ddbc3a3d448ad29c4f62239e3f36fc4e7d60942a1c1668774b032ad0713bcd15f5830b0b00cf9934f446eb52e26008277affc0c531ad12cc1f49f1566e36567d73859cb4b84490a426278c622457637ee108eb89c54c9ad0c9e68ada9d60b2757fa805c19010001	\\xf17c683f587cfb7f055275d8a03bbbb6a293549dea1bfd1e79b3bd1fb54b9de99431b0f69b5bedb67e6c1c4b4f68e8388a50d6d3e9a010c259c97686b77c6700	1681633867000000	1682238667000000	1745310667000000	1839918667000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
6	\\x10145d8db1fb88337eda42fd6c252ac899324aa31a3e8f13121104ae49fc97ee8bdaa8df41688088f33a9214bf403fa853cce45eb7254775467bb781337ccfaf	1	0	\\x000000010000000000800003d37453cadc70b9612837171bfb8dc52dd68fed18438dcca285d5be5973cfe2a57c1684bbb609bf133574a976ebc02c0a6521e54ac12d4abea36d3d09dcc3910245ff5676d0d9eecc2cc903bb4619b91c39957bedfb15aefdd56174b36bea2a5702e956d1304b24a2b06da8fd67a7c1942c103b7a93348aa15905881d448e3d93010001	\\x167daebf8c8ca0f90a80ac4da10ddf62f50736d1989d793f4401ea1b3d0e2b1144f05beac109b841412e7ef9856e5365508ceb1efb6308a4b494b12e5a893f09	1662289867000000	1662894667000000	1725966667000000	1820574667000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
7	\\x1024594b548789fce5801bbb71b13676c9b6ebe417c16b3a88495e37499812cdc4a10d499b8e7405bef623dac4ebeef85bc63fb1535f8d9dc1f587f4dfe1bbaa	1	0	\\x000000010000000000800003aee5146b61846ecbeb47724c1ec9cfc68ec5c61e3f9567938076dd6b66c8541b8df2397f58befeaf1b8f32260a3d26c2ff5a0e4ec3ec8ecc1dcf84218718c0ffac53aba58982b2256a0cdc76da0db629a4eb54fb36910eb5ded858381d041ed105997c1182065aa2dd69bd7b802af3571fabda6980e1799137889d3dfaf3bcb5010001	\\x8f9531da2c25e1a55fd44500fcac32bfbcaa87a224bc4d7e19528f9c290b4b10279cf4aed1f19acc696762e821b110244c3d7cb4be776119cd00b2ae0b0b1305	1659267367000000	1659872167000000	1722944167000000	1817552167000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
8	\\x11fc198a3502ac67a522c509179699db30cda9f7fd96ead5a0074b1a883112d64a2660b2ebb79cd91348d5ba2c3d3c45ee6ecf0919478be46cc26c32bbae18e8	1	0	\\x000000010000000000800003bad0539aa5080e6b6e2c981ee3339e94765e39c2813548451ca592d71577c19bdbd789bf982d0a88da7d64d462cceaca8a78c44878214eb166cca7612a52ef245b2dd1efeeefa7e21f5e6ab8764dcb9a6eea1d63f828f9a0ce0685221e806c0b9227095d1b7f3167cb405c2f087423ef5586dadad23cb4a5ecee57a581abfc8d010001	\\x7f8c9275ceac5e60dec24d8bb3cb864deb7ed48e7fc7bb59f116c211bb23503536da2568dc61a4cc5c55eec4e9188d0060e1ca097462a172be2f7785cac8bd04	1662894367000000	1663499167000000	1726571167000000	1821179167000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
9	\\x17f83ed63bb30193a232997365c1cc4312328d56a1625cf07a88583aa04fb7c9bfd91fb961b1e8786c71d8a752fb29420182c92c8beb9b87ae250aa5f5830ce3	1	0	\\x000000010000000000800003cc79d0e3482f8f2228f9942854d55e8dc18ee34fbbf1a0212d78148b128ae314b8b56f3f6ae2c59a8126ade62e935d7aecefc6cc4ab619e91a06278d8dab529b37827a52caa9e3ecaf453339dd687e19826b0548f34dbde75aba811e90b27419ba5ea4455bfd00fd9669fcba177720d42d995fb39c0540c8f20b7d34bfba3c6b010001	\\x4d3d273ef6ed76af54218b72ee5cf019413ae356a409b5b77d2ec361e4eb3f0aa3d0a3ffb2f17d6616d7944bff2ba56ca2e8c243a399a8882c2db672a746450d	1667730367000000	1668335167000000	1731407167000000	1826015167000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
10	\\x1a00c0fa6ee0c351f2010b48c8014eab56d2941f9078515278facab55832e635ebb1e1219fe17c2e51fcb715dcc61c9b8718be5b9ea488409c343e7620a86462	1	0	\\x000000010000000000800003dc0cc90b3e2278fe66dd1614e03e5da44e64d80d854cd687c2abb05525f6a8652842878e0de0e87e796544b82453c09a140d49826d1a472a0feb0281b85ff5aacf355947982c2b26480340463426e4c1efdaeea95750c82f8a1e6339a6849e2c713d458b23b730767894e68f0ad5e916bff29c7857de7ec7af3042af6992ec1b010001	\\x42584e6228d632ed719c63a626626644b2061d8d6fb5dd50a2513a3b657e3d41a4c13956b46085c33ce465928cc3fc0e9eb866227a86beb8558ec6edf4e4ef09	1656244867000000	1656849667000000	1719921667000000	1814529667000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
11	\\x1fc0cd3a5b989852b8f174df01fe37c2a0b3b4d8da8c2e432ac24d13c411cadfff03ef31ac9a905337e316ff56809feee01589f82df14cffdd81deadb10fa6cb	1	0	\\x000000010000000000800003c4a48bc8a73cf7895ad9d2ad9c5c87d887e7bfc44babdbb38ff364958cdf92ef5adec747d15db413bf9b6a2d2e3f2edf062de0022ffe121f1719b6d164cdff45b9688548843adce49eb3ac25037d3c57554ab71174178707e6b76d4647ced5547b1496a09e06f39a31f90c52b7d85c262ea7999d0b87cecd9bdb428e0b7d487f010001	\\xae9e455d79a9782ccbb7bd81134ed8e6697b2faabe4a5907c558e01916d4bf8dba5b317a1512af91b25eee77658c46181b5f10ec71f6bf68c95e79ba642aac0a	1655640367000000	1656245167000000	1719317167000000	1813925167000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
12	\\x21f481692a964774f77a54f0d74aff0b2a8d76c27f2b2991abf300c5168ef2c98387f0e72badff150654227f5f51f26852d164ce19f4eaeff74b956bf7d13db6	1	0	\\x000000010000000000800003bd79124c55c70003b3b613028f3dbf8fdd23bfd1500743f10868c8263e95091d0ed2d1890ac62695bdecac7347a220f4c98356b138f9e7faee4af87f0a344dbaa37a7abdb2757bb661398a6b4a941678f61dee2fb3e22a87f12ff366a7c0c9431cd16dc53fc8f79fa819bf03d4e114a586039873574a976c3f843b90d192a1e3010001	\\xba393cde6f1fae4698a64aef84a84a485af0447a4787e1766e64ec75e0683c429e3c08ec470c2309ce7c543c50ec6f0a097e2039a9e7624b467de83fbe07d207	1670752867000000	1671357667000000	1734429667000000	1829037667000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
13	\\x2c8c5607af0b845b1775f394d9154fa2fa59af6409c29b7d86af9e2be0dce73bce204c32aed2037e15a9d67236692df1df6370b015284992140829c911e2cc50	1	0	\\x0000000100000000008000039a66ad484a0ffae93c953efb949c0b359d531e45021cef83aa01d12e9bd767047b7a87103382e6a4b942bf1f05a86422ada9d62512aa28b5e545dcda54c2e20c320f621f04484296c0785f505df4e62a38c41f24d03f05a714042143168482ab49100427d2544156ff60896cf5d02194d1bf3d1ec030cf61be996259e1ecd1a9010001	\\xd8fd1b21eede14c6608bd31cde5aa46a5e6c70481790b331b67adb64d80179788bdfae0d3af1009fffba8a4f99e617c9dbf151fd94c4c8102f1e35430d837506	1674984367000000	1675589167000000	1738661167000000	1833269167000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
14	\\x377c56886e5c93a9c046c4b802f593e677b692f2f54ed323c0f02ed7df3cdefc95b8591afb1fe3acb82e5ac7ab372c0916e577ca0ebbf5497c69861c26331a46	1	0	\\x000000010000000000800003a9653ddb091faed4236eb782007a2ffbf2cea1e09071814dcd7107e63b2e507ddf1c1f5956519a9a60d4c5fdbec70433d7b49e39212a133d1254ad299ddec3bd82e1168cc6776751f52ff6642ebcd29c33d6d15b1f34548ec9b4f89a97897df1c0463223fd6e5ff4394e46582be106ea7bd17990a841a149c9330c644047522b010001	\\xda1a5ee664f93a87861c3360318f76899180228a13ac76a840312530c14d2aa0ee95c2662f5b35000b017de38eb54af3fee4a7ca4b6021f01cf8f3da5b671901	1656244867000000	1656849667000000	1719921667000000	1814529667000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
15	\\x374c74b0504ab62c4cb1dd83f94fc996ecfa8043b8b63ef3422810a7f3a780866dc7d12eeb7cf265c5a0c0a8602b936541f8f855f2f2617f6a00217088712f9d	1	0	\\x000000010000000000800003bea1f4fa54793a03446e9b6a47390c42582d0e039eec30f0f47d15d65eab6a4df161d20f950b0d50405d1b077b3e31c1b92912bb950fda8ab5b877119086ac4405e7aaef9518124c18dcd6836c3e03251fba1486ca1460ea32bbc7d92c9162243fd483475f62bea4ed4162befe6a2bbdcd02cb09bc6c01007d0f9184c2b007c1010001	\\x4fafa84c521bbaa29b72aa0f1282b02040b4624087d341287c8b850df611dfda5dec84c8e022da1dab3abaca3d9da9df04872598cbd647b1ee909459f2c57d00	1658058367000000	1658663167000000	1721735167000000	1816343167000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
16	\\x39386471396c185eca8bb3e143aaea32d573953a29330f9356794ee25b3f2cc59004433ba3127269862d35135a7ff3d95ec29a82e6491742a313aee19e764dd4	1	0	\\x000000010000000000800003d5169b3aaafe1751c65b8a26a04ba907507d39ccdd62752221fac6fd9d84159cd2791458bff9083953d4d8edd51d9e6c70005924418388e5b96ef63a6407e11dd816f2168d8ea0761f1d5d9cc92a2dea363ca2f97ab7a087eddbc04f66decbfc1bb3ae1a3af1dde1ed094378152ff159608e6f3f955dd6fdf527b6ffec2dad25010001	\\x3eb6b7cfad6f0f5e85b5b75616295e0661597da906bce9f11dc7af47b3f80f70750d948ccf393852913f08bbbf7cb0e0c9bff714add5a697627e0a40699b2604	1681633867000000	1682238667000000	1745310667000000	1839918667000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
17	\\x39a090b11bbd0aa7cad0c708d26925f6c0e03f9cd6f7788105a8ee28302f3a408548bab6b60be81174e9dfdab56b6310e42be40679aa29fbe56c58a5ec33a4ee	1	0	\\x000000010000000000800003e022966d15628005b3a8a6298ed2de07c26e7ef3a8386ab584a164771167eb2db2b6b311fb0412070c33fbcf662f11746cdb209fd8902c5856d953670a51a6bc42cca986355fa2a8b4f3cb37fcf62c84fd61ffdacca78b70c0db75c96b8847ba2a1bb49f592e710c35651e3decdd2e530c6d37b1c17693a26146edd8ca448541010001	\\x1df3f1b42fafe4d7e4ba3b85409149a0ad8e46c16032e4d86539905a164c656ef87e18a03948a6f327f06a030b7cf214cdb26bb83c4d6e9b149503a13fe2c80a	1681029367000000	1681634167000000	1744706167000000	1839314167000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
18	\\x3930ec48024232d9cc3a8e77fd3b065fe2796962d12cbacffd0d1533cb5bafade7aab5b1fb5b8c0cb335e87042de4627714bc41f60906af3a7d3636515576837	1	0	\\x000000010000000000800003a10e46f8eea9258be4e19bae8e19c7bad965f5f3cd4e4c122fa345ff83199cdc104fe974a717386646299f2598e16ef66f92b37b843b0a42ba55bfa733d39ca1be83466a4a148a4de3ab658dbc78d11711c3e09caf679f536f7810995c30438f80e0efca65d68eb0708e593f06817c48025219bbae58971411585e9f5a9ce849010001	\\x2c62209d96a3261d357234951d3fecb5b9ea9d75c06dbe78cab7103103d7215e63b3bf513e2aac74f3c9cf605517255e112325d100f28b42c299bc044865b10b	1668939367000000	1669544167000000	1732616167000000	1827224167000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
19	\\x3bc073ef9156998c30f70cbebff40e3eee5786682dee45d7978210ba0ecec2dfd2b7c716f302556afd5609acb834a83668f7e6b72d29926835079d61cbcf68aa	1	0	\\x000000010000000000800003c1edb35684e35b22632f4fc5e038172a038a3a8b54700d9b469d59e432c17f137d57cd7f07858d20dc4ac49648a9911b2ff2b5e95e8902990aa3596a87262d2d973189bfd54e51ec89c4b47e4bcb32c667aff4bdd82a5ef912be396f31132fec1392a91231c3c50500dda77ced8a9227be15a8909ac9d7cd62b3b70f40baf89f010001	\\x30d636de39299d0c6eb7bf88a575de3c7aa84ae9d94309e6fa687bb34c0a5dde89546920e42212abe33d5aef41805f63e357f158bc4657ab4a67fea1e65f1a0e	1685260867000000	1685865667000000	1748937667000000	1843545667000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
20	\\x3b40cdb0669520feb7218c0f7379b2c38bfd76d7e313de48c5b99c6d1ee8c20688e56a540a10bffceaa68ddf059e40dff056c65f0f9b50428cdd79707a92e955	1	0	\\x000000010000000000800003c3ce91d38f005e16d77b3973fa1b181ff845bac2ba4426cb066f5a15a30de73191c16a8c9f2a1228df82028e28a8773589cbbceea14b0851c40e65af9a488d40d594dda8b1c82975a535378631639e3b29c950311bae1ad2c2f3a8a5a6cffede60c2c30ff9225671d80347fb540089eb98259d2f63ae007676ef03b6273a9fb5010001	\\xcae397361c385bea03e94918175963e3a37c97c556cb7357092c8ba6879a91983e8007ccae4317d4f0d7baf4c40dd4f9ae2b0639c747a91b354bf7c0123fdb0d	1657453867000000	1658058667000000	1721130667000000	1815738667000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
21	\\x3da8d7624d899da91bd604215a5e83f6d63217bd591c161ff68e4c8cec168735c76b54857060fafed467cfc60fc34a07b19667ec40bb732e3a8303070adbe517	1	0	\\x000000010000000000800003d133bea9ef74dddd57a86b295141b07e4d69d1c7061e25edc55fcc4dd3ff114933556bac6028b3a88965191ca1d7209783b6045003db596d38128dc7728971ee4e1bbfb7388e8012569b2cc702c18d8da0c1543458292a40080395863d9f8ed7ca68c70a1f318693da408637d8049e0f29e0c63540b161baf8c12db65a49f80d010001	\\x2e8f7c22363170da584e112c3af20cf8dbd99b123d4eb14c82beb213a4d93d85bea47e1d49661c8f4f9564e1440497c0009aa5df12cc951a3a0b98d256c2b407	1659871867000000	1660476667000000	1723548667000000	1818156667000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
22	\\x3e4cb15b705648e86aeb5e327793784fd712d765865edd93ed820f14f9c7a334ad8fd5781708e9f0f418f3f90ea65ae111968181c7b5c78dbb5110a74a473c9a	1	0	\\x000000010000000000800003a56494a5107b9c8201f76cfc9e90c904543149717d9f27c2177fcb2e7e7fd0c97de8c35b9b3b768cbbc9290952a1aebf95e511b9446a9a813fa98447937b4cde25a87831c4e7bfa7031c59d93dfffdeef0c35aec5abf2005e0a868e23fc72aee8e0902338cf67af0c33816955e5863ad09ceef395e94f329ea04afe499602683010001	\\xe7780b029e4afbd9f7ee0d14d9c4d4dd9bf4b778344a3c5089c433fe47788f7ac84427a3897a5f560f715bee99a5946fbed54a27bf9fb46e53e456a0df97b902	1676193367000000	1676798167000000	1739870167000000	1834478167000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
23	\\x43d8403376bed10ea96c0800fedbe85cc457381ec576c5e4328517b6ca4da90139e71753562c3f925bc0c5ed4b76b3c7bf96ef76b4201bbdc6cc9b5c13d8f141	1	0	\\x000000010000000000800003dae5af2b366c0ade66579e3baeb9d7b40784159601e71bffc015eb32625907fce2270f8307703cbb2af8bbe437ad0d4792d4b91b85e264ee8bc3584c1ba9fd96f24501799b6db4a683b9809106f8a810d421573edfe700722e6dda3a728752ae37e19e6861d43046f1987709878d026d6373b555e5b74965411fe85e7f983333010001	\\xd8deebe27d77c4b2cb01fd70531b5e74b3e8d6ade89c05411c104cf793d8c9a5e3ee98113a3ec6bc5898ff7195f736e2885c53613b3e96e0d6231e393734bb06	1686469867000000	1687074667000000	1750146667000000	1844754667000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
24	\\x44442cd6c5e320bc968d4c9447e247430ecf1ad2c1b35dd287ca5ca183b2615212249aa317a2c1645eafaff6f9d02f5a136d90886f6aeb66f34f9d8da754127c	1	0	\\x000000010000000000800003f31cc60a29756c32d9373a75d54028f9b3d89ff7b5dea033f64a4eb012ef465a6e454fb2c5cc929b2b99d9a11dce100482f750450858fa7b051a1d32705202e37b56c39c5f72ad9ce194867cdfe7b2f41f9e0dfe87353a1916ee2ee2e1d60502cbfd3ae09da6f7fe8d09802994d7dd8865f7c085eba607ce68f92ff6a3862e8f010001	\\xdf9f4cd7c923171601eed196496663a0aa5baad7b230e45d355b95d6a872e31305e8a061bd974bb84aa4edcb451efa409b7b23de938ca27eeabe032f3ebf3e04	1679820367000000	1680425167000000	1743497167000000	1838105167000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
25	\\x4564b0cc2ef030aa91705c1d776cc9a5586541c492943e11e546633bd6a2524b8d411483f4912b8f2f22672dc824a5324f4ad2f11a5f5140bc4a637b40fb9fc8	1	0	\\x000000010000000000800003b996c5c43edae6e6799c86bfa76c853b435ecebfc96c4da0f259038f5422792a5412b46ad2f7333873e227c21b863f3df215eeba0e5f4357920e5797d7d54a9b14bd6c3921954ad77d38d11a42b04b03d72f99b6f06be66000c600e21ff2b7a36817366e481459e31861db8600d42c7a385534ff051917ec55a320e73c65abef010001	\\x30b91292cc1c86ad7f0566996129e4034d92ecdd044feced0ea640dca4c9a6a7d353134872f19c00bd01018583cd2601c080f99d14402a2f81c7079c4ee2ce06	1680424867000000	1681029667000000	1744101667000000	1838709667000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
26	\\x48e8a1d919f43a833e659f6b86207a791da91731110c5ee8d94ba7977a209538e883f277e330b16100eef70323e315fc006d97c16b67e105084be9bac3cb6b45	1	0	\\x000000010000000000800003cf92eeb16f8f12ebccff8d6b4e0aa566261624883efceb9782fd5cd4d52e4c79aabc7cd07ee5bb57d980e1e39700957d4299b2abe1386186ce1501cdd721ab291fb36349869a48f67972f1349108fb6cd03013022313205b7394904d448abf23ac8ccee73abced0537966f481883d75d17fe6ac2946e01f72ff0a9fe1bafc779010001	\\x47f5f10c8681946399daf90a4de23d36205296499be0823dd2fd366070fc45e1faa4f4bd1eeb8197eea90120c3cdf9037b0cdf21b0ba3c84b6d1e0296e1f1404	1664707867000000	1665312667000000	1728384667000000	1822992667000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
27	\\x4de01e1089e3039c430c9024305494e1941ff85a76e6c36057549f97cd57d78c63d31193564eb027cef9f4df95f0a422dc201bf6ccb0d99edeb655d7133e1115	1	0	\\x0000000100000000008000039f1d8a26d853e55e5c90a7fa2f94cad3df8586c0a31696c144c075a94382bb007e948a545864102050110c21beabe2d0924d0d22973c1b7d48195e2fe7bbaa8504640b93c8f36bdc8e3bac50c45163c0c2c9fa689c704b0f2b8c82360246b7bf0d415b4a541b1339319ab724baf5fb490fb0f5b944815874e84c725ef0c254d7010001	\\x0b833d176086deeb725ba3dec8c28517d7105052ddd45fcb0352193231cd2a9dbd2714ec81c53f01441a647bdc8ad7e2f13b2752cd4a2c69a02d375d76b52f09	1665312367000000	1665917167000000	1728989167000000	1823597167000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
28	\\x53d8dcf4a3ff3d3e4336bc31151c437164f4e510be29e558dec22c9fd96082c90fc447c1c05dba571efee81281951a5b11ee86188a567346267509e94e005a0c	1	0	\\x000000010000000000800003ae6efa4b4fe89b4a914049e83677b55eb5a61cc0da7bbc8c7105ea1da5d4b9e7acb1a12e38e1123a99efc2177e97e36f0de899cb98322c3aa30fc5f77f3ff3afcae5d2126c05082f7afd05a02226d6bc5a86df2ffcad34c98e953a5f90ed512ade08743f3aaf95201bbbcc7fe35f58b86da68b897300d823f68af460d0d58529010001	\\x4798659ea7a60b25c0ffed2bb6c5b06219fa549a75c24187c039cb2a0fe1af6733997c53d999a1a6f084cba4b1fbf9d060a2eee19634600481a2f80d65085908	1673775367000000	1674380167000000	1737452167000000	1832060167000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
29	\\x548491f47c8ef5cf82a85e9f7a065534564f827186a8ec9e7591c62841654af92e213510c17a636d24e0ac3267adbb09463d2fb80bba50534b7c82e66c6cef3e	1	0	\\x000000010000000000800003aaedf3f0d9f90e38b17d58d54adc4acca9d74db14c86e25e23de69175e9a36c5582336f6eefded324d31788376f167a1047f2f98f14feca1b2050de766e9908f43f17fb24b8ef322a2bb3f0f3c06ea1cc128cc3b75cdd5cc2bb7ff585bf27541fd68db55efbcae624f0fa31311a44146ddb28ae90d6d6003302359789cedcb89010001	\\xb5a5f4e4baf82728ed7710b4be4c1cc4fa689b0cd87a9270af0343218614d4473a82127665a3b225bd4c216a21fda87815de5c64037381a43837fbca590f3400	1676797867000000	1677402667000000	1740474667000000	1835082667000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
30	\\x56d47a5d4a9707f355a65a79e5f378287685152cabffa7e3d6e142b8c749ac374e6f857d4defc1a5165d831ca854689ec43bc3dc4e2e69e1a3770bc2a6525aa5	1	0	\\x000000010000000000800003db418799802129d211c2b8365e568d66a8a0f4833382043210e72d6d2cf50bbf107b7e2213d56fd7d0277d454a90c3d221e2d40ce86724c054c236492d0f3451cbf974bb591414a38dd7800ef15745e2bc63172af2410dc0167535989d1f11aacd243fbd58d90c091f73f9e4e2f0c9433d28feccd6d12feb2cbb96fae262f453010001	\\x4fd188a7a15f7d0a5cb874ebd79a31bf15d075402a7bb1f6efb5c8a29131015b59fc0cfa8a9724ee99c2c6ed2439c045d9473cd0d6e9b97df864c3244de0ff0f	1673170867000000	1673775667000000	1736847667000000	1831455667000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
31	\\x5a28f40074a8a3142950f4c8c79c287488adf52b7a5b34b9678d99afd66c2ba3c83092519715525ce758d7f1f5f15bafe44f18f0e192e310c49aa7a611d6193d	1	0	\\x000000010000000000800003975e4e39022f530b5343d1551506ebb05ed3730e4d432a5fb7197b1553c4ad2ea739ff39761fd2a50e9c4596f83903b7689222b07338905e3439c3c5612d25201dfd84fa59d5db2c470661e4fa0fd5aaebef89b113c20f8711359ca918c05ff0889e4d837c7f41029ed04548f4ac713050a22f7794aafd3a6a9ae6ef2211fdbf010001	\\xbf5c20b6356da4592c1311343f123bffbe0a5459658580d75e8fabb593f47cdb02145b27ff7f1d1ebe5f5328a5497df204ac59b1d15d03b308ffc725817b6e06	1656849367000000	1657454167000000	1720526167000000	1815134167000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
32	\\x5af4631ddfac5e15d62d2d3cdb40ae76a45ddd985d0d7f8b515b240b1779ae02321e8207978ca67f2478640fa6c1509859f3c345c346b95228b75612da4674bf	1	0	\\x0000000100000000008000039dde752529216fba9bfa35c734542d0f8fbe76fa26d3e4a97d97e9db38822ab809812554560156dd31166cb8825986827f87ad398a6c990562342c692b5c9d1afa3c56548c67f65fe749465fc8888181b61ab5b305a10c3e76d52f9488fb9a5bb4470008833777008e58d6acff65f2869060bcbae2dd3a4a88a61ac6765b59ad010001	\\xf494c315f492a7e4bfae017f90fdf0595b06255d2ae0429cd779f9db7496eaca0f4803704ebb4143bc205a44fdf1a4d15e647fc5eee2a72fc6dd2450f8a7d30c	1656849367000000	1657454167000000	1720526167000000	1815134167000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
33	\\x5c68d148d1a2756a553d30beeb457e971aacc39239f9cc59fb4acb9befe443eb8f536a7b72f2095099a50f274a5dc28e6909a860e6f810768839898a127b4f37	1	0	\\x000000010000000000800003ba377498c7828da3eed108ac894f3d4dd900764141f99b6792e0331ace4d9bca6317b9c37d9b3c06b88c85995c5033e906e00ed4f770469d5c0d486df078cb967bc22e9844d58c3b5714c3e7f8e252ccfef4fed2b6c851386abdd3aad34a37bfc7364ee1bfb72ba936fbb6866b9082f682a2c535ccb38e046fdd0de9b98e8eed010001	\\x065cddc1ee34f6ed01fef03d1c6b8241256f27b89808a615fe6db9a6754b094be75b09834ea3d418c35786f38b6a027534d48d609f2c60b35488a434ceb6800c	1685865367000000	1686470167000000	1749542167000000	1844150167000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
34	\\x65b442ebce9ff663cb2ded2d0da128b8f83fd512aa1ab1d1364cf8ec8530cf9faec8c5313286ebb47e19c6a9d6fc0870163f298c7da659382ffab8d862e24400	1	0	\\x0000000100000000008000039bdbeb67ec856942544f6e9218bf38bf3e5c3262c8ace78909c0ca29c84b088163fda3ec61cd23f6cb849eb6aa4f0a9ee77026cfb2de9de18c1b322aa0a45ece7c3b0d985318311ebdb0303df5dc3932d63a1ab0e85b143e1a39b895374b60fd8649053de7a8a3934e11a60605ceddd12b12e06b25283e605810a2038e3710d1010001	\\xf80febcd2a96f025d75e735f5386027b78b4b3d7071e384dee6813e4435eac565c3bdff8d0c0f441efa0129232e07aa79ea54fe52fe5c964c257e9053f533200	1663498867000000	1664103667000000	1727175667000000	1821783667000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
35	\\x665004da18cd49195f857b0cccf179b251a733b183a4aebc8ee0363fb6d49d3603e8523002b0696df99fc8e3180251f9fd8226699400f01dd453400a9e970438	1	0	\\x000000010000000000800003bf62641420c57853f91aed3155d6b54550eb6f315ac986b5afe461b2082d5fb78f4ed4c6c244d30d1267ea36d5e5e4cb2154d55c61709552225887144268c139d8fae5ed074ec0cfe0ffe822417b7773039a32033da8b0b7bf987c35fdd6be24e42f7345eaeb73748aaf79b09cbd01d2bc80c35c9cea5d9fb3885185bf6c631b010001	\\x4d26cea32bf0ffd6c1643cc28632825f832f308ad35875673255d69528db6eb0f586b5eb30e944d03100099c7321ba4d4ff8a9f79b25512d6c766b1b09f35303	1661080867000000	1661685667000000	1724757667000000	1819365667000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
36	\\x68c4ad682a000585cbc80c3745965c7bdb8232d424f373ca80c7c59d06f2dd128db936675a502386258e494da38f866fb383cfcaedba31f2903e5be96cdd2dd4	1	0	\\x000000010000000000800003bcfe08a6bff69a2db03bb676d8395cb63e7819701f98515a8bc56c328ad6903ea1b09d39a7dc2176796262598256deff3ab727ab89735c6c8ce2698eb1c7fa5c90452a3f07924d1fd3af4f269cbd972b637c699341f9ef37902282d13bb2044b75a7dd4d5a16f394b1dc6de1543360d321dc27736fb501c945d5959e3ed0db13010001	\\xe1bc9dfcbfd595926cb9d446dc08ced2a2506090219c9d821a14aa0f84a71bdf73f6f6e5edc66497d4095c62993311d6aa4e34e322ad242dcab650c24955e40c	1666521367000000	1667126167000000	1730198167000000	1824806167000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
37	\\x6868f610f499495da55a4bd3374bfff12dc75ce44ba77340e1d21b811306834b456d994436e07d1be684f2b3722bb91b8e6d2457a777101ba73f142adfe8e83a	1	0	\\x000000010000000000800003c90b2e527ffad312b72224a56ca8d2029993c69fa4f53ebb43e21716cc6c5de8c79ecead1ee8671f82c867d72e659a081cdfa215a649245a9880979b3b74353644df9ec6cca524f2fe04bfa7736185e87dc1d011c2f7e7b0404cdd1b36d37698712eaa69e925459f285d49fd85d080d75528906f0f778c15eaa22910d71cecc9010001	\\x3050781e818d0a02cc552d24d045b35b3a5c9ce276a7f3b6b4beeae476e13c00f1123dfe425a12d8b13dd985dd7191e6938a5a145b33e91f9707a81e4ff0f708	1680424867000000	1681029667000000	1744101667000000	1838709667000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
38	\\x6984aca5758f3e2202cd5d7589e4a8a058b616dce9881d35011a2816d8c09f6939ce5fd4a2efe93fdacbbedf3310fca4510ce38160e9e36c5dd557be4b43389e	1	0	\\x000000010000000000800003a4bfc2140ae8a35d2e30b1a436f2b094fee13fcf3f2b56352b305870bd4db2cf415265023e81bdd6a1f17a0c4f7fc0f53b089e0eb393f32bf7cce2b4d61cad1a33501fd9ef882348bcd27e0fa7e3428e9663a19e4728c5b82dbc6a58ae505966430068dd1603313eb8755612a8162629d0c5c06d7a2db5376683ed2861a659b1010001	\\x5124589fe94a412183997be1182a5face01527d4a6de25a085c2ce39fc5c80d2e6df6248bdc34e4beca4c7ad726eb5f01080625c9ec90dd0b5f523fb02e67306	1679820367000000	1680425167000000	1743497167000000	1838105167000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
39	\\x69944c6df63b27b9ea485e7fdd3781004170d3c266ad5b048ae299d40aac1e3aed9663cfd58044693e71966b9e16424de5deccedee0b20aed99effe1b2f4fdbb	1	0	\\x000000010000000000800003f5440e89eaffdd6cb17f9debb1d886d9e07dbd4e5c4dff8a49714869b7e4dc2236cb69bb2a3d3ff897ca90f0e57cd31497dbaaf9a91f8fac46b61d6d9fb68c16b375e449da26148faadcd4510c90c34b4c3aa1fa34c101e22885b60d781c5f54956e35a653898a0b81f5a0bbc832a3622666620c565592cb0341b52a8849cfb9010001	\\x997f67917cc2b8a73d611feabb36ecd40ec6693082db585a403d19823bb8c2158cfb9b231606001c92159994361b3497725b45436508e8cac506f0924ded960d	1667730367000000	1668335167000000	1731407167000000	1826015167000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
40	\\x6b4076a2d1f6752c96457e5efd829c1d3f8e6b92e0b5f644e310bef13a50ff30ae5c05bb024a32ae1c8728ff0e3e525d537cb0d961775de954b7d75550078c61	1	0	\\x000000010000000000800003a999038c617999fec6f94860925e0d7e1e99f3978fece7839182e7da7d821bde355fdbe8ce81c86c20e855aa0aebcef85eb092c8d5da895713bed49f93e643d3399b05d221686060523bc8dc2b8b62ed4ccf01950fe8c28e471ee68312c02028c4b1da2ddc09c1f82af0b18ef5febf915787575e980a598caee4fa19d2af977d010001	\\x5bebdbea6a758bc1fdb58ac420f7b241e8bc2e7260d7185c5f477f2b402e2272ad0046794995ef68919161ce253c92db49a20f63098039b6ff6cd708c13e8409	1681633867000000	1682238667000000	1745310667000000	1839918667000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
41	\\x6e7ca01dfc7959f18e36a3e20c157240d6bf48622229c615f8d273f26d9bed0719c53d9369f1155481ee5838067e838bc77bcecf23ddeba3b4049ecabb94f6d6	1	0	\\x000000010000000000800003b87ea92930f8e3d074e890af3144d14ad8b8c798af6208a7f43888f2c8eb46eaa558d27af16771cecdeeb1ed6c10e06d13ebb170734ad12c0f643ed4f62fa627717497040668b58b8e17a4840ddd52ba5952f0fde9c1efa74c1375bb1728be93d99cc1b94aa4ef8b72ea649a3c3dda0fac4a58004d3d0f90a565062c393e0077010001	\\xac66b95f06958da87a09dc9bb7b84063867521b128c5f6913a121e8c6418c04d56f671fcf65c6f8d5c2f51b0eeee8f2fb827eb56d37ffcac516b265ee9182b0a	1685865367000000	1686470167000000	1749542167000000	1844150167000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
42	\\x70f090c6443926d16ce5b23d6ab82076da682043a03a2194f79e7503eaf7f87f230bc56b1961e1f48b2767cbe7ffb1c958382858ad966744fef29f6a8287ea38	1	0	\\x000000010000000000800003bdf732b0f7d202eb55eda8962099f2781520d9be15bd4202fff0760fea5f3db40fd41873eeeb140ee1b13d9b2ac5941fa5ad6bb1f319084347bffa304650437084774c597101ee9e64618c826e22a9ef4303e6cdcea650f33b9f229ee1bd99cda23168c6a1da2bc93c0ccaae9d46d518e88aeb8867a405413688ff90275a9ee7010001	\\x2a0a24a6dc8b9f1552e11f647a47d9cf4f33d096ee984deaf1da222da01df0b918fc9dbf1a5e6736ab168b9638438b53a1af0c2046029c6b7bed8006bb68650f	1661080867000000	1661685667000000	1724757667000000	1819365667000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
43	\\x7108ab1e557adf6b2a0cf690a0e4f6601b4c996b01da767b4d967c0f8cb8d35b584d8684e7ff422967d3810c855b09fa6c04550a64d768493445f08943bbc19a	1	0	\\x000000010000000000800003f38d2d64e5a1b2ac7032aba685e8e86db5b0fad18cce850392b95774ef783872f213ec09912ed42839e873cef2632233ea9cba43f3fb60200e6a80e7e9710edd9de16a359a2bfd578685f66f37bfb121afaa15a2fa09014f3d36bd650fec1988e503097047918d088dd45f17f79765a37867b1e9c0689b0a1b556278f703fb15010001	\\x1bbb7060c931672d02dc4b07ef4fb507c703060cbd1ed261cd86e5d9c4d786671c2e1c210e97b0fb533ac315f1ee4c6f0f1499d4e52cd732273c2c65a686a00b	1658058367000000	1658663167000000	1721735167000000	1816343167000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
44	\\x72fcbcfe94161978c7ebbb51727c51c67708934c94d4f47aba021f4c3b5bc444d544ae1b10678327f9bb82d05312be5b6f3f115dbf1f7d1abfbd67f140aea089	1	0	\\x00000001000000000080000394e2d4f8cb6bd5f7258c1d669dd6ad843351fa40cb2e0c6c867db7e44b3c28aaff48e760df749ea0372ca584b895876dd586392f717bace728efa7f4e7d652c66270dde2279bac554d83d72e11c6f35118b31b8f95d74c28f9e79d501acd13f5ba454d470a5cb648f0e130b2c640042702c0558ea312e5747fff5c0689e15d1f010001	\\xd2528dca4f35a64d377ca66b446f7eaadfa97d0e81f2de1e531f6af922eb945e70254330243d7aa7a9a383f2ed6f1fb47915a18217e236c4ea3528dd6c2c8505	1664103367000000	1664708167000000	1727780167000000	1822388167000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
45	\\x76283433dc1c450da525fd7dc4ee30ea1df210abdc0f73cb7a4f5ff146a372dc717b8c90ec3111c5ab852fbe551d3fddfc74c70989ee513596e31c34ac65c07e	1	0	\\x000000010000000000800003b53fba5435fdd07f5ec5683b502a593082e5f8ea03684c21098cffc5450aa224ea89f556929a19e3e9704104e371f47570e28ab8cc44b55d964eeb24ce4a3847ca438df77cb4720296d074e71ffd7bb84375fa177bdf666c33879b5ba9ccb7c12bb2a909caae5cfa4eef7b17d271ac7a37662787e730e4b6b111c44d8fad24c7010001	\\x1fa2c11eadba79dec01d13cf592c4d9727401cbc8ac1c2b751445b4ecaaa3ae7d3c1ee4f75bc0041babf6e398e15c1be3b9973fb3f49d420785a4dc4d8c17e01	1678611367000000	1679216167000000	1742288167000000	1836896167000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
46	\\x78d08978b0f66eb65f52328485e805f10d0a6359c5b76fb1dc159fd7f98f659fc1668ea42cb228764192ce8b4972f51b2bf2e12784ed175612df8323adf8b676	1	0	\\x000000010000000000800003f54ce8d65cc68edae981c75316dbbf0cda9a59e7b96b979b9bff590631de64dc9d0dacbc5b68d01f0d3eecb2754f9ac0073c6fc976fdc28ef86a19d0314ca4bd1c928272136692f6ecee6a97f421b4e8b91820eee575adbc36e103fe4ceafb33bd8c3feb84b76a67362274b8014caf2b7abfb8f8f510b09528c58aabe24fd19d010001	\\xf899db5c67ae5a557eea9f1e0b1a803dd15baedf120b27997e09a0bc24b9b5e1a412c6fd8273188702c5446592981edae73b1fef8003fa525bfdebde93aedf0c	1671961867000000	1672566667000000	1735638667000000	1830246667000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
47	\\x7898d01259b2ebd8a90e7dc2097536f7e2af8d9822c11da994d0023bc44c515a78d532568737adece61df3c5079a54057bb1722e05df8ed1bd388b631cdf1a20	1	0	\\x000000010000000000800003b268bb4bab66499f792e523278676355bb7449ce0644799abe96294c67e5bd9b05fed58c9f69d1813462f28938f71b956deb6108048bbb1cc8dc83bbdbbabc1a97bd87125b87222b42890e0afe79c8e2be293c076011425f97cdbc19796a7fddd2efaedac02624e0238ca36e7d4fecccc93e07eef8dd0616a60d0b9e5cf392bb010001	\\xde5e49339945737c191c9c0ac1ba2e7ee1e0aeb56667296bbfcf81b241b34ca8a11cfbc0c37cb74f03d857e87176c6c5bc5deae3e32a554bd0a584b27209470e	1682842867000000	1683447667000000	1746519667000000	1841127667000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
48	\\x7c34360e142f47a96ca632ea7297639c4d1302a36fc6e0de34ee055f74a27fcc05f27ad154be5078a2f248871d45febf58e5b3581cce22a25ce758ae7e70425e	1	0	\\x000000010000000000800003b0b4ead1d743965dae92ba759a1f35c19b63f925477eecfd4f028025ac667a127f1c14d78b5fbac1ee36e532ec27a6c78f8996f83dd29c8b369fc54866b2d2029deffd647cc629e2eeae00642212b10e36d1cd4d90b32d1ff0aa0e4e556a18c41c0f12a87f9bd3559526c1cfc149b9c7450d609e565ac2ab47d10f2c1ae24b83010001	\\x082197741af56d782cf39ed558b21c20308f45ba653ff0b00b96aea6df6cdc1920dd115089dd4171cd0294ca6a768c639f9b01d0769b8e927736a4d73afc910c	1655640367000000	1656245167000000	1719317167000000	1813925167000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
49	\\x7e88b804cee54d41a75173d9f1a6467f40ab68318633896ec099161617f582ed543654e9253caf253f31b283002a80a4786e60194adcbbd2dae50d7c4a15fe61	1	0	\\x000000010000000000800003dc96de181a69aa48393ef17d74edea22cd8fbb4f263ccdb5e79e474b42d4feafd16ffb7a34646acb993fbd3aa9c5a365f81ee0623d3acf433e3bcaeca86d1d3fc8d12f52db1f5eebda05c23a08426e5182d0699ad9457a0dc9bd4996aabceac1022a22bc6187aefaa35cfc55593d8d94332b7d738d73ffc78a5e2ba4a2fb51f1010001	\\x93ffd9531d16693bf1726f19486df3ab17009476e6146617adee5b0c3a7a8d7dbf23775d11c9594754e163f0d7069b54c3424ddf2c28e183bf4955f8956d3702	1658058367000000	1658663167000000	1721735167000000	1816343167000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
50	\\x807427a48d8b58670edc87886ff2704f24cc00eacd3ae5780d03e85308f1114291e2f75c6aa46a9e32fe1d5fe06fb1513e85ea4360cafbdb85e7dbee2a84bce3	1	0	\\x000000010000000000800003a3da9d146f02d1de94b5c79a142a6af4ff25cf4cb91d6d326881d8540a01c3be77af5c1be11068bf7c8b8460897e0dfd397dc8253fad74855aada4ef2fb4c704c13419fceac6a38b4a3274e43f7f28daad6b6ad7cb5470f2bfb43d9a430173fa43dc76fffb81464e3ce0c60fec983980bd8ab8b46fc3fae83666128ad93ee057010001	\\x75581b1d8e03899252cfd0aa0b7b600b546f1517b71c466bca7a4a41c1aa738f8b12d596f6e0d2b90048ecbc16b3f40c9c4df533b136636ddb46b4e718197d01	1667125867000000	1667730667000000	1730802667000000	1825410667000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
51	\\x817894c055bece0072633d98c51341b1e21b50eb98a247982d9f46760addf45c36d6f3a9d074a9afa324a95ea1ede33bb9eb8ac0d835e27105de47377a8af7eb	1	0	\\x000000010000000000800003c89d99ba5ddc4b0c8d63bbd77e40882535cb6d47bb6df5473a6e49c7cc8019ef3a01fa62ba73018559ec4aa278e72afdf9a721d1e05e77d38283bb9b6f42dd874d52b44709d9272bb87b1c5978ce99d9e37b4cd31018b723e25673318cbfd30fa7dee250f69ef325fba5e7baa87843ecc3183afe3cf993d0ac510d86ace86499010001	\\x6473534a1033a52627fc4555a9f9e6aab98177ec7d862751ffa9cc2515d89c5ce91ae90c9a9508c2cbeac0288b607e6de708c3b95f9297f0f638fca6afc7af0f	1673170867000000	1673775667000000	1736847667000000	1831455667000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
52	\\x83e4457363fa9fb27f77aa7dd43841c9d3768b756ae79fd1dc69c849db957cf69611abf1660cc83d5e135348fe020506cc5613e40273895cf08519305b66d3df	1	0	\\x000000010000000000800003b28d91abd26c6441eae17ed9b32f355533d36976bc59212996d180032418f052e5a31e4c045248d747b8bbc9d3a315fb69feadac680c63148f18749b2cd03135dffc51753cae145d14242f910549610946de128ce0a68fbfac893c9ceb60eeccb31883f60e162bf668b79b3fa489797fb930887a8c3da869960199ff625610cf010001	\\x62e5a91f2638295fd8c73414c73494017f83a8cc360fa9446bb5b4568c94d481f17dee25341b14456cf869acd103fa2f29011444398e3b2acda898ae628a120c	1684656367000000	1685261167000000	1748333167000000	1842941167000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
53	\\x8b00a55bfc859d7a0394a9fb691ea8c8e35a3bae3a3b6592991fe34dc1228facd4d25f011a0c60fb458529c82714f92255e5ca673d6c697bb32d09b4964968fc	1	0	\\x000000010000000000800003cbeb921fca251bd90413a6477c30120c6b0e3e09e018d59ca1cef48ee54fb0d02fb7db60713ca2c02bd766cd93d425d7cf80cb7b4c7eb71578b3a4f682df372719fdf4f0f0fa68f069cd72f3a9cb0d39a84abe0d3e947a5b0c956b02a59aa5c5a8f55f8e60f11a4d59ef9dbbdbcdc2c04bc05e749f7f0a6858afc95c6ce71e23010001	\\xa589b9dad49f5c63a1a181ae4b8e59ca3770a24d7fa344760f66e04b1001e0b7d73d26804e9084336b9922b05adc867df6b845200006f18df764021e871a9800	1678006867000000	1678611667000000	1741683667000000	1836291667000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
54	\\x8d0028b4b7f087f11ab98b5f65cfc5708d86cecd2c58e6d27dc7ee0e0f35858a14572e6a5d0337111ad90831dbee0bedb03c0788520bc7d215d9834e31c72b75	1	0	\\x0000000100000000008000039ad2b94d356a441d29e6ddb32ffcbfde9f81d961c8974d189f81ae6cda7a7299f9480188b663fb0ff7aee41cc957b8b259a3bbdab9d11aa89ee8fceb179a38be47e1aeabb9c7c0b5b14b2d17fe3a52c5c5e2ebaba1e057d7cd6140fe463ff5f37853d034a0d976d8eaa9cc6b94a6277c8472e2f1a049dc3adf8b6f54c19ae87f010001	\\x8101e30429a1c46f83af7c2fa82aee41461a8e842ce709c4cb374fa7ef604e8da61697b9db844ce71ebc5cb9e96a5ff7de4b246d67562c4c822dea65518b460c	1684656367000000	1685261167000000	1748333167000000	1842941167000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
55	\\x9490db74a961874d2e3165ae963e787bd7be9f96b978e33136f919ccc2e80d0e345d0f0ea32355b9e0c16927758f64bc3f792d694aa2deb6969bac637a59d6d5	1	0	\\x000000010000000000800003c468e65da2db112cb685a589def1d6b3d2f1c0e84dd6707523461cddc440783c7e180b7e0e96377a396d121001e3fa6b1e0e50b3c9f27b13e589928753cc91e9ab828b94fbf8719e03a91316a21455971fafbab7f1c0a7a0baedb8ff3203521c33d9f42682bce824e809c6a0d178799853a932e1bea81084b794563dd4be0325010001	\\x529a0e91ab22e1f6a93094e09a89502658f4f948583507aabb1583488ddf4bfe07f9160af3cfff3ac3dd3b12d79f1d0410ade90b16f47690fb5cb72933c8e709	1668334867000000	1668939667000000	1732011667000000	1826619667000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
56	\\x9734c939e1fbbaec0cd3a28d63a0659ec8c0dfd035cbaa52ab9ef0f7fc66f9ba03ba2f9617e6ae5a5a70f32da8a90efac27b244329112af6dc58997b96c52c73	1	0	\\x000000010000000000800003bfdccde4bcbc718b227ae859de5ba77898788cb17d11a0df212813294f6374e997ea926124cc6419f0eb021b5053d44c0fb2de522f1ed0c4af22f123b50c781507bb16017721a0bf1e457640258e6cb52729d79f622a12562165b7c8c7fb29b0eee82a4afc8140ce7fcf2aea6c8ce404c719e299ecfc6baa044a6ac012ccea01010001	\\xdd0ea52098a91815c2319754a79a1d453160844cd9bf0ed7a68c64038f64fecd031ae50df6abc771261654795ce3e9dbc8a12ee789d9f787a71a25faead80807	1660476367000000	1661081167000000	1724153167000000	1818761167000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
57	\\x99e8259eb2acf5546f91096e742941c4d60a2ad091cec8903366ec400d2e40a041a1e6f21b7a6261e354800c088fb53e9f52ad4cc6641dea35e5cd6f53fe56fa	1	0	\\x00000001000000000080000395ed94090c297c46e9049849971fb588159012326f50309a0ae016b8e1079d990d76453f4925b6addd5ca078c4c66ef75bd7ec3220d245ca9ae3a8e3751d241f952c70623a3e96f693db75a71f3221219d9a9d8bf21aa89ad8ac45760985a18a644ebbc3ccb1e6511b787640ca788a95939f4c3d69b649ea3e4ec0497d6a5223010001	\\xa04747f54f7c0332b532167a81865e2b57f0b406778f2468a252f45a6958b61aa4a9b385d674709b86d5bda8c40299a02f0991b2f1a58838f078f130b8b86502	1681029367000000	1681634167000000	1744706167000000	1839314167000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
58	\\x9d6089448245becc0bca00fad97fb631287fb1f0a028506845f955922af8f6696d07dc68afc6b17250e217f9c81350ea67ce9335ad215a46325d0f821b1482a1	1	0	\\x000000010000000000800003bc7520f79a85203c48e0dbeefa6b8d829c951a90bab06e7ed9dc593826474a7801e1247e0d2a768b4f179cd5de8a1682a2f9c39b891d7163244248d6207d5079893760039baa634086a29c83f1f63180466cd82201ca4d5339958c27e9a026bfe6750af58fafc403940faa8a30dc8e093472603e420fcb5fe8dd02188de2015b010001	\\xb95a8f8eca93c6726ed2b42b524826d9c991e535989d46c21761c9076b2cfab5c87ae0cce8d119904dec4a26931bd6f708c1b32e62929bbe1e667684bd0f190d	1658058367000000	1658663167000000	1721735167000000	1816343167000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
59	\\xa10cad68dc6c088f9beefdbe820b55a30e5cc6e80153013506cc3e1fda002e7e62ed18bfc640a04b75c5f7779dc94f1c6b6a11783688e010658a2054f1ebab36	1	0	\\x000000010000000000800003e1cc4220066c6d6d9c245db05961ad4cf67397aff854fe064c98a779434268f161dd2a630bba39b8eb91bd00a4eb9f81264991d71e4a3cb855ed3cdf545a85204ca2a01e7ccfb9b03ccf80140f0494768ea2028ed30057228344408e2cd384ea7df6150189b2f166c82981717fe66aba34fc7516b1d3da45f8428de2c5a5a40f010001	\\x23a467caed0ca3d3127232918e9ade5bfd2739874f83cff166dbe1edd8f0bada0fad8caa42e174fa29ee7db7d1f5df9b4173f7866595a854da628791651f760b	1658662867000000	1659267667000000	1722339667000000	1816947667000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
60	\\xa330919023de8bfebdde31456c1c05984c9e0581ccda9ff2af2071e76579c92cd2cf3dc465638e09decbf17490e7b9aebf5165237d797dea742ab72b71b6275d	1	0	\\x000000010000000000800003dfe4702afc372996eaa6790c6b73f6893ea5805c204a2da5fa736e9d484d701220bb5c410606831cbb8a7e0e7c472a6c144cc9e074bc256d9749a2db812ca8d7dd6fc82436a71b4f7cc83186e30bd77684762629b6758e1a2fdaa6b00a68c0b524f74fc7bbc4b38334d762b53dcf908d6b6e9799d1c3e8982bd8203a541f8c59010001	\\x39cfe46782cddf3a2e2f4791a12910dfe003461248e2b2cfb61366bac9542794ed43ed19f9dbbe882280f0f065b6d82c138a34f4ca5c29abc05cea4656e65500	1667125867000000	1667730667000000	1730802667000000	1825410667000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
61	\\xa7dcca057cd2b1a127785e37d5c3688d09bed8f503c8723e2039db20a552408893dc1668e9de3b3fbd50f290a180b702b51e2380be347352420808e267aa7bab	1	0	\\x000000010000000000800003b1738d14b51820cf1954da46c20cb2569acf93bae75f927e2f4b4fdd39bd4709df6ac7f3dc6a72dfb7e439e5ac261afcdf58a6cae0c7c61a2c59801bb71ee0423277e8704a832a22aa17dd00666cd920f81e003e785e01bb79be3a3f156a5897f27991b10750482bbca978408f959e907920e996ec19c74553457b58643a191d010001	\\xa38457ce394df871fc4c2792f8b48598b7097166ca6c32a01738d16654970a859ad3da349bfc00e0f2bbf776fad5a3e298c7dd98a3d9c97e3af544d45dff0809	1679215867000000	1679820667000000	1742892667000000	1837500667000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
62	\\xa830e6f37076ff074e57e6c2a287d52c8018acbd8e1286d2c7b89e68e9e67bc4734f4981fe91f1d91f536b31dad16d547350d8e29e254215e66fd1415703196a	1	0	\\x000000010000000000800003be8474ca7bd272994bc9d442be9cd1f0e5ebe7882e6f04b1bef94c80fd917007061150eb06e30671904c581a8ded994e037247192324c801fbe4902aa072ee97fbc3a3b4838d5bdad96813f3ffaecdd323b4472ae66d597939e6070e15ac1290324bc7764cb0df7247b762e278f276a4f70d1f12bd9753ea4e21d278ebe6aedf010001	\\xb197801dd090ad284242dd97d3dc6340c6bde182279049c375fab89767ffd738ad598a62f5d99216a2fe6b6340111687463afe80958952e6b88267b5bbb7250e	1673775367000000	1674380167000000	1737452167000000	1832060167000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
63	\\xaa30f31c44a7ac45267df4452a8d68e8a0817bfac92c4fba6dfa5d2466824527a1ba2749dbebf4a6571fd6bc1c3f0790274ee3f07c3a3bad24d1a7a42abdcc9a	1	0	\\x000000010000000000800003a0621378ea2adc8fa57bfc0d5c54a2d7a45d66a91339158c065109bf730e305816b75f1b96017ca0f916d983c37b362316736301e5a97538f941fcc795e44bdc4e8e9999b2f8b5fdf585c628414db6f3f5395ee8a1ecf3bc05664c374cde7d0cd94e50447f8c3c20f4adb340aeb69d3d21711983f442aa470784b0d4f5480771010001	\\xe8f8c2734f7861ba85886bfe7884d91d49149ed6661b7267b524db03b77c88bdbc5a37727214e12abfa7dab166ce2d84a2319fae20c6af8025f8b182ff83c20b	1662894367000000	1663499167000000	1726571167000000	1821179167000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
64	\\xac6826fd8865e6fd771d29c2403d3f7c8f7be44345eb3c39335476042ac7b7b3928a581cb0b7075e142023127193008a3db4621c9dc91aa56e781006c9b891b8	1	0	\\x000000010000000000800003bd57c161f40171599f92cdacf3f462aecaa6855153b6f203f42ecb4d92bbbc42f80f65930868d64cdeb87fcd22425f692a6444fb474545643b96d03316b382b29c8a30636761a1cbf1459b68a33d3d5881d2a6c275f64cef47743d338d78781766158445e2905dfca3cd959d9b5cc8360117b3e644205de3b943bfc5c2286b7d010001	\\xa3eed78542290760aaa45e6e8a9969573ad0a20ba6f8bc02bf92fe9eb87ecd902697c8acb409a16077095f8f497995accfb340a88340a50e20419c4e52b59103	1673170867000000	1673775667000000	1736847667000000	1831455667000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
65	\\xad0063009fa923c06ac5f284db1a5570d8204b29aa40de107b86ad6b181c1b82e8419084025d45398b767412117d45ef1ca15661001ee6ba15cd0101d8936238	1	0	\\x000000010000000000800003e5b0a7cb86a6a9fd0040abf71b106079d0d92e2e709d89ac1cb7e6888b76b4c6c70e39e51b3cc11bc4d197dcd63176e79857208047a6659c4ce27a10b4a4168597f33adf45d24ae9b600ac59607dccc86c9c06cae43f328aa50d4132eb97ea65ed97632d3912e1ff7c4b703b1f1866d173fb69b7115ef9933a5988c3d374255f010001	\\x37b432123d709aa0af547796e9064471bd45fa0122a0907d79df34c29b8404809159c75b88df3c79cea86135a96e0064e978aacb0d6d17da47558ebb25fa7e02	1670752867000000	1671357667000000	1734429667000000	1829037667000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
66	\\xadd8ea3b9d2768cae70a410ef0b0321383a58505197f28ffefe68821280f4868f41edea18383409714d98193ba4c469714da40e328c072989294dfb45450a39f	1	0	\\x000000010000000000800003b72c9e040d21b6bf6e2b4c01525b81aed5d692db440674ae0e212a9d4b9bd6d6159a6816f95aa98a7cfcf1c344523b9f77bb68f48d0cdfb36e621aec17cf29f4c75378b8ecceb3d9d588a54e436b00e652011d072ccaecdea1d89e6e72a4378a6a5a0a7690f22496f884e875aa4fea40839185e87cf220959a247e55d3c615e7010001	\\xf3494091ffbeb5f48f38cd3c78154741e650667b77ac8d2a109c971006801e359902b29a0ff9d5a2522c6b2fee95ea92e412f39aa70f10922c8d6022ea7da80b	1674984367000000	1675589167000000	1738661167000000	1833269167000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
67	\\xaf48205807b428e8c93fecd4cc54518ffab47f6ddf6f5e7d4b3654726eb1d1edf2a6272faf57724f3b1dc5474e01a86f48618e1c3877a5c6424eb6e2cf3f5975	1	0	\\x000000010000000000800003a9cf43ed433e0f9751ea687d466e6ffb02768b7733faf6aefd96658c043e8e489272fb1e094aae67d91a0997e6e5c030a0737340d2e481031bd8899e30ad7858a7ae8eed6c84a85c09b77b835e4b8829832b5c7bef5164b4b03f4bd078366557d56194b4763c7fe9747e8799702ddffdf0bac401f06d54d5934beeab6cc75b97010001	\\x6678a0c2e6f01287cc8296f0c8e0e163a422372d26c62b50c4d2c09b407b2e302e819917ea888fcd0021886f836371359c919e63cb4427df76b9c24d87161607	1686469867000000	1687074667000000	1750146667000000	1844754667000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
68	\\xb6b03adbf5f7e1edc5c8ac8072ced679bd68557a496c9f8c41b1bb109d6b66f8ee0ba96649ff81ac57d456fb451d4c34c73a26353114663c135b24cdd42b16a6	1	0	\\x000000010000000000800003bfb74ee0b913a681007de9250e6a8cf0e57d65dcae6eb23ce0c2158355e89624f5a03744e1140cd8a501e274891e0fcb9d3882e7c62bac42062871c72e10abfaec282edb681e3ebca9bed9838f6972df3aed46da2520320d61a75400944c7f9b8c4d8755b5c2720a6dcead8d71bef146c589bd09a38f0509088b2c09b8dc91d9010001	\\x99bf806b107b34f69d82e9c327532690b92b9445b497fa34eb012618e59e8278076eadfa86461afb0801b50a2889f8de1bbd064d8f0f9c63ce45b0355cb1d505	1664707867000000	1665312667000000	1728384667000000	1822992667000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
69	\\xbcf8f943ac8078b089cd0a374f778eb1ab06d2ad14d499b1fe8d91f0c80ee1831b4b2fb6ed1ecf184829be2eeb06eb6c8c1cd135d4a6efd6ac85944d479a17b7	1	0	\\x000000010000000000800003a60643d5c05adcbd277e356b5c31346ea58f2e3addf6cc1e6a19cffa56a961047e298b1dc21dc13e25f5556c7114f4bfb19ef0798ba3321fbb2ebff66b69ca1280350215b7b43bfbbf9297e980f228bc69934831b8a4eda1b0f06fadb34318ae59e4013a5c231b6c5385d06ab098503160c7c5e0338f6d01cb983cbf7ca0dc53010001	\\xc80ab30ea9b83c4a7f2d4d6fbd9784b03a18a7133a102ce9edd713c3e44d32ee0f01aa09615125f825681f5a465d2ccd38037eae5e0a2781accdc96740879703	1672566367000000	1673171167000000	1736243167000000	1830851167000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
70	\\xbe78975cfd7150489ea1fcf0e355ca676ea18a065b134c7e452ea1fe9ad60158ce5671c910c7ba1b3fb377789133104e22e317447ebcd4f8a7c2830c176b5bde	1	0	\\x000000010000000000800003d126920b0cd22f0c430e838eb3d8a6ef075bfe90eb9edcb81c2511461966bd60098aa867d4768601e59668fb3fe487ccc04ba7d5ae49fbaacb7313271619d6e8b8d52576a95e77295a08f2a6e85d85272eb23e1806e2070b4951fa0dd6216a0bf45caea8a5885197b1a2eaaf5d2b0a4e598dde8a0418845831c12df8f3187ac9010001	\\x47bf2b59e4fa296c0eb26bbd69c0d13d9cc71fd8748e4261d4f3dec5eb754ef6048750a007b87a8717cb93ab9b3932475eafae4304d13fdb7f2206c5cf59170e	1681633867000000	1682238667000000	1745310667000000	1839918667000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
71	\\xc0fc594253f7813d755b5c070282685a2673c130cef75e010ea150f629a54de68170a8a2966c45b0ef163eb662cb67f2a78484260381d3769f0c8fff701ce8a3	1	0	\\x000000010000000000800003d251ddcd61c1930bae12b0a6348c20832576a1b83474aa4c9cc416a5e61d8b47c5d99610bc63df5a7e791feafb406e810a6379a911b5265738c71a0c40c2a4b720690df3bac7177d90128208741f64eb5a13f39f4f38d560b73627e58ad3037cbf0711f3aab98ef70c54535c75da00a38c1cf2729956de4a05c6cebbb29be629010001	\\xdf2515983b416d9dcdce7d26d0523a1e7efdfbff3d5e44ce77835653bcbd9bec6cb6b021f5e10e22075f38e4c829963609cd40b70203ed0bf564f7e07d22bc02	1670148367000000	1670753167000000	1733825167000000	1828433167000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
72	\\xc320949327fd1b246af423e7594e9187d89cf57a18e495745d050b16256494a224c74a05759fa34ecb0547cbebe6cd02076bad7f74a91f0ba94cf37ab3acd803	1	0	\\x000000010000000000800003e6463e2e05df624083747cad978993ee5b80a5945d9d375d5e9c2668baee3914c444c135d6919cae8c1283bc89a9762d89e81a1dccee9884129e77acb13fabb594ab95142aa64bf9bcb6de461ffc04d4175e6778694aa52d9c1de37da30d2e0476e35285a2b5410bcd5457c1c16fad03a3048b5a12fb2c16b8fdeaafe73d910f010001	\\x7c8227f3cd52eca39263a9552e79da1e28dc895863dec4d092140a14b777ddc8a947593926a740db874c815aeeaf763c648e5970793b514192e69330ab758d0e	1674379867000000	1674984667000000	1738056667000000	1832664667000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
73	\\xc3847e542883304148fa214447a1cf60133c74a74866cb0eab9d9d3a17628a9518bd67b24a6540c37451524d057c887dbe8148a4cf982b2e338fac77b424acc2	1	0	\\x000000010000000000800003beaa1eb6fa68f1db0e297e63108f0e3e4efec4eac910ef6a4848c00d96fb72e9436baa1e9e521e3e17632ece6f897f2e7b1ff2ba055bed9a047d97a83ee1caf7f13c178c6dd2402629d7e239f3ecafa0d3cb5930fc90b5d664819797013cbc43db82e1f06065239ef6e51fa23a867aa610c76c6c3ba1fb1aeb2e8c687fdb0c55010001	\\x2cd0006b5969c047e1eacbd70781d856c3ff486066a03afc282255a81dd7fa402e01226448a326076a182ea8882640192f4e0fea9c042cc58e60542d727c1d07	1667125867000000	1667730667000000	1730802667000000	1825410667000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
74	\\xc3e06c93be91b5c409c47cdd040f6d60c4257bca6ee7856fcd10e073593d205ce6f2810a78dce1af11db4c44ace5f255593617cb362184eebd4f9efcca110be2	1	0	\\x000000010000000000800003d6c42a8b93a606be2950ba3694d3a8356caf748490da38fcca18dd95c6b2e11df91fc61418e5e52d433a0983d7398a994ff208bbf191db371165f5f44e49b3413bfe7690f1c00e87c942f8c0791094dd88706014bf90d66d64f2cc05428588c80db7d2a3266abba617abeb7af2e27bedaa08f9655f0df0ff70e5fa2ae4f4f79f010001	\\x09d6f4e83e905b69a51a7b81faa93067dc6a76eb23dcd13053275c6ff590ddb93c71d676f38effe97430f08590cb9d13d2e263e034154abc7478fffd12129604	1686469867000000	1687074667000000	1750146667000000	1844754667000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
75	\\xc6746d90b5109f301ae63e6f8aad3eef0c8b28a31c672f378b7be3282ecae47a1d52df639e8aff0e8ff8be53759729c3d97f1fa78890c8628427e9fef5eb860f	1	0	\\x000000010000000000800003c806e72c44c848d456d1eda2a61de161b6ddeea408ece5e1701a617ceb6f231930d6aeef0abe23b84d7a65f5a12b61d09c65708d472ec0dd5bc02d6a855e3b1481db503cf5eba7a4e4d2463746ceb36b8d02651b217b48860b0eb7be8fd8b93726535d1c4a1f4ec4cf0ce64792d4bd8f0b6306b91cae5a1dd57e0e324df8d931010001	\\x811ac06754698afa0c2d3887982be4dbf3baacd154d11b7fbb6b2e1074b93a8137a97ac15cf70f146bdb9d475bac877913a34865ab7b93cb3324fd7947778d08	1664707867000000	1665312667000000	1728384667000000	1822992667000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
76	\\xc78cad1641fb646c8c0504173094f72a0b15d0834675b04d9503fc335056e7477450e4d9504ad5839d3595327d3182c30f6300856441d8ccb55fbaaaec575456	1	0	\\x000000010000000000800003b7894a5395f70ffba15569c8508ebe90e94dd19b70bdf17bdb695770aa2b5c1c609c0eccc87f3a2fef43b3840402e1074e11836fbea8084f147aa05b4a69551e3db85ac8683710e19181c73ace1cd0ac4b95629bf39d22452c68d56b10efd427fa2d79b66cb0c7359f8a135edec4803fc275629a70facab153e24d15110821db010001	\\x2f1f760a4ba0e915c86c6d07583690f5dc0cd21742f1496cf7ac2e98cf00c1e2f60e503362ea2e468e6bba320e6ba0e125967c9bccd91e4ce5f6f3b875308c00	1674984367000000	1675589167000000	1738661167000000	1833269167000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
77	\\xcb48c3ab7c81708aaa7f050e94c10bd794a213730ae9599c2786235378c4214f82cec647f68d6dbc5b12aa1530f5eb70b1911803616ba9846e7645570577fbde	1	0	\\x000000010000000000800003f2634c84e63e929ebc3628ef65c92d6082a54664eec805964d1108af22d82178c28dc58a7373baa667074e0047a022ff067251e099e829baa8a6c03e6511e61316cf7845ba5751bdf5a91d682a568047093068871db3ceb8ac30755553ec1bfd1c9037605e37a6e93bec5436f63413c326b7b377a73c07513802382ea949f8b9010001	\\x5dfb8810029d47fa9cf4b0e470e0f0ae6ac68a9b6ae3ed67d5265dcec2bb54f3414f65d5e61e2c988cdc41df7433c48740111eea57df2b6b381da73144eb8c08	1663498867000000	1664103667000000	1727175667000000	1821783667000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
78	\\xcde4f0dc2640f6a6148c7b5cccc1596b14ce9d89e646e3138750356086427e7ac56e8bf5d7f2b4cb3617a748fe5ff1ba4822509e42d8f52559769c2c82903d3f	1	0	\\x000000010000000000800003c0e0d74a7eb35c9acca3158c4bf14b139e97a84db01dacb4e54cde1c74528f67e0d03059a4f8ca03a033b37c93e9a03eff2bd595ac1e5106d953312c74b2941479848256d64b30220d8fd6a0815fa8c270f443b91d09bfe72fe381364810d95e9f9c327e6e145db43751425a77912bcf6673f069ae35fb795fc282d420c2be4b010001	\\x018c30db2226bcb079c170d3a724aa89fb431b17cef51250e4b1dc29053cb0a42d73e9bfa3472c3a018021ad35047955f7fd8619f1b0850d2309c2520c13e004	1658662867000000	1659267667000000	1722339667000000	1816947667000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
79	\\xd1d8f1e8ea84cced4be7a536471c28f2508e1836f006a769edbdd12a644cae7d4148e848811d9caf1affeec80b3bff89bf8ece91746e540b652017978edb779a	1	0	\\x000000010000000000800003beeb2c2b7d75749a04eef78eb88a2de5b2bc490a5296a375da6e5a523c3cf4ff36d8ba70b1da38c1f33d41e328631bd66ec3ef7017f2eac9457c48acfcf45376b50a00feba5655f9e420627d498f587603e26902bf6d7199a190b3e3c6d3f9e1a6517c89385b9267a60f78a9eb35368260d20535c3f893a5202d39d3046634cb010001	\\x30ea78ffd7631f64226968ff257fd6fd3085ec3ea698aa96d14b0d92f90fff322b5f5e8e3c2129ebaf00c0f37ed81f3c82bfca39599512a7a679cd4afcb28a09	1659267367000000	1659872167000000	1722944167000000	1817552167000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
80	\\xd26c6d65f8126323be5c6769a9d6ab676abc37bd0483e93908d3291a46a9b767b15857e83a85ba0f239c9488dd1249dc413f960b113d436c13a24c17a78f6807	1	0	\\x000000010000000000800003ee899309a2291bb1241ba9297a4912dbbed5ca718ae7c6b8882ec04ae91d8c12b179de3539f849a28082bc71a3929701803ae69f7c14e877d77c30e97534a6ce09dff706b4a0ce94725ae2af7de3c3b2d03753961d4fb9f718eff9b22ce6e0d174d7500b5828cb197aecdb63f94c905d7a85023068ed6899e26a205bcf01a527010001	\\x86d09e9c4151c5979cf83ad3bd4a69f9d29c5741a272f6a77d07a8b44e594cc8e6d922a9c59120d13c38db75745bd385ee4780b63b5d707cfbc3253b8f98b108	1675588867000000	1676193667000000	1739265667000000	1833873667000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
81	\\xd3dc16df7e84df873d34a160118fb6aabe53e312ae4e33665679d340e6780ad72764f99b4a3dcdc1729d80f2235a1bf6c2bc5cdde559dfe54e17855114c00c40	1	0	\\x0000000100000000008000039de5d3316aea05bc572e6563a806731de32399288c3fc00cee1fdde013fe90b59acaaf3f1ff144586282e289b6e4617ae4688063f35957efdedaea76206ed9a31abcde9048fc2693f48e634e23b5baafb533f7a22884324f7433bff93ab62496e0a57527921eaf9a34805ef906f77a3668b0fe1408275043aa8b55e575eb7ec5010001	\\x837b24fa6613d795adedb1ecf5c05b68ffd4285d433e62493829e23dbe20e4b7be1d9db4a279d5c894f4b22cde48870ca53b4f8536e5074d425e1a72fe351103	1687074367000000	1687679167000000	1750751167000000	1845359167000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
82	\\xd4ccebd1478fadbb6fd12087e17f6e10d1f960163b91a8ef28403b5a007043edfea51f6ed74f56f1fbd49f6c18512854816f7940d00a086452523310c5e13127	1	0	\\x000000010000000000800003bef75ba75abfa84bf98a82b9fbf825a447e98052c3848a4d5d657156b4e845d4f16b28580e0708500222799fdc0e484596bb0fa37088c40ea3843b0fb203332f0adb43f51ce0896ca78129fd14a02c1ab36764250ab4d5ba06714680b9f5fffa169e26dd0ef6f49e285ae786aa250d3f770f133da10f688cedef6d092c16133b010001	\\x6046f0b2cf42d03523d84fdc5326487f14193badce28c0e433c88cc8c8bda41d0cc106b5bbdfaf2a68d1d8d36664e44a80f7b77271866334d2dc905ef087250a	1660476367000000	1661081167000000	1724153167000000	1818761167000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
83	\\xd5f4cbf8ccffcb759ab146a3486a2dc2c0be276076f94a82cae9f1db9a1110ae20e8008f54d2d29907c57e652a64ee7e1e3255c3209b00d5cbf3d76d1bb19674	1	0	\\x0000000100000000008000039cb5c90ccc3aa2b8b9d2f3c89f728d5738cba31f2039c7b1b090910b9ac705663e9152c539757e05153eb444c2574f0380886ae16f633e91f1ab060b4d38aca657429854d98829711ee171a3b9b8764e74f5d6d8a4ed4443598abb1372fa2fa3a57b5ed33a3155b97683c60e48267fc63f94dae1eb4edbcce936171ee5c80981010001	\\x8237db8edc65473ffb962a9d7e35adac4cb3024024a0992013ec7c6c82bde3439d2f3e3e778ee5c0ceeddc05e9734fed084f736f63cfdbdb8766c41ad38b7b09	1657453867000000	1658058667000000	1721130667000000	1815738667000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
84	\\xd77c639bc3c0956a34c4f26a96176a8c97643bf1b0a0382fb9cf122f218193727a5e5456ec3afcefa41fc0e257f1bb984e0ecd3e816a90b6a6510b5a07860679	1	0	\\x000000010000000000800003b8255e7f4fcb0336bbbb8f8e4ee8dab40556de1aaff20d8d2915be3f0908aaeee0ec85284e530bf9b0ad05940d3a51a989cc5a025c1e39356028a5c5f31d9ae26bb61c80bc1f3f53480388ec4a97170f8dfd684828eeac02575cd3c1f5b384a08124bc42e37394b80bc942e29015c217a458584f2a70c160503bd525479d9305010001	\\x68bb8c66c1a917b534054f0bb2bc0acc2a137510030fa68a7d1c456bed7c6a9c452b2ead5275183c8c686c0be06833f3e5a41079bc8997a2ea1904e2e594ea09	1656849367000000	1657454167000000	1720526167000000	1815134167000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
85	\\xda2c51b214b00ebf6092d88a1fad20597878cee283a5830d237e9deb4c2af3fded5d70c42df78826e4808f56208614a4c5d70f1dd915b7f5afacd59b95debba7	1	0	\\x000000010000000000800003bb3c3c22ce064365f36f8f65e0586db5dc808a8ad10e2f83aa08df3247ccb43b17f77e2196052a850db5c4a88b788e5c237d27960c0ea0eb77f118697a8445e2d6c80702f476481170d595f1b714dc057939ea1fc7fe348af24b81a45ef1cfd1b21f205580d9990fe69b802bddc23b672b7090a8fe1e89c16effb74789481afd010001	\\x41c193556c00af80b04a8f2dfb8e74948094ce017d9187c25104635bf92a5974a2902f9c13044bd19a9c0ba182414f1bb4c95be48c161a542fa86f185932600a	1665916867000000	1666521667000000	1729593667000000	1824201667000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
86	\\xdb48fa149c6a0eaf5f985d6db0c5dbef9788f6fe113f0c91f168256dcbf60f966af6df2a620ffd8d3d59fcad2b8395f9ce61f38de0233e18bb10d0f17df23056	1	0	\\x000000010000000000800003c3619dd0deb1c41f0c622bac9d023eaf872cbdfe544d3c60d0380cae7dbf02cb0280096114bb5e0468b01469de9a35e0778189e57d5b1cf0c2abe7458cfee48f12d4121512ada44085c176c52f0c58d56290d75b915be27e78a2c6e25a9e044700f3651f74dea1b991f517b191bd1daf5aeecfabf33b9e67ec4a286226e99143010001	\\xfda40c4260ee02e5fa82086e2d130f00c8c7702b56c6d23b03d0e5e813845c14b92414099ca584ba4d3521227d9325707a9d5e35058949d1f70ca4d32359ab0f	1682842867000000	1683447667000000	1746519667000000	1841127667000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
87	\\xdd1c891c9cf2ebf4336aec442e2ac8a8c8f3aae17bae573e82fdef7c145121f0950f5abd59454373765a99df7bd504ccffed3101ca6131af60de47d6a0c1c45b	1	0	\\x000000010000000000800003ce40790239b3c86b1233b32adcecd491df31c6a951e118e9c4fc9eb4260da8b5c2a5ce0ee48b2816a454452720bafe25c27bc620e12a9656ea3a1acc14440bcda4671deab877e705d5e87ae3cb30c43a46822fd84f7a2c1347b87260f1a40c71391a70550bcd18a1430dea170a1d351a6c707a621e4925d1b6ad31f4e497b02b010001	\\xcca051f84a156d3d2cdbc7028295d749ddc997bb911640811cfc0c3cfba17583ebd58d0e82007dd4504102a87c66f44985ac463bd15bf0bda0c868c7ec3d8b05	1662289867000000	1662894667000000	1725966667000000	1820574667000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
88	\\xe46ca06511d01c0a726d792ddd9f66757a78069ce37afdb35e50219c16262a66e9c37fd5bda23680bd21556569d718c585c3f71548cd6e316e74dccdf68936ac	1	0	\\x000000010000000000800003b94cf05db590e30c86ec1d6654c7f6c56baef8442d6695439e6d0df25dc8fc7a203c1075281160bf2c869ebf052347f56c84ec965d8776798b512530c77867a1b3e772a85f527695856438284601916644d741757895875f166d4b1c7404611af2b29973dfb77e6e024ebd5c33c4728b50b96e3b63fab502aa4bb3a849e0c229010001	\\x21d6632fde8bbbde9f401908762b2e37e3dfb87000131779b304ee4b06ebcca85c234d114e5b5f7b3a31708ad69cdf580b68b0ef71dd91ec246ab09b04958c05	1659267367000000	1659872167000000	1722944167000000	1817552167000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
89	\\xeb608624536e096583c1d70a151207da55db264fd2402c7fc7df18e132f73b07232c5fe902b04cbb000d5fc27e829282692f01557d3adaa7f64f39c5af527e97	1	0	\\x000000010000000000800003c14b806b4131a6cfa16664b98d89c28fdbda25fefe12669098182a0f567a86fdefc4d8b8e573c8f6e74bc57d99204d21d0626d9e2fffb75307d185744796f3c3086448c6b00abf1b480c0dd6d28dadb29a6acb0ba6eebd500745fcf9ea1f3d19a1c35655d598c96cdbb2a78722584103efcb7c67d7889cbc316330a6630dcd8b010001	\\x1791aadf9bfe3f7817b6a08f1e05faa7cfec36cfe75100ee4e458847b811fa2aa7eb2a3f547cc83252ed4e3303559f5e40fedb1f5c429f7245cbde69addd340c	1656244867000000	1656849667000000	1719921667000000	1814529667000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
90	\\xecccf735c1f4f0c7db00c2b79cc397bc3b6b9c6f92e3f66ada24b5e5c52762059759fbdaf020c925838013f4855a48a40297b6519bdf0fa67c82802ef3b01a37	1	0	\\x000000010000000000800003a4b4d10ba6ab4a5e241525252ef4adcced7da68d88297d0eb77930e57f24c991a32de4d5e05d27cd9f7f3392df09e59c3e3b2bdacc3fdc5beb6b4d114882175f3b0fbc7352160f0b4c1015066a22bf4e29c30f14fb7a33df711ef210a94444930ac90e522c14380d855ea6e7429962b8e5bf69353e40a25391a5ebd2294f502d010001	\\xf03ca80394f5cba304a88c9ca7899b12fd5fd85f5be1d70a15e996523f4b4c84c2c2ddc3f8f0e0dd695ff0ce551e052e29eb7be55eb8a002af2eed4c9403d40d	1678611367000000	1679216167000000	1742288167000000	1836896167000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
91	\\xf1bcfa8b1357c8ecc586c70d87b89514d75bfcdbea910c9fcbf70b1f1859115dd89170f447ee89ba417ffc622b488c52ed3e2ed1d20bef7bfcf32b407f5d6095	1	0	\\x000000010000000000800003e1464e868ffc73b8a035517708c1995a4a2aac3dbddf616d909bfde027977b5f4439dba50766ace8375f049c5a075d143eeb03fabb4c9853afc23162273e27e989ca0b7e87f2bdfb44a64b89ba5791ee44952b4d21fac27ac43c6df28630af45c0a998c6e5398ae3dfd048c064b2b247739ba8136bd9dc7338537f994c88b5f7010001	\\x39607490024e177ec311e6f65cbba2707ce1a6824259a6f1e0b80bafbb9dd1e63a42379c2f14509c1e2705f3809364da6ca42f3d651b4127aaed7c2ffbb05108	1668939367000000	1669544167000000	1732616167000000	1827224167000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
92	\\xf3a04272043ec72b256dca7b188f1fcaf03ed832396466ff851ad475130351e7b5afeee0ef206f91a30cf151307faddcb59c626463c66d5178f01e3afa717054	1	0	\\x000000010000000000800003bd7ece2e5b1e7395022ce0709d7a9ff41bada5e4f5acd8b2de6847ac86b9cfecd9667f8311bd88832279ed860d569d4176b6bba39bc73ac72e7645355612ae6c73cebd3e8859f40b377980c0d0efc58ce0d1ff5e971c430f0ed1773f44f6d75ed12a7aa80f4cf815f1573d3841ffd49a3ec7b4ab1bc5cba9f6da1d3bf415dccf010001	\\xb387ce9f9bc43d46fb1ab77d3c75e793fc2ee404d22a620eba83eae45a809f2b8d3ee531d7b79b77adb0dc3f954f0f6e992a1771e73fcc91fb7d732f8242bf03	1668939367000000	1669544167000000	1732616167000000	1827224167000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
93	\\xf6787c832b76413e96eba859af3c9205e8ab95502224c8ba84f9d18a790045766c52652f514b1f20038bd69354e8efa89bba44042bf4c0979477aa483c0c59c0	1	0	\\x000000010000000000800003cff0ba339bd06972bd30312ff01a6fde7590dcd262453bc474a1a6cb8e5b5db4cd4d8ae4b6fe87fbd61de2e89b2ca94ebfd6b4062470bc787c0db2478138ab2fb8d6e67645342f61281222ab2cd904000bd110582286801c5f80a2ba6db6e4bb114970f57b2b4028e200d62b4f9c0b88eacb31e06be31170d16f65c433c31e63010001	\\x29e8c8f1e456e8fada8c47de5db53c34e3b92a9290f95b1da2847cf889c9f5eb7c6178b18bc5a2f81c2b2a5b6e2ac47a056fa3a279998f28075882a02a043007	1673775367000000	1674380167000000	1737452167000000	1832060167000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
94	\\xf66070910751558e747f06fd9bb7a36249f493f8b3e645aaaa1640df2e9a61da851635b76fce5f5fb94d11d92174a393e0a6841fde05076a0347e6bf1a011787	1	0	\\x0000000100000000008000039c9af4c04321448b6ac1e116e9f74db91c506d10cce25504bee17ba235b437e481e2723ad6ac3ed4b253e30d277d6ec376b60ff46fd182ca5f039c1e16301c08ba84d2707afcbe49391e98f37558a3251793eefbc34e17a45316a0e2a006a7fa68e995dc41781237708935753544103c80a70267e990df3b3e5de07f1cd8600d010001	\\x4ffdaec8236b6449521861a8d25dfa94b9330abc962d7d1683eb9b90104ea2e69197fdcd91546e4a9e57befa539e7a2d44ad56f1fd974a1ca90a92bbab9ad108	1668939367000000	1669544167000000	1732616167000000	1827224167000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
95	\\xf73c97b03952ad04c8d5f9c5516c92a53831e661965a052b1e36c99724fd266c8093ff012a4d596e068b6eda9f26234f8aa908b58484d8239579c26b1c795865	1	0	\\x000000010000000000800003c6c752ee0af15545a150a05634d213ed7ce1175695c1c40951d3b829b4dbad8b7cb058843c594ab4785172e3e5c0f31e44878c48701af2e3129f83df133817f146b29fb7b3ef59cbd916f12872bca36425d328e2ec034c1a9574d8bb9fdd8505facc1069ab40a2f1e2c51682a0c8ef141ae3d6c53d995c6d173f333bb1f593a9010001	\\x844fa8f3a102db60152f08d12f546505c9b41e03edf513f14c69f85594c55eab9b3f4a953697b324c87855a542f4ca9ff7ea81b3a694094fcad2181d0366d304	1678006867000000	1678611667000000	1741683667000000	1836291667000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
96	\\xf95cc28f415405392edc61016d49a025272792b53eaafd3bead60b0a6461c5f3d4fe54d65b6f0d8181b5eab4ea23b3a4648d591d5f1a2a059d75f7d3de06d473	1	0	\\x000000010000000000800003b725ef576b44eb3b44e4037d821ca5b4470ea0bf50933af423d62dc70f36986f731f0fefe40cb16cbe2ae3bd33b03a2a9edda2411f28b981c125f12b660d72c79b451a4d97b7bb57e3ce864e7fd66f45a8342d39f36969dd7c6b774e3ea4873b0497c0db18f92b7f83a4e5b9e181ab382e2f5a551a6d45007240d3e8a1e9b68d010001	\\x7bdf1c427d3cfd0ee176f7f2ee98b29dc543d8881c23f18935e601c858b98eca97cc73e02d42f14eaaa0ccbe36c1463a77673536ec02e52622bf84884adade01	1687074367000000	1687679167000000	1750751167000000	1845359167000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
97	\\xf994b40d7b534dc23a041aaf50d12c2bf824a35702c939fa38a92ea65d603180dd9e5d4a10b157a12691a6f07fc09b5cea4768ecb0631adb0cd8aaa9a4c09dd3	1	0	\\x000000010000000000800003b1ba431aa63ba0869ce97f57fb0a1f338ad9e3443a672682e4d4cae528ce35ba6dffe5c0d15aa5dd6e559a4d760c3af5bd22f40645ba314aa73dcf79866ef5486d11a1cf7897044d3c5c23e92083f22fa52c7ba86ab4f0ff31028960adc6fade2c420a79e2a6aaa63a823e8daa75c734e202fc40c2ae2367ff4690337632a2e5010001	\\x8d609371aff8bebc4837f52b9c9738c5b659bfd6bbdf90c3d717c01c90a731d7cb3432286c634ed8239e1bc360c77e9973af4a03cec0dfeb3c7a194a3999b501	1684051867000000	1684656667000000	1747728667000000	1842336667000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
98	\\xfaac60d18d631569ff0cd9f6135d4aee99ea605145204f27383c5fd0417a731cc840b9de069aaaafd5da26f5a568a38703108ce6360fdaaa7d9501be2436e2e2	1	0	\\x000000010000000000800003c45501be7eade1872bb6585c703d5587d2e2c1190132c5576dea6aba2614669bbb9130725c3c8667ce01ddad93bc4abc27524bfd8d941908046b3748e19cda9c2b37507a3cc0a2d7fb7f2afcef95987c5b380373411cc18dbd5164c2a975d0df206a931fd73fb8f5e754e1d357a8d9209c73e50a2acc2717f4e3edd11f68ce0d010001	\\x27e93d631064b297f21b0ff63d5ef488f95d97ede3381062447a9094ba3445b18e171c2b1658e4297f27eebe5692e5b47e7bee76d4dfdfaa59618cf1554d5801	1685865367000000	1686470167000000	1749542167000000	1844150167000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
99	\\xfdbc63ac73f31fd9b74dea0cf4f5dd98f597d051a411afb110350b435019c3190a3ff0b0ce6af652df1383b25d070f3e133a88665aaad9e8a6428f943369a045	1	0	\\x000000010000000000800003cde5f1fec3f1fb315a9b5eddc051edd8b63d6114998789a310c3ca3c1465c4d15ea80e8d8d7fc3a5e045fabb8768e6e14f2069b9d3a10db0e0adf5f4aa4ae12ca6941966633b6e73d8cac574fb3ba5d23caa486c8790ad71855133c3717011f4058f6e169db328b0829f4dce5b3907f1a080316870f357490854690ceeb7849d010001	\\xb8625cf7b91b47371870463f7689e1ef021070ca3660f1056fc15d0cf40189ac7ac8763b6e35be99772f9e99b4c3782f4612790b102deaa5419ee5bf02fc6f0b	1659267367000000	1659872167000000	1722944167000000	1817552167000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
100	\\x05e9be39b480f6fe3f66da4739d39c663123b33fc786a6c2e8b9f3c6ef91d8253327f5f9d725e46b9ed64b244117a42cfa636cc5063576ac5d05c36c1bd72735	1	0	\\x000000010000000000800003b1faec6018cab4675b36446c8a252572e7a98c08d616a2306513a3aab8181f44937f08bea2f96683276108babe08526355fc0ac22fab6e09ec53c4fa58c458aa170bf013dcdadfacea711153be2178afc02c007615f53ceb9c3fc8cc51e93701e02190819fc063269db5c4584caca8a9f8208065471ee033845ffc7d74ac4ec9010001	\\xe6809316bb703b224697353d87c2957f16a34e0f1b5ea670d7d7c28b1fe769bc4c102690337a5d376954730a9b6963c5db53b8bd59de9d603cf0d58187b6e20e	1670752867000000	1671357667000000	1734429667000000	1829037667000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
101	\\x0669e383d2538048fc4302b8eb1a2cdb991db9fbe01c6f1207cfe3b0def6b8278d47a494ba16e6ea92dd895fa6bfd1c8075703084e007315e402423a5ed5b3d4	1	0	\\x000000010000000000800003d992ceed05b5962322795dda08747817e9acb8b59ea879d3c46d37f5c502972d2a9527099c3b4b1270d151ab5d7a3e04ec7cb575b12850d6d9a25986ce9388159333df9da876e584da6f43c0fef4460b872c51b320be7799601a52de834c6e5759220d52e0e59aeed56f18327c7b7b62f757524133ee8529c40f6fc059afec4f010001	\\x9fef6af26716e125239bcc0ba450cdd43615bc48762550a9f421b496832b729c57b49ef7e08e448d2ca1e73709629deda51e82d16b7c5094ec62111db081d10c	1676797867000000	1677402667000000	1740474667000000	1835082667000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
102	\\x06d9a1e986881d186ce3a1232b9c6c11ab6f4f806c348d24489226ceff8c97a73cf3f2a09f5579d408f6a1047d25a5eaa8a8c3bf2fcce37b1cdf6c38253ea2da	1	0	\\x000000010000000000800003d405bb273afa1844c92539647863850f745e405cf1ddbd31520de123c6af1b5973cab0ed6a327a8270c7de4d899d929da63205325c0c5f2231b19bead168af20cc0a0e8c616a086049c26cafedf022f24abfed1db90fca2a7891d52a825a70cbcebc8a35ccba08fd56f81430f132f43cbb76c0e3495b3f56cdea9dbc1fc30883010001	\\x8572a37cbafbd09ec31112721a694950336b374c5a11ae5e28da456e7c3e483e730606f12b943f9cb22ec83d3b308f3c91f69e0ee2264d6809eed8b20010ec06	1683447367000000	1684052167000000	1747124167000000	1841732167000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
103	\\x0bf9979a814682cfd3ba04a4299489ad6565c289a38612e5cfbb33c10165cc6b3f1245a20b62c25afe7a1b9b53e05ba8287744dfcd63044809c7da89bb70a308	1	0	\\x000000010000000000800003c6bec0e5345050ba6387eeabba7d0d7aabdbcae12f522affb7dc5ca4a23154f9ee0e285d1d573af1872f84ce3922a418ee7e043cfe9ae76c50228ebeab51e90406f28782754d873ce04b1e53a7d5164503ad75883ddaea89fc8a98d287887e0163c416fca4287b423494a220ac990bb84e6b6c49317fb39aba69a43de7da79f1010001	\\x1fe66b7299e2379793c5cd996b45d07a861f58b4ef65551cd10f96d81351402d42644de0dddc43e0a075285920abd3fa4edf96ec3b1252d75d621cb05b5cdb0c	1682842867000000	1683447667000000	1746519667000000	1841127667000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
104	\\x0c19e3f0bb0f3008f28c4eedbe6ea1fefe3e28411b751a180edac9082fcb0444eeacc0562f9cad73c5a40b7599e227b058f6eff0b7fc6fa6d56615a5d7d7d1fe	1	0	\\x000000010000000000800003e9ee9def153e3c495fe87a99f86aa3449c4e783119e118d06213018514f3340024143440afd025842406c6fee70d5d4d2a4da6f31ee4504605efce8fb4e12762814ac4130cc67858a4bf143818e3be9ada8711cde8843b14da78e4c48742f92328aa21a3c19826cf0c115ebe78b61fc27646093821b9d417f3cde7d32a50f98b010001	\\xbed2d7e08b61106fa51e8f1aa1e3c1c635cbe3f0bfa27e7ce54ab1df9cc1ec21144657516a027536f1ad18f63b84c785ec63d9af3e884ccb2992277c857e1802	1674379867000000	1674984667000000	1738056667000000	1832664667000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
105	\\x1141988904b6dc7990aabbe036e0542d356c6715c115e51f28325802380fd52e1eaeeb2ab47653ed0085c188555806c325179fdfa393049c2da5df2a2985b70e	1	0	\\x000000010000000000800003bddda2500342b19ebda17ea1adff3a1cefc85b251a7ef08f4fc7df4e1176519e551cb1de43e25acd62189797da9b440737746eef1b09d3957804d2467c3cdc2d9a25453e9f288deee603e5ef15efca79323a0c4d9764666883ba5803a9016a9be5e0d668c6a7d0c92edd6228969d6cfa3852c929dd43088301f3f06c1cd0aa11010001	\\xe5f8e5ea1664a42a67ccd7353d0565044826b21cc668a8a2c8cc202b42298f9635606465358e7c9a7753ccfb7fbdb959b3c40dd538e9145c949d31e2f5522803	1665312367000000	1665917167000000	1728989167000000	1823597167000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
106	\\x140da9fcbd7448468a55cfe1385ec75405085784e7aa55a0bc1a16c164dfed7e8252abf85c35fcea873b2fb645796ffb54d37e1755c11acb6c916e9fd3fc93e9	1	0	\\x000000010000000000800003ae76a07644311827aa55e7e5696233bc5121d07376a73264bbe11c03d3fba23ba6fd5a5240e74025d2afa72b2228966a81dfc3055d671bac652720ff544f248d18b039191d2992b66019392de46bb0c92ed4e3514b1a3340a2db9f1e1d9c15529c51603a3658549783d7b0e0b474e823177b62e6edc4cf168167bcbe810c77a3010001	\\xa54fdd3eb62d90bc21abcca33acf8034de4c642a905d6f8cc0fd0ca9982942ff93386c6ccab0385c137c1d5f7fa3a90ea6bb0cfb29702ea7ec3e0d30d6e34b08	1663498867000000	1664103667000000	1727175667000000	1821783667000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
107	\\x18e9adb45d82f4ae2a82e6bcd6a24ef863442f77eefbc13edf96d6186cbc82ea4ffb68a1900d6ab952a74d4cb1bf3935093c307e5b72e096e39674d7221b0e49	1	0	\\x000000010000000000800003bb1ce02e07f94a2d0f0637e2382b4345bb7d294bd807051912467d92e7993395dbcd95e31d571899bea2c8fd163602ecab3b6220dc7c41d6ca609582255c93025778aed5ce7a687b538312edd4075aa1d020b52df96bd1a4ea3fa2401ce561b505fef9b8cc46dd31871b198cd8a0af42c38d107e58f3b15bd77d34e71eaf501f010001	\\xac99e604ec2a1b1e325ab1782ebd1ecb161c4530546a2cba8de4a288c16ae4c06bf9ada4dd599f6dcfc157e7d36fd67ab1475b12d99f7e32f86b853973f85b03	1658662867000000	1659267667000000	1722339667000000	1816947667000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
108	\\x1ae13664d2dc4a072b7f21e8c34c1ea651c683809b67a82623983357e364dc252d3dc394348e37be17da539799db3219fe1049f8f1c01a8f2befe20c147517c1	1	0	\\x000000010000000000800003a3887b72dffc93c79c11b5e7df81a0e38e2911f902e414144489d49626160cb0e8329da649d4e78f9728bcb3476857860e55361d2e7dd770406e7312f1d7e6983657ead1dd13f8d19e95571b2d8eb0a758a50c7b095fb19a34ba60658ac3e149f5a254c18ee6369a69ac1593be1ea638647ddc76df369be1a38c45cfd37a7a77010001	\\xbe83c4967ed97d7e38024085f0fdda551f8d5c6e78bfb428f51e2159b47be71c93b29d19ce3882463395b2d3fc4a4afaba637c49897e36dfa2e0ea96171ef00e	1668939367000000	1669544167000000	1732616167000000	1827224167000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
109	\\x1bf12c3787f67266aa5cfd3037f9d69e327968284f272ae03d9202583488893e6b8de2eeca7b9131ac0c32cd91dc82354e7e7d13fcba52f5dd3d0ab1a28ed7ef	1	0	\\x000000010000000000800003d455920cc4ed37589a3193169a9ee74e9352c30067e5759dd885215f134af8e3720f15afb72e78dc19185cd7a1aa3b1cb5cc5f948e7c7e68344915f1cb93fd3288b65563d8e702da4ba39c9837d4e09fa090001b9bc9d7690eead8be5274354ea2567133ca8d04eeaed9117c954000de448dcbbfd54281635871cbef29034d81010001	\\x640c6d1a039f5ca39e7373377ae68712da84fb96550068ee33168469da040b6cb978052630e155f7b15aa1528b73434d51b0d5fc805e252920f43548f9c01902	1673775367000000	1674380167000000	1737452167000000	1832060167000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
110	\\x1e85d10c35aff8fad4eb1b4edcf63390187825e9905dd2459e905fc640b17d7bb5326cc7e8ea3a3abd394619a8c5862e16ff5c41244bdabea919b827f7c733ed	1	0	\\x000000010000000000800003e881dfc102dff531a86ebf704625246c71b8dc8a1729226e4c853286d9e0a003e66cf2d09c337b19cc291930920b58cda50407dd2a8e6d8d26da591e7876bf768fd23fcaa86b57963a1095fa5eda9cf8a1d4cf760c01089088cda704d6e9bc4b45e67a2d9bd65174b80fab096ec4d5bea69e1b6299dbd3dbb66c939d96c082ab010001	\\x6fd0bde88c84fe939ef36aa62b34cb5d84307b1f035a992b768025a4472063752e99e66fc207ef919fcdac9021f9803c115f363e33d0d5f1dd6b04c3f1104606	1687074367000000	1687679167000000	1750751167000000	1845359167000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
111	\\x1ecdeb7b18c63ef9effd76096abc39994045245482239550ef089fa9c9efab26e7cf4d5573a054bfcc0114aab7199d91c0e7f0f11662bb4747c38df9fc080946	1	0	\\x000000010000000000800003cc0cd1cacc269222fe722849f665dab4579c2423a9d8e2f97f68dc11a986d9b5883d4d48e6e9c2567bc5b9d5c2796665b172cb43324b87e71c976d8a3d09a1239eeffc515028d88f5840c8b99793c855c4874f4d6f147a8f374f6345aa51182e3ad54bb13a96b52c13c0cc5fceb952860a240dc0c70a52d961518dead5bf2b2d010001	\\x6c36748ba90b30fca32c56f8183de86aeeccb1c03c3cc1f155bfa5cb9f686dfab2e1c1ee14015f9e4c8f013f4e7979aae15cc399e95b1566e97699572c1c6c0d	1669543867000000	1670148667000000	1733220667000000	1827828667000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
112	\\x1f05d94db73cdb7f1b8510699ce3ff0d860b6f95d1b0f225df2ab16254d50842e02372a2c1c6533e1d9169ea09ae2da258f2580652d4cbc97629287d83860ea0	1	0	\\x000000010000000000800003cbbee2565e13c293023d333b331769a1873534f72f4e0cda41fb1914b97cd471b9752bf160eb6c5fa266656a5a624b8a629547712fb0ab80071f15fdfaa7d51c769604fa72b3b03dec691663bd8ae1a4a86848a79d33860ff35cf4cc8994733f81334af0199e34b12bfeed41252507e8b6660c98d742f062d6baac96b21548b7010001	\\x99fde4d9b339acbe9a78d0a6e6165ea3dba7af69a1e80ced9a3c640a2d531934e41d985e3474b37a34776abb4be9efcc14e634e5d979e141ec2919b7658b2903	1673170867000000	1673775667000000	1736847667000000	1831455667000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
113	\\x2099201e295721ef90ea189d01be2ac94f716a865aba5310affe36bc8b943a2ab97b5ba7e7c951f9a40bd9e28a6674e56e4bb2fd96b6ee7d83468a5c89128f54	1	0	\\x000000010000000000800003ea2b1c892bd02131e8a03b2addcf4a7962922d313ec0c5e2f0860459b8183cd3e3c200c8a09b9b7a27e6038f1c8962d4cf241e84ce5f9824b7a39fee58d34d93fec172cc32233a32793512ec859654c0f656e8c01c2d9155d02a23b4a6e9d38b017086613e6990c346d6316d45c49ac4d9d99a64d75ff473128f3ff435666401010001	\\xe2dbcb3834541f57e390443eaac048023e8036aa2dfe141975dbfde476f4da00c360b6646853826509b27b24c303b64e9a6ab970fb9b4bf0308ee513b1ff110a	1656849367000000	1657454167000000	1720526167000000	1815134167000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
114	\\x21f50b1515b4066a72d37351a2d747229c410c208ba54c4861e55625993668c9475aa281a6eb02a4ecc7b780e49bc5dc8bd6eabea8bb11121c7936b2ef914e18	1	0	\\x000000010000000000800003f1e4c937963eeec67beccefe213721be14fecf12217a30b62706ca68c2a1ae1d573fbbe9f07258a59aba5ebd820c62e0a54dab007b8c99b47b1c000218e14e53485aedbb89634ca6d2aa9bf87e34646ab47fce08ccd5ce02e4cfb85b2de4127b76da57073e07513b2f2ad70d561a8f43b145702eb2c39d0a478c16a1dce0dbb5010001	\\xd4563165a9169baddc2b00d524eb388be40165f2883126c878f01cc308036a201ff5f89a22ece74c75a12ee394888376466aa1b0bd8028995caaa10e40de4f0b	1679820367000000	1680425167000000	1743497167000000	1838105167000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
115	\\x248d05d96143cd03d1f0965688bf891096001c965eef885ffc0e99e23a385ac1cbee16d8ce436fecad4f92508c9cb1fb16cf26723c7dcf459c6e14add275cbb4	1	0	\\x000000010000000000800003b2ea5fcf7979d59704a6472fee890a64e4d1300f4756776d9e2d03860f6291459e2e389ffb92907a50a1bfafa6ab933d59eea32067d11a653bf8ab45a46aab7274bf4c7675efb5852183b3b7d9043d5ee758d5d0cb133980d66205391ee31221434c9a5c18810893928845d971cb9775ab8359301f8d34cb2d4aadab46e67aaf010001	\\x5feab291419ff7f1c4a7b264891c1fc22f4bdbecd5539558133e95884b793be34f0170194c4724805a572ae776ddb9defedca3763f969e8bca2b5ecbb1f78f04	1684051867000000	1684656667000000	1747728667000000	1842336667000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
116	\\x249516628e8e354c099a95b27f076e4223bc7246f3cbafd297ef137a80b6f1f57402f8942866327afe33e41771f2091524163e3e717a48349e900bbb57c11b31	1	0	\\x000000010000000000800003be2a876600c0c237e6e8012f63acc1d08acb7a19634dc4a6a8e341afece4bc2fbd86d3dae1482b7bd1d0affa9689b2a912af8e7f1a4459be8c0aa8803af7fc0fc5a4eaab1942cd103920c0bded5dc8f8dc79f714b3a13e2303d9ef25ae2a6258226b106131224053e94d6df79b7feb31f675436f68f97e71e261f5264c969e73010001	\\x5931b8c7846bac16eaeb8a1ea91c2e61f47093c0d9c99e734aafdd8c936cd3ff92095bf50d226523b87dc17cb64d558683c4b48c4dbdf15e6098beb259c12005	1679820367000000	1680425167000000	1743497167000000	1838105167000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
117	\\x2dc11cd8b053d9c24a73f00412278e83b4592f6ba4e79bcfd5a9399926c2ed97c053d0cacdb5fdce874b7bfc2886b75b1d029060cd54d6e906b42298ec6fd65c	1	0	\\x000000010000000000800003bffa8157eeb85622050a89e1c7e6092b6a62dffeb03edd50b4701b55db014fd44de85815aa429ebce55d7b85f52be3f79adae42f01d3ee0939b7b92627ae5aff94e4c127c8f5d943d9a6e46d2a8273dd35ad8e6eccf48248f713740a419176eb401ac2334fe4941b5fab1f96f6c315a9bc99f185078dd754ad4c5b681fdf52ad010001	\\xe2ac55a8a8ef92dfd716c0cd50206c050f3adef5d1e466bacce1de7822a1fbf41f2dd501f5ac05366e5b87e9416eff6e1d7fb588c0b36052848621c49c293e03	1661685367000000	1662290167000000	1725362167000000	1819970167000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
118	\\x2f5d2d377c41db8c1a0443771b54024cdcd5a546cb6688a9e73b26625e5f62cc5aafd84cd410311bde9545039dac4ce6c528d6bf1eb80c8f1fc23bfe532b4fd4	1	0	\\x000000010000000000800003cdd40dde333f2b8ecb3020a2f3c1ab4b7e099f4b08654513e87051b81d6060c823064a194119c3b1e429a1df9e70dcee411084af56bd04fe76052da188e573630819a8f3206a26a2674c8f0cf7bfc1dbe6c0853378fb906efae93a59fd3feb0c42feb82b609d6f9704f09b464d2a563338b0fc98f68fc9c89feb80bcf8eef1b1010001	\\x7be42fe2fbe773b5f35d24d27bda00ae628b27455f591756b5bee226b68e85f16b2d92ed2e3c1f8dbb9e3c6d6c84e3825efb85950df7f32c523e9d1e9153330e	1667730367000000	1668335167000000	1731407167000000	1826015167000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
119	\\x30356b50e9bd87aaf20edf00158f75004e48f2cfc5e1804891558a696b67d55b308cff604cdbb17965f4a82d6823eba3e997c07af97b0399be1a536ebac87b74	1	0	\\x000000010000000000800003af35752a3d4befe127a492b1385a8a245ab3fde09f67b952f8848b2a05243aa933d2945eee49762dcd3544ad88ca94dc9dec6ee155f596f6e98d92a82ff3d914937e3e2475783aaa480d075d972c333178154507be346a9d42b03205df650ac1bcc2f2df877ce77e0d3666d3ce27bba0c57934f709fa998080eafb2cfb0ccfd5010001	\\x98fd7c9e0b78fd2df8baaad6a27e83e79aefaf036e02ff2b5f1dbe75b3c621ec8ab84ab07004a2c1057b5f74578e542d59f22149b12f477969ce64d453f90604	1657453867000000	1658058667000000	1721130667000000	1815738667000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
120	\\x30913d48f354cdededf0f6a962bc21f3e615cb607d605bb91655e0bf5b3b249fa2b50a50586c69b6f652c49f5fab216d9ade95c354d2d2f3b367a04510f45500	1	0	\\x000000010000000000800003ae702073d121df2be5aacfc08c08be3aa232ecf0c245d2c99ce65aff10243faf94d1d9e34fcbfe076b96b2914e73685c5bb3aa359bd755a6c4365fe17925fa573353d973a1231c7d264af178c6a554b9d0ee2f92fd6b63664317bffed6effeb20b9e1db07f96fae1a2d496fcffab8ed1a526bb57f1402db5b69d54401b427a21010001	\\x03b797dde96e4f0c1c45ed3843c9e010b946f74c091336d572ae69d0c200d10094d79f14d5a6a3e0c1b439529270d5a0779501f39b63ba034b49884da7f94305	1657453867000000	1658058667000000	1721130667000000	1815738667000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
121	\\x31b95e5e1c7881b58b8bd0f5b0d861f9766c361ea84af715f01b9edb78112a9580a6774ae323c269bbafd18ce08617ea4336411a852975f644e0fe8e0c989b08	1	0	\\x000000010000000000800003ec669798a56ad3406fea069433a68c0eb3983d1922e69ec8ad7954a4376429bd3c295fbfcb12b845dc6d73d3037ed431827ce38ce361244c0d885c5688c918f445b8797b2addf73b38981ed90f214fae63b3ffdf4e25e5f9a4c79a14d872434f2d3bafdc224e9735482876ee715cb104a02f475168265610e324ee4d0bcc78f5010001	\\x9530597e6e01c872c97617456d9f8a9b7792f3277c7f1345d290467dbee4cc6385a3706f0231efb2c3a6b98880356bafb1e7cb706ef30c5b46fcef1b04877a0f	1687074367000000	1687679167000000	1750751167000000	1845359167000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
122	\\x32bdb058c79d9d4f411ef945c9917752565d68d5a5638a53d953c451bfde2330b2612b2b402883e1749403428178a0fc0f504482a15c4aedb3f9c3208417704d	1	0	\\x0000000100000000008000039f1daa9fe58c68904850d3c19c1dc51a1b06d906b19b6d9ec169e973ce9e32481dbcb0b490056f9ef7689ad9d9b21314ae4114f5ec73eb946ec2332c830c7021ee563cb83ff3ca9333d86e9da152adc6643ed2053c45aadad678d6ba630603973fd7cde3cb0444c06f55f857cc7a4f0472a0295c81fce3adee54a796458fb32b010001	\\x3a785cca72d0137de93957456f433ba87dc29c0640d2d01bdad0a0eca467728cf1fad5a8cc33d4de86b5570a06748f8c04ce96665217f1a94ca0187c9ebc6d0e	1681633867000000	1682238667000000	1745310667000000	1839918667000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
123	\\x366994434af2ca2b1f42f6b798947c99b0bdfabfe6e230972bb92c5ac24cf689a7d7dc6f919c641caa86e8d71b71582ce01ed3726e917200479df23a6ed1234a	1	0	\\x0000000100000000008000039fff99ececb06385693306b3d303a8665490a79921df17abaa2caefc8f31cd8fc672e17590580f70d553a4b7048735c5e9b6b679caa623b628ea7ae418afff971b53547c1b989cec5152c565a5d3f43185b90b590e2e20dc3ef646d443f00d1c36aaa5642062edd5d7d68fe8ed4267879dcb7b39ddb1316873e1ab31c14b0c31010001	\\xd49f99090ad2d42320bf081c5baee45185140864b708dead90c57d1605aa95b9b13490e02bb49b36772bd96cb066bc339af2d6a2cea68a775905c81a4252a00c	1682842867000000	1683447667000000	1746519667000000	1841127667000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
124	\\x3aeda761a2a359d95b41fd43e36055b2d85c793548b8ba74abc3c20b5b0ef0d0b0293d6cd3f11482a78801d259177a66f0cd4bc7a306e58ebcf0bd75ddace00a	1	0	\\x000000010000000000800003c7764dc86e72b5018edea3ec4a852e29c2538cd1f02530043a80166482e409be14df452fd7daa6012e60d92484152869f7d2ecbac8b90a29c14b0ab4385b554707c98c53042d7bf5f6b3fe635a5906c3ce965bc6ffdabc4d4e7993e9df711704976199a04909f93f3a555d66bf271b45902de58918961c799796477c2f14a07d010001	\\xa59e2a2745ef6307aa35a40d42acd617be8e2eb56109811cece8b3efe5a3d50d1ef3d544e932392a02edb9f1694275ce275acb10902d9d6c02344c6a3edb8c04	1671357367000000	1671962167000000	1735034167000000	1829642167000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
125	\\x3dd96550c5231ca0fe19136c1edf0f21109819c147dc7556759db10ba9223dedea34396f80c151cbbaff3c69184ede8ef599f0d1ca99a4187ec633c5f3add8c1	1	0	\\x000000010000000000800003d0b6a204edf179d5e90489425fd31736f5c21c13561749da0afce6b19cbb5a25e3ab1d0c32963d1780a306103c1636433b052390fd161d06448b0890587e0bd103c497f9e39de708b96c31be7ad3febe7d8d732d494d9ed5edc41cb8c5833a0acbe25f30d2d57ee036c5a0afe508e85b0ac466dcac91babb25c9caa07e26247b010001	\\xa4a1f07196e7d1f38e47abfa21cb439659fed04b8c4fb86b07e457d06be5650b63c864d73c24d1c4729ee384e34a8d7d056340b29301d396b76b0577f4240f03	1662289867000000	1662894667000000	1725966667000000	1820574667000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
126	\\x4aa9cf7a3344cd4cf55dcbcdd9f0b62fabdd3c1cd3bf19d21d1510c75b240ec86c3e103413809b21103529c6979709b5ba32777a4ac82dc0ddf46edeaab2d206	1	0	\\x000000010000000000800003bdcb5dc1fcf6bc4e4c71d4a5e562bf76c7e8d0fc638ac1e509b78fab1a59bc34113e9d100afc4dad5809d91b9a229dc49a9467ceaa8062bf02be9c188a6a461eb6557d179b7e1a5121d3baaaaee10752b793483e768987289a647fd13df76a95c1bbd638ca6a94059061af4d0a59027555e6b8a29110fe71d3135a0766a62d69010001	\\x7e30588609ea713b61d04e8a6e0d4ee3d198f679320e9c60ea818553eb2b57855c5b0575f0226f63203750583e74e75eb50743275f0e3d16923aec8e1a04c20a	1687074367000000	1687679167000000	1750751167000000	1845359167000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
127	\\x53fd8b9365340b3dcca20f2de6babc94db176b48375cb1af6e93496e0c07810bbfe022f110a30f0bd8affa76fa59fe47c3b5274bebee0870a007da7f997f02f9	1	0	\\x000000010000000000800003c507c335f5454690526fd3da9178e45a137cfdd561c07d0646878bb0b36a43491c8514a4fcbe7883e0612fe671298320b945cb1b3cabf8e3f62b550a781d676244cd05739045b0fceb83618e308665928dcd3799452489a99551e36a6a076d56ff1b964854c1ae84d78d734cd005a8fd779def722d5809549cb0143ad62bf679010001	\\xc56a72180d98f9648bbdff98ecd4baa67476abc990e2e08f8565fdb2e9a832940b1f6672e8c2f0d1af4e813df5ee7b3fd626e102366a9eaa8214c1df47553a01	1666521367000000	1667126167000000	1730198167000000	1824806167000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
128	\\x5525e8715a46d7b20833f4b8944309fd2d60fe2ac7870712608162dfe52ae390732a7c29175d25d12fe58c79505814c78f7c1c76e53eb24fbfbe36d18fc1b66c	1	0	\\x000000010000000000800003bc74a59cf0c443a217bd414536e78bad10727a7f7b2679682e818818c52cb9eb93dc1e30388e11f0fa4870c194eb8e18d85e58e0a6cf81a11ec5bbc736d31ef18128013afe8995e874dc5faae773deb911a20a0626673e3f0696b09d036859a35386f315d0e6d51912a0e4928a3ce83b0fd08aa88fa059864c030084db6a220d010001	\\xc656f73dbc600d0d118c8fb52f48c670544fb969fec44e43deca5156e4054df6dea127b993cf00f11f381f23bafd990beba9236b9cd8de4ec5f53318bd2a740e	1674379867000000	1674984667000000	1738056667000000	1832664667000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
129	\\x55797efb91ed752a0d4109a260c439ce7ee1f6ceb6891344b472bbc758932b8f535f1e61cdbf177280f6d6095ca0ffeefedd350ee187945b6ce289f2d9a7d107	1	0	\\x000000010000000000800003bcbbc93f6389cf3bc6ec605d215396b6c38cc55d9e6112240d04058e70b026eaa73b435cdd9ec747b8496e7089e349007bfcd9c5b019b719e9ee4bd488880ecbc17deeaf92008121c9950d6a1045bb3dc083a2568575dd88b036a06239a3c4ea297be40477d49ea17eb88677257fdd53641cdffade4e222abba8ddcbec72f5a1010001	\\x8bfacac6f0d22d4f1d421325723962c907b90741b045738a2c421919251561b3ca23b3c826016cb6eafb486a84f0833104047089cadf8391c59ae4547cc94b04	1685260867000000	1685865667000000	1748937667000000	1843545667000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
130	\\x5665aafea14a0c77f65dc7e0459a604f26142641fbc65cb760a1ecc7e6f35385672d92c0ffb5fdd2e3f53e6edc58ea42af1a081202ab213689477de44f3d560b	1	0	\\x000000010000000000800003ada6898e0ccb37c0d7afe8feaf552bc4ef17f25a4e412136179e6054fcbf73b1a6225469370df8a1615a0d4ed7177f0e67aa444a8807667ee5535a03bdc29f6a3f62740148b5cae57320c9749f9d2323728408b41acb9c24b57bbaf45157eb6096f462b06a3b65743a8144d16fe814150e8e198423cf26881b9cae21fdc7cab7010001	\\x1faa4aee4e6fb9e504486a48ff3deab65c747a351bc6670f51124a1b2651586f99498a1bad3b75e609fed56d03b30a433db20973798c479d3860ff47cae93109	1682238367000000	1682843167000000	1745915167000000	1840523167000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
131	\\x5751ef82145ddf27f1200f07d34305c0ec30349e9112e140dc29a92ddaffad2754ba531bfae72e13fdaaadf96b7012f7def600133e88c55531b04ae83afddc39	1	0	\\x000000010000000000800003d18dd19946e4f60ddacd8444151f8580c5c73f650a68cb6488da4de650dd29fee998f967531498faff4b28e3b0e0ff0362f13c830fdf2dc6c35878ea4994f526e61a47b33c8bceaee4285e8b7bd728661fa2dda2747691f0494ce2c28072f6697a12ea60fe25b4ef5eb52248b7ee45796934322491f4c8d673ae9c25725100c5010001	\\xf95db4e71b117926ea43593818f78993748fc2cd61c7edc8519b2e8b65b6b86967d8445ecefd99ceed0e7b5dcea469d40cd5c5957c1e65a2eaef6ff8e5870905	1682238367000000	1682843167000000	1745915167000000	1840523167000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
132	\\x5705aebf18b081184d9f3414963355311108a1e4624fea956ea9edc6e5e61ce9d8a899a369c7064cc476d739bd200abebc6f46b3008097e30a9d6e22416a9602	1	0	\\x000000010000000000800003c2fa7273b6b3db7799682f185f2849e86f925c5f11b394721c411a477700da6dbb56caf5f8b5253a898d6f937076f24a70ecd8016082ab3f8916fe77aa322ead9af44920f3b2aa49a3730f6a7e600e0e18ad25fca4ff08bad135ddcebdfe5b52435c6041c339a092b3fedae065873a32e2ca61fcd69829c6d4306d6dbe05e15b010001	\\xd44eeba6c3a2021a6bcf680c59f500ab5895ca7fd3755792d9a21f339ae093976cd98ce691b5a53ea885e739e866d7b851e1b135ba7fcbf9e2a906d7d3206101	1674379867000000	1674984667000000	1738056667000000	1832664667000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
133	\\x5b3d4c7a08e455331dd5e660c6e15ba6c3f7ba8b3f5d39448571add4573efe8e8ea0b3252f27885525f3c176e2730e4570a373ed9f3b572a795d928f01a9b0c4	1	0	\\x000000010000000000800003b4cc701e86bec6310d02a1f9e6201f77b69c4d5ac31b9e6537014147d071738ceafbb7fbb289d793609206c1aec4336b44fd905031fc313d30e2269cdbd001ba13f79b1cf91c492473476a944e7ffd8af02928346e49de13dca73f88e6dff68b250acb2f9c57f9e070a3138d60f608050b3bf7e4b3c1c93059bb1af009611e51010001	\\xa8b3c1196e6c79dd69bf07984e4dd58b628dad0d8ba240812a9b832abab8bc613bef52b5519167f76773a7326edaef478a34df2824b18058202fbeaaafc16002	1663498867000000	1664103667000000	1727175667000000	1821783667000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
134	\\x5ecdd51746c008a8d06345e7ff9c4689177c0011fbeed1e09afbab669cfdef0f21b02be01a6b154d36eb9875c6527cbe6ee3fcc07cdeb4e1c5acf92e7aec05e4	1	0	\\x000000010000000000800003d78e1f2e52acaa2a0d4c94c39181119d58af931b01636514a375a94e3a1fb83c87aeb700339e09e3e3d923482aaa7320069a8addc7ed7f5c07261cea2846d172698b33f1a420a8147992a9114c56c48d9fc169dd8fcd182706dc43ba39fabb245ffffe7174d59f75d6d0f60ac146284f90cc7992096a0a7dbb6fd503ca8240af010001	\\x9b8a416e25b563b27705bdf71e8bcc3147163dd3018bc6a3c10e06c70b729cd32e4e8464350bdd3515b1b73c616aa57e927d78bd7e2483ec87e88e0d4b310e03	1682842867000000	1683447667000000	1746519667000000	1841127667000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
135	\\x5fa9c8aee95084113a82e4c28796bd9332de49863e8711edd65a477226ca6e3c4c39db942b496e79959e142506296ef43c6af3fc8b6618631976281acff1344a	1	0	\\x000000010000000000800003f13da1788569501f05f824b99df9035c080a9706ced40802c5810f9ebaae439dfc752e354cfe9f48c22d81b9525c726ccb4acaaa16f562fda27df952de961228ee5a74c40b02780e2ee901c2d7c8330bd49a39509a9cce7c97bba4cf1f3608dc269cc0a9ab3ea8a18a491e1a4c46875897dc5246a775aa1fe07a6da2c6be249d010001	\\x42274b9050680981bb5f2952abbe9f52bff300209af09cb59a8e7c05ab0a4ffaf143101f094c334d86dd53a1057abe26d591ed328d45c79c0622a7ed7a559002	1676193367000000	1676798167000000	1739870167000000	1834478167000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
136	\\x6201d954e0f59d992494cad8a49b88d1c7376c2066664bf9f29e6197fd4a5a0ce8174129eca4c845519877803383613cd050625a65935186282812f0e62ed683	1	0	\\x000000010000000000800003cfd01ff1b06c50a618bf7ddf2e6a214672318b7efc374a46f3036d2f4b1d4c2560ae1da1f4ef1aef72cc2f9b60c168a6634d244b19f70ae227bc75904e1624d3c4160450d701fe6134bd4b58f2acf7c5ef363ebd8bbd71b729f70bab324e25a4e146548c88de8f5606ee7e1bec7b562c46d504081b3e1c8c16f98c6a8ba2d0e7010001	\\xfaafee30d2fed46e566dee831a3488b3535cbf70b30f76be4ff50ff09ce314f21a3fa9cdef5e22c94430ee9a996261638e17e7b692fb082b760ffcbb202a7902	1677402367000000	1678007167000000	1741079167000000	1835687167000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
137	\\x6475dac6be0e09f1c995012ad12f09452c6014e150c2d9d9baa4eed37e3d8b44dcb3fe7ef5e52593972f9a9f8ca74330fce96e6a9af97abe4cc4bccc895c1613	1	0	\\x000000010000000000800003b2ef56a39037afaaf65b0f70e8370dc43588f2551130acc8e316993e0c803ad0193b37bff330fc575c0073f8664d61805d925214fb0ae6897c9b186c653c27ddb43ca28a489613390e54ee9a471021e887c8ddd1c9b5a2e1587b8fd5123c8780920ca64ddaed085528e77ce28bd8deeaf7ad13ea2705751359eb1c1cce3e73a9010001	\\x73b04e6bf3b59cbd861c839f2429fbb3f4263e73b6011d7b1e25dc32039f7814b20f1b3bb61bc8403bcab08c9a85f0502b3159233be209e0a68bbbf70c4a870c	1656849367000000	1657454167000000	1720526167000000	1815134167000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
138	\\x67d9d4d7bb9bea56dba5392881adaef4280b52f3e64a1f25f3bbb3fd865e37d91bfd7808b3f1696836bc7df31410889d69b99ae640149852371657a928e54f7c	1	0	\\x000000010000000000800003af515b5c2a9579c08eaae455debea529b805732585c55ac9b6a352e13eb1f82fe1f49771ec944b6c2a4ead556f2b76101fd7058652fc2a0ebc0fe3a71cc01e027db221cda3f745419f6cffd33ffe4274e017ddbd161eb90c060379d1ae05e8168038761f393900ec33b6b7aaeabe580c8408ff72dd2295824105913bdd9162a9010001	\\x7066b67350c28ed783083ecaed04f0844f6dde50d7061451c4536f65c2054e15b28229143ef4ed48d54e1d631481e18c7f29536f9767000195a7174a8be49a05	1674984367000000	1675589167000000	1738661167000000	1833269167000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
139	\\x68d17a90d540a2346a6ba1a43440bc5a1133bba9d266b3d1c5361b6b4e4190081a7d3ddc546c31316d892b2556e1bc9f45fd29993030a496b0d0c3520a341719	1	0	\\x000000010000000000800003ac02ca8ca5f988ea8713288c06ebcc2a2e9f3184e0869fa12cd3eca38732a325dd850cdd94001ff2bc75b4fe74df25deed59ed940e347a29841b9f7a4e990ac51f421e77b6e288cdfac1a2f7c3e0f9d35fdb90d096b438828c9ba3a0bd39c049031842e726f2ff03c42bf4fb51c4fc25a648899d98b9629c915fcbe3278685df010001	\\x48b532cbe8ce00e9eb76fb2b45087d4838e14bb811c3a2a161172085e6641e9d6834e967d586f7bceee679446fe6bbb6da2bf22121a48d582f173a24cb047005	1685260867000000	1685865667000000	1748937667000000	1843545667000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
140	\\x6851bf0de0dcfc806b9f265743622f43c473a0343b1a1d5b2aab10a6fdc1afd48865e51e1ec78d6f66e9e268971ee8ac698e78cc6d893b1da1216c747e95508a	1	0	\\x000000010000000000800003c02a451e8aef3f6d9f1d4145fa1654d38ad93fd6c0432af6fa6b2f399140870a249a3281fa85f3e62a941aa32c9b69053df80687fa6bfca8afca171b9a7d516dbdc9cf19d73a152ca7f38165f9e814cf6fb074fcb6e9fb2bbc428b42e484231efdea3d6ed46f816fbdf3a9565f8f690c5d2e2f2f86aed765c66cc89e599fa6b5010001	\\xa3c4980c9849a482425eef514c38b9c11da4c71909a2364d64313b2dfd1c6a0ed73942a7921b04330346450a2859d057b0faada206dfc6627b67bb9b23b0b608	1685260867000000	1685865667000000	1748937667000000	1843545667000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
141	\\x699595be8726cbbf3967763255afac91624243ea75e59d4f883f90711bb6916a151e97be6665acdebb026476db5d61809cd00296a25050d9c079afa308387de3	1	0	\\x0000000100000000008000039cb1cef6149e52c24f0727e19b52112bf3c759acdf2a9a8acb4b270c542ac6128e82fa908e366451c23de47dd227dd8405ce5116dc338de57a950589590d82340b0152e5f6808e9b9c34db9349ab57343e155e1b51852e67861547f479f6216487c83266f531be6d28c84ee01a7a25d59c4e32941216fd7b874163bb9892d5c5010001	\\x0babb0c553855a1b6e7ef4098d8c9a8661d3d13198b1d7bae9a08cdf8a2970f97cf97f345a9beb908cf75baeeba977b0eb3d04c7c97b4d2c5dd7c906a5415906	1665916867000000	1666521667000000	1729593667000000	1824201667000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
142	\\x6b4d5ff16cf837095c3b38c17b3f8a9f104da4a8ced8badd0d821448779d92ca36bd293fede635fc2f0c923b2ca4a56683243a4a589af75a37948ea58501f119	1	0	\\x000000010000000000800003d3453e646266e19d57434987a51b64f3a1bb53797ec2d4766a59cd80b7cf0e0b81eb9d7f354eea8b81c5f932b8f86d64c7f2f99735613744c2c04540f0b83cb0644af36325039c049ccbcb1d4c59c9bfd31017ab20c79090fb681bbb985cc38a922fc98b3f3a88b44f6515481e8d06512022b2e96fa81b5e0fa1f58a371009a9010001	\\xa6f04572736239868070fb2a54c171522940348a9a81f125add7f7a49b2bfa23eb2eddcfdd8b79c615faf53f4a0a59a6b429a92c7dbc2e3e21bf0b3745e3ce04	1665312367000000	1665917167000000	1728989167000000	1823597167000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
143	\\x6fc113e9a8012ddd65ddd92299a92d0b4148919b534eab8bb27676764c6fc40da08781d3fb7c36a6f38bd58c2419fc8be7dcb70d36376bf94830e59ba61b79c3	1	0	\\x000000010000000000800003afa0e9c2225f7d16acfb751f87362793203a89fb292871ffae6639bbd2d0a7d23a665f845bdfcf0ec9ae30dcb00a2be8577881bd0f92c1776371bfb46e05b51eef9d96049a41c6706733dcda20e800091acc81d03d77c34d6b83f8f45c299765595fb7ff634189d96f285c460117f8d58e07215420c830109c99a508002b5475010001	\\x6dbdc96985ab69cabf8bb26e0118451a5b94d7bf496542b503a2f90410fc2f07fbe58aef7f9eb07bd1d956a34f9da421b52602fb43ca7984a7b8687034e64d08	1668939367000000	1669544167000000	1732616167000000	1827224167000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
144	\\x7105171b799bfa062db4589a3befd284e3e5f1751ebcc17357c7dafa9c68db34962cc9c6bd49f9e5453c20ba4e28b4bd7af02bad1372dfb94a5a8feb181075a5	1	0	\\x000000010000000000800003c40c4a93ae47707a85f1e0e6dbdd2a79733a27e5e562dd0f16862966e7fbf0da4a0c79f74a8a7d391c738fc6a730a34852dce76354f8d2a5e2ae37be1641c79fa4f7dade829b95616d1e82204218b0c762411b63026b98d93ddecd9dbab803d7d0228044ad5ad8fb8b168070171f4a63d31eba874c0394a477336a5dad4a3285010001	\\x891e4939840fc31e207e59b81d276fe529e15554c197eb1ef40ce96b0142ea9d215e43b2466ee2c7a43b9425c0e23fc3994445c0ec4f640219dd34df36ea1f0d	1679215867000000	1679820667000000	1742892667000000	1837500667000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
145	\\x71e5fefa4b2ae13213b34576ae189c655203c7e9554f476ab711b7439bee83bd8319eeaf78fa3d0fe75471e89c7df90383b8c8fdd1fa4ba892c950ec67abad65	1	0	\\x000000010000000000800003c283ec2c17bf02abc24f4eba701b295e1196acf24eb3ac0d3078dcafa4815194e7a1d09b74fa626a091d452bfeabe9e200930af6499c602c03dc74064234dce25d2048b773d81da850df6c2467010a1c7e5c80db20e3b65b773d4bcb5e2e321a706e65805905e4a368e1c39f41a78abf5a1bda5b0a93e9ae7630b004d94a744f010001	\\xb524f261e885d781ebf9c67dc79f85e87594f8b138b2ea85999ce60bf20137dfaa95614cc2f25a98477ec7fadc157a57fb45ffe76503285f5fb6c9c0aa835704	1670148367000000	1670753167000000	1733825167000000	1828433167000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
146	\\x72fd733ecffa91e4bf173350dbe5ddbf9af06221daa3b50288cf3ec07ac3d920ebafe1f8432a39d09f7d88f4e27ffae9f4a997c717fd3f39daf794479e93d1c3	1	0	\\x000000010000000000800003d01511af3adcf9a63df5964197b7029225a533bd339f06801db6e81c417a27eacc44b1335aa8fe0489eedd2baa72d64fa9782835b78ee1ab8615f57c8baa5f98fd79d32e7809e544ca61c7cf5ed7dbe78ba2b5b581a4202923d236b2730db1430c57ca6c151590781ebb5b2079b5c452722eebbfb6ec912e540bc1974c219cb9010001	\\x35ea34cff997ff00793db6020af31fbd02936f511b980987a524e45200ec96358c738df109c665d04d4e65af48a82cde87decf2529ed3d208773c62a59c3b607	1657453867000000	1658058667000000	1721130667000000	1815738667000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
147	\\x75f11b48b7563651198f1e44fb20a575db3722db569796cdfcbd4d407d862e2a0537400f303b90f35f2acfbcb81ca8301db1f24bfcc42e9c71a9339718889d1f	1	0	\\x000000010000000000800003bd61b1ced896a78ad3b7f32365163fa4223385de32221068c4f6ef1f4f66ba8ae4f13a9f992ee48662f84db13fc5d25394dc6c55e0431111288645ddfa1ccc2ab1a8624bb0ef10f6c1bf8b56085387861817719344300f47d48793648e194780635f963c3842a56776e0cd677507c6c9f97a744fa07b2a782b24c6e76ace5fef010001	\\xcd4f122e6bb67c7826d8cff5b5e959feec2f158f52351e74ed38ec5652da8f961dd795d196047f420526186e2af41a4f4f5645768d1d7d88462d3bf75f54ca08	1669543867000000	1670148667000000	1733220667000000	1827828667000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
148	\\x76317d60a568b0df9809f761580882ec660dd2cfcc6d218f77abe6a05a0af183dddb8a840d5c6289608d6cadab9e655d8a7bbcf44061a7ebc79defcd763072cd	1	0	\\x000000010000000000800003c1142283a7b90b09b4cfe835d625450ee8e95041b404b652386b54386291c752305cf8832d883c2b86131bbfa073ee0dc45db05891bfca0cb235d86174e715f12f3efffdb536268b16fdb712180c32e59e53605af034513835f2e258e81da9099ef95818652e6ea64597bd98db9605af7bc309a0b86c5ac307bb27fa4a229a27010001	\\xa8c9609cb690f774ed0a50e1e3da794e057c41f60560fec2d623f8e30a5f968377cb520dec0d787ab3a77a9580e384b3ffeee786bea7d3fd12ab67f275f69f0f	1679215867000000	1679820667000000	1742892667000000	1837500667000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
149	\\x76157af42857a8ae5e87665c2eb58a747fa87747fef5ac8937acd8a00307f6a0aeb7be08c321f30b7775f9ebe242c36978ea02a7c4a01c894b5ab12c55dcc27a	1	0	\\x000000010000000000800003d1ccc32db2f540de1d14c6296ae62ecb2a6a0400982636522f1a17fb7683c863e8299f4d8e47918e01ffad1834a0499f047b2b5a27d41035cf54b01372403ad7d787757ddcac497dfbafde77745b200ad86ff4afd2b4c1b97882389e7c0091c2a4d0128b5ae5cb6c9675e77e19c28222ee537f1adc90fe090356be8d130e1b5b010001	\\x82934c6d61c35996b0f78cacbaa666622466a25cb18e959e53db89d887156e2ccda344a6db863c46da2ed9bea72627d542699e73e4b7fbe361fff1fe1b7a3a0e	1676797867000000	1677402667000000	1740474667000000	1835082667000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
150	\\x7a5191ae0b5f1385dceef3785733d4c85f2cd3f89c867feb91224c523797f19c6e862aa3458d120cf389eda65c4fcec95823a209e2c76709607063ea126e17cf	1	0	\\x000000010000000000800003cb5ed87a408c0c9da562506d75d93a08a9ab915cf74e235819093a990d618a0a7ba9055324e191c27bc8073aa3605a17c6a88a71f56a2d093c4e3ebe8279b322d1f1516fd5c2ed6cd61d6d4517a0485995dc5400d00b7ca7c8e35e9a3bee70a4aaac04621b60ff948a3c07d43ccae98f8808ad755583c57c1a4c0af2124781e7010001	\\x8cd9036ecf6cc9f018c79b5de26b9bd6ffd0624b45bbf79f22e87e7024966f902d3fe11bf5fd73b23ba54169d3c624944fae38ebc756eae63caa3f4765ea3809	1684656367000000	1685261167000000	1748333167000000	1842941167000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
151	\\x7c35f2db28eda0181f14f28443df15f4fd25b1944ab37b28873684339e1334d690333638747c725788f749a25a8a293e41a952fb57a6396151f7187a29942b1a	1	0	\\x000000010000000000800003be310ee9e73e388d223f79456cfa7189088c83e62f5a54f5e8a2385abc0e11e858a46c0555fdc6dc3637fd9b3ce72a0142c076606d464c92f7f080347e535008585d6b0a42bf727ae089ead85503cbaf47577f9351f5af23c9241ab0cbaa019b0c1916accbe383047cd72a10b9e54bd60098d8e0903b8d4affa842eb6514179d010001	\\xcf0a7cf3b0bb55926331f2e852b1f39ebf179b4673d1b37fff2bd26f5fdf946ce4dc6ed601fd8f155a2e6e4227fcc4f29c1f46c9e5bc2a0ad05038b76a6c5e0d	1683447367000000	1684052167000000	1747124167000000	1841732167000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
152	\\x7ff90b8d06bb94753d3e454139159d384b1f4d5a8ec66ef48bb919b712277c497d8b8fbe054a7a3c4f025349d4d276918f531708fe767a6b1a89188d8dcf3bd6	1	0	\\x000000010000000000800003cc56cd9f858f31ea9ffbf20f10c7464992fc7b7a8ce7c1a47c33c2e3987c76d2baacb801ff2e1d4a01265f3edb0b259a7868f1c91d5192b77168438a9f4f0efe402947b5911b9c0d3e873f1c054ee00f6fffcf93812d8015c5fa0ebddd33bcba0fee3d2b10208f28d17b943925f684c1da749ea86ebc155af52a6abcc70bda77010001	\\xb5def87206717cb746c318c1c09afc5766e0f050784c959d5cc759cf0b04320ca9f4fdebe71f10b81392abfd931568d7fcbd7f06c6c6e6578429df342e9ac908	1680424867000000	1681029667000000	1744101667000000	1838709667000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
153	\\x80c57ffd67775571e155cc86fc6734c04c3254d96f3b86461f0f9374c1cef6a0ee505fbba10c6126f00b3808fd55c7163ea5f8f6ffe5682df66cea002aba4295	1	0	\\x000000010000000000800003bc3645eeee6d372705d61bf59580ba01cccdd3db018ca3510a34b7e40810c305fdb925d29d274b8aed750d2bb8a72aaf068fd80d5baaace49e4c2a6b0787ef1aa94f6c08192879c1c6294837d81c4a835e87103b433f375632f915d2d26fb948d0ab7ffc37765e911967fdc7fdd715ab50dd103246ce19988c92bea233751179010001	\\x364c68e6927c3c60fb72a0830fc8256f8d3e1ca1810047c44cd2eddd7ee35380ebcea94fa54abbe490687b3aaf3978508af8e7840b491c65246093963f76fd02	1664103367000000	1664708167000000	1727780167000000	1822388167000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
154	\\x810d7096bcb9f4718ac4ffc3ddd3cc0cea99285bb86f5e4be72ada81902068aa269ef37e040a8826ea66be46b22d471775a646a52d845891726a2c6367ab5e7b	1	0	\\x000000010000000000800003ec4c76a24958775faca6aa4d6f10398821bf1fdd838a207385bc481028a9f58b844ed39668ceb0cab4bbc0c793dc35d1639e686e563e837b2dd156d962a1b7e727d862650aec01dde80ae2190dbbe48f1e05ef509e426f35da1efc7959d64c26aa01a13563561b255b9bbbdf551eeb9658d8e18078c69846ecd0e23bd5c78a4b010001	\\x2a435782291b2175710a8d99b5f5e93c9e6062cc4ebe265adfb84f2f1dd1174c70f29a6ceef101f4c49e9d8eac264883370be8405c2651635c375ea774d3e900	1676797867000000	1677402667000000	1740474667000000	1835082667000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
155	\\x833d168e071b058e4643dbe44cfbd8e1910919b1170a97e3240afcc766903442e5d7e6b28a983c2152527fdb8e31a31937d244251389e67ec261220ef067530b	1	0	\\x000000010000000000800003cd0cdb8a2c13da721cac6e9ebc4d9c5cc7cf6b3645067e6d9e1d46a9147cfcbfd0ab51c730bdb007bba38f6181808e2c7b795d0dd8570d946791b8145ef87021d60908d257057910dfce0a147c11148d2bad12caa6ac0207e1b324a5d2878d716df38823909d3b7a69e27cfe5d9412ebaaaf990854584aa733b727f5df8527c9010001	\\xedaffbbdcfb441570a166447278405b9f31ed48031266282a39cd5bcd3e217107a29dea6fe2d0a02c814f1e060b490e1db8a60bbd3f57caf35f0f7094ade1203	1679820367000000	1680425167000000	1743497167000000	1838105167000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
156	\\x8ac5e622efccc8977f506436c1e9e778b5f8e38ed0c6e980e5140ff5554c14c6bc48981e8240ef8d89e1a826fc13c574bd6d81e1ed3a6488621747e01de97987	1	0	\\x000000010000000000800003b476cf686a0f75c6e3b5e6056a54f8ddf54054074f645016ac90291ba1594e17949e89de5998f718411cafa47c463c1630a00678349d2895b8952552d438e1a213b7232f172e1655675ac7b6edf66abcc2d7b180ca82464dbdf1fce5498c9b88092f798092b114143cbcd4e52b9a439550f80f31fe2326b4c6609cddb65de139010001	\\xd00f3a067af78a9efb3d5946850c1ca52617c6978d5a0e0f95d78ead4051386eb0c6cc634b73db0fc667e62f271e2558c7d568ec9727ca0998a47bd0c5db460a	1677402367000000	1678007167000000	1741079167000000	1835687167000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
157	\\x8c49e3b8565dd655023360d3e6991eb2f8e8c2d6a206cf020e1b5529dde7521fedacfec59460447cc8e5dd03c6710800f7c6d88fdc9e5efcb2d20addfdd05972	1	0	\\x000000010000000000800003a3d29ee6b172a7add2b97aa1ccee08966b827f24e5bc3e1fe8cdb7e98beaa5b0f60c5e5e9e8413432a767db7324ad915dc0832b9a9b800a26872b7ad02686ea772600b21063dcc336b24513a7798788bf9e4179fc78e85ebd3395e6d2fa393fa4e4e350cbb346391b9b8d4f7b1da438acf8be62b8872ee2716ce5d175eed8995010001	\\xd0efcf755bf0a41c1e9a219158363292d053829488f30202981adfe466cd439310320c7c1f91c8785848cd690a414c28269cec4f6f5ef337fd5ae9d7fd0be006	1685260867000000	1685865667000000	1748937667000000	1843545667000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
158	\\x8eb5dad7dcc04663c354a797bf0635a79469b17f809b6f915e2c4ce606d7196e1e56d70b214dd9e8fc7a895f9353013dfd23bd033e35d83011a7cdf8ec2ebd76	1	0	\\x000000010000000000800003c61e3e57d490e23246944b77f4984e011eebafeb0b70b0ec93e23b3683a36a9c097c9a9b83ac76d35dbbbefa8cc7cf9224a566f2dc7cb42615f0b2e8463fa57e30b275474d485ebb3d31a17e6d0625b87d56ec070ccdaebc3c7b597db0a11a9cbb13b5c1ce1b16aeff3803c9e54535457b314e83528fb82225e16853d73a5009010001	\\x15f9efd287867f73dca47c1a4a4ea003d6d48762522fb37119edd737ca7b8e61ba853322608f0329b45f29cbfca86481d7e40f563a968c7a35ed70d980a6660f	1670752867000000	1671357667000000	1734429667000000	1829037667000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
159	\\x91a5f3a5e0b9ce45ce9d9ec506500e125572d47e05198f41776b058348963bdfe86b3d1df110e798a941b6c2b7e7ad3c6df8f6c9dbeac23f77c670f5508b39ac	1	0	\\x000000010000000000800003e63cc806d76db12efc90585be6cb931e5568a4ab9eaa1d03472640f6c8080fbe4ce091530abd22ff05ec1e869d37f569f497970544fa4c52c22ff186e88b1cf4d5596287b54725ceb6e22e46cf8abc0c1ca787929285add3a4527fdb7ee22ed7a4bf35e777c27b3a5a40e7984ac866609e91b6baf610bd20013b17ae1b22d9f9010001	\\x5c3992a9ca866a423378adbd2a1dcb6677ad38f91925e43345bdb585450104d3901eee987a21e0e26342aee95f4c0c7453651751f5f054265bfc4bf850b53006	1682238367000000	1682843167000000	1745915167000000	1840523167000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
160	\\x922d33bf63aa85d73d0c2be86eafd617fb5cf5f5fba86f2f552ad58f4cb0745e0315ad7c7b9f70429f9f762bbcc89c53dd00cfb3cd57049d4cbf0ac7c808eeba	1	0	\\x000000010000000000800003baf70e8c34319cd2d706c8cb8fc82f512c7355d6a340791c88b677142f778e1ebd30bd04f29fd99ff3b421b6a2e8ed19f7dcc6190e1b205b370f1e9f1567e52429efaeb2419c65d2d3f324f8576857e64dd1d4e243666c56b0561a605b9407c60d6256d9c3eef1e78ad037d942d2c4c37bc4c6808ce24bca5f23455555cd50e7010001	\\x038cc2cc74ba0706d1adb15f2be732f8079d560c5237055d62e397c9a522e33e45b77b7c70aff64c8ed8569ca47791aaa6810ed80ead47bdbe8dab3d99254d00	1684051867000000	1684656667000000	1747728667000000	1842336667000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
161	\\x980146940b82b91f0b58510f4279ea791b38cdd66e6e1b99d8d6b40d7202191c16f27c802afbb93d9bd433960096eeea6ec878836dc93a94db738719e8d24c1e	1	0	\\x000000010000000000800003adedb6c134d674b4c6fcab2f06f057ab35377411ba7428d8e31efa83247699e45ecdac18cb534a0db703eff9ed6d14c224ce18393c0d42bcfa9892949640c4fc59bc006ef1c5f7e02106f8b026e0aedcbb5fd9d923ef8f5fdf72cf5b5727552b72f8be9bf2053371dbe4cf49071784da2e1925a985f3e4de8361449b40002b59010001	\\x011681bc9144a484805df3ae3af2efb73742bc1d9e8002b0d36264951086cef50740f87669fd09b825ff6cd88963df93ae14034f125d91c9244428f21ea21f01	1680424867000000	1681029667000000	1744101667000000	1838709667000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
162	\\xa375fb9aa596c765c30085ae517e524b80ce0dcc6b4f1fcdc8aceb5969152b46f0ada6be78f29771ab1c4278cea356a9fb264ebd90015018aad32e79fd996d86	1	0	\\x000000010000000000800003ca799c4989dfbe426f96991ef2212d49eb6580144b64a69a0e40e7627b2e3eaa3a6cb2ab098a21b74127aa0fd0a5c0b867518bda9707797f0847c29327f29c7ccdc9573a67c30e50b3430eafef337390dc3da0608b3fc3697bfdc5ae4d791ee4b26beda9e58cb01a637508492d9431ad8687013bbad6fdc135ac0f610d033f67010001	\\x577421ea112ee1081f8fe7d1b375749404c51715f9f6033ecc393ae7671306d3b07242917a36e52eb37e8a9674f7deca6699f76acbce890af60a2dff4784700a	1665312367000000	1665917167000000	1728989167000000	1823597167000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
163	\\xa605e3aa9f5e0d57de29de1902196dc21241e349e745977a66f6e137d85c898ff8138c80f4e5e8c3edb8c0aa5fb4e7703ca4ffc26f74ff0d5a794e6be6eab323	1	0	\\x000000010000000000800003a3b4921fe5380b995af30fda4bd091d3058067d9181582c1ad0bfc9de2fa926f5e767a002f380f72eea7473f55cd1a1950bf031666fca7cb0db72a6631b59a7138d2e2cf8f22633000b03c73f55549b2ee547ba81101444fb358ff1f52d46c19ff67e1f4ef40d7d65ccda6bd4d910b3c1440385857277c69101f1cf720577dc5010001	\\xc928cde10a32f1ba8fa25c59508df7deaff694217e80af98e5a9ecc9d477259c6ddd522920b58d3f5b15e0a11d09b110712e5389451a9719e5dc1dc9cccf1e05	1674984367000000	1675589167000000	1738661167000000	1833269167000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
164	\\xa84160a9f51282ec47c0b612762d7f1361ade19c5c30cf08cf197f3d66780fa3bcf073ab2af783d8db33361e4d7217fdefeb3992a2a5e97dcedaffeb6c973128	1	0	\\x000000010000000000800003cb283ab6df9d9faadeab4dadb172fb3bf152b2ed679b28344be1882ea8a274a99d412dd31ff45af17e86daf5df334a14af0dfe740cdf588f646cfcb00115c9658d096ef884d9bf125a3c0824bca43274a424193dc1056a9447d62c36a71fb256b93358cff1595854cf2ec426cd915aabfaf61a93b82cb1115dcf81106b136153010001	\\x0435e3e7f98d2fa2bb4605969dfa1c3f89181306e1df56157714f3cc42b0a6ab10a7ec2493e1012886c4e4982b0fd0de7b88d192327b5991f46ca1c673048a0e	1684051867000000	1684656667000000	1747728667000000	1842336667000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
165	\\xaa7596fbad0bb4ff7c14e3b7d5432ed60621c975983fb357359691cc4ac953d2d2092146eaf90337fc2f7a1be1ec1ad72a9dc105aff4fae9466c52fbf7004165	1	0	\\x000000010000000000800003a8eb1fe3f499293d755a291db944b5fd45deeabc28f28482d890e326e951e6f26ad6f1e13310c34be0e8ecd70428846014663227537dc54437aefd32ba14a1bad3e5ab50d761df220d02193ab9a2ac94dd4eb30a427f5f1f57ae4a97a5efade5a91f15f6905c79b41a259a6a06efb202281d752634c2731dad46f63116379857010001	\\xbed771e1373313346d4111fb8ea57d0f1b900eb8c6bd870687690be8386603400007a8a85b075cad1f979b9e480993425ee99259b0b287ee7085b4031d21e90e	1666521367000000	1667126167000000	1730198167000000	1824806167000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
166	\\xab418257b715adee01e12cd2a63df8e04f05adae2c76e3e4c251954e813c7b4cf27e361dffc269e5b152397623374c9fb4e879ac0bb21bcab8449e2bb4e88436	1	0	\\x000000010000000000800003c6194382355927837e49e78596154f21c2e898598ebf87e883bf0909fef9050652ebac85729ba108cd0e645a9bcb1a36e2f946e49f6d39e1b8b8e687bcbf44c6b437c49ad975c15648ceaa9c0841c45b0dca92a10654cde8903e3b54d110288815e9250507320a9d236a20e4fb63c51eba5b628ceace6eb11ceca7e040992717010001	\\x4c73dc4463beceef86d8df946b6c6b2fd2b00cd21f02fdf724f43dc23124579e2b4a63179a13c4f5ace04cc925965e5ffbd115cb2f1278fd6ae77659e6fef50c	1681029367000000	1681634167000000	1744706167000000	1839314167000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
167	\\xab0de7301dc106cc2b109f080be385d77706933cf06f8e28aabf3920ff4a6487736056d7f1f2ba7c7fd0c720626af5ab80d02a9e56a244d8cdc47568b9dbcba2	1	0	\\x000000010000000000800003cd76a8807b5634647d106914fb608637bb30fde7a94d83716ff1a92d7678d204bf2026cb80df57100acfa53a7322b10104ebf968705de1eaa09a10887d0d044ef446bb8094a50bb12695906b7c1b1962b9c38155ef7f5880ba77e9348e8aa240584efca1250083decb38080d05dedaef3bc9d055a306cfd1ddefade775bf1bf1010001	\\xf539456874fe4731e1e0631055db1e9151c7f486197677132b25d1e8e8d0040cbbb0adc09ae1a79cf24aacf5ba72786ba5789dce4a75121104ce81fc936e9c09	1675588867000000	1676193667000000	1739265667000000	1833873667000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
168	\\xadb9eb2f72b2f07ac3f064503e2ee21f5b7af2f473c0afa65a330acd5f3be27c69facf1d590d764359210e710d7e5918083f35880242481de2d64aba4d5d8b22	1	0	\\x000000010000000000800003c8aca64b5a85c3886e1ffddab53e9e648b78e30ca44fffc5be1d8fa4cc0cc78907fd934b26f9d08dca008e228af3990ebc10a915f18b77976313a3a29ae69708f54804cae174df5f29d8f4403e802bb5173632b31c143654651d00177b4ce4ac670865c2409e5ce34a7664c64a268ae4a85de86c46a97be084f98b8e0e7a4caf010001	\\x0beb373f8c848da540ae6ea63617bea2b53f340e0b0e1ba6b05a2b051f83dab3b0793622eb27c1763e063c89fedb4dd86718eacb6e7b4e5783671cde71e17b04	1669543867000000	1670148667000000	1733220667000000	1827828667000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
169	\\xb02d8390a5ce9959b6940ec6ba2581fa691e98a589d58aab8462d21fd003a3a6b085d66afd7d6d6093369584708c99fc96d2153ae1f2924d899a2d7182af3066	1	0	\\x000000010000000000800003b22a623e2e5b2654efb7a7db01eba5f347cf16ac4a762b5b3f790d1517b910ebc4b974237cf56e489a14d2937ea3a4c56cc0dcac3c92f7d4ed6a3bb345498d11e73f2f759adaa1183100d4ee5d4d937f8156f7d84ff4d5e203e8ade0fdae266791703c9d70cfb937e94d8dc716d55311e1b988208effbff5907d734a5c9d5223010001	\\x37d4280109d2788e50f396fffd945c5c41056a2bf7fe6555ec3588e31e3e4abc674f08a19155da11cfffb8c8421bc78ec32a254b6c57414202e7b82445215403	1657453867000000	1658058667000000	1721130667000000	1815738667000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
170	\\xb1812d95c20e8ce3a90575e040c49284ca076daa95bba7778b4bb9d457a6c281b8053e8717838ae7cc69917300f2e17f94bf4acb666823fc45aa0851cfe0db7a	1	0	\\x000000010000000000800003c5591554489b94dbcb865a1d7f41d116af3b1ad996238271615e85712385d80e690d96797d59844049506ecf865063bfb73b74d8eff02efdf16f3bc2871208dc155a191d29005305e70b87694e8841cfff73b6c391bb5240b224635b5a8e843e8fa1b8040379ef870195b5654555579a1d27ad87eb2ec8fbdc712e34f6b1b2bb010001	\\x16ff7558a2096f7a8ab2ed7dbda8006818a428fb7a970701ab209f19a5f07b50098a8b24a3f6d45e3a53ef1aa1c6ee61658282ec61246878fe78bd54f2317a0a	1686469867000000	1687074667000000	1750146667000000	1844754667000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
171	\\xb3057085d01117a4efb66a5ccf22731806b428795c1fc2dfd36bfd4908e4e5f78d404fddc459d8d29c64939532ddab26cf454b79e95bb67a286d95dde6bce61b	1	0	\\x000000010000000000800003e3719c1d4ec3a73da339504927bd40606a197c8c800aa498550c80b9f56969eff1b3a4e0165c783aed349e6ec7586a424164979a27ede5486db1fd5edbb236807ae84c70256b432b23e92a19fbdc7ab9a8a92dd91f5ba1177cb6ead9e199bda22c0528ebf19856c4b16ed6edc2c563bda5c0bddf348ab330bdb1a8f4edb65b57010001	\\x01af0e5bade60b3621e156ada4678d015530254cbe1bc26ed468dfe84d60ce119370ab0dbee5a5ed25eccf8f00d0bb63edb6f4fc089923fef0f2657c7e99890a	1679215867000000	1679820667000000	1742892667000000	1837500667000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
172	\\xb7490537768b043426fdbbc56c08d3941ae1f4d3d6a38e16c1cda551e7604b110aa90b554264a82e7f157b09b7c4ea14f21096aef04498febe54d24d91ead13b	1	0	\\x000000010000000000800003b11a387a9dd89671b39a0a79e9b5f031f31bd9999552bbc36d1ad6a3a4cf80b8559d2a068fe059dcce436b8fe8c0b7c6288e29575b50e28bb259d4b6adc0e3681d0b7ff2d1ed72a635a0c6760a486d2915ade8ff646817dc3fd1935c3c9d32032328e0b56f1b64032b99d1b498754fbc0cda04d21a949bd2737d91e180ff7415010001	\\x90119f99b3ff35df3c10255c9f4dbd46eeefb8a15ef46319b9befbf815ef9d896a5064ecb176ab5bf40e43a4a42aa799ca38205d57b7db8abf3fda8805687109	1678611367000000	1679216167000000	1742288167000000	1836896167000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
173	\\xbb25bd72ad4bf9c5b98d00392ef0cca8553ebc8a81079b752086a9cc7c156bc24c21f2724f69fa32450471b49234779b8e8bc8231212e64b7e4d72c7fe359984	1	0	\\x000000010000000000800003cfa63fb57955060f356163c575485d32f36efbb60fea95e11bb5b7e6a459ed8dd2c61353ddebc4f5d87d3856672a3314ff6e5ced2b72b7bfdc5b3f00bf3a3aae741f84c7cf8f1eaf731601955d13253ef6a6f5ea3ec55eb6d1fd0212eac286a766cf90a7b442a5dce7af1466b4295c19e3cc048be3686fc4416c826b0d03c4db010001	\\x809b889bf777d4c12c144feba597690c996404c7c7de5a66d54badf63a8decd104b64ec32c758ff7bd0ca758bf26190d35711e204ae2260037e1e71d4f343205	1683447367000000	1684052167000000	1747124167000000	1841732167000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
174	\\xbb191acc901b87ad875fe4a33ff747efb51b1576b7a1b2db3a7e89f8ef393916f855725a2c6d5b336e21c9a4c001fefb2aa730f205e2d29ed30fec2b78906900	1	0	\\x0000000100000000008000039a71ab37a3d6c56790ee290318fccb956f93591d73e7eafb4393907aced102ec0e2ec93fd1224c5439ad99283ffef46359e75574e5a14c6cc91ffcbd72ffc4eb13379577f8cd354398ce60880d03506b39c0eef15ae1544944c8e1164228a72610923b018e43a6538299fbcb11ba33185a5b166db49c6c42432ebe0c825e437f010001	\\xd4d86e5907d9bab245a1ad866c468509b8a2da11c7098f66c8bf12adbe95037e6e3b31e284dfc9735b0d927e25fed8ed218b4341e63b6eeed884638fa2853d06	1674379867000000	1674984667000000	1738056667000000	1832664667000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
175	\\xc4791a4697fc6e0ee54dfcea59c39577de50cb02cf421dedbaf98bc07ff95085494f4561b86499b31b665d76914882422665377649cf84731c088abca5933dee	1	0	\\x000000010000000000800003ca5df15a79ad06c85d2e0e190b9fe07b96b13c781d3a579542a11deb7c13f871cddc0708605f7e826ed37822b6e6677c4a82a54213d4b00c659acd7526135d6288c7c2f4444f9a76148b9132be837529bd905a5ade835586fcf0980787d5aee63f6f2586a1933dd69f488733b5c37eae8a599aaf4549b0933a74dd15052301f3010001	\\xfee89dff0e54f3f4b8fe90988d98faaa69378bf8a07a0d6e9a30d796404ab546aee9c2ceb043cf0991a219aef29b3ee8ceb20ae88cce60ffc7549810e3931801	1682238367000000	1682843167000000	1745915167000000	1840523167000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
176	\\xc42d397a177ded0ff5ed0c13647caa725bd336f91867469e839dd42c88be746f8fa6f28134eec0604cb85bc6c588419d19a90652d1e2a67a9efa456cb1b940a3	1	0	\\x000000010000000000800003d32de56cb296c41260096e52fd98c7d0c1ce047bf0ed18b05875e67836b79eea47a70b3434e07077cb4e4af8322306a3eb95630ce4e9d256d197f1b04c26fcfc2b7bce8cd907d3116afb2b01094110081dda39a38ee44e20512489c0745916da7d0ae8d582f86b0c80f6ae6bf632c16c50c724089ada1924acef402f9e1be991010001	\\xb7863c7c98e470fa10ed12461b15812b1d3dad5ebd8529362a375ba934b9b8b5a99b18db0318e27951e6e9fc88586ec3c988843d4b7ed306c97870eda15da203	1681029367000000	1681634167000000	1744706167000000	1839314167000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
177	\\xc5cd22ba069e748d8bddeb1fcd4a43a5b21f42730ef20f2789452fc73333cbd5e159456269c1c28bd3c962aa834d18d79a93e70b0d6b59d633c3c467142ce00b	1	0	\\x000000010000000000800003dea77b2ce97b8a9c950ec1b61c201b61fc41334a8aedb2f9e17431ba5a3902461a75a9f1b2ef1f89bc0c0701ab201b2b86627575279397e8666fa5f5ee10b5e2727498544ef420c7c602189c2d4721fa45d4902009ba55fd4adf9a7fccf411a4250029536cdf00c6f91114635cb3f858fb6b13a5d989311269f799925b257a39010001	\\xdcf549258925f5a34f9af89cada05213965494973024a3d0bba2ff6220531ea1916cccd1ed34af1260cdc34097f58210e73858b2d592eb71ce2aaf226abc2b0b	1681633867000000	1682238667000000	1745310667000000	1839918667000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
178	\\xc89de1e180ea11ff81d1f73ceeee0d73f3085fc525847a0837cc23131022ea4b3aaec97d966a2cc081ae9ddbfc564a06b4a6c61cf4418c3d7524c44fb6b68cfb	1	0	\\x000000010000000000800003bcd87b362dfd1659f0fe75490b6073f5df5fb2800c2f782bcbc944ea69080f809d0af180a030819c27a740f99013cfe06d07324d024f1e2841490823859df53ce6524b9713e4184295068e82f047fdd149b6bf09e7740b87c8c57a6d6014fd0c00bfda7a19082789b368a0695a4147f3c11f7121aeecaaa0701f91258edc1e65010001	\\x1c2f49f9e50cf4d83707dd1cdbd0737cd73c3a68dab95026b535b3417272f283b6a3f0bf2b50bd9e8826d0b473ae139f879fc8641b1da6614c44eadf710adf0a	1655640367000000	1656245167000000	1719317167000000	1813925167000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
179	\\xcbd10b5cb738230ecf9a174d8bd44f89ef4a6a030418e695edd52d8c783e5aa126e5f65a79678cb9e93cc7acdf79ba831951e36f011c2ff4aac4e320493a709b	1	0	\\x000000010000000000800003b64258f531113a0a5334c4642829d898867d5cbbb33e51b60db1dc5d445ec45f98b7cf5c55a835677d234bcc8d719635fcab43ab7851a2dc5fd185dd6307a0700134b489a745fb1c52ea843df27d0a2c71fb876805e0576b753f8b36f29b0e2428cd6be07b70b01c38d283393de4f0b8a70ddf7d1970036758e701b74a943133010001	\\x0f77bc38e35ebec1cac00a619f1a176f97854858127bbc85d753a2adaeaa627292a34ef621e2bbce6b6a20f17ff5626681a3972e5d6f19a63616501681c3190e	1678611367000000	1679216167000000	1742288167000000	1836896167000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
180	\\xcb0d788e8a12ad6c1e73fb78de8c2d2a77e7fec9c768d1f664d6030b5bb0cd77006249a86705fd56b961082a6d3acb0515918ae53d77020f4cf113487f808275	1	0	\\x000000010000000000800003e0d53491c22c7a0836a38c0091e6132700f6ded768a9db7f58c877f3cfc113c883255b52b9db7d287e08f51bab87d72e4426ac388f3401c6566072e0d6fa6b071f7f87a5f004162556a8826f29c82b4da37491944109c96272af080c30f1048be527a5696aee6ce72b4cf7556ea94271f4cd8b8ca68ceac50b4492b0208e3d01010001	\\x92e5a1f945d8fac44126c9192522e143dbcf0fca7be29ecb9cc300e89f77ca084499877ad07f84eb938a8b4251cd2588b1512e98200ee72505a6afee911a390b	1659871867000000	1660476667000000	1723548667000000	1818156667000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
181	\\xceada1eae8f2ff59608c1fd76139a353fabacb46d79d574fb7de96c47c170bc2e306cd6e3a5a8d09afde72d40b308459032e364ff33ba25a8cce356634ef5aee	1	0	\\x000000010000000000800003c53740c012a194631f4b099801701a95da3886aa728c94eddab0bffe0e589ff62a759a782be7e6c90cadbd74149e9792b29621bbb4a7b3e7c753ffde6196bd556ae6f8560d43cb386da500b4f9a85358fd6ef669fd1ab6f0c77e7d91ffd98b23fefc2d4224a6617aa7e35605452ceed117d0f678a44e28ebf8f386aac402b0db010001	\\xad15c65978cdfdb0b1dbd455f653fc28d1db2aa2e69fd5996c553cbd4b552179e46a5e96b2b3ed9d730803d7b6c7cb1268230f3abf2d41332a33325063988c0a	1661685367000000	1662290167000000	1725362167000000	1819970167000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
182	\\xd2712769942681357f0b3462253d10d02016e5b91044212b75bc1fa884fcbc1c6ef9ae17595565c8dc96b7ceae4dc8773a71c3dc08940b00dd27996757eafae7	1	0	\\x000000010000000000800003b12fc115029b34ff33a3549a63d65082e5f3715e3b2a56b10792162c13164ad40fd69942edc1c12088cafc39c4508f767fa1e422da20c435e463bdeab964c250421871d6c43b079e47f5ee05d43c12a3092f48eb15692ae8a302199c9935353388af0bcfa44ac4025f15b308789b05dccfdea6c0e41e365aeb683fb7440483df010001	\\x311b662751ca1ffdd3f6067b5cac212accc58378dee7a1b3fabaac247cdce0ea2ba437e898a11c8d97f8424283083a43c3d471a8235e0580a59dc7cb0e15e202	1660476367000000	1661081167000000	1724153167000000	1818761167000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
183	\\xd25d04b7045f5060e86670f701ff63d9ba8d3100091bbdea457168cfcc3ab9cbfb29dcc24f718c1c11a0580187921f0c87ef31325cf4f8d40aff366031bb21c3	1	0	\\x000000010000000000800003b3c387525a561acb5be802e49e4c898f66f9b4095a2e0f7c8bdd5ca91ec3cb77996895c2afbd93a72d12261904d42667b44f58ba764bee7543e39d660566878ec2b6fd114b5e49b84916797944f68c6fefd540ee584f131ebb8a4938d8281d89c89859fb4d64043039d90b6fa9d1caa127701172a5be991ced08b52e774d9d79010001	\\xcce1af14b8b70468250c2b22d8f4aad94810d89a436af2b38c77f686ba422200d9839eefe5bd94b1a51e8ecc44d952ef2456f66317ea13ad6eebded60994770b	1661080867000000	1661685667000000	1724757667000000	1819365667000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
184	\\xd4d5410f704cbacb1d5ced921b29e20a65b651a58ea6e7b46efaee33d31bbfe71d72237a77a4207920b802645c50a243388e886c8ff754c24e7b29609a7579e0	1	0	\\x000000010000000000800003b6ce294ba9d70943672be329f5e3d6631004f77d80608234de9d0a3fb77aa4c12ceea132d2685fb1ee1f454cad7f7ed36f93a532c51ecd17c5fc5c633be3e8db0c4b0f76e10d42de621a904e3d8112be476138525ed30e0083be719bd9e68be5bdf9ecd9c75da25907fa212565c8df5f19228fc920b312999d82ec8edbfacf11010001	\\xe6e8ab4a26ac771d4fd46a8929e3f71985bad83a036f76fe94546e1edaeebd5342d4221e38c922e5d5dc919ad4c8b6702594deb9df2636d03834d6ffabb12205	1682842867000000	1683447667000000	1746519667000000	1841127667000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
185	\\xd4f53caa47346b89b8270ae073bb25fe9c9de4827e3e16f550279e6f04249ebf2976f0a4ca698ecbe8b21777e53c824392f9a4273e3b4816ca99c6d0745c01df	1	0	\\x000000010000000000800003edeb3074f7407daeb447836d808c2293f3465c562450d236134c2114e73508a113680eebebfaf595cf9e2e415d8957337cb07fee0af48df087b9128678b336d4675a9dbf76aceca9511bbe21136cb024dffee27b8c35f785acfa27dee47b4662d62c95c4b15d918207e7c0900e123c2d0c213ef00684e048d88b6536c9315a97010001	\\xca90418e1909705654be3a4a0b3a5e5d0fd2c9e98f04357a2638296430bb25866947a0e334b86183d652f5f1c74c90b2bd2294ab1bff4b062630b7cb74d7f907	1676797867000000	1677402667000000	1740474667000000	1835082667000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
186	\\xd7fdbd925000f82d8c8b0da1fa64ca3c286658eb750c90448f403e62a75cca720a1d844aaa9a508d106f594ed29bfa91ceb131d1b1ecda4f77f8739bde0e7bce	1	0	\\x000000010000000000800003c6ea6c19bd7e0a9734c3af7ab599131237e4f7c60d49b0d4f94f2e7524f0a6a41f203fa92f334edc38b75a625568bf2b97962f1f9cfb9de9da36aa6235264f547d53c78baaad5b5970256dc9d5c99885efab86a3c1907c77aa19b58f60dea876e48d0ec9c310c7d8c2c45c038a83ab9f1d215573a255c10106b14372bf7a3ec5010001	\\xbd4510822a2e0dd5046e0aba2c32aa8ca2584fb624b8af820a1e98d59b39ba4ac438ec3bbeb5840970da4346f47c82ce675545b1087360d7efe264f3e3e2480e	1671961867000000	1672566667000000	1735638667000000	1830246667000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
187	\\xd80dd68c94276e5b286c645e8a76b38e657dcd388150bb5561bf413a6c44f16ee07138092a29aa4691090728fc78745e822e75e9b79521e148402db861c5bed0	1	0	\\x000000010000000000800003bea60f724f8c9bf1fc049276924a8b96bf4c1d33e4172fb1b8bbf70fd480a8d2b9ba5724d40b15a653502940482b674d63bf585ad7531c66259d49639436bc043f7f70cd642a4989539a9c53c18b44da518949daf68cada7304b84e8c0b0402212b7feda9f2ab8aa3afcb50467e84337a8d479ae486dba62e5fb78cc271a735b010001	\\x07f4ff15c2c0b46898a82ef1d99297fcd0da5d784dea50a3760a7fe70478defe581736cce38432850e2ad7c397104efa2285f32b382168d06654376063ffce0f	1662894367000000	1663499167000000	1726571167000000	1821179167000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
188	\\xda8dcda8cc1d586b0301e2434ff1f089af1da88173422ea2ac1a47bce871488181c355414e8a9588a67c7a9763a2c9e3e3085387533c49ed3674922c5544c2df	1	0	\\x000000010000000000800003976a37af67ca407d58d50e002a8ca8c70dcb8365f00dc6a601bb12d29c46c6e28c6f0d983d0052507aa24f60860fa4df805c4ffc79ab3ab442e141afa61c19e120116d8c5be3d9743777d8b8713b739a345ce82735dd603819658a2048c923dff87334178833b4c7ca79cda25d9b9ccb8ec067a21da6b64660baaaf2d63d07fb010001	\\x8fcbcc34524e24f76ef45da47d82ad7c32f2511814823d9a57b2a9971a8a58be21fea2c3f2af56d5bbd6cc4e57f8e6eaf0e4530ecc4e9d47ea3b334a0f30e70f	1666521367000000	1667126167000000	1730198167000000	1824806167000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
189	\\xdc8107ccd95b47c5c81d0e64ad1a6d81011c3b27baf67cd56c1ebe5efc42cc3ba4377a238172f440abac56f16e68421ab0fd1442d20081e75bedcf0fec6695fc	1	0	\\x000000010000000000800003ca2d5d3f5bf17dd4b1057271287c487563e70694cdecd5f6fbae6ef875c55e17cc57124faa522c93d586bdbb34afbf81930ebd6e1f797a5353ada1d5ee7e16033ef120bc725680578e6c5ec909526eef7c64c4ef3e7c615c4f65ac920b95fa4a6ccc5fa1d5262cacfd4f92493099e56764e6789d67285488112a169f616625cb010001	\\x6a76fb6d5bcb407db2513d8745ae6f97c23252e5486a7610563ce698ea8216c325711ea98c2f821da6c01a1d848bf4871be3d0049c5311f0cad4e8b2c2cdc906	1667125867000000	1667730667000000	1730802667000000	1825410667000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
190	\\xdda5883ecfaeb1083241d4fb64ad5a8c8bfd0772e59814c81e88f47eb9e6d5a3a7ae80ebbfaa6c2d879760b4b312d1341bbd0fc221a961706cae18bf43705072	1	0	\\x000000010000000000800003d94c78cfda0fb4b8fc0ee1f18bad5317cb283818cb81783eaad5d877e6b90271aee7a51686834a7e9fe30de1a25cdbce1f39e8e068bbea426f00033cda80b82d8eb94e89149e875b7bcf7bdb615d1d6930bb5d0a79cd57f20fa92d921bbacd67f40a4f20213fdd7e1d43669c4b297f6a098f7d6231c6ecfdfbf7a0cf9e33c5c9010001	\\xcc7c2766ec036a8a06a1f1466cd793d4e66d090ce2ebf27e00b6e858b6880c6e54f7df72b1bd7af3c02facafffbaea6d15ebb42ef6c3288af02a2532d465cf09	1679215867000000	1679820667000000	1742892667000000	1837500667000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
191	\\xde714a3860ac78202de1d8d1edbf3c82fce2ece4a7dd6ac8c7016dddce6f1748561257480655b83d8eeba2526a09843e82ee9875706a314e38383b7ffc4fb73a	1	0	\\x000000010000000000800003bcfb75d98d599f3b24882434d4a1ccc7c2611eaaa8b1c6c27ee20f5db2c795b1ae02f262949411b8dbe4ecae8f23b394a5cee4eddab5afc41660d52323e9fe4a03634082191a81c72af9770f28b228e62e61a1c3719f323dd7cb64bce3f1955535a25f02db41850ff29c2945f94af79b19198a25d9b0ff70e70286c7f01dcfdb010001	\\x6008b78bd9fa0ba5b442bf32a48dd2091d43b05d988a0f36f75c36983363f700e59212b46fcd94dba5b0c727a9deb96ce2f06a160d90504351d60bfceea51301	1661080867000000	1661685667000000	1724757667000000	1819365667000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
192	\\xe4a55ea7b3ef1ba025d559653074c5963d83c9e40a94ba28f332a7dfdedf8ba93d4a5394110a26aa4be71d8c22f178f422de007b1ea004d65cfe43ccc5e053a8	1	0	\\x000000010000000000800003d37afe1e207e2f5a11073a947847b4493356b5004da72813f6d33035ea150c1a9b3ef527bc23774e05c7ebf5afbbfd9c5004b15d6af0b38e9e8eb1b8868194cc02fb09f5bfb5ace6277c003744a414b7dff4cfe6da5256bcd55fa312ed1fbcb890f9194bd60a110f4ea0b387a1ee483f51a5c7084f48cd6f24c2578f2fc306e3010001	\\x4366c8f4a380b9000543d8a96a91463f8e10cd8a28c13a6ef02e145d626ab4c5e97d4fb0e240fbfd5dc0199b786404544af2a58c7fcc74a5d8ed2b0e87d5e900	1670752867000000	1671357667000000	1734429667000000	1829037667000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
193	\\xe71114a4407c947558332131f9339036caee54d5c190af315888d06ab5d60f20af3397837e9467c00c6f66b082c72d36cfdf5e9105fa0bbfb59f89048cbec059	1	0	\\x000000010000000000800003caddfa6762c88ecfbb2eebf76d69016844f22ba2a60fa59e0ff08c7964a8341ac173877061a61a903664f9eff7b9fed5a73ba3611d4d792cee0c6c904111c9f1baf2296b8ea2bb1231e666001bbde88d13576e5b24bba238fac5ac726dddcf9bdde51433a27a2d19e20acfe1a7bba95d9bdc9aeace6a5580139c4e8a6de62ae5010001	\\x9c60d1fea09670d51c58f92a3954d4d86a46ddb79d82b83bd4e132f21af1d8363619dfa5378bfaf0a5c525753da1338ca4ac1c8bf7110ed43026e9bf62f4e40a	1669543867000000	1670148667000000	1733220667000000	1827828667000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
194	\\xeb3112cda81f8990122614a91394d0163140ae659da585af1fffc1f3b1add490501ff63527678257c6340d738573474d4de0f65fa4ed2ab0716c7a98c3a8e5ff	1	0	\\x000000010000000000800003ac364ae2c37395129222f94738a52d0d536f21e203499b799d56fbe54814aaf1b78f4396797da37b4f8d99e3106a062a29353c33942ac602a24fcc116673ca4ce267630ac8f5885e17e2cf468e92e08d09099cbb45d9632bbeb55a2b6edb77ce48b47130603bfacc13a1621ea7154fdb181879962bfabdb10c5e0449effbe593010001	\\x869600a24af20291bf6aadeceefff8669b837cac7debeb9018a763a858a99adeaa0e1dfb7bc94e6f09a13939257fb55ccfd4e4bdaea7b3037af887510884930d	1662289867000000	1662894667000000	1725966667000000	1820574667000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
195	\\xeeedc9a9b6c6660f94330cffbede2144316356d027bfa2de6179b6e43591d030fd87792351d62a02867e976321db3df1adbb8b6dfb9c5bc780bd852db4b57a19	1	0	\\x000000010000000000800003ac25852b15ebabc9ed5c20a6c110711ae853d5433156da8bf03a0f2b5297b4c4d095d84b35c19431a99cef4e4295e32403ec42d70357df3722d11c24e0278c5ab99572908873e64369cc05562d91243aeb3e950b469ed0e7e5b58d1cd3eb798c21d83a646c2418a4eba7daa03f58be4a36bded06dca4890f7b8696bbdced90cb010001	\\x0a2ddd511742ae03d9a21fa48bdc97830588c78a607459b12e83840cb39cd44f3511c0e55e1957fd414a604b7db1827ba55e297ba7bdfd285f7278a854284203	1685865367000000	1686470167000000	1749542167000000	1844150167000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
196	\\xef79cbcf8c014c1053f16eb81ce640910a5d26e325c1cfebd81ca2ef050f0ee19ee75a5894e1ed90167c51b749ffa99d34b9e730e3e36350a8725aa01f6fd1b1	1	0	\\x000000010000000000800003d0a5e7b7ce9ddf9b2e0289757fa729e80279cad3d6e205b101dcfe8a1ba1a6021af23e31b20ed34944fc37e125e7259656d0ea1abf47b76d84ee921c23a8c14a671bff0a01d10fb6db40308f5c49f1da2cda8067e3559eca74084f25bc8a7782064e74bd4e09da35362ba1e2a6f81e1896e723a53664ee33243bc5678e7032c7010001	\\xfd4f2dfa0df9661d6a8bd377abfaab901dddbc5c6cfc3a304154370f5985a825add2686bc0aea8d283bf21b3ffcf1106d6fab2102331ccb71f393135496e3206	1676797867000000	1677402667000000	1740474667000000	1835082667000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
197	\\xeff9806f1dad8332a2ffa4e5ed32190c6bcd6044a2102b1e4d7f6235dc48b2082248f063aed388af5620f32ad623dfda50ab777f9f0419b2e629b03c79b82f8b	1	0	\\x000000010000000000800003b05c81155da5bde7bc9b231e29c00b9d64a93ee910415c0d639a5c18590e341cc5019298dbe529fdfb85fed362ff5d1c6d79ae3518d2c0ee5c4fb7ccf931776c65a1e3951b45d6b428e57878940f733185b1ca6af492f5cb3f98a9fb6a7448f2c4cf2017ff005dacc4df38363212b98a54fab9f25859bb91de95b86576875d87010001	\\x245a9b599d282299658177265ff007606a9154dceca4f173ad0d0a5dff839eb39e7f2eb1821c9072632d406def4a898ae9137bd30be39e15bc6b11cf996bff08	1683447367000000	1684052167000000	1747124167000000	1841732167000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
198	\\xf1d9306060c1264396308e34e0fec9dc38029aafc99baf7cfdf61779b03e9f421397377a369c26d3c307905f388fb2675a480c622d8e8447a16f5732bf9f6c31	1	0	\\x000000010000000000800003a8644899c0f30585cc194f9c3fd53eba8314da0bc24803eda743eae5d7bcc13d19735124896cef76206a8c1ecb5a70b51e9a1c1c1a035ab53219bffba02c1f1b5c795d78766d27961c4ec23abb3b464ddf36f9c20ec0a90a0b9e78c5ed72ffbd0ef0949c0cf2495164377117c3292a23dc0145abe878cf198eedb6ca1172679b010001	\\xb6162915a590ca22aa6419673be0d1c4609940c23d2b0237f680394f729dacafe8abd6087909856eafc72e443376ca55d6ca48db9a1bfa5d36be2e23889ca203	1684656367000000	1685261167000000	1748333167000000	1842941167000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
199	\\xf1a5607fc0eac2cb8205596003a06acae1ef4cdf39345d596a9d3b8b3a50df6980ac74ef3a3291a68dfcea1800ca079805682719c1605bbe9ab56fd95e3ccad2	1	0	\\x000000010000000000800003bd9e916415e00af539a294d31b85e5c116eb7ac2cb2fbef1852c37612e8ced8cbe52c1ec52809bfe542d7a7c1e8f863f84d793f9e6d188c1b764640f89b205fe19370d5982dbc6ac0785490c2e10890b888438255ee43021f6b63eea6e60d90b867b3c389b110907149b26a5d8c505fe83cc4a335dd936cca6dc090081a70c29010001	\\xc65fce06cbe17ff5d59c1b3ffba50444fb212aa30ff6969478d413b04afbb6764b51821584139828a176e4e58269c0b9ad9295292709183453602c5036e21802	1673775367000000	1674380167000000	1737452167000000	1832060167000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
200	\\xf18d1eb13e35e5a08fb4d6dce186d857ec0e80aea12ec8bdc0068c9b182b18c3f0830fd73fe7c01fb8eb7482ae9059898a93f787812526f6a26b4da1cbe62a91	1	0	\\x000000010000000000800003c371fdfbf3d3f57202b59c14e43a724fa10cc87b05d8dcb1208b82ba92cedf65f287621a50fc4ce746bd5276bef390fe57178a4d5f5ceabe931e0c3fa262301856b0269e7dbbb2d4024e70bf8804e6fcad8c25eaead87d8c99d4645bd0089f803fd43517dd3bacd36db0568637d792e6b97b6da80b453d9069c9a8c18114620b010001	\\x2ba3e980d0542e01aab3330f92a9fa804f3ac9c4bc327be46e0daee89a87e2be7892570740d82c7a8795956ae8697f6388a4fd2804e93ae798d932b633e5850e	1686469867000000	1687074667000000	1750146667000000	1844754667000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
201	\\xf2ad562c98a0b0d283f3d37c27d6e7d93b0cbc0a474963d14f74e7b94c8ea280a2d65755a5dc247760735474f3cf0613595c0bd211d6d76bba11199a8965076d	1	0	\\x000000010000000000800003cc88e3539033302a15a3eef03855d0066b7016a149153a01af57dfd4eae5c59da21a236287f8371af8e0326b46a8c31c2a47c723d74ad2d1d01dc7c100d380ff05f5456b8010707eec3df52196e9dd2f6789fe9a74be540eec020752bd21ebe0d924d7a153bc9e97464e164ae5f517f4ad1065be6c2a5dd859b41ae4f6f75943010001	\\x1795a02d88ac1a8a44f98fab427050e0e5f04e310228312b18b2d1ae43db98c0a56f698a508d0ab469e60961ae8729bd24b3af2fe8c4db64f62357a33066820f	1664707867000000	1665312667000000	1728384667000000	1822992667000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
202	\\xf2e111a5665a172ad26067ed2dc8fe0cdb57f854617fbb7beb01b474dbfa8fdfec0e06a3e055d1369c1851a701917b3267669803687e478f7a86f53e242b8011	1	0	\\x000000010000000000800003bb397f6d9480d652e8b46514525318ad71c8c8703d252901876357d1559a8b195b8486c5b19b64bc2e7dce23bc33b8f2056ff2779d635ff1b5ef9c826e33e4eb7766535fad3477f60112d2fadcdec53abee2bd8761ee28337072dd2e51e0cc78f1a3986bfe98a8860fba3c1be9b3deacd2058dac02297171ef1047daf2391671010001	\\x0b3549248be140cd7886b931fef03c4aff2bd3faf0b728d7a88e5fc4f97480e344ba1301f12ce91c91a12967a1d70f1ae8838434b0fb97d52f55c4abfc69790c	1659871867000000	1660476667000000	1723548667000000	1818156667000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
203	\\xf3a5cb21772b829f81e9a4a25a223679c120c2f9e4c79dc3035b49b27799cd1739f469324434991ed452c694d9574b2e23a2df6b615f98ca8327f4c5685b1763	1	0	\\x000000010000000000800003c6e317b99834ad6b87965b31aa38bede7dad4f304827015394531ad378c42654f38cb9221dbf2ed35da0f317d7deccb8af4083e91cb3901d20beacd7cd651d3f019a14f670975c01c8d78223f894c43979540af85ea0291e704cf10226b70ce6736c8345e33b383f4cfe16344ffae6a530215e8179f4e90fd93face240c65a35010001	\\xe37a7f5c8c4795651a08b243f1623b80bebe88088e0ad881cab97c26952362973293ba91a532e97f8c3711a4c431877261d941bcce1d5e36ca54628b8d16bb03	1683447367000000	1684052167000000	1747124167000000	1841732167000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
204	\\xf3653859f56ed20ac1400c76f7a94dd275ef3d03e1dff130a0d35b9b426c9f98e0d515a0b3980c69fdb2008511f3799596ef048f0c6120bfdae54e3c0c37e942	1	0	\\x000000010000000000800003baf400d69a6eeab29e55741f9a46f06175eda1af59038c3ae9f61f620b51cd141554ce27a428d66ab86a48f45ead7b497b954f49b7186d7c4bc8b31d171877a9f07794e67762109d46bd6850441ad65a7208788f5c8e5b2a0845954a1b54e2e6d58eba2f8fc58fa7b6b151a35db2c99ecc1267aa6bf8de2bdb2c85b638742f0b010001	\\x6cb747f142cce1e95a7299bd3e4a1291bcfa8e7b2faca54e2fd6e16950e12a778ad603072da7d72949633076d8a7fcd109c742e46b9442f6076a1666ad49140f	1682238367000000	1682843167000000	1745915167000000	1840523167000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
205	\\xf35568db2f35b4190669b9ba188e35b539a0b035127a33cc65bd3e74f1e8f12c24f763812d37af70a66413d92a4e08a8284cbf98719c0e33d225b0205cfe3f8a	1	0	\\x000000010000000000800003f36e7b3955dea99dcd14cb8d2fc14691ce1319942a443437897dc7c07c10090dfd0ce25e7fd423fb83e50b9db202aa184ebfe56075955f358162ec6b164291b591668a8bb20b744a62957c945ace4cffd03b4efde09094ca0877d593f4ddd6a787397de774be73d003fbb0c5825fbf809be46df1a4011e928d1115f4b6f23f95010001	\\x5f0d6f953747cb6a1f9bfe5666645f10385bc8c9dc21bf402e51d1b92f5cebc5cb339a064079b9250314ae9a3162a0e71b2309d368b3dd0b58344f03ba83c60c	1682238367000000	1682843167000000	1745915167000000	1840523167000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
206	\\xf3751246ab836dec1b8e90286106f5a205a39358bd347613fd05aef2ef9e3e379d68cf0134481e2c51f3349234b9a4309c64508bd9cc0c66db4c0fd091fc84f1	1	0	\\x000000010000000000800003c853cb2c390429f2eb98f66f599b40425a50fcf92448ee7e129407d7513c4ef92bb8f5c59d99a1746e6277da5d4ca46c25b601dd583925a62314840ad1ba9bf1c3a84abcca11a4b6f0a581c85ad261dbd10e6c2773e611e2df75f99089156f49d4b8e09c0256c05ac56933d2cdf5ae6fc38c9f2bd8ccd7c8744d501c154de0d7010001	\\x0a9f226732f882a87ebab8f892ee1262b490af1c0e752221b2d2777d7b560d0927395fc533018e574eb63b04a2e6cf681740ad1d05464ba6201d85568cc6b70f	1682842867000000	1683447667000000	1746519667000000	1841127667000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
207	\\xf50d7a5c9f0311a727ffb5cdf88b277ab01f681e7fdc3e8a713c675bde920beb22bcb4293d5d3b22e08e648229987630a0853f0169688a4f97ecb7cec030b138	1	0	\\x000000010000000000800003d66d83a890147817664e0eef754afd9a2dfac43c2ce6b02286348048e87f0e294f051909353c79a6653317b74610fb08ddb9704520fbc34880325fb54b766ff92dcf19d1443c0ef9b824ee2e91f773006ed091dd3177a11f60ec2f3815f7552859a7bcca0cb33131b14490de9305af772e8849103f5bb8fbdda5fa227fb61db3010001	\\x577a50f5c967dd4fe7e23383669bdc3c7318a2abc304cc1bef1e0497cd29de4ab92723955b6319b714914583efea57440e17683201f0b9fd1a881842bd25ee07	1668334867000000	1668939667000000	1732011667000000	1826619667000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
208	\\xf92dd35f50da0f3f185963de9d0509a35ec745dfd1dd4119e2628c562627b03e9e16a9f579bf7d7fbf619398f33b8766354e15cd7b46ab1638c7cac89dfa526e	1	0	\\x000000010000000000800003a71075979a888bd4e33ebbbf1556e2569ce4d2a411c21b6fa2d0dba6a476984e0cfa2fb1361ec003852ed4e1048502b91ca012af284f013e4b200c77e41c9bacde7b340737f965d2fc478c71b71d35b020835806f8d7e862903f97c46da7cb8e42c5eb52a3758396842fb23a7010f0142ebc46688c5938a7207f904cf74870a1010001	\\x439cc2502658f151d628cbd8f50685f340294fff45048e2af2f12f7cee115d730a4e66b7b0e64ffeae86c0ac882319632101b018968f0d1f638995e6d42c7709	1655640367000000	1656245167000000	1719317167000000	1813925167000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
209	\\xfb3d303c6e8eddb1525a96aabd72be9f29327c7c112e8e51608f061572e8e4c2f95c720ac4f7674aa0123673b1900519d562d9f4fe9d0b0ec042c236e60743cf	1	0	\\x000000010000000000800003ac4d017831769afedc686cd87921695095ac5d393f4073b9070db49feed64a0d95cdd32bbd45bc6dc9e1cc5431a36a93373c691c2c92a7802ee0060cc56e9ff75afd3c66d15ce8c2c0af31880f1c432c29a3d7814fed5c04402d3a53f6335f9769083b34d9c4273f25fa39a7d3affde75dfeeabbba4b6eb35483f43168728da7010001	\\xfa8e13bb2caca4ac76a69d1e15af903dbb0918482539a1aa6de4f4afdefe94b6116667a211fd7a10e9bc9461652fdbaa3b048aa0453c6a9cd09a2e4e7ce6fa0a	1682842867000000	1683447667000000	1746519667000000	1841127667000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
210	\\xfdd1eda7c93dfa92596aeb2b7e184fdb8f7da1df12459998399918d70c0261c182cdeaab48696a51fa37e83db6f60fcd78cde78c6e91d8e6c2959e08b3c48351	1	0	\\x000000010000000000800003da9d7a9c011b650dc47615403ccc14fc74f83d42d272b327fc72f4f22ad455b62f64650bbff3e4db18d731d1ef42621aa2a5cc664d4391de0c3f75a1265192ff2cec04743818ca61bbea2c49ba08df60567ed007699090271b0501082c558a8694a3a4e91065faa9b68daf5c3b9ee7ca2d8844cccc3b1202d6bf13d9f64666a7010001	\\x6ed34f135e2ed71a611f13543c55a19580984833b5c2477a1d55ac3e4a828dfab72b90365fc4cf4bc80b58afd6db427afce7ad0dd134261b256efbd309edc407	1664103367000000	1664708167000000	1727780167000000	1822388167000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
211	\\x06fab014f0635b6c8f07ebad03069396c7b983158298b2d40a21aa2505ed74b9f326e3e2964d3bde849f33cd315034388966d9af681e2502d3071b43c48f6403	1	0	\\x000000010000000000800003a059f5dcda9aea2ee6214952953ac77aaeb5eaa00b19e6f1e4970d9685403e5001fa54192603016d329bae53f162fbb131f9eaae32483aac0970ffa70eb40bbe06d1a5fa901e526a86d2d484bc0cefcb0bd952ec4e2a46afbad33d914eb8d394e2f828fd6d2bca00ab8bc80bad88652c0b55960fecc7ed00b140ae06d9833923010001	\\x087f8903e436c149560fa1f6dc7b5dfbfb9856b63b47c7d15a3079dfca5d76e8c0d3ac99737870d74d3a1d79e94ae531187e55edb74961d8ed43bc4c9501b60a	1663498867000000	1664103667000000	1727175667000000	1821783667000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
212	\\x114a007e49296b89888b6e6cbfd77ee41937a16f318e81a025eea37ba8ffcb85fc92e088a9a7bdf4cf8eb917a997fbd223ddb681e0f9b48cc9a12cb7c675bcd6	1	0	\\x000000010000000000800003e3e045a0cefc4776d623ee775cbfab1de563576558c5d7e60bcd654bb23bd2a1fe67f93efd56ef7fa5faa62d73c0acb1385c7bcb0d7114050915e5bd14faacbbec7fad4b34a2fec6f7d7bc0068ae97725bd5010f334be163eccabf8bf6c4245ceef892c1524c77fb0e4b71cb3408ccf95f0071904edce01ff98e2e7582d30465010001	\\x8f6e026c1043204499399a4ee95702b203dddb5aad8afb73ab6a5d706e199a82eeed272637aeedccf5b6b40869c8fa45c8764e773b9d8c474364187865bacf0e	1671357367000000	1671962167000000	1735034167000000	1829642167000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
213	\\x1226592a24a136d38f453f1cf7e82cf76dba8e2004791577baa2ef7c73adfe0666ed6e2986a1f9de5945348d1eac860edd59d87f4a17073be17969473de1dbe0	1	0	\\x000000010000000000800003978ca7b0b33a324abe669783105153e4a750ff680986517b7de40a6ceea99392a38e2b3747134470212f483f9a67acb58e57361a582738c6951482b6e4277570a3aaccf8603d116de360838ee1e1bdc0589fdd9c88febe332c6f6c09d8af9e4036d891923540e19e94e0150c877ad2f88dfb9018ce8400ffa4850db111900cbd010001	\\x2f85497b7bca775327cc5504f07f3afa121dc6b510348f2a11a55638ac5631df5bbcf222d70ce20ded4239d3c5b66d454eb290b81f12c98e3762b851b08c060c	1676193367000000	1676798167000000	1739870167000000	1834478167000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
214	\\x14b25bd0d4ae1a3b71882b4d8c11e9a8564448923c080ac780141b2cdb188b574c1d3e07903bc6cd98ee7e4de486078e210acd48083b9fab9893aae5986da685	1	0	\\x000000010000000000800003e03718a5679aec850763affff435d3245b1c386314dc9da1001458782045e0266464a3783739b566192734e1dfff1f78dde32af3bc08dbfeb71767ebe7e3b0734d43a2fd7395ac47e9a7003fc4b284f53fe0724e24854ef3c3526f829f2755e53841be997f38e8fa256c1e01a437aa21b26e3f964de9cbffa82aa1bd7eede4a3010001	\\x02b104ef188a227ba4d235379564b2d27aeecc88908c3c675df7c32a96ee01776cb95120ff0854a964e2af723b8d42515b62799d2bef25d3e3c388b62d2b4c01	1665312367000000	1665917167000000	1728989167000000	1823597167000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
215	\\x151e15747c771931769c2ee1a0ca9ceb91587625f98c467222ff7fd904545747b5fb509308ac72c670ce67d8094c41300c66543ab183d846e474e3583d2b0947	1	0	\\x000000010000000000800003c7926aed39620879873bc93e56f8501171a6cb765e1086b0c5c448194a4663b8ccf5aca944d1962cc4f4fccbd8368dd86fd86f2c2e4fd4da654e343ea00a8375551ab5685f511f32ddf6765d0885739b57ded2eebf2113227220b4aee457fb6912d9377d88e041d1a632170554b02e32e2144455f8503b7b339a1ea023af4e7f010001	\\x5386f92764214bff46547f8e33ba00dcc73cd8f1ffbde5de6838b5db97f5ace91867a693c259cde40d75a34cc73a145fbca98cdf3917fc4d8f6e8f69a3487a05	1660476367000000	1661081167000000	1724153167000000	1818761167000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
216	\\x156a1a11c6f3989716a90c0d04e947acfa653e0ffc76d5380b19cccd5f548695c9c7b217e377877c83056a45fa3f4d7c7bb0f630feed5a9b5c4fe64e24c64c03	1	0	\\x000000010000000000800003a9155397d6b06d44f49de71e1bf066b8d0de9868eb358f8f765b81d307cd4dc92aae43d62c5d59746faf990e1968908bffa9ce8f8c42880a2adf2464af9bf32abdeacf82fc5f91769947f7fde7bd2fd043a68a8dd515594cee54bba6ffffc9d3d92677b8cf1607040a0122e4801d5af030fbcedb6a17463de725035c00d2c67b010001	\\x4122186816c74621b4c8ffe773db897da46a70177a7ddd9694b445f458e38439866cae43e52903cdc168be5f4c746b13e6a65e9b7de142156ddae40d4419ac02	1658662867000000	1659267667000000	1722339667000000	1816947667000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
217	\\x17ca5862c5930c71ea53f86541e4520e5dc81393a8ca9d24fd8e3ecf441aec1c583f28b65c436c0d08689ace01b85ad843adbe627e47ee25987ace53bbbaf32a	1	0	\\x000000010000000000800003bd0e21aefd799e25bbfc7a57da20f701f7a4ae925384b6b533aa46d35320cc572ad12174cb89f5d9f3a6e24ffae6cd0b66e1964b5899b37ebddd58bf389cff7c279cb07667ee588205dacbdc066509c3428a52ecfe607293fc9905abe35a5288f34fe3c80b99a91b3b976cc026577d290b9655af4b0d21ba0de76f2d2e52bc8f010001	\\x5a9791692ea895db66ef310f65a487ec0160d2332c2f1343c39aad96c781b31f9c6cbd40e77f3cb1aa14d7cbb21da66a294ea6a8bc2deaaa368af805e14cbb0a	1678006867000000	1678611667000000	1741683667000000	1836291667000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
218	\\x1bf6df01848f18c25f7c426b2f0aab9b952ef5a7b92c9ff8dd20b2f9e33f8d1c6e2b1a060d23e8ada7cd7007bf72eeb45c49df4573f566ca8ce1d5c4f0db0366	1	0	\\x000000010000000000800003b9a770901e3e6139560801c17c0601103d70d551a2e268d2ee10e53fc09dd12b18366cf1d93594d5b06a101b2d4f829857975ba672b5fc236c36942203e338f6e0aea93530a07cc963bec9dc953baf6758d30cba5ea8d617e69be2d14ff99a1721bd239b3a9763f160e2e7f5ba9b3c107d913a21d675e488bbaa702feaf2a6d9010001	\\xc7b358acf8342c47061270d00742c19c45780c19c343f60c7b7de67bda914ed5c1ae26a2c252989c3c1a94aa9b79daa0a30efb9c0d04d625d1a912bac9a6fb09	1661685367000000	1662290167000000	1725362167000000	1819970167000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
219	\\x1b6e4e668bab76cd6fb264376d1f4d7f25fbaa64bc0aa0746936ea8510d1eaf505eb6493dee8f59e5c285372ae22c6f92d365fda557422b5f82f0e483d12fabc	1	0	\\x000000010000000000800003ad57dcc91f5630b629046f85f52bca60168220cc10cdc59f3ed73057c883738d3f503f596bd4fce18e2bd45b137a56e811f7636e4f624fb4e239b23907a482890a51b1fe46bcfd3742105cca31fb6a8325be8b69727dd06277abc70fb405dc439bba4759d294badea02de68db67c14c5787dec8b2a420c2a14de10afa60b1775010001	\\x0f5588217e80dcaa6a4bf1c071e727f82ed4dabd3a1f44fa17f7f92312fef1cc7036887838449e0677d8d58fbb9ea135bb7f064f028ae5db292b81b8f9fd7609	1660476367000000	1661081167000000	1724153167000000	1818761167000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
220	\\x1e2ec8bb573ebf794d3275b8605b869b10347fbebde7ded773d275bc3ce092f95ed05d3bcedda0f0c37370cd5316a0865b5db1a7864ac6393cfe60c93acb26b9	1	0	\\x000000010000000000800003abb4eb1fb8f1d0e27f095f95729725fadd43491c0a5de72a6418c32323fb3100d42b7592fd3d3e2bfa2e226d64921c38c58c785180f3acea8ede728ec43aa14eb965a13d0839a2e36ce32def0d400278a2490c93acee1734107f21e6fb6ef2460f1db346b87d66ba269987016eae1130df5979ea0d84940edac49f2406a676c9010001	\\x8eed482b3ed1c563a4d6be77f6168b38ce7c5adfb9ba4f55dcc5d0d1edcf1537d562257c0310ddff2252c5626a39c3e65b64571c101acf896b093ca5e5c9bd08	1679215867000000	1679820667000000	1742892667000000	1837500667000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
221	\\x2676d09a1833a5e29a073e30684b4309538882748337885e211506c6f37651ea0d7d8f91b8df8f451c643c34db0e280eef5c8aa9a81aebb1f73d015147ea73f3	1	0	\\x000000010000000000800003be797916648f89a92ac828cb2a14e67cbc70233e7a80e03ec40c7ffc5548f7b547b3c0715d465b0c77375fdb3457e6ac83d7fa4f54d1fe1ced47202240e94c886045033f5e307bc70b359dfb79dc3cdeea365315f8494796a58ff46e57132c618c0f21b56f318cedcd7171ef17ab634c04e8d040b5743d2a648724a41ac0d63b010001	\\x26b60b9d2f6109df3ee425cd8ed6f88ec9c62530e475e8c3955d13ad192014899f630f4a476178a218b10fd8e2732d16802b9dd2e893e16cbe65cf1cbc26ec03	1660476367000000	1661081167000000	1724153167000000	1818761167000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
222	\\x281e21c9be7a945fec20b0aeca1ee173423928aa0839490d3cbc55303c978b273cccf8fff8aea77fce82ec84a37bf2e55defb5531d08d31c2ca58978787402d7	1	0	\\x000000010000000000800003cda071b8e46a68810ee337d7cffc06d99d03cb68fb4c91d1c84239fd81f16a02a6ebaada3dffb6de3bc32a7c4ea8ec8d5948837df3abcea6a866386670f7112c254a14a3a3ff62a6a4479c87133601eabdbc85a08ef380733159d7586ae3f85863a9ee094d30f6eafc9a47832fa386a8c9fbe7f6f958170e0fd87e7c496a4da3010001	\\x4b1af57b59ee911cc85ebf8fceca8a364f362d8ad1f574802012583133a0bdbe43fb69450a1298bb47bca6ee281cc16131ad7f21d85d2c20275c6e877bd07002	1659267367000000	1659872167000000	1722944167000000	1817552167000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
223	\\x2a3a9e1d5b2980b3463528862dff4144b2ac7e0c6ffd3431906c05f42cebe8b98c02d0ea5fdfa3ce1c456f89eaf08292f7993d0888de6537b2b9d24d09d031d3	1	0	\\x000000010000000000800003c2ad185c03295b1658b99bee2f034f40ff9591cebd7e69e1255daceae3ad2487e3141ba8ca9ae0fd34170710a0ad125388d79ef27966ec2d9093bc3092ab3acd43aa49f54e128758c8fb78ccd2d8a138ad5132da0a530672eece340d2d2cc039213e67a96a0f5db294e52fbeab0471a833714674b61969f4d1acb65bc99c3bd1010001	\\xced34990a6cf2c0ef4072d2bd672446b0b15e59220889d93300b60cb8277b296558f9f36625054b1a945e360c239a08872714807d74fb39afbf0faba4e837004	1658058367000000	1658663167000000	1721735167000000	1816343167000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
224	\\x2abac246b8714106e96601c02a1aa2890fbd0d59ab6a4d27165a370a56dffd09f862f68b1a8c7e29825d67082d12a78c2358d44ea6819cbf980e60a781ea18a6	1	0	\\x000000010000000000800003a4942c3aa4bcb43e622dd116bf675a252c59d69b26724e64aad33441b1d210f551bbdad50ee62a0eb47c3bacc18a7a9a37d61f8951db2049bec9d69e42744aff106021a0582ed94833a83cf5c16e8175a8a038ea49f6aecc923f0f372d775c3a24de6597578fd87b7a244db816aa689c0ca877a2e6bc3e73a358a5627957d9cf010001	\\x50548fbb6bd5d5d6739fac5e7e7fc0f766a2d5b80ec626d40da9b6fa1c0e3881f66fa777dc4609d8c5ddc4a5a5312581d4089351dde55fa5b53b7dd0da0f670a	1686469867000000	1687074667000000	1750146667000000	1844754667000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
225	\\x2ad61ed9dcb20264bd0b8833e1c2570d99f842437a8265cbdceaee1cb27eefa2b3e64aa9163ddb5c840c19f4d30a33fc3677c241aec7f019ef236089749fd53e	1	0	\\x000000010000000000800003c8ace5c36d1387d0fdc4ac82b2dbe087ba8f419367da464523c4d7d28f75c6fb86ee2afccffc00205115744f3aa0045cc28262097ea1db0917ed8bfb9bb11d2907285c0dda465ee859a807c7bbf9fae8a38876bb458fa54b90b3903773e3c96c2070d280e39292ac3813524d5312c28d862332ee55218b26e90a8bd22a3f90bd010001	\\xa6fc8064cf5057b0ac96f3dbd4afb48209c02b32a4099f9e7f67b012b8486661ea9294bd7a0a1ede7b6e0bf5aa1a593539e542be79655552b64628bf79502702	1687074367000000	1687679167000000	1750751167000000	1845359167000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
226	\\x33aa8a0c6c6f30da54099f39831d749d94c6a1adcd80158fadf1b226cfc985d728b6d8e03cfb43f03db2ce09ca87eeec8e91f0da548e593af9655034a8ab32ee	1	0	\\x000000010000000000800003c1696696db270af1c6b2bff1efb95b02389215f0771638e24d6240b6f305ff662e92057bb9b66fc9cdaab9f5daed9702823c0b933f9e7c760710111b268b3a91bafd3da516aec154cc3b027ce280e087f6255c15981bd1f04b13a0f9e12b71c73286173d48deef85535634b54d5bfdee32f64fbae5a9ca0845e60702cd20a9cd010001	\\xfc47a5f80780a3cd38c775ef3de945f79f1e24181c17b9b1db77c19c81987343f3b2c0bb242e48995a49ff2298a361cc90dd69e1a26709cc87e74d4e456d2f0b	1669543867000000	1670148667000000	1733220667000000	1827828667000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
227	\\x3686467c8e0f9edfff141cfe3b95929e3b8076da53ddbd0505ac480a130c89466bfcd75e042ea490259f992e34ab4ec78cc92b4e41f94a81613e5379a501dbdd	1	0	\\x000000010000000000800003e432c69118fc43a404e8faf436bea4883ef446c149dc41151d40d5d7d3d2cb687790def263ab245ef25c6539dae5dc601c79e8092b8b88914a2a88fa8eeeb084155b0a11c6a1999738ebc9d0c9ad3392dda4f9bacf4ec995793fff4b56026b6e93ad0e9771dbd1a4f0528980b333319291befb2e1b70a131871cae33fe356407010001	\\x970f33a906d9db7c47032c8aecdb1b70d1f543e6c41e839c11e427c34bb5c891d01a3cc6887df7750e1bba0bc0360df7f45a45bb022f7ae6022c85cbfe6a7b07	1661685367000000	1662290167000000	1725362167000000	1819970167000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
228	\\x37269d107d9ecaff6d4698f31ecd98299ca1ec1875675400bd270358a78d503f75c2e402ea1fcdd7603ca78a7375db0d7e25868b0abfc96bb1ac7e40132c2028	1	0	\\x000000010000000000800003c6181edc81644dc91d49a6f379c5ebe9335e080135cf7fe0e0a4036b1024adb69a7ed86ff35e2d23c9bf0f299fc52a6e1e414099897279833e21398078625ab94aafd43d561ed5e95d1db9a0ac924eb214f2617628b4f97e6ea2b600641ad1e69ef37978c7bdffa8fb0af8d1148a64688e24206516628cbf610d2eaafec19d33010001	\\xc255c3fadc088acfea32380757b4ef357e61ce15c8e863e94584342addecb80d028bac3d81b20b0940574d540d6a51aae27f7f5d65e765e0fc86b87a428f7100	1678611367000000	1679216167000000	1742288167000000	1836896167000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
229	\\x374e7af06adf28d171cf296dd34d14cdf4d5952dc4a35213e1d30445272c16fff70dbdcf950bf9c6866ef6186b94d9a253933da3e8ef9712357c19e19df895b3	1	0	\\x000000010000000000800003a7e4c8e9cd89b24847d5d54978ad6409a63b7ea64e07a8f7345c33d118833f9e787b20767d719e4cf1c888f3703f54a70f644f9f6b03e6918cd76d666a5bbeabf43b535dcd06e1d21bf1c1a0c17a869a14853a9acd4994053a0f8895c21a811589a8adbf14dd8f1f0b20494a19ce1cee47dcb0b2e1c8c8c0f1347500b1a6917d010001	\\xf7e271b4cfc493dcafd10599c6bcf35450d516e320be7c8a455267780f3368cf0a347d56ba2905e0c691d83f281484b55cf341e65deaeb3cfa9bb9a1c58ba008	1674379867000000	1674984667000000	1738056667000000	1832664667000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
230	\\x4152bad66db5717722b9c6f18bb0938e4ea44f660dc0d78412983b64db3485c432d03c8bee99e1ea6452309475b79845ae1c23bce57f72d90c78e0aaaf93d828	1	0	\\x000000010000000000800003bc5e471450a85e4f7e9f9da1d8d2afa5a401907e3da23e63887f0cd7ec0954ce9bc3cfc7e3b24cc32d635797a844fff86a824bba0dc842b922f225af113f22bcf7caf761856bf293864e3ea404f09d00afd4b5021588f5d23aab751e4ea7006700613b565c99ccc07b8251084e4b1a9b89c28ba6c3b3e21344e5b1e3bcbc9b61010001	\\xdef6638a27e39c76bb547d9ccfe54bc7093fbc2fb7959170f41958a4f0f873bde0c522b1f52fa6c4632820669d4feea7282234820f1d65ea2e08c381d974c80f	1674379867000000	1674984667000000	1738056667000000	1832664667000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
231	\\x466e1be3b02190db0416aa8487b1a3a0310b4e045d98449a484ea216d2f1182a70c8263b5c1ed87ac20b4158353aa9c391ea99886b6f6f1658c98bc8786e8626	1	0	\\x000000010000000000800003d4248bccab489e0ceb11e0f5b478393bc9a4582b9905f3ad9df06378abf94be39754bd71a1c590fac9c04cb55ed67c13011e17b334ea8186bd71164b2b466418eb26d7e6e478564b0acc949ee008901638d445b7ba4eb5b6054879addb9a46b6cc3f39739489d9efd9e573dcacb06e1e8b904cbc3618657f16d9f001bdf7b6a1010001	\\x9f509edf07920f8cdf295c5df2891506506083dff147850e7564e0b99c4a20e7ccd2711902d4f3d3af9927c02b6883169e93a4aa6dc4dbabfc3aa0fb1edc4006	1684656367000000	1685261167000000	1748333167000000	1842941167000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
232	\\x4d76af61538f40c9a04612f0ee8bd2aa12b9186f87ace9021f89fdad3f65100b307738d6526be4e2a0c1559b6cd083046aa6539ab800a7d3c4423a870c14bed4	1	0	\\x000000010000000000800003a82860d8fb969b438b5954472ce171bb0f92e90fc4948fe27b9aeaf5fbc9698576a3d734adf672f9c31d486bcdeff0154f928d57ac9ce8f0b2bff360b078c14051a65e3adee0d7a5fc0c23d17d1808ea6605360c3e49b86b897f73ca014c717c61ea113e8da20b493db31c33b25258afe7dfd2e0c12f3b01c0ec50a34f6349fb010001	\\x897b2da2178f247ded576633a5e0c35284ffbd51f336a2add30b69355b28ce45b16e1a5dcac966bc0669311b0ae83a4480ce4644502ad8c45971a18060e31a0f	1683447367000000	1684052167000000	1747124167000000	1841732167000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
233	\\x4d1af64782053351ddb3567f9ce728bdc0c09d3af861199e00b3facd8f804bbd1513322fb5cc2f6e69cac922078ff0e94f8b2042554b93549d84b9a4d14c3c95	1	0	\\x0000000100000000008000039ffdbb937d75c5323ba56634b3c9d3bfb52c27ba1f4886d3ade44f6035bae22dbe69d67eb5e44534863c18a5d6758b2bc80dc961cdd9c66222e43cc899aa92990cc7e956b4e4be28cd78a4b4a00729f9c73212807ae476d0c6931e18141498c308ca784e858d7683015086b3accddeee6a09d0622e0a543cf064601d008732e7010001	\\x4b7929cc944f60ed578eb43c9c09bd39050aa01baf3ff73e95daf79ab885850fe66c6ae8df43931a1cf11c7ff5dc32b7998b07835d4249b84ffa53b22288e30c	1671961867000000	1672566667000000	1735638667000000	1830246667000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
234	\\x5326a3a6da4fe4695b493c111017b43480b9b73b72f81ff4b039a16dd29a71af5be12d7c0d16b5d7546d7904de2bbfc68b2c66496c53b33afb4e8e8c7947ac40	1	0	\\x000000010000000000800003ecb6cca8d2e09777e3d50f5d79502776cdc6b5a01c4e7c9120984dfcca95c2bf8fa8168787b5e17d62049c65ad872cffff7e247b3d5ad22d430bdf06bd5bec31cb6479af61fd505ae7f0dd7fe434c7cc37a8c6d0040477e6a7d229c08816307e2f6e20ab05420f03067fbf251a06c0b68c4822673fb31221c680211d184a3007010001	\\xa4e1e91e4c93865d98e3bacca9edb29cc08a9c4c23ac12de16c5918a1b02c3e8456685a8ca7b67894d15d2ebfc0a7417d025844a2fe0314e85f7803603b8b302	1678006867000000	1678611667000000	1741683667000000	1836291667000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
235	\\x54dec3ecbd35f84365d4be5da160c595b0bd84a1dae8aabe5a1403acfa73037b377d254af2ef1ac3d146aa8632acc70763cf52ae361089a718cb5700f8f9801e	1	0	\\x000000010000000000800003e681f64d95913a681343c82bfeb6b2bf169d9578cb267c204af6665d70eec4c29dd35a7d644c4442bc8445a87c1cf8ede028e022b8e2e8f6cce8be87dd56d077c72d3474d2729c4fd55a89d45437826d0fccda92d1183c8437eafca10a2c3935f0c15248508c475147768eb39b811b8001fb776ca719f7248db6c2b4f1f61fe3010001	\\xa22ada634960d42007f3bf1a8c4ddb6724cadd0d3f4eca7e378e405e1fccb88ffbc4b679381ca123dc505c550aca72e96cc23eb9b470068cf3c8366a1ae28502	1685865367000000	1686470167000000	1749542167000000	1844150167000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
236	\\x554ecb0a975a945faa219b60689f111c7eec2b955f913b678a040460e5243eb11dbaaa7064c906d2d37fb01d08b04c70117f0c218c9021df20e0e573c631b633	1	0	\\x000000010000000000800003deba033683888f9ab03513a855aeef9359f54a7075d715fc6092f697722539673e9ef519848afbab50b046408655cf1828c4e6ccac0f0350e1701873f72eca9334c48561ef2f09cfd705fb4fcf98612b6a93e5a0b78822cd6831f06ec5d4d1ec35cd5152015b36c62dc0d8b4a91aa6cc28c1f43c8860e5454580b99968997ce1010001	\\x5fc06f156f29128ae1bed85d0e91e2edb3d97d5ce91d899f9a489d81c58c0d54b0142284acecf0a72f9f0d43830ba3ea76a820487fe3a413b49def98120e9b01	1681029367000000	1681634167000000	1744706167000000	1839314167000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
237	\\x5c6ec91ad433d400de48b85e2e6ed52b519c51956bfc94dd27ebaba7a0c6caaa20d2b92ebf166ada8da1df793ab7ac28538b75bb3643480540c8e3a0a63a3bd7	1	0	\\x00000001000000000080000394e55ee3b597b0926f0b00e369e28ebb3405a9f37dcc6853d54dc099169879b4a3793241aac1450cfaf77de92cad0c183999f520a642fd21d50c122ea8547e4403f5b500f6cdbc0005c805d28f66a13b5850e150d1c66e2a6b787390c89f823e8cf8bfe5002666131f0f4bcc52dfde2b8725f16dd5a8b970e400fcb6521cf3af010001	\\x11ea6a8fe177773015b4ea13a1b1c608d61efdad148e4c8899bf15141b25eaf6adefd79ebfc069428d304c5afe8cbb1f07d5ba8a0b8ee7bf51673f1700a1fd0f	1665916867000000	1666521667000000	1729593667000000	1824201667000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
238	\\x5d62981f5f3aa728b46e2efd63bc57c313f54058dd8fca349ab73e9e7456b689f86b99a7a269070f184ec260777cd449e25411e00353d30226b6970f307dc4b4	1	0	\\x000000010000000000800003a919611da4f6b4cd458d3faadd61f25b0a06ff4656f09cda9f262f15e9b436a7c234db64315dbfbb86cda086d1aac1817b96738346b608c16b54f8e334719151bcfc8dbf9d2e4affb6e6eb494de8faa2c3c22fddd7ed226924556bde3a14c0a72d82b939d5a995478b6f7ec1f3c421f7d5d8f73d8566f92f2379ecdce32d89ff010001	\\xf8dbfc266cc053cf9329635ce67ec43ea5a38576174f27d9099b742f5bcd8429a91fc5114d182e94aa0ab1295e1acd38ec989ab2c92b9b39a4bc354dd88cef06	1672566367000000	1673171167000000	1736243167000000	1830851167000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
239	\\x5e12862becdfe1c59a436af82800eaa89663384fd42bb8027809f6deb32b56c1450cccacba7c175c476f49bcc8bf6f9c2615f0703fc626df09b54f040e41a1f1	1	0	\\x000000010000000000800003c612cdb143699ef08c2c904c27242fb097be8c1124947d557b18d548011cd7798ae2f062e749e46d96b176e1e36f1cadc0bbe260798011fefc2c6450db5883b0168c8ebb4a5c482ddf798ae3be5dc2eb9b027b04d4f69c331dc25ba877d4bcba6ca597c9a52fbc9d3c2dfc87e9d29b33f429e87f5f418ce64140a7f02603b581010001	\\xeb0897d27d05ee0d79ad1f055101390d3e8b1e56d27017d1d1597ad2aa94b78065320a7f66cd883f768051bab26ba5f2f9cb94dbf5d1f19bfaa5cbb688766108	1676193367000000	1676798167000000	1739870167000000	1834478167000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
240	\\x60e62ab09aa717595e0ff847ab1993999674367a80e076e77108980444b9a32566d416cdd274c8b463b04cda875816205efca999df77855398c9b81485a763da	1	0	\\x000000010000000000800003e891d1becae1bfc32e0def009f14fd2e38241a528b66de4f2c50a2c7bcfc96b08c3b1aff53d44fd81c269d720e7355c0f9a44ff349093a4b4fb06b2d8f25af1f345e58ce350e9c1f896825d609a72296610ec2391b98af5ed65c5874f5b036fd8c0dc64f1d046187f0e501209207313888b477be13fb161283c4c240bccd2ffd010001	\\x9ff4b2bb1354240f1a381ab3c11ea38f9b123802904f34e445152c517201c03ab9d74c17eb7b39b5cf6a8c549dea303bbf5fadff819309f98ca5889c88f1980a	1685865367000000	1686470167000000	1749542167000000	1844150167000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
241	\\x6022401cb488642b981976c454fa6d8e1111d651192f66ebe2a81717305880d6a1fd8164dce630b40b8eb834e14daf6c7c591ed30870d6de257e77536160b115	1	0	\\x000000010000000000800003db11ce24924e8bae14899e28afe9a92ab6a5239ddf11f8d4c41e10e9d7d6b6134a51098c4585352a77bd0a42ada9f2e1cf8da750af2d4a31d92c60ca7b0b6ca3a261b4ea1c89e98e1577255057a367d9a9339fc844b79ffffe9d66c4f64335480cfaee8ea458980c3328d84ef9f14355e570e9f63939ca9ca964c16192de2add010001	\\x66d95c27caa0f191ed56689c9158e7207a139791e5f5c3c9d0a4d7171254c0c61f320406ef50d3924507a9f27b52067bbd13a808712e35c45c04d789102bcb0e	1666521367000000	1667126167000000	1730198167000000	1824806167000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
242	\\x618a219a87c460290d6188e5db19be3c04c361d8b4781cf1469e1fcb761a05e66c2579f47e618b6e00125c3ddebee5851c8d7649ceb5cc3169d8d6673b2d7bde	1	0	\\x000000010000000000800003bfa84ad0192dd1da9ea496a5f977929fb59dce8a0b5972b0a04b098f060b845c7d3408cf10babbda3e2ed9a8a4e77951412e24441797328727d0e5822aded3c8a15c44a2e0d0d25becc957c8b5e9271411696c8553d71186c47fdc8169c9a4042b588f62defe7420a7b1235e03bf08f4ae7c89ff62b60d7d0d83aec3405d62a9010001	\\xa149bb9852d65d791714e11b0f3bc9e990a81492a21c57a1dd1bba5d1c593bddf80936f207b883cfa8b0686f4e714d8afe55ab49df14f9086cf935e5d5709f00	1667730367000000	1668335167000000	1731407167000000	1826015167000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
243	\\x624eb76a07f9847f6237db8861818772202d633f5e8844c00debb38e8fe2e67747381c330c4b4e595715f00f01471133a39cb8e6c2ef135ad82a8bd62f1efa66	1	0	\\x0000000100000000008000039863ef8de4e8c378e17eba27aa2393c9d972c09512676f05429ec376ddd889697a690bcbf7027a2eeaf6978b00c70c861dfb1dd174d81abea195e4b61992d50abbba10fa4d72efb2845137f332abb31edba2bb50af44c6f452677be0b274b43d28461f4a3924ac539a264885a4691feecc4908d71a845bc549a8a0ddd263126d010001	\\x084ac8173be7e63285e1661ff46422a1ac01695931a4c9fcf77a792639e3a3cbd68439f77b0edb4623a5f2df0bdc435f0be6753367dd0a0a007ef14e759a9605	1670148367000000	1670753167000000	1733825167000000	1828433167000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
244	\\x6556170ef38393e63ba9ec4a08857006d77734f3b57c6921047f87e12aa58b6d55b6410e4ef1427b9f99a05b1b5281f9a5bd1557a9f4f86e1c29711acc9333e7	1	0	\\x000000010000000000800003d0c1b2421ef257b60d41b19bf76e1ba8ea8a360d364ba2685ef5ce89c861134e0277addcc6e7972097e307a95358b308e4ce10ceea974750744e9cd50ecd58fd22155d57c809ea5a10258415e83f67e9a17e94a29b2fef581804f38ff50bfb8de89e4ba7055a309ecc74702bcf3748bb8dfa166d4b88bad3c6a87eedd6f954c1010001	\\x9a932c5a91807a7be3c643b29d240fb92787255c572661d8bd1b65487d8a64128628458620fcfda192370dff6d7690e9645aab9f47abba8038f41f7200d4d109	1686469867000000	1687074667000000	1750146667000000	1844754667000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
245	\\x679e7c386a1d6ad141adc7641432e99874f36df60b5ef13584bd8c0e38419842e0b7030054f3f527c032333d96ffef9ffccdc6b2c8877945a6567351c4007d67	1	0	\\x000000010000000000800003de8536ab3e94a40caa47eeb22221adc204d3c53f234436e5bf39baa8310b771873f592d57546451de1d01d5ea5ca77805843db08a115cc10542cd9e4a175bd03d745b366fd6537e0f00b6f1f577008fe374ad5b306facdc3ae53f88fbfc3df4348ae123cfeb6dc16619d5a420174fac3005e0673c3b5ba72e510815cf4f0dafb010001	\\x48cbd435394b3a2308701b8c63954ebe1506f7408a972f0e3c587fa189438d8a3ff009bd35fdb695e02871279ca43cb7d1ab371bf1262d188fcb82acf28b050c	1687074367000000	1687679167000000	1750751167000000	1845359167000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
246	\\x6776aebf383ae43f4a839948b87292a1fde75dce40447000087012cff38e967c387fcad0d838604c9d9a8d8c39c96041319458ea52ae8b679acfe2aba196c743	1	0	\\x000000010000000000800003ad84a431237075647e53b9067aa31afc68962ef5af62d4f5aea1aef669ff5245d6ccc363cfa1e91eed8f0e9f6f38332ea6f93d41fcb4e21064bc0f4513d4d714e4000921e1619007a3d382b9f205c144ad147fc5cc4f355053761cbcbc125050cadd24c3e06d0edb9da2cced1d93417a7f64377ca49eb559e741fa9f43f41a47010001	\\x756edbf4f75e3023a85c65c5bcc2831fe6a01342513d8b2b81ea99a7496d19afd09cca15420a7d120a484f7254151c71ef99dac311fde293247587d265c4a602	1670148367000000	1670753167000000	1733825167000000	1828433167000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
247	\\x6b1e37b3fb2bf5d7d1b173580c7fe29b5ee71e53ae17b9126f9efc75d6c11f27f018829a425a7a1a11ed63d404f51021d0caccbe4a0f6ab483e7416d71e0bbaa	1	0	\\x000000010000000000800003cb284f0f1f9cdc919a7a661da8330a71ce25892f2de823580fdff2fc60c89e5c8af7b77047806e7ac897026ce76f7ae7195ceca4121862daaeb7a6569fbf6690f49f1cfe078375df9200871c2c8dbb9c83a120c70be294826af53e87ad5dea4fe249383cd34410af75bcfd9a98f59dd24f31be4f3f2f60b7cdb72725ff97315b010001	\\x7b44e6537535c40fdb1dc922a0ab4ffc12fd9256bdb573f4557c924268720c935c22bbedb0289bac379e2064f6c45c529213d2b15d89e68b3e53932aeac26f08	1676193367000000	1676798167000000	1739870167000000	1834478167000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
248	\\x7132d35e47454ee8e42beaa4388a89ee647e0085c4160f1571e0cbf27dbe1def6425b7cf7575c358cf1cbbfecf20b5e08f14afeb2d363272009e4b4b03038e5a	1	0	\\x000000010000000000800003e9a121548e4684a0556855425cae8bea9b80719a9dfb6990b880f6392216fc7df5e37ed0b611ffb3c867eb597fa6d16160a77b1a8d174c465afeb2df9e049a82274f1a0d3264a7ea0944bf9ec45a8d0eb3f60f39103fc00649f21fca06d9ce78e232de09b8c010849686e3c2389e7ebae5a905120439e4ce1de2d1141a7728ed010001	\\xe9c9d099b19ef1649eb49c0fcd5dbb3717fa89f4eda2cf4d03832554e0dae8d35f193112028954ccea8906f7aec6ddd7d07c2df084bec94939dcee2edb3b4301	1655640367000000	1656245167000000	1719317167000000	1813925167000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
249	\\x72726e443f77027b8ca8e605319f9f0ad954ce494e373d5a4fb90afbdc0e21129c954c21429068f726dc2b193492227e51d164f46a627d21320837c850d6054a	1	0	\\x000000010000000000800003de7729f02b759e9f06bea01d2b7b53c9cbf770d564acb81c96b3e0026dc6f079a8af76056274fc600eda2965a903af240e53e68cca738fb8de85f617a842094e19beb5ea7e716f304bfb8bda1f4cdc6b940168dd874fb5dc38c02d97a8e17e1cb7d0b3bd0010f26e98a839a9f1ffaa0ea0a35674ab7f3b6357bc49b76fdfc3b5010001	\\xe07c7ffe70902aad0e6bce34192cc5ca3eab1780a5e635fe2e2bcc530c981931774bc35f9e2c468cf78faf4ea2a3d0ebb8f6df5b57bc4deb41fa9d146ce0b00b	1680424867000000	1681029667000000	1744101667000000	1838709667000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
250	\\x7272f4a77597a2c6728abb886c7fc608f95f1b06c3da3eeee7f5c33c35d6577b5f90ef70cf3dfa72b30e2bb89584d381a8755c20c4096ff38eac4df560371aac	1	0	\\x000000010000000000800003d683f8b21528e61c883944562a266c871807ecb4ba4e7d675aac9d477dbc24bcb46f0efea5a748bc6dbb301afcca18b641879da288eb36ff3106ac294158d8683f739730522f1c0465169670e76c94bbbdc508c136da297325d9cad7f0bee1226760d4bced04d5813c8e7b4bd6c1ab2020a40efd88a46b49198f071e118629bf010001	\\xd13f9595a96241c8a41640aeafcb2286b4f4f9bae760030f929dd7f16c03f4406baf6ff20bc55935b40de0acb7156b3e57bd48433864f38836398a5d347a8404	1677402367000000	1678007167000000	1741079167000000	1835687167000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
251	\\x754e5c8a32472a816e25f5bdf513b9b209ba1e67729660820bd132cc852d479225d40e3de81ac6c90febddc8496a6e317727a739568946688ba8c2efc8f340c7	1	0	\\x000000010000000000800003fa4e509439be697f92c91de020c32b95b23f8c50e419558e4a8fc6995a3931605a6654aa3da0dd1147fc3f792e1f269f1038303ee4bc898a80ee59a5b7d7f14e39b73f2f34ffa8d8374c8986f994a072c3f7d7eaa1e7e6ca33d9b7b9cb639f03e40d1b1117861a0902fbd15272d2c532acc5491882e3936fa87b61fca3d7c5ef010001	\\x88b4910ab0978f223fcaeb567ba9e77f99953c3151367760847ab273dceb869276d8e2236046d710c8012505d307987b20529948faa075c752381f8da051000c	1676797867000000	1677402667000000	1740474667000000	1835082667000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
252	\\x77aed22a8bc58bc1429d074d440d078571a366bd5cd781b3d92b685a29595c6d3f432d90e0821d9160dc611acc597be262b94183b15c307dcc2da72e156096a5	1	0	\\x000000010000000000800003eee4aee78e4b16b262908dc200e2ea5f6bd43a1b540c7a1f0b8721b5c1fe16679546082ca8bdad334bda99e8f6279f83f8fd8a1df3c18ceb8899c1dbf09eaeb2def1cb7beb8ac66644fd232f01dc5f22fdac91812b896c7237049bbf195d1952da6a0b1f68777f5508c27830336cce20138b440e765a3b0608b88154a5d4728b010001	\\x374d2e0ec8fd5f659dac5ddca809e20e41e9dcc726b6fd5bf77a4b4d1a8361d1dbc77fc05169478f9af747a0e266314de2e294c77ff1c1ea29b0b0f0ea9ed403	1659871867000000	1660476667000000	1723548667000000	1818156667000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
253	\\x785a20ab63a958566b0d0d2d680d6b3e87cdac1252d1eafe55a6ef2bf6f8742b67a1b660d9619ef876a62d731245211fe0a5e6ea95303fd1f9cc4ee00baf662d	1	0	\\x000000010000000000800003a11c86e780495598b9d4692f2f649cbc9b4a407701f3e0f2ba3bf572c51d615ddf837e5051d7ece9d8f3791580629e354a3b65923da836815c102e40c4fc1b61f09339ef23b61bbbd51f2e728d93dd5d91cb95ecabb325922c4be2ade0c7203bb560af26e414692b066fc87fcccf0b1b95b47f9200379dcbee76636638623c77010001	\\x127f464e809cbd2193a70d51f52cf16506c9d1c0d2b769fa01b8f238dee8f64c6b24c7f1fa30ae3aa2271a89c19584b334c40479f66c4da23b04ec4e85b36506	1678611367000000	1679216167000000	1742288167000000	1836896167000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
254	\\x796a32721d04afb2aac83857ca4f892756f1cff409d8fb542df2e6febb5172bce58b04c45081118d85f35a5792e2d7cc8c4a6b8d2abaa32bea18f6f2ff5fdb01	1	0	\\x000000010000000000800003aa61f75855c825a94fd80d9d8a6450214f40c51942221a67059861253922972cba18b9dae3370adaff319719c7a9ce61ad186c1805148ceb185b4d7b7c206690cb3fbe8c9e4ac6ccc5ad6db8dc1c6ad456c63168c288034b6169e055d536c1597ae9e86f0bdafda806f766414e72c60d0f4c39b90f9be04d077f35f5a6b41743010001	\\x7faa128b5371a8aa97009ec8038bf42c724b40098bbb430a62d98324e8876caed1e24fecd9b7e4de88fbc406895c41a1ab0a3db033e143a280cab558ca527907	1666521367000000	1667126167000000	1730198167000000	1824806167000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
255	\\x7a06ec9e864c03041e3d87661aca74e8b331fd6d385f1cac56034a927ba698d57b428be4966fce29e15136be6734095d585c1bac81b97ddbf5e4d4b33fa9bb88	1	0	\\x000000010000000000800003d8153992518883c4764e1f72ecd5cfb3adef100c9adf15a86059c895d99083b1243658a1f93ee734475fbc2acfab596c9835531c0f848023176cf5c3929a0ddbf659f95920121017d7642ca219d7cd04476af5e49f1ed936e6eff3069e6faf30b14e8cd1c3674810ec8386b99e9bb67e9328e732c3bcfedcfe4099290efc63e9010001	\\x7904d126d99f3509eebbd80f643c0ef87c03d1a517b4841c8f066a39ca2502dd88a2f3b59ca01e8f80e30f9d4149398677202190c8f459fd2584c6007bae2309	1662894367000000	1663499167000000	1726571167000000	1821179167000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
256	\\x7b3e5b3f96c0dbd3c202145aa6de364445fb7daa9f2d3c379990b399f4807db23946b9a8baaecf5619c9090f47c3c7eb110fef9624a879419f41c209ff73ae2a	1	0	\\x000000010000000000800003b18d8d03144e986dcc1fb0436b38be1b04e695c23cbddb34c763f1704cfad10c6d3dc0148d8462577230efbe30078698f308afb4aff20bf8bda7bbd43b5d28d5b504f4ce43c91853c3536e47641979a1eef867b7885652eef8254e38eb09e4a5d847c719e16883b33d81caaea227fc7aaa3c9082ec6b84485c41a565a3c23149010001	\\x2ee0d6e00adf77fbc90ae07e9fac522702cbcf740ec31f6390afee7e164e8fa5eedd61149bca285c7832e5ffff4330c38b025df5b3f0c8c7041d3ba4cb962d0d	1667730367000000	1668335167000000	1731407167000000	1826015167000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
257	\\x7dba70b9e0d13d676835b707ce3600d0adcd998dea88b4db38624e5a43ff0a2608ff466aea9619e30a277aa7d05c55854b5a74aaf0e4f0c25f716333df402d30	1	0	\\x000000010000000000800003db86488cc1c3415da723ca368f6a20b77734aced889a13864ce435df5e26065b3b8cf5e666c6df24c91a6f0a97b47d0541315f6dbb76140b7c0e99b4c2a5831ffa61d6fc769ceaa6a61f7cc96398e4de650d950f8056953d89c2ac3769dac6734b49bd9f844054c9f8d5ad891088cac7417edf5bab70ddf79f4d64c96b7a5f87010001	\\x31165fd0f0912f644276309584d0320a50165d76ca85f69b0bcd9192653f206b19c1c18c76a3601656d6fa11ed7039b2047521ea412f1ecc845903f4f987aa04	1665312367000000	1665917167000000	1728989167000000	1823597167000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
258	\\x7dc697673a47db31e77d56d6934003bcec744d9586444b742e9a955b5a55f5bd25f5e7f48f2143b4fb0743e0d6fdd0cc8ff410c479ccdc8014900cedd34a3b11	1	0	\\x000000010000000000800003cbf6d22f9088775c8ff036aba0e8817d1a7b2e1fe0833ce5089b24f7fe73e164eb3b067a7b57b316058f0ec6957550e68e113013dfbdc63a4a7dfd3cbdc6e858d11c634f75e87a1e89bc2ade057790803ad119e939e7c7cca7e198da97db02535b8bf2e231b67529fdaea1f18a4a8c86aefa46906c4b8f863b001864ac7c4c01010001	\\xdf89cecd19ce5e7baa078119ee541ede906d11c83cc3e4aab1821d3670a659fd676fd9f0379c15c79d1d3e92586ba2f64c9bf3dfddd7522e5655ef6689b3bb0c	1682238367000000	1682843167000000	1745915167000000	1840523167000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
259	\\x7fde6d0c7e7aeba0d65edfd6315d8f74fd77a1ad47a83a63d133db6a3546b866919cdb11294b18c676b3ce93caaeead320db26c217e731297a0fadb5bbd0a736	1	0	\\x000000010000000000800003bc4e3513c936b5d2de310ffa060532b7d8a7b5527218716d8b4d691e6e4b0ffdbd72c736431ade07f559b57a945df8b23d37735544bc83a2e436cab51af9ff6e37fbf3e44a9e50545492d6fa81e6ac829519d3ad03a3931881196005b9d0051125555fe8dd82c0d0669f94631ebbc097e0454d3fa0d078cb4de091d89372dd0d010001	\\x142850bc55bdd30f7f47f5eff30361148d1cc15f879cea999c4eeaa159bbdacf5c8fa1758b48659299a06fcaee6c790c474bd21bc38929a0752c4ac35145700b	1670752867000000	1671357667000000	1734429667000000	1829037667000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
260	\\x80465b259caff650cb649a2dbaeba891d1f162db2e573b89aec475a1e32b028980cf58b38ee25fe3c2ed3ef87e23843ab4306f8c3eca1e8892b20021d967ccbb	1	0	\\x000000010000000000800003c9f956de904f7cfb1f2cd6df76c26cfdb1aef76c98e21a69b5e404695918b9cb6bf5769479fe653579267fd14c77690bc72764b9f547893e4549cc8e0e514f7d09260720cd26aa6a77a5abcd5e5e3ea2335aec49e6af0547d6637342acfc2a4b629682eb3e126c09bc5f8b09a04d580d7e40bca8d45c582901002f74b35ee273010001	\\x0d963a9728d94ed89e463d72fa2c54da299877c10e517f1196ae50c4bbca9c5c7a2cfa5c9e17b4e668f0ec53fda9aa3a9638a4a9b0dc8e992816f84c2d54160e	1658662867000000	1659267667000000	1722339667000000	1816947667000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
261	\\x88ce1549ad77ab05350cfd742a093db3308f5e14d7c4a4ee1ae35016cc7998a13eb0303039f6cc44f3ff9b735ceb7faeee6614b572b334341a18b96dbff52d41	1	0	\\x000000010000000000800003b1ebb3c23f1b4f7f352f9b45f3d3261d7175ac664fdfa2d20b08e6cea8a74208d59d2ba9bb6eb9de4aa2437d941c23714b8c47f24c9c970019bb91bfb304b0a018c01fae0aa75e58fff92e7a4db17a6d0bb20582560bd12ac081de63254a94d5c09093fc0706de3e04421a656c9e4fe5aae2fdcf46a7a09efc3c152ae357252d010001	\\x5cc153aa5627ef029c629094e952e186c4b113e26db060c2344986b897dd68e607739187223acd5e8f43fc8191c31f55708c41aa3fcb5923f12a95e7c53d7408	1663498867000000	1664103667000000	1727175667000000	1821783667000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
262	\\x8bbae91a26612c40df5cec5aff5742decba9b3136c7b06b44a1308715d822f337dfa030c1c345085e382987cfbaf2b4217ae0122d229da941dffe965a758b36e	1	0	\\x000000010000000000800003d7681839ccf2dc1017ef117d6d296b74c22e36a99ff699c5246a33d66d0dcd008d103647e154f6141316aa93334fc5e757d6d6d80fc481a6c30ae3c012c2a632f5daa831ecadab046a7a31ce147985d5b2795884c98069fbf5c40913e5a50e7b0d02211e3615f7caa3a90dadbe05cde99d53f3e21d78027f41a84efd6965325b010001	\\xe2449848c1c49714aa673a2ed771c5523b84b90c66a289cd4655f88c4ecbc2da4a371c9f32057a10912065abee3a8dfdbec85b9750fcfbb633b311260507560e	1676193367000000	1676798167000000	1739870167000000	1834478167000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
263	\\x8d12d38b01948c86c6fed36aaf0f8ee1c4732e8ed716a74a5da6a2c64b2021add73e371b06563f5f9b5b927d25685aa3071a54c77765f55781e070af30b26e45	1	0	\\x000000010000000000800003bc3385d560ca880f0563f3d2fecc1979c0d0f227b8a59d1ee7b311d62c91c08602ab13b010f4e00439455fddea87d8f1f4122a50bf53c9c896b9753a3e8543ac834360bb919135b500c75431aee65ecb18f88a0bc776b7a6e8a4b8aac5c4ba3608a5227efb7b1114af42ea5e0b94119350105caec59a2320b6354d4e5b457a0f010001	\\x6dd55b6cd0928c2a3bac69d95dc326375d8e1f26ab79a88a75c715ff2d7d1c76bd9e8ccd983c12184d98d03ead0e5b65cc5decd2581277cbfe519c2782142605	1675588867000000	1676193667000000	1739265667000000	1833873667000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
264	\\x8fae987d02499879c0e81be9ce59af83b4b9bf2fdc1cca6ac29ca9371cac0c487b6032617cfb5b034f55e01dfa9d91d73078ebbf4543035c7f47e93331b14d8e	1	0	\\x000000010000000000800003d469845d3638cc0939a5d12bed34946cf3327b608f31e141d8f94bda538151413d3b1aadc08f444745115232d35bef2040147621ee3113a2a80d5976b4b25e8fc86641ac4474ef88e2e29159f09c18c99f114b6c8e0a6bc05737d5dea08a865b3672e497e0596b871223c643fa7ec77740f32b727bd1a22b40b101c1b099dcd3010001	\\xaecba406501061c82e2a86f0c472d4a577a5d76f59261a80cb22cfdc17a757f652abdf73b8cd92c48d1c8800d86481142ed9e85b72a94c4a3c6ff968c445c109	1684051867000000	1684656667000000	1747728667000000	1842336667000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
265	\\x92fe9fafaee08315defdec87adb755c38cdbf1d4d45dfa57cb2af9ab3d9059725f89e8e8b9bf3f8d91f2c7486064d67edae1d87dc0e692137101b3e3b72b38d4	1	0	\\x000000010000000000800003b3740c88db3289246a37df747c7a34074fa7714e70da48f501c5ab7d839a686f3eaa0f6c14e8bd5cd7699beb37a4fb7293faea08895ab072b05c4e530842ba5e6dbdc98fc291b39ea767cfb1fbb46f4248aa3d5350cb7a797f1440acc0d398979ce8ecb419d916229c4273d38e198dbfcb93ea4d86a9a7fc05521ed58dcba93b010001	\\xff7da6a2dd8923ff32cbda65922c155bf07dcac149d4b2eb87f8503822eb0de3b9b5a8b395be765396ea473a7f852aad0a360373864a6f05ec7f925d019e1404	1673170867000000	1673775667000000	1736847667000000	1831455667000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
266	\\x948e3231c986dc258bca4ed5073fe9d4ad061edc368fb727de7a77e72e9bac5aa2950d1da49445ff7e34bbbf5b5cbc1ebb344e17998b63b9bf167b4bfa68ab3e	1	0	\\x000000010000000000800003beb3d811a44e4d069280349deec99e7a2f620f41fd3a54c7a646f4de02d5f265dbc37ef988ebcceb4f9604b972e2b0d4181222baacab59a54fd5abe878ac9c58f6b7a73578385f7b325d72eb0cd39c076d9d07097a8970caec7fa49f2840ce3e391b69a325ea1db2ba60283509eb4a9683be8c9022309a0589e0364aeb58a263010001	\\x5c4035103b88557f80025bd09a942ef8ce6b398645ec810650778fd5890179a11110e740f3f64a45f680d3b59f612fb020fd3357adb5698ec6d081064197420e	1673775367000000	1674380167000000	1737452167000000	1832060167000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
267	\\x97c2d30b97b7ea4cc65c8081c94de88b8a5123481b0dbfccd60b42cf55e33a1bcd381fc2e663f6f25a31b67b5b80a8bf091438ba7304ae76999f581da09faafb	1	0	\\x000000010000000000800003b054d767a825f0387abbe92641f3853a30891c84af798d6e81c0474a2700990ad4f361b33b93b891cd81ff426bcdda4ba4cacd7bb0bc622e1db77a0fb8d94e8c2638f6ba8d9c01fc07281584125a9ae9afce749e6257d70d20e2c2a6d305713c48f4861de939c2c6e1ab92354bb0ed6d5f25b906b55d5b1b9fbaa4324d242911010001	\\x73123cc8afc66cec8413b248eae1b432a5a2aa07ff740a414e4df9df5e43780066d903987f953b46a1af8fd6a8bb52e65d02012fbcddb7b0c4068df3bb074e0e	1672566367000000	1673171167000000	1736243167000000	1830851167000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
268	\\x9e6a9fc408556275d8f3f09d5326017c93152f3b4b49bbccffed12a93634dbdd9b15c39c0ca66eb31ace0558fdb930148b7783edc9b3885c5adadb5842a3eeb7	1	0	\\x000000010000000000800003a64e120d17301e21704ce7fd084c1b8791281d814a2277e02c61a1924424d6fdd3bd97ed13511ff5f3df8254dd514da75b9475e0624bf8579008dd8f43139c33245012bab524c373a19f529c527917f3dce6660d2b79075ae25c5f3117c4cca3d946dcca4a79f8a0b27ae363ac64539fa5d19119fd9c42eef40a3872f956dc9f010001	\\xdbc5f3abea415bc1ed597ae5a7b3152f5fc754e945b8c7038c446a58ccf7139ce1d7646d2b68330df9b8d76cf06a5174195d54bcad014d29db82980df7be6e04	1683447367000000	1684052167000000	1747124167000000	1841732167000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
269	\\xa28ebc6a44eff83fd70c972ffcfc645b26d3555ab6c409f3e20792caf8d94bc912f37ca4b580b81859c9194ad661cbd3431e8fff95ef43468bab60efd806c96c	1	0	\\x000000010000000000800003b0512bd33668a9fe3ecd0a81e3f0d026d238ec3821097a6c59781944000886d2843b4a706bd0e27fdb67cd19644ccf2590f6cfb5e754a223be599b5406fa9b025d285075bc7ba08b3047b0d7b7b4df4443bfc27ee4eb7ad9b4fda180558826f8f56dc5cccd92343764b47b6dcd7dfa77269c80778f013a1190a53baa6a4ea493010001	\\xb126b480f62186812dfa20060b52286e9c5509bff9549fde3e9b28ec5efb1dd49886f5e84082864cc171e1370d462fdac887398ce98586be9091c839d3120309	1681029367000000	1681634167000000	1744706167000000	1839314167000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
270	\\xa3d24283da32369df68b07de3b3d0296d96bcea3cbf28a67274e5645b521edb6b3775188c9929a898db7567bdc8563235137c030cb78a67a9fdcbf059a34cff2	1	0	\\x000000010000000000800003d52347c197bff9f2cb52dac541bf1a8cda7161eaac1f50e47255f0601120b13ea270ab9a2ae3f77f68c86722c450eaca9423ba85500c5053e902ac873a54cc68a9c9df781641c939595c5b48f4de1e89464a13666f6c3c75facef88396c2ec7af8eb1329229d5e95520d2f5af86c91a87c6e75aa9ce0583f8e3946a60925069b010001	\\xd186b3dc7f211f400aefff301dc4ef4c56d847882ab38d02a38083acac8442427966b41befaf50af88b31d65bc8547372654f42e6e109925affcd54029bfa608	1685260867000000	1685865667000000	1748937667000000	1843545667000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
271	\\xa43a8d0b8f1e0c763549bee5107e1074f0dc1b35e5a5331a290bdaaf2ca9d13dd339a919d9a0449e18d31b45580a0625cc0c5a6b99cc7c7b990b49990e76ea00	1	0	\\x000000010000000000800003c37304b8f6bb6143d91640147fe39bb84781589f4256685c45e81af6476941b7574ccbabd06b1d46df3ee2eee470e96083868476f319c741cfe53dff21daddb022901f39a8a21b73bfbcf12a1801f5b457500c597dd8c3a797d045f4e92a4ca0d65f2b87f728817d9db0994e8d6341c6453e9636f284bb927f1e22e2dcc1a95d010001	\\x61283e117e81c829b47c88c0249137ade2b1b028c456f6344bea293218904ec61766631b47fe7a0d076ad4add82e355bc66e1eb3d84483650c19775ec7472802	1661685367000000	1662290167000000	1725362167000000	1819970167000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
272	\\xa5328c1a6c9821dfe97410ac14be91969a6c86a04e4ffbf96914ea65ca145e7aa493595bd732165b114a28bcdc2313ecdae129af77a9df4c378096768e9d2936	1	0	\\x000000010000000000800003cdf04df2d37752c5ea539a3046f1391024833f4d2cf480a2bf090ac515ee3987d49a951d6ce64503a9319e77234e0dc2703345919ca209f2bdd7a375db91a2141bc73d09eaf75b672f4fbe47625cc637cf5fa30c40d77860f4d62454562f23dcc7d78c0b7617446a916d781aabd3995acb32ce305d4d71142ca9ca689716b9fd010001	\\x1d38c2b1bbb7383888d1cb807bc6c71122c8e972fb204da918a64c7e624a42b464891cd49040a719b095da97e1e3bd59b4e1a17b0bf8d4aee74a54e7ca851d0e	1672566367000000	1673171167000000	1736243167000000	1830851167000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
273	\\xa9221ae254ec02c6b85b031a07407c6efacfc7e7ac1b9570e2009d9216661f3f69875e3ec3560aa01846bcaa1f77e47ecd7f986740cb109df2ed36f60f39d658	1	0	\\x000000010000000000800003e4fd24e449c2552d90a9f8728beb6db391afdbf3c352654604d2025cf33f44623d4b729f87a816daa8c9b86bd423a501a13987a1ef5625a52717f2f4f7d604ad9a1400c778f13a147c5fb2b92a13b0bc943d36e5418d21a13f00edcea41001e4bcae5aeb37c999031c8b361716e1f870123e988f0630e960c4ee9c3a6203185d010001	\\x581d8698d616909f5e240a5a6c55a751b205acfe8cd672c9825182e61202188c357c94badc0daa70fec4920c18c1ee88bbb58e4e209c9dc64c04072dfcba7800	1671357367000000	1671962167000000	1735034167000000	1829642167000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
274	\\xacdaea04dc08c2c636389005d6220c6e9c355e37fe80ae5a5bb213221cff3f0faabcb03b6c2f9279139c3c861ce2bae681953a38946b9d8a9570230572caaec0	1	0	\\x000000010000000000800003bc8e35d265044f91573812ad59260c9f3857eff79b39ce7183714ea77a33f106a5299893a773841e272d576ae606a24e6e1cba253e1acafcd5d3de89f80afb5749e1935ca8a54068b43583d83789c1e0d80a9119ced391c0a9cb64addf51ac00b18f207934a3f7b423b5414ff748df26a3be27ff88ba115af807cc4c33035083010001	\\xca6d6a552a696c5122898335cb75de5d36a6bb9562f62ec2bab580c5d0391ae41a85d5d657a619fd6b4ae1f7bcdcfcf1e9dd583c6d83075f3b8643fcd81d220e	1668334867000000	1668939667000000	1732011667000000	1826619667000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
275	\\xae52d9c8a70f658f27fe21c236cd3cd794aa15ff5a87ad848e43be28d467e8e4411346fdb8b1c88866513081363c92b73dcfe9a4bfdd98f7741c6e481b80e3a8	1	0	\\x000000010000000000800003d15c66ca261e6fce8e6b8e1a72fbd357caffc31c48ecaf80c456037a09d678b9e6a126c8d062de4014a53df74b781f0a3a280808f6474d10aa84c7fd55f4696d46a21f87496e3dfcb6f77a692c8722e62c1f59faeb365327ff84f37d02734cadfdcd7706b3fb3f1340b1b0b6648ded10999150f42fcfc4b0aade296e5c22c0d5010001	\\x0a1ebd64e094211832a1d9dd1107d75f83fe3b92805b5dae31fe0fdca8709e4e7f82f4f4bc65a72c73cce814fcb2dba8c5f9642553ed908bbfce581e92ff7800	1673170867000000	1673775667000000	1736847667000000	1831455667000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
276	\\xae86ee3befd2bebef11fe610ed40cffbeefb708f016b7569efb73673b12bf865f298c641ac9a3d380f2f14458604f0440780eca106f59534b34c772225179da6	1	0	\\x000000010000000000800003dbdfb2904b5cb30f7638c103da017ccf4d39645aaf4bbdf46b6ebb19fe12c8c696ceb9379e4ea2cba3a191a61737c04a0a17821ab3eba3a9982d3eb49a58bc3b16a5517e05dc5c23b45bd89f7c8c72e3acd96f5eaaea899af3588369433b0f8c0609dc9bf2d77ae5f38d525b4a3388d9db278491fbb171d54be9ec174a7c539f010001	\\x22c6cc98a1fc52decd0c1fcf9d8d0f34aa565a92d772a606dd9a3a72ae87f7197986303053064532bd08ff8274fbfcc7206d7a3ee08a28ef98338c7516c2f40e	1655640367000000	1656245167000000	1719317167000000	1813925167000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
277	\\xb1f202751b5a37f534323535c82fe36198c7038ec121b311735f3c798915060ab4db9f791f440a7d229c09510d77609e12202c97e9e6e8cc2c9c971bc83b35b2	1	0	\\x000000010000000000800003c727cf71ad813b2b82f7f6b2c00760fd83510b47b4957066b6678cdac12c3763e6fd9be233d289cf2ffd3ba4682cb9c3a726f9af2604b38c1f9065615d1b856c3f818144d222b7707d9203b2a0e4071d5c0a0865c5a53e3889a730a838895449d08e4c68e0b3e1a709618ddf31e8c0da63c0576efe8cf92a5e604d61a9070b9b010001	\\xd850b209fb0a9c9d674a7cf9197b67ab5c72b7ea290a7cd20486a7ca7dbf453a963318eba436d225e5d19a6ace01cb2d69ac60efed7c37bfc5a1cf4beec81a0c	1678006867000000	1678611667000000	1741683667000000	1836291667000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
278	\\xb41a566e20fc5d2aca1ea3dc7bdd5e8b649c7d94b49d231f638d7cf92dd31faa597ffa15d70a2be87a1837ba3a792632e03929dd0400e86159c31d356bead8c3	1	0	\\x000000010000000000800003c7f48559b205eee1e7dd0388b025f5897a3fee630a7e773277decfcd62fe87f18e0527d8cf6ff04824fbaf560904f5e6a10a13bdb7bb20418a0f6b4f7b1f284a62e8421650fa07b38430ca20752ed59d7694e9d1eebca170b11bfa3173028dbb42210d9a391bf1e138aa8c7f187de69d27c22e4e3f65b55236aae27457e6c611010001	\\x23fb3e9cf0f6da7e5c34f3e6ea92510c38ee43b252a78f128c51b5decafcca84b767f62df0e9e4e8ce4a2782bdd4ad288dc53a4fa0c45a25485f3ff4f6c8180a	1684656367000000	1685261167000000	1748333167000000	1842941167000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
279	\\xb56e61c6e23ec7c5b1d9460b232ee91a165524cc65c65c446f44e7a0f03076041319873afec109ad11a6b36910e219d6a646a48ef3a49ed6e2d7e99437c7ff6d	1	0	\\x000000010000000000800003d94282e52342f80bbb745daab99410f76ffb0f56d278e8fefbff7633d7954eae690c63d288fa30594326b8b7053564223db3649f5d98b2f39500a9e60588ce5a5dcb40aeb8f44f75392cd1637d22f95eb1fa2fb684ea36a6f097da229331128dca8b1d73aeabd77765f6cef6cd7a01ec1f07545c675aedb7eab2192697faea3f010001	\\x37ceb11a41b8cccdc9305dcb1480ea05419d98500168f12b5afddf1149b51047bc0affdb80ffe641879107320579cdffa1bae9f0a55a89fc154e533e5d26320d	1681029367000000	1681634167000000	1744706167000000	1839314167000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
280	\\xb64e1811b6bad326343b6d153763284fa79264d8f534c2de94458a4ffe80e8108d3dacd643507964089d3a1ba5bce5388edd7d1607f5ac228c69dff0c16d698f	1	0	\\x0000000100000000008000039cb76709dd3d9707de5fa158f22226e760a905becd7b8d6131c03a0d9348806b1a6959c419c61aeb2ae5ab894b6bc1a03ec56ef574d81aeb796a8884516bddcbf11f8d50e350848c57d2cb9624eafb8b0f599f974646652f8558f66917764bb5e0efc5cd6a7b03fae61802c46fa304688388f7f22ab53ecece552cf9cbbfc635010001	\\xaafdbf4146be2cf4e24373dbe082829915fcbff9259576888dd8f13ff036e485be6a6aaf3049b3a2bca692bee06b11fc2ec6b86540dae6bd3dc7cf5a9929f906	1679215867000000	1679820667000000	1742892667000000	1837500667000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
281	\\xb89efee1de588ea67214e316748e9489436cbd249a4b7042ef268d0a3fdcb7cf48c8d46372145251d235a3927f3e565c2c2030a8f511ddf5d1bb50a3c204b684	1	0	\\x000000010000000000800003af51b6b0bc2d662bfe14c0996fac9fa8ebdfc235ac5377a4cdeff7a1a292646ae3d3e7e7fd3216bace67d52797c1b47e625e4cae801ace9da6aa3f886b54e428136199092d2cbf8904400b36375b6d732755f4b529c3bab7d182ca5a5cbe7c7e28132444b36bbeec1d33e4520e0cdbf2cc11d9a55c80716e0db5d01a4e8bc2bb010001	\\xedb9b83430fbd6ef4a79da9e251f53e85a51b106f12c2c78401c7396ca590a80735d505fa3ab75fd20c4229b34557ef115ea0f80f457c81466ae2abc6ddf6600	1678006867000000	1678611667000000	1741683667000000	1836291667000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
282	\\xb8daa6756662e03d001212d8ddaca6b91f813814ae38ec2c01c354c452cd35513bfa4ed212ce21c7f395ca6f240047bcdf7df50fb89aca6f5c446e9cc2af5fe6	1	0	\\x000000010000000000800003cc6b2197b94aeda6c551077cce8eb4d8356d46f08b86ac9ca70f2c244e518404e7beca419eed0d79cee68f8266b40bcfe05c72d2b9520f6f8cdddeb44b4167f61dfbe1717ead3bd78bd64d8ec327d3341a3a2c55fd56bebb355e35d9695b104ffa65c4889398a835f0fcff90bbe218c14375504037794acafa5b333ef4889dc7010001	\\xf8685702521440216445a713b6287ab0f4047ff11ead16de4329a9c16402aeb4bcae1cf3f95e272ed3e5dbab7e8cd20c692341318be5d66f0d6bf335aaeed50b	1672566367000000	1673171167000000	1736243167000000	1830851167000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
283	\\xbae65ea658fe567fa1e5a0bc5e230db3d2d23dd615372cda5bfb6659f7a17cbf86fce75c6916d97389cc5b1358b0342917d335580e0b9d7472a1eaee0e0e7f2d	1	0	\\x000000010000000000800003b119620ee133f19414ae4d6179b2b0afbfd6e6a5d4f7313b7bd78c8650208d3ef6c83a99442c9ff4b2fb393051f439bff78ad9ea2e57da3d72e85f58813e1d8087108c43044cccbe9c8fb5896f737a2d764ae437ee4d20d366ca78c0f556287b111dea4a1b9465c8b561541c3becdf2ae21913446175b9e10a7aba005d75f3ad010001	\\xec825ac00d51d45a36adf8611ab61380d950ae895d7f109dc6b9264281c2be5ac6edb05d6af34ca0d50d49ea794adfe0a15a3e1a74173823eb7731124f077703	1667730367000000	1668335167000000	1731407167000000	1826015167000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
284	\\xbd46eb43e3d763b1927334cb3df6a7b0ebff2dc9ed24eab594e27651ffc301f4fdb424a31342ec509a5a80a7215cfeb3fba245982553531005ceca111b7af143	1	0	\\x000000010000000000800003ef82b6862166f821cede658298c5b131eae0983bcd5d040e5733c0da59774e98206c0e7dd189edf46e3c09eae64dd91b5d1ac94c97b8a17186a871c275c2b56bef62a27b36c46c6c391faf69ce69b6956e7da375485af7c95f80bcc20a739549f762e92071f2f4ef8c4e2f9e257f2421c9224d8ec9e2bec1dbd5d6ef0241e0f9010001	\\x2175fc57c61c813bf34f2e18536eefa6d4e76cf8d2c01ac25a438868d3bc9393b67bf58af75f4f96c1806fdea2545ad81635ce479edac8f411d8b220f70de905	1678006867000000	1678611667000000	1741683667000000	1836291667000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
285	\\xc016863d3cbc69f5160ba6824ccd650bbc497b62a63443c83155129fd8d877b82930b2171e78dd57b593185100671d9ef61e31fa2fe81953800ebf2bec4e0eed	1	0	\\x000000010000000000800003ae30d3d753706cf2bb53210a214aaa426a51059b2fd0dde3a54ab483dd05bcea658c53afcc697fbc79463a30e0e144245062bb32ca275cfbad6962cd5d4622832701e6f09e284be6f74c05a0502087344b04db4b13d127ad6783c2cd4511a237b991510bbfd2d2c3e3a62d0373f626097af853902b09cfc28cecd1435f74f793010001	\\xfeb75cb0afe11768d0b43891ebe7a80236b131fceb2d5051f99cebdd5c31f952735ccb6dbdc974316e0e5d0f6caa6205d562047a0c59d34c0dece6be2ef89f04	1675588867000000	1676193667000000	1739265667000000	1833873667000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
286	\\xc1e6656ec5fae150d98cb301b8da256792270d5507cc035f1a43b800107cd225cf8dead58282ae2605ffd8bb7ff7fac4e301d14c87c85b22ddddbeb6e76855a2	1	0	\\x000000010000000000800003c816293dbdb6ac78a75bff46ebb743c6baaeea18c5257a74eabcfdb58c3e4be2ac9c736f47c4910e33f1431511486884f4d115426f2a49dbe000e393fcad8b01c53258631bc80da89120125cb56ed69982d5fe3831613dedb4c1c69a70cc832f76a4ac5faf511cf2977a082e3edda6b555ac6776e00897473436397d3a1a1e7b010001	\\x9f9d5b5625d2b55f7a24251f03556e3c52e73f39ef7d865fcf742542d8c5211f3d669040b30d7f3481b6c800e437e6b5fa29cf862959844d3a1c2262a9c43e08	1677402367000000	1678007167000000	1741079167000000	1835687167000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
287	\\xc1c6f7b67025c2994e4c1a70bebcfe2008041bea2248d8e66126490218d9c23b72f7b8b94c33dc86611b84b2ede6aaad6a323540c7f6bc28ba4439a3ade3ba7a	1	0	\\x000000010000000000800003b531f8b2b557665dea67971bb7a3167b01b194ae3f1aab6d77acdfbd1544a6a3470ed05a8440249dc696104a9bc8866b50be187a46d028868321bf15321985864114d58c77fbbd70140d44df5df40373eb3bace8ff828491c5501dc37f83d6b35926d9146ecf4144c63bc399c62ba9d116a177ae3085b660c945d1cdfcfeb639010001	\\xf13478dfb123c025fc6e8b3b01c53e837bac642079b1e4d2523717f3e55b476812097c4d445a685480e22793c0c45fd2ed6e03fec4be5853f24e382cc2329100	1670752867000000	1671357667000000	1734429667000000	1829037667000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
288	\\xc2c25abdbf561d99f8ccb1ab99d5f78d138ba48f8efd383c90116c379a47be6fd88cd64d01b24bda8ab0ef5e8980e25fed54c78706a43027e6f9f730f38ffc79	1	0	\\x000000010000000000800003b3c0b589a9d1f1e7aa358991548bab5b438fd027f11b60f33fb5f2b3b236337e101ad8b824436f5fcb12747809e741c6f895bc228f2f3fa4753d4fd971af1b29a017d9c1f092fb0608cac6fc26705db13d33af182094e1cda0ec17a5129afa52fc20e1be26d646925f36b706cbad4d281a83eb0c826fb5f07059f47aede93653010001	\\xe7f3fca6a7fb764d10b54ab41732a1cddf7bcf1b295a1da76519b8c483b1cee118f6f805a8d709cb77033532d3262a06a1c07b428eea9ae6eb679372dfacc301	1673775367000000	1674380167000000	1737452167000000	1832060167000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
289	\\xc3a6a1a28dd2753c14d1d48e1f10d7d4ad24b83af9168828565a50faa70cd851dab25cf0387094d5125159af603c70681d5ad53d1f96c90000e551f97cf081ba	1	0	\\x000000010000000000800003a71dc8033676db9df744e9ef87c30221a547dc5f08b3aaca4cc49c47ea7bf39c740317d88647342f752539daf97d82bb6914d97debe52b9ff0518e8778e2de7ac42895ca41be321c457bab35d05cee0826bb7922780f1cfab1a6c259dd9d38f16b876216e601969f74aedf30d330ec99777c091bd17cc45186ea91f50ee1e5f7010001	\\x1f4344f5354311cdd62e4c7660033eab4068aa95d2c95500e7def9a0211eb9cc96fbc5cddc90c6013c264da54ca0b4221c28fac366ca95e91f84a0cf6bf7cc01	1658058367000000	1658663167000000	1721735167000000	1816343167000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
290	\\xc552781dfab244ab99885632f3d3a0e07f1a7e22569c4d93beacda3b5380fb17a30cded6264e2010460d2e1c0fc37422ac31f480ea6fad1aabb48a73b2826327	1	0	\\x000000010000000000800003e3f7a6b8cca23ee3937c2e70723f1e7dafa5ca3d856c047ccb61673529e435d344eb7f53b213c940ceb001a29ca4ed5d317512d8a48f63f27488aa3e1f9722ef9e7c4e4bdf07798478d1585feecdf9fe855e6f3d86489b9d5940b74c635bba970532277ff1f866f688b707796f45022ae63dfcddb715fc248ab001b3c4d8cf0f010001	\\xd4a3a82221e7829e41a6cdfe9a94b995f9208dae3bf0df10efdce127d6e99af5363bf0e5076389af19f28edadc8e5e81b15f598b197db176442fa0fffc89870d	1664103367000000	1664708167000000	1727780167000000	1822388167000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
291	\\xc7421640362060b0b295d70f14a26c5f38d17b53d0f2b83f471ec7b8c8b4e8837a2926912c3f6b1c7102b50d475f3ed357bb9e39b206d7627bb4d96e515145fd	1	0	\\x000000010000000000800003d93c81ef5bca823af975bfb506f1acd3f166cd55d0b701773a6ac7411dd420fb84b90cc04cced244916d76654dd5051baa3c5083eda49ca94f8de327991dff294d3a35d86e78f75b4e6dfb798679e9d6efb6f16d45b5c71a6c278ab8714eef2ae2d0c26440652d4618c716200aaee7d117c0d728f0ddd1dee9e5ad9f4eae4eb9010001	\\x7adafa97480640c38e208b55367b29d49bdc5179eca80dd1445470f791031f86738024f88ef2fb0e7b24e4d4f1b667e74ed295384f81a4b9882da9a1085d1c0f	1658662867000000	1659267667000000	1722339667000000	1816947667000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
292	\\xccbed1c4fbf25164f05af326bcc254769e39601815a8e9aeb35985f315da30469f491f5c816e18af2cad6404e95abca6f7deac9e8449074391b3afd9c24ab680	1	0	\\x000000010000000000800003ceb389bb1ce078f48fa6745e7ee099db1f401498f215e73f67aa31db5d4be171d7b0606df3342b63ae25ac187b1a878d49d64b6e8973876066b9d6b39b6b5ec77799368ea994c40c85537caab2d8c8dc0eb357683c098b9e8e26eec1c2a35de1b6d73b002223fa263b4ae0ac62bb4f992f19174df5f7a49e0bd8a5e7346b0653010001	\\x98c02bd6f3dd5f3c3ac7e0514b30c5d800891baa010782a792264bd6c846e1b258f2f2de53c0889e6610b6c3b7e69830700e4477ca8c3aec35e171da9df2cb03	1656849367000000	1657454167000000	1720526167000000	1815134167000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
293	\\xcc3efc8d9b6b01109d9934b8e19192ae364c6759d9e10cc8a0801a76802713bb108770ca4982250fc33af7846e86e9e88eb3d7749da2214adda81510e6a4e0da	1	0	\\x000000010000000000800003cef7281154f8aedd23df090d0408bdd1c553e44136deec9889055e3f59027a38f5667463123e7c2c91f17165f0589c84c1e46369d7966e87753f6f063a4168323d542c7b130e064c5fbde0b50eca6eae75319f49d421bbf28140780d9116e3ea1e0dd4a3a8b13f7f2dafba6d3353a2a9a56639c79b863a2407068e6b70516163010001	\\x4917f55185492fc3f2893160420fcb9578345233b43d818551ddaa271550497bcb6076e2f8d7b6f42d885286d44a4ee86f4099a5050aa5f4124b18172664e60b	1676193367000000	1676798167000000	1739870167000000	1834478167000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
294	\\xcf92631d9295bf53e8adca087de47b10d506432b0cdbec8ace81dd665e53f88aed506b99b034f8f9d514a389e8b463af089af6f081168326e6c3279d9d9d8874	1	0	\\x000000010000000000800003df1e7062598e407960bf876e95371a315718007d086266b6af13ff2ef326d2855137bb2bf109e04f441686cfba4da4cc8291bc753616fd265a1b929b4bcf3391af93ac8df44029f977dbe343aa46c24353f57608829357432e7ea029ca4443343a68d487ff26c2ab01758c88a0d204fdf74c52bc825cf52de6d9d93502c88149010001	\\x19fe29aae11077d383eb7cd4daea01805b991aa9ee20f05f8313d0f1792b2f5d33685c5eb65487d5aef3981132c12367032d5cf3e9a6c47d988906729dbd1308	1677402367000000	1678007167000000	1741079167000000	1835687167000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
295	\\xd126de3b3854dfa793076de68000fc885e612f459ab968c29eea6670cff58bec5e6d8045851172e87745c975cebbc673ccc57c8191477a680e9b3a0c542bfcc0	1	0	\\x0000000100000000008000039869be18f55108142bed38d140e955322b021b1c6521fa3a8075d7f2f72aa3bd6cfac3b5497986784e6863643090bea6111ffb16384fb1a9d02e5e310f85b1736eba572f798a04526c044207a8d1ea9a11b7e17a5cdfa7f140d476d6290bdb6d701d32f7b87ff051463aa610b02ab1fe76bfbed6655be10a349b25750fb59ad3010001	\\x8c192aeb746631beb5e8bfd0a2182fbb6bb0d5c9cc1796b00d4413cad9754f0cc3835d429145f8be7684566c5bd9ea852085a117c3b2cd983de6a95a7a40200d	1679820367000000	1680425167000000	1743497167000000	1838105167000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
296	\\xd17a4919eb0dbe91debbbd209eae757d55c0f3fbe6cf3e561b4dade57747f46a9353a45a69bcd3b42d895342975b9ad24b4084e058c59876fd3f93d5c7ba6383	1	0	\\x0000000100000000008000039ab3e3ba89a4c4d3412874dfebd03c284dcfb7322e38caf1a6b92614413b8a77e17c0429749835d935325fe3f7d25a619340b9b6c55c832baa75f00e35f16b06c771bbb824ddda5213efa1ffc0dc2e81b95f448e5acdf408faa131e6a6acf70a378e506871f2d85cafcfba128cf2dadda3470477283d6ea73ef5cf6886e3babf010001	\\xd3f4cec27d18c55b0f55f569fe1f0571ba2d98c8c422686caace6b02d057f15289caea375a3aaef957e38a543adc2fbf6bae3ba2080d9e24e6ed742eeb868a0a	1677402367000000	1678007167000000	1741079167000000	1835687167000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
297	\\xd2be2e7de577f3520f320d2c85b97045630eeb0ab900e47bf199b5b5c1545b0c91df0cd7da55179cba1aafce9bc57069b76cd984786841824ae53d055813ef63	1	0	\\x000000010000000000800003ab1d6572beffaab0e0b125bb3b8a76eaf36f948e2e2fc5c93c435cf2f5c25aa4c781299248cc714da23bd7b12738679635d65015e11da32a22c6acd7b10499d8467b59aface5b0fb6a3cb1b0f689a66299b087dc6d57780f571d0d170ae2c19807527fc7c7057543dd70e9f6880c21ed386c10f17d3689c182ad69b541cd4731010001	\\xf0b2b6d662324817d79c0f45c77b16a0df7d651a06fcfd8266dc29147a37029ff860eba36092739cb57fa70967bf972ed09213ebd3703ca1686bf8797972bc0f	1665312367000000	1665917167000000	1728989167000000	1823597167000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
298	\\xd39afa8f50fbe0e6aeb98b5ac8f3ac5d970c35297ed0a0fc0e46cdaa978f2a4f84695860a5baf2f6ad283a5437c85b65169186d3296ab275a2fd04a4aa69f1a1	1	0	\\x000000010000000000800003b53a28b6c1a18340285ddbc7b1fe07818f4c57204c43fb10677c14d2c98fef52434152b400f85eaf489941911e036369dfc8baed319a192f16264591909a2e6e8d9bd9bc62083579debb13eb6dec1d7860b49415b46c45941d07465e6a93aca9693b23584a5608321cfff2547fd819288a5f2890127f112b75ede8fc621408dd010001	\\xd5931265c2475caf837b60d18fdd8ed154f0de074056d3fb3b85058587d5a8848c5cc1cb6f4fa047a8edc6a33adb5ff6111f5f044b090fbbbdff30577f811d04	1684051867000000	1684656667000000	1747728667000000	1842336667000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
299	\\xd9be2e47275954b419342dd844b760598ae06300bf3580ab44d255f7b6c473153770297fff197f21070bdf5154ffca2a8067b9fee2b4c1d67ecc8768e415d685	1	0	\\x000000010000000000800003c6314727cd0215a28cf351520de3307acca81458e65ce392895b4f94b40757c28e438278ddc6b305eea124679b32d7a8842e58b2dc8e206d108d4b2a55c6a13251ea656739a28a8bc557e915af15788870cbdaef4b8aedb1e523b01b3c14bee339ced0e9a5c8238a5d36836bacb397886be5bcb581565a016c0f8de6d684b299010001	\\x86a502baeb94901878353b02a6f7c046a6194e51e2422c45cfffb2f1cae444ad415bb398f167d18ff9216478808b1bb4b01d985c95fd5fcc45649b3b31146f06	1684656367000000	1685261167000000	1748333167000000	1842941167000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
300	\\xde0acbc6c7f09e34a6a0e91203187a7c50e7c4e0e08b648e1679b45c40ce85f9ab8d13dbaa18e0af751da3fe4cc2d09640cb24635eba0f7b15249692ed1a2a3c	1	0	\\x000000010000000000800003b2edb1dd35024af419fbe03340811687a62cdc42c8d447a325779dc94816c6ab37edf64f99183aa0e8d21a768658dcec3c9f12046c0596504db11a5ce83638d1b2901039546d36a134cb772bb62d7ead34d4036809bce49d9f9713f45f034a28f00431b6d835665751a117fdd8b709446eb1a672e8b2b210ef9f8fc19935992b010001	\\x587725671ee07ce9a0b5fe8eb47c9245a00536491f9d656003fd05578074f2022958a7042a5e8bb8e0e9eaa88939cdfa78c57cecf8ec55c6a4828922176efa00	1659871867000000	1660476667000000	1723548667000000	1818156667000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
301	\\xe34a92d329550c88039598a3c86ede2e6f697b41d5ef18eb4ecf5223d204a6802e575c309edd7cb37011629b726f50a3b972b55c700213b812801a3c9b17e8a6	1	0	\\x000000010000000000800003ddc3b76e444e1f719871347d9a489926fc82d0534f48397b03f833d0505f1813566396a6156b3f908db0accbb47e89b2d906e0bdfcb5d60aeb954864f7b657d04f49b6bb49f8f9bb07ad27d6f164d7b3fbdfdfddc90a4009530d47b57b680f10b2916980fe26effb6d68130bf39f032e438d4c5c8ef9403077680beef8d21909010001	\\xc7f5de8761e204688701d298410302206a442c733aa811b395c4b7a098c1e268285bf37b9c8e4be7c09c7d3f5642f2340bbe1aedfc3b8d253d04bb236f7b0500	1667730367000000	1668335167000000	1731407167000000	1826015167000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
302	\\xe482b7ccd0d5092677cbd2a5662bacd4e6f2bbac1d337513922ab7b7f156a637123cf11bedd1af023a45646cd3624e7199c07ef0d39251e86c2d90702f995a62	1	0	\\x000000010000000000800003c236ea39e84918b7165da08d2427833a81b2c06782008d1ff19078f6501e079e22d7bc95c3ec8524fa5e6a104aaacd93347d08d63e72b86fd4082050f47108601d5ccf3e90a688f8a9ce839d67a608a31d677aa10ca5cd14869ae7209873f32868663bfeed032be7cc663cee671c5a56f8d48ba3d23d3589de99b4f8e517693f010001	\\x8027dcb38aa968adff760bd1c37b5638fa65d2c71905296c4bd01673faf21024f8bb46581bad636708c2d08dee29b6e0131227846cbc7a395ffbdeb870b1f905	1682238367000000	1682843167000000	1745915167000000	1840523167000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
303	\\xe8268bfe9073c309bb57f201e088938b24ec88e47412e4029facdf7363cd89ba77e2d1c62c47333af5cb7f3674a7b8eb0a95b8fd988c7286d9663da258026579	1	0	\\x000000010000000000800003baca0d45b1d1087bb3fb4760b0593db3abd746efa2bdd7bfcb4bfb2f4ac899d95149ba89ea7bbff0ee121e0498949810040d8c0f221979e345da930f59ad8e0aefee1e038bac0b191a1c2601beff77705a9bead63b361aa62cd16696c78c199a7e65e251e6e855178382f4e5471c97cdb1b38b134806325c25e5faf95404d8f5010001	\\xd8b260651185174b1e6541fc8260040b9df5cd6b2fa3eb0bbbb39d3ff1ab75e133fa11d36bc6599970193e06d9805d6e9eb8c96c22bacc35a24d0b27496aa200	1666521367000000	1667126167000000	1730198167000000	1824806167000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
304	\\xe9b6a15ee08cdac34c77ac12b34be56bdc47cb7688708e0a7e8ebe63edbb47cb935dda11797158579f2cebbeb3a7ba3254b756afa4abddc3adfa1769f61ad328	1	0	\\x000000010000000000800003e52fca067a46286ce5eb2bec735eec3350da706cc7b3285ec1092b3bc257311211f6109706b8bd6ef9d0e39a13cf27628057909d34f1c801f40503edb78a94c9052745fb86b0e723f6878c77ea820bc6f0b41c9065d5354fb08922ef4ae89d2516065f69be8bdf4cff0aeddcaf58972829d6d8c2540239112efc49dcd68de94f010001	\\x98688314bdf5e7f1ba067db8b18f2ab0a3b602a6260843c26a2caa7d2684d0b54fe1ba7fe407532598ce49469b930a3a06489c995b9c72201bdf22cd877c0804	1661080867000000	1661685667000000	1724757667000000	1819365667000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
305	\\xea7688d0b4b17ad3b4ba4a220e09df2c5b9cb67c44e452f3e9638b0ed1efb4f6a6cbbd330ca8c3b89601b1e315bd49aaa7b2bf345985272cf04d996b32089638	1	0	\\x0000000100000000008000039e2740cc210aa59cf2370181873bac8031e6cd97fcb51f79129eca8a0aa7c2d1a2e5a858ac57b3aaa096983a3b5b21feef0dd3e97f8164c4c4ad5d3e735d56b8ca02a0222c5903643f87bb5b162dbbbf4d6377971472d15ff6636cc589a18dce80b6d120abc0df4b06a7cce76215702a8aacc795295c48e37990a307bf18c9e9010001	\\x6704bb478cd9d5f5947d49ab02ff16d341b15e64cd6306238ea5b446c1e8f77e312e55f813956dada539e669adbe84f13a0b3289f33f285bd075cccc4ac7980f	1675588867000000	1676193667000000	1739265667000000	1833873667000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
306	\\xea46ee9fcbb2c6efdc97bc71d5589a898b1e9fca87fe806bd68928b00532634ed3d62910ad04c24aca2eb21aa719ea31ac3d509d774ea776f6cd12eaabb9aa7f	1	0	\\x000000010000000000800003c5e17d19943eb014c3179e058f3a76477ad71c9c4a783a0c3df9e843698b6fbd17380a0c890da3b6d7f4fe3f884350f1d36d4ba41dd9856f80c05dd266973551980bd11ca3e1811149a3a54d7880b8b7827279e1e9cf79025ad8e3cfa018c87ad220b6fdc9db378fdc7f95c75617452f6911ea0ea6060025bc5c20e588442cdf010001	\\x38bf866b9f8845527d3639b05e471b98674ac53575e1bc08d9e84fd94742e3ccff5509557b1fc9932356d0c7f05f3e4571941669b5420ed9f0cf07649d4d4f08	1656244867000000	1656849667000000	1719921667000000	1814529667000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
307	\\xec5a57ca29751f0a3cd504b901633ebf4afdaaa20be0d0709b083f7167bebec007353a37142653767d9183e9ac7435fa8da2fc112b481cce991e23ea7f8bc282	1	0	\\x000000010000000000800003da55e6970568761a0ff4d6480906d439908e86bd74ec3fd8d1ec503e6bbb4d63cb78589a2fb05ed03b9cc519c4cd6175af0c031ac774684398295754c4f78c6f7dd17ea027d8bff9d7a66c5c6ae74eb1f0bbce9f51e412d58e45aa696818a3e54659cc188b5eb39be0a937c649bea8bc0a16c2bfed548c3cd09d6e9432c6121f010001	\\x760a7902c4d5e3e27a198e68f87a88b30b861d783d3f065ebd1a8859b4c2d7c7087fdb17cf5fd6fac5e2a8452737761b59bb85748709376d410cfed588b6a009	1662894367000000	1663499167000000	1726571167000000	1821179167000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
308	\\xf05e198f9712949be02064edd3fa272928b833309bdd1752610b98d58f2fbf3bef68398410dbd5a9dc11764df4f664ed5b021b9a46bc108f92b94d0f127fb5a3	1	0	\\x000000010000000000800003cd4daa5e230ee61dde4ff057e19327c58b9d7a46d3661a2079bed483cea7f486b9d3e083971ec19551c1a7cc978d7a2934e5a0af83ac7cc9d5c0fe254fd4e1ea71daf9d285ee9a1a76c32dbe92b2f757efba405060eeee814501209dcba11d3ffb16d44e56bb9535cc49f7161e6e435f680e2fdead3a1b4e44de30d7d19c1f53010001	\\x8e2226f49a705cea7bcf730a74390d92079a453c35abdee83dbb10daf0690df78fdd54841e996fdac3f81dc029d53128c90d957445e5b450778de0b17d3f7c04	1662289867000000	1662894667000000	1725966667000000	1820574667000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
309	\\xf36e3bdd5126bd43e40901ccb2bdac0d32ee0d17db19ba48023c0d6361d0810add0e89917515185c5162f0452e47c6d48b707014a34152729fdc9e80b75d1718	1	0	\\x000000010000000000800003ba6127110da8111e722a441fdd5b1385d57ad1f186d5bb183f497d02898ce2080c1580714bc866135108e6af23dfae61bfa758f08d605db8c633d3e52ef6224e8350157b575c31b07db4b2a3067717f97ee12aa4e3250ada8442f086479188f1ee9c79e9d54d7f15060ee08b0083d14c0588e0b28b37af6ac6afb929ef49bbab010001	\\x875c18737851761b09362354cd1024ea85fe764e83a7304ad5e596d0cf574e9046d85f102c32022f9c4de3e00ab83661d6f3a65b9ad43b1278b7018cec4e0e0f	1658662867000000	1659267667000000	1722339667000000	1816947667000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
310	\\xf52e9ffc22c7545fdb9ca042ed05cb02453cc41b97f77ded6dcbf560dbe9c3b63fbf59b5b7b5507771fb7db1913553aecae6d92bf4df47d7111611bbdb74b1a7	1	0	\\x000000010000000000800003e1e924c134b1e996e1a2948c9c7f42419341bf5eb0ff594c899c5047e9d7c3f870cd0b2d0b412755db70332e236d7a575420464e3d2f7542b6acef001548be23b3510aaf5062879c59f1f60415d31abbbafa6212a7bae53c2384c2834d64b51e630c42e4db53f51be7ed66233d1dd63826c29d6135e1e74143c128e05c9754e5010001	\\xe55c15f8c661d40f382e8e0a7fd12522154e08b7719781af0518ded4d47f9647aa97a0aa15cecbd2de3e6c912f77a24360d7b8e5bbf2d4f98cb82c588e1c8005	1680424867000000	1681029667000000	1744101667000000	1838709667000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
311	\\xfa3ecf2462e0d68244a73242b181a3c00118fa8f124d2594e84eb74faaf54ad785d685d3378c6938cdfe4137020d9bb977f8beaa8ac7e9f709b59f4c7bc70cb0	1	0	\\x0000000100000000008000039e5bd403400d4230423d94ad734733f9ddb905f0391c302fee66097a6c3012b86f374482008a5e481f785420b50b3b8c50b6edabb79465aca633367479259898616466d437c233ae963cd311f321147b07a7df3a8869ef6a53ac2aaac5051acb07d59a5f2e3e75d2caac444bf05f653ac07d47cdfdce24e6f41659e403754895010001	\\x6e92ec096b0415620e0571647a841528b460a83107803151dcf65c89a72667a6294f5a098da0f4ee07831a948f472f47c3d4f2ec29b793f4bf8c736d7c20f601	1674379867000000	1674984667000000	1738056667000000	1832664667000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
312	\\xfab2b777375bc6b056cacdf6334d6c1e1f64cbca3c2412c2accaac891b006a3114427e1ac8260f893ce7ca4b7a8a3d4bfaa2810046a8e8ef772bf46053b47f28	1	0	\\x000000010000000000800003be67d2401aef87d57b5068126ec1dc09fb4dcf0ce5556a16936cb2392c54a441f25718d0bf9a65098d00e50e7488b2077d9606e2c38c0241dcbb0f5d23c95e960d5674e76817eb6f5888ff999925c251bd2651bb3e5af5585e4a70de5f2f450b17f5ccf3a7566b259f931b048c25ada0ec651e7973ebb373e8ea190e0760675d010001	\\xf1cb1a5cbee114bd11af941e8fa0b368bc542e610934db298edef11633b76d0b79a07e649ce7be0a32c940f5fed1882cf5277c9d6e9302f82e87c7be5b1af10f	1668334867000000	1668939667000000	1732011667000000	1826619667000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
313	\\xfce682c7af543584cd32f5b2a5f4f95e9b436af21a307dbdfbc7764a4b9ddaeaf49f29e0d3c50aeb0bbb441f8498f88b84cf162b9ee68928627637e51a682bf1	1	0	\\x000000010000000000800003bada471b2336af1602662ff7267b9690bad5ce2f120c6c86099350eb92c4ebe214cc187787f4e8e2b493635fbc1840694988133f332cad85cebedee3033be8f470a06cd202678bc75e061e1bad835be97a4157f12c5306b317c426dc243f2689f783ee582f9ca76e0391b94cf7c9d1480a6ba8ed0789b00837248ed8a1ffa78d010001	\\xe623da217de0165d4fb77f684229098575414993cd5adf40bd53f87b94b5cb0dc0a28f3df0ffb22c643435044d9b030ecab8929fd4908c6a82761bbd7a8d8509	1664103367000000	1664708167000000	1727780167000000	1822388167000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
314	\\xfd26d64778b0e28f0eb0b589c47cb10e2a35d05916b4ddf716cc5ae1896a660ca9fbcbd108b19f6677c8b757544d74dd49fa5fdd714c4bb53cc9978abf3c9e7f	1	0	\\x000000010000000000800003a63ac2dc7db873eb837e575a384408c06c831e7162cc1e8cdbf3cba7207785eeef6cbf1fbc9c38f52c63a2eb60e19cfaefb35cf1d18a17e63e24ec83ddccb411f477a0d2cde36f5b7ee734ac474fef0ce6af408164b7296504c7094aaf2436095323c362881a87d66dda35ee96c3a300e2d4400d93b0a8aabfd479e28376cef3010001	\\xfe6b74f118c872d240679da17b62af3625c0943971109d0d3758105535102d6ac8c78dbcb96be72ae880cdccb7366263cd4184789cc8cd5e61e1922e10f2c90d	1674984367000000	1675589167000000	1738661167000000	1833269167000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
315	\\x02434d7a879771f2abf8414418cb7d0db25e3c7a835922833e13bcf580e6975ded291811e4c137936000321fe189c59350cb9dc04c1d7b4195e54cc58a82dd2d	1	0	\\x0000000100000000008000039b4ba3007cc4a47d8c1a0071c288546c37f2e379f0f7934f5fb30164f677afafc8990eb079323568a85864feb53b5180758c8c43baa2206fdc11a7c8a5c1f766fde3d7a19a655edfa665c45fd34224edcf08d72ebf43f1d1ec46ba43ea0a3f6cef9c352129bdedb8be5123f41820acb10a4fee5ca7521a130804b588b47aa91b010001	\\x2292d1ec764503168313b47aee293d8c872cbcb4654256090782cefd78781b44b52f59b24c8a572ea28a9498209b997eb69b92365abe1a309df51348c5f7e306	1665916867000000	1666521667000000	1729593667000000	1824201667000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
316	\\x0567e4466ccfb095c271e91134fbfd515dc68f5bdb6fe2ad54af11333ac0171ec6a8e931a4aef735204967c605cf37bd338b59e8ac88d79186c16a13f31f0782	1	0	\\x000000010000000000800003ae6c1610c48b2e6ebc65d0c386c4c75f2486a3f8ae2d5f3c95ebc647212e1174a68ed45966c96b598f2805f626366ce720f2089db3617c18c3809ff9078fb7f20e4daf9574c1bd144f89db8ab9586d941874e6408cbf7f30935b784cbbeb6d749b286207d04ff794f55d302e6befb02773c55eaecbc78ab6e28d7acadeb8202d010001	\\x944c3481d7eceb2a5323c4cac03f7b3054331af938478ef40bbb741457a1041c3798fc7132fd39206e909e81e7ce0973613862e175b1d4266fb59b12ed60d501	1658058367000000	1658663167000000	1721735167000000	1816343167000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
317	\\x1173cba970cc600382e2b776347d55e64f534d3ef7ffc8db091e485ff71ce00a39bb491f280fc715984fb67f21c8f4a27d54995d76753ca35a0954a2ff35bc2d	1	0	\\x000000010000000000800003bf90136fd9b8502c29ad96704dfeee1431f2bc77def17d5d0fefd6272514ffbaa7d057f11012a313a46348b7d12f62418775c469447b4c3ea3ceae644a0d15ef48e001d8e6dadf49af9de4b35b06ac3012b9b17a5e18db5e4f6c844215c929abbe628784b4b363fb5cc040408d13809b14c1ea1abde6e15475eddf6162bffc83010001	\\xb056c6f0749992fc6af130c1437105953fcfcdef260552304d4d710264a2b87bd4f38218c56c9cf7abc5b68ed4c71cf44d543c2d38c5fc6f6489e237feca6d0c	1671961867000000	1672566667000000	1735638667000000	1830246667000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
318	\\x1133efd83e3d2a721d63f7eb2e5de8d8b65a089caf09235aa7d8368eebb2f96816c4d7eff0f67528505516c434217fdbdf40ae7226b9762d65499cd617c1cd22	1	0	\\x000000010000000000800003c626ea7847c10ea15f216c8c1e38926e943677047f3fec28209d2f242c9603027e5431f0f1da6ce085a2e90365531a12c922e09ce6a418c60b5f7435e36d24162ac3d34180c23b79df1f010d647e5ff42d27e18749b944763c79e8efa454b9231d88dfb69ba6b0329eb80df6ce5240d0dddf3071285dc4dca5a122b2d8153b59010001	\\x21c55a34f12fc1a88cc5075de637fa1c271b4a088b5a51784509f934103070b05dcae7371bc584566f8ee057147de9e6b630188dcca670973f348c34ad721406	1656849367000000	1657454167000000	1720526167000000	1815134167000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
319	\\x14df098a2c0bc68ec52edcc927dfddd725dbef8b50375a158142dbbc29408bdda30dd49347a784a29f7ef3ddd9273e5d3204243d076ddda16e33558129ff254d	1	0	\\x000000010000000000800003b202879338c1ccd020d185d470ae77e218c5b9b42167e763f10fc16096d0f00a53b40cbd9dd337f16a6d9883e3b79255fe458d5ccc274c9bd026d0854c57b8f8ff955d138bfe21d2be68603c3f313b276819c0b214e52d5bba6dfc270613de5e0516771656db5532a3b0ea66d6e1aa897a9afe6470908bb4ca1da2fd9ae5fc81010001	\\x1f09dc3e076e69c444cb51eed0fb6c8dc978689c1b379d54a0e8e281f250e4226078759eb4013b5d5a35dddd2cc58ce4ec594d9e83b9a04f3c38be9c989ca90f	1661685367000000	1662290167000000	1725362167000000	1819970167000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
320	\\x18bfbf305bcc527639ceb26f6aeaa49ca5f380bf8d0bbcbfdca75e94b56974f784f1f5e96ffeb708857bdc6f703be46baffa3024213c8ad705e97981cff90f59	1	0	\\x000000010000000000800003b17aa45c703c4a34f5a5256ea33fdcf99996049ea6d103ce4039586c0a4c2076d9c65143e7d744c450adbd3c8100e03db2c0ac6e1ad44b6b951a9958d560288ee04fafa947ee177f8e7b09b22822024c473ff52585a13a9f1d3858edc57b78ddaf0841bbc015baad70f54c0b6060458b78f0ebdd2580818a0b3f026c53e2397f010001	\\x6e1a3a765f68c5c5d3dac4d5d8daed2e67e98ec371242841161c3aae58f9c90ada707a3de7e0f53187d0fe52613c0d73c4cedaa5359c8670424d2eb1442fe604	1671961867000000	1672566667000000	1735638667000000	1830246667000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
321	\\x1813cc0079e0266e991012ca6a697d463076e2995afa979f5eafb370876d86dd98304df165df29b942110304ea178a65b4f8bfe549f02f47d03962e22d3773c9	1	0	\\x000000010000000000800003db0b7a68d0c8edcee28dab6eb3fc5aff5bacdf6212cd421e04b634096863b346469016dc3d5071673ba4c83d685701337b118fe2d539c56e3d5706acabc29659fd27a0a6b831954c05a43e220a04142af4c60d3fdd1f4885df17d31c75d89f413dedfbc67f925c32cfff019fc9e28564c4ae42b3cce1d5dcfa7b73defd124bab010001	\\xe85b1b799b6f896c4dee444d2e8ce62e5e70a38aeaae39741d8d44a3fb47b7caae9781cb1982cbf345694c15a5df0f31e927093f0c0959bdcf9e549162b2450d	1665312367000000	1665917167000000	1728989167000000	1823597167000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
322	\\x1b9bf48722871bb49d382311bc578a32f8cca3983fe1775c95a3f77383b492678c3aeb1132cee60dca0892ce6c53fb9ee2280dc6495c6a0d7a701d03cc59cfe3	1	0	\\x000000010000000000800003b1b8ecfedb7fb49ad8fd5f93bff6697a10065053a071dcb5b82f48dbf808ba0a64f5be74eeb5f0fa0626bf2712497e642d212561e8ef2ade89988258a8497b436e85b2b6b72b2d0223cdd39fe803127bc0165acbcb6bcabd3d45046305b077e1f1c86802249e5ed7bde66dc99131756feb28f4b020d1d90e168a3b2ec742f271010001	\\xeb410ec659b80a61cfd77f12f9633922c4dc6b593961557e9b529195e29ff7d9d3dd25408bbd60e5b901067f75ee8749053b15bb4b978d08c4bf23a34046ff0f	1670148367000000	1670753167000000	1733825167000000	1828433167000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
323	\\x1f13f0fc8ca25b49f225dc19ba7f7769f047a5d07f2f981e011d07eba7272b83153d867c8a58f039e6e3c7079384d74716469d89d13b2b72b4d0853d045c2eba	1	0	\\x000000010000000000800003b551c66814ff640016d63a89b5566207eb049b5be130d0361efda7203749111efc43ba367f00582ceeec38affaa21b52e2d922d80083821835661af795c693e5c4a8c171849c12ccb66bf973be1fe9abb2212f8b6065c2c88a52c31c3a64c0264a18197efbd866f034ae6663b81004d7765d8ddb9e270a3804996e251829c875010001	\\x3123c53c1426e56d178eda8f5df53e49a4449b6f204e8bd6f4be782ebc2918464c9cc40328428aceac6507ed0dfb8e1bd2298efd3dca162febfa18a10dc99a05	1664103367000000	1664708167000000	1727780167000000	1822388167000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
324	\\x231b4a87dea1c57238a4bd284bda3b7c027fbc945133cc6f462f61f6b47b7eb760aa209f3489d414dcb3aa03c79041be1101742796f605ab55ff43a85b7d923c	1	0	\\x000000010000000000800003db18cbcdc4bc1be0317253cec4e199d356e90fef55d1ed29bfb2dc3c667029d59e5234101bb37603e6ea923c6271105f13850767b689c8997bf241f5836a2a768ec76e870eb3110f99cd1e76a6541432030ed467f8ce57b422c280b68474aa723fc075eab32ac379a125d216420a9585a69d5de6b797d91e21e62d015c189c4b010001	\\xdddf6f97f68987c1c5f1f67181196cbf5b4bb5eed21a551f74b5f2819a1aaff38314931448b764b4726c834c39c100d29b977c0be04503e3655666e354d88000	1687074367000000	1687679167000000	1750751167000000	1845359167000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
325	\\x24e7d6724b95941aae62989ecbb3d492e80137741d8232d2e208c0cbe817fea4aa1e88f12b25b3ca261be68dc694f42576e90c80746104ccb8c6b1a76960057a	1	0	\\x000000010000000000800003d3559b7d655f872e9ccfb7bb9834406a60f6ea771fe5999036f17a1454c850965b7cc3924035f7b8d4d6cb136b6487d8cbf9baab48b76da811f6999399022cf4af1fefb36bce745f0c285b7045fb065ef48fe710705c58d78927118d4314caba40a67f944751b32117223fcf6697814b47bfcf0de8217346a43e581cb072db9f010001	\\x689da9287ced84936cf65e320302e9d28854d6026fe1dcfe8b26f123134b07030201f2a82bb4c9b66561865c8aacf41f9d0f6587a55e30da9ae821050309600a	1666521367000000	1667126167000000	1730198167000000	1824806167000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
326	\\x26db02fb67a0e9033043a8541940c14ce64e98f85478fee788b3e58ca2d8ecd66867f8404bc657ce1a8430b1af3b9123233e1ab97e51bfe7a5c14947a37f3557	1	0	\\x000000010000000000800003bf7aca62ee190c72cd0b0802737e793a90294db66738869ab1992f2d63b1129037fd85574bf28f8fe3a130c69516797fd8f8a928cd02606ab3c0052ba521e887c606bc6251539f0c9374d192474f1f52d30f7143b5cf683d33018ac4baa671f01321059e94d2af7306c896d824e0b08887969b2a517c7ee632c13d2ecf60dd1b010001	\\x36bfda479cf03449b3ec223470e9778f7d503cd18bf70377c1c7d9169f0e4101841ed734d2f5ab6713e4d135992aaef2ef3dc6804c29513e9f3eb8e9bc682600	1671357367000000	1671962167000000	1735034167000000	1829642167000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
327	\\x265b54e34318bb32bfa0896dad1d89c1f5587b95fa45b07d2ca47c5a1c2a4c3a485c8ede476cdf95b3cbff98192709d52fa59897e36f10a49c918c66ae0c942f	1	0	\\x000000010000000000800003b61b0435e89a49d17d331845eb9c5dd0af2c962e7c6d32f8f79ff7654f63f2b7e67aa486942e15236acfcc023de309ab50dd11f38ce449c94988f434ff0a8a117ef921927a056caabbb194951b71c800b8a6e0a6820f47548e4f87a8d75273e379849a75196f9d08bcd831c30393c18e32e5ce720c8c710dbdcd7afe508ee497010001	\\x4892f8247edbea9a06fc636fe9483e9224c2bb4f77bf8942cc2d4d6cc91fc452ee4f688cd6109855666b74e43260c26aa66b22970a9b0de373e34cb8d63b7a09	1684051867000000	1684656667000000	1747728667000000	1842336667000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
328	\\x27079f291a72e01a007db9e9e003194ba90fc26de5cafc4fb79dc246394fd568ef3428d72123c87c20d7e63e4b88a0868aa52c6f3e3c89956134dd05db14c822	1	0	\\x000000010000000000800003d0a6ade645d38367428d0f191afca279761cecbcafc201c48f2e9350e787f99c620cbfa2bc7a5e8d0f97af5656e5f8bfe5d25fbf3460230cd79643978c04ddcd847576a38dce47349edf0fe4badf86b6206eeeef1526b0a374c7cc390088854fc191a5e005927db9c245a1da06d84063c599873a26006e0bebab3f2298b51f8f010001	\\x8a86dfb92f1e64c24df7cae2b8e17753d44ce820a2396efbafb482c1790dede341d0a4c3b6eb54c91d41ff110e8b5c5d9568d4a3ce4e54e4cb053a7e03b2dd00	1663498867000000	1664103667000000	1727175667000000	1821783667000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
329	\\x2adfd7d912de2f7a906ef9693f94ab9b56000a6ed878aacc5eb681b53196dd67d9da0cc8713c937c29ad7902832d79e1be318e809754f0efe0c36456e4f42149	1	0	\\x000000010000000000800003bdec12c93fb68448e2766527d697308a9f681205d1bb4cd5eeb205627efff03a9c078a1e27d5cf89326db4dae1c091adfbb41383d72c0be3f06690e34c7846c8f31fcc2ff538c5f7e783dba12f01f285c3ca50fa3377a04384f98b75b56e285953d57495b4af4cb1189396daf26402504daf8be56415d91adec3a8f7179df997010001	\\x80a0e131949e36970235d0be18d1f17464bed95cd41087a0971c8b2921e5f07ac99e18616a991b113331ceb6512ac40eb9e8a294eb30eb9feaeeab459abeba06	1683447367000000	1684052167000000	1747124167000000	1841732167000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
330	\\x2c27e9edbeb49ff855481d970484e4ef97423029ddc1213a2ceb576a6742da85ea0530550ae6e036f1b6c2528e6b05107bcfaf1ff8414d83e4b19505089f6cd5	1	0	\\x000000010000000000800003a81bdc62becb1bf38185b40364f294910bfa9aa14f6f6e7d997b9f24931242bce6b81dc85c266bb107207df1b2f4bb6d63f7a739c41088854188342759d8ed13a192ab14da0d77ad3957bcd11823a07148920576d6c63006f22700ce2334195124beac47f33ca6c4c84d33e3c283c30ce63e8915f82867d468ebf138c275f1a9010001	\\xf2901c4dd64caf4ae156846d8ccb0c38dfa152d28ecea33080d7b3f7263fcf727160c1683088a0ef0c5be5f20eeeeb9daa114eea2d13a806b32d5e68daefd400	1665916867000000	1666521667000000	1729593667000000	1824201667000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
331	\\x30eb8bb3ce0884c33a4b5c5e38e5f89216e9061169eae63aa12b90fbbd5da9b40c5b61b8400088258ffaab2693bfdf07fbadfd9b62e97c8f4ac06ddafad656d0	1	0	\\x000000010000000000800003d9663e3f38c31f9a3b623ec1a37dce46aec9f2ad600735abb28e12cb17133971c9600f50ced6e631dc4b9f0b6f0ff4acbb71c875c7a9fa7ca556e2726b431754bbacbc69561168f31ef535d0ada83bcf924a5c4a322c771b86d1345432a0ad50a520888b6273e4fecd645f93da43f7a957d706acbd0d9cf410e32f5f02e02739010001	\\x4c71c421f8792ee71d38e1ba1e268078399f7a99f6fdda7ae92f92c7f65faea45d945a29d87f65fdcea35eb5e1c03fa64f60bd99d49b71a7733a977e4f1e1006	1684051867000000	1684656667000000	1747728667000000	1842336667000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
332	\\x306ba17396e532304406b4475b68f55622f64d548d7dc3c1c6cf00e89457325d21624b17c082d59de4a76d32a6fec6e714d4d285a050f335790c8d7574aa2a73	1	0	\\x000000010000000000800003b8ff6da347f4c40896cc3c33bb066e745a296535cb423a7dcb00c377057d94f1169f5a9487f01a192783e83c6a6fadd0ffd3213cf95f94ec0f39ea4fd55e1597ceeba85fe779fd2d757525fb354acdcde8a04cd00019d1df5d4a15baf67105267bfcdf5b0075425a545fc32213e72d1da7634ddf8dca72be66ffa1dea6b4cc0f010001	\\x2be01cc8f8fece97d65b01125d76fc6694706d86bf58dd7c00ee4c65773e8e59b93e98c34be0dc3e3d4409c75c37f33d853acbcf9f9517b6c3e5a7189c36030d	1659267367000000	1659872167000000	1722944167000000	1817552167000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
333	\\x32a79ddfe1a2638137c211d6e20d5f69c89af26d0d857a401290a570c93775e78205d00d6384189c81f4a40cc1936710e23c0520517fbdf92ceefa8b7c75bacd	1	0	\\x000000010000000000800003b2bb631f5a2957e20a510bcef012b336e2729f32d596a97a30efcf2ce047e003a23df04c97cec819102b4fcfd929d67d7274c9816ef148b7da848abdd173ca9d76ab8454c72b79bc57f7784f1f31e6be425e5fe0a66373a814fbaacb636cdc7a8edbd01f6306e20aa1d61857f7969a0b405433718a66bb5c3a6de4d93843cf05010001	\\x5b0ab72bbba34691346e36c4fceb8d8baf740a0fb151b415ec98bd994aa3d2df266c5fe1d1dae73ab2be3aa2fe05e3c672e585e9321678efa9b7c37467147f0e	1672566367000000	1673171167000000	1736243167000000	1830851167000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
334	\\x35d74de26cc9dc3f8e9bc07d678bb40c07e43aac12e21566088f0ee62168ec122ded3517175691c5d48a101d41ab0878a494fafc07b24ed5633d54d4e429e963	1	0	\\x000000010000000000800003c61c240c2f5fd334de6c9e6924840e150764719fccfbc611179ce2932079ed70c1b77c04b54bac7c7f8acfaa2670474c371e28849a18906678c025653796537a334c67fcc7b282724b13fd2404d4ace9d9555890cc530ad0e7764339739a97ee717a6b7c974198e5001a0737f2cb7b87fd9262a29e8ea23705ccea7aec48dc43010001	\\x6034197855aa6212cb3bdf55590da82833471a1eab01a01ad6c542187bd58f6a54efd78a39c0c2591fca61c12b812eea4e472af2bbda880445c0d06ecbc2790e	1661685367000000	1662290167000000	1725362167000000	1819970167000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
335	\\x36bbd20c0e3936e762f2c7e89adff5c95bf74e6766bd7997e5620ef590cb87b0413ce538cd5d1c64cafdbda8d9192b20e14af02f4a009cbe0251b53b25107124	1	0	\\x000000010000000000800003ac84180bac37492baf28f3cbe4d98c63a5f7e73d85bd57061800bfbdbc80edf32a691098869bf663871690a2f09247a01bf994861c2e7f7b8e962be67a59cbd9e9c48372a26e25f05d17cb5b782fd56af9425162c658bed33fe20753f9a13826fb900f74e32fb75fb466c1c1f0325c474e1fb6cf601b64eabd6e1527008f3ad3010001	\\xcd81b335b27dce35ebba5a30a1ddea6e898ad13d3d31a101225fa368528d3b58c68ad5bdef00cb6014bf7302a3a5af69c2fc4e52c0bb842fccfee5676e3b0d03	1664707867000000	1665312667000000	1728384667000000	1822992667000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
336	\\x36831a8884682db9f580be67709a3099a30222474f0d9418ee77d2b841ef29298b0250a6559142a5c01fcb2d81fa343f1282d4e8353959a894aabb434395f5d8	1	0	\\x000000010000000000800003aa749f43185a8fd7b6c74856768828834c32ad6133018a82f01e5743eee4fb4673a405dacc08363b62ea204c38347bf50088da8692a61807bf2e99592a61aa99ee00b0834c2d39d42a8b3f8e9751dc15f34709acf634f50f0571dee1efba951feb1e80be02390752094e2f763d14b276b9d22c92b3dd8535ca2ab8761eb6a853010001	\\x716e6bc561b72add58563e112a8f3852c4fb96d754ec5c98437df0c01d13e174622bf929babd8d1343197d3640e4e930c0ba48302c7684134ca3e66776759b0a	1671357367000000	1671962167000000	1735034167000000	1829642167000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
337	\\x3863f645bc9fde3f9f9271fa535eb30352f67e700f0e22d7a4d551d3ba189ca48d20558dccb90d89edb2a0157f02a00b447d4da84e279189c21ef73de6a64c1d	1	0	\\x000000010000000000800003b82c57ea9fb0c21d9aeb95a772d8849c0be6ab62adcfb9079ff01d8143b8ef6e25eb66e0df4c436d3480088a968603a37779ff37a4745d48ba54212151267803a242515a5599b535ff4ea95003562ba127109f34983ff9283c409378fd8bd2814c58f4903fc71e4180c2542e0d1a4ca8c368e2d87d918986fc919ee5382e9277010001	\\x94fb53336275cf66257a909d572f472822680a716fdbf0f1e2d0373b01d1adfcf82ff4ecc8fbc38dc0810efecef97cffc9f3acf3276dd494358ef62924366701	1677402367000000	1678007167000000	1741079167000000	1835687167000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
338	\\x380b50fe22f2c6529273055d6bb2f36557c535694f0953179835eb912b316a43d27af36b7e0424c38b917ac68ab627fc85c6836517f5f4c2fca996f9eb361703	1	0	\\x000000010000000000800003b8239d5355e96eddd42a7769d515374914445071958340eb54f6e32286a8e92f4dc724dcf3b61372e59f35e79aae977406e50a6025e8c5205ef3be6d70a5ef164df0094a8d366b643ebc40534972c6df313596ad7730eb33669ff390303400c4000b4386dcd0fe7199eb15deeb1be1ebf272c62a7f5ffdc3202ef5c797cc2371010001	\\xd2291c8510f3d3184a5bb2694db475b714f417cec898837fbe850411d0eca0486a19673b014c21a202237bd97f94ee697b54a1b049a6a76be7419d984229aa00	1667730367000000	1668335167000000	1731407167000000	1826015167000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
339	\\x3963c54ddbfe57cf89869b7f0f19f7ccebb45d764428cf1b0f9fbf75fd5cc071252c9d30eabe663b6ad8048ca0666672608d5201712e3342a8def67e4f441591	1	0	\\x000000010000000000800003beddc4ed29bc3cdbc85d0ba6f69b964d2e7e2fcd5cfc6d9ad89a5dd8f3024f290b04185c5b81ad32d8509bc05266376c6ec51a7114096a7f8043a60cfe853f2086f9eacb3e29276b8721304b06f89362bd0f80101ce428fd316670b0deafcbfb535647efe5a423bc87b255573a4a4e459215e4905dff9c752bc3681d3e288f97010001	\\x6510366378ae9c3be1380c95b5347a8e2b0ae8fa8da887e5082578652193a5ed418a516c3315537a9b58f362a60fde266f54e6ef9b784b150ad81d8f464b210a	1675588867000000	1676193667000000	1739265667000000	1833873667000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
340	\\x3b7304a323f38fcfe13f8c79f4ff80cfe4900acb6e109742d3a8cb120def75eff56b2b63de6f15a672b1dc3bd93fc6462d93a3cb28a871a87a50408e8095400a	1	0	\\x000000010000000000800003c0563721c3a4ed488f3e4c3704828e2651093878dcdc7dd940094680787b0c8ab74a7e27fdc0904f40d3a401e3ba86dc0f2a32662e6cdca02fa2937c1e2eb85c44ac16a3df4040488cffe860229d93445f1f372181cdeafaa6d52081d622ed06e8aa19372d8d5faff4d35931838db9d01f7b5165fc315dd0ac5ab1891ec9c92f010001	\\xe7a2b5742feff8b3983071ce522afc7efa581c2f2a347843902dcd6c8b6f6df149609d73977df87996faeec531b3da3938a0bed112e7b7528397083666f43e01	1685260867000000	1685865667000000	1748937667000000	1843545667000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
341	\\x3ee763930ee9c8b43c5b0cd800a2922576d3fc5fd7b229567b76b007f9e0a3c3e06bbe48285798a557c92d37d7b4461f17513b88b7c865aa46cd3812ed8a4100	1	0	\\x000000010000000000800003be2b9a5dcb72693d118b3f268b6b374911f58c612e7850d8579ac65f5f31abb2e634a00ec942ac572bd647b2656cd1361f57e271209a5994706fbb04f3318495c0c2ba7945a17b0f308e35e27102ca08df238d6b88b9bb37bb74e98a3eace5fa2e8e436f07d7f8e2f832d1409584de26635d43697ce4a5ec97985b764705b747010001	\\xce7bc4139a31ca894a45a870d0a151decaa93d67ddba63eafbff69891b681796b1f3b7c2b9c5017e0f36c455f1172bf9129f56bb528c8a9991c9858937c10f01	1661080867000000	1661685667000000	1724757667000000	1819365667000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
342	\\x418bce2ce7d199648982547f88c70a07b9da00eef11f857ffdfcc94612f639d7ff004fdb6c7c424a61f415cd54e46375b80c79a2a8d6c1538ce138be619a4f47	1	0	\\x000000010000000000800003e4cd3f84ec3ddd28a15233c017c7982a4be64e475f102e6bfd2a992d5bd514ec85b38ba62d998fce72a67678cc1ed8c5d435c55707ffd99920a9c985f3f5f8ceb1463aec7f007241f1f9a51a7da0b69e1d78e2d0645e329db6412378b733992ad62b15fdf0996f23b1909bc81080cf00d7854f63c76ca842668edeac3a9b10bb010001	\\x396a0f28384b60902dc1be5f820f14b3db29fd44ba59ac311e4a1a9eaf150efdeec7a6e77b5fe84db363e03e9a713a65475397fed37a0b95e241b09badc80c01	1680424867000000	1681029667000000	1744101667000000	1838709667000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
343	\\x43eb42e53f0b0e7ea05ad5786ee86b14c8b962e94b5fd4747fb1433930eef03ff7f48dcc5185e72919fa5d1a6d22c446803b5f51e2abbe55008b1c98442978ba	1	0	\\x000000010000000000800003ac3be42ea0f3df72cce7357b8c7ce4a4bedbdd8e72a633b6d7316148aff226512e7e04b72f453f146066e0a2d8debbc0c40d00be8bc546d80e627043429f130cca6cd1e800bbe34d16696d33069809a45530ddfa90815673532a6fadc370d90064a6da0d9b361fa29721712b984a614c32c7f78659f7f4df5c7be8581ec6005d010001	\\xf67513d91c1c845b76aa171088f6bd527aa031c42d52f8de520c7c8be9a937c9683144184ef77c17a1f356747648bffeb916ccb87590bfb822df9f501060760b	1672566367000000	1673171167000000	1736243167000000	1830851167000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
344	\\x486f129e828ff84339f63ca554ad0445194535900faa4729a6a439a3e1066ae36e701a944eaedf58cc8e2d4019262de72e4c0dd85e3460899e0bae4c5064f473	1	0	\\x000000010000000000800003e1c49e234389c689f6c0bcbdd97d4c95c4d7537617f4b1f857cf042a0c44cde25900b862bc526c904ec1bfc82537ee60eadc5f1dfa6b695496f1ba4d229d115ee91b55ed3c13f9a003a64d6b4bb2fcec2a3314aa3bc9abe399f1d732d2b71217e484236355be67628d62229d4af3bb91f50fe39c879ca35d046b02f07624e909010001	\\x66696ae80c9eff4254830f64b7f4430201a922705428d9beac417dd38c22bea5746aa0f99710d4d804a3f0eacaf3e446b91182fba22758bbf0ab1888c89c000a	1669543867000000	1670148667000000	1733220667000000	1827828667000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
345	\\x49bfdde405ff26c27caabd9b6c020a6120470e42c1281757f898772596f210e8239af5bf0a214a3ca8769bd25dd7841b9ef0e208c2476512f815361c2a6e43fc	1	0	\\x000000010000000000800003ac6e675ba46be3ae460a2e2ff9475cd04e178bcdd8aea6cbe14fa5daf5f4947b2f9f924bdf59ec1bfb12c3524d776b38b6275710b68e96c99cf6a9fa4abb18815285004e38ac941a87dd41f9ca5300e6cc20e48cbb8e509cb440185ebba19ae5bcb19e2ce309e82201288d3c3a5e5d9578fd72b65064e883ac846191a93e71a1010001	\\xb419d3828a30961c87dafef97dc23afe35aa97560357b09e5f6eae63c56c013548fffddf3ef04dddb756303365ce4d39f6a5d903501705b70e98a48aff8b7006	1665916867000000	1666521667000000	1729593667000000	1824201667000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
346	\\x4c6f300e174d9e3483d669e2a357c5f5e6346c819fa6bcf28c43934a2ed7ff9e5692b8e57e0c2d3f17aed19f5ae28a6f9e5dc934d4184c99bdeca298e9eb4436	1	0	\\x000000010000000000800003f4cb61be65927e72ab452a3dd70779b36275c24b603c6c04e20bd8fd2219642feea7e96fa51d788d57121c17bad947e9c98150071980c8bdc0d62c234c8f12ec495a22ab6a220f2130befbf98d628055d526b3632ec9564673d381c45e7cba0ad49929448d2788086ff4fbe3942789f526a68fc60b484ce76892e2f3632c2227010001	\\x6524715a9316cb15d8a44e5f75c36f41bab89f0b6575f80545224c572bd54b28defa77f3e5d46d3c891d702188fcfec6afc7c8f980dbfd8b830acc5121b12b01	1656244867000000	1656849667000000	1719921667000000	1814529667000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
347	\\x4dbf9c92686fed2054248d9d46e93be1e8ad55b5291806a7e1fc314239e6dd0765c9fc39b703d67b136b20a0138782ddaf6909e19bf4e5623630171c0837d846	1	0	\\x000000010000000000800003b4764dcd5a9ef0d8763bb1384a8e806bd6fb28c2593392093eac51d8ade792f0ecfebc7422c5a993047f8cf51288c27fc39d551b0ef8bbbfaed7f3021b8d3b9372ba89bebb4cb3405df24fe4c74e8b4e2381e93458abd8e54a792dfb41f911db9d53e5f5029623e0c3f95a9858991398b815cc9a99c1d8b84d83c4112829642d010001	\\x729853c3ab37953bacdd222d6ad19a47c935a100209c9008e51cea20a212f6309255c520cd46c17abed9a0391f3b3345db8dae6122cd1f9aca3a2c7fa4ef0309	1667125867000000	1667730667000000	1730802667000000	1825410667000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
348	\\x4f77e6a2da211a8fac4b83be699bf7a5aa811f9ff0c3640c717ee5f8455abe97a8542f0c9329b6403d1751d0f5aea90021d273ed7ce98d142974ec5536437826	1	0	\\x000000010000000000800003c4b01698c348b35540ad1f743c3b9761b1697c062a81e02ebcb6a70709324a432573fc8e4a5d19c1f910e0760e2434d306882ec0335e97dcda3f1052f5ec43adbd2ff5cae1bb0de6fa9f9a5d43808546598d224903c1b855b1a8b82fe10e7d8627b394bbbba8de80fdf11c43f94b963fca0654ad9ed5309dd2fac1935101c291010001	\\x6ed6dacf52a36f48c352dcd41bed17d19a368e3aa8f4fb29581837fd9365f49a8dbd6b8d06e74c0685b6d6daa90e61fb7a498ba6b7d1590b15874fb5ce503c0e	1659871867000000	1660476667000000	1723548667000000	1818156667000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
349	\\x51e380bd43909efc49f521940d62d0a73355f1b046fbee44f91724ee9428bc741432641483767863ba2f9e6f8add46596291de3d9150eaec2c242c65f064438e	1	0	\\x000000010000000000800003c7e75fd79051de9ace014f45fa0302c487c63a35c2233870af522ad218cc52111f59fb60b63c29bfade7876882a567dfac74591e5df1cc6442a64c161610e0657d2a856bcfaa85db10c839d73885b77119612b996559dcf3aed2c6315c7af81b334d4968c8c421d9b635ad76afa1a5faf995611aa237aa8d5a55a5d21ede911f010001	\\x2b090efb5749d69f59ace51dc947de8ab6afc8c72714d9522c9837c2216503e60f1c54488725a3c5a3ec6ca7458d509ca9448c9b6c2b1db62fe55b9d265f760e	1684656367000000	1685261167000000	1748333167000000	1842941167000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
350	\\x51d7bd38dfdb252ee86306da2bfb189c35b75a3ee7bfa892460d64abbe50e35dbb9073fff41464ad8bcd72a4188a7d0522c2ab162a277bead88854f259f3e945	1	0	\\x0000000100000000008000039ada1a14f448f82c49b31c796e8a8ba769d3e4a9603739e0067a0a945c81e44786d388f4fcd0365391f99c8c5e3da8828f2f423c189b6dc2c6b3bdf0a55aee4332195d4e4b97c3c6b920907597b0ce5f7642874e92a33f1e9f6e627efa88b57235b2373a2168389835099c9e8f62f4ab4c5874987e3ee94feaa5f1a841e593eb010001	\\x647eba0e0ce6183d33c717a0bc661290c49f58fbb9c97f4b3452400df4ef32d4a3c6930aff0ffa5aab5aeb2ec725bcf1ebf334beaeab92ddaeb5cd7a0c0ae90b	1664707867000000	1665312667000000	1728384667000000	1822992667000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
351	\\x542f4df8728c336f9d2396aad50d16a0a0e76d215a308128d65027d514af0102e75e8ff3bf4dabedcb327b6d1bbda02e33f1fddd7bcaaa39d359e891333ae04b	1	0	\\x000000010000000000800003db23b153eeb679fba5687607bfd17a45cfda0e9f27cbb4f8cb77af94b8bd78f5c251b418163172a1ffb6db8cdad884ae3b6ee719361f81333d73a5a06e3623c96cb74c7bd2f16a21a1ea6206314a198e9515cf64ba4999eab77423fc0f89b4bb43d7d4db2014a60acc18642b0b4f0c47bc0d5c85ecb48ba94af70fa108c5ac71010001	\\x1986595841b9bb0a32075201acdadc37ac6847d713208abd7416d5d4c6d6c247bfb0ef807e3e104452a102166952ecc206062eb3e7eabcc70ffb861242b58b02	1673170867000000	1673775667000000	1736847667000000	1831455667000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
352	\\x572ba76911a46a77476cddc48ed4bfded43fe36f8e87dcb23febfeab78d8ac76497579b9671a9b0578ac5c7d54b980a8838514a0ed08a7cc5f4a26bf94fb644e	1	0	\\x000000010000000000800003e08c5b1d26776c44b1afe7dcc92d8f0679537dbcf342a2f6b6ff8789bdd1f914d076a87f7dc66367de90e37cbc4fde28609c1ac6292767b50369c8eb70a99146fec492e724373834c797e7a5b75f49321ccfd5ece5e465b492f92ce338817f20d17137820eedbbaf37d12e9b08e62ca331c3201929efada004fc4da64c9ae555010001	\\x1ebb3ff29f944f0093c4c500033eebe933f1e04df114ec36d605dc7dc9f034880feaeb1ae036d905b5df0f60339959d48119fa248767f9748c50278061b82303	1675588867000000	1676193667000000	1739265667000000	1833873667000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
353	\\x5ac7dd76faa7e75cf0c357cd354a173f70549dffc066e46a4e7a7e7637268167c88021982c3e16e821cbaf6e93d1c3487d5d44a83f925e16ad40060b4df021de	1	0	\\x000000010000000000800003e13de8b61337e76b36f469ec74d2e07a84dbb271346fc317a3d5d6467c84fbc5b78737f4cc9b9ad94a770d72d66054938033197a206d5b851822216da3749c67a5b4224135ea0735213ceb464bb0516ace20211ad0133c41aeaaff2495869c88b9d5a11175c41e6cd7944ce4420ff4b1719abacee7ee4d39e05a52e032f4b7f5010001	\\xfff23a0096151efd1d6c04fb14f574e0502973e04f4ecb882f159deedb32c5ab790e76bcb0863880681c7d405714833492a413d78e6a1626ce9adccf0c5fc20e	1678006867000000	1678611667000000	1741683667000000	1836291667000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
354	\\x5fd7f262cc291f91703c99d6661762bec7fe030505fbfab96103c50285ffb454ad8b00c59e7907ab4ff34c188182b4a2b4e86ce1bf54d0a180bfe84619258eba	1	0	\\x00000001000000000080000398558f97491df6a6200697421fb17e6444c6f66f982c6f8eeb5bba221e8a88f289816fbe2c2cf712189f67d286f0e85d99e44eac8f1e16a94026a1ea53e1ca3dd5c759137f7e9f818c6c04f3e8ec1b4e8bad79b04c678ae441c45f59b267b580a9941ca24a5f7809eac9b5eec38ad2c0dc0084fc4d6f9d21ca3e8de8ded06469010001	\\xd51bbe2d6f75a1aee9ea35dbf051036b54c73fa67199f17470081ae5af392afa88ca862dfd7606371766b95999f21e58ca1faeac3a68874c8c0814959ecd6c0a	1664707867000000	1665312667000000	1728384667000000	1822992667000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
355	\\x6043ec1fcdad91c3bdfd93c29a1135060dd6e980734ecea8ef4c6b215d830b95ab04722a2aecec3a1bdd3f0b5bc9046a34c80df30187a3c679d98373366cba7e	1	0	\\x000000010000000000800003d26af7460147e35a8831f5951351f2b87807a0f452c6ae34d3bde8f59c9cb60a87d7016da9d73d8bae66c9f25df05d480b70ed6f95a0b57f40714916246ebda943a2bade8b17eb9998dac35cfa682f6c1c50021a18ac52f02eeb8d60f68942577f0e70e4ce31d2181ec524dc1a71f38678d9af53c89a32a161b65dbfd5c35db7010001	\\xaa4b77ee2ffed2e21d7a7d0e9de1e8f8b4ececf88441608a3788cbe55888a9015abeb99d3660c149f6f47ffc7d66b8fc8b718561c4f4e7cf7b719cb124f9830f	1676797867000000	1677402667000000	1740474667000000	1835082667000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
356	\\x63273fbac71a02bd498c6280d3f82f84ad3ce15d6224338946da117c8e3b1d187a4201f464d3b24c1865076eae48ebf1236109c3d486a1639dfb91ae1a6035ac	1	0	\\x000000010000000000800003afab87c89adaf24aac73ede6b5ce4a1ad501c7c6bb31ef1f4c86a4826247b8c89f872a851a76acd0afda0b6e0bb13a9d1e338ba95223e7f36a407eee4ceb32a0f9faa02e6234896be4a9764f0c0f46b915df725c2d8074d625e848d1dcc5f5ba422dba73f8171879f9170b9937fef93a6ae8dfab0ad12e3b3f6a3a8744236859010001	\\x8b64d0571b232c4de371150fbc6e7b5e8ab1f911cc121d0c8e29712eaa82b1b964b02982e5218c480bf76324ce0e851b2bf95264d0f8a5b70214bd8415e2e308	1671357367000000	1671962167000000	1735034167000000	1829642167000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
357	\\x644f52fafdf23216a5bf31ff7cd3a8e829ef5a4c3276a3e5b8065fb078487868ff715ed510f4698af116def4e5331a59a0ca48e1aa957f835decec590b41c8dd	1	0	\\x000000010000000000800003acd67b1b92bbe82f5bf007eac59c72f06aab07aeab404161e0ba77309e12b48d664968ed97f922bc65905952dd994545d3f84e997e37af4844e494c32c61788f24e4bf9331e0e6d012cba0c446d9e6657c6980ae1f4eb8c2c8e6f511271424b837c2053a552920eb89477c232d8edd6187ae347e5b57d8c96caf289e5804df5d010001	\\xe95b8613f43518ad73306af9e983ba924bc6fe01ae70fd4444c8bd3700ac60ce51c132e40b7fc964fcec820a35ffffbc5f048821a239737419c60c1975dea703	1676193367000000	1676798167000000	1739870167000000	1834478167000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
358	\\x6593ca0d849a73172492fa467b4e8e0276f4b3e69f4e4447fcc603ee02f90704dc8f8014ba6be1bd689013eac24c0de102c872b83b7695ba26e4bbfe642cd9a5	1	0	\\x000000010000000000800003e1707d6613a76c64a19701bedca491a0fa1e6720ba552cc36508fbc81976f41258fd7c23d587b284d5dee44400212e7450bd7d1d2207999557adea4229ec40f19bd4f2e515f73b941297a8589fdb64872634a90f5e23d053dc86487d691b14638a9688a32c12d549c8e65762a71371fe857d8b7f27772283923b0946836a79d3010001	\\x7cdbffb31f4672d3cdf18438dbd758b3b6036186678279031325ac1530f4082fa4e2693900bcc513c288ad2c5bd6af372729dc8bead189502b587f8188d2090e	1659871867000000	1660476667000000	1723548667000000	1818156667000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
359	\\x66bb5d1fc483ff3e92dbaf772a937ec2ce22b0c476e20597a1242b3ee116ea22ebef63732dc700058dd6d62fb311e7627d18e5863d144bc40cbffb316cec313d	1	0	\\x000000010000000000800003e00045e3a1532dd951128d0a8056de7b283d8363eadeb3de127da894ae21dcc5e42651e9505a4f5bd1ab06fd2af7dd44999c986be6a6d244b81b432364181018a5e2e9b99fe98ed1f34ac607bc1a203579323578ddcaca097834295346bcc63562aedc7317776d17a0337ea5264bebaecaeb4a2b4e6bbfeb06c3e5ac91df4d5d010001	\\xd8104c9f3522f6f27ba4a4e28ca26eaeffd86b31e95e9cf6613f69b723dab6b960a688271ab16f041d5bc7f317b3efb8dfe2035dc96279d5802dc32b3ec22c06	1660476367000000	1661081167000000	1724153167000000	1818761167000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
360	\\x6733119bd404ac21df863a68a10e61b02e1c75c892a7092eefcebb35b7a91517f1e4b813d3569d1a9cfbd0bbc9d38033a453ae9801790fbe897dd6fd074975ab	1	0	\\x000000010000000000800003c1a74bf8083be2d5cfabf805515824197d7e729ba5ee0a6d940685a2b1794456a59b69d3f71085506ea326a326a9d49a192947868c4c0ee6f24e05f347ccfb0a9b6cd843f36cf3b8ad913ba58fd443b895793310a1b920dc9216df887b9385cd1cf1b6df8bf709ac666f663b90713fbef169724257807e0670e7c01212410e81010001	\\xdb5572e33dcedfe1f2722c117e7def7718a3009f8b5964f931d55a87eb38715d0127a53c9a6d73a479c7c2a3570305ba0efe40dcba6775df828be6544b34e20d	1678611367000000	1679216167000000	1742288167000000	1836896167000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
361	\\x68b7a8b4898eca178ebe5eb40a2b9ddcddc64539c2e69c3f44c3fdf15a3c1f221774703572f7f6c691fdc9bd336cd9d1a555f8149c1fd6cf217fc8bb61e798e0	1	0	\\x000000010000000000800003ce241f04c0ef401091abcae5333c0264229c68fe4147eed0b2b47e1e622a1dadfa4801d88035044e83e3a4d0be3de5582efd78bf43d4b02c01966a1a6934ebf94488e6ec11fb8fcea398a5c00826e27f294126a4da74c13f11e6044e785b10c00aaa8711627edf0466cceb2bc3f806328e6a42efaefb922a736810802c6fb2c3010001	\\xb7d52ab202e9933dcfe10d5ffef1d7ecd026823a5d1573d8f59ec6ad4bb5e6f3ba4be8442e52f9318673a3d5800b8e9089b2ea44ade2c5a1cf50c050b5ef4007	1668334867000000	1668939667000000	1732011667000000	1826619667000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
362	\\x6a67a076dae0efa79bfa6dcc4ced2e09e8efc50a291516541776b4c9f35d068ba1a33e66938d699a6ed9e14f36db93feb1794a60a0a1a7ce538670b469e635cb	1	0	\\x000000010000000000800003bcd5227fe025c53e69326fa66e5e4f0bd603e48366b393159d13a399e0a9457a7f109effd4b21fd6a5c9b0d0d4bf5617af1a19a8e4bc3edbc76379cf160d16015830d17e4b6de4ecd1220ad261646072957280874391c74db941f8f1f205ef6263120398b2e0f68aa5d3c79fc720867d2a70ad66c99c0650e0d6cfbfb78478a9010001	\\x430be3687cea18659591c2aeab90e9fce464dfab6fc81c361376c56d5e104ba75acbeb241e6a71e9f999103b4da8bdf2e202c435ae217e971ea701f26a1a9509	1674984367000000	1675589167000000	1738661167000000	1833269167000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
363	\\x706b61d80a25fa26ecd17c395a46603275fdbd28f624d01d3da51be15638261b27d81aeaffefe89868a788c0266071784d91fe1bd8995cfbbe8055a2e18c217f	1	0	\\x000000010000000000800003b63e53673a17be835d5736406f6a6c24cb0423605104b26fe6ff2fca20bf7793b061e77acb81417699321262c40d4553b4bf046d71ca60c31744c8482a334ef6a7dcd6facd3390b6017be2e29a5f3e283b64c91592b9b8bbb39b60513640a41c6bb2f9dd83fce5dec368ca87b0cd7085dd6b4dff758bf9df3dde97412fde158f010001	\\xed8b85b4d0f43fca98877ee15cddfe9193b07b169557d2efd58925136cb7400a65bfd958439d16826f24f59eb14629bcbf0cf1b71d3223166a52e7545fcd5b02	1681633867000000	1682238667000000	1745310667000000	1839918667000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
364	\\x74633570808dcce601dfc026f6c49b3853a8220992e61d5f7ef2613a0ad229dc3c624d404260cdf9359224cff7e82d5bcae6f32a0efc8d915bdbb27291b264ae	1	0	\\x000000010000000000800003f80baa0b4d4d70ec83f5839ab3fcf5246f6e09bf1d368efef0485bce776d915a35efc6cbf034536272b61d269a09aa7271f1d0b2c5dcdf59a2e20c7fcafc4915882b23ebb2ec9ac8db37f9dedf5efb536053c5a4b2efa467f802fd5e6be29ab2ac9738850fd56ef56c7bfc3ae10eb6658e9f6a8bb7188c838ecbcb6299d80eb9010001	\\x0aaa58eab2ecb56e3eb92fd979dff80b5fc676a957d55f4020ab4ee6c687c5ce47d3c55bfb74af82ec39723a81ed83a6a78c8ca5b887e937c55404bf07dd4409	1686469867000000	1687074667000000	1750146667000000	1844754667000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
365	\\x76dfdb0ea650c923cad20e4c198254a92db278b357c1678c1a32cda745acc884c89f238e448b1d166963c8c48df07fe2d22168a70afee09b0bd0cb7cc1341f90	1	0	\\x000000010000000000800003e45aed6cf05a725bdad3da0296b557f22bb9801a440ecadaf8792a1ca15be62a196aefdf303b89101b6ae039743701d64a40f0f69243af49a218ff34764c9c75dda8761d053fb54548ccb6dac7a90584c154cdff0ab07e16c95d9ad8302d916d8e4a1e791ad14fe832fb13f37cd6ecca44d6f77e2837240f9ce7b47a1592427f010001	\\xa15ca7e662a98018ffbddead9381a2822a85e64dda9d097b9a071dee1de56343c86f05df21fd8d62390b54820a9ad58d777e759eeb585004d90b02c3628e2405	1679215867000000	1679820667000000	1742892667000000	1837500667000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
366	\\x77bbc6ce018058b39f6d487d35f8fcd6b722f510231daeccd4861ffcd8ca3ba86448c3cb762094b18bda66d7e83db3043537eb9611dd2df4e11df310d58c5775	1	0	\\x000000010000000000800003e5ab011164b8703be1ddf644264e27937a00fbda5b5b0df762696c832781f40a8936bc03ca84ac4cefb3258decb455b5655095ff928f512e2c08e1a5182648c3bd097918efe4d097ec3415b3d8fd1f7ff6d5c6109c7c41417b6308a0142fbd6629b83e3294eb48b4b96eab63090419df664c3ceb1cb4ad1ba84f431b04064b8f010001	\\x935cd9c134b6d7cdd967b657ba24e00c20737b33e33146780ba6d3759714806b0923bfa377b4d289d518bed53a1f290995f482057d26bbf99acf89370e980b0d	1656244867000000	1656849667000000	1719921667000000	1814529667000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
367	\\x7b1bb80d963e4e00a6a202a8d84fc6891b63031f4e11ab212783fd00005beedcbb57b2364c56941aaeebc9d1032c1f68b66fe5d7408f25172d28a63f3b281b04	1	0	\\x000000010000000000800003be12483f3b3f8d5b0f7b01f2f3430bafd54e2555292a322a195318b2f35f7789cb41267382945fb495b742781eaf5dea2cc4a0499460f42936e905e16121557261a4d1b06a6a98ae26f9f9171dbe48f6a38b62b5718d5643bb76e5ed620d6d0c6d2594f2a36ed5e41a7879f4a7b9a60f01180ba84fd6c8e4fd36d6d8245060a7010001	\\x26ae2c21f414e2b5755ff447819822234229820878a47439142d4a5077a1ea484fdfa5bc6d84dffe6a68f3094a7c5f9609453d9f8d6b46c70cb802a0f6364a0e	1671357367000000	1671962167000000	1735034167000000	1829642167000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
368	\\x7d8b9ebf9dc1f79fc6f94122ac51455c63d7e6a6c62b4d5fd84ffd3f5774976eddf38e68fcaf072144d7fb55d98dba5dcbf0d83f7e4b7f6f6f51724278db7f50	1	0	\\x000000010000000000800003dd8c3f6c00271cfc639895fc0bb2db147fb5525bf7435050122f0379682a8eabe29bed6c99027acf6b3b2e38e970c34c1b903f5cbafa45b8a068ad68eadec35d623bb439bfbdfb4a61376250bd862cd35dd64659015e7a3e03ded3eac3e962f0ac38aa6789358197980125156939c71c67a82d448b5f6fe99288fde4fbf3b441010001	\\x7f643255264ffc40cb801477c582132e31bf9dec07617f645443291a0940ca0a4fe5649d267e6a27a518e46035c87db340bdd2767304fb6322dc65bd63d8190a	1680424867000000	1681029667000000	1744101667000000	1838709667000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
369	\\x7d83ce0b20668a0cf997d648276170c66e7fcc91c703417a715e5540c7cce0ab6970c5a1aa712dd55e850fbb545d29d00a62e95fd6ce22a8a064e4a34820c7b4	1	0	\\x0000000100000000008000039bfa292073414dbbd7765f930b30194b3fe1ae302414a03cc42e744cde00fe012181007bc59867613440c7870f64519c2374df04c1f17317699862d71ac56762a154d030842a0f4cbb2006da301565c7259556c97337a31ba78064c14b96d47a99d0fbbbfcc5328b4d401c0acd1f7323cebc1cf348c8614535601750934c3ab7010001	\\xfad06a03083c18a3e6cd2106356c10d7071ff48bcb47bbc11fdf24013353ca5a932d55b41d607011bbab9509c17dc827d45528353eba66299154057c38114509	1671961867000000	1672566667000000	1735638667000000	1830246667000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
370	\\x8243c17053976197e28de12401a7ec603fb90184aebc5c2693addf00ba6155af659425346f2ea76a9d921642a5142dfdcaa970d4317b0d0c7f6db55bec5ee25d	1	0	\\x000000010000000000800003d074388ab7c0f3bda54eca898c16c78f9f948bc311ce5204e8bea203db277d9fcfb4900dbd0dc463568220164c1b0ad558609f050e79e5fe60bdef2ae9a23d342dc5943ac2b09697b9bb782e17b5f6218de8fabf9fe7fe50fafec4c3ec937a99c82219ce18ee4e555e7c3c27e012d55a19fb1c93fe241f9666fbae57239dc3e5010001	\\x1dcf504c12f3d0a1a94b63a1022316f2c59fb6c3277489f7bb0b698fd60453819fcd9d0494d7d4fad2444c80d427a81d90d9471758a61d9a3a3a858dfd7b2408	1662894367000000	1663499167000000	1726571167000000	1821179167000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
371	\\x847f2cd203a6e6bf2aefc33a2dd6d043f0417ac6c50e11d60fdfef6e801663240b42a1490605e014f8ba39e4377af4f9ed055c08a5c101f5e346054338d6b531	1	0	\\x0000000100000000008000039b55ebca68460f6414fca7d42058825ef9880b40d6003ecb375b87845df529c15b281ed4f953d2c3f0b52a38f851cef5f1eda585aafe4112a23997f71c3ef086734d91aca98b2cbea39f57a8fc74965dd72210ecae8bc20619b4adba2055b420a8611d7477ce73a007d291ce63295ded4b95c5f32b9352450323493bbb978dbf010001	\\xb839e77a92f992dc6257ba8c4fd9c5963f69e856cc2d025e95cf6581b85b24a1accd25815e6583e2f45e62fa31ed3f5a3cda43ae7123fcd6e65ecb126e4fcd04	1681029367000000	1681634167000000	1744706167000000	1839314167000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
372	\\x89ab30aa801fddee5cb039cc5810276fe7ad20e1b3b180aab1157166a17707eabef508961acead73330771a5c2914d96a1b2463613b5b761711169119970ec60	1	0	\\x000000010000000000800003a8976649848538add403d62e78760e1b5ad4537aab9468ed40838ac6256f4aebee5b9056a7cee0edaafced40073332d876e7902b92fa25390de8860ea9939e4832ecfb51d4853400590aaa25f49238376e84dbab25494646fe92767a206869e7274e55cbd988b939475916082762bf5825f300c47be36d2b09fa3ef44417606d010001	\\x104a10a342c5acdecdc61e5349961f3d2e3d16bdeba62413b6b3827db7c9c23b76087349ed8360c9785b6b3973dd65d45bdacabe3f438baa2bab6b7ac6f6cc07	1664707867000000	1665312667000000	1728384667000000	1822992667000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
373	\\x8cab835b7dcaf3673ba670f9295b8420549ea0f11afab1e29cc161e8a3a5c19d814f93a55fce46f492ca4b591e57441b8c7a92dcbf1c7e1d970b60ee031a63ff	1	0	\\x000000010000000000800003a8e04160894e49967db536ebe8e0ba44d52cd5595494806e77653a5bac55613a3ee471513c88471b1dd442c6c5fda857b5394233a1a4fcec8ede00bd677520a96d43f1afc14923a456679022c10954a064b4bc14ae1edcc71222391821b5d7104ebd0c00858753fd14d852480109c9afc15e7014b442aaaeb5cd560be66e9ff3010001	\\x156bebb6f75785278dce2b4d7bc80239fd8f906e4f8c6f5bedea32c2fc463e29840c3343b2ec1e60530d9c00248fd078031affb4f6e622ea70011560ea2c700a	1665916867000000	1666521667000000	1729593667000000	1824201667000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
374	\\x8e7b779be56c3cf08742e6be6270d28714a8843d60269a67a99a2e6bbdb07bdbebdf6188eb66e53de5df79c7677cfd623c7015bd504125d4b48ea685dd32713d	1	0	\\x000000010000000000800003f76469bd128a360e9aecbb8bf0274d055688ece6a089eb0d9197c234a05c8b76d3b86bae3807ac1f8d2fd610cc9b434ddd58bbd606fd11389995e9b608e87dae9650cbafde22006b67e8cfce2d6c5e42956061a34e9343fb55b7179211b355ddd7ce9bcb83a552da36957ea0e833cff3036810a797991f72ecabcf1ecad9a9bb010001	\\xeece1848aae8e240a68f737a84bf20606eb881f1833584e5849c836385573d793bc9e060ea796a072fa12ee5f22c94df48036719dd0eb2886e0155c2a5899906	1655640367000000	1656245167000000	1719317167000000	1813925167000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
375	\\x8ed75a55096c7c9acb667d4cdd0a3ef7768d749f719af7ac84f563828599ded400d54e8418568174e7b95e116f8b21e02aa3a8e6fb13232053277c9afc0a4f46	1	0	\\x000000010000000000800003b2e0465deaef3ff2c7c479a730c8e6ce489c199eff8544f5a79ad8dd7c3a5a6ddb8fb0fc3932342e099fb459d254459fe33e3933b5d59b3b69f198ec1af4d40a6eaae5bc318eba9516e93b10e5cba6d6082a15140733cc120972581737c948f8ee544a7c1ae817b3b5b07b319c42798fbd3c1b5a88caad3cc8a0748bc9ac400f010001	\\x0873ec5dcff0a76003627f4a3cc379104fc16b66b56463edfbf10689b032dee0ab55f8dabe711360367253692898aa62fe7de79cff455b37bbb34c9ce94d7800	1670752867000000	1671357667000000	1734429667000000	1829037667000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
376	\\x8e7f77e41fda3deb6ec54a80dab954b50c21195d965bd8b6a90957616494b085143ba206f3d4aa127c7b312f1df381ae9ebe3e26f1d51a10c8ef7cc700462d2b	1	0	\\x000000010000000000800003c3d175870755fa89c486def7d36d4af7d2191dc1094941dd1b9d2874349e1332c13fc1023f10a756b6c418c0682b008d283663f7ff408ced2a33d72fc893fb8b2d2fd63fb8c5ef4a6a993e34874961668fdaf5e4c78ee4f50e7c316a416368982ec693109aeea57c9cce8d28969541ca7acacbdf2b9d7f225f2d35f210aa153d010001	\\xd63eb133013df6bae02d1e5c3d770f6d0da86426987f5e94fb752751c88e9cae109467b6dc5e031acc9f27aaf5bf15164361a53c3c87a53ce6ed65de5c695e00	1669543867000000	1670148667000000	1733220667000000	1827828667000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
377	\\x91b7c199761865d418be39b96e81a2cdb79b0b74cc2a4ae2576bdc9de887c19b8f1ec100d1bfaa691d5e610ec92df9ece47380a3d0c33ac57718fbfea5c40b0d	1	0	\\x000000010000000000800003bb0ba34b665ae5392c4d9ff899b0dd7a1b1899a6bdcfe9d1b15c2a6c8a1f7f4355b96ddbfe4c7486b2bd38a13ce2fea06f920a77d5e36979aba1dd16aec107eea3e5b76ea6b425f426732d7ee493a4210d26d100d38ffbe639a81e2151b2ecbb011be3777cec2704d24504e86632a88495acb51d27bd8cc4ea498b7798395303010001	\\x742c2c895da071fe720291d1cb98809cbca77813f516c4cb7b4ff4d332e8d30c8696716dd7d4211be572c566d8b7e513089b09d96d144a34449120e3916c3002	1671357367000000	1671962167000000	1735034167000000	1829642167000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
378	\\x92577d989e67747663f623c8dd87a03c6e227ef5aa905db83edc302caaf23957af3181e520ee44d99aa5cbc473d0ddd561855b49a2d2322675ef4b8def29c082	1	0	\\x000000010000000000800003aa9748e25e06f3ae565d0be091a5535f8859220976c0ee8d8daffd14ca5231e2b6003b7460d3d931e7452bec1b0af2f9c5c6be42c7662eea031524265b494c6a9c693faf970cac8973be3fae9b14363bf4c8b786d47981e3bcad6487ae57f73a58332d21b6e45ec047adad87fb003ed511e85cd775fa5d3d1108d1aa7c3972d9010001	\\xc499a573e9c79a25e0c17699e9065a49a0093446a126008127720d0aaa766bec6836617f98f3876273d0886d29e66bd9fb614f801b2f72b68bd79b37a5e7b201	1670148367000000	1670753167000000	1733825167000000	1828433167000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
379	\\x937bcb99affe195e65e9b380c91d744fafd2ead790141ee33aabc611da344a566bfa584a42c0c71246f117d155f5b0fa88019b596d3ae8c624ce328d2b08dd22	1	0	\\x000000010000000000800003bad6c53688425f99301e1b4ad0ebe92cb562ded0dc009ebd38bd03aa59b2df5f327ada1b756e01c473af26614e5fbcf9ad030be9c673dbf424f794fe2312a61de1516a67af0ee9212e46d476c4bdf10bfbabbf1b4bb1149c49cbad650851e832303c2b8cc96c01dc0f8f07e4528e3b6cfe9e4d9718e692af78b4049052e37745010001	\\xf00c5c8f22fb1c6a3071ac2c8ef5a88ff96e22607aa0e1eaf58baf8ec6660a3c0b2401b967452fd82a6512afac9fa1c0e56225d92ccd9b646f99403070e56309	1662289867000000	1662894667000000	1725966667000000	1820574667000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
380	\\x9b8b3c2a6ac857701eaae867e876a796897d9af48f82b02de5915b1e417c76dcf4ef845b1200e06eb066a5d0ad77a994704910a6a7e994db47165da90e523be8	1	0	\\x000000010000000000800003be2edde13e37ea17cf86f4651c5fb3d8030d5c32178850090cb7ad3023a580e96591f6320969f1d3c89fd82af2ddbd89590253737df88f01dc0d67e4061c9766ef5eab321d98eef88ef6dac327452b6a422e1ad78a2bb1bd59306d86942e3343124960e9bc7dc7536fc609afd3d3b4dade50fae0cca2f4dca84eb8724024cbed010001	\\x4b2ab68dd889a2fce15431a59981d29c63a17fcf394ae510d0a3204909d410cfe8ae61a65054bb7b63f354f0d63630fa35f0a34679e2bf190594ad5b5fb98e01	1677402367000000	1678007167000000	1741079167000000	1835687167000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
381	\\x9bbb0bffef935bebdb8e3ba746437ed0d490e5c20f1f65c6702a6cfae77107c4c50790049c573a37982db98cc94fd14235d39255d8aeac87c6d7092740651d1a	1	0	\\x000000010000000000800003afd563d2cae6b5163b8f8961c5c398d13af4aba46db4eed064ee350eb0a1e3cc2ece69c057e756a3093092d4730f5230ab617da45917ec03e42e39989b05dffd985a0b086f1f9136afc3123222c5833dc8b42c09cb912a36309405664e700085baa6952dc42e30ac9a89dc5d2b744c10c8a2065db92d055208a60d890a7c4c5d010001	\\x7d8ca1bba00a21a14aa02e1944760fdfc33b2d645342815de6265e2a7a0ae8b5aff269edc7742dd73fe5115b9acb70f33c65410819282c10fff82d15ea9f080a	1670148367000000	1670753167000000	1733825167000000	1828433167000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
382	\\x9c87d4ab0e090d79084465c2dae7a9bd9f3732460e423837c945bf9f5903bf094f32b599855172545b981543fbeedbf257f33f076003ecd36166808446a3e9c0	1	0	\\x000000010000000000800003aee343cb4449184498089795aa8bf0ed4e6000950808915982ed6570ed1cbeec8a3326bf8ba8e4230d90eb7796a42c5ec9fd4c5fccf0822ce5b55f4458cbd624d51e5529a4f27fc34f35d4615834d857750bf635c15a7e1b091f785bdcb5f6e2e94b5b8ad90813c376c880836ecd8e566ab1ebd82cc2623b8fe81814ea2d6d37010001	\\x212b6f96f86172b586c34171805018e372444fb4fcff16af085982f877cb55ce2510a8ffc8ec9c4575947f5b5fd2c4e3118cb97d435e602d389f1e3fc996e00f	1662289867000000	1662894667000000	1725966667000000	1820574667000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
383	\\x9cafb1c708e624555da86b4e4ea612d2a75407478c547dc3dba5016503ba9b2bf8ba800635eb3f921eef659f031df21e8109b0292e35bef47e0805a04dce7a39	1	0	\\x000000010000000000800003bb3ae8c8ce1914d5b4aeffcbe4f1b2fd56b271bbb065062d70c2dffc8e4468d472074aeb82f69b0e00b4178debcb5326d9d22670914b3560540e35acaf11b9959c8b0395a78e9655a43d399866a57736c72cad26c7eeb7a155e15440f8aa242742a6fb4766092f99eb3988762e1fd1bf13c03939d7a63dd65a2c80b2bfc26247010001	\\x6f0416a630c2d37b77d40e5c44ce9f3b7112278887d964479b0c90ce64f9ec72e1634e863531e02051b581f2e3f93efc2c5e1f17a3e5dcda6cd4a3979e206a09	1667125867000000	1667730667000000	1730802667000000	1825410667000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
384	\\x9d1378e72eb5c7acdc31d0e3bafc7a5851d1e6e14a79292d29712612765930061bad58edf4a5148ff329f2bb69a5570ad268a3ff355dd02a218d730ce4542c70	1	0	\\x000000010000000000800003cb5f83b94a08c2abfc974e1ece51a46dd6a118b217abd49038a528e447b82c07870ab6f4c19318f01704013b01fe3950ec6790c2aef2e2aaf55579104a91918e545831acd9cd7509a1d6f55ee08a30a1a674d2effda646e962bdbee925c1c2530b0539104567ffe9cfd629c382388e84b34f38f826d9c1599201358cf234b41d010001	\\x7875b250562050aeee31c4dc55758f1be081681d29da9d12e5ba8e152373b8ff97ebfb94b7f91005ee1430c28091e42aff11846d3341e8897f6ec53b47bb990e	1668334867000000	1668939667000000	1732011667000000	1826619667000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
385	\\x9d536fc52cffec064636a96b7582318d72b10c1a0bc1282126c4f25597be31013735ba39ef9407a8fd1ed4ed1935aaecc94caf0600b6f800c42b263b997720b0	1	0	\\x000000010000000000800003f090acdf003627df1fd6bfdd6de9d586c3e8bf60492ccb4ad0c3dde4e50be03424380be8573a3af0ea7c1bcd3d9b890f76d7a8d9ae05bbe22d7c984bd0e8e0b0a7808df3ffa1b7110493631595c907310c354486c8d2de7fe0db5a231a057a3d062fd11fa013d7b01fcef48eda57515c1526a32f9f1c9a47fec7ec1096a62ce5010001	\\x0c71ad2747a5f40a282e6d58ed6d43526ce53f0e1745f014ac007ffeb3087d0eea9baa3606e971233cd445e23802c9967b285b2106301b8c10961c044377ad0a	1656849367000000	1657454167000000	1720526167000000	1815134167000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
386	\\xa20351dbae8bca44a961469ff1ba5bb81c9636b0adf28e789a0b3a828e0ff50e508427d49716a232d245ba5b02c7e03043f11c80fa0bb8060bf5986fc8735e25	1	0	\\x000000010000000000800003d5f5f60ad5ea3c6f02fb170d15a8982e6d23dbe0b1ad2a39a04330e39c374a803b70b4fe12cc19f1ff9ca78bd2aad5612ae4cb8fcf6c3dd787d89543f134f96ad437c8e811afd0eddbec5151cfa7e35e779dae96d5b1023cff01ece4e41629b9702ddbeba8fcfc49d07903332124f3967948a681b3eb317f2cbfd2ec195af399010001	\\xe832fd55fb3d73471f3b1d350e1ed1cd893a5002b0dc705b2fcbd2431fdaaca5c5097e3cd5dd70f9becf33f9ecd21aac38314393c08bab9cbd183887d4989d0a	1659267367000000	1659872167000000	1722944167000000	1817552167000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
387	\\xa257c31d53823ea176df815969bb374f7a4aba0ca71d4001cae94cf8b9b420121758efa6fffc198c11501212ba5a55bc922bfa62bd7b79478384813cd3e7fc46	1	0	\\x000000010000000000800003a12c635ac23b7b89e65ed4c3802fbf66759706f78e001eaaac57d365f8ca1a3496198552cf28c1a52bd5fab7417e725c1d7d8abae958dc41fdf6d978a2bb532cc4485fdde1e309904ffb972f0338ea7bf2b19db9817a8741a846e45579390a4617fa7967c661902177a39762a66ed7d415871b098414c384c0c47c308c31410f010001	\\x65c343978e4e1c232610395d7252257893876906edb44e56807614bb6d8d004a09b48204f05ca34e890d2a851dbf3ddd1ba84e8e08c11ac6e44182d38576c201	1658058367000000	1658663167000000	1721735167000000	1816343167000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
388	\\xa47322eef0528da051141c8e8c91e81aa01c2484a0fa15e03a8b4ce4cd7386f776bd4766001d2f81f237a2ff67f37edbfef363f89e1a26047abfe808e7d1fecb	1	0	\\x000000010000000000800003aa02817ade3d1de2b70d1e5a666cc56e3e075b83ef2927dd4ca07cf86bf87619072d5cd2b8d972883b3a5b1b3f67f62d280f4ab2fb27858468fce285cf8e9eab9c8c7118cc7b372fcc17fe337871ec2e76b936bf45bbec163f093d0c20cc5ffe3523b2b51905af7229e169974e1344c79473f5e96d9b14513f76b0f36857206f010001	\\x64a59d9ab3a7e0a49d0dee15c7ede9445c5499667279982571246dd5f1711395ca28c41997dbc2ffc0c6c34f49b35d64e71639e03e502f4d8851b5d6082bb607	1670148367000000	1670753167000000	1733825167000000	1828433167000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
389	\\xa47b70d9193696fbcb6247fb8c5e81ec144c9fc5036d639d9e62958986ce66091c8310ffc6a4a5865a3d13d0621bba21107d6000cca065433e60b25e6217e008	1	0	\\x000000010000000000800003e3b88ea9de32c90d0b5d873ee2e03b448ae926de41ab5a2c44f8a4ea154da72dbfd8f304d8c990908de4f5aa3ddba8677dbe5b4465056b2790316129de51c6bec092ae9d23d8b58391e97a61e33ca8d2dd9af31bb2e83bd8f021f67148339e7aa0ae78e3773f685cffa4787119fa01fdce9e3f769c0af73428d6aa0ce4ff7e5b010001	\\xad5f17baedfd66d0b66206355988359cff415bdf28198bed34e5bc0ba2cc5d802f722a53251015aee96dac93e20e01e019e6538791c66878086c73e6dc7a8a02	1664103367000000	1664708167000000	1727780167000000	1822388167000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
390	\\xa737da7fd56e297bd3f4bc2d3667b3f4dd1ca5018ad1f373f0397dc3139b50f072dcaa58f3026524c7ba68638f7d9b5f84805848b8e01503a48cf289d6b4281c	1	0	\\x000000010000000000800003b3bc32eed5664f9659169c49108b96e7a15d49243426f3b768a7aa55cff96c278bf40fbe17cc64a31431c247459387811368e316a837b7a577568aab23533e048bd8af8ff20419c27231df5468d3cbd467eca988b057ba29abeb0646758c440e6e61dcadf935fe27e322ad5acb76f2e5574e9cffbdfc30aca981c2755d1c5173010001	\\x0d03d0774d6d64daa393505ecd639f7821bd03a1dbb0f8ca65c6bc6be74d345ad054a0556c081c6261bbfcd169a234567cb845e009e0f2a36df6bf677f94240e	1685260867000000	1685865667000000	1748937667000000	1843545667000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
391	\\xadd3ef02c26be39077f0b258249be20b158ecac29942a4d954c103f443a00a58306c43453e4290b6cb01bba072979ba162daef7814c0962aacf26173f870775c	1	0	\\x000000010000000000800003d0517014312a33e69fca29c1e7a3749bbb58e452de123746d092a07fa97e8f515badd6dbdb60628d0a72f7dd1f93dcbf5b26445b9be0d0ba78fadef761fe8630ee23b2226a1aef9423a3dcfea8657fd647c203e11d19801aa16762b99bcd7a2f25a6ac17b12460cff1f9fe17600cbf5aeacb444c8f95d14e6bb7d7f13a581965010001	\\x1e2d1a6df1f0cfbe1871adaf280d3612053a3fa172567581cdb745e2ab00b5980ebfcf987804922aa56c3aec06a22d41486e1b13e215f0c610ed9844d5bbcb01	1668334867000000	1668939667000000	1732011667000000	1826619667000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
392	\\xadcbe53bd75b3b0677852446c9f4736c856072211d683b902511cc0d201680026181f65c04564090d2557552b9fe57ce09a539306f5702d716f122683e471de3	1	0	\\x000000010000000000800003bb2121e8ce2e1e2d6db34fede439803b90b77575a5cd438f104a83409b35c2be9ea0aad89895752b8d97e9f1270d19733fd992b3b63fd9616510350c0ea623b8299ef6cfbeef8c19526080548a0dd1faccc39f7df070de1877247f639a82b1b67cef11aa54134c19cb8d1b91ef0936be8c2d60c9a312f1a1daa38f45c5963355010001	\\x8c0cd1518c2d7254108bc9026c8f341fee6983bcbb7917e4878773aa6bfff3351963dc204d1dbebca7169dca532f12a3769f4ca3cb995ecbf48bd45a7d019208	1671961867000000	1672566667000000	1735638667000000	1830246667000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
393	\\xb15b809375b1d54a944638d7e3ad7eaed7c28554f2d921f6c289086772a5c214f17197fbe0e2ba532ae36c11e1e93e9c5c519180f8a86455abb50487cd9704ed	1	0	\\x0000000100000000008000039e378e38508abfe48cc6f6a23b5120d5d55a68435e80e78cb5e65d6250df5a2ccd70a6bd4ff0f28289c0e4efcaee030464ecf75f99800094c7fac8ebba32cd9024617e567cdb6c1215dc239c1bbf0172f32c3ba4303044680141255fed99435d911007cb0047896a4d7c0477fc62e45ba17ba8b1b095f9ab1bff8041e99ca67f010001	\\xabd7532402e9f7a300ec90e54a4120839712606884b245364d8a2e7b0499bf23a739da0793864cfb4239dd9581502aa86b1548d2278098dbc3f09e0cdb9a6d0c	1675588867000000	1676193667000000	1739265667000000	1833873667000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
394	\\xb5db326c3d9308093d208d6798a661c66ec7d3faa96b96f2c82c4c01aaeef02977da24b9907436b189b0197062bd4da6bb6948882f0976ed55a75c73318a0f9b	1	0	\\x000000010000000000800003d07aa5569a04d5e7c839790f6ca632179c04c771599751599ca9c270598f9af6d1fc07a105f140538775659c6048eca55232203e02996c220dd154bb7da7a16b6f167d2c2b6f05246182a7e0dd4fc5c310fd9cb9eaf5fa37c1b1698c365b463837744f0f2deb8f059c090631ce60d60ebdb0332f9d28bddee62c127f427605c1010001	\\xb3f2b2874f7cb15cdd458a6bd895323e101e0c8ad6f7ffd5602ef0eec2a78b6198f07cab752aba730086111da04bff8dcc3afc72de03780c93274554dcad1905	1668939367000000	1669544167000000	1732616167000000	1827224167000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
395	\\xb8cf4831948935caecf0c4ef71332567d7edcbcd86808216be7d340af4d2dbd84f359d74fa464f1f0a357dc98489c87e5fbde7dbd395bc68b616dcd3926caeea	1	0	\\x000000010000000000800003c52c6a252eacabe661c13d0b6c8dd2cba0159b4624e499eb0274f73fab65c0e236272f62d6db68c7f662e7d0a8f4236d0318239bb5175f77b3bfe59c820f0a1512266d97438ff54e9ad49bda70718c8bbc19193d5711b5ca9d2f1c43c4786730fd71b09c663aa8de7e228f65e25a74e63e6147ac1624af9a2e519842295e70eb010001	\\x23babe15506fb2b3a5836fea7c4b13ca06e2e831d4ac5a55ad78bdb4e2e0f20fab1cf6e297b78eceb00db9eff541a7e4cb24e97b660631650196c1ebe280590a	1685865367000000	1686470167000000	1749542167000000	1844150167000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
396	\\xb913bd7ac731555a7a0abaa0979ea5d554ad40b74df7cf3753fd022d1ba638c1670248605d4cddec15503d5b3002b18f3a24e4a714d928f77c4a0f71a9314d72	1	0	\\x000000010000000000800003d2984b453425ecb6fd30708b123c42eb85503a27e33824d9972b8e58d85ad926f4e0bc9cf69bc7b03918c38f4b63e3f31404902da18b1a2ee87ede3b92aa3d2e585fd57145dd946d835a4f8c5cf977bb7596f903a43b30c16d65db99541cdd7fb22fe60ad8d697763e3436198975801c738d6647776e7a7b272fe65952cddd7b010001	\\x5bb593655e93a0f9fe4f980f70da3ee8384bea026a988df511c3eeb369e1dce9b2b9ea595da278418118dfbb1b99fb653242ef32016419b10f277edb5e5c0303	1661080867000000	1661685667000000	1724757667000000	1819365667000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
397	\\xb977bed35f27fc608001f191dae6a0c102c837cc446464cd400c9c050c4485d429d6db68f96d2860dd8c9025bf4883e91a35e142f8ed931893deaa4e9976e09e	1	0	\\x0000000100000000008000039903f4e1c678e22de49e59b14cf6760101823b295a6e97f5a1d50d3ac5f96895f861fd7f085ad44f6f62075c4061587685c9021ab45dd1f56b7b24a6de3bd0e738d9ffba6e894b2a3c2e8ea2594e025d53cbca2c18ad4da730a1ab31b75beef947833abc3a1acd0da2c74ef82b0356cb6a90026107259a15651f479f3aa5a9d3010001	\\xdf95e9c39a72374433abbf44756fe39d76b084e959eb7f063afeee5aee6a376920b2ffb8a5b97d6a749b3fc89871b7bde9c8995042f23a617aac25c05f586807	1657453867000000	1658058667000000	1721130667000000	1815738667000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
398	\\xbcdb2963f3ae9c98da8f7808a38779f7d2b4ba7294243004699b6d7d52a5e776135ecb93248fc806ed5478adfd6bb2b365a9c12d3091b4529be3eda3542a6e95	1	0	\\x000000010000000000800003e5758fa99fc290f2c3f7be962e473dcd33cf61871259eb89bb252af3a1093ace4e448445b89af48ae33652bfab417796b12922f85a3d84615f8142517df17d63b19ea0096dbadd82393eb27d7e489c00f9e09f409213d3d4274bc88d64434165ae2ee7fc3b19d46c275da338b5fc341fcd86439bb15611aaffe88cc9946a1883010001	\\x7e442e1d2f2eae7bb1a631c2576220116d84cd855ca58d3253a70a1831164f286382beea524674cbf093f87d8b42cfd764d22614f1bb1f397fc9e6402b62c40f	1678611367000000	1679216167000000	1742288167000000	1836896167000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
399	\\xbd773ae9b93b9af398ef5f9f8be9c178af0d9d5ec370b5cf239f4d8af7d386b07a80680eb38135922d00810d81c715bc0c31012a4c1ff653884d1d2b96d09811	1	0	\\x000000010000000000800003da9fbe55d1c09571dfef430e3c265f252e8a3155ffcca158aa574e077317eba6cfff93cf7d6478441e7aae3e44f9e5bb360c3434a1c116a2f4566eaa241625028fb4ec27cb1d9d44df78266795926d08621729cd92739fc7183f9a49c8ad1eb81f25fedaa6c4e5931de23fb9b12217b71296d45ed8fca0697b5d1cda0d08174d010001	\\xed9819c15460714bd02155a03ce841722fe3648c5c25ce48f082ab99d5e4939dfc21e1db1e44bf367e50debcb510d96f7dbda6afca8281308bffde1addeb0202	1679820367000000	1680425167000000	1743497167000000	1838105167000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
400	\\xbe23ed58927510d0c7027f07b8db48902d49af72f0eed714a5a2da6c259357aa5c0333adf9d4a1fb7399b4136365cd1d0da3d410c93ea574da2e8c8d89df80f4	1	0	\\x000000010000000000800003b97bc0f4bb6d447d1fda63d42bf5c9e9918a7343ba1332526fb35393fb65086a1270f7fd5e75e8b3cf3e0cff787c175cbc66f5f071a1d0229496de76cad45643fad78c2284f8786361b8df217a9186d25caa8227476ad5ea7ecdc4428e9e9235e13f72ead5f0d4b5c658b67597c6576a493b9988eb4c35c9a1ad1d2dfeae765b010001	\\x95860f05a6efa112c9b483edbe672bbb6375dd0e836e56f26ea530db1abd3e7aa7da3861a9a55adcd7b9e06a52787cf6e33c8af0b91a47f7938995f2ac56a203	1674984367000000	1675589167000000	1738661167000000	1833269167000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
401	\\xbe2354a0dffcf04dd6f841ec617025aba285ca38a9842c302f95db876d94fafad088f04d05e0e741ecbdb809ef5b703627c8f2c2c0ad5d2c26f1d65d957c9439	1	0	\\x000000010000000000800003ac26a4746b5e593812d9d8e29e5c5dbee49ec970f6d568b05d947c8874da0f878661483f21190658e6405a33234b1ffa5790d611b22c86130e8f52c27825c650e85df5c5f7a47e270c7595334e958ab70c736425eaf88879ac4b6588d7463e6a47f32d40b3b3bf68c253ed41b2abbaa6b3929616c7639803a93f16301973a84f010001	\\x1fe55188af1d8877c9a486a0da6970ee91151e1e7f3bb38eaff36050f04dc4d8e0b2e20e8d9cbd88b8637921fda34d8d0f6ced2b29ead1e9a5f045ce81a2ef01	1668939367000000	1669544167000000	1732616167000000	1827224167000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
402	\\xbe3319cdaac15081dbac82f63721d626abd4abd505b1f10256408eeab3a9e6bfb9d0e0f2dc518672a0620157b6b2158812f9d159b422c82284bf0a916e14209f	1	0	\\x000000010000000000800003b68ec69e677e0fe061caee84b5fab2b93d3e557ebe81e64fb66d8cfc68d44611dee76d8fc414d7e23a27f44882c40cf88dace4491fcd89c6585d8707f35ebf6d27d3fce9dcb976f2f48bd7a7a56426704d82589068864859cc7942ebcd7c138aa0911ae7ff25ad406a9d025f7ec7cebb93f34ec5902793c7f3c571f6cbd1beff010001	\\x62db941675a8c1bbccdcc0972b568336059a9d2c0afa27fcae30bef777afeaf5258df626c5ba9b63330e72678843caf826d64a56717de82103a035104f9fe60d	1673775367000000	1674380167000000	1737452167000000	1832060167000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
403	\\xbe0b989b852c85b797c2a6590c07d5aff1cb30802daa6669a0c7bf2d19755a08c4532926671c4a4621f5e0b9c644b6918f6bffde8fb00de02d5594e3013d8ddb	1	0	\\x0000000100000000008000039f7c05b05ce3458088c1b96b181e25ecac6898e99278796c9bd32dbc377df808940668924e6f79dec87cf3dab0bbbee75bafe3ef6e63f960ccfe7731f61ce8b06bc22875db93842fcce1eb127c81ecdaf1655917b9fd8d811288ba953e816308e22a58127a7ccb87d16b2e3cb51bfadd11a76703431549fb98ca2c900cc11391010001	\\x398f4f203b5bb163a2b5c4993de2816a32d725e7833ba48cd423a2575d446da11336c9d0611cff43890d0472ad59c7a6d7309f235c71791f2108dc700aa3570d	1656244867000000	1656849667000000	1719921667000000	1814529667000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
404	\\xbe7f08b4c3d06f5368091bfafe308f2143bda23dced9ec2b885b0d8402ad83aca4fc0397d6abbb01f94e85231e7e9e1ce0a8e6d352fae89088207e81b76986c2	1	0	\\x000000010000000000800003d238cdfd772823a4790a34cf55bc5c9badf9f4b838a2b2bb4647cd57a18f3baa037ba85c095d5ecc465020a48a6e63671994835a9cf5340e587cef2ad7e4ca82e6d7bb2942c14ba000082eef1987b820b79e8b5cad9b9504d424125fdabb909f3fc89f257bd93a3b6205f887e6c0e75fa28c64da413f6bf60508e25b72681f7b010001	\\x60cf66d6c303a22272b4ad2a01ba87890b95e1b2c85ed46f1ae48441b2e12530548d8b501d6677f6f25ee5d2e3fdbda0e033e2d504510be2659af961e75df700	1669543867000000	1670148667000000	1733220667000000	1827828667000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
405	\\xc183bd303f2baa209a584113ffc84b8ff55e712a36f01147615c45f3d87e414cf22bc13bbec3cc0c960b125605bc476df1ad16c00340b8e1d8577dd8a541cb00	1	0	\\x000000010000000000800003d2700251b34bb94de6efca3fdfe518ee1e5b42393f8efb550a61fd8d4e0d63203c1b421d7aef57e04cdecee4a11b9bb190989d468fb719be5da90d152226c56acd8eafe177599f4c3c5ec6614833aa89b76874237e4dd844378068fd479b4c35930103eb8f7b6f64f43ec655aacd3995867b87e3e02d2d9b5a29d902e12ca103010001	\\x018210bcfaf08c6679531a650d80989b54bf0d754dc22bd9397cf478f7528db3088b249e3c557463b72eaacdae08287102be05d414b07702c70d7c6144302e02	1659267367000000	1659872167000000	1722944167000000	1817552167000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
406	\\xc2bfefdf1d9ed332b5bbaad0af8aebd94520eb44f831a3fedb920f4fea2ba202409a25c54cc04950d67ca88786a8bb20545dada74495a02407b9f0834d585dc5	1	0	\\x000000010000000000800003b7b05f599f6656180862301861d87e9767a88f3855b978c7f236b837300ba42084f6b058dff42fa18e9be84a3c09f3d560e9aa61a57b6a713d3d082506e9141a6a09d4fa478704b403e3f0530e090cf6525473d747195be5015f65e9fddbb6d7e9cceed0a031ed131e81f444365cc2edc344e31562ee4b4db3ea07f5c9fef64b010001	\\xdff6b91c79f674f703e6b0c8f0427098d90bb70c147f4f726e467e72137ac0cd6a7b5ad33e78be2fc6877e2d1caa4c97c37e7a7cb21acfcc13c639c6250c7f05	1661080867000000	1661685667000000	1724757667000000	1819365667000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
407	\\xc317c5902947abebfefb7d23fba8f1b321c794c1e3da741bde84c50cb579c7e98cc0ef62dfb62a8d72a23dbdd2f9f3dfe61b1b11e06de87e97c25a82e500c64e	1	0	\\x000000010000000000800003e1d470d215a16d65e24d3177a00ae71a70504d0273390895bdb8371450a68128d30bb20006f8deaf5f6df670defae577fa16dabeb8555b1ce0bac368e8df8cfde2e8df77a4c3dd61d00aa5c33bd202f9c5a8ddfd34496f27f4ba52a0e6337f55f7d806f962b2e3a699f0720066f3cc72f250c6b724bebab3a4bda693c2d5d73b010001	\\x8f311c4dd1ba4701ddb1773a4e019e5a1ff1619d688f48a40bbb9a4752671fd2be358aa442aa9213881d6c7bf8b424e36fa49a8eb4db5bd30bd8f74bb9458f06	1672566367000000	1673171167000000	1736243167000000	1830851167000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
408	\\xcca3d387e99b7e812563a1bf5b267c660a5d4d57f26b8e0590a9560d4feb64b9b299c28937dc6775dacfe2af6556ee4058e065b3de66786dda82b037861fa332	1	0	\\x000000010000000000800003a7d2294fa8ff7d0303efc536f67f5efdb119382efeb927d39f3cc69cd34bf42b4587a679cbdfb090481069c30453435ef05e904f918722d9f538110278d555ffe057391eeae6d93e127be35ea30945ba23e5e93d60ca0f1678ec0869212dad09d2865c223906409c54b6fc5b91f6e0a4996f4751f85156b84ee76021c1b96a25010001	\\x87a20423bd9611437a4e086de1c916ea1e9403e2a47be1f2c3406aea14f5b1dddfc5f9d357cfa1433a014ba4138ef6fe5878cf79b6fb33c5700818d08df6e104	1661685367000000	1662290167000000	1725362167000000	1819970167000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
409	\\xce072cf7406ec5acf124ea5600927cce7f9d41d22a039a70355d20e7083a44f43d875385f131e92e460ebc7d655f3666b8b1342c7c75b90a8b21b55ff878e942	1	0	\\x000000010000000000800003b3255fd09ba0fcac41cd6fcc842b359fbc07e7fdf00a04aa76dab415dfcf857a774111f0c5c772fac5b49992e60cf58d411df979ad2b00171082b254222bab7e56832bc382d10bc9f5932064157fb516ab837538d01ab95fad6b9697057e9973670d9e8a691e3513507180b5e4bb6cac29a2ac239695df479592e8bd5a958bcb010001	\\xe6f8dfe6ce8632612a03b9099b6e12082ecb37d6a1f1bb6510a5d298e8b78493c24e65348067c04bda53a124e8a5a48f19cead7e161b24b657e4fafd27285509	1659871867000000	1660476667000000	1723548667000000	1818156667000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
410	\\xcf2b0ecdb97d4a5bc963e58d54128be4678500c8a5361b4706da1c074709429f7878e1772c6540d5d4839111650f48a333ec7b599afd2e937949e3036e29c046	1	0	\\x000000010000000000800003c04e6354bad8fb201dd96e1d1f3870af2ff603ee6ffd6710ea60a9e8098e10a73e4cffe9711fbbd216a6823606a555531ca4fa29b9929d9ee0e3849d3b4d8bf37fdefd1aaa11338ef236e3d8c889848e851d001b0d34090e37c24af9953306a4065dbe2359e555ea3932f10362109b42141dc16d21f732ba1b2a827c65e3ac77010001	\\xb2ad3f53e7b8c1a55d7c0f12830717bea141549a673615f2c7beca87bcef1b0043b0c55cbd5bb211b51d7a378a0296512a41561729013be5be5073b235ee7b07	1664103367000000	1664708167000000	1727780167000000	1822388167000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
411	\\xd0db3601b517ba46fffd7992851e0b7fb699a9bee6deb5cda4c258764191da419462cbd3d76f37d7fd9d5a984099f43c3ec01dfa15f4a6c90da7f7353f518652	1	0	\\x000000010000000000800003ac73ce483cfe186521b0e81fad9637ec26b051f2d725e0c81eb995ddbd51953462343640ad7c8ba8ea5eb7be3f12b43858e1bbfc4a9046bb927a24a0b345c02dd0a833284198756790d652e28deb7531f1210c04de5752a325df84c8dd6e71f5742876679c90d83c4fb6a3405f84fcd271a899a21d326cf1ae7a64a8d3cee62f010001	\\x7eb5c4d9c9dd2e9f7f464b629f434ff294316602a04c8767721d17056b10287f282dce1b4057356b6edb8d136cd206b4ff0ecef80269c200013e342cff1bc204	1658662867000000	1659267667000000	1722339667000000	1816947667000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
412	\\xd37309d7b30a5f6e50a6b7eb6dc13d147a5e84a75b4f1c3d082ba4170af8eac7ff1da3cc242ed19ed553510a42208f79684f2802187e67ae87b218564575d705	1	0	\\x000000010000000000800003b8069f76f1a1e2611f37352f07676a8bed96fb2421cf391bb5f94d9b092429cc80468898344fec9ef37f5de4d0a627052e0459e6761a9c6ddc6a2fbae77c665f5910ff68485f832772bf2eac9c8ca763ed6a29ebae05151957967b4764cde5b5a3c18ccd83b7024029c94000702dbc5dc78d80fbb42ae0705fca0aa0d6ae470b010001	\\x70ce974c09a48855ce0af23dec178aa7dea6bcbf28b553e4eb4e1695865ac69487d667d8fc916fcbd659cd6329059397eb86030042ca9f627e33038c71a6ab04	1663498867000000	1664103667000000	1727175667000000	1821783667000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
413	\\xd943fd5139d37c77a142d16cd8b6edf7068502e30b044b8a43fddee786f61a771f2632aa28d4c89581f1405b5eb01f7af56c649e3e847c44eb1a5ef8617c8dc2	1	0	\\x000000010000000000800003d99e99d70f639b0e3b38ad0799762d3bcfc1467fd62ce84599dd9910837e19997126740319503fa44d634bff97078092e1597f6d7ef0859e4384c4a4c2059f270ca797a4cb68ee3f9bf6f2dde66696733233eb8b3485044e6be2e48859fc55aa34a38baf65065befc7e893e89e8dc1e7be5833a9921f72b7ce14742b6b61a5a7010001	\\x86070cb381d5e3e67fdb19516d31948b05b5dac6251a674ac490274a7679c9c9761a86c4b996d8f67802cbaf60cc5e342c0c50fc35c66c84d02391b42a343c00	1681633867000000	1682238667000000	1745310667000000	1839918667000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
414	\\xda035a1d1d057bdf74f79e70f8f9114274cc6dfee7d63e82d9a8d8aafba29bac843ff1b5c9ebb016be774546d2943fde12919a20bbcb84307f5de61188246b87	1	0	\\x000000010000000000800003b54a2f9048ab9cd027cc5414a64258d27b08a71e63a125f101f3bbdfd4639e05d55877c255e2634ea99b6ab1794b1a1d43119cecec2c1b53209b3b84240c89f7191761703808415ab45a172b9b926b1076e33d6381a01ff89d322171bc2538b4a2a9954114b6fc72b88b4847067c4aed4e22cd9615dba911ffcc39fea1065b99010001	\\x2b1816fb3c546f4863b4e0c1f4348ddf446bf3d743f991b58eb9882b04af9f691572c91de374956e52379f5c67b1c9b6dd53844ca7494434fe11d779516f8602	1671961867000000	1672566667000000	1735638667000000	1830246667000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
415	\\xdcd7443dfe31d217a69c1b6789112e9347db23770597ea9d8a72a24ba186da53b3a9c8b36aff616dbf6f6b77cc85210e66fcbb9a5c28733dde8b2ef9e32e8f5d	1	0	\\x000000010000000000800003c91c7d365e4016b606f05456160a9f99c3817418a12e4efa8b7782d2fff3cb590ac7368778fbe5714e128dd0d425b3581aaf612712fd9ce8ca4edaea495bb2d988f95bd681aa25386a69d314b58957301cf7f6fcd9e0328c3b4c146788b843b339306dd097abf01ac98fb87900c6ee3419347214b3d4de1b944dade5be63ea19010001	\\x37a52fe29f411167d984c4b345188a01ab55deed44ce2d624294c0e2e0bc93940164b29430999f7362dc7bc1f2aeab46d21d74354dcdde3eaeb304f0a66dff0d	1656244867000000	1656849667000000	1719921667000000	1814529667000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
416	\\xdcdb6e2c631822f1b077ae0374259a3be3397df645f4af1c89fa789015f138d3c14dc9189c6f4ead54ae5e4571fbd2774f045afe5f77f8e0061886c6773200de	1	0	\\x000000010000000000800003c52cbd85b28a23f20731b618c8808e28b6dd6cd680410df18ecf2163ead23ae4ae20652a2e75122db3570565fc8b40370fdea40edf4e9dc51b79eb633ccdcb5ed626b846b8357a2c217ae52b2046d6565104e2a190b5b2311e25af888d7e24e0cb1e177f0f789fd840ac9361fdb6d3fe80622752381b66582ce16f46046a4215010001	\\x1064e9a2bc056043db5e636929b69f26726c69d79b7fdcd9ccc3546f31b1876ce26e62f5d8a852768e1116ec5d330862546223d64fec9f2ee898beadfca4770a	1668334867000000	1668939667000000	1732011667000000	1826619667000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
417	\\xde0b75cf7dc1e737adf985979bf7483fb7b963bf34678c1b98e780f9ee6c38ef7131f0caaa994bacd0bf0b1af6b61450c39c0d81994846fb83624227a845cb4b	1	0	\\x000000010000000000800003d2167a137975701120a6dd3701b9a3e4c3f35d5262f276fe7f12b45efdb27a2da05107107831bd3dd0a9d49968d7a7a61da0821a2a84f2865563cde252e1f97288a24862946cb403ba4cefb59623a32d68a45bef7a99253f5c0ca1236adaa5f81d525931b380b0a647b6fef0df80f5c23c3b93f59820f9e6ad85f71dc713a709010001	\\x0bea4a4627c0309c5e2ca5cbe964985e2b76385d2cb267304cf64f8c835a9d2622d58185753c81c8a45c7266ba9e8e385abd6fbb6bb6277a6c2b09818fc2b50a	1662894367000000	1663499167000000	1726571167000000	1821179167000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
418	\\xe707c3d0376d6de24d990c31c1ba1f722b09a02db337ef6c2477b9f2cf5fb2daf3048f476b2b94cc2e1359fad4cfbd5571a6f17ee12fe735adb26d4a760ddc3b	1	0	\\x000000010000000000800003d956848e6c6035037abe9648098b0d766e07d7d8410f99787189cdd074f623e9cc31830b938a0518302c1bfeeca0601724b7f71ef15b6adad3dfdd40589cc8ef33ce358488a1d10485ccd4d2cf257a412377a25a47ae9ed1724bcf51be8ed5034469dc7eaf0db72ca49f142ab63bd651f7a6e279e14213046edc28fbd64824b3010001	\\xcb00898cd59de1c342efe2685137e72f9e9ffcff10598238378eed0f467a4205847c2649b9555c52903470de1511a1cbfcd0f97dec4418657dd63ab0a40b9502	1667125867000000	1667730667000000	1730802667000000	1825410667000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
419	\\xe74fb1223159b4ae12727d792baa63ad7c127609299d83f0e4772735748398197ab25b08c0a04d445ba7ad8fc65027179fd26a065f1851d8785546ba4fe78fa8	1	0	\\x000000010000000000800003c3e5425bf5727ff3bd480a7df4f4587bfcc0e6060009a17c9b3c61c6d6187a2a37901689dcf0a7544b2a71b3573f7eb7eabe5e45a4fd5bf2194af376bc9c15087c6d471262539c4c3b8817dac9e0af05a087ca666fd3ca2b33349a0784b96a78b76a13a1c14befbc0a2923fa87ec40f9be63b0bbb454616a4982b37a8c6559a7010001	\\x70631c07038ad3c9057d187c111762be08643eedf3e270190d9909c23532a6b4479d090844709e4870380426c98ca844ae49b5a8c4d69c76420e24c5cd1e0f02	1685865367000000	1686470167000000	1749542167000000	1844150167000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
420	\\xed1b3762433c79a7aa13cd17a929e5b006c3bd2ebdab3ef5acd5fd9cf7c1cd5a8bbba9b94c94411c3900d2c651988e27a6eb85a1e4c3c47bb724b3585341d7f8	1	0	\\x000000010000000000800003be49e41b4eab8cc4ac6c0a2e26ff080f126db7affa9720c2dca1bc9e544f7b73fb826d41fab5e6aa3f1e20737dc526235d525cee7657ac13d5f32bd3ce6150ec5df14be7fd96f497a0a3cadb91831e6df9758f07d6c35c28a68b442f0267e906dddc92d0a91cfab93908b9cdd544035a958eb1ebca789724657e7137fd47b441010001	\\x4e9e83e3547b3ae816c236ce3c92d365811117b808002ed7c0f9d7209df3344ed1f0e644ef551d67139f44ff2ec95ca26b409f9d1904c1fa7f94fa57b43edf08	1679820367000000	1680425167000000	1743497167000000	1838105167000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
421	\\xf29767fd862bb2e37297781c502409136dc9ad1405fb1fea2f734c11865cacb80ce57e00e6aaf4d8c5a02060c9ed61560ecb967f3e505208e4e33b7112f48cb3	1	0	\\x000000010000000000800003b23e24c0b178d26898e408cd98102e0aaed01d38bf99910ab91ca969f1e258ef2337f600855b1f4f76db852a00d17983d4b8e6b5c03a90ddebc248db8a4486db5a80a064f770d7153379cc990b8326a21c55f28096f34a1287255dec52ef941fcb42223d8bbb8a26b03b01130a4d532faae4a4052589ec6175fb1a6428e27d6f010001	\\xd65201eee2396708fc0664096149f522be2d2600c712965e8535d03905a782ebe8f09dbe2a24585b4bd28e210b5b1c505486b5063cec1f776d20e907f1e40b02	1673170867000000	1673775667000000	1736847667000000	1831455667000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
422	\\xf2871acad8a43f8a5a2546a29da3cc831c70684249336698beaa91383495e8a0fe8206012e1b0a65bae3348404dddfbc99d283db263806fa6cffea5d9af05195	1	0	\\x000000010000000000800003b569c48e2d1b5a1a8b181ae0edacf0cdcb1f4aad645f74dea072c6d8b79a8a3aabecfc3e41d40dab19385019e3eda19a5ec6f1b33ab39c55529a2eab5a68e59678f37a8cde792aa6e8ed24756694966ac7e0806284cd67bc383d778d962555293c32dfd43eebb0faa7cc0fe53a14a7b2dd809012868703a95b095ac072cdc11d010001	\\x623c17bdf6e76f6f3b7559280274cd5acfe89e0b7699a1e4919321c6d72e71ee78624cea830948ca14b4f4424bbfba044c062646cb42535617de206e0c439109	1662894367000000	1663499167000000	1726571167000000	1821179167000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
423	\\xf447389383dbe1edc4dbf5589123b8fef8bab2f68dc6efcff065f802cb0e50b7bc39c7c5eb9a05f4047b7b6dc704dd0b75258af4d80fd280748d3a70cdef44e2	1	0	\\x000000010000000000800003bdd9693cf038be25d1877a194ef6cbaefa20c42a2ba39588057b781345549d4bba1e76811a9beee132afc7cee0837f9da5a6e712a4afc2695c82551396b872b4f8049ccd41fa8bb5356e5c4b0e4e2db0a3e34f75db5f7ea1f926154a0d143216be884b4a6afcd9101a7ab16fbec28bd16f722ac456cd3facfdb276924c29329f010001	\\x9ae2b19e01cb1d936ee4b1a4b858f883d4e73d5b918b66407a33603f68415ea7069f9aee96c0cac1b24e5e1218acaef2272dde99069b0080e646823b83851204	1655640367000000	1656245167000000	1719317167000000	1813925167000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
424	\\xf5d3e14ec6dcb2f5b672793683b97fbb539b15dc99c104add50b351c214d2dc79dc4e58fe4b16e4f7b995b537950bf39ff998fde4a1547af4ebe259e16e858f5	1	0	\\x000000010000000000800003b7cf51684d8cf161fb2fd8747568aa67c0b48c6dab935b4dd46959c7bb441a96d45fc8b65557c3a64c0b3ccf2f77e9a3d536de015eb3d1b2508a486ab6a3e0b0946826a9545b7cc09c1391a389d4ba4671185054b568b7ed8eec452e600ff0c534f07617d45ab181d47a1841e61a784fc8dba683de12eca6d94617b9e378f13d010001	\\x675a8622fc674349f59e86b01e23a72fdf57a3f25559a424e6145ca74380290a4086ed578405faf21a0e688d76e5f1bf68e5ea9fb1ae292149b60fe1c318b40f	1662289867000000	1662894667000000	1725966667000000	1820574667000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x9501597634378d1f2ad3171af88e2d909c99ff909d06e03fd8d8b638b34b1b6e	1	\\x95de2c8d8d584af667e3a66b91d0278d8f5fa810dff939501c5b0a707a6e93601f6982c42d31a16f72038aad89e7ebed1c7e78e5f31f94ec9f8631eb26bd2fa9	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xb65713724f4d8e1ac62efbe9ca84492fbf03b3dfe1c2cbee05236cf12cb83e1713977406c29475d037332f20fbbf54f11e302f3f5695416d8fbc84ec31f91420	1655640385000000	1655641283000000	1655641283000000	3	98000000	\\x59756ec3b15b5a54f816ab5b0440852501067e9d37ad2037fa0e61c1d6ff774b	\\x20fd8828c3440cc771f9ce2f19f72b19e3dc4a3a0d058fead4141fc1829e4e77	\\x162020ebd1048386539554bf0ae7876128e037b5f1c46346a354705e6ba271763bf2146add46addc81ea50e61d5431eec4012606b27d54a99bd49a5075aac403	\\x9bd85dc28e06af0b1bec2d0927025abed8ddd199cbcdcc41cfd996598cd4a83d	\\x10990c4fff7f00001d29349bf15500007da03f9bf1550000da9f3f9bf1550000c09f3f9bf1550000c49f3f9bf1550000b0233f9bf15500000000000000000000
\\x9501597634378d1f2ad3171af88e2d909c99ff909d06e03fd8d8b638b34b1b6e	2	\\x734b89a6fa655225e628975df6bda32fe724bab6bc7dcc9f5ae0dbe677453b4dab131bb277c040b3e5b4e3605371389f9cad7b0315a98c48f0914467bdc28113	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xb65713724f4d8e1ac62efbe9ca84492fbf03b3dfe1c2cbee05236cf12cb83e1713977406c29475d037332f20fbbf54f11e302f3f5695416d8fbc84ec31f91420	1655640392000000	1655641290000000	1655641290000000	6	99000000	\\xe577cc9b4807132edb0408b20d74b1b50e6d1ffd4fb6b332a7e5ce5bd7665dbf	\\x20fd8828c3440cc771f9ce2f19f72b19e3dc4a3a0d058fead4141fc1829e4e77	\\x8564c4f2463a851d487a8ae156efe67fe0b549d9c7a85268ec59035fcfa8dfbfb18633d04d4a495964bcb4aab42673ca8193349b719e06d4762b23066fcae00f	\\x9bd85dc28e06af0b1bec2d0927025abed8ddd199cbcdcc41cfd996598cd4a83d	\\x10990c4fff7f00001d29349bf15500009d60409bf1550000fa5f409bf1550000e05f409bf1550000e45f409bf155000090833f9bf15500000000000000000000
\\x9501597634378d1f2ad3171af88e2d909c99ff909d06e03fd8d8b638b34b1b6e	3	\\x051dde6d8850aa30ad3e18762851ebcc2fd8fb8e0b8984c04a8faf1a12d2162e1b855b80297792d4c6e2ed30262e9f5a9abba9f2e422c798d42503585a93d3bd	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xb65713724f4d8e1ac62efbe9ca84492fbf03b3dfe1c2cbee05236cf12cb83e1713977406c29475d037332f20fbbf54f11e302f3f5695416d8fbc84ec31f91420	1655640398000000	1655641296000000	1655641296000000	2	99000000	\\x084583bb8fb2f7f09c7329413ec6e45f03bedbed5ade5c4c5347b6deb3e21c67	\\x20fd8828c3440cc771f9ce2f19f72b19e3dc4a3a0d058fead4141fc1829e4e77	\\x704e4b2359901a534a87c51cf55eaa79ccd9aefdadbcd79b11b3030f4052c706961482094b6e7300e84f225e7d5e50d11708231afbf49e2320def6a5ab707403	\\x9bd85dc28e06af0b1bec2d0927025abed8ddd199cbcdcc41cfd996598cd4a83d	\\x10990c4fff7f00001d29349bf15500007da03f9bf1550000da9f3f9bf1550000c09f3f9bf1550000c49f3f9bf1550000e0853f9bf15500000000000000000000
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1655641283000000	358907221	\\x59756ec3b15b5a54f816ab5b0440852501067e9d37ad2037fa0e61c1d6ff774b	1
1655641290000000	358907221	\\xe577cc9b4807132edb0408b20d74b1b50e6d1ffd4fb6b332a7e5ce5bd7665dbf	2
1655641296000000	358907221	\\x084583bb8fb2f7f09c7329413ec6e45f03bedbed5ade5c4c5347b6deb3e21c67	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	358907221	\\x59756ec3b15b5a54f816ab5b0440852501067e9d37ad2037fa0e61c1d6ff774b	1	4	0	1655640383000000	1655640385000000	1655641283000000	1655641283000000	\\x20fd8828c3440cc771f9ce2f19f72b19e3dc4a3a0d058fead4141fc1829e4e77	\\x95de2c8d8d584af667e3a66b91d0278d8f5fa810dff939501c5b0a707a6e93601f6982c42d31a16f72038aad89e7ebed1c7e78e5f31f94ec9f8631eb26bd2fa9	\\xe39ca10cd50fb266bff9816211dd92ef083d51bdc3fcdbad4cfe300cfefc387fd7c82e5270c28a9048ca821bff59798e8a7704ea0b353fab135593ff49f4500a	\\xec515a94f4b41acf32dc6e3f3a8587a5	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
2	358907221	\\xe577cc9b4807132edb0408b20d74b1b50e6d1ffd4fb6b332a7e5ce5bd7665dbf	3	7	0	1655640390000000	1655640392000000	1655641290000000	1655641290000000	\\x20fd8828c3440cc771f9ce2f19f72b19e3dc4a3a0d058fead4141fc1829e4e77	\\x734b89a6fa655225e628975df6bda32fe724bab6bc7dcc9f5ae0dbe677453b4dab131bb277c040b3e5b4e3605371389f9cad7b0315a98c48f0914467bdc28113	\\xfc2b3ca2efe7d4bbb0854f4bbd61045e9477b53595b54ecdcbd7db283dc5df7e5b8b78c9b0159f60b6cccbf75d41a5add88e0fc22997627354c22829b3532a0b	\\xec515a94f4b41acf32dc6e3f3a8587a5	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
3	358907221	\\x084583bb8fb2f7f09c7329413ec6e45f03bedbed5ade5c4c5347b6deb3e21c67	6	3	0	1655640396000000	1655640398000000	1655641296000000	1655641296000000	\\x20fd8828c3440cc771f9ce2f19f72b19e3dc4a3a0d058fead4141fc1829e4e77	\\x051dde6d8850aa30ad3e18762851ebcc2fd8fb8e0b8984c04a8faf1a12d2162e1b855b80297792d4c6e2ed30262e9f5a9abba9f2e422c798d42503585a93d3bd	\\x67a6c98db10e90eaed8a7dc8b3e414f4537913a62ac34f34e7db8eb6abe0d847073f23bbd30485710382b9b7e88a987f0213933a1b82a54c0dafdbdfae359d0f	\\xec515a94f4b41acf32dc6e3f3a8587a5	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_for_matching_default (refund_deadline, merchant_pub, coin_pub, deposit_serial_id) FROM stdin;
1655641283000000	\\x20fd8828c3440cc771f9ce2f19f72b19e3dc4a3a0d058fead4141fc1829e4e77	\\x59756ec3b15b5a54f816ab5b0440852501067e9d37ad2037fa0e61c1d6ff774b	1
1655641290000000	\\x20fd8828c3440cc771f9ce2f19f72b19e3dc4a3a0d058fead4141fc1829e4e77	\\xe577cc9b4807132edb0408b20d74b1b50e6d1ffd4fb6b332a7e5ce5bd7665dbf	2
1655641296000000	\\x20fd8828c3440cc771f9ce2f19f72b19e3dc4a3a0d058fead4141fc1829e4e77	\\x084583bb8fb2f7f09c7329413ec6e45f03bedbed5ade5c4c5347b6deb3e21c67	3
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
1	contenttypes	0001_initial	2022-06-19 14:06:07.778114+02
2	auth	0001_initial	2022-06-19 14:06:07.909903+02
3	app	0001_initial	2022-06-19 14:06:08.00535+02
4	contenttypes	0002_remove_content_type_name	2022-06-19 14:06:08.024281+02
5	auth	0002_alter_permission_name_max_length	2022-06-19 14:06:08.037325+02
6	auth	0003_alter_user_email_max_length	2022-06-19 14:06:08.049206+02
7	auth	0004_alter_user_username_opts	2022-06-19 14:06:08.058824+02
8	auth	0005_alter_user_last_login_null	2022-06-19 14:06:08.068975+02
9	auth	0006_require_contenttypes_0002	2022-06-19 14:06:08.071941+02
10	auth	0007_alter_validators_add_error_messages	2022-06-19 14:06:08.081588+02
11	auth	0008_alter_user_username_max_length	2022-06-19 14:06:08.097021+02
12	auth	0009_alter_user_last_name_max_length	2022-06-19 14:06:08.107046+02
13	auth	0010_alter_group_name_max_length	2022-06-19 14:06:08.120467+02
14	auth	0011_update_proxy_permissions	2022-06-19 14:06:08.132188+02
15	auth	0012_alter_user_first_name_max_length	2022-06-19 14:06:08.143816+02
16	sessions	0001_initial	2022-06-19 14:06:08.169546+02
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
1	\\x210afbe5bb8866a19b5f295d9430d7a339863561dce1431c9d4566f782f5fee5	\\xb8911b7845d5c0606d43ad5eedc780344aee4fd936606cd6a9fd1ad59d957c431412a3ea4b3efda88a9df7c6b3db77a19011bc77416ca283ae7ce63b9005cb08	1670154967000000	1677412567000000	1679831767000000
2	\\xac28b75d81c040fe21b06acfed1f8b69594927091442d4478788836452d57995	\\xca8520d51f7775304c53618ed83a04deb35d42b82bc901b3a8d5ea868c4b78c55ef7611b6bb863880583d6d8feef44e2a9a3130acd8a75882d1b2e14b2e0a302	1677412267000000	1684669867000000	1687089067000000
3	\\x71a5e021472ae50c77dbb8fb43bcc2c3fecd526c3f0f8ada5d982e4d09199939	\\xccff7779ad74e8a010cdb28fe958a27b915693729b0991f6a3680895fe1e7141bfd5d91da1d470ac801403d51640d31814db2d2a39fb98181c83212019bf9908	1662897667000000	1670155267000000	1672574467000000
4	\\x9bd85dc28e06af0b1bec2d0927025abed8ddd199cbcdcc41cfd996598cd4a83d	\\xf94cdd1c684c1e6a736bb5c5aaec3d5c4f60310ce02f2702e35de62f9297a9d623bc474fb42bf174eba9a0938594151bd7cbc5bfc4b70987a2dcdd8cb0c29a08	1655640367000000	1662897967000000	1665317167000000
5	\\x1ef93e3311ab00c04940af7425f0487670114350f7e6f0ddc67f2bc0f5b2c11a	\\x480f176c9458e5ea1bc106c88bc41ea49cb33fb92e5be554f7fd080a7c99dd6c29a131e800fcfd072bec3ad3499f449a9806eb5c1c9d8ad65e3eda1bd774080f	1684669567000000	1691927167000000	1694346367000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\x31b9a57344ca4526d135d52315d9f7dd51fe9933584540738c8ce32ff0486d0ce1560ed830c0f28ca4abf9d0aa99a4d5373a423b0a429b660e4e857989b8880e
\.


--
-- Data for Name: history_requests_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.history_requests_default (history_request_serial_id, reserve_pub, request_timestamp, reserve_sig, history_fee_val, history_fee_frac) FROM stdin;
\.


--
-- Data for Name: known_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins_default (known_coin_id, denominations_serial, coin_pub, age_commitment_hash, denom_sig, remaining_val, remaining_frac) FROM stdin;
1	208	\\x59756ec3b15b5a54f816ab5b0440852501067e9d37ad2037fa0e61c1d6ff774b	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000074b9c8513bbba52f0ed6226fa1d35264bc5acfaff159c63e9dda2d9a84b611d8bad0876bc0701adcd91f176ec213e937912c30f730f8e7d027410e4db719b6eaa43fc6f5cddb67260750d93bf42f5203beed6c03e9e8d43707aab10793db0e9f7cbff0c07d906754792f671076ef35a86595d88a77e2b139dd3b3ae4cb598b38	0	0
3	276	\\xe577cc9b4807132edb0408b20d74b1b50e6d1ffd4fb6b332a7e5ce5bd7665dbf	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000073ecba6d95f0c449741905187de4ec660bc15ffc0bac5d010e994e27adb1dab89b5bc206128705ed77f32f4543d735f318c319429a8761bf1f5c53bf5b01a1a94b6014a2f189cc784f6cd8b76ac6b2d879ff0207ebdf7a50434294a92de999add68c3d2a116f1339c9378bfac72db26ef19b8b6fbe89d66f27935c1f0519b330	0	1000000
6	248	\\x084583bb8fb2f7f09c7329413ec6e45f03bedbed5ade5c4c5347b6deb3e21c67	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000815e71d37c316e9e277d65498b2504e4474cda5d4a56140464749242f53d1b3a8e2b715b2e3b66253c47db983da05b3ca50606bee8898a1cb0e78c5154c1dc3376d0fb832394fb491ce7ea04dde7a96e74992f33619468f45ed3f411503f26e10e629450c89007e0e89264c88d479a891f0e8c6b543ce356f069989330d6b509	0	1000000
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\xb65713724f4d8e1ac62efbe9ca84492fbf03b3dfe1c2cbee05236cf12cb83e1713977406c29475d037332f20fbbf54f11e302f3f5695416d8fbc84ec31f91420	\\xec515a94f4b41acf32dc6e3f3a8587a5	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.170-0345FDM7WCNXP	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313635353634313238337d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635353634313238337d2c2270726f6475637473223a5b5d2c22685f77697265223a225053424836574a46395037314e4848455a464d574e31323935595a473743595a57373143515647353444504632423552375242483735564d30563139385845473657534a59383756515841463237484735575a4e44354131445037565331374336375748383830222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3137302d3033343546444d3757434e5850222c2274696d657374616d70223a7b22745f73223a313635353634303338332c22745f6d73223a313635353634303338333030307d2c227061795f646561646c696e65223a7b22745f73223a313635353634333938332c22745f6d73223a313635353634333938333030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224a4d304e4a58484d365936485941504b32574446483348444a3245394b5a57474b4d334530465952563256334843544233445130227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2234335952474136333847364345574653535251484b58534233374858524a4854314d32525a54504d3247465733304d5939535647222c226e6f6e6365223a225a4e30545954305452393834584336313657303638424b30444a38514548474832514237343850394143434643444e5a57504730227d	\\x95de2c8d8d584af667e3a66b91d0278d8f5fa810dff939501c5b0a707a6e93601f6982c42d31a16f72038aad89e7ebed1c7e78e5f31f94ec9f8631eb26bd2fa9	1655640383000000	1655643983000000	1655641283000000	t	f	taler://fulfillment-success/thx		\\x6cdca09da86013a7add5ce8b8c954858
2	1	2022.170-03E9CXP2DN5KP	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313635353634313239307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635353634313239307d2c2270726f6475637473223a5b5d2c22685f77697265223a225053424836574a46395037314e4848455a464d574e31323935595a473743595a57373143515647353444504632423552375242483735564d30563139385845473657534a59383756515841463237484735575a4e44354131445037565331374336375748383830222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3137302d3033453943585032444e354b50222c2274696d657374616d70223a7b22745f73223a313635353634303339302c22745f6d73223a313635353634303339303030307d2c227061795f646561646c696e65223a7b22745f73223a313635353634333939302c22745f6d73223a313635353634333939303030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224a4d304e4a58484d365936485941504b32574446483348444a3245394b5a57474b4d334530465952563256334843544233445130227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2234335952474136333847364345574653535251484b58534233374858524a4854314d32525a54504d3247465733304d5939535647222c226e6f6e6365223a223238344d3946474d4e54345158313756524451465a32413135505a4a56374548424a3950524a3354443552513952465645475847227d	\\x734b89a6fa655225e628975df6bda32fe724bab6bc7dcc9f5ae0dbe677453b4dab131bb277c040b3e5b4e3605371389f9cad7b0315a98c48f0914467bdc28113	1655640390000000	1655643990000000	1655641290000000	t	f	taler://fulfillment-success/thx		\\xff36f5efa9cb2b8aed6122e9c1cf795e
3	1	2022.170-03MA3XHVY98FP	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313635353634313239367d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635353634313239367d2c2270726f6475637473223a5b5d2c22685f77697265223a225053424836574a46395037314e4848455a464d574e31323935595a473743595a57373143515647353444504632423552375242483735564d30563139385845473657534a59383756515841463237484735575a4e44354131445037565331374336375748383830222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3137302d30334d41335848565939384650222c2274696d657374616d70223a7b22745f73223a313635353634303339362c22745f6d73223a313635353634303339363030307d2c227061795f646561646c696e65223a7b22745f73223a313635353634333939362c22745f6d73223a313635353634333939363030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224a4d304e4a58484d365936485941504b32574446483348444a3245394b5a57474b4d334530465952563256334843544233445130227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2234335952474136333847364345574653535251484b58534233374858524a4854314d32525a54504d3247465733304d5939535647222c226e6f6e6365223a224633384541314d364e593531394148483338543347354359544132515a464252525257484736445a335233523432585658365730227d	\\x051dde6d8850aa30ad3e18762851ebcc2fd8fb8e0b8984c04a8faf1a12d2162e1b855b80297792d4c6e2ed30262e9f5a9abba9f2e422c798d42503585a93d3bd	1655640396000000	1655643996000000	1655641296000000	t	f	taler://fulfillment-success/thx		\\x2c01ff4b336c21ea3d9396e46011eabd
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
1	1	1655640385000000	\\x59756ec3b15b5a54f816ab5b0440852501067e9d37ad2037fa0e61c1d6ff774b	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	4	\\x162020ebd1048386539554bf0ae7876128e037b5f1c46346a354705e6ba271763bf2146add46addc81ea50e61d5431eec4012606b27d54a99bd49a5075aac403	1
2	2	1655640392000000	\\xe577cc9b4807132edb0408b20d74b1b50e6d1ffd4fb6b332a7e5ce5bd7665dbf	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	4	\\x8564c4f2463a851d487a8ae156efe67fe0b549d9c7a85268ec59035fcfa8dfbfb18633d04d4a495964bcb4aab42673ca8193349b719e06d4762b23066fcae00f	1
3	3	1655640398000000	\\x084583bb8fb2f7f09c7329413ec6e45f03bedbed5ade5c4c5347b6deb3e21c67	http://localhost:8081/	3	0	0	1000000	0	1000000	0	1000000	4	\\x704e4b2359901a534a87c51cf55eaa79ccd9aefdadbcd79b11b3030f4052c706961482094b6e7300e84f225e7d5e50d11708231afbf49e2320def6a5ab707403	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x9501597634378d1f2ad3171af88e2d909c99ff909d06e03fd8d8b638b34b1b6e	\\x210afbe5bb8866a19b5f295d9430d7a339863561dce1431c9d4566f782f5fee5	1670154967000000	1677412567000000	1679831767000000	\\xb8911b7845d5c0606d43ad5eedc780344aee4fd936606cd6a9fd1ad59d957c431412a3ea4b3efda88a9df7c6b3db77a19011bc77416ca283ae7ce63b9005cb08
2	\\x9501597634378d1f2ad3171af88e2d909c99ff909d06e03fd8d8b638b34b1b6e	\\xac28b75d81c040fe21b06acfed1f8b69594927091442d4478788836452d57995	1677412267000000	1684669867000000	1687089067000000	\\xca8520d51f7775304c53618ed83a04deb35d42b82bc901b3a8d5ea868c4b78c55ef7611b6bb863880583d6d8feef44e2a9a3130acd8a75882d1b2e14b2e0a302
3	\\x9501597634378d1f2ad3171af88e2d909c99ff909d06e03fd8d8b638b34b1b6e	\\x71a5e021472ae50c77dbb8fb43bcc2c3fecd526c3f0f8ada5d982e4d09199939	1662897667000000	1670155267000000	1672574467000000	\\xccff7779ad74e8a010cdb28fe958a27b915693729b0991f6a3680895fe1e7141bfd5d91da1d470ac801403d51640d31814db2d2a39fb98181c83212019bf9908
4	\\x9501597634378d1f2ad3171af88e2d909c99ff909d06e03fd8d8b638b34b1b6e	\\x9bd85dc28e06af0b1bec2d0927025abed8ddd199cbcdcc41cfd996598cd4a83d	1655640367000000	1662897967000000	1665317167000000	\\xf94cdd1c684c1e6a736bb5c5aaec3d5c4f60310ce02f2702e35de62f9297a9d623bc474fb42bf174eba9a0938594151bd7cbc5bfc4b70987a2dcdd8cb0c29a08
5	\\x9501597634378d1f2ad3171af88e2d909c99ff909d06e03fd8d8b638b34b1b6e	\\x1ef93e3311ab00c04940af7425f0487670114350f7e6f0ddc67f2bc0f5b2c11a	1684669567000000	1691927167000000	1694346367000000	\\x480f176c9458e5ea1bc106c88bc41ea49cb33fb92e5be554f7fd080a7c99dd6c29a131e800fcfd072bec3ad3499f449a9806eb5c1c9d8ad65e3eda1bd774080f
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\x9501597634378d1f2ad3171af88e2d909c99ff909d06e03fd8d8b638b34b1b6e	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x272066002ec5e5b2ead4170a9725486d79cd121990451d0eed8c37b9f0ccc296960affd10de255286930dac890a321aceb167df1ee8c77b5138773e07a3b8a09
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay, website, email, logo) FROM stdin;
1	\\x20fd8828c3440cc771f9ce2f19f72b19e3dc4a3a0d058fead4141fc1829e4e77	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000	\N	\N	\N
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
\\x68387e39384f371dd3761afc47422d5314c9abcdf94a0ac24847e80c8b4e5459	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1655640385000000	f	\N	\N	2	1	http://localhost:8081/
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
1	\\x3505e69731a66b6f6c12665792abecb96ad8f69e524bcfe460f3d5c3c3862f8150804f3fa10437a0ef96e1c606222623f73563359751fa9ea74ae9061071a10b	4
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1655640393000000	\\xe577cc9b4807132edb0408b20d74b1b50e6d1ffd4fb6b332a7e5ce5bd7665dbf	test refund	6	0
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

COPY public.partners (partner_serial_id, partner_master_pub, start_date, end_date, next_wad, wad_frequency, wad_fee_val, wad_fee_frac, master_sig, partner_base_url) FROM stdin;
\.


--
-- Data for Name: prewire_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.prewire_default (prewire_uuid, wire_method, finished, failed, buf) FROM stdin;
\.


--
-- Data for Name: purse_actions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.purse_actions (purse_pub, action_date, partner_serial_id) FROM stdin;
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
-- Data for Name: purse_refunds_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.purse_refunds_default (purse_refunds_serial_id, purse_pub) FROM stdin;
\.


--
-- Data for Name: purse_requests_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.purse_requests_default (purse_requests_serial_id, purse_pub, merge_pub, purse_creation, purse_expiration, h_contract_terms, age_limit, flags, refunded, finished, in_reserve_quota, amount_with_fee_val, amount_with_fee_frac, purse_fee_val, purse_fee_frac, balance_val, balance_frac, purse_sig) FROM stdin;
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
1	\\x4655f04cc16666410f93bf35b6606ac3870cd6540972ad000f17bd49174892d1371b6567c766497085634eafdaa755bb707bb1579b78886b3f99843e206ba007	\\x59756ec3b15b5a54f816ab5b0440852501067e9d37ad2037fa0e61c1d6ff774b	\\xfdf15c29135df0f060e76978b430b90e77385f053a62a13b485c281ad43b09b99358429595970f407f817f18ed02dfb1322ece790c5bfa66d1839cc10a87500e	4	0	1
2	\\xeba9cd52e1d82d98419110732b918e8adc9cb5029ea4d217bffd6735c4736c22635b232a5559a47ab6fb7dd1fe06c508cc585707139566cacdd458352a0b1470	\\xe577cc9b4807132edb0408b20d74b1b50e6d1ffd4fb6b332a7e5ce5bd7665dbf	\\xc0758993a761cb6c180061cbdcb3310511822fa2764ac71d63bb4fa076e3a214272c09f62496f56652436f1a394e1511e29eec3655601fd441ccac4170baf705	3	0	1
3	\\xd063041939a7f4080c0c780ed34660ab68a0ab43390298d0c3b0d288c9aada048d6bfe8e0bb94c42fded5561b57662c924df94a7ca1f3635edd4c6fca24ad6fe	\\xe577cc9b4807132edb0408b20d74b1b50e6d1ffd4fb6b332a7e5ce5bd7665dbf	\\xd543331f5a7b0de9456ac7efeb5cb7f03afbc3244e59ca80a1d2e25bf458d0249155ee865cf885249b5ef8ced40fa3e40962d54d6c7773d0e933ce810e4e7c07	5	98000000	1
4	\\x6ee59c008971a38230f1e6535af3a871169d3ee47efdc0b92fb303543297caaa20f34eb9681436ce917c5466b2893c548f94d1ab46d41dc8044d89e18a8ec61d	\\x084583bb8fb2f7f09c7329413ec6e45f03bedbed5ade5c4c5347b6deb3e21c67	\\xedfb55a5e872fa519e3bbb6e54966afdef3a6312eb503252cad859cead8ddf91f5f88283186fd1e009ee32a6452fdd9b378b8b393737b8f26ccc3ac848d04c05	1	99000000	0
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\xd445fa88afc20a9f90ac2a31aeaee92a056a14146530f54059e6221738708113074ce2d87dc2a82efa7def48d33216a01b0a5c93ae31105eb943e7d5e7a1ae0b	423	\\x000000010000010052bdffc0c10571b8986683fcefc9fa44b034ebc70bb6780f8e7aea61387a1db78f6f611a105b1cc0ce4656d9e60da0387dc33fc540be85e335410523b05dd06090009ef66ad3c5ed7753ab10ce0a86c402bd6babbf0c59f27cdfb4fb3cc65b8960e040e71085587603ca39cdbf8ab96328d0385b84d47066a0929ca264d5de0b	\\xbbe9fa5c5586eb0469dc503efc8d912543b5c1b41a0eeab4d6c9d7595438ae6002b2275883696ff75123b88e32747e08b8efa7c3a0344cf98c9314c49596acf4	\\x000000010000000159376c75a8f46081e62644013a61490e2b64608d4e2901c25c1b491701e46b6812c178883828e68e248c2166ab419d360e0bd665256c61d9a4c848636631e9fc95690f544697f9de205140e8b747bf8be3b729a80ad4c68ebf68757299f32b068ecae2d76f81af533e7f4da4775432465f94b3cda506413a6dfe54db711bf57e	\\x0000000100010000
2	1	1	\\x89b67681083751ec4295ed9cd4c0d36ea4af26af2071d30fd36598a1fdd5035a25f6d33d2224867a9baf6f6e13313e0373aecb1390763c6fecabca790d39f80e	48	\\x0000000100000100a09d2b1f85e8d9d4394e124d1861d57cd5188adc53470fcf4b8aa3a069fbf400b42acf514242b00a5a1f4fdcd2513c1b747e07a8f08318e386bc112d3218a049b86afb22f06502231aa10f30ffe93e756208af09d9ac766e87133f75c253f74209bad69f31d8f158b853dacb4b2dc08df7f8beb3d4c50f8318b2c62b42eda212	\\x4c03f101a17040ca0e9bd70ea94859d89fd427266ca3ba6d1ad5376afde4b93a7ced83688f017e8c68fd9d31f3d6da5675781789f06be659318e0580c811bee5	\\x000000010000000105a1b40d25de41c89a5352bab8f771975e13a578561d45c5d796ca7e91c6b2f84a4ab1d4d27b7df43f0a82cb1c68c908072e750bba1b5aec8781607c76ca367b58bc49d6772d5b1e46d7d7f365610eb04bf4e93bd75dcc321937b00e06678af1a9de9fb18818fa259c66aa82d97c80b75f0ee41b9615f5be26e93d1940dfea66	\\x0000000100010000
3	1	2	\\x62026d6fc0c0fe422cb690b44ac9dee4e66619ab8fac03fbc36f41bf9934d886c99c3c7e5bb43fc11e49ab77a90f1993d85eb2e3bdca82e37409657d48062b07	178	\\x0000000100000100651db7d747403645224801972617c9a71e711bb77a8f2853d31ac554998888ce3cc6a115e1cb6a2a0d5b58bedfb2c76a0ca007adfcb60502bba8ffe0d5dac400bad9f19916229e5a6c6ec6dcd5b28738c8da68bb66dc552a0c84d28cbb2e66da1bb5142a1a210d63d73dcb1048a2b4ff467ba074adbab1e710fb6dfbdb956a4e	\\x7f2a34b4498443effb1a923be1e2fa1350c5553bffe2ebdbd6eca2449262841981c8f870720f27d002d35b5ea79381f3e52da4679abf7583f87b90bcbea4b31b	\\x000000010000000161878697cd53e14dc7107dba562d2bc83349f023c2406852681346e6105b5317a17652e0ddaff2f449e48bd4b8b536a5c93ba664e7caf872ce239020adebf740cc9d36e2fd1efa221e4f980a2a6a7f7ebe44d07b92645b7c5967b3ad7185f4814700501e54d92a4fbba165bd10a0be4b29863ee0fe087645c269f72706ba5949	\\x0000000100010000
4	1	3	\\x92f00c49067fb1e9ca4eed70cf460647b951d0b74ddbf96753a498205d4925e4c7768ae808ae99a41e281156508bd5232707dbb2c33a17a2ccf6344440734901	178	\\x0000000100000100848785e17d2f2f211f2f958fdbb08acb8925d6ce615362abdd97015709ca4d0ff64efea284ecde9565fb5378cfc59706b6d896b8658106e829ff082ea5a930acd52ab8eb454f3512dbe1270f423ef59842894a5e914fd1d511c1721e15f635ac8e26568591ac6aabfcebea7fce9a9fcb33b9ecde08f1790396b9e5823bc718f3	\\xe3dc47b1699757c2a6dfd4deccb059ddb6f0574b9556c406ad2bd9dda89cef3d60ee38727db78cc8fe1877ca630d0938ad10817d894b832b2212ed3ce1d698ae	\\x0000000100000001b8af90c561c9d95a19c38e7f4799a64575949877b44fdd193dd1bcf8ef5d9a82c0cf8d7023d79e8f6693de85af34f72fbcc73996de6eb3c632f1d67e742b5a2d33bd8d4a1709aaae3e7786c34f856f25f8b16191fb36bd944331a183b66391a91f73d37213e3840c734b602d0b6940edf2cd9864ce498ed0d00ca8940cee3eba	\\x0000000100010000
5	1	4	\\x66ff42d094120d951d0becba6c69153657d52c4a217b12760cc5d2c04e913cdab8ba72d8821e5c8c9c01d7d26cd922bd822623fd745f958559acbc42948d810b	178	\\x000000010000010025965f0b49df3d15fd402d395c391b197bb6f1810b16f316cfdbecb12c6084f9ed2fa0d4e9a77e760d79b374fe2cfb37e6f680c68c775d1fd91a9ec92926be018dd2bf8d21d977161efb9b0fcef559864a45640be1ab304ec0e02c5df7fe195cd61b1cc186eac7dd569509736f2570c20119f29448b41de1b0c9ca32590506de	\\xac8bc40d6934bf269c42cfb022a9b128b1dd36557aafa6a0be7a44159b48038b9e2070bc8122ebca2e64bc1b68c02062a25d188eed2ca8996af0a857f0cc8353	\\x00000001000000010ba9a44771ab9ef2ce8643af6707d24444abe63d44149919281c034f8b64db9d235b48758ea0c04bcfd470f610123130a4e61ae0248aaa986efb204cd4c6b17f883f5319ee229bc378d2bfbded988f1ef39fdab65bbfe87e4fb3de4b7294e46f6cd521c2acadde47cf61afabfcaeee16660e3ffc883aa071ab8279a96787462d	\\x0000000100010000
6	1	5	\\x198913cb54490c331d6c3dbddc5509fd96116cc005016097ef840750f41697533ffc0697a0b2a61689f5a3113778825394e823323c95acbbd54ef34d951caa0d	178	\\x000000010000010080ee86c44113370835b24d7d00175ac3e83d66bd2f31154d8fe0a79868a4d54308668616e88f7a713c91fb691b51129846bf11d54b0992e6110b980015c9d99035b78bb1f536424207b4e16ef60d5f049513dd9fa4aa2648f85a64a2a77c79ddee782fb13a3b221ddb66d9e1c7ff080d6df06ce4ad00c42f760a4bada6fb9b0b	\\x717a9a8bb945410b530a80e4437a70b9d88e106d54de34f28ee793498a95f227c6992efdb0eef29506ffd54d05b9468e46c0dc1e53abc54882adbee0afc817c7	\\x00000001000000019eebfd210894331a2a880d0a2ddce26f6a1811140f928a44b6c2ea51c757ae98ea120e8b6b8acd60c87fdd45b49a00e58c41ac6523d9211f4fac97c32ad92cccaddeb5491a465a53b4d17b856ff12b0e291efc8ee5b25bccd51c7b960b809ad28814632a96cb574fca77af5ac8ecf8fb8fc30d06b25d4f4648b6100b27e3421e	\\x0000000100010000
7	1	6	\\x637170acfae29f14847704631a49573409150256255f856d7b2b741dd8651ca421680133dcdeabf819db8cbf1eb700608bdbc36b632c7c20db96ba085c504307	178	\\x00000001000001001e1d8568143696600cfef3c4bceab2c6ca9a99e7615a128404080a772b5f14e64109ab9def046d87a8e786115f00514c9144fa437e92e508f5a513552f744d562e624d99079641a6e93a6571b14423a47fa936e150ec9427113449c7abcba63cb32717d2fbd33025111b7106eb8e2a653978d08ac76c0b5288145317ba2adcaf	\\xd1f6d982d2e2ed973ebf838a88fdd3c8505c4e8a8a469d1072d1f9d7be4b8d60558aac1bc137059749ee1eaadef14c9d6eb5283611ff07b8411fb442fed5ec19	\\x00000001000000016004134afd635124fb22156ee2e191ff104b264af3d52965b7f308bb21a512942fbebc6885c38d034fb5e938857009edc4a36f7e9debaf38169cace6eb52938268d3a3f05111ecb936d509932971120d390d2cf22e7de8ab3d3c0b3bc4b930ee39e87a9142c36589b2c830a7a4b404679e9f4d98f42b8ebc23caae9e4fcae4c3	\\x0000000100010000
8	1	7	\\x5af1ea3cf3480f4b4fc86adf6e65d87551aeeff179a4dab7d3402485fba5b7d78387ebc246fc4052f1f6a2d8bd8717afcd5dae65c26dfd301877723257eeda04	178	\\x0000000100000100a559952cf51b6f964d62bfb9c4d3b00f2560dcaba5e1fb837c2b630aefd802401db9b814396511468a40a90ec0b693707f3128bab45e5c46bacc975fbe7fb613cd8e664145fab09b9f9f43229ab5ebbe4eb8b6071e7c124f481ae7703044b869ed8c37610fcdd2c9ce3445aecb497fe81246b33f4dde32982f29dfa73fa372b7	\\x8809f4cb4370d3a2b5c17f79ca41ac415b543e6afff818f01138fb0f1a5062ea22ece6426f9aefdf7dab23d1120a22679b981415373a303996d20fb2ca51df81	\\x0000000100000001081d5a4b9884d2cf1d0b3868a3cbcfc8063541ddba1eaef0f91f2a7c4f94e4c2868bdffb630c4b6a198430ff7ddb3fffc0d49600d06d1bbb3c8b9ae44327bb58a7b125b8e87f441ea10491d9eefe1425de7fda9a44f07104561d50707d40d5e967d1c7f06f55e9df38ee66813fb79a86bc69dcd6638ad81ae8c05d76f4972069	\\x0000000100010000
9	1	8	\\x27311115ee41d7bc99ceaf07c545c539c0ae3196367531d972dfbae5358bca7402131ecd2b169025594c9bbf91325620d05b22c50d73fc50f02c881d95299d0d	178	\\x000000010000010039f3eba33bdb8473f5f7c95a33d4d31b0d05edfa80999b716e1ebaaa1dd5c7798a650c49938872fefaf4cbb558f1500fca9ede6eace27df7a14eac7534c50cf43efd8e25e30540f0762f60299eb3312a4b613f2765bf4d59f1d1a1df7e9c29424d5e00b92ae17e3c5f235ff21c46c0ac7004abf47a0706ac375638acfb247274	\\xa7b49ee0ca2e0ed377a2d66005c8589214e62bfd855107116d66052f69b7a3cd852a0ef4671a1f06b7df396d8417776e5e00ffcd1dbc72214167dba4d549fdda	\\x000000010000000183179c4a7e83c623f799bc65797838c636300a7a751dad2fd689a06a1feae49fea7b1d2030c83eb3f6a9cea16375965a03c71bb3a5b2bba5255612f327ae91e6e298673d3b31673fb848084776ae17f5e8c3adc293869e67a3900bf0aa46e078789be4b5ca140611829d0344dab31b44423a3ecb39d1adaa7a5f0ef38156fe76	\\x0000000100010000
10	1	9	\\x169aeda1840f1a495b457f11365691fd9201e867c7c9f1fbdb686fb79aaaddc44a179bfc4b1d75527217ff66f7e353576343976583cbc1ae80d1b0ef92d09404	178	\\x00000001000001002f2d859291089e18f36f0ec514e2729d7fad3d29df8c9dd8b413da9e4fb6065b45c4776be58220ef410ab4e0eaab8fbc545cd98a28bdfd9d23ec88afaf5044d5f7272a7ed60d8a6a9a567cb92dce2d7e21cbcf2841017f44571cfc6a09bf928027262312eb3625e756ca98408e189d6206ca35152768e3ac290a2e5997c93ad0	\\x144001dc0e5eec7c7d81a2cece7fc2dd2e5cfa53639163cb441ebb83d2a8e9e7cdeac2ee75d5a7393edfee3ac80d3175099341c9adf73e67b9f284f45de8a17f	\\x00000001000000014b1f848e953f589874cc21cd9950117b7a5ea838161fd8a8cb13df23e24a87ee17d84761c8da55837b277c738b3bd9083212e03fad905fa4c92a23be7da56c67ac001f22683a118f9c70b60db5ec6f04c812bd605b9d9d62d6ca5288cbcd53e6fe04345d61d9ea1bc7d793f5f0a128cae9fa06aa013d789f729f323bb4611611	\\x0000000100010000
11	1	10	\\xb58824cf443b3650aa22e0dc80ec12265294878afca43d973988e882c1ea8f4a8c286ce3466f85144a3d62aaa9a0a60f5ca347cf0a076dfe7272ce97b7888c09	374	\\x0000000100000100f0bb954df030d98e0a7a051d1d4b59a879b34c75a5ce0f906f90cb6fb8558bb104a64c2e9612e5966d2cb3362aebfbdecca796ce97b118254533451b4b7f9de7b48e2f6ab6cd7a74337275054d0bd559472156749d5d9ad5590b4c491348bcf1a6a207bb7c1ca67c55f3dbbdb7d73f477010192ab8abf470e857e7de68ffa4f9	\\x95bb014f8fc80c38e15ea54df8107215dbab39d5643eccdd14b9fbfa55e56a921d979d3def467e182068818698dc76fa6ff9b498aa4568db0c108383419d26b7	\\x000000010000000125bb48cad7a98f1802d5537af8da5901e40c0a16ac6be4e9b24d9bfcc24bb579f79d329d879ee62502a20e48d4af209fe0ee58efb0af09427ef901cc0e38e1705c0f15f0f6e032fca6a7d536e5cfdffea6b7eb6c58205795bdaf5835286853766ed2010104d2f50deb6348e44f0f33f560f1d270daa49a412565ab3574f7904d	\\x0000000100010000
12	1	11	\\x025ccb1a6c928a3c4a235bddadf5cc9d06410f9c21d01ccda6a51b813a86b8a5523c867d2cdbf0d32a7e36ba85d72a200152e6b8e00a24d38070ba8b5b0e8802	374	\\x0000000100000100579eb205c07d0bcdf6c799e69e2b344bc585caf309503f09d8819279f2080602fd5eb70e01d0019546577c5c9ad16ac5975c679fd9f352d3aa4bfcae8e2d78aba86e79bfc12bcb5161ab382108c99ce56f8b34ae86abbc573cd6d6a739594f5550ffe27dd96b27483c6930dee2c4cdfb3d45278f8668e0095f347798e6935a6c	\\x2e5fcd98babac79a07a81a5e4083c97b3360c8cbfa871ae5120d15e3505161874d9d3eb8d48180bef1dc17d8190359ff89efc9516d7ea859042e69e20a2cdf30	\\x0000000100000001692b7c48082b7eccd4002f5c0e2d20330b7525bf5d94d3479fc2afce4aa216f7a8e604dd1f96463e74c43efc2d9865fc3cd93965c8294edb8506ceddebd0fc678ce010f237bdb0939538e7fd4e7daf7b80824bcb6dacd122ca861c8e6dcec56d1bc85dac7171f44516221170afe38297fe2f352b27c11db20aaff992e66862c1	\\x0000000100010000
13	2	0	\\x5f67d7e422bf49cbf017556ca0a591764af8503e2ac74a7bdae692b9b7416d2c8a7c3672e43af5059ea6aaf95e673d66d3cdba3a17b2be3fba98ceb38e86dd01	423	\\x00000001000001000b035c54882ead471c3ec97ee07d42eba73221b870f199fcd434584c44fb3bb9060984f0e111c2fd836a263b2528736c6e744d6ea2a448c0355b8140a0cdf92850cc22a5359225490d14cc8e7dfb8ef73ddf2b4e3e12039efe63dfd31e134d0abc77f182fa4c542756206aa25fdaa33233404b313a83aa472261e1b8d6a4ae37	\\xa1f310984e326de6e06782d5d8c81f066f118cc2f27213807ed9159b288366e8ae440a8156f9535ac07d73a7e7889f8c007098acde97d50da2d0a545c11ee98e	\\x0000000100000001960e40ca86b0202f689d801cf6663691953c698675554dbbb70e983d9f0ac6d889092be2f436a3e433a044cbf3a45e19694c73ba65c7f0c809ff133733db40874fc8e3e4e964583543980bdd18088af8abbece2eb37cd40d9ae9b3d25bb8b74b57448e214d15631dc6536094016ecc4b90292e0f27c2fcaeb008d10acb2be062	\\x0000000100010000
14	2	1	\\x8927d3826cd3dce9770366f52f39c254cbbd3b8bfa61a09868dea4c16b854a7bee14c5f8bf08f7bbbc0a9d2dbbeddb9f74bf1bc25fab508ffd518cecdcf36509	178	\\x000000010000010038cfed045bea46e5e029a5ce60cb42069d046ed58a063fd74e605f1092fee6db47dab2e6e1cfb807c4bedbf972d32dcb007486ef3e61318c898665eb9cbc808070e710b699c8552fa509fb2c2a3c34cf61da61321f327699aba46dcc437fce050fbd1684d425d683debf1d0dd60ae58777e53ef29f47e7f957f4fb77826aff3d	\\x5a9429e3beea68ddab36d02e36962f16f3b0af118f0c9a9868fa16b4a80cfe463f7967a746e031222fe80774749cff8afeaa003b179a9c0777a333280e86f7ab	\\x00000001000000015ad5ce16380108fd078a5a483791a3986649bd9859d9a2ac8ad7a322eb3487a133c4e405a02f0ac157b1bb000a37098842a3af5df796889dc7068c290d397698e456d0f5bda1c81b75568976fe0b5c1894325a6f0737b5dd6e692e933aaa8f352d7d1b66cc8330c317d731dc0fcb8fd716d48f71d8db24459e910eb924291ad3	\\x0000000100010000
15	2	2	\\xefafc9858fbec39fcd52f384c90cd109c99005728f59c11eb8c1c09e5072f517137f60ca7fa08f06c5409ba8bc1c6d29756c33e88300ff86459f0915872cf00e	178	\\x0000000100000100469a84509778fe928cb894002e123ff08613a955bcb46cf60d7008c5972e1cc4b0e91541406758240f2dfdaad2f3cfd1e10b422864f5fd1b26019d7bc457407bfa4bcb1ffa48caad7de9398ba2237defdb239f5f639d99c4f619fdaf921c2b693c1ca41fb0fe8e4f965af989c7dff53f3b671c3f882ab2c75a052a41e9e7339d	\\x6df31843a74bb2ed3d4135b35c28811ab98ea8298f3e81a93906b71a4bccba3d63458828e571454eeac885d6e76cb25b0b6eded0a7a138a37c88204b27cd00a9	\\x000000010000000119ed74461914b2d0681af07e9a37075833ff8b426fa51e9241aafe6e707406b9120e2909bdc96f271631332b414d96f3aad496d17aad13c8c0654fac66af2eb2104cd2e4e17ed4bf70aafdaaa0a4f68f4bc6dd18a7940e85bba9ce947155b76919d93920d02d0fc72ebdc9b5cbaf612df5cac6d7a58d4926ecbe9b2aed86d9d9	\\x0000000100010000
16	2	3	\\xaf28eec35a9472324b41933f3d44c1646dfe5992bab52b9c87dfa691df7db0d439dd244b52e95f79b5078fef2e749a7f0d44d9bc0a35e9c8dcae13712e2eff0e	178	\\x000000010000010048f3721a4d7446a5dae9ee9712da1fa2086813d91e573aa1ed12e91cdf8d4d7e31d0c45119de54164da6a9ced43f3e0d57cf87b74c5f2e427845b7f0a3dcfac66a8cc3d97cdcd1587724baa1340bd478b0c5c2531febf16858a1524f849465b89f7fe116428cedb3607709b2693c62fc135dd475028d294db6d4205d765c9bf4	\\x72d671f57edf7bff359491e53eed35f23c32cbaba8ee15c7ac5e40541fe5e5789d0176223eb674367224dccc3289e68ccae3d4582c200c5ed5933dd2776edffa	\\x00000001000000010dc9e161178ad280aaf48002f817140056ff77f161a72130816d9d9bd181164a55fcf73c159cf572a2323b5553530b5456d4689f9bc07097fced6826120b77a1433562b223af48a8e959e35012fc7ca2c55d1cb9cd903d506bc1a1639081b230176601359eaa68b48fc5176fa0955f277067ad470ce2bd41109c1d3f82bd9b5a	\\x0000000100010000
17	2	4	\\x359adefe4cf2687a077f06c10185a42f801cee59ea4254271814aa8aa46423c6980c40fe931c5b736d5a361df499d179dc036d52b8dca3598ce8a782a04a760a	178	\\x000000010000010032e43f08789c26330db5328c146c113251b188169247f11ffacb9ee2163379663ebc6224e27405c2a3ebd7c21c10a61fc82cc7b73347ad4d458169cf685ec6698019af0ee6f1fe972c0726e19726d09e4cd1339559f81b4f56aa29f6a58dc5258fce3afb8759beb43575e83bc0c7d5df981ed53b209f2aef444a87ea63bfc052	\\x21039f7aa14fe3bcbcf27d9292aca93d1d0e20d64446992d8a0f4a8a2fad47fec786da788a1e27a897bf2acc00f85c7388a5a1a80dd3b25840ae24da10970297	\\x00000001000000015f3660dd4e0af927b793452d0ecb6c23efd0051975fe19765dd9d90bfd0114eb73b9e2111b8935c4adfb8e223a6c90f5e5224b2f5a033c338f9cc44de050676bba680921235cf7c24891c3f282249bd98bf04370d4150ac81d876f440487a2a8c96166660b159600e2c326623b87f33e6d03c9361049f3c84bd84fa58e6ec299	\\x0000000100010000
18	2	5	\\x745a7119abd1cdb7d3d1815fd8366125a9e0f845afa427825962054acf21c49296cd91d73b7849563c89bee63ea1a5ad1bde547f9fa36426c7ebe225385be40b	178	\\x0000000100000100107815d93828f1465c3345834479d714d4d87b7d2aebcf735496151ee4f529602707badd16ebfc8fda31cee701ffddf5458f785b4a1a896a8c132b72273bc1f30a7d1b827a848ebfe7166672005b536b6150d865c8fb199bb6ade874f93218531e094fe1f3f461a19746648c114f79db7bcb1e8a071b86a46da4ab4dc29ad007	\\xc593625b9c113dcf1a76fe1b4db0e86666afe0030f04692a25dee7e8570917103934a9dc1a56b589d57b3135008d661ff108701298bf0b7110700f4fbbbb63f7	\\x00000001000000017bbd84655ef8835faf0570cf8e88f94c482a8450aa4cb1e173b25a636b1fe7d7e1453747e62e6f69f9914fad1d03bda2c5cda8f7627cd8ddd91dc037d7c76e5f30194d2aba9e964001fdfdbf45e006511e561b33cf6213268fda1eaeef38c6dbcf59ecd589beac26847e6e0ef8830d5c7fef90a31f4b98c5ca69e693d447a345	\\x0000000100010000
19	2	6	\\x8523c4861aa6d828a67dd8c3584921b1af8735f9930de2a06b4a7166af363bfdf68f94eb40e1e682d7bbce5133861dc3ff67201facf96f08d5168d3d2f005d00	178	\\x000000010000010049bfad4cbd7b8fa1d67c815e713dbd808fb13d3859133e9f9a3e13c109f672398cc4b4ec9c9981d264dbd90ad2b0d0967cfa24e0b6593ed02f6a57534ba7669177b01ea2bced1f3402d44af6cd10201f4df4dbb8f0dd7b08c0575dd9592b6740157b615dd28290120807b532860c4f432d2e9f67986d07b0e0bbed080aae0507	\\xb04492e6bfa1e985529e7568d0a460dc844be639c943b937aa343009644efac36e16718e21ef09f1b57bd6acad65c8aa5e7fee75e27c9338f7d8a0dc7ee1d9d6	\\x00000001000000019305e6e87e4ed10e53460100d844b1342cce466d767b7cbe327824201642ef5894377b88c650ec7f708667512b5d9368ed232d94186bb24f3f005172d1e201ca91975d79ed1552a01d12e9ea0c278b1969cccbe770483a900311940b3b46180676683fa448bd0af8cbf166e7b68e02aa3743a9f61bec7720ba0ea3cf2faf7978	\\x0000000100010000
20	2	7	\\x2016acafca2df78b9ae502b066a27b33d6edc5e87b08b1fe34a88b678fcad3ef6f6564b7f4d2c5b55cae27c3897a7cab34c61b4721135220912d84b3dfbc8b0d	178	\\x000000010000010008e350d2702b42c7912c6a5187c3ad370c85ec2eafea25a39676a7c40b9ae6a6ff7d2dcaa7e615b2b69374e573b2c33b35eaa6e9b0afc1017268e1833a1e8778f2cfb27d1ba3db460d16dcedcfb4f29e8fbccd3a314fded4e471e6ffde209822513995546e8cabaa9da92f926489214899119e4afec2e6c93255bcf75fe69a11	\\x8a7e452464873c7ec434cc1bf5c90663b0671fecb27bdd66b0097f196cfed7047598b538c0ee0c912006fb95860050b6a89379281f9ab7354c3d63b739719e1a	\\x000000010000000182ceb6a263ecea3da597e41dd93bb07853a9083d4b9fafe07cab1ca65e41f334d4b9bdcb956cb5bda3e6c31a2f4bb7aa1bcba1e44c17faa4156006689aac9df98e19f3f595d31530bd2f144076217f8a91b6952c4c85cdbe1ce5a798b043f4896ba4f0ca3243d291d658cc18ada3fbbdb6f8830f34d5146ded11846b606da0fa	\\x0000000100010000
21	2	8	\\xef8fdd4193d9995b93133b34926930c798add57d875543c84c4bff71c1f69daee4f9a4b6b7b3d5a2e49659b716c9d88e26a76cbce05f200eb11f08c3ee341309	178	\\x000000010000010089befbf58180fbc586461ed7806a69f77367f0a68b63afeb09c5bb2c189d5cd683b070e0eb473170c068439d79d753698d62d9bf8226a1410f1ccaf1e1a118d994225cfd9defef4a92dd7274069359872f1abe8927dbc63e15bfc11d75e202901d887da01e6448342466ad463876990923392f1187a8bdb4f8661c881c113d12	\\x1ab7c8e4d9ef5f6fe3c96e74659324d32f1dd26809e00db82ae437870d51b9d5f474da44656de3825e6843a1425ff6584e07f136dabc7a94b4733702c306ced9	\\x000000010000000106c4f12cd67e82ec83d7a1280a1fde90717a1a04dec42e688124ed197cd5310f2f2f4be35556f0239946542c82556cb9abafe4ff41603d4426cf763e4a4bd05ceeb63544e67e16f501d298f01c8528c60bdb96a652f3db2ce7c96592d96fbd3dbc8d2628606e7db4e06cfd0206da7d65a96539ce9278fe443763678d968c97d4	\\x0000000100010000
22	2	9	\\x6c67ac6c9ee220496f60604902ddf27344cf60d0742a429d2727e0c5d5228407a794c5ccc1b22fb8dc3fbfa44587514286c0efc83f23f55fe4b97b3b6a4ef909	374	\\x0000000100000100070544945f8f387073e83485fc6717bb5d4bc84b41d8985f8094d9a54bb6c53d6662ff416980c36cda6ea3837a78e52ca822f4f9de8858d8d9e6ae0c0a339a408ee068f6ec0a4cbcf790e87666b9ececb5c47d909d5281a7864646b469824808920974a4d56056e7d52a2a1fdaad1e69e0e5aec575ee73a13410628a5612340c	\\xdadc0252ea1c48364ff716e10b2ef0098aa03e261b08d857fc933aaa9ebe9f7b810491b667ff310e7824399a94fcade823f328e609555bd73f2b2db1b29ef6ba	\\x000000010000000159e10de6ec907a5432673b9b24eaf7d4728d612fea5540035789a1c16d35e9ec5b5cfcb750caa20a724058bb05f1b1923cd2deb9ea850128d079a81e3fa887cec5067020906045e7d61046b629716d38191aa38e15c3edfec3f3928cd026663fb65e7f7efbc05ee8831a51b9c0a26513b675c6001a9e61c684691a4e61f0b9e5	\\x0000000100010000
23	2	10	\\xff332b709fd3028edd3bf615d8dfb6a49235285a535dceeb7544b9cf3eb8eafaf58ef3673f7dc97461dd968d36e8824edb5810b4fe9ae5f0e318e49acd611e03	374	\\x0000000100000100de351bc0222662da94cfea353c1f38dc0cdc918fb3113b3c44a5ffa72b5b319878106c264b1927659db9c99dfcf3cda3632155cfeafc64a5e79be0cc3bfda830e6d7cd2b41b2e33112bbc8e61f6c89ac8a6ac680bab5a82d0ca3dd36d899f05d9a2284cc66878fb002e32ca36da7b024705272a03258b2369aed0ec9f80bc69a	\\xb6bddd920185c2daf34f923e12e1bc57b251ec6189231c58644422de7652f22089fee57d1b42999c85b6dc34fe3bd29ddc76cc12a4cca9e3b4f1f62a0753bbbd	\\x0000000100000001661ac161fe0389db6f3543efd83164b7e22cd063bd7493f857b7c5f41699a500434e3fc423d5c86efe430bc2b11088d128ee38daafa295dc702eec34c291a06cbe8eb80d0770bfe60f6d6d64e7a516dcd4750b23d3c6e6b0bb4fdf41e4c45e03d8aad5d9ff2c01a8a1fa5282caa9bdd82649e7698ad6b9a708aa1c44c02e3f7e	\\x0000000100010000
24	2	11	\\x08ec604eab695f93ce2fa2e25dda65f818ea5c54d591011f539eba77daaddd399c07907580d319ad56a8d722c5f5f2faacc5f1f0b78b9bd1600c1abc99a2ff04	374	\\x0000000100000100b79a4bd8b20c48aa045fff56b0720f2d5d1801ab5b5d295d694263841fe42043576fd8edd92371ef8b5be8704a5bc8757817051fa854bb442bed2b1394856dcb9a12cffc64cae743a3f1b4835e9e768268ff5a997d2e05f36e67b40f9a8f09af09fa9338d787fb040961a85bacbf40852238a4c59bcbd1f1ef9df73decc95910	\\xdf8fe371d1189b52eb519086c9b54dd44a84d6119a62ac7ff7ad9a8641786ca417ca403708178502e3977f402a764a18bff727ed21f046db74228c3245b0aaad	\\x00000001000000019cb2cdde7948f478e435e4af3dcfd9b6c997fca932fed7e1481b8902e69d561dd0cf2023ab2136c29d26d26535c4597c423a68349d6c70493118091e510a6c5d1a69d4148980c175000e226116f6269a5436ee68d343ad3aae67a9a3226ebaba16e5f0cacf6237c44b5bf4353930f4c657090bc8b9269b2347185105ee4addb1	\\x0000000100010000
25	3	0	\\xea26f36d335c035ab829e01fc43a6925713fec5880ed3330e2b411215951c74e8c5132a11335433b53421a726b30fc9ce149ac02ea0debf2bcee0cc5ae8c8505	248	\\x0000000100000100aa975fd1358e09dd1c07e97ca62b2433b79916788f1c7cd50a3f28bfad3a0316dafeb6d76a03ecc93994a80cb929d24632631e4b805b58ee51cdcc767245e41e81b5fd761067b64fc80eb69c242902b9b1a3fafa7bf8f8901d833f8f60d296d70c0cb723cfcb97de787b089ccf5b779767a111019340a15611a2ccf07ebb942c	\\x154d89e0203ed22a365a2e299e440625238b2ea270209f38472e11c0e1d188704acd81ec100df0130a8379fbaf610dcd220ebf30fef9836b4c564f6532f65a1e	\\x00000001000000013532d73e3cdf5d9d57a95b25e0e87ae7a349f3c10a6d06de7af038e06563a5f361c7c26b1d1079c7a750db8d79c4d9660ca625d83f301f894ff9a9fc072137aae49135f682c1da41cd11a2a4cde3c5e41733c83f1e3535b37b9ea4ec7aac209c2de63ec0d14fe1f8f1d0fc38d16be1cf9acae43a57d3c2f7948370e644a1fc70	\\x0000000100010000
26	3	1	\\x97df77eff8beab5d7a690d91fdc3503edb2e9d44b10d7f0ac25f6dc6d780b2a70983945118db743e1c404513db0b82bc4f4a4fcd3a6b85a405aada16c04d9204	178	\\x00000001000001004538f6f4f459b03794bc2072cf821284ee57bfea26b3b5353de5a42c55403dbe193e52e6d3a3f7e6af177fd25479a8cc76a7f3fd5ba9d5d34275dfbf25c0704f551de85ead8c39d103bf1adb664e1d1a32f104264322e50913d399f5c94f21a066b9ac3b09d272de2269fb0c61e68bd330797442e3e531710e75f17c28d0c10c	\\xd7c3eec653cb3122cb518c72982baf6b63e94a65095c1ebd321e7c840a59555a58fb55314d014e763d89e6f23d6ee239db7497fe8bd6ae35f3f4af8bedb22623	\\x0000000100000001b074dab128af6103aeec81ed6b89bd904d6a1f8cee1c0962515ba487b4dde1f110e2956bce1a1bd9325c6bed3a2231f237c94c8908ace56baabc230d0c39f825604e3a8c7a45a7ac339db0d2d789fa475c52ecd9b6b98231424d6de8382f320be1e212bf18cc649a6521048357a6e06b754e4ae0bbccac4aa9327d516a86b4eb	\\x0000000100010000
27	3	2	\\xabda75ede481d2b0345497adf5bf7ecaf45b6e857da63c3c384ee4342d2be7c102e7cd1fbee30292e1b3b96b6d14be2ad7793fcc536adf64764b0fb0d6a4e50c	178	\\x0000000100000100b45605caa3863a33570d1fd05efb5f554c1a419c69d2e4694b6542500f1a40ebd37bef8f659cd7bb1c7dced98d961f630df36d1edd034774f4ee49ca725abbc279382307f67c5efbc0adcf4ea76e81d6ba58cfabadfe02dc9caf6565ff238ab65b554b4eab098ae31a7cb00890b8c921b44b5642ba5774c45914004fdf13e777	\\xddf0a6ac28eb46d7e6b7a9a5cd8be79689cd89fed6c31292225bf8a2d7efa22615579cc3d24c3ab9686a2fb6a28d953e69c9017ef35fa7868e4dca76293f8a8c	\\x00000001000000011dfab5d264ff145f49220b2ea101edfe9117b70e408e7fd0b38a5d2d290fc5627d0550fee3ceac54d6601fe331fc3a759da2b239479f43695bc82039bf71de2eba5c7677890e02f251dbb93e96e6b12ce43c51b16116c907447bdfa531e5a39993e5b379f322dfe44c051a50de18260ff5deea012d91b1f9956476a06802e1b5	\\x0000000100010000
28	3	3	\\x21e8b8b9ddf94cd70fab94731c09991d4718b8fdaeb6cb4a1e0751ce95d6edd84409fbce7b7ca9dd2386ff6205930c257ce9ea59fae04fa61a856db7c606f506	178	\\x00000001000001005c75387f91047a23ee85db70fda4e1edbe1f47fafc6b8ed953b1394df269eb5b5831775b17b911f445ee65617822ef014ee13f5373a81dec9e7dbe6d2800e9e1cf515b6456c5a9ed6fc895744248b351d3789202d6ad356965f836e3334950dfda4a4f920d98f63694c5afeb9a90e29d978659ad14e933aa75e0a39fc7762831	\\xb7648b53984ec1e58390d1170c192b141d80812a9fa43df80f4b7f857f3264eeeabb11f0d1c955790a445dfc3f75f4de57238c7b89d6ae89dde66d7ea8c7e908	\\x00000001000000012f545fcebe894226475e9846d78f10449510c6f7db6cbd1948173be81856685d32b1105c7f42362e7907a9df17fcfc2418f7a44394ac3790856082434a97ac9a52f00960f1143e380dce7f5dbebadc19606dad23f5d68be9b3b863c5e69777119697a42cae70e1b707a76877942cf105163dc0a9c3fe05d1328d6dea695e4c58	\\x0000000100010000
29	3	4	\\xeabe8ce317fd255c354ca44c7b83a98731913750e248a3d54639d030520f128a1b6585a5ffaa2487d18ce0fe6dd4a24d5f7f5752df22b8a9a1d2a69dadde0907	178	\\x00000001000001000530d095687dd1548d53f3ae234d6e9b7a0a64e8ff48913011ee1f6d31c208f023a37613add440808b46755f3b1ed8fcdd216d48a1c024834731e174c02da1fa4f8f222d0d2fb9199dca555e87e17b8cc2ad4ed2d93d6ca3852da938ed6d07aab1983b8c15dcb2e50cac0a3a093495af54b7daf36c844fbe6ef9c99eafdfabbb	\\x27d4eb3d7aa74084c616a58888f45a829b85e40f523bc215723e5bab0f7d3f7a35822eda92680dde7061cb213f8bffbc70ddaa2b05147eb023b826f21259ba6e	\\x00000001000000017014f6c1c10a8cc7a3779dbca9da1ad18eaa5a7856363cfe79c0a1a8897042635b89ce3b9c4e5bc73cbba879a8bb9dd1459f819a350ee91e9bd11f945d224e26c6ced88c2ea25ecf18a5a80ce4e1eabedbc736ba597de14dacd5eef023ceee9bd1f6191ff1212b059310b5b0845bc9fe42b33b983b285476bb235000f263b152	\\x0000000100010000
30	3	5	\\xf0f9e3a6de5ccc4bc999bf42263bf8ca3e6adca0e08fd9cd248be934b9f36cc0becf67189723fbb20e2ea2fc05cc8ccdd12b633d4c0f3937a8a7f7294029940b	178	\\x00000001000001003b48c2d277a5f231ff7057e5f8a25def085b52e98c551285e5df7308581ac39d3439bd0fb528a29879c3ff434fbfe43637e48c74351a515333970f186f48e66be47d09d5eb41819a368eccb90ab0bbd0a07d082461b02da233d92d7fd3c1bbde58d529c62e80078200156b8a309ce28264ebb5760549991a990f507212dfb187	\\x4713689b3980c8d262d421ce9e1acc64b2601321bfbc56d5739eae6e5892094a13e34c86bbb15d2197edb0b3e5e76fc80763899597ee48ace8763dc65024e480	\\x000000010000000133f465487dd9618297f1b9675c8d1393b06c5bb29a7633abc748395e5ab8a14f95099f964784bd1ee52cbee963e5c6291dfc1a04eee7cf06c4054764788238146bc60a706406a6ef9fb20dfeb8aa1fda567c6219f8fa4ef308d3f237f49d5df6719cbb54f21e6c0fb1316200fe1463dda3d260a28fd69cb783cc5f2d2794bdb0	\\x0000000100010000
31	3	6	\\x43d8d08227ef0cdd67d33491b684a86f5aa6dc3f02f43e21c8dd5ccaa75928b1bf1fb1d00b3859010fedfe20f120f1a1003fec8b511f48f21486507cb037c704	178	\\x000000010000010080ed6fdbf618eca8610376e297ce5ea487d1cc44a395f3fd4821c6979cf81f36e56e6bb217371454f55f9e0c1a0dbff78dd7ef54d6af5977c69608bada7027163c71609497390073143e58208343ad0b40de7c2b491abe7ba6dc6ae219dfea651f94e3f80054dcb17c857037041a0d4cff52d0083860f2ccb5501d057fec1e32	\\xb93fd660e0e17ccc9c8014bdf7561408dcf25c4da796007d5b35121c1ef3866ed3bb05e28e2397e4c0bee634e2697ff3c2cf803bd86daab75f677fb40bdc10a5	\\x000000010000000116e994c4437d8b6de29aa10aa56620cf8a96c31f29018fce1f3ca3c5cc4f5c9e6e43094d71d402499b62fae9eb875c57aa075de3f4cdd340b08d3419be8b9e5848374293edeaeb73a6453a325c15db767a62cb3b838697b3ff889757c9959f2a44e4b47ab2c279e105559bb6fc0e0761eb340fb86ff4af858fc0ca05f5262309	\\x0000000100010000
32	3	7	\\x86a3cd89f186636bf1d25e043a26ddb2aef6d4784259a196b9ebfe059b2412e0b9d47a11d7801c3e1f48319e8fb2ec8aa1f01afa456aedbe31a99db8be7b660b	178	\\x000000010000010012e137566937560fa639093ef901cec08b40c1c7ece2fec195da529b076d3b7de56ae272964ae80cd1c323d4a7b337068b9dba3fb5251148005966a2fb60a981e982cece17aac49b2f99edbac17deecd4a7139cb06606e99f4528d5fa382d6287f9d3e7919fe4487f6fff8049e7470eb58eb81e83f6baf6e2becf3eb5cf7aab0	\\x186912e27ced8ea99d1b15a2d769b972a3062c6f7b50f3ec6e862786cfe31bfd48682a4ff16db0686480ebcd4b17a31b644957959cc2bb272ba92e33874fc422	\\x000000010000000197b47bec854dab4fa96acb9a1c5088edc3b75bacec980f35872ebec81da0b10fa8955fa23b21b1db3a46bb2a1299a7b0c9eaf444da52536b338fd194fb596f15492f43bdac025a065dbcea1bf57483a02373ce8363af4520f8ab5dcf495bfa980cb7909b28809c51420fab29ab01d5d31d21a82cc362eb6c780caf852497e54a	\\x0000000100010000
33	3	8	\\x6d752eff83e0ad99bbb82e6711cbf317e7edf71674593c862ca2e8e549096e812345b8351114427680d5344c7661813e3541beae0a86868958c64089139a460c	178	\\x00000001000001009afdb46d1eb50230a63161f61994abc0ea2fed64a354d1c7d44705242bb23626e6ff14d2ff2d55ede092f3b4b169bf7a5908265f7b194d15d3bc81d37e3528bcd23f97ba12cb1631ea43dd7ac13fa93aa90f7d2d2bbffbecf342ce825ee4b495c33d09144715c74d9d3bc349d607a5583e556a8ea200b1dd74e1a552254d189b	\\x977e6d815c655938d6ec28b63a26be1e306113e7790642976ab39f79db956b6a524cd314860cea6f0e2f60e0af2995905dc5c48e4a86dbb2d5ad163683b488e0	\\x000000010000000114b79909aee52139a271688ebb7a24f9e7aae17eae341d15d4ca49a4f8d17c49b9746532fcf1db5e029fd6f6625f243e65a5ae66795a351b8277c8e564648a5bac5ed1ceb34b966d4855f1f55744efb0601dfb3b5ffc8df55d193d192c8fda8133837dfb851a9254d74a314aa17583fec5fa38679d0716d1bcd1aea29c748f1e	\\x0000000100010000
34	3	9	\\x84db3bdba4f765c24bc0284ecdc832072967868fa5f1fb50f3dc225d9b07f2b16d01eec08684f096c9722679ae767ac40b6a245ce2cf6167b3d27b72af511b0c	374	\\x00000001000001007e81bbe337697d5927002cb03ef64822f52ad82130f110092c4af09bc6775e2c52704343b516fcd222f3a8d083b6ef9253f053054df4e0162c675750388a68ece8794311b2d106546631d687c2844da2348b522aade0372e876edc4951a7c13cd153df6c83f6e20ff95b3b8aac5d2d308f9c990f1646c0b3aae83e970bb3aced	\\xdc8124e3ca78cb7488a1d0c20b022ac6bb1de63bf0676414e86c9b139db6a9e0824feac8516cc552ce8c9f2f2f25fe21d99c46b87f6bffc9db40594f52f6cbac	\\x0000000100000001f48cedd2357eeee7532ca8f3a27934f6ab88821915459fe08c490f224091747b62442f8dc92a44a0e8c93550eb9e11c9cd0b53395b234219d3a46709c5252ff413f4bccd2633a70968c50e324a0b4c31b0ba897411fc46d55052648ef27d3bbcbe82d97c87a1b055abe8be9f6e87b7bbd655585226ee622bb9a81055fe8f9198	\\x0000000100010000
35	3	10	\\xa3004d43d9220f9225bc9b9c61cf0e3324a373c8fea10fc6a853d2e4e1113e87d96d04ae940efa5247a60a849ad4bd07f39a2c6b393b5d4eb756a8a530df9507	374	\\x0000000100000100eeb931d329c0f50323563b16ffca3aaa094832f6d484707c18211877bb376df1ddb2417d65f024cdd946624eabdc0454e6bdda6984c8c477b444810dec4c44ce84eb54158ec786d967f7eb94e776b9a7c53a291a755cb3f3e99a74faa4df0e4a7500569455cbc7d1208a035be47a3307aed78094bbacd25632c9937a4090a608	\\xb33a908694e1f8854e9f5214d2a2a928a294e4b1568b46daf6c446d44e1a3de9aadf07bb404c280e9c1f765218c3ae15d792629b794af1dbc318c83e520b16d7	\\x0000000100000001755f3cb86cb75dd455496d891a28f0b8f7448e48552b67bac98662cb7c5e60ce11cf2b461677e39c4dc231e32a26aad8453633a235b2b2285a26c6b169ee7818d39aadec5473ef0927008c868b7e102253ca97e509b9a5a29acdcb54f3898185f4982fdedca69b37a8d468e7562d32c6dedabff5c208d9dfb7e3cb8f6cf002a1	\\x0000000100010000
36	3	11	\\xd59fb86827174175c838025ff287c3d8ddbb03c56f5b770418d8db31dadb2b957023bd5d21c45a2e5f304cc896d9621378cc849b25e284779708f022ff502a07	374	\\x00000001000001007900305be757cf27957ee199278f6a5404abc8f3722de8d8ea0d161c5b52d6ad5fd47a83ccaa63cebe91bfbf453e5c53e004aedab1b4976a235191f141007647a7c0316404a3f09c7a4dbb79a1f721f65f5f1bf05e6d6d60ce3c768d09862a7d0846c530ef68b97f1b5b98f13c1d062fbc2cfca8c3c63c9957a4e7fb77d8cf81	\\x20fb3fb4e2e46dd703bd91a84b87c0c12646c24e6e6bbc34e4cc8a358150de10bd31e0b1f8850d0e4e4670919354079b7fb2bfa811cb2536acf16408639cfff9	\\x0000000100000001f545bdb63b0fd0f45e5d3031ed196a49ab73894eb39d74dede48607bcce48db7c19cd933a9e278ea075ca54bd2b2f32595c0680d63f502d85794930960855a6ba1e793a44821b760bf6e44195893fa78b1539e5a09c6eb96ac734128e400bee89022704967987511c25291ca6dc8774b4b9f541222178ba6934543d66cdcfd6d	\\x0000000100010000
37	4	0	\\xa752c2d2852e4fa3f853b6a84438100b3b1a7151b644ab97ac0cc48b85a1aa25807074f0cc847a6232799f6cb445a7836965b970a86e7b5c7ccbe6e05b204c0a	48	\\x000000010000010092b1d17e01afdc422eb72001545b9f1c84762837b5ebb5ba99ca0fe7f6a62da1e20153b5be0a0fa681a858c69e210f3150f09cd1557fe552470043e23717321377bb846829e24708fa1a04db884de11020e8e7522014ede689740fb400b9170bc92fa2ad4e3be6a18fcfb30f6912acdc48300c8ba434565f0f34d046d6e72bb3	\\x95ec9858e93ac33511f7d718992bdd8890e867867f89cd79d929e4f9ce81210f6c9557e3e2aae750379cf5d5ba4b8e3be5c31ff2b495d1e2a51690f011bcae7c	\\x00000001000000010d4d80c2ed69df0dd73f5f176018a14cb65944b71ac2d30396ce5568c141a5b1ade0154485ea228819baa5fecf11eca4993b3786fce0573c2903a439b9b031b03d393d181f7fa8409c8117bb9c36d1dc36c7aacaf8bb59c9143abd90d44bac7514b8237660f2b830156bc90295286cde44bb3c419cf4ac76788792de8a8f07fd	\\x0000000100010000
38	4	1	\\x28b672b474483fbc31677b7ead92f00d926ac34d093b759749d06c860bec0332028437faef4847e7ef62f174201109167a5a726b9b17d0bf6c4f50d581649501	178	\\x0000000100000100897afe2aa62f4f41c8b025e52afc04d613b4d76a785416ec9eed0b8920ebd0192df3d4bbe6044dd6103554e4b4f30bcf1f122b8dd00af54b6f6d8c4928509caff2c0864787d1d5c2e11f2a767ff231857a7c61e9efd62288fd90fb1f63fd94282294e4d5d867b63919de589b83ea233bf02853cb6c966164992564829d0ec6d0	\\x843e09508b1babb2eb932ee58a87535eda8b2348aa7a623242c59e121b9e486cb6d5547b58a598918ff611bc9a4cbac7a6af7ed648d83cbeffcddc51891291df	\\x000000010000000178f38feb0682863dbb88ad86de448d74dd121d0915d93ef22ca8c48e7b1522e504ba54b3905592edc2316b6144c2c99dc69be59af881166b2f721be9d6e113655949714edd4155344bf2fda726acc5cef686b32c60f98b4ac8f8697262e4f5be5d66437164cbafe035171a8102ac2981303177ac9e35e5a61132f24f7a9e953a	\\x0000000100010000
39	4	2	\\xb7108f6a30b8211c27e268f3e4082ad5a24cd843ee19295a6ec04500be45be3508b874b607b112b691bc70c73b02065980672cb23359e214193e5e3eba0fed05	178	\\x00000001000001001e9677ccea4eaaf1f55a4ddbb0e83c597df6aeaa68e53cf5143f05e7ebf79d7faccbb7dccbad60aaa313158ec14f78af249bdb5e7e3ab0d8468ba643424a9c247268b0951a3b854ea912d91ab461cd8d59b5fa99b71c5840b2f988c49c6c5f1297e7968895ad282f4218f9af833584a38b4bc9256e2f5d47de2b708842ebdde9	\\x6b3012d9e4b947c87561e445ddd4fb87dc250b8826437d42b20a783c5af0af9784d35da3378752d79f4018d1949389faaae6e665631d3a2bb7d6ecd98316f2d0	\\x00000001000000014242fc39868d9ef5bcab8c8a7c05564eae98ede36cc02959984fd1802f01dd4102726be8bd14da5fc37296537056c8e4f8c0ad5da837eea414499ed108c30930153dd0cb8fef776ce6240d35335514b9a85c8b54a70c525243b30f63be6e3069433d122f5ad35c9705c4f5bd39bd06df8a7fe5f784bfac6453dd8dd13396e9b7	\\x0000000100010000
40	4	3	\\x196b541dd1566ce3f856621ff0c7d3dcb2c67cb37c595387cd6af8ce93c8cf67619950e85bcd91b22cc8a21fe19189c45e84c8b8ada5a960aa9df61c16d2da00	178	\\x00000001000001000dbb402991960b79d5a431ff9d8cf0b9b29328606ad4ffcbcdb27b5043688cd9426b8d0e4c9eb9cc6e434ff2728d56f47f15567394a1e6f2fd3fd81d54599ff7692846ea3d8e7ae0b0b79c6d01303fad1907b62079e9dd3be3ff4e63052504b5c9d83f3f6dd5a1896fcc6d89ef388758a46a0c04ed185a21591cb1a67cee3a21	\\xf3b8bfc1f795e9e0419dabd9faa09d4d4bc44b41937ea26ca04aeda45a2822307ea819ddde587923751676a4d14bca1bf67c3a76ba9aab29367b91d97828794c	\\x0000000100000001b64fa5f80793bb4beb712b483539f4336fd40089b27a8a528c737fb748e4c67f131415a63ba9d8afbab274fd275338addc97e5c4760d87f31f74f3f7775b035338190c22188617d1a4f53b300ffd7e56f0daa424689aea53680107e24f0811b67a49b9730c28fea8e324e95da030f8c620d5d1ea51660adcda25ad5433b6b7d7	\\x0000000100010000
41	4	4	\\x7cb4238fc6ef1df30159998043c6beceeab4670d703d7e7e67d14b71b8e334eca8b6671a1da7df988dd3af3142e2a65636640e49764d6fed3be992b657361809	178	\\x00000001000001005fa5965217a01384487a8bbffaa6137c05a3830c9def1ef57428a479214b7d95b35dceaddd2a94637345bf4512112fd54fd12beb1b211c368b26fa9a7c55362ba18eaf65cee138e9a2a1a5bdc3d774b517389dd2c817719638c51bbc6bfc843fd3464d68657d5069a24ff39eab7ae00e95705708fd8350701ec462a7c2c4a0eb	\\xd12ec53ec09e3bfe08556f99a8bf847325d323c6f6d4c1e49d26b55a063e1e26c460615a6cd17601ef6730fc92aa5a358c4a314f487d6ae8677f56db527a46fa	\\x00000001000000018642612ae5ceac94cd830f278e47036e0892e654205c86e191118e29900b697587189d54497c28f798dc89adf8785fb5cfbe84d94cb2bc9e34e3f319bf988dcb2667ae94e59ed6a784960b6ce4b83e85ddcccc0669df6ced6c0d52c1ffdbbe5f88322cc0b01ff16febaffde2bdaa4afb21fb752a89aa26c081eed5d6e2860e81	\\x0000000100010000
42	4	5	\\xbf1f39a7a33f6ef800ef0e4dfc92f0002f6914f1743595fa2c3ef43056ff4c2bf6f62421aa2c90236279dab96dd1ba16d286407508a90aef45b86138018a6c06	178	\\x00000001000001008503f1b2fe07debeb20ea72ea956233ae5984c47e9de2df7ca96961db962b38b2a14ce4d00cf6d8f5db150285a02ceb6c5f8a53ab64c67ec706f16ad68535ba3faac0c7420a57ed92ad3f042d17bda7454e45a3e0ef3f488a6796e6df3cbf8ee6875abf97b24957aa8a65d0a0e08e015bd9de50f1328a5c3d04f439d578c38a4	\\x25659370d0f7e8741c386fc9dae228be4146ab52d588f954353cc07af602673e0e2c9aea130ddbcaf94df2ccc9b4dcde306a4bb36631ed20a5fe8b244fc9466d	\\x000000010000000164d6e5d7aac658939f187f5b344b84c6183f47b6ddd5b80ccd6f3724a60380669921d7f817bc6d8afefbe419c0e898e741c644d3f09371b676b7333949af5796fbb7e05288a77c92888330c3c39919870db8000aacb571ca984f91839e3309e9e22777be1a4ccf93af18d99822f6e24ee7621d5be1c374cbaee5d15415f8ed4d	\\x0000000100010000
43	4	6	\\xe2b1b8fe388d10f1dc46db9a6a29939741f2a287e62eb0e92b2125d115df5152a127a351d06f0ca5792550c59e8baeb3c2eef73a14acf4f317dc2df529200109	178	\\x0000000100000100528daa565cf9958cf388a9c33dccd7a40c099518d3f21a58ef800d7bf8835cf55c46fbcb4ffb6e6c04f0b6b6ff9b3017a21b5e05f002f200f0ea20778388ae10f785ebee4a4cf4b3a11984f26aef2fd5b1a22b65c9ce4b6e70bcd33dfb45baf17acc0102b461e0d7e39bf1efc1eb4b5ef49e64d75583a1d76e0098fabe652d6c	\\x6faf75b145bf8a879374f7893a3a12f9c020849ee523338790cb12b8540078da836da4db6c7152a9646b53aae2df5844aff04c2d0be7e7007d66c59d679a5784	\\x000000010000000198261bb71c35206f3856e6ff89552c8f61b1d2cf7434e6e6e140cfbf9d96d7421a4a8dc205a674d774eec4092be8c1789812548c2b69e476ad121ea696c058b3186563b60f2638bb3cb2636647bfc429556e48fc2ae6e40b21cef1c3d75c199092230c4e760cd3bc6e6a88c1ccdfad6ca564872b609282bfdc1c46c4ef49cb97	\\x0000000100010000
44	4	7	\\x57e397a60261d10d7a3bbb41d50d12cd9fa63c09fe21e7a56a56b8672231a3a5dccc99fc110500d45d44b1787881f180ccb442135abb85679cdb7e66bc27db06	178	\\x000000010000010076f596fe37520d4cc1b7172a390350d40729b0fbb3019a6e9c3e40dd6b072d2a39ad41f60211db254936de892a938a4830056b9a6b77490c779ffd738fc3bcdb0b063edbdcec516896d41de4ecf5bb0f52839dedd147052a7bf11e080e9901f760b7d73ef2aa9449c8eb2144485e179f70c0776d289fb42fa5be5caa8607e5c0	\\x5b484012196d78f165300b7ee7dac7be25a828bf88c54ee8f2a389de4dbae177504bbfddfcadc60ab12b53d464d9c00efd05e4dc1ded8657c892a3f217f9ec71	\\x000000010000000111c5c49afc9ba2655fe61b7841076ca4255a228513f1343bb6892a6031f4e8a2d7a34d08d781f6b5c7a0870c0fcf07639676517e4b99cfcc242f229a1425991a50050ad709069bc79d17b009b74a93512849e7e46488f8088263adef3c4bf95b468155d7c2be03ef6401d67a9ce9602d3931def1222c72ac0cfaaa5295cc805b	\\x0000000100010000
45	4	8	\\x90ff2e3570bcaa1384a7b513b4e5b115b58c72120711e948470c02c0e42f0859b7e36bc2c6420e8ec309a6bdead8d0ad922eb0c06bdae8cc2173113663460c07	178	\\x0000000100000100a3cfe7be5215491e0690d3ae332197c1386e70fda49dc31365c3db989a708aebc2b1a8e8ab8d19401db530d5c3b55e38d9baaefb95aaa76ca566fdc68812c95ee8f3dc575360a69058115c80acab9883f0affc0dab8cd8745a36be29e6deda48d7ade3d0ac8c1bbe1d278bcde11cb08d89242694c30014ac71c44295c942b930	\\x277635470860b2e793bc1cb0890ce5e82740518ad1b8b923450aca457cdfb60909b5f559ff6a1abb1ae3db9289d46cdb3162626fffaf2f2e71e2203638c67259	\\x000000010000000125e04e415f6d18c371fbafb8de68999d9e62e0daeb5fbe7f012ccc2ddd8bbcb6182c4e889fe5c1e58c8cb27b8d8a8f953f134375779479223db4215866536a9619af37ad92566f9718910e59aa1124e56568f128101b7bbc3a433853e248aef357548ea78bdd4fc49e87ce13181c3183d2daa387d3c21885714e8abf2c4b8e84	\\x0000000100010000
46	4	9	\\x2a673e2cb58908f7d47b1c8c2dcf0ce282aa69239f782344bf060361f02c525ecd4c22e13f73ea3b79e9af3253c7b415a05081b5e7995cbe29f1bc76d294fd06	374	\\x00000001000001008c9751c6f4a5148fd369fb16ae274a128ca7b4f607c9f86ca3950298e758739ab179d55da7590a2273cfc2d6af207513e2168dff60cdbcbfa5931ee6c09c9f9e7760fdfe92580ef89ce701bb5c842620e68cfb42c389546a5868f2fc613d279fb9955e495808b5961fa0b8d77763ccd60227c817007bb1ff61ae973a91d227d4	\\xb9d959225db080ed72b1002326eb585a6f47db7e46e849d557f289d52edfa6f3f6369241f7e695b71adddb3a0d64ce628d7f2454f66a7b9d3927fab8b26494db	\\x0000000100000001f547980db9d79dd56901f532a3f79500d8aae0f71f44f30ac1ca518e9722fcb9d45a3a08c5572eb050ae81adce0ccd42220e7c3204fdb264f59d8f16e78c642e16c170a676c23e5e6920ddd179faa5fde0336dac6eb294788ce036a72029603a0cc7f1c2ec99cd707c94ff493dc111866273186235cf84f5d20478b835a8b569	\\x0000000100010000
47	4	10	\\x61c72212663be87e819c81a3717c469cb1a46ac484a53bb6f62374ad4d7c6e3df209984e5670315404bbfe7d3c26174150623611eebc640fdb0a160bd7737e06	374	\\x0000000100000100712247ebef606d95285433edff9529de0e12de17cdbabb3c67e230908bb8384312f298dc170cc41d215ffb09858217b7085f7006f0148940a78c8e2a52de6964927b296a82f7d56a6220c0e3f346f44a3cd5ad2bfc563ceb7a188896750160477ab5bcef4a46cbf88b4c167b0c85bdc30eb73464470bd8f0e34a99da2ad8c3cd	\\xa773881b04b2679ecfb4246708c036267079d8dce6e02f24d0da48470b7abbfbb57a68515d8612d8e1d9f1088a6935413651aedefad0dd6d40df354b1b08dc04	\\x0000000100000001d28de7f114b657f3ea240f973e31fa693a90b258bdd492fddcd2759340e8c04b6211fd254f4480bd930748a4037834f5d47875d887ffba719ef16b0f81b260a0ed1f7175e50ea532cda270eb17f791314bac10c765694987565357a7ff0bb3536b8e81613e62661f1fea65629ea4317a4a990cb38e7de82bbfe877b47d3d6390	\\x0000000100010000
48	4	11	\\xccce3ecbb58164afbc9a6da871cf0b0fa218acbdb95997f41dad9d2be38c6e025b40a31d10b6230dc64c3c71e40e589f274fd6eb0b7219d7ec18ed1ac8ce090b	374	\\x0000000100000100b30e965420e2f457cbe2a3e1adfc26dab518d8cc1bb65ae3da65df58dd34c6f478c3ed23a05512dfc90a8bee505c9ea27ae46e27eebd100582b03f0a664684a02475d46bbb0adf622930f147c96b534bbbb73732d05ea0fc7ca4aa4031ca391cf8f3a903b6fdc0c46fceb4e04d72f60d9f38137a7ca3ec99738e835111f10010	\\xcd6ec33b6efd04ce19debe01d37ab43a78ed620a81b637ffed238b85e11f85bd6552a6186430be1ba99517cec4f2076b61d3c33cdade46394b1e6659a156d294	\\x0000000100000001b2a04106dedd9e4619c6c307f2a8f087ca22f0eb226fc1c1d27b63e0af6a7b801c608c6447c21b471a1ecf8dfff38837f5e82179044dbe334841eee39601a27d7cccd29d9bd814bf994c027bf9365c2eeb5283a02526c45e7b3727787f25cc42d6d6e6303dcc4634303cbb6b18eb72385a27156b07081f4a4eedbcf800547bef	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\x7229049fb28410a2fae30ef73b30a3376067542d870474737e4f1c980b490e46	\\xafa552e0893803649f3b0d697ffcc25c8d7a2878a470790fcda29237488c7b2ce5dcec57024f5f860d816cebab20ee7dc23b4e64e922c7e39e1a0ef77ee5c39f
2	2	\\x855d7745457bd9d1ad7665a5bec644387935036362a4436b7e12adc573bbbd08	\\xa83a8c10a2d90140be891047a8b453809dd2ec341fb1e2d4cd355e8912d5ad8ea155c1698ad9471522dd4b7325d4e0630560009b1abd9a513596de2a7ebc7db2
3	3	\\x651ed3a0e2e3af5ad14f93f538670ea27abc6ca01a7144b77878133759214c34	\\xf8a18ed32ad26099721265acdc9742744fa29b033fc6162843164b98abd42cad16804fb25bda53bdef2e2b5ac68a21fe3352823983f2ef77b13da66620f74652
4	4	\\xa58d196dc16ae44c9befd9a5508b71042d4f0057a0464b28a9bc190eecbb3550	\\xcb2b7c26cd69881a4d2b9dd7e819ffe1ee31d471db66acb3ef5c80678db9a89db14fea7612c948f2f00dea5065bad796243b57c742eb159a03f6b517deed86fe
\.


--
-- Data for Name: refunds_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds_default (refund_serial_id, coin_pub, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xe577cc9b4807132edb0408b20d74b1b50e6d1ffd4fb6b332a7e5ce5bd7665dbf	2	\\x3c268fc11fdd5bc41c1caa4d34e833486c87e8a95e6837a5b84b4db58d075a1c8120decc69e7f6e130cfbf810d12ecaf52dde67b2aa7cad5f682430e153d7e03	1	6	0
\.


--
-- Data for Name: reserves_close_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_close_default (close_uuid, reserve_pub, execution_date, wtid, wire_target_h_payto, amount_val, amount_frac, closing_fee_val, closing_fee_frac) FROM stdin;
\.


--
-- Data for Name: reserves_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_default (reserve_uuid, reserve_pub, current_balance_val, current_balance_frac, purses_active, purses_allowed, kyc_required, kyc_passed, max_age, expiration_date, gc_date) FROM stdin;
1	\\x8e218d5d5d01722ba2c840752ca057016d9ee77f91cc8361dfe93d32e087b879	0	1000000	0	0	f	f	120	1658059580000000	1876392383000000
5	\\x0b59c0a997673be19745b5f617a961e49b69388a8f2f774e15722770943323dd	0	1000000	0	0	f	f	120	1658059588000000	1876392390000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\x8e218d5d5d01722ba2c840752ca057016d9ee77f91cc8361dfe93d32e087b879	2	10	0	\\x1be0980cd3e088d4b0e7a46d6ece6bf749bcb131fdede29f4822b1856efb5050	exchange-account-1	1655640380000000
5	\\x0b59c0a997673be19745b5f617a961e49b69388a8f2f774e15722770943323dd	4	18	0	\\x5dcc39674dd6e447dd1de57098e134cc951d0d2f10b23b3583edf607327b574f	exchange-account-1	1655640388000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\xfc6bc2553f968e66b9e5601eb9942afca52d5e25b3c6a691db4d14db28f48578fc3efdef8fb91244cd75987baeff71cd04718ce820ca070f1565486ec9e9e203
1	\\x0c453ea1855c481d2441920c3a36d46ba843930b8e732f58b388ec8057df19ec240322ba75356e140722363afbeee73c296e511b4ea4e876dfb49d074f6321f4
1	\\x5fd075c57e0b0813d12cf909c2c682dfe2151093dca8679f12f8b4e72a0b62db96eb4be075eee34e40dcd6a5cb5be75914de319c53bb469a24cae0bc4372af24
1	\\xb338c8171efa63ae43830c78dcff7a61b96600aef15bf6d1a91f493d7e3594fefe6acce750e77307edd0a934cc944ec769de8720c5f0bb561a2260a018823b8c
1	\\xc7fff15c00453fbb8e99bb7df7c2d7b312ac304d17f4fb912e068600b8468ab410e98eb4bdb808727ba5fac4b3fae465349d0c5e25dccbbc32eb48393fcf903a
1	\\x80c2ae29e872004919244e7275ae595a792402868a62544386ed1a5b0668c7ada90e5a789e5b7eb16bca6aaec612988200f1727bdfbd4e0d866a4f2a12d99c30
1	\\xa51ffa96a41752c1de52204a880d61352646692e6a647292f0f211a18655b0e28a6f5b2006e8dd1cbfee4c32492beb3460fa951ec705362186a5dc73185d5c40
1	\\x9c684c092b8a229cd4dd220126fca864d4d00b46e0c721476fc25a4416c1bb76bb271c1017d9e99d878413c414c33e777defbd495c7de6a1a878f4a7e24819bc
1	\\x25f89e81627d3f6427f6b41c5b06b405d930b4dfc8d69b71bb0726214224cb84aac221d12683d7655a56f52644041088ad20607fab8d90eeac43de11d5783570
1	\\xfa48df8c82e11e259925936cbb0f7b9aa39b3bdd1fc477b25fb53a5ab0f76c10238d279e44b68dcaaf22432731a5c3e16d1c1ef123351787038a4230f60d7840
1	\\x68f61d1090cb606cae07a539d6afc4bb62396ea59fdcb069b524c8c11ccc73af9d57c232063b6cdb3f770bf0e51c127f56717680a88c48b58591e1237b40543e
1	\\xa3caf100ec69148f3275276284ba612d8c37892487bbf65dd976b6b6f218542f6f46be0cd8bf9059c56dc371b5691d19cd1889e2bddf22dc96555ac5f61cf477
5	\\x75f45bc40f1d2da8ee35963efa67a5051b82abbebd044b79d1d32e71aafa83d7c71cd21152e89a35f238f5764fd5e2d32b71e76890d0da875e4716e3d7c7bf58
5	\\x4948e408eafb5ee22f338a228ef1ada0779f9cd7c8a3964e5416f9517b934f0dd73db85c485970bbb9617405a0affa0b31ee85bc079a7a1ddfe0f6a9fcb6a15a
5	\\x93b266c53aa27144eb4e76ba3e940ea28725c169aba62d6a4ee33d2c803a36b582fa13e201c40e66dedede0ee47e453cc3c8afca2bfc9d8bdbba36e75fc3fcc7
5	\\x3c32bf83d1cc9eb3c1615b618b34c4e015ad7b3c81be5830dc395e0e6514fa242cde76074531be10e36602d5751a606868e548174bbe730a8a7aa51b53287265
5	\\x5c0760782b196e39215cb555bf50612963fbd1b5ee82c0a7942cc1006210f57f94a561eb97e271aaad28de7971aa4b732b4b3bf86fcd0185cbc2162b579bb164
5	\\x4f94897ac4be7925bd183ac8ceff2445646620bb547e7c4e023f904bf1bb20131ff1918b9701e53b1b06eff6282130c7dcfcb0e5f79046d3739c219a098c8fd9
5	\\xcf25428ae38cde94912f9f19826ca4aea790cebc5e5642c7274fdf3a25355065e79a26f090b5d591f69e8a89f03207176eb7c9de0881e327af730c59cbb0220c
5	\\x05a59555df5d6ba2ab41352e1871ca8c4d290223395153ccd2930b438cdf9012e00c52553c05499804de719f17d85cb6d4bf10d388b66ba93f044d876927bbce
5	\\x38d18f9a4cba086242daa57f88183f2a85513b5df826462f08503fb845d5e781f5320fc322b3d9a1a6e0c7bd2e6bbbe96124657fb4099c62ee470c4db338bff5
5	\\xabc5c32a539a00f0a4b8f5eb0acdf40209aab636e8d70d5dc9037ec0187bee586928a919c1bb0d0107b82ad98fa9491916e43826179f498db0f435396578a505
5	\\xd02142e3ec1c84eea41c1b6faebd7d567640e22f51ab5bc960003ebb5fafdeb62f9f4e8d0cc9a6b1ea7c232b928c5120ca9dcefe0193b69369c5c73b8afbe2c6
5	\\x042d69e6ec3df3f28545d6dafab2d2f5709e125558821731b983b7bf5e019851e4d0e4c3bd3a4e0b6caa60bac5ac58db86f8cbc1bc8652e7e5ab05395376b95b
5	\\x96934e398e4b786a44faebe707c2928ed2d39c6565fabf552fa44173ca9c12283da6fbd3ae67a5da638387d82e4655d96d6e80abb70e8459c1e26452bf7b1ce1
5	\\xb6d2a3c3b38566c6a6cba1ce26e24f9eb91b4baebaada102ef2f2d26b9fb3f32d8a11743008018796b3b59596490d5905d9782a7b2b59f2c1172d1bdbcbb33b7
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xfc6bc2553f968e66b9e5601eb9942afca52d5e25b3c6a691db4d14db28f48578fc3efdef8fb91244cd75987baeff71cd04718ce820ca070f1565486ec9e9e203	208	\\x00000001000000010fcd8f507d75b69adc3bfe070b60822112d9bc27d3524dffc9456a756979d6dfd3d831848b16e0e9ac5f54d5be3becc34c307c639f9b3687e06271dbae96b720079a97c0413307cba4f12f8ec94b0af3f852e3697aa867f47e1a24e21b1612965e38273a3a3776e1f8d43d23db1de31fb28551a58a2c761a744ee77754b17c5d	1	\\x05025c7a57de79e879c49d5c18842baeee164b0f337eaf9b0fa60c9969520c4d888dc9f891000fae05b22de1c495cf780e787d4064a842d3e1389894a3e05306	1655640383000000	8	5000000
2	\\x0c453ea1855c481d2441920c3a36d46ba843930b8e732f58b388ec8057df19ec240322ba75356e140722363afbeee73c296e511b4ea4e876dfb49d074f6321f4	48	\\x00000001000000011a76e632372644605bc307873383802214b5496c822112725d480e58c1442c237885e448d4ec11cf68a79df963475e66ce28360c29d3ee55aee146e7cb8299efa7827db15261991bdd260c042c81be277ada9a398963999b574d305ee170a1da3a389d87f8452c088e454c72131da8cd03653e57ba6a947259ab4f028d30e374	1	\\xfd3dceb686e7362c2bdbbd315471b74c52a1a1a15df168477ad008b0430c1e233ba49dc9bb93b191dff1aec4303956ec058b119fc0c73ffbe1075ab247a0e005	1655640383000000	1	2000000
3	\\x5fd075c57e0b0813d12cf909c2c682dfe2151093dca8679f12f8b4e72a0b62db96eb4be075eee34e40dcd6a5cb5be75914de319c53bb469a24cae0bc4372af24	178	\\x00000001000000016d5cf6ac32806ef87eeeaa2b3178c6e4e74b806d4a70c9bb084edd5547294f994e91a04a837416fc86ef14fca591ed66fbf85fdec0fe53593cbf33d989248e660144b2a72492f8889000396573c8937f19c3286ce13c4c71b47d5e78310e24736b980f3c533681f399a158566af66dde22452855ce5c15afdb7214a6b1d00495	1	\\x41110120bf7fb7642caece4d66185818d091bea7db397d94b7f4b92d92140815b70e373b08b3980ebe3bab87cf7950082a53e73e62fc28e3c1f86bdc4317860b	1655640383000000	0	11000000
4	\\xb338c8171efa63ae43830c78dcff7a61b96600aef15bf6d1a91f493d7e3594fefe6acce750e77307edd0a934cc944ec769de8720c5f0bb561a2260a018823b8c	178	\\x00000001000000018c52292d1e3a8f3959c6358f3be0c1c80787ecfe2458298f4b9f74a175a035bf3d16fca9a5d22526d8ac0a14f7dfc00ce7793a532d65a26720ac3c393b9e8293d0c24af58319c8adf6865c945e6cd68eff437eda82e79c1a78eb7dd69f806aa647551a61f583a35bcede3e1c96df2326674c5025133f0b08f8d389932eb7b631	1	\\x2b214a1832b4caf096bab0a1c541c4af2d34deabbf1a30c0cf6880af38eab8cf5d7e95a1bd2fc82eb112a66d10271c1223ac4b8d29f799d9ef3f1df7228b980a	1655640383000000	0	11000000
5	\\xc7fff15c00453fbb8e99bb7df7c2d7b312ac304d17f4fb912e068600b8468ab410e98eb4bdb808727ba5fac4b3fae465349d0c5e25dccbbc32eb48393fcf903a	178	\\x0000000100000001328b8f9fc397fdc1726d0bd0c49166a880fbdaa2617b8b7e37ce95db6cb771936938ea931ad61a4df9dc9060b7584f095a8510961b5560f1c5a3cde7fb9d23c8fcbd90842c612c72ad7b90633556ccf1ecd897984d19c9ccf439d34aa8a6b50577302a79a2fbdbb436c99c0414d164de18de3b329a0f881a12ac180b556a4cb4	1	\\xed2eea990f14556c5496789ade45019936cb61221fc52a4663ccda3bf87be8c569379ef8c3ab49e996316297b3d2ab30a6001a0ce1887f5c30ea3f44ace80b02	1655640383000000	0	11000000
6	\\x80c2ae29e872004919244e7275ae595a792402868a62544386ed1a5b0668c7ada90e5a789e5b7eb16bca6aaec612988200f1727bdfbd4e0d866a4f2a12d99c30	178	\\x000000010000000116f316463d7ac2e0f628ccdb9452accf0fe770a4cb22e5df4e439813c09c9757036a681814e5e291990f3b59f3794765ce64baadd66d44c7c4290b9c21df08e60b107e762cfa4aa8ac77d907725321bddf8f54da2b263c3a480f5e743814547f345ec2294df76544ca4ed8fe29bd09f7a134f34b87846cb579b6a40ff424570a	1	\\x18db40d352e59633521b0fc74bf24a953ad1bd2db7d0780189b1cbbf51f4ca9698b800619fec46644c01e713b2c9e92d45c619e033cd6786cfe29546558c1b0a	1655640383000000	0	11000000
7	\\xa51ffa96a41752c1de52204a880d61352646692e6a647292f0f211a18655b0e28a6f5b2006e8dd1cbfee4c32492beb3460fa951ec705362186a5dc73185d5c40	178	\\x000000010000000101f9d0fd6f1c28f118d52db3b1b66c6156fc86bdc8a5f796a967894302fad9ad26708bacdb95bd35ea6a7ca4fc81aeae6af62e29814a68feaf3850fffe999b69a27af42267ca92227f13d1a165c7e49270323c34078984270f683031f5c8a9cb8213615cce0ce9c27e57d1223aa4c3337e9fe609302720a6bcead297df8f4a1e	1	\\x9ad09fdfd2dff5b17487d173728058108739b78c0983e9ab42d57d76915783c4455b8fef53c0f86da1ab674557b481b52193eadad2c0d03c61154c6c8c09f101	1655640383000000	0	11000000
8	\\x9c684c092b8a229cd4dd220126fca864d4d00b46e0c721476fc25a4416c1bb76bb271c1017d9e99d878413c414c33e777defbd495c7de6a1a878f4a7e24819bc	178	\\x0000000100000001025663877bbc133477c6dc8bd753573c97dbe1a7218c9f0c1148dddfdc50085292bf65c2f583297824fc586c7f5420119802e4638de89baf5a537316dbbd2c9fbd48e3acfe3ae352a2f5e0a836eb3398f15c9a04a20f0f56a1b929e1d2cbd7982b903c82706629a2fb377ada4a8715de18c05c5d6dcf0b5bea798d3aa4454f5b	1	\\x0452d4d4406fefd54b2abe91437aa8a0ce6a202df69dae8677483b84fdb578e47c268df32374634ad94b45185150b4bc0a508fe992e2fb2cbea9a1a11eaddd02	1655640383000000	0	11000000
9	\\x25f89e81627d3f6427f6b41c5b06b405d930b4dfc8d69b71bb0726214224cb84aac221d12683d7655a56f52644041088ad20607fab8d90eeac43de11d5783570	178	\\x0000000100000001093b3ffd8cea7461f21ec0596aa130c234c15dd276b911752471b1e7ec6ed6ab2e11f1b300440ced89a937d59cccc48095b058b3a832cddd1e11bc9d966cd554612fd0afa2acc59e154618426a3b0fd044ad5bf29c3b791bff1c622a99e49431de44c7e148ffe8ca4a010e1925c97f29aebb76627c14614a5e6c1447bd4422a5	1	\\x28f81835a1eafdbe85754b211cbbce3292aa80c6e8af28a3b4ab8e09f216e264c04f5cdd0952e4acc479ba28b436b625481caab39abdaacf7e82891a4cc07408	1655640383000000	0	11000000
10	\\xfa48df8c82e11e259925936cbb0f7b9aa39b3bdd1fc477b25fb53a5ab0f76c10238d279e44b68dcaaf22432731a5c3e16d1c1ef123351787038a4230f60d7840	178	\\x0000000100000001ba82cd27d9ce2de7645cf95f6dd5c36bbe7e26e45a3f3667c45e3ce44603b127859027ae200b04e4ab971927782257c7c8c702a67468ee80ba2bfc11f0cc9ce40134ad45191d1ec61850a97ba27aabe202164411b08320007f5ab46eb247539d657a3f0fef17aba10cb8a89e3e8bc7f0eef480aee2f9460a5c482241d216a16b	1	\\x4c3f91c595d78e43050d7dc82cd387872adccd1ddb035e1f4e8d7ef6f863c87d0810722f45b29420e32ec1f5dab185d37b74f022c55fc01511c0e36b9dbda005	1655640383000000	0	11000000
11	\\x68f61d1090cb606cae07a539d6afc4bb62396ea59fdcb069b524c8c11ccc73af9d57c232063b6cdb3f770bf0e51c127f56717680a88c48b58591e1237b40543e	374	\\x000000010000000183aefdefcd1684fa9a559083a71e08daec0692437065ceaa92c0a6ab192a6ad4dc3aca4f1376e71d51d7ca679d0bfd2e00a6e235c2d98a09784be2345ad11737fa138a72ef2faaf3ba8c842f451b310eefde77bbe8114426f4a75f50c8280738a911a67d75a8dfb280135a8a9e05a3ffe6aeb1040659ba91df3f8fab17bdad04	1	\\x57bee4fe1e9359f01120891dd9c8d32b61ed220b4b6c941042dfc7becfbf0260b337e467915a15d9fd01a4353d787c5fd07d592ac831e5a1b5bb76986fb0010a	1655640383000000	0	2000000
12	\\xa3caf100ec69148f3275276284ba612d8c37892487bbf65dd976b6b6f218542f6f46be0cd8bf9059c56dc371b5691d19cd1889e2bddf22dc96555ac5f61cf477	374	\\x0000000100000001314e11d17b7c3653b907d5997b302581dea7545917a026d387ad1fb35c944518a000eebddecfbccd8e0bb29fbf6a5b7725cbdc177a1d86ebbc6c2a17eec6caaff9bbc046faab95b2b8c7adb7160b0c01e1cddd7c1984a5bd25dedcf7368a6b95d31f28f2b7bfd361009ab091d598fd9005a1a00cbc23138677bdfd27bbae6d8f	1	\\x8f980f547c324b2854fb3d9b01ec0d7c6d60a8ee457d8c5100f51206cfb6b0fa2598fc22de4129c9cf1bf05b6c3e29625e54c8809f1cc49ac66f7b5fefc9cb03	1655640383000000	0	2000000
13	\\x75f45bc40f1d2da8ee35963efa67a5051b82abbebd044b79d1d32e71aafa83d7c71cd21152e89a35f238f5764fd5e2d32b71e76890d0da875e4716e3d7c7bf58	276	\\x000000010000000153a59248727912f14f88eb8deb36e5e8ce04d6d5afec696db57cafd76d02547139076c9ae970cb92d9cc9b90f02a9aca27f0a20f06e5ef6f75f2b68884d4cab7285910e435c2e1a7a891aa2509545ab2021605b66fb4a577a7ea04e2a7027a7e449af5611528c29a1f84422511cd6a8ca9d2eaf00b8324454f1b194f4b0829ed	5	\\x60f232a005dd07cf17213145cc9a0d6983c5794eb92e47ff7ed22b1be7da0312e0792fe49c5e351283ad05df3827160368020311b7a69b49c7aa40cfb070aa01	1655640390000000	10	1000000
14	\\x4948e408eafb5ee22f338a228ef1ada0779f9cd7c8a3964e5416f9517b934f0dd73db85c485970bbb9617405a0affa0b31ee85bc079a7a1ddfe0f6a9fcb6a15a	248	\\x00000001000000012d7cf42decfdbd7819d3fb93bae53054d489d591ae7934ab62b436b6848d1c4fc993b89b4dad2e1c10727d484672f13772d7c9b35b5ba519d0a2fe025d368db5857504a7716b969dc6b4582d946cca35f2ab6a3ed924d1f28aa82204d26f6934ec898d197f3c90e1b1de7056657803e68b6cf01f51ea8bdb341f24f820591678	5	\\xf8b1e81cf0ec2e2492289d949da6450f1d8762bec2646f22ba5031fcd5cc96c931a8c4f4e1e6fd8b3365032e16178793d4a6b7bdcf69c738547c777a6be7a200	1655640390000000	5	1000000
15	\\x93b266c53aa27144eb4e76ba3e940ea28725c169aba62d6a4ee33d2c803a36b582fa13e201c40e66dedede0ee47e453cc3c8afca2bfc9d8bdbba36e75fc3fcc7	423	\\x0000000100000001e3cfa010b286fd13a771870145abf0f8212259235d12ce358c16e5605c0d213d0c569299ff202c8d154bbf1562b3196caf2d9160be967f645991b0853a007a580c9e327a9d77f82bf17cf3af9b7db018beebb0a523c40439462cb7bc7464a7f376a3fdaae8b545f8ccdb7407d3e475f2d3346e32669f3a739b60d473cbfbbb	5	\\xa48393c4c7736e0d89365a54af90bd7c2190e29adf75a1b80e069ccba252a01ec1dbdb3c6a64688cfc5a1ce555f88e8124fc3e50883cce77feae006879402105	1655640390000000	2	3000000
16	\\x3c32bf83d1cc9eb3c1615b618b34c4e015ad7b3c81be5830dc395e0e6514fa242cde76074531be10e36602d5751a606868e548174bbe730a8a7aa51b53287265	178	\\x00000001000000010d227775af11a28a34d570bb572ddc2152b35d052485ce10645c25f23f4d1436f917a651ccd0873803a308f626e4d2c1499957bf8952c689f47c978e87ad6a45805981320e255a02c3c24765a250cdbaa57272e5f6ea7a36aac3d9fb48a52ea6748765a82c8510c06b9b081687e159a45b8ed927369c33dacd8cb31d63e30264	5	\\xc60565ef05326dfb1d3cb2584b2f7ac6ec05c3bf4944abb85b34628baa9e0457cdcafc7a99858e8fb2068c923d7bebc11e0c9f628f52ab2d20c65e496c704b02	1655640390000000	0	11000000
17	\\x5c0760782b196e39215cb555bf50612963fbd1b5ee82c0a7942cc1006210f57f94a561eb97e271aaad28de7971aa4b732b4b3bf86fcd0185cbc2162b579bb164	178	\\x000000010000000183704dcc7f71f7305b1e7ee06bb60735ab53dfca027fc36addb5b19ba7ceea8b8315aaad69ebf3a5d260f889bea9739c2891704eaae580c6bb0b19848bc0af5fccbbe161f605016d1e145674455a79c82703fa66d30994cfdac116959d4dfcfb467887850600d8aeaadf7a0f52d87876b824545e549246f4e3f9c9f5e9857259	5	\\x36d37b7dae9cdc9326b66fb95c6720456a959c4e82b4ce2a4d9d79d2d1e82f015bc0ef5206d6ca9211ab1f21de1075a65b587f27e289fb11b58dc2da671cc005	1655640390000000	0	11000000
18	\\x4f94897ac4be7925bd183ac8ceff2445646620bb547e7c4e023f904bf1bb20131ff1918b9701e53b1b06eff6282130c7dcfcb0e5f79046d3739c219a098c8fd9	178	\\x00000001000000010e6991fa9d6dc4f88e2f67f103f6c95bd251bed83c6a045dee08bcdc55bc5c9a613cf5bf99cd91b28644463ad93b10e25823d6d57632542b2ec0c47ee84abcd58116357cd5b044930406e0741d35cc19e66b0bcaf15112ad0bd383be2dd3912b2acdaac0d0916e626f3c9ed2ba4a32b50ac57d60287682ca97ef6b171ec5db46	5	\\x6dc7e73e2a872a6e633d9b4633f61257fbc88563db2abf1205bc97aa04ef50274ae62d795ac1914bd7612c79dace38235a6b2fa3f686baf62bab6e47f6d1bc09	1655640390000000	0	11000000
19	\\xcf25428ae38cde94912f9f19826ca4aea790cebc5e5642c7274fdf3a25355065e79a26f090b5d591f69e8a89f03207176eb7c9de0881e327af730c59cbb0220c	178	\\x00000001000000011630be5cfce6fbedcfc8b0f952b5b9ea9b544c56327446b3d98d24d31228918babcceebb95ac605f2fc37a3cbf3b1215e02fa4be24dd534d3853a3b294880fbf8daab3c107d87861daf3d7eefd45842d0126f4d4893500ce2e42365096c06071af100eb9bd708fce19b62125f6caa989a49bbe09af115a6672e08e17a8a40610	5	\\x6abacb3113738b10e42e1da6b43617c31aaf686fed5b0e9e92be1b2ff0cffe51ff932cbdefa6e98a8686ee1763326203dd8e2bec9a2c9e3f9b3b1200fe59c802	1655640390000000	0	11000000
20	\\x05a59555df5d6ba2ab41352e1871ca8c4d290223395153ccd2930b438cdf9012e00c52553c05499804de719f17d85cb6d4bf10d388b66ba93f044d876927bbce	178	\\x000000010000000123a5203ae3fbb0c50b9bcbd0907ecca5ad51a812d62a61461cacaf4e933a687300f6f8ee68c57f2bfc5d411b2e49ce58c200d064de348504523eb57ea351a2c38ddf4e50c85996cffb9e71802f0a054865e801583d443e9bfd7b36f5c8a1921e92f18ecd8ad9f46cbce6b320906502248db498f2074794eff94d71be902edcb9	5	\\xfcd43aa02c0c0de7d54c2b5752f1e9336499178bfe39a01a7bb0072e88dbd4f2c7245688728b5058e86c91d8edbd8b93d61c40bc92b86baf95d0a66985bb4007	1655640390000000	0	11000000
21	\\x38d18f9a4cba086242daa57f88183f2a85513b5df826462f08503fb845d5e781f5320fc322b3d9a1a6e0c7bd2e6bbbe96124657fb4099c62ee470c4db338bff5	178	\\x000000010000000174d532fe861567a5fadead64332f0da2e1a1eb6abf3825a0a3628eb7c36e6f1ab0b9094791b26088f3302b9e1cd1a2799b3809fe1862714ad98e9514195d1910841620b25568813c400f0d18ffd9bc46ebc50c65db75b9967f43ba9bba6ea3a02de9d76e6b54508204d7cfd59d5f397eb3767ee2f323b62c1893d5477e2794f5	5	\\xb31cbce594f1cda43aacb275352efe8f4f63b648f244d946c68d936cebec60968e5564d0218f49cc009f0551485f8c6ea518bcea56c5b66dd0fff13246e9100f	1655640390000000	0	11000000
22	\\xabc5c32a539a00f0a4b8f5eb0acdf40209aab636e8d70d5dc9037ec0187bee586928a919c1bb0d0107b82ad98fa9491916e43826179f498db0f435396578a505	178	\\x000000010000000149e1ff1f58615beb30b79c5dc6f729dec4fc65c6d49e10bc39d3a40a365a542a33dbcbffc3d5675ab36992abf5d31f835c1910517227a83beaac515abced74209dacdcbc07e54856832c8235c242efd5b931bd2676f2757dfe617983cd1ee483dde0c7ee2c6b8ffb5a617ad4109461fa202308295ac60e8028ca8b6c3e6ca4a7	5	\\xa10a3ed49fa568352955ced37e9c765db150a881e7498782eb646042cc67ab5357933259deac5e5c2ab7da62d27203101647ac933cdab6f35de1949d53dadf0f	1655640390000000	0	11000000
23	\\xd02142e3ec1c84eea41c1b6faebd7d567640e22f51ab5bc960003ebb5fafdeb62f9f4e8d0cc9a6b1ea7c232b928c5120ca9dcefe0193b69369c5c73b8afbe2c6	178	\\x00000001000000013afcf0eb7570367bd520da7acbb4ccc558528a305dff31cd6c782e7315468df5b1b731261d148b5c359bc298257e3f2a3c077c8bf31b12bbbb2c4e93bca9f151a51cc5b5a797bc64c0fb362e9b5716ad5417c86d6d4201008f51570f0dec0481cf0db2c4694c83ce91a343a9b39b46c49c616b1ac2686edd79784f2d3d54d76e	5	\\x9531a482a38bd1c1b7c651271043dd0c7e6da493a6ed571f7b9e99f3d2f69a4b11d52d3b839556087d7b4c09906215cde2eec6b4892f69ab8ba5816ee7aec609	1655640390000000	0	11000000
24	\\x042d69e6ec3df3f28545d6dafab2d2f5709e125558821731b983b7bf5e019851e4d0e4c3bd3a4e0b6caa60bac5ac58db86f8cbc1bc8652e7e5ab05395376b95b	374	\\x0000000100000001d6d67e70f8946dbcd30d933d857f9037e8f7c5b3affc64e1b17b7ab5a7f426a2e456929621c3cc80e062b95e8577c9b5a93b742a95d6cd5ac2a14e5f2c64ed8936ca20de8f8df3d7dd1b4aa45bece94d2041c4b26e358c881c25342b93d61b9ba917d2494114d8a22e0c4eb28063a5570bcc861c32b75ede4809304509d99d6c	5	\\x309734682e342ee38c9a70707edf45d563921cb06f54f4098924d4ea49745c3cedaefbc38f16febc3a6953488c0e04d541a14add18faab50b5bd374de1924a00	1655640390000000	0	2000000
25	\\x96934e398e4b786a44faebe707c2928ed2d39c6565fabf552fa44173ca9c12283da6fbd3ae67a5da638387d82e4655d96d6e80abb70e8459c1e26452bf7b1ce1	374	\\x0000000100000001efaf539ea0432a215af6f4d8a0483068e75322edbf73331d16a74f0cf7945cf086da8d53804d253e2cf2fdac2a8831dc93f4cabe7bdc1ca427404fd9aeb0c2cbcae9dec0e3e1512b75826f650f83ed792b3d415da5ea93dae330a7a418151df98073da3ce8804ee4eb7a4a95f9ed9470d11fb614af1b1c3e1d2f4548574056fb	5	\\xf33e8a54bafebc0530ebc9bfc2d873c09fcde80ae7fe45547ac642f4edc1892bf4dead7cfe39ce0e26442463b14f00bf33f9d6d85608ed36eafa3f538b6ec701	1655640390000000	0	2000000
26	\\xb6d2a3c3b38566c6a6cba1ce26e24f9eb91b4baebaada102ef2f2d26b9fb3f32d8a11743008018796b3b59596490d5905d9782a7b2b59f2c1172d1bdbcbb33b7	374	\\x0000000100000001604d779855f380404112809093f4bbbae9e41078d446640a9f107cc5e3956296e548e2862f15ddd10f5c5644413750ca84b024d04cce06e3d80a710fbe787a4e0a2851ebd27315b84347db0f7d7f061f241eec9f5686659c1974ea526de17060aaacfb3f2b1191caf7fc768e3eb249de6faa511fd73f9bf397f74eea0c7a2477	5	\\x3a4241288342b8c679028433a3a64c0e05f07b4c23d410b3783d5f8fd9e7d7031e02db17af4b043046025933574981c0c4fc9de2375945e0210752bf5c7ad609	1655640390000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\x0ff7a538a2664e233a108b7aa4beb14d38abdeebbe13443126bb061646fa64af25116b26038b2847bfd178f671ba6dd3346e4c9d392bd29d191728665922300c	t	1655640374000000
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
1	x-taler-bank	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x272066002ec5e5b2ead4170a9725486d79cd121990451d0eed8c37b9f0ccc296960affd10de255286930dac890a321aceb167df1ee8c77b5138773e07a3b8a09
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
1	\\x1be0980cd3e088d4b0e7a46d6ece6bf749bcb131fdede29f4822b1856efb5050	payto://x-taler-bank/localhost/testuser-gk6lkeb2	f	\N
2	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	payto://x-taler-bank/localhost/43	f	\N
3	\\x5dcc39674dd6e447dd1de57098e134cc951d0d2f10b23b3583edf607327b574f	payto://x-taler-bank/localhost/testuser-bbpholtl	f	\N
\.


--
-- Data for Name: work_shards; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.work_shards (shard_serial_id, last_attempt, start_row, end_row, completed, job_name) FROM stdin;
1	0	0	1024	f	wirewatch-exchange-account-1
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
-- Name: close_requests_close_request_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.close_requests_close_request_serial_id_seq', 1, false);


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
-- Name: history_requests_history_request_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.history_requests_history_request_serial_id_seq', 1, false);


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
-- Name: purse_refunds_purse_refunds_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.purse_refunds_purse_refunds_serial_id_seq', 1, false);


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

SELECT pg_catalog.setval('public.reserves_in_reserve_in_serial_id_seq', 11, true);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_out_reserve_out_serial_id_seq', 26, true);


--
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_reserve_uuid_seq', 11, true);


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
-- Name: known_coins_default known_coins_default_known_coin_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.known_coins_default
    ADD CONSTRAINT known_coins_default_known_coin_id_key UNIQUE (known_coin_id);


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
-- Name: purse_actions purse_actions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_actions
    ADD CONSTRAINT purse_actions_pkey PRIMARY KEY (purse_pub);


--
-- Name: purse_deposits purse_deposits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_deposits
    ADD CONSTRAINT purse_deposits_pkey PRIMARY KEY (purse_pub, coin_pub);


--
-- Name: purse_deposits_default purse_deposits_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_deposits_default
    ADD CONSTRAINT purse_deposits_default_pkey PRIMARY KEY (purse_pub, coin_pub);


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
-- Name: purse_refunds purse_refunds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_refunds
    ADD CONSTRAINT purse_refunds_pkey PRIMARY KEY (purse_pub);


--
-- Name: purse_refunds_default purse_refunds_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_refunds_default
    ADD CONSTRAINT purse_refunds_default_pkey PRIMARY KEY (purse_pub);


--
-- Name: purse_refunds_default purse_refunds_default_purse_refunds_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purse_refunds_default
    ADD CONSTRAINT purse_refunds_default_purse_refunds_serial_id_key UNIQUE (purse_refunds_serial_id);


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
-- Name: wads_in_default wads_in_default_wad_is_origin_exchange_url_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wads_in_default
    ADD CONSTRAINT wads_in_default_wad_is_origin_exchange_url_key UNIQUE (wad_id, origin_exchange_url);


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
-- Name: partner_by_wad_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX partner_by_wad_time ON public.partners USING btree (next_wad);


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
-- Name: purse_action_by_target; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX purse_action_by_target ON public.purse_actions USING btree (partner_serial_id, action_date);


--
-- Name: purse_deposits_by_coin_pub; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX purse_deposits_by_coin_pub ON ONLY public.purse_deposits USING btree (coin_pub);


--
-- Name: purse_deposits_default_coin_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX purse_deposits_default_coin_pub_idx ON public.purse_deposits_default USING btree (coin_pub);


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
-- Name: purse_requests_purse_expiration; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX purse_requests_purse_expiration ON ONLY public.purse_requests USING btree (purse_expiration);


--
-- Name: purse_requests_default_purse_expiration_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX purse_requests_default_purse_expiration_idx ON public.purse_requests_default USING btree (purse_expiration);


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
-- Name: refresh_revealed_coins_coins_by_melt_serial_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_revealed_coins_coins_by_melt_serial_id_index ON ONLY public.refresh_revealed_coins USING btree (melt_serial_id);


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
-- Name: reserves_in_by_exch_accnt_reserve_in_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_in_by_exch_accnt_reserve_in_serial_id_idx ON ONLY public.reserves_in USING btree (exchange_account_section, reserve_in_serial_id DESC);


--
-- Name: reserves_in_by_exch_accnt_section_execution_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_in_by_exch_accnt_section_execution_date_idx ON ONLY public.reserves_in USING btree (exchange_account_section, execution_date);


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

COMMENT ON INDEX public.wad_in_entries_reserve_pub IS 'needed in reserve history computation';


--
-- Name: wad_in_entries_default_reserve_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wad_in_entries_default_reserve_pub_idx ON public.wad_in_entries_default USING btree (reserve_pub);


--
-- Name: wad_out_entries_by_reserve_pub; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wad_out_entries_by_reserve_pub ON ONLY public.wad_out_entries USING btree (reserve_pub);


--
-- Name: wad_out_entries_default_reserve_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wad_out_entries_default_reserve_pub_idx ON public.wad_out_entries_default USING btree (reserve_pub);


--
-- Name: wire_fee_by_end_date_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wire_fee_by_end_date_index ON public.wire_fee USING btree (end_date);


--
-- Name: wire_out_by_wire_target_h_payto_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wire_out_by_wire_target_h_payto_index ON ONLY public.wire_out USING btree (wire_target_h_payto);


--
-- Name: wire_out_default_wire_target_h_payto_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wire_out_default_wire_target_h_payto_idx ON public.wire_out_default USING btree (wire_target_h_payto);


--
-- Name: work_shards_by_job_name_completed_last_attempt_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX work_shards_by_job_name_completed_last_attempt_index ON public.work_shards USING btree (job_name, completed, last_attempt);


--
-- Name: account_merges_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.account_merges_pkey ATTACH PARTITION public.account_merges_default_pkey;


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
-- Name: purse_deposits_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.purse_deposits_pkey ATTACH PARTITION public.purse_deposits_default_pkey;


--
-- Name: purse_merges_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.purse_merges_pkey ATTACH PARTITION public.purse_merges_default_pkey;


--
-- Name: purse_merges_default_reserve_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.purse_merges_reserve_pub ATTACH PARTITION public.purse_merges_default_reserve_pub_idx;


--
-- Name: purse_refunds_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.purse_refunds_pkey ATTACH PARTITION public.purse_refunds_default_pkey;


--
-- Name: purse_requests_default_merge_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.purse_requests_merge_pub ATTACH PARTITION public.purse_requests_default_merge_pub_idx;


--
-- Name: purse_requests_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.purse_requests_pkey ATTACH PARTITION public.purse_requests_default_pkey;


--
-- Name: purse_requests_default_purse_expiration_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.purse_requests_purse_expiration ATTACH PARTITION public.purse_requests_default_purse_expiration_idx;


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

ALTER INDEX public.refresh_revealed_coins_coins_by_melt_serial_id_index ATTACH PARTITION public.refresh_revealed_coins_default_melt_serial_id_idx;


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

ALTER INDEX public.reserves_in_by_exch_accnt_section_execution_date_idx ATTACH PARTITION public.reserves_in_default_exchange_account_section_execution_date_idx;


--
-- Name: reserves_in_default_exchange_account_section_reserve_in_ser_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_in_by_exch_accnt_reserve_in_serial_id_idx ATTACH PARTITION public.reserves_in_default_exchange_account_section_reserve_in_ser_idx;


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

ALTER INDEX public.wad_out_entries_by_reserve_pub ATTACH PARTITION public.wad_out_entries_default_reserve_pub_idx;


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
-- Name: wire_out_default_wire_target_h_payto_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wire_out_by_wire_target_h_payto_index ATTACH PARTITION public.wire_out_default_wire_target_h_payto_idx;


--
-- Name: wire_out_default_wtid_raw_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wire_out_wtid_raw_key ATTACH PARTITION public.wire_out_default_wtid_raw_key;


--
-- Name: wire_targets_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wire_targets_pkey ATTACH PARTITION public.wire_targets_default_pkey;


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
-- Name: purse_requests purse_requests_on_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER purse_requests_on_insert AFTER INSERT ON public.purse_requests FOR EACH ROW EXECUTE FUNCTION public.purse_requests_insert_trigger();


--
-- Name: TRIGGER purse_requests_on_insert ON purse_requests; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TRIGGER purse_requests_on_insert ON public.purse_requests IS 'Here we install an entry for the purse expiration.';


--
-- Name: purse_requests purse_requests_on_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER purse_requests_on_update BEFORE UPDATE ON public.purse_requests FOR EACH ROW EXECUTE FUNCTION public.purse_requests_on_update_trigger();


--
-- Name: TRIGGER purse_requests_on_update ON purse_requests; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TRIGGER purse_requests_on_update ON public.purse_requests IS 'This covers the case where a deposit is made into a purse, which inherently then changes the purse balance via an UPDATE. If the merge is already present and the balance matches the total, we trigger the router. Once the router sets the purse to finished, the trigger will remove the purse from the watchlist of the router.';


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
-- Name: denomination_revocations denomination_revocations_denominations_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denomination_revocations
    ADD CONSTRAINT denomination_revocations_denominations_serial_fkey FOREIGN KEY (denominations_serial) REFERENCES public.denominations(denominations_serial) ON DELETE CASCADE;


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
-- Name: signkey_revocations signkey_revocations_esk_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signkey_revocations
    ADD CONSTRAINT signkey_revocations_esk_serial_fkey FOREIGN KEY (esk_serial) REFERENCES public.exchange_sign_keys(esk_serial) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--
