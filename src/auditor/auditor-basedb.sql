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
	    ',deposit_serial_id INT8 PRIMARY KEY' -- REFERENCES deposits (deposit_serial_id) ON DELETE CASCADE' -- FIXME chnage to coint_pub + deposit_serial_id for more efficient depost -- or something else ???
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
exchange-0001	2022-06-13 14:48:03.52293+02	grothoff	{}	{}
merchant-0001	2022-06-13 14:48:04.415212+02	grothoff	{}	{}
merchant-0002	2022-06-13 14:48:04.801823+02	grothoff	{}	{}
auditor-0001	2022-06-13 14:48:04.927667+02	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2022-06-13 14:48:15.100362+02	f	06aaa21b-4c8a-4dbb-8b3b-73097eaa6f79	12	1
2	TESTKUDOS:10	F7NJ4WXVW42ZQ1CF4TEMYVYRW5Y9ZPDKW081324VKE18NQXFP9ZG	2022-06-13 14:48:18.680711+02	f	602e049b-6f56-40e4-8c31-ba908f9f7a46	2	12
3	TESTKUDOS:100	Joining bonus	2022-06-13 14:48:25.701068+02	f	ba9959d1-0539-4744-9c42-d146bcccf48b	13	1
4	TESTKUDOS:18	RDR8ZB7RG83VST2WD09ZQTMCQ57CAZ19JW243VKVD4R2N65977RG	2022-06-13 14:48:26.366395+02	f	47549c0e-ee71-4080-b117-31fa79a4ff53	2	13
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
f0ebb7b3-febe-4ebf-b595-952dd60e2211	TESTKUDOS:10	t	t	f	F7NJ4WXVW42ZQ1CF4TEMYVYRW5Y9ZPDKW081324VKE18NQXFP9ZG	2	12
ab6e110b-0aa4-42c8-8ff5-22e2a016933f	TESTKUDOS:18	t	t	f	RDR8ZB7RG83VST2WD09ZQTMCQ57CAZ19JW243VKVD4R2N65977RG	2	13
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
1	1	17	\\xa55cb0fc360dc1111da3b17993ba8ed714a2b6a2b17b13496a05c24e4356e294c751cdb8ddad9cb8af0a0953bd74faa4d33901d586805589966d47347c900a07
2	1	111	\\x4ebb4b49ef772018351366044b5197d8e907954ac1cde5a96379032ca4f5e77e0330d88642367012ff6cb272f18cb5962af184979132cf3568a61d41e4783101
3	1	403	\\xc0ef9350db16edda222394f9e6021e9c787153396c871025f2877d5e8b4127ce95932a83a1d15027d1111e49deecd064d314e84dfcc6512c756130a28948490f
4	1	114	\\xe6b983e831e42a1f1cf48366536b23c8d2d41f9d3f8e12ac9363687ada7efb06ca93f1248e969913e28a509e8bdf1fc95282a343d6cc6ac03af9323a05a40108
5	1	23	\\x7e33a719b428a4402ecc6ab41790b8a06dc195e9224d2ec6e2f8d78c4d52671bea36ef6d2ecb21240b6e9b9e24074b52ebc103225fb2b58ea4d8ad4c950d1506
6	1	124	\\x0a1e9f7e39648714b8fb9292abfdfb137410fc3d4d6493dd36792fede15f47b29ace0164372a167841659dd692d1bc17f5e5e9fc3ab5facf185c7f9cdda3a50d
7	1	304	\\x685ac6263adff1309a6a6a8d56c35958a28cb40ec2c0ddeebe40db6ae117add89a6e92a072d028638a4bff66316dcb9eaf71690532a5c2310075d866926f0601
8	1	328	\\x4045d02382eae6d929d1361af843d52a3089e34c6b209f4e52892c08edb08079ca9a3fd2bf5f8a7b075ef0db98eb1a68f68f88aa22b3a83dbbd11d9e3c895a08
9	1	412	\\x2ce7286dc5ca6ca7ebde2792927200da8a68b2558fabef8f6a402e6b547bd9a017921bb6575d796988523516f11503a7306faeb50350745b3bfa3592de112205
10	1	121	\\x92633ba82b847d533719ee5b6c10c399830746c935ab86cd9f306f0dbf3605a1619fe830f34ae0b1b1dac47d5e31ffa74af4b480a9fb8d8c689b1327e4426d0a
11	1	167	\\xcaecdc92b2edd762edac8b7a1fe14b4ec17f9cf0c333df802ae0315190b6425ed3b20ec2fa09e9a8f9b750df83cdac8b08eed6a0f26549c8bec59d411fde4501
12	1	383	\\x36a72c538713d7825eabcbffad6f828e54c78ac3daeb9809c117f461648b9033a2586ff6a2df21c254fff8e547f9a63e2030eef7315900eef8a989d43e23ea06
13	1	122	\\x9c9cac586692a7c1bcaf50031f8e28fe9f891b375c2f38aa2c938f68fdcc18e542c16c784308598d08a2dc3d0c6c0d1ac0eaf4b2314e3be52087d67d19567b0a
14	1	415	\\xd003e23151dd77b4c86ebfb770bf58ec1ffb07139a8b2ac56a0e9a3772d986a060159c6210f43b9e80131cc0c06469d1308ed13486aa7a32c9b2b2ad052e8c08
15	1	45	\\xf27ceceee958f93ece0e3959d78a2d20c8992fa2a8eaab8046bed20ed64b8c089932b87f2e55a3d25ef0dd0ac3dfb8c179546b0e6538dd6894ccd2a79e989f03
16	1	347	\\x3a7718445fd062159c444bcd7717fe3dcacfe38a0d042ac749792d6a5feb2347670bae151b75187ce78662f5143f0ac30db03f032efe03caa397246bdeb87809
17	1	57	\\x9e0466196ae509db21989cb5586e11d69387e11b62b9b848494a40afab6d07cf89fb49868cbb62f6c6a05a3422afde21610b15840fe1771b915d79a37def1408
18	1	87	\\xda47db57f3015e35755e0a9c83e5a65b7b1e94e1bc9ca83b7e7f95e7d55bd8a83ddb23dd37191d32b2d31caafb1e6a880730d0d82998754254a4fa1b5e5d2506
19	1	99	\\xa4b8716103f3099695d74ab44e6c1a91ffcf4c18041e416bd14e48426c67bf001606b37a10f3ec2e4aed78edc3913fc5f5e663f0f61c7c142d7bbfc32eb2140e
20	1	174	\\x074dbf8186aa9cf9dc3f0a2960f897f9681ddafcbc029aae42c80df04513525c75270432be78fa294bcf25fb0f1a9247cd973a0142893124e57d53656f3e8c01
21	1	203	\\xa150c88c6911e08b9edf3122bd7de3dbbc5011a79cf98dd665cc356e0fc6f6f3864db932baa8e882e673b61745a7084faf8d01f565f4e2d4da38834db070090d
22	1	134	\\x230b89a2293f80d03747dff9f77e6dfc5af2e6f6c3918fcbc14c92cf04000b918397880448ec330fe0104c516e7c46dd800130b38f6356e62cb3f7f25d49ad00
23	1	366	\\x4e151b4de254ee9cc04fca44a96ae91671198bbb9ec4f52e65eb79d7046d992e911c9f1788b6dc2eb2596870937da4ab3d205d3d53b3763f740124a26f09310f
24	1	380	\\x7ec2791315c393cbcdfd5fd1e21609862157f040d839f360bf7da514c453d8575cff68485f15a5934020adf22b983950c5f15c11786851cb5087be16be6da802
25	1	326	\\x7efc6bd606f71450d2b2e4301f6a307b38f1099d8b4a65b078e2ff0767a4bfb6c29d4715fb92ad2073887e28506b84d943e99b4ffb1bc766c49b9b37038b6602
26	1	321	\\x00f1c3558cc96713bfcb60cdb7951b7d10f56c3016387194f347d0c50862e615c9ade540fd33a34ea2fe32e8a632480b8cba8a4052effee8a4aebdff7733590a
27	1	126	\\x1094e2adad81b56d5902b98458225c8c222b01a370e25d5aa705692af3c987a690b864d1dca6d539f8597172b31ca4deda67c1821c9f32d0864b458e46f1780f
28	1	225	\\xb2d8851b665fc080c6658c631c1ef9b6736c3ecbd3b9a27ef3bf1a7e4bd14cff20b356415112451a9a4bfc7d403e2a6b7084ae295b9b31bc1a0582c160c5420b
29	1	201	\\xd677a0308c53caf6c09e3622ef3fd21abdec93294002b8a2e49f5808020b5f855ae07ddf6d45e124e97d93212ad4b80b45ef401f8abf82cb3ef6cb89ebec6f0d
30	1	255	\\xe98c71f169fc565128638e5943bf9e31f3c2cc589e6232f49fbfadd45dfba632aa6136055e9b04b1215e8e4fb49faabdb95ab027c22e781e73706452e07ad709
31	1	157	\\x2d07b404f46f4cf993cab6968d8e5937f63c147c20445fceabd57c69913166abebac485d743503c16060c39c14de034fe7b7411bc3709f1e6cb55fea5c80a005
32	1	181	\\xca1e8ecd90827705b616643ae8d12a4031dfd000d2d3361b43740e6bbe96f74d55c1543623fbf20c3c47a0c6d285b47fae1317c5c038d8f327421e26a8c75907
33	1	273	\\xca3616557d3fddf0eaa317a871a4b91b1763b41477a221bad1e28ee7ef6ff2fa1d8df271bffcc581a68a25b98202a42d88b8d9525c4a12887433664a722bbb09
34	1	323	\\x498e2cbdb7e50cbd2ca9b447a48fd1d66d066e6ac7c5f33edcbe8d0fa39a0a920f554dd3a3fde40024dadf3e30b611c2753d426f6f06bc2bcb1b0ccc5b6edc02
35	1	267	\\x81ced426c233068ce6ebe1e0484baf5b74b9e2bd94186ac190d764262c20caf98e94a5c4d62155810a33333a700802a5d034bd1e8005ee173583eb3ed810370f
36	1	136	\\x70f2ee1a6fea381f83302c24e943903d8d525cbe1a6ef8f933611d560d2f60ad394b64f1e927fecfa99f974da14410756dfd803c06a1400c7e9f51f311a6cc01
37	1	409	\\xecab1f3c1b301a429341c321f898b6fdce3188c8364cfd005bd31c55918eaa2cd51b91ce558f7daee4b2e32e6e10ad2230d6efa7db975c405d30cbe0b1e6ee0b
38	1	115	\\x13d92859de50074144bbc3f7af1e1f0acf272ccbf8e83210bdefc202da6f8b1b14174419ab3357df996b04a05b0a28127a79dede383a292a7ef2016ada838e01
39	1	413	\\xcbffc90bef63699c5b0d4e22b3c4f647c59512b42a5729205ac9c61dcd332e13d1349ebb30e70960cef018e004a6a47c54f7079dfb484904c899cc9b8f1e8f0e
40	1	55	\\x31a7f5a59fb3df851e54d539e0ebc87ce86b5689aa3f7930be3bc5f394a38c1b1fd470f2a0d48b188adf1d0141318f71b14cfd458683e8ec050747e398c26701
41	1	259	\\x2047dc419edee54bd384c1b9da56e724854def36c71fabb1a404da2eb254e97ffff50aae28800c85cc7efe3092914334752d58d70215551bb7bf79c94cd61d0f
42	1	166	\\x3cf32a95e9b38f1afb2a1eab22d340772e10e0639889acaf77599e2f842b7cb98b7af9c342e9e037024c8ac1e70c604c8c6428cc9aa21bfafdb98ad3d6dd860e
43	1	16	\\xdbf3ea565278a26b7f4597b200926842a80f4eaa8846afd5a10afa3aef26924daeb18814a14be4276d39d41c567a9165d7e7faa239406ee070a486f4d25bea09
44	1	90	\\xa538acd6bb499a728cd010b7dfd4297c86d02bbf2e649df43272b1bf597f97d44ecc8b6355e1660999d71bdddb54dc0474bbeb8ecdfae50b50d5d141f0e18301
45	1	365	\\x9166f6681d90019c043f422cc2b96e5b878157316c7074bf60be1c79de5eb6d53a8472af9cbddfa05f582a1fac8c655277be3330d0ccfe23aea41c6c22fefb05
46	1	185	\\x27443e6449d00acea4016053d16224cbda412621f11b104023a7f282c9247cf252dc5be6f8d3725cfdb8539801a3a66d221aa4851d19f8e087865a48ed142c08
47	1	343	\\x84f73023f9c776aee43bb3f781d31c880d014f68f5a85309c28109bed24bf99beac709103ec810126875e6066fc4e6ded12965c9a89752009b317556dd91dc01
48	1	60	\\x49bc4653ab4ea723982d6043a67b71decda75485539510d8d80c17b781aba728e05a4d20ee87938544a0bef99806923583d14ebb8c4aa766186cb7b5dfb48c00
49	1	159	\\x7d4c06a6552ed1765431022678abb4bfed186e920eac761c8a146075e3594d5100306a6071be46affe6f05d418b07a2448879df945e60c6ba8b704283a6b150a
50	1	37	\\xff70d5d989e83642c2919335c77eebb8ec89c189b002267d7fa1b8d76a8a3c4828ffb1b82c55a5fde733166ec47834579dd82a8c3a0b690f7bdcaf1189394c06
51	1	300	\\x371f5bf2e1ff6a5af6f89af9d0d33753f2e1f7c14b4465acf324e4456177cc1770233e8e89f821b26b32a3061e8212247cabdd840584fcbb90aa1ea6cfdb2203
52	1	210	\\x6b94213e08628ee19cb1e42c493899009f8c8253bf5268bcc42a1b9fa0701745914de8d15765bf654107913ee928fa4db912f02252cdf10fe6d4d3eb2edc320e
53	1	408	\\x60a2e5d784d76e09cd0c2d8d8964846333d1b662683c4a36960ab2c66f5cebf21a82fa6e8eed2e5bf916ac3efff85d47315e0fffd42dd23aff3130deec748b0d
54	1	195	\\x8b079621cb578e6778466bc0b38ccb95712b6ea988cf5f8ef8cc1d20ce8d4ac085b62bce2bdee880478e7f15d1e6db201b46defc7d13edab9d792ecc0ff64b07
55	1	202	\\xf6adf3dcba7be1499498e4d2e3538837203b15f2ce845ea5c4ca14086365e07387b3551b06ee388f4b6024a8568ac027c899021370715b6e3de895a880abc10f
56	1	220	\\x7bdf413e02324b215a99c62f7883a773542653110b0dba2afa1d245d0ddfe45ab09239d9f67a6ce964ad19704482bf8f35630113607ced9ca459d0aad9169805
57	1	283	\\x4c1a0bf7cc2937c0ba0d5aaede0635031101db124f15b74eddc3de3f39316c1cebd4622692699e68f085bb928c1deec11506a0e696124838431b0f345c8c9f03
58	1	218	\\xb85900433688d1fe6d30b05e33598056eb7e7da8681933fae83241997a6291932832c8a8b4c7305b93f9c8e75e874ef34b713839b02d6fd539f372bf61d4c009
59	1	262	\\x36f3b48dfea7711f05947b9267581aba29aeb40e756d74aa7f4345adcfb6c58a051b0fab744db8b22c66fea87c4624a81afebb9a5d23edf20deb27c1ae812d05
60	1	258	\\x18adcd86eb3ad176dcd8de7581ea9013fabcdaa7812ea7c0d387c910c1454a1bb40e5241d4332cee465dc4c41eeb50aa0de30f1cff6258c84b82009bb4451301
61	1	231	\\x280df5edf39e19bcde2af593cfb31ea7b149f82726feb3afedd2284d77904d0a0c2a4b8cf6ec802632010db2f0eaf2612156303f2f93ad2936f0ead5d30d9d07
62	1	385	\\x3c17d19eb0e4e02f6492f5e7912d857277728d93d5d5c36b3b94f319ae0ca45e8a97075fd801ccc9b1e6c920fb660731af80729dab14a2bc59619e19f9c16102
63	1	140	\\xf76e2b24f9e32d5215f5e6b507b9bdcdfa6fd50c9ccccaa73ebbb320c07c52b1889b01ccb37f68e6b521f4ad43e55d3e09346d0ec74e88bda092ae0e34958007
64	1	270	\\xd77ef949085c6f6a47cdcf8d4f57fd81f2b6085944324f745e90304791fc8b60a9443682fffd37e79c4e2b9ebebc8dcac99bf8ce3e488fe5a28d6eeae58d880e
65	1	197	\\x1516ac11e4b4a95121ea0736236f945ae99fe40bbc59493d5eec04fdc2e03ff6176ac8a6c609fb802d354515a9a11d25733fe28254d7ca4e165176a83f98de02
66	1	143	\\xe588d540dbf063cd64df9ea2932cf869828db6a16042857155719804e4998a79664afb7ad9f5fef8fec72dfc8b44b73fff6005dd543c131d47287c5a7bb49009
67	1	48	\\x50ae7dfa3dffce40156e578c81d011542ec9887f87c3e148f30ad7181886fd852bef0bb332d00bfcf68df9456f5afe170de992edbbf624c5e2e650f1d66c2501
68	1	180	\\xe8c26f853a8581395c62fd085d42ad7cef292fbaf36f99bd18c4f3d82f3a60eb85c2036d26cdb231561d74edaaa70ac0435ae66fa44d3f805a6660189f390f06
69	1	316	\\x22a86f6878462922aa7a8a9ec0c706852cc7ce61d8ef4411fab8b5017a6247d0ec38dab7e9062042131580ca84a0d446e3390330a2736fba21b648bef53eff0e
70	1	230	\\x2d6816b72029e9636d4aad2d1f5a63b08acfc0bc8372dba2f373b82ce5b0f20671dcb3112bd4ff8d94e465f4fe12f170f6d4a044a340ec8ecbdff45dbbd2f509
71	1	356	\\xd263a3ed5112fa4e55d23bdcfa1ea357ed763517a00437bf48062ce228f050b133ed7df9ae7ce7d4d87d84b3568d6da30e75b12be3a8e36d9c61886b9ea0880e
72	1	2	\\x13ae2c484ae232b119567d46f4a43f5b659c8308cb405267022d9e82311da49132a84cd9c71091c9a0ef999d7fe5348fb89d44da96b35d886a1c56c36c400d04
73	1	172	\\x3783312b73662ec30cebfa3f54aad6b21ec65c40e5fbb471278d8f833271282af669ac60f98a08308dd97bed551dcdff8f0afce6854e7ab63b363d115e8b810c
74	1	144	\\x3a9f7ac3022586e85231b2b085a3679b5b370931f1bfc986bdac804149b5504f511e4b2d25cf6d146331964bb3a2e5fef24a900a206bfa829f7ebb6c1e0f0b05
75	1	221	\\x0e7ce21809eef34ea2945831c50020c49091304733fe2d25bbe8050cfb24871f789b60664cba8b8a86ef9a0b98e2e0ae36a1a82dce66f7644bc6cead9c7fb20f
76	1	104	\\x97b87c7538b561553ccfbb7293a6e2d7a6a7b342198d548398efd7eba1de7602d02a7b55726e6c34da7bf5e6839b62ada29d379cd12e80e91c41f801a8c2f507
77	1	256	\\x817aba618aa4cc6ac0ea92b9dfcc081352fa307bf1164a597b8c869025624fa9ba42d420ae06a74f4f1ebdbb09840b9a5e958c057b2babf4ce7e900cb189f409
78	1	329	\\x8b3cf50ffe20dad387b4c156321c51cedbf5c2045431e70517105aecf234cf22a9b4aeef02b18b6620c61fb1ed68f1c478fdfc7cae55da101fbce03c731f380f
79	1	95	\\x1a06dd5cd4cdd53d45cc329dfbef488c1f36cd5ce484973e570d6f55d492feb91c29ad704f8fea61c8bf2b082309799f6aa188b60734af499f55f43f3b13550c
80	1	375	\\x4fc92d81ee619dcb74a5323218963a63e6ec3416be4d6c9c926893da0253aa36064d42af25aa6bad10357b0801e1b757b20a7d107b17852598c2e48fd13f050b
81	1	228	\\x7b539a90e0b23c8d109b1f08ec0f1443554ce6ad10498b38e78dbcf8baa64bbf0d3d85c4c56b4d59d2736cc75c4281ed8ed7ab27f68e7f50263b27658f770003
82	1	127	\\x6978e720c9688ddde13d78758ee57de2723a90818c565f4c0f492c0fa259f8c4ccb7b7e91a931d050218acbf9e67b6da486490d4486a21671da97f3baca2e202
83	1	379	\\x081965c88fea2fae207b8006079860bcfaeeb94664cc9c16f3a75b47c4bf9e25a96f17f4c0428ceabc6648091560dab25134a0badf0e644428d5f61fec06ba0f
84	1	62	\\xda0d3388754c8576ff4f7ab7184a68b263a42ece269fc23995d5e1a91d31fba3f56b01c91e929449628a3048a169873b92d432fc8e3ea896c2649118dc38e405
85	1	14	\\x2730767ae55848f1a4c53eb087d69016eabe0ff2a1b299e056082666a332b161f6956c5c3e77d46c965713cf7ad8a95e5724e26c28d7dfc4a43f97cb78b70d02
86	1	278	\\x90b58c9dfdd7f6eee09598baad09fc531b08bcf800bf8fa0b79e3f350d3c0196b2c93951d6749b5791b61bd6a0a42ef99ae41086231c8f4343b861d564be1201
87	1	253	\\x5a4c2b1d32015969b7f3bcf7f1baef90dc7c6d2fb696fa2132de97e8a58f72bef5ef2f5926c988d2c5f177b9846c8170e8dabf40b48b72d911a08d0c12b8c009
88	1	399	\\xa83d99b6182dbb8d62b1232f6bbba330d6bde738ee526262b4a049a558cd2ac69cd831c14a5cb83b202c6966a9dfbe85aa6cc8c68b8f61b28c57e4f3fe5b6c02
89	1	148	\\x52d0340170855dcc7bcb4c088bff932517e0f009b0c3b3347dbc0ee13d011adf9a094d4d8704c37a1f6ba93a752b2675279a2e9e21f3a53c12a8169e2eaa2a00
90	1	208	\\x59cfe07fc3edab8e0a8094435abdbc553549c2fa845992735c95e50d2165ddd446f8eafc51a86a8df6d7f09668c85bdb95c263ad3184cebe47cbf4655757d90d
91	1	290	\\xdac7678513682af203f2a1185b86903cde887005e85031a9fed11f4e8f81ee8beb75011238863db6f8cb2ca719664457ce8a1d7eb512b483967c0dfb273f6408
92	1	421	\\xca420b0359867221576e0d2ea20a628839f9cb825d3a8d5405f795d89c83b54bdf3348e5c67ac32b07c3a8ed403174a8b6fbc3e617aa2722477816921455930f
93	1	146	\\xb2ab50f0c956b03fabeab2a98ac598c045c8f32b0206ea25d98b0bb0bd4cd035fced702a9a668c1b5700af9e23c4cacf8982a97b7ddc0f12efd7736bc86f7c0d
94	1	360	\\x6482d6533603f1f666e9b2832299672e5f4a63bbc264d8dd33d211dd137652bebd64010f9c03b514d07bfa1b1902b7bd202e7f45090c4d9ca819f087321c750e
95	1	105	\\xeeec187aab7dcc4818e358f9eb4049f535220b52dce27bd8743e6ca02e6fa94549380a347eafd1789e367b8f1633a521defa3772c40ff2d40253809d10e87f0e
96	1	310	\\xdf3247dd2e44b6c4744280fb6e654d5dbd9dfe864a7fc8acff2dc17eeb9acdd60aaa1061d2984691bba4a9f7694f9838219bc65baa072c31debf40909469c00a
97	1	101	\\xbb6fb94ea272f772d17a7d1577b640a8e60ca9d6494de1eb122a807db8df24829386f7de06c5d40c6e4567f466a713a2f34e56a7f30d3654fd71915896cb6508
98	1	405	\\xcb6ba0a728d68304c543d36119f47b7ed29886cde7c009da4dcfe8a85ca8c3805b558dcb299d601aacd43a24a13dc3f909dfca3f5f2a64e36a5e7c37c9b16508
99	1	393	\\xa4379c6844e53c548d0f51904802a5885dcded464ea23dc797cb97fc14f265993d4db16b12f6b3c43850184ae3ae900520c92991fee1acc1da1451cbc0d27109
100	1	38	\\xd8c363d47e42c90911f99ee295608f0c162a5365ebc15134f5cc6ac601968bf4580b4bc6d5778ddc9df30860af68bd3b023b8f153dd9be10dc6957bbc907760f
101	1	64	\\x32d0693af62af58d5fffc942ccbb34967dec597494afb6ead018052f4f096259fcffe067ffb5cb9998cfd5cb18b7601bef060543ebfc8e77ae7aa336288f9f06
102	1	91	\\xf841b206b90ba57f3d48655fbc9185edf74666596741eb93bd3e95f53d78ebd6a674437ffe0b18f3c6c9160c4548a9a63566a5b95e2ff9e40338fa87a06a990e
103	1	116	\\x164e0e95efcffc26d4b023fb510adb10035b6f90e03ec8c001c50669267758bc80aef9639fdf915abc19bf6dd5c6d5862fdf104930ed592472e49a5d539bd00c
104	1	338	\\x81aed6eff0f85f084463d53a42be4d9391c6543da0c6ec3c2fb570cbf5a0ec0f654a08fc22ea137482ed5210d64f131f18133fef4111cbc2c43d8a612128ae0e
105	1	402	\\xe77001434e48a31e1178f0416944f55afa9c28834b8f7a806af55032794dce59c4d3d3d13befcba16c66874b603f088021e669239e30a2acd38df627ab05df0e
106	1	106	\\xe29f02247781fc1b6a3a993eed7b741fb0dbc05babaf65b8c4fc49338a1e191a3bbb640aa861158535654feb3fa00bf75d689d750faf8e1b99fff95c0e70e301
107	1	66	\\x30924f434c5a0679cc1d93fbd4716fec48bc22d2e2b9fdfae6224f920600bed8a6ab8e027376fe4c02072a21fd31d6f552a6a65114bba990e5e92629c5d61908
108	1	229	\\x62bca1586507de742987ecc90000a99013eda3397e2d7176c1a85adbd0ff0543fdc1b7d1d45e62ac2864b388759b74f7f25674688c9403504f37a0ed63ffe000
109	1	242	\\xb75d6b9f92edfd6a1889279360b34810f0643ca552afb8285a41c4b527f8a4d16ecf4109a1f0e1f7dd6fbeb4522548427fc0fb5891aed1eae35e8ab2506f5001
110	1	327	\\x7d01ce75b8331691f70c85a1b968039d33b8672347d68b9a64b5beab09aad01189b29c30d17e9abcf1615d937e34f2f8c46974c83fe9e1201e6451f85aca0403
111	1	322	\\xb4b3afb31700c0fb679b462f720b90fe4e2a665947ed618f339836874dca0f04e9eb3faf7a9357d4304fd1252a96aeea00eedbcedd49015e7325e7dda86baf0d
112	1	337	\\x33c22674937b85ec9886a30e1eba899532eb5ac9fc1df2383394e9e413733aa7701352e04df42224afdc2299b87c1fdfa9c93a99e3797e65cebcc40734f7780d
113	1	370	\\xf0fcc2f5310628367d68614740858daa08de873fc1e0e7c4b269fbb975dc295eecab7421a01c74ac0e4b3d776c86eb399d2a906d27194582de3fb4f0af82a70f
114	1	162	\\x37a3cb62733be183402166c3ff69de1afd934624f6754003338eb7c750a7ad9d550cae4c7d9ae03cf90c025e30ba7f55bdcdf75b7b39b5c6acfddac0fa509003
115	1	313	\\xe75f5bfcb44f749aaac62561fd89820db30c9d60be7bee4ab124eab7818d07fced544a79955f2de58b2a27e1979611e609df93995284d10cdd3b9f1b6fb0cc06
116	1	131	\\x79c1e95680b045976c63c0e44f229b35ab7fae4262bdc2652e916006775b657a8d7c89969eff33b2d0d8b57d8816c8473c9335f1eac2cb6003248c512242e60f
117	1	47	\\x734486f41dfb710e05c2b0f6a9c4ff8ef9558d34acd799d5ea8b98cc5be0398718a54e163e2dbb530939e0d4d957bb5e3c1b6c850d48ca32da5089cd586d5806
118	1	13	\\xa196aed164aeda5c7bd89657a9652147779d29a47a073857437c87c80f9e9bf2a24dfb707b18d94de76ac46259979e29f3cab41d0c3b2e634be2b57c30815a00
119	1	215	\\x2f5304582227cc53ad8d5fb3a57a24fa69b554c08708791953ff8e7d897a6fa962023caf9f4ba3b638ce5d662ee8ce29e52b456add7e7d491b154bf4b467a50c
120	1	369	\\x7e67b62d6f89e2867e153abacd230cd56c73d678119b914ec15a3d8c1d0a9b06469c4ecfd8c884302e8ecb55e0ee88d9af76533c0cf648de0e61443e676cab05
121	1	263	\\x6d2fb336bb1fa94fdd02b1871ad4174fb86d63e68dd9093d1dd9e026a531b852db5c64e0d15df6924c131b2416da9a7b6e38580c8a2945ab125f8e7646b0030a
122	1	88	\\x6e25cad1814024c66006c99c8889b103226a28f8d839fd826c14ad1d0d4f390f3669a1c9fd9c2042a27901b91596e5adcb7367329a71944740a4ba24d5d0e40d
123	1	246	\\x4c284ca60ea6354bf0fe3153fe97ddf749e62b7acbba25fb116e5dd768063bd1de88ffd1019537819c922d4ebf055d24a0ade18348f754f59df63a531e9c7b05
124	1	397	\\xf56d3f392ac650d7b582b236d88eb84faffb7eb9c061c603dd633deace725ceebc8233ab8fc3ac8b9dc15a19e453a1ab7630013dfe3eb76e6f265446b6d2030a
125	1	216	\\xd3d8916488b884d0de061ddfb6f075840ee01bb4d99c51bfae9df891913a4e112ab41c4c08152885f83679800286d4787b24aab468c6bff9056f41633d5f8c0d
126	1	59	\\xf630b4e4224df18893fd0d50eec2b12fa342ef36078cbaf2f716cd240cfbbae49d8f25ff7ba8935fa00b207248bc3a8d465c715c7ff6633f8aa821174f2eda02
127	1	334	\\xb3a239c56e44572ad4ccd3ddd9a7be4ac7e69487465996888c681999353856a2198856cb78376260706b107565eb2ea3514ec51aa1e2a5cde46ad9310150f50e
128	1	152	\\x5a4af8ff06a9a0c25a9cf80c797209d061534fe6cbdd70e2195c3e72aad89ae84b101f843571eba8fbb822ad8cf0b7141121aababdded422a4b6c4e78069ee0f
129	1	299	\\x6fa6096710de765d863cb5d1072d1c74a028c1d4eec834829e70dfd30f33b6c65eb1c1a12b3bfc07bb5e848ff3e0488d7b5c00b10dcec39010d3b5bd4119ca07
130	1	169	\\x8f924c1be321d01b59a5c52034af14dc75ec3dd6a7e47e8455a2d1e8a95553bedd38cbd396c23e20ac3a50227fee75d1e352732d5161aa035338d3679da98b04
131	1	294	\\xb8e370f788d8c41521f6d865d219b11082c31251d93182a5877e327b6840dd4baf14adc7b8a82bea7b87ced7eff035e236ccc4460b7194ac1b9bbb5bcb4aec0c
132	1	117	\\x0ed1e744cefa83e4e4e43bf186e23c120951d3511e203f4950ca1c2f0f4735af8a4a468d76feb8a53f9be4694cf4dc5d7b363c4b00ee0ba78038992a08c81d04
133	1	25	\\xb275e9194f9f11fb3dd15263cceeb52bab5b5c777b81ef4b80f7367da8b762209f2553f1d4e4ee3bde60df1358a3d8ba12c0a7a2af80b16a6442f26bd4fafc0f
134	1	93	\\xdf70e3c523d6649ea77aec6d3f1349c474d2bdd07ee0273c50251602ca67a9d6f3a723a99a9ff1802c87bd95a575e23a418f7a12943a835d29898367e19ac605
135	1	378	\\xd1a72b55b8f142324602615fa6090345573c9621199c0560100f7e2cf563d1aafabd46339c851dc87d609bbfbbe31208696c87767da36fa7212c91b6e4c1ff0f
136	1	317	\\xc2f63efdf637e9f46e51ef2736e897a82c49c00b65d6d7abd604328d0ac18e6911c50da1f250da264d806a95462dd992e844773a434f243eac6d76ff08f9dc08
137	1	206	\\x0bd2850658d871ab0ff611aa0b9ea488e0850e1adcd5d0026b015575a3a57de7b4b174db36b63350c3e8e665f7f957dbf8644bfca5265fb29b06929b54df8108
138	1	277	\\x8d6c52fed33b2bcea3cf5e37668c9068ded21983401bd7c5cc58648cc029b267123c97a9f64291154c9f57dbdf21e0e48fa417fc4ad42ebbcfcd00cc4d6e2b00
139	1	303	\\x70b4171d1cdbaf925ee157bad3f94afd9b8a590e3bb8870d6da6d5a02ff3d98c337a43ae777f1c55f0f67e5fbe77971d9337aaf09c5572dca898a5effdcdf902
140	1	325	\\xa0222f063302fa8fe081f004da3f6b1d0836148819b67cb7cfb3617e9ebafa467be208e3dcf0afbe94429cc2cc176ce212598b5d0d580f1696b2737f39b02a04
141	1	249	\\x0b1c32caaf1791333616e03df31c9796e8df697152ae22de74d71940db4f310273a78808d7306681aca6256da053c3928804ec72476b80d1774c9d5239cf4a0c
142	1	51	\\xfa8b18e18bec749362dea1508751ddd843d93d56d21109cac56139ec33e3ccd1bd62fe98b81b02f37a305b9345cc9cb0be38d5e32b622148df6d9c0445848e04
143	1	422	\\xa9ff27cf82e1afbb395154e399c1f44c28f97ea6d5c64e8592db56c7d37346357bbd195c04907172a723b175d497e95ecb730cd8621422e40ed33ad4dbd7330c
144	1	138	\\x7774b2db64aa180c86eef5191287cfee76065e61ff9a8c12fbc4d1402ff7bcc914f1ae56b7e81f1ba1a9f31ee6b0dbbdbeeaf854ae0c99d04f668f210fb9740a
145	1	168	\\x008d0810b7e8686aa6519b812cb32d9ca7b988a3347dbec961b2160660ab9b90cb54758559014930571a22b5bd0b488fdec42333fa9f85639c9c354eab00b002
146	1	194	\\xfa20c6cea992d8f6d9dcf762c25bc1c83889fefb19fd3618850a534b535126e0e7126c5ab4b5309ee1beede98338cc6562af09ec3c91bb4a2666662ddd889604
147	1	238	\\xbda20606f8a1914d92cec38a7e7ea65385fc2127f4e86c4d03e86d847f2ad5b974148165773f4876c971a4fdca7b001f48d7c6075ef1da976c91d2c7872e2403
148	1	351	\\xbc6e90f07720534e6175655f76482aa7b56405c38954817cc338d548d297135ed2e3f21c2c256e0437ae9c1cd2deb37e7fb62e33f6082c7a06612df88d347204
149	1	384	\\x3eced3e929866d6232effe9a84adbfe76e8273b7de8aee3aac552147630049d9af750a4b64043ee237ecb5015aa796acad07133e6be59d7944fd1c57d7036006
150	1	94	\\xd62756d2c7aac21042d0e1029a6afa795b6bd91335ef91d11ce872f1dbff4b3642ea1182ad8d4e5840372a3f82b23bfd5385876375d92f84065433f243653c0d
151	1	12	\\xa2cc264946b72df5d8ccc19cd5d59cfb79477437ee06de1e71d8e24eb29c19b7a38f8e2c8af2328e7d7104b8aef892b684089ba30de87339b14a10b4ce39650e
152	1	320	\\x14dc8bbcb9dffbb3d736625a94a9056fea46173fcbd2c638c8de93354bf2e1f9b82ba4d7c709e5865508f68366432b909896e1ff46dc85a1e1fb78b7cb28e40d
153	1	78	\\xcfffb632e5d1415eb8826ba6175dacdccb84648f0d042e6e4cb2432607c25855e29a2c6c18d31fca964a011def9b29aa566f5f57656f57be9f019318dbef9b0f
154	1	135	\\x6a96a6be5be23c95248b40424a6af2513aa4bcfcf1162bfd18fa65e02d887dfb9f61abf0cb6a32128eaff38cd4d9abc5909c4bd153f46bcea25f3d68f38d980e
155	1	39	\\xa80dd7c81ada1d5a41ce596ba1423a05a95ba9d9945cb80a4c3fb58cdd13b9e255c49374d28db43d57eba0012fd2280ba1e2d55693492a8ab8687336cf5a2b01
156	1	240	\\x25155216ddfe30fdb93962157dab75a7b046a96f78889589bed6c54a35cb79a85a4875924bc3cfce8b09b0dc2da18e6d980e96d7a018b47ad205dcb0b393170b
157	1	248	\\x9bdaccc1361f7792e188d927bffd37fc676cbb19cb2e229108c594bd768f6b1622d98dce9f6ac4e008fb34d8e80fe4b8aadd37d769bdaad844d0ce9659dc9500
158	1	330	\\x1248f76e5e2e28a5be18ce0dd1761bc1a9dd144bdec3707ccaa5bd279cab343688a3b1b63aa4050546d68ded3530ad81088fa77b172ed989174c82c4bac7fe05
159	1	193	\\xcae368384e8cf497da3fd449f72d1365eec62f842dd1d92cf66f27dbb8e0f491d8b8879c8e287db47de1da18b7bdd2cf8f9e7328f0773b635a49d34da43fc50b
160	1	19	\\x27cb17d3f1b11b79440ad8f3633dc142615ef7fe4fb6d31ec7506b4d63d728f094fce66bc49ef6e41cae913c357337d67d174c8b2d7ad851450f7af47a9fea0f
161	1	21	\\x6b5c830c3a5362b0ab672032ee6cdfb5b0fad5ef2921a240c04d044dae511907bcafdb2342822598d278b7e085cd9e885bbff76b6f2155dce96efdc6458fc907
162	1	28	\\x4666c8ddfb72d5cff98abe542e8e582003d159e37a906eba4b38a3f69d64513e6fa8d0f648ba6527f0af6c848afb4aae50ed90e5893c5713ffc948025c0b250b
163	1	335	\\x5f4a6e5983a01af8e92ca725774aa40820ccc8d8168b5e0444325f69f83d6e6bd48c068ee8031a6d14c09d629de4764e777692724767b4ee59fd40579c987b0e
164	1	142	\\x9006005e18d7cda9f5433609bf499962fc9914e76474c6cfae40b929e91e69dff9061425d43774db29a8b3a70d9ad351c01dc93d68edc00f92e4857ba1062309
165	1	275	\\x61963c7043a2309ccc06adf20530f093fb82f9fb0926bfbd0ccc3338d7f2be25ee8cd3eb370caf40e638f06c6f37e4d8b821cafa4cd6170a957ac4b2f5060606
166	1	287	\\x83aa160f8cfffa7d556198d9b006c9c26cca8f05d5a4db52eb401971829116b546c615c5d3f694af2fb6c7f331a3c5168a05aa197f31eaec77574067d9c14e04
167	1	226	\\xac13186041746e8dfc21e96a0eb67ca2bb492a8111a58347732aee38f4b4a0bc886be691e5f4605619a2c83a34cb355bf2cba4b36a480523e5dbb19307d22900
168	1	417	\\x837524a252a7dcc551fee324b20225cc7982d4f88b37f3de7f3ec62944a03a60059fa6922e2cfb15c41a0531c7ee39bbc3baaa23acb8bbd0772d18861e0a6b00
169	1	43	\\x6fd64cccb245aaeb3b487caaaf446a6d0073d1e666489dbc9a29642e55440876def6f106fd81c4a100d5453482d3cb1b3407c5e6fbdc2071b919928be5f76705
170	1	306	\\x0d344ac5e26e415d78410a53aacb1f28242ae059954e2a0a76e060e83c9d291e2e03bc62974c88268aa6aa49600ed4060af927da269f7944298bc50516bed801
171	1	10	\\x0846600c8365ca451965800e17f356225ad735f2bb96ed9b1f1faae672fe91b97903e2fc55a0b9130af7d539fd279f0c52def7e2d6f03026c10c8a3c863e8006
172	1	11	\\x83a00e5eea6f03944ba4d3300d157bd985660938da9516d6cce058d08a0cde10ed50c2c73404844875e5d1ef50a71ee94e4392af0335ccbaadd62d85cdf9f50b
173	1	155	\\x5d7120bfaa43a8ea27d829989a2b903bc8aa62658ee717341cc5f6d70f49dd7732ca4d6ebf4672779764ae732c8ed810dabc46d0af8427f1644c0032bf9e8907
174	1	49	\\x03bd31b658d8b75d054d4ca573e37f9d541e5d73488440225b7f116bd64bb4471cb60b207e48b12213b59572a0cf07eec1cf5db05095f14b9748e53a4b43910d
175	1	198	\\x7518eeb196e3837f23962e2f0bc01005f01eb420a45bfaf7a326d940b1b5fa7e8a02c25b574ae56111c5e4611a11f721bdec70703cbc004b1c9c553b9929df0e
176	1	82	\\x803e114fcf8295ab5b6e06a8dd8010b1a9a6f35f30304f20ffa877d64bba4397052abbdffdb7cd86adfb0eb628ad63bc96cbc3acc4d959be0981d1f6cd3b790f
177	1	406	\\x691837a3361645d7ca36efdb11269458961ff3ff35eebf2f942e22b586c1082016a5e63d8c550bff11b1862ca0dc7b0c09da229d38191214e4c5e51b57a56b00
178	1	254	\\x89068327c46bcab163bf15c89d1fbf238a6e2dd85d3560c36549bfd16e4630fbec61223f84153850d57133343947fe64b802d3f8c1f08b2c848763dbc6ff9000
179	1	315	\\x4301152b7ac50de20a87d45beba1d8082bf41c4e44dc19a45e3fac0e9fd8425e6e930abbb0034c82acbfd1fbadadef25c57e5c97d1d69702d2970b49cd866b02
180	1	40	\\xb04a181636058a94bdd187482997c59cefeb29b97faf9db25a51e35ba2dbf2ed2857fec1b9ccdccb7601cd41929b06cc84d8821c62f63ae7ea0e4d4f271e7d0e
181	1	123	\\x17bd6fe725644da58a5014cefc73bb64aab97590f199e361c7f2e5a12d76879c2bacb89ced626b1f7787475bee6c8148abb1e4d996f4ec86f24d82b2fb80060f
182	1	161	\\x0485a923f259b4d84a2e4ef3699e706043c8f5df9d3983618b6af3e5cbe379ceda4d3be9ca554c2d05d1322afb0245b85146d51fd6fd0d4093bd6f580a456b0d
183	1	34	\\xb19b8defb9ea3d44a0eefe380305516a56dbf5af9b58a818f39f76a9380e1b27981564dfeae6dffa7f94e9249f9c353a37dd016c4121f3ced04f5b79120a8606
184	1	388	\\x93057a98ebdb1fa241cbbc3aad1644529553a00cce8faec3526fc7ba7857c51fab8a721c554718d05e5541464a579ce047bb42e0ad99e9876264ddd24d5d820c
185	1	235	\\x4c1690970e9d5fda03d88a1334994acd7149980218b6aa3978b2d5f668e7875f348d0f48213c55f207b6492bb1a83c60bd380c43e468ac68515b431b19013107
186	1	394	\\x6588d5e28b9ee95211982f982029a9ea04492cb93b6ec092f53e23a5ccf09b3fe0ef504d70eab62cd2ac8f19f7f40936196a480fb46688e963398939b743c408
187	1	165	\\x97a09d4f6113f7f77fa3f08afde4075a06299385b84411db156f9d85ac9e54fda15b4c4aa498833be63de4248b15796bce8f39595763c94928cf9faef498f70f
188	1	77	\\x09f6bfe88aba7152735d958edfa997c8f7a58bd01d4e58492394bb615170a7c2bede38349b0c13cb4498b8173c88279a89b461189c23a4c980e2b56413cf4f02
189	1	31	\\x52003308a43a655fecb8a5e3c83e7d060745b631395df1e844dbbac66f900f438f049dce0a2a40e9cf1374eb3c060023c76f79f115cb8b8740ed0628cf1d750a
190	1	145	\\x70388c79be11a5a8cc23d47381c67b389d723e1b656fae9d7d9b541de1fe480520c735bbb65410af4592c134d99081a08b392d0d17bd01d3dca5afb4557a7e08
191	1	222	\\x83b208013ca37a7553a8584e299d8c8e6a5f59af3deae80e89df123df6b108a1ef952f4b670e5290e6bc2b205f2f138eb47e2862173c4687f91e5f4d1149950b
192	1	418	\\x826bf979aec33b5a6b960bfd6093ecd8411e158b26ad8597128e2db3444e44ee1d7eeec2137ec34dfc28f368ffc765764cc8429e01465385ec7baf2fe93d0a0e
193	1	358	\\x9158d48c37351eb8095bc9dc4f7cba46f69af88e79eaa1ce7e1816ae6b6e5fdd43a936936040ee649baec97f00df1ead2601f7cf0a512a4881ccbe053f792c0a
194	1	69	\\x6a29924c234db9f992a0f18d9e99933160f022502b6e54bc1a14384c632e45b7c0705cb6500a2b5e199def7e8b3f3cca0819a3156888a312a6487cc83769630f
195	1	410	\\x4d4b92364c286ee87cc46e8ff5e05fbaa705e56dd429e257288f949a8baa4f12a33e49bafb77b08c13d2abc4dd7f8e7dd3f1224ffe57f84aee0ef03a270cc80b
196	1	376	\\x6bd364608bca25c32f8cb0c9166b63999a84a084ac89f24dbcc4577eba7c1a8f9a1c843d1e9355e296847676679dfc2a2af090936601a6fa52446f9884b0cc06
197	1	357	\\x5cc0e5a3592e9ebab0de1c0e963dea19815027a4a058cbbfde7c3250ec82428f9217261446c2d349623a7d9f3949b268d137b2af245008ebe5b52908a2cd3508
198	1	332	\\x314a27899ab8cd906923849a6b586b06dc962f277a97fae9dcaf0111c4e6a64f84968464e8019b378c6f5a9c034a764998ed19f65d7949ad5356b9e02eafce0f
199	1	318	\\xd78d7f717f6bcab0ea06794204bacdfe9499d56825c94d305933e7347e2f742cbc269705578a6b0536947604df9a20e8da1f4834d27f6e876c82fe078d10d70b
200	1	308	\\xd316c97d8874423fcb8797f51092109bc31ce320551993dcb1b0d25ec377d2a715eac5b81e80b4765b21c223c63f607bfc10bf469e583259194ca6fb3b60d600
201	1	331	\\xf6d4713ccb9415e494a59c85c6fd4e89e797cba182057a913cc7a61f4096e63a7f7d3a52cf52216938626c5c48f9d53add3566bb5a30e275cbc353fb4c35d605
202	1	18	\\x6ef5fe8fe2214cb87aaa89c9bd53770540e2fe220427155cc40bb969afdc2c18f4a62ac70a480584902f305f3595292460d50a7cd33ab230ef23f46ce604130f
203	1	244	\\xe2436f8650b4f8069a012061b277cbf37a8fc2b6dc34217daa533437219d200f7f3a2c61e60a1a7dbceba357277133385bb4ca63d945fefce58f8f87e2d7a408
204	1	130	\\x43ca9ddf1a7044b7104e9a51adab753be20e96d57b0bb0db651e65f5a57e233b150641801f2366aae953e6b0eb3c32b05b607d46205b7765daaed3e7b0fd8008
205	1	296	\\x538d5b30b89d781573108bba423fa924d51fcbd7b76a1c3e84ddc977cb64ab5ef50a661cfcfa69e54cdac94b24246a97e50027540aeb39a20cad9c4a307e6608
206	1	163	\\x7087833703384fa8c1d5c3320c0cbc05df6b5ef8a8c4a52e8e84d5067b06cba94cc5c0d8d9e981be2cc455c9b7bddc938429abe883b888eb9cfaf8dacdf1ed02
207	1	281	\\xfa5323245a7e3e5cbd5ec1f359a69ce62636153efec9f4ef9d7f3b8fecd898d1a3d5a3a7da3210d112c854725e5c2681daeedbfbe94c6af54a94674699a5ae07
208	1	349	\\xf873fe21f32d826e16316b5ee8002bd9759f1b9a4a018f312810e914cd73531204bba0b529108ed66298aefcdb61b873d111d1b6e71f95b61dbb7025be96ff09
209	1	119	\\x4fe8b7bc61e615ceed7138760c60a3d45933eaac25f454d0c2d3917f59faaf8ea48609e55e03c6b038fadc859db2ebb9b79e00ae40eab5253ab0abb43851d707
210	1	333	\\x92885987b9b6e9ad58e216e7d9dd1f829160d6bd6500e5eaa7e6f0c8f7471a0d742dbde646b4f4dfbece4cf573ff18617f68369c3601fad9887e70a9397c3f04
211	1	350	\\xe46ef477c0ae20ccd3ece41dfdaec5302e1a9679fdf329b45103349336d37a8379b7dd710ee5ac059fc2e00964c0cfac05bf032fc9359b4769b9563d5df8e10c
212	1	288	\\xd62f2429ea207b7ecf135770be21877189e10162eac39ad66beacf22fdb3c5ff702278335c58b76a85bbc4f1c08499b32b174dbe368f01e6bc9541a7e668390a
213	1	381	\\x76031eca6cfeaa35dd4721d6528c4a662a486ae004956919ac84efaf5edc0b151288cbd966835503beeacff803b5200ff5978aaf124debd599e9049a593fc705
214	1	80	\\x58a999d24a53fac39c33b3776bfb91d50bc58fc6ab60c3c2bff171f8a3ad52bed938067b30e1ea4ca8232486d3afcf9a4e90228218141c941a3241ad048fc600
215	1	3	\\x1110e055fdd213c281d7253bb35ce944cd409881cde8606058f30bf2e06a235404bee6e2b5c0212852b53889eb2d630717c90d426b62c7a6aa91eb21ed7c6004
216	1	398	\\xff1d8959f783800624ce988eeea3de0d9082c5f80742367f2dbd176c75c1c10d30f1632c964472a49056655ef63ad88056e2311988de3ef56dfb95ab288baf08
217	1	374	\\x60562bebec331c4659da53e280653f31f1ad14d4bc4089a6322e638d5d0df89cf8d82ee554cf66135fbb612727b9660329d6afe775d7285e17252cc752c51008
218	1	319	\\xc322a61bfa40883042871bf817e58fa31e587ebf5e7fbb3775c04fe6f7dd683c1abf8f82d21ea7de19080c6150d0af562b5fe7f22d14b8786065ea51dcd2c902
219	1	372	\\xe6ea6481e2c6693aace3fdee64bfa5ea7a3727116c0a01c099dc81e2347b42ae2ed3ced37ba77fceea1336751111e8c4c979f496d1df7562c333638d1d544209
220	1	400	\\x78d7d622108f5f9ba55c3288d22e5cc1240787e4b55f90b04551ab3ce018d66a6f5cf61f2d755fdfae3188570466d866b00080e6c5864828ab20edcb7f286d0a
221	1	65	\\x65a97e097010b968fafd80c5410f741a9e92570721a8f7f6d1a153c75d488176727e39881f79244fa620079b90dcc02bec1bf11d893391abf705050a4c97200c
222	1	97	\\xec342770594f0155f22d8d059f6eebc20326e929a837e3ed27b7e25ebcbdc6f747c978c24412d4e11b60f54b6ab7d37fa4ee8b1d0e80ada3dc9b599ffc7b730c
223	1	58	\\xadbd7f54f8f27ae99061f18c69d59e7d16e8904b5bfcbdd5de043bdd61d24bdff90fff48278efc70e67f92cc755b800481bdd6b15040f6fdabe9fc8cd3fe3c06
224	1	164	\\x8fc306fe5abd362629097cfec8e4a2ac4a869017d003c81727e4d971b7925a9d0eede088b470debef92fa9c3a9dfe7b4541c23ed10f929ccf4cc246939ed0403
225	1	20	\\xe3bed598b66a957ee3590122396120eb704d63a7e1ec26374564bf456226e0b2bc164669c90121a4d13eb6f5b32c75da3144d03acb854bfb516feb0aad8dc90e
226	1	359	\\x1ab1f92fbd5ded9ae6dd00c84337e56fe258eb7ff1a8d7d0f4c965158216583fec03946f1e4e19c7fb83f3ee338556c1030b1eeeee9377d2e460e5c1f166c50a
227	1	9	\\x2e508e37f130c1ad812c5e4cbdd79c37a615527c91963fe17615cf8588650c9afab7f2ffa93a47fc3a31eb79b149b4378a141f2cac24a984d5d69fc9de9ce709
228	1	311	\\x0600299acd04ed26e0c62b5553868a1beb9ff0b5968105f15b96ee521b6683f7f51d17713cd0c3d4321bb04a0c4263e4a4e6bdce8352c0aa2b3492f218a26c03
229	1	391	\\x6edb2defb081bc025580f28c10387af557a01c10e32d53b6684e4c9dd62400223a75a2901d13b8320c309c8544382919bfc0d858a31cf41d63d1e94db36db408
230	1	33	\\x49b896a7f3407378fb0bfcc6623b3d0c65766897831f02277ff4524115cefee636c37b0142a75c34e16a6c084b751eb6f1370be8e345d5a3d9991912245bb906
231	1	363	\\xe297c6c87e6199f2922295bac8d22a8cf91ced7ea6549d189dc3ec67b64ffaba209ceb8aa25becb5e0efe494d7098037bc35c25e222697f001ea738b9c325502
232	1	414	\\x07c1c09f9606da50709cb6a772f82fb5ad633000d9673107babe6f57b9290d7eb65c7c3b8c50350db5dfe9cb22986276abe37913ebf4c060b8c631637e8b7a0b
233	1	340	\\x215733174d3bcc51854d9846b640278a7d35d3a4b8409caba77183bae9d196d40c936ebcd0140f76583d892503c1ddb6ce93e4beeb0429a65d266e0455649508
234	1	107	\\x94fe8b8571371e4c11d0ced8af363dbd8d59de48edf361f976579efa5fd803f46c23852e9f90793df591b9d296a6c54684a502df80886fb9021165ac16fc7601
235	1	83	\\x677a7eb826d01ecd8d2fb5c024be732bc69c959dc68a3838e532c6269df75eb2fc7e53c180d64625366a6fd7ebae7c0ab5934b1769a085ea92f5505b70448a04
236	1	27	\\x5a07e57e73f169836144761877b90d9b6d90b4057a03542658e87672813d71c7f48ced0bf93da576249814e375ec9377cd10dbab5875c66e5cdbe58299b51604
237	1	200	\\x41c78cc70996cf948581b6cc307a1f5f366c952795437322b1295344bd5f215a38ef68837ded191f1f73209c24c3c3f48603b9719fb44ea1e47dd0852a13db07
238	1	53	\\x188b770a94bfeb71badbcfb012aa4926acd29edf08dfe39339784c550d289bc0ffb7440aef8d0b3955b002fbaad29b541e1c551cc4813741472aad3c8aad2509
239	1	178	\\x6fb9a6300deee581e11622a1d6ee640545eadfefd701338eef34d6eb12d3ed3b258e810a95177380900070fbfe505df78eb8050801529af08e8fd1e66f8ef101
240	1	192	\\x3817d52f3757fc0bfc6fc7e04c3f698d037164f4d2579c779f700cb37299582e92e3757c48a5b0924d6e04510b1888711571c550b478e079af76e9557b38df06
241	1	342	\\x747250ec3a5c53a1ff0a4535ed7de323f1981ec9fda2bbb76563a3a17f39ff664d5002ca4802ec94bbf83ee4148c57935e49d3614730774c56449d942ed6ef07
242	1	63	\\x24c7c1c3d0f6f0cb69a6d3d30042e80b75aa30b35c33a781d3bbbbb1dd2b59df59c14b7becf2dcbe548402778dedd0a825cea8f81db4882a5b1a31b8f354aa0d
243	1	175	\\x3f0feb8907136da7524eb7f1deeeeb39469b846d7e1cec8cad41b94b79d2c8ac7b1ce247e63884facb2eaab123b69871569ee8b5d89529ac83bc11ed778bd409
244	1	382	\\xa3626af0a64634ec57ec9a254b34918b35f75c042b7031650841bcf63b9d9dbd20578399cffd7f2712582d08122a765a7a2c4673250a02c013ea75b4c832d70f
245	1	247	\\xbcce41338188611783d4078c81c5b3e9355ac21990bfa01d29785235b1670be824dc7ef9aa0a46e92a3397c913a51ae8e3bfe97859b60d4464c63726f87cb608
246	1	298	\\x4ff94cbe9536907564a5282905e3fc85c8cc314e4ca49558874ca8fd3d663d1e871c3d823bd790f21fdeed78c6cf4cda1f6881ea0f2dd168931e3f6895f13800
247	1	305	\\xe38bcf4ecb35ae0140e3152809b2d585d29f04f2b5d1763e699ba95ee2a147e5ef52f60cb4942576eac5e25ca776dd6679bba209a49cc26cf48f35b8ddbd560c
248	1	186	\\xddc2c7b1181c6ce6d855c274d1b4f0ad0505ff9128c0c2afe10bdc31556eeea259fccd4d1593ad1fbfe873cb068fce8d25ec7bba40ab1a81972515e3a4ff610b
249	1	179	\\xba75da38bfd785abab307ccbd7e0444a6fda6c696113b8c142d18431e40a7e0c5875da4a8a05f7356d4c2cffb1154f78f20292964e5b9546ec4354d2d2185309
250	1	219	\\x7335ac09899017a8110e01e1c3cffd93ae390e11ea976d97c1ce77f6e006436279ff87d38499710e0b08536317b5506b0c38b44574f0e2c4bf00bed271410d0e
251	1	5	\\x89fc52cd16a7beba760f384a289f99fa3e841092ebafaf5b2e63d464f762cdf0b3f337e6defc4e142c64528b86dbd673d79e6cf818f6ffa58ae03bbfdf35920c
252	1	182	\\x3f0cfe65f3676ee83c0a91bd5c4cd7032cbc51796050f350dae8117fc977311cb61f90cd949fe19c279f0c83b5adc35083b8c5cb3ef4aadaa205d8348fb87304
253	1	108	\\xb37836f00187aa10db1d09aa8f8fd8f1ce8ed804c480b34a0da4e55bdc7aa3393d6c58e2de5ec2b84b4b2f479aff48f65f0b784fdfacccd44705a5cbe5482303
254	1	265	\\x022ddf770b3d70fae99e480a3c273122bba20c264ab49958065a1a9ecc19a8979f55bed50315e3af1a8715094a860cc6cacacd1472463ee65ddd1c6a1c2a9b04
255	1	50	\\x03781636d75bf00947c0e4fae9942ab535afb9a808101b4def8a4f77220807efc84080cfe34c3a77996ede9d55916d3ad77faa5a53c1ba790844db9102fc7509
256	1	129	\\x7ae61e2bbe12856ac01dcc4f299435b67f0a48b3ee37b2ec5d6344983b1deddedf67bdf553c4d8de3f3afdc6892940ee7bf695432cff13f613bf3c51289cd505
257	1	7	\\x7fc957f645ad720fb63d18c970b79c357b08d9966f53a89d07bad697d2b98a2f4da7dec09fef50b82cbfe86067b469df5258a67ccce63c2e4dfeb39ce9ec4f02
258	1	395	\\xb520937932d7754f7f053dfffa451ac745b6845025c6c919831b5be7c964138a7933163d395c1a0cd27a8e6bdf9626a13643f0e3fbb0b2221626ed9b6619e002
259	1	295	\\x081ece16e58ebe64b882e6ee1b62c9ce77b0f63d52d0a44bba74191c8f4a47a3a1edaa64e2d73a260ac03c35a004331a21c494c034111000083f25f5fee9c809
260	1	4	\\xcdc4286f98b551885240c8cd83bc3b7e640f78fcfd9895f468a2760bde53fcac740920627106a7d6d7d0720c8388401e8ada34d32d41b04f40111eaa59407307
261	1	367	\\x871a145bc4b4a40933482e4d3a31b68ec1be3f9db9c57f13c3cb827a5e11bf8e736afb09500e96d5ba81b1c090b6e53d6205bde0fc381539adb3c6b9f316ba08
262	1	35	\\x216a3ece0c105084c62612fded667b7358be5c12f36bce757925f8ea09c8690d61e0fdd85b252f0af76a37c74cca2d7e0f13b45aeb17b1c612552100c4cc1105
263	1	339	\\x7e181832e6b12036f0762bac69f89e3424927fa7e5764bebabcc3f7bafad3d32a66540c1219f53980e6fc67df182633c0364b0d355a3de0751ce12444b44e309
264	1	132	\\x13c7d3986aeaa67c3ec0cb27b7d8fe8d688f6a516ace0a3cb35623bf064483f7acfd9262890f20feb2ff835f9cc96df2b845fdd9fb4f0b208e49b6d7072e5204
265	1	75	\\xe270667f1911c45c75585ed4a0bff167b8856e7836d748324a3101663b2921616358b0edc748e1d8049f403dfead5b3aae4634646091e801fe1cf942df0bff08
266	1	24	\\xd455415b7437d42b6e3bde151bbbb027627db7843ed8ed8a27e0be077a379e66c35c75b09e0271ae6bf58675ad2a7254259ac44de3c9d4319d7412c8af7e7109
267	1	297	\\x8b08b2bb9e848edb07c00c78852d229c0b80dd09d72041bab99c970cea2867c8e8b0874355f080faa219704d4a338c93b0bc7e30c29389d8acd6c8642c5eac08
268	1	404	\\x607e3a400fd62db188c1d0cf38add85c0a7140ac378c73fa04908d20182662a78d485230bb168c719bb0441be65252d5f29bdbb4e919eb2b58ee1177c13cfa09
269	1	109	\\x320b6fd8c584b569d482ab27b8576218679f6e94ca98be803c173fd86b7cf956b3031edff65d70e0f81a67738d45050a82d1a8b53ff5e2cdf2747e4b937f800b
270	1	355	\\x08f32872befe0858591371d9726d371f0edd586cba208b2ce54008ecdc14f6fb1cbfde83f82e36e958a888a784de2c1f04719436dcd104becc46c5d14e4f6b00
271	1	183	\\xb84d8cecb5b84fea93ad91af8e4a8afd868b823f6f27f8f975c104e76395a1c4fedd1425da65c57557e2f36ef231e6c711a1956e85b2e4b97722a8e31bf4f90a
272	1	46	\\x08d318dea43e05a5f61a25d7c3b79e2ee771d4cfff32d5b35c4aad7e39a8614115e3e2bb7c0a46607acb0a6f1037a1153b86930045006dbf5f46184ab7366f08
273	1	214	\\xd3564fe56d46a2768212f5124840ecc539c38dd2ae5f95fe9d52f561b8c417ba6e5cb074274ba8e318e697f9684568683b02d3ceeabb523fca40652ea4fd630a
274	1	420	\\x1f0c9f98cf3782b56f14e82d033b91496ba9ec61547ceeceabdf3f45bbee0ce0699d27389a4c12664e45d88c4170b7ffcb8f1526f64e5b40f4b1d8675c70660c
275	1	41	\\xdd788e17dd9d08c95dbd9f5ac28d7caee631b0cc60e3b8f486f699645b9747fb3d60b4443928a776b16fd57ba41238d7b7b35cd7f3967962378604fa0ce51602
276	1	274	\\x6c730b3f4a9a7255554a8ecb3c1708cec194e189d12b47a7afd3987b3ae18b6a30953113887f75c4e279fbe9af4d5df6474b841fde5557542636fe330745a90a
277	1	223	\\x01ad9d2716ed0f2ea007ec86fce614d78bafccbd4c6a0ca1749e198948286f97c25f454303b8ce0bdd1f6d0a23482bbee709416eee79a33da3399bc1031fb006
278	1	176	\\xae80aeea39c24782da6ce216a9db8f05073d67c65eea41241fb34143c560999bb628d1239425546b33ac6d5d472f9d419f1bec8ad02bd8104cae782e5b3b9e00
279	1	257	\\xf556d2d48a15c2aad484665cb3eda5327f2d5d575ef6d7ddd5e044a214c1c1906c1b3e2a3511a4991f6954f1c2bf2cf52f0b5f3a4268730dae579877844c9d00
280	1	30	\\xc6f8a1c34eff2ebadae97989d2feaa35a20641e0837915ef4f7aa9ef8d674c0f60f9dd119df3257ce92e9dee452e23f3287d57c12443d3bf0b7381a534307e09
281	1	362	\\x6ad46f9834abed3a342869e3184e0a20471ee5529d8fa4d75b78a81b7869dea0c261b6f108547eb2104f646325657f2425c7f6f2143a5a8b9824469c90d77f0d
282	1	71	\\x3cc34531a1e0647e627d8d00c315c55eb00f0069d2bcba3044c87f257bd865e8d8eb4d4ce2d636dae57cf42581ff66353247c47ce5329c799ec4d2d107b9f907
283	1	416	\\x1b48467e2f99a18f149c16e86029863cea7259d62d9f2e8db04094244c88536d900cf6a7bd970a5754b53cf2bbb19c0a5e676c54ae948ac71467dfcae92e1b01
284	1	67	\\xa4a731bb66f35c3c3bc422d122d53beff45eec3e6e9bb6acad648d6d111aaac16d91bc4b50cac0cb428ea3b6e2c0bdcc0c5e87ece75a91cdf42737fddd0a5e0e
285	1	309	\\x672f2f14645a2fce3197bab66ccabf37f37a60de6cbb514f8649458d06609d4181ba4659cb2d81bb25df1bc93bf0b98fcaf5ebabee68e516bf4baa30cb5dda0d
286	1	113	\\x75f46f4cd3f2f0320afd92f5125ebf15b3ab0b02c7919041bdcd2f2cda7f836b683d3b702a153579fb31215987e9761627f33a639aa753ceaee5f2a226621b0d
287	1	312	\\xc3ae4a40931b2e57279b1339bd2b13437fcb13f3605b254d7e71c22305fcfb8955cd799b2a5afedf3fe9e30693ee45867a829dd6baab5a1d449a43ed05884602
288	1	344	\\x9647a77fc358c73a306f7c7379bfbc9aa636fcb9857204cb39b0892ff76f3b9bae39f121efc1568fbad345f4d73be6c36c9e64e7f32c448d0e1a473356619909
289	1	364	\\x17f9f075ce5e11ffcc7dca9bec2af594d5710f0c23935faf61105c4599f7b35d37f3ef668ba2f25739c480d4f4eb6bf6197e52fff3e9646719647703c468b309
290	1	377	\\x7a4cceae3dbf57a927a61d139930282953b29bbd2dc16bf595cb115114a4b73cadb7cd9dad1703d1abd1921e614c674dd6af4d90c0bde1b0f79b7eaa90135306
291	1	324	\\xbc7e6ce46ae1cc7d98659eb82be401dc85c0e678db128f348f0cae59171eab3704b5f2e5f271ec4cbcd925094c021935eb4663f2582d17864aa5d6d49fb34009
292	1	190	\\x3a53f8eb796e0d65e2d260df0b8c93d77efd7c55b59020637522a925a63fd737c0bf1146b4a35677de927aef4626d83c6edef089d5f377ecdb06fa6ece96e30c
293	1	285	\\x2917374bd7741441fca47b5257a48f64c52e95cae0e56798c3133ccfb72d0f965888497bb0b0fd5304ae7d79f0a2e4b79fc698edee79a7679882a3e149aa3c09
294	1	56	\\x7a014e42f9ce710d3806e1fe9b07062fce2a6d7aabf46f034d7e1cdd8f04e940047fd1d933e6682f11b7ed5f31234dd69370f508ceb82f8840b17e122f432101
295	1	187	\\x29e6da791ceccc4dd158cd9e85f8d396c66f92540eb1794fd520a6f94d4d785e556e13fc7f908ae3b97bd9ebd016ae7530d297e222d3e0307d6b9b301ec09703
296	1	212	\\xd8dc452f76028255477c9ac2dd1cbd43bc2dbe99161da9b29e15300c3640db156257f500c0b3ef38811edb02c91a4ca4ad2656847f782abf3dfe7f41c4441407
297	1	371	\\x4498727538ea712dc4b32ca99d27899367344363d8197a84800004706f6ae9fab22b01ee55f7b1d9b63aeb2df947d65c17d9dc267cb9ffbea862e01492e3af07
298	1	301	\\x5bf8d0cc49acf7bd26b38dfca96233ffd5c32522d87f7134e0099be6dc32555445b1d7639e10a742b7de864c434ace95124408a27fcea4f49f27325cfb69bd06
299	1	353	\\x4a8c122d95f18a3e62c55509fe2ce56280d75d5b82705d9af1cb3460d57f28387585a8e7434772eafaa05ba23ae5cf4175d6b0258e16546fb5c25ea3d2545507
300	1	266	\\xb7631b63b9c0758cc21d318a1395700ded9b0695f313b100a34d7f9b69b377bebad4091396bcd20eb96f76a662193ead95eb3e019c168b9a3e2efaf74b768a0f
301	1	141	\\x97c0cd2b2deab5ce0e3c07d2213b0fbb3789b7228a30c810442b6f155e4efd575312ee24a7f5fa0c59ca725baeae59aee7da7454ffd60a359e7dc7146305a70b
302	1	96	\\xeceebd0e5c73f248b1e1487b284d5a99e7054b94fc78b161e99d8561893290ef99eee24167ae5f7166a41f46cba2d45c68cfcb22fb025d78cc7ac1cb362c7002
303	1	307	\\x1521116e0b5afd8bf83b935ef6c3c93d56a3c4bce2d43e0adfbe79d612b1580515d56ac284d6a259590716b49ede0e2709bf85b9d3b087b8be15b0c561bf1901
304	1	22	\\x85342ce25d0214e11c866a9973047f25f9f5689d02451bf7b320c58cf553f9d041c8bd0eb468944385dfcb4b10a1bd38d5b217c0ff356bc9ff8913dfbfeb7101
305	1	250	\\x56425eb9e27676bca669787270ce65efc1cd689c9d7a8970ccfa05b8ecf1d20fa005389bb691c81075f4b1554e862f142e1e8453c879051652544c2a311d7f04
306	1	292	\\xcbcd5011d2c474ce8761705f8bbcf1e8100a6f59b807078e521704aa38dc4178715a741687a084d33f278d88174e7d973dd478eeaf7182d56c3f83ec9eec5f06
307	1	103	\\x045eed7e72a27e5056c07aae57655a9aca21ca066e4e77ad7be9b43ef92bf8652d36435df5e83dcb2b52c6a4ea9b836982f96fa6901d601d85c00f6433998901
308	1	70	\\xa7a9367b55f07f5e344ec4ada47f78e24595c7520257f6d2e85af6339d9aece2d4a1ad0df4dad6dfee64fa76f06cf0d2e5e463dcb1beec85067125782f9a8a09
309	1	346	\\x9f12f644403e4469f757868a000ee5452a95be3021caf570bf568f9cd21b6349ec1fe7808fdb107c1da5545cf0a34531ac4ee431a1cdaf71a374d39955539508
310	1	252	\\x8e22f68f8ba2c0e1c9988fc3117d6924fcaab434e72a5ad4c9c782cce3da3b4e8344a81308b37b82956b0df15d8e95b1c2eb0d4fc046d33d625a3a9204ff370f
311	1	15	\\x4e61601f827ce732188b802e4d1e6476252307a06a0872b7f54bcb44701736902580673967d0791e8367fda00c4a25bf03edefb574d7c4f7c0ae393f0075090c
312	1	147	\\x4c1d1586a41809a1ba15102ea43475cf6c6b1243326e77bcfaa9802ebb924ca853c953a60b883cb9b91456bf8e3a1947940397b2eb7c9ae0ef7db0c6ee5f7909
313	1	81	\\x4261899434100752f8e103faff65f3d712fa174494feb0a3cfe1dd4f44b4126d678ea7a4cd714f2e456d2bc85f38bbb1250f548c9623fc1a0ec9748cc8f97609
314	1	352	\\x36957174defa1df0a3ce12feb938f3f3af8c53c18bbd689be13dc7b89f947be83269b87e37d3b6cf37717d67be11acf2af76027707fb8c87b6f4ace103f9e304
315	1	207	\\xad68a25a4843bc520da015bc8bdcad4fe0c7cd87ed762296b26df59e63e33a23d5c6e610dcd9bc64cfbf113251e2c44e5586477fdbd28990c20f458eda884700
316	1	373	\\x3758399fd1bec01105a9f90bf3f155a2679cf2a50c97ff4c2a7dae0b8dcd7673fb0538372702df234375987dbbd5521c83330d0eadfe3a362d875d61e34dab02
317	1	272	\\xd26942ec5020678f3d2ae90e6b6b78695143779c8af1dfaf30f8e547a5ba417a2cbb89a48e48cad52d783fca4ee1fa8d75e3622e19bbdbb96f86b506080c8409
318	1	204	\\x14266adf4cd9d1e179002e056601bacf9ba01a09a949729a0b58743c83db0dc5f7256a7aa480a97e26b3d48f747defbd4e72fd40b3651139cf222d098172700b
319	1	137	\\xa00659beca9b3e71b2849a341f502080c5cb9fbb3b47e32c743ef7902127f789ae4f0d700706b9e6aa2735ce0ced248c1fb964bfc4beec3834551ad3e78ad204
320	1	205	\\x8bc0c4bdf0e9e50072fcba5af6ac29b98125dc348aa77d971ce03c6b698588a8f2703a8d33c3a7351b89f483885e49c2785e28715abc5484a2e11d8563b84a01
321	1	44	\\x70a466f5c152adb931f7cd4f8d8c21dec5d718c26cd5d093aa9844964656d90878e2068a74b73227cba01774fe38befa4336d8239df786779889e552dac26905
322	1	32	\\xb56718943bab3a770d2a1133c68f5bb2d33498760c4aa966abc2f593b1b0adc24dbf74cb97808aaf451c168449eebdae7750ca2abd225f1103462b2b5d3c7a0a
323	1	74	\\x6fb071dec182ec0f837a9b8161e066833abead749aebfbd8da55079353e7faee05f8d706dbb6dbaa09ecabfeb55db85577e5dc8226ea91c8ef89b2a48375320c
324	1	341	\\xb643b595d73f6e4151517184a07c95f32128caf3ff99ee189cd829b0dfed3e11ad88e6ee1276ad8e034279a50ba44c599bd2a3d65399d88b46c7c8ae903c5204
325	1	261	\\x9914599d6401c185f0d270c88779571a6385f3679dfd30168526a1b6bde8619385abe0fcb93a78acda4db08bf32fa1f0247578905d808528edf35542ae27500e
326	1	348	\\x0176a8d49c8018170f9d28be53abe6afb91393981dd30a533e7154e4be088869ae406d02b2e40e9c70406f5eec335b5b6409a91d0f83bb03dd4f74f7dfd3aa0e
327	1	336	\\xf33859d6c1f446aaff806f00bd9da06afab333dd0e8154516a358ec064b97c17626a288fc07395c4b3425ba1e1f42190b840bd6b61c2c4fa7551e3091621830e
328	1	239	\\x0306954f1a3a3a0279952b73d234bc0c8891c0ea1599b3d61be8ffc460b10108188e743eae417d84a6d79afa46468db3537c6535d7eef2981ef5d6bf9fb7f60d
329	1	302	\\x43deb3ca60f121b47b0a8c2d34852954019da4eef3631fc9d73ef8b8c06f5f8750ce7a2ecbf01c597394ec76c1f4e27b293c868ce0b7b602c83cc987bcb93c0b
330	1	232	\\xbe92509e13e8a0d24513f85d22417482e1f4cbdec419f8a37189f726f5e36580923471dc0c81a2c3667ed4a38ddacd5c79b0dd1fe02b344dd81dd396340fbe0b
331	1	419	\\xb8534c7a4c327fd66f4db0ef45efce310d57878c86aa058598ee8e2465da33ed7347479762923cbe90079e3ee035a080e9288e1f67dbaeb791c9253588aa080b
332	1	390	\\x852111343cee0c52c74f2fc286229574e26d160601914ecf211632b2a8b2e05032025f627d012457673c75f081333b66ca4adf1e9bced1ffc248149047287d0f
333	1	153	\\xe6c49751bb60854ccd91de2734f06cbb16b8a89db8863532b19a38a54134e8572a5e0681a22174974e3c5684ce580f4f2450456368575bfcbeacab3f16e0a40b
334	1	423	\\xbe0a492b1c4edaa58541fea817cffd8b52fd1eeec916ae6ab2dc5b673333473417fc924d68fdb054bef528d571f94753eb783d3ef19f845626cd4a38063f780e
335	1	237	\\x06d1a568e7d0565d131dccc3d6ef9ce6529e04839eda77c0ceb1ac0f73def6cf23099e4aee763354607185ad0a13a4d996c73c97aee18cb2d31d58dea7575502
336	1	392	\\x2681b6f94a082bbd808a4e598900def8b768f88c58bca333db1212d99818bdc4544f0386c2c41b4f8fb3a9c6803cd20ab37f8035c7cf9c0cbf5c0a03f525e309
337	1	120	\\xe26cb1c83332f913fcaef1d5beea63654280e51ce2b0e7302e3421c8d8a7f21be9fc4c30233be0471a0cbc21eebafa8d0e88d9e6d044521f3b15b0f386b05f07
338	1	26	\\x41e0c685e5cfd36833ddb0a84d69490b5e933877d02d2d2ba8ecbe962abd73f2a8d29b66c4b1bf8cbaf5218ab58dad15361677343335a181799ab297b846d506
339	1	271	\\x2abecf9acb9ac6ccd4e1cbe649ef40c0b58070af3241412852d4485acd5eb04b53ad4c611ae3021ace79143f048b9b824d1fb1f70c7b298b46218fb9e29ba509
340	1	284	\\xa0aa0232bdd1256e8d9f325b082e3fde03003749618cad4369d3927fc09e5a9c5234aaf1230fa6644da1b081193208db13e89b9d4d873b77806b682c073cc80d
341	1	158	\\x827f7bc12f32e77d491093a9278a6963179a3998567f40a4e52bfdbf6d9df425d0a5c6a2e6d53fd8811d7248fd49bf25ce293978503364c82514768891364503
342	1	112	\\x4e790d541baf065049f1b047c5768c65b95d32f4ee4ebc841e35a5fdf31add29cf80d26471c05a6bcc67936731374ad563a12bd18429ceb9413e97ceaac56707
343	1	386	\\x84e9a24a2db2952e7b81e760586eeaeaca57ac12c017713c6eb048d33d1a1f5ce766b1a12b199a82d84ae610f9189ecb2605c0d888d70016e1746705e36b4005
344	1	401	\\xd635195bf922d0a8b5c1c5d54efd3285bd3c499f2ab73471cc3a751cd64aeab1d26c400b2c79d8729124363dbd8c78a194f48cfc8db1aad6df6c2407e6d32e0c
345	1	282	\\x612c3e94c4335e08c955323a0299489111ccd60c8cf79b778a040c94e3388c36762f390d950020c14de4a62338a16bf3fd892d1d09ffd0f456c8d68e86d15604
346	1	269	\\xbfc91d7136f238524e33cb77a1ac4278f6806d636cd89007d4569e11f283c410b8d1eaaa43cb4696380f88d8e156f87e45dac26d9b2a8defc83ab5ac1397af02
347	1	79	\\xea142c4b9e3b17aec2dd3785c8dc2213ab55a10be109d99ac499ec215416bd21f407aff3d472ef669c54556ecc0d4ba3eb60193db7566161c2e53e43ee0de205
348	1	189	\\x982bec1d33d52427726d2077c2e3c1f34b51f5ce986b3c695ef51ba8925aba0e9120c933db6b3e6ee4574d215aabbb3d8cc961039dc9b6a47739ebdd4ad1800b
349	1	234	\\x1b45333a120b1bd2e8e356225ffd9edfb21d686632579ece9a55c1647a55eee880d83a322b77e8b60343e15b1a1057b4a45558877295f4c41d0078ddf4297201
350	1	387	\\x9e459ae3e7d601126b0773c77bc36be91112fbc5ef355d2c7f145b23b00c5aeaf5e538ac82652a1ff396f322ea6a86558cd312d33a4b11a3e6eeeddd2101e600
351	1	236	\\xcea53cfde94a6926f94c30fe3f78cef4a984297d6413fe6e26536ef041d440d5268a6be7909fe7da9827e55a41f61fcb5d945917cfa76317bad2ada9f22a0a0c
352	1	98	\\x4066de4bf1999487991adf9e9521fa41d11222a9b163af669a137b6f134f5a6213d40571676741450690028c39511de382d13213b74610a9083365de0b8b450c
353	1	151	\\x9be2eb1be0a498c705837b4e1413cf6e16b8378ebd40b5401044a681debe7ed2809a8ba6cf9da2ecd29b05791ee0e211d82cfc9ce31cc163748dc08e53525e0d
354	1	264	\\xb5218bd0a5fb181053271b32711748a67c91dc924184c5eee155c5e585fa18fda385a604fb9af192cb60801d6651df3ad097fdbc76484c452d493447d39f780f
355	1	92	\\xeb3b7fa3ca0c945efc4496a2cca49e663ec46614044feeabbaf21e55b7cca55271e636316c75ddb0e6d88a90bb371ad7da3475d3114b65fa2b81f66e8640dd0d
356	1	139	\\x5159775e26d606dcd96d624d490dcb74f13c6a78ba24694311dc30c7e61e77c9a803e514e1bb38bdb940d720bf7ac8164c84fb2f992f42653eaee958e746d503
357	1	354	\\x47a476c368337c32330d205bc1679d6d9a8cc2ebe7ba9fd5f526ce9c78e1a3b3155379ab78c15ed686f72e628fe4a188c0e9c1137c28ecf021d6663b5e642804
358	1	407	\\x4cc41b224ee9ddf9daa13dadacc1fb07d911cb7c1135cd51e01c25aad4723805a6418fe4ebc54e8e645a4fa20eb069d3398296921a773b36124e74d962cd900e
359	1	184	\\x7972c9c8e7da60f41f76a148aa992bd7e6fe89e9cf4b72fe7f6ed7c46f0013453abc1df840391ee1065f475f378494270cc1e6f94debb26ed07fdd675f64ac0c
360	1	54	\\x2c97348f2152c24322afaf7fb98f8d7b6ad3c82b3c6d29f63e08806e282378f6a3f139489d0c298516ff6995ad1c3183b32a416b4c4a74e176ac0a3e52f4dc0a
361	1	100	\\x6c0c29ff03f5a23a7efbf74ebc83a46f4af7a83c292b6e6155919c5f39ace0f550de9d1ac693ada35f60cb9349523e719e18ae42a1ff1a101af7f7b0c851ce0d
362	1	102	\\x827708b96f3074111b68f816d3d0e088a19b884180675ab89bdcd1b8e1b62f248c45a2c18446d49ad4e6c9bd7dad861673e0c1f127c6cfb1635a6cebb31b7b01
363	1	85	\\x18d889b61529143c69973b7b05a20518c5af5c016d256e5008990675d070c59a939ea460e44bea9c472ded94fe0d74234b7f7fcc9da0f336ef0b2e290cbaba06
364	1	217	\\x31b234c7a6c9f90d456e0d90200bd5555b9b3198e853bf487cde134abe88bb4bbbd7c0a3c4b33d5b9032c1fccabd04926c45a10dc330fc3612e7271135aaea0a
365	1	241	\\x66d64a158ae442077ef602ceb243df8e6eef7cf72ab4e540ce748b5135a384700e3bdad5c5b3fa06d85d6954a4ae977093cd6461fb72c4cb785b3d4d39b37b0d
366	1	211	\\x3d2aa42fd200b17324c19aecf8b675c8783b6b06b119145eb4fa2dd625503b49ba7efb3ab1cfe75c49a327946f24335af3a9d6ba3c13e49ddea8a79d694f1805
367	1	227	\\xcb62c8693379fa908ab94827bf4287bd2d43f11b32c69441b8d57065c1e7c2dfcf5f70353d02d0e925ec5b1b30e1a255d147ef6cd7a55d7385607c94d33dd506
368	1	1	\\xdae895c8e4dbf78ad492b953c2ecad8d2b791318bedf65ad27fb7fae207115550b2a75ba6c8373fbbd168940633015831179499d108c7314a824ebd277ba720e
369	1	170	\\x544c32d461a204e775b38ef8b75952e60d5798f040a1e248ffa245c80c29adda3ff8a358707736e903ca865019af0f6e2d1d8de2a3aacff6908860ae845b3603
370	1	118	\\x2fc3344b5297069fb4ab6aa5bf99f1ae5321c65efb4092d9ed47f27b186e7517430b62664d6320dde113f6c7144b753a364713cd0f4202eb97e2035c29934200
371	1	280	\\x2731e795c91bb5550831718a634bdbbf3ca59bbd9a78245b614c99f1bfde948d51270c335c8e9acda21769507fbbc69f8ca8ac2518738d1a6e265c64402f140c
372	1	293	\\xda50dc5a89ca8e34a6e6d0b5fbc8168cada01c3b0c5cbf2991dd3b263694904539bb9a261b7081807167e28b65156c6ac39e7a2e0af4a144cc786202ff75e106
373	1	260	\\x3ba58adfe4212f33ca904fcbc71068c6c474ebb52ab06e5b7b4fcd48727aba51b79ffedaad81b68964a5d866b55651cd603bfe1cd1ebfce3a53d70887352e60c
374	1	209	\\x9ab32e7cc70ec7024691b67c9d7ec13a3297a5410b234795e7aaf604226368b20d82a0c4008b2ba44b4ac25ac9a275e67ebbcf7700aa279266de265bea665b06
375	1	89	\\x2db4fa78132b17022ac347a1e125a24bb6fcc6c5f16c6697be9edeabe54211a5b966e30ace8f35bd981ee0d506ae03a87ed18fef2d5676cc6c61be9d972f2d00
376	1	42	\\x97cea0919648a01b5780eef1b33d288284a8bd5f4912da33e22d846f2a80851ccfea73cdbee057042e5ddc1464ddbf1a7769437b3052cf7eb00012fafcd84a0f
377	1	191	\\x6d866d012df1b77b2ba70e372bca5685c7a38a7f233a6591c0fbc8c70bfc358b846d8090b31186ff0cb916268052f5a2d807ed043b0f188cf9561434f5484a0f
378	1	29	\\xa8954fc1a399b76ae376e4df1b51b7ab6372fe1e549fd4a1392d68be13946c5466003f33a7e6877d057fb174441a553e36b635d0f99be5c1423bac50ba118200
379	1	173	\\x316c7e92291d2f1edc65852e452590f234f1409b75801762fbe409d4fa3a0756f5f86413c89823e2d18fdba2fbb72999bdd5ed298cb0fc1c6ce2b30414f3d402
380	1	251	\\x698708a4b4a608bdefa2afa56e9911022567d6d391205bafb3d6cdd34c230df78b024d20f0b51d5bee23c49e74a31e4ba94034958da1f190434f053899b5c004
381	1	213	\\xf703425e36bf61e661d267a44acaddff1bbcc4412a3e9bd5968e00559b4b04598df7b6a069177c8fe9ef56694201eb8c462bac4852875249c53647baaecd3707
382	1	68	\\x5530e89bd70ee5cb11cd231008a2282eae09842a93af8cbc850d0d592ae0eed8f6d9580d6f7232658435085170565c49b5775089b6e5a156d05ba5573803bc00
383	1	368	\\x3684ebf1eedbce384d46d510ea9a1ebf3d5ab9d028819cd9e54689faea75e196c6a2a5dcf5f83889179546c42cb64ea4d5beb263217dd2fb4d65c31294f88e04
384	1	76	\\xf916b174235e5ce64762b1a54b4aab9b71945ebcc90ea4227ba6c592a4ae85793f4303b4d5c5c5ab5cfa052f64deb3b59532287b255bdd15f76e9c5fff3dfa0a
385	1	233	\\xe40ddaa0197dd3f56d7cb125cfc275d999a776867365e897b5a1f2b97c6127be4674327c889518ee99992212b57c5226475647dabefbf3e44a2c10952d6a4c0a
386	1	245	\\x38353eee7ae67f4f0e5f054adf3dfca2645398399ed6151842ae5aaaa6840021535ed262709ed50a1374326e1cd631e8df0d199a8f5350a884b4c6673f883909
387	1	84	\\xa16656277541a3fe30139784866ab617c27a0bfb09fa05c5bd55a03d9022eb9552b53806205a07b2f225cc8aacee0a26666296b5e112f145c78dec3128e59908
388	1	411	\\xc5931156dfb9d6fb971c384298515b4a782d12ea97be1b3e838beb8f2f1e08f318a87be4503f7ed78f02720def26f43ced09fe199c8118a847f6a3231d280902
389	1	110	\\xdb4cb48598fa4801c18626a8ced29f45008a22924b5be512eace5e21f7a2b39e3b67a326ad3a982c29b1030eaf6af0d0a5fff85e1e1f19e5a6b43a076fdbcb0d
390	1	286	\\x0807718f4c0f7f8b7533a39dd707cea68fad4485028135dd27f52fb3634665793ccce5f7c9fd54f9b2a75f8c9a481c202d6ae6b9796f61823163241395156f01
391	1	133	\\x8aebdac29e813ed6a1f7d7e2ecc0cfd2f7b033c813519eb82f3c7d0e73b9854d916c97a698df55a978860f3d5fbd6e6650f5b3b27fea18e3f9ed0599a0a90908
392	1	36	\\xe00448996be8f2f0a9fcbdf4f8e7698ad77484a56a0eb65853b31a4fad66d188fe9a36a87b3593c16f294585f7028a1de60c8f440e1ba18c340793a9847eaf09
393	1	199	\\x283b14b2ce388bf550331ab2dbdd5a638dee4a2ce884974debda50faeb792b34bc562f6d590488b6c35b4969194f045361fcad14cbf636cc8a010ff8e748fa04
394	1	279	\\xa43d3bb3e0197bea6a2e26e7abd07185f00553a811c793278bfee9f167b4dae21f6318a316f5561fa83d6e518689f4df903bd99e6db1623a2d486613786caf01
395	1	396	\\xf457e323829c4237ec82bb240dd7ddf0da9b445331b3671faca8dd9cd69ccdf7485dd10e90ead961609b44a9048db2ff1c2199a3e014d505e20fdb961ee9a900
396	1	6	\\x28513e7be2a13db32646ee8283e1123cbab6a8c5f7c75b0f5dc1441fb29448d75b76ff115debce06c0d75e7f41d5bd33c7a3e34e458e819b512c672ef73f3a08
397	1	389	\\xbf5e055ea2eb5f469bb91ddbbb012ccc0a7af5b9d3d9906d7c8deb3e3bf4732ba7a077ebe2fa53f1de96d0d019a180e1cb0598e598590305707961fb6804de0c
398	1	73	\\x55a6389bbc2ba7f4259e379fbdf2d5d75029d3516941fed246df3b115108dfb443d1f4b8cd2d2abc1f0226350b4a60f8d71dbeeb4f1a041e2835d02418d57706
399	1	160	\\x53f205c5c110e2e65438e8fa8ab2ae66b409f2b81ebbd3adcf8637ca89ad83a7635a117707de96e480f4ba1d82bbe6f697ff83c9e8fe8fb7aed4e8cd2b85c40d
400	1	196	\\x5b22d15e8efe8a13c21f01d6f0682ea47f40b396a2cd62ab084cdaee0418535ddee99f8252b261122c36869c970a2afa742820f0164327dd61418c56bfff0805
401	1	156	\\x0ca2eba39759eb97d9ada1168d9553df5895ccc0f54c5306353f0fda333d8533d3937ba9626cd9f4c4bfce9246007b88fdeaf55a911e2b28920d7c840c442403
402	1	314	\\x01a3b81d59406ed6f95ce13811c90eac9120fe5a506733a01ece19339bbca7b2ebdae9fc48e7bc0d5cf078a2de32f88e4f691a7196e4e81546f2ff092491df03
403	1	154	\\x2c459a19720c814f3a70610f00afaa8d83101e60580d019c27e372dd7e44769b569b08db3b670c469cfb4397b376bf0ad32d932346652ff4128a1092c1907f0c
404	1	361	\\xbcc9a8c6c3bbf8c4eeea6897b9f42f224d0f0d74eceb163d1e6d46c78491301d2d70153fa59ca3477b31206f9803b5207ab91cd2401c6acf245e1d0794ac7007
405	1	61	\\xdf90249a8619cfb583832c5fb7839f5901aeebc9234ebfee76e890d405f67cc97754ef67c5757e19d1b1408d0f2ece1fc81506ceb717d1366f1ee79a705e190b
406	1	291	\\x7e1fadf845dc9e662371dc6e564dfeacd2ed07f983180f60f641853f9ea44b39eb62c70dd299f489bbc6ef2a930fecf404450042934560a0d3fb515d4b430207
407	1	72	\\xa840c7fc2548da4fe0e0010633d1ba285da1a985518db5c5fbe513bca22c654910b2a64ca495cd4c8bd0887b218500e239a2d5af0f49cab74fd0339232fdfe0a
408	1	149	\\x038f81971a52039a279132c131b099bed95c8fc99229ee1362914b8c2ec0f91303e04f7eb968c6deec9d16b40727de47884673caf305672cf290b81da2dc3f0b
409	1	268	\\x9daa06f5785f47d03e4c7ad6bbe10cdd517b61f128fe1d45e0c338e67b73ef1654a26b365bae8d9078c3b4ff86a3cd0fae14ce0b55cae78cfc2d13e71d722405
410	1	171	\\x2708b14ad80b7e21985aeb208bcb8cf6bc7f1b41b03d8dff12c3f7d8f05cf655fc1f4103231d36ab05c930ab8370cb4171ead147ec744b4e59e22166e893ca05
411	1	8	\\x4da679e6f17350e80be7c5179deaf0b2a110a08dc0038296535cd35090e15a44f31f8ae7ade62a91044139e5daa4f22173f450126a8dbeae7e309c1470b76e06
412	1	125	\\xb172947e6c8ce798aed425f2652b4e584e6ff4eb7232700672bccd5280dda8221b849043d5e1c05324166a05ca36ec3391af295efed69c02dc7fc93baed6fa00
413	1	150	\\xaf8995f804fcdcd773edfd41fea9ba9d02656795064edc4d0d48441e5824993769438a2a9d1678467a679c2fa989f09049b8db33687c6b1151ad93949b39fb03
414	1	188	\\xa33dae0ced18c3b61024d65b9e6c9089e45023cc04a47d6424f38146f4bb23004c7b44b26382ee39b007e62c8f25917be7a811b09e34f504615eea971da70c0e
415	1	177	\\x36b5185b4fdc7653313e08d4e05643c291d19efdf26dd194860b058efde8bd4f536ccb7fd3bcc27a9a4c5d2668cf7b8671142af29c70cb0687676115bd35a005
416	1	345	\\x1f26aae8c4ad4e4c5d3a32743903cb6c80d7777256a397c4e291a88eb97bc505c97dcf55e2df488c59995d61dbae5163df0f030442cfecb7fc1d2e942bc0990e
417	1	86	\\xdff18d77577a4c2508126c06463fcec43e91612f86dfc739f32d9cc1aba481111de8b8cbc0d64feb43ccfabbd7efe1fb577964c4e6acf8142346e29a0cad2102
418	1	424	\\x23093083b330943c5b6fc12b9985b2bde9398064edd0b10a4d93da21c0551028fb15d14ee541e7368ab6a8807b45366a6dca6c5f1466c7de4afbddefc39cf605
419	1	289	\\xe4ec88739befdb0703b25bed76d8dfef96e1cba2980b9e27e573a770164e3ae8429d35440a6f00ffde97ccffa87cbff0e338278dfa600008c8b2f69092276601
420	1	224	\\x39cadd1cf2dfa6e5258ce22a4b40b89afd9f894668903b00e43336c1d063c01903510dc1d2d6f8404d3e1a8058b96bb2ce44f0e7327959700f59a57ffd8cc80e
421	1	128	\\xe06c4675b211fada327af06f29297680d806ab66874acd567740aa43dfa6bbf8b80281d24fca71db3400fd4edfd4cb2e698e08a1367c584648655e9681c20005
422	1	276	\\xec67fd05eb616f3c502b4a61365c43329c12dca52a0975632087dcae0dcbc6022d02f430e406e0b24343daccb938faedf6bf1eace851548c86095d5a4dcda000
423	1	52	\\xb59affda90996e8af16aa30f8743cb8c420a1a7cacc26641e34bd63bf90638033d645af28dc066945c7b5e73a265d4049e9338bf92b046093a9ae2fe226be30c
424	1	243	\\xdcc7bb7c265c288b941807a7489e0b4e850eacda73977a5258a07e7f445c02e6c6b31e686c86a7e75f35b9bda828a3a90daf8513b52cd1df53b3f131bd6c2107
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
\\x85961666db33889a3b42b74cb7f36b83de85a9c125005c49652304877831e905	1655124485000000	1662382085000000	1664801285000000	\\x8c817cb9a5762553935b50a9b62cc06817c747b79ce32dfe7347e8aa199df88a	\\x56178324eac9031cd89733ce4c7959b6f5550247d5d857156bbdc256f1b8dbbef04c2844b7bbc236eaee777cae7e2415bcfb664b70fbee02841a873b6ff82a08
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x85961666db33889a3b42b74cb7f36b83de85a9c125005c49652304877831e905	http://localhost:8081/
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

COPY public.auditor_progress_reserve (master_pub, last_reserve_in_serial_id, last_reserve_out_serial_id, last_reserve_recoup_serial_id, last_reserve_close_serial_id, last_purse_merges_serial_id, last_account_merges_serial_id, last_history_requests_serial_id, last_close_requests_serial_id) FROM stdin;
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
1	\\x7af7b36c2483198497a2e0ad462f4ff7c991e7a3954a02511996a930c96bda53	TESTKUDOS Auditor	http://localhost:8083/	t	1655124491000000
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
1	pbkdf2_sha256$260000$g5rDeAcgWNdYHIMUNCbvtR$5r+E616DXLtNkXjIuNzo/TbJunmVXUEsCXUXRI+d1LU=	\N	f	Bank				f	t	2022-06-13 14:48:05.849739+02
3	pbkdf2_sha256$260000$rpFpfB5vHYI5N4qzXmpFBt$tKfeYqFUzXkRFGoICM5rDd8DX13OtnmUClvZjGUaGLE=	\N	f	blog				f	t	2022-06-13 14:48:06.045665+02
4	pbkdf2_sha256$260000$N6iZcOS6GEESCC24ByYJcj$BSwUaJ9aKaj/n4F85FRKCqkhCOCEvSEMzqmNHUYC5HA=	\N	f	Tor				f	t	2022-06-13 14:48:06.139392+02
5	pbkdf2_sha256$260000$8V8QH0eu8CuXGLMcOr1c4V$L39T+CgVSwFtB1SCjGMFXoBwCjceiPGGV3ydXd80rro=	\N	f	GNUnet				f	t	2022-06-13 14:48:06.233793+02
6	pbkdf2_sha256$260000$P4IGDC0BB3roVJcfdnJodE$74opXqZo8ViBXCDJmamMTlLHN0JwIqJKx/UK7LO4hnA=	\N	f	Taler				f	t	2022-06-13 14:48:06.32704+02
7	pbkdf2_sha256$260000$I3KAqVqG1anb11OcMALMor$jRHLYNmEAwRZzTXnfQaERVHx4SESxLtVnEGVi4tjJKw=	\N	f	FSF				f	t	2022-06-13 14:48:06.420611+02
8	pbkdf2_sha256$260000$yhx52LWvkgddSs4N38nV9I$Khrn2L8KSfpfeCX7GMVnbGeOhgGYkNWcMMdgnWgaC00=	\N	f	Tutorial				f	t	2022-06-13 14:48:06.514262+02
9	pbkdf2_sha256$260000$Ugk2lJySj5bjx8oJGDKkun$o8VGEcXDafCDidf3zrA8CjAHrjHcdeO6GY4ESazzBNc=	\N	f	Survey				f	t	2022-06-13 14:48:06.607173+02
10	pbkdf2_sha256$260000$nUsSxTW3oJk5oyfhbdJTyw$QF6xNtgzs/Y51VgnQMqD9HFNWV8Mf5wwQeiqQSDhpWk=	\N	f	42				f	t	2022-06-13 14:48:07.052724+02
11	pbkdf2_sha256$260000$7EcqMP54M2nYRaPjcAAUtX$NVKbYsfBa9agddnXl4Gg/zF0orcNjJETpSXzKMpxsLo=	\N	f	43				f	t	2022-06-13 14:48:07.499149+02
2	pbkdf2_sha256$260000$bGpwXhN2mQoJ51g1ZFl3dC$zu2TUrGkN7k1Fq16uW9xWusWGEfJXncLl4A86mXSI/0=	\N	f	Exchange				f	t	2022-06-13 14:48:05.948936+02
12	pbkdf2_sha256$260000$jsZiLjIhF120opmMjsocSQ$kCOTBV7ARHxEgOm7I0LA/nDHNxRLr5nVHZDvK1MaSV8=	\N	f	testuser-d429mmy8				f	t	2022-06-13 14:48:15.007314+02
13	pbkdf2_sha256$260000$TaFVTeqjqyI6IjpXEivuOh$wFOMeB90chIOxcQ/HxOn0mmI6mxFYe78qFPslZoFX8U=	\N	f	testuser-nrlfevji				f	t	2022-06-13 14:48:25.606998+02
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
1	\\x016cc9658b03f3ba015f80c095d74af701921d78c9c0004d64ab8b5d87b1d241c1c4a748aae53185ab944f967bf807d9f97a7d26f2d9489b8ff29ac5ad0fa829	1	0	\\x000000010000000000800003dd2a0b5cb809e7406a52cf94df09766fdc6f49ff33e0810d473a73459c0fb07dfb9bc1d8f0ce8d3144f8d30390b1841b129fd247d19a5c9f8ef40f717ef7275e7ecfb13457022ded32bd47a26f25839ed7af13ba530a02ef4dd34b18192bd5bfe17b83ac8cc39d50333e2934af8a6e18f9992ddef379daed6ad68c8a85b0a5b3010001	\\xcea16875ab0aa87e4bcb315d493d976eff70e17f5bd9fd33ca55cab0c4d84dbaa20b9295fc35df3f3402af5db8b5f47a928dc69a95ffbf6ea85e0262a481500a	1659355985000000	1659960785000000	1723032785000000	1817640785000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
2	\\x0290ae2a4f4ef581515a9139f19edef20badaf2a89124db7b510df9083cc06bfdac24690dcf6e4084c510604908f072b8f7daa690059b03bc8187adeb9d19a57	1	0	\\x000000010000000000800003bf3e9373ed41a996717327e5b34a49cece4c1462c636b639c0bb32a7de954305d3dba8e5026d412e5445e069da442ceec4a893cf099618f7a40e71e6d555b2939efcd7fe83177948904b5463a18254dfae6d12575a63baf4083ab1313ac0d57ae5662b3c54e9d33ffe66c930e7672cb3fa677cee57d4b69e1a7da2b206dbc27d010001	\\x87a70f4370693abc331249c5636a87576f8bfd5cf5a9b065f55243cfe12b4e2a31ea631eadfc2e57416b06ab3eda94b9d9809ed27fcabeffa4bbbf598e78300b	1681722485000000	1682327285000000	1745399285000000	1840007285000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
3	\\x04942080fda102f18ff644555465caf064956497e1d7f3f33dc237821df33dd081db57d3db20b5b571a371fdb6b78793bbdff61ae4a2bed34cbf61ee10199a58	1	0	\\x000000010000000000800003cf91cb95d876e8f65e5394c5df0b3652f8772b232f7cdfec8c0b8a64da9a024223222f9af5656bd9fd77b51359b2a28dd28c028334412742b94f353744bbe8dd405e84f38812f6bb68628759b7295a1a7ab8ac64be6425d2120cd0a886e61457915a76744a61e17d8dca0c135516f2d7ff1b89fcb2dc9ee6d0552e2c909f43b1010001	\\x84f31eb9d64a6ed788576dcf69b29ec6ea3833f1f3617d7cf592f0755c9bc84e3e8dcd645aa7f16026f7a050d2a2e49c92dc0c6c987574eb08d06aa43a6bce01	1670841485000000	1671446285000000	1734518285000000	1829126285000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
4	\\x04f838c227fc10aa913234e969c3ecb523ad241c5a5c92975ee6e1fea290913a72b4a3d1500d00775aef9819f4797fba652730edb910bd7c9e22d0082790e657	1	0	\\x000000010000000000800003c980c44acc88415548b7daf9a10c9fe2bc92a9931d6064739a0c1f7a1d9d87f83919cc22284ce8bffabf745a2b68a47fa01deff0d49e0238f463e874eebf53bc9056406d7c91639ef46a97315d38bcbfdf2bbaadfbdd0803ace9463d3de1f49f71b0e5767e15753d88fa84c5fa773384a78cc69779120814fd1b5107e39fd8ff010001	\\x8ba4c1021105878bccc6aefc2acd1faaf20508888624c6a8f300d48aaea9927a1a035690443728b4115ab079ca4ac2e78122bb6c8d41a70e3af2634eef368308	1667214485000000	1667819285000000	1730891285000000	1825499285000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
5	\\x04eccb1265d79eb040e7f7e47d96ca16d772fc875c0a29ea420790c98e6e229ddde80d76b27acf5a50a50212f3feaec8ecbb8b2aa923db1427ae1d656d8edc2f	1	0	\\x000000010000000000800003bb1827cf37443251067a8cc165da03f85cadd52e5aa6bc2daa6860fbfbb925767a1a0f560ec7af6c3bd6778fc3fb576fb452366fdddd50fbb92f56c0ba20e9311a33d01f443d8215cba99963a356d039b7ee35f3256af1c573814a8a455833464fdcb75af0b9ba8c9cfa3366ff8dcdec4fae1d2d1dfc39d9c1a74620395f2657010001	\\x619f7ac04368919c03f03dd9141e3dabed6c55517cb4f5859cc41db73a8894841720492effb91e5943315b1b4321658045ba96008e4c51fe55904e52f359cb0e	1667818985000000	1668423785000000	1731495785000000	1826103785000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
6	\\x05ac537efab39566bd301da75d63ae9e11bba1c4ae2d5f5c851320ec6400b5151c6646e29ad3979a3531f53587f921a80d3f97ed46b3f59fd7f5e937b8732150	1	0	\\x000000010000000000800003c85304eab64ef2ff3727366a2b3daffc02b5b4278d0eadcb910bd81f693dd67201b04877d8cfdc14ee1a1b386e9a238a63afddce0ca73696afe53133cdf4c25e7bc517e15bee57ab4e70a8d454ac4c81a33471f5b8b50e44784a23f6b9b47b3a0b3b007b72c1b0f703ab305676e9fb0f0cf6530ab41b7e2966b0aff56fdf4fe3010001	\\xb417c5c19d92588a9052d134e5ef0a1ede6ba93f67e2623fb93d907df2cf5942b30fafaa7c26b85d28a6d2cef8a2a00a2c4c404da5ebfd8ba0ce4fa913e7890c	1656937985000000	1657542785000000	1720614785000000	1815222785000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
7	\\x08d45935ce185401095b8c268dee8fb8569073c69a4380027d5137f4791e6896db4fb934c0968916aca5414a1f57fc32b7aa726a9fcefe8ffec899887902c62e	1	0	\\x000000010000000000800003c90f930809224fbf29852a6555af006d1d79fede12b3d2c1fab669f4725625ae2d00fa1b47d82d2ca19ca0d4fdfaa0ab1c76a5af1f710953ac7ae953ecd50a3f14df1250c5b1cd3fe7e22d6f0f09151bc14877563e08686743dbfbb30c7e025124058ea28617b1b9a44967ff29022f858b13c30de1820005027c5e1508fdd6b7010001	\\xebf5af39d1daa815b3be6e7870ab6efb92bd09aa6b50af540adad4fef75ac8ce22c6bf427081e394f6376f27a4fb2c04f1160258105b9a411d668126a1bf0101	1667214485000000	1667819285000000	1730891285000000	1825499285000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
8	\\x090092bce2198b5c3aac3fcca2208c60b7eadf97707791dcc5fdae05d53a9994d09f153e6cc854903b2998f25d7b20a71e985ab3d61c0f83b2baad124b231eb0	1	0	\\x000000010000000000800003b3ab0fb08dbd260df7b49c41a662a076e89be4f2384c264b4a34eb10734827d9c692714aee5191e8f51f05dacdc018b5acaabbe0c748c9e2cefc12cc414201d46cf727d0619cdaf82e915793049a682ba4a8848f3924ba03208027c4b51ff9e1323ff28e83fcf5d611d6aa5e1aa1ff5050b2d4f733fb44ff5b81fddbf7742409010001	\\x6b82e85a89e867348f2cf7a83cea38eec84a57826c0a6af0c450bfb50931c35d203e7da71548ac2b043e7e9ef10beae389f277b149396467057bb6ebc47bd70d	1655728985000000	1656333785000000	1719405785000000	1814013785000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
9	\\x1330ce1a36344b087bc303cdf257657ceada1409f026b22743fd7c05383100c25780e4aa1edf89d8859df5686a9363c03bbf0b4b7d31a14934b703e77bb86527	1	0	\\x000000010000000000800003d2adf8ede67509a3bd28eb221641a81d774179307f04d6887848e78782dd77c0be9bdbf2dd96bc38921acc3c25089b16529dcc279dd33d6592041e66e80e232f03ddc8cb7ba59a8df8f24b54aadabd34e53ed7eddb7a25443083d1262e17e4d9cfd32d15fce550a6752a573873dc9cdc7ebe7a441b1d6a73138e9f56b753cda1010001	\\x47e80a74fd0e303e7c24314aaa3ccdc2fd5b1398b13bc65cbb0f19b71dcbcbeaaf471b55eb73edd2b7807782624bb480582bfc822325748071e1eff766e25f08	1669632485000000	1670237285000000	1733309285000000	1827917285000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
10	\\x151491bbf24f139d28e03df2e6732ae2ea9e683dad6c6a5b83fb6883fb880d4f565c627e7b006e164cb062399468adb6e3ee648fe10e96eee38defec7e1d1299	1	0	\\x000000010000000000800003d08f68ca2349123421608dae3439170fd1fc50e287ccd327702269ac1849fcb95c3463afaa57d6ed88ea5a10b2039a2a4777a45f223cf1f3fe73133ba0a45737b7f6890eafd6c79e45ef891485fb27f165fd69a511642438ab252a1f77c8233108181b2b1810917a1e5f2542c437004fc917eaa6de1fc92475b34ef08439a973010001	\\xa6a6dc9767ed7abded6bf4c7a46f1dbc621bfc9044fbda3dcacef142952690256314fdd7c7cbe8147711f4302e7235d8845a379c83e9869045f06aa279b40909	1673863985000000	1674468785000000	1737540785000000	1832148785000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
11	\\x1a9c8d25d271ab4ec5c6575752c5949c3b3846211249b9f36fe4f7bdb4deb0a0bb41b5f631ba5133dd9dc6d602c48be61535baf1c9444f87721e33de8e592136	1	0	\\x000000010000000000800003bbc91838780b7a0de03635296ec02ed2e97a74e69e901a142604b20a56005b3e5b526cf477fa729ee5158ab712eaa5c7bfb38e4eca9fb59317800537a4ea804f81cb79646283fcd88becf3a5752713d974b7d159dae2a578b5b2d6992fd183313d5d0a5547827bef4523de0de1fd3418da23c4c2873d1adde3f05b358ad796ef010001	\\xf3986e4b6c8fd922eba6a00e841fabcc282ab001ee4c80cdb6615ddc2ab9bcee7abaaf2508aa6a68d95617be1d7963a0ca501dce0c33299c118844a7d14df701	1673863985000000	1674468785000000	1737540785000000	1832148785000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
12	\\x1d9cd120496ce267d59f305e05a911ea98e051bd59c2c08939e86353e2fb1085b6912537087bdb1bea0f8262e1bb355657552c521fbaf4d7c7d709989056597c	1	0	\\x000000010000000000800003b821457b0622331fcf303e2ddb1744163927590dc50b0509d1b50e4ede1c029f87fd39b5fc996e8d8dbddb58a10deb819c7c5f232a0a3599b21cf9f3ecae8981a58e024a3ae2bc5088d40903f30f4b918d9458b36c906599d4eb911998a1ba6db23bd50f88034162346ecd691b88ef78fb43bb8dcf91b5c3a54cbcaa346ee78f010001	\\x904943a8a4cef1d0dab27cef9a478092b5c435b4902feab65f8e1a9144b0b39aef974518fcae7f4e32bff01a082c620e3d3040424f1187653101d89962cb5608	1675677485000000	1676282285000000	1739354285000000	1833962285000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
13	\\x1e30ac186f74f3abb0c6b5c063247c84f1e70a25526511c4defdc3d8756adc42b32e9cf6ee63ef5c953a3f12f0934215a91f5822c2e3a427aed6a02143848b4c	1	0	\\x000000010000000000800003ca1d1d56b6a25439e44b4e97c79c6d303d1d4683ee6ed78af4579c6d203f063b0e6a5c8297b1e7735fe312d93bc170b1b0f6e2659708b33c75dceae7ea85e91421c3ce290ea0815b5f3e90a4cc48558ef9e2efcfa31ee271268ddee8e164129e9310fba334fe0c4bdeb23621ffbc1ae87ea78538633af4f7cd823babde71cc93010001	\\x6b5427470a4c8fb9fbfaeea44d9fcb5e16d01d7426f1f56bcb20a297b29c527ad310bba675cf24c511a15e582211d0e6c3eb1c181b8d8bae5374e097213f0809	1678095485000000	1678700285000000	1741772285000000	1836380285000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
14	\\x23d865bd03aee5ebc85f6d168ef1769c706679a5ce4627b2c585e749b36dc70cb1adc14536f1765b091987b65d69e12afa97ca887b4458176d390a3bc1479b3a	1	0	\\x000000010000000000800003b7348cd7e987f64cc07b2fcf90216515a16cfc6ed05441459e11134f6553a25d447820f878824c15c1489395803548defef383574ec04a8ca3325245ed50c3b2bc3bcd598c9ecb17f973ae2e60156454eadbecfb6884298b64827b31bd996bb6078552a0be2acc9c8368c9085aeec68a3adf22f5c4e5a0ec50dc30f3320e653f010001	\\xc33183f33d61fc6d03a5ae60c1e51bcaa3dfc58e6d57c68e78f87aeda8eaa74d7463ce48aa75c3664ef3ae1de48aa53f407f9e57cb739681290d0471d4250804	1680513485000000	1681118285000000	1744190285000000	1838798285000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
15	\\x251caa420993d78a89527a7c4d53a6757f55e2aba32a9298f5cf62c4cc9e4fddc3432f956a6ccad9722205c9da02ddf734d11cdd0dc403fedfbae6c5107ad135	1	0	\\x000000010000000000800003bbf2817ae81758544d0dfc781e30ce1fa954e0a49d4f42d28163b277e6bd483ed6429246282d8f00b0cbf558358822b33c8255f9729b6a844e1da44e77559ded221a463381c61f92d7213d49c9e5940bf65077e0804d499499ff56cb129fbeec32a8d9e248530be0898c3693509602368075210f126c1ec2b118390db7319c37010001	\\x50a8cc0dba5e266ce34f34350f5c07be7838d8e5a436e29a2007a80bd5aea325d1cc497578873bef94a4d1dc29773483c48a2bbc8973e8ad6d7e3d5f10727409	1663587485000000	1664192285000000	1727264285000000	1821872285000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
16	\\x29282094a2a84b81790b380aa15b0929c9f46824ecec1f913647436be99eb45d09165039d9de5c41c96d65ae9e7769f6bb091e51d59e58236bf406101cdc0352	1	0	\\x0000000100000000008000039fef83f68815207913e3627de0137a64e97c9e09507d79f4b785037fcabd5eab827e601bcd4e9cd79cbd7fb4c8b7e26318e55c2a569787697d15a74dfc7b0e826b22ade9687976e7db3ff7bac2fe8516e9c2a4613766ccc67cca1dc2e306c56deed9bc4adb851addb4b0687735e5dd7adf372b90d19468f0c9c6cba79e2deef5010001	\\x0f58c5028dc88946e145317f1072a8145d5919c45ff2da9283646e4be93c0a2f8d55b3c59e9f27d3fd73713e89519771a2b579096a01a327bf4ab67806af2202	1683535985000000	1684140785000000	1747212785000000	1841820785000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
17	\\x2ab03a10fd8b14ce9b00f695a39eb42b6138bb11ed058e1f86ab268914b29d72a1afbdfb8346ede4da1149c13e672ed6a4d56cd0e22c58fe176bc6c4821b8e12	1	0	\\x000000010000000000800003bf5eab405878b0c9ed6f19f1041bf91da029e7bb023ba1aca44fb0b31e16b8c391ded7bea7e17224de7c9747ec7eb731bf3bb8b6e2419c4dd21cc09569674353b40ccde05c5f8c12b50c9010894c9da8e28a96c6766804fffdc8178f388b68042867f7de937a80ce0e2c70b86a32e5825cdd28557110d4d6aaba497a84be01c1010001	\\xab2b90d9508c22f2f2175791cab2bab19e7d3d378c66ea06f372781d080d3a2d339400ac087f3132d1a8bfd6ee79f5d9228668749315447190a805cc5b3fd000	1686558485000000	1687163285000000	1750235285000000	1844843285000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
18	\\x2bb03531af646be885393159362255842705eea27764dd54fbb3a68dc2a1bc8322c2da22cf698b451ca2b75f9dd7a3ebab029b06c7dfd291636920e2a326d8f6	1	0	\\x000000010000000000800003d45abb408acf59850e6bd1d8deb8a3670855fdd7962d3819ca1c48d52ae1e07da9ab25ecb981fab5e3e8a4932f21420f94a848183f23065f8e961ad1ca1ff3d0ac473854a7834aed330834aaf549a5b409ca537e3bd9cbad906bf0bcd6d1efaa1a1e9cdab5390faab5c6fd3bc2a1c99f6c5e18f1ae8e847544377e06c748d543010001	\\x6898ea11369ff773d84c54b58c06b8bf9cd893a34e8e3eeb7f4fd9643c3030bae83c26c70c83a0b73e81ee29a88f93d9e5ee51ddff5153dabc2a0d91846e7602	1671445985000000	1672050785000000	1735122785000000	1829730785000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
19	\\x30d062a0fbf20c997a8578ab343d460f55d98ac35f3875d9c0c701429f005af893f4732557a6f5dc8cd0b262571a0a594da46cce6a3116666d45354cb0ef6ffb	1	0	\\x000000010000000000800003beee1d81a361a1c009017e9bdb082437d00cb5a30106e61b94072d9bd0fe6af79774b0aace49c1add93e1885528b09b31da1e80e30ef1c8749d60e4ab102ac088f1f66c3bc4216827ebe6acdec36f301a56b34922908f7e8c28199b41ebf6b53071947ec532d299d7442c3e282429dca523affdabbf435cc70def5ab6f09bfc3010001	\\x56b0bc6a3db8d73b9197ee2ebbf98b5466b4c242107db1c627e5dfc7268a8864b3f47631f57c15a9bef5ccf2ef6c3bd174b881399d63726bb2db75bbb151ce06	1675072985000000	1675677785000000	1738749785000000	1833357785000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
20	\\x32886ff3d0f4ab04d10bc8e8f2c7f3d17935446e3df98a6b4a7b74856952ecd2ccfd5665a6515634e4eca0e95d9cb45edb98d49a9d6442146b1f76785dcc60b6	1	0	\\x000000010000000000800003a44b8072130626af48988694a45efdb24f4b5eed2b5c973e92ee97d5fef5041b0aab45a5f30a09cbc7399226150c24bf007f82560a7b25c0a0a2ac7fd6b41e3d33a22da4c4d5a21a5668395537d59683e05832c3e68d11cad861c333323f4788b674b7f85752177bcc72471945f485643e97ae258707776c7be692883312353d010001	\\xc2df0659d1288deacc58c6b5200c5c5314e11875fd8f1d5927c30ddb47fa46a6b9e7d3d412fdfb52cc34b799958c9eb227992cfa5f6a20d5bbf05c779ded4b06	1669632485000000	1670237285000000	1733309285000000	1827917285000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
21	\\x34d07a65edd1c8f89e8f16c83d9cf838b885226b6b19935339f7c02b930fea4480ad20b25c06a272ee9d4c66c2322d61c8b4f4846a148f5a424fa1b66256538d	1	0	\\x000000010000000000800003a2349ad1993a73d4426bfd2194524c3ce5462bd7990f0071581a35207613c210a3be93745b7dd37d91f0858490c26a04fb001596696e297827bb99450ae914080da8dfbf9e2686b830eded039ac1454948d5e453f32609e97be5ee798c4d0048cde7aab3f4c4e23375c5cfd5ed34ae4880d1f355d60139d1ba8ba6b03f87bef7010001	\\xfa443cbeda5617e973ba7751370fd9b63918f9129c6d9d4ffab80f3bb022594e86c295fb1936f3e862ea9adfd3c9e7319b73843f094b640b2431839457cdb002	1674468485000000	1675073285000000	1738145285000000	1832753285000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
22	\\x34580a5cb1317a4b050d9c9dc4d14fbe10e022107416b033d7e66f128c3d7ad02f2f40647729a780ce6a2af7a75dcd7f950fd86b14511b5e7d407b516c0b5d0c	1	0	\\x000000010000000000800003a93b3f29cc61243b3264b9f6a3c3096910ad41027c61eabf3f40802737694ac2e98f7ac8ade86462e55bd0dd239bc1ceebbced5f876cd69c7821860bc38451a1c25da330927c095d0b66d75c9bb0ab633aaaf1419db78f8d3c2657688cc9bd9668a498541728eebf43dff390e9c9d4eae65fa4cb25acb95f2c285f54e152a931010001	\\x1c1363c36a5bed55a8731fcb632d82479c6787453c7939540cfde0f4a45ba47acd9804a1247a41aecea75b1ec91497e16569db02b77253220888619e3920040d	1664191985000000	1664796785000000	1727868785000000	1822476785000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
23	\\x35701be3e16ab44b8e68abc0a87cc1101d136b6796187ca968e064f01a51f07d4a8eebdc5f265e2d887f1c025b9d73830e855c942a3e2aacd52239dc1c460a84	1	0	\\x000000010000000000800003b5bb841dd8bc6038fbed05da579791252e6e60901011d989e9b86cefbc1fe5ab4929c67ab3e5de38a926d476e7dcb0250462d2b62baa9c8f92d71278758fd36811b16c9d2f285dc3bb4605f83b697b84aa09c0d78b57ed5db619570377b279b3f33e8ff88f1b0ae47f083f275d0e85fd5d3b5edb8aab91e2f6dbc145309b57cd010001	\\x22d12a9b7f75975b3101b7cc7bfe627d3764739271b92d3f56256e6603575192f9acce36ee281c19ee32f6e5f463a8ba9ff34e5de01c0b10404cd5f808853704	1686558485000000	1687163285000000	1750235285000000	1844843285000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
24	\\x370491ab3bb74d2a4b5122f3697f755d316fd46efbc0aaa453f90f7bdc0459f9634878e42752173f58dbb34355f6b2ab8e3b602141ff1ae336fcbe42f97e2eef	1	0	\\x000000010000000000800003c46de11d08685e06a82f65123b111e990f9a03fe51ff9f41f90d9559fb6457fdaf0dcb66ad24f3af3943547c3453ecbd68ee4b55ee380f64b8733e9520af182c045017537228c0112c5f478a2ddb0a103c71a6ed60bd9fff73cf070696b8d7c887fbcf2a6678cd09feac7b647f04a14dc5ae0f2932766ae01cb5c627f9e0713d010001	\\xc12b3cdb5f93c59f6623745c5cb17013ab13bf893e9fb348c3ddb756f6fc5033084112ed0a7ad69cad9b15d25e1f9999b37f3865fa36c5c0914164f6ac289002	1666609985000000	1667214785000000	1730286785000000	1824894785000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
25	\\x38284332c84875e6f4370aca5513f061f573ccca401bac2e54b507c9cd0705457069fc7437f22dc0427f1090b84107a7a3b2f08bcab58ec0eb96a78b8dd04fc7	1	0	\\x000000010000000000800003b5b0409a44402e8c921991d17398c2107b42080924fe5efa2154023a060774217cdac7932ec5266d2ca24891ceeb7b6c75836478c65adc327ff83e808d8a210c25fcce2c1ea4b30f8a1fcda10d1aba10f060dea70c094dfc4c465ec54874d93ec8d272a69941f47f9785cd4f328c7062b9fa3564e5d986b02f8f894e6583253f010001	\\xe5aae1ad0f8c8c819b18e8d86b2a4daecd246a347d3e65e3630663e9e884cd6c970771fec28114b03647e3eb52f258b84d8a0adb09b8e2194405582bc7fad502	1676886485000000	1677491285000000	1740563285000000	1835171285000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
26	\\x390c3d4e0ef34d63abc5dfbb343c745316bc20f619201b10d3e56bbb5c2f9969234bf4f00f798fc947949a7dc5e95489e1f9e59fde2af074afca4ac23e82994b	1	0	\\x000000010000000000800003c352685927b83f03aa9d5af0c45bbc6df144ed799d058c5f59d994d2e3f9e9b07c5a23ece81d5626b4bd5f1f6e94e34dfc84bb57bd15a19fcd6d8eec1c8e13fd580500d9d1d281aa47ca8c83d3cf87d472a4a287a262cb38d30ec0f2b7725ee10b4250cf122bc36a8eda7d542084769abaa56d4e99381fab330375e41baf45a5010001	\\x91ad53889b016c150491f4ee48531b917dbbc39d3981eb2701ad6619a3070a28717537a2e07260aaf30f1e3c37909debf1f27f703c581c99f894e7b09db44b0e	1661169485000000	1661774285000000	1724846285000000	1819454285000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
27	\\x43d074b569daec6a4e44ef6a5b44ab8325226bd69dc14585c15d1f9ecf937227585359bb6c0e924fb6ed8c953ba8f306151703dbeaeb13e99ed5b948693739f4	1	0	\\x000000010000000000800003eb95a0c8c694c7c5d52a36da66f82ce5ea79d3ae06a51efe620196d208ff10d3ac3eb1403d9b2d5e1175925c89a95ef856391720a8754e0627c3b4bef642905301d2476eebf07cfd67df47f2d6a850b7b83c476602a9a32380360e0815b7f54789947bf7c9e9b9f0780f94388f9d328d8b4ae056848f59c338fb23eb8b12ae63010001	\\x31d4a1f2f7e0e22911c6bed0a65f5c6910fc0574d42612df136980286948876dd3a29a8edd09ba1dee71affd69d58fc07057ea52d9091921e05e45f5ca0ea800	1669027985000000	1669632785000000	1732704785000000	1827312785000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
28	\\x45d47429e3bd4b7aef8361dc8415e1d6add57ec280bbba31ea01d27bb4f202e71223dbc992e56bf02f8822ed1c206922606c2e6b74cf77da690f4a67d7ee7cee	1	0	\\x000000010000000000800003992767a3601239e1432aee69c8cfef27aecc8160c3e02c67d8de0d0e890ccd80edd85948c480cffd2541a472dfcf287507b058c1ada78c2a29596012f3ad40fc8168bd6c00213f2e5dd756cd68c45bfb7982fbac153980b1aae3bbeeabf7cfce2273a76ada806cd843cb5a107e5617632b66474e4298fc35b1c6c001a969e4df010001	\\x55c63094496634fb2c159bd4e5e5e31bd58a23934765e19994c2211d61f25886c19d862291186b257722bf4d302b98d0e1ad395349a1969e3fa6bb7817cfb300	1674468485000000	1675073285000000	1738145285000000	1832753285000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
29	\\x47988bbbe5f9999e5af8d7d1e749e4763dc9da5db980d44e6ca29481faabb9cd8038d21150131dc318f4f38d8e23cc6994fa585b183303ec361d0965a479c3bc	1	0	\\x000000010000000000800003dbbfff78ce5832a61f984dc6f8eabc599968c0cc1d25ffd077f6927b5ce64b05ba8833e0d3ff9c94a7c4156303c501fda647c1c32edc1020fdd39c1d0b5738872074be00d759c3b1f466fc25ab8149e8c139fe85c6ee6f0c4973a4caa2d2eb907928cc94c206be0efc55e7768a0e9123d2139e8ab3ecd8add09b02eb74e64671010001	\\x2b300212cca155c240e2634d7132fc3b2b8419bbce47485f201223cc331f6e5ecc28f6d405791df81a911d85f8ef036702007c57ae58906342e7cc02fe2ce500	1658146985000000	1658751785000000	1721823785000000	1816431785000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
30	\\x4b0c6267ae7fe3d62c812a3cdc1e85968ac34908def079e788688639393fca2f49dc440b356b7b982f0c513accc9f59a882d916b1d63ef019158828635147b60	1	0	\\x000000010000000000800003d4768b2671fe348406d0ef78ca1676ec983b08b4577e34633b992ef2b92e46f6392f6a16c616623f98eeedea54102f1a661e7bae942419ac0f85d7e9de10770da810bc8c2ec472089eb53319f059bb211c07e32278de4747940839ada77c469bde3264c5ec108644f9a3a8c2625990c356218f8d11270e6cab315071f689f679010001	\\xd4219cd7b9b1560bdebbeafd1d340b22b2a2231c4ad133659b5311e1e8b2001eea8416862eb810b8065c8abcd0b68cf936a2565fdb469be143e78c82b728230c	1666005485000000	1666610285000000	1729682285000000	1824290285000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
31	\\x4dc8e02a4df73988281f197721dbb1c93996c4c0828f737395118a2846faa91b060ce7515d6153e14e08de31f6100731984b41da0575fe931c2790ddf18e4599	1	0	\\x000000010000000000800003e1ed035e1b862ab46ed9bd87a3d2820042d8467925eb5c6ce518086cdb3f9e3f28cb653cbbf8c3df9ea749b6a9c8baaee4d9e13684974b03c53d4b32a240b561749b1a376b3a34ed62110ce751e9e1c218a32246d98cfe3d31c7a06722f40c71e3944387be4b46e02dabf6e1ec9e6cbf32d8b9cf53028adc0c56327c09ed7875010001	\\x8d073955ba1a1a61f01817876ba79890e937637485d1b85d06f639beec0bd0c924c52ae67914b0b3f51e057a90bb698ce121ba77800ae91867a7126a6b9d6608	1672654985000000	1673259785000000	1736331785000000	1830939785000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
32	\\x50d87224949d97618d3f59d249c3d9424b2b195ba23ba73c0eaf4529d8e6240c8a5787f828bb80511175cddc80a03aeeac5bfdfe5f69a9a50f17c0501008bfd2	1	0	\\x000000010000000000800003b8b21580a3c45f78b3af84c8c52bdb709651ad824840c7f0d7d1462a3ed63a3b9bfa6cd35abc0010c7747ca5f26f54177fe1c46cf3ed642a5b1098eca694dcebbf4588f5bc393eff273ce50b5369bfee82ea31bca20d5f728c53120ce7b2533a53127435f25452f7b1e48f6a0ce0e89dbbb685bd3bdc2e109c3145f11c8b0e83010001	\\xf24b805b363fcb616663374044eb72c1d45d14f6ab5b739e7e3ade44537d06b21e347f9d5cb678d35aeeac4935a00c7efcf3beca12b39c2b868cbf2a519f670e	1662378485000000	1662983285000000	1726055285000000	1820663285000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
33	\\x51ec9bb000d653e51f564332c97e263c39805d9aa13380fcc4bf7015145b7361ccebb18324845e935e97ef047bc3ecc3b21fde32af03ee0458d2c192bdf2ae27	1	0	\\x000000010000000000800003d069b2543f595f505d8699298da3ad57d19dada5aeab7eca396a86dbdb2b716fb007495cc4a7c98af856564e89d40dabbc7e94012968be39df86c24c86fdc678ff7ff8e09c8847d92971e94e8cfc9226d2e130f2debfb3274d472580ba190840aef28fabee4b1ac99bd3720c9f520405035c45144db442b162c2708c85ca55d5010001	\\xaf32413866ba58872cfc7a12c097c5e7b0703d412a956213152d04153fcd2ea844f78e801d7595756c8d1d00307fe5cd78a86e35d6791d7517505c78d96fe207	1669632485000000	1670237285000000	1733309285000000	1827917285000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
34	\\x5648137bdbbdbdb0ac9fe6a7867ff2e123d5635a0724fc3ccb744f4973953c183b44cc1ff95a0ef2a6b4c63818dd63dc389fad2cd5807cb1be66346aa6376718	1	0	\\x000000010000000000800003b78863f62c30cdc3c97414099e300cb303e80294e6ffe64dbb478c120dd4066aa973b2f044a09926571f722acc34397039d8707371614fa9296f2dbc2f2beb77285120113c7be8f696c769b3657a81b7a92ccc4a3dc5bf2dd421690cfcc3bc593df474a6dfcbd6ad6ae0978492b003c3c5310e2d16bca4c995baa4035c0fe4e9010001	\\xdfb5f8a63c3cde84d811f87747ae7fd91db4a68cdce3ebfb77c8e8b4ec21b106d4f082b954463e1c4a984ef4e985fdece0504ca541487fbd9ffe96f766cc910d	1673259485000000	1673864285000000	1736936285000000	1831544285000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
35	\\x58cc18eaf9d7f4fbe0932248f619ff469d9bb04c776bc4d4b50cbbc5bb3ef795a37d11e8ea2891598d223c47b97f1d03ee6ae1887a5adf2e3c04bd486c31090f	1	0	\\x000000010000000000800003c48ae0df12f63035fd75990ee5466e1f2d9fd922f0eb61dee264ad66c488498a0fa21b627d2bdbf2dbb82812f8b9f77ec1aab1f6bd4a64e365aea77573dcd92ecbb9459ad7cc9e901a3404dd9f8e95c855601ddf7a55575792c5854b537fb8c712a37752eb63a1e22775b1e640fbc4c4209eeafaf4d7faec8c442c9e499b6fb9010001	\\x4a9c2f21ecb16e07c5d6b15f61e5e0ac203390c2ddc270128fdcbdef23f03e60e27f61176c0b640bf13719064595c0746726f8f8f36f8b3a15acb182e5faca05	1667214485000000	1667819285000000	1730891285000000	1825499285000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
36	\\x5978a03b7b2a1151e29701a38c7ed2c6e5903e5fb5147cd2b8e5af677d2b7a1152e0983b38b72323bc8166da3b4f97b802e158c0949797b0e657370ed4feccf6	1	0	\\x000000010000000000800003b43a36e33a1b27d289018d9df890d35e06d0940ca37e8a5c11b5c5ed56184a8c07b74cc1bec932a0e2cfccb6b7e656c0a44ba5294fc6bec3d850e59b79aab5108eda67e8ea5753c6f00911b920525d290e672a24e2c85fb48869f0509a7081115dfd3d765ca18a60dc3fc942726b98eb3d5a1346669c910548e6b41fb27c383f010001	\\xfd56f2e162941e8557b3c8d6bfe41ace7596345b1f9f34b98e4b67c890267b5610c8349213950872b8571d8e1804b05dd690fbea66225566065b6c4cfd48c80c	1657542485000000	1658147285000000	1721219285000000	1815827285000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
37	\\x5a00c6213e3eaaa49880e620885f59633dacd15abcec16c8f4c1a27ff6b7cbb038eceee78ece449981540924537f621ba8d8e728c1b4faf0c366c712d1746291	1	0	\\x000000010000000000800003cc205daa34591e2ea8d2ae681ab82029123abc8d0d0608f75e14c6cee4029bb6f0ae322d6763f37d974d93a2941ed1557d43b9202c72f22712090d78be87a525971ba9e9f29bf43ee974efb53732d5b5761c3553d4647b91657a30a6e9ed9f7b9e6dc37fde29d335aaf26a282301ac7bbfbf24a5e3d5f0e5704e477b3b1f06a3010001	\\x95e3831c6ada18bbb1a5d8c8235a2762b34e60ba18f465415330a76faf5e918fcc090fadf42588b894b7f064dee30dc4243945232354eeb41771b209d5661700	1682931485000000	1683536285000000	1746608285000000	1841216285000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
38	\\x600c3832210a3e5b1ac93239173d65f643432a564e65d0ba65fa8fe5ded5df643a9bb5b7a86de858c87aeb30dd7388429d7aa0de9e41fc42a8149c5094684ff1	1	0	\\x000000010000000000800003cb8aab6793b01dcfd42c84c9b52aacef4b58810c14184d65a3009761f06fbfbdc6e0eb59b15ff470943a46875c20da5a12cd45c1f64f6defa4a138509568d351b701b4cc9fe0030caa045bf1f40c660c72686d43b7d605883463c932da1796f825c93d80045012938c717021a1985588430a030f2d1b8b304ea22b574836cfd9010001	\\x664883dfc9a4f944d88778b9f14bdeadef0f0cd6912067697e06fe0913160a840e677acca5a11f547c7dbfb6a9de78a1d288cf6bc19456c4f370e94ed5a2fe06	1679304485000000	1679909285000000	1742981285000000	1837589285000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
39	\\x63bc3b263cfc2e83e9fce4038045242c254cc78282b5ed32ea0cfec5b133c6177afcf887621d42da6f700ecd278e76d27ae6190a9162ae1b04bbf99f8232708f	1	0	\\x000000010000000000800003cb76c4d82681e8e80285399a965036979a2e97a6ec843d40ea009a3a0480141fe48287e874e943ca89d71e1ceb2749077070f8e49d280850c85008c9f16d436fa62251c735f1153b3db608c6be3532b6c8e2de51b5c245eb51eb2a0f86353b263a65a54d4270e1d2c15699722151e33b887278783a68345ee7fcd877a9b01565010001	\\xd042260acee0b0a90a0b7a572d6b77c6e194b490f91f01f8f2eb339f3b8b3dbb88d921fab8c8ffbab7b2dc5e1058c1f0e1cfbe8f2fc171d6f9bcf92c6ba82b0a	1675072985000000	1675677785000000	1738749785000000	1833357785000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
40	\\x67c8c152a3f7f6591e71dc5a15d04258888766f39754e76fa1097dc99349a59f4cae4c54bc295473d9735fd1e4c28422ccd9f81045cbd2c3056c519df8056fbe	1	0	\\x000000010000000000800003bf202ba79142aeb2c9ebd981397475a3a028a389c432c5b8c320edf8d9e278d1f5e767a8fae1d7617b1d4ea123f96d7f43b48161c5f84a200bae7f62e939bb3c1810aa0b11c81508f9cc06f15cfdbc8229677612e8389fca37752de9e799712f29868df7549ed2032bbba114744d285ee0aeea4995f30ff3d293685c927d55fd010001	\\xb5e6f9220bbc768102e56c1f94440fb4c129f9d8ccb85e9d948d5d1741581382b4f871e8b29ef9b11acbf1c0dd5b467c4a8e16fbd77399d154d3cdbfa09b560a	1673259485000000	1673864285000000	1736936285000000	1831544285000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
41	\\x672846c811fcaa5c72a1c7b78e9db157ecec5abdbc45c97103992886481565c0d85aae35c70796583e841a4b219ced63fe28cc642be3d58cebdb650976932911	1	0	\\x000000010000000000800003c0d345d4841522b3a6c3373bcaff31a5398f5e346dfc2a65125a82d905f7ce77bef1c311a62f357dd39e8f247504e2d41924101f9682e5bbb6f9156c6ebc8f86f25f325465dc471e9672791680fc67acd9055dd7abba2d237f643a393c627347a2eced0e47f3fcef3db9205bd22e7d51800c92b680b122b0a4858b07d95fc359010001	\\x9a464efadcd70972c94b7c87891bc1918f09c032e81bc5e37ebdf5d983fb912ad989c25d87a8d1beda2f7a23b2da3a70c4f406c38d62d7fd4cc54136492e6f0c	1666005485000000	1666610285000000	1729682285000000	1824290285000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
42	\\x69042c90ea631a46cf8a173f6d20ac22fbf1f6d17a030a04c95c3a720bfd6995eddd673d93a7783a8f0a9e42dbb6628bdabf53f94a20f1e77cb16b5f9f6cae5a	1	0	\\x000000010000000000800003bbc3af06a7efa2ec1b0f3fe9f7978390916594803eb35e61571559bed6a3f7ad36231d2ac0f9419eddc7178e48214487abc2b693dc266468bacd24b519f4c46c773e7635d9f4d49a9f615d413b06611e2d7f2aec13a111f4a93aeb445ee2b1f2fd557ae8f0b5005bc32f1e3e89d26eae4c09aa476655a38785c02e013f943841010001	\\x4c66dc7cc73756c190e1582a91a2baec9bb41e9e1de4c31f999bd246b8eddb6ff14aee5c863662c95cea64b2ec6530abcb2c8a0abd5653f248d5626c69b50200	1658751485000000	1659356285000000	1722428285000000	1817036285000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
43	\\x69a42f1f947dc41b40b8637c0dacc44bf9dbaca2bad73d9b62e66ce7262a0ec5d32fc6bc61850f8c61ff2fe3bf435a08dd7707838bfa3d720a846973d2e2aea0	1	0	\\x000000010000000000800003be671dbe61383f077bb71fcfb3df050ec07dda5c7b9abcd442535ba5d8ef1c05e6e37898f3167e10b500a66482d0b096fc62d264ad344767a714e8de720dd5a427c13de978305c2e167276cdfb2ae171daf3504605237e7330c441cdf1a6c4502a11fe21c9b7d2eb5b2840abcec982668b6ac2a05454540cb8bc41f9ae1f7a7b010001	\\x008c0e26f16751375cdfb3be880ed37459286a7804b4bf1d3cc7d2dbd37d5860008e94e9e0199c2730de8220d81e2de5be77c61598be410a16da37b618e10604	1673863985000000	1674468785000000	1737540785000000	1832148785000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
44	\\x6ae4f0f17fec0ac6ab161e64b876f538a72b5e60ec5cf6222f782f19b6801e95b17c3bda28a522596af1755a1aa4e8c47e213ba04e915c6d2947596720ce8b6d	1	0	\\x000000010000000000800003d85b391cc7089009d7d09f29a6292452c8dedbe2d2f60d7edc0dd34cca5cb8bf14f5366113d76feb012e24e05bbc47a9b2f37262526d90a9037cdd777209c2ea8c2484547c725945f91e191e0edc02d04d0d8f2f49e9f6391dc4c2454879d1405a578d3cb1b7ac6c7cae58d9aaac42cfd8889b4ab018c3810a4a9836f53463d1010001	\\x568c435f1f8598f93171f0fdcc12116bac9c291af863085823101555edcfc8c5aca1217653bbaf532827cc33b738b1aa1e30d87fa50c36b50c1f91d8af77e30b	1662378485000000	1662983285000000	1726055285000000	1820663285000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
45	\\x6d1c8d7588428529a1250a802d1bd46fb2a06d17779ff2363a2512e3c4b490b8529b9573e3538002b5e1c6a572e13b19e2ed80e408337f9a0e6e9f66be3d08c0	1	0	\\x000000010000000000800003bfab1b3ada84d511c5f030451ff4c684b95aaf4680c232f882124c6e9f5c04d8e30367f2b2c8a06122d213b1ac3a49fcb10f941bf82970c0a211748876e161a1c455705e0348d998116032c61a7feeb7202058a27179878954a0c5e02c381c6e1207bea4c7162ff539808d910f455e84fc410d39e67040a454b4a8474ef0ea63010001	\\xfafaf28b2031657a487cb45bdf73de950549df09b6601ee16a085787a398c5bfc3e6a994317ee81623def342d6d9f13baeb65a4bf1451e2751d6f184ca9bf207	1685953985000000	1686558785000000	1749630785000000	1844238785000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
46	\\x6e64472db9317707efcda1e9ac5977a2c456a3e6cbaa4c765503b3965587aadb99bf4de96244f9767af78a9054f52d993c30fa7792afe84abca5b068178e35f2	1	0	\\x000000010000000000800003c4d6b91487c791d5b18fea18939e9ed911abe1712c1f74183e1634ce8df88d44e2139dff1840fab039c57659ef8e9617a64a48a80d5bd0103456d50d97a3a3c1275664e57584b3e666f4eddf2879d6169987991296f65dc6be90a9f079206fd879cd258aad5eb6ee3a7bf474a0b3afb65f50e38738076259c39c431f3f8f5b8d010001	\\x6f0c18ffb0354ff7261d3017ad353bd27082f46760167501f68971bcce2ea8070b0807a57913e17806339c9cc05ccc9d7d51f9686b611a2e6190dac5364ef10e	1666609985000000	1667214785000000	1730286785000000	1824894785000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
47	\\x707cf2baab2a2fe8e59d52d87fb2a494e463549ced996fc63784bae0746491deabd8df651392e7d763549187065af75560f5f5d84bff234a115071bb983ea1cf	1	0	\\x000000010000000000800003dc6211b5c2be4e4a3a802b192205cf4da78bac854529c5226bf69952c170218553c98fc832ee23d095104d132e5d3d80e05b34808b6de6995bb99cb6fc02c3acf23122d3364203f8bfb5306ba320fff5cc46762068951ae4879a65523c84616fd82a5c34299f536ed307afd79915486a3d54b70fef4d94a295bdc4b776c39b19010001	\\x4af7fa7fed473a97d1d78a9945b3e585806210a1a38d8f957fecabcb7e90f467df413e5a57995ebb14479962c07bd66a9c0f3744c3a6cafbc7a2a33ad39b8e01	1678095485000000	1678700285000000	1741772285000000	1836380285000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
48	\\x714044419b8845d446fd6440af73d9dc86683b1099f12669d5ff0dee115bfdf4a61d28942e0039a86525c87be02fc45c6c72754e84d01559ef5795cffe8b92e7	1	0	\\x000000010000000000800003d29bb4ac038f3e43294e4a620b61d1d6e535fbb38a66cdca57b0fc986e2b608f162dfb5fb93606087df4f548ddc13e732ac1c141aab29c3ebb41c46b92cdb1fb8a4165186e52689ee152260214c6a3dc2d38c368765009b3f9a4b4b6d833cf842899cf4aeaef583db1d9d45e930fbe66b21de234f32cb01d45a48a15099ff8f7010001	\\x283a02529342b080580cac04fef0751b4669cf5bc08958b324bb65a20d8bb56898935407633001050cac68e609d739021571bd9e9c8ca09eed79282655cefd0b	1681722485000000	1682327285000000	1745399285000000	1840007285000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
49	\\x75ccbf3a4dae81b95888d4530535a68abadf388cf13328b905e63a845f96324852fbde65d2ffc30a13d2202fa578cf2b49790c61b2d2321cd7e191cb5738f394	1	0	\\x000000010000000000800003d2b6a6de012cff470c48168fce5a8b3e5c49f9bf7428192832fc841115f32bc8944e7deecd1cfe823f7ebfeb4c3f90b7c5c28af9e990691974d633db046dd4073f5cca13c7ef9a73936a1fbe90db90c4b8d2e137dd708f5f29719aef0c95b58c18ae68bd5f31873187af0c03b041802e268feaf74c1314b3e52a3078475a27dd010001	\\x7481139e81da214e81a38b952e8988af04c5245070ba8e322781815dca07b1b7c57da728288c9a0348f43408283efea5050122efd3691f527b05887e76f73f06	1673863985000000	1674468785000000	1737540785000000	1832148785000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
50	\\x77c830ae3b11a90706905ea2688ac55e89ef1d7eca575e6e6fc98984670613e6bfacd0e87711ae47d45c0f0d33cb3f704255580321ff20d267a1011353c5cd94	1	0	\\x000000010000000000800003b481d0fd90f25457dec73d6fbf6e98aed28ea3a787b857c521c415264985efd558221b50a448015f650ad34a12f1ab96a676d39bbc0106317972824d4c849098e0ddd944022c651ec5ab788655d6d899b3415ba58d9fa43be88af6de59de9a923689f5f457e3f591fae9b11b7211b7ac9fcef2bc237c04fe24931b1ef6ca662d010001	\\xccc213e3605003201bafa5c71985634bfa780e7e1e9d6f37a9d2a99521747676e8ccace0f00f40e216909a67d81a77ff0eec8b9f6ffe573df95025e393d4a608	1667818985000000	1668423785000000	1731495785000000	1826103785000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
51	\\x7948d0e7502339ec4e9d262af6413e87fb5d12dda6fe51ffadf7bb39b5e59711595a7b1a2e6944ed48974bd24129eb01d4577ec581c7a8f7919f5501e1c3a90f	1	0	\\x000000010000000000800003a1d4be6df4cfa13e639f4bc3cb2dc4d3aef55bdc95a16a90fbd0eb33db5ff256dba4580161aeedf8a1f6555b402d8bd386d93747b37365f85e01ad852d2a93c75068cce64622ca5f47d7a2f5ac1edcd59b4cb97026809fb254a45de0e0f09fddde9a96cb9e920a41d5852d51b9d91333214f7511a9ef4783e5624853e8155ac7010001	\\x57eda507961dcda904b3b0b4b42aa0f0daaebb892464c12413391196eb40fab9982957eabca553503792de86526b3f9b37ce53147a628fd19934e9b71c1f2007	1676281985000000	1676886785000000	1739958785000000	1834566785000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
52	\\x7a0cdc7a94fb6338dfd73d60fe0207b7e60d4f543bbe0f205b786d6ddabba4b69958de2888c929c86da6c2da10d79529975d1f0f092e9fc001bed9c953226ddd	1	0	\\x000000010000000000800003bf9c1b4a431a77a573f715c5518ce83ef379a2e026f0ae207239f6de1b901177e413d92b29b17772e5ebe081bbb6a60f9eb7a9425eafcddaa829022f7f151575daab691fc8f4cf6f838a6db9ae616686162543759f48544d6bfb7294dedd6f5f0b66398b8bbeb9296950abaa79de48bfcbd350f1619b71d68a31a5ea8109810b010001	\\xa7a199864a55ef9fa1e18b17c71c1497fd0265099808ea3365b580720ebc6ca4845320aa1f70f008152572e936251814b93cf530b6d99fb0feef537dccefff05	1655124485000000	1655729285000000	1718801285000000	1813409285000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
53	\\x7bf83ff17c8d08b1ba537cc3d47071ddf086e31c42ebc5d546ef6dc3539e5c76fc6d52acd9878e0c89a9efbefaa3b68f3e166937b13d53bef59b36209b217819	1	0	\\x000000010000000000800003ad80b2ad08a17661e4ed7fdca532ccae68af5473d89cb507fd25eaea0072ec29f96b7074a9d131b2242fe8a07c7b0078cb59ba2b829956ca66a82a94a04846752f36b7af2f793e3eebe8ac86476e1f8e42c27f8f17006104651c8e9754d14658418ddfe238ff6c371d314fc07c2d8caa350a017a7d64ef8e7ac29fd5aa0bcf65010001	\\x54d6affeebd3ef8f11dfdf4f65971b88a8944f68622cdeecd129abe7e67df2640ab4c7b667ba54293a215903ab3650dbc9e154af829efc9c83d5a4bf349dad06	1669027985000000	1669632785000000	1732704785000000	1827312785000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
54	\\x7c10ebab8d3643c6890b381f455918c2b3dc6900e680c8be6988fb4d986bfa4acce7f1a808e60fcccd6b00a825baee3bcf6ddc710e5a9d9ab8ee56bdcaa69df0	1	0	\\x000000010000000000800003e231d86f5d991a5af8dd5fa9f82abaf001d10949b8bd39cd7a653a4d19833d4e194f4cad20dffa6d32a55d822b725b8390f176b88f90bfb245198fedd8a1acf4fcd85d5ef5ae19248d892116cac80ffaf41ef6b8b5364245f827974ca03075a88ea3b6935323a3ec9f4cd8c89c7e0155a40efc5d142129d0322f229b772a9ecd010001	\\x7a0ad7492545812ad57f8f6ed7828f125f94c6c201de88701d1055f73e6b7847f6be57f1f501ffeecda7cbb125a7b22ac42e3665c077b2a8f18dec087796fe04	1659960485000000	1660565285000000	1723637285000000	1818245285000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
55	\\x7fa02bc49006e98dcd707db6851a6bb03f106965947116bee2d0507b74a1afafe05330b6534b6aaf743531e28b82b82a906ebfd79e0ee2243c4a88c09fd1b6e9	1	0	\\x000000010000000000800003cfc78310311620208e2a55a978faaa6ede0a5570535cb43ce80413842b4cdb0715d965889a8a1ff794280043c66e768b68071510ac1607c2e30876742b28d283632c87a3d75831eafd92165198821000da21e11797f1b8d52d01c193409a343c867f5fc48a3b93c5732f54911c026cfbd0191ae637efcbdefbe0f40e24bbb5ed010001	\\x35488b988c3c15a2fd064325905054846a244290834d6cdc7d070d3ceb0a72c279e814e7c6889b1f73a91c5c58378df11bde006b4287b064e74719e23590ea09	1684140485000000	1684745285000000	1747817285000000	1842425285000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
56	\\x89d834b39daa6b37df64768fc2fef7b7e911237081d1650b3f8534183e7bb26ca15fedbcfcad5a6732a694e44290cba07cd13d35b7f59dee2a8d143eddb9f752	1	0	\\x000000010000000000800003b9049739b7efe8a805054b9ea495ba28089bf0446e54874d4b0ff9af390b6901c9e2091358f49005e2d7c711947255281aacf0bfeca70d1bc9921214bed54f2b8a0717ea066de6cf64ff2efdebd98f637f45db1c61cef3e933a0d943ee2ceb286d3c0c3a2dd210e655f34ee60e0644602b1f9dc6e8b81459623e8eda8a20c45f010001	\\x36060454f7f179573624eced51fc4166ff5b598e938533f5b75f78e613d71e5dcbeec735086c94cf92e89126c52904ff1ad681a287a59044ee760bce067a610f	1664796485000000	1665401285000000	1728473285000000	1823081285000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
57	\\x8c9868145c004a26a00abc7436e344d3b534eb11bab3ee1095d85d1f234b3d5a24bb6c5daa1f79227188a559da2683bcbde5e67fa814071226899b260be49838	1	0	\\x000000010000000000800003d549fdb1c5824c8a28a83fac395943abc3264f9ba10b1fe4e3cf18678b73b2039ff437cb2057aa0f63fa845cb8700f45bf7ab231b846985ee52dd2d92493e4b7ae9df12f678264cd7287ef0010b394b62a654a812988f7d2048fcc97a54ed76a694c4d8c269717edf27afda34021a19b415efed64596dec7f1a4a941d589fdd9010001	\\xa547084b662d316c6da6e91c20eb4bd90390b0cfdf67988dda3a97becad174a635cdfaf042c5022b25a10c4388de1001081e31b4a99c5cd51941d2e6ac40280c	1685349485000000	1685954285000000	1749026285000000	1843634285000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
58	\\x8e98ff8a25d7a24dd249c3e2c519755021cf94e055862f758eea3d204a6c139d87b40579e4cd5b66c1b384202c804ca1440d5e0fcab37e17cf2a2f2bd0150859	1	0	\\x000000010000000000800003c39a4b9ec2172d7c90c454b6ae8b80af87a7e633866b754a09ad66c1523ce21629b629020f4809cb6f61a7b63b4a1f7525eeab3e5b4db26fef7b3ab245c64d46fcccbd23038c2fbf373b37d6567c0360e34dd5bdb17d26f5eab00147a466da137290a0e49252b30f36b4d85c8692bc1d533f8f2e7522c4bfc11962a24760f477010001	\\xfa33cfa0ca00aab41f3861ddeb406ebc33f7de5de816d152304a9b6a25a6c243be3560532b9ca25faef6e7bac23d8d7995e1dbcd9bff87fb85f082d672bbe900	1670236985000000	1670841785000000	1733913785000000	1828521785000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
59	\\x91746c78aee324db0f6c193f1d53e00d2467c5fd0a7e9c0f22f1830175f1974a5ce75b7f4af6d53c5bbba8e58bc18bdf31898255856fa86d95cbbd8b471888e1	1	0	\\x000000010000000000800003be01d9c8353c6b1c5a34cad117326be3716d50a27a954fe0b33a37fd5bcba242b1a0062917cf474d4b8fb6ba21f80a4355ac1e6263b955ebf00dbf63d18e0cd010a7733b7fa6b7c57379a4d2a94267843bc12f39408ad4efad06f921d829ce561fdb00ef7aad196b23dfe6e01ade3fcbe95ea055791a13b4ead43cc35e50fc87010001	\\x8c8c2660c9aa3eb30a22d30179268aafed7c460856f288073c6f63da48c60e89afab905584b24e9ae2da0e9c51b3c4d814ea1f4f9ee60f2c9327864d65b8cc05	1677490985000000	1678095785000000	1741167785000000	1835775785000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
60	\\x92640f146877b548631ccbda9c1b912a0649d5a7ebeacaaf99ebd05521f11ff4a23ae24ac9f1950b32cbd49033b94a29834f820aeeaa2a90114eebcc6a30a369	1	0	\\x000000010000000000800003c5bb3a8c68d8d7538e126be21066f3fc79f4f0018be60492e20cb7e30271656931d225c4ae74b966f69eee86bf95e4301d1b8cd092a7d0f4f6c6868d5070654693cc7a090ab217aa0df4f7b811cc5f717a08b46aba09e647e1d1b0adaf558cd95e3061d986755b47881e7111db1c9ba2ebc8c604e77d476fbbb7123607a06f8b010001	\\xadeba80f798f6c0c220b2c3feca96a40f2379f147e8d50e2b3c7fe0ce25d07c5537380a0c95c009205cec31d3d68fcfdcc2a46ad27e34190110b953271eb0503	1683535985000000	1684140785000000	1747212785000000	1841820785000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
61	\\x926c365614d648bfe66e1b34040516d6accc6a3f654e5ce893afc6b723c9d41890d5358b5dc707a0b4f15d4e1c30e095f4be266c3a112b45c23b26b60eafc735	1	0	\\x000000010000000000800003bb9cac7ca4538bfed0cfd9ff3da5702be0ce6478c1888ed635cf3203e13b766ab0a30e68055d19b3f23fb40d25b477a2a79f0f1f328b02eac2c7f95e08bfa48707b18317ae75954964244717ffe73955fc0cbf2cfbc5bcd0729cd3412c1e2cd3419f0260691bd4281aa0a78aa924b08f204609c8a99e642bbcc8d0d4f3111881010001	\\x4d4b61b7c03aa305d2a4b8a010bb6bbfc991720c5521130d9b4ef99e4dbdfb21da9f160813cd3264a099ffc36963c1e571e5790211f6cfb44abf93e0c4a46d06	1656333485000000	1656938285000000	1720010285000000	1814618285000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
62	\\x93808bd77e1c4b85d1bd2fe77044224b3d347ffe581a5bd807045d91192d8cca6b480487e5263c3c836ff486b18671ac8efb857d2f13fa30c80cb2dccca64b21	1	0	\\x000000010000000000800003b761af965f15cad48b377d244f48b1de17199e80d76a26c2d84630fb50f6f5380ea02cbbb4c90d1079302eeb077437d0b000fc723cdf196dfdecbd938ef93a3bdb62de039b153bc7ebe33f13955cc6c7ca0cd63d76cde1dc4730ce602c256b926f71ef877fd3dff499a61c64ea873ef86d79cf3c706ab0008e7521ded19f83a1010001	\\xc5337fb4676ceba4304339d3b5973c4ce51e5c90a2fc2a4f2c078fafca19faee7a93cd887bf9cad17381371ea9935fdf0f1f77856f5a9070933423f674a42d08	1680513485000000	1681118285000000	1744190285000000	1838798285000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
63	\\x95ec9ec86abe4090cc1aba05a321c42c5498de498a200e1c0c1958e50473cf93935bcbe3195d700783182b8dbd23bb203244d220f0dd3b17daa59d68af8c24d3	1	0	\\x000000010000000000800003bba994c0d18fe69d86e8351af5453c5ec7f637f122f2255a170b75e326d004a467cf88023244c40a34ed82891bd52ff2190a756d20f70d1c976a7d4ddca6724b53b4c250941a31102d959f7e31ec5d4a1017e095ec8d58065d4ee58f83b1c9cd3a2ce76fe9e819c96f2373b32c8cf5750cddeb202e5863d6bf527e725c6c02a1010001	\\xee60764fb71947a1322d9cc0532d42795039f4da8a6576cbdafce00534e546710223245362c1a7b8af6f1a6435814a37cb1d578d548ddeb8f46b57ffb007270e	1668423485000000	1669028285000000	1732100285000000	1826708285000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
64	\\x9650f19cdd52b28a9a8ba895a83c9e684548502d88cb61997c9534f1237fa8102c108ffb127a2ab8afa74ae9cc5861451528aec7d451a7faed21a27dadc6b26d	1	0	\\x000000010000000000800003ce518c161921417efad2bc084553f32b50219c01c1c1bbe66f50593aa2c7858e56452288265ea37447b1cecde373151667d441ca466338028300fe48dfb8229a6302cefb1bd0be7415cdde09eaab739b8541313803f4e00b33154d8447fbb71dfcb64a62a6701c559908a16f61616df10be1690377071c106b02b56d7c3a6a41010001	\\x026e733a40dfd1bc2a6a6a51c6727305681b7fe5c443f837afaf57f259314c101aa520ff0a1aa32d9777acd036532cb5772c0dfb70efd3c40a9f8d2e45329b0b	1679304485000000	1679909285000000	1742981285000000	1837589285000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
65	\\x98283131f4ea052522b521d30318a2c5cf8f7c632fa344521c6a7350a4c88196b1489c8b63348fd56f78e10e9d1b523f38caef451d177a849905fe62c6787a52	1	0	\\x0000000100000000008000039abedc2afdfe5ee2a7d937dabca529e7fda433053cc0dd8ee264e35aa8af711946a33e2ed9db7986a02a68c53f79ff0466b43bc63e90a4328bb2cc626fe40926661504bef55b76fae3e663aab683cebfc2ff069109db5c7d82ed704b1b98e5f4ffb4f764388b3c398b2bd3ceab59b3ac48e7765930c283ad828114b97aae99fb010001	\\x65fad9215dfadcb1627cd174c2c134f70527462f76a8bde23688aa3b98afd998bca3d520f90661d24079be27e5025707f56ae0a51e119e2b0d1412e23ad6970e	1670236985000000	1670841785000000	1733913785000000	1828521785000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
66	\\x98b879f9bbe9e8afe03a753551c0b15ab86832ab2b63b0f0f6e4fe4aefe69a7152115e4f98b564d2cc7d46b3d858894b0a24456feaf1c23759f4cbbfdf197381	1	0	\\x000000010000000000800003950d17d401f3073f8f8b9016e1d80eebed9cc67c7693d3267dfcc112da34e8942946afcc5fb45c8e0446683bd716e0e8959cdebe9ac35d08c76ac871056ff1011d415dd07a49b0605df6703187847ea3cc54aedecc807e670c9646590a19cf7506736c65896b98cb467b93f0af116a9402eb94b8d042a9447b2e097d665b7117010001	\\x42c53089ebe0e45ee87a0e761d4306338dce572cec690c40df442c429c0eb031e09bd108c6457fd60afdaad1113e2c6eef18b837d89bd413ca915430904f4e03	1678699985000000	1679304785000000	1742376785000000	1836984785000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
67	\\x9ab8e6e7d9f3641a101446c3ff6773a88765eb4c3498c9aa29d23f1eccc7e6da62247bcd22577ea46f34e5dd0c7d5c1fbf50fcd3c21a97f6cbf64cb60f94775b	1	0	\\x000000010000000000800003d4b0b8bb836744d1b23d350bfb701cc42e70415fd5c11d4f579245a77d772ebfd76c1a539bbfd0864d7baa1719efab76ac45a9771c91b3bb4a5f3ade1861d1f175e45cd7b7e170962860d7a4f4fe43e97c9983019f5c2b646a457c20c8bc8cd84dcbf2310708e64b0ff68aeb27369afafb24b883a3bdc066bc96e081c935dd45010001	\\xd1716620cc8193ec6f8ed2b15b341ae870142b1f83773785b87db6ad31762fee74054970392d4c7dbe052dbb9bdb62d705c872b2875d8890208d6ded73323100	1665400985000000	1666005785000000	1729077785000000	1823685785000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
68	\\x9e381ce099119db2d26c68ae95b50ebb4413beeb09502e7e690fe885a228037b30f5e697e8b52b2c677e3824ce25fd8a7942a0918d8ad0a41c953742fb8f7538	1	0	\\x000000010000000000800003d858424b6ad9314db147681642cf1e0dc7c6e453bce0a7b3bcb4184aafbd51cdf0bbf35cc2b9ddadb9fe64b954ea431e75b3c75803840664e4fc075ed253f80ef0dc17279bfcadcce00e86f96971d3890caa536dd8592dc5a736f0824e9f8862d0c400f4c24d1c5d2b0877d9c36f3e941242d4844fc93356e4c86a7a6d940113010001	\\x03f9e21f4596c39c1db656c493f8cb0d7e6692586d18fdddf7c5ecebfc4939024010783acd513448b5590652bbf3ae4b9a0e2e54a3198ba9e3c530846c9d1802	1658146985000000	1658751785000000	1721823785000000	1816431785000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
69	\\xa0a096f3f9e97d0611a95c89ffbc607f1486b897da0126813127705f13bbafa3fe256698f04041e3b0d207d6cb8a0796eb349a37a360e20ff53722b15e12f3e3	1	0	\\x000000010000000000800003b1b27198a29da8a42950053475dda34817275cce04671a328f52cde1e51a0ed5a01ba52939dcc60ee53529985a3fca14b914cfa30a908ee35142b16898090f1205dc7b4d0dc5f0d8699cf1b5af71af744968235d9ce1bd01cd713330432ca9634ea7b08d500f903f9868a6ce881ae558a93f9cc37ccde08d72a5fd97d2bcf415010001	\\xec1d305ca4aa5731a1271fa0df223db8e4aa182ca78fb501512fff11247f7048c5368dbb87413b56c2eba8ff022a98ebdff5ab25ad694c2181a295aadba7ac0b	1672050485000000	1672655285000000	1735727285000000	1830335285000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
70	\\xae1420f15c69f57283268e44d5edcd0cf283050b78fbe02f7db642e56da1d1853c438ef2512daaf31c669399030f949ab9194facb1feb74236e3a25c75714b0e	1	0	\\x000000010000000000800003d6bc259749f3f7a416392e179beb5d657e386829f6767da580131b817b48af0e7554fd5418f29e09a0c6ab4badfddfee65900cdd13dd0d309d557594f2ba35f14812660c6329a1c00d734193338db4932ea4fcbce4e8cec18e74a1c9f63b2526dd673e0b6eef33bed12d8f34d5f324963381e78bc8728bc92a6ebf6614b8d459010001	\\xd3bcde54a1e4a73518191417dea4fe0cfc75270ff832a52b0b79321767ae5e4032cc188b3b3697cd5431fb6deb034bb10dddc78f7d23e0866180aeef6ff97c07	1663587485000000	1664192285000000	1727264285000000	1821872285000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
71	\\xaf10d5b3fba022547a1b67198cfc702b2bbd08974cf88a4db042617e2c256b76cca4f9a93103612bc589cdb558eb98bb4a62889498f2c7a06eb2b8279854e288	1	0	\\x000000010000000000800003e1e89aaf89efbbc692ada9319cc3b032423dc3ac2dfb27524bb1ae0999040a6c316653ad8fde7a678368e858a991a7a4f758bca3395d4b1a08f8c9cefe5ac2f510973f13f770fa4d8e7c20abb6269d3e7188c90d4e1bdf415abc5ce68230a4ee83e0dcdbd5f22dce3a7909c3ec83052d37758f03681e72006c1e41f1124cfb61010001	\\xdfd2e24e8a5c5dc92564da83f3c4667b92b112217f8bdc777e29735abf9913ef0c3cbcca22adac62e892a49bca62c535d5ff6d073ff84d589d7decb232e0bb02	1665400985000000	1666005785000000	1729077785000000	1823685785000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
72	\\xb898efc2da36968af76125d1f6e8a26dfc9af5dad9dad4182c3ef777edd741084f5b5dd25e36cd91a8eb42690f51e8fcfbb2f63706f027be5e09532da0368c9f	1	0	\\x000000010000000000800003c27be6c3cfd1c26626de30691cb7fb6f092b7fba54569775abb15c6369ef964f7f71f1211f07ee5cb5b2c41cdef4b7969e12d623eec7cec8408e665532a3f13bbdc664bb5841db1d6e7707fc4fa654eb8f241391e312fd457f87c80b03617c59f0693eb87fbcd6533a3efa8af014da4f6987527e2066bc7b6e99d38d67cd6f3f010001	\\x353a2c2d7fd3078e692339ac07e5280f160947e3dacb1b9e3a2da1ebe0444dd9c4b218ae6fb46bb813de90e5e6aa944b804ca1de96bc37b3652127a675ffcd07	1656333485000000	1656938285000000	1720010285000000	1814618285000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
73	\\xbd68e412334dd0edf44ea71c68cb86a0b417a2073e8cd905cac81fe94d1bba60524aa95684a40db40500ab4649dbbf6204d940b9e6b47350d29b6979d6878934	1	0	\\x000000010000000000800003bf9fef3a8f32dd18c07bdb98d003e9f1e534b154e626b688f72f853a6dcda16cc8cc25e2e4fec4915a693e2e32568565f793e454416a5708d76b78dbf5014b1970ddc85ffd9cfd90e1557c1facfe9f091cd3d446d27798d5e12d5be1a05d664810d01ccddf888a244f9da75bbc9a558257a11550645b4050e2c1121a2a944bdd010001	\\x43916c06c59d32aee33d7e08ca18073d9692416609b31e6a0bd116089ab7bf330563a6c28d9891787765bc41245d266893871e02b979f71a83999a7ad21bd00a	1656937985000000	1657542785000000	1720614785000000	1815222785000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
74	\\xc03822e9a267fd76a1c2dc09f6acfdeb63babc2ab19dc7614d5affeb4a87a0fea08a5fbd512929d89ebd01b8a25f4587215105b23373cab6718ec0e888335d53	1	0	\\x000000010000000000800003a4feada372e5fbc839717bb9a423d0e23125a382aceecbbd05e2b978c49c8eee5cf6035ab095b1c673cc70ec9c0bdb6ed1489005be011951a52fd85872f5d163e2d9a0605f8e018dcf1424b4661d37b36ae088ae52079431a8d66b2171de39b0f17464766968dd003686e0fbba5d1df3ae524be15014a70e2eaa4c2bb4b49d79010001	\\xdc82e60b3df228321dfbbd362cff286c6906525619b5a1b5850b74706f9999be766cee0f672b6f963bcbe52e4f9ddd195a25c9b898ed55a35af76781495c5f09	1662378485000000	1662983285000000	1726055285000000	1820663285000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
75	\\xc47c8327ba14c03d68dd778041628c14a40b33fbbfd2cc12afdc9af2c3aa793b8d7db3ba2a7dd91b262bbe97a2db7fb16f47117003d1a66b4aa3765096a5241b	1	0	\\x000000010000000000800003b9da1a261d61d6d7f1c42d8b10a1e2d9ea6ffed66aeefa7040ccf2403df307b33625c6a7a8f7775563821f205fec4dfe9de20cec0556df9025e19d4008119fd4d8c62476dffac30c9e84f8c3bf39117cf4a3be0edcfc5911eb346d8063c109f7eafe69ed674acf2eb3f9432f6a74da83bbee852b0102cc486fa775994bdc213b010001	\\xc78e408e68ed12baa527e7de051a41c961c9c56e98b3b8a85d1fbfce3604cf944277524269f4b40cbab9b48fdabc4b509a6ba6831965c866f34109bbb7b7840f	1666609985000000	1667214785000000	1730286785000000	1824894785000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
76	\\xc684bf5b71b039043bc291b654b7128e75acfbae76f3c1fea72fdbc2bb89d3b5bdeff9f1bedd31d76625ba972e0fd6f6374c1ae3485b82e216673bf1d70bbff5	1	0	\\x000000010000000000800003b965f90f2246f3406941aa3e95731e9d7e686db92622281dc4b63f1ebe48ca14000ce3eaa43649f2451866a272c3cbb0754d90619ca0cd975b3445f6bbb4244a926826464c25c443d85f13b1904336d60ec4d4a6dc59f546e2c20ba03ac29e01b123cda387ec6684d51ce61af59e2c1206e1f58454b9dabc6a9765352357550f010001	\\x2899b24154dd027fb47846cf9d025653ed0d5a94305df488b21128224e67e0074d44ae63b083c21c229e01af793becb1339aa97c39ca6ee9817d0b6274205807	1658146985000000	1658751785000000	1721823785000000	1816431785000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
77	\\xc700f57538a785fcc2c81fb5d4179e4756cd8330dcdee0b598901ef75437ffd16106ce3104f42563392afc00e7ebe350ebc29f5dee2f165fb3f8f91e0f76605d	1	0	\\x000000010000000000800003e59ed5e9dc46cd19b1f1ca7789ba87205a0aef617a5a5b58b382de4c60562d8e890a86a1712282e9e6bd1184a22f79e2aaa46443faea1907dadccd48b6f9e733330104bd89ee5c42a1140521b3a420db9db5723936975375a43ee87c70c3e6262d5cc62ac38d818951a43a00da5e0c05706a6ea408f5a2427ac11b261ca776b1010001	\\xf04f789465af01c2522b91c1affbd1961cdbad5fa27b9a7a652ecf6429402ffc4fb5786c386793e79b6f5b581f7a80467728ca54145fad623508fc9ef4db6a0a	1672654985000000	1673259785000000	1736331785000000	1830939785000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
78	\\xc75cbbe0bd1a0d1ad38a852ec5f2f20abfc312227a474ec95d0c7b118482318afc8180b4fa937805a0fc39e99d9fb8a6374dfdc7c428631e57021f7cebd60072	1	0	\\x000000010000000000800003971395232b15e9f7e4303aa53b6d75186a21994a309dbc660c7ab2958fca5b6c1ea11e056fbd78ae4ac8322a798cbb19156779ef94de9b773f15f45198be9f8ec5a2ade52c351671d8ee0374428c4bc173763b23ce25d58d253f2e40f876344508b2890a3420102d92a8b574db55f71b770d5aab16de9253baf1e0e2ffe8b895010001	\\x68ef5e0b8c70650b7f50d375672d259253a1b350c907a9d2b4af9e2561d6d80bcf31911a0412f8f2b76017265d14eac46bb4e1c9e93db61c5f033872b8e0cd0a	1675072985000000	1675677785000000	1738749785000000	1833357785000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
79	\\xc9cc175f00cacc19cc631ea61f42e9b0eb2e20a7387bf69b84a3c7c4d433591814a679ce068f1676fd0437c9fb360bd0c39286ad83936af5317c4a5f23e5beb7	1	0	\\x0000000100000000008000039e2b4dc3da31d825947a5a5573b849ea7c3d006448a4c60f1d17d09b6f701a6ad5603855ed5761ba712ab1299011ef027516d25850b04f165dc1fc76f8011608a50ff655993f340375935a28362e6e235d4ac64498b15c6935887320d8410731c5ea06b7dda0eec75958fd549f786f489e8357aa3279cdf4d09525f0e70ceb63010001	\\xf3ed6ea483e6ea6dfb966c84a9a36eff5db3bd50a6692dc8eb67068dd25f748ca9084dfb31cad064b770acb5e8a31121295868288ef1b4734b521094189b8006	1660564985000000	1661169785000000	1724241785000000	1818849785000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
80	\\xcae4aab6d1ae83aac339497637f6200ea2e2b8a29b32a0e5bbbf40c7f564330cc4b3059b097334bf1ae9020b312a5fe9583a767cca685492a6f65ec8879dec9c	1	0	\\x000000010000000000800003acf446323e4d733aab6f174c38862aec41730bbd21971f63fffe9e74f3d859c837d9f575a8847a424de6dc97f7164e5691e7f661ecba83cbad654beaeb8fe4aa1718fcb811eb959dd6812465c644cd1a31e94dd51f9d2e79ecfd8ca60cb24de1b4cecb74444c22216e12a8692219a694ec34f7be443ea4bad4fbe1e0d2b5eb3f010001	\\x65cb50116890a55e63c52675433dc92c5efdaa0a47ea412006aa35f2bae1362d786a6489129d82bc576c941d75f0138a76f730f8fa92ce68b447fc5879dd3c06	1670841485000000	1671446285000000	1734518285000000	1829126285000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
81	\\xcce4b6280dc65df964a63774498222977f15be859c80a0343eb25cd29b7ac881f4767985db602bea54b49399b256b0a36ccb982abedba978b2354f77c79a8a07	1	0	\\x000000010000000000800003be3d1549aba86b493e06ab0eaf7ed8cb3cfa4ccbbb280872c8f0a43b5a184bfa72c5bff1d2d354022179395790ace1b18ef68f278ddec4523eca546f0b5349b0081dcbe0e075ea4ad97b447893f77f18abdee8f68f5d5de78167f1e8caee9b90e4330710730e73db786cdebbe03785f7a739725d4d70f04befdb469f2f71419f010001	\\x5b89fa63f39d27db6b14c33374e4662b852b5db4d60e56594870bde88b8d833c65f973e225737d4f95d4bee5a560507aa1ee15bb1c730b40fbde30fa99949907	1662982985000000	1663587785000000	1726659785000000	1821267785000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
82	\\xcd9cce7344be8b4c2a716209fc425f2699f51fbed226d09eae8866cbaeba9138dc76160904ff53fb77cd96a593d8b6029446c011153c661723fe992f6e05392f	1	0	\\x000000010000000000800003b87f20f0e942524ebb7b7e123ff49e17c8c5a35656c15395a567825d0445d6556cd14d7ae0629edacf844955c8383b5ee98b11d703e38075534f0444b5bcbd135c94278f8097da0b6db4cddfeeb2d800c7a3abf0bc29aae17d6dd68c4c167e3d10c415356de9ad69375e1ca920a863b958b6c122fb3aa4d8a2a5e92ef385e4c1010001	\\xb650f9cd482b17fbab611e3a2582c17d7a9a7e78a2985f1aa1632a01a37cebef02726ebd9056d317c17438bbc09d49a9ba470d5945890f8650fce5872a03160e	1673863985000000	1674468785000000	1737540785000000	1832148785000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
83	\\xd7c0e283900687fe90ebb74b8c809f6c2020ec27677065341f39060997d43f32d3405e99c30c361f57fd9b7c3413561159951e99dcf73a12440c95668638fd05	1	0	\\x000000010000000000800003c011658bd1c366657e3e33eaf160df09a9bd0d20f0db8a241cb341f15fa57d624928387fc70712b8db9ee7c4d6ed1aa4b592348c225b68b4b421bfd67fdc55e935e09b14e216e2bd44c8b57e169ef2976f7abcc918c125c9d2b50cc79a469a876d95059ac33d9d17f35ca7879d1e79aa692220d3bf23cc7a3b1d9893a5ed849f010001	\\x4ae84588dfd3aeacb5c67adccb6f75dd8349b4791c7f21971ffee36bf46d7cc896cb07c95f3fc04d5d959519fafb9606886431e177acb73bcb66640699dc8008	1669027985000000	1669632785000000	1732704785000000	1827312785000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
84	\\xd7c0f66ab0d42279a75947b32aaa9e8d3d686a0438485e1fc5872d7d783dee85471640ea8729a8f52e8b746d9654f5593b6e2d77fd541b46826711addd9a9697	1	0	\\x000000010000000000800003ba12d429da864735af494866ee2cf3bdc17e7bbae53fa61542601a6a8df06f4433075f73301c1368c9cd3c29cd3f3bb86ab245e9a491d09ee2f2a29da7546a553bcae887a39441be667bfcd861ad0484d72f046f398e57398eea56f160647ab3bda4d72ffb404ee1bbb9385b33aa48c14551cfa05d8002d018b3020d7d319789010001	\\xa4a09dfde74fb58e8f081e7f8e0cf9acf268e1e1f293960ea19a0fca7af8c4d45acc428b45e0a01977a7ba7c56483157af79cba2948309a97c5c18b458407c0f	1657542485000000	1658147285000000	1721219285000000	1815827285000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
85	\\xdad8a90ff58173cabdb453f4a460c633b07b2c4bba65572174da9031f6e91a52ac9d3af476ae63a7f687cf2700bb5536dae2d4d8d2a12c5d0f6fb06a58d88bd4	1	0	\\x000000010000000000800003ce2f1544a6340e93dca42428af9f326fe41a2aeb93920db176ad8b73f252101b342f4060835c83c0ef2552072d795243c3e7365c998e2bb5f72844f73772cb68939f51158747959bdb2aabf0deb9c434c9b5403ba2e3b56c42e2fb450f1a8e69f80053e8170bd935ea87946ffcf73970dc23c2f186825cf72dd9fff515298de3010001	\\x9e1d79f9afeb19896a8d60fdc91e67e0ef2a18c5bc8ca2504de46da2710e328a30984ac2874590344a32e7170d4ca03889c46273f555c815327252a0c2754801	1659355985000000	1659960785000000	1723032785000000	1817640785000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
86	\\xdacc6fc3e26e0f38f5eae0f89fedd57198a9c45d6aaa1be682e0984557aede64e58cdae51388b62febe5fd904787cce8945edbf80f65d02b9bb43c605366b87d	1	0	\\x000000010000000000800003c8b429f0b382cbdef0130ce5ed9e6b8d6668301cb4b880f43a4fec8a7f7d8cdb20461adbc7ec63ffb2aa038ef894e28edbc491ed8d6cf781b4fb9e669c290c3e32014aaa48947c90cc7c8933480c210a8dbbd67a3c7859d6b2d9f7e43f93ddfa91bb38ac0aad57ff85deda7a4d2ae3a04998b55be57e018294dff7951adeed25010001	\\x5dfcaae20992313c91c9a358c61149b0afe2560dc50d883f14dbb5ae58a86e97bd63fa4b164548be38132782196ea5e8c0bfff2e9dfde4264e84e4a608e7010a	1655124485000000	1655729285000000	1718801285000000	1813409285000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
87	\\xdc1834e832a3039b953271bb368179396c47d477ec37e2384a58d50af5bb55d3ce45a4e672dc210bddf2b301ea8990a63b5ca9085f62fd0a990741150e871b60	1	0	\\x000000010000000000800003c02993c23c2c0194e7004c9474dcd43be8f86417959df3e022e32b5e57d1c9a6d17dd476461f33f8f8a045d25e035829db6fe06b46f11284fb754166a58b44e0bf9f3b534602643903db27ac3523c0cc39e08ade1ee42cc781a21673526cf6c2d69f4273f03788e776a01d599ebd849701e37d4b15c846ce19f84a15b3cc0901010001	\\x30351183159ea23a375b1e2779e7b838084b917ef7c228c942ece14ab20db34e3e0ef0fe6a2caaa901ad52edfedae6379d1b008b286400f6d36492c3ad057506	1685349485000000	1685954285000000	1749026285000000	1843634285000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
88	\\xe054760b696d25a12d28a3cc44c7fb31bf2c7de9c297575304527321ef233dc69e4d8f5c78662dac75fc8e9798f366b4682fb786f05369e00ac230d666a3e138	1	0	\\x000000010000000000800003c42053557e84b82868dff748cf09ee79ca26391f2b698a708487c9141467a4028f5581f6a5b9fba4e67f2d39e5b7cd37e9cba7a6bc800f1597cabe5ac772443c4cf38caa5f7a5541dee23f7d45cfd2f879bd61988122c81cac2042e54730568f1a7e2ca6cd39e22f2ebbce59145a332e83136939b84eef105a424dfe07b9cb1f010001	\\x3a01cd6b48f659f466f29890aace1eb1cd482745f14a4fe708f544d8bace5f5e8ca7df96c67a605fd169aefa48c4b4d0706504342484b79c4538415e58d0800f	1677490985000000	1678095785000000	1741167785000000	1835775785000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
89	\\xe26465bc279bafb93bc80274036e0e2333c0ad3fa218be1cece2ce70727879b1875a4ab07b81a49e134ba8226eb99f5a4e6a7f486f1222d447df6e954c9851d4	1	0	\\x000000010000000000800003fc562c0a97e2d3cfb9dc11c9ad72a705e4a68368f46fe829340b69068078561febe8f3fa6bd2e40bdb8144f2373f0906dcc278c21fe72dbd51b76f21636b90f6f74b15624e7c30cca54a75e77901d2267990fb44f0991cf6ac1c4b3e0e3bfd0db57d30379059ac344a90ed6deedb0127d868fa81123188fd1b3129d811f82219010001	\\xbde1374829fc43c5ee8d1a65a7ca2fc7355df018c7cdbf246423a25ffce2a968526b2509a25bd7a5b8d6e5cf323ed2ef8fa2c979beef2ce8bea8b90de8a5380d	1658751485000000	1659356285000000	1722428285000000	1817036285000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
90	\\xe344b331c32551fe28b1ed27a0e9f499fe3474f42c4026c9083604dbfec67a0d25608c47172c45b4ca6900f66f096e003594177703db36fc2abff8a705721a61	1	0	\\x0000000100000000008000039deb288c68611e701faa15e8b9cf3de618c00850118d4f61628e297c448a7396c9d932951fcff00b772138e194285681332e054521e7ec041d26c227f9abfd8dd6ad6cdb46cdf9383e7935ce11dfb5b315d9716b0371f08acbb9159c1be9a30598e6f78c8e721d7a2371138d763092de3d72d286947b983fdc066cec287bde01010001	\\x412fa13eaa291b8d5118ae377a92cfd1fd83fa25e91339970f688a60555f8299df0f9819f5b2d5877af204014fbebcc1f381b479c8386a0089b2c8f5d31bd80d	1683535985000000	1684140785000000	1747212785000000	1841820785000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
91	\\xe4481ed9386a8aa0877deb9bc5c0a5a56b13c08bf4d25e7357c6cca4adb49e683094cf85e8b58ef728b5fffcb2a0517c86c763b296eb9f7463624f93c8554f36	1	0	\\x000000010000000000800003c1878c9f96b3a077ab90a0c25c511c68b8cdc92153aab4814d333647791e00cb315fd56075dd6473f213428e68c99fdfc23bd2860531e3fc416cbc2bc4567fcefead2f8aad2e6b0e9ac3985a276648a87908ba86194fb00f05e8ac42ad8c88692f80208b68c4a2c14af01467576074743afda6818fd37c5551500d0920359941010001	\\xb523d172370e2d7fac93a049186f68d41ea2672bd09de1425f90e3bb04abe55539152b1fbe655ab8da4fb7bbb1106e944db5b0af6a03ee8e1d9c1af96e1d020d	1679304485000000	1679909285000000	1742981285000000	1837589285000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
92	\\xe9b8c87be7f63f04846f2a3115c71d592aa5cee039f167c394ec4420c9946dd65169d11ffc7b0164a89af9e10a982ad7cdaed82d0e59b69dad697e4360f0e2d5	1	0	\\x000000010000000000800003b88d0872b06fb3591f05ee752dcc55c237780ec6ef04c07f1b1492d428d31071db91aa74ab5f48cfd71692a3d336af039b00831bc5b9f9eaa43df63fcbaa46107bbfb68836a3efe9fcb01a74f99029f55f083802dfca2fc95341f116928235cf4a84f8ec4b754e730491d65fa6204bbfd657847d0a0f78ccfecaf219fe98868b010001	\\x25b157a8895f835532f0632e9b4ed7d15c2aa12ab5dd622333e404cc4c446785a3381823e143439f6b4a1666985832f8a72bb17f1455e2a52ba9cad4fad3470d	1659960485000000	1660565285000000	1723637285000000	1818245285000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
93	\\xead437d5fd557598d9d024947230b6dc694774f98faac140a3a47a622eb8e4597c21814d6962e2193b430d5b2e1e2f4013bf3769d912e4dd1b98c00bb861ca56	1	0	\\x000000010000000000800003bf0cb36ff26436e889909325ea7356d33c08d08840411cc8c88a861d2a4b02316480acb68adb70aa05fe3631147fd5fe180d1d81281b69b0be3e6a0c6b0d6b47a07b4eb6c6d07486c9b696c5935def9f203fe0deddf704da626816917897345b7d8cdd57f61882c64f4796e8c28ba78828779f4009e20dec7783923137618471010001	\\x80e376ebe23a28b512c728aaeef03b52258c4cad1f6037067874d8b7bcd71d68c0de05bfdd44e6c38228ba6c98b217c58919208ba2f7cab7799b7447600fc308	1676886485000000	1677491285000000	1740563285000000	1835171285000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
94	\\xebe46c6e4115a11e3c3a5a64bf39bd2f2ef248be0c656288fac749cc53f4f30da99b47c25dca8d78ce71925714615cf2004179d35382a81df901824789aeaa7a	1	0	\\x000000010000000000800003bf61164a2bb0ef9fddf515e44463ea270aee46ad4d5ef3a8c3aaa1047f7ceb2bb0060cc168fa923a53efaa8de6e2e21259fca4350c4c8a190c4df0eaf75cba3dee3ab5f13d4a1eb9e841d78bf487553e9021ea490bd3d7eb986d91628edfe09ef37d432a09836ed602949fb530af16a10ceeb5de94d1840411786c91a5d508bb010001	\\xd3e93e443aa557507bf1d250da1ee74595c84c05625fe2b1bf68799e5f88113c8752725b24a1c82e9658ab26cbdc4f1816ae90abeb8c16dd01f1cfe4e4188f0e	1675677485000000	1676282285000000	1739354285000000	1833962285000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
95	\\xec78017ab9e15686dbbabf44f8a19d9530cdd1d37c9e282305a20a76bf67cd209c39aeb4806bfb1c1f7c843215c5cf39c93260d30c01315da84d4cc6e179258b	1	0	\\x000000010000000000800003d318e4e4817ba2f406580bf0fae2b4e2fe08721afdf50e6574191fff9e7abdfc85ccc96534cd619d69b414c0dc24d946190a5812cf767d509babc1a0a05da54b452e1760c9e55b8630d92d6fc900f3381256334ff3a4497c1eeee6826772dc08aac105ae582b9208b175f3ab73fed40c9c7c0d01d861d0c062ba20434e675449010001	\\x77414f2c33d385408e428ae139bf6a38f646101051998a74bfb84254991b15d76cbcd96c50da6d793a7b9eaa1afb1b003b4713ab80f39265172d3df9d856a904	1681117985000000	1681722785000000	1744794785000000	1839402785000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
96	\\xf048a7e6f775d22000ba2d1506b8fafaa0bebd46f6a6f8a3511838cdeb2cea9a443b170ad54b6419c60cd75774aee9dcce07405fd9b592d8b0f9c8da9b65314c	1	0	\\x000000010000000000800003e24ff008c45ca5ee0e8fe8b7a1cb44372f140d8360c29490aed53193611d7d224abd038a1cb62c94340346fe2f8ef7964adab412c432c00c76cdb1d339bddaab549184a79de712089548c24a5f529bdcfc5ba7905de860dd6ee953ec03662ca6d29034c0709c47d1e175366ae953fd1bf5d5a05f420d0f85f8db80123fbeffa5010001	\\xb566803a5c0f6a55a63d9239184a4e3a6fa1f627877fb1258afc413a36515deccd5a4b8ee36d9b5e3e2355ba52f7a3637738c8639d9e4c4b0222c25043548506	1664191985000000	1664796785000000	1727868785000000	1822476785000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
97	\\xf08ccd19094b25a372d8192cdaa02d221ae70bd75428a6c66cf552c9ad71acb56f101bc5d3eb9ba15282d091b66b585d94a8c8c7bde71cedf4eed78bd1b746a3	1	0	\\x000000010000000000800003b3860c114a65461f4f7bd224bbe0c2f942f0b0a90061f9c11d7df1b13537cd97a0e9885fbf01131d6615e667c91ec94672f7ae7c661e181f416975c4b1f825616142f13c4c80a89b00986dfcc9b1f8393f039157090f4d363eb8f60cc6cbfbeb26dc3ff797574ba8005f777ff3eaefbcebaa5bab07b2dbf90674165acc5f6191010001	\\x63127c0e0a3b6bf6e699a1465f41aff10498ea826b02d3c4931251f2c38d62d8fc1f2fd3c027989c3b20e28291ca9050d37a723e7309fe85f42df3168a56360c	1670236985000000	1670841785000000	1733913785000000	1828521785000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
98	\\xf510a3a0063b4aec6eb1d5c4bdb44ec7e0ad120dbfa912768b421acc6ce6f363624beb52ba46d1c5f7383b46dd20bfecd0d17ff82e8604cdfaec8ce9b2d1b421	1	0	\\x000000010000000000800003c0f694053e887ab9afea608cfcd34b60217a8679aeb840876b187adbe76f916a132dd1ce8dbdce1d4ad197b1c4a09365f68545751cc72f7d2356ed35c43c8b29d50fca00f2b4067d476a6914cf689fe88f7390262144c87bbd17092c9d93ba9905df0c3dbde0543ee9571abd7d06f6b0afe58ca467c25f5e999a4420ccb1eb3d010001	\\xa6041aed73beae4326411f3a752348b400ac3455e4611dbc2a668948562f520021db29f74dada1164323f86e392a3690c6cf0377cc6de3dfd2303b7f889de204	1660564985000000	1661169785000000	1724241785000000	1818849785000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
99	\\xf790c1403b195a946f20e9b4696dd57fac2ef3db71eefe3312fff9278e6d97f1eece01daec78ac91d44dec09d4ae2be2297b2c84636fe9ff1e743f5fdd042026	1	0	\\x000000010000000000800003c178c0e3b37aac26af292129210357cbe6d05122dfe11af2b578b616a4d5d5989c596fcc3c76447f59a9ccd66313b1c567e78261152da6a0c43c520971d04e8c0ded13cc8b6a14257c7fd00c932a80f16b4082a95d372a7f4238486022f2787e0deb8ce79080dd6f62c19f1914b5cccf4f3c7455dffc24356333bb84d6ecefe5010001	\\x6b394b4a8ff9ade818ea3c8d0ed8d47da0cbd028f98b88763ec82aaadd215a61f213a70cde77bed26cc879fb9dabf61d0b1a21138eb288315719af7fe0053d0b	1685349485000000	1685954285000000	1749026285000000	1843634285000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
100	\\xf86cecd58a80a898b430407260684de3a0fa80d46658644eaa57e046a36c8a79980efa90db1a442fe8795ed4026b131f7bff30eb3f6b959dad3498c22a6bf2ec	1	0	\\x000000010000000000800003d07cea11336d71d156dee0e5cae26444ed5b9d472f9133af7791d22a022dd4723210f0aed5b9502605f45aa53e1e88c4ac83a6fdfff5ff3323fef5094a74946ff2001bd1d620b28b65ad9330adf7995799cc4141496497c4ad62eaff73ee889349490163a2cfa8ce40af0d34b17f527290c81ab4a2659886f82c4918eddd7b63010001	\\x2068df5068a4c6686e41474853d0bef1c4af453c41f9d1cae0d7fea7dc9906b58c577d889c177c01b30b44241cb8b1e0a2f9efa5517d3c98a49ccd39f3c5ce0d	1659355985000000	1659960785000000	1723032785000000	1817640785000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
101	\\xfad4a2a4620aee8763b7698f3a058c818c26b558417c8d540cee34dd1efd4073fce8e1b28f7f44354acfb9458f1deb947635f30a51e4057f7b391b79f5747df4	1	0	\\x000000010000000000800003c446794a8bbb80d0c8f2d4482da472ae35056a078db32566a343dcffa43ec6bf6e7ec7c1f5fda1665e2b86a3b7b2cf00996186b330b194dbfa0bae97ccb77bbfe4f653dfbe15b7592b22eea206ff8028388fec24cf96ea440df2540362d7a778b7f2f2a307e4ce01d66acf98fb48a740af32b56dcec78a854acf0e3eb4c65d95010001	\\xc08ecfef95e6ae1b83a61533a1df49acb9bbefd6f3f3de6635d51dbed604e5dde6d3f500b8e0874fe9cb7d5c3c42ea98e3264e067e6a8cf7fb6a4e25900c9a0e	1679304485000000	1679909285000000	1742981285000000	1837589285000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
102	\\xfb7493394aa414c39943d491933ddea78f96a70515df015f3b9c95b8e9bc97cf151e8fa275ad0677adad7688863e894b7fa905e6f6c3785f6241aeb857119f1d	1	0	\\x000000010000000000800003976c5c953e37ac0bbda0ef2ae05ffa0bb7575d57e66cdff227347e5671d29f00a4d60e24d5f217eb0984d4c5a2ef8a4d6426491ea216f92ba63c2d74e0f620467d2a76250154c381647cbacbdc6198c3145d33fd374b89890bdf6a22468a7a27bcbbe28ce012baf622545cb4abdb566f5ea719648aa0d16a150ef1084bbcf19f010001	\\x5ee30fe9075ebca0bc36768bcae4657c5ae1327b959f99ef678d1061e723a4a96b3081cbf6cc6af5fa11f4fc350544886dfb99a505b7fb576d043d8aaa394507	1659355985000000	1659960785000000	1723032785000000	1817640785000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
103	\\xfc042878f1bfce89427739db8f33fcfe60eb5bc4441fac4ca8ae3d93f5e8f16ff45396ebca5da8139942b6dcd4d886010f60accc0cd2d7148fcceea3a30c143d	1	0	\\x000000010000000000800003b14a59c523b0348f4c5c17fd32888713f397bce4d8b9957c2c73896308c3a706fe65c185a7d18c838e9e8577c562e838367767c196bf5b1aeda4e30634bf4cc7426e0b0ad07951e6d282933e38c63b044c40b61f18ecb272afb78e7b028cac3efe64af1eb63f784eca156ae046531422f8b6c10bb0d3003291415b8b4f86b175010001	\\x334d6ddf69610d894f14875d8c750e829e9aaa971b90408fc53b540494cb8c82e0609d3733043b26e2bfef431baf82c2a88da50a65c94ecdddb076a4a952cb0b	1663587485000000	1664192285000000	1727264285000000	1821872285000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
104	\\xfd403ce1aa95c5459f0436c2c4a92b1f9b42b8105a95e5a793192e1de3f6104143df92364b73c7bebe2d05f067aa9da496e72df85de25cf4cefeec028c4443fc	1	0	\\x000000010000000000800003ae05e2204eff7010b6d372d46946698dbf1f1573f30337e2fb69d4def8afc9cb8b9dd12f5b673b4fcac637e9235eaa6fa818ce501910e1a8c7be1878a23cef78813f3e3461b20bd2ffebae70e65f5c190fba13a68d02e49014cbd0f5d2940f745dc4a709628cfba260e0a4c16aa4765b96d1f3f3645423adfe5d812a59de8af9010001	\\xc347506086553f960325af1689d1077b85b11e7f889202cd3929dd745c711b5ec6843712bf1678645916ed0b2bd3dbf1d5d6815afb32888cb698d99c9a9d4204	1681117985000000	1681722785000000	1744794785000000	1839402785000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
105	\\x003135fa20a00aaf5236b2922657a519e8a89e5487a9fe2bb686374dc21b4f6358dc2a2f9828baee7c06f85f3207c12eec838fe28dd907bdd45cec1bafac32e6	1	0	\\x000000010000000000800003f06f05deb7643e99688f3ea628f8376b49a922ffec829118ce72bab672b7016fb9ea8e1fc8e6b04727e6b731039ee39e5a02f0cf371db1b1391b2b18ab1b7927c84ffb9d2a41b8b2218d2047aa743cb985bae19f4f5eb13228e00117f32d0246533bd0e72c94725ccca371207985859731e3db7f0ced834b2f62f3dacd4c1c3d010001	\\xc6690f9b20d94fbf94535c5bbadd2092adf4453bbb5efd7ee04b41cc4f52d8a4c0956a9d0bfcf0f250776779b7b3ebbe89a7f4215a298e1b0b448a6b6832500d	1679908985000000	1680513785000000	1743585785000000	1838193785000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
106	\\x02759626d26d737a6469d01e6c54e6002ecd9f3769b244a862f5f7cef230803c834a66422e470e3a96b901760708da73b4f87453756866a5ce310b86d98d79fd	1	0	\\x000000010000000000800003c561722fdb67147e6245c09c9e766478ececc8ffc3411836acca488543824fed383852c29d124605b81526b0b4edb90a2a177be6ec5f2c269e8c6c1a5e587fba2f0a1b4d3d4cddd745579f5b7bfbb5225ed97f3b843bde448bdb97c2974491ba6698df1d7fcb4dbfc6a7907a12eb81f8c7958ef0deab14ce65a4d12e24a73365010001	\\xb2946be2eb300a10541c5545c4cccc1049377f0ac72c778453e17da3e15613acf317098267384c9458f150385ccc8672c708a5baee617d2a84c5a70f7e8df300	1678699985000000	1679304785000000	1742376785000000	1836984785000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
107	\\x055d7bdd8f8dc29955599e49ab6cd204e1d6d068cb3db8b26f788bccd4d1dfcb9ff8ebe6caaf1e44565331468d0eab2597e9441416760aa7f143c8001c06c455	1	0	\\x000000010000000000800003c6f67cddfbb1c9491756a555a98f8dc31c25e7644b841eb2136e8e639a2d8d8ae542d07b3ad75832aba0c62ad0908e05ba1627dfc37b4e6af03147edb132debaa391827f8a20fcba6782233c5890d42d406abb4d6767323deedb27c30b4dba0af3772c878ce9a5ee3f276a7abfa07ef3ef7ad08f10dfa28946ffd977c5ca589b010001	\\x58e7b80b9e407fcf3f228b7755f69eabad960656dbce6c36fbdc7b1a57b1e63de384f82637a28dec6753be6728c6854aa5d7898418c2ad30d011835725b98600	1669027985000000	1669632785000000	1732704785000000	1827312785000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
108	\\x0bc17381e03860b8d3ddc6409e58066d3a2805faa30876268435d987f310a38cf353d6aa2979a110dd64e6a4961239dc357935d18665843579a8df45655d36d8	1	0	\\x000000010000000000800003b3d65aa755773c8a8b2297969f586ba22ac90514de5e2ce505a578e3bb9c11b5c3c01f78637106af1b19d148a4489557888a0b0d5b3fb6b363e430455da3a464cd5c66db217e9eca20e3d5b9aab5e1c4ea5e9f99381813f5ba63bb2c7185298d1acfd6c22dd2f09e708f3d872c423331df0cd4c5eafc7ccb754e98589962a6ff010001	\\xc6c9ec3f63201fa39c63170093792af23a4c688125498f6442dcfc865f2c28b75c68385cefc4cb8d9a2c253790c8db4ddbc678b3094b1fb0bc5b4828f29d7902	1667818985000000	1668423785000000	1731495785000000	1826103785000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
109	\\x15a98278cd77ccdbfd253dd2bee765af6f98829f3d1fb63e7da949ed88796d6d66a4f73db695276dd70b14df6cf82a6872357736e0a076456fb70526c86ee90b	1	0	\\x000000010000000000800003af61aac57fbcc01a28b63c32586b9541e0ef2941e77d2016852ff0b2df00e19026e2714f88237fef313aa4813aa2de776419138f142a8f9a7915c1b6dc854697f9ac9514dc75f3e5a79103c25c645f981b6bd2f9904bee544bb9ac0dc328a51978d5b5debf21ef46c5a4d281b2d6b8287fa164691d5fd34b21fd6774395e2d65010001	\\x6a55e50b42c895f27ea714c48b80bf5265fdaa3e9aa853992bd1488d09bf1dd06002bd245e60be854dba3541cd385e4575c9b9488e4a14dc843ef969960c7808	1666609985000000	1667214785000000	1730286785000000	1824894785000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
110	\\x1a0933ac69118d7c65bfaffd2ebc30e40f480bd16a4c97c9a62de717bd49621e4217e9300d4f64e168f5e8211e520c775dbc0dbfbc595ecddc70e6dcca9f7f43	1	0	\\x000000010000000000800003b810927e7f18ca732826461c421f8f2f4a61cc03f547a416b6d4650f5ff20bd32874608c6db2b741d1c73367f00737d4c49ecdc965b9fb30a0afce7f131c762f211545dda7c89295b6d024eb279d6674a8159e4f2681201b1d2750bfe7ee2821a0816edd7b4d4ba063d05932153e0dfa9ba7e301fbf220eef04ffd7c717138fb010001	\\x492d58aeab0ac184887a662dd807b56790b0d013ed798b37b2708a97ae490d50c948a16ed3344bf9d8e4858a2bac04411c5adc4771c3e109037d0e6aedc47e09	1657542485000000	1658147285000000	1721219285000000	1815827285000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
111	\\x1a6d6e1e050e7cb43821eb7c39bda2c38fd0f732a6ce959bf4e4368b07fa000b114f6ce0b43709533cf6d055bd395875d0189747da5f5d6d59a6f110de3f8902	1	0	\\x000000010000000000800003acd32a4e209eeb35335dcc45685d6d77279a621242f61ffdd2acfb26ed7f2a4c66852c19a41504a40ce618e401586615a4917d06559e1ff2e9d1de2cdeebcbafdad3c9dbe056e42fa6857e2167d1e5867ea3bcd9d6674a4e71e1e3e10930ce65d5ef64b96d6cc007d81d98bd945ddfa897e6608b7a482c4945e6ad2260b7b60f010001	\\x7e42a34eb5fd48693f2738cdcc6004108667b36b0ff67a07b87b3c744dde39a660fef490121d0c91e8fd089c8537dcb78addf8edb70cdcca6a7c188c35b47e03	1686558485000000	1687163285000000	1750235285000000	1844843285000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
112	\\x1ad592dc91867a89d666fa353e62b98f3693080780ee8071ee9ad045325ea92bb74c377a4b8bbca349b15885cf6f742f89324d6168a844ee0a3b76a128c96bfc	1	0	\\x000000010000000000800003ec2f9a22fc714a63a777eed11df3fa75ce13e3f93b8a880ae8c3103f1b7edce239395e3ae843e06e571c5d7553455895b566c9e8d9abdeec1f04d4ecc9c8aba67b7499bad7dc7dd16d383286f45aaa033e50e680e2eac573a4af6f4b33317b3aff9270298e77e2a2584589dc1956b23e9733ae6b106b53240699b86581b67acf010001	\\xfb7cb2555ab78aa61b2f5a3eb682bc64abdd3eb985cfcb53bf45d67db899a7a70f9a2206891545d56e689e0916fff41abeed89d03bfaf92472f3119cc1e81708	1661169485000000	1661774285000000	1724846285000000	1819454285000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
113	\\x1bf1caa5dd74a03f485f1ec37dc8cdba971693c41751e1350ea8dd5a92e98e5714bc7f3f9cfeb0926c4743252189bb8156e5e0a9d4de065df701211b9522747e	1	0	\\x000000010000000000800003aa27612b83573f9fc9fcdf003a325fb571f23a38fb700afdfdd3eb045a1f3bd1585b4fa43a888978f8e008de082a0a639e9caecc433e53d46aba1e5299ba7c25d4d2e03c137ddbe0ae9a2eb3aa0d2eceddd0d8933fc660eba1f2531fec8ee880cb31dabb20c6df96877e4e2386d623ab44cdb170d78d6f7663aeb82263453089010001	\\xa49a9e98ad9fcf7520a9c016b745738937f765c2f95a6601b22339d6b698aacaa86730f607fe556dc469b49d10d2fef2603dc30c1a3374adff95d3ca7a625205	1665400985000000	1666005785000000	1729077785000000	1823685785000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
114	\\x1b291bee1323ef1662ae7266a00be07ea4446e60b1aec5de95913e07ac1c08021eb61e986698038498f90c1bb9849411065b5ae2bf19d5fef09e0fa17fd17869	1	0	\\x000000010000000000800003dd7f39aba3b79e5424382b3ca8807b6b299a547511eb6385f100480d29c2568bf5b735f6d65e6dfdfd84d372bc6b90ffa221a532b8d0d339ede203fcbddfb6c3f9312d3b4c1ce034df7599a987d34758d0f4dd94a53888ceb8c3d01838ade78d634d9bb0f58883e89302bff4c30ec25277858a127307b69dab837c525b14bfab010001	\\xb7da54f14626cc985edfed296c5b7a7d9c8d48896d3e023dd50548db88a981708c314713a78abdbfd83f14c2d150fe5f996229dbe3716b50d400b2023d59ce0e	1686558485000000	1687163285000000	1750235285000000	1844843285000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
115	\\x1d7d3ff7cc966dba00fc02253806e96affcbaf86cb35f9944696534f5c96f1a3a23f314196fc13a972d8520457d78fc93533db78199880623416073f29e31fb7	1	0	\\x000000010000000000800003d48161dd9e58c3b0ac789a9d2b052b9a621c0d153f5f004b800ab2325aba7e9832cce93411751af0c5e13dec8b58bdb78c505c0c6e8a57dcbf6607aa5cfce05bebc927e3493f309f19ff83f7e526d2ef2bd2738276fe78c147c8874eb8c91bc14a969fda5312abf6c5687cc65c3dd10005a0aa721613ec6cb7bf4594c5a2699d010001	\\xc4eaa6215fa5ae081a099c6e22d0599e1f348606c8e664d11ecb38dca873e4f4762419f0154e82fff5cb8ff42ef94ec020d39d04a171a47fd6ee3ab3ae3f8400	1684140485000000	1684745285000000	1747817285000000	1842425285000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
116	\\x1f9d2ba0ac3926b608b2c642e12a9a17359d099cdc8e27b370c29d5780117fb860607c21c79a8caeed8e60bf46afc8c24ce97e79f55567732523ba4b3c50721b	1	0	\\x000000010000000000800003da54e1a39062259c7644b3056e9620fa0c6dd7253e402a780245c08d273d2b201f24a37691114c0adb7583e54418a1e0307e430af40168e41a8b25d0b3589865fa1ff8c9f91af31d95fe009c9487805634b69fb215434dac6b0f2f7a65176620cabc1a2813161d5ec48ce4715cb5d1534682a8d699d26b98b9d72aedf1288469010001	\\xe96bf311581c9530c0b1f0f180e9a51f55973b6a3807a4b49d71575894945338489dc6ddc40f8f291d6f40a07fde8be533eaf3c3abce9c6b8cb1566469c5f603	1679304485000000	1679909285000000	1742981285000000	1837589285000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
117	\\x2119f4e9c69a2d76f82f494260f8d9047773ba8397c73d26c8f73e0b19d073106d50f3a5e426987069b7ec12160336b62989b4f7b12e6e7032e2feb4d7bd755c	1	0	\\x000000010000000000800003f20a181bd67fd83dfe7f0a8bbb68454565898b42a35e95a04247c47d0b1f63eaef93f891cd83ef3ca12462c2a1dee1138402cbf991fb24b3f390b708c0aed6e757d1a47a7189719efafaee8c66c9b462bc20c77d17d66ab361cffcd6be5f263d01376960431468f525b324f8b04b34e71b4eb456622206ef60067e9f36e97afd010001	\\xab813183ef5537351b63a0319e5fc5067dca16aae21a5e8a045a1db7593f4285df007ee09ec0347b3ce3c7e5f086429e6e1d36d65aac87fd2a73ca457dfc7f04	1676886485000000	1677491285000000	1740563285000000	1835171285000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
118	\\x22419aaa01ddeaa577919e12baa7906666634e9c5d60d7e23015828a719f6e4d9825988e28bf90cada0098ba6c76ccdf77324c096256c2175caec2122f6fe116	1	0	\\x0000000100000000008000039de099efc79947aff57b7ad5df75f326e1fe6d08e2c4a030d99f69d7fe3ca38af4a33a7ddf82e63d108cecbb166ecf5412852da29afa7c1e088774755a5931ff7b050d607a8708d99ac3675a6a13ecc978f510a994ceed694982ab62b0cbedccdcede73fe275f1603bbb82c2dac8446d1c12698ef34f30d25dd49c7a5783e3d7010001	\\x86a1a8ed235bd58646823d4c449f08fcb488ffde0bf62b8a37d82160ec9e48bf4a280e37d98e665769a725d218e21183f5085dcaebe477b858652e6232d29f01	1658751485000000	1659356285000000	1722428285000000	1817036285000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
119	\\x23ed094ba59abd8caea459e870dc5b469e654dabd373dadbc1f14e0c1acd1941cc2e245ca0f5d1dca37296944996b8fb29a90afc5d1cedce0f69081de1a62283	1	0	\\x000000010000000000800003d17ca52681796574ba8a9bfe4117b27d1e851619e7a8324dc7649af89744e3ded0befd0db1aeac36e1c29428f93ebd794ab12e47c283b70280e266ac1a2537e5600f0bf01c2d800b52e6ec695caa9c9841a065fcb4eda086a0aac94e73e70bd22271f7f6c9ea71b4a7bd45ef7dfc743e6b7b8d4c4b04fc7e31721b8e9f8c46c3010001	\\xe03be96b02f2e9b0eccde6ded246b82bb8da57a764d88a5a70be22df24bbcd8ffc8d7cd6676595b221f91c567ecf1e78c1dec92ceba58421dae83b0a2629f90a	1670841485000000	1671446285000000	1734518285000000	1829126285000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
120	\\x24a59a00a84851ff68949ff38355ef968bd1f967fb245d49bc0cf3bc5bd3d0d181375faeb3be8084d03cfa97adff5e3d6fd080185db57220f34259552d1d8b59	1	0	\\x000000010000000000800003b8e9bae6d52ebc4caee599010bcefc87276b7d945ea4136ba480aac1b783662ee3f0c68dd89034fbae1d9c1e8e4a537194611944dc69af99fe4433a958c80fe033bd13fc5a8f634d4238ee746bb70e8a5fd0cdaad12bc591f69de1335be146da0fb49d8e0d8b8a6726951df92c423cac14151b2e981b4ef062e2ceaf55f2bb49010001	\\x110b8dcd07ea90a4620ebd302458349de9005c6c9d644e7cb8b108635bf2f5064453847cd0810713fa5527efe7fe42fe8d3b494e6b87aed6ecb448860631940e	1661169485000000	1661774285000000	1724846285000000	1819454285000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
121	\\x2ae51f2d3f8b6910c412d4df3a21b40988453e010b027c5ae8bcbe005702ef8e7edb9c793274bff50d549f48f08f6ce4c2849f7bd69af63324acd3d50510adb2	1	0	\\x000000010000000000800003c66151aaf18f31ec9d29fc6918bd9749b9ee4e511be7caf1b83a0712524cb8d18ef7a58e33956f437b63cbb520a03325d823bf4993e466bbd1ef97a3f7334d8ff96c1900644f766eebac6babb2b618fb529865b3c62bd89e8fa4f2a52c8c59d99c79c0b3eeb546a5d4e08fddffe6db09ce2969f8aea2fd17e86a5d3ab6e22489010001	\\x4e347d185441ec6f0eb7e4dc41cb4d2e8ba9418c3dc07e7536d48182e5dbe9309bb6d64e74b62bd7194ff26e1eebc586ba7942269cfbcd711bd4a5f50ee06b00	1685953985000000	1686558785000000	1749630785000000	1844238785000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
122	\\x2a656768b6ad370b1675243c1a52a3440c4e45dab436f2335716eecafad4348e102a7e2a23d72e7756163a775044c6572ae1077fca1a0bbe350d260f9fa15dad	1	0	\\x000000010000000000800003ddf1cd7509b911532f9e93deff3cd1fe970ba8d7968f5eb35f8d06251b95b5ad2d2a9b08f3374dcca878869cfdf9c50e0cd2ca5ed73aa850f77cec50713f20c2c9d9fa02fe4db43a90baa0db0fb7f0b0774aad80dbdfb47e116039b9430352c40df1fe4e8f4eea7095b9f7cfea60c99980eef9c7d388d946dbf6639a1143cb97010001	\\x9381235421d0119f4899fe027cacd959267db051b6e4c5d6892522b656a457a32a2e35d22043a83c82f88595f962e890335e7a5a75d0c113beddd31d94381002	1685953985000000	1686558785000000	1749630785000000	1844238785000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
123	\\x30a90792ff8e9ea631fe52764b06481d02e4394b7c6cab88004b92251797091a5cf1e4e6c5dbc4a3bba710b21e2f1fc3d2001429f050ba6e7a039ea6d8bb1525	1	0	\\x000000010000000000800003aefecd574ee0d9953f8af9881380d1aa84df3119000a818635d81c2842049923f3c592eb65a17f299ce176b33adc7ab1f196aa1502ced45524b612e64b6cd7dae69f0498fb3db51c4123109bf10f38ee24cad4af95aa49ec60ae612d844593d50ebd839a123506651086846f3da884a37edd33b7637ffb9f59a3524cd158df67010001	\\x89dcc900ccf0ff62ca481e91733620a918161a267d3df8fc78c3eb14a494c62b27417eebbf0393b1cebb925a9c22db98bd65dab2edbb55fbf5d31cfe40877006	1673259485000000	1673864285000000	1736936285000000	1831544285000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
124	\\x3381d31016de9a54b67a2cc8d5a728e90ac5b06eee6df9790b9767b519e4e12ead60caac07d966e7503d25d875e15b87061fc8cde17fec09d4699db792156e1a	1	0	\\x000000010000000000800003bd1910bf4ca0d6bd7d93c59e598fbd978c377e79450753156b81e42cab363030f8d83d3d329ab187495fc7eabbe9930618e350794c6ccd73e19233e0d88be0641dfc6f084e1226fd2ae2351df0554aae122d0a05372df32c8711f60c628f44fb04337bbc3d6fb6f5d02e79c5332df8b9419c6882464ac2a94a6487f22655f7bb010001	\\x166f5374b2203c690897545870efc055033603ceecf495191ff032dd9d049d274dd0187afd26cb7b13138b69818f36bb4ec3a38ccbc901240f235c88af985d09	1686558485000000	1687163285000000	1750235285000000	1844843285000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
125	\\x3561824ec63c1ad74e06241203e649f5d4353838f983ceaad6b775f4ae4c96a088277b5c70ea87ee79810116b7da17f04b79ba519110da117b74ca5759afa3dd	1	0	\\x000000010000000000800003defb107b01ef9041fe0003f4755830f0c9031fe01809b364cc433866b37a37443295f97165554d7734dcb2ce4a9cb1141e50d4375517464e27b323b73c940c3eb0428923db71e151cf2673402226bb972c2801155d76d74020496ce990a0ad199850bf0c133ee4b1db24d2c096fe99623b472d393de632749b2e761acd7ec7fd010001	\\x1ebcf31d21dffd57436f32ca50c5d72c5c6600b36705234b0fab90cd5e29b54ff688e8b13f18e541ba372f0c14cb030385184e3ea6171527410650c23703f80b	1655728985000000	1656333785000000	1719405785000000	1814013785000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
126	\\x39555a4bb16fb08d39bbd76d6bb8237863a0816b19c6b1e9f2de300a898698cc30f26ede10ee1f44c919b81cfcf5b72e2eb8e9210d667b7119357fcd0ab6efef	1	0	\\x000000010000000000800003bf1a34f98cc4dcaa7091430d3ce464d9960ab0a330649a71b00e94f1ba875f27b7b74e1781fb78ebd927e196d163096a42132b0c88639f59a9dd88f7f0dd121ea4cd0de5e6a38656041e03726b22349c333f7271e1ac2ad416bf35d607518dc320fe1aa8ded41dee25b645c7c617eacee6bbd30b0603664948761cf1c29e7e9f010001	\\x436a49f332442782d058dd95f6bbf3f2defaed628a35d7843537acb2cb31de1ece2f3e2914147bf0beb0d28d15fd03adec0b659e99e26c4e0ed3991688368804	1684744985000000	1685349785000000	1748421785000000	1843029785000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
127	\\x4259d2bfb79088562466b2de9c9922ac4b1ce1b545d5446b1cee659226bae6e905b3b4ebbfcfc827df4c073e2c667fb8a93719ad25275c769d74f58568046e47	1	0	\\x00000001000000000080000398cc932fd39d9612d083bc89431c8ec7403e7aec26cacf075b2ae61a0193001931204bbc82a8abe2c0ef208efdedd51e4ae45ada5abef6788e13f337f5616ea8f0a9509aa2b1cf1002a6926ce6882bbe7a0a419ba9d0683bf693cae816613acde491ea2fd95f324cca356e01249b7ad7d1d212e15ff44cc55d2796c69e1d2f81010001	\\xddb34b792b7022f9f2ce951c300e9b04cc1b2c2d08e39a48425512d9e7b67d711a26118f299d6dd2f142b7d7f5924ae76a2a3494cfb8e5d42e45f7465c97560f	1680513485000000	1681118285000000	1744190285000000	1838798285000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
128	\\x454d0cd81dc4f49fd5487526d5f59adb14e6a7c22973c388f8a3424faa15b3bfd8ce31cd34bb666ccbfb3f7b401ca80bc85b711d792d52026a4fe4533ae87832	1	0	\\x000000010000000000800003acfa7c085d977cd131a84d343754bdc2a53969b87dc6842111756cfea820aed7eb73340777df2f6996185fdcab7dcfe672931e50f2740fc218542cb2fd86167f73ff398407a08adf6a174960547dc11e20b26ba74b0f3a4752175600d4210768ad5eb0dcae61ca460c1861385716cf72668ba38ecd851e79f99059b4a23d4a67010001	\\x1879f03541cf2cecaddbe0ce97965980df5735d69eff269ce949eda34743e4ae5d625fcd4c9c6cbfcd19430c11c96117d4c66461a79c13a4e3385fcc0f3a7a03	1655124485000000	1655729285000000	1718801285000000	1813409285000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
129	\\x4fc5b6aca23345f0199a47841523d1142830e5b2eeadbbb5d9f31e373b795088757b9edae182a22eb29b1413c09e56e3127e9a101bd126e814339d98fc55c915	1	0	\\x000000010000000000800003c818e710ec148d336d3fe427f08605158c31b2ed224edfbc0ff89d9206306380c8c6f6a3a0fe5909ef9aaf9d6dd757118374d4f2d9c5c4dcafe6242d6e494811e831671f151806d97e066f9bee137937dbe0489888cc35a455e78fe316c069db629d3d82ecf70570cc50e2d5e5cab128170ff1d0977de72c935f840e3ade9d9d010001	\\x99877844a5cda55cc4fa48ee0cda953608ccbc8cf1e7374a5e53b9aca4e8f68ff83145ea3343539b72d275eb871c7e69c25bfa016db09f23795426e236dc2a0a	1667818985000000	1668423785000000	1731495785000000	1826103785000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
130	\\x51d97517a377364d1872a84ca134950ba879e4a509bc7e9b6da9d280d06cae17c3c689416826e73440a26baf49c2aaf77d699986d1b216bb2d2ba423505b1a51	1	0	\\x000000010000000000800003d0fcbb0d6d72b773857d0c5cf5a1578421b92f8ad4f8589e4a5590f0d416844698db0543688d1b1783435fd72b8357dda50e06dfd497446d49d5280a07582e36add53387f7b7910d007087c431e873e2acb3c478996a83915236642087926d978c8d055afb92c81ae080f8544c8454f165f136900697e28284db4786328f0677010001	\\x3605b729f3982db81d013cd168d50c05206ffe0b63ddd96bb7ff8565150c54b590b3ad8ff1512dafe54478c5c2489eb15d538798c02e27aa2d781ad17fa2d703	1671445985000000	1672050785000000	1735122785000000	1829730785000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
131	\\x5371ade692abfe51b67b789551898473ed8ee8eb6e90eedfbfb0ff407e040a3c951b12a70a126a53029bf96a05a57b4c3e6fe1fea62efd732949fe1cec96ceec	1	0	\\x000000010000000000800003e2ff8aeccf8678f532225345dd5ea8f1273a7ed084082c9c4fffdb603bfa57fee957a55fd9c7db83a23f6e99f39e37bac9db6f6bbbe7e81deb786e372ce378cf843b9e805c9266ac7bfa5264b4759d6f63c7bf7650adc1541a20194a69879d0958a185b3b97d1b5118af7dc8a45929683d2eeae98af010bd0abc2b2a566831a5010001	\\xb345e4d69a02bb0e00782b7cbd74cd36a487b22df2001accb6bd558982f6eb3737808ab86b6e5ecbf0125466573bcb245ffe34d35049b02ba361fbff4e76bc06	1678095485000000	1678700285000000	1741772285000000	1836380285000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
132	\\x54ed77362eee7bc68754e42070ec18fc883e7f689756ea285eef42f6e532708c71a323555e6c3409bfe5ed8e815c3223a2a5bb2cb573db62e4629e7874c82622	1	0	\\x000000010000000000800003b3d31799479d0086d0e3f4f43cb092d9309c5074c48d6b27bebfb711eb8912e367389e54fcb8c37dbb651b7fc684ef75a9215f7b14a1f80797f3e45723d2cf517574d84ed2b63db21263befa0a73a435503d7ce89c2eb14ce7c71febf8004104c48cdc4eb7de127234d897e0f0c11a6e5d693637a75a1aa0a5d2130193f95689010001	\\x35420bf149926090e4071812e8e2aac977ccb504e2322f83e19312ef0ad9378c216d14fe6d295bc6d450ff13c73acab817e69df1d228765aac183889b13b2a06	1667214485000000	1667819285000000	1730891285000000	1825499285000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
133	\\x568dd6352b731c27f63d421b9e38ca88e3d77f72147c538e7bdd5a4a35a053bc5769fe502850421df2edcfa43cc543a2c51eb087e4188d9b14ab9895cfe07b38	1	0	\\x000000010000000000800003a49fb892fb9dcb2e9e82b8310f0e7ea1cb9cef0a9d95c79ee3ef22d20eec69dac9f423524609423fcd1431892931ebe9712db4781fdc8ccb5aab5311362d3eb03c49bce21d80cabd0443c5732e1046a27318c7e7c866a86af0c61ed88ec6a20e969fc3c275570e8b08890126bde86b58ea938fdf8614b4e7180a4d355ba5c3f5010001	\\x35bdd4659bbc1c2a38fa0c384639164784e11fb9e0db766acb1f7668a0caf580996179bc8a190d7f912af9eee08e907f1916b835e659735bba14ab93bc2ab605	1657542485000000	1658147285000000	1721219285000000	1815827285000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
134	\\x5999c4d166358e921c934043fee297120cbeb537be57b86f2261fcbffc2524588975c5fd428c6bb73c853c1a7d3989aeff94dd072ccceb2ebfc61c19ba5fc500	1	0	\\x000000010000000000800003bd15d37b8db1f3bac1c41af74be216dbe8842ac9ff0eeb1aac5990795bd0e73967b193a2bb0d9b33eadfd19b0ed9a90fdc8cdc052affb3fb840567a68a6a88b1546174f18adadba5f51fbac3bb13a6fa65b353f0f109771b2e17cb3661d8b285ffb93e445e242f60196fde66ed002d2ece2520d2604ff307a431bc31468540e7010001	\\x040ae75fe20c9a02e4b89b9cfa3e85d169fa8eb58f8d8a9b75d9d98a0421123851d2f6e2bb9b329fee8ae4110eebeaa563ab5771c4bebc7bc535e7e5b451130a	1685349485000000	1685954285000000	1749026285000000	1843634285000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
135	\\x5a61f970adc5ca8027e61b0ccc3e9e70bb0a59fc30b32f184812a434cc079199c34a9a83667aba167c27971f61a51b21099144d9fb6dc9c98d676e3f7e46e7bc	1	0	\\x000000010000000000800003a6dc5a6191b868d6c2ced61d181d038ffb6589a505ad1f6697a001873e3c0941f75330207e3b78f49b24775d396f96fb454f1fad862f1b233211a8c7bb916f07a708149a6dc0673bd94a2e616d93e946f229c91d04ea479fd07e0a614c3bee707c62a594c770c7e1ce322d74c7e38efcd2bb0022d74c069813cd010fa385e04b010001	\\x3cfae08e59f543281ea431ac4acd2f195ac157a6b7c53e096681b1ce7b876dec12045aeaf46d2050177ca4b837297347f9c2fa8b65f2b57a46b2ca12e9e90d06	1675072985000000	1675677785000000	1738749785000000	1833357785000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
136	\\x5c25e7ed014721704ecfbd4d29b5aa0ca284a0b5454b846cb3a53e7ba4b09ce31c42fa4af300b55f5e515f556f6924773448866b405017b3e3dd2195d98c545e	1	0	\\x000000010000000000800003c6d46418c7e3c6062534be9031df7fd82238ab224e84eab3fd3e618024981ce2ba4af0caf4c83a7398eacc049b3b4066d67fb14eb6601e4d4a6fc0b745a8bc93676113d2a7e6bc7119c74157d4fecb34b05a599114509f784fbe050f8e8e7e64bdb716c129460657cbd82244804e74468f9a998085492951bc7ec69b1cdfb519010001	\\x0fe9bb57edf9fcb499846011069106ad0c7f8c2c1ba34b89d4ec949e3ca5330e13131e2631e38c17e444a319a43fd310375ede70171307a91775914fe7cc0506	1684140485000000	1684745285000000	1747817285000000	1842425285000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
137	\\x5ca500beb7970a9ffc4742e0736499956f1a45df7ca01c49c719bac3214cf5e0b05de1940e96faf57160ba9bd9295bb18c7b9e99b1a93280605e13580145d124	1	0	\\x000000010000000000800003c0f15593d58cf275be6a03bd1562b669905b2bbac280857348b4ec0108e2337df8e29f90c10c8207b7f1b724e95171452ea7a694b01d51e5bbbf59f6e098586367ca8f9325fab144f1219ceaa127d5f7754fba3259205a73f01009cb1ed119dae654ddb83d452edc9ecfab9f5ffc89af505267da7f14afea4c75d745837f45b5010001	\\x56b831a05b380375594edf14340400d373e6acec3b8b1183e3f1b442f9d8b1e0faa82e42ad4c666c954d0a0733c239c3ac714b55c3d9f4a8741d03308c72ef09	1662982985000000	1663587785000000	1726659785000000	1821267785000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
138	\\x60156f25a7f12e1d8f67056beb4afd0b1c415b8e04b62c8c766d1f1b9126e230c4b75b29bad003ed5dfe62f8b1a211d01d9db0f9336cb4e7b43c2b7a79000805	1	0	\\x0000000100000000008000039fdaf88ef91d2e20af95f1431b6800e87292d89acad126cbb958465d1c7567d5de96d602afab2191d35bb20486ef82c4ab929efa041e390056941cff0e6db9ad91e1bb55f3e0364b41276401de26c9bdc5086ab36725d892503055214576f6005e332917654ef24694e8e8d8a7834be35c13cc327df2dad3e5d4f7787ee4ccbd010001	\\x6bb8cfd8a474c529b395f323c03897f9a08b83d2e551a08d6559dc8b8e10d8c287b505a92f16af9b7e34b312e06bb925cd8110e9570b47eda032af6d97de3c07	1676281985000000	1676886785000000	1739958785000000	1834566785000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
139	\\x62352661ceb55522872d58899ed8c13af02aaca517b4890bda82ec193dca5367e0774d9a6761e7b10582e978d620ec7b563424be66dcf22e6a794d25fd7f8baa	1	0	\\x000000010000000000800003bbddd487ea3049281170aeafd1e1f5e49c5a56b9ea77492bec98387296b304cd110f0f495c4cb8ce8c43722276f92f17cd7d69132e3d17b24d80868eed1dbb3f1a276ae51a5418e85868b471e9b9c53fd3804e177c52d05c7ec294b68d922a64dfd9968cf7dc4f9e212bfae8794f97f16086792f0a8e9f0281982ddef4a41791010001	\\xad25c9197fba727ccd5088482d8eecac13bab8856a3aac4cdecca98fac1aa8b4b79274ba699f13a5828d550747986d8ea219a43dbc279eeb8aed2ec9ef525b0a	1659960485000000	1660565285000000	1723637285000000	1818245285000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
140	\\x6855d8e1b634100c8647b1dec819cb0cc4eb49cc82840fdf51202c877294ecd26b9ad63d4f1e41c6169f6f4298b096ee30885f0be75e5f832393a14e7f48dba2	1	0	\\x000000010000000000800003e104416fbdffb502f0516a63f0ed6def8893578e229204d23da41f565b3e8a92c6e386154fac8cc6567ab179bb7b634eeff304fdc05914ed555ccba7e4fafb34b17a87a083b0c27edf8f2625e4e373a56ae24af45f8bc4e2b465cf2c70ee48fd223bb2e67d764895cce1d866a3de0665f1b5ec8d92c596cd1769f0aca94e625d010001	\\xc9b3569a07008be84aa9e79d51caf70648aef2dfe2bb76989b7a3efda1951b0c7d1df441cb47a93b884564b51b809a798230f48d5076c6d1a215ef9e313d8105	1682326985000000	1682931785000000	1746003785000000	1840611785000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
141	\\x6871c931ea5b22b297077afc5b921542a8a7144cd2e6f13ab2c1258ccd1982b50ad7e04cec3f0cfcc415204e0ed8287d78c66777422679386d3ca0317196a38a	1	0	\\x000000010000000000800003af35e7d66085f157de255d8866087c14cf1e04887238cb98a1f176baa0a775eda75783d4f6a6429f6a10b7a4259cdb4e10d0adfe5aeda4cd8ba4d5f55c7fd4b1210b778224317d8c6e2e7c9112d0e5e1ec9739756628ea965abd37117f2b2eb937439733eec563a0f560610475c718c32d945782b89c0626a04be71fada7f0c7010001	\\x74c771f8a2730ffea516d2487d48bb166540f966fc87920ed3d867ce29a65b60b9be822a6de161f6678a2727b5a919143df99db42381ea0e5968db730809b90b	1664191985000000	1664796785000000	1727868785000000	1822476785000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
142	\\x6a256b17548e125a02420313ffcf76ff9bcad425554d093ca56ef26ce60a7d972801710ca5fa173324213203e9cd3e731e6fdbb5f0cd5df13ec617a16a3b1fd5	1	0	\\x000000010000000000800003e9584abce8927ffea8741722850441461a7cbe11f8f1c001dc8b2fa8e82d1b8d481a9e1a8e871f0cd689a0d9e4543e9d947a2dfed9cefef066a4c7f51d9125d944091e450a85e31a59815e7b02ccc099b9cfdd88378d4a926abc5486e7a473ce84c9d4b9af46af8cd08919677ada6011285790155b8aa37843c7608af8dcc725010001	\\x08ba4520cbc4872b869c351cbda57d14331b656434afde50cc5568d11d5f9a538409e785e630a30084c3bfb69379e5352484ea2f54d18648c53b7033e20d2e0d	1674468485000000	1675073285000000	1738145285000000	1832753285000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
143	\\x6ce9007565c686c07dd2c33783709bde72994f07e48cf8344180c34607776416b5ee2ab45537a1064efca8e0bef6cc3131fd1fd90a8f5b2a8bba61f019a190e4	1	0	\\x000000010000000000800003c439a479b02bde55cd1f3a51d34b5e1ad78f4cb561c3720c73418fcc3c9feb0b0175807ccf8b3512789889bffeab01a1132477946ff7986a5e6aad2787f60412624989a2c988c2d19f861306afcf8da9f79b0c6bdb0c8ad64a750827fe9df969e27d084833c257c3225266ab075aca4bac23f6a7a2aa7c26dd848c860896006d010001	\\x692bfe46a2cd825200a54ea05ab92bb6df84a7d436f3e2fc0b2172c380910a34450b6460e85c6d12f15582b9a541e85f29dee0ded16675ed50c26afa2228be05	1681722485000000	1682327285000000	1745399285000000	1840007285000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
144	\\x7159ff64b498f4979c69137d3b8564e83fe750b921fd895220148bdc8d5fd467346be55b254935e7b1e56af633f45adb5a5500a0c08f77e8a95ceaa59c340bf5	1	0	\\x000000010000000000800003c6e7991244e2c1b9ac1f951ca8c8426df1567706be0e6109edc952824b3344976aa50e5bcafa9a4b3ad1e42eed14a1b3107949f368c261782f188aedc055c20addf92774d8bdbb2870d29309aae9b071e179d0bbefc0a28d0a6247a5d50ffd64e8670ae19534ffcc0281be2c9f11e83322a0532ef19b859a3ec4154749cb191b010001	\\xf63793683f539ed9c681269ca6016b3e502720cd1cbec1f4025e994381cfcd5c423d09124c868950f01f30ce63af0cef65d444aa8d962b10e7bb03ee35751803	1681117985000000	1681722785000000	1744794785000000	1839402785000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
145	\\x773d0122754509df9baf687809d0ada56b84fd36872ee8e07c6543cae4c4e8a28f61a4d140a50eeb5e5ecf362440c964ebcc1fa1b5cc424620fe7b09820879b0	1	0	\\x000000010000000000800003ade9b8ec38441bb07ff6a87e2cca2094ceac1fe39a976ebde54495d931f1014efb90da4c625eff4b50d719512e35ed193f8f1f7f71f61345fb035be8cdf1f31b553e7a82e3b1952a5ca6451b57795827088640c5da2fceeaa98fbee651f5170ce2bffa18adc3729ea01e3b1b12bbfb40103d7e557f171cd8afd5ea81e5258b55010001	\\xee59bc1b383c97b7746e7ea676645b357a30564dec452a97835cbceed1fb08848d7be914710342c3e22c70ec9ad1c5e94c3885182fcb223c3ef78dd41d25280b	1672654985000000	1673259785000000	1736331785000000	1830939785000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
146	\\x7be921256bcd5df0d1f7a75c58972b9172de117d6e3d7a90768cdf32214fcf71ba47d0d2fd5a86dddded12a6daadb3bd44bd22b473b800b469002a8a7c860f18	1	0	\\x00000001000000000080000399139806b97386789a4ed570b3aa9fe3f41d8e94bfb8112ac0b3a9276958ef5ea007be75058202e2459c451a28f924cd1a3234575064e266f11a8c7e872e3588b638c8693a5b1a03d311db8bdd85f8e0cdac312efb20b165f8a80319d007eab6d55c290813c1529174a1fb423e1284cc5cae8e8f9ed4d76de7055ce09ff417af010001	\\x6f904e32fed946e79cc41b6b17e8cd0e87612a8ddbc79646a8e48fe874152620e967e68d5f6f84322b8d9b38aaf5af0c58de335c7efc07994bfb51f6e30c0204	1679908985000000	1680513785000000	1743585785000000	1838193785000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
147	\\x7ec1b1076cb021e3982d69157d15ba3ec923ad0c2ed77f8f6ef3855ee2aff53558c10f7caec12ce089f23be24d4e6917dd28a2ac6a37d51cf416ea9ef903c283	1	0	\\x000000010000000000800003a2d84e41025b9e2da8d66a57313fb4569a1fe4aa43bb1c713a10618c384a550b27ae85dd5b868da91be38d75d445aae9983d604044445c1eb6b9871cbe7f31a9e8db88f83a1410aeea86ca4c9e935c8a01838d3e7997f6591447874106567815ead301a8102fa018aea32fc805ca7756de494632183ca75d375b8330ea29c163010001	\\x1c45c1dac946f0adb1000c721974e218995140dea56e82e13955ca0dc491099b6af8ee77585ee2dc0fc65f20491db789441e3879c023308a74063f2d48812409	1663587485000000	1664192285000000	1727264285000000	1821872285000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
148	\\x7f8d64e019ade5c1cdce8afa372d109ed0366f19b7b8c14f10028a51b3ce585b3905487a9d2bdd17913d85daf06da863403f51c8c9cdb0880f0f982b0284213b	1	0	\\x000000010000000000800003d2f1a39e23754c122376f8a53684571d24f90b9be962c0364183f17ed7dadf7d7c9b87db67edd3f4261965dbbd8f634263d0839d0f49a194539a9b25875478218e19dfdae4d01dcaefa0043541f1169bad27abde05ee6f4ea52aeb6dcab3007924bf9244347edb62f43607f31c90c605bfc54b74142746da189452effc2d8495010001	\\xdfdf6291517f2273e9f8fa56c2dbaea91ea4470299204df32fb7a83c3a8f8d4776f757ba998520679ce7cdb86305d8351e9c6fb871825134cc3ce66c24d73004	1679908985000000	1680513785000000	1743585785000000	1838193785000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
149	\\x7ff1a726cd72a3b935d9b9d0a6c7949c5f0cb6854862d29974e695cd3f57e8130df7345a927d6011b42bdb4bca6210fa063827546c03b7e7167f3d80b201d003	1	0	\\x000000010000000000800003d902540960b54bfc2674b1005a18958b77b0c9149517a435c5672b8686d764a706d6eb60460f24142559d193cd87c3a92c0d318fbbd7227a2a3e3b5909fc2864b8a84faea5caaba65f9c340fea97d6ce955aa4d62d7034f80e8c923fba7df862415003bf58852d4c2638c6e8d4a6cdc43cc183a5562a268681794c04742a3a5b010001	\\x2141e4673d1cf2a47e29cce41c1f0aaadf36fd743ece9cfbf90c7209548f574b518ac67550b69d4acd0c271d210f73a2253cf963e15ccda3f94ebd54d7be7c06	1656333485000000	1656938285000000	1720010285000000	1814618285000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
150	\\x8345423ce8cd62a42d8ed5469f0dd925ff230bea7d34cfc6e882ae60b122c2b220eabf02622510fd041c64bb8ce608b4abb5327fc1e2bf27fb289905b260ee84	1	0	\\x000000010000000000800003c7e9caf317ca1cb471250a963b7b4a8bea6e7c8bcf08064e066b9154b55278018aca6e5a9dc2e7cee36d68eedb3ac8ffc703bf57c58d611d23f376ea8ca62dcce2f09b7dae38cada582544dff05b1027c014ef178c5a4fd6df014509f9145048e4882cae216e73c71784a475a944b59ef1aff93480dec0e19a74293fa4dd6cf3010001	\\xe3e501d0daf96606e4499773107dfdaa19688e7cead2d98bcc22464d1e2642a8dd39b1da9af6db87c981d8b758c52e90195dd4e277e704b725895f6d84c3ec0f	1655728985000000	1656333785000000	1719405785000000	1814013785000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
151	\\x8cc1c102348505a8bcb1f18abf23b3e0c259e2fb39ff37eb24cad5cc2b61a6443a5ab32f8856563a43d78547e04d4748ae82b830d8efc47217f01fdb80f75925	1	0	\\x000000010000000000800003ae0c6e265fd7b6bc3ded251139a9b15ccc86d2737105ecba8a59c6037e44b18b764ceb71201e8d1a4fe76d1a2ac41e53839e4580dea68030973bf8686c0865a4b09ded2a12a69a9c64aba68578d103fa5621aa41e1d28572ff2cab246e33728f22494a581bcaa5a3f58f47187bffcb07048a66b9b0961b3eec6ed65b53df1557010001	\\x9a89c087c7cbf7b1dc78d172e46585a0d9062253f5d478369ff10dc3c6419cafa33a2e76a37aa43ed6e1edcbe85ed1e20ed2b3ab85eacaee679398027ed53209	1659960485000000	1660565285000000	1723637285000000	1818245285000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
152	\\x8e2d7c5c5a4067164916122c5a5bb9b964ffcf15424232b613a8cb8a587be606e5c0cd5236fb5b95eb69c6396c861400c033a132d37eabcec75e7a61e065f21b	1	0	\\x000000010000000000800003b6d55e55320f921bf7ef6c73a8284165b4d101b3a274edd27d793ce7ff2e47fe8ed70927eaee4ef9def0e493671edf60ef761034d99f4a8e15e93824c9f4ed68ad6947e5d955010781af81d6e9e2a8465e7adcd553a6b4b0ac3c0de9652d8e77d9236b9f87f2c402596c1ebe2bde7cae50064a32440355dfb9f24b757d3b899b010001	\\x1649bae4c33969a202067334a5a52b56ae217bb861fac6deff359897bee18735b5f719cdb3c32b657847ac1548036d96f4a7d8143188122e52e8a0a7c5522601	1677490985000000	1678095785000000	1741167785000000	1835775785000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
153	\\x90f98a1f47a84a3fb52bdd3918cca777ae7246510498d7ca0c5ac57ae631747b99f853a542a6a4dafee9b62b0469fb5c7fd70a473aa4658d4372ba70e29141e4	1	0	\\x000000010000000000800003f479e1b1840c006693a4060619e1ed1bb211b1fc90e648954cd14e90cdbcd17ed3c3645d2beca3ec951b4a81e8afbb2c08e291152a44b8e56c0bd4b86de927b2e2925c758b16427fa1c5c64dce005d1721ccdc424462398a392fb64889560f57ac92f99f3256be5a1356ded2e630e36ee0cbd8a6a0d26581fd8597a1ce964915010001	\\x2b75f4d16c617c7f1c0d87b3aeb02f11ec09755a94c24fb1d4d5e9667dd1afd5b76d8b0fccce66fad655bcf45d7e3235a9c6fa68d337c9930be1fe87da72280a	1661773985000000	1662378785000000	1725450785000000	1820058785000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
154	\\x911dd7634319e54e39e37e8b0ee38a1dfc39f2aa77a1eecdabb2e5d7edbf2d70a5a2019515f3537ac76666d8dce5103bb76777e40453c028317ba14e7361f6fe	1	0	\\x000000010000000000800003aa9aa024a351ae3ad87e99ca0c530a0c0793b8991666470adefe1925b5ce9847046ff6690db92d7a9ce726c2b35599bf3a36724885bdc7c024b22334f9ac65a3a9295b47064159b4486d07ce606522a6daad051a685fd56cb1c8fb25135af92447bc0107b190e02a6eb888763aef41328e31e2fd829c62bd4914e148b2b9cdc1010001	\\x039b619ebfcf0db337cebaba39356cc40369723d7f72b69dda303edeee9584cb2ab15b53aa886b392902bac3b560830f4d073291bf1e414b69a8fb2cdfc70c05	1656333485000000	1656938285000000	1720010285000000	1814618285000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
155	\\x93154f1f7b61687814d0d254eb879834242943e7b659b2a0f79b6480e41cce8bc7095ea7c4a5e3092ff4e5285323f17d2645bebacae05900bdf0e69c649c1146	1	0	\\x000000010000000000800003d7c7a9e87dfa73a553348fbca95dd0e24e5c4a84341d7bacf8d00902c3cdd6712ca7c12bed2bf6ad3a0d7289cdad1dff2126002020b8b3039d72947f8f6fc8626b9c1b00a39dc5f31bde92bd2b9d55f9b4ee43798e980cf6e91a113b5a8f18e62a9b5e20757c8c5efe92a70597cd94418a96b86699135b4d440b5a6cdf2fb5eb010001	\\xac049b5aa1e207163b7ea04eb1c8bf414b1b610cdedc304d085bd9695f25d979abf036d038fb09d6ea660174374dbbd9d2acd588e18ba3c17f55defda77d0406	1673863985000000	1674468785000000	1737540785000000	1832148785000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
156	\\x94e93a85c68eb1bc6ad509935f5398883001e35e5ea1ce498433da25f471c5e27173164135864aa902fdfddca98656c0e2fc9a2df567eaebf2a46550df5168ff	1	0	\\x000000010000000000800003d18e02658b97906c78d408e531b040488eb59f6dd6481151f44735ee97397f05e28fc185e4f4177752ef56ab9cda28014fc085e6afb32bc07cee05d2bf0cd4c000825c7224bde553d89112cada5072613efe14a47cf913762802f0d058d7313e467b9305180a662f36d8ec911a26e4f8e839a975c13a1a6bdcbf40f99ac3a863010001	\\xfb95a5dc4589f1fd7c22951e04031f00bd3b4348549feff89ea8f35a2a41ce21d39682ff94529c8186dd4ca45a28e495bc3da603ff22a41b82c5c528dc78cf09	1656333485000000	1656938285000000	1720010285000000	1814618285000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
157	\\x97996ded6d1ddf203feafb3b380aa1aeb17a1ca2130a6691ebc40e7c41196a960f150b4d904df585a0ecc0a4fc2a4e86b85db87ae6ec2d93777812d67e7dcbf1	1	0	\\x000000010000000000800003b5201293d3d450dced39bfa63982570e38b01ac60d562d8ca3263e7d38281b7915e8032cb38c77c66aca633688ffe8cc3abeed76b48e0f2d15de06b493582497f24300ef1171bb4e9f2fd4f5cc681337dfeca27ac833dff599b926557266c209903643ad192cf17a3d1d9ad5b7924e7b49c5471c62e0eaf518fdffc00180fcfd010001	\\x50285a5ef397000ce37ac66b09393e40b66cd200741bbb52e65903814df52ad56be2faac86673a66b413dff14b199fde65a2182657d23ab350a42aa22bd7b202	1684744985000000	1685349785000000	1748421785000000	1843029785000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
158	\\x99754d8e07f31027016221c0c2f928fd2d35f517ad1942553c6ef8dcfa3a7b21edcd7a1f4798f51e69096ac9eb8a0bf5ab3f43365cee8156ad7d59f7bf396bb9	1	0	\\x000000010000000000800003c9abf2d9fdc05e3244508e8470d2833056772854d234b7b5464f8ba1025b4bb2fcbe5efebeed8f8fe57695b7e5b8b62e92d60f75e1287ff3722ada50d81743c297372d297094bb7160c716b3786ef051366f4334c230f238f0e23306ce84cbe1db6b55d5c16c9cf30741801fd8da8a4e388238d8d0c71f1d1f7937efc8a1fbed010001	\\xe551ab7c89e096dddcdbed4aa65ae2600465103ca2891b1d59f32452b9a5fe9237aa5a9b573dbe98459a34c76e1145c1245d2cf112c44e2e0a3b16fce7ffb307	1661169485000000	1661774285000000	1724846285000000	1819454285000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
159	\\x9cf581d766aa8a04fbb35575699d47c2aa71b61aea22ff802e4173165dd1fb3cf854b31132d19b11bb2e3d7ed95ef94e0e73eca531fdd12a7b07e678768d70b6	1	0	\\x000000010000000000800003c65dccfadfce853bddeae3b938065081174476c38d28a593f73cae8c1509df09c4f89e4600fe698161f93b8ac93b4877c755c792155e6e5523d0431cf249230f4f9ec6f9258e01be3a5639f4dca4013ae1124c61de5e19406654a346ed2d4983fc1618e7e190d8b318ff055c6d1f09b6fdfdab4cf365a8bf1a86e1bea4ddaf13010001	\\xfd985c0ec83a28b1a1e68d82eb331ad50905da7421b4d0ed481b5d614e6f688a2a77b43d9c94a059e7a660419293dc8f170bfdb87930a2696e63edec54be9006	1682931485000000	1683536285000000	1746608285000000	1841216285000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
160	\\x9d8922ed4c6ffe188e178d49b62d8e835e0c58b24fcdf21e15d92fc460edbc30459c841d6d7bed1c767916534aaba2b7d641c8fa3a0e1a15e99bea4121777d45	1	0	\\x000000010000000000800003cdbf12defaaf30e4408d5298df2a5e45be09dced13a8dba1f63087e89e87905e8eb37fa865f269efabfb7f29621becf6c9516f6fb8f7682dadc613f1d830569519dd80aee51af8b5426ae50c1c5853cdabd78d2397014eb0b787225ee0816a85ea343ccd697088bb39bbfe3d4d18e47fbca47453dc50d92a85f84b3694e6b4e3010001	\\x5ce2f05371a30e8a5ddb548a06be1713cab03dea9f96110b0c54a6933edf500f281b41fba888f1132bd82ce7c83c498ad8e93072f92849099c1bd27f1652d60c	1656937985000000	1657542785000000	1720614785000000	1815222785000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
161	\\xa009cfbb907a267ac21be8a3defba5c7aff19895fa4bdca4a9a8f02a4741ee55a173401fc36367bd87581cde03bf40eb40ac741d3ae95d839a1a8519fa2f88a9	1	0	\\x000000010000000000800003a0c253efb1985cc3456cd1f86cd0591ce59510cfaa6ca59f638b0f50c1bae254adf7bc778395df3d58abf31c8e6687c46ad02eac93f070d2fa484f1e703046f4ef4a340c3663c6ec58b23180489ce19284a9b243d4ec460f52c64b38b4e8206d2ee53ed71a890c558f7aa2215b137b2840965aba785a5e7ad26db4125fb3d1c9010001	\\xb000e18aef34ea699bcd92217565fbeaade433baa009a64d7c827bf7e7495fbfa42b0a101ced9e5142cf868de458bda4789211a3437007a2a968c707fc8dac04	1673259485000000	1673864285000000	1736936285000000	1831544285000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
162	\\xa455ff75e8643a8700bf70f79e6b70cfff6a926313c77b3f88cf1d64b961fd558a4291c70d826aa5d4f8f7898b70d1ed2abc172082f189a185f1341e24268d90	1	0	\\x000000010000000000800003f49b0b27bab87ed329bc25c7b96c3e3966189e4b50a1667f2807bcfb6775d9022a0db8ded2364ff102cf1f94ef33efc134019e378e9c74055252b9198ac62076c57f8e641806557a3ea7899d9701a303d85ce6d1658b04c23934128ad865c87ea23dc81578aae27812064ea9d1e719fc29dae689d3fa5a6c55d89c30f71cdab1010001	\\xa7a8487f8b49e66515bd78c73bbc1e3418f66a893b3f2ed0b0e89850e024c835c62f413adca212dee8481930bfd141755f1f7ab5368853b125236693c3d39300	1678095485000000	1678700285000000	1741772285000000	1836380285000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
163	\\xa4adacb9dec8d63bb80bf5999e789bbf0e355d2e36d71747f025bae805c36512bec3aac4cd0e34fe847d941eb7a547087deb520aae2ec0e53533e84ad73f74dc	1	0	\\x000000010000000000800003ba256fb7bd0a0cd572e1a2946acefcd727a714a2a55156303acd93e35479a319f0b90af596a66623e7f059f32222b04a4df04b6d250d130aea8222769dd3d61be143b1412e5cd2cdece35b61e0a9c0e9f96ad03e859bc41c2b488dd635305a7ae2955ac0f2452823ff3b8156e3b5bd35aeb3804bd5bf72454dce9d519753b017010001	\\x2f42d3f097772f124284ecef295295e8888d490489852972432d78a1b4e9a0c166ca87f935ba793978bd823ee68f2ba1fc67acac020d3f575f440a0c51db5900	1671445985000000	1672050785000000	1735122785000000	1829730785000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
164	\\xa4ed13d70f2377a62cf2f5e2da19996f1995ac46470083671dc14d3f6f4309987c36e904483bcfb7f84f8d9c3d6d97301aacb6f332df5e32c8c25d1ff79328c5	1	0	\\x000000010000000000800003cc88f218c4e0508456007245401fbb15e5923819826bd722302622444a4fd1e0306a448f0bf2d3c28db043500ddbed713ceb7b072c06a936079612b641d8862287cba555a5efdc8e6e880427fb149bfafa6efa5f3bb7a7477157cbc449951e123a2acbdd740f26b83098d84c1dce93b2c451d7096e584a9e04e43c5f411b9707010001	\\x20abcb912d181188a86b8b2f35970c5707d32f5db7e7e3c406b48da6b900ad1c807f8d82ae21e84738d794345936865b723f7f81bcbc127a3cbcd7ad5a65e902	1670236985000000	1670841785000000	1733913785000000	1828521785000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
165	\\xa7596c403a78b3c055aa4d2deba9d306a7d28a0541fa118cfc90ac3f49e9ada937ba0c942adb3d0f7a0679b1c6114e27192458e6e98e17529d3623ee45691a40	1	0	\\x000000010000000000800003d1abd13ad998426752345d16ad7bfc76d5bdab1b21089fba7b8030db9270878a467f6a68418b9ca5e965410c08981ac833cebff057b9c8574f47a8826d632f1c4e2ffa068d7a11961f3f5d60589c0503d75ed4f77bde268b903dc51dc49d5e96ea9f46df5d69413e0a091a5fcb1b80e58c5e64b8d5eba85c22f4372a086003af010001	\\xd8c0d56432208c485e95b03cd56196fa3480d7f4a46f66fafc0a475b5edd22575799f3ceef33da599022ac28669795fd095748b7fe0d8e0ae4e1439b67298002	1672654985000000	1673259785000000	1736331785000000	1830939785000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
166	\\xa8399bf3eea89ea3903ed5afcecfb6a0978c6c1f6f7c038aa13ee6c4bf903aede922df79f6ed1983a9b2478f4befe01b15fb265efcb01c38248fef0ab0bca42b	1	0	\\x000000010000000000800003d0e6d18af31c5dbec66200752ea182e910dbf44e8ef008070d2d3f4e69a9889fd0ab664fe0f1a058de11c229826ba4d8449f2116cebf96676b3476ae2174e8e1cd7e969a2625a4a1150bcfe5d87c03a01c7dd979f7366d318473c5485fe371cd3f23052336a44a8458aeafc13650ac8caec9ae4964c9c171647bc7beb47fa9a3010001	\\xdc55758a99bd5fac19b19d97626160e85c59c20f0bfea5bbc72453472d44086151bfc56b6327b08cc8965290b9291c4243749975d57bba40b35275cffbfcbd06	1683535985000000	1684140785000000	1747212785000000	1841820785000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
167	\\xaa91b8af839ed40bf4a5c32938e3fd52523bd04ae5db261d9fb1a5125ab2bd531fa46aa0d346d5138aea2f98c0e8cdcfc1176ed2fc9f51aa4a525a5ebca4097b	1	0	\\x000000010000000000800003c897586d614c1456a4fac9cf0cb4a635a4b5445986d1e83967f9ac28f5ee897f32d3a44bdab542667566943f188fd88f15f41d83ce12df1b1c123e9b764d35b8b1bc0f7d1503d9e022fd7b1d6bc489f4900bd135ac777f176fa6fa733ffa3a2478e90e3055fc83c1dae09a16ae2d73851b94e84fe69622d6c1372ef4d3d5b14d010001	\\x457c1e15e3d1bd84f94adb100fe114ca2f63fb402a6e14c161afd394c7f2422b2045eb8fff0b9aaa26dade0b22008a2e46aa4b170b1964328c4a5d944d1b0706	1685953985000000	1686558785000000	1749630785000000	1844238785000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
168	\\xae4d9dd418c2efecbba24e76923b6dc28d37bbcc64038fcbd785ed128a11cf706586e76c4b2cf4ee77adca1423df0e9b7529ad4ea9bbc01929c0c44818a0cb12	1	0	\\x000000010000000000800003f3961f6668faf3184dd7802d257a12c98f9bce6b98f240bf24c2a1b917c894befb9a77562aad5be893789bcfb8defa810956c4a1cdab79d2c55b2451806027784fd407f5592b5edce6800c883cb119c2e0bd6b4eb656b92a09b50e888fb833a8ce73fa59d30e9233a5db882d31806d12d22fc21faa2277620b8efc83d05594c3010001	\\xdc2da6c25023639a6e39fa973fd6cc8c0d48645e3e5c3ef59006b2e8542e83ce3662c3c4d72a110a617f3e1e80d2843fd5fbf46eb2883bac78a0e3985084b90a	1675677485000000	1676282285000000	1739354285000000	1833962285000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
169	\\xb5c5c966edc7988bb6391c42bae2037254fcbc147840b2af7ddbfe3e5a58dd042f2daab16ff8bea05045eed5f916d0ce720f7be489548b81ceb8afa1ff57bf61	1	0	\\x0000000100000000008000039e3d753c611e95432e555508459f2801ed8b0b6af8e6e189fd606fbc40fd7eeca40986e953c28f05bb7556ace62fd8b8a2db7fec2d2780124e760578b603844531021026fc9cf7f0f4d00f42dd4c4956dbd0ff6c529727db5dbc14f0214507f5065b360d71831f7e94f62e227a9aac9d688ee68b170d5a8feeec75ecc62659af010001	\\xe389b3383c2d2c3021a009865135ab4007f73427a7ab5726b206641cd67c42c9186158760b6aee119925302d56f39da3169a3ed4362873969ec2e5dbd007ce07	1676886485000000	1677491285000000	1740563285000000	1835171285000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
170	\\xb50da0e7cfa942400aafe2b4eff526b8c0027b5fcfc6ed3e468653343b5d6da1a80dd841d20c2a4db376d259be3dbd443b9b0d39f8f6b0d567f63bc619d70e1e	1	0	\\x000000010000000000800003b0285665299cfb3a9a6637022896baff5be6433a62fd56564dbbb1b2c6f30311bc90d432982638dff0c276224012ffd026c58154335a647d68e16155273618809462eb33e1b5967dc4079a5a8ad17679d67ca92f66e13f5a727d12ac226be011be4c40f0a5361ecfbb1d41dfa7620ad034e438a1ac9981313f6304d2b7041fcf010001	\\x8ef77d9aadcdac51d1a19404d7d077544b9fb8be509f6e0bb9f18e16475ec5914729849bf2c0d905735d70259796d9d363316e404625e95dccc7639f9b539401	1658751485000000	1659356285000000	1722428285000000	1817036285000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
171	\\xba8dbda2641f0afe00d4c2b04f0c239545ecd0b687c1ecff4d3670ec6c41ffe4e26d1f18a6d6a18eabb39f89dd8eb662ebf935149ee1b289daa0decaed2b207f	1	0	\\x000000010000000000800003b8a7da6a03cc2b21cd283f6a24d05ab5f11ee99fae2c5917e51d28f2d7518a4b602e971d48b050ba087f0c69f5cd6283fa5fa900703504210f46026ca38370c2fde858274b613fb88ba637bbae3aab4acc63c8555225915384e7423b63150c6d17f194ebbd6e34856ca80f82908b7519e0026327bf2c89ae705a8c2778074a13010001	\\xa17892122fe956925cd5449516e6da27e12bd6d25fbbd32ade2d6e1d89caf8cdd45533766a2b0c1d29301c9dc08922696f8e388395824cd04ab67cba09745f0c	1655728985000000	1656333785000000	1719405785000000	1814013785000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
172	\\xba89cc9d7818154aa5437ad60c32883526c56fd98670b024472fb2d35f0bfab55d1f33d9ac5f569b6536484a5f29992e0dac39a1367be5e9a5d030b66c29da23	1	0	\\x000000010000000000800003e65b7ec19f5448192e2f3bad800c7fd03ffca470d9664235d9fd0a2b27920e597a8c3ca0690a4251d277340f970f28fc5a94bc496531dcf998266b9a892a179f2fe121f7e21cf1ab7fee0996596c25785148d2fec4972341c68bdc00d745b2ee33e5b566c8b0409c2af8d384ab615b2d6aa1a442a2842fd48bcfead8896f14c9010001	\\x401a93c3053bd91f39f45a4277ee7b0c6325d6f99a39c39fdbe040184ff9daae54dbacacec18e3f71b342ee905c49b37ca08879acfbdedefa0dc962f9602bc01	1681117985000000	1681722785000000	1744794785000000	1839402785000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
173	\\xbba9b55eb2d750be43cdb92d688e8e9210b679d74dc8128d8c81ad4fca592ea3cd31772e72f746997005aac34a03603e687eb5c7a4a3731019b98db5f92797c7	1	0	\\x000000010000000000800003c483875496e8f9a0deeb47d90c9c54ad81c07eda8a46923bd2f724ddea900bb324a0e0ec1e59bcc58d69c22e5d9b65e83ec648155c2af78ae0d2ff1760549b533ece344b50838d94d023b0ec3375d5da4b09f34cf3999679df8b9afbf972a4a6dff4ed1a696a515b6b47d2e4eb7d8f3a4bdee9ac04beb2aeee6cda1c7eb4fd99010001	\\x37b66817a572a7ce5e01849c1008d4f18b1ac1a8041482ebcec322cad96047538514fbd7843a0d8f9399e55cd0caa178caef7c6f3794281e3292b5f5dd9a8a0b	1658146985000000	1658751785000000	1721823785000000	1816431785000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
174	\\xc1e1adab003a107f6d74fb17339e3b42e8f18acbcf15c3d291974f173f00a211323723448c9c84e430c83ff1dc9a51c5df4b30e83cf9b4c7e0bd1515cf4d6950	1	0	\\x000000010000000000800003b780abf2dc35ac855c0b338a593daaa7701463e57df45393b6d8f153d1c7fd496bd74c02521073b2c264f21ff780a7d30f55d7abbf7610f6e3820a457c6586c3c296825d6a3e6e0d6df2a8561b16c104c9ed23d3da3b7fa9069a66988a29043b2a03b68c3551746b25b1d871278d43c90c1c3f769c3bad215b9c9fdb95f8ff0b010001	\\xfb7bde96cc4e6a5dd19430316c5307cccf9d32e9a44c486085336e59ea46a00dac8fddde255ffd8d84aea50056a4901d3970047a0cc5d89426c3c6dd9c93f102	1685349485000000	1685954285000000	1749026285000000	1843634285000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
175	\\xc175cbc5e1bdcb92f9ebd0480f8640eb6dd32ef014c668b22e08eb16022f24012db2be18cef38bceed97d9b8643430d90115fe997c72f679d3ece2cb9345af30	1	0	\\x000000010000000000800003cecd7ed71734730f53fa11ce85cf0c9e5806de57c20069802e552cc5ad5e5338e78fbf709a16026ba8220d1905d860452a73c3ea26d3935577846b2b5a6306f203620c96c3a2fdfbe96b2a5e0fbd0d4f004a0221dd362e36d318315d9fcec55c936e6e5866a1ea31944339517da6538387bf1d2837971699daeda5324f8dd1a9010001	\\x142aba5de5b471db59720b8f280eb1110432890ecfdbc189c69122cf6061d60210fc0f80475ee116f0dbfc73ab3a9470d55bf74a5111e8c02d03a1e6c99c0c0e	1668423485000000	1669028285000000	1732100285000000	1826708285000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
176	\\xc4a5c29328bc6a2b2f30802a81d918104ff90e99862e195520795f9ff34542f599c1c9b089b635db16278a3f4402ff2db2752ad30a417463643ce09ff9b34185	1	0	\\x000000010000000000800003ad0175c75f1f0016a4bd7a1c4a8712c7a00d3d17a39dc2ad5d7df9281f77bde223f393f2676f45b918731026e6ad02777a3285bc9128f75a2a543d7c63b2efaedfbbcd0b79cb8e25ec7f6dd6135d81a6150775c850a8c1fdc76012620b6503ba2a64636040e7ecfaa1a4f5c011b5b33bf230f02e3937f2be5896bb1353474707010001	\\xfdcec77592e7a5d328c5b720191140761e433b44e9c2cf810056ec1cb132ee7545a80dc3d8e6213877cd1961113fbf6a50d9eba9b33ee27f259209a91d90e90e	1666005485000000	1666610285000000	1729682285000000	1824290285000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
177	\\xc7b9f042831e64d712522d30ffa48e45a9dd9e39af07f800562e348da968a50b775e823b753f5a84d92548fc3e9f12939158f1fb711dc6fac03f416c549f94ac	1	0	\\x000000010000000000800003d118e214fd72b4b82235dac0d21b065126a96766bf3bc49efc6cb0b47755c286327fcad4117312e5314cc136c8eb1fb98ecd2b68ef5867d985138af99855b1b930e184ba36abf000107c6c2c2310251da6445ef2fc096e7a1a84a0f759c4a4677a4a123850864f57adbf12ad1855fe0fbce8eb583039302be8b69844c16cc4bd010001	\\xe9d266878a0946c196d9cb8183d4559912a98a54d03f8b71d7dde27c8419a44515c2dff98471b7ce04d0a5a4168fe637d40fc0fae1e7813cec891f1625a2590b	1655728985000000	1656333785000000	1719405785000000	1814013785000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
178	\\xc8512212bc1f38b02ef5b134f13d7e3b68330bf06ec0725d15cfe5297ea521f9d9c8407113ee03eb274729ad8ec2adbcd8575ec03209a86f270c0936c0b793f4	1	0	\\x000000010000000000800003dabb9e00d1d2fd97ea10eee56b5483f08b4c2cf682e44befdb0ee2e957522c8fa4bd94c0877e67db50006e20bcdbb5bd3513ad950ff77598f9ba4483fce2c385f470e1e449531ed718b8a38562849785a1b6c02a52535da1af4ef132434c38f23572ae0499445fb5250c538973c0006d0662c3212785f19e004b29158ceb378d010001	\\x1b86f0f000987afd8920323016c6706ff80b7e93b0d0dd244e9737c403710e7f9f95d4edc4c752e85f1c33be725ac45d8d557c2b5a9610a8949548da4ba17102	1669027985000000	1669632785000000	1732704785000000	1827312785000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
179	\\xc8e5666b77c3b51b9982d7e1526ae14571b01153a6ee3a67b986ca0f7723e715fab5b969f70046135f20b73fe893f6c0b141e31ccede02ca3d649466ce04748c	1	0	\\x000000010000000000800003c422667f6639e97425d7cdb5121181c4e863424fd3fb3e250da95c6e9fae348dc2a469eeca97e153e0f5abe58ff2b224ec91c549b8b3b524ba37092f746e869f821c836a5e091e2626ce0ca1e82cd4c982d2167c55b1f03ca81d9fe23a6e8d1afbdccc3f3edbf5bce741cf930c90f969a9f97239597bd85583303a474ff857db010001	\\xbc422767be61c5bff4a11e976dc97f9baeff0f3fd41b0ca08274646f913ed4ba2d8d6413bb7ef312d2418bb94438ed22e98089f0a3a9e51c1818b5c25963ef0f	1667818985000000	1668423785000000	1731495785000000	1826103785000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
180	\\xca8db043638711cbe00ee896339512d93ed7e114f58c9683fe9dd5a5627de01858c990f9c0a817c9a1fffd001fa77582b795078229eae853888dbf32629e639e	1	0	\\x000000010000000000800003dd93b764bc3eb434105905453fd2c79e0c6ea220321d4f619bc26cd4f877b8c4021d8e78fae450fd444effc02c31117801405fca762e55febec6837d74a06e7229bda6971c6020e1982c3d0cfa188ab394819a4bc3db5f5ce0cc10f89076fd5427046ff603def9ddabc1118505a3e211a1450ac52987efddf0b2f462d62f78df010001	\\x95d82954ff7ee7ccbf0b84a82dfc90873146dc09a33efb7b14f63251743e60df46d2ac0eb5b45e54a9a76a43f07cf13a4618bc16ec835e68b9673a8825e0ea07	1681722485000000	1682327285000000	1745399285000000	1840007285000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
181	\\xcf59706099de3c31275f01e268e24ebfe234ce8b8db2603a194a8195e3db844eaf4291b91bfbf4a2129ca0e8b1ef526635c513e9b94b54ac1ce2679ea1eeb6c1	1	0	\\x000000010000000000800003b2217165dda166b7940d7240137004332b6f09d7ca05f4ffc33aded0b83758b2375773983254e799bc568891f77b5b0b263d7ab0b9fcd7a1c13c7a931988624ed5b149c7cf3a98a7664ae0d467ed7c6d3c96c2e3caa969e97d9e3843e5a196390f5e3207e21a0881061c2d32465c48860b23edae45c22b2ecf7a204b70f30731010001	\\xf3e33ef815ad0f3cabd2e0b610c0d4792b6dabf3683fbedfd5e1f8ff26fa7b56bf6283b68524f1d87003af45c11d9db37191a01297cf63633d946a41cab24003	1684744985000000	1685349785000000	1748421785000000	1843029785000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
182	\\xd909f85f7e50760676117634a3dd374ba1b9a968ee956f7d1bb3c7f5f423688132a4e210ef2b150247299166673247f4db8b3a98e28070433e772af8e2a133ea	1	0	\\x000000010000000000800003a4cc9a47b4bd9b8f5fddc1ef796ea9a964734f8139997ace331b4fc79a46e849200efda3887965214110e7c2990bf345056d9ad597eab162f4385981c7371b34ea61b9a3e3440bce9f2b42cebdd5434506617d7b94608e262e2760da9aa6edeaef948ca0fb72042db641f47262b372a4cdff2865176276c4f2a34c3bd4b4ffa1010001	\\x39ffb6c71f6c40631778bbb2c2bc6394e1d64d55edc14bf7f066dff9fda392dc851caa7b3ab7b8e355ef4bee2b1fb1849efb05b4dcd248b9109f28dd2f35c302	1667818985000000	1668423785000000	1731495785000000	1826103785000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
183	\\xd91d2db94cafcc493b40822b6b4a570b7eedbb78670f42e097a8d3d0094e46753d3a41e99b6130a18fa29196ce464dfdc4a7f3e78899f8459f3346c9117469a7	1	0	\\x000000010000000000800003bd609a329e2a1f500c92c4cc78a66eba9a699ceacf8167e271e11e930fd98cf6b5258bbd2a5ed4839045ab38566a8e7def2e52135a67bff386060530f652a510e76090019034bddf9238af2f78ada9639fb41715750af7b754e2db2e3bac288f24f0b13e5d81109336fc44e6cda98e9e0f6c24e903d5b9e297504e3a66b2f013010001	\\x0eeca32bfdfaad57227212b821f9af19b4aa7a289065518d99c84526bc454312ec24f54bf162224d67af06b793797341a9484206320b2457b3245575eae00603	1666609985000000	1667214785000000	1730286785000000	1824894785000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
184	\\xde157533cf64312ab5754bbb050e270e07c86e6999e767e65f3f2d3b7cdbaf8de0dc464c1c912fe4f610732749b5c181c23c2368dcd2261a2af1da7c7486860e	1	0	\\x000000010000000000800003d73deb69927dbaf8f26aa88201a973cd674e8cabb60b46678d631d5904523e02765126c36caf7ed2ad80e084b8ea9671fa2fcd1450c9a8e135f30f48cbbc465117488307d91e6128ef2abce1dc615528d19a7e214727f6db0ff96583226d98ab863643ee808c5998d00b7d883714a0157c5f86c17e59d52105be5a78c276d2a9010001	\\x0c7378097b0767cc163922df5fa78fdc6e8fb6d6cfad4d497b8a5ceb554b3edbf0937ca8d6e620c344553321666d7d26b9c962be58313abbe832e95e755c7708	1659960485000000	1660565285000000	1723637285000000	1818245285000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
185	\\xe055b90f9dd4aed814bf660134534dd7067ed1c79e36dc15b6f314291ac22590735f51e2d799521d10efabf46004d955b40d34c4a881e52d2b2e95a34b60a65d	1	0	\\x000000010000000000800003dc327e3db41f2224a6724e087abb259c0ee38f0148b702af3da18dae728513b9102383d2e7597b326d1211611a5791e7bae334844bfab12b0aa74718404d893b331fbd12ce8febf290e32f867dc294591fda9ecc4abaf7c01001549a49de76cca845f2c45042718daf73b0a44095475c05546c37c2a422f28cd3c17cc2eed9d9010001	\\x8e435fa71d942924e243eb662c89ef8256c0d3812425fad2e9982caada58853e45276daa7ad6d87a91c479ac18900c8da4b9301984f5ada5788c2ed4f8990209	1683535985000000	1684140785000000	1747212785000000	1841820785000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
186	\\xe431aea946ffc880ec64cb05575df1de95d78d1bc8b3f1ee9776c7d79f339fdcc1be21b4456a6112d20acc8a2d69590f5ff964569b910bc301fb1c9423f0665f	1	0	\\x000000010000000000800003d055777c29681e9d9e2e447d74fd2cc2754c6841419d025ccf6f3da7b2f98aa66b1835fd270a230fc298a64b1de0987f68eb4bf6b0dfe7ea97373459b71f3bfc624443b80b3a311e55df07e9dfa11736b519f6d176685663b0b880102abfbd973058762abe6cf7b3be41bd2a382eb58ffecde0a6da21c8275dc8d575a1958621010001	\\xe9d75030ab96e4a8b59a6203af426eeb29ba71d31f7272126a02d3b7f55aae9dc3f92f219dc8c0a97b4746864674186ae084580e5b5c36cd6a3bb8683fceb00f	1668423485000000	1669028285000000	1732100285000000	1826708285000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
187	\\xe5016c4b5f1284e1975205092263b9a7a3eee2da030efdb8ab23e752e4015c4d36f085da1043c2378a393f699fba5d985a62286b3585c44a0557eb836b41dde6	1	0	\\x000000010000000000800003acb061673afb09edf42dcedb12b98b30a1c1c42caca02651b9b20b1d282b854cc71bde7c3ca905daccc5d5bd1cfb2d7192f33254f17d03aac7a0b2e26884555d1f69fbed24f56622904808b194074fdcae16945c0ca1c7429a4d162f815c3e9884e0f32746f99cc7e575d1fdda500952490ab16e4abb78ba0c09a4f31575c9d3010001	\\x5dd6bfcefc6c81764deb8c5fd3a09464c8fb175a4c120fdf28eef48998f595ae64d9f08466728a11496cfc6e173aa7c043ddfbf1e4585ee6b6525c3b9fdc6800	1664796485000000	1665401285000000	1728473285000000	1823081285000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
188	\\xe589c58a5e203fce57cf541474661f74d7415d3fd81a9af2360ead8a75b6965711f9f73a5b78c0c7e797e753340d0c86fada6b31b490251007577237dd49755c	1	0	\\x000000010000000000800003c86d7679de57711d0bbf894fb2646b1bc92c23c3208f4c43c9680ebb1bc4b50215c6ac4fc6b658d8b3ea679f986fa08ba26ce44420d0707b9c1e1df23ed3d9a5725e492726280660e9ac3c129f059c8e9608adda48e1b2f9553d68c383ad7624a18c259b1209e9bfa4f3e4b60c5d8944b19f33ce72408e319e4d1cc32c96636d010001	\\x7df96a5c978ffddced480ab39f84bd194a49cce15f973ef837c662a8ff5da2fc7f3ebe4164fd62cb5b622c3b66be7c09cc78fc77508d61608ea03e881059650c	1655728985000000	1656333785000000	1719405785000000	1814013785000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
189	\\xe7dd96359f7ed3ee10eeefa3550737bfd06c93d7da72bb2e02041ee7b93888059eaaf9900f391ea19c6972ecc78dd5d223ee5e2cb21d7c03b8ca83132b6e5144	1	0	\\x000000010000000000800003ab0355ea4fe91a59ffbd5f45b17644b15d59286b7faee7acf1424b5dafed5737bc730a2a25322a2b258cea3d0a990014f5a9e79340b1c974df35c7af44d904fdb164f0e700edd7673a7f178058752af54255952e97103de99a2d7ad90c644b4b96d1331c8a4d96652aa92adbd52512c945f499cf649939b47704d0c5dfffb6e7010001	\\x9d6484f7e294855e4b02b0141e97d10250cd963b831749d381b90c3e58b7574acf2d580884f692ae1ca4a776b21e351f873e5f58b699a72e5b31ed5ed80ade0d	1660564985000000	1661169785000000	1724241785000000	1818849785000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
190	\\xe799368e4ee44c613ed9ceb24024f7cb708af5ba79a2014ce9a4f53a68eb2157f828a61e0517a9051cb72f7afb660bc5ffb9b3c4d50613bfb82024b898fa4227	1	0	\\x000000010000000000800003acad51603640b84ab747079d0f438ed539eca1f530e79384d98b3d1cd94ff024614a2f95a42f9862b10cf13236d0db66657e0426c7ff83f583dd8568a48336fc09271a983b71de4f077debac3ec9675510907fb2122a2ee63c9013adc7cbf757856a09e8428b4f2467e6cb9128e1b6dc43a94141f98f5c20e5cf9e6dd266b5f9010001	\\xaf7f2da4f130973cb7ac412a621b4b566e82b965ad8a13dd03077e82f375cac26eda755ea1e92ade50fcfdac83ca5ad3818987a89b64b7f71a5740202bf20a0a	1664796485000000	1665401285000000	1728473285000000	1823081285000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
191	\\xe849016b41f1b88811d73b8b642ef8a17f2d1eb00eb55147cbf97da77323da1afa4c58a2b2f4d56fc8661c4479357dc7eb1cb157f3dfbd675726ee5dd04c7d9f	1	0	\\x000000010000000000800003a3596b693c4ae92cde2ab8733e8d65ef00555737dbbaa6def3fc60cfdc9e95be3a3b768d8c6cf84771a79e25b6f6319e96a97ba68014a7778d1a6f5568e53c6003eb43b3165831cbe16a02a6fdc081722317b8b2136d8a17130ff36774e7607955cfc035dcc731bc7065d0ca5cc732fc07ab781c8f07d80339ebc8086aa2f9db010001	\\xb31af1f5e6e020a4c0d94d0b43c04de5dc12b3fa69d157c02a0b1905fa6fccc3013fb9c7243d875e443da17a82087d6b2b82075a1a6665bef86a895a525f9e05	1658146985000000	1658751785000000	1721823785000000	1816431785000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
192	\\xe8519f4ea122849d371abfda61d188bbb05d15586386dfa605a52eb26eeb9a9b53816938b9cc6bc47110a36f5e190affff2fdd095f822232127bad1ba64896c0	1	0	\\x000000010000000000800003bd866c29bb213e2fc1f699d2834a3bd77e69783c32286649186f734153424d296998c024f2bab0e83867b678323e384733aa4a04685b32ec9075ab4b547565141d24ebe30d1405caeba961113754d51b6490c1596a7707260b3ece160d848d9b7d4911274b29b2fd099a4894f70fa8544d1bfada7bd8c4ccb0c7a6c1f7c4a843010001	\\x7757de5978e741a72e32e9c24d238d596e7021666256cd36e7dc151adeed7c64d00b62f9426148958b1481ae4d76fb41d7304a1097ab668622121e11ac286d08	1669027985000000	1669632785000000	1732704785000000	1827312785000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
193	\\xe9e1aa55673f7a75d2933c2ecf4748870bad7c21ebce4f46fecbd903dff194a66915ec78c1dccdeafccce0fba7f1ff13cb288d066fe9231e60d4ac85c4c006d1	1	0	\\x000000010000000000800003ec4fb08477340eb23b911fa79c75fc98a275c36c35a8e43645771d409e711843c467955dd01564f9d08c29668c71423d165cd2cde71a4006bd4da452bc3ae2fc11bb189cee985a4e34f475c8b300504011331e04a000aeb637056c471834e06325c3a7bc79cc31581846ca9c3a20c34d6a23c0e3078ddbf12193ef83059f859d010001	\\x3fb7c61c6f2bf883d102f37e1ef691c4c0cb2fabf70192594ffc9dff221f535eee235d04841abecdbcd92f822c579ead0edd45304823275dab19df9e4d1d3306	1675072985000000	1675677785000000	1738749785000000	1833357785000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
194	\\xea7df112bea012fdd68d128e63e58433ace42d9fa88156b5adb9c32da375790b864c5909c3177d5651d6b9cbafe0f82fb09f739e47bf55c2ef707e56c6d26af4	1	0	\\x000000010000000000800003dd3f10cfd6f7426d73b5f21ffd5da72e9b5163e615b8b9559baba408798e52efe1576f9201cf8b4c1971f7ff72c2bd5055d800ab61a9d600d5e87c61019b7127e51d6c648841dca024218a9d5f7a99f1016db5dfd40f271dbcd2dc9a78c6bc4170b8a95ddd93424b0d98e92df045d202cebac0edfe9e1005c89ec54b4ba2a133010001	\\x4008de86a39598964f60a6ebe7422381ee6280d03b016235d483ff310304e76bf8763be88d1cf9fdb79ea0139b6a0a9a406b1b754ba3b8e3c9d522f618f14c04	1675677485000000	1676282285000000	1739354285000000	1833962285000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
195	\\xed61f8b648db5f3b6f4c8a369ad216044eadfbecfd60e7eee8ed361665d588e5e878e2abe89a9d74580b11ccf521b1edaa027178a08cecc55d9d79ceeec8479f	1	0	\\x000000010000000000800003c9607e4d2095d3950c70218777990a7877c0a90447b7e7fc51655e81cf6fb72ffb0f83b472214b8a725d2f6abb0d323a42d263da02bcf2cc8c7da2fa48ea34b35d475c3264e01a0de86f779c2c84584e5937826ad3f61b17823338203b3b384727ccc411a1eee2e44f5340c7a82350220fb63fffa87c777dc8713953fddf2305010001	\\x38ce674f44bd6271ab25949f8ad379b452ba92f96b40624246d8b0475cd4c0fef5bc63339630aa7155ba735f22a8534c9e4f182c8deccdd8b4d2a3b13dc2e508	1682931485000000	1683536285000000	1746608285000000	1841216285000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
196	\\xedd9bcebcdd2e23a319aee867422c3a2fb93d407af1c4cebd334015f7feeb2918e7d2be73d8c77a4bd1cbf28625ae52e75b503893bc1264d2285a1719396d74a	1	0	\\x000000010000000000800003c50c442f9f3cdf248701be5cc0a28315265e5a3e6a5932e6580cbf664748502e4b23c43f9ece4a98ae923af50de34938396d028e29f9d89ea908a0fea168254b1e32ac358b5a9206e83bf4c75ee9becdc49c7aecb42a6d51718e48e29b1a6e243195d0f3b1e80524f2505b343f0f9b321f38ea912ad6d150cebc58a26887f323010001	\\xf95d43bc16911b5b54f028d278d31914c556aeacadf3f4dc5d94b328231fd5edc9c813fb675f93eae8991ac2d73ad48c5b266335d99fe1f0fbc692f5c7a4380a	1656937985000000	1657542785000000	1720614785000000	1815222785000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
197	\\xf0896d3d8fc76c823c4e3357525d923b974100eadb53a8ebf5fa9139a80aaf1e2aeb03c375fea8eb9619010701d02a9e88c17e999e3639880050d7f3d87b8f1c	1	0	\\x0000000100000000008000039a9d989a2c8e1f9f76fc78e01022a5d0db46c500347403ea33f10403bc6a7528d0e4e929ee86b4ef95ec57683709b3a39ed04114881175b50e866b5079d9cd652eb5afdea2f7b30ba9e038c6f6b7f922ad1998edba77a7494a553294655ea136bad548468848114fa2e6ed999e560c1561b0196eea22947c06d03c817007927b010001	\\xa78f7a784245ba09cffdf35005b5f44760ef00c65cf18e4e722aa077eb32832dbf00f54185bd4e42d0da59481160816a854284b7102ddc9472f02551757a440e	1681722485000000	1682327285000000	1745399285000000	1840007285000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
198	\\xf1d5ecd84744898ff483da4da4aab6ee363bf3c955190625476767d63a500e4762fb69c7a1bafee656b4aa031539aaa4f6ca67c57ccb40460dc38fa4ce4bef99	1	0	\\x000000010000000000800003e31d5bb0b78b021ec109c096e8153083cf913b4ab61eaa70ccbeb48f616b64b513030c9f0a709dd952a9569ce1c2ceba8a7d1016b97ddcbc12be6b57401a8eb2a2a52a6f612b162253d1acf06a7b8feb1aa3aef0cab637c882ad1e9a74ead6cbd9f904d17c121ea1aca2c09d0fac2e16825b177837587e179393dad939343e9f010001	\\x339b66270e120e9059ee0778f1727edc72ae1ff5659405cd0446bbd6bfc656f5bc2f9689de18d4a98ddcc980d02702bc28853f753a289298e7864ba51dc5000f	1673863985000000	1674468785000000	1737540785000000	1832148785000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
199	\\xf4318149dc7bb6991b8d64d83371b413f2d3de9bcb549c0c9ca803558e0005db8a06f4808444be8fecdf6a51d5b7b62d77ea84d1a6fd2580a8ba5d6a8666853f	1	0	\\x000000010000000000800003b9474739a4e4fdd74cb23c01433e20e3c96eed0dbc2c701d24b0d7f107dab2a2e7eb0e875ba7e3ecdff557935f085b9736c33182eb0d59c33c7bf0ed3ef278f7211f61c81a677ab120447c8991ac131c57efcbba41613a07271a894b103e9e7ba323d08cab461526ab6b300f1ab28645a98091727a46f42a50964a1e2f7fd8b5010001	\\xc3fca422af8e17b87b1673d492c43431dd22f01af2c3954b81f123416f726354dc8488f37da3f20f1e60a18b3a72ad8476ebfdf1ca1b19077883d74a7e2b110e	1656937985000000	1657542785000000	1720614785000000	1815222785000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
200	\\xf5611d4a9dcb874140d149da52fd4e6e69c8c2b92c4775b2d68b874f59a8bf0e4a8d2a620f53519d832c0a1c4fd1929b8ffb225c3a86ef658f845173be04a6da	1	0	\\x000000010000000000800003f52d220367bd3cb5f30af07c199a3e049e8862f65ca59d61caa51ef69ed2bf6d9e0bf1ec4016f322eee244eda49a678a2971bde637b536fd8e387a48a6f0892eb51d0978e24de80bf27781b863e128e153b1fad5c882e951f62b534eb2e988e29793b9d8c5c84509e40caa99eb67f65928bbfb323d2575979fc35b6f4a0e3c81010001	\\xc8252ce41d583ff1c8ed633fe19aaedd62080ccc122360d256f9a63d61a86d224381d845d47acf3ca49c932b0010b19e38e0d5889cdd2627cbdb6d5a3782d007	1669027985000000	1669632785000000	1732704785000000	1827312785000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
201	\\xf9f56758e1d9d1d5ac96e83569b715d97a848c3bd3c916fbd72db5d8794b1d9f68c32308e6e045fcc2d5ae506eb1d1ff6c4a93a20d9b7ac68f7c7cc0de8f8247	1	0	\\x000000010000000000800003c08670f7a91c5670911042c92381137498f23fa203583b46942ad10b92fb25953b52c59859f5ad32a642e7d9f193ccbbdd45987b08e34635384da612476d1e5de96d0ac9ac1c2e6cfe275650ed9c8be7355932b444f3f0e36d59ed263381c70fb3f4d6cec9af859e5e04dd24f02c585c92c5f6ec3d6aa3bf80b67ab37a61f4b7010001	\\xf4cdad1aa165a59e611e20207ca14649751bde0e597896bd9d1154d5770412a4cb8f839bf890bc69426a131f61c0792fad937f12c42ce0877214ebd96e806006	1684744985000000	1685349785000000	1748421785000000	1843029785000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
202	\\xfb79630df7b2da13a246579b9b10e60a345fd0955f1813e96f9d080f6fadddb474771498df5aa1d137850b14ee8f67ca8eaf60b00283cf72bfca7f9ac76931a6	1	0	\\x000000010000000000800003e71bc2853f7c607dd975174895d9ee9088f0384ba4e710c05b750b332fb3ab2e9d908b950da992f2590411f34d9bb8280e0c59fa8571c82026ea671afac8184efe5253bdb78dcab8830a0f7c070dc797fb1c9fb890b6b01c03cbccbd170e5cf3d147bcbb74b6531dd1bce1dfcb5ce5b3d7dc99c18d62bcac4793c97cc7db7b99010001	\\x00230c182a2899e2c8f4c4950c0e3f0f0e5fe3ea9d0bd71e0d2770c1778a2f0bd4de26329f6b6e40ae6d7e540d3a9663e1e60383c930cb425e9febbc12baa303	1682931485000000	1683536285000000	1746608285000000	1841216285000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
203	\\xfc6133dc64012797a768b9e5fdf0784f5e9d56fee13942ef2678556bd9eda70d812ec53e3dbdb4f9279bb2899c4d82dc25e56d4fc4ea8e54aca81e6f996cbb0e	1	0	\\x000000010000000000800003eb7815b83fb453e74cc502dd6610993a1ca7a7a44cc4c115990d3e23b3424009f1801d32c12f0b9d04aa881a44e99ab71895065ec4a7e6477eecd7fe7e1a36d0758f827dc749809d69c69e82ebb532adfd5392ba659b0c60bb2eea3c9a6da909865f0ccafbe4b22408a6abde604573a3b566bca8ee5a28ecb12a3cdb0ad8b8e3010001	\\x06d7627a972b9890c4d8ebd6be0baa830ae4298d509151ad2b9ef866b222f58b2e37d3a3f793bf7288fae64f90ab2edfb6ca3ed3e26327abe221d7903fb80604	1685349485000000	1685954285000000	1749026285000000	1843634285000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
204	\\xfd41ccc5a5f8d7479199499e98e20b40e3eb4789b82d83d113254fca9fec8d01f273c28cd561487523fc2980cdea74f1913e271d3fb21121b8a144e3459e7b31	1	0	\\x000000010000000000800003e0cc725486a893c1c593ad963210a6586a3804f7a4e8446aa365e3ea02247c2971b5fe6d5eff8ffe0f36a34194acf9d3121196fd39efa78f30170a56dcb5580ba2fbb473403f7cba7ad8895edd37aeba7ceb888ac91c6121bd8884ae20b31a000cf6491fcbb1b8279f7f6506c57d6ca287d706202e9bbc439cc5117479c0b12f010001	\\x7494913423dfaf05c65b00eb98bc2b4c9088a61ad14310a997b2924325161cf6881c3e76ec830e31a793696e79507e9202eb72d74fee39d54e2f8e43af1e0f0e	1662982985000000	1663587785000000	1726659785000000	1821267785000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
205	\\xfd1141da333134bb638ee501710aa04de5c4e7186d22fc0efa664e361eda832f242a667fdbf921e28d4a84f182882c763e15b55cc31fb8e97704d1c85f989487	1	0	\\x000000010000000000800003e4941782160020e83d893c022c19bcb0b37d81d8b726f82018af9f7003e7bd1f2829e7cca11a194a16a6a1da5f170bb7bb44585e0014db73531d5b70c11e5ee3b8cc74a36c9063e2d00931a9097c9cd42ff437bda602cec9a9532e097ade555624d3a1f77b71b2644c0a6a1a2085d5cf6d534b9c25a0448a979bdc34aa57eafb010001	\\x4d208c3c00022dde9c6fc99ab14c03273b62cd41587d0aee503f94bbcca37b0cd9f6fac11578ba04f0178df54a518a3331e3194f529199bcdc6d357beae6ac0e	1662982985000000	1663587785000000	1726659785000000	1821267785000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
206	\\xfe0dc7ebd498d9a544556efcdd83889d9ca7fc4ba81cb94e17e88af06bfe305766d8024ff4b88f313a37fe566d343096736e7f1269fda5ca9da1d1a0194b581e	1	0	\\x000000010000000000800003ba3b21820e5e5f178dbb4ed9fb36de8fd6ce06b531452ca56aec5f8863aa95a118bc54fbd9a47fd9f5b4838f3ac35931790ec9892eca3f46cfe0de3ea684c7ef10dda7ab50d16c9d6a1a51146fc23a2aaa24970070f7b036c99c3552e964eeb52efbb4fba52d8fe2b8e47efd731b241bf791c61c4ef8884a61edd2f2b9c4db47010001	\\xedf3a1601703571d5d201f8b0d358a0aa12e73f84156eab0f6c3d5505948449617bb4fcdca437ccee53ead9e61d25125893a7dfa8b50e2b45e3d9fe8978b3202	1676281985000000	1676886785000000	1739958785000000	1834566785000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
207	\\xffa1888bb5238d805ab03591dda61db9b0d58543c3221aa24c44a4ccf7730d44e06821d1e77f1e6271c32621c4a8509e9b3d64304d448dd0bddfcc5fdbd6a100	1	0	\\x000000010000000000800003d94b469181c811b82df2262cf41282893ec23a50ad219610cbb00feff770dc6541eaae292cf0ea89a6c4a35d75e33531aee84c0b1a1ffde68ddf9353a6d10bf74bb1d24df3032c8ee280fe197a74d90658364e0eb8eb3c63c7414257a5b96cd56612ae16980f6c86f78f06a2808415d46e7be03b2d0eaa6d76fb9ca2a0f56b8d010001	\\xcb5d41d25790c52b4a899fcf0699158051dc7a75c87e1f90a96318f52d6488d6ec4ef148cb4c152589cb35a783620a82bd487dfc9c287d2dfd3bd3ff84be1801	1662982985000000	1663587785000000	1726659785000000	1821267785000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
208	\\x03a2b4a653949c3cf9ff7abcd6b3490aadf0ba5659795b458be6fbf10437b6baaa394e1ae739d16907293ece61dda2fdf26ccb0ab7ba2458e6584fd1be668da0	1	0	\\x000000010000000000800003b7c897fb41f2432b7d0258ef464da3f3a914dfc49ec3b458e70965fb4b2f5cc2c40e560aa953c6bebe1db7ce308b669e9bc1352893e72212d22b038a9dafbfc8d66f0bd363319012c7492cc541ba1381bb7ea3f6fc77dd8ba13175f56dfea2619d780261051cc7c54bceb25077d21d14bb41a00b78042231ebcd1ab4f3a179a5010001	\\x10a861cea3d06ee159c6f17fdfc9c664506a181590d14fc5ad4633d0f3ba79557b21553f4e3fb9e6ac51d2e93c2b29f3fa8b37e50fa2f0d94faec14f7f244e03	1679908985000000	1680513785000000	1743585785000000	1838193785000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
209	\\x05ce7da1f3197e4bc2c32f1156814dee9dc290dcf0a5e21026655358aab05fda8572839b7e05be079dd7429d7262c713c7d13a4ef6ff7912e4498f43ff0ed953	1	0	\\x000000010000000000800003e23559118690c49cf375c641f1e8e60a33b5fbda138317c2a7bad73a336a1fbf186ba7224885abdf4f344a41a922407a31905e66f8f3e1512aff8bb493f82543a5bf8f31399ae3b3ba22e548015ea771e1e97c62646c62a2a6f0cff414a800667752c23cf6f97c39746b3248e0fffbc51fe665aa1f46ab41f0d4312ad546dcbb010001	\\xe6a2aa7ac773527527c2322fb73e7e06999e6926fe1fafa8f474b1eb0b83ae523ace894d6485f4d26b438e47e9b9cf33a883961cf61cb402955284b24d76dc08	1658751485000000	1659356285000000	1722428285000000	1817036285000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
210	\\x0e5a6470c04b167e2d3de28233d80fb1b0a6dd99afe4418eac05d519e478ca1d158ffdc6f239e680375007ee10c69db53cf19952d5580c242d1e53964e7680cb	1	0	\\x000000010000000000800003b22c1c7f5641ad4d53b9674dcc1e5ead6523c71c98c12499366f09e536cf318338ff09f860a9cd2d66a889162e1df331fb11db4f86af43624405fd3a54a822a9703d0b5d3efdf5ea0904b075881cc78f1f93fe541e4cac087ad7183d713038401eb6ede6be1a32dd0b15598d8f1efeeaf8026eb054881e015259b7fa2993a9bf010001	\\x9e3fdcc48369ae7aac462d5084cd04b6bbb55778fc9fbf81c42e3c1ecb525a2975e0202ccb2abc393ff120555a390b7c59ef2a9f4aa56eab00473a94a0c43b0c	1682931485000000	1683536285000000	1746608285000000	1841216285000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
211	\\x0eeef2b964576fdd64c69894ba91531d1e169155b4f38dfb102273ffc2989d32fbce2ef0137880029dc2f7211081cd24b01ce7762a6092f17300bc31f158c327	1	0	\\x000000010000000000800003df446a4426ba55fe46c7fc9cfb5235e76827aac4af349a28d15b715bb69d40571bbc4947ae592f662529dfef9f4b05a2f5d6b5c523d11d2683ea5b0623b5f6a5513bd5f758adc665daf6cca7b53ca03ff2d783f6d096488115a5acffefad1263fb9f0abc2aa8c931fcafef1f9b3baeb0a68d896202849c79b738b884e7796ac1010001	\\x4a233daab9f1e7d992d527840647cf9d65f683ee17bd094fda81d866b0fccd3e474eeb98b5d9a5e7025ee2ea5f484a8e9808091c0fd25f7fe4734f3754629b0f	1659355985000000	1659960785000000	1723032785000000	1817640785000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
212	\\x112e787ca4ca4e4c9adad4d91e58bee352f1e1fd03d1870ba80381b94248de96d5c85cd9d9ba73588426a990312e31d37a007eea59ff26f1dd4727828093a04d	1	0	\\x000000010000000000800003d6711bb80e3a48aa3638417ca04fdad5adec743757a73261c7984d95287ef1ec0756f081c12ea9c4dee348bb12b0f55e13263d0a7e7aa0d3d6a6c13345f6f7c08933b2ed0812439e63aea6ac2ae811dff47f10535d434019d87dcca259ef5fca524984dd6da7e6bf4ede877a716cc17904297af54fd0b4cc4631a23b1d750fbf010001	\\xe2682268f6f3aa9fbf3d63d5ee02542373e756c496e9957dcd6cf36a2172651b71a3a45ec80354a18e374363a014591f8a72632ce5245e21a0fc17fbb28fb404	1664796485000000	1665401285000000	1728473285000000	1823081285000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
213	\\x132ad9c87bef45f31846f79da7726ef709e63a9e9e13c76452462dac248ad8a41e264a49da52ca7693df7f533ea7b060d319a9803e2b5ce492db264c382f1688	1	0	\\x000000010000000000800003c903124ccaeeac67cb6313ed8cb0dc61d80490525e5a079c59bdd4bb87162deb4b59d64192d43d1c5e1d60814b3c44376a41cb65c331ab0d226897d5cb487b6cae0715432edf5a341e53c4d725732b35f7dbc7f90065dcef2fd7bf1aca551e3237393aff6cf955ef4e6f4d44ca740ee235ebf2f88de9b8c89caa7a72370b0c5d010001	\\x78d00fa90ce807106d6ba4046475c12c565dfb2f41c535b1a62d95ccda88b6ab6ddd3668a8b4b92d73315de645bc081ae259919b07e1e808528212859753780b	1658146985000000	1658751785000000	1721823785000000	1816431785000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
214	\\x17ea9d877b6923e59271302b95515eed221a24b40cc1278905c512873ca1e271e4ea832e6523bb8320a9ab1b8b1342813881fe317ede279336b296a7c581ad5e	1	0	\\x000000010000000000800003e83000300e77c1826d8a19cbbe617c50c354132528b7a74698c356ac44dc8b0d3c158a8aa91fa127055986ab29fd29a62915d985a70349076872e05dc8fccf7fdeaccdaca188c6b3ab92b315e7f4d2d122c89dedcff19f29f86aa0ff7ebbfc82cffa7714ce1f036c9eafce694926d1cbf3c6a9c83435ff7d3f6555c22252de5b010001	\\x486d02464a4fc43a0e6a79487a5e719c106161414bc43fd06564db32ee1125ff7fd0ef936a211b8b31f7cd5f2b1eed9130882e4d0174ce5cf406538440ebc608	1666005485000000	1666610285000000	1729682285000000	1824290285000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
215	\\x18e6e6d907eee62ab58d3397e9ba8a7702297aad75040e7bfa00ccc0f6ca17f85957af5184c94a8d1a75a5bedb359ed39e7dcb861d1ec1b676753a1f765db0b7	1	0	\\x000000010000000000800003a2b0d3ea3a7bc35b6b123794f0674f143b1059204846dbce7ae13841f5674c21210d7e52738d268b98e6ab0eebeb2f99902a27918657231b83fca2fdcc4b8dda0c33d53a4cba12e14b7feed594b00e447b117035f214298126a2de96082f6ff66ba670b447dfa587545d79e05fb0e4120cd90c79cd28745b0153942c8f3fa0af010001	\\x780d8d4939cf7912780b886c24e332d2174c5a0de8f27817f222e1c058050138538beb19fcdc0730ce32c78fbba3f6694f9015de74f4065f544bce5949dbee01	1678095485000000	1678700285000000	1741772285000000	1836380285000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
216	\\x196a691962612f00ed08abbfb5cabe2f96f829ded1286e2ac46aa2f750203a5ed7f9157fd4206b4c43ab0e17cd33a7b4affe3286785751ce06a78c1200c0e3a9	1	0	\\x000000010000000000800003b7f9dd4fb8229b7d668ba694d78b0e0d975f5ac3ef1cfa23606a9c262d76a7a9ee4a11dedd9eb063295fedfa0e722310e9923839eef40bf05f1b611b527df96723a589e7688a44a53a6313b779c65ee6548858080b8534fe733fc43bb91230e2241c240b1a9287bf3dfcb390405c565a972f910518c02c4d41bb362fb5c43171010001	\\xd280a68fe0e6c2818f08ab875f326951c1f399d5492ff3229a64986d2bb75b95a5a3d5a0a3e0e2ed11d6572739536547c4ffc06b25cf4aef9413c83fa892f806	1677490985000000	1678095785000000	1741167785000000	1835775785000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
217	\\x194e7d0da2a32d562d5f944bfd122f416ec1dba78f0282e4de770d3ed80bb2bb6e21e8a7fa149369632040240aa7c9b6ee5964051de6e8282b13d0b67058d47e	1	0	\\x000000010000000000800003c33fa5cb8dcc04c46dddfa44b9e4d27e8bda80a575811d873958581e9dd66a8fcc56ee1f82b2765cf1a507025b616e3cfafd0eb7072f872b80c311550dd667bb8d8aa2bb9c42f8e82058966c5e81aadef108a02d76e8a7d0d24eee02668e373a9e0287205d01d7665bd15e086296bfe378f31c70da09cd96d0058f1dc5322bad010001	\\x85651bd77de1e47647b2c5f44bcd8dc67c382a1e1d7f56f289aee1170441bacd218ee21264a4c66d00294e613adfaffbb4a3b7066d290e010709457868804001	1659355985000000	1659960785000000	1723032785000000	1817640785000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
218	\\x1b76f4c066756191c8e6804ff20276f27a95a85b89f0a56d9ac097f85adce6a267de4bdd71acc2378c567913cf8ddb7dae407b5e69fe0200a5ef01cdceeb340e	1	0	\\x000000010000000000800003ac81e36d0977943a52aa2b3759f5cd1a959d61db1cdbe2b23351b94eda30c2996c3bde67c3ba7583d14f848a62ecec214d16f9ceae0c000d543c5f4c96b797e5ac59d1e52752926b6dc5a736703f785bb0102fbc9da4a41954108152c113b255ddc2d6546ee3d938052674be1d11614b7b5bf5d9feeb242aad37c08b84f60bf1010001	\\x7eca2606a694c7ad07e2363375190e62c3db66f42ceec0caef46facb9820dcb64c1b0b1633f419a7ad7f6d4d6cd1da58d85155af2794e7af2255a873253f890f	1682326985000000	1682931785000000	1746003785000000	1840611785000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
219	\\x1baeac9de6fd767dbb8f85805ff94e8a3ed2f349360b26c64528f6bd98301939754b1e45a39916355a6f6112abe30e6d3fe54c1a02c6448b33e56f00ac68e95b	1	0	\\x000000010000000000800003d42e6b9c3c07c6ca658d7b6ae6bda3dd6e3e3a29a63b11e18b55aaffe69128fa797998c495bb75d86c3a78c39948c1cf9dfb1f3a3d7acb4dc35189aac518fac9319c6df1a5656a76d7fdfd6e9749fc19a9859d6549d0b0eadac903e4f922515db903d3997fbeaae644d45e92ebcd1f06638c03a794312c8c88117550756f9627010001	\\x08b61ea191e3518991e325d8bd307b431c1d518f744ed0e2455f405b448c18ce4266f3aa8af84d1ee619f784ec00fd0f275cefc65bebacf5a9e259cb26651703	1667818985000000	1668423785000000	1731495785000000	1826103785000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
220	\\x1c72fd64626feacc0c9ef7281e744058cd5f9886ce416127dfc15b72c58bc0c1fd12eeec4d2afd66cee7ddc0d7d185a7fad8cc7d1a8150e69eb5fd06be64629c	1	0	\\x000000010000000000800003c042e91d582d3390c9507194b5a26e313df4b2fbcf189dc21098a55fc24cdad9c7acdadbc015b4293114e6313c10ab742cc8160b715e6e0400c10759fdd3c8d8270dfed3f518b69eb22e123b66de4b065c5b151539cf532547be8bddda5d1b72a6bada879e6a1e848a0cabd9a058cf4ec8668143f86fb6a85505fb9553dfa315010001	\\xe1aa995ca5fbf188c2c2e406ddb72fc9ee426d0c7206b28f1a14f4610e6229c9aa42a53d83a86b911769cba66cea41837880f72c1c50f56af4011bac1eb1a707	1682931485000000	1683536285000000	1746608285000000	1841216285000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
221	\\x1fca5bb7c9d9ee306aa160d349e7b33d2299efd781bf25f83a7fe4d175f651d3b53d36a973c1d165455d5d4dd9148ddd31992e205e3b1162e6594c42b71b946b	1	0	\\x000000010000000000800003a737a0c9526188724e9de06e1ca84d2d78484ab59d0eda71dcdd8016f2bdceb9eca6cd309c4741d34595d41029e55277cb5ac9a9b66680969927eaf1830d6f6ebfb002df3e21c5bc0d216dae16af755037331cd8a8c93078dc8571d7b3d04cbce1717fd1e345ff01cc938d4fb634867b9288a22fa23cbf6917d87df2a0986dfb010001	\\x96d6b67372a1dc1067b85c336d2cda4c6720796832e4a710474e4f4faca273fdd484a5821fab1e15278f439ca1e526091c44ddcc1e1ac486a41d94316bb2c101	1681117985000000	1681722785000000	1744794785000000	1839402785000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
222	\\x2322412443b2ac12183fe61725d4ee9bfc6efe1ad9cf5b569478a40d209a45074a9501c71e9abefd21a353cd3be436581cd3e1d62d625893c2748b3ea709fb6f	1	0	\\x000000010000000000800003c93a3e96bcc114826b9d696b5bc5f975f27085e20a0063fd3e7e50034771e0f0a4fc6b6aaed77a190c39e825fcf7a8528b5a3e33ccff7c0fa2b1c773711d05cb9552ad35086d48a4bd40f50613da7e546f61803eb70d4707f3dd1c42809254124e01bc31eaa41dc25d133305c3217f5769624e1dcee94ccdc278f99a4be702ab010001	\\xc7972893dc80f8af7a8abd2986925b3ff2f823b0152bad310123e82a00c62ebea0cf01381f882cc0756f9068bf5cb71f99ea85247d9d23b8cfeaa292046c930d	1672654985000000	1673259785000000	1736331785000000	1830939785000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
223	\\x286225a3d830fd52db2cae856ea91846a07e353591a3603b7da517c3663dee4ca0499f3a0920d0b45025adf30efde9a0dd8218f99c667efe1d3a0116ffdb9f74	1	0	\\x000000010000000000800003b2969ae47ea7e6eb81bde756fc8d9b9d9cbe494da81a18cd5b5ef08adfdeb1dc6520494546ee3642ca83c03ba34a4f3c71e10daa473e86b1d2a5530026b8a8d78e1526488816e365efc8b68ea9ce1b3c5ef0a8ee9dc325d51689701f775a77049a385c127815a311c4fd0faf98776a134a222d0bdd002db1b15b47210d5bb837010001	\\x1b25bf7561b5ebb299b4282a91c6bafde321d9e48b56a15c28622654720642f2eb556880722a1dc357284d6c5322f11cd482b27a0c2a249ced96223744e3e509	1666005485000000	1666610285000000	1729682285000000	1824290285000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
224	\\x29520f73a2d753745d105258ca9ca3064647582803134595e90cce519e0328d7957318f06a0b50ae64cc6f6c032553dfbd6a66cd5d666b6bf9bf9d6b5d91686d	1	0	\\x000000010000000000800003cb0e26c07f81bc44a4eafd8ce9eece51c6e668d131cb24fdbf277b2a9b3af299384edbc48be39b17d2c5e6b723aa81a3dcdc74c4c8d22e10bbc060813f63b757091910d08fc1fb149abad039c20996dd7bfcfb84979f5d2b78b3a8d3b70962833286b71a8b65c24602e3ad1c794d2a502ce0168eb09a2419f424b9a98401a2eb010001	\\xa1f3f39834e75609f80852c3877f1ac8e250145a24d0385d932f22173d408f68398c57527431063e49f345c004c9282bbf49898ab5eb7b658551f6d6129c3302	1655124485000000	1655729285000000	1718801285000000	1813409285000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
225	\\x2a6e0660e4c1f9877f07d56686f725c8d3e0649eec1807b72569eff4fd56e1e6b4e6d3c6397b00c918393b501ff0af2046aa870f605ebe094521e0ba5539b77e	1	0	\\x000000010000000000800003d3ba519be0f7fc501ed0835a20007c240b3e5f3a976bd1ff87ecb020c02573d7f3aa271744bbd144b860fc3d66f897bfb1c10dd95c8203fb5cfa29cd6f3ba71b3445ade33c1a6e1a710e86f86dc311e3fbb37307290a55fcb6a531e7b4f2acc968cb624e7dc8d83c1d346395244689ecfe810787607ea0172d3e4baf625fd8c1010001	\\x6de615fbc66808d002cae06ceb5553473d1282f49bc598b77590a44c5b5318ee4c4f094ad139b36913328eee2ef8561a5a620f63b42a584eb98bb49828d01f0d	1684744985000000	1685349785000000	1748421785000000	1843029785000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
226	\\x2d2ee15519aa7e8d5dbd60e0cec0078581bb2ec682d942d2682afe8d6850d8d9dd117863cf8979806c10c09dcf3991b4bfe8fb77acb087a693e1eb6bfb91814c	1	0	\\x000000010000000000800003c8f7fe77c48d78e7801e5367c12cc0a8d1622cd673b5ad83c66ffc3bd7661e8b42dd2df3367dd59d230045c98c4211cf00b94f3d5864a337943354d4a460a0d1c4600d45e5f0f31820bf24f9bb30f6095d44f52ffc867e634c9a18332e4994feec4de174acef7d8b802915911fff5f199c56e1dbf6d4ea90786cc2c460819079010001	\\xd2709c1796e6f43b331aea5a5dd41e3dfbbeebb4f4e46222854e95df2993b85fac669d37721b482179aa26dea8174dc8eae234bf0a240fa29cb9867e21862d0f	1674468485000000	1675073285000000	1738145285000000	1832753285000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
227	\\x358abf8d3b6edad21b575fb1862338c801e356071dc2512375a1d58f25333f26f0189ec413fc7b6e16c55c996898ef726e8f9530c874e0f6bd876d0dd0c43398	1	0	\\x000000010000000000800003af72570ede2aa67716e5c2329662ea1237f5208ce89931b392f3de179b8912cbd59908455b1af6a5456efd136d51c3bb828f3f4af808a5f5285ea2a003b0a3256a1c01880841ea0c1b15cc69f022bd2ec72deafe782bac8c5a6e56f96a9ddd6bb5ec3ecc90894fca3ce912a56d8daf307324acadcadf43a8dda6569393493503010001	\\x0009e2c296f1cf90fcd4ffae1632c2dde3be81622765d6b99498399cbdb0bea1b403766499de6d283e1b701f619a806508ebdb288e6d3ea6ac653dc7e656620e	1659355985000000	1659960785000000	1723032785000000	1817640785000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
228	\\x35ba528cdebe4eb21d2e31c3802b8be703c06668a07fbeb44ca91f36ca0fcd0bb9424dc83420a4fc5c0f0965587bf5c12fed98c383a10908ff5e99b943087e34	1	0	\\x000000010000000000800003b9251b7d9ca542938bee8aa19c0d609547e1031cd5fc430360cc41cac74baa051dc0cf93f009443335ef10bd494781f7a6fab57333662f0b798cfde2a065c2f9bf27019cf88e335b25f2f9f3a7baa78ddf3eaff6166c41e8b2c5db8905dfd727ed7fa9f51c8a43c3ce5ef7a7f7cb8fbc13f7bb89f85151075595687db05cb331010001	\\x8f6e5510574e91f087c380dff0851dc395caaeca71dc682e1b2705e67c2183a36e04bc9a28290431123386f10c195c1d39a3f317e810af90b964dea8d6ae9a01	1680513485000000	1681118285000000	1744190285000000	1838798285000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
229	\\x3a6224d84287dde64662e32625f838fba0f698c86bd0ba20e073d1f73cd7f6e852913b47563897ea2657a00277cac721a43d75640fc1ee9133e53293f6c19e63	1	0	\\x000000010000000000800003e09760b6f91157b0f254cdd31c08d565610029206914b245733709dc5ecbeaecf89514642dd69e6022c427e6e760d714c05c3e9fb2e09fff6e9d4721cd7dae5e18e68d82447bb775c80551626ff3c31854f46a91b9f8ed0abcd6af06cc32491aea0c27edb2c361692d6df0cd1803acaa3c8cb490af588c2d6d7d2a9b7b23c1dd010001	\\x49893711dbfcb86c873d584260c070a5f3bc542d554c9932ab11c3000dc5e1ad06542c926ee26690e5af2a803146cb0d148f489627b7a914c70f15f43b4f0d07	1678699985000000	1679304785000000	1742376785000000	1836984785000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
230	\\x3a120f3564fce02f10e0a4bd0ce9da7f1e83f9f63be8d9823bff94b6d1418f3c2b2df01eeef93ece4cecf9f2b02ce469e6815f8835cd81ae487f6f540b4e7fa0	1	0	\\x000000010000000000800003e3d677f5a7a42bfff2ae40fd6a9c36c1b5072efa461a02f650f5f4757bc4c8deda1418e84250899c3af1d2f1e0604efbfa5f034925ec94b7bc3e2d47513f0a374826cec53f566004daeb63f62a62c8534cbcf3121a752fdb09e7f287e360a6afd50db555f250053154af44ca542439f4be96231944421600be37d195162e8fd9010001	\\x7840804e7119e80a490f29b7968cb9065cc8919a8ec2f5d745dc708d95d27645517b19deebc2bee70d0359ff1c716f9c604531ba82675ada1a452a0e20c05a0a	1681722485000000	1682327285000000	1745399285000000	1840007285000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
231	\\x3d42d9532b2560dbcbaa62e07c85bffae2b66fc6e07147586ef2c7fa1762afb5d6f9e0a9716cf57257f6feb374e0d7e9fb92c28744ff02d6506d966ff818e8be	1	0	\\x000000010000000000800003cf39e02e405067b23b440e65b3b7e322a609dc4cbd8235e1a2d74b63418e7651d0129d1682c2c50dcf8831728905dc3ac2c9cced6aa484722c5fd4c760c154e2207f0c2508838623c6841de0c0fe0701a167d70f3d9f86655f15d3030cfab15d78df8b183627abb2d588fb1eb474620372f33067903c0ebff0dfa8c377d96cb5010001	\\xa54401934af4b5d80a61486d2c0032344710439259ca45ce2772972e66513bc122400a1905217f7e3e265153f5352ebf6391085f4b4cfd10d7b3200b63790c05	1682326985000000	1682931785000000	1746003785000000	1840611785000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
232	\\x3dfe0f0aee2cbca5afb345492be7c5f3f07a1693cc3cd239e5e363bd800e26b8b9acd081b54625c4c13d5417d2c10d6cf6907ce36e9aa93312b6438e07e92424	1	0	\\x000000010000000000800003f35998fcf0fec8d9ebc285a49f295c3b0a8585988dbe289688e53e24f987771de3ffc2a31d18004593fd0fc08de6c61479c07b9ff90c0c99dc2acabe256f291857827c92133344009ef39182d2d6b458b1cec82bf73472068f38e2918b3227e72ac09b30577c79fc1679387a8ca4ea7965a59ac0ddc51e4d16c5396ccddb8d75010001	\\xfef3eaab8690a42d4e37ffd31fde4285f32038984ebc1d33e9ae504dcaea5647894f9528b2440f645abe5d60dd7977b86f435945156064928b6c82b7f0f50b01	1661773985000000	1662378785000000	1725450785000000	1820058785000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
233	\\x3d52f2878d20b9ab538124ecb22784623d94cb5f454f77b57821734e50d85af5949bc7d49606d5ef7b574face81a7e3d5f1761157cd8151c8881e8c7b08759eb	1	0	\\x000000010000000000800003cbccc8cde6f37ea75d9b62955c01d0b0f5059c132eb4c19b6f13eb9ed915be380255a7d60533812d79c85540858761af612e76f54b1990b6acb75e951543ba8574d439b454d7d4bd336a95b14abe71bc1779180e4f612cf33e4ffa455cb5bdca37c45b701aaaa416b9f5c8eaca74b0b7cd33cf598172a9f4dc1df6708ea705b7010001	\\x925510f4122765697fd01f8325fd7260fede35c23e7ec43bababb695738bbef2f334bea3c5c417d9bf3e5fc9e38a7fd700c0a270540c6031afa70489e221530f	1657542485000000	1658147285000000	1721219285000000	1815827285000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
234	\\x400ec6483c4fc77a6401d8e07895aacd4b17cea9e44e56439f53cc0abdc8c6260a48319ebc22da1c949bc06aa00017aa2a2f627379c8d5423e322c2ec814660f	1	0	\\x000000010000000000800003c6126556245f61386df1779601af990d92767d20373498396992f74735b600d91a407ccc984dab26529b8923bc4e610738c772f62aad60cf36a8ff933a0f23f7843229ce3bf8e88b5cd86a94e1702bad29aeaecceee7512bcf3bdba64fb28002c363697ea54e05f8892f10597c9168b45003a473d0cf2b491b1797ac11a72ea1010001	\\xf06c3a23cf306f15cbc12ae42a405cc9f9fbf52d91a3028f84e3de0bf65cf5ff422c8929785698af86881a436745a4b0737f38f297bc1d230b4d3f01c6618600	1660564985000000	1661169785000000	1724241785000000	1818849785000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
235	\\x459e7ff7746870a14f1f026c00826e5b435def933b697d286d127c10ef9852594526f091c28620c9427f3323af120feb2cd8e0aea597c659edc8c3835e9d3f3c	1	0	\\x000000010000000000800003b024185aef67fd0f66cdc44f3cb629038d886e2743ea0c55d4c83d8807c56105a13e2055f1376bff24341e9cb7993e96a421fa9def6fcec42fffe391ce364c89c866e6ba497b19f6ff7b06c7dd8374e7ed8e27adaf2a966a9cd9d9b5716277fa1f20dccf74ef70fabfb687881b320c05644d015baa6a8c19baa03ae4f3921be7010001	\\x7f4cb4807ada084d946e7c1d9a1b46c3eb3ab889887644f81ffe9a289f67e09f34e43702431e1d7ac4c16a7b30bc005c77b7ff28bb133be114f2d03d446f440b	1672654985000000	1673259785000000	1736331785000000	1830939785000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
236	\\x46ca4c0267603635b204ce2c09adecc0748da269281aafdb37efbd3cbe0eb79772fcf2d3080a9e01e6c118bbf67b4728bebb3b588aa0a14f1ca13d1a59f9b117	1	0	\\x000000010000000000800003cdd4642314c745fb3839021c6ea5bf8d944832f49de7aab558693501447444b50d470b8f40ccbb90e513aab69906e68446343339f7be8e354f5dc96ba9eaa07e1a78441d33684b9cd76c90b40cfcdbe22fd8df0ef7f759a10a30dcaa98c7a787d7ec2deb5783940802a3d98dd192bda52d5405bc7f9f660d0eed3888d478260b010001	\\xc33ca6b8394612275b9e06ed003cf1003332c7aa41b3d4956ffb5ce8feea4d4e5ef1403e9f3c2db72d1816e5c9792adc1e9393731b5f97b8a4d17f5d8f98b60b	1660564985000000	1661169785000000	1724241785000000	1818849785000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
237	\\x47d244413bb9b5685ad0ef8ceb90cfb20930b6010e41909f2ca4458019be4b88ac00855d5440e10d9756354895185f0fecf653ffb3f2182eb9da1a864f13b8b3	1	0	\\x000000010000000000800003bda892141c419e077bda1d77b61eacdab861d51359ad65a354f9df148e6a3e20001d0954ff11239cbb6327988c3e1ab5fc97bf3a37ec960fb67b910115df6f38efeb870dc3de21f00336ddcafe2113d402539c739d99190c0b65693f42bfc08d6fd36b50e2cdb834ea08e6e0b083deae8c0ba7594778eb88bb80c70cba4fdfdf010001	\\xdffc2c588217d8ff0bcc60366b20a43dd3725c6ee1eb7eb35c101a3e035f0f8fdc1071573efb732f60c63778b96afd129d50fec1f253f6b8e29f0e502cd3c109	1661773985000000	1662378785000000	1725450785000000	1820058785000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
238	\\x4a2e5e0311c040992ab9c238f41af47f1cd0bd70dc10a616576722c44e1f67ee282d4cffab79ef35310df38de00811cf81a7d49eeab86a4c0451dc99b133aa58	1	0	\\x000000010000000000800003f484b0e85289eb542e39f7d069eba64d3e282b86e3676196c6d2c2b1d9581a4bcf286c0f4fb182ac01b757e4da86f68a2588f3a2186520c090fdbb930ab1dd0ef1f43c2dc3eb4fec312eaf5eb108669a76044a0fa0398ae5b81c9012acc6e98159d133c1aad2a57c51e53b2206a8dcc36a4d11221cbee059690de255878a79cf010001	\\x1626c5f338ed50f23f08915a223b322f19abfc3b96c8344fdfc4398645cb43b7a74ee3f8a149abd4139dbd8340687b1a7fa4f58221160e9bf398d6b2a50d340b	1675677485000000	1676282285000000	1739354285000000	1833962285000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
239	\\x4a0e7e7a2608b85b46f027acc371f50f59b0e4f1176577dabfeeaa82b6ee1610d2e07a28c6a5403ff90c00666cc341d61ceb0eeab0d0f909a124565bdfeeb5e3	1	0	\\x000000010000000000800003ba7c63e917a131486da1959e476d1ab03c392913809a81b98d924eeb2adaf2d5916d779c547da2b1f825261f7e176b5c60c5a93acf7ca977df4ba7810e495de00eaf217923897403a0b5ffbd60166e79bd2a481fa29ceba97f96b5391ee03e68d7fce806495da604dc1fb913cb83148bcb89c4097976db46b9d8e493fd2574c1010001	\\xd2b66c1c026799e353e0e836b51a457de9be882eabdf56201e9cc17ca05e1d72b3c6216b5b17cf290002e895f840026911c313bae03de136258d10ed9e1e360f	1662378485000000	1662983285000000	1726055285000000	1820663285000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
240	\\x4baac6d6edbd16acf95fa293906b7884ad6359e0c9fa09db0fd6702b98a314792bce1caeaeac7c480012e041cee8c7dc0a4da930eae2ed8e89bfe68cd2355d97	1	0	\\x000000010000000000800003c161c1eec12c92fb5a3cf7310a2e717e57f362cdbad46b6ebd9e8300608a6615d9d2ba9a112df2ab2cc1fb2de1998119612baf1d9aeac8d9a107b2af43480641959d0c3c745e9029fdb8f9d5897a59e7482f73734ebcae16a63baa611db0a50a0dae91dc912847ec27a364302290c56d29bad982f8af779a7256fcbd4b52f71d010001	\\x3ab966cc847efdcb18c6b6450c76675fdabc458a50bf1d4deed7b5f09292d9744954c9e3017b92047c08ec54864c9179466395d40b9a436bf21041f40be69a08	1675072985000000	1675677785000000	1738749785000000	1833357785000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
241	\\x4c124d118b00338ce4a2274801a807155ef7c650cb1e487c15c5c5e07d8e8816b787cc253df5cd8af3a1038fee5c5870690f7026adfbf8864e9f2d1ef84687af	1	0	\\x000000010000000000800003c1048633ce087c3590dacec38ed0a86f75df565ada802c0ac30dac0a6984d7f9429a69c9d192883ebb46ea55fb3e73b0623435d5b48c2673c241e7dc44051f0a4b44a9d788f487c009c80518efe8058d1b1eecec464c841e6dadc3e63d5ab03b6a3e4f4d6d582c04e653a4c7a20e4b90db84c9fadb56520d9fcb94eea55e47f1010001	\\x1024c55efb89fc54a7c0efa850b1d3c7b691893b283229dd15b9d5971709312263c5cbc3600d110c14426f34e2c26c3190b30a1d173b8e3713ae417e31ab830b	1659355985000000	1659960785000000	1723032785000000	1817640785000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
242	\\x4dd6380858d87e075546b6811632ea3f3d31eae03b49fc771cf51e921f519e6e6e807029a8cb3aeb8bbe37056ac0cdf25245f4a52308966635cc585fd37e5db9	1	0	\\x000000010000000000800003b8a237b6510660709f315ce2461491873c01acd9e3e96eb65de901bf1e3ab959d0923c9674eb1a1a0abd93d1e43d615a7d6393a8745d7f008d25fe08b9321771987062fdf56e18fb051717cb713cb8c72f829abc4afd6c241d1b3a661962e13fda7f9893c2e489b99d06f913f030c13871b919e8c7975c789dc012efdd5aff29010001	\\x20ee69db30d20343f1e1a50e0b8d7674ee1c92d6b85a95e47a3d10b1b50e97ea97f942cb18556dfa6177809944f850b8801ce4844b8284a42563d9b7b68f5c0e	1678699985000000	1679304785000000	1742376785000000	1836984785000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
243	\\x503a0e63abfa640c5b9c53d11324684fd4f08be92fdb0825af7d9cdd77afeb7f009722e29adba31e27f0f3016c370b3b2c8ee8e585bed4d2583dd2dbfa32e381	1	0	\\x000000010000000000800003a7c77d9513b3d9f411e21233cdd7de56b27085c57eda8d9b8708cb2249efca72d95e4a7f320adbd83c6d7ae7f156287d1d5eca0f479bf1fa2a09665b8ac5b399f205e6ad45413b04255e6974417aa1c22b8f1f9d0f3ac761276b58bf85a38f181df195619742e3a8a9236fe5ee76420921525679b0092316fcea6b4a52e24b0d010001	\\x6494e8bfdd7c24ea2d592e895a06bcff5e759ed4d79a7b395e961d06f6a139ad7fe5a06c30ff7ffd9ddee2fec68bf259e4f6141d6aeb83450cca7751b48dee04	1655124485000000	1655729285000000	1718801285000000	1813409285000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
244	\\x516239f8434972db881ace4feb0771d20df0f56ad1645ad94f9705f87cb98399411013be7e1915ebb98616b2c525c4d15050934f25afecdfa00a309904083b56	1	0	\\x000000010000000000800003c670a3f22110796878c0e7643813f43b8fff057378245c6d1c48d340295960ee5d0b6454f3b68653aff416fcaa83b1e7d191988de63c7924bdb55ecf6321aec3903ed9cdcad5f1950c0f4796280ab84fa29e24e5a40b6db1e95906334a541b2e8619e1afd37aa2394054d951d4bea403edadef2a7a8778cf1d4ca29cb3406c2d010001	\\x122391327009a08b5d410af8af7ed1777c1894526065f18f2b6227a100e4fdd57fab2bde7ab7d4886abfe955f6487fbe4d3ec812d33b343be90ff14132c47b0f	1671445985000000	1672050785000000	1735122785000000	1829730785000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
245	\\x528e4d6895c8fd22daab920633d6099483ab167e7b1ffa98402e5da4390fc84b2ca44eb779cb88f17111141dcdbf49ad8cd2d9c80e164a622691cbef04cd2538	1	0	\\x0000000100000000008000039e30fcf9021309600cbae6b317cd66446106e9965cec699af035b4780fdee230784910b73e1cec1f961439d72949d78bbc4fa2ad88f471366a2fe491fe8a113496b1bb2b2fa4d57887108929b5a9262803a0dcfe075ea54e9af819f46ad02c9fd3a01a752f697dbccb6ab388e22bf3e0991eee7839a0152986ca8639ff6d588b010001	\\x8482a5389fd63d771546147a21815f77b6922d8cbe722e13b1beb0ac1253b2928924761a51d533fead6cc75db1475c708e01f641878de2980f59ffb2c927a40e	1657542485000000	1658147285000000	1721219285000000	1815827285000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
246	\\x54eee9fb72f4207f1b0d8edb7f5b888153c84fed3ad3d7cd072bdd45e20f9785e00ac66c6992a1b234f60d3209d2c29d6b9ea98acc57c9d9287492506aff5653	1	0	\\x0000000100000000008000039a2302dc21a2ceb3ec8a9a661d3afc51fa56507ba2622bc643d51663b7f96b5755763d00232d7bc1ac9033de5f8fcf098f8eb340c534534fee57c53efc7e488d03af2d67d4f5151e2ee99323d18927d4ffdd52e6b428132cb1a57906926527f7c4feeb960430d9a09ba2592d20db72fde0a7960065ccb30b449d5c76e1c21273010001	\\x46cccac86b7ec179953271f9c406d25f05a83bb21214626ccc75538fffeb114c8130c7eee43ef47962bbd711d85dd025f44b0b9dde975c417db736591574ed0e	1677490985000000	1678095785000000	1741167785000000	1835775785000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
247	\\x57ae6c04f203f9ac21ffba208500cc4efdf55e50f4f840516182fcd4241c630ab301177356693491de3c3a089954f7a9f91810096d85e0b21e68cbee37b23189	1	0	\\x000000010000000000800003d7dbcfa902f0ca73c89c48da8ed237a4bda2710c687c011ea76db300e8e02a5f02295ae097132c84635b6c3f87c1e0363ee01c3fd95beb4b95497a6e5670af7f324dc824044fe08577c0b5e96fa0114c8e49245ec1850f37c0443a3582c2e8be0229f09e194efa2a25ed664b63d6abf7bf9e65d051ba94a77c583d179bdb7981010001	\\xbf3a030cc0f714196c9b16a0ac00cd64166c9fe95fe8716c840eecc59555b9ba95c1ed65828a2a972c862ff8efc0a018e8d70f80b47bfb7bb006e6b449a48b09	1668423485000000	1669028285000000	1732100285000000	1826708285000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
248	\\x584eb419654a9ae62a082fa58916f1ea79c72b04dc1c532d33ccf2fbd8bc6c9e608d11e39ff41be2a58b66e76e1e73832954d85a313948fe7f19bde6edcb12cb	1	0	\\x000000010000000000800003b7ab3a83f8d95b66048794258f0a79ec365bd6cbb71296f1b7b88cc33940c769f5ec7e2dd083640e9df2d5b0dabd09eef4a724ecf683e59fa6b6e7ffca832cf7067c8c6c2fe6fed756cf80a9cb515a1f894cfd6f24e6571ecab0a802b47c2f39eb684cc0f8f22414b9afcdea7aa9e4506b10dd4e5b518d290d41596f76cec079010001	\\xd1801bc770524909d8d60c0a6aeb54fc71fdb973cd2b30258b30a93f65853be7c8d56131bb7acc4d07d5ef3ad99327625857b33fec5a7b30d50e7e57f451b701	1675072985000000	1675677785000000	1738749785000000	1833357785000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
249	\\x5bda241708eed488afe06124b1c6c6d53ca794b6fab51c76d268eb7ef6482d9077c14b154150485331467037bef58d2ff5e0471481ec366557fc49dd45e6f57d	1	0	\\x000000010000000000800003bc8146005f93a2c228cee40050754d116d12f3bf32a83fd542b135aa69ed61dd68e62267be0cc3112fb310e61d2ae5692995a8bd18facdd83c3cafd3ac91bcf48c0b931577b8f7ec81222032fbf4e906bd774417bef48b90b791c91c6120987b66636e290d80efc4c71ca5eacc36d36a40e7e6809be8577165cf400d5bda705f010001	\\x1c0f52bf770a4121335663aa1dfe4013d363f650957588286d5e84f891c5fa18045c19916b31944abf18cde749410725acffd33f378a4154ec6c823954869c02	1676281985000000	1676886785000000	1739958785000000	1834566785000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
250	\\x60deb033f52d91ebeece0e6d3e0095fb9467fd53878acca2d4bf55f0c4af0d3f93a0528c4f1d07ee017d9e584b6babcfcb8b6a502c6bd17f5c3546673cc67108	1	0	\\x000000010000000000800003c868f8fe31dfaa8e7d36014268e68e40ea613919a76ade5e994c2db370a03378a5cf87711044ef3b0bdf0a54268b310f51ade9a8e7b5f48df18173579f08b3d90cd85c773d8def96384b0148e13db36d179783db43764e2ed41d6af07088527b35d9247632a863f832d79cc913f80692233530561b407f3adacb70ea5997d5b5010001	\\xa3dd721a980a783ad741f629fb0de5316cb7edb7d0855b1a78e30f154ff7582ac2c2345cec0bd8cf818d009926a1b400796124b02f3b204c84e59fbfebb8be03	1663587485000000	1664192285000000	1727264285000000	1821872285000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
251	\\x665a6278399e68a0cc9301f4f9eb455398abcc894579e3dd61fcbbc8f784e8733a5f4383a4f6549aeb4a538d913a9dd85c2d0f0c2ffccfd52ea8b75f6975acdf	1	0	\\x000000010000000000800003b6d00bcb069ae2a7ef15455a0a2e602ce527dd2af62e3c5096b202b2d81471cf06b90a852ceb3892c0564c22deb2a739a0017619c810a153a3448a4d8ccf2da03e12a80cbb6509d0dc439c036674ed136b019f9808929396a4139b42cede3aacc1ee221f2854016a6ed5cf8a292a14520ced545bf8c3f6269bf299e7a2a08b8f010001	\\x7054a5d585f47976ca926edc085d01f8b0a40b279c991bfb5cc6df5c05b3668ce8f0ebef02b190e3fed9a666ad7f0e2f497413702807b9ce89a30a895c1a7c0f	1658146985000000	1658751785000000	1721823785000000	1816431785000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
252	\\x69ba5eed8e2e08048fa1591095655fff04227d6c37a659b69dd2f09d3701277556b1ab7babfa3fa6a0e1b7d6ad85e2a85d08d481809484abb031d555c9a38f1c	1	0	\\x000000010000000000800003e039bc37e0a94233c94255e2c55396b4b218b692993840583fba19a05c8bb755855fa75d4dda320eddfe9a995e03ec1e05e3c5b75f4466096b08f3b32ebeb09553b41b5622bc6992989f09a83edae649116b6929c413d4c7b22984cd9a7aa9da9d16497616eda37940e28d554224407da99c7b15f97a5d706f1eab99abaf30f7010001	\\xb4dcaef5099d54aa5eeb2f461970a1b5a5500fdc443c4b8afe6ffaeefa869632033380b6c3047da4866800794abc24cc0aa16980ce60990711ecfb10dc06160a	1663587485000000	1664192285000000	1727264285000000	1821872285000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
253	\\x6d264a1a8b44889bb205d728d1304ccdb122ca918e471cc3c95a777e15ca9b49279a22b392c180da162fcfb19e7d52038ef31618e9a6fc8627c05fb798eecac6	1	0	\\x000000010000000000800003abd15bb6850077489f8cf17bc63d798b9556f5c8fcb2e26eb7376469e34b5aa9159065177e51e2e8a1d5d0c9f9a0da6d4d7f5c2207a3577dccee62c0a0b1025d10ef1c2e7613c770c10c363fe166720882ffe3030ae61eb52c60ab11a6fda8bfa30efae013baae81332554de46ce45d34f6a4ff75845a712e844bce950cadf37010001	\\x44f87061578bcec5216b63445c1ef343a4c48e7d33fbf28a8c95f20a4cb69cd594fb191f5b5e8ed9117d0368ebeb15471b345bbf414bd92ec665fbdea7b47908	1680513485000000	1681118285000000	1744190285000000	1838798285000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
254	\\x6e9ac5aeabb5a8a6921d89609b74fa57152440c89712dda0702499a2b52eb504fe0bd79c1ab3e6bd19c76dafb439daa1041c11f2019de70164ea851b84c18e4a	1	0	\\x000000010000000000800003b06382bdbe58fab9d4c37e0ad730dcff41074255a0d9448321cbb65012003502f40e18783c061d179f1edda279556990916c23233303211dfefed57d666cf3e515a9a1e1ab165ea1c1144db532104659c9e32a6e7bad66ee83a5e0d1b9f819dbef896a5a1a02f4178c17748ec1af0259d943facb76bcd3d6299a394fdd7bb58f010001	\\x6f73daecae1a72ad449bafe321965a621bdf7aafed2aa6ae451fd21b022df5e5306c5ecc7764d0e6ef91e14a31db27845fafccab40d64657e30ebe80bf243a0b	1673259485000000	1673864285000000	1736936285000000	1831544285000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
255	\\x6e1674235359edcfa3220cbe0ece7bb354f3ad7aee8dde96066281874370e927319081318eab188ab666189b6d3a71ea1ea8229019b8d6fefc653b2452d268b3	1	0	\\x000000010000000000800003d14aeab366d6b30c42623a2b24d531aa6478c7970499501c541df288502606734c8422a171e739cfbfaa54260deed0447467775fecf2f29d9f77bfed5220e51c323317f1e552dc2b97ece21de40a087ad5c769ad18625a85dd87f9bb9e26770a028afd4ed016994037751df3a1eb1f9e543017a9195335726f950c7cc19790ed010001	\\x3decb1015936a8be01a83fbf7be632a2aef374286ba9303c3e55ba032750afa07420dccd45af7864305f310f57f92002248d98153de251c47d07f5b165cdc603	1684744985000000	1685349785000000	1748421785000000	1843029785000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
256	\\x6e32bb5240f0fa1cfa45b4f05ac90151c8b8dad9e1486d2076970ce40dd37a0d96fe238714ab49ee0e8d56f3e76c727a106f08c85f718ac8cad95dab0b5360a4	1	0	\\x000000010000000000800003df6b5ee3dee989025c1ccac297b1e9786828b09b7feeb8d016b28f21c9d734a540b83290bb3f9e817b2bcc79fda642d4adb2caee172daf7fb01b8f17c13fbb6959031979cd6390af0199f88727ed163754b9bb5e6b17071161ef10d62c1e7943bfe2082baf90e43f80486752d57e0e5dae213e756cfe04bb5e0ca52ba10113d7010001	\\xc9e4c948c61dc27f16a602c2734c5d66d0b56ab54aa5978a6fb33cf67f5d39765ef05200e3674b7c8db8017c4b8f32f27c34d4f2fc7d73774fe7809165e94100	1681117985000000	1681722785000000	1744794785000000	1839402785000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
257	\\x7146cecee54ba5878116e50d517377254f5f062bbe386ea418a530e936217426eec61721abc239379454824691e52e4c53dc848bb9e8f7a1b8624420f8ab46cf	1	0	\\x000000010000000000800003c069262d634cb6b4f25ab7796af2e64c511a24af8646a3aee1b10f61737b81f708b4da8634440cf4e29394239bdcd985f22f4037ee3c2f6aaa1d0d7599a8bb96fb132fddc9d3e9b063fee8afc0d9e9a324841a1a190bfd5f2c593229f3a9cb0ce2219f3755551ae12ce54753f1690cbd48083cc8e1142f483b7013d00a10aecb010001	\\x262815456da66ff0372a9d20ad09cadc3a1811c029ea31ec965002d728d385585564001dfbe595e75b76861979ca6decbb3761a9aa887e99122d8c0ff04ac602	1666005485000000	1666610285000000	1729682285000000	1824290285000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
258	\\x713209db48cb4e1aa71b23f2be23c3578dd7d47315cb662916bfabfb2f563dd196fe1436de0e1ce837eaf012e7b3ac3aa6701051e480e9da8842785a8478d10b	1	0	\\x000000010000000000800003aac35fe12e91ff971409602c4bad0ec3ee1fa39b20b1239cbefb7dbb21e85f6da712abfb1b84aa289e8e5b71930224da43e03d4d3d8331ced4e5c3ee7854fb2ebefbc63a74a3d0a07526eec50ea3a9fe5b10a3c658e7a40a493a545b588f738f3716221d6f1458123544088075ea9b436c5cb3b95321ef6fb076549fa56806b3010001	\\xb9f7431b0cf8cb52e49eeafc4fffb5209841ea42ccfb54e5b5dcdf3c4df555ba9e1977c23ab03a0dd067d4c8d3e3d7db64abfd7103199523062c2b68ebb16b00	1682326985000000	1682931785000000	1746003785000000	1840611785000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
259	\\x71ba2fa72fe5880407a5eef7059d5d88ec02d81d09e2b31f872e6e4216d1ca6ce0939e8cbe0eabc9a032b43f97b82fc5d5bc13380a4bb374fc21fa41c6ea18e4	1	0	\\x000000010000000000800003bbba05b389e84985bf32001fa78e7cabda4fa6a413002f44acae77013c418ef8b6198f737a259cf06731a3a75644ce2b544c42d1783fce013d050f04526bf241c7773323e6229a0d24bcfc93f645977bc2d883e09858651b5ac6d967d5e778a628f1330cd7317afbe45fcf8125fce5017d4c1e179b6c3db444f3e3c8811d79e9010001	\\x00819ccc60cb14973ab2eca10889903d44bb715769cc09cc8ff72a64c035cacb53d17aaa757af685051f625a0f08fa425311cdda4fd7a18ac5c6260da891d205	1683535985000000	1684140785000000	1747212785000000	1841820785000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
260	\\x770efdb50983e302b66acb5a68ba3678f8fd479d30d1e5ca8595c6645bd12a8b268fe036d7d1ec3f3e5bfa937e57de31411ca939e6a44d3bd3cd456beea602d8	1	0	\\x000000010000000000800003d3fb2bac991e9819c054b1e2af5b6e55748b50de0251fa499e94b4652188a222499b76ce5d0f5601cad014939d493d5324744df73d2edc738f52842462598c44d1420528bd1562e2c75298cbea811d3577af0d3b2a4cb8e7bf0eed200ae91aaa36d94d4608b9840bf1fc21c256a1c0659c055475d3fb81684dd9a74fc7ebb5f7010001	\\x75ab7d609de06503606a00203399eb7d2ec57059c7a480c2e25b09741ef506650dfb9af9a281a7e6a2960cdf1f6fb37374d0d55a0e852b9e64e57c15e530e202	1658751485000000	1659356285000000	1722428285000000	1817036285000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
261	\\x781e0b58dab566982c40655a8d413f96fd0967f27309252a4ac3f94d0c76e4348a4bb6e21244d2ec684c0aae1fcf5db4f81dcef6ecbd69aba0f8292bb22e9189	1	0	\\x000000010000000000800003d566adb01fab0dad234fff8df3410a80138ec55c54f4af236ea03b19c2c4550cb66763748edb96e44eaaffa033f4fe5a23300646a6f8d096f3a34857a3b523bb1c153da9eef2cd79853063bdac2e1f9cc2ca796150cc997da379b5cddbb5d00c986cdd6b2c6d17df000c2522f5ddf71baf32e28b221c17e3bf95904d70a4017b010001	\\x12f4b9390ed4ceb3fa93d2e97821cf0891cfadc5a4c86e4e7bdde9d4b76abc39c8ebbb46c0fe95e992a7839f57e2ac5134afd2b5d44f6a9a818a3ed81dfc3c0f	1662378485000000	1662983285000000	1726055285000000	1820663285000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
262	\\x7a162242ea88d67e9bb864ad159e530b23a82e21146a34467e9917f4364348e100671a9f48c21779fb6db0738f189b71b0544bb6f5239e1d445bba4d3321cb44	1	0	\\x000000010000000000800003b60b22fe81dd02698334f395d8b123e29bd4b7e6a141157a05f02f6a0bd4c0d640ecc075b3846d7e27ca12da9ec00b9bd14f06f77e4da0d9a0516c1cd962f8f2dec5c5a561b19d7ec513e301a90475a14c7567377dace617f578b272c8299b9053a182c50dbb86f29d4b6ae2b8582d751af4ed68ecc0b5397b766b36aac530c1010001	\\x6214c3da10446db0176aac496a477252247bcaabb26d84f28b411ca6ec3ebf858e9c888633630d43ec6e6a78bff096552fa7aaafcef39d60f986060eff06020b	1682326985000000	1682931785000000	1746003785000000	1840611785000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
263	\\x7b5661c97b5a1bb15e00e00709c1b9d34c0172189d9225f4ba724ee220a48bb12eda9eea9c40c1e35d9d63d006c73d1f8ebdbd23be5b308d9be8e1c75e55a480	1	0	\\x000000010000000000800003bde8ada2db321b03c2b1730b6580751c13212b2a1ede71ca137113244e04179e4cf133364d79bce34ca2792304bf42ae79ad4426aa062ae246024b19cdf644a2b5b5ee7c059155563cfe420f259bb1e10ae4ed65a2687a9c66d57e6daca45e0cd7361c020316bb4861a0ac2cf68ad4ac98acc267cb1348d28141d3d7606949bf010001	\\x3184f6243aef5348709081f4278b064daa7e6ae4968b83a0b09d320d37fbe0a65fa1a11421bd0d28e8b5adad84f6330b074fef8a0de5777b3e204faa050d9902	1677490985000000	1678095785000000	1741167785000000	1835775785000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
264	\\x7d66ea14b909b81c0b3a7351fec8e973aaed26eaf3beaea884bfda68cdf91f95e32ff1d834db95d40f54e446627b73e7d864e809a08770c75246f8adbb34f58f	1	0	\\x000000010000000000800003bd61e5acb0beda714947d6cbad7266860f7f92efa8fa66ddb72b3bf166f56b3bff99a2a848905484c013947e68326b8d906083b15726bc4f05991e4676890a7b92076cea9d0f7eef7089de3b423b06d16e0f1cbf66274e5d54fbbfb5b821abf94f8ec8025d690a48ba289b31af4be63b6ae408474bac33e7771ea0a79b234a35010001	\\x4814bb898262bbf25a2e588d71690ced551d102b09b9d0be66bae42dfd013a4e35a3d49416bd122a403c51f3e84059ac4eb259708db249e6c6245c95466d1a0a	1659960485000000	1660565285000000	1723637285000000	1818245285000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
265	\\x7fca044d611944ee32e67cd6212a0c0b2ba11ba6be3873e744353240b8b91ed4a325e22dab1c17f15b2d7dca524f7f85b89174a9c6f173a8b3eef45534d0d00c	1	0	\\x000000010000000000800003b47fea1df96aa819b5bab73575a1104a812893b2208c4a0ab293efd76f85d7af0e2dac51026c068dfea7db5a62b055b12743aea2a121f717614abcffa27b9091de174bd45031497d8cf2e94a0a43814d2130fa865bfded25c288db060618d76cd15558d74ae8abc8602330f527164262d65a19cf158a31eb7acc2bdd0e55fd33010001	\\x1e64509a356536141d8f54120965dbe329b1892cdf9541ccf3e286686731b1677810adfacbac812aeca7b1e03e88e30c65126c2662a420142dac0d81071f940a	1667818985000000	1668423785000000	1731495785000000	1826103785000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
266	\\x7f9af885822dfec1c137af5d1e5f6cddadc274a8e02a84d2cb2096ba79b922b9ae8887b1c497878e06ada48fe03d4bf270c32cec6af820a915e2954f7ea4408b	1	0	\\x000000010000000000800003ce6ef3d781cac9783606f0df8e0722d1df26b2aa055a31cedfa20ecdb3d199f62aef74d1c81b9a70b320af1f4436f15c4fddbd4ceae18b8de69cc6244fdc5569fa04e1787a79626426e58f909edee8089cf9dec08323f32294bf28931d2d75dd58d10a9263b1b084f5d4efc4cc2bf6711c5d69aec236d6e18be9199de13f1e0d010001	\\xdd7bbf0c0ccfc09e9b3dd5fdf39b055402c17010eeddc9b36b6268db079c9f463e02fdd5c17b7d58eeaa0cd03bb54bf986562207ea176e011bbca116f314980f	1664191985000000	1664796785000000	1727868785000000	1822476785000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
267	\\x811adca6bff57c73dce30da8fd88efce5da01e109362ba89dd8cdc446cfbf41e78ebd8e24fd68d407330d9205cf05b8edb87a0877e55e2ee705cb9419fa65662	1	0	\\x000000010000000000800003b32cebb5bded3794d3f5c9fd715768c51a6e0cd500551f7e0e7adb84edef01ac1bd2f950833e82d72ed37057e4c237240e5425f8ce6235fd1b290b19166d199f83312433d9fa6f92f7a9bf05553beef34e19f63acd66d7632016c9a0cbb7e557fc0215762c94010e5ab6fd0a88dd73254d8ffa9fa072acf6e225d72de5408fbb010001	\\x8174e63ff0b4ab858324a3a25e761d5ab1a4e3ac655e20a2daaf3f2e0317e10315bc87a741af41206fa0f9f5799bf3eb024f264fd03040e93322b04a98314d0d	1684140485000000	1684745285000000	1747817285000000	1842425285000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
268	\\x8332e776e400f69853404b376d00c76e383f38ab05cefcb3fe0cb8a52f69c9b9a7c223a47d3494f7261c27b1c8c32cda76573664a60ae78a9f85ecb985fec6e2	1	0	\\x0000000100000000008000039885474a78756de327da0cecad58e27b420c4690e0306dcb1ad70e8028f50ff57a43f134e119d1c93579d48e3401356f1cb4e2109449bfaa56ab8618cfbfd8319c742f8ef17b30dcde6d505692ec1b7f6954cf2c42fdcbe9b5ac57101d6bfa9cac6441b46f8ea69485f0258583f07aeed4a8f11316fdee07c563cc7c157236ef010001	\\x78bcab121ea7988323faf02a767ffb1f3c459e1eed3ba0a62f04b839435cfbe7e3ad547ffdf41f8c7b3343ac7a5cd4042895cda46b0c86225f3bf0e3e6d4cf07	1655728985000000	1656333785000000	1719405785000000	1814013785000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
269	\\x865eba3bbd978d7e5986eb37ad85b59ec1e107acab702c7cc599f004585c13cd921e57c7ed16dea5dd635b2825375dbea0c31fae9a7af040461148aef425ff0d	1	0	\\x000000010000000000800003c1687f170718818244789473adad0fbbbd7d07b58d87ee8df42a70e29f205f84ef3af79340c85f80608eb0a5c9111396ef1e8acac915b1ec27f2230a733664691cccbca404fb7538fd1a89030bd11218f7ae41002e7328f014fbfec5776bcc420d3f5fc058e10619f81e41ce048f5cc0be754f33021c227ee5ebc54c01828535010001	\\x18330abebea8957e30316a28f43adcc829269d0d7ed25b866651b9b292532f91437faa0a576597daab481f704564d651abc5089bcd09e78939b02ffceb8d1f02	1660564985000000	1661169785000000	1724241785000000	1818849785000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
270	\\x8662e9279667a7f4c1d2e4df99130a565ec3d61c7e16c565d77bc47e9e653b9ac48b6100c1bcc57d7f533598f2686b2dd84d21f5b53c20f3b24390b00de5a318	1	0	\\x000000010000000000800003d1a187e38308f743366077099991ef0fbf21c890ccfed8811e876ce7c8632feaeb9b764ffe928c7e1bebdc2704c1b7c9871ad24dc56a42e2a955ccd766fdabef338616db0c5e9ddaa8dc6c4727b19f7dcb795b96bbbae8165d5fb4e4aebf433711d3e93dad507737cd26728261b6ef4128a4c108a032a24767cfb0f3adf76ee9010001	\\xb76c758dd4413c0fd3e32ae60c1b908ace39d02bb912932891b7937fcf22e859e1848fef40bf2ff7c1f50d1e6bad15242969bc62209c2c556f6b292456c9f706	1682326985000000	1682931785000000	1746003785000000	1840611785000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
271	\\x878aafd227e42eb52502810c6c75783b271c10cc9b1886f66edb4615bd02a13f369eaf84e7cf951de36176489766d5f0a1d67e05fba6ea1fac9ec90f9d97ba1f	1	0	\\x000000010000000000800003d821a274d44e1a6711a1b79277cbcb6ecd592e3246ab3d6374ecbe9f44de53042ba783758fed26449fa2e2cc7afb4513c96c8b2292133b2512f89c5bd68e5e5bd0434de952e9ce1aef0fd7c455311d0a0a9367bbd278d78e10528fc5416f3d84dffff749549e39ce4cd2b22a705e04471c7f013b31164271b2d8ac5c34782fdb010001	\\xedd117559df5660de5bc2fc4cd6a23b9ee4e3f17dce936fa7a08e9ff6a82565b976262a7dbdcb2ded98b6d10b7d760e0543b3d423e912d3b2344b37036726300	1661169485000000	1661774285000000	1724846285000000	1819454285000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
272	\\x8bcef11a5c2bed35d0556f350bbd1b1ec56decce441b3bff5af9db241ceb7a7b40d9d1a2e3a2380c3c7827c36c7b12da64de91f6c6ad269db4d61b50b523f941	1	0	\\x000000010000000000800003a7f89f0f558e19214e33fcb7e099d656effac661adda4e03962910fa720bc047ca35bd277ae49c2b9e006da7e07f29726ad234118a413e01955341a13b9529cce5659d55b14c760b0085397fd4881077123bc64e610b1f7d64d9ab6724f194a81cf7011d4aad7b39fa5b43f62c07287422c0e7d3f2ed4a1f5220ede8cab4e3d1010001	\\x8808efd6fc75a4feb849dbeff5dd6d256bff24c46e177d4b6c8f1f1d2002582be2aa4cc75a467d1ceb1d226cdb30e3b5510b4d873f9b455f4a459da9a2247f08	1662982985000000	1663587785000000	1726659785000000	1821267785000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
273	\\x8d76731583f3898ad8ff3c3eb63e651c54442fa2aeb988da2d255919f6e3719eafa9fe828731ef2f2b5f3d5287e661221cd814654962871c6d04882d1f51d4fe	1	0	\\x000000010000000000800003a3dc9ba7b09ffe851b64093bc5baead78577ad1907203ebc8d999bcfcf7086c692a28d62393eefc9c8c7681148e98bdec74fc86add9e3849540485b5a4fbb38179ee7006f133c4dbec032e81206334696856ad31e14a0a40292df5f155d96207a8dc66acf44a03951b34dc7578b29b2101588127f4d97425c961cc1f417ddaf3010001	\\xd386805171c205dd5c94404b93b428f4db058bfef24622b36a06ef4be0bf85b51ed233dba0de8a290fb5b881fd3681cd16ad590762bbda17750a73e6d824760f	1684140485000000	1684745285000000	1747817285000000	1842425285000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
274	\\x96b6af01dbd8b3939c7255db295bcd526575e618c51ed7306b93f30b6127beeab1a5c00900cd85e9530a249f4ff55e98adee1a4ec35e133bba8d2accce392d64	1	0	\\x000000010000000000800003ededdbc2dd6591624152c52f0fbb967886cc3a2c37960b5b274b3d48606e876be0b749469665a97a369332acaa8a4f2995b5b50d37604999af8c7fa4ee5788586dbc4d8bcfbb649fc727d2bf9e813cbaaca0ca86e621bfd68c9c3607c457d452fe7e34cd175d711435017152a8e863ed60fbff38d3efcf9307fbbc85e4faeea7010001	\\x501c518fe08c0c422798baeb307fbabda3bf418b0bad040e88148d9bf8c660ccad849af26ec0bb66c308c240e4fb6d14a1d6461842e6fff0778be84f50d0960d	1666005485000000	1666610285000000	1729682285000000	1824290285000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
275	\\x9b7ad2278e8c5dbfb364e3904ed5cf50a5b0e3800ea8d7c7331f1cc390611a78443f91287a53724d6ff7e51d7d6ebb7ab0971f737ee110ff1c79be1d659c971e	1	0	\\x000000010000000000800003d414676f10dfedb52b27815f81f9add85a463862af8e3d4defb3fdc5cced5c181594ec94c332c4dc93b619dbfd4a02956bd8665b4922dd82d4acfd3f2dcb8d40859c48343889f7f578e8498ade8522c4d85f6b27b60ed0cb95dce6ad171f42f5357f784539db03a53e2a2168c10032db89bd0b6c453bbac36c1a829b49822321010001	\\xf11c00b00440f806b90e1b27d87df9a217faeb8b63494090cdeaaac67264a948b460e88c5a321949ab6966204ebd7e4f22604a059725da9f00b643a8aaa66c0e	1674468485000000	1675073285000000	1738145285000000	1832753285000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
276	\\x9f42558887d5d6184beab61faf43aab7c0482b75998e3c682c9f84a686540016d1b4fcc2b7ccbfca4a7799bf7f858f6a64ed8703d294fa0c257b0ca7a14134df	1	0	\\x000000010000000000800003cc921ed35e9549b6f05835160c75682a323dbfa5e1cb305d697606a23a92b8bc49874f2d5ccf939f04b7f07aa76cae72e9b8af8aeb6068a444ca8d547d04dbc7d45375458e29e56a88a4118d464ecfdbb966a82a1cda3b0eadcde195c565e28caee606106d326062f92fa242d816aa2f5ed2ce33752331c6a4c795a8a2f5de13010001	\\x7977e7f6f7d20c69920db427ebbcc06153b7920286944853b72e90c1065cbfb26e3b0b0cfca42514c49759d447838bb7535b953fa9eb80e892e8dea8ad92ca02	1655124485000000	1655729285000000	1718801285000000	1813409285000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
277	\\xa2fae27f4eedb77b20e00f312db28b10878cf4e157852f4445dea4186482b2582ec25928200ab85fe611a086f5a87d0dfdff50519583724570be1202ac8219b8	1	0	\\x000000010000000000800003c46a3af65ac9c3a3717a330e3b452b9985a8f878a47361c97841a6f2d766cac5f7724f6732f88ba32bfbb6010fa10edcd21f7390016a8c235bf8ecff3e9cbacaa959457a375fb9f735273c135f42258e4cdf70a95cbe555106f66fc5fd7ab2a24740fe9dc021bc29e6f8ae9266f5f43962c02573beab0fb54c3a8b669ebd68e5010001	\\x650b5de48279563fd299a6f5ea562497c61d0634da4195d5e8a7ac1137bbbba2d1de5d1c32fcb5eb19b0ce60b099fa4f8b59c3a0dcb5f27bc37035723b837c05	1676281985000000	1676886785000000	1739958785000000	1834566785000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
278	\\xa20ad392d0b2f7dd76d0c1ea3b5a5cc919b96d245bd1ff40db90f668e644440368aadb0385dcaeec61472bb6e5c063085d151623eaced74d66248b0d55abb915	1	0	\\x000000010000000000800003c8e3a8c202184b844ba4294c862fd083bf9d87d49c0460a6209a1335d65a1ca8264031facc2e1511382cdbf9e9432540091511d39e4a01181ea045b7a7c45c7851b4dbbe54d4797011d5c5ea7428eb4a2d90611ac8f142f83adfbd3c71921c4ab2e163b79efc1f4be505dbb7594f44fb9c43c58e1c1d1ff0978994a6f31fb5ff010001	\\xe389637763126d80d3f6ca62ba1533c98483e86c97d87cfada1872c62d62b7ed8233cd58713536bbd5cb3dbd69299a09129af830879e5d1bf5511d0fcab57a03	1680513485000000	1681118285000000	1744190285000000	1838798285000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
279	\\xa22e95a3a2d3497f9d4dabd75708e20ae20d06234441d61a75a164c6900c1bfc7f299936e05c9d6fb701d71df7e507b78b4a04f81930938426d08160b40a89fc	1	0	\\x000000010000000000800003cdb4e54abb592d1c62a2a666a6156a5ce31393159f907d0763b5290aa47455a927c7c6ee704c4e88a2a4a31ee8f60e54d6b67d574357f647569cd06267db9c3c8863f94587e929e47f99b771e8b01310cbb13803292dc4734ebb37db3a2aacd8f8e88f19e483eb044811c96021501ebc2e46556c9b97300218128ce1c4099d3f010001	\\xb5aed7f911f8c25c255eb3137670ad545caf64869f1f4587f3089818efab07cfaf85ffcd1374e06ca1cea6cf9e064d3d869954de6a6546e146f2a977638e0001	1656937985000000	1657542785000000	1720614785000000	1815222785000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
280	\\xabd6627f3897b63b5b036a910f337a2c5ef83c9621f9d59ce773c870367f760b27568ee931ea7461bdc1070f5281b953042905b25dfdaad490eaf603ef032640	1	0	\\x0000000100000000008000039e1421c6fddcb0baeed78ae1080cab6499ed1d45f5e0d070a301a715be796092b56c020cacd589b2fdbd07b3597997cd6332b0791a6d93c38c377ebc5eaf906cce7986028955eb6627d223dcb34b7d8696ee4c00fdcfb2d13458f7856f19d400c23de2e44b740926de9435651722faa4ecbf50d9bded8c60eefb3d25bc58321f010001	\\x28c45a88cf65f64f15da347b1a0cbe1070f87d4997136c5677dff4dfb1fb86bd2faf68e68be2016838663d61b40e6150933faaf8cf5f8ea513810adef6c14508	1658751485000000	1659356285000000	1722428285000000	1817036285000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
281	\\xad5ad98508d1b85f791abedaa189c6ec4395da6bf4421532a3fe8b2ad3a7032e2287915d7123e1dddb42d5d264995fafeac80d45e36c20854a75050e3cfda93d	1	0	\\x000000010000000000800003a7bfb299dbabfcc2602be32614dad3cd48da9fbe97b9ddce292cdb236057e99c50ccbaac7d450b9385fa37575f44e2f1da56160e307535bc26e79dd94a59760c19519072ed01b6c2469f55f0b7208eb1686559ee26db0f50feb87995cd29c58ae6c0eaaffc8b899ed50521120d99d56d319467c5826037f905f7087a9b9bd561010001	\\x2b755ec4a1a113c57f308dfd0c357c2bd903acf173f9cd1276e046e7a8e3e6fbd5a63bdd3ff9d9f162525017e6918344ccff576b85f095500067f645fda3e105	1671445985000000	1672050785000000	1735122785000000	1829730785000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
282	\\xaf56e14442f7c97fe20def073bc34f0951db08601be3ee9ad68237f97053992c7c377e58cd0ad3d37a53e31739e2aa4e900d9926a11472e64fa948ca96217413	1	0	\\x000000010000000000800003ee6ad2df89e0e58b8245bcadd102575e2df722f971d391092854c45d64045e2f3705c86f3bf73b5f977f70f92597cc37a094933e16a20e8f2063957777da0b1f539a8914a21c813a0576c2ef91e0852b466e1a9d307735afb14f3c29a81cac3c861707fe51cf5a7e6e24c7c01b6d0c1f68f963586b869af282ebc40d17b9d179010001	\\x9fd24a721a3520f6ea831965bb5ce59d447a935884f647e2dc98cdeb22e6ccc9df60c5a99411bb5dae1fa1455e4b3a724b02f9e39b67c20f8c6ff687910b580e	1660564985000000	1661169785000000	1724241785000000	1818849785000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
283	\\xb1be2603503f22cfabaecb43f515770e853eb30c3779fd1176d88dea4874545036581ffaf70b059eb0ec7e34088eaa91c8f16da032a6f0082c0792f3c4819c51	1	0	\\x000000010000000000800003d3369630c0c62da1fadf070d6c83f23064924ae3580613cd66140e01c8f5f9a33d32eed0b8b1c333871feae6f3d1816923f089f629dce06859cf76593d9a7ba65413aa8d2f91c5668b3a3583a42b260400c755234982fc698d9f2b239d88d0c9d7cd92b3b6e84c2450016c9db6f94bfe5e414122612a1f24aed1b0d504284d3b010001	\\x67a4d6fc95c71990589aa88b5b61a9b7340fda286385f1c2e83abb2b55218eca6f8e89244a9c7687f2b304d0c34652173dd5a3a8d123521298b5a9d602c32e0e	1682326985000000	1682931785000000	1746003785000000	1840611785000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
284	\\xbc8eee5bac2352971e53fd7487520241c5675442a91f0847c33ec17897b9efef691f89de1d2d69b4a02d0726e8aa66840c228d2766d1f7bef553f65abc4ed7ae	1	0	\\x000000010000000000800003ae9d288f3cc020cb2a086c8c2b8ca81406cf71547698a7cfb2b3591427946a7f1ed0a0e54bc0c7e5c9afca4c674cb1c8167f7ba59e1592d5a673ab9bff5e14a0b7c869a475b3d8a6ca02e0a3087f449e970a1cb057773e8e1be94215141be151d9f7b74a963f0de920c8988b9edd5dd4a155d3fa53d77e4ca4aaeafd1555b2cb010001	\\xd71660f9af86d32d1d2b6268179dafa0e8bee547c39b2a1fa9bf837f6ed4ab028439438e585770c2c956bbf2e42757705ff1b6c958db45c4521abdbdcc984704	1661169485000000	1661774285000000	1724846285000000	1819454285000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
285	\\xbdaa4074de6d96bc588aaec43b322d88d41fe513c6d2ce995038d2748213984d97cc217ec336397a2b10f1651337bd68e1f271eac6b58b453e24142966fb59d1	1	0	\\x000000010000000000800003f3079f68a32faed76f0acb498a95eb6e9593d28749b5b908b407e53b8f933dffd5cb873c7a8547be261100dfed7dabc80da1e086d5130d8da50bdf5eb08c61544033d6e671ce959f0297d1de9bc341816b28e7f04fb6e5e51ab1a3076de01dea1d3c88d48e0a66b8e7950ee753537b05297d7218b8d9d237782e232d3cac98ed010001	\\x3eff8c5f7638fd03f937d21ff697d3c4b46478d88f0a3ef4bb4a075d9080094f5528647922b5a1d1620460f0589b0ee6b539317dfe02f8516c7238029995c20d	1664796485000000	1665401285000000	1728473285000000	1823081285000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
286	\\xbd220a7f06273cc1aecd2981e80e894a9e121d632fa6aca3a5cfe54362b5960c26be9f6df63cba89b915c9abee217e7b099118d5d8d865402e27e5cb789d3e9e	1	0	\\x000000010000000000800003bfc743531f0c8cf3112821d7db1f140deba58ffe77b6be15b70233318e2d6b32794d589102bded97721ae456f3c741408763ec53d255245de64065cf2f58cf756dd7eee8800dbb6259b4c35dda64f109b45000a68ffb918db65647eb6779e211ed045a0bfadd0202b5dfa839a4d1c679d44c3a70a120271ad12a845a0fa6addf010001	\\xa8d40db4fffb32c90ab817aefdfce61a9b6202d72ae5fc369553ce13cb32c48bcf47bfa3a41acd75933d1a611f73bee5661b091affbacca6694c08e8a547c20b	1657542485000000	1658147285000000	1721219285000000	1815827285000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
287	\\xbe92a3a78b0563eba7ac41ef923ed5059aa23a9ff4b5cf137d37a5fe5908e0ceca9a9f3a0be585a59747b836918f90a85558be893370e71231625b341b12d9a3	1	0	\\x000000010000000000800003f610901dd8258fbe20947a1e3cab4d85b4fe179ba6ff41b9533e2396ef1e9d29dd17ff709890733cadb4ac7e51ffd8d37f8f1d156395f8d860de7e3020b7bc178908b38fd424a90e47e8304d09f4a4c2240f91bc745fdf9d57c27626e7663d70e2ab8ca1be706816b50bb78cb234e3d5d6c007389df1cfe9adeaae5c8ec14359010001	\\x2c0e74067437d36f411995fe06b5847c000f6b698886d2400a9a259cd2793ee33b37551fcf4d9fafc50b3173079dba264e9ba5b3fb239ec7ee079c2f75514a08	1674468485000000	1675073285000000	1738145285000000	1832753285000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
288	\\xc59654436997fa90592c3badc8ed0782533886dc4aa7f4c2b81f69a147bf66d2126565a2103f38b0ec32d4e8744f8a3b78a83c0b627fd5a7c2fd0a34c590d883	1	0	\\x000000010000000000800003bf340f6dc6b2a3617a1d70191a6617c4af5c46aeea2b195e0a59efb28a201b236c599f5bdaa8252cbcba145ecc9ed79b0531170dab2aaa1041f6cc0c268582c6c54657824613ae39fd41e908661a993c965258fc71d83831fa6756b1cb1c19907c830526a28413546e9967629cf834e2c4330741e4277b5daf7938905e2d05b5010001	\\xd1f8b75d0ff14297318a0817e136405d73f145bbb13ad320925d7092c4932e6b4d287f95bf062bd42da2a8c6319690597a993df450976f0464153aeee3a2040b	1670841485000000	1671446285000000	1734518285000000	1829126285000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
289	\\xcf02607e2b3e610917cac416dd6eb992a0947677cd24beff4c179e370ad6347f9f94f4e56d45ca92680e0a6ab38567486e3d1661b749673e24b718a436724c17	1	0	\\x000000010000000000800003a8cf0e1947e273ae36a701704c19b8e292a7982f2ba9399eae8671a5feb557bfe19872b370f48c4ded333e8bbe136ff17106724f0d33fef3e2370572991960941e6c5a08cdf33dfcc46b0998860e866231fc195026540458c63085096c142878449317e8440d1df3f8572de93d7e6bacb555e5b2e4c152797d809bb19a2f328b010001	\\x88b791bc57834086261c9b14baa0c18d2d8bec55251d89f129cd674575f55fe3dd4e70b2c9de1fb275a6219ba4cb10cc931bf3bbd8ad8d0ef8f12d757b3d5508	1655124485000000	1655729285000000	1718801285000000	1813409285000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
290	\\xd04ee9366f7cca1835717175fa24b4460de0c5ac7d73fcf7d32918a89f549426f5c8947f18a0ef9bef97261c95bf26229e352d477c2df8e0f46c1123657689fb	1	0	\\x000000010000000000800003acb8fe57d2d7f29027342b2ce7aa6fd07a5f7363447a27bcd0f79dde4e5b554e761f536cb0fc1fbc016f2989f992d1cfe347afd40d51e764d315b4bea33c0375fa5e3f4a38fde6a8810a428ec54a73debffc7d2b1f90725ed27a8834edfb765f3ecb8be1f720a96e9f1b448ef4ac73b6b0269ced3733cdd7a3a6219ca12b9ed9010001	\\xf720958e788cd673d8e58938b849bfd1e2e9c605f10ea1f0550a571639413a0669979f7f31931a82047364ddcb96bc838c70c98b8aef2541717b7fb96b483102	1679908985000000	1680513785000000	1743585785000000	1838193785000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
291	\\xd1dad861cdf633075c681bc556073c3a3a51d6e4f9dd5bab2cb3c3618a3cf2e85a6d390537b09a099cb90721c86623dfbe1456f9dac4eafe7452fcadfb1c83f2	1	0	\\x000000010000000000800003c07223c828bd77312ca3c6d3dee2c560d7408c4d681c7d1e6f455c586301b413a4709528ff28f83c5922e78cf99cd901a7e9af2b13d7f3e2f20f3aa14301f5d5ce6abdefd9354906edc70fb51388158365809b991ccf3aa5d8c872608a5706e832cc5fd7eff9f7db98a536870e7a40372ad4ccc59b9ed353b4b3ce670bcdca7b010001	\\xa27ddf4a7c15963db5866826e4a06fd4dfd24f15f53f7037e0dcca1cb735332d7ca73fca0fe03dda862062c437cf914c66a1c36a3d7f69e5d9552ab7523eab0f	1656333485000000	1656938285000000	1720010285000000	1814618285000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
292	\\xd65e03e9c7a189e107d173ef21abca1143082df9cc5ad0046cef9a8c787cf811cc17b2798eb3355572c028bc62753d9581c0b998845237ee56154e9fff255a59	1	0	\\x000000010000000000800003b37a7d42870c90ce64602e0f7367e0d77d132f0c546539a1c6196ffbc951bfbde1c967c0744fc44f1f5f36067677295592301fea39772bdf490e40f38b64c3669ac7abb8d11320caacb23abce816752a6d549aea26683e34992ef1396bb6f29e7035114bc8a806ddee44f8d15086c49d4de819a140270346b66c51c7e16ff127010001	\\xa05614abdd8fb46bb7e47766212b647262d0584107ed4c6dea82f6583fd390d2a7644ef35dcf0820e185a1aedba6455238050787eb3c29a8259fe3f42422950d	1663587485000000	1664192285000000	1727264285000000	1821872285000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
293	\\xd86e32bef67ac8b8ec82a01ed659cc3e7fc3b93ab46aeb67a56bb51496cb920dbfbb5cbbcb25f5b89a66e24c85334f545a62cc85fd9d888c61f9162ebda37ab7	1	0	\\x000000010000000000800003bd2832293b5dd9b72d8ee4394d5cff2d43e0e29d22492b3bb04008a7a3aa25cde350055457b395f7ad24e702675bfd598461ffef1289953f47f577cc681b3d5eb3274602d1f45e4e84680b4a25289ea6b60a6ba629898298df1deea8719f52bec1798a8ce90bc7685774f9169e5539c37a2ef536acf098d71a0a779ec1d2dfdb010001	\\x3d4d3ef3085fb856378a6ae869142aae41bcd0dbb0f2d9f7f66013b79daff7fdd649be9bf27c4ab51f43ea428a816243c495c742a6cbd7bfa60c23f30205fe07	1658751485000000	1659356285000000	1722428285000000	1817036285000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
294	\\xda9609b5e1b2bda8ff58cd95f015d341a304baa4325b75c9c6a17315b11343909c2c2d54e7b52ba894901323797f04f80c78e50a931157edaeb428ca27b4e77e	1	0	\\x000000010000000000800003b184a11d74facb6907c7e4233073666197545bb7e0a33c98af2a9dca8c6ef65305ca614ce89399fbb71fd2321f5592024aef9d0a500b7f2ac87ffb380afa23ffc59077e4182c9a0034469efb155818aa62ca64c7c9374af0b428b474a3c6a245a4c3e1217424c07bdec3bd5366f8a1200430913142ce66dc34d55a8cc93e4977010001	\\xc732dfd018ab57628028d63b519335d3cb27ee7dde17a1d6cb26c6254be2f6d4f136ce53dc2a2ea274abdc072f3dec9c168a7d7091d8c9417bc5fd9b3000b702	1676886485000000	1677491285000000	1740563285000000	1835171285000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
295	\\xdac6afcddd92472b59695101d0664e96605e514c7b875d041a83c80f94e410dd11391c15c6685389c0ba7f05ff0f77ec8ccd152131d7ac76b0a634274b060ae4	1	0	\\x000000010000000000800003d10d47bf39b4904b4b23164c5d1f3acc645d7cdb7d8a7e0f9d998944317bffcb95b77acff2d9c70eb5f5b1db0b6e8a2bd6df26ba9cd714933b5a589528bd3475cfa2dceecf1d8e5f23a536c5cc51faf0f301b705665a6a6ba5cfdf75383f100b38bc5b7be44ef8a53b3decb8178b4479c2505eb99f4f8d47c9f608a806fab837010001	\\x282ae2e2be587f56aff2f47b72a408a1163ad541c623d4887618989411eea14187a201719af26621f635b40d0888d22f57b2d7f2e99ddf755a864fe676b64207	1667214485000000	1667819285000000	1730891285000000	1825499285000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
296	\\xddc27bfc7a678d0058a3b9ebf9fb77044a19cc40bf61bfd4de0a481c105c4493ff3855fddfac43459137e88aa53bbda0e8fa8bce8e68c5dfea56f49ae3f23688	1	0	\\x000000010000000000800003d4efd4d0d4d2296690d710b2c422efd577f2300fb034205e0ab58b2d11b2228a80009e9ea7e8806ecf9ab4e67bfba2a576f5a06e497ca9178fb3d010d027bf9e76d2cbdf2a47bcf66991c985b9200f456fb951e98fbf68d8116c2cf86b6f9801ebd1dee384dd2065b386e89f127320585de7cb224bdc2771745321b5b35834e7010001	\\xd78e9a22f430fa802afa000aaf65e497f54794b9f85412b91013178cfd7cb906aff828ca5f0a88d73b2ebff62a785d7386c39d368d282f1844b8938daac21e03	1671445985000000	1672050785000000	1735122785000000	1829730785000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
297	\\xe0b24a9264bc63b87d52ba4c0507344cf679fba9f5fa80fbb480d01980cbcd39f20c91b7755c3e73ff4b1b589bdbb472d95978697431411015d2e352543a2070	1	0	\\x000000010000000000800003a33731abbb0df9666b096a56357771bc7ff5aafe1b46faeae90d427e6ebe7243fe43a4a39950837e25d75ed19c435bffd4a674bba2fb9a805230cf8e8e6b0dd080f95238c7005ccb8f9221e7a35d7613342945c83b4377630e4a79cb998b45382768e2f82b7186f1749e94a2ba71808b1ec7e1b04e29c1789bde6bf9ed324181010001	\\xb18401c557099ad6f110ba32569dbb0a4177605e7add62a0f32321d7660262486c23068c0e06958db6b5e6ae5460f9cfb3b2a32c05f5cb915d034fe00ca8d70c	1666609985000000	1667214785000000	1730286785000000	1824894785000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
298	\\xe0fe8484652b6d14747ac3a445f80124e3e95320a5ec833bce15e1c6394756595116606e4be16a10112a67bd3a393923cb9de38a8a8f817191acb19ad5a1bf73	1	0	\\x0000000100000000008000039eb0a3f898b792d0e20237aa2b4bcf458c1c68715ab965d59f339f78ade55ce01d6e8bfd1c5b6f332b86b7331ac5c17a38c96e2095cd5cdade78709e0f35dba6db191c5b86a1fa339f30c9d0b69113db198d8681c2e30248757cbac4c35daff98e7f9ee07c8be7b91bcdfdd201c1cd538bd81aaa3d263f202b76fc4d50e8f4f5010001	\\x366e1db4a8582053df92e2025514b4f1bced0850dfe010328bab22af2e30f12a4f08fb5492bf732e348d34e5d0a221c457ab03754ea597b2fd1968ce6e1f4e04	1668423485000000	1669028285000000	1732100285000000	1826708285000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
299	\\xe612739e71e00145f2664390d92c8f3d06367ea29957b63ac7220df3547feab99f5628b900418161f4f3c8d6a97a656e8a876c6dc0b4dc4677e85207eb93a151	1	0	\\x0000000100000000008000039b9a4e718080142c6f8deee95e41c22e8eb090dfa2b1fd183d412ba60313b877aa74e204b8030aed975bcb221fe321ceba032c7ccbcc99afdca4601bd2a2100ba0114294bb1effdf3da06ee547978ae18d8c98284cfd937ba2401cf9d2c146b0e8c128f2b36df493cf5f2586a7013bc2ea0d94d56bc92691e4b3c6b127ec5f85010001	\\xb66983e8ab4f73ebe1607d3c19acaca5ae141b28e220afc6e14666bc8ec44f01eb464d4b62fcfb44085fa17b8a4d6027f516fe8b7885e11213d6dfe809a1d10c	1676886485000000	1677491285000000	1740563285000000	1835171285000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
300	\\xea4e25c0b5321e7a1084b0ad5f5cbcfbe58b590b63c298988f6b64dbe500f386524f02e30fd4d1340d7de41a7d4c0f10d80e6636f8d3bb7517fecb7a36e28556	1	0	\\x000000010000000000800003abb91557d26b5bd6a12d7e7342fa83a1c5cac3d865d2106cc671f96068a3551129f01a229166304d0ee4ed1d6ce792c0110158d0482b90a9177e939f7ffabc436a2a990471d8ffe3a0c44e2ad73535c43d358cf847b51fd318f5ef7ca183d281a8b02642ab5c08450e617f13278669c72904fc322c9d90bc97f8d37e6b1d976f010001	\\xa7b509f719625fbad2768e25166f1482dcb45241c9b1855e0095d0b15d192abdfc544690942c04d267e20687eb64e9cbff872da5ed9ea109775a29a299754806	1682931485000000	1683536285000000	1746608285000000	1841216285000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
301	\\xebeab3b3dfdec8a0381fa435462f77ff2df821d991bdeeeba9d7c6c2b55f8e3d7104c98ba54aa52819eb02b143f0e317d36841dcaef12f530bb6fe85bed96a23	1	0	\\x000000010000000000800003d9457752dd19ebf029fd1cb402b0429c416207dda6e50402be36b92e5917992b63584851bcc22f53b8bc0088317bc22caf1324f3a4c07228fb95363297d438fa916cf38751f39f6433eea346b0f59d841a7a835c893b5fd7650154e8b3d092c68a81ba7d1d040837c05e11ad71ebc32bdb74e4b8176475c429f9e8ed5adec7bf010001	\\x6deaf96ae5d3900f91efac5d073335e1abfc82691ad4d37f9b6196fc089b63a1ba400bbe430a748a327d2593f84c8ca0c0685b82e9a41ad2fb4e9cf2d90c590c	1664191985000000	1664796785000000	1727868785000000	1822476785000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
302	\\xf2a2a25d8bfe7b3cc9e2ab13ef1b2a2ca05f916658238870bb4faf1a1948970a49b9efcd7f92d00c3ceea7abb667d1bca17ada6686dac28c46a861dbcb42e9c1	1	0	\\x000000010000000000800003af21042f9ba540df32577e6c0695a04c33c0476fc478a0f895f723a46cbc4882f5a849314a7b8ac30b5cf976de5d4b2187b3441ea6384724a31b56e0e43a7a236e5301305a407d2ab8ddee5ce1c93e2b3ae678505b387bd0035e589e7379cbd2bc2ec934409b1eee566387e8811aad3ce7d7393bdf79cecfc9e03bbd56d9d201010001	\\xf14a5da568fae38823268589365d4edfac124f4be5c239a71e39fff6642dd8b1596ed0574f9adc3e9e95b705f7191eb2621a144a908fcda0d191a679c6c0330a	1661773985000000	1662378785000000	1725450785000000	1820058785000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
303	\\xf45a13a42cea31d42f5ec6aaf355b24ccb7ba11a6ce34952b42c1916be6c806b60b9ffd8eb559c6bf85173f65587586f6cb41d9702526bcc12ef28788163386a	1	0	\\x000000010000000000800003b4a7b746734c3586d99607dd64a21f22d9bd24811f6b093573e48efa318a57c942c47e2a3ed5e695c8e78898a37e31b90dbcb673a2354b1f10216c3ae83ce80a890bca9d8d435890eed9870d05023f4229e69000622c497cceeef3cfda33dd788af7fcaa385a4d1a0df8e763eebc9dab599d6c7a1be9830f7e745417e2a43959010001	\\xef11880fe07f53937c7bb859c132772236658756842904c39c440a9da7159e82717d87bd5c2d294bfd6c863e694fd3229ef48649684fbf855c5f38de2a54c900	1676281985000000	1676886785000000	1739958785000000	1834566785000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
304	\\xf696ac5a77d5d0d85de59b33e69fa62c2b1fdc86582521274bcb719a1b2c5e51fb7c30c1baf272e628d58dd1930564301ca01691df2a78499294c7e726bd67ec	1	0	\\x000000010000000000800003a3c1b0f6ecda671c3ea4f9a24256d66da1d35721085c14bf1fb842dbb1aed32b2365be890eb43a726ccc3cd120f1b0d8696981899cf530218d7e6f077e046284060f7a737cbfeea338e7ae415702c5cb2f67cc254f463027fc3f177c5fae203cb324d0fe53d2c6e480c75b97b7a4d7b02043cfb5624841ddacac9487440642b3010001	\\xff7c4ad3f35621f40b568606a374325e27a66efaeb5f07509fb46ed8dcd93117df07ff433007ae5762021451adb88135483e81f40b71e09d493baf9c9f480d02	1686558485000000	1687163285000000	1750235285000000	1844843285000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
305	\\xfad2344a07ec373bf2db6fd80fe3f066e5b1035af92c3755a4b60479f8857b2821ae969f0156716f6597206ca0de0b041b6f345a997c300395b34d5651981968	1	0	\\x000000010000000000800003c61cdb72721558dceaa95d514bfcb3f6c65ba31a77b804f7092b1ee04c3807bc2a88fae228a4f77f18f75a0b5fa138382044b5b904b0b434058065bc069291734afbdafe29a27bf9710e047b64f47fdebb741b2ca65cfaac3df69fa668e8172e0d22a1ccb7d88e8fe902f86bf746c135e20fe4039289b6ae37df7ba3a94133fd010001	\\xd1f8fdda592c6fb86a4e7ea9708476bc5bc5d0f8eb77a25ae8055fa2081a900c989dadde2c12b927e2ecaa860457cffecbd1ac1d806290708e530691504d3f00	1668423485000000	1669028285000000	1732100285000000	1826708285000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
306	\\x003b0c602bddf69cac6b750a9e2a574e69913dc1ebe84db105c51b99973a923d0951e6721ed5fd7362887de2e6cbdcc79af7dde783c02aa8a55b3a87e696d196	1	0	\\x000000010000000000800003cd4d4c309690d5fa9e951db580b1392b46669676df934a914f2338df0376606894428de7a85ad2a55b4c559e89982756cd23f660d1cb1c981b8757b54cf5f21fbf2cfcfe347eb61b4da637d7d84f950d89234accae865509f1b5fe507d300b3c7bad0808431394cbe629fddc356af8bb0e7d043af2dc4b22858708f7982a82c5010001	\\xfb2868a569d93a3f0725ad4e56e86ac1c6fb4bd9651bb51456c55d7daedb9717f511dd203630d078e32a8f98eced17cc4ac58ab7bdd2e0b8779d3e9e03553b09	1673863985000000	1674468785000000	1737540785000000	1832148785000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
307	\\x00031822dfcd01fb5ddf3d1b22c23879e60d340a933b3ed322d68ed7cf6c8db652990eda41d5e250df0e8c457be7333913e4fe1817da2b3f0b7c0ebda875027e	1	0	\\x000000010000000000800003d9f07f451f30d08b232acf293f087b95c93ddc3410ce6b34ef1681ad78b8efb6c313f686f471ac62ff17d2aae916beac7ab55f7727e145305c097b6daf4e3b460f2a1c3e47d39b9e087ea26bb2278360048d3b3c7a818da371dc95c42c0a5fd6bf276dd44ffaa8de9a820fb6c5478e9c2e61194248753120935c048eabd4b5ef010001	\\x575210b7ff1ef24ca359ddb0862aa4a95c3b191477ff97bb87f19eddebfeeebb5fae0e0146d378fa105d0272afcedd8dbfe8192d6bfb2be3755ff67831de6202	1664191985000000	1664796785000000	1727868785000000	1822476785000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
308	\\x01d3e95b577f7e33adc242305f70395052062f9a5f91ba7050f6eef584059fd1de45547a73479d33de8afd0a97461cf95f4ccdd82b175c5ac33c9f1aefbb9d37	1	0	\\x000000010000000000800003ee4f54253d051038edcca457662de3ec1e0139469db3ee1d2086c488a0b72e72f9cf04387679b82af498db1536df81d161cb2e7a9f58ee04788ede2ec8cd8095a22db0c7f28f592f0a5c53c586b6a6c7568331c51edac0a33a294bb11966b2f0b623b4d5457422371945084276d81a496dc43e7d2ef049421a6ae8fe27c8a625010001	\\x7583cd09fd061a36c533e6fa59f166b4e7d9835730bb5f9fe146450abeba4f6a3a814bf833ddc524a98b687db3047a9bd3eb34d0548aad1c04a9dc02d05c4104	1672050485000000	1672655285000000	1735727285000000	1830335285000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
309	\\x01ab1e043383489d3946dbe8c500ae3ea2095a9748e6045fe795773b4dbd72c8743951ec1e711d1115b46eeb2cd9b6053c0afd63aa2eaceb005bca5f88270314	1	0	\\x000000010000000000800003a703924cc27c42fab86bc1aff99d209e09c422fe337e80968252d095910804ed10dc99bd8d908d2f2c70a7b63b69d5d001200fe11994ad517f5ad616445fa4b17b8a6046b48166c85f59d94440ae828c355f2c29a28ee18af0b78916567ebaae182094ca510e95165f22ef1a5ec1a8fb183a777d333539148498b3eea171024f010001	\\x422b2b9ba2b5c359ee1c15da188a2505088b9ba20817b1d24dcbbc495f6197ebf78d494f6627e71490127a8bbb2d520e870e92a98a8f690627cffa809ea96803	1665400985000000	1666005785000000	1729077785000000	1823685785000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
310	\\x0377c0fc1e224821f23d0648e5b001f16d56bd2917ac3af6f4a7d459ec85f04d4def794ea9337a31df73555651ec34e10d5d724e77855a8d875f05af2fcb123d	1	0	\\x000000010000000000800003ea0a598d39869640ac159079042aeb6972f97fd9551e855df5c778aa621050d0ec8f3d4efc56f11869f32f4ccb425f4d0326a230986419f0470fe00c4e6fdafebccaa4bcaa01e452be3568029265924cbf7cfe0aa0597448f34a8b2cbeb792fb828f5318e04543512002d82dee861971203433ed2c2549bd4c79eb0fc53e0acb010001	\\x857b88b91c0b7dcc42ce5f9177ee51e57367c2e8a9d1878a0a68bf52d70aca0d6082bcfd693dab2fe0e514a1bba194bfe90c09043c125d87a105f90c89e4e303	1679908985000000	1680513785000000	1743585785000000	1838193785000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
311	\\x095fdd29d30d71a54b0cee6e2ffba565e98fa0c7b41875246a224b26212fb697606421417be15a0cdc4ea7712d2464bece4f34568c9a513141c43dbb37006f7f	1	0	\\x000000010000000000800003cb2dd999053dd7b26947b85cb6445cb286f87657b0aebee6246aed1e17bb22a856b7cd4ddf3a541e79fe1c82965f314f7f7655ba31f9b03615c9b3ce48e4f3c6c94b377176042820f671224fd68890c80d1c7b42787520ad8ab0d60e1a63875142bd789248ee7aa3465219a6e97f65c07d0d068753edf6363628225a550089a7010001	\\xdd316f262816e31b96b7f89bc5f39edf7ef740c95ca2f00d13ae9550944df57252d8a71233170aa935624b59f095f56e4de3c7e28f0e667368ca33e291e0d903	1669632485000000	1670237285000000	1733309285000000	1827917285000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
312	\\x09e396cc4a718cdf1048dc6a469a12fc75e3ce68a5f2419f876213b7c1aa1f4b1fd75b1f02dcb0b5cc9a22704bd0758946ef5d78294ea1664e5c6cbbe178148d	1	0	\\x000000010000000000800003baf48af169f2b22d30327df2be092be078c9e3fd5f34f853697c9c8decae817558283126d2d39129ec553b4045488fd0ee2be4426652fa44662e17e7f5557f51fc690b0f864c4fef192a713e85ef0dad31b55478225a161929ad288e9931f4081496b50f60ddf8cf91f3e07a46cd1bd24f22e57c6e3f1bbd0836a28ecaa4b30f010001	\\x36e12449af8ff6a828241e8288fd90382eab5f392486141819af10105ee2dff57b418ca7b54525e8ddafbecf1d7033b769be4fd365d991ba9531a62791601509	1665400985000000	1666005785000000	1729077785000000	1823685785000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
313	\\x0b47126f67c61940b5412278960e26aa0231bb9e3fe09bd5ca65aedbf8091a65cc7e01aead372b5c7ab0055ff993e56cbe40b1841c97c8828c8bf8b57be90d6f	1	0	\\x000000010000000000800003b0ce9abea60504e35573ef26c8e1bab1b31c0e56c4c06e4e1bcac31141dff3a36b3d5981dbafb1ad6d593232474a9a4e05844fcbf2f4c3fcd8856005095f9f916802022eafc2b0ee7c7d5b2952716c0f7bdffc9448167dca41e2856d62e7dae243e9b5caa79f193c42919b0465c7c1c52666d82174cdd99dd6627532c2b58379010001	\\x7d6b78a86135f3fe811444366de23f87edd60d1849c643115467c2861324a8d3e8dee9e7a96ca22b999ab7082d96c68fed983d22ac52ecd3550719bf474f8404	1678095485000000	1678700285000000	1741772285000000	1836380285000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
314	\\x0debb50c585fa59e1f70d91f1e5ee0834a9ebaa2b11fe25ce7ef012ae5d8bf2f7f449850239ce6aef0e72a68561c990b53afdb6a2e99afc4fcf2942b0fabe4e3	1	0	\\x000000010000000000800003e5cf3e0294fbdf5d62c405296eabe9d7c55c55843489969e840430d98ae8a00f8c3fc544d3dd7c8cca31a75b6e990c7f0d179f232a4222a62af56d9ea83ef5d1597ddbe6e5c5d60447a2dbb687fa2347d53b250e404812222efe79eebc612bcea0a17f9d5170f1e42edbfae2189c1d93b8729c8e962c1eb997096036e95c3515010001	\\x4e78800a327bb4617cd82a69d1b1cf1c4ce3ee572d7bfe76304ec6cbb24448f38f38601d6e3046fdc6668f1896dabdeec8d42a1c788c2ecd3d1230d0fec76f05	1656333485000000	1656938285000000	1720010285000000	1814618285000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
315	\\x0fb352f4284a44f44c63bf76bbac989a5168b2eda763216cff4a7a82ab3195aee4f1d6fdb4b23dbf37364ce305be429c97f9742b48b15a49f570538dd14a9a5d	1	0	\\x000000010000000000800003ab87098e32c5f9a2f4e0f644761c7020a78ac6ec194a633111af1c27f8a1fe7285419c602327784a379bb1ce5639cdfc4c7a48511ab7b7f643b9c9ff5a76b643727ba5185d5cc4062c12124f5db5545e7f71ff31c41e5f778d9ae00a4522714fce94298df9b49d327b32bc94af7d671f2ae79c20091fd2d9818f08788be40dcb010001	\\x4d328f34701a00e5d9d7db5a0386efc7875052104b7525af4ce9b84ad41a9d0cde7fe02b7a2df5708787d7cc694702bc761f81989ee247d9d3e076613c3c860f	1673259485000000	1673864285000000	1736936285000000	1831544285000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
316	\\x13a7a4958000efa0b36f8dbc2ba1315e20fba8fbfad126d2f30d65b505b54d50d2804357b77595b2f24e4ca29b3f3fe952f3e6b1fbc1ac0de941f9b469246505	1	0	\\x000000010000000000800003a4fa81e3f1cfa5a8fed92df718b81ce9f3a93f41273f0aae4e8c4f3e239062c167ddff9715f306e12c27332b9ac1437a32538186a6ccef60594d58052c9a23986e0fbfed41dc6c684c82ad832ba93b71ef5f9ecb06105f893d9a220596f4572b3795ff679be4a07793f4a4ae011ce4bab4ea6619dfabe8d92f1afbd508845601010001	\\xfa457cf7aa9ada42483b9988d2b52cb17b959dea67f3052c620c4aa1dd244582af55bfe729d5fe63aee580595b687806829ce4e153aa9d42182eb5580628f50f	1681722485000000	1682327285000000	1745399285000000	1840007285000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
317	\\x13fb80391ad9febb31ce3bfb82d7e69f8bb2f4541574a84fa95c2e8c7a5eed99a2d19c5e32203ca094253b8d6ce7e5acc0f3343e0d64fe65a8c2443d1cda551e	1	0	\\x000000010000000000800003b847d397073d5c1fb83847629197a4efba8665308b0b65f2d2df8534496756501c3d309a26c91942bf8d42e57a19b278cced5152a177b79c454f1536604c5c00bfc5c9c06d187f47b5d2cbc77edc8770514e8b392c5d068aa5591e0db0f6e7f131a8af4c9da95fd9b3307cd923fd46ca6b9ebb79464c0d8110721e2a1f9a1ac3010001	\\x818ef4eca1cef73d1dd4f00b67c3e56cb66d9fd933560fb1ad1607ee6c234d573e5d8b5b93855ce22480c54d24ee493fafbe3e87eb8906509ff0994ae008c20a	1676886485000000	1677491285000000	1740563285000000	1835171285000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
318	\\x1493243033c315b47822d6b44467ce5408dfcf327d21454e24ffa3c66a6e84554abdf29904eb08aac41a9591bc6c7a1b4c6ada9144e7c83f9d93c0f3bff8205b	1	0	\\x000000010000000000800003b9711c9ae020580850c36a2a8f69d493624f0f4ba82ad137934125d1a0680253d0593cb34927cf15ed069dd09532f044cf6ffa1c77a7652577fe7f22545d685924bccdc39403d5c6dc1ad7d266d4165142e50e2aaed5ea8d3eb207570d4f6f6160aba4c4dd39f1268cc4dd3788fd1379d7b23750951ffe2ff5e0e2e4b8b5ba05010001	\\xe97ffcc18862f97dd1ffd3b004f56ede4246b8ed3184a439037069fb27e5fafe5ebb79f368f01e483febdb3e632fc9ebad45b1b5a712aea3ac1cea7cdefe4c09	1672050485000000	1672655285000000	1735727285000000	1830335285000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
319	\\x154f272a86c061fe29a12f7002aca36ba2531fba8644b82d770c3b0783f5500e4c83978e5abff898c440e8d87a7090d483ba86586fbe3edad6309580b6175c92	1	0	\\x000000010000000000800003cff4ed1bb09ac049d01911cf0676c055a0872a9b0a7eb01c2de57d1eb668b7827fb1860973ef3acf18973445f7dc008fdf3851f21211c6269cb112692148deeb5fb0f6ec8fc2d867495973463eb00f908566c04096177281cc60fa483b91b137c35880c1882465862536594224f787d20b991690d48ee5f17e946477fda1f121010001	\\xe80d0a6c10cccba003708e87b044974a31ae566223f8c3f092454bdfa0798e9c4056eb88e410afc38b26df4b6b0d4a48a79f335eaaa8f360255eac2608582a00	1670236985000000	1670841785000000	1733913785000000	1828521785000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
320	\\x16d3441bfa8e9f1b064e80be3f10bce860d1ce1ae877bc6964087d93571dada76d842594e76e25541d464bd6f785ed8d3233d7ffc13efe9e3b781bd6fde15bdd	1	0	\\x000000010000000000800003c4a24d0594369c359913edf1086855d3250aa6e2519cce401242cc1d10c47a2d2ffbbadd3f012a23e3c0cd84c72a5584b58ff72a9d275125e377e6de3c012b98681ca0f03dd5fd9820f7ccc2da89e6a371434cf9ffa873e6639fe1a3b03b14f057df3f17082892a7780b70794adc65d8a84a7c8523629c4a0bc95522dd3fc5a5010001	\\x424fd8754fa14f2531340cf0c69eb8a564befbe29c506fe8d0a6286d1ca79749b663b7b9c9078d493767fa18ded65baee91f1421064f6aa5f5f45a26ebd2e206	1675677485000000	1676282285000000	1739354285000000	1833962285000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
321	\\x17234afdb5aac4520bd3df270ae1062970473ab1006a45d6e1a961fe71f3e866d69b1e6340391577f042b95bd4a28b410b7a0a74d15d044888da01873100b204	1	0	\\x000000010000000000800003cdacb59d29e593bcf65902b4621c258539331130d252367008f881215c0a35273cb0f1ee1af8a1e43cf813f6b7d7f8d41faaf46c8bb4eac6bdd1fe6791ce90c891c5a5b8078745d1c6336197ffe4fcc035e0f451c52ae53f46080501d04df76ac9c58ecb73e92a588687686a01aef42c2d5f458f66915fef141f4c21a2d4e7a3010001	\\xf36d17f8a692864d6b0b02b7d1b1eda81718bbfc086796bc239d1d1e80359b90394872b4f73de7c6ce380385cfd8c8ecaa11da7508e8795a7979af6888348909	1684744985000000	1685349785000000	1748421785000000	1843029785000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
322	\\x179742a270a2c1b9204becce9532b3ef6e5859443a643c2f06fe2b8291a038bd9b0bbc0651e59d701b13f362dc938c674b9f4318c0b637a8c8dcd88a515768ae	1	0	\\x000000010000000000800003b9869a91b963270027fbb0b328356e4e97a2fa2af32ba573bfedf82c7f2da97bf10719b86505229d517df8b682491c9e4abb14f181d93a7c48e9bb84052b73c6e32dead3201a3fd8d44ca03ac8e9eaa7d1e3b2f411b2e4850b03683aad256ef6cb7dcfc87d93c44936205f938f6b4c89a4389a3e342aa2145592074dc48bd351010001	\\x06c61a2f5f2cae4c945188579069ff0275d3409b6822efca14584349e03ffc5b81673b7f05406d0d1437c05835722668f6debe65aaa1a971c01253653fc91408	1678699985000000	1679304785000000	1742376785000000	1836984785000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
323	\\x18f300912dbb5c1e06e9561106bbf94fb0f1c8c2773a80a473adb0b429a553fff45424dd9350d4c0cd55b88d3eab66ef4512aff31e801e9d714ef9ede4ee548b	1	0	\\x000000010000000000800003bc89835d6dff14ed1f83ebc1c07a9c5d35579a687e4a29237ece0e084b18ee0e2200584a89ab78bfc493847b27e6329e80fabb5e374644ccc54ec96ce78e16477fb0b38cbecb83d7225232bce2045a3a252bc99d6fafc8aac9e403fe4a0159fcca28d941b49f0c4ab401515f02734a654eadcdbef19b68290dc34ad86610522f010001	\\x5e887297f4453dfe98a6da78c7b29d91e6257288685be4cf8b773152b33326f91313af9d69fd1ba4ddd99b9b9eae94424793a1b4baeaeed5ddc3e5cedad57a0d	1684140485000000	1684745285000000	1747817285000000	1842425285000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
324	\\x1a978ca4bb626e3ed8f1ea604da3240282c9afb387d88ad06bcc50b3c0a3a1b2be0e0e468c1b7884561a14791b1bf83d8a214cc4a4355ee856a2ac0ee342a2a5	1	0	\\x000000010000000000800003e08bac35c8ef377c406cb8a6740d78a629c7fd6008c57bdde687e7a67ad7e7ea9a12158308a92d0e7d1b0dfa60b61f4273fba4849ee705c5a6a3ff1513bc8bb925549d93f51c8adb66e559ef36e61edd1fe712c85cf372b421315fb86ae1e4f0e1e89633c5c7cce62fc75ee5179cff9b0332d72a721fd05058a03c71da71f84b010001	\\xb6fe657401258da3cd51e2c9c15b5ce64fb187a2741879efd72d3fea41032cc3589da9e527a3730435b17cf128157c6e90eef605fb294038b5cc69db013bfc07	1664796485000000	1665401285000000	1728473285000000	1823081285000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
325	\\x1ab37b426f09c73b624a9ab004367c4b352e37352cc6bf4485936468e5cd2f9a65a3e4581b036e7e029a526b7d8f0555ef2313bb0be188332c62f05e1cbf6d72	1	0	\\x0000000100000000008000039e6faff9137e5d26fe17ae76b3786d39fa410cb89344e73cc4da2d01dbb72850c69d574fd2145ec26195aec232624d38200f3dba950e4607e284a0e981dbf4f0f902515ab25cfff8b89a8733d7e87a9a9b55def599ea280f082d4267316a5a7ee095581fbf53639bb7a2f117a621437d04560773c1e63acce7fd144e66052a61010001	\\xc72aa3d1dacf4a04784caefff26c63c0c471cfd5ae8f6e6cc9ddeef9a839cd5561ec172cafd4a0ab9e9c9e2317563ea51386556b5ecfd66543bfacecb879e105	1676281985000000	1676886785000000	1739958785000000	1834566785000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
326	\\x1fcb99657b877b039de15cfd291aa80ac46d9f422ba11ab07d93fac757c31d9604e77c17543eae44241cd7699ef02752e50977186cf2e30156f99a4313706920	1	0	\\x000000010000000000800003ad343099657034129d73e46e1ec763d6de13409e6557590595240549244434281a94b40f7a08158211a5f1824a62489679fb51733777df56b72ee14144629b2891919f0a0dd745030b5991f3374b5f2a116a775d5c623b417794a8a396519b784898dd9fbff8ad2bcfe57c8eb45796c0f597bb31d612b56e9da0a2827a787dff010001	\\x4c8500eca44cf542665d5412dfeed40a1df739ab667dc9df8c248d4d1a2faf4489309b7cc32ecbd1a51353c8aca19028cddef504eb11ef946554bc3d0ef42100	1684744985000000	1685349785000000	1748421785000000	1843029785000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
327	\\x227ba555d98e89f77b3a3f2e471223cdbde37c45c3d6a13478f37ad06ba3294bc77f7332665886e39a1701dd44f5edfb90c39ddfabda32d83e700c0ad7018c8a	1	0	\\x000000010000000000800003afc2249d98f77e40f5eb1619ac26d6cfb606be02f31604cb81f5bbe06805ce7b8bbf16aa076f4d695e8c3a1811fdc7ad92d2bb5014eb55302bf171b0844057653b7b415c83374fb0621baa4c448229abea5fc451cabe79e68329fa5fd8c08b2a6ec2c1ec833a001af8044a96007a2199cb5ec109bcdcd56ca399cdec6ca2e019010001	\\x4387bdf5ef634ebc2384e8db03b85604ee9bfff77ff86dd5482917a3527abe1c4d4e2500bb9bebd2c8c46c624790fc7d253dad630536255a20e574c9f7f27809	1678699985000000	1679304785000000	1742376785000000	1836984785000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
328	\\x233f770410526acdc3ba297a0676d624704329f8fca2c3ab1df5edaf01d95ce883a67e812e57abe929428280be2b4c4669caa9a7128ee3e3270f996647570b05	1	0	\\x000000010000000000800003b0d02665b8f24dad9afd2224811bf24e8a0707ec7dede475c8ea1a3501d09c826ddecab9c00d763d66e5438db63cc29b0339985dc9d1b612ea9bd09eac3705998803c3b77850dd005c7450dbf9ac2718a700439d35891e7804b7d88470d0bd2733b7b589186e464e0c82f6b5657f4269423fa75193b5d6aa8eaf9ff75eb3fba5010001	\\xbfa46b5c262693244afe50e4ea98545bd4270f9755929e348eb496fa2c1edc990d87e9f13dc501b016bdb8decf485d2839bfe94d81a6180eece71e527a5e4304	1686558485000000	1687163285000000	1750235285000000	1844843285000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
329	\\x2683394d5ecdcfa15b56f0cc9ad36bba86851868db1189eac0711455b7994c4cf05a38fa559a9a7f897395f2fc9e058487e6c0b1bc7854234dcc6e6e1fb4c6a3	1	0	\\x000000010000000000800003e44ef1b2ccc96f326928cbba115e75ca2afb04ca6d6b247f04ca32fd068c249e414d9a06cb90c298653136080cbd9397b3239f4073f25ed4f7bf54acbe51fc3cc4457d03153e52d8e4f4ce27d23e4bd34db727740fc8419a0234636385bcca3c82a381e83af329a9bfde92fdc739d414bdb91c27f131b898e60d0d2489d2edf7010001	\\xde1b9e4d6d0d1a96c3263015debdb50b92487ec7898b5775302210a96b91b16072bb541144291b4e28686ca37449a26a65e609ef5584462692917e8d00d6960c	1681117985000000	1681722785000000	1744794785000000	1839402785000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
330	\\x260b6ee6af5c22731d2abd4ad003118773abd781fdf8a10ef2f5b41af898cf67082080c0852b0ee55356e460240652220a1300750f5629968562e63ea3eafa66	1	0	\\x000000010000000000800003b36095a92db34993070aea8bdbd049e713e188a9e556001089f1ca0199244ac00218e8f08ea2083ec39b66f807551e6ab14fc3f081edcee51c15f9dada4eec94bb45fb455a8930732b42e3122c8d3b78d01c4576d915bc6863a4110adc4b35499195a500edee2c91507804fb127e50b8c4a495a75bfee268a7ec79d021300c55010001	\\xf8906e697a7575b1bc830cc111662e6e6420f8aa3abfee72d5832a942921c4b94ddd0a6486c66224a81c1d02cc11b43ca1ac6b5020a72c7e97eeee0f42b85e07	1675072985000000	1675677785000000	1738749785000000	1833357785000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
331	\\x2a578af1214c82721b4ad0dcc0e31d96b969aafb2d1c636270548c24f15fa4146da350e5d80c42b025813417222f83ffe3ce5995052f7af7f7f8ed48cd20501a	1	0	\\x000000010000000000800003a64263d43a924fa89ce81ea554d8202f9f78e8bef5c1a7e4b98c06073d4038119550188757d8fbacc7dc1fb212731331a9244c5d84ccb92bacf0898b1f09439a70b86c8de0e5ce5107e7b7e910b796cd4b2f693171096f222f41296c1a26c91af974c7779414c6e5e5ba5c9be1ef945fbc1979f5755191716b365f0158b01a69010001	\\x2bae8bfc0c9bbbe1b24d1396f954d3d55dfb3844e829bffed626cb50a6150eb084c1a315ea5ed14e841a04bfd50fb20e7877c3402c89ca06421a1e3ef750cc0f	1671445985000000	1672050785000000	1735122785000000	1829730785000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
332	\\x2ddff52c68f44e9bdaf6039a0f3b04db6e39015fc2f9ee9d9ef08943d3b83e2911db0b6571d74dd18b5ac3271a84944923fb61708f812ed221bc7ea7d3d13cf1	1	0	\\x000000010000000000800003a3c3c6c01fe0411f232ea15016c249bde03c6152837595826db7ffa200578e572899a9a2185b531bac2cf333109c6945adc0303400ab43d58de044313b60525f396eb8077bce928bb30a0d4752d7c9d1b822814067a8a8caa0aa22f67873306cbd6634b0c7891639edb6fd3898342bbd0fd75e206c3c56cbac234a1db3083e1d010001	\\x3771c6b869d97420c0ad84b3ef9bae11a0805cb48dc519bdf76a917f818b41e4556874f36270c3cd96d3941b24386c5d4b08d96a4886538970bae11dd3e1f602	1672050485000000	1672655285000000	1735727285000000	1830335285000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
333	\\x335fefae2891189378d7fcfdaba2366cf51454132f968759b080b750694f9d8b351fa3d43e959e2816ad107b4de44f85fafd4278de9ddcfb49a7151d6030812a	1	0	\\x000000010000000000800003b6ab3ead98d37cbb703585a20cf1a7c2113e234f498d12cbd0aafb71993e6a4cc01b27e8d9fa304291ba7aee5969802d78a27460313be42244d774c5aed0995765ca86e777bacb0e0d599f262796752cec0335132bd69ad6e957bc24a1d651b8bb5eb15de23f76831a53ee9fc553986ed16c756d3d910649c9234539efc27945010001	\\xc449935c67957499aa6f0f0b23830759df0e376922c23c936b176882609faed35439d65d1b6a02c36836d457dbd0200d079fa690ac0bb40ef923a2c5e3e8fb0f	1670841485000000	1671446285000000	1734518285000000	1829126285000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
334	\\x346bc1b12acd1db25a0af81be12b6022e548ffbac0fbe64db73365bb7cf857922d16fe1d368f0c7b406a21125fcb2068bed38b6e82856659152950503fdf1e4d	1	0	\\x000000010000000000800003de2d82bc4b1ca44cfb3c2d7e2e9046cac9149306ec37e633232516fa9ee77a0d8e36c1429af22a2b856b70f1d0d0f6e835c0bbe71db25df0f4835f08cdbac455d069789f8bac4772b85af1c21ee3f69ff8c4f9e9e31af9dc39987d8e02637502b7d4a6b62210ffaa98ea8ac0578da2a308efec6aac40ce8e0523051a3caae7c5010001	\\x71fc4bf2bbde04d0db28fa444eb606538d7d0ddd3411805ec706b5ea5a15596af902c765998a3d9ca4446d0eb05092bf495efa1eb8d6d71da43edc8c406bc70a	1677490985000000	1678095785000000	1741167785000000	1835775785000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
335	\\x3457bbcc7709eb41f6019f600d6fd155a934421cb34d66f6dc6d54c041ef4ce1a65bba030138ec95542a99519869bb872d7e4e0a005bf42dde3011969c311caf	1	0	\\x000000010000000000800003cf757820f35f3ebd19630613ff85b630bbea3df2cff59ccf089091b56d77797b29320bc8aa082ca5de563b5e842b0b10a78f9c2942a8792eff9bd911e741a4b0f868689d54576692d3e1012f195902b2f0a27d5e86f1f48e14fda1e50462907255335065f36a49ee63734b965fb381d3f8d621c7d0a440a17a2440fe63af40ff010001	\\xc83384c9e472ed63eb480dfe69ff3bd42cf6f8a78475a7c989ce40706cb8673b3cd07ec16d0685fdbd4335076732a95c68e04e5ebcba9a305d617ab86e16c007	1674468485000000	1675073285000000	1738145285000000	1832753285000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
336	\\x356b6afd418eb29e5ed26afefe13c8c28bb5b8d7b5d52de3850879a86a4747a20a9cc2e79fdfd358af940057d46eee8621da599a8b03180bed932a2e466776bb	1	0	\\x000000010000000000800003ad19460226f604bd7e5ee6be122f1acb980f055686ac63519060b46bdff0809724b2a78f110aaff1e1008c659d83b3d671ee26840a7517c367bde8a25a0bce5ea17284914b90dc30f33b110304d38f43c9bd966e758d434397cbe88f1e373a581194fab67e2c97d407e07982e2e53a7ddda4a0b64d223c4024ff03a6cfd6fe0f010001	\\xc63d3dd61aa4f6e5bf0019fe17ee44c0211434cf9d8aacfa17d270d9ad2504beb51470db35d4db13df885ac8716929e0625628125bf8b6451ab695ffec94c204	1662378485000000	1662983285000000	1726055285000000	1820663285000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
337	\\x3673d2933a2f27f389bd74e7b38896eee9464502c2ac203ee7c44eaf881fdac24de3a97b6226369b9618b41f480bcbc6bb922f96d18255a75f9918e924c2f8dd	1	0	\\x000000010000000000800003ad9459850c8c34b983cfabae609cde0e222c863cb1a6c7254ee80bb19c27b830492dfb499a5d0bd14dffe0e2d42e1739a6e43347fe7184bfaca72317abe397f3155e666eddacb1a5757ed46ba6493203e1a29a9cc766cde4fe03f5f7f433b5dc0c435f6ba439b1c72f9c3a7a2d87dee05f73425b3f08f02ba07cdee0feffa53d010001	\\x800c378196371498597985b3e8e9bd18d205b331a09af2c4a0baf1809a5f0b143996a3235bd56aec799be9fcdf830964a1bfa44a91a5def11a98e1f064f32f0b	1678699985000000	1679304785000000	1742376785000000	1836984785000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
338	\\x3923b3d5d0fdbb3a9655c2c07b64de679a9b80a270a6e7d41483aa58b097f027e248b522ac17cedf7b4c11f223be57dad828a506990513812037282c03db6db7	1	0	\\x000000010000000000800003a39b84f69273e1580a7d177413ffaa0702554dd1d7b90af44177652697f8188a7dcb8a207bbb1f09477f331c916a4e53181ea4ad21a7f6a9bc8ef7db3351149eba1c61ab50a85597a0d9c69ffce6419c72306b02bd25bbb3f081354b260af4a9cc371ca160c1021890e85165852373d4a00be6977c91e9c47074a3aa0d69bf5b010001	\\xd4fe3df19c2a391229b0c186e772c7a90a15e9ac3dec5badeff31221dfce6194f918bf132aac695dc1b803dab044134c1d59702e2ccb79a0493936d1acaa030f	1679304485000000	1679909285000000	1742981285000000	1837589285000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
339	\\x3b97c6126b32d9959b27d3ae1827f62e86ea4d55bc78cd7cc1c1e8d7079c51c2036b98a2a8d18704ae89bda0d86af86e33f6c37c1244ea7b7b24a8d747bb649b	1	0	\\x000000010000000000800003cbcca01f966dc28fa960eacd3ff7a07e8dcd70637344dccb6033603a1f4ee59f30fb2b87e18525a13767a07397e3915bd19dd9c7a8b341310fc1e6fe048ee19463982893ee6a85ad1282b1eb34b39536e606edb0aea441fc58d9b1fe094fac6a829360f19776b2e41165e99509ac33a9c5809ce2bdbc17588dba574f3ae6248b010001	\\xfde7f951058e81fa1138253d607e417ff4bab2ae2ea77d34356298c44b54702b062b52110d062c6bdddfd6b3df8e9c5fb2988b68fdef4ca9f8492a835617f30a	1667214485000000	1667819285000000	1730891285000000	1825499285000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
340	\\x3d8bf2b617736f746e827e4bcc81c2942bedec836a795ed5abf7dda4ccb3e1b25999cb51d51de09336c5e944e2f3ab2b5d998ea2e62606d91422acf3520cbd9c	1	0	\\x000000010000000000800003bf1e5b606417d6ceb7b1f2af1c4d2df026f5922197ba67b90c9d2fddf56df70858e884b5dbda904f1be244f975c14cc26adcb63a2a7c1e7712bae99c652e3fc2742a722157acaaa012449f1ad40eb9beff56126de2c847d8e7de022ec1bc60d6304fef8759c4c2be5b0a1b195d9c8b362d54dc18d7ed957bf6ff1a8ede970585010001	\\x39aac1386883b98308a0c2d6aa82dbeacdcee918b7e3ffcd0e6c705a9bef3b39af2d58e023e669a45ebd3be0a7ebdf89bcf5b982abc07753e61071eaa388670c	1669027985000000	1669632785000000	1732704785000000	1827312785000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
341	\\x3daba86567b7b487ce5e8b041ed1a338fe4285557916587d2c093076ad457536bf3a9dbddf80b9393dd06668925d8d818245438afe12d198aef0ccb691123a69	1	0	\\x000000010000000000800003b226d4f4293b32372a8fd3ee3ae7088547b655bf89203a8335e336538accfe536500bd101c42e268ff1ffcd2b04f516bc244292ef253f3c99f52d7df7bfefca3d55df1bd107d06651ed5a951f712f12e194f58ba8f275a5ddf36cc9ff9c20c3f2a67cdbfa2f3e0dce98efeae12247246f064ca3f7674a052661ce185d7063c0d010001	\\x591b99d98cac89311c105e9b1776dc8c7e7867fbf7506b1d440f09b045baeaaf18656c735fead8a3440a74154481f8e2132704b3d597f62753351fa26921cf03	1662378485000000	1662983285000000	1726055285000000	1820663285000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
342	\\x3ea7304fd7d8846fd0510bfabfe7184feab645045012f5693f4f3bc698c5d09fd05fa0824ae6fb9378a353a34390c129857177187921c879a3ed6fbf5551bd04	1	0	\\x000000010000000000800003b03d77d2c7eb9dd889c5eba9097d937371ddef2afa4f5b3df776e04b713e4be0ea752f19671970542f3247b41c678956d8f9dc4c819b94410296d2d2894515a3bfe7b244863616715c110b8b8753f2e3e99ee32c5c5978de9f451bc6dbdd8d49347683eb752dae1583c50d0a007a5a62f4848d452122616371e0799ced8f52bd010001	\\xfa8ebb9716ca7b148b1521c423b11566394e8962f42cfa4f6e72ea8c68c5ee3e5e6578e66215795f20cc5cf194b67516ac3002c20415315f397ef92d75ce6a05	1668423485000000	1669028285000000	1732100285000000	1826708285000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
343	\\x3f23accf820ab22b4ae1b3d0c7ac1cc3781a95d151aeabd7525e5373758518c580d73366c3973c9d2f5325563e4db137d727d96d3449a9cf6d57d36c05213fce	1	0	\\x000000010000000000800003ee6717841c138d79413ae08df41cf5831f441e9b07d30eaed70cf0e1e771d6d25db83523cbb494221d1387201b5119e91bbf0e56ec819d2b39af9120a5b9428aa938b3a30fd77fca8d025a9f3fa32dea72925bdbcf523006f70ef462c1c79bf02f31758bf63e3d9d0c2443fdd4eb309c8239f5afda50ae2ce7358d247928a067010001	\\x53df523976cb290830c30e100158439457260e44ebf33384d837cf18a8e51bf86324fcb6855819b685963628783c5a3486267c88b8e8789e6f6efb8dbea08b00	1683535985000000	1684140785000000	1747212785000000	1841820785000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
344	\\x42db60847485a19c009e1fa3d9f18c7e94350d7cbc4cd80d7025b518d5dff2ec84f14db1f5997e52f9792da61fc865f2f279fea5c1e06797435a1ee5d5b3cf69	1	0	\\x000000010000000000800003c7036c658da51a36c1d14f276baaa8d31164ab40fe875b452d9dba35ee11d40cb9003e41b05406b68f31a91a462edebda7a64f846f353d71cf4113af8cf07c8da502827249a807ce10e995e674ce312402ec3e310e4e7e620d77bad932673b903230e5d2e5134b7121707ab76eb325bc769af88d731d00b6500129b27399f5a5010001	\\xed0cf88b828288556c80965cb8706063076fe421b31fa74c95eac4a8edc6de09c31e3e362f799f190d81adf7bbfee67a6d150d2e7f47f994f525817f2d3f8d01	1665400985000000	1666005785000000	1729077785000000	1823685785000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
345	\\x47b7916cb46d6d99a87bb70d2148d682f04178cb4f5c3137608cc9d0f34d976349b8c2ed9e6d360af4b266653a2e6e5c909331c171c2ff8036605b8076722a95	1	0	\\x000000010000000000800003d38f8f4d3ae42c94b997e85011959d62cbf0cc5a651eca8499f0dcd7ae166b3c530a8891efd48c6d791459df00743b18f1502335bfbcbe13cc3316cb1c151386496541dc92fa3a5cf9669b9856b84ddb2dcbfa1c8c5353296023af016976f1f5c3579f3247a0c6efea8e9782b446dca2e051a02084905f7560886307882e13fd010001	\\x2413e6891db84e794da517b2a2129419bc41fcd879838db8677be2efacc1d0da8ee09076df288eccf25c827f845b44a12dcbb17a50019b84ac2082ad62503809	1655728985000000	1656333785000000	1719405785000000	1814013785000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
346	\\x47b7258cfc533749f5184ebe9f88fba67a3d5e681219adc8d359c3595d285a08995f4baddc5ad4a6ed6e4801ae910a920aaa2042e791dd6646140097324c038c	1	0	\\x0000000100000000008000039cb31845a7d59eda760a2a743747a6ba15a3c4c8fd180221cafea959476bca8634f91c813aee2c629942f513f3bf2842196c93055e64bda901b76bb6734e8c10ac18eb4330a436672c8cf2f078efa5a166d2b9a028833b92c382fe26c61d783da33f31c3240ecb7c6355b8871cdb2d31712fe7879bed437faf2d2858c75bac1f010001	\\xdfe106f18e4d218b40af3d5e6a75aa242bcd06a92a092bfcfa5f289e1789c44fef345f79074d618c68c7ff18c50ff4ee19614d3fff5ef8ec455cbf9024a6410b	1663587485000000	1664192285000000	1727264285000000	1821872285000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
347	\\x487794b3217f307ddee81fa080217193653b31c467f0de49b80b3decba3d199ef723798f3dd29651e64b9774eefbd5ee662227134f1ce37dd573f5e55a26cde3	1	0	\\x000000010000000000800003eb9cb581e5fed52178ecf26483f2c6a704acdec46907ef880fc8cb0479094c51de59867d80459576d6f48100d372f616c712f0dec18a43960d21c96dbab9d6b28ecd99dd46324462a1e5929b22357a058f21b35257e9bae4386e319a2cf4d1c58b13261e28aeacffcb1d2d2572d3a8723f3d75267233eae03328783d75ba5f89010001	\\x7e5389b416cae8dabd4a1b3bbb9281e69a66116559c0d613f33a76e3cff3f70dfa8bdce143f5edfacf2dbcff76c080aec5be15129a4176dc22dac0692dd08103	1685953985000000	1686558785000000	1749630785000000	1844238785000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
348	\\x4967b61a9bcb5f35fa05811e269cf5eec3e54af31050ae6153dc649953b03adec7fec58b395c95e7d3ff9a77b150ea01d76984d706ca5fadd7ebc364b827abc7	1	0	\\x000000010000000000800003bb322bf6533af4dc247f040f7502dd2075046a44579b54bb35d7072fe98ebfcef27db66f8d487a13791368fbbe222b5dfc754154a7b9312e5cb689c6f29a34cfad57738229f262c75a1fda3c50823bbd3a47ebc9be259a35a29bdb4076628e1f43291936e9bdd0821ab4895039d63e04159dc0ffa0d65923036a423df14e38e1010001	\\x781842197b4ce428aadd08378f586be89beafe8dbfe217f8c4395fcc13eb54559bb60f8023739b3e7ede10d7a84aec88168159f4836d302591f5b6da3af89d02	1662378485000000	1662983285000000	1726055285000000	1820663285000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
349	\\x4adfa983cc11fa07b5be81d7d34caf73fa0dc51d89d00342e424db9b0e94386babf2b45f3e5e789fd0b0a7f48ed14463105b1c3a526a97bda985668d76a42cbf	1	0	\\x000000010000000000800003a3540ce384398c8ba5036c184c7f4ea68e0a4804493a36c54e0359dcb579372c114bfd83d159b18ddaf492130285b7eaf1c6ef523ee0456627c8380faad9ecd79cd234a84312cd8d255f0e18c1229029f26d308e6a727708aef1a70d689d42379bdf9a0295eba8cb906b23ad9bb15a2fcf8ab034d3359df0069d34445cf47d75010001	\\xa7498a38313d0e624b05d7e189c644e1e75680023954ae96aa30554e66f0f8a3dd8cc7104e8016f90308f21595d0366ea3e5bbd0bfce7ab91dd7571138fbae0c	1671445985000000	1672050785000000	1735122785000000	1829730785000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
350	\\x4b233e43a901ac81f2f91c4e8c0bcc60f98797779b0f66de5f7929ac70c9a72d7e04212ebbe83175daf9fa19af854f6f04260835492c9d32f23379b746750a8b	1	0	\\x000000010000000000800003c12a93a663e50830736da98aacdaae00be68a594ee803e149419e4ae671dfb030e42c500bccb90af15ffb277b23ce6d87a16df6378b5138bf419b90c2ddfaa1251ec9c9a0cc46155c7fe216809c7317d28ceb12854d75fbc49ed900add0fd736c7e4aeff15e1c9adbbe68832d3e1f0571f61e017c0bb4e45b84e928532e8d9a3010001	\\x55052042c9a30515fae83e89405d0976efe0e62093b3f2c624ad37e59e1cbb5ef839df3e5f67fd890ba6260abcadf85b9a6ba460f1790a36581167af8d5c4a0d	1670841485000000	1671446285000000	1734518285000000	1829126285000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
351	\\x4ec3c28359942e7bb2b358d8de997486eb5e468b3af9dd95b9011c8f561901b3e4b1ab920af903b70ca54438980ded5db1cc0119fa79f1cef6da705a5a28439a	1	0	\\x000000010000000000800003bbeed00e1799ce9cd72d7cae06747665df11e3661435ace03f524e148bfe42794e1cfb80c850783554e055f2d4093ee7d56cced533b5a50ac6b4800faae854a543231891b69ef08d4bdac3f6ed3c6ae97ff5716066187857b1d2a18043079bb011472f02c2dd3ae27110f2f2d3bcd51146b0b9abb07fbe911dc31191542afb9f010001	\\x748eb46df75f80fe3a015cef33f6d26e5a711c0fe96e08fb39ff034d177ef5d55cb2a2620713aac4538c58dee5873b681db183e4a84f3a40b9f1c583265b6904	1675677485000000	1676282285000000	1739354285000000	1833962285000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
352	\\x4f1f21a018eb3842e3b31581dd4301f9ac7c5d17a835236c321e01fdff44f16a8bd01bcff400aec6cfa0f69b371927f70af4f5e9a8ef4fa983bd4eb05d357c1c	1	0	\\x000000010000000000800003ca6d958c347adfcbe4c4190026ef086af66b06611fb858350460879ad06bef109609c283f15430fb0898875793997a39d743c2fe3f7cf743b24859387343270233d3104d4ebfca17ae895f56d54c4551dc352c8685e224e2ec39aacf41793b76329c4f248408f12c4a3320e4d6fe07dcdc97c79c7ef403389ec8e13b871ba5f9010001	\\xbf4716ac66a03a210dacb2412939d16f26cb9d5072a66eaa7542ac07ca000732491dfe15c25f53a9f7207751bc67e407d222b7c1e54f27e3795385cf17b3f60c	1662982985000000	1663587785000000	1726659785000000	1821267785000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
353	\\x503fabbfd2816f7ebb3466973c77dffbb406928495b9314a370aa10a2f864a35e56a4d7112743a14ee0541ceee90b03f9ed12b30a8c270fa7f45a2ad54ac1b6b	1	0	\\x000000010000000000800003e78cbcfac0b07ed0e33a1d0d650f18f6b40df29b17626cc06aa2d4eb59ed44129a9a6ef6d5f9d79593aafd57d19f73da9614928aa8991fc4b81e6030837700b0e0f24737e02b04ef177c771f8fd8b0e3a6d09288fc6b7d17f7c7f7c653d224f65b5481356141250936abae466d37f7b53cb3f52c41965cf70fe5794e498d2eff010001	\\x53b6eb2614ed044b16e74269378e39b3f4b0c9f4a3264187cd7b73d1319a5cf5bf10355af977ee6a555d706bcbcbc33e4381a87fee00aa66ea8a27cb29227a01	1664191985000000	1664796785000000	1727868785000000	1822476785000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
354	\\x505384f97716b12f7b42823629317a8d836ae98802f4ca828dc614ba051296cc6cf71fe3b8ccc216b9b4a3c74c93907c9b4bff4328d036aeebb6064f0bd8ec91	1	0	\\x000000010000000000800003c7431abfa7201c2ab824d1172400fcc70dc34978977039ec0e10ccbc2daf57e43c2fe1ae9fceb30eb764382125d9908a708eeb2b41ab24a48088aae05c7e9ef2141bf0f66d26ec869a6b6a8981a77348698cf54e0aa31f301d52a024f9d2a3f81e78910bfa8ab7f0eb8a99135738ac1a7f9eab8735520903af777eedaeb36893010001	\\x5b3d01d4f2093c27260e47c59f0e93becc0b44608c3e59ac2fa079f231f872ce99ac828491bf673f6875781d6c51a805efc882435ee230702d2abbb9a057f101	1659960485000000	1660565285000000	1723637285000000	1818245285000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
355	\\x552ff2d9aa85678d6d1963605a4fffddee0d2237fd48bc0b3a9e140dbd4d3fd4b25cb9b3fc28db4a1d1f73ab8e0095abf8179539930c2c661953d62436367b3e	1	0	\\x000000010000000000800003e1a65d57ead2d5bfae1e998ee7a9c2f8ed9c42fb8c93353734ac8b476e7af9a44e2032526a9163e6f612a9d477549ddb4c8e9e0ed9acbcc324c53c45272fbc44fa5908f75a064f29ffea1c57bd8e5a6f26483630d40a1501f8ef510e748fd5011db5b1fc772ca7a449615c6ded924483912acdfbfafa03ad3725807ac84049dd010001	\\x6cfdfe79af8bd734a9eb2f82b712c4a374268b47c2d942a609909c15d98ef705ae634d3c4669112e6e265fe1c86eff9883c23b3d36c5dc16c7456315cada3e00	1666609985000000	1667214785000000	1730286785000000	1824894785000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
356	\\x564bff0d31e269c46eef3af8ccbc2d62c43abc4c14a19b41b5947dad8ace673410084ec2db9b5edd152aabe7f34b533032f28d831ed009e6c81c47267b89111c	1	0	\\x000000010000000000800003e96487ccf57a1adc2d8b10fb3492288535616058dcd309fde3159eea1f59026671ad7002a2f861795e323d611c137cd0c0a263018fc9b712aeb0d218aa2e53dace86d275e261e720304a213d57c1b10be79d86e404c0c776222a24c3a405a1de061ce5e06438da98ae82949fe6f6ab94a7e2c3b30081fd83430d32bacdeb1917010001	\\xfa7ecb079e7296c295fa2476b1533d53a866f4652c13ca3e5579e12d5af23080df9bddd60db73a681aef1e0aea3ecbc53bbf77603e68e06b37673bf4c25b7609	1681722485000000	1682327285000000	1745399285000000	1840007285000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
357	\\x57735bc921473bca79d5496472a5a0b58923eb8f7872ea97097500f58b2b198225eba65cea560cb1a285340c626c057027eb8be6291847b0c322575d123dbeff	1	0	\\x000000010000000000800003cb941fe0cb6ea9104cafc7d14aec21fcda99103a13aaf77a0b17b6e33ca3b8d80386a03ec5c5d02ab66111264d35a30392ce357253fd25a4a7fc3461aeea66ae783e5d4a164dd66eebed4425475c0d297b3524fa158959c91511ae16c59f4d6606a7d815e4492918536580c7909cec273d473025214170e0bd7b9ae5a13eac6b010001	\\x442a43d8d067469b1a7db8b4b69951b9bcd07431c305a50f3c19c0653d3b55d5a6fed6b8530bdbc34d9dc2d0d2ff945ad5679029bb64a3b6b401e82fc360920e	1672050485000000	1672655285000000	1735727285000000	1830335285000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
358	\\x5baf1e0f8f4d5253f99d0996afdcc867e3253d8278876c59d2f7e6a9d0f872e11e642393712315f329b0bdcfb076e764ae90f235880fb50b1d68c3e43bcb48cc	1	0	\\x000000010000000000800003c70c8abe287db0b8ea102f72d6f03bb4ce2fe125696889f66afaed9665757b649ddd3e3f56570678d1f4a0241de4d681dcf07852396d76f4cdc2ba177b6f9512397af783cee74c0a4860626342cd916ec60221df0087244e520f702345706c1e99f7ba4e1b0c6e8c73ef8760576e1c3a5dfa09170e611f18cb4530ba19021467010001	\\xcc86b84f14377a8235b8578f3296cf6af9ee52d20d6f04585e36c93dca7589b642b20d89b5cec5d559181f56ab6023663a18b2c36d0f5cb47fff66930cd5dd0b	1672050485000000	1672655285000000	1735727285000000	1830335285000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
359	\\x5f379c9dc4c47c5d2c7ee21e266c35bdc35b1ddf43f815edfe9539cc99564096c7d4f708cfb7536bd22740b051c2eda2af722e641b6c0ddf1067a63b9bc0952d	1	0	\\x000000010000000000800003ae7195a26109de0e45d136ac1e7287bec3f0223edc2efa224aa81f428733315404b3cd784aceb3833c4b300f2c4dcdec64d63a2653f002f73dc32949557d7ccfc659febe1a2972bf7fd35961b838125609140401a05f0c191604f9bdb549d51b756e5f57d76c93eee918f429381848769cce0c16964f28af322cb503a72aa67f010001	\\x8625b5b7e13e71681b32e3fe5a8200ca8841744367d582fd06ba100e6a586657172a3cfb5536f7eb847a02027b1c4d0e351afadfa07033b02eca3060a55f700e	1669632485000000	1670237285000000	1733309285000000	1827917285000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
360	\\x5f0f8b190403ee4e14f52bb76ad8ce091173e87e807263f9183d356dc2c110cc66cf381aa60532754f5244ee029f6adf0cd8c39dc78f5f5c70f2327436a955a3	1	0	\\x000000010000000000800003dd0345a4af1e7c990c1aaa8f5d9f8960d8737f1a7ac76c000dfd53ee1c3c3dde65a3ca7077acaccb0a0f44e9353d552add182a8d8d67d23c6fbd30969f71c360aed0d7af61adaf0fb05585b6b5d20277b1137e58cfeba1ec4c9e80a1308056427a918c748c5acf75721717c0b43e45c37aaf49ba3ecc3e4c78f98dd89a849637010001	\\x7e198f6a80771744109166d557335ded5ffefaea722b516e567207e82b4b299dd88df864ffdc911fc6ece0f547bd4bdda56adae76b3cbd77dfe333a33230d70c	1679908985000000	1680513785000000	1743585785000000	1838193785000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
361	\\x600f97de8be6f77979f26a8cba0ca4eabffaa6ddb81d7fb296d9056aaae3090abf30618f5dc20e698fe573e9f63bfcf0563916e78ffd58e4383ef6b0dd7bedc7	1	0	\\x000000010000000000800003cb32d125cbc76317a035f8b143f2763399269faa24bb74855e02fd642271470e2d9dc31142812ca8fbbfd4637bf26b8609a7a1a8b295f095ae2dc48f47fc2bb32ee90c4c5c27659c28d78f9c31958b09da7e4c97035a53af1eadff1f710f9c315255c0d559fbc58dc87dcef173fcc638e73c1d332b8db5102efd4eefe8b85e8f010001	\\x6593777a7383700181d32aa245fb85b363f7311d4edda21d5ac96b0c6cc9d1d6d1fd17484e3593a0a8c06baa793c1c919cbddf399187b45f9b0cb76aa20a5205	1656333485000000	1656938285000000	1720010285000000	1814618285000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
362	\\x609b498a72d42fc50b740d40ff3482e6d21f6b43b0619b0a244433d5a5565b439fdf536310ebfd00ecfb02c9030de105591df17e18ed63b56c093b7738304d0d	1	0	\\x000000010000000000800003c03b7164940284ba70b1a287567c36d89019ace0ce56cb8db6869356d5ef8aaee3aa07d8dad700de1f7b91a1aa8b0daaea7a1b0195a281dd979cb5fea6cf96a0fba729bb711d3fe82b79e80cfec60636eed97cd3a2ea9d9cc0184d6388909d9717de70c39c8da2c9d286390646cb158f83f73cd1e20c477ea0ff8ae300211c8b010001	\\xd5700545d00ba600c3638afc6a7a7b9377df6ca482a607309563b3efaa228005d2bda797ecc43fed5e8ad0b2018c5abc014dfa5a21e9c111a13b96d3bdb6d809	1665400985000000	1666005785000000	1729077785000000	1823685785000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
363	\\x61e394bc261881437e844d951f29bfbd6e686b3dd0957b2fe0fd9077fde5bcfe382389902a9266e8a6fec8f36a681904ed6059b9182ac79bbd6297566aa56ac1	1	0	\\x000000010000000000800003d6af9895aaa75ff58645f33b1da690748d42be219d4aadc7089f86c65b6e217ef491ee4c828816cbbc2836bc94679968e1b57db0e1c62803058c5278ef76fe3a8a5a6a9ea0805d82ba502456a3db044230a6de6fa988fd0ea49b72ac4ea20b08dec4e246bcdd32c0a262e34ee00f99a171fa6e5844c7a100994fd059b8529537010001	\\xa17c8a85f3b55b022cdb87e68dca633bb234649a2c723f640a78296cca8486da9b46f238668f8b0fb5123405777621892f7f66bb0d8280731579f3c4beca0c0b	1669632485000000	1670237285000000	1733309285000000	1827917285000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
364	\\x614f7ee02ce591b562772958bf9f8aa9b5e870585b8724233547a835803a8fe2e8e3003a5ec7c14837796a90cae587d8d8d8c4b67f690e77ca7713440af01c65	1	0	\\x000000010000000000800003ec890de7100e3fd757ff1f1001beb26e1309a8ee8c6e5642322c37460425f0b17acbd66b8dbc8b3786f668fc31ae00fe8fe4ffc145feb77980b855e95c82f2345bb4b9db9f094110cafe40a918db0406c38d1644f75b79c6d6fb46e9662600034bb648baebbdebe0cb4ea004adae09d73e5b2931da02e90ff3ef933d1bc7cbbd010001	\\xe96cd49c9ab9366e138507b5a62ce03910636961dafa79a7a356be571c38315634a209beb7d69589895817ffb1266b725a4d97bf6cc6fcd4933a37e45d63ae0c	1664796485000000	1665401285000000	1728473285000000	1823081285000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
365	\\x627752c83934154cd99706ede4cb832a2a052632e9c7333c533480212f3d8b25b5b67cbe37b2e8d513eec4ca55c55c933602481bf972a612f7b14683f179f7bd	1	0	\\x000000010000000000800003a373b2abf1248cc21e818a527a2e2b0994ea29aea65782d4fb88cc86e56b5dd6c78ccc159d7a5d7b3a41fb61739b676d0ca3069cf6b7939038b19abf5b236391ff2a8cffc1829373094130e56ebdbf838e7be76cf36c0ddb661ed07704c29a055e7f1603438705a054f16ed5e1b7dee88bd24c28433f8f534a0a4b1fc4c354e3010001	\\xb660a52d64d1d16af2223082320c53d1e33ff48e9449dc84ef6dbe5de3d32f0259dd3a866946f968dfab8060ae697cf30e8f98319c231cc7bec6e87965b1eb07	1683535985000000	1684140785000000	1747212785000000	1841820785000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
366	\\x63330a17e46a03416fac5b73947b8b82c942016652a6f7685a4a6ce356eba13b0cfdf25f4c9758c12e215220a569f473607c8e52670eb5b52cea1460948aae8e	1	0	\\x000000010000000000800003bd0d6ba224a769108e345c567676d0939ac812df1b8f54e0585ed4cf11ad6e45a1b233ae56361cb00aea61b894f83ce2e61975b0eef7368e360b7d48e0973acb9a4353187762b0db74a91253ecb38421cbf09289f463e3defd6a83b7865b0c5292857c9949858c7b5264f2de5252b3a9d68488672955fbfd441006853a2d2f1d010001	\\x079ab2a9008b55255f951dc621ea9e96a99934a8ec87ddc4405186b3e3518542a877b24771f37f51776026b039686e60cc9a735a1c59078d1c42d6a21757ee0f	1685349485000000	1685954285000000	1749026285000000	1843634285000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
367	\\x652f01b6c845634d0688f66bd22114c0a2ac1eab093d1d451be26e2b8da17962d9f004736594c4d22cf524fe12de8dd529ad34cf5fb14df705e7bd546209f0a8	1	0	\\x000000010000000000800003ef883c87f8cec98287ed2375dd73f54734f2b9afd73953c9aa9e5a1bc3719ec9da8f265eeabb35a465d6771b6a49d4e13a11fdeb605c06927c173cf8bd1617e1325cb600c3abfde8c901e593e0ff0dc8b13f1b417eabbc596c514d0780b04d136a708a556e65c103865f4306a2c0bee6e605b8e1272e2d75d47912b1699c8039010001	\\xcbe4d5978a26fe15b9a7e75235656ffaba125fa825fb7af9afa1866eb075bd88b55fe17255c9042ec569b1675469ad3b04c0b1c6e56103037a52a458b93df700	1667214485000000	1667819285000000	1730891285000000	1825499285000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
368	\\x66471d94d6e385c74e375de9a132d2714c6fb57dccace5e8784cdc74dc1ebca0866279b8d334dd5213bd25263ed2f81b754618e5eca5945359027424c06d73d2	1	0	\\x000000010000000000800003ef036aeda18a7778367d59f8cb48791f30d06c4d103864856bbc05803f2b0eef3daae22b0f573173acbf7e2007bea6f15fb77cdfd71ca0bca41351e3cd17d3ae595a9fa920c7d438ca5bffd610f7008fa2a12c3217b671bfcd7500cf9df084ec8dfaeed37b96868e2b3823fb42a039717032b0cb0f3bed58a130da5e643ff8b1010001	\\x138968d360e7964d43165d51ba20fa262161b7d12922a113384a49098a8e26540fdf170d80fab5829ce6d59693ec7dadb34d8f1f0a5a4122b26d0ddc8ca0af0e	1658146985000000	1658751785000000	1721823785000000	1816431785000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
369	\\x69930e4074616838c51bf4260bec788397ac4f2bd8480f7a7e5367f334733ddc1d237c0c24463fcfb20312fa92ae50679cb4232835e9116130381f877f9e7d0e	1	0	\\x000000010000000000800003be5fe9d9962d536a20b11330e1b658036f5bb00c03a43c5f0d05a8de53f38f196c53e65f25a5abd5fc0bc2b8cb8a3a8b612dea5145cb3cf4aecf2185d7c12dfe1957508907c1ea2dd3340d79f04c4e9aed91bb70f53f1b46533f829e8d43899c79d9ada05ec0eb3f2127fc9badcd680060f3168789493a96284c654f2004da19010001	\\xd6ae6d0265372e34121663ffcb7de015f2ddf6094908c4a1471b6f199be970a3d617c55255458f8fd20b7ecf3f0f2467633e2c5f400376ea6eb0850f3da93f0b	1678095485000000	1678700285000000	1741772285000000	1836380285000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
370	\\x6aa791617a53e0f6dffb5e1e3bbaae85a638d31c37701317ed58fc68ea794843f6d7f1effe5468ef5fd115756344d4ebc17650c94a9961e317b3b37c9dba3357	1	0	\\x000000010000000000800003e7baee0e3a4ee22de1d1a324b730712d36c486dba26bef504e6bb55fae4a2607f424c2dfe02d8b90fbfff857433c62bc5fe0876995fa618ee9b3c1fe2881641604865c138ae7299f58f0b64ce634c784fcf8d8fb8f947e257f38b6271b577164e6e134fb9e836efa7359db830a875d74e2e4ebd354af2483ccfeda746429551f010001	\\xde43eaf013deb27016ff784ae1794dc6902fb67c2148f59e416a1ae25e80b6fe54fc01442f8799bcde5c67b73031b343f7e93b8598dbb4ddaaa1b98bc32b1f0a	1678095485000000	1678700285000000	1741772285000000	1836380285000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
371	\\x6d9320c64ce65add65cc9f10b10bc5ccb16fc93c8f4e9e6f8438eb2ea709ef6e2ee98ba162161dd160c6a984e0e3987f7e9cc26ffb57d8477c7a3595902fbac6	1	0	\\x000000010000000000800003c432ebbe31ca8525a94ee45ad21e4bf9120345389f1c5e75535ab3866c41de06642fc73770df8e8e7d545e52c6497ea5469546ccf8118de55324a903cf4e65d026bd61b779cabcd8bdc15543cc02b721f9f6e5962ea96e6fb5265df9bf7c14842aed1cc06cda97756c63f8738a865d126ebe8ac7bde850fd701077b636ae42a1010001	\\x47616b689e2415423904304815c1ad82739212eebbd0814d77a9051e0360f71d833b8a1b5bb7f494f988dd5648bf6e0186a42eb2d6cebd8e6c323b8ba5cd5e08	1664191985000000	1664796785000000	1727868785000000	1822476785000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
372	\\x73fbd101545c6c8bac72826e325531f4248a0009fad2f6d0f48c53be131d1649bbe028db144f09d0ab14b266065d756fea6649394e1ff559c22d572ab54d9b27	1	0	\\x00000001000000000080000399d1ea1c1619fa796f37905cbc2edb9c936cddb975153dab6d71f89e9019bbe9dd0f6072274e36ca5d5cb907216a8d952e3e07e830bdb62b51a12bd79d4d97571021bff42e2bab2192d46af43d1941a0e537b6a52e9b40bfbf2d705d8b978b1b644018c1251f96fb9e9db773babf1aa1b1f883abeb483d60469208fb68ab6c95010001	\\x5d62b9aced3623395700dd7727b4295dde31a6377efde4902e65b203bd8f454098182965b15fe87135d1841ce73cda274c6f012247861a61300ac966d34fd70c	1670236985000000	1670841785000000	1733913785000000	1828521785000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
373	\\x73b72137c68be560a56b870769f09c9c1ab1eb72d4ff6d761619f484f5b1cf84728397783326bdcc42aa1e4c365da6b367f7044b89eef3878cb2ffc6842c6c59	1	0	\\x000000010000000000800003ded6b6d123c3e40ea7cbdc0302454868444e4a398ef6c879172bb028691de234ea7df77736c675358d3331a452aa068be14b8acbb169e7e6f1d74308a2117c766351831f67d0dea5f89e96fbfd0f5e9206df220a1bbeb83944e5333039e0c7e50fce2a6b3a98e6ac79c0e8c4bba054417f2c2e0a50c0c0e822b44d0b1fa672c7010001	\\x6822a60c6250be5ec71f3001719f44ca66d5619e597bb1e06cacbf2829a7de002d8668a4153cbf00124cb95bccac780fa7664c2bb0bd44e0b0b77f7a7248770a	1662982985000000	1663587785000000	1726659785000000	1821267785000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
374	\\x764f46b9b5a798fea09f48b154718f22c5fd3337eed5b7422f2210f615d8ff437e5c17bd8bdd10aafb26af91a50f7f09724d08d99a58c48a270fb4632a0bb75b	1	0	\\x000000010000000000800003ecaf0565fffed8214e2dea57c96a3dceadbe1004d9f92a8f77b01cc5a2aa1c10b62626bbf6586ff97929482fe15945873a63f56d1387b2fd567d0cd096c7c20638f1f283fd27de3015f6ceef6ebf82c475239a71a02ce4f98402ff47bb2fc9c0f04141c679221698eea6d158de14fbfed4d426453b8f5f9ffce14aecfdf95f2d010001	\\xbbb3aac89f7f46d771d3041e695455ac77e36614cadc78e16e6f6e5e064369519582af0c3371f682ceced4f30602c848921542575f67ce91ce7eae166f0b210a	1670236985000000	1670841785000000	1733913785000000	1828521785000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
375	\\x7e77cbeb3e52bf72542f55c411804076f56f083e0eb5343b12723bebd84714975f9f959b0ebb224154ab244e43fecbc5822c4e7ca0d912092ba427620b0ec625	1	0	\\x000000010000000000800003cbda3f842ea8a5f39d87ce9f21dde3f8b80fc30b43d6b3f8d7e3a908d0b2e960ede3daa5889f13b2bac8a6facbffa9b6c8f2a71341d169a3d7acc6810e242f26c68c763c2b7ca3512f5f372edd0c06387b07dc94addd2ab5dd4e3b5a58490fb4ad9fdae7f5f573e783e18922bb8ed4f95300b2ec645a310beed3147581b021ad010001	\\xfc0254f550e8c1a431b442e16cddff6695d9755579d78761c9ea7b0288f98dbec17dc8036bc7d93988049eb7f0c0710945716caac9b0cbd0e4ca803a8263b50c	1681117985000000	1681722785000000	1744794785000000	1839402785000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
376	\\x81d7c5e0456b721a9c9349503a7372753ac83f9e55abd326e5e030a876ec73cc830d1d9dd6b8615834ccf53fb8c0d53694c89415627edfe6838843968b154133	1	0	\\x000000010000000000800003eb002a248f2e12ea463f0524e7289c2ff18645e0a744da50bbeedd69e7b25d7a8044ea7183ed2096d1f2b46b1c999d0dfabb778e4efb67d8177d01a568e6ddf1010cc3310357240dd3e1487a19d4351e92ee51962bb8914463e679da910070d0c8e638bacc4ae1edbc30380828c4a04dd503405920eee154f5a1cc1c734c9839010001	\\x4d5f1ad094206828537671ca36e14374e1c73388e19c47c857d606832faef3bf71a8d23b5ccf3f11707d6ed32cc3ef4c96db4d6ed38fe00d79b97d47a1dcfb02	1672050485000000	1672655285000000	1735727285000000	1830335285000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
377	\\x820782cb04ac8dedd8a2a7e61f99f69ee26c96014421239f7370690c2eadfa87f45e8d010b00ca75f504f692f9ea6ea892ff7d385a2215a209ed1d95bf169db7	1	0	\\x000000010000000000800003a83f0ec44f76655698bb3cbac0de73e48422c64eb328cb4c99549ccf1dadbeb89ecf5d2afe33e0463eab135b21888482b3c46a2286a3df2d89db4cd6da64cb8211bfc6f9d260cceb321cbc5bc749ae7701b9ae1dc602cb29d216bfc0f6883b03c65c0b857fd2d72a5f5491c1951e750cf78fbf737131f798a99a90972fb737ed010001	\\xe6133a71ea5b3a2ff3d36f2581a12f44d2eedb1406833d8ca1318a145cbe4c50b891fc7f0a320610970befd88efcb7d146ef0795735cbd744892aa1f33d06106	1664796485000000	1665401285000000	1728473285000000	1823081285000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
378	\\x84f3118b2375404a5203f94f6e3e65db708d59aa1ed481c033844536b9e6cff1f9bae7ce8741806e00574fbaf5f598f328c87fb87381c286d843ff7d8ccac957	1	0	\\x000000010000000000800003c146fce78067431fc695f8d33ca94dbf47b3e7dd3bee7157202c8aeab1eeeee026526a37164d335712bc0033a386a65aa8b107163006ac4997f8283bdc5404c5504a8f5802e80df7bb3e37a21e1aeed243f5b10ea97dff4a356ed2459971113c4eca1d56499a2b19a3467188289198701d471a4af8d401410c4a560417b1a947010001	\\xb284b3647639683338468832788adb48a81dfaf7c6f5659402f1de53e59356ec200706e2808be679772fa81a295c4ef80ef3d6e63779f1ebf6de9cc522591105	1676886485000000	1677491285000000	1740563285000000	1835171285000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
379	\\x870f28a41f304da6d83975350d176c44dcff9cf2efb19b677dbb3d979a30ac8fa643a8634bfa2469f39da7d595f2f8c4d39bc92ba824b8866ebc066a87abab4b	1	0	\\x000000010000000000800003d76e3682c5f1e592b3f3f559979b5fc9b0926dbb39d5f1f4b7c24cd8d379c9d48b0c2fd433e11a4420f4faef03bfd2916beef5038e0cc1aed3df189bd7b60537a8fd458985e6218eadd918c14a6f7ecdbc01d423c7876d20460614b3472cc0082c36797e746bac61300c04b38a25a89113e7e84ea726b6a799677a648b3ce4a3010001	\\xa37192040781d494d353a45cd465d81958146e245bd054829c0ac5446d9210345e860782e963e2c19d84ede7a544760da39d8ff6396fe75224879eb63ab47a0b	1680513485000000	1681118285000000	1744190285000000	1838798285000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
380	\\x8ba7848f290ecf226b81e3964e02a1238218b65ea9c05d20785558eb74789831518877d845f48f496514030324c89ef21849b6756231af58edeaeeed73c41e2b	1	0	\\x000000010000000000800003a005f46b91ea94a91ad0430641ff929de8f1549b02eb545d877071005759999f23de4ebc097eb077009341c3f87e338887d15e7b4628b0dfa18a4e130a4a50d452fae96d94422e6001a1d81e240cdf2447cf0e7684f63efc298c575652958a3722379311e6756d94d277c0ad7f8142464b8eb588c05eb2af65782482079e3f07010001	\\xa8c495e80aab8a6331c62548f20b03e5641a7aad06f43eac8b4fffa5302f075392ed5745e2e889acc102d42d31fc33111a0d8ef2af76562015b5d74c445cd409	1685349485000000	1685954285000000	1749026285000000	1843634285000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
381	\\x8e2306b2afa52620ee5ef90b1bdbbff2cc5fb9321a1b3daa1efe76879b77ce8c95b098316973e671839b3332d0af876e7cac09917fc01a06cceec0448c725f00	1	0	\\x000000010000000000800003afe3ca2e5f1daef243fec55965a3e32e1b4d3d2d7bc8e8cf4ac35b66391d021443a773b00e4bdcdea5e03359a49846c346cc0f2e7e5cd1b0fc0fad44c6a5d71687d41741dade43982c4ce07ac210da1966d727303195e0d0f4dd58bb975e2efcc6c3702451be642dda60104fdd5e57a4336ed8788b2dfb4a581ded61ab0f5383010001	\\x1947b2af62593277e5702eb8669b479a429c0a18b4e68f9bbdeddb6122ce2293623fe3eda7c07dee1817f76e24d5e249248ee8e30c834fbc31c534f1ff1a290d	1670841485000000	1671446285000000	1734518285000000	1829126285000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
382	\\x9187be7afbbddc4c1e426db94392283edc0b59945ce2279ba159f2d61681238e79bd951848225f9c7ded31c1f088f5e0043dc9ac7b911c957f11b3d37ca1e7f1	1	0	\\x000000010000000000800003be567429872333710d91aac1182d228be09fd459618b97bb13553afd9440a99741c9a4432d380d50ce65cf586f06c945e6c9ffff998b1486e462ac6754b7e600bbd009a069caa701d01688add94af6e4e591e1e1d472856b31416980584482c58dfc0e9a31835b1870760ee4e255e7e8f00f7e1d75c87c198c998df97e6ac997010001	\\xab825e66d22ddc2ce8f196f5e06074334f5af78abd06164888245cfa6c25e35a125d0c718ff437bae0cf1f5b6f774dad498ab50c1420b0371e18a0b34aead60d	1668423485000000	1669028285000000	1732100285000000	1826708285000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
383	\\x95ab615b4a3e759e4c05b5da430f4fb141fb65b7717d39ce9d1a6d4dc0c58b782d7faab0eb8e55e3f447cd02343ba013fca2cba1bcc5248fdfa292a15f6ab6f7	1	0	\\x000000010000000000800003d1c06db42d2297524a8fdd75b44e744c6ca80dbce06affddfea5d9ebea5b4346edcd064af6d4c912f287a498587aa5a85bfc72b1669f47a13ee0f2ca49e631f29448ca092d11b499b79cbf02d7f31d65d11f7a9fbcf5e9ce4f503be401c5f145818c1cd27ba5625bcc93420a1bd9871688d1e3be806e1b54ed3b21ef6ab1d365010001	\\x75ece2e3cb3fa8cc2453c90b4a98d5d19db0328f56e1da197f197692dd0f4059e8947384157657351097634e4205ebb61777689b4f5e637bfe8d60cc6dfbc005	1685953985000000	1686558785000000	1749630785000000	1844238785000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
384	\\x95cb1b311b0e854e43d3116e9a7d263446877bceb299291baf3acaa0a0a4d0436c15df684f2a280a12dea32b11fa8a6245d7a7828e2d25cfeb72371be013e48c	1	0	\\x000000010000000000800003e127fdfd7fdd8a19ace2c30981737f4d2ebeaf094fb59ab60e59af43c2bb74fcd37f4185a17486a366af6a6ada2bf01475ed2141d92e82fa55789a1d98de0adc52c865b3941a1190d4efa2926769969e053695914e34e8b15c392714e03de90e4343bd8791f25651d26dc5e4072802fa4a0657ac49419c6f841591157017fc11010001	\\xf7aef7c13392b904384bbf7f4ad1013bd804ad9a60a38590f4b07e2739c33c4a1c445a1a66eee06f5cf10337d30a1c6614479ff1dfc9da73023ae5c8f609ac0d	1675677485000000	1676282285000000	1739354285000000	1833962285000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
385	\\x95dba99920f8cb3e71d0ebd27fd53bb943b7d47f9b3d01ca48e86f7849f0737be09e32fbee754d592d1c3412a3ac283e4b14bb17d55faeeed09a588d4eb23e70	1	0	\\x000000010000000000800003ab2fc94ff7a2353c9a67af686af75fa3db733921998b793afb395af0a64a715d097c33fe6b349d83d491f254087d2876ca81bb35e278f24f01dc9308b84a6e3f91bff9cc06a24637b1e18822a84ff7f183200ca64856b48d1bba58c6aaaad40bd512c7086e0463f47af767651cd731bde43f813bed0436195944cf424c90ae2d010001	\\xbe3aa525002217c63ff38c6a0ef3e49edb056d072eb9d48f1a091558837ff014badf7c45c1eec539b5f5d3214f7143644a545442ce3e206b3fea3bd3cda4640b	1682326985000000	1682931785000000	1746003785000000	1840611785000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
386	\\x9757a28a59298bc691d1f90bbc53650ad401c980b46a633a94dc997e8532f8811ddfebc8455a926084a2550a40c4b3038bb8a4cab832838080fd7ed6405ae8b2	1	0	\\x000000010000000000800003b8455a0b79d998e1f3cd9f74b4d0870a22e6fa09fdbc9178759c8798855536c179c167958c5cfd11066496006e87262937f526f33d5a8fceaadf6453734db712550400558cd82c62a1b2d726661ebfbf1984cf45fe73b1a5324634221b879b52928c729d8270e8d433bf71e737de3dc0316d247ba66c9a6d8dd51f17df5334cd010001	\\x799b2aa70647f5a521bafbf8b26387f0593b26bc310f87f22d5fac59035facb284bd8ac8b9dc415bf3c4326fa2d9b8ea144532987df29181075cc6d05571ad06	1661169485000000	1661774285000000	1724846285000000	1819454285000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
387	\\x99577a8b7c163ea583f5901ecfab0902183022d280e874b1346c90b8bd318702db1d937dc34f368e7f9f07af8350dd26867eb2fd8f8d20c62f1d80700decc20e	1	0	\\x000000010000000000800003c1f05e0665b17a261385d537279189297faf7f22636bfc7c85dd37fc293fe1b516a1c80cf92a8e38becd59992606e68284cbdd87b86ec88eaa2b7698b2fa37c34271602412f0894e69121cab3e4291f1bdfc16bfe2efebf28f8257d418d7e2d061daeea5aefd974c976b3e6d36094764f164093d0b57e696aae05f33aa63b32b010001	\\x24ef111b81be5516f4d4498b28da0a257ec06035b99acb26a0215746bf382f9fe27e76ad3b4e6fbbcfb07b73d4c43833e2373317462972f37a6078c4bc7e3805	1660564985000000	1661169785000000	1724241785000000	1818849785000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
388	\\x99b74023ec1fb52907604f2b67c0313dad2f61f74a7ade7527f863216c2431bb7e37758269d95e19cc59f0f2ab89ccbe64745f9a88d049020b29f67c8e1ec278	1	0	\\x000000010000000000800003e7d33b9a1dacd85ab5b162fb13ad37bbf16cdd9c0990e89c8003287c9b780c00f83a209b7f9c86cf282495b035ae8e1131a7f880287823b7d393829384d3e6d6a7aa2dc44ca1f90e8ced3642e531403c3457b843af69773715a5b60b74018160609ecf54520b4969068a9f085fe0951c837aa5534c6ce7306422fb135a2db97f010001	\\x46cc756430e6116d796b58d52a28d97adb6e584d2b7715cdcc8dda096358b9fa73fad9d63d1799941c64ec06b614863af7e67de6001a5836a82a09c712145504	1673259485000000	1673864285000000	1736936285000000	1831544285000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
389	\\x9b2ba2082ced7926108370e7bdd53a44a3c7bc6e483b0db79502321a494bb0d3717fc3ce797c1c9d8aa9f7d3fa464bf15200d5fe76454eb3f651fcc535068604	1	0	\\x000000010000000000800003e93368fc7880090609ef60c60eebcd908fd7453b914048e15722d046b7c3cf400a44b1fdb23ba73774066e52abe8df56f504be211495c36b8edfad7462b3776d7f26e1d5cdb33d9021cdd5113bee3f7c338fe4a9fa09fd8270c86c84f8f3a830354db2aa208ef2c9271ef63f60984d3e53e24ccf6a13d0475c76536c721c3aff010001	\\xacfadb077e44e3d31caf21cf013ac6ea6312647489bea53b6748b33d735b7f4ba7907c35518204b538e05578086c1c51e543de32e080588bea84db1323750803	1656937985000000	1657542785000000	1720614785000000	1815222785000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
390	\\x9f4b987f3171a2bdb947e3e129e09aa6b2d152163444a6ac9c87e27bbd2ec293eb22cbe392e1b4115fdf5acbac5970137fe797050d2310187c89f8e7f741894e	1	0	\\x000000010000000000800003d24b78d3bbd4ca60b81c10e33ede067d5d085baef16ccae9db96b4b53b6b3e7cdf6fb4fb50ab764fb81654905d6c3d699083f886ec98b640970ed017f36e11234564269d92cfaa801d5b397aacc8f1c5fd53a11e928cf459202f96bf1fd37a54b189d2e54bd4d95061e3bd2095c4ed886a3070e9b4e9df4e8e99a581a709206d010001	\\x1179d5ec6637ed92431553e1da54dd06c5c18bed42019905484a425a3ec3b219a6f9e1d3b0080a8b18d0c70f5eedc5e307149eea4553ae5636959343fa44cb0f	1661773985000000	1662378785000000	1725450785000000	1820058785000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
391	\\xa09756de76d40b6234b686267da3a1183c67eac7313b29ba97676a336dc1183875a8d99caf9df104f5d4edda04b4ea93690501e78442809f6c422a7d83349705	1	0	\\x000000010000000000800003ce7c505905dab980413d7d17a615eb91f7c004b8dc6b3b327e5216888dfe5f618cb3f3ba3a39f71becd02de399a832e054128e4d27bce2d5cb11d6d1f165fc9ba9cbda763ce3ac22895e2b590122ed49dacf857cc527d0d1a6940f9b4fb296f38e8e2b550335562226f2f2f812844ec2e389c45c9ec4f44df8b20aacb354b385010001	\\xa503c2ec828aa431f04b13bb5743277f5963fccfa79f00f9ed700e51ba305260fb40a32d77f1b993f0a79c1dbc6797c85e50b5e6285c8fa41aa09d3fc416bf07	1669632485000000	1670237285000000	1733309285000000	1827917285000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
392	\\xa093a1da6ec0e0fd3ca8eb1b56bd07d3688a369afc764401214f58daf4328c2ae9ad527d5b236f4a324edb0ba14ce7532d65518841bee3f814d62647470105ba	1	0	\\x0000000100000000008000039fb074102f6ea73718cdfc712d25f75cfa9bc20ac6c7067158621b1a013a4bc92ca3f9d9e84771b0f18bd90426f7fb02d5dfe2208c6cac000c08ebe5a21128cf482876d9444b9375f31dfa26893b1e55883066949945f490424911b12305d051f7b158a6f602b08d8517b0edac0ae5cc8e3c7c1be0725591bb8dd2e5cd744127010001	\\x6e017882c4cbb1a26913cea6b148693725f0e2814e0d4e44b8fcbfaf8194deb35e01828816308ee1c5745058e2fc1d1320217bda3781785af6b750682802b203	1661773985000000	1662378785000000	1725450785000000	1820058785000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
393	\\xa13f2564ed47a61b5543fc5b11bed68770d05be61ef6996db72c006890adc1807758590fa359d2c36dac8a105687f02f48c566701e1b2399de8ec56d39ceb877	1	0	\\x000000010000000000800003c48d28f1fa166fb7b3e410abdbeefea9a29bffdeabc8bd72242cc33bc34a7aec83929d1c245a06c9a2b285536c1ad29061f3570f18c0fe90e10873d50886ff883445362c7ffc61a6737ebf7f0552091f0df6786f5473f784ab24127a34855233dd91451527cc9fa0330d7dba686e0469f3a956c6a653d24f0c028e424fd4d039010001	\\x4eb3f3bf53cc8be8c1c921829c79b52f02bae941d1a19f200912a33d12b8483087e72c3fa043bf932c8aa7122f5dc22b629275c6d9af5b5eb8c9df9c3af98b0f	1679304485000000	1679909285000000	1742981285000000	1837589285000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
394	\\xa1874bdb8e427006e885059894fbfec9d88c6867ee46f93bf74d16937f1237bcdfcc28c715f0ad1fcaf9be6b254f5ce3debcd3d044f6f1070d2c66636441763b	1	0	\\x000000010000000000800003cc570a3c77c370fdb69a1b95506f4d558b1e2ed0f2f8de4b3b3919051f24348a55a527dd81e490b0bd11ec2e7ece81ed25b52ab4a444534c12783dc3d61ecb31dbe5913376f6e65e2e2d5e04f518ab7de821c42a48530ef17e764bb954d02b1423d6a01c4efe9fb57a789b4fd59229b396f96386723e189dd97b12b82f1c127d010001	\\x9c4f10cdfff3a766eed9d2fcc5858f5f031fcb0f9cbe1d8f0b0ddecc2cb24d20dd9a7ca26f7b5cbb20e824339420c54bce114a6028d8307116c07c8b13978e0a	1672654985000000	1673259785000000	1736331785000000	1830939785000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
395	\\xa1f31b5e55aece72b451524ab6c93834b37b2e7d6a84846c100b8e41604abcfeba54df586ddb95e899c2330c869d5f421189137ebeedf0577b914c7814d4d9f7	1	0	\\x000000010000000000800003b73069e925f556cbab440b98b12dd157a7e8ea0411ba883cd169d286a76b6c969b1f16015e084bb8136c6a9b58b3993bd89b16aa146d738383289197bcc665ed93c88609f956a6866d590a7ec7b3aa981eb6a22961b85bd6b3c737f52a2a4af5ab0389a12f8254b89191ecc176e8da2e3f06fad02957e4a66100e08cd4c4d9bf010001	\\xb9244884420092de893008c3d70c606feec458c5dfce73831de3028e808a73e05455aa19fbc3707c0dbf8138f216f25d1abda0cdee07bc6f6f94bb2c685e5c00	1667214485000000	1667819285000000	1730891285000000	1825499285000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
396	\\xa81fb749939f2c0f51fe17dac35d79e501eee2b40f7717f86c5f566e3a7a02a9ea3d7ed03ec2aaaaf155a8841498f32a0b4d77b6e27a1fceefb539d614531e10	1	0	\\x000000010000000000800003c29a3635c3a802ab034955da3b5c7d4763c63496877ade9705830d77bf0a26eb2a2b9aca1ffe483eecf69dae30a6b8273059a2df68918db2978c01b07146337572ada264606a8813cf70796a150fb816d4d97b0b53a141c98c586e0d9c45786145fb75d4bf807ce26b800dba4e5b0b079ffd024b1e0341ecf76424ee1966e901010001	\\x8f9dddf6a0945d9bce771b39791e87cba7fa38e51af28f92164e5edc1ee436629370797bdf3dbdf321318c748f43ca9ee44bca312a21463a04dc36b559a1e603	1656937985000000	1657542785000000	1720614785000000	1815222785000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
397	\\xad3fed8e2d65bd64159cfaaf21432c157dc12b0928980d630f44d2f1ff956556b80ce4e1ef6fd99979594182083f28d8425e070f8bd02df4db937382588bc476	1	0	\\x000000010000000000800003bd783b952cec9480a493e60cb5fcf46bd54fbb642c380cdb3e14f758a0f92e36db0b93148f2d34ad05e86e324ee4487537c43ec96e4e253ac22f69ce78c23e1a69cce2fead26487e626c0ce299420eef05a6bbdd80ea971e0640ccdfe2b2e1a6ba4523b5c798b8f9f6b2b79a42a7d303cb1b3015bd9e4cc354fcb4e3c189c0a1010001	\\x55eb976fc4d454d546eaad27c94ca81a8f9b9cb682bcd36cf2c115d653542db14939891d465662a2b4ddd9df823a0191c83196ef51e06ab64bb4a86af7978907	1677490985000000	1678095785000000	1741167785000000	1835775785000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
398	\\xb01f288717b4dfabaf557a77e9c44016b92228a4eb25a01621455b0b2429b3a1c8811c503c169e5775370e2e220e9a6b4c93560037470ed65d3bab72d8fba97c	1	0	\\x000000010000000000800003c14be97d211526f4d39b77ec1f615291a3ae6f7a2a90cd49544ca99c6de85f567d5bc28a2a68154c46a0b1bdd86018c6f3cc8b9e7787d9aeb83263b8eac25be2a1bc4f576406d85607e3f93b3f7a813771b5a5e32340caed204e743c54802746e8b20edbe08d11b534e4745183a19251dc5c2119f9356bd485ffe29368e4bf21010001	\\x483cd9e5bf919c705bd7b8c9fa46ea62a93322ebd954cf88952236dd7f9f57574a53e396a9187042557ffca35e0cec1dd1d5223867d68ea66cc66bba67329706	1670841485000000	1671446285000000	1734518285000000	1829126285000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
399	\\xb14bedf46f041c8d9e7425e193ca1cd9fdc6308db008078e21907fe06135999f7dc5fe10889a739243d6cbd7cdf4040abc87a184fd6b4d21cffb00c70314f11e	1	0	\\x000000010000000000800003d66469cc0d7b16271defc9929a375d296047870e935efc8d0f7fda7aa0a79cc10fed81761a811e87abf48ed8a55057ae59fcacb056bd4605c809700a8267373b9797c70f7f62a21eda0cebce3e87a065f439c0adb0bdc343e2cc15fe17c2c4a9ceeddb7b882b5d428aaec1160546ca9e724dda42d76fd8728fb9b8e965d07647010001	\\x92b09265ef5536d357254fe0f989b4a80658e5ce03f6b3c0b202b68a3808773421c309058bb42a36534f0f2b64630c752329407f0e3a7834c108f5d0c268210f	1680513485000000	1681118285000000	1744190285000000	1838798285000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
400	\\xb11342f2c49d64a0ebdac6e32ea212038efec7880e02e0ecf3f2acdd827cc89824b27b29b447bd6cd5ea31353866e01f4aea84bbc614b2b8c33d8f5bcccf0b1c	1	0	\\x000000010000000000800003ceb08b24e12ce6376bd6d229c1dfe04cb172e8add3635b8136db2717c4908c0405fb0d305909b5c7a912e27e1d59d2df2cd909b2559db01ebf4de37ee3041e5629f955d727a025b1c505feb6f1728c7973aad89ec020e841113d6d022ba93d0f9c5be43f6bcd2c21aac7461a078bf324e233a311c5e928eab9a3d0686ff4e4e9010001	\\x2ffd2e5270070b6c1e1169c0246e11c541cc3eab9a10e3cbeffe9d4e9aa45ae59c97f6fa8bebdf08bc6680b326dad3d043b800ef0869602a7eccacf1fa564f0d	1670236985000000	1670841785000000	1733913785000000	1828521785000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
401	\\xb68b2c8c801daadeb01b73632cc85e5cd0901af2a1d85b6cd41736b2393c8d4b57e1bce2a75445fd4eabaf7274b771035030c06578933423a080d41bd1283d75	1	0	\\x000000010000000000800003cec6f07f3c0629fcb6e087c53ee4277704358d31b8f22fd854019a0bc324842da03f908986ec89b715276cae635331297698f964403b438ee60101aa35f43e644cc69d553301a12cfd3a7f6590c4c80ca7ef48dc434de6ab216a0dfa7e97d6be0fdb47a6118f9b5243cae2f244beec258b486e1db026fc8c40e3b061557c74ab010001	\\xc0479ce120a7638db23d660dcfddaaf420841e5d9ba1feb39abd2a09170db67bfb349ab9ece8d9341acff76a50c3b7de4ac402286f46eabad46b285d66ceae06	1661169485000000	1661774285000000	1724846285000000	1819454285000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
402	\\xb967254b0ced034c7f252d1258aedb3f8f18344c2f22a6f456dd6b18b9d6ce1597737856c704ec5b2d18d8fe2918e48f8bb85a788e046598d7432f13fabf0e37	1	0	\\x000000010000000000800003d2fe79213be49be5d61ecfc7cd9a21587f1fa9d4d3a39c53c550645282d61377eaad53f5eceb3d3a2508220af780cb1b78978af180e46ee6f737031a4ae649cb6b4d2a8dc1784e004f37ad686f07ea6af9b94493b02e8149f62688e7e9f24a2e78538c2be05ed89256af17d806a0134cbcca0644787cc895027a1a1bdebbb1e1010001	\\xd09e1c27a5c2a2879c736bfe7c67a6b844aabf7e167a99f649ec023fc71d30fd7ba11c047c1a39c8d8574caede45e610c60a60bfd69d3348ee82a75fedd8ee03	1678699985000000	1679304785000000	1742376785000000	1836984785000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
403	\\xbbdf7acab0d7f05789bdd8c98b36deb82582f96df0748f37911029024a5399cdbe0af9ce4f572b83dde518bd83c41da6e24b845584d15596bdc657d45209832d	1	0	\\x000000010000000000800003b28cf786921fa7c529a5ed072a5e6882ac26c64acc1cd200559490fffe799cb585a33cb206228835a62c7d075269f7d7ee1c36708048e24398b1baf3a0e4c090fd151d6198f5398e8c3718311d2049da16a5ccb6c08e0328ebee88d6f4124ff20908a05933553a3bb7ca12d6b99a923f6220af22a3c1e0457f51d574f49e7e13010001	\\x15304549f31b02339e62554bfc9a0fca2d5354614bd8fea1a84d39944317e14c4c7f5bb11e688af4019b7b76f2324770b497a0605a675d68aadd57c8b3efa107	1686558485000000	1687163285000000	1750235285000000	1844843285000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
404	\\xbc734d81cda618f7a8d3177160f487f665b063b618035e711ed89ccfc8f2c62c3a82584ddef208a7a896e12bf25a23b0b52270e67d3451ae680628e98c6fe151	1	0	\\x000000010000000000800003dc48644a9119ca3f13ba27d87893bed475e260155ec1f4de910187f346b5b0692e639aeee214f6ac58d42bfa8405d05bf5e9a06cf14adc10138849586d399b7650309c093834779a8d2f36e6a3b8fdf52df436003794b16d17c210aff6a10adee31102f488bb379be14a8452e52bf8e9cd979d4c111a1a18c45165f4d6a9dccd010001	\\x7ce1081f92cc4bd4b1e0ac78d1669d684255e5572107f14457fbef6ba8536a9ffbd1276dd0f6ca67b79e364d5f72b20dbb171790f65ea143cc6b669eaec26201	1666609985000000	1667214785000000	1730286785000000	1824894785000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
405	\\xbf9310fc158b2b16fe22a552117003ba2540c4b0c0516addb0edd9b83e57ffcbbbf2e77b278cb63c5729b7772e4121226764496411576f66e2f869f64b08c10d	1	0	\\x000000010000000000800003efdf6bcb9f1a719c3c62dd2062c2cc00d3f8508ff45fdb13844ad50bcdadb407d190e3c4d9c0fd92d29a9578a57fed1fb1a3c087ae083b3bd13d91e06716d173950d0baa39365cdeaff43e96eefddca49be9b2b4c1a8d3ce71876240944671325d4beb85f59b9738b550485260db651ec682a3508576ba0fc86ccdef11b07f95010001	\\x8f3c9395218f5b77792f52be16f0cf80dd7b44768e8b0d814fefceb122de6bd6a22c0b811160a8efbbfcaad49cd1a37ac263f9f51fdda5a49ee383bf85f05105	1679304485000000	1679909285000000	1742981285000000	1837589285000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
406	\\xc0fbb59f9e63c9781c2dde3f733b88f0dadca0fc71aa94a8fd551cf36ba68a56fcd32c3a1a5713aa93ca61e5e9e9ce5a9e965bc3bd500d80f01c0da8aa5f1e7b	1	0	\\x000000010000000000800003cb678c5b8b9b4c60e0c1545f3f37d91d3d71e07fec6722ab866ae1adbfcc012b713a625968a0184ead78254855d4f22df295384ec5d093c826fa422503e5b2af45f4a04a0d2d1830c359e65f16b3748c0c13372d704f0975cc8e7785d2ac16157bdd5f4c6e0680f8702905a395475b6948daa6ba1b4ba333780f6e9e396d4539010001	\\x9ab14e42b227be19fcd5da2fcad828fc83b150e9e0ffefaecd14faf95550f9a4f1decc7bc5fcfd39131ef7563970a7cd0d7e6f6e564c0529fcb70d8e3150e20e	1673259485000000	1673864285000000	1736936285000000	1831544285000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
407	\\xc2372f098e784457f052ffa1aead91c6c969f62158f0b3518d0e6cda040a231289ecdceffb8f228f49a4513e4c4ba212a7015f7e3cf1f07a275671cbe8347206	1	0	\\x000000010000000000800003cb016611076909f5a8ba26fc69b5e52d5e18be389f101958baf438ca0883260d36b2364458719a34b9fc895ac804133affd5ef364d0cbeda512b472d2595fc681fd5126f5f3d8e6b0deb01c779d83c6b49f0f8f46bcb8f1f5651d42a4a6e1bb35d8d6358e1c448402f11a0d1f82e8e93b46b8d42613a0f77da740a8309be608d010001	\\x77f27690b3e1c27bc87708af58cc7894477f37dd3a321de1cf3566c20d52f49877a1068121fbe15178a08f41c5897201edeb1d97f66ed6b22d7f9df0b48b3408	1659960485000000	1660565285000000	1723637285000000	1818245285000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
408	\\xc2ebb18345c06c3334758d0ecd89e88a9e1286259a47d180bb175877342650ea3998ec5e1e9416efb5975d530be05c9b1fa9347a1408fa10d84d193d90f2904a	1	0	\\x000000010000000000800003d01f34ba48ab2bfeebd66f60a3e756254d99fc5035b02d846926ff829b53a836493407ec62f8ccadf4ea3671de680002d3a6dca9ce987a12313a86953b00e88755835e741be6c2673fb4911600c5ea70f48c033a7493a961ecb7b5072633f9f6974b0db5b1b9c3240411bd22f8c9bf14f41b829509cd1e288428276bb006b489010001	\\x72221cf08cdedfce87793d7cf1acdd6ea42da72433d280ad88a0c9d6eb425d0b8d89e142d3092a0974ade31cf8677e032d549177b432c18ea9bc4a42a9ff8b0c	1682931485000000	1683536285000000	1746608285000000	1841216285000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
409	\\xc6bbea5c90cc59185e0101b642a618e77626a0c64c4d47f848e8799d71d09c7a0c914b5663d9a9a408aa9977a687e877288257d482af5427379471d9664b9577	1	0	\\x000000010000000000800003a96b093d58b59a17661f77bfcb36870713419e26cef441f92685d18be93461eb6677b3b795576327248dded9336f90a6e2b9d82855c99a04824ca5306c76df9e383beb0868f01641f89aca31bdc985ac55c54842fe1ba0b6b2644573fdf60c0fc5c15515262a99c60efa43298bb244f73cc1690f7690772c38302afa4bf58ac5010001	\\x04b98dcd5c5e4df25b46b348fa41b9bd53975c72dcc0dc838e183ee9bbf346dc4c8220268c27dda3fc0f61990e17d977d8fc1c47b9bb6409fbec4f6efa2b8e03	1684140485000000	1684745285000000	1747817285000000	1842425285000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
410	\\xc8df493cde13cf839ca7127f6be17e6c98230d9bca89129f0d3e95892fb207b522ebd98c1d9200cb9ae1fc9d1c0c87382254ec1b70cff601ee04d227fb150122	1	0	\\x000000010000000000800003da3ee940523c286fa4626f42d648630f8eb4a4fc018b40f3a35d6b42f721706fd5298779eec7d2d2025caf19357d8b2e72e2e850d61abed18ce40a22d440be6a8334cc1ded24aa988e03d48c8d37260ec55da4dcbb5a4d183a37ad91e924bb564f0e7c231e24c207849179dc30a61e57fda9304cb83a13428538b71b8ae225bf010001	\\x0bc186fc81ecb28b62da8c1043d5ec5412845b56f3e2a6c8d96b57df24d3b97f6f2ee6c09877d50e8d951ab1051acd43fbf038419cc5c2fd40b75a8397db090e	1672050485000000	1672655285000000	1735727285000000	1830335285000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
411	\\xcc7722b98c29558615aa0c0deee7a7ef3e7c02d3d89984a8b90ac2447731570eb9baeeb6f1772245ec7c532c7134102c0bc6c2d4822f662965f7d650f51eb9fa	1	0	\\x000000010000000000800003d906b3dce8961adb19a583859781753ee2ec47ce04b68f953b3c8dcf17068e0503ec1b36dacde99d2ccc979e1804a39b1b7001db08fd42614782a49b61b66bb962dc47a0db2a46560b0a0537212447f5205174ba2d2cf2f4966e74e4be4b9fa6c23afdab181ac57b694bb34ba87990cf665db47f81e2b50567507e12c4933e23010001	\\x3d5318694679cd476b5f50531c051db49de403227fc3ed3c531fa6a814587157636f210abcf87604a532e6777d7eee202d18227a9a184e2e8a2ad7f49952c705	1657542485000000	1658147285000000	1721219285000000	1815827285000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
412	\\xd437452bccef71ea79b7202e4a9ab7d2700289f576ee029eb32d05deb1f76bfc84082c52dee751d3e704c89030d3c8fa24453e08495ff38b84925ef7d3b30045	1	0	\\x000000010000000000800003d75460b390c26c9a4103e54e4a46c51cdb7a53f297018702d79458c401fba95ebbfa4c828eb1c77e8da3b779bd1d5eb4ad232e0144c6aa5b5ac13f6fb8828c93db994d8bbc3b57e594e089f362724a2a4dc1194b84de4099df40b3b210c523eb381d421d082dd11e3850eb19c3230e3ffbe46d323fdeef52f23fb23df797f85b010001	\\x702f6fa0532840350b00b6be281a4d1ef41ca3ae0a1559409195eed9606354e0d95ba7eee6709170db564dbb872ddec0e0bde5e3e600da28d2908e06885bf20a	1685953985000000	1686558785000000	1749630785000000	1844238785000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
413	\\xdad76241ac7c2228f6323612be20c9f90b79a2a29f0fa5829b92d5981f487eba9f150ae978ff53208e350673e2d8c5960aaeeafd958854a2c3bf9cac02475043	1	0	\\x000000010000000000800003c041f57c66a2a8189fbc69b865b9dbd729aba6162c85579270288544f0f2305398739375a4ee8b8950e2c025a77ab708af81b5b75170d2ff5c3603bb7f99e36be791f27353d094bb80f921f41b37dac662c83c1af10c3c004f9aea001bd2b8f1d78e1d51f960d5d8c30aea3789387803cc08c4014ab36bff89be67de66f8fb67010001	\\xaa678d533010fbe06c0967fe3ac4994f665012731d0b00d3829002aac03f6bf8e3f107fb8bf9460486f9c56836bc24b78d1f98e425e30ae523d60d3afde1c903	1684140485000000	1684745285000000	1747817285000000	1842425285000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
414	\\xddcf40f4eb38eeae7923d8dbbaa3db028e6c0ada0f8ef638aafd6bf1491c8f80a3154251cc80a3f96e8af45684fad9b522ca6e5085d3f2f90e48b19b37be5cf1	1	0	\\x000000010000000000800003dca909a59920a154b55cf8a59326f2c84c5e5c6494c37a6b06a1db05ea28c6f8a7d8d9d7fd1317a1f5fc3796614aa12f915e824fd0648dd8e26beb2c345062497b976700c60c2a8934376dbe2e0d8881478f6171750c03f31982ad2391cc6af3acebacc0bd3226d2a2a76bcc74aaa121c817b0afa0c2167d400c074309fdf29d010001	\\x70f4c5e600ad379ee1f0fd704eae743605735b1e5e94dde8a9c17e20f0d4f36f306a02402b030918b7b7e822c657816138dfa9747145b3d7294e8af1aa083d09	1669632485000000	1670237285000000	1733309285000000	1827917285000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
415	\\xe27ff3efba1027fc8090f2d065c87ead38bb47f59aac4244da16c710359ac60e21b93de54ccac310406bd14ecd2f256d33a8251020f63cb55deb4eddc1f1520b	1	0	\\x000000010000000000800003fce956dcffbf5510a3e0a97779271c043039631e5a346de7c38b67ce7b74cc5ccc31c624840b4b7b77c61248edad68c01482cfbae6bc675f3b64b0651151b25b3d013dff0bf0af46d957b03cf4cdaa02925d5ab19695c5375047c61dcfe3c1c14f4763e59c290bdff1827bdd8d761618fafec1cc65219131639a64468b162511010001	\\xe695116fa2538a2ae74123b2ad205cd0d7d0bdaf7ca7c90bc2be2aa5a6f1cc1f9228136d12ff724aba229199b9e1992438b7571c5f1d1a399b9269cad95fbd0e	1685953985000000	1686558785000000	1749630785000000	1844238785000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
416	\\xe88307ef92db2d55ac7d01610ea4965997a576f5639129e00b6900aa779cde24802e183f45b762363b6041f76007fdff0223f9bb021784c808d5ecb8716971d2	1	0	\\x000000010000000000800003c0a74f40a0703508b8cde71bf251dac0e1e01b008f39bdab7e5c3298b3f3e3d16222bbb0149a3aa60bccd24f594145674353cbcea4c1f8f40ca59c58aba7cf1d28968d11096c49bc23a682ec25a3c1194297be06d53b6bd4fb18ebea050c3fb9fd5d2604d2b8f98592a65a1eadeece40f91a5eca5f715a9c9d01b6570d58433f010001	\\x08f35d338377b1a512b0d518bd16ffb82b9b0b83321eeb29c4c1fed1f88774662b0800bfa7f918d49411cdd95005371861c926f9272dea9b199d71de95c2ac03	1665400985000000	1666005785000000	1729077785000000	1823685785000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
417	\\xed3b95edaa6249c45501ce118bdc85362b4958319405dd044868c1f7767f1053c23dec062a1f0541b6d3eca6b01e37ba75e81366e6777fc036c9f81042a5ab57	1	0	\\x000000010000000000800003c0e8b388e882a83cc2290075641e6206085f5b10ec8dc5f9cd17116512e155b87cecd9c98c8498b51c2ebd7d382eb5aa03b8f151b47cc545ed2e22de6471f0813a42dbe8cf83d1eca51a13258788f7be8da581bc54f85e022a10069ebff898ebaa4e42f359794b8856c08302610cd0ebee5076b7546f042fcfa02d5c3d0db629010001	\\x57e7dd731fb26c11f3fbcaa0beb6eac9fc874b34f769303c14691e598a45536a0b05b6dd0bb48ee59f39bc3648d032c4754c448dd0c4816d7991b8a21b4fc30d	1674468485000000	1675073285000000	1738145285000000	1832753285000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
418	\\xf15f13aca89b0fb4da9d26b79fd0c87d331212aca58d5d60b1a4a77c35c266584fcd4c5685917e5b7b1d655b047c345ff1059430e736def49112e41841b2bb5d	1	0	\\x000000010000000000800003a7ad50228b1fe61d1ca834263885dec731e3bddd7ac341022341721b4553f7d97b9f849b392f9e6c331ac45c8dd3066b97072fa2ef12aa5df8048a2884cba10d2f7d498d9ed34c4037e9b0af2f27fed8985936b8bac1e4318414275e5c808d8b386be5944ecd65a06e61426be2f507b8a460c9a286f6b75e4bd3761e378e48c1010001	\\x9a4173ec8399185e21cc968d3f291d1900fbd437dc94536e89b7fa29e7d919075e116d0d53f1700107e6732702a6575d08a9f6ff38c3c1948d9ee5e5bc29cb07	1672654985000000	1673259785000000	1736331785000000	1830939785000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
419	\\xf1dbd8acb09cd851cf3e1ccdf3d8cd9788db41a869dc3e116457a5dc695730154f7e704ccc500c91dda013ec7b31a094816b569943563ba7f816c9910d61321c	1	0	\\x000000010000000000800003b3e5c2ba148e480a3bffd6555daf7eabb8123711e0f8a5e01a97c851f1f207310ce0e336eeb8b9539d4a81219f7ba874d456fc8c8c26b197467503b1c599b0b25874b97956645bf0e1639b4558b0a01e7ec76220b5df3feb1e39d9b41fabb317df1094ec105f9e225172c3a304798c882bcb718813d3301167528cbc22d8fb53010001	\\xe46608de56eb69e9776b3763f1d32019e7404a45f5d92b34c4f330acee197b59fb8c4b95a6d5418a9d3ca7d0f6ef29c1bc89a950bab88367ae4b0c4408a4db05	1661773985000000	1662378785000000	1725450785000000	1820058785000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
420	\\xf7d7e13422f91a0a648b4072834860d20be1e25e10e624769c75a0a1893bb260cdafc6e263ea1ea705aa9c3ae516e98c5ae98cf45456efd0a2c1322c1c8da4f3	1	0	\\x000000010000000000800003abee943ab486baae28d6f776db75180a4c996bd46c644067381902a5bb81166567d07fb6be6d93869d685eae6e76f0b52cb80ebd57879286f9e1c0c50294302c614147c3562a14010c34e12383de3dd45d8f45c285b54444b327dafd84bc51182858c89f076005945483d48a221e1f84b6ea9447e053b6f5d52ee2bf606ead69010001	\\xec9135aa19e2e181ffef25da530f996d4862f560548e117d8d57d97091090167265a885a1b3e145a5482387197103e5b00baa0ceb8f6abf91355f2573385340f	1666005485000000	1666610285000000	1729682285000000	1824290285000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
421	\\xf99b7caa442b60216379334bff9e1cfd061fda0e73838016e6e57e90f0fdef4170a35b49935e527a8826a517fad14275b10ef2269a74ca136b5cf98bb0c6723e	1	0	\\x000000010000000000800003b82d7facc7801751cd29ae7600c7d815d1cd12ce8c0526aff76864db5775cd30adcdeac9845b2f539ca1935216eec469b13cc55eb6d8085dc6c5b51580ae8f83200e6bf67143be1154f4e731991c98828b092f7a382b014af3e35de5b96c0a101ede56ceb05adbd2a9e8737e054f2706507b5455495174437dbdaa950482dd3f010001	\\x6d2db8ac4015344cb62dac86c257921d9d886dc4624ca4f379d5795b5a0b4d7f0fd26353c9093c4a7f87ccd93dd45daa3c6c80f91d35069b04b282528098230c	1679908985000000	1680513785000000	1743585785000000	1838193785000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
422	\\xfa1f7fb8fc8b925b1d1eae54823df217079da187376233b4347c59b0fd89a73a8de416594a86e292ddf260e01ed0a98b4c53adad909c65f90bd31d33b1315bfb	1	0	\\x000000010000000000800003b694fbe061f8a80198e81d9afc97c364ea0480a2e79998dc02969b666b752c20bacd5860efc0cd4407a6f5b3f7ad03e246f162a641645bb877ea3158fd59a1060dcdb5ea1f0584c29bd5247fea13a210ff121d11611387a9fde76a008a3146919413160b1b8978a20e5c4e97a2f1b1b1184d2c2ceeb13deab0fb2f996c0847fd010001	\\xb135dde815833634bc6ad59ed92627804c5c61b23af407e010bac7e7d4dc17ea267400c2d63c50b344d9593c13a49ab7750f6d61b356d4d7db3fc5334d299c02	1676281985000000	1676886785000000	1739958785000000	1834566785000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
423	\\xfd0fc9798956484b5d1ae0d361a68d9493ca624f93aaef7063cd56e3bff7c61b29215186483842e4cc379d84626f6722a2ceca34fcedb94d4c227f2f3ea69db4	1	0	\\x000000010000000000800003b776074c6a6d308dd1579308d840bd9a0f2ddba69f302e2238476f1b52a4488e5719c2950618b5f876da5fd7ca03302693940b24ad2ee45a7621aa379718acf5622ed6dd7878bb2e0013041c38fcc662c57410ce7b9e78149d5621a1a78e0874e946eeede12a468e3ed532ae2b3de5e9fac660e27d0a48bbd456fc290542edc1010001	\\x41339725ac6dd8bfde1a216ffcc2f1a0aa75a230f86285f2bde2620a004e77b75abede5fc2438983f33431d96c595241518546e9d4815d41233092d76460bb0c	1661773985000000	1662378785000000	1725450785000000	1820058785000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
424	\\xfe0b523c819019eb140770f63b69cf5f2c3935c4090d33d7f8b4fce46785ac14f2b50be2daeee5f03be1d7ac4e40f8dfa2a5d82bf0df0b4cc140d71142a17d77	1	0	\\x000000010000000000800003d85d15b999f0c6d136c8893e3b7f11421182afa4ffd0cc24d24d09cba2a14583b3601a9e312230de4d26dae350510627140aecdb95791d5b13946686ddb1c946ae7a1f54ca1ccc1b6b1944b53c8b6da3014b36ee46ef7889b4fba782d1bcd30b97f663cca7f80936fcb704fd6bf13f1ff50d4cb9afeb849b4d23db8fb4f8bb29010001	\\x3c728059d289e030509d4a5605f3ddb9266ecf3aef45586dc21ec0d3034c58682ece2d129c1ed4fde4474e179763b0c3c884f6bcaf110ab1ff162aa67357ce01	1655124485000000	1655729285000000	1718801285000000	1813409285000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x85961666db33889a3b42b74cb7f36b83de85a9c125005c49652304877831e905	1	\\x1f9eec971fa70a3d36c66616e8eb6a9077e35554b7540c928ade21ef72ac8b7af7686f248e83bd0b1b98a55a9979c2a2e1dac67b4f28853ddf2fbdcbab93d9a4	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x5380a512026f078b45fa64bde365301774ec6a2964ed54fa0ee9601ce3c00c9cb37a6c3e26cd5b5e6ae29461c7aeca7125e5bae9c929ccc92b96cb0b2b2c2084	1655124503000000	1655125401000000	1655125401000000	3	98000000	\\xf14999286fb5b1748730f1abffc423514abfb15743e259f443310a1d348c8014	\\xb01ef17fa8db7e4b8f705f0046af028d9d59258330a33d9980471a4cb14936ac	\\x1f2e0212ffe7b04eb631ff3f821a6b2aaef751023ec6ff1e38a77bca154c4610030d3d1495217b83083781c0bae1f7982cfa6f4f5a9789eb4bea1d478d831e06	\\x8c817cb9a5762553935b50a9b62cc06817c747b79ce32dfe7347e8aa199df88a	\\x20c8a2e0fd7f00001d09167933560000adbc5479335600000abc547933560000f0bb547933560000f4bb547933560000e03f5479335600000000000000000000
\\x85961666db33889a3b42b74cb7f36b83de85a9c125005c49652304877831e905	2	\\x9f700c9cf100657049820c5825000e4b3821eb4ea3778483ed20545fc5fcf3e56904f9c6701a5b27d087c6f4727aad542336f2ba2fe28d5649895c784f54dc1b	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x5380a512026f078b45fa64bde365301774ec6a2964ed54fa0ee9601ce3c00c9cb37a6c3e26cd5b5e6ae29461c7aeca7125e5bae9c929ccc92b96cb0b2b2c2084	1655124510000000	1655125408000000	1655125408000000	6	99000000	\\xbd3df484b6874e48478333300df8398720935e1b7a662e769cde72df6753117a	\\xb01ef17fa8db7e4b8f705f0046af028d9d59258330a33d9980471a4cb14936ac	\\xe257a7b29220fdcc0cd9f139e542eeb770795ba146f8e4f2323d56640133d21c7f3b2f514d442c70b7f39c96447a43a322798d03e9f68be8e413b452f966d409	\\x8c817cb9a5762553935b50a9b62cc06817c747b79ce32dfe7347e8aa199df88a	\\x20c8a2e0fd7f00001d09167933560000cd7c5579335600002a7c557933560000107c557933560000147c557933560000c09f5479335600000000000000000000
\\x85961666db33889a3b42b74cb7f36b83de85a9c125005c49652304877831e905	3	\\xa3b31ed807d218b51bcb29c7a2bc87acdc933d91794b6eaee0aa528538268045ce8ff42820834e7d22596495c9d9d23a6c487f16a8961e2e65fd288b363a43fb	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x5380a512026f078b45fa64bde365301774ec6a2964ed54fa0ee9601ce3c00c9cb37a6c3e26cd5b5e6ae29461c7aeca7125e5bae9c929ccc92b96cb0b2b2c2084	1655124516000000	1655125414000000	1655125414000000	2	99000000	\\x9df2e2a223bae300dd9b6b33a84d0bf59a8e5599de90366a8a37f02a1123d22a	\\xb01ef17fa8db7e4b8f705f0046af028d9d59258330a33d9980471a4cb14936ac	\\xdf33a4f16a30c364d00027b988cb24337212852202946da5549360379c4f1ae9a51478395b12b6d0c93aef117fde42349259d63c7c468ce57d9462348ccebc02	\\x8c817cb9a5762553935b50a9b62cc06817c747b79ce32dfe7347e8aa199df88a	\\x20c8a2e0fd7f00001d09167933560000adbc5479335600000abc547933560000f0bb547933560000f4bb547933560000f0a15479335600000000000000000000
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1655125401000000	1273790493	\\xf14999286fb5b1748730f1abffc423514abfb15743e259f443310a1d348c8014	1
1655125408000000	1273790493	\\xbd3df484b6874e48478333300df8398720935e1b7a662e769cde72df6753117a	2
1655125414000000	1273790493	\\x9df2e2a223bae300dd9b6b33a84d0bf59a8e5599de90366a8a37f02a1123d22a	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	1273790493	\\xf14999286fb5b1748730f1abffc423514abfb15743e259f443310a1d348c8014	1	4	0	1655124501000000	1655124503000000	1655125401000000	1655125401000000	\\xb01ef17fa8db7e4b8f705f0046af028d9d59258330a33d9980471a4cb14936ac	\\x1f9eec971fa70a3d36c66616e8eb6a9077e35554b7540c928ade21ef72ac8b7af7686f248e83bd0b1b98a55a9979c2a2e1dac67b4f28853ddf2fbdcbab93d9a4	\\x38c3dd94c7d2f41be35cb3781478eb90beb3e46b7c9b09015cc3d2c9b0704231a5cf75c8546601da708a733a0b8e84362fd54ea686925992ff98891742865105	\\xed9159ef66e345230bbd1312f05291e8	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
2	1273790493	\\xbd3df484b6874e48478333300df8398720935e1b7a662e769cde72df6753117a	3	7	0	1655124508000000	1655124510000000	1655125408000000	1655125408000000	\\xb01ef17fa8db7e4b8f705f0046af028d9d59258330a33d9980471a4cb14936ac	\\x9f700c9cf100657049820c5825000e4b3821eb4ea3778483ed20545fc5fcf3e56904f9c6701a5b27d087c6f4727aad542336f2ba2fe28d5649895c784f54dc1b	\\xb61ccb197bec2057f6704d80fd406e21fd0493e7198b9318cf0a7ec38812c1e78c88cba4f9a8c9558a69c01643b3e3e3a1cb05e1138ba4d1eb331aeabf7ac604	\\xed9159ef66e345230bbd1312f05291e8	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
3	1273790493	\\x9df2e2a223bae300dd9b6b33a84d0bf59a8e5599de90366a8a37f02a1123d22a	6	3	0	1655124514000000	1655124516000000	1655125414000000	1655125414000000	\\xb01ef17fa8db7e4b8f705f0046af028d9d59258330a33d9980471a4cb14936ac	\\xa3b31ed807d218b51bcb29c7a2bc87acdc933d91794b6eaee0aa528538268045ce8ff42820834e7d22596495c9d9d23a6c487f16a8961e2e65fd288b363a43fb	\\xca0ae7273ca957c1f84366ddf06cd74ac776b9778bac0ca7a576b01b758b77ba0f8d11c8208ff560c8c1c8ec17f1a95d6f8c34bbbfdf7dc26a59649ffae87f02	\\xed9159ef66e345230bbd1312f05291e8	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_for_matching_default (refund_deadline, merchant_pub, coin_pub, deposit_serial_id) FROM stdin;
1655125401000000	\\xb01ef17fa8db7e4b8f705f0046af028d9d59258330a33d9980471a4cb14936ac	\\xf14999286fb5b1748730f1abffc423514abfb15743e259f443310a1d348c8014	1
1655125408000000	\\xb01ef17fa8db7e4b8f705f0046af028d9d59258330a33d9980471a4cb14936ac	\\xbd3df484b6874e48478333300df8398720935e1b7a662e769cde72df6753117a	2
1655125414000000	\\xb01ef17fa8db7e4b8f705f0046af028d9d59258330a33d9980471a4cb14936ac	\\x9df2e2a223bae300dd9b6b33a84d0bf59a8e5599de90366a8a37f02a1123d22a	3
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
1	contenttypes	0001_initial	2022-06-13 14:48:05.344943+02
2	auth	0001_initial	2022-06-13 14:48:05.485798+02
3	app	0001_initial	2022-06-13 14:48:05.580374+02
4	contenttypes	0002_remove_content_type_name	2022-06-13 14:48:05.598869+02
5	auth	0002_alter_permission_name_max_length	2022-06-13 14:48:05.610731+02
6	auth	0003_alter_user_email_max_length	2022-06-13 14:48:05.623675+02
7	auth	0004_alter_user_username_opts	2022-06-13 14:48:05.633811+02
8	auth	0005_alter_user_last_login_null	2022-06-13 14:48:05.643634+02
9	auth	0006_require_contenttypes_0002	2022-06-13 14:48:05.646838+02
10	auth	0007_alter_validators_add_error_messages	2022-06-13 14:48:05.657002+02
11	auth	0008_alter_user_username_max_length	2022-06-13 14:48:05.673831+02
12	auth	0009_alter_user_last_name_max_length	2022-06-13 14:48:05.684992+02
13	auth	0010_alter_group_name_max_length	2022-06-13 14:48:05.698898+02
14	auth	0011_update_proxy_permissions	2022-06-13 14:48:05.712833+02
15	auth	0012_alter_user_first_name_max_length	2022-06-13 14:48:05.724089+02
16	sessions	0001_initial	2022-06-13 14:48:05.747258+02
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
1	\\x6abf4915d79978de92d9409f4642e3c44a17de6cb9e6e822116188d10a86a763	\\x1b7045ce4da855dfcc4872f3b605f2afe5be3973c7f7fa283c18265544e16f860a7d623bb2e812638d5b5fbb38a9e03b3ea9e7c334a4d9bf8affb1809ff6210b	1676896385000000	1684153985000000	1686573185000000
2	\\x8c817cb9a5762553935b50a9b62cc06817c747b79ce32dfe7347e8aa199df88a	\\x56178324eac9031cd89733ce4c7959b6f5550247d5d857156bbdc256f1b8dbbef04c2844b7bbc236eaee777cae7e2415bcfb664b70fbee02841a873b6ff82a08	1655124485000000	1662382085000000	1664801285000000
3	\\xd08a082e5f324b1d9de93b0b298f21909082e4ea1ed31fc5fa6d326384123a1f	\\x59aae44aa4108d643a003c71c2a2c1ed0b4aa8099a064444a3e9f2b95aa8971ce3082511787ae6eeb993b4a5f7faad9f861dbd520b04b69b3d898f850c2ac204	1684153685000000	1691411285000000	1693830485000000
4	\\x359bd5182b6d2aa13be95ff9009699f2e47aae106252b38a3e0e3c26d92bac91	\\x4d5827cc9dfa7343d380e33761614e4e421954d3ad71270e5ac4247f50f30bdfd33c45c950086e4a0fbbcb21c81d0fbba7217a416c7229ffb7eb0279a2b43108	1662381785000000	1669639385000000	1672058585000000
5	\\x993b43ccb24897068613d63871623ab7c8ab51ea86c7d6653f9fa3aaec434537	\\x9ac98a52e8cc2ecf8b38daf63427faa31cea7edda128b92dc372e4d0e177655cb318490ce8d0325a4d3e4d5a87ca6c28a70624a82feb3151dbbba30297fb1305	1669639085000000	1676896685000000	1679315885000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\xc243eafcf720b88760aadd4ad84f9c32247ffb3735c0ff6c3f869a7e9f6bd8a9581e4524a3fd5cc551c44fb6b3c567106ec0bf69743f629fdc0386af606edd01
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
1	128	\\xf14999286fb5b1748730f1abffc423514abfb15743e259f443310a1d348c8014	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000008179a99187dc07cc31f79978d147578254bd02d40e5c45b31d117833853407181d4e24b60461cd864ddc35205a4b7a69e314bd59035e422f62911282c121d90b873644b8904217ca095ffe768466aa398e304e4647d5cc5c70ba8880cd0094a63991ba92e1dafc58fcda71a1b934d6ead5f72961e8a516cda2dea10f86a280b	0	0
3	52	\\xbd3df484b6874e48478333300df8398720935e1b7a662e769cde72df6753117a	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000095516d7d7c45a84790631e5b0edc1ce296717a7854f6a94a42b7d178bbb87ffbf3a1b7ade7f8885506a7f57f4b69b4c237a04021195e93e1e6bce373c85e3219a2151d464169e954f67e8b9ed1a382f208dbe88bdd8e525b53142a3f28dd09d77a10c617af9a754b870e59c58e2e26705231643dbe278cd1714f15530247a496	0	1000000
6	86	\\x9df2e2a223bae300dd9b6b33a84d0bf59a8e5599de90366a8a37f02a1123d22a	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000009513ccc8c1473585965380c37eaf6801d58f1523fdbba34c0dc460207cf9aae353f68d7ae3a02d6fd5a0e337e95466e30f6b31d9b3c616d06d5d5377a6ba5fe7547bc021ad9213e7fa5aaafe20301a82602777abbf1c2f6ca57e42a2f34514a2f7295b8de75add54b9cf38a774cacd6c390f6cbe1a9814912d0729e7f333a550	0	1000000
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x5380a512026f078b45fa64bde365301774ec6a2964ed54fa0ee9601ce3c00c9cb37a6c3e26cd5b5e6ae29461c7aeca7125e5bae9c929ccc92b96cb0b2b2c2084	\\xed9159ef66e345230bbd1312f05291e8	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.164-03C5NEW3DAPXT	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313635353132353430317d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635353132353430317d2c2270726f6475637473223a5b5d2c22685f77697265223a2241453041413447324457335250484654434a5959365339473258544552544839434b504e395947455835473153525930314a454236594b4337524b435450545944424839385245374e5635373239463551424d574a41454353344e53444a524235435032313130222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3136342d303343354e4557334441505854222c2274696d657374616d70223a7b22745f73223a313635353132343530312c22745f6d73223a313635353132343530313030307d2c227061795f646561646c696e65223a7b22745f73223a313635353132383130312c22745f6d73223a313635353132383130313030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224750423143535056364534394d45543250583642465756424746463842414531344d3035524a4235344332384559314858343247227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2250304646325a583856445a345133564742573034444252324850454e4a3943333632484b56364330385744345343413936545030222c226e6f6e6365223a22303945544a51413551484753313834384657364e583233484252514e4e575941544e444e324e4e4243365643525345424e544630227d	\\x1f9eec971fa70a3d36c66616e8eb6a9077e35554b7540c928ade21ef72ac8b7af7686f248e83bd0b1b98a55a9979c2a2e1dac67b4f28853ddf2fbdcbab93d9a4	1655124501000000	1655128101000000	1655125401000000	t	f	taler://fulfillment-success/thx		\\x3efad7e4b4a08d1f2580d50f0713001b
2	1	2022.164-M3V1C12MFC5G4	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313635353132353430387d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635353132353430387d2c2270726f6475637473223a5b5d2c22685f77697265223a2241453041413447324457335250484654434a5959365339473258544552544839434b504e395947455835473153525930314a454236594b4337524b435450545944424839385245374e5635373239463551424d574a41454353344e53444a524235435032313130222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3136342d4d3356314331324d4643354734222c2274696d657374616d70223a7b22745f73223a313635353132343530382c22745f6d73223a313635353132343530383030307d2c227061795f646561646c696e65223a7b22745f73223a313635353132383130382c22745f6d73223a313635353132383130383030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224750423143535056364534394d45543250583642465756424746463842414531344d3035524a4235344332384559314858343247227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2250304646325a583856445a345133564742573034444252324850454e4a3943333632484b56364330385744345343413936545030222c226e6f6e6365223a225a4a333846514d545836445346573850424d48524a31334a37344b58415936394442503532535335435a4337414b585233463347227d	\\x9f700c9cf100657049820c5825000e4b3821eb4ea3778483ed20545fc5fcf3e56904f9c6701a5b27d087c6f4727aad542336f2ba2fe28d5649895c784f54dc1b	1655124508000000	1655128108000000	1655125408000000	t	f	taler://fulfillment-success/thx		\\x184d5042b2ca18d283b66f6f59d69b12
3	1	2022.164-01T53Y40Q8M7R	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313635353132353431347d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635353132353431347d2c2270726f6475637473223a5b5d2c22685f77697265223a2241453041413447324457335250484654434a5959365339473258544552544839434b504e395947455835473153525930314a454236594b4337524b435450545944424839385245374e5635373239463551424d574a41454353344e53444a524235435032313130222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3136342d303154353359343051384d3752222c2274696d657374616d70223a7b22745f73223a313635353132343531342c22745f6d73223a313635353132343531343030307d2c227061795f646561646c696e65223a7b22745f73223a313635353132383131342c22745f6d73223a313635353132383131343030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224750423143535056364534394d45543250583642465756424746463842414531344d3035524a4235344332384559314858343247227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2250304646325a583856445a345133564742573034444252324850454e4a3943333632484b56364330385744345343413936545030222c226e6f6e6365223a2251565759384b4a5a484b3646364a583656365245574457505a574a46534652583048334b4444563341483247514a503038354347227d	\\xa3b31ed807d218b51bcb29c7a2bc87acdc933d91794b6eaee0aa528538268045ce8ff42820834e7d22596495c9d9d23a6c487f16a8961e2e65fd288b363a43fb	1655124514000000	1655128114000000	1655125414000000	t	f	taler://fulfillment-success/thx		\\xeb9252c44e4c9ee4292544f143278b61
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
1	1	1655124503000000	\\xf14999286fb5b1748730f1abffc423514abfb15743e259f443310a1d348c8014	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	2	\\x1f2e0212ffe7b04eb631ff3f821a6b2aaef751023ec6ff1e38a77bca154c4610030d3d1495217b83083781c0bae1f7982cfa6f4f5a9789eb4bea1d478d831e06	1
2	2	1655124510000000	\\xbd3df484b6874e48478333300df8398720935e1b7a662e769cde72df6753117a	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	2	\\xe257a7b29220fdcc0cd9f139e542eeb770795ba146f8e4f2323d56640133d21c7f3b2f514d442c70b7f39c96447a43a322798d03e9f68be8e413b452f966d409	1
3	3	1655124516000000	\\x9df2e2a223bae300dd9b6b33a84d0bf59a8e5599de90366a8a37f02a1123d22a	http://localhost:8081/	3	0	0	1000000	0	1000000	0	1000000	2	\\xdf33a4f16a30c364d00027b988cb24337212852202946da5549360379c4f1ae9a51478395b12b6d0c93aef117fde42349259d63c7c468ce57d9462348ccebc02	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x85961666db33889a3b42b74cb7f36b83de85a9c125005c49652304877831e905	\\x6abf4915d79978de92d9409f4642e3c44a17de6cb9e6e822116188d10a86a763	1676896385000000	1684153985000000	1686573185000000	\\x1b7045ce4da855dfcc4872f3b605f2afe5be3973c7f7fa283c18265544e16f860a7d623bb2e812638d5b5fbb38a9e03b3ea9e7c334a4d9bf8affb1809ff6210b
2	\\x85961666db33889a3b42b74cb7f36b83de85a9c125005c49652304877831e905	\\x8c817cb9a5762553935b50a9b62cc06817c747b79ce32dfe7347e8aa199df88a	1655124485000000	1662382085000000	1664801285000000	\\x56178324eac9031cd89733ce4c7959b6f5550247d5d857156bbdc256f1b8dbbef04c2844b7bbc236eaee777cae7e2415bcfb664b70fbee02841a873b6ff82a08
3	\\x85961666db33889a3b42b74cb7f36b83de85a9c125005c49652304877831e905	\\xd08a082e5f324b1d9de93b0b298f21909082e4ea1ed31fc5fa6d326384123a1f	1684153685000000	1691411285000000	1693830485000000	\\x59aae44aa4108d643a003c71c2a2c1ed0b4aa8099a064444a3e9f2b95aa8971ce3082511787ae6eeb993b4a5f7faad9f861dbd520b04b69b3d898f850c2ac204
4	\\x85961666db33889a3b42b74cb7f36b83de85a9c125005c49652304877831e905	\\x359bd5182b6d2aa13be95ff9009699f2e47aae106252b38a3e0e3c26d92bac91	1662381785000000	1669639385000000	1672058585000000	\\x4d5827cc9dfa7343d380e33761614e4e421954d3ad71270e5ac4247f50f30bdfd33c45c950086e4a0fbbcb21c81d0fbba7217a416c7229ffb7eb0279a2b43108
5	\\x85961666db33889a3b42b74cb7f36b83de85a9c125005c49652304877831e905	\\x993b43ccb24897068613d63871623ab7c8ab51ea86c7d6653f9fa3aaec434537	1669639085000000	1676896685000000	1679315885000000	\\x9ac98a52e8cc2ecf8b38daf63427faa31cea7edda128b92dc372e4d0e177655cb318490ce8d0325a4d3e4d5a87ca6c28a70624a82feb3151dbbba30297fb1305
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\x85961666db33889a3b42b74cb7f36b83de85a9c125005c49652304877831e905	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\xf41030a0b734a6e667554a11d20d01f6329e498210cb3f27a0dc713a770b02a8ad3bafce2ad8b5d00fe62dbcb0daa68aef7edd52f2d656ba636ef1b9fbd0ea01
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay, website, email, logo) FROM stdin;
1	\\xb01ef17fa8db7e4b8f705f0046af028d9d59258330a33d9980471a4cb14936ac	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000	\N	\N	\N
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
\\x41acac6602c6420292b18f28b71cf5ff2d7bcc3e18668dcb6a407c4191da3639	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1655124503000000	f	\N	\N	2	1	http://localhost:8081/
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
1	\\x3f50ff1c22deeb4dad8d51845b11fc9e335a1fc27989708b2232a3ba54e7511558d0e254b56a4a240390c51710413199dcf477819247336b8a1cbe0441a1a90a	2
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1655124511000000	\\xbd3df484b6874e48478333300df8398720935e1b7a662e769cde72df6753117a	test refund	6	0
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
1	\\x713fb1d0a20f2d0fe4466b647e14f6f37510a80347e826686df2740cfcfd52da1e5bbde3d5d47db0a5c468d69899995bb0f55b127f8046df10c474cf393a7075	\\xf14999286fb5b1748730f1abffc423514abfb15743e259f443310a1d348c8014	\\x45e51d98cbf81488ba841dfe595bb5c146be442ef4d6a71df00b946f3d20343326f1ba40aaea4d12bf17cb2bff3a21e6a21ca361f2336b4a72355cf85edb170a	4	0	2
2	\\xb3ca501f31663a80f541c38163fbc0030b7ee0e90832714c55da9ec8ede84f54c9f5c6abc1b380552f750e64d9e695d9f479df9d92542218354af6a0d7d24e4c	\\xbd3df484b6874e48478333300df8398720935e1b7a662e769cde72df6753117a	\\x726bcd216c96bcaf54d4f26fcaba2ab2424a94486ecd3b7ec9c1f11f0de16734e37226d9cd98adb08ef7c2bba941d71eb5eff283ce8dad9e73b1de587b236f0c	3	0	0
3	\\x0daa588017af7eb0de01b0af6899820346114ea42f6ee094069ca951f03fba476f36ebf12ad6cec34f32595494c46e99709391eb1a6e51dcd87c3f592d83307c	\\xbd3df484b6874e48478333300df8398720935e1b7a662e769cde72df6753117a	\\xbfc42fb6cc87e9128ea28af04578134f989476d5224f75725dbf74f757df34bf5776b6608e59296083a24066f2ff22ea0ab9e5443a2898dbe6406b2a5f998b0c	5	98000000	2
4	\\x65f7076a3b491a3ce6e2b8f46859dac8f483ec0269c88da92f9d77be1f64be541b9c267c071153cd34199141b83b283104d0e0dc9dd37157c086d7f6f306686a	\\x9df2e2a223bae300dd9b6b33a84d0bf59a8e5599de90366a8a37f02a1123d22a	\\x93ab3f50032a9c70e68cbe466cd44188163d665575aff5d5aaa379b0c141ab1331b89716d19c15acdf2eed52718ec6840d16ac99bae695adcb24f1cef66c080f	1	99000000	0
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\x7f1a451cd0572e0e4c6a3083e607c99b63c5e0d7ed5b60dee37a5229ebb9ea0c03fc7fe486efaae750771c2b57c7028bdbb7ac6ccc53bc8ff9d9cd77c68bce08	243	\\x000000010000010096c1c6702b1b606e00f9622f714ba84cd11f304621133c6f9be5b3ae5ae1f70db9cde3cea64a2e3503d2c83e0cb72947f97a06928410d60bd64fab42e3a967bf7c5f5d4fd1ea5afb70037884499451fe8fa42ce1c309e533f68f6f473971823e76cafbc057b58e483f428bbe7e74e3ee98c215791973f1a68cce471eb8fd2799	\\xd84db7a3c7067f10941d0fe3a919aaa582ef1bf50904197d16be09ba05d811f86d6e28dc8b7706ffbeb401b52b8aa86377c0772bf8215ff0674a15b41882620a	\\x0000000100000001713f6013172244803e3555f70d40a69b8a81e50a8a95dadb7a6a31e7ed7fecc741bbd1e5f994f2e68e29646d66d8062c60d5f00f4bbdf21ca63d16d841c4e37d31f24b23d18ed3f4b873e3cbdc3fc1ebd7c38f2aa0007476f297150f33102224220e3adfe602c39210abe3b36e5245c32555df4ffb5d1213862e4665c6ea1f33	\\x0000000100010000
2	1	1	\\x48fc71a42d4a8b60dab30d0bbbdc301bccf4731efbf0e7916b131998fb0f6952661069d6db2b78be2a4081c672433682bca9fd0e44df52c82cb68c3b3960100c	424	\\x000000010000010068ea5dc3e9832df766ca83d89592114df83fd8a09993f70a73700b2515baa760678bfae5d3e0922c3e86144069ef6161849992516ea03e68c83b17eb60fc3deca0497fef0545c19051ee606b97af5c27f6296497f83ca957fc83e63c54dbebba153c7589a66c1b67fcf8615c83275b046954fece9d999733c5efc2eebdcc7352	\\x29418f2359022325734ad9a427e002168ea16d9a05abbee03b09ca1712b3b43633d9071b570e08e917d9fb872d7de8546d80ca4fce25ce0ebef5acfcaa3f6fdb	\\x00000001000000012a45ac1eae1e3e23255459508f3e73eff295789002e3c2a24cf06dbbd88697132f1e31e09e291406e3c9c04db998b322dc7d5eef0261a0cfafa63b95e52d002a9fee1e6e83da7b087a3de3c4cf7de013c0c6b747f71c64706193dc9c897631fb126cc2e6fdf8ae7e720eb48b1b8cb49eca34d4e73a3197d63650eec81741c7b2	\\x0000000100010000
3	1	2	\\xb39db7da8b1a5ae11ac7eade6c1c9ce3eed42f31ad9c9f8c353caac983d303cd5a0859bde659aca5cbc7bdacdb6fe57c8956b102fe8907bda2268845fb802c0b	289	\\x000000010000010084dd5d27c5450ca696707a8d3cfd67eb2428caf26d501737b729b341a76653d9de0eec8429f1eaec16b76a478335c580372f0f5f78179cae0aeb77835e78e1b0f172170c7e1dd8f34d542ea3fc420b9600e72aaaa1384695563ded537cfbcf39b7c9faefe13127794d780e0548039239199e55004ad8416f262e8a72d97b450e	\\x191ac3512c0b3da155433e7d14afb53a06ad70ee6d0c360e2c3de5eec12353e2270638318bf8e371630e687add7caa655d2fd55c788e69972c682d1b286ccaaf	\\x000000010000000143e56864a8cb21394dfe9a7276836002ece4e10824489122cca9e971018b947482814392f0bbfae4071c9c24fa852108c2fb6c427155dc448e765eb0f992b918ba3a51541be5653711b5ccc97a18f7963fbb550bf6c19111d57886d2b393ea484a1dc2b04973dd7be66b7cba2e27f5a00c9691d48fbedb5dfa86e975ffcb3b12	\\x0000000100010000
4	1	3	\\x38e2c38c66a53aae8a4280f2713bad4148147b7b30ec4421d3a1d87d6b74fc3fb4f18f304a929882f539f0adb618cb3497e09653dc360055a6ee621fd209a703	289	\\x000000010000010085c816dbf04a9e5b0da43466d54ecd6cf905dfce1820aa66fbd7f00df9c5bb1a973b586a5a1bb78f67f2df9dacbe103811c5d8a035b5f3b1fec50d9883b4fb31dc59e9f194790c847bf7d56a8e1ee2239611824c89606e6a10e7dbfa691b6b13e2df39c526cb08cf7afa044595e42456204f879574807fdbfdc61ba0e6e82c75	\\xf60ff96b97c5c3e46878b2ba8d67392a70fc35fb13fd19e812dd91a07c945082630335a7b129c87891afd2013e6a7c3dc7541110071e12c03cdd6f701e5d41c7	\\x0000000100000001a4949655f8d7fb76a58825f31ce158295e8be1b52dba96429afee6d329049a63a58a915bdf3dee310550731191d779f986d6cc3776ae214d8e8db0cb72e422a29b100809ab8163d67c64036579a8004ec6bb5199ea7ea57289bdcef38f18390d78592073d745ba438439a696d8ae070d9a9952006b5733a560ecc8b1dfe903c5	\\x0000000100010000
5	1	4	\\x02e075364e3b75b0f67be40d1c59a6c4e818a3ffe35ef8377f273c1046ec7d1b3f13de76b4f6c7266e1dc9b98fc217520b2b7205082993342ffe86949c383c01	289	\\x0000000100000100663eae7179389c41c3dba0d484b121f75d968fd2bd4505d662a4b41dff00865767fa43e2f8ef9d0a0757feb82b0b3d6d876c0366cdd527f381ecc32ee657a95dbae5d6e93e12d8d28a51d4c6e38d0fef26557a18fedef3fe7011732d0c3ac19f129c087a24781b59433bfe9ecb0ef564bbd239988a4bab6e0641b318143ce6fa	\\x2f8f6978d80823bbcb8f4583db2f0126b7d91e7d25bfd3680ac08107c802ad0dc3b17c4e2807d81b14ace29ae853eaa41081a2df97dbf33552e66d12f0cbe5d2	\\x0000000100000001205b8362d979c68c9facc3e7cc4100e92eefbd65d03788da39809ec5848376385f47e87050b40e6d7f8e387ec3a469a1a29140ce9a9875f5198496939e6123c6937f7c4197f121f0d860d624014bb63acb4b14d87d6ab269fc5bc6ec553b5161ec918fdba297fb884f76cb2101fa85d9125db1792343e67a8d894089a00da373	\\x0000000100010000
6	1	5	\\x389e9c35fb9e027bc11df10a7f2ca06ea6f428d600a2cb5ce9006d22c88c662a09b38930841c3aa783cb1978f732031791256ee58605d2e826cd47eff0dfc807	289	\\x000000010000010055aa59df17437afd5effcbfa0f74aa43d3154bf4e2bcab6c01e64100c3e77e4723da9360a6acd2ee5e86833533fbbefae131a359367f9f1b2d04532b8c945a11c7efe46fa7af4075fe10e3cf8d35189efecaf5ec6880ecbae6cff15e8b23de80f012ee3895fb75d05d41f229f2462327f775aa4f5c3d7e60076042aef9ca662f	\\xd0a72521838f45f08e31316f96c22f1287f835d3ab600feefe0559043c7cd86d52005e7b90c1cdb3cf7259411a86f724660b000b431995c0fc762c0c97e0a0fa	\\x000000010000000149fab310ca2cefd259995eab7b187a5b6450713780a9cd298220d2eec2ee8f629cb49a8de67c870fac1cfa77369d2296cc5463cca237d6365c98e84dabdbdd777ac715995f46981c1d001bbe6426cfb80989134d386a31d706bb4e65a51289739c4ce924f8d45ece0e3f4273950de4a2d8b3b2b1d34569d2d963c4c27b29adca	\\x0000000100010000
7	1	6	\\xc8a3e6dc402932ca5ea2b55b45608b16bcad9f5e77fc988eb057ba155dc6a63a3016e73fd74b1d53419b927f62a15ea9b490c0e5c5b02ab15fea189693ce2909	289	\\x00000001000001000ac3101f10395c590e6d7cffc90cad1a3bcc11a8086179983e3945629f4957e5f8d3e1321cd11de96330c799b3fb6cc3cb81b7ca3b4a2d1407c6fe708150415f5bbb9902cfe69583490e35382ddb4e4c9a3b41c3ac60f468664919349ee7a127f31d1d3f71309605cb49cf6f533112ca96ee81ea72fc6706f3308ef6f40992a5	\\xcdcf859e88d730450c3ae102215404487018ecef15b7cf2ab25cd7fcae3738c5a18b075d72f342f7d8f23a9fe22c47bb9dbc8e9c795d18323d0ac5157549c610	\\x00000001000000017200f177e8fd842099e88adf33317235247f710c294dc844e72a19f36dd45ad7af2449eae036db65b647fb2d812176223ae54fae41e937f7e9db44d151551507c8141f60df65eb1d922aaa84f1c964830a1b4a7af0970ea12fa11c0b622787ca37d75b883633b431b5bff24e498dbf4898d1634d1503ac429cabd9e824735468	\\x0000000100010000
8	1	7	\\xf86824aa3308e30fe1a629b8196780cd6f5d36f8c2a18f57705c817015783c3f7943c22c37bcf33ce149996cde54b151dc4f1f746e99be220f2fe7ef5a13370f	289	\\x00000001000001004fd2fc8adcb65d1c9bd4055084e3a0ca87f5427e2bce2d9b9e9430ea98b4ef37450ff74781c655d5e94d49bfb058fb50bb11ecb7d54b54fe49bcca9c1a5eb3f03217f8f65beb45610e333baa293e68a04d935b9e7c56279b592b12ed06d8b5a79b056af9b39efc7588620316f47d40cba688518609903e33a389057a7ad5506a	\\xa46039d0062682f361d7a58b8c5dc15ea7f225b1e7f62772ac2815f6b84ab3d5753c84f86631e4a798ff5ebe9dc5664bd40a5113ba07818276a6c290d669ecbe	\\x00000001000000014a81a62f333a9741cbb60d8f8d327f0a2a66c5b7df2b71c28d8fcdfd86cc4e0dc015f695df08634b51b1b5dc32b0a8280c02df665f78944f1e5cb75ea9d8eed750ff13e452c05013415b27c117dced2768e02d9a0d43347ca299e58376f490297d910688fe2274273d76ad9146b7dd51ab70bf28bfef462ed1fbf44f2bb48929	\\x0000000100010000
9	1	8	\\xd35199358ad28098780aae7991c45c2c820c81f36b18fc12322b87bad33c7820297dbb4011042eea2320fb9b9bd120be2a9a0c9b2f1555474fed43f8b4705c0f	289	\\x00000001000001000676dca68787b71e36c0e06305804f82f6e93ecd981d70a6ed6dadd46acda6c9a44a87b3ad7706f750ffbb6063d5ea9335d173f56a4a2a9b2c44a251484ee5abf276e4ff3598936f7684bb2bc3d5a40388751067877bb99b00dbe3ed4d9153b763d61256c1d9459228539f4acdb0be06598f33d8754335ab22773292f535ac2e	\\x7f829d481ba272a3fdbb418ccbbf83b443449198bd2322ce17b1d41b5823a6a1b288186af39e4d1d464840080d3657d0c93ef5538c1030c54db3559679eb59f5	\\x000000010000000111a6ae3414d010ba3febe873d4d5cf5ffad0ba239607488798aee5b26fe573e309a1cc930c8dcc55fa4b9684f3f47266525e32314c2dc519cc4099d5c5724b9ebfe5fd6dc9ff02eddc7301ae62f6a6d256e78d345e4a646059398c1a364df55e3f8a2d97931b19ce6d04a5e56f3e33599e99de013552cbd35fe312778aa2d082	\\x0000000100010000
10	1	9	\\xd3d1a080e835133eb97a06f603c6b616b49156f02a186323e677513736f9d206cd8235af785f82370ba10cea1b2c926b171297ea41f51dabb4a719b1a5410a08	289	\\x0000000100000100891c753f520dbf8a4feed44a30649d1bb2a5c7ebb851f66e0a29c277ef628f9e67e834ac2244322b7d028e58e6c8a63604340e31074c54ac58e747049ebca023bbe4637a2df14a385bec0cf9d7f036bdefdd4c33c1d94fdbf7c569aeb76b46a452282ebd415caec5289531914b07cdc68ed614be122521c3d2173361b18fe3de	\\x23c3a37aed8bfb082c6aa2dce7ce204bfaf08e8b8bd321faf32b77800e90450b03669bec07bb57798e71f2c22cdbdf3e816da9f7a9d514978b43af1dac11c4ed	\\x000000010000000133c7af25491031f8479fa83957d97c3e9ec5299b20be9bf594bafdced5ab6f5d8d911f33537e78578837b26729677484057c20cc515ad01354b6d2eaefa6f3463026a00fd1e3e9c3185f68a8718a0a8c0842301f2c738250a443fb745700340ad7243e775066b060ca3daac1d39c6d281acbed0446ef98e6e87c0e76fcce7f4e	\\x0000000100010000
11	1	10	\\x9f7129cd32a305a0fdeb36b1ffe235f1ab7e7090de9e3f2b77609b682a9a1e5030c6a421b7cc9277101921818ab86e1f2eeb29237098b916b314691985c45007	224	\\x00000001000001006b5db0f8fefe71bfb06d95406955c253ae0b3af81689c71e13724be35a7fdaae52b47f410a35cdbe9dbe177fb08cfcc6abc5f99757e5152c99558291f17b18b6e9a1e7ae28deca1b8d3082b575255bfbefc0f5860f6d34fe8a863622c84ebf728de27001a4e1e5d6ca5cd56be72cbf4d40ec86e504e9df96bc24baf9b28defed	\\xaca10d32efce2f4ddcba1487a436acf97c6b7122808111cec6783b9c3bca6bff30b4fa79e37bae7405b882592736c6706da76be8d9d03f5ba2b49932b46ea733	\\x00000001000000016578755056c2dc465c217c0f556aacb04a3ca7b1ee782de99737ef7bed0f72645a6ee114b3c187e751eb2c4e87214f51b9a9755dc75be036e835c16fdaa64fded88875f545b7cb6b6971d22d3ddc2f4991443c0b3a9ac58decb7688afec44535ab0a37b1267a939dd800ddf4a7c6ac5c9e06db7e469e254b1437599400d15484	\\x0000000100010000
12	1	11	\\xe253c4a3cb1482b150f0a080ad303df5079c6973a16ed4bfb0940390979f1fb9c4290b3d9cc4050623542353c083521ca9f47bfdc1e7043ef6d6cee7c58a2d0f	224	\\x00000001000001006b36278cdc4779560ef439c14f32ce5aa78c9bf277c28e69a756c8f5f05ef5ee9444170603dbff2bbddf36335796b11aeca1c52ac28fdb7c3fe7ca535a1c3ebe45ea004d93c653dcc4f4b7a7ca4be42eabb6162c0ca85673119caa6b210f2e35484f74c3feb044ea51355a1b40cc071ea82e9fc0145fd4e4f2377f53cb7e8894	\\xffc99e802b713b5c86e97dc96118e9b74ba5ec42dcd0b1d55b2e51dfe684952bfa1fa284646fb525a3b0c0ad6f07b93dd76fe724a90a9a494106fe12281cf378	\\x00000001000000019c8bbb66fef5bc9298aaf153204b0f440a4ad8250a07b465b2230dfe051c33624807ed1f2e55bb6110e6749ddeb1fab7d517b5485ee932170fcebfc4e5b02c044284191fc2f05bf1563d197c23301a634d0ace1019a962bdc8822d669881a560dd9ba34393d33684b061ce259c7f3fa73b995d6e91360382bc84682801b4ba4d	\\x0000000100010000
13	2	0	\\x3bd535d5ad0205c87a1c5290f0976513ffadb41c73501e52648d1c02e891add2a321f29c01e4f96c8b20c1029d2c82fdc7b587b78e53c983108fd40924f60b04	243	\\x00000001000001007ed4e86b0e132eb05c309c7c4b68e03ec777764302a965dae9f0162f11ffac4592e8948fccf419c29a7b6a9a2fcd7b6683afedb8f6428a1f16c8d8455cead50afcdf0fe6599bc94a204e96450971cd5c97b62285963ecf3f50d9b59f05977664691a1987604fb997a9a0fdca6448402ebfec3b9ff255425b1f4d78c487c2d485	\\x7e06e292f7304c0c77482237419ccaffa7602e90fb6f215aca9b7a9efeb8c56138d57981af800a7b8fab100c18c91256470de610088ea687e4d22a856346316e	\\x00000001000000019e8a5a7310afd232983f7f5c68c4e465d86a10ea102892d2726c43a28aacfa99a85e3f143e3a619728482ca01e9bb9e7e479e77d66031aeb1bef29ebe2c370b827925b8f89528680b7443973d3f8435554371b28994470c790d5b188d7c977a12b08040f41f0ba260b3025dc194cdad551830e4031f2cd0e201c87f195a6c2af	\\x0000000100010000
14	2	1	\\x12369cef28ccb5fa874a1d84436f6fd09e964c273a6f591d2dfc9c7e5a9b7aa6f61f7fc241435f2adee1efe495aa8075b1e6459e1735024eedbfc728ede11201	289	\\x00000001000001006e50fac21bef40091e73bbde501f97a6d2c4352f0a27b329abea1ff10b6bf9811c6671a2188cd8787464262d29f15fb10444eebccc5a6859319991b5d4c2e9e80f486391d0c19195f1cc5da7c80ce1c4dbcbb0c2209096c50182d9cac15336107a92e9a874be4417df6705c7c5df7f439b8511aaafc2acd1d714bbe9639dac06	\\x51551753de254e9e818c83ca6578ad2671f535bc8133623009175a24a141dfd4b53608c42ab411ec13fc4a2b1eba47fc61d41247fd8b12e65efa25417f14166b	\\x0000000100000001a6ec58a3636f8b7564a13f66c2b6f64271454283fa28a314d427b4cce3fb6da68c330c9ecfed063addb13ab431668eb1ca4838e7150b9fd0b774c7d8a45c60e06e3fb3969b1c5187a7a350bc629131b9b612b46fbd5cdeafcfb79ad07661bd13fa923548f0b43799b41bb8db4928c098ae79a91e093d975aa607fa84815d4250	\\x0000000100010000
15	2	2	\\xdb360d17cce25aab2253a3286e13ea26f46e926febc707a1faf222440557481eb6b67ea058301275c52d2a3e388edc2ece97d894d885974ba4685bfc7fa8cb09	289	\\x000000010000010043bb08df30927ed1ed388e94f5a03b6953ec55dc3d1a6b9c49e71bb1fca6e5edc419e51e157ac0d9c5859d4a3e15d5a1bca28a6481f419bb90cb015bd06ccb535449a68106cb3e2e40dc8abd6115c87a908e4cf74fa36807957543c7202f3a667aab1274270fbd8cb06be63c1bf6259c7e3bdf9b945a217f8c1c9560daead636	\\xd4ea84bb68b4351fe73b43cef754ad3d02a216c3f31ee3cc94930b49c057e2cd68ea042edf8c3f40fe3acc08dfc2cd98ed3355cd724febec11f3370619e6c5be	\\x00000001000000013dd38c9035417100b13c2bf6fcfb892489dafadec4ea72c0d0a340a2541244f3c1959d4cb3a8ef5f2226dd7dee1f783ac4ba84875dc47408a496febbe732297ef157498b14c9c721d5ddb65e60d9d4bd82137bde83b489b4220350b767050b5f76a25294b2d03142e9cd2fe8448037571d3483a9efcbb093842e974e5af277e7	\\x0000000100010000
16	2	3	\\x27d278b5e441eee7dd4d75411f4b9366be9c44cc9c50f929eb693359fe0dcc176e0b3fd66a6954510915b1ccce04e3fc9c827127f9196706a661af10bc38400b	289	\\x000000010000010012e421eef48b69cb90d6a3a76d5edeb4ce9ce2b8fe3ed0b054236eb86cefe2b9d9c1ad25adb68e80963d19e461851dfc59db986b38ecc9f50bdc55f85fd747c8bc9ee35c32a77b4339909ce09ed384cc728514ec0fb6a8d8967888aa2ed2bae8023d212a9b7b4a3b79acb282afd219162fff3cc9ff0d27e01c740a349627b917	\\xb88cb3fce9ee945ba29fae50f7e6877046116b5201f486fa6732980fb1b283f489bfe40e8c012be2898c7c2bb454923cd6412c044e0a577438b482f29633540d	\\x00000001000000010914553b1a81cdeaeb341567b0d3a0ec109de191ce5f6ea46d60926a488c5836270e07d5cd72213e9a1ecabc57164666c70ac23a74b1f3bb0bb92c9b94a39a6e9659720142cccf85795545814546574c30a7a804db5a1bfbafa7210f3aa2c7c420d4cc8620a449818ba8fb93577c9715d55cab4cdc2c24309173c62cb4868cee	\\x0000000100010000
17	2	4	\\xda5b703e9b8c016d5adae46d78c7d3b47b7c45cf4940261e1fc698b1ebca01aca61be37df354c885989d11f8890935b7835ff04ecaa7281e7ffd8e12cabd3a0b	289	\\x00000001000001006499e442fbfd8d08390983450c82785314f41c55f8962b648c86f299d44224049cfd7cebb8df40f51bba11fa9c00764cae981fc00b903b349333279c0d13fad21137dee1445e4cca0ee7c8d57060a7a89715fe75b3cbb49e6e6facd99b23080144c3b539ee54bbcaaa005b274712885714aaddc4b5123bf7dd606038e119e189	\\x3dda94bd759264ecfeb082d1e7e135b0fda1adbe7e4e574f7b6c5edff12414fdc9cae4c8c40bfbb36f6729abd239026a0987c43dfb0cc732298cfa6a05c7a1a4	\\x000000010000000139cd2326609c8b63f0f6750de5a4c1447b0aa4379809d9b229e5a444865f925fc77300065e5d80dbd1c014f4dd25c7c4a8a02ce70376de038762b249fe4848d17afbef2506182e88547fc82c38c133f8461ed4ebc55061c7f4e27a12b17269df20fa4b1396903ae358bb62929c180f8dfa04387d89747262b9d05fb514fc2f8b	\\x0000000100010000
18	2	5	\\x0e449a49d672beb7575fa577bdfe133f0bf7668a282d173d25299d128735fc24628f9815a5943aebc24fb1457698526d0e481035a433ff5ff3b6a06dbb3bd10b	289	\\x000000010000010084c196d9605d4c13a68a3dbff02abec75c03aad8a43a14c1d1936f4d48cc3f4753cace10aa786558d63362c2e400833189ce695314dbee059d43ceef751e441e61fc1c5cf791ae99139a7bb2c2909020812f4809967f841922dd2bc7f1fade872c8edbdd7d0e89694361eeffa479267ff6c8ee0dde1c7487f6ca7baac9aa92f7	\\x01de70a50d1751f2d5453dd109071af7cf4089d3a255578b64c2b90d0eb8dbbde77343203ade1a1e7c463b8d45695b8cf858a2b460c5b8e7c7a3efbcd10d35b0	\\x00000001000000014e5ed2ba0bc941c098e63de4977b987e26355f39b760ee76ae95f5f88686fd7385f77c2731d560da7c5e5866b2ca9bfd15fa00e06efa0d040ea209e7e07dc841f2266ab6cdc251dfc696a8ff6119b40fe46a509b343568a575b30d7056d304f722cef350f9d527ca2b092b2532c219a0f29e189cca3a85d6443ec3879b441329	\\x0000000100010000
19	2	6	\\xce20733a5ea495d05489650b1f97b375065d4561a0dac57849ffeb276cb7843aff72e6719f2aed6e4ecad614524d0c7a8bb3b86fd92f08d5d5bdac35b72f0c06	289	\\x0000000100000100865b5c76feb48a3f510e316e74ebaa83da5cc6d12c87b7ef99db0c550affffea8db74cd974017c3f76833c72e731ecaa399af500536a29103b5b977725d71676de5d2eccb13b2223cc16b4374f7253723f9b886feb6d487546346c001ac59253f504190332cbdd5134ab191e442a181ab9ddd4498d9d2f35e7d29a4c961b9698	\\x873e0c73beea89f898185eedf132cc5daae23fb3beff2350492f615693403287d7269bff32b2451c15e166432912c488ae2f2602fa74a42748b8080043db9d8f	\\x00000001000000013ab0b9bcb481089d47c1714cdbea691743e5cc884d01aefe03ac837383d7dcaa37389e0bc262fa9a2a346d53bc95bc12402e62b1ce79e878cae340793a86cbb7a89387d0999d79bf48bd44583ff9b63604e6b8d79e3ecc02291d10a74270565ea646b5cc54ea993496779334ffbfbb2efd0393286251f9c99a28bed6477f5413	\\x0000000100010000
20	2	7	\\xe09232b1d9b837bc75a456ba1e6d5888676a81e668080c75f6a341c7064feda9d802deb350a07f55162b46f8b97f3db03147084cb68ac9a3db2026bbc2a9590b	289	\\x00000001000001007ee9b7d8ca8ac22a719d7d7cdbe6b7eddc82925e44de86ee3a9d01fe68aa4644d2e91ee869deada22d35c2773528e18e478762e7e2d2d635722b45732446033f242f2427650ab76939c577629ee446d916e8784ad809994657501a4772c1af4aaf0d4363e34197a270fd16e3dc3f4a870610b2840fe175ce15bd9f78da05065e	\\x5f29df98ba0de870800c1ab86bba790f847430441740bcf251704bc20741c233f5878a06f2db8f93301d3ef73171e790920c50484b9f06f8754f819cb5a4b5aa	\\x00000001000000019d08cd46910bbb6db8b1ea063d368715fdd3d94eb00c595eed128e766046d40d3f019ddfb2fc553aea44c3d7348e60e53c890cdb2342e94103c89d9cc3b330660dcbf3552ceff1582d7dcf4ffaeb1e3ecb33d7a186acd9fa5e0848b3fcd7b0c455f461b5a30fcf57021dac6794386da16368f068d0ea8d425f3da1b5e8758bbd	\\x0000000100010000
21	2	8	\\xaec58a4d2d124f88073f4e649db83423620ef3877ef45b5f66eb2109382a5bf68387f457202a77143110088405d129ae054a5992eaa816801cb112229f893803	289	\\x00000001000001004054c7643096ff84f56a52cabf6409e4c8d484d245fbfd9d8124009524b55099593be35b59d0811239b482150c7f2c5939d7e9fed36b6c022701b2bb4d6b6330eb599bf638c873b94a790ca9b196962815a7054997c22c8ff8f723f28c36d568471d6f7e239e3b54f7e6819e5ae4808c76949957ea8fffc331b002c1119ee90b	\\x2ee06141faf45ff7f90ca33dab3d09345213c0fc602f12a374ee581ddc9f9009faffd2d348970ad743f44e44f16fe63f2cdfa224f983c6744c95d130c9dd164d	\\x0000000100000001862a89508e20d25625f5643db59c591ef5ed1febccf44d17304b5fadaf10dca09a29408ecaaa4f19b22d5642ca8b8162dfeb0c01a48a5337e868ef3cb636050ca60a7b09d8d21e8be714c3f9f601c6582f907dfdead8951ce7d4054645b4e0ba0dbe6585733d5ad8a517b0ab21892fea7bb4755da67256462726c16716c83c5e	\\x0000000100010000
22	2	9	\\x479805abd79c929400a0891287ca70df19a246dbe61399734aba0e4afa90901f553ea756f56df6130e435a9dfb2eb8a8d672c10c81cb024b7a913a75f80e6703	224	\\x000000010000010067db9d291191a4b60d6c63ca3b5bdc3d8ef9aca7f174a2847aeaab64e7fd55d7803d8cfa39c696a8072bdc5769e797a7fd70396a90dff872192b0b4df9020dee79e44017319a31b0b1bc6ae21cf3ce0184d9e86b319b744a2c206ee65a10b961f0ec06229bc4a6a382738720f6b84436bab717ced32b538259930e9ba11b254e	\\x7306368fe8ac77358d496c74bf28d70a9b4fc1c966d937918df0726bc60a2bbeec8d647283b316902cc1d4b3065b4aa12b26a90d90710ea098f2a725327a375d	\\x000000010000000128663eba494190434641472092d3abd5a2d43325d8044367e95733a9d6d5372657af423c34a8ed8865a0351a0796da245a2e908dab503e31bdf1a20a82004f1d2637a0691508a4dd2d4b0c176008a0b26ea5c7279ec70349731e34742c3927a9a7f1e1fe7b958314a4a8e06a24a8b82007fdfd33b6b8ca136d7d0e31252deaab	\\x0000000100010000
23	2	10	\\x8f1d752a5a453b4c6dc7de6d7cf1b4d4243b57b7d61347df2d6f0b33dcaed7beff5a81f824a3b5c25749b3e84a87ba20acfc595a663f00c1777f615ede09a205	224	\\x0000000100000100a9588c2aea5d660e1807b1c5b65d797758810920d72b0cc08c62cb49c9b9d4b4023a38df0b263baa4c37b2eaa429ece41081c5033fba320cb2c59ec3ec1db2d9a0be97d06c0c2156d56c1835c60290c7c9f44514170290886dda66ce335884bcea871be1f8bc717e9f0e4a7eb440d7754e2741a9bdcdf4b20dbeb9959b3cea98	\\x3a9e65861429f2c38f50813050fea4c0cc3968092ac29ca40ff86b5242f7a56c5141d1995ecfdc045c3b62ad0b5dde9de11868aec182b561d76a7e3c6272d7a8	\\x00000001000000013ede91b06049aab04d6057b06e0de14cfd3e3a386ec81f233daa89a411f887e786694471bbcef821efa8e711a7d728e91e73c4947cd8819f21e144131f8a8314fda4442dd6cbde7d545277ce42a152aff4686aebbb9249ef2397ef700c6a6be211fccf38baaeec896eebf3c46fc544988917870ae47033656576be0e0a9a36c2	\\x0000000100010000
24	2	11	\\x7e28b193689fb722ac9f76363d584607f15a7161ec0a6ef0dca37220f87970388c54da5c0f3a46900aeffc4a3d52b32d19d5fcd105b20dad7586579b31a09e01	224	\\x0000000100000100086d2520f3c9ed53559cc9fb39645ff8a33f7dc803626e2094ad48c33919ff646f086480907406c72b87fb576d0a5881085124b3527b15e3e589d67e9dc1e45692f22f5baa63234914456b6c0f916c9f09f1494924ccfca364e3502e6a490df02e7694ad5ab987aac807c153dce041117617a18b6c55ff2fa5aad1cb1c9f738b	\\x161cf96019f3d791f88107ab456829943c9936c459116f410f499401c392ab3460ff7dc5e91a028a486cac775ecf82807ce50f6309962ce73d4ed315635d6411	\\x00000001000000011677d36e3d08973d4cc935a2cd412aa9f9df53a0748666500facbf863ab79b43f20a2cf25e467dd78939610f9edd3dac1c4dc1a657c34fea424cca11ded4996815a8f0c9ec0a97a466b3aea4442bf508477c0cdbbe7719585daaf985806d3165a63cc3e896325f2eb8dfe13852c6e448af214aff5d4d7a54c56520d10a008b38	\\x0000000100010000
25	3	0	\\xdd92c4224b670f3368a0d695a0365399f924de72c282552df885f54c140118d312b83ce945261b2727eeefc276d8aebd32aa88b9518e003b2d72a642ce233304	86	\\x0000000100000100abf8150578c03b53aee4c87863eebdfbd98ae276456a152f07ecc57b20c308da6a3d02f01435165881e9af5991ea16dbc595273ffd40ea1414a53fc7a508451e5ce09c47c8c0977ddee5c926ebf4878c971ce265f874d6c72f6d36a301837a293d409644a834d62b050debe1c49c1579770d1107f2bac90ad1cb9c0b9def605a	\\x9e533328437de71b71103a8b1b5d5d727400006dd24bd9fa6ac50dbf545eafc76d6907b56dc469b5510888f7a3358ef46d1165dcc9613a51478450b659748ac1	\\x00000001000000019ef24a0598828922da8c374cbedaf7e203975e1fd660ba4960a06eda770708d06d772eedc23c826c0a7c2e5a2003298ee78aa136e296caaf15433da9bb020d64815c714d2123c0992d2416466266839b251f88f68b515f19093b42f75d865c368816e14df15fd7e49096d0e5ba695d352a277d59305623df9160aff65e5c7795	\\x0000000100010000
26	3	1	\\x1c2c0b20274fba73abf28a140401bf9cd1ee7ec1a6c0aa17a16aaabe0ac2202548b772b5d957bc1f3ea16faaa86abd425eab097a0f5622947ad1e3fb2ed20f0c	289	\\x0000000100000100233d4d6819c1a5d2682e489bebf96869271eb8adec95d950eb5d09ff35cfd9f0203283e7a909017615057c931aff245cc39ef6a97b8b73ec4b5526f7762ba11cb44c8cf49b55c3f661dc18318ca5e8b6b490bd34807b95e4dd7fc27cc1af42cba16b31229c40c9d6d507752a1cc9e6983cb081a0543e2d78714e4375f999dd53	\\xbc2f69d783bba315601c91861bd3184f46876d066e451dccf98ea67d572d6b0cad605fbcca0558e5b1b54c6fbf9b7dd75d0b7c60563a2d9ffca3694abac4d7c4	\\x00000001000000012a24b0ccd1f0f7752018435fab8eea64fac0b316198cc9218c23ede66fb6b54d0d2eba776ca8db7a53b2f174f91f3ba7a54ad6342df5fdc32638d853af24beb3df36bf5ee8d1e2b837c2dda5d76efee963ce037280f1ec6d442c52d714ba59f957922fc0333ab4948201407e00d40aa1ecc5f6374bc21c5df1bce84b5959d83d	\\x0000000100010000
27	3	2	\\x073653323b8c8f6c68082a2a80f49b190580c1779ea37634bbd9617b0ac1feed6bfc1f9e4ff2512b3812c56efb1927540856202301d26c7056b987ab165a3208	289	\\x00000001000001005f7a4037e570220394f550974d61eb9f4ea3da8a541a7a4332942fd0b58c4e39567364ab647284a313812d029001c3b31512feff7b017662ec8a84731436a5a42ed20bb9705f9320334ab62f0499846eec5a43a08e6d92fe23b905e9f8062653a2c96337ad2dac98eafc91e7faafef15155401fcdbdbba41e18d46fb3c522958	\\x8a7abc0304915527744d0f3d7cc48f0d598a32c781ea659a2488452fac150b055e7480a9daddeec80f7506276fcd68a18a009ba55d5a55fda039380e606de043	\\x00000001000000014f22d10e18944146693f827fde2a4aca89d8a750df17bedd79baecc07e5414e91acfd28d03e3b39feabbc6c0fb8fb16c1a0f8729c7168dd1be653accd5a850372a51ad734d98f0739cc06e851d78aead4895ad3317cc6db4cb65c318a1aef891b6db3a59118bfc94165bd040f84cb57f8695ca0487084bb3609b93107f1ea646	\\x0000000100010000
28	3	3	\\x2c262dcfbfc53280aab2482a7a6f293518d68311746a02215abb975f9e6abd180b0bd7d266ae3e243cc92e0427a0d4d5d6cf77ce1c763cb6b68200bb082ffe05	289	\\x00000001000001007218d9c56df19efce2559f76aba00347055d74b66ea0c9542e5e933bb6ffdd88b6bdbd78de139935fe3cd8fba68e3811ed4effbc215617bd14804982d9de1764381df6fd40fb5f1cb9acde215b7a6b7af5b94e74e917e99aac4298371627e20321bed3a01795aa82d5510c138b6c06f52632d3c6af04a21ee2af6141c907419c	\\x60dc5c5c3fe2b8afc7fd2630867948b7272b68c0f52200deadb5bdf4a7ff2ef8c8b9cb4ae7f5cb45e5a159721408b5f2826b54f2abd7dfeb4a114c1acf10b0c6	\\x000000010000000127669ebb2be4bc5c90fd5185e35107b2a16a8019ed1f88af5e03d258ca7b16e4b23a41563b46f7fd94c46970edef650bd7b313caa9ba2f51ccc93355093902307f76471310f34143069de7ba1f18933c5ee591103f25cd37bc6d89cd65c4fede148fbca74b9e06701d845cdfc61813185a9252a25603d38e7903510ddbb96bbe	\\x0000000100010000
29	3	4	\\xbed6ae3f790544f13f85e3de4a4498afc2872de7596c95e8b5f7a21051c477fd83cbb564e79c9f737cd441f534e4f08ee0ae7997e51111e38b061d6efe433105	289	\\x00000001000001009298e2f6c1b606574bbfff3bd8fe2fad08d4c3a4d4505ca66270bf2e0968febc57ae42e89b826366e5d7b254d6b92bc498217854601a867051002ae0645ba7b440439b94c79ae78de74dd450fa13843914127fd862ecfd1dafe9c0393eeeb73d97ce1ffe4a2a1fb2222a8cd68ebaa7d1ed1ae27b02d8b6a988875b89b8f92b10	\\x5227bbbc5feb656549e3b9429e184f97d3c57aa66c47bf04d0b27aa2c095c6b4188069a965cc87f68ebaf7cfc7196112aac89333756f359547f7c1e98bcdac34	\\x00000001000000012b9033a9d9c2528b8c460f2109f3901beb00153b8665f06f89166c3a679964c6c9d4fb1f39c971e00c8e22bd0cecfe79e34d03e48ea65b7c84b5b787389c5273bd1b165ac762349d72d06ba648fe38acff676d6848c8c7d66adc52fa87baac5bb354c5b6e56b13b68d93140b74bd91b184d5f3753b18de0637c4cbe03b2212c6	\\x0000000100010000
30	3	5	\\x20de8a87b2b2d9695b107ef45897de2211c56c8fea7c1ca2470dde97f0460fcc26c41f2b3f41cc0e3bf2165c468bcc27c6df44e7854995394169e254c8eb7504	289	\\x00000001000001008af4b7f9c8320aad3f137b17f4cd9998d76e926ccab2a9c5fad72427468033f947abaa06882dd980ca57980bf85475493ae3601a3aff70f75359b6da0f1253dc7e583c3a7a615bbad00e28fb355d04695b34095303f2eb2bae1b6ec07b12fafed6a290684d38bbaec6a8c728a7a564d9bd29518184ee9251e55a83fbebb55d27	\\x0c5313070dd52699a2e6094aab3132e5ee326120e29f82e381c6f6a8b0a342899015647fc159026d1ffc089cfdc63413c64bde22f697fe37b33eb3c1ff688318	\\x0000000100000001339d04b977588ee8086bdb37ca8106ab34a42cb13b879c0e9cc6b5dabff795474c4db7eff6566aa178e5f72e29cecf67dcf5ca34be5492803d3310212b107c96b38d9c773b950c9d753f66f17a7a2b08135e430f5067730119fb6b9dd941672334239030b2774c603236fec5ff186c6b19e773561f63a37cfe9aa93cdd447984	\\x0000000100010000
31	3	6	\\x2f8f5987f29216b4ef2cfbd2a4ccb6d3095364293f597f1a4e41681f8358b0e5c3b77c780ba8dcf595b214d84f15e8f3350e32f1b7633f42b717f33c79405707	289	\\x00000001000001002b524e804bc43a081dec26dd863d25f1fbae30b2d6e7c1befc0acb575725cfecd78b22fe0a202f7c6bed36a1bc5d63673a96e66943c96fcba6344bb96ad9ac96a213ea559593a52c153f88eb5d61931b41e14940a7cf9c724cd1c1e21e50d21df57424d972e12f7bd9a006a24887d0f90985b0604024c7f3c8a86efe7fab84c7	\\x031d101e1d2c7774f206bdab38c880464bbb06877e95053e87e07e56a7baaa0a824b3b8af92e36a99b19d4778e1f8190851e449f8ea208a438e150481b787e98	\\x00000001000000012be05a3c30fadc673e2dce23d44c6822b4533de72c39f285aaee0136b2f34835a0e2ce5d756f31e85720de9e14772842769de97a73abe7fa2f726ba10cebf05efbb18ce899215ab044e003227648fb1eb5ad2ab4b77693b89e2fcef295aaa2ed1f8224e08eff2e0aaf2d410eb8fb918419e48019c49474becca607bbdf83e3dc	\\x0000000100010000
32	3	7	\\x54125c02bbb7dd1dd5c220374a04902363b382a78d40f4076809e8f53b412652a2d695c20ceec0f2dd18b4b715847f527fac655aa0d11d052a448f470de1cd09	289	\\x00000001000001002e40a955519393f16b20b9262dd7ca9d2b49721e3bc79be4ba7005c951c5dabd6791b49b6e34b67907f32db331e9f07c7719819ea799e38391914a9ca879982d2d3a172227cf17b291c0c3eb9deb3d14b0749f3edd9a3bf846d1c2bf470bded95dabadcd1184587258a33cf03def2ab8d634104337d8aaab1806213494759f9e	\\x25b8cc20fa6c4203374ed08bb480a9cfb59dc9cd369c44305744c6a63b1aaf6014d5f8e2460cc3473b5e435ba80497beea9ccd1bc166d570162e6a6b7b15a48b	\\x0000000100000001518efced8dcac20ab8c155a6c506dceb8c572ad76ddb235a5b40a0a3077d6c9597d68c76b8868540c09e7d1945cf8c9df660b3e41a16556eb38593b7ace498a530c52b6d9b858fe42d834b27c766dcd5576cacb96df343d9ad1ce68a92ff53fa5779d540a10f66b881918b2b4323898509c70ee5fab7e0dd542641795c80b2e0	\\x0000000100010000
33	3	8	\\xba86f94ac2ed1b645daa9f487b5df8e4220291e85008dc9e07fd63f818747f02907b9cd42ae869a2907207e17288c5f09f6440e00923c8b3c3e7f24fef195607	289	\\x0000000100000100a470b6d573fa7ed3c29e2c9c6311cd6006fa84bf607191983fe60d7c4b7878bccff64045b9abd86c269a3e41ad33c87c379a03da31465260d24d7cb48637e86bee62df9f91146c30b7a3d6a322caf8ba2f0f2efde9750da30c019cd15f777d0d0bf049dff0f8231af473850bc3c85002ecee1087de67db2de001f74146c7a9f2	\\x2e7daaf5ab74889bcd84544765383ea0aec87207e0cc1d4a80445fe58e1b7610319b7f4c040a5e02145ed99fa2002f748eeac23c31099a779d4bc0fbcd9f9a40	\\x0000000100000001251e2a31b886667a66800b632cd7fa48cb32e36b3b3dee5ec8e446764dcb34ce0a6015febeb82f27b4f893fde5a20bf4e58244787a050c3634584fcaeb66adeea69299fb81396ebc78e2390c7fd2929e9ce8d81ab587e16614ec4925582614a55db341dc635d703b8614c087392989bcb195ab0cf68127c4fcb11353023347c4	\\x0000000100010000
34	3	9	\\xc359dc84783a802229182e0d0bf270751c437ace6eace8630fd950733a38ba296ea180ebaa547c633068fabebe9eff7fda6a09cb857c877ff462acccc1e7d107	224	\\x00000001000001008ff297d6bd0806b105795b28ec383694c3e8d2e389fa1312167164f1007648fe7dab64ac126df362bb013f1a9b1147fa82da86a62d08ac5bacf6f1a233d08af5841bcd4acba251a4981e9076831e96f1d9958291444e7db2ac791923e5d0907303a0330e2c2917d8cacbf4427bbdc0830c52b62706592a2217271719ebfbe7b6	\\x2e87d547b8e362ed2091f26a1a7c4a244e750fc12d3fc97e986259ec491f691b4647cf3754a9357f4b97f03d8a9c39cd7f982ef069725d28185f4230d5818684	\\x00000001000000011cafd9f83a8e842535b563e93025c54cf6772d355f6ae208d41588fe3167728f5d6e8c3613b1295fc4ae7f61e941937694b3db160c326286a1e28aa3db121dd0c3d9cd705c9b251b0da4a0cab2b53eb40e5e38d6183a7699d999ec28396e7a5f54271e10421cdf7a0b4142f9e5b067dfbb9dd3c36cb2ae3ab831d16cd8fa6b3b	\\x0000000100010000
35	3	10	\\x50970b22fdd561e71ca0887cc3eec4311f70479dc8fff08c24d59803715b11f7b82a44590b2f98cb00fc938079d8b8d565246ffb4af36ae8628f00330aeb4c0b	224	\\x000000010000010095164b48df5896d93f2b860f4ee215d5b7c4ab72ad60f620d24b4d145fbd3708392cfb77b4c5b4fb2a4132c079095574cb1b7855c13679a0f000bfddfb1fc2f53958eb0f436e89f3f6057005f18d7771928833976e84e7bf57efbd0e92e0ca1de12e22af3363825ed9318c7e26ac34ac9e21cbe8344b5d19f04a33b7a17d414e	\\xc38478fabef032621b7930dda1e4e2e7217dcb432a614c15c09fd2ce9de215910d4db34b1bd318cdbd92459d02fc6f9e328dd78ab03c6b646d74d350f69373ce	\\x00000001000000014e55a3b3ad91b51ee4fc06568ba917812dbbc042d14814f6c5c873e041ef09b4a05b3ab48d69299686ea27c4dda34a271f539806186d0d85f14e7f4f206bcec71a2f4c6e52f2f19404fc08f701621b76992edb61153063da54fee368d2b06fbf45abde7413e0c0fdd80b9f83da835a152fb6a7b53ac29ba270b0084828356b64	\\x0000000100010000
36	3	11	\\x4d73567a3262e752257b490a757e594a42707eb2ee5f2b39bf3e3215b7305bcbe4727be10851ca7687a322eeb08cc02526e0a8aee295240e13b02c40733e5c02	224	\\x000000010000010021be7dbe0608bfe4a554b5c20af31aaa83ff2609fb3ec5aeb1b120625c216a055c77f983d3919a02210b4130a7b1bdb00b63862d3501767ce4b6f5ca878c389640495d0913f7deee9758e41f94fef946221ccbad5168a317f9f3909db5880c5396d9c0ccaaace9bb1237eca87d93c9af5bd4c5a5b42b00d337ac589dc88bd433	\\xa0258583d593a86c660f3f3a03c27333fc39c856098ea4f18ef47f93a6603e933e9dd9b07b982ebf8f5f6a136efe94b9ac9113b7b4acb44a3a4813a81cbb5144	\\x00000001000000014864b77bef29a8e7972206d486c7771bfb1895f60813a75df2bf64a882fa594b555d5fe9f4d4d9a92a7f2ad97919e0001fc5b384a4c1250bc2fee7548914d9938387d9a22bcbcaf98e25ba441bbc10013392ca1ab166d9b8a36e3a6617fde876dfa227ad826eb82f62b4847971ff5720543ad763d6e768980673d6de31316dbd	\\x0000000100010000
37	4	0	\\x676599751ca7f76e17bd6a2f35efdd502f7f2a8c15406a8ba0da1b624ae5e47c54996561a1c88803ab8d34923c9e775a72a4d4fa9b069a38819cd4a8e7420607	424	\\x00000001000001004b5deb7f982ef590d6c840f736799b3ba9660a85f53f0df77bc612805a2341a47876319032d1a27ba9582528ba4ae9b64c26244143406898e6788d6e441d5ea7687fd38a57dcf6c1f569d91cc07c92209c6503862cd21ba05c8dc6b7de415da54d3c8d009ac4020e03e22cf18e4ffa3f130fd43d6e128086987accb953b9b9d5	\\x41e7ee2ca3fff9bdb2ea815e3b0f5a34b0970d31d04964c76d8fb701d163f13362bfba4dc0515c40fc09e8fe38f57073b122e863f32fe7c76d25b0510782cb74	\\x000000010000000141326e45ffeef142db07ba014b63f27c93112e795b4cffc4ecabe5219a6807bc2dffbbc63f019ed0ce665bf5404569d16475e7e050f1ffd12346fa34765e278f0b9294af8ec3c31a9221bbb7b40f5540463315e95818fa132e1fe86e6fde222f4aa88628cffa7edbe1c44e603cd45268443a34685be00403df33789d1b29848a	\\x0000000100010000
38	4	1	\\xd9444170827b25da35e29570797986c2272dd11d86019d29756ca05f5b47fe712f5413742be5efe9393cf94ec30b729a2529dba10631ba1a0cd61253f8ba670e	289	\\x00000001000001000ff9d9bc6dc177938f5c207da3d3deaccb4b18044a8ab49ff3da307e31ae30ebe57b458d6026c070922c97e8801955e2e52b68e45c0cf91bb3c6e1611aa940ab553ebbb18da9b85c2258d80bbb5e1c2ee3620ed1310764094115dcb50a5b0a44128fac84486c4b7c5eef8c1ce952821bc8f61a1050e2eb44961e039dd05c42d9	\\x2da20231e5a8a10a065a5d5ca89a939512725cd5ed8e33fda98673190126df9fe285401f3d2225647bf2464688678603654ab919ce12b34b1360f1339e06ae10	\\x000000010000000172fd221364947bdae5bfb16459d1c076979a9e688f951488c9bfc77e0a6b3bdb27e17feb4f35c8bd0f7d561b08c1d0d1d4a6a9cd108d1a70ec62c1a9ae083204a466f1ee23b0a6c18270cecdb0008a79b01ef183d4d24e09196708d45ef096543f75c883ed7813f9e604c8fc2a32f069b5f39091644fcaf23b4f1128a868507d	\\x0000000100010000
39	4	2	\\x282be88ffd6a5904c293b8e620dc441affef77285fc88a0682ba12f9a59e447ecf69f0f3476ca9d61f1f92606ec13414bed7f2274bf0aa0e604de47c53325908	289	\\x00000001000001001fd5de0311e69882024c1cf3ed0d372dcd51794708966b29f8b182af9e444c908d134cb9cdfaecdbaf051e6ae868101994f9f247941efd3e63b4c24326a12bcdd491f7f77c1541c0c67bd1bec5c14b143cef1209d11c3ddc2753f4b8335637c777bcdee8721bd2820883e7f5ca2c296c9e57673c343ff137f89419ac8528beaa	\\x53bbb789dad7580a7be9d01d5069e214bc274aed15aec92cfbaa814d3f14f74386e4c5ddf080e3a65dd5517dc84f3501493dd005d0668a1db2ed581af04521fb	\\x0000000100000001355a8fe1ebea9b8a66f79a6e87c746b65b323a0020499bcbd8d4ca4a01244c508eafbc776362d8aefbaa7d1ada327f9f74404b3cdd6385806c743ce399189581756fc8f18afbeb3db0bcdc21fe925486958a210a7bbac6f737721d725eb25fe04a72616bf210a7fc214c3a2c62598704b2de7cdd1e7073e84a81188e86ae48d0	\\x0000000100010000
40	4	3	\\xf71815cebed2066ee64a94558cf6b3f348e9ac76605069ba15bbead56d888498eddc2ec5ad2a82d1816d13011bd5c1d52aadbd2d97dbde03d841d6c36d39d505	289	\\x00000001000001005c8378c0ae1a84854f5cfe86c57a3b96387952e8a470e1a6d2490b6b4defe2747a4d61f8dd4f417298958a81a6c1167b8829085df12003533f398af2085ab870b76cf4d0dc51d9ec80c9beeb44256e900222332006ddd9e4f204fa350b3e5d70bf3554887c38a63c60437fb1f544fb3da0ed7a6d0637dea16a53a6de133ba219	\\x628b7d9124f558cd974bc80afe3de8754fffa7df23ed69063dc4c18d96654ceadb2836c971be2f2c2b0509f960aeb85678bb56a5084f40b4ff1f1170361515d1	\\x0000000100000001a8a4e70bb0ce44ee87ce2d6958bd26df90b848e9a667482961cea9c9514abc638c6c131255e708a63b3f38109e490cb7b1b8c05b015b6b1a21783397a7764623e5755cde48fb3b6b7956ccc780d9c351d1c63956c0a0f3c6b66280bf556dcb10f4cca65da5a564489dc618af95490226af0ef033e998895257c9fa74f84244f3	\\x0000000100010000
41	4	4	\\xfd32d82b95daecd27eedc41642d0a1313bbd9afbe29a43acebe471136378e82448730abdd11218df8e35a004e844480a7c8fd8a30a003029dd0f86a20cee9a01	289	\\x000000010000010067f26a790ebfe632f3add747ebb8dbafa50aaa94003a962e26bc6d9db8f7d0625f94beb841bc73bf60136640f30381fa1e07a816822d0af5f6eee42971d95f9c89ef8d96b1b7240aa6ded9d02726a4df170981ec9ee6f70833f7609d02737f5115e520a0581f6cda922817d4e28adcb34697d43dd20d2d51bc5d6969a4caabc3	\\xb80ed8f669155c0bdc8f0d570e3861fd527cf67b30d913196d7cad78e7d8698ede2ba482ebb0d8c5a10fa71c71652f5e53a8b476da2aacb815a29d6bbc549a1f	\\x000000010000000145a6dcc337f614468689eb020c5d713518ae28658cbbb0a17ab4443a9411e818db5270242ca2120d34ac3bebf596250efd5e33ab961f2587e3c63315cdbc65aef647499ad897c5b138f16b33671ac41cb8bf2cf5f0d63936e5c18c0adc48c9550dc1251c3a23799731f95db0413c859b78facd919ba02351d08bb131457b0c9b	\\x0000000100010000
42	4	5	\\xc4a5378d7625437d908f1c5473d135c1758b259fac064f9b25786e46eede97e3664af362779586e3620be0ff263dbcfded76340248f5630b3459ce5d8488ab0c	289	\\x000000010000010064b6bd447722df685cfa3337fa4b73f36742db2a49ddc112e2c6ff869fc2097cffdd97011c77b222dfb0f656e6e743e557e32a71ce25ae770b98d6927648f1279825ca6db4f581fcfcc9c78f2e3ea6d30e4514c7b89bc71b2f192f4dcb11f77d0498e22e2340a11ad304f7e1ff35b9fda5330c45f8a754b41cb80e0f7b1f6726	\\xd54453559aa9fb5dcaa856518b812598757a7b571370ed2cfb060de571028bf7a13ed41dccc0e1b4900e699968594c5b6cf14b068ae09913f532e6da51b84a31	\\x00000001000000017c4b5a8aca0b6517d1d797a5c7fd48a635ee9e86a3fac913ffbd684443a6e407cb04c6e856b7fb693b252b9b261b803161309a44084c5e7b7fdbad94c15d3483f47adcfbca7323683a7d53a7cf027a1d2fa949078dec34dc4253edcb34c7c60b30e29db3f06858a45e52256f1e5b43f7a9fa93b2001dd81aa662e8c6ad03f3c0	\\x0000000100010000
43	4	6	\\xe1bea7993bf013eab18dafbe0641eeb30c6140884cb6ecf46a5c3273d5981c4b3d4d1c65bada2cabc42e573cb3bc1a43a47b94071e26541286606692a59c7b0e	289	\\x000000010000010003d5986b7845563b764b151fac49ab12fc375514f529c8e8fce59a5399ee54a1814810d7bf0d7352134b0d1125c98343257a9f99a58fdbd759be8682096ee50c049c6e265973b6dc6fe320601313fdbc9e8b095204a5036d8da5950b12cccd04b6f468313f00f2ffdc717092be5349a1ee30d9431006a0706905e3633931774f	\\x641d3cbac527de11e1bcf7041b14e05ab26b12175bda9f24ca4f236b0b2d08cde14014aff64dd34f997be2eba36337154f566ed0c47e1e67d8bf220f9164beb0	\\x000000010000000136e41deb8cc181bcab767f0bcb0cb91ff89a2abfb483dd410288a8ac29238cc9ab8bd2a158e3eb8b482ffeb2cba39dc018c9c25322aafc6a7f5fb9b0233c6ee33d4b4bbd258f476f27d72123957c95fd21ff862f877cc6fcac4796655185c2945942b0d2070e92aa0c5d54bd0146d9cf65f13815aa50587ed309140e0e675fc8	\\x0000000100010000
44	4	7	\\xad0e07b27c54d4dd3cc96b962982bba688bb43042774eecea9023c59c2a1c672b06f4afdd21b1ccc5bce6ea96154aabfb41399fd62dc75eae467053de7872605	289	\\x000000010000010004f676475ff5c5ea66c97ae4f37f2444a71682cfedf5590fcf7e7b80964cb3ea2efe8545c1f5ee1ce1be8e746560454c6233a98b79b95da14f83af133b0b15bf87d2c9406cecff914011c483008fe1e374da09e9e4c0a5b0aa886931db01aec26d2a4b2ebbbe360481e8a35ad6357d75f7cb9e8ae1dca941b1ab0a6ec0c0ebdc	\\x6453d17c3c6fc368c10574b6887c7a1a49e250e05db455c0b1f550eeec80f145b109e92d09a609526688f1d74a90e84ab2b7c105028c958c8405c6e99179a7ce	\\x000000010000000143e56f3b79b2b9489f8997b3a03226189f7e993fe6210c74ea0f88189a92d2e2f00674b99e1ca9278fc8436f0b28c5bd3431fa348e11c1ca2a23798d023cf63cc1f38235c937589ec9217c692677ce5fc865881302c8dae6f2acfb3896f68461c84553f20e51825abea19efd78fa828dfbc3001cb4d5ccb9224b6f75bc4b9f86	\\x0000000100010000
45	4	8	\\xfbd506225dc53e0567d95066687e49af7e5b7ace34427da13a246665bd6c5bac94a9da5464b94dae0a63688a0b45c4e4961fd0ba1c596d25eb12e065a8836602	289	\\x00000001000001002ac779adf604fcb840b6f7b39d80a338bd1e47b33fc94a868b2d5dfbcd6a894a9324156e4f4f0236bf00f6e055a44ae195f88138bb25057634adc2e6b0767143563107bbc518119e2730de0886c6f88580154886edc24c4854191d97ca5b351c2dae4c8a3eab1fe7fb4905051b43ae0db17e020152b980f5ffeebd96cf6ed552	\\xc5ac1a400f4331087f133bfb9fc721a5c5813fe65f84ca747ff2b45315c5146574f5a83a29679001acdd2ee84da821566b951b30a9e0efe866528bba09531420	\\x00000001000000015eaef5c24a9e82ad5d25883b4c5aab7aeab67f9f34c871ddab43fa0623d978e7b2892d51d0c716db2dc49ff7a70009c3d57ba6508213fa8a5d18ac4170fc4228d62e345ccf68e3a57bc8192c3c958c31ccd99d8ab1f7e15b566ead8a1e0c3ee7b0d190fbb0383886d20094429bfbb8345fdef4920d85b9ec149b1ac389472e8a	\\x0000000100010000
46	4	9	\\x83d5de2d5ed3700bf6f5c4a610b84cde4b768e6f71747edd3814ca6df5aea9aeae8f7df8c01396ef7f82efe9f4aee698dfa2248da361e52905a43aa0d0286109	224	\\x00000001000001006af423c8b2dc494c20b2be2d60c31f2df0cef3db50fb0f4d21bbcc10cdecef538808601edd8c132528e800ff559a731a57b2fcd9d4ab3b705d2ae8a4bca45a37d4d70a44d698807f3fb35fa88453bc3ce794593c418dcc5ba8383632da19eefcf4286ac5331125eb68a063b1bc07b043ea73c0f36c4e4faf99fe39dde6b568be	\\x0f641e9cc4bbc2c4cbb5054c78c3163c5e5e14046885f6db03e7a8633379b81dccc8d2d9bf6c087f9c57cb690604955e5b41dbd6187fd231815d5715d60d0cb8	\\x000000010000000128d398c3c4c72b2290c8fde875723b3e6b3e67d7c9554a192e3d8d64e9a356858ab396b8d4fb5b44d388e18d5cf00174d3824c8c76cddff64da86f4cf893c961fb51aaa1f665d608fddb9e9fb7640a6e518cc7038e19550f6f1776f71714c4faa25604cadb0665bc25fe5126b92697bf709340ee3c870cb6d62bbbab4f09120d	\\x0000000100010000
47	4	10	\\x9f9b7efce134713f483e5d9969fe513e60dc78f8d936bbbaece2c2ec6f2b3e530952d808508376a9bf06383264a4797ed8d898898f71aac663a4e950124a7d0d	224	\\x000000010000010040119b898ecae540bb99d90841034a865bc6cd3fb4b1f9b6b17a029d1691f04544b8d199d2bbbc784372767725c7d5fd3d79fa45a1b88d073b3e1cc08041ceba38037d2509a48fbc6b70ef75017304b9cded6f69ee4edfbf847b7b160eea7714f48478512b4b922edff8893ac5fe1b3a2071efa2fcbb020de6399b84ec9c35e2	\\xbc6a6524229117a666198a3e3200df637ae2233471f18237bcb675a031512314bf5393ca92f1ee43245ff2ebf88c9a87109116585a478224918b0d23337b354b	\\x00000001000000010709e06bb93c8e57356bf46e922a50a7a35d3326d3d581357c18f20e4d608ae9a1b68240cb184f72b042adbc2c65569215751df028c7f02617dcfa62a3b55aeee51aeaca473c0ea7f9f674aa5201c7ec8678f99899a781be14141184a0abe445f746310ca8740d841a0f47521263a3ae71946951ebc0e6770d092e4ce1ee548e	\\x0000000100010000
48	4	11	\\xd207ddc86c6de399b3927c2074d0ec6e6269ca9f688e6329e52b6bc9e0f5ebc1f4c9ed2b98c5ca9d0b23f799185655fea6fd937d9f9505e787880969d19e8f0b	224	\\x00000001000001001008a539655e69bb4adcf913eda3c9b855dcdaf541282285fadad1ef9745e3efac85a43e7574a3f1ccfa90d2e2d9f5b46542fb8e9bfc8da4b298f7b1ef88854c36d77fc5b224a9150c72753ee0d15acdf2a5322cdb8d6f21f7dd449e71ca12afbe5c4cd453eb654a4c35145f2fc577ac431501b54fddc77ad35be7a605bed328	\\xdbd25636699ac432c93d3330cd07c03c6a638bcb10996cf02c1112e29fb3a2e44571756573009ef3992b77f356d98c65aa0d153881d1076e2612037eacee0378	\\x0000000100000001a59dfe1472db3481bdab34f588f24221e56525c4e5a55087beaa0d82bb60863354db08df80e25e9fc55c48774b16757bb673cdb31437d7d8e343c5f8ee24873eb0e83e851e075fb88acfc25a9ab1778246e250606da1cce835ef6fa05aa9eae59381dd5484ec17277615d6c0693d870e83ceffc21f4ba7e29af7b925167acc00	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\x1249c7d29353a45697e140859efb39f3fe66e7759a485c15ce409a3568bac432	\\xcec5fa1e196c179c7522d9aa564ac39d50925077ada731541537cb8c96491f3be9119736be26a89d599be2768a03e827636accf4119032879518dafe1042789d
2	2	\\x24c5e831f9239680425bdac319e3e533edc5fea4e5b0e40393720875715e831b	\\xb3ed89b937d4c58a0f56cc1a76fc24eb33bcb9f4960cdc4841096b9ab232a82a3cf9167b4fc24667c406e23ae5b132aa197011ac09bab3bcc2bda81599d85b3a
3	3	\\xb590d2da2891788a6c8b791f465cfbc5c0a686131b06b2d42118de4955096d2e	\\xdfe589dbee42312594e5d596fd346410e5a853cb4b188fb8cae899ccbb484bac1ecb0870bf0308a2e528866824bf190f8be622c99afbc88eb7cfd05e3f867e10
4	4	\\x8837c85c0849c79c61b506d89ee1df9331d8d654d64ab3f5926d7279d9c04872	\\xedabf278d51178ebb199dad10553e35555ba64b91e01ec6cf4db1263362d69f20a16204f9db7a9c3b5de1939b2a125f0b5477551a2449227fda768b939f4da3b
\.


--
-- Data for Name: refunds_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds_default (refund_serial_id, coin_pub, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xbd3df484b6874e48478333300df8398720935e1b7a662e769cde72df6753117a	2	\\x54e4d1a9001ba71231d1b6cc84dcabde52fad75af6118d2311f6a4915e311883dc3bd599e70641109745e607f3d8464fa6af96a0c6f54fc64a96b2e03948030e	1	6	0
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
1	\\x79eb2273bbe105fb858f269d4f6fd8e17c9fd9b3e01011889b9b828adfafb27f	0	1000000	0	0	f	f	120	1657543698000000	1875876501000000
5	\\xc3708facf88207bce85c6813fbea8cb94ec57c29970441ee7b69302a98a939f1	0	1000000	0	0	f	f	120	1657543706000000	1875876508000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\x79eb2273bbe105fb858f269d4f6fd8e17c9fd9b3e01011889b9b828adfafb27f	2	10	0	\\x86add62f4a7434d5adfe87d370c4f90205064974b3c380735d81b29f22adcfef	exchange-account-1	1655124498000000
5	\\xc3708facf88207bce85c6813fbea8cb94ec57c29970441ee7b69302a98a939f1	4	18	0	\\x99d31ed72a1098bcf4cd189bdea76992100f05b8325c0f7380b8e0c3eda1c01b	exchange-account-1	1655124506000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\xf59933b1b029847b1f9dbbcd59dc076aaefcb1b3090107d57289e1758a6169967b80fe18457ccf73abf28384c073fba9ec7a5fcaf9a280ad1df97cfa1767a474
1	\\x106d04545e2dd9469be0cfcf623eec1ac62fd416051c24780466c8322f60494c9ba996489cbfed5c5250cdd90e06d14e3dae626193ff536462828d21b9015d51
1	\\xb86cecbe03cf32d358477d294446e4ac192005907ddb14d614e37889c6ff61ab7ffe13e372b4bdbe0e11cce85e6df68f52540e564d6f5cec4e5ad0b5b088901a
1	\\x88bf738447d37e62865d85959a8a5677c93106fefe9f2b8c4dbf2794701b7611c0a335d96b34fec0affa10f2269c07b30b4b6bec43e0359f56ff181b1b1c9646
1	\\xb6848346e5f152011d2d29f3ae96be0284e6e55798e7b806cd0f677ae015cf5fbf2c018416eb74e0e6a86a5c88a49141f84a591111ab909505573369f23bbd3e
1	\\xaca0c1812faf2847ceeab6862ccaa4ac85b4a8271ae7c92582ec75d3e07fbd3abb354fabe79afca1dcf88312e11997e6ac06231c80ffb37875d9c7e416bc8747
1	\\x9b5caa3a02245d9afff9518d532c801885d04abb4293709cfcf3cab253aaf05c30fda12646b18e97f94e50244e290591d752163aa2f6be4dd2ac8b0f6289ae0c
1	\\xf88c7cb0cf4ea5002ad34950f6ac78c90c12fcda7586fba5b1d0cf10c7b8b1e09913bc48d7318d3686ab67eed9ff437a702da8c802a9c7f2e73e2f263cdb7da7
1	\\xdcb23d61271925e8ba5f504ae8e43bb1a24dd9f63471d8deef218bdeeb95b6f298839d4bc1599a79c336c8df4d2dacc0415dabf3c59e2a0ec353b463b20d95c0
1	\\x9f88592b0d004f2ef7e823f577ce7db399911b8bd7ed9480332a1b2869957fbd37c987a00a9219f3aa04f7f48598149177d9babcb3343ffe2c175b476238f3e7
1	\\x4dfac582218eef9a02837ac322eb1c212ab3905950acc956f7458ca5cf8365a59fbffbb2d71b87ac0e3d05cfe159da111a15943de1f69ada823505c4fe702ef3
1	\\x90525de7c3a80376751bbca4b0c456a6b2c13d3becac95af97ce9b2fa49ca9212a818f4fb063e61b1e00e91b3d6123b76326db5af5a5ce1165c7a0b273a24268
5	\\x4882957cf8cc3918fbde7db646da59a1b0813261474618e5bc376915b66610576eb9705473b3378cfb504f51100c7a49f5fde9eaf10f7099c5146cc3fde1d5e3
5	\\xdade3a1f1a921cbe61234a4118138c31e47c559c30f8a198d64c1b3ef99c2b8fdeac8388e3e2a239595bde2485c96bd3e6b2a4ad788929fce2b6afd3a5150c0c
5	\\xda3497efbe11e95cb20184d3a4e01346dcc8ac9fbc3779db942871de9acf621b364d116820730d7f3ac057826dd0077cad407bd47bfd6f800ebce3fcf6aca4c6
5	\\x059776ac3a74c7d064ac7589e0878c239e205950595fd1334f0edfecc62277b45c79dd1f03a37269cbfc165e36e44afe98795cd1bbcaf77ea75db1821442b942
5	\\x86c69f9c39231d4dca60c8b5eb195d6c629a4c90c306a5c1ea48a2e2096c57ae7e54f4769d3246d50a724d858b5563873dd0fcc01473778ab3fbeb66a4537a1a
5	\\x4ba678c048db7782da292247bd59fdc4a850a78f7a7917db8187ffe3e574d68377fb183a606c6675f87884c8481e883309549fd1d3f6a99a98e0a1ad04948876
5	\\x4244c3208d0c54c0f1116fbf5d6dfbd154d6b26f500929e959261e11f05de537baad55580fd4464d7a660626695468f7df8109cfd753bf6023e139f49c51277a
5	\\xcfbaf3825a4e6f54cf22ef1c76458245709dc611c886746a6ab38443312cf69875f18f12d78e7641dbe8fbae4320824e17bb3206a03398ab5b7cd364232401a0
5	\\xde58fb50d19bd3a6b06267f7a246ac441987dddbe8d16014258a6712b40d4194d6754cca2aea53db59a3ca5ef641f7dc9e108be64e3e595b723a7ddf3b812b4c
5	\\x7f1a611373be366e03aeb7494b8046e8e753df7b92df162bb5ffe7aafded6e6d02ef5e2581c3da0195b2fe4212965f132670e140d85154c2b6827933bfdde61d
5	\\x896991de19c5436ba94df45b0baf0dd575985134f59daf5e67f469cabd9b345845568f871d30b1c7719412359afa494ae6ea5222655ae3ee51b4580e74ba9b64
5	\\x446e8a7abcdaf860f9ff443b6915a52b38dec18935371f90c55c66c764a2b506f9dd280bf71b194db75f63410732f9b7d84e40775d8743cec3684519a1fd8fed
5	\\x44d05c56ee29a5b767f2316588838712e738b119ce874d4f0a654517600c447e9aa4d6649e2a4460ef9fcdb267f67c4e103ea88ae88281f8a8933bc887e5f252
5	\\xf8c136b6cc2d4c61f9e289fdad21589bbac36db4d675d93f00488a13b1a341e20ee21dbe54bd7da9dfe8e0c4491ae8f4647c09f00313871c2d0075280cd89b9c
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xf59933b1b029847b1f9dbbcd59dc076aaefcb1b3090107d57289e1758a6169967b80fe18457ccf73abf28384c073fba9ec7a5fcaf9a280ad1df97cfa1767a474	128	\\x000000010000000189085b0b2a4b424bab4f8a2376f1f43d0c62bbe8817416cbfdf2b49384f13fdd3ece2b4c64ee1a8c13debd685cd5c74654ec0c0536507082f180837e81cee95e02d2fffe01be8964ceb3aa3986608d3f3ecbc77f7e0697b16a26726ce022b453f191fe76b03c741029be850f412385da6c5b5fe410a22bd6488ebf3bf51f2b58	1	\\xf962a535cf1e56fdde5b18b172b5d2ef8b700a41c1c1a07a7280bd936f0790ddfb2b65fd52242a6adc5f2c459e7645722af9bd44e938aa9cd0c03634edbeb703	1655124501000000	8	5000000
2	\\x106d04545e2dd9469be0cfcf623eec1ac62fd416051c24780466c8322f60494c9ba996489cbfed5c5250cdd90e06d14e3dae626193ff536462828d21b9015d51	424	\\x00000001000000015f44f7f7711a1c05cc133232897684862b3bf4e79f86464975134d89b201355b64bc4a13f2c5a9d2401bee5cd8a3fbb36d7e5f1f600c8326a13f4925e62c50bb09d6a4a4671d3956bc88b83cc47feec9ec9c581c95992d0661f88e1d9f0369b31d73f9543737bc8f144ba2fb1b3986f8d154cd49125cf365f82017df93456382	1	\\xed2cfe56e81c828dbbc4b51f2f34cb54caf19518625865b518c6914687fca4359596db8ea0b53b5f83271e7fe7ea7abfa5d68d6ecd8afb5cb2c4e42dbcdb3102	1655124501000000	1	2000000
3	\\xb86cecbe03cf32d358477d294446e4ac192005907ddb14d614e37889c6ff61ab7ffe13e372b4bdbe0e11cce85e6df68f52540e564d6f5cec4e5ad0b5b088901a	289	\\x0000000100000001849631a550491ffd1c7924269eaf748f8d4d5594c6ca9e0d9f646f7b9e20f08b24ce48b62fa1f916620507d03388f0192fd5daf70a678f080bac20cfb44c83f511d33bfcc87d63841ec01d46ebf2e02aafbff304fe723542891bd2b8ca649b0c080011c845fc32c1609d31a9cb2561d0ab1a46b74189f77e5973d8f59e39181a	1	\\x10f321f21ba70c271ec35a4f3d941cdedf9faa2c25272e6bfc1b28fc31d625d9f07b3b1485964b820505ddcb394ebc29fa24efd56f4622a914261004a4e32a04	1655124501000000	0	11000000
4	\\x88bf738447d37e62865d85959a8a5677c93106fefe9f2b8c4dbf2794701b7611c0a335d96b34fec0affa10f2269c07b30b4b6bec43e0359f56ff181b1b1c9646	289	\\x00000001000000016d81d7d4113d0e462be17ec91c7eb930941c5f95a3338c7ec142c608999735ea4d0757a3489e03725de2064869c943dc304aebb66b4e2c2ba745375aa094f3f7962e624445925cd1a8eefd0f8252d3d3e26c7d634d4a61fe09ae52a38ef1088c20cd8fd2398a283cac3dea23be4eb9fa9f658bcf82b46550a7e48a7d55b609e0	1	\\xd22490baa3d75d626fd25a013269bdff8567e482a8576b679280610bb00c71724ccbdd8dc31caff8d6d6a73c2dbf15a723ae8598c3dff0f75b5bc4439b41c90b	1655124501000000	0	11000000
5	\\xb6848346e5f152011d2d29f3ae96be0284e6e55798e7b806cd0f677ae015cf5fbf2c018416eb74e0e6a86a5c88a49141f84a591111ab909505573369f23bbd3e	289	\\x0000000100000001123ccd5dacb032242d163c3b3179f26764c7669f3033219b0c82531127d518d47883bc639e40d75572de10dbead55a1ccd6a2b40ca2a9e9eb89231a97e6425e353a691e4a16a689318b42eaa657628fed0c51b04be0fb1d1c93cdd39bb90d8daffaa7ed690c96ef5e62e8a6014f1668a62ef69f58db1324cbdb5cad1fbf3afab	1	\\xa2cd09db3b8e766c704cd906cba7880070750a8541658d5e1b42050ba8758945982cb6a4ac83fa127536d41dc4289b388c0db357850fd9cce8b7ea0288ea940a	1655124501000000	0	11000000
6	\\xaca0c1812faf2847ceeab6862ccaa4ac85b4a8271ae7c92582ec75d3e07fbd3abb354fabe79afca1dcf88312e11997e6ac06231c80ffb37875d9c7e416bc8747	289	\\x000000010000000104474450f60be249682991cf76f0a9dbf785f37278f8b8da72a61a781cf4621d87df6d89fdaa499abc3b02d4191e871b998ce6ffb3ecc478d6a998b649086fd9ef37553e3030519e247a568780572479ea73b79dc26ef294d64e87fd54c55317cd1563e862cf3b45b17e4537c36a3d2fb2ce87095a1d136138ffdc61088dc389	1	\\xd193896eca9e9431e77686b6d7e6334c2ddaecb1b736d6e0dfed795c81ebe8d81c3d34fa71da3b35246985f317109495e72294458f3c17fc1d2ada4733ec5408	1655124501000000	0	11000000
7	\\x9b5caa3a02245d9afff9518d532c801885d04abb4293709cfcf3cab253aaf05c30fda12646b18e97f94e50244e290591d752163aa2f6be4dd2ac8b0f6289ae0c	289	\\x00000001000000010bc3453abe3113b708cef6ec48794ddaa60c10069dd0a286a6e7891a657566064e4b8f61c1e2065cf7253c0b41d3420e7b1ebaaf8cac3405eeecb33877c33eaaac8c9aafca55f6b0de74a5829c4b2e610d43e6c3ef59fc03d892adc97b2d92fe9b211417a3acd318ce1f9abf8b76dbe3eb2320d0bebeb9fce597e4f23ff65df3	1	\\x0230b15eb63ea9e6f2c4e57722abff22b4f50b26ade30bc3ad4bb8b27ccb716f0cc117b318588ae7b0596714c9a793118523405f8b9a002d6495f365bcf0ee07	1655124501000000	0	11000000
8	\\xf88c7cb0cf4ea5002ad34950f6ac78c90c12fcda7586fba5b1d0cf10c7b8b1e09913bc48d7318d3686ab67eed9ff437a702da8c802a9c7f2e73e2f263cdb7da7	289	\\x00000001000000011e53ffdc1e7f233487c0aba36ff608e3205168becd9d27ae3649f470b6109e9e9a32e31856c5da13e2e2ea309f58448d9cd5bac6978e7e6d3298facd6ea633a0f659041ab563adcd780a0000a8df73307009569f9c2a767f71ab25ec835eb332f502d49fb7f883f37f8b71f183ae250decd5035fa6d92b414bda6d9b7e873bae	1	\\xa70536b7a516c6fa83977ad5aac54656b0a0044f37d3c4a36b7cf589751cb4b6b0f617e79b3b3c1addf08cc7ad15294dd5773d2ebde9c7739bf10435e4147005	1655124501000000	0	11000000
9	\\xdcb23d61271925e8ba5f504ae8e43bb1a24dd9f63471d8deef218bdeeb95b6f298839d4bc1599a79c336c8df4d2dacc0415dabf3c59e2a0ec353b463b20d95c0	289	\\x00000001000000011be8cc3efa9f29d07419a164020d51fb94eb9e91cee6741f3d846bd3c9329f72aea10897f9d407c576eccea49f9792c91c316f1271b17426690865f66b95f5098398f0ddbc05fa8567bc27090c30ee7cbb49578f9ef641ce2dce734c519d791122202fda600be5e47f79ecbea4b3b7c97418ef20c46391a98dde6802bdf62bff	1	\\xbe6ecd2da945d6576e3fb71ae70d5fffec62d9e2cfc15ff2320aac195815d90095ba9d1a6557c23dbf68d2bd895c8a70848e648c37f7ed75aeb6936740e48c0a	1655124501000000	0	11000000
10	\\x9f88592b0d004f2ef7e823f577ce7db399911b8bd7ed9480332a1b2869957fbd37c987a00a9219f3aa04f7f48598149177d9babcb3343ffe2c175b476238f3e7	289	\\x00000001000000019ef24ebfd5738d02a7fe3b94013ee48551e58bc80eba7defaf2248184d533fa24e11757099db41e2d460523847c9381d4242f51b2467175c33f0a8e6eeaa3e722556f62634eeef4670137bfeaab4e4ee5efc6c561b104bbe1782fc7f0ddf26ffa3a64f854cb7728b122891768963a38076ca8d71ed978af43127d98ff6bf397e	1	\\x36577b25397f4d92b51bf5ac15f170b500150f291ba1c21f5f8b87ea37cd38c82505dbb222c5a241cfa36ad1a8013e0bde1bb110b50bea244feae57cd8c97e0e	1655124501000000	0	11000000
11	\\x4dfac582218eef9a02837ac322eb1c212ab3905950acc956f7458ca5cf8365a59fbffbb2d71b87ac0e3d05cfe159da111a15943de1f69ada823505c4fe702ef3	224	\\x000000010000000160d724cc24c2826e41062344b95306d63c6763dd89014fe58d040f7d6f1b6c7875d1492c34c7ef7e4b1ad71af6812e4ec0fa49e89e7c669c2ef52a5ae6e77c24b47a6034ec9db440a278f3a1b859be92ac8b6ed60029404bb639575c15752d14543b3a6f2063b75bc0d38ceeeb630d531c1f93302413a0dfc460bf9ea9873e78	1	\\xbdbdd4a4aa5bbe99a1957588ac28791ac671fbc34089379a6fec46ffac47268fd6b3fd2e4a7c8388969e8ec0776f16c0a36a8c96ea9761e8f91e39ba05e59101	1655124501000000	0	2000000
12	\\x90525de7c3a80376751bbca4b0c456a6b2c13d3becac95af97ce9b2fa49ca9212a818f4fb063e61b1e00e91b3d6123b76326db5af5a5ce1165c7a0b273a24268	224	\\x000000010000000179cd22a167d7d0bbfe667751f21e770c5672f813fb567a16d82c3d4d3c71a8613726946a88c336eb1a483957fb797300cf158a71f14a0a4957075b15499f165ccf4ffad650525e1234ab54c145cc882d66cd6c5f0f713c0e20f54361f6d057b554e058f825fa7789214d153f1ca1d7fe7de6321b9caa6367af57f95411c934ef	1	\\xc54894892130d6db3adbded97de5e95bf42f2abebf0fd3ab7a6de19d6d887726bd2c3ecb45e83c0cbc1fb219cd89465a0947a368723a402c71bd26b07b98cf04	1655124501000000	0	2000000
13	\\x4882957cf8cc3918fbde7db646da59a1b0813261474618e5bc376915b66610576eb9705473b3378cfb504f51100c7a49f5fde9eaf10f7099c5146cc3fde1d5e3	52	\\x00000001000000014bb2a702aa656ab2246607860263a55b82a713fe3b729722945b592a147d0e1d5411c9a8ef08d6a47393bf7d9aa5d5712fabda0ed08876d3b15e5850d83b8f9fa79cbbda5e7ea946f8fb80c42089ea073a7fa5bf1a64cc477d60ae86d7d6da56ddff4a844518cfd51a5d6ddfd79d2bc59e588c0c01b77dfcfc33b62071fbe2d0	5	\\x43e3d2738a98cb168455b2f57a3854cf741077817c58f0a52231c3d0da2adf03a964b7226e4e747c950c0223be77584816625137057e933420009b2944bc3f09	1655124508000000	10	1000000
14	\\xdade3a1f1a921cbe61234a4118138c31e47c559c30f8a198d64c1b3ef99c2b8fdeac8388e3e2a239595bde2485c96bd3e6b2a4ad788929fce2b6afd3a5150c0c	86	\\x0000000100000001bcc6c55d809f8bf856a531799d233f2b90d27025fb60c68fede30c438b039ce4ca3f10293ebb9a7db54e86d479b1a640a6753c2d366afa41d9d79c7d541fb302acffecc53a77964c32d10cafdddebd4ae51106013742a944b93ad0492ae3e09f4e4358625f43793008fd8181a165208b8bb9c2ba2316a7e4c62f4b5ba1456c84	5	\\x8dcc6af7151adca2b660ec7219dbd22d3d7fde74a16ba329a73f338a52485cb565e283b81850f4cdbbcdb593bf0a3619a3bb0020207b9d34e3233afe5a9b330a	1655124508000000	5	1000000
15	\\xda3497efbe11e95cb20184d3a4e01346dcc8ac9fbc3779db942871de9acf621b364d116820730d7f3ac057826dd0077cad407bd47bfd6f800ebce3fcf6aca4c6	243	\\x000000010000000101b521650e074485958a93e9375dc4e18c3990dfc98702bf4326ab0f8a46bf9e34ad81849234276460f8a6a9debc0764888ae7d944b7a62c945fcce003d562c317ca5f87c6d5ffaf427de74c0c8b635f183eed12640cc311108e8aaccf2a04cbc5f3dd198a996efb9914cfa15f5bee10aa2c46f05d9efd35073c3c9c518ff71e	5	\\x7b45122c90347d7d3c76319f121add84bb4f39fee8cea438fe382f0c2695743cc37880c76d160039079ac85a988c49c48c8d4896be4b38d1e576e447c2b90807	1655124508000000	2	3000000
16	\\x059776ac3a74c7d064ac7589e0878c239e205950595fd1334f0edfecc62277b45c79dd1f03a37269cbfc165e36e44afe98795cd1bbcaf77ea75db1821442b942	289	\\x00000001000000012acf361f559f20656aea8df0eaaa334505eb578f26cfa524b8edf962bbc9ed9e97fd785e26b48f0aa81fd05bdc3fa0ce334e2e9ede8178167278b112b7c3e15558afb12e83daa8e470a1068550211078d6bf5e0dbf47efb18dd0e2d0c63393d871e3f2bf396919ecec9f297d69ccca6f07c856de21d9dd01f184c42b13e133b2	5	\\xae8fb44be3db8d5e348d8035ab72ddc00e3df1af3d74c0867f473747b6fb84555fc864dee7088e7dd48b1f750f3be7552ec5eff98760e91e7d8ae1a65db0fe08	1655124508000000	0	11000000
17	\\x86c69f9c39231d4dca60c8b5eb195d6c629a4c90c306a5c1ea48a2e2096c57ae7e54f4769d3246d50a724d858b5563873dd0fcc01473778ab3fbeb66a4537a1a	289	\\x000000010000000179c5b9154d031d86a0b1711fcac7fc543681a981253ad795a720ebe32241c13dae63456d92c9afd59f0c711f04a2f7ff6e6676d1d87a870fee4939203ebce36874fb0d04529a5a34a450acca0cafabb03dced06e633967c6d2372d659a2f9aeeb1885725d8e555eb3745f7f697123f1899c396893bc1f0e3548fe9127fde42bd	5	\\xc81e1b2f4554237708dcaba2b1ae02a126cfac0e6e2c10a59a4ab7aa3ced1a56bea39b8f6b1842bf3eed530747a11ec26bd0777e3c55a0b23bd8d744c85d320a	1655124508000000	0	11000000
18	\\x4ba678c048db7782da292247bd59fdc4a850a78f7a7917db8187ffe3e574d68377fb183a606c6675f87884c8481e883309549fd1d3f6a99a98e0a1ad04948876	289	\\x000000010000000144462941cbec846afb61d8ed45b9f152144429c3047e2b3e8b54cf5551b71253902de4c58c877728730e6a314da53682c9a4936bf9f87a46484f467b325014239c400684f422ab1bb3c8d30af52fdeff1c3a7c7b23029467515e8c9b7560a2bda3d104ee22385c2cbcd39178c8245f52c7b93960d56efe21f41dff2c34043b63	5	\\xecc36d2a829706eee2059177a6a043482583c24f06f162e87df02e5fb17644d050828cc88a174da0c50d6b0d6b1d47414db1737f5ab0bfba4774375d06a3cd02	1655124508000000	0	11000000
19	\\x4244c3208d0c54c0f1116fbf5d6dfbd154d6b26f500929e959261e11f05de537baad55580fd4464d7a660626695468f7df8109cfd753bf6023e139f49c51277a	289	\\x000000010000000171b81637a03cf40b006417ad6949b1ba1237978b4101498d2387f6c9f947ae85c86f01b07e295256ab9d4e3a48a7b80299d42d58a89d2637540d758c85585494b6cc3acf2e325ba4b720092c1963adf8f83ea0d3ee4fad55b596b1c82ceadc76662e2e3997dd1aaecd375f60efb5518fec79cef649a66e684cbf329bc13def2a	5	\\x98e894263fa3fba0e4120b6bed540975f9d4ed35eb0081ad7885e8ba864904542a0c37abea5ce3e73b6591c5c926d88bac60d926d1f861ba4ae0b9663e7a700e	1655124508000000	0	11000000
20	\\xcfbaf3825a4e6f54cf22ef1c76458245709dc611c886746a6ab38443312cf69875f18f12d78e7641dbe8fbae4320824e17bb3206a03398ab5b7cd364232401a0	289	\\x000000010000000112ab5a5ae1effb4ea1c83a666292662b4ebb711684d5c806ab50725edb629531fd8a769a162f48708eb22c1a61a42b3c01d875c086f3d61d73ee1543b90df2fc65eaca9bfe78c3244e36e7cb51461e7d1f1048bdaa46ab4e35108a22de8825d8ff7b6d3dab9dda0166f086c8ddd0b532556d8fe1da1ad22442d84b9a52d5f17d	5	\\x51fc7905ab0129ac24d35c32239f1fef17c10842d7e5a620d29cfe0667a391f0ee48ef357ed0b1ebc92b18970002272ff1432388e606dbf76760971b87fb5c05	1655124508000000	0	11000000
21	\\xde58fb50d19bd3a6b06267f7a246ac441987dddbe8d16014258a6712b40d4194d6754cca2aea53db59a3ca5ef641f7dc9e108be64e3e595b723a7ddf3b812b4c	289	\\x00000001000000014c40ae619a88f2bef9aea269a4ba3a09092c30d8508da75cc6a9b9087ef6411c05c84383291a51d31d5182110f6d640a92cb02bf1f059eaebe76e3da733178333a38046c258183e4a7b3ed179309a74fdc7631ccc632ca334c21c2c0cef22da9d59e6fd4ab3e4fd4614f6cf55da5d610c4d04aa3c6cf2967c530fee9d87219fc	5	\\x2127d5c9f7251e1e1f31f18f01a04f2ef404061d1cc2d4277601f482effeff37b4e789ee0da849639f631d0ef425be9a222f40ddc3f7634c8310c8f8bed62005	1655124508000000	0	11000000
22	\\x7f1a611373be366e03aeb7494b8046e8e753df7b92df162bb5ffe7aafded6e6d02ef5e2581c3da0195b2fe4212965f132670e140d85154c2b6827933bfdde61d	289	\\x000000010000000118965a73af9ebbd250b1d3ee069c30879c314c908ea3f5f718b4e928951b14b66659ca01daed44f8442c6961b35e8771e1307ad1c5809704bc56339e77b27070cbef2e7bb990ce657b58b8cc0d034b4ff69016bc403be79b12d3e91f0a1e60d6c2a3b80c0845d718b8f935ab57bef57f036f4cf5f0c21e3dfcd2ba227ea3011b	5	\\xf8eba1a44180e5c1dd1386053078efcd3b104d315996b91a152c80164978a43e973e5867ae8d2555813f73d16db0770ccad1e80046bfc27aea2f40886ec40506	1655124508000000	0	11000000
23	\\x896991de19c5436ba94df45b0baf0dd575985134f59daf5e67f469cabd9b345845568f871d30b1c7719412359afa494ae6ea5222655ae3ee51b4580e74ba9b64	289	\\x000000010000000171e87f71de637cb73ebff004e9b923afe40ea29919deb9292ee6b5110d1d10fe55b3cf86fe4e130731e9f3e5d186af54d604de4bf2e54bf1383de51fcba9b929c89b272bdfa38867b34ee7eb795921d8fab5cb6b22b47e4069924f15360114292f70c027b982a0c22338b6aa90f4e4e93cdce168b78a6100eab202149cbb5d78	5	\\xb1ce71457bbbb15281793b2d12ef1d818591dfee456038230ff3fed2eb966bd2878ff098743d4abb163adfc541832e409ef27eb1fda6cc2f034ab59676d24a0f	1655124508000000	0	11000000
24	\\x446e8a7abcdaf860f9ff443b6915a52b38dec18935371f90c55c66c764a2b506f9dd280bf71b194db75f63410732f9b7d84e40775d8743cec3684519a1fd8fed	224	\\x00000001000000011bcdd4812f9796b9ea41f0d3f1c2e622737a2fe007a35852a6042ac788d5149b41836104c6f7e624b46388b645417f9f2d261fd0d87719f6c55ecd83f6c3bc676310edcb458d5a2a762a69fd0a4a3800a175e4a3af2ca1269f655fce1eea3dd7c17768ba1871ed7fc78c680924b5d1ad50b8f42ca096ed373e38bbd05534a4c7	5	\\x302cac4cda6e6e686832691a36a959d7c85269e711736df4b704a43b8d60bf6c5dab40bfedb867a16fe2c573ad5887c9b1ba85af11ead97136fa2770c899e90f	1655124508000000	0	2000000
25	\\x44d05c56ee29a5b767f2316588838712e738b119ce874d4f0a654517600c447e9aa4d6649e2a4460ef9fcdb267f67c4e103ea88ae88281f8a8933bc887e5f252	224	\\x0000000100000001878f21a3c8f015b9a089707595dc74fc5c1e16798ef5d57ad13af01b5f2e3cef4a419e1d773678c743882fd252d92e3b18993486486e95808fe69077cb12f491ca31ad866ebf0467e0a154b7e8ef0eb6d60394e320cfc5227d25f29ee5f513cf34d22d7b91e0676b7e9de8cc466e766371bf91eadf9c42e429b8c0ce6b788559	5	\\x13f9463299943fc679e503d95d9604c3d18762e7bbbac13f17fa97338558d2ec8ca95d8ea52a738dab51d895a4c5684c8e88f50389a63ce3ee3d3c9bb15c1301	1655124508000000	0	2000000
26	\\xf8c136b6cc2d4c61f9e289fdad21589bbac36db4d675d93f00488a13b1a341e20ee21dbe54bd7da9dfe8e0c4491ae8f4647c09f00313871c2d0075280cd89b9c	224	\\x000000010000000113cb0e35ef38727bc5d9b95e6d6120fc6c0a27619fe9811b21cd1d96b3dace9daf2376094bb1d24cc142c73bfc6dd7c3e3a8d40117e12916ed70c7c5af0587508e0986c900b6d7893ebf727fb5899a7afd847a4bd8b699f13bd63ffa603bc3ecacf989a50e17c595b6789526901932080a3840fb1f467ae0192b7030ed3de8c6	5	\\xeac5b4c72e37b050b16aefb1af30dcd8a2c30dfb3fded9ae70406a4f759270e6f7f25d039a21217f1d06cc652a53ae51aa8c71bb33005af57d7b77296cf27508	1655124508000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\xef8e1af2e7af0d6006c05870eabd29fa3b63a5473e877ecb4372bae777a1d2067b076f0ce1e6253b22631830b53b018cca6fdc18778f227f2c57eceb70d5290d	t	1655124491000000
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
1	x-taler-bank	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\xf41030a0b734a6e667554a11d20d01f6329e498210cb3f27a0dc713a770b02a8ad3bafce2ad8b5d00fe62dbcb0daa68aef7edd52f2d656ba636ef1b9fbd0ea01
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
1	\\x86add62f4a7434d5adfe87d370c4f90205064974b3c380735d81b29f22adcfef	payto://x-taler-bank/localhost/testuser-d429mmy8	f	\N
2	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	payto://x-taler-bank/localhost/43	f	\N
3	\\x99d31ed72a1098bcf4cd189bdea76992100f05b8325c0f7380b8e0c3eda1c01b	payto://x-taler-bank/localhost/testuser-nrlfevji	f	\N
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

SELECT pg_catalog.setval('public.reserves_in_reserve_in_serial_id_seq', 15, true);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_out_reserve_out_serial_id_seq', 26, true);


--
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_reserve_uuid_seq', 15, true);


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

