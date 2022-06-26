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
exchange-0001	2022-06-19 14:09:15.999773+02	grothoff	{}	{}
merchant-0001	2022-06-19 14:09:16.903953+02	grothoff	{}	{}
merchant-0002	2022-06-19 14:09:17.293337+02	grothoff	{}	{}
auditor-0001	2022-06-19 14:09:17.419085+02	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2022-06-19 14:09:27.273418+02	f	7cba7a12-88ff-4a37-b5af-3cc84c9c17e2	12	1
2	TESTKUDOS:8	BANA5SS040WY8ZBD4C873D1G91S31EZ49ZG3647TT4GF8EGZPDHG	2022-06-19 14:09:30.797861+02	f	d6f3182c-5314-4eeb-99a2-ad3c1beaa30f	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
3a864693-f24f-43f0-acfa-148a4f69d9c1	TESTKUDOS:8	t	t	f	BANA5SS040WY8ZBD4C873D1G91S31EZ49ZG3647TT4GF8EGZPDHG	2	12
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
1	1	10	\\xe1d58cc74ab5af00c931a317004abe22764c42ae5c630cef8653d3d96c77a75d0852de21438b2cabe9680a716e5ab9caf362e2fe14136d13315d2438b769b40a
2	1	215	\\x97592d7f2376552627e494c2c4fa2e83b6b339d7b3fe6b3a7a2b41277f1df56f47311fb62c71f6e9cc484f74e08d0e1903e0bf93e1027dfe013c2b17fbbcb50d
3	1	355	\\x8b94eb6fa0c7e551bfeb95bf1a19b06f93cc77d66cbb40a4007bfcfb8010cb61d8ac6edcb96113decf3943b789ae066a0088c7bbaff7288b1a47c656f1b6240f
4	1	395	\\x51b236d3b2e4868af65f8e4fb5d747eed7b9b0a5cbb6f58d409d5226568ab668ddd3a4e693d3eee737474d9d8fc45c65b778cf0024de9e6a10bb37ceb483020e
5	1	17	\\xcc1c22a8f417573a7ca58657275adf17e58ad8aac5ea1622dc2b04bcc4da46645cc45d1f8caa1d0c4816c9765b994ac438c8b61622c5b74d6ce77f76ec350e0f
6	1	166	\\xb45282f048f61e1d088daa6695a7424b4d60d5338470f973e99596a57c681361e661543d12c008a01d69175cef8eb3cd2860d923156b576bcedda7902ae1db03
7	1	131	\\x0e7e5d724f3260b856ff650a4b20e1243e20ec9f8c5723c8396646e9c1f242a0ce8291da7675963ca50f25cd7e50f794bfec22f5f67a39d778141851844e750b
8	1	180	\\x67dc17c067255aa0146977e9b7608a25536d97d10f5e0cf8facbc6ccd4e6531902c3ebac303f89ac683beeb7c1cddc6b430244667e9c9af3b96053a6092a9806
9	1	234	\\xda58cf11fef79edaa5d66473a3c721a005258e29bd5476acd5de607d04f38a8a3df0e501c68f364f2fd451a383b11b93d1338cbadb1526fd75281be249eb0e0e
10	1	272	\\x7fbf049f568e3891a80912a226a78e3ab57edcf8e771cc3f3fc6075d700c097a99570799432ef81c95948103eff69485b575f3185baf271fcf4cc421beba9907
11	1	19	\\xa6db3c839e1c9c2d3affabb05bb3e8584be2402880783eb55baaa6f7c9506b3a162c8585c898250bb5951f40db5514bb665877ae34806241b3d3772ade60650e
12	1	384	\\xf9377b7677087786e133d7abd43abc3f8bcc6794a4378e8367410693160f67d907b051df26041acb3387f854d00235c8edfbeddf19c89bcebb34f8767650cd03
13	1	278	\\xf10deb8d0ba054d6445a7d27e07b81271d99d0eb1b8570e004040b6a56f4bbfa1b9c8705bca514c3c4d411e94f2ccd3d10467cded46edb0571dd535da1fec70e
14	1	233	\\x15aaa37efd6cb226009bca1cea602f7a070ea70ec66bc067331a078b1956298632fd1ee2ef05ee9e11243250c8bfbee607fb45f2a4d8d12c51eb28670619d504
15	1	241	\\x1453ad028f2a1029e7ab31f60ab31cc1ee85894245901f238b07daa833977f9a2721a4fcc67cfad63b0c60fa9354c95a3b00db6bc4c74d9ef68233a308c10d0e
16	1	175	\\x1950307bb3b0d8ccc5bde73c95cf4c4edce9bd12b4fba4639fb1e828ad2af400965cedefdae32f63cff9e2f71c9e4d27076ca91205b7039976676be605e50c04
17	1	9	\\xa3c12032743f0bb93c483274858869533e211cb5513073ba2e4bd86747ca7a8b714197dd472c06566bf46a7bd2a9e6939d7cda6e706e0e5ef961dcc058d85208
18	1	247	\\xbaea199d68ee37fed1e96bde4ff03f04d95b7c67c97780dffbb012280ded7d5c2d747586a8e99fc57432c1d3d1aa128d79e8ea2f8c07cd0dfb72d73efc9eef03
19	1	137	\\x35b5191a95fed5b9fabb63cd5cdad36690ddb13a510e158905956a7c0981198ac5abd90b967893a0aa71b6b6719953f9461e8a890be0f9dec47734046d9cd60a
20	1	317	\\x35ca08288646ca4521e79c24835b0b0995a33f8747e4339f97c8544b143d2292b2462ba86d2dad4dc26fee475488f148b014efc2db54d830e785dd610cc2d20b
21	1	144	\\x6054a18978ca63ea7b647b7704faa42ea493da7be3ef34af3c667c1989fbb39146f13a9c848ba5c73a9ce62424ebeba3116e91f99aa843184a04f0f3cac0d007
22	1	225	\\x9d375fa26838de6ee26224171837d30be15859e40d116fa50deed47e5290ed62d1ab6fdb7e466314b75fd868ab5668067334ef26d044f3074c57aec24458fa0b
23	1	357	\\x5843bd074c7b1df424a8114679d34fc68963a9c13ee3b54df0e50529a4cbb71a9ba9602a04da13a72e5d4ce2c1b51ba73714578b96e6abb4f5f66269d6da580a
24	1	231	\\x395a1ad256dd4cfb8a30dcc6af4b04b4083e64464a0beffab50085c7ce82c77d071660c3a0e013ab657b6b0c6e9b5951de200d5f2e2529fc7ce5c80acd5e5b06
25	1	189	\\xd9c525eb5c97b6389ae02e6651c963cd6d897a36a0d3a109e57f2ff6d3640526f98d20bc0f48b86645c2708345d0b505c7b0db26e74c0081c3f5728fec71e90f
26	1	102	\\x94d173ff1b775b5b94a5e0c4ded3b2b17274619b7eb41c04308253496bdad3ac0d2368e3415ccc2c45932a81f4830c31cec60fc199c57fc69da79c2de9cb440e
27	1	21	\\x6bd807418dc0465d184c681f243d1af62bd4109185543c399e2f1e2d51f600b47040d83751285813376814a8de2a4b9e31f65832d31bfd6aa36e48ad6fb9fe05
28	1	289	\\xaafd54f58cbf20c783243ce326e9c6960f5339f4addc876b2c04b8b7ac5e90856958436f31d965e68eb89c4ce8ae1ebf64fbd512ae794a66afae2889b8bfd302
29	1	226	\\x97f857ab984dc034ec5d9cf189f7b3af2fbc857175ca8182bf5c71d71c55974800c015f58311e5cebe7c9e447fd0df234f6faae399d48677b5c9fbc68b5fdd04
30	1	89	\\x311bfc0c19f7b4bbc3b65fc24a485b230af850acce6cf417576cfa379b7215557bdb644fceda32738e797eb557947206a86cd2230e19915ac292c5086fe87103
31	1	1	\\x28a964c8a0d92682ccefccee72c6b0bfc3c563b9953903e16bbf4db640ebbcd86daf02cc11c911be575634664eb99530f482b0ea988b4912f2f714d9e0a3e502
32	1	2	\\x92f8dd688f9a3947ab4d4898a0f87216a0460db8cb636d027aa759eece7daf1ee4028e38b1913e48949aa5ddbd511a73a59b33e6ea12c109c1dc551c9dea4f0d
33	1	142	\\xa8bed11d177a06f68899c96e8d1d810d935f7f7feb1433102f8667ab87210fcfe7287531c5b67b82bb95b69a26dd48afc30f89e13cc5b460e983cc7585def805
34	1	163	\\x900f059560670ed137a16449277b619cb66627185cd0ff19c2ec89df06b641878404f1a1eb2e7b1cb0815c101c2882f45ffaec19c9ac1610866377544191470b
35	1	263	\\x6f31f0f60e46681d2acc4e683a44369f53bff3420320434b6d995d935a4bdeb7df1cd14601a9c663fa5594e2b483cba19a92964a2457c43fa9e1c06744d73f09
36	1	68	\\xa3074e1c2b4d61cfc473317dd70f812736a4fca40a68e47c5022d8986f546a99f27d3cc6e9904792ef5fe932071f382734e1a757697caf383bbb374f10ffd107
37	1	246	\\xabf2e8c78185d21294bcbde3d06307a65bb70ac77c210ee7ed0a7a40b7ef1611538221da5202b61a558308984f8b55f426eafa7f68584ea4d091d90cd52bf305
38	1	80	\\x79a0bcb7a2aa33e212a4f6dcb5fe99d4f2d8901d18ff24029de13977237ac619c1fabc1d377a95b2bca4ea6c95ba0816957de622911b19da7d1d13272074c50b
39	1	188	\\x1d3d2aae703d8e399561d410312e5219ade426497a9023c5cfa4c77f52bbfb59c943851bd0995568ed67db52823669b06ac4eb30b5aaae1de20f1f69a7431b02
40	1	237	\\xc8cd7774632eb090b9a829f07c7c7535ee84292dbe0fbad8dea2701113903b2f1a673c4a7abd8bb94c897ac7c81e8ffb248cf5568a60c6c4e19b5461c44c6f0c
41	1	385	\\x394c839097331240ab965ea75b68850d754853a4fa02ba2ed1c2809a7a08d238ca9b687bada3d2ffd54f32777cd95a9defa27ce3f9e3fd6407ca2bfdcd287b0d
42	1	63	\\x7182d1a377c79463197f31d37caee3e7b85cf90bd77b468dc45666a6b1b4511b08cf40c1651451ba3090f355b8fa14db3ba26850c3077c77f25d65ffbe228d06
43	1	126	\\xd6609e33c6b41b7adee721398935828545f4628525100a98b973e20d524c6862d3b61e330cc2c3e0a5e314e02b67d9707646612af372148790a3d66b35066708
44	1	160	\\x523ae325e390ee43977460d9cc83086d67f135f4c01c0a73c493725bf8588a57f536af4465f38fd91f8140ab6cc06039624904d622242ee7c719c6c4967b790c
45	1	342	\\xb2a5e9d25d2cb29e92c92a6ea1ef8bc51b135bea49d49196e4d3e121db4f47aef39205f799330c8bf564f9f6ac0fd27e7db9d86974aecd78bd4273dedb480d0c
46	1	413	\\x7aca3f1e6e7479ad190025d53d591fe334621d2ea558e41ff5718e105789b0b27f3df435054e7dc307d14a62e500ed6dac0fe14db3195ddb6c843f7d48df9505
47	1	424	\\x67b82ba6356b136f3a1499a25b9d0681e6e446d623ae57cee6a414d4e965e2ded6520d73034b8a0de006010ce6d42ab3af2d20b563aeecb3deec3cfcf3c5b903
48	1	242	\\x4d7a35f7ecec5fa390c1274c34c3f0ed7b806947b5e341ba6d4081af9bdf8b0e12f120f1a10eabc36538a00a00ea9b6323dc4fa5913e39d5e6578104494e390b
49	1	103	\\x576e422e3b2c1eeeb069a7a566664d83cb43f157ead3c883816d88ab9078ed3de611899d7688353a8a32d52db731c962aea071504bd890031e6534715342830c
50	1	117	\\x0c7b4c90b861791616069f6921f63627e52a162786b80b36a99a7384e09df95f46f12a736d6ae32f0d1349b6861a15bcfcc506fd5c81bb708bdc75ac30d24e08
51	1	359	\\x323429a114271c4ac44beeea7cc16c36f9a3d721e34b8324602245e62a4f780c9c7aaaa714e2b15509acf1b1ca504b3852fbc13ab57fdc125aebf800e90f8400
52	1	170	\\xa6b38bead301a30cf0f24ef95e947fc80db6cd5cde7ff1fab524c585ec9406f56505c4921201b1f1c090bd7da883aab3e632ae68542790d7a62c74fbeee7f00a
53	1	29	\\x65ba4faae7354415140e8dd6d9f4c1511b9c53814b4ec0f3e86cc762d248fb06bc8e9271d1acc2eda4a094e4402edb721b9d198da13c9bcbaedff722a6d98504
54	1	370	\\xe7287e3aaa32d9b8addc5c386ed0474e16057be1f6c3e25c82b2ae8287288ae34a149df911f3294d058529f21bba88a03175f5b8de297cded13abbe29e5af00f
55	1	348	\\x5b6d9a23e3e4549bd291b66a6b4c932196398bebb1078dc41b5333bba812eaa72498ec830597ce574ca2737b637a0a3786c290e5aad1d4ccfeef36a546421501
56	1	389	\\xb1c67fa45b97e53c366be83a6b62f990bdf75483391b591d8e5bb36e2f603d1f212cab4daa42000002e136856f8531ee4aeccc5c742e0d81010b76d67498c702
57	1	43	\\xee56c93601df65e73435f2cd51355af8079817a95e3d2b6642e53c202d2f20fbf13d6f3712467d9e948033ffe5dc7679040b8e1b60b76c2fd4bd8de16a5a2d0b
58	1	123	\\xc634d13a8bb6f7d5b41ac2705fe3fe8ea40ad557634ce7dda5765485ffeb4a951dd1c9da4873c231cc28d66fbe473da85803234bfa7a95f9bceb8511b2baa00f
59	1	400	\\xc7ff961fa1d7cab4c17e803cdacba83c9d8c9add095bad5a223b97b72512ea9c2f61d0f71e0ec6cff0acb823135427319d5a66f07dda741af5e1252d8cbb9d04
60	1	141	\\x4a0695f6e6b51977ada90cee9599e8220307844c7124d7bc2a595cadcd1e8eb2f2f81b28214d22559672f9cbaaeb44321b4139e01f4cf7de9e5678a3c187ef08
61	1	365	\\x51651b768b4616ea030c01b376b94b8f29d3a6625a54072002d31d9cfd770d3d9a344e8bd3970ce034d626b6800a446ddc877f5634ffeedbdcee76f7420b1a07
62	1	24	\\xac0836e01e0fc817591b91a3472cafc5f297edc5d9134e28cf382d4842e414de89a5e8bdc48283efebaed7820b16cc45bbe42b50ad580a9bb997bf9b9458ad08
63	1	220	\\xeb349ff388015133490b0ace2730f66e517cb774c3641d6baf9434ad2e6d08cf214148fc3de43939f9eb34c5406507771b3afc0bf1c3d3504daf96de673dd804
64	1	271	\\x0a9766aeb831f0bfc335aa72a13bb5ea97865dca98db00ae4a071770f0f29669b0e477fefc2d2757fbced4f9cc422f0a4c5859a85fb1e7b1df9c8a74c271bf0a
65	1	154	\\xd212ce988d5116b3aecd77b4c3b75d33046bd7a00c24a26e332d60920bb0d58fbebfc967634a84c9fde00d37a75be5fd865dc40995909fa6cbd53e360fc12a02
66	1	280	\\xba63e4cbc8e7c0b4325cd93834edbef6e6a5d29174fa9735b79cab6e602196d5b7c2c58b00a6b350671668da9213e4c865cb888627bf319e8885e26701fcb10a
67	1	109	\\xa5ea3b72fe6c9d7637075e794c202e38ccd32f52e7ff1c356a7fe83d83f69521882f40a5dd4b996f9aec42e12582c1f9c159d62fe73e0ecea5c8f2825cd18809
68	1	20	\\xae272f2f8df59b2d83445001a94d684a9af5932d60737e7f31fb1f481e3f6790a0503d90ac943493f56d112f55c314aef2ea42bdcdb16cf99308da9145e75a0c
69	1	196	\\x102ae48354f79d4a0711a0670938c8ebdc81f01a237e0140eef3c1d7ece1f0a844f534962b29f596c45314d5025769c5bb6c6b54a0817aed922061b13ee2c601
70	1	203	\\xc53ae7678ea3d6155ed75885bd7f91eb02b885f8fcfbb57141e1afcaec48a9ff2eb0f220e4f7a0a10f23f08514f1bfb7715e3562ec7ba3fbc2597fd6c114c502
71	1	221	\\xfd7d8bc89f222d967399dfcbd8dc4a34c77ceb391c2681cc168d9c5496c8473e0a9f8b01f5351c6b3e4b97fe39796a0d66003feb787f14d20984d6caac620704
72	1	262	\\xcc7b8ad0e7f09a1a5dac18c42e3b092d94bd2dc99bb1381f44727d451aadeac3be8ceb44d61ccf8652744680e8478569bc6bf46a5f64db95bb02e6bcd2b4730e
73	1	200	\\x3c4ea854aa0706c0f1353a009c42d3939b7d2dbb107f3ec43e195b2611349b673c6bd1d4de984d78f87c0175853310f459fa6d4df741a0da018345ccadad7c0a
74	1	270	\\x8940bd24045c81b8cdece19a5b968a25821121f6374d02eef654fa1367d65d24576a719d2f41ce007f80589b3987a4c963e96b2d1d7499546126a6f6c1f4fd03
75	1	95	\\x204615b8edec1551967086c6081fff94691f54738ec7fd0b5fdcccbf2b6c8151a8765c339ab59012d7c68380ea52f9a861a4980c4fd3d8b006f24cc532e2f104
76	1	298	\\x3d1c8fb27200bf2b1baad7fc7fd406d0de8c5be4881231620a3587ae0ffb511d6d576ca30485115fea4ab9d56306fc520c3a6a69cf0a7e00714328d00611f909
77	1	401	\\xb13931d35fadd53cb5d3a5fd78ff9c88225f20b1022034fcab4547a3aed5b33fb61a98ab8f471e5ada0a442631452ae8016b491f4adb8c52aa7fb84506aac506
78	1	417	\\xcb4c3915b0d492834742c78b57a5ea3f8c3b94169548b80693367ed2f2be147b8c3aa4b39fbec8d95d5b0fde64f73a23e086f551c4f2a41b6847da7a1901d10e
79	1	423	\\xab3d8611a29162e2502f5e7315ba0b960a62a0ea06cc7cb6e4a7075bf8958e448384470a415ad88e29b1333df2d2b491cb02bd2ec780912eee0fa01bc230e009
80	1	7	\\x6bdf3955f6f8050d64eed2de847878440c667b478accfda9c2ce089e2748cd11a44895ddef41d8769b518f0644376f3538328c87f37a711431a1aefd8ee6b309
81	1	381	\\xc4f470904cf65c364d73812bbab114080de82aa0a1bcbf22e4a4f124a91ef5bb1a367cff8d5beb6c5cc92b98be1c3cd6b04ee09c13ff8c3cc3d032d9fae61c0b
82	1	259	\\xd781a4db470e5cd4591aed5beb3b9127fa4239c29bd7baa6610ee486aa51ad88a56f11c9c53502425ddd60265f5a62471a361fdf4cb2234bf1f20d06a28c390d
83	1	18	\\x367ce871719bcccb4b23eee679fc4d413d42330c6249a72428a2f8d204d45d60199ac726c212b92d726f859222efd2d2fd896b775bb65a7d19a9fd3951d97d07
84	1	28	\\x25e753c04a4261de0da2b780c64bb12198781c4235029ded162fbe4756dde12ef40e2bd63a1ab4d74266dba243f7a7e130dfa3be551c2840793b52a59eb5ab0a
85	1	105	\\x983dc501f9b1db845018c87285588733aa829df37815bf3b7b1200aa153ad99609b190175f2d165fc5a76819e8abd63ceffa598c09fc374fe4a254d1d2d9fa05
86	1	311	\\xefc12d89021c0c5a850355eb735abf8cba84aab9ef7158c08c60219644bc16505c257cb1168e0d30e92f24eab94a588b25c472f03b7a68ce8b39c1597bc3cc0a
87	1	205	\\xcb6c5b6d0d7d7199440c8bdcd930f277c8ea6ccad3d29333588c496f0ce6fa5f5854738307f970ec663be67f70c1ec3e1f53dc69f6a070e4f37524fe7f5d2e05
88	1	275	\\x73f21728aa4f49c0084f21709e8f61060e05d2159575e14f3e4c87741728c2d8c127b54b5591cdc9c6935069e765ea6a5dd000c30b69ef28e61ff017c7b08b0b
89	1	13	\\x8b0a99cacd7842beede1f57a9eea33789185c6ab25d206c842a89245f07d6ebf5b3b7c825a850aa149edbacb28f6f5e8860e2c340d131e422321fc2f53cd6f0b
90	1	218	\\x219d8c9faf9b3dc3cdace6265d2cd87d251d8f38ba0b8455da98ae740e301b47991f77706e3714d17ee8847d2586a764a2663b1bdc3a81524b6e0ed0487bc903
91	1	239	\\xdbdef0f092ce0612d274700fe3cb248b1a76c0b2f918438ccc765da51812e10e83205dd9a238c8e016a864a85923ef96c24e3ad9e5d44940eedf4944200b0a01
92	1	378	\\xb0ca7b5ca26dd8aa55d4af654f0ff55c5d0831810a8b8a79b7be5ca7275b959d97156bdd7176a6db64563c0e00ee3920457946e789db2b1684a8156186f20902
93	1	399	\\x6e6e2c76bd7ce46092296d62d317b1527d7d578e5a47053d37c67c3e1f32b441c0634362babc1fcbf1cacf1c49773bdcf71423e2b45d94937564d32e3a071805
94	1	151	\\xd0e9d6cb2e5cb070a9c020ec95d27b832e2156ff44149f1d9dfbdf0445136e7172a69e4a998cc14d147130b19b584038015489b4c3060c03ac34551176750407
95	1	373	\\x7410d1f64106aa2ddd1e3ab755705d287b62adf905b8d9d303c9147dc47a589c43387397767d71693dd46f133bc55cfec31f492c738e2585f0093d969fce0100
96	1	230	\\x9c1ba772f95f31042bc1261fe4031e7651bea02186a5d30588adaa88fca51c3db3d67311106e90567dc9ff79da7578527e35d069d1ea599cc30edffa2352ac02
97	1	394	\\xe9700af05ca116669c41a48eb80605db5320ee1b42edf521b937ca5ed406eca76793dad71a9deb324b5e99ca710b7fa9e4fd06697c965ce3584076f279edba0a
98	1	382	\\x57a78b2424f4b6c1283017eb20f5f94cc8416b446802241ed357a803cb8f96d6f8feb87ee68b8f340821d5574122a2d3748f7531d54d6ef911f9bf98c949880e
99	1	343	\\xca0dec791b4db5fa9eb7a629389f1af4f4dfd735e0ba108c8837f809b88c30ea2e31d5d4cb6254b5450f44ab384fbc4078615a6eef7dfb3f8b7f99b594ae100e
100	1	363	\\xa29bc4c27b3a16bf9d3d9654a15cfa29ab2f420ae3352462678fcbd587876487e0722ec5cf8e154cf8bc28665566c7be0a9886a8caccef6266e3f40b18ff7a00
101	1	335	\\x7a2aeffa6518db55f305988bc1cadfddb47e845be2ba17a06f59d16424d667ba5b8b724fed06c77c5ad4a5389e555f8d3bcaa520c5ce72bce9a186b168e18304
102	1	152	\\xfdf31417d21fb9e50206fceb69b53e868e1f06e3316d8170dd2b609d084558cfa7a6ac7cc636d9c31148424d36fa3304b64e4e078123c09065e7d04a23e61d0f
103	1	15	\\xc842da515f0610560aaadc2333e86ba3ef1d0d799383f531c00485b6590ed61e2899786efe2b2cf60ca4accd4682eb5bba262e18a554fcaffe3d098edac7b004
104	1	323	\\x7f4fbbd29cbb3c211fbbb84a8ca3ac6fe74f490569a2d8691d25e0021908bc66d5df20addd3c9cc00f15f304bf4ae9af3a55c4dd32d7622f11f3d230cb42d304
105	1	58	\\xa5baa5f71c700c90975b35b215a9d507044cdcb4631269e73d1acce867fb11c0dc2fda80ca209b302c6258166f65bba081a4ce3d4e6617387a99ae27803d8409
106	1	26	\\x9e0c83ed465ca8d7f7380e3fb0c0d36415dd09691f926bf7a603e0c007fe497bc7e9b282ce91a122555030756047920d454e228204d2f471f94d6b40ed8bf907
107	1	133	\\x6fa2cdb304a4b9a3c8e14495109c6bb9534e7c6fa7e0056a72251894436fe4a94fad6c9f4119ddd71f1c8acdb20e7090b8de955e86a763179c79e46c974a3102
108	1	186	\\x362dfb321fbcceb099eed4f16078f84908abb301dc5c290f144b7783b3d99630730c76f812ae29d01cbd431de5dce3b30d2fee4e7f5da8f09576160c52f09604
109	1	347	\\x4684138ab6caa57bfba838183a89f4060bb1e017430bd2597f527de11956b5804e626b754b05a5ab91af96bc96f83fb222d25d9dda0425f72e9d9378be4fa306
110	1	193	\\xfe53781ec51838b00bec0893f6bcb074b9b65f79ea20a8ae57c6dafc62f340273a1810f77e62fd5998f61165fe626a13f704e63e9be565d321582184a2c2df0e
111	1	351	\\x92ffedf542ef13d47d933fec344840b5b0d073b837a1228ea1ea9b998ebe93c6e9973fcf3dc61352d593fbd43ec2d8b2f1504246ed1a916b8e3804595119b106
112	1	167	\\x9d46b04921df9a3c59d522449b102a8e9869ab4279a2476f8e789bde1bcd4fd311b0e1e2c5ee21f45ac802e1677a9e9aa5772ee39e22dcbdf99eac94b1eb7b00
113	1	55	\\x9acb981fd75338bc53f36390084897539085b3b18e420bc280c7a752f2abb4d10197b0a2af85b0ec3dce8fe45678933f2d29f30d6e81c29420d39392dbdfe60b
114	1	210	\\xb46d67682ff725dbbfb61d412e88b87f799085845b16b9af7a5b4331c7d92b577bb74b3144e9e5ebaf7e3974b2efd8eff094aac19cd33ca022d80dfc900b0007
115	1	11	\\xba7d0535465b0ce5ddc2e3c046358e0ac6ee9ca83e21df08908aec10394aa0bdcabb848aea8432f6058d78cf0c70594609f0e3e2ac9303da9f11d81f17e6240f
116	1	315	\\xc35eccf31a2c2ba7dfbadba40d8e5d70b5e2873f6665b73a59247080bf7595c0212d286de16324907dd239b839cb1a897b13cb9d22355faca62d623fa3a96d03
117	1	155	\\x2bdfd8af0346aa3ec5ed25c4bd8d7e5026a80182419d0e98aaa2318a6b445c7c608004b85c040f1f8204a75476452facc8c46b71b296fd85b3a63fac09e1930d
118	1	158	\\xbc45bd545205c1c62af5e137168a46b6a0e46f5b8217489e7022ac95f719c11da24dfbdeae8049beaf313596a94c5f811c0f82b0f260da27bbcb9d3d6a91a20e
119	1	116	\\x275266fb3d94d8c4cf4ef84e5d5eef4b6a9c8b6885c9d7f8d4f92a214b416a09477dfb2e55d3dc6c19802f4a47a21546f670e2aaab341e628fa8e75267a76303
120	1	285	\\x3ae29942eacf6d8e1451cfbede290fa4c260732e4181a7be361f8f12d327b923e57604c36bedab6cbbc2eae0f6bc9ab941b7a6b1773d7f310a72ee22aedf8801
121	1	118	\\x94ef84f8a0f00370f25f7a49b6415644d6d4712c02f7b339b8ea639150d1771b5cbadc2be81a21d2c5480c94212b8048ec4c0d59a93c7969a59d639d6f5e5b0e
122	1	396	\\x482f181ede6b64766ba8b6214181c0e3df912f4efd06f778c283a200a4f92c45f43d0b5799978e3628453696cea62ed942e271ec64fa22afd202ce9ea997860d
123	1	398	\\x0d302191451e6714b960cef88c2e2384066fac81ca0339f5eb10172c98a05a05f79f79983d28d33b8049fe93d7a2ee4ab2c334d4a5dd2b643cf0ee89dcb7fb05
124	1	253	\\x8b2ae3143347f83c701ec3255ba42d104e76c02af0375d698769dc1f5c2664b6a0d0ed50711bd21e46776e7435bbc43127398ea2274b9f07f9a07d584456df0f
125	1	132	\\x351720735e8947ab1925a70e425fbd26ff14ce7fde87d49420c5d2aa5ea0ababe301982fc49f750a94d5639fd58992afec53c1f7b6f67eab236034acae70cb0f
126	1	202	\\x0598dee7dff69eeefc74da9d76843406651e240f0dfd6af645916a7926ac308a5ba22a2134f717182bb513e87827740a0fbdcc2955691d95aa8fb56f3b86500b
127	1	216	\\x390ff49a1e1cf8efa0074497ddfddbc0f0c8f036a791aad6351d2f8a93530077c587a159918aa8d569a6024634449f652ba594ae286977a6b8e9f44ef028de09
128	1	22	\\xba8de7afa082e359334689d478e6bdffc79242fed09248a81fa7c2c13280e52e76bda3066900500d13f762ab5a64229d27135677ba4529609ed241a4090e3e09
129	1	316	\\x88be5c19f302827a63085659c40ac1d61ca00987967d5c0bc4e97c880cfb690bb99b7fa90c3dbbe276fa71b3417ac8a753fdd3eedc6d19cfa9ed464c6566e20a
130	1	107	\\xb4bc3582f4956e3c6f4cb0d9785c8fa83f8e3ddfc0f475f03ed9f8a940a6962d62041061949f7da96451d49a898456d02a31dbed6827dce789422b2be9b0b404
131	1	266	\\x5ade64a1eead9ccf22bb728f39b36d1736d61de2f685ea4f36b1cc54cdccd44621954288fb35ad728c6d15e8da155e5e4d7c629d382f7d4bf9b905e32160c10f
132	1	287	\\x16c156918abc50ec2f906f28856287b49f326172c4e8d99ed45de35838bad60686846853da29a09ec84baeca696266fcfd0741ce936666554b85cc8ed994ce06
133	1	45	\\xa928f192bdfc47610d415fe461501efbfa6d7adf3110cccb40dd542f35c4ac042769e57d0b80a7eaad0023df2d0ce6bca4c61e3605f9c4c337ec160cf2ab1f02
134	1	99	\\xbab61e2868e0cb7b5d367a05725689b8d3e0cdadc7560b96f0b38905e7d0b5dec2afe84c8861e7516888180a4950af2b5bd80bf9561b0c9a7b8858ca90d2130f
135	1	182	\\xb2d964ae8feeb92be1152d67f0bb7911dcc3ca4b41e7e3f9ca459addcfdd2fcbb865ef7ad1252976e1df8af2361b95bc7f8207e0ffb31b6fa82e5d41f0d7c706
136	1	422	\\xbf71eee54fac8d1cac4ef5e8391b669a5d6a86b1bb3d38abfc50045bcc6ab46826d651b8570864b4c77c09280ef8905ac07ed3c688dea541af12742276682401
137	1	224	\\x7c1bff5b64ae2d79d5d0af80afe6001a5ea6f25d00839faa5314bb826e3c30b0909fbfd7c31c170479c1d0f373bb3d44f0cc1a37d46cf3b7eb3465b74ed24003
138	1	409	\\x67dcf271d0706722a02fad43f88dc964c60b35ac39d8c2af0e7d1510cfe349de72b8039cc743f9d53620b0e4353198b50ba47bb7185f2bd1922a9d7fe1532104
139	1	48	\\x0897ab58a32495747e34a8cab37498d37972f13184c2b66e7ac8c29df8f8dedc1223c9c479aad71319e71791913e57d1f9266a17da319ab15b49c7392ed3a10b
140	1	334	\\x118afc758a0c54af2653eca01692ac76cafa5cacc60ad444df3d4bb3cacfcd6b89603e079e01e25f614fe67b2defba39b362c64c2434d4334244dd57097a8b06
141	1	267	\\x603070d90a602b479c3e7952cdc33595987403da587d2acc35924f5e662a8fe3f180072c0974ab2b0264fd78fa98a91ca4c3c69f2daa0a70bcff4b970ec25f09
142	1	108	\\xb87a6586fb2e80c44d01ee84c3c1e6763863a64c4302b6cc637486d18ac08c15c0476e26db106d32f3e99b4a0385b226f07b166307d857734dcc9f10b75f1f07
143	1	37	\\x9272d3b6c6bf3d4177d9bbc87837ff9fe8f72db60dce97cb9835c7592b70441456491b309222209ff8bae867243d31b5311a495c4d80cdcf3323e4f2b5da6b0d
144	1	288	\\x421978691f5db0e7aa19f67d2bb0f37d061ad708dd08a3f91403da76ca4be3c412b07de164b3dde4511766a150db924c1242e426640e19d239f49631b8f0fc0c
145	1	16	\\x1dd97336ea5bc25c6e7ee924dfa5814ba347e70b94de11681ecf441dc8f6f8b3d296d7ad5efd473d9d8f3bfc067efe46c7f74643e5b26ed325b5ccce05203d06
146	1	207	\\x19dcb3c7ede94f69d650d733dc93a52f24bc7c4e4dc2b18b660e0495136e3844a898707cb02e0dc20d73a5526e2c003bd207ef9bbb34fc0f5011fe5c0500dd0d
147	1	356	\\xa3e27e946fa9c1bfa4b0cb963651fdbac4e32d736168946578038180eb6f15747b593d8b0b4fdfda81734b47353b4021ef4afdad867634e028011983ab36a70e
148	1	299	\\x99e45a124e0524d60c8d7f3a274edaffb9196b6232cc9611b2c2447d5aea2c651fd37606f6cecd4dd4915d9b31d8b4c7963fa0400b92d7e07d01a2d88fb49e0e
149	1	178	\\x6923f3f30299922897f722a4f8368b9f8faa23386886888e1f63909870028b40782af42469e603e71b8033f670a7d5251b633dffc4df07eafe3cace10f18ea04
150	1	173	\\xd88a4495e2b3387366c1a4ff3ee8e248c2855793f70ab34c2fee83522241230f585cd68eea5e37330dba9fd5343aa029ab30c4626bb06f9bb775279d008e9201
151	1	380	\\x67c050ee64db75bb282f975e679d99e82c53b6f5d4e17cd71e0e90d90d3e20cc2a52642da85f2b03e465dcdc3616ba64c510b58b1ebbe7fa2758145b08777004
152	1	367	\\x8eecc72e4d5805f5dcde98c54ff89a703c1fdfdd9c2e1225c4ba2bd36c5d768c462cfe08992cbbfee5b5b63f48dcfbfe178b8fd0e0ce8d9596a9b51469359806
153	1	78	\\xfee3c3bb1d748ab0ca0c66c43b5381cf137f39c714d56f4696e4a5a13f2fc9ccfd740088fb0739dce6ca7dacd3ada54e5a1d242445d136aeaef38cd7d060e102
154	1	329	\\x1116899a33784effec7e3566f245961e61d1acfbe6a3eea4bad82405c80941f23f45e474c328d69ad2bbcc3622fa544944dc05ea05f0e6ee05b7cb5f1a6bd70c
155	1	404	\\x9a7935c1e3b0433fdde3db3a9c4b26fed97f3537f1e2f20d23cff821d33847a2f0a8500b2986cb720b4dbe21dfef558ede79821369cc9abb3975eb5414e6c906
156	1	127	\\xab4067e8bd08ff6835ceffbafe1e476460a7269f87432a6e6b62161c1f8411a888a68d8b4776e66743484d6b5f6cca3f0eb7ea00993dbbe7c64710e4c9ce8f00
157	1	14	\\x3ba3e4a0bf6981b00462969073f73be39d8cb3193a2bb6f68da3bcf77da83d4d64f661215787b6a5f9fe3555a4fb5f868864bada1209cd28de50acdb2f655702
158	1	309	\\x67e2cf3d747e018a1e9e3e9fd50ee2b3457b90aed0455e334e325dfc1d47175a51afadf233e6859225a7ffd27bd89c6fd36ede100c523180f56cf6e3ce9ea80e
159	1	52	\\xf1f3d75d7376f45d8963abd71a1fe4674e0797b9c1385c625684a756a170d627d5bc7962e61a30d9d8863a1dfb80d2b96aa9fac5b946db901e42b7eed4b3490c
160	1	54	\\xdb503f2f8cce2d14bc4d013f054abbbb84bc646ba07f1fd33c9446fa23f868cd43539801544251d691706b9c6f730c73f6b84c113ee0b6abf057711ce0258e04
161	1	238	\\x60e121ad105ec5c48e714473fefea745d398df7f440a4a0b406dec49767896cb89e0804d781d2e2e32eddc29f0388f3a79e21d22c709bc9c16cad45ba2e0cd0b
162	1	372	\\x882b72b6cef3cfbfbcd8ed9e55cc3fa1dc8cf416d90905eb3fef582b6166058b41e968ec8f3ba3f35b417f4b959c631dde54be5135f50c871a5b69daf2db890c
163	1	326	\\x5d5f6e230ace292e01d645956531f84a0b8680cd84dd5f26a5fb678d9328f28428627f307356f632429dfa7ccdc0066c628cd39b861b7d71cae0ec9e10700c04
164	1	284	\\xa785c43dae9e1b4b5e7d0afd9d83f92257028cd2aab2cde65283e8b3f5a08b51d2ca7c5aee9408d4f75676b6cff2b35793e9f0936cd1bf6c1868834fd224c109
165	1	61	\\xa9a6de95144ce046f50ee11b879ac42763f4998da33793725f77efc50add45749086df735364d699ee64d6d80d6d1a0329a1d9b5778f8dae6eb8d56d5ab7d80c
166	1	332	\\x3d2414d269f98ed7c1c6224751cd588ebfd66719224c8ee385f83fa010fb370ff00cbdc035751170e72f2f792cd6fd9d9a9e07e4a1ac277ffdf17a894ec7020d
167	1	49	\\xff2659eccb306a322ded9010e1b237bfd87d005b00132f85af9f176f744c6779463e4d0039f2df0d1e9472ac5f0e1ae22cf90d5a0ff432f2ec44fff3736beb07
168	1	257	\\xeb46d5c8271c4a3b5a54965578ebf3a787da657e22dee88d00e0e144f23ec76c1e31edc5be61c7a662c970eb787729f1756a386c495888e59a9bceeb789c9a0f
169	1	312	\\x8b8c6044abfd8eca13c30e890b677fa2617f39abb85036b3192959fe3135db127364ed3ec35b8db52b1ddc655a8e3218800c805d4688c82192d8aab3c41c6f00
170	1	92	\\xaafb536e990e9708db72917e6aa84ab91838a48bbcb6ba3cf0a51be8f8969d82c1dc460096cfa5ab4d860037510faea742660724c7d8d2fc8d27ef36c01b8c0c
171	1	339	\\x0b65cdc713ef095926577c38c44c50cc93cd9b44ccc8a772522c8cac3a067ed8f0519442e8fd9de896b07e555ee25a6fca40aef6bc6d7c33db800efeaa576505
172	1	360	\\x9337159347c63897efcff57c6f56fdb719f2d9779e490fe606b6810c18bd0d94ebe2c46d59b60a1a14ab0cad4aba390e7f779a9b8dbd15d2353e90f336cc2f02
173	1	172	\\x05bb7de3bf079f8e63d4c0b9dcb9260fd79373ba8a3b1cd5dba343800b2aec29e08769154371dfed9d5ce7f42e061ecd7610100588ea97ece4e446448b622503
174	1	148	\\x47d11ea1a8f765f6d351da93e5e059b66e7fafca0ae4e6796694d314b31b9f3ff44340a6a3ed95179cf845136bab7def8daf1675e8a042dbe4b989390947ea09
175	1	82	\\xb3d23511f1a569be4d279911b8a0dc109a335570a792abeb3589a933644b496096071cb7c461036c62253897778e15ea6223c5b48eec18227e6120ebc7c44207
176	1	169	\\x0a6277b4a9a62dfe5207df455c929719e3386a0e54665fc1de90bf9459a6d47e7dd7a23e013dffb8263fad02f5b519d2c7cfe8c1e2e29b8a4058a8f23933cf0a
177	1	76	\\xc99e6b5620fd8485e36b792fd72b5a28085969e49ed436ef747dd5783eee599af1c81b579750d3777d34ef09f320658c2b8366ab59d21e15712c4ee2e17d0704
178	1	223	\\xad4cf9ad7f52fa2257de5aa75474e56c2f2e66ae4fd92d77a10cdcb2b20657ec443bb8094f7ee1b0d1cfb75788bb88bf1fa999ca86471e7d7c3fafa8d65a130f
179	1	217	\\x2bd40fbe3f23505d7482519d4683cbffc6dc6d473a44eed439b321180edbcfc1aaae709bed340bd6d6f09f7dd2f6ee33eb8e55238bfd531d3eb2de5dfaa99109
180	1	174	\\x9ff8872a1b4cbcdc6952fbc3edd0d8ea1be12595b4c17a8454f0a32ffea64a69a0df45e6ed7abd25833baddb4840d7bc8e0d5d9387379d1d45f6f39d69f76009
181	1	4	\\xf80ee1e0e5f509b73658b4df55a0d117e8392bbf7382073fc6df4f5eaddc11e56855f91ef928c0eeab3bd3616dac28b11d82453dd7fbda407580b1134041ba0f
182	1	112	\\xbdab5aa212f6429fc083c1cd662db5953720e6a0856a0d583fc1125c332c3e37ff520fb561eeff53a706abd7f3f5cef2ce23d975fb1cbc9eef7eb28d10d2e203
183	1	318	\\x0f930735a8d8fbb312cfe0717997b3363a6f9a4ffd882608017f34bd8f67cdaa28ab705ddc5a2321125405b76c95b359174445ee9469e11c5445b3932d640c01
184	1	264	\\xaec8af12e21973d56952b4b4fe573d6f56b0e4de75072d8ed1920dd07638874f35f352dc8646f9a1fee1727c7465f99796ede9063f821b27a5191d495bbf680e
185	1	101	\\x67bde5cfd8f9c9cfd611b73cfe7b919d0080d5cabadbcb94444b2e87d1ac441a936f15d7f3fdc57e432532a330e4536948ceae8714ee09a41069c06edeecc802
186	1	96	\\x8823c825e376aabf19e9029462a9bef4479d31d08c8b805def9b6e23bf9ed16ff306f63fd1dda3806e27b0a73562f345899e3f64c64d30fa4fa518564e014702
187	1	212	\\x992b8d53c8efac293eb92802066d7940725305cc2965e5ee3bebd3d3c582215e81da7714d2965500f60df1a083e2fe36ecfe5a2fe19ce6c898c2569ecd99010a
188	1	211	\\x1bf68d4df2ce71d180f871f7015318688cea809efb9f510165b0b2d426f4bfe4892e9bc0b6090f43b04ea01158c204c173487da1f3cba606409eb482ba372a07
189	1	277	\\x47fe18d663cd3ebc44fd6d3a44569fe2730874d925cb3a887f12daeae4daed37db1c8e6cca5d0c2bf0889ca068a0ce9d684e6e598f3177a5fce8965bacba7a0d
190	1	353	\\xbf0b991b60dc1a833a8a474cd337d58ff7bc7130239d0b5773c668f87e1e2910f9fd626a61f4cb7f499a0a365c11de639c0732944328c985ce1a9e9638809a07
191	1	308	\\xaa6bde9c62c1c939b957fd39ca6325146087d9a810b69f2adcd6a72cecba551da5f88da4189b7194199a1904cf7af35b5615e86385cd640782a4d681bdedd10f
192	1	341	\\x552f33d33d5bcee498921e311e66294bc3aaa394535e85268f06e39575cf3fd07fc3f54478d13f24037af2af2ee4932ba96b67c11af7c990f8e7aa760c0f9c0e
193	1	187	\\xa12bdd525a00e7a7d256683fe4c0ed1939b57789ac2faebbddefd5d9994611ed7cae84a7b8bc4f71a21c4f3edf58361aab1730f8e014c3a47bbe4c8a256bd40d
194	1	75	\\xe0963a51a44cb707661d6def06c839f33d1be129104e487e5b405174e5824413585cfb987aa4f6b9d8c5d8564551d451cade910f848344b1a2a6d5a58298b408
195	1	410	\\xcf7b73afbd804ee53a136e6e5ab506d4ab087fd8284695ddcfde4cf9ff4d04365e75f000b4aed3443a8d213a151e25e4bf005363b0be30da94c06392b12b6e0b
196	1	150	\\xf9e17e9ad22a373be0a0842be93d4af09b73f91fa15af6eb6b21982ed6e73a2adc6dc2966b5036830e2d958cecdaade861d976dab143b03ae4019184db341401
197	1	136	\\xf9bba003e528c9801e110ed15f32e8f0d971bc42d9d4953e210cfa37f0c85720296efe37b5a96f6c01263e8abe7a6d232612f228adb2457d3dc305153fdddc0b
198	1	265	\\x1c7e7b8d10b7d5439fca94147ed897ed89108d637001ddd74b339e2f965d1bc579c7cb8974f2c8282167e643948b6331fe6fc76e3324e1984ac23f78d3a57407
199	1	336	\\x952f353932a822ecadfa3558610f5c711868045b4ef651021995bbaac58a3e53aac4aa65ab709e394b69676ddb8caff39ec3f29871f6e49132194e32e3bcb003
200	1	198	\\xb5dcadab72c46a8bd5bae8b5a9c15b3d562947978d3d808ad210299159d634a26fd46ed8e3d5e15cee1e50d08d51fc701ddf42dadb68022504f181c0210b1e09
201	1	361	\\x662778d852f1f1a4a938a5c15b4751d4913f6bddf5fde4eefa137e05203e60748f86ad5bc10a5a891bba3e7b2128a33f5f45c8fe0e54d29ad0977c56610a510a
202	1	313	\\x52e2c7915576c2df0680647fb0b533cb03e081fc6ed3d5f27825ccc52026ededde569008ee9d82f74933229798fec32ddc09707683579b6627b693209810df00
203	1	368	\\x0d9137e2e34ef8fe68ef312ffa5172fab0ebf0bfee8f320f7a3e61fbf20a3dd6497531ffa1c7b5c014a9c9e2774883a835c314c2141b920aea8b8b3a1bca970f
204	1	268	\\x230c6062dcc04f8fa9867f78ce7c4ea24f87df227be020fe71866702643bc2d83b007b25fcdfb1eb9d1f0350e801cbb26baa8d2c2ead09cf4e8c116872d06604
205	1	408	\\x27513357b80588055edd9abfd6cc984866b04ff0f3ee958154d880f640ff844285d90143ad6bdd3d28917cd4fcb5463d2dc1af10fc8906ece5a374a897478606
206	1	387	\\x30ab722fe91b4cbbf7a24a95b8ee7d214ba6a34d1db79fd49081e3762fee267d893a01adc8ff88920c3e32a673830d3429cced5fcaa826621c6f16f85de60b06
207	1	46	\\x0c7506c7da071dfaa062d955fc9fc62b401f8a836a4617703851610c4f56aeea80c497a6ac38cda03883cd7e2742edf0550b30264c26b8b654a4496f27491009
208	1	421	\\xac42affa6b6853d799aad2a3c0a0d2f6456f5c2380cb5f949df44e6559003356cfa18e6d2b50c5be5759fc458582502cc4bfec6e3f615f91f74e78057e0f7508
209	1	60	\\x48c95b561c79c88d4a5ff49498936c6638fe8a00fd95a97c4c69365e258c7dff8c4dce79106958e46ccd006532fc0d1ea59921356bea6f822340a24bbeb0cb05
210	1	254	\\x793a563e66cc36af9c8195165b477b794abf012c7f5ba7112d4ad831bf1b473f3c27e853ce316f5f1574b952bae733e42253e67f87721599a332c4bb2d553707
211	1	304	\\x27eac405d63e5697c8e6475a25686f48741e5351aca81427158cfb8350bb276a2ff11b10f25d3c3ea254958b95da62f8a5f98cb2c12aa98ac84312b6fea9e207
212	1	120	\\x39570e266e043ccb8fb3f23fbde377c27a49e9322c78f8dc6c24d01fdbb48f5d6999ed9d1b393e9e6ad62364b68c88b3dfdf0dc46407f0369e38af9ac9181c05
213	1	209	\\x89bdc014ee5ac38112995f30058f470e2d394a7d0990c2226b6cbf30da8d8dd83d591fc9a613d5f7e5653563574977c46f554a5f98f95290a814bd3b37a9ff0e
214	1	235	\\xf785a391b496c9ea5eab22d424c437a9e7aa693f2f9e6aa86a3c0f4a2f8b4d8e80a1387e5cfc5c5b1250614d01b772a458135ee88e8288c941cfd1e15ccf2308
215	1	383	\\x051952fdd325b6bdd06f020b904f6ef9e3e9ff1777cbc183d2b54ba352bdc704ae322f2f93e21b8476ab48ae5344fbce3d350b0faffc3a2247d34d9f3a40da0c
216	1	388	\\x1699b47e5a6d636ab78a8b39c88953d5b2256bda2d547865a34d267f4b2f71cf5bce2cf28db55544003cab525a7acc059f06a4070513bf1326c89af7cd81df08
217	1	295	\\x0000835d424342118dd796f25b4f5801771a4331cd88e2bff7aa0e29e861b2b7db1c4c11a9064b2b7bbf4ccc549a8e26a3550627fd572de7baa8715881bf1a0d
218	1	35	\\x9026c8ebf7781ff809a4cb9bd52d63d52ba8c08a17bc237fdd287ccba137a0c0db10d9089dc2b3fca8ff663090d13db99ed3ddb4f8c8a979252d02c9f922370e
219	1	415	\\xf2254cf98d15e478de544aef983455501046d59ffca7c1dbb60e2eab2815d0b8eb8b682e9dad638eba328749c652752a9fa3cf415b894993f444d209b388b302
220	1	33	\\x5bc494c927aa233144ebeaa5f09f46749cd39d8f0cdef8be9abf146edfaa4b25d96a2411fa8aac568de1f66d8f4f4c9b44f6e20e697faf27f4800783a6c54409
221	1	208	\\xf09b8561725ad4458d600519810041915772b54cec3ac09ecdf84c3480e75b19bb25676c74200eeac4b895dd6ad8e01cd52ac0f6e48251dd96b208d44a518b04
222	1	310	\\x2bc6be92c66d6d4b82f492458d4e3a564dfaaf7c6c0e784ba281ba608856ceaf381dfb738ae23724f50b49e58bb8ab01fc36d606ab704909f8b28cd0fae9e70b
223	1	327	\\x6bfaac24459ccfb1fcb663b9f876c6780e949b835e177c18b1ab5abf7cfe8c91e55c5e35b655da4e0e4630116febc821f9ecf502817fc4b14703a19c112b680d
224	1	3	\\xcbbca9032da27abab469e97417b2edc278db06f9fb34bc058c20a29989091283ec74bddb515e48df8b1d9ef3b25dae96156bd8d1dc006234a2d45f8cfbadfc0d
225	1	190	\\x1efc9e60e341ad142b732730d70905049fdde5e2a8ea2a5281a58fc0dc598717649290df2d7d131a108ba25fb4524138fcb117f357bec00130b71262a38cca07
226	1	168	\\x08062b8eccf9466658f1d9f852a64a0dc2a93f648da361531f63447d3acad822b0af4cc29dc50310cc264832941bdba69b17b718a723b7db850d8bd829cc910b
227	1	252	\\x82d9b4b4f2452cee62d5a3221d6d3c1e3ac876414d8cd85328fe396fd4b6cb9ce63dbd243a66ecc5b427c9f08ae637c40df478e33a2acc01436f5c74c0819a09
228	1	296	\\x14360e8405026d8d3d1992866c891381856b878d546b81eea8928893121af262dd0c9d54f1f8bb94ea1cd1db2e3ab5743de39eb3fc725e624c1e69981399980e
229	1	236	\\x565a8cb74786e5c133099cc916fa9cb5cf4e06228d1d371a6a29bced18d7fc63be5b4497f87c02adc9dc0f1d8d6a82802c9755af1021f755d512c2a42633af00
230	1	371	\\xd24b0d6d79e2e2d86d0d9d9419aa35952c1b690790a023b0f19fb7a51e5ac99375a587b0e2c5776734be39e73b89c4a0d409d314255e2099a7c9edade6da500c
231	1	36	\\xf04fb757f29ef75cd7365a95123e28f1e121a76788cc2247ad29bb32ad1aa85773ab927ff9a5968f501b884f6efb5d9c578c8135870c84593090f21722a8550b
232	1	192	\\x275072cd1641a4dc273d1de11873b450713e570433a30b08ba709ac0b7c6a27fcdc921ac056bc3c1329ca1d358eb14de722ba9e4c434d6901bcdd33ca65af408
233	1	219	\\xec8d265426e62184a2dd77aa719bb25e66e2ed72ee012bc071a8887ba7a557c6bcaed8c19aaaec3c8622118b579193176c6182eb4db8228eb273f30bba5f1f03
234	1	31	\\x4550b8e230b20da0c626775f10aa9439ecdd7855085272ca8e531d6f0e26cc371232e71e89a6122d7a9fd12f8dd4cf105bd4f51023a9ddae1795beb784cda906
235	1	69	\\xe401f5aebe48211e3efd4dec70e51927955861a68147dfeb998e9ae3cf3152a4c1474e2601025d456b143b31c21b0e264c0436446eb9e0456727c2d099510003
236	1	291	\\xbb8c873411f33ef3e996c7224565483657c546a5ebf1835db34a8d9ceae13f7d1d40dcb6549a22511d01c8ea2c8aeefeaaaa6b5722bdb406349a386280a29107
237	1	314	\\x3feedf2ba6bd0bce64d5a3f03d3ff6144d3d40dba6546461b9053b3e9cf282687c6ade069283f588f37ad9f70ce23a64fad8ccd7d2d2dd3f55d9163c3e213803
238	1	64	\\x4e2dd2adef3ae8bd723207f6d415a98c7ab631977ac10ed0ebb5e713d7bfdbdf8928b98906103326bbe1eef5febc9a0fcc0d773e9af626e244af0623292efe07
239	1	62	\\xc32510a8d5597f9b0101686e2d19c2daf6173403adaa33f6c592953a69c3d121d43133f9a214e72c59e6890860a3a939d6349789b544f99dd52720d04d128309
240	1	12	\\xa11a0930a806c24bb815a13accb3db6804e539ea9255a771286f12a401097212ed5c14f0c01062e5186d8deb33407fd59d72c5c2e68a40deffc21c507c53610a
241	1	5	\\x6b94d4057c8d44796eb91a772984e47e95ab0b20ddea72afe3f45e490d3658f1780ae7c5674318cb68d8fdc20de40e0b01ce71e714b6e659658778e2937a9905
242	1	251	\\x72603a573a02b9d5912c4b6a13afdf7758f6f51139d35010bf95cd6ac17f8310e6158ad03e4def871a34a23d1872bcd236f1878052bff7d128e7ecb3d223b60d
243	1	338	\\x744500ed4987cd73fbc60eac310a71c82618a9b14f0fa9a703eb1f4c15c3b5eb4d9b6015644082386f078ffc3021fc8183f5e97ecdf4b24bc5510f81ae211502
244	1	305	\\xc0f86fc409fa55704f172dff5be712c9be4d41bea23007e94c074552bc3d4e3680e2cdaa5fbb2ca423c31c5e8336a970217ece8b598ed47f4c144788feaeeb00
245	1	349	\\x3a433bd2e4c00e2fa5e682bb2ff370055db10f50edbbb230d09a276b31dcd9009a1b90b8591dc534c831c5e6d9d6b716d97fdf4ea4c46095bfa6f8e091c64e01
246	1	146	\\x5e614c2587844128b47ff5b85c8ccabfc3ffbb2846fb133d93bd01af068a106152eae1cfbc46b2dd52a58fb70b700fd8bd87551b8d4d867aaed5f5cc3c3e7f02
247	1	214	\\x9fe1ffc501881eb028a04cc66ea49f7d3ab57243626075fa1fb3730c357fee8e2642a39cd03e0569c0fadb09a4ef4dc208db24bf6820a654bf2d14136f5e3c06
248	1	153	\\x27b55f4c3a2738bac4d391ffde53a89e9c6ea451fc2eca01d8a40c89a7a67733704801fc1a43c0436fd51d4ef492675d6dff0ccfb18e79da48851a0d8d7f0906
249	1	83	\\xe98edc4d9bf47c73710d97b74cb746a010c2bb8b2a8b47478f9c1f502c079331c51f7499e8f0b8c5fe25d78c522295cd1ac9aa6170601b39a795440380a44003
250	1	306	\\x70720ed857a106eb01479e4ad5212bd6cb3123b05ef5f74220c67cdc5359597fae4646b0f721f61c669a222ea13d149c8ffbfddf07d0e4c0ea4466de503ead07
251	1	122	\\x65c65e125b556db72e1fa994988062fa6f5eade46c74af894d95e339908ce4dbc1f2f537e7affef1d20173557097b36e63a8feb1abe8f36ff9709b05ad55cd02
252	1	50	\\x1ec1241e7d4d66520043010c1809c31fbeb19d30516f36a422cbfee664dcbe596c32ce27113b3849c4e9c31d42b96dea24314088d061f25d2676a1b8faaa7106
253	1	222	\\x19ef470f1eff0a74385e85412b3bf05048ec1717b67bf8fc81fbde83bb5e8173f12f21dd5c976e42f6b7d431a000cd938e55e567adfd60b42d706f6d314a6500
254	1	104	\\xb7133a363d43cadff8d5fbb3b679a644d7040ca10b6e63e2399737ece42a45ddc224977275636796eab8d5036215c3359c6b693fa3e95f1b439c39761d0ff906
255	1	88	\\xfad91c60df33c8c741e4b9d982d9f3442d261368a42283d229ff6babf9b3d683ee02026ea78de81f409f20f83a04ab3c1ebabd42450c4d91a2e3336daadccf08
256	1	119	\\x6fc75d7a2d03b0e55f78fc07fe60c527f731e4f437f5001564f38e0d6a8761bdb52e9d74a766eca296f819f5247b35606ae7dd2ef8ad5f7bb4755b180d74c207
257	1	161	\\x957e3bc90b45f652363bdba4c6f10b3ae154674eb9b006ff1ef70ffc423d2966ff3a047181875ec185df3e4ed04fa86c39aed9abe1874aa89acb17749c240b00
258	1	328	\\xf4b6f97b006d38e28b55f0b35763b2914fe18b001160e97bac8ffc88f073001665bec661a4a20add2ecb1e90a4a30d7821e8693a605db0e01ee7d3fd929d5203
259	1	340	\\x0af9e1a9bc1123e9565bb981b9a4451032bd1a03708f1c8a7b90276715be8881341feb9228e4e311610e2ba21d210f60f19dac57025e0b48410a045b17fe260d
260	1	346	\\x75d0c7ebf47cb763b149b4e8330bd2c198a8c0920a3a8df4e75601e22e84de245eca814eb0e821fdeb6d70ce2f1e0d456d02d72896af3507ad0fd4c3fb3be502
261	1	292	\\x8e62a4e488f8202e9580e2c38ea22590e5cd43b0b5640e73f25fcc80256d6830c4da9b77534d5796ceba6cfd1b53372e94d6891b6897a081671ade94f5f56b0c
262	1	85	\\xf19cd5e7db5e31ca051923eeb98bd5108bde7d4237d5ea32bc567845e7c67482233af317352d756cc4c8862fa1bc855acf7bacfc9530c8c0871f9801cafcff02
263	1	324	\\xada00adbf43a320ab8505c8f3deae353d2abf0a0ba198b63555a0603e3cf83a56fd575624e5dbb6cbb781d306f796a4f29fcaff921543d905926647343d65d02
264	1	32	\\x8f9957ff19d7434811ff83bdf413fc1afc056a18318b3dcb0bf275cd7cc8af9b466c5daff709bbbf48f17688028421e95a4756f72a8165819d02bedbce3c9903
265	1	248	\\x21c2e5b086b43ca6ff5a896808980944190fd6434ed7dd1a8627410779d9866814e59d68f7015150af3fa58c8a2b2f56412c00bc11fabe43d6f642b819138500
266	1	414	\\x3a4efdcbc7785b1e889a0c1111dde1b0b985341cc55541df4ae041d53ec558422cb1b8a8800ba87effad72fec183616feeefc6a190aa4292ac6b3f39a1f18803
267	1	129	\\x7878caeb9e6d422530c03dca716609ea91a8646f3fb90cd825272d846cfeb8a462ede1241962a6ea400ba47100d03b0e9e384fe66d03ee48847cb916dd3d1401
268	1	81	\\x10a158dd368f5857a13326c4c54edeb6d3279c49ca437d72e2db42abd0e2e4e0a253ecd18bc71b5be3f7aa5fd6f5edf2b34074ca7570e9fc9bc405c52dbd860c
269	1	42	\\x4171b3600abbc77bcf81c28a81c7b70ce47db02f78e1dd6e73be8b5672e622b719294bebf4b0d3df90c314ef2926871f2cca4dd49c440b3dae24823233baaa03
270	1	177	\\x1222d34d995c480f6e3ef15fd04d14b8cd84b52ac0405fe6be92036aeaa588309c41a89d235c5c8233aebf3071098476429a8c7269dc4ca6d499570a5efb9d0b
271	1	93	\\x137580eec8403820b920325727e54bc7b7c7ecaf473f9b8bc37184ce6abb1dbf2fb0dc1097a2da5219a6afb8a319e11dc51dd44050d9b8951a972ab258c05703
272	1	70	\\x689095cdd7b67164b481b2ab6b91c5617e36e35983541697b4f0d9f2b0a281f6b9a76950945f0e7f52815cec36030e7dd7eb7a0071c985811d0e6c4e981ee504
273	1	276	\\x750ed1e23ff5bd198a921ed7c13d1062779343b1c7cd94fa6cfb04ab0c71e1f46bb059b49a7ee5b3f930131d7ba60e22a511c984bc42c50618a33f4c97744903
274	1	171	\\x7b45ab732df7401f6abdb00ef14144d384bc70077314001e91e4c4cbbd294fcc550984aa157714d45fe2acad913fb848c33ceec64c4a1441045077ef87b57d0a
275	1	403	\\xb3503b340fd81e034f0589c40a50d9f6c2f14aad763124740254c234fa8036d13430e585f170de67ccde41f85222877891afc508eafb22e6ca8dbf79110de90c
276	1	110	\\x7bc70fdc276994025c0026fb7eb9e7bd2b21f115873c8d80583a898bb7e148488efe756eb921a906e320c347de978a995de721c5968cafc6de22d84945f98503
277	1	369	\\x27e6104a808d3770f0518914e05310e801598fdf070301309cbaf9f9f8e02665030091c1f9eeae0e69ca01be0d33d112f84252e873c79d19405243cd1823b10a
278	1	86	\\x544cb9d31599fcfe6964b2d8628e8786ef3cc9c2ff27d0cd273b8f92cc40d09f4929ec666491029e035fc3e23eed215a72da33270cd5bcde75aec1973e07cd02
279	1	283	\\xf0d596aa2496345f1448d41c776d958898979794b462ee5818db384b5ec82fe57ba7eb48f591ed6db1704c3244140a47c431bd3a9edeaba6b151b1b9b8fcfc03
280	1	147	\\xeadd2b446e38b057a78a02dd76ad273508e4723f3ed638d77901d2582d2245905e9b4c468c5b72bba81d02ed754e4fbf0c820a9b4c764ceeabfd60e2fcec5301
281	1	344	\\x6b8b71ccab687b17395c4dff9487e28d3298c80ccc0b9eaaa49ac301083fc117e3720a3277e824f4fced80f1da5ed7d0b8c448fc3bc9abdeae2d17575d6e970f
282	1	165	\\xf6728352facc4592244f546f3011c433239e2067a90ff2005ce223512dc3d31025aba237364dea635f554f6c1e28eaa9fb4dce26f470b2d37c55d804f648000f
283	1	139	\\xf24465217e16dbb524df0776c5053d978647ac91cecb02f5f4a8ba9d3517fdc613e258aacc0992452dae5ea39a7e49fdcc84f59c79d0dccdec4a92a127e1c10f
284	1	156	\\x76e1104ccd428c4d0ae98470ae5e3c2f829a9268b30c60b27ded8d40dc1e4ea000eaa529013b7a97f111696f10fbb4e55afd30892c3d4f00669ae5c9672aa103
285	1	106	\\x28b6d64cd0d795beb1aea2b1d4f16d05a059ce1a9c419ecf71d40ad8b51477becaf7e79ba7115ed8ab257020bb415fbdcc59701553cc0f10bbe9804036bf2208
286	1	138	\\xfe18a34b7b930797b8a48ab19a74c730e1f4603d65b7dafdfa81a110e14daa80ef24ad6edfa5a9a710933bfcb5819275b8f9ad9cae29c56c9dd1ff4eabb78809
287	1	30	\\x9b981ca93fb915497da6a9ddf6e1e803ebb10e6d5b1252c7391d6548ec26fcadb7575de66e560c24ff04556f84d43881a00c95737cc49600508406e83d49a005
288	1	322	\\x456f0d29e6130168daa14402ddd7c10777b4877ef7dda6f5657b419e716a0799027db4f00231ae9181112c7026ace4bf75b796dfa0b0785fd5ad7835bfab2d0d
289	1	79	\\xd7984915f5fc1854f23e3342ffe1adcb39dea891475cac0d133eb89492c1e4bc0d91ac39c3be64acceb32aa654f5d01f90257a92a942b6fdea3dd62b275a5f08
290	1	358	\\x51853ca5e9362996b48b60e192716f61267bd41cc9d750392fe516672c0e347e087f4e440e426358c3b71d1a00c551f974f85d1c3cbf956471676361390bba06
291	1	53	\\xe5b7a07fa456222ea0acfa85bfcf271d2bf428137c7142b86bc4a415d564452d3c68f1ea94835a0f3a115fbf7ed1c2137c8155a581dc34f284b707b8d0e2f806
292	1	269	\\x442124944b526afb6b76295ef52bfd2a2343a3fc428164695afd3b24cfc20482a643e53b0876044e4b4ea0cb5d6efc7ff0a960ffa2ec12a7715c3c6a3de4dc01
293	1	352	\\x63cf067e2df82988c725b8e12a2f4fb5bf8782b5df516dc7b0cbc8f9f4525f60f66915d1c7c247ad5a07e9d54e3e20daadafcf0ac997eff7f3920bc81a5bdf06
294	1	100	\\xffb71c392d486bdc68e118e3d852a1c367a491b37130eeb43cce72075d932fe3559aec4e19ba43b1dcbb2de26fd7f4f4a93f5c09f16ccc9a9896b989f74f5409
295	1	377	\\xd4101926aafe064d1f7d4c1e7f23033b990ab0b6d2c66f65b4d3ba4ce18eb8aac3cd5891bea3511867a724990f3004dcb1f28aa15d7cdb0fc168140bdc4e6a05
296	1	281	\\xea19e458c8b6d4aa5e4686832729f58208ab9905a63a274db292c1a7241b8aff76e6839ddae5b874e952ff992a68ca88e7cb0657607d6defe6b4bb96f3846a0b
297	1	183	\\xbf98141ede06fe7c52d131599af67ebb2b1997dcd1ef8aa9d33e69877c85cd6479db806e940e2cc5bbc23ce3b81984613b2c93f99a9de29c1ee21f7e9dd6420a
298	1	84	\\x07af707113ea842c272f0b86814aae5bf25b7fcf011d557f3f5fb75be29ba73994e964a0ea75cebee6adfe0eae7dfefd129399ef22dcb4504eee9fe31e3fe80f
299	1	416	\\x12c0bd0301ad8be33e12ab139cf5893f7991f82ae75e18c15b309bb0afd989a6bc0c0d413264e62011c6b4787031cb1eb7ace57d730285fa68e7d064e0c45109
300	1	258	\\xcc0ac0be321c2d1112d42509880508f0ee86d0b5e41f3a29417e4823b7b55fa3ed80491989bd547ad8e131d1830fd19dbe462baf3f50fd77bfe984b31b12b408
301	1	227	\\x5b2a4729245a508c6ee61cc5efde2f1540a71f6024713d8daf2d9605b31434f23f4018508046bee35c943d468b4f31157e611178297336d8fc6128e5cc7e800d
302	1	392	\\x88eff9de0b46f273f030ee6a2c3016a8ba32c80f4085c58229e78811b2d6d6535e45d88b3896a54648425dfab96a6f9530819343e3b2556e5c3d56ce7f5b0208
303	1	321	\\x5144d2c80a01f80b2091d0a2c27c60e01423072e2fbe3ec92e2cc69fb49921781e825ad51eff184e5c20707a8c69c89796bedda5568908ffcd93f15b11f8f50c
304	1	386	\\xd4ee25003d147afd10ac8ee7ebda4e94e10e139e7b806aca4d0f1bcae5a9cd36c8df649f7994c8cae4ea5770f6a348336ec0b3d54e335a25e0cfbf7513a83e06
305	1	244	\\xc12210f22756718c34d329a5123e8e8da83642ab95e035f9e0e61ade35a289dafb2c13dc1914be06e3b07792c718a0fa08cc8b1a9f49e3ed46078a7560750b00
306	1	157	\\x431b8005009e313e6a1823e60bf9342bae0251a465e9ba32b215b2e011594b04a68405ee09673c6abed572c158a78bf32f13e6c9ade394a5a9745ee9d8627d0f
307	1	366	\\x8e7a74aad26ccb12c777e144be555311c27d39822da80f508f3b7b7f323b7e0cf9516611c8219b9e4003efabae7a10dfbb3c68a00ec830c57aae96d46ac44a02
308	1	307	\\xad7959781e797e13218e34734ebc2a9819cb7843a57e218d814293e92f75314422cee6e1ef63d7380ea41d7a1e8925ab9407ec33987e6907f7ac25c330cc6d03
309	1	345	\\x80ce6282f1c2a5cf4d7bfd3935fa0a9b5999d9c269867770f7b02a585da3297da58f2d3a45efcfe6fac79112984a0d75a4aa644951c2939821f663e223f3c501
310	1	41	\\x214d62b874c8b269cffbbac072afae678dd634e1770abcf7d149c747c673a899d29916ef8d831142125c1d13ec900ec40246210ac68ad62aa0dbc700e6372306
311	1	199	\\xd1f8c3be2f07be7f5368bb683c07c204f53baa14ce190a0360db947721a0e790980db34d11c8e4a45695de31f1a66feb0125e9de1ab4392ae9f91d0fe2ed7905
312	1	87	\\x8b741d8db6da808edfb61215a914ebb8448cb99cbf6782383b73add5673049ac3366b56c0a1837deed00bcde1e2256f89e141326569b4233366bc8e939c01306
313	1	181	\\x2ba7ee89f9640c0420dce34aa219d8f479ee6332119a5e88edf82ffa1bffdcb3d515ee450a6ead918ec106e7c2fc7da874bdc34c41800bbb86d0087b21e4f60f
314	1	130	\\xccce02bd438fa6a1592c770ab3f33166f2697c1ea40c10853eb398eead6ff746aec03727fa065556ca723ad06492d8f88255df77cff82c2b83b56419e054f500
315	1	379	\\x58c8b9ec5698984cefe6ac678e3d4642821da11007ed65174ddf3024fcdef9ff0fdaebf2294e177f89504c02240f16752a6e4b46cf512b12344c1bfbc59a0305
316	1	376	\\xd07e79be9e4d263e7448b95123d50a6899f4eec24d8219430a2594822893a6da493705f4ebd019486b4e359c7742ffbe40802bf6cb186801493db71281b8de04
317	1	256	\\xe3064ed238c47543ff09ea86a1ab2f04d626e9c3d90cb4452786e30335ef666f81a9a9e5da77ed9977c6b989169c029b12a2c02f2b838579944f93f4dbe93201
318	1	23	\\x384ad1fcf281c717006b17aa0590a492987a825ef299218be105e2ac2ac9326a5a9882ff0a4967ba13348cc0ea935a16cf85caa2bc4f6585fd254340ad49700f
319	1	66	\\x49903072be2176b63a5719c1f24d831de2e3a4f96dbb424a2f14576cc5df5372c1f109a5bd3a423635f478f6c69cf0e868b36b79c6ef2b4656c65a8603f3f409
320	1	302	\\x5104c70a897b3a46148abf29ecf2b4ade07cba9d3ea68949b446a3f82f0a0c47ec28b5f6df45073e042a13d3bb56df7f77ee84c078c747919b8f8fd6d2804e0d
321	1	134	\\x4f21d447088160f68cc625a20bd210c9356bad157e9c6ecf87259370a354129ed9501ebdeafc7a6b5b330287767e81009bf766be4c6c938a7b32438399bc7e0f
322	1	6	\\xaa9d3601864fbc2480f25c77c4b33081461915d14562ef4bee64654fca0091c10877e8e18623ac6deec772b9db329c64b62d5d9caf916ea81b968fd28c4ead08
323	1	185	\\x5d05a74ab871a83ccf7aff02f43b5177fa40a440f925987be95a1a57c3c787f1a89745a647cdd4a1de53dbe4d13568ccfaaa6e449726607710af6c5fbbc8e102
324	1	56	\\x7b11e4a5f41d3f5f97404b56c38491016c3e9857e397338e550ed004c259506a424239650140049dc38e2844034c3ab7563fbb65115678472e2764e5a7419305
325	1	47	\\xc0740fabd73b453fafb34b9ac98230dba03b9092facba4642dedd891b9836702930dd98bafa737b8506318d9c7abd7fab19c9becb4a2e6d050c2fbed507b6809
326	1	67	\\xcbbe78c5cc5856f022237031288ef1e3e60ef8293d12671359c9714e18d440abf02190ffee5d3ab79c89e7f7ac10230a72f8b15657e009989f0244d0fc40fa09
327	1	274	\\x95353e6e6244f54ad459bd3e14ed90b96fdb3f95118fd9dbeb1234ed77cedf5a8bdb22aa52f0064600e4aae65d51f40d016123b096b9dff8b217f8d454fde303
328	1	97	\\x63a30a0c0f35357afd94ddfd51e894753a8991eb1a5c9f026ab4882537f6d4304959bff02bd99579fe4371746ff5a740777bf2309060380c914496b452fb6a03
329	1	250	\\x3050adc3b292376dbd056207bf8a17f0ae32915c0678de25c725b83e0799b9fd5cdc455e321e4248341cc6da8ce7b87721aac15cd92bc5684d48b52554a5de0a
330	1	243	\\x702dd149777a690ee7ad1c4eb963330b649c1c6f240e40329e0acf6d88d8e779ba6aaa85d855a96553579e34fcf979c22165137bf05770d4f791d96143ee190b
331	1	406	\\x3921cec0d38af6c1c8c1586f201b74f2853e1fcd1f6ed8ae67d8ed24ace1bb852995c7680d0fb772e3fc29d2dcb4c906988e6c77c0b551a42c14a7664943830b
332	1	73	\\x6fd37b2afbb25b06671aff5f88f07b30a79563170f588de5ce8b0feaf140298d0abe6987f0b9fb515fcfba341e1d5024ff5485cec50e29b44073c0c88aea7a0e
333	1	74	\\x50c9af51fcf6389dc47f4164980755da6cf3ee9639d1db68c2798d3f5526eaf6e4790631a362abddcfae8e9094bf5db5c9f2aa09905a0aaae2567a8d7310f50f
334	1	159	\\xb4464fbd59388f7366bd0f65555abb13f65b9dcb00b58e0e58ea7bb97f23f856027eae040b572742c6c9cb8b51bb229d436d2fab4ed13e6bd9ec502675eefb08
335	1	143	\\x7e04e5e462769d6b0153d18b9ecc4edef0ea7daa0cdf411c0e4c90133b5ed63e3f7b0d5d5c8b9201161427497520b8fdec3b55dfbe1d878487c3ce3b071bed04
336	1	204	\\xfab16f1080703211bb02e63948ab4d6c4312196ec0e0330d73b4f28d854b4850cb6c0d57b1727521f8c82ff10f560b7102cefb12879cf90e3b08aadc5d7eb407
337	1	51	\\xf515e6e7e682daf338ad4a4ff70637ec6c93bcfe11e67b27301ab7d8f296456e68ae1c09a03ba9aa7076309a6c953a298d1b0e6ece798048ebe1e84cc97b0109
338	1	25	\\x3e5c96483dd162658668832a36410874761a3f4011ded6bc198b9e09e9f7966492b00928174f6c3610ac26a24309cbee2e702db3b6d1eb382fc677c368146806
339	1	303	\\xbaa47e1b0a545ae8711e161d1effb46890b3c25793360e76e299453849b13aa2d80ca8500d50a10e1e289225db29c9b10cfd2503996319e3216726bcb53be501
340	1	255	\\x06e5163299ef0f813cf244ee53aeea00212cd348a86e665450ffd7bd93a209e82e91e913d891dec2f1355647cdf38af1d3c82d4112f0920be52b26b26da9bc0e
341	1	261	\\x0dd58876c635f502ac342df11a7cc0bb96a2e99c37735dc942358997dbc136dac9def39964d13f25f5b8f0275fadab7b716536d22fd5fb191e3b86320945ad06
342	1	197	\\x20161e991af095f17d4b4b337a65176d8ac18e40c6ff7a7920efb69cd6c42f4062c8f73059c1c4fb288b0bf47ce34d2712234e4b06817f56c3908f9e760d3303
343	1	72	\\xa8c29d53927b63e4d61b2c63b3d98ea84493aaaaa584e46fd79d6a74d707c22c791558480e08a1bd20c8082a289216ee64f0648cb18c26f5a775786db8b03e00
344	1	94	\\x2b5ae2469dffd94e2828611b2001d7c04b031fdfb509480b011d469b53444b5b64be622e45dc2a8e63f88da4dd16bc4a6e6a29c4e0464eccb87e15fffd08e800
345	1	294	\\x380650e39181c5f200328e0133521d71d889d5a32b0d4818023db616047086bf0b67611f0ea7c57b1547643ee935df964d99ae5a64851c8c0628544dcbd2b609
346	1	114	\\x36b98733f644b9059cddbc0bd7fa869325220a8095a693026e6ed950c89faf1da7f19f9f6d2a46aba75355e0244a256d687a2b7a7c573f027f696ae55a51cd0e
347	1	319	\\x316d36152803ee8173c369fae7dae3b07cfdfc68310104a94135c62e3611621dbcd9e6275b547de16849f0b8ba9098ef1204b703cbccbad6dee69037bb78b902
348	1	354	\\x914ea3e551ed9cdb4b527c1dbc9c105c50333900316fcb2852b257981999117b11b9eda025831eea474da55e33ac48a512ac719d294edaf66030fa80b979e60c
349	1	362	\\x88a017958552c2132aaddd30e2f1b0cc1bb04c8c5b9101505564eefa5b26da09ec528ad7fb40ea1c42bf29e06a3cda8b53db5b4e9f52fbd3830fc90cd5fc450a
350	1	124	\\xc0f5ef7935490a0f1eda9ff13f9e8a1b8b9f2e25028e43f26494249be206111e6d39ac2db04a15c3e25aac5a4ef116033cbcf52ec97f218ca3fa58a906ae2902
351	1	135	\\x519cb91149dcbfd07a1872624c8cab7c1cf3952bdd9a8236e651971d5c998b306d8567ac39b4a7ce38c4af02f3b1e95b1b6366a260c24ec4310d93b55b742d0e
352	1	374	\\x4c23e86fa586dd5be96991517ad5ebd7a7c61ae5ea3c7e6bd031bf3766de3a2485f0e852265142647782bcc532f94cd347699cd33dc8ff4aea4a2fe3fbb31a0c
353	1	206	\\x620501efb92cee67bc6f97f8e376c424275ebdc8484528993fc199d18bd45cdf1990eb1acd69917628110a452ce50a1ddfd577089c21196e2a832b30e482450b
354	1	301	\\xfcbbe990d25f48249f5a96b9c3612416fdce225b94de54767aacfb71882cddd3488fd9972f229ef2f6648b81e018353e0489dfeb781a604b575cac1bc009c80a
355	1	290	\\x81e7cf743f874a3cb7754597474aa6d34faef6e1ab20be269578d3efa2dbba32646865a8bc73057121b6c24ead5345145f2910ea4f5229302df3191b779a6e01
356	1	350	\\x56e38792aa8db3dac1e9363c071272f3930da193e407de52d9004e9db22f5c70a014799b85eb91b119f9390415ce43b8898ed4b456955a4cad69b8f03ac1f902
357	1	44	\\x990579a4139f5e20d219804648554251a78eb7591d0f3406280b39f420f95fcc55794ca988ede63f93a1587f43467d02c34ca3bdea39f6ab1f77182a73bc7f0e
358	1	27	\\x34965485838c6924325bf0935c47572fb0639c7c0964c6ae2c7dd92ae66f5087b20a3a964382f17f6b11b389fd7606013ad5a7afd618f91d18daa7a80a65f301
359	1	98	\\x35ec0d7f07267c7d3a3c7c55da9d49ca6e922e9eabadc17c7da710bd0d13232506ebef33ad675afe4aff7fa097cd7849c708a2af892d48ae39144229c95c5603
360	1	330	\\x1ef795bd43d1f9242b8caeb633558b158c48dd19fa0d08c00b4aa5ff47a3dfc234f2902aa91f509b12267c4e473546bc5abc1a1fc646b5b969bf729230931601
361	1	149	\\x27079af179d874e1789350cd767dfe3cf494789862f102629df84c7308bdb4937c553d3d930d0c878a6fa519ce6f6f89e6ccb750cdf17034faf6decd32c1ac07
362	1	405	\\x5a7670da92c3534b0a37be51dc1456aff393d18af3fcb62d44178346909ad04998641d97669a86e7af40229e8a446e9f7f0ea136e7cf52478a825585b4d36206
363	1	111	\\x7d42479c7ec8c3cd2ef8bee1e305a7628fa502876ac74e2a9e49febe5edaea4c706cdaf93d7b807ce58313aed953405d998a89c49e13b62b02142aa1bbcbcf0d
364	1	90	\\xf21f5baccf124d380ea09938d9b29a363d5599dd8cdd4c341ed295ab97b8cc3223e0e5d426f4e9db8238a9f8e0de5f0f66e74da8a95b934c494f9d72c3c13302
365	1	176	\\x124d6b77a7755d30ed5517745a4174c41b637ea1dbf2f16aa6ae920ec3077a9ac632fc82fb70cc779d7d9646d7f4d783a30aee11310100e4184da095eb82c90a
366	1	412	\\x7adc7ec3340f7ebc6ba682ee52c3f27671d636bfe4bc30859afdeeb95f77f2cff8e531564d917b5421018bf2d4d65cab14085dbac76ff76cb0ace23941e56505
367	1	164	\\x87fd4b11bccc608aa351ae1a5601404d819a102134b6a9aa9302d41437d793e5add54fc30a3a550868063f767a48176a86647d44cc1d08a8838d7a75a11cb302
368	1	393	\\x47543ee189caea6c3a67119c669eff080bedc835f2117e4a18bf7773e87d3855a1b1d430ba257b8f0b3778516c8671960590754ad345637ed95e43dec5bd8a07
369	1	390	\\xfe9b6771be73f129b8f6527d209d548c314c08ce2dee58531b205d91f014c3c496ff4ea110f169fa1f9b5351526766bc8053ed58377f0cc2d9eb75cb7315ec00
370	1	407	\\x8cdd73bd6a37d1309724c33434bbc5c020fd962ded33e955178155549004241c777c8ba11b490fa2bbd52752fe6b21a9cfb10f4a3b2d9134421dd0b1760bff0c
371	1	59	\\x85e1aa6cb3ef8f895ddf2a66d3b161395aac9ca788fdcf8a7d7a494d4e5820ae1b29261013a83e427e0bfc8224ce1d241be4f2cd3fd77e6bdea7e0b4cff6da09
372	1	297	\\x5817801f1695cadf45eaca931683cb436c8357fc7f4e74a3b3a9580d2e71145274d3d3c056d6d264c890f6a333560dd4ee078bb06886f74909369f0dce2da300
373	1	420	\\x9d9f64e41420e660a5be3c84732e3881b53d9448475f0854cf1c84d4ee05a9e297cc3f31c4833c2ea81498969ffc85d4e65e4c77ec154346fe0d0bd9d7057806
374	1	125	\\xe4eb5ed671059548d6ad7354fe872908579de714b08e702c063f1e7398fa70d042669f1dbeae0dbc417ab9997656e88218ae7efadb8739b227a05454450f3004
375	1	34	\\x4c2e51a767bc585782f9e584ba9af152752fb7fb6e71f2da2ce2228ea66fd94c9c2de4b54a65cf2e8c00d1e653dc6857c7bcc7bea689f679aedc3165f443ee0f
376	1	191	\\x224f8e7287e9c04cdb80847c7ecc6d3be9532b5929043f6d772cb3f1621aa01a61a187defc0fefd17b847a756f4a5df98097a3c9a342d2bdbde5a0158cf4cb09
377	1	145	\\xcf3c64a78709592962e6e88e8fef5d58b9e01745c008fc3266c04b0ac8242b93d1b21dd34d252160e07d81a352635ed99047dd40e705d2a0a6c09340ebf1a00e
378	1	286	\\x77f3c41856177c36d7a5374377de702b65e918d6e06cb2465358fd8a7a919c840cbbe55975586127a6217a7a27b8c4cbf692451a06ff1ba8764abbf116a13b09
379	1	115	\\x9794b221f19c71b8946ccd862636355769517e9feec93c393c7095b1ef470f77b716d46571507fed4437a4bc20e69df42e9d8d372ff6ae8a31bc73d897e4870e
380	1	195	\\xb62e23af716d3cbefc95cb93d455988590221015eda5bb913c2a96a65d10eedc0daec85e7eba524da31ca4b05158d8d255eb62ee7a20e16411557c7bb8b66e0f
381	1	162	\\x76ae74d7a44fe39bb2d5853430222bb2c0f62eb0b018202f777e4028b060e095a67536b0a677ea895cc7d9898eea22307f052ee1b602849207963448804bc70a
382	1	364	\\x045934e0100b2e2457b6f5d451314bb8958b8529312fc4835a0b1d6646c731e8b879c3cd4a7a306be1b76b53c8eb72badaffdf79108310360423436e0eb7450e
383	1	320	\\x61ee769a37161f445fca8073cc041ca51562e9601711e8b53683468a25f70d4242c499c5a142fc7631e45aec81e568e2d4e68dcca79e97f8c0559d8a0204e30d
384	1	38	\\x65ed6f7110393f91fe4ea072f290cb52fcf0dc8bae250b9a269ba1eaad5531d58ad56c8e72a3c0f1d2101cfec7b8af7e33f9713188862d3c9b81fb98a6e9420f
385	1	140	\\xa704770829cd36d0e29f949481d157db52482093f5ec243d9fc6edfb4f6990793addeb520bdb5e8057a3ada187b0d305600a4f9222ebcf9bab45e44f3d6d4e0b
386	1	8	\\xe551e1fcc2351496e124f851da67ced29a2725d5b2633bb0ad69205d91ccd63b512ae8e69ebbe29a74add75f127cff6b7cb5751a8790d8a5390b33384e70c102
387	1	279	\\xb7b7cd51ea453817e1b2cc27bc112b3aa09cd02080447d85f429a38f0f6e5e840f4e9d3145127218df226ad6b8e6264ef2d9690ca6178867c618429f993e700c
388	1	282	\\x4aaa78935f3e0f69b5af2741b4a800637226ea7b04b8013531fc65baa05b74cd716df87fd59b69b28a7dcc1d4a1041baff6e751bdd4e9221cd0186394cbc5303
389	1	391	\\x8d2cb1f92f14d6f8af2a933fe060f3e682f07059e42dbebbad4f02d3e97ff51e9c8eb09467f0ca25615078d47ca217d7b762981595d592fd17c14cf16839790d
390	1	337	\\xda286d217007bcd45c4399374bcc84d6bc69c47068a83a511a9d0bba1f20d2e1e3e3fc77138e90a8865bf1603890c085b0624d6c272389c4239d62e07fb0b203
391	1	121	\\x43e0d743d8c4f46830e10691d5b797e6f05fd572b62f0a2117f6bad8d496434a2f75d60711873fe7947d6a49e1408b232f8ceb7626193efe5faedb2400587b00
392	1	39	\\xb5c71376ea3f9a7212d5f5b07711dbf9a7dd3ad91dfec7d4e979450f0eee212e93dfac6fbf46f58b0a104c57327e1f07ea0143b9e2d7ca1f33911acb36b3510d
393	1	273	\\x161ea3625978dc6fdb69ba77a26860b6d97b0db5496aa8c789f1ca6c19cb19b0f18364a3e626a0b9c124ebddc181ff54d91b65c1065458541818aa3757ff9903
394	1	411	\\xf5b21d79b8e9242467f6e65f059c3cd0273c0a9e6310dfa6ec62bbee0f4388001c441c4c5096cb6c15a23eddd0e7a26a946181acdaf8066c3bf113b6b0d1510a
395	1	245	\\x1d42c457864108ef1d144ea838510d7483efe25a11473f633be13f0d776d5699cd9a22081ff50dfc7ba99f7a12479d87b04eaac3993eec9e9a480a10cfc3000a
396	1	419	\\x21b1652717aba0f13a1ff36527af92586660f98bfb3135232190ef54c85e724ffad1c77023f33d8953562fae4e9438dca8058dd9d56f1ce4f00fc3d695650d0f
397	1	213	\\x83d6bc7ab8e7f5362304690d77b8fa61d1a66edaeabd0b7bfbc909595b3adefa0469cc6af7a9b0c8ece67570dae501cfcb180d073122a44d784145e47ec57200
398	1	397	\\x97c65d3027fcf76484fd3114e0ac253a6023490de15da6a3f272332a85fe47e9566fb496048597846a823c557447025c8ff39bfe46a8fddb99cebcc5982ffc03
399	1	300	\\x864882fe9eed787f4e5ef1e760b145fb8b51025fa51e3be46690fd389e5b76b0c312f33694835e934449b2faa2203d2dfe33ee1d767d8ac8355d81eb589f7606
400	1	418	\\x2df9bb765180e50500eabfe75a64fcc3f4a6cda46c451182a091716a065ab188810a9a9effc92ca92529a2e717f39c8c64b995baa39520447832c6ae60cd880b
401	1	325	\\xb3f1858ed906f7e97f232a914852c7b47d7666e28e84bd97bdfdf621a7bf44aed51c743a1a278c31b6b5fe43f850e68516648de29918eb7696789156eb15d904
402	1	201	\\x2028d96d96b0eb949774caba753a50893a4d2e9d4a13e7d4af18c53a32df18c294e210ac79caa843c9fcc36d6a3ebb610e73ca133dd2eb4816d0c2b65e44c300
403	1	232	\\xe80d0b9f49ea50a69f874fedcb04fcb1b3c52c7d97c8fc2844609bc7ea718571c76d0f6aff95cd972c876b52864c4150907703e4158917b34b84043793c78f01
404	1	65	\\xe8f62d437f851ada609b2628661efcbd37a006f8a38594a20ebe0e508a1af7c7ce05892ff8a1e26c293ff5c32aa0a8d60756307cff47bb5635fa116d86500002
405	1	40	\\x5ee68bb4fd72033235a918fe57fc75e0fbd44be0df3d25d774b9a061f8523c6a6c4f0580e3063883ef9d45bd10fa3d17a23ceb3724eca99fa604ba64a7867c08
406	1	402	\\xdd98db5c69d46a533c1cbbd50b6c24fe1f14f556bb5bf3cb88b384cf513c1a7c15392a575f4bb199f970fd6bb1ac7e1bc3af809cb4e552a4da00b4be346c5200
407	1	249	\\xbd1aa9e5584a99c9975a4e3544a25989dc7db8c1d9b835dfea3f3eb79a38ff63c236263c1ed1778d9b2a0a1fe66729c51d3a547c7bda504ef2ec58b8dc3ff403
408	1	228	\\x9d13705fb044e66715ba28557e0980230e03406d0afffcc54ed3cfb5fd85ac90e4c2d6dbfca50eb017b15a11bbdfe40d7214cf3782629de06e789f558c85570a
409	1	293	\\x9fe0921c8b37e8a30a1c73f0ea16d846c57fd5646edd31bbeaf07fc9fc9ac987398d4a53381c8b4e956049c4574943d60c18a2f6dd73c55eff72279525f8f004
410	1	375	\\x5e6bf832d015008d23d2bda78e5deeae3ab70f662ec4ad0dd5edc83f953144f3749223f0dbbfb5d34039f93dd29156527e81d47a8c0f11f9be85e10a0b979905
411	1	331	\\xfc34a2c8f858df4017c18d5dd234f6b4b4783daef132c30a81d59159102c5c1dc479e864e11229061d9f8e14a90f4cac84013b49f72aba159dec6d4a674dd00c
412	1	71	\\x0ae0b44455f76639d3390e60fc33f0d9417f7f3b90e37d2a0de8666335ca4549cc9db95faa32e6d409f79a3d344139806ffbab696ce15f00dd5047863b0e700f
413	1	184	\\xd2017af86c542a7ffbd1f3d8f48edd9645940b2cdc995e5de325793e596f54fac5e400f3175908d8d097a564fbe19970b78dd8325698ed410375d086cc11ab0d
414	1	179	\\x217e036b0aff99d9cf98658414f4eea8de00236db4cf7c7946592bc0a8da673cda65a20902d47d6c28694509febdaf3c1f4b7eecd6ba393544b44e49a1cd770f
415	1	91	\\xa956221672641ac380b4423803e4276f19ce815faf1895a20507fdfc7cfb2c5e113e52372d5e7afe0b249288694dc179826ddfc8ca4d8a31f52568fbf65ca104
416	1	240	\\x741dc119d67742b3ce1874db544257affcbeb85747501eb222bd175f7fd375bdd93a8d0ca9252b5e3eb6a6c29595d87b55a322a598be923f902ac3995e69a803
417	1	113	\\x012ca9d7f6dea931d93607f30480e602f24361cc34578e5f9697a018510385b2e80f9a4c9c449d8bb436b1fc25f6c550b7cf202757cff8b48d39f25c22456d03
418	1	128	\\x0cf80cde478ec592983431ad82c57d0e5faf6cd550a6de8fc0b3cdfe35334d19e81036657a6568a089f45aa21eebfb3a1cccfdd9c839dfdb5fd09996f681a60e
419	1	194	\\x0c232085373245ec4b689e654811ea78391f20fb2dbd1b8d4547ec31534eb9aa8b1dccfd167d2ce9e9b6fa9effaa12b97a59ebacd415cd3162dd502d0052300f
420	1	333	\\x156b4f235a61d3ca601cb3d1c917ddcea7ebe7a1316dd7afe0a97ad354ca72d38bb78ced260702878c488a46c21f941cabb364f6c0a0eefab469a854e1905d0a
421	1	57	\\x3c0de2d85a9c826fad6af4a2c122d706cfae7f837a5c5b59c03e3bed9ed0fbe614983fefbe2d6d4362bd0c6b8c59021959727042f2878688bb0c109c0967a70d
422	1	260	\\xc13e9ecaf7807cb5c51af4cc8dd1a434e81a55a07ad5d72e908d34412d4de8462766bf31987fc20020b1d3146528486459367c0ff3c6ad1b3f3a1d4e291dcb0c
423	1	229	\\xdd98db0c77cbc2ee6fb7ffd9ea3287a25782b1833aaa08af31b635ad693b98c9dcd99df4a8c5acae9ea470d65b6bfab188463d4a67408c06ea181df672ed090d
424	1	77	\\x6fae8111bb410af325f2241d18bdad808a57a05fbc3885c583d04a36ae57e2286cce21ff2247d5195fba01f70fb8b8cf8b4df836d5eacfe20b5ba38830fd7d03
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
\\xa61cd803bede7a4c5bd951a55bfd23b09ad5c08578e86c2ffdc6489a025add48	1655640557000000	1662898157000000	1665317357000000	\\x85c532e0499b11517a10665c66301831599632bbd934c51a829365d590a774a7	\\xafe3bd45c87ddaa6ea471d5a66a3a038269230ff0904d959a862bc7e0b45644d06e95ae4229fb5270d8b4c065ea45ba63a29d30630094ee1eeddf7ba10709b05
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xa61cd803bede7a4c5bd951a55bfd23b09ad5c08578e86c2ffdc6489a025add48	http://localhost:8081/
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
1	\\xc3a02e84d73f0e68b9826d81596154680bfa87107d0128503aeac7549e703004	TESTKUDOS Auditor	http://localhost:8083/	t	1655640564000000
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
1	pbkdf2_sha256$260000$0Nk9sFAkUuwKp13eoE2Fyq$Jw6jKZc62NKUM7VXPGXIFfn5GzWc0fkCNL8WHHaRdog=	\N	f	Bank				f	t	2022-06-19 14:09:18.35267+02
3	pbkdf2_sha256$260000$imGMIBBxtgJ0D1rfWRcuPc$0IUycrmTq8m3gZktURaiH1vExUfFKNoOVB17z07Y0qM=	\N	f	blog				f	t	2022-06-19 14:09:18.542836+02
4	pbkdf2_sha256$260000$2HwRHNH9Q2XC0iS5w3abaz$Z7Tgl2hTW/c8lBkwffGF8TmVFaP5pA0nzqUlHNEaWCU=	\N	f	Tor				f	t	2022-06-19 14:09:18.637257+02
5	pbkdf2_sha256$260000$xqHYfHryA5aILKgODOvs2J$S3mcZa8zn92MOMcIceJDGwcHIO4thpDy26eaTjakZeA=	\N	f	GNUnet				f	t	2022-06-19 14:09:18.733397+02
6	pbkdf2_sha256$260000$qtWebIwgyDomY1rJtfpvDy$+9givxgn7Uwz3jhxwd4CxdRWNUav6p28VVCnRz5O1zg=	\N	f	Taler				f	t	2022-06-19 14:09:18.830494+02
7	pbkdf2_sha256$260000$w3Bisdw8RgvDWlSfxBMM8L$guyILdXtCA3GFuUswAlFLHFAmmjSJcPHx4Gf+1tUrlw=	\N	f	FSF				f	t	2022-06-19 14:09:18.924503+02
8	pbkdf2_sha256$260000$37ZLZHSIfXcdl8z80fgcI4$uxfI93ftpcTqkoHTQQgOY9WM7Y/A3iM+bUdpQI0G9Y4=	\N	f	Tutorial				f	t	2022-06-19 14:09:19.019958+02
9	pbkdf2_sha256$260000$7P1exzuUkoVqlj9SzWt4hM$fQU/z7JB7uXnsLUg9FmFTjh9jdEb1TZJspux4PQ6g0c=	\N	f	Survey				f	t	2022-06-19 14:09:19.11515+02
10	pbkdf2_sha256$260000$meDHz25kyrjANxtbwyjC3L$kj0NdRXEqETSterPnlITygIuQ8vHgzV+LFqXDZgrJ0M=	\N	f	42				f	t	2022-06-19 14:09:19.569582+02
11	pbkdf2_sha256$260000$eRt8twaL64JXiA9bdg2KcA$4HG4gbyhjsJ3xA95W3dKpJv6fCkHFIl3TjkJCpx3bjc=	\N	f	43				f	t	2022-06-19 14:09:20.024089+02
2	pbkdf2_sha256$260000$6pkmIymnT7H1BeGVsr9FEe$T37eQLgxGTrOQKikMx6yACGIG/KpkqSDIk4hARnuMyk=	\N	f	Exchange				f	t	2022-06-19 14:09:18.448095+02
12	pbkdf2_sha256$260000$0NikfnbYrVx0rLJXfkREmw$Ztk43rfDY8Jz/uW+FucrLrCNmJc81T1xpPShJnMk3pg=	\N	f	testuser-ljgqtzra				f	t	2022-06-19 14:09:27.167398+02
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
1	57	\\x5bba4ba907b413a40589d32ddfba3ddb5a76c117b748824cc68823cc74c82fc3f049368d350b0208474d1a5eb5a043ddd2a42e697c797efe519a34cf5e693305
2	293	\\xede76eb00447c3dd33a646a071cf5688fc2ba6aeaa971d22a7ce32112d110d26c484bd9616f89364757a73814d8b93fe84e57a632f21b853e5129b4d9c977e03
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denominations_serial, denom_pub_hash, denom_type, age_mask, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
1	\\x00683800c64d9cc02dfa7cc066e76414ee93ccbb1f4b9c723010e9a3bbe19655bfe1420d391a6bce0ef7c842104f53473a7098c531804d9460d255db8321134a	1	0	\\x000000010000000000800003c542eaaebf3d5e437abd0d212ca29a949a154eb7834037cf4c6d26385d80086f19f3262d9a0912f7eac7ef29524261ccf00a107c20e732e0cc5772325ba74e0dce34d9b059a5ff1906e597f0b0742ae0d9e718670e48bffa98df208c3fd756c9b0218e355ff259f6c248f691050804834aceae08ea7214176e10f3bdb8bf8571010001	\\x6e0a557756f303b694cf123ecbe42811e310ec2444bdffa024dbc88f3dc51616247ebd1028fe5399654d3f0ce4a26e1478833851dbae3a5878110ba528de2000	1685261057000000	1685865857000000	1748937857000000	1843545857000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
2	\\x02b030c8ab8a7f87122167163804a203dda43d26608b6e578e85cf2f847329ebe2d6cd5dbc542b9e1cf18c7d63cbf998ba48788b2e45503ceb03de39927aef11	1	0	\\x000000010000000000800003be35babdf376f228e6f185fb4c2c9ffd454ffe44d847afae5b6a52f906a932901c57d9775e2e3027c0983d0a920a663252ae4a25d5283c1a68b800617472226dba56c1eeb88bd0f50d14770b0995e468fb7eebabce86b7dbcca31570ee736a2169ef1f6ed9e75cdfb7efdf47bd1783797970d1adc3b17c406ec229569c3d0961010001	\\x75fb6255f65e4e4d498ed98fcebe2f4d4a63ef76d6b790c3b1a5d8d40324a562d441fbd3c9e2d37d4e6a61fb5c4ce227c1c5e6a5206e85fd7ad05cfe9ebb6a00	1685261057000000	1685865857000000	1748937857000000	1843545857000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
3	\\x025807bdb4caf718de80dfd61231b0898c27044ad7eab075abf9a4c43f0d49247cd18566bbf9da208801045890643b41abd020efa03be1a166e64f4c6a1ee1c9	1	0	\\x000000010000000000800003eb664840d1c572a268af0bee7911e5e65889488cfdaa518720f064ca6cebad6279c098dae6825c214c4b0aff7ef10d25e543f163a757ddf814bc9120fffb4e5590fbf35f16193ffc72205136def7e52a020fc3f201e92a4d14ba87115337102602b8d7d78e9631bc7c5f2edfe1eb4cbed069c8762dd0a3afdb1cf4fab262da11010001	\\xee2608b6db91966650da32c41b0b4f6d73759946a9695806e731da8a7aaa43127f054a367fc2f4ac0fcf21e0ffc0d3a36b7049d8deab4c7c7f30ed84f7b7b00f	1670753057000000	1671357857000000	1734429857000000	1829037857000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
4	\\x0df0c4fb49f5b3f8803b54ce52f216968965adbfac25f874ccd443eeb7d4e5271bb3f3c56c98f3f3aa4a4cb49331d119fb95b341db626acec9afd357035e131e	1	0	\\x000000010000000000800003bf2c08b2ef2c0693aebc00835ca12be769fbe314826ecc052c0fbf4f3eebf3bf6fc58a1c1b20aeee77e5702a9904a62abca58991b8c92c754dd6b03a145f3fe475f61ae4572213163ce3499af262b69de8a217163542e0074a32e47cf9ff254576878d3f17e1ca75ad3d78a8a57c5d19f3d2cf97ed30c4ed6800914e5a03ac71010001	\\x61e484cb315c873be7a16139c531907eb670224e2843e2f6a6d3d57bbff5952bbf92961f78a89e6232d1cfb837861e572565aa1b64036895565ad2715fd60e02	1673775557000000	1674380357000000	1737452357000000	1832060357000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
5	\\x0f6016178cdcf9c0ab423ddb2f79da4ef4ca33b84193d482d1156cf29ff6fc04b344d0a368fa4332ae480b04c04c284cfd67f5de46855fa4378ce20e6ff98fd6	1	0	\\x000000010000000000800003ae7cb164293576a2bb6779179f28b3f5b5ffcc2ccfe3afa475a7a18f27d3fa8aeaf8b17270b04d9c94dc37dbc89aed5630c7ca4ce88282341b1fb2a00e97dd017e949d5bb6695cd3a4746140418ebb7b43ea42c268fae750824e8e3920148d41e2ce1fbac431404b6790aa61f89f35f0b9e51435db073890ed957e2e8cb3c8fb010001	\\xac0f0d5e7ed65edda9af2f5eb62ff5b04b93b5e74e5c4a2e821e36f852f14e99198aa842728011a4f02905c987624e84032871f8f3e55c7d01bf6fb4d45aff03	1668939557000000	1669544357000000	1732616357000000	1827224357000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
6	\\x0f2484ffa37e91614d9d3af00bf570527c7cc948e82a7fb7a71d8ae19b246d48cfec5925aafd3da70414cfb5eabdcc1f462fe5d53ab95536e8c5d46fda7d3425	1	0	\\x000000010000000000800003cd9dc84b2060758a5d7b253068ae149abab7b046f5c96d8fb9a273e8fc74cfe37e0c466ec4351791dbadfaea0e7a7a31f02fe1b1f3755611730ef43fa9f2f68dc44b9a88b35720e2ded02478c2b4d521945ca936bf5d8629527db7e6f587b6c88a2ff0eccd864180444d56c0d0dbea536a237268491f4c379fc51a952664e059010001	\\xe2837de4378f8fd8b3305d91df0bd817d37206adafcb524791d76f993770a81204351e3e5d506d94bd88e104aaf945b8f142bf50fdd4a896643ce2accfd07101	1662894557000000	1663499357000000	1726571357000000	1821179357000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
7	\\x10781b1bee9d3fd5411243b5ea03bcdc9861e9f735b62049a1aa54088d5658e60e233b7a809a25bb8cd6acd4c022baa1d390160d4b4478b85c5aed2472d7c636	1	0	\\x000000010000000000800003bacb571fb6b6dd2d7c9f78796095a70f2e4788dafba78679fa75dab230ba8be71a0737fee389945dcf5464c52f4014eef734d13a62685ed9db20e6e6411dbdd0c46c3f51358fa51be00843b0f6ce4d1257c35ebbb2a36ad275f763601f6422821abb858838bb567131a70c09198684060ac1d469d45a68698c8fa397210ad8c9010001	\\x072771665de823382fc68cff00a28be9c2856a4f50d0d1bdd6656b49f4dcd1f06a51b56108aa0a7f9aec0d465a149977f413c9165488fe0439333ef26f41ff05	1681634057000000	1682238857000000	1745310857000000	1839918857000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
8	\\x13b41bad97620b4a00faff63061398451033df395a2fdf37a5df7d833fa04d4f8ffef858c6632138c993c40c083f4be57af4ed8b2f1407081e5ef643a44e5bdd	1	0	\\x000000010000000000800003c0f83259e4441ac28a695992021b4313a31221164fe11e3818a0a14d2ad88542e84b52853079e4519a676e209e41515adf27bf530598cebdff4b39b184aa16e4c6edb988d7e03363cf4fbe3887fbcc38879d7b2e300a16d8ae9807cb97c21ff9bdafcbcbd08b7cecab0cf3790a6cc14e9a42585f21b272ac53ff48febd0d9113010001	\\x99f94cb27ce85a94da1522e79f658c186063b171bf7834a0ee41a65a5dc6bad2ea0cc171559907c4f743b7730308c79dc6031879d0b2faf8cc9a365e6ffa390a	1658058557000000	1658663357000000	1721735357000000	1816343357000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
9	\\x1724fe01d3ccd0353a77a1cbfdd33a3b13f7b7651099d02521171412f369c7076579d8bc31548f6d56d800a4f2ec80d3b58a87856969768d35b8319acf0ada97	1	0	\\x000000010000000000800003ca1b71fd768d2c98d80ebc9064f67d4cb28e20b2c72b1615dcf482443737dd7a86ad504c971afe2298eab047368ab7e497d7e383aaad370a9a9c3a3bb91e400bf18e4550e318f8b4b3a93a76eef5c019288cf9ba40aabe3d74fd3c98514ce5afccb98b31ce9cf7a3cfb9bb7d5b8d1c5cb2fc60266b140974c90bbf2f6bebc585010001	\\x4e7e5ed2a62b8be70df6e882b97a7b843b8306d47712c885178d38ff9dbc1bc4422adda2fc4020878ff681787074154c7d7123ffe84b354d7f136ceac1764103	1685865557000000	1686470357000000	1749542357000000	1844150357000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
10	\\x1a088e43ac30b7761737bce9c393643d61ef72913d32d382cafeaad6942e2fe2b7f9c6c4b68da208ba1a3b0b397feaeda72963c1f236e53b06125c44a0681c63	1	0	\\x000000010000000000800003b2be19dbe77d457da569c99d120fec32017dda2af1d2c68ce5327b0c2dda51f369fd2822c20c87e733bd8caba61818ad38b9ab7eae2a44d6c358935bbd73a3c7b2f68d96274756f8a41b14cf4514a77bc8c1e19a45251b5a8ce5a31b725f7370c5cf9df9c2004789e80c0a98c80caeaa8e593ee40458783580e4177f62027ea1010001	\\xf9991c8f50fa9db6c296f22c86135fa56b47fa3bfaa307d8820bf50b7658c355d112b2bc169532aba52a2846382d830c1214aa57922080c04fb923594352af0e	1687074557000000	1687679357000000	1750751357000000	1845359357000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
11	\\x1dc0f4adc0de41075926abf65657a27fea7213ccbd1d676341f8dc60fc1705ed34fd3596a184bc418d7a555d83422d27e8f3b256273283336f63781a6c6ebd78	1	0	\\x000000010000000000800003b51ef13e04540bfcf78f78127cf43be45327f123e3023b257c1e305bcb47f797478b557440167e1c9494c4cbbad599c274e51ceb6f5c3ec048bacfdae870dbdebe3c560600086c3e79a3887dac97eb5cf0183a898065f8f98b419906722437432ae651b71c139824eac08951033b2d76a6a7cf9a712f9d6cffccc2700194a37f010001	\\x3d2d151a89433ba68a9af882d7b68fc50bc2fd9de89a76ff0d8c1a1c71424aa96eda88ffdbc376b744d145278c79e360a136a6f55b2aa8aa7498703652cf0a07	1678611557000000	1679216357000000	1742288357000000	1836896357000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
12	\\x1d605e35de0003b5a9b95ff9df58c40b021b6fe3d4e359f12653a3d1720dcec1586bcdb099c937837c499ab8f1c12b89ef82b3993ead7f1493002863362a16e8	1	0	\\x000000010000000000800003c15ed2ee8a170357d68fb0c82e782786806eefe0ce866f9e73b6c0323994e2eead4eaf7e021855cab3198034e7e989d308d130cb4eab0497d98fa4e4ec11c9fbe853f92c7101eac41ad3aa0d4373f1fbe52bdfe862964b8284af85e284d11dc9edbba2e9df35f378d79b68a4276880e7420901461b17a7203170985efb47134f010001	\\x241d13d0ed143f659a816b4fd46fbbf64d550d53d0f019039cf326acb612276f24b89a986a59252df931f174b60158ceba4a0218fa5195bd3bc11d708a6c3c0f	1669544057000000	1670148857000000	1733220857000000	1827828857000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
13	\\x1f749255cc2010a30bc45180e6b953bdb4d2811500b33854696abdd0697a863f8805d12ba7fa21c30587eb02e80ffb6f20747450536e548c5ec00920df92db6b	1	0	\\x000000010000000000800003f1d73063321fa3142c31aa6f3ec73e734134ecf191e80e5fc370ec419d1a7fd0e8a0bdc7c9a01558d081f41a1f0203790395ce9f7c78bd76282235f34588e8cbe198581de565a5d9bf78a189ace92769590646321c1b80146554bd6d3a72940e1d5fa2d6edd16a6b483a81eff0ec8d8c73191c75d202248a5b9b29953c9f7d7d010001	\\xad09ac771eba04d666449892b3d93d272b6d9214b7745c8f10ef0d7be491761a68cff1080bdf44bc2cad3f268d5a970c21abd939ffaf0d6adb535f3399c2e80f	1680425057000000	1681029857000000	1744101857000000	1838709857000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
14	\\x1f98d3e8601cabf3218d2a1323a39867d3a20cf68796b08640395efb6b6b06062ca0f56d1d847cac65ccd9d5e9f55eb079580fafdaee75e56a0eb909e9f6f0d0	1	0	\\x000000010000000000800003d617123593dfe57ec49d3379231e3865b853070f0932cfbd49e963fd8566d41390671508d4ddc73dd4813a339e6fe7898035c22f38553fe405d5548e5a79e296fc92205a9089760ddaa7bc099468eb4755b3d9eb24f0642903cc907a4d9b43f83f132fbd892d355b58e6799607d21e67dc72f3a6cdbd7388636853c5b4ca1af7010001	\\xf35548d88a62d6aafb0b4c9c2a8b997ffcb47b719db4ed1e2186317c6fc353220298bd00ec3f3bf4e38f2e9b601e3db2e0f98726f395f2d572aba4c81caef504	1675589057000000	1676193857000000	1739265857000000	1833873857000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
15	\\x1f48286896cba78bca374dbf7df7d27a202487b506b474679ac9786d130c065f83edfef3f72f1223082d870a2be76e63580950daefbf3cc500a181cc69915aa4	1	0	\\x000000010000000000800003ce1fa693d4f982d3b49dace6f83b196f0ed83264a42d890d1450740878e6ce26eb4e7e649af4adb82f0cb9f913bf0bb8d1e083b04db3c6ec197220460f44e5bc87e74bedbccedd8bdeefa8a5b9b2e648691e6b8b287c7d68281acd10acdcaf41c69983e303e5ab3cffc839433cc2aa9616f93abc105143ab8d9958fcef131603010001	\\x65b19b5297fac83e7bd77c6d37458dd845c2f8680435c10f85346c5f555fb39618e551fbb797a6367c4c48f2e82454efcdb230e377d9fffad41c74198dba9e04	1679820557000000	1680425357000000	1743497357000000	1838105357000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
16	\\x208080d369bd9633e2fbd0fe023f9c7b3ef1456da3d497fd3d3781eb262f45b343326ad41458f76c7f023c55600181b811f7f5f75aaeeb8794165bc6e1abb382	1	0	\\x000000010000000000800003cedab4a4afa502419ec999f42155a9e6da5358d1403cdb591956809774396d530ea70f89ead3fe46d87041ed126685d18b5ca8e4cbbe93174abfd60a2680c84e9a7f70e6f4c13d6256d93b8f99dc73a5dda80a84af5b8ce451510135460fd71ac50b482ed01a13a1597be376c1c20849b612ac2735daff69df48a38d95eac3b7010001	\\x4707b0cf83b2775e373d77ade6072898d42f2b1210552456689d5a3d513213d59378dba743f8e2b316401801c07045626935b2b8c330146f8d65bab32820a603	1676193557000000	1676798357000000	1739870357000000	1834478357000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
17	\\x2a90dd58cea34e61991a61f9c1b7d020f9194dc337c2fcdd48914e60aa68fa49fc002091c6ca8e82e968c3e5f68082d2dc0345fbc1e06a51d6d8bd5e6069b21d	1	0	\\x000000010000000000800003a8e5ec8b6604724d7cc9c95762c54cde069f3ee2487c60b1ac045a159216e4e74024d4d5284668ae05e4555e542e888fb755045ad1831d3a2cc7b930ae752fc321faa2b9caeccbb07024e16acfbc6d3c8b8f52a3d9a52aab00bbef5300ef23d1b69f48c2b49e077457981a17e8ea82e83e40f9ed92588518439b624199c25391010001	\\xa7ded64a7407bb6af6e626e7d9b771b2e27c1a56cdf126e272fe559227aa8719788a06da7aa1daa5c15e430539a7abe8ddae0e72b5f6f723ac7e5aa10dc56803	1687074557000000	1687679357000000	1750751357000000	1845359357000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
18	\\x2c2cec8c589197bdf22e2c8e65d88e33f06e016db689b6051213807b693180f39f35efd30b3e8a7832ff0e89498ec95f9320ef85d66d5a35278000e7aabda3b2	1	0	\\x000000010000000000800003d7658f11733b3dae615e068a942cfa912c12fb2be7bb52536baf8d0ae5b88cceb47e6833107e2fc35110169f24f8136fc550d030e8bd7e9e4f78de301181e04ce7a3665f3f587d208fba10c411947503abdf3b99f28e2ad3bdb824ba42d35e3e77ca9786c976976a2c3cc46c7f41678baf81f0d37d6d8251e092c62e61140c3d010001	\\xa00e055c733eb328a0db42729fb1fdf0c01ccd83c9845326ec312d37becd9c0deccf08e8a5dea0c7058763d927378a890ea08bed35462544e0900bb6c1bf8409	1681029557000000	1681634357000000	1744706357000000	1839314357000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
19	\\x2de802d9f3818c9aa8eddbdb573906c104a05e69e146a9b025daf27c69aebe59deeab1fb645ea94dcf9438951358f3176c52122096ad5a255dc8f5bed78dfbc6	1	0	\\x000000010000000000800003bd4d31282a1c8f49d60004221f347fc53c21a5174c2704f05f9e8bf64ddd0454b4fff1599358afada905294f8daa3f4cf407fe08fe7fedfda9f2acd93807b2e2c35731971df85f093a03c985b934c562e89b7cf41cc65a8c3c898d5106fdae7adfbfa3194f7990e10f5e3176c89863cd761f755d10ea068c2aa044243c1fd6fd010001	\\xe63db9daf283643d0535bffe8034c06e653a3d363c7f5f4a75d427697f00e065430e17c3e3ec557e46fba9d2801b0f18241f0c2e70774661d5cf76414064480a	1686470057000000	1687074857000000	1750146857000000	1844754857000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
20	\\x2fa8ca5403d0ce2260f51bb45e5cdb81dc992d667e640875a825f424b93a8245cb58392b68a8e642ca6bce8256052d17ea4ba641a863d48b35cd3f16bc6a4e76	1	0	\\x000000010000000000800003e708f2b2b211dd0e3be279fd75586a9272b3ec0814061b79aadf5ae99df168e1a1ff0805b1fe44f709eb029176ffd998e6d17e809b87065a8bded606f6b589ece181c56e1843a53b96f1ea43273917521c44bc76e4347c3dbf2d4964078829976da9eb814de344927b669f99a5c6b3c3c5b718a9e2403007502f5f4029322065010001	\\x3189504b7d5a0fa4c7c4d55920e188f734f0be0fbc78a86279eae51e533fbf747a20da07c539519452280fdd9229c85d17fa94b90bd6a8c52e9ef193bc8d7e06	1682238557000000	1682843357000000	1745915357000000	1840523357000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
21	\\x31302bd097a6b7059990c7e8ff09d7d62b4bf8376c2ba7416190aa7765e84913228578945786c2020ae320c8e0977fa48679623ed9bbcbbd079b9306a9a98066	1	0	\\x000000010000000000800003bbcd7a451f5773745076d270c33a3851dde45b08c47b5e254788a495acc202b60a286098c89075644e90db912dbc4d26cc8aba846f3c0934e74f93a7b0a4a91a6ec157a1d8a95651f2730f380b0f65d6a5f0837e07de81d059637ac094c44317e42804a6a1cd3d4e93db3c082cf1cdf531e166a5a1daf43d55544d2553eb470f010001	\\xcb291996066af646e83b93a2cd02dbed85ad0ea1f58f396a8f221e085f5817bbc8ae36e2fd4e7bb2391e4c999947e2f46d2bde1b55f558e79e6a9cbd48ddfe09	1685261057000000	1685865857000000	1748937857000000	1843545857000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
22	\\x3a749b0f49e87d581ed7821e01742b2faedc1713ca11fd84a4d53aec79857dcfb5f12ca9994383b97327c2c0f48270b8ba7c73721f9fb724eb7c05379573726e	1	0	\\x000000010000000000800003d089e2432e6c8a84a5d5ab2f9a2832670a39289ddf9778dfe3169bb0b47dd50250e45d100bc6dcc4d37b4308da9baba8687acb69fae523ba0604a9c4b0fe8e5695820315e9106759c38a98a1e7db47d7753d257566f877b773268d2e9c9521d86bf4df7e391dc4407aa70442f09d67ac1f01960a3a41e5d777a73b54b191f22f010001	\\x75ea479655b174dbe4ecedb257777430d9ad5c5957be8e96f90940cbd786d76870f27aa735235bcfcba22062f340ccaa6381e7ee4fb2165b7e226a46658cc009	1678007057000000	1678611857000000	1741683857000000	1836291857000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
23	\\x3b54a9d2816868cb2924149cf45469bf8a1d8920ca2e0910963a2c4676128ae84fef6ba7c0ebf72ce113d57bff386ae07c346d9f95a1c5f7cfd92fa7429c2822	1	0	\\x000000010000000000800003c9120895ca0783a87d80c169b2721f6c97cd29411b84f27210caa352edeaf66540963f18810b6472d7f7549df7437c4f66354feb1b2f26af319332b8fa241682ea8dc7916b8a33c9d8e330db05a69cb2476c139ec201ec5db55814a62e02c4cb31d94747f5a786263a7160d998d5cd1f30c0472c6c0b804a4cb083bbab789433010001	\\x73a10e8cc71bc7f970911c12239c5c8c575130b893499149d845bc8b7aaeab30b9dbb862dbd0685042a40c54e0c83d473654ec6eb8171710fca880c37337b10f	1663499057000000	1664103857000000	1727175857000000	1821783857000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
24	\\x3ba00608f8fff079f9b4310586a4bbd7895b8ec99f8abb1963778c8b925a2b5ab6579e2f8286a4cd84ac54bce2824eddae0ec6d82b60a95a06e32301fbf944da	1	0	\\x000000010000000000800003b0b06d97581693e4f0e8c97167722bd9031a269f2cf85cd759d5ed1be0d86ddd91eecd5676f5310837bacc18c518e6c7c491d593c3bd86b6c63108e46169d0ae69628fa89be70467569a50da0a290779e48c758a45752f77e46f48643856116d1b6e2ca20092e265eae4b2f5edcab1751be6430f39d2bda40bcd3758d68d3dfd010001	\\x86028bb0421e6bcce39d2109f8ab49027cdd3877bb1cacc5591142e7320b0bfd6a2adec98413b4f352e8aeae3cfe32e9f211f153254e5be56770b4ee20d89b07	1682843057000000	1683447857000000	1746519857000000	1841127857000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
25	\\x41b0c503b3dac4c8c3c2096af640e471d11297506e7fe41308976bd577877b36e47dca54d285ebdce957ae818ff1c76559b93e1e68fec7376159b6858de8367d	1	0	\\x000000010000000000800003c76901c9abb1456cc55bcc46e44686e6145a0d0616b1564137be124915eaea1662944475a544201dbbf1775d67fed06c95ca7c19d45552251e5de987d55b7588748b4da6b41d03a1b5b2c966bac3e417c68e182f425d607b62f9c5d3aa7f845f5a5f2acab254f0857c0965d598c28d7292a8c79687d84f6981a8172217983b1d010001	\\xdfdaab9a3b508616dc890f0764d7115e7fceeca5fc67e35a05a099dcc2be723893ee31dcd1bb1c2c178c3fdb65e117cc33e016e8022ec95cab3250ae00abdc01	1661685557000000	1662290357000000	1725362357000000	1819970357000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
26	\\x42b00dd5dd2938f3a51daf2aa6e70675c42e20ce1885268eb7647c64ea1e317072023e5923bd12e879cf82a92d55608fe1dcc20a4a62e96ef5bdd250428dc34c	1	0	\\x0000000100000000008000039836bbb68104694d074d2dd8b7e19233d7df5453e099afa93b464da6f7c8c2c55f87c5c39fc5e56e1634fe492e146e10d1e31acbb0b34df7b37f8c43d46c6fd3812d57aeeabd03535e9ec92c1022425489884c79aa47c8196331f160c60f55a6106ef0fd88cb4f88f1466b3bbf9d509b8f10f5153de95f5312c483c1b53cb267010001	\\x70950990316f990f9368c7316844e8b3c141015352aa4573f87b0e5d17e56c9136da0f8d9b5fbc28c8d7d08f75e90ca0fbc0cc6c11b356fa942e5fa58c00df0d	1679216057000000	1679820857000000	1742892857000000	1837500857000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
27	\\x47bcec50593acf791807f3045e0923b6d52e785878a87c183d62428f7753410d965846b89e9c7c851847ee4542ae7581edb5b6b99321a70319f846199aa46019	1	0	\\x000000010000000000800003c5ade7e2de4450d621d3bc5685d2de992e9955324a1a3e31c75d56ad93d60fa8b38f754a7c0408b506bf9fb116e0a8f91d245898673a171703a51e05f1dde49e92c449fce113de307bd1aaa7b4948e36bd5e44eb1f90c260c0fe00a1a8a50e67649acc9c1d8a4b2ff041a52e3595e9b1b3c6dc57f7545f1560f7bc7c39205a09010001	\\x2cc79ca4579e426797e1f072322eeb4f2d1aaabc37678bbd0f6651c2dc898a26cbab5704fdacb4422fce77f1004e96e642967d02fc3cf6cf12e47e5dacb3b30f	1660476557000000	1661081357000000	1724153357000000	1818761357000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
28	\\x4928316e28d093a5b5012cdbd6eb2c82c5b902a62bbeec0de39b73d2cb46357149230907b98230c770f44a5d8628d08a92a91973e27506433cc69b81418cd932	1	0	\\x000000010000000000800003c740a1640c7ba742d414e1a17d72d64dc0c90a126f86e16061d8ed9b9321041b7f89c3359f13baebce0b8c8892dfc6784ce061e66363dacd6c4bbf7f4078979b3c8dabf99828ec5f77d6a2afcfea006f290711adf7b6949ca8503099c8df164a4a596dc85d7ea8eb3c62be5f2de47a798aecaccbc5cf17ad12e4e08618eb8107010001	\\xe16bf36c8ea6ad5c7f9c8fbe18d60e898425e1440748c468a63680cb63f7f31046c8bebcf6b6c0e6aa6106118dda2e334c246aef4a0a5f665002d75dcf405d03	1681029557000000	1681634357000000	1744706357000000	1839314357000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
29	\\x5354b02a9fd7e9dddc602d4d363c7b4d9ce36306b75b98f7a84d337095806c266d9959ed3bd89a21fe927da3dadc7d2f097d08ef47260dd7a3665d3f95794243	1	0	\\x000000010000000000800003dda27447cc30c1d20dc8df9b3e90311cb766f9f77a8467edb6fe7e9f2888501acffce4c0a9576aa60ab5882e9c1c4d2d428e7e6cf94498d41c258c9e1abac311172ac3a5ff59586b205f0ae86e89b2efcc67367868b6e0b5ed871ca450b557ecbfec5315aae9decf96cd114e288f399f5aaa9d124b573719326012b5c61860f9010001	\\xf50a4f7ffc52d17e0d62ea71e8e6196e26d258f852e05f7edd2d612cb420835f31995b063dd8d49765d61864de20e7c104385c3ca877d2c9cca922a86f74d609	1683447557000000	1684052357000000	1747124357000000	1841732357000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
30	\\x541c7a8a5f2f9c0ecf9db2b20a5130408ee22573c6a8ff084dc9cfe2451ca7d3ec3038166069f0dbe4694617d4a51e0c508dabbb19e2c5352923035339d7e842	1	0	\\x000000010000000000800003b30f2496b7d445b4dc7dfdb8a748d23392e68cf00878e41f3878cdae00d0dfdc4ad90e5820b61ebeec76a33049c358ad8c50598721d9364bdc0e90142776e640ed990a05402366304612e189347933cd218bc95aaeca0a2c04c766439bfa962898b334175ef65f4eaa1f97c5ba567fb2a3fb1ed64c61734f41ab8a09055f43e3010001	\\x17be2bce4ce0df242081dc5498bc8820a08e73c94828e0ce2d526ebba6618c8674fd3a0ad74e70c5cf736edc24e233cebb24c8cda4669114619238a45cf3020f	1665917057000000	1666521857000000	1729593857000000	1824201857000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
31	\\x5524ae1678d05e584fc01df305757c78a8c919a71f6f4f092faa2e88036ac33c8d53d75974f328818d5340f7ad0947d0668dc30774635927783be174942e7c6d	1	0	\\x000000010000000000800003ee44449e9f48beef8d9c5561255da3ef3a239a5a066a82867baccca79bbf090357bf5af8d55b24fa5ecc00438b9dae0bfa6002b4b6e4171be3e58bc10c612790583e1eaedfbd9402a78beee6fa7ae33a5f7d5e201a780170bb3d3a8b7eba3d1df17053ddcaa11e0a2069f24fd6e545ef1d03a4c1649d65b93bb72dbb0ccc7811010001	\\xa3ad28f1e3841f5304653908ca66d71750130ffef5a2e1b07c303c9753dc76d1e2fa49ab957d3112406338b21df48b2e1d9e764271de0f0628fb0dcf97d87b0a	1669544057000000	1670148857000000	1733220857000000	1827828857000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
32	\\x56dc8c97f86b382b7233a942f12c5d1027deec57d90f7e5d87e3f2f29e339c1bedd77075d5ce6d6a4fa930f5f3d9337658e09b7079d51d5d80b7cfada9c078c7	1	0	\\x000000010000000000800003e52850c3c20c2429a54c8a0f8d35b3b69403771cf4abce7dee89236ccb713865d54ae8a7df93bf38bd3ddd03db9772dc3958f96f34b4e11379f50a8d9388684bb0683d67182cb0d674391a16846972156281f56a3b270884aea80d44b1b061a00830d5d28e8c458e2344784555d350e0dec4abe0972e1f092c5e09d107fe7285010001	\\x274c4dc9482a96123a2213c7fa45416cb8f5d0aac78785664846e2f91a784110a290a68effd0ec12448cbf79706e9d008f77c2778aeb9ac5baf85429f189700e	1667730557000000	1668335357000000	1731407357000000	1826015357000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
33	\\x583883948296c9fee0ac787e437c6963fd07fd59e3e9bd960b7634ec76384bb08383d1254a145773c7dedb5d750e1dd47f842a5c07789c7e23c5bc989283145d	1	0	\\x000000010000000000800003ac5a3a35bc1e782560efd94ffda32bd905561bf5bb6ff366dae530a7a991e17727ffc7420134562eeb79497fcc0a25c8e12ede234aaba6bce4ae16928f2d18d88339cb528f270f39f1d41a442c618aa727960fbf46d8a5bf6505ca125a3729bc0e1e7dc56418f5e25525ce60ddc5f30c3873f41ac3ca58279927a77c6a4afcf1010001	\\xb31da122b5ce0cf8c078052d27deac28d3a56c10620e752e10e148c0765309415b35237d12ad9be789665fe79cec403b438a920c00e050bf69d2e110f790e50b	1670753057000000	1671357857000000	1734429857000000	1829037857000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
34	\\x60ac2e47b67e79ac123d4e6176c6be1ef86d556b5b21243c7bcce9881fd6fb8547ad5e365b445f3cc2e3a803a5caa0811d12417056093291c48b6e0fe382c52b	1	0	\\x000000010000000000800003eb19a0f1b8c5b6ff5995530559a41d9e36fcfbbf42d89627856be91bd240bd3a46d429f41afc4830f92646cf18ad9faa70f467e8202318842bf602f8cafedc6efa6a785a3ccf1bb669851690161ae87a403b92b73d9bcf14abb9ef11e1619bcd962b83a9bc641e2cf8a55a78a891be4072b3cc1bc27e8b2c731c65a87bbf87a9010001	\\x33e34102bc2291afb7e10bffbec68c078d194ac152ff61978eafe893261527879a6a0bcc9ab0f77bb9f0e9f37b3730e43cd1c7910a111d2465378256ba3a7b00	1659267557000000	1659872357000000	1722944357000000	1817552357000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
35	\\x66b8af8617abc1660403e3ba45868d0438a450378c8078740a794030dcd0ec03164d3ad73ed0ac60da9f97478df2209d8178942601ddd168b1e1266fe250733d	1	0	\\x000000010000000000800003ecb00ef3b4a8aefd598eb897be57431c505813c935171fea9154c3d81e6121f1a426dc1107a1ecfa8d16f22f0153752f1130f79fae503d6955d9104c794115b1e8b12049f36830e6db3354f21acd3c7f78a9b88a3cfd9c680116d10ebb20ac409de0bdb0f62676a7dd8865bb4d5ba1bc8351e3003a03b5a88c31ef4c6f6e50fd010001	\\xc4f21599b8ecaaf9133ca930c4acaacadce74946ca4bd13450c0ff0f0997632c9a792698e6772ae23631e2257a76a1c357d5d2605a23be637d145792375b3f0f	1670753057000000	1671357857000000	1734429857000000	1829037857000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
36	\\x67b0448aef0d931df6e741e9c0db8809eb79ebacd7bf3fd976dd09281b51170cc9834ce16d087611a37037abe4ea3ef0319cfc7313894c49d82b31e9fdece4d2	1	0	\\x000000010000000000800003bbf8d4520d5889dadb2effaadaed3cb50a329a773e9e38d25cdf951faabe56da0cf571564d0d32f38dcd83aad9c2dc8c45b0cf3ed1d79e754452fec08895c286ee9059166c88b307297fca1d7457aef310e65a88f555dee4e7410710d6f7293079d265923f1412858925829950f2a77cac6c5e1a55e0e6bd5dc95356e3bb1313010001	\\xa577b3d145753afa8f866ec306a812972a8efa2d23ba0bd9d30c0e502875c581dcc314bb4cd62f9a6c5f3f52f96bfe7a43c25086fd6d84a555f88e12b4b3a506	1670148557000000	1670753357000000	1733825357000000	1828433357000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
37	\\x68c805b4f5cd6fb6a04eacd94560b5d3cf9553ebf9ab0705426d01e6572cc969d34bb81dd9e29607945dccf4b5e759700e4841aadb4c61392dc4e2ed6213337d	1	0	\\x000000010000000000800003e8976139d2cee41fe3a5cdb1b4c34e5e33d14a4e7c85d36169f748e0cd596f1706a8720259850d0428856ee662674652df36f2d76285183f84256e79c4d58bbb7797debbd637537555c112929a545df225df86655b2f115a9c93189edd68fba0ab6100274736ee66c980554023d506c89c08f02b7cf87cd3e54621691ea6beb7010001	\\x58123c92025e6f6e1e4e184d0905a062592688bfca26d5aefd0f8bc0d0a0a0ca723e0a306818cf59b80ac162be01e25ad5247893b29c04b4a7cec668c22c560a	1676798057000000	1677402857000000	1740474857000000	1835082857000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
38	\\x6b9c6585ff9c9cc0d9541c6a0d2949c566c5b41c20e733397e274e10478145cd0d4a4ca6c25a2d3b56e4556d35ca62690164ebaa6939995b20c18ff62b2ffe82	1	0	\\x000000010000000000800003c098c669e9cd6b24c44b2e119ccb11bbce9633b173c97c0bbed9b7bba85260959550ea6bd2b1d621afb426bdeeb999f70862fcdb332886f7126c842f1488d29b69c1ed123e0fe33c2674452b6f7de5421a81fe4698bd7293a02b4871714e1c3f2c7421b0f54b26110dfd2847cbcdacdc99c7f579da6d7fa1dcbf4666876540cb010001	\\x57599fa34537c8507f8d76819a49791f8777556b06310c2486da600b58edc5d091b11f316f844ce601e4d8f261fb4a03248350f8e55f91abf4b5796f386f930d	1658663057000000	1659267857000000	1722339857000000	1816947857000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
39	\\x6bdc0d0b0ce4c03479129efa65b8191ce457f653ab19fb1652cea4ca0472179ea1ef8cf9dc48112a199c47eba1297a2bdd5645a24d391d4207b2a0817b70a43c	1	0	\\x000000010000000000800003f09ae9471933d1c3b70f175e00dd41146533b631d82facfcd2b9f9753e6bf585488f825c4f5df32fa7860dd448ca8197bfd6c20cf6b7e26d2fccf9e258f18a204b0590a637dd16e35a9a92cf9c3a8978b053b399d8d837fa1685262dd2feb0f366c861940246d99b5d3cdf7b1dd0e63826b6fecf4e9ea9ff729572c78b90249d010001	\\x3b9c3b3b78c058861d56bd7a49df2049ab529e2cf7dbe51ea10f0d13b8da3e4f4fc394e8355b890c00044bc9499c5fd88d6cc45adbbdf34827e7e04468a2e50f	1658058557000000	1658663357000000	1721735357000000	1816343357000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
40	\\x6ca03bc4db3cfde86c1d50974e5098092d07de0cae55edc89ca31fdfa28302792daef074b288278f3337fd1a55a6affe6bb62de965164fa37f45e9c30e9a3ffd	1	0	\\x000000010000000000800003b96ad8e3e9a4f31315ced693098356f7ba78137287750d9ebc2a391c104352f0e9af7eb08062d186116fe877bcfddc75e735b2cad7b09fd85d2879c21d69cba0263969eceb914be3834deed11af6be416a48ebac55996f70c6566029da3a45d4e116c25692cb7ccfd4b5a6079b58a15555d0ed46c5b0fe7a160341ac8b0b6611010001	\\x039464ae350ad04e8baf44167a2593b11b404c723038ca0c16dff4a39f4c426f56a0f53b8779b13ee02b6223b487e4ea0ea81603434dae8025a53e743f56a50c	1656849557000000	1657454357000000	1720526357000000	1815134357000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
41	\\x6fb45ca71d8e83cf35aa12a953d646f4e06df5e133f74f366e92a5c0bf9f4e77abcd4a9faa3c344230fc3efb1aee40cd21002337c804962d683909743a1fb591	1	0	\\x000000010000000000800003f1b662e961851136e1cb15eeb938d289c16c531d7567dfb36084bca8aa0357231e11dacef59755bb9da638c86faeb1aecf2afebdd34ba646aaf43b46a4e19c2b063f3e61e5cbb17c2921545cd1f36efc98e2ebcdbc20d24a48310d059e66a043e98086bf8bb26b292a69db09b4d2ae0ee35a6deee86d8b1745bf2745f095f62b010001	\\xed825f41bc15d5f93f44f4d50def73a4bc9b0d6893846c1ab2dcbeda88806f9e219b6769f74a64f854a4be1afeca97b34cf96c3b050971cabbe4b8b892c3b000	1664103557000000	1664708357000000	1727780357000000	1822388357000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
42	\\x707c1b238d7f2a237447e4b62795e12d430de377edde6be8e4818e4b477fdb396784ec2c7ee1aca9469c92d2f96183894e0e6b6bb73943212dc4d5ea1a2c24a0	1	0	\\x000000010000000000800003aec741f3cd09d344b7f54354638510869baf64e4bc30bbb571606962ff047dad661dcbbbcb985b8c980d89c23f3f040ee37b9d84e4b6f9a8262d66fdaf47e8f35995952405c799960825adb096fd1e1e1a0a40680e5d5fd6d0f82582faaad02ffbe45849307f8ce3b11f246c3c2982771e1ba8e8834f171c16bb4c3092724d15010001	\\x24a591096ce1e3fbe9f296e8f98ef76eaac4b0f5a1df59134af42b38ca4442228c96bc9efee709447c45cc30a18dc1874b40ba4047c966fca3aa0718217bc402	1667126057000000	1667730857000000	1730802857000000	1825410857000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
43	\\x7364536776e716282a1d6f76edbab36ba9a93c3d03e7e2ae1e56529511c3960ab995b94513c0501f23a31a91e78c190b00397856cf423eb9d0a2e44857699ba4	1	0	\\x000000010000000000800003b318dded3b3ce737aa470bae6751660e7a1b2c6c88db361060ad25f0ab4c8c8a3c5c4a5346c53d2cf1cfa481da1da0966145e8fa53f41660ff95eb22738728e4ef63cf84a6487f65d6697a849b28e3d68ede04bcbf3a63700504afe027548de421e9e0147a4aba65ef197aca76e1a1aaaa2136762529570a425b5b626bb81063010001	\\x2c9a6981b2daa4eef8c87398ac930973e4d905570886caa3fe499b8a22411c0ddda71a4c3a8f6eb2bfc9fb341ccde64f19811ae7fad7715baf3add1818987f0a	1682843057000000	1683447857000000	1746519857000000	1841127857000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
44	\\x74246b87d5cbe6d782c55732ffb6bae18f5a1910e1c4561fdc7d16417b389087832d249ba438ead37c332ec28d672ad795eb4631ac91bbbe762810c1675b2c48	1	0	\\x000000010000000000800003cedbd7e1cbfdbb2d31397a574fe125bcea7693722f01a5e5c8be37e6772b942ded916420dcd3642460e5af4eeeed21be8b843c0225772986cf19317975c1ea0a0e2d841e3bb3aa066ab908b744942b6fc1269a603491e13ddd4c3ff7bd261d73c0b62f6353de69c5960598de801df547bdc0adfdfaa47ac9b9af9cca918c8ddb010001	\\xce485278628f8fd862c67b3c69722b009ac4e651dc6cd61c552f753386495d0f108489c9c1e94d76a0d122b98698fc53193f94f7cba827f641ad2ae70dd60908	1660476557000000	1661081357000000	1724153357000000	1818761357000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
45	\\x7478073894cd8c545cf903b7ee90419a4b037561829446be67003916cb88aef05c154cb45e2de9ec9818cc6f619d7efe42ff7582a1e3d14db076e147101b4458	1	0	\\x000000010000000000800003d687c47d487ea17fe4b509816262cdcd7d166a8dff842dfa4b7f5bb7a84338022dad2fe2fcd987434e59c8fb06bead57f2fb0fb3be734ddadb71f50fc4af35a2b7d995724a68c6d1fa7b5dc08f6eb6cf661bdc975489523a279b22bf2947ebf1a18001043f64270ce8d3d3c32ac962863a62a97512b3880e6440a35b3f32ff31010001	\\x50a13b9dd12513996c47c04432167d145f9c64c41b97ba14b85175c99e2902670bf9a895c22ff916824336a4ef2297afc64ec6bce4bb75768d1bae5b1b654f00	1677402557000000	1678007357000000	1741079357000000	1835687357000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
46	\\x776861fdbcb4c3fefc830fa0b2917ae14ff11cae2f3b85b4f20224725c6b459b748d829b20f7a39e048e1962523e5f804180a8b0f8588376f08e2f82aaf3bf1d	1	0	\\x000000010000000000800003bf17e4cefada72ed4ff0658f3bc2c67f4f426ea7bcb8bd10beca2f210db393e1641776569a167457aa1e58080a17d514d267e7bbef6df83477620caa52453e845b6b70ece2dd5dd8aa7f66d4282cab81207926348c5704cebe75414554d897c120cf2d34c1a532be794fe31ab2815ffb15d15c9f7a38064dd77930854a79d26b010001	\\x883b16c157a03a52c6f0dbc4338a8ff3f2fd5f63c93f5797b3fb7ca5e57d17bbf2bcd2129785db25a786665bfe71bd86d41b7e404f32336cf72820859a03d801	1671962057000000	1672566857000000	1735638857000000	1830246857000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
47	\\x7d049c931915821a0dd302b465c91ea689fc1992c82ebf51dcb8d7ba4fda8c943ea43a373db602e2d9e826fadecffb54a95bb68285d5cec32d42d7ddfef1b98c	1	0	\\x000000010000000000800003aaf3e0de672ec38a26a30a99028a284e5ca07a8d80dfb59586f88aa16705cffd370dd6d505a1f5716448b46929a6f4267f45ae0aa16f34bde2394dd6ac7f9045e94108d75b924a03930e45b1ee61b1ad5536c28b5b8b6c251207879511548c6a0168b32ab5a645c98876827fc48d05bb5bbf602bb3229432189fcb4465fe248b010001	\\x8e5b3ed86cb3b21850f5f57aaab2c82a98d50695aca8c419fec5fde491b8437961bd8cd27a4884581b260acc64b9691e85bb8dcdcc9dd3d7cac8858dac58f107	1662894557000000	1663499357000000	1726571357000000	1821179357000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
48	\\x7d04a7eb69f35777e56bbac322a182ef9922eb264d1c8c0358ae75a5a4a2669ab02ae05597be75792fe1163d33e2b96bd55403c0bb17ca601ec5dac8711b0af5	1	0	\\x000000010000000000800003cd72a0cbe68327fc332492b79f4238ad4a681a663b7597ea992e57a88abdae4439ccbcd713c58a80fbda478731bf90769eaeb740fa32562c6c5c9810db6a2e7400feae7bf340b90d09a8d74e491d1107eab77d7a871272a23f51eae6b5237e19dffe061c394fe8fac2351a750ce10c42abd80968a3123e7feccbc27c6b1ae7cf010001	\\x45e87b6c706b3ca29a8ef3a6ed5e2d4b683b4e960417348ac6b12e6bfa9e614813ba71cf18ea6da9a22a71671aa93aeed6b5762ef21fefdacbd73143aeeefe0f	1676798057000000	1677402857000000	1740474857000000	1835082857000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
49	\\x7e0c627b84394fbda5f02558b02d1e58cf45b49181d49b44f5f76cc2d3cb626419e95b93561991bba716f8f140151d7c4935e192cd41e011589f9c2c61cfd55c	1	0	\\x000000010000000000800003b922bccdafc0a075f41454f88855fe9f83fee229e232fbd3c204690315f90ff6781bfa132718d548297355c20b7aa2d4affde7e77731c9b09327fac1b252d969c4fdaa1e5421093f784c9884998cc0c1a3e5b5d098ae2b5b75c2d4133810a0b37554979e0156969221678a12ca433b75a1c16f45779171750760da7b4abc93cf010001	\\xd063ebaac6418da66badf44cfc7df52538deb0c166ca425f7cdaea72c63bb13c260ceb5458e158a31094040da90752d5c63c48c0d0658c2bbda0e2c06bc23702	1674984557000000	1675589357000000	1738661357000000	1833269357000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
50	\\x7f9445ac12d2f3233bb5b3cf75dda6352e203d3c21b83889af322b8f0b6c8cea9479ade66d9cfa5a1089207f50880cdb5a9afeb701f485be1d0130ea14eb9f53	1	0	\\x000000010000000000800003c500cadc1ceec6bc5a27ed05f3f091ed6796f0e7845e6cf417e4473a934f2336d0c5de959aa46b128256ca9eb6189f4bc5bcf51aeaff6de1b32fd4fd9bffc938edc686306fbc5416bb264ac1a5996b021ae8a58dd9f2a000fe174f63e96a4b5b62d6663a61abe43415e9318ae8de1f673bd0a7c09beb11057f84e4718ece4387010001	\\xcbb2e113a8bcc4c299e17ff1b18e2726f3b696e63cd867d48bc5f3e164ea69b2fe6e3c62b8037b4de485aeeff7d5bff59a2ba5bebf75c79b37d6d072dd506905	1668335057000000	1668939857000000	1732011857000000	1826619857000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
51	\\x8db027abc443d7d707c1c270fd9672394c6e83675d2697c7f3cefa6349fcfd56884580785b8c3984994ee061c50fe228c66bc38d9100139daca60579f1991c1a	1	0	\\x000000010000000000800003bcf3484c804c570167bdbfc38e274332158643b12cde503e60b713dd651be244a4275f4a936170234fb8c5980acdf6c36186cf047be600522d51a487d8c8f56334d8807c2a10d3f2376aa3ab4cb0a7d6342d620c7bfd26d1035a94bff043beeea4c4d965d7a4a197aba361d01ee6a84883274f75f43497780200b1eca2fed541010001	\\x5bce8c31ff0ef94836255fba2a95ce9f3ea25002a44efd33ef79197bf6252b548fc481942bea870d8ddec757bee9d0cb490c506fae466f8d475609b781613404	1661685557000000	1662290357000000	1725362357000000	1819970357000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
52	\\x8d8487470d9576751ff22f22d8caa9ef6ffe92636cf09f5f0a33caa147e8e0c564b00d1da6c29246ea9fbd78ae2c62988ae5ac25cb9b0cead96ad21cd7f3d19a	1	0	\\x000000010000000000800003cb6d6bb07ffbca2ac864d6ed10b53167f84cefac9aed1a439b6b8c50243cae565bfbd1814ba92508d02a2b9024e2e43a5571a083d8f372877812d0624e70b072cb858cc32b3c4b19714f8c8804b0b75ac7d9f1069702649144dabf8bc616b7239b845e9689bf30b57cc3904dbe4f6d1573ef293797da1dedf11f29f07525f52b010001	\\xb2ce44bf31044ff5096aa407f7792e41f08cee7dd07d5dc59a9c9776e9f0e8f2ad7072dfae4bbb71c0654cac24ca16b1163612a0494faf6b00722cb467b59305	1675589057000000	1676193857000000	1739265857000000	1833873857000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
53	\\x8e04ad6ca6d66af799ca74f2e17212c5b51404e1107a8776f8782663d4047264d7d9dca402555ec6f26394c50f52362283d8f4a3e03d241b7042e81328f457c5	1	0	\\x000000010000000000800003baeacad32740f974e23289f009f2bafceef14fb5fb70bf7fb9b9795a7b2c43da777f6978cbcabb2c98a8b69970912349d30032dafa29cad4e7e0c268475f16cccfaa0ea39aea60c9d59650adc7fb33ed27327b0da8da3e184f799c00e45c62007a56e59c3472f60493a076d2f6e66f350c2829bc44d81248f434de9e3412311f010001	\\x3a5f4f4e1081c4c3d08a43c1aa3442af3bea6196a204f0b67d1ad3ce37af742f4f55d5b3be848c764d657275a22abb9d79f620ffd17d250d52a7f26b444e2004	1665312557000000	1665917357000000	1728989357000000	1823597357000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
54	\\x90803f10bd24f9fe6f5f155e7aa9e1602742d4d9e44cadf02b5b43b8609ec671a2fa1d0415390d41d0ab08e7b16a217147cbe703c88ab2e92de52105ce28c0af	1	0	\\x000000010000000000800003a0acf0f0fdeea86ef8e4b1180826ac07d38bae89fdacd8ac509ac82a8d463e7ec73bd6f7d3003e57852706bdaecdca6b3ae5753687c66e68f7cd7e5bf133162f76db713f0fcb43c310b76ef60e7e8863e4c02b852a0733fb589fec2267cfb7200ad25e1045c7c26ebc4bf7d761557f8ee3d9f5a3544b57259d5f4090b5fe8af3010001	\\x748b3e7adbfb3ba11bfadb50795c17d0347e9e6d77dbb6fac2a897cfc63c3047deef4a8e015c4ab9593b44053a0dbef85aa8ec71baaca25be8babb96d46cf902	1675589057000000	1676193857000000	1739265857000000	1833873857000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
55	\\x916c9eaeab8157bf4d218cde52cc6bd38aee98c92c7f9936d6fe86bfb9300fcf073e94e3a6ec44e719aea66367a4c2f689cbc577b984d5f484948f24826cf84c	1	0	\\x000000010000000000800003e0b232f4bc8f6927bf128aad5e7bf7cc4f037161bbd7ff8f6d04a07eb55937c503ef5e47c98b4da36041523deb3cc4bad64e70f3895fb0658bde7d1c2fd0a1ccbe4cbdb759c7d22ceb3eb3dca6c38856819a8aa76822254f946a10d7d49ca1a3799cdae28d69e67b190e22a59018b5ca2e0937fc2c3716ae30c7b92780421f45010001	\\xe3eecc3bfa23681b03a94e390b7b7671630bcb66661e1363b748fc452c309e51657fa839aad2a5e803b4d1840a2604a1c82f1a5a229e8b04bdeaf468ef331902	1678611557000000	1679216357000000	1742288357000000	1836896357000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
56	\\x98e04edf8c716462957c977a0692dd93079af163a110a85526671950d8f097ca8f8cd9d84bb54571d93caa21a809a588e938118e1ee4470d19d010e657d9d832	1	0	\\x000000010000000000800003a0c6799afb148ccc064849f547801133db8e20644e65f0114679fd14776ac8662d32a2357c16a564f9ea0b85cfc71533892e0182b8b20ba469c9b4bd6315fa1453a1e22d62f9b28e75356d46d9373ba79fd2c17c6e9f0079c40359d2845130ba5fa42732b49b5f341049fee1f428fd532633b94e73e308df199c3646bb707727010001	\\x9094821e50a9ecd1fcf515cd3b194fca46a441a290582e63a617b796827d2ea6dac18157200bd7943c1b8c0b390bd310d27f05c24656c1f5f65f9a8ce4bf670e	1662894557000000	1663499357000000	1726571357000000	1821179357000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
57	\\x9a30f35fa4b0ebb5ee2d0c4541e9852d0e7048583935c23be57ef77cd70bd294aa061ba5f6d64de9cf9c3b6153ebf542ffccc560e4022daad3a3d0ae4a2e1aca	1	0	\\x000000010000000000800003bf9a3408e11ca64228e285cc13e0588b8a12133c984af575ec64dbfb97a61a40c0da403e1b7d244a3be8f9faae0dbe1a6a790f5526d2fa88d4d2b8a63d89f32f8620570508bb2ead9af47a47335da327f7a44aaa617c15d7b3207fc09bef8267c48d843e2f79858a5170dd4937dc209c0fe1493ecd9d2c829c85c0460af08db5010001	\\x8c914e9b6aaea4df3abcf4b9cda1570e862fade8acb92bcbe5f1509616833c6c8b00acb589fbdecb119488f67c50e1a1a483903ecd51b5e6026d9e560e94d30a	1655640557000000	1656245357000000	1719317357000000	1813925357000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
58	\\x9bc8afbb9b647678dcd5116e9ae6f6233d2d9732e66caee2b32b2872e20c1f9b844e99942541552559aba9607167e30d8c93e9bb4f6909219602ffa8cbf0e381	1	0	\\x000000010000000000800003bcd5ef3566834f2189416ac9c52db17c596bfb1b48524dc7fa53c132d54bc22007adcb562486983db7a4d41d253d116863a6e6433d78d26871a1c37be1091350c1d4ce5a7b8c90768857a8f22fe8d750855415a6ed75321a2b05e955877fd263d30aa8584761ada04af269c6ed44a0af1fe92e30c1cb445097d2e36a7cbd9067010001	\\xb1c30b3407f4bbc81eff4b2b8e5e241f728d7a76ad311b76ff37c11f7998309251a78bb1b0313c54cd681103567344f58bc48435378c3e67a029daca068d0a07	1679216057000000	1679820857000000	1742892857000000	1837500857000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
59	\\x9c0826b29d61f7b80eecb560a28d38a2202550a3c7ff3ab5d04a189d88a3aef4e890fd9fe2376f9964a8c4af0246c28b92707a28b2ade4dcaaabd24c2b661672	1	0	\\x000000010000000000800003e310f7747a314a9bd535de3c9047d453a5128854c581340429476455f6541c25be421b11cc06300c284b0115cfd514f9a9f2aab238436b7668d98aaaeaa6a44d8268d274d30e9df3c9b0e63adedf1aaa0f771f524719da4a1f0f5d6a2b01cf8e250f776f6af87babcdb8fe671256fec111a9f7e14d80909634fd70462e4feaf5010001	\\xf79f663c9e7456b2a5a5220f593cbb37ba0d9f5ecae93547627c36db73ae8a30067858e4675c3395173aeff17bbcc4f44be5594738029ed202719d5c8d65860b	1659267557000000	1659872357000000	1722944357000000	1817552357000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
60	\\x9c8c8690eb9ca7a05799b819acbf0bb21316713d4a1267610e35215f73441acbc52476831616262f0570ada2635d75318b8d9974b0a393d9f9ee762a879287f3	1	0	\\x000000010000000000800003bd32e8c442c8297c30526a9ab66a176c7149e0e2690ca49601957e6adc17684cb9f13ad3c311a78cce0dd08f887193af9f4400143408c738567ae32cecda4cb281ab8e54f9afd7456d8e61dd4272ba37af76ee27a7e59e6468ed2d6a058bab398bb33243b978dc35a5f12d012892d6445b76ff4408be0a4299a292ac5e4ffe0f010001	\\x65568b803ad33802bbec7bd80a96d7d355bb6d303eae5e3ae7f586ff4e3eaa53be577151f351dfa2af21b2ba846c4a790ff487fa220c4d77ba9ae06e2e33e80a	1671357557000000	1671962357000000	1735034357000000	1829642357000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
61	\\x9da45dab4ae4a6f2fc78cb0778e491a2f52b0a83488981e4c6647659dc0c3d21468dcc2e4fa7d21a2c6b8fa06d711828fad9bed9d12d8100f3138400b7f9e8b5	1	0	\\x000000010000000000800003a3cd51263182fc9636632ad020834dd099ac5cde9e5d46f992de39021ceb5af2ce7ba44f59cc6ff2a1d3941619a0a2c60416c7d972213ff9573af588a72718cd6790f6c631ebb3f644b38f6f2e49b309503e03257a9d5c8e9503e65817b436b31146f8f64c384db6b5b2465b35f10e125b27ab32639b8ed69e96945363106675010001	\\x01c3590b2a080db2758b55d83e672f682b1737618f15415edecaadf82b2563907fdfd195c9382e339927fa777a379e9b1f4b79b83895fa5beddb845b4bf7de0e	1674984557000000	1675589357000000	1738661357000000	1833269357000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
62	\\x9d0419b01473a238e72c723a867ad08a1533c38640fee487b554f8428d0cdcd9f3a88aa40593ee1ae4d064929da41d90d1d645ce03a47e3564598bc4ee5978f4	1	0	\\x000000010000000000800003a32c12df2d89bafe825ae0e22d0fffab87182149cfe6583e4ca5ef35b78d8b0b2b53718b735cd9987a11158367dbd369615c99525230b12aeed36cd687528739addf8a8b676d493ec83baf7d70fba0b62241c0ff016b2a38c1b9b6144fce0a8d6cdeac613c0eb8bea409484ca48fcd4fbe4281019044e9b28aca88719f218835010001	\\xfcf6d399e0fa53aac3d58aa3398df6dbae823aa17b5a6a49e467682843d6e512f98e0b3029aa1a4c4ff743fe8d4b86598a001ef11461778826075bd822ddca0a	1669544057000000	1670148857000000	1733220857000000	1827828857000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
63	\\x9deca5f019077e7c68035b16bec9e51f3f687a4c52d9488913edd25ae85aa864cbab3a4795d21eed9df1c377ee06936ded9cda124ff476334bd06a6328ea999d	1	0	\\x000000010000000000800003bb052a6f78687b604a9b507165bebd5b0688ad7f07958f72b14eb6360d0ca756d41ecb0968d3be08526b9a95d5eabb6c6421e7217cafb706840d4788c67b092090264f1aa8c0e885d9c0096555fc5450ec0612ad5f0a684126344cd1b3f778a69bb7728849255067871eb2e9e5dfafbbccbc68aa26f37dba8d3be610c435a729010001	\\xa09bb67852df01cee375d1a1ff0b5595746624c566427c504f89720c52161ed3dedc991f96b2b44ce7a9ddbba39c3810fe4809f5d66a8c311371c3c2f060ea0a	1684052057000000	1684656857000000	1747728857000000	1842336857000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
64	\\x9ed4cc8712edff70a379e5b3358260b08afb9c0c5db9a438f67a266525be1536ebf14c58d58ab41e6cd5ad461fa23a59cc590741526d89061d1af3d7a2f0fea1	1	0	\\x000000010000000000800003e0e9fd29a3b6bb7c1dd1178ac9e72c9eea12a01239be5fb5424fd2b5c980a114dc76ab8d0cad8b8da924b5fb6e484f6468d5b679e9672f3d2f2fc64f05225b11a467c00fbdc2f88472229e47cd4812bab93614f02ddb650d7be0a250d0febd34a3c094f6c69c4db3e36965d7eaa7ccfa431beddbd5820e7fb4de5c29a5774999010001	\\x5fea40e6ad0781ea42aa6402f97c66da904ec3ba3e8de7f85876efbd255017c02e186db1c8027869d931294f06ab9948318aa13aac925b9ce068c3881f88ad05	1669544057000000	1670148857000000	1733220857000000	1827828857000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
65	\\xaaccd61d0d7245a536bfec179677e42c8ffd0f1c72b93ba9c413c989cd8653ff4513c1d18f8c7a1dab9c893a59e1ac8b98382b96be13944e85ca246aabfcfefe	1	0	\\x000000010000000000800003bbf1ba79a16f3a85f4b7b4239d668d399db2264856c1daf8bc46da813fbfa4988b1d04b1bfbd4a7510cc21ec10e60fbb29a5332ddb786d901719175d1b3d8efd47c69d8bdfaa7b47ff378025d19add303b28948d9ad99d866c23a77a67bb08aef1e465417fa38dd61f8d86901157da8317fca1e3ba496913fd42751a05bb8113010001	\\xc8d51d922ebc8a93230b8e2f3cf644c404819d8cd6ed07d6c67195ea41870d3beaa9f582bd2a2c011641aeb71f7ffd9e3219a0bb67ed39793b2b2a7cd4ae5501	1656849557000000	1657454357000000	1720526357000000	1815134357000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
66	\\xae702901bcce8800cb2179cc843d153ca2af29b28886d2b9705d4d0e3bad29bc3618b4c16182fc2bba3f9d7003d473f87d6bf9391a31b5b26b18089de57df95a	1	0	\\x000000010000000000800003aee4fedbc8871851ab9b564a578f05b3bca15794e0085ca1f760ef6e3eccec9ddae4f5b6c8a70245df13c1ee67f87be6a2c182a0dec4ad10f28786976ee5f1cae771f3921a230946932644284634500a859f86cf53c4c257ee6b6699283502b37356e6738014c6649b95bfc5edd40e93a7a3d83199b9ea07938f9ac1ba9ca783010001	\\xe814a82c5eb53eb1d92c9c7d65997941d4fe4e86b63ea8c0f45643a392c8a8c36f45079a14d126ed453a6165680c48a1e6eddeb33850a2c4d97fc883c95a1f06	1663499057000000	1664103857000000	1727175857000000	1821783857000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
67	\\xb428ec92f7bb463544c38b9fa6b021bdccbf14989b5edfb45f3ce73f260e13c3d794f662e43d42f4e4065bda1c7443df13ba00cd3346a47d1eeaf8461350c463	1	0	\\x000000010000000000800003db4a61bbfd0b4a6bc36a0fa936d83025dcd5aab187802853dc2119a2abbd7f7d120beaa3bb4e15a92cbd480dbce0267d882eab2c2afb810cff23cb3df054b13b3e4fdcd505f3157ae5bef33bae3a7da8926a06a61b9552b3a72fcc8ab98537299ef0c14fdd3e9f867252255c6a3861f885143c4399ec198ad202342c7f58681d010001	\\xba8a65963f28cc1ba7392e9fc78975cb9aa45bc14a639f46402e5cac8b23bce0fff895eb9bcb7820bdd7106eb2ba0572114ab290acb7a92e403f16964072f605	1662894557000000	1663499357000000	1726571357000000	1821179357000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
68	\\xb62cda783c94a4b91ce89023c1629355172223068c41763cec1b802299852accab195308bce16fa4348f8557c359fec56874417f6edc42c08893018134390ea9	1	0	\\x000000010000000000800003d5ab662e0bf78da44d995a3e32f372efcbb31b88df645a1cea8dd7ef035b9210ef83bef19667c400c63daa371f08563e297e4c442d063ccbf9b00e419d26da54b0c73f2237523eff0e6b78d759ccd94049cea67faf8b4828a3c275cca93efcbc98b4950109a0848d1dcecc129451a235797692eddaad9564796ffb139dfbed49010001	\\x3122dd79ff1b53835e7968cc9646a344c6dadc9678c300256c22163826c5f17b294c8b71a7a3492f54b6fd3c9e5da14b6aa4af66f01ba25ab66d9d775990fe0b	1684656557000000	1685261357000000	1748333357000000	1842941357000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
69	\\xbc380bf6a39ddeffd5ec5bb8d7348ce80cab6f75f5adf5be7a84f0f0ef2a8ab2b0c22425e3934d8d43d76aa0a72929cf3b68ebda04c8e1a928e319f8963eb057	1	0	\\x000000010000000000800003acc9d4203c8ba9c0b03669c749eb9cb2f161d400035095be8266c9bc25fc1ef3f71e53950c944a0d2593e44ab9ca692e7510fd410d2e2122e611909b491508b5c3064c695069b5acb33dcacd00b7e1e9e470882a5472fcca3ed0003e84166afcf39834648725abbc86e65245478f560809a1e8581017eff2ef3cd93028f7ad03010001	\\x0bfe22eb352a769e4d9c7016843fae1e2c3c19971925cf17f72d0cf901ecf9e848249cf4208214778ecf9c82c40c28200e12bb66b8c793410c6e954c6248220b	1669544057000000	1670148857000000	1733220857000000	1827828857000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
70	\\xbcd8f8a1f0a02a09bf6f40fe494f80cbfe64ff67947f34a310da91ff263afc2f68d2db60e3fddd9095f7c3248897c37f5fa94b12f47eee54162eef482883b93e	1	0	\\x000000010000000000800003da1d380aad13013d335b3cce0f4feb6f7163e43225c84a71936ae8bff99d5b4f1c2efec1476bb72d048fb99e247dce4d4c5dd2fe166ee7d17c73e26d8b4cf8e18a2d8aebfad26443842534a833518fd6dfd1de4eeb0d2d3130ab2d49e1e89136c227540fcbd0ac954d32cf38c4e0cd9f7a2091515ba3c4752387c0a910d5f343010001	\\x81dd8cfc85dec2e4ee4c23f3f73cdfc3d7e7da1fe4bb852cf4688a0f669bbcc2735e3d60b952f9037b817f161e8a5b88ef0fcdda9a47350fda7091258179680e	1667126057000000	1667730857000000	1730802857000000	1825410857000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
71	\\xbd5c72675d936ae753bfcb2faccf226c6d7aaab73478109f804aa054544ac06ec896df21871f88bd40dd2b7539f837853aa166bbf6d7dafdf4a0407ed9068a3b	1	0	\\x000000010000000000800003cd71d9def2752242ed449fe9dab331452ba8ad5cc95ca72b06b6fc3311d6b4ec9ab94593ed8a1931e55a35be011c3f0bfc139f7edaef0cc3ec82ddcb29094372148610d6d543d9d64a99da0c19de109446d01c7295cff1c7deeb71e1203a23a62bb1697060fe0dfbbb04af91fa4a7b0054f3d03bc38a05e968a3bd683ae4305b010001	\\x47293777f5cec3160a1dcddfffaca77c1579d28e4e38907e9491fb17d59bb620caf1dce7188681e4af1c796e03f29e49e112b39f6ba0ae3a6f6c45f7e500f308	1656245057000000	1656849857000000	1719921857000000	1814529857000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
72	\\xbff416a241d606cd4a50d6f72430fdb7cf4403bf246b266c6503ddc7963cfc087d36131c537675210e37920e9821143c87de601d5d0850f72b2e9d0bc25d68a5	1	0	\\x000000010000000000800003a1cf47a804707a5488c2aa6d54558a1f826ce15f9b704072634ccdd2d3a3c831a8ee3a3c1a2f51730543f578b38d8e8e512de2370ee7514b673e7a19fdc9e5356cf20ce0449fe3d9d0d7887d94ef9bde1fe5836d9c7cea68f3a7b0b0cec742bd05347bebe0bcc6b664cfc4cfca8cfc74bf8135092a5cfa0f5f6d501562172b57010001	\\xa1c85d2bddf9c7bd47d5dd680be15cf09380eee2ffd8530a41b4944f213ac1002267ee216d87dc9215f48384999c384372ebf958c6c518a53f828a4313fbc709	1661685557000000	1662290357000000	1725362357000000	1819970357000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
73	\\xc1c86cedfcee36e6f9404ed70c167f6a515a2d913fdbf01cdb6c9af281f3f0c85e7e247e49912c27284991b27af91c28a1532a891c0e47c0b70aeb36e9a5be1c	1	0	\\x000000010000000000800003d3341a6775db9a90082c4db96d25502b311f96bf6bcb0d9d383f5ba127fd42ce6ca4f766461b8396ec52ee491813d3cc3e4f992903fc6776e40cc079910a6b6081c1ef874dc4db0da71e883ce98d7a8f10c150e9189f1ec4ad7e9c724c86db0c402db3bc9106e23b1bc62b8119112789b4c88a6a6dfb0d1ffc0cc8320dc0ea97010001	\\x6fc28845726fbf24faf19a2cdb8d2d23adfa776ce3073466ee618e3f29c34c12f732bf9ff07a01fac1d11bc66a7b538b68bb3dc95ecdd7c3aca7c13c957e9c0d	1662290057000000	1662894857000000	1725966857000000	1820574857000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
74	\\xc24cb6d746ec7dc6b9532bd8d5bc0c33e10465c64e39cb09f6c907ce1abf15795796c2adcf8f6e92fc138748f45e7f9491379df1c57f789858e8c4f9d2728ab8	1	0	\\x000000010000000000800003b41479a3ab43a8ebf55fd3baf5b994a233de61a8e4a128c35d4c91355aba6a589597c06c9463f5a1d1d1cb46b196849cfba334922000c52758a5fb8a7ec4433aefc3d490451afe0eabdc31b5900d86bf83912c60925088dc013cf177d2e73efd49ef6c53c3940bc8f2d064ece422ac165c15485428c7236b49767e2564c8c2fb010001	\\x094fccb10d1f1c2fae5caf3f2abb41519dfb977c793effe804b46766c7223e0ca56ab3b0f5acdecb2e42c122dc58b8f83b6b67bcc612d4c71f98b100c566a007	1662290057000000	1662894857000000	1725966857000000	1820574857000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
75	\\xc2fc389f8e627ea019b967b508fdf572550c775d8cc8622e45a80c68dedbfed7397293b30ca50059acdf785162a843f4d0f5ad3d69aaedbfba439cfab361f630	1	0	\\x000000010000000000800003e9275ead8cddeed936ae6e28259ada5f1a374c280c9ae8343c1d9fe378fa2fe438b0207811ea192be7b7fc8fdfec78ea56914f4273735c187d56346be2b9f378c5a9cd0d0cbd83c8f2e9f36e45f8e821bc76de5ec505adbd474eeab1b8f2a9724d3d67c8110c8a2071af49ffde657c2dcc7253345d2e639fc4457058181a287d010001	\\x35a043382fd2c88f7caa7dcc586f27e6e1dc36a0d289c8f94bfd3de83b57064cd97578cc94221f1002d3bbbae262b9dbf2ec1fc22837da3cba74f27ad1ce4f05	1672566557000000	1673171357000000	1736243357000000	1830851357000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
76	\\xc3441d74468c060560885a32dfff18f6f73a87754f3299b2309772c320ad196324b8444e31a0a28fc246a502c49bac80bc4a31786f3d539a2e8c0bccfc02cf02	1	0	\\x0000000100000000008000039fa5a3601afee7c26d5fa5f174fa34071167b38e6122de6131add5d0e936df2fdc7e6bfec7269ef02803ad8c90dc216d01118a634649b3cb35a671782f2ca56a97a8150504b3eab6ac127f0a9c6f52a8c7ea4bd49ab4d3d01703edf12901290ba768a8be0cfd56322918663c13daabae1c5eb82945475a8c296f058be8587a8d010001	\\x80b95c27fa6bd6e54c43762b06d1e38cdf94ac19d96f95ac51adfb142b14f02864249d9788d4c013c10b147dbd4c8b8c538fd7a5276efa74b867f3be8dc18b0b	1673775557000000	1674380357000000	1737452357000000	1832060357000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
77	\\xc518539ee9c07e3df0059cbb7ffed64e266364f63da7bcde1f20f2920cfb07e9965c14c7c85278c504d8412715856be380e1a65a1f661af5f4f796d52f6b646d	1	0	\\x000000010000000000800003b394c6d79ce5faac3de2009b437946561333666cb33a70c681d5bdc420396e7ce0c1a9a8fc83408f9a8e45014c82ffdfd9720421ebd6c9a828331248f9d25232bf5eabf1482b6f4ab0353899ef4bac6bffddba0938b7c6309dbb4e0e60d2f7bbd85dc97cb31cb94a0ab20b790f4a0fe7117e37ecfd862323f47edb2e2521c0b1010001	\\x45ede2664977e55402442a86fa719da32704db63426c8c0dd92e19187bba9d88de5d06abe47026fcc48248fe2abb4becdfca35280465d24d0c98ec7978419c0f	1655640557000000	1656245357000000	1719317357000000	1813925357000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
78	\\xc69ce60fe1c4eac3d566491c3eb71f0bbe8d871d1a165380c5bc700f4d2baaa5daea7956b6c74065f8524dda3911c8e053b05299cb8997ee097d6b10b8a9a7f5	1	0	\\x0000000100000000008000039e10d01945ce039e342fbca39ea4b2da26c526ca7381fd42ea44ed396ab4eadb2087a0d581ac6612d980d65380a22a8ecb4bda094b18538ed6699a2cb6a045e81400df7df1d5b0fef19e76ba2bde1e09c387fa40e606607659bfa3e89a5d545b68b1da9f7c18a672a02493b09d36709f20e3982b1be0e626285b6aa8b56b1f85010001	\\xd2084e4e24479e8b1c49cb136cf240a7bbfa7c0896a712d8723645a8012e4d1f2a6429b6d69381477079d03567818670ead44e3899b3a8648e0cd0ebbec50a0e	1675589057000000	1676193857000000	1739265857000000	1833873857000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
79	\\xca489e1bb9bd47bb071ddbdfd6b62b93c4a64494c2d322ba6dc8337638114934ead60348a4b5b6cc9e8c4a07308e7e2c1efe7d29ca311e56e9804715f1eec9a8	1	0	\\x000000010000000000800003a715453d57e369599ef3b91b59db0468df815960d413b1c3bf247890376aee4353485125fee1e69248044189156cf5c5414f82ba86b82a761db210f4a10f0b6e8d6fcb578609ab4bc419bfd4d5b827923aafa2242d8ccc73b567dca6bf2969b83f41b7f8cf01310f9805426e767a3093ebc0258099f87c9ebd5527945c8022f1010001	\\xc5621b3c9a5f269f36684297e97665e79fb799c0dfc46f51a2110c040c31bcb028e85e22560c55ac43395c3cdcb91347fc0014797b46e85115a0eb7369da970d	1665312557000000	1665917357000000	1728989357000000	1823597357000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
80	\\xce383aa17965cbc570e17fe52a35949c8d21654fe238b05657d958f25024de7667dcc8b5e8f7b0ba33493129d866ec9a707a00503c0980d415eab18d70e217ba	1	0	\\x000000010000000000800003b99e6f3ac8f34275e29fd9aaf91b1185e38df572ed7da3140e5a25c048a2baae9b845d34f02504120cd0262e8aa4488aa4d3d63e823a01e78dfbece3278fba71425caf68429fb0b06c0ce57078f7fbf1fa325596a95e26ede56bddab6de40798493e56bce79894ddf38d8237eb450eca2193df618aaf5d2a4e4208467df02a7f010001	\\x891aca9aec70c8699638a359f14ef4e87fa61f91df97866a0bfcd4afba86e25b1d7e7a436860896f44c41bb4b2c90666c5ce680eacef5e1bca25ed8fcab48704	1684656557000000	1685261357000000	1748333357000000	1842941357000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
81	\\xd1d8986363ede28c625afb66115528e7cf777a519c4b834b1cc95d5f9841386e30a0edfe554bdfabd98bb50a0f2203d6f3f81eb0d7ebd3e45eec276693d58ba9	1	0	\\x000000010000000000800003cb4875ab86cfd4cc8a49cdf24d973c15f88fb00ab5ad6fa6e98b0b2f5644661bbf81b1da3f60417fc538253414275c09dfd37a4ec05d27d186ef18070dbfb8c628919778ea1b6d5752c11f7caa9548408b2d0f3a28d6f94679204913967a4e461f22e7d11223b22ca3bffda341c1a1f09fe25179e84bd9c83181cb1fd9861769010001	\\x226d2132bf470ecb72413989aafd9e64dbe6122c3abbd98c97587bd016b3bb3790970df7affbdb7a7f7818e776728482b47ca5aa65f689e77cd8ca12d4ff0b07	1667126057000000	1667730857000000	1730802857000000	1825410857000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
82	\\xd31cbfe227e4291ada52faa12f7c13939e95062bdec4a2965c63ce75ed7c1e4c37404033d9597712c8686243023e6d23d60d63db946784a618fa154cb4661aee	1	0	\\x000000010000000000800003a888cc910384fde72b02fbc64dedd42760157829fce074f6e738fb91d61d8a26973142b93d543ff7524e216afea5567eccc49e4a1fc562609ce70deb89518c584f720daf32fb540290fea7231df461c10ff82965e3f54389ae1fbbeeaf0d595ad0045cf011a2218b4c2ea8b7dbbc22336177e4a364b2e9fe2571a71cbe93f30b010001	\\x32b04855e8f9e91250bc345316683fab1e44d7be6c99390b643bee44af9119368179e1a6d7843d53d800e6fb3679746bd2daa7d2ce919c719defefe39f093801	1674380057000000	1674984857000000	1738056857000000	1832664857000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
83	\\xd388f3ab66d218ca1a68f5f7db01b4528653d29fae60cb107799820c2c73b1d08b7fa89fde4967221e8e2515c68aff992f4eb55d833c58947cbfcff2ddf45b15	1	0	\\x000000010000000000800003c4dfda3c5446e87c8d852094304b080139f03381fb1c55ed198caae8f8ddfe9239a96da023802098f303df79dc4d2163649a3f42e00a594084a06cf37038fb1be2cd9c71ddea17b6aafaebee25c84a4b43782956ed024b8b78e5b8160f4ebd546c59608fbcb4beaea21fd518990994268f298a7ba167b10e3a2992601615a1a9010001	\\x46b8f16c076937c9156c72c5a3b356e95f4ff52205f7c01079ce388ca69851ae1516de909833352282258f82605e156c696516fca53d18ebabb633f279458408	1668335057000000	1668939857000000	1732011857000000	1826619857000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
84	\\xd82849a91a2cb61fab20282e54c5774a75f5ab7829786d97d15b34f40cbdd409a6f2600b478fe31fc1daae61a24b6dea5a875db4d164a762b3bfd6bda6c7f6ae	1	0	\\x000000010000000000800003dacff6cbdeaf68e05487d625a206675bf9db6dac6f9ba31538d66d5d12a48d04659548f26b3590c664e58599a023cab95ecd8ee4fea7ffe3890aa4f49eba2ddce06b9f8d8ce9e2c9da8ea8220d275b699fdc765d28279f53a5f59ccf343d42e9ff7bd885abb5f232658307ecdb774cabd97bdf7f15a155b2f9f32b813da12a81010001	\\x4e8c720fb181d23d11e59c012edf34e59adc1919f8120e1054e695742402b5d312ecc3097ba01edc8a6af83f8159833c0cd743718f8952f016bb75396a525f04	1664708057000000	1665312857000000	1728384857000000	1822992857000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
85	\\xd8144e3a9646a632583b1511a095209c51bdac72ffba01c01fd9a2cb2ebcc5d511fb8ede5bec7730e5ed1664abbe67ff3f970c27cc02f1b7ec8aa5dd61c5acab	1	0	\\x000000010000000000800003cc2df278a77ca29a200361756b021bb375f9fb233dcf1ec3e1c784b4e66a8d42e75359e1191955c40aa7f82233c5285fceb1c13a10969d53fd5d147ae1b9264dda6ad6474588e53f3225218851fd2c5a704a8b6aedffab6c1386bbaabd3dfc8e7d4b46b7726d0ce29cff267bf6c1e53605a0bc3654063815cdb8e55699f2252b010001	\\xd69bf53a1c24c0679b503824b2f85619e169e0f01f4312d2883ed6df006008a327da4dc99dfc9f530086739912d398f496a27d525187a1fa780fe32e64b7cf05	1667730557000000	1668335357000000	1731407357000000	1826015357000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
86	\\xdec056237e51b3852440c403d2abac526ab10fb25adf8908f990faa945f1dd5c93f621a3aa6147d3ff2372d1baf4fb5d6e1d95db7f0c593347ab9ab8e55f7d19	1	0	\\x000000010000000000800003cfd416355111f58e56bd0fc57232fa6527668e43f757cbb7211004a4800e5caa3e2234ba41d864ae7e37f476325f12fa19398a2ec68bf1a8e1935e00286143fadb630742b86aa045ba9f96f19663540d97cb6d7b8ba4b29098df721e9bac6d33519f00ece9721ed6f6e1547a3be02a51f84bddfcf2154e7068554a787f972529010001	\\xa7842a0c67b096d517a09c669069c401f3582bc407ea5669a091b05101333f10fc9887e5782149ed63543506f9fc999aab4b65d3cba74cfa2f7a475a75045609	1666521557000000	1667126357000000	1730198357000000	1824806357000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
87	\\xe288680cdf1c1a6973cbb985da0cbd43624eef50a37f6379a95434b7088a1c1f478a092be9bb343aa6c36fdc4a50480ce7f1503be2332d8601196ae9bdf62548	1	0	\\x000000010000000000800003b90e0164bed744259fa9fca68139b311315179848aada01fac7c4a2e0e68f6662403d000f3a6faa010100faa2551748d9b5d72ac3562d56748c395b22223c4b3c498c7c1d7fa169b57bed70a3190e802e8347ab8d2a9fa9249d83796e392f2e25aee0e84d084b3302cd53a0a271235e25222ad5adf9e7b3b47e45e7663082d4f010001	\\x1610fefc8e507db2f3fc1131f84c09a5e0e4415fb2c73bbceca838c436b85ec274c03da92c6138ee60df2a9e55103636dfe5e8750f8595f7ba7973c99f81b106	1664103557000000	1664708357000000	1727780357000000	1822388357000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
88	\\xe6842cbdc03fffaa4ed80a825cdbddd19c7392d7bf693b8a87ea88975a1d55d8e21be730f7ca788df3b3c4fbfbb81d0fb9beb3427c901ee08be4fd37a793e072	1	0	\\x000000010000000000800003c29a1fcbd8e8a760f867eb80091858326a6196afac10c6337bd4a15301dcfbc1c0d869641aeb2dd3e1eb1626ebddcaf13d648d2ebd0fbc4c913bf51b6798db71b359a87ab47075e119b38f52265a6b528116101d3c2e724bad908706bf8f53ce38268b766e00cae8697991af89ceeaccbef7ac88f11248c03b55556bd2d26f0b010001	\\xbb965711a70dce0c2946330db61e700b265ae513470c16dee0673b180250036087fb7bed421a656f836777b8ce20b947ae6571aff195a26820610558946a2508	1668335057000000	1668939857000000	1732011857000000	1826619857000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
89	\\xe8d093fb7f5e77089d562093bd25e838ceeabe26d0cf5d3214c5a78a39f30a9a34fdb3ec90857630746c00ee63a1f497f317f50cb5776dd3bc0dd046fea566a1	1	0	\\x000000010000000000800003c1ee10c1492f35060d96aed02e3c4e4e25ccd2ed5e624cc6f95f524c78883b280bca58211586782295180bea1a2ea4af830356f4480ee6b9abc0d95ca6c62f3e5c3464dd95ba2bd48c415848ea5d44db5e6b7955ba46aeca55b5915f9a24867a96998b177e6dd62712b8c2b2afdfea2b600d8ddd867c3264703bd3b6c914116f010001	\\xa5363eb3171612e7abb5b6e26a2501393077875ccf0e5942a5afbca73fabfcb5ccdeb24e5e9448f8193a2a15c3eaf5566c45bff12548e7bf793cc2911d7b0404	1685261057000000	1685865857000000	1748937857000000	1843545857000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
90	\\xf088c3b5f9495dcb24bdf321e1d41d94489dfe92cfc92f7a1b325d7f1b3f322981006e2d796724973f54513b044f48dcbe7cbd3ee032bc3bb1a95e50769b808b	1	0	\\x000000010000000000800003d173d3c3cd99a7b95c5b67f2dd074d8021d77dfe9d7c6ac2f1d420ebcab9beb8e37d1929b8e05e50cb96cce601cf61bcbb30d52299eb323b4be187cc53b920e397a925d35f0fa58ed4b06c1c82e0ca5d0becf71168fad625c35e8d8306dad15c67db261654b71235613af2de3b2003e90edf37ea80b61f73d73883dec748d0b5010001	\\x60354d3c0654c3d6f928afa6bf0e80b0653f06c8dee7e42c322c47a1a3d27ed56f5af32f3f0adb13ae78b2a86c40f5dd0bccee501d17ada1fa384a8ebcaa2c0d	1659872057000000	1660476857000000	1723548857000000	1818156857000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
91	\\xf3e016ef1e69020cbaf418a7cebdfae9728aad98964e3d04a3257514ba8a0cd128dfdce0a99d458608b9d5f68dc0b1e8c8c907e79c6f05db34fb8ecc720f7fa5	1	0	\\x000000010000000000800003a258ea37b6ecf1cfd443c79b288e570f3fcf061fa2ee1c4ce89931f84fb2bdf6a48365a907670edf29e586f18535766c0bc46bc41caa04aec06e1c4ff81847f4261c8646e1e7939b96a4dca75139bba697f729fda2c9c7942d2c4bf86dae03d8875afaf8c5523c692e9eb320c2d99ce759cd1f7ac61396a9aa32ad73a393f545010001	\\x121d6d5464363c2a910194f2ed93ad3f56dceea9ff214447ec539e8573d30fb97578419ac5698a833def83c2fbc46d59b3e27af4e419cd71b27331a6172fea07	1656245057000000	1656849857000000	1719921857000000	1814529857000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
92	\\xf5c0117092c0c23ce4b956d78977ec6ebb6bc8af4836c9679d3704b7fa0bd735803f107d954aacbfba33aba089b6800469a751a1d3af8e9d1ce92797330ad87d	1	0	\\x000000010000000000800003b78f77f34d4fa938366f3407406a6a3892e78a5ce548f6b3f8c0af0ed3968adb8eebd5a6f56f7ff43eaa44746e7d627fbac8c758d05865d3ba1cfd18f2bb5c2a21bc2a867a03c86b4ee73deb09dc13e6648b875624e530a00334fb34b25211865a4574ee3be062c4b1cfecd8deddacff23de3363b2346fc60c633ccbcfa7c3cd010001	\\xe5baf4a650fb3528094a2f76b3555e1195c8d39ec5ca981da70d9a9cee90d7a3e183ed63299f1f32500300ea61e089e939dd5a0380e2b2614d98be690429c506	1674380057000000	1674984857000000	1738056857000000	1832664857000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
93	\\xf58cc64a51ec0daa404f049b4423a6f8b8ad0387689597ce28077f412a8a4ac8a03166ec4a8072cca8c1b2fafa31193a5e869aa3c15d8f6d19d06a2b8fdedc67	1	0	\\x000000010000000000800003e57ccb68ce77336f4898541922d9e84cb629dbfc3faeb6932e29f628a55e206ea9ae4ecdf47002eea60eaec69a1d1eb729cc25f1edadb3ba687c5d11aaf0513f2e87beff0b22b24d6f67c15d2991d1485ec7279b8cd135c5b7efe4858db041c65affc8a899c3e3350c7e74c6c5668f565ddac38c7fc809664e021bdab08e6d07010001	\\xcd387ace45ef9e685eccb8e85cc4c02f880b25ab89e7a76fbcb9a695285dcfe3fbff41856509347072c1be2fba664d146eb53573a00b8501ea60553fd36a290a	1667126057000000	1667730857000000	1730802857000000	1825410857000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
94	\\xf9d03685962b549c21d1182887ae034671adcd0228939ce44352a70a10a3157e7e0715d5118597e70ef91c962e013b3bb4f114b14d8572103a13f613b1075867	1	0	\\x000000010000000000800003c4164a5faca8af76b21367185818061fbd114c6374d1232a0c0f8207508e2fd81ed448cda94bcb135dc737c8732cca5f8bf52392ee388b6a850c60fead530c1f325d1977c0b8f831fab8d64765439931bc07a05c350cef79238b38178548b7198672fd1acd85561e7f605b0068200650bdba327095f69581ae34ebd97596d6c3010001	\\x835168e0d608a5b0cd932558cabc5e76848b6bdf82553a5dac0a6c5ff95ddcc2c6324a981ac90534bb3d69b5cd877fac70bb968a390c69f02d0beca92724f602	1661685557000000	1662290357000000	1725362357000000	1819970357000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
95	\\xfa207efa5d6f8d7ff79c7d374ec9c5021a7aa1f432a279175f9c96b361ccac4691052cf9a580489553ea3f3540006389e33207d71a350c028ffb0cfa25d97a95	1	0	\\x000000010000000000800003d05804ce28a0032fa519c3cc5b41e2f8c64f6f8ebc0d40c7816763b2903d1db28339ce868a410cd06a14f649700702cf200f94c29e5f84cc5497f32faddee253e53ebda937c75f13809d98c6c945bbcbbe20825d5b9ab72ebdd74e662518ce661fc2116560352850db0296be066e07d578a937790543b43d1fb936d22f2f6a9f010001	\\x73394fb6b89bcee20762d641b566e2e1fda20766e506465cbe7d953bb11904032832a4a6ee4d7e8f78a755bf43e003c97fd22e06849f23a5d3346f88113e100d	1681634057000000	1682238857000000	1745310857000000	1839918857000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
96	\\xfa98046bcdc2280d27a45875d5375e22c1efdc4aad97f2ec9083e4f4e10c26e169094851281a84afa6f4619b8a0b11f264676f1a07db70a832a4705a37c84bf8	1	0	\\x000000010000000000800003b21d5d7aa85a14ea9514241ab67920e044f727210d7b3bdbef7404f2a096f91230e2460d529a4d49880377738327161914a69d588def7563f663b6487ff79411629608cc662420208d4e69f8bb677911e44ec76b287e7b5710fe63029aaecc56f96b23c4c60ca372c1499fb2abfcd4092cb82e24995e9b3f2b3ee46416222ee3010001	\\x9a65b3bed421891ce80030bd05dea9efc0cae5258f43f3efd4dbad590a332ec8493103918ea8916fdf82b1a2b350c38a0e42bf9226aef564c7056f19843c9b0e	1673171057000000	1673775857000000	1736847857000000	1831455857000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
97	\\x002159e326095cc5deb156b6c2ccf05f9ba12753bbcea770ff9efe7db2621d83209fd97707559c38e77e16d77110454a22ed64777cda311249e7228eff8a84ae	1	0	\\x000000010000000000800003e64c573c2023515aa5c2134043fe2e366bc08cad44ff55dd4e53f9bb151dcc48180c9729a2d1aedffe7994ae3a6ef32c5247ed6b6d43374734e87fd2d1f8135fd13c8379c50e736e140a089918470deb1e08bff794cc161d3832bb5ea4043f2c9943d777f08e7239fc2d696715ee72504e95b6da1576c74af7dfc01f3b919e79010001	\\x31a570e5427cc50900d322971cf1f7e4e778f249748a214ef514c93bbc139535b2a5627d7443405926011d41768c3cd69917593c9657fc9a5c457a47b0a1f404	1662894557000000	1663499357000000	1726571357000000	1821179357000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
98	\\x06fdca50a0053f75db67190b567b4c571c6a73017dbe38f03cf87f584158a786345f1c32b06ef6554398a3a74e66c6e1ddad96b759b1b07062b8da0a9961aa32	1	0	\\x000000010000000000800003b1bf4ee9fdcf13f5321f76e9f2a3ecc2d919988af88254b0f803325db7138c51f16ab9765b7be22371b3447e4a6150f64967592548108e963febf98096d1612a6dacbb3d376ac3aa84d34eb1497ef5d8ecf2796643d14bacc47a91ac9ee68f4e3c46599b75b8036a8ea5a2a1b875429c56a37034fcb4f4871920281ba89ebf2d010001	\\x012308c64716fa93516b5f206bf151d97a6fcfaeee2baad700ae259a19acba35add73627db51d850f9546a66cc4c1d87ae3f5f9321bd80107d89fdb87cbe3a06	1660476557000000	1661081357000000	1724153357000000	1818761357000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
99	\\x0795010ddd54d43dce255beae68f968fdbf11f502f57c7dee20e9dbfb24d379d15acabb664d26ffacdafd3a3b0518c4d1474b44ee238bf12df4e8b707a6a4504	1	0	\\x000000010000000000800003ab82881c8540926f4815fbc7eb455a03af048dff3152ab95ab12d45244251ca3f6aa4bbc8293004002a51a6ffd007e0052967892267be94005c5d4a75edbe56fabdbafe4c7a03fbe7fc28f94614402c4eaabc74454cb87d5dda7699ec19cbc7f65be0529677ddd308405a4196fb561f6e66fba90a803deb7f25754f93f9f7285010001	\\x509458a7d239f12a6651f960d8f874e7fd32208f82a314659dd83b75c2ec0a386a7eb11dd120b3a5f3148947c3eeb9065e3eafb3e2189344ee9ac34fc2bbd209	1677402557000000	1678007357000000	1741079357000000	1835687357000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
100	\\x0825f787347075e059cc8852c33ee7c64676e58ad5a0f337d15c0fe6c7c93cb7a554c4701a39183d02474502eb19a1d4053f0a47a1e01eda489a26e0c4f34984	1	0	\\x000000010000000000800003b91263b925eea583b7052c10ef6e137c4f0a8153794f5939cc26c1db902685590e08e720fc4af2ed88bc482f404c3df9567e102750f0bcbb37e66c75c95307c066ef669690f080db9a03f46264c695d8c1ca7a59e172d332320f26f634d57352366e2f5b2d3c17f305e7cb00528872767380268c2a9835920e81e6fe811bfced010001	\\x177ba315da6baec62a959ceaa664e4b04a047862755e853f5d0b2f16632c3cf8c94fa28f6062bd9031b2ad01d56f364a758133db7add69833c32232214cd3404	1665312557000000	1665917357000000	1728989357000000	1823597357000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
101	\\x091db9f52fbbd01968d810baf66b4b637f587de7ae5c8618af48b88791c9672445988663c969e4ca04a661bc137d58a498cf9109dbcd1f6740467bc7fab50e26	1	0	\\x000000010000000000800003d7615e1aae19db2c39250269260606def9a82be85b2adfaf6ceaf70c7af3250b68f7c8db0f64351bad52adae636eebc4b4fa75cb099139b3036f32964ad8682803fae41ee430c6e4728293ceb2d71106d85bd021f46ac367066a3eab5bf3832c8818135ba8fd40db2d1089ea23cead26d089c0d8715e5032e46a63ea80db4e3d010001	\\xdfeaa481022addd86094882cabd607da4a418b54ca4681a37515cde139d3cb915c2970f20b4e31b7210c84fa041e47ea1aa4eac4b5cd53dab9f0253b5b999500	1673171057000000	1673775857000000	1736847857000000	1831455857000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
102	\\x0aa5778426446013cc3f3126493198f9302f0ee43e35aedf33ba294cb23a73f022cfe47004a9e09a0364bdfa658b31283b3470d8a30f23c3db389c09f947f227	1	0	\\x000000010000000000800003b05c2529b7f3e864c814de71553b5e387081227a562debb5a790ffa5c17c2930e45fe2c049576fa77f4888fa702c65bfc9d7bd9057e5e07f5b10d058911b26ba07c03aaccd15950e3f4c35dd3baf51a5602d2c01103578c504d5be6dffc12c49c95f50ea1ccd8d482c240d9a20885036b7a8b6cd5029c87d94a00386f74b0e21010001	\\xb43ff7521ab0c7e023aaa5fc3e12730072bb0799439d2225f6299d31d58707db3b17885ee7998ccb4077e64f5bfc78d7b79b4b4940a0d8a3e9cfbba01cd6cb05	1685261057000000	1685865857000000	1748937857000000	1843545857000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
103	\\x1021db3964358247664e196dd7d59479a76577d958e86761f95a2e8bd2e92747500a83f7954204daa0db16105fe2462e3dec79062e41fd5129f31c242afab152	1	0	\\x000000010000000000800003c3b7bb08760547ac9c5ecb6b1e4efcef5a4c4e4a8224691079f3b38c424643eb9bc2b3d1e20308dac443884e79280f2a84ac790abca650d760a90291698d637476dfd751e27d4bccb26faaba0bd0cf01e0acd31acd61bf9d268335e28ba5edc940892fd92b6a5820956074f6a975eeea770c137c04fd6de39a0deff3862b09df010001	\\x51825a0963d8fe7eb69b1edbefaf76979d7e36daf3aa2ba0ea45c611bdae1a0a640ebcda6895e04de751b50d9e9e1afd10ebac20fad13e348526fc6fd88f080a	1683447557000000	1684052357000000	1747124357000000	1841732357000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
104	\\x1b295c4ec4a0f7bf13da708c4d3cd444b65c2855cc1a0ce993e6e3a9f599f7e9d07adc86d4f7e71654855a88619a9555203e635c7ac66d618d5790dabe19527a	1	0	\\x000000010000000000800003d9d8413881ca6f022376db5d894a17c745a1d184a40079c71d1978cb9f0b641e3ffbd860d78381d37f6d7dd892d35f9bfdde5c09d8cf380113e4e4af11f9ad92bbe39a8e2a5cf28b4cadd64cfadc5b5e4d94943d18a9a6fbc51211f3fa1edb7a08a8de4292ac6c65e591b293c091d2a7d2424809f947cf4a5fccbe20b57acb99010001	\\x4e74f81347a647175b25b55f2c9747ba5d30a468a116819491e28f80bfd2873c7c2c07b844547f37bbe81c9a9cb91b6ce7d2bee2d50688e3907e134f55bc1a0a	1668335057000000	1668939857000000	1732011857000000	1826619857000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
105	\\x1e21b19a7f47f92ca26dcd063e2d09f78a43813a9b67d1e2523f0ad324bb5aa90bb688e8514dd965c448504379517772d1988c2c838051e5c500a6abd2110708	1	0	\\x000000010000000000800003eb1e37db4822ea1b8831b4ae2041b3e71cfae6389da3dd1913b299cfd1c768d3a475cff94045981cc2f53ff5c03cdfcd59e564d4b734ef1a937839ff85bf825f42b5aac49582951d4eafbd16d06e6a39f2dae2a50c328e7db83754c6b42e1ff6953aed476a133585cd95caff674678636fa48f18dc91cf0c1d2804db81858591010001	\\x0a145c5e5c28b062ad0194cb13c3067e43f551e4f644041784dcf537a7d5f3ff151d989c3e2c7ad64f865ce65c12cfc46da6e8f52d7d1c16d4efbc24a9ac240a	1681029557000000	1681634357000000	1744706357000000	1839314357000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
106	\\x1fb9fbc731022caae79f8d813ff1d1605cbc4fbf70637fdec90ad51d882d6f3b2961c1efcdd2b27e7116da462bbc002fb259d4db60b53b4c1a9e481d220ecc3d	1	0	\\x000000010000000000800003c5475a0a1654c39e3a7f129eb4a97f9db3340662078638eac15c02062ed01e53fdd12b7dc54d2d6d90624ac80acf673d9e2c3d1752eb74c7d3aea9531d8ab5c4475f0bba9b3392ad1760b529555625e69eac3d053a22f1d8d622ec3878c4966035b28d453324cecaf00b2c0176d6cb4067d1195e32745f6eb006a5d57582aa2f010001	\\xd1162f5404d900bff85835cd7df24250dc517281ab226d75cc291154c94729f483ca95260b986caf69ab1372e76abe65dbb979845c9a3f6a908c12150088ac0a	1665917057000000	1666521857000000	1729593857000000	1824201857000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
107	\\x2091412a4ebd585d49ee9f86be5c26ecc807e6eb36703c6602f897d2894f93a135eaa96e943dff72f685f40182efd075045a62336003cc8445c0fbd83d393747	1	0	\\x000000010000000000800003d874e6c407e98928ac9f3627822132438654945e9f45cb438234cb789bc975e014f737b045156611c10f04d343396ba8f2a8735341c1f8a8cc213c52d0abe1f2f66e85a5efe26c0a78b679ec78ccd1684ac3403e11828bcebdad5aa33989ca8799addf404e7421f7b99db321a3c51a75d4bd31bda2bf30ae4f1e505ad03dc0b3010001	\\xf1843cdd834905fa746ae26ce0eae982b26d4c9857414f85ee80f1ee98cc5caa9c5e43c07f7d56ad16244c2909c3721c7580993ba9869be25c1c6fe994d6800e	1677402557000000	1678007357000000	1741079357000000	1835687357000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
108	\\x21cd9351bb3b66398a79a5ad37a506a87c77bd15ffd68275f17e2eb0bff3bb7cd85a9435c545ea656887569ef22442c08799c647182c8305fc8a844f01cc2884	1	0	\\x000000010000000000800003f0099c35431bfed22d6d361cdc80610a6b2a86f5a7359bbba43dd63c6962a21f9049efe39712d41e36014a37635ce8fbab274c0395cf9739f7eecda15d8f2e7c437fdd58cd262aa3698787e1e48f6301f358fea3f58e9afa6a59904a612de6ebe7629086222ed7354b7a7074b5aee2b2fe6c51694250290427e3683ee8d15827010001	\\x918f7fa46192c9d39aee43c649df5505c7d334a5b3f3d5fcc0a2c334d7552bb99b5e5dea1798ad3275f61de0bced571bf11a92585b39bfbadd779e970a788607	1676798057000000	1677402857000000	1740474857000000	1835082857000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
109	\\x26596db45b09e628bb954f25fc5ee21176930d66d4658b28528ef4a617a08f52798f970894e2b74691019b71246ddcc815db35e6045c2b6edd15aded2cb36555	1	0	\\x000000010000000000800003c9dabc5da2846367142dc6f97baed82d8efa236e225d80ea4054e370b4df8cf6c7ca5ae960ee954ec3e2f2dfc6b06e58dc4ace80c891504dd8f43bc0b6e74a51a09da44c47d5b72be00f609b8721a698677d73e0ed17e4d93ae9a76b312e44849b77cba63d825d130245b223cd3ec4d99c89d4f9c976e524cd7a6ba6fc560d49010001	\\xf4d1b39d31137540f5c811a48511ddd0c7477d0d5f94ad5393e32b2e603ded61e1291b74d46b58b2599aa724e6bd85be97732ab484de1127f13a737a0e069107	1682238557000000	1682843357000000	1745915357000000	1840523357000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
110	\\x2ca981b7f6ce975fe9d2cb9a96b6a2d2ae3a152b997da22b5856a3a43a3c742dd1ac1b2a192e3ac9e764f6982543896804031b679b0bf7b28fdee42b36b482ab	1	0	\\x000000010000000000800003dcfa3e94f463579d941c48e250516a1438343697edbd1a929daddaacc1d80c14800b1b66dd0eb2f49124df0d6a9226b896e2edf2009f4b5d2b3a9d269604e3c379ae103d6b9f1108050c155605cfeecd48083e68cebc8056c8840d02381d5cc97db244417d79e3d39fffc74a6dfeb22e75508cb2d5ddfba5280682e51f2ba9ad010001	\\x51bcf0fd376c2cb86853730e83aa5737efff32a5556df7aa51b2abb4846ade170334bdc71070b50ad16f4fa3a8821da561cbdb091d12ecef8b7bbb6993729e0d	1666521557000000	1667126357000000	1730198357000000	1824806357000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
111	\\x2cd9de98d8578ea8bf5f20f691a8373d68b43d9b8e3aad2c0001f8498c79d1da87266583a394aa985f358de4291008f8aad50188df8ccc54829dc1c338abd551	1	0	\\x000000010000000000800003c648455715cab29edcb857b6a5230c4789a965352dadfbe00406ada1bc6854df744a7b666fa0609a4f43c1470a92a27ec0a7a79d7c4a2cbb6e001d8b756e63041398933f910e620b12de50b45dc5d363ba6eff40a2a372b548e225a2d697af78a21d21c9a194c31941e17c97f63873c01784118c470bb1e20c44f54e2cb50453010001	\\x387c58eaa9c7d6265197649831be4df5860bb16b914fed7262b5752be73a39d99d74352f03024124029c914409e5c78d83b616e2ec5f57ecca1bde21f48e9b0d	1659872057000000	1660476857000000	1723548857000000	1818156857000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
112	\\x356d338a3bb66f9609ff81af2c4f9539b8dc5eecaae99833cbc3d5d9e7148ce7a872c90bbf39fee625e54e7de6e3cbfffcca106b60f6444da2d8e659d506e25e	1	0	\\x000000010000000000800003b37df85a536ee338f0d7845953ac436df797206dfe124dbe506b22190a46ead429030effe65b9e67458e335de1a66c42626d962c1007008ad95e09be566b6531c5575daae93ed5359a97fc85c20e582e3bd7ad9c7c1e79f465ca38b2d8a597a5f601378c5af6e7c39a8c0d8178313c7eb8b85d65ae7b4ae800bbce2d9260b997010001	\\x9f1241c315a96bbad6fb3019f73cad100dabf83adb93c7246367089885da7375e1b3165e95bed3fc9c719dd04b9e584efc5b69fef6b22417408ab0a1f3ec4904	1673775557000000	1674380357000000	1737452357000000	1832060357000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
113	\\x3551f17f64de8123d0bab3043a3aa8388fc443e0691cac0cbb3e557603203ea56942b085527d139a42cc78d58f9d042ab2189f1e3295cb95c2281373b30884d2	1	0	\\x000000010000000000800003b2ecd49e4976d24d9aab7ab4adb4234770a32fb8f99b7bf835c1abd561857d40013860053196fb9687b1e0875872c03235bc0fe0c7d29f71400faf6fa05fbabe5828a4841ed4913f88cbb9ef2234eb6e5258d377116972d982fdeb90cc11fe22fe8f02b92dae8a2d616fd080c57c2b1cad73676ad3116afbc7429d3c41d48189010001	\\x3826637ac96bcfae8967483cef994d90416c0e0f534f8605e463022df73f1d9716fef62f77353ec6c1b3458358fb59998578ebcf524fe77b2196dec12b6cd70e	1655640557000000	1656245357000000	1719317357000000	1813925357000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
114	\\x37f9152779005cfff96a2967bf59f7420d721474edbb1b1d8138aaf52b5c351c3905e3a6848204050eca6f836a41d9798b3104f75208ba0605462689e427f7ed	1	0	\\x000000010000000000800003cf5847fec81eb30c1244adaeaa0c927b8f49dd3b4bbe24893462129ada226e8b8333b11f4b077490d1dc897c0ed6a7f38678d2146beb762d8c89267479133110f25e998b206ba99730e6b04598818132c49c513c902c60d495008fab5f31134abcb95ca1c01c47979672ca2f051e5efa55172b204db21de98900a0cd2b40fc97010001	\\xfe057c87a9acbec99e751513c595ee54d0c2ba7b94c9106da5c5063a931b4a9c9f16a228c209da16eb1a4593d55fcfad88d6962755ff1beee5e5dd4dae82030b	1661081057000000	1661685857000000	1724757857000000	1819365857000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
115	\\x39713e98b4e02d2442a68954f938245aa15ef7ba10b6b297f9cdfcdc63720566dd9cc921b603b7e1f21a9a9203d48bfe764f72e52242407070b0c09d5f540585	1	0	\\x000000010000000000800003a6720915b59aba91f8730a10662f5777bcd72595a94203633484d09d9ef52d48e04d1525b10b29aa013f8daba3ee896cf6778c14d49082a30a2c10ace8d9eb7629c73e6b2ab83cd00243c0a77857d8278b11fa70e8cb0ca8620aac4a92194d859b0318cb13c550ea9b1a4410c9219ae9a488f70ed3c22c5887ba34e86bc7582f010001	\\xaf6cb9477480a3891d940b29c1c82d9b79ae1c986668f5ffd82d71e94702f1e5eae7399490da78329116f67454e8d9ba4cde546a947e74fc9ed1aa77d6b99a02	1658663057000000	1659267857000000	1722339857000000	1816947857000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
116	\\x3a953e90c624d22de95b34b0efd3d84504cb27f0053fac2ec96b3d58b9e231ca2a301372e06c3859485491cc7140c53cc37f54eba604c8f3a53239e6672e4a8d	1	0	\\x0000000100000000008000039e959fe4970421b1f69f2efe9af0f297a43460b291f5044eea14cd9bcaea89c21bd7b8dc7039ece4c977d83bc299dd1e02a5703181b7cbcf54b2c38f15f0d2c4ee5f310b8d26e84b8087219e13715ca7030afb9b22e05e07e5a27431f4565ef1b7512f6065d94a4ede8cce254f612ecdc02cec21f10feea5f06a47e69445bb8b010001	\\x1ed1221b04af50cb9720629ce3843a96877f205131728595fb3cd8c6033ac0708b213452754381f904662686045eed0def8b39870ac02e925a3400c561a2d109	1678611557000000	1679216357000000	1742288357000000	1836896357000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
117	\\x3b312989073291c6a421d730c446f2cc1cbbfb78ec133977bfaea69485238588ff1a4ce4ee5dbe927abbdf4f173bd35c116211d9d9992eb8b9fe9e48e3db4ee2	1	0	\\x000000010000000000800003afa932dc6de1a29310e96108d9128b5b2c908aa2e4ce9cbade9177e7b2e0acb7549a6c80b08d5844e7c6eedbda45e6766e1400506e97cb26367981f1936976bdade84751ddaad66a0c4108e5c1e0e0d212476c742535e354632e5afb9141af2999c566eed83f223bb06f59a8a7336088990ac11f494321da7b859ef94e002869010001	\\x26a60fccd043d90e7df3500f6f11a3cdf9dca27a256e317462c6a6fbfd83cc0b88e2bc5aee76278498192255352970bc76df9aea17e1a7f4de4a4ca382a97409	1683447557000000	1684052357000000	1747124357000000	1841732357000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
118	\\x3bcd3abd3aaadabcbbed39af6123904b2bd5e4c5ea05c7b1ffa552200265c740edadca9d6335104ebb82dffc1dd815b730ebb97eb34f5c041608fa3e32ecc217	1	0	\\x0000000100000000008000039937b865211332d57571a6038faac660c3a25a5cb3a1ed58f7a415ac7de90dd403f45f0c4f5edbbeb353f14f8e9ef96583ca6a81f689c07ed8a9590729ff5360dfc4ba8aae5b0fc5a5c5c1cd9fb555bbfad774df2ddeeec68103b9fd9b7a5966e3d187069570e3303c0cb4bbe9e4c20fb8c9f0b8e993429633f92bbb42c4796b010001	\\xa16f4aa7c1d5ee6e99c7227d5f3ea60513a4bfa9627d0e179bac384c97a7339f189c1dd035c48401263b678f98f1f6e390fe90f21ec17c014b1562c502bfa505	1678007057000000	1678611857000000	1741683857000000	1836291857000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
119	\\x4079602be44bee523e83be13d503e63543548a67a3fdf0fd186467c06b7ae2719e765f77d814614a57f06ffc8206163084c784ff9eab89599effabc0651cea7d	1	0	\\x000000010000000000800003b375c8dded8859a4555f2cfa5241d17a736b11cf472a57d117add1ed1df70c4d6f1678f714a04b80882a9ce88a7b8eed4354c67b9403fd1febb40aea58dd460ccc137db49e971a6493c9e595dd4b03adb5b1c0ac1f5c5c5d81d7f8bcd707603baa32eaa2414ef8085731d6f1aebc24e15305d70c407e399808ec8007e3d666c5010001	\\xa9491e3a6e6c7ee9d370b22e66b8ad7e8fd98f81e8992b29e2d1cef9f6f9487d324958ad12e4b3ab1fb72eba06df7a05b61f056ba6ed4ead6cc4a83b6d0a560d	1668335057000000	1668939857000000	1732011857000000	1826619857000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
120	\\x46ed834788230459b4a0ba27abd7f819257a6f6ae75b24dff882b5beea45484f4c16d9f19e72b283257ddd9711cc246c843da42e8dbb2c3a9ab407bb516a6195	1	0	\\x0000000100000000008000039c87768b37c61055b6ec214d56db4e8850e36fa45d25bc2183f8538e7b9fe72b41a65df2ce4eba1e989a315f246db1f6955051b35a06830112a216cf8cec50043abc9d038b690ae76b08d841b8ec9574be197578ad12a28b4760fcef235c75720c7a3320b5f94d83b73f3626b05d4023a15da8da7017e62582879907b7f8a473010001	\\x883836a91cc56ba3d0fa236b27a595e479db93eba10849d2d460fc0106f48c70e8e4e112e34bee38bb3e94511f9b51853012980f4532df72b521b214a4ab0008	1671357557000000	1671962357000000	1735034357000000	1829642357000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
121	\\x47d9eeea0206a2a537172e6dd06ad99aa49f8c5def9b2ec3cdd95b8eb8654a82a6d3bc7147b06b91ed2337181a17fc25bea94575a9b0aa1482481a8f1ba9904b	1	0	\\x000000010000000000800003a44ee4747761f2f0d817c59e1ecd38db45ae9e7197837da15293a1da95c444a52c6aa5e154bb2d1067ecc07df10d6210af32d97357cdd8498cd2609a82b768abc6137df3cc73cf5382c8a9e754ed7a57630a554e4c7d60ed087ece802ea9a313838d0f7985165a0ac27ecbfa1078089472963fd077d6c050c735caad4b184b4f010001	\\xc06e1d4cd401fc5bc8d09d16560c53d617fed8da3db5a30b8b20a93de8750c9624cac5b5aca92f2ce825192d75907aa7e2f6dc9664858a12a19604cbbac9ce03	1658058557000000	1658663357000000	1721735357000000	1816343357000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
122	\\x4abd1efde328ebf25c577e560285d90284eea0bc5bb4329c0130fdf1b3e9893bbdd8122dd6ee8a22b5d3e7c04055cdb7975fa95a69809f69dfc02432c8eb3553	1	0	\\x000000010000000000800003d85a88f45373f3fecf6d1ee0b80c6590136ceb025cf4e90a42138e90b56172b5009fd404eb9e0bdab7bbda30fa37c0f9cda586a1995f3df8bb1992eeada65a182ee85cb6cae51c9c742878b10552c7c784c4bc42078d25b8372ad3946844f37822362d971fc1f92d1c36fe1e4e8040df99838fbde5adaf92362a616d781f081d010001	\\x6842cca7f77dffb9e9ec728ed1404d7932618d2c7af08f966250b4ec1ef92b5d0a9385e88eee7cb206cef22927926bbac9cf276274cb7bfd02196d041674b209	1668335057000000	1668939857000000	1732011857000000	1826619857000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
123	\\x4a81bd22c8b8f336e8d065dbfcfc179137de12c1e259a84c351ede689454444fa843873ee898df213b5acb94f6a1ac4f7fc7fe2d56df3d043e9763233b80d5c9	1	0	\\x000000010000000000800003f422878cd23d26b4a065d8aaee4909c88bebc422f5ae65116a72f91b8e22afb2650b82ca469ac88d1b5216c19cb3966ad5b5b2963d175edb09b737e7e8d887f7b5d21ea16b42a73259ddf72735b0b77602bb49d424049df71d6ef709a5d5407df8b73a15d801ce6e1d82410aec836ec5ceaafd1b8aef12b1b68e32cc1eca3bdd010001	\\x9b1453988e72c5d0893908ee063c87fe102ee7ddd1b15eaf92947d9770887fe28000f856a69d76d5e8a50f39f02492ddac440409cf364ad3db662feb6f0ae308	1682843057000000	1683447857000000	1746519857000000	1841127857000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
124	\\x4d35202732272c48ca0c465e6843768bd6278e93c43088fa39da8fc34d5f4aaed1770bc3f815f0161b105b289e5ab57670eea8b9931851ab7f37641106f336b5	1	0	\\x000000010000000000800003bc4e1d3dd2e8ea4f0deeed8b2080b5389d0d846c18c2bfa26a7ecdd274d84038a1ed461860ec67ff6e21a6d2e00bcb5076d2a1ce0d32f75dcde3ca37ad6054d078fc449b7cfeb6dc7d57d9122b01cd8facbdfa43166ab9edfd05755504c6b01bdd16f30c85703ce26a0b24124268243a4730d690faee97aa2dbbe1b38a98baa3010001	\\x552d3fb384fa20db072647a37d4cddd33225f7b74c55bb1863ba6485c81b523874a6695100eb4d541635be42b863e4f52f8c839e38fb1f5c4f9fa49d66122902	1661081057000000	1661685857000000	1724757857000000	1819365857000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
125	\\x4e29b47d4b6a4e3fa89032c736d99eec11f8844b2cff885c88a1139ab40acfbaf14f7396a34405f0f3a7cd77800a90f8de02fb4a46040266c21e098dbc0fa659	1	0	\\x000000010000000000800003de37021f1fc1ae55968d18d6799bbf677eaf26004abac5b48e83d2e0ac6f8faef07c996715eaa23113234af9c83b1d77a5e51544f65c93ba8ff40c31ceadda9c7ca74eceba1cf55d685ea88f58c6b721d0abb97aa955444d755462aaac9dce43fcf2f4f201d3109cc3e0c40ce916526fc09b5ddcd16190d4e7ceb8b3f8d8ef05010001	\\xe676888d3633fddf4edb2aaa3c0e724cd30f2c8980b24fd517d90711c613fa91e4dd3577921f20ccf7b18f275a5c3f3fd2ba665e46da961623e7bcabf42fbb0c	1659267557000000	1659872357000000	1722944357000000	1817552357000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
126	\\x4e11bc41a2ad385078df1c43e6c8fefa1e193bdcaba2f1abdfffd1cf13dd1b81ce5fac5ea708b6eca6bd4fbe59c0978f0eb6d29c50957ccca20b0b2901f945b1	1	0	\\x000000010000000000800003ba522b37915d4e6f8ff8a4508fb8c0d64ef8ac116facf34bfad7d28c30f176fba57a54a3414ff96d41c2d6943e90aba13da94809703cc02c330570a21041b46aa84045b5f35d7e9621f575a3944234ac6637f6526a59cd7e603b3c2f37a54d77aaf51456acf9ffd85ebf627a39960625e7fc277ed6c117ea9583eee2335c0a8d010001	\\x06377370a8d006e82a1050bc5bfa2777c3f5c789a5d1e7c5400c03640157e3828b03b259e0fc7e09d1748610c695f47c0881ac94829e7e5a5193bd654b592f0d	1684052057000000	1684656857000000	1747728857000000	1842336857000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
127	\\x53216ae84bd8b98e75326ace371b7af714bfce0a1d4f677b545ed715e9e67bc5888e7479bf7516a1b8202b70286a62d0cf765e0ed7c538f6505e2160d53c78d4	1	0	\\x000000010000000000800003c212465a44040bbd728809daf4549e5344881d67a3f3dfefdb51e84d0c546142e872fb1c971d56f95542c1a80657dbfcef5215367587d55fd857737718a1caf7032bb2b75fedecd7ace13675c0c221a5c00953345f80d445d23558978b4507423ec2118be729efd4729be44329ffecdea3e196588550ca1805f7676ed0b69d7f010001	\\x9e19b1dc3537a8d4f667f59a0efb6c4595b7232d18e5112af3fb5c86a6ab307ccc12eae1bf454688e13eeec52463e853b53511b278e3ad9f2aa5bbf987657308	1675589057000000	1676193857000000	1739265857000000	1833873857000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
128	\\x54e50b805e502b05dc89fdbe4a7ed2ae95d56b6c6d93310412fdeada00dfe2eee9c631336d9a13ca38b9374301b88441c76331f18cbddffaeb2294f8184412d3	1	0	\\x0000000100000000008000039a89d56f94f5d098e6729d38fd1de69bd4a118fadd1149aee1fe9c4850e3f1daa2645d35c03490449875182198b4edc938768e4cbea13261a264e9d5d96893b7cedf2dd4f3091be74612ec23901c85b3932ccc356a2498b659a4691187f4a41b2e31e3d442b913714dc9529e83e5dee648af7022df9f73ff7d124d1f6c9ec2f5010001	\\xbfda14e94d7fb577fdbb51260c8e739a1a6841a5e9091c6fd221c2ca3c6b0d10bd2d3710a92ae3dc4c1f21638a847ab9ac5768459944a92149beb8d9f6c14307	1655640557000000	1656245357000000	1719317357000000	1813925357000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
129	\\x562dcd14e56d1cb6bd37f946b7c5ffe64f3c5c42f968b3104483f76d0688ff10a30f4b127be74c3f49ddae0f62a08bf5aa8364df8e34ff92c55d2e4bb8a3fe89	1	0	\\x000000010000000000800003ae13cc144ec828147efe255ba341e8a736115256f851e6a48807cb5f645617a3b6e23a249de24400625ccaaf2d234717a8ce58977e6aa044b05b60bcbb9e966f84b1338f9776f9bc153939031412c1b7f1e9095c6d61acb3d254466c31b1ea77e3cd3603f28341767852d4c6da79d91f6ef09399fdd3659bcd91512de64e3b59010001	\\x267fb9a17e5d402d82a27b88c524aa69ed1a326063946abd2ecd62a44c8e3a6b7da3853cd1078b9fe1f1527a0a0d5e3cc40b6127eb714984f6d6a90132431801	1667126057000000	1667730857000000	1730802857000000	1825410857000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
130	\\x56ada0cf3a841716bc1f6e59bcf274c494d455deaeda7ed5dd9818a9abe5081a924a1a3ea8d10d387be3ff1a6ad960f53fb84616288e17124eafeab39a7c97ed	1	0	\\x000000010000000000800003bd97aa2ba311d69bcc37b1f734dfdea5318128f8925a10b9899926b8dc026d608ef106178c62670f1b465e4f0099578de1c3ab73a7e3966384a2f7387d08f13cdb05eeb3b7f5c10fd05d8104d173b4e1659b73d7447a6362e5ea079c22eb24161895a5f931054e3daeb24189b0955732b43fcc2b16d41aa90e8594cb4366e597010001	\\x84ce96ecc16cd2262caa418900672cf0eed923c4bdeeb2867eafb0e48b6ea55ad3f886ed3101755c54deb240a9108133b5636a4ef1324b70978f70bfcbe07b03	1663499057000000	1664103857000000	1727175857000000	1821783857000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
131	\\x5815a8794d9e95c7f07be2a42a3f3a1fbc1ca1f879182d4c8438618abe6070c56fe3bb841c4e5406b6c6ce5bad279ca109de482d38a342f9066cfc4b74fd4ce9	1	0	\\x000000010000000000800003c03f06e4335c3dfdfcb8d73c06dcc5d2b603e5895203dab070e36967a709a2660033763805742a17541529042ec156a18071dfedaeebd51ffbd41c78a02710ace862c7f61f89885187d6a6c19dd5b14d26600b116abf6ba54274e6283fa796418ef782dea78ee8cd651e0d2683274801caaec522d5ef3ea378a0abd91291de4f010001	\\x9282fec18dd670f3ba82852edbe46fcaad85a9965ad3d9bab32024c2f803e98664d6c67c1bf550efcb4634c4c0a7fd903107d3c2ef6115aed1e4d142ef525905	1687074557000000	1687679357000000	1750751357000000	1845359357000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
132	\\x58f5e684fb2cf931f8b6c854451f7301d9a61fe49e33bd879354f085a85c70bf9d0798706870b91f475283f1859fd0127ec2d3b136c9a88d4b9c2be4ca0106c4	1	0	\\x000000010000000000800003c9a18a69a2c347549083c3cff1f489f602004fdf0db99091f7c108a7f8e913d7a4e8f56652b9e7d929b483d2ce34b2627aeae74c8c9f820f69efb0b757a0f902ed3aa45bbfd5c04b2b835d483092c8977524cc68960e754667d4fdc6baf9ffc18d425083a22b88804ac0fb878c29031d03d6438f1684973198401e70ad28f3a1010001	\\x286343efb30fa73bb77cba6cf18e6b555f3a562a23c0afe9c6e4343df6e4dfb19515febf2ab7819f85f875503b722e72a15955474ac92a665f979a9dd122da08	1678007057000000	1678611857000000	1741683857000000	1836291857000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
133	\\x5bbdafd7819668cdeed66a839c3056fc723cf502677160b71da44da759275c248ee16c526ab5f3452a77530e90befb81d0919c188dfbc51702ed583915c423ed	1	0	\\x000000010000000000800003c929b71edc09f7ebe8f6c1ad0150b7cecffe5ea93556e7b06fd67c0699a24d49be8007254006319352e1ad55e4f9e15ac643df6b965d71fd7bee8cefc94447abad728620f397eccc1214a88d213e433760d3f60209579fb1dba5e197966b42e6573e50639143d48953d15491af1b75b846b9ec4551b5c80b3fc567916220f955010001	\\x3667565c12a2ef40bfd78ab08548e2aa0726bbea31f560d77555fe66a0a9339871ca89adc319cdbe87b992aca08dae474d101bae5198550c8bc3bd69ba26c003	1679216057000000	1679820857000000	1742892857000000	1837500857000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
134	\\x5be5499b46342e7075dfe19cdf76821fb3f752099aed89eb4db11c3fcb8718b8a202d608d7a1b9f68bbedc26601ccf0d148a3a5faf24ca6a7aaa5df1bfa33ab6	1	0	\\x000000010000000000800003b194f25c55df0e3405e3c7fec75cebe80fe14e2e8730a45faf6390bbad34ba294dc54410d96303e83fd164f6a35ae8062b0a179025fb6c9ad11fa088fb2cd84e85001aeee2b44bf7891f65f8d4e8234ed6904ae4ae22600c49250ae71c57538b295482b717ef901c7b164866a5bc927695aef569491b5f31c1f986ef45ab4b1f010001	\\x691cfaefc59cf215eae390c4fc9c749870fcf89d2b12d665bf9c50612456d585d25464ac11768312d5ec28f00aa7444288de1d482225c272df324605922d6508	1662894557000000	1663499357000000	1726571357000000	1821179357000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
135	\\x60994712e683df157edb73907aa4eba213323e83448f69fc3cde4181e855e75d15fa53586a539f05258cacfd9e7764569d65d01b836e63db731ecfff13a95892	1	0	\\x000000010000000000800003d1b64ab5cae393d3a47e27a00b072fda74d295546c22c3d89dc49b4a25feb6113a22d1cf856fa790064a7cd34143546b9e6d8a220cf6813fedc71929bf5902e21ec567bc2b9514bd4b89f8179e2d4dcf224e763b232e5a38706f8b8ce46b931e217ded67704c7880abe6ba82d6387dd4f405cd4447169fd337c11fd8784e7c5d010001	\\x6b7bbef59c8a43a8eea16d62021a57f4c09d3a9a7891d1cd7cdea774e3bcd4e0f6c69230e0caca3aed6799024b62540377c890a2c870ce2d97ec5aa55265f809	1661081057000000	1661685857000000	1724757857000000	1819365857000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
136	\\x6435fa26159555178e3b0a42c0674d56c1c1db199711e23c5c6adcd21859a42634e2857411bd408a11850f05dacb67bb8a5dc33bc9efe5611e9ff7d1ab63a9d5	1	0	\\x000000010000000000800003f51e9d777b8e30efa64ad27e3b439705b3ebc3e9816a1fe4ddd473243b16544dafa144f6b3c58c2ab898d88b65e3b8158e89ebfb439e31043519235857583a875eb86904f2697b12d1ab3dcf0dd1a68d03852d10e9f83b2c6249f730da4a9cb713b43bcdd9166f12ab06d973182f33e9c0c9c130a03bd70303ff68f89cc4eb85010001	\\x3c5997763756aa529268180ea8eefb869d6933b4bb8c7f7a7894f1ba22303d75f205f9752af814a4fd8de8e08d2e676afcee69914d8867b3aff2ee70bfb46a03	1672566557000000	1673171357000000	1736243357000000	1830851357000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
137	\\x656584268365cccebf4ac3725f2ed7c79a3bf352d3e2d57fd68eb0507558f57ab895abfa0f489f8b1642e6c483d834094ea2874afe5fdaf7f833548ce0afa70e	1	0	\\x000000010000000000800003d178f458ea4e8f240a854f0fa1273bdb0d165f6f6fefc6ef30f865f6f719f248631e0d4af0d1b50728b283a49f2f40324029c99d906dd99330f7f38a7ce7cfb89b7e1caba24dcf248cf9e83948cba562b6e083308c94adabb6e5468618097c20397c8c4ef4a38504997261c641c4de678f11fe7681b6a070ec3d0b84ff71d1f7010001	\\xd290c104facec80837f9e80258b43c9b06ce9d5ebe4080a99a9e147454df19c7da60c6e4958c863fc4c56b571d064b68ea815c30bdaa81e6f943b3159da83805	1685865557000000	1686470357000000	1749542357000000	1844150357000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
138	\\x66c92336d79bf38804cc5258a326662c93c9077b79afd000abaa9ac9a80b6be2f6deb0baa2d31e6522cbca3aab039068ed7bb3cefc6c4a520219fe90fc46aca7	1	0	\\x000000010000000000800003ba0efa9dbffd8ea9981ed3d02bbd875b33e74de200533f8fb482e4ef7de406f1fb7310dd5f59c7101c8d47aca00f5de782943001f3ff99c443ac04f57124fbde556859ed4c1186333dfd2847e3c7bce5a837fc05ac5df13c8b7899fb94bd57bb87113a8565772b970e4cf40b53a1179734cae180912e3aa5d273810b4f01fc45010001	\\xec1390187dce8cdcca0a8139ea2280732f7bc0eccee53765a054bdae62e12df1a2c6fe4690970030f81e59d67d10de19f719f3089faf7dcd54405380a0d29902	1665917057000000	1666521857000000	1729593857000000	1824201857000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
139	\\x673521981556dbcbd24d758c5813d228a3208caf11d885876c6a8a392027b836e7d3edad4cf1091d97c8f2d3ae023d2696a04207cf458432378dd1f5fe02cf91	1	0	\\x000000010000000000800003e640bc2727dddc2324be7e149854447b2541fbc8668f1fb1e08486c6377c89e06cb4a1015148998bdda10844db274f3445f2d8e429941e0a1861c572fd99cd31c836cea5d9a537648eaab30c11fa4d0ab4574ab7f91dbe2f4922ae2f07ab89ac7f530569181879d0c6d0af8661de0fa44527be535b00c51e819dddbd2c878a6f010001	\\x46971480bbbd9f9290d61e6aff1e9d352a44434e86bfdb4be17e7825882d99e39c559d594c0b4ed4f472609ae6326ab7f67215dda502ccb1aba1c607406f7a02	1665917057000000	1666521857000000	1729593857000000	1824201857000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
140	\\x67353b12de56dd71d3e680440ee1bd5bc22a2cf71c6b65e5fe2dfc26ca2d336b5c6a895ebb69cde321c82ad2a7b3a3fdafaa86665ea79294cf50c4dedac2a6ae	1	0	\\x000000010000000000800003e4abfe8d355a227043bdb0f16858a839da7abeae45068cf6e1bcba54529ceffaac8fc6f2dc74a3597a270121b4d96b92646ed3f648663c895f6a809bed31442ffe94661539426e4722c8ee48b01c863cf452dbf1bbd1f55b8b63e1772e6902c82d45d508f07b57634b6e9948e5118e99a8585e0ebd8ef3bbe4192c75ceb4d927010001	\\x21fff547b798021daa301d65ce386be5a89497dd02170c3ad9eae5eceddb36c7db2369a1cac6a87bc695b621f3a17f76b8d05f31e97374fffbc51fd029155807	1658058557000000	1658663357000000	1721735357000000	1816343357000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
141	\\x6b99fc505e77807592807c61b7bfe89995081f24500d04c6147cee5c85c9832c05e889e277782345020e5a59c4902e2817829bd5e08764e8f54404fdbe72b153	1	0	\\x000000010000000000800003e333aa5b3147c54e4d065269aa48420c3eb187f6b9b01605c78258f39df91b496d7b8663da5ed550b6f17e6f8800b584a39f8d93c3b4b74a204af4043cc958aca5e1a8cfdc82d31c6df99c9db5d01de1215de204b26c736c0b229e4d83cdf10983065121d375c6fc91ba7b8f752d6f9a76ce102a45bb773f473d6911df5e344f010001	\\x70761137410a1aa6c17c0a7185cc72cb905b8cbcfd7a5625400c178bf286f30b4575ebcba3e902bed2532c36bf5544b2481ad18fcf4e24a62405a39ba3b8f208	1682843057000000	1683447857000000	1746519857000000	1841127857000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
142	\\x6de934f478a00e960f765c6628b46cd9939f9b48f70c2f5a797b1bc81dd3959253065e15b09db785433af8947a053a81e721f166fb6833703af8380d12cd9746	1	0	\\x000000010000000000800003cbd61b883221d0676807fc3478c4181a7c56117b37e8ebc074036eee4d5d2dc99da269b6b7c2d91f449f06da7d45776bb30bd1591f42b02102be035fe306e7f0daf2f175f5bba642baf55a7df05d54630f888729931c190d6ef45bd171e7423abb438f3a363d82a646542aba39fb3fc71d8b43046e87fc25158d52bbfbfcf21b010001	\\x9e34d00966868a32a1041f9b2c9f08e0830123bbca63309fb5bc4bdba5097af983efe5cdc4c53eea5d8c31d4f241739c62dd6ad8c4c46592ae26ffb3c813cf06	1684656557000000	1685261357000000	1748333357000000	1842941357000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
143	\\x6dd99641a73fd2120997dc063b2b3ddf9149ef283174bb8efc24c9b81cbfc0433b65edf47efdab1e1e9cd0a0e5a61b4a1f902d9bab82772fe567541952af29dc	1	0	\\x000000010000000000800003b338514ab900a0d8226f7506a1cc9d662938ca964e046897343892ad244e6ffeb0dfbb392f9d0c3b7367d1ac70a1bb23f931cebf031e7243cc94ab3baecad5222e87e7760423011602ac32c73e315cc1d6695bbd10f6563fd254de29d665141b921579dd3cb1fe9cfaad1ecc04a7d3b67362d6739af793d3e90468c5dbb755f9010001	\\x3cde02595a73e6976f30bdb36c87704dc53ada712ac005211790d3df18a3cb24d1cf0ca29a5d42b8916e769bebf73a1465928c8ae74acb30ad0b9e4d50c9d70b	1662290057000000	1662894857000000	1725966857000000	1820574857000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
144	\\x73294f01fe40e562db112ffcb1d7b1d2825d0bd4da3f0f26922a82a1d5772e46f068d0fc1e616f975ee6baf136526bce1d7696e627cc9c5c3cd9f268b14e1f5f	1	0	\\x000000010000000000800003db1d36f4309faa000c59b35483afc98c5f08ffd18027c0cd9dfa01bb866e33a09637c52a8eb82ed3c56bcef43b65df2179b5562dfb3a50d184f78d6cda49f755cc1d8e88f5ed3f4b7a2ea8a2d0f8e1b999bd964db052f69956566b4d505bc5e9fd4bd0a7c27bec4f301fe7268f8a0a871b6334a174647928d25bf1281c38d589010001	\\x5ce0cf31a563a38af9fd8ffaa28252a8296121b0b70b2c50fd3ebbfeaf69c48eb720431607707f81c9957ff08ef8cedf7e28de8fd2dcf38aa09595ea792a1807	1685865557000000	1686470357000000	1749542357000000	1844150357000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
145	\\x730deba39d3c3d92523033cca74c7231ac70a855c8a4451bad19780350a2920c9b39c0a2bafcfaeee01beac6fc0379917f9a5dcfeacf8049c30d28bf1139d9aa	1	0	\\x000000010000000000800003ad09f9adad1c2ff1d0ccb058fc5de74f7b0c98377c93ddd25d233a4cb6e680b1d5517c15bd09b4e98ebc4d7b0ada7a2288e26818c714d0f206a1ac83fe859a83cec864187fec101399ba1dd1a815478c84470a73df1a586e40c40cef39835f1fc81648e602ad6be3295ed280c80c2b0119c3ad2c595b5baaa16955e007009fbd010001	\\x130a3207cfc2c747f1b9c26fad2faf00bf86a7f6d36282edd63235c7393b9229d0374946fa6970c97c1be62a70c0cf846f0cef24110911d00554b0eb0a786e05	1658663057000000	1659267857000000	1722339857000000	1816947857000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
146	\\x74b19ac3170e8f35cc3d7f06a3b0d709ebb6806b2b752910712e2a692d2b97ae38d9e8966f4ee80c06d723ce3c2a8f29a19d84419ad0087cba9d9ad5d09ac753	1	0	\\x000000010000000000800003ae8b3ebe4e8dffaa3e5bc5bc795fb38eec74213e4f82343735dab666c5092fe35ac736fb768538cf44a97785dc2ffbf4608b63be04d70134e285572ef00b58ed890b2e9fa29253c5df8a1d43ccde2b895c80e2972d073c545f5336508400ba695f98e6a04c9e4a3ac734d8016eb8fa1c721376fea36d24878d9710ab8ef6e48d010001	\\xcc3e0afb2a5ef41afdd30110e5bec2c6d31b604506e8f9b57040af01db684590f1da8e880c8bb5fe3c27145f1eb43bc9b0a153c3b3dcf59b351bf12cf8835000	1668939557000000	1669544357000000	1732616357000000	1827224357000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
147	\\x7a71e39344614a37a836fd77bb0dfa7e1b4b87ebd99c40fa0a10bbcacd8bcd6beffa1b3dcb03a1306b0eee503c64f5770644fdf28ee284b8dcf92b9b12b1ae65	1	0	\\x000000010000000000800003a3386bd203055a7c178cdb832a66b0a89fb42885616421fdf443095fcf011bad54ffb1d499ae82105378def18be32c5fe2f412cf9047358bf4a5272df19f4199fe1b05ad3bdcf807db581525fa0ae22683c811b53a8dc113cbf2f0f9dcbb7436472400d7b7ee95d8b02a7bbe5d33902c4432fc21dcc6bb08051ea1aa7f5292f1010001	\\x331dbbae1b2899b4a31305564bb0db7bb7f12bc5af747eefc48c025135db42bf2386cf70eea0dca7e87e7f83ffc3964bfbabb5630ff3c8334f0c762573dc2e00	1666521557000000	1667126357000000	1730198357000000	1824806357000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
148	\\x7a9588523a30aac178d6cc7f78ec4743fa02d21418381f5fa5df11a871a333dbf41d6e10eeacac83e9d1453690d5e59dbc1ebb88a7679b7111f03f4409746f50	1	0	\\x000000010000000000800003b52b18f2ee5c5efcc8506388858eba1214aba71262c0889e0c66fb32acc6262cc5c9926866a67a376fee6eb363ec6968cbe09befd2502bac746b624b9ef63ba6eab01a622a0dac8239cb6318c6e26536e3978f0e866b899c442113240cdce0af55d0eac1313bd8d503d88f20358f9a63afdaca63e0eef6c56a9a85825abebfe9010001	\\x8d42887694e1615eaf1a4427c04d5747ac5b9d376e01012603dec4dd7276cea7d56703a5f3cc603b94bd8c8c946be14c6f6be4e276a1005b101051a47fe2160e	1674380057000000	1674984857000000	1738056857000000	1832664857000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
149	\\x7b0d2b7d0008f4f632e1218231778540356a543b76830a6a939c681b1b05c6180cfa84f2a779979e95aa137ad5d09cc5714a1f30ca607b1552d51923f9b21066	1	0	\\x000000010000000000800003bb8124c264006b98c523afb388b7cccdc572b1d3a19a27caaa5c1de4e5f23043496769385bae5654959b247e5f004a1cd04a073def10d64baf9498995fea9e3fc027c4c8c0ff8fc0518b4108f0510a776d4cf8f680590197c7a95976d564870634de9aaa9c57340394d168de6f1babc5a38cce64b34364434dea61f7043d90b9010001	\\xe75e6940a4fb7d73b49cac7d8b6fc55f9edc2cb57396e90c6fd3f3a134e9e444aec91dc59799e0b110bd0ac306242317c1b2a59c9daee547f1b51f8d34381a0b	1659872057000000	1660476857000000	1723548857000000	1818156857000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
150	\\x7fc1104922f2f4fbd47cde843e83558ca71635e074b35dc42b0576514f59fbfc113951a2443e8e79d74ae09bc7cec946ffad228e985fffe2d9c31edd9d6d25a2	1	0	\\x000000010000000000800003cf9bf987f40341e3e764b9b088cc82f36085af7457f9678050f18433dcb994be89c52494b2c47cedba5ce51d50b66f5ec5a35d06074836ec10ea9db6b574da78d4838094ee88bb03f9a6afb6eef9dea44fdbb1992053c1ebe2e0d1198d501d77adeaf1cc01d4c875c9f11ade597b5eb1da684d9f5f446e73ca60eebcc20ec5b9010001	\\x276be449b08a2b60670da182abcd8a632dceae4285a615703cb8b3495726ac948f5d86492988a4df583429b5cb32446f337a51eebb89c560414c25ce59bf2207	1672566557000000	1673171357000000	1736243357000000	1830851357000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
151	\\x80d5a8390395f49d518f13fa13e93713239678ae8d3bca941d29426308ffd69865b45649bc0199620be6ab6166613f72bed454b16c745f83133c9c9a71218510	1	0	\\x000000010000000000800003b423da78664a195ec7dbe2a43da1f4cb9eee98c342c1da66f41a1a9ee6a23e47f427f93ccf06d6aa46ab39b72ae9333929233af67c7ff79b29648d9564bd5a7e4aed2741344cddb648784d9341faf3b588ac30b84a26fe1b4b05e49ff6502dde69f17368fd48fcc008445a941bcb5017e70ab96d40b3e97d045ada86fa2841cf010001	\\x402948b63a73f51775d590c44bb64bbf23f38bce2d8bb6ca7aea934f9c25bc3900e875c7c2eff99d83697c07c80e7e0635865488a398fd2692bc764e5f427f0b	1680425057000000	1681029857000000	1744101857000000	1838709857000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
152	\\x81950d7aa0c8ef4dc8692c1470ea62e09b85505528483350620d939aed6e83862fa96b7c93359242a8346c1f22276d025410d485a59af3a93376b24dd47e37c3	1	0	\\x000000010000000000800003b8ba4ef0c73e441fcb781ad2e5584db4d7d827e3619204b1fda2060c6cc5e967d258e788533f89481ce5038068dd30937f6c0cefac028d0d05aa2cb3f7c9c89e65998da9a5a1a716122b3a71c3089cf75045aec0f9a0428114c661a22cc1d5f855b2c1d1bca6cd39ab3256c2034ee131078e21eb6f0a7b8bef1dd3f546a25587010001	\\xfdb28df13f5a0a8be4ba1859482e3b22fd5ede546987d5b3edb95e1ce655effd701d8d29616c40f8b9e3521d6e3be8a92315132269a4d8f10157b78f3ba4b10d	1679820557000000	1680425357000000	1743497357000000	1838105357000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
153	\\x8169255361af7456b6d7159e250d332dce46cdcb3339e6cb1b7f334e3f807330aa6e353e58fb66f325d945cc2f074e3418ba4a00b49e197de21e243180cef64b	1	0	\\x000000010000000000800003a65e516016cad6a796b52600aae17c77601972563f63e3eefcbb7d7bc8fee9097241b300abc1aef13ce12c850722de5829b6086652983565b6a1bca8dff9a0bbff7481f01bf59f704545d15c2c258aba150297256346bd44e2b8a82e3efde6b6a263623f227eaaf9321e3550774b48dc320174785dd482d469514193611efbe9010001	\\x0ff171d9fce3111b09493e6adb742299daf8ac2bd6087d0e7921028e651197d90ade7bcf6ed041af39975d8da976a14e531188e675932c88905e719255d88503	1668939557000000	1669544357000000	1732616357000000	1827224357000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
154	\\x8229ea932fbf782e592b10f50db250bba6ea682b9bb160e4ef371ea5a58fe466760970b8804f781d6b5148b7e8bb9e3740526ac09ddbff8e2acb3990ba8acedb	1	0	\\x000000010000000000800003b9ec51cd696ac2f428205b1826deac86728551bd8a84f6b3f7a1de0ee437b04abedd4e5077161f10c507089d9b4320991a5e141a6a7d3cd55a973b091b1aca26fd7ff88e000a2ae2ff080f799182c5a469632236c634146c69d58f70f8f5759c7e840cbaeffa1920659944e953248bbe84f5b7e8b1ea7a0e8384f71b7d7aa11d010001	\\x44a81409c43044ad25d25054e469b5aa4699503670eb5681a0c3016ed8a26581bbaa951b24d9db43157e209c5f8616b0ba9d31db022cf17c0ad42dd84b1a410f	1682238557000000	1682843357000000	1745915357000000	1840523357000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
155	\\x875984c40528b5cda994e9e69d595d857853ebd952c09a3b119cd7ee7dd389ac691057ba9d5f18ebb5b31313eb1c6d1146e5bcb157cf818c25dfbe4a509c489a	1	0	\\x000000010000000000800003a140d4debf359769d99697c0c78c5161a3c46603bc20bf584745e60a590ddf60824b0fafd0559b677e9b130e45ac57b7a8ec903bdc120fab2172ce9f2ea820ebacf9bdfa0e2f98397ec33e13504e0c68047ee24cd8deb99e378dfeabdfa81da8e6de4ec900f8d187fbe90f89f5eb3cfa1079ecff45716b449a5d26f02fac6f15010001	\\x15957da5c9e2228d30a16032714bdb9f4a42ffb5024cdd96d177d4d382c42a2cc7f8c1be6aa632170c625a67668d6900a3b99aa81b3f51b553b7e4395236790b	1678611557000000	1679216357000000	1742288357000000	1836896357000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
156	\\x88ed4a94b31ab177bb291b29eb8366bec5bb5246a8b407181cdeadfcd7def2b9cf3ca3aa418646f8803e0d08e2b352c69423d309bdad97ba42d98c35c5220260	1	0	\\x0000000100000000008000039b8e87542e4762f8baf37e071d8046dfc122b331115b72e4c31846970965974f90f59c3018cff50d9e74078cbc61832fff42382aaa839da97dbec0a5eb766313950eaab36fd4c0d9c15db9852727a1331481382f651ce3cd008e06481758ae43513618a6dd66bd528c2bc0160221c4508a1b416ee0ff74ede02e35070e2196b7010001	\\xd56b93f24dd28a8cabc5c3c3d60d364fe4a2067c5e4d6334b47d5e1f4e5be6ad31f7960f2eaed1862a6beaf5581b912d2235ce20a67c6d3fa7e68dcb79dc080f	1665917057000000	1666521857000000	1729593857000000	1824201857000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
157	\\x883982e657b5594d2659f74677ec02113fa77ec612187cebbd9e4dce5715e78453f47ef9876f71952674e3f6e167a86a5f909fab183860fd7d58cd090a97267a	1	0	\\x000000010000000000800003b455ff8ac18a69beb74526d91488c7894d4941807d5c61b07b41aaeb4eed3c8477047175623bdb3e97e27cc8fd3bcfaa5c78de4cc382d27ae9428a6d169ebb78859b998f3ed27db8c3e43b91d011af7f3ddc05fe12a232185c7970e811b64aec317f2261fc7521ea5ea41aa07a51210a423ef2989b0c935efb154df7e441ab63010001	\\xa8ce44b0ae2054e6c89aed3324f157e7065d7f1601b8ad476d9e1b6feeae9e40fe36c232b33a6ac9e717a5617246921910e50f409a0b4c6542677faa1884960b	1664103557000000	1664708357000000	1727780357000000	1822388357000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
158	\\x8cadafc07be917a29241b81f1b488aea67a3ef4604bc693efa18e233416322a8425182c5e341cb358011f0885ecfaa4723c78efd31f92d4788a04eb47d154169	1	0	\\x000000010000000000800003d2f25f01be6c345705705b828e720b5791e8203874706e9b8668a772bea2e7af994aeb1d9e4bf3612b857b94a16682fd4e60a41abec841635c6ec2a632c608c1d8ca004c283415a60ee28f9b1807b7b142fc34c407b9d56e84f22a3e9c016b349ab8bde97f6d9cf48556dfc8d34b17762f10d007b47f969db9e02c83568e1e9d010001	\\x27532690683b9ed3353884c16a4bd9f2848acee282fbea41165df371757d54c0e7c9604546583c7a58a0e29f9c682d8ed5df506a3fdb513934aa488acc819009	1678611557000000	1679216357000000	1742288357000000	1836896357000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
159	\\x8d41044e8bf8aa06c559d0a389863394ab9874dff3be34c9c6e16296f25fe0d364b5e645fcfa9deb5c60c6bbbdc4b78771618cc7a34d4f895f6776332ffd9dbc	1	0	\\x000000010000000000800003ca3ef7506a657dd65464e79be184f02ed066d89d71ca6ccc0bbb3a5ac819dcf2a7a7a337264020389704d38e37914e9824bb833ffbac19987345f6d983d64b061dcbbb1607ca7bff37e17c7f6b8650ae098986a9562cc82498882adaea48c70e937cd0b1fed3fd9de63d6ad8400b621393ee82945cad77c55e79fcb1cf009653010001	\\x035dcce90ebe6b03743218afe99dd4c69ceae85e0fae95945cb6f14c0ca5845876bac8c39f033564da0933968abe9fe4bdb1f51649145f3e4d3521beb95b5109	1662290057000000	1662894857000000	1725966857000000	1820574857000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
160	\\x8efd5a0111d525a42b43ba5cd3e1428da5743d13cf5bfc7932b19d2c1ab8396061e162f5702d7ff14b30c27c73e83a09918c4b3e78965d38b61210e5c74fb6da	1	0	\\x000000010000000000800003a0ed66d6b6c90fa362c1cbfd00eba303bdc41e31dfb4d2069afabc6c527916ee9d4b1438eedbd818bcef0838ac6816f790056264416c77f2d9840fad41aa28986b59b55243dd03f8de7fc7d243480bfae197661d4e01628d5063a18c719b3cbc0e0f920e72e986b712eddfb03d3bd0d908860665906854a4fcdcb489efce1d4b010001	\\xe0ea057c90b2c8e4688bad079ec12ceacee344ef9560c340e2aafb06a2a01018e4c0451c032277883ad028da58f15dd9cfbd2386a80af7025f138801ca43e80d	1684052057000000	1684656857000000	1747728857000000	1842336857000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
161	\\x927185493202f08201b928095313108bcf7cd774978301a0d248872ed360f385e9afaf7f6835e987d50d46273817322a7112b8fa0d2062dfb8da2fe11ff1b9a2	1	0	\\x000000010000000000800003c69733fe993d4b1628360c68853bab60dfe4f8c2fdf829ae257b9d513eb8333cd1c7689ca96e5d94131cb8f7fad3c4a81f80d62193ef84b3f882247fbfc28d1cbadc0f0dced8269e845126fec06fead80e7e7da5dae07670a28805b9d8477e034c91801a8189c565c09c56adc1786398be386888236e09aab829c4ec1ac8eb7b010001	\\x0ea83ca0ef7b3c94028ff0d066a6274921805089b23b4eb551e34993320cdabf356e5673dadac70c824cd28888342345006fe0b121fb4a2399e62297bf659d0d	1667730557000000	1668335357000000	1731407357000000	1826015357000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
162	\\x92f92e9de502c07be8decdb1293cfe6347ed63d07f16b391fc587406c33e3a1b6971bac33f5f43bb7bed98fb2031c821861a2d2741bb03605e29ebe944626ea4	1	0	\\x000000010000000000800003b7f15699eb7f01c92f5a05301251731461f69de7c721570ea0e977be78e25623a536043f5b9287d35fd08d29e6a8edbd4d8b02251370fc7ac3be0a6a7b7841ffc97c722d27652e4723620064fe7b2618e5922f1b2865bcdce71250ea544064b5bd70f37518004583385dde3b48221d54355a167d914d6543fc483c380b61e72f010001	\\x9d15b2b76d110b26f3ec0a000c8467b229471e5a326a2327e623fdaab00517c3688d7d93505e50df8327bad02e25a25570b648c0818b2869df9ae36ecadfcb0a	1658663057000000	1659267857000000	1722339857000000	1816947857000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
163	\\x943df7797f63f86601fdf464288cc2e3eb9f862126c487ee5e803c6ba45616ed29b964575600593a2f626a224c00793a49eb645d4bb8e2415cf02d523d564b0f	1	0	\\x000000010000000000800003b3cabb0712c5a0375f64fb071f48350d42ec6514945d8166bcdde26327fc47e1ed9e1552cd171ac9e96b75459710f49b724fa42f2a98a8ac991ac952e5b9dbe63a6cff0c6d7cbe252a0bdb8e59188ec82431474d68974c55d00a2e7aa488724987decb6efb15d23406b846ea53f42371c98ccd0634a0ef1808a9cc4801ecfe35010001	\\x880e4c8106ed2058d917ecc640a123bf90b283adb2adf22f5afd46445d3aaccaae637427428c4dbe59e33d2954abc97dd175d42883bf715e37d14cb7c6134203	1684656557000000	1685261357000000	1748333357000000	1842941357000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
164	\\x99f15c6a41cb0908f8705d9417bf64337d747502db6e6cc74dc4594e4d0b41715a16fb9894d53976ebd67e63922f95fdd2cda5a131aaaa3f42122fe28fc9e165	1	0	\\x000000010000000000800003db87d2d125b5526c5604e631cb997a6397f993d68aff4c1ede15e2830e66c4478482cf9baa89dc930b10a7cfcbe9d49af3d7054fd2d087c98d2de9582287d9cef53efe20ba4b331d83c55ead1049092a2be60d4f6c91f09b9f03f5866f96de316546cc6c8b9d8bccbc3c44fbdae111e8726ada54d415b8ae619536f5700b2ec7010001	\\x43962e270a7229da2ce3fbf8b4d7ce9b0ed64d15f8c25c759a78fcee57c987cea3bd5c9b0c088b9f1f211d4fcb4a045cd9a1ed54c2fde7bdbfe450555c628905	1659872057000000	1660476857000000	1723548857000000	1818156857000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
165	\\x9cdd5e829fa66c9da8c14f7eaafb656560c08217df62e369d84eddc5aedb836716537a687aaedb6bd00984a8a50cecafd176e61c45e11791d2657c0eff7346da	1	0	\\x0000000100000000008000039e8ddf6df0aba3b2985cca7aab514c6ffbc663c4287ea0e8b4811c85977dfd263a5a2ece281ef52b0cc8ce91ef7ee8b41c654fe2d9174f87b005c24c67de1ce1ee2ae7b62d0dc444acca64cfd49ad045f5ecd2790d717ef1f18dc0fc643cb2b4b58ff4a67c0b92fe3dd216d56f442b2b7e91d03d7a018e5dfc54c84de667166d010001	\\xa596a7d9d824edbdb30768682fbfcb9ce573ccad59089272864c41dff8ce4b42b3624027dbcc0aa5aa286b97e3a41fb397c08a917dd7b49fff48646985dab305	1665917057000000	1666521857000000	1729593857000000	1824201857000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
166	\\x9db900f537036e82f4b89f1fff39ca9cbcdac427c368e8631400e78891c2db8f4d87fa8621c7c0d9b9ee27dc2515822825b145b3b71cdc7eb194f4a54ea64290	1	0	\\x000000010000000000800003c245520ff54fb98f2155f9a7525ca38d3ab4a47199477e9468e15fc7df61e7f91ca59f6d817f5d06cc8755900ecdeb0448f070edd4a0cbed2bab73a1724a19aad0fe6251b7f6c3589566eb9560e5cecce4d65091cff27b32eb1728bb6a8ede9cfd66b405cfa859c4189dc45a94fcbe7346d26d6eae22f7ed911f33d6c3bcf369010001	\\x39147a18981d14af6fd23b234f7e6099e204ddbd05aed3c69b80ae606ec1430d4f63848c61401e2f6cdde76af06bc576ac0f39aa0e01e7799e17a6e3f15d0702	1687074557000000	1687679357000000	1750751357000000	1845359357000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
167	\\xa15d251ea52572155e9109fda8e6b59a2506cf45861c5d3e4dc778db1b6006c56d6ce962a13cffe819e5b3674a6189442e3c9f3fac63f9631d83fff8ef8c8250	1	0	\\x000000010000000000800003b7667e39bc64b8584af24e5571775815b726972d128d8397c2c98b633d447b92d89eff008d35f2d2f65e500aa84f7ecbb5efcd1342cfc618ec4685853d635054e2b1556c62a4a81140a8c708dc0223f61e97520a8c106b857db821c3e705745d4761df00d3e70c5a96f8ed33c871787df2d9868d7feed42636ceec1b90c9237f010001	\\x93ce4a85af5c131f537a21d3cfbc5f5bb43bd464b8e46ae4d0d7c1f1f93edd1b682817eb9e15bf58a6eb661dd7f7a16443b116205cd0e677fae5ee09599ea00f	1679216057000000	1679820857000000	1742892857000000	1837500857000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
168	\\xa45d7a76bd9527662bbd2bda0cd8b7e2911f3f0efab66744ddbe7f094a99fa9673f7a3fb58d05b7dfad9474a6423d8aa9f54cc2a2f27cf94081afdb3a7545274	1	0	\\x000000010000000000800003b475d2e37f81008ad27cf596bbf58d6642fb57a161f892ee570941823ebc7c0f5b03bf4e3d7584c069be620aa51dd8f81ea093282e757fa718e769eaaf138e31236f37c2c5fd31ecbefae2fd19931aa08f9d691c7ae890802634384174b234e8241f46891848056338655a43a2daa68b7ef51b3452d09f24d3098b9a28627723010001	\\x9b269b93df22fa36b663fb2912655477c70b61647d128f3153eb5549dc98cac56b619b495b8f7fffe7bb52413acfd9624693c1c1896cd9589330335046903001	1670148557000000	1670753357000000	1733825357000000	1828433357000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
169	\\xa581e2e7b6ddbefff80ec38600be094788126968c392f7da6856d2b837b3a80d60397f0fe732101c5f5c61a98754db9bb0cd0bebd0c08e9d0c5758c919a42f07	1	0	\\x000000010000000000800003c06e5d6cebb17572b76fad3df4dd86911f9757a4bdfd395a1027f0a1be18262256df08dd57c3ba8e2b66df141829bd92bb7fbd5b2871bb42bf35c63da9bfe5d9143295bbea4fc95b86e1351401d68dddf59b43244978af25f1ec083d654f21a683d3ee10a87e60f60c7b7567e048fab5a6cb182214db2a0817d3dfe07de37515010001	\\x26764a8f60a11d201f527392eb739e9050c1a705623f0bff9d10a389c7cf8a7a9b694660ce0248ca45c3c5dceb0881f334842a14021ec23dd7b9cc5976ba7008	1674380057000000	1674984857000000	1738056857000000	1832664857000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
170	\\xa9596d701529f8b355d299bb3b76837860bfd479ddf84440c42a67756e263560046a012d05848c3ef16614e9a593cc17cc4d872a053e6d51c8c17c6a63062da5	1	0	\\x000000010000000000800003f3df78148a221a6c627b9bb3eafdd421b886075062228eddc8193475ec4ebae37e034ab83d7ccdf3f11cf8e289c5ce01039ae759bb60883b760233b0698e734e28417626207d4cf9856bb8dfc54da465d17405c42600e0c09a7f8877d15d6f2125337d2697eb13f6a1b94cf3d04d113115565b4d1717187415df8d8088f87a89010001	\\x1db5f620689d33b0e7b66d53436f112d2d9fbeafb708f8cf632dd3dd8dc6f26cf7e443028e3e9e45678318f2524085f56c400b9e1e7b62d6d13a20d0830a1709	1683447557000000	1684052357000000	1747124357000000	1841732357000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
171	\\xaadd969d02b913bb66c2433d42105f999ce0bfac5892df71c411a05a0d075e594c32715fd8d7cdac3b19189977c7c1fd9e6e8f3c9e4a26505865d887bd581ab9	1	0	\\x000000010000000000800003d9f87b2849dfba4ce1d78a7e956954af10ba374091f9ef821b8b2443e517c5199884a643cc3ab32d86bc7b3f966661233536d0cad89aeca4ee0703a9a2e52e5c8755c721c5a40562a203b2f04d984bdb358dc01c1ffbc178ca7f9a965baff8e99855f49229daf3224860893cc1b14ffde526c0f7cae8c2abfcb6e262cd18fbc5010001	\\x8d545da2ab0e7450bf4e4d3a2e357d775ae25178a7ccf9612dd11f242f697e4cc4313d5edc9461c81025e094493469c3b57206022f9e1eec0991975ca032db07	1666521557000000	1667126357000000	1730198357000000	1824806357000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
172	\\xaced803672f834ff99ed92564a379d538175543aba0654c4950d1ffb76dd89ad635d962e28cb744f1850c32d6dc89af5c79a5932065e97d8f4941b5862bcdf60	1	0	\\x000000010000000000800003c2e26615e269db0080127b1c22c949abe9f76a3ea8d7cc963e92ad0d66901c52059edd22f99268449c82129a369ca038564a31d127a21ee6c2c4f8da95f4b95c0cad3cf2b5a71afae03888ab2859031811946ba4f65354af2ed42c7025b5a254f769506b9860210a42efde4f0c296d88805cf0d8aae21e600a1b0a2efed702cf010001	\\xe57697962249364edf66a757a9b78d9724a1cd1e59bdb962101a104c361494837dbb548fa963827501ffd3b99b76ef17c1f3512c2372fa29986e60082052e901	1674380057000000	1674984857000000	1738056857000000	1832664857000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
173	\\xad094b7fbf15d97b38a2b30741ac7f66607d0d765755a3ccf7724bf3766d77f6b67e61beb5202a9f21b9619634991bb3392ed96cba30fcaf6a09d2f62080cca7	1	0	\\x000000010000000000800003cd736dabfb1cab762a504edc6cd118ca51160864a154beb567cc2642e6450b90df0d51198d244314f6b1cfa295c498113ae3422367f24de0e83cf1b6ae7947a28c7bfed864b4febdb8c48c1266ff074f0f82addc476e48cc5a3f329ad4230fc689cee2fc5598b5b1f1d5749622ffb36a2cb0b9554d8555cb33326945e2811213010001	\\x09b26c50c180095678a443c6795c4265a7f35d4e0f60b1d72c9518258064b6788f61a597b6b0146de9dc80365e8be4dd9ac54aba4930e3147361268936977d03	1676193557000000	1676798357000000	1739870357000000	1834478357000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
174	\\xae11a8c08ef779e5e93039a01eecfc8db858228be4b7d8b74c469b3d1611d550df8034e7f88d642450edb5960698a740d55d79c62c9bf0135755a43b5dc2430c	1	0	\\x0000000100000000008000039d6618d53d193bf56afeba3f3f30dd53fc04379981b6c0fe9fb2ba44def7b0c7c123dc4bb2617c410dc5264bb80adaf3b9f20babb3c90fe53fb32c86a49815aa422a9037a9fb68a8c4656ae3302a4c95f2fc49b4aa0659a50ecfbbaf3a6d610462ba974bee0f10d7dcf0cf94186dbb9b84855ddbc26374d72408ff30af0a1b4d010001	\\x3de2aebf14f7d62d6adfbe01811b8c2d288c7f1c0de4e4e88b3f567e18397e1a39097ab54a71bac996cc95600981a231abc29f5c249eac7a14080560c2dbf204	1673775557000000	1674380357000000	1737452357000000	1832060357000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
175	\\xb1113abbd5104b1ff99a7e3cef66d8e4bb5f40a8d0c947c1830209f45c2c2efc68434ab5c5d58e67cd3c42e00e79a0b6b45edc198922c5f1dc3a157b60a57491	1	0	\\x000000010000000000800003c6e384f7003843ae3d8d8fc57a9b82571650f71094febce8716b510ba1760a41efea7ae535fca8c35cb0dfebf644a53066040a80568266df73a243c94dd6ba2b524f32e0cc3e47f3b50a519fdf0cc92bb14ea7e2fb05d07c00927706d83efd635b199a320905da2c51cfc7b8da0408d4a463ad256db2ec232d7a4bd922ad8d31010001	\\x676d4f958a29ee4399ca1c64b83e0ca5a59a1215c7455b51daee29843a445eb7a61633acb78b3ee5f438eb4ae19b7bee82958d014a921bfe684e75c6fe2ddc0a	1686470057000000	1687074857000000	1750146857000000	1844754857000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
176	\\xb2e9a9b5f6428f322dbac921dcd7ec76ec76fa31a07fdf993d617d46d999a079eb82ba9a989eb4e854a3b11745af501ce1717316ca2fe131ffa7a64c548b7463	1	0	\\x000000010000000000800003aa5e66aafa1c7a7223438a141cf676744d18e4eceb432f2e1724a743fec8604ff6e0f7277f569015043f4f365f8609693b0f1c37d00edb03d9069af507047ad9b54e5c06fe27c85491babc14014f7c2571738d1660b8a2244fd4c1a909b736660da1b07ec435a0b964e8710b2cdb839aeacd9cda8df674ceb9f3d0ba2ca577ab010001	\\x3730b8ece28915afa266a234a8dcea52a42266944f9026b15dd92f998172ed9625bfad7bfd1542af1d19ca571d5e46407cdc9874be6720ab1bb69eecaffb1e00	1659872057000000	1660476857000000	1723548857000000	1818156857000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
177	\\xb2fdabf3f8f21472ff2253220ade047ae39d3ee1c9fa804e7214f538385f70f1e91a6b85a36e24182febe7b7988ebe52ac98b15e7303f0c69a00e04c1e8cae31	1	0	\\x000000010000000000800003d5dbe53df5b67eb33543085550c9f8eafb0f22cc37191cd4fd659d8f2041dd61d5d0934c5ffeb5c706a3da43dbe42f87c6e6357bdd82660795773bebe9c1fee732d93bea7741972364272b944694c3c1ef4572f27a2b31690c370c0fd866a3974aca96715cb5600f5a6d139a5920ae7897a7c22160d92829fe73376c06769dd3010001	\\x8a334b558ed9da015c2627daf1b42cc17bbec2cf34ae13c7171abd7b1c7be8439c86f56dc8125f80fb9bceac5fbf6bbfa751bb116ec789bf59e0c156fa500000	1667126057000000	1667730857000000	1730802857000000	1825410857000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
178	\\xb3618b06474459c5297b71ca4be3aab845f78ba1d780ca259baf9e64803c91f6299111fcbca4be607f4e39b8bb16704e4d858187da6fe98ba177026ca65239dd	1	0	\\x000000010000000000800003fd9217a5137a5ab90d03fb46c3eaec55f8e283a0fd63aa6c12e2316e01e529bd5e55c29e8fd45abff46c03e008cb46a3c6061a17155c5d6aae830226f528a5cdbd79521d3a8242a3368542568d95e7401dac2386dfcac1c7387c61e2e5d08b74f9e167592ab6559941b2ff9000e426d2b45f2d93f0cfbbe0cdf127df171f4c11010001	\\x4870be716f1f71beac633a27d41b092ef2fb4557e068aa9ffe95dd1dea77c74218955e6f1e9ec312cfb58da8c019f3b725eb5a2ace14b5411edaa28c09f3af02	1676193557000000	1676798357000000	1739870357000000	1834478357000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
179	\\xb651da48999f7b60f3791ef9a77472163105cf406555b3198d7ff1594c158f03eb2263dc37ce80cd5889282e2c13ba35f092f1f4805a685256110a0a910491fa	1	0	\\x000000010000000000800003dddd1bc32e0195766804fb15cc532acc08302d3b2dcb8766dbb42655b09d386c6521d548e6ed139fbba25afb6e007aa854eea94f7e68e018ec88ba0b31c1e2ef1f9fa054bb43ed7e22fa1ca000d23245c7f6b2801f835e61a516e97fa6ff1e920ca7a4dadaee0c793c3633e5f9050638e156f8f20cbcab32891b5279ce0fc7ef010001	\\x31901eb2d336a5dc84b5ac05cfad110a78feb013d4a63f9e2925210f911663844e38fbcc70ccf3cf78ec1e5f868b06f373a5e2b6d698efc81b29572e42e4f409	1656245057000000	1656849857000000	1719921857000000	1814529857000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
180	\\xb9b15dc2e6f9638788fd12c7a12e71a77b9b7223c2503b466ecb0c9c4dfc8fdb4bd37d4e33bc5738f02d072730b51ecd88416afc5608265194a4943087b88e18	1	0	\\x000000010000000000800003c26dfd65786013204c6d5e805a87b4a4a9b1a974ced48d0fe3af852f140e46e5027f78a51ee19e6f2bb9a0d5c518e8d59700eaec372fb403d1e84ff4d2750267654ea1bc39783a94907d041f881f69f7f7b3e3d043207347a8fe62b65e6e00a8403394a9806b96c13b4607f90681952773d719cb4a1423c2bab4eaa72eed7cb1010001	\\x68b6dbce51cfa37fad1eb83e1197c3ffe03dae10cfec679947de5641b67941fae8206ece5dc60f332fe2b6c412da16dc6cc79509990a102b9be38f6cb79d8a0b	1687074557000000	1687679357000000	1750751357000000	1845359357000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
181	\\xbc8514280e48ce2263c9fea9596870ea2861195b2f9e03570be242230666f670fd3cf6ae1e0bf6251d5d27cff93f8454e4c548154ab685fbf7d1af41791471f6	1	0	\\x000000010000000000800003ba8e52bba9d297d4b62be6a79e7d6a10dd6ea6b24f0f0c4683b8bb2f77fe63722bc35ac3c47f899b13853790c393751d6a7a10b9b77eb2f62bd926c7ba93535c59101e8b86f4703b3160a8c28b7c835542a28e036b99deaa48714dc847847d2577895f7e0c8b71d8ade5970885f986551d70cc3246e2fa1a757629b0b0cf2571010001	\\x70b02a7b0a6fd41408153912a283da55ad61676fb558612fbcef108c6f249e23741b72a5143b17bf562ba9f89c38a1438819d026b3836c8e493bb2243a390a0f	1663499057000000	1664103857000000	1727175857000000	1821783857000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
182	\\xbf4d22690d6009a80f7f0e85006550760c71727e969c66f9d1396141c2edd9aae9d61727bb6fd7835495929b0ce9720613bc6fb9f89781dcd202535f6791e222	1	0	\\x000000010000000000800003be489a328581f27b084ab82179f7a50cb807c62d5cecc520fbef8cde7571806a735525220e4b1003f62a347bbd1da8115032ab6bbf60bf890ea2bce021dacbc796032e14ee27cbf2a5735cc1bc80cbb06ab131c7f233213874985c5cad9be56fad34105d8a5b1081e8dae55eafb935318b6a61959e27116662fa7ed2e44bbfef010001	\\xc85571079ca27250bdb1b5d9eaaf287c049150e19cf1e24da1611cd2ab67b5a5b930e2756d1cc5d96db57b53c66c9f709db83af34af9ae481dbcdea738524c02	1677402557000000	1678007357000000	1741079357000000	1835687357000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
183	\\xbf4da73839fd26585970918dd98b6e893cde41bcb33b3b7ab30d90b7fa99cc2e6e70c6fa6612a1f2814e509ff3f69e55f7677c2c35e6ac326299da9e84c7f6ff	1	0	\\x000000010000000000800003d75720de628ea8010e852472292404fd211424e5d9fb107873fc17c5994ffbd92df7afeddc75bd7d58333d82e15352689f8e0134346fcde7895891f94c632d26779a977c71c8577afaa5361c9078586621de11212f7d8ff90347fc70d082945b026cc0c6d8113fadf53eea9de927e92a541568e85b09d00e23051c6e3dfce58f010001	\\xea52ebbbaaa3ea4cad3995f017e64fdc681ff0f8b945f33eae50408844be378caececcabdd34fa7240d05cc062373615dbe498d48fcf79deefe5a96f8c30550b	1664708057000000	1665312857000000	1728384857000000	1822992857000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
184	\\xc249be26028b291f39e2745c4eb929038934dc4492d4e4b93c1ef6e6fe94a91d8499d4e95441e145c0f5053435cde3d3e73627befbf2443f4ba3924d93109012	1	0	\\x000000010000000000800003d14b8a6f25b543b938e9686861be06e7015bb1ea4b15b9c93d8e1bb385464b6556f0a9a1240e67d58dd6cb696dfc5879765c996d0e3b7a8a1d8f9cffcb60e3fa7e9efe572d6a6e0b0154680b296e06c05abe480fdc0e8f4950350a3cb11503e4a2d27f298a61b127b8828574d90759e72c7974ea1698c0b067bd159571f00451010001	\\x28b89ecefe6144f4fb25622aded545b03593d067ac8025c9cfa224a557e34c73f019c56ad1c159a7a640f3722c582fc1b0ad9d56c5c166e4f66e61dd09cc7d07	1656245057000000	1656849857000000	1719921857000000	1814529857000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
185	\\xc375ae29555d01e60f37a971dce744a897974d9d6afb830018591a7d4cf1182eca146c2cf0b4d4b17f9f03990722b32f691b5a1b725534d58a7c83dcc67dec35	1	0	\\x000000010000000000800003db6af775ab773c4d2696c9413fab6d2b660bef17800d33ace3865f3d210af896016098da79978e5be39be59df254a01905c48952bb53744bcb698fbe437dd8ef641a328bbca278965f968f410ead2595f1d95e2165a520c5477ac3be82cb144fbe5bda10cb0e66b69bcc05bd18c743fed854341ebddf688a621fccc0f610a899010001	\\x345a5ae05581dedd9a127064f2c931558a5d5d17ce21eee1535738d1c919244fa675592d046ce02398cedc269aaf63eb899e3549bcbab1de082f634f75c42608	1662894557000000	1663499357000000	1726571357000000	1821179357000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
186	\\xc7f98773ed54a4bb14b4f686696f7856ce095e418934779f33b15ed3b28ba5dc575005b846a0f4c598e9c400ea854693ea80ba114370d3c84beae563bef323f0	1	0	\\x000000010000000000800003c1abadf933c6e59d3b43c19824bf78b4b1169595dcba904c35dd40404b18c14567836367c501ab105b1c20ed6df57553fb2ce4ef408f420c4f458888d19984393be31932304e645610513110637b357ceb373211bf003ce2a2c248da0e768183c75a55bfaa2a1238c40118dfb98a5aad7713974b547e94283b5f8b373a411eb9010001	\\x5eea7411b458dca68e5a8e2c467719546ea8d167740465045c3e3cf557b94b768924c978d0a42a7d7972a694532874e70a218f875eae644968b17287c0c9c407	1679216057000000	1679820857000000	1742892857000000	1837500857000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
187	\\xd06d6f1dd80f26f151d7bf5677d751f9c3dcb641b9eadd2730860514e04ac4b5d1e99db158ae41aa193bc6959d6f1a65bf8fc4e3499c5528b5d95dd1b8e8bb8a	1	0	\\x000000010000000000800003ad4e995f152d4772bf998cd2f88b0ff87e37bbbbb2516a5a6d280fae973ef2776cfefa89f116a20409cf28896c216d088cb11f5cd665fb42b2d501b1899663be771335468e61acec14115854fdb31096487d5306f1465246a1b02c009597b9ffbbd8bab432aba47015139675a0accb5738d7a8358536702aabac66e426f39aef010001	\\x07643ddc27d09ac3662c423625650564243329ff91e036baeae63e700b438261f5474cf308414a9abcfdce71aa4344b0b80d45e27fa14ed10920dccecca5f208	1672566557000000	1673171357000000	1736243357000000	1830851357000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
188	\\xd19922d9af544dacf25dcd40b37d12602bd322148f0575f7419190aa35672a5c8bea7fad85f0c190c3e40903cdd0d66b616ca96824a3b5faad8b2522f16eed28	1	0	\\x000000010000000000800003d593e13425e319372e0c19bf839334007d810c391d2e0517a5525141870491cda6626d96d76175f42e0e3a78d7fdddd6b09028cd7724541edd7abcf496e9a319efdfd984493dfc129706bc03726c8e1c4fd05cab3cbdd74695f19fb66b346772171820b038df6bb5e6005df97fa5cf0fc913c604d945743042b1217068f9af73010001	\\xdf55a834da2fd26f0add62c07dab1804b10872242d64bc9decda0f843188a8a7749ca9f4e1e91f9047277bcd8d3a283fe38a445834342f68b87bd7faeed9500a	1684656557000000	1685261357000000	1748333357000000	1842941357000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
189	\\xd28dd7615b4f437e3867a9be8b3d04ce89558c94063b332249cf94302014486dbbdaa7f9dcb52b460b23d4dbfe7487470386cb4a482a200486469555f3194c82	1	0	\\x000000010000000000800003b5cb13a5934601ed700a61227afc9cfde9dbf0c1013da3c80f071600f14db20521234bbcd8770d9396ab37ccd6405d646789f8c8d938afda316988f207c0c5c6fda0879413cad7902d4a786894dc83455f344b20bf53169f2d09875e2697294b97057dae7b85aced3854f27ceb450fbd08bf7027d91b1d23d11662521f3fd7f1010001	\\x3cbf72112086c2ab19f089dee5741e595173e9c3369066e0b2b4a8e0a9c891efa95867c20ac3934483363d93a603ee3fb30e08e22e1d5518007540d2ccc5a406	1685261057000000	1685865857000000	1748937857000000	1843545857000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
190	\\xd2459b41ec3d44ce9be1371b49ee87815350d671b3ab7df1b6838725681d6680cbf1d40850e1e6f00276a66aea87fd65ccda0efecbbad7d64aaacc4fc3135f5a	1	0	\\x000000010000000000800003c524ac7ccea4220c80938062322ee4fb05040cfd87b6120602fc1090fea9d5648cdd8199cc5a42a9d386c7bab6fe1639619c4838c3d2e454876574e39b35f5a0f5cbe6ba4761a2d5d957d75f8efaf657205c7f5b0b54752bcc394f8070ac7c47d3a837bd0295a19df21efba123da375e526611a582947b7a8e670c80b623b305010001	\\x04abe65996dff7898e8092b2fba0191f5a496820f8be16ecdbfb97752ec9f1dc83279d09470d11327e88f3e51fddee6d6e06822576a1998b10623819e6278905	1670148557000000	1670753357000000	1733825357000000	1828433357000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
191	\\xda5d319f783abfed5d28264c0196598cd8daa6999efef6829a7a574698d8a081a8029229d8b22eb0dd584fcff5b2c13985d937f6e00f85e1339f37f23a1e8db6	1	0	\\x000000010000000000800003e4de2478a06627e3c248230706b90deeeb3da648dcad9d7c80abf1a0f11a374a615c1a4093415ecf95e56a934d993b79499b9af2087ee7e0aa9a62014dcf91419898721ccf945597c84c09ad4961678af3a3c9128588d0c32c7c2f26ac11820eee9df88d09a24bae7e1b1b91057d5b2e8e5d7df74905f70941c2ecc7d5d2c945010001	\\xf4ad271876fd0d806d3c75d0f252e28cf6b35327e28d63d9a7216e6ec3f3675f08eec63ea18a9c2b2b9001bb6cbee897e33946f0e1d4a353250b81ec852c2b02	1659267557000000	1659872357000000	1722944357000000	1817552357000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
192	\\xe289eb6fb2ed760301d1754b7b62f4a4eb316721caf675f5d9bf72ef4451241194fd8c39ad686cc7d5669ed7acd677030ab6ad4ce622f9558eef75024dcada43	1	0	\\x000000010000000000800003a4fc7df4fdfdee5d4851bfac9499634726c97d04044519cf45e2843e7a86e5a7bff8a51f5c6804872d2116a9c079eae3e6ba1b33d29af72e28dbbf85ab5889a785a115788839de51c17c3f52c134fc4c8454e23158dd455ca63bb6f11d46a6ff6afd99d432a18cd44bd9eb0e4078459ce1792496681a7ec4210203538c6d5a35010001	\\xe0799ca0a8b6d9f2f13d269a545c235f72b0e9862eb3d100fc9388d63ce5ce4fcd6f58872c44bb71941410a4728bb09abc23e02f4ab46bc22d9aac4c5e12c009	1670148557000000	1670753357000000	1733825357000000	1828433357000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
193	\\xe2d9974cc3cfb084e2b2ca24da3d54f5069e7ff789c744a36c17de2bc44c7c2f95f95f506e1ad725a80fc6ef144334560e71d1dbec52645c7dc877ab895ea11f	1	0	\\x000000010000000000800003c87dea5b853c55468f83c976e6ba50a02352fda54e7b4c31707c83daa18cecbccfb56d921c99072dccfdb9b8f074c5b99fef9ad6c410e7528096958e77fe1cf2099314bf2efaa530864a46ccfe15074feb431f30d69fec29199b033a2cde76eada606527e91e081b597d13219e555f7d2fbe5025765801e6a1b625cddccbfd83010001	\\xa061f29e8295f40588c812afb586a1a0b7790cf99f1fafb2285d334cdede43d478204af88558b1e631f600424f6c2491bfa97923eb2c8f3038b5df4489d0e506	1679216057000000	1679820857000000	1742892857000000	1837500857000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
194	\\xe4f95993e183aa4f1ff65235f692cac80e6cb0d751990e159c2785f389dd1f32115b8888a302985f9781238b67e719f83f91450d20c22ab2f4b5d20b0d7bc33d	1	0	\\x000000010000000000800003bedeb7250869320c91cb21b2a1fb5917eb9909a21a442810703ee6ea6901db192e7dfd5c4f33dedd16987e438646417c618d15f0496f35d7027dd310ef7f0775c3f4e82a92b4514d112c76379a3ed665e710bb0f07fcc6514f83e9d958518cf3396e6485a7a7cfdf376c763b9794e65788fefde713ac37376384bde738765ef7010001	\\x510ce8219c282037e2697828bb2b801d62f279b036c1db23d2276adba000f0a22230f540b815e77ad5bb6be24c66e568231e6b102ab56b0712dff8b3a86eff07	1655640557000000	1656245357000000	1719317357000000	1813925357000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
195	\\xe5c55cd0317c8712ce3cf569285aae5a5e5999c0169227364e05565d33d3470661cc9acd9a35cce5113da3558b6b38467a8001dd8d404635a0d89ebd08ae8194	1	0	\\x000000010000000000800003f28f63e1a46fdca10ed0e8b97b5c1fad947a3ab309bf0f4432715dd5fb4378a9f6d15e128cbdf86ed9786e4015fd6f09482038fbb75b318075b507f8172a654229bdd21073ab42391f3856b209e2fc4646a4e15714c97f189a35a65fdf838cb94f8243a9a41fbc1b83be2754b365ff456503b0f6cc14119d65f43bf46097115f010001	\\x9c7440e2084e1d5495c13d3aca2f50c6be31eecdf6dbad9734bbee9465e06d8c8fc99a258b63d6750f89dfd22a3dbd0caf49ce30108789bd05d115d0295aaa03	1658663057000000	1659267857000000	1722339857000000	1816947857000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
196	\\xe80976c0f3b3c05e2e712a849a8b014cb79256bea36867039e58e92f4ebb927c76088d23322ac26f627dff9ea01c237b930e9291ce140d11e5a3d33a2f3be00f	1	0	\\x000000010000000000800003ea98de8d1fe15e1b36cf1b59165b381cc715d6a2899cd1c7487fab18da76a80dd896f8428f65f44ef89eded5aea2455e9a03156c5a347b9b0b65bfe9e65515acdefff7b8538a07722a2da94ec689cf60c3460f6a2bb226893ce6651045aec2c917594ca593dbcff5c2ecc4e641b579b49bf78d5311361c737d5912acdc98726d010001	\\xb1af1a06cc42c436eeb5bea86babae46236e99a554ccfaabf867a6a0f8a6988b1de65090cd865a31e4e6a8314b4b1ba8edaa8c25047645bcaaf8864868594606	1682238557000000	1682843357000000	1745915357000000	1840523357000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
197	\\xe8751feee57cf472af7e6ea8fac6394ab3df6c4e0e166efccd05bbd450988f75893e1c52368556181e3db1570725c00fcab57f9d1e9a975398b4878f27cb46e8	1	0	\\x000000010000000000800003c0b17b11facd0adc564e7238c1256c6833655c3c9c54743bf3c1c556ffa9f4dbcef789989c04225ff767720b5d81926466b043b69d85e44ca95373c9d0c8dd2a94320430c2ed5c5a0116c4b6efb5a9813da3d94e8b413e486d8af6f2e00ce9bbae41260fcac53bcb28af4d212b4db2acf8ef80cf7fe06095c137867a4502804f010001	\\x49accffbe5c4a6f1cae6d29d5f4d066b76bd93eb3c3db9d3d20d7f399551c83d308fcbada155b4eb6ad5b210c4740ebeb4b06a5949b23ca376a27fc3e6475b0c	1661685557000000	1662290357000000	1725362357000000	1819970357000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
198	\\xeb859eca2b55a62d79ff69c7a83f3c11355eb27b7ae27b06a54530df98a6fb5c64d0b6a9a9813e0596c78c5998ed6ba613a515b6d4d61f6cede154d23c31d7f9	1	0	\\x000000010000000000800003b64340aacb23a3467728415fd505db7d95d603c1b006215a0984807bcd56f69bb11fd15a8bd72a8a7a00bce7af46a5c94bab91fbd7c51964746020a738491835df4c9c575e9f8485e64945e3bd70ec83315e47669a8dce414eca24b472ef338d1beb000ac1faa93829b973a5a5747d9422d78a55d58411fdba235a53ba7bee5b010001	\\x66ee2e7f6bfc12dd343d3b830e411b3e82a0928422284f22b2dc62e9f2a26cdb904cd9eec288e93daac22618d12f5549ed95d31768e05e0bdf0d3421912ddb07	1672566557000000	1673171357000000	1736243357000000	1830851357000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
199	\\xf6658e07cd03327399de43812b4ff26cc37fc10c45c40457741ce2f39d681349966de23827fd6be82fef8320488a353c84fe27f9cbf2d5142fdda2ed0d06b2fd	1	0	\\x0000000100000000008000039e230bdc8ca17c66933d90f94d882f544960b3966f8a0f1a969f56ffe4bb9b26670fde866797f1986fcc3879c6b0e140df9e4c9c5bc84659fa049c9cce8d13f7ef137caeb22dc17893e88df6206dd4ab2a2db82f3f6f8047b04fc224972cd476c84d9879676d108c7524e3ec31e5e7fdbeec9e10fe475cd2a904cc5e66de945f010001	\\xd94144f2e75bc8252606b337dfeaf654d5f4a93fc4a0e4ef0d62c8bfaf01e39d2084deca087f740954e5795b703bc313ab0533df730ec569029e5b48c5722607	1664103557000000	1664708357000000	1727780357000000	1822388357000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
200	\\xf9d95ea501e1805eb87605e773a0c13abc0d8c2212b336de172df7b3e4c27ee3d305a30cb4a6caa62b2f68a77e3d6d8e86ae7de1350b9e6106c849ccf21d1d13	1	0	\\x000000010000000000800003b75f400b63f4c015100731b31d0db8c07827543f29f6048cea9b7a2557eda0c356fbfbace9b7b0f8b72299b288f8b9ea6300420455056604edc3b7a73a587903b44d73b280cd346f3cc50d194e2af0290b2e7355984c6a5dfe488773bdec6414a977dc2a4f19dc9bcf91488fb8a53c29183e0d9ac4e8e9a33642c33a65e9e255010001	\\x021d34390670ded59fafc97a3a6ed69a593047b03716f6c671f6b20b46eb5fc1eaede24d9f806ec29921ad3ce7fe60c5cc69ff46f12fa929cc36a958c56b9a0a	1681634057000000	1682238857000000	1745310857000000	1839918857000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
201	\\xfc21de90e2abd9653c7c3985f5db466cd3ad94abb90f50b6e23ca5b4c3020bd31596866b15ea8cf446bd814fab084b70fedf4b1eff683136ea9cc7baa9fab532	1	0	\\x000000010000000000800003c4487e8b5a2fa6cc0bd0f87acd22ff3b35c321cc95ee17c5a4032eaf0911556882918992414d9dea40869d928fdbafa5765ff5f55d312544cbc0c0503ee08917c9273ecbb7bd64104b1e8ac0602df223c4bc94b8978b68e8ec04f8246e674d11db4f772cfcb3955d83f91bdb33177294c09b4bb59b97e45b4fffd8b6411cece5010001	\\xed4759540bb4cb7a6e940a8ee652b7bf6f021840ef136378a8d60366eb59904d89301e867fb077beb05080f2ed1c5d588e9ad0ec2acbec259915c09a3ef76609	1656849557000000	1657454357000000	1720526357000000	1815134357000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
202	\\xfdf9f9b61b0eb8b1de17560ea51db496f843383fdcf718f6360285e0973f161173a0846c48842b91608ac5d607f0e1216bb32b93d1fe4f8028d723048e03aba7	1	0	\\x000000010000000000800003c61e22a8cb0dcf49342446db23ac8ab23204cda16b38f5e324d84071d2d4147f2f26454cbe9b5dd068ed6f0be1a34e7c79a92f9c4ed3121e3e7a31ecc84101730b43b0ac29aaf929036cda9379cc0bd090f71a131f6eb9c243205e727e480779c78527fe9f07d1991e2ab2d74b85d8acbeef116525031e8601aab200ffaaa78f010001	\\x6c29a0b63536458c1d551e13c2a0df461e7f560335767bf7b14e3f18d0cd4bfd5ee560c4e43f5fa3a3f70bad3d9eec9e5747d276879af8fc0360e8d66f1bd207	1678007057000000	1678611857000000	1741683857000000	1836291857000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
203	\\x016257b2c0db7cdf2f0a854a18eea369cbb93a1beabcecdddc61e5a8e47c9be5d482db686fc8a86cdb09b0b7e119c985204e02b0bc63897b5f7ac64ffa3de2f9	1	0	\\x000000010000000000800003dc223da48af90a9647c76abe56e1cea3abb0068469dbb5da74f239e5ea5342587885011087660a14e43b710eea8c35352adf351512ebea68adc75a238b82f1e2328c4d56ca29387d81db8349339d3ea5c15603d9a41829e26d1e7f67d5a44fd428784e79b127b27b46db0413246139b6b614aaef3ffce2b7e51ccf237fd52bcf010001	\\xb81c742276e51bcfd4fd6c860980e212e3f21a18289c87eab5a356f92c61c15563e68babb86cfe04cd32627c882ac6ea44160e0766bf3151238797c72b317809	1682238557000000	1682843357000000	1745915357000000	1840523357000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
204	\\x0342ae5207aa85532fa21e5a79034e5ce6b65fa72fef28454d6d931c5387fe2d810a5c7d5afdcbb6d673856847b0088b6563566e153993aeb9bf1de02625c901	1	0	\\x000000010000000000800003e25a5742fc4e89aeaeea0f4de474d712609687075f8a715eb601f437e657c62d7d5ea89444cdf108e1809be65ae3957c7b27f6f61c0698bd813696558c45e44d047f24c0cc9ff9d813217511ecdd8e72e7b5a79e1b43d7713d9cfe89994dd86d888ed16e17fff676c96d2dd0d985f2105d29e3b117fc82df2a40ed36793df63d010001	\\x61065fbd26cf00b450ea86fb82e13980d9f55734bda3326122ff487019d0e211bb3cf3368a7e62960ca40b7991127baec75670fe8f22173b9872a070f86a2e0c	1662290057000000	1662894857000000	1725966857000000	1820574857000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
205	\\x047653ca588eb2f561d09d17b506b55c9bb9487e19fe966e786a441aaba81cac58e3b6ce135c4b1f439b72f0c1a22b5885c76132041bbd1130bef00b9703f530	1	0	\\x000000010000000000800003bbfb1c13008a521c88a023fa404fbbd88771132d11d847b789db4d77d669ae16eb74b7bacbee32c2ff580e9a838e55761574550ac23692bb7a47593614ba9436dbac5f7436de550103db1b8b7ecb0176af457ebab7120a03b5ee6e59e077ca9e2a217ad52482879104a7e1cb579daf5f95e45d90b54627fdb63a3667565f9403010001	\\x429c3a5460da50155b3e463dad799626ddbcab470dcc3ad1f69401a362d684130c77ca4ad7c7d0022648e78fc00d548abc2648fa4983dfee6bbccee202427807	1681029557000000	1681634357000000	1744706357000000	1839314357000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
206	\\x0852a1ffa0b74aacfa84d72cdbacba36d9a9fcc79057fd53e55bbcdee9c565c19f26f464cc1ce80c01aa19271873a95820fd8e6fc3c3f3fa18f0b4e7822e7121	1	0	\\x000000010000000000800003aaf5eb70bc28d5c985ec35a23a895bfb008773ffe44ca59af023b5dac4d5d0c4cdc505389cd85961896234102a4e7d25021b74ec1b97d1ecfe722d9a72c0efb56ede22f6d674a8d0b9f99cbd61cbe2b89c288e15b979ae2e9ec36bf22587500da843d5b91b864ca21cdc04b1641d38fbec52b3a47722fa4394909e31207e31cd010001	\\xda04269293e6de2a36656916380416a63ba76d531110b85ca73ed3be462b62f22683238e11c1fbba2e00399a7e8926974893c59c0f7d0eac76a0ed4971f53d04	1660476557000000	1661081357000000	1724153357000000	1818761357000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
207	\\x0c96ca54925debb8dea7beb7025ac709a072a093e42bcbc571bf4211f20cb58cab20f00237b571ae6758fb7447f3723daba153a63dda72e5762e365c0d4fdc70	1	0	\\x000000010000000000800003d4a25b78cdd7f84ec6c7eb9b35bf611372d565e04965b7b636a492811c738be269b035ae8bd9fffaeb236f38d8c9f72512c8b947ca3f653e717286444ef2c74731c24e6b909f5ca54bc7b9d5aa1a2281f846ef18909541f62c2db7f03815e85be70efce908e8b2068191b01563489e35450d013b0fb475d024ac66f4a7753261010001	\\x5b2de38cc119c9b64c73c1b8dbbd94624b79ff3f8bda424208c126dcf981c3b3a6076c5ea8f66631fe190d6ee390eff45dcd87a539ce9cffbe0fd75d0b3f9b00	1676193557000000	1676798357000000	1739870357000000	1834478357000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
208	\\x0ce60eeaa1a130c8b49e0b23bc3d91f554ab7abcef416ddf9ac78388b523d8ce6b793366cbb4c8ad8c8c65b7630351d41374b5df14e8e9dd2028a857d39686d0	1	0	\\x000000010000000000800003da8f047e474c9196013bb7655b9319590f86d003e91e2ef44f0f7864ae2e9d060d2726f6db5d79e24422072cda3e9027bbe8d597270390460957fb5751bb79c4400e706364f45103fed7f5d2ee3467a386cb0187e0652ef3b5677eb5a0550b61a3effaeb341bb3d3974b101186ff4831fd527e2ef1a87ee736b6fb51fe948dfb010001	\\x849f509930166eacfb1ddcb90ef2dc968d653d30ee7ddb788a1ade4e8a5565b540b880ad2b71cdc1e918d04b78fc4cdec93640686a0b697f32157ac7457f4d0f	1670753057000000	1671357857000000	1734429857000000	1829037857000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
209	\\x0e7a90f892de3b18229ea09f0f1b074c1373e2de530a761e7f61b107d1c45bcd81d805aea5df78277db1062c121a1a23011fde2b81869f168a2db30ebf0966cf	1	0	\\x0000000100000000008000039a511918ad22a5cf34d82009d4fd86ef8c41b5688792a49d02438604718f57e285ac0a3bf1aced42ec52442fcf26fdc328e12807b74297d8221295df9a3b33b49f13f43101b00e2de98fee77e790e4e493ee1304f448028bbf18dd5e570e6bf82e2486402b45366c6e8a8da49aefb01a651a3e125b3d93dc70c01d457a3edcb9010001	\\x627afebca6ab1509175cc13d4c3d9f53a78140c3096f9f3269aef440a4c77f2b81a1a16b0fb6bc8cfda519f333e7ad2d8da491c8ba106542ff80e9d8460dcb01	1671357557000000	1671962357000000	1735034357000000	1829642357000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
210	\\x12aed7b54f14be4a9e7a0274f891df4f9c6c9bc29984ee5157232ef9965a0dd283a81bf322ae66c9aacc9502f768c01fd78d3ea3b0c3e715d383f81309578c97	1	0	\\x000000010000000000800003b1de39efc74ecfdeebba9eb34334d40abfff47243a46a3388a05914c3df19479f9d9c2481b514d81062963b66a53b6d8f5348c1e4df3fbd8f1888b0e647c79d09113833f400cb831d773fccbb8accc811b887259ff767eca468eac3cd5c33bc94f8e07c00fcf523c529094a89193bc478aa0521f7848e223ffdab9ff4d1306db010001	\\xc3324bcb8e492684a59ba254498a1d75012e44358c47305ac659d46acf983b838ed982ee3fcc70bef206468d38403e29f4115e09acf736c94cd7763758c9590c	1678611557000000	1679216357000000	1742288357000000	1836896357000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
211	\\x16569a7ebeb3505f0c700634ed3531cf6c09d584dce7e8eac4d809c956cd111082fe32070fd7040c66fffe84a935ad55f3e801d879e372f3a773ff157616b1fe	1	0	\\x000000010000000000800003d06e13e9a2982a0f4b30dc0129757e9f54abacc751b1ac928b61fd2ac91638c7a34159634e342add54ef75c3c916ed1877cf8d04bfb457986f5a1759b3a0e142bfba63908962b09ea9504bdfea01495bafc9f59d2793b5086d624b1557f786b535dfa52257090d55cef0367a5a3ed8e40d2f0432feb519fdeea0cee6524bd8b3010001	\\xab5513f54b32defedb5c7ee3bf85f5f9184c2eb50428fa2fc032bab289802d48368446decd601a7407f4bd0ce931323f0747d14c77f01cdb3f0531b25f2a4d0a	1673171057000000	1673775857000000	1736847857000000	1831455857000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
212	\\x19e615bacb44b772b0ea177491fcb9d5721442a16b6b41fac2a3387f509b8cd1ed35b94b1db9eba4bf14d069f294e223251db84f650dd11554e780ae432b5a16	1	0	\\x000000010000000000800003b85482357ee4934f723ee8f9dd4ad34cf6556aae97023e22d03093ea0318937976481f6ac8e1def1db3b131d5b76fe7746bb5fcceb1298971b28901651e743318bdf1bd29c2608c8b0129ce9a55681ee59ae9115f8e2abe696c1c2c4431c65e9c729b277458eb375f34edb272c2fbc367858db8ad14d813913d8da1cf33b7041010001	\\x8c50da67c86de84d0c3c447c980db1ddadc6e1c367404b3c763fa6ee0e7642d4e3f9a933ac265a91d57cc5866b3988f9d2a305c4dd9b83e93ec3dcb9680d8e03	1673171057000000	1673775857000000	1736847857000000	1831455857000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
213	\\x1caa62df99f02a2841cc43f52398f7d8e2361f700be27f2996863ab53c571bd5ceafd7275f1e734e441e6819801a41b5df2e391d49af805ab4fed90a98cef1aa	1	0	\\x000000010000000000800003ee787fbdabd58c1b05e1dfa9c929144f828d97b55c7381eae7337917371037fd41d4610fe18c96a36d8dd1c47d3c4bfd2393c1b6f6801a25a25187bc481e8305e749941cb4d1d977e1f07097c6a1913528f5c381dbc2eb9e00b7a583189a94ed29e4c7937cd5a46c21254948fc5b112d4876d93f7897c332101f8506a5f13a71010001	\\x8858a7f4f60badcec6e8dbb792b913ff1f3ab2ec9e16f76343ba95dfd03ab9c4dafa88ba1e6c02ff22d97d55cd16f506d74b999a71387c23aa7483e1dc329209	1657454057000000	1658058857000000	1721130857000000	1815738857000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
214	\\x1e967ba4ad86c9f440a9d8d6c5754e5846912d5a549a3a46c56e322b95a4ac700db1e3b366b808ba72ce598fd05f3da446fbb18e2295dbd161a2927451d9a8ab	1	0	\\x000000010000000000800003d3b484ee3c2c24611f90a568613e5a6c57c7369a894358fc8eb5c3e2ac6b2e31b1c1f0596edbdfa1fe08765c5c6ff6b147fc55e6de79fc3fe098a29aa4add09849532f8bfd5bf342bbae83ab476dba55f972d84a3883a1f1fdee6e7d3bf75c2be653d9617d0694a4607dc0ea0c54450b05fbf0b7f40539023f914828d01168e1010001	\\xf37569b9f38421d118070fed7e5290755037f740ec58c5e9777673d70b125825aaf34e88e4af91dcae3e0f3b82b63cd45c6d43bbe96449fc84a3800262f5850a	1668939557000000	1669544357000000	1732616357000000	1827224357000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
215	\\x1fe2b0e6b8365d2f51b2d1fbb7f89146b54932eeee5b83985b4a7d03c443efd5b60944d37c9e686bac878514bf1072d8ec76515b0152f1d49b2285928568e367	1	0	\\x000000010000000000800003bdef71b27157e0b44fbeb5c5deb7e9ffef2d64004eb28b193bf7bd99fe1bf3b416fbdd6a4080c20cfe38fae6e2bece79edb20a751903e689387e51a867617dab65d4f27995f4da7d4a7797b218e404596fd9a91e424a926e539d83e3dc72ca1bb21cc077644e7d059bf89d28721e7598f0f85354362f679ed65da7c69bbb4513010001	\\xc2c9cec3a038c465547000e81eb026fe8fc1252d47efb03fddf7de8acbdaaf0416861dd8ea0ad57d42377cdc48f2cf1a927ade346ac0b0de2aa2fcc838eb750e	1687074557000000	1687679357000000	1750751357000000	1845359357000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
216	\\x2362545c17d26fa889afd495ba6e6e1e506997d89e18cb4d77bb8bb9ec4de9b6030ccca2bea4cbca636b5ea87bdb5bfcd9040b2d1583814a2a6c7bfb0e217542	1	0	\\x000000010000000000800003b58886dfe255eea7ac3f02b30ff3e7917caf6619f21617109dadcdac36cb88e4a32e386d3fc08d5493d75441b90a8943e4e9e418268267482d38bebd9f32423a93cc0f1759626c73f73a95bf9d1917259c4f5203f6254244c52119708562c0c2c7c50f4f557f463ca00378ba73b3601d07826f345dc122fa859f8dbca4ac46f9010001	\\x3a5b7cc8922b0a319e10d36637cfc50131260f9de1750703da5c3f1df130950853987a36f812b6622b7496e0ee24b394b626ff9e233dc93953d8c45dd221330a	1678007057000000	1678611857000000	1741683857000000	1836291857000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
217	\\x247e0dc45d360eaaed60d47afd483f582a83af98be2f0203dfe5a3b688e94a277662edc517a3f4d42dd7ea5d295a4340e6ac4ad9948c06282413e13f04c53041	1	0	\\x000000010000000000800003b3f907bf6e5f20b8a0e21a1fbe240dca8f6b48f27da7079cc251ef5c5003936c5d6fdb2070d1e9d6db181343959e759482af4890a980ccead42fe932b5cae3568420c21d2727b335cf974fc9d7e17431595bc8b2f050cb3c5c8ebf2e3dc91d2ecc4697e18909c36103b770a7f8f7ddb8a69ef34343290a792de09dac4e341c5d010001	\\xad17daa33ba519ff68105a722402941d47b1e3e15d379ceca3ffec566c108ec8431c905ff63b36c5a141e4f7b95791e0c21864cf3731b195f8bc698e2cf5e60d	1673775557000000	1674380357000000	1737452357000000	1832060357000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
218	\\x2686440c4afb009bcfe35edd52e30c50c31e7c1416e6fbe31723df0b7a2a67fc50a92fe31a9bbf695a499bc7505ce5b9e9d1a21683d9523938b6b36a81deddef	1	0	\\x000000010000000000800003ee83033716411ad454b1bae0036ce48ae32cae645f74f05bfd002c5f85c8da227f5041543856a6c4ca8dbab78b595cb7e06586e07ab4c3506cd41addd23ad0cc065ec684b7d6201ddbc5c2f32760c98d1dacafa8be796f8f31b2d7f7f9b6ca2b3a315ea4dd4b781b4cb90e5834406986436e6a2e3615e6e6527dc1435e5f8965010001	\\x6dd93596cad5090333639d40459457511eb5084982d5d01273b8757f883485a65c9b44ab8fac0766a1d0ceb26ea407a4644069db1fae58e48f2c34c66fd6810d	1680425057000000	1681029857000000	1744101857000000	1838709857000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
219	\\x2786f51ca2d4a2cf0c3330facc699aae735d81170328d8a0d19cc363c7af4fee3c000eaab75e2d3f797e8d869a570d4eae2080c0c0590e70b7b168727a2aa90a	1	0	\\x000000010000000000800003da47dc21f4ca12304be43c49b60980594414afed8a4c566402ab608c752dcf0c57da6dad0ffbd7b616b4a1c1297dd6150cee4470dbdeb7b1200bde3c0fc795535deaeb9b327b1fc13b962b25aa944c0c33cd505ffe7f651ab7ed2a4fbb234eced1a3330623db912676ef100c2f27ed5463275ea40c95a04f8297376652219ed9010001	\\xd7ced3db4e2e851446822a214b4d8ea976fb7fb52c222db86b4c4dc3b459f90cc4242b96eaf28ec21c31c901cac4be2f5db8b2e13525f28b4520f2cc4cc80404	1669544057000000	1670148857000000	1733220857000000	1827828857000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
220	\\x2acac47d28b0bb1d77670cb99880a0590fce099dfebb65fa431ac30ef115769f63e06c9a7df53b2d4526c2320068dc02c9faa49b1679b5b10d9038fe91a22a7f	1	0	\\x000000010000000000800003d93989c7f1103cfc9dacac06684dcb5b81bf9fb7f697031dcee7b11fef3ca04eb579063bb009d4421bf4d056e90011776fc72204059c96044d308603e35011390b035ee10868881b136950a849a2f44fbf187f4d3ab21462e54ce217c1fcf7d29f5a35edbf55a8b74216554d64d6b139107f693dbe07f8540a1f26fa53c89f71010001	\\x13c71aaf327e21fb48c7e2335fa9b558251c71063912517809d646f31becd1633afabab469086e546e604f694f6cef166c842864873181d4a25ea2fd7f2baf04	1682843057000000	1683447857000000	1746519857000000	1841127857000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
221	\\x2bf2e99b36c2e52eec209ac16e9f21680b30d115e228d2e4151dca5ef9db014c4fd86c4b00bc2b998aad56a5ab23a49f9e5b5317b8d0cba55377b85056d4af1e	1	0	\\x0000000100000000008000039b917094c6801820afd7de4a6e2fb0f66a99b2117860982a3f625aa7a7fe5899beceba0e645015685cd3203dfbf2e991802a3799a47261b5d205e8085e31b0559acb8748bdee33821aadb0dab8c516207210f53bbe294c88fd737eca67c036748b22fa9ba889df1458e88d8c6d2f882f84113cadcaeb4975b1279a941f7c0e93010001	\\xaa0772848d105972a2d9a164ad1a20e7d9963ded13e9b619db1a2d543e1c6a632c526799c2012ab6e168e9a856066386fe1ccd1b81bfa90cbe94d5d8d67f4d07	1682238557000000	1682843357000000	1745915357000000	1840523357000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
222	\\x2c9e36460a7c9891fa623390de15be8986bdff9643595e1cc9187b3395e4373a56fdf428167fee1c799ce2b4ad29d7e8d76e6b85c4a19c1eb26a55780d1d0c4d	1	0	\\x000000010000000000800003e95535b3548667c601530fdc2a6a5bfb9c2b85e457770e2daec657b3abe576b97912765b2ac2355ed337fb34c94a6862eea731fc2d0a3e5709148445fde1009f13e9cdf0693822826d62b38bab713d9d772c53fbb327935d8632fa1128c2aa1ff04971d1659a87635491a60928449fa05115c97c1930324129295625e8ff5607010001	\\x493ef2a300315c2b164c729b1d912ac911b5b87b7004cf561bf9372d4bd5e799a4f6340d477dc5742859a909560287c47b8e12f3cfea37cf20c3a0e41c480106	1668335057000000	1668939857000000	1732011857000000	1826619857000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
223	\\x2db2d50c0e8d2091cae0454ac8d8a827e4865a6ba48a2a242ddd9f24f0848d60d2136934bc9d85123f2a2cf489b9a44fa42c988604793e4f2186c8598521cee9	1	0	\\x000000010000000000800003b0c0d2d216183936248dc3a038b536c74bf56c4c6c3b80fefb9315204a6089e175d6c8d408851630c18020f708c01985466a361100b00413e8e00f5716ecfa4adcde6886e7170af5820dde95f27588ffc3e6c3941ada25aeb52dd4e3ee6188be8dca322d0c3398f24cae89017833c62dbefb3d586a6e52bdacf11a57ebf622f1010001	\\x0d8eb36e0f84b1e42913b2850e852fe75344cdd313019605ff99498e6785a9477326830f9b087d7c4ea8db52df246042d272266f115f7591c24686bc1b9fad0d	1673775557000000	1674380357000000	1737452357000000	1832060357000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
224	\\x36aa6405708d256fddc1a0158b563500edaf9909f9f0fe95cc383fd3f036040907bef11c1a5a4ee26fb6dd3bf3e9a8a2aa9520fc1dc3bc479ac12af456b26437	1	0	\\x000000010000000000800003b853a832562970128c436281e57dcd886d76212867c2b45ebd7ec70e580054678b860c06e8a57176e47fc5b8f8add70df27ac1c5b9368111ea9588a4f86b128e60316f979b5103f372446f780d0b192701125336b4a001c29ef8cda836f1c3a434f60837927d7a8d1fd8a610a665d6e7b1f0c6adc1813433661edcde72146f59010001	\\x619ea1a01b1b372dc1fbd44ae9201d4c320cf21ffff198ae87b7adad87bc799bf64612aa75b09511481b0eb6982b3ed978e7778c36b285b28aacca35359eb107	1676798057000000	1677402857000000	1740474857000000	1835082857000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
225	\\x3906a78daa246fb435bb97dc5988861b5d49b240069d292f5039492ec10a51aad286b638eb756fb5a3f7554c9c9e55fa0654f4ca59a31dd07da7fc66a1311def	1	0	\\x0000000100000000008000039d7e0eebff6838dbee9dbec98070761808af46d7152ec8097fb33d87c8b4841b601f32301770f253c9746c1cf9b4d82829ac33248bdf5c5faeb32b10f3bd43b5d124b22571f22f522cb4f23b4441a7d0082f61c5880fb9707d13c91bf725fa2b523826087de79883bd4ea31f66ab2d1ce78787df633558b30c3320f35378f3e7010001	\\x6e5e785c4e61a3399d73e0d50650f44e1be438f39dd12a3029071b5b12a608ef1496a3d758aad031c5749a072c65c0e73ab730b04a5862facdb9370bba293509	1685865557000000	1686470357000000	1749542357000000	1844150357000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
226	\\x3a123aeec7b8450c46573271397351f4af3678e14620b662bf7d080abffb6d26b053fcd123129af502e06e3a65f003686a8f44fdd33772727961753404787a58	1	0	\\x000000010000000000800003b84b753ffbea7eb58fa2817a96ac2f40bc15a7503cf64c3b724a169aed7d4dd19d83a20c18e663eab0b8a052d76ef89ce14511ff3ce8a564d006b0eb968690635808485b32b849eae69dfed5c12432500052f25f798af6b17578d4e3465eed99116af13abcb80847ea25d771fb32addbff54ea8e061537a224cbe572ed666b2f010001	\\x05e3605015afb085683ae7d524cb248dea796367e0d8acd5a687917546214bfca57d01df0f473ed3b3021c74104f7e66e72c12a41c8431f55af119c63ee57d05	1685261057000000	1685865857000000	1748937857000000	1843545857000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
227	\\x3a428e11de8449a173929dc1bf774ac065dc69bf0de53311c99ad631027460e861d1b54556bd462366a53695864beeccca0b3fa3fe9fab383e885c948aa1442a	1	0	\\x000000010000000000800003c35a8f38bf06940506de6dd0138d2948904aaf690e9beff00fbd239b4f9cb4f1634595511d5e2bb1860c142b3853cfd92a4034dbeac322b37dfeecd445442e86a9db27b6ab5163339b8faa3006225ec7efa5389a47f6f5d324f96c77a5b283c7c8a8e68546e87da1c6f37538fc53ddf33f8308624f3ca48ad3500a06dd2e8afd010001	\\x3796230558da295539f006ab2ccdd2da157b5cad95c2efb9868f68a8476dbc2b0306dcc58fc93e395ec3183bd22810a4c46a53742dcb6141b5ac8193646a5201	1664708057000000	1665312857000000	1728384857000000	1822992857000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
228	\\x3cc2a88d704f0459451696b7f35551aeca7ff8d684619663c451f4726ad4f554b57f8b690954021bfd903c488f26cf659059ade7b55a4307b93b0b4dc12bc57f	1	0	\\x000000010000000000800003960f20eda3ebbfd1c619319998355f6cd54d19e8cbf3b1394f217892054b37bc86aa2e2e80afb6eeb8887d01d4102c5f2b8dc91eb51981d7cc6dca6137415dcbb5e37987da07b969a1302f498a7a58a7a10b62ec03e14b17067ea05278489d56336e06db9a7adaf655d474ddefcdd158790a7940219279b1cdfc51195580f90f010001	\\xfde2ec91673f1a4ee3417deccd12266e8a3c4ceefa0e39c1e89663abed80eec926a81daa0e51f8ca087a58f8741203b7b9dc0db4d43434855474bb30b71bc50b	1656849557000000	1657454357000000	1720526357000000	1815134357000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
229	\\x3d124ff3cacd5dc5cd2b9033484feb76d7445e2d54ba4a4e9ce8ad14081c2a781698a945201a6f4fc74f8d8420f5dd7831489b23771cb189509527bf8e002650	1	0	\\x000000010000000000800003d37df21db988a2c2fedd15c1699b5f1b22c7aa775e2ad0da69d303bff0b724aafa24ccb5b0db72866898a51019e5f0e5b4aea988cd408d27deb77a8c7bf71e87ba9b1c4826720ad20fc91597046930547cc586f3bb9fd94595c5e51b9bb74aade9802460392fd6cde99313d5d28c4e41e55c8cfc697feed6bce62d2540c62977010001	\\x787ec95841105b5307c8c6b5c978aa9a566bf72761bc6d03b469e24460dd03c0d27dc577d178d6a2b4c23bde341fd6ed03ff707b8ae9711e325b9f2fd0c8ca0b	1655640557000000	1656245357000000	1719317357000000	1813925357000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
230	\\x43fe772ee26bf2aeb458a1702399deae73622c263d74397b32157db5c2af4ed861b4cde12ecd39b914a08de5e96a1b88283b58be57c56481fec24dc1824d0ddd	1	0	\\x000000010000000000800003b05ea7a9221cb51992f049666f3bebb3b8403063286c9c895cb22febc3e6ee184289e887e5c09cd87dfb25785e9608f532b9752025eb58d6e817596642724d4f06bcdc510109b5a5802c14322bf72dec97634ef018a35992b1213cf7b2514453a7891acb09f115e0162c41466d8ae3a3c23d39995903900a11a3789d5b17ae81010001	\\xf9959c75db19e701a0e2b5c5e67a475532d76a55aa63e11c9963c916b9d888f98988a7ac1dc1630ba2722ca8cf4bf38210feb727480c54ce7d7ad0a5b5889c09	1680425057000000	1681029857000000	1744101857000000	1838709857000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
231	\\x4316945def3badf225bf1650c8aaee52947791c69e75337545e71d07673abafd12ddf629c809cc99619de43795d883637fd50a7793f6b1d7a436aaf05435808a	1	0	\\x000000010000000000800003a21be3fbafe357d449a6d474584ab8c62c05b7c026d57b1de554dc72619d712cbce100e19465626322c047467ef46aa9a80ddb021a45afc216626c14c9238177f2d8f58cab3e06e8502b9b85ae65e15742d485e187718e9bd855403a500e1b375abc22cb7725d4c57b7fc17d2dd9698d5b3537166db460d9d622ff602785be8b010001	\\xc88687c6fa6898c86898ef45174101e86a36a078867b0a185b649bb51511d1ac3de0bdc758df4842300070f54031d495b3fd31151f4910fb4eb9e65355641c03	1685865557000000	1686470357000000	1749542357000000	1844150357000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
232	\\x45e6524bf0e3b202ff038ed18d04663a250bb1455dacfb9970821fc68d1cda574026a9318b8b0f38941d846871bb718f95325c9f8a94f24b4d9ec3407ecff072	1	0	\\x000000010000000000800003ed7afbf598e9f56d5237acbb8f526547a3fe96307f8c5b56867994e80b16b790167c7eb797b06852897b162f5397f803bd66e9884ef79ff756f42cd421ac55d4086803bab354101cf68f9eef0988c1a879532aa2ad72311bdf5a622c291e3968216ad5ffcabcbde2c10d69dcf8cab563e8c3abeb78a4ecdefa9d9d6d2123d04b010001	\\xfc1871fa21a965717f7e42385336b84186393dbd2a45decd13570cd1f3776c598679a6865cf15e7bda3389fdebebc714e8c0b8d602dac574956b4a78be7a8904	1656849557000000	1657454357000000	1720526357000000	1815134357000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
233	\\x48d2100c44c5f3a007a0036970220a733e98de60283430efb93a578257c68418e42b6327904e22f9a7d3a22c71f8a6849a247188eea2e0ea450451f37ebb4c23	1	0	\\x000000010000000000800003d46d4298ad66b9881e1a382fb41cdee9271608fdbea61c20d0b7c00c02c68e81db5de17c56c252c99a9b111d7a8c9d6c2862364b97fb11a6e380f771937fd274897774f18dcc25e600ed88d631fce11a69df0e975484ad171256843357db74296a5aa251d3e14ac95aa3c84672a044a181167903480eeb5a0ea88620b336fcf3010001	\\x5727a3ec747edcb29306011ce94532d5f88687065285b6b6024b959904516fd193d5a1ecdff4b7dbebec03b0419a7c1c25bb4263cebe3d13d04244aecf2c5a0c	1686470057000000	1687074857000000	1750146857000000	1844754857000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
234	\\x4fa6be8f8bb8ac07194296188337212393bc42c999da2c70bf58b0d3c0df5cb738a5547162670f7820a20802e93a9c9448dfe0cbddf07ee1ef97d778f59d4415	1	0	\\x000000010000000000800003b98963efe976dd240c0b15c80795dbba426ede4be20a4844ad5085b6751c546f083a2185baf7b872208235c5ed591fcb516ffe44ae5af728321af8dbe3448da0dd45054cf3e774565dd8e75ed9b335f44c8d496bb361c8a713975adacb8e4c03f5e8ccd342e18957895e0a3d7758aeb61c8778093e2da9f0c8c526de6952939b010001	\\xbe15ff05469aa45de2511eaeaa45b60315934831cf71559569c419ad50d8b931e9a550629f79043b67b17d60becdd9c6d0bf615d406673f836cb8e8bb3bd3008	1686470057000000	1687074857000000	1750146857000000	1844754857000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
235	\\x56fefd79a6f71ccb5a9a5b114a54071a6af713fa5439ceb501563ff3e7ed1e3a813f713e9c3517d9ad847e29653424e7cbe300f6f537cc2102f544c452898fd1	1	0	\\x000000010000000000800003b806c78b7c1ceb66735f262eee5ecc08ed7cd899a4ad5de1c053578043576894aeb67a1d16ea5b4f6b2abe9f8b43f2d9c3e9596fe0420d24b95812eba26e7d673378771a661b028ab0e6532db0b71da5ad53e7b3467bac20da9cccd2fb640572632e63a532026cd1596ce48e93af712f128e7e030ff1bbfe6a3c50851f9d1195010001	\\x9e9fc931c317038f69788b463aff6dcb5c1873f9ac0b23e7b71388ba00dc5556f5ed0b16433daf3935aefc23b66d201156fcc92d7a2f0b50f416cbda5b07280c	1671357557000000	1671962357000000	1735034357000000	1829642357000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
236	\\x562a24da988139a298dda942caaf605ffe9523fb3dc772ce3849e839ba677465a68660ca3699fee75afeaaf817179246680d1835a9884ce633d22aa43818ccfc	1	0	\\x000000010000000000800003e442cb2ce981babc4da3153932c1d8548f3d9cc6aec140fbe08a36848cfa7425f416d22be2efa72656e0870eb0cd74c9de1a3597f2daf03f5810e9d57ba8eb44800b9f7c619e2418a0961a09bd44cd8feed13e14eb11e51d5b06729d75a39ca6f74fd5064e8537d2fe1bf50d84fab7520ec4f945ead26d1b211235316279ccd7010001	\\x93f4be54d1fc2835153351c30ffd50908768e3bb02639f8714f7200b21d3be759f055128af5f2b574ff165072d0f5bb5e2e81ef166509f3d83ef8f6a0add1908	1670148557000000	1670753357000000	1733825357000000	1828433357000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
237	\\x578233d7fe0c3c0754610c3bbb041c5c4c7af9f1a09b369ded445f17c2323acd5ddc29d28a8e191e87bbd5983de2705c6b6627fa1e4cb1a4b297429ef59d94ef	1	0	\\x0000000100000000008000039dd46d1bf1df6666bd79e8c2ea30a5a4a0426339637103ec2f256edc6afbce9eb6c74903bd9e0e22de1951e062fe9f4f2ee7425292054e77065b8a5f712603384f1b4ea0f77c595e23df99cd09690d0463969bce28268cfa87de990bedd43b0715424121e8627d96cc7a67d372f735efde374d5943a628c72ac3951223b1f793010001	\\x77d0c1e36d520c4e91d2e31bb01f3a5252dc666ce7e74b1b0216c57fd4ce94a55ab7933c8acecb7c61020adbfd3ae74c1db315af8a4957fb98aa285944e0d005	1684656557000000	1685261357000000	1748333357000000	1842941357000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
238	\\x5912c455746114c96b6bda93d25c37ecffecfb0e5a82d2cf26ca754509063808a997f4fba4795066d8f725aacf820d436b5b09c5ffdb58343978c4b198a93470	1	0	\\x000000010000000000800003bfcf0d0ad6debc6e15e5ab39462dfa3d00b91625d964ac61a263c07cbca65752ae79a69d2e13d93d60f50c2f409397e4eb663a9d74df7821907105cac9b36daeaab7f799252f0f393e1e93237c40be3908cbbd508cdcae9f6df2e657a0ccc4e5e02ea7eb5d1ac83259daf8594ff00d5afc0a1150e3e2af6992c87a3f61b1d66f010001	\\x0c28c88e0f16ebf450c22864f996767e969efdb7c39c0f4f15b7a6e8401a88a9f9bdabe661877616cc4a3f13871344382a4b2df27d6a359e6de90a490f208a08	1674984557000000	1675589357000000	1738661357000000	1833269357000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
239	\\x5ef286a67d66eefc75c36a5fe10bc1dc56ad460396e1049959a752a98dbafefca948d9ee3ca13fe6b623cc221abf04513dad031e0693fada5c547164eec14542	1	0	\\x000000010000000000800003c41ca6a2075dc517fa85ba8d54f03ea482a8d7741616431468933100c2df60c8cbfadacc800fb657273652afa7875eda4843ce1e4b2bcf55410568981935bf48a511bdbde2efeea1f0327cd7f563afe1ea8740efcd049bdd5a32f2c07bcb66f009c508a05bec27d7d5868ce5023f21d8536d05e12ba5ba5f045473a664b4c5ff010001	\\x5a9856704138e35dc593f5316b00336b2f2feca04975db3c1845e7248e7c24128ee0660ce83d800bbf5781682fe429a666c9f79a4db469a404ea400f475fac0c	1680425057000000	1681029857000000	1744101857000000	1838709857000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
240	\\x6046434266cba06f28e78e8f2fe9be2f114e2857a618d9d0510c3fdd50528e6f5e8c2d15046ff6f945898dbc2aee42a439e3df23d4f2ce311d3684a45ae2a635	1	0	\\x000000010000000000800003d41acd6de98e4159512bb543e0d1ea37996a7ef1f0dcebd526d877a6d12d0dae0854574a5079e3dee429b4b8748876d2ad1b36ad38fe803ac88f6962162fcb24fa826a0523624deafe334db1c36ad4379bb2246b8972416db59167f4521fb58aff1f2d0f9d20df8927831fc9ce00e41e20af2790a21ab98b1cee2c23c258b8c3010001	\\x7104f06e2d23205eafec081d2c548e6ea76db9a60e647af81219f30f8d57c819f443a557f9da634c436a89429d8246bdc94e6ffb7499f2c029cfe9fbe865960a	1656245057000000	1656849857000000	1719921857000000	1814529857000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
241	\\x64d288fae4bb0451013d78489b2f7f8771eb27864bf0c019b28097c46ddda7de89b701575d1b25c7896789f2af449c862c0511c8fe952cec9ee0385317b56688	1	0	\\x000000010000000000800003ec361141896e9851bb7d5133858eac2004467e3cdd75a139705d778dd4640ddfd151271c7d7305240b2afc2f55b502050dae66a38c1048e7584ff9560813283a48165fc46c6f8acbe04b788cf362174ff84b976a3497971f167c63256d4ede9d27893987e14d9ace14ea2d81c4f86394c2893c0e115235cf11172f5bc6089409010001	\\x367dd93973cbdb49891cdf9291a01fb5c83b77ca9071351f8a82ece9394ab17ad9808447c9200e53507f59e38d68c592681c43210fe9b352d2a5cab5bcadce0d	1686470057000000	1687074857000000	1750146857000000	1844754857000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
242	\\x65e665f839c534f095cd5f88a629e57b9233506899f949b228a7594896a2124b5b0cc408a166cd6d63718b195dc63ae6834bed0dab7b9d147415aff55214b867	1	0	\\x000000010000000000800003d8cb56fcaabbbd256334a37e591c8341ce89683b5546e483092e542aecfc175a72d36b92fdc7d8d2057b2d807ef3aa9ce70d15fe52007fea05b6c4d8401669611801a5f596b032f1ca82a718d3077ca53a771870ffe523abdd97133850f25a78f001d294413e1850c771324cd43ae17da3bc898e5fe6e3bb21588f4ef49cd421010001	\\xa06724389d9d597a23a909460fcb6871c681a7eda72acc2f0adff61060fe1ebd858a19e3493f905e45e4eb0c8d5e47ada9b9fcd15e3a73b275b60b5f64ac8509	1684052057000000	1684656857000000	1747728857000000	1842336857000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
243	\\x65a22c9c3739a78dcfa3c195bf8fa1871f29d48dd58957858676b7128c86cee2db72bb662699eb6abe76c8fc422e388aadd76290381fe45937ddae223b79ef60	1	0	\\x000000010000000000800003d1b2dab5abff99a478610f64553ea8959b5d3a84c893df251600ae4a4c19891c0cf413f4f9367d83b1d5fe08f1c002ba080521031a5a4a79ee87d96c680100738be46d6586e3024e4423986fb676bc834313fa330fc8ff390ba4146d13edcdee65daeb2420afd728943ee18624667c53cc0a7fde6190a3168bff9959d6fe3d03010001	\\xe6ec634c10aa869f8158c284ac0ff3cc74f24fa5c98db278c8b1f9ec8b603b9285a647e96f9634697b328b7e112d885d9e39fe0111de156c3b87cfe898b8b305	1662290057000000	1662894857000000	1725966857000000	1820574857000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
244	\\x6662b787e9379da736066644ea3b2f336e8e1685baa14dc8f25e63030bf45fb07a6679b799871659c1038b50ce7c92d2b86f0bbd9204d235021e11f0aa2a2d9a	1	0	\\x000000010000000000800003d78ad4a72534375b926ba68613bf86b06a75fc4242bf24c5628a39fb89c2605c0c8f113191ff0220cac9fbf53b23da1cb37a11996bb8a908247fc04b57c10b49eb4a6759bc69079acde9e6b5f606ed73b901b6d843aa5d86cc5dcc0905c438d9563ca97de0ab60f06b5420579520412c8f13948e5596f1a6894a961195740f61010001	\\x482ec13b7174a7352b17bc652b4bd0b185ea7cf4f2d10b28b030a7b1b4fe16f936c405a52583d113d5ed3f1832f8956282ed1836dc46c432c8e387c575f3ae03	1664103557000000	1664708357000000	1727780357000000	1822388357000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
245	\\x6f524c272b991dd3f67fdf929939740f269466fdf835157ee0302782761cdb8c06dae3a9719b9313a38cba724efdce54921396c813a152f00aa618c056703e4f	1	0	\\x000000010000000000800003c276c836e4a0d6ed9dac28072bf443ac5b6c5c2b7fc4a31d075b508cc9532fc7da348115a7022930fa1c60afc831d038ea99e8ee1444fb3cfe562fe009e25dad610a115feab119df11eb4b538c27adaefe160a5115fa44961936023889a1537a8224dddbed73fd977c7845a7924e42b0f11fd9a691f653d91dc2f090b43fec4f010001	\\xa617ff0b29836ef4e7e49801e02bed07dafb4c838fe3d28832d7c7287f3d6adc6b36060d58d048d6c22d101e5fbad7218ae772db6c513dff4f80b5da1e64b60c	1657454057000000	1658058857000000	1721130857000000	1815738857000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
246	\\x7182cf312082635da43f9a76fe2a76efe0f8c5ed0bb5fbd9ad28880a81bcc0983e70a46bfb52f9984ea8a5d5444d4409f69233dc094a83d9a176f763ff3b0b57	1	0	\\x000000010000000000800003e6f7dce272fedc8e503305db5d50cb8e2f304edb7e91f2620cc0d69de45532c06a76e413acd82679a00ed40a00cc4924aac6c9fef4551ce837dc7c69705fe7ba5d6519d4b8302debcff47fc77f1470af043a7213d3f0e9c28439079edac9cf43583a2e761939237210a4dcfd6d45cb6b8547d7fb68244c9ccebf1753918da861010001	\\x53ccbeff495bf3ca3a1602ef38856ad9a8d5affa73b16f5ac9a0f500b8499a250bca9b894e2e5b7116deab37ece0166d2bf7b5b9f6ff5304bba8996b0d0e6802	1684656557000000	1685261357000000	1748333357000000	1842941357000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
247	\\x756635b874cb840f164d156e4540928406285256c445e491757df471f0636a326517716efa4c3143013a0ae41a8fa33da7b04c61730ab11b59cda8c037ecccbf	1	0	\\x000000010000000000800003d2b5872852debf3b0183145f496978a8066091b765cb1d64d71f6e6e44682b4ca892b372311928e290db929888eab3f8d4e4339bd69a28b03743cfa78ce4e675045309fb82c6291beadb48fe854e2d4b722a9c34e7718729c0d44ac1c7148d18676bb2dbdecc1c7824f40b40305a3af91d9cc3c36705e59ff88f9b7c917f5817010001	\\x45662d4e109e82d12ee1ab789bfd1b2985fde1e310460658be35217e33862922eeb75ae7e89fc1ad92aaf71caaefac31f7b863516d24f67e9121b42d2592bd00	1685865557000000	1686470357000000	1749542357000000	1844150357000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
248	\\x79e699fb3c4891e8df6459606e960f0601fdd243fc3ddfac44fc8543c700457f348d4a96c3f0230188d9144653e36e61ae7fea22fbeb3b1ff8cc0f603a24f787	1	0	\\x000000010000000000800003b7ab1efa60c00adbdc3a004c1d05eb5a543a456da5fd3c3088e33db5a26a8fb946a9932693ada2aa669f7f98fc175362c30e6e7f1a6d9433b5c979fcf4d83f4257aeeeafa414f304daf63c82faa22ede3cea8f6c819ef540c30e78f514357214ff4663d6069bfc26c25974599a71a5beb950500f0e4ce8c91202b794a9ce8ad9010001	\\x300152d7b82da4a279f23918bc4f298b6f2487bac06969c1224d7398774ea8843e67f92c867f1986c3ac2d9efde37bebe8e733e76fc8d968aaa560f1ae74bd0b	1667126057000000	1667730857000000	1730802857000000	1825410857000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
249	\\x7c52175b475edbb5486c6178ec30773aa925fa90870b5de91a01ef8368d0cfd3775cc627f88bd35f5a1ced93e231b87d7c9f237092fb173c13ea66b5a173b04c	1	0	\\x000000010000000000800003c50a4648ba5a19c5daf8fd8f02d50dbd6e097b1d8aefaf002bb5487d07ab297bcc3dd92537ab20a592268ed50b8b770e98fe3d62c2973cf8e39ac9b9860332a96d4ba83a40b073f2e8393f39532b80ec5891decf6ca3c7e6bf3f2fe27204e6b1ada42ebdf7cb96807db41e2fa124bde608106e5b141838a85768c08204978801010001	\\x00d9fcd95925e98df20259960cc3f7eb8e29c6ea5366c8d3318466df6a4e4c0b9a1e597ba8773ee81b18224167ebca3d0da2070a873661d81ac530f5e46b6c05	1656849557000000	1657454357000000	1720526357000000	1815134357000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
250	\\x80126eb0cdf4dc86bc53f6e0190c0952e8fc9e9f2f3f52a2cd9560134722187407bb560d6c7ba77e61cd7deb53edaba6f32b0f1c0acc1e04ba53d0b67ea2cffd	1	0	\\x000000010000000000800003a088350a0bb1501cab50089102b313cca4771176e6126236767b1df6b8d8ec00b979ca00ea8dd7410cebbc5b10dc980de2df6a7fd20bbc2d2edf719fc35a4142eca7388ae8fe29e96408d57dd7a81f8045ce0fcc28917be12b0906ee9d5c335121e2da9db9b4b0e70d887d851711abc90259d3449d15ea5b7fafb1c919eed9dd010001	\\xe5239ae91f50a496ea0856ece3ab11ddb6d1a55187145d5be4a63049bc460c25c6455755c181d1dd077d4220595e47dfb24c24c564ac70dd6d47c044be316b09	1662290057000000	1662894857000000	1725966857000000	1820574857000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
251	\\x809ad422d94e77867d416c1d65ad9d01e5c3439fb3d9f90a1d1814b137237960daa3fd4966b802eb65d73395ee80c604a63b6491d86c12051cec605b15bcad47	1	0	\\x000000010000000000800003eefd4699d9b505435a2eda45e9159763662fb193c025eb6eb22750afd0478b13a954be0028a594571ced1a469fbfe024e7dec39bf80a0287aad60b510c97e0fe7085d29ba06148b5ec955c53d9e5fd5b026c096523abaa45c2a8077ea96fa4dccd2d58f554df21826cb7d733dad954dd2c8b563b5373e7d598f9d7a122f8356b010001	\\xca8591627f5e9a45a96e01b391c824298824b7be541da89c68f0aa2033088c3b793fde4a64291a8a94f91c25706a4861f060a948762898ac5b0cbf54d9dfac0c	1668939557000000	1669544357000000	1732616357000000	1827224357000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
252	\\x81ee9e2f94e0e62d5be7d9adea04eabdfb9b744f9d1f8cbc3bf038ab0ea58e45a68de664eb06ddc78c7ebcfa647fb13dc88aeb0d54c5c9ef03a3264c569ce003	1	0	\\x000000010000000000800003bcf92ba7a7f5871a93bb2547bc8ad84ff37160ab3edff31940df88e75d5db2c8d7db6de0857e333484c7107d66063ec2c6093cf4fc6667f9f89799cc0705cff3f32eec571a8e78c50108e47984d98a0f8d46b024415000316d2c364d42beacb5bef69ee08133dcf4e6f386557fbe44095ee3a1931085cb9dc332345911e0e88b010001	\\xe5943a3fd853ab60869f9458a69cedb2bb5e853ade9c5c8aad3f7048bc700c870d9c76eda837a80a2fa76d957a0ded37b91f831bd8ea784ed3997520729daa03	1670148557000000	1670753357000000	1733825357000000	1828433357000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
253	\\x850eed79dcb09e93463fd625b2ef20f1b801097f31c494173bc3592cbd7372f68c080cb8d2023549beb57b2318efda3d0c3256c6c24899361ef19acd4073fbe3	1	0	\\x000000010000000000800003d7105edd9932facdbe2e3ec453f84f90eeb8d4e066619fc7c35863d65251684d51b257a6a3f5d5bbbee477f4d27df7cb5c0a1c0a6db308f5cdec0a998c0edbf5cdb91dc394e30ee55dbe6179a295d72b01a9b72186db788bcfea7bdb06174735a06903bbad01ccaea61231b5f8c62d492b23de80a38bb77a9ad3ca5ec09d5bbd010001	\\xf9cdc36569d2b0b00158c71a2df15db86c8ecf62d3fde2da9c0b77c1b0daf85005487a909bb71a1f10f0d8d7e829184afb69081558930620a126dab3e5a99c03	1678007057000000	1678611857000000	1741683857000000	1836291857000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
254	\\x8522205bd925e238681703fbeddccfe8c01857f5c0d7863ef56678264eb8a28257e0dc8178f62a345eaec8177d71089bbba0a2664c47b1a1188b1babaee28acd	1	0	\\x000000010000000000800003d54a3ab4da9f46c20f578823b792ec0aff88af2fed4c3a9e31b1349fbaf850e201fe0ecd5695b4af5741532c152be3f5a4d78fb5a2188a6ffad1232adb61799dd2aa745fc8ab94d8f873eda44b2487a7568e3322dc2f22bba3f8f896d32cfb3ed3baa6f08a41d02644c878c943f989fcb2a4f49be7395dc865bcaf5174de21fb010001	\\xe950751fd44403d50e20b7c2727e13c193d77379825c99b61997f5e056206e5f22a92cd1503bae7fdef75666d84c873cb056a07bdc5605c036cdd376cb60af0f	1671357557000000	1671962357000000	1735034357000000	1829642357000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
255	\\x853e9a92417763af925e40bcf5b86996580dd80112c1bb95c177304167a6db0cd9f0fdb146a29a1087e8ba695492c78cf7971a7664a76142515f9b5956dfb0ac	1	0	\\x000000010000000000800003e1927bf8f96759a317120a357ccba0d87425d69c27ec629962f05c2903e533d0ff8885bac15df1e793f6d8dd61186cdb3eb9c54bb7b0678d574341911956412203df86c4623c6b5d06e6017429df9d0f15b9704ad9c058edd03869c847aa7cfccbdfe40ab3199d84e6ab09fae0fb725182491ade054c72076437a505cb3dbe21010001	\\xa53076502930e73ffc25bee5905878f21a5aed5812c29643630c1ee06a66e432c036fc86a950c2cfca752ecf24ed47a62944defe5e5285fef071b51eeb016201	1661685557000000	1662290357000000	1725362357000000	1819970357000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
256	\\x86d2229587a5d5008ce44a09197a431260331a3b729644e98b6f6411eb991b51bcec44430e09ae3ed4ce8e74137faf3bcedd04a8a5b1d7ae260e07c045a32225	1	0	\\x000000010000000000800003b447512e9f9877255e85e92595979e93862d57bbcb706ecbd58daedd18ec3afc4a5f8b6587c9934b43172bd6f66479c57f523c47b26c0d805a54749e32ed00a458143e524043009e66eba6b350dfcfbb65f629f61a1a94b1c3da80125d6914ec43f138a07ee2d6151befb3dfa15a36cd7e4a9f09af050897de65770e4708e935010001	\\xfcf554a8fb4dfabb1b0e9b6215f95cbb8a091a6a388fd9849345a7f03783d6393dbd37743b0466cdcd5652f48f3deea8db43b51bac6858ce91e6963bb6a17907	1663499057000000	1664103857000000	1727175857000000	1821783857000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
257	\\x86f6037ea728f3eba0e89367e8084f2a256487ed9ae126ffbdcad5411c174d3efbc4ac3a4f6ab3b7b7b36739cc6b4c6b8cee6f24d194277094a21ca86045b10e	1	0	\\x000000010000000000800003a5bc21722e03ff6d8e0910c6ced302e7224ecffcd1792974e3a5f239e11f9f037e008fcf3dd08402d81255c706e26cda6c41b395513f5b83c167580d786297ae1059fcbc60ac9d4886f703fe1f7b373c45d79fbda38de88cb03c7baa574fa35c1f12a8ddf40c876e9c0dc98466c58062524a96c7d9ed55738e8e6b1d4848fa63010001	\\x8a9e9d53469bfa1aa1089996c206060bd06199f4ca6bb9cb7756d79fe22e6879acfa9be730b7f582d6d890fe98ec5764beb0f6753e873be899d0e377ffa93502	1674984557000000	1675589357000000	1738661357000000	1833269357000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
258	\\x90320ad18e35dd0c7858b392afb37a2b8c35674789f66c75ce3ffb3bbeb43d4a860daa068f2104e06840080705567fe4d5aacd20d88aa7aa9168541c5ce505fb	1	0	\\x000000010000000000800003b0d2cbbe4c21916be0d4f8a68200d3702a183c4a8668a9ebe99ebdd6017e2c76aca22f77bf68fd15e59632266c0edcdf9fb634a50d3e5902a9cba9b67e262a8a0cb2734e3346e8fdf08a0612328f5fed93889b380da0bb8cf14e1101b1b5b1b6003eb1ee51310a2ea9c1820f1e72050534361a92f2e2dd8b7f10f560acf3abf7010001	\\x3b8534b44d145195c7899097098bf2070d2692fb878d5228d1551e588eab0b2da819a7a65f8613c79c3fcda84d08da658e40cb420cdb35d9f8c662e49ce75a0b	1664708057000000	1665312857000000	1728384857000000	1822992857000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
259	\\x91667573ffe6e23a544219086442bcec8dba1eaa2a7f3347d3985c5df9916bfcd00bf940bd7574415c09d794c15307a7bc14d441715bb9329ab927b7f1a41300	1	0	\\x000000010000000000800003c5f14ebf1da7839915fd03e820fbb563b113c6cc34c596bd7a12ca328b11fb75efb5ec79522a7c3b511818a4cb06e9df1c603824fb24584c4fa204584e126076a4b346a39595c2a4bda497c86079c7e3e33d397148c798cf68ee0244f972cd3d5dc16eaf6476c7e5fd6f8f281b2361ecd31b6a38e2800fcbf07410f7cf41668b010001	\\x30e4e37927830fd101f8f7eb387851d0a3a7eef5ce736c166966f5f789e8b4aeae39c20447c6d663d46663577c0ae4c3d20028c716448ec0ff7f034aaaf79904	1681029557000000	1681634357000000	1744706357000000	1839314357000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
260	\\x91024d31fccca7351de6197e07a156cd8b485afd1a451be0b0470dd11778eed817825b59eb9e9880033ee9f06b6275203a746d7581157781bd5a61e95e8a9e90	1	0	\\x000000010000000000800003c49d265019859b77f38e71887815182fc1dfc490c3f26baf686a043a2f4cad65d95486f07d123a771796073c92b5bebbca1861e82ffd0862d622c6c5efa9d342de5eb126de9f381b1dfaa608865da31a210253dc4965d15fa999f143115ae96491bdb2032eaa47b5f3fc85dd5915c954785a1262a02d8924c27c03a578f82c27010001	\\xc20b1796b688252912e0128010c24849ff523fa94dc9fb667f13c41f22c271fe16507328a7b376099f3aece3e83c03d8b7b94ea6b4a099e8b125e0101e10ff0b	1655640557000000	1656245357000000	1719317357000000	1813925357000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
261	\\x947e76d03faef44025898dc6884b913fefbf1a716db410f5da11ca7d8d1780b4ed267c0222f1ce574d6fb5ac604c1c55638c65e1e00b250c3d307196efff0e27	1	0	\\x000000010000000000800003b1884cbd960383f3a2f4ba449a4fefd0f1b9db56cf27de96362d22301a0d886950c3e402bc452430217913f4e52653b763d6f9c12c0e3972845be2465a8e43ae14177c632d6c49e6b79f5f8a985e9ceff7cd19114d13df55aa77ca046b85cb75f5cb50ec89af6350c76f286198d5eb085f6119e8722796e721979ffa8078c293010001	\\x5aa62c739431d48bc4bdf653dcbe6b3312a1bb960b5f90c97af762517ba96889f501cfa3fa550d3b2bb643d4d480ddda4d9db804395dfc8f33d18737d677fa03	1661685557000000	1662290357000000	1725362357000000	1819970357000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
262	\\x944a547f847b510979f2f7fd7db5613960ab77cda6d29fc436f5f3971a360903f85d97d1565f39fb0f899269ff572f20873fcbbf198d8301c18bcc8c3ca25004	1	0	\\x000000010000000000800003b173e73be03eafb0d6e4fd7d912a7e1b1b04f645583c38a5ed8f30c882d3527ae4477f281d2c7f5dbf87c1534f90ab8068aa0f1da95703d5913c0535e9a2ac4fa5ac7896312b5bf4e0724056496fe9a0ff43265ae8d6389a0e2aa527f33378e8daadcbc9769745f9d4634e7033e4e85c8de8a0d817e391937ed7a3e35728a449010001	\\x44f5975737721264bc93ff6ef545b234b2f19ecd5c74df2553f8c886d9a9a60d55a14b8f2e2d9d3496017652d37c4b826dd75876f2d96d4f011e6da03a41f308	1682238557000000	1682843357000000	1745915357000000	1840523357000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
263	\\x98126d37ecdafb005316e4296a6ea34bdef275b5f6695e44598d0741a8c9a14b197410a9cc918cb9ed0ee0e0424a4bb752925bbc2b1feb7c80449616665fa672	1	0	\\x000000010000000000800003efdd2d26829838174567a75209da23ca129fe8b1e70b191ebe9ca2887c14b03b3b64344ca5d5e52c20bf0b24b1601cf05d1fb7ab05d5fcc08a73342da9a703d743db65538aef2d5c7022aa055b77ef9bd7e4e052e40686fe9dbe5351b82f82ecc063884546a6741b3024ce21544170eb82d4f9b655466e6d12758f59be84b347010001	\\x3562af93862114df8d7514175a3db5eb38e62ef22fb0b70ac1b6907f345f320d3bf8c50911e6d44f3cd983c448edd292df105d752d1bcd4d6c145dbb348c0e06	1684656557000000	1685261357000000	1748333357000000	1842941357000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
264	\\x9c3e973e9198f2587ba6a8325ee6eec28619f262be74a0fd9ca140992fe1e2ac791b5d0dc6da3ffe99c56dc2a7793b9044b1ae5512902375dc0cdc4c0f485bdf	1	0	\\x000000010000000000800003ce9a2eadf29072cd99d883bb40b5f3bdb7d5891ad4828c3f386c02240d20fa87c579db55b2a0d8e7af0363baba5b5eba5d5e8d876b43ddf4b5edd485f41b75a17bff74d8c586cbb6aa2e308bff645dbc44ad1a70b005ef41ef97be5c57cca2c41c4a7e86a4d9578c78d248a01c87f68af49e156d52a6f77ecdb14b1bece2a84d010001	\\xabbf6f56c307403923520d609021813b6bf99eb5e350edc7c4469bd1347ef460d31c5bbe2081eb0c280977aed5e411695235ba3b26f6878da410ff16b521fd0b	1673775557000000	1674380357000000	1737452357000000	1832060357000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
265	\\x9dd6925f31bd2b60a2be25288c6699b774080329f209d341053f172e0ba16bc830b431273fc1db4207ec0102a10464bd595f67df890c200a14ee567f53c21111	1	0	\\x000000010000000000800003d26ecec21b6b0fc491e965c6fa54accfc1ce901e24aba84f4273d833a302dd8d3d551aed399a7b523dc9769d9685099d6c3b25bb69357c33bfb79020bac06605b98e6f7717f6540196c57ad6d73ba1ec3a91be8995962ec40d773fccc25ca9eeeab594e2010b9dc47bfd1477be50aa18e1f9811b353c0525c2d06af1a6ad75e9010001	\\x7378a72b49c5e745abb35efc3351958d272f71f05a03062ea2c58d447c14f15ad965798fcbbef31fd58295e08ada06fa95a78c712e088b82b04787f7ee2ae408	1672566557000000	1673171357000000	1736243357000000	1830851357000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
266	\\xa0de0b15b29076849306325fa948c8a9faee51b286316a12b4f2003d2d0b203209d33634d5f6ba5d36fd04e981b2e639b3179675267a371bf8d9fa86b66354a4	1	0	\\x000000010000000000800003ac6d24d4fc079f90561c9b40799b2cb41bc1dadb1508b5d01523ced1f049a53d414827576507784fde6a29d22d85583d1b8d161ada08fd333fb645e359ea0cc26c0a303893e2e869167d1d8c7b4442ab4ad6bf81bcdbc8658935643233d8814e160d46d9741aafce5467f35c08343cb4d2f6407ccbaff2bf22e9e72c06bcdc93010001	\\x8ac6b502a6d2cddfd3ef640481e769425d343471465ed244f9e758c58035a14d2ccf21e09968495430e144ab8791ddc9aa313d1ce82197bb821afeb7c92b2207	1677402557000000	1678007357000000	1741079357000000	1835687357000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
267	\\xa7caa5778da6e7255d375e037e0fa273f2ce613bcd1710859c5bf12320bfbc47c0f20aae5d3b20d3fddd8d3b3fca70a8276cdfea3d152fb84b973de4dfc3c153	1	0	\\x000000010000000000800003a99d4b5d59b8460e4ca6e0eb26832c0da07c7a5d6dd39d66681013e00191b6c4ee90bb541e39760cbd181492f3b48d003746ba06663e2e0497e83ab855053cc0c51b651c946cf154a40dee209c1353c839f9d7a3724a9dbf94ae8776d37ff66d93eb050df5c64190de5277231921ce6d47c1142f7d36f8341614ad3ab3ac86a1010001	\\xc7dc09c843e257ad1d5413c9088ce775a8eca163c5d137a5ca00fd2d24a2df53fc00d5bec5609822a1c342b905870f11890dc4464003353a43b435b4dfb7660f	1676798057000000	1677402857000000	1740474857000000	1835082857000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
268	\\xa79a26f1c4acf351f6d67bca00cdb1665cf93b4125d70e50eb3a953585f3e79a31bf76ecc42c41e32a7b80ddffd185a5721bcce2d88e41a9c8103ddf606e4f76	1	0	\\x000000010000000000800003ac4a67549f3dc0018f9bfc7c52a687091fded577052aa2ccb64bb77a02f9c98e5fb5a482157022e38568d5525a595a390a11905933058eb1d9611b9bbd14442252e395c7012ceb2d32b33af7b05a7b22083073b09b515383b2f6fba304f23f864aa0cb721380013c845c782500cd4b6a7efd989409779c28fd1725e554646013010001	\\xbb5b00c7bb13486b72e41ba6de48a2ba04c6bbbc27d1426f51d6c4a640e3544e04b61e5b0156396c8ffbb2b8b14ca0d63694effa2e02d52641a7eeb536c29e0e	1671962057000000	1672566857000000	1735638857000000	1830246857000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
269	\\xa83eb641d4b593a4629cc7821532fcd322bde133e83a4d53dac89bc76ad3988955625461f77bdfb02a36ab6760a0e19b18cbb2d44377c3fd84aabae789153278	1	0	\\x000000010000000000800003b4f10e64cd59d30f543134897641b9c9dbafc3a38df5358330488438405d2ca57f0f569c4c354344f1ee3ca266bb75bb69dbf88e39148cc3f718f84c61ecf2ededc798e3d5388b5bfadb626f068768079be0d87f655e658606444179bcc6562ad7bb4833d83fffaed20c374a1035de062e39f6ba5fdb4292645759c873c903fd010001	\\x919e57b810036da8e0c2f281049555b35d8255bac182854f8782d2a4ccfb80da1c543de13f3772b2d6642120336ad0fae615a38ed0f712e5a3d4b0cbaefd1805	1665312557000000	1665917357000000	1728989357000000	1823597357000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
270	\\xaa1edef02a8c4dbd406da62d7b8e5da38ee3b88a0e04fa32d42eb4b4140ab5ff6e9065fba06092f82ac308ff9957c26e689ab792bd45bf2fdefa617c0eb00868	1	0	\\x000000010000000000800003c94595d2dda47d7a700989693ef6adf5f30b33d67eb891d24e8541949a64ff3a524a9d10ecf566e3c045a8a44836c7a5841305da0ea8fffd5eec35f4a48edc6010c1a6f6b16867e57af37f940d9f6584a2c9b9cacd1d988a0c8b7e5f49fcb75541dfd4260f1e3a0bd8b5a4ded95d580cb30204365429830f4cfae75764f6bad7010001	\\x4dd31ac2571f9921f65fe356d77c8b082265e750f0169663e1f4ac2bdbdb2f2c16ffd444b068ffcca0e3f28bab4599ae4b7666790e5cfb822c18e9870cf1970e	1681634057000000	1682238857000000	1745310857000000	1839918857000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
271	\\xab22d11b8bd5f209a182d09b0dbebaf7be2e2af5c47daa466d470cf8a8f7ad302713f45a2b49fb6575d9e94f488d91736891a5ad5dfe209bbee8fa2a8d934e47	1	0	\\x000000010000000000800003cbc2145afd1c24b111c8606c4332854531708cc15bd92a31dd83e4f718f352c4af7e8848013697490a1b038f774b24bdee61e0215622343a4e2dd75d32a0091a59831b57bfae4b23d07c63e6d8802014179ae85b34c0cf2cb1ef99d06e3f42246e352827c15a09c06a4050c1f08eb6d33e0edc4c5aa75cc0f87cdc3073a37e7d010001	\\xc3c75a01a3f9e23432a5fe11b98d9b2fdec116cb62b7eafc90daa7babe9c7eb6fdb9ceb8287615bdeb7af5206c6e2266aa7cb13618d1b6ed86b058da959fa806	1682843057000000	1683447857000000	1746519857000000	1841127857000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
272	\\xb5523815dcc4eccb4a09cb6d969ecfc068cd2d4d129983844de15e1531efe651b7b4abfe537a960bc209548fbe2ccf484b66a727010d36f425362fe30bf21908	1	0	\\x000000010000000000800003baf4aeaad8686a2dc8702921b6874f0c02f211a6e5c177e1d952fb8eb1f559ed6c5575db40d603bb9340c1e5770a9ee7d4d0f49315184d7df02ddd417715be73ec026ace84a19314ded946a5241638121dcb63ba61b1d81cbf6a7281eefdfa3206b15bf418dc1f8b204f874f8eb8279e2f9bebb73b0367e845b5dae4e7e0aaa9010001	\\x131758d25f1cb912db98e0920110ed64c41aad5c2b4de1941499e11ffa070f938cd5522a316f8debe4c578727f6fc5afb1bd662be91b22e3fe273ea51ae6e905	1686470057000000	1687074857000000	1750146857000000	1844754857000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
273	\\xb87ab7c50fbd33e1045e1d10412dbb865f6dca3a3d30125273dfcf74cc1aae91e0f22eeafe089b72b30475c5e965a60e9e0ade5474c34ff9540c4f17a064f3c6	1	0	\\x000000010000000000800003b0265235adef17f35bea307cb5e18070b51b25960e05bc2162c986118b3eb78951150ac1731c80aa1eef83037736eaa14ecf9c4396e254a0ba47002b2a5a7460bed903adfb874dfef46c7adbdc8b56e567c3b5f5614ca83e0360757467a3f7be32d9fd93b02dc6289e4581e5a679db08f2fc695e8b50d2d1d57e3fb550f4430d010001	\\x8dd61bf35dbb3312be7198478958dcb4063bcb07d9b4faca31e6b49c94cd1d70fa10d97652889c3011a01a4f5d49ad468dea86dc66e893183d62cd2c04d11b09	1657454057000000	1658058857000000	1721130857000000	1815738857000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
274	\\xbd9653e0497b9ade8036687feb8bf5e2ab50c36ae817f252986d12daa7d5d23b76b17b239c29c8eee8eb121f18a12591173ee3639b4877091137af70dd9a1941	1	0	\\x000000010000000000800003ec41f985ca399d677613e1d1ed07ef063e83fbefa5e478c2d9d079a045d467a6ba632306956f74d5e772cb6c31fad1ff0f4bbf86cf18b9195a58242379f49dc25bdf6825459f7fc0563672acd709a897128d2df3ef0bbf9d21489d2b9c4180a30ca845552d2941b4ad431de435162fd4157660b6689e837f841a39de2796f2bb010001	\\xc1fbcbc2ffd79b8efdeaed8ea668248e492f43ed26498512a0252c5201a1b2f067a53220da2ac4d2aca332fc1b364a33649ddb1165600c002ca424e33d76cb06	1662894557000000	1663499357000000	1726571357000000	1821179357000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
275	\\xbf0ab5e5ca3832733ed16ed410df4ec7344914d3a9215db061de662849bcf8ebafeaf47bb040a55f75d4cf25b5e4f6b450c0ab88791b230095cccb540586dd98	1	0	\\x000000010000000000800003dd6cbbb78719ae19e64729a7f7c5f784b3fbe36c50e16be3cb2f1c419ca44da4dca8519abf0d07c6d59b88319630f0bb80dbf838156282f2fb9a7287b13aae856331889a1388bd756c5ed966f24803d897e2876152722bedaf9aee13e7dccfdc70db30096d61f741fa65a09e680c7e12b05afcf80b496b928e9e54f3532a2ce1010001	\\x88de7f1d294a44b9836024024be86edea29ee3f9318ef5c29bf8158994db66bfb3ac5af59b393a8b58fe08cf0a222647da610af1d3875eaa0295564f107fcc0f	1681029557000000	1681634357000000	1744706357000000	1839314357000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
276	\\xc1bec44dd12e52bf2ac370c653e8abfd5da6875ccea7dabc9e2715bb8836b131185e1fa0dd0ec2935aeecb4b39215c20e2e45e0a1114bcb161c7373b10200422	1	0	\\x000000010000000000800003cdff500bd5d15eb3f77bdbcbc545b6965178e4b47293ce77fcb69196c60fdaef17045be6825d7c350d4e6a9a879f1cbd689e0a8a5ce37229843cdd0398be70e7e9a04d7142daee7bcdad47a288bf0f6c96f61f1a74393f596c896d9049f6caed12580845a07d222cbc63c9cbbb31c1ee8d51197bc2dc9c4565d97d20e37e65b1010001	\\x25bcbbd6c30817bf3d6359a11d1f32d063edb554169da40bd0c39a34aff79a7439b54b2e1a6045cb80a017e4b85355bbb4451d7c321af07fba7cc73cf866330d	1666521557000000	1667126357000000	1730198357000000	1824806357000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
277	\\xc2d2ee2d1f287c95f633ceaef045dcaf8468c5b83c1a94a7d55de6aa67289c0021707a7428dd0323534f312e7f47289791e130b4ee036cffcbbf734ae2f0d274	1	0	\\x000000010000000000800003d68decf611750a10c25fd395e409eb38ea7b2ef139a2ca04fb2db481e87536280ef1ab5153233079f85e0b4ca072081ecc6d04a433fcd461589a4c9f7f1e063072edc973378f5ce531582d41a313db2011d3319bb1872edbccb614d4431a8fb7a630044c2552a0a53d5be6fc21068628d30283dd8b71d5128ecc5c86cd1dab4f010001	\\xc2d1bec5f96b04b457bdb35e3e24f64967d9f0cc8640028cdf38d90022622ab2b3f230116880d82b7c8960e415a8c1b58bdc0d8f9257f3ed3ac4efdbab942200	1673171057000000	1673775857000000	1736847857000000	1831455857000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
278	\\xc356bc274e0ee9b57ee00df070b55439d36b55406eb9be59defd71226c081d029f841d03bc728a3d3d45b260e9c242f734d470bf6bf70bae1bfc75bc8f51a0b8	1	0	\\x000000010000000000800003cd4525dd2254b5d849def64027919089bb2bb2a8481c259217aa9674368bf904611e6f89fbc46103bb3cfb8e3cfa2df28be95037d0d7cf9d4657d1e0b2aff499f4096fca3ec5527f07139dbaa421a8bb0654bd2da4ce2a2d36f8fb91dea52190f816c7627ee6701f61d5ea348a25e9304ed139adfe8bc48655146a649fa3983b010001	\\x3810d6be93249141d46dcc7246d4b8b7a9083fa0cca6b6e868d19e15e1e2c61960a1d4918b0a6d31b4f6cd547cc191f7a9c917fe3b9544157ec3ccb011421905	1686470057000000	1687074857000000	1750146857000000	1844754857000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
279	\\xc5ea14e1cfcdac4ce44596cf239e1de829e6ca9db496cb9fd2ffb33af13ff9dd4f89c75bde95d9c7e27093008a26328246aed6d581627d559c9911cf7dd3df76	1	0	\\x000000010000000000800003a9c66ca8e9eb34ff4a0ef382c6c1fd0611a501e15f84db113c25d2150513cd937d492f23f501b9bac1485206a65706473486bb2087ae1425cb3a5d96572926d53980e5e421238e7eca7338530cb8a094ffb3668b05a0b67a0f56da46a16a48377b5304dd655a70eb10e7c1951424697751da965ec1043ddbd5195f14bdce6295010001	\\x42b497e397c5960825bbf9aa08c45e9ca424dcf38b597986aa6daa3d11f772c36abf469e188bdf1733a7bb1f3b674e8e8fe4a616ed0c91bb7769c79288d21a07	1658058557000000	1658663357000000	1721735357000000	1816343357000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
280	\\xc63284608f095861071811b1969596e30beb8209a46dd37122d88506976a47a6e55c66dfedf5248f062a4c6d7b8bccea9d4c39983d96c22b91ac2314120638ed	1	0	\\x000000010000000000800003d4e49177d2dc4d0e9b24177416ac2759eb5bba5746ae733704cb24b6fda666b7fb3bc23fb2bf1548eca95cb7b952cf9329aefb7b64a759e4290098d5f1cca367a9ee036c82fe2f08be1ccc588d7c34972af769a8e54f8b86ea1f147f0fced0521bb19e7180a9d65bcab84e24a0caef8c67a6093fc96d73682cbeeba8dccf6065010001	\\xc59daa7eb80fb66baf6935683eee577d6c7d4f824e1c56e48ab0f327d5bafa9d4350220551d4422d9b472ff01dc7f80d608ff3662ee1da057ed323612a253501	1682238557000000	1682843357000000	1745915357000000	1840523357000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
281	\\xc86e007fd21715a191918d0d401355806167ee10d3ad55c4cc72ea0a201fefaa516820f104420f362351fabf6689ad9dea3f5ec69d93c6db5ad54d9db1979a4b	1	0	\\x000000010000000000800003d0ed0f666fbf5eaab745e82333bcb7c19c0dca1410508112fdede5583d50346ab9b6234e1b7cc57b8e08e1d0e7d81addd24bcba61d5cdd260942d3be08ccb7f64c040c10b8156487e6e3ba29c95cc64c4001a0b54307b7f7b32813b1dd92cb1e8bc702ee01216a7486b9013055dc526cc4ff2b92fe667d7b96e0f175222f8a13010001	\\xbaeb9d9a5d1333568186640f51c8faf1f02277d57543acdce8fc69e23ad04ed2cb761e751187f86894bb2c0f5afe3b06da3da0f5120bddf67e830790442c0f0e	1665312557000000	1665917357000000	1728989357000000	1823597357000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
282	\\xc96e0ced4650397ab5943a2440c5c384be26df919e2c5f0c20d4158aa8956e0fc0e6680911c75047996b405bf6a7f60eabb7dd94aa8083979095352546aff4c5	1	0	\\x000000010000000000800003b192a3c821f7fa30729d62708bf08a76e11ac64d417c424fef373a9bdd7d5d94377869db33a223877b908e01576dbc9496235f043f7174a56fa087cd6e6d38e232b2cc9b68a1302b088aab19120537e403a6523e0ec4d119881428f4d3e5adcb15112b65b27dca24a5cd1bb8aaa5b61c17cbe6e88525ebc97f7927fd98a3f8bf010001	\\x4d85008910200988e74ce6ae5302f0e98aaa8aa5f95af4845ff2d83df702e9f54d0e479c593b478a6f18abaf8573e33d76475668105fe8958dd4b92f38b5d90b	1658058557000000	1658663357000000	1721735357000000	1816343357000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
283	\\xca169d4ad1ed445e7ef2f62abdfe3e725fecf58a644beea3b17797e18d3fdbe4f4639d7a9e3087ba584386ea68cb769b5424231c1235b98098df2822c1eb6d2e	1	0	\\x000000010000000000800003d76f918104292ab84fd524df7ad38e2c3856226ca50a34a0c685dd6719b9e89274cb4b4ea2c9d55c07cb4d4124da65e32c9061402ea6d3f0191c2c070adb9308701e10af09d8c4daff3ae93f0e8e4943a7176928e52da27efba6ec01f0c71dfd5e52d88845406737d76031ca2af64b0d6b849333c966d33c271978c5f3a60823010001	\\x4577847bd92984d7827f3f68b496f644cb28ea421589f0025bb144fa48dc5785f58dd711bb98fc01625832f14946ac25ebefaf74d32d265eee92904d627fd908	1666521557000000	1667126357000000	1730198357000000	1824806357000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
284	\\xd22eaf579659cd369716938fa8ff16ccf8b9466916eb0d0200fafba7d185f3acf1461c18a6c6999be4e1b1d58060ab0331e7cbc501d5f605d55fc2773e5671e3	1	0	\\x000000010000000000800003ae138ff77de606d58b36e8b5e3b435cdb65b8ddf6e51e981cd37465bc0768f7c5ab3e43b70e60454b64ca35a9bd847fd7f00bfa57fa135f650b73d606533c54daa3de7b4c4d157f20315cdcdb7c0f42e15bf3fe9d956dc65d057ea20c991e0951ef13d94559139af35fc781a7fa8092765ca18132cf7f3ddc75820a220c8af0f010001	\\x63fca97e9c42222776acbbc48b482688e53e1b4b4860c7b80b7cf23113b023c637b00870922f117d8e307449ec01d4695506d8410dc5786470ca8e16206b500d	1674984557000000	1675589357000000	1738661357000000	1833269357000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
285	\\xd3d6d31df266c8a88c29fed7e7642fb2cd383bbdae410a6e485d6856e14a5c38500ed47206c953168cf051015cc8500a846b9a38ed03a767534b313545dfac0b	1	0	\\x000000010000000000800003b6dce483ceb2a063acee978c3a1ba86bc571690a9a5a8f29e27037f81ee797a6f43b7f2c7068bdb5ca6d788d0ecf8d94608498ad87f707d019503027737b0febfeb557627ef5dfa08afe6157f17373c1f32df0f517eaa89c8cf8606422dab8d0ecc2da7c493a072cc5fd0c473d0369db85d733d7464a92142f2f82304b806d95010001	\\x281d749f5e6bd7fec1b6c3b5d02e3e4bd50161695482111692d3117f5a76838dc00cf1457a1e61aa35ee14d97454d776487522789ea04eb32d2613ca56adc50b	1678611557000000	1679216357000000	1742288357000000	1836896357000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
286	\\xd872be98960761ab5fef39a9dde2042c56fd516d202118d66a7c90e2a1da15c1209833a15b26f938b389ba1b298a23c9c83ee19c66f1c396bc4fea29f4c0ce7d	1	0	\\x000000010000000000800003aecfbf32a87bfb8b33656d3dddbb997742e539edd63853a6480d3e9058c8ad56a628ee8a10821af58dc0d77c2b2fb2b9e25c0520aebbf2980bae8fe7791f95acd9db5e7df35305707cb516b259b9999de276cd620e1c64d528ea38f9a910e061376e6d30730fe4798d3a76997dda29659aa39817efae97520cb6d67d1f7ac55f010001	\\x7992716bda2a87f0fe6b2eeea46c3b36f66cfd2bd8225eecdc559483ac8dfcd68762c1d8bb2f970c20c81e22cb8d9b8206f1c678fddb3a07ca3b6bece436fb02	1658663057000000	1659267857000000	1722339857000000	1816947857000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
287	\\xd94a30df40485450386ec127b60635c8db7a6dbabb3ffc50d069972d5cf5c24bcef9d2bb8c4e4a4ab1d98e8700dd53f32c07ff4b5750154d2dbdbd9267455ab9	1	0	\\x000000010000000000800003a9a8411878770a4deecf9f5511b692423bc37512fcc24901dcee35707a73831168b4f7199cc47c3f8b1c3e22625124572d9b06040cd13cff0f406a3274108a951af2e4b14f3cb7d103b68fe905028b4a509efce77405247b7d58925f2af214d3f4e4de6ea1c06dcb2891266f3515d7f83c202bb86ad45371dd4df95d4e3c13ef010001	\\x4ecbb8624749621b136823fb9093cd5028cced9b013a5514f39d243b53e19368eb8befab0f88880789fe1a8bd31e3f3af95ac2d749d6eb7939d602c7b34f8401	1677402557000000	1678007357000000	1741079357000000	1835687357000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
288	\\xdabaf6c22078f31fe5d9f5a40db7249fdd9e2d5759c58babf18c8fad29c165108a4852502bdf468343167a9e8c040534ee8e748f0e8a02b2d57d31f51e83b0d9	1	0	\\x000000010000000000800003da5519683bd5240ed5b92214b97747f7c939cbd00aa1bd67bbfd6bad4484353ec9b5d1a61a31b85ebde951b219a04149f304bf55c2e3551a56632bb026d6ef87bd142d9b4777577b23a343fb1d0f4b04650688b37c8c1e88c2a78c23b87ce20f530bffe089b0300721b96f1b25e348bfd09c32c8542d3a2f7d827f18861333e1010001	\\xd716bfea8149a9d8f3ba3c1ec49cfc411f7d10bc1cb836c667de949d0c495ad57c2f6cd52fe000b71c5f5e32d1f8918df034a02d4b232f67b36ab93db37ff50f	1676798057000000	1677402857000000	1740474857000000	1835082857000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
289	\\xdc96162e0585bd188a460ba12aede192609cdedce341a75ade07a9dba57fab223b634e9db1d0cb4d8b41fa437d3d7d2ecbc507aadd434fd933a43d5f82e3352b	1	0	\\x000000010000000000800003c68dce3149c49e1734f8976ede6f1541605130b5e0dceb4d10ef5ddfd523f793619d37807468749362d860ff042241efe9860dab29f667b7bd48b571fcee0a2a289500e237f36a7cb806da550d6a96e4faf0ce7623d3d7fc67fac2ecc7dc7bfcbe31e245f5b5d8764c85b964648b660458f16fbd5e83d8051699eabcad71b73f010001	\\x4878c2f6ff043624424b6d56f5cd7e95e3fea0290c16960b3c1210d08a8e0509114f6cfd885aa8a72f4c436309a25048753b4c6e58cb362d5ae0f59cd5dac80e	1685261057000000	1685865857000000	1748937857000000	1843545857000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
290	\\xdc6a96c4ce08f314e8f1a43bb161d748ed8e49e87f208aa0515ec349a998d959ad2ec56dd987facb91de404b26a77a08af12920292b6c5459a6f2613cb7712d2	1	0	\\x000000010000000000800003a4d6fba444b364357ed85737a21062ca65e8d3376a2c0c64485b5e8262baf6e37a23f01b1aa6ff6d1981f7c4a15e9e241596406c0dce4c41103c500a93c18f4012b9b43f6e010824b9a6bdbef4460a3e22b622f06701ec562a683994d922dae639b865a1bcdd0e039ab91dd292b7336ae3c10324f211291eadeb59e069229a67010001	\\x9e09d4be7e36a39ffed2a3b26ad8c93c5c928168c4db427f04e64884c417018f0c966ef425fa61d5377b35db2e62f448044360dba6361abf23015dcdbefea30e	1660476557000000	1661081357000000	1724153357000000	1818761357000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
291	\\xdda6af0f691e8d8f3aa9a3c611d4d9d8ddc902e6bab987e616e841a0abaf0068f89af21b0836c7d2fb2aa06ebb85843f7b11df439263b5843138f029a8a0e5d8	1	0	\\x000000010000000000800003de67d7e5a1321c5166aeebfda749e1370019e41062b2174c7fadca4649bb16da7f5d987b9566f43a19d0861a77eef80e23843cacece0fc627b2320eb4f43fda2957047a526652914e2945b15428e0e118dd149e6bda935057d27c783a99cac4bf2579041d13e73f944ceb769e693e1e9b00331d7f722072b7e2f13f5582fb52d010001	\\x0b157f024ccfe21c940fc770e04bc014ca08981082ce0c213a5b737889111b0adc86edc4a55d3818ba299fb2b3e800d594f201877a4d7d052d30c7beabd8790c	1669544057000000	1670148857000000	1733220857000000	1827828857000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
292	\\xdef6738f05715bc11b8b88923dbccd73fc98e8dc396aa0730a8ee342612df42808e7e2449569c3d20c541831a3a23146051a4d2cea3bfa45d45cafc2ef96d5eb	1	0	\\x000000010000000000800003d5f81e9872eee366a2a64baf7162937e7d9fa0c52191f729a9aeae83c0396d088430a2d33f8c09f44775d6f2851e8a4c960739e37d5e7996a0e05bda083ce2e4637a9a71c76b5c148d5c79c162f67686dbbeaa72d3b5b346798bccec505be7abf16dac035f04ce99aaebacb758fdfb3767849913acca2f24beef479c84625a27010001	\\xe293638e50fa9fc66ffc7e44ccadf9f10b8bf47277eb1d43cd60efb679e0237b03ada011120b008219983b531ba9d9be99ff20a29e6dbe1a37886032e26e8205	1667730557000000	1668335357000000	1731407357000000	1826015357000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
293	\\xe0421bbc753ce731e257f01cbf5e51d7b4ec0420999b0b28ae7e79a76fbebe3013b464a4bb14852e2c477fb0d851da10edec6206b07b388b8f1f86bfdc2b8b77	1	0	\\x000000010000000000800003c9d11c837805b62ff98a618dee02df52e74693c28154e5e401a4fa814805f84b285603e9fa2fa1504222ce135583facd0cd695f18cbda335c96406d2fc37864df6cad5266547a79ec1d5225009f1199f0433b9e78d495cbf8d13ba1b6ef9979d0a49fea89828af6c48e2e760bdc9ec3c970ed34d9bb966ac1263a241ff2346ad010001	\\x4af219d52b37728186c04225f83df3566ffa04bbe4ce04b961370d4b2cec4db7457ffbe068622aee2e511b77a95f3fcdb2178631e05197bb223131a47581a707	1656245057000000	1656849857000000	1719921857000000	1814529857000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
294	\\xe276fb3f624ba9f72860fa4f959eb019994395af1dfa1333cac008df299db9ea97da29fda59b88706172cdaae84c5dfe84eb238d8cbf9e58e9e16994f1b6577f	1	0	\\x000000010000000000800003aaae566222940d6397c0d90dc26a88e6f9867eecc020e65590b7b4889479116b7a3aa12abae9ba14a71a417d29ad7deaa2308e1b5d88a20de284b721aa4ace0e82179238be9c62a2470add7535e2a96657f549eb2decb0932220ebe11e6b13c4613005acea49bba69f95249b01ca9bbc982d8d923121322630325e788b6dbb99010001	\\xcba50474fbfb43aa15e1389a77239239df427a4480e0dc4368bbb572deebc382cd6d19e7eb3ad0d7da67dcfc8f983270b36458b748d67942591f9296ef85160d	1661081057000000	1661685857000000	1724757857000000	1819365857000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
295	\\xe30a3fd504a5273e11fb5b2420318c36782b8f75890fda2e650507f16c8e7ec12833865fcad6ce42812b1646f24f2f571872a4e989a193a3e792b9d0b6c7334e	1	0	\\x000000010000000000800003b3b16c6e8fb240173a5a639cc1fdfc9212e418854b52880d0962619ae012c2b9f4be7258a30cc2b792595cfc1c0abc92f2dfbdfffae8492cf31a74486e674211a815fe121b77305f3166c1736d1ef4cc399dae2c75ad8f2e9513106ae0f1eb6ad8622a1d86fa3f3dd51e6795b09bdee6548985e10c2e9d7091f964e7cfaf0f71010001	\\x91a7c4b3cf84a37fabfdeca48f89fd55b2ca612743d201b844e461cad9527393ec07f883bca17760b703e7ebba84e13d45a32afb4ca0320a048d3a4667e19007	1670753057000000	1671357857000000	1734429857000000	1829037857000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
296	\\xe382097774910f60ea9a35f7881296fd244e0d10f600bf485b6641bf0ad3e4e15345de953ea34f7ba618926856e4c936c5bb62201fd0365f074ee08ac4a8a44b	1	0	\\x000000010000000000800003e11d448e5c7d9d1eaebf718c4165bb8c761bab925a4dcb044b8d4de70401e085e077cea784c37b24516d3501f542beff555f475988955ff26139d105ea8970395f8547350b25c9a86e8475987234031cc9512a51229185878c17b59e28d08e48f2b18a64d12b2093cc7b70ef27e415394ce8d06c73879f8ddcef6cc38cb1cbb5010001	\\xb7cc57a752655b7827180c9dc09dae28eb53cb66dd909a8de53d1fa76033d6816929e7dd4059a6bb6053c1110258ec12467cc11bc7d89286b9993a625dcb8104	1670148557000000	1670753357000000	1733825357000000	1828433357000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
297	\\xe3ae42b4b81bc4f1a73ed668a08c9bd02c7395f99607bd36404e47a4540bf09acd10faf582133004c91ccbd31816577a4c98da08b60197aeb6ac303a2fadc430	1	0	\\x000000010000000000800003ad958ddcdb7b9eca778dbb0506c164f1cabe3af298eb8ede5fcc85485771c6a698d55913a1bb213e97958a34b930b15b7576893a8aea4e5b917968a49c0ff3a70183aa3f1eab9afb886df82f60b322e99cb795af64c2d8115b5e2d9a758a29fa2d2baea86c05c0768e189a61b6d3a0c09e0bade8e4bb895c80b7481671055bf3010001	\\x936e1f02e724a2982dd96dfa968bd4dd99d85988752104679783ca1b709da06a9d353dca9b7d9c98e974d0a4fd1b64400e83952c151629c893a82f33ca3eb300	1659267557000000	1659872357000000	1722944357000000	1817552357000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
298	\\xe7be3c438c3b85b85984cfa9d7fdda04bb5cfaeedaabcf0e67fde514f2b50df91d0ebd005ecc748dbce07786602a74d2451d2516c145b37834c177779d493b43	1	0	\\x000000010000000000800003fb55a4310fbc4ebcad66ae8000b649710c3d1cf0b22602e7843d6e945b634c6b4d97d6f53f3dfdae18a15e93308d46e715294cc2c512c486ade8cc191aa2c1445a59c271993939e5aad6cb102eab2118a2be638b1b3d5e84369430bb0e4dd81868d83fbf3a76020ca2edec6cdd2a3963db6b694066baf3ce991cdd41d497bf9b010001	\\xde8e086bd4288be371b06ce08a37003f5cdf19d17d0a941cefee8a684dff9ea324c58f50f9a78196ed6377fb4fbc4052c3a1ca515b95bf2bc8304e130355660e	1681634057000000	1682238857000000	1745310857000000	1839918857000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
299	\\xeb1eb2126e951169d47d1b2d882668ce66c3f18ee2269b23850b76d7241fe9b283faab26280c4b45d6f65626334627133a8e319f5e97225d1109327735642c69	1	0	\\x000000010000000000800003c96cb5e0c0354a504189e65e065bf1eb1dec7f902bf35de45ebd7ac1cf395fc13f0746752507510549d27e8ab36fe0baae92b229aa8d7d77cca5ac940c6cf14370937a302c93c540a8fff7bef56ddb9e7462efbda8fa89922dd79fd7bd972fccbfcd96a41b84ece81299f686b284e1467583eb974f535a6957f46c46f022c075010001	\\x37929fbcb0e0557ad26ac1191ce0a15edfbba59fc7ab31330e389fba98794fdd9bbac81bace1fe3d8c81aac1e60c52eac87e77bf4e272d05f4e0a10e6b0ad101	1676193557000000	1676798357000000	1739870357000000	1834478357000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
300	\\xecea617c599df6b8a3a5dd7625c3d202f6bb9493c8c9142df5ee68f648c7449c0b3eb3b759b2cdbe24b9df9ea4ecf4d7f449db5cd391d465111079f5fa6d0f9f	1	0	\\x000000010000000000800003b4fe8cc4dddcee1a8d497c105d80e3ef7ff487852f3ece35540949ae982456c7490aa861b9cb1537032c1417f1b28b043b789d066d071e9f06e72dd7ac4e0bc08b153fce9910a26bc6ff1af37a9fce1591a95c4fa609b166224136fb0a29ec1716db100199b24eef10e54c5661ead0d571da3e5b29871b3f03c01edc52bc8d85010001	\\xee5d72ad2e269d4d723d02cec78c272a4944123686c48a57587f9d9011fe8bd2605cf168ce98f36f78ac166c769eca155df4c8a1bc58e1cee3bfee66ef643f03	1657454057000000	1658058857000000	1721130857000000	1815738857000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
301	\\xeeae2930f1bb562aabf9f1a267249f9067109495432462e622619919e372e99ac737b2322ec61cd54208f8ac7c343f85fa0d487429bf4d6d963bbc7480a73cbf	1	0	\\x000000010000000000800003c2a4ca562559e90e1a635f7c6d8eeee9aeba17a71c3b419fc055815a293f0fc015a32833cdecead670618e6b8749bf252e02d0853986db482bd8656b4cbffd6618f98b3cc8f6cbe9ad5e794b6c683583402340a74b0a5769c1892283ee85d26cdc6045a1f9899d7803880a838488f8ea9d55705bcfb802a67dd0c9a8c6483947010001	\\xc9ee7c3948a234777e3e6e69e23d8e90e08e282581b03557d5aed6642db8fc58fd6b91878fea9e0ba050aadbe1badf8f7cebacb5bcddc892054160699bece20a	1660476557000000	1661081357000000	1724153357000000	1818761357000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
302	\\xef3ecb954fe52537789544340a95a4791615a28d35f110d5843702787793cd90f219ee185082ef7ccaedbc5a6018ea34b0eecf06729febe871436b097f600f6e	1	0	\\x000000010000000000800003af2fa410a6bb34ccbe8bc6df3a0b20b498310abb1e39c7a549ab1b5568c0906f9dff75a648808419b7d64030559749bd1a97d04fe239c20535461116fe1142458905a4daa1ce90228cf6f978d1e96b251208706ee39c8bd0ed748b5ff4050ea170d79b52722f3f4b0da9a82074c89d27a5e00d56a40dbd2a2a460fa5b6259f71010001	\\x4edc5465012cb642dc2efe0bcb9c343e71ec6369a10c6df4e2a6e4fe76bf1caea852d94bb9f23fc70c39f124f2bca79bcafe8644e26362152fa5d877fd205108	1663499057000000	1664103857000000	1727175857000000	1821783857000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
303	\\xf5a66e8e150ad97e8f142f40ea25ec6575c1f52702a13d162de277591b2d770943a819d134dc357f8dcca388b90f399a1809dc22fb48ef6570e2c64357f9faf9	1	0	\\x000000010000000000800003acb65d2014a0ca54ba18821084b3d387c58b489ba498be886a2f320a5a9270a9921d08fab14943413e5bb3ed77048fdb92546d2849b77e159f512f418dc32248a415d293c664741f93db3f24ee4b46cfb0666fb1b4953c1b85af8712d41a6def04489321bd7f8c7f4a33573e45dd6bb2129da1865c2f18ba13f759ca92d4add5010001	\\xfa979cb1db55f3e66033cb14d683d2051464457afc49cb44fd04f560026d13e955ed6508957243e4836ac602297b2eefecc6809bf9717e9daf196d49f648780d	1661685557000000	1662290357000000	1725362357000000	1819970357000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
304	\\xf69e0d2f3cf88fa4952ea75ab8431cd1418dfc33ebdeec3f170a526953298fe8281cfd015c990868056d6e6a245437a548ee61a7a888f7b3fb5da0529a6d2d36	1	0	\\x000000010000000000800003a4bc210882ffb4e8f8239cf71966b4fc906fab80200d50b8daa5aae1fafd20e65ad1d420f5ef6bb4f41919485c47339892bc0e47cf60afdcb19bd3f61e58968dcd5d0e25f84fded242f0edc05a726f7a844f84b8304b5f82abb3a534a13c2283a7ce0653ea74bb90264e670f597329d7173a1176ea9c5a93b3357c786b8cb82d010001	\\xf55df2adc0976393284454004f7315c1a0f9257e6fbe224653a74af3c3ac1873486f40d10397561e229b4d0e2f4149177eea40d71814c52e1b0be04f09e3f30c	1671357557000000	1671962357000000	1735034357000000	1829642357000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
305	\\xf6a68d982960b98033206d3523f94641b51409a102567d2ec6a83e9c858010689bbbfd4e572049da52ce6c0ff970893ec750f032a2275de704c49b50b7fe7017	1	0	\\x000000010000000000800003d76c688170ec40e23b768d28f1e462f296610be3df425a51edaefbb12b7be8e3a18f5527a3a202ce1c2064f987e25f4aee0205f37ba47fb75bb49295c71f7c67a32c1a3d9fb47c5e8248771f401f14b6d03a1d0cc6d7603a98ab9c892b38a7447fc86fde463b1807fa6eb66c0d7758b364bff44345520d8c8dcce65b94d07ff1010001	\\x4814c7c63ae2f55813afa9ba7ffdb8a8fc32102f9d48b7f228e0a39e469882fb26ae7c87482980cb31d39439046d1007be4b31979b811eba4f316b4d9ae48900	1668939557000000	1669544357000000	1732616357000000	1827224357000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
306	\\xf70eb4f416d0900d4eafedc0027c4830275017c1f826bcf706515a29acdc46bea7df9af78dc47cb0ef5ced4bbd44312ff02b0eeaac386f31c34401b4ef2c4a38	1	0	\\x000000010000000000800003c2c3afb1e8f6321ac13fa13734e8117515e54b17202dee6a6d87558a1eba1d909eacb37e0fcb275ba3eef6d99f9546350bafe2418faf433462b7ddf2d7d2f964ebe7442b26d338dcccf758ef553dfb4531ce3c33d6ded3f412f01b36a4de201206fc40c4dc27c97cea542b198782a83d9b7caf852c1f3ecc9e07eba3b6b42f9d010001	\\x21237820f3915bd4d63206485548448c2ba0682207e6dc4279fb303031a844135e4b2551edb039032a296caf6de95b819ac43c273e2f6720553537e335fad001	1668335057000000	1668939857000000	1732011857000000	1826619857000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
307	\\xf7ceea56c21d1d53a3bb4d5e67ecce070aee7975556e3c281bae50240df0e6711383ce9c0aab4bee0a87114984f43d7ddc572c422b921fb1cbc9fa4348a189ea	1	0	\\x000000010000000000800003a4b0fe6b6fb877990a3e386e213816b5cd17e7d1b067035ba869060a0ba0ccd3850785c2eb29ba472b9c13e7128083695f875aa55dca72a0f716bca10ed295710f5298e4c433d9dea9f7384c309800cfb8f199c531fa88b35ac28386d67130c692b85fcc3a387a33bd207986e9c7f11ed49e9d2c100b39bf95bd0fa5ea0717b1010001	\\xb9e6ad55bd8076d5d6e2f66f15c5121ff95d6809b154e524a4bfef993858abe91880a928bc391b76e3058738875bcdcec9270ae2161bb876caabd796d11ba002	1664103557000000	1664708357000000	1727780357000000	1822388357000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
308	\\xf88aed25b48726361ccd0a32c6d645690215dd1ddc36c800a3d6569c713fb70ada934ae724310507967c03c73b143fe7de4ff3d8fff251d2bd33da63665f3b2c	1	0	\\x000000010000000000800003c2d5b0e52b2a92b15fa91879c6803e7de7410aca83b4a2ffddea843388262783b750763d87da43f0ba2f2d88f75b70c52f21a3227e28ef40a3ab2e7488c5ee3e34bb8c878d31ea744abe40f0d829a4c657844bd9ea6cb673472990097c896fbb308fb1bdb65d964bea16f9c2c18a2ca9d29291efe2f9d5bcaeb406f5bbbfa47d010001	\\x25c29e75520f67df96fee6fcc05b39bd1d20704e800fd3df532aa63ebd5d17c6ac02c530132fa80cd863698241eb0639c4239844e1ac1974627ccf19935b6107	1673171057000000	1673775857000000	1736847857000000	1831455857000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
309	\\xf8866b3894106d1c30a62e19fdc752341b59f2372134a1595ae55154b84419b07116f58ef58da7d07bd20134811f7478bf677e03029096304eeaa29dcd59459a	1	0	\\x000000010000000000800003b394da6ea17ea54d82580a488fcfb4000db1a41e4d3c32b5386d762701d461b08bcc15dc408b3cace62dfa3cfc3382f46f41339c0a18884159d982f4381924da04cb06a86cbb6de50b30d7001b2fafed46ad435a5bfec4a98a7f840d3b94a78fc8d48ea107e223322b3df7cb84f9029b14928ca7273b9a5a4b48399d16624179010001	\\x428357a63b0f4667a5c0248aae140c387875fa64694ab8628589b3d383c9f8932e899ef8b3c7819a8daf39d7f3721dd1dea9e33aa4c134df8c6d9dd321c62501	1675589057000000	1676193857000000	1739265857000000	1833873857000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
310	\\xf9ea3a651f320239a4c35ea5beb63e1ef01bd6349eda679a4f77c8063072628bdd1ce1cd874f2c2825b4a4d6c3c3ea1535fb6de307cf3c9cc16a31bc4e2fb449	1	0	\\x000000010000000000800003c9be260a51bc61dd1d7dd24d279401f76bc1542da8f6f2649f7a8ad333fddb03a067a197d921491389251f5eb66eddd8a4c6fb596b5bbc2ec746c2d1e7e6e84cd8f2af6d66fcae7063ff98f4c0a3b7070c2236221ce308a05dc5cc3b41204da32287524087531d4cde7b9979ca65154c42d0061eb8fb951c61d37c5db989124d010001	\\x25647287394cdca32a27b1bb774462c6219485c205716f9e3b786722905a9f9e89e903edc50b8b558996ebe5ade2d8addc2268df5c1614f2e92923a1224ad104	1670753057000000	1671357857000000	1734429857000000	1829037857000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
311	\\xf9c6626c3e09364af7d85c2bca3b930f0940606b20a528e4352930188919ef7b1a18ea1b696125e1a3909f657eed785559cb740e4d70fd782166477094194195	1	0	\\x000000010000000000800003d210a0939052fd9b7a441621c495b7b998ad996dee86c9d8d6385599564f4668c459a2cf3827f9320908bc9468ad1f7782bd84cf752d3348d43926a3d1e328fee7f0cc4de533064cd75585bae92ae37200ac97d112f57e22df8b9e863a804b2e156a41fad3d3b01a43910910ced53a4a538992fcd9fbbf2b2572cfd9d210f647010001	\\xa6a0dfb7cf4ba7d501c1a28f8b7c798df2a11810f3e1c813c3e210b917dd8ecbf0903638766a85673b841b475f385f124d3e803f142c0a33277ce60d750d9a0b	1681029557000000	1681634357000000	1744706357000000	1839314357000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
312	\\xfdae7092ca00504df40cc8a182539f7d89ed40c6599ec2266edd941af6dec4d0eb15e74f585ea5da69a2efedde4b4777d758a8ed9fa448b7abd598015d9d6a27	1	0	\\x000000010000000000800003d12fd17116ddcf6b236056c5a03f8c5e84a22f125c6ddb7c7a1587e576d4080b186581af36778f48e3ecb5e2fe170681065687cfbdffdd265b9e431859f782e73a7c3f5d54a265f2a50a15f8a9f77eec91a7a045dfb255cc1e7c6cb6bb2806d0db1b9d5a5a2956aaae47b3e88b222df7ac47a3911a96bcc127840e1a8195a22d010001	\\x3f5a39dc31ad4f9d585c307b6b18abfbde1b9039952ede3799b938a3cb2833372a07aabf122cc0944b4e9e81ea7b96eba9f4ab764f352ea3fdb1ea464d16ad0e	1674380057000000	1674984857000000	1738056857000000	1832664857000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
313	\\xfda646d02b37fa33d98eb6128295504c0afa5289f1a1e79534d916ddb26c17d8c93b5299a666f391f5561994ee4663d520b5a35150d500e81be6442fdd059544	1	0	\\x000000010000000000800003da8a43289bc3dffe1647b86565a9bdc53fb826d7d47507abce8faabc8e4f69c0f9b973c401558b1f0b0e5e379008c40347bb33ef01664ff92c15104b1800428744b9375c2695f6116c918334e084709048b937afaec6e4f2c152233112bbc50720a01acc20054584591baea35ea771b5a41856a38b263f78a7b8d9bc9987cfe9010001	\\x3177e384949004c6d402bacfd8f038168d429207d310f6bc6eca88eb9fb40fb64e68d7628ccc4dd02a8821df4e46aed27d412f29f48d9e0a93b896cb0a57a505	1671962057000000	1672566857000000	1735638857000000	1830246857000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
314	\\xfd86436b5183f78e3dce83266e678b5fa46bda06b3a4a84686780d66f91a87bbd72489d2c428af3d5bb236c1db11a5bf77881d82462e6e5718a35a56fc0cf2ce	1	0	\\x000000010000000000800003b22e1e8629a50dc10d6f28f8c3e1223cd3f1827799d06e95103a3849950d3d620a342f4a295caf16b1b39a1f036e6b4c37204f068df6cf0cd63e8b6e7f4979f86286f7359f93611b340a3987feeb5ebee4ff455b468614efb8f1aa630a6279554bc3bceb128f28e28a392a8cf00bd95b814d12a80a4412f7bcb424c13b4619ff010001	\\xf1d4a7b5510c09bc172127f082bbcb5824a26c9e9f17889a0bd832491cfc616c5c426c339749e4280d9dfc5ce6a05520b966eec0ab1d8ac06b3c01cad2c23f03	1669544057000000	1670148857000000	1733220857000000	1827828857000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
315	\\xfeb2f5ceedc0e173849302155556552958ed8f190b62cafe8713578083ddd1b27373b7a1f47be742af5c02f924ded61e09bd217cdf10b4c9ce7b12f7143a9026	1	0	\\x000000010000000000800003c53e2857c5234eb2ecfdd46cac3c645956ad018ca90e2b9bcca25009133f07ade3ba935ee2eba64e95ed0922bd0eb36e9fe2d5a3a4e5a7d75ab761ebea9712ea1e913aa10fb797dc403e0d97ac97ae32855e20cb74962b8141132c75161c7aad960fb03d2838a497d3acc3f1444b4bbd9e8e3ebf1347391fa626f4168f6c7a65010001	\\x2c4092ec9470f9161b9eae6ffda316335b7e1537a0d529fe279db1f768a461033cd55fd5776a0282f3d3d11bf54df9d86c125528eeb059fc31060e46985f0504	1678611557000000	1679216357000000	1742288357000000	1836896357000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
316	\\x000b76229e6a25007817649d1bf1b220d2f7ea6a9430ea959aa1c1c51973f8f388614b6d20287184f57e5947f67d780f8d6bb7f24ffc143311061b3d7174b23a	1	0	\\x000000010000000000800003d762acbfc670aa892ada7b1511ae5cbb5972276eede75c1798d03501d50db01d64659f5589b438666f89c81609622e5d623cf1e61f0c93084ca360aa48ef1a4460ae785e6c6ee29c2e63ef81a3d69b8e75f4d1400dee2e632d8de391a9c7dc9479d244f6ae3cac78dd82bc39fb4615fb470ab724cb9c34237a648bb34decd183010001	\\x1ef75c9202a21dc9a7c6bece413eac18d162f5de9939be442659329e18ef784cb189a05e9a017320333645f928b2837f1921d549a8cd776d302b63f260492907	1677402557000000	1678007357000000	1741079357000000	1835687357000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
317	\\x00e7f96fddcfed206ccef994e38f5dc24ef59de60ff0ceee712e758b1786bebc7c60da73ea3096884d66a3a84cd90188026e46b4e9f1339832d4264ed4259cd8	1	0	\\x000000010000000000800003da4e1c16ee721b88cb9f471a22527642987e7f8b97332e1d356c654fa6d2fa3316155a26d40fed3721d60765f8a9cb0511e230c0ada8a304f7a0b4e8bc258ade2e5e2131d13a793a7067a1a30f5770ba5012f31182dc60f8367cb911855e68d1d1a867756ba261e4317eed05b66a0c429dbb84d8b653ecab8f235559d008f577010001	\\x3623d48328f295d8920b1b1c9398489e1b851353a2dfc3371e9f8f877abe6f76213b243f12ef775995019183d26e653eccb720638bf0ff5fe18807de1f14f203	1685865557000000	1686470357000000	1749542357000000	1844150357000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
318	\\x01bbcff8ca374cf069cc26d034daf989ab715cab2bc05ae8dd75260866a2581a957c163406c9f66739f8fc72b5c93315dac622d01a5239b6b0bf9d8d06cb432c	1	0	\\x000000010000000000800003beebd794c049a1c583546ecd25dd392fd73864b83b30fb9443faef34f58f11d97bdb9129c7d1366a0a453c5223a4f1ce0145814cf567d0779e53697a12ba3437cd9b1a5660af9d36c32c32466c8d64af23277dac0ffa4ed1a8c79fc4322e07da6b861b8603dd6296db61758f6a899d374ad906fe8e9aa40a56c8f1b6fa1e8345010001	\\xeb21d43141d8c470c1c8c6265817081125e9c8d4f461f4b026a5de65b3ad9475cd74d26cc8c7a4af8280c02904495c941796c1a21899ea6d50a99eae80fca00b	1673775557000000	1674380357000000	1737452357000000	1832060357000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
319	\\x086ff9d1a872ec79a822aa77c50be6d143ad5315cbd79bb9a7dd4ee3b14b435b4667a1a8a0a5f62d9ea95edd33ffc8b933a4e08b8aba8cb693ea1aa7e057f527	1	0	\\x000000010000000000800003f9c7510d1964555be15d2b2700b3875ebc271ab1210bb709c16d7cdd046610de584b472ab54e36276066896fa30a2e691bcff77fd62deaeddd375753679c6c2cca5c17bf17ee7669fdae58bac4f503d174067bca486d9696cc146c2e8cf81c317dcf2daec91571ddf637b56e821039d7ad88a5097e7704892760af3af606ec7b010001	\\x11d6537829b79c4ff76c5df3bc115bb05efb5527ae00ca4c2813d3fdcbd8dea7e091b8a72e0b4f1b668fa7383b4f976c866b3082307d68bb8e4ab8a15381050a	1661081057000000	1661685857000000	1724757857000000	1819365857000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
320	\\x0b07b1e397a338ed4e0a3ceabb2e57fbcda86f0230e0ed0d00aff11178985627fa16e7bfb4e0dade41a1d57834617f25f8a9547b9a401010c5b62ecec5059491	1	0	\\x000000010000000000800003bf58918a2ab153f4af7835e7ba9473e198dd34b12c1dab48073727c8f4a416c74a12d6d0ade6e8f7b628688c7e867022d0f07f85d3e719ec0234e506c66b96a4d3e95753dbf17f622ec1f36f03bfc247ac1cfd0b963f10fb9645036e233d611b81270c05499a7a4f7a8e3330eddf40701d167e1e91d4ce276d6dd79f72af43d9010001	\\x7fe9d4ab59f4699d40e988a536d4b1df29068f39986900d68848d0e1266e6a5d0c29a42188ffb384c93f122ae7de61631b08109f2032b450a105d86c19963a05	1658663057000000	1659267857000000	1722339857000000	1816947857000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
321	\\x0ba3159a6da0febddc9eb6b9dd3dcc727ebbe55193766edaba55e50b0e56dcbaf00ad26776ec32076fe98e7b2da6b38201f30272c2e3d2209a25ffe41f2a6826	1	0	\\x000000010000000000800003b3e2674c569942cb46c0c6e28cd4791712c82162ac56a71259040c71b93e6630cc91e2b147d8990e2c7f5d8dae484f69c9f220540f74836e76f4b75ea4c6d17f696882dd55d89ed7977c96f1e520e7bc9f246bc9fcc51f262e98791aed7f61ad2161664862ac44259a5f0d4313dc21232a046c44f7d8acef68099cbe960b0f9d010001	\\x1f91f76edf5f9dd27d7a365ab020989cafb8143baf13676ba51a29290f677857928bbebbeccd3122a45a280f70a7fd91f49492c482d0ddc7c3b80851338ffc0a	1664708057000000	1665312857000000	1728384857000000	1822992857000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
322	\\x0e0b917746af8f495db10e0b6bd9dab87a2f5d0942f1aebd2bf034f3fcfd887b02bc733e480460c45596b48f3806e6fa9ff2a81a529eee9824864f9724c39814	1	0	\\x0000000100000000008000039c8a3a3ea98ec06cb6ad0c3e281a6a4ce6f718bdeef62321cde6642c16b4185a26748abddf217bfb10165dc9d2c81a992752ca70485f0ca953ba927a63fd4d9f37e4fc75d5c79469df0c49e1b8a1150dce91bfb3c44ab308a23dcecc1eabc8e0dfcdc425c914e791643a7c09dccc4b08afae64b3551cea775647b5b589daf62d010001	\\x41f95c1ad915f6e3fc45e5b1ac3784f5a2181a310aa042cfd87862d36c4df74457c740e944e2a698e381a15cbde2b25d18284a1c297c9a2db935a3b24bc37c06	1665917057000000	1666521857000000	1729593857000000	1824201857000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
323	\\x101b458a6a464d6c2dc0b272ebd7b16e5fd5efc02aeb2bbab19ead3ed26b86d4e16c1158c49e2a7cc57be5d335ce34ad4f91d92fb3be0d181fb45039605e28a4	1	0	\\x000000010000000000800003a7e579221f62cea478cd7d39c04edfe900a2f4527d784db010ff9c6a9ad78dfedf956d5fce8c9dc2d5b3ce15e5a819b06f0e9dab1db00840135aa3a18ea9fc55f9356ef64f6c26cbb1ca641f2464d1e87ef7c3e221abb201ed8d9edc1cccb2bcf6525255177f9537794a97f4acc5a977c56a98269dab46017f95dcab783b17a3010001	\\x8436048146b80226b0a0e2d6a7132ebe1aff8d76623be63f085e84095a64f95cb7fca16952f98849f9c95ab7246aa223bac81fd000d2b35b4065983b53b67709	1679820557000000	1680425357000000	1743497357000000	1838105357000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
324	\\x12fbbd49a65c85739264570a5f401fb3ed5f67b6b547e7e62688c0ae626108f76865a404004eb39f1729a225f0cb026b96466992304abc197e80889811185878	1	0	\\x000000010000000000800003d12adf5029b37a6d81715ed49e9581b63bfedbda86679d0abcf9b600c28cb930bfa41e6f6601ae991f4b03c29a2d36fd72f61779154408923edca48f62a345d3311596a57c927232296d832175a90ed1cca17212696bc0434a1e133c5ad197c80e5060ff32efc507cbeb65d47cfb5b64335167fa9eb1fd0396707ca1de55e9a9010001	\\x97c46c6be4b5f8db215585a6b0444ef0ee8c8d95869da6731264ae6bd49908d642fd15e6dd67c6fb3649ea6183e9a9855fef258a02bd69707b8ee0a385219408	1667730557000000	1668335357000000	1731407357000000	1826015357000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
325	\\x12fbdf0a54dcaeabca541345c3cc15165c85d50057a0ae0abaeb627dfaf2df945e70ee169c6f40dfcd76773f677570abcbfc327d6c8e3960da44b128225cd258	1	0	\\x000000010000000000800003c4ed1c7c8654609e3d00d046ca1e957537029adeb92e9f73edd2e5d2af79846d29caa9e3c359b2b7c3b1e31989b9d74fe448f03ac8a5fd7d21244b7c06dd16c2481336f5d155c98dd60989ff6c1c3707a09d161750dc3a4253f2479ac06c8697799acc46a3fd9777edeadb0e7e9ca65d203fa8f78c3d17fcb943b4bb2e95c99f010001	\\x7df4b69db67ecd58dd7d6e6b5f4b12f27daec479a4a55d3650edd285f03593f2404dcb2666e8b7b668bf254e4f744c69e30ff7f8055171078c7b351d2823430c	1656849557000000	1657454357000000	1720526357000000	1815134357000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
326	\\x14d3bcdd6f03ebc5ba60f4e3e194a80b184cfa84518e716a32c044214fa63de17a8534b507b638705df02b80d815de8ab08e63e0686856e2cf2186257f4cfb4b	1	0	\\x000000010000000000800003af5dbe16f0818785ceb7d4e3d210aa1692b6c1df274468335602758fc4be5abff983249ea62449d6770c39908bfd031e0c85e42bb9d260511fba23b056be5a3da6d58825628e153d1b4e83223b864be844247566a84a5bae661c361e409cbc9336b2b8efe9804ad142a926be86b7e7a20bdeec992cfbfd6eba1ed894fbd10be7010001	\\xdea742f95cc16d5325bec8a9bb13cd4c8f6acc9ba222b2feaf70f6534e6254665dae4b2a87e2308e01c1105b06c314312084e761ed5a0b127e53ce87da62b501	1674984557000000	1675589357000000	1738661357000000	1833269357000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
327	\\x15e7ba664824a81f2fa32de89896e694551ea8cdb43ec7aa7b8ef685485ce7ea9687d519df06c2e77e8777dafca2c2bb268ccca8bff6206e479aedc0f160a4d5	1	0	\\x000000010000000000800003a65bc77a3a3b3354166d519d56b748ef7fc44fcccf9f4be3c3fb07b6689834ec199fa390712832be8ac0c5bf9c7bf9a86ff1f7126ed4572b8d1d8b842206d3b1e17b9d2323448b0424c926193159009a84b37589bbf128d4127ac96306b886216c9015883ec637deb85c34155256306224cfbf33fd4ed7c6cd3847183ef1f2c7010001	\\x65214e3603e5b615174093f570ce67f1a12129c51fc70406c64971c4ed570a318bc3151d11e1037c12edf375b1bd07d0e435c208e04d71c8b07f9d4b90cbd10f	1670753057000000	1671357857000000	1734429857000000	1829037857000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
328	\\x16b75fcbc23ee0f48d27b4cfe63e9bf40d8ee45c0389a0e4772bdad5a7b2ed70ab4993fc35a4d25adc242cefe99520d34877ebcb83e798d8ce4d76f2a1208179	1	0	\\x000000010000000000800003dacbc636fca43ba08b7f81bc2a03d674513c000e79a390667373f181325d871d2a560d4974be1d2d4112f47229e481a0d66148703d0d2c94de1a6d2e3601d4c965ca05eb9dd03756b6be963a35a9e94ea4875f87d7fed93509de93bd0284d08e32bfcb64aa1792adef36e1d1b096a2d594e43c30aea08865f344c816407978c9010001	\\xf8327655f2cf16f66a4979b1bc2915bdd1af8bae58a1e12173b7bfa67beea548eadfb68cde6134eded5e9730b51334208ed9a3e33f10b89b2039f308313deb0c	1667730557000000	1668335357000000	1731407357000000	1826015357000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
329	\\x197323d1827d40dbf83cbdce3a526316e0eca9a6bea43a13e8c0471a2de3c6da82b7db8467fc80d3525586caa61952c61d739638bb0dd5644b4b9abf0e207f6a	1	0	\\x000000010000000000800003c09d9dc3929a65bb03fe04851c26d84bd36ad683b4d851dfadbf0e43ba67a3e2ad4b9c4df5c7cf3715643d0f23fcc2659607d2cdf15fc0ef81ec62a8cff06ded1abd90e1ed982a5a3a284a25b80351c918d9f5d608b4197352377313f8d327df91117700b1e304c279722e253501514890afa98698897e7c674e9cdf8447f679010001	\\x326346cae605f660e96658175ef0c3feba9164e644b08227209a9e2a09ecbb5b7e015138d1ce2a695819045687854f02461ef7fda57703ce8c51cd21806df809	1675589057000000	1676193857000000	1739265857000000	1833873857000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
330	\\x1ab3095e48fb9c0133a84cc326fcb9cf25c72c3cf334eca66a070728e36f0ed30975e43954843270375ff4c480393e55dfcc98173c5365d04a9dca3d7d9b59e6	1	0	\\x000000010000000000800003b9798d4a52e1ab1162d827a486706e22906882d76bb2aa7f19dde3ba1d18873985b76865b9f8be91d03533493456dc62bcdecf67465a995a4e91eb25006a8e7eb4febc7577121eba0d977193d034332d3a94be36d9d9ef4ac3a11ddf6ac0b277abac777a263cd8489a376156d3a8ff5be980d9cfec5248717f9756bf5deafb53010001	\\x9e754a24ae42a767021b4b38c60e8057943e11ac01c6cd0bf3b7f26d24c9e01a9ef7dc90d8d6b3738d88d7828c0f039c3342701fe42ca2048030c1efc12d2c06	1660476557000000	1661081357000000	1724153357000000	1818761357000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
331	\\x1cc78f178d0daebd4405dd52193b8bae8db64bfaeb95d2c7b66fd0809c05bd0ae5a2613adc9c5758a36e234812343952fc18373b4e5b2a5127ab3dd2bb98347e	1	0	\\x000000010000000000800003d17150dc00464ce218814add51962f8fd7b74a971a1b25e60d4935c74ec9a3bee451a97eee850fc1d603568d2b5ca2e955ca221b0d535d4111fb6fabd5a44f41f1a52fc3ea34e5da699686c2efdfe00e2b77eb4e8705f3fed6ce37975381f46479317ce063e033b6365e078fdd8c208e6f71799eea3df023fcabcffaa7ee2e7f010001	\\xcb751f139fb909332563f6cc92bbd07259b4686e938f5531d735cf367ad6af4844af9a74d1cf03727c9473bfe783169657d4667b5a7f00a5d854375a89d4cf08	1656245057000000	1656849857000000	1719921857000000	1814529857000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
332	\\x1e83551cb94a08673ae144021e818d0d8e77b4d6e00c0f33b7f7a63209283f3f1912b78a1503eb5cd445f683f4d8a5bad810a546a174803fff8127ade1f927c2	1	0	\\x000000010000000000800003c7e78669855509f305a4758ef94a8952a959221e52e8e46a17eb04763fa22babe297b1f177184df7b2ecd4964c712ed71330af1492e4c490d3770dff4f4735915bd664d4ae5794352e97965982e5d8fe6b937a2f20e6c37e56531d9fa96a01037e847b09c75a3845eae2c780202e0b89ace4d580f7209a5db387e8de900b9f63010001	\\x669441709ad5fedb6e60647fc0bbb2b74f52deddef3d0e1a7d95aec11218f899b1df990134cbe795b050c1c6ee4858b771c4ca4b52eb09292613a6d3155c6302	1674984557000000	1675589357000000	1738661357000000	1833269357000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
333	\\x1e3baf8bdebe87e63d3c90d34aa8ade173f7d49681d4e9639b2a11dded6bf3775867b6d3a8562e9e78ea0a9ae63f6d795e7d51709e2e307755c1b74ce4f95a97	1	0	\\x000000010000000000800003f5659dfec4e23389a680068830951b129a7ed6d45341443bcb3e46fab4b9f7ea1bb3dfdeef44d4ec2640abec6879befcc18e797e2290dae63ccb2338e858318ccd1836999158c09735800710882d24dd72f4142069f19036407988eb06b56bb32541f220a3c8474111091c677735b4926f59d77c6aa4c73f3e2dacfd0e808b3d010001	\\x91aed150b1fa53de80ccc16cadb42623de5372974291806060234954be6ac68f80ec12611be5ecb5d4c0d49bfd9f1b0010a8e625725ab75e009a179854c8a108	1655640557000000	1656245357000000	1719317357000000	1813925357000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
334	\\x2293b4c3d57822179949bf2d9d480dcbb1599293bf4daba7def9e9f1477e4b0d32a5182e19d0d2936e81704d549b5998e3a823d1f2e020b494725084df82aefe	1	0	\\x000000010000000000800003b2d4d48a5283dd44bf8e6443215f7718222b2ba39ea6ccc57a6a3bd983c71e13c31a2043b18aa88cbf1106db816ddec958c41d0fbceaae5829a70de99a27e81a58560f29c2a92b3e66f4ea065edae3c10e013cc980ae5627214d2eef4a113d4b573bc0996b3dfac844a72f1d14152d68b785aa62b1bda6e209e4177ab8c489e3010001	\\x16a2d5c3b526f4a63adf08ea53796f1ab9c6aa9c5a99ceb82cae7c2f3cd8a627ce6f3f737c0015cb00a3fb38b043d50d68d4faae547d217eb7b783284d0f6e05	1676798057000000	1677402857000000	1740474857000000	1835082857000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
335	\\x24ebc3bcc1404165bc8ca40aabf98c144c5ec257968b8ef4d55aed9d01ae1eef5b4784adcbef7cb7bc98e48c9010a5280096f54f55f30c3778351b9044566586	1	0	\\x000000010000000000800003e62f072d3ce8fcbb4b4a45d1a602ad218a4f281ce9535ed058f2d580724dd173d6a704166512da18a997aeff93189e56ac6e1875032626c93a9ca7992cdb4a46860f03b83576ad9bf354833dc5c2a9f584b9cc6f1e1cf295fb99d4f55d4ce82461dc828beb9899f015c8eb122b452d3a7da16fe796db998dba97c985ba8a3745010001	\\xaa5f4fe22c6a637352aa2a231eec21bcb176bbe7d8bd0c7ba1129dff7776d7442bb9d21be2053f4b3ce4e8c0657e11241a2b315e48c95f7cb630d4c534e72a00	1679820557000000	1680425357000000	1743497357000000	1838105357000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
336	\\x26a32305ae0e81223325e5a683d67b79ff4d08ed5dc6ea9c473cedf8a05077a8e55a08aa9bce7c5f75520338cb671ac1d630d28b51e0b341ed8a3d944aeddbdb	1	0	\\x000000010000000000800003d86690852c8e1cf1d7e0ff4e68acef0db4b3f13bd3f65020743121764f1efb463a24308c9f7d7d9633c6d756a35565f0fcfc56820335c382ef6d14fb214d3ff8a05897566aedf9e374525e0f21132d94d53ff6c2234a20bc1865f9d5ea7f0c60668b3ed65e9a980496ce08cf620ba39a9a0b555224e290e05d6b58cad983a52b010001	\\x75ad8293d4a2e0ffed9f3ddae27fc65c028ea9daf21491fe87ea01b5123057a3bf9d435efca13d277ba0385d91d776a1070d1afdd16983325bd28d4b21cd8408	1672566557000000	1673171357000000	1736243357000000	1830851357000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
337	\\x270fbf9ad8ec3c175dc91fb8133f69f54616bda639d69f4acaff779d8f1c7c178839288d0b49301d0fbfb001fa2985a91ae0ad3fbe6ace69943b7613981763ef	1	0	\\x000000010000000000800003c3b83445c707408fe6ba21ef2b71bf58ebeaa284b9fb623ea1fe3f2333338c6d59d99da32e50541a1a10f8f491144b9c10341ffd2e68296321c0b0625cf38939f8c0a17ed5d4e917938c0a227fb66ccbdcfc073ebb0be8df9902f28ed90f671848c1dd1aacafd3a885363bd9dba27c85cef1fe9772d1fd0c7f7274c43acba987010001	\\x0438d6b68149319390baa6e333f6e6e93e9df707a0a76f341438d830ad669134f53e178fcfa4f46cfc96634caafe66b5f6cff4389a0d8ea9766824e9be8c4e01	1658058557000000	1658663357000000	1721735357000000	1816343357000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
338	\\x2cf330f61cb416427762a3cc55f5304e8fb3add3addfee6dea3f324990927b1a05cae6b8a476d498f897f199156632ae756657f7b992109c448d7f4211efed4c	1	0	\\x000000010000000000800003b48c5f76789b04f1b6f16fd108ad1db84608294a61bbbc6b73fbb8a6443a8cd4a1f66c0f5915f3e3fa0316a1d986120df1ef758af0342056bc7d3206350f6781d0a129ecfae99f54701e4b9091ced9465224e2a41c38cb2db613d5be5014ad90db571337f2f43dff50a73c763d20677e1c692876d08559a6f8c71348141d09dd010001	\\xe7bf65ea9eec37731a1be8135378be878842a44c774608b8165c39979d12f35243f4735590bc27973512cf611f23d3886b449cf3bdb58e7f2d9c3a1db8d35700	1668939557000000	1669544357000000	1732616357000000	1827224357000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
339	\\x3aaf1cc484b935889f185f5fb8446d7e244797f34f80877c5cd410aa0f5a9ce816003456910f358fef5ea7f239d12e8b85a103081c2f1321d097ddfdce31a4e3	1	0	\\x000000010000000000800003dcbbdabb6f24d47d6357ec4fc9ce9c3a03921d79b604ea8f0a99c57ff85ba536000847866ad40c3e62dccaeff723afb9306937da735a7567f03589411ab2121a061e5989e2a990931a63c526428dad267df8adce322122a91a8f2b24fc08078b550663477850eb5e61fa91dc234586b1b262d17aba28830b07d626a3c29c912d010001	\\x6a3d87652a91fef65792760f772c71ffa8905ee603e6e303049d6b21ad2f315dd26fabe2474d36fea3650182b416d2f170978f3f89cf17f166d5416d0cb18304	1674380057000000	1674984857000000	1738056857000000	1832664857000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
340	\\x3a3bd244873376d583952e4bc735ef5f33bda30e13dc5759429fcea6128ee7729275f9e523d7810dfec732a81a9a709a6f53e882105b80241aceb4dd54fa72cb	1	0	\\x000000010000000000800003f93affc9d576fd6c4ecca43fdcb27065e268ef1ca63df9ee389993f0062df70fb25ee7becda1e10f2374a87cf62da77f1d9a38ac523dfe8ec74c49115f6c22597481d77f55a6f5ed7011889b20586a388087db87076d5140dcf440448dd72fb39724471e0a78a3a2bf2cfddec7c82b368855a43a1ba31a75ff2f7f91dfd8ea2b010001	\\x155e182a50bbe1023eb5530f0cf51a1bfe0e77cc598052fb993d41f472d465620a96275b0843ecdcd1d74b61a32edf0de9eaf7582e36cbd85cd3c3f2824cb10a	1667730557000000	1668335357000000	1731407357000000	1826015357000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
341	\\x3d3b020c77798aefd18d2c827836a6aea461aa11e8ec7933263819909aaee331a61977f6ad05e9cf08ae09b4a63085300a3d0ab8f3afdd558b482006e3582d15	1	0	\\x000000010000000000800003da5ae67c5765df63352628e870c53ad487e3d0c3ea4dbf9d5f09456784d4c1922bb3cd3a03bde262eba7ba0b5404f2efe49362da742dee3baeb20a51f667582ce127577945f78ccb8da326caabe8e27851cc5e1d1f14523316a440899f633fd872971c54158d17e1946db15f4a9bff39a3516cfe486d513fcf9bd3e571860e2b010001	\\xd70b83b605cc0dd171855c031cdfea54526e2a10d4a8bb4d77e923532d2669237ea62b80432fc55053fdb7a34fbfcf99802d7d8aaae594988409b9c505bc770a	1673171057000000	1673775857000000	1736847857000000	1831455857000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
342	\\x3ee31a9dbb9da77dcf16df1d962f041724d0c881721539309977bcb5d59d04604c5a8030a228500af050fb9cd44b9d37d65f040e0c2d95ff95f697fe7878b947	1	0	\\x000000010000000000800003b4b26f07a0085b6e1cd738e6725d1ac09c9272c9d9cf75eb884897565ce51a1c38b306a4e38626933e5d297072141942567bbdee14aa2b06bf6e9da92191cf4b2bbb53a8262f05cdc1dd756804621ddc684aff92709dbb7c067dc427e571c809ca2d4a179b8bdeab29ab4ea6ee0ea0657a49f02b0c447f2989b07d65208838fd010001	\\xb11e6648a839958f4d0c9ce3d04efa4b36e246802abbb0f76bea0db401c8e3f7c505c8a531533a013f6c11a2d34c0afdcbf11e31b7237bce3abe679430e23206	1684052057000000	1684656857000000	1747728857000000	1842336857000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
343	\\x45ff648c5c50b151d7b88d8faff6a2abf353581e52c0bfcd6a4744b0a4b7098db0b956d6fd9a32e48db5033fec7695cb5a627e93399a07fcf50298e675aa78f3	1	0	\\x0000000100000000008000039cb999762631a986c251fd7514f3f2789a6ae74b6106fdaf944b7c4a739002469c3afa3cebcf997d3bc68483da05c1bafeebc1365a728ad3c2cfba5535762e8c4125eb1442dafb273eeff3ba4e494b77234a71b2ff92724b7502846217af1725edb4a1c7ff68507a52df692cc93171f28d458634078ff712787ce77d09a42d89010001	\\xdb4b6ba00933ef95f3e10e806985a4fe9f6df3bceb5edc369fea3095613f7554d8b919fac79ef19839853ad265d654f434fc5c3292aa51d96f82d0a090cf6d0b	1679820557000000	1680425357000000	1743497357000000	1838105357000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
344	\\x4573a090b824877ac8784baa2938e7250d54e2db461468947ce6be47200072687aafdeac2c250da26ae8fc06c868bb49ad3d4f835b1ae5efccab5b88c4ba98cc	1	0	\\x000000010000000000800003cdd9abe095cf7f5a3cce51685b0e0273895606c936990b0cdb07e43164f3dedd493873854a77301b9dfe6a6c711faf0bdad9077720dea2eb0614ee76a538707b284e48f39abd63c1d19a079d5d9fafb1d0a529bc17b23bb17555f204e83f5271b41721b33453f904d12f3abcfe8aea366ab23d11ce74cac302580224b1a0ac79010001	\\xb8cb059714d0be2f7755cee167be4129e5bc65d77f4e4c5101056b10b187a12a6164cad8e1457e4f3c9f367903bc2d9bfbe63127e1aba605dc109580937eb30b	1665917057000000	1666521857000000	1729593857000000	1824201857000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
345	\\x49bb586530b74600443157f7a6d565cb9101a1bf3186543bfefd77df7737fce1aba2b3066f7dc390a50675a81a00d697281f756c90a6630e8f9c67559a5ccb6e	1	0	\\x000000010000000000800003af2b9e15db63a8dd9d469fdbc7b931c30a952169df97dd94bb3836bf4087ed2d076a3939d3e0e880c3388c324ea641849048056f7442a16c1b4204a1b8db745e242f58332ca436e4f5fea1d0bfbcf8d03aed6436431b7c749b9ecfd60c2101020e684b473262d3d21ee7c1f1ceb1787d06bf5bd03d441a6d01f0524b14038067010001	\\x23ab6f5a472b731125358c1c8e925c088a0d2ef7a445b108b007abcb670a137544ca93983f95af674f51cb89d5ab1cf6eeaf8710816949a2951338ed17871206	1664103557000000	1664708357000000	1727780357000000	1822388357000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
346	\\x505762bac350086a210b515e439db36ec856e1ecd3d7f027f27a018315c4baa44faa7c0da40816c3de1e0b900f2f54bba2f63ec746f2307b96a063a363563cac	1	0	\\x000000010000000000800003b7d15e480158101deec3074488cf590074aaa0d32ae62e2edbd19683ea0af6a73854937eb2c4beb86a553812cf227367bfaa77330ba404b348ab6185c7f5bb02be9086af766142d3214da4437ebb50699b79435f4134d2b56afccd5df28cdc0a4c104551ad915cf327ff9a97cbcf6435d4384001c86b048cff2fa08340b7a3f3010001	\\x17a50478b470485b529d78c3fcfd088e93c075643ea562207cc55f70e27daca90b8481d294f60ef3aa7c05f86bbc53527754ade342d23947eb827fe0d7bd8802	1667730557000000	1668335357000000	1731407357000000	1826015357000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
347	\\x52ffff1227775f193282f1004074939755e5285b060800b8c1abcd42292caa746be22cb35556068840b66f867a3046c0ba3ae754a2d244f71bb78455197ea045	1	0	\\x000000010000000000800003d46defa79074da8ff2daf99af9571c981ad2d8e0a7feafef350c939592ccdc403b280f2a88a503c64804cbf3428200d0bf6bc174c600adc9f3db14be7bc01a79e744d66b727a9b297a831c8cd27b83c470d26195090bb8bcb8e5fc44158d1a840c19c87b75655ab70d32302c737dd04e5dd805c3fab46a4d2f15cb8d36ba4d13010001	\\xd4c566e624a8d6721b1ba263bec57f32c8294d55f69078e2dce87f3b3e43fa836b39c6da39dfd0fbf6a1d26aa2cde7b1055934ac94f07310bc70213dd0c07305	1679216057000000	1679820857000000	1742892857000000	1837500857000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
348	\\x527bd876dce3a145846fef8c6b8245f9cea64c3753c58d84c6e61d0490acbcb5a92869192abaf3e4b18a2e5012831396f9c5d5fdd28c6fecf512233497280e06	1	0	\\x000000010000000000800003b77b325569b21a3de57e9b55e9f7278943cf97e643d1ad5889594cb3736f9b3bdf5279252276b1a872170453f5ec8e453147011668066279c9dfda7170eae436126c5703fa7c5547cfbed6d121f0b5f6ed499fa87456191260cac3223133382d0b12847b2befc6f42ca2c37c334f3f46b030b445cb289ef19a0e50bcb95bb5f3010001	\\x046bb55acd58a87f896b198b36e9d9f675b92340b41f8e7966641b1f74212331ea349dadd906a8e4d8d56147ca90afc8e3e60f2da6711d6ba01d9392d323e003	1683447557000000	1684052357000000	1747124357000000	1841732357000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
349	\\x56333e2f39c20877180a40338f500deb1363e94e551868da6c69a75f1e3c3184b96ca62777812f47b2d511528aad128ddf94bec4a430d8cc65c148e5f6636ce5	1	0	\\x000000010000000000800003a93648b0e1019d42e1d2f7cbdef3db6ea5b409148a7b6c9dab8ea55ef8b5cefd1a2e3ba398207a65fef935e3d7b6a920072b9c6a49773602cd72af314f11e033d0e08f9daaab65495ae65235ef3ade140f7eae124d0fa1d890cc9bb2e4e47765b09a19b1b2b7488a8ba312dfc891c6b295751a336bdf50803117157bc77c9e13010001	\\x57a364eefcb9bba3b2922be8b82f18b67a0b90e4a1462c27e46d2b39f43934c19384f6f529aac9fb8c6c15812e86ff0fc5a423d05465d03f61c4dbf6b640a10a	1668939557000000	1669544357000000	1732616357000000	1827224357000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
350	\\x57bf774685b0229e6904c295aa7ee1a22952bad686cc484a1a04d6c016a7a93a96b0f09f6324b0b52dc2c4743ef430c6f5012472815d4eed7e85612dc6f8d821	1	0	\\x000000010000000000800003f2202bd1ab3076633af19cdd9a8857b1061815581609cb87de1545277071219778eda6e2392a2c1b83b752febef3768247683184dfc089219bf0c60d4cb5cae83fe25929135eaec75bd0a40fa5e1afcc3e5711a4d99bc85ba00b57997503fb05da0cb90236f385260a04b32aa9478cc1aadef68b9a3cd04171adaf51cadcd20b010001	\\x9679635610201652b955e1d5e04710678b2496a1f81439ca186d827d63128c2e691f8c8d8448e5639710f818d7569cca500148725e282253182298a04bbee103	1660476557000000	1661081357000000	1724153357000000	1818761357000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
351	\\x583b423abb69b990f3814c820d4fb6664598e62f7c6cebe94f86fe6582ca874f70571c55d13242608c0fd6f4739999da3aa267e2d2f5c4094453b0cbffd6acbf	1	0	\\x000000010000000000800003b355b58893cd47a96a52b8a9c41000f7ea833ab58afa5c689c402d97e2052281dfa1aba902f7abdf193426a6075322df5510ae42f67c3b8670a6b62b3e7d15804ad319558d7ad4543cc0c374220e95d357d24ba6ecd47606942942a7362da241a536adecdb5fb132d082be638147f34874303039ce024041b22c82e53df16997010001	\\x9221718c94816247bf161494576c7b82c8640f049fe15c74d22f1360e7a826017c84bf3e7014b9e83e634fb694a9aede8bed35c2c56a0484a7d32dd04c3ee803	1679216057000000	1679820857000000	1742892857000000	1837500857000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
352	\\x5a076ae028ec514606c44fa6a89c85b6a82fda5f4f0cfd9183c1a0b7cd53c4c93d1cff3df40f34cb24ca537db2df3ced17e9865c402d02c23c160e0533c40d51	1	0	\\x000000010000000000800003c24b6a25a92bda54e08657a9dfb83221229e7d38f38fbdcdb16c33c4bd4744b19bbb3648fa29876f127f0b1e6ae4ca339c2553467fa3845012c52bfb0c13a2f44729d9c4c688fcac32d6bec8cb467a142761d5b87f586be40546d8384e9cd86b7443f61c130e2161c09401593a93d679b228996e7d446e70c2313c5c46fa461d010001	\\xe4b1b12d106c89ae8a28b6e90bbc534250e151fe936de468a42ae238e3d06563ed9d0a5142f77f57e1cef9af963921ff2a111fd245682236d64600f3ba1e2d01	1665312557000000	1665917357000000	1728989357000000	1823597357000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
353	\\x5bc74f025520311f7189f9018d8e3236f1a486fcfe43c22d68d6503deb65d6c916ec65d2d361fb7e0453190ca8e0fb8105343ac83d4369f70c603ef0010704b1	1	0	\\x000000010000000000800003b68a117cd74a17fbb5ecd131b14e48c8a7ea279ff93e5c67ca381dd423e6bf33b878f0b37ecaceaabcd4073b24184817c2d97d86d04a28a76c18bafcc10e8bdc5c676627d96eba485105d58b8ec0f23a2295ad16c1ebcd369e28b266caf91d31e5424d9198ba182895eadeca15e9879fac67a5bf4c867a2d2f61201661cec5ef010001	\\x8106bbfcc6322e4df1312b69d7977319ac7a19472518dc08511385b2c98220962a2ed5887494cdcc617ffc0bdd0e560db3a259e020429563446d4cac46b7780b	1673171057000000	1673775857000000	1736847857000000	1831455857000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
354	\\x5c3b4cfcc91a200e8a1a651b2f07e55a9aa9b122673b03a4449cce6d5dff7d0bed0ccd8fdbedc76f0f535d1a45a125476833414a53d3d90c808ca8d2d0ab2276	1	0	\\x000000010000000000800003ccc4013425065ed822eb0537d48099c4334e478786f1e4b8f6f92fe9279e615db7a63d77e7c2e778cc42ecbd9e34b631ca5633f9a2f2deb8207af348d283d2b3fa67b458d0251411bcd023fb47bfbcc41d43c166928a818f01f52fc651c504aa77203821a2f57a1b588a05b5737a120765baa7edae386ea57d4961fb5c1e7d51010001	\\xd85ae64cc1cbedb9fc8ff8dff886b3bd6d4c6a37d16aece4873ca82499ea7ab860b362c13d6a5ec98174a053a8c8114cbf58b84556e3be5f9f77af63c0283603	1661081057000000	1661685857000000	1724757857000000	1819365857000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
355	\\x63e3bf64cc15d81f976a00edbf7e43184c0e33ced5ae5f69adf4bd84dfbc741090000cef93a71e7857a8c32c572470b07c3108e11b11e23dcce59de447fa7550	1	0	\\x000000010000000000800003c63a27dccc12dc2bb06ef8c6888921ba520e81a382ad167c986b5142c92b5d97f031043dca5196f6248fcce905afdaa1692cff6ee895fa5be88bde9a44306cda200a843b97c21c06238f6765c47409fe0f4b8f32383e5b81fa3fc7caf8c3185b862f98d6166668760bb246715db3231ae6f5dfc77e57377f348efde1de723389010001	\\x20976f9a3ccd28949b86edf667a42c943264bf9438cc8c1fb233d456c7d3b72c7c7a495a0e719cec58f1ffa1d5728ef41b6ce7e47917d0751e70d7b6dd3ae605	1687074557000000	1687679357000000	1750751357000000	1845359357000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
356	\\x649b420c34a250dfd820537a9d1c8ad5987e53983eb5b6942b56f94a4a6d3f6aefd7b173561170a6c76d578ae49726e531ad578bb7332daccd34c0002523f1cc	1	0	\\x000000010000000000800003c1628763c37468b05263778e283ed2cb6ff707a5a36b8c9f3cbbb8e1bd7974f7a48fb3e2fc6b183e97f205aa9bba755432fa572d33cc496cf7415142fc4a526f37b1690bf65095ec712c728dacf8fd896678bcc74ed7a73af90ddfa7af13a14bdd5c9b4a5ebc43d817839b8a8908a0b263a845763c98fb6efbe7846c088abe43010001	\\x1bc08742780ffce0022fb3ebb5db56cc0a107d6ccb717277719c253814d2a65a67325f302b9de70b84fe705a5499b80a98c81367f44ca42d4af28f948100f201	1676193557000000	1676798357000000	1739870357000000	1834478357000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
357	\\x6677f359b77264c7b892f120f323565281175ee45a5561696eaeae3748cf79bbd272c943ea47635300647c9f39ec420627b496ec4ba5179d2e435996b52b2f09	1	0	\\x000000010000000000800003d0152901b8104b2d8f4b0a486a3acdbbff59d85af88a5f0e47a8ac14151df812de203d36c43d279ec9f2469181e7c2157043545e12ce8586c23b0af6d505f3f4d5fe641dc2088e4f14ca2a2340602afa04b19127b2638de55a9735176633f5997bb16332c5eec8243f52d48cdbb230237760cc984612e2f899a91b22f88af9e5010001	\\x5aa3d19a7076e1e70bb6d7eff2ee47bd033a02998c3792cdca921ee72fd1a401072b32196f8fc70157eee3561123129a4ef67c43022736293685a4b962efe005	1685865557000000	1686470357000000	1749542357000000	1844150357000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
358	\\x6613d5613357dd96ef8a7c5cae455198a6e1481572cabde6e5b22f090492450634a95d974db057cbe55f2c1685537cac58bc999b98691c7303c5f83a8451827a	1	0	\\x000000010000000000800003c791e093420d47c495f342d3e4d0bd981658cb7f86c70b711f93d9b4e808ebc39d010f967eb3263efeb8ee896bccf8e2b3f70b41f44cd26ba7ccccd429fc8e459fbc719a3d9b6d7b4ed71d167876adf4d2acf7232deb1e2ed20c028c54dbc598ac6347ce31bbcaf5c7e9a6bcc0424619c4573b8f86cc7451369c5fb6e324b41b010001	\\x15a7a6be20bbbda0bbcdd6fb716e763e3766f16a6176747c902787ec7a164b056334d31a116ba6691f3e0f73b14900621b78d341e44ff381495b8e51124a1404	1665312557000000	1665917357000000	1728989357000000	1823597357000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
359	\\x6e9b07e49b776feb63c51e0846d22f282c2d7884d8f35b267cfa774d41d2212653479f9747a0597b5968db922b5f6bb0eec486f37bd344b3f1d17de138208ff2	1	0	\\x000000010000000000800003b925eac41556bc26d3fdee063784b18db3183ce80b20fd458b5a5e15bbab9c5beb014fa4a88f3d38d6de7e338e59832449b1de1121c8bde1025e85e9537989505208fc393de4f2f92e9f35c83f2988062a750cb5b7ad1ce00b7da2c224c293b7f17b8e688e86365672c634596564a94543ab501aed5fffda9a11449c01cf12ef010001	\\xc41f4dc6b568b3bd4148ed2670df75bd1c56d1365914e405babac06e7d6f131527668db2130683bf81bccb2895d78d8df560e51da4af2753fb6a8a5346485b03	1683447557000000	1684052357000000	1747124357000000	1841732357000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
360	\\x72c7d9a97a38232869cad31b6fdc5a6eda2c616f035da40120897fa0f9ff7a913efda54728c96509a4730133e2c9506c201f8495f655dcf0886036b02987dccf	1	0	\\x000000010000000000800003d7bde7f122f571d88cf7f8814f2ae73a023cb4c9c0102c5625863ea0ea2d60484ce3d0cf50be3bb276ecd10d3d09f4b9b370c1f2de9d671b10c5bd2974ccb8876cf07b42968cfdcbeb562837c5066f6df1aebb1cc6b0ddeed609bd663654ce5f9ae366596818038e39935d7d2d8e1c2539174106f3f4ba22c1499f205fd1f145010001	\\xc1f709a378674c8856eff5436b6e1b0c5263b766417041cb97754392c7169816805ea2a42a3dba079a30807a2601eb5eeb2a8ab0da2a1c81be496a8b7af08809	1674380057000000	1674984857000000	1738056857000000	1832664857000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
361	\\x729f4689b311de76baae4ad5a77096233aa70325186dc721666a608e99fafc9e232bb822fdf6988c69c6b3a5d8f24ede422fb69f1cee233b571be1aa5acda1b3	1	0	\\x000000010000000000800003cd83cea27c308b0cdfb3c4cf06d6d7c59a3427304d0d48c64be27650d17e407aa3fceab2c055442c49f81bd259237b1d5172133a6180575061a5b0fbed2a31c83914cd026aae9e9d711b332bf1e0436083881b2f5c7c21e4ee3b926bf09b214d20491e70b0216533a9b253d7ac9ffd33afad15350cdd79a32007ac117b6f556f010001	\\x2bef4ec2d8f3ffe5164ca86f4c91d9cc297c11552866c81f844d2716513c3b34a9913e622b97e68558c2885dbf3b618027d0505cfc99748c05399f51c2a6710c	1671962057000000	1672566857000000	1735638857000000	1830246857000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
362	\\x727b6ee2934bccfbd97db2cff20e66743344da8c8455d78a403b4ece0ec4ccc8c1c6509e670098cf3965df9a95f9d6b456093abe0f1bbfad6fdf1771b7c023b1	1	0	\\x000000010000000000800003cb8a60ef35c43bdb98c73a0aca0c8e0a60e161b552ae2bbda2e2916117b4dbc768ee4f677dd39a0fc0791fb86a862440c9fc928f0c87a840ea87459e53f7a987d2e7fcc96aa68ad6bc41fda6d72f9ef6266307765da875ba8cebfb8380d516920145f1f21ebdd08e1b93d86fbd30a35dfd9cb463d34187a484d5bd850c88140b010001	\\xfe27080c133b6954ca32e6326221b8d8c346073711c2f8c517fe2fec7b64bb8db77e965ecd5c5074ad329b224b432aa70fc6ee23109d128deb1967b9db20e10d	1661081057000000	1661685857000000	1724757857000000	1819365857000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
363	\\x75e7e124ba102fe129892cb23988b5d54410bc5b2d2cf84c43d92f97f84a6124642cdcc4eabaac78852d294df7abecdba1945a53a67593a4c85d2ba2239bb82a	1	0	\\x000000010000000000800003c493c17995ad7aa8af54f91d7d2e742ced057cd8df72263ace32219e30547a3b962fdd76551c72425f496daf42dafc379444728241a34de94352b1cd34ff81d93fc869fdc0d3afa035db779f32be1dac8a634a492cd1fe944b98520fc0a59e49123b9ad42e1b4a65ecc2727b7b73b2a62cda818083d881e8ba49b9c8bf0e0b2d010001	\\x104a5f55378de4d2741c99bf4957014cc3fce9cb75f1dbbaf2a809a237c85e6278bce1f26838fe0cb031d1d692682dbd98010ffbe71d497a531f02144bc5b40d	1679820557000000	1680425357000000	1743497357000000	1838105357000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
364	\\x7543ee57e4f7905af6e14172a717967620973c7abdbca1132108145fe28fe4248d3552991bf36550f2f124c2c1cd3ed9972e9ddeeb815684da363d3540329706	1	0	\\x000000010000000000800003ca325e8845de89aef557f234f0a3e8122f635cde76b4617127a08d4b70813e5b917914c5b648d3852e35287f426f1dda301ba9f78210aa7d685156c525f80debab7817dee4ce172ee9417762a9f5c9d193e48b0f41b178749af75748bb5137939a1231423d55f118c8c6d303da2fe7979cd6501a93911fa7875d908848bbd555010001	\\x7a9a1d49d55cfa9d6b7d25a810c4095540b9d3dc91e09756acabc18c19b0ee35306c022ae790d556bbefc83510a39e61cafd9f67fcb02867bbabbd43fa1c510f	1658663057000000	1659267857000000	1722339857000000	1816947857000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
365	\\x7cfbb94a3c796b770fd7efd5d6e6732b450b837e188fd43e92d240b6396a243b46d6f17902ff920453e485faab4315ead4f8a8925549cbf748a9b2ca27fa63e4	1	0	\\x000000010000000000800003c81611258f561521d6d146db0579193f942074fc85916cd566f1e90b84412379bc6fd30ddcd7d048b44318033785105f141b1a363acf5cbeb22d51699a7fb59cf5180e9369d50f7cbcbbbe7e0c6f0283626718185dfeb69783ba16d73ff29fdb0d2e46b2e8e0fe5ee88198e511d5ace8634e3acc5c4da184ed7ef815c6fcc1b9010001	\\x0fd8584b120693dc9a4f13f3b87fe97ff2869e846c86fe5652b76f01f9e99e3a9d9bbfaf27e9fbeb6face2a083bdd180876ff25e20e963727da45d42ccf62e07	1682843057000000	1683447857000000	1746519857000000	1841127857000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
366	\\x7c7be7f63cee33d7df37951770e75d95db9a5d3f5f6452ecd679837ef24e955de0d8aa42a6e6ed7c3e2453600987971351820177862888e6cf5e162dc5f20bb7	1	0	\\x000000010000000000800003d8d54d3bd3c678456e0fb894dea4acb5a0e5c7656cf0f97ca65cb55436eef39d2690e81a1f8db4765b081656d5ffef8c4555c87483996581f15f342cd3a9fb48b49307a0fc075487a5c4d7731010ef40bd767c0dbaa17883c2b3b2757929ce7807fa8368d9e1f1ab4339c91ba298b704d0d44a9d990c9b605837ebc9231afb65010001	\\xc0661d1b7cc0ac5818363f6777cba0d20932525c6ff41f6b5faecd24c477278f5fa73781e702d49adc4dc81f05add8c2f7810174e8781ef3f657ce0d9c6a5806	1664103557000000	1664708357000000	1727780357000000	1822388357000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
367	\\x7fbf5425d9eb5c417c6fa05d526be68743f2f0d3ba0501e0e788541bab4791480f68f825c598483c051aec4b54aed237256dfed7b379687bbb3faf04ca1e1d9a	1	0	\\x000000010000000000800003d59db68c0aef4b1fc7fa22a1932a1588dc8ba25f193345dbf8d8f761fc45eec0c3a792cc216ec6fd3f75b97b1697db2f5b5b0caa8fb445aacb0e0310a3bb1ee5a6a0dfb665af1ae88169b67a1c08642ed2e72e8411c42239450014862e3176896c1b5b78e77f09348b96cc4a3b04ce7c61918da0d4185ab8ccb6b178f3aad9f5010001	\\x4c08cace32f27da2600d7e3c2e91a7f533f368842c50cfa6062505e2a3737d4112232cbf86472774639a1091d8ef50834cd5292a12e82bb0ac05ab063725f605	1676193557000000	1676798357000000	1739870357000000	1834478357000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
368	\\x83eb9fca59dc55769dd1cf8404934393dbe5c99a20da71c5368cba283a92cb37a3464362bdf092a59c2c733494129ae27b2fcf54b6b3be506f32dccd4e7db056	1	0	\\x000000010000000000800003c43f09541edeaec9ca4a5f79a8dda1affffe32dbfe8509c6ea825d6ee51724e8f21932f58a09b0ca424251dc006f1b2816ff45c5eccd2943c4d3483b0fca44d59cd499edba514ca7aef2f73733b40cee95e081506bbc756e43e5c3d838859f467efd96d05c2a31f087c10efe8f873d1f826eac63a68be5afa852e7cb7651ea4d010001	\\x094020b04d68cb04cd4da89b39957c2b9da3b5e42e9a1ad659cdd4c97eb1ca16547d8ac66b308311cbc60732bbf9e38923dacef623ae8744cd76d56540d55a08	1671962057000000	1672566857000000	1735638857000000	1830246857000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
369	\\x8797e545afb34d7931311ef2271021f94dd51aa7d5e17654a64a83fe94b2150a0af6c2f500c6e132d101ab1970f3ef8f19685d91e41ae511585d472579f2a43d	1	0	\\x000000010000000000800003b79bcdcf073effdc1f4715d00f1979b95c2a131fa05eac6be5a99ad3405e59976476a95a8c6baa2f1cd5cac226d494b57637a961773545239563a66faa21296b5555d167212fa0323f7a179730bd7b6882675dd003c208dbcf1b59d45611b27a8c6076325530e4d9b5790f56bac38450234d73b5a4fe4f3a09c9f0c52bc5c71f010001	\\xca7702418121a8597ba10881c44bdc627b9ab1c004d359d353897cd5f160a81c0f77ad515909f9ec5a092fc9a3e3d71e86e7d869b1de7fff126fb360ade90405	1666521557000000	1667126357000000	1730198357000000	1824806357000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
370	\\x897f6106bf8e428ca31672c1d783049e3a47c9b1106ed635734f4923a75c55dfdd3a5f5edc80f3834b5617a69c1e6aa58eac5500ebc39bac9d33b6ddedca661c	1	0	\\x000000010000000000800003dbae76ab7082ef282462258e6efaea0ddf728222401af35a22f86cdef237abe1e7f876272e0ed3f650178b1396237d3de841a5d123904b3cb0432fa4797b4d56ad0841f8c07c6332d3e31d8e3fdb38eb3f812cc18e4090879378a41a8f69e50b28660cc60e340e43636de07151082d9a9a782e7713084c6fc982eaec0dc05629010001	\\x81ea9319fb1617081cf224859bc4530a59360b7517e9b233a807f7d6b625a187a30210765eb2243261a1f8ecd80e7981a6c1e3eabe6625e7d3f1c9690631f90d	1683447557000000	1684052357000000	1747124357000000	1841732357000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
371	\\x8c53a1850d9f556f808c5dd4f3d0619a23c6541bceea4e1a8dccdfaead552f8d3b8fe97ccf1ff1df2f381690d0b4dc64db8334b3dc558b07fad3b91c18ac9662	1	0	\\x000000010000000000800003c366ac63ac161150dfda7064395d07da1f048461d26ea04d90eebc2ffc4089e60b9d1ba7466f9b85d864d1e9536f5bac98db5ff57c904f285071fd5429ad61660901ac6fd4f74e65d42716cfdfbe4b8713387ee524bb417ec6408897b9c94d8fb27cc7ed075487795ec2ed6d2b90fa9d571a66077c78a9f916a554f9f81fba93010001	\\x60d04ab4b2a7b9dcb2fff0438cf425f7684e55a44123c451ff5edda0f8679137651bcd1f029a6c0c3f3079dd8fd24a94a5a6061d9e1f7985487b6f87df9a4304	1670148557000000	1670753357000000	1733825357000000	1828433357000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
372	\\x8f9749c097263f7ade8fa20e010365153cc7b6a1f6ef4f4161422e73ca4ee7a440b6d36c5adfa059e98c612b7b9e4d9c98c8769c0a8ec1960a3bcc808fbb231d	1	0	\\x000000010000000000800003e6ee5988de371101809b950bf7b69eea42dcab672d48b35d8c9d2aed309dac268a9e2bbdac29f65527e8ca7f76341d7b063a36ee02acbe4e1d91603ca96b90e04222f5017eef6f33db9ab37e50d6690183b92c108e2b45c1cf9538d00ebc37d3506de751ee6321824b42ec34de5abd321ff72119d688cfc65be52bc82d4ca411010001	\\xb92af7a1a56744346d1ee580e35a49819ee4a6bec8b5073b21e8c58cf5ab904c5b869547cd436fa52f84e1382b561fa3eb0fa0f34a0d2f7c88e945ccb0ba6a04	1674984557000000	1675589357000000	1738661357000000	1833269357000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
373	\\x97272a7f0b6a7514eb6d95d4e44f9c8f00e71082e7d7837a20e3158e5d872580c57435bc6493b869ed2910ae8478f924d87ca54b0509193155598010263bfa00	1	0	\\x000000010000000000800003e0a99516fcb5f69de428d25eaed35d2c79711a6f853f93b11555677bccdde696e91081edbdf003458e9c38a797aeb9d0dc3a87ce187d7bd97c7fd7f8f7b69e8ea3d2f0f8695ebd543d2aa4838cc11c1db355db0d8142267aea7c3c599df7d4a3e9cd1ac485dc77c9fe2b126e22ce9e3997ea69bf08b0efd8cef0e302abb6d9ff010001	\\x91a1abca337c33362d6456e3d6a0d79f82cac672224407d77287108a5f9095bb8f631b84743b37dc0d44a6600ea3ffc9d3cad2a03ac54be18cc39a585df8a40a	1680425057000000	1681029857000000	1744101857000000	1838709857000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
374	\\x98a7587080680e9fa498fb8ef612f8c2de1894de638ad678ecfec7d910c07f51f169a4c5de0e236b180b8116bfb4248c3ea37ea21add1367d7c352c8fa7f1a17	1	0	\\x000000010000000000800003b1f8dae8fa75f8f335e3e39107789bccfb83a0f1523fed906b15810d6bd005379a0a1b6353cd5106da29badb7bb46d88ccd4bd5d9f7a40b8d6e9fde4e659b8dbce0f17f18398cc60a688ebc07b5c6fb91ca9097db4ad129739dff5d02365c54d6c01019457aaf3206ca66bf362909c5a8c51317748745621b2854a885ce09f9f010001	\\xdc156afe2debb18b073b69e6f3d77fcdf22ebe5282e04dc434c6b1f5ef596e895bf2f78ddca762f4520c770becde44f3c0ace89a50849ae37a643bcd13ec410e	1661081057000000	1661685857000000	1724757857000000	1819365857000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
375	\\x98c75608231f9d805bac7cd5a089c213f22e583609a6dc09bee7b67ea3fee3ee1748d81938d4eb80301d09276ca5143bb92ef2117a75a0b5f0eda86ec3f4d9c6	1	0	\\x000000010000000000800003d3dc2db2499725e25f278cb7c8115e28aacd48487009ba036f0c3e2f0340622623b9733375f9b8578aa7daaf6ccb0d182d07eea1288602c41e43480c061e15c98e6402d0f5922c43684dd74775d983e967f50307fecf8170ec7ee77b6a874e9fe3b87f7e0d8c72e0a91482476cfd700c6fa822e927a0673532eb7f06a70dc951010001	\\xc321a3267fc23be7203dcbcfb764e7250f31d601a2c5250445c93c8c58ae913866898a611963b1b82fbab81cf5b2e839fa358d1df70652bfe7911c50c56d5b0a	1656245057000000	1656849857000000	1719921857000000	1814529857000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
376	\\x9aeff5b7f0eaa78d4e10ddb7d4497519ef766a13f756047c4456c11c8519ae19731c2622eaf9124245596c4c34335b0f4119b4862b46c051fcd3d86acfd8dfdb	1	0	\\x0000000100000000008000039f04e9b21ab10b4fc12487fdb732c0be12beaf2ef0bfd1d061fc06588031f627b514d256f750d4cf12ce4f4957988cda71154b58b620c24a01ce9b61716751d124fbad20cd58e4ca48abb6c0686c3ef64a99e58874ee4ea658959e4166c3d7cd1013b86148d6312069421098df4f0f1b0f09ccc687ae63c432c931b873636a1b010001	\\x472bf275c6ab25fe0e34b810b8eeea331d4b41a3c8c1b195f1f25a5344ef58cbb9bb8c0a9b1fab6b67271252279e3f52eb9e7d28b6297deb29942f5b8a5fed01	1663499057000000	1664103857000000	1727175857000000	1821783857000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
377	\\x9c0f4b9dc32f0a5f2510e2e6e2b58a93d8e3148742bdca08beb3ab40b1fbb82fe068e3d2338934cd98348f37802bf348034e25f8f9e3a16a7c9a71d9d3029381	1	0	\\x000000010000000000800003c0aab4557d9ebf22ab78b90cc6b0a5260f902f8cd9523eaacb6f68b782b8c0a8acd08ce5ce815ae2795209cea4242b41d9eec5dacaf54967b59630988f44a1d9c64e54ca1114ac68dafd575e2f4acba94e90751271c16f1e49b30e98848eaf29d1eef6afb58b56b5d72badb7b2000bdee9f8fa6a3c51a40cd91b6d6e27f00ad5010001	\\xd8c6826515ca9b5aff8ec6e17b24ce297ef91eaf1ed17c583a637694ffdbfa1493d4cff0b2534272f7c8eaf28e249b0b17a3906bc7c18ed6ab794840b57de20f	1665312557000000	1665917357000000	1728989357000000	1823597357000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
378	\\x9f0f31f6eaf08c97330bcf5ccb0cb48ecec52c81ec477cc97d0b3f554fb74ba61876b4c0388cc0856720320e5edcc6b70363d86a1f387a2ad1b3844f47ec97a9	1	0	\\x000000010000000000800003c70b95c0b477f1f27ed1d321ba961aa55ea32223fe84dca0fff2160447fee963da57f13e1a2198dce3c9f8cfec45810133a8f40899a2b97528041785f3a271a5d422f98752d83b215585a4de5b5f248aaa3f818caa50d026b2afe19c7a4698e89456bb4c763d37609e9809e80a204362df982f915a17ad6dca213062f2337e13010001	\\x4285a8f8efb104273592d88db2bef0e71455d78ec810e289e4c8be8d9d869ec246539caaefa6b63b8110bfbcc4ef7ca5407988bb2cefe9f5d2e9c8d5630ca20b	1680425057000000	1681029857000000	1744101857000000	1838709857000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
379	\\xa8831e10b9a1635d46977e0e98c08b1c4ff4ab38f124aceb704f5cdef69d9178d5b7f10a2beb1502966dc5c3c1c5650d22c84632bf842d117793333382a79df4	1	0	\\x000000010000000000800003d587244cf2546dbc3161377ebb31e14b3118e35fbaa65b08918b3fd5e259a3bfa4b554b8f7c2eb5f600f23a31dca190a1530b06e2ea4475c6727245712f82abdd8de4c905f0d3ad13df5c7808c7ed5955477da06ceeacc8f0e0b3c63bbf197fd49106b91fd12f63effc91687a19699a1230ddd279218e6e6ea91e97aca945445010001	\\x5f18cad75f532b2ff8bfe28c19f70bbff68c70fb5ac767e7e8544e114edb4d5f40cb1059981ae77bb289a8bf7dd576a2b0f18ed37be7c8e306e519b2b6d06102	1663499057000000	1664103857000000	1727175857000000	1821783857000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
380	\\xac335698036ca743c7c01e74ca7bb3afa3f1f1855a90d5b0ff6df34f92fb81473e87169c28652599ee5e9e24a69e865cef203c0f7068ac1d1a1dc7359b660dab	1	0	\\x000000010000000000800003ec9e8154d090bd2124f08c3121d4db65685e46bf27a812e82ff17de72b156b6e6d920197654c5b405a4b18007f3ddfeb1ad93a647efdb65402bd7a537764b07519dbcc9b0d73a725c94fa972ca68790da78f4ab6f683ed75cb0548a2e680adf3b822bad57d4f5697a3da16f25719fe31881da85783bba6a4413994b1d6b33103010001	\\x125cb8b2e37ed378b0d3a8709d883e90b037f8479c73e87aebe7df6b8ea94a1b758e8da36ddd8b35077d98eb51e459db7d5e45b1e26260eae5472c1b18f0ba06	1676193557000000	1676798357000000	1739870357000000	1834478357000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
381	\\xad532c262394e8bd447b612405e094835f2e541d0173f0ed34b836ce390662006675b88a4266b59c48cbd2377db7ce72f0288bc5f8732f16c09c0f3b9ea66735	1	0	\\x000000010000000000800003c82acb80f84a47b2a2653319767936577f1fc88ba6b368e67383bf4cd917352bd04d91d0c3fb75ac239ea846458c409cd711d78752705d235a61aa65c450f9ebf8adf1a72c8ec8b7cdf5196719c373cf855f35f9583fe873543f385e23cdbb94a8660269dd36a178e0e1a04a7723dd90623b3c419597ede3203a4dc5708c60c7010001	\\xa04f60dd7c97a0126e906abd8ea39d279afffd620f920be553ac54ebe1cad406e93f204083e0c265c7a17ec0b6bd572c34e5636bd51f96910ceb4a682e357807	1681029557000000	1681634357000000	1744706357000000	1839314357000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
382	\\xad53fc7bf8a92608ade67365fa61164e22e057eb8fa33cd790a0a072d199c7166128029c20757eed0b3758b98dfe84ba1084c4db76299d46cb71256e2baaeecb	1	0	\\x000000010000000000800003bd99121cbe07059b0b632d54200d412f742d4aa3d62ce5d05772207a2eee10cb9c3d14f59c21bacab68169992f40318c024cabced90738f404e788c59fe84e2ba1664243b31fea8d1a27603289f2abecea3881c60545a33d2797a27b9393cd59b217cb17a4e8643fff4819a00d7ecd72ac2463c5c4d0db0bef835b3934edb967010001	\\x5c39e6d6fd33f38fecba082afc6f4fcaba0b068e29d4cd1e1b3e37984ffadbb15b7d95fc1c3e1f2e2014903da6c3e76c9000b76529e8714a3b3f5b98d2a44c03	1679820557000000	1680425357000000	1743497357000000	1838105357000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
383	\\xb21f58c2c8ed7faa719a922662336eaa2ab0e8ea16e5de9b778e19fc22305302e56bb2125be184443c4e8bca9edc6618668f27c7a1cb2999ec570dd2c095a44f	1	0	\\x000000010000000000800003c60e4996ed9db3c63e520a8e4b7b17d3b38bcaaad48a8e6cba6db656b211964c9242bf9ca1cf442179cbe4cf95d130e5c47e7d351ccb0b442f150fcce07081e371d85e5a27d11bb0cc70862b4ad4b28f9202ef641f29a187e4dfc32182cf7de86794f0f7934855b3b2ab1707002c513a97b77d17ab20619442cf7e969696c2a7010001	\\x415254fde92ac7c13086b117b9409e32a0e438cf9583ec24d8e93941a36e9c07f65fc7434ae3c83b9e6cc14f6dbfb0091e1be7cf82a5b665f5b335a10cd4760e	1671357557000000	1671962357000000	1735034357000000	1829642357000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
384	\\xb3af86df55ba5156c00a4ad350afac998e994d7d53f294917984952b312ed299927c54b4b4a5b6de4c27e9822971467abdcb93bb1074fde8e90d459c6c3c477e	1	0	\\x000000010000000000800003aab50c0977de9b4c101a1c9d6a4cea44c2007d22236e55b4be4f5c94d0d6317381a7fd02fa8f7d85171cf3375b9f6a94f581a2a8ff1ad828fc4e35417fef680456555a2bfd4493a6c0c4a3499030e9552a1fc220c66e0b27524db246c8c21ad59d4b5ade9d1ee620d8b688597e9af3abcdb35988b0e878bb2d9807148caa8a7d010001	\\xff1bcf971bc4c087239fa55f12861dc18607031e694b72d535757f139b259f1b2c293f3619ea751bae316ae309aed61e8229651fbce0e8b8651afe2fa7c1c601	1686470057000000	1687074857000000	1750146857000000	1844754857000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
385	\\xb3ef859797c8a66fdd3436e175b9ce0b8e1c05ca5450949c2039a6ee6406e491d80d95252f3054e6ebf5b0ed1b43ed4946dae49fad05d499c8ca2ecb3068a3b6	1	0	\\x000000010000000000800003d371d11b53f2ad463fb84855faeb6a84a4a075a6ffe4f1848602edd2dfbaa95b21abdd7bf6e94830c3ba8241f11eef88e642c20b4c9e42e2def78852bf30527456a5fe51834a4aeca6aa3592f54a236589f2fbf467e064111ee1bc0d486014d3e8ea462ab5dcea51fb1c0edb25d467ed4d0b483a64cd373d3e4a10e4bf9dba0b010001	\\xae21cf4d45eee405da4a7bf888fc059a2a77f7181676643298bc92c277713dce8cf336880414f4bbbe086ac324148db745866cc61e0f25e8c5b798aaa0f77e09	1684052057000000	1684656857000000	1747728857000000	1842336857000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
386	\\xb4e30c9156ef13dec41ba9cad3daa4e6671f254a12846e4a84b5df47ce9d1f12d0c95f14a79965c1c9c01f2321b90e1ce7523ea0334724b5e9df955712c917a9	1	0	\\x000000010000000000800003aa5834b2610d0b4c576c41db88cf8831f4509d49d253bd66d1055768a4dfedcc9b63327618a0a5ef63fff93a36901dd704c3ac130420b2e7785782a6abfe4f01342ac6cbd2c2c75d2dec5170b837a6bc9954cdeebaca428b156b2251e0a7d6b5d4ec3f2a6e4563d3925cacf2084cde3682c7e69ca258a96362a30b02ba2597e3010001	\\xf949fb870490a8418248d2748f8bfd736b404947da672918269b2761fddb42a7b2e20e09e4a9e3956d1efcb94c04a98255ddb831e1d97210b34b00b104f73c03	1664708057000000	1665312857000000	1728384857000000	1822992857000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
387	\\xb7ab71fdb9222d62af8a35d4a151d88d77165adb546ef0234d625742ce1ac818a3b4091b9e9fce467af28e27d0e5c0e2fd0bdfeed3d218c96747773055016d75	1	0	\\x000000010000000000800003a8bb5ec8e1794c3cadbe5944d13c95b4cc61e4553d79cf9a441db4a343cd5ead2ff901676fa743be546e9e8b6944721564d299ed74525ff64d0ba2e2ef86693d5179aad4046ff851078668024be0434dc35876ae97fb9e64c0d4a1b2f0496f8d347ed3cf956e79068c9d690d9f621d05b3b350a089b7e3c2b379e8632fbd6fff010001	\\x32c535cc227cafb16354aa38812ff0c6030e1e086bdf92aec6f0739b9160f17a3d640aeeb5e0b7c9a0349dd1f45d1b7290fb60fa72616ebe194e28f43622fb06	1671962057000000	1672566857000000	1735638857000000	1830246857000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
388	\\xba7f5828ac10adf2a1ef207693aeeb43f7ff3e2133986a1e1b96c781f669a8095a1e088e6a6acb46a00fde3e6369dabc0aad7c50d11b16c77d3d1c8c79b163c4	1	0	\\x000000010000000000800003adf44612b16961e2f2bfccbe8c54ddd8a2d5644d426fe435e80872bf8500b08a2128315385530c8717fbd0e88a528a8723a48b94cd34924437514ee36e7593ac06f6aea4f1203a7aecbdb9e9c012b29d9b3ab2164aafc9b699b345707263f66262911173cf0d1ef2a956a51a6883687bcc6b1173f194aa07290d4570ec86e45f010001	\\x765fd159d9940940b536d13ffa627ca40d0d8fba3ee0fd9293dabffabba99c7d4f61a40314f08d0a5958bd6319000e8cfa3976b28390746d1fa6ca31fbaf5900	1671357557000000	1671962357000000	1735034357000000	1829642357000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
389	\\xbdbffa2bbb8e7476723109f2c1253b224c0ab6215485b8466e515521746bdfdf63a2d3093aee3d7930424eddcd95a6f1cce531764b349227ab78ae780dd276ef	1	0	\\x000000010000000000800003bf8b1f26732c54ed37ee5d7d339ec2e9c493f1941753d110a8f8e8f03c294f1dd7dec1d1025aa90db4f331e06cda37bffcd3e0425aea13ed6675423c551a37d94bb8ac1bc86c3da0b0f05ff8463d1f61e898d4f1533bfb851653b4cddf2968b958bfdd4c6bb95fb5c0ec08abdbfb51737cf282c17c1f6f3b00320bcec03f4edd010001	\\xe0ca4551f9595ffe6b4b6284cbc7f3fabe8e25089c6d0d821370010df7bfc8e782f98ea0cfa7157f33b08b1cdad4c4897db73dabff1880b967f6a3f9a470820a	1683447557000000	1684052357000000	1747124357000000	1841732357000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
390	\\xc157316d9919a2ce878f689fbc9e36edc28b15e7d273cf235c1d9425fe193fcdb4a242a938762321cdf6e832572e36bfab9cda27f991b20daba3ec852bed42a2	1	0	\\x000000010000000000800003c8a0cbf59a4a03c89ac20e286881e8292c053c6c31076e14bd3ba59b42126774d265a2fa274d5d0d6dd0d393725710ef56ba84973dc92b306f149b66cf55ae097dc8270ed3c0167161e8c4f17b178753e32a570d17bb7b9841fbba40df467e692b47c0cb3d06761b905f1a9ba8dba247c345ed17ecf6bf5b94a825d900c9331d010001	\\xf22f785bf5c8385441fd9844f8a30099e66a731b312b18dccb6a1b532e267d2f0430ffc600fd5b614891ff7bcfa9431fcd282e13c9429f4ed0b81a708d2e3d02	1659267557000000	1659872357000000	1722944357000000	1817552357000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
391	\\xc113f8b17a734b79558ca7f10a72bae98889c6139fda806342cb8a5484fd3fa9167e4cc3627d44f54211847aaca0bf414027ff28d843a4b3e87e06cc8952a169	1	0	\\x000000010000000000800003ae944366efc56f0077989338da616b11d0d75d8b1cbed8929f4a3f8868d76ae03593197030414b51cd332bf029395853fb3095633493902a47914af19c86f497cdc8f691de1add817582bfbc80a9b1cf4cf47a8c7ceea963498fa70c96f84dfde694f80975d1d1f5a1670bdb47c7dd06ea42b5ad2fe995e164b274060a1df13b010001	\\xa18e6715b6bae777ae1cbe4ec8f097087a41d9cfd48ef626bd6fbeb17defd003f3c513a8ba7ad392686c59e18f39fed8a817489286281857c644c3841f90a701	1658058557000000	1658663357000000	1721735357000000	1816343357000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
392	\\xc2eb1cb80f44390c898cf80ada3e3523b5e4d28c2f21fbc9d525f45ed5bddf80caac6abc6a4bd2dc2d75c2dec012b23e8dfd354fd35775c70dcf58ded5a7e3f7	1	0	\\x000000010000000000800003df524974ffb20937e0673db6415acca015d9726e86d5f7b7add5e12b5f8330afec78449d14b28ce6e46e6307b1d875ed458896a4724fdc9b0fde1732deba0d7b7abdf4ba704b52d7896eba536bac3f14e73b2b7c108eb5a673bafd251e2a9aac55969c5443dfd819b91922c9c6f17228e64e7f2aa82ca39b8b34a0032f2d0445010001	\\xea0f751d1c5ae4145b4b190a44b6c1682ac3b5f6d069ea5967dc4ba553720fd394fcce3b8e5203ec7adf8beaa01b5e702076f8a97d17c12079a50d0148cb4b0f	1664708057000000	1665312857000000	1728384857000000	1822992857000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
393	\\xc56bdd81cfe56043a3d6e32c6c012acbd4ee2318f8df55f2e783efa1d679e074821f6215807982e25f6a28c827b9ab5f1dca4e207810854ab3663f9412342404	1	0	\\x000000010000000000800003cc6460e01cbe5d7abd7ac9be42c3cf946d96f1c6add77ec05e0b086bf900e1e1b15aa288d82871e2c17b046a593680e9b03525f589b0e46410657703bcca7a5173d4d7b8a44b1b81edb14b97b6c11e2e73f491530270fae766cf2ff47e1ee1f1933ffe0888b02c880d8a1b2fd2201ca055a0563eff75d681c3aa327313cdda6b010001	\\xc103456c2b09ae6ae5c1e4b7b87587a6173d4db0ce4977bafea15982271b4c3c9e4f35e1cb0dc7b7ece9824dc64087b8ef3236db3dbf8e26a38a41d794015203	1659872057000000	1660476857000000	1723548857000000	1818156857000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
394	\\xc6c3f337dbd34255cdfb0190bbb74cbc91781a0724a4291a741fd0fd31192832394ffacfeda32c065b19ee0de0a4375f2a9174dc0d2794faeb9c389a5823a0a7	1	0	\\x000000010000000000800003cfd094dc2b6fb7fd929ef6335962ff05646282a3d53f972d9f7494a07db789dcdb7668fe90a5a2ab57c5daff6a15dcf6df35c29abf72de92e6d941af1f640188444d96cfbe22b3b8a6cbc105d0df242af5a1c7e5e45bbb15605ad5ef3b2dca5e426c0bb3853fb27410493a17b2fddbb603ca1b2f45e7e3bafd85c275aa51a429010001	\\xdce95a50cc853d8249b7ea2767f4612d59e3d84739f7aa95f19838d5c7f93db89148ff60a99ea322640d7c744e97d5914e6ea80c18eb43133f02d0f40a36d409	1679820557000000	1680425357000000	1743497357000000	1838105357000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
395	\\xc9db6814520c028bb27df5f129e06aae22f71928d7991bb7809c27ad8a6349a06e25ec1381841af7cb5b000d6a15fa8b5eee4a9981fb1ac55ce9c8c648b375af	1	0	\\x000000010000000000800003c9aad0fef22b826ddd7ada4335d4bc9bc7745a4e27ff651a6b913400bf360a35c33db23dd3f8809132d01a6e8f843ca6f2d48d420214290e9dd338f4bac99dee92c9ea4e44f60ac28afbe2615709a1fbe2cf1042dc071a5f467031e6bd2eb94c1b4b33d882a3f4baf8d21dbb9571ea7fae9ef4a86b33306417dc9e4ed2103033010001	\\xf297c28a425a29ba8a87bd79c0ffd7a5d1618633552a3001bdd787aa08a35e65ae492e57b2a385c7434fb7c9c42df8f1dec4b0e3dd59b12ed9501c835387c705	1687074557000000	1687679357000000	1750751357000000	1845359357000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
396	\\xca4fd6174c63e4e64dde563a10969ead6e5005a26bf83dae1d352d4287eff225fb847ed0a38c4fb7e992bbdec86c8720087a37ba3142962babef98ff5b633650	1	0	\\x000000010000000000800003a35810e8be692fd341dd5d47d4bad036e1ff7b6e335be8f6377cb70e2d76ecde2b75bd6c9478cf8bb0ab73f469b3e9f44ed68a1c9693e9189e44e7985884a1de6b8d4b53f44fffc43db70e5edcbc521e60325debd87d64c0c8548e85372261510578b91fdba9f36a5e1f8f22328648091a9ca9e73dc5b7ff53569403e15d68bd010001	\\xcc21d88e2f15963b44da2501182a814020b2e4c690c9dfaa4f3cec0ea70b0fabd637b9a04f334005cd580b68b1a671bd210e4ba87d4fff4714d54fc6fc4e9503	1678007057000000	1678611857000000	1741683857000000	1836291857000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
397	\\xcabf2ad262e81793b5b56ef65b7a61cbe211e322f8033984661e04bfdc7cf2c52db9c2bba312b4ed1353ec9415323e7f010962a0b230b9117bcd544ddd9e8199	1	0	\\x000000010000000000800003b118481e158f4e1d37f9c1798c7dda842ad185bcc7a06d18ab2ed152a9f5b2cfb70049798216e0d1d7a3fe955de76b6903aa5d5df5b7837b69bb49520d83b5291ec4ff7b3fb88804739019421aa577e5a318bf541bf4707817a25d2037a6953c86c80dce5a72464d3c7c3a2ced6d533ef210f67677921ef073d6f682f8de0929010001	\\x75ef0d9511df4d2087df0fcc6a9d3092ea206f8299990a089390b2e5c064b52d51ffe15847ff39d3a8a04af7c864ddf692deba11c6bb52a9879f12c210d45a02	1657454057000000	1658058857000000	1721130857000000	1815738857000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
398	\\xcb1f04be0d06577541e4434295907e3088bca5e696a3deb89f11620bc38cba30741b942a988f1451a93c052fdcde1dfbfa46a4ccb790b2e9f4af1ffe4a60160e	1	0	\\x000000010000000000800003e8a9439bd5cb6ef9904cda73b3400979e4789c70c4f62fdb51b0d8b2c77093dd6785123616dd72c47c0ca854df4be9f4861d529547383143f38e7938d08e94135f9b7c8159c2d5ae72236cb3d17e43bd79510f577384eac54b3f3a4a2498a7bbf582892484e80614f90359c8d81e9a79d57434d8152f55ba0792e74442b92709010001	\\x27a5305dda49cafff6fd159b2d06ffad83bb584ea21f5697bbece9626da745f9aec000133cbb927552828ec31b990a8c6b206410723fd071d089968a30111500	1678007057000000	1678611857000000	1741683857000000	1836291857000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
399	\\xd65f4073edaa5b43666a95e05a5eca90411f83a7ebd4834a1f5c866774e776ec45fd9607d51201c9b336f1c7c19992640601ffd1379a86a57b15963f7cf05bf0	1	0	\\x000000010000000000800003b3e6060a30e267c90ca5dd82c25091bc2feba0b6a6501fa0e69dfeaa2a7a441d65bf9947ceb5d4f0a6ef824d7e26405b2e04d3de63dc043080cacdc6d3631a2a46095a19a278bfb8dd2fbad5f4cccd7aa61c923342f3cff2b6982d18e1d63b8871dc5a15358fad0cbcaa9f2481532ac984cc60ea10ad8078e70296e0a6f4d471010001	\\xcb79b9e517e902d75569a130d053bb3c3d8cbbff4b0b5eaa1468925afd9004ef9c70cf0accb72b1689578260a89da95c5eedd10002e13e4e0f66779d9b8ce700	1680425057000000	1681029857000000	1744101857000000	1838709857000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
400	\\xd71b96cfdb7f2c0d00069603794218cdc0b11a064edddf62a9ddbd15f3db01aa0b55cc51c3b7d533ae25963cee4fb3c52bdabddd51aae016d5eaf5bdbe9eba5c	1	0	\\x000000010000000000800003d0612e8fb827d38d54c42cb5812aba1c77ea9e9db7bc7e18c6d392299ffd70302f04c591a50c84064a748789d8f8c9521622e2e21cea99982b21eaad38e4008f626832c798bf3fdb98604ccd2ff11ed799be8544f98d713f253eddf2414f66427d612a40b07a8ef8a139495cc00e1d76fe7705b5d639ee6fe43c86892623b7a7010001	\\x189aa6bc547bc7b307cbeccd6a30eb53da89cefb14e99135af4aff24083f56264c4043293ea9fc7a85ac2e41f32e49a5e9c2f1fdbbd29869972863b5fff14303	1682843057000000	1683447857000000	1746519857000000	1841127857000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
401	\\xda1be67a6e5c52325b72000e7fc5d159b3839f0a18988704c1ce1be9dd49fb23981152d2ac8d0922fefa31794102dd9d2c8fafbd09f78226177ab1851803ad6f	1	0	\\x000000010000000000800003ab89ed05676b9eb95e2a83e7d64cf12bc9adad2522028802f09a9c78029c1ab11e45d4de38cfc6080d63caf55d6878dd23ee95dd84d0ca2004faa2940906804b09ef31bac87e2d2ad61a1b8ad5ae242811c9a6ba340994d8c782727444a96eca08baff9afd4f33477b0f02c3825306641738ec207091d5c562f748344262265b010001	\\xc467f977f5dd42d497bdbb00fa7f599a9bda948a4cb374d5006be4e9385639f5e674bc397f2e218fe8153abe7ab225dba4a73adce4cac6a063bb3a0792414709	1681634057000000	1682238857000000	1745310857000000	1839918857000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
402	\\xdca310778dcff475e224a960615608c37f9a2b8f54756b717905be8a9fd7c378e9fa34b69cb843267ea1d7b3db836a94bee42a77e1043a60a96e4e7255c59aba	1	0	\\x000000010000000000800003f796ca07fe7ba6c34b29fb19c0c6f77bc5f4b00378e7b1fd32b0722a6ba64255635fe0e90ad63aa38ae66c062f95d8d1ba62507cdd818dd4cfc938dd2ae2b4d04607deee4a3bbb3bf25e525b91d2ef64a98749bcca9f89308f4517ac4522b62d6295a48d225eaaa70aef8389cdf58cf0af309faf11a136a7f329714fa0e04a01010001	\\xf5a0d3ef6ab8f3995d0d297c677efddfa181f45dd3a6b1d40cd57d58cd50519d2190320c7ed4337d69030ec33c61df10df867a01036a9b727c59a8429a267a04	1656849557000000	1657454357000000	1720526357000000	1815134357000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
403	\\xdd43632c267744ac81e8b9ef029c6e47b4ee695ffd1572686a9569551aa642f8e6d8422937a910ae6b38271f067b76c124c5075691b41189d473520be9e0bbf9	1	0	\\x000000010000000000800003a78b395fd30d2428e257f8e20f5d96ee3ad5b089c307c6fd99f1727e4fd1ba07780a325da353e6787201cf09656babb10ac9584b3750c7313e55454df18560ac8abc2abc2b810b5bc84f51330a6b71f3acb5a947c5e589cbe293e22174a0e4d392e58c085cdd40cc14f112919c33736708d93cbe9c05994c5f4d1eb3cdcc1143010001	\\x24c5c2e53728a138bda3bb7beae5896a2eae1cc8146772f823b41bf83898e11aa9cd94e0525e4eacdcfec113bde869774559ca8804c7e1af6bf7e95889ede203	1666521557000000	1667126357000000	1730198357000000	1824806357000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
404	\\xe3071f24547d35855ede8440fde7d05bc0ab4eb83734a750b2b159f58ac9f9c0c5a0c35b25c46c42d8643e4b014b51f35402c5d556e9465810bda95fc57cc5a6	1	0	\\x000000010000000000800003c2a364d54832a76940885856b4d5365f1e0e194e7565c0efb8a557ec1db78428ee60986d5301c29cf77c3db68555ba56560078c6ce7cba291c93d31b3277577669afa28057f653b685187a0364d3b727cca425d5cfdb24e8622bfeed9ac1a5a251955bb5bcda79ab1ba659b7da11a9c7fa653b3ea2e924713928d0eb171d4ed7010001	\\x1bb86b4d9c06d68b721a6fc30b8af9770f554637b6efceff50f81845811ff36804276cee31fad9acba9fdfeaa42cb18019bcb9ad1ca0e7a6cd5eaf39f31fd004	1675589057000000	1676193857000000	1739265857000000	1833873857000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
405	\\xe317f35717d9bfc49787eb40c7cabd409c4431e8f66021f28a1247bfea6b0951e7ab5bf34253926cb079028a9e71c8d8db04f385a7adf6636050b3a56c2dc531	1	0	\\x000000010000000000800003cdb0e05a6b30b5d70b920af5c434e3e60122e6ebd3e627c282bbd8f912891e51c30aa0ddca2e6f549ff31607a14004f193f010265e46415eafac638c799ea25eb9bf09c60d25c8f568bd674d162e1e2b2b9cb91b5f03a0d7e5c0b9d6bbe03c039c7dc2801680f3e20359cb54302f5b80b5dfcdd403f9aeb73e81de2ca128d435010001	\\x18cad548f93e0c6815462037106973650acf86c7d96726f238a2d556246fe8ced59c17158278fa37ece287858dd43789fa44ccac4d994d7e10b9cdf45579a90b	1659872057000000	1660476857000000	1723548857000000	1818156857000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
406	\\xe47b7cb7ddafa82f545a25bde64232ef2751ac084c0828548fe5a3e5856caca5e90d7818964041f1276781c262cabf4e7ec58dff47c8ac36ac6882122022a334	1	0	\\x000000010000000000800003e3b98daa01b52bc5d342b340caecee404f7b2c04e9106336e2dd1ce07d243b1bc979ae2fd7734058630fcce58982e9bc96fc6b3ee4da9ee2cd3cbcd74c8f7196073695f0e1646638eafa783cdee939f836e0a13e1076fc029ce47104751e5ede39d1b95a318f25001caff50cc788647a2c56058ccac99de52a67f1a5642e57fd010001	\\xbdf18b9c77ac5b9ea0682c64189e41ba919efd6ecdc08d35aa0c1b37e2212f861aa69b80dfd471b07554f2b4ad38e5b76a24625128a4a8836557457277afd601	1662290057000000	1662894857000000	1725966857000000	1820574857000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
407	\\xe41b7ead4c186b50fa78602a9462194514b5947c83841582ea0aaf22a3532381d544059fee9128b93242076e5b42c7d05162a8638db298ea133b21aa632ee274	1	0	\\x000000010000000000800003dea1e88d56f203fcfa1a2a88425e0da1688f52317536478e1980a8aeea74f435c663b2a98084a55feb2369f062a59804c7a55bf4d07bc105136894abbf9856f3027d9809d61f6d85c67db775f4289bacb0e7322098f8fecfbb773c90d82cdfdcc84d91a9818fddcbb7105ce75f401cbf6ebd58d976b369774665728d07f5f995010001	\\x3cea61abedc877e27d9b2a1e9143c050d5f18515f2f554005419327d6581cb320af405440c5cba65b02d3fd1b0fd65cb6a373818b33db76a81bb7cbf6763f001	1659267557000000	1659872357000000	1722944357000000	1817552357000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
408	\\xe8e713ad8edad8046df31d675387ce76d59bf35f8f2922cb900907d09263b6a9ea41d2afe2ff9847b02f25177994661840710323ccca18eccfc48e24c468cd85	1	0	\\x000000010000000000800003b7b4ac14dc22ab6ae06ac748ab3fcd8fa2a95689a20f21b735d984a7ccf9de06001414a62e356d706ad15f88aff5a5a7ed37c47f18ead307f7f00559627192da102a16d5cba9fe59984abda43eadbd0ea48661ae7ef92b5a38e67fc5665b8457c20038b47eb792e7e2efdf8494c540ad3a11fa409cac56d5f62d9951241a09df010001	\\x605eeb0d8a9b1b1c904702a5f434bc8c747055c029c9eb909ac3d370fec4a260c05237851effcf182e883ab14f703ec8389a39bb42c017c2d3befeb114ff7a0f	1671962057000000	1672566857000000	1735638857000000	1830246857000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
409	\\xe907b50285f1ffbbf42cc3d48646f660f25091f5db842a48d3d92deb332fe1a047d66fe18c0540ef8d06c9637d992e1b8f3b5afd9f7b093ca9ffc84c72972b32	1	0	\\x000000010000000000800003c19da293549a07895d638efac147269907990d397599675352fefc56f21857d4788aa55b4d5702a1dec2aca774eeec79a9100536139f841738eff7bfbed6dcf98f05df7ec6f98738a8d09a9556eb911f323d7696731c8a9e7dc8a7acf4302d16b78404cb66f38d1b3245db8942fdb60cb0666144516d607f9e5db709de2e8edb010001	\\x89faa312fd18952fc7011e4d61fbb161bb3cd6e19f34936d2dffa4c8a9c0be5a3872003b01fe25d58f86a8656d17ece3c6ef74725efc7ff58da99cad91269009	1676798057000000	1677402857000000	1740474857000000	1835082857000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
410	\\xeaf764731f1cf22cc027571ad91b244ce24577bb20f435966d80d70494bbcf261db4568cdcd3af6a71562f8ed5742d466d78fd5ac60e1a8743c04a04f50d1aa3	1	0	\\x000000010000000000800003d4f3f0960caba5d0cd8c3c35f0c2c13a5599bf12df27975f658661f29ba6185e85e22c51f305fc8de0c16ad00611f5f515910c90d60e2a3f9e2f26956e46eea6c44b35ca86bb0bdd53c3d66475e70f97eb7bfd2ef5bff3db78f7ca7b52ad67177242f4ff17f864f8013ca842af856246c3a947274994fd44ecb9c4aca4fb8455010001	\\x7185ce8e019b12889a39335459dbc7e23b5e84427560007cac9049b5a2aebfe7ddcecaf51f26dcf2e7cfcc7a7db55bc43f1b73655adb0912f8e1f90a19600c03	1672566557000000	1673171357000000	1736243357000000	1830851357000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
411	\\xec8b2abd06630c9333bb5684ac954c0a884b18126c7ae0fb258721189076e33bf9451d1565172321c43ae0881c1c4fae5d9f9d38cd0c01aa43ca91997316b8bc	1	0	\\x000000010000000000800003d498a3d5efa41b3b2ca4552eeb96ea09511f4cb8394342c20abda7db9b78dc68fdbe163ff5ab65b6543c72d3e447600fbb09edb6d68396b343d5da067ceffcd2e55f4733b5f0e441ac993346d884cf8f53235de47a1902c4701738ab4b4a018abd8d37069281d76d6ed70317bdf1f2b52ad1a015bf290a787af8467b6996eaa9010001	\\xcd964dd656920da8ae5f432b892ea587adacbe6b8e4930bc51477edf3400bf8b05a23f0308e7735eca207e08610172dbe479a1ed72f9fe629585fadb02e7f806	1657454057000000	1658058857000000	1721130857000000	1815738857000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
412	\\xed0f74b4a76d2f48f20333d267120e1ce378189d5153be4373621bd61d6677c2fb9dba2fbf40935f74d81f9fbd494d28a9f19c2f8f32367e62e9272f8cc9e3c9	1	0	\\x000000010000000000800003b709f284e354233d487df7a9615cfef4ea491f52c35e4a9a2dcc49b96942f27eb1894dd62796cf61481bf0586ac6d91e7a8b0c50278a7f16cca633650288398ea088a62282ca20ba12cc0276983162b3d2c876896f3f74e6ef690b96c2fe4f926e5c241e2e7d5443bd7f8a6bc2d12e705ae9cd62cc08e2fc5e0d26e2f1c8edd9010001	\\x031dee484bf4f8d58ebde6c1d9349e181d7eefe3499c57b83c6413718f196cb6f0ce2111dd67d7fe27e6871f4c95655e221f441b363892648b5f060c2e79190c	1659872057000000	1660476857000000	1723548857000000	1818156857000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
413	\\xeefb940cc5515afcb8a76bcb0238888c7179321641170952d7babc3ea96fd762de6ed1a4b62e444531bb8604199a56a1e36b97f3eb557face8f96790abdea0b1	1	0	\\x000000010000000000800003abae4e94d3cef8b821c30855dc754811d02c83211cc08ccb0574325dff435e369709d2ea83392e6abf82be07118dad9a882ffef401ffb86902738b4a3d37d448cb6c3765011e68f7f7a48f4c446d7205b415b91c611378d600c7cc12629b7636f9c3f115af58d5ba7df9ae02932305a15674975a63195b5f016df11dd3e2677d010001	\\x2efbcb2d1a6b6f8b93d3a11f979bbd824e24347e82bc1db1711f1bcccf44b521749345b92346fda91e95b944d6a9bbd4969cdc3b86a4280c015e5986d7c35609	1684052057000000	1684656857000000	1747728857000000	1842336857000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
414	\\xef8fa3e48332c7bf4aa9f13ddf8e4c11b712ec6858535ac2817eced70be31b76d6b9aeb8c5ca09db3f699e19cfd67b57cbcdcb727ec8052b4b0b8e0add4b7ac5	1	0	\\x000000010000000000800003afe2d87e60f8a7cc4a8d3d0d3ac3da1cff71fc7f0cdd62f5312b31a74a6c1422fdbf0d337e479238cb70ede72627eb5b98adcbed0fb61aeaf1dd468f8cc655a679e572ccb2855b2f808c7d8f7a5d8597d44f95f0427b907aebb72e5beb676d89ae367af192c5ddf8e9db94617c70a4866a5d171587bb7cecf9e404f902945695010001	\\xb9fa7bc7be2ce2c4c7c8f93842adf0a3a7202928ae8a51da3b27b1a361954daf42e4a8f6173ab16ab9cb4de153dbe2a7eaa6f90f6a7683f6c988b50a7bfe3c01	1667126057000000	1667730857000000	1730802857000000	1825410857000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
415	\\xf1130d5405aef6e118196148aed8b97f04a6ddf5a575378e2252e55d47c2a09d188eb188cfc736cf75058d1cc4b0d1a2a3e67a5d76081dccb1e5ddac6de84f88	1	0	\\x000000010000000000800003ce8a5bc1f4f2d31a9dab65383233e3e56d4c5c13efa057b99d70f079647ae114d2c34c61000542f508992fb5adb68acf1c0a3d296530c6f1f245401fa3077bbb1895413b0cd2c18036922777c26a427e7989cd34b3274e710dd64ecac1ff5913420745a93b26928bc642739be77aa8ba5fda88fd120f3fd00d30aad35e78bb99010001	\\x0c49eb0caf527477e9baf026716d57912ac8bb6e9509a33d88260e21b35a0cb56bb868243f1f3d5449ce5545b61e5714c6e27ca8cbf1f6626f21171487fe010f	1670753057000000	1671357857000000	1734429857000000	1829037857000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
416	\\xf197bd0f9dd3e4d9623abcd9c9c1cc9fc122556bedc41ae08da74d751c5db0a4c09029ce14ffa7cd9d08168e7190fcda9a8a7d330ec1c908bd8d127629785816	1	0	\\x000000010000000000800003d6cea21e5bee50e886c14a3a89bf180d1cb2ea450803cd7053aae361288ba690a450dbb5347a4a569c50ed272dab8924c08614a7cfbae81564c5bb1aafe30e8a44c8effd84691bb4a288a417706a5fd788a210b64bbc10458d6cf069d2b5d2399569dc584755fcfd99ad62180b57a22e6e70831b15cda376c44396f77fda23d7010001	\\xa6d6b794003c17bc316b97c43340e35f8e052d693d69879c96cbe0d6340894fcca41635a31c17b35543059fdda51b3334891b5c668078f8df550cb4006adad0b	1664708057000000	1665312857000000	1728384857000000	1822992857000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
417	\\xf103a3acc67ee08d1bb0445c21926ebb8c06ee774d8a6522772ea80b27ab8d917109e16da134b74734128f18f0f37f042ae9522529917b6f12811d81dfc09656	1	0	\\x000000010000000000800003b50f2bb02fbb9166350ad2cfa3bd3bfc130375ca5192155f05cb97055a7a096faf13707d5c6bbd4969ce33819cbb59a67f9ad1dee8f7b51732578227784d02d28af66514d9de77b9e7aa711df8241a5e7ecd6df5d749475eeeea75cc15277800788fb99dd8300cf4896904cd9dc5b8ddd1d3960022d9ca9cbaa6f25f37f73eb3010001	\\x7e1d4be83935c9a2e12c7dd913e75043ddb7f99cf2120ab8e96da97581f30911e1cd3c1f3cb4b17f744d2c97699edaaaebbf4ae5c03b7d64ab97ae12f0a55109	1681634057000000	1682238857000000	1745310857000000	1839918857000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
418	\\xf34f0dbcb2d80cd2b639a0fca62e937c43355cb3fc6204a901e3863a90fa88e7a91b40dbf158f48c5e860cd7f1ab8bf4105afdbf498b6e2e12d8aa01e1503caa	1	0	\\x000000010000000000800003d3114e393add238d6cfd8e28af1db3908b4149cf549f12f6cd6fc22e901514febd1a9b81c964723069940a33e68e34deb2c1104ce6530ea91a0b1fced44918bc89cff64946615cc4c56fd9dd004130f666123e47c404f2b2bc78026b437dab753fb90ab78d923197a2d607f19e0683ad886ba02e73daf33e6f58039e633c2c41010001	\\x89bb29becd1f3747b6f8531de09577931c0c3d4e37a9180e8049bfaffbc1cce1bff39f533aff953eab9b01066da69ddab3320b1eb592f0e25aa3c84af5d0ee0a	1657454057000000	1658058857000000	1721130857000000	1815738857000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
419	\\xf3c3ca97fef3db06864b81dbe97a7f3fd64e6becf137d911d4f8f0beeb2e82bbfca8c4c900490ea593f63875b7f84b75cdc69dc17e551ff2b652bdb85dd61d45	1	0	\\x000000010000000000800003dd07a7b42c688985bca39bdfa171e9d9c0a0f47e66d09e067f837972d6292664122bb67c3961bd70bf4ebd87c6adc06573fef9edf57ce013df4d092f9e8bb3b47c8af670005fd97bcb77da79ad5c3f0c3d135923d101aec187a6abcf1e152bd156550ebdf6c17908918f0decd9975a6ea8a8043a60aefe1ab7ecb4165774d10d010001	\\x77ce9212747c4a2a621675ba7abf44f56d893246d35805693e4c79d2615d6d5a43fd70cbdf2037428074aafb811cb1737f39a9bfb1e17b4e22d845196cba3304	1657454057000000	1658058857000000	1721130857000000	1815738857000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
420	\\xf62301a0f8bb6e58833ec455509e117fd7f1a853b976d34f6c0068b0864f17df10e66eb01f519cd125e75da3d82bc687a3cb9fa37f7e3b266f20dd02dc50d741	1	0	\\x000000010000000000800003ca27dbc66b4b36b62c8ef0a8a0321970459f65eac494ad858f52bd0483a48b58560876e29a13c35518af530108d3c42896966e723b6783ac19ec35e21a389cc3590db8c9fe8073acf3f4012126dd2216ef6c9163605320c2fb5f816035dc1d842d87c5d5a5f496fa40fd4348288e9817c76b7e6bb001f32fec6ace5069922247010001	\\xc0f551c6a3cbb8aec82799ced4703a6834493264b639a6139b1cc3e5a0a5e71e551bab7985f536c99f4a44df6116900dc71f685772c62c5bff0f3bcdbd714b0c	1659267557000000	1659872357000000	1722944357000000	1817552357000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
421	\\xfa9b2642d5bb288268d0292eb4bac842bde971d62978a3bc9cb3df05b3c0ece1654cc3c285cdeedb1baac563740f6ba5fe795dce460c0b904f81e62341587c7e	1	0	\\x000000010000000000800003c006693d9d9d91f97889821373aecc49b16c3b68af86d952b105cf9b1a8f8cddec86638f7ab5edd0f8d6ec2480f3d6ca19814638168c177b380c14862ecc6f4bf7ad7c9f2c1b977c0fb8016078989adbeabaab96023bc3a359a72a9d6445736cb6950c36c108cd45ea21aad53c91eb593a343efc007de44892ed01d2d0abdfb9010001	\\x66ebb34e6d30415bc602db03e6a860eb04514bf6ac59b548ff69f12a8af6d164dfc6bf58ae09cdd7e52e45a19aee0fe07eee595636e4a7608ae2a728bfe83b0d	1671962057000000	1672566857000000	1735638857000000	1830246857000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
422	\\xfa8f808cea3de2ed08475e719447db17e0bdffbef6c57476f8255a93f273b40cdb86c79377056b0461411317b04a941f6cc3a57a4b4993c8d3772296c2e648fa	1	0	\\x000000010000000000800003d583e5ca4104f1d47c1c61907567203f252106c403bef6c830b2a5b6e36bfbf4d240b7a346b8f84d594795bd57e56fadbdafb793695bc01b6042e05bebde45f6cf371656af2fcbf372db694f37380dcadbd0e95af873b7be8ebedc0d971453b262cc0dcebf872d095019e906bd7c74ceaff8a8063f4b373bb09116324d1f75b7010001	\\x02d27f45d003fa8658258eb30f85272a3029ce76135dd882c4894089af7aa7891fa96d2267ae5a9955d34d46d7af8590bfa2de1ddec88a1d0012f905287bdf06	1677402557000000	1678007357000000	1741079357000000	1835687357000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
423	\\xfb7fe989bc764c57dea1010bfbbc6088d5143f60761a63b772e46ba7d3afebfbd2c3896d2fa86bdf22e8e4b78dcab36fd161db456e6217676a9af22ee41fdb21	1	0	\\x000000010000000000800003e244500770a499f598ea8c41066becd35afadc8f597fe5fd49a92b629c47331d3ed2cdfffc988eb0771fc9a42871fe24f584168e68b57eda6db2631c0f2d2f990a6cced4dc76d40a17c4b9248ce463704ffec709c062f67acb6688261520aca6a7592b9d0c6bf1e67c3277d30ad493efe03eeb974137dbeba1e42f494150cfc7010001	\\x45c3cb30049aee67b67d3c2952471c963df68f7ceca770340583ed89c2070e463616bfc8b8e680864328efb7cb2088b6b4ca46271a1be6e83dfbfca2ed832a0f	1681634057000000	1682238857000000	1745310857000000	1839918857000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
424	\\xff6383b8ecf9d487195b195e9b0e28f61c9b183c3d905f2d653deb6899c79b2270689b2def088586097e2b59d6a52c5db7f0f1bd68fbdeec1db495bcd62a96f6	1	0	\\x000000010000000000800003db43ac3574e40c51ce543808216ede011031f3fe820ce81c65de7895fc1c2deb225f90a5f8c66eaf33fe42ff32df00f5c6761c69d32fc47abea8deb435304a01ec7fa51354f574786e854f74e6a7592c4952e19977b4fb0820ae2526c90d5bf1b4c320339f6620de8022bfe89e92c421c7a818fa15c10bf36d309dff921d2a9d010001	\\xee48f223dfba7579c0b547bad3608559bd3bd9d0de7fe4bb6af623e30c80586770281b93616f07a4bafc041f8450d4b868cae6861c2e98cfa84ddc265f7bcf0d	1684052057000000	1684656857000000	1747728857000000	1842336857000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\xa61cd803bede7a4c5bd951a55bfd23b09ad5c08578e86c2ffdc6489a025add48	1	\\x446d924ac3616f31c181ecfec6a3d6967a813dd128d58345c2081213684988fa3df4a7f2a607ec38a63c074eb880b1c2c48870a70d4baa39a25cf3a0dd277402	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x3e551a82672c154fd6890b5e98616a2357edf78351e51d163ac5974648e335ed5e772c7fa9019835bd667fd6e7e77602e9c048db589e7cf5919e8dd9c6f864de	1655640588000000	1655641486000000	1655641486000000	0	98000000	\\xdad90d6dc263d39fcb288d066e4391d92e8f307f934585fc104b4699147e9673	\\xf337883e3a61ec21f25253d1917e3eca4bb0da8ba9a8b190ad0a0c1eac8931e9	\\xf7a324cd130124c6426a996c3e7aec64f5e03cadffdd2ac03ce329b97d097d1eaff6cefefecc7ca28070d07dc630d9b926a3c7cccbc705e52365bab63b29bd06	\\x85c532e0499b11517a10665c66301831599632bbd934c51a829365d590a774a7	\\x80034bdeff7f00001d9904bee85500006dfac4bee8550000caf9c4bee8550000b0f9c4bee8550000b4f9c4bee8550000c082c5bee85500000000000000000000
\\xa61cd803bede7a4c5bd951a55bfd23b09ad5c08578e86c2ffdc6489a025add48	2	\\x8777bfd11f12e9e6cc970e4ce3639e53a8e28c95dd71b1252d64f1136e7cf22ae2fe2ef65d9ba1c72a65ddb789a70181592ff5232a92d33378d25837140ad11c	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x3e551a82672c154fd6890b5e98616a2357edf78351e51d163ac5974648e335ed5e772c7fa9019835bd667fd6e7e77602e9c048db589e7cf5919e8dd9c6f864de	1656245422000000	1655641518000000	1655641518000000	0	0	\\x0a938661f11ca2b6284a512cae4b1a01e5c89e9a5f9cbda49608110ae166639f	\\xf337883e3a61ec21f25253d1917e3eca4bb0da8ba9a8b190ad0a0c1eac8931e9	\\x336f89de26b436c0cbb26d657d7fc2eee0562e74378e85c1eb16bbc61afebabb3694fa64415bbaa00f7f4805ccc7bbd151b01cf0731ac59853f9d9c6de93cf00	\\x85c532e0499b11517a10665c66301831599632bbd934c51a829365d590a774a7	\\x80034bdeff7f00001d9904bee85500001d27c6bee85500007a26c6bee85500006026c6bee85500006426c6bee855000080fcc4bee85500000000000000000000
\\xa61cd803bede7a4c5bd951a55bfd23b09ad5c08578e86c2ffdc6489a025add48	3	\\x8777bfd11f12e9e6cc970e4ce3639e53a8e28c95dd71b1252d64f1136e7cf22ae2fe2ef65d9ba1c72a65ddb789a70181592ff5232a92d33378d25837140ad11c	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x3e551a82672c154fd6890b5e98616a2357edf78351e51d163ac5974648e335ed5e772c7fa9019835bd667fd6e7e77602e9c048db589e7cf5919e8dd9c6f864de	1656245422000000	1655641518000000	1655641518000000	0	0	\\x13137681cde0c2f734d8c2865b9666bede70c5630949a936b5da1b8c41baa84b	\\xf337883e3a61ec21f25253d1917e3eca4bb0da8ba9a8b190ad0a0c1eac8931e9	\\x5a3e7839f76886498ed6a79645603a9d84d29827aa64f761c22f599ed26d65b2feb7186cee916026da6b52f67163f19b3b6e55b36f3eea6686b2e13226e8c409	\\x85c532e0499b11517a10665c66301831599632bbd934c51a829365d590a774a7	\\x80034bdeff7f00001d9904bee85500002da7c6bee85500008aa6c6bee855000070a6c6bee855000074a6c6bee8550000e002c5bee85500000000000000000000
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1655641486000000	1290768505	\\xdad90d6dc263d39fcb288d066e4391d92e8f307f934585fc104b4699147e9673	1
1655641518000000	1290768505	\\x0a938661f11ca2b6284a512cae4b1a01e5c89e9a5f9cbda49608110ae166639f	2
1655641518000000	1290768505	\\x13137681cde0c2f734d8c2865b9666bede70c5630949a936b5da1b8c41baa84b	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	1290768505	\\xdad90d6dc263d39fcb288d066e4391d92e8f307f934585fc104b4699147e9673	2	1	0	1655640586000000	1655640588000000	1655641486000000	1655641486000000	\\xf337883e3a61ec21f25253d1917e3eca4bb0da8ba9a8b190ad0a0c1eac8931e9	\\x446d924ac3616f31c181ecfec6a3d6967a813dd128d58345c2081213684988fa3df4a7f2a607ec38a63c074eb880b1c2c48870a70d4baa39a25cf3a0dd277402	\\x0c56a9369d7efed59f505251f0e4d0618ca9fc5eb84578028d03d9283b3023343a2fc6061180cdac96859edd8986e2f24ef38b2b4a1644b4360777a0b5c5030a	\\x1d58b2abc9ad337262b6c683dc44e809	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
2	1290768505	\\x0a938661f11ca2b6284a512cae4b1a01e5c89e9a5f9cbda49608110ae166639f	13	0	1000000	1655640618000000	1656245422000000	1655641518000000	1655641518000000	\\xf337883e3a61ec21f25253d1917e3eca4bb0da8ba9a8b190ad0a0c1eac8931e9	\\x8777bfd11f12e9e6cc970e4ce3639e53a8e28c95dd71b1252d64f1136e7cf22ae2fe2ef65d9ba1c72a65ddb789a70181592ff5232a92d33378d25837140ad11c	\\xc45a777d798979b639fc7b302d3c7e702b68126235989bc44bc24330e7cfbe1c13058ea2b82147334a54b3638a62d33c94c0003ba4d60f8c266f9c920fb86b0b	\\x1d58b2abc9ad337262b6c683dc44e809	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
3	1290768505	\\x13137681cde0c2f734d8c2865b9666bede70c5630949a936b5da1b8c41baa84b	14	0	1000000	1655640618000000	1656245422000000	1655641518000000	1655641518000000	\\xf337883e3a61ec21f25253d1917e3eca4bb0da8ba9a8b190ad0a0c1eac8931e9	\\x8777bfd11f12e9e6cc970e4ce3639e53a8e28c95dd71b1252d64f1136e7cf22ae2fe2ef65d9ba1c72a65ddb789a70181592ff5232a92d33378d25837140ad11c	\\xdcd355615d2bd94bf23b0685c05be006001520ac84f7c184fead78b23f67c87eed6218e8ff2aa9608df9792a811e82f8123593ea0dd6391124bc99a68bc8a706	\\x1d58b2abc9ad337262b6c683dc44e809	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_for_matching_default (refund_deadline, merchant_pub, coin_pub, deposit_serial_id) FROM stdin;
1655641486000000	\\xf337883e3a61ec21f25253d1917e3eca4bb0da8ba9a8b190ad0a0c1eac8931e9	\\xdad90d6dc263d39fcb288d066e4391d92e8f307f934585fc104b4699147e9673	1
1655641518000000	\\xf337883e3a61ec21f25253d1917e3eca4bb0da8ba9a8b190ad0a0c1eac8931e9	\\x0a938661f11ca2b6284a512cae4b1a01e5c89e9a5f9cbda49608110ae166639f	2
1655641518000000	\\xf337883e3a61ec21f25253d1917e3eca4bb0da8ba9a8b190ad0a0c1eac8931e9	\\x13137681cde0c2f734d8c2865b9666bede70c5630949a936b5da1b8c41baa84b	3
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
1	contenttypes	0001_initial	2022-06-19 14:09:17.867501+02
2	auth	0001_initial	2022-06-19 14:09:17.99087+02
3	app	0001_initial	2022-06-19 14:09:18.084734+02
4	contenttypes	0002_remove_content_type_name	2022-06-19 14:09:18.103148+02
5	auth	0002_alter_permission_name_max_length	2022-06-19 14:09:18.115787+02
6	auth	0003_alter_user_email_max_length	2022-06-19 14:09:18.128539+02
7	auth	0004_alter_user_username_opts	2022-06-19 14:09:18.138399+02
8	auth	0005_alter_user_last_login_null	2022-06-19 14:09:18.149173+02
9	auth	0006_require_contenttypes_0002	2022-06-19 14:09:18.152537+02
10	auth	0007_alter_validators_add_error_messages	2022-06-19 14:09:18.162986+02
11	auth	0008_alter_user_username_max_length	2022-06-19 14:09:18.1794+02
12	auth	0009_alter_user_last_name_max_length	2022-06-19 14:09:18.189932+02
13	auth	0010_alter_group_name_max_length	2022-06-19 14:09:18.20326+02
14	auth	0011_update_proxy_permissions	2022-06-19 14:09:18.216478+02
15	auth	0012_alter_user_first_name_max_length	2022-06-19 14:09:18.226724+02
16	sessions	0001_initial	2022-06-19 14:09:18.249227+02
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
1	\\x2323cacce95f64054a17a6b27f0c46c75a67511e2586b8be6bcc0f16d5b74a2b	\\x1f77e6009d721c0307ed72dec032c0f14e13e78e404c8ac061e4446bfd934d728786ee20de096fd34943b55c4bab98d3dd059077a957c5c7a688b1d9632df705	1684669757000000	1691927357000000	1694346557000000
2	\\x44628fe1b23ee69049e56354b0a9415248520c51fb6a8da3cde42f930315977e	\\x1d27d7c1ed4300027e2de3b89dfb64e666ed7a5cfb23bebcdaa1b36c214afcd0885d47cf4dd6b9f71d269f4b4348d321ab5dcc0854c98725a7a3ebb78a979d0b	1662897857000000	1670155457000000	1672574657000000
3	\\x85c532e0499b11517a10665c66301831599632bbd934c51a829365d590a774a7	\\xafe3bd45c87ddaa6ea471d5a66a3a038269230ff0904d959a862bc7e0b45644d06e95ae4229fb5270d8b4c065ea45ba63a29d30630094ee1eeddf7ba10709b05	1655640557000000	1662898157000000	1665317357000000
4	\\x0fd09e664b38194f365b1b94f10d7b325b7161596b0085faf57dc00a105f422d	\\xcb54ed7c75669fa6aceb9ed05dda9a555fdf236c5bd032bf097b692591904372645a859f43271c6a61378ce4de478757f0e3670d4cc9ac77fedbe0cfaebe060d	1670155157000000	1677412757000000	1679831957000000
5	\\xfb4430a08d5fbfdcb0e978a79515fb750c6671f7db584b80ef6e3e8873ff5979	\\xce3da1c96fa341c0a683d4e179ff7801e98215f7b9a30700e612b411cc94bea96c7975772b58879fab0d61706f31a3dac09f966f023871057123afe0230b040b	1677412457000000	1684670057000000	1687089257000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\xaaa6cbb8eab49ce0e7403fc736614adeff5f331b251ae9d3a0f0a4ca59fe8d648a4fc3c2cfd7caa14ae1f098a903f0f5c0df5673ca69ac90cab144d2ef484501
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
1	57	\\xeb4a542d360b0d828e00756683f933203da76ac6ceca96d65c71a7cb99cd47a8	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000003680373aa69cddf2c313a189c8745ee5b3384df4bb4f629c6a794feecc1696a41225343da6d42bf072adb766e707dc5bcccb4fef45b43989adc0a2fc84743b5e32ffb59b58dd20b0a595426a07eaf4fbb6f05d143033d4a5b69bebad3ed25e9823d5cf2c62e3c17cde0dd803e562c2e4152aa6b35ef79374d7a8dbd5cc4d4ae3	0	0
2	113	\\xdad90d6dc263d39fcb288d066e4391d92e8f307f934585fc104b4699147e9673	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000008dff217bac8235f49321bdb37c46dc3126b77ecfad5e51dc19f0af0671999baa71846e1574a27a260fec3f75a8413cd099f5a0d1fb368b409ed4385fc1d15f9be32d229ae0e888f85d7f283ba2b3dd270f66f8781e08af124d34240d3ac4e48d16828ab6dea0d7424913680be92010664caa4f32e2f20cf538dc1aa093db62cd	0	0
11	293	\\xdfbdb7f4eeb2063c34d4eb4c120ce4f22e62586c7a4ee2d037462021ee7fff0e	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000009e548151758f039cc14439dbcde6b0fed605c7bd21bf4a66bfca15903e96d03d79f70a3f01c9a626de91a71e0164f26cb3b99253b84a0d34b9bb0287df699dcd1cde7b55dedb6974b8afd412a06bb8f5d78fbe1a37abc5443b5215ced5e0d33eba47e589a3ff0f64b339febb13067abbd5d82e0a3ecb412781f64b2ad55c2838	0	0
4	293	\\x216e1ceff6791b0853c76f6574feb33457e465d94fad2e3fa5dafecd357f159e	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000002e83c90060ed93c83040770efe26331d73fd532cba874188181f5bf0ea167aaea33953ed83f3e848633b13f1d9ddcb78a2620e41b02c365a3fc9ebc34841c8472fd96e4bb0403807e30c8b07b6e3f36c530234435422f1a7f94d9e80caebf3fe7b81290df8f9c5baba3ef3fff2ba543090c2df1ebce607e2a24fca52b9667f4b	0	0
5	293	\\x8e85a27e630bb9f33a419d5422b03c7f500b36e11887bb3d0fd1080e8ead7366	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000003173aa8ab44d38d4f508de4f8a06b46224f78aff14153371c9e3cd4a2f6b2f8139721031d0001ea54cf88d4bfbde940cd50bf08b5fae279506d020a6466866ad472e695acff63b09ab27cec01db5ee1c68d22d213b6188765eb3f9d71ac475f9f81445a8f1dae0ac89928d39e3fa3f7420e23bdfaeab358892f64167c3326362	0	0
3	333	\\x42f9ca46570da62fa188ad50b68e620766b311011d21e3f267d043bf93ea5f2e	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000009d1a3a38654457722967e58280ef17a912c1f71b1461da3ae4b6ed692f67a303195b7006111d5b10625555748966fa3185975a1ac6a46b979d0a62348e2661af422aae901e00b9511cbb115aaca0b23846ddd374a3fe2ef9d76605a5e1957f4551ec1369bba2bbc42492da1bcd2d470480454b822e1eb1dbfbd95eef9de67576	0	1000000
6	293	\\x8066b8abc93de0c8bcc9b6d5fa45657a6bd0cb51277df2a47e7cd73985177304	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000bb9fd8cff28210891133e72a53be54fdd6e365fd00d34e285b2707cdf644e1d2082e21f3dc71205263930b1e26054bed566ee20cf42a2ecf1702c1e6ec6ee6e09babe79bb8d3cdcb3ff8a13a91daa19a6d1024096e81c488b062120937cde0f8b68efdc92f08d9bd7b4057e58a1a872915204678fb1039dd0a6525233752adc4	0	0
7	293	\\x56986e5ebcc14aad7895e3ac7ca5e8946305b938770685c00b1098ddb64dec12	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000000dc7cee7d915780f7638c4432e92d3d69e215c4afebc5952982927f5df8aeecb55443f01613e3a55714b759dbee7faca5229acd453b6d3dc0c5b83afbf654da756a08bff2ac883b0c919ea58f660642862b7e2554bbf955b8a16cd36e21e4551a6c912a87e9efe61830f54160fc2a37177624dd50c4432a879ee09d05ad1f69a	0	0
13	240	\\x0a938661f11ca2b6284a512cae4b1a01e5c89e9a5f9cbda49608110ae166639f	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000006b5ee4344f29438ce1a2ba5f42f8341fbec25943d8541a666728fd5b2c297498514c5f6621f5422394d477f1024d2cc887653212dd83b5943b223bd8d9e2ec88d2894af4b36882be94bae11adc0991c0e8b21870a11bf80cb9ec24d7cfbf3d998be36d568213a86a2535d1025a0f34250f667b70269d9a1383f6f181bb35118d	0	0
8	293	\\xde1b7e0ec87550a7bd3780784a5c258ab86e5c7763a481055ba556cc4fd58a41	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000027cc6732164f250dba06d13e1f38ac4ba65c3bf0461480e1a03d957e9dfa3518275e9f403f5a0daa1cf5b47152c095875c3f3e29e689cdfe346ea276c2219bb7665b79e96378e45408df69d56ed01ad129a746e3bb8d17f9c8b640fcb3081d824a40b635f4310e1145224719cfca8cafc47192d467c40027ff366ad7075fdf50	0	0
9	293	\\x4cac6c8dc22cb26fb6097366c1cc5c4b56fa1680b282e911c7f668b7f70996f6	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000c9164e5a372455a3a67ebcb51c8fd3f77bf54c9f22f75da608f44e29e2a14f6055c45abf1158fe4ddbe8cba461171afb40585595d09100319ffd2cac74fc84f5114808f06f5b73abfeb5dc464059cc0310c0c1b37d5a0562b967f6df2073215b1262373f193f8686fc48d3b46843fe7b8aac26dcde175938f9e036a92854410f	0	0
14	240	\\x13137681cde0c2f734d8c2865b9666bede70c5630949a936b5da1b8c41baa84b	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000005ceee14188040c64f3b3819e519470088ec7df999a0b765d4c131f0f4cd18d7aa3029ac00650010b2cd74d11bf2c511e2ecaf17ab0b3f7144a05576105d14e720ba0a707ace4dd0ac3838b0da024cf277d21607b200da8c4f86966ef8f46f1a6ff71267ac557dc80c0afafaca103e2eb86f1455b014b68d77a82e73315724d24	0	0
10	293	\\xb6fe1e53f197e8dc3a67059e04f28009f8e490ad46b82c4f09c36b38a74bbcc1	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000006557265383718d29d688c9cc3fe5fec6551699a6ad4380008dadbfff9147bb275403610fd67a328157627ab6b2c94bd589a1ef31ebb95fada5194d7c701ce029ec03a147705e57c5aef74cfd5c8ee86e7e546d2857948a9529f5fe827573e2f6f421b3013cb11e718b999aa98189658386405e626d2426d8e4870a2060291ab0	0	0
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x3e551a82672c154fd6890b5e98616a2357edf78351e51d163ac5974648e335ed5e772c7fa9019835bd667fd6e7e77602e9c048db589e7cf5919e8dd9c6f864de	\\x1d58b2abc9ad337262b6c683dc44e809	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.170-00R0ZXV0JY3QP	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313635353634313438367d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635353634313438367d2c2270726f6475637473223a5b5d2c22685f77697265223a22375341484e304b373547414d5a4e4d393144463947524241344442595658573341374a48543548545250424d434a37333651504e5758534346594d473336314e514e4b375a4e513757585630355445303933444e48374b57595038535833455352565736395147222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3137302d303052305a5856304a59335150222c2274696d657374616d70223a7b22745f73223a313635353634303538362c22745f6d73223a313635353634303538363030307d2c227061795f646561646c696e65223a7b22745f73223a313635353634343138362c22745f6d73223a313635353634343138363030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224d52454447305859565358345250595341364a4e515a3933503244444247343546334d3652425a58525334394d304a54564e3430227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2259435652474648544337503233574a4a41463853325a48595339355631504d424e364d4233343544313836315842343936374d47222c226e6f6e6365223a2250344841415a355833483648334b51394847455a5642574545523131505337514752574331524759305956485a4b315935535130227d	\\x446d924ac3616f31c181ecfec6a3d6967a813dd128d58345c2081213684988fa3df4a7f2a607ec38a63c074eb880b1c2c48870a70d4baa39a25cf3a0dd277402	1655640586000000	1655644186000000	1655641486000000	t	f	taler://fulfillment-success/thank+you		\\x5d8ff2e8bb4568bae0b6af6fd1738112
2	1	2022.170-03WD45ZSFFMRP	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313635353634313531387d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635353634313531387d2c2270726f6475637473223a5b5d2c22685f77697265223a22375341484e304b373547414d5a4e4d393144463947524241344442595658573341374a48543548545250424d434a37333651504e5758534346594d473336314e514e4b375a4e513757585630355445303933444e48374b57595038535833455352565736395147222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3137302d3033574434355a5346464d5250222c2274696d657374616d70223a7b22745f73223a313635353634303631382c22745f6d73223a313635353634303631383030307d2c227061795f646561646c696e65223a7b22745f73223a313635353634343231382c22745f6d73223a313635353634343231383030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224d52454447305859565358345250595341364a4e515a3933503244444247343546334d3652425a58525334394d304a54564e3430227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2259435652474648544337503233574a4a41463853325a48595339355631504d424e364d4233343544313836315842343936374d47222c226e6f6e6365223a223237503646455053364637334853314e4d444433374554475959584838564d37454a5a5131475137425632425a364d4d4a4e3730227d	\\x8777bfd11f12e9e6cc970e4ce3639e53a8e28c95dd71b1252d64f1136e7cf22ae2fe2ef65d9ba1c72a65ddb789a70181592ff5232a92d33378d25837140ad11c	1655640618000000	1655644218000000	1655641518000000	t	f	taler://fulfillment-success/thank+you		\\x7c8e6bfb2d09fec33fb6e3a9ca596341
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
1	1	1655640588000000	\\xdad90d6dc263d39fcb288d066e4391d92e8f307f934585fc104b4699147e9673	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	3	\\xf7a324cd130124c6426a996c3e7aec64f5e03cadffdd2ac03ce329b97d097d1eaff6cefefecc7ca28070d07dc630d9b926a3c7cccbc705e52365bab63b29bd06	1
2	2	1656245422000000	\\x0a938661f11ca2b6284a512cae4b1a01e5c89e9a5f9cbda49608110ae166639f	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	3	\\x336f89de26b436c0cbb26d657d7fc2eee0562e74378e85c1eb16bbc61afebabb3694fa64415bbaa00f7f4805ccc7bbd151b01cf0731ac59853f9d9c6de93cf00	1
3	2	1656245422000000	\\x13137681cde0c2f734d8c2865b9666bede70c5630949a936b5da1b8c41baa84b	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	3	\\x5a3e7839f76886498ed6a79645603a9d84d29827aa64f761c22f599ed26d65b2feb7186cee916026da6b52f67163f19b3b6e55b36f3eea6686b2e13226e8c409	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xa61cd803bede7a4c5bd951a55bfd23b09ad5c08578e86c2ffdc6489a025add48	\\x2323cacce95f64054a17a6b27f0c46c75a67511e2586b8be6bcc0f16d5b74a2b	1684669757000000	1691927357000000	1694346557000000	\\x1f77e6009d721c0307ed72dec032c0f14e13e78e404c8ac061e4446bfd934d728786ee20de096fd34943b55c4bab98d3dd059077a957c5c7a688b1d9632df705
2	\\xa61cd803bede7a4c5bd951a55bfd23b09ad5c08578e86c2ffdc6489a025add48	\\x44628fe1b23ee69049e56354b0a9415248520c51fb6a8da3cde42f930315977e	1662897857000000	1670155457000000	1672574657000000	\\x1d27d7c1ed4300027e2de3b89dfb64e666ed7a5cfb23bebcdaa1b36c214afcd0885d47cf4dd6b9f71d269f4b4348d321ab5dcc0854c98725a7a3ebb78a979d0b
3	\\xa61cd803bede7a4c5bd951a55bfd23b09ad5c08578e86c2ffdc6489a025add48	\\x85c532e0499b11517a10665c66301831599632bbd934c51a829365d590a774a7	1655640557000000	1662898157000000	1665317357000000	\\xafe3bd45c87ddaa6ea471d5a66a3a038269230ff0904d959a862bc7e0b45644d06e95ae4229fb5270d8b4c065ea45ba63a29d30630094ee1eeddf7ba10709b05
4	\\xa61cd803bede7a4c5bd951a55bfd23b09ad5c08578e86c2ffdc6489a025add48	\\x0fd09e664b38194f365b1b94f10d7b325b7161596b0085faf57dc00a105f422d	1670155157000000	1677412757000000	1679831957000000	\\xcb54ed7c75669fa6aceb9ed05dda9a555fdf236c5bd032bf097b692591904372645a859f43271c6a61378ce4de478757f0e3670d4cc9ac77fedbe0cfaebe060d
5	\\xa61cd803bede7a4c5bd951a55bfd23b09ad5c08578e86c2ffdc6489a025add48	\\xfb4430a08d5fbfdcb0e978a79515fb750c6671f7db584b80ef6e3e8873ff5979	1677412457000000	1684670057000000	1687089257000000	\\xce3da1c96fa341c0a683d4e179ff7801e98215f7b9a30700e612b411cc94bea96c7975772b58879fab0d61706f31a3dac09f966f023871057123afe0230b040b
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\xa61cd803bede7a4c5bd951a55bfd23b09ad5c08578e86c2ffdc6489a025add48	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x2cc20db7f38de122d90c286fe3954a28cd9d942dd6d849a80838d71c1be3f5ce1325a61fd7b576f139a4ca72b2407922e0dc87cda6e48b58be95c3a77e95be0b
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay, website, email, logo) FROM stdin;
1	\\xf337883e3a61ec21f25253d1917e3eca4bb0da8ba9a8b190ad0a0c1eac8931e9	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000	\N	\N	\N
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
\\xa922384f62eb331b9b0f2567e4144a77be94542afcb80f374a2297a543d63e99	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1655640588000000	f	\N	\N	2	1	http://localhost:8081/
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
2	\\xeb4a542d360b0d828e00756683f933203da76ac6ceca96d65c71a7cb99cd47a8
\.


--
-- Data for Name: recoup_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_default (recoup_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, reserve_out_serial_id) FROM stdin;
1	\\xeb4a542d360b0d828e00756683f933203da76ac6ceca96d65c71a7cb99cd47a8	\\x2521b2624377d34720dc6b7cf246eee9fea257dc3c5566018f3497c0787fd1abadfc41c2d5e345c9e43f2821f0957f9f495887f5b27f46560bc571e22584a309	\\x65aecb66245101c2f805c3f9b5d9d1ad09e0070cb87c25b248a28f43f50a02f3	2	0	1655640584000000	2
\.


--
-- Data for Name: recoup_refresh_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh_default (recoup_refresh_uuid, coin_pub, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, rrc_serial) FROM stdin;
1	\\x216e1ceff6791b0853c76f6574feb33457e465d94fad2e3fa5dafecd357f159e	4	\\xf517e00abbd57c646f62eeb630c204269d6908791180a0d4123e52272de58140055e305abf912bad557369ca785a48fec2342de74e2d898b41ceb5e05726de03	\\x1a555715db8f096f2279a4dcb8e32b8a470975c8eab7d6d9dbf650cdaaa8cc57	0	10000000	1656245408000000	2
2	\\x8e85a27e630bb9f33a419d5422b03c7f500b36e11887bb3d0fd1080e8ead7366	5	\\x9a86a85fbdd0c0696d4545425f1515494b44acee9f592313f61109c608c55ca4488da012f9039ec2913b69735df95c81f99d43bf73de97fa54e3d88c37c4050f	\\x175189bff5a66b6c427dd35c7b5972a08e1801222558354b8afb1ac2c429988d	0	10000000	1656245408000000	6
3	\\x8066b8abc93de0c8bcc9b6d5fa45657a6bd0cb51277df2a47e7cd73985177304	6	\\x90f8f00273023b1001f2be74b99afc1a1868a515d210ff3a6b418a4251261c24d5888d166c00fa74d04a22d712c039fb5c04df465a663d20f0831dc96e97ba0f	\\x7444d17531cc85ac7519faca8a9c509867860be6a909da0157a4e0a77e35fd93	0	10000000	1656245408000000	9
4	\\x56986e5ebcc14aad7895e3ac7ca5e8946305b938770685c00b1098ddb64dec12	7	\\x71580af5b7b43f1f93e07ce7c3ef71f529507edb0466d7e06205d81a84da54eefee40ea7746328ffa78128a326c1574f95fa6dcf6e446d1bb137f9652e17270d	\\x9f45ee93397e518ffecc6d193d71127662516ca246097f217707a9d563f456d0	0	10000000	1656245408000000	8
5	\\xde1b7e0ec87550a7bd3780784a5c258ab86e5c7763a481055ba556cc4fd58a41	8	\\x8e9b8c1c3709d1ebec240056e63711fd449e9b1c94d8dd051afbbf54801220c2233afe95b39329d0ac2cfa9a61e77073466a9cd280ba1d74f503c5fe92e81208	\\x48b5c8e5d4ec038a64ea3c7efd4cd8ec266275a220f8b1c615d0c1d5d1919ada	0	10000000	1656245408000000	5
6	\\x4cac6c8dc22cb26fb6097366c1cc5c4b56fa1680b282e911c7f668b7f70996f6	9	\\x385b50f47ddf8737eb099a9e811bd21e64f6c9a465e4af59a66732c3cbd6d26f0b00e28fbd645bdd069d21f70857f1191e42def4d587883872c9d9ce82507e0d	\\x1f4deb49bb037a23681b5346fc1097d2bfd9c605cf5e48f4703e8a342fda57fa	0	10000000	1656245408000000	7
7	\\xb6fe1e53f197e8dc3a67059e04f28009f8e490ad46b82c4f09c36b38a74bbcc1	10	\\x7e3fc256c073712033744677476e5cfee9d0fea9255edce2dc162fc9841b8307a0ba0f163e9e1fe172b6b2fa011ce30ce110586a4d3d1a0bd292fed553c31d01	\\x1f71992140e6281c003c6edc99ce9cf5f9b37050f6769ded3adde3adadd92d5a	0	10000000	1656245408000000	4
8	\\xdfbdb7f4eeb2063c34d4eb4c120ce4f22e62586c7a4ee2d037462021ee7fff0e	11	\\x7bc3498da3e1ff05830bdf12d2540404713941c61a9bc25de62a7a0f7e30ce76d0f2ab07419c49d8273242e21fbe9490ed7fa27f3335129666f6bbdad25f7102	\\xa66876c3986f9bf4a46bd248594af960d8b9e80c1154a0b9536c1ee8bb2332aa	0	10000000	1656245408000000	3
\.


--
-- Data for Name: refresh_commitments_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments_default (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\xa68fc56f73ead457a1dd1debd09bd04e45271d4eba3af281c1c911efbf971efd289b07934b46d6e0d5945345692c2b44870ecbfa896b548d17b65e1722b4ff89	\\x42f9ca46570da62fa188ad50b68e620766b311011d21e3f267d043bf93ea5f2e	\\x7e9ab139da5f3f97f19700a9e755f5ba2d82c56937bcf738cd62c34b09ca95ee39289131edd495822d051027eb06f311284aba08e7ab27b0c27abd64d62ea309	5	0	1
2	\\xee546e2d4877e7c9b83fc1c79a92cf5e9734cf2a6b9af0903c10b6fc9bb5036742583662c4dc7654eec77b6582ee75002bba4ac5177ebc329ccf6946f72a20ce	\\x42f9ca46570da62fa188ad50b68e620766b311011d21e3f267d043bf93ea5f2e	\\xc1d35e6f45f2ac62b79dfcbabe0e1f2f6ebf1a24855a67ba422097ff93e120bd31119cdb334df56832d72cf8b82abb1afc6e6ef8cbb9fbd8079c039f4f3fac07	0	79000000	2
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\x8d000a1e71479ab24ee4860d24a42ab49976c413881cbe64e9a33c94254c168ded5f8ae61206bd93e91216ab121edaed8480c5bc835c44e87f5eabb0a8c74c05	331	\\x0000000100000100c99a00e9495fbb74f8eca72cffffd6797811cc655360f8b58a03e91f49b65c3f98df7190683c9352442ce64a0000293e853fef42257420ea70f5f6f7872e5f9118c35c2f49b5f6ae2bbdb1fc23541b2be1e6d1e0ebbe2d390cad510ef203cb2a2532ebbe8ca69aa0782fcd26607678104e67391d8e9e50dc3fcd5bf4d3684fb5	\\x8e156c466618ba4c82ad3c22e2abfba299858933109bf2272932b770600ca71eebe6d33be59cf738063207a111c4a773fe94a0948a01d300954ea094ea3ff9d9	\\x0000000100000001110e9fed0626426bc537ef9be0e16aa1553ce8336b915bcacabcfb439d9f97c8fcbffdfdfed65e8879ab34e91acb23edc01dfe0cf6cb3d9c0adb9b1b2c323033b2250df95a1a3256fa43e39c72b58f8c3adeda603db3cbf9a625fcc91186f26c96e9ab705f98b6ed168f597cf27774ffadbc8bbcf7ffedcb2a768fec3cd63dc4	\\x0000000100010000
2	1	1	\\x9d040d892bfa3bbb0031531ce35c8257d2d7e199e5d351dd84eb9858d197b04afc4c9349394cd9e27aa72c9bb30589737aec1e979f11a2c20025091cab53e008	293	\\x0000000100000100a7eca7d57442aedeb3d5916074e8bf7f0d33ca4337ddedf36a5bf35e5a596141ddc7884ea2b53f80831348abe821c37c64650b4d722d4b2a87bdefbc266ecf832769c7f58356018849b8ed524b149a0656365b546ae2d47584deb7f59b13c36ea8ad49cb21270ec7086d215e4b48e0715fc760c7a5e750e97124a706ae4d7079	\\x2d5fd330f683648b11aad89eb4cf84ef228fd62bdef9b9f0ab608e40f3f1e24abd40a8263610c9d02ab13b4aee1db9bd76d60075be6143978bc4a3032699bdff	\\x00000001000000015b34938b71a3f056d31d5f19677fdd866d3027203802d1d385f8b83ec0232f889b49996d095a3ce196ecc114935c5965b42333a96bc205f688ba45a88b3891dedc1b153c79399d7405dfb8b5c54690258ff701fe87fe31167b4ac5d385dbfeb0c27b944f0730619e749906bfe4437513c46247d4553fc24e39156d13a32eb4be	\\x0000000100010000
3	1	2	\\x6fbf0031c9d9107eebe4688fcd16092ef1dbbda2b5b8c94da50e5f3d170e8992c0510d8e48a55492ea9d61d5bc06f84b62355f54cba40fc2b2d9dadfc884390b	293	\\x00000001000001000b3afba4146abfc2ed9c3b42b3cd3970434a44dc055e5feb71d06beedd2307382f500f07b9244775c8b15e4610ac73039b7f490b015ed31b9162401a85c4a2a0f8c4b052bf62070c2000a9f726c32b367b1bb567038aa31598ec1cb2cbf5198b2f35c03866c73b2b40a2a3dc71942ef6c8b61ddf7cd14b78a07649123e2a0f5d	\\x66a4e5aeb4ce29b77f8ad3070d715d2a3145d5d45cff5aa33ba354445b89d9dd91df9b0b6abab4fb74149e74339d591af42194584e37b8e7ffe967d436044963	\\x00000001000000016efd2203a4c4cd74b0d629d8b8dbdcbfb60066a399e72840ec2d55e1c2d9973c0ebc2e7abf7b81cc8a958c0cdba5d82b6c4f5982e1782c69fca87e58c45e557f116f7f6914ae84c208be4dd82087d9a9643fde7036ec92b18dbc5b7af7a87d52c429e4ffd9df1f2a769e87d0b66f6d24cfddf5641c32c2a623e6ecc39e301283	\\x0000000100010000
4	1	3	\\x39977b5188e8c53d0c072b12e9fcf99c6213d679af3adcf515a71ced437b0da755429aaca7c67f39948f0ced12f8a0cf9bb4cfd0488f9f1611a85187cb6dc708	293	\\x0000000100000100b52f534e7d04034afa7f04536517cad00d62046c3148b368777603e08ad532b14eabe498f09ccaa7293202cfc5819bd7b8b2d40871b424ca33cf63a05de4d06ed6235a9907221c711e75471d43ac2dcd1cb709b7091cccbb6a3e30358d10e374bf797d250d32717e7eb6cd8ac389268be7923cca4dabe497065b57c9f83c3225	\\x459f849bd9713cf137ffb08f1fbdac20d23a727f198709ce3a657d997a2009a3038289b8ce8f3ddcf86583b7629c9df0b78662fdfc973dcd8d7916d610382e01	\\x000000010000000139ba98586e1466f99b1e59f648607be96662ede72eb6e2ced098afc66a3143a93dee804c9e0b2688bd42a1803841398aba1ab1e5ae9321f33279f98ffd90acba22ecce2eb7d7c037ebda0dc24aa7242b64256410e913e4c53accaa3d0fb929342f9bfa83e64a881c48ab5a9f13f4a25172ec6fc37a71220a66843189f63033b5	\\x0000000100010000
5	1	4	\\x66ae107464dc9a5c1a3a876222252936699a84543e46be953f159247412151b85f5dd998b497eae318a71e27f335989ea5ab4d7203008095371c0f95fa43f30b	293	\\x00000001000001006f63c1b5a04a9db813b772eb5678d03015a23c987b75ce6b2aab96ce850e55bbed5c0886da73a578bf51db031a04e80440a4d6955fa38cba5fa1ba4391fb6d3ae6e396a3cb0906bb75d79b6e3ebd9b29ea87605c534303bf6ed4a2e89fc3f17df551e061ba8dc3867838821a7f5ae48eb1fdcd9b7c6d3b90f2c06d0a324da38b	\\xea05a4cf4120e8839e16facc5b2ba4df324de04c4a0715810fd4b1e5cd30f4a66922b1438e5ca0b0827b842b53ad732037b841735d5ba803460f35f657fe88ba	\\x0000000100000001c6cd4a2f2c4a350f990488048c2da8d78fdc9453e4e6a32eab83636590c119988d7f7e826f94d3b86d9f739bafafdab71e896964512d2f9eb1aa7dbbab7b7a664ce7b7122686994f408c0d1808eff80d14325f06eb06372cc14f124cfdc780b49120474ed730e33be69cd7a0bc545936c2ca3425e10ef7cbb3208a4251077363	\\x0000000100010000
6	1	5	\\xf27353945ca6512ea37158b178475d7635af5017c34e2c85cb7f8969bc8db254dbd549a6dfae09c7d672ca202991ed750c06a9cac153601f3391dc0659dea108	293	\\x0000000100000100496e165e69525a7357850b6644ed404b8caad436eb5b6c7645ca66649af2f6388e1eaa9cedb0dfe790e1dbbc1305f051be0a315a342cf934299f375c9c962bb0610d0262e9cc4a201ed4f8598e8be9b4edd9a090b2d9f03929bd4626c5c4af651e4ef81226a02533425eda352b421846db20d24715136231cf0cdd2f5e398320	\\xb2a483fdc559cefe18ee031ae5ccae9b31f5a4813b12160056e24a42825a21702be47696c31c49e8bf6132b325053342929ad471fdee18584439ae5b193a442f	\\x000000010000000167b28b489ce39eda3856a0b476f8e5319991af144db80a90ea60162e7b1d86eb9820a353237670dbff9484d1220a043e69b9166acdb869acb62145a9c8b25051cc119a77a9a913a1bd26b14ffe611f2bb87c15953aa2bbad52bc1653efc7ec7338e9b25385e66ae888e04ce5c8e65ff125f120ac9a9d838552026cc3a96d6e5c	\\x0000000100010000
7	1	6	\\xe8ae1ea31b9fcb5e7fad242456b436709e370fb8362e7f882561c346ff223b8aa47a2d50ebfc483878ce61e3843d89fa96d2ba78ac067401075485e40e87880f	293	\\x00000001000001002208c3807b4974bb08e0d72ab0798383265a92fbd8ba98e1f9e3fcd6b042d663c58e9ec23de0d9b7e449c1093aace937a83a7458772db04f0b1a271fd8d74e15550f18a64f679071f19fbd6265913e1cabc56835da3d1268e039eb414b0eb0292455cd195b9db04c958f972e137c7385bbe1404edea6a45db6c1ae92810177c0	\\x95fe170ddd36e5af11882811c913b1af0d13439b591c29b3cb7cdae7590477c317f1817c35db6adfec14244aec1a796a42fec25a4b57ebc3491562c478a5bdb4	\\x0000000100000001500f7c75e4d278546e3c4e2a4e65bac500b8292f52dabf82f7b5766160762b85fa54d52ce3286202344532846a700a62704e06cad3ab7f1308f114bfd0d51e60188a8cb269c483e56f4ab3a8ded5a74950b439802333383a2ad58a0bcc095c1e460b1514fd151b1a6f4d13c0681e626a080027183d2ba3428e746e50ea25245a	\\x0000000100010000
8	1	7	\\x2140b5db65dda22e9065c2544d1ae5d44745a6d2ddb64b25ffa0072a9e85ebb3bc5a809cce4492f836071dfea4cdae784354810e2f4b57c2fa72e3b8a8945709	293	\\x00000001000001007dd245af8af2bfd675b9c3f72435313d59965eec4a188fe04c6c3cfb153949a6ba5ec40ff0370e249922e324532791bb4bb8ffdc52290eeedb99c4e0a985e5be96198ababcc950adfee9d1197ffe2d5bc1db3455d42826fc70d52f03654eee037a54a78bcfd2146b84dab55ad6e56cea00da129be226fea1e2bea4957812a9fb	\\x88137a60ee794093cfec2c724de1cff5acc7d20d6d81786b5d81defa553abbd0cbf21e7fa145a59b271444b556921de59640494008bf53d9a28baf55c8eaaef4	\\x00000001000000010537af6a6dd783c32a2cbadd84f3b3530997cfc9c79ab0679bda2bd8aace893ff5867da7968cb9a94e463242598542ac650aaab72f8f19ae02c433afbe1f3c63aad39d0cda1ec107894d41bd5088a14dc86efedb2c443ebc9eddb9fd3f83a6ebb032f781ffde7a3a00c5b2646ff916ba3a913a7fbe6a5d60e225ffec5b3cac0b	\\x0000000100010000
9	1	8	\\x94fb44cb63dde84e5836a5f5f164d1c6617dd4a62e0eca717b4b4b72144144c3e3112b275a437965cbc1c603eeb65abac71061d367f104d3104d7d3c0f711b04	293	\\x00000001000001007b49d462af6e467c7788d07aa9a79b64ba3553f6342cd122a2f0f5190f83f54f4c0ad301c4812704c422c0d3d6ec64b8e3f20d7870ae54dbd7a3934fc04bd99e72928120f71d3d26eaf831c77e5749aab170e984c0933d9bcc18f4cfbde0475c419f4e2a5951a0e5dd49d41a0f39aba93f2c81adb0d0ac024c815bbbd05e6a5b	\\xec11952e0735f655db2fe096b038452f5dc129ae86c75efe5ec69e301d2215b2f9f2beefbca0b0450793bda48832e9bb0434333b19fc4cbfe7a49f7508ac6127	\\x0000000100000001196cb640d90be3ddfc57ffc2499fe2a85675cb68ac0f1957e0f87c7fac6eabca689ae798b04283901887a370df8c8944003e0968d6e9eafa40d6297a791ca331ab23aa499b70f5cfeece60c7436c6cfc7a3ed5f04e3fe226542d5d99d4f5160edfabfc165e6bcbef0f730ae055fe91317bcce5326f142740b5d649415a16e3ba	\\x0000000100010000
10	1	9	\\x830d6902d35fc0c6d7686f8c9db654c9518feefb433146e63b759afac78ff475599c59136e086d8f8b11c292f376dff4b1c4793325d0f3b3ff1f585276c5f90f	240	\\x00000001000001000977de9bf0e11eea965657c352a384697b06dc510f45a394bbfcf4cf6d430739587618f49ed7f0122fcb21f0bb43f865d5b82ac89464f40a93264d26a78c046f32675591aa85f2fb1e4f3531e7c3b4e6bcc0a77bab82000d4ac4e20ce69d9734be023f27af7208fd066050bab33dca5bf4d1737370510e8ca0524d73ceec6e44	\\xc725e375ade1edd8533d9bfb31a83e9a83d6f9f2f60ca2a197a66ea7fc320fa5a9140f6c767cff7d4d4882dd308e132728ab65872e9bd5138378e926636d2079	\\x0000000100000001b5c764d624f8ee9cfc496a5c8ab4de50cd6cf34a3ba5e7c41f590aa3c34226f6babde182aa8e6c58b96872f107abd8ee288d674c8bb1f347ea6cc423db5b5b1cdd86f7006f46631c6d3de94ab27eacfa5eb87cd5afad9f719f0fc9b0a2df5f89c1d2a7923a06eb392cc51f1424c7b640329c7a13837524060ee420fa5daecfec	\\x0000000100010000
11	1	10	\\xae3e9f4180da00b1acfd974b4d374cc332becbfd8f46cafa2c0725309f26f6bdb69c3eae736e47d3ea24b22504ecb0bdab191a960e81ac69974c5b8f9563390b	240	\\x00000001000001001ae50faaf317fcbd3d2efb9a204e93ba549b4a25ca01d73027cb012d5df690c09a022e9cbcda2646d495d714ad711c8e9fcdc9e949ea5b3146ad9729824eddbc4036fda9780ea0c177a585ae08239e91d8e27f7a4b02bc0164ffaa8282b99d553bbe8ec323f3f5f46ea7851c84b75453ea2eb9409314be5f877018e82888114c	\\x1c3ab312cbdc241714c089a0572e4669f683ad7dc2b53039cf934c4bc66f5863ee358851b1f5641e7bd2a3d5310c7f8a8fd49828df4f57b2c3ad9eb87c0cdc04	\\x00000001000000015cba2df6107a709f17a33079769ac47083660e319862cf5acefc576f4f71a76d2d425056ae8d31ff8df7205fff74e624d8bd44febb15822eed63ea1dfab67bd72536d87e7929cfd1527348ff99d78f88846ce436ba0c1b1a6173cc4e02bda61ae6e7b03d54e8ad74ed47d7ec77befabbf385616aad11cee7fa1ea983cec83ce9	\\x0000000100010000
12	1	11	\\x3055b3893d869a9c9f68229b308323f41b65c9466797a57b3a5060e8bf6c21c5144215f65a209968cdab3fd8e09676595aa7a6c63a381aec8a0a5d59c332a507	240	\\x0000000100000100accd4c6aaf5c15096abb4758304a3a65955968a61229c146ad64cd84799d9c75069750c6d45158aca44e43247fa2bd51087ca0b059d7a28de72c229f968b76610401e4f57c97abec2760c697a192ecefc984b664a56ddc55c6f7d0a55bb180e8cc1040135013e93ea955d7be8540f7f1f70ed5a0d15d325ab8d079102cc53163	\\x5c3f9a08ed3ccc80422b252abcb6b1de1c6b4daadf243e31258e94f0634eb0e4f30a7a4e0d265cc4247cd9201f30c76e93af62af93b127cc1216fc826f426155	\\x00000001000000013d6c7b36a45ba6e9f081fcdb2dde30b0de4a40d5d3f273c548c142aa9fee7da54aa1433db0e01aaef4cf571de668b23aff2c39534f2a7ac2f56b3822af18beb4025e6123d9ee8db6637eb597ad1011dbc58bd2326aa5404538035a84dd2d98d0217491557f221384e842b377993c3a26498826db4846edea878cba364e273928	\\x0000000100010000
13	2	0	\\xb8d874e91e4f67546556d853cdbd331d3e9cdf03f5b442f6c16a9fb1f215c36fe07cff2c8373a41df3ceb0a9b3f76016319355772e5af6119340736a855ab90c	240	\\x000000010000010079999f55c460e2c6125f327f5c0a66736eab5ea247c11df4a1d70d7207ec2dcc392b5144ce8a939d8b0c0df1fa1624cf773341be62d56374ffcdd84c8133a8dff847bd2d9f3256c64aec1150653b9b6186577e36c33ce1ade38215904ad4b16aecf14d772aa85f34bfcd41131c11d5610a12675e0db1cd7a75ac6a1f907a7263	\\x389c13c678b8c36af10907ed7d3501b267a8243654ffaa36926e3a50db8f06274157d927d0d37c8fa1f68d34306e8378c8ad3bef99e0e4f55a46b9a0cd840984	\\x0000000100000001b16b5b9b10148da945cdf4338be6e55d5678b388ed6b3da09e1cea8b3d53428cbbf7622077bda538201380d9f755e3fe26f80c5fa0fa88358ffa795cf2c3ccaca96851fc787f93dc1aa535d3fc5c7f3661cd02351f63eca2174b6d3749be48bd27bdd180ff4cbef28c082c7eaeacafc6183ba5ab4c22637f6ae740decdc1d29e	\\x0000000100010000
14	2	1	\\x9647e8abbc21dc09a54f088a0e4bd0423a62ad419d6f91d8fae5a469b7bbdf494169ac5e7b2be012fd35da48b2540e5712a60d69939abb0205aabaeb624c9407	240	\\x000000010000010034bb038039517434715d6c8e59bbcadbc2fa1e6311857edf0e98beb13e95d9a7b1bdb8dfef42d43247b2d9c12906d1c94f14526b210dac7d2b4380e445d8b9805946bfe95bef95d2ce816b8db44799e98b8bdf0902eca3c6de7cdaa3533c220df81f38ac31ea37eb9ed22fb232a8f28d7a0581779adaad33dbf75a9eec6c7600	\\x3c7dbbe835036f1274316da639a64cc5d580f5346d8cd5bac2ba212ed1b842543194a74713db5b10c1f006a64cffbab8a4a62e6e791d8fc6b9a4974605197902	\\x00000001000000013ef7be1f4b544ca10ae3d43682553058a4925bd3bda0bc3bb158586d797c23b9a935fa0af580b3ab1dacb4cb332891d97ca3bef01e38c8a7a52f33c58f626931b13d6f98d8ef1fc3b41d90e07a7e89dc9a1fa14de37c98ab5193317010b554d81bece558c09d39ea5aa0ffefa1387706b4df5c7a056a1bba6f006955dcfc37ae	\\x0000000100010000
15	2	2	\\xde24132f01fdc91a7f575ce4317796f65327f277bbcf76e8da37060685fc0a6f644109c1ea6978e2df6902e638e46f7066e8d08d523b9c9ff0d823eae7b13e07	240	\\x00000001000001004d02823b5c55cf64962baa608f1e6009162a952207492c37f0b4541f62489f9e03fec6fbf1b2e5a94e7d33a9057a9590e715b02aa419d6bfda896e8e444a7ff69155798390d652a8aaece61ee71a640e1ea8e4975b9bfcc28aff1cf5f2b4f720ede9814788ff91c0d296d804f32dc3711c29371dc163811af432cd567b4a58d8	\\x5b59d96d051d9bc892c354c3e00a5f54360accf78c61d048a6251e669137db69fa1e368d4f8f561ccac8ad52bb6116b2c5159613770458e979b966b12883e6d2	\\x0000000100000001650e70e6bff2147f16f4cc7445e8ed978d9dc8da718fb61ac95ced049ba89865dcc3eca7f8fdc342678f29612571d6e859e1c2916a320aeffd17174c0c4abdfc739dcdd4ebd350f4c435de84a1ec4d1caca34367a2e61a89f4f2e7b0220131644d6dc6f44f4ed1715fae41e08e17bc30622d6aa5acb0c928463d55f7bf3770bc	\\x0000000100010000
16	2	3	\\x063cfd01a7db812ac76b8879419a6cf86f4b1c1a05445741cfda0787d75736d9584ed3023f5b8c16827b25a2b8077c75795a5ae909b85e373c4087dc31eb400f	240	\\x0000000100000100184c1b6e2c0192a409fc4b31acbe56cc1e7e99588097f2ad074291666280c8bba10e0b1a9d3ca38e91843de171c62ea86054d017c02c45ffb460dbf81ca114c166cc138f6d220afeea5adb782a0855c268ebf0e8617dbc27d94d29aa6f9c3f0c9f44e90ac2e9238fe1910fc93797e3a06e57d782f1bd16049dfc3fdda421ea47	\\xcac83a06debd6e9dab1c3b01a86de91e68c9270e6ab4dbb419d2994346ce43d8b92762f3525ff0406d9c2d6f84670587714ffeb9aeffd1b6c35351dedcd2045d	\\x00000001000000014a4caa4546de02bb51e8ff11d4b4408dc8078a413aee21b1f97681050d639fa6d6add1c364edccdfaaab7d4aecde363936ebab4813073d1a52835333adfcb0f4581c9b1108ac47e768f5b8e4cd69f6b87a5690a25f9068b7843fe94c9a08c77a65a441e5ddf8855135ea7a050a586de0ea3599b125b353f9c9e3e3b75e8b1c52	\\x0000000100010000
17	2	4	\\xa61269f01cac69ab24eea8b9dfc15da93949a845b7cde6d0d0f5100632af3b64e87fae7983e8ee42d68897f43bb2ef21e32b8173b81374bb055a1e41e2d56202	240	\\x000000010000010096ac673322d45d9488b6a13be402b715bb5de09c203a3cca3b18dfa9bc154c5120f8c267aba3adde232d3b20b3b284611a5427db9b6b14954c18dba7fa5a18b372371aa4131240ef26b267ab4853ae50736dff4d927319b23b50bc8493335b5f6704b9b2f8ab4776cb6ca79ccb194281c545b33d7793b0dbcb9aac1a4e3569f7	\\x624912ac14636d47af2b20376ea080edccd890db07f17b403735acaaa05b014d7ecf2607171b1710242e5b196fd941ccb3fd378624e4a59db427e594f859d831	\\x00000001000000013ddb3e812a218aa69536451a25d9aa9bb857f5494e5b5431a31a18d715ba2e33dc310e6c97c0a83be95fdb7c61fa3544d65429814652eec116617453f42ee79ab91c6ea5ee6c85bc148d5fe227f2d4906ea4522b1d28f880c99e2f5f00195abf900eaa20c2f3e24a0e0ead28b370cf62e49f612fcbf2232c1760568069e18290	\\x0000000100010000
18	2	5	\\x353d9386481c8e230283c2b3ca91160034d0c97236958c86d7773cd38706d7419b66665bd79e08cb47afd6f4fe5c99d3d71729d62c2359dc7aa92630377d7e05	240	\\x00000001000001002dacd9dc3c9b5f902a9aba4b8c1e11e4bfee4a77c87c605d55ba0921b727e56ea64056a9275773585d05f63d8c44a4476bf561d3f7a65ddedd9e2e8876b941c73c6293978eab84bd165ce804e59132654df2c123cce7e0e88f95527f9c5c32ffe3442305827724e0565a336fb44a988f84444f81ec390ce5293fab7ae5a92c9e	\\x8a84454c54f6bce03b35608ae2e67f26d56399e299547a924357be470ba2788ead1639b2b33e5047c5ee3d2b4b936691b2ebf5fadb435fc9a3a11e555efb0617	\\x0000000100000001a0f2322b6c1ca570ba24e5407be349567e50f5399ffccae588fbda1b98c679414494394b53f432c6bc82b6368d69b7ce452ee76f77a63b0af8849ad1661c43d355ed9a995fd85eb4fd81319fa8d3978f2abcd818d8ada8b3fb8063a575ad9b7a2e3b24609686894f37f2514f5f8e42ae46dbbd52dfe2a74c765c9f0874703f14	\\x0000000100010000
19	2	6	\\xac7003d5b76c0676c416e7d8b43bf36b6be8882d00d0231346ed72d22a8a40fa95244d9bb6d1d3fd94ee1c4fb4c904b559ae25497bb0545220c03de8c43e5904	240	\\x0000000100000100202cf06e6cf63e0c2dea402082c06a9b24364bf72915d5bd0443540e1a8da5526b65a10c89944d160eec261f8d6bf1766e2d321176f6cda071b6de3f8b9518e9bffec1ab79ca2a859f95f81fcf2a698b80a75dca1b68caae31a9fa4b06a939dd6f4e0e88c914908dacde76d0de4d69df36427a6ce9a0ad303fb3940913b9c209	\\xd5ea8c5f1984cc7ec2019769355bf6a24016e443fa982d4bf938f3eea3c4b23e7dbd72e77361288a4d48826a136ef9285a4146801f34eb823793f7cb2a01a88a	\\x0000000100000001b3960fd72a8656926409d6ce17690f1b9789edd9f19fa6f2ec6ac12c6955a448ae937939b9c6b83d503a9d27a66e5dd5425641959672b16b611a919749bfce235eb25e0f7847c9528a0ab25f3fef24b983641c8971f65ca35af1f75c01280d67c507b4d0bfd1bd0c9bee7335b8e233cdb862c99707d6d06495b7b19c81e64283	\\x0000000100010000
20	2	7	\\x1a1b505bf0c7fcf649198debd888d1dd33b0ab93526c65d5f7528d96d1c7d0342e00ec1c4bca71a2857f81492ba0a01b4b395fa07f37a04032bc6cdd57fe5c0a	240	\\x0000000100000100991645cfbf79e76a04ccd9020619cf9673bedf96d57f93eca8c6b03b70039694975096d08d9d11cb9a2fa3dc4ec84c06288c436ac37eb5fc3dc6dee7d0d7a76967cbbdca8753406553b9230fcf4229dcc1d20366a9fa0b6dc25da6722f5a36ea5632573dbd2a7331219d2f7016f65c3bea2ea0ab8036f3b58ec74962ea7e3d80	\\x71a188f14ea9b2534aa5df1acebcde004d10addcf347bcda755b2d5dbe034be83e0404491aaf6923de6c886649c276921ca732fd08090730e397bddde337c5f3	\\x00000001000000011d21b944f55772f538f51495470d97a5e6062cb5c67e5e1d326b1264dc8fdbe8a39894455c36f74f981d6df084c4f162f12ca766515ad8113359009dd8a7fbc5d8146518508b629902cb2e192b7db1be72a80127cf52cfe21c16a0380cad8a9562ad6ee727e263c7d46019ab1f100f600118105c062aa434dd27c38da9dadd46	\\x0000000100010000
21	2	8	\\xd00539124c8bc9dccfbd5206b67d2403e42f91a9bc53e6fa63e729c9621d6bd172a6bb947f88e935a869f0de934a38c49bc1800adad768cd64c9b2b355b8aa0e	240	\\x000000010000010054ff190bdfc0689538567561bda3c096588402c61ee7e428c0678d675bfab54c107908069c730f731ef19a2c1dc7f3b5bfd9ec9cf88f5625312a3d961ff5b1534f1f6c2254297d3bdbdc8d25f0de137954c87cbd1535eb782504c1444f6d0cf563705f38ba04d3a822c31b16fb5d65247411fd5d4577e449421ea7d8f87bc182	\\x7d2dbd9af656d3f34450fc2a7e4d17e1986d10d4da47bc72ba912eb56b04004f9fc2d490d05c9d21d2a79b074dd8a72639afb7e4bd5981af56c13b5bc5661adb	\\x00000001000000019216cec8cc93a7f00e3e1d0efda989c3f117d28a9aec5aa7f99d52d3254799c327312bd15c9a53876a51bcdd7690425d720f53bd037856041751d3130cc7041e373ffec59faa04bc53da7703311a906c02e11e640abec24b41134c1b95e9c1e28cb1511ae7173046f12660a991d2d5b2278d4435ef7b491a9e3a5ee5960f233a	\\x0000000100010000
22	2	9	\\xc1f6a10be4dc6f4644859b3e336b281f65d2bbbc1ab7e578b8726e121005fd5fb1957789b72f8094cbeea888030259e551f548b4267c2965a4eb446cd1d6310d	240	\\x00000001000001005826ebcc5a73ef73fbbaaade2891943a5a7297a7ccef111e84feeb0aafd09788fb99bf6f68fbe92afe9024a3ee6eaab3e19628f9bc94b323a536de75a39ee66daf46f1f71e13551d225390166d4b407959e284c795a9574fc7cc72406dcb1820dcd8f07e40d0794f276e1ca2ef9c74cc534b27e75201b321c2ef76e86bb7d903	\\xecaff04ff6bc06248ddc748ce0de4e1da799c5dcc13c5a19039820189b7bb450ad30074de578a8763200cea2598bdb7d81830077243e1f946529e7acf489002b	\\x00000001000000019e3885748fd2651c6fd4e80d97833b5eb3311a5525de3e123997a540b24b220424401a43cb9831a3e0ce0d611e9b5416d967c404176bf21db33e68178f2322568312a7c7fe63a58d6a7c4f0aa015ef4ced85d9088ef30483d8ee622202b554ded01ae2982533669da06dd78ce4a55dddcf79f2815cc3483f6a3204d449db0c49	\\x0000000100010000
23	2	10	\\x98c5ffbba75ed404169ad411d81f7f246fb757e471f5a94f4d8070e10525ea65f06222830c4fe7c4142e500334adc45afb583dc71a305ddc66e7079d88f39400	240	\\x0000000100000100d0751fb83925413df61e30cb0ebe178805ed32bc488a10ada9f7b92164748281599a0fcbdca43ddf79a40967b2ea59dfc4d59c2223b26ad3fa2790403884e4e61c9b5612cba4f5514fffe2875946b0b1b7989051884fef3052eb780ba92325e962f9b5c573d72cf9550eaa97dc3b11cc28fc7644aa00457e1a8cfd6faae3398d	\\xb69313ae8933d101c0066dfafb342a546849d70b248c7dff5f67a945fc896ac3096cef4d00bf8e637d75b04033812d291bf6481d2dec82b8ec21cee46ad454b1	\\x00000001000000016f82dd54e720b205f18a2b6211dfb06ccb4c17856bea2816af7b669bd2d7416b7d03786791f025ba9a83521c4121e1b59622e5bcc71d217c82b7931a22fa8b27fc6930cfc120c088fdf69b9736af2db6f689c070929e3b0d395ba3c79e3a0f79a902de4e22579ae657ece05fc53a5934d0820e9e04896869cb9b05332884abac	\\x0000000100010000
24	2	11	\\x6deb57dcbc4e02234b76a23acae07ba0b058404d3aec9b5c9105c2753fccee9294d3e1694d88f6dd5fdbbda687e42af9fb82ad4b4e603144b5aefccc9041f90e	240	\\x000000010000010022388c09c817ce8f5752f3ab0df8cda328f216f104ff23a5a07efd9924c7ac15a3922c4734461199c64994311a5fef3ae7b5defd022c2be17dda680c5ef5796f7d79bc4f402211b4850c1318043a86810f7fbffae6c5a41ac0ce53354253c9cd2e2ebed6fd252bdaa4ee609e90966212bafa24b12fb50e201b9376dfde8cea6f	\\x35aa4216fa2fcb7f79900111d64e81436ddd039e469ec852df59075b8e8679b1e32fe1e6d25bf9a1f6567656bca45a29905fde98d0881b3e82d26c554b63f247	\\x00000001000000011059871156305133139e24d20e4f35ba08100ab2496c012eaaaa8817e15c3eac5f52bd41ebdb6a624ceac7026e7f08bae9a92358de783af1f3654043351cf24727bed215faed1dc8205ea2cb659a26fa95d8cd9284efcd9def821e9d191c63b03ae018074320d1c78f8e410f0a97b3ef37d10311cfdb5e8bb9d101438a8f73c2	\\x0000000100010000
25	2	12	\\xf6bff200656c4eacd83027db2dbf02e39c288e30cc8838e494731f12f18860672d5951cf188374b40954e476cf4854a0289da6339f2dbf7ed152f38b9719ab07	240	\\x00000001000001007d15ea68fc7591c55b15e2c77dc2a7a0be516a3a9fd85667693f82631a5a266304c793b4112c797d9f41eab64f37b4fe138da1b03807ced0f8d8173d9efbc5e8a52196f1b88c8e5dbe7b3047927f7553f9b055313642e3971cc6ef61b388f188bb711b22c5c1101e59892693548912fff86e2514b01c466444b7b174a6e8cbd5	\\x335b2505bf166cde02128c1361fda0e2f7deaa4174fb51c22d73ec7242d96b638bd1442f7442bd7997aa032503cc1f3128d6672f38ab8ea3c9d8354af49563cc	\\x00000001000000015f8f831646630058c76da93e13e98df5a29f0aa3d8e02bda2920eb926dd9a4f7c3135560da70d966001039e87e75e136f350e840869f6b8811d510ef848d0b1d2ab69e093c404642a3580e0f95fff0a57dd6b77be1f54bf233b34436cd290c69b9a23c54f417f4d305e7215086827c256a2ac319fe78b538c3998bf7f7fb7c10	\\x0000000100010000
26	2	13	\\x895f84f9fb92a82604d6e59cc294bc977a952a3d99b29a5a636e02e26e778c32468cf7488dc4215218b5f76ad987354be95cce9c8c0a3e3213190a6cd0d6230a	240	\\x000000010000010074f90a2f78d5211fcbb0afa8c842a7c7eabb8099ac30d9123d8595762abb99e267f1d311455363a041e49902d1104118d05b588e03d9105b2acba08a73885209e9fd0ca88a0fd708e0f50ac0e1e460f24adc62bbe297f5690b75e30cba6698cb2314de04e5409b616eed759801edd24eda1cc2b91689af161d55e772a35448	\\xca2eff057047fd04fd51304fa7c7e322eefe0a07ea9919ec3a3d2d6074f292d0c7a9b872fbd4967b690201489c9dc26da57ed77fcc15461ae426a9030c95ee61	\\x0000000100000001c0b0112551ebaf1a6358423b96d5cefcea40c59815fcc6af97c250474da802550f108f5be4a1d9b9f9eeb039c7164edad02be4e3bf4f53d796c5574457827dafcae43baa7aca33c0ba4b1a7c50609ec494510ed34670da289b53d550c827b7e0085c0c5ef3e02602523c5008d18b415331e5c78a6765b6996f8c9b104ad6f2a5	\\x0000000100010000
27	2	14	\\x7059cb0faa53b5fae7a134147c99a96f94cb7f5d47a4d81a6af22f7d63e672b7c4ef0c1bfdc22d4c706d0f9a8c693a368c7192565239b358e33660092c53fe07	240	\\x0000000100000100a47aae6db0e7df27243ae446bbdd1fc5bf9043183ee7a460f3b379048f22b8e76d939b478117f4b5c00617c704fe9248de0ac26308b80599d3047a826b8b3c514e385dbceecb7bbb2c5188755e1210d82eb6ffbfc80b887bbabc2481c08006096229721ce20e6ecfa876b6cadc95d424990e9c25dfbb690804974d32bb7b8c13	\\x6e4720f6867a7921d86f91471487ad07291a96141a145bd7552885fd602242f8da26e356d49521c76c78c8e3301c9edadc247d8beeae072a76b73baf88722380	\\x0000000100000001c2d8f413812df10b7b87026a5c521995fdca4911a976f990b119e9198c3bf67286ccd2fce764d5d53188a6fe23507643077a84302a85af5b6fa63ec3b8bf316a3c09835401fe653deda539d693849b10eadb63a980bec3cbad0f68da2e233c2efdbbdf1974bd86c47cc6f34e3f061ff0505fe0fbce7358f8a14ce7fd86eef06d	\\x0000000100010000
28	2	15	\\x46da0db73d44fb34d7fb1c31a509629a409ade43c182fa4ecbe436eb8cfa81e6962c9bfe65d0e33727107be78b0500536e4f48c7725be24ef5bcf388799e7202	240	\\x00000001000001005e21226472a0c5f8a8b9231f443313c3bc37a35e3b7d6b088e0edd3437deee43e54df1b7ae51ffccb8f1035b20481918b320b040deef41b8c86560f187910a0be5efd2b126dbb6d01edf0a98073b25935256119a9eee443aa32760bc721105133f1af3a5d93607564c58fe8e74d3e70d05aad05b7ca3c69d962fe832e5af7d6f	\\xccd0fda3b41154eb9a7a509048ecdce625d09d6192e93af477a76747c20b52da949f268b35fd6b48071031ced0499c26cff81dd0e5e12c9148f95b6fb6dc2f5b	\\x00000001000000019092075aff8e7741451317fac1c8fef66f0ac59bc9f90636e7ada9ecac1025564dc2699814cbaca5b397300aa213eb189e508f9b849f4e665b7af756d036ba1507fab0314255118d50c2d70b7ed023ba84d2dfe85dae2776bc81d7327bbfd2596872ac61c274fed831ed867319c08fc5ac86ab48e8928eb95e8501e5373116ba	\\x0000000100010000
29	2	16	\\x442b686e68c8fd6a503bf5e1cf2e4ee2ef017e8a7e5efafecb01b46b116a77a600be6e17333668c16573679fe9d2860ba08479907c34d44fdaed5322716a3205	240	\\x000000010000010086b81c643dc48e2428fbd4680b451bf2edb481df96673927f7d1614ecd4d40bb94a799a72ec6b2d00c588f8b67b59e78f1c639c0b82d749c3696d935630714e09f6312881b8638d175d9daf6452fc40bdcb5cf44e724e3e855458db0fc3177d6e9e2607f6f1e2881e4293d70399bffe9c92d67c9951f05ad64f9a917290d062d	\\x43924f8019f8e384a617b7941e81a23b76dcfc60d2af960ebfd2a60a05a7a9b6615b64cf227237959c844e465430f371c21ae532f787b6b2b091047c775f81b1	\\x000000010000000170b9d19788970902c4af6f6ce207158c613e0f4174672c74238b11944803a68f4fca20edbf31fa5a76a01d05e462f86e69f9bd65779fdb299c4d32c92dae3aa5a0b74181fb96472d1be810c19fb8532206bfb4387f2e7b556c2d4de06bc0d7b57578aa6ad4d73616ac21d16dfe11dde9096ebd473e6094e2d2378bda29ccfb34	\\x0000000100010000
30	2	17	\\xe707ae6f38cec3b08ae470ebe6d70e105ed080c8e6b1e56e6b0d7e475a82a8d6ceda12141e71dc3c162d30c63f5011388ecad80b103d49489754c46472b1b208	240	\\x000000010000010013c9294ef2bfa12884a155c730c082cf00d249ecc2eaed41dbcc50d1d9ded59cc09b4669e74ef725daff850416054bf04f44b41b77aca818878784e2bc43ab61cd81ccf928c9180223759ae893324f1c291c6f3feb4dd17369cf4323c95a65b9dc5c93dc1eaa9f770bbd5786def0c7642b5e80cf1a0db9deb94010e28eb964c7	\\x711c9f9519ec419ffd1e6b411c26ac69eff151fa1dcf61ebd0041efdfd55fdfb7fba6c03485a6205f9d0751210dd942d0b7282e70b591040d7dba5cae90271e1	\\x00000001000000011431e2d77ed942b11783de48a09ff9aeb7f0593b1f5067160dbc2635f223fe14e8877e9c2c7a2b78191523e7f78151fae46c8edc468293c80aad63680d2dc583fe4521ab0747d91b715a0a318007789ba5292d389ba5cefca389835f7fa8e1688deadd8588015087c2de6678c65476641af8e5607007c0efd289579827ef23e6	\\x0000000100010000
31	2	18	\\x4b4ae75bacf7e398fb523a162060fa5a5e0203919c8b4a280a6ce2432aa74d88f05ebb0ab38e63da2216d8abe9709b0ad9385180c04b5b360e415e475bef1b00	240	\\x00000001000001000509532c9eee882b5641be9714cf0381694bb7fbb6d50a29f452f90a046d925ce19a0bee445d55c30f38c8ce21b105416aa2df1387ef0a3706bd8866b4cab646bbe769c86cdf72b09f79f590b6ba6b35d952ec3b1cce3d750e8c4aa8c6d8720ea400de717be389b68c965cb32e60f72e32644870e188d2161f72e2e5138d1433	\\xa0b67c058203ee8efc5d95eee49ad70650aba05cd6dca629139fcd6dc085785976c154c59d44b48895e2f03f8f9a2772c1462f7e78fd54d4708fed8c1d0c6e6f	\\x00000001000000010f065d6a0eef1fe2cf99c2f915438090fa1edeb39ab8088e5a3bc1dcb802c6959cd4abca202f7eff5b3983a0cbaf5d1a31c1928ebbaee4e08c360d799c3a38c9d1ea930997fa33b7e9d440dc3b8d0e7c7ed2a9ef32eebf95a04937286e2b8b7864ba99b129ee312cf67bcd0bc7db5b942f1ea4705ed8f65a794cf0b149fa0635	\\x0000000100010000
32	2	19	\\x1df11660e21aef86396677d18fe9a61c5737b4a1da49ae03df44b8440bcb3254aa7a42f361f9af22b07cc8a70f020fb708f1624d683b97e062bc2c884ec6cc0b	240	\\x000000010000010032a1d5712b8f462574dc71f4cf109481381b5d3da57d1d51f4e3534a9d3cb9656a7b3fc141c529d469e3d6ef704fe5fae1ea70105700ea2ebc33841ef6ed7e627aceba5962a9484b69beee627eb1c0fef50b53a6bca2ff03be1dfb4534e1b8927f518323261e5f772ce10f0be733b37e50757621efb826e55f696933fd750e9f	\\x18fb59fe6511a38f216ce5c66f64794b762244a1511f69caabba2a19bdc723c83789de4c36b2d9ff69ca046c2277508c28d8a16a922e1fb7c14ade5251586c5b	\\x00000001000000012a8562305bef742a7429cf21cec99d9d643acdfaf1eac99a99e349c86d8ba20f588ba3584db5b00396b6701af048d716a8202286266d7d133f54ddb7721ee114b25c4a74ab69b58ca27cf899a70d6221f6d9c7de15a48bcde34bef66e3792f7df8b43a1ee8d53857062491178a8c7aa37fa1a41e5e5117579f0f1b3f049e7d9a	\\x0000000100010000
33	2	20	\\x03337f95b20abdaad4aa82fd333c723eaeccbdd9b3d6bb5eeaff513953ac60fbdd585d0f3d74e06823d40e5ab2f43c9d8c18a87257a7551d066484803903d304	240	\\x0000000100000100403bb4ee6f9ca5b887391fc51b9c5179563744b0a55e8ec43a2d0babe14de37928988984c2984548560ce95b853c7226cf181fdf30a8557308347bd4806c0ec4894976950d964b6b085b58567874e5491b7948f5deee178f44124e81c1d88d58ac9c2c74b0c25a4960ab6f9e1de6dd8428c17dd6dbe768cb85315f817ac22d26	\\x20398d7c2bcaca869a788277fb9e877735d2f33046abb2f5d74430b2c1714fcf271ac75c0b6d00fb9134542c566e880fffb3150c8c72c44d78feaba95105bb63	\\x0000000100000001cd8f39c8193e69017ea70b7aedb36e51adaec16eb2ef54622180126cdd67c9a324c4aacd4c0aa5398fdeb332d107def7aabfa22b3b0bd178b8b1c1494a1c16a3ac873a5f084f9c0e7db56c98612ca2efab19745ac8ac8f13ffc7dbd3d8b546dfe59dbe4212ce6bdf20f3410e8b50051088975ebc1eb1f781b8d5811d18781eb5	\\x0000000100010000
34	2	21	\\xa1060be12e5c96fc651795b8183427703b268b5787bcba8f4d93a8b36cdea09dfff4ea6f5cf0ed691fe5c342325e78aa787137913900c14a07d8f8bf0fab8704	240	\\x0000000100000100316d57b97d0c840ed8452a14435a12eb7d597ddfc6fe36413eff08c904ecd52570785dfbec4b56aab92bb2d8f5e997fc28e10cd7d03e566ad8a972267a798431e07dd770c458afc11c1dfc26350cbb1c1769f1bb4ceeceb99738a24ebb9ad70b5d5f02a623367441059c8941c4f287025e52e35bfaaebdb217fe4aeb385a7b94	\\x79f6b0ffff859edb2f84a6f29ea1a50b68de656e8bcac75cb36aa5c06b6fb0ef31c8fb4b081fbbe9455148e8397283e5200f552074ead255aa9070b32ae929f5	\\x000000010000000179db9a044c7e4fcff45a407c66453032267fd5675610da45bc68e14ab5172efd9ac7ccdab6b7005f96032189ecf27045851b89986b1f87b9fef51de8a1cde1da58a9bb004767bfd9b10cf0acc27609e8e30fdff065acd904a5b4d4576b41fc54f69173f3fc5a1c1f16b32a27a666c2d91bfc06dcd3696602f38a78330bb558e3	\\x0000000100010000
35	2	22	\\x6f3c42609544974a50d09f41b92f536228c7f92fa14ffcead2d88efeb011b27de0f8db897601d6ae47852cba2d0386a3f83d513d1f674ca1f27bb106d94ea608	240	\\x00000001000001003fa606d1256b2acba34f830de5154c55f6b32103d0e6d67d57c0ff7929220bd7b5fda27cd99fd52089682d4e45c4c9a12607f2ede002ca7ba4b44ef7d071701d9992c04f3fad65dcb5c46ac8712f97f3a033c57eaff842dcfbccc26893bb3a7c1a05c876404e45ab1026ec72123151144e12fdef617eb84fcda4fcb9d99454bd	\\xca0e8928564123197d99c9cdc497635def689cd2e89543848d89fd699fdb055d9bd5d20bcaab76a03d988635910395ff597b65d3de46ed38b94c8f8443050124	\\x000000010000000143114b50ffefed1d68c0ae27725300ea6fd19110455175d0e87c065c6544267e8353d9aae810020e741e6cd78efc965fe603a42600ca99b0298ba05c38f0928cec8b29a428960efba1e7c7425780688e4fa961b6df167398080f4687f3bb2eec5e1a708e5b805f11b49457d5ce2e74a57942a4cfcaac5580c6a2976c172101d5	\\x0000000100010000
36	2	23	\\xf71c4981e29eb342a779967493cb41c92712738f1a9cc7d9ddb123943b0dbe202aecc9d05a5d56b3327fe9e0f89e3dae3ba36893b4adc89ce5499bc14ca23b0e	240	\\x000000010000010013b0f074759a5fc7f2fd5d0b66fc7e3d50d76ae62bed1bc4fa69e90f77c0f59edc377faf2192a1b0b8a52c51d351ea8fcfde4cb2a0875ec4ea6de17d7f1fccbeea49faaa622e4b4830a91e7d632d15a5d9cd871edd9f7463a14c24d0c5938bfa0d1f47ce58b0f3ed5bd62f3ecc318967c34fa1b77cab375326a4e9167a852438	\\x910c52f7980fe1e37dbacbe6fd79368a267966bc6ee93c7ceb282c742a327e8ec42088b525f98c1ebb56d7ef24dacc1fba355c5aaffd8dcb369a61f729ff0c82	\\x00000001000000010ef64cd0aa16de75ab5d5d61359186f7eae8c01f0eae996e0596928323d539041a24ff4bfe58918cc3fd05fcb2197ca6f2414a0c2ec656e15f7819cd5059196fb972466940ef8ee98f11a956cb774cfe738412e11f49b986357b76dcc7b27280695fec1256e6ca9ec1e950ddcdb95db1ad648a1a5d29d69ab0c29302ea41a79c	\\x0000000100010000
37	2	24	\\x0222f5f615a3b108d25ccee2b1f42eb162dabb82c2a7ea745bfb2678fd153505aa236ffad2d15aca3424b1299991f412c69dfefaadd9d54b00ffa00e7065dd0d	240	\\x0000000100000100b0aba0895c166fb60bc5c5e6af3fb4676bd0515f8afe38fa1150fbad72bcde5db153c51d6dc2fd2ac3d325c33c61558c76147ede0637eaff327975620609db38c850aee87f6310390a2a695a18dd2d2f8e4f0620ace13645f7936b964f0e8d57199700d7e29fc962d053953262fefe698fe76e62319feed87fb33772d4deb397	\\x6ea77cc84f5352c696fd1d3bd0bbb228067ec54994965bc5b5c5c5680849082457f1c408bb2059a0f338be63a334592bfd03df621ea75a5a4d38b60d2f7db785	\\x0000000100000001a9956e689cd943ed4bff37f97b88c3b714b9e834290b6f7dc4cdf28929ce8a14108ec0c4528a2e7761dfea7a410d0a12d3e784be6446b9e74febdc0a872c072036bb98cffbf5dbaedb0c162df765a2e3bf3eca9016fbfe606d62bfbff2833b3c593b416df38d8e2b89a65e11f4123c1373dcc8655c1f75c439e9bf4159e0ae35	\\x0000000100010000
38	2	25	\\xe397990e3ae1a5f22c4e0d209218fdb6bcd0d741d23b82459c5a0e8887340bcb08255a9e5351391e5f85590f3381c728b5b9860d70b169fbf0611f76e6e73c00	240	\\x00000001000001005c72c27cdfeaee65ee2bca47f7a85d25c4ba4adabc3e9f154576e7d951fced42ac93cc15227795956a3b1a45b21e1228e42691190c26dc616b373216f4f6714a6abc51b3c8f2d9c061a095ebe1117de01d2bf312a8ace38d828bd9a8cc2b89d7c7c94e76ee1e5c47ed6a797381402f0280c5d51e2302e0b644275efd6b3161bd	\\x6f4773a971a41b18e7ea2207bb1793063be2a9496aa6af4b9e120bde5fb1b81008d41c42c6cda80f7863e5944513bfc6d3644c2d6df24b38b132d56d7f636515	\\x00000001000000015a1b68f49ee7e7c7c2c678acf64a4c188b3d2239a5a158164910f06f643d5c4b15fd289677e85cff3381742dcd98be1096af5468df9aa8e2838d557dbc9881a509a1f520fd370be21e444b2de1bd807d17c84258bba694955d5bb758e8b04630eae97dd816a4d9dc610838a183b23435405f28def51c1f37a6493e71aa10c5d8	\\x0000000100010000
39	2	26	\\xc1ba80ca80f38576b342d3c4c05189b449cfa0102a07aff3a5ad2e19194df862c948872a97750e59e5a71449976cf360352f8ffff03b56119ab1fd26d066a00c	240	\\x0000000100000100c666a195b0f88f0b1684891be03dd3ec0eb0edb284cc99e70b5eeb619effb10fc7c5888a73b10ab17b4472153edf81e00a796dd9141f3248a14147cdda7d92db2e820f0c8655894439d9659c3cfb9cb9645f20fa1a71c5f9a8ccd770e18efc526bb3267d11affd426bd7df61b27bac9da652b8df0f27f9e3e48d91d95cdcf534	\\x782f12315d98754adfb4bdd0ebe1ad96fc9858ce0aa8bf896d38ae73d753934fe926a1d68691fde4de46343871e27696617416e36293701b6f3bf29077f6fc21	\\x00000001000000018f10fd007714855d97163be3acb24f7fe368f7568afe23514fba0839a10c32fb391198327cd84a04f32282b2073a28910a62324580736dbd7f1c939f1d10793b299d92947c39ecdc99152f885276d7e00d57174063d732c83047da2008c047dc38a9201174e575135c35c7c70bab403024e4e8257f41836b5d9c3d0072f89b38	\\x0000000100010000
40	2	27	\\x945943b7e1d3d37a2ace7c3790d824b9f7ba50ba9c2d091795c923bd7701330d2806f9abe2ab8c0b23fc285b9a1f03dad36cbdf15aa5dcad34194ebd6e944405	240	\\x000000010000010058b1f85bfe2316044ce24bcff8f89eda5fa427fcca6b7076dcf60718c47141356042fcd5df97fc8e8fadbf29d407b7b986fb81606f6e84aec825ae95b82bb4b90abc78217e85651d0c03c4bb3fc4d1f2ecaac78eb09d6605f879c3661a1f7b5ca5b5f5a045f45229785490123808dcc2e89c08c8abd0ea42cc2fdc1e3ec9b7a4	\\x6a145e202d1a6a1028d306bb8ec0e8ebb019bcdb8f14226dc25a593b1f9dfb2b5bc09e0a108e334b1190acfd72034ba39b4d7681a6dbdb7b21706e7e91024a1d	\\x0000000100000001a018a452cdea6d4450f1058ad791827f7b93741fdc9e1f5085272446ed89a9f68d48591ab3a5de54375332bb235438d78bb0e6219ec0d30c75f67ccceb1409236cf59aba02ecf7ce1465fdd0f59963c0e8c24dcbce4ae89771bb592975c5f3a2d32f88f599f54295524fb5aaefbceb8e79ea96aa57cab10bf266d951f32d8cf3	\\x0000000100010000
41	2	28	\\xe00c47915b2552eea894e85f344672fee5f3effd0584fe904ed8bc8d94994b748e6c983f345a045a08ed084d493c68f8dea369842816c68ac6050b4615d5cb05	240	\\x00000001000001000a170634778462a8165275e362d67ef460e02e4ae14de163802a75cc353211aff1785edae1a8a235526f0d7b0672be520c1143ab5a6e4ac19683566044fd6d6f46fc93707ba4f845bc60193da734a8fc519cd9849836b72110f95c2efcca5e2e4d4c74791da214bc720fe24e4f3b9ccd60aeeec8a35008e5f504133a7509adc3	\\x296fc4c5f4f8ada17b8d26cfd93b8a1b7a5ca7f74ba9335925d6aeadc26487242b97c68eda683c06f37afbf83539dc96538a197697334bfb911db1c947ab1a12	\\x00000001000000016468b6e1b3ff3a9d65c402e833eb096586a2ddf2d5e1f2bc4b2d85202711bf883bac8290ced7ecde6589ebf09e550734473e471cef18ecf1527bb53df37e565dda9cc617e3c500523e90aa48d1f5e2d122ad21f52ff4cf3e9df710a60eba1a8a2d301d1bfa18fcf34aa04b83562a934b58a3545deab19b3feb31ed8dc4f4d26b	\\x0000000100010000
42	2	29	\\xd940862d94e01aa97c7d53439bd2b7e0c924556de2b055b289ab35b9f40c032e105bf522552757189f7b3844ee6ca6d8f117d6370e471dfc9052371a07c5740a	240	\\x00000001000001005bae312f1ca02a030ebfd3f68ac45e50911ad1666561a3d0a58bacb132ca1e88c6fe122447391e8e04b688e1d90226aa5a786858f9b62de3c32a7cf66df2ba29123773d10167b2f404c547288592fe65c14211253c9f77ad1efbcf4d7aa85b0b37b1cf5b33fcc220b02e962c4da1fdae1e5985f3af542cd04d5821197f9712f0	\\x206cf01ea8876c306784bd6d4cf9d753be5c8c75aa2bac9b4246019366439df55166bf4517662877f3176bd47cfb2f757f45ba11908092947990aae88fb3a317	\\x000000010000000123f20517b049d016d3805e0a6b1ab3db2779d3f6cba38730b6173a8effb7041f2f4d1c509712145603ac357976abb2cdb878de2be4c347ef15f312af57ab121a5ee05bc9e9e22992eebae8ffb9001cde59227c48b01d26576b7c87ad6d56d2d6f5b0732e8e504537fe2b036f63e9fbbf0ad0f4820ebc464d2daaf3e846e82420	\\x0000000100010000
43	2	30	\\xd433c8036e5421a401faa51807e7f810af598f5891a0642a379951e579fd66097dee343cbae948a7d5ac6ea27d0ad4671ce0e5b753856bfa93b530d5ef0ccd0f	240	\\x00000001000001007d92ee7e6ab87fcb82d57090f1d3c1c390e5aa1cc32333432eaf11240f81cb70759ce998a0c1ddf5b23f61c8c8046277ed40f2802442623a0c56a55a6fc23d02ccd40d9864e3d9dce991a8e572ce4d3e23f3c00764702d343edd244da998e508df3bb78c9995e45b73fe523ba869e5c9ecfae3794c8120dd25c52023fdbdb8a8	\\x75546ecd0b9c79e9dee61122c9457f7a951aa11b8bb492f7f1e9a720ea64f8705db333cd62333485917a2edb85bd23abda1f3e7424f0013062df906b98c72eb8	\\x00000001000000018eb19253e5461200d940b57d729ac113b201166140a592eb1cdc7fc2fdf7d9eff19b7622263345066e1f9de9dece27cc493c64c9230a9d368a354dd500618ef8d7aa9e60d2bb60da417315e7f99744a0b682bf42f8cb07e0167c21a195243d02e451586342274601ac6b0090e7211d0ed403228ba49fb579d6a7c7b48b377aa1	\\x0000000100010000
44	2	31	\\x03ae5d7ff956739d41ccb500b6e24dd2c0004a16b5811c51bb914c6e457f9e3b6fef8bc10fcc5ed4f232f245ba683b233e600c73bc509dc6bdc45c6332bb8308	240	\\x000000010000010042fe5c1b4082cf1bcbb77d830aa0b28e5cee23cfc676b03fbdf08be98892127214f2d1ee249c65f37e4149da01af9c18c1afcabc3e38081583e0a944b094b9f159071ff2eb05beefbd1d93b15a9c486fdff6085152b913ea095eabe18d01f56aa61adfc50470eb574f8a8487b10ceed749f6838ae4843808dcac03468b1d0297	\\xc13b87abae4cbe1a0e53f30352efe6a4f497106ddb55a9216cf8019274f26968738292ac1f44ec2332cdc7c9dddd5c229b421ac5b9d1cd56df638521106dcb96	\\x00000001000000019fb55e0fc361cf6fc71631857e33a09f2f36004125c664a76708d6ca82b06b23a205fa96ca8665e277cc28c5103ee21799109059acdf48a26a607ec4e1558a9aa0a2a587241060bb4b7b5dbaa72bb77c608ff8cbccd2018ebc8531ba5ba2559cf4d6f46b5c43888e4f108665cf40c48276cf75497ae0e68ba953fd6c73238659	\\x0000000100010000
45	2	32	\\x88fc4d15c021ea56ab506a29124983273ebf5a5dcecef2d2d392e310ca7bc28674e2f1f97d77fa0d61087aaa2d39584b47dd9c83fc0a49f982720bfc85c2980c	240	\\x00000001000001003acebd409db25a974dd55b354826cf4ed0b860f3bd94ce784dbbc03a72734880621cc17815da8cc6f23a32eb385328ff546214e4a2d685167613f629847d7ab3452f7ef1008481204c89d87b45e5554d8bf577f1a0538d2bc3d18e576992143a5be2d91726b200704a5e88c4112ebd6a6f7912ec08cc4ab3bca158969c15ecd9	\\xafb8a48224205961bf13f927a548a32599dfd1cf4837f673b37195adef9d949833ec93b126cd74c780d509f721d25d9c73b77ff649f1f47b1e6564158b32adb7	\\x000000010000000167e09d04845130d25bf18f757f3dfa6404b207262063ed22ec6ecc1c7e7ebc4cc76bc786127811e4fb559a338fcfae479e22829bd5e13d51f00b68a80876cb6f44b9318bb917bf625987533882c4d9f393f37808c6567f95556eff101df50ba172a9889541854b3082d99fa622f17d383435770e04628f685f545881a6752855	\\x0000000100010000
46	2	33	\\xd6edab2668b6eaa34baf1e06efd7ae583ae924d6c5b600b8934d54c2d83c3850d9e310b02649e47ae4950ac46bcfd57174fe8c302d66e31562c3b10913dc300a	240	\\x00000001000001007a2090bd0bbac7f6aca6dfc135422951a5e5b6aa2c63340735fc977dfd5d500694fad6395aa62343d63d08f0474d5432b114e25597259fe1d64479e5bb4d856527d9ab30e2066a2087524e3c0cff07d2ebaaad8b8df810ec6ee378a2628c55eef9e7a1bc2bded673c940e27f77e87437c2d054312047a6bfb1153dff1cf27d10	\\x34f5fb65e88e4a5a6d7090af7f6d351fef10e1ea0a02693b056cdddf6e46323686c2670140e7bae82ec0f702a3850826b226835a29d11a95cece3415d3fb8ee6	\\x000000010000000126a1170fa2106c92587ef38a8a0a4d5052e5b2f5b384a23221997f49d97c76f569c5560c49db02bfcbd8e4cd8dd8b28fc6ceaef052d8306b0af0414f7f8ffb535ff0b00edc9121566bfcea9439b0946a2031b18f265305082477a2dcf03808b356495b83191710aac7daebbdf20ffd09e853dd28b2d176cfcbd8e39bc71797a1	\\x0000000100010000
47	2	34	\\xfffff94f32fdceac63483c5020607444c813c10f83e7dd9b11d2eeb5d46e5346f621ff984fac50d69df8fd8bf1f5facb80d8c011801e818434431ebc5096a203	240	\\x00000001000001005de332fe66a07e10bff206dcf736cb3bbe6e8aab3ea7e126e7a2c354132936b8666f316dfc963749bc1950db312f95748665e486e635f74647b2fba374e50475281b1a4f182278070b5e0e65cf3b746c0241b1b20f289cf11acd10f014a9e6216bc77208c0252efcd18d006d70df6e8e4d918e2796830f3048813cc715e61409	\\x0af39040e84d3acdee68f8926c156fd056f5484f2c40b15c39a14661340a6579b9a307424d34fdd1a7c378f734817c2d2c3f5e32921d12416f00cea472515dea	\\x0000000100000001ca2a94f49318ed1c9d46b4aa4b03bd19bf119337b4dee9c165ad4ed49d594838050396c84a55af06d09e4cd31ddde74d27102108d459c4a05b8602dbe81d1adc0a561b562d97399ba1947cf1a06ba00796f67a018ad364bcdb533c5a24d5d5dff43e1a0a8c65d6a05bb56867646cc222ffd4b954c858947e8a52d75714c7390a	\\x0000000100010000
48	2	35	\\xf6947d991b82957c4edc283e9b615e109ecfc0dd3aff4cdbe4a64d7cd99f8ae4f65fa1066462d731aaf66623508533f953a4fa4e02ad54337ea9294d69778801	240	\\x00000001000001002032d9be7d2b58660aadb12c82524a77a737eb891ad921e2961a1d2ae813fa2c2e6cdbad166ef0255a91877c074f5fee80a8c8978fa2dea69d82a9e6f3eb8a917b35080f83dc018a563bcd4b689feb0d17134f6fbcb315ceef6dd385acc64547eb8fcb1a55c7a21dbc8dc286428caa5c317191561b95d0820fd7af9711742587	\\x25048ced31ca2ca2ba8b9325a3d2c5532d33931c3b96135d22c92e5f592d59b5f526922df2a0b390a1abd7ee2b92b85e106a8d57986c05213c54993f738a5203	\\x0000000100000001c0c7a8ec897c7910d48e85e4d26050510550159d28098ad4053a4e8fb5abfe0720db45d9170fa441edad286e50a2294b409fc7ff7e54e411c8a046b8df38de20dc39b4c485e78da4556f3b35b72bc4e5415646a60ec6d001a5ea974cb05d20730bc42229564deb5417766d4f38859ce78adc50be37b75b2decf6a4f7e24ad342	\\x0000000100010000
49	2	36	\\x3a1272ad23c295fdff6d075cd803e7d52a0960a4688541207a77e9614df77d8587cf30d0d254fb31ec9ec2f9c1921f8eb59d952d151e1b3c9dd3658c81a3d107	240	\\x0000000100000100ae2ac965d1fba4c93c169c7549db748e3fd0ec4b7807a1bcd366483333c0a91086047ddefce6e32a2944f0978996c07028c0b898ab02fb3240709b454c0b20fae8afea2dee9faf0bf425ad9198477a89da67b1a4140f766b8f751a20d81303baf0bf9d1a94eddc02378adc216068573204aed6888874c4e61f18e268f42cb0f3	\\x47037c99e07f661282c2acc8314c8b3aac9d7dcfc61cd7d677a2769705b1f38397942fb5f886a8ac6b096b0f049c3353d278646b9948361f9119202e428ce5e2	\\x0000000100000001b7ef9d18c29973a8abc6846ce3bfecb89fb103d20750668aa9ac6e63300cc05d88a4e76e618e9365bd441f6d0e1d10e2b267191bf90a05ba9913bc143e6d3f8ad636590d2610a07a2583f183d3ae196ee56da9c486366485bfad1e9fe3a4c0f3e657b3488d8aa16512e3e915e8f477178f6f2bbf3e34992be3dc894f3c304627	\\x0000000100010000
50	2	37	\\x389221ff53d6d07dcb91e242553aef6e7fe510d1b444ada7b63bbfec8d9c28f735f8f89d03b87adf2df622d67a8176638893199335cef37588364022ba58ff01	240	\\x000000010000010019553984c4ef07b1c93d540da328096d8e791a15dda8f8879282c6032b44f6876875b483744be82c8b16459ba993e6ccef307ccb6214b06a139400dccd379fda7ac91410f101f84dd276a1e66b6e9781efe0344b7eb2926345ea0575865488cc1c2c0ea3ea362d3d1e2cd3f5241f92cbc8930cb6c9155aa7d3f05f489783798a	\\x1794c2d24fcbddfea527cd95320d3e900855052e590b54e20d538f42286fb19d6ab50f5b566001649999d2502672007af8c3d781ee29959f1c790905dd6f5257	\\x000000010000000151090942899afb42a200ce6d0ba01df9fd79656d7172702eec94469dcb8c4e4b6b7edaf9e7d22ee298f8d5e80f540a9168aa35e5a30a8c541118d5550011d90edddf3a2454754bb797eea706b84f53787db82e2d6c2436c91c00ea200df6e4532f5a69b44df1fb3c86fb6d351bcf0ff37f70edf09ddd8df384892a12787ebbec	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\x0129756951c56d84ecd5a5af7d655b06a89e52746410b56b14e5d8e227624f26	\\xd689024c991c9b3a6139e3c0875f1ded910f22f9199a8cf3d9f87168738a68bd0f0406fcdd90285ed7dc2d7260b48b1a2c713a4aefebe3654c915c4d15efae23
2	2	\\x361e5de57998416e718d7c651475274d64d6c384d6baddcf5966fd145ec7196b	\\x624ff293586f9e33ab6ff72280a2d652581be70dc37d61b2852b972204a0abf927e7954ff193c9c417ada334469301cffac41ea96c293aa1f86f551cde0bfc65
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

COPY public.reserves_default (reserve_uuid, reserve_pub, current_balance_val, current_balance_frac, purses_active, purses_allowed, kyc_required, kyc_passed, max_age, expiration_date, gc_date) FROM stdin;
1	\\x5aaaa2e7202039e47d6d231071b430487230bbe44fe03310fad120f43a1fb363	0	0	0	0	f	f	120	1658059784000000	1876392585000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\x5aaaa2e7202039e47d6d231071b430487230bbe44fe03310fad120f43a1fb363	2	8	0	\\x1db2fa56550bcb94b6d488e373484844ff4e47013b00ce57df739290a0bad591	exchange-account-1	1655640570000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x11d1b66bcf52042de4cacf76b9dc02060607a58557f0f847f2d1d97102aa0b381ccd05f2f4a5929e780c5e1dae0f5073b08bfe1518ee99e15dcf296d2504621a
1	\\x852467a9b2b862c2ccefce1f99b0c28aada9804a6d5bfc3a01e8795dcff9fbcd1b21cded3ec9d20ee0df272b5738357d685c1323597b00ddb24d0586e5c560d8
1	\\x3e44fabace5fb0f459db6045de962689a6883771211a99b104e9f5dc1f6286e634fb8f3ec55e88bf6126f8100bfbfae0f0ea2145585ba17862af301947bd72df
1	\\x4fca019753789ba83083eb07b2653952d6dfb47c11aab24471b4621898fdd5a73080d4c28a4626b293336252a35e499087b25c0da964857c24a05e942babf83c
1	\\xc118a43be3715a9d1469b8a6c211fcfae0a447456d1ca95129a99afb820b40222678f819bc358930c98b77fe6dcbfd166752781eeec564fe18f3b377aa7ca4bf
1	\\x8bd14e0caf2ae43d4877b46893c36d0fbb57006103a18c36dd279418d443c8d4794ee4b0faa1258df7aa5db7c20cb6f5791e322bc510d443f13aa2cba0948046
1	\\x1413046d323a5bbc884d5d43a3d055314aecf35440d4753d8cd162895e15c72ca76d9e2ecf1cd4044b46bef63c9c7791c179b88d376a018920d09767f23697a8
1	\\x22885831d3d19204025b4f2497ea0c1af8ae59e3b40f9fbb6a6dcebb31c0fc000fd2790805188113f0148f0a1483ad993d2e2fed9080187fd122cd914a49d26e
1	\\xf38095bc89c74ad761802b0deaf0b7b94dd3e6ee232353e5053dec1d5eec8546c3e969a0e86d4e7ee0d2c50f80638fc739aee9827619d3ef529e40a4ff5c8626
1	\\x61154adcdd414269ae78b7aeff01182402af547c82cc15d84dbb3c5c5831587ffd1eebf04a4da78f3d609e77d18884c69ab5e03425f3df76912ac7bc7413b754
1	\\xe623ac096b83f861e2f707ba71944f25a4dd232f80e74da2cf795a7c1c0fc4d064ee9e8a930b729f91ccfcbe2ee2edd20e45ba12b53e60d3c65e95055bf1e977
1	\\xd334ba98b8fbe0fb6a8df73c2727f830571e0e5880facc23927ce7c04b08db25f61f39273c2e0d1c0561b9c055bd8836215ff278b3d838218b591474f327b23d
1	\\x3b49d802dd9c3e8b8ccd79b58f92e1b81b8ebd0cb8ac41a3cc66c0cb00ae7488236d752636757960157e64d10343d54f8fe2a6783e3908b4ab90b3aee2922865
1	\\x62255d8aa461a9b663d45c4d7e20fcc9720b68e56b171fb90f946fd662a606154751278763d500e0f872d35e31fe39902b7a1824fddae47344feb41c42566cdf
1	\\xbdf0d832960008b6ef619deda9b8692853b5bd5c048ef2cdf2f3d278c30dc0e4de378e7d6d0d441888a0e43c66de58a19f3229360c05a3b3be62ab93266a829c
1	\\x6b8b894e2c7d18c957f39b916654cef04cc710b54ea850933e81076316afffc84475490366fe7ecda949e00d8bbc88a96c51475292a3c8713014aeb24b09afe0
1	\\xee8618b0e296c9cc7e340ef86cb34e55bf0660476a16da6093e5fc27a4a7e2167ce797fba31cb01ecddd194fc6775e66b68938bbd10bb01cda27fdbd4ed32e99
1	\\xf768888a9fb0fb709c75dbc50731c1367d31cb451f5bdb1d8943d401e2fda94e69d96b172f5faa660ac5c332ef8a983d66791e3261da554281a326fdf88323ea
1	\\x8d9e557ab5391b42598705ac5aad57777b32bfb58dd3bf14e58c46b6abd80f85aa92f87ba8c37f7632dd0a6dc0f3901ca13239260bcc6462f0b822ff57e192fb
1	\\x977ea0d13e9eaa39d08be569b33a25b975aaf53d7a5611646cd9401702e8b835802b53295e733a6af93c4c0d0c4528c7b5ab0180795802e95c007fcea5999214
1	\\x4ecf6dbf58e0285bb95a953602938788c904b5e1d499c6c17ece226622808893ec8d6201bacd9fb94a32159a05879e5f93dcd03f0fe69a824b20c9640685cf2d
1	\\xf7e6f4d36dd9c3bf79b2d045b25063b7c02175d52749bff822cd221d307f4574986eef4dc4bfeb5f8df6fa95cfc1a039f1a992b57bcfe25054b910b9f0b5867d
1	\\x4f40e4a013d6a6e39a29a046d694035cff0a039eb6fb69cdbbd614c1bdc93d1edbc7e66e96e09857f544fba053810f71ee18fa34e845d54838cf4c8d02dfb496
1	\\x033dec4b2ebffbaab4123fa00bba226f6e615c5b1372d0c44a9e106f6904d55a2f7c52e7f06207e6d15a4314f5e15422475a1d55d98a4efb662128c0f058e02d
1	\\xb55545c1457a869bfd62efb837eef2a97293aeb9a05f6b3a9df96730aef30b14b9e2699fbf549c1782976396c3f231d625e8e9eecb67c0e7d458f69a3c813944
1	\\x210dfb838a5c6b62bdc636c8ca6958aa8d581c2fd5f6dce9713d4aca873f1ba9fad926738249b75e3c8da0b6eccac3ef49d859bd43dabe511a4ec7adcacea23e
1	\\xe4d7c150ff14772a9417ffe332bf3b9016c99a533b2dfb5a79b7b48c46c0866f1138caa151c70b723d6f3dfbbbcde636d26b834616ce54507ad72c3d1cebca2f
1	\\x125e1ae7aaf3a596c6d2567646981f1e8f87944efa3eb3abedbe77051fc30602428a880852395b0d38e2262482dc4fe1c3df58c220224e990a9139dd64ef7733
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x11d1b66bcf52042de4cacf76b9dc02060607a58557f0f847f2d1d97102aa0b381ccd05f2f4a5929e780c5e1dae0f5073b08bfe1518ee99e15dcf296d2504621a	333	\\x0000000100000001306a51fb331c4d538e5ce008d1a582addb306548de0d0d43cde43ea050fc8866f5ab696a31890bb92dc394d670b5d3d4ef5942985887b0c825072f50b069d2c0058df02826a9aad4d82f75413e9fad7c05353b955e7e17a9baadba839592ce4117ab07b3cf9cfb230ea20399c50cfba31665be2a75202491f3271f6dbdf0ad52	1	\\xfde553731a1e7d44e99faae20ea0788a6f24e78ee67b9788391128f3e3b96f5c979ce502e9f00a6f767e5a879799e2ae18faddee89cfb987ca45fa8932dcf308	1655640574000000	5	1000000
2	\\x852467a9b2b862c2ccefce1f99b0c28aada9804a6d5bfc3a01e8795dcff9fbcd1b21cded3ec9d20ee0df272b5738357d685c1323597b00ddb24d0586e5c560d8	57	\\x00000001000000018b401365d0aa4fe014f2ba42af9bfd99683c124bbd330625d8ce5fb37e149624bc3d83d164ecec242ed9075430d600cacaedc88bc5e3d1acca25b2a36b9f4504fd02c7d4fad7c0ab33a6776cb0dcf5c2a59233b5aac1020aef85aaa85a1cffd98de30397b1efc72ae336c266553fc59a3d9956598e59ee8832c6f148dbb1f393	1	\\x11ccc307707ed59cd6b74c924d038e72aa0b9bfd80d370927f434bb2f6d2d0c90804836b945442b3eb112fcc6d7282a3626982dcbf2e6cb49f7345360c99d300	1655640574000000	2	3000000
3	\\x3e44fabace5fb0f459db6045de962689a6883771211a99b104e9f5dc1f6286e634fb8f3ec55e88bf6126f8100bfbfae0f0ea2145585ba17862af301947bd72df	194	\\x0000000100000001559209240d4dac70c87ad82f3b4be7b1c5a689cab11a78506c0f4c856663177fdda0196d61d50e44df76d3d982955cb5694b7e9f10d547892e53c1f6ebb51bf4ffcf0d5a13604845fe4e0aa58e58685bd3c8602037b46476e499fb4219058c36ef834c2aef480e8ab250942a5d6bdcfd841a2a7bdf23de57c33f4d876725b799	1	\\x260a04eeb917d739c5d5cba3b0594ddb129cfadf67a4699634584bc6ab3941900698abbdb2db8306170a467bd72aed4238f6b32d87ba5a2ad671125e54e97b01	1655640574000000	0	11000000
4	\\x4fca019753789ba83083eb07b2653952d6dfb47c11aab24471b4621898fdd5a73080d4c28a4626b293336252a35e499087b25c0da964857c24a05e942babf83c	194	\\x00000001000000012bfad807bd147bc6918cfb627af53e3d9acc9ff7f122c259a70a414c22275d1bd7aef8c83160abfd957b9183a99e3695a44f42599b2dcfde0a027963984b99d69f742919c68dca435fcfb05c4bf583565f66fce9fbf143c42672e7d7f2aaccd3febe530045d2b13aa15fbf2ae12e83e9d69721b666bddd60b0639efddaafbe3d	1	\\x7f31081b8a4ddf89570e08e7a67d94a893ddfe7c99c9e0491ad70775eb9840626e66d091f16e89c313ff63d47911b0ea2717ec548a17a59f177c43d02b7a0307	1655640574000000	0	11000000
5	\\xc118a43be3715a9d1469b8a6c211fcfae0a447456d1ca95129a99afb820b40222678f819bc358930c98b77fe6dcbfd166752781eeec564fe18f3b377aa7ca4bf	194	\\x00000001000000015a4fe9fb8b4697d2234c3303087c8fdf9e7d555274ed139ce0d811284aa2af6cbf69090979ba55da0577796af9d9a2b7399e68335f7d0b123f581d32b78af160f3efda5c08bc1d75df9a45ec49985ca1790beedb9bb82fb08dd30361461971b3863aaf6d65597e7b8fd6bf6fdc4902de13c5ab6fe96d49dae07d9d55f97af2a7	1	\\xc5ad5a541c3b90b5c56b6b41d0fecbea64a8d2477f9bd6fcf361ca8c8b9178d0c04f24e73ef6cdd216990a33d2b9314a833801064f6ba20602bcc7e1672e6701	1655640574000000	0	11000000
6	\\x8bd14e0caf2ae43d4877b46893c36d0fbb57006103a18c36dd279418d443c8d4794ee4b0faa1258df7aa5db7c20cb6f5791e322bc510d443f13aa2cba0948046	194	\\x000000010000000144927ed6b7f39937d38555da136b3a3cb36ca0579cf9964bfca1588aa8ca2f77b2834e23b174e32e20632402a7009945b083e2161390ef9a77e544eb994504b729e0c8803b2024d7f19444c2dbe33ecfda774ff1a5b3b0ba2955a2a3ddc082fb05485f63a322f9a5627b72883cf118fc9083422e89fa982de3b6eb98988655e2	1	\\x39a1a4b0c88aa47f3fe42227ea453dbeb0fdde9c16805a00a69e5a7f1d7cabd611dbad02bed19ab7b33149ebec71c340aaecd3baf5904b274ddf3feb80015c03	1655640574000000	0	11000000
7	\\x1413046d323a5bbc884d5d43a3d055314aecf35440d4753d8cd162895e15c72ca76d9e2ecf1cd4044b46bef63c9c7791c179b88d376a018920d09767f23697a8	194	\\x0000000100000001830cd74f4e84de64e4c8569005defa2cc15bf35c423872aa69d07a9712bf9e594a276ac1950e61455254088fe745c413e0d6cebbe6e3fb09e9b6afd992577fb10a3e916db4451c1fa784e816d62bcdb2318ad31035b20a8b5f4b62f7d9a5a7567672f1d9ccb59fc15639c939fa51e107a0ab2c07ff3afd712a36dc3b2742329b	1	\\x3e0037b45bd2a943a23aa0f9af3f2b4283dd73c029bcb54cd4cf2bfaa513cdf3a46067a2d8c785907fe593118cc38315c1e6572955d2c16725204b01ca0d1503	1655640574000000	0	11000000
8	\\x22885831d3d19204025b4f2497ea0c1af8ae59e3b40f9fbb6a6dcebb31c0fc000fd2790805188113f0148f0a1483ad993d2e2fed9080187fd122cd914a49d26e	194	\\x00000001000000018e0c5d7b8c253e9aa185be7347ef761faadd7221607fb715800a05b91ba614c21128628a45dcf200183d5737b3f498121713fcd0fa2ee0ec8d7b29da9f96606cd2299bb6cfc07b49f27351c405be21b6105b51fbd354ff951653bf94a5774ea8dcb95579a6ac52764196af501bae42386cca84c2ce7765a8886579c7050671d0	1	\\xad910ccc19e9032f5feab90165deef132eed1b60902d69f095f1e2d3d688c14898c448b23369ee31b215b92ff09d628528aa2887d58b73740851f16e07fdff06	1655640574000000	0	11000000
9	\\xf38095bc89c74ad761802b0deaf0b7b94dd3e6ee232353e5053dec1d5eec8546c3e969a0e86d4e7ee0d2c50f80638fc739aee9827619d3ef529e40a4ff5c8626	194	\\x00000001000000018d362fd37e041e7a8fd5beac2091e539ae2ed672d0b88f5d35655f98589d50abdca4b2a82ac74617c4589d2bbab5c098831e7023ae58b586132aec314411f0e4711de6eb28f7b748c946d14871719e7aeb468187aee7d6ccb1ffd477754b3a30387bad7fbfa9f2fcd0c1ab9279e1e23c9880be8d439cb3b8789015b4a7e4adca	1	\\x2ea412257567726b13a20583bd86d6c595c2a0588cf16acaca2121266c7cbb58e0969f3e3c7421306f6a3842592cab6a47e929d2da30cec146715ad0fdb9dc09	1655640574000000	0	11000000
10	\\x61154adcdd414269ae78b7aeff01182402af547c82cc15d84dbb3c5c5831587ffd1eebf04a4da78f3d609e77d18884c69ab5e03425f3df76912ac7bc7413b754	194	\\x000000010000000178482b1f2038030dc5b9af5456440f11f520a1fb6e9f3a643e27a5d131a521775aba226c8fe9830a4d8e4fe51ce01aa438de978ecb16121f8a50988518525b1ff7a1bc04adf1c7ad0efbccb4a13fb91f4e850a6c191c79cc1cebd7106ff0cacfb5e51b2298c3abc290d9d811e62c0a88292d748255bf7ec3341c6ecc64a6037c	1	\\xad38b5db8f768a28ccb6988dd86e5b01e9c068f7254da80c47b41ca1c5d77c23dc174be3f96f25600b40fd56bead65df4bb3cf4e79861341859ed8424ef51803	1655640574000000	0	11000000
11	\\xe623ac096b83f861e2f707ba71944f25a4dd232f80e74da2cf795a7c1c0fc4d064ee9e8a930b729f91ccfcbe2ee2edd20e45ba12b53e60d3c65e95055bf1e977	128	\\x000000010000000176c6f7a4960c5964599f800af2a8fa7fa6861e92016f18555284c75608a85a9c20ab8f4070e1d6fb5b053a71a67ee588c80c040a7d9bf6c4bfedd2f326ff0191921de9eb14f52fabbd0fa1e87f644bfba7a1e82e7c14047138913c200a4e98bad78d0ff806fb774c1ee9a914d864b781bf111581e39d8bfba6bcb2dac7fd884e	1	\\x77264f8fa37ff6a348e3654f6e4742d33bc903f930fbc7ece35321a84b612208acdce6c528d51422ff9e199b0935571e5f85f4b163a095027f39385e9cbc7906	1655640574000000	0	2000000
12	\\xd334ba98b8fbe0fb6a8df73c2727f830571e0e5880facc23927ce7c04b08db25f61f39273c2e0d1c0561b9c055bd8836215ff278b3d838218b591474f327b23d	128	\\x0000000100000001788ce69d5b342a234f9d938e2d8d420474becfe5f85d5535f45220798cc22a35d86a6e69c079cdd54d56e62378c461c397133780b2e3b014a4d9f0557174a08643da9c7089147206caa9763ff28a13391109060a96f5e6a323ee327486ad19d12118c16f766ac39e47c386a02967b56ee97ac82015221c887883a674a0743f8f	1	\\xb5d0f74d09d1ff53fc261e083a1d340a4ce3360228d1afce0baab11f16e2d45c5ecc175c7c7eeead8b42bba3bc8458bbb1aa81067b9c9955b614e75e60beed01	1655640574000000	0	2000000
13	\\x3b49d802dd9c3e8b8ccd79b58f92e1b81b8ebd0cb8ac41a3cc66c0cb00ae7488236d752636757960157e64d10343d54f8fe2a6783e3908b4ab90b3aee2922865	128	\\x000000010000000125aca229b90a00a30facab9b1ad037970efa19ae5c31d71ad2f82bfb6350e54af7ad5f491fa71dfaae140469aafd80772ee9c1cd51fc3bc69ee7aded85962ff8a78ffe67a59101db6c03380ddf016b6da817ea6501a00e8e7a14619ec994ace51fb26f670db501431911729f99cebc2a69a819a54c8c978610814c00f6d397ee	1	\\x9193a90b43db22607a8547fd562ded8e6d2a2a74f0fcfe61130aecf95abcc5109e29fc0f8c9a432a026b92d6c19bb4821e5471d8661bf0d16f91fc0ccdf2b90b	1655640574000000	0	2000000
14	\\x62255d8aa461a9b663d45c4d7e20fcc9720b68e56b171fb90f946fd662a606154751278763d500e0f872d35e31fe39902b7a1824fddae47344feb41c42566cdf	128	\\x00000001000000016f0f0b272593e180ff399b4669e9642379529757a4df6c9fc15ba083a486b6278bb7430313477bcf086341c7fb0b9f745d741ba1d9cb62d53ccf1b83c524d9304e13822d23084c30dd9a75392107345ebe8acc16bbc894d43bcc088be6931383a9d911748f2831d9fe212c950aa17d788e5b55fda20ef06c72cccf6f7a9ee412	1	\\x1a2ff059dcd042007f6b91eb31abfb89cc47c579acfbe2061d0f6c78e54780c3ba9c53365866a8032bffdebf4615f81adf300f104753d2f965612b4399e6e504	1655640574000000	0	2000000
15	\\xbdf0d832960008b6ef619deda9b8692853b5bd5c048ef2cdf2f3d278c30dc0e4de378e7d6d0d441888a0e43c66de58a19f3229360c05a3b3be62ab93266a829c	113	\\x000000010000000158e1f2a1b52f6340c43f743e8e68bf1143c77f291896a628ed763baba7d4a8913e42911e0a7a4ce287a105bd6ddd6f6ff3e8e9d0ed50a13a687b1c0e9019db11a716e647859f84e79138dba05267346f01a961249acd45ce0f1848eb3545f64a6463f251b83c25c5deb2b070e294c3abd9356524bd3d60caf2a30c5cde33d810	1	\\x32b298176d59e4a7be51244482e98a679c4ef57dfa48d11cee794166a0698213e97cfa767c146e9de84c3944125e05f9318d5b3af236153370220ba9ba9e4e0a	1655640585000000	1	2000000
16	\\x6b8b894e2c7d18c957f39b916654cef04cc710b54ea850933e81076316afffc84475490366fe7ecda949e00d8bbc88a96c51475292a3c8713014aeb24b09afe0	194	\\x0000000100000001415a583f8fd7ae8b7a153aba6a5eb096ada7e944823d286e965e64c37cf249fa3b8146d185c1b93b052280353c6011c32ff40b994413539313f345b8b0d13cc86486a46add6fd080335d722a8b27ca7daee1190b75b39907513ca97d0ec3188646fcba2178656482f5f3fa8fe13dbf4d1459d9671c4dc3e16b7878c5fb8b8724	1	\\xde1d7af7fe490adc4d947ad48849420df0649012bdbfb726e717a0bab2d120dc4bfa7c7a508c695b654adbeaa6688895336e20705d5059480d01fd0f3231250c	1655640585000000	0	11000000
17	\\xee8618b0e296c9cc7e340ef86cb34e55bf0660476a16da6093e5fc27a4a7e2167ce797fba31cb01ecddd194fc6775e66b68938bbd10bb01cda27fdbd4ed32e99	194	\\x00000001000000018be8266df6a71ae0a3d7d27d38f7d21057fa6486747f0b8d4e308c5b6516083bc50124367e6639a56e7eeba55b4813be2b54bb0e10658457faba9a86014de09cf6c1ea56ce11f5dd82a89832932815effd12bf9e5a65bde35643921a78f8ed9ccce8670882c88e4bbb78a4e94405d65b2c7ddc3968b21f8f7587756220cdd8e7	1	\\xfd97c879da147122a21d13f42224d68140997ca9449caa73be521681b5134fc7fba3a3e5e441e3065d13262e4f00833daac59f7bcb21e1ab596ce9d88b7c9a03	1655640585000000	0	11000000
18	\\xf768888a9fb0fb709c75dbc50731c1367d31cb451f5bdb1d8943d401e2fda94e69d96b172f5faa660ac5c332ef8a983d66791e3261da554281a326fdf88323ea	194	\\x0000000100000001926c5e4a601bcc508f899eabec266aca2880df8b801259878dee6fae526fb2b3526fbfdfd1b37669ce8a2142b3aebc0e154b105c69b5b3df4b2511133918ca8a234a750ed0711eb5531483a52747da9b8d8148d2ef87b36e2167c2ab183fe2538b08cbee99ab3bdc10e420e69efaf93dfaf80d33893d37f7509cd4b274e4d59d	1	\\x8428a3bbb444726331bd573ddabe6240657c51ce07b8b65d087e549fbc84f277a3c6c71f1d346ea6166b9fcf7b8a68e379048edbce506651b3100286bf1aaf09	1655640585000000	0	11000000
19	\\x8d9e557ab5391b42598705ac5aad57777b32bfb58dd3bf14e58c46b6abd80f85aa92f87ba8c37f7632dd0a6dc0f3901ca13239260bcc6462f0b822ff57e192fb	194	\\x0000000100000001027521e9418f5366f04e08524822cabff5a19c663d4c5c5de7704bf8c31d09f2cb4ca777b8d6d774fafcb3d82420645f2b6cfe43143d490599cdc723980e8327b2dc1c9d050c1983ed3274d1113f3d84c556bee2c3816cd997f3005e294f86360cbd949919880b661f1972476a842a4d244a993192f86a54c8c33b48534f4ff8	1	\\xcfc7f34462b486b1fcef63a7671286d3f0a1eff543e1f714250325e202acddf3ac7f314821c4a33e1c620e51271127faf6579c3a3a7bd5eadfd09f279a387d0b	1655640585000000	0	11000000
20	\\x977ea0d13e9eaa39d08be569b33a25b975aaf53d7a5611646cd9401702e8b835802b53295e733a6af93c4c0d0c4528c7b5ab0180795802e95c007fcea5999214	194	\\x0000000100000001797897bf2f12dafb8fd8729df286a4858dba622d23275312e938a26735c63231846b7a9f3c0b78f9f11256325ea1340f3af784467a0bf66e52101f098209c28219372752ffa353ca4b15867a053ed9ecd0a567aaef29fe67829e58b96708bf18b2b08df5fb3dbde4e58bfcda9a74aab4820387fa399986ac4fd3ea0ee49257d7	1	\\x2dece29d6feb83e96eba617b9bd11eb4a0b7a0eebf5cb9e1d2cdcaf9c6a47d966149ac1d0f8b09402d81f4b3c1f51d6b8474ec0eaaa5a963ebe46f99d2e5850e	1655640585000000	0	11000000
21	\\x4ecf6dbf58e0285bb95a953602938788c904b5e1d499c6c17ece226622808893ec8d6201bacd9fb94a32159a05879e5f93dcd03f0fe69a824b20c9640685cf2d	194	\\x000000010000000140807edc9c108c9130f6deba97c154c442a48f8d19907d7eb4d51432e2346b2e24ecefa76c1126aec76bb71109609d4381b46e5ba98c2713ed044208544a36a6913130f47f7595b2981d996328fab0e82f0b6f2033f51633dfa2a296df61c8c51edc6360886a75c8a37e6f0d517443f622e3295eb2407ef60cd912478aa7b244	1	\\x9fe3ecaf85367effd71d72790fc34ab7ef00ce8ca1d0a775ccadd78b8668145f11aca82af7888db4445a5742f1fda2fb33e20fba69c0c4b618ebf9c48e491602	1655640585000000	0	11000000
22	\\xf7e6f4d36dd9c3bf79b2d045b25063b7c02175d52749bff822cd221d307f4574986eef4dc4bfeb5f8df6fa95cfc1a039f1a992b57bcfe25054b910b9f0b5867d	194	\\x000000010000000109b1b4b5413ed4d233f27003d10df6fdebd5ab435ebcc005f9dd5421e6e1ebb0ccc3087766c70fc01190f3fde03f64e996c118b16c4b088982bb96025da45abaad399a537697919211fa3efb95ab19b0f15f35e483339dbd11cdf7e8ee802f2d064b6cfbeffc618598ff49eb3fad0121eae94a198498fd2c26d356b3043910ab	1	\\xc1633f8d979fddce49a818c2c866e0b75df026e66bb205378278bf0f09c9c03f88105544223674e4d862084ec37d6541bf78a26da3c81922f08328fe7224a80a	1655640585000000	0	11000000
23	\\x4f40e4a013d6a6e39a29a046d694035cff0a039eb6fb69cdbbd614c1bdc93d1edbc7e66e96e09857f544fba053810f71ee18fa34e845d54838cf4c8d02dfb496	194	\\x000000010000000157db256c1e96b2a389a0a493b666acdcdb78cd14a6c6a85f43d587ed721ddb9153e43462bb29ebf4db96d5ff6bda175eb22c8b9d39ab4a32df16cf1394074dbce9d601dc759c462cc6db325d18aaf55aa973c7e1148a37565710b774c55aafcfe20f7a0a201ac13dec7618c51dab37834d7c4c45c29f135b4909426c1f957bbe	1	\\x04a1203c8917663a4ccc3be9c23bb33e07cc200bfe1da774aca035c675b04e8df3b10b76e4b03224e26b51ec48a2a5cb048babef3fa252d68a88f312a7964b08	1655640585000000	0	11000000
24	\\x033dec4b2ebffbaab4123fa00bba226f6e615c5b1372d0c44a9e106f6904d55a2f7c52e7f06207e6d15a4314f5e15422475a1d55d98a4efb662128c0f058e02d	128	\\x00000001000000017702b16ce55e70614ae3ea42fa476ad7ddc1253ec312743a2cb10ecbf569dcdd5a571773fe2b728e08f5073536afb4c8ff60921d6f3b1f71518324aab4d4b6d4c8456bbf42065a7e700b09b00fa0ef62800c46c5543e94cd24678bfb5de0f110df1eaea8771c500298677db6ae1a3bc51971ab035e7591f5f224895264de8e89	1	\\x4c37dd0d461c3b3a19bc084ca053fe95c1ad7a0e5da635d71074b4afd8b2ecb4f6775b2e6f9dddc920132929d9d1561c924afaf745e5df3b4e5f2d084eacfc08	1655640585000000	0	2000000
25	\\xb55545c1457a869bfd62efb837eef2a97293aeb9a05f6b3a9df96730aef30b14b9e2699fbf549c1782976396c3f231d625e8e9eecb67c0e7d458f69a3c813944	128	\\x000000010000000133b57573ac8fb9f6c0aeb5e7f31b3df9b18b445802c80cb7947acb177dff17c333b7b67bf1d40b5252bb76bbb8a95b4aa32fc42d80b6189f93a948e5a5b02c1c733c033848bbaba305ebbb6abc750e3391c245db2f05dfc65cf1a5685ed533f41cb52b259c15d681c3f22c7ebc6fc18af4009b011d5540b50255e57d0d76e9fb	1	\\xee1dcf5ffe1313521e5e0358c46bcdcdf0f29968e88f209d13785a2fea1eb3a2e8d7300c9f706b8c4f7b61d7754e39bf2d7c3f257768b719c587cf88518f4f0c	1655640585000000	0	2000000
26	\\x210dfb838a5c6b62bdc636c8ca6958aa8d581c2fd5f6dce9713d4aca873f1ba9fad926738249b75e3c8da0b6eccac3ef49d859bd43dabe511a4ec7adcacea23e	128	\\x00000001000000014b63d2f9201cb4c318f31f6af26dfac65850142eed0dcfc888174180a16c4315cee4561bb115b170d8897576ccbc583ad35398af50afe644e845f14975155a5270d0ff6e421a3ae2c38df4a6e9f9f0f4e672e2a43c70440bc03ff30e954c4265441467f822b325f27f95fc2281696b111a3250293193500441218b47686dea58	1	\\xbaba9b9258c74f7801967e2f1ed96870c588f5b4c88ada496db8f265619d2a3d7b0e689b764822867923a42ad81e9419f4a122ba7503cf0421e652c32218cd03	1655640585000000	0	2000000
27	\\xe4d7c150ff14772a9417ffe332bf3b9016c99a533b2dfb5a79b7b48c46c0866f1138caa151c70b723d6f3dfbbbcde636d26b834616ce54507ad72c3d1cebca2f	128	\\x00000001000000018f1cb81b555f352b98dda79393ffdfc278ea07b9e54b39d237835ae5f4ebd42891ee27c36a3ea7eb4f6b02259ed2cc8d4bd43d6837ede22a8d1dc4cb17cd04bbb543a538546d83fdb7ed66dbdd8ac67bbd6e63b75b08226a23743d13028599060792f86b41522040522af008dc5cb636d4abda58952e45065da5ff00812c4fb5	1	\\x1d51b2fac0cfcae46b2d659cc2c87235bb351c20f5c217660a170890544dfc8356cebde3863dabbce0e87aadb89de207723b91aec263131e58217a89803c470c	1655640585000000	0	2000000
28	\\x125e1ae7aaf3a596c6d2567646981f1e8f87944efa3eb3abedbe77051fc30602428a880852395b0d38e2262482dc4fe1c3df58c220224e990a9139dd64ef7733	128	\\x00000001000000017f1d005a2a9203470fe393f2ffd3d8c9b02691e7b00131aec1638dbad4f0cc4fcfa722ef4cb312a5c36ecc17e5af8b1597b27231986209b87f877b53bd0ddbc75c9ceb0bdd6d7e1a72d58be91f4cbf63ca60b7cdbdcb337c924791a99dc8d34aa1b186db02b461e16571c1dc1fe5128ed2614008fd8f8d5324ad80b9ff035c0e	1	\\xe201f6d1967f1c79cddc624c4762723754efbb797646119cd663ca0ee20f4a37c8705a72920a57433b82999d19b76bfcdbba618e4d9ac706abe575c87c6c7605	1655640585000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\x119dc0cafa9281232f37301cf780a12f9b0cf252e87ea4d336c276377ffe77a3ca9acf5e5ba432ac03c1fb443deef4c634038f10fd747e710828172f1b4e4307	t	1655640564000000
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
1	x-taler-bank	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x2cc20db7f38de122d90c286fe3954a28cd9d942dd6d849a80838d71c1be3f5ce1325a61fd7b576f139a4ca72b2407922e0dc87cda6e48b58be95c3a77e95be0b
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
1	\\x1db2fa56550bcb94b6d488e373484844ff4e47013b00ce57df739290a0bad591	payto://x-taler-bank/localhost/testuser-ljgqtzra	f	\N
2	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	payto://x-taler-bank/localhost/43	f	\N
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
-- Name: history_requests_history_request_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.history_requests_history_request_serial_id_seq', 1, false);


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

SELECT pg_catalog.setval('public.reserves_in_reserve_in_serial_id_seq', 22, true);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_out_reserve_out_serial_id_seq', 28, true);


--
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_reserve_uuid_seq', 22, true);


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
