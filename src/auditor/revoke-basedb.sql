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
exchange-0001	2022-06-13 14:48:49.271569+02	grothoff	{}	{}
merchant-0001	2022-06-13 14:48:50.212322+02	grothoff	{}	{}
merchant-0002	2022-06-13 14:48:50.619642+02	grothoff	{}	{}
auditor-0001	2022-06-13 14:48:50.75622+02	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2022-06-13 14:49:00.576051+02	f	49c3ec71-e4ef-4df4-a362-62a294c60188	12	1
2	TESTKUDOS:8	RMPK9N2VJCSZ1Z9402MZZWH91HZZ62NCM4VE6EHQEG4EC1Q0Y8DG	2022-06-13 14:49:04.094598+02	f	215db98e-49e7-4468-a91a-81b03ff3de95	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
5e63c4ce-b537-4967-b133-c47598645a2e	TESTKUDOS:8	t	t	f	RMPK9N2VJCSZ1Z9402MZZWH91HZZ62NCM4VE6EHQEG4EC1Q0Y8DG	2	12
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
1	1	59	\\xad66075b4db9fa300cb2c660e078ed6337355cb622fbe8af3f9796537a8d791bf3a64f1a54323887925093b7329d516fd170e1219cb65da6ad23072e2c127705
2	1	303	\\xc7ee9bf82d7259e1fcfa464da9bba38450ea3340a0427272f81fbffb22daadc38b21fb14b17b67efde53dca32f41fe4758101638b7c8ea85b152d58c7f33400e
3	1	355	\\x35aa2ca55793feb25d69d735fb22d755744d785d5643d222e4c7709b4abe9a1aac49ead40c0aee18912489712c1367752cb5aa94d47793363aab86b63a112606
4	1	108	\\x92df396368edf5f52a966bd9988224b76cca45f26e36f6b438206abdf539e85162419976033955162d96aae073da2637c863aa6fd97771461df59eed37ed2307
5	1	262	\\xff7cbb72e51c631842d85553bca30b5b2d96c5c85985cca9b14d24eaaf8b5adc674ee57226d33b0a348918a75ed38c450ea218486302790b1c61859af5d8c300
6	1	162	\\x2156a9e0ff2ae822fbeba36d4a6865fa904bcf5b2d210e994346ccbefb587e45e38f8398701b0d5c887013201d44adbe984a15844c3aa452509888daa17eff08
7	1	237	\\x5694269a9d47562bf3f72a9190f3150573ad43e1eb490049e301e5a26c139eab878aed7eb8a4adb0dfc97b64b0e37ce86c398e26da3d7d6a14714c6aed27e70c
8	1	271	\\x965b2b6292221a2d27eb0e400ba3fc1019aee4f422a37aa3742651e99be60d2a36b33f26959f43d0a793ccf2d72f86f0319e8bea84d04da1ec4b075880a05709
9	1	111	\\xd32140d29b29e66637e3cd4920dee8542a615509ace8586181836c7ec0467b4e6e7cb3e4ff75d739cf2d10c65eeb5fb7a263bf7cf92e00b7e0dc121563b2ea06
10	1	203	\\x9a742b4fcc419ad2ef47b2aec6840dafc1798c21fac8d8e8392e6a5c77c954ded49f5affdb41864b9349af8bb75ea6f2d168930596aa60ea1786a0fe6b84d60e
11	1	383	\\x8a2dbcb043dce85af2459de68d4c7a375ee1bfd1b63b02dd10698af1e1526dbdcb891180eebee4704857b7480771dacc406b89705e51d90e3a4f7ac6b51e560f
12	1	315	\\x57755f5ab78a4a380b9a0d32da2939f35334a34217ea618cc0d56b78265b2ba3d584f69b9860d79c73886b43a5434d40f051766cd010aaf748179212a1df570d
13	1	258	\\x8278c5e3860915220206a663e640ad35bc11a7e88b9c6b4df3cbedee6bf9a7f0716cd101dfa67d3db03442a7b05fe56ed11c6987e61881a906d97d7a7d3a8a0e
14	1	68	\\x16fb1f3b7c594cb8c8bb0f3066c9e7fc9d1b267a618dec3ae4565a99aa406d6e55a7a4cbc37217226db8ac4c5067ea32d26b111a12b07ac60beafdf48e85480a
15	1	85	\\x0d9eedd7212b5f3c70fe9cec6a5d5d553d0b72e89bbfb1ae2cba6fc0118386367c4b59a59264bffdfd5c0313c0cdfb0e9ab7bde0d5626cd9a9c1bb625f5c6d05
16	1	94	\\x5c8950b8eb06956c25017efc5def35e19cf82d1327cec3dc079555bc0055d7faa1c5657e41fa13b8c4509281e09dad7433adee11f643b4afd348993911a42b05
17	1	23	\\x88142ca8bad0a60402d764437df9e685d117cdf647441e937d3965fda4e81126dd52562d4a8d002f15a381209164c7e6853d4defdbfbfe68395edda3d9dd3a0b
18	1	55	\\x370e6b4eb62ce4e6624f37afc7ba7400ee5c10da4a00c7bf23b62ac526f4767bfe6d64933e08d9d5f9929430cb2eddcd2bd0ee686875e6eca79536dcbb575108
19	1	99	\\xe23f38c9db92746b54ddc1f16195fd09df2d9771cb8c9ed800085333ddff4ab5a87ba9dfd92e36ae86794f4db13c531c752e1643946500984e7eecf002819202
20	1	241	\\x5b207eecab4fd25631ea8580773989703c46c30e4b6d901242d812bfaf904acf3dedbacad52db46c30959fcbe612e713e610674a192334852c336569a2abb807
21	1	353	\\x6030c50126ca091b7fef8ec003da68fe447707c4264a556a464e1b21c47b277a8f30033ea714363fb4dc11be4af650deb3a1c259bcf39924bbb1aaeaf19f7c05
22	1	138	\\xc260b6f815c409bb2c8a0774561dfa233065c4bf7f5c7d4b3b88b76abb1a6e8f424dfc2789e7d4fec61ab960a10b761857ed8d6dd46f8e1fafeeeb453515370e
23	1	351	\\x4d495a661e469b707e2cfd9c61a6b151b36064931a606a38d70452deb20b00dfde0214ba905a7b380aa05b21bf1b6387b750a408e2571fde40837867ff60ff03
24	1	143	\\x78d54dd6b481651a801ab7106c8e7c25efa27b187601cd22b4d60bf7ecfe58b4bf95278fc722223a99b2036ae7df7269aca4c1e0af0bc18ae302c14016b1d404
25	1	290	\\x7b988de7d3fc6d980105aaa74b91efc31363cc673ed110a63d0232ff6ff8f3a57c0e426a9ef695940e75b5dcfc72c62ab9f8ef6ff82044196b2b198b99dbc90d
26	1	281	\\x7b8b231b2d67075f0f097c559f8791f00f9f1c9b3ddd848a103d3b749a0e39999dc4de5c31eb0ece2d06feaf332ce716bb6eac62b5ac461cc3a9448e1924ed04
27	1	247	\\xb7e139a7577fb71c70ff3686f5bc96090c4409b64d889ecf5111d31f476aa519637a214b4895881029cd8cc8d7930a0524cc2618a510a147ea81fd0c03b52a02
28	1	363	\\x2c00b0c0bdcdf4e619f84681ff40799967b5c0b93a0de861f4d1474683315c22999a6732dd608645f1ac84ba234ad51a529dabe45ddf34327c1a99a4644be807
29	1	121	\\xc4a7a0a1c43feaa548570c804b8910c09c112961c4930671d796f27e37e76b96d388e7e1a96d3f4942ce319f8f1842bd00fd742a199abc7a61033f14bfa7a40a
30	1	125	\\x65fa7c59197267590516973dd7f7298975b598fcef5eda9d5ef61e3a28e53b65457fea2d4322324e8719dfd6a7681212d5177cceb54ffdfa7850cf572cce0003
31	1	71	\\x4f6c3ab663e6b59085d4c3f5c08aadfa71f99dd54408ff77efcf282cd4c363099aa587442412872f9005e8a990aa6ee5bc5f746f180b6504860a16d5b442b20f
32	1	172	\\x1f28877e74369f26224ebdb198d352b0bb3d8c3459ad50b0edc4571368db29e5b652d721e2af522eb8fc8b1cce48e2248dfa48c8a38d7d4eee2ad835232c5e0d
33	1	131	\\x6546e6dee845accc6dd7c3bd8391a43b2e53ca35a83ba52d29817d1fe56b6505969fe88d509fb1c4a79ffde09d9f8cda956ec18a0a6864221b87f5daf825fa0c
34	1	120	\\xcc85fea311ecc7f31adb1fd7dea057436bfbbde1d5ffcd85cbcf840ef1ea3a48c40a383686ae22320d3b1636211696f61b0895eba8f0b1633db4cdf63058c700
35	1	350	\\xa8a8187a690d5acb2856b9a176eeb6b8bb44c266e4d63d5a5998d15e70dd0b4555dc22fdcfb17aa8f67607f818d3f316a615a71000ec09fc5555fc3ee15fb50e
36	1	174	\\x90f1aa29f1cc2a020b773157a348cf63e423d70fc2b41386dcd7df0f9f358ca2f036fc71b6aa66c1fe97b9a80e193baeb3f181e3460fc2a08342805fca9cc706
37	1	252	\\x59d997efc492d2db876dd0ecce838a74511478bb6840dd8308bd3e201d191ce523ced784be435155ff7176dcc1eaa782c6fde5bd6398c7421f1b5e7239f90a01
38	1	269	\\xff0adbce6725fee6eb54bdc5496a868649351695416e602cb6a4c508bc06d828a78d24a2a5f2b48a0b3ea8e5d474b748aa3c8373da8c0dbcd3731525619fa101
39	1	332	\\x008cfeb5f206056797b74138513df59a8400f804ff55c6e182d99ada7876600502d292d7c313b15548d50b306bff92526bf72117f7ef017957625aac8e7d150b
40	1	403	\\x5325edfa789692e48677afd9f72d2f77f6d05aa284342e637059466fa770c581249ba4aabc489a66d69277f4106355544c1d87ba0dedf9b60aec4d23da53ce07
41	1	32	\\x65b086aa5c851d9de00b0a4bcf641cd19175e840b10713450580e9f4c0cc96e7e888f3f20491f0ce2da061de6d509040c7217e8a96f409c61a828f363ffbc60d
42	1	360	\\x5898c1253406af688df0773d7cc3a68106bca8aa6bbbdf94f490ba0335fd26030af555d8d6bad9106841256c7e81685a5c89152bc1ccb686c44edf29282ba104
43	1	293	\\x7f5e302b850c70490d6e3be368d5afd12c4318598dcc60858a05c7b18acc9c25cf6d757bfdec71504044ed5360c42547efc7eb2da886f4508e83c8c3e0d8ff0e
44	1	151	\\xe04e4987b0bc56ea56b9738151a0d376ec4584039fbbad142a695339d28327dd102b8a41bb30bc018762b95f7da2a04e7602e29c61e3e5408654d8f141fed804
45	1	319	\\xa6c1ee598fc7badca10502fb2ffa3dbc7fcaacb58bac70c0bb1ebbabd4aec1813e3f5251d496c6707403dd160c97ac52dbb492fdf3004b771ad9b70a72fb3a06
46	1	380	\\xedf32689d01ee0bfd42647d9dfd6ee08d6dc8a4284e85f719081d8d5aeb4a9747ee2bb3253be8cd46caf2d1a3d0b95186bd0df34b920dcbd6f101d9309682000
47	1	310	\\x52c524321b3968abcc3e5d32c85ddd550aa16b343505fadca9e11b7370a406b6aa940345e93027e18eecb008ccb23a957bd004fc29192365984f1986aec79e0f
48	1	238	\\x44000f980d7fe021e68daa850fefe54e062b8252c01f0a56bd1aba1d99874b6c27c7e99e26618e0bcfd349a11c8fcf3be1cbf4a88d79ca6c7dbcea5d373fac0f
49	1	16	\\xf0366a763ccb375256d86a7ef3c4725f1c50bc27a25cf4c1f2a98da64ff108b90a7535c211a535ba6850f11ec4284e220ee1f5a9ee284b891d16f36a18cca50e
50	1	329	\\xc362204dd6c8f0058c78cfe6a2d791a2410b7a45cd7372a13b47a29c221c693229d5aa016a6ad70ef7d5deb1f15753895f344762a8432ab7d4fb4270b9650d0b
51	1	386	\\x42d2deb287330dbc4e765db511650af439d19ff3264a63244f566ec49b7e26903cd59eb2f5a79c4e0ccea56a87406b7e8c81f45e11f6c98e5166a369bc21110c
52	1	105	\\x5541492074e5359b33e11bb82b8278c0b736b8ef9eae2b5b92b5687bc3561ca289df8aac7956beb11361cd88364f13992af9ee4a950474d6d88d2a13534da701
53	1	86	\\xca8807d2e9bbec11213f14537a9751c9f86c80878dc21754cdb381d185e15e3cb754c37f5c4c1a2d2627627ccb69516254877d5c987b5c397c42852255f71b0f
54	1	250	\\x60f9814b87db83999bbbd2a016b87d4fc8b62ab6c7898eded32d59e2004516d8a967e6794280a8742845f9dcf8d486922e147b3e5c757958b567158ef3970d0f
55	1	17	\\x5969491ab5cb3abc6770653c97d6c13cc01b6c64d8d440e7c759c348ae0b02a06459505a34dd22081974cd30f5f9e830d2107214113bdbcc8345508fab7f7a01
56	1	42	\\xcc7098bfe3134c35cbf776567a7ae37b59b1998e2def48a23e9fe2cb2ebe61fc7d2115cf56132213f8253779fba7144278868b62f212cbf62e9d882cd5f1fb05
57	1	156	\\x8b5aab9f43bf07c1cd7f5c0e456d2ce7021dcd44cde6b62af145b7f1db0cb648bdd622a931cdd78677b9397b508adff18cb3380652fd38f774bf701a53e69009
58	1	282	\\x6580bf229d5e4ced91570275b99a9f2040c3e47533f5043c3879bc8802a1de70a4cb3a21c8a6a37d37a829ebc5644a5676076879c242beea2411a6aed0f74909
59	1	70	\\x06e006350ee3330017bc6f57a7b90c9c77a01e92a4450182805dd34b011037cba434f7fb7fd71c934db31c8f5d9fb0baf32df241df8db0f0ad4106ca10013a0f
60	1	187	\\x5d4300c87e0565adc2fce3a612845b4d09bd186a09249da3b17448da36bacb392612b86a0e6118e8861fbb7c310e19bd5b87ac7309133cd90190806f944e0b01
61	1	167	\\x4993d423c9086e736ee0d6bda9a1eaf41cf391c22be15acba0c3a3dfa6fe293798d297b99e07fa65a8d82b4db0cc1c83cd44a66f550eda031c510a7d854ae907
62	1	204	\\xe2fff013422a530f19bf39157879d7affee0a6698f7e6198f13a725e12df20d53e1b36e427cfd3414ffee97c1f7e18972751f2d22d9eb1445a4a18333e340b05
63	1	190	\\xe5dc2bf65ff211c24f0ef4e7e8e63ab22aa931f5df82b3bbc374f2e297e4057d95bb3aeb629d3456818eb43f425ce5f8c3102ea1598ac266d539756df9350806
64	1	336	\\x53e078364b9b79458cfab9c3643dccd8024faab364586c647c2ba106a3263a4079676051953f038092b3a52949b985df58ec66685833aa3d36b2db8f60952e0b
65	1	274	\\x3221cb1c7daf4f216cc87ccff0e7f25904d3324bc68841667e78bcaa8669bee9444500e06aaa7016e5f55a435c5ff74c74739fb731bdd0b13c1f4f853f022c08
66	1	413	\\x40b40a3f567507a27cd9ff03fc1031e51720426aa23c30549f81b9a97181e3e17e8b2d17a27ffdb827e503fc38e5319ad9b4ea5a0feb2b006cdcf76bc2776c01
67	1	275	\\x8ce5b286f2e8cdc3ac56fb5a861b72740f31faf57da2792a7b9e56be340e272d7ebe4e5fa680c03cd8aa3c844be1075ffe6ec80a4313880b3b0c1581c5078a02
68	1	347	\\x927048aa9a6fc8c92c9d417efab30ee97b594b0d11024ee5ffe6f2c3a2a0aa69583d4d85020a5cdaa28f7943974195753b1f9ade4b659a495b93dc98f314da0d
69	1	46	\\x9a2e99f5f291900f97331441a4cf2eaffeb176d68d893109c31d1c8903b1ca5dbbf2e5c166caaebe97911391e3412df30d22ee5212e194d96ad81bc538f4780e
70	1	333	\\xef38d87dfb000efc18cee1dfb6ed699a05d6e5ffc5a09789a3be963732dc5c23a32c0df53f610552aa8d0a36eff6e785d94b27340ea9d0d09c1118558458730d
71	1	77	\\xb60c46ddadac8c323935755ff3c6028932e7c2c4e05870430f9a599205857ec8c91af56f830bd3e1e18cbd022f3fa87d97453a1c845d31ed948d1a1af6ffad0c
72	1	135	\\x66da2bb5ea0e8acd4f293363c2d20a13ceb43ff607da747bbf0d16950b36021dbad2a71fc87c05192e05a6f40d595c74fcbdabf1bd7265a4e1de326c65c4150a
73	1	31	\\x687f8c88b02f1b8178ea143ebf17701ad60391f7632bddecd7f7b17e4fd1aae5611a0dd7e84edebfe290af26044cef6d1be1bc6bde2bd5383f2b4d82207fd00a
74	1	244	\\x78e03c6c2ce4a57d416e3f7bc0e53330aa6fc8401826d12139cf3f0798969e73c92c4fc50649afc415198f4e64254bfa383992cb6ca0b16e52c6f2c07aa20006
75	1	39	\\xd3458acba01237c7748c37aa797efa4ccaa80e6a4b12b274798fd14797f81a231aa3178a2f9d357a98cf002385d9cf959fd51b1d91013cd51aaebe1dede14f0e
76	1	265	\\x200f9c9b8f13afe6e799588d44fee444eea489c70313a7c68b9c722636e4750137241283839f2ad3f5b5f733b4ed3fb8de7de072487b32b31ea707a00248a60c
77	1	306	\\xc77b82426d8054da7abaa8c464fd5dfa99e65a48fb6c4b439ae9971d41ce67652c850124089943d04186239ebaf7888e0e299b1c43fb512e4b717613deac7c0f
78	1	267	\\x4a101e8f3d258865354d582a45d31efc4f63fa9bc4f21208f84e906ca27732d1956ae1493e8e9047cd459ec12046c1a94a17ecede05127a583d19c3d59005d07
79	1	192	\\x10fcd7aed8eb949e8057979c09b6b97d5e3cdf4c4a0913e87e86aeb37f65413054790e3e0b7dcd0fe402adc8d73bfbc92e74fdeebac00a4d52850e3823f91706
80	1	348	\\x76462d88c7c8f27a53273e5b9812f57aa4948467ba6ecc224d41c438e35a4d7cd06f791493429fc605789856ac6d453105abf962ccd9d922a138b949223b9a06
81	1	259	\\x2af44880440db3fb2408ebeaf0fc19918b203e5a27df3f5092521e8ed2548ec5470b164cdd1365e021546e383e05e4d3f0815d8edc0c36c436a6d0319750b506
82	1	276	\\x12cfad8be3c9f97436235f4b51536b0cecb88664e8e572b7c6574d06ebd4c3a3e5955cb69e5aa1a3dbe9eca4d6623e555825f242c9050aa5a7e4f38761fc9b0b
83	1	257	\\x6be4df731ebbb8f56fc5e9ae0f0648ca7ab367caf71184c5510178c6eaf25796f35e34619f540263a8245133102905fb30ed3d3e5590337f52217748b6956f02
84	1	168	\\x7362babfd173b548afe199142b5203b20f129c9dfac0870fa57f131888c4ccd616979f1a369f199416c9941a5d0d193f4a350a09e138e32869e2f3c6c2950204
85	1	194	\\x1ca8975beb56b76c64a18b29418b5f8da16be8e67406c028ebb74ca31fc9fe110e7203e4886df5ecaa8c0df07ccf11079ce992c6a7fa69f9c2617ab753b9ca09
86	1	394	\\xbac4e23996b71d9feff5b4537ba89d5b652f0ed5a82fd11a90087deb061a8426c957f074553e66b4d69d381f44fe7aa082f63f669a68b6ef4869a0e9a910fe00
87	1	58	\\x322dae4585807bd218a51724553c462c93e03239f4c517629b0150f5da83737a8f7d02ce5cac6ddcaa2e9d384b3097b93311718c814fac4fa926885d879a3e00
88	1	67	\\x42e426a1064c826a53bb26305a0c4059fa91cb7d87f90a4813480a007427b8e10b823813ed640e3ec139e9b504e33170e8298eb6a3e14004ebd732866d53d20b
89	1	224	\\x6ea0e4142eda84383aa45ed22c2b7cdf58031b428f33e5353a17777fcc89f5e85ef19576992790481dec8eb362433a5355945e69a76494f68296ee452131ee06
90	1	286	\\xf998b297a101d841bab4f06451b0edc391ea94b6aec7473d5e360d1ead455f031c02b0663673192667755bdec0938cd3eb77e7c03d574e4da6f726c39572a50e
91	1	226	\\x85f09d93ff58607948a314c2093306344ee41a602cdaa1d029b67b1c4cf00f17c36f693f117fed86cd60492118a3684731b5cca620a608e904debac2ba21a202
92	1	139	\\xd833f7097cdbd9d4eb87c0862aebf8f54573cc87420cccc51c4d2d076e5507e84fb0070b7856909dd68b0fef4c8e69f3357508fbdd646046c267d8ff2ae4c501
93	1	38	\\xdcc70aeb8e800939df214097d6dfe85275be0188e925f58ce067e9204a57f0dbeeef841db091ef17ac076515b3387dae2e3e0bb52a8f27754d73121f3742ce04
94	1	260	\\xd7cd22bbff25f7577bcecdffc23ed3e2154e6fea22ea5e180dd14485fc1f5fdc70eb60a43015c2299a0e75c4c983642829d3d31f62c7afb115b221b4217c7609
95	1	186	\\x01a09ebf75af5981f3dfe6e1a187c16e02a2929f6f95efd7927f2cd0ed1e47bcd4aea92e21d80d40660f184d77c39fd50043703771d30d09e3b05021f3637d0e
96	1	406	\\x3adf802fce9cee6446822c338d1a92ec20936594ad92df0541f1da44e6e7471b47434930f97aba03d66bd16a84d763e3309474e46cf3dfd4add18c33aa112e0c
97	1	18	\\x8101d1e85d2234df054bd9bdb40e9eb61d58061994c51a58e21a29520e064f7c6cc404daaa4e7ec569643176568a4489494747b443683c586b8c88bfff1ef504
98	1	69	\\x52d859849753b1ff2186d19e74ce1938f674ebfee3c5171b46f0d71995c3de95ec864f5f054dec8b6e7f979a48a70b10ed4e0fcbf19f9277c98be72fd61d9209
99	1	83	\\x01c536761755d3caa3bb04426bdd15daf75c621a28402606b45befd89a08246c367386a3dbcd715354abfcc48be81831026e4e718817ac4bcc433855fa703807
100	1	44	\\x7a3f0c887b593e05673602c1e9d6bceb282a754a8f1fa8c93437fa61d5e53861f8af6d04c505c023a18ff80b85923f10ec0a2a4ddaab6ebe0a2a401aea8e710c
101	1	364	\\x3f118033e38bc490b767557c519b51e9dd7aede2cee5772fd258036a975b83c6103ee52def26f476281b932a621357ab93f970b1b220eb837a705e50eb505507
102	1	1	\\x535a2ee74137cdcbd612a8ca3c3f9864af1875302c16e8486e37199ccf853419424706852308f3c6b3cc89f6d099be4d42bdf7243e33d4ebde4128ef5aa69b0d
103	1	345	\\x08e0ee96274e63690fdf1900c66e8fbe1ebfc6c2cb3b699438b1d2570aa3af470b5d2df4ad67fcee605056f30bded779b707172fc33abe7bb2ae0bb19067a20f
104	1	407	\\x1cacb8436ddaf53366de850b504b780329128b68620ee2b89c21c4286194e2b7831bebb70278e35d6d441e3f17171c49132257087b895c8a75db4ada5d3f9c0d
105	1	223	\\x0c0ed4a8d1b39f775fcc4835fda3e844bf8ac563edb1b739fc45f17ff37ef8fdba20f496a958dbb431f05f2c4e3d14af0b458c205f641fcb6649ce580c923502
106	1	98	\\x01d912c499679bcf216c1fa5d06d97191af00229a3159d30b81f7d04cd73d731b1d7d511d00e36a522e9f3bbcf90310a8fa2bbe2d462879e6ef3714a3dc9b505
107	1	316	\\x4ba2c9d43e207c5ad685326edcb2ab62aa8d54fb9afa07b8a9a65836576c979c12811e3febcacf7387905798a714f9e9d2cc40b25356b471f302ab2643af150b
108	1	48	\\x285acc130d596d3d0a771ed61d6dfdc87f291b6609033a23aac71ae246707249924f131fe515f0495deb3be2e125d5de6af203a7bd9312dfce5ffb9fcd47100c
109	1	188	\\x685468bbdf501948a171fbff4fccecaf1697ca5a8775e1a14179785fbe027886ff5629b02c0b9e170b9bddb2b19d10b3a4654ba5f9f41848fccf12e410e77008
110	1	423	\\x3f36c126cf91c31f2f0aba02769f330fe9a53cca9851948a113ff4d837e3bf9e5789528b8d1073fc115cf54ea5e69d719f9399100b98abf57f1c16c9adecec04
111	1	158	\\x9e7def7c0430a09f0a265bb6fef4e056659d999f54dcfc06f1a0ea387490227805559d93dba540c82e16e383cbcaf9733c8e8b61e4c2a1dd87f1976964409003
112	1	201	\\x101c6caddd18c7ba0b49579e3f8aaf7c2ddc1b2c7889333ae9262a2658cd274ff474cc921253aed9fa750f66afb25cc302ed51e0b247e4f6d5473e5cfaa4200b
113	1	133	\\xdd21cafc2b5628561c1d6f69cb18f853c697b4499eaa27b65c022eec02bb6fb1d71e1ff1da371d31113567feb2c5005ac25a08871891f16e7ab8393fd5d70f08
114	1	165	\\xb8c877d812c9b8c672a9cfa0535fdb28620bed2c2f5eca46c8277cf52ab9cfdb0245ecd7fe8c3e283470ded9fb3d5ae4c8172670dd20dd44a5604ad8971ad909
115	1	305	\\x07f2b597a57dc623acccf5d17aa336ba61d9c7a62244653af885fbb4a68cd3c05b3a099a5dfee710de1ee428d39d7aaa8a01d56b2a899bdaadeb91cde249c60e
116	1	82	\\x71f287a471401170b298bab4499f538afc40fcf94731b8c4c08771445414a4a98a9daa620ebea77d27422d619b7364a6bf79a61ad4a6e65862b5d1a16003cd0e
117	1	381	\\x8dde737b26fb05ee5ee3d2165cbc6814b560558d56147bdb8da2a91907ddaf050c89cbe8667d3430f3a2dca99ed577d02481a7f4f104ba21c1a7556dfbeac10b
118	1	377	\\x14276a370fa0c7cbf0914163c5c5632208e87237d63c8f9f35553644650950aedb61abfacef4f429d021f6d4f5aee911bb3f6e1c402eb89dbea603b73f9dd901
119	1	401	\\x6121778491f4141ef29ccacd8e89931621b0ea87f482cf23da5c76b3b6b66469476e6759cf25b390cc8cec5f2c15e8f2d9f82a7c286a917b9dd53a2cc477580a
120	1	93	\\x77731e42d86715bcbe5176620cc379ac73e01e7235434bb91e4abc53dd283ffe34fc91775aae0e764684cd0c97033ee8ab4efb91f9be1175f02f5363aa0ff105
121	1	243	\\x3f9ecab7d7bd6d1be029c2aa5d0d512a41bf2d4c44eb599b4f7e6d8e56afa2950f09295473f8bf15dab7b2875f793f414b1594793b06228e3c5fd6be92a01703
122	1	327	\\xf4af3e2628d29455eb1eb91cdb951cea80ee12976cc67976dd2c529947b8683206526ced18710b65a6207716ce59c922e94a8f44948b7367de88ed15991eb706
123	1	117	\\x1839c5121beca63ab92f2e796c9b8a6e898eb2264dcf655a251d1c4255d716f459b7d7cb5ea9723416c3e28508923e0948d053725c12ad3609138846d4f5fb05
124	1	113	\\x55811d6dd9c4f515be69e20c3453bc177cf14c659809b715733ebf3f10cb3db39bfafdf722f8072fb03a291385651f1e4ddbb5fc929c35e8532c9c5595ebb900
125	1	359	\\x7250c1d097ff2471f1ad009116be296174482817df4e4dbbbfcf1787a14e4b541f48a3ff0a1a25a2ef5b991a8b3e608f9c3d72b8543edf616ba552e7a32c8c01
126	1	344	\\x7f727e5ef6ced17204cb439aa85ce9f44a2d0e09023f7223c23da027578bd177c1e618bf4d47dd2ff2a0ce049a8ff69d7744c664943c091c94014fc1b026360c
127	1	40	\\xd9969f185bca3ca8b5d6150899aee47314477a555e28758824e4a7228160ca41085f39f2d77e3b00ba4127e0fc5b163a430f793468faeaac04d4dc2aaaf4e302
128	1	272	\\xd987d366de5f3d5c9d62fd88619e35873daef5c2ab8b848e96afd4c804f11b23d0480159123ffbb8765ad2f939b0b40acaf8139cf0812b3cd737c7d960b5ba00
129	1	15	\\x6ccb893aab028cf65e0a01768ef48f3e8e1cfb702b37e801f1c9ca75a0d140473eea1f7f34ebdb51373f7e44da7b879001f7e6f7e59462b4ff6d29e9f349e206
130	1	373	\\x3b57b6fad660164d5c228ecb31382f637bf04f02833e12906ed90d43d2cf0b1168a933e76be5c5cc3067b4e0501e98e1ca861a6634acbda490a25cc39477a205
131	1	26	\\x1c57a5e63479c28223e43ee8242ae856b80dd96fb8ababb9af68215cabd37614fe29678c773c3f4ec4a67731cbfc735b10cddd9a5496d3de3c6e11972e93b30d
132	1	27	\\xe6297839f9f28cb1ccfebe5ecf6d7a15de86cd051d907fabdf31ef893035c9d3914c9c931469668e8b2409ad15f933209b19309e24aa67e9fbc2d3ce50c3c90e
133	1	365	\\x2756a37b9843df3f93a837cb711515a7b17e378eb46af13a55db53f71b8f022e4ca743fbbfb96e166e8f0cc2b9a42a76f7b3ad79ce2194153e3413a9a3012a04
134	1	354	\\x1124ae0a94e88e2f415b0592b7fdd9d0555bef729000aa319b61761cab2010ba911992eb653d68416f09de6b53367551d4363e083296acf2ce196db791c1170d
135	1	390	\\x59bc92d9cb812ba3054625ecb8ce71c3d497907b0d2b54c7da32afe5b8878c577f367d0b2a3fd83458ce5ff83c572a39d16d7a5cd74e7cfd280d217ea0e4790b
136	1	411	\\x24774b845c05b11ba0dd46668f67e78769e90a37d1769c1a8931dfed99aa99603e809bc69a67693f3f350a911850c215913d7744f540d2738a95156b1fc8e404
137	1	414	\\x3e6c4686a875e7d3b8f5cf7b6e74c1bbacd6724ed3e7980547e8ff4ff508b51a30f6e97f88e928222d8ab5855cd263517b67ed463a9e2a49a615a5f4114b8106
138	1	228	\\x2e44d884d3bdc4857de1a99dcbc6ff277dcecf9295811cd10e403514e2f5dbb576f6f65e6cc3076f240d7a22eca2fdc8d810e970a33a588d5ca7a2bcb4a06105
139	1	20	\\xee710bac4c34740be63af6a59afa5066c62d284f9f09910dfa42468c3220d558559cd7741fd815f4b33f510a5be12049d8cd549bf3f1766cc62bb8b1af44e108
140	1	193	\\x0a46dbf6decb01be779eeb919bc3585bf1a5af6b07bd02abaedf17beafe3e9039027f6ef6e431b9e5f4e0b9421f41ad867b1e616f669ae17d8cdc6bedc573f0b
141	1	330	\\xf61c1afa8a69be5f91bf45e52e9c801213d1d825f8902a1c6d7e47f35296b6734d606a7db65ccfeba8c27fe6b5d527b24ada4b77dc6b0fa3899a020d73dd1609
142	1	178	\\x342a68bccccf00ad64d06592863901f74a9949046a5ec01d804e21be2d849527ac5ce3f22db3264fcb6a22a3206d15b1eda5968b5f4f9f6423312de1bb683b03
143	1	295	\\xafa841a5cfdb26ede417ce29b43048f16236a1cae184230450925f1d5d1bb290827ca13548a438cea500b42cd61fe02de5e16f5ff431d5c60e3e1043aa30bf0c
144	1	54	\\xb7cc9016ebe13c9535975c4ec2b23d0bb60d5d7468c9564f809b30a147b9e104bc0fa4f8e0c6f63d86f2194a899cfb59906ec6f57282b6b935c0e6bbb9185103
145	1	211	\\xd0a962708fa43fba0de4113e95d9c526c995b93547aecb3662db3e61fdb9e1511e80f5cab8274fc25818017d8380a911a5ff8a05796eb9a61ec95702fc97fd04
146	1	261	\\xa960c1b027da6c2d55adbd842e6835528a27dce74e53cbdd26853bf85e7e56e9bb7c14feaa8cfcc86dadbf7883dc3393fa09f9ac85762cad4d60d2b0995ee308
147	1	341	\\xbb0c5d7317792ba079092989619421d0b06ece4255c2128dfd27604bce2f01ae37a0bdffd0e99fbd759d21e19510ae84bfe4acea83ae7692894503afccaa3100
148	1	53	\\x6108cfec8982a9e6f206bc157aacd950c25188bd9d22d70bb3c330541167eba77a0e1d1bcf4e7e6a5a45a2cd6bb4bf85923a7bb1e3733e8e1b99302b282f390e
149	1	153	\\x488e199fd3f1800b3f0f18e8eaf2bcc96ef8af7f53bb04f57dbe1726b047065cd49233db60de07283c091504cbb819ba13aca80b06325b6ce47008aa9c3de80d
150	1	418	\\xa647a19725f92dcd619bf2ec45d70d6af35a3a3ff1ae60a46c384f97b01425e565885ea90fa384efcc0271301cbb89cc6e6c20f83b9c22dea93af19f7d61080f
151	1	387	\\xc676234f9837ce4d13c5e6c4290f7ba82106ed3023bb92ff088147b917a8ae0cbd7a86cf039ba3ec6bd2fdae473f51e85c5a2470cdeccbc6308267e44da4e50f
152	1	109	\\xe5c8fb9511e779ec1b5a8736d25492034cee62f6d1d572fd32c3a4654ef52a26b551f1d01a6e3fa9623eb054d55426346e50d641cc78474e81cc50154807f402
153	1	408	\\x16fb60fdb53514b3a9cb6860320d9db7824009874979aa47010b0810442f584d5485432d61ea2dc5dc0b0bee799808cd963375b41ca63cb98f7f41f340b77d07
154	1	21	\\x507931284d7441924b5a87682b117eb446dd21c94bdd0e85c61983f1d6ece0777fc88c76b7a01d920bd5f0d2e2636f01fce7adae42e8be550ce1ba9e53b2350d
155	1	6	\\x8fbf19791ff5f7033f88e2d7d1ff0c479b97c66ff70ced27f801a35bfd595eb3297b0791b4afefe4861e5a9b086e148626f95ea314b7b85149ac80938df7f902
156	1	369	\\x640e9e0a1b14635176164c87eedb28725eb634caee69fb576ba22bfbfe0058713c494b5da0b50724070f697399b064d8607226daa9d9f5762138ea4f396dcb08
157	1	47	\\x0784d2dff433bae109b8f0977c62b9d4021de356de87f6f47bf6465ed7d0c524c5b0ecc2fde4b38b3f48b11e646297d0d5da3a59d3cfd436ef757ad49d709608
158	1	212	\\x24bcfc9064a5c1dbf37e4a79c3d38d65b8f05d5b608128f2e63c57e4f0f33fc15481147f76af6371964ffb384cfaca58a11745ee7f26d1b8853ec50b4994e909
159	1	163	\\x9c36436df20aa3bcd3730fb00cf14c6d1c44505f82d62351e5fb6d01dd7fc26e191e0495121be99d70fd5f447bec8e6ee61912cda7ea32efa93c8ee9c88ea40b
160	1	236	\\xdc3c35e8e6d9ad49f5e158c09fb96836cad4d1f48c20989620d1beb5579be79bc8e720547bed1b1c3a3fad320271e9fde4f240104b8ce87daa006b2c1fd8d102
161	1	183	\\x65bcb355108027d8b27d3f70cd462c1543dd5a39ad390036948953a29dbb174e3594eb41c9a0a66db8f6cf54d9be789d5673198463d95185c5ed056ac437a402
162	1	198	\\x64ae8ade78335e251b64057f17bd87f9d85f349b4698577440e88a8bd531ce2d8f125535d23b1de89a4eb11d0230f72b9a51f8086dd92f13d749927096bba70a
163	1	352	\\xa98a3632fec58cd9deef1ef332dfc57ff4adcbf4e3b9348ad3ec20d16d4ee287e8516b53ef95e931e9b3c216d6232dca0f30dd01c28e857ff9fb5442cc03c10a
164	1	184	\\x36753e65c2439e598f9268a9e5945e5f6f9f479bcd8e4bb18cebeca5f321368c0a55593376dc1126c8e0efdec91a45373f51c198ca5e8d080773a6f53614c80a
165	1	308	\\xd57909dbe3857e7e45f5720f90f0e261603272f5c949db2ce4fc31051c851899c9be41cfd2bb2d6e18279972fd42f71e232aae14f166104671b4250fbc3c790c
166	1	159	\\xf3432b97d238b7461584a1ce8293d32fa550850aa75fa2f5c2702ddd4c5ec18a3c8b7d301396ec6b8d37b4dab2f4b9d287f4831f9ef5fa45817326b3cb2ec10d
167	1	92	\\x172f63223ea44f26578c8b2e5319f18f344e9953d8cd652cf419ed8f0cfd770454129c7486f7e1b88ce61dba27ca9f3847495466d7095c3ccd0c7ec26726870f
168	1	115	\\x9390da5a5992582e49d7f59566fb2e600a1c3278887cf5724b307e9ecee730b25f2a527e245e554e4caaf399579a848ccddef907d19110bd32e5908966768104
169	1	14	\\x5ca20eec74be02817d8988b7b435eea086ff73dbc15ed7d1f8fe9dc39a408a17e5de96c71284260a3b26afaeaf237c435dbefb9f430b8d297be87da4f78abc04
170	1	217	\\x20f522a7f582cd4d2117ee8f0d60a06ffbf40571ed88968a4881aa6b2e6be665be7bd95c7d4257314b4c385a5dcb5118bfd5e84ff02c1cebed394edf7d433201
171	1	248	\\x9e321e5bb2e85cb5512b2ae728b3be8f95904157c050c8416672b5de21605229a5213a13a0599cd63fa9a8fa0b3b9186558d6e1d34cc622cb8ab846e0f367600
172	1	292	\\x5cf7a5333eef977a52326ae9c5cfd9d168d482b72e443cdcb2ca8e7820d8fbf04869d153d4c4ca9d220d1ca4f2d579b887ad0f42ba594e0f9256f28164dcec0f
173	1	37	\\x2ea6722c82c4a4a644b239b32d723e84f204c1706b74e035dd84840fca0e7b632d1d5edecf4545b8f4284692884698463b3107a4e82a3fe53e44abd862282801
174	1	214	\\xcdeb97b4cf8e3ef9a1bd32f3c4b0106751bad2815a65cceeb35fe0605fb11e9b9eb5172d25f790ff88393fa3ac19a4eb76b5694a4dfc64a521ff891b865ecc06
175	1	291	\\x8f84ff8da634a209c7508f9da0d194e84001ba227c280b1510774a9e40844e41cf8705fa86abec6ca4f1c0d7b30a198c868f21175b4237770d0a473f45d75a0e
176	1	196	\\xc783688cd18b31860ee37ec32659a9ecf1f6c2335572f854235679cfec7a72797cd87231b3c97a93480a9e69bf9ab18980a553b447253e2509414c084ff24601
177	1	173	\\xf2f4524bf6ef850910092695a21ae75cba02ada71453024276bd98ab103bc00e23b5b6d92e7afa2795e3e8029fc97c0c2d05875c282456147e7b3bcc2f509102
178	1	161	\\xe6e1f53ea3c82a83b60f52aa64dda315d8f6060c60ede4da423790ef28ec5e266b777e74dde71d3720b60357bbda0d215e45a59efdcdbd92c03b95d739443906
179	1	361	\\x00afa7ce7f05d921ada336686ba29ca91b9a5739597c7231d8d5211a2d398b510484dfec84eb0c5e18d0d4447ae55e09fa23f3189e7bb81e830d955116bd5908
180	1	337	\\x8a572d21f50033ba31833d86fd5d4b2c75fb7b0a876489a84d8d702c49f0363a7a4b0a36a9368e2c01fd1b05637c2309ed2ace701f82a0716f69916fafcc9e00
181	1	343	\\x3d20b53a4d268455fab89eef05cefe5694a63c30797ec183fa5c9b9f6591f171045611d8e4ff510bcebee50f8323957dfdea4af45f737d785539ef61e55e1903
182	1	362	\\x8243641de4d4a94e9f6a3fee5e35ba093c885e3f9bac96bc2d068d7e0cd3123b4a250bcb987d28dc35e25fe37702ee4cdb2cfb80ff4721f04057cf576f04560e
183	1	409	\\x7e499bc9d34a28943f7d8fa9317fb05ead5b46801c6fef47fab3ca2b5cc19a94ff37c09f5e4237e6c84cf3c0174f720334d3e8dcbb155865fbc48bece8c9be04
184	1	176	\\x90d880afb3dd2172c5fedd528463f94eed81a3035bb6179eb86c72b9bdb12a2787787c061a9c381f19eedd8fb419c1d36162705f2235acf2ff140c8bc29af60b
185	1	164	\\x77d5788a3eac7f18dc32d8195ff4933aadf28969ed9945cae303c1a40eb41c692dc46ca75ec12bb8b27af312a404d86afca6c37b05dd45f519a39ca96d722f06
186	1	304	\\xde24de8804e91191607d69ef5a373f49e247e22ee8bf383be307220ac4cb043adcc25be92c592768017bf6c2f07c9249f0efb717a4971d3b8ab69ca7a56da60d
187	1	116	\\x260194f52757c97590a4af9b2cacb8e92a848ead241566b7d73c03acc65508cda0522b2bb7b600610b49aa0b6fd446509729f440692dda9d5fc4d1c70af88e0c
188	1	419	\\x3973fb51d632b61bdd1a9f8de28d5dd38216ed0cd9bc0674ec01149e25a738af2109a63baef15d34a9f79ec9cbfb371991b3fb93683e2ecfef47739908b15209
189	1	251	\\xae09b9c03dae17445d41b37f4574d52f3cd666d7f68d665b9a33075243c51af352287d2ce9aeed969b9ff510cc7a81b808e9b74eefbf94feb43f15b2e8b0ac0b
190	1	103	\\x185c7f248c217783047013cabf19efc1c1e8f9dfdf6cd9f16c91aea489c5d288f4e528e3df7bd570fb45414525152365affd84552c58824cbf622ca91cc1b407
191	1	28	\\x527090d2e508b442077315cca91b505d283a03b044b31bb8c33be2c74853d7e0c16abb7e94f978d1b22dafd8f04e4d5cc0356fb9eaef602cce8f364b9b97e607
192	1	106	\\x7f43d82bd02d2c4e237c789ff8b0f78cd00aceee919c7cc9b1813021b22c2994a1752679c233f7d3bb3694dd961d30ecfd88671c42d76739489743e88038d50c
193	1	107	\\x0100f7349aed3d5003dfe00343e70bbd6e693d664c35135609283e7e266b4a956e4aece9a980a1fa071c3baa2bfe07d9e246b1ead0d67b35f300153b2afea90b
194	1	88	\\x14a3fb2dd9c84ada5f565760ce2d7ce9a803a28d71e10294468cef7db6c8d3efd8f750e5d6f53b06cd5e5d4f6ed4f7f1a64a75f13083c407565b0920dd2e0003
195	1	12	\\x81340c4fa6e7b305542bc254db0afa727c1fc8d8e27c89da96623aa3d69ad5804d090323b69280a9cda8bee53bd3cab103fc3ecc8483d9420ab661c6765f930f
196	1	145	\\x6a3a7255091a576a4a7aedcf98b74eb6e8168be0016394041fbf1a3bde2f484788a60bcd231ad4f2985df7030892dc465a8bfd92ca5fc7bb8befba3808f7ff0b
197	1	371	\\x5960db11f194b8f2d96bfd8051be1511ab58fb7e1b8e2e7dae9607fba60cd812aacb4cab953caf0e9bf7259dabe5b11dcaa9eb2e81de0295a90a412047dab009
198	1	405	\\xd673ec79fdae2bb22bf299b5246481646a28945a8f7197c88db67dbc5c89304db930cf22adfe8e41f5b5fafb62debf6e82f8ca001819dc3ce970816d5fb50f03
199	1	326	\\xe9a66a809f1947326bae1ffcd1ae6b5b7ef3c99fcf721afd2f725f63ca5dd752f47575aefc37afb72f3f072bb874c89a474c4b367668eabf9cc3164586c6b30c
200	1	283	\\x49c6c27073c8a1a93e2fa9024c715eac1e3a8d607d992a72e5f3ed6e9920f1abed50d5191c8e2bff38819f9188d8aeaf6f018888aaf726c9c14b0c7f9e4d9807
201	1	5	\\x7f3459a77cef965359d050dd4f40948ad3ed60b0f738438c2054c1c5dd684cf82aecb6ee9eb621f10e63f89e35e9daaba4a92205d2666614af80c0b76a50770e
202	1	221	\\xa7777fac42de4a53b012876823fd3e91221aeeb1e8f0ed8b9ddb857b4c5769c5bc3c5ef9c4f5d11782a7f95633c09e3678ae145d0545d2ad332b6b4e9d27bf0a
203	1	90	\\x92571cf0b364426ef8aae4c4da22b2e9ae09a2a298eea16b189a7664f00dc3647eacc92b4a55fad7d67beaa1de787c54763d89931e064f48c66d6e864a0fc704
204	1	325	\\x4734f43ece5f69325a265f16e9992242cd274a849295e9f7ae312c693b3762ea90f6babfb430976ced1fffb4cdaaefd31a1d417d4f74dc4c2a9fea3b58c1ee0b
205	1	391	\\xda98d8e21ff05a5633b9b731206b8c9c684ded885e7eae36770baf2cc251929c0776129e805d7f7f22ef51dd7a2cfd7534e4e64e81489d2136918ab7ccf5860a
206	1	255	\\x9bf72453da7cb724302e419e351d796bcf6cffe47f20c37f2a612225fa6d69995b3b34f96cd40c61d432d946d49b562201c3ab177e9dea6f64563fea944c010b
207	1	123	\\xef3c783e68bcee33093fc0d5034c2724f8fc88e80d1ec649b6ffc0b8f77c25bf63dbde05327ea2b867c53edb218fbd3d23873800744330d06ae8f3a02b61b304
208	1	253	\\x400d486bea03f841a31d8456abce76f7dd27bf9a1847f90b9bdd4141496c57b7476117be8efcb70e9097d7a3f835493795ea64f7e6563f55f24e37868543d308
209	1	60	\\xcf72e647d51ef407c874f5ed9c32d26c4dd01968f25dd6c7f95f23d4b1c032c31a85d1e48bc1ed7f291fd0fbf5926cd44e878ca19efdcc41512816a5df9a270e
210	1	91	\\x2ae117eeeb9f12c86ab6d1c89e6b62d93fdcc510e4cd68649fd822c21fc4fd8d607d1a94309468a7bdf2032c8d02322a06d650bb81ecfa1081e17c9e146a7e07
211	1	45	\\x6f09ac6bbee85a2c4a6f72b25c54c15143324b7ad36f722a043c1a5351479039da5c47fdb50a7ec4652766bad504c39f805cf23ebee9d77a35bfa80fb3fbaa0a
212	1	372	\\xdca07426c46016b5b5947184e572cec29053fbdec07ede4c8ee5a0977654c6acad3857fe0f925850e5edb6a93f1a3d7421eff634928111851416ef5c7251ed02
213	1	320	\\x887d978bc10a26e55d750e156ad806bf80717bb4da3d1a869d635881a49207ff9ecb45a5466d1e09d9098201513dd4a825dd2e295c4a4ffc51361365565a8705
214	1	65	\\xe24059b9b248aa95cb00decd4dbecbf43fefa0c2c606b5db4488517ec854aca5fa64afe6d0cb6cc3453b0862c89c8c0a69a521d1895c8c99a0df1d8440c4ac08
215	1	225	\\xeec17732bb1176e69fb30a89ce754ae516eca2710e22fee52b427eeef0e661b25c3dec0924bda563b1d8cfe0897ff4d7c26985899254cf38eaa3666b4b79b603
216	1	242	\\x7699798c8e104b6e39de8016199159de9dfd2311411052e16acc971e8f014566214084de5b0fe717a8dc63e923c2c16111aa7a483ef5f24dee64a5af6576e60d
217	1	209	\\x2dde0cf79af562af714fca2e91acca6eaed4f853676d2a4d1a2b7bc5443616b59e8b2571cbb57966256f5807b3a2c00ef87a7b5418bbc12d60b308035f3dd008
218	1	30	\\xbc029e2d76b94e3b3dea520279d8d25258e4d76ae913e1344d2104921a548d765087c25b5b0f7de30a1fe4febb55507607bebec57766dfc8345f12ed0559c503
219	1	321	\\x8029e8d553a3d5611960dcb17c08e1d74c2d38e7166eff621dfa8418b9bb5291e3d52050bd1156b56dc2c5522a7d3f8e9117be0da69dd4b2b38fd78a8a29960e
220	1	346	\\xec029df4702fd6d7fc7c16e9846274bc99013e379747420767ceb9fa80ca2ec360e24b1c293e86bac6fc74824989612e75a503ebc89f092fcd5b8786f3855101
221	1	33	\\x2588c2fccf58ab3ff77bcf64ed9e6ae0b17cf49eaf46b160dc4ad9120ac0d9891a8a7d05150e9ead8318412548f705dfed8d538dcf17add9e2dd3725bc69960b
222	1	367	\\x09d75fbb010fef838e9339a5f8f07551e6d739e1298903eaa46195c3618baec9fd62d847bf75aa996220d7bdb5ce01f7e32e2559ed5153a6a6392367778a6406
223	1	7	\\x318f4e53b1282d987a8b1bff03412ad258db68c4a24bb4a243ca9be90c7212d020ae54b3408e88049c975e54427ec44c1aca18185244a117ae36161ec959d507
224	1	22	\\x55a036f9a71c77fa93caafe27cbb453e88d469bba7a4fc5b9cec288507cfeef1f5f56adbb84fe79d6e68b15c00ac4060a627d45a03124fcca6184b25f3b72a0c
225	1	146	\\xaa6cf1e50e92fe37256f77ab096fe16385208cf9275e27cd6a10753ea03f126ff866a0d485f196e815956cdb516cef85a835dab2af356b73ac161326cd4c2500
226	1	50	\\xf6da3eac9ceab88919b28ff62350055dc9b68fe2685e544ba16a167723157574a2ad547d8ddfeefe306fe75bb2ff20711816358e5b23221d7cc16713e441c005
227	1	422	\\x8a1f1f6118167b924c1c62383bba6458294d0caa115965d8fcc79f805bfcc09a36c61fb41407b38814ac03c62bb7c541108f46942965e02727bbc87443e44002
228	1	339	\\x0961e851d5f8c7e5511d38a276d9a993c467413987482ec9a5d55562fa061bbfb0e6bf5f849b0ecfe9f4186dbee2ac61d16a9efb44d37b16f5607bae7e3eb407
229	1	368	\\x450f79bfc0a4ba095aec8b30e9eb8fa95c0922d3e7710bd882ecc893b749e4119f0dbffaa54b181ea54d64f7fe051827f0bb80f01f1054f9bb186f7bc6995408
230	1	416	\\x967d1abd750c48f2668ce78cb94087f13351700022eaa3dac85e2a8a7d37537e957648765ab26d330cdfe08941e1e4fcf2b0dcb58c58a05fd02315ae2930d60f
231	1	300	\\x15740133dbfb8155a52ee2404d01b06d65c615d14cdcf7aa2ccf517d1df3d3f5b47c5cec6a6e8748b62a457cf240b5707d177b47087513491b0e56b202c6a107
232	1	79	\\xa37a4fc9b282c3780c4448697ee7a70ba60a7d5edfa2d36d8b4a66185e1c504333c7da024cab77c0e40e9b8095bad0ee7cc56c89abe2bd16b645cb1115fe0202
233	1	301	\\xc0ffc75dcfad2ebf736d5408effee9916a2a03d28999b52c4709648d83a15dc6b7e7d4686ee1515c8f775c58a81dc04cebeb94669929ce36680cc48ab4bd4a01
234	1	137	\\xf211c6eea3319bd2e6b46d1c631ab1e6e03534b82e9813a791105280af1020ec73b8c5eb7ee26a16b22eaca8d0c80cb34a5d58cf00dd09cd76eb5187ae7b3b05
235	1	112	\\xedbdf0bdeacd6f4f3edd17842ef87799fa2ed833e8eb05fef9c13efdf44c7036a073218fecc96cf48a30d14c5cf7883e65dd4f7bba232cc7feba1ebee0896902
236	1	331	\\xbf4b078a167baa77fe8d2ff1a121b6ec3938065a4c66df0a99b82970fa94b389fadea04a361c400db4fefb815aa64acb856f1ffd9e85ab685c9d46d6a8ca3206
237	1	114	\\x3a4adba024668e881e19ed6c93c5322414d9b3a74fc120166ae12e86f810f51440caae1e04f8851854b17d616402d6302352fab102898975e7740725b6f0c60c
238	1	102	\\x6fc7127fda39e2122af5db482749043c6c3321c4b09f86c4fe1264f74dedbbcde0f8ee0c72dc461b4ad25067995ab224d9adb645bd286b94067e2eb1e6faf704
239	1	288	\\xc5c56b98427b65e83248aa779b34ffe97f05427d3ddf75bdb3cc868e8fcb501ee9b54e7726f4b7dc6c4f943eb247caa5d3a0ab39c94dc5de5088232cbd4d6c04
240	1	3	\\x74304d3de6a4a7b622d9233bf2e8ff771cc122b55cf2e5c3c9e36f70ee201a80f557642cafc050422d865a1f541b53bf8d20603af19f822514a3a1fa82587001
241	1	249	\\x4c37da9a1819999e308207bf8d13c248be0cd5e3c4a79a985f0f5f3981f9d8bed2fb0d4b485b175a661ccf5d13a8fbc6e3d7dab32198189118180d0a039f3703
242	1	374	\\x9b3ec3105862ec57e4d9a12b8ae43f26123e46274ea3d93c85674a19abd70ba839d63e15a3cb32f6fd3b9483b557984d9d229a65bac5d98cb5d1a6a80dc51b03
243	1	150	\\x5242157381297bc760fc9020e60e8e8dbd9588e084daebfb5f2889acfe076e014f5da500400c99dc91b397daf33ca3f7de11ce4e6390e69d95eaaf4ecdb2fa06
244	1	142	\\x13c3b89fda3feb2dd3fbf8d3c5083c5e5cdfbed752206aa9d444fe9a50597dfc6fd8adb65661d07e36a2a49885b8da07e5de4d34160820f07cda41bcb4d32601
245	1	199	\\x57786986eaa8f91cb0898974000ec582b097ecd3131bbd2d3bed6cb4ce96ec7a6baf7d267088b577eb35dc7e1ee07c1461c1a50ba863516cdd95463a5df34801
246	1	57	\\x68eaff8a21cc37375b39fc284940b64914d0a35381c210e335c22f3e6973a86bf93116835c2d13013fd71c25eee9f3ee248d1de706e07a7784d0597ba5935609
247	1	289	\\x25c916b0abbea94341dcd9ddcd6db408786250676ec69f82bf99ef5810b128cc8931405863b59e0f942c6f155fb89bbcbbe269a76675826f9089a33a4962350f
248	1	36	\\xb0591891b44b06ce8aad7d11c3a300542de9c696fe7df221d6c9350c0b01357c824942af98075589c9a87e018c7ea5341b1525d04ea1276684892c96ce10220e
249	1	136	\\x5fb2029999db4cb5264532fb9d042a59e817741c82fa2c8813c13487b036d695aae6f38530b7127fa2c321c408dc4873215fd7986208cdb57b6cbf11dbf25805
250	1	376	\\xf0b542c7ca647a8fecd6515b75c2515ef8db6fe51da78105b6424a281723fe2732f047aaafb4b5cf363946dd999f281be511f477cea1091ca04eba30a2a13e09
251	1	216	\\x8c3c9f9fab3f344d5facb6b1e391e9d7d1ffa4baac121f19d434fc401351a3232847c9912ed183ea9d1dbe335fe6e8e875a633aba24657b4755ae4713200c70a
252	1	180	\\xe86e6192b5e85111589ddb905cb651d9fbb3cf10525a6ee922c743831cf7b7bb644a6e2a5014980e73d98599a2af5b4aa9faac7dfb91528a5321222f61ce1a04
253	1	208	\\xd8504cd17bb08393de2743bbf992e9f2d2796e8335838112c35cdc7a27a07e1fc75596478662d48a2a3cef8249cba0988b4163393e5051839c5fd889d5482d07
254	1	80	\\xcf3caaab83c8a6be656ce19da68845036731f49cf0a7018017d30646c302c9d5b566d77c8c45e45d50908952cd4d607911a7981143c0e69ae600ae869f9cbf07
255	1	64	\\x3f89d2968642b1cf235786415e6d9f22de3f13f923a5c9a56507bfee8bfe513566dfd293c58c8aa4fad273e7a06c01906456a7c05ea75aa3a8035f36d56f1e0d
256	1	96	\\x85b31eb03bfcf337d9eba29e2df3f336aaf441cb63c05994a59ce71a85cd513eca8de2b08e23257a2d702a208f8bb550cb1895db23e2311fd1d295bd3ec50202
257	1	215	\\x2e125812cc0697465f3160e4aa76580f28f3cf97c82cd4e912039c4405db2341f784ca10b54c2af5256627c3edeaf12a89a34bc10a4649ceb9edd8297971bf00
258	1	298	\\x02919e3c43583c621a8c9fde04a5791023b461efdca1af9ca4eb4ba6e308d8231fcc41dbdf8c6f46aa98b3f8b57680d02716eb37b0c2479c806b7e6ce21a930d
259	1	322	\\x41278cc86679bf133e7cefaf1fb6c1cdb6c50cd2e81f6ebc354d02641910a3fb84de22d3673d331fc795516f0c514239007dbdafa43d36464455bc752b9e0b0b
260	1	81	\\x36560881d9575fc7740186b545bad7ff57ad9b362dd5d803d22c98bd5b3e13e970193fab8ba7035a1f1cc418e0c07113e2c2cfbaa914d02ff11a43be65cf6303
261	1	72	\\x5b90d7a0419b1dc32fa8d02174a25f7982d4d073894cf3dc2e87fb5bdbe7d5d0bc8cf21aadd4325387af670d0f9c8458a44e3d95ad447d3f00e41631b1c1ca04
262	1	154	\\x4985478f7aac53b950dfe463d9e92ae1843b5b4bcb7c67a12685f18b9ed987bcdf105f883ae53a11416f594a94be7fcf81ad6101bf54dfce480f791d8250db08
263	1	207	\\xf8e8b3328947909237605acb6782478ac33f525d06a90fafe118d3fe0da47ebbfdd7633af24d322b439dcd11fedbaa16ca5788707964044890ae281aa7dc140f
264	1	256	\\xfcf8ce631256f15de30319010e9f26f7b9937f430c25d588c3f57d59584d409789b8d675effd561dda4fdf7c84dbb64056fb3b2986c9cbf2c712938fed4a4d0a
265	1	273	\\x3bc2adcb01f071e3c786c0a148fbfce31a84403ed8c7c315333191cabb660be06c41719b218f6d2560e860e84acbb32bc658e60dae73e5197d9b37b6fe057a0a
266	1	56	\\xcb88ab05724ed98510238d0f06bbcff272b6d25085d33a7a753755fd71edee53f5d2961acfdb9dcf55949f7108175e04bedfaa854e8a166cf6f35d81e6cf3a0d
267	1	356	\\x4097c526762aaea902f6b6e1e2f0d8bbd716e9824e8c17705accb60d95e7beb351c53be769ca4d536d8d2f9e5b81f6db1fe01c131e0a62f0ab61957fa194c708
268	1	62	\\x12b1578231c7b0cc2c23b8868aabfdcf94e8e03414af85e5db3329bf329395ba52de1bdabeb7142f7a0f42287b4bf6ce7937bb16022702b18e93c4d1ca686000
269	1	340	\\x7f18d15c9774157f89a18df87f2f88cc47ff2108d3424b1702672de4211dc9cdc846fa37645c531cb185ac5410726d71ef88d54adcf21511956648d73b6f0801
270	1	200	\\x441a0a5185aa47d8178e176cef196837e0af28363d86a931fe459f463dbaae988e6c9dadea28bbede9fb57de47d6399c8b74db16136aff2a1d1adcdc67b7eb08
271	1	119	\\xabc96b7126a9c3d6620394c2338dc703c416e6cce6045a002284b152d702dd6008cb8c5ddc43fa71fef85371dd91b239307d0c3bb7666a23bc1041aa71484d0a
272	1	399	\\xcba540a82327cc0bf91d52788989021d23daf4a3107edf475dbe8587fb8f38e3766ea210a6aadc139e2b1370ad30f31c68430f0d0a6a07cc4d51610bb352c709
273	1	302	\\x9bbcaa2aff7cf6e8b43f242666986a7fdc9fe030092063e8a15566e2b608929acc66d446b3439adf8ba6b3ae559d2defc1b589842dd27d2cb97e8bb8c8b16907
274	1	398	\\x9bd723c643d75e986a3466ab5e6637db3be49e3c4bfd327072b0f0d94fb63ff35c68bd2ce8bc9958fddb646735e4ffb788fd9903dc4ff8f36f22463772d7f20f
275	1	314	\\x2353b3eac500bcf3ff1d0698c2845603683ef4bcaea7ed2a23aa99919b8f46e3845fc9d3469406d1474f9818f9b1b8984f0c533cada507753a25f1f95a7ea101
276	1	234	\\x851581f10e706ad60892f8a1e675774b2a2dd281208b808c356716721e4872cb8457744b988207daa2c9b52740c6a247542fae80a83205ed58eb4930b276d505
277	1	240	\\x6911aee7d93d970add7a25e7466f046806760c06e4de66749878e268268c473f6beaef85f7b98db7d2dbfeaf674fcb7e55e2fdd015ad23cbfb5472a23ed7c403
278	1	395	\\xe1f7145ef665b1862d7254b763389cb076665c4970d90c5d034d14dc6e2c7b8f76977979b087ddfdfddbf33f8e1dc6990da37601a99f2c1adc3047c9f3018d03
279	1	317	\\xbc73c778960721f54a8f3c839c4fa47155765b80ac00e01a58e74986ad4dfae59235c0804e8fd5c298218ece8ed122f82c4242e2dccdcf28c4f0fe519991f606
280	1	149	\\x7c20c323c0fa9c13d64cd282e94051f16f878dec6475f9535b5b676d09ad7382fc300df32f48bae218d4c87e3ee30f73bac7604f2abc08af7098324cc57f5703
281	1	277	\\x32d27c2449b61bb6bf67216a95b4d25063b5768645c3758e83e73fc51572263c10dc018f3450e0f6dc155afcdfeb2f94e480a38d4403586e9706e7e4f4693902
282	1	338	\\x5ad3288ba866f891d08653b0f78f7a39a13761bffaf62088831c5c605bbba7ea83e851e677b52094d7df7981e01def1d434ca750672bbf66a5f095c5150cdd00
283	1	124	\\xca6af4205835e9c5a1fa800de3d6aec6dec893ac3dbf307653a9d5ca3582d93e373c8e9bc9edae56283f0594e8575a0dbb30de354bea16a16db17e6fcf7b9f0c
284	1	396	\\x781a0da4c35405c249bc357d5586d3a020bb8862f71255469bbf3757c91c6b68ffcf9fc2074ff7015ebe5768528c2621bf97fed187ca86da142999c5df0e9a04
285	1	95	\\xaf6981e2b45344f6be6293db0edfae24825f549fc53f5125d95932d7865e41714093b7e57fa12606554eb6394176480cbf52910a5701c4bdf26defdaa589b60c
286	1	318	\\x00be5c90e5d02bb5e9b9ca8383ba91268bdfc9405302e3cc94f904832e8008974b8e75c8ef1873db7c51551850bd295babdb3139687d708e669e660b1f48bf0c
287	1	393	\\xe82f0adc5221610bc481cc58c5f9938ada6cec2c04e1d9bdf47cda2ff9f2f84655b155c4f3e780e04c6d196660de3242aa2cf6c0c4f93a8d7aa7ea4735d1c80c
288	1	104	\\x76642d09b4677b22e9d792f5cfc3266e0845d30482e0ad2f2d9a4fe398384539e739664fb4c43ffa5be8d7a8203abcf71e035434a2c85a702677ad7b1714ae08
289	1	41	\\x06a4be66eaff3ecf72ed5308adf2d52abc59202d125ad0965047adacb83186b6525c9396fe8275962b9de7d22b27040fddadec26944d088fe5e8e00dc3310a01
290	1	166	\\x2a41e216e32ba41f0ab094f30c766c8d296e5861f97bfcfecd00fb51d113084c5a566483cefbc864c609e94a7689aeed55458784748c3d5f8a1a1ea856d7b30d
291	1	89	\\xe0b70099f66010b09755f4bf5905789cd33134c5fc2f08534fdd801dc576e35e2dab6a38b04967f02fc9dd0f07ff7d32dad45bcac3a08b8d9ea3427fcf6e7d0d
292	1	285	\\x23d8d95e2ff4b39243815b3aa0c01daebae5454c086f7db8f699e5018d52d5d75b40cd9bfdeae545716c49c53e661b4db916eff05843706faf8df260ae29d201
293	1	309	\\xb3a2c46fed2ca0f6897e6d56dbb2baf8e121e3b88369e8074e7ad02cf5c50b86479d04e9551b3cae9de5b5e3239cc56c17680f24ed31ad081985d5c94002c705
294	1	420	\\xa9a2c8c31929e5684cd9fc14763886f22021cd949f52613511c4bedbd87f86af9e47e513daaeef475921a95fdfe8ac2ecdc2b763c10724bbb76542a7c79fde00
295	1	78	\\xe75608b40e62e99b8edbcc40e0e7f5b09bacc867ebfecad9f31b50008084dd5c3ea30c22cadf89f5eede6b68ea2a9a6963d92680041433c98aa7ba777c4cdd07
296	1	4	\\x33755bbb33d2f5ecdbf99e2482222e117cbbde6c017f3307e399654b29dda02009b1aa1a857a18f13301816f90a2870ec093feb1d989dfab63ce0fdfbff4210d
297	1	284	\\xcbdfb5774d89ccf5ffc0691bc63321461a2fb89c98b7b6e6bd29b128dffb19b3a597919577743ad9e4e6bf6136d43789a0d1b5bd5de37798ba6d3e223119380a
298	1	402	\\x9d34fc00120b5be77b7a8eb3afc80c1082cdc1e6d104a1b64ed57fe9124f7e277bc278f8748b68de5f48ea0c937fbebe6eb3f8087737c61becd1011c408bcf01
299	1	378	\\x8824a9f228709994ea94d55bdf065a44426c9a9f51a642a405a89b0aaf1c551bebb7daa3c4bf4e8c2d705cb991d37b7cbae3c3d0806caf4284b29850980f0d01
300	1	264	\\xb78ce34f46bf820a00df381a9dc63f4313cf69d3d4a8f478c62744208be5c5645ce4bdbede2fb47789c2773bcf45b4b0f99beb6bbb5514afd67dc1e244be9309
301	1	97	\\xc4ebc9d28906194c957cce15084d171e85f52141ae212cc6bdc6c963897bf7a957a55e1ecca40d88ac64cf11d0f9fd2176b21426fc466a508a140c27a143c00f
302	1	126	\\x0ea114a76519963d15e1c2fd01ec7e731ee424459027df6dffcf63d04f50c43d6bef719c6561834f8b680f1cd6ea3b2137b659120a35375b3bf3ab9b75417d06
303	1	335	\\x97bf1d1442384ec3192b21a5c0714a94c6182ba111c724f69a17fbcc13398e4f44286f5807757ae25a8991029917b736f58ebac971f64a26a4603803dcf16a07
304	1	245	\\xf0c999d4d508ee398a4fdf5aa4c4bc489c389b6a928438f4958891bae4e40d46a3d42a127eb2d5ac115d651fc7bdc4665da72aeedc66028464b0b4eb0e2c330f
305	1	66	\\xe990c045b0dbd7ac3806c2ff73cee371444cf7f051984c41774ed9bc6e8985a3d78ca13f6214e71fa2e3e02224ef032f5a093be431808e26a30370584754d603
306	1	185	\\x0b00bb25c2b0ebe1a73b99e025f249c10673b8d3c4f98712a7d959fa5a0bdc98bfc3d2c9c08582aafd87c23b8d1ffdbafa8c6a1fca32a6860b474f85f5fa9400
307	1	366	\\xfd3a5ab9a2625267996cd03f37dd279872873119d7761aae07ce69b0474866b0916871056e69c2fdd3508e9640f2464c1388a7023198d5eee7465477a7d46c09
308	1	328	\\x9c17523709d5ccc4143381f9e5db52efa3f8202b9bddcddcf591ffd945ec5891592efbaefb130f6758a22727c072783ed0638774617f3713a4afe602f379b60a
309	1	118	\\x619db14c69393578cec94197b4df2917f08e0c25babb6dde29a80df936de232514f088b0924791057d8627464c5b461cf86adc14e4549ea98b8f44ce12edd20d
310	1	231	\\x2ffe5751562f33bd91acdbfee15ba0e1876b12df12b797e384dbc34334b4e0ff5477c74f3d2692345d949ecb71fb9614ec948d3d6892c412bda143fcca16920d
311	1	2	\\xcdcbb0bfb06175abd12958ab2ac167214dfc02b232fca1195f03b42c0058fc5a04a57b35ebf45963a054ce8651d5b5fab16d091ff1d7969ba205ee6b83c8d60e
312	1	222	\\x522e4eeee301d9ef9ffd4f0c4c77035c494a5a58a711518dd3befb0fa4970690e63acaf01cfbad13aa888d6d973a9d5aeee92fba3c9051f56405bd31bb7ac10e
313	1	266	\\x69d9be4610cdf627a8c2abb2d92ad1b94e4eb363fe2653d398c2a3219a9464140b938dd27b4e39e4260f043ab2423d2726ca51054f98913fd712484cec3e8407
314	1	100	\\xde3b59077c35c41e9059aee7d393107ddcd4cf08257f4577d2da8660f84d09f1b3d6500c0192cb97868c3f9c9a5c6e32de1f3dfb499fbb0dff60a0274d200302
315	1	239	\\x12b3a1a34a5ab1065b9467fa9e83e47dd3a6b940ac69413108f37e502fac8a1b95f46fe62a443d14fa1b3bbac91b360832c5f536a88e4e574683d60e4947e409
316	1	389	\\x2a93128932eacf01fb222b2e41548d2a4d86d3803d33faba25e0d9230a666e0bf38b6d87397e0f9744315803599b0b344d7187ad83b3b01c1902585164e88f07
317	1	421	\\x985fc13ba5e78523d7dffc986678114f61b906f01453287eac9721cae95f7e6578d91176ff781d0efbbde02346b6bcc8e4b1174528d1a839b7f67804d7438b03
318	1	375	\\xea0ce2c3d3e06f0d329ee4ebab90862cdb6b2f7239ce6d367dc430cfef8420c2a0f8503e0fd27ac2904ab96b1317b93b92600ebeeac380e1d20051a8bacd810f
319	1	75	\\x1055f03ee873eba79799868c7e68ce95267fbbd8b52801e5792516236b59e558e959b25ebfd4430e39a5d120f42f4acc02946f6c9191179b659f3883f2b4e903
320	1	213	\\x8ad96f18b846825a0e0ff55991c2fa74c98123c1ae1f575cbabcba88eb90e4fd0832c06a1537576e15469aa4468e814df5a71ed4fe983e14e6e09ebf7c40d30b
321	1	10	\\x5b743fb188aa32ae857a93d36b505a79b8ff5200107965e563d2f107aa236fa96488d4b33bd11db30b3972baac18e754edd7d25c232b8c2efd0528b2c0899a03
322	1	84	\\x859eea606ad00fcba214bd55b7c3ea933706d8f3b028f9631eb84080d98d88239290969bd9be24a9766e64479b2b696b3ae8959e3888935dcbe43d32f8a4a101
323	1	52	\\x08e323b2dffd4b0dac1a2f6081cb017b7ea9d446db4ce766ebf8c6177d2117fc3f5897aa7d7763671ebe8d3f111bbca48728c18f4420d45b9c587569601ab20a
324	1	49	\\xd5ae6cbbf5ad7f9eb12002470054b1b307cb766bc7b26d00d037bd85dd130bbc3b96924bfbe8ba7469ecd11f2e6157e49a240734de6ad84e91c37c2a83a0420b
325	1	87	\\x21e987f0ed9f056fe07c6e1706cb0d899ed9f9a32a4d4be16bffadcd3b0f9dc9a7c898202af92d329a91e490c631dff669a112890646767ea3ac17eac5af630f
326	1	299	\\xf26e48e90716407981bcb4e91671076af5df1788a453c2e80b83ee0e68626e6924a697edd0b3cc6b02c0fb903a6ae70df40a5c14d35556e35a29d2f0e79bda0b
327	1	311	\\x688fc30a07896bcc07a7d1116c515bcd4238f9b20dedbcf68ad7364e4e975ba517ed313e74a26c74ff0cf9de0c7909af56fe6647b4e043d7668e89abc843b904
328	1	210	\\xedb09bd9ccd33d0612db09e346dde38bf13df03be08d4105486f0943c21483793898b9319ced5d5e3883549ffd6e553fc2d0f062faa2c9603b28b9c436483a08
329	1	220	\\x6d32d874b42e8e72f09fd415f79e8b89bd7ce8fc02f264669137419d86bf182a52e5682d22fa9beed0e7cbf223b4c6a459e4d756330f839d5415ab353e5edc03
330	1	140	\\x53176ddb3aa233331916cefdc1b6f9ef3b612144e53ef97a5ededc4fe6c36c4e555e7eb3e6628ba0f802794c0efdc373a15d95c45b13a4c0ce4d47b873df450f
331	1	43	\\x762f274af7d33925f542b35a8c845de8d80c1b7d1e8b5f2f659a0a06c7343f7bac275b39974a51ad8e2da0be6a3dd865e9a961d0aaf4594a2fe8f206020eb203
332	1	263	\\x37ba14f3da1d4e43ceff2191e6fbc40a4ba07def8584938d06f8983e2f81bf81ae28419ed05a9e40b2a377d2cd8b0294aca7e3df20c8fa3e413e32b9daa20a02
333	1	141	\\xf699eb50b67f7918e6fe1facd1cb41fd5121e6ca3edde09e12a58ea9908ab5eec2e12d4552d9fa32c9784a31bf01f85626146c3bcb92f580b94cd683ecdb540c
334	1	29	\\x52677aa1b3f9d6a54363d1980c3616123c7665349c295cf6d4cc7b597a9f0d0bd9b4095de8b87be787b64cb87619c1f6de54287ddf62436efeb5faff7d1e0e05
335	1	73	\\x42a24bd55a95934f631654c8ecc0be5258ea68cba130f5886ac41cf4823fbd0648b837fb0e946d276c3f93974a954bdb54b01183da4d0df51ec1f38fc466090a
336	1	385	\\x8d5afc8f30b566923a5d2544ec39b70525154780a53ad8cbe174c11347361c207772e994bee112bedf6d804d0960c5009b4e9f6b90218131970cd74e64a8d306
337	1	227	\\x72ebabbe023c4b4beac5244389c8437f4df112797ebbcfe48f42f04b38e17e87ec5d2ed07fe3e69a5e14e52d134fda4b80f8d513d372690798f8215c157e5605
338	1	34	\\x493cf3fa21b0a870297e52668e37b1c17051973fc4bf0b9151011d6ee6d7ef265da96b7eaa0a9134090203e8bc76c0b1acb83909f7a753ff769bae4b1fbc540e
339	1	313	\\xa073841d4c00d60d395a29c89be1e387358110bf7ed687d09aa42a461573bd88ca1a5bb11438c4e1473c16cad4cf29b63f72da04f100e773dd4aec85cc585700
340	1	24	\\x687567ba7339abd9b788ccab226f529f3452b8e4c6d880e087813cea176a8e0cf18f7b885cc113058586425518bd7a06713f81a5ba0908d3c73695af4dd0a50b
341	1	324	\\xa2a9d8c58ff18332e736ba820e07077a33e56cae2beaecbedec38fa7ba20ab6838bf530dc0ad2817824514f7d7e906f40d18f96468a407e7a6e9dd6e18a80601
342	1	415	\\xf440c2106a7fea69bdb241a1b9e0d29137e6752f3d258e0ae2155f65f344c6b5c22d953ea2f1d42069909af48ba41c8cbfce338c2a3ea90098307c17427c3506
343	1	297	\\x3ab4650b634db0622d670918d7630111af476919f0d8ea465fadbe4066a07a62d394c4dee180c2e123ad4bbcca9cd0828df04fff8dcaf550f320e18f1f4c5d03
344	1	323	\\xb7726dca0f49d3389a406681b68342bce957401f4b352a777433a5e6194dcbe0dec97c36fdb0f23c796c3c12b85283c9d15829f151173c055d842dc06e3ebc07
345	1	205	\\x63c6682d6aa78b4a0a1de97981f59d1fa245a8b5f609349eb51a04c0cd3c3948d9e090d8fe075f50561786240ec2305e6b884b903855014a7a02255cb1265e00
346	1	417	\\x37d1339553723caccd3f2b94f4eabd0b5b0abb86eb536f75ed9485e066ba1269f391236c14ccfc5cf900ba97dffd60f7794918ca3d67e32c1c38eb8c2fca280c
347	1	35	\\x1dc4cf21c82fa9a59980390b9888fec4a3e43529f72bdb99a02f8f0c630ce4fef35741599cb510f577c61f1d5e98a72796df1b685a90aa6febb0d6e1fc49a20e
348	1	400	\\x421091d517353401ffa8567c303afde725f40782c994abc2bdf6d82958d9593ba6654ff4fa8b5bdb42e3ef19b2215e021ce6c2528f11b0c23f3308264c846b08
349	1	160	\\xf2e658402751566353f25f3390d102ed7f6e52d0e9ba2e35a0138345d696833f6f555d90a2a0b7925b5a8bae8b4a0703fe7b72a1ad7cc588ba1e28d660a8fb0a
350	1	175	\\xe06d64c81a34e1ec5edffa2b374a474bd726fb7cdf1fd5aa2c98b82b69be5cd864389729b267babffe97a710b60339b85ee88cd10dcc511809effb0226e93406
351	1	280	\\x3acbf11bc1efe90fc2bd6798532b0a8e6427e4fb86dcaca27f0f7d5191f2585d797f0bee49c770906f98d49840cc6952b4ea2bb2b062a763174d3151778a7002
352	1	51	\\x538cf5a48e8a878b6aa89851b1acbab0d5f16d9e02065f73aef5f27490a6834eaa6476c5718184c4620766df28b9a745fd933bab03034be2d32c427d917c120c
353	1	74	\\x24a09e6c453960350b5dd38c785f4fe4df425ae4844d95d4d2fe392e7fa0156116a7cdf521f1dc001e92bb02e56286ec4f2e83ebd07b50f283ab9375b46e8d09
354	1	218	\\x73ca7817814154d00e573828fcab4559434b7b620265f04f51a64682c5092361ff41182b5d9d2fee51a0750ac97fcf8209ff54e347863793830c9c83d2a70603
355	1	101	\\x6c1050e19d724e7172303e768a0bb3d7b0947f22af8ebcee75710a3ee272e6a7f38cffdcd79803657e2c387e2ba2221988f94163db6e80c4b490edb74dfaf402
356	1	206	\\xcd0bdb1790556910cdfd7e6abb7ba6f89cd5edcfe0f117e089b766db158a202a51b028b7b99cf86803adfdd59528a5de919f0ed850cd2e96499f0dc18d6bed00
357	1	382	\\xf2ce2ae284eccc2aaec9444993eba8d470630444ceb80148c19136feaf5b4f44eb05953c78227a0b79c4cde9dbb98b07e62c3b40bdad7d2ed7a3400eafd17901
358	1	424	\\x49a08e483dc5ec66f5a442fb808080ae825c3f237c77b341e1c531fcea724437f27a8cf151d1cc16047b2d32fd4ef4c7c58ee9bf635cebe873a64d407be49403
359	1	233	\\xcdc5ffef1d141b46432ca108a3d243fb29e5ee5abb1181b1ee38dd98a5af7441cfdcd8d2395db19d3274d27a5ffb3ac6b87286b1439f74b9baf47049e007b600
360	1	229	\\xb888ff179e61537ac7054bc8f16e2503e8b1852124130a49537ea00050a8d7d64629f18c9b062fd0ad3a768b02aa911b73dcd146309b2f73d0e5f57ff65f200f
361	1	13	\\xbaf63f10e4b2d912ab7a9f6d409b158c72fc490f4fb8783256d7dea3edf4368880d07700b0f0154c8c80ac28c247e4ac4d69f684cf8b51efcbf9337c3d0e4203
362	1	148	\\xc4947164a6011830e2bca33f675ae0f0753a82b7ec234972d30445a7189b414437e665d2b84ebe523d84759ed7dbd83cc50bb86f761a368319047d6d8425ab06
363	1	11	\\x817953adeaeedae9dee597a82e2418ef2b661af074b66650176199735a00a6db0cea5b2e417ada47ed90f753a694d45df4f0d9e3b294a620d00d0c4c5f627b01
364	1	181	\\x648a6aa95bb33945be1f5032188b2a17d88c07cd21e75f592d31b287907d67f185237d3b3c933bcbb51612ae9b093af71bc6168ca88dee57f08b93251164d805
365	1	296	\\x5e74d5b9ed5eacfef77b86fdaafa44cf2d52a62497c6bdb04fa38e13c4e1e49e2f25b7ec592cae800aa0f59ae6ad9dbd51be0d4da26c7be2e3b8eca17ddc240b
366	1	182	\\x3b7eaa9957d408bd8ef2a11b3456f5381bc999c07f2242ff865faf3883d7ecf5053fdaaa4e008e4bc3e7293dfca03d18ac0135b97b8d53516083a34b24f44e08
367	1	122	\\x744ba74c4c001141343a81a1acb200d14ad83355bc9234bef910264258e648ad515b99b22619a8018686397090bd59e40a3fb4970adf1acaa365baf1d2740e02
368	1	61	\\x7655d786ad1cb042005d989688abf71d71a4584b23e3ec96f173b1bd1834720aff09b84a42e21bfd714e23a8a43ae1b5ea28edc4647d22da27f35737d82fd303
369	1	379	\\xaf50216896ecc93459b639169dd7b574d594ac8776c20dcc7e342460c4012b9e9f8f2fe6faf6657f8ecd82310ebe11e29fe7da459dbc13c6146c81d4dbfd460e
370	1	189	\\x158c78421e9a896bccc29895f38865d34b2b7c6fcd2bc203907a8100c81307f16babfcee59602b4600f23e47189b13fde5cccb3a3c1cd4f6b1898a2163969d0e
371	1	197	\\xfbb62b7cd8b683948f5ade8a38657f5e172d1044a563e04f45aafd6d89bb662eaf038ac187594b7e4bdcdae33a3745a9ad59b41b977e89a0f2f30148bc851e09
372	1	219	\\x956e163306cf8bc836aa461e3601370421d52384d41bd7a89190e645f7992315cb1e158e31a3e94cb7b6511c0c91c32ec1a897d8a698ae2d99f3482b05008104
373	1	134	\\xf310647a93fe5643179b11d20f4ed8ff31785f9e2f7c1517807add939fe4569a2aef16c5b72798ad115b0a86a7345f5c263261772dc05dd42711b36ce9636805
374	1	171	\\x22e8c7d1cb9881f65442b2ffcea6c06822d3efe5af73afca10d020a4d92d35ebe14baff6b4ea9b2c22f27f97dc0a75661b7cec74e0b4d95d63ec80342d1f9204
375	1	410	\\x66ee6773b6e18d4fd8a6b5c6522e2a12a69b8b2806e67b903ba9423f8173017a5801980e80e010b0eb178fe590d49d9c80ea7ef7f1ec1e38baca3b3972e72609
376	1	342	\\xd2e916a5269e21fe0579db4aa1febbd1134f373860dab699bbd34ca74f5ef90be39cb26d0456402bdccb23210c76494d4f4bfb3149853eb5afe0fafb59f1a104
377	1	147	\\x7f2e026cdc9c723314a9de68aa95e85045fef6846cbdd7578a1815efa045a88d0c87477c35455dfd153b17bd1e464ac5e561b27c14b704e08ad533ec2b05d307
378	1	246	\\x177ef582bcf54365de908e18e234a74932986edb5c278b005c1b94934d88ffa18435f0d39ae3b274b194bbb352b11a65f4189b6c34a170a8b0eb05362206df0e
379	1	235	\\x0b182b9a3d7de3e4a1b56e39f75be7948b3ca43da7ad9cfcb6b796bbd999d83bd52beb835d4a849ed3d425e67eca5bc44551d52455f07e08041234524fbae00f
380	1	155	\\x5c0acf64765a1fc9733910d9b6db0474e976c380e10d9ab905f05dc85600fb18b09d83f4ee3ad201d60f086534a20f80c97b18a440e83085c2a0ed6f45da2000
381	1	9	\\x8fbc14808dd1485c052f2924b55733ee773766a4767994e5bfe63aa808e3217eb259dc3f47a24fb353b160541d6a8351548e7bcc3489aca2d023ad15a3bcb20c
382	1	268	\\x080723a7ff61f44fa10b5dc6f97f2e1b8c914e6ae4a2d1ecc9ca17eeae5a5131ab252b8ac000714c0fccff57b1163f6f2c6654d87bd2933b3108eb3add540202
383	1	129	\\xab019c4cd998177fb4935550324b22d281630fe58e37dec5c21a924e6b06a7662b9865ad0932584efc426a060e6460fa0e9527f5c5994abc5a55d2db69149f04
384	1	170	\\xdf1c8dc7205de0f1940a594bad1e0414af5b1910e2978ab20c14d4bb0570eda2055bc72a7000824def0362f435f88ce3b91e20e28c08a927ac19e46f9f674001
385	1	63	\\x76b7b6e76544bbc8e3a481941f4803085609e25f4767d354ade43d061d1b915d5e4f0f49b2207d4278b1808750ad6e8221f09f7271ed04defe602ee2e2db8500
386	1	384	\\xd1aa74109545402ee3af9ccc23cedbb597d839b3608d5f3c605de25d6d888484a4a8e66084cd522756b0601e54f7529496d3605d9308f495c2660a0c35f3b503
387	1	392	\\xd4fa5c2f7d0b8e93915e9dc8c223f76b7edc3f958a8f3d776392d7a03fd737567d403010f338eaf329c8444fe91be28ca713fe911593d6d4362ece89b0a25108
388	1	307	\\xc1220b8bc495bb8a47d710e8201fe994fde8d28402fd336934a269b6f9efd1637030f6b62adfdbf2fcd97e2718fe777c4cd7749028a9587b9b40a2649cc4f602
389	1	349	\\x8cb82b9b8c7684da0ba4edaa5eb5199fa0fb86cd08fb8da2a87b5c07986a0a43a7ed4dcd54fbabd42db9e7154b6ceb98df9db912c1d9e592349451fdc03cfc0c
390	1	127	\\xbf9bb4615d75c53c0607e72741e861538e27415a049fb9630da79a84516b438ece58d26c468b676172f5e41d423a343efc8dca88692e1b104177b05cfec57d0a
391	1	270	\\x531c157c54792a7811949e84ea5ef3b69249409137a6dd926b01eb20937c31d0f056bb7a42a24b1e45d71bcb91dd8ff1d16d80651a598bce9d354eb379bb4901
392	1	294	\\xc5c83b74e2799d2ba126edc629dbb006c54487b8c55af6352294d4b86266b3a23fc61d19d24ed7f7916974a05c61460d90fb2502a37b4d74d3535c6a5270a708
393	1	254	\\xf9d57457d817d1a74011d09c05a44e84aedfe459135682af6efb421168072ca92d3f299c2a0a9d17b91a9a9f421ced002dcfac5208c6820911fd6bb882d2260e
394	1	279	\\xfdbdc4567bfe21565119ba3a1f7d0005e5efa6392c3b7949cde2ac7e30b6ea30a0fa52144a4985b9eaa27d19007f8ef4052dca532b800a26c5d3bdf5ce2f3801
395	1	278	\\x9e7b03d45ec43597dbbad60ec23ca912248dcc6532ac3373fd1abac8eeb6bbd0625ec2088d35a97696956cd4d22e0fe2d90157e9abc4306fe844df2f75ac7509
396	1	8	\\x073a6a00770ce9c355e1193fda25ee2a7f27067df13ecea2ddd33495944821488bbc83a927180ba63cb7003bbb39fcdada64bb549d5f2f4dd21f851b56e51b04
397	1	152	\\x74ba718d9656a297e49263b113b3376d11189061133d0b9a73ba924747c0d6d0c2880540278d0713602bc61fc4e0b6ce7196528d8be7c2c38e41fd65cd2ce40f
398	1	358	\\x9dfe9610400617b1e8897f8a1f94ae64b1d93018ce8786f31caac40ca3a7cf82a0ba4895690cdfabbd58c3bff17171b1ac61da4667564c120e1c44daf039760f
399	1	169	\\x65f030c3638b667712a43a23d82993a5321ffb4d1614edfa8dc6124eb52a857c0a5cc9c823290f2a9f9273107d70d5d2a2b4f6dc4aa4938066c99394556d1c04
400	1	202	\\x0363a6d04d5949056493c5b92ef289cb8920ebef06de06f818f4606834894b0b919dd2f8d1df304a84e6768d9f4bffaa49225bcb36f148bfbdff97d1a424b202
401	1	287	\\x323662525dab2d44444f3f971e6f09b09865fb419dbda4b341c494c05a43b07ae7465bbd9fe729f2a7ebb934e4d37781884da0414ae327a58d7e0bafb9a3870b
402	1	157	\\xf76b66a2e7871c00fff4a03c59e0ed608ce4bffc23af13c5106612a0f11d6e1a98904389405b0739d7347a390056cb5995620fca7f22062ed2a92168b5fc3204
403	1	195	\\x7810b05f6b39443b561b22ae83ac87325f94b754b92b9a9257086d80c244272074637302a401b2409662a7fbddae1c25dd584e07a08a25501964a96b09d7020e
404	1	312	\\xc4934b6c1cd491ca8d3362dd7484c38719797b0f328fe761a15eceb04d1f90523b50a6c3fadfeeb8aafb35b188e53eecc4033e129f5847eafd0a02a86ac5c000
405	1	110	\\x414b624524ee05452470ece652c4b75f76a6adfe1180b74b2a92b23c816941dcb7ea66f58d8c660eb306e855fd150c2614dd95ccbbd66d1fb7557095a294700d
406	1	144	\\x2092079c70dc39ef4cef886562534241e99bcda6ae70926473899ef710ac22cd55f7fb19b77f9b5d8f688bac880d90a00790b83eaacbe9b8691d89aa3f3a830c
407	1	412	\\xd3ddc900f77824d1107831bebc7ad00947fcd58966cddfde3c02837f1a30a9dd58b3e00b47f1c827b42167c94f248c3e20365bbff36470e5699ade10f237d30f
408	1	132	\\xe94708cad1a45ca2773bd0ff236324ad6c46387704ac1a4deef29c5cde94812187f6c3cf21f853176858ad2ec3e10679879143be00a30a23adbe061ead6d640b
409	1	388	\\x6d0aeb6bf24ec6da4470e9ab24762ae95c2717cea407f26052e6743d159044b83748e2d5191eeca5dd030b95f6d68464b8e94c1b6a0f52ee596edf475a820806
410	1	128	\\xadbb2381714900ac7eb6a3e23c109dbc1f0cf0881a998af4fe6fd7b2bfb38d4aa17caa01d674884fe934fa732e81e24ff25461444fb7f973f67c38273fbdbd06
411	1	19	\\xdbdf3134fd9b5df3926e94e4f04678045323a34775277445cff7868e181e9d3bcc15d744ab1c55860679dc04d09ce3c51350897320eef74c2b26131324956606
412	1	130	\\x1a9e52f416d0986209806c48a6d018f166f2b77b0d5a7bc7af21b9a810cec047c6f528a23f47aa5a2221195bee300804204b24acd3ff9317ba4ec81888123600
413	1	397	\\xd594e1c47970a8422780d8b512938fd8483d5cd0f8841e55e2e01f8a1dae5a22fed75488fac0bded894116394f09ba8ea6421915aecd5780cd362a90854b1701
414	1	76	\\x2897b202fd88e59019391e0d6ab5cf4e32c9726d8739d3d6a0494307efdb53ec9fac2f3e90d7f8911a1ce8a3467b43d452a954365005b4f1e7eb029da7eb200b
415	1	334	\\x4d9909ff4f5fabc4a7942f1708bd63b31130e9ef5585da0fa99acb349e6a498c28d2a49c990825f9d11440b6b4d40e9edf169193580428feb1c532e5d8a87006
416	1	404	\\x41fccbc8e71986687c93b2dfbb44302f844457ac14f31647405d6037e25194f744b640e0d374924b47627a7af6cbebb8e0f73e8edc92c7b743605330053bc10c
417	1	357	\\xc3751cd6ec254468261a7a079397955c2907a8e152637a10a09ece070a2d2797d15620d689270038d9ed56c5f5ae46e941cbbc03f44fcb1d05f8929e85a4a00e
418	1	25	\\xe26f08be2345ca324a1181d2da17b98a3ec6c747601270d523f56f4694cbcbd272b64ad873ca504f2ea109d3e3dcd11a07a729a48644e7b95f8cd73c80f54f0c
419	1	191	\\x19151a64e85d2e1e7f7dabf4cb58dfa607860fe8ee3d1f68f2a73d26e20dcf4ab2f6856ef8e009b5d5ad9db142de10000a09d1776701b6ae02169804f1fd880b
420	1	232	\\xf720b9eb45c27397030b5bee4b4f8fbd94932cebc18b3220ab36f1609b660d6acb1f2b6e04843f3ab5c8d32b793fd2c572e9a8dcb0e3eb39f480d6e14965ce03
421	1	370	\\x7945e55aebc85ea7fb14e3e6342e174dc39f5957fcfab9f4181403b7c690ffaeee2284b873ca2aba67626c46500ec573ece95e1345e39d787e7dabc29d954e00
422	1	177	\\xe6c708f9bf35fc1cbe4edf14661ee1daa75eeaba083e66442dbe36e38095dea5b20791d662c0757811ba6c066c4ff79a09b22ef587a8a1067b344efbe2085501
423	1	179	\\x2ca140fecb973c6e1b1b309d4c17ef50b16b39e4719055ff1304d52fe9ea37d38ddd47e5018e9e48b6b4a90286e385f6ef9a08a4e2a16b5c4e2b1a154e192800
424	1	230	\\x878e68992793d7cf0503fa883ca74274032b1f6f7185aae78e11987e5f90b31d9c3aaa5facc1b66e0dd0fede1815a34566b690f33159ccf7accd38454e600001
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
\\x331e018582973b75a519ac558e66d2a7b08950465edbb021968987a15132eec6	1655124530000000	1662382130000000	1664801330000000	\\x09f2d99228e97dfd24242f178a7f59a31524b9a0713b04d84dfcd5dc43effa13	\\xedd931dd96aa1050cfe741348561eca1957792c560faa4adf72d0537d04a7a5b3057577c3fe3c6993b41465cd28cf736c8748f307d5b74be7c294018bec21208
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x331e018582973b75a519ac558e66d2a7b08950465edbb021968987a15132eec6	http://localhost:8081/
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
1	\\x4ed0633975ec7e6dadc1dd054a3248f1815b0da981ceb754e349143e74e5c0df	TESTKUDOS Auditor	http://localhost:8083/	t	1655124537000000
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
1	pbkdf2_sha256$260000$9pGaZ9PI1s0kzmHUEjVpyB$R9RAbqV1CQin4wxMS3Zro+aIy58RQu3+4bB95PYvP70=	\N	f	Bank				f	t	2022-06-13 14:48:51.655789+02
3	pbkdf2_sha256$260000$eZ1n5wLkj3hAQeSQazEXct$cmN4XSXjbHLkSD9atj8BmhmYDYWkArDyG3M/gX9YySc=	\N	f	blog				f	t	2022-06-13 14:48:51.844745+02
4	pbkdf2_sha256$260000$MQkQeQ4NJDHeIlqDcWIWde$r+owFQIMvyD44sf6zF/Wz+toiePKVmWyUJQ7xZ/P06A=	\N	f	Tor				f	t	2022-06-13 14:48:51.937451+02
5	pbkdf2_sha256$260000$F2qtsVHPyVnfNOsLhFhSQS$deiUffqrU6YSqQEZQr0nI8LXSFRiaMayiu04jkAfgmM=	\N	f	GNUnet				f	t	2022-06-13 14:48:52.032325+02
6	pbkdf2_sha256$260000$TZ27jjYurGmJMzf6Z0zc3F$5+e58Jg3dfEN+PMHcsu2UL2wMi2np0sdtWTH1C3sl9Q=	\N	f	Taler				f	t	2022-06-13 14:48:52.125481+02
7	pbkdf2_sha256$260000$l3pLLN9x13tyfIqQH7Qcpx$22mn0wTyrbk7ne5O1wzc2Nf3K+l5x4CPRRcx5GaxLEw=	\N	f	FSF				f	t	2022-06-13 14:48:52.219647+02
8	pbkdf2_sha256$260000$aunrgEAyn78hVHWiTaQsut$N8dJLVwx+FzEaED1XOm5+YWFTXI7+pj84vHPgcaLkZ4=	\N	f	Tutorial				f	t	2022-06-13 14:48:52.313724+02
9	pbkdf2_sha256$260000$ok1TiwrKdwDX3cO7jo2uBf$utxo00ldGMsKLPXGmZt0HULECnOxFBrlq3ieuG+6hRM=	\N	f	Survey				f	t	2022-06-13 14:48:52.409266+02
10	pbkdf2_sha256$260000$sz7hClXOlPHutG80f42UI1$xcXr4kTMLJo2d5q2OUTEGKgx8EhDHX2M2x8aL/iMVj0=	\N	f	42				f	t	2022-06-13 14:48:52.877993+02
11	pbkdf2_sha256$260000$j0cuAm7cUoq3j198KLzVde$+Jc08qgYjnlpOawP7gQ5/8VxvYfQGzV+gxh0PGMxjT8=	\N	f	43				f	t	2022-06-13 14:48:53.346588+02
2	pbkdf2_sha256$260000$EtLEexFiCyNJBxKYVB8cIn$/PgtnT1ST25+MB35vNRC87cwbiwanr3/cnsOTowCIoY=	\N	f	Exchange				f	t	2022-06-13 14:48:51.752219+02
12	pbkdf2_sha256$260000$GAn6AfCGbxrAhUZtH7y75x$w/ERz8DZMsOD46iVawy03UzGp72FPlipoa7Rd6rCPWo=	\N	f	testuser-as98unb1				f	t	2022-06-13 14:49:00.457776+02
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
1	191	\\xc98c640f0300b1961d15355d6ba84f83417e7a999e8e9b8eedb4524701427270ab100b350db7a5e2c66cca5cdcff391116c1bf854efa11e5d0cde29b3269ba00
2	388	\\x1c7a481de7605ccd45f255c61900343bd84a7526c75feb456c12ff027e631b2e1b0167d24be1946d0b52e4873f79f99ed7a10eaf51b8e86a4cd065aa56603e04
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denominations_serial, denom_pub_hash, denom_type, age_mask, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
1	\\x075c1a07227b07eeb147efeb17080bba8f81716e9b982257a90429e959db58a7f4ff18084b9532e424206eb1e00b3d36ce8fd8bfbb30882bbe1a62c7ea6a7d1e	1	0	\\x000000010000000000800003db951211b766cdb956186bbfb8638c23562f8352bde6fbb868ac746ee0a047fa6ce28f4922f8d3527eb9f30798863360d485b9b0ef6ed5949d767f342fd8afa871fe2f6ea68c31ac8d99f207cf6d21fd5a4277373d628120c4e51b332d19eb7d205b15bcfad54e838b6ebaf6cc4899e4afec930103bd06af234bc07cffc34ded010001	\\x489035af1401e2fd99b5dbddf4c70a7f39cb7c4358907161a379db2f55eab78fff35b39e7de2939eb5676700334a87f0f8d4de36cff8bfdc84c873024f2a0306	1679304530000000	1679909330000000	1742981330000000	1837589330000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
2	\\x070cbc760316d93112be80ffd07948f4a52a7d909286ece81dcb248372de2c9fe133243eaf269ca85d7e0ecbb542d9c5855c70ef2540e55d1774e87b7445f615	1	0	\\x000000010000000000800003b0570ef92866e0a8aefce80c4756bd6c3ad5d513e145b21eae5c60d56ef8216491eb32b3c1a811681e4ec178defdec1440877214457b387f5c6607b9d98b1cc1c32aded6b61241060f01bbed4c47d567e94918a4519ef9a6a44a3b26db445a41d6379df040f2ad120a9c35e0b0fbdf2bfe437ea732168c1b7a9bfca3abad1525010001	\\xafdeab6e1606a5cad615696d4b5406a6ecbb0172bd431a3d652364648fbee9d95c5c46b28a6d20687827272eaa5ba228368ff2965807dbe842e4e7d61c637b0b	1663587530000000	1664192330000000	1727264330000000	1821872330000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
3	\\x0be89a3ed9fb69be35d939a9eb8d00fcd0ec22af9bc55d2d15d58b7aea16cd38e7e7dcc46dde9fe20a2c9fd248d80673dde585065ee478bdcbc5ccbf09fa2679	1	0	\\x000000010000000000800003b35742cbea2f3e539e1e568682693ab0d06438ab9d525393fa728f3d3519aa27e691cb7af172b08d48984212964795ca06058846da7280be54b7aeecd5cb0fc0b2ba63a9deb14cfeffe34df6245fb1afc9bd45c4d9d9d97a2f784882282e6211fc3ca539e2b8fe0c06315322d76c57b2e7a2455af7dfcb20a8f65ecfdc9d7ee9010001	\\xb86e6e1b42c6a500276f5e02ca754cfb79e9b08985290244edff5c6506aac474a28d79231abd5cead2efde82f4cc85354c3185dde08806b952449116b4d15e04	1669028030000000	1669632830000000	1732704830000000	1827312830000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
4	\\x0b6c15144db4be55eda7d442e625e1aa62139244b81aeea4a44668152d183e0792005690f58e4542cc03498473a03cb6cf7c31bc064f14be35d7c8d7ce915ad1	1	0	\\x000000010000000000800003cd3f9cafa08f9211dabdf3195796ade404885a9a80d25c7a55d25b209b3a28aca0723fdd2537467d497efa82af435503d093d797176bf0debe9a2930984f04dedd06c58b13ac48412d6498d7976a67114c27f4d98feb5f2d91e9e5999fc1dedacf06e26c03519936f2dbb2772cad6871a7328e7071040a23e44aea2b9aaeae67010001	\\xd73f52007e5b70db16f553f3af456acced022618b6a1374643f5608ed7874518a4697fe6b351a1102aec986da5f01506fd8efabc8444ea92331dcdc70f55560b	1664796530000000	1665401330000000	1728473330000000	1823081330000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
5	\\x0c1400afe299d88700b86f67a5cbc4fd1d9fbddd4a94e96851890ed7054e631513218dac59501f967700dcd4d2c5fcd09dd4f9806525eb56d423ce01e5f7e0bf	1	0	\\x000000010000000000800003c1a125da0f48e6d6407eafde76419d38838140c603a7958b3666b14d7afaff9628c03a811663660e42a23a200d2985a3fbfed94a1ca6a87674b4169955dd93037d79fd1672db766dac5edeb7e8c84380d32f8ae92bbbd4b2d6c93fe615e39142a7b7d0004094396aec087d8f0fa029f9486b9ec7287e4e79d7ab93e833482a35010001	\\x33dca0e17a183ed980b83080d63ad62f86c915829c3e158bccdac7591b575a150f268d257827651413feea685fad74deeffb74a3479762dfee75ca6d51f13a06	1671446030000000	1672050830000000	1735122830000000	1829730830000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
6	\\x0c00de6ca2c23d6efb057bc034f4b7c0f737a89697daee59d03c4f70932b63ca082120d80bc8e33b9f4c491263f42b33c5b1fbdfeae6f933dd2b5e712a2d9c81	1	0	\\x000000010000000000800003af84e24b574d602540df51421092c949cd7288513d0c1d630b2ee76b03f18063a7b77867ac133e225424a50a7c9e9f19777a0364c38d11ebc67533a57364b07f1141d45833e2447326d11abd0fc16d70cc3a9926b0fadca1ef45dcd1144229a5287da20b77a8d55dc416e113df829678756be97ceb7f9b778d0ca649a23278ed010001	\\x208d3d1b1b4f4427fe0bfd680db70ec6f96f7be31a28101d2ee401dfa0ad0d1b9b68931bf04d76c9f7ba504cdd65df50a0e1f9bc3d2cf30a6cc4c64f4d549408	1675073030000000	1675677830000000	1738749830000000	1833357830000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
7	\\x0e60a9c9a129cf4d93023e13d960422a30d3b7b6d681c06761b1b41afd75c209d824806ff3e3839c0465115dc7f1b142150ee5dcf51c111c1b46d212888e80fd	1	0	\\x000000010000000000800003a36de046cf6c82566851e4726532aedd7876a3c7d080cf1cae68d5adf621e8dc891d5aafa8f66bbceb60cad634bd127374158ef8b09eadbad0fdc0bac66fa8acd9328c94e5d965b92b0ea83489133e3305c5c4477b586b09087b8005f673ee1c3cc9ca708ab4501b19111f499e797818d5d9c94690895dbf3fe364a44706ad43010001	\\x13d289a9f7325bce411c76528c34f80e94640c1f028b0756cd0f46caeb00e00f8be7c00229c0557ef43c499e29270c096d824ae878e40302f7f38ab806e4340f	1670237030000000	1670841830000000	1733913830000000	1828521830000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
8	\\x13dc9cc1d21a6d4d51e16c994058660d466b298c9c7e4f719b497b33cb57e5bb606227a931797fb8e4e46bc90a6b137675f9b84716e406e71824116915fd1594	1	0	\\x000000010000000000800003b91a785666ab0f8c365c137fab33350f5bfb9553b0fd7a98d1911f813b53658d6a8990ff373af8b7b5b6d8151f46aa5a5d273f5cd38b0a20a760dc92405b367133af0f345e1a5aed1d6045eb43eb17208bad95226666cb5124749f6c0fe48e113216bf5e50703f66d12a3d07f134fce0bd185a7ce6445c04827673cd7d059a6b010001	\\xc238e6b7baf06cde0c7c2e35d31efc3b1059dd405c59f6ae427972fbba66b9446079ca9a56de9c5005cfcb53d4d24e71a464aac2363b8612b23046b62dca2a00	1656938030000000	1657542830000000	1720614830000000	1815222830000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
9	\\x136cdb38992c7fb2ce33a032181639e70e106db7ca5cfc906f7fed126b01131c65872b20cb62727c4a5162dca6e90e1d687a15f9e5c17cab8f0f98b420b74e3f	1	0	\\x000000010000000000800003d43b7d752ffda51897a9eae360f4379e10fd1f990ec68a861e992c1c5e45848e0112db96f162f400a53c93e30fd6ab3b953b7eb61bd3912ddc5cc6388dd3a3123a2272a599e0a3e6f8adcbfc5093fcff1dab72c1c36a3104cbaa6c6361ec145e629c67b7ca2bf5ec21c221aa73f1d35f0edbbd153a0e3d6e1a0185ca470b4b61010001	\\x87a25747c8dd6079c2cc8b8e790e6c9add7d3225ebdf0e9140475e36a1dc1e3b68313ae1604edea458376c7e3979fdbe123f013e6a8b6600132ca0fc90027b0a	1658147030000000	1658751830000000	1721823830000000	1816431830000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
10	\\x1558fb2946c737a131adb4990327976528575aa6154ef0ab4f390f827b029a40bd099b4bfe20e3647634a796c6c9e92b54b96a4cbd2544fa3abfd009cb6de4b9	1	0	\\x000000010000000000800003d463ea85aac93c60c8f46f4b44388b414785bae1280e8742c25c6c06bc023fa0253ca07b5ecbd493c50006f728ad1bf696335abc7876eb2261eb431d80f41041e417bd5317d2bee1a02cb9d81e9e6c832b798920d4aced7e8d2372c09c94e2c2d50a3d02f66fbe0d926cda58ff8f3af3f102af9da128b486f3bdbc2d3f68ba79010001	\\x0730557f01b3a5b577ceb6691837f52e151590801df0f4a89c0af42dd68ec19121a60a128ae34ba4cb3dcceed13a60e87fba1b82a384e1db479cf64a858c7402	1662378530000000	1662983330000000	1726055330000000	1820663330000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
11	\\x1758128aebfd295f46a87839b360808ecca38d79510dfa28fc5debc7f61c2bf9a068e6d3d6f9383d0095e273d5a6ccd22f715edcb7985748a081f7c216f02517	1	0	\\x000000010000000000800003e24c6d1c5c5ccf98dd890cde79a5f2019983f4756567a434cb0e8f7de8c14f8f879ed57aad37ad26545e1fde52aedf2b4b3d760f1ce3ea31d9400f15aec6edfd92b76b2a0864f4570bb5cacef112a60b06ec9280d90ef6b1e471e689498e2a870ea490ddc960bdbe2960ea9af8f864cb7e6704cba1fc3d93b9bdf0c09f60170f010001	\\x55539a9ae83bd3616143dc8d05e27bb4c7d9e8ff93f3f68c1f47c0eec36d7c852e28775a5fa407e8a2b7fd2718da1c3f3801a011606b584a124acd8a4ae0890a	1659356030000000	1659960830000000	1723032830000000	1817640830000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
12	\\x1af48abf8c4b08205fe66eb8cc28aeed3625cd508c92b471c18699085335ddc694061e5efd9d92d4836445fd9cf500269fa49a869cb1409a5eec84213a3f2a1e	1	0	\\x000000010000000000800003dae2521e5294522966eae156611cc9d8d28197284528231713d68a5a770427040e3ef519bb7ce5d97c49bc93a13427d175619886735c2b82921ff5a6b07b1ea0612b6058fbd03ee8b48f581f4d2ff48b89ba80edb9aa6d3c6c0a6c681669305205f0b3e822a3dbe5ff95f9e5bf6a919fe07ae8d3e49d038d26250576173c8cf9010001	\\x7a3b6fff220a4a93badfa4c6dd286c4a4c8c8398492458198aa84468e2e8ef4d6b8e1d202c6df9f175bc66c4dc99b0a669275167034569b344e57fe2d1150c06	1672050530000000	1672655330000000	1735727330000000	1830335330000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
13	\\x1a7032a8c89fcd1168746a3723bb72b190d78b67f5ec783c33619f178ec33912533c67cf4c9a07585b962242d956e2d062334ce33b22e5f7500522ff3629ee76	1	0	\\x0000000100000000008000039e159de1f4546b3801df14fd58621ed649d28d22bcf5e27cd1a4aa116ff8def4668017b232e74a7feb87aca23fa716adfd2e248e840fe1d9d598b490fb11afe7d49484feba60b418086981b60820481c27cf9889d18ba7ecd40a5a0f662c17616e416ec9cdff08e227452b033cc56d26fc32bbb6a7a313ca569098fee2869493010001	\\xe4969f11e38a767f546f0e4f60f0215356b8e358d1e27c6bb37e01cc7ac6b29563cf5e162995f8a3121e9e9ddb20355be9d81670f254962adf7c3a407b865a0d	1659356030000000	1659960830000000	1723032830000000	1817640830000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
14	\\x1b981b5381a924b63925c3c43f5fec8dea0b572de17e7306cbd6d4af162c72c02b490564c797b29ff85482a75fa30396488019b6df9bbe255aa2e2c316da09f7	1	0	\\x000000010000000000800003cc4bead82972d27e321ff500f25d42a5ccb90a4e8d69363357a6257e9532c0da67c317997a8e7e59d43ce78617e2706f0f8409274fa3354b21c9aac694c8e1f3c11829c464686b7a1729a3cf4fc608407d0fc873c17ef9a106ea9d71584f0714c8ec5bc87f318fa515f2d3810cc4cb5a97bfcb3a8fa057f6db7d39ce11be9f97010001	\\x0bdd017a8d205bb396f0479e8e576eeb535a0f412dd48bb598ed03c2c3855f7b0f23fe2d75cbdd82bcee9de52977f1e62ec592f77fa35742ae9deba9d0e71d0c	1673864030000000	1674468830000000	1737540830000000	1832148830000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
15	\\x2308b7500df1c461a78b372a9c8b7de7c72c42975ecca792d5a444333a3826a0b11e9a972cf9a349aa8a6db9be76fa84aa55023d342b8ceb330e590a8c1fe41b	1	0	\\x000000010000000000800003a3c5009e7982147224c0ae0601a2fd77e475765b53292554b0b49dc3a8d9ff1152515c5c7d3dd286bea17d806742f7443869ce11b6ff57b06bc38978f99baee7a3226dfcd2aa1ca93f2f5fe0ba83b6bb64013dc58fa02eab8066041f769ab79886339a27fc8a4a67763a8fad0c973418c5e952991673ae87f269303721add117010001	\\x332f9ebe4909fa6bb69b75095ef02f294cc904c32d0009ba7a0b9a9f77cd64776cbd19e8dede0db762863c4308b3cdf1fce9e8ac0ce9edec7669dfcf0c577805	1676886530000000	1677491330000000	1740563330000000	1835171330000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
16	\\x24180c500b699a07478225219078ca7e0b1809e3a0c4482e7087172180f2f3278d003ee36aa5700a360459bb1f836fc520357ce376432d38443a84cc30008425	1	0	\\x000000010000000000800003c2670318659fa6d2a28a1ac86f7eb9f9665dba374b8833bd4208c29b49476a6dfbf97260e25dbcadd96edce1fd2bfdf6f84024a5fe2bc2438790ed815ccc8b8f727669d01821a87c5a3feefaadc184aa4482aa89dba58cb2440e92540066ab33cbd5e282ca4377a5e39ec0c091343c463491b4a2fe80bd270a04b2d35ede267b010001	\\x05b9a85727f6f37cf0e01bda2c70e58f23bc3172bf72c9c0982f5f7f13cfd9e64688aa6f70566027e65665a154d0b92a25ca653f5060e4eef4fe1f168a1a0103	1682931530000000	1683536330000000	1746608330000000	1841216330000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
17	\\x27e0d7174758343a1eb36307bc58229302b45d13966e4238ea7629e75a101befdd634ae46968ecb264eec958688cead2cd7bc398563e1f0ba8664108fa510a87	1	0	\\x000000010000000000800003bea1dbb5d4ab6f020db292dfc712746b3ae05e4c616678d094f2268e823b44e2ef292612d58192811bb1808c0744b6289b9a3643f0e75eb9cb6205a80c3e1cf1d084682ba2b3e4af814b0df9e341b9944d0d427f399c5a3a0980db6efa430d35515f6ea42cee86df2090d3626238d3251a4b66cc1c28b1792dfe89bdd33606a1010001	\\x8451b1f1b796c0e4afd416e2893f9b42d3bf60bfb40430a4fb7fbc23497024c38b8e760c8635d11f13103c140433e834401e33a8d107d7f281ff1fac6c495c07	1682931530000000	1683536330000000	1746608330000000	1841216330000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
18	\\x29843a8a70169c4bbda57a13b6f3d33498a41f27d3b5fe3cdbc02132c5bd65da01c481569b4deddfa8604c0cb6393ea8cd7cd5c62162487775173e13fd43930e	1	0	\\x000000010000000000800003b7d32ffe48f97990f8461a306b03bce863d5a9e35e2f41658561dab6f2c646745af98615464a1e159ac6a426750d74d0b1272471eeac2acec8f8addd2d87702fe4f42c7eeb8f72e65645f9ba595de2cb1f5e74cc05d22e8fdc44af845eb4006529eb05246f800173561768607f2ea3ef6c2e1e4d524d8443eeebceedcb384479010001	\\x1f39c0eb6c71968885f52747da2df10da651eadb651653f6d9375ebfdce697910d581013e81af127a9fa8ddc45852c81f6ad2c4648ca6d17a317f9f39f2f8e0e	1679304530000000	1679909330000000	1742981330000000	1837589330000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
19	\\x3138e3a4a83432c0789c84cafbaa951205896d93bb03c37fe2b79ac639e6fa529410d02b26181f7fda206f5a36c2366d0a8d03e4136f0ef8a96abb94886d6b34	1	0	\\x000000010000000000800003e2cdb7e373cb71a3a68e944a5ae9ada4aad2b1609095502c3c906d642e8b63dc3edc4b54885613cb5ee91b549cfcfe217034ccb11ad635c397d62251f494e07cc84cc5aeab1552b66abd3271c153475219a521f660f64d1ade4fdcc64f5c770ddaadb920502a470d577a2cbde5fee2f5d293de943d3e716712275800d9f9df17010001	\\x2aa173ab9e49c2aaaf9e5ba2fc0bfb9ede849960ebf7aab905a27d5dc7c9d17f5c14a8c7035fca831158183757397ed1120427adb36175cf39b52fe32d02820b	1655729030000000	1656333830000000	1719405830000000	1814013830000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
20	\\x33b4bb1e473411a51a01391147785d3e936c535d9cd9279ad6a6bbedad15a1e9d958e3b3f71c5bc36845267f6009b0e85d7153cda37bb828e829b2c9b4a2d01f	1	0	\\x000000010000000000800003affd23ce25343e26052f1672e7c036ae8d9d7113c4e15ee2e0e7a19b9cd08f299cb83e5c75523f1a9d35af00064a598a013eebe88034adb06c03d124106288ea2c91fa3b1f9330eef739f3edfec440e6bf26d09b40773eaba993ff0e73478b15b4de2590b9689bb8a328e159a7cb88fbb2e2d7985f6e062b1e1b20c1431a9835010001	\\xb6f0a1792e1212623d09c890c968257b7d0ffbaea9efa7a0b1847af37b843f465ea514e83d599e9f622b8f351f4e1c101ac1f7e1156993d93f1de5d013d88807	1676282030000000	1676886830000000	1739958830000000	1834566830000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
21	\\x37807d35eea58c5602a428625b1bd7ca69b968564891fd07648dbe8ac229c9f3a2541e265f520d7be778fae53780712f1c378bb360508d164a17ff050baa1b84	1	0	\\x000000010000000000800003b67726282368bd20c2d2c8d58f5f286b107e15005344c6542187bc88d2d6693f722434e2b68932e32b1fff327b9164f4afcebb24d0b0500f64403c145b66e7787f71132a8f470493d7df11391069fa4d5111e272f791f70d40d9a428f643586e7da21a43791f691f043ac8c3ac4f6edf12f1460624b3cbf55b409da5e0d26279010001	\\x47ac9d025f450ce270ed135707e488f6a69709cf2d992cd96b8fe2a567996ec00c3ba3d8c65296700a98320190f97308512b493ff11c1d94d89dc26409de7806	1675073030000000	1675677830000000	1738749830000000	1833357830000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
22	\\x38443944fd75b93535a7849a9bf1e0b1eb2ca5d2b7a28059805e170841863d87015b739e2e1b9f90f05691c89484777bce1809fca44a87116ab31080bc06b59a	1	0	\\x000000010000000000800003cb320848a836ed46a5b3ec864f04a32d8a5fa0dd4b6bd017dc7959708d885b3735fd9e4fb7d226342a903432a7553ccb589a686b7db84a09827bfdce5aeaf64753588c55218a16a98139f5a10c8e877c86cd779683441db490fd93a4a7128b2ab5d768cdd584b846c56cc651f6e2b584a1bb071d61ada5f19ce21fb8b214a7fd010001	\\x13c812c72b801e471f3c760fea32978a1d2003c69fcaf7487c9f3dff24467db63836ca46de44eea0fd566bdb26b46486eaebda0e295acc26a57af256cabce40a	1670237030000000	1670841830000000	1733913830000000	1828521830000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
23	\\x3ac81fe0dead2c077126f42216aed0c8a8d9c215c158719a1c15a5e9295a4c069c1253adbbfd888774a5dffd69559f7c885e99d84157e9f9de8f89f2df76f377	1	0	\\x000000010000000000800003c63db2c6e946007b1c269326a46b996a0952bb2807ec1047b6881e6c8438b831d793b6b1569521c912ad57548ff45e6752790a0ef49fad86ddb434ebb7a1c70c3182a417c07c7fce4518249bba71f8c553587e3a5993d10b7db910e50a7d98b6d2aa02c0ce3fbc217e1117b83926572ea9f362698b774892e8f87977a2af5ff3010001	\\xbe0f1ad0f01a8f541be7f66343e5cea4493714b2f630118dad5345c2dd3d1a4841673733d04443a8614fbc4f2229d4eae127c10f7b712858ca2c64d8e5e17b01	1685349530000000	1685954330000000	1749026330000000	1843634330000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
24	\\x3b488e34795247cadf3de63b8653ca1ac5874b2db92bbef1e280dea347fa06ee580266b755161476d503460859a377d6fd6dae7d4c3ec7b8309595e6721fc1b9	1	0	\\x00000001000000000080000398f36b6bd86c4e55f85a20c0fe63748b9156d2ee8d49e551c879ae2a59bfc4e41801ff7a36355a070c3295e5a40e6a6bd39559ee1701e2074189edd57b42c7683ec600c1ad159c3d2a0e2ff58ddb4f7897dbf2af0d58530d27fce3c155c9c08625b089da11b71d57936197d141f8aef0f766e414a6010f5507c0fd464b1684d1010001	\\x5cf8843922645d878003dc48c3cc757f856ac3f8746f56afd1492e3aba44dc8bb8bf7694678cb93ae9098022d0e3b2f8e87f9638377d45aed8fcbc663439c50d	1661169530000000	1661774330000000	1724846330000000	1819454330000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
25	\\x3e3054a1a5741ab661dc406ff97446b3288e7cab7b10767f86ea80b0fe29134ce89bca9437729b3354bee601cf3d28c7eb3621cffb0cea5b219b84e78bcb8c69	1	0	\\x000000010000000000800003d1313717509b1c96e4e07e3cbfa56afbee7e663442518ee8bc76d68f2d3c8bcf4c376c98879fb202f6696beda3aed993740311524686751e67c9ba089f221781832d62b0d904d87374a3003f4cbed37edad4b4630515a87d412f5e94f3028d4af0dcdd2348ec6d52424ee9cca92753663b79572fdf5fe59788bfd470a52b48c7010001	\\x4b9b1bab94e832551d289310a31011bcd83c0689206471988ee586c4c4d3a9f0a5133f7bf2aef33bfc9a51700a235ac178963a8e1c3bff6281a75d0b02564c06	1655124530000000	1655729330000000	1718801330000000	1813409330000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
26	\\x3e8c6f60f8b43c5a1e50fd3e3c0ac632a422fab825206aa566f96802cf612a43deae8da270f43018030053a3ba062c259f10514bafa8d3b2a386cc8cd7efe116	1	0	\\x000000010000000000800003cb9ed127c246f54079403e4f98d301457693ce1e0cd26c9e8a6517271baba348cb1c28a0b381ab4a01b31a4ca94ab62481b00817c102fff0331814e0a629dece95ba1007214f93694b74e6f3240141b40607ff36bc9a14f188b55794bbe467344121787c3f147e4fd5c236e5ff68a68acc2315ef1af98564bca5c556bd778447010001	\\x6f9732610a6c87962a5f35d6dec93e63cfcaebfbc7f029dda8b566dfdebba7d9f7c9482aacc4779370f756701efc4ed009effe995a205af9f94858f91b3a4301	1676886530000000	1677491330000000	1740563330000000	1835171330000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
27	\\x3f68c1564a44acb5825445ef1d062308be4201d3d5950de1fe81c21708b5e40f4bc565c70b3a9469c6cc334aa1311f1daa84a496f463a1134e0d526b94fc2c73	1	0	\\x000000010000000000800003b591aa0fd9cd4be592414d8769b45d3019a501e9ef917c023654b14a87bbb0f92313c2c090a3a6fcdbd6f0c1373253bb56aa8e0f3d8d13b69e1b1e4a5d48128176b89423bc49e0658edd3a4e3f1b547f5dd2be2957667c5e370e3698c4e9dd26b51bae7d08192b92e8a7199adebb989f9af9f4eb3c65a5ce956152b77526b11f010001	\\xa8373950ebe734d829e702db7dd19a595b29b5bf10d068807f2b61ff8669ff14fcd9d693b2dc5ee26d5c69532a4541612ad07ca5d00a1bc1c64b4e0fa9167b06	1676886530000000	1677491330000000	1740563330000000	1835171330000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
28	\\x3ff00e4c6f64a63c2a0760fe3638e976e61229f9c20574161f83462d0b2e97093c58fa8edb638ea7a2fd990f264729fe58a0c47a1135106911332c0f9d8c4958	1	0	\\x000000010000000000800003bb9238f61fd92d2ddd3cbbd0fcea7789998449d1e79f0b0ffcf376f22a9a88bf35dc580261c018cc13539f8d35e56c9f39485fce6eb04af1d028a91febe78402f64e7e8b4f81c01fbf61ab9d5088148e1a785c6820344fbbe5e10741cd20e56fb398763520bb1535332036648470fdfbb758e7deda27d25607b4fedbbd3af07b010001	\\xca007f244048a39e4a84f251803aead0bd618248c26bcf4683152ace58432d890df5ac139c3fa1f55836698d0a06d429bf4df6931243c13d77cbc65605fe8006	1672655030000000	1673259830000000	1736331830000000	1830939830000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
29	\\x435ceb6889d5ef033f4d15212dc8bbfe90bc187ee74db7d95d640895c4e7a152c7e53e205e34490ae287596c9b41e8b8f9dd691cf07e155c047252ef07d6b00d	1	0	\\x000000010000000000800003c65edb892258f9152092e848f5ab5a7c9f10280db8a58f5bfd0a2c29594c41983663b04eeccb4ab5f60385d63c83590030a6b5e371a51f67b67f2b2d95ad7522cd3157ca778a9dedda825047bdd3cbe423bcd5c2839489f455673e9e1ce784ed48b1fd9d3a791e8e3a7aee75aeecb769ee54f6eb73dfd0724019fbb7f2a78871010001	\\x60279391a56cdb2918795618d9ebb02d85bec8d9891adc0aaaaa529a740763f4c54b03e6effd034bde3e87b3edb96b2d8d91c776c6ae1ec43d12e02451535a04	1661774030000000	1662378830000000	1725450830000000	1820058830000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
30	\\x4744e5e6cd3fa9d66c912ac0483f710270e1c0e8442f07b19db46b08ca253b355c3509ef7331d339512a2e9f63934c735043eba748f5ce652bdede5c2817ae87	1	0	\\x000000010000000000800003a38074c43854e3af7bb2a629c4be1ec5d477bcb98d06820e75158bbc5f75edcc481eaef599f59e8c06e3d31ce39656584d9727cc1f42759af37fcff7374d5dcd299c687c0c3786dc65cef5c004e56b6d5f6e99eb4e4b05e77da1a70a0b21686ebaf0345676cda4ebd51751a8ef1ae8c70d7284c45157fa171e44199cfb829d1d010001	\\x206433e4f1c62a21a9049e0a112bbac1ad5c296633fa58fc5ad8501f96676ba61c37f6f3b26e228b507c31d4db664f523695af339c6bc397930295ca2076b10f	1670237030000000	1670841830000000	1733913830000000	1828521830000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
31	\\x481802c5b6ebbd5cf2f05f8c18378f1c281deacbd579b1775cbf1664ed21caaf62b23494b7d2ef23024cd1540fda545ee6c1b15b7fffd196990379d771ea71ac	1	0	\\x000000010000000000800003ae9680d5d444f2787c6ab01b15d76c40937deb668e26c3f2f58380088f0167d37087a071a8f916fd2628674a088e1d14a35f89667c1fe08819034986eabeebb15dabc6bc35790fe0f09736975193241e6f212ae430e6829478a099b5de7a1fcb8a80bbceb016febfc826ecd482dff327bacb75ef6aa38c3fc64262ac01e0ea6f010001	\\xfef353d6f2a739d81f77dc050e16c29932d1640cd92d8ac0e606ac5c6f032139df1554ffa49102eb03f0a342eaa68425f49e720978105fe93f161828a6231100	1681118030000000	1681722830000000	1744794830000000	1839402830000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
32	\\x49bcb8e608748b298708f18cbf21b21feaefab86243812ce74f2e7c1204e5309faf5020f3b4d49346f8759702e158aa30fde47b6d35d3afabc951a9623632e94	1	0	\\x000000010000000000800003a6d69f2cd06025b29029ccc136b544b909346ddffa814777e8c4a406eea4eb67f4158a91a591b68238df596ac8e63d3ec3d0e3045ef5858bbd2107f5f386e40148be13c112a4e6de216591708829e7f86f92feb8bf1529f6ca75ae2f30c70dc04939674193d78e811edbcffe9c1444ea918a3fe37c230166a204b713fe84acd3010001	\\x9c7bd9e684ada2df7281d660949d9e191fd20da00ef465ffc47737fba778367d3fe31d3d3c71cf02da36804ad6f6019f57c5cac3775c68aee49067c3d506960e	1683536030000000	1684140830000000	1747212830000000	1841820830000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
33	\\x49f01719b553e172a8c24c142f2de1c951212234c5ee29be3f0acf2e8eb17a4c3aac4ee205471bb4be44c8ae57efc2f0a2140fe5b012f0891e3507504605c695	1	0	\\x0000000100000000008000039940b39a9fd2b206b6d1d79579b8096696e2891d8edb01990a5a4985fe7aa488f385989d43d4a49ff0f95bd257c963c5d308911f88384925a6851222c935639690c9e30fc1bf75ed8ca1c1fe9e5a2bc18d89af3fd66534f41de2dbde396176180b7603b779d6d87d069e010f75231ec91b2b1d90e8b63235a0f048a4c98af9b9010001	\\xb5557e22aa30743e55fe59dbf527db36a6d63771df0da586ed27133f7be11bb5d89812c4be3c85c506c050ea9962568c85f6f2475fdb33ced753b6f03730c105	1670237030000000	1670841830000000	1733913830000000	1828521830000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
34	\\x4b905b65967af45bd5671e7b42229d0f8f488fe911fc4975dc2681b3de24f264c0635ea8a87adac53e3afc5056aeec73dc4f14654b17f9b9bfe839f445bb9fc1	1	0	\\x000000010000000000800003d9dff72842783bf6e713dcff5d0464e9bd287c5dc1eb97583c72cc40627fb6cfff0f19a73e0c2610c336d38dc28d408022c430a786c6a29c1699bc2dfc0da7ba10277f83a6455aea64e7f6cb36bc5a06091f6eaee4894a0e96531e135c6bab294ec2cab24e8f3920a4852fe879bef77b19aff242c104b30bc3871966a7947a8b010001	\\x34925d94854cec95b4f4a8fdf41579e09db9acad5790fe3867a2f38f35b9d8f55bc673e298cf75f5045a57e4c7db194b88e4423aa1c64216b3cc3a5a92711801	1661169530000000	1661774330000000	1724846330000000	1819454330000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
35	\\x4c34782bf0e98f0c6995bc3e28d88589318c39b1c32e21dff28e45b175530fcbda223cd70a55427d859dbec807d7a65bfd74c025d3e095cf6c41c217a2b27598	1	0	\\x000000010000000000800003cde860616d35f79cd105a1bebd23b0c5660946befe1308b643b7345cf5960d18f26f795e7714ca7de172f2dcc62043f69ddffd32b5740ab9e3423b1284f77b3005cb368f219abba63eed57a28773e5a719159d279e8390d98d6cb718f3fab59614fdc3a2ab78b7a6470324d52b1755830d2470047ea2966d3c8b18a37f327eb3010001	\\x65608bcc8febefc14ac52389f7d6459435086d810ee99fa10cd8e38b57fdd87dc7830dd0248e733e12e41a8975cc5185768f38b87a0b1776768a2cb161a1da0d	1660565030000000	1661169830000000	1724241830000000	1818849830000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
36	\\x4f14f480e580ffd2abeea6853fb3b7f1c7b4fd83641976b3957cd35c3aa6f217b3a1d3b15e1d39cadc9e2a235a52c1ded6a3972ffba4d298c4eb39f038eb8e62	1	0	\\x000000010000000000800003b8e6b50e1bcea3996bfa1143a9ec310a23c40a84c1537bc598969d4aa130904fe7810f849a540423ec56cc73d4bdff09bafdc26ca6a081789c422a723c6c5f370f10067e1d5e84ad47e78b44e76ecc136788832b3b75458766e0480afc52b568e39bcaba8e1983ad9a31eb745f8e9e2a939c9accfa14544c8f9e31f881c1e323010001	\\x85854b81bd60d59f48dcbdeae838abf11bef996692a6bf9d23f82e8de4d349da1584be6fa4c277fe6d8106806647202de6697788f5bbd8c158a85c55f35e9106	1668423530000000	1669028330000000	1732100330000000	1826708330000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
37	\\x508804c3ffd6887b8ea454e185a477205aa7a5e36be56b29ccddd83534fdd09eba066241c16cbafdd69d8a5e8d2e34e4fddede4a2c5a7e19a6c7b63c7ef7e106	1	0	\\x000000010000000000800003b2ed8a8af79b91dea3b7cd9c05299936663f681bf25097f606acca3f37322c13f66403f676ede0997ffc76f96dc16bf744c53ce673ec50b29c91059689aacf95d3aeeef8f3aa9c24b3b1a7fe1eb6ff40a0bc481f292f211d1d5a92180ea897d33d8566246a251c060900dc76d9e62dba5ffdee234038fc7699113e10695ebdaf010001	\\x793e15114d2481f6c5600184ae1687774bdb33a41101f3d53b3104b8ccf4384c6c5e93b8bffb9665dc443c1b6346e11edfb148de3517dd68c93883965f61990a	1673864030000000	1674468830000000	1737540830000000	1832148830000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
38	\\x5210705c98be6fc65cf6ea772022ae606acb0017aa14a9f793fa443d8ac8f32e2a27912358a11e920302da3ebc53e4b74c406053c0493fac2ada1009bc0193d5	1	0	\\x000000010000000000800003d361db20924444b523776c03c789815913badcecc8997fe121256c275acb16e448493a3e7edd2a6c861ff616d27e411b1bc5a7837a82e85199b94a28ace8b149a41b5b14c4c4d3eefb95816fb89715a85e33ae31096f0a9b823a2842a377d7e0e33f6a779e9dc1e46d9e13a2113e32449bee0c43e2a47daed5eaa70645463961010001	\\x7b4cbfe081adb76675c1b5f4b0d0dfc443cc0e4d8cf7540d3a206015fa00f1768608d9476bbe392e01610caf95c76d9f8ca2a45583fc798f05ca0490c222fc0e	1679909030000000	1680513830000000	1743585830000000	1838193830000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
39	\\x58dc41feef409f2b9b068cae55bab0782d1362b6c48d949f76d177bc9fab44d15de6be27e0c7327352a36b1fed062f58c7a3ea244f1b2e52ae1532943d81bac3	1	0	\\x000000010000000000800003ab62dee0e2eb39b827bf1d5b1f1f4e91659afeac8430034c71bd325415617bb76dc213a10db8cb2d9a54682af0265ee128c9b177f8c69de9216150387fd179bc413e117710ed9b9db1ccc410a8101a896194ab7f90765a4d0f8b9d96cdf0c5bb743ce77a57a5bb9a54345ef87c133c616fad2bce7192c2c5815175008436183f010001	\\x641dc0b65ba9ee59dae6f17ede2758d7cac00563d7b5e43caa766887bba65054544da600e009974725220eb3268abeb3ff3d7386e31650794e9036e057655107	1681118030000000	1681722830000000	1744794830000000	1839402830000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
40	\\x5a64598f6bb9b923f7df72271821d80a98185730760bb7686c39fe761a2b32f388c9d4fedc1efb6d31864c94a5ccfacb3db0340ee19c782236df735fc6adf240	1	0	\\x000000010000000000800003d03ee712b1aa3941f2b5700b9b2eb0fa09352788546fa95c0a18212d96e15dcef67e36d57994217b8f6431cfb577eac2dfb2fcfee25d7d2d3eb1f1129c87242a54cb6ecc40000d5bcb8a93a368de9e3550dac01dcdc9bd87079f68d352d0863e7f4a3c7fc1ddea976b8c534d97de670170592e86fd4d0eab23db9d6774d367c1010001	\\x0092976884584227a6abbc724760d62b62f0b4a4b56b138f5c735122c48db82b7c3d22462787d5ee7740828dcb2838a073bf02e1ebffdbd7c8fcd7a0662fd100	1677491030000000	1678095830000000	1741167830000000	1835775830000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
41	\\x5bc0cf4507dbeed0ce3cddab7568ee23e2184a2c118e5200a0cb2977a2ec95cef62e1a72f8215719f6145c9cfc4ad70a7a21d49cd5ec36188b808c08154a636c	1	0	\\x000000010000000000800003ab7a3f47e7c4fad9c681eba88fca6ccd370a30a5fa505e359cd9b3f6a89bc0d486cbfafde0f2e1cb21f5c5b8b64616509639cbf5a754b114a369a2f516a2da322205c6eaa0536921cd8f825cf778f8c13c00304cfe6e69394f5678eea18d2e1cd4cccbc37b9dca16bfd0f4dfbc6a4132105464b2eac1e09ed62e4dc0ef2be3dd010001	\\x02e8784305a0b60b50abfa27a8439cf991edd88b648e2da56f2a93ed43968ccc2ee695dc1e9733df444433d3658bc0e516cc5a724d8295581b9d05a36a19de04	1664796530000000	1665401330000000	1728473330000000	1823081330000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
42	\\x5b70004ba9330b2721646cb5c8c69aff1df650150ec682424eddbdb3c80c92c9603f3d892d18f1f990402c88f0412685374f52ff0d882cc72a391e44e446512a	1	0	\\x000000010000000000800003be9d8ba92e9098b7967917d4d69aa7784fb97384be82ef03ba9257195bad6bb0709c1db97fdc2c363e6fb60e1abbcdc6aa4f2b67dc01b59a1405e958de2117bbb81855939c798118017107a6492cdcf92a7ce503f61e7626775b8e1819a9dc23951867e2b7fe456b4a2c2643a3129a3877265fc1c115c6e62d009fd822ef1581010001	\\xcd9344220777fe54aa2d5f3de69109fc4e2e1db6f2e6ffe214b1a17cc379a6c4a3de03a0ebb4a08b0dc18ea1b7e1379c54b995eeb5994147a3a536fa4212bf05	1682931530000000	1683536330000000	1746608330000000	1841216330000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
43	\\x5ec80527a51fabd97553dd71c9c7c9f1ab6a9e0dd56e6b638662bc5c6e63d82c8740e816f01f5ace904533aac16ba8c3abc14db319d014ffe2bd5d4ed3b8b79c	1	0	\\x000000010000000000800003c5994d4b82c338be1eef5f73d171d8d56dc9fd6da07864fc657ad959471dd61f9f941278d366440b34e768ba5b7fb22377bc8037fb831f567a0eaa796ca46458a0d38317370e97abbe78b427fa30f67aa7dbfc88b94e89ff2e5c46db8cbe34d4091ea453d6b40203a7d87bc2bc843cac254c8853939c16e982744d048c28f35d010001	\\xdc7ef72cb6d47d65481c6055e221a4468d63d978936babd01507647b28dc77b706b659c32757b5355a907f5eb1b1ddceeb4c2bacdffb04eb89d551d3cc2cde06	1661774030000000	1662378830000000	1725450830000000	1820058830000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
44	\\x63a41ee39a65df16253ce96cdf46afff7bc4d11fe64a7fd860a6edcb7ce42a0c8daae71d0a6c53c61d48c020292314f871642cc5d80ffa15c587e027739f4103	1	0	\\x000000010000000000800003c32dee2549625e12a8ebd245836abf45f7f3a749162d8841a709c61786c06bdb2f05fa588997148d3a9391b9fcbac76ab875dd4dfd2771f368266ae26f2393f9caead7eaa2c1cf8f61cc510c7775da8d21e6a678314b587c040dae86e0a5b4496e1b0fb85acdc2714439aa3ac2d4d17c729055143c6fe96ba8204e767d0e9825010001	\\xe314982cb5a9faa0c374b1994a8bb6465120afc13003f69c2b4d056e467cf1b630f035bdaf67a89971ee8b2385851e47807ffa9c8f9899cf6335f98cd7b46508	1679304530000000	1679909330000000	1742981330000000	1837589330000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
45	\\x6a34c6ebf9d8cc790d494c8c88b37fd086b75cbc68555decc048ec29d99bdab5f2637176a7c248c4bcb44dc0b0b391170a417812e7773b0b48afa00bdad6560a	1	0	\\x000000010000000000800003d92531c5d2a0808fddf3e4284b907b2f75f868fa834bac9598b282f8a08b3dcc39d0aeb0a2555d2f21a403aad8bd3c75760856c9cf1db5f12d7a0363330e8d8fcf8584fcc5610b0c5ec821f25505940bdf2e27cf7c9df090ba16953d1f8eb418528cf9d18234def00e0bc54491840cefb998f6e78ced448d75d1b7ef1aac3d7f010001	\\xe14de0c06a56428bddd1231036b6d0f2276d7d369aa7c69d3594de39ac1f557bc989e3a6b420ca6f59c8643a075799c5ce33b0755e687f1b23e2ea0285178307	1670841530000000	1671446330000000	1734518330000000	1829126330000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
46	\\x6b00c0c77dda3829a30d9e36ed17a1d8be32414f8dea3ddbe8e244707a27188f7c7aa464c29a7318d83916124fd52a0ecd4f7805e5ef140037de77e5f2f5b92b	1	0	\\x000000010000000000800003c46c2f76ef4c92162ba4b6c9fe4993122cb51b25313e979f0c14972e0de2c11be7bd2b23a641081aaa76df5ea2aa51bf2d75dc1027a988f4e1195330f7ac774a4b3a8d4a3a0ca5863ffe0528f811a1dd46e8289992de81302ab9cc06cdeff8380f530b5e11ca52c52dea024c54b630e2cffeae86dcb35ccc6782a642f3f9a919010001	\\x8af0f317454defedf3677e51338ebcc1f23f270f21ed9e4fb447117ad2756fdb7845c2e09ec54ec692e33cb6e4e2d9c4c2615a93ac63541f9418b3d6e32cba05	1681722530000000	1682327330000000	1745399330000000	1840007330000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
47	\\x76148b070d8dc26337a6190321ebff857aa90c42df48e3e73f5fc2f07261ff223578fe214492e7d49c67e9193b291d62034da1bb419004ddb2436c45735c21a9	1	0	\\x000000010000000000800003e8bce3f75400c57e16a6d75ee10eddbec2039276ae364a5ab254434ba8bac582b77075e4cf1105120ac539de5a71c8fa801a89f1357fc5f3ec073da2ee479848e649f43a55c7a07ca60db5ca505979b7a035352b45d4f86bbf616d78984e99b6d921c406a27b723cb07d230b3e1f8348395111e6e5c8cf91008eeebce1a40c5f010001	\\x6d76c6ee65a87dbba62ed5aed775182467d154c92a2aeb339e984d4fca8350137f4b624f86a403225b546e6423b9e90454acaebc7f9501025c61498995aeac06	1675073030000000	1675677830000000	1738749830000000	1833357830000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
48	\\x77a0b14dd5db1e10d01d414810a225bd11086966ad13cdb1571b7939fac5054c4786af8f530b458ae4e069cab9473ededf306abafed72a5792f3baeffebbf1ee	1	0	\\x0000000100000000008000039ada3472a7362058240e3cac3f1c4733796fedbf68fa97f222d18cd8c2f28fdf121daf252f96a24a85493e9fd6e2bdf10ec8f528e9d3516995f8ef80a3d1bac3ea0efc535d6c14b61d56d21aad3f60f90f4748a8792d72db84e3a1ad82bfed1dd2f0091f90a2badf99d3050b185b2599a4174653b38d6b59dc1c7ab787ef4281010001	\\x613940bb9be9dc7aa7c3c05b6910e3716a650a04dfc877097021976385bc6e14cffdcdb9f3a16dd9f25da13f4c2f32979ee61cbdcd1d8edf6ac18c57561c4903	1678700030000000	1679304830000000	1742376830000000	1836984830000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
49	\\x78248639397c7b532b81f29c42d5b2653bc32c75d483cedec241eaa51a942e1d92a1e1be2abc2d335a1bd1d65e892b34472c562019d9235798b96d0252494eda	1	0	\\x000000010000000000800003a0e94342685ca010772aaec7b3d442cba83b19258b7e1fe55dd7d40fa9510c39eaeaaa2645582cddb1dfe80663b4f88d70b6f5dcbf0bf6bc7d38b3c37de4453647cf354c82dc6205fd8d406f812a4b713c934227cc4e8794004a356566a264ee91755bfac2ffbe9dab6f23899679d11116a42007dc80e3a8185f9d494e266b59010001	\\x6984b740fd23826cd4d3ea1f00b0ebdc4ba110c93c3538467e019bcb7f92881a2b88676b843deb834e304a71833c39a8967f0947ff39f4025cdf1a4889939804	1662378530000000	1662983330000000	1726055330000000	1820663330000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
50	\\x7a442fa5e246e975a8c9830a792c0c8cc499a1944ad6656cd9707d2167318a2358b8faa7e2abf2db5a0b2916ce425ac6f5b5d9c3714df15305001cf8678a6e82	1	0	\\x000000010000000000800003bf19c665d2a4ec3b571bf113588ce8a12bbfaa0da1e089a221b76bec44454970b87b5f5499ab26beaffdca4b4d30d0f642cd68c3a8e58ff80f68f4cd2b7ed0c9d53675906383700cfb09c422d73fafab3dd3eb9240ab4c8884bbd6b6a919bd72be6896b28f6fc09e44e4be89c4d82c8b724ed88d575bd990fca57040c994957d010001	\\x1bf0754e07746fafb3876c0e40e4515f00266f54734b743bc762cd251bd402ab73de55cffd4ba595ba64bcd62d7f323c1e60fa7c291c5120cbd400d8424a2409	1669632530000000	1670237330000000	1733309330000000	1827917330000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
51	\\x7fc00b82b799cae125491de4c142fa769438319632ba6c5fb4c4f065f79a0160cd5b0c7215f01dd32051d84293a09f78fdb61439425510cb35fa0964dafd7e84	1	0	\\x000000010000000000800003cb3914bdd7211741c5764036c7c8b5922a6b49cea756297fac5652e3e9d7c597b72ea12c2c52ac55e1f8e18fad3b12ceb45786e91ff236590d9ebac75a4bb17e06b765d2007c2ea9b162ae4f42f99e7f0d6cd7fb1b1baaf390bf5784897040db7ad6f7d0b66914c6560d0f20c9537100786d6a5192feba853acc213a095ba82b010001	\\xb988ce4a9aae6eb473de0769b2b30eda2683806d6b0e5cd39a4c9d47edfb22c00e04e1fcfd204618566cfe8c9f46a24be43f50188dd500afb07705d9e4ae7908	1660565030000000	1661169830000000	1724241830000000	1818849830000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
52	\\x80b0430c8a9b7ddf4097e6b27c487f2396144af4dbc4d426f1fb9e7b9cb0ed544e39d392a08ff1027f9f60e05e5664fbe28bd5d7acbc16e5fc378f00c9a0f517	1	0	\\x000000010000000000800003eb324900db601dfb80e97e55c9488d37bfaf6aea55dd44fef670fc122a5fea06a5f93a92f1ba3f7cbfb438522b46a5ae5497976826d078a818e9fd0a2d174741c4f3d2f83bd6cadfda4a324e7425afc45b511d910ce727bf5c4c8b264895643f6e1ab1ba0a9fa2c0b4cab81f51d87bc7b9cb2535df6e4b182c92f9c286c840b5010001	\\xd6cc3f973c7f7676b150eb6551629d6c8c688f42bf4df88bc587e27c7e4098c3de7c07ddcf36352b898ae271bb59b6458f003954489e80ba8594ff2bc53fe20d	1662378530000000	1662983330000000	1726055330000000	1820663330000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
53	\\x80b857a5a125c523a3ec8983f7f22e08933f51100bec99a643c0ea8dd55974313eeb1bb30ccce10d292ec0f6fd55fc876c61fc850819ce4ed7d9436316755aba	1	0	\\x000000010000000000800003def65538ad445d77ee166bedf6b777d850fe39c942590e5a4fa24f7ad81544549e9087f1c91d0224a5724c3b3fef09c259293fc226447a62cbd5548969611f2e7bce68267733735fd8ea12ecf6eb3223b250b425371eaaf95932fa191beef9ee59a54a4d851904a52e4bf7bccb970b4f3fe1a2fe3e663dd768de29772bd80d5f010001	\\x7b606a0ea86229ada6193c5961fbafa59a55f4fd35b2e7739a5aebc25fd25a0d9778099cdbda10b51c8f75714e1bf0ee0e4194b58ed062e6f40ef4a522336a08	1675677530000000	1676282330000000	1739354330000000	1833962330000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
54	\\x80f8802d600d272d35ea3d55c3a0f920e307c226f7731cf29a9719a1e5ce10e18412587284c45055055b92697c59d29b5d3e1c4c87bdafced4ed0442ee3ec5cd	1	0	\\x000000010000000000800003cc6e779586b4157fca5dbebf364dd0078f49daebc9a3999956f6e175e9cff3cf6a42eac226160022ac496eec4aff52df9f16c1faa7fb19ca51898d4c0c8bd19ffba3fbe1e3e28cedc4713d4185cfc0507c647a6bbe8ca25c94ea8aac2cc15bf2cab8810068987dab2ac567c2bf89d64c9d8dbd58220fa7deefcfeb1a25613097010001	\\x5afdab5bac55dde6a0ffb1b2afb333134a7612682d689edbe5bc4058c826b697b60182165700a6f7444ebdb64719aba34099f2ca210b2dc4da4d78cf00457205	1676282030000000	1676886830000000	1739958830000000	1834566830000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
55	\\x8194dae31b25588055d7c553aad7374e777fde9302c544812c89946c874deff63ea30b093c20768ec936cd22e374aa23f7e42100db522d1301bc221290326c94	1	0	\\x000000010000000000800003dd6a96175b6e8333ab240d5ca528ef76e1089aa1edb475e3ba34746463da065fc6c1e88e7e87c9b8700a8e78b7f3e6514d356d2c4e91d4937c52039549c6aea7a97b28ad8c824d25ddb4e61c6a1a023fd919bba6cd6532f4a9ac157b1b96b513ed40cb11265671de99edafd5faa90287a3de8e9bccd306c49abb382f409e10a9010001	\\xd083b8082ce94228d32fa2f190427fcdb961de457d649b750756ca08fd0fe37e9ef329d0f4f9c4d734f562e0e233b16149711b0f7a5b73a73fc38eb2c6b69402	1685349530000000	1685954330000000	1749026330000000	1843634330000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
56	\\x87dcf2318b0c93fa70f9d82cfb97a4490766afb58f50704489814aecc0b6d81a9274aeeb385c0b77bcb23f6236d72284b617e1935c6c952477d0540ee4173d15	1	0	\\x000000010000000000800003b83b85366277993aa5e3ce67377fe6c2fda03543746a3265fe83d484cf91715524a4ead45dddef21566ee2d379b0dbb42074ece26effa1ebe68fb731c9a557ba5dde1c6b54a3729e571b55d9726c5a6dcc6de946b8cf5e53cd018897faddb639476231e6aaa4a1ded12f696a0741e03f7c39ea40244112e74b7d2048a484ff91010001	\\x2ab653fd28c9e7e9e0defc35f3d834be0d748005be473ed674902886a518a69460fe0303c13fa72f6d5b34f8872de0cb7712f8b3e4539c46a99c085077af8b0f	1666610030000000	1667214830000000	1730286830000000	1824894830000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
57	\\x8cbc442a013790f2e10ad52084ae79ca842e4b58495488b17f6ee5600a37a78fecf6b5042ff9cf4a243a6db5aa64ad385070763f11c241677ea32c6377700415	1	0	\\x000000010000000000800003a6e0a6ef61f583e9047efdc6addfe1499306f1105f17995cbf2b9e60a3efde7601cb667d14c11ffb27cd21f70e60df98a3a2a9084558440ced9a159e26fe6de4c14a0a74237c428930808466dffa9bb6d6f41d6c6f5e14b0c004e79f029ea4ba0c1fd8a605996eec072fef4518267d678170af7ed650f6b8fe5328bd6a177443010001	\\x6b1cc0fbdcbeadf603f097858285142d8fad46161e171c930b1575b2e83869096add6d3704c3c991df98bba3f83323836861831c313e3a7c1effc5e3c47ae40a	1668423530000000	1669028330000000	1732100330000000	1826708330000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
58	\\x8ddc43b42a70ed49fc8d65d14ac383fd19e79ce4d7ac6f92aa3bc980537accf9de34afe16dc7b6ccdd32b9ad86e7c8c440a3dd18baa92f74a2d34c9dd7594e6a	1	0	\\x000000010000000000800003e5f6184a01efa7ebbd810b8ec75d2327eea35946d55b9912a226435e7aa2109ff758bb3da49bc40bd1ef74a6b3048eaac10da13a60a5be0c86e4cf38b6c7d82274d46bb0d5bf96835f9a65b2f9b433c78771363df6ce186868dd9c821bb7e069b2a5ad9556faee73d8138db288739866b74a1bb197899d284200f1a38f6f33c1010001	\\x124e132a6a2e4024b9b4988b0f2fb2f3f851739c83402ae8c250561d240866b61483c52d6b434d11a49bff7347b302afc369d7f6dd5c9b9d926b4d7476025803	1680513530000000	1681118330000000	1744190330000000	1838798330000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
59	\\x8d3890bf3f4698dde85b5ce2ba462f8936e901d5ffda34088a4dd183c0df713aa8b289cf361b8229632bdb008a364512e73466c3321ca9a116f587fd1f108063	1	0	\\x000000010000000000800003b7339a5e71deb9f035dada2088f52cb7eee5a84c8c05250e0870e2a9e59967781a7d014e041fc0dcbc564a442f88ffb62d482fc3c59146a0404adbdab7cc4f4c3d53524b7c4b501bdd76909469b4a01fa0b6db7c579ea065f07f4d78c470dddc5d7be9b52b6bfc70493c2665611426d9551201adca9b134a1ea35eb68832f5b5010001	\\x2aaeefc9c8fc1b6c3a25fc8d9f24d3ce9278fdf41860dd7969c0fe2c98a541f1bbdd89f89b758eddf456fb0bd4d25e7cf48beefd68ea1e4f7b2f1b2e85bac20e	1686558530000000	1687163330000000	1750235330000000	1844843330000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
60	\\x92609d8c7aea516649fda565f55fc270714501358c54f3e76509b1d64b934d7929308ce272677338addbb7868d657d4cb691c742f3d313d69d0387893581ec27	1	0	\\x000000010000000000800003c5d694e972739df5030b3ddc6341db35a5999ef7e28d61e212c8e10b35acf53e3650138c485c9a021521ee400be1941ca086709af20e59c5019fc5b8d27b96d12299b6428717d6975e1ac956a7b84f27be60bb0af87844f05af2a7fa6ad32a0856480fea3eaf23b2de6ca34ca8149ed113698c20f2eec989396b139113421d89010001	\\x2e001ea0f99b170630dfd8834d9894839c2f2e1f723fb4b14120525f57179a274ae02a9e76cb9ea188db0d59ec8238c166da4ddbce03582808f9ba3437ca8f04	1670841530000000	1671446330000000	1734518330000000	1829126330000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
61	\\x9524fc78940542aade0771201ab09a874d8a541bb39d14f2557fd94e4e88920f0c41945353438efaa0a960a475929f7a1072dd2289cb093e782bc9a1e05b28c7	1	0	\\x000000010000000000800003d639e0f2a709d8eea313a10d895af272903e543cc7a735c1c5ab81eb87ab2c20799199798891c46a31a6d7ef657540283cfc8cd60d1523d058d857d3a2e3f0b273df6b07776fd62853ddee844b239bdde452e8c7d1de867c15f25f183bcdd0f9e5aceb387ebafba7de5361c2a76b82ba261dabd854fa3c0a3d3e7f4fb213bf09010001	\\xef395fdad9b3a0585d5c8e32648ff9c98838708fe69422390d2c1727c3bacd8798ff262f15bcdab09a22ae4d94bbd8dcd9c062b5026416ca8b3c03495cd2db05	1659356030000000	1659960830000000	1723032830000000	1817640830000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
62	\\x9864ae2d19c6d38766bd7607640f95a4c3d11dfc8ebd708d503f0c6267d4e1040d4af2a841921ef6a543547ef1ee1d035186e31300d90f56c30fe89c4718ee2d	1	0	\\x000000010000000000800003ce1d96c99db85b25f737df4128b85e4f666a066d1a474e18cfbb94c12aec3697ca722dd73ad82474bcdf6906c371d585b43a168ea95743febd58e800c288269d3a2c65245513d8dc628b953e448626d7f4b2f13eb434d3f54781f84012e565463b8ef4150e76325cc8902f1cf7d823b492f3c9a5e3167b3a8f66552dc5b10441010001	\\xc11330c5783631b6568ac84724067b94401f47f528edacbf6e1ff2ec3629009f5ca6172d6c67e01acdcfdaec38f1286dc4e374823c3f7ee334c1d25849ed940e	1666610030000000	1667214830000000	1730286830000000	1824894830000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
63	\\x9ae821727f48a28f8742113691b912d15fc0fdeac6501a9ea7921f589f8b8ccc39e2a01476b0f4b42e54af40846902f86eaa1b9e46b70235e04d3eb2dd6250aa	1	0	\\x000000010000000000800003cf81be5ed6848311cd5fbd0531b09867ad4b92e1a7dbc245958a2f86885499ae60728c4e77e7f45885343160ab71e2654bf03acb3c7f82aa737d38fe9f856d4eb46a1256c85f53684ef7daf83992ed846eca567f1f7a5c6c56f44407f8f2ca277ff6220bb931c9a6cc9e9ddcbb5b8aa25b1a8a74cc29645b09159add4f325d53010001	\\xeec3de51c43262579fee84949cb88e5bd7a2896e417d7aa30067b27b35de1b004b68e02c10e3de9bdb0ebf859a22463cd9da4240b9ebd612164139e537148908	1657542530000000	1658147330000000	1721219330000000	1815827330000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
64	\\x9f5478a9d6015fca7f7638797ef024c05271e387e2d25b8585085759b7a0868dfa78647528fd37513a36c067e3c5addb2039e66ea156e5febe1711a60115816d	1	0	\\x000000010000000000800003cda6c863ce1f3a325fb274fa9d620160c1645bce4135ab00bd75a8219a0d40af4662a6f4eaf8d449eaae84fc839cab7d50b1af99f28f66202d8d2b07c8f9b158f4aab20cf8427d75128c9ed4fd88aa2fef8a8f39a99d7fb04bbf8a032dc7de1970903f0467fe2251e788d9d725a61de3e1a4493cb4c5814e69a477f913a75d89010001	\\x39812174c16342ff61a150dd17d341353cef60bff15cd3a8a09bc9a17ad16d78fe78c5e195a851615af4a5926693ae00e9d20e7fea685e5df18dcedbe8850909	1667819030000000	1668423830000000	1731495830000000	1826103830000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
65	\\x9f9894339a0171c43cf5b12b1937e047a56fb033cc7ea67a797f496ecb583748be68a316df94443280571140d4cb5f7ce8b8c2078383225efad4e04543994efd	1	0	\\x000000010000000000800003e0d86dbd95e24780f04030b05e6b1912f075d3d72d7bec8c2feefb149f9e0ff38f26bcb1fc48013a432bcbd0ce21a1f6405dd1ae8b8f9ce2f5111dec9f6839ea4ff3be2698dc721cfc230e01f65f41bba50b7bb9be913f44b676840ee387203bfeeec912b43e7f2d38bc886991fe922e3dab4b80cdd8ca28f7fe14f682e30715010001	\\xab1eef689ad706a6e70e5afdcef039160d5a3d5915149735d6d3f06f3b7817876b00fa652ff6ad07bf6b34d28687648af266520b2a2ed33e08956e14c2836f07	1670841530000000	1671446330000000	1734518330000000	1829126330000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
66	\\xa4e8e14f7d2a4359de2af35e788ef44163084605f432e5252bf2d8a5eff260850e94dba4768a04bc2fa42eb2a72fd50b52e4b9d964741ec956291077c1f8cab4	1	0	\\x000000010000000000800003c30abd1ee162a6a540c5538b948642ab2d243bd29f6509b8409574b1890ea8e40c878df345d8dd9acd7b7ffa30fc23c42af8033a7bc4007b67f5cc03114d91790882a0ea89e267a3ea6c231bf342fa41d4f0cdc423cc14eb7d885dc6323ae8c6659cda46662f8d4990a6b88bfb68fdf4569919423a8011dfa0057db5cfa3605d010001	\\x4aa462511fcda047d50dc1878bc24ce9d1da941f78b203d547b294c5f91ba30ff26ae62efd31c625509f841749156b404803b76d053a4a71a16df5f94e25b301	1663587530000000	1664192330000000	1727264330000000	1821872330000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
67	\\xa9a4bafd5596c7b1c40d22e4004e9d6ca670134b4d9d592c111b1772a60a51b5a990aa93faf202e916d382aa12ae1f96204d7c5f623374eaeba8868002ed15a8	1	0	\\x000000010000000000800003b40f84f9ed22b9c0cc2da5232d04c294ea49e17e31503be94f8b92a829f6b70fbf544e9066928f1653ad1fedd35bbc777cc592d61e50260f74c93519372db086fd13a4c61151fb44b5ffe4605d2313fb38ff5f8df91afdbdb3501048e31a218c9db6e4fd0b226f2c2fa81b1bf24b0fd3d7428a0a65d2e894babef8ea7017f873010001	\\x3e1b2a7ca43c4c25c6bb9b37ffab3b30069ca19ef4fd243f566a15eb4b76e5619f11522c3a724739c4019095ac1318ed2c538d91ff041ef93785fe086aa66f06	1680513530000000	1681118330000000	1744190330000000	1838798330000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
68	\\xaa80e2d071e5b92b6d31ab633e444919190fd9ffe9706099883cce54a0994a7ad933e05be86ea1883dc109bf9c041556db0ddf22846ffdb07f020f333a84dc08	1	0	\\x000000010000000000800003c1a9e0ee6dc35331743f836bc9526bc17e90588ad994546d8c088b487298cbc644cb500f6f0caafaa8cf1cff6e30506dd9263432bfdadeb8b0148ee6b4a3d4446aa61c34704f87f0970383745240eed8bab9585c5d47cb85813eb6271285a61029e442658944ae96f09b3b8c39bf68a8b76367cefbfe18bcc800e7a23735fb49010001	\\xc5efc63bc9966f6bfaec2ffe52815f05d01ff3343ffa7520d8f7b928a8975c00640234b47acbb57d4f013bff9450c7e42c54ab0313b1ef1f9f934174f2a0dc07	1685954030000000	1686558830000000	1749630830000000	1844238830000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
69	\\xaaf8de432f1027e86e9ce1444491a30842941d35c6a30a1ef19e881bcf77d11d12347bb84e2263c098aa543b6b03edc4a52abbfe192f06697f8625ea09ba7127	1	0	\\x000000010000000000800003c6d96ab6662f3704aece9cf9dd7111883cf5dc54c584f195e559f2fcbd3423a7b303f9586b4a483c31ed5e2750c8c48a22855cb9b1a9a161625a62fd57e782d878a509cc05f59d9e3bae7126b871bf7c94a06c47d5857c806cd2f0a7750be9fba4edde676a4fda2348b301818a008b9607676221f7f6780cd5fb9f0dde74f977010001	\\x76d1d58c4e37de02e071915ee701dd6422808da061d3027239315092d73f783e21b425073342af540356b9a408e29faa6edcdfcd8f6907f3ab98236b97518201	1679304530000000	1679909330000000	1742981330000000	1837589330000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
70	\\xac4c7dded880d6c4e3918aa1c7cf0e0b647ee2213b452ea6ad66a278b2a561b6c948ac8cac8e74c1b027156eb82b4b4ae2368f766c4dcfccaa5e0ff5d6fce02e	1	0	\\x000000010000000000800003a981a7a32dd11de09d566b8f483b55183ce07819c4d4c920f15f46c18db991aebc82d194ca6561a5f3d80f5987382cf46f3a6e50834a2c61e7d2f403200c06eb5be93971359dbd35bf5cd1f5869c13d417d7c315b7e2ab3cb921dd81383cb8438a1c402ecba5530ddac84387aa637f42f24e4ccd502d2d0e1243c82a6b98588d010001	\\x95b349b563e2ca88ffd045d08ac2dc4127964298aec9ac1d91a8cfdd173cc601508530653fca0c8f86f2d22a2dd2e0130a8b79e397e8c2e9342bdfc0d39d3e02	1682327030000000	1682931830000000	1746003830000000	1840611830000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
71	\\xaef872974fcca32b5551560debb311a739d05c3fcbaff1ba1331cc77211df35c18d34186917c5daef7e59a19df13656d8b2ff5bcb9d6a6313020d47a1045924a	1	0	\\x000000010000000000800003ba0365592acb97b203b5daf5297821a4773e7a5c6b93db430673b46a09e3544d967c0ff6c0f61b87da868d3bd60d71140532c59f4415bc52a7da1fb231b1dbffd873cf05775007107e83fa5438850e8c12f0c8db2c441433569848f9d1f4d99b9fae2ce8a6fb6ad64d35819a6ad2f9d35a53b05d8caec047df1fb2fad87db7f3010001	\\xff5619cfb34f082fd799fc808a8937c82cadf8442415f39b4713b1a5bc218a9dd96014799c72fe4be3234ee518f15a484fd7429f94829de59d2fed15fe30ae00	1684745030000000	1685349830000000	1748421830000000	1843029830000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
72	\\xb158a74cb9ba9ae032589e5240e1a23a8b22644d854fd069702b575c68bc35174e4bba3414da2bc613e202512464e40c61af728f007392c4ac180563d0e270bb	1	0	\\x000000010000000000800003efc32e643bccf74628cf3192e15e5c031da7db34dfd8e92edc3505856a63e7214bbc94a227ec3e5b7dd2d773fa21a8a0ae3f1e10a96cf5ad568339e696c0c90d27bb99c7ca6329c6323ba2262731c8cdda6140f3ad8cd7155d9227fa5c508e711a0afec408f4e4cf012efb33818a2c0860dc4314c500cc734e7620ea71f1ae07010001	\\x9c6ee9f835ef8504a2b5afaaabc5434c22fda265d0a1af04d8147b23cdf98e69570890b51be0093a8f4fd5734fe9a743b8fe23be3b9478430f16e4e0594c660b	1667214530000000	1667819330000000	1730891330000000	1825499330000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
73	\\xb2c00322f83dfa4474de25145613c4ffd1be60c8a23a98ba1bb2af9ef659bbdf965e1d33ced2ab71e581bace614ef4cb1c7a57a8391e5b090a30cad797e29706	1	0	\\x000000010000000000800003aaf126f1721088612eedeecb8fb7594f145d4fd54c6e3fd5fdd66f2d540ca64a7a8cf0e0f12c68aaf178dbf90461f3020e1c27c40f69f55bb3ae2322871ce5ee31b957bc8ca4c1a3b37532df8a22951eaa8b9086bee9b061f3df46a13b4e8e84a3d284534212c64bc3c008c936acfeec26c16f3b3199526edf1771ca06dbd1c1010001	\\x9096fb68a3abf4f913ba0faf265ef8277695e594cc08daa1eade5bd66a3b83992f1e5c1d72eb62dc5d4abe22913f1d3d3b042206b810c49fe4cadee9b25d6708	1661774030000000	1662378830000000	1725450830000000	1820058830000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
74	\\xb5789a27821ba0a207b3a8d2b7c20c532dff70b9b42226b8566b292f547b763ddfbaba3f636ef780b7f874820e949f4fa4e34813f0442e0d4910a9173d3ffe5a	1	0	\\x000000010000000000800003ca729cc592720474196af1052bdbd53f8e63733fc51eb08967e7c2aa3cce59e4c8159c8138dfb7c6d96d5846a0d5b3f26cf54f1dcad24d8fd5276598b86768ba5f8f423d3bb8fac385c46d3c1212e4041af9434cf83d0a17e1cb30197057b5253e9e57e13d3fe29d429ef47717e4e42a9145c6f4352d6570169876423617b1f5010001	\\x7740025814f6196d34ede013c75dbbb4b9678e7b7697b3b5f868721d26bf108a2615b98d5cd1df3404f257231c3d76e11b1aedcba6f544ec4554e593b7757d06	1659960530000000	1660565330000000	1723637330000000	1818245330000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
75	\\xb6e4ffa88f7570b39d11fcbc14157cbd46fe34573f6cc0857dec1688af802e954222f9b552646ef3cef933c37b3766b97110439c939958b899ad6dc27526d82f	1	0	\\x000000010000000000800003c39b07bc9b78612e64ef459ebe2affeeb28f08808cc5273904df3f1c32dc97eca95c635bf30e49f944a2486b1823f3bb2099a57aa5efbef80c39d4f31e1a50f0df18dd01f933481c21ba2b29581829daa872d0e33d71a858623721098795515484270581f5b50ce2357353f5c3e21ee2c439bd71d0b48d43b61a8ae9ca5fe9ab010001	\\xc56c085f6f692979c9fadb876d93e2b194ae40e195ee73dd2921541d8b23bb2d88013caa65e4a947cd339f0afcc600533377c0fc4df274c5ab5e75692dc54d09	1662983030000000	1663587830000000	1726659830000000	1821267830000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
76	\\xb624660d351fb8718060463f6ac303ec5f6c15c0546a0bf0c69cbe66b47983dc1ab682820c81844819664f768978a77a75f39b47b5871c066c4bc5ec4027cf21	1	0	\\x000000010000000000800003ac2fa52125e10dc45cf4b83abcbcc70a7e1e8692983a093170db844ac708c5418685722287bf137d04e7956f8f29b257ab3c95a305065834da95a2730f9cf3f6cf4af53522da909a49d5fa966e1197d7cb4927ce8050f7a80ad0b8d2fbfa8eb7dba960a7f2d699f5add7c988f419a9f326aec0313dc247049bc7e7fc2fd9bb2f010001	\\xc442b5fcf4c40f3dc7d91603f01573605c603ceee6fde49c499d08e77e0ebfa5afd7e1fe2b6107250ce58ee04554c626d52a81f438cc20a63da27008bdfdee0b	1655729030000000	1656333830000000	1719405830000000	1814013830000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
77	\\xb62cc009276c88219a9e19c3bd5bfff7844be97cef9d6874afa70c04f1d1b1e6af2ec837186264a10a7affef4b4aa2d6cd4281934268337683a23d9d2844a73c	1	0	\\x0000000100000000008000039c1da7fadfb206acd90c637a044d995b8addcdc88c712bf5071cb268c8d146395f74817e4f0101df210b376c7fb4c61b088084fd6f0e67baa936a787229625ed69aaa9e4527471d58a0c579edb18dff953c6642ef2f4cc43231ca22df0e259c224e628d68106508bc267d6e9cc8ae379357e9a1ef0df2a445ac44147e561f735010001	\\x095bceaf3b7fa7397c60cb489a60acc159757e805fae4a458356fe66048d96feff4d7e8db7c9fd1c620fbe746c35f257799efd45e1264c2193bb9b3730e20802	1681722530000000	1682327330000000	1745399330000000	1840007330000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
78	\\xb668cf4b55afe4f920ae356a1cd353a97f9c2e4c43c1c2d6385a19e6c552c203b08ff971fd9814a9a085f838357f9844e15916667dc546ecfb83361fa5ebae73	1	0	\\x000000010000000000800003bcd78804380d37ddd31053647aa853bed1aa58b4d7a63b838cb24b8a299fc3c386a5ede18be967f7b4c48b010a7e6b26bdcba037fd720755a26dcd70f046a482c9d82ce4be127349498ef74ae6004225b6996763f9106ccec264e1e5222b9eb377034435e087e85164e36191ec83275e2ee7dafc0d37449091720682b155cae7010001	\\x089fa9b5802350018e24b0892f210ad67636ff72cfa50903d0cf833d2f1cee5c4b6c1d2d17bbf204bad95a176c32c5a8ce91627ba0aeb912df5c5fa82c75210a	1664796530000000	1665401330000000	1728473330000000	1823081330000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
79	\\xc018e2202fe9307fe45d8f94ba848e32270ee98c6d59fdbd03c915e0f7c1a3a55e03ee6bffcd46f18d92d4b9ad07bb13304f08d5636cd6694a3123ce3b8a758a	1	0	\\x000000010000000000800003ba854c778d9beccea760dc18f497f84b2e15cde299531f8757ea8f96927589a5f5e5ace0f2fec8248dc52ea774ffa8f02e0624cc9b100ef2ae464e79b60a0ff39c5c2bea3a7d5cd7bc6994bcec026603fbb80dfa6ce286f213c99c84b4589812166a246267ef62b89a122113efee8d19d7d18e7f3bff819bb025a671377632b1010001	\\x2bfdd987069e284e55dfe391cf6d0f6ee2c5e659518c717bb2e70076f7dd89cca068f7d53626a24018b2fb1b7bf91b05d6b6803648ccf8a691c854525af49c01	1669632530000000	1670237330000000	1733309330000000	1827917330000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
80	\\xc0bcc8133bc09e3da58995e10c2156f72a8fed622f7030e94e52a7f409fbaf43871ad67b4d68676bb39b5b30c854cf324ebadd3ca2db963152681d7764da707d	1	0	\\x000000010000000000800003b895eaca28f3efc2cc81fa94daeb276460a33c44221e0465888a07ddfe5d555457668bfb9e5a562f66de46694232be8ceef689084974fc1332fb296513bc953ba98829de9b7a100f187e9b8057d300d932b01fd92bcbd03e3ee5a29a2f6a49db6a07905459a3330ec90b4f562c8a6677291a7781f292eabd06c8ca3bbaa4a94d010001	\\xfce41d6bd93a8a08f03e70893f50ee97aef670e82209160952a8df32325986ade6ba1c94c12cc786ce28c62aaf04a8fd914fb83a61e1a97e31bbaff3bac44309	1667819030000000	1668423830000000	1731495830000000	1826103830000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
81	\\xc2d4b0bdc38eaaaca37b8379ee898f153e16d30d3b44905e489f184fb77fc7a09903089d82e0f5642ce15e10fc9d26ce76af18f56c170be3381bd6b67317a236	1	0	\\x000000010000000000800003b670300bfa1d342a44155e35261c09ea8c90854ebfe0f0e7a43f8bd6bec0a096697525cf1aa0b55d266cf3d2e343a69a08bd56b5ec7d7c29079803436a931ab7226122eccab3890b203b0f516aa523d8efb34e3dd5370005d2b9dd8fe17f078d46387c7691f7a19a2b014fde00150a5f711f4c2d65d023836b519b83f8810de5010001	\\xfd2180b0ec3ec85f98140e6cf91914529bc62e4ad901c1a613b92bc331554201dd83a1b75070e927d780f53ceef963b23cca2a2ab75649c2bef4e62b2498bd0a	1667214530000000	1667819330000000	1730891330000000	1825499330000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
82	\\xc75036edb65a80fdac17a4249f400f337dc0d14ab0936c2e4c515a23c64ec1f46ae1b9f853533029100a3d196d1138c6ac6916a5ff507eace0d09cdb8403f344	1	0	\\x000000010000000000800003a5f2075dcb2466836a8a77052cf99ea27a7c1d2cd266dfb7d684951aaea889ac464dcdfde6a7401a50292942669686efa11f2fcf61d6a25cfb0bc802fce6b9e9b019a1c11b1f7de9ed779e356072455ab78beca7eaa61a93e3152a1cdff0e3b6efec4eda8707dba5e5c2cd27649396d906949ce3369c3eadeed9478738c70369010001	\\x6623cce815e569e5ed0359a86c081e7b8ed274fc3c02d0420b3236f5def871a1da76ea08ec31b0b53d2fd281d103ce1689dfb3537de9d82efdd65e334132540c	1678095530000000	1678700330000000	1741772330000000	1836380330000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
83	\\xcdf843569ed07bf912bf659c3f7910c3cd520ab1491d15bc330d14904fa0bfacb9a15c1ac58b79c31622154205414a3e9feeacedffb659f770f97007febf48b0	1	0	\\x000000010000000000800003c1f7aa439e875806784c02cfe68a4278e9599a9e2a05346ae28bf23d113e6adcfb3d88ba3a13feec07ec9669020719da604852ddfec8e785c1acc085e0f6bd677a8af2dc525610954b9488ed5a6b40409f72d3be0906f6ca82155c0cd346a1bf7543b0ad6ff2c1ff5cba2674ee18165cea15e245cfec3dfa6688ef76dbccb5b3010001	\\xe1f20c873476a0b12fa4ff126ca4a0e3ffe4ffec765035a22c527f7ed16ae72489f236db7e69963d0e51b78d5ef9640c5d6749b304b77b572bf1efb376218101	1679304530000000	1679909330000000	1742981330000000	1837589330000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
84	\\xcde84a6955baa6033dbe25c4325b918caef77b14a6c84a9ce796ac88335d906a8041db515a47103a95a547250d42c745875f8fc7ce8bca5f1ec195b427aac34f	1	0	\\x000000010000000000800003b912472fe957f8a79b65eee3464d1ff77e841b5d4ec82db957c833d4ecf69989b7fdae9572ba7ac09cb80b46805f57ab467d8fb6ba02c778865b40a75f5c14fbb9ab4072f27c1c54097015f39964a3fce5b75c22001acbd0f49532f190c9569ef70da08e9edc53807817121a43cf97ab8252c5e9e555c5c65df6698405aac415010001	\\x43f0aa640fe5a783640f3177691d7d54b10eef0ec441a75b764e88b9dabb92a187a0c32a47c9c77ef9e5ffb1e1330a96b56975876bab42b45319d1f84168b801	1662378530000000	1662983330000000	1726055330000000	1820663330000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
85	\\xcda4a4f07802fae9bedfd6ab974c094124b87ef49d5d5469d743e92ed135354150455a5b2680e80cc550c1284543e0ce11f42ef54bcdef7b4e49841fc073b81d	1	0	\\x000000010000000000800003e28738eb896d5a3b9da48a9c6086e7602545b03edbe77ca60d0e74acafb47e48586d2aecadfa450e80e9151eadbc4fd67c44bf023f24e7628d8988a05b26fc0f3dc15b76151df9faef98976ed5ffee9bdd968b4c69ff55e13e745dc2315f787f6189fe00e6e6fbd5a9585f11e31f2ffbfd17d4430c4484df66cefb5bb25b676d010001	\\x40513f86267cd8a1ac3e2bf5dc647bcd0df05f2cf0cd2a4bc70239321495fa337bc173617ced2514cd10fb9c31d350f663863a2a7be4efb75b6ca486b375d808	1685954030000000	1686558830000000	1749630830000000	1844238830000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
86	\\xd01c2459d7b10bd90bad38e56d08a134c8d0efbe67bf0d02a6af5646517dd569767f104a0341cdbf9a37f751e37b1b41972e13646eab63a08357951e2fbdb973	1	0	\\x000000010000000000800003cdacb4111ae05c2f4c779031d0043a7b258937673cb858e78d65c112233744cfd61f68fd67719c2727640ff22ed6b820812c32cf043f9771305204c088c1aec2fcb1603dceecec019d7eda5bf4f11c41b5ccc55d1d18aae8d2b188ec7e41064aa9353d9c21aadb5a33b3e482bf3cd6b4de79b7934158f94283fd4e601cfd9481010001	\\x9abfccd4b33e40bf1bf5007e0de3181f51fa33b375eb6b29e3e006468f453135fa969b70f292551a316d4dad8ddb40d7b7904945a3ad3fd6dc26735bb63efd09	1682931530000000	1683536330000000	1746608330000000	1841216330000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
87	\\xd25885d5bfa32749124f2769a64e5d1356454b80b41a560b6e0931f10ec2eeaa789bcc5ed52636cf0764ce8111a0a15d324efd4a11e8030d8a1e1294162dc996	1	0	\\x000000010000000000800003c7a15cfad3b0f4ab8bd43d9259b18d2cd2146341c05d3b293372107603e084f4417d1209c12fd058f7b3a3e4d8ef4cb6facd099da19fe53b75bc9de31a970b740427d9c6130c1f91b7e4ca018bd08bee31c64003e9c9f7e577d4c60f99ef5696cad86df062458a26f3728fba344a36633bdbd58e39fcbfdbf5651407598e10ad010001	\\x8e65e99ed97917fb4d89567c4214551066034b2c2a54d7e91f039bf84d9ceb2b439e874d5c9fd5c568872cf8e78176bc75d66edd6cc77917650b084cb2c4510e	1662378530000000	1662983330000000	1726055330000000	1820663330000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
88	\\xd30cf6b3564c30397d9dc746c672c648200c6a3d754a55baf40b104fccb88d05e4d3c62db86e4994ba009c1c1245c87cc96861161ae57af51698a2485b7e1674	1	0	\\x000000010000000000800003d688f3e95fad562ddab3142905d66df59e77e86545d21f0ae138f395458609ec40e4b63789c92932f6117dc63a89e0be1566ff14fafe3cf2b13c71a8e845a8bbbc766725bba0939670072cd26ea8f228e18a77b68c79331ab03e080f4750cf7c29e918e9faf9e00d5f9d46c429541f0ef235ae15bf3ebeca24de92d6cd3f8fef010001	\\xc777965d265bd2ad2598d61512f73a446af150000455bae59b722238a7cf24b2a27172b673a8dab4641395c14a55eab3fda52801c76c2cbfd86c275e9f3af00a	1672050530000000	1672655330000000	1735727330000000	1830335330000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
89	\\xd3cc181e3815715bc21607eaf14c7a7f82aae292218b9680c520d15f10f620ca260c43932b951bb3fa9b78701e19c79b51e70c8ee3f92598dbb4d61c58d5f992	1	0	\\x000000010000000000800003cd8bf91e01746325fe0ccb9baca66ed190e2f53cc2fb88e164eb92086b2965e5dc8021cb853ce7f4b8f04e835ff996ec70a0f4c2436bdb894e48b409c20d15ed504ee6453d72d160de8d77a48bbdbfa5f21a3a44b9a881f36f498bf0480a5de7885d86f01ce6824c624b60f6a05bd55a312d0161f1ee4f083b140b6984ff4521010001	\\x1ec4930d524a99baad009f53a160dc656976df0da31ff1d62a3e1938ed4ee0030d49950eb804d6279582c6ccc545f6987f05b2b8d1dba2101b88570490891505	1664796530000000	1665401330000000	1728473330000000	1823081330000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
90	\\xd5b06a884fdc8f776248acb7f4d8a52622b8f0c39e28d4e101259df35a719a3e6996098e274678f9cdc87a5dabaca745f0d23da0a95c94e1622082fa9aee7117	1	0	\\x000000010000000000800003a856c4faeb2925357df38bca005622c0630cb00900ea569f11a551e0271078396305f35297370a781745c6cd6255add5e89d805b93a2eb0b52d19c50ea57a764a9cec358a106cd37098fcec7602105f9463d4f78b22801a7310cae10809955e732cabb99419e6cef59b0cab7bd6c176dfa25b60523e84cd1f0d3debc2690c035010001	\\xc9c4659fa331cb76a33f141414757b54857a1287c3b3235573f0c40ce6d3da5723cbce462953d01b010e776c0fc1cb8b82438821fd87e1aa2df9f630adce7f0f	1671446030000000	1672050830000000	1735122830000000	1829730830000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
91	\\xd80465c42131e7e784b8fb022b62f041ed99380a1700b6be387725bdfe1565bdc22ba71d99930c016ea457035dc8c94b6fcfe45e2ae258b3a7f29bd80a185d51	1	0	\\x000000010000000000800003c099577778ff990af23cab3014a2327f50e87be3a13b0725298a5de6102665f92788d6c5821b14cc033458ff4aa12c955f14a3fdf357795d024dc01a0570376814743844e8d53198d29c3ea4147bb75af74678349727f92e6c6ac8947780fc695e9155ea1f6450caf52c41935d78d548378d8bbdecca8ba88de317786932c487010001	\\xca9db5fff46784476c80f24321544356a23bde9b3f8e4de61a82a211adb6e7d70f71dc6d61884bfa5ed0c289910234e06042a7ca40bf0fa5a1f910811333e806	1670841530000000	1671446330000000	1734518330000000	1829126330000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
92	\\xdb782c80864a046ffe6572bc97ebbddecf0b9cada96fc5e48adb39eb619d8a3cbe32bd6f024554fd68fc7c74c0ace01e269170f163415247872918d1d560df4e	1	0	\\x000000010000000000800003e9e55f0107a5f44cfb59d239f250cb88a307c4414c93afae7f36384a7a021efa3f0e71df240250b330a4e8f4d7a43870f6cb7c70a8c47b73a47acbff3f1b74a35563a9aa32a9a9a246de86274b3900f0eb7578449539894d9e66a7fa21f363c1a4503f57e27aad9d677b1bf4202be54a11d8f080d31fe1fe2fbaba861f960755010001	\\x4fe59c8808875af3de443e518932fe09dc27ce36baa7d8c63758089755546573983f6e80d71ef2d210c9ceb34e59da054002f64171e1d77f7a70fab69734da0e	1674468530000000	1675073330000000	1738145330000000	1832753330000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
93	\\xdb0cadaad01693b80fc50267f40d85258dc5eb64a9a4e72d276f6fb3939fd516da3f981d5f070c8b8212e87daec22998b6746221023dcab4e08f57dfdf14c212	1	0	\\x000000010000000000800003ae59184fa7a50ce483d604fa465959c3b5c16c651a6ca5ddd39489d802c36c8642d5134ba63e1a192e434b9ae713738d2175151fd3e10c80e271351c9b39fa2158fc3e5c10d962b5de9bc4068decc477ee6555693e8ce14d58f9842d9b94b239eb7ebe49eb2bf028f998054db2825c0a4f3f565bb28239a50d1a9d78b8a80737010001	\\x4515f03a25c9339efb7dfd4a1038541f703b401b2035b05111b510fd2dd594f1171f3d0289d9ee9f1763a9aa3d93dd667b8574bc35d3bcaad643b3b416aa6100	1678095530000000	1678700330000000	1741772330000000	1836380330000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
94	\\xe1680f5a5d5d13411f588ec511b546e79873607eb247f7b46cfa92b8700f3668676a7c6c03247e61d951155748efa0002939d5a9bad195ee9e5a0774d2fd3016	1	0	\\x000000010000000000800003c600f418cc7fc4b5841fd9f025daf1dabca6ef1cd092905656e2313222984642b4bded597d3392a57b55cc6b43b9889e7a92747df6b87a5799afc57862b30bc88b7ffd0e7275ffed0dc408e2425b5dbe9fcfb46a0a74282d3ce43403ce66180a210364e44e3a28e44bf174cc64586391e33b0c054d2b8cfae26cb996d0d04f39010001	\\x3271b7ff4c4d61de179ac3fee48c3728c2311f7be2f6be34456beb380d30d2b6f7669c98d1f43dbe8ab818eac0f7eaee7c4dac0eaffc2b759a0fc3c45b16c305	1685954030000000	1686558830000000	1749630830000000	1844238830000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
95	\\xe37025dd41fe79120a0bf6414d02d0004b6d6e824a3aed7fe7aba1aaa52c2be7dbf9ac429762fa1c65a80d151cf37b704fcc975e91a301bc12732324d8baf8d1	1	0	\\x000000010000000000800003c900c0cbd217971bef44e3ec85631f99b7107dd3bff69903ecc325eefbdd3a4ba6138f51a6d600cff3f503ce08514f556465970a3092d11f1390c30d5417116960ee882b936eae4059da365616cb97b4cd3b98bcda120634ed6372d8e5ae74cefb667fa0c9faaa3ba8a535b121a7265594d1f3f06dae6f70bbaa42c5c394e341010001	\\xb60ecfaab655385ad9bba4a881f7e59bdbebc94172cd38e3b956aa3942b119025cbce7992c3663034ab1f77cf761e777a655b826be1b91bb5ec1bfe95e875508	1665401030000000	1666005830000000	1729077830000000	1823685830000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
96	\\xe5d0be7532f4e4ab68f456445ae76e72f7d862b785b2fb0ef38e0e3cd0af2475ec1af791dd7c2af55185a6b27d017b38428a8d36505a1ef831f47451013bdb33	1	0	\\x000000010000000000800003d9225a9176fe3f3a52dc186493a9089621eea95a01d64bce1bd74791c7bedcc9e2efe9e50dcdc74aad2aa4cecc156634d2391eb76630859a23b7b3baec789263f117a71172a1f6fa9978f33cb1bcf7756b3d793597a8427dd6c1ba327be5408461453f1899287db5d601a424958491f22aff7e357d9a2bcb4db8b3c8b5975b2d010001	\\x53a41b1c3961d11e7da4fee4ef93af49069c823c8fdebdb0d4ab258e8f5e3cc4514a46a74abed9ba64b8ef2ae670a576adad16e590bf13a677ddcbaf011ef70e	1667819030000000	1668423830000000	1731495830000000	1826103830000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
97	\\xe5f4a64a3ccf19352a804cd1ef08a4bc479ca05958205a5741aeaffdbef968176af143ac8feb6ff8337df280dc6537335bd8795378273f917b062345c9cde0d7	1	0	\\x000000010000000000800003e44074d953c33a25488d36283191fc58524c2a37bbb1b1c061f0f8af72b47828178918c6e51f90a8ca6e7712e1b0c0e0b2fa392c4c0a297a0bdb29136df29a5fc197f780bc4faa19999061df8eca9d1ad7ffac21ae1962c4603bf969a9dcb6269f68be9a76018626632c11791307d986647e98b86d434d2bea00fd493799f849010001	\\x9dcca737a8eb5a716cc81746d3723e0bf865aa6beb9b948138e974ab043f0f86920b2310e4487076faae4aabbf7b3cf237dfa09c4fe091e25f4b113a2b94a404	1664192030000000	1664796830000000	1727868830000000	1822476830000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
98	\\xe9f82004458e7de01f2a23e8a6a5e7056ae74fc04bc207b30166f72e7899cb60b075e9479671bc6b7db573c8c59246c6648a8dae86ca2fc86507af63ce132136	1	0	\\x000000010000000000800003b66171c242b07f9eb9acee370720a5428b9749f9bc4540b9001f4a3d1de6831e5935542c0297043406926a3368862ad343fd39bda1b359f2a546b7a80ab17a9280c2ad8340150bd719f3df5abc488eb6f1e87bccc2f273ecd74ee506e27bcf82ba602956d78ca3339de727fe5fb8ed95e5924f11ea3b369b5f5fa5a8037b2737010001	\\xe9b912ed45cd98fc708d3ed11b8a07d767fb803425505a8f3539dbcc68c9bae3e3fa56e475006cab8defc2cbecc379eacc273350dc3a203cc6904a7611498c05	1678700030000000	1679304830000000	1742376830000000	1836984830000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
99	\\xf3c426833513ce3da1fbda8d78b8fe3e20d831b35f653b72194bed95b473fc2ed886e9629907a754930002d30dfeb85e7942e1a565ea72d94276355c1971f8d1	1	0	\\x000000010000000000800003a519dbca872a786726a737929a59300160df14070459fe53f853ee07bf8c72b2c8e8f2511a052d7ddbe8b630bdaeec6afcaf512fa7480f087d97057c12c5f23b834af1ca1b67404beb97a2e20464982febe79c6a806a1ec3476e0f23c299aad741476f09fc6f43ce1c0170782237635d0a98dfff55bf09db8c5c940de082a9a9010001	\\xe974917df21a345bc8f1da813068e11079eb55b911c40b98f207ed63388a068ac7cbfeac1e8144831f5d35614384027a6a4a55acacb48d9dbe3f5bb4aa48090d	1685349530000000	1685954330000000	1749026330000000	1843634330000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
100	\\xf31c1eb792cb92bf515e86d9e1dd469d3793ba133406f1074430bb1410d291af8307b8d2285666386b537ac38018009f32e46ac00e9a4326a31d859ad0b073b9	1	0	\\x000000010000000000800003bf82d558d8cc94849b30788a4f20d016261dbc359994a6dd1cbc52e33a0612b574f4f9aa3f6041d177091e6de8172cb513ba87d8b4fdc0b68ecb9fb1bb2a2e27fbb6d7ab6bc69a1de5f4e3be5e78d969cda14e1c86b8a36156b6f616f012e9406a7a9c44fcf1b170c4f047f99994c9569b9750465fbe99150062b84a02f56099010001	\\x0528c95c34e8e4a7506d1fa293e94754d6a2a5e2ab82b710268ae69836a018dc41280d6f9702e84ccfa39acd4d179ed0139f196643735b6606ced4b949149500	1662983030000000	1663587830000000	1726659830000000	1821267830000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
101	\\xf604073cfc3179db1c80bcb1668c58d1e96348392157e674d4fdc90030ffbaa849215e7c59fb491108f7c4239247a64d3187a31e6f8446f4c0d3cf3ea1e9bc90	1	0	\\x000000010000000000800003a96142c6f4d7c159a57e55fe90064785323bb738797e1e635841eeb5635ea401a9c65a77d2a961fb44f11c0e7fac055328cf130e0f011f71eb8f9dd29c4db79999ca671c5e5e922c93678f0cf4b0c408c433e41d2ec670bd8295b57442d254c402b79dcb5279cd50cf9095ca1c84b6241a9d834294704ac2d86fe64d2176cbf9010001	\\x47d4fec7939b59a608f1e27f86fb8978fb8c0e74ba2fd5ee2e0c5e38eec7aad5c9b6114e5eb82d8ea71a1820ac796156752ce9b62695ed70400545703edc910b	1659960530000000	1660565330000000	1723637330000000	1818245330000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
102	\\xfbf07e208d51e7765f7a11bc6043f6bb0f6143420307cf0faa07e78dc4ae23d5579b780c80c7f42cbd98e9e888849e740a6829251df00d465f113d944514c6c7	1	0	\\x000000010000000000800003c83d16e0a01f4d836945f2e139c884ded48766e43e87a1db910243f98dca2a6a86c71c2bcce311a8d210a0c2d12a21001275ddbb1f2daf9ecc65e3f8153251794feba4f4b8063bbec96f7c3fb9882ac28bb7cb6a302d2d928011a8cc4e2819fb6befcdef523e59c34b07f5b2f4f8c262029bbfa7a64b16873c05d2dbee22f225010001	\\x6d281c327c46f776becd4be1fb555b4139ab60cc5bd32f61c547a03c8787af391f133fe1a4e282390d1d87e779ff614cceccf38b57d958fbf24e0d668397d603	1669028030000000	1669632830000000	1732704830000000	1827312830000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
103	\\x0675bec7befeb78e20e5ff23a5b0e7f16536e14a6b617288049bf78da4b488035d7259d5ae1768ef70e9d3e4927d370a3d951a426b78968ad8a8ecdbcdd93d6c	1	0	\\x000000010000000000800003d0aa784f0a3be7802d93c4b0ad90be45b95a7f12f77eb15cbb0c762433018da602f852c703bcfeef0bc1196b784a3b3c68be0936a24f4306e540c29006fb90d4343d16016423a3ca70f648f547d5f2d70dcb8a9f2fa728d3aac497d8aba0d4e026485f9b11009037cadc7fd91af92440545b86a23171b52562a6dfb0c9dbf355010001	\\xf08a3ebd9efd35bee3d1f11429b59302d573c865e7bf9c9b239bdfc5e2985f36555797f925c7a08c60cc9b746649ff7b1e5add4a806fb38c090db7bae1570f0a	1672655030000000	1673259830000000	1736331830000000	1830939830000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
104	\\x07cd1a4f1c4f54c4a5228f4291527878bb62f8a7be7f877781a73e1f20e176c5e3086dedfbd1c12070bd2b173d52e435c09e7ded90b0901d2b7dcf4fc2eaaca1	1	0	\\x000000010000000000800003b713968f4e1e35a54b7c64d30e79f39ee87468cd5e1a6fb97c059765f908cee76dc22c4d60043cdc1c96183205888bd90f8327c114ae860f049cf1c147e7ec5ba2caaac762e69e22333ecf1a09e2fc30a0630f6ff628ab7348a5ace3332cdeb17b83444711626edddd4e1d3caaf08ac086ebe31140efae209af50ccfc16762b3010001	\\x1c881163e4fc8f487c94cbbbb91a63ed9e7a4e554c4e83cbbb5ec83d05661788368018fdc92fa5459867626d7c92a5d8fd2501b73ca11623ba32a85652f16a05	1665401030000000	1666005830000000	1729077830000000	1823685830000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
105	\\x09b584af9249b0d3c2468c2488d1c6436af49e468c4f817ab1d93f78b544ff9be8ce5beb4dec7e4e84fa8047c73031b67142dbcd56fc725781fb16a3e7e6f28d	1	0	\\x000000010000000000800003a5bd097f547bcb90d3c9b2769d82de539210c27b402ff56a08f47f83022bd2c6c2f601c3c2d41b836409cfb4ac2c04deefd307e9e2f364e6d676d2e30d568511c7e0de347192d71e193cdac51f7e178f6a44b6c4ea608f48b62d3bfe08e0020c94991c420bd8c86b0f3c89f6a63c24c563653cd33d4175f65fe74998f079aa27010001	\\x3b38328af92c16463694be15932e5a6ccbbc3e384d12456e9a57183ed5c31ad0cdfe24a7a83c481f063b17bef5baaf119b5d673cef1d7a9b8dcb304f3ca7db07	1682931530000000	1683536330000000	1746608330000000	1841216330000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
106	\\x0addee25507ee7c48c0afc2cc9fe2bbfa763beb2438b1af2a3c9ca46db2335b84502886d0ef238492c78bd6851d91b7dcf1f7491da17cf48a0ca9eeaf4d1befd	1	0	\\x000000010000000000800003e03f265f80dbf521f77f073aec82434736d679224d5cd405ccf77ddef8d39e56d23e8f05a49088f83b6e867d07b5dab23b4670f5ab0ddd1a5737833210c33b6709a791ab30f9322437f7d1ada7986b0651d48aaa4a9374511ad572a2f4100ec2bd01787d79644a3167437d199eb3f409768697aac9f390cce1d9932d3a01b1a5010001	\\x3145a388e05620db9131782cd61e33772f74390c2ff5e96ebf0f2de0fab9b73e13ecdb3bf7cdd03727ad7c7d956f8e2e53bddb0c231d9a5fec601bd9838e8504	1672655030000000	1673259830000000	1736331830000000	1830939830000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
107	\\x0b55c7472489e326964a6d09aee1c8aba520885a16ea46d7e109d0ee45a87490bbbc459ca7a9d8623dc5967fdada31ebc0f36047b677ea519aac534328e1001a	1	0	\\x000000010000000000800003b4b2a8f96e80b77cb70d3cfec170ed051fc7dadf48967e80af21129cb3942118fa857ade482aeb691c40aab5ef248ca2370d753efd0cb185a3c14efb2a79539459412602f97cc12e3a32c355c5eaf401b1391b13aa78767803c430bd3ca009885e4c07757675121b020319128d49b987317ba17437a8d801a94a335c8273809f010001	\\x43bba11a7c9bd1fd7d6ec18fd853cc7e954def049f0c8a6be147502feda5adecd804e1408a0f3d512841294f2a9ffa4e3d9e82fe3b62d42cfb02757db1b6a60e	1672050530000000	1672655330000000	1735727330000000	1830335330000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
108	\\x0d0542e9d4bd0be2cc182a6e47aef77e099c236223b3ead1c61cef849df90b55519e6fe96ee56729d1c74fa162f92ebf13e1b02dda808578d1337d24cc2d6879	1	0	\\x000000010000000000800003a1eb04ad73b6191f5546812e364138d4284cdadf8581c017cf8134853979858e4e7b071531f1f3a1bafb95d97f0630a70d0634ea87973c5e16110264509ed23cc8f12fa26c529db7250dc0e6dbaa1c5954e23b4a5edca1730f11825bc7816df0600cf9dce3466bbb7254cb776bd9c7591b6f9ac2a3e9a906ef880dc1df094aa5010001	\\x1d42e35c59ce52c5c09ff50f227476a3dc3f03bc5cf36fa4d5fa491bf2105363a3c590c2d4318ac6408df5b0b6bf7d7d03b16a9fe8ac76713c8fc4223a06110e	1686558530000000	1687163330000000	1750235330000000	1844843330000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
109	\\x0e292c2aa4441e075012856bf3b4e9f15b79a153b20c24d6a99ad44a9494875f8c71096cf6137bae16c5d98b2dc6eb0b4ec9f13e64272dd9518c9fcc1917df96	1	0	\\x000000010000000000800003b8eb7b6a5feff2337f94def6633982f7f9455d098723abe94f93ebce2ad725ada7464323643fcda47bf6331be45705f15a02e3befe5ddd28fca525bead525e8dd06c9393bc40fedbdc3319ff8f27fc821477eb18b54b6b0e1be164df97a79b6c43fa9ca704cecba80a9ccf449dbdc91afe69da41bcc552fd44ae870cb319133b010001	\\xeff9ac4c3a1a40b25aebf766994220ad86a953fcd2c5fa60c24fc7117711009b598fb9e72c7e060d7393250e0f2f64ca94d811244c4dbf23a409f63c80eb5109	1675677530000000	1676282330000000	1739354330000000	1833962330000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
110	\\x102d8e9d7fadc96052e5dd759b2a2b89e888b426d73a3e3c10b37ef03d24cdcc1def39ba83769735a40ab31f98b3934194dcbc6bd92ea4f88a47e579942d6347	1	0	\\x000000010000000000800003bdec6140eec9f3040b62239074bd32e932b0af781405d344b1baef44d2353dc43a779926369c5eac5907151f93bf549e6af88f2e7b0f6c3a8cee8769b8c68280fa96bdd500797923a242a9dd520942619eb7b324225a2e9694e2249febcd3c9e29ad6ebeb37714f4d95cad61847737c56fc189af25f37d4af8b3c5cf09d0e283010001	\\xb389b4fe2160b58692fe87363a780de8a088ad22192f8f62de1c05f68b70b41734903c68f2dbf9f989dd09e77f0ab8d998e93c10b3e361cba529be37539eac05	1656333530000000	1656938330000000	1720010330000000	1814618330000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
111	\\x102d55e9bd05321dd9d00be3cfb540b75b5a3474dfd226fd620faa1d1648df8e1f8ea3c43206e761cb9358bc6c74518e25a971fc7a96c2a5f1ea8586e8ed76b4	1	0	\\x000000010000000000800003a50de9b29ae74b66e2a73865c63e558c1351e1b20a82648caa022a16afdaf42e249fb3f0094c1407f9f1eb3248cc2446b9ede3a6567cc8ac25ed9351339841fd27ba1dcd8f420257411baba28ffb6ccce327d5e36e69979d1032be7e3eec2a0ad385c3a443833e722fa37fb58268e74ea3806c24cbabe17dbfaa8e234e3d1f45010001	\\x05323508d059dfa306e54576c94fb683343216cc59331f3d5ac80abeabb37d041ece0d8f073c67cd8167a37ed70f1708ac9e5c8176493951c59ccbc6fb502703	1685954030000000	1686558830000000	1749630830000000	1844238830000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
112	\\x1031c0486f623d83cf1e457b7606ed1b53cfadb30dedc37ea20f759df390e7fcd38a756116289ebec397c82e33cf2c8a5976ccf4df28e56a9ab39d990efa707c	1	0	\\x000000010000000000800003a63a80570279371e5fbe83000b82ffa6a72b8ea8b37c9f36fe9acb1c6763c10b4a1bea744218443242b123f7fb5ab399a1c74e0456993e140ec415150de661cf0e40695794a1846800f179ce2256577d21708f3231431960b5d4951782a31df48ee8cc204fbaf0cbf02e70971a6b0de395bd33cbaecd1d6e2acb78fdfa67e28f010001	\\x1d5ed66f6041583fe3ef23898d411a0b36bf98eeefc27fb3c0f851132aa80ee7fe0cb21428e469260ee0cdaf33269bf9bd370068d366a8f8a493781189d18001	1669028030000000	1669632830000000	1732704830000000	1827312830000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
113	\\x12dd27045d9ca9c7e45bf9296fae76afc690915a2442fffc9d885bbf6429da816fc980689cf6647fd41ed203c2e2033c0907e9c213aeace76b1fce50b54e3da8	1	0	\\x000000010000000000800003f3bc1562490b751d5f0cda2b65d3270c225969ee0a742fc310e0a6fccc4498e75e8bb309a1de655bb12e6a639c44b17d52ce870f8fa779c9a1eb3a20a3494bce9ce96410da10b3757094264074f072a815906da7d8a4b95585987a5103edbfee3aebf6082c9a1bb7c7dc899b675345e436830581b77d1ef5c393cfa39a21fab3010001	\\x3394b49092084aae25c76c9d9963913840d83e8fc79efc450b76026818cd82147996f0e292a6e34747a5c781ea3bedc9a286293eba683389d0407c86d2607601	1677491030000000	1678095830000000	1741167830000000	1835775830000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
114	\\x15b1ab0a3f292e53495ec50925d5d3fe4f33f3d835b7593b1e0a06da61a7b87c926e33f1ca77ceea9dca63992cae4ba38bfeb43936987da4b2e159d38f67d40b	1	0	\\x000000010000000000800003d172465c9a7315cdce3446948784c736696866d2bbf621d71c868e8eb0191538ce706af762703fcdaf2c7020b518ef88aa15ed5f320b98156322b7a4987bae0cf30a3489da1f45d7d56bed6297e9bca6e545e7016c3602509a0411a27be5d5fa6a40d4914e9763a3c9e6eb6a0646f142054b7fe45d52ad445af10a0e1dee5199010001	\\x08a50b64c58454601c53d0e298154f17fdeea7e8edcf96c1219977c8f8a29d5a291742dcaeaf6597da1bc7041814e3b3fd7a3cdadc0d77f2595c2ac33366ed0e	1669028030000000	1669632830000000	1732704830000000	1827312830000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
115	\\x17195c256fc27bfbf219bc858abc156c135684cd323225be5171f16b2b9cde29b6c16d2237656653022524456c25c68dadec69ec2e39cb17d96f2ceb496d5352	1	0	\\x000000010000000000800003c7a54e98e49d0773fd6fef4b2dc0c1e09ac48cad020686b06d4779f6ac2564f393f7a0cbbbd7f778cd7c1bf8227b4470c20a4766ca72f64a71a562053793ae51c818489fba40f9cb61821e917e721331fb965b5a90673d2f5a3af0e3e53cc5b3249e69265195206aa2078d36e8c158306d206f472a9a377ee411d1d810e0c211010001	\\x28ccfb97795ebf29bb75bbb12991ae2b5e67f8535006444f541950ab9349e512d08de3ad29c346b788514145adc3aa74b41389af0c7fdbc181a7d9f25364e309	1674468530000000	1675073330000000	1738145330000000	1832753330000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
116	\\x190deec2e2fee11f55f635f4d1dfd0f85fc3d1dde16929aa42d32d09ab239a4710222980a381c73cad017b2aa5fb205402e6e35003ed7691ceca311a260ac0b6	1	0	\\x000000010000000000800003d6e43679a002e9f042a542129884b8c6d25a9171a9e8b2e438e598e31717bf310c07e1de523e56016a0d19773eba222f26d096f147872b266c7cc44e968d7299f0561a16766ad66d9b0afb55eda012ad7b53846aef7bf89e16ef7f6ce5dff5009df8ace317124e38e2ccd479d86c8f66e73e0b41aaadef3015bfcfbe73ddde5b010001	\\x39e3e5b5813227e99c89d4bff8876f82753843a64a276624899ab48be2e075e44e06b9ca81e614378bd18943657f5c41d534d52f8134fe5e4df69f04cd41610c	1672655030000000	1673259830000000	1736331830000000	1830939830000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
117	\\x1a71c2d24a3c2fd601e1f0fd806c6c0d951a1ba5bd437fad925ec17745e8ebf7f15885af8eeb9f708c95d2e0bce08c461397d687ed6dd6aae610ffaf4687f253	1	0	\\x000000010000000000800003b4dd710bd4de3c25787765eb3c3a9a7685cdeb4b5b320389dd89daef6cd52043b00469272f635d3a74e8d18c4345da67acdc060f716eb53d07a10b5f6c7e81e003f2432569ccc06493b616e0b4fbd89741b64be46ec107a668c481a4b8de97294c739ce5a36eb54a86711b89b58240922ad5e4c6a5b1a5255bc3ae56029565f9010001	\\x694026bae85058630f5fc924b028b625d751fa1e2c6a6a9ffac4c09e5ab4f8ac0fb61137644f76905f29648c42e99311fdee5c39ae620893e5de88ef9198bd00	1677491030000000	1678095830000000	1741167830000000	1835775830000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
118	\\x1d79489552ef53f04b548528c4f55d5b05a4eb121cf98f583991f8d2ca61961f784c9db96f2e0098a7054ad02e14af467174dee673a7a26478b99736c8866e70	1	0	\\x000000010000000000800003bcdf84148a629f04f1501dd222e665930ea3bb0a02353dbde8f497969da4b55ba261dae72063630b1bf853419f8da534491ebab25e90deb69494c9a8ea5489e2c6d6b5975aebaa4b75f92db5c104202a3d7066e97e22b39f3075e399357ba396a19c507b1f5d4990ef8823cae3257cf7cb7e5d2fe69e95ab24b835b759288f8d010001	\\xc58e8bf3dcae137ddd8313a57fb355a1deeef516b27fef7cb9d3c184364b5f1304689fff1520a6c41f8dfa47581e0690ab24f610f8d141def2faeb80eff99905	1663587530000000	1664192330000000	1727264330000000	1821872330000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
119	\\x1f1917eb8264cd71e001a110eaa63fb9d9577c4b77a9c18284629bb91053735d4d0fe935f9736e1b329bbf7dff8878ce5b0797df2ef0c048b72b0af5d0cd14d6	1	0	\\x000000010000000000800003e81e62643df227f9002438a540e76f994a64caa60c7e7f234abebaf4802689c8824737082dbe414e85d2ed3ff2900d8ec60891662f03eb50e4651a34521be6fecae7bfae6ed9ba987867c8f0a89b4f5f29861d56965ef39dd4f10d8136f1f1e1ebdb5625e1d713eb75217d04fe63cc0c8ce8dfb06e6822ba881dde038f2cd29f010001	\\xb1d6b83fce27bfd5214785db6faf1ea4fa04758a825d5a1a776a666edae8abba96fcb18d119796d8601f4a52aa504ae6f6a91352be92677c03be7d03704ab005	1666610030000000	1667214830000000	1730286830000000	1824894830000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
120	\\x2091426ede79f4ca9ab2588c4cc0495c10ca47d89cb1b4e0d393052b92fce98eacff92c0a39b9d300eb5cfe88e1d05612bacfa54cba45fa91fdb2dee80fb51c9	1	0	\\x000000010000000000800003c30349a69f06296074f7296ac119a751408624a0646f4a4c14005763c7539201f51844da1c7440a69237745509a22bb45946181d3aea0fb4c31b6c723cb379f402f06176b9d7ac84b404f4fd1662d3d7f7d004c465fe2d4011f61958fa51e84031e7737ccb3857a382b94204584accc690da0d8692e5bfe446e403f8e839ec85010001	\\xc6bdb1106b2dfecb07566caf24b1af7751ccb69bd34079a62b332a7a7d82e71213889163688103a1209ad247b77df53dbca50ee6b632a32637e5e2127e0c2809	1684140530000000	1684745330000000	1747817330000000	1842425330000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
121	\\x20697427a09e8b94b40b5546b044cfdab500ed7c29e6de4f902c6b494d55945369212db27ac9c25b968a6c0407fa6b4662e4d9fa71fa9f882f2f6539102ea2d1	1	0	\\x000000010000000000800003c382a99897ebfbaf0591c1fd6583b33ca7657155b5f7d2234ddf3271e371f4052a455fcfc8c40979625a3de57d5f324716d34c7e9a9713144535b5a4793c2da100752a03bd5605c8773c98e10987afc9bdf0db2f598186257196d5864da146be9011042c3764545533b5c9219d04a27ce7c756a8e0eff97074ce79b9fc9f3b19010001	\\x239d88f4b8567c2b747b4891e9bc9ccf5c9281823c9d4a1e18929b43532909efb4737ff520a4e997c80194d5d0222744f79cb395a60f70002fe16dd41fc43901	1684745030000000	1685349830000000	1748421830000000	1843029830000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
122	\\x200d843bf4a024ce26d754e2f1c82cd8a43aefcc3793c74bf0e83699dac6d5030abb519c1ff23648834be179d4c8bac88960789574ce2280e869bf7cab317587	1	0	\\x000000010000000000800003c27843ea1360571d8521be7f4c90fa2e236a71048cc221078cdf1979d3f580384a528a61cb7fc54f597d994de175883cd7817de09ed590aa3eb9681b53eab5ca47bfd503d6d93e78ddf1b9751bbb3d3d68cfdc608d80307ef3813225a3d1abfb5839ebcd645a5bc95dfbc957d7d6abe52c343c114bc556663f4f811959c2293d010001	\\x2ca6f9df93fc3695b26ebcaf8f64d56456a73afbe1776a7910b03e5577a52745427241b8357be75492ceb6445461dac5d29f5a67f8d7e3cf5e1fdd4e85a62808	1659356030000000	1659960830000000	1723032830000000	1817640830000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
123	\\x2469211fca7cc3584e1b2d07fc32f747b7bf299d019904ae38193bf4eb98319f9dd4d92bca5f08977eb10f9c346ec17d4d852d2c6e5db6980aa8204340527bf6	1	0	\\x000000010000000000800003dda2e18f61ffc1649da86b5e155f5f6199fb17f9fe700ca025e8d8a5aa30d308dc978a477d5221f0da5ed4aa293ce5dfc3d1f8a1398d1744047396525f4aa7b8cdc94b9ef3ab5e8d1b369d2f1a98ce1c3e67763c13cf8fdafd99509ad9b1b86c9edd16457fdbca05a6c760db69abb460b832c7f22e0bb84f1cb4e8c53d62c98b010001	\\xedeb6c08417dc796b28b86dad496dd629288cd21f46f975c6268b39213435c04db4f3eb227c1cdca19bb8e3fb8bf66410b79f89cfca86c109762a4d7a564db0c	1671446030000000	1672050830000000	1735122830000000	1829730830000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
124	\\x24f9f6e902304c349e2bd4fba26a7000ac6f4ec062037cf011a9e541728308a729c5ae26347ed66ee4ba14e29e115c0ba3ed1e08ad096130a2306cd6e9e8cd73	1	0	\\x000000010000000000800003b88f149ed2cb383a3a40af1a74e5661f02c0d28c1af9ee77f576e2ca0309ff4c3c52822ca3afd0240ed04cea336677041e5551ec065cc4ba57fa471e55de79f0d5ec4ba0444364b7522f8aa92c53942b59c0252963d5487c66f2aa778d8074b5a59aabdb00110e98a9ac571d17cc24a65e00d92ffe8d86cb90fccc864adc586f010001	\\x024efe112fc3d8651f2865acee5febd8da923c9f44c607c65b11c9b8e0135dc189890826080589c9cc03df40e583b32c760aa47fd5ddbf9ac7d3343c04ec2c07	1665401030000000	1666005830000000	1729077830000000	1823685830000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
125	\\x26ed29c0606c38269e6104d6fafd8d5c3765e9336f4deed12301f4cbfcd7b21c2c1fe59b577c044c8551563dc485d821fc08301f703d4b45721a668f784ecb3c	1	0	\\x000000010000000000800003d5ce647bc49bbbf868578102eb0fc95a942675e6a4d149230a7bb324968549e9600595cd931c2bce2f6d39f5d6e6e8bb00017b9112265d016d25454d4f7c33b36016c513a3681c7d848d4a22bb0c2ff0fbc0b8e0f871594c482baba2d7edfad113e58de13846f62b887bc772ac602baf00e2c6e67c5362595268e48b2be4d8d7010001	\\x26f08e4f1a0f0a990a1064abe9165b1aac7fea2bcc10dccedfc0c20e58bf270f3371b8c2030c49f96a5bc23eef6f358b8258566efbbd55ccfcbb8772c7224b09	1684745030000000	1685349830000000	1748421830000000	1843029830000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
126	\\x27ed952ab6b6e1997c8f2019e9be0ba4902da27fe5301f65b92e0f67f7c3d173f3c63fed589119b1701de80e2d481196bc4a03bd1b916c49efd6fc2c7056b865	1	0	\\x000000010000000000800003dc01724a0849ff1ad200cfbd52d5a3ac7c52aa6939dbd7f3250f1807b17df8a982b3b32e6b84eff63452e70106fd6249ec2b460eeae092adf81f42562e383949c2d07bd82fbb04d3d18b5959bf6a53be253ae7678c36e73bdfcb7652be4b7a5e0b7b145a8ccd1e5f1a79084b9973a9b9659b383537c10161ee6663ea4454dbb5010001	\\x55142441c886870fce48a88335ae4628b185e6bf1250990db38d964b6375585e6e2a8c6a1baac4e0036cb39cb8b9c97de1b202e0f184770e70366908b9efaa0d	1664192030000000	1664796830000000	1727868830000000	1822476830000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
127	\\x275596c824acc3f1ba5a26e3a7a287f4e43bf1f028d07237698862bed94ca46ec92544fafddf547fa0a1402dd475016d8a19819a183c15cd9b0d76a76c8c8285	1	0	\\x000000010000000000800003b7f224ecfb35aefed8255e7135abf08bb96daa6415c5a902c839400e9fe4ccce2c9020588705b45f77a115b895d0ead69c35470b7dfa722d2dfe2ee86cf17f9cc5c4d410027c37e441393cbdf7d9fb630dffb3b12576a56441cacee61dc686103bd253b027164550b5bca2572bc3e6c17cc38df348c09a39e414015e46af2bbd010001	\\xe0f0610b636c44b60a1cbbda97fd47a456871b6cb700bdc65d0c4897684909376af37e565df948dcc9239a0e8fddab68531b29bb225f53dd5837d18c3eaa1503	1657542530000000	1658147330000000	1721219330000000	1815827330000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
128	\\x2b71f2065f5a3c3e54253b4efc3e4f81168a2f63328bf5075f3997e5596380ce1a5234b6dea527d69eb1fa3fed04a23f2543b0af1f9d76cd7d5e1519ca0b5a03	1	0	\\x000000010000000000800003c5aa09ec7f3bb641a8a9e3d4b8119224ef969e65865d4884c396c63632ee4317f26dbeee7526ef1706d09cc6d5aa1628ebe8d029edf05e31369bc09128f1224fd76e941fe0c69ba995f2a4e835029b5a1164e5743fd0ccd070461e034fc322c928e98758cf265330f087ca7fc6dfe45d4cc5ec162bcffeed83634091c849b15d010001	\\x5d78000039e6b5b811e53f979a8dd7e9de54b9c7d337e27357ca417093befb88fd65a790763791f9803e38546a54137ba287835d49ced2b1c3a47f21b6c86107	1655729030000000	1656333830000000	1719405830000000	1814013830000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
129	\\x2b89a8eed7cdc8153a096d5158fa2fa9f103611bb814acfa17e11f100890b10e37254687edf10f25ad1458e195235ca922dcff316a99538f55ea738a709542b6	1	0	\\x000000010000000000800003ba9aa48c3d842f3913139d7f42d4247e24fcd597a3237825a35dd7f5e65ef1fb1731e67f8ca7584fa81bc9067b68f8580d533ce3d65bc32579a3a7acd284a3662af9615208db298cf0b2ad7d37de9c5ac5602383cb27dfca6ec09fa054771b1c563646b1c3867dfb7f584c54dacf66b12663d3f40325aa335b8ebda574eb3f73010001	\\xb13a29f229b77e57c7bc22190ed73b4a67639a7e3a6ad28ec80ab2b4b803f0e4845d6dadf80cd2b9fd61eaa6e09a56bfa3b64695c549fed7dbd8508c42e86b0e	1658147030000000	1658751830000000	1721823830000000	1816431830000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
130	\\x2c693e2487337cff77b385018107b717097ffe2ad0d96e902e30133bb8eb1d5c76b5b50a25ddebba9e98e66410d968591f4cdab6f3e92296faf3b536bfcdbd21	1	0	\\x000000010000000000800003a2cb1d68e0799620a2635b6d2be9e47dd711137a81d2540ef3b1fc1c9e81f76923c376e6c1cd196b1a9919e066c6f1ecc405f921561ddfc5fc1eaa9f9dc4ad67e33ed2e0359f6f05d966353a097f9d9eb80810cb30e12379a2384e68f775c4b56be5e845b0b029c458fcd349bf6bdbefe62298b824b5a68962a9d4201c96ea3d010001	\\xc607e406dd1b23f3e88f58f1246825ac12b22ad3b2aee7306a2c93d9d00f6ba7dc04d6c0c832ebe0b22a97ee4a54a68f5d5dbaae19207d4635909f85f9564c0a	1655729030000000	1656333830000000	1719405830000000	1814013830000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
131	\\x2c653a416dafb3791f9faf04a98ec0d444d51748619f65f539c6e1f120614b0994dd92ca88d7efaf2224a64a1865b04863290af50368d1526314d3ed7bad5157	1	0	\\x000000010000000000800003b1282b5f188643e47e13f411fb06b4b681e3e7e6106afa1444e474b822902c6681f11b57a6e94a367271d19c9912852c202a07bdbe42bf2311c413cb3a0d97899acee8fb40f1847183f04c78ae6e54edd7d56eb68bdf29059acbb2ccc11634a0ef230a9a6587e201f57a2f62b0ef88f7c88ecfd091494aace6831db14d3822d5010001	\\x47418b004b6b235affc38afa822ca6067acb0183040cc2162988093453a0694516fd59c555f45a441eb1f8dc927c4d1530039acc038554baf54c42436e17bf07	1684140530000000	1684745330000000	1747817330000000	1842425330000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
132	\\x2c91cc51973431751bf1dbc84a74826a7a9db810356598a52960a07bc7c68128b5d1dbf194fc9f23c4ff2d923750307a397d24a00cc6dc855d2fa915a63bce48	1	0	\\x000000010000000000800003c72e1d4215fa72d8e122c736ff21503e4d856a15c5cd57f9a1e1c4ea0a810861d62068ac29d1c452ef5c116ea160d2a425b3d1a674adcce564c38dcaa708d41c04336b3b7967cf176264e11b94daea59fe1b16dfd05ee57dedef047dc3e706637ea7347621c5f6d461ecb0b781b479d6dc04b997ca001bee884f90c0091d9581010001	\\x18bd5a0075534b6631e56f4745766951cb3e9196e7ad47bf5aa92c39656211b8eac174c55d9a247b9830841e2ab64079b1992d724e08c7176c14816d0c4a1400	1656333530000000	1656938330000000	1720010330000000	1814618330000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
133	\\x2d759ab3f8974d9f79ac596cef7c3d0a480ad193086979e57b10e9a43761febaffedfb1143100c2b7c91aa86fd9beacc5d589ff3fb4ff1a86a0514db92ded348	1	0	\\x000000010000000000800003c1ed68107829f640f4be2f971de4c26bc07c47436721422a505934f1a81625ea2fb3e712a9c720092b01ae4d509bbc170bcf2d6eeae56c384cf896dcc8d4acc18eb69ef6abe485af0db02ffbad4a5d2f200be3e7c3c75ce47a043fbe642694b807639779a38581fa2f9fc428c8c204fa3d0ad4d858da372dbf551e42a5833cef010001	\\x88a30b512217f211f9f49e4a2f1c5dfd54adf96d3c248edc7eb557fb884f73935dd42b62053b3d0c0c355334866e74e0c65786986efea742f2181253182d5400	1678095530000000	1678700330000000	1741772330000000	1836380330000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
134	\\x2e15efff710a82d7c04454eb8855e3738f9f33fb8f3d2b5f1fc9c8cc627ada228d8f2a4ec7b9e6a383557f82b58358e36b162f14717a467764d78c1992a92577	1	0	\\x000000010000000000800003a1a6a551ca30d21717b3b52fef16f1615f13f2f35b23f55cb6fc076600344e2d38702f75e8e7ea5ce0283a156b0a4e472171e68861dca955c6af6cb3aeb73cde88ff4bd9d7e35da4214677c0e7a9cd0f947880368efd7c5350b60ff2abaebbaae5bd3cd3ab851fbd0e3ccdb0dffa220b0cbbc29ecf029dacdba9bcec74854dc5010001	\\xb89d428570770ea0880203d6cf1412e9c37ebe6cdae6b66ea2269607ed24b57f92063efa6288a14017db3412fd4aa004ef81f067414b13decb7811ebf0e47a0e	1658751530000000	1659356330000000	1722428330000000	1817036330000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
135	\\x2ff12c12daa38dd0820564cde852964e85540885e7cfdf2bd227b4b3b25c000bc761fb5021ef0fd5a0810b1bd3944d832116ed25f8dfd083713b2d22845eed58	1	0	\\x000000010000000000800003cf1431612d2eb73466b3177022002350cfe6cd6a964aaad602dc53f11c79f7328732e87c1fafb1cf76bc96370d3778a7e8d1b31a55a0153402f29d79480a7a938cb461074cf67d1be83212ed3d826d586ee83f43d188063fdd12670a0ee65bdb62b3b41dd91f02b7f4f40344399c8a815e8a35bea0bc3cf76faa14209776ee6d010001	\\xd2eb5649ea22a1c09dd4f692102428dca4875befecd180b9259738219c6a294c6613eac80050b2522c6bfc26bce081d49550609885153dca16dad491f6686002	1681722530000000	1682327330000000	1745399330000000	1840007330000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
136	\\x3089e0e1d26a0e4c96af35e3266ebaf5ac4e354f1afaf9549a05312b82f08576e4c399758beed22bede5aa17d74472a1dca6173c2c0a5309ce2e20aea50f0532	1	0	\\x000000010000000000800003f9782015b562b87828cfe0e085b7d67f4f133196dc97cb737d7c35d66132b735c9aacbe2432ef605d8bc58d2fd1741c8d5cb87d6d7981999ae35f6affc0145c39a208179460729292fe08a23a0bc3248ed944a41c9933aaf82cc6742f763f13c6d0e2d5d17b8cde8d6d8201f609e40b1b374eb30c1b5457b70a41be8a82f4d13010001	\\x044fe6f2c5a61012b4723e3eacee7fb8f5db0c3886d765b7f9bee05b089cef35469f6d9a49b0b9f29065a24bb05d0791516f1915e10b7483781e2fd6a019a80c	1667819030000000	1668423830000000	1731495830000000	1826103830000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
137	\\x317550d031ef5e6eee6c12f3a2894f4779a70e4879d613caaed89b402f79009a81f1bf19167744c7cb9c88b880e72593ceda99e0751c119bde565a7bef304047	1	0	\\x000000010000000000800003a45af8a1219279d93defe7201abe0b68304613b5fef80ed7ceb589a4409053cea98b01610852ee2c6f07451fc92772e44617548b531e7a84da45300448b3d3ee056b0e6c8de22753befe5a07c632a6a576f9af873734afd4a833d30383ab9714f98df63a844abed69e93faec7f38855bb05a4211d96770faca349c58b4bf2137010001	\\xb1c66ba8c40de24e3b35101b66c2fe0677594d693f6f52f2a23c934165e6b4988a5efff991f99b2090ac6e64dd658deb95360bb42fa8bfeb09e930485b7d3005	1669028030000000	1669632830000000	1732704830000000	1827312830000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
138	\\x3295dbd6081285fe0a8738b160ebf11d284828393a9a16017ff7a513356b950ee581d13e787153227bd07a5a4a48caf5dee5500c886f9145872131e414dc2123	1	0	\\x0000000100000000008000039d54089e23acb0d9a50b986fb73b0c71ee69bb21dd8cc3513d34c5d103827cb9269ea49152f2749c928dbd2410943ca4f056b553cc099e62c550dd81f84069d29158cb02da113ab36f0383632c876046a4f89130ed2e2daae25b7ee0e344c392d56f9e859dc844eadd5bb4bf6c28500e76510f952126c3b60ff8c821a309c0ef010001	\\xd13d386620d13a0718a14fdc743f7a80dd3c380aecd919c998b8c002a3f23a998d5fde210c3fdcc6507fe0982e32c2c73c8253d6fa28686fb14dd5236d51e90a	1685349530000000	1685954330000000	1749026330000000	1843634330000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
139	\\x349dc36d0030efca35ac4aaf9f6d9d77a27c014a798437025b7b5976df2f73b0e67d3639cda165b38295b07aac8794ddad6fb654283ae4768d24da408349e937	1	0	\\x000000010000000000800003e5cce2239ee64bfeb8595185657928d91f89a1dfe4a86d1f422e5b7916a4401790680fab28b58e8627319cbf0357df523a532387e8e63361bc708d01f8fc81a8c4c21bc884d7fd81941aa39ebf8f13c5acea9fc41c1b71572fddbc79e31178120eff41f11f6bbb25c56177e015db414521b970df1512b01b03a284fa1df2cc91010001	\\xbd6c94cdb73a49690d44593acaea8e279f831d753fa8b81a28db327256330155a1708ace47a458e79c4c25bc9d44c71b0f0152d9304b14cffb083e9eedfa650b	1679909030000000	1680513830000000	1743585830000000	1838193830000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
140	\\x348942200b7f3ddfb9f55f9c0e8c0d61d1f774589565a7399829f8b03eeacec4ec2073913adf0975b9a3136d4245ff1dcba81d3afa69a6384d1d49e155cdbad3	1	0	\\x000000010000000000800003b43924367568acd400b00713dbcb1052e500a1edc9d10d43aad58382046fd77f3371dd3c14cc45f0ffe7fe830c7d453a44997dca21d96f417c92ebf9a5940e1775b54ce7d0b4be403152d02f87accd1919dbb6f67221414c8ade271c33e872e45e9b1a805df27a9fd8c4887310cbcceb978c51f891fcfc14eda04f4f341dc807010001	\\x187cb37170fa67f6ac0385b4a68a64bf1bd731e719c9449d80533a46f9a5d491e648112551ede3dc571883d4e68af4518e173adc2cd0b5b5ebb8f35c219f2100	1661774030000000	1662378830000000	1725450830000000	1820058830000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
141	\\x3b89e7df8737f1f3df572e0bb8e765aae6cb53e80a370a108966ee118a8867067d348e559ee1922bf2fefa47d2780254abb71f4e373e2f57381d78bfa58ede5c	1	0	\\x000000010000000000800003bf32d3a432beb2bea4d9f3f956c7867031cfe3017d6a1f8f71f6b7cff111b7015e0319513a33a077fb9b7b5f3f28aef7c14db3b2161a4206a9fd1bdd05d8efa624089a18091487fce524c6cbb6f3b8af28ceb612709aa7cebd6e785ed98091dc44bcee044a3a09bbc4172376515380c4404c87cdf4dd75a4026bbd070f6d5029010001	\\x62dcb31c41ad7c2cc715e66982376370b59b83438aeff2709ffeb77489fcb1ab3b9d445b77a5d4523ae5ec7a6d301544c2cf898838a147ea14da5f014bd5f50c	1661774030000000	1662378830000000	1725450830000000	1820058830000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
142	\\x40dd30b3184338e7c6cf46bf9a802b80d1cbac3028dcf51083908b73ea4ca88b3bd7f3a34d6b0e0229e63c7d27bf493f304850d159d54c33ac7b0952f3dfc768	1	0	\\x000000010000000000800003c3f0daa776d9ce88b3821e5e7440fea2b994af4824fd9c5dc43b25de0b48fdb72305793cc5432c2a6bbc6b0917f9f2f273592b8ce20476f5de283e582ac9cffcaf618234a02e88fcd6dcbffb174f7f996050393bc0e2be0bac14a05b76b7b47a9644ebf63ea074f1dfeb278fc47f371c68fe967a1ab9160f89e5cbf02231778f010001	\\xea8e4a7c141d29799f88079213519cce333acd59baa7285a0bf50ab5652172d34892b2968048fbf0fa931b0cca7d1c9fb3cf790b1817d37fb237ab3229a8cf0e	1668423530000000	1669028330000000	1732100330000000	1826708330000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
143	\\x4185304a9b15e2e4ea91e2c0821445a5d38f5791e4b2a2c83272d6366c25aea66f1a11c638a3394bb56e63dd79d702f500cb7be517daf8b11f30b32751158252	1	0	\\x000000010000000000800003c00be3e0a9539a74197239a7c0c56d9a32d1d5fddf162a830dc25b749b39f230f4cc1fbf2123cac1b944e9f4353c754690fa0b2661fe3efd227cf44158a3c1f91fd09879b3567b0fe4d248faf210c3477400540fc45bc1507cdb7a96a04be1a8279bac5f265ad8f0ee67b00c724c898a1443e477db313ab9791c74fa2839d48b010001	\\x51838467c4d88239e697239aa7158730520206b6a726a8edc91ef1b2a69ab7f3599d6b6cc9306cd2c25d83ba2709338b5ee9eb252edd0b5d4f85495de384030b	1685349530000000	1685954330000000	1749026330000000	1843634330000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
144	\\x474daf77089045801183dc371153ca81121f1e302a0a0e763624596aec60e086c9552a131f8ed664f0fbdf407ad32c225da55905a4e6c849e77c567a35c22036	1	0	\\x000000010000000000800003b18ab3eb68ac9b7a67f5e0cf65b5a8839062c1843ea85a739f539ff4ec46da50121fae89e364b9e9a2f3303c768d4cf6ea3f4d93870ee56115feea6ffdbb2c99907bbaae10411eed0aa2371a34e43bf7a53b06388e0f980faef037bc477e09bc6148d5aa03537dfb452a0c9b785f1436ff8714eb91daa1931bf706289faee4ad010001	\\x9fba81916c67f3e491ba2ab9cdfeff52c7f17fabbb28e7259bda0df856a0acd999bbc8a7e3266420845f04a8327fa02efb5a87f30ace336039651fa409c0a40f	1656333530000000	1656938330000000	1720010330000000	1814618330000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
145	\\x4725d1ae948a863e10efd11469f8f902514540d2d51a020c95ffe2abfb65b9a1ccc56a73e7654bbc056050db22a455acbc3c34c7b88b599b4b7be64ecc99c229	1	0	\\x000000010000000000800003a73daa6e389ea6318533ea0e6594d1825b62eefe3bbd48cec358f5067955a3070e1a3a51928eba4200f600c50fb8d94bfad633c774813320724b72243f9b636c82ddb11a488777c9e23d9eb91117fe339e2dd97ceb2b1372a5811d22019735baa118b8fb8b04734f8182597d7b635f732cfc63d63cb83de02bcf1031e69f7473010001	\\xba2d1c4f9e16cba2281f8a243be9fe3cea24e67b1f9d02e26b12b3e9da9764e7321628579e1e567a35a48736b45d0b1cb91372abd5fb6481182d1f8313912606	1672050530000000	1672655330000000	1735727330000000	1830335330000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
146	\\x4bf9cbef0f175bf92a9760540e113240a9eb7f277f8bf59605a28142c1e8644fb4145606fd26d19db6983e6b825ef5b988b4eeaaaa54688e50ea702cb89b36a2	1	0	\\x000000010000000000800003eae732e7871194ebfb6f178ed2a8eae7eef7da8744797ca8d9b9da8969eac47a293453a5acaddf1d80dc0af3965ba6359d1764f85808dd5284a714e57ab9e795b97954d6f965e6685d53f39202cf9a8ec2f2a07804fa27055bd145b21c47b8007e201a221e2c838dd2a83d6d3965f56bf60150d2e105a09bbb6ff1a10bffbef7010001	\\x9648a88d6342c556e3b78644922e04b4def6054d2d8352757bcee5343a140078cd026db91ae34b20b424a9e9f96c6239a17f6f65735799e4e9ebcc2869fcde0f	1669632530000000	1670237330000000	1733309330000000	1827917330000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
147	\\x4b65e405f166b6ef70ea6e3dfbd26814c889c175c4e73d41b9bfbf7bfcbbe0738cc41e3ba78bdc12a99dd929a7f1570d7be6f87f76622d4adb4c5b403245d099	1	0	\\x000000010000000000800003a6ead2b03c89ee03af0382febb7a67aa88d9cc40998e21a370cf96ce687208cfadb722619c326c7127362ea6d30fdc774028fe26ae1668ac46bf7f2b22829d5a256ed6c42da47de33b34fe735934a0746f3d366586554e69cdcab7baf3c8a7851bbd91200c9abcfacf7c6f4b614c924b6a9982b92d8fc368563862872490ff75010001	\\x15de8017701d40422f8123ce3d872703ee6d1acc00e725a6742b0582459708d47626ee319071762ed39a1abd5cc0307970b68111f07f628db4135d0d8138c20b	1658147030000000	1658751830000000	1721823830000000	1816431830000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
148	\\x4e453adc2ddb91b8fa06d9e7beb204a22660e6b9175088f7d651207f1f8b32a0cc595773e0f559209caf93c8914e6069ac9701afc26108e659c2a46ca2d603db	1	0	\\x000000010000000000800003bbd46303456f70ab77a90aa15ea22f24f9cd10f3e57e4a1209b0550071cd06843230755f4d1849f4e981acffc1512ff15dab6aa52808052686157092fb841909a01283a64225760d7162ef733a943160c34d78bf49a12e8c915c3472dcb2a8d8500eebf97b0ee62d19c164476048c4b764a32430c609544ab635d03375e33637010001	\\xbc8c1728f83eae00fa3fb59cc771731f7be121956556e7b6244adbd4bdc5c40b59639224ad4899bae5bcb68400c40ced53e9aa2ee0f8dc34b1d2351c3647e10a	1659356030000000	1659960830000000	1723032830000000	1817640830000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
149	\\x4f8d7c40bff6197682e42e34d38c794eebb028e6d3e13e400aca5400f2ed8588470c71dbf4cf69b96c6bb204fa9df7fea75a1547708d6221be0a67ad10611cff	1	0	\\x0000000100000000008000039f116897aad46daccb87e7229ef09e72f974e691afb97f435f43acba6d59abf1b44cddef6813cdd6573dc003c6c5f075718653bb322497ffade02ab9e174a8315d1bc8b64d1bb3425091377e4e41b2b76b9837827c5ca9629861b27b27c0c0733ce2061c6829bdc349757acfa1dc8ebdaf8f2b73c3775369f39673e9bc387247010001	\\xf65f5abffe291d8839a16b92200614a23c03340f3b994661f11e94086cff9590636437613e6014b792db1fc247068afc47a8e17f16fbee150777319ec724a402	1666005530000000	1666610330000000	1729682330000000	1824290330000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
150	\\x4fc5e024fee39f5e91674ab18bed0e26d1a223a4e01d8e6ac9447655dbf4587f4164528f1e55110f4ec3c0ebcfcb26ab0b6d949e314bdb23e4bfa648a62f35d1	1	0	\\x000000010000000000800003a7ed957b0fa80fa360d7b78069d5dd224e9d4501397f97104153c980b30cca9398b9715bea958db3d0961ea697df2df8b2e6371b577b2c17fa1e9828d74913d8a3d42e1ef84705a21b46f33196f0348a1265281245eda1e2c26ee7e274e2d4b2f671cb2e45925beb14c359ca3040cb61e945ec55e3a160be0fac16c0812a4217010001	\\x02c8dedcffe98aa84eb35851623a315b992332a6c1710c73b9bdf4fe904cf54650bf243ec72b5cef9d867e07027be6dc5d8b6c21a397f26fee6270b6ded3950a	1668423530000000	1669028330000000	1732100330000000	1826708330000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
151	\\x52690fbc9e94b53ef2e687f51e554691e138ea6e92589f6ba6904cf39a94f3ca0410c6ccbb01d9c427205091bfa6665a98a5aed3b54c18f1eebace9ea150842d	1	0	\\x000000010000000000800003a197fa88ff7e680edd51a2377c782b402da463c1d647c8ddaf36e74e1bce7a8e61d622a6488eef82d57a765c6fd0fa04a00003a81247589a9f2182b3b3a510eb0589fcc0fb2e27c26762318042fe94590191ceba727a5b64a0407b1a85d00ffc0ff715a04c41bf80fcf21ffb6509ee4ee3f9e0a38b33ee8b98bdc46675dc812d010001	\\xb295564c4aeab2911c35fa511c7b716dc4b5d6f36ed7a4c57dc025d53ae490635e5aa2142b2719d77e4a067ec50d349bfeb617c28c9ec73f627cd2796c149504	1683536030000000	1684140830000000	1747212830000000	1841820830000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
152	\\x54d9df8dd053becaefe1cc09aab3d9544063b9940389a4178544fa62ed4479775b966d11eea7b89cbd871da872041f5eec46adaebccf536dab04ff741af68aa1	1	0	\\x000000010000000000800003cbd13f8cfdea58af624d695a49ec740175233cfc3dc04abfc7b5809627e1163fcdfc6e44963e0ac444fd10f7844ac1a4035d3e58f95865130236fc5c78f4dcc518321add73f0fd72a27e8c5a49bce6e2167324c1558a0854bde264caa35b9461dde38776172ad6eea57c167b11caf53e441ca6b0195243dceae046430df8fddb010001	\\x5f2bdb24e0e0baec1acd5079e763e6746178ce936c990042b5f6007ded9c5148ee44bc97d22b20dc4613b05a2394638948bf613a823b422cc23cd4264c098b09	1656938030000000	1657542830000000	1720614830000000	1815222830000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
153	\\x5731b78da5431e099a7f8f854ade2263472d21822933e6f8cf0a47c6f58d9ffcc2f7778e5502ab2889f395b8b8484ad331a011959a28d51a0c5df0edeadd6da2	1	0	\\x000000010000000000800003cee6711cce2e1f1cc0ead4e4f431f576a025316f99de6e633e4c5156f0f011a23400e1b139b6fe79090ec17374aa4e9659350f83eac9c973efe9f34e6d2bcf2d7236937e8996f98833184e0aa885aad08145c8e67d4ab26634169d7ee1d847bb88ba6ea8b5c8b8b6f4976c8168f62c40f9d215bb127f177185227a9df0eb47d7010001	\\xba78d10db7ecca9836af0dbf82ee83b2ce59013192c03be1f3cec5550257146451b4810c14c313e97f843d5e6e9c6e8a2a6d5afddc3404fa03b5b89ef08d7b03	1675677530000000	1676282330000000	1739354330000000	1833962330000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
154	\\x5e558897515aba01f361e842855c1d3f57fcdc22aff6123ee4c678c03dd6ea66d6c4a95c677d51dee50a9c0e2de1f1bf1f70c5ad5fb1c8b715452464340c3cb3	1	0	\\x000000010000000000800003b190bc5967ccbb54f3d1c9a9eb463c2d8c77dc8a345cb44853e0426bbf2e80c388e5be788c108e70468cb6bd8c46a9eef919491375dca1c8ad9e33079f186979adfc3aa42c0bd8dbe71b321fd58ca6cc9fd5aefc1f752ab477a8e80f39ed3409efa24a812fb7e9e08423c0219afe771c2770d7c4c5cb52306fabd6fa6950cb49010001	\\x6b6ce45e46b38fd18ffa86785e6a3f8af5e73a91b6ab6f4a165c66311bbaf3d453b8779c665dcbc72a672e7fe9fc96fefd1ea8999d9b4989e4d470eb1f770a05	1667214530000000	1667819330000000	1730891330000000	1825499330000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
155	\\x5fd18925655d58e44456159c50deb0d6113d8ad1d3293d5c30a6e50c6105fe487d38ba0aa9178ac04eb3fbdf9685d09916ba7da8c598b2adebaa4472eb0db6da	1	0	\\x000000010000000000800003ef758d2a9e23eb627e78e2356d1557e93c4dddc889375bafd0d18c4b8ca9c9444faca465b97233741bee49a8be9008c3321fff089571e01f70357c2af84ebaac3eb161a4ed1afd6462536ddb6ab7eb344ea1058bb204ee868c4ad162f93386b3941a0855218bf9111f54ea466ce5731220c9959092e2a1cac729fb91ea01925b010001	\\x8ea26b4c932b55f169585a412fab12c2a2cd72258cbdeb28b6dc7193337d97499e6a22c8d1052bb7fe23aa7d0682311548a738b9a44a48d6f70832f253b41a02	1658147030000000	1658751830000000	1721823830000000	1816431830000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
156	\\x5fed5b328b16659fe138727f44bad5a3ddccb5d59542e26d2fa32f1de1ff6962c53deed0bed8d3713e1c5acee365e84baf45f9ee047fca11010ca22b7446b454	1	0	\\x000000010000000000800003aff6bf58ea245a970bf38a21e34c738fcc6c7f0d1ce74414531f78b4ff9524b2c24894ff5d413e781d8676bfd40429aeb38389670786396fc26c5052fac242a844fdcd37494165908fa6d95e2fc969f69edfe27747958b2a4c9beede3c90c595475a17a34b84fb1fb2303fdb2d00297b91b0b5ab51ce2d4dc6409844bd0311d1010001	\\xbc3f71363224b2c6e49fa18499cbc2136fcb1e875ac121b7b2fa50be402f5f3003c28cbf39703d5187c34bd40160cf689f3777f6470f6ecc168fe6de91bdef00	1682327030000000	1682931830000000	1746003830000000	1840611830000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
157	\\x64456b71dd6104ad59cc750aa36bbfc0b20e307c57516e9a36bd7de38d8c8b0f91f0b51dae91d0e3f37187f744df571a75cf8ded16e8d934875effad54329224	1	0	\\x000000010000000000800003bc3387d40b7f16be4ec1cfd9766d9249638ca5da3a0b131bf8ec5c99b7e2b69efe3855b512f1c260927cb70980521c30c5c51647f992ee536c176bdfa743124e55331522bf6c4b46525907f58de9f43dd6686a96703491a672000f7134ec9161cad66d472029bb97510ae60142bd900d7b9f30c42e2f6354257ca294d1ec08ff010001	\\x7091d9377c48db5bc1e91f3caeb18af9329ce4ee8ece1c71d397d58365c172e165dd7b48c138229055b37742062c35085094f2e6619831651d74ed4e7fb6c908	1656333530000000	1656938330000000	1720010330000000	1814618330000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
158	\\x6cd9a05353730c9fde307d3c2f8c1e169c6537950a75fcd9e10938474f10f08c85e7baaab3a0eee9c29bf216ed022681759a0f4f2a0c7992c1f703dd2d7d829b	1	0	\\x000000010000000000800003d3c04d14c0b20149081635b9cb852219deb6078de4c063d01685601eeba65f430877393539fd8e6c2128b6ee72ad5f24dc2f0cc2eddf383c475bd303d9f9fc6a3a0296d4b8ea4a7bc718af2dcae8ace23b706aa73c0b486203c718df3cd3651ca057b27898b81f7d0f5fbdc70bfa8397f0dbc61faffddf1eae7c1b5963b13385010001	\\x1327fd15953a3af08b5fce6511ed3ec3f23f640b56d80898e95f65c1e34dc45c19286bf31e282145d7730a0b5b3f6a277488f17decf566553f243084457d4403	1678700030000000	1679304830000000	1742376830000000	1836984830000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
159	\\x6f35bd288ba139a7e81f08d3578008f66ef0384fe02b085c861ce53f7f9637703ef80789630badb9c64078917e0ccf8f634dbb4260c0a84936437dffda53fe56	1	0	\\x000000010000000000800003ad86a73515f4c4dfaddc4393f45bac97e9ffe1451cf151cb3170b99db8eac6099b69d0b9e93a765e1381a296d46019afdc9626f54b2da9dc45a9484d9c5cec841a625643abcce594934d86d2d38b43f5f636e6cf1ce51f6d9b5a0f66068aa9c3de3ffe3f0f7e1454da8f13614d26dc77353cc06a827078c64067ce456cf887e1010001	\\x2d75a3ab1f03014ecfef85e6195b73b867e3dadf87ad720b86acb62367f03009c458ccf807acf7be7153bf964f497a9eec32a58a689cf42a70c24e9c38748e06	1674468530000000	1675073330000000	1738145330000000	1832753330000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
160	\\x6fb5da28e4b5ef867a332d493b51bb4ed15e39bffa787a9b191588c822eb028395cb090d19fc96318f62ae4faab6970efbe011328af440a65513ee45d1fd722c	1	0	\\x000000010000000000800003c3650ecdfc1f05081c4a81e27d409a3e8ee80bf1cf069288b877dd8401884a199e33e41b5d811bfa4627695b2ca850c94e7725d8947eb4d749f7d35bc4ae06ffd60a154760a99e94fc9eccebc4de535a7d8f7e8196ffa04ff676ffdf7194fc3ed0b682dc5f45458ca3725d3a58efe261435b844dc39eabe9d7072998336c70cb010001	\\x51c549628be39e54fac236bbaadeaac0542f76283d3250e1c116cccd4b250269d684a0308c6b06550eac29fa664307adcce92e83f6bba8f6fedc5328fc24ba06	1660565030000000	1661169830000000	1724241830000000	1818849830000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
161	\\x70b5612ff52f3df389efba4bc7475e4c942e634c8dedf54ce618ba0331a119a9a05ef8efc5d9a565e0444033217f476fa6ead9e0687b41782dcd56c500bdd3e0	1	0	\\x000000010000000000800003b6ea196c603a34a084c2d75bd5cd0cd722c133b47a049af247eb5e7a5adf42d27a20182d2a987fb032c92d3f005a0469f8c87474b56fb7e1d7eb65b6cf3cd9d9399a6edad789e2b3f0035f55d03cf0b9f6744cf04191a6aa0f2e86add74e832b28cb906183f2afea869a0c3dc250316e8a19cdc95ca0a1fa5bcdcc2cee9d7891010001	\\xf224bf61eb115a3b6bfe65d4abb9db459453b5558bb40780263070719bf6eb5be5dc34cc528b5f7c5933c2ef9bcff80d41c25121be96db2d3eff957427c7b903	1673259530000000	1673864330000000	1736936330000000	1831544330000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
162	\\x71adcc2334e65582976c2ac0454c2daa0f8fefceb72a60aef6697d18ad3ad1f126010964c03dfd40d58ca321239693a27b936eb168f6b3478ac74e85061b0876	1	0	\\x000000010000000000800003e75abdd11c65dcc1d7f2fde9bb42ca2bd082b16517ba2486cf5fa3776af6215b50005fd12b1999d4c34f06fa109eb9237e94a999b4231e7b46c3ec025d96f914ff654c23cb9d56dec4af123f283d6a542d279625c0c522180461ce5008b85cef709fc19c5736d084077fd54170c01efde8f77d94cd02af087b1a2404adaaea5d010001	\\xd0a156c15e2314f22e552a9b94550e364f08e16492a646ebe98cbba9fbf0ef67ba27ef5694e72b791df9a1e5d921fb69c00cb62fe4bdbe8be26930dd42870e0b	1686558530000000	1687163330000000	1750235330000000	1844843330000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
163	\\x7381bcf21e98b975fa7cf1b9465b9fab973ba340bd19d498c4f7fb845a6534cf251ff888e03d5226e7498de992fdba74b6cfe705560c15477ab385800b7a9d43	1	0	\\x000000010000000000800003972c53523d1b2fec2a4a456b6d0b305ea98f0ae1fd92852b0b240fb1951f43e7c2675910050d665107553cdbbe7804fddb483111f519b5b3127e2ca8d89ae4a399f20fb49bf1a2726ba6066f84b3611481bdfdb64cc8354ce798e0b3b535fdb0b2468a5aef6c227412525883f0ac337147946724382aace521531c0cdd4a8c61010001	\\xf5dcc9961c083394567615d33b436dc722e4d77c9d9ae02348831b02bb3c0753dcd5d899ddbf02ff63ecb7669d2f856e5be6caedfc84c2f89de835342e1e3809	1675073030000000	1675677830000000	1738749830000000	1833357830000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
164	\\x77fd82de1cd0a7affccc280946f28a467e747a29a50a3713c18ec9f32ea9cb721d582cbedc04eff0158a9084c4b4e2b7a26c6a30c8053e23fbefa36a310d98f2	1	0	\\x000000010000000000800003ea054b2896465ac71aa7705e8583180a7e7d0802aad4a4cf8af253932ae35b4cf0a8c1d542115d271a9f16d2907cd17deb740ece38958af617f9e03696464b58149206f4b0ac1f8fd1a73ad16f58093957d7371b81828d8571d32cd979e4977b8c23285aaf68b1dc9fd8cbf6b49f182d89b11d1bf2a4c73d49980b66ee8fcf91010001	\\x11cec4b41990ebe2269c9721992ef51499fd51fac5cea3e884baa4bd3111738c0a1cb48201761e64ecbf308a2623156424682d81de09f936ab14570b603cc00a	1672655030000000	1673259830000000	1736331830000000	1830939830000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
165	\\x79c9fb29d54c4b2cd47163093f295acedbd86583ee0d9c742ff2ae6d288bd6cc44955268afad7dcad8d8232a21da4e5dd67ec0d23a84c58cb68d4cd06314d67a	1	0	\\x000000010000000000800003e56c404e53f1e60d02fa48c2ad9496ef8880cf139f0b338397808667914e5cf0b930eb545b471a969cf178501c0dada407386402f9a31fc6bc95ac7645fb1acde7a81d67f3683a457c56ebab9a3734fdadb3c59f6f70f1f9a8d39cb087c61be9e3921ce798674d176c8580f3d2ae96ce4c1d38a15ff6f177333671d434aed22f010001	\\xbe7ad0e1c98b321c5a99c10b17f615a021a48408f1efb78561b4256818661403b54019d52d44d58798bece3fda6d366834291b481220cf3316b02bf1ac832f0b	1678095530000000	1678700330000000	1741772330000000	1836380330000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
166	\\x7d95277effbbd0f66c8ed7ee8fadfe60140504a2dbb73782db9e3f00c95e109f0945331d3727d9bc553c9bd2487762e62d8bb3aab51cb659400992900085fc18	1	0	\\x000000010000000000800003c9c87a6c23d9107b50d564b4ccb048c61b6ffdb6c942192cf50a4d6b4354638ba5a965279ecdcf380c888965ef5d5272ac1e46f538a2ae41038c21f08b3e56c03069b25b641a702de4de1dbb23f8817a77a3fb05cfc9a39f9ca3e4baae2f8dd0e8ef6f84eabe812bf194a56c0511c7b773c23f92f51cf2b2acfd97b8fc75ff59010001	\\x055e44b604508bd6703c965d942e82e8f79bf20889673390fa5f679d3b41de6ee646c2bfc6fa526aa80428290829f0c272ca3c78d48355bd43c4f17e155f7103	1664796530000000	1665401330000000	1728473330000000	1823081330000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
167	\\x7d29bed6288b7519a51178ea71e280b0921eb954657b8446885228ead4a1576a07bf7d8e1e8720804f117af87472084876cb95304f3af05c52573508b3821870	1	0	\\x000000010000000000800003cecf440fe6ae96bb21e7d0558ec69bf22f0ea15ae473e0958d3f51456662e95abfbad0054feaaf583447e8cc798b3f37831f91680b09ad74585e452e063dd5fdab3bd48600ca537eedcce02fa08e5cb8ebb102e46513055405413fce1362703bd7ab6c929b35a7da9a138c98e765178a289b0f0e7a0cdad74c1d9846eab27bbd010001	\\x74210f67bc25c5a0e794583710bab5e40dd37ab701cde68a28c30b24066a0cc0a30b25f5deb0e93f1364d1091e3cba79778c64bd8a947c8cbc4212a73f34a40e	1682327030000000	1682931830000000	1746003830000000	1840611830000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
168	\\x7e850483ca31eba771deab578a832121ff66b2418eee37dee4311e282b11a1663f9daba6a04905fd44c20286dd44699078ab6059d76897eb1b7e1f6bdefacd2f	1	0	\\x000000010000000000800003c6d91f4aeccdf79327a237e7817bb9047e0c4307604455350ffacf436daf3032c96b2f10cd76ea8ea254ea7e645dbded38a17282f1e5457347c72a888d15a77ab412d422d732d2d92fbd79262d208e77661be61ddc0f2e0f8398f16efd61806a018f02581f3a4631becfc973fa9197f324fd1734ec5677c1b9e12f9274b7ccbb010001	\\x06d77869c406dc4cff59c67f35947b8acf8535a3f7e9f94a380e9e95db6e0e8caf7fa9f7d6ec0a1cf0e0191a2fe5b42abfdebce864a446791cb1cb129801d003	1680513530000000	1681118330000000	1744190330000000	1838798330000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
169	\\x80f18a64de67e7a0ac045270e2f585f2f2491d32ccc8aa13028e8806b2052c9edbd415f1f3c73a723b5a400d4730eeb3d9abd009ff53b1672ebeb91fed70a2aa	1	0	\\x000000010000000000800003b3d246060eefdbfc9b06391f35986454c4c85f163d679163d9385fcd957198d5e5a12f2a5b6f2f7d8106bbb0832adf5dd5b92eeb551debab7a961056563fe4fa863f03e42f993a3de6b9c0f0266e2191a4940b2327f5771dc0b99e7254c716405a602ae39c70be6799a770f410a239adac08aa5a5a16ee4aef5862610d0d87b3010001	\\x3b85db0cb8fede47a5a17d1ef25c397f90682b583c13030386bc0f2764e0cdc9b0fc311318d3d0052ee6dea28ae2785c934b0396308570803c2f23df8a19a705	1656938030000000	1657542830000000	1720614830000000	1815222830000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
170	\\x8261ec54e34e58ba49c839534ffbf1fc45ca04e5e379619e3517d67cf05dde6429692fee4c8d36daad8981d63d6fc151130c5e3d3048fde5f15c6d26ee92f713	1	0	\\x000000010000000000800003b55487de06e14008a26b7cf98b71f461cdf6ded4f7778a399da510b5050f9f3431ca70475e3ff8fc228fbea579ef88e40c0fa477889f4c49072c3ba8fca993e0d92e0c9c23db5e90c16a04818580ff8d22ab4ed47c9d1df7e9a2d3b6e156d90192aa58f3c182331902edf895749e20e25d7e09e26152637cce201c06e44fbdbb010001	\\x9c78e237f76e045954e59c6c21d8ae51054bb463023c05e090a37d65cb0ec7f085233a3f4a03be08d7f6d7e4f92ad442530d4d633ef123106bdd6fbcc46ea50d	1658147030000000	1658751830000000	1721823830000000	1816431830000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
171	\\x8375fdbc57edc11bed9cda7a0ddd4a1670fc91aefa1385f7846c68b89575ab74df5fdedbb8883ea378eec43342ded33897e7505f793d7d4111811245f317ef95	1	0	\\x000000010000000000800003c298bc2625d017786c412957c5032a88b6b8236737ee50e6720989e252e098400ec37452ccd7ecfe8de4824defb71d661e5dcdda59b6977565426ffd6f9c0ab9918adbff1fd8d68e0ad80da5b098ea14823dc82d95176eb59a7311a12a0bd56e008053b94bad67e5f28419289a40a575dbe57e7c77774dd5734b2aebc280e1a1010001	\\x8475bdd0ae386fa73948faf29c6dd2f5b552e60b2f1102d66522bf74fd0162b5fcce07ac1020dbaab82a29fec985efc904093db67d4ff0abb845b9af1452f50b	1658751530000000	1659356330000000	1722428330000000	1817036330000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
172	\\x85496812a25861211acaf1476a8a08504c643577b05aa7dce28d58a5e98a104a3e1021c72b03ae87b31103233790a96ddf80e4b89fae142cb0d2eb0da63e7be1	1	0	\\x000000010000000000800003c3a5dfa8cb53796e591f1616f287d97d5b1e2382a960b39564e4124bac256c2640523f725e8633e21bb16f1427b2e21f52dd1b9052ffe40cce2db290a772da6cab230ec781c153b1e116db6c1b08516628b7e70a867599094e0757510e63a59dabfd608054639d08f7bc52d9346b5f698ec28363071a79220dfe85bece1edb31010001	\\x11827915d1c97e12cf197e54496dd9e07f0151181a732b53713e05406f0fcb1f47132ab54dab0c70dd6db006150df94d9b18be156ab34314b180a15e6025ec0f	1684745030000000	1685349830000000	1748421830000000	1843029830000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
173	\\x86052484221bdb69630516f0934c9e04811b791536c481819ea0fbcf8728a26a064bda65692b09ce7ae6e75ac31e219619a75fbaf8d59117bb1b7b6312e96804	1	0	\\x000000010000000000800003ae168bcdf721cf2f5f696c6b35eab657f3a91e2824ca944791054006c78262e676c1b9f44253f957735f3d39a52b1ed972d7cbf61cfd14a26e15476860a09fd8370f1119a2b8d0a33131717d02e2c90391c849512df9719f76a3f1c00e80b90af346ef52bc11705d8c6305420a08d0aeadd27502e913dc1c00da2fa3cab03aab010001	\\xd6145919fc4cd60aa57b40e24281e60a7b547118e42646defe63db7fafdd28c11e1c599733c7c98dc20f09ab7ecd026007fb45256624fa70d356f6781e55d004	1673259530000000	1673864330000000	1736936330000000	1831544330000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
174	\\x89fd8b78ea6a9769695fd9421f7ca74dd79673e42a8f233f79cf73bfa07fc762a78cac3cb20d86e53b1ee7dc3905d233498ac797003f50812795a3b4ce5d19e2	1	0	\\x000000010000000000800003e0ead2b8563039ef99a2c3636c1526ddf486273a717926ca809fbd268560aa470bba180cbf3d89035559848d20328fec7d9770bcf64fcacf7cfc2ce0e9792e34c970f0e408458b8c3e436d48e57860c05d4f5c9f0e7f4d6b8bbffa58c6dc86146b74d7157a1564effcbc3fd8a6d0ae0f4e73cbc7f3c5ddc381f53324f38a9bf9010001	\\x449c7c8c01bb31205d38b057100b01779af9bbd47200cf3192b42f528fd394656d761530b62af499de8ba5fbb0c6f465668c8c9cc8988b99437995c5cbf68705	1684140530000000	1684745330000000	1747817330000000	1842425330000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
175	\\x8b0d9078ba7437eeec9ec30ce1cf1bfe17c50363945e6da74863561296c1f279293ef70df873f68a47da32fc7d548a8c2397b32aa9dbe5ee7b516da33f0c9dcb	1	0	\\x000000010000000000800003cd29255674b744f119d6d42bc3fa3ef82967c623ec8f385a100bfdc0237afd4dbabc4632d4aa4828365059bd3cdfbd7653a25036b39311d8bc77cf32317b64a2f4d16fbcbf49456901340f20f17b939a7fe90a41f3571203c2b9b512215f89c910b03406238197627a454a1e7bbe1ab511a4b11a85b9cdbb9e825f374248426d010001	\\x453174818cfeb34dbfd8d82bdcb427d951c068148c94514e30f6430002ef86e64291a4c4dedf674ce6f1eef1707be773b107d0dab7a51f191a13b6746790310e	1660565030000000	1661169830000000	1724241830000000	1818849830000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
176	\\x8b05fbe9707b3833518f262a40c939f9288b7051071e5ecd8f52c0fd98676667bb4bc88a96dc505633ab395afd830fa4394cdef9eaec651d71f3df15c978a1bb	1	0	\\x000000010000000000800003df2b9baeb6ae9fbfc43c7de088e4ec09a0bfc04b2bb61ab61686f41c7f3de32839c4a34210911b8986a8e763ba0d973943920453a5072af7310152db8a13e0813dd2e8e4015d81c1a6a1b4753b282f9a8f08ab51deaf8238050efa5ef876f459b04b0aa9d68c720ddef8621a83b5bea8c108df67a6b74b358b7702684e367177010001	\\x2f9cd1027ba972f14a4be61d499588eb6a3a5c104d74b3ee2b7d6f12779de54135267e01c1aa9b2ce87d6e6f22eec8682ff6854023521746624621efdac6c40a	1673259530000000	1673864330000000	1736936330000000	1831544330000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
177	\\x8b912f0e7b08ee355dff8466f339068e3785e3623a216522bd90b654503e0243ea88e7ab310ae5301321cd5dc8de9b534491a96a44a8a52ca39f6046ae90c056	1	0	\\x000000010000000000800003d80f7c83da2d0f467cb3662c08bb9b72e0837f964b137e3fd4ca04fb57e3727f902106eaa32def0e498c0f8f1cd91d1cc2a1fbf640252ff9b2ab2a8fe1062bbe24c432c10091de72ffcbe845f06101fca81a7b4c4f4119b77f20dd6ce8782359f03429186475abf0738573711bd3a2f8ebc8358362bbc890bcb2468713491a0d010001	\\xe0db4e52e55acec92f091fec55fcf91c2889b14203f1de71903a17f646b258c9fac5161c5390b00f280640896cd7f05302818c8c81e081f7b8e810423ef46408	1655124530000000	1655729330000000	1718801330000000	1813409330000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
178	\\x8dc5d470d826a9f738b1ff9a7deebe4ff93ac0ed64f32e8c7e66ab1d5d694b9b8613bb14e378477bb4e5dfe52964ce641fce353796eb6d76fa221272329bb9c7	1	0	\\x000000010000000000800003ac6e471f994b81c056d0d3474d9a57461985820de9f5a7a958e26645623d8ab91d227ea06177810b3390f4a90e7bb9f4b52b355ae8feb71decb9a74db974637c5ff5c44c7e2c2214f6f50d8aaf89e2ab518febab76b946a4ea9ebc5cf0c84452403eb3e64eb1585e7c16d8369971a9f9744f79c2c3fc42c9ff5edf84c0c4fd1d010001	\\x58bce85d1f19503d76b5321a7318ec31063f6fe6fe7c8c2c3640db15c1d088ea9fd30d0b581db4118db458ab59b2afee0434469e779560cef963fcb2a327fc0c	1676282030000000	1676886830000000	1739958830000000	1834566830000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
179	\\x8e45383aa12f3d4be93b8aa2e4140731b3a7303043634c68e25daeb8c9eb52c086caff6c4e4b349c24b8a9de274560185f07701757e678c051487c2c297b745e	1	0	\\x000000010000000000800003c440281435c9083c7b7c888efcf335220bdbcbc4551d39957bc0fb34bd30200fe545af611f86b188cef2abf4fa77fb847d1a917e196dc6cf13de5c2ff01a14b596dfbb42b09ee65dfa9925a3bb9dc7799da4cb1ca42473b68539ae0faf6b3903eee041db534bc3ea151d72b7a67b744a7b093ba9bbb881de26bf6fc356f5d143010001	\\x5ce8f4c6eefd8ace7e27a6fe09f46e1155914375782ab56689547a637f82c4524ec4696dffc91e5547b9678e04e11b027c8aaebcab39b583c00ee00aaec0620d	1655124530000000	1655729330000000	1718801330000000	1813409330000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
180	\\x8e1dc354f6607248792c90d7b34cedc3c6a7aa60c39bac013bb54c0bcb0b52e78903c33489be05dd61e29a3384dd192a6826212dafd788e215ff980f843c5079	1	0	\\x000000010000000000800003d98c38b99700ca3bff5693aa84ea3d4517505a8ea3acbeefa5abb7ae2a183da3072195e00b79804b0f7b70ea57a56b62e32e044b7e81f41f5e94f044418b9ddb94a15408dd046278265e026a470c42ae2f1de180f9e3775af0a7c112ad5ee998c04e5fc37d937014916c8de4b5e0fcca61ea98cc8ae4b46c08d44dcf45d587b1010001	\\x84a46528699dd93814a021344aab47a0a982ad34c1e2535a0b363187696fd69ebf3949fa47e95f59c63ee94b9c577b2d99060fc90e523df3b9cc08d75bedb60d	1667819030000000	1668423830000000	1731495830000000	1826103830000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
181	\\x8f29dcfdc66cbecd79afe1eff3d40675e3cae55ade336d60ec4b8f36901dbe296776ac9ade1d06b8b2ae1ef4303992890d11165143b118c43d6dd33b71debbb0	1	0	\\x000000010000000000800003ce83d3800ce3dae713bdd65a776715c51ad705994282889187984e97926222e7699d4bde2fd76e486c4f0dae5264c4ffb8d61c9a4b8c89e86168a982d11a0b7798300a74b31b77f7ea6bdcd4013409535da11ec31b40a3b0d736bb699e0a38f986fe613d7386300c1a3a2e0ce37453ebe0333f3745b914381da9813086e7971b010001	\\x9d682910b8e9f78b836a54ccb309b27c73fd57f85633aae9c8216c9bf7908e474b5da4ceb6d8f4d5e3c843ec555c8ec37a8620e9f235042556ccd6a27d367608	1659356030000000	1659960830000000	1723032830000000	1817640830000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
182	\\x90c5c1c4fde4fd08456351328e0ce81ea60d5f9ecb99c209d9dd1c41f10fd5078a81dda11306a918b9c7a6f747baee33bd2e346624d9ad18da9b0c7846d5e029	1	0	\\x000000010000000000800003aa2f4a023febba762aff998bf03d569bee5263c36be032fd91898c817da2391a92daa60ab420525984a9021b13b0bf61991097fb2cdbbc9648ff26ed2027d153bc25fb1db6139f40c1f52daa625e1c47001d54920ac7035dde0d39d0d8027dcc00608579de5e2dbf695b4070d0871e5b4160c0bc6e0909d428226f2445fb505f010001	\\x38ee1b3ab7893eafa06bd20fcb2f18c7c4650ddb20f8c80e092dd23bb5fbb1c88a1d520112a41af7b97cdc82d1c717f98cccd751a240a21e812e3362df00240a	1659356030000000	1659960830000000	1723032830000000	1817640830000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
183	\\x9209b6176ea75f4c4031971fed0ecf6d8f9e7c9f5f6243c8c74fde3c47042f15b4f368822aae9115e691bf60af6916753cb04472e1186d3a151d2298e2521beb	1	0	\\x000000010000000000800003b90f13406fb89583ff4a95e29abc9156baba8fd2674b558bcc8387306aba812645fd4490350a7d8d0158552e0e9094dc3e4b6d2a330c32b2b7ca3bf90a424534a90075e075cfdbf1d7db593856c4ad8f8cb97312eae785d26f7d19ffeb6301b2d212bb7ccc1d3ab037c814f1f18256c92bce0b4dc9ae4c0f5d7a1cf8938b4039010001	\\x8f159c92a1b0614ebaaeb700914ed0af7f2507e8e76d952990bc261a18a6ea4a56dd6ff48ab4e22d48b4673d96dc0a2816b569befa8901d22e6634133921bb00	1674468530000000	1675073330000000	1738145330000000	1832753330000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
184	\\xa789b8d88fc7f76ef5ce7acb445cc54b443e4d192d6ea99a0d26c645686252573c8ee674749b199c93823cb80746dfd2d6e6ea7cf131128eba95cbc05619a16a	1	0	\\x000000010000000000800003c3be752fd1eb8d9d42928699baa792796c959f1552071cf53808ffb216a045b5a89c0f165253caba46f8666cff3a45bc018ba8825a127f8bc6a8ec8217f9bf34685e7b23627d08cdcea6f683b1991db09fc8ddc7f0572e76bf2725a39c04897385c97837cd49fc07c387a994a9d6ae34d649c9ba8551e792c58db7a091256d2b010001	\\xffe914dfad2fa791f41fdb96d3fd9e6254c3e06345b28fffb2168ae8d79006ebeb219dabb0c877cb52f1cf749402582bb6cf6f5512cab539280aecf51e490303	1674468530000000	1675073330000000	1738145330000000	1832753330000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
185	\\xa849465f7fbd4990498f8573fe49ecc99cc2410ebb7f4abd89dd35bbc8b85e9cd4eff52384f328fb4793979323743dfbb5fc9667b6b45ce0a1c62b5b9bc2f6d3	1	0	\\x000000010000000000800003dbd9c03749bd97426718b15af8a9fadf8d08d4cf95a46e3a14b32193d20c00128bd712da088f0cde069511e02fafb34399eea0a74efaf57ac6deaaed77c8b6e850a76c7024a9ac57081c0d11d47cc67ed95a648f47be349efcd910472ae28eb63a064f7c25fb1b89f0ce808b078e01d584fd7dc227128e32216b28e99b3c3d57010001	\\xfeb2621fa8d1429f1586955aa92a9a3865733bb9c445e005b6ecffa90b7fc2cc5c5f4ee256c2115184f98b8fc39d176b0201802b4a3f4a3699367260df49340f	1663587530000000	1664192330000000	1727264330000000	1821872330000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
186	\\xa949e210437000b06f78fd5a49f6665f4bebbd2b104c606df6c9cc702526f6a93af692b717cefaa9903235a1d5628377de04e77f49531e664833596d9696e870	1	0	\\x000000010000000000800003b02fe3166841ec0aadf97cc780b178601cd53ef51b1046681f218c510eea32ff48f72ea8590402ee16cd4b8ccbc3c1dd73189abf35653b6d54dd3547798c3ee788d1b7e57939abc625a8271843b1ef929b17cd9afeb3df4d21471144cdf1304f027c7d88a52f3d54b39b4a1e6c3b312d755cce3859e863dcc75a63438f6b153f010001	\\xd8777ea405d7321a21770c74e2b1a6732d499ac1aa0d2231d041cba35a0339abe2cd22c304f2a1d4e44bef0262e2907b713a864b80eae8ffbb44863222c54a07	1679909030000000	1680513830000000	1743585830000000	1838193830000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
187	\\xab350335ad1ae41b8c103cfe6d038c8dc1feb65a450bfdf9e2888199ccc9af2e0c4f4b1bbe807ee3fc680e81bc724cdca10de1c00a92eb8ceb9a6e6a661f43f2	1	0	\\x000000010000000000800003d090ada1a9fbc7e1e3ee339be20c1d7c200a32e770d9b9ade64ba57001b35c91afda3dc416ebeb0cb95ec0163b7e9892aeed0efa24f1c35e985882052020fee910eb63222067088f937cea64f20dec50411638e178d0cb251bba8e101dd56ece8e84a09277f1d89faa1329162356ff50baf007cac2188f67e485d321ad3c29e3010001	\\x44838187dee03571dfeac9f9e9c5b3ef03894539974a662e1e3845f7ace5f4c66a290aa77a5e82bd193ae9fc91cb47852d1beca914e789f596820c78a157470c	1682327030000000	1682931830000000	1746003830000000	1840611830000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
188	\\xacf512d7bccea2be2a036f308da1b3afe2674c294fbe2f7c4ab0b5ff836270435dde6181a98c7783a631bbf99835205d37c5e91e556932a0db9684cb6a4466ff	1	0	\\x000000010000000000800003be9593a8a8d30bf25f91e4100e08c58865d64888b43eacba9c2473cc4310b9add17b25028f2f438ac36aa173a8807ae1587e83ab677d33260b5b4efe6aefae0fb379d114c03b962f2055c87cbcab62ba02cd6f046f05e9c5edd3518e03f3f622590a6462bc9d7ea13a151d4a8ec9961ad0071949fd0fd2ea38659f33b50c7719010001	\\xde45cd1b76ff26fcf2f19f86d0275d6500ce61c8ff3e03ea1cf5ec0cb3e6d36e1f25ef5f589e63d070aadddd5f23f454465c07ab2a8e242387e17979db353c0e	1678700030000000	1679304830000000	1742376830000000	1836984830000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
189	\\xad395c74dee0ea1fdb1a0ae34f231631cb28303753a5a0e1021b6c9447cc17e423979bc5803f570331f5b720d28be6d5a470a7bacb712e32b15d743fc735e7d6	1	0	\\x000000010000000000800003c0f6fc1f6463feb579cda1197578504c04bf15fa174d3b2cb257b109fb7c2e32c6edbab231c2de661c92ed73f006dd0faa115f4dcdba0c9e9654c9aa7f6d7662e24feb9c4861b7d4cb255332fc62934d7365b1446d37cf653a7e60ab88ca2a1f435e47acf989557730641f53201b4e0390771b58d50512ecd7bf1b1ed8f918fb010001	\\x87b16866de3122dff1e59f505694bbbc447858f4a957ec1b1c99ced30c07c8e3069213e3911237d39d0de2260a93f831e0832e3424a01e4ac7d5b65a5ddce00d	1658751530000000	1659356330000000	1722428330000000	1817036330000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
190	\\xae717ab883d3214ccbc3efdbd198c487d571c118a1094a8b8af7a62fd224a598c466c3dd3f6a469573aeb9346623423120b2785543da455b4dfd42646fe450a4	1	0	\\x000000010000000000800003c09096441bc881bac1f8a1095c04acd6d6445186983f0996a19d19eb66d4212a8068ceb180e67091646b168f153c6a8ea0cf3112c360dd596181c28a614b9da2ffd908a0118826966fd427dc600cd7ce6524259f4a652ff8e502dd9009e1d5526796d5ecaab857ff6f21c05cde6a694c259d840c653dc5d1ff727104575a81df010001	\\x1b4a656cbb9b6a938137eb9dfedce9411fb6ef0fdca8ca5f23cd9e44ba5792fd46fc543a67fb9edda2e45b012af659f90307d2bb705921f3f0153063275af008	1682327030000000	1682931830000000	1746003830000000	1840611830000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
191	\\xb0157b89c7542748fb51082e3ef0fee59cb2caeba011aa111de741008a7899d9709d212e329de4ae277ecbd98513f978f6c3f390d689817ec5279e695a30d0e9	1	0	\\x000000010000000000800003d02b0eae0c265cd3b5fae982517bbfdf6c9b0a97ec07af88078003cfe6264bdd637b29dd1957dddd9c01ad7cbf26fd9511e5ba61932e9fac3a519be377031fe5aed11ff02f3377804548dbb33da0be994b7a28c557cd2089376a7fce3b3f6a1e8b15b2ff8708d71239ff7727872d5f3de6344c5aae04c6599d8e0ee117b63869010001	\\xd58df8b5d638686a9ddf23811e5e5e45e7d53beaf5caff5e528e3a327bea01dba56bd6f6487e3469b26f1c76cfa2fde0229eb00cd44b7f53dc2232ccdcd4a806	1655124530000000	1655729330000000	1718801330000000	1813409330000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
192	\\xb0b957db7b441ae9e75d1b1e94af3e24fae18eea65d714718c094d56ce4ae9141365d0ac963dad3b1399d26db72dfc1e5bc7315e434b488d08f95d2ff4a3aeef	1	0	\\x000000010000000000800003aeb022d6c691a7680c20f66a471edc40ce7908c189591bb987bfba8f34de42a0b61eadd5c99b9711374e0bb7715da4a9c616e7a76dd0457ee8d3793b1844ff5b2def6192c69ad9b819d79050773eecd8200d46af3e298b3679f20dfcc321960e0aa59f3cc5ec4735fc611e9a00f9436274233a96cbeffa55b831d89bbac06cfb010001	\\xad4f00f6aa2dcbc3693f28e6d2fb24e355c7a67aef3338caf0ad9fa0bb096ea93982137d8f703335c7716d9ee081dfc5fcf43d7dd84f99641dd092b9f2332e04	1681118030000000	1681722830000000	1744794830000000	1839402830000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
193	\\xbd1120cd8d320df238b61bc5c47c8b0d24dcbcd2c12f95c3e4c45a4f736dafb1a7af94930d26140c80233133e374b71bd20ac6d07c8bc85b34613cbd6d92aba9	1	0	\\x000000010000000000800003c36e717a9060c28e0d00b559c1de7dbfcf839ea17e35ebb112d32cc7ce5c3cee4cf3edcb391ca0a1c7cebc497bfc4a9f475cbed6d4f535c770509c99f1e19b223b8f7161fb08f2301113cc7889c56709e2e8def3c079ea56d1471ae2a7c99fc232be62a7ee6e17caf43f7e16363d0c04ddd64101719c170a42d36fd87e1bc89d010001	\\xda6986edfe9ea622fa2704e0b5a152288d238d4afaf84d7675574bd3db72c051b83a02f5bdc60eea355d9d22235d65da399bc312f111afd2323101b4a29d640f	1676282030000000	1676886830000000	1739958830000000	1834566830000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
194	\\xc715aea9793b9ab1f1cedb60925f8ee4d17e68ab96a64c570daf6014a8cb05193f32f1205a888b9a980f165fae741c4a27b2335605b395492f1c6727b6fb25b3	1	0	\\x000000010000000000800003b3b6603b1dd11cf22ca509ebf922d1c0793b390b6b49efdbbc629080ad1a700d25b857b0b9274ac07b42641b781e02b4bb5fea1ac15e07992cf0a3122215ddbb6f7e202cc604fffc8cb7f3fd65d8f150a67f1d77b92e8742906f7b139670772ef732827733597b7fa8181651e328e0b40dad24cb23e6434e82ac2946d9e5b885010001	\\xcfb88870906e26cb17d926db2d3bd359ad55558b9a09f2c0a6beb2e611a19cfd9b3599574544c0fe41d0c3388ce337e9eb97f190a2759877a0051c9aa6277d01	1680513530000000	1681118330000000	1744190330000000	1838798330000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
195	\\xc8813453c4d0ece968f5282db6943d8df9a26fc914346b2550ceff4ffeab2e73521dfeb7edbd198758deae88605e0503e787b7475cbd98a1c3f39a4fe195d2ad	1	0	\\x000000010000000000800003c3879cfeabdbdc071f21aa22e1b6f6067184a47bf3fd8a439cf306178069e8af03b6ad0a07f4b2551151c37cc7945da674c16a958a389d98db4d449b67386f3fb0be903a87a46eb1fc48a428a5b284f4536e93899706a74f261eb3941b5d168e132741ab4286772cb51224276c43d6ec2449bd903f5c0898a57581d972cbe215010001	\\xe6d6f6c703fb3be95d1e7ea543312a94ea042542e17dce94130fe74c791d91aa033826e0f9ff4deafe6ee071ded64e106d26cacfac573563dfa786ebacc9e00a	1656333530000000	1656938330000000	1720010330000000	1814618330000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
196	\\xcd1d05580f17b7c720b1ab8b392dddb8de3d6283f04d7a158bcea4f4012f3cb4b771a455ced97b472b36ab4052221a33c05f7a23375501f63ef6eca8ce7ad6b5	1	0	\\x000000010000000000800003c3dfb3fb0b1795af07e94777428fe606eaaf8b510e829f2d0e57f7460d847f31484addff432946a25d98a9a5a7cb5645d83fda0c2e1edb369e2f763f637b08cb5ddca3a248323a88cc2d79d4132bc79de292d3b1242f6f11278600c4a3132be507166543fee82b20391e30b4bca8645ede4a167bfd88c33ce52e9e899d78d2e7010001	\\x2a8c058a6b8bfb59a140154b6e503cb4bc01fcb07cb5f40c5624912b3acb14bb41e95f229a8cddde0dcdef795327b3ef0a618318423093f7cdd80ce574f81103	1673864030000000	1674468830000000	1737540830000000	1832148830000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
197	\\xd25d813fce41b70c367d28f3c5a37807b080907e7d962aa5df61804b07bfa5c1ea3a882d0b82b26b37fc12e19ac431f135b7767c9fd1b4400b11d0621cbb1cd0	1	0	\\x000000010000000000800003e42e8c5b109e6f33875ff74d356212a9730db8664df18a3bfd50db0889dd14dd57d96c989e964f4983f808bb3d3c68435327784b52e683536500c3e2c4bfe3986675d6b52ec89af65a4a0db0627bb94e038e5ed1d86be6b4a6524d11fd0e574a9c8860679f0f647ddf4dea896d659d179bb85147fb4fb636804b2b472d4c4e85010001	\\x12c8ef93202b5332232829dabe19234de4420e42e8433e347ad897c4bf14ee99f0efdb01276b0643bcdc9bd01539fd5f04575aeb9e31b66f682bacc131ff9b03	1658751530000000	1659356330000000	1722428330000000	1817036330000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
198	\\xd32d3e150137fc02003b38dd6a03188a132d2bedc7318b4e051e175e5d317fc37c44b7c5bdb82ab047ecf3f5d9a971b21bf5c339291018b1b6f15ed3c263a4cf	1	0	\\x000000010000000000800003da4d43eb27941dbaca92351ccb289231ade06c14118c306ac185516a56371144a92468724647fdea10e2392b2d72870504ed7a93de35e6840b6747d3e78b7da3da257d1c2aaf5f0587e58a764695f189b00785655bf9db12277cff4d422e80638c33f74884d794d5c82b3ec660b3292809dd543ae96a2793b35937a2a4cfc27b010001	\\x0b824412b2b0f260c925672de0c3050bef49e863e98ca47c57a57ade00cde078cefab3d79bddffc8cef91b28e0fd44056e1b71cb8bb3a8b8dbed96341128d200	1674468530000000	1675073330000000	1738145330000000	1832753330000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
199	\\xd5c9ae32cd3b1be24656c5afa5905546ee80f59ebd6556aff71b0e4fa29c9ac1e3f4705d08e2632d65ea1a0ef633abc6148f4502f3839f134feae2f11fa5453c	1	0	\\x000000010000000000800003b33225ed883eb5fabe8f8cdda4eaf85b5b1e5e28b19cc35b3c27d0f16bba2b7c0356eb759b367dd6e12d5588bd7397595d7b7c41c89e70aa440e8f907d34ffa096536ddbaaae9fa92f8cf75550011776dba47695a57368aaf5515c6837961c8231768b2c757da734fbf9e8608335ff65d100dfe9e0dbe47ea7686cb05aed1529010001	\\x6ccd0d0ad5c68540ea95ad016db31976932665df60133dcf5a50cd070b2b8e63d2fc1c99911381acefdf04de4a6af576a36ead95f2470cac712e7bb747317809	1668423530000000	1669028330000000	1732100330000000	1826708330000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
200	\\xd52d30ef13d44aa7d0aec76567b4c7c6c6b37b342c065cf7e4a288678320eb7d8b6261ad5c2df899427ffdbfae5c8d6cd5ee7c64020d8bfe4ec871b0e6815d82	1	0	\\x000000010000000000800003d7e449a338b5e78184d3ea1a190d51bbc0331fa22ec31eb40d2d28b5ede7ccbac2bebd3fe4ca8486cc8f312d778290e0ee796b38c41d9454f41f6fc23ba201a9be36a670d03b2936341038fc9b13c2b8fcf5f2eb3f5f2e99a2259ed37b15557bf55d6a4dd753384ed52ff2961171d9f6b51a29e07af7329bc192548dd4a86a1f010001	\\x928120050f125bcd049eccd8bb8d5fdb8d23f6f1f251fac934779a45ead75059cf719d7886f393d1176c39259d54813e8db9b0da6816ac3388927745d3eefb05	1666610030000000	1667214830000000	1730286830000000	1824894830000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
201	\\xd631c24d36f7175409c1957dfba6b3d71edca50fd1e8f33a02b0c72293584656cf2bdb46e611a6d9145ecfffe14bbf6fd9fd55c699230e7f98034082c45cedcb	1	0	\\x000000010000000000800003b2b80339ff0d979aceeea2f06511df09e326b37b03f6d66a011cc44f6edf6f587b44c49069af6f7d7e01378e7d37a4f35118306fd3fb964b540c9f27dae0afd57d66843a2ceffd687c5052c99e6f0736ae1e6a21db3a1d392ba17ab5a58effcaa39b535b09bd9fb8c69973615580e6ddcccdf30251aa107d9ec15d15bfaf7e45010001	\\x908cb64ba4e625b2edc9073ce985ec299dd00ded5445193787b524a9bb577e0e3e69f5714292e4e0b71a18bc81138cf7605cebef8d22e7af1e0dc3e76975d201	1678700030000000	1679304830000000	1742376830000000	1836984830000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
202	\\xd8a9339e0372faa00e2fdf31b09fe3f663eb3df20d40d8713ea1063bfd25d575c670cf26736eab7117db9fbbd3714e39e3693e557988c718a33689c2c6bc9d1b	1	0	\\x000000010000000000800003cf9de2aa716b5fa6e17adc0b64f5c5916770d96349347b3fe4ce216d43468821c66ff34ade1ae422bbe939b9daf800f6a38e79c1a65a82bb4efd3b8639e6edd635503d29f419872604022f72148439bbbd1c786af3a5139430e21ee42f70d3ed1fe21cb356c6ae951a9f44e5f3bd7f3d79be4fa84784fdc672a2e318b5e9995b010001	\\x498b16b95054b69ccfa1b40ca5fc782024b744f1f3f9445fb7d7c45ccb4cdbbe7522a4a04c92bdd30c6e03e89567298a7e3df96e902b1a42e5a7369a4d3a0e0d	1656938030000000	1657542830000000	1720614830000000	1815222830000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
203	\\xdee949bd49320e4868ab67d7b799b55df9e9386eaacf2447e5be90423b78be90e96aeed33ca427659f9f1507f8ca32c13b5fcabeba3d1b85369b48c91e02b5c2	1	0	\\x000000010000000000800003c34bf114f0b97ad890ca0eeeab568ddd0521fc8b4dad1e06616da09e84da529a3bb2ae8ddf59f8d2aca2e84f1da48cc999298de1a2226d80d0f7748b5180bde4c38175c348d446c3b5dffa730d04225913348b33359aea4982c3012e0ffcbce024596889e98f8feff57a965d6fc2d8ceba948d258d996552166975315668b2e1010001	\\xd92b8cd672b112e9163c3420a626c9fe32fff710a3930b0514bdd1f4094126b203e46df8597add85b298d8ebd2d47bcb9b383e9882fa094ead627c8567e43c05	1685954030000000	1686558830000000	1749630830000000	1844238830000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
204	\\xe2d51c3d81fcaefebbdcc43741e6e2d7eaddb3e90a0f41eadf41b23e7b7436e6d98afd1555ca2923f00de04e9fe37704d71606fba8adbef104116dbee17d4511	1	0	\\x000000010000000000800003ba936dead46bc0763a981f809a45668960fe2323679e4a4f4fd5b6031a005227fb53852bc850b328c7b1be60396db72aed6d6a59521b99fa049e3dcf6c66072eff47100f876e21d1214ab2837057e52edda72d046363aedda52f03191f9a49c4ced76600c75f94e59a8739b2cfc19798054fb8f493ea2b8793a561facd561581010001	\\x1664095fe86fc6e93af6dbf200ce01bd8d4d07818740a8520590e7b0d5a489c3adffa8bd5d332a8ebe82c25b406192e9881b5ce0d862ae81ff33bfbf25c7df02	1682327030000000	1682931830000000	1746003830000000	1840611830000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
205	\\xe459bdbe5c466f4dad797251ead6f6d8d06a0bf9b130cc4cdd09c8d45feeec5df253c9495fdddf8e80ff4d09ecff689b136cc88b9091d74759c89846aa372779	1	0	\\x000000010000000000800003c4bd50839f41a9b3b07a2a1462a93291f753cc9b890dbe58e6ffd44ca3464eca6e6c97235edfeb5608d7aed276f07a37bdfe4e00aebcf6c87790e58e53568f294c925f86fef4d58c08563ea2e179ef87a8bb37ad47ca726a6bbf42912682c079e58f24fb8eaf6d72c0da192e991259c349bc761fe00e24ecf0c87d0f8fb08cb7010001	\\x5d0cfa270618b97aa454aa06f604735ad6b40f6c1693738aba86ceded829548cc472c6419724cc2aeaee904ee895e6532d69357355c1058a4e1bc3b06ed2d207	1660565030000000	1661169830000000	1724241830000000	1818849830000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
206	\\xe745d7ea8dfda0ff4a239daacfed4d71d8564d94f2380136bd568180a00063eca28706f22586fe6d4e53103d46a074140ed69804af0e9a1893eaaed6f6e0cbfc	1	0	\\x000000010000000000800003c67ff47234b5591781d0139538458d33a1d6f5295c6889a974d1744c9b0420e5721a57ae22acdad5cd8053f235ae45f0d99045321d3efd7b1cbf484145a3f3b4a80a62f1d189d05b61c7ce973781db1c2b3bc199f4fad527e299bd12411068cf7a2f15075f6f2d7f3829ff0ac0888b8cb1c8e741282c72c5d42f62e865a35f41010001	\\x05cbb19bcb6394e4fbbad99af8e9d6763c61e4429663371b36a31b6025db65271c3ebf6e9e300bb7d6e01eacd67cb1ef307ec3f8ff63fb998244ad2b64893d0d	1659960530000000	1660565330000000	1723637330000000	1818245330000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
207	\\xea452b86e955e92aad9de3907e68aee77c7139ac6904d051cc797aee46aef12125f6c26a939571a99b70f5a388947a47333db2758ee7d82a8e0391f4c258b371	1	0	\\x000000010000000000800003c00ce5e7cbcb254e66229d51d8ed3f96fcde2a898bfb805da1a75e65ffbf4369495384c15cffbc886266d0d1fa302f8dcf5ca210e208692bc3da4ef7828b9419ecd7a7ba4543febffbb34300ae9e4c0c724576ec0eb48a85654ca33ca91a2266b219e3e40073f6a7e1f1da69ef732bc1cac6721437afffce92afea911e4335d5010001	\\xb069dbb70a28b8767ff5e31a80feeb8ecfec6dec167189b60010d60b4ae601785ebf91a3207538ef8968dfe7029754800dfb24456fa9dbf8e31743974713b10a	1667214530000000	1667819330000000	1730891330000000	1825499330000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
208	\\xec154e18ed8c3e06290ab844c5bdcf4573f5b3e87f2ec365195c267dc566e52702defaf0cc3a249142e3192e8501cecc51b4d1a3a27485c63061b86ddfb9a963	1	0	\\x0000000100000000008000039f3b26e2b60b3bc0330558af7e58eef486bd6bd8186aafe1028f1ac9e82de7b2b23083f97c37839ded2a15000a6e85c2c138de8b52ee6cbf67b2d21bbd573052035403ecb92f3f36278b0a572b00bce99282d2d8d76a6b7d3316627d870c576a6e9bbfe277483391be653513094dfba74098c54b0752e08f12e275ddf1c25823010001	\\x181c4d2a26ebcc4a5d3c9a51247170325107c27fa58835b9154e5ce2ea0f536a458cf23d220a3b81920d61be2b7a3c792743c6098ec4dd9f0a89696bc688c001	1667819030000000	1668423830000000	1731495830000000	1826103830000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
209	\\xed4d30880e95c9c9ebe09009a72af0a7d2778fd6b1b58f2e7b8730b4d890d2f06608fe322e0e55fb8375614678cf2295873095d52781ada0559dfc31b024f68a	1	0	\\x000000010000000000800003c602598b2368cfdb94689de3d9131fed031698a3f1368b34e3ef444271f3f1a64b572a4dbca78ffa4201088b7a041045e8b3eeb4200926b3d567cd0b5e7ea55c70527cd88df30f17c8dd687c603013d05fea530a95c2a392e1b0f1f8a9597f65152f68fbe565179c62286badba18acf379b12eb40975d02ac0f3445e57519eed010001	\\x091ec1c7b98ee48c955d3a5f36d66ecce1e0d107c7b11f277858e3b4d030e675258e9cff4a008f053edd47ca7348553a6b7b245a05157b2ca40f177e0cd2b600	1670237030000000	1670841830000000	1733913830000000	1828521830000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
210	\\xed4154014e060d870ac6d79919bcd07dbd7c5e9ef9817a09f59f76e64c3fda58e3a89399fa078a8336a8b2f343e217fe91f78cbc9f2082f2d72cdc5054e84a02	1	0	\\x000000010000000000800003cd810aa1ed9acd17805000cf4c66d793beebb80937c4ddffb597e47ac0da2993f5a80d978a1354cd8f04d6dd9f3c331302be06591ab5f380b5d6776c1286974298b6a46f7f45c6798c58e13e9bfa3b040b94a664bf162473b485b73195d5882c2a890aa74e0f48cc8c152e15849ee2badd629a2d2cd1234e3d5517189764f821010001	\\x583dd92e21b26d744533c01f2519641d889a3363d768d74f05e9d8a1227c3cd550927ae2eb38c173985c04b230295c2d32936b277cfa122f394ddad668048305	1662378530000000	1662983330000000	1726055330000000	1820663330000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
211	\\xef35810e7ae0f2ad3025f0a7b647bcb5749306603771cf0d0b5401476c441143730e40ec698ca825abad3ef37c63b960a91a55fc75380865a162aebecdf9ddab	1	0	\\x000000010000000000800003a1825b3b902e2d104e26b5a1e5577eb6f3aa6c7460600588ca7d48075b19efc055068c527b1c8f6a2cf37676ccdc312cb2b8db53bdcb2fb960d05f8665a0b6f613864c9e8054a323dc9a7bb75a97298d9bb2b15420a4cde6e432c9f667e00801074a151324464d09e7a2b7d82e7a4b4b4c2901e7fb662563a53f556f36a94d93010001	\\xae34b8b81e5eaa9137df7a6e37065f4a6340a38f7e837cfa4d52921d5b8ddc61ce1c2dfef6d31d502d51e88b81e03e3eef67e8bad2396164997eb266108eeb04	1675677530000000	1676282330000000	1739354330000000	1833962330000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
212	\\xefb9056ea4ac37ad0c5d9c2990e9ffedb52054f813fba4f1e6ceef9326e9a0e5882e818b43a602dc37b81dbb305cd2d73e01ad455f160af18a1be34dd1cdae1f	1	0	\\x000000010000000000800003c0250e11ecdc6bbdd0fb59c490b3dc6432758ff5300ab630f2155e00b4a4074493fa1d7c41ad23f68191aa6492bd4d721ccc0b806e16a4efe88c4103e7ecf6848b90ba3cdd8b3978e899b5481ff459a500fa2e400a0a0ef1f026da9badd0b6ebd43e7d27eff3e367e4b0a1b2ba54e4a93789c41cebd839b8434bd3809e06d6e3010001	\\x0dfe3c515af50561081d3a92c52609cb4efe4936a939ee4485e1a373ce78c2592e4e3971441fc17658713f6a83395f560cdde5b94ab520187e2933b0163ca605	1675073030000000	1675677830000000	1738749830000000	1833357830000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
213	\\xfbfdcafd4e02b477c48ec77e736036c0e2a009799dac06abfc9ffe3ab6de13da54b3b98975c2ade32958e54e02d26604b9fb9b05dcfbba6aec6313139913f16d	1	0	\\x000000010000000000800003c046934675533f72935e1a1b323941d4e90bde743b3662c704d819efa10570c12f43bb613270d387a04e66cbad60a4ed5eda5825f17aabeadf46349f85dfb63f4f5e0696cb95709e06d730912cd721c47049e7018167b81b71ca61daf293189dc0b1922aba60c5282d3e492e1d7236c0cdf1bb1a61b7aa768c273564338379af010001	\\xb3b075e4b1f3485c2edd7d26b9813eea388cd20db9fbaa6d9bb552524006cd5520f9622be4aace007e1023490fd865750b2862bfbfe8c69468fb845eaa7c8a02	1662983030000000	1663587830000000	1726659830000000	1821267830000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
214	\\x00c6e3df1e0ba6a8c7ea52b1fc5a7fbba8416eef3249549520a50fed17c5e5942ea0438824736982f00195558c0eb59ec7083dae232020cb9b654b985b1d25e8	1	0	\\x000000010000000000800003b4a24c895bdc9bbce66e0cfd79e29741c62b166d37fd1617e3457ed124da574e446d30d8e7d8c0fb6fbbcc5348c3dcb81e7fb7a093becf394fc2f5bcbc32cb2dd0ea2791bc74575f29721fe0ef818f6f4ab1668771611643d82c5df0f113aa65d016b345e8c58da7fc0cd7620dac05f7fd1b01730b2c4a9bba0562a3d19cef8b010001	\\xa1c3d1c03e615f0e682743a8313f2990b4f4b08b28f4ba3f115782c092655c617173722ad49099b2697c68bc16f245edfffdbcec4b5074b65b010ae7d05c6205	1673864030000000	1674468830000000	1737540830000000	1832148830000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
215	\\x0176a2b429a74673d426412b048b9700839e08c95fa8920bfd8891b29fb6867a51be3f91aeb9418775c79e12c2da94e6d538d37a5fec27d4014e6711395566b1	1	0	\\x000000010000000000800003b7f321ab4be5c28c7cbd5e94cd36bdafa19c14716d3f3b8eed3aad7797d083a3ae361e0a0ba5dc4d46c2954a0c6d93b6fe60dea102f09efc16843aef7ef997401acf737f7e390cb8061db10cbb263df411f21d84246e5356324838c7f56f8e80460315378d6c6c0ad780516caf4ac6b4ed3bc6e87c1f6d616f5bb1bce64426f5010001	\\xb52cc05a57e5a77f3312ecd837c5789497ed3f99b159b635bbd6e3475994e3003a2dcd0f37bc4ae637eebb0233e848daff81d48aeb5d6c61e0a3c0a7f0a3aa01	1667214530000000	1667819330000000	1730891330000000	1825499330000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
216	\\x089614cad3cd2a60bef58239ba98b6b0f2aacbc35d6bd0e4b0f8ee91f20d5589a726e92efb0a1d786f3e62c8408560438c91a939595f05433eaec908a3b1d29d	1	0	\\x000000010000000000800003c636989ec9346ae3bcc672fc8b56a55f194a555a23cf3de86bb6dc82a4a782c6c7ad4694de0e5bcb95c48337207556e8704b4f316b5fc3ff114b920d2867d9f813a252c4cf8c63a8bc2453435684602c681c480436d02095ecad425c906b543815f8d95c81fda5b462eed216c38cae75ba62b488c8621a025b489d04163b8cf7010001	\\x984503a22f2e9cdbe73f453f9d025a9b10d4c2ce04dad6dffe282ff72e4d96a69c875849e34023f6424e1720357c576377a498b8947ff9bd586ac8cbd27c880e	1667819030000000	1668423830000000	1731495830000000	1826103830000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
217	\\x0c8689c3606a1a5e57a4e1254189a1b6d197bf51c751ccc66267b034edd4f2cc7ad2fc9c45e4a4d5660a028eaa089f6d199ddacfc0faa5fc053d9d7b363756b9	1	0	\\x000000010000000000800003db1eb941adce28a36655c23194321a759961960b743c5044c6d978e4b6e86b54a399fca7e319f543ec6c3203cf706bdb566eb54683cd97fbf842485627cd021608550d3d787c0d0cfec5d6cd6dd48854c4143890c932afb76a693f4d559e90922347c699bdbf2cb03ad5646e19959d9491e266988488a2cafeee1e96da603879010001	\\x46795161f9120ebc746e25ba77d102d38d4a2f083a59d7950aed4f7e1b9d43248b1d581e76ce47d792d82e026b5b65e8106f3eaf40278adc03d1b76dcd433707	1673864030000000	1674468830000000	1737540830000000	1832148830000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
218	\\x0eaed28b07045f079e86b6d40978aba68cd81006b689a0c8789a7af32aedfed0da76d8ac1efce11bd1b41e8d2048274831b76f021961844446aa8eebe32e67ff	1	0	\\x000000010000000000800003c63df97e047de86111e3ab305e7f792450eb974635966ea48313f7b9a3b5a5bb19194856a523f3b39ec05f9a3677940d594ea18ac1ba8fac5aba63ab0630252ea05abbbfcb7521db8ced02ddf300cd0089f99f6c4d72703a158a7d833b7c25c0783a57f457b6b30f39c1ce033851b7a369dcc0ae268ec989a0851975215f2b01010001	\\x0ba16cdbbdbf41e8d6adf7444b601c1bb812fe568997d075ba367f3b60f96623d78759c2755ca5084d9868e3e0094ac497235fc4b44d979256ff0e3386d5c409	1659960530000000	1660565330000000	1723637330000000	1818245330000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
219	\\x12d227146a33750298f567fff06356c5314978d32e9b5c700f7f385780a963b764408cecffaabab02b56396f1260e4f27b296cb39366d704a14ae7a0aa690a1a	1	0	\\x000000010000000000800003b07dcf730fabd33d18ba5624fc4c890121c26d198371fbc1d5bd8e5c3c76524b9f7f48e5320b713b5bf9b6901843efc1ca60e39c0e4a9fcb99b024bbfa4cfddc5a4f20d73a42e82aa5c617fb027abd9a43d41027f215a95f98c2401a0ad562dbb5bbc2a220239a6e55ac8baa55955445ec0c32723b857b16b9e04baa7b35c881010001	\\xd4c6348c44a5f2a7f306065a8f889d25114384ff5b7ff0e7ac5ee75356c43b516010e214cbc166e377507ba8b87af85e1c785c9672c74e45f0c8aa0245cf950d	1658751530000000	1659356330000000	1722428330000000	1817036330000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
220	\\x154e36ba4074c86860a3f75f424d43a77e5c7630407611b6429cba52fa4c93c1f46d9502763eceebfb789be5ef16b0b8bec94669743dcdadf23c55468b089c0f	1	0	\\x000000010000000000800003bc15910bf566974843b509d764d9a6aa96e2fa34055d0356ae34b48a466b2bb381c199060c61d2aab1071062542a4de8f702dee5f7f5ec7176c8523880ca26d90ab1fc1e843c68ab8a703bc536949bcc37087935a9dc717e39898536efb2f00380ad4d9aaef8e500a1b0824952412ad810233302b795bfbf33ebdd4a03fb80ab010001	\\x87170b7e6211918277458d55660e934e704230642b4399d7d263e6638ba18fb4ff89c17d035872cdcc5f2c4bfc53e62ca3f0902955f2747246900c8283595c06	1661774030000000	1662378830000000	1725450830000000	1820058830000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
221	\\x1776de2a0b241e3435178e08a5522524df10c0d35668ea51118383181cbaf90e13adbd0b98ed092feae2372cbed4a1d53ef34dbf10e9d02de9b27959a9052119	1	0	\\x000000010000000000800003b261889bafb3083ab8b444bafd183fcc17ead62063930c4a44a79fcd9dcc80286ad33d9f323f39cc8d4934e21a8709f47d17643f791788a10cfc23b923d0b5efe4626c062fb95d43d04641b80e991538aede3e94df42c7b4d00851f3ae6a55a51964094451e9862486fdf17c90d01bf68246af2dfd52e64f83556f243637a7c7010001	\\x32b2299757eb807a59720e12a40866feefa54cd91d486332ae701fb408a84055188a99e0b956695be08f12e27f8e2b0d93ae8955cee3224d52c76988e9b30002	1671446030000000	1672050830000000	1735122830000000	1829730830000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
222	\\x1806a129bcb9646b5633e20740af91cbc59694c4b87f795443fdbec1c93c5b3fd99d793cd2610e4039e05a5831ef2851b369a2f015b0b634b8839ede426a123d	1	0	\\x000000010000000000800003daa35ec7e871cede21881dafca6b073ffd12f30419a1f17fa5f135bf9624f7bed45ec25bffe57a7e4f9ad576f8d17d5065d429afaf77f0b0f4f32e825c6a759d61188bcb451cce5a1d9b5ff9cc63609a8cd0a86f43e521e23e0b327deeba4595eafe1576d1636ea2726794247e8fca0969ebfe50cf7a3c34cebf18c560950895010001	\\x16bae22cbf5cbb45a412947f2e0f0b55da9c483a8046d46c8c2e479f03e6604054a88898f47851871c99ff221517c6dece9d80f1e178220a67a5ce6b1ce3fa09	1663587530000000	1664192330000000	1727264330000000	1821872330000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
223	\\x19b65a1c01eb4cd024e60268609b402a6a621a3a32fdde63a27ab44458488477049fe91cd41341a1735828ff08d79da84082a441efe721580310e338c2943b15	1	0	\\x000000010000000000800003dcf3008d5574390d1bad3dc593a8a83417a7a49729d373e0fa96361d23a7f329f61534693e2ece2b4f35e5294325c2e3f8ff3bb822052bb4d06b9baf5439036e9caef1b6b1b3630164c32a13a8241dc01ca4b5a0635daf8973aa8507757b02148c2903fd4139cb0feb9882b75de85941dc28becfefc9c865dff557b28f31cc99010001	\\x111550f0b2c67941aeafa05de6c56e1af4808b03887b355c749bb6cbea020df6adeaff845d2f547155774c5b17aef931736e62ea7e770b0fd16d5520d736bd0d	1678700030000000	1679304830000000	1742376830000000	1836984830000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
224	\\x1e5ef88f8bacdc9b192c8c8a5c1392168a71c2df877d0ec4f389e846025a28f7c882ae40b2a4790d82bf863c1ac3e72fc121be0f7c016d5240eb973e8ee32f65	1	0	\\x000000010000000000800003ce4970df80a63e54b71ace79b7d51515059d7906ff00744b83b77475ad388d713116ac9e1d929e74fe851f23c668f9c66698fc115828e705b27ff31e0e9bfe8eb23b6abde113173dd9450859135f66093e85f7d0f75437ea6b226fe2b8462a08984d60b02ef59d7743bb930b6b8af2a96da7f7e89301945e4471bd55bf8d735f010001	\\x581e385766411f4caa8d47744a6dbd5cf4d3d2109478dd8d599d092f964163fcfe5da0d7581a3c2379306b762a1cccedb554990670638cd1504aa9d34e078b09	1679909030000000	1680513830000000	1743585830000000	1838193830000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
225	\\x206e8530dc1c4c8e791f0952ea317d0e7f6319c46a3c567d719478b9d2a34cd7b87b17de0536d7b8c4ee821c40d98f8f89c50bd0a9fc93bad032106265b79c0b	1	0	\\x000000010000000000800003b6d7aa75d89ab505062e9c524ed606b6345bebb9151a03e4a83d3cef291bd733405e88bde78380c19d8cbb3182fc88f52d63ab15263d17aaf713682469d662cc4bfbdee7fabcd92ce2f15336b22d1bee42ecfebc8e13e8ba042798e2bbea3bc1bed6dbae6d3f3ec8048265406a8a0261830db1b749b80fe2390ed3f62c4d66af010001	\\x6e73a8ca5039e9730d5067a3e5e7914ea9f29fc576e554d839dcf988490b811a4bb64d1cf51677ca2531a319d5b6758dec82e483a580970350a85d1d5f33dd05	1670841530000000	1671446330000000	1734518330000000	1829126330000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
226	\\x2046dd35d413d2bda1a97787799d10bae844db2d577d7edf5ef5e8a3524a5b5798c025384ce14b4585c3bdb11e3e319e8ee832219909df8c959d621bd164f7ce	1	0	\\x000000010000000000800003b334e819d0927927f50e4db4419c3b67aac197f16c8496632291897f060b8dbb5ce23fe431d9fc4a547d4647fbbb9aa4b4aa98aeab2786310cbde96f46df5120863ffbaa379ec61a1250e36e93913f26ab21db8ee4d06814e7a1ec946062291034e6a307f8d453678578fa3b22fee86e93a5d9b6f7bffcb0b007258f36a384c3010001	\\xa0a2549aab3888de409d50f9b468023b0ac5753d4e5e8be54a2157f63d7a713b426d04e0a8bf0b8d143a9421a2456d29f864097712c43ff5c53d79fdef45980b	1679909030000000	1680513830000000	1743585830000000	1838193830000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
227	\\x231e5cf4cc7db463bde1678d377cbd461916b8a7d12037d31778f9179e3b7846b0fa9f8931637e6e87472cc739d03af08b2e83075b1dc985cc0961dbad1d1e15	1	0	\\x000000010000000000800003b3e5b5f0cb1a721e615c7ddfa19a9fe27e29b145f3b734a3d615a375e177bce187931a89ddc80acffa0ae322a76c673f8c09d2633ff00b1282b6ac2a5958dc1ed12f9bc5095d67fa9d14fd0013b9774c29340288ffaabc639981179aec39fc25bee834781d43b01f59022cc8c1613c71f83c46d2082f7ba018857fc51035a81f010001	\\x91988482b561a2f2f4a6c9ae8168729b4d733463be7fb9ebb865385cf74e8fe45f0573e7ca3e717330e463932a39a6b8d8022ec4c063c950d5d93d42f593bc0b	1661169530000000	1661774330000000	1724846330000000	1819454330000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
228	\\x2832ef403a81d0f169ffe351d0176e6b24b0a33a7b33bbf680ddd2143ac00a6a7d413643c38f11580872538205bba8717f3daa292bd7298ff178a8593fb23cfe	1	0	\\x000000010000000000800003b51fad833d0d03c4d2bd42bbaf98d8c76433256a0b5083356071633a0a1e0604a917727e3e87d2c30efceac8b2fb472d341a9827f131031fcc45a4b7d69a0e9f93523bcbf8702c9d33031313d2f1d4c2698676d41bca714e25ba63cdaa2c7bd8297c785e061be2be60d3ab49b70c9b3c8e1332926af8e26c104531a3798a83bd010001	\\xee5792959807ecd3e76dcaad30b3479437e69ac1286c57e72630f5cdb3bfb80fcac47ff5683b8afb75b3c43f50a7df96851278c634e6223bf2ac84b56257f702	1676282030000000	1676886830000000	1739958830000000	1834566830000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
229	\\x2b66c3d3e49727cb4e5f62fab77b32d926c5bf8b7ffe6c58902e8e8296bee462de449743733d85533878cf07fa0e9bf7c831f158c2333b139b9cf7c4f0908be7	1	0	\\x000000010000000000800003b503c02cce314b50bd2b94c99bc80f50263a5dd898bb6684fc94b6f89c55c2fd53716e3fa43768735fc8b6737ee821f7e210d3e9671dc205209b725db315dfc3dcb3c020638305f0f31f558ef6a98d1b5b3e62a2752d4623cb43b6c6e3c5cefa4b994692900ac8d4b8fa3dddc71ff68fdbea54939e2a636f6ab693539cbe56cf010001	\\x0fccde483347a0064a7ceed7ba3f4d31cc88e7104e7b6f443605b992c9fe889462f54028685c8fb8bf5d6044724d3b969518f174833723217f3ae31d29b4330a	1659960530000000	1660565330000000	1723637330000000	1818245330000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
230	\\x2dee5b9a3264961bb1a724d5b3f043642903bcac6ecf546b366e224a9aec62af8990f04ff711529bbbff0f0cc11d66acc0a996457ca439948c9e8df887f60ded	1	0	\\x000000010000000000800003ececda37139c80bb2cffb35cf846af5a3579e3ce5370c76d736a4798f16bfaa56cd7bb7ded8a5469abe3f38e44959e479ec775739d12aa5999201452389c6ebe8df136fffa8246ff35f9bf8c7a3cd4b83af69af36705e13c5bdfe2265920d68c8a85b36c8247480d61dbabc65b18009477651be865f2adef0eba0a73293481c3010001	\\x32293ca9afd11f5e7579a46d6d84ede10d84f743e1f2e718c3d1577635d6419e09f8fc019f82a56540aefd80d4cb7552bd776ab5eace91496a54e9aad076fd09	1655124530000000	1655729330000000	1718801330000000	1813409330000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
231	\\x2f360e81dc7f7d3da819addb918875dbc705352a8f5ec4be9f840fbf4b5684d656f38f1dce840d1035b2115c4bb0765e6a8d887a79a7a79b7bf6b92254afd948	1	0	\\x000000010000000000800003e50f7289794a4beee8bfd553ea004c379375b2020930b0d34b796ef2768a579e79b2740359b8a24bbf81a813024d86b2ec87dff7acad2d8e9cbf35ecf46199c65707eeb987fcce77f5515dd7d5843aed067807cad1e02970d5b753a9846c0c512c07b1e6e75b212ae14cc3170eeb14d7a647ca0b45f847d49f47d3967f586d5f010001	\\xdac100b00b350b0711f11eb5a3160bd0346b3322ff32328bf4af998115721757302b1046785e88a2a2f7c5cbe424920ef1b4442226ae819e716d01d4a40f0a00	1663587530000000	1664192330000000	1727264330000000	1821872330000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
232	\\x2f3edb09565ecfc15eb0f803830a7f83d6fc4b311d95f36e3f44d98dc063118814e2d3d002a0e9a7b687f2d5e223ab73f93d79d42928cb5e95b9b7e24505db64	1	0	\\x000000010000000000800003d5a25bc32287188b56aa96ede9b0c2b1ca5154fc109f052a5c1ff9de912b4d3d3ef50b9a53cf78f37629b35a8024a6f8ebda1059cea4619c0522c91c098f2abc1a5621b0246c5c199028b1625f127d0165cabf5c2e36f3b797a654233b3956d358c14187288f3c14c410d8cbde4e42d92756fc21c7d51a922e3bdcb6275707f5010001	\\x3532691021a6f405b9ad37c2ff749039978e5c41e9546380c5f29ae030991ab8a9d3dd3b5543fc801e2551ed094c7063120f59e55e183dd1fc2c9e1b257f5e0a	1655124530000000	1655729330000000	1718801330000000	1813409330000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
233	\\x324e9a1b1242a3dc454c8539b1efc8b71cf07ed845ac58bf2e3b310c4549a34019a434c9fb189be827d826780b1648f41947e17a21e70af9670919f61b0bd518	1	0	\\x000000010000000000800003d8a67a82b14d6257558943bada336a6a9698ed5b37cb893a8b9a8642fc4f83c7927558c97876e337d4da4fc14bf713f4f289c7c40c511875b5f04f526ecc1d02ce9dfb5aefc8b2a3f6c8cf65303ee580c39aac4e1cd5c67eb1aa1ea047c3be42441427bf7030d634d5d525c4f7e95f770b2066cfa778961310721982d19b72a5010001	\\x062332ce4db2a4f4adbac32fb328418ddc0f716d6c99a04f90fc7912e34a7877a878d0cd3c239c00dab17554b9e87a3b999fd3215bb56bd3d75511502f32480e	1659960530000000	1660565330000000	1723637330000000	1818245330000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
234	\\x3376e2c27e2bf5a07e42bac858f5667147eb667bf6de9813c758ff397cdf53d7242dd46828a103071662acd040aaa534125571d65a6ceec8768605b291f27859	1	0	\\x000000010000000000800003c0c976d7ab1e35bcea00ae847d0d8366396e93ab57237c83cb2c38f9db94012124729e6f50de855fb0660c0b86d6898bb2a21b56962310d3125409953bde0a97ee5bb99256b2ff3c6a4bfde8856298e70568bf85acb6a2fe1a08b2f8e3733d4f6e7a111bdf72a98b3e1c5029d638a434c924d3c127e1419546738ea001f8e983010001	\\x075c3de0fa039ac7aceb34c54def576229372ea3dd0fd3edc4c386d02046a71279cd7dc2eebe940f8dd4acb41d9b484e44a69bdf52da50796ae922f22119110d	1666005530000000	1666610330000000	1729682330000000	1824290330000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
235	\\x353a2cc5ac5d3af5bcdd294a80344ad01a2a09cd755848ee5bb02b5bd348a797f53f518beffeb6f62259dc0780d190de9a0658122038c3570888566ce240691f	1	0	\\x000000010000000000800003b82ca4d12e0e512f12161343299133b384c0d19d34f1ab0005dc4769b349518206543d467a4a842d35ef21b292b34451c10d978f672ee6fb3cb246bbbe69539d7e09a6f9a7c41db01cdd268eecb5a84b71fc460896447f6159f7e2c39e69c347cc770aa99ba220b71640d8873f667f2336980f272945f16f7b0b5abbb0f5cda9010001	\\x8034ff14c02de47a67483c61f2f87237e001105abc8ec6c196afd823ae1adea0a7b430a9463c6e9dc474a27d9f66a658f5eb0bb9c0501534d707215abd99e401	1658147030000000	1658751830000000	1721823830000000	1816431830000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
236	\\x363203583a396483fd9778ca7c881739f53cf601ea9eada911b802b81780da5fe669b540868516d04e6393e9ed6bc441478d0bf6e7bb89b1437189bd17b20c73	1	0	\\x000000010000000000800003cccde77da33e3fb63afacd25f309e98b5cfbd0cfb29b5f0be97a2c594c5dbbdb2dc9e7271ca31576867bca778455d0f48e69176c3543d7f1ad7510131f5485208c12da5f456cf8cc7d44a1b3f0ae9c55e36a0040a64299ac3e2e9f48c3aa87c6bebd34638baf9176b23dadd1cd8a2274fc7cadcf0ef323099903719d0c6e2799010001	\\x7ec4289247dfba0d5d383baadb0daeb89cd0e008108d54ea129c8dbd5c719126998dc3deb605ec35840be2bb27e4d56306c83e036d57e30e970d0bc11c26260d	1675073030000000	1675677830000000	1738749830000000	1833357830000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
237	\\x36d6f04fdb86220496851f24d7d00503822b6ddf07214924c8a67182edb6fa0d6d47f89495786b0f1693f17e928f26313040e7fdabe5b5d02f29640a0234c975	1	0	\\x000000010000000000800003c5e90e1e98061ba17f97cfd5f9f9c0294c8f9a54da9475f733ca5bbc63e25816c5df12fa2633f568287559f7f91b77a9d83cc4f4ff5c6a23de7f9650ecb8014ef556377293a765f1b691b084414c5ce27a515859b169bffe50c47726642f4c0ff4ebb86a14234e266d6ad88cc0c9d9dc03b4a1323309ce4e7f50de97130fed05010001	\\xf7a06005554987070f1584e39609199bbbcb2341aad2a74091d13a0c6594d10a60a0dc1a773bd66d01515ee82c35802dc01bfe8156ec4e57f992f16363636f0d	1686558530000000	1687163330000000	1750235330000000	1844843330000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
238	\\x38cae1604e71371990123427e014441c9df71a7d22891621d41f38467e66e67b7cc1a310b30fdf329df5325276c20244fd273e397a27f954139053ddf796ad6d	1	0	\\x000000010000000000800003d93c0c54f14313ca3256661bdfe48c051a0d1614cf8c6e05e5c861da0e98160b7c38656e296a44823ed045a9665f8b2f0ff39776c8d26d0100a9eb2d8b2287315702e238a5fc660015c93cc3c7f4d062fc3c031c8f879815c999671c3fff4b2879585dbc50f9ddc9dd52584640cc24eb16ab53ab623b005cae5ec216868b4b91010001	\\xbc5a4344f5c755722b535e74ca2d89b409ad69ba1ba5f92c54f5848b813bfad1b855ffd8f885624bf3385423f379ae248852945ce3b6aadd829c8312c4be1305	1683536030000000	1684140830000000	1747212830000000	1841820830000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
239	\\x38e2e61b28900c69c2021b37de66d84d02bf4f34d569a52caac5231ede3c97f9a20f56626210f235e526ccb3494279b9757e8bf6cc77f815f8b7d774726b7040	1	0	\\x000000010000000000800003c1c505a165852c01aecdd4906f279681b67226c225e83c811f49b0cacefac61b84597f1095a51e306d195073bd3c876f6c73c8e6ad65bea3e09a78bcc943456c4cdbfd4c96dddba41070ed3bb9a214afcb7e7a56db914390b27013fd2bd1197f7abc5e98d984f07223dd59668e516b90139c55a378b344e5182d9504ca4e9fa5010001	\\xf62c5c7d830a5ae42f3706587a91687341a3a99814edd0bc0a17a6f28352ab95d972bb26c8ab61d4ef8a76825552e004d3420003cba2d8e93d4abfb4216e1c0c	1662983030000000	1663587830000000	1726659830000000	1821267830000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
240	\\x3b82195c8f62ff8ccea110a77b38314775d6ecb0f98f858135f65d7bcc96230926fa9b032da0c76531b254a49613b9c41fa14bacfdf52958091821bdf0d8df3a	1	0	\\x0000000100000000008000039c10db3035ce60b8223ff2b52dd0c4e40f81e6d92ebb4d6167bce6c480c6249b24e20e041965831ebb751b3cf55b603fc18d10e3b7abade59cb85f48a1f3a916af95094a4759325dcb35fa053bb4ae5d71f2aebbd7abbdb013da866ab5e1e06f2ff2d3e19504e5e9498caee7c51834f47738eab56985d325468fe333ba4dae57010001	\\x1d04d374d36e66060c70ca69a453d4f6a4d280b7c39b018e7a70fef991352bcec2372c71a074713c3798bd2fcc16d160f52c3edcbdb0e9c7178acedd98c1660f	1666005530000000	1666610330000000	1729682330000000	1824290330000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
241	\\x3cee50b4cb35fc3a505dc1aca2c55b1700e4db5223c6f25d9990a8fad66f46d06f00c0f1880351a6abcb14d11c46107d22a686877b27eec883443aa1e48941ca	1	0	\\x000000010000000000800003c724a9a764b57a817b84b9a70de79ca87874f645a08d7539077148bd119f04d726b06ba594a86e89692408fd87dd6bc006b6bce2d01971587a6fecb89631f21eea9a78241759ff19b99c73a5549ebee54791d82321c132d41f33b5a59cc22b22a770d3b5ad122eb038dc868fc5d2f906948a753c63725f8bc36a5f4795baff3b010001	\\x77e9563192738a52be6ce16e1b0dbd28a8d36946323966cb6e8dbf4029cd1dc4a7df911028eb9d76ceeaba51df5ba2756226c6d2ccd7d78d3cda0df7ad0f5402	1685349530000000	1685954330000000	1749026330000000	1843634330000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
242	\\x3e36169fe5ca0db4fdff2d910bf664c78ff328d9171ca5614e86a8f42ae76fb124488d06a55e81053677368f36bcb43c32ca17710dc20037a9eb5933d29d01aa	1	0	\\x000000010000000000800003a5fbe780ee6234aa2f968800eef13f06d0bbd93dd68fb3830b7249dab2081a05a3ec74183d5e013fb694bcc20425bba28df57a9b26efa5737893c0f5ecb5782282d405777a4aa8d2eb6e67668ed0760e5b0d8a1216cdee0fa2f562fac488d3266574aef9abc14bdccee36dbceed0d9176d3d0d1abfe9e7b66d075c45d7239b0d010001	\\x4c3a3679238facd3e67de57668b8948749d6f5d543cf765dee591634d3c58c648cb2eb9425c1c6848d829164768acd4ad9f7adcccb918df4f858e8b11d252c0d	1670841530000000	1671446330000000	1734518330000000	1829126330000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
243	\\x42ea68b4628c4d42d8b0001d53cf462448767e3fe0bb6df02c90376e5a30e4c33eebbd72a60be58c70f4fe08dbca4423e6adca8d70b1b2efdc7c7b80add0ee1a	1	0	\\x000000010000000000800003d7b14dd17aba269e1109c8cea814344476e3f1c0b828b0f2035bf0915fa1a23def2802c2f7d0566a9ee09959dd4dee2924a71f169e5ee330b8a15b40ccf39015b4b1b0c3319bef3dc8cc7df7cc39b29310f0eb2b2f65aea772733e9ef2f4bcceb178cb33ee2d45ed6fd4fefa66affbbeecc52a94a2c4a9492af2c9d9652ab9d9010001	\\x3896520b544db0f4abfdfd43dd3cede20ae8421ffb09ae07e21409092d14ffce4b146ad1f408a82cedd2812947204be13406a9c2dc42c9a604e3db9052f81f02	1677491030000000	1678095830000000	1741167830000000	1835775830000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
244	\\x43da3ccf18a7ea03635a009fd50d15965521f8f8171fd090bf69b98e14d149872dac01dd8c171fa67656c04d923597327082b408df5510fe4d120c8d205ed2ac	1	0	\\x000000010000000000800003b5b17ecb6d7da5b133438e60ff7e47641f160f8da2b260fc56f5ead4f3038763cb0ca8b07f44056d874087cee27b81a184645af90495254b382d9d64c756a6cc2e4857920744204a2424c179fedbc9b9ad4e71408c084a89ab0cfe7ccb05bc84dbae3119b31904f10a49b675feb65f616c2c0171d003c5cac37855c8709a0513010001	\\x5d315ac1a3ab36234cf4b2d23d55ca82b78ee8ad811495c472459e98cb0ed359a2d093756fc6d0facd12c1b38bf0d223f8905781feb4ef7bf88b1c48e1470b00	1681118030000000	1681722830000000	1744794830000000	1839402830000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
245	\\x43267297e8fec19c887d947b45dc234965275946accd23303f07fc66d259ef6be90be7492b71a1a3f50059cdb4f25c7145ae69f6e05e761c4f5bb70df17d0ca1	1	0	\\x000000010000000000800003df7e9432b3f9148f1cce76eaade1a256bef960596cd4b8080b49ad4086303e8778ecfd01f266646441cffd1e842e7b55ad4398facd158ad260ccb6586ca014d09f79a8cef73e3edc57c21adaecdfcb5b2a047a772049a32aac742f618d0cbd0c55e3e421e7bd4b24c5b43e80da03fa86623fc30333158a79a79ed45bef0e1f87010001	\\x5abd1134660f24534bbccf2b7badb8121bec8898f4315be2b87d56b3227a5fd12307642e25396bf2529e1cd6af43831619ba23352ec64e96d89537ebf97f5808	1664192030000000	1664796830000000	1727868830000000	1822476830000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
246	\\x46124ee8f8c8d9bde8b00aa965b81b97d13e234b5044ac6776ce9cecfdeb68be539a1bdecae8a1b145e7ec853eb8835df8a92fad0c84f303401b36fc569cb416	1	0	\\x000000010000000000800003cbadc4adb35c7358dbbfd6b183f01d2e3b9fb5ac1a6c80380d3b9f78b0f1b63b71e2bd12e817ec4c132a34c57a7161ca6c683b16b2f1bc9a1eda572fe0fcd6f240476b2b3e2583996d775b7f351b65ba170ca8f21454eb16061bbd13b1f21f399dcc7d7aadd264824b038d8018799bc9738f91df589506e31a1c3a3622b83fdd010001	\\x006fc112a49586eb9b718885e9e5034911c0f87828512e8e25e58e716e186ed54134b97ef6c167f199633be578757543d67d8236fcfa2e6ffc05063945e4b408	1658147030000000	1658751830000000	1721823830000000	1816431830000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
247	\\x4bda01f05b0ad9e872dd226c1e4e649a17a370852b6370ebac31890ee4561932534cc2fed362aa93b74281f924e1d9e19fc2e02969a744721e69fa7630fa86a6	1	0	\\x000000010000000000800003d549c516a0a65bbc196f722f7697b744c2b8ab448e5db06a737ea1b05d7529a5cf90075723e8f4e4940a58f21236658edd2760018f800b12d84dcba1f6001fd1f2b77039b77be47395ff8750a9d976adfc1507c725ce373a43f61d14de02bffa0c64607914125803015b92f0c81f182e3f59869637b97ca7b07cd1dbf179877f010001	\\x44c430f7596f32fd8056f93a60475dca72b231ede6f4c2346a8dd0daff136d466d233f49559bfc9a51d20eb303b2007cecdc317dfdfeaf9f3d1741287c0e560d	1684745030000000	1685349830000000	1748421830000000	1843029830000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
248	\\x4ce67b9fa33fe76bc00fc0904fab1b7622e24d5d727577fc04174d9539beb1fcb3b444cd0c7b26b20cac969c7b9df561c034f747669508dd2252fba9e4bcf6d9	1	0	\\x000000010000000000800003cfa97e8aec232c36decc3fb6103bcc5ecd65427687ed1cf91028335c62fe155c53ea68523c3869f8e824e31c8b93cbc4399fe32825b37d020582fd1b07e53728a1f9defc0c84b95c269079b8f917485a080fd56e3167f5296c6ff1555f5bdea00b34fe9d3e3faedd516fe64c4b9bd36500ec6f9376e403a0a4db65e7be3c9d53010001	\\xe13ee35a335d2c47c34a87df7040d3b2c4b4cc76a56d7246e735cbd8b87f5ff0481fcba8856d30c1834c81f91ebb6c39a37c057c04dd67f9a4ac1acd741e740f	1673864030000000	1674468830000000	1737540830000000	1832148830000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
249	\\x5922d6db0d6edfdb0a3f53c5177f5121ed271090c253e1cfae75950b6ef5b572fd7e479e17ece9de864843e271d47e0a670d39fc1dae14b1160f79024132212e	1	0	\\x000000010000000000800003deb50668c833c5b2186e6644fbf5a227893bcb4b2b1b171bc940713943a45a854bcbec22ad4d64f1d4ef7c9f2e24782a68b44cddb7f6dced8b045ba888ede428f46888ac1850aecff3fdb5c727fe6babafd8e54f5ca234b0301a0455edbe8599a3ce35e472f1991d05fadbfb664ccf5d7c8fb33bde5ed30f57de1d24d7044bb1010001	\\x6313bc0b1349bf0b3cf384d45e1fd8e8ac99f258c47509e29c10bd40c76b2a30afbd1a13dad7e9132df891a018e8632769ee7e881913e8be046f499be6cd110a	1668423530000000	1669028330000000	1732100330000000	1826708330000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
250	\\x5b66906af52ae98cc718cde9c8b49772ad2dc38b29abeb6fb6bb388a4600d7bff1de01758927cbdceaf25118060f7ba4e39cb96e938e7db34e4c9034058cb148	1	0	\\x000000010000000000800003d43bab02203c564716e8b7a670ded713ef07a15f27cb7fbac104b58fcf147658417aca9f4cbcd37545aebb3211a74576ce0520d74879b559d8c1c0239ceb4018f68eadc34376d3b150cc8f4e601ddd3f6eb8825e2d40a0dd95fde316563376b2301c3c44be7c3fbe85a72aa7821ab3b2a35123c7711a670533fb41f6a4415c5f010001	\\x5e6c5da9f10e60f9928526cc1e7fdf16800f3d7751a5675a301cbabcc53c394984219a18abebdd9c4b8af5e5d99d053c2f7a715c6d5b16ceecdb071f80ca4109	1682931530000000	1683536330000000	1746608330000000	1841216330000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
251	\\x5b5e50d835beb73f1fbb3f1f32ef35bc2c7f0e1d0eb32ff18d2a12799b4700362e974c6ddf133b0a4409c6c866666d0fbfd0cfa27d25afbcdbd13df551a06299	1	0	\\x000000010000000000800003e8dc61504c9619c63fbbf636f7b613ccb0de447480dda11b13a6b24f4ed7c7a08504ac0f46cd49602cf8928aa47e1509844e4d8736b6f4cd002e2d4a46dba85a859dd922a7ebe0e7b0e9bebe84a3d725be550029b962878a176703c06acd7e78fd6544f7074fa752e83ea4a1081b2c8a791a9b68f436fd3c47bbbf845e0a8381010001	\\x3cd11e7535a2a573bf8959bd93510c6ff2ce8fba95fcf9837d01c9aa189c9b27080e35f6038fc9e0ae9b75035ad96891bafb7988cd3dd5b6adac76cff918f30b	1672655030000000	1673259830000000	1736331830000000	1830939830000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
252	\\x5cc2a0c909294a7679835c47c56874d7cdf6f544135037f74cc111f494eef5d603fb6b6a66ce76665262576574175b45faef2ddc98f36078d3f36ca446287e1d	1	0	\\x000000010000000000800003def716b87c6d2d031cfac93b7ae2a9ebe0e6da05eb1545880bfc489403092b058b51eecf183edb4ef5f55b143000d3fffe63e0cbfec28c8e5f12ac4ab3d4428cd94b7ed43f4c568671344279fb365bcee0637b849d2bf3dd3d44946a3b6973232181c335c295fac84abed763fbeffe1d39e010f1e8453ab839cc352d33a4914b010001	\\x1b18b9f9de4a2bef7107d31af0551e482740634f5c9665c6da61d1e2551e86036419c4bc5c40d71b94d89ab73e014209635880ea6d64bda8e2051a70212c7801	1684140530000000	1684745330000000	1747817330000000	1842425330000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
253	\\x5de665404953527ea5619a512e16a0922d560541ffbde0922a7f7352fc76c88672f5c55a5048fa5dd4c1abb3535d26227a0234fd0f351744a0813e714c3a66bd	1	0	\\x000000010000000000800003c64babb7b011aa343eac38d1e7b9c1027d47cbf06bfbba45cc94b5c2465991db88fd1982b05a6f8448a44e6c82c1dc2a5440490ee5da36dfd10aa7640d86220cb30ebbfb27181fe61f2ffd09727c86e85b234ff27566efbc38b93da2731280827b96a627de5ec79cfd030ff876bbb9c2fc562b8a9e671d69c6c26daa3caf5359010001	\\x99cb71372740ee26c5adb547745d86ce1f726cb941d3c75e289543f005f9951a64da5f3f5d50a971ac3b12c9e01cc183f4290fc4843b032bb357b1eb07156707	1671446030000000	1672050830000000	1735122830000000	1829730830000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
254	\\x5df2246e4f3baea3756a0d307cd592e8dbd964611294cab458c9e1c4926dd94684bb25d72d9af2d6ece145221af20e7066df7b217b3aca87f9efc55192186435	1	0	\\x000000010000000000800003c8d89f381b383a705d86fe11fa4888dafa58deaf4ebeed8badfb67b260f5336bf866e2033240b43f66ac9187ec324363fce7c74521443716c579d77028c5b8d410d65a4611ab8dc563c9c8088685d9fb2f1c78325c71448a5f14ee19e58120db529f9737f9df5af57bff52c42f65987b55263c92ee04529569c25a2baa284d2b010001	\\x1c263c896553d87446ee2e67c2b9622c74801e74be93cc408ab49cadcbbe32fa97f821fc581faaa635bc0f587e4038815ec3ff637982cbbb7b194693740b2d05	1656938030000000	1657542830000000	1720614830000000	1815222830000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
255	\\x619ae52e43c90a6d6c476405d8ba902fe3369906369a831329c1dfdbb3b5bfcc6361bfdf6f4271ada01353e39aed9bf73f61f33c4e8efaa049eda84dd5c3c693	1	0	\\x000000010000000000800003a25afaf203ec85dc8e66224778c33e4a292d664add7af5f610043b3d30a918cf1fdc1581a2b4241f49967d8c4d48dc6faaccab133bda04466bee69c744edac480e5d9afad97ff0289b45ce0358fdb7acfecfb4e39dbd85d83ba511622e33094af390b6d7c3583369e925d269c1dff34b38701b690e52a299dff3974e77f20907010001	\\x48429b93f0262d143efa3ab1365528a60991362c76ece8345b28c7bdca6c7f0706850bf3419ca0a7fa60e1bbccb0e84b7cb552d1c077a4000085f0ba45e88901	1671446030000000	1672050830000000	1735122830000000	1829730830000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
256	\\x62463c21afce45e8804a23bd7d2b6edd5da7ddee8f308e9db21154e81661b0428e2fc5cb6401a384f3cbf3bda9d0a9665acd31cd36279baa168a35b87d118845	1	0	\\x000000010000000000800003bc00a6e4c12d5eb9908bf3afe4e9fc58a4b74a399c628504baec8a99be0c873e3e5648f24d76f723957ff1a19f12bbac528e2e766353945fe71af403756428388767d292c04b76a1d0b1c400d4a0367836b7c85e843c266a73c70de03f8210faeaec23927cd08b4be0659071fe2d8569edfbf8190ae582c69e27e7bab23486d3010001	\\xb89bc54fac5cd3736423f41d4f3930333915c4a4e74823e5e3a90411a8feb9d09cfd952cf3712646c4e01743408998d07ffeba1c27c831c0cfdcf265d5985a04	1667214530000000	1667819330000000	1730891330000000	1825499330000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
257	\\x644e0e5c266328fe39a14267abb4b125089daa230ae613c343c504699dbeb23f570581388715c06978b2cbe1f7826d1fc99b117ce0f6092b8792f3089c8b9273	1	0	\\x000000010000000000800003b8c5a97f26f1943ccf21562ac007d74b124456714fbc8bc8106a48dceed18ee8222035a0de6746090e2c0fc51cf10b265ae2fda752f32ffab80c4a22a4be78c7f5a277a279e978dc187dfaf868ccdccef2eff59a8bad6d6d941467757a148a074e73b14df03f2a1a0945f76346097770a16609dd0f98d92f9e080725dd4bac2f010001	\\x1fbc1edd5c8e0bb4775e928fa97e48678ce98751d16775e4dc4e7b91f332b0fbc3b740d8e92a1a3f01531bbcfeebc3b76d1f9fbf6ac20469e1c1408aa86cae0a	1680513530000000	1681118330000000	1744190330000000	1838798330000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
258	\\x641a4a1bf46fc02950b94e1f3778e465f3c5dd25e9ee7fc9f75abd4bd1cc3f361da137797d7928ed49e7f2395c30cabffd7eb80bd25a49e2dacb1dce343741c5	1	0	\\x0000000100000000008000039d93ba77423eb63fc8084a6157feee4f6b410f1b2a0ab947c7b7547f0dd93957d324cf4f0f612f610758177e013211495930461e658424a896c0055dde6f2824f00814c5d8aa64917ead46cc726bded9bbb8ebacb45dff5c72652ebb2beffbc4277e796a19d9a86a0b388d1a2bc513abbc4da15b3da72c179230f4956dbbbdcb010001	\\x587900882fe59e27ca484c3bd909452322f60f245753f98274e1a06e998170dbc886d62541dfa23950deb093c43ff07e1ca5e7e787d6c37514cab24390943a0d	1685954030000000	1686558830000000	1749630830000000	1844238830000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
259	\\x67e272fd2e8f482c033b3575d0d61b7bae67d58b0e5765d5af0279de87a394d647d3c2ee35067d3ec54edd9bea6849f7d98cb86a4e07fec45e8b77dbef3f267e	1	0	\\x000000010000000000800003bb67cb5ca2e7dd0b4ae42fe5141db9802497c992e0668899a69195906d7348c26166669c154317e136447d07c2442bd0e211a629fe76268014f720df08d1c77245f9bafbf4f0f214dd992bcd42b384d97e70c22e3a9600ef5cf00bb3ec608430fcd3f25a8760f4331c0d13ac97f1e9529f3ecf4608a1fa6cae40826c1cd6d1eb010001	\\x86e613365024f6a87cf969e8064cc8d10aad3e1f6dec51b1cc51414e23a1d79f8df446a55fda26b526798b3e24f28b13ae8b23705bf5129e36204eb55372b20a	1680513530000000	1681118330000000	1744190330000000	1838798330000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
260	\\x6f1e165d98a34346112b40b97e2d44a5b5ec1342f5a2508bccb97979eb0760961cbcd4bc262f23df24ff26b77961970f07ab3cc438c35a2c29203fca74559837	1	0	\\x000000010000000000800003c45f2262eb6553e17ec57edb15cef830fd4a52885d75ef08ea08ab1eb519171d5fc481befb67898740583af728e02175d7578c6566ea936dd6fd105d1a397890c303ec628813cd35b725880b893b491aca591ead15584f6401bbf671a1d82de56efc292283f78d205f71519568cac496ac371afa106613ba79dd4461f34468b3010001	\\x5cf5371afd504184937ec9d1d481f489bd927a0a0ed205316563dff4c1cec9dc87685644ea22740d6d52a01a3ddcd66571a5ca2dc8ad2db3214cc8945e18df0b	1679909030000000	1680513830000000	1743585830000000	1838193830000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
261	\\x707e8f1bb09d50fcc2a82347cf9e0910c5b384c6b8d2cad30b3422bda50893a24de1d3ce19c0449eb2430c28dd2afec89ae6e68952fdcb445bc51c7d53defa8d	1	0	\\x000000010000000000800003df4b163f78671a25974c46eff403b8dc13bfe555c3da465b515dec18246cbcf0421137859247a36723e2c74b47efbf3e2d9e764ffebbb34ab4510cd11b9497f74dab997f7f763f26115e384207225b0af283eda041dd2cb003bda9652df27880de233bf0c6496879cb5af5cdd893a15c3e3ef0b18b06850b0ba9646c55874557010001	\\xb06469b5aa11e49cc611c2d6960f3cba1294115c7e301b22bf5554d4747ada040b243f10d7d3868dcc47d0e2cab7c6a47167f13d3747fa5741487539d5edaa08	1675677530000000	1676282330000000	1739354330000000	1833962330000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
262	\\x766a8d5c8601c676fd2351f1a9fa707b5c748bd6de79fb9c51fa7ccceaafa34aa49c243f02a41f931ce0240b1e24a9406455802deaa5d696425c995a286d6d19	1	0	\\x000000010000000000800003bbed6e4d2204470f3fc54c2549fc8047e2b422ab2a81f8e0602a676cd1397fbbd410c9da9d5741ca5bf1b75445e1b342d6693a4240cc5fb03e702389bc4829705ffc4ba79b28a4ec364e6978f3f72a84d2589bf299f55eaf368975609bfe1b4a4191d685402e7af2435aacc038a6d949876a433bdd3b29adcc129e8fca8d784b010001	\\x79755c9cd76d3293f9ae9f406ef7dcbb7fa8dbb24328eef8ae5c12b19a51b434e7bb97191c29f5c303031f990979bd1f49839829bd4c56c90d62033f69f24609	1686558530000000	1687163330000000	1750235330000000	1844843330000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
263	\\x7e2ec19d48c94622982cdf7145698b60803782d20e6ca12f8fe4c3586c931dbecbc69c521e4e8eeb7c841b3fda5a37f95bca0c380a938451c49bbc7b31dfbe2f	1	0	\\x000000010000000000800003d34300a728679ea158fe57a8f48fa88bb4135e867efb26e90fffe7b502b3e5b52bb404073778c4ebb7dc57f6c81101fcc1490202477366b9f9a39a22a61cbe2693462e09e6623ebd6ee8661f126aa24f026649e45c06c2298adac06a4c6f212a95690586209a652d5c4fcb37a49c36465b0b2d6d9ba8387d25c930da63404745010001	\\xe130e0081ab1bbb863a0f324f3cfcfd659d803a227b8430bdae49e28daa47795c4a0463c3d38bc0f00ccd5d647e8f003b1ffe922a85972f4732301b11cbf4402	1661774030000000	1662378830000000	1725450830000000	1820058830000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
264	\\x7efa2a7a4e7afb64ed91ae0ff5750d4532eade4cc6fc6f6234d74f54f6e89c400b34ff1d43279dd9113da9c3113b6cb23884c3d5ed149691a234ebcaa3d71083	1	0	\\x000000010000000000800003a96ea03374a544fb49997699beae97379c6bb8081c2a90d9425a7c75cab98b2d56987366e783233033fecaa6327b3333aac06cc345561f236a0937c4ebcff1bad79b7797486d66f4d1546e6bce5fde5c34786cd599bf90ce815fd00f8cdd02d4bfc47a6b45824ac24f019931150eb195fa7466ed5405fa6996c492700bb16509010001	\\xb70fedb9ef603c3462b889e837297ed15942771a5fd20511db878ecf3209dd116ec78f3fa588507dd6494f1232259cf36fbaf9e4f3487097881ee712d851d908	1664192030000000	1664796830000000	1727868830000000	1822476830000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
265	\\x850eaef5f20ba39ee979863035500b60d3a0b0c7c12457332fcfef3f2a92a347d2426f73a74892714f1c9658a2e5f7c8c4162beea4147e44a6e958e1fe0f07cf	1	0	\\x000000010000000000800003add39e7c1a650e2c5725ce10f0095e3c577cf1e410b778774a344a940766a7e60d6abc3574d57fa31ccae5ad0fc4dc7a981cf77e7c1ddfc574ce02a15c7bbefb4ab7e13b6ec62593426d7472c9f6d9cf063a6ba9fd837ef8ce46198389ecf2a4b708d4957f7afa49602d431a24950c2ef2ae1800c3427a65de6c949b21a21971010001	\\x9f7799eb9c9c5050d90053a6ee38dcf364351568e2f77e38d7efbc06bac32a448f36a74da8b42fe114169e2b26ddc1a024c592093746d7a615ddf4bb3f0f6b08	1681118030000000	1681722830000000	1744794830000000	1839402830000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
266	\\x8a664a29877fa85f3473d41b5aa108807f09cbba2dcb23006101f7da6587b0831344233620148efd8a5f50cef51016f1bad232038cf7f3ab8103b83524a69bc7	1	0	\\x000000010000000000800003d50ed0b09cafec1ad86a48a14174dd3e7f680fbfb2930899a989757a620ee941742bdbbc30e452d0766330785af05a0de76e057884d35bab0c9cc197a6169144463e19214af6472cd488e45de804b8cddcdb4b317c0a5e1aac39a7b829595763bf963e08086ca8c4eaf38dede7ff24126b0f9e42cdf5782f0fbc609ca3ed018b010001	\\x3eb7b4e8cf5b1345a56adeda1f276d6bf46191731393edf8935eb2de017ba10554fd18c52734a0a73ce1d5fa4fef5092f08e78eb3e790a5ddb07763c87d02209	1662983030000000	1663587830000000	1726659830000000	1821267830000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
267	\\x8d4e32f5a390941f0238f69dcbc04e570348e1c526ad7820d40b8bb7121673f06bf03a7169705021e9a426c7068f419d3e2d1df720c0d918ad2ceee69a60f34e	1	0	\\x000000010000000000800003dff3edefac600fb9cec8016a3fc97e398c594cbb0b513ba36b576d5b3a8090bb7018dd7150839f519686a6291d497e570f0af7e34770baa537200afc29cad7f65afb0fc76d27aa464f2945ca83eb0be3fbfea47a5dfe1896a9c5cbae513da05fd91203b86098cd7bd40371bc0eaebbd77d4bdf8711b72ae7f0d02421e4ab7b95010001	\\x8115413891e63e6b3f4b8e3b3aaeae4f72e8e1d829e367b034aad9449b81de85a66cc1b07e2999f35956f90e3d88643e69a52112686f03ec8dbd94bc35837b07	1681118030000000	1681722830000000	1744794830000000	1839402830000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
268	\\x8d9e6131ce1c680fc63c7827761cfbda1e1c8790cf493c827876843fb002e7a25216ccd28c190803f6bdc4f464cbba7e72825d4c4bbc6042f7e217bc03eea2d4	1	0	\\x000000010000000000800003b9e5f5b87667fc6b2e26519fffbc3c44d1a1a54cc49e8d5596d0197132d201ce7fbc79b79d0034e946c7ea6bee787c56e151b69dfe4d293b5a480abb3b7701f40684cd586ab9ae978cddb2ed2cf507398791e49b9140d2aff8bc4a1e381b16b6f79aa166930960f336ac24906d8e3a07af3ebd24083fe8034b951c21a73e555b010001	\\x0e9c2b4183184494226b50471517684f9d32db812f997aa475e30d09c483a8e6beebe280871451577184ac3e3c9c0658d88f2d04f23590b650e0eae12f9d3d07	1658147030000000	1658751830000000	1721823830000000	1816431830000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
269	\\x8d8604dd1f390bbd72114b8820305032819babebb30569f7c7e855ce5dd24758525439042cf8127af1804bbd92c748bb0152a50191842e0a3e6cf19c3bc59592	1	0	\\x000000010000000000800003aa7b7b9090c6012d73a866e359fd58cb4dd73106c90a98cdc3e355c1d37988c495ba9e09efb7d6484f5e634060dda7981ed6652538e84ce9afdee654a83c279a570b38d2d1d6ec0cb2256b96ecd97ecbd3f28b74251aa3929c7ebdaa23b258e606f70fd0a6369748517c5c4b8a733fd204d870963c9f6ddfb9b782aa3c7ac62d010001	\\xa8f05d1681b2bf0888a9ce09a90c2db3cb0b5af88cba1b27b2f46c6b46f467a3b5601c11b4025ea77b31f3c7b743a35d56ff36f21535b70a0adc8154dc61ce03	1684140530000000	1684745330000000	1747817330000000	1842425330000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
270	\\x91ba3cac4e01c5a195ef2cf19cd8d64fa00cd2d318c5dc1d4928bc8c742e473b97cfc035cf07805acb1a5d95e757a86234b51c5f4b67bcf1c131a73b856dc12e	1	0	\\x000000010000000000800003b2d945adf477e3c369b4d761468ba807db7d28d6152bbdccbe6957180c0444488de8496cc0a3dce13326039d99334e6e0fc107597a609a5859fef0999125e43641acd8ddd714dfc1947bd4a590b1b402dcc1c71802dd5b8a6537f7cfeb32e24cf605797c69e2606d1c95cb0a2e55af8d92c37f307f924a931708075dbe7c158f010001	\\x4b20cb51c91619ad18a12788dc23d65a7dbfba4d32466a7c8400699c72d0d722a0b9c50700e7cc4cf20dc68fdf40b5e88dfdb5a6d2e15195b5aca3b37250cd09	1657542530000000	1658147330000000	1721219330000000	1815827330000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
271	\\x92f61e5b8002dab1031f906858ba2bc0cc9c96857102cd2d945ecc937a35c0816e1a9192045af5d30bb7148f03a8f8dbb5af28a104eeee074488f93da259a947	1	0	\\x000000010000000000800003ae055a524d033c98cd88cf7ff648fd12d661115c657ed33d78eb49eb95f00b9e22d3af9d0bbb560fef6110f17d328297cbd306624fc8210f9555fb10059ce8bdf7857e22789eb02007cd688574a5f52e7a96d183d3f8a1cc9f59b9a585e5e15fe8e8f6e2ab78555bb5415c726d7938a4b93b133017eddfecb201339a19b48071010001	\\x657c63e5927639eae0f1f76791408bab3d1b7754cceee403c4beb5fa59d96b67c3891601523a3409122e707b015a9366ec5d5a6e07ad6ded15a0dbf43126750e	1686558530000000	1687163330000000	1750235330000000	1844843330000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
272	\\x921ac99a3b5ec470fd7615cb91e1785e6c1baf4cf1a91cb3fcfa6b67d0a97159b0c11edbedf7f5049f894ff66c83bb5ef8d6434c42501046c555a3a8ca37fe8b	1	0	\\x000000010000000000800003d1a5c8586166bf5038a0464533c173b9cebfa24e2c672ec33caa88808b66b5e4229a594ffc09200d87c7ffdad7ed3a84aeec1e84cc7183d78e70f369c4b68eb31bc92be77d680d123867816f8977fca2eb838851cda2ccc51f6510b5bffc2847e74d773e7093a7742b7864367f48025c48a9162e07b6160ecec2a2f6a4aed11b010001	\\xef51f9049b6153c2ab77cdf74b83ce123c5db6db81dff1e1fe00716a3d862ed886538257b505623e11a05528a11d26ebdf5f8f482ccc7e106b11cdcbaf03660a	1677491030000000	1678095830000000	1741167830000000	1835775830000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
273	\\x955602c6a49584da0b7d80fb203974e27167b393fe57f7948234792c2e519a894e098cb48543c7019a5d3d48082002cdb4071ec1696150668af5c7984dc7bde5	1	0	\\x000000010000000000800003c2c9b22dd6a403c9446fc80a569f8ee99cbdd39a5a5aef458e978644fd48ef79b4690641157fc9431b97af9b58e57b3f66a8d6626ecdec61f99908ec8bbeabbfa2d788547194214c57b3dd4c3403c4163c6b38f0a876c5c7427d00a386b2c8a2bffc2399db649f67ed482ead69f371ed1661913dcd0af67e9d88b93e3d5f847f010001	\\x918cb5d8c91f78aa31fd2e422e395879804b4fe04c8ce2b9067459f6f7ffc2bb8f0af735b595d32a25f2c4d0865de312ff8173f91901d2e30deb027b0e839d01	1666610030000000	1667214830000000	1730286830000000	1824894830000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
274	\\x950a8f809b1735a99db08e37ead58b194bef7bb8d1dc0725142fefe75b5cafc0933a2e34c772de7e5ba1dbbbdeaa1b64bc7d72ce9f88788154586a51e2bb657e	1	0	\\x000000010000000000800003e62a85abc29e9bc41d99b14e54aefd4c331b79adf36b9e7443578ed0fd4792ba972046c916028e77435dc46f8163225b49ed5f9450d0ae471f4b15c432d6278f2fc4ab2b1b2fbb2080d51cb017a9db773bd313d368217278e49a44d60474928765c608d644225845d952dde2c8fe54d746a14cfe3ba8ef560b527636141cb6a5010001	\\xe65bc50e5a0ad99db4143481bc61b38ce9766542653248770345a30233054a65534b9d04cba20f0eeac615a4803dbff7bc9d6206975f8cb52d71456c58c35c08	1681722530000000	1682327330000000	1745399330000000	1840007330000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
275	\\x9bda7e014617bbb1641019d3fb1e01ebcfbf80abe91111165322d9f37d3fad45a9301fecaa1bfb14860c94a8812db6b11df0a77c0eb8fd96fddb306f3d60f9c8	1	0	\\x000000010000000000800003a15f7eb95bbde5ab8f7843333b6f6b98ceb21b0d5d676bfb45c5c07a209e31549d8998f36520b980185425a78ce21a8c2308495d4ee8549ed15b6875a6af90aa2267ef74131583a57fcbae5999ca18cdefbee512d514742b992d9e49553e223db4a9f663bf7583f07c5a6af2590ecdbd89c4f5c157052ad46f229409fbf21cb5010001	\\x525379d98e1f84c09b0c638311991bee8d97fa882b40d9c14be8c547e605e41c51ebbe602adea57d5e3b7a2b0010c8afe7a180fc7306628112775b835109990c	1681722530000000	1682327330000000	1745399330000000	1840007330000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
276	\\x9f8ef80a8c9df4e2f6c03774094cb4d4348954c7e03c69fc6bb9363fc14decead9cd26d3748129d9db97f3f857296011ee1289ade8a9caa3024fed87033cb863	1	0	\\x000000010000000000800003975154b1c64088d5f26732cdcbf047f9593106f1f451164d51749794b95e8d6827e8b89543b37708179c2aa753c404c5921a2c383ea3df73116c59e2cd0f5ce9de0299dacc57973ab96a30cbe0906574a725b47c6a507c1bf66ba6429c5224d66fa0d7bda853d5a4a07e693d39556e44b38625f0d320a86b75b4a8aee7af97b1010001	\\x1b014c92565b9df5d9e20e218c48746ef6c38bac854a24d6b83017b4aa326fb6f3a52c648f83121f1b877a3f8ef448004bf1ee4bd0d0b7cccd08e20b5d15f105	1680513530000000	1681118330000000	1744190330000000	1838798330000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
277	\\x9f9e181fd1526d57ee428e7e497a4c7bb14cc8f0e0b5aeaa59f2a2c5acdb84614ceba2e9aefda4fd6cc1a0eb496f848119945c66f84d487bd45008148f67c30f	1	0	\\x000000010000000000800003bfc67e99c2917717a82d0f4f2c5eb98341432872c9a3d947bce0f7226224cd75a54a2201b10a5a738b5a2dce4f8d15d0e0cfb1e4108bedff312da4d6894385a3ea45ef6c8c29a09efe72c0bedeeaecf363cbf008010d36e0c9be4a3ace6031ce8fcfd29aee0ff47781f61a6af08e6e0b9568957a0ed6d281b6ca86c3f3e3e0f7010001	\\xf97664136c77cacc6e689e502afa686212a4e8bba4b12abe150c4d7e8c7921f58dd443b46ea0d5cb0832fb0ab3fd4598311c07e45409ece8ca79f546f14d7a0e	1665401030000000	1666005830000000	1729077830000000	1823685830000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
278	\\xa0d6b5321aed7592b711dc05fd20d77a0c0350b2568d285099833559b435f306e0bd661adebd2ca033bf55a153afa617017aa8ad91155c8d38b55502572200ac	1	0	\\x000000010000000000800003c98f28910bfa5b4b11a6cfbe67dff95be1485b86cd667486ec8b62ffbf6787fd43303df10c97d3873edcd8df15a0e1443bfdeb102eea1a8cc7e5680762e0cd0a718dbcee34e040511ab3a8914659f40b53808c42954ec20d59f2d7e55a67c118f4e9e0c687ebad163ed4578347c2e54927147467d60042b8ea73c73fb24a0ae5010001	\\x2e5cf4aa19976b2e469762e76e0ef7f3f50151feba62a62f7c708f79581ffaed4d711061c340b7085255f9b17637a042f81fcfe87679f7182eef0a7f4725a501	1656938030000000	1657542830000000	1720614830000000	1815222830000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
279	\\xa2be8655e1d3c4322ba03af0f3c2de6a768f97b84795614b5b933316239b1b674d01fa1a319a0715c19539cd02cad0f2ef7ee97de63f56c113be70085e961397	1	0	\\x000000010000000000800003cabc81c9863a411c87b6940cd1744eb33cab053bba617972115024dfe8624c4166eb332a33cda78c041c58e7aac98875c69e02912711cefc49c098d6ae4e45875920d47ce1271115439075e202af1fce68cc14dc8292b2cdeea47376a14241536f090529e880f96b04f573c03ea5c1c88e77f82c88aea011bfc8e21a6d8af37f010001	\\xc229e7494b01ec6c3e06308389746bc55012830b4e365648b12bc9e1487a33e95e790e043ffab504d2d03b04f039c28f68224fdae5c13c6111a3747aac058507	1656938030000000	1657542830000000	1720614830000000	1815222830000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
280	\\xa47ab8bcfaf2336d5bbf8bdc487e8270568c672e085845ae86a33151f112dc7f790e40c7daf12c3b8acb65ed4f4a3d2051e709b4251f5ea9ce474ea7fff3d416	1	0	\\x000000010000000000800003dc97c95957faca7783d2a4991a66b74c4a3031e145ac848ec98043baad76946e5d5c34f2ea8a4b4048b36b0b0117105da2c46898cdfdd69fce9279a08bcade0c81a2b12048ceacf2ad1f8faf34146348c83de68069da579d4b666dad70defe10a32e9cafdefb84cfb5d7281c341466e78db4b397ef8594cc7c912894f40dbb25010001	\\x89abbd35d717a3fc0ae4331e6fbb153424c3da94ed5f6445e1d7f25910706ca7c8a950939d93bf1e0d1381ef4049fd588798670232358781d0ea664587c6270b	1660565030000000	1661169830000000	1724241830000000	1818849830000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
281	\\xa51aae395c49228bd5a8fbb5082487c3126e794cdc3b6be85f8df083e232c46041b612e2433ef8f8cce9dba6184ed742a2d2c7fed9aeb5c6cbe45bf5a6be5488	1	0	\\x000000010000000000800003c0e70f0be13e6ce46abdb6b08d2671119f19c10a2b3ec5aaa73640c2bc441c45e0e9bebce8b4c279a6420cad9f16bb8e4d6360baf3f1d23e724ac011ab8fb496c96800e21babc3623f4d13c4633cdb5ffb99acc60f535efa3be8eae4e3dbafbbec0b75667f6bf2dd208a37913bfdd50f75d7ef6af28bf21a2bc45e70bd1d42df010001	\\xd3be5ee4670dc244b1a41030af0e330d0d748289dbe457aec9590b6e9d00e5790106259c6ab3d6de568617f8e51b2b4d858f16fca97ccc9041ea9c8f410b4702	1684745030000000	1685349830000000	1748421830000000	1843029830000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
282	\\xa5aafb0134c4df4016f3e9276e9d2ec928bd59e2ee69c99f89ce06b97a316e642d55c71a2a9717210db5a9ebb0b1768f580f56f17218201d3256e1834bb354e4	1	0	\\x000000010000000000800003c68c9c196466f122a89149237b60a0b41cf9b116f723df05e9312528af27802456b98daecf72981949a8c689511d0f271c6a610fcdcb98243abf3ef604cabb12a30f5fbbf3ad72860c671e0d598d8054725b02b21ac66a6aa636037aa2c8a4c7a6da4543845d904095698804dfbd769cbbb1315a53aac632fc53a0c214294d4b010001	\\xe98190b2883bb2caf66fa5246a62123bc842c77409d3fe81c5b8ac58cb474fbc4df14a557e1a7e3d64ef83f18edbd7c9f294816a897e2135195a8a571ccd0305	1682327030000000	1682931830000000	1746003830000000	1840611830000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
283	\\xab06149b53ac37a563478e8da7950bad74f774371a4b1aa85ba94664a77c0bffe1852f6fa184b2a7347f83d961ef6b6b97964d6df79cfb678ae56e302ab5e365	1	0	\\x000000010000000000800003b00da19cff33aeea6f7ff484f574338f9292bd124782cef121544a89e200bc87d4972fcb0f66a74a209175f2c890dbdfbec9a748b5595f9e83bd08380ea4f03def9d7c27877e8b772ac76fecf569c66765326f9217abd0af43ae1d503ab630fcd6a5907e09ac6d0409889021fc4564d6ab3938ffce1ca71ba4d3a240430797cf010001	\\x5f49105e050f666c9b1b07ad9ed396a1cab3590af5e95689f9e7ccb1a96fad954a863267b18943a04a0d9c23d54d48bef3ee99e3547c5fdba37b3ecc42b9d60a	1672050530000000	1672655330000000	1735727330000000	1830335330000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
284	\\xac32901db839facd661332b10446081c309f7f9d6434fe38d4c22c4b21b3326b212cd159d33912a5fe6b743a351a3f2f70b681efdaf2721df30e1ec6627538fa	1	0	\\x000000010000000000800003c8de924c71695d149328915231dd4f533b67f2ab31a5d48885caad00e05c624c41c69065b87d31f9564fc58a7d26f4e7e589c297d28abe4d42e9d2ce6fa455883fce5f177dca3567e55afd1114806c4bb079318d6414598237cd3c470b4073247027fcdd0e5146ce034dfc54d4c337b98a0fad0fd84a169444ed8b7a808b6513010001	\\xe212191ffe889e7717cfd300a6c5b01f06a2996077b21082d1e1a311e7c7a21a069b0e54aeb9a8f42d3d4a9ff17b12bc9405e8f633af8d04c4d2945dee38ce01	1664192030000000	1664796830000000	1727868830000000	1822476830000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
285	\\xafc28d6ae492c3ac0fa8c09f3143208ab3d93a9332e2b03b2d0adf3827e6608003c063c05bd90600d773b1f47e8236eb9484c75887210ec36054e296ce5cebb5	1	0	\\x000000010000000000800003d1dee917e0d247d8a34913fb7f1fb3e74f5262e6ee368a65b72019c1d2cc43071fbce121ed22a06867933dd3719954434a8f430ed1058a8e56a949c55c6aa6ca9d6c4eb79f38fe804571364df94988c32a7f37f2d1e9b8b04f70cd55166605b98ecd61c789fd5a707ce8b1b504250a6515ac20b231f31449bc45ebde115dbc83010001	\\x44752a190bbd99d4b2128c372d9ec6ed5ba9212cfe217e903448d538a0fbe073a536af7a892246e4adbffc0e26fe9d2c1ad48dfebbeb8c0ddbead22bb8cd0103	1664796530000000	1665401330000000	1728473330000000	1823081330000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
286	\\xb276b3ee47c274e26d3656a6e2e0be150681c12e0fb9e8659fdc3d0c00d4b8eb6511c8918f1dd02c09b10e57f270eaa54393a9727ea0f6579c4de8207b39eef3	1	0	\\x000000010000000000800003bf9043251b469f252478246cd280b21fb83d15265c04fdbdf4bd63f25ad03f628d5bff188b386f84d82f3d72f55889d41d75e4e52e3bb7df54be031cecc06003a66d0df931e0f62b52236c0c687350f55d0c618d07b224811b73785bc340f24bc1b7e923f77f7f9dfd66ffd6d4f7312ed2b4f09a1d5c61a462546ed473b3e861010001	\\xb7e6bd40f1a81a7aab5b0171d4e0a81eeeca11fb4d4cb4e0e6c3fa4c5f2d4ecf45384dd033f38bbef4ecd33a438f684f8cfb224f8235b87fc25c87c1002c6d01	1679909030000000	1680513830000000	1743585830000000	1838193830000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
287	\\xb37e07b9b52fa1e56338de58d55f222f6dd84efd854d8e4aadef00f85075ce18912ef8db496ec702a7e1530638a080d34d196df9ac5929c6065965b950790325	1	0	\\x000000010000000000800003ba41f7672b88cf49dd2c91395da91ffe135d26317d1f5e612ff998b6e41f46093bf05e199ce2b87c0895e1a2807211ffacd2dcf6dcadd967aad93635fed9c90e8f921174e64aab3c25de9da91bc41a65fc5d9a2c81b1007f6cf088ba7e06dc90abbc831383ed8da203d40641c0b3c5ca5acb9ca5160bc0b89f4c70b3de42bf9f010001	\\xdf318561f380f6517272a09156280930298ebdef151fff6a6f59fd630be12db7a6e89b345e69944f4eb765962f9126d35f49e0a45014923f41d29076ae65b20b	1656333530000000	1656938330000000	1720010330000000	1814618330000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
288	\\xb4b6616a3d7e0a587c1791242e79b504667e058d79ce0840753a6511ade451ed506955228763548ac6af20f897931f6702b6d2d20ea2e2a870a9012b81d8fb09	1	0	\\x000000010000000000800003b4aa4b4e179379b7731b5b60e087eb4c4309951aaa7994e5abe7277bc427d289c8e6ff798dfe35d16fa8b441d5b6cb73d3de9ac901a8864e5e7ee06663163882ba11928d2873901cee4413f813e5016cb967c58dc5a2bcf7d9b9f5989c8de13c876290bffb23acc0d3e9fe8792ffa82a748dbd7cab6483d6f102ceefe163d8b5010001	\\x03c1546d46487f36958ff4ee155787b061a25ec2b34eb1ba5be33f3450f78f2f6d56602e71648643b7fa4bb56f5891ad1c6b8fed3ee25b5570dd662649bb0b0c	1669028030000000	1669632830000000	1732704830000000	1827312830000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
289	\\xb8a262a5bc64ed714c1f6dfc38e4f6f628a941bd4518749e6c1fe8de08612780b718acd6f1ed76583c8a719b26667ab72c99709546e245f40f6acfffb0ecc4c6	1	0	\\x000000010000000000800003c2bbd4a6fdd2ad0e2998e50e3af73fd71c03cb8c924183846c5529ad6fa5e7692113d427cb8dff971a30408f22513413f27528b099502320cd67433cf43d556b130bd5cf61fbdf969332cf156d6d8376b581dd7560b73ee9162c4592d13161060292d98b7316ae3c1d55e6d971aef0d30ac33395fab56075ae819a924cdfc693010001	\\x128bcb02d9ac335fc0c4cfe594ac8fe95289092cbced88b8477f1f8c2a649a8a4d2062f8313045b132c9717fd357ae47c06cb0fc29e7929fffd0fb10f73bf900	1668423530000000	1669028330000000	1732100330000000	1826708330000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
290	\\xb8e6e6551579af55605fe13a6c48852f290626fb1eb180cc340332f92fcb43e895b3917bf8f25f0b963c2c86de8d0be97f303114ef119d3b8ead3c5f2e354a25	1	0	\\x000000010000000000800003e2b6a1a9edb430baa1f9266472938c9eaf0375befb150ad4a64df3ea4ee2247bd205ee5531b250dafb1ea32964eb9de2e5d323d05b476fdcaf6f47a2b5cf5604918bf9a86fcd202d0c6900dac868be5e5f89d508783561d67d822b024fb51d89ad462d993392c04ac915aa98155563114b05e2c91196b22f2c65a5c0f9166121010001	\\x26d57abc5d751d2cae77469a6bca900313fed6f0656eaa7e1bec036f7d5722d07a1bf0003e4b358b8b3642d15d1e6ebf62f06f8e0fe5ff9c7900afcbb95d7309	1684745030000000	1685349830000000	1748421830000000	1843029830000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
291	\\xb9d2516beef665873ae9945573048ff2e1fa3a45b47f3701386475f6bde035cc1417ce968461f368a67ebc59c8d256d8ce713e78e7709e8d6f974f52228b4ff8	1	0	\\x000000010000000000800003f17bc02d567a0ca37abb57cc885ad1b661419f67bd792924f4a2c39703cd26ad6945ba4f2897d747868a7125f27958eaec6ffda5fc3f16c0211f9e1699f3a4365825fac4ee292cb3ec442464eb2dbb2527f89fd5ddab55cb0649c984ea987800f6b70d69119834ea92053a762aa000388d3fa9889fe85befd3cd7318f21d0313010001	\\x2e0d9dbd0b6c69ec1cce304e23294ec14b4a1ec89d6e4778f48fb66c9688e34101c7ed434a20bbf9aead213b853c3a80f25dfb8f2b76f372903da75d44545506	1673864030000000	1674468830000000	1737540830000000	1832148830000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
292	\\xb9621864844e8c5ec31c9677813c6c6c1feb3e3b1dd23d57f630bfbcc05127f9e2e88045b9769b3dd4e5a6b8f5ffe7e3c2d3821ead4812e06676037b86e9f6ab	1	0	\\x000000010000000000800003cd6978293a74915585900d61a9df04c5928b626f6ea8799899f92d9e05309e0a14491e19b8566a7f7c1fd35b9d3888abc9ea117a982c1fc07c0cfa31a88f25a40c9639a5134385aed7ee72afa1288078f0daacca19109c6286eba82b0beffa6a4e13e82643c771258794818fbccdbafd99ba01d583c693fee34703f2ca741899010001	\\x647ee47d73c247650c03f43dc40157e7cd3fda89311bde452ee9c283aaaef28ae3be8770e528932a6a847e2df611e2b795f6e2c062190419e1516999a022df0d	1673864030000000	1674468830000000	1737540830000000	1832148830000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
293	\\xb99224f5d81521acc4c8063f20fcad60f6d9674f224246525affe41daa39dfe6604a3606838d4f09be04cb61cb7b0b80a81b17add8cac765e5bc3e13c67fa8f0	1	0	\\x000000010000000000800003b9b9b86a9ab3086483f82e25485137ac1d2c6a0214d9dbe88fbc165c173909c27d998e0d795779292d722acd73f7322729e1338782b0b1361b6a9fe1e08b89d1fb499a988738d19dfccf7b2514979393d312a53de4103bcabfe79e9b8e8bf3e7f2da8b9129b20355c9bac2eed471f5b2ddede63150899c23d75c043eb201fbcd010001	\\xd46253b527d6e26dcf2a2ea887f408cab578761413315b4b825602328af842c149bfda15f4dcab9a8b14ea29921079cc9e3782074ce518c757c94833f214c000	1683536030000000	1684140830000000	1747212830000000	1841820830000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
294	\\xbaae1eb301218ff4b1bf8a8a96bf5559b9a038ab0cc09c0f1f12d870313ec7fc00a8831a4ede24c0d8bb73ccb938e47411b39c7fe9f00525004cb6c2007b3431	1	0	\\x000000010000000000800003c1c39cc081658dabc72afbff67abda570d47ceaa772666dcc7a37b96fcd00a5e4e148b615b24caad6259c17e649f9c148d9570e0b4587039e08b39413fad82112c6613be5cd4c7e636042c9606b74edaf89bf47cad05e0310428c1ef9a776bb3f49cb3b986c532fd8ea3ddba75837d032691aebb95c0334ce60182364651ff97010001	\\x40190477dd40eea29a57aa609da4c583e0abac2a43080ab2233f237f74f411c1ae8a6047dfdc6ba0a10da67f56d82a97d593946852b77fe97bae2bc28f5b2d06	1657542530000000	1658147330000000	1721219330000000	1815827330000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
295	\\xba426a23a4556844a60d5681c903be6c61669a4e6b5f50bba577545148a9fbd2a57ccc738c3541c2c415cf42079ae34bb86c1e825998a230b87989ae39874eac	1	0	\\x000000010000000000800003d22b081d05926f0db4943fa87afa1a2e908bf0a24aba159016fa4589c50dcdbf1049ee315e0a90a6d0eaab31190f426d3649a28f323e98cd617dd2f90c4708f96a49d23fec23e3aea2e225a88bba385c903beb4d80e4ad73c71f92545b77f8f5ad5b46e22b47346de7483143b35b506bbeb0356f1052380fafc47aa077b7b9b9010001	\\x8c1ab77a14a31f451adbb6a30cef5a3caf6ad63df694c1823301019cf508b1f00ca9294516d76bfabcb7aeaf96412847f308e818590c9332b0655d89f08d8903	1676282030000000	1676886830000000	1739958830000000	1834566830000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
296	\\xbfc277a64463a29057c47189990e42ccd5bd898ad707a220ef9354ec3ad95fee84c514060b4b41edbe39a5d55076e23ba506478eb5d844d526c7c6d31649493b	1	0	\\x000000010000000000800003c5d4097ff871642f4955fced86f2421b65a06c54ee6f08608d3e54cb57483cd2dd0d1005bd6bbebf1fadf2f289c34acadf1c1cfc20e3097e402750c4f5db63a8819ad685a102cc7bb794e7ede44cd753e42fb31e7fd2e9083f513d8037bc5e457ef84670f6dff84d202098ae88280a2e84adf93627af4373f1a92566d00db3eb010001	\\x212469010897f68ab8a29a57851988417be165550765903f3bdad3302b7e73f074dbe22736332215aabd047476454b44d34bec51978e4a97362a0529a1bd6506	1659356030000000	1659960830000000	1723032830000000	1817640830000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
297	\\xc47e24b12412e2c84d3011e1dd3cb46574140e817b968c482d3efeb18e5453fcb284c84d8e2561aba3b002ce8e687bc63da94c34f92e5f32e0a3fbc416cb1807	1	0	\\x000000010000000000800003a3af13110c1eb8446570c12d7dfede73e88d2cd3620ba978daa2113d73c321e4517474608dd44cd85ac7ed7f89b9c6f6e8c82ec0906eb7412dd6e0d34e8a0e63c311753fe4609f9629fa5b1f2462e7b150f4414f6f2158720a49299ee3c04530865a75bf969ab3c6ec63829ceac1238898a29d75605e96ccf6b2cecd3c8d108d010001	\\x99fb3f58d674a27cc34b638f7fee2528f9617393cfcaf0b7b1ee566f53c326b6d765c42f66ee2c123fdc6a91bfc2893b7f25f82dcf509c6094a752832e192f03	1661169530000000	1661774330000000	1724846330000000	1819454330000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
298	\\xc8ead438218ff88f8fa2cf9442a0b9e7a6533149fd068119a481fc9254f6798a62e8397fb1192ba0ce94eeea36b5377c4bbb5f8fef8e2dbff6fca8b8b0ef6bcd	1	0	\\x0000000100000000008000039dca0e7489072b81035cef04890d3918d2c736de0f33b085f5f911b2a9deace6af146ca0e4f1025cb80e94e4c08f19c3f5166fb4ab4c44805ecbc6d96b1743c7c09dae9375c7f7f960c9dcc1a8b3498ebcf379274deb881ff59fc14902c98264d653ec3a788fbaad9b7dfffcbe0aa75392e9c389718eca7cd7b3be0ce50068fd010001	\\xb5583a6a7c84b3c13bfbffcc131355eb228af94888a9f5395336ad581ff9cee9d0081c3d0769c4ea983f3dcaab5284f37f586680d52581473410c87fcc36820c	1667214530000000	1667819330000000	1730891330000000	1825499330000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
299	\\xc96270141667f66d87009445bdba73c88bacc575a46e86117164e7b6fa20af1bc2ff9595283dbadebfe6cd710ead559589141ee5b2afa5922e338d43f9e36a74	1	0	\\x000000010000000000800003a9157c9b68b66a9a82f342395a10a674241e0756c072c621747336e03fefad6a99770f2a76944f300b5ed7d62f4b5965750d1cb41f7613832bfb17df6dc705af7685d44443171453f6e09b9d37404608d08ef22147095f6d70d8e73d3c55a3620cf5cc459fcdbffa2cdafc91c16eff90c61fa87120c6076cce110b7be927017f010001	\\x42e73793486e445ba87e4722f85e038d781ea65cb3f75d5f9e5f5bb026569ce2eb344576bfcf4b50f23b8f7289e87d3ae1196478d6b6dab24dcb705dead89100	1662378530000000	1662983330000000	1726055330000000	1820663330000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
300	\\xcad25aceb59b41b17323045d2a769afb118cb5b0bef176af848cdb1240f6806f2d02909fd0702b6d9574bf4edbbfc5e8f404c9302f5b327e0875ff4b0ab75264	1	0	\\x000000010000000000800003db8f8ba11d37ab882ab39fd44fc9eda7308943e254f357e967ca8f367b36d5934206c009983fdf2a3d9619db50cc5234cdfa1e26cff8a7a7d49a98254c69969372f57ed67061026ba8db34e8b39f2d75eae039c6b38210238294ca72ca3dd117f7c570a3c92927478908581e62bcb2d2e73233b1218f02c2c24e85f66145b5cb010001	\\xd91d22a55a901af500a0d1c165b422373ca538f531e0d0c27d3418e398cc5c9bdd8597d32527a79886c6d9d69a809816b7fb3696b05772e88b74b74d9bd76401	1669632530000000	1670237330000000	1733309330000000	1827917330000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
301	\\xca36e89224c44cd01f84ce87bee48a7b75c42aedbd4518116f3d697677353f5d37bfa1545f903a14ae622ab76981be46f10af4a8bf3df2928cd33bd773dd64e3	1	0	\\x0000000100000000008000039cf28526e19443cff1f7da0e7b4448e252f936033f11976b5b91d12a069ba4775ccc0f9d8fb39772db5f22eaa9a1158b0b404465623d0ae74b5261a44eedc3a37581571378699498296b9b1ab74d47274a5b5da6aac89cbd6b017f26aaa3959dc129d8b0f87aadcea036ce40369e7f2ee5d5289c0b46722cebbb686cd3d30523010001	\\x145bc53b50a826bb93c0d03651b7e0c8b13105c2cc7c0950bd79534247ac770ec77b622263dee7c82065a511ff62990c227ec458ed829fd7b41fd00284c4dc0b	1669028030000000	1669632830000000	1732704830000000	1827312830000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
302	\\xca86dfbc3e8e3abcfee80357ed2ff645586ead997dae8d87c5b69c5487c9db39f28a7ba802421f5289e37146755cb5b83ef017e8094ea3b64cc24998af53c73d	1	0	\\x000000010000000000800003acfe56ac02724e49343c9050e45e8647b1bd0ad69e6f3ef3bf844ed42f5c977e6f8c7fa488c51544ebe1b2116eb82fa8cd152476d3fb9d96bc2c422f5d49cfd435af6e51cf9835be79ef735184d0d613573db4558a75064117fea0ece4cfd707595a277acbfa6a041fdbf37cf4dbfe7765856b94ef6386ae29bbe2c48fb23891010001	\\x21afa8397677d83864f19bec72d9e4c487926c501992ca82d915eecc06ce551ce091970f6edc9c6d95e1deda00bdcd0427e3578fc9113566de786c7e95f31203	1666005530000000	1666610330000000	1729682330000000	1824290330000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
303	\\xd3be64ffa3ec5fba9d7105eab549fa5b684d95e40ae2ac392b8368a255e7157e5df15952d285e6139f7354ed50b699747e451fa2929f8f201eb977f8d43a23e1	1	0	\\x0000000100000000008000039ccb802bc84053cf1b5ee236f334af1c6b0316b2dd3f5e620f1ddb4b6278ad28a18fa8fb48a292cb01472d2308e7c98536b27f09d99740764de590add292692f236a71c55e0f2d5b19c980f37e38a473ae6a4b15d7bb947f570d65b27d8eedf49fc24b82510b3f69437a83d80e7b8e56ec1f6179dafe52b64b6f78a090e8d25d010001	\\x0ad397ad38b54e6c7204b4571c5d3eaa53564c872e8ac343cfaf8e6f7e7cda7c9579a01cc5d619c67ffaddb0eee11f381239384f5b2bff52f2f7b76aa1826e00	1686558530000000	1687163330000000	1750235330000000	1844843330000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
304	\\xd6429e82154c2907226f60178b61e18a15b41557ce01faa9df7f4a25ae97e8a89589a17bcaa66e113081140529768fc33dbcf71b4743620fd7af2c89973009f3	1	0	\\x000000010000000000800003bc1636f69b029433108f1ff9983d91b96f1549a93c535513dcff5c57f867729ca3f28c23b1db50da33ab9f19d9c19b18097ee4385ba27bd54a3ae5e4943dcf08adc05ea21863978008b11b10443391e58f60de2283944b4b40b8d0647e128519e45d0b4eda31005d37214ed9000c2142471125ce0aeb2f25a4115cd278cc4b6b010001	\\xf8b2c69395cb3c50f1a151090afb27c417d3ab8827ed4d3277d99b238b08bd61d9e26d252ec3dbf03eb8d1c71e00aef9aa5a045b1024e35358fd294dc599830d	1672655030000000	1673259830000000	1736331830000000	1830939830000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
305	\\xd9b2c162914bf99b56c22c5cd624b335be38c79437361f5546345ce43cbf9dc173f683362678f1cf41554ee544474e43bf736bccd03aa96eac521b10093f29fd	1	0	\\x0000000100000000008000039c66e9b0812c6bc997186de27446391e911fc98050cc2594db71f9624fbf3f2634b65811586af0b4a8fe6e4cfafdc39ed1c6413bb3aa073f2c7720b6a7a90e88150164010edec11646c7ef19aeca87907ab9dc56cb8332fa057bd9a9c7f856bb2a44e48dcb7af16c4d3bfff260b9a3c62c0499ca248c9c3b147b536292c1b0f7010001	\\xf0e7c8d32f098a85446a00dd6f359b98f4a98487127533edb60c7c1f26652d14f80a51a5c9ce8c45d509fd6d75f26ef1a2e8d408f57a3d081a679a130589d009	1678095530000000	1678700330000000	1741772330000000	1836380330000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
306	\\xdbfe23c67f4390bfb1db73e6d30a523ddf24fbfd9f61d9fcc04c91269207035d89429b0f550c21ebd5aca6299af198e379ba393adb68d8e437c1b8500e035f40	1	0	\\x000000010000000000800003ab6bc5dd173539778c51aaf93c1278341ee231db902202d3c9d84b3672ccea79193a6807ab32359bac57ecf367c04c7f6ad35412936ca3c8ee2900409969938747c3068c52f42f66e75aafb850a96a72cebdfd83bab614e17605fa696b31e2cddc35220ed2cbe35b966e75bd811b4d3b2c8731dc4c85ab6b37d4728b5e9e3bc9010001	\\x621a8a02c3cc2b4203ef2be936b15a816cc1c9803afef5613356e21a537049fc898273aaf95d7e6c87747aa27fd00379f7d70ecdcabc4e676fc6f61225e1db08	1681118030000000	1681722830000000	1744794830000000	1839402830000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
307	\\xe06e0d5e85583f93d2495b3fe38e4c97e0ea35b51f9bca6d919c8a7292906c501e02f20508b3a3a88e68614dd00ef26be4fc6da561448584b765d7ab865e5351	1	0	\\x000000010000000000800003bb1de5cbb19f5181255452eeec6e969e2deeef2d17deefabe113ea4377a8be40d9af5cb136931189898d3af88402939e785bb74c5eecac9f417cdc0b69ebd2c2bcfb83899ed556cf093d64a4720dab64171ee19558eda7cd5ff4b254ed40c125cf50cb21562f5dc679952b5e33ea842d11e31a945bd14e0269bb7c1971d531f1010001	\\xc1bad58b8b14632d603256b97aaf669dcf32d21dd589865f4378d8db3ccfdeab8885ddb83aa3d36fc531474ec2be8c8e86486e3186dae51750df3a495397e508	1657542530000000	1658147330000000	1721219330000000	1815827330000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
308	\\xe26aa30d0c14196c1c84820317fd6f7c5898d97548eecc0e7c98df68965cc6035e4c2477f4ac4539793db680d19c4e3541d4aa655b38dc0e18e0acc8c4d03ce4	1	0	\\x000000010000000000800003d6950613a8712575ad0bf0328b4b8cad756fac1998c49beafaf115709a073fcce9cd4ec880f7a7fcc5e56945cb6519ebfa64f11c263e99c05b222ddb6d13171993c8e83bd626c6bdf500e61f9b0877a7ac5494a4421662c0c342b1c7624b01ac06e9df15c1365d6085ee793e8794d8b882c06c629a33c10b3d1733683f083c77010001	\\x890e68fbb57b815c452b60becd275c94b0b1260d6f0f9c1f2d8b71c6ab40f8ef5679fcbca3ee3bde7247a71e0fd4ae03f8d5c5d94b3db51c25cb5da1dc3fc203	1674468530000000	1675073330000000	1738145330000000	1832753330000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
309	\\xe342a472dd7985874663b2c7936846aa620d305059dccfa6afafbd219e01fe40cc34ae0cb40f3b26602152a6c14a014750400fc9b83ad4b50e9937c8a5b6fdd8	1	0	\\x000000010000000000800003c27bbd40f28e67834722ba666dafcfce71e6d46b55e25c28c832cc76508e0960e9a65c0c5ec57b946bedc769ac7886cc710e2cc2e4589504215e9401a6669546b0db0d83c3c4ef08454412bf69103a1a57100bf7cd9383380d448f0e00f1c5ba7426b369a25da7a0db73390d21342200ec2fcaf60f5af1bab72ec53dcd6e7ed7010001	\\xab02a790a95579b012187893d8024051a7f102fd855b1e264e5832e08ecdd3b9467ad78561233320de4f97db44b9e4130afebb69d0f513442ef3b61c5d276007	1664796530000000	1665401330000000	1728473330000000	1823081330000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
310	\\xe8f6dc010c654fb9fe134b649d86392e4ca77ec7d53ce672e0c0ede5cd2ff36623860d7c4f7925ded4f51d989074a83353b3303e1dfe69fb04aefe0d1ee02ca7	1	0	\\x0000000100000000008000039ed08305f61d90ac0659289e57cdd95addb85881ab24e75bc7a828db50c86b6d212a4de4236d51aac3bfe7b896ee3c15edfb67c84bceba30d36e6bbdcd85eda260a5934e5560ec0bb3dce4824d0400e4cbb1a979907b4ea8def61b3dbc820bcb4198a0f800f6adb0bb9464d9c4ec63cab67b4733dae8b2efe452913b6c72d77b010001	\\x03b900feeefd54e7426cf0bbef8c25b267c28f9928ac5c149b2be6cb5325118e80336439f4301f12727458a83699dda3f86c7e91dbabbead1e9e9babe6fb5906	1683536030000000	1684140830000000	1747212830000000	1841820830000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
311	\\xee020f8db89e7c1a9c6b533cd244f4472187134add71da2040a2163788aa39164f625b8fdfefa2afaba46ff5c327b1692f454c448dbb1dc11e3551ac19582f6c	1	0	\\x000000010000000000800003aeb734f7f63a9e3415f231bab36bced8ca1cbb18d8e5c2eea125064fd89176c5e5e3020bbcf106d51aa90bc9977b3b54739b21ab3dfd2ac700099b1b1cc1d8c0343cfbed1012baef8a396cd1767f320bcd3579871dbe12e7529879eb7ff21f1573ec24cdcfba12ca43df383634eb0f0a7788f2a881a0808cadd0ee54f3b46ecb010001	\\x3ae3848e45e811ca98020d843c8ea4bf62851fffe371b5cfd797e34f5e3ab5fd5df232d14aa8c2e1b60efaf8a9fa9788870f2bdb031660020c1aa6a9d420160c	1662378530000000	1662983330000000	1726055330000000	1820663330000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
312	\\xf3523c01db569a7f7ba4a694461f7ded872b3fb67a31eccb0dd69a701927c2f67978b060e10fed9e77438e752d780d6273c5f3137308717da583dcd1fa13527a	1	0	\\x000000010000000000800003e0186be7b2f7d5e64757b85fbe8c375798b5916f7c744efadea9e363d4f3a29cae50e195914f75433a155defe8b6de408f508958f7228d4bc35a94fe2c028fec733092af0c431fe51fc15b264839b6aae2e89e411c546c9155b9043a0928d10fa35fa36dca7b97b70ac6853629299bb55fc0841f0f9932eab74e0036100cab27010001	\\x0eacdde14d10dac0486218ce10bfc119d7f873d6b3c0cf3bc21e68173f77410fc034b7e66bef7e85e8716767237a742558e817b09cfb5a92bad48771ef73d308	1656333530000000	1656938330000000	1720010330000000	1814618330000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
313	\\xf30ab42643bd99e78dfbf3944443ca96d187ae18c2b03621afeff5448cfbbca21c8c980406c0b7e82d0d97d482c56d11db826e41a0cca075be7d504f01aabafe	1	0	\\x000000010000000000800003afb4756241a77d06aaa05628b8b702c24c623fcc9b57b7b0d43d711f6157eec66ba707c2e76aa24049bbfca10e6ac24634fddb5633b3e477c28c4f2a9be00444fef4f2c674e2a8e399bef357878580ade522ef03b533b0c9f924f7bcecad5d7e3655edde41ac7b8770f5590d7f33fc690b5b95b7178c135526543f71b32e4369010001	\\x86361179c0b48da961082216bee53049c21e0ac606b47671debbe4d3054d16c0bd8f8d0ace4a35b22ec417faae5a5518a6dd5d17badc44a9a16507960465a00f	1661169530000000	1661774330000000	1724846330000000	1819454330000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
314	\\xf5fe35fc606f5de5836d3f9c2132c0e60a5f0795f42ea00ece6c6c798cef3f75a10e23683902fe9e0a5392147c112b99ba06a63a6ef2e7d0a1ae423b2ca52ed0	1	0	\\x000000010000000000800003b7895ebca1d2ec10b6c00f2172c671661955eb4110ea5db8f1272f9ac2ec56c8f3b712b0deeaf397dcf1620b0263a4014bd5d1f564657a2a055f0c8dd84dba6b20c49ba372b5111e6b3dc3e834353fb0702fa145070e225ec5c2faa1279b19963266decd524534bd6df22be8ddab05848f884ee51b7baf2c45dae2c20cd1a31d010001	\\x6a0f4f7a16d30782377696f91a00d298bb0ffc83bede9545b642af00331ad0d2e9798d20b32e8c434e0ac1e10ed7ed4b07049ecd4bf858ac55ab9b4c6f7e6709	1666005530000000	1666610330000000	1729682330000000	1824290330000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
315	\\xf562123c4b68ef528e5a68e648486b189e04101352c85a48596ed61ee5e17aee21581867933cdba5444494c0fd9ffb55c436365c9a9d1a058f76df7ddb0ed854	1	0	\\x000000010000000000800003a2cee63970887b9cdd6f0ff1f3960787e16af7865e235cd5c5acceca5c7c39d38fdf39b694820f9ed54eaa455caae87c94dbd130031f9596556f1ddaea2b24866d2161981a03480e090d1080796873f85735c57333043b6cee222e0bfe74d38bfeabdf9cd5662e7ef755328811ccf1a1ff3a5c97fb75f4b7d3909e6a11049909010001	\\x3b3494d96facbc9c52fcd0b27804786e3a9157bc740dc813bfb7821fd18a36113fb4abfe4dcfea0fa969da3bde811d1462128c5eb7e43edc59e56882ac8ed206	1685954030000000	1686558830000000	1749630830000000	1844238830000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
316	\\xf696a21a80949127d2820d956db18bd0acba2b2f7697e34cae005ef88caa524474ca9b485446b0ade83d340efc762ca57478520456a03d0b92ed335d740fdb8d	1	0	\\x000000010000000000800003dd1290c45a6db528b331cef016de97cc9077efbaa80310b59463870637b0e9a139a81ffdfed5278d076a21d143cdafd0e977e6f15ce24fccccd789705af015a0531f8f4ded2ecbd6acffda4a7e34014c94f7f67e7f28ea463b0e4a8e8a52cc902e40faeaa427ba755da1388648eca0df1b8d919fff3bdbc8119a9094e50ed62d010001	\\x9b171afc1e76fda29f5a2944fbf037aba5f7e3bf93ab609df66dba5ed9642f3a56d3aca9ac1348105dc989b001fd790a6bd20975a4a9e4d9c3cfca2eb33f9e06	1678700030000000	1679304830000000	1742376830000000	1836984830000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
317	\\xf7d2f4f26e026805cfeb3a6b600461ce7777b6e41716a473098b535efe2af63a58225f49fe1150001d138ba08754eb623bd7de23d78557bf5b583d1852f5df29	1	0	\\x000000010000000000800003d4dca04a57c1457fe420c44c7030d040b31e08ac33ce46dff0f0b4cc2bc3a730bb7297d290ee9563da4a39c81f26393650554e2b752dd863ee61b0b73749189c84b650388d95c9b8c683f75da6522647316e264c9498c14eb6a1b0e8d8ec78e8426d008e955d5d4fd7710c33648049577ab565f6201b3a764db6224ae73c49c3010001	\\xee123ac7485e0ccdbf12bb9c31b60e75f146167bf54ef29214796f94d26b91cc473a5ce69e47bacfcbdb5ac0f2b1d1770a8bf7337597a07aab973d129e37810e	1666005530000000	1666610330000000	1729682330000000	1824290330000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
318	\\xf802da884ae6bdf223ca2c14fddede9ba3ad9702dfa9b5be475c6be691b967da2d1c47eb0b0d4f1bc91a39f3dcbb1ac93fda369e7351847fedf29662e7e01eb6	1	0	\\x000000010000000000800003ce3c66677948ec2de42547b4d46e1d82d6dcaf5bc2b74b85986a2f9989a6d573dcedd6dcf1789de2eaf48c2bcba983713c5ec2156389c6c76a0c354f5ea3d9788b3545c72e53e22c5f32e391c778b6b16a9265f0f35d130de1bc3474c7a96c2562bf41db902da7be5e26a75c13ae4998e070cc014ae857986cd7419b9c9b0c1d010001	\\x2ba289ef140cb04a1e9efd11db76a7e319324a4599cf4a2c0605c566078dc1235e36896a8b50aaf8616218dc4cc563984502b2128f763f10f2082558d9c24303	1665401030000000	1666005830000000	1729077830000000	1823685830000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
319	\\xf8ce3b6c43b01c1738ef117c854ad2aaa76a5e4fd84d856ba2bbcd44ecbd28fd13f663b2fcf4fb3dd8ab34e358151d04742bb520bf3ca7c8c677fcdc7f747d02	1	0	\\x000000010000000000800003b4af94370161f50aeb2004e843906ceb43ca73702636cf1b8f551fba54279bf5f8a5c4d51c4b913145e185d64f62cf511005b2d3eaa3f35e2f77f654e413e1b71a525d336de881c695741843742c466902607b1623d47c03a4b0568abb476d31176958598831644000ddb834d0a9662f72595b598200cd62ef7291eb60fa6cf5010001	\\xd518ec53f4a72b6bd5ddf7628a281eee51be4c7cb6513f67641ba2120b3ce1659dd222baa438218a1c7463e14928ece6c5b8f6c4cb9c080f3b7d96df26782b05	1683536030000000	1684140830000000	1747212830000000	1841820830000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
320	\\xf8362f1636071d0f6d8be9f6172b2d7cfdf6841226a959d42dd77bcad8d15eaba5065581bd8093284fe83f1f447bc8448bfee33176d5e7b56da0a6e9de3a920f	1	0	\\x000000010000000000800003df2522fa809fdb3e8fbba9a40081432408a1f8c83a9542d6df72aafa6192a7db185ffa2691745ae68ce197a879da4e816f5e526ff132d401cd523beffa23af0641938ebaf6cd23d9fb48d420b630c88c3cc69c0e4b5e2043df2727e2f488a6669b1a50d9676cf998bed80f0dba2582fe177dcf29476c743eb48358f4aae2c265010001	\\x65f2e84592fee055d14bb6435cbf8719350357d9ff8733db6be1c2b02cdbd1fd91efd187dbf9491474b2109fdc51c1b433533579dd6568a7271fa45fadf4d501	1670841530000000	1671446330000000	1734518330000000	1829126330000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
321	\\xfb7e8aced39ec8ba24a6302b51ad3da2a184fc87509ddb1519420edace2f212003a1900f464e3bdd61174420d370d94bfbccbeed4471b7f9e8abc484fd9269fa	1	0	\\x000000010000000000800003a361bd1a4b1d5526314491c846d7497b7dd9322301ea3e1076485c9dc494dac2af625523e07c1e99cbfc22c7df7412076c4e09231e3cb8c1f1d4a4504bae62034d8017ac8e7e4d373580dee88a3e91c1b10c0aa55b6cf6ee76aa5f848e0970d4e8da22e8d5660d9f5e8d2331959109257842996c0d189e1acec3937856f34269010001	\\x3ccff68c733d0750a14e3cb497e533e27ee4b1cd1559394f5b66a44f26901c4a106ec8bc90d5ed8e68fa2faa284b6cbdad41c9379e5b2f6645a3cddb3a860e04	1670237030000000	1670841830000000	1733913830000000	1828521830000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
322	\\xff8e30476390783d294c16fe0a3f9f9e70a7ebedbe804fbe2184fc6c281f01bea1b05287269d8d4c31d59df7749edcd904b38dfc0acc7be59328f174eb4b7a21	1	0	\\x000000010000000000800003be2e5067b0c9be2a46c531ee17c2fe1e514f8e2fe6672a937640483afcf5f9b53e88b8a67d25d1ad455a48f40b3b116b89ac527babed05cb2d5c002caa024d3e5befed995c7909e55c01ca6d7ee337581bd09657edd7111be7233466ab87f51fd06ee80e0de1ed36253df2a300719ab1f49196009f6789bcab3f3e9494e8253b010001	\\xbae09109013d3d634fbba7389ee7d39e56a0244a6da5ece44894bc8a817b25393151a678dda22d63505e92f6744d6ad525871e1c1915a7f722359bccca1ba400	1667214530000000	1667819330000000	1730891330000000	1825499330000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
323	\\x0137b7364c161b45ada8aee1c0e12ae942b204a38d93f224a072e22890f2830c80caa9360275fb8b136a233ce6ac29e9b6495194267705abb300591ae43ee571	1	0	\\x000000010000000000800003a6af1fd60f08966a894eb8c45082d00f5b0162ca6424c77971f824f0b4c679fd7edb1c0ed140169a9f82aa74f693d1cb1474dbadcca37dc23e3403f2c6305a3b4919ae996d7e1c3a189fdc06c533355dabad442e819f7021c31783bcae09bb6379a798567ff3b6a3bef28deccde89ed89fec7ffc9577cecfcec96ba2c63376df010001	\\xbba718b4fef31824a815d2258c2a61a2baa156448cc7c7ee4b0e540b7bc5fa01319b68f719dc63a976f1a6d66941d8f3b4f614c186822cd29b54694cee10db08	1661169530000000	1661774330000000	1724846330000000	1819454330000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
324	\\x040fae1b24745ae6a9e52bf5f2ccd796710c7a342f375eb23b10d2116d45d9e58f2a860e70eae5adbf724201ab7536b38c754f552438c1441ed94128f1423efd	1	0	\\x0000000100000000008000039ea69b3d93d270b717257e8c01b365598f1b2bd70463e02946259f29334eabaafca50c92522aae49228b2ad84509ccbd6c0ceb925605650c100ea6feeaab00999a44cab3023efc8ee14f8c37c71477607bf0ff64756c2dda27f0c791814c349969ae7c6a13d60a66a210fa9790679e1cf5ed7451941b61dde1bccf784b590351010001	\\x89cc6ce08329d83e70114cd0a9e3cb67a92e72b001a6e0be3bf2ec6ad4e422c5fc555aa32020ae75c9da617437448e08e3598190659c0854542af56e109f070f	1661169530000000	1661774330000000	1724846330000000	1819454330000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
325	\\x05cf2ea83ab955120992c2affd5ffcc6a634c2b0fb4b8e12157d99a44eda50448e2c07c63fb2b352077fde1667618431c9b368e5a1df7e363e9e8d7f4f345f3d	1	0	\\x000000010000000000800003d59f1e135570f49fcc1e226f4e1ed0f232278cee4d379100ba889744aee11806063398f3402604f3f0d9d9a1d52a864ce22f3777994030ede548acd6956e34352585c5570321648ca5b46c0e69e1339ae915329741ccf0788a9734f35fa705b2fff87e3a1abc1dd0c597301b24e39680efa7b8a3990695e01b856c74e0737fbf010001	\\x25ebb304594038303fe7597001648772e8e3663118953a02f897c4ca7afa987f019a2207a9731957e8e30c1b8dfe1daac57a28619ab864ae3c564f7c2bd55204	1671446030000000	1672050830000000	1735122830000000	1829730830000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
326	\\x078f42fef9e443c18b8a15b53d19731f042dac3dd6eb6b0f94a258ece57687837a74d73830f77dee48d6d9892e76bb40f7911c5ff0f6b5e356eeb2a5f394c0d9	1	0	\\x000000010000000000800003cf17e5bd5357a21defdbe0b11317b0681ba4448efd38ac24ed9cf8eb27777923d75495f2d7d92b384079d78897adfc1262908ba05722ba21dc034d1aff328caa543b2a0d9ed11d1e435c3ec5c3a60fade8f31772ef855495b74c6f2951d8d626d7ce1fa069731bea545566cfcbefa68c6f7401a002ef4c30addcb7fee5251b23010001	\\xe07319a523c90206b1dab0da1ba7ea5fc73ff5f55126ba10a627b97ed47ef47eb8c18262a181c6ac8e11fa74d63cdf2444ed1118890d3cc53ee9030553252d0f	1672050530000000	1672655330000000	1735727330000000	1830335330000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
327	\\x087bcd09c8316783f477ab7c713b732b8a6005a57b432f8e521b54d4b33fb469de1ef33405fa64525c0b250f2c5257575e8494e70cff474146db63b33969d6d0	1	0	\\x000000010000000000800003cd3a755a1d1a20f644461400c7100ad683661ba019d6912cd2be63b755b1140710a95d1073030ee919980aad55115c9f876aa020fdff1ea98e446c68021be95ca48a257ef265c3155155e6079f3a4db81e31bcba479ee7468e114f5b1870c60daf75c76d74dd6105a134fa8b63ab104cb9f2535703a638f15411aafb1892abcf010001	\\xfdf63d6e3c24d9843cd6c1ad66dbc5b45ed8b978ff5ed2a10861bf758974e377bc455bc567fc9acd8115ea258923b8594433c0753e43bfbe25ea5a53e966c90c	1677491030000000	1678095830000000	1741167830000000	1835775830000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
328	\\x10275302a41d0c5e2f9893795766ed0c9de6e381f1eb0336949c66ea99839543d955713af0a8932d062af95a10398ceb78ef45b54ff05d9b97a62f926c6a4496	1	0	\\x000000010000000000800003ea5299472dbc1a5d510026137ee6f41742951256fe5e405a0524b582c027e4956ce1a149266a339dc47ae3021866b9fc4627198b6dc42ad3e7a733b0bc9926c1a6a68874290a9afc1b7272d4f64f6d3b8ece0ea7d9c0e743073dc2b8c0160ff56f9751f1c801e72d20ce68bda4dc90fa50511ad45e26bab5650b40d2abf8ee9b010001	\\x6a150474ad139fa099b87259866e9dc3b8672a3190a49de139f59817f3fc000954f244ba4e336740ba8dfd916405c6c682f32706ee45ea9377d567712412ec03	1663587530000000	1664192330000000	1727264330000000	1821872330000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
329	\\x13cf10ff69475f00abe1054230333df003377a7459ade0a60097465a596dd48e67b5553e02e4b862d6a9f2f52f2ce3cc404f8f95f16a9b4e98ac8e786bf80e3a	1	0	\\x000000010000000000800003c7c44aeb6ce28d43adea462a3e9f352e4a924235e571009880b3aa8352de7876377df6494cc9578e2d0a03b2c9d5c66b1d5e8dbdbdfacfabb817e44f95d8ea2c506f4591f1c2b401eb72466a1ae34c676aeebe9c275a68145e8c82271e98c2ed7959ebc0a26e9be27cc5406e88d9cbf479c4647c66b7531676a43f8d367efee5010001	\\xb7e10c4f2645b1cb271163d96412cd196edf42d032a46c20ea413cc808a3fb3fa4f149e1f5f73e83c87b95a76dd8c75e97ab7fb2a2be361f678e1bbb91005004	1682931530000000	1683536330000000	1746608330000000	1841216330000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
330	\\x1637b858db854eeb65115acd98eb4b365e32c495e5a53b451edf143b273ddbb061263ea67e11757fef465a4e489d94a76c1673163acb610ce281c93cb2f58909	1	0	\\x000000010000000000800003b4b54655a9eff3096b1e774647f72d8a4f02bf9c4f42132f4a2864aa60a2cc6b4107e8e6a69fde07ee01cae68531a84e8616b710401d2234e91d95a44e48b0554e143e102619ae811c8888fdaffd1062babd3989eeaa59e42611166f618dfd5b315b150d70a736d15ad914e0cac283fb54dc2365107545ac415d7a2371fd019d010001	\\xdbd03705fbb2a06ce7488693bf3c704b2fb479209b079ea17704c1a32dc58f6a68d19df8c81994851125493bca44efd2b2b502e01881d3e7d0a9588134a58e09	1676282030000000	1676886830000000	1739958830000000	1834566830000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
331	\\x171bc3f9679fdcac444d731f19a6e3679cdc1309ecdaacc1afe0d39a53429ad80aab974bc080b9f63d2aa06cea0507fbd982bcfda5f1cf849b656c36f881627b	1	0	\\x000000010000000000800003f60b7bab883e44041721977b9080e026aed3f516fc100a4e82ef51aff0716e90ea48bfbbadc2b58fff6bf4d70a3afbd090d7e6a703f07715a1475c2eedfeaf4761eff08b7664d932416c35a46b7130eb89297e1421d589873b86989acf9b730bccf394e09fd24438fe84408a2862ce48ccfa67d251e5fdd4d2984efb0a1aeef3010001	\\x7a94a9daa24ef887160ae3aebd84ab3b9cfeb367d500aec137cb0d08c70c1d8581970c63f353078dacd1270b667fa3a9ab40129cdaf96b029a2e8e41bc423206	1669028030000000	1669632830000000	1732704830000000	1827312830000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
332	\\x199794c4a7569670a1ad9c5c40004e3aaa2be81d0062704786f9833f0fc0a653eb853954e2e2bba6fc0dc8273f0a4105b18ea9d0ec40cbb19f7ed9bb249b855e	1	0	\\x000000010000000000800003baee76b612ec5d4852786fa677be721dadbd147ae2350fd07e0116f7ea4cf441faa5a09899f455c30f470b824657b4b2a82968801eb4bfed2aa039d6e8126436418675a0b744d45dba949d6a3902e3ef8f469dccae6fcb104899149ea300590915fcad2dab1bd71ffdefe7a608b0d82dea5da0f6a7353969815fb72ec2ac94db010001	\\x43fa37a5c872ff499a0ffdbd6085559da658855f78b5a0fc3042a950dc6aee483f8a035c9ff85af4d2786957fb8d985124e10cb6408559bd1021ce1af5faef0e	1684140530000000	1684745330000000	1747817330000000	1842425330000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
333	\\x1a97e09c1cb9dc835a2e9ac7a350bd2044faeefa1efb5e33ad1b8889fbdf65952865d7a0e5609bf577a13a6475238ffcefe7d814ea0cc30fd95d15a8f3eb98ab	1	0	\\x0000000100000000008000039c467932f94a9313a9dab6e1efc7f110e55be7ff2f0c9b1cfa49a42be45f9346de078ec058345008b4572e6957c974cc258642c7ed34169763b61897a2b8a45e08ed7b57f25432aa8d888dfb85fea1ec0e60db372cc28e6f3bc6f5b3bc986f7371485939fe703e068897e5fdb669fee6e41045a024a9eeb8f6201a9b01772ee3010001	\\x254b7a58794b143e5e6f5915cd0af74d3d6303b7bfdae33c4254bb8d5c39099292928ef6422b4db40936e8f1fc8252c8beb8a715e9a8af279ed3ec528d119f0e	1681722530000000	1682327330000000	1745399330000000	1840007330000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
334	\\x1b67e33d094558d1e406f45c0a4efcf844e991db4ca09a8ef087ec0abdaaeb6280d7da51b635c1c2da00364b8513d441021209b2878c3d3ef8491ff32056567a	1	0	\\x000000010000000000800003d334cb826244907def9629b2b7953a45587aae7f0ac3db2d8678c9c27197ab6b05af26c7a5f498af43a3fc05dcdbd784164171fdac73bb26fda032e42b649dfe06900c013d9a72e699aeb954272ba2289b696271580150e22176746112a50e156747563551f23d5c965fe969ab67e8f7a13b6a3d63cea0b07d413e920ad479f5010001	\\xd9cb6ed486edd347ddc99a6c7d456b3008ab75317448373404da75c706f4f95606978a38d5f68c764e7f6c4b92dc9f700ff6f82e511770b21451a43726e3cf01	1655729030000000	1656333830000000	1719405830000000	1814013830000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
335	\\x1b4fda296409d4a842a06985787f6961c1c73c593094d59727f515522a3a42b59230615167dad880841d7f802ff31e4318ca751f62e66a0b6cc7aac8c9d1e050	1	0	\\x000000010000000000800003b3244d3675783d8718cb363fc311056820fd4433201075d6c72f6999954a93b07ecdaf787c8a50075f93aa52f0f50c8701418bcacf672021f622c129da4091fa778a384c5f5086ce727f8d758395b71711344a82869fa32a02e31fd45b85c49cbf2fdff0924d3f6f4b30ff2932d690be4dfc93fc96ca57981622c345182a9c89010001	\\xe647543bec925ea67e6d618ccaeb3590915104ac30e2a28b13ca08190f12fafb981c9de16c7792962685b7a0d34139843124e3b17be6cc10a7b94c49c94b840d	1664192030000000	1664796830000000	1727868830000000	1822476830000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
336	\\x216b62bd773dc4cad94fd655b30080cb6211c7ee9b65350191d6a7401b0b1623d94a430e41fea7b2f46c83ddb877e0dd4d4fcc22ed59cc4d23f3b5f44c62bb35	1	0	\\x000000010000000000800003daeb26146e6aa4738f8cf26024eb1e78d895285d7b64ad0b8d33dad95006b1fee9fd675faab683127abbaefd95c7b35bd9d50036ed3eebe5c2b972943c3fc773b4736e4935f015fd0ca8fbef84c9c9711bc1dd4bbbc775b68ae21cdb95c4e38318419609b915589ee2dc09e05356086963dbe25324bbc563dd2bf85f394d931f010001	\\xeda847fad76991cbc4784d6e905aea6e7aa1b8c3afecfca6973469bbd9ad15047e4dabdea284588bfc287795d08f9fc9c08849fcd2bc25e990a1da1743aa0d01	1682327030000000	1682931830000000	1746003830000000	1840611830000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
337	\\x2347e05feb3e0b04cb09ecc872455256004e83d34a44f7e641396f7a0b424cff7942dc67be9bbd17de2b10f8ce35bc9914999a17484f304903c90df2aca0d3b0	1	0	\\x00000001000000000080000397534b3ff04ab8f0fd017a4cfbf975930a5a3332c15ed26179a518fef226ea56435b45dfecd9fdb7a386335b0d9c002226cbdc0654a9695d6fe91ec527c65c0a8e280964e3b375aae5df54d4e44eddd055f6670eba859dfdd7be3ced17fc4686cbed35dbb10ceabcdc26d94a02567e7898f455bfcef062630688681260a431b5010001	\\x7d7cfab45740698c2a24e40d0f148c1dd082457034193baa0e49d4ab7f60e26c6c440eab5f7b1f636909c924e215fc22646eff3bead54676dde7bc48fe8f3d0f	1673259530000000	1673864330000000	1736936330000000	1831544330000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
338	\\x2703d8c0f798c645f8ba1f8424d28e73d5fdb55bba4ef9350e3ae3e7467fd60d2df29ff1a7bd0b0283e66f670526cf09660b8c880f8b5e14f8856a2d8f363f31	1	0	\\x000000010000000000800003964f85bae42b42554539a0bbfd2394648c2fb66d46342367ea498c65be54b2501a3c68b4d56cad86f50e6c0275412a3d87b6877006814d8c49d1871aa52ddc352a9b0965d8e7e8f124ea3acf768fb2628b956a5c48696ce4319586bf5bd77bac4ae76387cedb4cf7d4dc9f124e1ce79aa2297640a7dd202b708ebfd4ee234575010001	\\xeecee6b10c182dee1d3ae10bd3c996cd0fc3e24e43be2b06ed39350f04289e8b545b61c6fbaf624595a7689ab15678921384f901a9f066e0e33b929258471d02	1665401030000000	1666005830000000	1729077830000000	1823685830000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
339	\\x282f44ae84a78a0bab45c37d3ff1c0d56c0b4b3d4d2ba0ce94ade0e824661ea2aba2f25d8b1cb4cf232241e852c7fecebfbf8737f00ad6eee7742534758b4a49	1	0	\\x000000010000000000800003c66e0505b99ed29a1057bad22544fdafdd1e270a56719816cd0a76dc424e926241a8a10bb34716b4ea2129f0efb13f3a653430416de591028a1656237751733b2acd07c8f99fbd5d050bf85d4551c26547ceca2071d0601a92b588542dbf8f2c6b10f15545f414bf4cd374112d29346a340c9991c162231f2cf81d7d2e7b7ef7010001	\\x1a25aa7234b9e732c0e5d9cbb933cb9ccb790cda3fed33b691fc07baa3a6e012d54e09631ca620284b9abe5d65618f362e74ff8172da64f37bdd2ae64c2a9703	1669632530000000	1670237330000000	1733309330000000	1827917330000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
340	\\x2c1756a94376c244db41ad93400a6ce28520319299a2a4b4d6f1110b19c9ef57ab8a4d5f274026056bd590959153d490b9d66c7db31ff0545c2069fad802e8eb	1	0	\\x000000010000000000800003d04bcd69263a81895cbf9f0c959c51621933a2a5e7bb287ed315f609e252b1a5d963868aa8ad1aa7439ef6a0f164a901aec055606f21405013d314b6d16646d6671660c566e4affdf41a40504d2bb1cc025dd7440d81301022791dcabfab361c94fadd6fc2226405feb1f845ddc8f8b83d685de207f69579910f9990f96fb2e9010001	\\xf8f70ddb1b912ead75a7efe18744d729faca8b3d6198ec7cd80f8c38a83c56317d5ec75fb6592639d49081e3e9d3b9a9d0bf3b31d6d8635e86b2a68549b72e0e	1666610030000000	1667214830000000	1730286830000000	1824894830000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
341	\\x2d5fe90c54badbbdd22657c7505d090ebc893358c035a1b0c4a092e352c8f38540884ff6d43a7d2d26476aa94d3eb271652f76f1444971400305a7d2a967796e	1	0	\\x000000010000000000800003d977f147d996062d3fc2cea64a8bcdd65ba08824e0dc84c8a7186dddcd180c504658d161e09f311c1d8e9caa919e1bf3e7775ac8cfcee4bba435922b6d71fa167e039fa4265b7e47d9b13ed1b5ab856a7f0c9083819be5cb574a951c0f97368caa79d4dcb9b670d358bb50f18eb5b4257a5dbe0508230f7edfdce52e5c2865df010001	\\x2e232f316f8494551d100e32a3110f8942f49a85073b64b87c13ebf4e02c5b7039ba7ae582e1d9df0c3c1dea65eaffa44a57571ffd8c0f235f5f8cb8ae256708	1675677530000000	1676282330000000	1739354330000000	1833962330000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
342	\\x2ddf8f48823e41355871388b88b7a6e5267a53046a799f58f3a6ec8f296e9fb7e024e82ac8fef5f53d64c20fe595df267f08e47ecc5d3dfd4a88839e5b77a981	1	0	\\x000000010000000000800003aac22171301e1d1851ad55c70a14f7f926e1389454a9f69715507907db5d7b7c5a744c232e76b1d8bbad609693a3d779c963e18be5e40beaae8ce8b193fff58a698ffa4d9ecdac8684eab5e856e7723b57fbe7f322429acfd27fabc438b287cce09c177716be9f1ad0dce1f68407b5811c2826727eb2ccf9bcd90efad2ef0993010001	\\x13243447e98889a7ac4f8576d814a37482a810d0ffb9dcbd4be39905673271adc6d46a4208f64e53c1834cb79a57c2db9e51a41b5471fdb99692d1932a3e140d	1658751530000000	1659356330000000	1722428330000000	1817036330000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
343	\\x2d8b31a2567dd4bbb94daf953a99c0fc3255a2b5f096077e4f8663f05feff2fe00bcbd8b902205163577a36c527c4673d98b89de5bdae94f31a45f4a9ddd084e	1	0	\\x000000010000000000800003ad898b231ac13885ed5f3444414282fe18b30c02c5269ebe52196b983fc351003a2bed5e14a2c32105576ae61cfb1081d08f2a90e12e0de87c529ff5f65676de83c6e41719257131d906162f684840752c46d388cc9be8669f45dec140040dc3585a9026f45ebf5edc7ce0d669c0859a92c831f925fd112d72f8a51eefe54431010001	\\xc844db5c5ff221f8431fa5671bf578b1675570df9f3ed3226eeb98a72fd675f69bf3594ff4e38de304fea50d75b7cfca05f80f9857a25bc3889feb020600f90b	1673259530000000	1673864330000000	1736936330000000	1831544330000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
344	\\x31afab11583dd0820cfcd298ea30fce28bb6b64c5c403a9f9e05d62bbc0c995a864b02b6a688b3c4ec98c3a88dfeccb02cbcaa534d8b6b8b76e96f60e8e3f4fd	1	0	\\x000000010000000000800003b929a17605ff2ae192bdee375daef09ec89061ff4046db8869bafd307195dff974c6990098b232fa7273e15067223083dacfcefb1b0993c1114809c4b4d310bbfc2cade4a8cd1a78cba81511aede274ebb5480a89a086f490c2286be38161175b1b3854426f3848ddffafe6a091c0ca6d8ab14224951056f8e15b281230d2637010001	\\x3f03eb7ff87d85d93bec0b89e2790bcb1324c6816413ac1ba9487031951c9874ca994ec3a7659a8225ded27acf9b4fbd942bd88c97960fb19c12ea656c044e0c	1677491030000000	1678095830000000	1741167830000000	1835775830000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
345	\\x3107fa29273b8abb94f7e9c9e644bf39afcac67168966fd225a8f6fca26fb2d53da60c1cd9ff5cfa635b7d5f6326d1d78de8c597349ea9fdb2362154c4a6a925	1	0	\\x000000010000000000800003a3f7832e509635337c45256a731a0fc4ce67463c30c0f621a4b506701cb0b078760efc3515982d14bd95bc48372af16eda2097d19a4d8070dec846ca0fb09e41b6935b64ca76ed509b0ea346e0d7067e69b5b150b2df715446e835b565a9c9160312a11efef361bc6a4fa859894a2aaa1f9b571289ce24115b8c8b570289a15d010001	\\x50d26813b4d92a49b6ba87221253996d8c5aea7c2aed9f346b630b30a734be694bd3ed0f56d0ae865ef3871fed800285b193b3dd593f21e056c563c655bea90e	1679304530000000	1679909330000000	1742981330000000	1837589330000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
346	\\x32c7573cb720e605442ce9ac83727b3df9907a61572a5d127c64736ebaf2837a2909d8226a4bffb1bc600fb3f59b2277d9f543bfa9cd8d9fc562b8fc5eb679a6	1	0	\\x000000010000000000800003dc147eb1f102f027ed9903b79924e50de3c50acfe96052c973aa89ce1f918a862df22f6b15237d9673feb30c5838b50a74dc5f4ae276639bfb4344d9399c34cecd8dd5e5ccb520014ca932968ddd2c495db4a4d1eb6c54e062bebee58ce90ae7db49e4fbac9205720d7edffe60da195fd8933ae3882c0c5a18f0ff756b213c9f010001	\\xc22cb0b20901199300c2ffdfdefb62191f2959a6b0cad5406e21aa6033c1fbda8f05677b80d2a3a252c55d6d185de23cb7cd75fba64701036d6f78fee31c1604	1670237030000000	1670841830000000	1733913830000000	1828521830000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
347	\\x3b2bf128601d102bd7879e2f365c347b725707ab7148ec664ab9a7249a08d72d9b9f196f90ae061e4e8e86f9880de8640aee3c35ff98a5e5012edc71b3eadd4d	1	0	\\x000000010000000000800003a65ebeb439a482b7367423136c999e165915757160f4f4dac821d2e53949485a41bd8e56c8c93cc93aea7392e6a3a048e434cb072ba5ec1c6858aa069649663228cd98e49835bd8df3fa96fe785154e76a95e94667ca60575eb338bed2f0683cf8f75cc7ab522816fd2ccc465a904444e78e5a90779ab1b09277466844751cad010001	\\xed46f8097d40acfd907d1effa414ddbf375c25003397fbb088db8c4f3adc7ffa2ce369fd7bfc4f5d960f601f3b16b6e2a45db1d7e3db4923a0b1a35b1170db0c	1681722530000000	1682327330000000	1745399330000000	1840007330000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
348	\\x3f237b72b80ce666c2019b9c587c6f66082e157d57753f0398fe5e3fd34a567f38746d9f3e1ebe87ac530692bf3bc1341d647c8f7ef5239efb624c9dcecf7e4f	1	0	\\x000000010000000000800003a3dbc625123be870a0187baf92f93812c9de5039b1373a545111cc0a8335b63c9b6e7f48d3aec053bc01f516c0ded0433cc14eb3b8304ce75213f383811034952a81aa3505707e76db75e07628b3aa6266be3e890b6e4d22584f8c1e002161182ce86dbcb39902694292f46acc15d93e89dc96a763fe56b617a45d69468258fd010001	\\xc8b73813608e67e86b5c15f878c3e6ca802cd8492e1a84db5addcf6b9e1ba970a13ccef7b80e05baf1099d518863355ebc49f8212ce71e959e970e119920f309	1681118030000000	1681722830000000	1744794830000000	1839402830000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
349	\\x3f0f854ff3ff6018f2ece3dc25391fd9aec52e3aff734cba09c7f2dcbc71dde0352c2c9ea17404f8dedfb4b595795c1cc4e0b70fedbfa72413e60f840d8febac	1	0	\\x000000010000000000800003b77a4be16a7ffc7305391e09f355ec2f402666e1c0648e4c2523202481147540091db52717b4148ac61137284675cdc3d13803f6e7250c8bddd42f324f453f4f650641be99668ea44aa5bb5215dad17573386c3a9ae929e4204c8c2b8453d19624159be758cef446f091e495fb091aec1e8245ac7f5887ef33651ff72262cfe7010001	\\x883be0a8c9d843efeb3e942ed6cd754412f04f8d70d0fa023f607ff2700bcacf7c63dea5a7e8d8291f7dc69a6f40653fb6961c038e0ff821a6512f91b78dc70f	1657542530000000	1658147330000000	1721219330000000	1815827330000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
350	\\x3f2f6ab7f6736f14114afda35f6c417e13a764647f68b36abe219b452264eeeadc3564bf4dc4e2d0849ee96c7e0573b8724a63e2d78b15206ad742e289478fd5	1	0	\\x000000010000000000800003ec4b8fb5221cb317d8124cf9eecc6014bb79eef85f594a53ecafde8ed8b4966ab84ce2d76d15db3c1b14c8d65f2007ba21f8cff9ca906654a07e03fabb83304fc7c7dd1b7263e44d64d8138b325ebcda9df90ed693f4e7dc473760c9dbcca2f6e775a6088f5698df165830e0c60367e33bab5d04bd7cbdc33ce18cd1d5e4a823010001	\\xb3b3b7bf0596ec712112bf500a595b760ebadc4efa4a30199f0ad57074848a2ae4f7a4f6bc70348a88d3459b05782be3b8a34586c3247f19a83ae44130daba0c	1684140530000000	1684745330000000	1747817330000000	1842425330000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
351	\\x421bba8b5f1755a2ed6b43ea336b6d831e601b8d04b2b9d552e2ccbc256dac92474f65055648fe0dee235f38692d945725194d11d8696fbd33b5ee7a894c1c0c	1	0	\\x000000010000000000800003e86d8b8945bde26ed5e4e9d69d951ad735639fc1060908804fdd589f61212e5a116bcfbab3570b1327a67cfab40b80fc1a1d353aa30c72e76bcc6b88d8d6ddf7d4a7e178dc5f63d8416dc903c0a7984e92870e22ea4ddefd17b1ed0ba93335e7cbf2005fce635f72318f0629a4964ed009b89ba3ebc165a3e2f4f1e55ad80f03010001	\\xb08ce96b05339864945dac457fbc52eca4997907aecf468136be5ac090ae182ac0c6e485b5a411c03f17ebffe7a93d8e91a30505827d7c6e0e6456de2d7cf409	1685349530000000	1685954330000000	1749026330000000	1843634330000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
352	\\x4273c6458f7e42873a9bfdcc22820f71788e88a8188668917758ba48638970a38f6fc351ed6cfed173e19fa807a65c58ae02127501365c7bb3432066be518a88	1	0	\\x000000010000000000800003ad0d2a081072178ca8f865a86a1315505cb280b984d52a32e5b2aabd21712b295bd5c76d40458a884c860d6a253a33c57a7488bab530421abf0c0c33455aee24955bba59d4f0b72a52fb1bb9ce61979c4f83daa3176db18016cf3a4d250cb3b6d777588b5e008f840c175666ce53c00acfe2a6c88e2dbf479a44e49dc52177a3010001	\\xfea0b0a14082252db649b3234da345a1806d14e5f0e05d6dd4d4f22ef360103009352df25ea67106ea6be27bbd9a40976e312cfe5b630e7cdc709a3d72a62104	1674468530000000	1675073330000000	1738145330000000	1832753330000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
353	\\x424b728de8f231e113d76d5742ca0d908863b05e1bbe15ad02a1cd14b2d0e53a9539399126ee60a3df0143bbb30718c48b80ee09d911f10e90d1a180069a8cdd	1	0	\\x000000010000000000800003faf4721a574877b76b69e86eaf0ff162451ea2ea18d34e6113df9d734d4e1b820f02df57ee51e77f4a5cff8ddb51221e27ef7f6b9650f623e83df941c2e9bf88c40a7ed3feb5e6746ac612f160c877bbee8d4c61eeef62d5bb09c3831208f819da3fb6910558eed79e439139b430486022e9eba226637b267a4693fa58e5d83f010001	\\xb96e45e3e3f9e91a718dcd9160827dad8fdbbfcba3a60f1b145bb0623777963ceb35bcd3fce505cca8c22555f082b9ca2144f3028187d95654c87f735bbae301	1685349530000000	1685954330000000	1749026330000000	1843634330000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
354	\\x4ac389c4b6307422c558fad5f469a8adfcb5c9835ac789c062dca57ba4e7e7dda5c498c814fe1fa0c0787a8db3028e380f65634f3ce5308abbed364be9b284ac	1	0	\\x000000010000000000800003b4b8f3d1fa2885bc5d51f265e4c91235800c9b806f86edeb06b1db291b6c986c5431effb133105fe8d457b76d2864496eb0fb4e948baeb1ebc354651c4179fc4c2175a4b703edb393bfa7d024431cc9b22cecb16ef2194759b219fdefd4f7be4bd8d58fd63768e19301e37d3ff488061ccbb858cb9c278341f81e9ef1846e3cd010001	\\x4f25475de49219ae79135643c42c5444bba0aff461ec3f983a513ea199c77df3ae31272d0c7d789ecd78e6172ae3b60f4baf7663b19c9a194c6e37107120510f	1676886530000000	1677491330000000	1740563330000000	1835171330000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
355	\\x4cd7ecc7b9a02b7fa35f6565f0a932d484fad578ccf71c6b26d0bea6633b906be6d756d519808902e45f75029919a2d5e73b9e1af8cf75fdc4b55bef465fe59a	1	0	\\x000000010000000000800003c4bff7a78175554fcaac3746f020658cd54be76b7bc0fb93d83e9d5056d6cf0da018f24f5a577b0288968068950c82021f66dd03e1a220890d18faf651be77f7fff1af1ff36fcfd61b2c27d858e7e1367a8d7e9727465145730cf0494547c626e34649ec3a2991f3307c3851b3715cce220922a3a6130438d9632eb0e778744b010001	\\x01fd4b5abb21926fc7771c96003caeb2baf2fca13284779f46b789a7f82dbca030bc4441a1608aca21e5f2ff3c37ca83ab6c3b6ae9b720c803d7a9dfae306e02	1686558530000000	1687163330000000	1750235330000000	1844843330000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
356	\\x4d2f4c8f12c6e958260a111c9d36c04770f896aa9bb641c23dbc1b3bd3a6ec3944a9cb06e9f87edcab8d8f911e104a3d1fc21f65dfe20cc76be50984e91e8569	1	0	\\x000000010000000000800003c6c460beaa9f4917973f32a86999ad5724ff29023d4f08be6bc3f3508bfe6a92865fd69d33f457a360c2dd5d4e2a971c1c428240e6fc77387d5f50a2d1f93f4bc52a9e042b8693c762d4bded93251efd3a3913253468dd48644a05846e21b230923b0a1be8aef87242d888e56f4e8f8a8ecacd80cb8b1a90b07b21141cb7a681010001	\\xc05c854fe62a4068c1313f24e526e1295367a4e338feefafcb38bc8e8515be96dcf43dadb0bd77e95ffed26d712d0d3cabf69c3e38dbe9ef8f280b2edf61fa0a	1666610030000000	1667214830000000	1730286830000000	1824894830000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
357	\\x5c6b86accbd699def517a5174c05a4bba10eca19520b77bcace8d762a65693bf606674f56e6614ed49bf2d75304f264f76a9ab7a518b1eec668fed9ffcd7fb71	1	0	\\x000000010000000000800003e89276fb506db6aba062a15707c91adb2bceec69f316926089992dfa868009935594c7247330f7c2cc3c6077320504b8532a21eb8e65a20c62e0d107c6270e6fdc116a8ba6ad969236e36d631fb5d46bb7994ca3214fc14aaca4d2e3e45d1e0020bb01857a787efadf2272afd03605009d12d386963bb90e47fdc59ba438883f010001	\\x5b02419db57b8a1fffbab2d2b0ce2b408ddc8a8e6586bd2d59fc80777112ed0c466910c8d904dede72ff2aa416dfe04764b12ab031c07f8c1ef0d4f56acfb30e	1655124530000000	1655729330000000	1718801330000000	1813409330000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
358	\\x60f316b0521ef99c1cc7106373cf437fa098e7e4423d33777d7e26a1aba3cfb01abeec3446c4c3deb219e512cf8281b303d8cef91074af4428146754be00e475	1	0	\\x000000010000000000800003be2b95b27e859aa37fa4d85080decd0ebf061ba6590c971a35b6bfea6cfa388cb11479496ef5e5b1691f095325242bcede3ae67148c76a856052e4ed37ff16d80dba7f2a53c79ecd1773cfa3414ab2d30267743fe28e944db46cb7b8080817bb70a1cbd981366290c4d72fed135c638fb3184bf415c535bb2746f96a0d874e0d010001	\\x8ce00618f36cfc677baf241b73a3feaaf1ea5e3cd850271480ca41f4f36cf0f85ca5bb3c0b7953cf39a544acb8dded350452cfa819cb2b53a3ea0bdd8cdba30d	1656938030000000	1657542830000000	1720614830000000	1815222830000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
359	\\x6123613c0550219c83fd44c95c4f080dbf0351d7afe6c6c0fe385e71c61e6049b921c417bd282781f1e1827737c5a2e4f117cb03d3e9929f05fa386f98104356	1	0	\\x000000010000000000800003a09043c6a86aafe67040210f28d31f2953b3e9f4e29511c2831fc8127b09f87b00f8f438d75ca2dd1230386d3d64307ef49e7da99ad287214f496ec8eb78247b9ff15b522e5da39d544bbb2b2c6274d2516b89a059ec0e487b692e6cecc42f5172a5c6c135df93cc4fc7df2584e3c53948d22a1ecbc7c8c6c8fc5b9e51d87961010001	\\x3508e51565126f09b9f2771e97adcde0694a2fcc08492b43b00ed100657d3eff562e397e09e975419ec4faecc4eeb7196c154e45cab672b7b5e4bdd45473be04	1677491030000000	1678095830000000	1741167830000000	1835775830000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
360	\\x618b87f5a256089e09a11a87fb6b06b5e2e34b70f74c90e4c3e1e4a937797b8ede79eb6ecad85e33870c8a614d06b35059ce2cbb823842b20f64fda8f3f76513	1	0	\\x000000010000000000800003e38544ab64388c64424362c803521b6f27ea716d95bd35c58274b347a2b8f53c2a8f4067e45690d655c4b6207b4a2f781ecf3b2b0183474aedd47023a6781b6ee2d15a87fca356a9f2476aaf76701057d11ee5a9053013b07efc95cba45b79ae969250d76b5e179208a979e3cf1bf4a3222da6cc0806e3a4dc95d4fc4ba8949d010001	\\xad750c81c5387b5399a0c9c56cbdf744bcf78066eae5f8a75294b407113e24f931f3d0040b850310b0fe54e33e0bb41054f1203e1a549c54ccc3beedcf779d0c	1683536030000000	1684140830000000	1747212830000000	1841820830000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
361	\\x698737510aaea7a69be6674e5fa9220b39554a64d6d903fa372d4829887c8b63f419864c571f745d61e93f3c8741544c4d764ac8d518526a750e5276d3238c61	1	0	\\x000000010000000000800003cd5dfbc413958d85bfbb36469555c35ee9cd40aabbe96019a5b5b511e268595145e9d77060d58d9b54f2961f7318dfec0f93b72490cc552989bbebf05609bc20d1923dbdd5c914f2d45eeb1f16def2282bd175d2d3b9e691941cbf18a526963eca438ab92cb13436c12b782884fd9aeb62f756c4781af2b6d36da992589b87b1010001	\\x759a3512714bd7bd9ad2dbdeda86481f0aa5a3c88b8ceff6e31bb126feaaf9a9ac002cc61c711d53164d7e54effd31e99d448daf5b9d53fe1ac72628c859c10c	1673259530000000	1673864330000000	1736936330000000	1831544330000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
362	\\x6e7f6baf3b1fb3591070d1e1bd17b45ed66022c2d3caea230dca29e6eb27fdafd20a9f921f87248124f3187c62bc36e8ba15af9008f8d740099cc2aa49124cdd	1	0	\\x000000010000000000800003966bb2079da7fccb8f1e56ad9e9469e4b88c2aeaa96dad91635d92b9fda470b4476553cb054bdb074bca9265aa5a6ba9a4f2e77166c30d5f55e857a1a7f98ecf223bc1b8a8cb30ecade3cd88fb7adc353d806022b8c4584017b83efa748df1d56ecda64c5c1ef0b8a8417b4a779355b2aec4d136c74b27ac44ee6073b7d5c389010001	\\x3dfa8b3a3c18f93d663b3b4e9eb5c4f23492f4b09e010603c99df1c7496c35ade82e7d4dcea9a94a3cb648e578ea6de0c769465ee2db626f2f715e8de08f0b03	1673259530000000	1673864330000000	1736936330000000	1831544330000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
363	\\x6f57a0ba7249688a61160c94eefad82807b1e3a661e492915c21250c0b6debda4ab306076900375fc749f8eda5602f0673086b740845206b975b25b3756dc9f8	1	0	\\x000000010000000000800003be4de54ccf51a82d30efe39544e60b1a0ed71d08c7c92c7c9e4e36a1745df07562d084e76790d520f549809332e8e0c24c2b68a656423079f45e39f7e2819c3018850aff10a1cb73af21e3970821f40d420149f701c67ef6219df7f84a650154bc59bcc2490dbc0f5a39d8b41249e1adf627424cac042c168e793926dd3e5a2f010001	\\x9a805d445f65aa4c3004dba7172fe16c57a00f350cc319b23fef87d8654df24fe845cf9e6ed72b0ac40cce11085b7790a15b47916c6498b14a51b2dae5fc7107	1684745030000000	1685349830000000	1748421830000000	1843029830000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
364	\\x70e7ee373248d9e405f4534cad33a3bc907daf4552526ebfb51472764e304b1fc1c16d4f24bc7d1c2ed16528b322756040f0b72c7830de011fe96d24b46aed0a	1	0	\\x000000010000000000800003a64bac5e0164d6f1404a4f4e2e28f08187c254707ad712aae3e3356f0fb5ee2d57133508fb01fd1a01d29c38c928b9cfd74d0da20dbe95ee7aeb2132750df7d733014351f907cc7a1d826f61b7a247195f361e6f445b7a60174a78a385af1870c04714ba49ed7fbd3eec779161084181f78a820581fa359a098be5e4ad2c98d3010001	\\xc5e98fc743c9f1095e85920faa00f12901e32fb3477bb37de77efbf5003f66f9969f77ab7fe6ec0c523f6b0a90b9e9b520e3b6e727075f2d1e0a379d175a2502	1679304530000000	1679909330000000	1742981330000000	1837589330000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
365	\\x70e77ebcdb2b7030c938fc519558ee1bcdd9c1457f1c02c7b05feb09deb6caad3b2a4e6a7c352acc84da00fd682c94b0f14e5a207d7eabf69782199e8e576a48	1	0	\\x000000010000000000800003c65e60f827b6ca931c629064a9aac1479414824f38f1aa73d1b61174271fb92f937c37f4b50944751d0445e07025d5c40f7361a8a28246913dcc9a3c7d896f4ae2f39a67b12304e9c711903bc7621339367a7fcf0b9a993db0c043992e89110293b6005a70bb83b7cb17bf98dd2977483e112178db8e9454dd3d78e843a9457b010001	\\xa99882a04b6d9307fc4cddbdff9935b52b163f16623dd0aaa90603dc72484f02b851d52b269b50c13cd1cb2fdb65cc9b208e4d8f29a7029c487296654528360e	1676886530000000	1677491330000000	1740563330000000	1835171330000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
366	\\x71cf408fdd5c0b53abd6effe8caa254fece0cc9ff42b34ebaffb99b7fc2103e53fe9dc96dd2eaf6d74d577d823db92c32e1c71f3ee45e64eedebecdfbca86f7e	1	0	\\x000000010000000000800003ac081490fd16caed3f4c1dcc202d7f844366d94add640d0e568ba383e7ad829ade23e8bd7f875d5530f2749407f5e6ec9e9bf974ade8d11cf73001d8568fcced715f3f64e4eb01f209feb8437b4188dd946498183a30635a8dd4e08b6c7a38c0eb6c587146d486c459b259b582465d5e485ed57f0f34d724179b3d5841493d0b010001	\\x6ff2dde3725b1c8088038e644367834f517f7cdd0c0e65c2f146c63889d41aca0faee00f2e623ccd828d1a3abd86916170f5b4a0780f3ed93767c44659274704	1663587530000000	1664192330000000	1727264330000000	1821872330000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
367	\\x77878493d5c1b286cb44c792d8c6b1f03a8a3fdf5f8e094b61052a04b19b2c5eee62428c76e43a15c2777ef0622ef48bd1c27c5be010489ef1b355df526daf1a	1	0	\\x000000010000000000800003ae7d5f19c90cda190e40ced261ab7e15e23a62c28f66e5a368f599c91b2796e0cc42b904f34e1012e4d7d9b2e5c2f237dd4a80f13b7a7b3eb04e17758fc4a260815a9c316150a405cbcd1621905c61dc75dd5fef8d8e048bd275417e0b7ff3ac961fdb8ef66c37013d7c413638d0635135a8aabb90f16fd70d7224dc8302e989010001	\\x2ce38a7106e75f76d17281179e479625c520cfd611489ebfb85be2a7207fefd64a6299b40330bc60050b42e165fbfca3273ea07d71631c1f053b223fba9a2c0a	1670237030000000	1670841830000000	1733913830000000	1828521830000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
368	\\x7847dfbd784ce50dd30d16ede992e610445f09f9e87d8b4bbc37ff7f19008a46df50b69a213fa3b196f5d4b142ba892d3210b856ec9b518c72cfab41128946d0	1	0	\\x000000010000000000800003c9bd3f3460d18f7e6e5933bd2ad02bb93e0d0f5ac2d485ce30885514e88c8165feaafa63fa11c77e3059c9b8e93a20c0f9f301c6c3d8b4895d9f3acdabbf83fc1f14434a2a13de75a6b21d785f875c05b0c46094ed489c64153eecb37fcd457044885f635fb4ac18ed409b31dcde5ec6bc1e6316f9ecee35319c2a849ebb7f1b010001	\\xeb6264af0a5845a3850ede55e3cea378a19051b7f3ff9dfdad63a2c98c0edbcde02d386122ddc8267db76e79cb79831c0441ae58458a245bc09f5dc9c0117008	1669632530000000	1670237330000000	1733309330000000	1827917330000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
369	\\x79a3dc06469374f08f953b9b6284ac9a03cd6597aa98dd481632428e67af85d294b2f964168f675119cdc4246bebfcd7266f8614bbf175d7e389c33b675737fd	1	0	\\x000000010000000000800003b46118c4a42c00c80e3b76fd5c5be7ad4dba8c733b6fdf7cb22dfb612adc0e978021dabf630d4079b1f0f572382fb0d5b3a83d9cc507e1972e208cf908ad77d59145fd3eae19c83cf583e54e019e5ad1567a6ccf1725a7902f9071b34aa1ceb2d5b94a3de118d41017e1262d581245a9f2aabf8e55f2c519ec871d84711f2eb1010001	\\xb883ea6ca37fdf3678f8c80b49c9bc374d815be7450eb4689a172037607197ee739ad1575963895dd31db7b480db5ae35b938704889d65dc7e2a233a680a3a07	1675073030000000	1675677830000000	1738749830000000	1833357830000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
370	\\x7aa339639993085e64aae740d5f2ae989332bfbecec95ff7620645b5535a02a442321a69dd7c172e4241e44919101aa2fd4fdeffac9701a33643d5006f0c8181	1	0	\\x000000010000000000800003c4370153fd5d208affc5714d714c806be7c89984c808ae3391ab67d5e9aff739f52ec8468c095d5e05be696b68a4bbd93a5f5176c0a1106a422426bdd0b7a0893249cc6bb6fd42d1e7a3dcc7edef524a76c6ac3796a5144bccf8d7ff1d4df6d1789eabfc4b58a5d7005e81da28ae04e53796d63c314a3306d52c2195a09fdee7010001	\\x9c65c64345c9c5a7d1e2e35cd54bde68235d1ad126eb003dbf5d4243932caeb03d1453cfa4a34c6cd5b3874767cc80590b2f8125789d3c073a3827167ae22707	1655124530000000	1655729330000000	1718801330000000	1813409330000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
371	\\x7e370f0227d80778220f40c2b7d1e4d3efc90d44c5a97001db4f9484d3de9d1049a6b4d6a7524ba23c9fff805e45dfbc99a0f6b72633204d1873256ba1affc68	1	0	\\x000000010000000000800003b6aee6f344a8efbe09a6c6befe00679e53f01725afa600c4d0db67628fbd0b95b58213f42982e9d2ac06401e8e37ef7436c264e3a6611149677bf218070c162258789e8f9f2edea6adc840ada4481776de4c307068b532545d40c4b7dee2cb2d7dc11f3763de6bf16341e343a7956e0f510efd328545245f51fe3ce85ee93b6d010001	\\x8c1a90400965f5a0547642396e6b52abce4c07794886fb98e42c2d940915cb0991770f27c681d11efb02ecab7112c37cb6e75750e8b15bc56643b351ff428900	1672050530000000	1672655330000000	1735727330000000	1830335330000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
372	\\x832ffff91562887f03066e9b4de30738ab60e4431d0275a0e9d39fe8218853f13a8e853e4846f0a91491d0b14c92d7eae3cb1afb7329837a03d0b45f06a3007e	1	0	\\x000000010000000000800003bf9fbb26e8936b2afc3da5fe10c9570aaf2233bfc5eccfc07869e4eba7859b1f4ad61ecd4ce717e7ac3069165cbb04e45cf549138d64d228713745239e0ce2d39a3418598684ecde121b1614b6d3c2c5e7dc4b77a37c539241765ec4eda77e1f300f44d221587063b8bf3382b388380e636cd816493ada41eaa7315a14b754b5010001	\\x7b3f654039e09cfd951c9fb235dccbb974eaac7b6af28f319e7a0664a02c104f7e0d3d3a8cd94448d61bcb9d172a38bfd0eb248d50ef0e85a696957a48ad0d0f	1670841530000000	1671446330000000	1734518330000000	1829126330000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
373	\\x85cbde3ce08dcad6c4a9a0e3e9046c284b520f8fa0218b1a678e11c3302b180d9a8bb1b35fcc79dced156c3eea9747b22d7bd415b58cac7fa8c7de07f774c838	1	0	\\x000000010000000000800003c1265843c5d55f5616411f8ad0f29cf8767a713a7577f86b8d42b6bb5d05f760470b3f997245d06e5724779d12146dd3985a0c25938676f2a8c6a2618694bcc7f6b4522763c0da60788eb64515610d0cc486d9a51a1e3081ca18d5ee332ea5839dfa896c5436ff2e2486b24c6c7b83971642a6f8c8b9de13a9c9e1a70cef8221010001	\\x236a7872c31f9fac5192d5430becd7705bb8d2a1d0960ce7e8ffddd9c8a71dfa2a2b9ebbe7a23bd8ac88c2da7311aee2d797d4dca0418dc9d98cfb0e3adf6e0d	1676886530000000	1677491330000000	1740563330000000	1835171330000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
374	\\x8dbb7ae95829f08b25ba50cf0a2c9483776e40a948cf6a142f67e917e214a8ec05569dedd3c6d5267324ac13d49cb4f3fc0ca085e1b4988be8596d71152e2ea0	1	0	\\x000000010000000000800003b4d4df55f4d0b0c5a25f48c7a31b33c2b4e7f66ebcebc1d8c58b3d75dff4d8adb8d91f28e86b0211f35c07d7a20839e608125b066cc6032eee05ef19ba8ec744d177474c368d1f4ef35eb49db78e4814740639f3676792fae53bf42827f9431749ca85ce095b636a493e05fc8c8f38da800db8579c2d1e749046e0160cf4ba61010001	\\x085fcb9893b3c19dd8d3f8417f2ee5cc3060b5953879ef1a0084c86e9c2eda9dd2229e51a6cc4f3a1e36d8cdbaebc04df3447ce8df8f608d200a9078cb3f3f04	1668423530000000	1669028330000000	1732100330000000	1826708330000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
375	\\x90ffc6208038790e91826cc6df6102e2890e3983f74424e4d9d82404d8ed611290054d95879e119c6a39c0f3ea127a45eea13b6e6f8b5be9052af7632f46ec32	1	0	\\x000000010000000000800003c338213f17c0dbd0f8cc1920be8c86e2335149f35dc862dc49e5b56319893fd18d8dfb5d1b79cfefb83c2382ecdd3f3d3fe364a9a944302effe6337da2685de34ce7e0c5152d8f28129f1fc4662e347100c132ac6c68d826cb6ab8507fa5f935b22e46e33fc2d6d6b9c42fce3bdc5210dec24592e9f378d7c69ebcabfe9700ab010001	\\xcdc6b021fb8e9d76fdac98088c87843a7c3dff3830387daa92fe086d57c34cc6f857c33c570d45dc9e069f9ef58fa91edc0044c0d0f859dc9298e76afb393d04	1662983030000000	1663587830000000	1726659830000000	1821267830000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
376	\\x923fcfdc7cf0768fead3ca1d6e12bfe1d83e55a6ce7b591962540d6b4d9b1ec8e42175f1b8a71491507624afe63b4ba89bfae0dcc88bee5e1ed5528a2a30e70e	1	0	\\x000000010000000000800003b1fa452819ba09a7b1230db78b4018960ff5208b7387e6f8d0e124169c664e7a07c71cd7daad6b2eeff6faaeee5caab5c08ade1fdaaa573099da61992293744d2bfdcf127db3c88a099dd73e16094786579cb76f56b574d541fa583de14b547d6850db655f10022e378e8c14acca6616812bfd0ba570b8a63adfe16034d194db010001	\\x6088d151b87f716e2855b06da1eba70d997a1994cf0d57ec833a7a6a4ff9ebb2e7d48b0d53b8fedc79c05cf5ec9bfcbe8094e048d7deefd0c47b6fcbcf92f50d	1667819030000000	1668423830000000	1731495830000000	1826103830000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
377	\\x94f3f98f4593436310ccdee300aab10faca2257bb94fc1337ecc0d1487832bc82e92b65927e8f2c6c86c909e724c660e5a35068ca2945ca31937d4b9f7b37aae	1	0	\\x000000010000000000800003b82e913c4418f538abae23a2fd333464ec12de707306b94274739c47baeb39829d996665c196ac0521934a73fc7662116ad098c0c5ce51f74db5f319aaa656ba2b86a49142b7535b2a8dcebc763e762c3c7d113e7da201e6ef3b25f054b196c86020f730bfa7d6c407a074fccdee0194789384cd89281228e781e01560fcfd7b010001	\\xea1160248925d227809b2374b4cc98eac38892a4f1f0b1b07edcb90e177d7a28613671bb2b9b7d26dd1672f255439998bbed3077d2232a0459cb29af04e16d0e	1678095530000000	1678700330000000	1741772330000000	1836380330000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
378	\\x966f3f2fb9ac12083837eeb39bd2a278248868b1712ba94a8a143c49b63154f5f4f6fa5eb3115cbc3772a9eef3844c9d6b37242de51245773b39404eb2eb47a6	1	0	\\x000000010000000000800003b2d1c0b4e5b58fb840c4012ba1c213c2c1d3231c1fed49213a11f3274ed4d2b0765e656e8a35c26016b84cb54cf49b1663be8b3cc6be2bed8c1cdce31420eac43cfce87027eb7e3ab616359400f2d20182975305744c0b15ac80ce8ce571ae3bb31cac3ec1e5fae28a5e1c20b4d102c76e2a2be02915be5b947c5d8c6a79d34d010001	\\xa833bb7c6af7f620e389ca4d70f709e6396671ef01d2c91ed94a1d86455f4e9787fc27d4768d3a4c519272e36b177ea3046ec80f4727388080405fa3d6a3da0f	1664192030000000	1664796830000000	1727868830000000	1822476830000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
379	\\x97bb9a98c8c16d07c46d1ac100816096527fa463ef055580ba9331bb08fbe6e93d7598b4fa3d32b762a97063ab96f4481a0c88b2f178dd397cc9814bc7d6377c	1	0	\\x000000010000000000800003bf2a5d1b4da61083bf72947d947524c7790423b5e4ce242589fe4b07127b838d4dbf07f94985804c677ff1acd7f84584c5a788965da93bc1aa1fc4c1efb541e15389bc55211814b4440e96e5a6e1ace92a449050d2a2aa9548ae9424c5361f6284cfd3f55909f40dfe23cfa780df7d8c0b3d227806b38002e91bdf62812e43bd010001	\\xd2ad1bc598a46ce5cc1aed04dad1774e230db4db8e51ef6ceeb1d4d81bf3f3b92c720a197e74f66ba35245bcf60bc5b68ac296016e0217011537bdf8e361c600	1658751530000000	1659356330000000	1722428330000000	1817036330000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
380	\\x9abf724c21b08e81434f60f4c5aa68a0172f7bc945a0c19ec6e811c2579c1db91b667288309d3cf6d7e096e037bdb8bbc48aef19ed8df2c5ceb59384664e049c	1	0	\\x000000010000000000800003c4324127ab9b21cd37393d8b3425a289ec489ad463733eb35b4d7d0f151a841b18f0720c488e0e2a155a8918f10a91f9bbf98fc022489a702df895bb176d4c1c7763d94d61b9bee580d07775b4610ecd345ada5f06885645ea75dcc3eb2a4c0c2ce1c726f4d5d992514f41cd6bfe6913580697595ef09011351b5cb0861ac237010001	\\x5189ad7479f9d2538e077e1b615883ec4faba292e3522b1fe6bdaf201af03072451b97213f2918d4fa2b23e998dc6605dd55f2236d14129c45e4dba2f73d930e	1683536030000000	1684140830000000	1747212830000000	1841820830000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
381	\\x9bdf0d75e436d019b5909e16e577e3dd5ee90c3511abe82628371f245fab5802f78f8375c80ae0a03d777fd941e96d3bf3d129484910705de8d7dd4944cc5094	1	0	\\x000000010000000000800003bf09b95844e2be445acf3e9a58f6bbf6f3ac40913344903990a73f6f3e82cae266e9fb9b37cbe12ace46a16c024fc62691040956d0d83e10b5c3fa7a216e8f8dd4978ee853472b2b0bc4c413bce7c302a8b6833e9715df943ec2f65c2cb55b81bfaf5be6825a1e70d352427783ba65c5561091f69954b560cf40d851f393c0bb010001	\\x3f8e122f9a85d35963e89e16ddb4f9228951e6d20ba336312b2b09bd1e2dbea89e8ff9bd2449ab9ddedefcaa6b00a089822bed77ac1b3e7d2c943d85fdd1da0d	1678095530000000	1678700330000000	1741772330000000	1836380330000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
382	\\xa0bfbd166c28f5c7eff4ae49c0635a291da9780a5cca9c28372e4ae1a7d548cb99234f3ed4a9cba5568e34b34d6b602a6a6e8c0cdccc8438a8026275cf5e2fbb	1	0	\\x000000010000000000800003c333d76feb6c0f2ba71bd6f48db0cfbe96f35918b3c98d740c8be6bd52e3daf1b260b1f57b5ae9b5393c3519fbc29df8fd8f09955d3de26641b9a88b47dc693e8ca6062ae8ceb8ce85f3c7cbffb4553c0d84b7d6c07a60ce60c5302a072b7b9fdbdfa6dfb21fee9b02ad58bf8a6fde691aa79dc9075ecd70fedc685c482d2f27010001	\\xf9e262f6270d814ae3d8ba261f712dcacd6d96aa7d317cb1e0b76b34402325f710de0737b3ecb54c4f80b67aba62f8b086b98c665a74a6637a1ed6113cc2f408	1659960530000000	1660565330000000	1723637330000000	1818245330000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
383	\\xa32b2a1aebe304cf21a14757399aa0e99856a7bc079dc356608c99f07d2a6e50d747957b6ac86d40643107f35999edc7954e0710a4d8fc3ea527b76a4617f6bd	1	0	\\x000000010000000000800003d4fe809e7df3bd5d57b383d5a607dfd8451dcbfef0b934a5f3c104039100dfd2e9791a1bd3107b1cabe1b5cf55a4f1891908f2179ed5e8cca589e8f3c07674045774a5801d1ee9b62b4b854fc7a6201bb3e7a55bc7e119f75832f35a0fc6760966c934e0811b3beb9886ea50ac493d39ea97296aed4a755d45bf11d00559a547010001	\\xbe75da4bec375fe4c088646be3c8259f57adfa8af018b113da5bcd926780e60cdbbd6320987528b1666f0635486da6f4b4d23aa3023616adb214288ce0dcf305	1685954030000000	1686558830000000	1749630830000000	1844238830000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
384	\\xa31bc4601627fe651bdd235deace607e99795a7933211372a0fdefe36210986769e35a4f59bcb23404dbf83ed632ba6f109b59dbe35e8e0573f0b727e82510b3	1	0	\\x000000010000000000800003bb1996e210706ae06c14f815b83d7cc8c3635090c4746b398223041d56ee70ad906661953e1330b3220863a81ba8d48f680971ef144253cdfb049ee15f71718a9a53009b531dc0a4ddf68a5201f16c0a1979db72d3be52159e1be2e0fae676a349d53b3a9dcfcb31a0bb5e1960f12e76e527c31f6e76c11daf7f69b55db8d169010001	\\x3cf7218e45fbb5bd181fe9ecddb2339bad5fa43d32271dcf875d2e919b21ff8c1eb108743a00f75e786489d23bea3c010f1e83af7580d093787b88126491370a	1657542530000000	1658147330000000	1721219330000000	1815827330000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
385	\\xa4f7392d56d9c787d001fa54212c20a2737cffeab99a1592f57d99e1254b610c89f3cc992bfb62db59cb11e09456a18a41888e2ba43c8d149828a8b5f95888b9	1	0	\\x000000010000000000800003a0c84ad3ad3fbf9b8ce789ac74413cc7f19ae7de4198dfd9bf82e7d576a85bc0626395c4b88aa01ad43028b56397f8dead279bb953198ce19512987f908776dccc595499183f33b85ae5f5a403ea6d4495e9af4c4bf84995ea3353b7775ea57f22b427c28e31e4cbaf07e4cec9fea1fb58fc38b81743ed75f0391925961a5ee9010001	\\x512e83fab311406b9a45127909decf5e15dea224a9200d1a6407f83159c1119d0c813582d3ee32af497cc201ea277d39193a0b2aa9ca12cd8e55bbcdb807ff0a	1661774030000000	1662378830000000	1725450830000000	1820058830000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
386	\\xa76fe866003d10cb9dbebf31214262fc9ac423ba9a3f99055e6248ec28baa694710d77ae3c919dd067ca0971cc3d68bd7f7ffb5bf300b67b93f8e62cb362d71e	1	0	\\x000000010000000000800003f2c8ec3c00ad4045520d4400d43026c6d4b0cd55fa5d7b3c865d7f12a4963a8368a84b3b95400bea5266541d47c3e2da0dcd545862528fd7227bd623345b7e1b4449344bfafad271d46fdba3922d996d594852361b0e00876fd49dfe49683bd9a895df8973f86c02658da1f5b2531c469e984a796763d36466d12c65532ebf0b010001	\\x8c4e994df727cf71f1973cf7b3bdb9793fb2e804240e25331a07b7549200e9f9744bab863637ef368f03d21e109653b9644c68e1b01848da1786346457bbdd0a	1682931530000000	1683536330000000	1746608330000000	1841216330000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
387	\\xb3f75ba154708c94f3417c334a31d2f545061342396494bb3debdb3f43fad534bfb13fb5a0864e732447b8ec7187d744fe0b6ad03b4c5efe7de2d79dafbf93b2	1	0	\\x000000010000000000800003b0decef9558b1cb149188613d8e6e121c01e3d1792c77114462c31857ddd5bfab1ed8ab096ac0d12e8295b1a5a1c6e2cd0ef1297237ff9fed728100a8647c6fb95cd1f871c40bcd161f7afdb5b1e843004b18e42ca2796938dd9343c899dec338e33d774ab838abcc752df6014692bb3ef2f9708a550f7c554c3a5d32d9ffc01010001	\\x312f64d29c86cb6564165c36184977f0e7aa53ede86d719edbed43768dc5fe4f275c87fe75a46ae8c340de91be53c5ba66755a63ac6ce1d663a145320736fa0d	1675677530000000	1676282330000000	1739354330000000	1833962330000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
388	\\xb3fb0046c3a13c9a5cea9217308320d3f00af76308864bc2988aabc8a604d7c21f25b1870dbbdf1406176241cb6070f86cdab43a529ac4dbfcf8f90bef4f5a5a	1	0	\\x000000010000000000800003bc2541c39f0d898e56920c2c9396ec0ce3e644ba4b15d18bb0a99d388dbd57e6b813ff21df82ae725fea05644f13129935a82b2d1c1201744d035ec1a7970c4ee5f59b9c561e1ad14fed035870e4d76988dc20b19729bc27004349815828633050aabe31794363f0404faa56de972bdd253f4e6157bb1d660aa16246fcd54379010001	\\xba9b8723664a25e7a61def6e2b520e9e8550d515e8b5399d9a854fb75642b75db80a4fbe4b6b23454a02cff1480864b5607fd69fb6dcad52d25c1a4530f82c04	1655729030000000	1656333830000000	1719405830000000	1814013830000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
389	\\xb40f6f8c86d1dcc3ef94a013f46fb64e232036ad1f74820045cc12b8487b9dea15bc5803b1d2cb1c605d30a8400c1906fc033160f737c7ad3f643f29d7fe1d8b	1	0	\\x000000010000000000800003df9e707e4a1466f4a7f729b1d97f26268dd34e1ab209b6a682caac58fcbfe05b9b92d7b57cf7458300438131d14c76520b90f8576d3733cd6ef4fbff9b9fc0481b5e60a55f29becae4daf64767bf94c90e2763a0410e845bc8544c373e5a74098f9ff59036f6fe0fa58abee9e4d4a282e46c079575defbcf2053aad94760b289010001	\\xffad9cca3b430c94b918df336cd5f2679fd58e532825a3e808156f8f8b91b8994151815cfde5e115943da013d5c94f0bfe5a76ddc4afcb8638da0f5488779e07	1662983030000000	1663587830000000	1726659830000000	1821267830000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
390	\\xb52feed2f46230b2158c0690a0f5dc64df1fd53cf26ea680a38676099fd750820ed641cb16ca06addd64d39c37f79b6b37d4555eab56a549db32193e26ac4341	1	0	\\x000000010000000000800003c668064d9aa70f7cd224b28dc8090a1b8e85440ffbb16c0fbb2542ab6d3306bcd3b759b950b6208c06be2d36442761cb1f03cb8870ca50b3a13ca06eab4c4874ce6c4f39e676612124657080108bac2c14ad55d9c8653fc0c05e7a641f2150bbafdbd97549dbd07c234ab5e68be5bdd46cbd30c2ce31080de4a614cbebf84051010001	\\xe67823489de73892703cbc75ea6aae326e12dc46d900251ae7e2298ee7ba74793aa30b01f8d41d0d3307cd16fcd4c248f647b3ab328fc2280c228df4049dfc0b	1676886530000000	1677491330000000	1740563330000000	1835171330000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
391	\\xb72b5ceb4f9d3e8a9bc0dce7bed084957c2cdc5343873b5bd998c4febfda5b97f9063c9d4652fcd3d374ab8182325b4df40235a8e02522e3717fd7008258866f	1	0	\\x000000010000000000800003dac8fb21831afd49b69fb960aafc04f004df871c21ed9cb25ebff74be433d0500a151dd9883fb9de00d405bd749017fbaa4acfb635d90cf0713479b79a6f4ef5654152a9d3e6a444b3a4ba5e3248b02e06154e05c8a4f57f04736bae3f9c059a267a16696d12ae182cdeff4ec0405d9f86b78949b5a2fe2c4cd642aa966406b5010001	\\x1b4a088e646f78675dcae1b4c5a89d1679630d042d7c757b749df69d4560a294775b6734243c719d8e7244f10da7706fef4e444cc129d7c1e321da7175035e06	1671446030000000	1672050830000000	1735122830000000	1829730830000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
392	\\xb85f3903edc0179a406fdc041be98691d14f4464f54e9211a54b2efcdc2d6340b4eaf0b1593e5f6b950af9dffde635533102748bb46ca2b4df03c21e0a505d57	1	0	\\x000000010000000000800003cf9a21f78215141ce762eeb764a481d3ad006b37d99c24e83aac69b2a4174e64e448a27a69e601fe2dd907809db3c5453a9d48c24b0f1a6c268e96af913455c532e801b652e58df834a68d1f5977dffacaccfb5bfad97d925a171315c1dbb9d850e70491674e95e24d1d311168bbc7858e8fc3aeab9aef6cfa7a13ea3fb796a3010001	\\x8b6ae167ec2eee3597463591dd06939fd825adc266c73da3e8dd43ac723cb2d88ee968d4f9e38a05970a57b0ceae592d804beb754e7a08aa66bef6a8a2672f01	1657542530000000	1658147330000000	1721219330000000	1815827330000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
393	\\xbcafcb575a1b158345490a73b04b463fbd9c5de3ffdaee4f98217610e3b8c4889e8ff895b71b0601f43280ef4b5bdc2dfcef0599696f87e1365a4b08d4c32f32	1	0	\\x000000010000000000800003b947f34788ed9978edbca9c95c3bac19bb1f6d9be1669d881c2907c4e19d7f639587c687b1bb5d70c0d3b0411f30fa1442049c29d11b2d9334c3c4aff83db38d26dcce4973a5cd7b75e9a0898b667756464cb36ec260f74d1f49a0fa10472623ad01f1ebcdbb7cc5190a81eec6a7e092070eafa3647fd1f8572da21c1aab40f3010001	\\x2af906ae3084eca40f6bdca4435f117e5d3e15328e13b46ca7f124ec148100354ce9c932c8b337a6fb41a79fcf6e6068b5ed4798e41cb60090e2d012a207490c	1665401030000000	1666005830000000	1729077830000000	1823685830000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
394	\\xc2fff800cfade6d48767b42741091b09f7f7decf23fc35deed910839d6efc316f97127aa21d43bf2025790a5dc4f0e67ee0eaea5414f575b1be3f80cd1dd6fee	1	0	\\x000000010000000000800003c5dd735695c0516398f95518b907d3df2374a2433674b05660993cc03a7e5d80fe99c6067c58b5c03267647a127513c506b4b23895394381bf5c8773eef36eb0536d30221329218644097dd29f56cafc1d7af0766874807ebdf1de15b69cfb6acb344154cbf33d29351a1c53e0b05467e3d9b8e3c8080a439e144ce694dee181010001	\\x5dcf07bc24bb0cad0e701b37ef0274d91482aef65de4999f6f561b03f2aeca36517978888a32d03ac12c29b78301029cde012822bd0d86073e58c97d6f847d05	1680513530000000	1681118330000000	1744190330000000	1838798330000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
395	\\xc253c5c03b0521428e8fbe1d9cf462da4390b30fdeebebc95c902bb2c215c3ec252828d1bfb4d5adb6be70855d2c99f6a9be214860a2cc5605aa4d881a61a19e	1	0	\\x000000010000000000800003d42954173ea56a8c193b87bfae2f3a1488a5a8972954219aefa4831ab9840af59194e1de142fa9964e810679562eca9c1e1d189dbaad429e9c2d754f4fbb279c50d744a47a83ccd98136ef89839653184d8f9e0c592fec4200fe34b8997eaa4639fb81f8c7f3268d73d89d55f82b796e1f2fea42c0dba197ad25adf3ef40e40f010001	\\x7999c251c8b6a8b2d633f62d1c582417dab80e4f875ce84d4e520835dfdac60fcf912c493b0e5bcd2d9e2a4ba3d53c1d2790cd605c1e019fded18465cb519705	1666005530000000	1666610330000000	1729682330000000	1824290330000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
396	\\xc36f97569ae80e4407a8a9b370fcd2567c923904cdccb1488014d05cf1d682e476963cb5f5bc6d1f1ffc42b10a900efe7aa7637302823703cd721c2e9d9aa270	1	0	\\x000000010000000000800003ca30f33af2c15f713dad6e292b8cb61559a34a9bb9affb107851b279dcf93b46362b68beac8a4c3935c60eb66564dd283028aa3b1da386c6bba5b71bd9968ce3be7231a59b370d4a2707a085677c537a1977dcb365dca289d232b34e9811ef9a8c686872d8965a17a992c1d9a368966571cf70826d8d99b7d3c6e4a7fbc29bd3010001	\\x3a3a6391e7c73ec210e7971cd63613b5dbd403f7e2bbbaff4fc75fb964839e37b8ec1aa4e5507aee5e080d599f58e1c4f94aac5a0f1e345cfff3fae376e6cd0e	1665401030000000	1666005830000000	1729077830000000	1823685830000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
397	\\xc3e335f9c4b0d50da36ae83c63a3d3071f67f5af45d2278dda46000f594d72fb627f4bad27b117175caac5c331dae110c0f4df6e81212a5f71a47e0274807036	1	0	\\x000000010000000000800003f234e40f8e6c7db42440e6568305b0744aaa4dfff6538b74f40a18b62cb60284e7418dcb7f04dfa53c52d9ebf42bb42b35b60886e8ee9e11898e81123e53b70e57bdfbc89c8ccdd549984ec5493b8186b4f922912e3b046ac5fbeec72db54c56f2999aa1e6f6e5b51adb6db42bad9a3d9af385f06db2267688dd05b4aab9541b010001	\\x7c9688b877e8d7df9463524b933e00959cf1d069230b8adfb16eb442b37077ddb35c0c094a44f8bff27c5b54e3e3cc7da5468501a6bdf72846cf61b2e3923c02	1655729030000000	1656333830000000	1719405830000000	1814013830000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
398	\\xcaafaf95c9d4037f42235d29b75deabfc97406658fc952853b13d8bd7c3178121939437343d108eece5537e9afad8026fee8e6dfe875f87a8f35235ed1f890ed	1	0	\\x000000010000000000800003c5b4c27fd6058ee85a687972835d6e029063cec8239c66fa8e5c23322cb29aa730a0394ab36e59d3df095e2b4e1f3b27864f73a452df6ef325839f49cdb747bbae9e93fcdb097defddd10e2963f537c83d63c870c11eade00a603180c098fefcff06d54d48e849e63641c12202baf26ae75dfe81d60b18fe2b1b88438e7c56c7010001	\\x980d8424f82f567ae02ec69e32a0a7bfd47f90582d4bfb1af54c6f7baafcf6acf09c849a18cbc345a111ecbbc8e29cac090cd90cc519ed3db6158eb6fe40ec04	1666005530000000	1666610330000000	1729682330000000	1824290330000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
399	\\xcb2b568f4757828912c359f3c8b06414827826f87292218d5ec22bf336efc786d65dcf5c823a92862a92f3beb8868c3a6035740e6a4416305cb16f44de09bdf4	1	0	\\x000000010000000000800003cc80676d1f3fd60be7977d4e00e5f5f50bca92d1227cf9a00f7676a03e5973badd0563b3b48e38e19a233cede1d7d62a34ee453789d311af8a749b85a4a8e6c3224c7ef2c80531172243e1216fdd8a93e97c1cefec89264845bfd51d9dfa27c31012adb9a1fab4d4bc0493e027deda00ddc04f5500fca1fb34f0a848e77fa9bd010001	\\x83dc41af57538880deb073dbea3952b51805e45cb5d6e142683a120a5d6f078471f0033bff4a445e93fd919f0c391125a626d9dfc23125fe02e147105a5c560f	1666610030000000	1667214830000000	1730286830000000	1824894830000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
400	\\xcee77a1d62eed44294a5f53c39db3922327f04d60a2cafffaf7b116395992411caf5efaf7ee4c87dd1bd105e7efcd28cb5ad9dbc595a7d3e14cade2972e2459b	1	0	\\x000000010000000000800003a5ac7e313d893b27e16890e2d39d22b9d16e1444fdf2431019fa76084d878ffdb631d7ef0aeafd316957733b7573f6f39737bfd352d234a01b80044e7e8aa1ff275ef300e6dbd1e07eb9fbf0227d0fc24bfee80663c2ea39aef6257cb55724de4e00336c40a5903d37142407d39310a1b17c92bb315628b1179b21b7595dfa47010001	\\x995554060650f57b401c2a15b9b88ca197f5045d13a355c2452f9ce6470e236fed610354fd97a9d957910469b595b31966332eb878a9c8eb0581fde6c53d4e00	1660565030000000	1661169830000000	1724241830000000	1818849830000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
401	\\xcf0fa7eb5520e06f7f81675a19b43f6a6af7c2b36e597932d077bb587c5d5740bf10e2824b0cc4a742a94e88ca5f4921f2817d538eaaaeb3db7c294d64a2fbe5	1	0	\\x000000010000000000800003b309c249cf43c556d67284d7845d2c054c9f4f64fdc9e41e71647c3f649f01cd8c6004d187354aa6f5cfea69de627344951c756db229989093b51f24be2bfb2e101ca68ad86ee6f3feab416047d659d40530eb923446c6e9ece60664fb8dd778e4aab48f81b11c0637cf5f7a314a94199cc755f7930b52e8b77e851207fff2bb010001	\\x5decb9fcd94cc6d8fbd105dc62fab152e334dee540bcba5cb5284c5d02347206c7bc162e177f2c1361b6b34b3ffb20b014b74dd7d74fd7e8c3f9caeece03a30e	1678095530000000	1678700330000000	1741772330000000	1836380330000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
402	\\xd083e5e9b79019facaf0f83f480b6cb57bfadd99a39371024b0be67a346b44ba54194d268ad54e8d6b520b570eba689065a109e73a807d1eb83deac4f37a61ea	1	0	\\x0000000100000000008000039a9b98d35090cd736b273e999dcb445de9d41988893fbe25f98a5353729bffd8c23388d878db2fc6c7bcd44b60d28eb37a40a3bd9f616daae51ab3f3b6dcaa33734bf40b80ffbcb83aea8a8f0fd69ff5352a07c0ebff8c44c424337986abc53c7d8a2aaa5b819b7a603c6c9b5864f7d877c833a591710235f6636975d8171d6f010001	\\xe7f152a4d9beff8160748ad307a84ec3e6332e46e5c8c9096183ec9ba96f8b72a88c15f9d13780b6c65819bc19aacb211a14d3f1e23cfe6e9880efc438672900	1664192030000000	1664796830000000	1727868830000000	1822476830000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
403	\\xd09383ccad6965f6109ee8b2ad429af22d16b1e0b6818073478f8ce1ca174840b8c81bb8ca95b53c0bc4b1e259dc1d0232d557ae03a2bb32fe030713eb1a6aae	1	0	\\x000000010000000000800003eaa0f95b74d5ddd627918d2c390a8557bbe0442de41196ab43f9221ee446318e5db1628d9d3fa613d4e681479efca253d6d3153b5a095a7f386e041007a576665b4765bb16afa13aed939f41100e8496a715f71682bf3a0c159f64f7f0db8644b689dfe7db4b0ee594a5b484db95aa99fcac19895df5ae85745023dc192c6ad1010001	\\x43308097d00e52e999c828047101f477a7de86b30b15bf31471af23fffc42c31a262381a79e3473715e79a8061ee69fe4ceb5950fcf0dae40126eceb04550f0e	1684140530000000	1684745330000000	1747817330000000	1842425330000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
404	\\xd35775ebb4ee9bd9588b8761aa97d24db7627eb09fe8d4d0259781c3bbe486ebbf5ea582ad403ee37b4c1ee6edab37b3a18743af521798ee7602b180ffd40cd9	1	0	\\x000000010000000000800003b671ca59781e3281154a9617720d88e6239b989c57a4647a68ca38c3649345be8c3516b67ed4404886ae7ee9f09793f821f8d5a5b88f25897b7d4abfeff6249e108926e5e245ef189e49f28058c329269b698214ae03675b7b3b7004af44ba79e7d45ceaa6082737ad96ee51634b0cf6600551d64773f7821b89debf6966e7fb010001	\\x724f21c94a0e69e342ef07cd255c54876e815d12ce07d2c9c2789dc720e26f217415d1086b3f01a9d6616aaab862874ee5a907df6557862746026e5ca1ca5707	1655729030000000	1656333830000000	1719405830000000	1814013830000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
405	\\xd67b7902e884bbe71250263f5cbb4b424f79e97893fed8dd2c43cb52d71f0c53099cdcb658eba2f5b0589cbc12eae3b6999c35dc7f720060199d1af558e58553	1	0	\\x00000001000000000080000397e3f2fc4b21c62ceffdd19a0c1b70031acf246d949c4446e4e18442df3fbe6d15e8882e17be0d30d06bb6426e2052fb367268a0958622bdfa1d026cf6295f356a11c9ca1b9d446a4beb3e84089fcef2c1b96175c3f00655c1b453035b458981a1d93fba52658dd29bc12511a9010533d6c1a48a8f1c38e2a02df5fa0c2b42a9010001	\\xf5ebe5d93954d2e335a9f09feebbf24e5764cf236bca2d90806ed204cf7de16a381a6abc5a747942ced6bc8d5d38060ef66c5ed79ae428007f9acea3e559c200	1672050530000000	1672655330000000	1735727330000000	1830335330000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
406	\\xd81b568bfec4702e18cc5e37dca000ea826cfdc7349c82c138fc2eed9615c328898358fc404fbeae610d9708be8489663122d5cf22ab89560a509c546a44e6ec	1	0	\\x000000010000000000800003dc9b453d65962079633169b0494855d702afdf76a8fa1e7bef7b03dcfbae3d439e99db087f7c4045da36b58e2a80b1faa18a5cd0aa2fbfb778062a1b828ea0355276fa7ee2d1eec52afd34e069827b2fd0eba4a448af027828cc509f69c452818dc20e5624ee87241c9a7f0690ba606e2325ce9830f502602037dbd125194f13010001	\\x9c56c513b5c8ec4623d1e4c7691f79ebfeec32d6f25ecde088349730c4bf0bd21daf484b14c88af38e18e42eab2eccda115cc0cacd30e97ce70e3985cc5eb907	1679909030000000	1680513830000000	1743585830000000	1838193830000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
407	\\xd9d789e97f6c92b26805227c81a2459e2b42fac409dca5d15b43e34e0446386145a40c78e0b1c941c27daa2a7e887489e56052bdef584bff5f9d6733b1b6e7a5	1	0	\\x000000010000000000800003b791e32892ce7a592b3b8df1a62cea2c1d2757d5df393cbb7fcf10139f727d2086ef141822ef8368709fa08f88191eb76d732e0493c205c5844087366253b6ffe48c6171a914f89f0674b7c992e5ca0525cd6c85549cec00b56354aa912c99379cf58cfb058ea917ceca1b2081953a072ccc2262236d15397e7f33394fa2d01b010001	\\x97089c0802e3acf78f8aeddc02577c1ebb1c29d6932e67b82e85246c107b9b71cc81786f53e801778c08fd13cef48502e05c799cfe34f71a8942312c6306030a	1679304530000000	1679909330000000	1742981330000000	1837589330000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
408	\\xd9f72e05f085452fbab7c9eb16b3732696c8b3a3ca05d3528167e083b11e5b75d017380f10ca5a2e3d1417beefc4d9c159a2a0399afcea87ff4b8f9f21d2a1fc	1	0	\\x000000010000000000800003c07a9c610dce67aa486a0cc222bde9391544a20f74b8ef496b006c8d49b2510d13f6ca6b20c7c3b0c03f4da4b8901302387069ae9cc80b9578c6e402c8f41cd7940a40737f1303ae65f6dc78c646c2052a0f7d8b8ed0812d1c7d9b894107c8aa312e60acdb055165786d1ea81d40ffd4fdfd56637cb830a73573894e2f8157f7010001	\\xe0869089415f4a4cf57139a22309d45c508750cccd1681a92ba4add335ae4d1e4554670e06ecbbe7396c3dc9bb650a682fff2b20d4330975cee5e2d0fad67304	1675073030000000	1675677830000000	1738749830000000	1833357830000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
409	\\xdadb454cef50a9df9568d6aa42b4a3a9ea2cc8a91c3eee2820967a1ea38b76ece12169421411b35dd9214c7c1a7b5244ab8c081bcb697cea2a6c62ae953701bf	1	0	\\x000000010000000000800003c0ea00b52b259eeee91ad40cc9907f766d534b2ae3e453a80fbf2743be199509ba34bc85fa8b3995e6c22a84ad59fc7eced4eca04ca77939e36ec246ee2ba9df910f97a211fc9d2c06fa9e4d6308c2bd348162dec5e91271bb0cfe23bd22f147d72f6938e64568e240ed1cf20f871a24d5a82220c82d83e54f497c373b292fc5010001	\\x58705e521eb3602bb743e0c18a640f61809a074ed25c19c21680bc51ee357dc313026a573e3702479be4de9c3241ac384352dfa2f157888eb3405d69aca45702	1673259530000000	1673864330000000	1736936330000000	1831544330000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
410	\\xddfff52088a384c936dbaeaca542d52502af4742b7382b4a7d268e8488abff3814bbb2ec96258a39979310df2699e8d24373326d9ef021907d0f28522759a46e	1	0	\\x000000010000000000800003a522a00e004d8b89fa7c172cc361edff261efeee024f1a71e0c4f2450e319ece682be754c06463beb870dce18db6b3c2007187e6caeab64f8760b70bd86187c97d0497bcbcbfcc05a65afa993abbda4715c9a4dbecbb5bc25918afe98fa103080dd30e3c4af144174cce5a51baf4cfbaa4a251fa6602c08af37375bfbea46379010001	\\xae7d097fe7ef3b9e186fe606135c2d744ffd9f85b59e0ef6c9b12bf5a830fe55c7d890025a815d0877cfa037ee38e406521d7e6b9affce01224f1a3b96fa5606	1658751530000000	1659356330000000	1722428330000000	1817036330000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
411	\\xe1bf10d0a457f81f231ba7a2a1bd59875f9e7305e213a43dde62cd5ce611257c8e4bf37a3a578c3eeeb314227be7efacd020e4f943ba69105b26ff3fd9a47464	1	0	\\x000000010000000000800003d2c082cea825e0b2f17a69ae88a64c7ec6f660244148d9a4c5ee618764f0a1845e175623546de5a55831049b2e22fa918c79d591f95d0f37ac7a004eaa8352683d273d330e44faad7c3b4de4f9bee31773323daeb2d5f90701bde1ca7bda81a8b6a0c2880f838a133dcea9282a39cd1bde576ed7d5257a23ac5dd7a69a57de93010001	\\x508a006ecf9cc7dbc1dcad82586c86189e59b66796ced390c6b14c11053837e512baba9469cf1bccad19067a69dbb4fa83388e82e2e7899569e88f99da8a9f0b	1676886530000000	1677491330000000	1740563330000000	1835171330000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
412	\\xe5d31a335038c70c358c224dec056dbeb3634a292bd7e4b1a7b5288010bb6ede0173a5a298f68a3edf35d9f020d21f290ad8c8ebbd6d9160620fb74548f849e7	1	0	\\x000000010000000000800003c43d466f86cbd53bcc3d4df3b702d25239a4cdfccb82128e397f5b4b2b6cf3140c6006f657373f94d6319dd6518c005c7593cc6c1744139a1940990c8098c4f2aa7d8b7338bcddf705204e9ef316ef8045768b08b286d0f1d70194470f797adb6dd3e8e982675e4076d9d5c0b51650191df280285a5b3ea880a43a85a830ae41010001	\\x4e1e6f5745391df4bab91e901d9d28dfc87bcd56d6660cf7ad8357b970c9f369087f2da59cc9f9fdf280fa4e34294da9f608b3a7f414a32ec0b5bb3b8042890e	1656333530000000	1656938330000000	1720010330000000	1814618330000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
413	\\xe7e7571afc601e6efa3f53fa26ea66a287d4529b7bc19e331cad5888528c585805065dde8d95ac43bea94b5ff9e8122c9862672ddbe7ece240f08b9df8fa7472	1	0	\\x000000010000000000800003c7484466bd93e55469d181877c4df4f320d8c528bbbb630dd724026b161128b4b3662cdd8270ef9045bfcef462b8ef2151b615ae445b30ed005a7f9dbe9379317b0c34d6b715ef5db5b0168d17a552faf66664df3b1806c8fc9e1ece79e1c5fe0a6a23f3a9abf564cae462f049764cff10b74365d12ccd4105e688b380783039010001	\\x92acf1e33492d76ea4b794fc0abe9858f3329ea8830a7056b386dfe0e4922eae35a5ceaa244cc07d891e5e821fceeef39bdb70ae99bcf2dd4550b98c84497906	1681722530000000	1682327330000000	1745399330000000	1840007330000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
414	\\xefb714c9d442be5be48526932c79bdf9ba55ccc34d77ab1446c05fb2e44cf7261de384e1476e247f45535afa988dcaa0dd927333ba63abbbbb643c7802751bcf	1	0	\\x000000010000000000800003bc8346a8cb8915b78c7247ea67472964d84e0ec834a67932eca0d8e818eb18b38ccfb719a4b2f72c6743929561f707cf24689e338c7dda8aa9916d13434266a607fb259d111c5729e3c85c38378511c75286d874689cc2266fe3a66caed451b02b1b3eb133e9ba58cbc77dbde7252cce07a78a5ba56957ea47c58424d86256a1010001	\\x5d2b25c123176c14069b5b2fadb61a205ed678f366578277ef7f3513b8afd857901a9baf36856f68b6073d24ac8a55a1e4ad72c4bf47a387234284ce1d4f6805	1676282030000000	1676886830000000	1739958830000000	1834566830000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
415	\\xef2797f81fefdc03f2a0526e848d759745deb1abd8359d528e3a3c5c9ccd91ea8a72e4a3da7d10643af49038e2d6d5d4d508916aa7d055723b56934ce7d773af	1	0	\\x000000010000000000800003b4c82ed7590cadba38d3278e6477abccb3e1ecb1175de5974a5ca5a340549d4fd6ddb88b3b2dbeb6dc8be1b03e925c5dd8157fa4e283bf87d0e769348894b1b4ee918e8580a0eb42b98749d689ce709176b0575be94d03a0e51402af4f61f5bef8484bb29cf120a737bbb950db90498bf8c0e044634ddf4e6352491d22a11fd9010001	\\x794476f9c2a17c756378a3a0f8e722bc0637c8559af571b6f35a4f06a7ce8e79746f992d2ebe13595e2124e12f65670cbb92ec8ff8c69452bbc88139e38d4505	1661169530000000	1661774330000000	1724846330000000	1819454330000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
416	\\xefafe8b461eb12e01306e4eabbb201860c384fe0599375be459ea93f98f81727d992be51de3f3d2403098f08df5d6afa1cef881400ae6dfa948cc3ac11fbfc18	1	0	\\x000000010000000000800003a2e13532595ff538be881a5cf6e6b289c1db6adcfbbdfc3f9f276fe067e74c08dd3ebc9180be469ae58afa9f6b4e0a7e79560e8dcf5d87e31485e3beda157e646df067ab23b3673779f3052995adff41e38727bfd0def8fd6a34e7ed147ce6c77816aef98171363754042ed9f66a8422d65e991077066dd0d3ed66045a302611010001	\\x4ae69bd01970af7ffb4bbb7630b14a1fa7b9f4ca4488a85d14af5121116f3faeec80fd92e23a2995bae17fb7f4a391d845708ba2c6fccd79e4934aec9ead1d03	1669632530000000	1670237330000000	1733309330000000	1827917330000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
417	\\xf04b3a3b9e9b847c458382153413bfbfe3b7cfeec4c8cbd7c00ce34a5fa3245a135011c570c7627ccbfc265ff13aeff82da500b7cd2df0f40e7787f1bf54c419	1	0	\\x000000010000000000800003b74690812140e5558c9b53296ced468e17dacce442a5861374a9a0b32d387de9a51e95943856aea64667cc1bb16fe6fe38cbf255b5975f6077fb9cb5615a8fd0543f32bebcf6c943d9bd8869dc2986af9c7ad79d5ddd928b483ceb7b453961994ca0e7645b4e10e4e4b17558b09049e20e5e959fa783dc3cebc81a8d49a46a17010001	\\xa14e4943f093974fa4089a3cd1280b51c767c4bea2a11330f0c27cc365c96607531c2a7bdc34ed361d6db02bdd97533b7cd86e2f8f38479dc81dc4fcda477900	1660565030000000	1661169830000000	1724241830000000	1818849830000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
418	\\xf1679148ff5318f2f081c41061270047b02fcd4f1d576c3c04ca6c2af5a3ef9473e6076044e3e4caedb1d2ce8b6f4f8921fe6ad05985af16185706c43ce055ad	1	0	\\x000000010000000000800003a467c91549ca9f49a5342b8cb5253e6e8f4d3c8601b720922a73057b84ad3131dbcd9038aab1b9f4889692c299c709660719d06b6c9e9aa4a3937dba45b814af6492f1dba9c80d04f1a71178237c5131ed09d5872f575a5c516a35e488d4e29bd074ef928366206185072863f17de83b55493c2d573b5f1e80edef39c71a3f81010001	\\xe2ff64d28de8af12bbb9a324b9628e41bf8bb4dfc962639c757eff45b2d4a7d01d8d396b46151ae9fb9f3526e6c9c7cd5a9b9b76544cb060b0129562083c1c02	1675677530000000	1676282330000000	1739354330000000	1833962330000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
419	\\xf2e3b47e8e42fb7b71e2a00345f3b948dd16a35181dd7610b5c7bba11fa001ca17f3ad08aaee6934e80a0bf8d515f19f4d6655459c81f52b992d4cac0ad8a396	1	0	\\x000000010000000000800003c830d0ac7a0eb4799f5845aed9b2654c8c03779b2a83a88e815f6a21d5330e491f2a907aa556f4a0c734bbb85ab35c0d6f2105c155f242835c41e4770fbbdc004e3ac52dc50e72b5da418d6b8f800d7f202a06f187df71edcf02e4e6b356d14fb4061bfe7f7db3e4a9bccc730644caba57c49f5756137783ebce1afd414a65eb010001	\\x4d240e25fbdc59edb564a3a1fe227cefbd3147ba313e08a872eb16224be00f12fb86f94421eca2f3c7029fd4c35e3f14464da0db03df241e2879aa24a2bc2805	1672655030000000	1673259830000000	1736331830000000	1830939830000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
420	\\xf643b0d8c31615d14cef61b2df796691cf17424bbc1e693cf037d18d3c84e96299765b158c8cc6a31a1e873e78e7dd97b0259cfa22b216c25aaa7d44572c3ebb	1	0	\\x000000010000000000800003bbfdb928d24cea59b778f65261098239b2ef62b05638e0fb39fae091d8def55b4d01aad01b3727a8c97aed020380d731fbc830258208f8fa4d7f7b472b7788c4dde8465a0cd2a1518c08d4f26635a559592b019d4e1f2c3dcf650c872ab813fe8040807884ac4eb0b335d994a1777d9f147a12024d086de37a4907e722b7a423010001	\\x077df9d6bb7c752ec2469ec1d79e9768a0dfc10e61a9372d898c15b64cb3b62f4b93a6f86c5406d9dee9e4f6e939be3520af836b990fff4b428a39e4626a2a03	1664796530000000	1665401330000000	1728473330000000	1823081330000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
421	\\xfd2f872b2a7e84fbac5e07496ad44b18124d76f9aec2a676d458652fa1df569b0719f7fdfefc13fbe76f10640dde6cf2c2a6038a47973e5720cfc80c8715322a	1	0	\\x000000010000000000800003cdaead475c81561d871205e3fbc7c80d63f52bf42df7fd489658f76dcc61f0a379b1aa6f26911a1f54e6b1f0bed9ac52e22b25e5fa508e11dd6e3767fa275037554fecc3f7bfd54de182c3dee5feb63e5740ce21fc5c2c3f68bba5cba82acd9268f60be26ca9dc67b106a29155ef766c97fe248ef2fb2ac7a694ee5152b8a37b010001	\\x13fb8cd8001148a741bb98d2b145f6fcd37befb358e1a66b6df97b6370ffe304113c937bd31751d1b388121243445d92ebd99620c41c48a59a678c41ed80da06	1662983030000000	1663587830000000	1726659830000000	1821267830000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
422	\\xfd1f364df95ea891b4c33b97184d1d287e849c0209331c2dfbaf4717ec9c52c489bd598667a1f1138e801d29366933c0c3071db7244ed87e238b20df99c3f3d0	1	0	\\x000000010000000000800003d3e69b696d8cf486321373f0020ff10b5b1a4e61039d63bc59887bf009a061da7b6490754d1f54cb0814579de59b04e764ea525cee5ad80769a2358f88a61c423c73f0e4321f9c60de3ba085b17f016fc1603228e94fa5e77f5fe98593ac993ca34d256f65294967e3198633cd7a5b7a3eda326a96d51f1e319a85c1ae30d1b1010001	\\xf88e0ad9c9845153711f6b959348a0de8ef614310269f1c2ee971c3d1178e4200001efff68160ed77a7e1df33dd4869eb5bb4069415875a7f59629bc7f5ef104	1669632530000000	1670237330000000	1733309330000000	1827917330000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
423	\\xfe83972d887309d08f34c35f9b43ec70d4da2c286126047432ab18fa1d59395a39a145f5dc1d3118b8b4e74f6e69fa9203760fa38bf0db53f17c7bb8d7576c77	1	0	\\x000000010000000000800003c0b42720054eb3e462d04b48d819c89aa1886fb9f0d4c510bfa28e8780c2596d7ef94141e333c26e4aa4a5e72d902acf60cc87df14c29f53340bf7b8e890b4e24bc6026abe1db5057a835d85f88d64ab52521221e026aeeff24e8b24748bf808ca79ca1744fc6d85e6c7a8851370b954952cb5c79788eb640938a9bba5516223010001	\\xdfca893d632906a360790b7c6fa5fa7963d682bca69f2a20b392fe2ebf0c61901908860e4004e1d95ca49a5e27c11053dde2612f846ea018d48e395cce1fe000	1678700030000000	1679304830000000	1742376830000000	1836984830000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
424	\\xff4f7e3b2d0a08da8574471e056556433e3b22a8592ebbd214ae733a53def38b2ddba8e1d97116e1f70408953cf4e1e6a9be850317946592eaa2ee10b8e1aafc	1	0	\\x000000010000000000800003992991e418c5a7dd416e9a66085085c50423d97ae4501deaf9c83bd3b08adf10a45ecf1f58146186137ce9c891539af65acb867ba468b8d8b24acd811d4ac8ab8c6fd96c8d8008f312684a28c6e07319bd02ba5f36f162ca038c8b82718ae5dd2381b8e6210cd98d08acce74ffc895bbabf86b5637f3a1597a10514fb2df175d010001	\\x79be640f3b1a499aeadb5409ec001c1f3d044a16229a14fa9804f3057d3933c09234f482f9d99e7275deabac699642f51873cf6e4ee92e1a5bd0efba90e81700	1659960530000000	1660565330000000	1723637330000000	1818245330000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x331e018582973b75a519ac558e66d2a7b08950465edbb021968987a15132eec6	1	\\x7c854be3f73f6e1502069277ddf7fb44312331ae9af74ec5d753f19952f9e74efd892ed4e025b8ae0609753e9df0945b40c3b862c3b4d4e9caade0db1c50a783	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0a886d4267b326cc81081afef50979933ad658549ebee455328c44e06380d4b7849db4ab9cf417b5ad029e38e05a917cd96db787e08eb26921650d6eb4bdc835	1655124562000000	1655125459000000	1655125459000000	0	98000000	\\x38699aa30e02eb3912f32943bcd591e28fd54115b73bd98fbefd1338540b881c	\\x99819bdfc598019892c2da9e55fcd3785681a5854ceee935d1b336dcb85a9bf9	\\xde188291797d30da54499a5c0ef26a4d86fd83d8e95f8425eb9fca01f681903bbce1ebc35a9f429ad8fb45bacda1bdcc9c82c355236a94012ced76b2ce148309	\\x09f2d99228e97dfd24242f178a7f59a31524b9a0713b04d84dfcd5dc43effa13	\\x901d8a8bfc7f00001d69bd67585500001d269d68585500007a259d685855000060259d685855000064259d685855000070ae9d68585500000000000000000000
\\x331e018582973b75a519ac558e66d2a7b08950465edbb021968987a15132eec6	2	\\xf0d1c6f9876a139effc975228cb2ee0719f8dd2615ca8b3ee815fea62d01f9aec8bc1171c88016dcef99521350c9b1754c243879b598607a76330b0484510502	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0a886d4267b326cc81081afef50979933ad658549ebee455328c44e06380d4b7849db4ab9cf417b5ad029e38e05a917cd96db787e08eb26921650d6eb4bdc835	1655729395000000	1655125492000000	1655125492000000	0	0	\\x09ae19ee26408cdd03660be69b56e8c39febcf097fe40ccee782021b1831282e	\\x99819bdfc598019892c2da9e55fcd3785681a5854ceee935d1b336dcb85a9bf9	\\x35e1249b45a3224c801af44e3f8d64504e1f01425f83d4c78c8d7ad360781fc26e5421c932b07608bc1fe7fd1a1887cc14c2ba6d06613a68ed1ebcbe26dacf0a	\\x09f2d99228e97dfd24242f178a7f59a31524b9a0713b04d84dfcd5dc43effa13	\\x901d8a8bfc7f00001d69bd67585500008d539e6858550000ea529e6858550000d0529e6858550000d4529e685855000030289d68585500000000000000000000
\\x331e018582973b75a519ac558e66d2a7b08950465edbb021968987a15132eec6	3	\\xf0d1c6f9876a139effc975228cb2ee0719f8dd2615ca8b3ee815fea62d01f9aec8bc1171c88016dcef99521350c9b1754c243879b598607a76330b0484510502	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0a886d4267b326cc81081afef50979933ad658549ebee455328c44e06380d4b7849db4ab9cf417b5ad029e38e05a917cd96db787e08eb26921650d6eb4bdc835	1655729395000000	1655125492000000	1655125492000000	0	0	\\x12f4cfc91cb999bb9bfa1487657c373cab576564b1c7a4f2446b3c375f4a8810	\\x99819bdfc598019892c2da9e55fcd3785681a5854ceee935d1b336dcb85a9bf9	\\x8f3e59af0241699da7edf08a6fccbe4bb2cd8bf14166d930656382920c6c9e3dd5eb6f971ebb61978de9434b6a1a754869ad23d57244f19731937e7f3b934900	\\x09f2d99228e97dfd24242f178a7f59a31524b9a0713b04d84dfcd5dc43effa13	\\x901d8a8bfc7f00001d69bd67585500009dd39e6858550000fad29e6858550000e0d29e6858550000e4d29e6858550000e02e9d68585500000000000000000000
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1655125459000000	390438120	\\x38699aa30e02eb3912f32943bcd591e28fd54115b73bd98fbefd1338540b881c	1
1655125492000000	390438120	\\x09ae19ee26408cdd03660be69b56e8c39febcf097fe40ccee782021b1831282e	2
1655125492000000	390438120	\\x12f4cfc91cb999bb9bfa1487657c373cab576564b1c7a4f2446b3c375f4a8810	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	390438120	\\x38699aa30e02eb3912f32943bcd591e28fd54115b73bd98fbefd1338540b881c	2	1	0	1655124559000000	1655124562000000	1655125459000000	1655125459000000	\\x99819bdfc598019892c2da9e55fcd3785681a5854ceee935d1b336dcb85a9bf9	\\x7c854be3f73f6e1502069277ddf7fb44312331ae9af74ec5d753f19952f9e74efd892ed4e025b8ae0609753e9df0945b40c3b862c3b4d4e9caade0db1c50a783	\\x6dd638885c495a12f29b31fe9a51ab81c6a45f80008e2175bb89d3a117086ab74cf07a1875f950c66df558acb6571d3d2367fe13813f44da80ce76fcf98b5403	\\xa2605c83e9eeb6a865403caa4895162d	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
2	390438120	\\x09ae19ee26408cdd03660be69b56e8c39febcf097fe40ccee782021b1831282e	13	0	1000000	1655124592000000	1655729395000000	1655125492000000	1655125492000000	\\x99819bdfc598019892c2da9e55fcd3785681a5854ceee935d1b336dcb85a9bf9	\\xf0d1c6f9876a139effc975228cb2ee0719f8dd2615ca8b3ee815fea62d01f9aec8bc1171c88016dcef99521350c9b1754c243879b598607a76330b0484510502	\\x444cf6735651973611c2bed47b1af191e286616b555270a1f9c03773e26738adf9293981752ee37d6768da582d7195f9ceabc9473a193236473f5f713244680c	\\xa2605c83e9eeb6a865403caa4895162d	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
3	390438120	\\x12f4cfc91cb999bb9bfa1487657c373cab576564b1c7a4f2446b3c375f4a8810	14	0	1000000	1655124592000000	1655729395000000	1655125492000000	1655125492000000	\\x99819bdfc598019892c2da9e55fcd3785681a5854ceee935d1b336dcb85a9bf9	\\xf0d1c6f9876a139effc975228cb2ee0719f8dd2615ca8b3ee815fea62d01f9aec8bc1171c88016dcef99521350c9b1754c243879b598607a76330b0484510502	\\xa6c1c78e45c8618668454de35854ffb145e4bac18e1fb2d9a9273f7596abab0b4922c6370254f689c8f5c846c3b80224a6bdcf28ac185898cfd5f87762c2d406	\\xa2605c83e9eeb6a865403caa4895162d	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_for_matching_default (refund_deadline, merchant_pub, coin_pub, deposit_serial_id) FROM stdin;
1655125459000000	\\x99819bdfc598019892c2da9e55fcd3785681a5854ceee935d1b336dcb85a9bf9	\\x38699aa30e02eb3912f32943bcd591e28fd54115b73bd98fbefd1338540b881c	1
1655125492000000	\\x99819bdfc598019892c2da9e55fcd3785681a5854ceee935d1b336dcb85a9bf9	\\x09ae19ee26408cdd03660be69b56e8c39febcf097fe40ccee782021b1831282e	2
1655125492000000	\\x99819bdfc598019892c2da9e55fcd3785681a5854ceee935d1b336dcb85a9bf9	\\x12f4cfc91cb999bb9bfa1487657c373cab576564b1c7a4f2446b3c375f4a8810	3
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
1	contenttypes	0001_initial	2022-06-13 14:48:51.180876+02
2	auth	0001_initial	2022-06-13 14:48:51.304152+02
3	app	0001_initial	2022-06-13 14:48:51.391899+02
4	contenttypes	0002_remove_content_type_name	2022-06-13 14:48:51.410204+02
5	auth	0002_alter_permission_name_max_length	2022-06-13 14:48:51.422741+02
6	auth	0003_alter_user_email_max_length	2022-06-13 14:48:51.433804+02
7	auth	0004_alter_user_username_opts	2022-06-13 14:48:51.443749+02
8	auth	0005_alter_user_last_login_null	2022-06-13 14:48:51.454386+02
9	auth	0006_require_contenttypes_0002	2022-06-13 14:48:51.45743+02
10	auth	0007_alter_validators_add_error_messages	2022-06-13 14:48:51.467794+02
11	auth	0008_alter_user_username_max_length	2022-06-13 14:48:51.484028+02
12	auth	0009_alter_user_last_name_max_length	2022-06-13 14:48:51.494351+02
13	auth	0010_alter_group_name_max_length	2022-06-13 14:48:51.507593+02
14	auth	0011_update_proxy_permissions	2022-06-13 14:48:51.518517+02
15	auth	0012_alter_user_first_name_max_length	2022-06-13 14:48:51.530151+02
16	sessions	0001_initial	2022-06-13 14:48:51.5524+02
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
1	\\x09f2d99228e97dfd24242f178a7f59a31524b9a0713b04d84dfcd5dc43effa13	\\xedd931dd96aa1050cfe741348561eca1957792c560faa4adf72d0537d04a7a5b3057577c3fe3c6993b41465cd28cf736c8748f307d5b74be7c294018bec21208	1655124530000000	1662382130000000	1664801330000000
2	\\x32ab435f6236f7f0a811c812ae9dc575b2432fd37ebae469dbd3865b30d5c47a	\\xc0adde33e4c3e48e0902e3be048f42ffedcb0e37c1c6ce929a5379dd5db5ec4e6d891d66f8a902e84eed078942f460c0d08932419be5d2617de7571638adba0f	1669639130000000	1676896730000000	1679315930000000
3	\\xf56122b2cd881f9191430aaf0197dc68d4228527ef1cd3de30fa4028e69a0127	\\xf5c4e84ff191eec717dfb735a40cb2e5b4699d749a20b131be45f43b786ad9755438966b9a86ba9900f58d919b2f686514c7394424195c1f749eac7655d88b06	1676896430000000	1684154030000000	1686573230000000
4	\\x765445af14e51fbba68812052afbb6eeb85aa5c73485d778286fc447d6449690	\\xc873787e621cb30fff9cf5cfba080897a98b1bb096bc1a29ad0635d7a31273c3dfd126aef4774a34210fc647c927cb7a8bb653074cf3b1fb530af087be1bc908	1662381830000000	1669639430000000	1672058630000000
5	\\x374ebf413ae380e0237a2a37443613ac403bcc70f5a5ab28c799e80d728d063d	\\x0ee46d8ea1ce2fc42ac92505264ca457edeb1c6411a8cf14a1d72461f9cf3eef72f637c29c56ebfba66b97cf15fabd55a052fcbe30305ffe339a21a61df0b504	1684153730000000	1691411330000000	1693830530000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\x0d56326aa9cf87e55ee864cc6952ab655bcc3186df7a384a21bc50f36eeeff15e8d1cfc255cbc50af72e9c1f832e7ceac3707ca35b8eca5b66deb1fff75d720c
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
1	191	\\x4af77fb3a37a61f45c5f622db11b409469c9994a8758c4c0ae3b5dfaec6fc44d	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000004fd75b13e9cdeacc2b6106635aecfee75248fb3089d50e4703a4927474b510fbdaf728deaecd7eae15ff82f7b10098ca37f718ef9a9f5b222057057639204ed5d5afa2b192ba8c7ad2181858a06bac30e36d87cb4507410ce78017402778b448aeedcb845d6800f866ee2c5a3b4277821d69f9de92122ed18c579cfb08219086	0	0
2	232	\\x38699aa30e02eb3912f32943bcd591e28fd54115b73bd98fbefd1338540b881c	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000006d938142996060a7de250ae42bfe937f295226a358333b29818de7c25b7da2c2d26c31031912961858804f9d95b0949b13d5e5b1a7f73ca34244b28766f8cbbf36b734f85764f6cd9d7dccdea76c776f87cc4a7bee06fc716bc09a3efa076a1c44b6d762c4769ffa79c29727619a1da1709880d37e7ee5db5bbceba39d01ebbd	0	0
11	388	\\xa9dd1a9f8d765cbc437fafb22bde1f7250f5e4ef67444c3772fd13ad9086f3f3	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000a4f5cd652840d05fad46161f03515f66d59708bbb552cbac9cc6757a81342ebefa334217563d8926154d209a6b3ca00e2531f3299eb98e5b6908865df12bd4a4b46a77d3c09dd8e39c4f0834aa05394362437f1f7a0dc791cbf05e627dcf3661f609b1ba7b62ecf507450d64f234f63ebaec38d05f7cf17449d965471c1a764e	0	0
4	388	\\x0a61ef94900235c474ef743d0933e7712c66cee6019e8a3b556a13987462e1ce	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000005f31cf2fbcd51a4ca825a5baf463edbb958e34b305f0e78f255371bd3cb3207294e92b6790bc0844d3a2891c74a3b75feb4b27d2fefdb79ae75d72b5c3b51502499df725e017b443c4e895a6042becfdda04acb03d2e2ea406586fded2763410a8bfbd134c505c907cb001bbae1fc0a298f4a589d375f229491fb2575dae2bfc	0	0
5	388	\\x0bec08acbc39b3fcc31f02362c6be70f5a9d1490d8d7dc8ac0c16d9730500ed4	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000002fd1f4c62887e753177def8f7679676cb47114539f1b3dd1c800e07c78465ec4fb54b45e30ec6763bed692ad83f48815d3bfef2a7ad0847160be39260a2e7e7ffd44fa045f74aa403b37931d33309b2fa048272e77f5ba62886badc82fcb8d76dc7d7382bfc2a86f73c5eb9f7d914bf99f29da09ef0c17dc8d0d32b9aafda052	0	0
3	357	\\x673e78a287285119533986bb82a871c9550d92732505a384175148cc0a601cc6	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000093f8c44adb88382bacf9208b7a0c2976e397a777ca762222ad06834bf48c10b5639d056a59d84c81b1821221a07d432cc8dab3517e844c4a845b65cf8b98e5bd10afcd920de9f21baa73f29b9af2cd004e763e32bb5db5aa3083e235ef36b691dc726e06cea9daeca5aae23ca8054c5ca5e9cf6c9d0d6e485e3a8047a62598cf	0	1000000
6	388	\\x681a8c0909da9a4b964ded67e843b9d5225b4d6ecf45dd13a4e9033ae1623970	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000a329bdbe4ba80e5e42b65305af52beae5f0e1f008edd761c4c935311830e4bada1812ae9c95cb8cf99def727c4120850793e9164545bb7c22469bc157721f699acc29f7ff92fa6068a2661f27c54a79041a580fdbb91c96cdd775fe5b205dc18895097128031079735f87956cbd43eb8ade2f709c023c64f47b8ee7516bd4ec9	0	0
7	388	\\x898a0a28802ecd923e42d9e81c18413b30a0096a100d1e718524e65790418830	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000070c4cf1f3db78c559f2b04e5d5cee5cf02fcd227fdc47b70d1909e517fbe3e7d75a8e24556e21caf25b46efa8ba622e6d6c24987d08faa51ff6e5fa540e75f1ac1da1ca56e7d6e62e33f3fdd14b06f04f5bace84b685e189eaf2afcf113b1e9e192b664bd046c2743bb7b20d0e2e74305ef939c9954548a1c327ac6ce8aa7414	0	0
13	404	\\x09ae19ee26408cdd03660be69b56e8c39febcf097fe40ccee782021b1831282e	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000ae310f83ec170af65a67a8fb5283a29cc4df222d3843f481cfabc3193995cc0f50728344234dc549c423c9b74df549536fb2d26f50ce06ddb7619ec323cb2439d9f3e606b282ea4521a0e591130e66c0cc992a01ca77434a3c746226ee67ac40398089303e1a5ad5379711255a2fa9bdc22fa98cf7303e4976a25e79219c8bd2	0	0
8	388	\\xb627ad627c2e692e96d682f7b6d1070e4793c2b9f602441c194ec3166f684ac1	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000b14dd4b80cf8222f943dbe3e5691541f1f169057b30d1926b0a828da795eeed950d4212d4263cf7f929d52d6b02ec2a5a95beae988c2023b47d9aa6910cf95e692d01e1a319346eda31eb2fb3f381ce40d70a0433b7d7cc8ced36831a2ebac7a8b5788ec10a7a104463d62b08a296398bb37d969a1f39cac7ad9bc442e61893b	0	0
9	388	\\xd59dea66f8ff5f25893f0b67c51b3e264faf7d47429f39da5a8198f881709c36	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000006baa1b98d4c9baa8f12f4e108f5064e6563ff329b19291ebd3d7d235e8b2e8997ce3ee985f42bfbf5a08105aabbfec5ceff1038194f336f5e62097759d2a28adc91e74bdffe03dfff9f5e9679d3da09b2cc1d403422a381d3be1686e37c17abcbfb4e54dbecd6c556ad86b5af00fa866de421400cef61ffe660f351e846d5da	0	0
14	404	\\x12f4cfc91cb999bb9bfa1487657c373cab576564b1c7a4f2446b3c375f4a8810	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000005faf0a2775ab6e104ef79bed24f5c3611e0dd41abc7fa148e29b3b403d9504f132ac4995067441567b0a0c1e82cb4d15185b1b594c264d1be2ee464fe4c22c91624e5f2ca66202b58563a2fb04d406c05da6f503d46a1360830b8a3cab7cbbef6332e175a0171b8dacf5088209dd0c89041ccb9738a0f35aaf328f5124b98d4f	0	0
10	388	\\x30d758432b61cebe2a36811190a00723fc1f569e9c730b8a60f85a8f7e8bb3b6	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000b524a4dff28bb308e3d1ddba92dc6bf3b416ca0f74cc7830935072112d50c55bc5e2c23efad8f2aef8e8e33fd7b225ce024462f58c36c9f860b41235a0ee4adf9b29d41a2e82423501ee7bc372cadf86e3e0188a8663c00de462fc161197062591ef1024496040259bf3e0df87ca881d059b52a0749b4120c3374d0d73d0b9f6	0	0
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x0a886d4267b326cc81081afef50979933ad658549ebee455328c44e06380d4b7849db4ab9cf417b5ad029e38e05a917cd96db787e08eb26921650d6eb4bdc835	\\xa2605c83e9eeb6a865403caa4895162d	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.164-01EC3PJTNNG6T	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313635353132353435397d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635353132353435397d2c2270726f6475637473223a5b5d2c22685f77697265223a223141343654474b3750434b435330383833425a46413242534a4358444350324d4b545a45384e394a4848324530525730544a56523937444d4e4545463835584e4e4d31395745373042413851535042445059335931334e4a4434475041334245504a5957474438222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3136342d3031454333504a544e4e473654222c2274696d657374616d70223a7b22745f73223a313635353132343535392c22745f6d73223a313635353132343535393030307d2c227061795f646561646c696e65223a7b22745f73223a313635353132383135392c22745f6d73223a313635353132383135393030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2236434630333143324a575851423938534e4841525753504a4d5952384a4d3236425644563038435048363354324d394a58563330227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224b363053515159354b3030534834503256414635425a364b4631423833394335394b51454a44454850435644534532544b465747222c226e6f6e6365223a224353594633585a504541425859524b52544a544d4348324338443953305a3631514651434a504853425257525239475453535147227d	\\x7c854be3f73f6e1502069277ddf7fb44312331ae9af74ec5d753f19952f9e74efd892ed4e025b8ae0609753e9df0945b40c3b862c3b4d4e9caade0db1c50a783	1655124559000000	1655128159000000	1655125459000000	t	f	taler://fulfillment-success/thank+you		\\x6a60168b08a79b9f7920efe472f7b115
2	1	2022.164-03MDC8HCEHNH2	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313635353132353439327d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635353132353439327d2c2270726f6475637473223a5b5d2c22685f77697265223a223141343654474b3750434b435330383833425a46413242534a4358444350324d4b545a45384e394a4848324530525730544a56523937444d4e4545463835584e4e4d31395745373042413851535042445059335931334e4a4434475041334245504a5957474438222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3136342d30334d444338484345484e4832222c2274696d657374616d70223a7b22745f73223a313635353132343539322c22745f6d73223a313635353132343539323030307d2c227061795f646561646c696e65223a7b22745f73223a313635353132383139322c22745f6d73223a313635353132383139323030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2236434630333143324a575851423938534e4841525753504a4d5952384a4d3236425644563038435048363354324d394a58563330227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224b363053515159354b3030534834503256414635425a364b4631423833394335394b51454a44454850435644534532544b465747222c226e6f6e6365223a224e59364e47384553434551365a52304a574a524a3838444e4a434b315a385648374139525747513652445053394e513535413530227d	\\xf0d1c6f9876a139effc975228cb2ee0719f8dd2615ca8b3ee815fea62d01f9aec8bc1171c88016dcef99521350c9b1754c243879b598607a76330b0484510502	1655124592000000	1655128192000000	1655125492000000	t	f	taler://fulfillment-success/thank+you		\\xd894e6781be569195a9a1b084ba0e9ea
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
1	1	1655124562000000	\\x38699aa30e02eb3912f32943bcd591e28fd54115b73bd98fbefd1338540b881c	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	1	\\xde188291797d30da54499a5c0ef26a4d86fd83d8e95f8425eb9fca01f681903bbce1ebc35a9f429ad8fb45bacda1bdcc9c82c355236a94012ced76b2ce148309	1
2	2	1655729395000000	\\x09ae19ee26408cdd03660be69b56e8c39febcf097fe40ccee782021b1831282e	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	1	\\x35e1249b45a3224c801af44e3f8d64504e1f01425f83d4c78c8d7ad360781fc26e5421c932b07608bc1fe7fd1a1887cc14c2ba6d06613a68ed1ebcbe26dacf0a	1
3	2	1655729395000000	\\x12f4cfc91cb999bb9bfa1487657c373cab576564b1c7a4f2446b3c375f4a8810	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	1	\\x8f3e59af0241699da7edf08a6fccbe4bb2cd8bf14166d930656382920c6c9e3dd5eb6f971ebb61978de9434b6a1a754869ad23d57244f19731937e7f3b934900	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x331e018582973b75a519ac558e66d2a7b08950465edbb021968987a15132eec6	\\x09f2d99228e97dfd24242f178a7f59a31524b9a0713b04d84dfcd5dc43effa13	1655124530000000	1662382130000000	1664801330000000	\\xedd931dd96aa1050cfe741348561eca1957792c560faa4adf72d0537d04a7a5b3057577c3fe3c6993b41465cd28cf736c8748f307d5b74be7c294018bec21208
2	\\x331e018582973b75a519ac558e66d2a7b08950465edbb021968987a15132eec6	\\x32ab435f6236f7f0a811c812ae9dc575b2432fd37ebae469dbd3865b30d5c47a	1669639130000000	1676896730000000	1679315930000000	\\xc0adde33e4c3e48e0902e3be048f42ffedcb0e37c1c6ce929a5379dd5db5ec4e6d891d66f8a902e84eed078942f460c0d08932419be5d2617de7571638adba0f
3	\\x331e018582973b75a519ac558e66d2a7b08950465edbb021968987a15132eec6	\\xf56122b2cd881f9191430aaf0197dc68d4228527ef1cd3de30fa4028e69a0127	1676896430000000	1684154030000000	1686573230000000	\\xf5c4e84ff191eec717dfb735a40cb2e5b4699d749a20b131be45f43b786ad9755438966b9a86ba9900f58d919b2f686514c7394424195c1f749eac7655d88b06
4	\\x331e018582973b75a519ac558e66d2a7b08950465edbb021968987a15132eec6	\\x765445af14e51fbba68812052afbb6eeb85aa5c73485d778286fc447d6449690	1662381830000000	1669639430000000	1672058630000000	\\xc873787e621cb30fff9cf5cfba080897a98b1bb096bc1a29ad0635d7a31273c3dfd126aef4774a34210fc647c927cb7a8bb653074cf3b1fb530af087be1bc908
5	\\x331e018582973b75a519ac558e66d2a7b08950465edbb021968987a15132eec6	\\x374ebf413ae380e0237a2a37443613ac403bcc70f5a5ab28c799e80d728d063d	1684153730000000	1691411330000000	1693830530000000	\\x0ee46d8ea1ce2fc42ac92505264ca457edeb1c6411a8cf14a1d72461f9cf3eef72f637c29c56ebfba66b97cf15fabd55a052fcbe30305ffe339a21a61df0b504
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\x331e018582973b75a519ac558e66d2a7b08950465edbb021968987a15132eec6	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\xbee51369ace82f18a208e7c249ae8cd38c0d66171a08bf86aeabb2f776b197c52cc5e48ef29b3e73a010d13bdb1a4e63c5c4787a80d154bc50daad1a4996ec0f
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay, website, email, logo) FROM stdin;
1	\\x99819bdfc598019892c2da9e55fcd3785681a5854ceee935d1b336dcb85a9bf9	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000	\N	\N	\N
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
\\xa0149adb9cbe51d910223405295a0fe9a9c2bfbf289d1d6ee534e90533426e1e	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1655124562000000	f	\N	\N	2	1	http://localhost:8081/
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
-- Data for Name: purse_requests_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.purse_requests_default (purse_requests_serial_id, purse_pub, merge_pub, purse_creation, purse_expiration, h_contract_terms, age_limit, flags, refunded, finished, in_reserve_quota, amount_with_fee_val, amount_with_fee_frac, purse_fee_val, purse_fee_frac, balance_val, balance_frac, purse_sig) FROM stdin;
\.


--
-- Data for Name: recoup_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_by_reserve_default (reserve_out_serial_id, coin_pub) FROM stdin;
2	\\x4af77fb3a37a61f45c5f622db11b409469c9994a8758c4c0ae3b5dfaec6fc44d
\.


--
-- Data for Name: recoup_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_default (recoup_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, reserve_out_serial_id) FROM stdin;
1	\\x4af77fb3a37a61f45c5f622db11b409469c9994a8758c4c0ae3b5dfaec6fc44d	\\xf688c31df43da29b6e5a47c814e805527167c2ecabee9563b5018060587be449ffefd6de24cdf327353e159fc3d1d442e8276afd715e5abec208dde690041a0b	\\x4d52c38e21cd7752b028add950c31ae8fed91d5d17ffa6dc9996c0ee1bdbdf41	2	0	1655124557000000	2
\.


--
-- Data for Name: recoup_refresh_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh_default (recoup_refresh_uuid, coin_pub, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, rrc_serial) FROM stdin;
1	\\x0a61ef94900235c474ef743d0933e7712c66cee6019e8a3b556a13987462e1ce	4	\\x0148ca7b1d6269b9f28ff2aaddc0a783a9f8e51696f6eb54fd1f82457f9a00747efa6cf3023a086fff105b224f78264daef33c8ba05c7f200a1a2d2e2e7c3c02	\\x3e62aa8230685a66da7c2f627f4c41c3c891e010ee5fb6fd34cae82285ff8a3d	0	10000000	1655729381000000	7
2	\\x0bec08acbc39b3fcc31f02362c6be70f5a9d1490d8d7dc8ac0c16d9730500ed4	5	\\xa57df51aee53a2622c07f049dcc78fac3d34ab0666713ae14662b5ff6257099877780143a5f1e1830eba48c2ee492912dddfd17d1d5728a9d306a80fb9820f0b	\\xac52bdc1a58e28b0038eb8c3057b23a31541c6b6a0bc3569bcc71e7116cdbe64	0	10000000	1655729382000000	5
3	\\x681a8c0909da9a4b964ded67e843b9d5225b4d6ecf45dd13a4e9033ae1623970	6	\\x8c1ed3b7d23528c5d4a4c8e82dda381f5baec7bdc5125047ab0d8023e8b58f8196d014a0e9377801ed0acdc74ae74be7016eb38a50242adf6f1db23e02dc8801	\\x9bfe1ed3fbbd10f0e4f4e861dc45605381ce2c79e9444c475fe2a0468c47fdfa	0	10000000	1655729382000000	4
4	\\x898a0a28802ecd923e42d9e81c18413b30a0096a100d1e718524e65790418830	7	\\xcd8e1713306e67ae7f011056e88a9b8d8e624a90e138bce5a968db6670cc8607762548ad034e847dd391659aa2e804183e023455469ea97164ee5a5f52305806	\\x55b1b2abe266e5e172f4ee1cff4d602b5d1c09c48e59e49f28f9693f1952bcf8	0	10000000	1655729382000000	2
5	\\xb627ad627c2e692e96d682f7b6d1070e4793c2b9f602441c194ec3166f684ac1	8	\\x8f90d8ad7b288f44e2101f542c85dd14d40181636758659b2bdb984f2139111b116858edd0e10fec9bf14e70f9c14eb12e96230413fd911d7bf40ec3d82ebe0d	\\x8cc544d0334c4be03cc0764432e2642a7adc51255f9a5358466234153afa97da	0	10000000	1655729382000000	8
6	\\xd59dea66f8ff5f25893f0b67c51b3e264faf7d47429f39da5a8198f881709c36	9	\\x2c6b005baad7396977886182c7ee7ca08dd507ff303b10c79a00486527e58cd9bd576e3f94780c501ee85cc60a7c616b4834708d321955040dac17e1888cf40a	\\xb8fa1efbc281b0b0816b978225907853c7e7f05a04476f02766a899b0a6d7451	0	10000000	1655729382000000	9
7	\\x30d758432b61cebe2a36811190a00723fc1f569e9c730b8a60f85a8f7e8bb3b6	10	\\x34c610e7f3bb4a6d44c7699fae4f8257814cdad7b5d8c15ec075e4cab1d23a5c9253bef3aa22c2530a7b1fed15d2ae5d65f3af2fcb22e680cc460208ad87680e	\\x941b9a80c6019a82779ba11e23ce0bead8cd5d7e4f2a1759047e571961262752	0	10000000	1655729382000000	3
8	\\xa9dd1a9f8d765cbc437fafb22bde1f7250f5e4ef67444c3772fd13ad9086f3f3	11	\\xeb0a996e6e21b666d2dd1b97ac3823e528e2ae2a6319ef3777f9781c5b25e60dd17217b976ed4afc5f68660d0f958c72c056f567119b657b73abc5abfd835102	\\x0d4b0ea6482f6ee21a0fcaa5a92e3157bd4a3e337aba4ec4502aca8635df264f	0	10000000	1655729382000000	6
\.


--
-- Data for Name: refresh_commitments_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments_default (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\xafa8995ac7f4c1f1af1b74289ed7484797061366a0a454cb096859a3aa800f1d80e4840f0a70aa7ad0b2af9e339a289189b3a69dfbfc57a160a42752153d1153	\\x673e78a287285119533986bb82a871c9550d92732505a384175148cc0a601cc6	\\xcc9557f675da1876737e907ee4b8e64923bcb1e9e37c421d27ff1d2f11eb6c459903b223bd4b25d4c5f154c9e75eaf88f7a3e6a01d3afed27f95a4210a8f6006	5	0	0
2	\\x47825773d149f8f6116bab30ba21ddad0b7ffd88a44e76f8a7820dfbcec319cde38cfa7c2fe9fbbf8e35a7870028598af1333ba0e5637957a58265164a7cd72f	\\x673e78a287285119533986bb82a871c9550d92732505a384175148cc0a601cc6	\\x34cc1e0fc5649fc81c4ab424b110569dd98bcaea244ca9a8254cbbea096218f62300d6db2c07dfbf9e1de163f439310b947190483d5c2a6ae870fce12a99520f	0	79000000	0
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\x7b7a777a89fcf989946d24b76f77cb73d4a7a1c60d6d5f0fa72be0e3d9f89b1d8d50a274d17ba62c5b4e9d05ec2494e9ee264c288595e7cd91fba36b496c1e07	130	\\x0000000100000100150f01e95350485a6f53c8bf3e5c5f77edbbd70170ad3a16e08a39af9878ff96b5d0ff5de31603de7ace7ad7080c7456b3365a32842996be0fd9e95b30d89af7298471465b1afea948c915eacd2660c21d01601c8f9807b496cecf6ff85a2159ac3ebff176a62ccb96da78dd7e40f2d8fcf57c89201d2b40b74ebea524540674	\\x951c4d7ee28a23d3bf3b53e30fa25c5f3460d44d0c0b716891477f72e3a496141038bd9bd39ad7c656f02284fae4d9402563b558e782ab692ac3b1367104d231	\\x00000001000000012513cd7855c54de0aac9d5a7f28a83ddb19f7fc47ef075c13aae08f374c0ea078f6fa33a1c2b14d14d37fda791f28657ed282a850405e7733a1bd8dab046d829be19af43dfbf52a5e5d93e41778d2175c4365f4ff60c497078d2ccab48f4f483370ad5d0e380a91d3fa8555eac6b0b32cb3882e7f7c4e7033ffc6e44331a1b37	\\x0000000100010000
2	1	1	\\x892d15771f81009ae9584b6f77d70aa6c61594d04b661bb62c873a06c2537feaf5aa4ed736f5e3809e5d056001f3f198b27a09e9f6f8b0ebc0d5d70c7d1ebb0d	388	\\x000000010000010086289db5f202b13534ab2be533cc80f48a30acb19085fdb6024dcf658bca5da342ba85f6687271a73446ca08271ec293be00dac03a3df87a7780279208071ff15a32c4aff33eb582688af5d904ba26eca6b9ecf0dc495f5499c0a9ebb3c78e3b2eb47e1382caa4619c4cc762c7507a50f8795486520efc2b6ca5c25cc6cfb812	\\x9b3c402d5b0421ddc41a4a637886ce8697a98d61acee26a0166170e569b6929dbe339cfe7e7bcc9e05c0af2fbc496c557a33cdad5628acad11a601b24b2abe9f	\\x0000000100000001b9c78b76d3b63e84316fb0a5e49d9d314b98aa01ccb172d904695cd23df255a5052f57505b7c477f8f37b4a2f4f9005d407ad6d436881c567ab87dfb45517a33b25c9ce626ad564209a36031e982444893001f5503d2c21cb16625fc536987225025f128061f15a9f657f23219ef8c2d8df8bf447e56cdcbbe8d4b2620039fa6	\\x0000000100010000
3	1	2	\\x4adb15da79d0e10d7ba668d0c0e6c4e7e21157211900d4b9accdab6abbb708aa36ab895ac7549e3732b431f97bf71d852b01f145e210c611b6c39c9abafb0a01	388	\\x0000000100000100820111f724ef0a53a31e0346b47dd0addd2fc5282de713689a336fa4b3507711d7174835ae2ade7004398e41f9768808253b62b4bdad3d2908e5711eb22050b8987aec08f936d2ad50336f4eecdfebba881d0d99ba76cf238d92119af4c86e28e871cce27326efadc7bba35a3fc7738f0a2e70c6c43ac95346870485c4ad1fee	\\x3bfa5c9c9fa0eea1001fe89624328d1e410854922807fc49cf314b43ee012dba916f59225f2aefffc8d73fd2b7d98552c388a452260545fc78d806b392a77f08	\\x0000000100000001bb4389c520d35e7830547d3ef7346aed04868e65812be5a5c30c8c4ea61bc1c8790874d6637692ff3216acfb9e7c403b4a883d85f4eb17f78130a269008b3ce368ee1ecdf6b14636ab6f161ad78764d9a2eb7e6ce34f345fa18da4c56c0738d5acb69e4d4a1b30e8e2f7a96ce90c8b42bd7615c9ca1bfe71666c1877e17b0e68	\\x0000000100010000
4	1	3	\\xec67665a9c9b80a702f2b375552d21efe1bca600ec240e6d9f713aca19ee3b1e22984d40919991425f19fa13d8b294b05d0addc91493ff0148ef69c73031c901	388	\\x00000001000001001b2b68012d7bec00ec14042dde05c95ba2ac68ed550b0a69056e9e6fbb09dbbc72c48e97fb107d705541ea26f5afeff89dd2996982f55f465a6c6d5b80cccb7672b5d2c2c221bb5f45dac8ea952189f1266d7ecf58e776b25fcbb083d2d61f91ed2b217a8f1291e3552de6c86b3840c8ef2082edcc695288f2149feffddb7836	\\x56dbce4a66dd3c510a0a7136d962257689fc9ec612e09d597e04db87851adbce2a33b2e18dc27880c76c2bf1369973f630dfc927810d620ed85d070887ea56c7	\\x00000001000000018803e2c508cfae1ecdca84477a20e5fb08b8d1f73513e1577d2d20206252d5badc39fb61d3d42863dd144ff02a510fdef573cc82696c701773795f5198647c97f81ca4070a6a7f128f81aac74fea7de4b9bfe6ad19f25a0a57afbecc569e3a9e06df3a1c8332c73b804a365eac1daabcd9b44c5c553a7dcf80bc6dcc37c724b9	\\x0000000100010000
5	1	4	\\x3391cac3a4d33dd4a228faca6f8e369506fddaf18a6596e95b8023832305dcc7b96b27165b43a5bbba53228b9ee35dfe69574ee779a05e2ba7b86cf48b38de08	388	\\x00000001000001004b5844b6428447496568d64bc8769e630ecc5d704d36bb368feb50eda4d3df4779951c78a83eb88e4428f74e6aa0eb7ca3bc9e1d4be5fd8a9c92b03d656cd5502ab7eb09fb048f3f081b7708ef9fd180984d9889ef39bcf0a8ed9a5d759eddcd93163c12d7d11d78eb8d5cdf1ea185bdcff60d764a7ca4916f4676ae23dc4160	\\xebafcf5623668b525f357ebe59bbcaff9009c70a61cb7891260685e4f0640ca8806b78a04fc62928eac5883adb0220270bae967457a277e9babb2190945fd4e3	\\x0000000100000001ba9ba946315b336265809690363eb0c0d7d4276975c5d3cd0a6c22c8566f8fa5b2a599bbe8b10a17d46c29a6216e3d3459fad9479228dc1add9781e8bf30ed01a19c5514e0e5f6c7a9f007afda1ae4967f3ce626d12c1ffd05a49b70183aa2500ba5cdbaa1550e0f05cbca1ef6015408cfb2e5ac945e91cafc7a0fa0de25ec0f	\\x0000000100010000
6	1	5	\\x5e9df0144d6458959a285f5163641b02bac140ed614ba771db3a023cbc970f2dea8cc46255687e47d603e7ec262f789c85b78ce0a319c1e10d2d5f8b22975a09	388	\\x00000001000001000e32bad3819baafd5cc020d960a57f2b71348242005bc8b0e716c4473e60d9c5d8748d8b328297c8fb075a4c6a191eb8cd1410b18b1230cb6d298172631665d3732c3c025fb0ae95d84a448c535a5379d4003de78bafb34b03fa6b6ed8c8c71f4af1483397f3e5a3d5913d407b537b7554b51e23d121183e5b2a7cfe575a427f	\\x257141d07c73519870f53aed97b2e0de5663173fd1982741d51919a686a615017d6535c90e662bfdd251ad4a5c0e05e7ea250427f39d9e3c9582f66bd3134901	\\x000000010000000147528f64f00522d1f31c1d820c6ab1f7dce06cc73eda49ba90efa81dbde7cc98d907e73a1b4f11d0d7348ff08f1a1f78c4bb3c232fec73630e321b57a73b6be8484d6d180b234642168db3d355f1e380cb6e5e720df36ab94d3d2434f268382863579d0e15c0e2c86c320858bbd76337c5c1d58a11600425ef6495eecd121fb4	\\x0000000100010000
7	1	6	\\xad053901e841789a748afdf93fe4cbb71d2ad5e4f307c3be91d42e9117a1ea708826089cf179addbdd61dc1129e9ad73e81a791abe46eb4df6a89b63ff5dc202	388	\\x000000010000010081f99ace82afb6bfafdff1b8c96bba94b8b09d25cfc14cb7aa9f06c1f032845462a589dab60f8de09728aad44bc9b8df0f04c243ad956afdbdd1b5f584a8b048a026f7de3930f16c18e041e879fc18ff9d9a1381cb48246e1f309f1d81287f347e24b014261939181644d8474f9d6b97705a355ee8dfc276128635db60aacce4	\\x173adbe554975aada24ffb37f88109b81f4da1f708b7dd2e327a06fd092b00b10c1693dabfd44646302c6cf0b9ec23890d02bf35b73f95694ce408ab533425fc	\\x0000000100000001578ea8ae8115be5b50fd5d46091ae7e24e83d1fea2ba6c4af8ca9ba3d069e674001c38ad2c0c0be8c66f1eae9e4e5022159537e471b01734975db0c2773d19c6b07019b852ff5c07e95472a5dbc47c92abe468c9dd100a4913fefdcd377581d8b7ba51ef431b00eb87355cd7ad47c2c455c3bd66e55ba497baeee0d7c4a6b00b	\\x0000000100010000
8	1	7	\\x65c7a7d91bd9bdefcb99db83c41fa8cb02781e9317bf8a970b90de6cd2caefc13de62a3b3011d1f0174c47fb4a08c51234477237c4ac46aebd9a358e3c0ee009	388	\\x00000001000001006a73402d57c689528be0739b1d5a17e6917a6fd7c6e763418d1f17398f37b54400c179d031209492d2b9a4fafe5f012fc4acb444b0dd51f9ca755fe501a2f48786eeb29d601ac9d36a531c1c28a98230f229c369480a4d70f0e19c3c8c8040b0da8c618690509d901c1d07e4b3b79800aa458b6e2bad30074b2d36d5765d6d93	\\xf00908a650b6e602875f88639a73094fd860043224cc18ad86c10797caa0e8142269eabbec301565d02f2f552e3d7872561c837d06495d3ea8753f57e17befe1	\\x00000001000000015427f5fd2e49a5469e0d4ac8d0fa3896980367a6834e6abd40d129661fe3372c524e8970aa47ef0e1488ec2ce2ef9fee0a8bed07bc3dd61b20806dc4b8f18ad8da0462257dc4c9d84ece0db91841845200eaa6b128f113a2c8218d958017d51ac24fb4c60084f3701a8ae56871da94806862a16c4cccb4780f18e480de9259ce	\\x0000000100010000
9	1	8	\\xb8b332b101fb6428b72cf00154635e742bbaa85721c2c368f21a56c4d71bfb6ad1d39ebe3a17e1716d415c4f2bcf0e5ff6899f78912b4a5de187a272fad2e90e	388	\\x00000001000001000b3ef4377db8e71914af2919c6b83691f7e12055b531b6147bca4d5106e8aa3c2671959254ede2894d380f60abd10b3dfe0ea19361da45acedc5ead4a1679c03a6ad61ca9321bc781e0095dfbfb79bcb9b27324545f135f772ecdd947077bbc3062c7e91ffede64cfc961bb3d7f3e8bb6bc445a9a274aad7cdf9d20ccc26e49a	\\x6b5c1d48933b9b94bffd7c46dfd5dd3a58af71bd6994e4945a5c1a58b45c3de1da0ecaf6817077c69bfeb6c2a9a4f85deaed4dc7c878fdddbed01bbfccb939a1	\\x000000010000000170adfb50eb1546764c5cc1fb5de7bec884982326ac98fbe812d4781365cc6b88b7c2e60be4ba1ac23e6e3af099d8c425aaf8c89342122c31373fcf81c8b1a983cec290105ff2c73681ef01e74300025761c9250838da59de18de779ad7daf56a6424400c34b623c1b3d5d867c9c967d5aef84e89ff9daf5987b315ba7e7fe009	\\x0000000100010000
10	1	9	\\x48821d511461dc2a913713b3a03f9066cc8cf37e07fb18e89720ae84648ed9da021da95d93e5bdfa375da2f54eb7d8d0c0bd13b75abff87aa8bfb65ef948d001	404	\\x000000010000010005fbbd5af2a6eacf461ea9a278374d45cd3cececd5ee7b55256cbbb91870550ebe0eaa9ca315a4d008107aeab85bf242c470b39e88ca52f9ad25d503a8a2cde82551981655b444438a1f09483e8ae9f58114f9eb9baaeb4f6f146ffbdda75876353a90f0227978739fe161a7d4107073937a338a67ad6a4d81e8347a45df7518	\\xbb0876af02f666e712354995e9735bf8a5ff85d0ea13179af62e2dfdc39f950a457f9511951b3c2c352083aa9951aa1871160d3871304e0b5fe6b65e3db1fde0	\\x00000001000000016ad437bb6f8174c79533315fcf08e151b2e165b20c6070ef29bbb75f128a2fb2b5ad8876a100f2b2a9406f6d6b13a3827765af75972a15b9af1da08c850bf379219eb80385c19948c198f70e44d16b600548de9b3bf862f03a60221a475a608248a49f00ecc6a1afae813a4dda81a8a3fe18beb16b00fedfe8e0e90b8b05c258	\\x0000000100010000
11	1	10	\\xed3039c1afb1cd9cb7e51ef6a05468224eb6a77990e5df56919d704cc6beb17c8f45b99b2473cc1aa753a5b741504b1e6e291b771145fff7fc3f543cbda61105	404	\\x00000001000001003dc5c8bcc661af7666ca2e2045f018c9b6df91bb8bf1d547529047719f658817f47592c628bec176662e22cd872dcd060bebdd9d0d4b97f053f84daf0db704a869c0c8cd2a7930813914b91b8fdf07cd047714f6a070e79a5bbfbeb22bd5c1e92b7074bd0de49109779c6e39700e9d7d11ca9f234b2901895fb894526332778e	\\x380d4d7b177a7bdfd5b9fc1206630ff97f63e4296e7e94a83ee9fadd94aec0b8e2b424d53f3da0da9ae97de713ab7d9b92b3b75e2f2242497797a04bbb31c0bf	\\x0000000100000001a21726c4e354a3bb73909b0c8e4057b480884f308149a84bc52eb90296cebae057b0de56d631376c40341dc4863298c2c8297fd26c68bd088b4deadeb46d7d715038945f83df8bbc74818110889234f77847e0786731c06d0eea39837a4599b234ca17eb58fe6e03b322147aa0c736143563e1d04e13c3d9e21d28607082d1fe	\\x0000000100010000
12	1	11	\\x4cf4c939daeff7a13804a5250fd548b07f54120779bd7220b58c0b5ceda6a0c5dc8cb4bec1565006933710a0a62efb0c307ba9cca3f2c88f0311379cb76aee07	404	\\x00000001000001008b29f147e8706b990871fa5439500c3a0bcfa9d94686e67beaaf55a60bf766be66c69b6d4f6f6eb87b64ec8e73bc4512e71b22a59b85aae37df340013c9ab93f559df398c96954f6c92431cf2b782108ea7eccba0dc98817e52df79ddae1186df74b3dd9c6c08b8d0a1eb805bd64735a85cc7a22cc9d8b63cc8e504eb1e1fc00	\\xedbc05378a99b615ce2106e2bc759e0f94a9c51dd000f7a1b2900871cf07a9b03191fd78179ac1184a002c763244d02792e005ea2e7862f76ed0a0b58283773e	\\x0000000100000001583e07b7ac6523767993fd2fdeb7ef25ed31721a17a06896b7a8463189b3c6d9b7f77097a1b71e75c0d47d283a35c8c5693585d9a80d9eca8f1eea64fc30ce90a65cb4e6397086a99d15a78a36444e4e912cdd4d9b0d2ef8fe537319d2a77513567f612369768b5dad3483cc95dd38bb5243d3dffbd0fdc16707c1260f2cdb31	\\x0000000100010000
13	2	0	\\xe244680bf1065b46405b566ddbbb3d316679bcb52ce5c3174f3d85edda3dafc1a6140c41e8df76f9b2b0af8ed7deb1dc7e888bef5b630ac73cce12911b7ca808	404	\\x00000001000001006e708beb912d85b7e4a74c50d3f2636bc61bcb56b7b51f1996116ce83433e10f37e081f3d4a7afeca223afc79cec49bcac18aa08304e45fe5b7cb7a22ce27759a369c30838a70657e2b89083e1d8bf2f4db70531570fdfe60b95c5bfa88fc1fa5c4a8a78237c49841dbbbea0172d34dbb716dab6894b6d58593aa0fa973dcf67	\\x2e77b617d5814d0aa72129006f0eaf73f2785e07896bc8cae8395a59d656288ff174ab6b6863adb24382205e33a8b7bb59c2ab9e4baf281f972aef9ea1026792	\\x0000000100000001011a362eefe94f3b579ca54a9918856fc1b681fbb1af0cbd587414dd56bd5ab9ca167ad2fd9d5ede3c519f85d5e08b5d677dbfce56589edc3e175c315225db38e7fa3d24a182a3d4b986b1aa41a2e2cf0b1b8e0c98dbda712af15385481828830fc77bfa9df2e22bac3472357fbaa9731561729f3a150300b8cf0de74a5b9977	\\x0000000100010000
14	2	1	\\x86881d178af61a4fb6f54ce7a8cc881784f491bfefe45026a2c6aebfa7d753c23d10ec3107183a7dc2d403a93701d904fe76087ef8b6ce7a96ba95830a885f04	404	\\x00000001000001008be6ace4c44019cc5627a4baaeefaec728f7acfdc7c255f9ba1fa5f385e5266bfe2e065baf1f91517b0f05d279b00cfdc8a22dad5d871b92e46d66a6e62be5e563ddd260872feacd40f596da19fd949ba175bab0331b35d9b70800fdc63da3cccffc179465e1cd21531aa90fa895b2e5c09b2bfd422f3777e3aa36c2a67c6cdd	\\x475bf65d5fca91a16c48a9cab88ed30099e4499ad7ab6bac9fb712dfbdc8c9fc34c160417990900c3eb7fd2d679ff214dc0f9b0f2f44ba06cb340c5343974332	\\x000000010000000112e26b4c1bcaa8aed62030691b4152018c0ed6efe91c83095b87744a03e2b59e949ebed1261a05d363b7363cb0a468473ae51d08f00c2571da324cf9fcc5c38f666918574b4e8a05b421f4b33c869854e7958ae4191a25c9a4878767c16383fa1ff68bff9142e59f6cb4432d0d799bead71180e77ac4227f8823eb12c9c42d87	\\x0000000100010000
15	2	2	\\xff6384764af1ec78b37c0d5e76edab397c92e0af0ad465291a95635536376211df6ada3c07232c4a94500dd8da5cc43a6956b6af221bc779eae6b72c09ff1309	404	\\x00000001000001004a26ceac22caf944975833558ba0a5006f2794cdb74c400cecdcacb144bf4e62f8571b8dec7c404aec15af42b14cb72dbfd797e4c85934d5da9d92bc85e8347797f58bc9561bdcaa55ec67fa634667479074221cb65d64ee6568a4412bf2627fa915b4cbbd4ed83cb15fef3f9f7f80d86c8fdbb0bb87caaac156a69dc46dbbc4	\\x802f88b4e53418b75377b90f054cc646ecfda48da681302f16d73a1e861feeb2dc561812530c39f8666a5621560e0698bf48f64c41df949fa76f23fdb2eb9971	\\x000000010000000116eb93b12812c17bd85ad9e6bf199c72431b5643b7f8d2021185f2f68234fd56696c49ee90220560309a92c109c066865ae3ea81e1635c94290faa47b706b0a06e11783fe521e024e81a7b0005c763e0d96fd6329430afd7a84212f18c33f192b69f7433362efcc9528ab781568aad3d57f4f65bfe982e091553c2433cbbfa48	\\x0000000100010000
16	2	3	\\x319bb3c14575f0708205b5090a2346d4dc466ece03332c3e98bca0bd53758858eb38be716696e2d58335aae2a6795a2641565a43d302fa27498e4854c2c42f04	404	\\x00000001000001005a338e4bae991a4d3d5060ffac2eed42a55b0d123c1969cccc8f173e81b4edb6293428c95604e961f02b0269b3ca29e77d1fa35eed3d9f32d4d06e166d40b452c0a4db621006268094bfaf14c50ad2426507faaa8f124dbfe372696d7a250b16975dc25fd36f48ceeb9911ac46e91f5f1d873799e64fccbb7ca4da7b2e228662	\\x58881cb512365a14b56c54413f776e3110ca4591d2b85dff6ad72274a6a22448b0455c3a591d81f3e88284220471ed6483fc618945c990cc8be03e3502aa1546	\\x000000010000000121512f4864310e87714ffff8cdf379b02bcef2cbabab1c13916fa645fc6cb47ccd62deae9e9483d7ab0f3c92edf371990bd85426e18222bce4e1c68fcb9fd57579d4c7bd79b10e9429b406d281103456c43109565be256ab6e73f0307dbb5a8ef3292ed2530bf9d3f1542e8b9b6994b19cf17ca2d02e792d7c17b4826dd519c2	\\x0000000100010000
17	2	4	\\x21032ba5da675cb67b839f11a2e6f0dd3f4995dcf85d95ad7859a3bc4395e43e5cfeb19bafd717fa8ff22392c5933545bcd78c1957772d044843aa6bc68a670c	404	\\x0000000100000100584b178a0f96f74c67f6b52e5b061fd683af33056c5edf186d2235d5c23b25d346a77cd84fbdccadd7609d8ffe2996e3efd813d95534cb9d6e137a8b1f32b0df1e037bb30a196396d40d6ddbc25b1fef0eed18cd496f6e39a4c84f9816955fa534c66a378558adf97d7d8a66249f00f2ee99db5c18bf11aaa53fb42453f72b0a	\\x0506a7910a9f462c9a93e356d21e76403acb4af69cebcfaee68122772e89428868d10fed5cfc1d6aa974c9b800d1256faec5d55915a189b062b0b65fbffd5b12	\\x00000001000000018eac74fbe7f231a626151ef1174b279f378f1391237baed6b2b401f9238dd8c833d6917285b010a8f15c988aef274ee1b5d39e284751d27efdae63b8d96c60ec9e8192b183366b581e237576fcb3d15cacb617aa6d3d481406bcb7c5b7989fb9cfc6e9223511ee396471edc2c59f8617609f5122c5d9758c5883099f49edd7e3	\\x0000000100010000
18	2	5	\\xb40d915e2973d2693ca99dc07cec444377c6db92d9ca0a6149fa784c629aecb7d2df4029e8333fe3fe789759d07636b765236a2b67e2a2cf0f14ffc1423aa20e	404	\\x000000010000010006c5993ad0f818345789749b6a7a2f65d1be4370e57266f241e696e7a97f05279e10f821b1885254c939f69971efe00cfc02262b62d06f9aeca23cf835646498c8c0dad25eb7714765e8de3734b07b869866180128b8d32e47ffe9b4b20663b5fe1e72ecf5195af90e1be84ad88e6974178c9b937ebb8013453006ac226da320	\\x82d989c3e5f5a3c4da603f1e04fbfb72430df130f344921a53fef1464eee6746d4406bd57416a341b7a02e9dfae48227ba967acb9161cf85f61f93691a9151a4	\\x00000001000000013c341c7e81c419e5dd4f63d8485b6cb54e2a97650f9ea170d9dbda8ac6cac1c17acf363eb293f7d4e6e91b32d4e91b17ed00b106619a4848eef30b80a16e95d81bcaac5d2f159227e4ec57bb016db82fbe03fe483664ef246952e6563dd0d71525e02fb40cd3af15bc0469756c4d3c111aa07d0677cdb8fa7b5ccca58072c581	\\x0000000100010000
19	2	6	\\xa239b4ad8b8d94e606fd7dcacf6f7cb36db256201a2b776eafa2c3bd1f81ddfe6a45167f9a589745ea7b4c50d5539f607d48fcd4d2b84a5bc02114fc80f19305	404	\\x00000001000001000ad0710d4baa4148231c8fc344e181794187b23e38b3686955cda50d6df04081680ceeaf6bf4a84d4a5f7d9d64bcf8f9936348d9d5f09c9e63ce93020453531aaf98d1448be821f83f8f42f3201f1e52940371b85884f6d66cff0a7b9a7b125d38fda6d18e4df0716280d8d619f077476af261ac5bcea950a2c797f1507f5506	\\x6f5b0f4e52bb929be50349c805b28af5c72b598b11023ee119d00420e9660c9b2beb9ad24d38214afe980900774a102867ce620321c0e31f27f0e17437d883fe	\\x00000001000000019c846fda186ecaf12c58c534c7e4db7007d6e540d549ae02fd8914a61fe323256f26a66dc2fa8b51a585583cc9b6ecdc33d8920d6fff7dc6bd864862745d6ea365d7156fc494d6f2ad06977247b5a8b020e65b068ce2ef14128a16f0fb53d79afa868b0430bd7297ef3e473645971e7c8cabab457610d41ab70dacd3c408ef10	\\x0000000100010000
20	2	7	\\xab86eb9a6bb16ee0e6004ba27be8ed9e073f09384b95022822901c54fd3e3f0c912f3d0fc738f1e6995f478757df58bf5dadd6421fde8fe197cea88c7b4aaa09	404	\\x00000001000001006c8e99448cbe0eeb880817fa9857cd44bcd018953463ac5c8e6e892a557334271d33f534a54f628ad01ef82f2129ff3f6ffd8cf36e6e932832c99bbf8d6a53bde252bae5140a49a339939c7bfa0932b274a4526eac78b361355f127374b0749b182357c2db3ac46f365b1496a40ad5a75ff19fcd3acc028feeb64ba4eed6a46a	\\xd4ff4c4347dc28d8d763ca8a89337624f014e1d65e54e4757602bda782329dc800257cce87524110d303f0ee51875b8179f3596d39d8ee05b9ad67ede16fdbf9	\\x000000010000000169bd41bc69d063649a66d04fd995ffba314da809b53c420005e9e423370c0428ddd4a1e987c2ae59686b8563bd273c12e55c2967c1c33cd54f460b7db321c0823da76511427497b0ec80573df0e8f65322255551d3680dac9693df3151ca37aa1483b74866fe073ed8a4aac39f22b616580d15a6d0a01d77aa1bbb1ca395a9af	\\x0000000100010000
21	2	8	\\x1ce300ab387f8c5dd41819f4ae36fa5191291278e47537fe44a13e7d300c1fc3967f0e9604f80e10c4975de6500cabfcc343775ac9cad7a0e626eea4835b110f	404	\\x00000001000001001c6a3bf199935b2c8ecbabd334625acfd1ea7562717bde3eb71105b9c5583511f13411c70a85ea56e99a98149cf1fcbabb7a428ffed90d9b7bf0819adbc3522c6ceefa3515d17f48aa8abcc7ae98ff19342fcd0316e25fbd142fd948c77eda11e701480b3950038c95abf3772181fbe8b4bc849c5a2838e520bd0ffdb9a2ada6	\\x3a51eacc071c003217823906a2b9b3a9a6ca0793d77fcff50d4198b84f26543ad2f5220d9d8fade1e57a74bf17fe3fa31b0cbed80eab2b186af55ad701a931c8	\\x00000001000000016d176c5eb97ae34df8aea8569dcb4715c65b437e4e43339c6a8bcba7fd49036b6d471b60a75e3214b62997c8ea8db369516d9b7ddefc1ba5db18251382a5cbe56726f7d8ed226aeb552f023917424704b86f46fe11f9674beb20a20e9527f1cb81b86e96808ee8387162111ed9a809f21475b49219b5a0a6516eb1399a329cef	\\x0000000100010000
22	2	9	\\xe795f438a31a836c2d778a204611a8122b09313bf755f776ce23030e076104137296927b8efdd19cdc03c98a5834a294a3ec1bb81f48596b844f64f1d8e3750a	404	\\x000000010000010093937129cb383973c3a8401fbd7351e40335369e80ff556ffa831a233381e0f988182fc316ebdcdb510c9d8b7e426348efdb19511dd46bfb873cf29893147d011ba40893e5f3c3abbb925ec24c36842899efb4e6ac27cf1c4ae4a212a9864ed2d89240ed8158a92fbfab50dfa01bb3d39e242eb855fe395fa402d7702180a466	\\xba943052cfb6c245c6733b3a3e783568869ad90cdc4ece754a79b241a3ef4e57529be72f3ef065eecaa6e4cf7c921a43843457f4f947e79d6c9afb012a8fe5d8	\\x00000001000000014cf2c74b623052449afaac3afaeac4027f65e0a4d1de8e1d546429705bae9664ffab75a4da0e6bf6c9fa32d36516cd7064ab1eb49e3ae1111f1381d9e7659cf25dae42f0fcb101e3483ab379dcec25794713b23c96031788e55315a71dfebd300d9d86be168ecbc6a6a1c1f80f1f0c5587bbdda622ca3a1707e02ee3efbb003d	\\x0000000100010000
23	2	10	\\x7543ce40d92233546df885edcd880fe3c71c5e430fbd39aa5c77dd3f9948fd4b0c4d9aa441ba13a4189062a158710312b7c70fbec480914f14e1e9293f89a806	404	\\x000000010000010030506824de641b992632037a0df77d081a60050491f474ac6837187b742a28479ba097472c935a8e94e846d44306d3d1ba5ad150b61bea76c96025cf9eee979eb6f0432d89ba08412cd5d722b41527d8413119b02c9dd93d98474fcd21534726db8ebfd220b0e140b5a82e11a3850d360d84c8e9324e8960799d6d0235281314	\\xf1b9ae543a48eaf76f008ae9c1265388c6cf32872fbb5665622183119676ec023bfd510905adbab24616f019675d998a72376169bd26be6506f5045070e6dfe0	\\x00000001000000014571837c975b4a107855c458b0851f147b47bc0bb17ed9a2157b619245b301b83b97f2140d188b46a82ffe15a49c8d5867fa595b7817fe3fa28f2e1fd075fa0f607c73dc9557644bbb62b50eba45b538bd2521aa039b8b3011947c05d36664f91bc152c7b1868e6d231b2504e7494bf48c81ddc46eedeb94a1d2d6893600609e	\\x0000000100010000
24	2	11	\\x1cfc38acef1cbbea81a9ad985ed1a09583b89924c79961bbf131667b002a31c4db19bd8915b57c4c38e6cd34f185bf874f0eed6cd87d3558287d42cb41452302	404	\\x0000000100000100285b850d32f71fc4f7ae325c369ffb74bc7c3cfed0587d177af9eb791c56ff582e1143f4aa49ec49ea6bcce9463dde2e2e3dac2a7a0c897d57c4024070a6fb30c9b5593a94a3aee75a8fa1345be8b52b88c2cd0ae4cab730730ef5531dbca8b637e4eb997734607bfb91fc8fa85af4fbe331bf4f30b39e10e92453de7aabc1ea	\\xdb56336be94f933829699ebbaef1fe59ed86f4bc9d351ad491713be51f063451c0f44290af4f2cec09a6a09eeb13e1b36f15dfe0448f5973f0be620ebd48f1c6	\\x00000001000000016ce56f061caebf33f2116f2704b4a163928fe684aada426bb60834099dbfc1f22059ec7eb2d3ae31707e878f296f8d641d92ad547e8ae67ad302aee3bb9b8bce0f9b58c9de25fd041a22def7b0549512b197815065dec3035aaf929660a978a5785437b2e93d8d64a191420d0fb4e2ce190c9d92c42e37e2873d051a5a68f085	\\x0000000100010000
25	2	12	\\x185a213cff0ef6f28ddd66d318374430505632f9b85e30abf82ecb656036b7ac7844238830574bb108a39e931f0d33a4e41a88e719e406c97c9d51feef83f309	404	\\x000000010000010093ed7a4a44e275e10a72601dec1c9c33bcaa6b88effab8226fb3971fd022e6d6efb671784c0e1f55c8c08589e930e47bec2e2ed3644fd1a069a407feed5abd93aff9ac760f8e65e0e4cff81a2cc7a65408461de690373d26906b2574d7891a73a5cee9195c506cc3660b61f1fee5cafe6fdf042bfcaf2be7c3f02655b3cd6b56	\\x55f461d99231e71816f011e9737142791d58adf5a941d461f20ef7395841aef375c9ceec9272743ca34dd6d3df93cc83db553ae9f73ba1e20aa992f8d61d33b6	\\x00000001000000014f971f2509feb90c8cb9287233ba6fa489c8638a65fbae4d9ee5c8bfb3346980a489dbaf578857fd539def44dd6314a6260a404102a0066fea10b888e01b0955a904e4d1dba438eb6111458f887e0b0a7757c7894eb9e3b07f65c7a568e44a30dd4db09651e49d56ffa4aeb35d66a24de79acd4a0feb09b715f8d94b8c9c09e6	\\x0000000100010000
26	2	13	\\x46ab2d7dc4466718f1609098135ea128c7f476be6103ec7c304a005148be296cad4a806cbd9adf1b6f000336f7cb0345bfdb0d022be560bcb2975d4ebe45760f	404	\\x000000010000010061af8d3348bee83e8110e0c2fb6bf04eebd71c26bf2c25b3229b70d54f5987a97060d6071cc03fd2d1a11fd1167f0103b05417aa375bf64d662c569bbd23025c62f0deae545988c1efe941f4d03d258b2007989c87e4ff0d395e50d25e507368c3a5f72496e9ca3330a8ef70d37b728f781c09b468dd15f6bdabb0c843641faa	\\xfc843caa27bb02a8a8c0fb8e13be0542c2f12fecdf5dc0e797413fb7b55ac6c989443ceef56af1f1d4fc34f70cbaed1f1b1744df724f668b9bbaec1bc30cd42c	\\x0000000100000001887a61fca7bee35c13c6755b069ec9494539f19ad04de900c1241236023258665e04aa6936163538e300cc00330ecfb93214c0f620f3fd9d37949a70770ad6a37a07f7d39576ebea18d22bb2b28e61a1cc31538e751e4821d34f61949870399b9c69643e97e364b8934c2807ff2e517601d98ff866337cd0aedf1a77c8d11dbc	\\x0000000100010000
27	2	14	\\xc82e82efbcc3b1ab6d2f888fbae3572afe39af6db10b29588091575a03266ba7d20b8ffd05881f4cbc3f3e21d09df5ff361736ab703e3b5f63c01ce13fd9c50b	404	\\x00000001000001005409ed255844cdf5e39502d7408eb51ae31aae2212e63b7d154dce28c48789832a98cfc67e279b6e05133b92cf51f19ffe01f482b8db956b4faa73fef87b586aed6a4341d78b26056ef7a02fa3a71d7504e9a28e1d9ae09c34b2af253b0544557e92d552f9a98deb91a7b3e9d3a4260286359cb5956f9979fc1b1c2db245b79b	\\x51e458ec5b9dd323eea2f7630a578ff637bf9e05b5ab20bfac776bd907e55e7d877b86ccbb781c137c3bc0feaed6801db885faa7380cfd6a60302528803fa55c	\\x00000001000000013c1b0b2e6c650e7f01db2400bd74b4f16c76186ea7aa3416f5ba58997d9999e8397efb7b211d666262ddd2ba5a3f65d8759afc98adaf518f339d07e3dfaef4dbc471a1461d7c6de77df3eb5c8159a9d5f6b8067f6640890d67b952272f4764a464ddae750decb2e4ff01c7cfddc87e82da357e3af6e9ea79bf9eb090421c5ade	\\x0000000100010000
28	2	15	\\x6606001b3d30c73ad1a1f3e956291fc14dddd4608f8b27660b515929a02c5e300d1ce9fdf8bd2c52ce06f725549ba76043ccf746defa8de42be8de21dc9d4302	404	\\x00000001000001001c05f4fdb5e0e02bf7ddff0cd5a1ebf832e776e02feff5859444300318c2b808dfa9f48551e064b1edc58035217fbfaa07f0d9c2991d8288252bb21f5b3ce1d0df66531d101f7d182dfa5e7d20bc632f7c280e22185f722c7e05b4d0c70549bd28f1201c4a7b41ab541edd56e38f177d848616e1bc9813d62e387e78177a0f34	\\xbbd9b06b8eba5d639848f121d70c0f6d6a5ae1421c71fecdc578fc27b47a75d2e9629124fe11f127f9d23fb79df3f22c5d73bf15f9839bd6b0c03456845de5f3	\\x00000001000000016910380778a73f95957a41ccdb96a481e51b3ee761b9833e7b35a90dbe7b43b9f7623478cc94dbeeeda91fa72dea822aa1d921937692001f6adcd5acc7794d582996929d852b9de1832d9587865e36352c36242135536ead017ff61f95a7ed248128c4cec2c70fae58680cfce8e91d62c5a3a3df790f93ce46f800c999df5542	\\x0000000100010000
29	2	16	\\xbf3d24909a3665bcc26e60e568bb797f756f2a8cea94d10b2d15b1e5565dc32df1322d57420b4e784c93320a3fdae8f15e753c9bbf41d37a7f391e1af244870c	404	\\x000000010000010044289a9c860e05e12b8908bd8be03df21582da911ef7f3696f815627677eda7963ab2ee38ec6fc489c0765c092bcc96b23eb3c5be156c0ed5c8ecad0b450d01465e469662f671f3362702c21fba80e3d7761163616cec1db56c277a29f69140a823360bccb5b45d05943c02f22fb43b9fe67f64a7437f868715d33b733677f20	\\x12f4cf453f0a02840fb48749cf8b8127bd010d72040a70c191e81f9d9b46487c201274bd39ffcf972a14dcf3f57663f7e4dafe3dbab8abd9c60e4c79f0a207da	\\x000000010000000185e9577fa37d15806aca9f778c118bc587553ba2b2dd69cfd96a35ed33db4968d14e13f11ba508ab97adde142adb29a7a525fde8b161f4899e1278b8a7043ade994d106e2ca288a2c937563c2e11d91600032a29fcb21cc5015d1ce94039f23a2848934fdc22dfb872c35e0876dcafd4c8d49a5510e39588f7f0dd42a0322bc3	\\x0000000100010000
30	2	17	\\xd873d41d7700aa58534d8878efa4cd5ea665fac57284ff0986457d7abfdf7b4e4db019954d57b5643cc0247f2497c4414ecce8a55b561231359c49b862319a08	404	\\x0000000100000100110080708dada88c06a76872b15a5df15b89bcd609ba3697d093286472cc644f3e1d60dfd324764fb7b5a068b455d82d230b8c73e8ceddb6c9efbf350c4861af1c0e4874ba785a9236cafa536fc874ad0c68fe07ddf46051fbd9700a05550dfa8490e7065e86f8c137a92e766ecf76eb62d629ed4450cc09f6ddf16abefe70a5	\\x75e25d06d13171e0bb6379c12c55a43505c90d7f25e9ec9ed93023dd86d53bd90a028fb5611251a6a5fc5af1076787b8e8a74245e6e3188bb7c9f907733b7a79	\\x00000001000000010f49a616ecf3401d1d6600546ee536fc88417377c6b4e3d25b861a7e65f1f8ecfdafcf28ef132772614832651171c384353510dcf39b3b50bb06b90db71ae9bd12206bdc948abbe6cbbce493fc4f511621a0fa5bcc1fe429e8406702984fb36876a928e29a618bd1a2187837a44a67bcf6a5f04a43b72b58db70faf4b4755fec	\\x0000000100010000
31	2	18	\\x8979b73538387b5bbcfd1c4d80d5c74689e2bd2a7d82f8153eab9246464c07898449c660319f5d6ba9863c59fbd40b2b8fb16159a2e0c83dd2531f2e8648f403	404	\\x000000010000010001c6dcf289886e85e400a788e6074f74c939fed4775be3498f8deb9a45861fc8780e3ac7c5c0278c3100fad3d03e1b704e35801839c2b9340e934c044023080f36b18a0a866f91029db752ef9df99e48897a72712b3ddd5e5b44e02c20c549836858ca07f0c413c727fcce0575dd5e5f01ed07bc77c75bbb19ed36f3bf0bd8aa	\\x7e0add9a6a39608ccb64d6cbfe2fa92171431e300448392a015235b3f35f72c47464ba08950ecd6d55383569172e1ead3d450f66cb9a1bd658a3b48ef92524e1	\\x00000001000000013940ec612237a297bd6f4bb369f72d6da1e9ae3410e1175fdbcd22dc5e1c2b14181f200c75d54a1d93db1559bdc070534f7352781cc3425ff00e4a2f71fb4ba4005d381149ce94b1b30cf18a88a79cb907ed164dfd421ecf1f8a695f9b840cbdd85bca76a7e8f139c55d984a3681db99c054e0283b60636ac7e4459629d5943b	\\x0000000100010000
32	2	19	\\xe9467eb5dfd37c14c283dd49a097a5cbe205a67eef64f94666d44b36c8cf930967911c60b6293d5b3a65eef58758aa93e7db43b1317ba9b70048676509e3770e	404	\\x000000010000010028eaf2162d955b554b8bf34c7a45c075dc05a6f8b247357be48efce28522db6c7e20e49a468e50a657fc539ba8ffbe910b77660504a345be63fa380ddea21ecc421c831a234c09fcf701864fa447bc6b63a3938093879d56f62a40651894af1fb49782d6e4707b84e79a72e251a390efe4a181a5639c873a6134e04c81d0edb4	\\x062e6bb98919e27ea09698cbc4092c5c62efb64928687da7b118c10a820440373016f396bab37393e06aae88e52f1abbf40cf2d8c5d5a42297d3f356fc7f16cd	\\x00000001000000014a98220f5067c3605462c1a5ecace8112b40206d588467dcb9487796d1eade9d59f1f88820d620c26ee31fa40203b10e90ee29d3b487ee51c66def019f66343e52586c10ad4c4ea50ba0b8f2bc8e1a0d0b29dd4407e86028fa1c1a9138cacc2995f2b861e7dbf408f651ed7e9a58376c5e401f828f1285ba0686cc869378ee2a	\\x0000000100010000
33	2	20	\\x8407bb880b1e0d57c7c8c24c63da562a6cd808208c7fefb1cb5a2af7ab51f707b5626f2f7300d58db197e58e9acdced391a302b023995febf95a2d4e774af109	404	\\x00000001000001004116278cb09f4dbd75f2dfe48997689a8fb1cc917ac14fa3efad764427260e228d1d4d966b148559ff6d9d88c006fa3f0c59e3afe87a56f3b1a27c93a9ce8573d7d24e79f02c2eb966c7d1b5f8bbc7a5d63b24128c448e3d5849090626612b4f6023ff69a24eb5c4d06fc57db71965c1f6c85a02265db322d1381e2a2906731d	\\x4f2b17e23b62b6419c52e3e9d6f6f55ee090e702b7d168d43ae55f44aa8c288f24427fe125016c409ac5f3045fa4b8cd3a83a4708b69d467c964f32e664f2d6a	\\x000000010000000115f8c2b7bc4904f141714aa73eec9b14ca160bc7e2f08e2268334f8a2a173e1f27617f5165869960b1729fcc4323459143954db57392b92ee7e2b67ec4fef85a3823751f23f51e1b6600b6e91b84dd1c20d21cc6a2882610b78b5bc65163522644fc44f05d800009fcf541ad8bee3a0dd4450cdd721f28332a1bcb3860cd9525	\\x0000000100010000
34	2	21	\\x4c13e35618c2e764e108a30c34c75348626dfdb4538ac61a5c9b62433d55def4eff42e802ab3c8da48dab4b576083b2b42dcb0efa9f10e6a576cdae672ee6305	404	\\x0000000100000100425cca951eb674f16b1ed8d04a52ba6135e21c4c782098aeff6149370fd5c53931274c12255e6e1469084292b9657f4667a47786d4d5e26681b406400653b77de2bacc8c3d93e20867bf3f77250a1bbbb52b1c31892b49fd7d56b6f9235fe5bd74f9856198d1cf96a272cbda6bb914cc2de3b5f4ed7999ea053313d5a6454648	\\x833b2092fd6786e2542bbc5c2ba7fb622abcc3757eefaa44aa7ba7ba51dd75a6fe19a0ae5c597829bc5e12e32657542e53fec3fd60ef1195bb31302c0c07d2bb	\\x000000010000000168fa8b4cce06b4c56cbd29a4e7e68b2b4be21cb29ab7dab924bab2003a091683a7cadadde0a7a0c7e67716aafc1a0f653e3debf73c0634b1aa0b4d7c1d7a086f60fcb2affff47d6744f891b16b0839d79f17a5aa9d4ae140dd837790a518441b46593d4d7c20627a5ab8f89dfdc893a5c046bcdac0604553c2ac4e38a4869195	\\x0000000100010000
35	2	22	\\x21dd64d0647ce637be84171295db59eee4baf5db49150f379e67dfd6dc798f2049536512548a591fed080a0b081c136914f9867fce40655596d16004178b1a0f	404	\\x0000000100000100a8f44487940044fded763ba3ebc4b0750a93448de8e64de55c38921258d86af8efd178c42c0e11defc17c22248fb8ccda293cc4ef0081ed4269961bccaf8b3f48b8af39c9453f67d5b3d5809f89c4ea5403d1dfb67da430223aa9854e0eca0d03ead53ea0df109a43a5b5b23f9b67b045d8bf6482feb1593fc4cfd35a3d0e575	\\xd54991ef7849ae978710adb0b16ecf79c40438325cd73b35b11de5d0353418232c73163ddf3f3f17603f2e219039c97b7a33d411b2afaeed51615af3d5388c04	\\x00000001000000017c831dee5f7891c74d5acd7e771ce93d1aef444c3f3994031d510c9f0394d189646ec8c51a9357a66c748ff7b19cdbf0a12969438939b732b131858bbe1b5bb043ef40dd8a5992c00b581d8d85aa70ed2fe5fd3400fa70762197f15c69ccd79d719d761e1faaf7a0dd83a5c601cf30838492ae338d68ccfbeaef5f297bfa3fcf	\\x0000000100010000
36	2	23	\\x36552ab6da8a3758cc3489beeb4746b4f91df50b04d28ff2c1c31058d80284ea3a5f0b14dfe8a60e523f8f10b35bb4ee97dbd135dbb7351d125b2dc3fe863105	404	\\x0000000100000100729358d9f59d8823bd7ac38003a78de16dfdae6b8be194df08f483cdb652cc445697bb479e5b4583b424a2b7dc4bff98566afb30be42bfd394f99151f4ddecd84e9a51f60d095500ae78ef90c98d9331093e48341508a4990830686056d8affee1815962c9bc5b92a279bed654938b37bfeac57f92ced6fd829589b0a3e04fdc	\\xaedaaf0c3a28925c9d96af2bfce60438198ef9d9a8c93094130ec46f38060729e991c4b4c288b0eb86ba85cc7a4db5e3b34877de01a9adf85083897308cfb280	\\x00000001000000017640252e0d8b21515cb300ecd0f9dc033a41b0a8f8e05bbcb2ab2203e5e4e2b09e91ced3802b3fac44d581a94297a730303c4ebc43c8f6b64cf9f81216020fcb07fc5a8338f74b578bfcde248636569bef17e520e4a7b2fd6c6cc42544102721458a15f6214798bbb599569c192dcd3c2ef80135c8eda56acb711523f4fb6a37	\\x0000000100010000
37	2	24	\\x6e68327f6c88f2a125b1b0ce3ff42e75bf1b72227daf3608a5a1501da8df298735e3da65789be4801a9cd067973466c09921f8d3f62a6c25b61f07f38037370b	404	\\x00000001000001006739c8c198abc60baeb8324a49e61498c8d67e890299ed3e56f7525ac4105e23e8c8c8d58d00af15dab5b758d105601299c3b80acdc2685bebf127261468ecf0630f223bfb666390331edc7901e2940f4da34d4eb94d2f87dec1c10e42ed8a797cf4030803cdb2bc24dae03088c455cdf5cf3e6e477db4e63912b7d36e0185ac	\\xb60d12e841979a63b146c788b3f1af1db531f78f4ad238bf8ed141ae506baeab2f07407e9ee5c0618aa362037ced4042a6cb18ab7d80cd3e263e0d60827c61b5	\\x00000001000000017f000d94bb679a9d9b66c835f7f0a1185ad222c71dcf8ac7b546a33949e5a2a8904ef9a396879ee2b5d7dcd31cb916b7d326f627e8a90a0c9f81168feee300a5c110c8e59712ffede22f75fef6166c9d253acb4ae39ee998e35f37b8cc6f5140331dca7b36a5b766b6099991d8ca0afb368b0853cbcf9136e470007b6966e102	\\x0000000100010000
38	2	25	\\xf92efc8ad9c21593a50ccfcaff961c23e870a20fc6b5ae82e50529ee63cb30bf795829aa997178b168b58e6ebc34d96ed7900607611fe206618a603cc8c4b503	404	\\x00000001000001003f03dd25de10d1bd408e3488eff2b132b66a391b2ec10468749d0927a986e2d23ad0e6cd1d92ad04fb7f6fea821faf3c2f0636c932e132035d38318438ed0d2bc3de2a1eb41fe8eda55d2e9ad38f8879abedd0278e26502ac07d93cc57081924c760c9fbd07547346fecaf86cb087388f110ae86ce6a6e563dfbb676e8cd495c	\\x5c6f41ba1347d2141c7d09c9b8ae5f38839742e3b55236c5825ecf15b4cac67f2287c5c400bc9909f0b1e7787bb446e6eab4b97766678589128832ec6e6ed50f	\\x00000001000000016566ee1c025f683cd17915d66d0c28a7db03631d4952cb35b9280242a2f87e2cd0327e2c24f88997a6a14efeb76a405e5b8064caffd6a6c7a3054d4decb885c30e2156b199e9032a3f4c3ff47b10e1476393765935c062130e55d92c786109e9a555d6b8cd4a630b969ec0a6cd580459055c3fb2bb83062b3862340e3c5d3d04	\\x0000000100010000
39	2	26	\\x625190e2b1d3f39702e1f9494d3a019d0d5e9e5c079d56f7bbad1487f97ee73c67cacd48a7360322e6f9b9bf2a9f3e0963b362aea46ed3ce5978fe6c3c85bf05	404	\\x0000000100000100787f51e73619f187e4af730ffeaddf77251fd346ef73eadad313fab1ae1cc564c35d028fd18f1fa7def42ad3e3dfbb4cdff9b9ba8c31ae23a6798f8413fd8228ab9df9928fa6d6133e940ca201b708999ca9279d9194fd1fea1efd357181214528bcd77a80bf443efcb26f28c60dac21074ed4876eef912077e238fc1bb8f621	\\x3dd570d9720df4efa8621e64059bad8b70b3b95c26674da84d04247876a0af5b1bdd375ebbd4dd327ed234db255b93213bc57aba035fccbdb219774f1d731088	\\x00000001000000010cb58a38baf412e90e523497a90660d08a179d4ed8830cf5d2cc1ce4c6524d09d200c26eb271091407ef5aa160d4738f6b220e24b93e0596df0b9fee188477a87b244f9afca2719429a54089e2a4287305b97ac54e7117555b2ce2af7a5c1d57d9a7b0137236932dabdde396c7ca3d0cc95189ea94ee049aadc8c5a695f0d86f	\\x0000000100010000
40	2	27	\\xc5f129bebc5592ec552f8b87f9b89615caee0f42ea877831c6660abb73c760d210fade42c798920f1f1cc82e61d8f991dccdd9e787b7fc2aad4b1cb86fe16909	404	\\x00000001000001002e12b5c55e6a224eb17dbfae484d9122f461545ea56e1a95e5979a74f9df6af7465bcb38de85715fbdd207c9cc4e4ba34747e07228821aca2e18a93d8d8c4de5606ef78dd52fc0bd5b2a4d12db80e1df2f1a3ddc1c2c9e627e3d6967ab564fdb02cc4a5a3da2d45dbc9119bf19edfc25b12d171b0e430558238dba1748db071a	\\x7d050f08fd2534ff3a581f1a04651b8249dbee70bd28cf83718478e10a257fd2ac8b0ad4009e01f4eaeddad37feae4f124b879f7e69f46b36c1bd1b5263ba9bb	\\x0000000100000001aee42c8f536b6e4eed9cfbeb8122c83c9daeddb5196ef79d91dc0b4049d05acef0f6f7aa1a6d660f1370133799bcab53ecdf65c6aa90d1cb6264e0c09e512865a177210d25252265ff775bc5e8028c99abccd556460303fb514b05f041c301cd51c81b1f5a4463f8fe1376eb6c6f0528c37f0ed03633843a428f186728e9eb61	\\x0000000100010000
41	2	28	\\x61248b7dce077e58abcbca1f251be4070b0afa3fbf18f450572f30dd0049ccdd386a7125cfc7afc56dfcb26b218e1acac81703548f0dc84a21d1f08ec9ea8e07	404	\\x000000010000010030a47bc260956e29e8c39dcd1320c2fa383f221202b368103237e4b02d46be25fc2834cdfec928c7762d47d5a1e535bfb07636262b21df3876f0f5b951fddffcf26119574560d8c8c62962f2d061ce8d5bfc213c6dae57954d8bb8c699387ef0a088a246e166d9e9d5eedd02fe1c6dfa17afb3116e4a5672d75bbac6f8150dfa	\\x2b5134fc2736077989db591d68dfc7eaf3f406d0160a56b646a413114b8122a3fad22ab8a529cabfd1c1b77620622297c1cccbec078ea493c12c8c622c0780e5	\\x00000001000000010a2d4f2527725e25e4365b3ac66717977412db0a985b35afea816df55c05bc8522b1c3995b415f6f2f2ef8ff9899a5d551cf1a98e7dfe1aa27faba3b1cd8e1f33a87fe9e60a55b5b23ce0f475bf890c1f78a6c84c2ca8f05aabbf61a097d761e855f6f06cfa83ed6ab6d582fa21615752e7a01c3a94b313438dfa38ee99ef64c	\\x0000000100010000
42	2	29	\\xebfa0dd57d61c83828f71135d0b2a02a576295d8eed4f071ae09b05dde0454646af6e593383e4d144863e7a72f6f364fd9b4f9854d850984ae28f7e6a83e3c08	404	\\x00000001000001002bbf883e481ada7c28cf88349322baf87fee672cf8a9f9854234743251a1b55bf795fc9af2536c803774321346c442748996ed32695503e46e70d7f80a0ce703773aebd1b304b46127a683497c8273e9040567783cca9efc576d798105fe3b9ef5e030ce0f185b2766d0dfa0c7968684855a67b3f19d694cef343d4fe197b7a8	\\x8abacb277e5da24b1a9b8388c2f17a946f48577ecf769cb0ededed598df43b6a5c778fb8040f12dcf03ead7818d2db1cb74947e75aeac92c62ac5fcba0e7390d	\\x00000001000000012a99872939e050b428993859e610c91d2e1e5bc43a2f4ee3bf2e362430a36471b9844ff66dd215b61597646b70ec785a6c2469e8827fa927bab01e6b95540262bec5cdfb18f14aa639fe4ca0fef6a9a7aa26fc3ae29e613cef5d481931f2167cbe769d27412f8e7bb214ba732c6fda7751e7c2e726a956df4d1ee115bbc40ee0	\\x0000000100010000
43	2	30	\\x4462a5a5ea945f2bc2fa3afd793c45b6d505258de1fc817bfce7a3b774e1c931b55680285fc45cb71e10cc0bf53bbf69556034ee9f912bde437dbf6f8558b103	404	\\x000000010000010095a4de6cb1aa536dd1f756255a8a91f9ebdd5d5c4fa357251dbbeb065e94d2c74846087898721f5af2f90470ce6eda3e944ee404f03e4b4b26c7b68126d6a7a99315485b360bd6176d821993afdb84cb75276526401a89fc6444c553fd6ac27fb6746e4770853db29efb31b89aab597fe45c5baa52781cf0e70d51f2006af779	\\x106beac4c70dfb1f745d340ab09a11f0a5924731be4907b1c9f06000eb65ad9375e7f5e81e9a30a6a0155ff665ffe907c67c59aa091be087f82412b6673daf41	\\x000000010000000112b409f265d42a37c83d30d78c634ad90347216a3e2f11afefa8b0d42ae358284f0cf5128d02b7c5866b95d6ea595b511095854ecdd9bdd144ea230671e81904e659b5869ccdc4ac6f7ca6d654eb4e75a47b156a68d55bccfac694d14bc2fbbbfcd917d832d511482cbe15df078b38be1d34d7deb1cb99d20ba1cd7d86ff82c8	\\x0000000100010000
44	2	31	\\xd025ed974d5197c542b42c6991e48db21d2a0483aec59994c3b8c87860a581174a57190d24f5c8a89bf4e139c5a1212ff445892a0892c139bc1fca7191179402	404	\\x00000001000001002cf11791bdfdb29b1f6eb9bd7898aaf370d76b1ca35ea13e119b3841bb941c194148fb21c95b2c038f7d27c048c37983ae0d773fe31b60ed0c080f1cc50e71a30cf6d9a6f4bdf7c83d5a14df1bf0958399143b4e23598b13023796ab8b9553317c377a548a64e79a168036a722e348a2595e24cf3a39a322a1a5a77ea846db60	\\x378d0f8c9250a64c8eeb8ed24704456db0358ae6a63ac507dbcbf2de5bd5be4f699b2d391559745f77c9118ba0c96232aa46f813be8e7118904b73e64d560669	\\x00000001000000015533e63875e104e0ee5d8f7f6cf6882ce4dc16279884d4a4e1c2b57c622db69033c70a464b4274c24fc688150d36c4b1e3a0fef9719b469ce636121b1cfcf10f628827c7a481c36e9051c9469dd45c62a277de6eb538a6aaa67e19b3264bd959940a2d2ba3ecc85a6b520b9469e97e1104d2602b31b6ae51c1a0c9880a527523	\\x0000000100010000
45	2	32	\\x381bdbcef70aa9c55e0da6a6752c3960b549c8ab5b7c8d17a80cfbd06d9a6ae2419c11504e45a9ae59b3e8d9925ff77e12c1f1bf6615068bf2807949a25aa608	404	\\x0000000100000100015417422b7df9c46ea34f962195fe59d0bb49a4aa5a912c295e744ff51bfd1cf23908fa792c6868763a2eb1145540efeda37d20b7c70d9927da461f650815ed7f059ba91fb11e9672aa34c6abc95861ee3da4b7e5e352d243e100688588d6cd3c1bb83438ef7997e8f0505a19ac115dc88a2a80fd6ad6c801f8ae5c0a5f0d3e	\\x61e0b6c056f29bbeb22880c31e162dfe8dd100636b1955830bfdbafcd6b33cd43eb79f9fc5f2c3827351e366339007ca111e1f8ee8ef9ff25d409de3a3d67a24	\\x0000000100000001564ff2c8bea532f9712f75d0e9a937f2e8097c8de7dfb8c70982b3768bf55f6209f2c7f5a434b42694d522b6953093a1f002aa5131970378cd02dfffb40195aa910af7ae4b93567788a51a7efc3af50c064e172dc83615700bc7eaf0bdba96fd31cfac995f0b14ad7d4cb0d3e83f6845d339d740cf5e3d9e6fae55bc5e1abf25	\\x0000000100010000
46	2	33	\\xa568956a8463e6bfcfcce5c21214e19b721e7e5debada1948a4106d4e37720e5ac2d051c70ed87c172cbf8b2cc1b78149cb8a1dbb19b6fd8f29ceedc08f1ff0c	404	\\x0000000100000100307d12ad6555a0fd02cc029b5a7b1643fe13cb0db4ecef52d8ba2a633084efa9b5f4b48cbcc49d81e1769219c2678447aec9f8e138178707308b1fa963407c4f9b423aa714ead115c18d9b1eb9941f33f85e960aae2a4896bf9f1524b2f403237512bd6b547ea137cc79d0b0f01fb842ed236f73dfcd62cb710afefe00e1552d	\\xa73ff041186b6821e57d01b11e70c265f6abddf150457645ea192089bb72da6d2b6384bd6ae9c2a4697423083070441fb478c49fae665f44b8a407166cc07517	\\x00000001000000010fb953ca70fa2292352d30bba144298e33fa2f1d75d7d1b60a5dc867ff5b177be2c54e3e446fe1e3218ff57b8752043d70dc60aab50199875087ce91045e94cd6e47148f4a3588ec1bae6c03e07e2ebc171ec71a12b1073ae5aa569eb7b3da6c757534ba330182840567753a5063fd3d1f6199045286d29e18792f2e0bf8c0e9	\\x0000000100010000
47	2	34	\\x6e8526f2efc93f73e6e5eaaf4461a7a6dc637bf314bb47a714072c53580d1f240a39c2fb96c7e87e11bf65e34726ac2373b8758285695958375e0f9fb29fb00e	404	\\x0000000100000100496d1041ec1350e59a142ac0bf6d379307337b583cf1eb16aa31969d7567f1f4736e72f891f696f525c37eb3dcbf08201e43a258bc625a26ea7d25143882525a0231594ccc0d7cc4f00e4587c8c07323af9022bc3f2aee0a1048ec2e01c432c001ed483c9ada2575ac4c24124fb0cbe57c085f48e24874d3d6893994a6b3ba63	\\xfa160492785cc434d4c4cfa9b16cec0136b1660df3e565fc6ddbb9620911252963861ce7ea6d26d09b0c057caf7b6dca938972afa5b01aa03106ae2523b94c6f	\\x00000001000000015addf33cc39fb06e81bb0d99d33882704919138ac533c0766b86f11f12034aa93f444313af0d91936b911bc31c4b3194abe3c990830e8ccc2dd4fcf486141292e0dbd490ef6247302b803eecd6994874f10d5b8e5032d0c4f6f60e9706bddfe153b36e810b0f2dbdc37b20cc988f462c4aaa83182d26022fb706dd7ffdb6e846	\\x0000000100010000
48	2	35	\\xf6df91b6e36f73fd1c42b0b5cda49ca82e697e320b0660feac1ef824b1af84f87d663a64544b488e9fbf9dc27f1071e294080229cadb2b5626fb74b47b500b06	404	\\x00000001000001009ec626dea36eee66fdd0bf93b24f2fedd7bd95fc977c1b8589d5a77dc0af77fd04c3d4e0904d83770ea4870a843e9ef73b11e25e4edda9c0353ec45e622cceb01a858446225392168194df997219206797cf97b39d884bb609b4432f181693aff0ac12e6dacf0c67455de89de2f9f6b2d1141cfb36e2212cd2c547f71961da7b	\\x1fe7a31bf5e4e77807a3d853f25f40177cdd40d000efd3f92fb09a54f001c6f39714ed20a54cb56252ab07bcb686a9b46157d139f0fb1bc5db7f2f56d3855c2d	\\x0000000100000001ae1fc637551529d22cc72e588fc4a57132c7215c3e89296ddb41e5a1117fa27821ad1629effbcfb919e75667faff41bc22a9861521051f9953a71c5ac06915832b2d6359e04e21d8ecee8fbd12fe65eb62ce7ca7a3cb2f9531a89411542cebc32de6d24a6b71c5287813c0029635fb5499a11f37f732f1bb72220af832d63045	\\x0000000100010000
49	2	36	\\x11f3c2cfaf3d1ca167cbd0a2e2f8778ce2fc06eb7ee08c703fed4b459ba05b1dbac25d03aaf98f5f0196ee38724cb6705a3c946703636c7f91dc730bd44cd10f	404	\\x00000001000001009b5987f96adc42c4ba72f4b2c67384e30486424b9e2df7c646db8d4a2ff80e238f74775601ddcf1c1ed321d3d33303aa6bb6f9f34f37b40209f5ed726bcbaf69292f8020684957472cce7eb02679808a8cbac5c98a653a217d4666cee06d8cfd3167da6383db5c7d1a4212aac97cccd05d3be0edc32f2e8ea06a6aa0031cd00d	\\x9f8959c5c543b986e13c6e76dcbaef213b3e23979bf8eaec538c229fdec01653f5d6949f04597786e6f8a59c9345c8f3b5bbd5c028d91da2bec5438c697dbcc6	\\x000000010000000188bcce1ad9a5529620e8231968a5e4a943f3a958a7d537ef3c10e35d05a4b8be6e47766c224794fc935518203043eab5195407379991d6fe9fd2fb560104b5a3605e10ce4cb8ef8ef92866d52285dda39c6b515b6b004322403f4f59b15baf114ac7e8076fc3b5288766a78b1943b84711ac86f62421e8cb3329a7c6f3331a78	\\x0000000100010000
50	2	37	\\x53724aebcf1067f008e8d0ea97a8e2ac3cfc8ce6da8a68f819bc974779e568ebad9f22fa9387dc40e7831328f020a6ed69134cec542e89f2e1fc5e2b7625dc00	404	\\x000000010000010017dac74fc16f42aaaafefdc5f922d1b9def5ed63c7a4cdec6fe97471adad1165194dc569b139a2861f82397df3c6a4fd5543c86f5a1df9dfe369a7ebc02759567302dfe2eb950484fbbe7ff9137ffe1e382fc4980861dfebbd1ce4d264d95b219c8d9c591b8a50b8297e926122f0f121ce6a8d88cf36844f93742cc05f1ff8bc	\\xbf1ba98da1b562ca7aaa42b0f0b104127b66a4309683629ec5298ca8a19b9d1199c55d52ca106332fe494dc8cc6e4ef17c6148173545c1dbbddb98e5fa5c35ad	\\x00000001000000018bb84ee139e3042b90de07a97606841c8ca8128270708bacbf1a903b05e396b4a44c80de36e0985e2eb910b655e780a3a4af04dec53c40a9cf01cf6d6e0179152dbcc9f314a208a2dc656c83bf1bae74e10a6bdc98f648496495e66bd615b8f0e75365c151afacc3cea0835beb38cebb48966d02a77f6acdc532008ddd2a45f7	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\x63783ab39139e471ed407ae9fe787fe6dad49b8c467c88dcdbc4c0d9dc4cde1d	\\xe351de8a58c5e9a6caef40361a04dd8349fefb02af4c57e4bcf9a1dcb6fafeb0973feffb21effa75d35d5be7024a7fc50498a02386001494b5cc5481ece79ea9
2	2	\\xb144147f811e1bb31b7445234f7f0d205b39b10bc4e7be9c4fa47245d7247436	\\xad2d5c0c8ecfba6328158a7d12897b79dc7cb9fef2a175d3ff43a2cf9f470e8e5b20d4bf6479f7c92700bb73fb764908a9a90193fcdaf32ff7b941af15a07c34
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
1	\\xc52d34d45b9333f0fd2400a9fff2290c7ff30aaca136e33a377408e606e0f21b	0	0	0	0	f	f	120	1657543757000000	1875876559000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\xc52d34d45b9333f0fd2400a9fff2290c7ff30aaca136e33a377408e606e0f21b	2	8	0	\\x12d95edaf029db6715a6830bcf154777cd3db087bd2503f947c32da46ab1ad24	exchange-account-1	1655124544000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\xbd06538d27c36765e381952bec3ba29091aba754340796e14d92efe4b2bad381726456337ce352fa6a1a693ed725014528c7835b04bbff4f412b4a0bc476f6e0
1	\\xb53b7684804f377b844ac8755088de6d7447f9fd4c9833698b8c1855b5ac952f59a499ef4fa91e0f5561d2fbac07637f2277f088ea45a04f655cc6a0610e5b49
1	\\xd75cb5a9b98fe3e5f26d8030ed23ceaf2c5de4c3b9b5bfe29595fdedc335cfb47781ab37b8d07a5dd16528c02b769a1e63a2b04ddb59e043ef351d4bfbc59e95
1	\\xc04cf27b0fac240ad81aba67269ab412c26cb42685fa860c59ed0b2d88385b825929f5b59f03c09c22c54ac7af271e00f84a923aa4555218bd77862d628bfcaf
1	\\xf32f879b980d1cabce174082bf11c5e5718bc737630f21da01dede0651309946288f5afd7efb6cac557d50d0ec7e927a246d8d2ed4da19a5d8b237d2d4ea17f9
1	\\x489a7a27042559dc74068d710ab6bb6b5a708396912e6fd1c0f13ecb07a54f6ea6c86d174f7658f23240c939693acaec51385986999f43f00c7da9f961b8a493
1	\\xcc9dbc3d5510400ec2a3d00747e4d5a4eec98b5622426e8243859fa7f201495864a0a2a4842c7bb034965bb4a04e00da7b7b8e481dfb20b3fd9f6d79690530d6
1	\\xc5c905da4637fbdda4f9f47a60f6d77e01e7f27e6e843c94ca9d0609551f92de2d821ed62fdcc8800992c78a866a215e1cbe7f4f30461404d6b682e998b06307
1	\\x6e327611f0e371d1813137a12f52e5eb4e5d242e4f49435c506910e9ae3da20f01c1b2ef217b18690e9fc84bff4a31a6bb05b98469a8579ce5a9090cdabb925c
1	\\x02233aae00951f01fae7704bdaf3cfced2102f7de3cf10796cda41b7e43f3461dbef68e4319799575f44296ab7ac657bc8e257172ed44e78f46c1acab8c61dde
1	\\x2c258dc402173ad8de602913817ce1ca60096fa88150348fbcad47cae02fb03ba8cd0c650c4c9c7b1aa45410b9359916c454f4c03d357a39948381bbd73e2e49
1	\\xdf3461672af5da16f85ef1c7c396d18250483aa6033f30faed48974b933d92de2bfdfc5a796a59510cbd57f481306b8d26f731d8991810d40cfbcc5afa83a854
1	\\xa5d4d9006115a45438a58c348bfd4d9793185f5d92643fdff9497f8bfb2bfbfef6d99eb09f7e8aa17dfd0701571894abd69cb74dd87c1b8aabcab449a3111b6f
1	\\x1d4ee93aae5507ea7bb2c9c907cce0b464a965e84402754b861ccc669b050645d302cafd6c9312f9b9dfd80303b59795ae166c17edf6dc99d1adc6fc7f965ea6
1	\\xdf2fb6eed498576c12a28c3cf8d52429a67e90683c354e23b37c20e4349cfc0168192dc825e1abf155a940b6ed55f4024c371c6d5b941dba46d5e5c25463e39a
1	\\x64ecf6765938d9e5ead59b05452b69521ea4d47dd54614bcde385a9d2f180c0e645322ffea6c31ea09b04dceade9456178c780f66eae695dc089040fa5d753dd
1	\\x1dc3b1808bbf64ff421243aa861f852d551f4961e7483111a65fbc5c352aa89b12758b8cb918bf3781aa8991e670d9ac863d9f48764578d60ac230a3ca9f4c82
1	\\x53ac29f0abb834ec1ae1484836c831573bc7dcbbf9889e6ec8b3bd00bce599e682988645701829d39268f17b8c7d381ea9ef584ac4c00d4863d818afc344ff14
1	\\x1cb30c158d54054ac1a60eb8449667d7d9362df91fb77be45d765f1cb0b5f89cc54600f4c62e3ba20f21dba05c62c536cdc0c6cf396f139c702c2add4931ed99
1	\\x899347de196b1e70972ec6a4bf92aebff427594f4f70856ec34c808354efccf625a5125f1bcf25fda093c2b8e0cf1399c548ca49eb82df3d692981512bfd29b4
1	\\xfc742af02145e15b0f4e4a1b91e9fa18d4043b8e78454105a94765466a4506f636047bf1b49315a5630e7f94115416e292ba480d0da141863097bc530b8df1b1
1	\\x6c7259220702569a8295a709b4f1c4e5c727f8a466d0218a22e30aee54f6b0053fdf1d835fefb81eabd9a46e3f6ee835780c0077e9b73cee8a821ac4f25b4088
1	\\x2889d5484aad588401bbce25b99b08d2f8a9b5b09b37bde4860f165d8f0f7e0fdc0b22fdd27f4e5c3f0bf64f5e66956be72c2589f84b1978c55a1f493ab5fb44
1	\\x85f572c35f91d33cae4c6bfe3b4c7908f4fa03b9e23acbf58b5d2670276e75abf1036e117e63454238f289bda8caf16a402cfcf1d08593c7e902242326dcfda5
1	\\x279d701eebf1b3aacae92284d0d59c09a2b7887394127c02313780d693e244f31bd7e4b783f6e61fa5809906609c07e8a5d18e3f6e357ca67981d1be00e60ebb
1	\\x6728b615870b084a37b4cc038212ebceeb29b84d3a1a862ac3826bb59da01d46ab9082e76b17506f94a3787582d4250d27dd904837e15d41c8842f35af49d267
1	\\xb65c94385e47369f4776ca71263ebffb9e935fd2a5bbdda851fbec67a173b9432387e19f32003291c3bbdb54ed006615642ec7b98e73db0fc14551b703329588
1	\\x8fd4182fd6bf4bd517e6d38b4948bda1821b97a433c847f201bf7e820fb20b1f2a7b487058099ce2f3cb079eed560c72d0b09b8084bae9c6a530c7aac17f15a6
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xbd06538d27c36765e381952bec3ba29091aba754340796e14d92efe4b2bad381726456337ce352fa6a1a693ed725014528c7835b04bbff4f412b4a0bc476f6e0	357	\\x00000001000000010474902b23a143a1f9fdd80f83503b157063edc26bf8fd8c9196bea9bd9355037fbc783649ce905faab42f49d9ba25c7649ffe471d14b8ec0f6c0962d3a2ff3a306cbfa91a54251d67c27286ed3ca01cfa4aa9c8269bf6d0f441fa4dcac1746cab5cb63371bfa9414dd99c97a573ea462c98666092eafc1e2d8180efbd584093	1	\\x64a1b10b702e854dfed9c357af94112853f908f79acf5fcac0c76b16f3cf2fe6216bfd5f9840c939ea4d2da475004428d54ffaa11b5b552155f4d856293cec0b	1655124547000000	5	1000000
2	\\xb53b7684804f377b844ac8755088de6d7447f9fd4c9833698b8c1855b5ac952f59a499ef4fa91e0f5561d2fbac07637f2277f088ea45a04f655cc6a0610e5b49	191	\\x00000001000000011036e75783b8500c3feab578bc45a4f2afb6a55f3b0b1ec6f1a9375359aec6c32a83830126c98802929ecf9adfcbc3504f81d49b16c77b08a9952dde5381e509d243e90e45ce7dbdab8dc45547c8c2c4572128f4ea4cf00ce5482a06df9fe4ef29e77fc557b8b3f6aa862b97e76b0fe732a2ba13ca9b39657d2ae99da1787098	1	\\xcd2a855ee88524ad66ce32ce7a1c4bea17758ebccf54fb6ab1f1486612724e4f4cef32e9bc2d56858450cfa37ddcadd0b252e50799cc7a5219beaa6f871daf03	1655124547000000	2	3000000
3	\\xd75cb5a9b98fe3e5f26d8030ed23ceaf2c5de4c3b9b5bfe29595fdedc335cfb47781ab37b8d07a5dd16528c02b769a1e63a2b04ddb59e043ef351d4bfbc59e95	370	\\x00000001000000013a84d66cdbb2e3cc833193f1d5322fc82cae90a84e45a3e70a71b2944cff64c85712c291be9ef4b6542072f1bd0c216faf923706e6ce871edac0d71d4b61f8b1ee6318ca7cdead63a4badf9750e377ed83224d3970f558054f2806c68c30bd6becc326369bd70ecdb18468c7fbec08834a19e3107c02a82c97c8ea16a48d844e	1	\\x1c0c4aec95393b6f3316a3d45793ea836bdc2bd51bc33ace263a23005fd8030cf2f2c70a6b8fc9a5cd8aeeb3e844a1d940cadaff6d9240d06f418b40fb3f9001	1655124547000000	0	11000000
4	\\xc04cf27b0fac240ad81aba67269ab412c26cb42685fa860c59ed0b2d88385b825929f5b59f03c09c22c54ac7af271e00f84a923aa4555218bd77862d628bfcaf	370	\\x0000000100000001bca341c75a32ec5757938486f980ec77482335b0ad4a8596233918a419f25a1f1e0629266008a9a6ccf0a3acf1db770fed14cf3f2c5570372c73e2e3015c317f4f4180777a1fc00e877af90bab4caf3093f7446acba5f3a893fd2a6b29831845d56e847369b99d010a509096629870f8b5816bc357e695a2727a7c74cbc8c3f1	1	\\xc6f882fad53eb12ec0b8cae1ec02b5b1b258357b303f0ab5db067990c08b1119b90995d0b37ba86c838de8637b7253024059535466c15f92f44b0f7ed0cfae07	1655124547000000	0	11000000
5	\\xf32f879b980d1cabce174082bf11c5e5718bc737630f21da01dede0651309946288f5afd7efb6cac557d50d0ec7e927a246d8d2ed4da19a5d8b237d2d4ea17f9	370	\\x000000010000000147029aa31ed8701764fb737be6cfb6da07e9429f13e6347da9907d9ca600cc221e9d21eafc7b4e99d4ece8fa3e40512a6b6662af5084d680118614bdbda151e2a21877355f81c0231eb6b87706aef2389ed44aa3662d3445f334ebdfde67cef753f8245a40edebc15dcf3cfaf953d58a466593410470f75fcd6bf676d9824641	1	\\xf21c745dbb5d13970dfa5c5f2423d7af4cc87bc5f2075a5332e7885358aa3054a317bf43588202e0baa6f6d5cc185dd6cdf248332033713ee5aef4ad0f8d7e06	1655124547000000	0	11000000
6	\\x489a7a27042559dc74068d710ab6bb6b5a708396912e6fd1c0f13ecb07a54f6ea6c86d174f7658f23240c939693acaec51385986999f43f00c7da9f961b8a493	370	\\x0000000100000001025bd6a6cb64b514616e86faef0012b0f91589fb5b74081f5b708cec150b3220aa0e093e21ed9cd3978bad1129419f091e97a3897ab92ba3943063903794b894b1e0f65d6e5f109c1a435cf156d5d9c3d7930a8c93fdaea32995abe61a740c46837e4cef908c3c1cf64d165f6882365e96981a5923d707e9cb036435c20baecc	1	\\x0296af3f5b034d9348982b1e5d9a2215d81f15214be087ebf99f7852953e2a15bc925e0e2d2cac4da7f43409c5bc63070c6b3d8ba5325df19303e6238e0e0309	1655124547000000	0	11000000
7	\\xcc9dbc3d5510400ec2a3d00747e4d5a4eec98b5622426e8243859fa7f201495864a0a2a4842c7bb034965bb4a04e00da7b7b8e481dfb20b3fd9f6d79690530d6	370	\\x000000010000000193fa9d5371c19aea26bbe5e95756ff47e84106f841a7b717a17c98b48695d45724a5d94a4ca5081118d8ca48351634da5b4452cd7492c96d90de570bc50773a9796d629dc8c4047fea8069529d2e6466b82c68de03ab15c1121ebf1244ec2497d4e7e2536cb915e5192531f0f1f6357f2697893faa34057143f804995d3f63ca	1	\\xc1fa7b6f10fa713ee7b40c1d8cc067b71ca2f2bf4f3001ba263db802587f1f6286230f513e0fb7fdb64a2c5561f3334c067c3194e15a1e8b611433e15bc85602	1655124547000000	0	11000000
8	\\xc5c905da4637fbdda4f9f47a60f6d77e01e7f27e6e843c94ca9d0609551f92de2d821ed62fdcc8800992c78a866a215e1cbe7f4f30461404d6b682e998b06307	370	\\x0000000100000001786f8e12d43f1b2e03a3a91f4b487708874048b5e924aea2221389d949407e02eead9b2ac9ed563c001b72ef78fbc20debe9a72b7c1640ef571cf7a0e964930d952843ed986de39ecef38bd4e632c9e276c3e8817658cd4c1e36a2189f078cc162f866bdda6fb80862fd42ca46191699ee246c8ea4667020f97fad2d6842a42d	1	\\x0e109c895dd3beca1dceed0edf46cca36ba5de82e579c45a593c85ce00d2e3f01846ef474a719596fb0ce1247e5eda917247638ce7e8b7f8b72418c51ab29c06	1655124547000000	0	11000000
9	\\x6e327611f0e371d1813137a12f52e5eb4e5d242e4f49435c506910e9ae3da20f01c1b2ef217b18690e9fc84bff4a31a6bb05b98469a8579ce5a9090cdabb925c	370	\\x0000000100000001955f9d1aeafbaed65f5932dc5d192573b343e626b9b0650e903a1c4833c3845751f430d184ff01777e7c63ebb9f57be0bd8f29dd47bfd605bc5a712c4b4452c25d423d98ec11f82bf38c6786e76ef8f7cf810035ef065763624171903e29a4d98c3be76e3770de5d7d99bb50a346aabe1f8ac1797de84ee12c47a3081e1715ab	1	\\xd47b354a275b4708a508d3e82d2ef45c0f0d80744953e752c4f0dae458e50565abcac8fb4359a024e15d2d13344e013e64bcc6e4af0188835178d4e63eea060d	1655124547000000	0	11000000
10	\\x02233aae00951f01fae7704bdaf3cfced2102f7de3cf10796cda41b7e43f3461dbef68e4319799575f44296ab7ac657bc8e257172ed44e78f46c1acab8c61dde	370	\\x00000001000000017d1c8ab9999513e70653a718beec28656cc66ad39a920290185ebc8cef174e4be56db3b60e3b30af9c0faac4414eda2f555a891e3fa267b24d2de85a469a16108cd9734b39c1c2339a599691c3b832dd9e64fa7b8945f30d9cf69fe2d57e94838d58331e1a447f5b894aca6599560b2a173e539609203f03dae9ba90e75dc3ac	1	\\x48888e2ba2cf5c1a1e1fcb7b181e6f17f7d1d6e0281ee24e29927506b40ab7030b376b15e4a7c2166fdd293498e4b63430ffa50903d4cdc09b341b104850e809	1655124547000000	0	11000000
11	\\x2c258dc402173ad8de602913817ce1ca60096fa88150348fbcad47cae02fb03ba8cd0c650c4c9c7b1aa45410b9359916c454f4c03d357a39948381bbd73e2e49	177	\\x00000001000000018a12ac9bdacce052778d547730e3464f60fe2f9e1395309441a4de1943637b63236c4af8d9ebad14c3ef90f7ec1ae7e94b31b4ae424aba9d1f53c0a2a9c224356e9d522b5b02bff33ad9ea6b6751d47ff9180c30123b486aabb80c695071cb119add738adb8cb60520c3133e41a90d7b1a21e9f2dc151e798891ddd4503f4fa8	1	\\x88c9f33324a0345aafe509dff1c21fb2957b6563a58311ece3e37afebfef9f9bd9b5ec908ffd4b8314a06b4d41a8dce268af82a2cb051acb130eb8e627a5d00c	1655124547000000	0	2000000
12	\\xdf3461672af5da16f85ef1c7c396d18250483aa6033f30faed48974b933d92de2bfdfc5a796a59510cbd57f481306b8d26f731d8991810d40cfbcc5afa83a854	177	\\x000000010000000182c438fddff4e305514aa791fe65cfdfc45f93211af3fc457fae5a227fb48b79e05ca55d04b98a364a30b38b32eff5adbadf8f00452e89d6c6baf881c8d70035fb552704ae607f4630e41b5d9d6835994c4dea7883d91aef2d77373b18f8347bff4dfee222610c4ca8c304ebf7f82a668278e0158209375561ba243f24d22842	1	\\xcb8584228e0d35537de5ca81c4c20c0f5b450cf333e203bdc1cafb9e03a5a634da158876ff911ae3ed17add9621fe99e1978b88ca8e949375efec5019357d70b	1655124547000000	0	2000000
13	\\xa5d4d9006115a45438a58c348bfd4d9793185f5d92643fdff9497f8bfb2bfbfef6d99eb09f7e8aa17dfd0701571894abd69cb74dd87c1b8aabcab449a3111b6f	177	\\x00000001000000013ee0f875137528dcde34c9c64ffa7b3dccb76784e7f8dbd595bb6b059136a67629d4586ce70c015c35c0ee36c58cef1d1f8727be6253151147ac1eab9aa0c19ef3072097c8e05a36cbe495f83553c68e9f7e1838e9dedc78e4c3d0b56d3c2358944581dfa17cf5d52c322e838b190b1ef2f4f49f92ecebd318613a55a1ab34aa	1	\\x51b408c16e3a68b2cca9b0ff029bcf3d1a9b8c22d5b88800d433d7e40e77ca3ed68edf731126c58b9637c6f56f633bf78fc9eb2f395de8b151b18c2f73a5070c	1655124547000000	0	2000000
14	\\x1d4ee93aae5507ea7bb2c9c907cce0b464a965e84402754b861ccc669b050645d302cafd6c9312f9b9dfd80303b59795ae166c17edf6dc99d1adc6fc7f965ea6	177	\\x000000010000000170912b0e6ef97daa426bd04f85807b71a9850db4912abcf29fbc4f99251805dab23fe2100aca59e62aba4f115d551593437133e4d019c87bb6e2e6cd1d22b48a4b5547cf2a8ce1d3c136b8216a761c3adbb280ffe7417c6e29e5daa41686d788f257d565c8ad8efd556b88cf3181457baf98e19393a2aa49b45cfbce79c1e02a	1	\\x20e89a1b0ed6f6cfea82d17214a5cda61a3a01baef8e1c0e474c1711dc43252a5b1c6d6836a3a6e568a57c16d3a4f2fcc2a39b94f59aaaa6bbb6ca69fd1ce306	1655124547000000	0	2000000
15	\\xdf2fb6eed498576c12a28c3cf8d52429a67e90683c354e23b37c20e4349cfc0168192dc825e1abf155a940b6ed55f4024c371c6d5b941dba46d5e5c25463e39a	232	\\x00000001000000010f619b2a0a623ac9ed80f7a02879e9675d8841f9b24b18cac018d35def11e79a188e6e3b398ef63fe6fd87026c53a3c6d5effb2f6e4a979bc2fe4c4f363b60c8b521eb5b01d4102a1c2a3fab4843c412966b80fa037e1a00253908edd701f48c95d67f560adbf364cc58b072cf51bd2dde64f633005d54f0cd67a21edeba116e	1	\\xe7178b3cafc3dfae1060d54fe1ae54b988b47d4e30a727bd7a3f97737e879989465f6503b8fedbe06a6bc45cfff0096bf4ad069d6e226111e0ef7db08ba42200	1655124558000000	1	2000000
16	\\x64ecf6765938d9e5ead59b05452b69521ea4d47dd54614bcde385a9d2f180c0e645322ffea6c31ea09b04dceade9456178c780f66eae695dc089040fa5d753dd	370	\\x0000000100000001a0865176d405e8debb91045f9103abfba569c8676212f18e590cb0b06acf07986303f1b4147a80331d830da59b226a734f2c357f6da556ef9f36038ae17fc38e7da3ecfd1bf14fd051f23e1e15f3cd72c25665b00840fe8278e5519a293f09371ffd3f37bc2885bb1353ddf38f83bf666ad4d2b43a3e1f153dd706f7aafbcc7f	1	\\x9e3e498d5e4a62391f87af5c681e265638c816e2211f85ba30c567842d91794fe4a4daedf4a9310fff2daef54ac7386b38c087c48a7cf04c088456a755eef30d	1655124558000000	0	11000000
17	\\x1dc3b1808bbf64ff421243aa861f852d551f4961e7483111a65fbc5c352aa89b12758b8cb918bf3781aa8991e670d9ac863d9f48764578d60ac230a3ca9f4c82	370	\\x0000000100000001babbda6815a5c058bbdfac57d8998c5b60163237fce71ee03c7101cfadf42bb8925bd4ca4afdab66475541a4c6d9a9cec177d58503f441b31fe1d1389e25571264505d3173e2cff648c3bf73847e26eed8a3c102ffeddf0db03d97f75552adfb9a449c9864dd72a8e0a4ac770a0a234b399205a26d1a6e66e734eb002c775600	1	\\x902874e4b8f96b303ac79222a2d1873ea89e700341395bd40aeea82d4a77896a67f0dd97086ee7ba3dcb4402f56d9ef9279ff3af9d616002d20e97d8097f3502	1655124558000000	0	11000000
18	\\x53ac29f0abb834ec1ae1484836c831573bc7dcbbf9889e6ec8b3bd00bce599e682988645701829d39268f17b8c7d381ea9ef584ac4c00d4863d818afc344ff14	370	\\x00000001000000016004bb531cf85d7aab936fd5cc5ab8352c810204bf4a6775b40fa45297fdf954f1dca6e61f75d857c3cf89e04f9597b164c873e28687fc2923fe36b6df32415db56d564ee03a4685c6c97a61b75ae2b124e65e0c1e29c0e1c4855c41bee6b7f39695f24009e0b7a00a6e4c6c561d826fba84dd56628345f3ba86b8cb7549e822	1	\\xe50ac171598077593aaafeb5fbe06e7a825ac1197f2714c8335f1b61059f87f9502f4c6337471229b929811e3a994f8eff62443d2388ed48a303f148a642180a	1655124558000000	0	11000000
19	\\x1cb30c158d54054ac1a60eb8449667d7d9362df91fb77be45d765f1cb0b5f89cc54600f4c62e3ba20f21dba05c62c536cdc0c6cf396f139c702c2add4931ed99	370	\\x0000000100000001505c7da0900cb10326c5ef96f6afdd70dc874fe30824cf6ff43ba439f3a3393ad47be4c22f6195473abbba9461282ff4057c9fa6f2e315101d3536976aebe766abe1dea60b91e503884cef02f52e4546776b0be4795059c34fa57a19092b06d0bd765d493d022454d6f4c2ca886a8bce1284359613e0d31f1041b17af1b27026	1	\\x61d384b715376a23b82acab9e0272dc6840d300b4f515ae70aff4764f70c663cdf5495aab604f06bdaf7f754e1990cc56febfca5816ed789ec25664d601eea03	1655124558000000	0	11000000
20	\\x899347de196b1e70972ec6a4bf92aebff427594f4f70856ec34c808354efccf625a5125f1bcf25fda093c2b8e0cf1399c548ca49eb82df3d692981512bfd29b4	370	\\x00000001000000011d5a1cca395294d5ee4bb974fadfecd5ba5a61f9e5f7944b2174acb5cfc43813bb43dce6efd34334d8e1fc5a63265a57f725cde9adedf40fdf23ffdd9d6a18287d002a17f8bda6e0702b6dddaa0eb9ddca6bec53d5c7e5b512df71a16f0977f24c0422eaefb5491fd5fdef8b48f44daa4985d6819ecc1efb3f62820382c87729	1	\\xc317f3005548bf81f7c23cf2d4f11eb12fccc25d1b128c723562a30aa01075604e779152cc8bab4f6af13fb79a0aca4defb27f6761059e6cc7fe5b5bed99c20e	1655124558000000	0	11000000
21	\\xfc742af02145e15b0f4e4a1b91e9fa18d4043b8e78454105a94765466a4506f636047bf1b49315a5630e7f94115416e292ba480d0da141863097bc530b8df1b1	370	\\x00000001000000017fb2d3a592d90eb66c5950159a79950ccf1cb26ba9fec9b541e2d781f9e3b4c784384bd75c8525fd3ada6eda2d0d23a7bb7c3786e5990febb8f6d41d85a6dbf264fbf0a54a05f5e382349e29751a969b3cff250496cff9f00268328b0e6c7605d76e4cfe1ea184597ad4e51266e74424e65bb0ee950fc23da2003d33187acb93	1	\\xd8632c9e073946c105bc0afff0cb06e0357b084806777d767a2981df17b27822e1865c286d49abf8819ffa89ef291d975a386dd7c41903c2178981a5f31fbe06	1655124558000000	0	11000000
22	\\x6c7259220702569a8295a709b4f1c4e5c727f8a466d0218a22e30aee54f6b0053fdf1d835fefb81eabd9a46e3f6ee835780c0077e9b73cee8a821ac4f25b4088	370	\\x00000001000000016e19263a451f694ffcd9b0e1d7aa401cf3ec6938f2d1650c4b93b5a7061b0bcf21ad6983a6316d4d1836b5db3c47947601327c072166802da2065856e07b94c8226d020c5171e782d4cf007eb72b89528351559f393af787bc44a056e7e04c2f87e76461d89289b257807c57ac3fb17c0bd3b5b67635df2901c0ec407191efca	1	\\xb1b4a72680cfd13b194e541d4977c56e93b78ecd28b341e79704c5e79119e5cee7451df19b1a6c297065a4eb18c62e983b2c72b78ca8513289924a2850d3440c	1655124558000000	0	11000000
23	\\x2889d5484aad588401bbce25b99b08d2f8a9b5b09b37bde4860f165d8f0f7e0fdc0b22fdd27f4e5c3f0bf64f5e66956be72c2589f84b1978c55a1f493ab5fb44	370	\\x00000001000000012f96fd455f650b392d53b47f93c600275b3beafdaf9b51a29f66969e36468d8ec5745b77e77a5bb951ea995f6f7ece90c71e73ae3d681bc7f68712d1bc054769f38fcd5b44740f1acf87b56f4fb611350b5a2248246b95cfa140eebf92fef620b054700093dfd73547e0b0264c95fd215e38eb302883ef557d56de42e5894cf4	1	\\xbc64c6b1c24a3a3e92fd9d75fec01b2ab8ada6818ad813a47ceaaa69e0d8a26001882b5156466508444c42f3c86f1614603e24a10efd9ab0715a4f8005af1c0e	1655124558000000	0	11000000
24	\\x85f572c35f91d33cae4c6bfe3b4c7908f4fa03b9e23acbf58b5d2670276e75abf1036e117e63454238f289bda8caf16a402cfcf1d08593c7e902242326dcfda5	177	\\x0000000100000001d60a721a05e842b7abd926f1d7836dfa4e686c79b240cf2aabd0f8e61228978895011106e0aff2b5d73fd62e2611c258a55b3b6d12eaa8ff0e53d64b1669d8b47bc530c2f8378874c1aa24baf785b7b108f1b5444304b6ed06e2a4243682402eab33a8e9e1c7ab57313979e011d6d507443ba260f5328aa380a4cdfbcb21c6a4	1	\\x4ad096212ea1eb1f4dbe96f84becaeba2295d9503e62cae3d5caecfee8381b0db745634d722422d589e3a71407f9c52b7e28276650c0cc72ebf91dc6e0fca605	1655124558000000	0	2000000
25	\\x279d701eebf1b3aacae92284d0d59c09a2b7887394127c02313780d693e244f31bd7e4b783f6e61fa5809906609c07e8a5d18e3f6e357ca67981d1be00e60ebb	177	\\x000000010000000108406662f12f1d9cb9a2bcf61c9c5209efd0d780351f7a8ca2bca0475d66c4b03ee310b25fd858357c2b82d871533c4e9ebc5c6cacc3c9ccf814edb460265fb027b3d6dfebf63ee5b2425d41a2b35774b0e4fa18cc4da6ce74573c06c5092c93745fa844dd55592cb95dc06ef82402d3c48abde4c491ff2f0b173f894e125ef4	1	\\x59b99b330ae6c27b53bffe02086b9953d86e67834e3242b89d5bd7b59955b28dc7c8df31f82a31b849eed85cae28e6c913c44d555bfba75ed67be92ddc27c404	1655124558000000	0	2000000
26	\\x6728b615870b084a37b4cc038212ebceeb29b84d3a1a862ac3826bb59da01d46ab9082e76b17506f94a3787582d4250d27dd904837e15d41c8842f35af49d267	177	\\x000000010000000166dea605eb8955be5dee5a8625db281c5540f73b90ac16e6424ad10275e54d843b46595e94d142368d7e40f95eb0f39bc73f594ff8cb06cdeb706a676964a05df888617d9d7531d5e466f31f22227fbfcaf46c0687a63a46dcf709174a3457123ce33d2e39dbf9dd86e09e93bcf04acf623b802c0e3f2901b71760b17d9c9d7f	1	\\xc26cd84cee25e4c9339a4da6cf183c2e060047dcc31239f65a83af0f61c8c4d121a64dfbc6450bdec2f1e7455d7c1597904a9b91fd3230dee9a363bf9092e900	1655124559000000	0	2000000
27	\\xb65c94385e47369f4776ca71263ebffb9e935fd2a5bbdda851fbec67a173b9432387e19f32003291c3bbdb54ed006615642ec7b98e73db0fc14551b703329588	177	\\x00000001000000017f0421bdbed42b0faa9db231af195d7c2b532faf65b68406b6d6e0b6589548b4a750793a56c0dbc2201ea9b04b14a2f2b22e69f4a17fd3b35def25a57c1f4c07e49916273e3609090c8bbee02d5f34dda3e3b104ffe25dafec136cf212ec772d60fc787773d929b862d7a9ca576c38e4c635e1e144e1dffd4e7edb833bd3f8e8	1	\\x7b172992d80b9fc15cc8cf800ea8439e377b3f8dfa2044ae8d03d889dd8f371b13bdd0e450837410827591c8b4f383b84e2f8a39a6992485b73b2f3c546a5503	1655124559000000	0	2000000
28	\\x8fd4182fd6bf4bd517e6d38b4948bda1821b97a433c847f201bf7e820fb20b1f2a7b487058099ce2f3cb079eed560c72d0b09b8084bae9c6a530c7aac17f15a6	177	\\x00000001000000017a8642d232f850fc05925e300085f78fe061665684bbf03f4b50267e92950cf41aa5d108896e0606208bd7c14dcc071d286903b584d0ff65fbf35efc556def800d98c616fa64f1f9fd303f0479b7b88932123bf03c9db9252b5c248a4660002a9d8196c24ea6fa86de0f11fa76ac022907fce5ee6a904c49bf741fc4f0b1d403	1	\\xbdb50d2dfedab1cc97f4ddbf98a3b0ad7f6714467bb65b907cbbaf60344d07797b4b495ca4a2ae6a7c2cfea152efa36fdf7f282e629576ae33e81cae50e3a00a	1655124559000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\xf4f35f53f32c7cbd4d845fd7a2211f6c8000074b0653a713872fde3577741d1b84fef98e2ca213866653b8d4154cf346d96d1fc2cb092ea2278382e661c6df0c	t	1655124537000000
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
1	x-taler-bank	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\xbee51369ace82f18a208e7c249ae8cd38c0d66171a08bf86aeabb2f776b197c52cc5e48ef29b3e73a010d13bdb1a4e63c5c4787a80d154bc50daad1a4996ec0f
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
1	\\x12d95edaf029db6715a6830bcf154777cd3db087bd2503f947c32da46ab1ad24	payto://x-taler-bank/localhost/testuser-as98unb1	f	\N
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

