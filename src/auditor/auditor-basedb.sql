--
-- PostgreSQL database dump
--

-- Dumped from database version 13.5 (Debian 13.5-0+deb11u1)
-- Dumped by pg_dump version 13.5 (Debian 13.5-0+deb11u1)

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
      '(reserve_pub BYTEA NOT NULL CHECK (LENGTH(reserve_pub)=32)' -- REFERENCES reserves(reserve_pub) ON DELETE CASCADE
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
      '(reserve_pub BYTEA NOT NULL CHECK (LENGTH(reserve_pub)=32)' -- REFERENCES reserves(reserve_pub) ON DELETE CASCADE
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
      ',remaining_val INT8 NOT NULL'
      ',remaining_frac INT4 NOT NULL'
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
      ',purse_expiration INT8 NOT NULL'
      ',h_contract_terms BYTEA NOT NULL CHECK (LENGTH(h_contract_terms)=64)'
      ',age_limit INT4 NOT NULL'
      ',amount_with_fee_val INT8 NOT NULL'
      ',amount_with_fee_frac INT4 NOT NULL'
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

  -- FIXME: change to materialized index by marge_pub!
  EXECUTE FORMAT (
    'CREATE INDEX IF NOT EXISTS ' || table_name || '_merge_pub '
    'ON ' || table_name || ' '
    '(merge_pub);'
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
      ',current_balance_val INT8 NOT NULL'
      ',current_balance_frac INT4 NOT NULL'
      ',purses_active INT8 NOT NULL DEFAULT(0)'
      ',purses_allowed INT8 NOT NULL DEFAULT(0)'
      ',kyc_required BOOLEAN NOT NULL DEFAULT(FALSE)'
      ',kyc_passed BOOLEAN NOT NULL DEFAULT(FALSE)'
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
-- Name: exchange_do_purse_deposit(bigint, bytea, bigint, integer, bytea, bytea, bigint, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_purse_deposit(in_partner_id bigint, in_purse_pub bytea, in_amount_with_fee_val bigint, in_amount_with_fee_frac integer, in_coin_pub bytea, in_coin_sig bytea, in_amount_without_fee_val bigint, in_amount_without_fee_frac integer, OUT out_balance_ok boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
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
  SELECT
    1
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

END $$;


--
-- Name: exchange_do_purse_merge(bytea, bytea, bigint, bytea, character varying, bytea); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_purse_merge(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_partner_url character varying, in_reserve_pub bytea, OUT out_no_partner boolean, OUT out_no_balance boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
  my_partner_serial_id INT8;
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
    RETURN;
  END IF;
END IF;

out_no_partner=FALSE;


-- Check purse is 'full'.
PERFORM
  FROM purse_requests
  WHERE purse_pub=in_purse_pub
    AND balance_val >= amount_with_fee_val
    AND ( (balance_frac >= amount_with_fee_frac) OR
          (balance_val > amount_with_fee_val) );
IF NOT FOUND
THEN
  out_no_balance=TRUE;
  out_conflict=FALSE;
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
     RETURN;
  END IF;

  -- "success"
  out_conflict=FALSE;
  RETURN;
END IF;
out_conflict=FALSE;

-- Store account merge signature.
INSERT INTO account_merges
  (reserve_pub
  ,reserve_sig
  ,purse_pub)
  VALUES
  (in_reserve_pub
  ,in_reserve_sig
  ,in_purse_pub);


RETURN;

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
-- Name: exchange_do_reserve_purse(bytea, bytea, bigint, bytea, bigint, integer, bytea); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_reserve_purse(in_purse_pub bytea, in_merge_sig bytea, in_merge_timestamp bigint, in_reserve_sig bytea, in_purse_fee_val bigint, in_purse_fee_frac integer, in_reserve_pub bytea, OUT out_no_funds boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
  my_purses_active INT8;
DECLARE
  my_purses_allowed INT8;
DECLARE
  my_balance_val INT8;
DECLARE
  my_balance_frac INT4;
DECLARE
  my_kyc_passed BOOLEAN;
BEGIN

-- comment out for now
IF TRUE
THEN
  out_no_funds=FALSE;
  out_conflict=FALSE;
  RETURN;
END IF;

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
     RETURN;
  END IF;

  -- "success"
  out_conflict=FALSE;
  out_no_funds=FALSE;
  RETURN;
END IF;
out_conflict=FALSE;


-- Store account merge signature.
INSERT INTO account_merges
  (reserve_pub
  ,reserve_sig
  ,purse_pub)
  VALUES
  (in_reserve_pub
  ,in_reserve_sig
  ,in_purse_pub);



-- Charge reserve for purse creation.
-- FIXME: Use different type of purse
-- signature in this case, so that we
-- can properly account for the purse
-- fees when auditing!!!
SELECT
  purses_active
 ,purses_allowed
 ,kyc_passed
 ,current_balance_val
 ,current_balance_frac
INTO
  my_purses_active
 ,my_purses_allowed
 ,my_kyc_passed
 ,my_balance_val
 ,my_balance_frac
FROM reserves
WHERE reserve_pub=in_reserve_pub;

IF NOT FOUND
THEN
  out_no_funds=TRUE;
  -- FIXME: be more specific in the returned
  -- error that we don't know the reserve
  -- (instead of merely saying it has no funds)
  RETURN;
END IF;

IF NOT my_kyc_passed
THEN
  -- FIXME: might want to categorically disallow
  -- purse creation without KYC (depending on
  -- exchange settings => new argument?)
END IF;

IF ( (my_purses_active >= my_purses_allowed) AND
     ( (my_balance_val < in_purse_fee_val) OR
       ( (my_balance_val <= in_purse_fee_val) AND
         (my_balance_frac < in_purse_fee_frac) ) ) )
THEN
  out_no_funds=TRUE;
  RETURN;
END IF;

IF (my_purses_active < my_purses_allowed)
THEN
  my_purses_active = my_purses_active + 1;
ELSE
  -- FIXME: See above: we should probably have
  -- very explicit wallet-approval in the
  -- signature to charge the reserve!
  my_balance_val = my_balance_val - in_purse_fee_val;
  IF (my_balance_frac > in_purse_fee_frac)
  THEN
    my_balance_frac = my_balance_frac - in_purse_fee_frac;
  ELSE
    my_balance_val = my_balance_val - 1;
    my_balance_frac = my_balance_frac + 100000000 - in_purse_fee_frac;
  END IF;
END IF;

UPDATE reserves SET
  gc_date=min_reserve_gc
 ,current_balance_val=my_balance_val
 ,current_balance_frac=my_balance_frac
 ,purses_active=my_purses_active
 ,kyc_required=TRUE
WHERE
  reserves.reserve_pub=rpub;

out_no_funds=FALSE;


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
    purses_active bigint DEFAULT 0 NOT NULL,
    purses_allowed bigint DEFAULT 0 NOT NULL,
    kyc_required boolean DEFAULT false NOT NULL,
    kyc_passed boolean DEFAULT false NOT NULL,
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
    current_balance_val bigint NOT NULL,
    current_balance_frac integer NOT NULL,
    purses_active bigint DEFAULT 0 NOT NULL,
    purses_allowed bigint DEFAULT 0 NOT NULL,
    kyc_required boolean DEFAULT false NOT NULL,
    kyc_passed boolean DEFAULT false NOT NULL,
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
exchange-0001	2022-05-02 20:31:57.856832+02	grothoff	{}	{}
merchant-0001	2022-05-02 20:31:58.689509+02	grothoff	{}	{}
auditor-0001	2022-05-02 20:31:59.197067+02	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2022-05-02 20:32:08.901914+02	f	50d22041-64ce-4fc3-b2e2-572fe211f025	12	1
2	TESTKUDOS:10	HFY3XJR5XH19TBKJ22ZMGHDVCQD1Z8A9DPRD9SDTB6PRD9KX96TG	2022-05-02 20:32:12.354897+02	f	0240d38f-c322-471e-b850-deb57e1b2391	2	12
3	TESTKUDOS:100	Joining bonus	2022-05-02 20:32:19.074017+02	f	26e0c18e-5531-4e80-ac29-74187d58f57f	13	1
4	TESTKUDOS:18	D4ANTKNHAJ99EKAHYB9VKFMKS7BRCFFK3XA662YPTEBG8K5WVY70	2022-05-02 20:32:19.767664+02	f	755ad4dc-948a-47fa-ae74-54806385660b	2	13
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
9e47fcb3-2ae6-498f-b2b4-72b7fd4b5eed	TESTKUDOS:10	t	t	f	HFY3XJR5XH19TBKJ22ZMGHDVCQD1Z8A9DPRD9SDTB6PRD9KX96TG	2	12
ac57842e-cc12-4560-a088-3ab3ef1f0f4a	TESTKUDOS:18	t	t	f	D4ANTKNHAJ99EKAHYB9VKFMKS7BRCFFK3XA662YPTEBG8K5WVY70	2	13
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
1	1	9	\\x149f68b651c89fa37a4a1c3497d6001eb852d376d957c20efc04bbffc130540f3fb9c9e1de4f2f30962f09f79ab63b0797fd4b327cb7cfd63019a3a3a7d5e101
2	1	139	\\x594297451bdc316f9f7801c2840f1ae5e99d541ae20c372b7c876761ec1877ad7c3d3fcd962ef2a7bc63069900afd0edb7cdc0f2cea782683760a40792aea10e
3	1	198	\\xe3700d0f3894e1462b79c066f30432bd21662787497ae392a1016529d1f12d9f81a90ec8e07f3742381c553c03a9f2d01340d491f0595931575bf7e876188804
4	1	372	\\xbfbaa63a569ea1ded26d36e296ea8df2942df9879773533005e33f3d038c122de3e66631797f6dd6a53b8d13a45fa18035ae760a7a07fe014d2016867764190e
5	1	209	\\x2a6981ec250dff1dc0076a62046003249b561b1075188d8a3ac764438fcba6a3f4dcb8b82c9d68d241036d3af195de9c534d9b2200bd61fd9adbe0a8d283cc06
6	1	221	\\x59f385979473c3fcb6ae37b72931deb66f986bfb3287ed2e3d5290edaa036c40f2fbdb5d5e341f350582e81dc2236fbf9ff7f6af2ff82a418afc6e77a9a1a406
7	1	388	\\xd04d5ee6890dc30727b1a5294b6b64a41f4697e9ab8fdc01f212719a209251e7399566e3170aaf9135a1d9d100999353814df7f6ef9019de318ac4f1c5a64008
8	1	422	\\x04686c83dd20231165c5c7ee4f18a6c7de5a811bcce5d8805226b45e8af8a98fad7ec6a9ac183418b0fb479657d047cbe04fdc55d268cb5c7c6418f8e86adc0f
9	1	411	\\x6cecbb9205cda673598d3db01cb4104b3bd46d8dd596509acb3b3782186f7a905c046b5348451930b2f2005262ee34cb11a8d3cb15d65a44d2eab3e485a92701
10	1	312	\\xcdf3fd8c2b0de883bd0bbd35533f1fe7b9cedd44656f679d50bb649be6e705a31d3b6b8830c77c11dbef226bd75093235532f47ef98748bca439d3281e56af09
11	1	23	\\x9527d19dc5332df2ff5029795182496b3818da2fcfc9245be3c07ee83890a9380496f13bc3392c3b8621bf2d63c41a12624fe451ebf3fde2a051748c6b0bac0f
12	1	267	\\xc0549b5eaedd9a978bd45f9b8769e6f39396c9560b7bcc1171dc45807e9f1f75c78f20e09fc7085eb093b428aae9a4703023ee836d8cf13c8928aead2922fc0c
13	1	299	\\xc732094858c10f02cf61bfa44a9eb2c7de5d9ea81e92259dad0fec392a35a83ebf29ca24b913f1aff7a436644d2112c128789650267feaa8f772da07cc38830c
14	1	343	\\x435404ad01c5e938a306257d7b4dbc65462a556c6de7d7b3cc3daca2904f6722f55ed36c3927c844db20beecfa268602d5beb70d156ff5b293a3fd54c07b9c0a
15	1	77	\\x3298842fefbcacad27b61030d2173fadb52878f7b4b091d1dd2f22425ade36ef77cbfc6fd49a59ca5de755975fc89148609ac12b1950dd8a57d2b7cf5a97390d
16	1	318	\\x7c1bc7b9416e579540f8b602db38c07de454977e0d79190c11b81fd761eddf76d0c0db0a4b4409fc486d45a74361157ee1eae50710d6994a9daf17717ef7aa0a
17	1	391	\\x2b0a9edb9a903337e29a851f2b4ac2b07e82a358ba4065643aa778c8b7aeb955430aab6555e81e1a3e67e9570fa2fe20916f5503ce87330aee6124f21aa69403
18	1	348	\\x38b9d783e277f1662d4e49b245abb3e552f015a8be2f59214bb9b5fecb996c09df9644ee5f47981d6e6e6dd3a809c7ac5132d727d6e460b4dec767efd9a4c80d
19	1	360	\\x3896df088d81c084256982febcdb72eecf61060d9394581742670a554e8c2ab8eb28facd2f4d7354152680598812c6a0ee930a5b4eea6f9e237c0054c900040e
20	1	34	\\x7aba15f0df2d174ca5b3ce60c13ab22088b142119405c6ac5f29c41cf4131a153787c7366235c552ad5e4191d3f7bb96058aa18971ab3770724fc9fcfc525d0a
21	1	402	\\xe1664ba87e1a447f1908da2d3df9e188b9e0cd77cb041a33d88c23578a8102ef8ab6779bec68ef2b603e116d16d245c96e1d5577cf7d3b8fb38ac8c5d87b8500
22	1	114	\\x22be2a0e3d15e05152e72826891243a5979b76a305698edcd834ca81e7e6562ef665b2cd5a08b41656d1887014d310834bbe96e5c01a08957d23a35e62adeb01
23	1	287	\\x3d47a3b3948619db10f0eaa198a66d84d0c2db1e49376b48a6a6b0b94cb58abda478127fbec65b7e311dc348749d6efca074c2b01f8156437fb594a022797e0b
24	1	413	\\x1a14c6ff3d709db89c31b1b4eeaf540d36eb229d4e364f1810e0bd25528f875a67ed5127020d4a4fcb722eee3195f4b550c53335351741b7d76205d068b40e07
25	1	334	\\x8083994ea17bf385be258e38b6ee280dc154655c452a6ba24d453c1c1c7704a98015d938ced0ff40f1bb4cc1b10ee45b2fb3ec33bc66962ec6860fd5ae9a4b0a
26	1	335	\\x2c3433aff168fae806af742d9b253af9ee1c2ed5600b50d8ff93d47a872c8dc352173b210098ce839b722e0aa9d3adfa1d31fb9ce6f5ce98c945e72b7cf3fa0c
27	1	346	\\x49727fcdc441417e919cafd584a1e304a0478cea2e73fc6368120586d2f81364f92361fb513151a698d17aa0a6ee6d9fffaac915e23dfbeaf196cd02543ae002
28	1	20	\\x0a340bcf243f4375fde678fa9ba77ebaf1bd57e9ff1da5ff1f26dbd8795262badf39ee6237b403c08cf252f4409e926abaf8b3a10b4b37ea0553e010015d5702
29	1	95	\\x7288d06d9a9b420f179a2e5e293fbdd39c2abc6e3706e9f40cd6120c6144d5b88be5c000ceee6eb3d5f49b463430cba9b92d2b94940615287bb38a268f776008
30	1	248	\\x4f78ac0c91353f9743325eb744a800b3903adc3b9b74cf18b195a1c73d5702353f646996546f0703ad726032225653d0126c78980b44e6bbb09a7550218c910d
31	1	148	\\xf8dafeace7e85e4436e2561feb99e5b83d87dd830c506c4917dcdef79144253f3dbedd347a7536b55cc4b9a4d3ef64b2f9df5b0c6a603ef710f14632627a9906
32	1	158	\\x9d0817360f2f350237cb98aa47c488b5579640ca7439f55eb35c11629e4f1471afaa9bd534902bf0a2318176d1860fb719b36cd174725884f1a0ae34180b7a04
33	1	193	\\x76c7320573c51fa23d7b52d8be58581315671cb4549d6741ae87c9eaae3756b1e62c9952efb0b07439c0c1079736acbd9a0925c8de96a5827f86d7e494ef1701
34	1	268	\\xf8bbb37fd21b22df3f580a73f63c4bdd24eb71da4234015f12b426e90cae7bb1695b3b3c4b31fe47c2562072c4e93de51304dc377bb0a42ca87e93c9bafd7c0e
35	1	70	\\xfb26ab8b3d29ba3266f565943714f8edd2e5e55fe186dbe96d1997f018e59a2d7005a15dd27b00d3d871ddbddb52c7a55ca1cff3cb083362572dc4c0c9dbe806
36	1	387	\\x82ca7d203df22ed1ac780db0b5779e6ca6db2b0b985958b66d2534d8c518e7267efacd122d3b8b3439b96d30c3b487b3aad55a690150ea981a609bca0f13470b
37	1	120	\\xd3c92a6f1a505804ddb95a010e9d8fe4a193df475bb32ffc9461a4ac26d3414ae3a2008f51eaa6ab45cd8a288d00329dc8d3e51520b5b4951eeb0dad48051100
38	1	394	\\x0409af586128157888fb7bee0e08ead256436611ea55a1a1a26dad1a00589496ad7c4ebca0f6bb4851bc6d3ec4a1079d8c489d81e1656bba04261e239c02920b
39	1	146	\\xcad7ebc66936178f54c7032c0c7b21c6e05bcdb32134a82865f5a16820d746701b08633bfd107844328abe281b0796d59be6a960a43a049b06e25252091c6808
40	1	194	\\x31a960d8528ed4a3dc9d420c54c3533ae939faf6ed73a2e68c6304272995a8ce740433334518880a83a3fbf82c34455025ba83e697dba486546a413b31a7e200
41	1	256	\\x79e227dee8823d19f27b68a65e8c1a7eb8198bd01686f633d23efcf3a957571b76a79ac7385e068fcefffd6be7c1e64b66a6de2c573c516310dba8b9fcc51406
42	1	295	\\xd3bc5f5f9474ab666a2de6f8213b8001ca75dfdb129f8ef49e84cb68a90cfdf3c7300cb6fb6d0b55e502903a32551e2b5e22f2281e81b7e845355d4550c1d707
43	1	196	\\x20cd07075edeb81be4e5afbc9310110598a954349eac1b508fc538c5a68e0d08abbff0a8cab6977082bd5c98e6ca311d8fcbd0edce176794ffab40378a78d90c
44	1	357	\\x718db20664f4b929ae6fafe8271e036b777621c82f5d196973106322c801451dd69d40afeed02264d3c7402c15a32a630b48ea638b6d20a10c51e39b17fe5804
45	1	26	\\x8027437ca59254a9563c5d8b94987820cfd4fb6b786ebc1f767576e26cae165524234fa4dc6e3e2b8504ffb0cd192f2cb36a8c5493d5c8b20428fefba50d4207
46	1	132	\\x3724028c01f31482d8a5f61e0e8f5de96c7297dcc63bc714846e3329a33a7cb3687585ccd2ba5a9a391ac60056b473b1bcb40f1d715edc6ee7e8d64809dcca05
47	1	63	\\x91bdccd65e9656d97b99c0f87ba799269330a515abc95a7f6688f76af94e0edfac7c3b933280bf63ff0136ef0e405794978c71719a62022bb8b5371d6a498303
48	1	367	\\xe18f6ac337a658f10a09436b428d4c817d00120baf1bdaeb364e964d976879af917ba670c44c74a67ecb683fab0b0dc5eeaca4c36668164c49205f95f7840f07
49	1	184	\\x2eb1d54d3f4dd83a126d6dad3fdb7ae0ec1db6ad35088e13ae3969253003557cb983769cb83fdbd84402658c21548e54d72f09475394ed1f786ffe8942937301
50	1	32	\\x2fba4c344ca9aebabee686c07044c632ae2d621b9127bb514a5a8a2a7e59b8b5164409bda701ffac11fb7e656e440aec4fa5f878d50838827e146a2e981d6f06
51	1	316	\\x90635a819b62c217826c8916577f683bdfad82bc04f97e2978c88985ea440160e9e251a7e8944d8780d72097027a1ef9a599457ddf7bfdafbd0b4145eb43e405
52	1	160	\\xcef5189f126a0f1eff621e3d836ac29a21f5933794e21d43ae7c0dc46a53aabd22eb8989d2c4caba2d2cca9043b55b6ce1776cd3eae96147e4d0233f58847108
53	1	337	\\x189cdba36acca4461507f094c561cfae0e92463e16bdf0a50926a44266b8fa2df9ef88c8d6eac20be76dd3359e1737e14c23fc733b9225087e1aa91ee5073801
54	1	15	\\x3f44a8762173bb08700576b42e942886f9cd82e301be3fc6a49c0929454e440260cdc8fa86cf3eca84dc6750443e7be0cba2c3a383d0e9648dd1b000c96d060a
55	1	215	\\xfab9f5f11aa1d3875489ecd96ceba59438f0a91bbe272e417e6290575b1640ddf717973ea415adaba8b153813b75650436647ef0ff65ad1cf44be1e7881f1b00
56	1	332	\\x13dfa221a589fbc6205619086dc0da979ef0c218bf230cf1e780b9805d18fa020cc7f3c587baba88e5c574fc390fff0bc44737c7ca04533f5b57d3db513a8a06
57	1	52	\\xcd471e4c49c6658556dd37de42547be446ca49390b6a759823202497b3189ea98e500ddb7ed2c1469fa1383217c48277e43ed7ad93e1d3b25c6a0d72a47d510a
58	1	416	\\x3b098f1d346b59f53c5a65986a4c0330cc14a96f429cf64a48f8078a3bfb98e47bdcb0f9f29432df27d5cdc7e4fa563b61eee01c0cc6c3b7d07b66aa07fdab02
59	1	71	\\x593b06396a43ba696fb90cbb062018ffbeb1a7e8b78cf35abcbb35c0ba47deefdfb011908912a28680554254ac49f7546157225ec7d3d26ffae6c55e030ea700
60	1	373	\\x5b1d66d6095222cdd7aba9cd3732bedd834a55964f2bcaa81eba5fe785ad48fc382f4f3ea9b5bf3c04beebb20009004ebd912ba2bd4a3cc23f8191173eadc402
61	1	153	\\x57cba6840cd5d2a33e7c2bf12ac2bd5e7406b90d8b3d82e7b72fb03a30e426d9c4442e7ea892966397ff2a2aa44eeb0d8d2bc18aed4d95be1618848d27a0420e
62	1	163	\\x56230a6e5357048c846828c1c4647edefe4a923a473e957477de092e5ef510e2433595d8036bb919a757947f6864406c78d8bac884f5e62fd6511cd262adbe01
63	1	53	\\x5d971e5f86664e73564cc0cfc4f5664e84457d59b0f47f30e039e2b366fa52620860fb1d16d09a6eb8db1f2af170add41afdb7ede04ce4f2e2c4f6ffa3f92506
64	1	89	\\x45d64fec9e08e791f6eb9fb4886361cea790c2622a5c287b4a5bba00e7cb2d1f1431ba3fbac87e4dfbee7540d3d6fc07453e0f56ad1b29319f4d1d3f8c8a5700
65	1	74	\\x5120b81ee47db33f44973818cf83ea4075cd93ca4cd6fb3dd21f121dcc5c10ec7bc1e9d0bfb4928edce466e7abc4eeb9aef3d19922d0cbab7b7ff42dd355bb0d
66	1	353	\\xa1aaeba1c66aaccf13df2ff395e8709f93caadc01d79dd25fc8d617184bc7a99c024b58549f0e66898d2b48395e94a5b87255e1ffa24e84b87d7b781c0632800
67	1	24	\\xf5e6dcbe5f8a31aa2002d818d3f68b6d3e660a6668ea290c645d037c7c3aa2f0c2fafbe57fc19077a4a2747e1d5c26c2c7a051e3e8b7a010db43be0a06da0505
68	1	185	\\xd39378a33ed8060b5cf097492c821408c297fe561a933fa966830eac2bfc6326e5bf9740f1fddaf60ff9364ebd790f52a699e2beaebff57af7be0878b54ccf0b
69	1	342	\\x1cc6ba6a41acb5e2381bb030ad31661527b45f9e85ef40141d8f70ef23b73a40a795c1148e842b3b99320c20e9ded638aaeaa6891892f55d2b7bcfb566c4a607
70	1	50	\\x9bc43f4bab2e1dc7b5adcc015f56519a57b4c9ceefaf45a9bfa8d1250b75d7de5d829764d94b8431e27642086fd8840c8b8f2fd34246ad35e68ef24b58f2a906
71	1	66	\\x46dd0782ce85d25a4afd88ae0a3f68a5cf25b68e942c810d434f87108c421cea7bba504dfee47252b14a4be6728bf4adfc41c521e16f6cacd7da43484b735b0e
72	1	30	\\xa06c869d2dbe56ea123b31e8f6279a82b9ab0c5acabf39ed513d2fb822dd2d81c35b6dcb9a8025afa691fca53b1577e4367815e08b549a3f390ebad38171a207
73	1	364	\\x9d8573f27a5929875e7eb340af84298917ae3081ff7214253cf658d0b1ff43f18d555da5c9b43ccd9c092f837b6b3b5c5b1acde4e380f7b625a962c56116ac0f
74	1	399	\\xddb98cd83d9c614537e59a93fd6df3241fe62ab3cb253381fba45ac459a14961f5a184a370d54dea7a43974bf473e22705d9080a7a54cb5b2ef526f090bba60f
75	1	85	\\x9d72b94769c251a02f6fbde91e8250c30777660f5f61369daef1599b239f3e2653187b85fa91e086a187b5edf5be4b28627a55f5e2ab29dca76fc37c99c50e09
76	1	385	\\x635154c7b41057b3100fb16ca1e7be679527efbba49f021a288935e6d628c9cd5c287c0626a16550361f60a310d951b45221fad0be3f2b393a1c426debf99d05
77	1	260	\\xa7f32981140b56b6f84e551a49282384693bad9831c492cc8081504e5bbd9eb409aa6d01f17424a651d7598dda969073dc1ea3a7214fe964681502fda2bd2e07
78	1	172	\\x0e8d44fd5342d9ae319de60b64903d598a8d3a2c301ae3b57ab8196c363b33527a39ae65a25f9525f6ceedbb26c666dac8d2bcb02a8380f5444c166ad1cc7e0e
79	1	101	\\x46323d8936ecab0666abd7a4cd56e9453d425555cf400418a98a95e84bee237e0920f979e6646db96b95c581314d1e76ea51401316491ca3f1ffdd548ddd7002
80	1	225	\\x6e38ff53c18125f0aadc982000184612d7297aa2658157d36d584fa9ddc17492c400784c444f24d5d95275985af26b830ecb09d6bbc605096cacbf622bccc504
81	1	211	\\x37e7994eb165436bd03addf198b25e6830a8b686114803241f19988b3ce7d869fc5a8e3fdb233e5c857e075adbce91a1aea32c3b7632b4272858613e0905c40e
82	1	54	\\xd0cdadd70b3d68e80d67bfce9255c4b0a3dfa4028ffd82fb748ce65b5fdcc495e6f5c81ad9864459462630beaa8ad1feda4a625b250a2b55496cbc3b310c790f
83	1	200	\\xc0b6515b30807ad9b6bcd3fe8637f11723201b72090490fcbfae3b2d4bf25969654ba4db6453d7033130dbee1ce554d1836449019e70e80e4cf0385351d30e0c
84	1	122	\\x53cf84b60765a81e8754aea39caf97e4986be59e76a56afebff5f06a95ba60a702085f0c850b0bf249f4501b4459f81b5eda5deb2bf0b668488b96761481e803
85	1	327	\\x6e0a53a91acc8fda91946614dd63d4aaf0aa111b64e6fadaee097d1aae2005e675be11e854dad41fa315e2c3e9fee56c1864e0a1d871732b6a6caf6ccb500309
86	1	79	\\xdd03bdb23089d9da37c0e02cc081d3d31e049849b708c796d7f8b20d618459e54194431beeca1ff5351dfb3c177f05dc1b8d5a11e2ad2fb8d90ae0ca393dd70c
87	1	195	\\xe14680c91f825c8aab97f0c8c36ec89a5831e94241950c9cf8df7094e9b8d227d6aacc52a741f13ed7dd83b209c61b8f2b9d3eeefb0fdcf87ab163dc71c90009
88	1	226	\\x561f3b002c7a8a2c5bad4dbffd31746c2fc1d9affbd833bcc952ed0ed1278c41696ada577af7e069faee24cfda01a5f8642db3257b517f72a3d94aca4e50f00f
89	1	169	\\x43b66f8c4133102150ce3d1a719c20403c18aeb79ee16810b264ced218fb8aeb6bec9a62190e33d36f6960f90eb0498edc63d800a2c7ac8a2eef36b1f13d4a08
90	1	117	\\xb2b4c69dcf3c66a1a7ef7337d0b3bf7e86fc58f9f24c3da2190cbb790bd86b5ab8f1592a4af109211d32c4f2c75ac32d803284d26b592597d8cedb0bcbd9eb06
91	1	341	\\xb69ca1173ab063991b3a97cd29b954d13d2984cc957870580bf6cafcf8162ceac8b88c0f4fe5e767084fbaddb6244ed27d2a152c628ec3cd9464abc2f5a0a20b
92	1	423	\\xed57edae62dc3a299963aa4b6960fb87c4e9e7a5e6df3fc13f610f3d76bccf4f496613770c5cffeb719d05b9caaa1769f740f74582ef8ac35dd47236fc69ee07
93	1	219	\\x737ab08631d9b34ef14871515329506d42d4af2cef0a6175fc5c9b4bcde96c7cf7838913b890c7575c310822e30c00e9a9bd011739d39190a6c0a9efddb60400
94	1	244	\\x73634b81e176b77d70a67be69f4d45064cda620c1da026646968d6577ca95473a72b9075024940724a210c1df3fe15f5587d9908ae272cb23eb167f7e408d504
95	1	104	\\x4ca3effbcae3cd0c77eff0afd1552776cceb36c5ef2ac1aafb871e7fff199c97c9974876422f2934517432ec442ed1a767f7fc3bff9fb33043cec738cd536d04
96	1	86	\\x214f6f9f96e165af8803fccd56f6e2329f2bd1b6baf300b86d98af98a7ae2f5365bc91c0d129e98401452fef4217c641fcc08f6b70df915dab84e99036e1f50f
97	1	167	\\xaa23c2b403cfebc1348d575c89f921814eaf34f7e8d629cd6dc9925a571733401f0601080dcdab79397f2933d178ca6729c1b2c1a9d0cca416af35eaed4ea90f
98	1	309	\\x609aa74b228d18c732657af8b85652d0f902771bea298f536254836101d659bbf969aba04e7a3e7143492c16966495aa671d3394d139b0ea39b086a808e0850a
99	1	16	\\xa16db22a43b4e7815bfe2dd3bad2b01718af3db0096cce82cd70b5bad0855ebfd96850c82e806b0c29c2cc49bacbed3e2d2b4b7367e08867b4a0cca92ea93c0e
100	1	150	\\xb7337cfb7370fa676c76301eaf952d74a30e0fdfe81ca9162a8c00bc13d4f999f93d7235df7819112e4237ee3967bbdcda1aac9e002ac70536bec45e833b340e
101	1	359	\\xf931588292e70f5599e6326bf33adebfabe63a719349a4012e759de82e0db065d8822d023f6699693ac9cf2692225c17409c9706dcfe4677e34f296162404d04
102	1	72	\\xa749155911ecae1367293fd16840826c84dcb82eb9ad7bf527a67bea058789b7837703672e5c16e4c17a01798a9de72162a49786bf03cf3de1a79ac21652450b
103	1	49	\\x0ccd7cf3a98501c88c609fe6a780c048d976ed40656a12028174656a357e24844980ad3d54898511fabd8985747044e463501cc7352f94f8dbcd9860170eef0c
104	1	281	\\xcfbb6118e55eed796c4cb6ae63eb1d2d6f8c185200b4299d03c52cc0490f17ef99430f1cabb7e5246c893d2d23e46808f04d6f6fc98e6ce56a106e0a01127807
105	1	2	\\xb66a9b06f85b6e46b828bdd485cee98347048da63e2636b5baaf3a6e3e163a93ca4cbbc92db47f7ebb7cfaae1d315fd762b415822ddda60bb66b814c3ac0780d
106	1	5	\\x42bcea7da19252ef7be76e2a23381e936654dbb91d96a301ba31f5d79244c1c03691f1cb92220ad6ae3644bb51f4bab57f3ec9aab9b2f1d3b2e76bc0a6c9920e
107	1	231	\\xb4df160b6105ba575eceb3c297332d52e63a2092f151992ff5cb320e4502bef128ee58df5ba429ac1c885e818b87a547f452fcccdc0f24f9231093c1e2443b06
108	1	142	\\xee558a14d48ef11d7db6742b92c6f11ef6914690a17303f69fbcfd2342765a60b3b38f301317871985a40bb66701f1f6a0e1a795b6c64ad81208085695157d0e
109	1	83	\\x26542c789350350ef0952e21cb7bf6a97295f3d4116329750289d0f6d4fe976c70f22150c251433ec13cbedbd371fc1e0df1ac3862623579a76de11645cbdd05
110	1	311	\\xd724231233533efb7b01aef49363b7c9f5c7f5f1a66dcf6a9c727761124f70b3907c5e0c61fb262e92e66cc64d15f2386d9ab21b1ca5366efe8b06d49ce8f004
111	1	407	\\x43bfec64f57b86e4ddc6efdab6d228e749fa50f7eb682f024bfc076b034a5116795afd1f05f99868231ec35a5253f0447e5927434557161cfb8a9c53b5977304
112	1	410	\\x9a72db1b1173c632dc1480edac552bba55e7cc1c7d46cf323bcc5413aabd50b58e4af940a5a82b51d976ae15a67c58f77a450e53b20d026adbe2454f0d5b0201
113	1	149	\\x621f1931cf06ad5c227c0ae8c7c02138b0a3547be3541e5a7473c827ee49403275c1528d6994045664f80feed96f57fbb1f3dbe8eedfc6a3e6633cff3525d20a
114	1	296	\\x0de29d596a2dc67dd3cbc8f64ab30fc15c215414658d327218d8def30b8f20922959901055d4e98b87087981b80c2fd0d613efef6037ceee78c06b1fbeec730b
115	1	58	\\x8f3676a679aff4e0a27f729a917e5916fd8abe0df789dd93d0574a1ea020cc6da03143ac48d41eba11acefc38ce0ef1fb77436322be501f21778c5658a1fce00
116	1	355	\\x3efbd9541496028f58a709d1880b5677cb5d0fdbd3e5f2d5a0cd070854ca83134c437b53b7c38f5d0961eae24dfcabc1caa4abd49e5013a5742dc0dd6cdc5309
117	1	351	\\xff139c839384552911ed2faec23372d8c546107a3833db79698eeaff890fa53fda1f98b856b52bc057c529129aae355b78bfebdc3e56e7bda1beb9186ce88a0d
118	1	80	\\x85daab785b66698d08d417cd27c09bcdb3f193f99195927e70401acd4218f2ba9a0df7e36535252d4aca660078be5c91723824faa96202ae97ef2569aeeca505
119	1	222	\\x168840b52c8639e2cf0d6090394f34423dc49f52a4560138949ffec290699e74443d7bd677863c21d6d491c2ede4fb40b0e0f6c5bf9b80e7cf8b4747fae6f40b
120	1	347	\\xcaf08ee861c817a649ec4fa635c140483553d6ccd5207aa98248ae62e0388baad4134770e80979ded3c2a584ecccf28da405159ff5e918ad2b7382e9d32d570d
121	1	249	\\x75532c2571de2f27ea2c6a7de51c24818fea333f9e48353780ac771bf608b9e82c79fad71e5e410b05ccfb6eb648b511ca673bf5b63bdcdef51091d319e4660f
122	1	284	\\x0ca010e872eb379794b1262f7b2ef303f477ef6371316dcfcdc1621d4bb8b6dd1a433fa563c7c600a1d6fd4683aee512fec7d2102eea8b353c122d7419139709
123	1	286	\\x9670f062b0a3d5c5cf1ec9e7511b0d573a5f113468784853bf15b0e60402e7e6ea80b56e96879e504e8580b7d68e9e99929f20d19191618c14af06beb6ba8606
124	1	420	\\xce4ea0dcceccbdde9f05a7c3da54a410a6379f6137b173a90340fb958e4ca5b76d2a517ff92d7f589e5983e1cb2ae88f641f274d15a9e8b293ebcff7f12ffc0a
125	1	320	\\x1367df878f16df5265dd2820b60babdb712131de336bb0befda4b0950794a4b39dd5a0610d81431c98461687bd3ea78c3ab4f137a656f278fdace116e1df0608
126	1	250	\\xc426f0195b8aa30c793f9bf8dde1edc8081cb69ae825db8b424eb144113959dbc0bf30a2c511c5ba8de4d864cf15d77d8ec37a323229ff6bacff467a4e16190f
127	1	277	\\xc7e403382718076143a1b3d292a248b49c5271dd4dc3deddaf05f7ea9ed6eb1902193aed67ed0fa6f4b4024a029814c2f813d638ddcc2d04c14e5293edac1e0c
128	1	155	\\xfb3c391673aadeb1d8b6f020937a8ef6ac9704d6169b2b826a69e26a4883148d7e207cb126930fe6896f74143fcb93b2d1cd58549872c762df900c3c8a6b0d02
129	1	228	\\xa71ce1c39260b3affe3e7ecc2629c30311c27a10f1a7e265d6273450defbb7650724657637fcb6d7504a5c2ba2041dbee55d931436a5b618029289821b5a8504
130	1	99	\\xceb82c2a023875b47519e0b870673beb2b8c34f0bb814465401356f461cc128afca2b73c6a67f0ec6088f9e714e35f0866b8650a50231b77fe6099654000620e
131	1	238	\\x58195e59392facfbfe3d7c698972a8fa362dd25e85d4a1fb768c3111bb4e90e71bc5a183068a1f62e5e503a86117d61548b143c86f8615652a0b7a3543104602
132	1	7	\\x2203f39731a3c9236e03209595eea7f6d464d4082b4c588abf7f85acfbcd3ca543f1aa3b0fb6b444cf890d62c354a8dc2e19246482ccdcc46a006c76ccb14b00
133	1	161	\\xb49e78c4f37a82e94da2cc5dfc713e44c937443ab93037377242143b3acca5e4d2b9178d05e8be49ae3e58b1fc2e339981c112c4c5feea4b664474033483da04
134	1	181	\\x71193500ffd275f4fd6b0417544adb6e37e3d74390ff00a295e74f9c35a6fbad44a6e9e5bc4dafd44b08a40f0361ed59d7555974a38f36a4e9c77c6a60df480e
135	1	314	\\x191dfa87a1d0bb304b3a735af27ab31e6fcdb59ed130115b9aa27966695c9db4ab3c33fd0a1db6b0341a6bbeea6c6aac3dce907bf7e5b2fa37ee35fd72a9c205
136	1	136	\\x88b55b8410d235eb55b71f7bcdeba324c967cdbcd949ae2f91e1cba59ee4970f4b4659b39b8ace8153b0e6aa6002fe0eaa54df4a0c5a65958b31471dec12d905
137	1	247	\\x1bdac75ba0409bf1bcce1838a1a848b155173d6b97df0c0799b88431058b22ec98dd28cb1908d3efdde0c21aa103dce07a153e8d386328ab3d1914fdc38b740f
138	1	131	\\x8670cf5c4b3bb2d0a529b830cb3392322763ba1f5073b8227db65a6b1a76dcde70084d6d38aaccc229d4f45a109bf086151c6ec58c29473de2fe162a1fdaa405
139	1	370	\\x9485a6eba25ae92cc34c219ede33f923699f64409fa20fa25f785c69e0ca37a845be6b9081f04be5d3986bb5cb363fc04290b758f1d19b612d236b5bfe222206
140	1	324	\\x7911e6b47ac43d174bfc812b27553e72d71c75e5d349009ee6fda5c252aabe089960321b365c4f3a938ff128e9f6972b120695810d516e89636c4e4461ed5f02
141	1	179	\\xcc221b001d5d79e6c2c47ac933a4b2b6306a3c910cede34831a3b44260a1cd4844688a13af15df31ceb54e2c779c758b0244f4ba06fe1b169717625db9dfad01
142	1	288	\\x3c92ea594c0b204d3600817b1a4cb21eecaf39d51a57da49c10d49276eeb445c026589e2ffc512aca1f8c5bf17d68dbb3af6ea68abb2b485568ae2376f35340a
143	1	395	\\xf3ef4a654cb88b7d47f3a2d7df5299c8f973b3a11e178349fbf5e72a67845bcdf4a92a65d83392262db098f7fbe8f288898c821f0a9ec5384dd4a0e420d1b904
144	1	73	\\xc8a403ac79e20c3e26a5a724ba379df5912fd0fdbe718950ad3615b264db7007fb5cc3541292e8134bef23865a36d15eada222618f7546a3445bbdca431a3608
145	1	344	\\x159b796c992ad025bbb8434db9bf2dc4a14b39fc7d1d04fd5f882478365dc7d724a3ed0e8c42bd2142c741ae87b7ed5b0700e0796d73e78e0db30633b0ac6206
146	1	212	\\x809277a2b58b72e8f6abd41813078616244913c6e5ad1c9fd38edd37f8543db6a12f4e3e144d1169842da5a895ceeeaa0b51e13569c895dd3829600d4bf2880c
147	1	69	\\xf1864125bc7d12834fc9d45dfa145a857710aa3bf6f177c3208b30e3fc0b52fe4a906fbbe48964f44f8096f8118f4292d24dad6468fb1359237cea10e7f25501
148	1	175	\\xa926b1855fbea9c1dca3ae43d9c0e9e9277bfd5d5818b08db5aed80ab9e81a787b868f1ee7c127cd13419b8ffc11abd32421fdc956a67b3842f5bfe40684f90b
149	1	315	\\x1d21ea0f550ff62247bfa2db635222d6e2c09578baaf9bf59970517d3f9611ab638ca967ea8508fe6fa15d69190d1eccd2ed6c993ef37e5c2d242599ccdcc908
150	1	298	\\x36932376d1c0b22eb2d2df0f3bfa4d97ac952304309766c90fb30137007214abedb7698e29f939a933a9109d043acf33823929959d4abb3ade5340af87838501
151	1	300	\\x8d56195621f5ee4751eaf72d730dea8326a6440d36de94c4cc682b47298046ab087dabd506191c67db224095db5520523a0f0738626321745e0c167dd0937c09
152	1	303	\\x7184a01d6631c937bc7c360913a2372a6e20a8bf9d40d49ef58d06cf2ec461220e85ddedfe5b2fd298538d4a00eaa4eb66c5a822bca6bc36caa7009346c7ad04
153	1	203	\\xa289250bb8ef962ca7557ba1b8402e639f6b90d18b7c50b1457dd14ed309f2134aa008dc18ca878d9c74c510da635dda9a1626d96adec898a901d66772244d08
154	1	241	\\xe76a97ef11d25922587edafa9971d650b78d1af252e176a17698861029be72e7cb44cd94a441921ce8d3a9b0382199d6e61afdc926efca856e59c4f55c31b10b
155	1	39	\\xab28c8e644409d1cf9ebb15f8fc114041b174d1f0746eb8c776388a5e39b665f64e065b53f39c5e8052f73fb0635c0542224d99ed42d3ebd0857feb51e50110a
156	1	270	\\x8cb9b273a28a2ae7c00eb509f1ab9299e6a0470278cc6890ed396d0f4b60b26410b6ce643d7cc3121089a6b235af40ed6188e2ac76ed4fec1670b7e84b9ad30d
157	1	378	\\xdf2577c10ee60d69a6fd58c18259f4d74138ed114fda9d5561161143687f59dfaa1e533ac29d0f1da3fa5efc6c38132ab0b7981def8876782c6aab9af193900c
158	1	383	\\x4da49ce5aca035d969a0b472276e04835753bcae11b6b3c35952b31217bfa75d1ab588c1e3a972ac4ee6f8fda47e9c63690cdd42f99577e9bcdec5fc1cdf410a
159	1	273	\\xb163f80e7c9f04776ccaf34ec5a7c4e8b92952de30900300090266d894ccb3fa2c59433d921c4b3136837388dde32550a8d875868b1d544c5144827b802df201
160	1	141	\\x123a7495b7f73e4dd93e06631618416e2fa5d105cbe7828acd8ad7809e36d484eb7a1aa02827e5df78eb0e0219db66989354757ac363e56ef23ce027b1587109
161	1	408	\\xd176c6df475bae2a3c961d542dd6e6bf505cb763d75a0899050c03ddcb50756ff2920fe1dfd7320295e5574ff73378ab7f8d689d3f18fb44ec1ad47ba3c7fa0f
162	1	272	\\x657f985b3b62be6fd247168fd28678c58041b5cf4916d8cda6c8535e8c0f4c89c9963b377ef732d4f5c3baf568c1336f67c513db82b0ab0a24c80489f1afc305
163	1	271	\\x94672250e363c35c20bdda6545554dabf02e8d37fb7da6d010fd6f2b80f8183d33407d9ee361bbd837fa688fee1fc592c66f14e4ee2c6c29cfbbc25f9723d001
164	1	229	\\xaec1639fe4ef372ceda92eedd8115fbf0902ba3dc7631fd7d0d6c1bbfc39cbf08855c40ba9a9d95255f312c2e2fe09865fbbbfe1441694af274593849fe5040b
165	1	239	\\x9a92864d11d1356fb1f6a71f7037ce856aa1c75ba799813f90324fbc998a7881003b8e6b5fd1327d74c3475204d853bd67331cc84f0eaff95c0044937dd9c709
166	1	57	\\xe8279886fdad2f04d93f4883f3e69a7049d0844a60eba4d8cbb0c551524b470b85a6299fef55c292d96ab6956f99a4244bd19e7b2b95c6907c70ec61b6409f0c
167	1	94	\\x725db14eaabf89d3d40922bfa617047a42af1913c6b67bb4df9abb6e9f134c378f1729f4693dea0d6cbaf0db2bfd00157ebb3966096894156517caaf62f4db0a
168	1	102	\\x839fa1e9c67e87694800eca29cea65d86765fea168a9285fe42dc8a31d7816de518306257cc1f5eb4e393110c29baf33034e6f3b141a49a348f8bb7c8ecd0309
169	1	170	\\x8f4de9ec01940aa304cecf127c9c2edf293a4c5236bf1704496793707c3bd2967f6f82ddf8d32ca02e192df66159b893ad177bb603144de2c4a8601b0d101c01
170	1	6	\\x30e07bc3b7bd16bf0e380754570b9c9c7b43826a08c2be87d7677e44931092872d7ea244e8a5dbdf286075e4c3d3d0ab9e78deec231ef39193bb44cd3959c501
171	1	42	\\xf81812cf43fe624efa98530ccc5d4fca299f5613cf3b45af87e8798de4ab0a60a882b1c1e7548477a69c1d47af5b0a1760e2d99575066a61a2984528d1eaa206
172	1	109	\\x0b35cb348f6103ad1a947e9cb707bda1e5778ab2cc0329deeae9fd038b5c44969346dc5a8f8c2c60df5c7d0a509d73e408a2e35894b9358636ec33dca1a67200
173	1	192	\\x53a946b2a9ab57f7cac46cc7db39d014f6d1adcf44860afce85222b8bad2645f991d79be594c6306d91f81c9f7f5fcc75ecf225f9a7858d6f3872420ab5c9708
174	1	4	\\x06849a5232622997d0e0ebc63f18eef870acbd305c025f031ee052c9104936fcb0bcb84bdfcfbb1314d4eafe05f73f64ad9a9caa3b7a45b3ed095f6fa107c103
175	1	129	\\xef91f01b78876b72094ba06e786adfaf2d148e8a777e98ab44551757fcb87a92b4bdacb3443d42591d0fde3d19b4df870460ac9d86c9882605372112eea37e0e
176	1	305	\\xf2f4c6396228a2dbf1f4a6eed01af07ce501bf1f31ba7a72e02b7f76cd81aaee78958610c467c8e680ddc0cba227d3b09da27a1b6acc282360b6fc14cb7eff0b
177	1	133	\\xccb7df5a2dc7b4055c81a1e6ee12f91ea92533730783af98b07b3a4556eebf804a08c7fe3b4971b867254261105f86aeb1c21a3935411d3e6a41ed7ee6da9003
178	1	59	\\x540aca17050fcb1a74f299739e03404a4cc34026c3b6163b246fb765d5004afcb86576d3d1b21c58857c53955391ab4ea4b27a209996b28947c4788fc0c82b04
179	1	310	\\x160dcc0658e1d0d1106f0e312d40a0285d7308f74a13956afb7c1501339c091b9c4f279f7d55a0f958a07e61314ed527256cea00a9867d01f2dfc92e726dc307
180	1	406	\\x5fc7be532317f9be346652c42735cf7f7ce5263324901c175738c9ac3eddaa4ae97652f80adf18cc58c8e5a8e1a9aa2a5ca7fba6fa8877df8ac47ba9c9f7ff0b
181	1	266	\\xb2ec3b43370951f742f1cdd3694451dfc4715de1fe4771cf39e009ccf1e1c53c372a34062b71f8123c3b235263a94ba2a467eb705c2591c32888b07c7db5c008
182	1	12	\\x99e47e057824a9dc2128ff70e012f2b810e72b3fc9e3338bbe31b2b3c3734cfd9dddb61f40b8817a1a5ed8ac04cfce5b54bf738794d5ebaf1ea100a4583fb601
183	1	107	\\x1d724af9165c5f86e9c6b2ff5e44671dbc6f3621680d6c3d01f6d360f2697d571e5bd9d2bd60f880720cdc8721d9a8b4f74d3fde1330519c35dad4976a2e3206
184	1	417	\\x01c6009147a711e2e2db74bc9706496b1615d3fc65d0975a2c0d50c33254ee3f58e3f0b8a41858304918a380b8abf7f16717da966dfa105dbb36c70332ace909
185	1	159	\\xb25874f6f717dd45b3181bec28b836bfc2090a53332bc80084b8ef47086a95862286c07c76f30dfef97c4614437efed15bad18fa6486ce3b58cd7d342605fa06
186	1	87	\\x620a8f5c5464999e878d93b3b26697b396493a9a92e20fbcb0a387cf08c36ccbef08ac3450928dd3e9da2bf1b8303ab09f74feed1b0b9810ec2067c6ef6b2705
187	1	246	\\x7d46b0bcadd5fd64d31a04528367cca6fde64de8c38c244500b2ed293e7cd02a5128fe3f1f0ac2a9b4c924f7463dcf7251f79fff3426944852a77f6fd2404d04
188	1	115	\\x05fcf0e090eedf39e6dda17ac0075c235998c13b27a003e9c6fa45229db66f765272a8730e0d6656847d7e1de3b4b9914a9e620fdb827668f6689410d32fcb0a
189	1	96	\\xf38e8aa18ca335770345f2ab79bb8a37daa1610ff28efdd2f847389cd660ecf50c105637e845f9d115d97f263f79f7e4713d6b9a3e9d4a2cf4012017c7c18003
190	1	313	\\x5ecc1f6f01efe5bc8f7c6d619d81f17b3db1e6a6b1e106ca51f6e1d38839a1d3c444cdc44b1c54bec475466e4cddfbde9519e065b764a841898432e162d04b08
191	1	390	\\x83d6c127af7a6542e6a1eceb632b7db669c658d0e321d22f2558f18292712e43632d3d8fa42e37fbaabc57bc3286dac7202090a6d49167a99439574a8afc740c
192	1	130	\\xd1228a9a9fe4f7bdccbc49663f64a7e2386d845ef33e0290871ea136555226eab90a35095dfd762bbfc592daa95e5182ea8ec91a4d51f6db7799a6945acfbb01
193	1	126	\\xe3342f51e58fb911bd21b757fd23bfe1ebd6885b5eb4c86dbcab4a44ffb871ee1a472f4f083cba995c942289e30970cd63769e65aa08125d2d43d801b6256a02
194	1	369	\\x03ba5a814e82a932058662cd09d0cb3562388966a997b9d98a1d867a0bba2712ab68aedd0190aa7aa6e920163b1594003e312331dee75880a4daf47490fb6507
195	1	240	\\x5e997b1c43b432586115eda00cbfd702d4cb346e2e4dab0dbc3c95a939228bd338e9519a3a5bbeabab31175c63df667dcde84b891fa3aa4dde6de9470265000d
196	1	90	\\x818f1ed04e736b53e75a178d384298c881200a1333c0420067f60f768a3bb50c160e159a94faa8ede7939da16d4943299d86ac5703419533ffde9938d94df70f
197	1	389	\\xc23026e8e3049ac12fa368ab6c2902d109c64a9bc5d361ca40af36600c2f4b08d89951c7bc4c0c878e0ac4998da4abb39caa664e3cc309772b5cab0beaae8d01
198	1	400	\\xd3a36880c78c562f348a9c127cdbee21c50f787d761eadadb53b1777b70c9bd05ad84f269f2270cdc34f979480c50e20c95ffc55892dfb09b107eb1f59a1ee01
199	1	255	\\x94d920c56c061e183c280a87a4867096838770eff469d56e8f0d89eef97be66e6b7aa2b1e4abd39cf89ea9ebf6e044dbf657ef9723394265ab5376928b04b20c
200	1	322	\\xdecebb7567c7833fc3a2cacdc78935434aeaf4b40c24671eadb0d2302c611daeb095d841ea08c5e3b4926af64785fb3d8b498a5752ce2a049a2ca118deb6780e
201	1	319	\\x4c662c84e7bfce7b207df43ea94cca4386363a10fd5a08b9cb344a10ce15ea726927a72dbe9188be47957d74495e90c6c3beaf6e4b98fe70e91aad5a67958a03
202	1	143	\\xe6644a45d77fc2ae37d34081464154207e89b82e2ebc8d31cc1c0903abc50725c33a4205c80b235af17f981e5f319b8fcb5e8192e49c0037fa6d74c6486e5d01
203	1	307	\\x751e21fd5e281e28dc12263682eba9e80a647c170d7b02feb27eff3d7c84e946266cd17daaf3b2b19c54d080e3d7fccd0000eb3b7634e17669f746dd360cc50b
204	1	60	\\xa3be50a3a074557be873a6af6e646d553f682dba582c7ea9de88c6b7f1be79f2350c02b0c979adf522c36d135b1f0d0412986004689ef045e699db35bfbe1606
205	1	321	\\x896b8550f1605443ec355bef0ef880b1553d76f598432dfa8bc15b12869ac6a9e678f28a690b5e202894a79edb4a01b714449fe8fadfcff9cceaf7da53449c04
206	1	291	\\xe8b23cab1bb7cb541cc21cf8631e3de55ab83a3bda43779a25333556baf58c1168ad362e647c0ad41f7fca56179d22f9d5aa919cb8b410402340b506c6644d0b
207	1	127	\\x750ee5fc36aec8bba3af9fe1e7034c8cfd571d1db44ebfa2598a3574307bf7ee04f6d582319462be1e2828067aa08c2f504cc553de18a098e00d3173d9ac0e08
208	1	17	\\x5b2435ee5cd7d8de8c36b4c81961c31efccef2ccf4829ddba660b3ba49be87965052a6997fc5cc4d477c81325ff686268c368285b874afd7f0db71483aa8d60f
209	1	138	\\x472dc8038d00075632160c959aaf057173c14fa234eae471e010c1594c813ec0ffcc204b64ed0bd83824550e066a4bda58298365d9ef88c5b3f653ef62566003
210	1	152	\\x0224f65b46fb690a8b693c37b471a652fb77acf2c2bf7920b6c11cfc98d49c83e187fcf2f2d3aa636d36a8cb5621bb07ac64fb60a9c89dd78fefcf06dbbb0a06
211	1	325	\\xc7a90f187df9b2830f20a9f2134424de133563ba18e26b911e9352c167e3423d97886d59f325dc912dfb2ec0b99d2413013c6aeacda38bd9c8bed0038dd13a04
212	1	140	\\x7e72f32ef9df1222522cac95934332f92822c1eed9795ea338f1f75003cf3e272e12c24033b9398d0814fa8c8874a388c826eef16e86b993401c617ede162509
213	1	31	\\xabbcc159f592c163460df2c9f51850def0442ce0bc8db4f3b1360fa9e6e50dd040bfe42676ce2b827aeeb78a6d8437726ee09efaa24cf0915c5d9ad8b3285e09
214	1	197	\\xba1b5409abe1d8d1389e6295473f6816edd8dd8601ecc96f963edb84a200ef2eac773b109b6550347c12b7b61da79199996b73f953bb8e6553a27cb98445be0c
215	1	409	\\x88adb2ea0e02c479dc73415d6a665db42088fbcf1db77f5e98836f12a661c91db75f1acbcbc9b8043bc1d2fcbb9679b3e44673b10be91746ea3f21d512789209
216	1	412	\\x84824b3e3019d4855464ae7649e9bc61b6e292d2fa625c315424c7c1fc1b023562e7812a8a26af923fc5240cc1dad0fd87185636c79679193044697aa61de004
217	1	65	\\xdacc947e17e8dd0a485234cb2a62f2c7ce5fd9bb4eea2a13ff7a852af867ddda6b01b75414d37b585c540b9a7ebd9c8bad6fc1a4ca8d14be97754b7a522d4006
218	1	147	\\xa42efe7e2bb10541fdc8e17c4afda4b31435e63d6a69ab0feaae644c0e3f7f85b8ec78b29d84e117caee4a52645b25931959e72c59a31029d3277258d090800c
219	1	78	\\xb1aaca26a72eda44ba63b6e6c706a6fa973db4e2092f789f262e8690c2ea0a6ed805922f05cc5e3e6c4f1e6ac8c0e93c4be2ac562801ab51dc933b55497fc60e
220	1	14	\\x46e2fc48cd5657f91f14d6d43f82e9932026c0f9229a60af48e28f7729a7dd87dc2ff71c365f0dc1a2f4b73725ef9728635c058a53b12b143a8bf4d02050750c
221	1	67	\\x7a41fea491af6c58eddceb58bfde7224fdfe089e3d7ec3c87ef4290ccbb2ffb9df504f850aec654d1e7a967b98e41ebbea83b3385ca118e6d0e53062e3b03a0c
222	1	33	\\xed53cb4869668291b1d638988bb85c8a509fbc52a6fbae6c831cc62cec3fc55543b0ed266d5ea4d6ec4b081226cb0769bf28ddd5d1e4265174e1f37bca395406
223	1	254	\\x1de2c13c4a9b15c908f13eff6cf7b401d69fa6db3d887aa90dbec76a7963acf27b43305ff2f28ee78e3b0b31081fcc0420015a78b5ec3a62f645907121f2300b
224	1	227	\\xdd7a0ba88dbc83839dd8af0c001842daef74c28765b879e674d9a5c576fa4b0ae7bbb742b6e48c3b20640e45ebd42d5113263a6f10eed4213bbaff102d81ec02
225	1	361	\\x6f0d4ed9075b4463615b1443a6cfcffafd3eb314a13be92879044d019280b0990a54f1b3d1116e385851fd286755f5699abe80bbda105dae640c9262a4c7900c
226	1	206	\\x7278b64bf297093df4e71877f32d20cc08ddf20da2895b17827b3f1ddfd015233da490d03b0fc0555f19288154696805116470e32d02a52bafbc6c84de556e01
227	1	293	\\x4cf474e98eabf9a88db7d4087c0d9a6f9b335d455dbcd4814c0c3f7d90e615ad7b3aa03c6bcff659704203a62847cee15e671b784353f483e6f9c841ba62d60b
228	1	84	\\x04b7f5f1f2fceab5b733c75c0ed15080cd7273951fa8978e4093ab79a437a9d000ff77175c74cd87d2e19ed7d196a36b4c267d748f5c7f687bd0f9f741d6010c
229	1	396	\\xf3ec028db008d500726b7c6fa24da277de7546cc163826dd371ca858dc0b6d28cf31623278ce4b62f3faf4f9f2c48cb676692ca8ff8a9967310a43f2d59a4500
230	1	317	\\x7d7bae62a5b1c869252d322f3546dc98eda32a88f956302e9b220463e6548952ac5d8007f5f505280d53a32b9be1feb034e61eb283d64f377367ad189fa06f04
231	1	404	\\x7d2c15ce7a2fd14d3d7ba395652c19190ecd9c303bd5f4f7857f345e88299811cb2315d4e218a19af041b869a1e196a89de3dae18f49943153d3b2296dd4fd09
232	1	223	\\xbfa301a330421878bab2e386fb7b91fb26de3115157581ec1d65bfd93682796ec25cbdee55d50a095e58fd9b8acc2c756820168095537337ee8f7e3a4937f707
233	1	280	\\x834c3c879aeddc848ff17f293c3dfade1fe22cae10d4d9db0137688537cf5e48cf337c269214abbcde99abdfebd37a5a94d21f613d2450c874fa1c25aad1eb06
234	1	202	\\x6efd96923bf10bcf272aebb80934972abdfae1e8bfdfbc9b1f8fd55ee08175ac67ec4d2d0ee520f690d27d4a7ca540d228d197f873b9b3708655b2f41f8b290e
235	1	93	\\x5a5c8ad5c4d13be28cd40464569a48d4b3624833e5dd61a05009869257ec87fd86217610ec2ac5587bd604562e27b62d6cec364d662c09ef5786f9a2699b650a
236	1	187	\\x856eccaa986d07b47c16430edafa4b340d68fafe19e4d295bc3a65bec0d043965175948dc165fe6de0a04d35cd27b1a4f397a4891ec34eff0a4ab0d5e0584a06
237	1	214	\\x466067a5a54b43797a7046010db7f190945f41e93cf3a5bf3447cac4354ddaf8d1e76c2081c6d3089362cc4a3ec6366dd7d607c1196a1593ff36567630ace809
238	1	308	\\x0b68e696ff033a3957ada83d12cd4491fbd2be043dc1ae666d74012e5fe89ff0fc446b95632ef9fac63e744ab9b26c8a0db46ec65817c949ad4d45791877ec06
239	1	82	\\xedef4511f1fa6fbf0fdecc1ce3d9049be5f1c7fbb670f51e6e4c483eaf176def8ebfa318ca4de18c10bedc09c564ed0427fa3b108d937fa6897dc6784ec9f00e
240	1	116	\\x59045e061e78665142845bbfc41af24a5fa80a647895d46b69eb9b0be4be2451526545576664b69f825ef82ea2efaef1e43e39c8370221bbd1b31d89dbfe5d04
241	1	419	\\x6ddf5f45b7f1d9b9eb643ef6f198729797416d1ef5823f78703c05bd82b1d71db693da22ac5bfe924b279147f9038d61545f60e37aa1d0a59d8d7f2c59723307
242	1	190	\\x553c750a1531bb23a4338f60b67946b8a693f4d2cbc0cd27b57197bb0aa1f45b1ae49b1eaf23d5f6da7517c8d1898c3dd3706f9d39b2525d52c7a57c738c9f02
243	1	397	\\x0878377dfe41bf4e09a206aef411bdb0a8f98ac633396144aa4f38a425f9c4d605955adcf5df05248e99f0d22eb312ca888295106b10e6cb86f41c454c523b0e
244	1	224	\\x00b6863580cef35060c34062b081f26b00889ebe02a005034f2a19effaed053f3c8785f8918e92a052e40e2bb3c4cdc2771fb078654cc54bd0693093cb36170a
245	1	382	\\x52207bf019c4f2a56e042f1a7596649cb6b7b8f422c5b4ed1319e6afd73f71af794e117391d1778722581fb00cb5b9c0ba6afde08f4fc7f0b40b30c36ba0b70f
246	1	36	\\x9f25d0ee934e929de5dda9e7490e5651a161ab1392bf5df757e2747e581d0c3374a79d3943af4a002f2d10ef9f701d9f0013dc09b06d4edb6d2e596361dbc10c
247	1	97	\\xd4f306f64b0cdbd65143f1abfffc9f3876574f8be02949232da112e93c84850acadf33f223c8d77e4f79b47e3a208743f19c03680eeae75bdb2ad2e4f6f94208
248	1	261	\\x594c92b7588470ed3f2da86df9459f31d851ca38ac5b9177ccf4f784cb8f037b4e10fa7e0f64db9e8c4fea138aab61c846474732a4e61ad9a3339ee13aff4f0c
249	1	242	\\xe862659e1406a4fcae6098c61338c72c9f8731855fcf4b6dda3bbdecd3a48d4283cabefb3fb38f35e9712486ef0290bd60190d9282a5514218f317a5cbac140a
250	1	297	\\xf8463826774f62694beb7f838b4fe41e4fc721c0e7a08fbb3b3ce9731aea5610d98f071dc6bc82aaf164abadfaebc62cf9aa7aa909119a977b47f70862c22e04
251	1	40	\\x5ca874af5972239cc6e9e426122bc806a4e1e73661f6a42c54d37a0018fd74f1c15fb669aececea5c1081adfe1ba191c621b7e23cb0a0c739a4b43a7bbf89c0f
252	1	292	\\xa76b5997b859ce085032394980929bb812497d86013e004df94399cc8ec4987ca7e463c19e5570fad6fe5a4162568d6f73c85ca6e3946ce4a344a093d4cf750e
253	1	173	\\x9c081561589637ab7c387f9915a542975a98ec9fcc9ec93909a2d2152e217cc8ab07ca307b9177154c5de834e682eda362abaa573d97e46ef396c095c7c2c403
254	1	62	\\x5695ffd64fa3a8c29045c226efbd9668aa33f5051f2b8b27431c218991453c2f03b8665ff096cb37df9bca87d5384188a79d0034aaf1a939bdfeda3f2a2cb604
255	1	330	\\x8959b0a86941d2bf3db6cb104beadd342f756e71a1ce60d38a3f80642579c6fbd407213b94c6468911cc1e51b07f48f5af427e2ec8017be6380394057d58510c
256	1	375	\\xbe86418581d521c0cb8631ea8ded9eba9c6bf99d7ecb38879c0bb63f3f7493aa6249a040f1acc8ec0ceeb597399ad66a72ad53194c24cfaf4b70e9bb6adf8006
257	1	106	\\x284da2ab185450c5f821d7515699bbe2f56936fbed497fdab3483f7e678fe9d4d170e673f80ae9bceb008775898a2d06810c3256fd9341ed3089f152ed50b809
258	1	259	\\x0a6ecffca0577897bc80788e3486aad51b5d3df2379923ca482fc5581ada69c72f3ac3eecffccb399323d5e2031349c998db94c1049709a5946bfe01abeb7208
259	1	105	\\x590c8e03630a959be2843dfb37e7b59287def7487532c4f5a049fc9690550b6ddf4eaed8445b5b674d8805c0c4d9e59e9cf639d2954e44eee4f972395e556406
260	1	251	\\x32fba3499afa8fd74b4843a1cdb78bc438fa15c8ec49dd8af5582383d77f03871b62779c4e54f85517e0e98684808badf87452db4ce43a70226e09317db60c03
261	1	19	\\x5614963cc3303076b2d662f98dc29d53acec2623e6be30ce328555eedc0685a37f528a3629376551588e81bb5646809fd10499a3af51a44e90dffe03d454a00d
262	1	257	\\xae29276912c2dce7fd253747f593682623c40d9275d790219298d1ca18194075ac8e132f07ad8e132537e140e8d15bfe21267d980eaf5866414bcc614302500c
263	1	48	\\x655ec8923a63cfe0e7fce96e8f36a606c34a9154077b3f02356a9c6aa35b3764bb552c0046810273bf753fa51e55202d93dea34a9d546c67e1e1f4ca15788e0f
264	1	352	\\x47ba94477d7416d414fcefe7b646189c81ffda3c7ff13589bd7fd418ee2d3f66d0c05cf84c7c489f736cf992f6ab2fab09a3589e6632f712fa5ffdeb9079c105
265	1	414	\\xea1b05dcdcc28fd74a7c3e02feaa825b7249630f90622e22ea788c971b9368ef74f6e5ce84f4de9c4895f49c80e0c35bfec5cc8d30dd6f74e24a242bbb2d0209
266	1	22	\\x1b0067eda8d490187805ecec3762be96215cfe41983bf1e31f8d863e1e78444a0e7f6a98e566a57d934663905e71d9927afa4bb7cfec724c8de814e470855c09
267	1	81	\\x04ba4b215d96cae2870496e81c6424c1ea13fe60886239b0bd91257b687c054b516f1edec229cdbeb94f8d2345c2f1448d39e918798ebefc59571a5d004d8202
268	1	1	\\xda35043fd43a9da289c02d31721bf0a6a030a185633ccb8408e8bacf5066f724ef251ed79e4a5f7e049765428653d690ecd7c9201449146e8028517bddda5a01
269	1	177	\\xdcce855c029e759b5faef063f4f31af3bf9821e14efdc1668431d77e8a3c7e163c9ad7a5bd5799cc033ac542ba89f8affd2e2989f281f61be22e5123a7b11c04
270	1	174	\\xa442333e5a9b0e08ef6a3a2735169aba96913bc8d8f8007d4c853e23ba8cb241c922d46ead7c2ff2aee4210917e37d858c30eb455a3ca51e636df6ec60dec900
271	1	245	\\xc38f0270e6a09c53b74384f677f16b998b9014555d01360fe81e6c0090c06a7ae588abaf0bfeb6ecbcc95fdc94e64d246aa8e6c93fc879c39c7043dcbf6b5f04
272	1	264	\\x8b607158b4a6d1504a746129caad18d0d048f869e1106a6e4c6fb6d416dffce4bdadaf9a3b33754f52865859339ebbafee90689decd9410846abb7b5ca7a8608
273	1	100	\\xeb0ea6ef1003543ae3bf5ab1fdc06e62b8d73b3d0871d1b9761984f68d17d68d296ff4c9ca901a7eb1a778774ad5e3e5ac41a4fbe4e28bd624acb334dbadd30b
274	1	333	\\x0e79d2ec62c4c4690fe976a8c84dd217dd5bd5e90f17d6647ebde0bd7cd7060b455636267ed3eceedf259c048fce8ecf8d789133054576033a9e271f72d3a604
275	1	64	\\x4ce28eefad95fb47b30f984f3a2f85f1c708483f7264748bad6f0ac9825146d679a2de74647d4a0e783e3fb23f5d6e639687c0934614417dca4bc0d8ddefba0a
276	1	123	\\x21251399a95df69a192f8617301fe413fd8ac7c340a3947d1ef4b8d8749fb76e837986ad136dc0bb2649b96362132d60d7d07da7af990b400d68ea5468b5cb03
277	1	349	\\x9b25c5ce4af488f66991d6f4fd21400363c44db149d8628ed44e3f72c869e9d038782f0584c02c2d9bdafc258f0e0789d91640fbe8fc9f8cdebe555612045000
278	1	92	\\x1cc87e5e21c72e518e2db16d22096131174bd2c79817244a4845c6bbd19696e955c836d0e236084c086a33bdb9a88b76c5bcc710d5ad05b0d8bb870d31d8950f
279	1	111	\\x11312ceee9d913ba30f88df8fe4002e5f210dc4c6bcde4b640a5a565587eb2f47eeb2e013241b51f8ffacd77814d70aa46f952fb0827e3d0e896b69eaa6e9c04
280	1	339	\\xf3e13818068851c708694c2a9af24db606f34a956328d775e27f64dbbb1d6b62fa2a0e7c03706ca8e3e4f34acb14067d038a79eba11c072c2472cde27611160a
281	1	47	\\x5bb73a302c3b6326439716a2bf168ac2acf0b4bb8b30dc85326e3fd1f3517d02a25d3e4ae35ea5c339ffe5d9c13923d90762606df7281062c3c4c01e9e33b406
282	1	128	\\x81a99cc50d33b1cf24eac65bdd6477da0625d2c78ee550cb68b2a02c6503603a7aebb3fce4cc8e66da417c343f6832246f311ce3d2f98fe83c4314be70aa5d01
283	1	329	\\x3196dfa172fba6b19325dd2badbcdb21cbf4cc3c6a0994d38171b7c4baa3529e3cbf8dc59020d5250c5e0ec4c7d5f3d75be5a9ed5625ecc8c8d86a7af0731203
284	1	68	\\xc2caf46a0d8d697d7f0eb16061023fb8199e90f471119e2db15077512eb17a48ff1639b7b3968b8dd9257d7f9bf3e11f3c1f494aac7db287b1226215fd274a03
285	1	220	\\x0f15087de53ddcb448d6cd7de2d2766e63ca1a60682da04928bc9f7ca5189df189034d9584dd34f88c34ff5133bf19b991e34dba7328793fbbf70603c0507607
286	1	398	\\x1f7957cd432bc02e30de8d7ba761648b359a49c6dda8f496e4fa58498a4cc48214a5549bb473703a341d86ff03722b8b7115e7f5fefc4f26072b1ecf8189a103
287	1	207	\\xf5e4fbad20af89a153a9272d64ff0f4cfef67cea212a5e1b049858383c921f9fd49e401c0a5109d5af9e6b254c0fe3fc5d0f74603bd26440b7b08d7d10790d09
288	1	306	\\xe01887491d8df4b76c02c9d04ec0155b9ad494aef2442a22ddb4781876a98e2dc5863c42119b9b85a316a31b2a8bddc705f9dcfad65778d49a3c75b1221fa202
289	1	27	\\xb9b0edd81d80287a795853afc44a2928fc5f2c8ca62f4b0d073d06887805754f156814c4ab7e7c06da8012a34c85fdf454fafcab69985d4207d16e9bdc00a002
290	1	180	\\xf65be98013f7fa528a3aa3faee065191a0bfccefa9fd53a807b9da5814a2e766b1b3e4b71da1aeb68bb87a9b69531d4dfffdfa9b081c42cce17c1d1c8d68c70c
291	1	191	\\xdfd0eb69402cf88be1762a39fde89b0f077805fc808244c80a40a0e8eeb5701b631899781b190f877c0d589c893931c9f4ae14692b255dc01866715cd0172a02
292	1	164	\\xc63e4e6f8f3b83694ae06bcb6f84d8f694f5bf67b3c0b4cc6c328cc8c22a90c1ac9337f6136150be9d3626807972c2dc4c0e29d9cf58487c463ff2343de93109
293	1	151	\\x53a59f7bebdd0c9a3e6df1d369fdeeb2cd02a95a287632f6ecf3719c7d408f52d9e83437de06a470ffee1d83f2c206d373b2cf2949340032cbd318266bf3480a
294	1	25	\\xac4377470744a8fb5e5f1aacfed043d7983758245bb3d0ebde806cb90c221a71cc8ef8a5b5979bb932e0c4ae231fa476e25853f940b6b8cd03905b7a48aa7a02
295	1	124	\\xce60f04c458a6960b87bbdd8e29994f00d17ea6e35590ddcd777dffd37cd4a6244f239a3241ab01455094f0cfbf300a287a2bb9f8bc42cc0ecaec55cca0ce409
296	1	274	\\x2c71bd419a5626ce3a570a143c1cf635ae1074e5751e87d605d64a4030bb65a4d549464d2b8e598d636a5864ff5b491e1d48c8f04b8dea2b1b2ca0b434859c05
297	1	403	\\x2d90209acab473b008b5b1faf5af8f4708c5e657ac4e5c0efbf583c833c1d4b405ab02791969268b1707cebf209385672e7edd7f0e222f020fba6bb939a2150a
298	1	10	\\x78a5e6a163ffe0a6a48a5ac19184af2d198b9b37a32de70be63ed4dc5e920ae36a05059f382c18cc48e4e36c1ac5ebd38ba86ca3b782384d082637620beee40d
299	1	21	\\x4b959c57b5d78cc6a138a286503e45fd0741d713987b40f81f353e78bb7cdff38346fafe2e0f0100e0b03c3f990b934780c2717a5406161b43211c7d81caae0d
300	1	178	\\xded9a9ef32c3f36703db4367f547b7421bde5ce54ed231b6b7e34f254e26e90171267bbc6714d1f23f280d9840b6806c7bd47c077757cfc56d91b38db9555803
301	1	108	\\x77f91af2b6be1cf91ced004448dc0471e1111bd2d8d73c152631e1c417c469fd41c4a31a79bf48388b7f238757c19f89ec344200b8467a8990014f0a54b91101
302	1	302	\\x5c61824a3b704a086c8eaec06403f9ff5d3bc8ce1a10b30667520312c8997cf4e8e75414102e57fa5c50f56bf07360ac3a049e9785c0fb3103f30db225f22905
303	1	189	\\x4b568f472adc7e6ef38dbb1ada62fd2834516c2ea23a6ed0b86c22e8ea64f1b0e34eba20cf901c86bf9c1f71d97ddb2a0ee77e141c038a90c1837e2ba8e90f01
304	1	338	\\x894aa98e1d4bfb651ff81bc1cc99e0f9c20e54931b939035589abe238d9c023053d0b3373a1af80bc71b94eca49fe6b545db2d821cf4e530c665f901c0fc4405
305	1	366	\\x193a1e787b1fc0bc00a0e16d43899e39b1db7f8794af67988560f35598f4731f4fcde3080e9d12008b84928eea2abfeb8f2d4e2ccc7492d261ff23cb76eaff0f
306	1	331	\\xb6e2088009381bc9ed6b79a55d56d5a01cbd4a6de8ae0b5f4d293c60267380f68ad5d525dac71574856f5e367b7b9febcafae451c17056309c7fd41024b64702
307	1	237	\\x2d097b1aba922631b13dffb8b56d2f0f474c5010dd5329c0a2d6e3656bc35c4c28830f1fb37741e16367ed25d32d20b4268098262876be0cd59542129221a407
308	1	157	\\x327441c067d6bd6d5bbf625c2cd225cd7eec3c5ec88dd57f77d94d8199313e62760a9ad7f4a1e4a44d5a0a15f6962dbc8e2f37c1324db9206f57dddb9618860e
309	1	384	\\x32bd4d1b0afd81cd36e79507e210769398c48662e5a6329b8f4b6e757aa4c78b03eb0102a1c9d300777e887be4ae6e41ffeea769f03f9f52045c737d4ac12709
310	1	269	\\x75a49334ad4e5f464445855edef22ffbd42e5a02631eaa6770c94e34334ccc592d3c9e08d035aa04964cac19c3e2cdae6e1aecafe95948b6f5b819c971be0402
311	1	234	\\xa1ef5ec0d149cdc799b7833ac98a87d43dfab16fb00ca4885963e40a10a5eceaf6182df9fa066164417f30e7ecaf6b337fba63d184d2f8af41849466e0e8db00
312	1	405	\\x1bef89bfc3e42de1eefa2dd79072091cc12547016347f82d8c121e549f4450e9d101a8a09fb652a454112d704b42567effe0ec85e93b14e237200112fda5980e
313	1	216	\\x255a15b69a6873cb6ca89d6645c0c0f50c4b967bc588425dc778c3c2696690572837abde5978b5ec83cb23ebc37a673491e9dda438a499427985066bd0ebe00f
314	1	11	\\xa35ba4da3634c0f6c030b5f61eecf303a6f91716a47a1707de180265ae20700a3a6621de204ba9b6625606d1127744bafc2086373998f95690c80a399706a903
315	1	204	\\x1ecb64c913eb36bc907fd39c94b5e5fb7535df12b2a3b63b3e3852b8988dbb5afa3ec1e476ec87cf2d2dff12de2aab8803f890abe65794ec1f64a1a6135b1e05
316	1	263	\\x9169b2ae49ee50906be587770fbea3c56ba83060ee43de22c7382c675793bbf23799b3697180806276af5bc243d476942db217ebe719b31a4acf758456018205
317	1	162	\\x2cf8fe14c002f9a08f9713425c252a5095b246ddb415abf4aac904369eba8e6e3793fa5124d627e0cfb2124d8b66ef71785d8c245d8863195bcf8204b7ae220c
318	1	38	\\x6cdf1a1420a6355d3fa9df4fd406e6f4a4b7e73f2e38344fe7264d40cc533a80c549d2386d4f4deb1020a61a127ca8b84f5e24a6659d8552a28d9d41eef7650d
319	1	41	\\xf94ad66072e9554034425ac291a9c8f0d54be33528c4a16c9f34f805d588c5ac7095fc1f0651ffea230a9463a0ad58ccb7c217067c0a4258c5bddb358b1d180f
320	1	328	\\x551c4d964e36a8cf433e87e649068b9becd3c0fcd74bea099d86f2c03e3b36b552dbc31a4531a53a48be414a4605a11d55c2ff496d614ef51d8f76476ed82905
321	1	29	\\x4ada0eb40d28fa832da19f886715b9fa6aef13dd9802e987e928f700ca321d353f37e6b35117581c42862541f356f7257748397028115ba288d0c892d733150e
322	1	3	\\x87738e26803d9fcb12117747e0bb9a36f3bace2bb522447e448aa22526363ba5c5c915d7f465ad3f19538c7b665997833744b1801a9d43307b02ab6603335f08
323	1	46	\\xc0964fb8e9c9e31272af580ef982ecdf12a04f2ba05cb99994a8f136e4137b8d55e591a5fb4df2395ebf6a8ce724f79f1fbf6c5e95b769d67c994d049fecd807
324	1	44	\\x3577f6ba378ba3d7f7bc7b1584c43329c5029713550e606f9177a84066a87eaa13cb20ef7d36141e229e353a7bf56fea1276c4639036fd9611bf13713349f704
325	1	301	\\xf5467b521ef12ed949285f1cac8dc78fde2d71c889acb3a7144438f066069c3b89421420b3fd1088e812f3f6af7f03e16b7793a3793ffa55c98eb8a3ce00d301
326	1	258	\\x972459ab4f3a4bafc3b7df0586d6c5d27a5424fbd422696cd177ce657f4c44d77f46e987fac1543b641773794582af42f8bcf9e773a83eca6196524d8e38f304
327	1	304	\\xe316296d9ae41db64501e552d59f4eae6c61dccdbb10406321006af47e369e91b087b661854a981aecb844e27ae516f5440ea8187a01915cb2270cca7b47740e
328	1	183	\\xb5109e568b7956fdc70cf0408cb9ab5d60f739d7a66edbf8fa174c82134ecd7585d31490a107c6ea8e21431e51fa2c067ed8439a7affe04506961ffee7cb400b
329	1	265	\\x768f545a2ab9a61c22195b72f84c3a31b2fbe4624f2ee290b4d5c018dd411c253cb787248f8f0ee5286e4ac354083293dbbaec2e9d1b208c39fd65d18a8e0a0d
330	1	213	\\x35ef383981939c0b4b1cdaa30317f2ce22dd3fe2bb19f916a77b9700557b1766472773098a9898ce300dd3e00eeb64f143718aaf0091a4f6ce0bcffe1955f60d
331	1	424	\\x764fb2149852c087f9c7883333c4ec13359aba710970d244d0a2a016fa5b488306b91a704fd6065aab554f4f5f54a8648f5d0221b4407fc4eb52e0971de73301
332	1	201	\\x8a103c666b66ca2057c9459d933bc4af1cbb891aedeea23931738499101c98cdea7ce85f5daca5f03ded730abe00f19649364c7f0f2d0596c481661ff85af107
333	1	379	\\x7b2ec85edf0e20ece95c70c8cabfcb82dbc4b94ecc2718d5df79affd538a97542dfe35f70832d5ca2c72349f3a6a89eb345162a0b72875cfed3a1d93e146de01
334	1	279	\\x6753fbf5d66393792e1a2d3546b216465090fb6a3f1d830b803ef0daa968e1a0718a61eff08839a68f5f42481850b41bbabecd18675c88baebe8515619884e09
335	1	91	\\xaefa81746633600b1b50f2a7d3513536465d152d9b3fd37881cc93c5b0bbe94d6e8af9e78cb1d8c930bbea5f543162cb886fc0a8fdba688f28f4506100915400
336	1	51	\\xf9b47f0d1a338aafa6df753395dc90e2449c492f70bae6c6f377e915bc6422ed9fb3e89d9cf118a5f5ec2fc320b07e6a48ed4dd0c4836524a8fa3a7eae03750e
337	1	113	\\x1a3c0660c0ca6b00f81139ff39471e50a4f7a2cd5a6412a5b511c45d2d049e0665251a2a8207e45b97ddb6241b716f6029b63a924b24834812f9c09249f7730c
338	1	182	\\x30679cf0494b87c6da5661e415ad0bf3d1c404558c8c285a3e1c22a374a43c13694f665d1ec7c1f1f76557df13982b11dec1593dd6eabf6a7870eb241b64f005
339	1	55	\\x93de34d7cb5703fff592b79a103cf0fc7bece34e83f2c26cb8f01dea9c61b219bda2cc8e3ee346c67b50f8808ca7c8c6385d5e8df5d135c0a11ff121828e3e07
340	1	61	\\xdf9e64bcf7cf6122556fa4518a11557d37333cd2c7d52da988e2499b372a669cbe70f4f976624fd2ece8c3e602c9cc6972a981d83ce2ae0b89e0d642388dce0c
341	1	13	\\x5c505a79a7f8adfce735353ba4c5e922da0273dfee38b84eab14a80a1659727d6bd76245c7b96f6ebddd75a2aeb298cf3ff9b5aeceff82b104c82f734367b00c
342	1	285	\\x69f62c99dfc7e090afb2b12d037f9f332881fd3ae359454d3e89a6f4d0821afc425077937025ded6602a052e4e5d09ab322cefa4e91b43954fb26e0279115a09
343	1	43	\\x7d55c33c007ccc9ce5dd941c70d5115b989119e3bdc8337274d9ff39f5f660cbab110d0f5e5edd7605422ad8750cee60f9d1314e8334e00654793a39f9c07b06
344	1	121	\\xf45767110f44b248b611da4357bfdfa688f7eb823342585022c320eea19923fc0a247a69a9ce08ea0dd3d8f7c6bdb5bf2cff3d1d3e1f062c2182eb0ae9de530b
345	1	289	\\x73158a319d5143db831fa320c1193a68facf5ea87cfe61ebf30ba20cfb9323fa16a3963bb97ec876476ae5d00530720828f452e402dfbb4eb46fdf72506d370b
346	1	134	\\x103f34a42280435af6ddc27a7e8b53917df112cb78d2acb707345e42abac20a98c3c3338b786b7f89ea4cc66768c3eb7bcfcaee3afe19e9f82afcd2347609a0d
347	1	283	\\x5a9009488b97a15affeafdba84b73c58924022b3d848459c0575f90d02803a200a3a9e98f3ea69fdbe5388cb618f20593ab9103f611e3dc7d3cc74283089ef0d
348	1	37	\\x9d78952334f92a6d488c8ee2b5c39c3b52c84c40cfda55a74e03b528f89581c516b944a157ca328bc3ec01a4fb5fe1f7fe282986193fe49a6d4c703ce7c4e50e
349	1	119	\\xda88960e65b6ea36f0645dadf1ce2e1a96ab31d7edaa0d01b7d999a56fba4e812347be110c6bd776980f71e1bb67c8584e6022d9845c6e948399b636ba1caa07
350	1	56	\\x739ccb6c27fe6282f019fe5c461887ffca7f1c08a5d53978e3dd77490696629a0e21dcac44a88413a97a81bab3827907a49b743330b12d0e41f6a6c7ff172e06
351	1	380	\\xd92b806f9df9417d8b22d1008ff78f4838aa66f915620d4c6e4905118d28abf813bc677e3b4d531d72ce040d785b72e9194cbe05742815f5ccaca790ebbf4d07
352	1	243	\\xacce6897d1d3378f7a4b8f26f2e38b0df9ae1aac5b0b2659c56ff239872b215fccf502cf0a42fde9265128d9ca566d460bfb1eab8ddfe18a57f14e2e1be9b50e
353	1	421	\\x54d32426d0e57276fa7df04c57362616189ce484d354d6627dc14c3973c172380a08bba78ca7e824342adddae68c5b57d0e2bc73ba91b20f163820bbfe302708
354	1	418	\\x4682ab77b7be0052a2291cc7965f60cd0b8475761dc306a71a3e58f453d75771562fd9b4b2bf4d1406b77d57651c6dce8b8841da2d06b9819be32695b0cc4204
355	1	75	\\x76cd491f615602c626704c13267942b6bfe49a58d2116bae269e1f4613b710dcc70485a2a2461d1b9bcfeb14b09de793b19c9af795af4f8e91b26b98f74f010a
356	1	376	\\x5556bdc7d70fa7a4a53969e00fd24983b799507857dc83b3f2d3a21f89ffa5159411ebf6efc175f215f976ca6d15efe5a2dd853ea7198546b7f706e962982d01
357	1	276	\\x1eefaf9dfdc64d8b080863ee6912b716a9e1664b82e34c1645d35c4b923e70bfda644b0081e8503937c13341b0049f8635400040629023124f1d37dbaa06da0a
358	1	18	\\xd1a6024f197c950cb3eba60a6857debb6df4ac0388b5f235c7c8172b966e495daa65b9791fbef1323e6f01252fffe5c29c9fbee1cb63c226a3d6b89ac5dbaf03
359	1	156	\\xa399c611b9561ab3bbf337eb75099813976459cb1d1ad68e75b0ca4e81be9f91ea8b4529777a09aaeb2583d2ec33d40dc5c7ad0143bddacc98665c823ea88805
360	1	176	\\x76aa056fdba3eb8c2244c8df7edfa2d7838bdf14134c3db30e0602236d363e59bceeda7d0df51346c36cf1aa59a2f906d8ba281314b7bf5ad48f104e3b06620c
361	1	356	\\xfe8fc9d74a9323069af9b01d8e4c22f0ac7266b5ad2c204c2fe96485368db198174f36b43a461afd84d27fb9b777a5aa7e0d606174345c33827741deec2e8604
362	1	377	\\x5a1a6d5fcbbad70379e0177306e3a65ea05fba24878bf58c7e73d9ec76d58af98475e5de6e7b5b88f4aff84d3a432025af22246de424e832d5eba534536ff40a
363	1	112	\\xc2071b9ba51b790381a04425e571dca9098d1122aa74fb2438720e76267dfb9d66fd50fafe4b4a20e93df92a0cfea277fad1415290270e6619df0223ed964106
364	1	125	\\x3c3fe29a376a874401260b14b846afc56a70b15526a2b43177f74728648ce142cf4d762d826705c5953e86cb59f01b8c49e84ae67201789b4e70deb65a0ce10f
365	1	171	\\x52f94a87b82f20efa96aa9f9b9e6b90a6d4988ea7d7bc136bef83751e49d894b15f19615499c7926c4ade9279efc0968dde0f908ada304dc2eaf3f3e6ef3a304
366	1	354	\\x5073eabd85c5f10fc0e58bea4179fe7be3ee990844e08e20b6b4eeb073b85abaaa64e3f0ab95f72638ffff2f800cd9041d3f40394ae2a5934cdc68ba655c8c02
367	1	166	\\xae82c0f8719a15012c8c1ff633e361ceb11d928a953b26dc6c82b00011f66acb1c6ad84bd11fccfa7c2c34e27effbf7761ce3babf364f4c6f6707a045804e302
368	1	233	\\x64546cecfa625bb8b27a4ef53e111f0df3c4ebf2e91af65dd392a7366060d271fe1b9375f5d7a25cace8f0f0afa6a5a9040d0483791189f5f9359f84f7b6bf0b
369	1	188	\\x82676a080fe25f1d060fd929a09b274108cd89d6263b32f350ca2c5508bb03432263ed97bc64dd7accf266732a18af371f3197ddf1156750ab08a4661338f600
370	1	374	\\x6320814917a9329ac04762d04f6be62f639b614eea55f184992b4db804e53610a8157626141e27d433fe6393e04e1f405fdec08ed2f42b5ddd98bb3dbb96f20f
371	1	76	\\xe03051518637b2134909d16ad3eeb0bf773d3978dcdca540f1e67cdc23d9e32cc6554ec969a651d01384ae0871bb7e8f7575c4d920145ab11f1add0a8ec06801
372	1	368	\\xc7542da51818d4aedac809c52921c7bccd8b07d60ae03ade605a46ecc40cd13d45e69e5509dd4cf633751e8c72aa0cd78f00ecbfd2b4e1d538ad31d4349b4d08
373	1	208	\\x2cdb3e9af1f39efea8fea8287af11b3e675e5150efe71a9d4874d93fc97b0486442f7b1bfa780886224809581c85e5708a12eb6d534c15c14da60bf037488e0d
374	1	262	\\xc82081269ab0d775e6e53bd6018a75c8000c701b5b9a2d7e313a232746c54beb2eb25cf59c46c05544252fa8ea14d42dabeaa6eb7c99ab7bdaae45b6074d2e04
375	1	205	\\x69b26537779e42dcb1d683f3b5820ac469c3573cde0334d6f96bc72dafa2231b33d444cddc688fbaec7f22971b98aeb73c168e7ec340ff979c6033890413d702
376	1	165	\\xc27b3e66db5ac8325936eda6aa2a535b37f1c2357ee7ebb77e74c58533050e65ccfe9f2d26695b0254c4b454d0be5f0a8813cb721c4c3129d4921d7fe404680d
377	1	88	\\x5f8eb681dc928e500fb7000ab3faaf78acb6b89a4f5bfcb3ca511f8ae82bbc7a01987211c40a8e8f5fdb48a7d5894a9531449d8868f1b782f58e1ac18a1c9603
378	1	350	\\x84d282997bab90695d3bc4e0eabda2542a6b2955e729cad77ed35c1616d3e8ea8867c6dab2626e616989162be764eb5b0f698799ac4e2c9aff2c01e835854601
379	1	236	\\xb7da37056c2dc17d70352118ba26bd38d138388455728be85c06b5cbf8d556cc65b0ec54b7b441957eb9061ec61427ffafeb1e4671dfa872458b61df34aa3c04
380	1	362	\\x1321fc879127b47ba70e7edfe24223de7fae5c1497c7afdcfca4689855f0938bce22c6df46dea6bf736fda736fd1d81fb5b872202cc71a263584907330486b00
381	1	415	\\x3a75c012a488b369fff665f12fe600d53ade23048c783ed6761281a0b3280c129d1f731e16c33288150cbd1f1fae8abb51bf876affbef29bfa61728e2acd950d
382	1	401	\\xf9be3a32790ac427b842f59e1363948bc1553add1edb65e2f2315413e787c4040dfa413d06776d66375021af16e13557d4bb1c8362f7d2a49a4651473649c403
383	1	8	\\xf727b4313cf9118bbdb5cfe2038298cf91d25afc52ff9d31d1b45c235ef8dd888a277eda4af2efebe139f88c0265682fec725973b51aec392ad3fdcb4a41f10f
384	1	363	\\x6437ffe2c811c97fb05436e0223cbbae91fef7b9caf93bf8a9aff597d9c5a20589e7715dcae2c1e0b4b83c8026b411c59d3bc314e1c2171ff05dfb53b1c52500
385	1	392	\\xbe93922b8b09cd9137aec5c6c3bfa60aa78975dcfeb2fbd7348cdb8217dd7e0572550aab272fe5cd8807abcc8d85526b73f8d0d28f8327cf4265124b240e1200
386	1	210	\\xeecd51e92d7a844e7fdbf863447872cb6487b54c40a57c3fbf353c43bed7962f8aa6a7a3eae0635b173ece5a0744d7fca436d5d0143502dec0a4e76ab7f56e09
387	1	103	\\x020b380c1077b2dcda132ad73b2a9dcdd4084e167c35ed62c635a97b640dbed5a9a9176721b8a16893a1dcbf6cb135d9688794d9422d03376529d7eb671ae90e
388	1	252	\\x7f79de461da5d7a694063db2713be42daae204b2d361f893c74b1de7d2f649214dea37614f7875d3cd6859dadeb73f8c48950ead5308aed1298fc4730f7f2302
389	1	323	\\x0d23dd986832386063a1fd178f68ce5fc638fd6bf0afae8127a858fee99a4bea1f02e32228fcbaa187fb7022660ce2a55f8e5407f8b3e785ab872a0949474205
390	1	365	\\x98884ddfa92513b5b7e445a061b526cd905bfd36a80a0c77f57a9b5af7ba94d92c1161e87324496670ad744793e9661878a9a616ded2894c08106b270305d507
391	1	386	\\x337f743ab5803ad7892ecc067503c819ac63d6049743b103f5cda89f25dc63a40106050215deac3d9ac4d7b94ce2cea5a89e5dccaf7f1ac6d167d82d751d6302
392	1	336	\\x4ee6fe6e96834bd4728111517cecb4523097826733a06d87a19eeb9cf5acbfd9a024ad3611ac830c918dea0dcc1763bc6b7f1294f4c817731eb9e8217f428b0e
393	1	371	\\xa0acd38812e641b16f919976a32afcb9c1d51294f0e878db516f299b0ec28f09a0886cc2027786c4bea215798a93af02622c07f1c48bc8f4360e2165799bdf00
394	1	253	\\x6b8afc2aba70fdbc0ab56abe8f42941df83e5429f3973422472e6a82247c790c3895678a5051f24ea00664c441a717eb7562e849ac412990da150e0b7363b00f
395	1	294	\\xc84186487c3bed848af33825d0e00d5e1e73f7154532003408cefcaa00ef43d964e39ef5527156eab178d68f659ab32036d5beedaab04445e775c10345c23a00
396	1	282	\\x2907c94d30658cc8734e5671485fce7a461eebc33c47c08ec221ddd223f38f989826533a0a4341e7a796086ff323489f56873e7ae82e015b1a576b06ab5ff703
397	1	218	\\x47ebb4475e91f4545ba84b8876d04cfaf8580b0ae33c7c856d65a4927fbd75023a440d72ba75d8dfbf6a51546a38ea88e3642cbf9856ce4a9a9bd8691c08cb00
398	1	232	\\x924d2c23ff93042acbaf36d19f6e3f8b52e4e17eced4067168743b4b27e445a8dd2cb058b79dd68d1a0061048237872fd726bbb99b9d2351db4e05f4a1dca901
399	1	137	\\x9b6ff53aab32135e3af4c7b2c9a593159aca02bdbe53dc5ccd6ff182692c26d0be1313a28fa2c970b657aab5a54c4ae1779f058342b9720f208bd27ed1be2f0a
400	1	275	\\x5e462de7d15c1b3657a6c6d88c0782fe1531aef60450a9b91fc7b0a5c8acb4b3da3cca10505222519f288b6398cd180c34f68aaa92430610bef18fffe0560202
401	1	35	\\xd526573aeb9437620d1ace60fa9a7809eae1e03d1d311121ae5cf118f398deb8f40e81a849167a26d26a10968e09746ef66c7ee3cf5e30bcbef30b8438e9630f
402	1	278	\\xc898cfeb57a6666b28b2c2fcbc91c1785add7c408d682a7eabba5284abbd9675c68f0ac772c67444898cfff4b728f91e8acc45888c6a4d96cac9debdf6462201
403	1	345	\\xd38c851b38f568912603b280d40a5869c5b25cbeee1901a0dc26eba7dc80d6607cc5c8bb37e66d77bb256da7b7a78c4a0fcb529b8ffc0834c77b0a9f6fe6a90f
404	1	186	\\x08acc4d7cca2f58d38abb3cc096992d7aac1b11da1b129da05b6380848d123954c027c77eff551c55e01d354306dd4ea30ed50de86bb64bfdde00d5c54f58505
405	1	135	\\x5c53ee8a8128d719ea5a0acd61d3093102e15de394f165b4f7d8b222924340e20596670f7ea41fc1ba9ec58b235a32f021331110667d9a647e969f1aee1a3509
406	1	290	\\xa79681860db2f319f18197e84419f7e6bb44595b2361db89ba8a2b01424604e202a13d9d3bd33b43bbfa578d65d7a567671f1489e9569e6cf28ebf7683ca9403
407	1	217	\\xe41ad91f3e25566ac5ecc4c6e51ecb1aafd7042065aa3989274dd78a508d530013ef47d51bbc1806da5ea5b62d7d69c254d87784791ac6ee314af91d335b1b02
408	1	28	\\xe3615bac4f2cfabd11833182642d1e769a1d9365ce635cae03d3ea23ff6613a979f141409fa0c8f8ebb1384bfb07cfe9d185fa36a042b52c09c6b736a226320e
409	1	118	\\xc9be4e1df3c639ff1281bf54778734f2bfb2999408ae88a2d0738c7e83dd2e0254e7ee5688a237f3930fbfdfbd4f233d5fa4d365b974d51528b8e5a74180620a
410	1	110	\\x10211315ed7cdc18d2af6bcf81e9af687b3621ca16a02baed3a2a426c20cdd909616ac964fcd92254997fc4be4aa6957db0291ee308331ece6e3d045c400240f
411	1	98	\\xb33779b9b0fd044ef8bb76d4ad70cb26d5d0dc95a85bf363f5c5ad5f3284809bef86cf9dde1574f4fbcf9d5dc6beb28830497b47edbb4c733b3a8dc2f61b3409
412	1	154	\\x29472a3f4a9cd993587162a4982c69c671ee5e179c20e1499fb5462b3831b06ae6aef0577cb40198dd972deedf9e84ead798482fe0ce30f24e3ec165c3ee4b0c
413	1	230	\\x17d239642f020492a48b2fafdd0e3e36b46bc01ae3169ac882c256bc31f9002dc1382e4ea6049779da442f15d604cd462f177873f2d74aad6b2f780ffbd59b08
414	1	326	\\x44d353a23b1e66cd86c1a8a1b5c1ece11971b973378e8b436fece8a5c31df6f1952c45d5a954a96d2e5964eeafd97b53ed4b934c3572fa3e51380562e78ea90f
415	1	340	\\x603988d03c944e1c7f50404a120fb484afa5ace6fb068ac8a8647f927cf9a80f74ae8370b8fe92f1acf6e2afb2a1ddef3a816434b0f31f9eac8681325bea0901
416	1	168	\\xc0c1dace2b05ba6844ec8988208c46997e8f092e9fa87a487e51836425e236b5637fe4df7e3d2f14cf4fee20aa9417a2ca281dcb43ac9d773ac1968f620a3c0f
417	1	358	\\xc1ce2d21e27d7ea78e1b680322992efaa9952a8d73064676d07924304b7a343035b5e7ea4df51576307c3c7c864ab1e1ab3d544dd67c08c3697be042975c5705
418	1	393	\\x2ac2673b5e5a31f2e947e2b3aa267a2e886f6d91ae826a97b1f271a0240ff3d3eae29cea6f7a1281c06da0c1319e4f19112bc5e1e40538c2d540cbffb4321e02
419	1	381	\\x52afd9026f8ea012d32577b5143187485fc78151b085ec236861d141b136fddd8652319f4ff5baf6d0bee6e93f47a215822416b3a55548c487205410c4066e04
420	1	199	\\xa7d180a92eb2c1455ca9f5cd29341205ae935d7819220a1f918ead914851e719a4e0e57a1cba94ad07c2a5ecd3c2bdfeec744c8103fa6cde1ee505624744b509
421	1	235	\\x71686f8c035ff30427b582c0e8bad61ad5e072317338c68dd89ba928a35f77e50f3c7be6974d578ce9ce5398988a77e85da0a695887a2ae7122af8101cfe5609
422	1	145	\\xcfc46d5b29e56f1e3d0dd3c13f84bb85f6e4bd4c2c22967a68725386eac39b17def2e3de93aea47f282383c3d565aa958508faad11107eaa62b85d5de8b0650d
423	1	45	\\x8fe0f1ead115700b67ed3de3f9285eb66803bb1791abd0212ce20f5ea6ca2774085a34fe6f13fc267a237b88730023aa03bf39f69a022c0419a88bbadb5f200a
424	1	144	\\x03240b5ea3a5af710adc27bb6c4ec1a300863022e965ab4d8fc24cb9fbb4f1317117e151e046f5f6a969d2ef52ba6823a3e6d8396966d14cad507623e2969301
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
\\xaf96eb56a9f9586fce845e9a7d730d4b96e369c2f3822ce94684a2bb123bbb3d	1651516319000000	1658773919000000	1661193119000000	\\x47ad02a8c69cd47f05a8dd35e227ff48bb5129bcb55b44a4d8626335492424dd	\\x5c46764aef393066362dc49bbaa54d15ce826c6929709cf64f3061f1526d2df5f8b895379451ef9e678bc5213e4aea5900dd69d1ec66ab21aabccaa1b49ffa0b
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xaf96eb56a9f9586fce845e9a7d730d4b96e369c2f3822ce94684a2bb123bbb3d	http://localhost:8081/
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
1	\\x08bbda01b75f4378a0e2c7b7bf1dc7bad8429a7e9063a22ca798f4f682df38ac	TESTKUDOS Auditor	http://localhost:8083/	t	1651516325000000
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
1	pbkdf2_sha256$260000$X4khWuKsdDGMKXOJj87oov$8lrJ0v4joqfsaHJ0ormGQCoJe884nzdGAouUG0BLErk=	\N	f	Bank				f	t	2022-05-02 20:32:00.09996+02
3	pbkdf2_sha256$260000$yDlM8eqo85YoQBr6RSO8fO$Dgv6wRw2b73KGFUQ2agQan4OlD6IInsBxAEbuLztDeU=	\N	f	blog				f	t	2022-05-02 20:32:00.286589+02
4	pbkdf2_sha256$260000$atelB5gPkE2zbXAYExflsv$6x3NnFvXWXQKvjOXmyWPqfiT71oPfXEQiz+ynDXqHMU=	\N	f	Tor				f	t	2022-05-02 20:32:00.379814+02
5	pbkdf2_sha256$260000$O05raDydITjc19XegCDFrh$0iKnlWkV54jkmPMJqfSr3Ob4TVffFWNWPLAXOIIrrwc=	\N	f	GNUnet				f	t	2022-05-02 20:32:00.472378+02
6	pbkdf2_sha256$260000$lavhq0e0qGBgxBjNBSmhAi$0Qdn6gOTTAxDXTFPQRYcTYJ6sbW8dw7lIskGOyjdof0=	\N	f	Taler				f	t	2022-05-02 20:32:00.567669+02
7	pbkdf2_sha256$260000$1ZvbmltsJ0KHcBFJcrwl0s$Sqzcj6OD8wUvNFpcbBKex/VaiCv9fvL199rg+PA+FgM=	\N	f	FSF				f	t	2022-05-02 20:32:00.663395+02
8	pbkdf2_sha256$260000$waX1B2A8OY6wZNmBrNQfFR$R20xkYnSHjXnNyoeCOMLpI8q0BowVVGmkIM3kPbTtsA=	\N	f	Tutorial				f	t	2022-05-02 20:32:00.758441+02
9	pbkdf2_sha256$260000$3okuCkBjB1sJEWqRL8vR5f$PRUCqXKt0hUTME4exnI0awzV6ocJdkcOa9aDAnQvZzc=	\N	f	Survey				f	t	2022-05-02 20:32:00.854477+02
10	pbkdf2_sha256$260000$PgnaA9aCdWAQIRlxbeIKaS$uFOm7Hdv3ExjBDZwvHHjF6j6H9bXzMVH44RtZn+he9k=	\N	f	42				f	t	2022-05-02 20:32:01.313577+02
11	pbkdf2_sha256$260000$xcJ7Nf2NTjyo8cvfu1pxle$Y8o3cZNz/ir1KcL76iIQb9JnzLTzHLGfEm0LW4XBKgg=	\N	f	43				f	t	2022-05-02 20:32:01.759163+02
2	pbkdf2_sha256$260000$RaI674iv8moqcyfjA2ieml$jJ3kpJJV5AQWZagaBncDcm+lSSMn45Qlqs1BiRTnmIQ=	\N	f	Exchange				f	t	2022-05-02 20:32:00.194032+02
12	pbkdf2_sha256$260000$mc7zuT8ylQOTxJDQZVy4jG$1yXsSi4LPHsvnDWnVjMJH7T5XihECrGaN9xumv8IF2o=	\N	f	testuser-pc10aumb				f	t	2022-05-02 20:32:08.774084+02
13	pbkdf2_sha256$260000$0NgYsHjVNy7HTYQ99hLKzl$zCRJ/klPX8b8ZaqFVAUhB8757MSUNzgQry+wMwQkthI=	\N	f	testuser-5saj9erp				f	t	2022-05-02 20:32:18.94757+02
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
1	\\x004823b7ac655bfca9722e1cd6bfcf9a1324ad9ab0d1a95482f26c0de77b5eab0e92b61f3a10614d01636e79906e5bd52c4e83f274443f2a77c1fcd092e107b2	1	0	\\x000000010000000000800003d818a453b0b7b2b30c0e1216a1c9571ce064e88ca3cf858dc0816fdfa578de1ec8285bd0455b7de03860a7e99a2b256ffd5d86113609171a95235c3d0a8dd4e2792baefc9788c33a0c8f5123905178d77ad82877b697fd0d3046cdb0df511052a61f88204c4daa1ea01ce1e717b311c9f8187be7218dd20183a5f7ec54997f1f010001	\\xd090cfd97a66a2f6a6d6e31bbd457405d84c7214389dd88f6908bf9382e0f0eff1078458595fb15ef3b98298e4cf4d4569ee80ec7f2619bd5ba2d5410720bf02	1663001819000000	1663606619000000	1726678619000000	1821286619000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
2	\\x01f891516850be0be09bea62a6c63622721b271e2d369c8b42da2f23a6b8797bd0b1c45a07d2bf7dfa399d75afa050eafb78a1180c0b7735b1b0621810d5fbc2	1	0	\\x000000010000000000800003a39b44a3614eebb27ea7d80729d90252cfd512c2b803e979cadabc078b99b5869946ecc97364edefb0b7fee8307ab59219ba0233ddc3d8a4721336112b7cb094418b42045464ba38611345d3dfabbb227d914ecb42f45aa4720368c7e6e3e5bd77deec98633dd644d41f15766b489cb115122cf36ce4af451a64364948d3b8c7010001	\\x0017ee3d25983a6bf3868b095cc927067e293735f27d50ae62840a8ad02d69730a39db1e51a5eb08f3f9b6b6aae6faa4e9186f0647fed644d55848977592d003	1675091819000000	1675696619000000	1738768619000000	1833376619000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
3	\\x018c72ffee6c92e2f14ebf13d19dc6921fc190c54c30638da8e80a9d4aa44f76b5e6ac26b7f1e33991f53444ac4f2fdc3ebe576954e77ea622ab7ebd69941c0b	1	0	\\x000000010000000000800003c01c77224364cc489a2a1efb84459fc61dda317736d1e2fa524be5ddee7977573d672f8080e345ada170d4545a62af50ef7d541bb8a1fac57d2dcfcd6251a08c0090624e9369fb23a4dc03a73f7ad3b22c4acc372b60d8d86a4fa2e89635dc42bebd4cd66a36ae28ea1a9dffad65115adc316adae667f6dd90a46af84ed66b4f010001	\\xbb301ade3f7497993cb0a54127d22e8ea33d20ca384c6f6cac3fbd8ff9b4bc7221a92c8b11c482df2ca7604205dbec185de37ca4737304368a0016309066e70d	1658770319000000	1659375119000000	1722447119000000	1817055119000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
4	\\x03d82e51052113855ed4c333ffa76464f5292d0e43d3cb7c879a13c8c98dcc95f58a0df7f26c83413f7e79e92c0e070f6cd0e3e721a421a6a840eec5b7d1364e	1	0	\\x000000010000000000800003eef28baeaf15553ca3120c9f5e21e133eb1e68123b75e3e068843f17436491a3f1ab369009f77ceeaa0b71df4c4d3a95281e10399e0f95e154b66aac9e606876f49d7cee39ebcf449fa8813e516b528aa99f842fa47cff4673be1b714510dda11fb99ddc1a97cd2611ce4445931941943446de42d3c100be3eb63c036ab4988b010001	\\x1720dbb804304347709d998ffe11d2e41bed2fb38338c003b11a11ff5797c593258d76d63c1f6a611f32c87c4c46daab822ff24ee37606cd745bd6a106dccf04	1670255819000000	1670860619000000	1733932619000000	1828540619000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
5	\\x040cd1f86e9450306c3a16a363a387c0df96c6b92b7808de21e5c688c1b52cf1c6175e62c310e8c8de78a839fc0369fa595d12cc8333a41f293c6e71466e24c7	1	0	\\x000000010000000000800003bfbafbd445afdb6b10d5d03d481cd833ce569ba8e101d7ce5f5a51c47e195b4079184c386c6566b7931a3c9219c66269b854abe5de6225cceb7afab76a3073b5bbdfa1804616fb61af7d5caa20e5c06f7d09461d9cf367100dcccae7caba0ea119e89f564348461745c6e21d51dc13beec32a6fdd9fc28d955c0eb7ef5c80887010001	\\x69acf048c2c976a45b88823601fa5aa36524a079071cf2d6ea886330cb23a2894ca68118051796ecdb876b372e226021ea47efecb8f3dd44d68cd499e9279705	1675091819000000	1675696619000000	1738768619000000	1833376619000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
6	\\x072cab33895bf7f2851c1a1e46ef07f4c141b2fa4c9bf81efcd3bbf50e89f207d211dc745fab2c420dc215461439f04ba84082ce42c6d65aa0f86277d85739f3	1	0	\\x000000010000000000800003c60c0c7ec55108a6b980c5b6e6df17adb40b368dd8b71936634a15aadbd7fe31f7aa7a7fc1838a7a70068f1f48d36320b9cb75afeffa1042ca10f3f73c817a7000308914cb0a866bd9d3a865118f4f78c776b68175445771f58970914342906f5e152843d28f30ed8d4c16a6cd880bd52d4db9be2630ec34dfca54f556f3c387010001	\\x10634c949cc9e419e2651699147a03e1b48d9450f76c760a78b8c632bb883303398392c8a2b2d3d8b12f4cbc0eb60ada12cea71b7a0cdc5dc16e970ad30d580e	1670255819000000	1670860619000000	1733932619000000	1828540619000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
7	\\x0a94851a92215843379611fc49dcadd0df3c75e8b8cc521a80d3805aa631b0343a53bc08e90c7083b3db39172f7776f81f50252eeed5dad2547f3a6d20eabd45	1	0	\\x000000010000000000800003b9bf2bc74a0a8d7f4b72064613394dbb8e37ee1d859471f6921bc4b703ef5b5f4342c46cd200348240b328b7c27fd2b42421f2395431713b93c2a6b162f42c73ff4bfc8a9fc0e1ed6ee3403dbd024afd1a6dbf29cd9d8b2cbb417b8d67a9a52a0482eaadd6b94e516d60053668df0653a3b547f86fc225485492f93ced448dcd010001	\\x80572df928cdfe3cbf4f767546ba39d11abcf4a3544d956698875999e0b0ff73f6a007319228bd474ec283d9ce21d6b3225e7f2955db4a3499f9c5c96984ec01	1673278319000000	1673883119000000	1736955119000000	1831563119000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
8	\\x0c54269ea65e4680fb0edff83d04c9424d8c137f6264c155777d4d26062ea63a6f4936286d8431a2e2a91bc2726cab1762893ed8e1dbabe24e4d26d5d8a2a3e2	1	0	\\x000000010000000000800003e58dac4647563ec07313978705d0121122d802d157c897a21558dfc1fa72df0579b3e3e2454590a51093b82c1ebe440aa2ebb523390342b17a353564b1b240f6194b97c1531f8b1e680dd9207074358ac4aca84f3783385b8e4ac12edeab4ee5ae676d70b46c51cf7e11c8ecd8608e47f0202b1c9c1ae673611e38b86d5720df010001	\\xfcac228ba0b0dff093cbb5b65b09cf537f8b5c16c466f5b51c05b57043c79579a92ba9a646981d15caeb5b2fc71d85132ee9541fe57117570eb352f7d9df090c	1654538819000000	1655143619000000	1718215619000000	1812823619000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
9	\\x0d2c072e17c652b3bc30df5520b7dc1444079b21e5c3be4d89a58604eda4c83e02b3b8f1c0f198b3c8ffd131146ec7bd53cae16972fd8e34744b99591feb4299	1	0	\\x000000010000000000800003bc5ba49dff58c4d5c39ceac1ead68c225f5b438a8f8d83a873f4da847b15fcb52ce74c1232f9888788e6659b375147a02561e40be962373f5e80f2d28a8743622b45c65556e704398aa4af9d972051431697187c83bb03c5ddfd5e6a3c1684f79947bc38a725be724e1b0c888c4eab4a732ef6f6a6030000db3167dd527d93a1010001	\\xc77dc4984d625cd369210aff2b4f37a7e3395b7c018bf89c0b3c2f8ea28782a4fbc905af72a1f7b5c039c9de1fef8c56a2f78387c4b04d12ddfa07bc37cc2e0a	1682950319000000	1683555119000000	1746627119000000	1841235119000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
10	\\x12a085b645a1663a800e529e841d3593424f6e02bf1f06bc35daecfa566f1652c7df2bcbe93eccd8655f4b8737dc75f6ede019d4364a0e06fa311718556f9fe1	1	0	\\x000000010000000000800003c8fc5adc28ef035f510d5f5dceeeb3f8159e662e41b7c48c4ac198de3f8daca6cf0c5a7172a6c01464b570cf20b525de74c7f597440c7d73f70e20662b6ef386fb35fbce3c99b4657a70c500f4c140f8917c85f216a5f462997e25941cd132c01d1b4913385e9a7e2898050e2459ff4a7d4327f13924abdf3838c4b795de272d010001	\\xa2bd3980a26f2c22bd181e9599e31cb926b6d683f6f93f9c9ab6491b8f2377de189acedb7ff7c4ab5351cfea5648fd949b4e5c71757c8de9b5101807ac7fc909	1660583819000000	1661188619000000	1724260619000000	1818868619000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
11	\\x139467b8d05eee7cbd2593e544291b8636e665562e8583f519f37ca56a7764aa04185d8d50bea2a12a49998a7677822d3d81735e08728fcf5c129da15938d137	1	0	\\x000000010000000000800003ed7f83a04432ca029e98854a7d8045fa7c5bc64eb616a2091d9d0c6c311170501524f479178c15dcb2c25507af8f40398cd3ac08573844c165623e50d81432b1ade88e8a5bafecb79b1ef9803382e8ed12f4860a1cd9282395a9794b2c90758a3075fa6922a4af5b1c388695f6296a4a644265d47e6c54d4406d74d7adac613b010001	\\xb762edbfa80ca0b689438437d496a484df56211ea66702c6461e6f9ab06ccf3a00156b5179b93eaebf3532b8fc2ce04518bf7c97d962c86c999a270541810801	1659374819000000	1659979619000000	1723051619000000	1817659619000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
12	\\x1488089355ba829865a2ede38b492fd01a9c829f5b434cab8996a873bc2f9f7095e6529d3d56e856e30bd9af38ec889aea1fcefc8d72caf9f9afcf19c0dbf9e8	1	0	\\x000000010000000000800003bafd97f55da5ec11f054e9bee564253c5cd2a0a7b184cbb97db2f683396c425284c5c53698bb39dea5d96b85da0abad5d5ed18a668ab07403de73389448e3ae9af8758be34e47b614b4d81981469483d4b8419e710fbcb254ebababa3b5b3d0a0676bb59f6c54f3067fd766b367425dd79a88d9838112fc6416941bff04bfa1d010001	\\x30c40b7cd6c59390be236a19db378ed567fbe0ac44a84e24bbc73a3b4359cda9770fb750247dd283f01a32f013e2ab36a8777ded5a6c1781c8dca08f20066808	1669651319000000	1670256119000000	1733328119000000	1827936119000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
13	\\x147454ab30248641c6de454a3c8c69709155e595768933dffa77f0970c667dd13f60b400d42773713cb34cf2740dc5c0c7d0b9ea7f5c83c4a583a16ab6f3c667	1	0	\\x000000010000000000800003c0594cb894cf21388cdeae77a4350d497f50e8c78ad96aa183563971f2a6afab37d4669532312b873a699ec057738c5761c18d3bd38d5b06fd1aca670f5a0d2bdd2f3b229970d1c64f9465a96e6b6e66f2a1d973382dd3da2b91aa4a661e617c31ebf6fc920fbb4fb829e8827beb1aba26c36e51beae36fa200403063813d833010001	\\x3d7586085b25db703b1d11a33d4d7b8ed3cdbcea03f17fd1ae4146d6b25c1e9ff5ead609bb89dd00895af1ca4ef1ae2aa50da4f13d73a22790704848e509640e	1657561319000000	1658166119000000	1721238119000000	1815846119000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
14	\\x14ac04e9bcc769c4eff986272a99eadd2ed64ec784bd0649119586a0559ba7b666b099ba8d7f45f8cfbc197d183cad2d13fee3af460756c6c10b7566921c937a	1	0	\\x000000010000000000800003e2700d32474c9aeef7e72e9ad0ec82c46f6cf31fffe28d1b59d5eac0353cfd73624dca4cbb3fdc69be98be345d78080a92b487b52c9682e8068171599db308836648700fb859cac9cf75c11a6035d9cbd5f88c774b831f54010721926aea1a617c6b88aa55a3cb25f936d260ff614d7181f7c0488feb0c68787c8d5ce984eccb010001	\\x335d00e6f49fee9c323d1815352f2c8278c569706d370b6eb313465eacac99b830b6ed330239eb0ac40bcf4eaa158e41e2ec833c801c75acc5a4fd75768c670e	1666628819000000	1667233619000000	1730305619000000	1824913619000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
15	\\x15e091117f1aecf679e80a1134662fccecf821f0b7a2c5f8b46ad0ffd3bbf50d53b54dc7212878540105c0081fa1b3f84ed2ed6698629408a316dc9f6e012399	1	0	\\x000000010000000000800003a6ad13028ed47096f7b22454d09269a2b19c62baba93f2c3786f6816e95e2c268fd992bc1b0954bb29f1bf4d7b522c7b31bda2a45f19078f1de6fd8b0af2fc22c2e3ca36bc7538c4fc04a26b8f96a341be2f4735c1dff4a6dc93bf76ec04cff0b3bdcc251d08c38c20495ed69ea0056f53888fd2a89b99155f95129d886142c5010001	\\xe1787c9cbc2f2a6abf416c08da9dc5a8956a37ec8953899661f4439a3407ca669de41f4b1f3363cb455b4614682aca1a9f6e1ee857659d4ebd42e1ff4e58f80e	1679323319000000	1679928119000000	1743000119000000	1837608119000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
16	\\x1640feec0a7c084b617fc6d0b882ab21e49a99101ed91a70c63cd20b5345c0b6465c5e68211605a5965f8124095edfe3364ec2889ed545c270a06852368bad32	1	0	\\x000000010000000000800003c38db41b8915322801081c9a8cd0fd481185af21739b8d8ab5467f9ccc2697b5768201cf1ba79aefbfeb6c60751b35279cea31ddbad471711de954333c6640cd77928105c387e3cabebb1b2cf2269a3a8be8a88c7b5a57e087e4caf319476bb3386905d1150bb084902857517024336669df824aadc4562eb73a05c5b4593cd3010001	\\x28a0110db4f89dc058fc6a002257397300e81d7eb84b07c95ae07543c9113310030ec7a457a09a87464f510c1eff633565c92e5fb0a81836773923c88ac94e08	1675696319000000	1676301119000000	1739373119000000	1833981119000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
17	\\x1930fe6a60cddbbffcb071847d0522420479d1789f3c09287351ae3915d616ff1481f2a369e915b2d943957c8b5932a34652afa5bbe7447278f61f70eb05d4a2	1	0	\\x000000010000000000800003cc8060c42f401c9946dc72fa91fdc666f832696a54a50a6c448fb8cdf2c9793a531bc01730e656abe91171f5a49068d65e52c5f42eb0c78f902012d263c0e3fd5eb724bedd1d29575d70c789db4966f8bed224dc798df3be80eb283b67315a7176b1efe46ffcd85ccffb33230b1f9612fd9545d2251afcac0368bf443dcab617010001	\\x5ca20babb56c11c0f02965a11c30e8f3077d7a4b468457d02ed2f075934207d409d38d2966ad28ba81916bdf922fae7f41f51326fd801df5149fa21a6d11bd00	1667837819000000	1668442619000000	1731514619000000	1826122619000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
18	\\x1b6c2f2131eed89f9d348cd226db91be615060ca616732151debdc3900f45b6ff2d8a4aae362eb68340ad3c87d02a9809de89ae1f2fc8ebd629ff0f449658aed	1	0	\\x000000010000000000800003b699ed10e2411ac2c3650c6b6bc2e0ceff6f430c3b61287dc42291858f3343a23614c09645a9bbf480e8b7f75fbde74684130432d8f02beb650b79d889234eea40bb116429f45356b797b461c224f20ca05d4f0ddb8f5e9448f0a4a2c463ee9cd4145c3a7e28fa28736a0abba06e0d9a7b72c93e62bff17b6a1525f8d627e6db010001	\\x6e85df0a3e7a016fad4f90aa4d6bbdd60a74614e2cb12d30c41f7cf0a0d8b846758e71e59ca0e5446b50cc7b9666b2c370ba0b7052ad0af7367876bf95cb9b04	1656352319000000	1656957119000000	1720029119000000	1814637119000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
19	\\x1e2842f4e8e09b3ff10d0bf1825aaf41c78b2f3de241a8c59d83be8e660523c1852e2d68b95046414944822530890061a965face8754bb82682b688eca947b68	1	0	\\x000000010000000000800003b5b0bf87da7b75be3b7976790d69cb49f8082722e8e11d4b09c53e52f50b51f41fac53895590951856c7882375f3a9fca46d2768221e47a1a2f01ffe77ffd7bc535867a806c4e5be287251270591d55c42be9d0531218ebfbb890f4c164fc3a12a64f085c74f8f4b77cb8ea23b38c2cb1737515db3c63726f8983ca7591ca597010001	\\x59e945362ddac5ffb27f4e1a3836e941c09ae15b6204d02622eee2aeadb9ba1c7fe5e4a260e67bb9637491ed9e2e643ac5b49343b43bd976af4e030bf5cf9e00	1663606319000000	1664211119000000	1727283119000000	1821891119000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
20	\\x1ffca0cf308134d98a4043c2201188d73d8df6b7cd6284ab6c6cf6127ca87e051d68ca82bcbf9e6cf01000b5ff57dfcbe49b53e5525e89c06c9a99b2f161da27	1	0	\\x000000010000000000800003b967f95a79f3890ffa4738c38230e7664bf1ae8b89df84cfd4461a97f8e1660f857ae6a30e6b2d5137954bb47c48287d2df200be464d3eaa5ecdbe36fc68a1506d7157bef416a1a49459645925e9d3049f643b8f6a175af8a5cde97d9f93d9e5a8856f6d3170036020bfc38aace20e23d1e81269afda6875cf46630c89ab60db010001	\\x53d262425ae8d80bd7cc92afdd5f6ce2acd5d08385aa819c39acbb1ef609a49aba1cbd65842a3c26701471082e29ccd2a73bdef746b3c4c07f424f7d2845a104	1681136819000000	1681741619000000	1744813619000000	1839421619000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
21	\\x1f987f8f71ecf31da2ac74f789b2baa0d448b9af4d048e7629b90da75be1397a74543fc8b0e0f4362fdcf1d35936ae0b0f287266235b4d2087da514e35467189	1	0	\\x000000010000000000800003b7588bdc9345b5da029124211f97504db3db5b5c706048364f5f98147cc36c85f7fd03449aa7b834c15eacbddc2656d565472c6a143ec406fd3549f79f79498d4d5ecd2cee7a845c7d5db1766a06ab1fa1b3e84c305d152f6d3bf02feff8a161ec7ddf53a0e10b7130c5ab94ab89cd2ae81eecaca9f1f9155698ffa01ba69b71010001	\\x96993f0d2fff901a6b07d228acbf01feca97d871145009a076162979f6976ced76211ffca3e8341dad544586ae49bc6c3ff8356141ec8a8aa774d2147b9a6909	1660583819000000	1661188619000000	1724260619000000	1818868619000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
22	\\x25a4ecaa03253a7c1ba33f5318b89c93452ffb7718e4f90ded2ea39865c1ffe66071d0f5a0733de25c5acf09a2bfee4f78b7716f089a5ae55e904e2512798e2e	1	0	\\x000000010000000000800003c5e0ce4da151f2d74b26913fea4469af19436db0a8bb1b0598b7328f6313d082ee7243b8bcd22648bb90473ca417fe4b6ad20d35d3f5134d7c114e567f70bf8bcbe73f153cb915e4625d8b60d8adcd3d7a716c582a5d88f183d2ac259f8f237446797952c698d04939448fe9b1eba84d8f970631f269b2aa56340e49ad442e77010001	\\x2ff6b621fe98d0fccaf884ea58c82e2ae6fa2b105a803021b37da0c5c055db52067c2f1fe062f258455e52b221b24a366a7c4b953dd0220e390bd7adec8fe201	1663001819000000	1663606619000000	1726678619000000	1821286619000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
23	\\x2eece63efe16c36ed0b7ab7588a793fe855b557f666662200be70b67d750d5f105e38ecb6f812fb3d525fb2ad52f6d9f71ead9ab576969d5ba5acee7958469d8	1	0	\\x000000010000000000800003bbb157bc54266396020ba13c371ba5bde3a9d4cecdc3a12d29773af42c0b1732f54dba34bbe4bab3278dcad5a12ed75db8cd11ac0ea1e2ff7168761854ef6b3d43b6df216dfb1a5a997d746a569dde3f9fce33c79cb95fa18201476ace90f3d8ab23b705d5b1c31f64d98dad80637c449b1ac56521b5795b90a00f7a2f9237e7010001	\\xbca63172f29277d8fb432ed4a022ed0335fa790f1e0abebb89b7f7f91304cd2cb5361e9d19f60de4e588ee6c4b5a505007cb214c67c7b1cc9fd32d6a08331e0c	1682345819000000	1682950619000000	1746022619000000	1840630619000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
24	\\x2ecc0ab45b29452ba140b42735fde7739f596bbe58df341e4afae9faef6e9515f8751e909301c5f0882a64f96f17e0f9b570f0775caa0dbea1e7e9efbf9b88dc	1	0	\\x000000010000000000800003f031bc7b3457ffe1542f027ef9536c3941a9478aa068c9645cfa5f31b13519ee544b96cb90dfb30cb7dd280a8cc285f7877b5b2ee73d278edc0ec9548e2b7eb1d5299e7e977b9e71e54adc4e9ec90013f213b9478996c9ff0aa20af3ddc310ac96acda53d3ce9f353a7146d67010307ed543b50379299be56adf09d550ebd7f3010001	\\x18e6d1901daa255ed6bc4954a3e31edc9d5bc97b048ca4b8c2b766159a9ae1189e06cfdc0ce2d05ef29806ba1958915dc6d8c845fadbe6bdedd3913490f5fa03	1678114319000000	1678719119000000	1741791119000000	1836399119000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
25	\\x2f040de31f779dde4d792e79a7b9c023f279005270e2aaa8c910d31293083fb73ecc5395c2dc3dc27e03bf0f49a3358d0c0770316a50dc869cc2712c5132c9f4	1	0	\\x000000010000000000800003a9c6ac9990c60847b70b22db767d47bffdfe720b6341dcb0440176ed4424aa16e7a1885817bc760b7482a24986494c59a3a0185f5c05384da69d9e8dd02ff4f9deb54dec32a725dac2d0de023e98cae0970d1a9e55d2c1dd30ac7bf643628b39ecd109499290e03dcc2d9c240585d05fb508a0b6f1ce0e8757d3ff8b897c0bb9010001	\\xdcc4cc77bffbc46569e0e805e71440b84b833b8bdcac0311d937424680e1210f795151ad9e5da27b73365a6d0531e5e37a0c4d68aad366d267810408f7355206	1661188319000000	1661793119000000	1724865119000000	1819473119000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
26	\\x33106cc80d41dfa5aac07f19b560a9f06f2880312b85c7fffc0d4cc94a59229424253da8c1c7c735284c7a1b6384f165c475b6b84d057370a0fe12b6ab221681	1	0	\\x000000010000000000800003b80e6c4a4e9ceb792af40b600bce1e9a287f7a5ab363ad06f49725f49b30b8ba232424e5a2e2d57d2aae360d8aa3777400011cea2887096de279549d3ae43ad90146b55e9ec79e8a03db35b694d9a6a93563addc4b11d1a8bab42d2124b055bf7dea61491a77aaa8a5fd2e41c2749363749f6b7ee76055ae26614a42680136c7010001	\\x431d44b432d48b3ad4f593a0311a480f40c4f01cbcb3aa91d9d439162a0eb898e90c9d07ee0ff00d0510487ef520d63b565832e38582a984c57e2103618cca06	1679927819000000	1680532619000000	1743604619000000	1838212619000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
27	\\x3b0ca1f6cc54d4ce08b2426b9b889a23b76ab38530344053a076572c56a52b47944c9db3aeae7a8d26befe59862a32a68205a278b54012aa26d0500ac5d8c388	1	0	\\x000000010000000000800003d8bc203730b2d6c5b17451ffe45f7a13deb083b5262a24f5cfcaa7fddc1a853c9b66cad13d3447c03edf04a6ac24f039de18dc303ba4d6dc4c06e93839accf7bcc52f251464ac0cc704746debff1b9b6cd9d9d59b0eeed6ea967004319ad5e88521788f325dc05c185d44fc89015d9b048c5cd73580c927442f5d9dde4a17521010001	\\x32da353922681a1b689e40709b9feec2a1fb2ce2aa83aafa661797638c2ce045d0d7f49b5f7d3659b33a32dc2073f0c53ff1579a6617a50a1d9483e4a1a2a702	1661188319000000	1661793119000000	1724865119000000	1819473119000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
28	\\x3f507e44e018efc04cdbbdeebe015983fdadb65f56ac1bddd374c3099a05a9706142ecd17130d7bbf6c969dda4b4aa52e358dcb7d4fe34c9afc2d37d12522b6c	1	0	\\x000000010000000000800003adc9eb936e2f17238f1c7df701e88c42eba6ff53250e52d46e1a1a7deb0b546c852da4b39c2fb05c88dd363816d7c242984c1cc30668f43d74492381dce4224da541767cb06358d07b9fa6964077828d7932f918389240a40168f2f5bb045a952fc0113c899e1223cfa48606f2b77089d7109f54a431ff36ce3ec72bdc513a7f010001	\\xd9a5e6401b57e6bc29f76c09f8d2a28fc09aebfa88a474ea8406374565f1012df6df2a765780cbafbb44f5b7490961355046c82e7d714f8bd84277ff8320d905	1652725319000000	1653330119000000	1716402119000000	1811010119000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
29	\\x40d4d453df07b4c9ec3f91df893b9cd5c0cec25729796d679b16fee727b6076ae459fc35ee8da43cb4060dce80ddb191822f83163700ca52b0593da340702e64	1	0	\\x000000010000000000800003b32d940740cd9ad66f8d3daa1fad0a119a8cd0b0f66ad8ee50513255840201868c3747e790a361da7289761fb89e0ac6f6a5a6315e61d2a605f3bcda65ccf58be219f38b2d15cd595334aa3dd0453d061d0d92bbef6cfebf8cff7c631ae1130eb07198c11f5490022357d2d1d85ddcecb804832211ca0c2e2a2d906e10e0f375010001	\\x75346144ea999759071bff6470262c678538b333d26359002889139569b947db1a9578932e7261130a4cfef44a97ba8b8f23354597c01006ce9ea536f75ef60c	1658770319000000	1659375119000000	1722447119000000	1817055119000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
30	\\x4be0149a6f4fa6677379c4690ae2581928820749bd3640e536b03e3734d3a89d26850f0caed19c00463cf5a8e36cef92e98a206d7bbff02fe9b0ccfb80505fff	1	0	\\x000000010000000000800003be9145e87c24ba8d862e6e85c0b3bb73780adeb57c3f15d1686233543851d44837911819fb5d8a0cf6443f0c969df62c8f67ba16951b78ffeb2784b305d94dd47a9d1d15b8100b6ebd15e86a100baa370d2e248d8159da039e099b7634ec5cb184504f6b64345ec2bd05941257fa0fddf25f17991bcc54f645aecc62f8a8384d010001	\\x5aca5b0b249f398eca6e3419bdb1b13376e244364c32590668e8aed61513461470456e4d5b6a8ec626e5732c29e4fe428d2562dc704bfb5497a7b893704e330c	1678114319000000	1678719119000000	1741791119000000	1836399119000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
31	\\x4dfcef9f52692529d65d5e80a921b1bf4306a90f33b97554b0d4853f1b2f4d94d672fd56cde9bc4ae0bc073b7d60af46514be4f6fdd7ed62db11dd43b36965a8	1	0	\\x000000010000000000800003c39df8cea7759c4733985a0e1f284e6f7e5b6f7fb05ab073804b2f21b6baaea74600aa2e2f6fb57d6a30c75fe45127fb1ac7c650810b4a68866535c1ffc8eb90e680c61192173dc2036b6a6138209baaf286e50796817f89ec7fe25fa6fc9375d517d03002618356da4270949901cb98136ffa1f0ebc9a2ab857dcf2c931751b010001	\\xbd264922c5cb6f6330b0d64f99ced161752ebe752e63856de3b9974413c7936d3d14581ba0c0d2ec70057b1ce0f6fbaa8c69472576fc8c8c3d1acd261fd0050b	1667233319000000	1667838119000000	1730910119000000	1825518119000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
32	\\x5098399c947694ec39bf2c92cc60b1589d02d53b17dc883780637211efe1857cce7af4e5da4e00c95ad0c9a44eace031e1a1fa8c5bfefa92aac4259984fe9283	1	0	\\x00000001000000000080000395706c0242e380133762b1402da2590de488350c1c7cecde134a5c6c13b10193194a7baafbc729f1a9816a4102804f26c10a2a92c1c66957cb893a4b9db429040c64bf8166e8f9c3d4dd3ef2e912d0cbc6669c86f978099b37c7cb0e6ab6d8370956de3a6f595359acae526fdb65aa491a727a3619fc4e887aa06d934b36571b010001	\\x1007ca7e0682e2f7c9e377b7488d38f2b552431f4a014e318f6275ada38cd88dbb2bba89e8db1b7625f7639494dbd25c864c0eea8ac612b64c78bc587c645b05	1679323319000000	1679928119000000	1743000119000000	1837608119000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
33	\\x5190436110eadf7a948e4750353c864df19bd2b2b44095e9f271775b0d2a8e9d360e9610a94dd04a13fc20b66f1cc5e01bfea58902203b3373fa851106c684ff	1	0	\\x000000010000000000800003dc9939f141be6b12445b45e3792f24a77c80fc0aad27a3708353d8e9eae233f1be0d296284b151e4a453213f107ae9ee919f4f9114b930d09438b7fb55ee0f83e5898914eef6537154653e3c4489c67b458ef5479bce4fbf27937bf7578160e28ab5c2ed02c221e1897226e48ad02f74f30240504cb101b1fe03399b8f891fc5010001	\\xca36be6639509d883eee075fdaa4f8793b4dbe047460de61eb2d74d3414fcb44a25658f15157b2e7ce1d87891f47a3cb1136f22c0013b4d875567efe3a0fc403	1666628819000000	1667233619000000	1730305619000000	1824913619000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
34	\\x552489b4c4042a57826c260e7c653dce9b29c8c2951c4fb416579e9cf2d955c11e6c7daa36c1ff536ed648eed40e6cd658d49f5f23e3424802315e158d29cf21	1	0	\\x000000010000000000800003d1af0a7d78293347514d2476e66e51a69ca9bc5b0269e81904c864d600aeee4577b7e4126d6f3b50bf288b684866672cac65eb0d5e844e8f0fc899c4d96661c6a75e0010121e08bc79c4696edd8dcf81fefb127353bd4ef1dfe30c230577d0ba497f22af9db4380c4959d005544951694bcdc9e8e1b49f6a96d171332e534a4d010001	\\x8bc8bbe2048b9b4ec03955fea2f5798ad9c3c816c7842e9736dfa8ef0c8ca38fedbac0473624c437c34e996112baec10dc0afc9c60752af634dc05ab3eb64608	1681741319000000	1682346119000000	1745418119000000	1840026119000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
35	\\x59f05a655edf77b951a336b2b8cd5cc4422529286a4fb3a96a38801819b706474630874a3dd682eb6fadb445ec244b170dbcbfb0c2e7479e8047a605f6376c04	1	0	\\x000000010000000000800003c3a30aa7863d7f6da71e07e8ff9b769e5f16fa075a9910cd0a2a002f19c8ef47a1e5ee58c78988fe4eea3bcf92e250e04a3733c42a91a4b34db4114f3f550b5dc16a9d00771bee253ca68f6386d559310e44dfec40b897ecfd6bd5666467c263cee389f1414353b13de396d693fdbdd72da660579e7fafb587f815086f98de1b010001	\\x711edbc6cd50d09cbe3b7ea6382db50d51990512636f71a2560c2e1085874ec3b86f2b948a55c0cad6575b740ed9136bc2a795f9ecfd5211169688a0189f2805	1652725319000000	1653330119000000	1716402119000000	1811010119000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
36	\\x594899550e4728f23eda3ffeba413107c554a10ef43bddee1438be1a7bb74ef966baf056b9e7c00c1c64151d2241522a0582836cd03734bfebc3700e9cbd3d47	1	0	\\x0000000100000000008000039e063adfaf447ffd5990dbbcaed2c0be619da54b1c6fa680ac1b94de073392f44353523362deba184645aa0a3e3061372fa03c3ad75a2ca50c3101851b5eb55fe3918fcb8121632a5b0344166c2e734d826c7d517830655579f9c763a2dd9c587f06ba3c01b7b23f8b7864bfcc3531b1327bf1f260b3f771b7406c597b4058e5010001	\\xec7c7d0aac0646b37e4683360275e2f219438f6652d5ad6dec1684a96b36aab689aec57b1755cec59bfd8b7e87742c4ff026b8203157aff9faaac7b490a8ff06	1664815319000000	1665420119000000	1728492119000000	1823100119000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
37	\\x5f584ba5e01d67574b36676ba0533616fa48d6898ff276c1d43deea8f6784c54b6e78e4e7146946ef7ae45a1846865b6523ec4f6827ce3e8fb98aa725c975bed	1	0	\\x000000010000000000800003b23e51de4549d1ece86db303cde2991086fd5216c7627a655dc131b6660bddc9318db9ddf83664af3ceac81d5f6daf9426e0ac30173ada6f8fd68a219878c776c69833eacd3feaff885814d9835e67bb065b0b5c29fe1e049be922aee4ce482ca4086b7bfc91111ac6d9d44fe8a4c2655d7a5582110be1313467e2a101dd4ae9010001	\\xd506c0c594f6dd9c30b4c7198d2dc20b47827d1c738ca5437bbc4dbf9d3afd27f957592bb6e3a71a9ab9dfc5da432ad2e333c6761ccbb84e9154379d04473207	1656956819000000	1657561619000000	1720633619000000	1815241619000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
38	\\x6368c3a09b5d85db6beec91fc0f88021b24f98de464e337c4887eb14b3cbe67b6393852ed4cb1fd6447cf2b045516f0da09f3dd4602f54b4fcd869f896155e31	1	0	\\x0000000100000000008000039a28479cbe2a70009b5b2221c4872af718af69fae21664d9d820c9838e4f4221a8ef5a2d44b8530ee102afb2a202a940adbcab6746a00f8c0a27fcbacca31b944fe784d60beee7a2c9bbfbe310f83333d1e1af02ae28dc89de21308e08d47c3c66337c77bb5eb0658f7137b2150291863b648689f85d941d9817ae3b914d072b010001	\\xdcfa0b12e8c5210ab8f70972bd9e43e1d1a264065fcbed41d10deaf7fbf47472e9c0408dac7b014d4b06e9a13f050b26f4b24c3ca10a7960bf1bc25c2164e60a	1659374819000000	1659979619000000	1723051619000000	1817659619000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
39	\\x6870f9e403438c072c4751d63c2bdee4ab77009ab61b1a1f0eef49d5306499de436d2e191295bcabfccb02510ffe07383d6a0e121aa5587c78ec13c870d1d559	1	0	\\x000000010000000000800003e22612097b08f7597fd780b3ef7318b96fa72ffa2db9f2e7811593c8e3d533b9379f5657461565c80747ecf0f5c1ba11e83a408069c2fc39765351ef070968f3e2c446e00e4f6e3640e559f3e00806f33ccca8c47bab8bed0d8d528151771c4aedf44dbc9764155ee20d8d67bcd758ba20556cb12ee994b210ef7967c6e04817010001	\\x7b8fc0501a4526da85741bce8b44b902ca021763e8a2c0785f53d6d68440d728182e85a64f62945024a6e6c97321e600a0da8ad19ea8ade9193952ef945a570b	1671464819000000	1672069619000000	1735141619000000	1829749619000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
40	\\x69c856b181910b3461da5fb345dcf4b5a42e67c3d4867ec20c4dc175d24226890b826802c43dcc06fd056061ab1c9ebf5afe8e835b166ddc86839fbf1c8a2695	1	0	\\x000000010000000000800003b8a1dbf610024f7f73884789b9edbe34b0691e065abd00a584e560a69ba98fafadfc2286ab01935947824c2c1c1d76960c76784029eaa30637c98f2742f8a7b25ee42f599d6a73ff7093f9705d10b43ac7610737201db4341f9b787ca66f824187afba6c325328e3c0f28b8f9d4601d34dd24d62f99639adc746076afc303ab5010001	\\x24dd2d574c719630889734ebceb1555c7febb48273b9aa5b73717a33349bc084f5f8399bcf5f6a93d97de82d5f18016484b17f511d3857bae003e31db824b70c	1664210819000000	1664815619000000	1727887619000000	1822495619000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
41	\\x6a90b399c8dc009f24f3df471b9059676870475524e6d5475cd623666dae2bffd9cd48037b7978e03c84f566dc18b882e75bdbf09a0e6d1871dec5f82db8986c	1	0	\\x000000010000000000800003b26e94ca99fc331c36042c5fb51b44ac3e8d0f42c6c7461fbaf4ec42bcd3d195cc403878e693139162089258991215b50940665a475932f34d7ca28894d8af26ca6c40a1dba89bfe6d6d89cafa103fca00788f3a9216ab36998355dffaa978002d14a8fc24c35d8fd79e495578e54a97d8d4367dc71f55855e98481c8b974e45010001	\\x504ed9cd919e6ea8a3166fc70e2ab4bc00be6afa1b7bbe738c2d927ec41c7c117f58237bc7b509c6a9ae65ca4b309a57c7a00e51125c86644fd2e4ad5b2cf50a	1659374819000000	1659979619000000	1723051619000000	1817659619000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
42	\\x6e34f340f98ab739c10a4353fd312b9f68b351bea7c1258fbc016403a835ea998cd20004e052dca1fff10dfa86f5df358b893d7fef8f215b230d1ab454911439	1	0	\\x000000010000000000800003c565a4062bdd0169a8d2c91564794551a66d20b08e0c9f57306d5f5ce260e904e34028aa189b78b09b477231e4aa88f33b2ca093fdfb5c99caa961044bdba13da80974eed482b01c569fe6e42e990a9d4c6b17b183dd9896c2a7af954b1c4e50f84592f63b30ad1e214de82028964c719751cc609213c178260554b356b86e61010001	\\xe6a6bf63e63eeacd306303c90a35c98a484dc9ce3d4c53b5ba9884d8a5c0e8ecad4637e01bf2e8aed2f752053caa63a5aa76f8f1f5dfc306f1294fa84000130d	1670255819000000	1670860619000000	1733932619000000	1828540619000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
43	\\x6f20b4b10227b9ae8f28aada7721ce296e38a8101c1ae8b9552569c28da3e258f45237f8206fd91e8149442e290351a5ae2a57577c84972dfb0a00d085e6a858	1	0	\\x000000010000000000800003b6dde947a2ba647ad5aefbc04d46860168d5314ed55d2f92416fba4f8c0aaa9e2100732cd0723decc6b503611fb485a40370c270257594a56a5b6696bb6600aeeeb990b3bc93fd155f4984eacf9352f9007e38ba6d219a558f0a1432efd909d4378716613c08eff89450b43f90175c90fdece6e3e5ef0d345888515d7c6e389b010001	\\xc4555433ed01095b56254e803ddedee9f1e6f499e1cb7583b92d8a49cf51318da45b6e563158a478c265801560793e276bed220948fbe9bd196b04e16305c307	1657561319000000	1658166119000000	1721238119000000	1815846119000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
44	\\x7578d2f1d0878c1098b34f0007fe0830fac4e5811c65a2b4f8e675e56e38f5f55d94daaf20ff993cff7096652f67d6e588b1c805eb21384ec3f68e3a943f87d5	1	0	\\x000000010000000000800003c7f6d83b07463bfd4394a8eff5ce779846628501a90477234086e53c70bfb0bc15521be931de29ca79327291c3ee154c56d601e8e246a5e05525bf65b7dd6104a8afac644047a37d7415550899c583d992f701c940880f0864faddd75ba7c0574accdf114d0e743e1bf90993709212b5318eee55b6ab5868c0dd4a044e1edd29010001	\\x5ad92b9b4f1a721b7e32b531bdbb72dc980d4a013010d8962a5de0fbb3acc05564c0b786cdaf7d049977e976d25f0d95a17534fab539e2d06bb85e842395f30a	1658770319000000	1659375119000000	1722447119000000	1817055119000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
45	\\x76f8d5267b3d7148fa5c6a709001172af3649f8a4a013fba01d82093300e7d5c0367877f49e8214ae40e73761a4733f7272a4d99ced652f251011ae0c54ecc02	1	0	\\x000000010000000000800003bea8e71639822d47c17980581f90d53d44252daee1e50bb99751a079e698f3672f44a7647bd5c218a8dc8d95b4d42bd14b18a3bd5af6c66691d5209bcbe8c2c50666f694cbdb7594caafebdd1786411a92a1be7423458ce48a93389e234469a7116f7e3d5bf2d7459597e7ae0ffff337976db1b3d32659a3024663e5dedd4225010001	\\x1e3da1b940ce868350d2a723359b20fee6b505c7569f8e39d4a4e7f9463dc789d8a4cf794a73edfda77614d8701df5f36d8021274c9c0b11e90ec99c955d7408	1651516319000000	1652121119000000	1715193119000000	1809801119000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
46	\\x76d89f34d3d6e3721fda87b68bee3a59e35dc8a1886be239228ddabecde3cbfc63b057fd1da1fb8bed36507cbf83a7cacac4cd28efc59df9812b658394312d8c	1	0	\\x0000000100000000008000039ee2f9c7ea2c63ba1a488131af3cb6b2716bd6459352217ba377c11f0f5f0882ac021ce5a28f882d1ab8df61abb0a35ca7f20b6e5606e10b69c2d1a907e6d56e5b91e79c454ed1943327358140f74b4be743932a67255a603e5d3fd7c2e36f1bad53a00b85f0cc738967c6235d054735633616e80931f5660cfe9885f1b9742b010001	\\x67448b37e6adb83444e063545b99448dbfa3cc7f50be553dd7151f5a80ef7b2df46582fa6a7c4099a0d3e0bdb0778a373db3e329a9ea795d78351de7aff2720b	1658770319000000	1659375119000000	1722447119000000	1817055119000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
47	\\x79d0ec7b885ddd3ed5028e8e40f4d5715fba5c3148d3791a4f4463ba241db3dcc8ce3a8dd69cd74472004441de624f73cd3698f2ea6fce87315ae864969b9931	1	0	\\x000000010000000000800003b38da5abaf11df6382c1b0792eb3ba90b70cadaf6eb3a4c89e4617b31d0eeb29e4579dbe7c491cc7ad23923d9e36512481b8a6e28eed6a02d182b3106ecc07de7e304d74b8e31bb5a7f566ff6f99880a1aa06a77fd1bda9559f5c02929d1a4c124e383992346bdf2238bddf613423b6db5d8e714c885011a73bbf5da81bd20e1010001	\\x060708e88803e22892812250d3a2cc92630584e554d3225e7121f6d5e778613b8f11e449a770c2b519abf0161c6f90489ba09074d35212aac0259682c8390b08	1661792819000000	1662397619000000	1725469619000000	1820077619000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
48	\\x7a90307112054163ac58866d87bc1de1efe2b62537e484563b775151abee635e3b67012745f99b2cc53564862d04d94e9b4ad4c02c01a3af0bc721ed9c822723	1	0	\\x000000010000000000800003c4360fb4b4f2d0eded1e71bf15787d7d365268b0e510771a4c403482e53dcbf1dbccb6435a6b5c1dff57bd32ac6e4d9acc358a2a75424b714bef1c26e95ec15f8ce29f3c3e4ef1e708c693b66a7272349d9ca89c289c301bc87fd2d9005ce3103300a2826e375080c5170f945e97473311383767fcd4efed7de10a21e5924103010001	\\xc185b4ecf887ff308137a6811994bc474c03fca5d80b97aaa02226aa27d8dc3a9dcce3570da01ce1c3bdee6d53d7e931cfe72a3368afaa800a4d3aa8cc40c905	1663606319000000	1664211119000000	1727283119000000	1821891119000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
49	\\x7b48dbed47bf43b4f2b1afac57cf95cbfddf5767711c101db129eff7a614ac2847751fc4c44aebd302704d9dcfac518e5051f3e6db41521d4ad31b012a98de73	1	0	\\x000000010000000000800003acd3b5af9da4361fe255ceb119c33ab0b2e3e087182a26944a6bf71fed949011ced4fc76181420419cdcfe2b1123f6da4a3a0959d6418c0fcb174452671f7d69015889c046cc9a3fb1d0504d32fb7c6f1fdd5df2fd7383dfe2661b186ce0074411e1b16556f2903618426054608912a7f56f35f503240c79f716b9713363eac5010001	\\xbf6a0dd1c4cb9435dada5a097f8eed5d1156ea35ead32055b20e22de4003c98e83564895c2c4392b8fb8c74f9f05f1bd55f95e37bcdcf2cd7fe05546be6efc0b	1675696319000000	1676301119000000	1739373119000000	1833981119000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
50	\\x7c4896e25566550e6f669426c6b540f182131a8540840f335c370f3ce1a7ba6bef873a01ed3e85ca6e9a260f83ebbe5fe82b0297c1e7595e9e03e95170d9038a	1	0	\\x000000010000000000800003a3e4e0b3648b4e316ea42435f9be305b0c66af85345bc7dfa7268d6d7b0646d546f74dd81d5d1335eec6ada9aaa393656962c171c7e288777d37c3e6c3efcd2d33c7a558c3f0e3744401944f521065c37c331147f600861c6879fa926c9b2ecc0a0daf9df4976f995666d7db8a41189a834a5841ffb90edc90ef4bf14ff19379010001	\\x177aa63cc8113ba5a4dd8d786b8f7bf25579aee715b8ae27962c309bfa0ec59074eb97a5a8bff0d0342cbcadde307296aa3b63470f98315577a237e97d964802	1678114319000000	1678719119000000	1741791119000000	1836399119000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
51	\\x8210697a875449cd4369c10636d40b8bc0adfe1982058c77abbc709e3d890164ec71057e457e4446b90252700c23c3a74e376b76e92c0f4b0806a116e19d9fda	1	0	\\x0000000100000000008000039a29cade9cccc42dfea6dceb3490d0d761a11a5600775add06ed00e25aac68e091dc816c6542dad213bea56623c3ad9ab9ca12950c00ab43f1c57ee565f8972425b3f33437f58b7453bb0097a35b9ca07265d21b0764120a9fffaf78e8bf05225b35a4a16e1d70626242e0b27630221d7a4d94ae2fb3577e7c6c63061ffa8593010001	\\xe39306c4827d0602a6be13941aea8da17e4d903a8aa6d25723f5090ecf14eb05d97985c610c605681b8cea9bae2c0f47116191ac601f13d9e73b1e1ce132ee00	1658165819000000	1658770619000000	1721842619000000	1816450619000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
52	\\x8380dcbcefe1ddf5bf9b5bcea5e5b310b79ab1077570f4732037389263c0238e9a58952184d49ddf827d18e0856a4aa4cb3fe58cef8da300b0b1697ef55ffc7c	1	0	\\x000000010000000000800003b671e95c73587cb9720a79db7a550553636e8a6dad1d24bd236ff89c5f1472bd2e56c650e358a342c8cdeb082172009ef78228af3caeeac4b5499019032c3a0177601078a8d5fab3f1e43326b9cb7f3f5107d64190cd9fc76997313f474ea5515cf6131eb66e50e55aa20b94634230ed9d0f4bd04e0e6d17413c968832c424f9010001	\\xbf3b1e9f3a3a8bdb4744013f8a2e81aba024f730e88ed62e25693af4d1caeb4975638cfdfced085c50cc2601b24cd13eb99a670e6b3fb76c9f19b58c6ed27701	1678718819000000	1679323619000000	1742395619000000	1837003619000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
53	\\x8ad4bf2ab66e9bbac091c9d506e6a97183adf78cbe0b42250870ac6f418717978845c53efd5c1b149a48fa2fd50d661c5633be4b3a3cc870c58713e7c23805ac	1	0	\\x000000010000000000800003ce914b4760510a8c0b682a7a067b72989b78804707230de48e24b703c9e0f5cac7925e528331f1968e6e4bbdb4bb9b997958924f413d0b92230e57fe73520f6206138d5657f68fbf740df593888d491376216aa6cc6657b5e9add47b0eef1211896bb1a22934cd605786df6c02d1c5011d33b56c95f13a91dcd3c890f9b73fab010001	\\x23585e4211cbbf3c344bbe3b06126062d515019ad3e27c0fce61f1dfc7c2ab96273dfd8bd22e593443fc1a7da512ff0924db9dcd8fe75bc6ae84eca52c80d900	1678718819000000	1679323619000000	1742395619000000	1837003619000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
54	\\x8b988114cef8c230bb536511fe01e676af8a6e3b1c49f16c476707077a4396d5839bc77b7b51e1001d0711474b648a320836eca4df946b3eeb08df82d5a91334	1	0	\\x000000010000000000800003c1bea8f1abcac267ab58b8ca7322c827bcb9f445748126eca857078e9774278d98a2fb4839be50bad31d5064a3610a3e7b3e9f95a3c8692deb92644dffdb5ab753611d9e1124e954707f86407a4d0690ac33280e2c2604d5fad399a44d903b6074eda6567648243f5d838dbb12ba327952f33a56cb081083f8d6b41994205f93010001	\\xd945e45f08763644ee2d3c2757bfbd9157a8b36ddd825b7d285f8be3d56b1d5c3219c4822294f15aec2937d525d99a06aa09487304db5553ab524fa076cd090d	1676905319000000	1677510119000000	1740582119000000	1835190119000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
55	\\x8bcc04e2ce2ecb4a7f2c06bc19fa4639ba3ffee455b8eb6b260db504537a9176ccdf6c94289c9569678592db64399dff88e1946cfc53bca363b6eda5d3356718	1	0	\\x000000010000000000800003bd350ca5501870b6f53d54f5383b0bcfe8d6ff18fb96bdaefa01cbdf48e03a3ba65f8c89636dacf9f256eb1704877075fff2f6a4f9449ec25ac9e2f4b17235b39dd3ba8109ba01356612a72ec7e757812975efb42f34f3b36fa3f9faf9740cba4ddaec83aa5b9883e11ba67816cd43c89772ee6c679cbac194b0b58a52c97047010001	\\x37d54f7a0c94275101db4952c468cca6e4753b51363793a717fb1db0a0f6fa9569c8dbf2451377c496bc84cfeaaf0c0bb70300ce9c4322447135262602c84309	1657561319000000	1658166119000000	1721238119000000	1815846119000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
56	\\x8c505b83cfae43cdc0500d7d186d1c49dcf51e56b21039394a2f805365cd7b988a121abae2aafccde1f5afd24978707edc12753b25d35f0a1c223b74a9f5a3a7	1	0	\\x000000010000000000800003ccdbc68af577acbf45cf7a8c081efec11752aa6f80a9805b32e67efcf618fde80017320f584be50de1039ae1db8088492a1e13b3e9900d1ffc489c11c693f8e2d694f03a1c0ea21b3a405a494cf4487946512ac4f9cfe0c874e98ff50d9a9684d9d15743f0cb111af775ca86a6ece71cc53c8ac1212fd811ade5f5b409081f07010001	\\xa865c32365f41b735eb67f293f5704dd80f48fca2af611071cb3167929de3b5676a2302a0d32b435057a13ddaf8071631cabc51ec24716ab148dbcb2a01a3508	1656956819000000	1657561619000000	1720633619000000	1815241619000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
57	\\x8cfc2ad78737a62bb52ced08829c477afc6d60335ab33376c84145271198066e488187a61ec11c30cee31f01b62f7e3d88a4c669c37dac6d624470208b44e6ba	1	0	\\x000000010000000000800003c67ddc55cf05616f79917765fd00c658d39a32d7dc07ec09c28854fd7612e7bb77fbfe6903eed9ddf602cbe1acd2a03f97d7afeb0385a4f2795c467ddc423cd719619c9fa8bc1ab780d610fa7bc662be0e3535e66d6f842c65cf5a0b58fe58d24e2e212eff2ecbb82a212e4642bbb07dfebc5eb86637a3099acf71a151703371010001	\\x91b526826bf2e47cfab700c6ea1a15eabefa5296a050321136daa8ba538a62a63b8489ac2d409c15f546da8b30147a6d83ce1dcdbc78b9957a355bb89553f103	1670860319000000	1671465119000000	1734537119000000	1829145119000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
58	\\x8df032d80c001013c5b9ce01899d6569af34cf46c991781dffb4bc53276951ca95a4158f995a3a3dd147a9b6480a45e64f00ef89fdf2c5522f3fba123a6dc661	1	0	\\x000000010000000000800003da2bd6afa6b243de84dd6e9964a8497305fdc592785d0623927999f3e9196f1df9a4456a18eb9d5a2aebc2be6d233f4707610c952b8902df90d6a5730d7e26ec856d4b60dc602c2e7ababd2310352e9f489e5592b0c6ad34e72766153bb43aba0d0f6b0d27dc1e2f41edf8783d8f3c10d566fbf85fdea068e3c5a44d117fa1d9010001	\\xc579c41d3ee96e322be231c0229096f3d8ad5d29cbc821556990208fbdd30190cb830cf4f93df571d3ecadcaccdbe76ad6b34c0b0b894cc7da372b62df0e8902	1674487319000000	1675092119000000	1738164119000000	1832772119000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
59	\\x8d90100f42a1a55e2dff06431cbd6a1a262a7e11daaf14758de93bbce5016e9a90943191d942c3aad84d18212eec4fced8406b153b4f8806f34b3aa4c32dbd3e	1	0	\\x000000010000000000800003d35c8f3cb54e156b203c5eef05edeedaa06c0525310d5ad527761c358b5401f9c02ff49edb9997fe6d00061976b879db8894858e6aab8bb7e66a0661a3a9958bb59aedfaa3c5798c7c889e7b86c09dde0fbfcbe256f060124e6c4dc461639cfd99aa70c939af6bfef3b16a7dd36e79a8f63093f14923a9207f65f03aeaa06ef1010001	\\xf2014786d630b14631e904d9a394ca578c0ec337a9007a56a2ebef136e7c92fed48bf7b784d5145437f6751cfb16c278fcdc96dbb20d35fb80a1f3b49a39a705	1669651319000000	1670256119000000	1733328119000000	1827936119000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
60	\\x8e64ba0889a5b87317df39684522cf224d84c59eb4dcb9ec3f9f2667802fbfb1199665f4dfd436432b2553dc1db7c0e62ce75e353e89ecf129a040b3c87e29e5	1	0	\\x000000010000000000800003c8669bd36247fcf0f9d852b2c1f847774cfeed9a306764a1b09ed4ef0361c390c4ffad8e0db674fb578369d144557ae75e5f60daedf2ba2c9dd7655665ce0b0c9dea5b01bbba68faab1133e60f3804c7add79e9347735783b161cf401a6755a06c0fecb63d56534be7725f0f9801e6352e6b7fc7f4f3ee08910d8b3cb61e002b010001	\\xc5fd7b30df6acaa89918a69a73c704136f0c4be435b9ef605e4cf184fdb9d077e0166d3a569c7cf960e8a6d625b4246b5435c3399d21261751917f9cdd6e5809	1667837819000000	1668442619000000	1731514619000000	1826122619000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
61	\\x8f78548531e32e693066b9f62a07c560b6e8632f541c7f9aadb04a1ec1bdcf780b449928c035cd7d82a46c59917f01ec939a383009ca7f98710a505ebc942be2	1	0	\\x000000010000000000800003b92e019e83c10552c313fa11d71db0cbcabad4a4488e4305212c1f5e8f6e5b7d524810c82870e24750f80c5abf67f7d579b06743767baa66a0ad1cf87e0534043ba6028163e034fcc00de5832b8f507c284c70a3961d9955a17a3b7eecc912232c73e02c016e7fd3392af7bb535a8973f68c403c15ae1c6148042ce1c180ac0d010001	\\x249c83c8fe739bddcbb8d4c5f6ebf7f5b34eb8c6475af2268bff00586e164841c8228b5d3608be673acbf03437b7252cc5a022e829d19d11ddcaa37ddf21a905	1657561319000000	1658166119000000	1721238119000000	1815846119000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
62	\\x8f94b3ba3525b0c5caee1a38001d068b19e9438e7e7ed5329ba1c614a4b2cae2b3f2dbb36ebd1d26bd94f18fb008475fb634735226c5d8908b8cd5e5cd4135ab	1	0	\\x000000010000000000800003a99ff206698ae9ab4a4e59747b18effd80972d76e28f1f08e8c5a2c3857c4f5897809b11d30ac2e492c6a200c6411f8893a8bd6384dd2ecde6eba723f5db2a3c8d9463c91db6241685b2e27e60bd55209255fff16d2e2f9e60a09de0a65c8f881dd52346355b97d8eecb11929d419ffbb61e96099c8894387e10741aced532f7010001	\\x4cd9a3bfd8c917d7e53724692f8ada5de65cce2f582db4b82bcbb3508bafbfa0ca8bd437c841707cbf334fdcc3ee9089cb98350e672d17c3b00005a4de93fd0d	1664210819000000	1664815619000000	1727887619000000	1822495619000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
63	\\x93d8801198fc3d3e810acc61155646d50c6d5664db238fea4cb97c38de043695885a739d0e265515876a4e5cb0a46d29708e0750c03760be7b7dacd4792e9fde	1	0	\\x000000010000000000800003a0f6505d3c27f0c8eef518aba3d976025de5533acd270145308e55b3ec89dfebd5e37b3ea5ce1220881fc4cd7344bd11667201792d4912970afa154290e73be4d32058740162323734ccc45a574819abd17c271e1d99e761e738c5dfb5c334d8f1283dc077cbbd8421fa17d863b68260a95cfe4354c745d4baa21d89ffffe62f010001	\\x05632d5c298b79691c0e63cb68ea1370335ef8d6d18bb4c25079368b7d8920c20f0ee870585eeb0bcd479e5ac4b698d07e1f6dd0900d5129d85c94702e754f0e	1679927819000000	1680532619000000	1743604619000000	1838212619000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
64	\\x96e0ea51774d030f557e51b9c989cd2a049d6daf7c7aa396d5f9f889ef84edd12080fecc2b947dfa9cff8015daee0f3fa575a73a9de77aa97396cc8e8b0afb6b	1	0	\\x000000010000000000800003ae4aa1f6d5176f7ba6b06e1108f7f1037a20853337ebcaf59d457c352ca6e79fc64b6cf97038a2a007d7d842d0077a98993ce5eab8e334bdf63afc0b8400da1b7ce2a0d2ef9b8484eeca35f4e3ce818b22ad9056f85b4c745f81efc3c5e969e3911e83871a5fd5cbe7a6a9af090e2defb0da463b1b36b0a85b433244548e6a93010001	\\xa0d7b2dad1980d462a5ac30c08b13d1b0f3ce96aa7d78e42fe70430e8b0ebc5e7fbf9f3153286f8e04a8a52e219d129546198036f2a875e999eb04558135a80d	1662397319000000	1663002119000000	1726074119000000	1820682119000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
65	\\x968c490dccce7388f0673e20dddbeb90a6906b9dcfb25bdfe6357b9d97b72a113de5918e2686a774236403f08eab851cebe11623e46b25e1a6db9ba919450bfe	1	0	\\x000000010000000000800003d3cfa4af48d716b79dcd4542c708f7e9dd9650faebf67c81b7ef528890751cb6216b446ea633e721f8f299387909305981d96ea8c8c0202cbf160b52ea4e05e5c27a8b32352cab8a11bbf3c2bb66386170807573f0d9f4265398c29d2fcbccc74b0808abd8521e655965749e5fd2e09fbfd5e85a5e4f291bce1360a7aa657691010001	\\x3c1f2efe737dbccbc6982d02776aa6666349f692e39cae468d03c1c09f8641a98345a039ebe41de756fd3d128bea67f116d8e1170732ca90182a0e3cc342ce0f	1666628819000000	1667233619000000	1730305619000000	1824913619000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
66	\\x97381a73a5a882e0274aaaa37c43657d8c497501789dbcb7539964a48432267877e819aa0fc25c1451b709781c6460cd2d3f81ca66fb35024525cb80a8179fa2	1	0	\\x000000010000000000800003b25b2b72917f5eb6af7fadb066cde64c1f37bfb1d769fae6ce2ea8f1ba9e925e418a88d8deb46758031991e719c7f286345b6c717843e582ca9d824e83c9d792c2dee117671ceea6ee8be6963ec4350ed7e7f617c7d7d782d2149bed5bd75c0340a1122be084a7948522822f257a1e1219c9e52bfdfefb120c3d12ba3204beed010001	\\xdc2b0e608e58b9218d085cb2f2ad55fdd1b3b809f6b19b8ecb7910bf67d20f7bde21bd998e20e544435c32cd8fe69794c161a3beb954d11547ca58a5f637300d	1678114319000000	1678719119000000	1741791119000000	1836399119000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
67	\\x9834452574198c36b00dc74658ef175e3d7e7a2ec0ca63096731361b14dcb60d2171b215c8793f150ba6e2faff91770098d02a4c230f36a58725cf874475bfbe	1	0	\\x000000010000000000800003ad25ebf4d6e5d2044a7e263b11170e3ebbb13a2a6b9a4c604ea522dfbe8677c9d25a4e81d8a3170d4c3edf63d2ebd551347fc26748c49a46e3fc938a8673aa0c0aedea3b93ca442c06483e2197485a3d207bb091815007cdd74be8a21693f0031f7517538c40d10e66431721c35326773d77aa716588b65532f4aa9de532d52b010001	\\x4862bbb7600d39e14482ef5d0e699e4fcd68487292cdeff6079ff4367884afabb199416161b99a2c50479a6e19d753c34bc692f35723f128bd7862cf499d4309	1666628819000000	1667233619000000	1730305619000000	1824913619000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
68	\\x9b88425e77be2f1f2d1f38c6b3b8c15e3802eb6330dbf97a15fc14997d2709c700e01423daee06b00fc7f13f675d885ad1e06c1577424c64f72e8253c7ece317	1	0	\\x000000010000000000800003b5993fd3f515e9195a146ed0801615d36dcf984f214334a3f65640b94dfdafcf78b0feb12eca29df65d61d6b54dc3d44ae3be6c2dc87aeb215d746d4af6324e5dd4d66a28f5f4f1e781cedf2d73e54eaa8f8d712db349ebfbcc2f67744ee915e3dc0ffc745c8f0a62e2bb596733db865d562ecfacd2836d5ea0b736731f9c533010001	\\xce0e9de5932f1ae35902145f4bf28a63f182e5a090c5aa7bbc1d6178dec0ef4aa07354dee0030ea28ff581a7f10d30481339ad361d5b636e8b04d6b0ddc31206	1661792819000000	1662397619000000	1725469619000000	1820077619000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
69	\\x9b346b565da1000ff48d783fb8d550b37d4a247edbed79564e8ea5f59b257d694bf8e43326c6b5cfc7095eeb8981a487dc0655a8cbda1ab9d54f64e23fdda236	1	0	\\x000000010000000000800003b1b288ddec1f42357d9f844837beec0c16f61ddb29bdc700e567eaf24e3f59b208d78ea343587f5a5951cc6cc4d65b467861af4ee97ac04449e31270307c4becf4fe0903a669ec426eb04623548075f349a671305acde8bfa000d942fb870e28abeed60a59d6158085a0395996e5c46b517321c40be824a1314b8c10ed343387010001	\\x92d5de0d6954663d79be7e893d992d3097edf2cab083c0b320f00fad16e012144c321dffbf5fd4164b8047627f9b8e5f1e62ad9710860b6301fae6b4b831320c	1672069319000000	1672674119000000	1735746119000000	1830354119000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
70	\\x9bf0e03a84e5329660590c58d7ca9b3d9c90cafc7025278f8d68594e8f707be65c3034e5164d1ea103819db72615376de6285c4e777fd465885d9085687dbe40	1	0	\\x000000010000000000800003e8e08faf166a86826bbd7f19d16da154606465aafa2275ffbbd9fdaa24deb8d3c5d0649f6abc3fa3779a70d721d7bce41d31be4e230e9661ec4a741166f41065dd602283c39c0cf1fa8d4ca4711010dacd47840ca5f77da4c4e481815ceda0320d17c891fc53549e6294b0b654d4721c9bb38443a6dd6a7f81cfe8d2784f42ef010001	\\x9a56454b6936d04b4d726abdc61e0ffa8cfd15cad9506b70d2e18dc75bea952582522dbf1960c14f8ad6867585f573998368e83be73c9d56a606c0d8ac32700c	1680532319000000	1681137119000000	1744209119000000	1838817119000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
71	\\x9ed8819a7878951731361cddbe5e834e22533709ee1948d04274e01f68048ace530cf669f038fa60ee2727601646f95354a973309e816be48852a84de27803b6	1	0	\\x000000010000000000800003b7b392286783a488f88704103e39f1c676cd9e7ef56b55d9ef323e17531321249b61006b0b87569d24eb90fa22f31fb998945ce6f0af3f6aa433b1af4e9a4ec7af51a1970fde78d814afdc89ff7366e3de08481d679e3e6ea7e889f6c80768e6f1312fd7f7648a2fc12f81241c64c4f9afe671f4453144265a1c06ff3aff64eb010001	\\xe5ab00dddcaf9c04f05f2df6007a8a50174147b37d04eb0e018fdfbc5f857378aaa8ca5f140e1354861747ba006247772c8711fbf67a307b17bc2fd535904007	1678718819000000	1679323619000000	1742395619000000	1837003619000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
72	\\xa20cc300f37ef128fe8820e1b60f5e3763b174a272631689bad68778e9a657b7e80ca83681030936dd7414c6a34e2d4470b3bfac3bd75400c7b3b631e4837a41	1	0	\\x000000010000000000800003c4e9af70d267de4c927c1846df61e26447cf8c2bbdfd8021072f2a283dc89f52c5ae247b7d00bf01f4992a52c33cd6a99f1694575f971033beac7be56b93d7b423e76cf4dbc3ef35efa313ca6098ebed909478fafcfe3e91a79a1ae5b3c8f3fb49b92242bff73fab5b03e5cb63c026a30583304c0f70415dc9a134348a53c31f010001	\\x4f9db3cef4e943b0753b131b7d342102a644048fc47399587b3eda9f12776040dd7a3712e63976c0cc51a0315421eef75ba99803dc963aff91317db68623cc0c	1675696319000000	1676301119000000	1739373119000000	1833981119000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
73	\\xa374d75f646d470b84f0a4e045c96a574f00c823fa2a711053cc43ce7ec9f77c15362375f66081958d48f24bac04012268034da96fe089068a2584a499136348	1	0	\\x000000010000000000800003d62ab499e88072d1bb35c86f93c979fe60812ae9aeb8fb541b43e29a49911c81e50f15b25abccd400e2099eded73703f8d78a4b75d7518740af1fd0c165c532ff4ad13a73cb6504d5281df0f81a16c6a696b2b84f2a6fd8e28fc9d206a83bccc9b18b9c4216ee2293a2c82588da35f7924b409b4c519a6f46253934f67839cad010001	\\xeb237920369a9e379f91cfe67eb9d740152c4db4c0fc9866a65371eaf4a41602df8e68936d126c3bfe9a5120fedf21690efd23ec54df939fe1db15b8638d3808	1672673819000000	1673278619000000	1736350619000000	1830958619000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
74	\\xa39830f77079af0fd61e489b7d2f960cc986808df7da1dcb55ad49a28f3a6787c87b8f25a6b895feed97a9fbbc87eb37026bd70768c513b26464a06054ad13b2	1	0	\\x000000010000000000800003c6c689ae2005ce8a0ff58b44fb55611b24934a75e367b101247a91b193c71dae18031f13c0cece937b42af47d8d6503502e59449d2e6c20d7494de6132b5797a4cc88823cd44832c7369813d1f123a4bfd5e44f0b5dc7652cf8626b9bfa712f98fba086fb14ea2e49c17d376d85911bc9e46d9a65cd06a594870578eede22593010001	\\xf5c196f5f32f9fca920580ea946d1fba4890269b3e3165edd27922284276b823d3853c3abe7b3d9137e4a5368e06fb0849d6ce228f0b0ac540157150dc96470a	1678114319000000	1678719119000000	1741791119000000	1836399119000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
75	\\xa5ecf18e3d6641c9ef3d1afdd395f67e75dd0d05bdccfd10c935b56b177e4711f031fca2919f28945cfe88304d22636a134bc1993a00c5311f9e940ded1125e6	1	0	\\x000000010000000000800003cbcb0630ffbe451d2728fee36ec825a3f474b76b58fce3806d57339cced108e5ddf49d000b8c88a51a4c69bba2b2ca49ab6e4ca281f89931034877412c6c7f00c3a788eb92b6d5237cd196a862dddb0fea81c1d94106d621c22bf82ac20d5219749b98ef04f79a78b7744bf6167429e3be6ba5fb1b3d030d544591f3fa28220f010001	\\xb8ac029b3b96845d19d3b72c2c9706419ec89c6c3d66cfd686e4d64d73dd522c56507f7d5736bf5c0c7f10dcc8a523d0117769815706cea413d55c395abd360f	1656352319000000	1656957119000000	1720029119000000	1814637119000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
76	\\xa6b44fcd6d160a8cbd678fa8fe489cc8674cee8951cf6d16d8ad0d2a2a9a5bbac8f6ffcdf84a37efee9b6fa0e95def0cb8fa9ca58697c75c2c57f707edd4a81d	1	0	\\x000000010000000000800003c63cf9abf69cfde73793ce51a93558ae9d55bccd22ac8cac7c225d52f77fce8576c9e11382437e73814a263bcf9b35a3373c73a6e5e7deb0a73608c91d2a6170f318693273d9061f8d4fb5ae634764b04d56dc7be1337fca64ba11fb32cd7f51bdae94578613f46235be9df844f0b4b7f875f6939d44b877b19d2071cafe9d11010001	\\xa9a48b085220ffa9c1d589e87fd833772826bf2f1218a37f037a259db6e3c60cb2984c61fda48b882e851c3f8c88985f9d9ee8330f444ffbd843b869790bd50d	1655143319000000	1655748119000000	1718820119000000	1813428119000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
77	\\xa6e8910a90b672b386bcc01bada71ebda955175e67a116f6e425e14a81f48a4a1dfa418c57f2441a6f0e9936a7dd674f5111d29b9adb81db6e0cc9e044bae196	1	0	\\x000000010000000000800003dfc0e8410f2235cc638d6fc104bd2e4e274c358d8e237be57a376ab5ecf0f6d688c9f7b20a247d3ad7d2c008849d27c055332a559bc8f6e07f0b9c9f568cebd01d05fbc195e8c300ee86090aba9782dbb1f42c9412cd6fd86de32deb61fe62e0365fbf3fcb8e2c791415a2e36634b7944e9bef74e67673dfcd60ade1df59ae41010001	\\x25f310c0bb163bd628697cec049e51a7eb10e7edfad63b2dfae4a678d9c622f4c492564795117b27e907ba6d668f37cef2acb8a6aef41cfe19769ce692eb720e	1682345819000000	1682950619000000	1746022619000000	1840630619000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
78	\\xafa05ad9d6859dc779d4f409a219a1776f90a5bd06e55b88876895b8212c671ac2f9b9b71cbe1632e577ae32473710da85704b214641fe206c9aa4ad657ba786	1	0	\\x000000010000000000800003d1256605a47e3f6e3039c1345652711e88773204428b7cae99bb869fc23e2ea1b5bd279dc39f146ebb7178204e79415f583ccc56d63f51c3d78cffbe32dc97eae5e2e2e4a96c432cd5906c630e47dd88362a39701c94ad27ae8c3167678418ded499adfe8646e28a3d4921534173a50753318b644ba24cbf8997cfe0756a22b9010001	\\x1c05f409ee40a08498e2f789dbdc9f06fe73b2d3fc95214707480819bad30d5975f103a499bfa651465ddf668ccbaa85b2c218d0ec96d68f2171367fc9c6a30a	1666628819000000	1667233619000000	1730305619000000	1824913619000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
79	\\xb0483c00f3b0aca32328e3bbb22b1d8be4d71e15325badac9f8c0e85c55183d981c46539d5862cd4a786bc7b93db74ea69ad2ef4e42d95540ca089f35ad64835	1	0	\\x000000010000000000800003de4de9e3b8e305530b3e7ab1374b63b98db9815c94170faf9bea334048f62b151fed1869309f1e609a9c17ebfed3a071884ead5a3e8952fd5143e955c41e97c14f9d3b7159cbe5a4898ab88499f45c90b666a9f7148c274eb77b2a5a2ef182c0a318e1b73b56a9ba20adeac73378d33ff992796b6ce821c89888f7fd93a45d81010001	\\x904e26ce6ae339fdc0e0ebd734552f258eabe9356887ff678b9d20f3b0080abac01294194595d270a3cc6a05caf32fec453c7b056a662b69a73ba8ee524f6003	1676905319000000	1677510119000000	1740582119000000	1835190119000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
80	\\xb34c6dc6b8ae99433f3ceb1b921d6f7d28b6aa72174b44194628c1a0f44c76c34798cbd273dbbebbb35550a1c3e75df7ee7d90fe7a5a308dc4302d02086598a3	1	0	\\x000000010000000000800003beab75b5fe7f4d74439d72259af45672d246e50e1d362ca1785bdee26a7de8dd48d7534b619b3131ad61ab9127abe61f316bdddde4a8bcebb8cb7b4e5b22e8b64424321a771ad35a0157ac2ce8d05153446b245f8e80d829f85f8409efa3dfd05aed67dfeba3199114fd71f7320b3d0037608830bb40563a6f6046287097108d010001	\\x7dd1c0a02550d7733821949d70cf26cb85ddc054553bd857a1cc735541b3916a5da8edd3118f8912e9866521872c5d2494760dd5fd31e2c4d2854a46721e010f	1674487319000000	1675092119000000	1738164119000000	1832772119000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
81	\\xb5b02a6956647865309da9eb06b922c5152c7756890c51e52ead5d92c383fd3658ecbfd3fcdf50b7162abd6c4ced60f681ff2f0afa2e3f2c7c108cf753587bb2	1	0	\\x000000010000000000800003b4ed50c47817f34336a0d039ecd5657498564845ed9c2921055c8c6640c091a4a701bbe93a538a4f27dfbd095756274ee4ea96d3b63ceb7c45c9d51e6e666445ac70ff73a759a47db3be9faa3abb15c9a399abeda07da5b0b4a37098d8d330b20e4bb8a0b8fc8eaf100c55969d61c7a7b1ff8c14c132d1c7238d0ecee2d7046f010001	\\x8e93be78482992fed1b9336364644bde538021b60b548d138e52a206bdc9ea753109cec2a1c0735a2eae39bdfc03fde7b65a789bb33d123d25f08d6f00eb3d05	1663001819000000	1663606619000000	1726678619000000	1821286619000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
82	\\xb56cff815620c6a42c56d2c4228679c78e021a008ff52bfcfac8d704203d13322ff0af423a43e165d025c3356c61884d4f9a1cd8d47fa98174631aceba52f6e4	1	0	\\x000000010000000000800003ca93efafbbf248b063c98b7de4e63406062d297203ba9b6c15098830543f32949f79830faff083eb6bc90190efea93044fd3c1b5cc4a54f8bfbfdf3f1627a076243b0ce556ab32003d4b3726ab4d4e1d9b0e8bbb1d7bf40cfdc48ff442bf4d409a19d23d8763f34b368d0bd1c1f808f678e05937b5865ad0d4c51aae7c1607c3010001	\\xd0ae1f4e3499048b0a4838fec8fce8ddf67b2e1872661a4379dada9b9e5aebb6d613fd728d70ed6aa7df188fc067d3b59e8467aa78f707261072e9e7d4c37b0b	1665419819000000	1666024619000000	1729096619000000	1823704619000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
83	\\xb68498ee90b55d57d36b78e2c6eb8178d04bf322e1c01d17bfd39d8913b1d2ee61fc0fa48b384efbb271432a30e8784e5d4c959d9afacae2055c1c14011df374	1	0	\\x000000010000000000800003a7a38f110d5174cb60dceea23c9f6d7c06a1f3c677ef1bfb1304d585607f5eebddb9cfed4eac6acb7d2b26803f511a8bd7714e10fdadaf8677343cfc60cc27e9050c60494baaa6b3cbd3c7132082cebb138cfb3264796c16fc3c57e3e45d7fbf68a8c211ad912d79060a95062b6df357d14f94e2572f10e358781cc4348b912f010001	\\xfe35d20dcf01b38c023d13bfe959567f07c0c3b70e62a34cd8f365a2a80caf6c251f8479e60dd516bbb1d1e36d683839363c2fe42981af3a37c27dd27dda7209	1675091819000000	1675696619000000	1738768619000000	1833376619000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
84	\\xbe4c3b98818da594495b8c68544b1ff9f342d75ea00fe2c8e3b89cee64c915ae1214f91dcd5c4faf7443311bfa5703f039233251137e019d0b918cb7727abae4	1	0	\\x00000001000000000080000398d8c9683e3dd80fc532b0a6d8448253f9291888b5d2622fb86273d33b644e29cc02fd3e82afe2e92370b2fec8cca64a08bc44821a30acbe571207d55bf1360484fc5ce6d243dad9c7a17bf6a6ea2d000bc8c778d9c4f51ac7be6eb8acc7030798270b5a46741bfd2cc35346e99861a064534868f822344863a9dd378d19bbeb010001	\\x65b3ecbaff16ccda0accfc8e9ebf8bc79d824a1243800b168a1a07fee20d4e9c3d229e3985073e58bc0cb11b766b94839e404907e7ac90ed6ee8b1bebeec3007	1666024319000000	1666629119000000	1729701119000000	1824309119000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
85	\\xc1b019b4814f75664686c663bba8c48d9805706e513982999f7cbb71addd02c2d21c614acc9405bf2e3c607afed4113814ece8f864472674b023994d250d6e9c	1	0	\\x000000010000000000800003a91e4ef5cca7d537476e7986cce629c1da450ef7e7b21ba8299e481cd60f3d8d235e328ec3e638f1527e4ee1ce41619c2cfac1026b8dc0b7014284c5d69b463ca9e69500591a690bc3f7b7f9a3374a233eecd83142fb0b6ced7d46cf747944b41866bad7875ac92da3739d996a76cde4c98612945eab84bfbd0a9867f8a612b3010001	\\xa0c0a3f9a7e2a83d9feec02a6a04c8b0034661c46845facd5486bfb8938ee8bfea12f2a003dec3b52163e7ba1c8080cecd357e9b26998bd96f323391d188eb0a	1677509819000000	1678114619000000	1741186619000000	1835794619000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
86	\\xc208dcdd5056bdc23f6a456a9e38b47e9838b615ad527aee487538f07f21c8980e3d1b0ebb9a6986ce298f5720754d6299701d6e976ad957a36348bfc5434ec4	1	0	\\x000000010000000000800003dfe5ca3049a75ce47ffb271b325ef8c84974746d714a24c3ac76b6e83483b2f7526496fd8da5812bd8050004502cab1bc56600ae355907bb410f2b486f14dd52b6a50d0d664efb096f96b72306741591125b3ca4565a9398cf15d3d3aef41d57500c356962f5b88030a229017fa38755f2f2b7dd53c75d192c659b9f52a9cfe5010001	\\x4d3f945e7b2f569bd6e72ba2708cafad981c518ce44fe8de5a3b2cc7e771e8c53883c7273b336e39f9492aa04ede0ad1b64cd6bf4e2cced45dda4092a0639902	1676300819000000	1676905619000000	1739977619000000	1834585619000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
87	\\xc324e025fb720e2292be049a96ce2175a342a336d80c65d1ee8a5194905ff1d6e382daa063caab35d6dddbf87ab3afcc77794a2dc0b1570ae0a7359ad35e8563	1	0	\\x000000010000000000800003bc3de9f525030d91357bc836686ad91cf17a8b045b3d0982f49eaae1897c950ebbdc6ca500e7827abc78adc3570af32a0686d2257061252320fa77be7cfd3cad94f32d48cdcc00668a69a34b813599d959b09506fb042b2ee7880167d111d2e718bf7defc6137cfc08c5dee3218640d244fa3931ef429d622e7b983c76192e0d010001	\\x43e4481cda3c3ffbec08e6615345a2d16cc2fbcff8ac81649cb69f4a5e3d7ac6a36c7b29ef622f3d0d92d2b69690a1960b436c5813432a0ea6de6d285646df05	1669046819000000	1669651619000000	1732723619000000	1827331619000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
88	\\xc3d0348ce04a0a936532582d26e7b56759057db347cfd056f43a6840361e8dd36460b1c90cc2332fefbf68cd230879e98945f8001cfa8c8146a0508aef75f8ca	1	0	\\x0000000100000000008000039c5f3818b6d34c8a8114ff877421070046d084f678dc5fb281dbd8ab2bee79a08d4312f5fa0bb82bad1e1d80081984c8a31773698164fbcbec76d131e3e05616e657c01816bdc4357806d0e7f2fcac40885b9007f36fe6457cb0eef8ddf3db6474fbd47bc6637dbbb594f7280f5d286d052ee86869699196fdb1f26dc778b64b010001	\\xcfc4dbe681bd5bad3ec1ca19b310e823d78cd1f25295c43fb1bf96b37b0ef39f10e4cea470c899c36daf7903a3c248b38fe2217d2925c6d2058de7b8dc0bd00f	1654538819000000	1655143619000000	1718215619000000	1812823619000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
89	\\xc4d47f1a0c471d745a3756457ab239c2ff9c7302054d69452a76063ce401099f3eb01adcc3f38de4fd4de264653e3fbf8c31ca4e1b821ac4a6e7a0ef28fba063	1	0	\\x000000010000000000800003bfb5683db8b31dc64a3370a5f5a4375bb0c437274eafd1e67f18d43ad1a3216a31c7d5c3fa480dbcaa76b54c3b44388e84b71687550f47c3b1d60b687963b6bc9f4440d609f93544f62980662257b474823adb9da914f2b0be242a04cef5fc51154e3601ebe1d10a3a255c6dbbe8f3efdb5886c1a1274384f59bbe253047d2cb010001	\\xd6356121695d3f6de66eab733489a6f33cbb895543b41cf1d3a184eae74fcea7ea41e31a2618f73cd936020d0c90d5ab8844ba96c54246d0403a617f199cde09	1678718819000000	1679323619000000	1742395619000000	1837003619000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
90	\\xc60c782b1dcf23ef638994a6bbdd2d1715b5c9d8eb88cbd40799af4f174dfbaeb3ab6bbe37728f436227525deb5b3df333ceaa59d50fd51fb54ffbfc4c7d4057	1	0	\\x000000010000000000800003e586b8bb1ddf1893ceca04fe3f17c4508f5188442f2deaa996605cc078365ee6b4817b50b55f6b1baec2ba2ff2a06c12544f07d9ff62a43cdbe6adc65fbc04887c9ebb7ff6e1c50e1a1ab354dbfcfc29222f8f1b39b36deba12b9524e222ea3af9336206f5c1c0b3fe88ad96aa0b71be12d743950a7489d2197158bb30a651c1010001	\\xf2c3e621f971b526af3ff74cd688917bf751b5213458079093644c3566e66ef5211f402206c65ade62dd73f90f356964482c56b321035607a9295b8d84f89501	1668442319000000	1669047119000000	1732119119000000	1826727119000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
91	\\xc9b88ac8a90e3d26fc936ba2814f6caf8109d6f0cc68d5579d89d00579b3058171a58804b692aff0f5a1f01471b2845c0d836865b323693b62f8412bb084a77c	1	0	\\x000000010000000000800003de0ebcf2f96f3c44b0774328fb16861fd33d4a7e770821a33dda5ec7b4f38a2380c55b6311354697916b3767fd8ff6f17e28a99e5bb8da678c6da27e7a2f7428e01bb727266abda7e2f4f4229c9d68b14fb826d81dd753e54c044f0f546e0f98a27ad7c94a9c62f003950ef666637574b354662f0384d535b8c7f98583fa5c71010001	\\x9f457add3338b812599b6dd3df47978c338207a51fefc491abfb383b15f9f10d31debc62f04fb4e276b9060872c54abf02dd6612c5b8742aa28fb90890aa8301	1658165819000000	1658770619000000	1721842619000000	1816450619000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
92	\\xcabc764044c3e636c58db41258d28c85f82067ab91bb2f0ca276b47b3d49c763397ecd776e0caaf428079c04955e09bd19c6395ea7922f8ab837783e39d758e0	1	0	\\x000000010000000000800003c7ff59f1443d44304ed9667da0eec2358d8d3a2c54c8a9fb75fbc242ee5553e0d029163c6000ed97b63f6164a3aa688504184caacd65320560324b9a4a846563f5de6cb4a0134f0fc320b8f893486e2420928376bac52b5cf4da31909c59eae21f48ab3b479739760287fea9277145616200a26331ee179d6e74d1497ba5cd33010001	\\x96a2b4a7c7a655de0fae9af18ff9df5bc8906f871416991a873e7219968b59123613d9ad2f7cfff4032cce33ca085095aac433cfdcc304690265f427ec0c1c03	1662397319000000	1663002119000000	1726074119000000	1820682119000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
93	\\xcbe821f0f575e17655da198a8860c3e1676ced482823401f72dc067f53d4b40579fd15036ece7f03aa1d6a3b26a54b21c172993a9568ed1f2a04a4557bc90503	1	0	\\x000000010000000000800003a36b774042bfcd09230e6b5a5123a455faabe591dcbaf73aa188781d60b0aa4f8c24e2e37a7eb0807a15b29c43f33fbbf35f38421fb5e8d0d566ba086d009fce7ca6f2595a48190b63dc9539f5f0bc685ce798f7f18926ceeab68bf9051d8fa8cf8f58266c846f6d3656588bd0de0e4c173eb70fdf30f6a83bfa7e70e8a137a1010001	\\x71da63658f7371e0097e1b3a32fe8b89ac5de520be58919eb9d5473b941250eaaff5e62f7b069fb8b0cb5076809730c123c70c1dc9a3533250429cf334663203	1665419819000000	1666024619000000	1729096619000000	1823704619000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
94	\\xcd1c6adcfb6d9c26cf59d6a3afc395e288d90ec2f801d1196bdc96113647d4368a75718bfe74940f3266a23d4e82a1640e8143cafb30d687f49ff3da7c52e897	1	0	\\x000000010000000000800003c70ab017c8eda3c6d1aeb87ffeb824eb9530e06958be7f1f07e794a4a4401c52b736684c344035f0a7daf14fa3b6e9a8ea922fae0bb7b6088953f10071987bcf7244cfe22889c60af9eb62cc7fbbe8821757ab347e2120d338ab127af65bb01162f7e5377dd0740d939cfbf24370357bbfc8d341aa3eee935a271e3071a21d3b010001	\\x85732ecc022ed4aa1a920d3d8b8702cd4a479e69913aa579f10ddecb6d183117ca411a8eb047e57aed8cadab0db294c1cbaca8ed7c4229e4b030d080980e6307	1670860319000000	1671465119000000	1734537119000000	1829145119000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
95	\\xce2ccbf11e62ec06e0686354ef22da753d1b495c296a93dce91609f07aec17ce56e99c8ee00f23c71d9e99f7f77eae961ac8b7ea61c4fb70575d594e679502c6	1	0	\\x000000010000000000800003c5458022271f3242d215e8bb6bf91c0518f8178b621492b740ee488224bc3458c30220aaa2996c61a54539095aab8749f137bbce372966a30f12db09c267b82c67e21d5ffcc4e946af091fc6c81ad2e38d8b9a17f4f2d804c208928546bc8a300be2b9cedd494ea26b09f86d16d98d3948c1ef8252b2edf05c962515fd94d0bb010001	\\xdbdbae755b7bbd44e215275557258bc64be45489e130ded7f25103c05cf79e10d4dc6bb2194ed3b02805e4acfe72bf5b7599b22daef48c70f883b17df339b90f	1681136819000000	1681741619000000	1744813619000000	1839421619000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
96	\\xcf44fa23104ca1ebe5ff1f6d719783395d9e40d8fa6314627da9c7a6a01ac5383dde60c54225913d5c046fef82e704e450456eee06d4d6a199e5574be2a20003	1	0	\\x000000010000000000800003c460646879f36929b6f583e2ea46ddc49868ffc578b00c76d79c1beb365f264ba7c6d9a1d79b0f4b2a7c5c3ff6bd8bb9a219edc1cbae81e9e4f0e43c17cd9d539a2a80e0abc93d54bc585306cd192a72cb9eeafde57e38acf10635d169b36c6fddb3d67ef9d3df536d14fb471c5b36031fc1a3a5a5e65115c27fb885135248b5010001	\\x75955e6a079708db40c859da0da1d36c888caf8c1a963813b6954a6f2de1bc50acea54b0a0434c653811404d1f07d35aa3969b8058f1622da53df091960ba105	1669046819000000	1669651619000000	1732723619000000	1827331619000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
97	\\xd3fcf48314f7563a6f4716b795cad3349cf8da36d6aac1158da02d9548d83215e04695f9c040107ecffdcea4af9fb7db311eee03c016b3caf5a19e1f33d4871f	1	0	\\x000000010000000000800003ffa241d5c165166886b7b3b48f5104fe1328313ca0b259d0c4a81ed12a3b58cd01578ade5887b9eee525fb0f219a9da0e0e9d0f116505cbde03cf2e3f7b103c2d6d84e5dbf1fd917d7c526bd98e8d80a25f4a18b8dbeefc34057520c264307ddfa16fbd8f234b2125eb38d2973befcb7d53f45540fa4daf368bee773fa1e396d010001	\\x697c0c2c5174c66e09d5068e02c417cb66d69d0173e0aa894b92c2be750706210a0eac8a3831c928598d9f6b5744d464f966685ad2139dbabd5e8bf123e99509	1664815319000000	1665420119000000	1728492119000000	1823100119000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
98	\\xd4b8d3448c2efb53a23ab29d7e607dc07e7c2a7118650cf631c8784f2a3fc37f2eeb8af432811276a2064889a3dddefa67527b50281d92fd1622d047959d04c6	1	0	\\x000000010000000000800003ed16a411e6028144595d5731d9cf77ef739238b3611810752a7612658ba7b5d4722bc80fbfd3a1e88e3985a210c216f1ad9d72674f8da57f90cd772564095a426529b0722122ec903dba521952b08ba49f7229e35cfb2e1a5de8c7e83f2876fefdf2164fa87410a1ec98ae690fcb74a8d156d3c95dd6f4e5f901bab2635e0263010001	\\x5bd6d206fd8c3c41207b304abb7f1f9f40662f1d9d3153c3906942344df923b214b8a66b31e59e5c25903599f016faa0504b2bfbe194489df295f799ba3e6004	1652120819000000	1652725619000000	1715797619000000	1810405619000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
99	\\xdc0485475f5e74393f7220441e4def6baf43fef710a8a9ef9df4216e9415372c113d051a388a71063160d3394f2d1b46f31e4a87f4bb979ed902a956552f5727	1	0	\\x000000010000000000800003c2631e4db25268a207e31278360902b522929482192c66383d2d7f0550a8d6902c921d5605473ee5371f50aa3f6fceb6721497ba6e56d519e73cbacc5f9638eb28eca64302212d1f4628fd888de53ad444931149013145bfa09c93c75b314da07519987b4f60693cd72cb687b7e62743378477a4bd7354d5abe6fecec516c8a1010001	\\x89a04be5a361a611f9fcb362fb2d230ce118a6c2f94febf8d2a11b5f913cab4acf803d77c0bb0c4bfe5d504d39021ab719bf9e8f3306a60b048a271998150701	1673278319000000	1673883119000000	1736955119000000	1831563119000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
100	\\xdc14c43cdfa2861ef7e283bd6b5e5412bc3d856fedbd1565cc89ea8723dcf70cd53ab71578a4d356c6b009d03e6e94c5ce98d890c2f860731e40ac2592dc22d7	1	0	\\x000000010000000000800003c258a0ce005a4bb0124e47f398d6e549c1f498ca5c6222145073690df38ee20df8dc37c1a9e22cd1b2fd2d6d04ef7025d2027441dba975bdab992c66476b9ad5fc24dcfb390057367347569752f5cdc19874985a7e7e7d761d7e89b0b696b24d9b0e9d8ce094248077afde7c3401e84fa93ae0b36f7ccd521d9fcd90b2c781ad010001	\\x01eae28db44ae85ada6751972de86badbb5cd70d276314bdf17d7a5255bd83f462a2aff027f17db17fafcd70d7007fbdafbc2c0a9707074e8be630c62fe94100	1662397319000000	1663002119000000	1726074119000000	1820682119000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
101	\\xdd284f0a5da0851c02ed00b066a100699c3bb4218782142df94cccf775cde1aa67ec220ae408877dde1494dba5903af4798653ba9afe4008267c0eff0ca392a2	1	0	\\x000000010000000000800003b9dd33973e7f64c348f15ba391feec058acfaca1f979046e09e6ee4c6729f94c763b88d3172be3abdd344167b9a2991b7f6ba92f14e5e4f065b9b90c4354eabafcaa1a8d2218198132946626dd312e1cf696388fdadbbf266e462aa65874abc9a9c14e5552df6ac8eb2678bddf66f54a09bef67293b6def5d76197e96f6ebf41010001	\\xf8802b9029ace0329771bda3f3cee36c6ce75c79055d4f6eb9caa1d30797f3970ebb304de763382ad38c2931a28388e3e508d36c310f77b636e00ddd9a195604	1677509819000000	1678114619000000	1741186619000000	1835794619000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
102	\\xdfe870b7c70e177b8d0f9844fe983404f75d384e334cca2260f07dac4d03790e13353f7a05b9625427c4190117d7b099a52d471b1b6512cb9aa542acb46ddf2f	1	0	\\x000000010000000000800003cbba4040e2e3c30fa242c46560bc8b154d1bc9ca6f7163b2416d22ed235f29df0b5679d1395712b7c62d8cf76e3e04b6e7a50e9302072ba30fb1e173815eb2319f67b2cba4ad39321b1fcb8d1511166c3c80429808aa09cd88c017517922fb84e409b23089db78edc70c3f67d3ed21d7c81f86209c0bd71d8d0acb047806cfa3010001	\\x1430a676a9a215f6b7f8ed611968df7e699557c0afc8509cd0e7d818f8b9628f9509cbc6a03ec51603bf058f6758d2262cd2af8bcd1670ef621d5c192232070b	1670860319000000	1671465119000000	1734537119000000	1829145119000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
103	\\xe16854a56853cdc4e475d885a38ebc6ba60c04341e7223303d769ff751ae06810145578667430bec06bdb01e9d439ebd88b064320887b0627b8bee97da7157a9	1	0	\\x000000010000000000800003a8e33bf0585dc51a9bd9bb2915f55c5803bd96be8aaaec107c8bcfac19439461b04ab7b7e9091563e23306ddabece70d345cea1b9b1b652a82a7d0cfd8a6b836b0006cefc6faa100544e40bb4a531c61de0f77fb650b7b9fedb5be7b45e404f8a1eebda2acec1f06bb75fc3032b7a7e7b05156a9ca389d621663ee0bdb8f4acd010001	\\x4720d524413608e164f9e1b8fc705900a3f7b143ada6b2f6ced80ed1c2a2904231d0ca70a4e2635ef4f2a82a8198ca51a88ce4d65e702ce0a987db48a3a2ab00	1653934319000000	1654539119000000	1717611119000000	1812219119000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
104	\\xe9bcd3c85ab84ea4688d98a865b6ba2fdd828ba9f2cf0c04508ad84ca8f52d86742d1a555dbd1df2f4f0a39c0621bd649899468bd0310e157eed00135501ce30	1	0	\\x000000010000000000800003d3e613d02195dad0896245083140b5219d59cfbf2c52ab4278a4e41a88d40a786644585fffe5ae44ab3af0c82805b3ceb3c36b022d74565109704cfe53b6f23ccfcc179f71972bae56992368e56584939fe609ab307b17b6d8ffb84ec8f11c01e03a250ae504c5f748b89807825c536fdd5ec5856e60874e3df6cab6074e84d1010001	\\xe84708cebd341df91573ca0fccffd60022ae6e063d135c3dfbba067861c065ffa63befeca952f973976e656690873b58fd1137590ec4ac8053072bb947cfa902	1676300819000000	1676905619000000	1739977619000000	1834585619000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
105	\\xecb87419ee474b64e3ab6fd5e2810499d803a63f66a260d2e2c29aede56a696138fd1391b26b7d73ac9556528329d3400c8f43fb9ef8fb47aa62e31026932d94	1	0	\\x000000010000000000800003a207f398534602c5dca2faa157f3ebb93ac1c6a80bb8d8f42aed23d8dfd0ea37f1a84e45d38e1f22327b89a8fb51ad81a64a12c8a06541fb9a5d24dd34e5d56bb2181f11f16aa919e06a294827bdf8f0a8c9e48058d8bf480b075d6ed32cbdf22948d0665cd1ffd92ab84d00f464f130dc1a6c919774a8e303be3a009a21d01f010001	\\x7be1df7783424277af3f8e32d6592f16e37aeb3953faf4a5d6b6cae40fa341f7785040c8ea7a1775dd150374f36cce9208408bbd6f3689da8109d9bcc6334b0a	1663606319000000	1664211119000000	1727283119000000	1821891119000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
106	\\xecf0b1efc7e2233d719b481300f8ca79db79173f8459113b528c44bbb4b57a8251b244cff9b9b032fe8278c723c193dba6828130559d7f5451c6870b0e4a39e6	1	0	\\x000000010000000000800003b6ff2234e55cfb7b062e8277b5ea5b2bafe2b51f2521020a975c911af2da435c424833b49fc5b16de5ad81448fe6124b22c5ea7d263cdd1d7219737425c5b81f67f91640288f0509b015ffb9356c79dd4edce719a1a492bc9c73d26258cdcd1a1955f20b32867738c21e57d4a30b86b96cd51eb9ef955d6535afb051d3a6d0e1010001	\\xc4b356e17fd983cfd6bfc40cee76997cb05b82484619e1086313115904201aa9d4aafcca6c7eb6b4123e900744904bb9efddb5480eeea5e49f76c36f654e0009	1663606319000000	1664211119000000	1727283119000000	1821891119000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
107	\\xf37c7d39a7462579f8818f1d4309183b66dcc0f7f1b63688b982f28e65fb1d28be970e17756e3d8664ba218a2a66be1aa4aa96f6ef8a1a64899e27ca63a8b475	1	0	\\x000000010000000000800003ce90a364727e2a3bcf20170a9fee4a8edf08a72bfbc907a5efa6f002de974dcf77f77b3a88da04766b329e590aa99968290ebe292c798462ff91361f887487f5bfa165facd34a5e94efefeac993caea9b3b77e7f07d22c29be23417e948a0942815516f0481ab19c54afa45e61e7336f195e0173a16d10761007f9ae8f6f3869010001	\\x681d77759be2ea4875cbf17a028be09b85b7ed89e021e9a11994a8b4ef64dcd16981fcdd1873539f1b414a58a7328fc6db6bd0d4203a05747c9c6e43dcd29c04	1669651319000000	1670256119000000	1733328119000000	1827936119000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
108	\\xf564a95f1bbe49fc227acf9d17e6f9062fe6af7b3d94765aa77e263c93f7477630aff00f16ee3fe1b57858e95d835d2e110a8e6bd31573ff251d82d0045de938	1	0	\\x000000010000000000800003d79faee8939208667312a612ae37ca89b28017aaf16e796d508b40cc1f96e3528d2b6aba3293d61937cf5ebcd4be7dd5bba56eed43a0a9fbea4cc53b34fe695e34c6c97abafd4b52bf974110ed45688f75153a6e734410fb2306fe36bc4c38fd1b6d5c5216bb12e60b81b4ddab18657767e7b534f877b785263ae6988987546d010001	\\xc1f4f343c4647e4751ef61f107016a3bd982c8f74e78521474d4f8f75056372f2744f1a69e1cfe01ae32d0177d3a836180c1113ac44b77a41bab04b35876fd02	1660583819000000	1661188619000000	1724260619000000	1818868619000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
109	\\xf75c0148088114b89024334faf38b11834395e9359ebea9db84bdaa261e46ee0174cc87be92da8c0409cecd9e2db699f8343f1197a38ea9e2ed05a3ae57815e8	1	0	\\x000000010000000000800003c40b3d0ae69aa1e7ff5d4d6366843e4de46c894e7d0598e730525f08d14afd2c8da70e427c0dd502a2fef35dd02f64f9b54ea296c8058e06af1bda74669796d4a386e6a3c6ffa16b04c5329baa9424661e90e12c311eb388f150ddbb7b2cfd42651497c160a29268b0180395c1372721999f37d913c71a4eef30b71e8fb34d37010001	\\xaa55012fd55704a7009362f1511d1535e924929563f9a1b9c5f835fd1f95cd73c7da644f81e140359b44bf612a801e624497cf8087e65e79f965f6861671d202	1670255819000000	1670860619000000	1733932619000000	1828540619000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
110	\\xfea4eaef4db5555295ab5768c1d30e83836542e877df3cafb5f109082112db9f5f05cdc188685ac3f32edd61b5be3bd89e4c0537ec626b19962a54d9aba48423	1	0	\\x000000010000000000800003b855688ed604216f50522b686cd10f01acb026850d13ba8875b6bc955cd12596e6d3e6c9650316df594632955211e15e89e7404dfbc3e11fafdfabd0826ffd2c11b05218914aa99f9560bbd07f5ff9bd0a9b105bfd10137b48e24ff4a9ac4d88bd2a5b85da0aeda2f65e681261648522951c760c060ec3b995b2dace1f003b0d010001	\\x3b9f20a7cdc50e9b341c9dfe636b7f51bea61fa2fb0eb072296e2b6405bff56bbcf5872fcdf907eed6164cb646a7e6dc1018442b0b5dc6b257352fb355b0d309	1652120819000000	1652725619000000	1715797619000000	1810405619000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
111	\\x02b1de8fc7a0e7f3a2e8f15cefdf86ecce47f864f53dee70f5e82dfbf12dff881b0352ac82926bbc8a281f54784687cf187f3666025698d08251c06929570f48	1	0	\\x000000010000000000800003b2efe173295c04f34a34bcbdbd7773d5d836d3faa0af241f1ea477508260b5cc1269fef7d0f2981b2b1920b214977fcb7c2ab31f3966b1c607e6c3519d78cdcad1a31f6d8b84b1b87e2fda44ef8928e285b0f72e071dfa1a9385827feeac4bc190173470f3f5d442e6d6a569e88aa792a5fa545fd170da46eecc42d3533eba3b010001	\\xbcfd0ea5c05d831083ef6ed4624ca586c1aa89e25105d1fd3be52be8e5a508b34bdb01df56bbd9e415666d4aba039810909080fad78b46c122957214fddf6f03	1662397319000000	1663002119000000	1726074119000000	1820682119000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
112	\\x03399facf81a0018ac1ac27653e0df932aa1f157d025634f21678ed28d54554052405dd7443effcd9e5955ba0fce7a0116420d4d3eb9a56f01f1fea95106bc81	1	0	\\x000000010000000000800003bcd593c2cd6f30d64c24c60480148f54007c855ab592f1beae97d7a9ef1206241e2ab6950a6cb4e075485abe1b3c8b139ff4294ea0100b082051af0b9dde44dab3efcd811fe2be346a5af0542c64e6e94d9972942558b666fc5c82b89bd646c0ddb3be754445bf6f2c051cf2db7f12ef03a6ca4398145f84c3216d51baea6017010001	\\x7805913a3c1f04413a67459386a5bd204c685b0703ed8d25d283cab35806ba84d09ae220e25b7eeb3d0f616eb2dd149cf111f20396acc47c030bb3860762ab0a	1655747819000000	1656352619000000	1719424619000000	1814032619000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
113	\\x0f219e29d69a60c105c2e498db500fb5e1f3ba731685dfc719c02f4f1344ccf114a43e6034871f7e4929d7e7aeae8f0f0c411fa68a23cba1b604054550588460	1	0	\\x000000010000000000800003cbd50acc427fa388ab1d1e80d31b2204d90ded98bb519f84d24ada2eba1f170d63c515b096a40442e64a83e3025436a1c4d980cd1cb6c3918432d4033ccffe5c15d075ab7d987068e02eb0e7f435e83fa419d7abfe5795ea19195b1b302b9f55f0961811819516806b65ebc1e891f01a1d99f1c71e12cbae41574841fa421931010001	\\x4ec3dabf1d00aca7ca21d96259524b78f4078cafb6ce71e712d464e93b4d884175fbb8a81667bb57c6e9d47613930c4b342f644a93a7c9f9d66d07221a0be206	1657561319000000	1658166119000000	1721238119000000	1815846119000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
114	\\x100d1d4dd2e202238af30238e4c7eee50cdebe4914fd148d153a838eb0f5051a35558bd43f35bc481fe358cfd4782ab05aab5ef5bef8d8bd66b295268819acb7	1	0	\\x000000010000000000800003cd8787f7e63258adfd694ae1b07179b8713c1fbe9abc385a9f1be7b53fb483a48daefd0dd2595fde709baa8f88c854429b02762103a56c6512b497e070867b4e91b5a6926380ea116308309bc7d6958027b27988248a64f5e0388cda9a00e33f89d16988363b5cd0b83a777acf04410af58db82ba5739063ae12a77fe849db3d010001	\\x73571b70f6a96a3a7bb2db7c29617c464fe14a6ce2ee3f6b30e59c3a98bd4db8c9d2482a06ac44b29f62f1268886966e7e5d2159f00fcc883b49ab84b21a7e04	1681741319000000	1682346119000000	1745418119000000	1840026119000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
115	\\x12bda53cdaf283e320b2146f23700635a0bf8a8c38532ca5a66e4d72c1a0da750f9b87dcc9ae4309cf1c2ab2cc815057b53c61d0416c8b194ed1f90c6bf6468a	1	0	\\x000000010000000000800003be03a67e926ea972fcb66ab47983d0a755f97fddcc543222a89ca3a6d691bb460190aafcc45fbdbb0ef6ec6bbaa9ddea54cffef385c8df3f000a97857bed77c7f1270573891c2555bff1858f7cb242d3a63c98e9ff30cd0abfaae21230445271c30a76a7a00273ed76faf9030f0f7bf6e035eef8cf3cb189d47cefc251182c9b010001	\\xe3ed18dd3c1e22dcb7bd6ab6af8f5c7e7c02d8643239630639a2804e0a959e5cca321284ab44c77c3c18ae03ee00afa046e25c26963363356208c6e9c3fa050e	1669046819000000	1669651619000000	1732723619000000	1827331619000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
116	\\x14b158b5a99d955ab3f0d539978b039f8d7c0b0a3df5fca3c67fbbef28c782aa5c10af58531187465f69077e03503da771383dde8bd97a80d9903fe2e754f1a5	1	0	\\x000000010000000000800003c5dfb010b23bb3d45c6d836bac10854853d5b1470e2a1c32c52de82f52b2fc25860aa8209f4a5dcb4ece9d3bd1e5d9c0948d8b55ce69583514c5bf790edc46f6ec39c79f81fa3c51a339b7c32796660790a5d3a23bd869e3ad74863a4ae5f2f87603d0424f13c5c91ab7537c03c3dea53942a1b20c420d981fb3a043fbd37179010001	\\x4ebc31bc3db3604eff451bc2ac08595bc61dfe80c055c6139300006a236e0d4ba657bb1690afad89475036d9a8d10f3613e3bd74130bb96189cca67c53aa7c00	1665419819000000	1666024619000000	1729096619000000	1823704619000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
117	\\x15b12cc1340bbf820ba972b523e46da384a20e1080fd9bfd27efa74725a62ec87182d8fc775545c385340bf2809528e1d1674fac8f9b560546be23e5ffdcd236	1	0	\\x000000010000000000800003df81dd77d1182cfea0746a1896270fd47054e77da7a4f2098dc080538ec8367637db5597f4d75d37332a6e576a3800a777cd4474c2c4111fd3b2fb32d8c10e249cf0c9ad6c4b890ad9259b90ec1328282b4efde8f1704efb27210cf2233a92192a7de90f9803d3e18e72780d95bdaa0e756975fd6739e0fba9dbf7031f46de27010001	\\x3114592e47142ea1b86b09079aec12fc3fd271629163679ea666e96ff42af97db901d5ea8d7023fc3775aa24f57b9eba56d8b7b5c81664b1a6e9fb151bc2f00d	1676300819000000	1676905619000000	1739977619000000	1834585619000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
118	\\x194d2356f6566ca1195b726bcf36f4f88eddbee9a4351b166aead8aa58e9255b820b6c72fe5f65966ea65e2e5e1c624587edeaa30e20d7a52f3caadb76980aa6	1	0	\\x000000010000000000800003a64ced86f442b18e4528549ad5a36d13541d9de7e86f89e2d93f58dfde666c1a45899d8fd45c6c1ddb004c4f620a41409bf5d50b32f8accc3d7c53977dfaf5678385bf046eeff4438cfae2f5a33d3d27f0a3feb4dde8ceaeacb76766c9082f075c3d7e2b825312f203aaac002b65efd31724c0dc9435ed8084df4392727bb985010001	\\x8d7c82cae1e48eece5d6ef295f9576080e0cf2f49d11e040c453ca89b1a2d014c9222ea385c62ec4d99494a1d33b7166c18d51eb025f625553474bc1312a1e05	1652120819000000	1652725619000000	1715797619000000	1810405619000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
119	\\x1ad9189cbdec2b59a266a070401b38ce5380db399cea21d2f7bbfc0a8f6495129bd0cc812f2c62fd0518c084bd4d1d0142ea1a8074482044e48820887fcf1df6	1	0	\\x000000010000000000800003d450cb0713da08d43b1254910b16177ec43d2b366b5eb49468cc0d4f270694f0e01eecc09dc108721becf3559540fed32b15ca331a04e06a542f8dcd26593af3b8a0915117f9173ee03d697699e37668ebc0e3e8002123fa77cb85f2f18a21e621b3b6563d1c8f11ed12cd07135496f4c237682ac4d37c9399c07baf7ecc824b010001	\\x660da5b84d3f73418804aa44c27ce694a0a2e2f5176c7138fb31aacfa201917692ae1bb1cfd5bb7823fdc9c81f56fd2da9ec51b63192f6bca44201b204b3ea01	1656956819000000	1657561619000000	1720633619000000	1815241619000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
120	\\x1cb12b15f5ee7e55615e7d35bfbed6f5b98a2ccadd78cd200fc8d5a2a924e4bd6339189f8e20ff2dde5929d470c1c94122d15451c3de5dcb21121b4e14931698	1	0	\\x000000010000000000800003c33921a8dfa85ccfdde574c61e32f0929c69ab7fc234d976021048a20a8a227670997db8b5340d2aa8da0c7a7cb8be503d91758a1633e7f6581ab6b8592dee679e0d6407006b336283e6a5e046c8995da5a60b8310d7487dd1423002538a2c1c4107b540b3743220876f36e5bf21dd5141085344e4860437e36c715a80579c31010001	\\xed63587944e00d825eb2607c7ed0b99e746f5d1876b75df12cdf94a57f3f91ea4a7f5638f132294d2c24ffccdaac3fe42287b987fad40de0733fe0bbc4b95f01	1680532319000000	1681137119000000	1744209119000000	1838817119000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
121	\\x1ebd0fde42ba387e6285ee46807e1bd929bf388e5e25092e07c209ffd0d7054848f6cd7afb6c7e32afb105d314b641825ea3b9fd35e6f295cc69e35200b806c7	1	0	\\x0000000100000000008000039f7d76eea258c21cd7dba3e641b430b22f7144a9c4f051e4eabd23356ff30485f14ca49271fd46b61925b249e0e0e5bf67c81da880516675e16a6e45089fcc69c8d381c94eab2f5ee5754118827513473d43f055f2d447197f3fbba2071778e625825b1968b1ab8032e0bab6ff083aefeb15dbe70c90c656591aee5ef343eea1010001	\\xa0eaf7173febb43c9e7187ffc6940213411be45cbc2d21e09b5a06d13f318552419418ccad63490348e767e346b1d00b40d7aa8404970b68613238df3e19230b	1657561319000000	1658166119000000	1721238119000000	1815846119000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
122	\\x20556610808c0a68276c31134f722d0ffa0366b70623930d96b4fa59a5fbde7d22ec647cbfb11810316a123b5286db97757506f27aa96f1947f1b3191f87405b	1	0	\\x000000010000000000800003bbc14de7e93276f19cec4e22c55388cf3342f58e1f850ac2c7f040ee1ab0d48980bb94044f12f4aa0ce1fc3bc820ec9e366340f8991f1a5213fb538d4c365032f95547a234b6d6553acc5d90ccaf8392dbd5b6382bf91feb09825c978f2a998eeeea36ffdee8af719ff38cdcd61339c3dd98ab9e216114db02450f23def14e75010001	\\xa8da1c37cc6d180b14178dda2bffafe13c07e95de29d744b89094b81c6938a3e13a93fbfd91ad9ac10e58e91a0ddd647e48fc50b57ffaeef575d39e586563203	1676905319000000	1677510119000000	1740582119000000	1835190119000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
123	\\x21f53fc143da9eaed51b409fd1d3016a3eae9dc4b4a95840b44fb8a4cbfe69a8c72b844d14017d05e9eac556df93c848c77d6e8e393292455e6a1124aad618cb	1	0	\\x000000010000000000800003bbd164dcb8ee8e7ab0c78ca801d4ab2b1539be9ef0e26336ba01d8cf3d9056d92ca1747fd93a360ba96a12b1ab3a22eca3c28e5574347437d90857f25ab6f5856bc70788cb7eb586950b645365d375dfebe72a3a0a8c2adf58c33494762526bf9325bda6a7820af64d1a602fa44a58c4a0dbbe679645a3e7bb32a1a28c02632d010001	\\xfee478406efef7e220d23d5fb8fbe10f3bcb7a1f45c5be4c87ab823992e8bcb423d67c8ff1fe8b3818d75ebbecd63b0ec091fc99e7a7f1420d7b9e040d005c07	1662397319000000	1663002119000000	1726074119000000	1820682119000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
124	\\x27dd51e42a748c77169e23834bdc02e1eacc418388671d5f337fe421d2b0b0fe40f05b4fc11c8eb2cfedcecd54a8c86ff291f226478499b2ec78d03f0ece0b98	1	0	\\x000000010000000000800003c8a3affffb48d144f4df4779ebdb2b1075044ba561442b28c53a94dba7e218a84772d514b037266e79ced491b462072c8f545833c0315bd0fd02e6bba6fd7ccfbb3b5582de7e79bc37feeb6235fb25ba9e3813dbfb24416d0e051be25d37fe278ce371f6e5bb8a83de25c18f645da2f212bb45146c31c52c37aa88c3d5544fe3010001	\\x6698c1162afb0097c2d20ca99f2198f4d1a47f1580fabba8168a4dc75083727d62e2071c49fc48ccd7eab52150091b841ca6c8eeb5f27ce701ea0be193002807	1661188319000000	1661793119000000	1724865119000000	1819473119000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
125	\\x28a128ca4ef3effd9f1fef6b5de1da71fcf1b51231b1684728e315c6a91c61557468ce88577c2db0f84c7f9d820b463a81125de0e7c0d3aada073177932b522a	1	0	\\x000000010000000000800003a692ae9c9182693ae8f67eedc5c1dbbfdadea62e6b1715e6357ecfaf067bc1ad4cfa0030aa0256938ca093175dc5e9a196f29ab20c34fdae37a92f14b6448c5c6aa64d10217f492a11e6f8d89719f96a90be7b2863fad12fd20896198e7e7d9c03064f08b990f5fd2d9b169f8ceb1cbaa88a22e532bbf8b9b9f65639a7d32dff010001	\\x797a0089145e9906a8221e48802d14d94db784472890798b153209d6799e9c27072b5985e802022c7e715bcc412bb22a645363238c9e5026fb73661cb261aa00	1655747819000000	1656352619000000	1719424619000000	1814032619000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
126	\\x2b0903238566749637b829dfed8a650db10f263e9daabf579b78e859a337a5878c3abc413301a7307950d67070bfd5e369344e30105151044f14fbf97def1b81	1	0	\\x000000010000000000800003e8f6aeb6da622ee632eec96b0f28c0cb1b2f752dbea17d2f663a7b8505c9474849af3db22cfd95886fc63902cdb7027b8ed6565a7cc5f5be7295f76cb78ae382f4766787cb1d486e4fdc4985fbda0910d6fe86e0bdb2c73e91cc8649fbd1fd48ab381bbb6cb1bdc6b03176087443f4e607a752f9f73a85b01cb67a83b1c260b9010001	\\xde3b4c3aafee9f3acce610b1f988390325f6f9c8514b7885bfdb1ca1661dcdcc25ad292d73f08fd3ee6614843d0bc079c722f82bbe5e396e2f0328d70cdc7e0d	1668442319000000	1669047119000000	1732119119000000	1826727119000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
127	\\x2f890e536e00170cff032ef90852cad6edc9e21ac5ba170aead3c5fc319e98529b19325b53186768ab485cb34dfb84842fd7d70a0e8ef305f7e537c81168a761	1	0	\\x000000010000000000800003c7f978721c713036bbad83c77f80d5341e65469adf13ba584c5c4ff326ca4d331ed79327f2f67b2789b8ecfe616f1185411256289e18d0b9254ebfaaed45801d933e877dffcc7dc175d9ac46733bc09826c5c530fbb37d9ac11ed176c586609a64e41325d24d2453b8564dc96d06b9130f983af308b47a739a255b92cb200c05010001	\\xbc21adf98e50b28a38c39bfb689683155c7eadc8a48e908981e077f12827685ec8b296241d5fd74eb12dc45d159f0e662aa17250d87923bc11c682dccbc8b505	1667837819000000	1668442619000000	1731514619000000	1826122619000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
128	\\x30b9c8a65af7dd28bd50f9557ea803aa0b4c952e9a66553da7cba42c8b67e8d627cc177e7368ba9673030ed255f5aedfb60438460c9085d4e2a1e7dc54101b39	1	0	\\x000000010000000000800003ca93be54a5cb1c68478f92e9a19226fb213b63ed02f8466cac62795e9bc2d1f541aaf99acd9a94c7c90ba837725c10c4965459570450e06d7fcb4689caf0c892534529021d606a1c8f9aca4f14b2a3b8686cdd1b10709053f9b884db0d03c64a9f6a6e9e5c57632c4f0a62f3cd9454a9e8f300fa96ec3af4c326f13f4f489b11010001	\\x533f8ba5db602b2ea34f6e707ea6998366f7e48f72c80937e5674da63018f37498b02a59d8e13741c1bbf88f86cef8393fae72dd136781ad8d90b6d614f3c000	1661792819000000	1662397619000000	1725469619000000	1820077619000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
129	\\x333d69930bc55bed881aa3ef123197a6eae5e06a1651a354fb762a14b4c4467adf5e47bbc5e4ab2e207ac29528f95c65fa02d302ede6edea56de8dd05772c1d4	1	0	\\x000000010000000000800003bf02f34574101cc462a9f9f6812f1e698fb2825bd6e0277634b9ba9037fff2de63e5526564b9288f2f3e662718269022aef7a79ef16eca7d2dc30df0585f76acd0b2f614a771b980c0fe67a775e6ec1d1c272724bb6bdba90e2e4a6f1a759f2d2ce32c4a77b0d56e9bb045879fcda5383f2f6ce1e86a4ad5d77e9fba12dd5b73010001	\\x044d49be5a336495f812f4474a9230faee51b0dab6841134abf70ce20f6a5faa5c34f6443b5404e1aa1387efb8b17ada6a563c7ad8ad67505144b5d790dcfb00	1670255819000000	1670860619000000	1733932619000000	1828540619000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
130	\\x340944b8ab7c662718fa32f0bc0603e4f0cb1cc2f2f272a59932c1a13cd38b4ae7fba6222a4951f273559d5dc7ecd4512b6ddd416e591ae5d3cbbf1a847a243f	1	0	\\x000000010000000000800003c1e18a33d3abc9ae5b9c9a272468fa71cb496422fd2cb4290519b9e2277f6ff5dab1f5c419f09bcac7379745b973b66aa4241cfd75ab8844be3125d5f3199aaef63b9b0c02cb1cba846ef83dc1a0b6d1ba84bd8cbd3e4d43ecc4c40b0566b9415aefa91877aa2728e8b215d6814da3e731e00f59922b1da3c275ae9748e636ab010001	\\x41b48cea09e5babbf237a261cc481d052c5cb9404013f69761ea5694586b22a7d88e87e30d727dfdab73fdb9ed9dff6e74e1b7a85a34d385f104bb72c18a6909	1669046819000000	1669651619000000	1732723619000000	1827331619000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
131	\\x36a1eb84524cb6f7338b8a6358d6c0a0a92a14ebe370cc069e28b29601dd5b187e7c9e7c8edcba560d688c151fb040085308b104a32728eab212ad84f62b54f1	1	0	\\x000000010000000000800003b63ceb901488bef44d7d4bc31f1a138be1091851472e3bd27728629ff8cca46c798b076e63d92613b9bae0c021777798974cee46fc0f2f036b85d065fd8c7f17b67b034a3a6aeebaabf863669faa761e4c113d4a8a4b3e6cd037324f284ca12154044a8d9fc1e686108d5ea7ed2116c56a835102d18e2255be7bfc6dace25be7010001	\\xa29913e64aecd463fe05be38c72d8da99380c06a9a3e3275dae87c88b1ff04e51ba6a3f440773447196ce8d53dbfe4972274ed73661d2fcd7bedf995ed21020c	1672673819000000	1673278619000000	1736350619000000	1830958619000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
132	\\x3725e9c9daca0ef7d647f1e0f0a0598ca507f176f6298bc6cd3922000ac18a3c9a128335edd5ea8547359d9bf4892aad658900610484b70d2a7ba4be8b6c1252	1	0	\\x000000010000000000800003a2a8c57c7e86f555be0ae4f6d2bfbe950acd02b3598023f2109fb3c0541b337f86a81e5d9ddfbae0b556f8131c3f4d5459de718e8d9ffa4eabbdcf97543db74ce00be7e6d1c9aadca8bcfe4a92ccab1e84a5502d48d3c9fa84611190d2c810091eee8bc71d5e145ba5030af14bfcec110ea104270cd2ce1c65a1bff337e13957010001	\\x2ec1549c6626b1fd5fc37593e95f6baaeeca965bfac1000b8ad44c0e5ac75a33fde3bf7cb83ff568b73536caf50864d2c5dc927e398a6e7ad5b6a31d475de502	1679927819000000	1680532619000000	1743604619000000	1838212619000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
133	\\x38a12ff03d061b6adcc2e1a05a773d0af886dd43571e875d01196aca19a74ac1f18407bcf0806fe35b2bc8d3a10330e0cadb96ad0da8f4603eadd7041f59fea4	1	0	\\x000000010000000000800003c94caa6a3c9761bcea48c777892e23b9c7d858b9e67c27b08ca200728e2d07083a6bf5d378ccb2aac686c8b1a56c05d4619775156c6d0f1a42048bcee84adc5936c84faaefe681f57344bd9c513def57bcb8e2c23df3e50c574c1c03da1ca2c8bae2c391f88f56bca8cf7d9a38f2f6406cd070b6a3fcde2aa0a3288ac5b1b0c9010001	\\xf21e5967e6e94d278b6621ab7311bd2a1f60fab9f9f52eeb0b59452090d3138e0cd7c3107c2d4ffa192be45e78cd1291a432132663aabc2a5d1c55e9d006df0f	1669651319000000	1670256119000000	1733328119000000	1827936119000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
134	\\x3e61e3dc6c3e52fdd3046ff29d3a038ad19e69d8651930a7d6a7cd32a544bded47f98414a2b8a6c84472df8eba090832359d93c04db0fb789f7c2a364da1f3a0	1	0	\\x000000010000000000800003c5ec29aa0f041d49d23f3e0cca2cce32453d37ff2a267e63e2947ccbef96a55f97e106f59254a212cf39ae4321589a83e9888c9a77912c1d8711229988dba94fdb94c12f5b4f1e9248682bcea8359917b534bce875509c99570e6d9158699d82feeb3eb133af3ebe0543a56279f2c770b4e552d33059490f4ceb86e1674480b3010001	\\x278e1e662d6fcc80341e5ea2e6cafc499d84cde0e52a10357d32327745ee085eda24a05e600767ef7a1712c450dc58c3395417ff102747a8aaaf9e9b47545902	1656956819000000	1657561619000000	1720633619000000	1815241619000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
135	\\x3f297e6b775badc64c03679131553e671ae25740d66d18dec4d92d615571b0074f9f9acbb5a88aa285ab711cb62a780b040cd8d23e8ecea4ae93a47e2263e161	1	0	\\x000000010000000000800003cc1539d28bcdfb541c6fda696ff29a50790ebef84257c6c6911a7725db88cb9703cf6096a68da8eb74c2d9c7a47cfc4fa4624b31dc8954f1152828739091cb9454fe440bd0444c88525c1b72daa750c734f7ee2be969fa9fc650aab07670727e7365c6d9c4ca87eea3c95bc7bf1011e82e3478c092df1ea462dec54d113b77bd010001	\\x9f1c978f7ba53e805e1e461533d458b7448ff2bd9cb8714e83dbc5a50768820890387fd3151d76200105487dcbaef5fa7e2fdddac4b5cd9246e416bd5fe6670d	1652725319000000	1653330119000000	1716402119000000	1811010119000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
136	\\x4185e84f96d5bfc6fde03c8d93e9741f99dc412183f4c46582df4013de26f761211d69c6c3bb8556d3072bbfa010f0b9ce18a591d7cfab4d0e0900a0c29404a8	1	0	\\x000000010000000000800003df6d285c60a9b12553e8f44307258abd23e5497c38a83e7e5cfb995cca7dd09586f9e9ab42385c01c84121b5e478dc884358513d82d2c05ebbf87fa178ce7aa09553b212668c520f311a6c07e94fc3920d67fb88968320f92dc7f2220fbd63e5b7730d2ff13bcfe521a15bdab1f369c18683c077b24fc804583c52c2c6f9b9a7010001	\\xb85ccfde7ec3207c7e1676aa113d57b3f1922ad56c6e4b76f7758d56d6a54221dae0467192135d34490bcd63b7bfa4441427d7b2d4a34c4615cfbfbcdb2e2d01	1673278319000000	1673883119000000	1736955119000000	1831563119000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
137	\\x4479df616a897e9064c389a38b526b8c3edfa0849960876008e3859598852eddd7708d556453cbc85711ba5ebca97705bdbabee83ba66f8b233e82bda7067c06	1	0	\\x000000010000000000800003ea89fd9770cce033bcb13a28392370cff3c34afc774f6067d77e38ef15700d52edeebaf97701c80d442c1cfa3f54efe96f5f7f48f4c1dd777a173ce57230da695fb6bc62cb8fbf75a78533ea21196db0d65446422bb25ada92c16fd9e8ef20f6ce1b737c664ca7dfc734217199479a39f386350c7e51bfaf4d35d7e1b05bc85d010001	\\x9f55da1fdc42a4166ad90c5dc4390dd3671ff4364a70f91e6cac4eecf65bead04e62cdd5c24c8e8276791a57373ee0f461645745eadffcf511f6cf6db554c207	1653329819000000	1653934619000000	1717006619000000	1811614619000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
138	\\x47f153d6a7c45d07101914d59de0c5affd2fd8aaaab1261fba49f56bb90fe805c07053a295ec2fe5def0ed166b8ea7d83b95b3caef03ca3627f9f08ee824b927	1	0	\\x000000010000000000800003ba19eaf83b0b93d24e4c0ab936552ca9358936cd0af4f1564b514c66e9ba963a1fad440679d6dd40545ff6de9e4aa8fce7223a8f916fca3eeaf50289e6af4c28a8fa949668d402492a26199fa5d2d86b076d496f90f2c20ba168fbbee447aff58f556105549eebcba922de577088f50b8559ed526820a7958bc3889f38f65f09010001	\\x05b86b5a922506291a77cc454185ebdd52e96956535aa8e45969e90b28838a2a071cbf68618495103fb4f17ebeb86ca1653ab3ff143f48e1fa87bda37e5b950f	1667233319000000	1667838119000000	1730910119000000	1825518119000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
139	\\x4aa16132cbebf8446978d3df6e37fa8ca20b552b4c731d23e8146835b7f43a637801472c791a0b253090844fb315283759014372cc32aaf5c8a6303f87d424b9	1	0	\\x000000010000000000800003cc68ddf763c654a0a342126342bbb64c0584c69f2b8ecfd51bbdade377f3c8ab49ed908608cd8f3e0533edc2dc16ef6ffa8ababf157d41bad841535059e4dcf04684bd7b6c8260061a67619b91999d64baa023381d586f7fa0d02eb9aa6ebf4009f62d3f10355ca324d8576ffd7f501dff4dd39719e3b246c10b9bd59fbaca89010001	\\x5c1cf21bdfd714f5d1f86321bd3681f353714ae6077a896699e444c352bb108839f491696938ac2d884a5c1362ad538363c2caf61a44346c9cdf1518a4c8cf0e	1682950319000000	1683555119000000	1746627119000000	1841235119000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
140	\\x4cf9703451de94cd7c17963b4bf2bcb56baa3bcd5cccc7d7100888bec0607f66b20718dfbca2305876c962dd21b831c8d1e5f44ae8888642a433069db04b1f80	1	0	\\x000000010000000000800003df46fbb47ba41ddf90f7ecf84c226185ce29b826bbbc089f91e540004c04f039d66ca87b60bd1db6ea296a01cab61e153befbf8c04edfc200957b453f8a2d50fb02c97028964092f10c14bda8ac870e195c2da86df2137fcf91adfda954cf0c6bd1fd0fc0e72bb28febd63183ea6f58cf3b98700395d805673d1078afeeec6c9010001	\\x5e1709c0d2d7220942a89c74697374ffde8a689585d3071d0163cdd42adf4325b095a1aa212469a35f4ef84a004c4dd249d60ec1f106a4b2e0c33a0e585c5309	1667233319000000	1667838119000000	1730910119000000	1825518119000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
141	\\x4c618d5e1556883433922a87e2b4302e77d5c6f1185367ba9b420c8929b65bbb1072b73f5385800b0d5b13c235b071103dfec44ba8ac540921c99e1c233fd01b	1	0	\\x000000010000000000800003b0dd9dd67b887905f3d187111b6ec56ef0111c26a0a1fb5d9168d904bb804ef138675a4beb28bf20cbb81e307d89a36ee285b228485715e9f5d04a301253f3f4a4f67a0d4e2a79e6fd5afd7bcb80d5ddf9d012fb8ba87fad3e9f1b98d431e409f17bb808aa8c7e532e520a5c4af03ebbf21096319504efb953e9eb928c5567f5010001	\\xfd7dd4abd3b5705bf8ce444ffe9405b5f296ac0cba651840d462e863289db7f572940e41178cd5a1ba4cf34e0bc633c84aa6ba5279f42bea9a5b114ee70e9604	1671464819000000	1672069619000000	1735141619000000	1829749619000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
142	\\x595defeb88f5f049af5815c9116f5ef0f31955c2f2efa799a1b309d7ec8145e81df2b92d55faf0f4c131ac7ef14cb8b4dfdd7dde8b059f2e705146d07470693c	1	0	\\x000000010000000000800003a3fec67edd2efd76abc0e58792a31e4bf5b927fb2561e6e0353ca98681ba49dad3ea25bd5e068629d0278a9b15c890e32a17d1f91b909766b850e9d306e3029ddd0a1a2cf1b3746559a6ce30baf3594031f3e82459b42a8e4b969a3ff755f4fadca0443ad7406b7bf19e588fa1eb8b44262f7e1fd0e046f4107cf08089be3c07010001	\\xcfedd0d3ffbb7dfeaf2674d8bfc650ee007c7f0c3755e29963dd164b979888873f13885ea18513b2a7d8456e0382e5024d4b9728f6f341abc4e43bb48b8de60d	1675091819000000	1675696619000000	1738768619000000	1833376619000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
143	\\x5ac5f399a27bc7fe166e39ccd25b35cc3cd1a6647c12f73fc535ecc8723429bd15abdcf81235483fb5039a3ad16b1e0877e2b58cc5ab78e2728c7ef32a0e08d7	1	0	\\x000000010000000000800003bf22b4989143d0d8642233c60c113c5f97f0d345868b0aa24968968ff7467bcca05ade7553ccbcc93d347848ba1652c1ee6aa9209335c7afc0ffd087b1fb2d669e72405815e7b670195a7d2834f3af7d48c7e30da0f774779e8c6150404d5ff17ff64d3fa4123d7ecd52f2254c37a7fce0e8ee08faf8de18886bf072c818d173010001	\\xf2765db9432da3237a85697710700ffbe8a289de60bd50628bee73bc7eb447a087d88345f014299ed165b0adc8d02d33563e6f061d876181bd86c74cc7fb5001	1667837819000000	1668442619000000	1731514619000000	1826122619000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
144	\\x5e0d658eb5e40166a5781ba1024301bcc01e02616a26f26c6b969f6f025ab8728e36f8063cc95463aa9faf35688bb5e4fcb888d8f61c69bc76772b0f7194141c	1	0	\\x000000010000000000800003c949a8179947b427e756262aea36c0e6a4fba56085053837c3329dfaf66396584d8ece616164b84cbef897223da3af2d5d1da01e04de6bed22b4bb397648a7ba3a5adef228eb4bbea78b6f14ddbd40a3980f2c653bf09a2c698d8959f19f3133b751aa2ab1313e1dccc42ebc3853e0b7e4972bc29107873bf070d243bd7f155b010001	\\x9922b7001aeb3b9c1cc335684f98d4322ac4406e88e4486c01fd5c3ce31fbe4516d2d7c3c3fe9cecbb2c4423ff1cb6fd2d6d88b06efb89c63f8c4b4a959ce50a	1651516319000000	1652121119000000	1715193119000000	1809801119000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
145	\\x6325a2d0e5c74fe9e284f2fd9bc3761b397ca1427da853bed28e944b59da31bef82991db5ba2ef96c4f2a9624eae24033ddec1ee955c14e73b4d14dbef44523f	1	0	\\x000000010000000000800003a9dd1d83b28945724c26ff126eee3f430dc5e58a478fc2ffb317c868b818ce9dcc0f068f0ce768fa581c1263c75fb6f00860d2759b01bf057cced91c5b955c70edeeb34fabef196554bbd170094ad8fc617db997ed35ad3f55c4cc0ec51d4dfa42fb6aee67b77b6eecf46bc3016cc56bcf13060eb0da073bc3d321aeed6a6589010001	\\xfc132372b42cad96c63d3ba17a8c9ecc939f06d010287eee0eebcf5e1f1585abdc627af9c611fac47570cf1906754590e0d0ac3803e6ae46898e1e2c124ee405	1651516319000000	1652121119000000	1715193119000000	1809801119000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
146	\\x64e5a57d8ffde81687d99ce2a5787538961ae0d438f6f2fc5dff04ec24eaf2b01d710986c26bd9c6cfd3fb8b45ee64f8e9ff245ff76605532b21e59358517486	1	0	\\x000000010000000000800003bf87cc255e1609ab0d14c86cc551e474d850770d395663e343c5308f4f95f0971790dae9b18d722bf2e2f830cdd6608c42cbb790924df16082d25463bc9206e8692d9fff51196d8923b198e91db46572a74e90a9637c0ec76da14ae2e9671aa1f291864b571a37fc5acf1a436b4b0ec536e8691623210298db5436fce69f88a1010001	\\x260376fb9499d57fd2ea9d8405433ac349499db9e458c4b3dd2573ba3574df5d3476e1fc2c891c4f698ca19afe8412f1db20b7f6ab69a899ff98f4309f8cf503	1680532319000000	1681137119000000	1744209119000000	1838817119000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
147	\\x67a95f1054c3da573d0c6d1f13b9c6e0b2daa946ccfd6d1f7e53416e1332581beed1ffea16ef1326b3447fd27973d91b1afb9f1e8cdc9db2dcc813bd72ceeb29	1	0	\\x000000010000000000800003ceba1e5585225f50eb998443b256df2cd3b3876181d856e0d64de7bd06cf3595876821f82ba53026808f931f4a35b66fe985c0f1ea21e21d9db608027fe2f5f869d439519bf1abe20c2f447c43e4235a1ceb29b8921f86a438045f7f48d69c090aebd220425269148d5c2aa8197beaf111c4fa166ee08cc59dcb9f223aa18e5b010001	\\xf16e6bbbbecaac2d69e13778aeffbab312ed6f1b6609a27cd8fb1ca35f07e857dbc44701df36940805e3bfceea9b704591bb20ff7880d878aef153095a412804	1666628819000000	1667233619000000	1730305619000000	1824913619000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
148	\\x67d5e0df7046ce05efe646b618e45348cde0112033958c9cfac879968845bf2ce74294f5f79212994b853e747d5cd06b6895a5a014af950bcd0bf2a1904adc05	1	0	\\x000000010000000000800003b8d299535129a376ae3600831894311c20543b92e1496ca8244330a03112d850ba1f7cccf53809026ededb9e87d848800da431a1d52cfbb8aa0bb2f4f3b0f8cb49e6c6800b5dcd4197c380b54a404ed864ce538a8f6e01ca465dfb0f07f9828b71186748e6136f9e8659aa2be35876e6761eff6d92bcac00a5ebfee2a7776831010001	\\x47d4efc1bfd3a373457366812dbfa93e80b69fb744042efafa9c4f69e5ab68e347936dfc65c2b25b914cddb831ce50c63251ef39f2412626bfa8b339cc9c7c0f	1681136819000000	1681741619000000	1744813619000000	1839421619000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
149	\\x69fd0473806c855671749625d0756821d35e4da9c2704e0202368986bf47ab0d6f920a05e92ede9b3bf35c1f218677cf6099dbe533f9902bdf840866c471f81a	1	0	\\x000000010000000000800003d6287579dc35015d135eec4b787d89f97ad3254a7fba4ca3939e53a646acda6e74d504b7c09151a2ddca95b678e973c36343dd4a1ed53e9c8f059ce0c5f35cd341e6afd4a9563857867d5d656cbae3f9f1c9db90515d565676529d4d04c97baca7c6c800a66ec5e3af50bac276ef0c01f5ee8a4ff4f7060145f912cbc0b6fdbf010001	\\x2f9f20857be5e3530b46f6903692d670ccaabe70aecd5edeb4f72d890d78568fe6bec7a023cb116aac7a767d91469b867e7fcbe1bdbf0959e442102429c9c701	1674487319000000	1675092119000000	1738164119000000	1832772119000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
150	\\x6ea93cdbf1064093d45c4736d442bb0606e752dd377faaa43b90f98347307dcb717fdbc7636d701c371ddfde5b3e6e300cdeb5c072dd902b014e6709922df695	1	0	\\x000000010000000000800003d2fb77afcacebc7f9f5171da2f9c379607567d41e6c01092b4fdaf727688acb61c42b66af9a3f71c6b1d993cb701431f48b1d76acd3ab7ce9161c14640892cb669ebd7c74283c073ebd62767c6768cdbfb19735e1271e31f3082a1f1c3d39f24312046419e92298eeac55fd029e69d865677256827e7df266c5a2228cf3e03e5010001	\\x643fb3452fd940ba88c319574e5b07fde6bd9fd47d80dc432d74a626d7b95085f82c1906b30e55e444f72ba3f0dcbc94af12c3783650d033482fd707689c040a	1675696319000000	1676301119000000	1739373119000000	1833981119000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
151	\\x708574a5bf50bb26821b68567cf1db19db42646432cb2adb5a637d0e4d62920c9b1f2b05cc53513107481f21ed6e9941f69f9b08ce8ea92cf8effc30b6f3f46e	1	0	\\x000000010000000000800003b708a4be91c18ecd794127acaa39224388f87f622d97bbfed77d19a03586b59d5cbb94baa8a1688524626b399e48d57c50014637bdfed8fe5fb07efa72953bd4d283e1b35cc475827218ff1601c57a1ddf8c383e54cbcdecbf70befb3e49845fbbc2484874b7b7858444b222fe9d9d75e52a45dd4823cbeafd0c1c2de772cbbd010001	\\x089239f214d32e1978d06ee268c729573c87eb202c6881b09ed81d2cec29f94055174381e9dfc0cadd338ff1ee1aa8e12f748e4fad7c13090da763f82b215a0d	1661188319000000	1661793119000000	1724865119000000	1819473119000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
152	\\x77ed778357a0a55fb29c59f7c0b157d6687f13e9f4fcd971f1390cc19faa5dca154f602465c9c12a94020dd11fa4ecf1350c0eb3cf3a8a5b55a0d55dd2416f4a	1	0	\\x000000010000000000800003cd2dd69151e298d6c86e1e16f6cdf25d338b3a8eebe22d169067ebd1d8d2ee0b57723b9bcfccc8730e9acba9a3199664d5304d4aa33525b0b52a4e9c47d131b786765801ee5d1e26bfe7102f0474c80c7182ea339edd6c79d7650fd1716b1579534a36339736b6e1d2b33c51ec3233c851174c77b5489e9af83765633a1ccd5b010001	\\xe0bf403de038974abe2ce63ab329226829e7c32ece9d2eb3c71a7e79cd7bb9cfc3940288356604621dc1b833bc958788ed61d10d265fee1fcff8d09e0ae7e006	1667233319000000	1667838119000000	1730910119000000	1825518119000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
153	\\x79adc66a02e5601068ab4d63a978636a182c3fbd51e913f8c01b729e71180877e4eeedc9461ae2215603efa7f91903f2a33d88c37515c8ae618c686e71b4e851	1	0	\\x000000010000000000800003e4fd67449668bfd7bf6899c6aba0f86fc4683f66e857eddafb07e7bfec89ceff1c2244ccb51136eaa02f06bb030a289a5b33b1a08b4675eac57d4b8086d9c627cd2303869b97ac96004f1d7da4510e25786036532b4d1348dc83cfece06331ce70c8e0fc69877dbf93b62e5c3572ea2ffae65989e7d13f31b64cd1264b49cb51010001	\\x20aec60aff078c3bfa627edd29b88633c59adce3205623004bc125b4a3cb4c552f7d320329dcc593ca6fcf9ee9067840ea4cc03dd42fa44606b89f47fad52c08	1678718819000000	1679323619000000	1742395619000000	1837003619000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
154	\\x7a896868d3d78b7b3a217a7a2675c8fe008ecf0d45c657953fdcb829d1b822f00ed738dd46b3996924521d77f90a84300a2b2e8c4912ced5012908d514be7eac	1	0	\\x000000010000000000800003c4d0574345795ea7e4bdf0ad3fef0f726942dfb7464ec8d28238c8162e171f4fcb665db12193e56105a740cb323816a0f34e28ba93a3ea7e80eaa6ff692990bdcaee311fd006e2cab10d15116a80266fcb3364b95e0ca8c72e58d9c67cc9e0652b3c3db5c7fc2cb2fad114425b368beb98c88a9e26e03fef26abdbc36a892773010001	\\xcec0461b151d42d823a4bb04f7a7c9ed76c1317d0775ab1c7509a9631f0f270f56bc65b8282834ea64693d3271efc6f470bc97c5a463aacfb9932517c353350e	1652120819000000	1652725619000000	1715797619000000	1810405619000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
155	\\x7b295f49abdaefd048844b871e3d2b99f5c09ab03a094cbd52602d0ede694a9430c9a45e9c7b09d0e43e04b6fef4c22b6523adb670cd7d7520bfd85d7427315a	1	0	\\x000000010000000000800003fa641c97c5fddd3514315eaf9fad697a3b6bca187da8024eda2d8988cb01c76b96ee2df6f8c334919467e499ea18904e4afebd377908da7d4a394047d020d6d5fe92384beccaff3188bb4248b839d12bfc518f2545a1f66dbcb7707d4fdfa7939615344376839d7de9609c4561bf3f29d79784b3a97fd3a227406e6d39612151010001	\\xeef3d8f3bafa18609ceb365d4f93f06b2e1d5c8c500b48e5c384fc218cf15773fb043d1a064bcac523f64c5a017b2197f2278b6d06eca34047f09863fb3bb70c	1673882819000000	1674487619000000	1737559619000000	1832167619000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
156	\\x7e412264a754b7c7f94f50f5426fb7a579bc2fc7f8412df39b2d92e4e2aadf840c99eea10541ae74cfd8c58acceaeb7aecd16ca95b6945d508eebf8b9b1799f0	1	0	\\x000000010000000000800003c1d07a747cd8a0ee4ea25ef3e1cc643cc87d5c3adf2e1ee6207b286408d286461e23b4ecce6ef7e2de787ca16541199ea7fff9edfb9117c0919bce6eb14b7d212c27b8090795ecec6d880b5a2ef066e1d7d7f7826e6da5d92cc0e1ffa895056d92d496155663556cb558d1e56a7627cc9dc32cfe6dd1a3b1514a29386e131a75010001	\\x45fa3619931a8e185a37c0bcd7a5de10b9cc9399e7e0e457687ea867d6ee0faaa275fa7f99cdc1e16d40ff46a914f812631f77da6d0165e326e4145275823b0d	1656352319000000	1656957119000000	1720029119000000	1814637119000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
157	\\x827924cd5084b415e47b0a22bec9f4dc51be09a53ecc5494aa801d0996357b7de32306e6e89eed6ed5ce659c3cef60dd1d7cde8beea7d21db6b8be0991880187	1	0	\\x000000010000000000800003abb02d21770b55c206ef5e9bea7647af25fa282683cc208e52a5404d9bb3d7bf400f89c19ff543d61e5678b22aa7f615de187b3c722bb6d8acf1f9e75fa9bfe367d89f3fa050d9c2f34376b475608887cb4c1a56b0d99ac90bb1a2c896a72a6104f1b46c2ae1745c582ea6ba3562eea90b6594aed5e2201b168f5e21a47eb7ad010001	\\xfcf1615f93d3653b026c9501e8980308fd884e7cc0e13c77898b411e0f707fef56ba688dc99ee3110b6b89157cc835b5b9c8975f9aa6216447e58b5831bf6004	1659979319000000	1660584119000000	1723656119000000	1818264119000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
158	\\x828142ffae781b28f02552cd28ff1197947cb15cf48205f631aabb8f91497e6e0f19a6efe7ccc679cf28eeccc25974b45c238c72ffa4eca8b7abac0950b9620d	1	0	\\x000000010000000000800003a6a4ffe6e74d47dfcb022bd6fa48231f3bfb5ceedaef0827bed6abe6208258ceec3e5be273283b2ce863a1c5d593285bb7b3f21352a019754309540df38e91459a5ee6d53574ed056c4ad4cfaca23cbe4a209c770f0787fb63a09ff5098eeb53f4fc260c634a54a0df16fc6f2edf5c4540ba287bbcfc4ff12389092294ed1d6b010001	\\xadf3461fe93046eb3f331c3b0b7ad90919c10ce0198eb1cffdd0c718f5c0dcad4fe4cdac54a28ca9623ae6771be8105772fa014dcad30dc25f2c1472d1b2dc0a	1681136819000000	1681741619000000	1744813619000000	1839421619000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
159	\\x84bd1cccb57854d0854a9470b076a250b81885e21927be035d3e02c926db6d026d71c1773e26f7a35dafa1f370ed5ac398d4aa61b949680c45ec55ad100f23ea	1	0	\\x000000010000000000800003cb425560629d8ef2e543a5d7dcbb9f9c7b1ca2a2e47c6023555239845ddb554ad1131f011bf11c06b09a847fe22a8c0400e5234375167ac660f13a5b24e54913696a91a6b0674aecdd110d18b64368fb32790d261957a4649e79a1db87b71b530b6e73e44cda0b5bc3e4e2ca4611d74210eb7181897cdf6630fdf13699b44ac7010001	\\x531a09407725c4b571b07ab5f0d3e97523ec61580c0fd8033bbc2839b343a0f78334ea8adf03c3efbc885546c30bbbd724ce7614a0d7d11919e003eacfbddd04	1669046819000000	1669651619000000	1732723619000000	1827331619000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
160	\\x85fda3c7794be933fcc7eb95528c09c678a5729ba40e2e0361a8dc4219291dbc9ed5d4b05bd87a4643dfb0f49d5f963d863eed160d34a5e98dc0d4cca3a173fa	1	0	\\x000000010000000000800003e8b760e529b5a1fd55b4ef816eeca1260e107565516511ec3f48c4d6ff4b97795624e95e571feac6258691b38da2c25ab8a7299ae6aabf0b3f044dec76eb4be4f92f04b5f5733ef92d383e5231c565c77023e72a9049dc014780eb41a82bb283a99571166444e3a26b00db75cb851aabe3a89968cd39497784723f889afa843b010001	\\xe31c1a1f234d9684f52c6ddfd0b6aab27c55454280ad418c5c9b57611d65f3a7c81cc8e23bb7a9f5c26e3c8fdd9477d00ba6856c6f14def3de1d8521b271ba04	1679323319000000	1679928119000000	1743000119000000	1837608119000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
161	\\x87796bdccca943fd77cd240c86c346cf75223df569e33fb46eb1fec5a983027f0227cda10c1166a3ae29d3c5b9eee81ed6a1f019132dab3005c51f28962ddb85	1	0	\\x000000010000000000800003a0f2c48e193b2ca788b7fc844525c6ff4e20333a303f3175b382882a5c799626cb9484699ea2b8ee06a1d06b762958dc6955b4ec40266f9ffd9cdddc94bc609b1986c0253de7f6a6500fa94cd9e822bbca48360e35079244450f8c02e409ec93deae2c2e81243ec4e7b0cadb37dc8bff3a76b58a8fc695f0c816e62dfcd7929d010001	\\xfefa1c4cb64212eafdf7b94fca95baf1cdd17a49a9bcaa54bbb84416ee17229169c338f3680ced3b94c1d6ffb9beadfe927ddf4b84a35267f0d762d21b2cd808	1673278319000000	1673883119000000	1736955119000000	1831563119000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
162	\\x8bc5e7a366723391a5c14efe2ff0133102c0712b2dfe3d8d91d4233edd62cd863511339771b93596ce6ef6bbb4b490811efac46d49ebc1bdcd54c61421c62d78	1	0	\\x000000010000000000800003d0d5bbc05b5b7dde895b8f48b35feccacc746685790bfebed17e0fc85ace6c9daf9ca41ea312839c4fdd91737adc061a60e926e511feaf72461b827b6195d0d0cc67b1fb7cab1a9f79b4b55d5c519f88d6131010f873a23f7ebbce148eb8d71efe11af2ff7e4677a4f3b9a4eaaa370e0c807b4ecbd8c7089f734aece43b4e1df010001	\\x67b8bcc25ad7fc0cdbb796eed2497121b3599535819c874ea4d37cf79f246ad410c245e3ab19ba73462ae15fc545ac04955894dcc5a94819b91e588daa931601	1659374819000000	1659979619000000	1723051619000000	1817659619000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
163	\\x8c3dd4aaaa8b9fb5e1f84fee52ca8011bf0603566c56498ec28a2709e2f3e33f437d83cc224964546d3eb27113f6d1d6d5baffc6ccc6bb9c0d50adc3787a230a	1	0	\\x000000010000000000800003b5f5ef4973fa2ef684263beb1f40d4bb3722a952e2de78114d4b6ff7f06608af18ab96f4ac582e19c7380dac111ac16a30f325cc1ca01b37f96947bda9d76be18d14a38f7cd18e0fbd74573d6186363e77047ae944fa5480c591e075aadbbe5b7600f752c764320634e3d93c1b3d29f361c2c06fc10a9418dc9835abb4fcb97f010001	\\xeb6841a8994af73aee7c214b9883ee67068767e8b9affb0b757a0e9fb9b095946f398719ceed44a31c2f6834f497f73d640df4fa9b43da179b3491c88e0d7305	1678718819000000	1679323619000000	1742395619000000	1837003619000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
164	\\x8f91e7315e104be91f02ca4982b2e851cdd8105da1279a20825f0a3ea7818684bb131bb3979f2870938aed5e38e833edad38c772399578681a239867d0b05397	1	0	\\x000000010000000000800003b92891f5417109cfe1f15c002984fdde2e6ca9a49bd1ae2cf9a900d6615eb95207693d3cda9f941dec60ae0a6f632dcfe585a32c855b810a0babda89b14d65e70548045f2e14967d400d9d7ac4dbb7a57ca8693722c3f24d5fb5bd6298ea3b71779f8ffca7b5eab39d5e62a4c8fe699a6b857155ca84028591871cad7a678939010001	\\x8efa19235a8d4fec12f3a25514d52b15eb2807ba1eff203c74e0cae483c4adbc16385d07fa280c623bf5f68a8798d8f1b63cd202a35460b1aad8f2b96a4cdc0c	1661188319000000	1661793119000000	1724865119000000	1819473119000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
165	\\x8fed095dafbf09266197a98ee8838edb651bef152bd0824e4c18af7b2ac0aa14fd15d991785175cbe144d0ed8f3b9350d888ae8ba7b29c496315417ead9df06b	1	0	\\x000000010000000000800003a8e3697a9b4efe50c9ed3347d162d1b5669f28b0f62f1a42e190a543ad747004807873e385d12dce697c04c1d425187fef99df42d6e8ad5eb2fbd278fd5c1d77fcb96639c7739df59ef6f66571842dc25935e743d07d73accc58924798e0eae9a96472cec2a0a54b2e450e814c7bad1284e823244841caa5023358600b7aabbd010001	\\x186abba9aa37bbaa8fb5f13b7bf67643083fd0612631e18eca6662ff00c0aec0e471107001d8ca57cbdb972732027b2673778046b00fef2070a99eec4f150902	1655143319000000	1655748119000000	1718820119000000	1813428119000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
166	\\x901183fa770d29e2a8e1187c59bdb1f24b5f3b883eac537bd4608da23ae2ff3b67f8e1ee621c1137af25083c8eec26a1560acce4fc7f8f7a1afd385925c794e7	1	0	\\x000000010000000000800003a3cfef651b3c451aa79c357802ea4df30c763cd75ea138cdff3e9c9e2637387f461cf5e6510c32832caf984ea4363d19c856e1092dd21e9334e6ffd5207724af12fb22d9361af709fca39310f0c01cbc61fa806e9f84ea0c5e1d5458ea7d2b569e8bc787e9418f7646e4189d84cf28c959b8caac06988ecf04365a125761e44d010001	\\xb5c5de59d049eeed181dfa09894dbf2763f135f2ff07322fb0f9a1a12f9d8e2dc5ae8c8ebec88af3d791a47f96e2737db0d07763c45ad2d6d8ed95a686cab10e	1655747819000000	1656352619000000	1719424619000000	1814032619000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
167	\\x92d505ef6a015d377d733668d7e81d29841469e84a50f888c6acd6b3c7892babb29b2fcc74809b7fd4db29f046223109ecb422bd263358b2f7135b493ad524e4	1	0	\\x000000010000000000800003c2f265946f091df4d9e7d310a8421ec49a3fa88ce1e94121d67c7ad33635290ee7da98f9a30887b7e4c3c5419f6662a40b568bc276949ec64725844cd316670f2688560d5cf72cfa205a6db637c83fa4caf60de077b12a2e2c3f5eb91282d9287d117bac321d7b0b6f531d000732889879660164ebda2d44491e4f9ac1b3d3bb010001	\\xdaeaa9941e4b07073d2b8d419824eeaa6756a5572ba6c482b7ed1c2ea45e8dd8e42abd029f0a79b3ffd2cee13e67202317e04b5d7f5b8ea184790f899f9bcb0f	1675696319000000	1676301119000000	1739373119000000	1833981119000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
168	\\x93a990f43330fd8885224399eb1f095061785b465a3795a9edb743664b3301c5d2985ada4cd7e00e9ce1211c36773483ff1279c3f517a7cc80dd3431d15441fa	1	0	\\x000000010000000000800003cc7d88c36c86bba496a93bfa789c3ffc5189f93b368b0a38b68be3c9ec1a0df5c998903143d024efcf5fc54824af07ba6bdad9a11185ad5461e436dd3c742ce4a01d24555d6e4a2533665480d5066de65204465cf802933a5e5764ef1a7d3ba7ff084f4eb12dbfeede606a7b4e816b9e85ab559a4abb674e8c63bca71346a57f010001	\\x7a0c5a1616e050deebe302d2d45356527a1bb7677db8ea48dda66cfaa2a539f4f427117002e18099fde128ca17bd7f5b610b1dc39ac7b9b6e6322af385e74a05	1652120819000000	1652725619000000	1715797619000000	1810405619000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
169	\\x940d9111014209b2c13431a59fa590b2e4b5c183a1f372c39038a6133fc9520b371394158e158970cbf084185fee39bbe0da673a01bd3f44b06f2a2faa038029	1	0	\\x000000010000000000800003aa4ee26873001cef5f154efe6aeae74d762c95be1dc1600d99502c553118c7055efd53dcf29f57345db50c3fe6e07815738cf490b5f6e062c1498405a0f19a580ac8c77de7c73b02e21cbe7d71c652c3108ca77149708f0c5879e9c327d80eca0a97be0938d425c9df3b73b01b5bdd4281d75c12e21b57cb4c7ffc90e6881137010001	\\xf6f47b483e933dd9dcd310d3c0ee9b523466f2b0060cb4167d9168ee7562f5837642d635c0464d212e99fb69337a4a7cf005403c8d5ade41504c15edf8459806	1676300819000000	1676905619000000	1739977619000000	1834585619000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
170	\\x94699c38aa90e6d618dce6488385c54dc89dd7a47b154ed53268852dbf174ef0d16cc2fa93705bd3a1435369fa1592dbc6d9a6a7e90fa50772aa9ce2b80131f8	1	0	\\x000000010000000000800003c0ddb188c35ca97def81ba25364538b68fe42e6b1cc6f26c15dbf2d68d1f51e1e7ad404d6d42cc3bcd6c41852f485a2d6b5d2df03716affdfcfad96d2d357328d97b0f2dba55e91af718cf1bc08e89ef7bfe6091880bf4fd2b4a83b5a40f4b32d3415049a9dd4dbb0c397db71bf26e82b74de44fb5c90f4ab23609849d6e797f010001	\\x8a7cab2b1754b720eabdfea47edf459740e79e0ba736b8603f9c080c1da5858479612108bbf0438518a275b165b2f289bedf54173973190d945d7708d4f86604	1670255819000000	1670860619000000	1733932619000000	1828540619000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
171	\\x94858b32901d6b5bc69c8a57fac1c9dbcae56e7d1dcecf3982199401d7cc29289a6c94db50b1db79f8e6fa29a3d7b89577bc8454c15d53a1a38a96b982bfd76b	1	0	\\x000000010000000000800003c7ec5836d8afb7ac596f55675b1c3840518e9ef3ef1d269f1ad5d52708340f7aaf0b92a52eccfd992d5492a34c5db950606cc449e47e9fd94cb285672ddac37ca2d7839641ec769a8ec05758abfa06c2f82f836e1743cb21f0d362e75a3e5897fc7524d2fe46fb6d9d629a78c35351963c5651bd6317c35185e5bc89927fd671010001	\\x74dff100f6abfe55df6de2ea0f8d2e07b667023a13b63b1915b7b473e316c91c06e3c0e33ee6293ec95cedd2e76a484d8ca3a3ca1ea3f676f1d9c779c316f10b	1655747819000000	1656352619000000	1719424619000000	1814032619000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
172	\\x978130647322413b5e47dbe96354dd5c8360e92c2075ea898fe703de2e4dd4c40cd96378994ca9e09e9e401cbc8b98693fd71f6ff825bc444db8e2cc28b3a6db	1	0	\\x000000010000000000800003c5a81906d85f5e821f22e50504b1739e94a4aaea324bb31c4dd5d0f5b49104c01ae3d4c3f89fd5fd19d4831efea6e81d613d384723e0fc69cf61ddbcccc49cab12ed3d2f520f15a9d1098cdf75093c6c8aeed15af92c5c741222a9fbabe7a74865b793c9bc7dd0ec81ffc3f662dc41b94e52c7e08ce5ae26f759e2f8ba46a01b010001	\\xe860388c438ecaa4f5fb2635761e836cf7ba2b827d1673c4225b14d88041b6f2b4f2fab51708b02be9be2fd4bc07b3f96e121af864a00dcbe27b5ce8e97f3e0f	1677509819000000	1678114619000000	1741186619000000	1835794619000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
173	\\x9811425b613b4f20bdf65b0ae0dd65e1c8d1934026f043ebac3e7d3f068c224a31c9485f6cadc0423f82e7a90bab53c02302e10b912c81fe41d47f1d596c722b	1	0	\\x000000010000000000800003e4bc445accdcfc837070fcc9da39ff24c131d80c6e3c5cf77d9c05b7c1fc1eca09e0dfb83777157cd98f01c2bbf0a23419a15d5bc2b66cde67643668ff3c6f3496be5d4b500f8df884a383ef0609d07fbf7aa5b85f6b93a8eada4e79ab3c63bbd39125d4acb6a2841564316f538b684a784b47e02c9244a6ffb323e588602797010001	\\x609e39b1e13f2a14a53af2b00cc9ee846a1b22223aafc715071d68dcd740930ca92b4fa6fdf7270068dfad1e47f2fcb6cbb1cd456805a25361b7b81fe14ce901	1664210819000000	1664815619000000	1727887619000000	1822495619000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
174	\\x9a811f866ee703028b19662c92e5757945e3e7dd0d044745a2e3d5740c30ef5cd718e2a9741e77966ec643aef3c8f61702aedbecd7bfbe216aa24caa783e2064	1	0	\\x000000010000000000800003cc8dcdf8f6d228970d3121c1f988dda083a8d5c46447dff5bf8a9b8ac4f3967d0b457cf832affe4ec4bc320476b1b9b6256e3420bd69cccb93cd101aad385c1ca8dce1bd4ae1ae43f632ac44d75d2989a39d194b8b725f605bbc8e196b648ce301861f02d7e6b0484e4e6083ed8fc45b60d92634b990287b688ea523b062166d010001	\\x43025a57ce14327922579e0520e28bd62805ce01cf49f4fdd7e7218aa53d8b57d85a66c007d88c01ff42ec1d61eefb6da1a8644f3fc96763938244a1599f8400	1663001819000000	1663606619000000	1726678619000000	1821286619000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
175	\\x9b2df8d23591d4bf1b116f92c2154d19bd2819b5fcbb4e461f3bf68b3fe0a95e2bb7a55d8d9675c3ebf72a3d7096764f6a6cef62f95126b308027c9a066dc900	1	0	\\x000000010000000000800003ad4ba4607f5b7a676734c1f3df5281776b9a91077a22effb795c3460657253e2e87340bcef13a6c3af4273af62b309b92781ec98b54282f5f2911bcb98d836a7d55dbf1e3aea4e4244da8c7a7f286b7d31a69b88a6e2eee0fc94745082bb4e11753f0d7ae5974b6a20bc33243bf28c1c4b3068056c2cbb9580e6f74ab536351f010001	\\xdc17a07971e1da1cec63a183238fa6679efd45ac9e16f1a89aea5a5e78df5be6f6b7967f0a6c517353c4af423b5a7df31b26c91afe6d0171e25f0aa5f3685f0f	1672069319000000	1672674119000000	1735746119000000	1830354119000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
176	\\x9b7dfe416d16aca35889494ae1b54abd2396e037dba25ea412b3af7419f728a3909da2fbc70ab3227578fe2396b6243a0423d3ee6610152da430a82c7794da69	1	0	\\x000000010000000000800003d7d82377de23a4ca066222529cba6b4a1fd135b2db23977de26eb03967d232b2965ca681a434a7a9bd4b17a56eb101d8490bbc51c1a103773aae8d8495943b39e3c454703c0d335211dcb74ddf9eeb2646bea7c7806a4bb279fac27024dadcbd82fe3224fef31c6cad147d148417a91d45ebe722e98e7b8453865da33d7fe7a5010001	\\x79e318149c5a3adbefd404ac78f316a92f54c0ae70c48498b28986e8eb84f65343e29d741aaefa689c083359dff82b31e9be6ef894efbd0f7453ba095b81c508	1656352319000000	1656957119000000	1720029119000000	1814637119000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
177	\\x9b89e75f0b5ae64be87fe740a570b1428a78b4b419b14489f5d7d5768e9c00d65d1d0dfc38cd2efd7183b2f5be78589e1b350a5f01332a3145fd0aae9b755274	1	0	\\x000000010000000000800003d264d4201eadc19d40663617a26bd70b54c2c782a6c339094d85626313eb1b06e342dd60c06b92d6b1eb3b8d05891630c595483eb75ac79909d11f8eec33d21f35b2800c840fa00a2c744599ad01a73b16fe1bc2df5210763bbe0282bee6ef88970b63683c63e9600b37ab301d737b65f5e123930324d975829d2eadd75bed4b010001	\\xe1c9225bd0235ca972447262df7b892b47b918ffa627e2d69931c893190b0166cd3763ac5760b52ddbc9a1db941f1ed96b258794990f635a78e62436d060b104	1663001819000000	1663606619000000	1726678619000000	1821286619000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
178	\\x9be157ae0866b824d57bda21b3a1398b06e80daa222279eeb8f299845214b5d134f6dd715c95a7cc822a8177f513fcd643f6d3875b27cc23ec5cfd1689c87ae7	1	0	\\x000000010000000000800003ac1e567b355b11603bcb50292f502a74be45381ff26b82bc543961d919a21bc22a06c4f62bfc5aab0fa782a39575e89b696f95a42db1b957c5ed5474d066aa91d24d98ade9ba87f3272b4f33bc3156ca1f389a5393eeca11f7626ab98b95acd32ef075599d31ee705d151961f4820c2c782606d215797d36761f8b1dd8d5dcf9010001	\\x468361c021707e5c9a3f950d9b6468e56224149e90032cf4cc4663e76d84a42c0ca8b99d2d5d4db40ad36eea3bdc5e0d1706765b3dcb1ab0860353a2f90e750a	1660583819000000	1661188619000000	1724260619000000	1818868619000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
179	\\x9d2566e7a475f6c34f5c08c0b1f8318294bae921c6c31c5ea78e10d1008d70deea9e3db34427791f517a988bdc8ff5144e17197bad987a0960fd4fd58771bace	1	0	\\x000000010000000000800003ae8273bcddf1be5fcb39520d3955a6432b23e07e622f17779a15c757d03f2824ff098d610c5c26bfb78ae6ccf1223976cab7a6aa29500b1daa706cdf8a06f9b9d5bcd17227afc8a06d0f272fc5d89dc33f6e7ea854850b613b2d1a13897769826abe01e759b41486d53efaf44c4531c6acc2c1e2b54db2322be6ca91611e121f010001	\\x156e501dd9503ea7728a7e04c9f827680fe997e55a844e7ff7254718a7fbc951a2d73665262e87870d15e9ce1f535f3afbf4040d65a30e4395d3933102581900	1672673819000000	1673278619000000	1736350619000000	1830958619000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
180	\\x9f59a8c0d00b36a6b230c44ecb96d4684c4ab4bd56e032a4b34b15075aab0c2e34d46ae3fbe4993618c4aa2d364d46b6b7f23b0f97ef2b80aa33423d9a1a0681	1	0	\\x000000010000000000800003d3483097fc56e74b9a0e340fed48bbb5082787f0d8754b69838cfbf4b1e72e9027b290b1d21b454c9ee7392c17afa94e9d697769a842048d7ced56b14c2632dee2df6bf69421d3d5bb70ab2924ce1a7de7c70bf763d57406d6b14eed868e24dd5f2d0c342bf4a7de292bf3f3153c69ba0e8a36cc043378afa9be46013044515b010001	\\x2e5607ff3a8334734e27768622d5a7c08ffa63efc429c9bac95a667c4952ee7cc0f87775861a1db10d0493d580066570b32f4b8788f2a476c620f17b9802940c	1661188319000000	1661793119000000	1724865119000000	1819473119000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
181	\\xa21d20b42e8c047177f8579a9f8eb58fb7766da5d41e99aeae77b39322a245a403e9af0911beb4c9ffdf3aa31aa291e811e76885fd57714eb8c2328f09706af8	1	0	\\x000000010000000000800003c3fd0dbae2f97eda75c313de1f28155fdb5835ba219f48978fad09a23871adff51a0b457b2d7e7e1f43df1e908c653215c9f803e6a6f449198909b61bc6f274c45f1ca01d29d8204ac19331c0bd390bf721c83282de26b35f1dce934f1d4e218cfc62f769e1e5b9ee9899c645dadadd274cab3e43469b00a64ecadc20884d5dd010001	\\xe19689f9b9e50c617e744e0767cf54266a11ef6e023631d9fc685ce95f391c179e63f1e6cb2a175eacabec93ebb10ae7658d579ed5eddc64ec779c6a0e736f07	1673278319000000	1673883119000000	1736955119000000	1831563119000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
182	\\xa439e72732c9f8293fce629b29173bd5477514faac1024341be986546b165c3f34eed40a4b4690040b314739bc2dc22caa76993ea399441ff68948c7e3b61c67	1	0	\\x000000010000000000800003ac410c35cfbba717c75dfc052ce366063756e2656f7650aef3587a5547474e783cb19e0d6dd05a1dd0a94f9935ceb0b8191dceca1d166784242ba65f2bf558fdf9deacbdebe87f6ca561dd44a51afb6c92e9eae1566834c72ed5757097fa7bc720a7adb169daa99c1c89f61985034e3588f1d656c707293b537bf94b6704e221010001	\\x42ceedb622b28092bb334727bb7d85e269c20d01fe5954ff0bcbb0bc5d04b633508e4766bed508ebcc16da1a27143ca66c7dbb51a58214eefc92a0d9e0281506	1657561319000000	1658166119000000	1721238119000000	1815846119000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
183	\\xa67574c75324e8204b8f6e166c0e29747b00ce04db10c16ac8c0825146402fec27f956afcbe7f0d48c963d7cbc7194a6dbef42a5a718ec8da15b7a32f715788d	1	0	\\x000000010000000000800003d2a6d08f17476e886f7d03e28c053fe31f9e14b72dffa30d92a9f6f58cc4e0096e7502c4b8381c2039f292b3edf458a85079eb80508034b370d51c98e825ddf1e253b4b4459786d99bd67915abdba0cba18fc97e17ab33dc6cc09a9b3979ea885c7c77294f7e052ee287503fe58bf107ec3289b3b70954a22107d5571b537ea3010001	\\x46f76f31bb8fff056fef9dfe3b13d8ab3a0ea6162cf73fc84465c9979b18512bfef52f94c70532a00b11a8c49d695560dba2ed7606b89a17ba3c13361abbc208	1658770319000000	1659375119000000	1722447119000000	1817055119000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
184	\\xa80934e30303db2299ecb99df1fb48b356b80ce1d428e441933cb3d521b6bd95c81f4baf5345da9d728ed70462dccd8ffda34df73446ce8fc5f21fa7b64f3f5d	1	0	\\x000000010000000000800003abb8735b193c31213cda67cdfcd72239efefa6f51af5ab77c762f0e11275b0156a2397f5fdad58e3be53451bc9ca5379c5e4cc99a2151f88140f5cc005dd3394fcc1cedd119c3db7ef4ab5cbbc7d2dc47955e822047e4cfedb221e992f0b4091da02dec3f6de8c448300d9967097dfed16a116dc6e3f0a78e28b122958bda257010001	\\x422f6f3fb8eceb5c48adc33154f86e54619d1325307b11e41ad363c5e452db795664153d2931a471c218fd246f8fdcce188a30166f797de26df3d33b223f1f0b	1679323319000000	1679928119000000	1743000119000000	1837608119000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
185	\\xa959f09afddc064af297429ca9c0922433bb0a95985fdb461c01fb4405340e6cdc6063aade49379564f1bf12dc47a32cf5d0420c368d57e5b2403d1576bc313f	1	0	\\x000000010000000000800003d50863fddb25f15bd48d951be0db95e852f36af99e8571fc39b76bfec9c73451e5fdc185b6b02cf08d77fc34682a971c0f4e99b9442eee860796403fc7a6cc0ae827354d5b75ed0fd827d441c5b857ac7595369972a48b84cbf815ff1294e1e34edd77fcd86d4bd8f54d39d6a1ff3e6d0e9b923eb7cc57cba047d818ca85c6d9010001	\\x1d636d72c086015cdcda6c2f9f84eae4fbaa1a7f37c260517c7db82d5e45c8a6fbce5cebb28c4f7d9a8a4d34a3165b350323f6492147e7269794595eb12b280c	1678114319000000	1678719119000000	1741791119000000	1836399119000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
186	\\xaedddd2c39f441c9c7cacc9c2fa71e8c885e148d86cfcd47b07d8388a4062e948a4f4a254b89ebcaa52af54592581a22d4acc3380570a690f4dd88e6f4c7fa9a	1	0	\\x000000010000000000800003d1c1dec52c7c0c5d71025a19c9113611ab745e24d083406fdcd7517dee697e2225b2cd995eba6700095fb0b9157c6b80a57ac7a42992cab6e9aef6de5de190e2f883c26070ad6ecb8b0e2794653f4bed4780eba1b8e13ad6af612b8223db878303b15edb4c12e796aef6b746d676d2101d7594f7facd9d941d267fa1e198c3d1010001	\\xb4d47d5e123cd9be15c70ce647da9a37afc725e08098bb446e86d412ab1658723e72b7ac593e79dda10d9139a8f0409071302d4db9816997775064866473320e	1652725319000000	1653330119000000	1716402119000000	1811010119000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
187	\\xaf6d4033d7cd2b437f66d2084893ad556054a49570ee93f6abdd41731da1c795bbb75e18c582c920cf54abba96c009bc6d226818641a8937572d92682be6f559	1	0	\\x000000010000000000800003d50099439c0e53800d050b85c0be8044810a4628b2324f0f319fdf7e0cfc68c35f3d052f08379dd5f2e8843c7215279151d884e0727282580744375ac297422fab672c523e3f435e7a9a6dcfab775c665cf26ffe57631e301bcf334f69a6a1afcd359bace332d29b7b94a5eef5684080487a1c082568104a90248f9d2a9a85a3010001	\\x30963b50fbd087c53ce568ce2d0fba66bf8c3499cf6d88a3452a7a3fa02107499b569047b09ecdf5a97fbe4a3750cc921ba1db89b32e935b096d7fe194279b00	1665419819000000	1666024619000000	1729096619000000	1823704619000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
188	\\xb4a53bf5ae524212799dae76bbb820c3f2ef83f303357408c6eccb72b5264a50e9f65cfdd19d3f0b366738521c540ff7209a8ff132d408d5d8f3da7b041eb9b3	1	0	\\x000000010000000000800003e492344922c92381976aebe3f6e1f9e1e1255cfadce13cee248f634e6526f260bde9069a1c2c0e7b4f160b82831a6dc4a45684ec70f8f215d03056baf859e8fc3bdea4cadc4a896f738de13522ebc0c1461077abbbe974ffaf37183bbab2f4b3e2883d155ca2ef63d4f4522544d416ae0c4e399b2b8667f0780edb1ee85b3ee9010001	\\xcaca07136aeccf11efa65a53cdea03d1cee72c887c53c186701144d1a8d4c15d9e866165c102424a944632ef57486aeb0089d4c1ce55d9fb4d7c70286f6a2809	1655143319000000	1655748119000000	1718820119000000	1813428119000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
189	\\xb8f5d9b2504dd36985a66d6d272bdc2d33bc0f4bde0eca000186091106cbe1c5ae5d29386d4299f60deca6cadac246adfd7fbc554e73ae37dc33a07d93781cde	1	0	\\x000000010000000000800003ab350260b7700bb2c8531925ba7718129df162d545c6c1b3a8c5d0b9c10d748fd690a46f126f8bf41f99a6470775715b744a9267d1b52e53caef450e021c46f24a02d91030277816d14b8ab630f1d71a8d609a46e45ce9635bf2c2d4af73524ae35ecc60b6ee2a04e916b63751f28619c0d4c38c20e46712774b7a38187aadf3010001	\\xedcb9f2ecbd5edea80a6e9862862d85bef04fefd0f5f5ccf6b8a937870894df656b0cc88f1d49d33e1150db79a418e7a27b6e4e6a3c54bce0b5020718e965702	1660583819000000	1661188619000000	1724260619000000	1818868619000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
190	\\xbbe1bafed9e05939410e3d7326397047de4d4f6c6fa2b27aedfd0423368ca7e6ed5468175f17ed77debc6b25f1f42e8b0fbe488eb2e583a0b3c6a36af1af2b7b	1	0	\\x0000000100000000008000039861d6b17e6b55c759711ccf42ba42f7e7f87346153b1e1b33a6a91a5e156f36f01e27cd5a70d3d0c4c899b439315fbdf1faee3c4f8e0d57afb599fcfe4ed6636c8d188c12895ecfa3fc2032c00ac0a12b14bf06b863fe42296f09fd0c681fc365515939b99fb7b364590d8e11069ccfdafe01d64edd5423b54eb20ce74d6587010001	\\x1487e35ea43e4cc878b4986a9ebe92d8ae168f84c6bc90ca5e8a3237a5ffc2807ab561324d905cb185525481cd34b25a1a27f2c6cda1e7f066a4dc39b4a4dd03	1664815319000000	1665420119000000	1728492119000000	1823100119000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
191	\\xbcf519eb0766e61e27d99e8ac535b6761badbb63f4e9d5d64eb964d13e53d953e0f18c974b8b5d9e1d878a2ef4b0c0dadc6b0b37df18418764d923e8237ceece	1	0	\\x000000010000000000800003c70cd683dac4a667c3700b9581bc09f33908d2c024ea8ca9b51f8fc5b5d59c8278b9efa26c71d26b475cec5b4a53e8ef2b6a7a9110233d2d18224083b3bee0de3d8d13aa04640b2af408f5303ea6c2a5f91d2ae9bd0716b9629f2e84114ca26d5fb5a2350bdde92abedf4593059b2226423d77c536e89b93c9c1e13aa2a04735010001	\\x81aee8ebbf7f2a77fe92a1dece4752ffb144f026fa61e4a8d395183dca23df5dc0b8d3624aa47ccea851e7f84b5f137872348bd1e8c26f4efc5765c9c77ef001	1661188319000000	1661793119000000	1724865119000000	1819473119000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
192	\\xbd15bbb2bc6ce60cae2e67430229d54ae0f84d081ea4102ee6fb160f5bc0b563419ee5817a15b296b1d9e18784562aac93a960e3c756b7a30a4c033b9bd4eb7f	1	0	\\x000000010000000000800003b7e6711f627ff04acd3bae2e600fc281faf25ded1f138d1bcf2da15ce8b0def8d902a8b1dfc31194f85d230a4536e64faffdf972f0b02c49a2e8fde15e540deae24e8f82cf7320af0f5a4bb522da9f5a475241f95988716af95437063a4758f866ffd41fcad387c0a75ec6f424d306b675e774524265808ad02ed034c478bd83010001	\\xee8f0259189dc4cab9c195b5e761d0c6c4024ccbce6f557a723112d43cfafe4a08febf16ed777fc84685600de727330cd464c13f35e94700cd9063618b4bc10a	1670255819000000	1670860619000000	1733932619000000	1828540619000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
193	\\xc03d9831f1bea35c30cf48d79716b13afc815ba1561e608763dcdeaba333deecd42f177bf52288c94198b3d137111d527614422c4881ac4f02234265be27c4a6	1	0	\\x000000010000000000800003d2f1c84ec5123e5a706b1a8c3af31abd444b642282d00c16b22834343ff01de175b0897e0f6ef684af099622900eb0533ecbef05af1aa261dec83a4d693b37c9e3ab4c42924517ac03ea6959b23d90be3edee29667b86c70a7a2eee445bb2ca12dd3e2f246c493fdb5cbbda3e71e814e3b086129688ee0b7727a733d9ca9e51d010001	\\x62c81973551baa1aa9a26b79f3239785ea6179e3d1a56ce342c8c5d41c368ebac7b73b5cc930a742ed7d9759e6409ac48668a704c6a8ba2160c22dfe9a860c05	1680532319000000	1681137119000000	1744209119000000	1838817119000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
194	\\xc61568db03eb5cb1b124d57e055bcfc8de46f57bcf0e3f7d6331024f7eee6ba541db38d4174482aa8a5894604eb9dc2031e8be8a59bb3feb3ebf0936da6f59a2	1	0	\\x000000010000000000800003d2d46244b8f78942fb184d508133feac8b846a79da1c3e6642606fdd8182c5549bbf72a66a9cc68b291e652854abac3e1eee70ebc83539aba24f25eec228bb01dfeefdcec8ade6319f6c6ccd1262bf7104d66158cd81e3b49ebf905c280d971b5d51d1efdd9b6d5004d52d59dc47b47f0bfdd2864e9ad19548eebe980cbf263f010001	\\x3e5b13f697e8618c66669c247f6e48ec2bc4863d8c9a18bf862026265ffbdf046069a331cc6e4de6d4ffa0728e9d8ab344dd7644459b455c7e57736cef745f07	1680532319000000	1681137119000000	1744209119000000	1838817119000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
195	\\xce0544e53c28980f98d490d24974a14482d909f1e97bde2177e50f1401f627954567f8f541cc9fbdd06a10885994471c7d130c43c3ac4cfb73bd091f8542800f	1	0	\\x000000010000000000800003bf7ea58b8097cba78e834f4b5b65b353c34bd9240b6201653cc6cdba22eed2eaae686b2145ad596a6cbbdb41aa03472543a5833f84c491ba012fb951310d4d459a0a55d33e0e751fe85178b4e3e45616880ed70d5a8aabdeb57f1c9791284d0ab3f2818f9a126a91ca0b31f4516b75bfb2fa03bb3aa04e5ae216012c4540878f010001	\\x85bf56572bf05191c47cbd44e28583e043d906a21ab458195dc4966e15a33cf8908081fcfc46383c4a6789e4d947ac0da9d97aba302e8cce8c7456cda478b40a	1676905319000000	1677510119000000	1740582119000000	1835190119000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
196	\\xcfb9dd04a7daec7ae16b45388de1693fa50e6a3875107a01630febc811f2bd595448f6fec9c6accbd0e9ab929e7cad5713579b2cfb943619d7765a766bb30d81	1	0	\\x000000010000000000800003b361cdf38f4bc21ba585281913ce7eef89bd4def25f37dc9d7f688463310419cfa399c61b280b8505dfbbb9a62ac23ecdc1a69b1e990ad2d35095fc6e4716cd27c093b7eb08a81ad48c8122ec0924a39cb77b23d99e2c466da05fa406bdf23ea7b32a0123c0cedad40cb7bccdf829e3b6f38171221f4a4fd8121d9194bfc7009010001	\\x09209888fae6b679bddb10aa56566848b9e86ff0d7b85a483cffbcba38ada112fef893ebd0644f7c9293c791ff10268ce99dbe49743a0f1695b57457f99a970f	1679927819000000	1680532619000000	1743604619000000	1838212619000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
197	\\xd125febc65bdce3b63834b1bbbc85bf8f65239345707d0c21dc4c0bdbb13f2001589acfd81cc6b0524a1e8a406713d890b87131ddc323dc7030b99fa0336bfa1	1	0	\\x000000010000000000800003a9872d2cb22b24704a00eea904fffdc7dc6b133039610b1d46be9c706b971b167e9e1dd7f93ce5f713c4544f6a17f98f7482f6542601cfdf6853aed1cf80b465d994cf063588c2c8639538d32d3e577d3902274e524798faa27c44a823446f7f78cc2817389f2570c3c44c364157f260c448b59a4ac2ec44c2470abcb8f3c7f1010001	\\x5ac8260d7a1f2f7ce0dec3ec9ed3291ca88416472e0a9ce1edf30495f3042333ab5ed66861cdc1fcea3bccb210909720d42bb67aff8b4be94bd97d3d56566f05	1667233319000000	1667838119000000	1730910119000000	1825518119000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
198	\\xd731cba4d1fa04c6d3150e8d0ef66fe29cba409e150857be3caf4f79aeb387f157e2e1bcf0a225df4701ce51793fc042b8acdaebcbd6865bba4d97dc1ce27536	1	0	\\x000000010000000000800003c1797183e7268f64e485d834531b6c63f99aa618bfaaa1b3df541fed4a1bf565c5e30570b19dba008656148ed723ee303c83683f94f7b00d5776233faec7b421b25dd63e73670be138ab4449cebcf9f14a439ecb62f9876404bbae9fff4249afa6af72d18340629eb36110e1ace60fc9ea09c59dd85d593921d68631e591b341010001	\\xad6f7df7c8e109daeaabc95540c9c03c09099f5ab0a69c9a88fccb47c459d1e0edb0ea8c0f88e9d7989d19b906dd7421ad91996061c507c25284b223aff3200e	1682950319000000	1683555119000000	1746627119000000	1841235119000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
199	\\xd7fd3958abdba79c7fdba8efbd92df3a297f867025e769e3675f063d41d48e1c5b7e9cb591fc299e00d1eb4aaffa921e1bd786ebbc0b12adc1ff6c6b5366dcd5	1	0	\\x000000010000000000800003b56fa835ecd8b783a9780ce6ce3ce0c3226ef21b8112105be02911d00bb5f67befd3be04c440fe11d466bb1804fc29fd5a1335c251e10c5e7a48bd2265d41ffcec062092d9d97cda9b25015c599a28ce64735af2004857ffe702d86fb7c31a660c1ce1bc5bb1a85f326b5509428fcd695ebbd2ed988fb65a4774c7e0ac190041010001	\\x659328b1842d00f9fc9d7e7ff3340fbf5cc18f13592b50c42e6e9f447823a6adfed58909eae7a23961dfd76d31401bffa71c8a7677c10e28861212b04fb15301	1651516319000000	1652121119000000	1715193119000000	1809801119000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
200	\\xe0f9bac9e7ff4cddd28ac18053266c7cfe51c73874519852d198b807056ce592e977084dfb07d2b719436935cd0cb2b477050be960eb1bf2151bb694a0fd2f9b	1	0	\\x000000010000000000800003babfc5c93df889d2a4fbaa8649d21bb9c13acf49ab82bc209212fe1c46ce04d83ca1fcc905cd50204babcebc31dd0c4bd3e5f9b0b1e1db16f1670fb7bb802a696d62d65af52537da018aeee5de2a268941dbed478028083556eb68124bc84c565af1db0c259af8d5c455786f9f26bea744f8dbd844833a3aa3aa7c1f6b6c413b010001	\\x65cded89dfdbd67ff8788eae017b66447d539713aa9636649e49f2dbf365fd66252fd5f3fd9cd53dd1d1e4619c8901e91744e3d36bd7400df448da967c4e8300	1676905319000000	1677510119000000	1740582119000000	1835190119000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
201	\\xe13d42a71cc52f8e19fbd2fa8678ca79988c6fab2451f2ef32d053a1c5333fb6d3c0127bceef89ac7d8c67602e74c0ae65012cbf429c47e8e659d1fc998a3191	1	0	\\x000000010000000000800003c20da1976145b8e4ae6601ca66be40598e2fb11faf678187a2937f2f328bc9a52f83be1acb157bd53f1b5a30928336a24d7f03bbbf534ad2f866082ca520f5e85301c6225a0b0697e908a36e7e562e9df733ce5d9a4015afcabcf1bb570083cf79fa7a545ac88003d6268b06ff23421402bb4b62b0cbd9c3605b339c169a0ff1010001	\\x6440aa7d09d1a89f66a722c9251740ff698d34f004e5364bc2f7dd7c7fa955727c135b1c9e152279b8a3b46eb056bc0630272eed836901d455640b2a9a048703	1658165819000000	1658770619000000	1721842619000000	1816450619000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
202	\\xe1fde6e754322a7043454e7bb7fd4142380af61b3a7c79f0f9802fcb3b937013ea709ffe67e1934cbe60c8c21ed71abe395d56f52eb3eb99c929a5056ab3bb8f	1	0	\\x000000010000000000800003c7310e1b06447a2d3b5b4480c92bbc372a9a775c196de2a437869b21f75b12439463dab6b9c58f182ff959dc56920de29c23c7765e31ac4821fd6f2202783f4705a8942af3d346b1bed1b4be5ce8cb9a15d450cdef605543389f0bc0ca63e459f2f4bb03cc0096aedeea7f0f4c8f9df8f22ebeb26d40d28f49bd5559d72649b9010001	\\x4e10c53ca601b56eb7fdb8b053d154d91823c0c9628686cd89cd3437ab545b0eaae75c913cc9078df964fc26744b6c8cabd96de67bc7242a4ee288a181e27708	1665419819000000	1666024619000000	1729096619000000	1823704619000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
203	\\xe215ed2eb93675684e52722ca0814ca19870412238ab8ca6f8a477350698df15f067b88df562793e9bf80dc6318282f16cd54aa8f92f09de4039f2bc5ab7f54b	1	0	\\x000000010000000000800003becf2677b8e161da59cd2cc665735c8b56d73f0bb93528db397b256b204afdf528abf526ca6c6d686d980fb8b118bd805afd1142a0417a8baa01509bc7f731b1d02620cc2cb4320b21e69d9773d04b992592eaf075a6654a0deded7b5f403d89ab6f0f7813ef445f4857e57acbf43fb3deeb40e4c4f1b825b62cadd7f624211b010001	\\xec11eecb2c547404831ff60b0e81a81a93dc9b5374fb338f016dfe45889dfb5f2b5de3b532a9de8eafa9a1c0d34cd1160dbe9a63911d03eda99e7dcbbcb94103	1671464819000000	1672069619000000	1735141619000000	1829749619000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
204	\\xe3191fe8b735b73fb76ba52d4a4b8342ba86c29f7309cb76501e113f52562acecb35e7e7c73af54e12d2adacb9ecd9a51db5b3556cae2a9e91efa4089424de78	1	0	\\x000000010000000000800003ca48647656b0205d661ceee62d7600c481c3ca8c335971d0a06e6d3647f1466881638a3d03c9d4fa75e9084925790b94359479b209ea04f757ca03bcd80db3e82d6c5c58e1900f3e47d60e0d9bebcda7ae433debe74e1e55b791fc0cf5e5ed67483cf6782fd095ca7f9fcf16c576e1020f255203b7e49c912395921d96af91f3010001	\\xc8ef4ed83ebcbc0e9ed015ebd604d02e5ad606fa4e761f8a3380665c6e10100f9a0df0d737e04555ef012e80e5be6250ae841e307d51c9ef3989ee27022b810f	1659374819000000	1659979619000000	1723051619000000	1817659619000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
205	\\xe4c5d99072eec7d68b555f7d9401dbdad53a7ca818fc525792590b0da71720de833c2c631a5f398fa68301f8f33b2629b9203741c3f5f0cb25bed12b77fcd6b9	1	0	\\x000000010000000000800003bdbbaa7e60e1535341e6e3d181ee2afd0e494893e7244604c5cb2df37c638730be8b52052b9034e2489e626f56381493c19f06e8fa8787ba6e7166056d17f16dde0ec76d5dc86b603f068e99d823599b74c133a79783d6a85fc5ac3ca93adaef0cb5129e292c455647d2f781d1ee8715453aa3228995e0c975f9880f34c60dd3010001	\\xa7ca14a3376238713665d4d14786ffed5e6672670a8f4b72ae59292df84a6446129b2c7534b1719f76abce72346d415b4928ca1dbfeb0418fc22c6abfaf94407	1655143319000000	1655748119000000	1718820119000000	1813428119000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
206	\\xe73950398742450009997dfcd9d2d853cb75a7e2b0801ba3b57be067101f432b5abcf7c8c74d0fc53099c8ee431b5b52b3dd72aa4228c265cadb4a5c692eace4	1	0	\\x000000010000000000800003ce04eceed09d3d0020f9665fde4922b6551a7507af2465026f7766e7ad9131ccdc3a64dcf4868566ea0d684e83268223c398ac8da8a3abc7518a8de6232c7d36afac90a3ace3f4d8de5d56308a77ddfb9d5efae8f3b826c58c486b528e57a8504039bba24dff912df4f7c65a3d38a68a7b881baad32357c793d06d8e0f1e03ef010001	\\xa4ba0a7691d10eafca8a357d3245fb37b7acd9e2cac09c1954ff789f92147d9e67c3660abc7676a1ded04e73afb7d4172c24ea1e187906b74e28bc66330eaa0f	1666024319000000	1666629119000000	1729701119000000	1824309119000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
207	\\xea954e351bff6086caa2d91c9cc819090221357d249d7ba007efa50dac8c32f09a7d6492d213295369fc268410dbe4e397452bfe5ab7b7bf1ca2dbd01b65ac24	1	0	\\x000000010000000000800003a59cca54b02c1cf344a2ee0e88ba4e07a39983393c96a944fdd8862d680d692f06c6d597cb1cd0f7f6e08f0c7454370cd21686b38c9755ddb0f07eb15e892b3ed2c94dd024023856a8a9e6f5f22241ddfd42121a98d915d6af665ee7de6172793219ed54ca5e9b99673bc5c736cffbfbd3505665763fcfec77ebaf91648b0905010001	\\xb9f584857462f5cb47bab143ef1d812a3a7d73dd4d0ff1f27c0e6f82fc1f13c265ef065ba8e8db2ba713104e02c0c8138b4a604c8ddf511fa89f2acfdf80a402	1661792819000000	1662397619000000	1725469619000000	1820077619000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
208	\\xed9d2b2b562525c058628195c147685b39560712572c8005cac62e1bfb209e9e7073312adeb1f30b95dff9ede228df8a6aa3393dbc0e14161fa874c93a7a9585	1	0	\\x000000010000000000800003b967adc67fffe5cba9e35ec18da6cc6bf530d884df62f7f1c0f1fad3af992bc2b58abcd0a254f2af4d0a500849c152a445f2ff59129fea4920777757ea80b7c51cfe44efaaea17f69ade1fe9d5dde2b1c0466db8a19f43058d3c9b7e4b021be7b61a397639b005629c2729b6a96fc347e0d021056def70ca960d1d561a00ed81010001	\\x226768ff459e77cdad4f9f5801ca66f27d3bdcc33e8d7ab2466442d3aafc4140c2c0c4da0419fb22783099545da444d58aeb8fa728cab118aefcf66073ab6a04	1655143319000000	1655748119000000	1718820119000000	1813428119000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
209	\\xefbd05f613fcdbbacd34e3d72b07175bed44c7ebf49888b7e2c997cecc226a64ef80713ac9a89da2903725b1afd5996fe2b852f6334a4a447f68cb51ea759471	1	0	\\x000000010000000000800003d4031cd7e6a05a0af3e12b30921500e7b68c1a34f67bd9790f9515464e09941cb13da189be24492ce904ca2a1e35b629d53b9d5c6634e2eb21df83ce9c1ee098a1e951e86b7cdbdb7817c97f93d1eaca79b307b6a58b7c3f14b6bc90b87cfd969c1190bd9f3712fd05b952e22599f99e451f683f28b9278a5be41c4cd5220791010001	\\xb8edff375d31407f83e12d7529942cba14f5f6c21e13f0f1a9ed59ee65887db52954954f7118cc5635aaf1d0f62bd39cb49abf9f639464bbf81085cda8282b08	1682950319000000	1683555119000000	1746627119000000	1841235119000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
210	\\xf035207663b9309bf3b46db2ab958deab63c8fdb49572b592d558a23f64bafc795d93ac436db61aff191b4416a4b57f426db8909e2ef28c44050f34a4aeb2b71	1	0	\\x000000010000000000800003bc5b013621d640b12bef1c55020fb9a792fd0f68fa0397b9c8ae6ce09627ff4a883e89d418dc66befc94b2d7e9b759a79c7cfa1f4f517ca25129c25a1f2099f6b62c5c41107b55f4ff0428cdcafafa21920de87c3e0a03235a288b55a1dd7c4e866c87f2ed3b5e195fea7cd679bc98751adabb16ccc5e6b9aaa3222e6b803007010001	\\xe2eacfe0cb2b426d86c2bd10899371b22f65feb2892d1c8d3e69698446ff4db48c8bc84ca10b8d7ec70158ee82ca866ec150122422933cd3e504518c29fe3703	1653934319000000	1654539119000000	1717611119000000	1812219119000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
211	\\xf5d1143139068b7a965ed9b3b9e2e49031a56596f5aa0ca2fc0695e55145e3a148a60a3e0824563bf1b1bea3fa4c183290431b696fbd544ca912f5ad96b77eb3	1	0	\\x0000000100000000008000039db3e496ef9261f9f5d36325088e49aacc33330a7cff165f50333baa99d78ec0bd55810138c4d4693e58066368bd425cbfbff7974d58b1111743654cccebe8c7033771db08ea2087b57dbb3499bd5324e959936ca7f1dd5efabcef4590d55d3ca692c65c1ea5a68ab7d7281ab8087965a79d6f4d80ff6b420beca7af33062021010001	\\x6b4d13b20701001a01f55f0527e3da9ca59681553b0047a549d88b19306533b1fd66adf6b4957c2a91c0014d61c826364e3c8f3bdd534c02dcd39e3985fc360f	1676905319000000	1677510119000000	1740582119000000	1835190119000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
212	\\xf5b5b945c80e0acf715fd8ede8248751189c56ab8573bf2c00cdf4b0de9cc63f58d832aef1f64eef789b7aee5db8932740e8cb6abfd1297da6615b145ee2026f	1	0	\\x000000010000000000800003b7ceed5950f649e79a57dd490cb1278e57b528dc42e8dd28781727e3c48fc050041edbf4a74b25a87a81971884713301e531973722cd38be520f97ce77e574449dd45159b917141a003758ebafe00fde496523c8eae21e6f188b420ed02233307eb5ef483a7afe7c0071c52721ec6173eb5651719b08ddb3e45908de5dbbc5d5010001	\\x1244b1b00030ad5a0e9ad9447b9d382c456047461823359ed7be18c4386487306c010d92e046e88cb9b0431782651bb202aa10466a93b3a97a0ec434729c2a0e	1672069319000000	1672674119000000	1735746119000000	1830354119000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
213	\\xf599e624c0587840946478127bddde568b6199f276a7a7287ca042f05440d47b000d85d4eec6fe63e787825af6b9ba8a4e8693aadfda56f3258f8b1f9224bc62	1	0	\\x000000010000000000800003d12f1edeb12409f5669646adba99439105a8653f6e1097e8f429df7a4b582e317d6288ae4d6a2e2d4df475ddf484a2e5f712951f8753e544169414247f3086d287fcdd47a0f29b55119d10b8dff0cd7fae9d6842575da9ec26512e40b935fe75ef08857102ff8648fd3fe14ad90471ad08fb323e7d19e65ff579195b699d64f3010001	\\xfeaa5a587424e762734589cd0675be447e3ed50d755d214dfd4e4bc71333df99238c6c1918a5a1e046dc2756c7034ec71e26ae204c8f2f4872e8b64d65319208	1658165819000000	1658770619000000	1721842619000000	1816450619000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
214	\\xf8f5fbba65707da47025496d78cb8290ad6177cedcf428b5041b77de469272a2a15dcab7c5cb3166a9e83eca4ad3d20d1ed96857dd41de4ef39bedb7d7bbe156	1	0	\\x000000010000000000800003e8d336638b0460af03d9146f473e0aaa3fc3aefc093d038edf5aef4d15818acebeb5484b2da11125cc0a369a3e48c58e69983373221046ebe650451911edc7c7c727bbadb67087f50b73360d333ba86fda5ec6f278d8d093c1a6f366ed8602bfa1cdd2d992b15367e8202d363941f898f8aabde058ed6cc9ea6284dc51f8419f010001	\\xb6f279e464bd17fb59dce7e06395ae515c99b6a306afd124232445d5dec43e6d6e9310012896d2bd568a984f6c02a6c5d2a5e8f6bff2832703875d39748b190b	1665419819000000	1666024619000000	1729096619000000	1823704619000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
215	\\xf959f8e623e08d890b3b76ba2cd1086e2d48bb99c947a0a8760c76faf6adf1edddbe483461c30fa489ee0455c134332c260061f24d76d52d3cf8299f8d5dd2e4	1	0	\\x000000010000000000800003c0bb1a0b294f8b429974c4dd6a5a56cdc0cbb55e15fc593b2551136c400e329d71f6cd50c97150a3c1278056bf7953423ae258dbf44c075649c0d6532edc3ecfd95af9a3cb33f78700cc7de3623781f1a62d8701529e11b865e6c53903cdf04c434e0dc49c256de908c41ef15aa9359f22d6932cf6ba7ea99ebbcc0f006bf811010001	\\x02c33d7bbca101c37673b10bd8aacb3ca74a922d8664709b6c800fd977b5907d6d317846885a7e531a985fa6589d4b07c9969f82a68c8e341ca151667378210e	1679323319000000	1679928119000000	1743000119000000	1837608119000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
216	\\x009e167b68aec7e238496ae949f97c8152dba4b0e50d0c8ee254b160a65daa89294c891a0e81456308734257cd1bfaac9b3105065b791853c30fc517b39f5432	1	0	\\x000000010000000000800003a26c12449211510519dac29f61fe7fda8b709f8b3494a2f52ba0d476fe7c0c2fe6b7def736792213df22014d04eef18fe3abf3ec0961d822d81801439c7dca0b8e2e6a475f1aeab1c595600610a467736cd7fa5710c4823678d849d98da70eab7fd1ecb554e0ddff0c4026d1af0e835b5140b3a4c8ac33ac880b3393e62fc259010001	\\x863d713b752f9c20493a50ea635b6e4ff920cbd3a7463f5f80e1b1742ca9d0b1f4b540838911032306af0e748d3aa66f0abdee3c6a6c52e6bcf6d73be9ba910a	1659374819000000	1659979619000000	1723051619000000	1817659619000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
217	\\x04d64ae80a8b09f9c742a5b13134b901ea5241a83c80b238871244a7bc182d0ef689df80227d69ae9eebf5ec0fc79e511912d9bb94e7eac897492e7ce19e1413	1	0	\\x0000000100000000008000039d3622bca177e230826c82086d0bd8d27d5be8267aead9aea4b8abf93e3f77265cd4490ac83f7bcf9751b1069b941c6e1591d0b0d4c1363ac602323eea9580683ad9c90fadb3abce9432af6d6b2997e673d1909a11b191869ec0959f8c3f2928cd9435d03979d154aa74e22b59569229b2c85a5a4e150043452b708cb5240439010001	\\xe11b82792592b16163829a4bdad772cc8c720151a66436a0a818e8f4d02f9b5484ac9a02ff3d2ec4ac00c4fe7cd7fd98c241dbb5a64ceb38f746c4b81b90700c	1652725319000000	1653330119000000	1716402119000000	1811010119000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
218	\\x04c64f58090155d46a95329e7ac173252f830227bbd7c0a41d33eedf8fe52dbfb4e6da56d872a4bde455740e5e27c2305cf88cf249bff73af70db5e2d60695d7	1	0	\\x000000010000000000800003cab2f6310c7a6286de548356b64fd3403b2634eda7fcae8ca575964db5ef7329ea0af41c4dcaf4147e15153e25dea64bcf3794ed6d4622f713a77817e13081a410afa877b3ef43b2257a67756a14f74ce9ceddac3163e884939c015318fd00dea5728b66851e694589d2aebde8fe9b11bd7f6dec7cf2f19427199577d77b5d49010001	\\x7180ef19c5621c18a9cee9fdf68e52fdf41f09039532e4ba9a866f7f39aac1c8e282327c41f8b0b99cd0c9cf17ff1d56da13a41e7afb42a0265f38f59e7dbf0f	1653329819000000	1653934619000000	1717006619000000	1811614619000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
219	\\x0ae283f96952176dd8d5e8d525912cca2f011a7def9059131fae8f566cfe7ed2439a448dcccacf393bf915beddb89b8c0e47afe5854f2250693cc15ba324fd53	1	0	\\x000000010000000000800003d7d8a34030304eb29ef48f768b7aa5c5792921aa1fb2bc79e4a6b707c168f4d51fdd853c25fc3ae146f48883e11f2a12fc8291b34f610183790ae02e58a292c66b1c3ca82029f7107b93196830c2cb8001c42b223fe1f0cea37bb06bec4a2a1bdd29ace672c234dd351f083ed8885decf39863f22fa2e943f3b6119462f10afb010001	\\xfe03f9cf13d439a4c5f3c207ac944ea34751e13a9deae63a6a30b4dad91c9f40d6f441332b8a50f7d766943dc98c01f21af804445fcb509d12af62f30d275a03	1676300819000000	1676905619000000	1739977619000000	1834585619000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
220	\\x0ade18f42352e60df21a991ebede4c7bf0cf8fd1c35c3a4cf47f38c3724be08e63397aeb64e02edd9677fe2cfb64db6fadcf3935efbe796c62e1d97f1238ab8c	1	0	\\x000000010000000000800003a59b2414e47bc8cdf0f52859b28aaf6efa532fa9dc6493db0212df146570d6cfef278c9bfc1d98fb8ab4b85304fd51c38fffda4e4d4a8eb25773488521861c395d9c529be065718c44d8d28f3f207bab6e4cf81f172c6ae274cd9d1533393e9861f8bc6e0fe10795218e3c7791683d564eea2bdd7c972318c6d58eb155ff035d010001	\\x76fd062ee7adc4c0aea56a19a03e5ffe2a5f049537fb3a31720102a56441037c331d5bf18a8e1e792d2718fe92478bfdc69ef22049bbed884f861abd5c8c3f0b	1661792819000000	1662397619000000	1725469619000000	1820077619000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
221	\\x107a8f670f2c3b4048a0549c8b9134ff14592bacb690d1a53f6bf592460e85122ffe5624b252ab32f2d9301a2ec61e81ce3cf5624564f3023556292c6897228f	1	0	\\x0000000100000000008000039e4ee697ffa63d4190e665e76b82b07982f3a9795f277721c3f29d3ce1d22cd4e284f858054edb723638cc4412ba3ec70f0cce559de84a851fb96be7fff3a475ff636da4bc0d9e1cae47ee9ef5bde49d1d7d627d54d4ec0ef5a3e1e5a3650dcdc8f431b0594cb0d9f1d3087cb14da0fc37cc8bb0472a079ecbfeb7e578eb6b13010001	\\xadea9476a1a06da1664418d1b975dff43edd6e0aab4ebfe511f0071622b3e6e656000332145ae5e0657e1f2821e7cc18a51f41a820a954c04ff5449ff5956103	1682950319000000	1683555119000000	1746627119000000	1841235119000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
222	\\x10ea9bc5f858013812a469efc021971f1a691413ad374eb8252014ea5abc27e41b77efbd3b3e1398bbf4ccb621a80ec307d6e5ab574c1bf903aa2b286a77b368	1	0	\\x000000010000000000800003a7362633f39dfe41460a1dc9e6b63c4f16e66d04276f300c906a1c5bf2c20e4881c3154ded156149f74b68886a43c879e039669bcecdd91b84b9492f7f87561dcc74be198e5481b1e117e1ed9ca2ab421f90c1c874aa40bd570513a8a6c6d907926c1b9f61dda70ee60f441fd60f1544f869a2cbb872179c076b9a0618fa67ab010001	\\xa38287638badfced0c7e91ff088b27c0294700d89c0adc5b51404ee98189273fbe25784e16c1b5c5a4cfd5d86b83a1fd316a3b635519b1788270545252137c0d	1674487319000000	1675092119000000	1738164119000000	1832772119000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
223	\\x134efcf758510c0b2e93d9a57b4aa4b1bd3c96ca058dcb3ed2bf13f36ea0b346b0c9f07151d277961e91b69500a3fcd14e5a150e3a7cd57556fe743b5e57b312	1	0	\\x000000010000000000800003bbe891c39c312a62979d2fa3df42fd55537cbefd635f11f1dd1007c806f1c046b6d557385dcfbc214a9fbc8ccf13193ff5a9130a4b4f75bcd63518698adecc1a54039b05dfe0cc04ebaa5c3c1e89c3af6e7c3fe9dd175fce8915cbb61c91b75f9760bd60ee686aaf2485d9769d654009c863e51ff245c39fceeee6feb4fa20d3010001	\\xff25b2c167c88493936b0e4a27d4fafe48963c60d856d05e863b020f1d44f9c3002cb4fabe0fddc4d33aeb7d00364a6068b1266e8c72e61b97ec2fb23016290b	1666024319000000	1666629119000000	1729701119000000	1824309119000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
224	\\x141a888e13866ebf05fa8b1b62bf3c3fcdd2dd3ab027477daea17c3ab2793cc6b262026247d4caaea9ab6dfacd3081e1c51ee45956e720858ad93d910bf28837	1	0	\\x000000010000000000800003b10d8f6809d9ffb5befad6d0e1f687a607f81d9c292031b93884942c636a7f0f51d48edd55d14b982cc2e417a9b9b9977381a225fe53130df42ed546f56a34983fcf69177b5b2b8dfab95714b8a533c642f4bae37223d88408b1726154c5534ef1e282d88f50db3f4ec5b6bb323f51a3b8dc30116ef87d018ec23b8d6e80cb0b010001	\\x536b4c5e638d7a69f7cb924e38e360df2c968c11992b06896dc258091f4edf196cae3ce7de88449adc5c68352c463523becdd0dbf3f6132aa60c198e796a320a	1664815319000000	1665420119000000	1728492119000000	1823100119000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
225	\\x15f21c1e175b0bc83017fd0904e400f8522f0fba81cc5c2be16f3fff50052209813a9af9b697fd7e1b8b92e7fc5f1679ac94f1e4cf15ee3e8b8161efaff3724c	1	0	\\x000000010000000000800003bbc159484a0adcfb248ee3a60cb85e470cc7ab391e64790f1edb9b07c185074ea54f6f2389f6c20a45d30ff91b96f2d14eee1299d687995c17b474ad84c980417d04b4a4052bbc8a5545b19ccfc7cf41e457e9134119c75adb167067b77a53a711a0324721f8deb8e2ddcf837c8907acef1324e64710cbef9e5a4c25aea28065010001	\\x3d7279b2060919bf606e8832d8c1141e63b300b1e6a8e83a85f9e8503016180fb3376e473f863c69032669630c84b2fb38d6863c15ec5b47af292f477b31060c	1677509819000000	1678114619000000	1741186619000000	1835794619000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
226	\\x155e92d7a10cb0bf5fde86d3c27a4b38b735c798dc5a20035c5784a22449b1e0a25415afd3577ec6d392d5111e1d3e445cf579fb5a604bccb9a38dbde7cc3311	1	0	\\x000000010000000000800003bba3e920b3ef168108b9bc447ea6cadeddeb54a34d44cc81f25958365aabd51f7ec8a4a19e9c559498ea4634a3599432bc11f232a2c9c7081c309b26ebe306cc2a394bc1b9970c190bd0e4f7cf544acccd38d2b491983d29bbcfb2c814dfe6e24357115f6129f9f70cf13b5e38f65dfa549bd19b2dc51cbb4de9be56e51d8153010001	\\x8c880f4b8e0708976622f4f541a71b4f953aa33d1dea43ef197a20281eb0b378aced6a4b8894c2c2d406ddb7ceb0941073518540ba6374bfd59b14acae172e04	1676905319000000	1677510119000000	1740582119000000	1835190119000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
227	\\x178ac1f118d41775fe9fe5573211e045b828df282900b1f9dafb551f9bf533a86e89139ecd5019f1996c4d2b199c074e9d616d812070d9eed2e2fbb86c39b065	1	0	\\x000000010000000000800003ad03e4aff43bfc77ca97e8850d89db2f7cf38162d8fb2d615258bb1fc0ff9bbea5a91704e3f0bcaa096dd53c98db1f60e1e18b6ff30c61df358915f24b2a9e91852a81fd5f92996b9e213367d793021c4c156198327f0dd57b3af9327cb4892add5214936f8249907a839b9deda6c5a97cf56eb85b8295e6a8f4d35f404f5763010001	\\xaae68e85ca8b25b7cc852b70b9ca0bf39799fe7a1be9c8fb7c3274ca0a9ded3b8cf40f210a05264a3c68dadf2a148811456158688520cac68a1287c38bd90901	1666628819000000	1667233619000000	1730305619000000	1824913619000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
228	\\x1bcea27d8050746821a92bb6ecd388c32ff9bc35ae72396ddb6e9bc82226476f7917fd4428fc744aadd9542e939ecb324738765b3f148c7c80149eff8f8ce86a	1	0	\\x000000010000000000800003d32d8fc55cdeb96e4c557b098cd7e0b84fc7a944082d2943dd8301ef2f7dccf358a6f6666415cdd88b2459b3ce665746e7ec4ad59565c89952e44015805ba72b0f616b6fc660d71c3d1495963bb7514c1f12902b41bb704111eb66a5226ceb1a0cf0bdfac6aaf800252b80e7dbde9adb9c38855f9e2536ee68b9a58cc79509d7010001	\\xd4af6c1c01d4f19f8b7536c7802bb550f7e1a1415fe21ed515492ebd13952a7b19a464bfd888b5787dcfcf9d1021fecdda386ee438e473d0afbca86e7fff740b	1673278319000000	1673883119000000	1736955119000000	1831563119000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
229	\\x205244ab5283cb5315f6d50e04f8a58961438f721170bf44d1dd52282c9242a4886794be7493f148cc7975fe376ee01a89d2bfc9e7725ec1ba95f2c2fa682799	1	0	\\x000000010000000000800003ba69189b246d648b2903dfd1f61638721faf0b6e91a26b9a754208ca95176d455f888fdee8f7365e70e044373e0fecb397f1c12d2ffe7e5200193f7c7a07c37e469d973a7960304b82e8cc1a9436ae3ffee969ca51303db135ec1df798f234046460669518ef80e70365b9e5a490137c3d4c7871918b06cb1bd8fcd43b7a2945010001	\\x1345ffa45b58b42229dff9c2c32bbe191fdf5d9d12d595a4abc7864625f6446042b6324955a33e756ee2195802f0c474078dbf653882a50475b3f12614b8740a	1670860319000000	1671465119000000	1734537119000000	1829145119000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
230	\\x204264964cabf6b1ea00b79f2a9803e38fc1e1cfc8464d9904eced06830eb12a70afd9de64b80e6f6c9e70fd6d18f2b6e4b024e23fcea98dfb5deb3514108e7f	1	0	\\x000000010000000000800003969961bf8f7185b522d0f11f11e537696e9adb99b92cfe0446c0f982c8e1030675c1cabdf765e0321cb5355274777dc1b3efe5f1af19d5317e036cb88e5b78607fe065810278d21814ae5afa500539c78dbb1018a596c08b265d08057fc067271dfe5f649a654cfc58a55ae3b06403ecab31f53b93e04d577947b4919909a09d010001	\\xd47187736b2ccf4a2c6a59dfed3f178dcd5b3513b28cfa7059d534f18bf017b5e7ff92d19347be2cce0c4b058947edc85db75bc2b662518900f7b6c79c2a3708	1652120819000000	1652725619000000	1715797619000000	1810405619000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
231	\\x23825e6ecb4d715fbcbda1dbdcde6a8a2c8346de638e9b51818cda6b8d1cd89163a14a5c6d3c3637fd0f4043ed7746e059818edf5276df61f4563a643db3372e	1	0	\\x000000010000000000800003a729d3aebb9ce37fde0ea3d5349fe1660c8a805ff269206354657e4556ec276da22613cafb9ec33cb07232a4891c94f7f493d4ee3662ab04a7a4678a1cc9c8f3fdbebb46e5e24eddc322eb15fda034af1592b437d47b63431d7477c28db5d855ef5a0f142804abe54340a5ae544b5a313171b643c6f7ae8dbc9a0299aeb5eaa9010001	\\xa46bf5b9073ae04e7f7696089a41263849b847ea0270e63defe7da85597643c416ef5f746ee89c0777897eedcbd52a81bb6248f5aa5cb683e1fccf1da49c4800	1675091819000000	1675696619000000	1738768619000000	1833376619000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
232	\\x231ae90f595f230cb47d9c7d7c7b3ac9430b04699b093e3caa4a2f4eeef2f6bdf1028dfdb7fed42e74e3ec0772062185d32bee69b109c2064b11658a6a5da98d	1	0	\\x000000010000000000800003c2b9ca9147ed689e15ff924697e18e324e9b558ee82f879a19c86852419ff2f8785fb1636029722609df31844e3ea21d24d7f54456e70b4234bdb0d12ccd051c39d0967c1b3c4ce0a31dad7639a949ee81c8407598f5b9a6b39cdd2d8c9972158627b2d027f8d9999f43fa7efa5860e039bca88fc645d59014294a0b8875b5e9010001	\\x9f2bab17b06afdd5fda38c5e93d74270fdb3653496c7a515e9b61dabafe05394616f8d0a76d2399e683b992c11b9eac4e75dcc229b6b9e574059118c0dfbc607	1653329819000000	1653934619000000	1717006619000000	1811614619000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
233	\\x23d2ad2abd7132492a36126ea26d1ade85aa7c32cc2c0e3a8208d136225ac8b3632c80627754257cfd6cb97e0ab84e8f50f3260a01ca5c8b3509db102914aa35	1	0	\\x000000010000000000800003bb43cd7fb0216b5a447b1650e076572108142a8324ef813b7f996ad109f3b1410ffbda9e8abe96328358790fa7eb3ab80297a84e72f9ee2c3fa1c32e5ac4e1f845b4bd58f825eeb9aab61405332fba6f6061805948cb8697ad2f8d5470f1fa400b90f358eb2484fbf347284c481182a28f5a08f690b41922eabfc7b7b10f83ff010001	\\x26aaf3a9b173c4ab5bed54f23a813c61c16901a60192134a1c301990c0395e8437e9f4b2bf2d7abe8d934814001b20d2715d02f4689caba2f2423148d5a8400a	1655747819000000	1656352619000000	1719424619000000	1814032619000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
234	\\x240e1cd692eef9e015dd576be6ed782d5b959d7bfd424a23455e7d41469b21d88afcd81209d76f320cc584a19a904a843fdb58f09e011db65291bd626608376e	1	0	\\x000000010000000000800003bf3f2407207bb2404d01d7a10cb875ce84e3ce9db528ded96f03d10d63c1b09f9664e1b98c4c040dcc5b93f5199c3eb6364d2363c10f3558da25ec2d35ac42e632161ea9fd94bfc238f21a8b46bbb4d4ea7398762a7f182561d17502c92bc9ecce0932dbb8fc000f4821737020545c269aa698b06372ca84b0077810235cc2e7010001	\\x71bb4374ecb797627f3208f29fa900fb71933d5f368ec8655cef0e4052a0f4dd9152a888ab1b26a3f2805a09cae7b889fd41e7abc15265fbe505f6bb88263d00	1659979319000000	1660584119000000	1723656119000000	1818264119000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
235	\\x24dad0e52af77f9a560c06f329a2e8a2adcf022b833b1bd211d295206b8caa7de46b8d0a94be907c76e705363956671b41a74be147b785155e25a11637e7bca1	1	0	\\x00000001000000000080000396f733b4faa53f1f4edc5754d02ee4ab3571c383106c045065499cb3c8f16d26083a8386fcb530d6e16d89d80a3196d19e7e2d9b68e8d803d5ef9e2d905df15c17069c7e23f624401f8eac203f9cae33530ee6dc0d20bdefcac80f53bfa6893cf5e40e471ca5d4b75e287caf5ea84c835c39bb6e2e283fe6bc5483aa5ed27787010001	\\x2826f98d95a26b36254cc35f5bfd20eb32dc34fb2cbfb93ad326e3c067dad11e67890d8a94afb5e5ec12810603d17648a61e82768b7b1d851219da9598fd5b0d	1651516319000000	1652121119000000	1715193119000000	1809801119000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
236	\\x2936e49ec1bd1ae4dc342391cf132d7cefa95bdac9caecbc9ec45b13b74b4701117f237a69faf06142f5365be6d00bef3171bed93c0bb237ac6aa480a7ae0533	1	0	\\x000000010000000000800003ea76691a4163016e501c1aa89e24cfbef571a31a74ce8a95508a02081d3f58477c1b1229a820fa1f51fbf96ac126c14860d772760721e9d2a0cc3ee782209e0367db29174cb1c6f483fd1ade51b9499ac3a759400926bbb71407c87134f8bc1eb077920b7e98de9e828377bee142abf41e421e9c67256552092646936ca09f5f010001	\\xe8f8ead305a8d61258dfee4149e0499f82e9d6bc9e841f1e905d6a72ce438440ba59863dd806fb3cff59a384ed7af4707ad6f63908d2cd3cb0db5921e0936608	1654538819000000	1655143619000000	1718215619000000	1812823619000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
237	\\x2bf25c6bf3f4db3a54218f5f71f3397f709842ff2250ad2e69ca92faf5191e392cf86730cd198bcb8e52446091da6293da4a5c2c14de45f2168265e7d4fbd263	1	0	\\x000000010000000000800003c39e3b6be3598806e1697a792a82f0e513b9ad03d402d10231028b5e5d4a0dfe425a7f6fe7e5387d9a28ced872a66adb1892a94038dfd4a9f747bbd4fb99f5099ecc19ea63f435f9e801f85e7abff0108703a2a4c4d7ef4be59caa283ea9c673604fe218eef76a4102cfc380959082ba3409b47b43fa1eb5371e5adb7da8675b010001	\\xb53b7533acd1b4d85965e6d0c85ed8c48b5852917882643f38ca4fc1c24f442c8a44886681b3be8a7acf8bfacf5a97ffe08107a229af9162ed7e7054a17b3000	1659979319000000	1660584119000000	1723656119000000	1818264119000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
238	\\x37a2d6b24b98f895a354645aa514d06810b6285079524bde029f997e264a61d74bc7c8de36df83a28462b81a608a75e3199f5dba37c215e15c656251652ac09e	1	0	\\x000000010000000000800003c070ca9fa59f1005f1acf4e1f43c6a7b28414c320758a53a2016720e47dbc67cb8a02d300e9304f594671c863eb9e42a2479163c88d0896c014ace1df9fe6d90ab7807646f5e6b0e004e01b44209a7fceb7e31b9abb34cd6e12b68f3a1b14999aecf0c17e4bbb11f0e1812fd5f2a79b35c7de61c41b837cbce5c71d224a2a4a1010001	\\xadd9dc5b2c5a88b30edb9c7b0301a596df77241c01678e9e1880b63883b24e4cc8a6fed817b90a414b46cc91ac9b4b9f04f14fe9bb38dcb9674f4d6edc7e3302	1673278319000000	1673883119000000	1736955119000000	1831563119000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
239	\\x393215cbb6d6609d4c8631edfa3d109300848dd5f93b93517fbd78e6fc4812f7719aa731fe14427ccccaa81b511f28f1a1037862f0a59e22042fd266abdfca15	1	0	\\x000000010000000000800003cbb22b8bac427580cc111ed2056bac62bba6ae03ad0e5cbe58a61b2ba759e07541d4fe6eff43a98f0ad23e94629a66717e9ad6f0adf06dd95554fc01c1218b32cee5bc34511657565dd80030ad6c4657049903a2d52f2e8af14793a670a0bba47b6efbdd5195117dd85867e5bb96191fa661b7865a958fb545fb52d26121634b010001	\\x9408346821f3800151e8b8ad839affaaca5fb830f5839baed0e26b2b3e220552c63cd5fad63c5c4e9d278974cb765cfc77592b9e0392b93be02f145c561d0406	1670860319000000	1671465119000000	1734537119000000	1829145119000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
240	\\x3b4ab033e24a655e9e76d8e6d1ce23e195cc999731cce0d0ae26edf66c9ff0e31fbe709e3ecec875d6ff0d3be55de86f08e0c2243250689e876959f3b487a099	1	0	\\x000000010000000000800003ce2ba49cbfabeeb2c8d870919f6173a353fbd39201fbf2338ca1ecdb3bd18620684c150f2ae19d55d6461559e6e69d1d38d24a7de7d2ae8fff4ede937213c9bb495a41c8c922c20cf69eef2cd93f3a1176310870bd5e89fa49e129375e12e899b8ce83da69e92c25c1d223c8321a5c3b78635bf6161426f48053aeaf89930ec9010001	\\xc70dd337929d9f061f607944bc064e02965dec081d9b6f4ee72a8dc5802add98487302c5b55f76699ffba7726a94f581608a56f0806018356dea99bb33d66303	1668442319000000	1669047119000000	1732119119000000	1826727119000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
241	\\x3beeb27c3412730f11bc007c2ce796feb611e51f3c0d175a643e6d0bce2f3c182bafd09f83db3743a3b459b073e9d4b76277bf9c23973748001783b95d9b5ed1	1	0	\\x000000010000000000800003b6ace8045de4e7b138700e83de966761942473e31cb1a222408482ed0b7c5fc5d5369f2ee0d610fd8be74926282538e95f268b1b328b3f8cbae17647558bcf00fc36ffc590b259c3a889c133df0f753953adc001c53f42aa9e719c042e14671d4c343150cb47786cf71b181fbf9baf2f20da55af093571a9139e1b29e570b0d3010001	\\xb80105d272abb51689bd29514ffa75b3db128a5d6fdae80aa3be10a3fd1fbda10651dfdcf95e62ea0e34e8ea13dbde657323502b20da7843b8d4623ef870a501	1671464819000000	1672069619000000	1735141619000000	1829749619000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
242	\\x40fe018cab8a56b83f58d793de109d16dcb77c7749c5fce3aad90b3e4e2a604984ceec4e7e6a3198139c5b462c9a8c2d7a3cfe3e7d6e9fc66104222d49e3dc02	1	0	\\x000000010000000000800003be14aa28542c84edfe07b7a7cae40c37aaf97224a27612f6161440174366e66f9895959f2b0c126eb4307de0101d0373a29d0e2363324b901f31951b76234427b8ca3f4a35250779ab02f6bd303b64cc29859a7c975c8c640eea923ff1c1e710e96ab6e5ed95c942c4ddeab59023d703b3c79ba2aa49f089f220c3fb17692d6d010001	\\x93bbae45d1c8e6e08eaf119a220b82b49ad50442ed51b9f2baea33f35617eb4f2f78b5cb9a39f51ab296d192c550ea1c1ddbafe30bc548d895016687715a640f	1664210819000000	1664815619000000	1727887619000000	1822495619000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
243	\\x41a246d4e73ae6225a93835b0e0e29993b2791b4a4db3b8030f20bc7ca235e0a941a70143fdbe1c1ec34851e75caba774738ba96bdc96dbfe2f183d5b194ef98	1	0	\\x000000010000000000800003e021d6b86959f9d19b6504b102f164b44c5d847c2250e71921e39bedf4518ad9060074b271c3153dcd26cc3c8356bad7c4a70172aa9174e2e529f778e13c89864c5ef7a3448c7988f5e17a539c786b9b8b67ca860e0914f617eec60e6510205ff08e373c80c42641b201479825f8f469f0a2d2ed5476b6d9aa2536c1dc7fcdb1010001	\\x7a7b433d9c2d72b66c8b23798b7d1e2fa0f4af705b99196d0256dfac24c393c10196fb924b85bbbd8672e3cc0d2c5a776c9be11b1604295dfb2d69cf1a8c9602	1656956819000000	1657561619000000	1720633619000000	1815241619000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
244	\\x4292604efb8df5dea70d13e5688ccdad63a0c5cb5703c7ee909af1054d3ede2b53eb89dc28e3f992c2206d4a5365384bd244016a273119856108bc3247c4b8d7	1	0	\\x000000010000000000800003a84277e2a2ab6d0eb57315e6aa07972db4dafb9a69940188edce6c83ea6799f2f438478ba216ab14f6569b6d032ab54fa1865a4bde39de40bf682b7b63a3aedc2e9e57f8580bfb9c1314d4c3bd484945a1184c4a9caa4ba68829e7482af28f6f6d3bf6bbafb5a1c1c7ad415a6d81ffab973b5e13cf9a28654a42428659ac22a1010001	\\x258766afda40805328b4c8fd80b5e3460fdcc84301c1be5c5d91f2cca5e59d36f77addf1cb5f9d1e38defc4df92f0d17824feea7c3e09e24aeb3eeb1c06a570f	1676300819000000	1676905619000000	1739977619000000	1834585619000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
245	\\x45ae1451c27181d11785058df6ecce9a03684c8834135a8ea0155a3172676c573abeffdc6caa688c6bacadfc907bc3ffc7d55780fb1cbf36c12ca26533113990	1	0	\\x000000010000000000800003ba92b96df06fe6aeecbfa0127996f301f98fbf6cb7cc68b4532440ac55fbfc0836712c27bd3edcd5d4356d9ff92f772d5e63054599908541657a1e267c78aadcbe985480bf32678169aedab32a2284be3153c5ed6da048b667243d8394b2fac9ed5545fd88682eb47268dede32308bf618c47aa2e88a68e35f164aa046720e49010001	\\xbe707964801f9b0cbfd3c61f0babb9bc36f2e27636080a9e309bd50b0cc8f6e2d50bd430f870f1096ce424a08b88b09f84da44ef80c6fe465c5f0e4c7d218f06	1663001819000000	1663606619000000	1726678619000000	1821286619000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
246	\\x494a13ec5ab03a057833820e453441acf91bf9525717311680892df42e20246e26af62d25237cf02d35b6647207877c6b72aedd74fe912f1202c3f3fa39dc2f7	1	0	\\x000000010000000000800003d90a028bf2b7c4b1363878249af8277ceae6dc3a0890e5bc6e6e95eaa315bc711c8e92619467b3b1823008424ec1e33c69fe4332fab32e6b50e99782b98eeeed45664cbc7ca38d8d12315c8960a370fe42966c40b29bbaa437610c8772e44d8ff1797b7441404c58344110c8374400d73b2885b80083a10ebd319f4dd8be45e7010001	\\x899f51c5f7508043640b95a7c4057b013c2d5a25d9d0ee69c77f34c13110069bf384f4ddf365ddea55cdd24935e6cf6d9c00af4bf81754345537d06c9094f40d	1669046819000000	1669651619000000	1732723619000000	1827331619000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
247	\\x4d76e74d28fd61814fe29a0ff619964950b91e96b015034f4a2cffad4d4b33937bef6e9b59f3e166d43f45fa2c4eaf6c0c7cd8580504058237227e526fc72ee0	1	0	\\x000000010000000000800003dbcecde2d31f8448fd64949137154af0378887ca44a852b06695832a5900e5e64425f129ec36a16b4888336691a7a36d9df478fa6f5257f92452ad1761e8bd033b7981ceb0fbb3ed3135a6ca62adb7e348b2f12250d58f7d7504e071a25410bf60a9f870d90722bfaab456fbff8990e01ee4fa408cac04f3d37a1381d06e8a27010001	\\xfefde5e3a501ac1df83184324e5213d42c4b4f5118e6ba32d0353beddf8d41bf0b73e31424c19c591ffcd3bc9951dc056c2d8cd81232fea9ca09ff6bf926d20e	1672673819000000	1673278619000000	1736350619000000	1830958619000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
248	\\x4eae39b413d2b90ea2dc35f06a0bf17708e2f323c67a0077a28a4272cd25c72c9f39ef5152576e64ab249ca9158eee060d36f1d9abcfc030eb106d2fe94ba9b5	1	0	\\x000000010000000000800003afb0bd35964e4b9400742c903a379e64c4c78dd9d9e0bd16a5cf7f48893dc513042353fb6f096d11fffe7473795217d165de5026ad8abc1a8610d26ca2875a86a52b4df55cecd6b5195793fa25d1c982d0ea7a2c7b2a46f79599e5590bada30efa14bae3f5d473f09aca38be110e2f49166c64d224f83f69a12a567e81970d61010001	\\xc1565e30f3ca381b789c04c49c1c30072a97428088f32f3d5ed91ebb5543e00cbdab66830d3f52ede9a8b77809ba137c37fb86e92ab563a802b6a4e01e32e80f	1681136819000000	1681741619000000	1744813619000000	1839421619000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
249	\\x50f2810f058fa63735853f897f691d06556cdb862ffbc0491be54377e964f2832f455f69773b7a986b18388a0e18e7b8369f5aeb40e89b1ec11251188baf1a5d	1	0	\\x000000010000000000800003e56b3c153b1e757d15a81a4e22bc203549ccee1e19aa21c8df6a2c10664922558776d1cb76e2bc079b7a8a366def9e42b35ab7c7ad8d2697cc86dd2d98ab2591b7cd8c4c8d691c614e3834d8c4f844ca2fed90c3be97224419b5fda00f7d9c8b7a43b57e0c845278ca72fae964f363702de6ed32d4e2d3aa3645e2640549dee5010001	\\x76d680f4f6c7d8d78dee168a1ecc1a9d3114e17062b22f22bfa28e801735fb92e7614b59e48f78f3da853d07c0ab7226ee2d0a03a530c1672b7d49c2f55bad02	1673882819000000	1674487619000000	1737559619000000	1832167619000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
250	\\x52ea9440b6fff496197768c8317e935444a65b3239a944bbfb1c6913c8419d0afa36ae39f54485565e25229304969cf22ef9d35889a07d29b78456f9652fc507	1	0	\\x000000010000000000800003c77081bcbcfaf6e88bbd88b20cd858b23b0e8122a329a977ed469f94a45a76c78c8180ea4a897f0f477625c52ad211ab126fd57faf6dc74d3fc9637af885bbc642b0394124d941ecc934876f928f8cd0362027f077057c5221b8b6951384f596a8006e3729c82a2203ff577fffbc2066ffa8cdb17a81bd5f44e998b52d050c65010001	\\x1f407a3a5377b8cf9fb1423663efc24e51b50702ef186917a91ba192b217157b5fd46edb67577bfe21ef1054c614ca34be55b43ab033fb73816c0c244838230d	1673882819000000	1674487619000000	1737559619000000	1832167619000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
251	\\x53727e4a50900b8995b821ead90a3ae84726a8e0e04cdca0534bbab67f8e9f4227e150be5a0281fdf7c863f55812199efa2fd703249142c9ed00bd876969fbd5	1	0	\\x000000010000000000800003bb2d0d789ae95614d1a66da10452eab806ec81d5566097d2afb67ac68b6c468526711a7490b9046635c3a4c445c2e4d0ea6bed7706571a26c71dec054dce103a8aa1c02c9f17c423d09c07bc6e13efa49debffe5eaad8b93af02b29dd1a6ca73739ad51b972e1f41ca2bb0a306c3faef9119a12bd645f42d3f1122a78b42a967010001	\\x2fe4678d03bc7685796fbb42b72854daa6a03164af65937bbcc8d33ec1dbd20c347b44280a7d9c57591a3f64d0566c0618d629b64916719c3d76d4989159ba01	1663606319000000	1664211119000000	1727283119000000	1821891119000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
252	\\x5372a62d8900fd201e7ffb46a4edb0bd0242d2609e6f3f494cb99e736d79df56e8ea5df1872e5de129e75b8bf63fd9ecd4cc7cc0080d4bea5e9916fb28e41bf8	1	0	\\x00000001000000000080000399e0daa8f140ff71d93e8807f6134776b41663564f45682fcab85ed3b8b27397cd30e4bc2c87b2c67ea228698cb2cd6a2839086b9f13ed48e683e4c4c37b1616d47b27e68c86da0846db0f5efcd96d4713fc45912f69262f1f32a70dfa4575e964827817901931719d3d136c9055e312144dfbe26b4868020f064d0b61aca49b010001	\\x69ef30319d8e577da66239cdfe0797aa6cb40ee1f677c635e897824ddba0cdd8f8294296a7c62141dcf63a3c1227f50906849ba79e32fc0c634695aa90b4110a	1653934319000000	1654539119000000	1717611119000000	1812219119000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
253	\\x55561380ddacb348a0e0be837a41256ab93f5e098a6c1a64852a13ed0027cbefe158c810afc83f7af9ccb8d68a50959b3c8f7e58e21e29548cec45899df5770d	1	0	\\x000000010000000000800003c5da4c68c4d8ba7a439fbc78e7992c3d07bfce562f9480f318b5255054662ef0e7b3dc3bf17906eff4f694e7fecac2b6e1087413e7deb45adbe6df59758388c736d7fb7de33e7c197855a033dd2fd437493788e89791a699392bd4b93f20d75d650f14ecbcaf63f3d907419fd8f4b64cd9aa49c5d2838615fe5b1bc8d20f8189010001	\\x68a43d3d29481275aba05380aaa984e36048b3d43994710326ec345bedadbf0e5bb20eb9c9b66664e1a492acf3cfa3f7a111e36cfd227966402f82a52e321108	1653329819000000	1653934619000000	1717006619000000	1811614619000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
254	\\x55ae336cffa28fd128de6c18fe3a49e9c832813fc746e4de5b5feab4e49ed546b81b535305c10b42533dc83a32fedb40e1ebacc85987a74511d70b388d7bdcad	1	0	\\x000000010000000000800003c6191d096d11aecb338cb0d5734f6575ebcd1f376c5db6ff1f235978eb2f0d661b4619f57516a6500f56d5e3f4876ed5784ce0afdc97243e4552330f758e0fcac9fd86cdf6644855302d44731af2ac18819619c9509802e36fe8ec90eb89f75b878766e3556e9d791f4bf311d75f5b31a44b42e9515e8514e27c004d7144ac31010001	\\xe1e142a82228d6afd4047897a043a966e55d6526fc72b9977b82921346f2675b278a7bfa969642b586c7c08894b140bccce288aa0601163715bdeaa537db6603	1666628819000000	1667233619000000	1730305619000000	1824913619000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
255	\\x5e36d51460db71dedeef06d1195bbf2f14c04de9d5f63c906095c5180d10b2bd5d85d61c9eb3be19035987a81d5e8b615b1be96f66b206c080172fafde479d7d	1	0	\\x0000000100000000008000039c9a0e8477de03c868382f043ff05522a8bc1ed75794b209692226d3c58fd142055b50c1cae5cea7830b545e102d446bcec7301ea2dd59330d0dafb140fc9585f1b940177b552b8d222bb7103f3ecbc7a83b9bb02b773437764c41510bba8d6c55feb69beb642a5cfc6e9b45fed52927481d8b8a009cdffdf71530423dc8ce7b010001	\\x02f46668d90077808fc607d811d30a9d00d5f0e805456a21ef07b80cbac84cc22fa4d358e0f7294de2ad1cf9717d6c9ca04dfebc486d4cd0c4a6dc86ccf8e60c	1668442319000000	1669047119000000	1732119119000000	1826727119000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
256	\\x645e5835d5d0fe948db4b95e9bdf9250c6bcc2a92851693d11382d51874089c5983ff507790de651c781ca23d2173bbf7edd414c7f65a62e43b311b575c93c1b	1	0	\\x000000010000000000800003af91d17302df76629eecc0c542214823798d1aba8fb51b6768dc181043df51675eb6b8770b6be7acfeafcdd68e0c367b0e9f6ed5a0a8b9727e76ca093a4d5fc4fc8d084cc15ea156c29a3a6db18a71eb7323e56cf8056cf3709f020d55b94f3579616f622b39347b9770b2abfddfc9b180f36f4a2ef0a208acb032ab49a8958b010001	\\xefc4fd9e6ebbd355b1d39dae30eeaafeef736c8c9a50626907468d4cb2e18e60441b57d8ad8909a6baac032ca82ba97e83042783df46fdfa450b192d2122520c	1679927819000000	1680532619000000	1743604619000000	1838212619000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
257	\\x6b3a5238a850566029e7f808174c0eb5580260b75045e336efaf3be4d35cd084885f942b7fa6beb5b434e81694e96006f7bc32e3a257f6f27050abb41f355c4c	1	0	\\x000000010000000000800003aeb5ae380c56d5ae3f85cd32ad58634e875326c8f9b9275113614a0fd83161e1906dc4009eccb50637f8e91b5ee32b7b27136261e89b42ef4d18fec785ebc5687d5a4156b9d7cd4aac2e549ed4dbf99a2fb55fd8928f9f9fa208d94b55aeb642632207174e8e3c27fd828b9a047f9d2ed0e3f36e1cc5e56e3906b39b2df11e45010001	\\x907da0c5f942026240a7b997e022c8f8ef329436361dece394ebd7e74b6d48ae35147e8b0817098bd91d9c04824a52abdbf6eaaf9c6aaf7d949087d9a4d34407	1663606319000000	1664211119000000	1727283119000000	1821891119000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
258	\\x6f028b0ed991ffbe726596b7528650e2da3d08a724c80e72524427a9311a1ae8a8c33015604d901072735264310b4f45f6464aabdcf13adaa935c5775f4b47f1	1	0	\\x000000010000000000800003aa7c639bad6b55a144d13a92165d0ba1ff84f33859d8e27fc0a2a5c45eed2e95f1c74515f3c9b973205392854f96afe799a21143f13e4e18b84fe34858946e1436d30020adba8276a0c235e1995a646f444fca92fa74b47f09cee11725632f85ec57e9c7faa8704579dc516284cc5787ee81895c7813409bf96286d5d2c81e4d010001	\\xb0be471039a1e89ce3e1aa702a9a4a2d69a70ccc3f3c0989c7dee062eb8aa7bcac6ed4f63e1fdfb69acfd1a3bbb81c41808d04500b793ab6c0a1c9497ed2710b	1658770319000000	1659375119000000	1722447119000000	1817055119000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
259	\\x70b2ad52632ee2005af5ebc8907b6f1fd784914d7d9499c3210a6e2f5cebabffe37b1da53de1473db1a189283e23d8677c0a06ae634513b897b89abafeafc7ab	1	0	\\x000000010000000000800003ff2d94113336cbc89d8391e15371c21a523778be6efa3ac15b79871a7b38913a59cf264fa62bb538fe737e944f93d657051bc235d320d1792a8a7f63e87563cba7997224485e3cb40475df9a5167cb481a0ebc14c0a6a84d747fa5895d9580d48c96a997dc091a9eef002adf7cb58e77286618f69c1a58be6be5d11e41c2ed47010001	\\xd5f1bbae8b10cb8e2f7659bb4dced03a8dcdd734854e89e99a2408948bb7e1779b5f190ef9984154755d610bf982a9713ac67da5df59814ef61e3ad082be940d	1663606319000000	1664211119000000	1727283119000000	1821891119000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
260	\\x728e1b6fc1a2f6df096483bd927fbd27a586c011400633e578cfac1802bbb2994fa168003d3b110e7e5915688776ce1ca62d44c0791ca4589a28630d73995fde	1	0	\\x000000010000000000800003cd0c6127d371b28b7f85cafa127dd9ed5aabb830e7f78e66edf4468deb3af9a9e5459aceee7f0bea57e6f08e2705343d9e85f4a3820432bb894b123676facb2e7cc5a6b2de408709866de2ae397b0f124c9242cae7eef9495a05ebabb3439e8698ca9ab78b88227f01bddb91ce4293707c34bfd6777e6862b4543178ada63f49010001	\\x663ab75eee3fd20d7b26125a54b903a5855aa8fb622780175b94de4120573709dfedac1ec6aa53c6b20ecd00ac7d647038adc5e9d4714ab5fbd3077ba7245909	1677509819000000	1678114619000000	1741186619000000	1835794619000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
261	\\x7272ab4c2d8770169764c0cc04c1c6db33d40276bb66636580034f00b2ba64516c26aea677ac7ae58b683b940430092640e4ade005c6c99422a2026a8f9c6eca	1	0	\\x000000010000000000800003b2b3a01d9e5aa192c949198d4bbbf95d2951ed302e9a0f30d35371a325c7e81f9f88adaf059881b666ae876d32395e105af7159250e694de78cf5af465d6820b503bd3293cc021b65e76b0a2c54251cd2ca2a06f389529e0aea72abecf8753da4a6c2aadaf4759c9d36f98af82355251ba93906613ff33a8bc9bc10061b26831010001	\\x5f4d8df5fc4907e0013c248cd8db70d1b06ac32a784fd2dc3e3acb3b706402b790857b852ab101aee153f140aa99c9e3241c3d9a6dc136e29b46c5eac83cb708	1664815319000000	1665420119000000	1728492119000000	1823100119000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
262	\\x732a8522a57a402078adc9fda1795668877a26f3b6e8caf870dc15483e33a09d5fcba1d760b8f074b9472ef956f04850c55782ab298aef63eff7f6143a383fb8	1	0	\\x000000010000000000800003b7a15c25f742abda88071607a3f6b992773e333eef3677a0c533bf3cfa651a93b59fe025a7372437800d9ac8eeaa090ce1939be8ad732ca38263d376718bdb629ed2cc27b4dba771521c2407eefb3847ee77cb436d60ab776f5c085ad302e5495d9329e12ea7523c1c35c402f154384d6e4aea563f9cdc2dc0c196c9e0f5b95d010001	\\xccb10994622f7f285b142d13ebef2e63e4254d55f7911a7d7c7f54a0dcbf31cd10f0e24316fe30e6dca4820d0ee10e0e73fa379c81143e6047413c7bc5fd9800	1655143319000000	1655748119000000	1718820119000000	1813428119000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
263	\\x740eb551a89cb4a80e1940c034328d402b91d7f206f77fbf1217f171d941434d639f683277899dae36368ab2fce9772ecd1a6260d374ea9be334fad60b18d45f	1	0	\\x00000001000000000080000396a5b794624e2d5f11091a226bc96c78eff8d0fae3e8ca36c72e449e7715632a635ea06191cfe5290071955c2ca3ee362c7bb7164627922fb504fe7eda5f86a4703ba1daf69ce7cb2a098c686fee88c56e476dbb2fa51202b738b00801416a03866c99f716bf2601de58fb8a1ed54c497d4007a7a1f7a0f51e3faecba3e3cf31010001	\\xc7bba6b0ee06a7f77d5a0f1b4fc5fd952592452d3cb137e64addef3f83a3b09c92f18d68afd67737ec35b754a280afb231d3e81edb91ef1d957fb05345865f0f	1659374819000000	1659979619000000	1723051619000000	1817659619000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
264	\\x772ec3510be4726d28500a3a4af87d65a94873ada1525381643aa174919777969cec581386d3c546a44327e0bdd412541249af5add55958b0698b9051484fb0c	1	0	\\x000000010000000000800003d41f5448816f7e3bc4ee8d8f064af87c46d00269222b63270394b633a68d65c8b70f5f5dd7d42b42a2c35698e1297f343ce59d3ae86c9b346f73f637666b4ec8d2280fbfe04d701ccefe109f1a8562003497881ca60b281c1ffeed57c4bdb66da4d665c392a0c82ee43fad74e10d4b2f129dc372f1c93b63db6d0fff45618a75010001	\\xedf27edb5a6fe9d0d19bc2c0604cda9588ca7fdafc30f57445bece7873a669484b5d802081007da0f3de6eb384c82617a4fac6f0b32f7b9d333f0478cdf7850c	1663001819000000	1663606619000000	1726678619000000	1821286619000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
265	\\x78c26bb00ac632c8c650260f2faaca1c0440245c49ecf774791f0a10c4b22d0f3b4745c8f10049a368480aac84aebc934bc3b02123cd6f52236183a80395488e	1	0	\\x000000010000000000800003add45704b3b4973ec9b7c1b8112f25b34095fc14285c649aeb4262999bba658a5a4f6bae789104982b432b33b4d1efeadd882c187d709cc7bb87f6b85f17c2a8209bf82ab857c983b0bc5ac15b92b804c71764b7ba88656aadcaf9357260c5db31993b0c499eddea950ab325f9e253bb7c76e2e088045374ae4672ab092b1d57010001	\\x959d3f83d82e80166e02a4156241c9e72177689bb141e48e1ba009838e14ca7a68651a09a12519e1a402e5e25f340296c9195f99e7e7ac55c3c5986e03175609	1658165819000000	1658770619000000	1721842619000000	1816450619000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
266	\\x7bce6538fd4c7acd4520bdef07c10fb07441d6ada25c53e9d63e71ed06e278a7bdcfdd3a870ee8675a568b455233fa100240a8b496dc64eb82076f398f09a80e	1	0	\\x000000010000000000800003b8e2ad4c964ae03b7f34d7861f55c7596ac341d13cf16479535f6a8b836c15df0addaed7bb83722e06861aaf775335a17ab83bf24b95662e301f2799534a7a063bdc43ea233355b32d57e9e43321c19f040070b9f8d3c7d92137e5105c7b79570b7b84104767d217fb3ff446d6302ac7b6f8425a00e85e8bad82ea71469206c5010001	\\x152763992926c68ffffd3effa0c4ec3da449fdaf2783318b7ae1c10ceedce8892fc2e43bd26005a5a96bf25cde4e2ec8d3f36217671c37dd7e5736ac6f95be01	1669651319000000	1670256119000000	1733328119000000	1827936119000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
267	\\x7b2a671f5592e4bd3ea32ff9c4e20a08c4600f3c49c56194b404cd9ddea8d63df3e815baf9b45bcdd6805d8eb7738007f57b6e8ae2c7534ed3fea902b799b4ce	1	0	\\x000000010000000000800003cd11edb656b38fb9e9432a417d4aaf2bc7efcce5ad22970a824157689b2375d694e4d6a0f7cdf2b050ea9dd67ca74b930e91dd8cbd2f8898b239c90106c9f1bbd7b1f3f4be8465ec6b7f8f84073d0f6e00c1f4165cc8b540b233acd6ed3c6127059c4ec4810f6964c06099a3ab997663bad48e1322ce5b029cae786e6b5e4981010001	\\xbb72d1e3ed28ab719f66d89ca660573561e3f76a855c347073fb3034b033b957db79a1f643ef37cf4394669e97ebc4fe05127ca02b1d3380c1e62e0ec0b9fd06	1682345819000000	1682950619000000	1746022619000000	1840630619000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
268	\\x7bd230227fea2b75f86cd946dfa1865800e673e1f6275bbc481b5afe0f5b7d9951f8fcf1a0d7b9b2c6a2418be51ac81e28d1690e23ef7aef87379d4420e27923	1	0	\\x000000010000000000800003a07d498bf388f2333e2d0d38dbae680960a4e17606b7fcbd9c27d305421d281da6db03cf9f54e98deaf0d6f0d300e41ddb03cd35e7f0bbbb4dfe649def85cfec80ffff4e3cbb0a3382510849ece74c177560f5defd7e4773e4fd623826c487e23f0c63f131a152ca59c7360163eec49fa218f9070ec3e4effa31bd0234f48f5f010001	\\xc79f2559e451c64ee04d9b9f32f035eb8274ba9b76e363f7b4ffdb70c2e2d25cf5481cb0d2d17159bc86d7ef50baa92cf297fbf596f71940b0b203dd792f7a01	1680532319000000	1681137119000000	1744209119000000	1838817119000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
269	\\x7e6605ebdb00ac4643dc73d757c0f8d32fe91a9353ce222b738bceedaea2331afaf05267954eec7f1c4d054fad5c78178a74d74622322e0aab5657eb5c0dac85	1	0	\\x000000010000000000800003e041cfdc50394dccb16faba290fc62f7cd5b81c2c39846bf34c8e41c92a96bf621b6d34906749019dda1e9be40ac64a3bbc50fb7a3b634d973458092380f825472a3f37f1af4f8fe4a29f159f170236107cec8eb3598aef97557421524dfa9a5d6cb79b8aaa20227c5da228176fa3495e9dd2c589c55e14bbeddd2a3c475ffd9010001	\\xdd8384a02fb5d19c19efa6ff7bc7073761387b51fb01bb13fcabda86e6c8df5af23b1f6b98e459ae46c0eef8ed3a784fb92f03b3833c4d97f4027a571dfac606	1659979319000000	1660584119000000	1723656119000000	1818264119000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
270	\\x811ab73743081980715a2c174e1495229dc68f7cb0bc7ca6c42fac6275ca3a3dcb11a56dab65a06e05aedfa835156f20cf6e2fde2fd43104e3a96873c9da38d9	1	0	\\x000000010000000000800003c7d27ab188ed63017c458eb88ba670035afd518c88f03ede24d142915bf69be8482981f2a43845a2b41208eed93ee70653583ee2720697784fb0b320053541e49bc2de47da09aceba0ba4b91341b7cb08c8f9b310caae464422f61080249d204cdb13b5cedcce54057d6e4787e06aa05eb64addec4d779e6ccf49153e6193c23010001	\\x8f3836def97e142834739159991478d57e51b7aff9e0ed6f786757a8cfaafc7f153bf5d55cedf274fc7eb7286cf319eb14e97582220478b5834ecf700654f606	1671464819000000	1672069619000000	1735141619000000	1829749619000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
271	\\x82763067a5cd27c95fa6825742179c5337f7988269d98b217db2b077f5e81647f9f4afa5a8818eacc0b1b8e768e64bf2b46d20815d3b747fc8e5f212079eb47d	1	0	\\x000000010000000000800003a8de4f5c365adc49431e3e54de6c8781f58d6c17e101fb7d472869b0a0a0ae5f453703925d9f13cc5c5bc4a7e6c33a742f34603c06c290d6a7fec374810460bf605dabceacd0664ffb307f2accb9617acc3b835489fdeb00cf3782850cf7ff3544407779d7b4de44dcf17aba1c6d97dbaf38c7b66e461b71e9a11f679d4c3ddd010001	\\x9b2679d58df03602ec79c421ad8776ca162b0f86fb18259971e4a9b3d29a7571e12cd00575714c092783fcfec42a19cdc68ecde161cd3d5527ee28b14587a401	1670860319000000	1671465119000000	1734537119000000	1829145119000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
272	\\x83029eb0e817db6b67b7ba5a87ec3e6b4bce756d696e4f14db993e38fca634263a14c580c39380d9cdc7dcf84a786945330841e1dc8f8086a283822e65ed3aca	1	0	\\x000000010000000000800003cc3471154844231831d7322a1d404bafcca64ebea39b74a60c8f2efb76e556cdb394a664af89784fadffcbe9dcb4d165314a6048744f663d8e8c2e475630f97e7f2500afa9ddc24376e2f57cb450d76038bd29b3cf5b1aa7b008da9395cec156e0ce8a6d791f3f8e13b7ac93278c91a450902a7f1d00a8b38aebd49992dd7b7d010001	\\xe8de27567138bc8f070a50c0e4e0771e8cf580c31dfdd0b59da4a99b52ccc03461020083fc883b065b9b6b14fbc4666df5301fd2f97e1156031b66a74cc0680b	1670860319000000	1671465119000000	1734537119000000	1829145119000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
273	\\x86420305f72a51adc124c1caa2e95eb4a17cf174452fac0a07c6a53ebf7befec792d5735a0501db112c9284093f555c9f9a31d532a3f8afbd4200969b3dbd111	1	0	\\x000000010000000000800003a669a97af45dcaa196c996a35c6b04bf3df787c3b306e419a2b7f8549e7c0c8fcb9a3e54c3e22aca4e00c672966d4ee6b1b3db1525d0fa856b51868b7d5edde7634491baa4c22d8865843b52289e2fe7b350f31e7af84a6c3531cc51c37e58721e8cc8104422c00ed51b6ece450d25d86943c0454bdc885585319a45ae95eb39010001	\\x9ff107063b9326ee44a73a22a248d3ad6b541deb02f6a50f6a1d6377e9d69b3791033a148a46fd53c16d23193bb87ac8086ebf4e586e64ffc2ade137b38eda08	1671464819000000	1672069619000000	1735141619000000	1829749619000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
274	\\x89f62eb7d0be3e4ab1c12e950e919a505ad833fc2f3cf29505a1ab81df480ff7699e0e36f03f8f2d055052e90c8bc37961419d7c67dbc64e9eb04bd135447517	1	0	\\x000000010000000000800003b37a2897ee001b5f5e171314c1e299a49bad021d665bc8f032c339bf5d1510aff891f42775696be635acadc33e2319b157f26b4ba6f368a5af362abb9407df09f787106de759838f092da3d7d9bc796dce3542d6d4b3e4c06cf6e11c250fc9bdf4c7aaee840656856c314e1c3a4d03993337047228c4573ddda7048b84e24403010001	\\xffff62c30b2e2da6a1c932e1a1a93c7b2ab54bdbdf7e7bb1a7713c5732435d7c49052d3525cc40061fdd1d45c2885559a7655224ffb1503b4c90da12e9eacc09	1661188319000000	1661793119000000	1724865119000000	1819473119000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
275	\\x8d12ec8b4df50216918adeb65829ab300d3d1b78287d9d5bb974dffdd57a2189e7ecfe42507ac7004c02469f22857f3c8049a45256e201b572ae8f8c5e8d4412	1	0	\\x000000010000000000800003eb29762f0f8767f3f7302a30228d953b00fd6d8ef3491b27b8ff96952ea2edb1d32548b74ee140da16b6d7f4c5b4deb78397ae42a51b6db30f9b4744c3fa5880717557ab67a262bb8692f3247eda4f224d6ccf424ba622796f656338c3ffc96071cf4525d57fbfbd8833734377eb0b89bff38607926519ec0143f53227afb4e3010001	\\x5a5d95acc298650091753c804ad6202100a585fc0c073063ee2cd84d5de9a3424a37d79e284bbba8dcb76ebab6196121a96a6102625fd7f14f22af2ebb5b9f0d	1653329819000000	1653934619000000	1717006619000000	1811614619000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
276	\\x906e737a17bb00070883e93d9b930923d9b2410771059e148309d9219c59ee9dc8050f7fdb6f8ca10e35e759095a920bc8a60108e182bb52be993c7e7916fafe	1	0	\\x000000010000000000800003a25ab88b502f52887222f521d0af0098c582536f862b2027e59fb850eab39a7a5ffd16b6f90ff14929ba5b4424aec489db164d6f2557b031c65c606a2127ddc50fb45ac43e2d7ca6887f15a8a4d4d069b202652d6f8700b49df452ff94f2e0bc829c3d205ecae6681545cd2f7fefcd69699302a080980d58a46b1b7d2c5599fb010001	\\xf7b9ec5bed26d81df1e51c12424bba9c32b840c325a6b5e8dc9a6c575a8e660cc19061356af1725546016f3e6b386ad56ef271c7b1b415556ba029b2dbf59a04	1656352319000000	1656957119000000	1720029119000000	1814637119000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
277	\\x9092ed6124283ad2cf6a55bfb6bcb95d7e5f21cd0a594920bcc13d35e81968e9f8a660adc3443c837470e343b6a0b52d1c279d616c4b9e04c2cc428787b08b56	1	0	\\x000000010000000000800003aa593482fc7d1774c79da0917df9be30a802aec3406f7fe549321d3979fa683f0f814fc70d5069706f9607beb7cedb6e69360dfcc8db30c0227efcd90d47e2a4bf0219086e12d93758da6c1a955ae528383ff791dfe75aefa987974cc8e4301976ab5f90b69bc27582642661debc22f75ab68550795fe7e4979cc20e05bb3f8f010001	\\x0f052c98fd989fdfb72e2ddda1b892a3d53ba9b913ee9ebae3c307903a26163277cc5c4e4da37d74d413a8d2dab761b78e88ad39c7b44cdece57a5044d60320e	1673882819000000	1674487619000000	1737559619000000	1832167619000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
278	\\x906ac74e77c6ca47f7795d1bf2edeb30e754cb2c5875cddc8e1883ba7d2127e24f811e4aaaf17f17244d1d8b63bc17801352dc83d767ae71a5f48717396e08bc	1	0	\\x000000010000000000800003c1949e6c7e569e0d603a8baaea8027b395d6b88cc77bc750d6ce3cd50141171bb6503d454b1dc270ebbb5be326ad9c2d15e832f3e3cfd785f3cf482fe621a6337d926e769ad6acf0b359fbc1537a0782863faab7edb424e5c66f2ed749be6b3037d0a7dcb152a90e8732b883e022ce3b3decb74e5abd0bd07e12b34f21b4e7bb010001	\\x2523293739352ae8b7e76e9c856759f49ed2a5818f45ca3e79ac9a34cdab3d5b9650c719e3d6d04ae62e9a332472c4fefa47abdeb046370bf52be36fb3452f0b	1652725319000000	1653330119000000	1716402119000000	1811010119000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
279	\\x975e563a02c98637141696e1da08c7f58a2f88958e0f5f0c864dc1738a7143993f6cf280b793e6b5846a5cee93c7ec6917b2211fb1f1033234006f54deba39f5	1	0	\\x000000010000000000800003c0bf2397007d8559b90deccf0ab7edc416dcc749b4f63fc8b3a82a4aa82412f933c6edb5b12a8bff11dbd51f936ee63fc1d99ea9c0425977fde4f17c92611118c03db427f361df02f1a6f8409a0c495d3fec363f70dfaede441f643e48c0e34a4ee894a8558ea9d9ba34f5c705e22ea7a989fc52ef0bde1ca104d8cc10e1fc23010001	\\xb2e80e4ef2b9b6dbef6a62e35d1b12f4adc521261729fce82eff8b19d776a2cb39dfff7fa866bac2361ad78da8aa23733c68cc958add49be1838a3b584970103	1658165819000000	1658770619000000	1721842619000000	1816450619000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
280	\\x9cbae90bb10c119eee793bd5974ab9348e513e7ce9ae512c4bbeac6e7cf22a4edc7a458cf5e440332dae3784e8f2370326c4edeff073033fdbaea77ff488ee69	1	0	\\x000000010000000000800003eea27e17f64771cc6641703af31ec7cc00b6d06cda340d9d5160c18dff2c814291977b3b5deac9c3f668e9a9b4903d3116ca779553fb9ccf1d8402149f378ff24ec074c0e7fb6f8f6188865f321a47f95519ebbe270db77837bd889886b9d3eeb6b29a9fb277cdd8e42aa540ad1dbd7bbbc3d41fc841266af12048ec8be2f0f3010001	\\x1c6245b90730f37407dd7f71e478e1a8b6845b2b3259c9b6835d2342603ce21fea76e0457f1b02c6841cead7b552b188fc7704a52343eaeb06314772995c330b	1665419819000000	1666024619000000	1729096619000000	1823704619000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
281	\\x9ef2f85a66c581e30001612a4274358b8c59f6039ec4119a9c944aeda404abdd1e011f501c7e2eb1606cd424f6c365813cf0432d55b1ba6c52021eac324f1360	1	0	\\x0000000100000000008000039e04d2f27cccd6fa69090487559dacfbb1206fc801c6963784f1271478d4034a9b137c6598e9f7e914d27efa8c615fe652faa8e44325ad52de248e50ee527a29ac3d400cec43d17c49a32f45e28db801f0ff7579afe993f10c11bc7bc7a66063824931e13e45fa6c5c2c30eef4b5b7b099ea8b534d5f91f1a1545343c03cdb21010001	\\x172886aa642160d02c48415a29bb50c91a44a833946e3ee98553151b5bc88c8fc025e3aef9f57aaf28b60f6084d6b757fce36d02e5d560da81899e118a5aee06	1675696319000000	1676301119000000	1739373119000000	1833981119000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
282	\\x9e7a0dfb952bf2ec7cd80db2e2805aa74edcb58484638de487aa2c0177adb61110cb81e342ac40d2a02aaf6ed95103068b14e1beffda0ddf8370a99a1fbebaff	1	0	\\x000000010000000000800003d4033b8bc5ac912fcf899e6087973cb23806bcbace325f5fe22cc8e8606e6ab624afe737fefe06f29bccf1ab4e6148b684433b50e7a819f6eeb130eb0eed9fec51eccf2fc9896b9552a4ac8f5f73aea801f2718cee219c830bd10ee1a1dac939dcba3558aad910f91971bd1550a25014f9c0431e368fd8b4afe6af5bf4f71cf1010001	\\xb172e0f7b1632c27a6f76bdf5900a1de7e57fabbafa4b6213aa519aafd43e6923307eeffcd614e3740bb7eea18671595aeb6b9bd4f739977e5f7710aa212610c	1653329819000000	1653934619000000	1717006619000000	1811614619000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
283	\\xa10ea782893e8c9a836da5e48ad198f30c7ac10102a914fb2d265f1f831e5942a9fb2d466e3cb805a180157a7aedd03f2d1d7944c31aae5d4f9a8df5330156bc	1	0	\\x000000010000000000800003df9b215cd11fdc01711f1c48ff370613ff687b9e9de4c40fcbfeb7efc46b6808af7cfcd6f699650a864f031b1fde01b64cbcb3af7fea03da74f44fb2c2bd79808ab00e8859fff85907fd91dc4f8af273813ad68b5ee87a0dcd29914b944fa009af808529b9719f8eb6f1412c206517139ec1be9a39dbdd60641a94372e54d035010001	\\xc16e1c3a47b9e0eaa6540a7eb2191d83d92d7706362e61266dc8715a6bab87a0b2e13c058ac46e81a76a16cedf7ce7f884d40306b024d2a50c02e3fa6bbf1508	1656956819000000	1657561619000000	1720633619000000	1815241619000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
284	\\xa5a6e2e4ba9cbe33aa1a844fa5cbdb07a4990eed80c3ce254d084414f751aebbbe02b66a797bfc54ea11cb35b17527846963f574655a46f1af6ba9643dc15877	1	0	\\x000000010000000000800003c483aa21f4fb79e4ebe3f8d94c6e2db3c12f326fbf0a27231a04b008cf935ba3fa65d053485d031c201a8ca9a656fcb8738782de608514eed8aded790baadae8f7637230a33764c61fe974138061cf4a367890d0587822251df707d614fdf315ffd6f352627f2c03ab8342251e89f0e0e8233e43f1951ba0c792608d8cc2f2c7010001	\\x619f005ef1f9e945a19c938650a8cd63d44b10ac6670acef235cc463936e317fced22cac6d984195c0d815f1caaa680b9bd25e859eac3b0f6c033a21738adc0c	1673882819000000	1674487619000000	1737559619000000	1832167619000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
285	\\xa67a4160a6738113ce5915d0eeda79498dde1cb50b0e408ad2a66a464b70fe01adb54232d6e92ee12db9d04505ab7cbf3802da598643bec7865188d60c9e13db	1	0	\\x000000010000000000800003acac20385ab28c5c4eeed27b64874593281ff423a93d4e989b8dea1ce3bdc50cece487a5d574f47ae5d1fa900eb66d7fa37fb265b6cc733ccbbc2ea8249067db88411794fc42b83f5ecef56464379bbf383da63b9d117519d376cb603d7f32725249521f1632d3af90fa3e58afb240740a7a86c0de19e6a646adfbcf5ec6943f010001	\\xf779ab0647eb17b7acc6fd592fa2eea724c5d3606fdfe0d80905b58a37211dfab8c29e29dc3e0425402a81af06a07a8564290ed0e8515df86794efaa04c30409	1657561319000000	1658166119000000	1721238119000000	1815846119000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
286	\\xa9fe1d7bc8362335b4fd79c55a5a718448e71b2091cda2632f8dece212d51c5632a1c307081ecbc67fe0f560062f5db450016fd34242b2b9a6920ccbd49c7fcf	1	0	\\x000000010000000000800003cf1ff98a13e11f39beb578940c81caeb9ddd4ea407d6dca9ca3545138366e42cdef31db0aa683feff91ab9a54d96222fe550d6253acf493a2d70dc6407374364c2820b9c95982915860742181fd9c2f418f4ebe1fb7733d923188cc54a5a9834cd3ef5bbe8ff56147068961673f89bfb055e1df84bf401547317ed46b608cbc9010001	\\xf121ec84c120110e3b6e872e664d197def50972873f09ffb1a0700468f2ab14faf30a8a5a0b85ac0f829d36b20218d99af919d3ca22699cf441f3dac8fb67c0e	1673882819000000	1674487619000000	1737559619000000	1832167619000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
287	\\xa9b6d1337e775ed9bf413514f21eac8484f1930fad9956c5b64d5b05c24a1a7e7b9311d1b1168081f227a5752c6c33ae1caf9d57067426811c147119f2b8958e	1	0	\\x000000010000000000800003ce3992c4248647ab6829f9f5c08411a134961467c72ea148a03ee25aa2f2b7128437ad3ed081998fa412f404fd895d7230e254781c3ab0bc22611306e2d07d9e12b80a4a90db734df10a274e9911feab69935922a29a0e39ec4f2554a43651616bf63a7140ce1f9e1ad350f94d5d00822c339a80b3fc19e2d5a73a1d337c44b3010001	\\x084ed50a637959765b65ab23f85d1233fb68d935a37cf2cb786e3268dcb020f736e6539e9b1297578bd0b1ef57ac2a713240be83d9a1cd62f0fdc771dbd1b203	1681741319000000	1682346119000000	1745418119000000	1840026119000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
288	\\xb4b23d8a20d571f8c9a52755ef188494dbb7b0b0730317275424a8e258076ef56e7cb24ffed147a68f2a8a9dc9a1b20ac8b2f6d965c86d86a105460dd0dfe858	1	0	\\x000000010000000000800003abb4961c7af9a130a77f7a2a7c09a1960550994cb59fe9e6359b54c1346811e5f3cf8775e884849561f1a5318d462130f1531afa801c778193a303baa654ef7ecb3834bd2a7d95b5b2580bde258075c279261a5797e9fc55cf5b391b021c56b81612f4520a47ea8dc4ac98f6f869afe43613c11329a917dd1b839a2e830e1a51010001	\\x56c1bdb60761dd671623e8783ae6ba0d12bfc8c37263b28c79c54dc38ebfc6a11d474e3ef038f9fe49c50787fdc47d9be0e763ac5c207e741555c627c98dec0f	1672673819000000	1673278619000000	1736350619000000	1830958619000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
289	\\xb5c6d0db9338070947d9b8bc96b7ecbf7524d291093612881649386a925010cf62172e2c2c24fe8ddaa30e019b127e10aab2f537bf4d17b1dc69308d2a688a7f	1	0	\\x000000010000000000800003c20f891a0280fe995c202d85cda6d182ece2ef9f563ba8520bfadcf5f335075e730e4839c4cff78898de5820e9ce421dc9526e859570d090d15657392f832728a72ae2a25994d9c488efe203d70697cff86335bc844dea3be5abd1e6c1eb49037f3ac0ad2d7254fb94c9db569cc48fa28b672d2c05d3ba076a0fec26a0e8d003010001	\\xad0c21661808b0c9227cb5d7e92051843210d511edcbbfd0244ca75250a55f2550d568f83a8a01590f6a7e2553c014eea530050326646f874108924fb8121509	1656956819000000	1657561619000000	1720633619000000	1815241619000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
290	\\xb602dddb76b600aa7bb595fc20cc118b39b1391bfa51cb3e16d130d99f0472631efb43744977bc29db41f326791da85a1a84522cafb03f277be15556a7ccffd8	1	0	\\x000000010000000000800003cb19187fcb8eb92019e003f3e59236a2fde7b0564ffdb32ac030de36f20f8a9d01cd1d109d48198546224cdd094c1fd1dad70228043bfd06dc389245662c0267ab82725aa2db74ac5e856cfbe8957f7f6128c5d698ce4957a61fd003c44ddf61f16d61a35e2b9c7b304581ee03f8021da6bffcc304a6fce3b6f141e982e039bf010001	\\x74e6891e9b625d40f9444a6ffe24c30a0451d053774f54d849843c3496ef01f97fa3a8a628219081c5f5d9ba4f8a978f6ae40f3972a2dd380a969b519d91940d	1652725319000000	1653330119000000	1716402119000000	1811010119000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
291	\\xbb1e94d85915b9ed183d70750b80f359892f6d18da95571684a9aa96a043ba2744630e4f1779d50e945532db30d4316db1c55af0b3eb551d6fd10d4301900e05	1	0	\\x000000010000000000800003b06033dad310e338e1150dcfb851eb3d5e9af87aa7492f5ca4ceaae7417515beaf668582db33068041983568b51dcb17111c5969fa40b4965644f7a848b7b46602049510768ae8b5b9cddee513e9709683aa04e0d841aa0b98e6a34c7c5659b2942a36419ced034cc06b475db9d3ee2404872b7152f48c879949b53f64d66af1010001	\\xb134dfea1e47b92c5fbb3063c6bc60d851a2d5899e8b126ae4a7d5b9e626d492f3cbfe78f50d489da76173288fae23b2be1dfa381edad6d2f23521c6eb46d702	1667837819000000	1668442619000000	1731514619000000	1826122619000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
292	\\xbc323a446bd8a7c9c05af46ee5abbb5a75525f0b5273f7c825f27c4f9b1935f4f29fcc77729db3df93f5f377f4b890e96a3bd6e6d78dfe7022ebd00dd0ac221e	1	0	\\x000000010000000000800003bd5ffa9b852571c795fa49d8412eb415c03e8c32b0be9bee376538450bb9a79af577de68b3df6be8247b13b5de3a6320025c66e6f655f95aeda4c5e7e91fc70131604ee50cd2ce4c78a8c74fdc27bab3404f1a53431a145cbf34d4fccfe086f0fecbfaf589f7987a6b45c6f883562acd9d861fc0c75e8000c7013b9d8496a3b1010001	\\x172b924d5f51827126f112cebfc578b99a6f071dbf8c8bc2b0052eca7decef144b670d4fc2c5fb6575e21f757d94d3ec5f0f0462eaf9756354f686dd6bf77d07	1664210819000000	1664815619000000	1727887619000000	1822495619000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
293	\\xc30a75fe356987ff4e9ab2e654fd8251005650c6238f449489f1c861b61fbc4247e88eb7e3e666cd8117ec7ae1021c58033b85f287eded8a5160758d987f4c40	1	0	\\x000000010000000000800003cbea8d22744aab152bbc6f2149e401febb3eca1222a6af061692c2f939d75bed535b9167f81a1f28cf4a7bc2211bb666d31b1d83936069044e68b4b174dad9ea7bf7061dedb09f71293b554f39e5fbb779a3d92fffb2b52c4e9f107509a5b80eacefb957f9e1c9905d91ad8437af73b8e36146cc9264156c0755bafc7da79bc9010001	\\x052cef04ca365b64ce51e97907f52473adbf7df25ae40f037cdcea90950ee4aff6b460cb77f86375d31f104b9eb6c2c686a9e10401f5b826c2f1a8956b3ded08	1666024319000000	1666629119000000	1729701119000000	1824309119000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
294	\\xc5dac36ddc6a632025439b1d7a4b96a929a17380b563b9ab1ae786978a750f9c818279c7422350c2c7028e9aee937a54999ca7bf3be07b75ccb93325d9b1848e	1	0	\\x000000010000000000800003e015202bd8480d261656449cea08b34691e9c9a92e520b5b4f95727b589e16c241fc8b85f52f8126029edf2e4265a0965ad8c6654990d5c10fc8ad10618212ae6c323149de5a68a1ff1c60afe529a45a0d60104e1fab841e3cfbace554e124239ce640e2d07742f3a04e9090656c594e1ec3877e82596e71e7d156a5a25cb8b1010001	\\x9173393b3fedfaaa586edf42a0e83ef22bcf2cb678b2b832f45b3bf3b8ea48709694cc4e882af825c52fa915897754c6ba53d0946781d68a4b9f28c9271e040f	1653329819000000	1653934619000000	1717006619000000	1811614619000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
295	\\xc55e31a616233e3eb13bcbb1ae14e5d3f3dec802bde0f49d4a281ae540cbbc974a1459e411efcc342a618281a5dc655f00fbf606082e268854a39e8fceba2d86	1	0	\\x000000010000000000800003c24d1371531f798ca545732d79e970eaaa930e7a574a3d9bac1b5682b8808fcb1cc87dc598be91530b132169375a901d2bc2b9bc01b76bf0dae0ed06566e3b65d76c4e11bb63bc0e07f346073e6867f3dca75dc83592fd5032b4b857f2d4474d5a8c358f2a251f1f8e9fb6b674d928f7c80df76a5da88b449cb6e8d829fb82c7010001	\\xf69b8fd1d17f86853e231bd5878c854b6c6372d05e9b4ffa0d470b665dd30bdce0a5febda8bdabc2536b9cba2e65f2106a67b36334852fc78ea5a1b527141900	1679927819000000	1680532619000000	1743604619000000	1838212619000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
296	\\xc6f63c0b3d510ab9f464adad852859308e99b22fe1842ee070262c6a173272f2cd7bd0221d639bdf516e18846a6e380a3cb9d8f8d70302781b4e9ba19dac1eee	1	0	\\x000000010000000000800003ad20d4e099d5b66c0c5eb33c9ae9a06ab3e9ef3cbfecffe056929d07eb6b020a7edae68cb4581fded4f4e64d039b6621df3ddc26e8fcc079a07852292e6c7a5c5d35666a4e2244933928fd5ac658f21b08887e95c5f06dfd37a8cc262116aa19c3814d9d3fb69a4db555dfc47d6d2987e259f1afc1586373d8dca436eccb5e11010001	\\xceb7d3705a347c1462686e2c405196593466b14a64a35dee8a50bec7c4452336236749fedd58ba07d9d36011a3eb7adaf347aff6d20c2693a752a15b78ad5a05	1674487319000000	1675092119000000	1738164119000000	1832772119000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
297	\\xc73e7b00b3b81e2ebfc3a74a4102fec10f9ddbb298e5786179f3a57b7102b28396ddb77bfd42f31c9bf9506c070d3b6566f8518afcba641d5340b188011c457d	1	0	\\x000000010000000000800003de59652f486c48a0c3e15f3bee1a009b1a8d73c9bfaa7f20f23d1097f7970fb5f796c0aa4a2eb17597d5b36173c9010bb99ef46c8511fb4bf3c9c02e5b423c857dc344339be2dd0cf8d12a6c36815670256e9955c5c2739058c8747858ea2daf12c8b1f0ad407530fb4b79bdeaea70f9895c5aae3e22069105cb80e5aa7e64e9010001	\\x07fbb8a715d4cd959ff9d1fdf9ba35a050464cb11668e52d18690c802d07610864ae7c58023a69fd670a09eef5a4a74c6ab6c44698be1956feb7b395e3e1df0c	1664210819000000	1664815619000000	1727887619000000	1822495619000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
298	\\xc79e42ee5ba9aa1d7d4b533b0d92d7dae70690ac70185b17b8b27c73dccf1b68c4d5d06f6a6b61e326aaee5619c45ae57b9f7b5052767a96f2c755712033c226	1	0	\\x000000010000000000800003bcfe8be21cabcf147b155a8864043fdbcae7f45ff8a5eb00326d302a1eddaaa6f66b4ae3b3ce0309d56f2e8f11b4368b7087eb00747c54c3e46e1dd2830c180dddda62fd8965f2cd79807b66caeb2e3aabfd4caa84d01612993f525396363155f88b5181a64be22864c3e4e2b4ddbf9735de13c56382263ff03566afcf816b75010001	\\xb2bf2f11d0cfb689a1929c8e6eb6dab4d60186d9f72f365da67992b87cdad336b95c3d6c32dccb9780997cece6b4f7af81cc1ea326dfbe005a9fef95aa2e3f01	1672069319000000	1672674119000000	1735746119000000	1830354119000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
299	\\xc91679e38d93b0c980f4b9c4170e8d003a062c2d3aef7318d39d536d9f51ea584e69f0a786bf4962e01e51761543c3fd09bb1e08a7b6d55d6566f5119876915c	1	0	\\x00000001000000000080000394168a7c5bfb14ba39a66ea050b0b17375bce5e2df2ad1900773617d57c3c39759ca13e2aef7ec6105c760932d1cf7adce0b9904958ad1b19418bf968fa1884b68e12e555582a0481eb5903e894613f700ca14aa2c4e6a204d825afe08d1fdd8a0a0741f02113f6d6f5df53249bed1f357fc2302f7eb3240238f0fa543e7a9d7010001	\\xaeb02f7b9f80f1c6e88161a1904e5b8afdc4905ad76d33a575d05e092bc01db4cd078ea63686b8583d67ea3b03b75589f5caf763cfa7c0754e85f2e26dd95f05	1682345819000000	1682950619000000	1746022619000000	1840630619000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
300	\\xca42ffed5e93e816ceda5f61f730ba0fe16e5515f3ac23b395c0e6e2c19cbcb57c14f026bc7535f9b0c685c3cfc55a1466675499fe15a7064657a5b1cf207147	1	0	\\x000000010000000000800003ed3d962d37f4ca7898a0fa3ec66a352d21b6544c66f96d6ae7a5b7cbc4d13976f211c3244b6d27e3b0bac7cae566b66b35ddd36e81b1f4c50650958d85163e39daf8c031a5824dd28645c090a5802c357a057e1318d27474cbe02a5a26ec57bda09617289f1f9dbdb082b5411e0d06899ba15800c0f71d5f1ace1aa90543f45b010001	\\x7bbd528308464e587bde3201ddb7633e18553130b7f08d5f5a1c987d522bb035f61988ce122f7ce5b4d4b04ce27600bbcc16dc0426e5a1fc377269e5fe314d0b	1672069319000000	1672674119000000	1735746119000000	1830354119000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
301	\\xccce63f0671e01d75db2a08da9bb5362dae3532b3d10ed90beedea3b3bc5438c250f583026675f37707de28c05377f48e7f9322e02c4876afc51cc89a1f488ba	1	0	\\x000000010000000000800003a864f161f70b56b6fd8a34fffe7fba0b6c920eacee20771a3a17e15ea236cc659e79cb56e4ca02400a458b834d49d80aecb3d0f5be031eac054e76e040605f3489eb18d7d1739dfdf4c2d63df3ea8ff0244cce1b1cd914ee83d6ee887d81cc5407d906bdf5c3f5be289a3f06c287abbdd994bbd93525de1450b96e3564137b0f010001	\\x7fdfddbe5b93cf907ed37ab860ef1e7c82bc83dcbe0ceb00170399d1b195c85d7eed98308971570e4e3ceef7175b1a721f47ede2a190a5ca3e51c30a34def606	1658770319000000	1659375119000000	1722447119000000	1817055119000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
302	\\xd0f6902a6cea07fcc57e78dfe1c1ee7294274af10262602f2f5e11595c7f345e02b9ffa1e30fc28f25d0ea9d076f21eca601966a0e2ee26f47712db1207b9136	1	0	\\x0000000100000000008000039b64fdccefc3f56676d0af98a8e12881870b5b44184fe42b50b18367f99d911cab201593f5d81944682994239f36a300222bd229156a854c953cce522b8902fd6f002f9eb50c176d34d9f64a33cf73b1ff46e20ed70d3d8b4931c396797982189fcecfc9605dd394aa092199ecf59090b306404f92dbeb8c8b883817a5498079010001	\\x43df8c5d993eaaee32325559beabc8982c9048da3e7b7bffb51b04f713f15cb164c39ebbbac96eec40fd8e37da8e4d6a3e087030185d952e082f921ece79be0b	1660583819000000	1661188619000000	1724260619000000	1818868619000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
303	\\xd016f8fb205ebb2fe1a996864828efc74ce59e0ca8e862706f2ebc3e188ae94ed1ea2d34cdc77e151d66d428e167e5e4cfa15120861345ac447a0452dd01dccf	1	0	\\x000000010000000000800003a99ac3cdb9494ebdf2cc7c20e301991144e2486a4c1dda4aaedda79e4c44ef04d969bda4c1c31e2f47a2c71b3592b5544b567b54cfb3db5086508dd7577c4775daefa383e8b87b47f6c2cccf26c7076d3da7f85839776bf6b4fb752c0d3712945b7f35a15605ec617913bb3f8c9efe44c06b595bb9c5b1319edc34430720e983010001	\\x38b3b599392f39ee958e323e2ae4c60bda170c2a26c193b0f14a76f2da94f12d217af807984a36b87e9c4a35bab9eb16bf74375a09b0f43426994513bacffb0c	1672069319000000	1672674119000000	1735746119000000	1830354119000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
304	\\xd25e8c3830e4089bde3423b3eae5e57accf438886c4cb93576f2178fe4e98183605cbc58881571e824762f4478747acdc13797e6383c8e9c9426f107edc13f45	1	0	\\x000000010000000000800003c4e62149340fe58f7c62b61450cb413a199bb9d7f4bc76eb77bd906b54cd6f7d19bd34b53ef2a1319c5b74e8908884dd48f5490657d7fc1fef1b8fe7dc773656f8d0b034b59e34a90dd3a44cf7f0b7a49d463646412ba27185985f647b74f1fed78243e4050b477a87b13f19a0b13409ec25c72b8bb872021f4568dac2c920d1010001	\\x334e020764e17fa80b3e6eedce531fbe42b668a438e21803aacf2aa99d97f0e159b452539ddbdabebc0929f966cce873d3cfd2faa0b06ad9ed6ad9a457839901	1658770319000000	1659375119000000	1722447119000000	1817055119000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
305	\\xd83a336a4270f770fdcec90af9d609b06dd0b00520c36d403400b0a4db994fd594d4140830bce477f2334fd97c226521f4e87f69395ed843c07415a0cb5ad30d	1	0	\\x000000010000000000800003adc41944963e1a29ff810023aa2f8bad05dba596c936ff752e82b67228bca574fdb554f2b19bbbe3a12b7a6e7fce61bdda09568c8c67c9ab54f761b83970b4a1a44743fef3419622570ec2f8312f3a62d581697dc66fb4785a914ebcb1439759bb4041ec5c098cc82a755a0c2c7eb9873da1e40dd5625ed945666f711632e8a7010001	\\x2bcd86f16a27be5f99752e2a58db48e599038ce6809eecaa615c2cbb57b59b968ad9eb70e8519d3837ab1b3635c8e291ea6ace81dfdcd967c4a25e198b12e50a	1670255819000000	1670860619000000	1733932619000000	1828540619000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
306	\\xda16bff8c0283942163464d324816260b55de0cdb3e1e58286c55fa20a4546389166d6f5ad382caa9c078a33ace3888969b1d1fae465298b61399551a1489fd9	1	0	\\x000000010000000000800003cf5d5410d81ffbba526f11946e1c65495c83fa1dfbccfc9983d5ce3754dd50a4553630f542c14125c909dc34f21f5916ff9b370012bc3145c130d1ce7d09ff83c232f30952da458a999811a65b9ebf594af0193cdb416b2871116e38590557a8fb24d237d3b8d4cf8e50bf149edb80bb9d2798778a18f27e44eec9bcbb134113010001	\\x2b621713b32740fcd96704116ad17aab88abee832c92c4642f525ffd596431d6ba6c08bcadc75ed9eca31a21d21b668371026c416c6b80a4d045e2b975fc2b09	1661792819000000	1662397619000000	1725469619000000	1820077619000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
307	\\xdc4aea9eaf38aebed2e2d479392b62f54ca29fe0e8e30840eea6887e776cd6a0c065754b4eb85e65074e71fe32297c1f3378251b2a93353e62344c65f4dc3a6e	1	0	\\x000000010000000000800003b9a959390f0a6ea9ac831772cd8f77a567ae5ec5c3097f59532ef67be96a4c7ea5ca68b28ff870230b771d1aee4e7902f1d030dc7d205f9b28bb6fafac56dc65ecc49097bb9696570f7196c3e2acd720e50417380bd5fc9f3984084ee3d87b97092b46cdfefe22114cb5d6d3f4930fdbbc02a68649e8a0bdbf1f3c47813ec713010001	\\xb190a33bbf499aebc2dadb0419458d61b60e7996671fed580c0c9f5de715c197c097f8eb4600929c5bd26102ad67fc4a472c113edb9bf122751c67feea25100e	1667837819000000	1668442619000000	1731514619000000	1826122619000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
308	\\xdefa16491d00b2fd8d5749e9f707ba5572ce22becf24f6d281cb421e098a53dfc06b05111e685e4e5ec454040189d020d8048a5c050a443dc1bcac1a0eb3f383	1	0	\\x000000010000000000800003df1f99102e80884b5079429a20c7c887ccdd0a147947ca3c2028ae9d031ad4601c5bc9da3762ee99241137fdbd09783c3455f7e37687bdfe5811b35017bb250b029ae9f42d346924cc1f91dbbfa511586d83e1ccdf9d0d2434fd6b9bcecc7b48f010421d58a09fe0b9a155c053d9d5d35f6354772f212ceb56e29f4c735c4385010001	\\x0c44a2c8b3bf7f9f78802e39ba094ec3b39efb7200979dc3e4006d248d8c046cb62e686fc322220842521aa969dda5c5cfbc757ac2189c38d6a8ba15437b540d	1665419819000000	1666024619000000	1729096619000000	1823704619000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
309	\\xdfcee49d03108993d27b72ec87f1fa4c86e9355b4bd17d659fa0dcfe80e1a7f24a1075059e75d2a6bc5a35283cbf132cb827efa8015aceded7ebe65f49b6883f	1	0	\\x000000010000000000800003bfb37e852826bcd27a1db4419e0ae2efa5f26e4a211d1b4d66cb99c129e4f2ae2428da907b3aa5d6a4a4ede9b02c08ce724d8711fcd60f08a77dca58a5a7ef37b8ba459159b5d4dc7f98035dca6c6ce8f4bfc0b1e2a8960ed8cdcb588539d81a9ce6a17284b6d803523f182549a127110b24b5326650a7441349afd20761b6bd010001	\\x7ee4c1cb3a7d2ea412811561763198d8daa48a128ad8a501e4788f22d3a858e04481991e7686aa98b6f825571bd3bc4d966f7d689ff536b97a03f9ff5eb05709	1675696319000000	1676301119000000	1739373119000000	1833981119000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
310	\\xe0ae8045db5fee329e26dc10d9bd7b51ced3e756837e60a7964c53def68110a5026f12f1c24cd5f8f6dbcaf5744fd97d1d662dd14c227978a7891fca6a8c3d42	1	0	\\x000000010000000000800003aaef47f46e033c235e23199958fc54ce168a89a9376d3903629b49af4cc15550c7c737a0e3f18e84c367b79d5978fc87750b752170bd102574642c621db1f79d0f7340ad4dd76a428aedb5ec8fde4ea5e391b7b93d7b77ac9d3fec6f60c2281ce3db7d648fba247596542aba1371b4bc780195390381dd19bfd8efa17fc94b43010001	\\x54a08fd12d70dfbc000d4cd0580a0fa3bd994e5c44367f0d8edb1af40d0d4b5cfdaf011d67dec954b4f013483c9dab5488047f25816892cc60aee11733132c01	1669651319000000	1670256119000000	1733328119000000	1827936119000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
311	\\xe1b641206e38d07238d70a48cd2d2da84ff1714cb6b567af7dc84674cbc81dd7ba932bb4581aff433377e1b0c8040bad1ce1c35436e2ca571da0de731fa1f9bc	1	0	\\x000000010000000000800003df400f9bb9ae8183993fbbd4e3f9cb5476733a070423eb61c6b0aedc1662c3320375d1aa5a7cf00795ab9891fba94bd37c3cec179c03a433ebd15947ce77535cc7940c61d17f1de0b9283c7bba43372074c886585cbb988cff0c26ee3b92ee6b04433ada451bf3e592be36c7893e278f6dc1a92ffdc64abe6986a1f8c3e87059010001	\\x8bbd201fdc093846fbf09792b53ff48224e9688858b9c76728e7b410ecddc4d5329a1777a784fb9761c0fcd90bb4954a4ec043d29c2e36519e48f86f14693105	1675091819000000	1675696619000000	1738768619000000	1833376619000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
312	\\xe25aa621b50d6c0a92eb58908bbeef6a600128bf41af6454198d057df8feced2d41e740a3b386e5bcbb1367d497d5903c8d47498e6f9bc8bf65fde49c7846d9c	1	0	\\x000000010000000000800003b2b3af39488da837bc45ca9d996c45ec25aa05efb54a2f204c21600a8e00e69bcc894f18144861833fcf60f213d0b4ebe23832eb4ad7fd53f32e0f29b075a6ed17253e5ad747d7ece442312074423e27d7e3a5b165a355ec1684f0f00ddb21998a57d11b9abe7c2a842c7b806847aa1f420f8a6d4f705715438a6b5fd2a8ef21010001	\\xf701c27fe524332325dc5eb52d890060384956870705a7f85b58d885e3947eeb2aa9f5109b7a02e373e8efeaac1b16d4eda07e9c27494c7590812758e68b680f	1682345819000000	1682950619000000	1746022619000000	1840630619000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
313	\\xe9826842488b0e14a74a5de84d9a013efc0f18e1e4992a96c12fa7d4422cd2e417ca7c5315d744e75426106411d19909893f75df699df22d117719498e634723	1	0	\\x000000010000000000800003e1c27e8d030d5d109d6bc27709cd4bc0ed05adb8bc64a50bfa37d69a457e927484fb9065e1eee4f140b12f0633aed7b660ac9aff0ac2e4c7a5c8ecb388cda47f4d043ae6b01ba43505cbedb76efda274666bf8e28f3ecb1d5a30dbd994bc48ca668d2cb4329ba047108e6daeb52e137be06c568090f7b83ae1cc6469fa059079010001	\\x9f918c9cf3f88898d583fccd2b3aad40296ce75c7a70f1d5cef626629f9cf2ab22abd92bc258486874006c5623f23306e59a11042716493164485fe1e6133d03	1669046819000000	1669651619000000	1732723619000000	1827331619000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
314	\\xeb620dc7f0fad4be77ee8daac4bef8519bf3232f82d04d0009404b44132bf9cda8651a5c8a87e33c8c06b1181706053ea360536662b66bafee68a28c8cb134c2	1	0	\\x000000010000000000800003c415069241d013a9ae37155ece69e5347ab2f4f85c97338cea1f99c9448e5a1a5220229087a9dc42ace5716c4d99c977d6f4d9adbc8a700a07ffbeac1c28ee5a4d66be3e53232e9edd546c9491d87a5a148cabf522832386ef45977fd050e58cc6381412d815f842f6f66e7761eda58f762cd2fa9f67f34d6302b5bfad4d817f010001	\\x09539a98017a5435fdda257c738193c83ae69fcda6280dbf1f5d553eb121964d4b868e2a8e98711509bca35860b497364ff5d67534eb42838d52c29e7f951302	1673278319000000	1673883119000000	1736955119000000	1831563119000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
315	\\xebd6330ab260849cfdfac777989b5936de69ec25cb2d27560210d0872aee87dcce263792da29f1a649e72216bed324f85fa30e3612f1e6ce3d9652050bbcd858	1	0	\\x000000010000000000800003b3e034294baa150178565ac9cebece0450320de80f6f45219a0c0dd7cde6d46eedc38b4430c8a1b1d3c2e7ab0ca55382a77af3a329d334b42cc5f937968c1aba1cc4143b1a28d23ac44d4a58dbb0b1833b40b2dc2d2ba2daea113cf954a4c0f42772f56a856fcc0c2927dfce9c7e8503e1d37c965fa3971bff9d0d113093a26f010001	\\xcb4365663ac0215a23afed4acb829d0763e94029d226fc0db8523e307b547051c6a30d81af1083029edefe7cc3b589deeeb9840b6390341c4877a41ef767ab05	1672069319000000	1672674119000000	1735746119000000	1830354119000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
316	\\xecee5eb0766a33614a550915d6c443986f4059e92ce5100caf9488eca0eefbffde261fe078b2c06d35fc72dc9f42a9e36c988ce8dca461dd23b21cffe0812dc9	1	0	\\x000000010000000000800003c77808d2e0e55aff4805aeda24acbb9c7690bfc46e52cc82d6b68886d3b3718ef81b67aaeba4c75412018ddb777319981461fb34e0cab54d5f8caa72793c249422d5dbb37544b8e641afb1e5fb38c9508eaefa40933dd34d27f1fe96e02ab657843ac1646ffd0cf1fe86ee2320c9b5c33cedb8d4b9cb0d9734c22bd631ba45c3010001	\\x4e96be1ce571aad53dead5b8545b16b3a04098a6321e2c262fc176e1877d9f1ac481831acb42facf308596e1140d51cad7ec973db78bed227228423a9e02e803	1679323319000000	1679928119000000	1743000119000000	1837608119000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
317	\\xef0accdd206d342d2ada1cd09a7e9a18c60a5cece41428855c0e8390837bdbf277ce5df3a7226973e87f270b6dcf2876086f1417133d48b2b0662ab3b3a091d4	1	0	\\x000000010000000000800003ca07357d5a7e90490082bec7d1511def81eeabbd94b1e2dfaa4496f01b4f216ee3bd2446e445af292f7f402da70bda19b1f76cfa4bf3f922183d024504e554dec32ff59a88c9d274942fbc68d9641af313a3879b3571ee03d9b4a11e1aa76e525ce14dd434eb55b004083062f01001ab02885fa81b0c39e94dea7923cd197137010001	\\x418f8b0b371891ad1d0fc00a5d9449d20c4a6fd43b826a69a20ea33dc6ab9ee7979e53deccb62ca4a012f09f8c17afa0d9c462d91d7c795e90eb97ff416d7e0f	1666024319000000	1666629119000000	1729701119000000	1824309119000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
318	\\xf2aac63ffb6426719842cfcc52b07603742eecee74e0dfc459519dfac8af14093007ed7df5362fd8ee75eecdd4bb1fa4e741cdce47a159093375c974d1aa2462	1	0	\\x0000000100000000008000039afeefea234e8d08d6417d868cff8ee4a591bc775a78ad4e1627b812ca0cf6896dc71ce74e2f924422d2282d7da19120fca5fb89944de4dadd92dba079a63835c9359dea90a2bbfb8d6855b61d55feb85482ca05ac8f5f248f2bfceb7ac9245ca2f88930c8c1a55cb31cc39add06a45f72380c86f0f506c93a8cc040c284c191010001	\\xf027e4493b9e0c4408e9ef9c7272588cdea24ac0c5a7098bc43db33609c87da5ad2d059eea8dcbd5600dfd3fae862ab5eec9fb039ba38e0142db11234395fa02	1682345819000000	1682950619000000	1746022619000000	1840630619000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
319	\\xf2a264c9d35a81218202774b0a32df9dc024f6acef60ac70d97babdff79a86ceec72819d2502bfc82690ce1babc0af884139e2305684a4c7a0a275b2ca85dc09	1	0	\\x000000010000000000800003b60f6115fe811c31f382e8f445f6238fd9ba902ab88b31453ee49a69db88639b2b89c2589d11d3183df5535e06c85184b23ed8cdfb4d7c1419e8dd0c33e8eb35ac2bc98a2a255231b9c3036795666e02683d4fad1726d2be896fef2df1ad84e29e11108b1b365e6fff047de9afb23bdb26ed98a6d5019c578a7c80a7b22a24ad010001	\\x0507daf7abf6180e7c29e3943bd732590ef9f96582daee138712f8430869c56d7db86704a88cc59b6a9f9598a88a355b15737333a6cdae2f690beae0eb1f4b02	1667837819000000	1668442619000000	1731514619000000	1826122619000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
320	\\xf2fabfe849cb8dd16a3eed085dc72d9bde8d6635c09eab3801303116a7a053364e58daadf8763cdb98019a377ea483c7ef454775ee46b8e22624ba1224e1d902	1	0	\\x000000010000000000800003a3eec4fd1328ae6b50477e9d229d93a3bb15231afafcc583d953862769bd80f1e3f915ada1395c68fb6264c25832837cad44a32eafe071312283cb8fecef7f9d76779b8eefc5ac516004792625ee9a7b84e1df096de7c52abb0899471b4e61c60d7db9fb1d089be5fdce70deb8f16f50efcc143b92231d665750587189bb0081010001	\\x03e3c2d3d3f76ce5b38a7f02cb3664fa031dc53ff0e96e24e92a0c07b5390160177f638ff8d7b16a7599dab71cd696c40c7d2ee5cf2a7db6fe1cac337915bb0d	1673882819000000	1674487619000000	1737559619000000	1832167619000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
321	\\xf9169b68e69183209db4b36582fa7c11580b9fcb2c6e7da4ca6da22e6d9068cc2f1ea30961f9fcb5c1db0899aa1099bff69b76ac7ef2b5bf6fffd82823c7a428	1	0	\\x000000010000000000800003c3f64966b6bbf4eb0821c5398ea3ce6b839536993254b9a15f24b4032c2350a166232563e65bd11e74910630867ddd463c90620adcde7689a02932e20fc69df49bdf59934724480afb0ff558e74159d93a44b7d7c3c4f1364b5aa3466c77648e5de88d1ba93fa570fcda1c2705ad625ad06530d69ef030495f48e5ca03bc6ec9010001	\\x98328d3edd84c0fe14c1ac2b70af6e4e307d8b2a55c26b4fc900773e2500a606b894ae9ce96608ab3fe20afc0239717b93a510d2379719ca0b5fa5e88d38e90e	1667837819000000	1668442619000000	1731514619000000	1826122619000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
322	\\xfbeaa79e63398b1f907379dfb576a95eaaef3f58aa97c2327fbae5a3b14a3e2cdb6006a96a93bab5980d01c2c0aa1cb9a1e97f1a4d1d762e570041a169210d89	1	0	\\x000000010000000000800003a514374670a4a69a66fa433176ea5b9dc832e0d32bfba691dabdb277fffd67b31fbe50717a1f345bd6433038a44bfd70f5d3f10534cbbf04d03f7f6487ad88d34f2d4fc1d2f1b087e6e95ac822afbd354ee95c88428f694bec5b837b705b8e653a0040ed799195ec819fa2e9c3fe65aab5b591719fe88b4d540d1ab114f21287010001	\\xed8d3a6d3185588c00832a06102525ce2ad58c4521800afb91bc4298aaaf686990aeda94561ba1878eaa42017b59e39a4a1951e6616a17ae7596b143da200b03	1668442319000000	1669047119000000	1732119119000000	1826727119000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
323	\\xfd567e8073169ef94149a62a211afeebb3637561a8323362683cff3d3869c020aa30ec07fab06e1825bfbbde7b8e81e6e8b587e15da081bc43c68d3902527ef2	1	0	\\x000000010000000000800003c05f73ce2e092f5a7930c2e9104e01404f973742028082cbf82ec4b02df1603e306e5a7eaa272303da2040944a525e0a4e901c0ef9ca4a4f9beda2c57be6f1a9aaf8514543133f2f2311112e7eabf8a6167af2bb9f90b8a3cb3c07fdd5175cec322bb47dbde3d605f572ccfa5482fd7362ae9cce202e8e8fd92d6a0a8190fb4b010001	\\x0ec0f0d734066e62d51fb6ae2b6b051964f66f7869ac98d06800ceb0ff0ddecbf6c053debcf69f1e2ae7e36e77bd5f2fa1ab2c8a4f5ee87dbc032e3b1a66270a	1653934319000000	1654539119000000	1717611119000000	1812219119000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
324	\\xfe6e894bc1b603c7b8fa44204c8facf7a084973779d0bfc643759550bc9f7611c706991fb1b1c0361f6b12270b273c50a2248712991d449184acfa6fd08806b4	1	0	\\x000000010000000000800003d2e299b5245ba6a89468142bf3566d8c855881157dae14f0b6a91caeb8f2907fbe2a51a31a1d173e0639f443d9e2cbfcaf25bd12e1494cd30edaaf8708084a789421680490006ee8c1fb49d783bd1c3ed4a120e479677a86536bcaea73dd795118ea8cd2da786608fc39d26f4345f6af9c2f71bd6cf71d5e9d2e880b63781f2d010001	\\xab57a605ecc44c028e927b33503a0c40c75c63e5e96b096f5263cb5237f0f483ee9c8c28d35d1c3fbcece2a50526a37a9c3b1321946b80b6df4c9b3c5f215a0e	1672673819000000	1673278619000000	1736350619000000	1830958619000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
325	\\xff661c7df8f7d08ae80b7867d1de5b1584cdc95db0e1164c5f370524e0dc4b16efe122e3843adb69fc5995863b6439cce4cb0f060ffc2c6e5f23576acec8a44d	1	0	\\x000000010000000000800003bccbab6980339fd54c42a94bf1a090980808a32a30cc0e64363e89ddd43ef2e4e45d3a45fa0cf5ea364a05c253a65848b4eb67fc8763715d9307b5cef4fe25326d97a77f5354a8a32e55e16738eca5b79d027103ac339aa487b675ad2f4c1a67c5296bf13da0c867092b094ecf9ea2f1637f3ae3e4f98671806e372fb852652f010001	\\x9c4eb9a5a2dfd1ee573e8c2e3295353be92ba7d69fd8d122806293e6e6aada75919f87a2ea599a9af66c748896555b1262f6b3e450acf853328a6426893a3608	1667233319000000	1667838119000000	1730910119000000	1825518119000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
326	\\xff0a6a8bce010f1590fe04929e9ff14c6f28ef65ba34882d43db2d99e0b96c16d4b7e39793081ed4f4cb4d217dd8db92332924f72033c7d6ce42183392205b63	1	0	\\x000000010000000000800003cf494d4f70ab0e830a16d7ac0fff2f3504cf833a51322df36f9bef61d2ab53d63a742397cb8a6c6a6f94f5d6aba896a21109d2fa9f65a5a029b92b65dedbaf7c617c9f084c2b5d53e0b5303bfcfa7046bcfb901fd67ad9d1200161541342565b98bf4161904a9e2e646598c3c06ad28cc857211f9953ae3edee4ce821cb58ed5010001	\\xa3153be029f1715bbbb70c69f69bf346aeb06d051f8168a46c0d77dbfec9028ccc9a39b3b30a27f1a8650aedcd5d4228395508733eab0c7f239a24128069ca0c	1652120819000000	1652725619000000	1715797619000000	1810405619000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
327	\\x004f5438fdfdb96647c3e3a8f73e921c139dd76aec08cfac950a42915e72cb44435d33677f6c45e269441dcf818495d61f8c47b76459d05535fbba9a9eeecb1b	1	0	\\x000000010000000000800003cd146b6a78ca28dc93c360cc9395086375b379bbdde052baddc70b96b3b0810d8170c780f93fd120a81926ccaca462b2fc78c26ed6b4159f81968ed663500e18810e01c4e666b93c9c8c2ece35175259a7fa617a90664fc55294b5992c04c9e241395f51fcf2562f66c937fc39dbebd4517d094a8d42cceacfb75a2baa040ee5010001	\\xdcc1ec7c894ba1103876cd45f97947415f74b424922b09a0c6ed5dfb7aee5a9501fa2b43e9aa7c6ecff07d1f26e3c37bd39bdb6355c3e409e8394dd554bbb009	1676905319000000	1677510119000000	1740582119000000	1835190119000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
328	\\x0517bb95b448fc3bce9d65aa441a33f9edf06bcc074a44780e8d68051310013d23becc5a30a17327a9f3e3d063a7f26547e33de5330ec624fd07b39aa5d0a2df	1	0	\\x000000010000000000800003e2870ea61ae660d75fa7bafe3fcfdd6fc4e659ec15f76beaa207b8b9714e6b8b8f1ee69ea2af2bb7fc7cfb00e3e4a9950cfea035033bc720a30540d5208bb90f450bd2d3b95daf11694d56356b2340ba2a693ce8d8462ac5a1f519e4c1323897a5fd965212288fb62213b17e68eb5b554485f55f81186552f24b1d5bb183a581010001	\\xe2dc8116fe67a6378323783fc4ec55c3bcd1fbeb0a220689a7f987228789a7b8c896656bcf00ec24e8ef53b0653600307199bb6f9059c926a7d13f9add92d801	1659374819000000	1659979619000000	1723051619000000	1817659619000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
329	\\x06abd5184f07a2886f95cfe46a18860ff98789114c6ddfbc6c798c818afac8d8ba712cf941049e103308f14cb1a9f71fa53edb5fe6587ec4fdd0ffb21bac8a60	1	0	\\x000000010000000000800003cdd17a399ce51c8553661d1ed2002a37138d87d7372df312184f33067cf0ae09e285ebb68b2dcd59f37954732d73c2b3fe2b7457b81c0b3c1ba146c77284f5e32778c1d2846a8cbef468586a63af46041bceee1a2809361da66e109eac9a9e70a20da3eb968b5153f38b3826a44cf9c115712d6348fb4d0b940583151fe6480f010001	\\x9052d729f14aec93d3e6610218bbd48ca52807c0eb7ae720facd4ebc45236690ba09f2431101e5d480838ba00e5c58f0c70b34049819cb5069ba83f0f0551c02	1661792819000000	1662397619000000	1725469619000000	1820077619000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
330	\\x0693d4d65dfbf7c64f11acec3d735072fd8aae7fc27eee088dd4417ada668207ce04f257172d58ff834d613a195a61265caa9d90c192d81405357622c0b549d0	1	0	\\x000000010000000000800003c520b9915c54f4418359f46bd144d1c4d6fcb4a5c4260943872df62f8c0b4c3036f948ef7177e109b8475c8441995e6aff9f36e7d4375362f8ce9c21ea9f77c08d3ce17b38e561cf21512c91b5f83b43a96dce36fa434e58ae9d7e03019a9d4e06217d08535ed4910a43f3e7b42a372a2fea821d5cd6310c7a08abe028e903e1010001	\\x726918bdecea8642f7d6966b775976a5eda276fbbc24376106eec77746be7106fea21eb59e66c0b9ff63dc8503671b02bb538839acc7fcfedc703958f8029d0d	1664210819000000	1664815619000000	1727887619000000	1822495619000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
331	\\x07f72dfd048e4d1c17ad4b6b03e25736aceb3d9e140822e2c0162871a418c857cddbc854dfa705d58df8e84989ca76eedaacf94879ba06cd25faa7a8e3343f81	1	0	\\x000000010000000000800003d5c0fb1ef348e892643f145080637c3df23be746e90233fe03b41fcbba66c1a0bf1ed8c44ebb74ba267978d0dabd06aff5986dc0fa86e88e61a1376f8157193837804ca1770c2aa6cbcbad84330a81505736adeda8bbfa0f9919a8f98a7f4991717e43208aa41ed22d092f446ee801f614b4f48d89938ab164c7a8ba32cddf6f010001	\\x20da8d06845901aab6882f3ba26cc7a29e8d29a031395d86b078253d8cd236d53b7ba1372898773cf6a4e7068f8a22145bca58dd492a3264698d3672e3d0140b	1659979319000000	1660584119000000	1723656119000000	1818264119000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
332	\\x07338f495d6f6405ad06b9e30012f376676956e921078c4342f7125a321ff49cde51c234dba8a7475f17bade420860506a06d928bf6678242ff674ea967c5067	1	0	\\x000000010000000000800003ddd35bcee34426de809d037515c82a7fee817082d61498af1546de56335ced2384260bca8801320f40b7b237a1a8fb986cc223126b46a684d42f553a0af7b4eba57dec4a34c5bafb0e67e69b8c102e9e3bb254ced5cebef30d009dc265e23d1b05a4c63d9a54fa33d79a9fc4810b18594d625d9155e51222747486440e4fa6df010001	\\xa2803d3074bc2b8dac4382cceef1798fbd625b69820c4c115abbc03e76f80cadb543d2d58bad5cf5939bc63ae352a856414267fd0dc0fe086a14ccb423926b07	1679323319000000	1679928119000000	1743000119000000	1837608119000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
333	\\x085722428e87df5d693b357677a6379cf66853416b002d435cca34866754f5e6a19b2a848e98cc4138c017c33c227ffd01eb5230ff32463f8e728a7a8dc5acba	1	0	\\x000000010000000000800003b811e8a2f71d185aff315f6ad70986fa7abbc9970a8e2e7118095258a421202358ca6fa0c732809ef78c99b39c407ce453878ef857335730ab581bf07c9127b4defafb3c303a14be7df7e2db3ad1220bace50bf6b7305253de77c64c39ce2a8fb640064be25c5694a5ef57c5fbdeb27841f6b8da11855e24c523bbd135a41715010001	\\x446536cbc0d999e41fdbeae4f5204ec63e0c6f9947bc2658f2480749d33c8151154d185425dd355803cbd43097969e8394f13e1d0887a9fbd089e2a55fd6bf0e	1662397319000000	1663002119000000	1726074119000000	1820682119000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
334	\\x0bf33f0672bccc8718a12bbdc98e7ca3c5bda8598c9467fe9263b1ef4949991df4f4c172cf6d1b55319cb432cae14b479a5225c817830b2ce54f4c257963a4cf	1	0	\\x000000010000000000800003e8b05b105cb144229128d45c33d2bc253d9f5177c40f2570495f2ce0f7ef649838229b1857685b927972078993dd6ed21693d4d63f5b7de9338074519b8e5c18a4e24ce64c43fa8c7e87ee20f476e567f07caa2c690eea12aa709506f2dbc8e8ae012709edf2dbfd5b7c021d437078294b6e9c169ea48adf20ff97ef9ac311bb010001	\\xe8e32d15c099a93504ba5560d89ede884dd6baa3267a216d38dc003ad4bbebc2a8504cda787f0f138e674cea3270523b43a8efdb270f3d37b53d30f658761d0f	1681136819000000	1681741619000000	1744813619000000	1839421619000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
335	\\x0eb799dc73be225ed9942a0a532cb59d9fe3c5d88af660cf6a57d4271d13dec0c04700b03ecac6a213761d435f3571e7729f3b28076d6c06e2b5c3eda693c893	1	0	\\x000000010000000000800003d99fd9b3401086f5223dfa5979e027f60a3203d33bd327b610fe9ef607d7e70bbdb8469dcc11b72c8e993e20264f547f09525cd3ed3d456e602bacac277ff2c5ccf66f221b9a6681d9be8afabe9b8dedfcc6748cfb98a4e3ca2f421dd93d97bd198aecf029124a84b7a723ec8364b9545328520a199871b0be44d00985e1cd23010001	\\xc291b57145816a19ba7f3a4add326ee769323ab38f675066f0f344682fbea795dba79e88f5dfab4ea344910b70f39b8ec8bb78f28b94f90e8a6c912b11fe7d0f	1681136819000000	1681741619000000	1744813619000000	1839421619000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
336	\\x0f43ad248e7460eb6228e887cbec70f48381d8252638a384a34383f40d7b0d5ea1614b78ab3b4822cf32ba7cd5de052d3c73e0d66cafb802888dff9cabf29510	1	0	\\x000000010000000000800003b9f5202b423e434e7468b49aaa234a5a375571504094f991d464b58afcc1110ebc0384903adfd76d01099aefc1a05662be7f39921aec4afdac52a94bd8cf4242d65e5b7d6919493c762c40040a67417b9c5c62fdf80a50d8dd65ca3fafa292fa47ac988ed30ff1c4fceca71d4a47dcb65252552f9b12a6f375214dd67bbd45d3010001	\\x4fb94d02ebc5c0cbe66e1aa52683d5c175e1d5a320953a69f66c82b012b52977f583e8ceb553294db51b7cf039eb186def4eb9c0ed305c67797165e19275d50f	1653934319000000	1654539119000000	1717611119000000	1812219119000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
337	\\x0f4fb2115855ce441054018a0a4c35c19b798f6c55c326caae17171721827d159f22f7288916bb24f0f638299c176c4db3ee596a83567497cf6f20023e6f7c12	1	0	\\x000000010000000000800003cce31f67f1df36b73859dd7d8dab592edcc53ec1d074d10118ae4defb1efc48cb1c0d78d3f67c1f06e46b7ec86e5ec357ec6a66b029a5a2f6e0a7b505eeac9819e11e383fb622cfbfb70149c4476e343366785a829a6b6754dbdb4c94c7261f8c10f81e91867199df332d97f4ca707cae6b1c95bcf140dc7d8c44dc8f784d683010001	\\x5ee1e33702940e4ff7ab97a9ef89c1be033d91f63dc54386cf63f2724c30ff8f4e5ff1b0a854275a41d23b45d20015827451ed316f31e28a306c13db71312f0e	1679323319000000	1679928119000000	1743000119000000	1837608119000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
338	\\x0f238369fd0de904c21fb6086b946b62e4bb9e10aff8bfea09895f9440f3bc3b3a0afc08a8b659f6079d5a99da6ef114553951c841db53adf9fe0155b12efd95	1	0	\\x000000010000000000800003a3db42915b75a0d2a90b46064bbd172e4afda48ca9aa2e556896f084e67a34d7dcc63c059210c65effff2310fe2c5f1e8bd8332373cf69f6819cc34bc7ffaba82779386feb388853b61221af48378ca148c2ef1f70112ae38f5b53f831b123f5828a2694c2a78a30a855541ce2b3d14e05c1565a32738b92980a556e67aaa819010001	\\x90819eded0ead98b362cb2bd97c6aba98a86cc7f253836e7412f44e2e3054f22aae61b3dc8fc03baf5f9a56e48c8f0deaaabec4cdf4bae5d4f9c14abb268db0c	1660583819000000	1661188619000000	1724260619000000	1818868619000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
339	\\x14e770d1df2cdfe7739dd1029ab9e8f58de17118a98c936545a8784c10dc2aca8dff89ef950340837bf0e5378620e9c9e55a059327be9f15670c2c715e6d5bab	1	0	\\x000000010000000000800003d86fcf33a5de91c9900186e06708e9345dada0ff3ed8bdeb08e253c075ed7e7d50bc77823f6938c6b55951f17aa6d159048841101ed5724bd64664213de55d980f5e55b350894278997f9d3b0d4ad70fca8deca54b8d557b0fa45b36b1c91542ec1c56ca417724063e138969a9ca14022c66688b060045d9db9546dc661d1e79010001	\\x61796c9a8a0032c0b6d1d3f9f6cfc28cae59963ff48bfb31bb019328d5107cf107607bf14450ebe3fdad9087a7d23393cdaf4b3e2e1c9710f4b4da08daaae909	1662397319000000	1663002119000000	1726074119000000	1820682119000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
340	\\x1887ce8365c03ec11a1a80d4b5cf16cf5620b7447661e3d6043dbc644184ae440a78b6eada51d2e0938181f5d8d207372cebabce3e74a906f53af710848161a1	1	0	\\x000000010000000000800003e2c69c837f9f350bd4f0effc6e8d1ed34deeb4c2665de3de258ee36356433418d8a42cf6c77844614f29ad9885c75b86a9157769d8ddec398f55f133afc7d338932f892b8d539e6b9bfa62a3f4681caa780c465b0ab8692d3acea966602a1d5eb1da3463c02e96bcd759067a8e56026e86ae56cf24ebdcc219cb105944ef757d010001	\\x8a9ac57df6bfc0196719fcb87032287689ab39aabe136dbc2d4789526721494411cde7aec2c2e86fba627ab0d32fbd2d060b858e379ae01e5036f577b3b33a02	1652120819000000	1652725619000000	1715797619000000	1810405619000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
341	\\x19af3529d839a25b76367e2de040efc55564a9786073fecc17a50f2092e5099391ec83afb34abc8e4c75673c85a61e834b1af8de90e3c0bbf391000b76a96937	1	0	\\x000000010000000000800003bc8d9efbbd2a7388431488a5d723898fb4bf22243da1cefdae888d82cf61a299ea375be471e485b92e318cad0211d3d45bda03e3f67bb700542391a7ea6d3816db3d2921bebfbf909d83105e2decfe7494fbe572898ff6777fde968812321a9b7b1884358dafb9db6e8adf59ecaa260f41c8f72941efa8406285ab5e0b352cf7010001	\\x0a1a5f3b3ad42fed6ffd01957ada44f02a11d7dfe10c0bff5a305ccdf251c3f12bf010408d33222dfdc11af573297642c8e23d5877e2665d8dde3fd9a13e8709	1676300819000000	1676905619000000	1739977619000000	1834585619000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
342	\\x195f4d5c753d107d9f3b4f6fd44066e6c08a12c850e52d677054f99467069fd23bad0c4943c824e7d0f426f4616146622caba38362dc0ded4c0a0c87b6d44a30	1	0	\\x000000010000000000800003e027a44fd75a888b37de4239882ccdc3846265648ce66118fffde7f85ad3c8d0097163fc1ac2f2ef63a0db76d58d06fa4c7721f1522eabf6249b561ea814d43da12697073cab65d351e0e128a9a6e04410b89bc99bc97ba0c9d9b5fa8107012d5570f12754c50b93bf9dfecd5d8fa3dd6e2d6b6ae21250a8b868fba85079451d010001	\\xd59df3db4498d86c279621b99ed1bce54e6a385ed55fce6ca3be9bb21b34b18ac5b3418c5b18dfd9062e6662c3f21f4693fd113b5510fe63dde7aecf1301c408	1678114319000000	1678719119000000	1741791119000000	1836399119000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
343	\\x1a07a3b82991c27db73e21996b73fa680237892bbb92cbcdcba5cdbb83ce1df2884adfb9da33b1bfd61822c11d4d22416bc20846f0c02c1d9a2275e417d78972	1	0	\\x000000010000000000800003d042c769325c87d09449ca094aa51f59ce80b08302ddce3d5130824f112bc9c78cf5a250c95aee5e044587d6955ef62c657af1efb96060d35a1868ed6be93c43a30ac815f5571351ca05e93352c63bfac6c005e58c43427e1b56cfff4481fa13cf1b6b6819c6a3119bad38d214d5da9a156aac8472c57d6daf45ddd404a83485010001	\\x49fab92ab492cd42341657ec353d926fa59d1232a15e313b364a418ca00b54ac9c26825bffa3a6840e5549a2dfea82530550b9a602e32cff263566987e41c90d	1682345819000000	1682950619000000	1746022619000000	1840630619000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
344	\\x27df0a9c6483aa9bfdc151c86c44d66622479af1d181a578a8274344ba6c8a5f07946025caadeb891838f16cc7ae583e4fb6568f2603fd18cc5999eda335e640	1	0	\\x000000010000000000800003d872a99a33c4b484e196b0aa2f133f2f2a952623dfaae4596a29f10b05b0dc8f7e9d9dc3b48db2ad74ae31dfa1ec249053905343c1877a951a8a1768dbfb8e11cfe7ce589eeec2f1bf4a996227482ed72c0cdc8411afbf4e1bc015fcb1148cf32ee6952dfdb6827478d807eb7572c328a3c271e033a4990225e596113178849f010001	\\x445d84c22c2b040b1a4fe36bfb0e72a0edf211a7c1265936097c16d39ae1fd155d9d2fd7594b1eaac1b26deb83d4879f484de0574d45d37a8317e12d30f08508	1672069319000000	1672674119000000	1735746119000000	1830354119000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
345	\\x27b3b6aac7fdd70606ad1dccc9a91a12c091d8fb4844b5154cfe35cb08fadb5d773053c714058303331e2b4cbf1c179b734862729e485c690c7c5b5d409fe26b	1	0	\\x000000010000000000800003c82f6f03375775722fa525465f61a24279652bb51d8944a6377dd6ef78ae49020c4b4f068128ab8c28d64e1137f8238a64260e5f031fb99d770a7a132dc4522087fe13df0868dc9076a69e7bedc590ae9a65862af6007d64011fe9d9e373aa0f91b36516f6fbf8ab1e889d140079bb6bc9f8176046352a459b32fb5cd6c34f4d010001	\\x60ed05afc65142b2d6703c22ffa23695903083bc793fd82feb327cf94bc68f0b91165f015fe6a5f8114415cafdd1e009c4bdd3d469a1b7808ccd19f636520f02	1652725319000000	1653330119000000	1716402119000000	1811010119000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
346	\\x294f139ebbeecf724286d46031a300c74dc91190d953bd9312ca2b102a024b106b3cfb9b3fc8cae153c29266ac6043c92eecd028ad8b5f260b9fdf842df26b6d	1	0	\\x000000010000000000800003b1422061071a7e30822997864a42b72d045ef405cce0f58b6a5b8c3973db3c48dd8576e46cd5bad7d6514c869866528840366aefb98122a632c2a80d8134d4e5037c0212c70552c72b5de1cb412bc5a95d21eb5c7eab94aeba01c2c956f3d3a10e2a71085e7735d458b750f0b534200369a22469c5872a3622478359f7e2f611010001	\\xa347bd294d4c16d5080e2e7a04744644e6d10316d20b9f0a60104bf1d3c0870e0a5ea3ff7b7c32648f2cf3fa516cc6aceb5aaabfe3eca50f73e00530743c2c0b	1681136819000000	1681741619000000	1744813619000000	1839421619000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
347	\\x2caf2550784b7c2f4e86b86dbb478c1c9a136e4a64e6fce88ef0edd5774d08ebe5088743168f045ec1f849d56d0cf86e72f751fa8d5f040e77583862076c7c2b	1	0	\\x000000010000000000800003b6068f0452e74717ecafbb9fd7c17628ed69d64c524052164380ba1ecdbbbcb47c189bb2d6eca31b2fe0527f1d9c910bb9b25e34a72359429dec0fa1a02f80ae69b408dc3d05c4ed6880b26e77d3bd797b25471f5dd7b1bb9e8e32b6e61b100034c2df866474ab0c274af60af2d455e8c3436c15d153c3720930986cb62b6013010001	\\x945a1faecda718430d9fcf81b4852d715ad3e961e43c83a5b6063f99b692609bb3ffe60e674acdb319ec96f86b8bb3f6fead7692132c7134ac3be6d6a14d0d03	1674487319000000	1675092119000000	1738164119000000	1832772119000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
348	\\x2e5f298d1e69fce99d8cdb30db0cd1c119825f45d0424e10dddb7eacf5c6d0e572dcb302578be156f1255614f11e2b611afbff48fc23ec77da8267bad4033314	1	0	\\x000000010000000000800003a2e728bae16725e0290ab6e447155e159b8397fb1806a682ab0c8ef70761b6299e13fa8a96996c3d995066574cd4c1335706513084e44a2b4f444908ea3c89691eba3d82f51d29f8c670f8b6b51effcfbf7a9ae4dd008be9275ebed59cc768c59ce893c2fd28ceafc873d6214e129e21daf0ce7c0261231cc018fa02a5d879d3010001	\\xc4ef455a982b0a31348133a18c3088631d33ec6c49ddd8c71edab272601cb93eda552ec7213d3d7996d1e6b22f6cc283db3b5ea64b7c488a08c3e68408d41401	1681741319000000	1682346119000000	1745418119000000	1840026119000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
349	\\x2f776ecd0d0fe1c0634f72ac0271a8e13845b4103ff67c758e50e1e9be360733db0bf6d0d6cbff9265a40a1ce191ba782b05abc9c17e97459a4b0c4385b8ca99	1	0	\\x000000010000000000800003d33abf4f7af24f9ae70559f51fcbd7838fc3f5b0a773551e183c544e69bc476ef2b3f6dc26a295204632d79b98b64fa20f50c890bcac40e0808cad3c7f7cb6e95b2c7fc33d4ef0f0f6759ab607442e8d3a74c5835b0fb2e1a92619c03df8c3d80a221a0898c67f46646e3c9e018198265fc2323e06c30b376ac40919bddc25cb010001	\\x823ea0eb8a8a55eda7c070b9721817ad28781b41476e6222e57e1368851b01cdc1e93a956da0821f5562d3446125bd0c589ca476f3af4b891d035228cef82207	1662397319000000	1663002119000000	1726074119000000	1820682119000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
350	\\x321b20678b0938e66f1eb3de3f33c7af6c2fd898a2d0d319199039c44d52630045964df08469a25eb2f646f3c4d13fa44a3dd5d9bddb7c31e19ff0e6200ca735	1	0	\\x000000010000000000800003bdadc67e2b7d934d5339a720903cbb0f153bb9049daff59afa7592a2342cabcc71fdd731d8916c2b12ba603fdd1162156015fb242a21ed4028ab6da0b7b8f773048d2b34e99167dcb9862f22449a6a9528ade55bbddd900791703a72ab5c97f80db02a9e6de0ac119ba4688a560538f1f7bc6b1f9717e6404a5b128b8ae87373010001	\\xc5f6f7e32c39be78044ce5ee014efa6404b99cf47bd5db5f34201d1264919fb96e69bfa28908cd5ebff87d8347cab0e7cfb9f50cda4b7434876d91d6b3d41f03	1654538819000000	1655143619000000	1718215619000000	1812823619000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
351	\\x3433f04e29b5cbe68501103449a80d6b4f5681b9d60ff41835459f636272b1d513f7f732931f7abe763c8b4e691790130a2ff0a1b18511c16b5990de6a949e58	1	0	\\x000000010000000000800003bab0fb380d7c9f7fdbe049ed0c5306aa3281fbe0fa5bcace1741f264be591dd170f1fad3f36cc484b86669616f6eec6c165fa1b878df701addb5e983a1b07bf6dd059a331ec74f82778478f17f76cfd127235b2b0d8ac0ae6a32d87694104211ac4db9f0a927433d2529391d8269a2791fc8e8f69fe5f433fa127ded0e8985bb010001	\\x4bf30c1efd8839a8dfa00897b73a52721f00c00492f33eb68d9169304eb00d974666b0b823b7efc5a8faceff3af2f592b49a859962849a4f8e82d1ce92eac104	1674487319000000	1675092119000000	1738164119000000	1832772119000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
352	\\x347323943138960f7a38a7b0d76b018aa883123a3443e26978c8e55f4c848a0af5c964ce69b9c7ca32cd8a7e5398a26a856c28cf2e78fe94480d5ec79cf3cb26	1	0	\\x000000010000000000800003ae34b5722efdd3c571ac56e3f2c7681a54e7ee49ba60a2f7797a523066c3df7fd3693a3a2af6cfced2272127fe42c4364d8421a5c16bbaace6e639ad225a998a1f9fbf58b172d20118dc1009b16d8899f0200eb5b88184eedec2f2036d59013661af57dd8d9639af6b706e4158289dbca564b0f61faec55bbe96ec1433263075010001	\\xf47f73d4a6e61d6beb9bb107d24359086201125a4515970891bfae9b0e75e6475f4d20a6e45b3ac8919f01c07e92bf681fc0e77ee7edf0891aa70af72de24906	1663606319000000	1664211119000000	1727283119000000	1821891119000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
353	\\x3cab7aea0eef8006af114685e7fe229fe5cffb6b79bc22dc336dbc116f6db64bb6de20b84622eaae7d23a722c8f613b8f08515c493b7042fb24e7030561e7aa0	1	0	\\x000000010000000000800003c3c28b5355c5fd451664d0337851efa6fd41b8698f31e081437288404f50ba6c394dfd2788d4ae5dc1f60f04b4367f7b415661e7357b17cc96525d18d07a612b4243de69159d1b454b9490470b62690bcef8bfe37f45f1871b5e6145ff6a60ca5d03b6b26d10bd4e312ad509bf48273a43f6ded7a3784a9a79425a02b60d952d010001	\\x106b6ed0abd282a7f40c964143111b0f99aa1dc855d61cc7ed21e238fcd4d412879022fa06efe3f5a2e6681dcb8fb8ecfab6a2bc817f4c54892e7eb208edad09	1678114319000000	1678719119000000	1741791119000000	1836399119000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
354	\\x3d5b46babb62f54a0318c7ff8a889ecf3ee27a6ff7d5969d034c0990b3b7cf032ab9d7c8bfe93dfadce19b980116acd5a790b72d148c75b52ebc0d5ccf45635c	1	0	\\x000000010000000000800003e33c8ce4dd0b0a80cfa44c83b3a899037a115f4706e0bcaa345c313233b26522223d4bdbd03403451f89f759884c10c5231ada3724ad8a448904142e9722cba179cd23c98e8157fb73227ccff37dec5e21a4404796aeda5d95d231dedf1109f106d4a5a6096edc91b048830b87430c8238b003c545eb5cbccfa6b9d0be26d36f010001	\\x23b38443865524e6a2338d649f12ca9d349fc5d8491adcbee39cde9029103bb7df694a021de0aa36ce61305250de536a12f6f19034df3156ff86a09c6ed08608	1655747819000000	1656352619000000	1719424619000000	1814032619000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
355	\\x3ddb7eb0bcb629350b7734bf84a4bc92ef18c33a441cea27af75989df33aba401bb67947ddc9f969b1bdd01f3b09fc85ea79482d9ffdd63685935d750c46afd4	1	0	\\x000000010000000000800003b8fd58b523d06715979da9574b6eb36bea020563c761da5e2c01d02458258d1240ab46657fe58977d043ef25cfe1ba6312a43abb3325e5fcad58f99061553551d084f525f906212b8018412bc873bcbdc4564427e0f0f7f75da41d260b8dc42ffdb0b39102558ab74f092cd8d9840c9e7f7ed81d8c0543a201adaaff5b719dcf010001	\\xcfd81cb0d06bb7ae64e9d5ce75f6387a6193de41ec8631ea89127d9dcc2662e4ede413794c41beec0913205e0c4ae3dc050e51e85d90bf5ca3547f6444e8ba0f	1674487319000000	1675092119000000	1738164119000000	1832772119000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
356	\\x43137115566c2da93ee9b35772d722073565904abf58600cef6c10e83b433e3991128b48be4cae9395b426d1d8957a1fd0784c1233bbe14650ecd6ed9a2d6e4c	1	0	\\x000000010000000000800003c0977c6db35674a56526716914cfb92583ccb85d56b5ab033b1eadb03d648da8afcb2d0b92470efc8bcffa36d8835efeb2949767a55e8ed2f6ae38fea878c65497106b8abdec99d203addddc9e446fe9ea3a4c25f5cbf1f4d0c425dddcf86ad3fb09598216c2db44e088e8e4abff3e0cb83c7a82a5580b3b9865209e1f1dd7ab010001	\\xaa7b87df66e065fdd32d028f3c9396932444dbbd93d1a2d863404c509e2f82b58cd66cac86d292a1654825d19e25c78f2e2d229e18104c69ce46b9b7cf5fef0a	1655747819000000	1656352619000000	1719424619000000	1814032619000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
357	\\x4bcffdd83aebef5ecae8f9db9f8dc642f77df7e958e428984056cfd7d979edf61bc8e2dddcaaea6e13f79f71bb92e44db971a89c91e2d661b0f52d1ead2e743a	1	0	\\x000000010000000000800003cdda954072b485b407d819809a768a3ec40bc818430874afa6685c96e6928504ce8edcad762196f1115a866323d0c9d4ef7ddea83b8fa9f24c9735dc4b11d98276f02d762480c24e802b6127cac956f2093f906df0f26c06721a3cfa660743d27348a917ed78ad27c17b01a39f3a7765228a86c3f229c5a0b4af779af8086eab010001	\\xacd41ceb53fd8ee35075b00848ae1a84d6c59a64ebe9e687789628fbb1cc52658cc32b897a7812cfad2c5c788cf4a3599423fc8b595b5e0fb913d1c38892c003	1679927819000000	1680532619000000	1743604619000000	1838212619000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
358	\\x4b97c5aa95a9c79ac4d6bb971c53afebd1632697f57b31e0a3d394e1dab7fafaa1b452d9fdf8e3cca65636f76847b39eecb51cc63ff97594eea5e64001d097fa	1	0	\\x000000010000000000800003d27d236c7e52f92cc623a28cbb6cae42f5db9a4a9ebd9e06d0e74c1052e26f315274b42aa597301ecd464e39e5f06bf88b6156b8129e2f0198f37184fd693b9c484f1f5f0332fdbe97d64898b0f156495e2128b79d0135452e0f51af536affa4157b0108ce3070934607b5246c790f7bf9770918a303a58dcf38b412eb1cc52f010001	\\x5534d32b22d65ea4249b859700db8876750047b0f75ad5e405623684e280d299395ed321e8481961655b6e7c01c33de00aa76d95759e03e7d936d66bbacccc0c	1651516319000000	1652121119000000	1715193119000000	1809801119000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
359	\\x4c87b1b8969f545db1ecff6cb5a7a3ffec9f55543e12b9950721f1d77bcfa652c6a8d18fa360ad73c0f2c45fd7a609c614315e5a6d26c280f7375e4ef7587147	1	0	\\x000000010000000000800003de80956cbe2df40cb61900f58c4bec889610b6dca8f06df84d94d6dbc5cd272a55e15b8618b0abaa91a1319580e923dc7d920c2c2e5dd51cd6658898288b0336c5ec4f8c8f9a62185ce125422b90b76f277d4c253f0e9dac2a90e56c449bba58e6b890572b859287167964cc43e6ee223ffbb08a957ba03f08753fc569ee7a2b010001	\\x88ee6ab96f0b66563929da93c1d7cd579f793a0ce2aa8e52652612f21ab4e8b5b5141b71eec9953977f49ce0bf82dc73d36b158840bd5d135872ea05ca2bf309	1675696319000000	1676301119000000	1739373119000000	1833981119000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
360	\\x517789a03a92f740823902ce92c8a75085b9ae58f6404106bb716a47d4fcb5ae3d40cf671a7be1d36093c04429aa0f8b529e42ecde672c0df02d15dd0f8fc7cc	1	0	\\x000000010000000000800003ce9a450e05c185c06d1be5df11ee4265798cf9c3e3273156570d8667fbab86b5147aa3b3bb8c22db67a3ff29c9997531628ba6ccc2facb548b059c28e87216bdef86f25e7a2aaa0518e7ab8bf88ad1fee49ef33f73e98647f242790c1d8fbeed2fdd2e94aacb3ffb0ce07921d5f4470118dc54c1a6a6e6a6bf0f220660bbfb65010001	\\x848294453dc9e8aa75163b9b9e3e47df7fafb4f1823e720a5aee1b504d6c98e1300d3f5336617e0edd57b7014d191fa59c4fe070d841c00040d4c3016d614f0d	1681741319000000	1682346119000000	1745418119000000	1840026119000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
361	\\x578780dd89f876e6d78a62011361ebecc7e69dd3514f1e5018449e1ee981d20e458138d21b4acf239ef93bd14b1b7e1e8388f92f26b2794a5260b250c7fe9e4c	1	0	\\x000000010000000000800003c5c2c5726194cdabf436759d512e37060c41d2dbc9d72d0fc4be93e801b045ae9ee698b174f3ed31da97a18a60362440a010ead02d28498db8c4e3c2938df3aa4a59133b9cf323d6cd4008ebd1d072e1a370cda8d85d96597ff5096d5d1aa89e85eaf81d535ca3d8ad513fc51e84dd43eec25fe70118afaa0908c1dc8346b6d3010001	\\xb3c5ff6090c1b58a9ee0577103a46533c5d5fed0862388c5cfe29c80e03401af6d71de0807fa6f15492bfeca7698c6eb2c2c62f591baa41d464c4f3a30f1ea00	1666024319000000	1666629119000000	1729701119000000	1824309119000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
362	\\x5a23330f3e6089e9492b22fd431953c65ecb0eb1a5cd49705047376f21e10430909e1b585b532d9938b96facf7125400dd17b4ee3d8c2a8599f25b3fa6dd7dc7	1	0	\\x000000010000000000800003eeffd5706d8c828f0227174b74569a1b53db79493cc33e0ca78b3b7f75f16a5c4501f2882e0eb5d8000159f3d075f81163b1bdada716696919ffa755f1d27a1b1dc623393daf9458143301280efc9b5fb41e085670f2de549084675cfc641f326d40e187cc4b4cde812fd0bd16418e0c5cbefaa389cdd997f3895c2fe6e89a5b010001	\\x1fbbca7d3ca158ab2b69623eac099d358f9f4fdd8ca456c466413bef560ef7886c64e9c4b644ff325ce7c1b857e277d49ceee148c8b2908a3dee3fd6d3b71d0b	1654538819000000	1655143619000000	1718215619000000	1812823619000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
363	\\x5ccf5283619f5da0d1c30ac43936069f299a3c1ad2de5c2d858828cc59d435f56f0062dffc1a3cf133e35eb44800076ecb00012a06ee735876761b80fea08735	1	0	\\x000000010000000000800003c46e16869fe62393655fd558011fe2df7364136bd4d2c79be0103a99e7ebe38292be10d00e96634bf04ca964c59967c1eb51d62bee2a35faaae8dd0e70b8420bfb43690d51c09896f9d5396de8ca8fea290cb10063b7b9da27c0dcafd2a1e367ce893b7d59c101aad13bdd7cdfa2756c46d68801b2722419a8120b575362f6cf010001	\\x8313f309cd56df90b4d212800b6d85de27f4e15ce54f9cb31328ca8290300018029b163df37759fdb0f6ee39787d20eef1775210b0d553ad4ca7b28926093407	1654538819000000	1655143619000000	1718215619000000	1812823619000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
364	\\x5d17eba01451148cb26443b299eaeebe6f0bb4edeaae02b9d5f707988b2600587f1a2e8c53e91331d96f4b04abb7062227236bd28d16cb3262eb7ebbffad10ec	1	0	\\x000000010000000000800003d0cec5f1a048c4d495674267430886f0d7dc107a92cb9faad2316d0da722941eafb3ea8b6f9b2a93f244c003f45892975935d102cd0b083ff225f1c5a2bf22a889a4f06080a4e153d5abdb2cb3127e7378989b9e992c5a64d5c518cbc8a19991f93a410b61248095f4cd2f5db533163254c61ff63ad629cfbb9afae671abd8f1010001	\\xee9a3ff59207c56bd4680e9d0173b753960dd4e44a27cdfe8d12acfba0afd3bf0d25406e718766cc3ef4e8c31d12398ddcef8c8b7d17e839f21b99055031c400	1677509819000000	1678114619000000	1741186619000000	1835794619000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
365	\\x5f8311cc4f698edf67033a83265f9ce11e14236537e24222b4c906e9c929ded128a78d5c3d3502040249abe2b37d49ac010bd6ae350f991eb365519cd58ca0e3	1	0	\\x000000010000000000800003beddfe6cb8e3da408a107430dcf0fb5a860f90b4ec88772b6f891e9dbfef8d3949ef649cbe58cdbf4dd8e51c2c4165be72df6c0158bf6f349d0178054284282714479b10596658a40c2e545097f20da76dc2fa67001bbf7449d2353f5729fab755cd95d177315d073c6cac0a354d225dcc5cacbd51387c40f2d56bcf7b7d9475010001	\\x81f289be919e55f37a4e48a1102fa0468c4ba01d4539c6d9dffea52309b117902f74df4231b8ac7cbb2c77b2013b467f66f26eeb127f75aab6cefd20e8117100	1653934319000000	1654539119000000	1717611119000000	1812219119000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
366	\\x619fe6229bcba505aedb8beef1773c86d861ca4abe73a11266e824bd42c8a5c80a55903128c793add11a2756990531a2f8d9c5a0a6476cdc99733fec4e8a1a56	1	0	\\x000000010000000000800003d78c9fa61e40a757bbfe7650626ab31e32547383b1df970bb2a36a96aee104b7a7b039621a3c1f1fd64c0d9150f3c562347fe731e04de0f07ef933131ae2ea6aa747e57b754aaef51f2d9dd83ecc03fa69d913fbb84b2cbc1b95cdc39bf2b60b68620bb4c894cb1b74063c5a24f490a75f5f09efb34f56e84086fef4d16e1513010001	\\x856c06af1dc9a8a93ffd59343e68860c810d7f6418ed0fb92cef7be36b8888e238eeb17be3f264e869c77e1dd218ae39b25fb4b884397933fd3fd8610c9d4202	1659979319000000	1660584119000000	1723656119000000	1818264119000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
367	\\x62a727bb708eff70f1969fdb43822ee5c61647487aec3eab3bacfa9fcc87c288d566f7623869719fd30239fdaed76f6f5707cce562f2f702f449ce5fba0d576f	1	0	\\x000000010000000000800003bdacd2909ce6791ee3a9531b756a293b7daecd2ab3a15ad3ef89bfd149590951cec0d8a03d4542c62a5c07d637f59538d645415b80be6056f5c6e4f670e8994734a3cf4c213ba06ad098452c0d46a4124a4677943c5e30ba6c0b7603a67c7c7696efd8ac0b892247616352466cea227fc0764418b73465d97da30e82f536aec1010001	\\xfdfbd86cee7e98376e0bbb0b6a24835d3fcec15ad34e20930436ee85cc81f04b3fcd6007a8bff9d80213a996c198179b50357b920d7afc74e93e0da9c5bc0e0c	1679927819000000	1680532619000000	1743604619000000	1838212619000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
368	\\x63cf053cb43ab6c26b1eb882197ac866ef7c9ba7c369e7549187f008e6ae79b9873475190bd8da3e67ef79ff828ac8cb504c1f3a922f000c38600b6cff00b85d	1	0	\\x000000010000000000800003b6417197c9fdd816a01a1e69ad11772f7014fa435183ff8196b2be50c271a37d53bebd555ac239c7f8cdb29af13029a62c5249b9e4dee1f444ae5555a56091147d7c1b476e8ab22031a4004ed07f4511590c46adc06acbd48459ce0c9152fc1dbd8a7856e1533f07b75c131b73ebad1e03ccfc616ac867f1201f1cbc8db16ceb010001	\\x1eebcb446eb37472f06fec059b509fccffb866086094dd2052684b8d2d2ddaa31b37e82d7b65d67d0de1024fede00368e3f6b0fb03588fa3deea3bbe51a0a101	1655143319000000	1655748119000000	1718820119000000	1813428119000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
369	\\x661f92670dc7d3f978152e53bf3e2dfa882a3859c073d1a44fb5585871b381915904421c668223afb6dec18ad17024b0759892a6ec2ed919c0458901058b5409	1	0	\\x000000010000000000800003c2ca17850f1b50f66496dafd3cd2afbdb3cecf9fd248567b930de921c813d799518e384f0d33b9c5bdccf9cd4b09caa76077de942fd1e84335314f51029c0b89b96303e69f534ce7c10e21dab4aede67c8a7acd2e50d23c4fc466b63bcafc64e07dc89c4b58fe9cf0c7fef03f7469c902ddd73259f18a8704d5e90c58b61ab1f010001	\\xf34e06ceaf59e0cf18b3a5b68a3061bd3b17332d268ee9082ffb84465e7fff13dd50d70ce7fe28469ba75fb9ca40529f57b8a3aa5070d362c8c0c017185a7401	1668442319000000	1669047119000000	1732119119000000	1826727119000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
370	\\x674f34b2d2c09ef130900885272c4e1b7f82d13d4573e8850d97ec6fe6019f2946ada3f148fb654be5ffb07149b13e10a0eeb2a7a1684bd29a802d4816e296a0	1	0	\\x000000010000000000800003b1366e82e88f86d7349011ee90fe35b919ae574f18448455bb6df950b5a8cacdfcb22ff5d33a58ae4fdc23deed32ec7df88592266955e74164f03af141c9a0b4317bfa4170f07368f5ffc5473bb5f36f961e3fe8a6270a2f29dca7212341caee135f7e64734b9e75df84dd0e27f4a27cb6540c3bb6edfaad5b244c1b50364c97010001	\\x67f73ae644d7a19166391d42bffca4e12da22ae17583f4a7df41ba17836166c2316e44d7f12cfab9397176cbec0a70c22f6896ca873dbf370d510fb26715180d	1672673819000000	1673278619000000	1736350619000000	1830958619000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
371	\\x67e3f513de5c749cd4faa11ac2962f1d1c0f66573f476180ca90453311a7fd7fec6809d0940b7151cd83e491bc35375d0d6406bc59b7d777d740c9c351940e0b	1	0	\\x000000010000000000800003ccc5f8c54ba1f07c1808f752a64a1f90fe898ca43742d8753b6781b9daa20d1ac7621539ac70cf365e1965cce3898d222fe8dc762ee3ebd2f2cc73ce1d8b6fda3464537bd78129595f58b986d0bda27b2c925a483010ed05120394badcfc02feb1b87b8bef5d485b6b9cb06a0c06626570323c36e1680031187741069c25ca85010001	\\xc4ca9663474dc8338b85ba335ea1559977d4bd56dfbfb740ae2fac44c97e2f79d34d12cf1e4df903c8cabaa458806e4623c2a5621716ca36d1232c8b6c620708	1653329819000000	1653934619000000	1717006619000000	1811614619000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
372	\\x6b533ce2ab7bbd27fc15511d4964e0da1c2d5403f7a80c446baac0f2bb58a07cfbdec55ec90ccad297e5657abf850c3461df6e22b48d8a3e5a74935d7ca50a5a	1	0	\\x000000010000000000800003e5c9c1d03abc73180f6041b3aafd6e67c204c16e86a363808a03c38f336c85c5ba22ee9580ff576c2a128f0893e700cb88500384a248ff09de6adc2ca4b9ae08349c92ba4f2823b3e2d8bb4963d2c4440aafe85fb32282821f0a63a148376338d00ea1c409487bc2e338de529b2cff65f616403bffff93c2363a16a4fe112ba3010001	\\x8ef064ce8150f8f61b6a5199cdff3b839727cd3754fc3d875d9e6db7c8cfc2683bdce4c138cbf2894f5dc54192f97743e7286166c7b125195f29fc1c7802fc0b	1682950319000000	1683555119000000	1746627119000000	1841235119000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
373	\\x6b4fd03a3a662f2add8a89a4a9aceb37fa19df5f00ed79447dde5f03284ae75a5724bcc286250057ad414159492cadb4c595b22c37f68f2e21c87f876b305dc3	1	0	\\x000000010000000000800003beb403c48ded75be497a91a37b023cef1122f16ed72e749365f65e6d54f51def5e57068763cd51c60f246a87a317989a06c2c8d4b1b68961737c4eeb49a56ddb52c24f3152a58b7d657f8c5e37389de8f8bc7ca0cb0972a4cb671501c96ed866cc7a84f7ae043db30bbb44db861701a87d88f93b1db140c0862b8b72befcc7dd010001	\\x7e0141f7de7affab79da118a694f2df2050bb7688bf467bc88154631bc0143ab6e0d6bdd96e977a7c93dc0db48323dcbaa43c18249e9e73d502ed33681040e05	1678718819000000	1679323619000000	1742395619000000	1837003619000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
374	\\x70db47d3d01dac54ccde3e7ccce4a48c2aa891283d7a76311b37c9e489ab8e03ecf7eff557243940a97f0f5c968519fdd1e332b3eff21badb1513c1827031cc2	1	0	\\x000000010000000000800003e16f096faeb5586453bc4e423186476f9676c6d3e167b72e53eb4a266c0fc712bc4035236f6863fe4af920910f97974c93b838ed293093dc56c817439788dce12799a63e2ab9dec83f3bf748e09117784de71c0fb5b3d725c6b59927d1120c84e0e08cb1ddec1de1968c39cee65f43c2f9340d520927856aa9f223057198787b010001	\\x33e175f0a35f386f8065934343685b027365d0e1ec486d504ee8a45d75fe3af32f69ce98cf0f1a01540a13f851fbf40797be130d2e82bfd87fc2e8310bcf810d	1655143319000000	1655748119000000	1718820119000000	1813428119000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
375	\\x722bf4a17fffd7de277beeb6b52dff450451af618d749ab7492ecb398d150dcb136b9c6a621f212920cb89ca4e79da57ece62ea87ac14045223b5bcaea8388cb	1	0	\\x000000010000000000800003fc69b7c514089292567a255e2670eb19981a030802fa841c89886837393d4c07d61bbd2a6d163e869e34a0a38997f67cd5382a009c0fadda54775b8abdfe6163e917960af347c32d4f86cdeae195a8257a5e8a1be5e69d03203839f7786e171796595dc24e72468698660eeffec5a92f14b4264a73e2c8b253aa65954499db8f010001	\\x2c48fa99602778409c0f5119453a3d241d064243a590bedb4941ce765ddb5cd21adf380fd57e3956c808adc8c559acdd9bf5133e26316963d897a814cffabb02	1664210819000000	1664815619000000	1727887619000000	1822495619000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
376	\\x763fe6ffdba87d57dbf687ab8a1a79d919ac168ed1adf2eaa4b8cee04b89bcb57e10c432ae950ebd7688535ff84fc031422e86b57176ff3c0df7f37c850105d3	1	0	\\x000000010000000000800003c551db857c069614add78947eba0c49b7e354c8a77db4c232547669686751e0669e3f78fcf2c3c22472e8f06f225536c3aa490f4cfa301ac9b3a33969cdfdcbceaeb848a2b7dd67c77f5e91b69fe7083f75a927427d955da36810f457bfd98c2bc24d2835a1f82baaaf833ce7edac49eb1ab6470bf9a8ecbeb33e86a91b5e897010001	\\x1141bbea43b01dd777bb8590d15264ff3c2f10c9bbc14860cc9f4aabed1eafcb32cf5e92be3e036cf24e6912fe831c7a80452ca889c1711885637516caef8102	1656352319000000	1656957119000000	1720029119000000	1814637119000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
377	\\x778ff9173d9168eda313ffad0e36aa2f6ee7c249295cd4c22c118195d6e51c42f969f967320b62e470ae854ebe626a8d5d4aff359be73c8961ab99a58ee5ecce	1	0	\\x000000010000000000800003c20e8f94f125866f843307389084be9b6c9f572b35dab74a7146ceba6af71d238a8923d7545d65697cca1f1337c30e22fbfe1d493e78a24b87f1ee7f712819d52f271860587045327fa5d04801598a457535e51778d894a32f63d44cd7fc0e072880e4c9d0b0b317a428ccea3577d46a1abd554ffc53dad0ca3e40d3ce31d603010001	\\x7e88a4852d7232107bf309c444c640b9f582c27c0e2f3db7ce09c22f6573beef916f50c2fb3f94a9b0b305a8bc88245d49cfc00eb1012cf8a9451421c9f00503	1655747819000000	1656352619000000	1719424619000000	1814032619000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
378	\\x78df07556f806cade02ecd557af3c505c38c229d79687ebb8e8cd075a92b59a531b0fae1de43b9fd0ba304caccb95d8479f88332813291d832a20aaf9a24a41f	1	0	\\x0000000100000000008000039b5b27cc584dab33a1fa9aa511de94371caa0b8d1baab6ba8d26110a05bcebdbd8736b7176f37ad58a607897e224d5f8c8b60df213849726460763cdd99e68e0068973772e884430948b7da233346a3a52bd82f771141e710071157959a5b67bcf7a174a5aa4cf3701523766d48bcb129e9cf3aeea2ebe47d6022e164f7544b3010001	\\x8e20659cb383d3c499b8cf7a09698594553b086d6e3ad9306bbb40ad617a15f2502b6c2f2ff79bcc840ace86484ce48eaeb5f19632c3a6290dd7c7c7285dd705	1671464819000000	1672069619000000	1735141619000000	1829749619000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
379	\\x78d34bb81bdce758579e595f7de621faa9bcb73b04408b492b0251551339e3b2a4cb8b623eb89660293bdaef01cef15bc30c06c930a86fbd74859d3d277fe413	1	0	\\x000000010000000000800003bf5c1c38a979665a6e57079dd593b33298cce886363f11bfdf9266bbf4e3c50ae31cdbff3efa42bb7fe423a72f0661c60d80d1433146b8b3159487df1022530a8d214226207baaed7e6b3e2d678b9ca99aecb31c40f32f6f0ca76531d2060cf12931d029dea1f114a5d05a6997db3615b6dd07355ec5aeba0ce5c0d7efe2f9ef010001	\\x541a6e0d0df44acf0b11604a719924697c5b58c43dc1bfdfb66b60ec0eca9507c58483b7e37a342f224be8c58a7fdca89847c1e7d91fe491fb8ffd4d322e2f05	1658165819000000	1658770619000000	1721842619000000	1816450619000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
380	\\x7b0f72f767015e044594e5c7f6c8040955d83a945301d1cb2f4c884d3aae940ba665ce9bf8cbb9175d08436a40bf793fb1421882bcd1fddf292c128962a1e3d0	1	0	\\x000000010000000000800003e288d0b9b12f846e0d62d6c832c75e47dd0a947ca556e1588e050e53a16d37e91ba3596f2018a45537d24f1bd5c7af355d8d89399814f5cb1bcfff9b52a52d2d5cb50ab9ab47f93ae1bec5afe9379974a7361bcc8d1ed33d84e47dc464130b13c38070fe6a68b43691a2062c8d9a51a9294105628528198d62efedb6e2a24173010001	\\x3ce49b50eaa74505ff1607fafdd7ba06f36a12c654105fb959618b243e9620bab637884816a12f933d170f51e41d14eb36736e3863bb6c6c5229796a6ef9430e	1656956819000000	1657561619000000	1720633619000000	1815241619000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
381	\\x7fcbed857749bac2ce429b2b46fe5f0cb650e30e3fc30673fa1cab77be7aaccc680d2ad15f70b738add61c3ddaf9d0d195e5fd00aa2f95d631940c8ce05c533c	1	0	\\x000000010000000000800003f69cc10c43fbac4846582c8e47e92d78b36f2ad2e2468e7ec7df07e3f2e7531ca9749083cb58584486bf4e146119c44227863eb8e4f181ea4301d0158464ed97b0e1891d0f3b319c1cfbe0210d60e95d8d8eb7520edbd374e61ef767aaea68ab1c9ea63768b5acf02086733b28e8a10519598bba455ee317d8ff596c72304c9d010001	\\x7cfe670b1a16b6ca6dcdcbbba667a2593c8dc2ae823b32922571ef13ea6dd6521bf5f620befd32120ba9f4cdbfef3afea18da76df0ac07f9da5e1d2ffd067e0b	1651516319000000	1652121119000000	1715193119000000	1809801119000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
382	\\x879f43ca67daae093ed6d511fc882538e685c8254602136ca651061d9da895fdee5033f2d1c3534d475b58c3bd6838aed3ddea04088101e1cd4920567164f001	1	0	\\x000000010000000000800003c17012c307d84915d2b252abeb84b5ad882b14a258cea498d7de19e9c7b4c01c6bc568e1d7a28a5bf0cfb3e816a3b32d1efb7785b71921a2476d94a56bd165ceb748de418c3e7fefbe7f1f6ca96bb85ac04bf57dd9cd0317a5b3fd5c793050bec3c6eb099b2cd30cdfe2147e3dd5cec11ab3a754a0db2c617c6e4976ece6e703010001	\\x31f75a5c1a0b1ecc2fe59154fcb5c644dbb0282b6dd74576ecda0f4715e200395e8475a3abe5164ad5c0210d12bc41b3782a2a15aec78b1f27bba9b752e5f302	1664815319000000	1665420119000000	1728492119000000	1823100119000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
383	\\x8847f75db5ff369b6565d62d9bf4136ee36179313269d58339c420be91dcae5c6959bc9a7292dc70dd7fefd0211e53307bee53899cc08793a16ea190f8306929	1	0	\\x000000010000000000800003d31d58c00fc030feee5ef2ec7628226e4526fe58f8a811b76b3bd853700a164eeb5b50847a800576ac62ec2fa7eeb7537c7e7227976596057177f30ac27bde21145142d8bb3d5ea120c6cacaf70cb3acfbe3337b1f80d1694427847c75572c59a16bd55e355aaea07e4e021402ae8bbd5a7b53251655ab5b7f8eb21ae201d0f9010001	\\x8b7b4984cd67e85f4be49bb051cf8fcc9da94fd8dd01311d5924e74fe52de73ea66e1fe0281a271a8127be430f716b13cf071a3638de96bdd659a9289a92e60a	1671464819000000	1672069619000000	1735141619000000	1829749619000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
384	\\x8ea3cc8356142809c258faf6c4cddde87be310dbba511d36b4db10c0ce7090082ebfb0a30bc0ec201b06a819ae476591d5bdc1164cadcda90e6c7079a8906486	1	0	\\x000000010000000000800003b42b72a3a8f9745fef9379677721c2e5988330d12d590d3179f4799518a32c100a21292c78d1c48efef139774a43272847342e9bd3b4d5de68bd8760c4874f7ab6c05ef408412a05a1cd78e6a63554093ae1f16fa4e9fca8e8e80440547cd47a9ae5aa52220b2ce9ac929323c176b43ed7679e587bd44d0eacf10a6f966d7cbb010001	\\x526599a27cd8b1b4f08dd15534c346cfa9546e4d5972d9f6bae4e1a788f1d95c5c89691f9f927bdcf8d940316e4d24431c7120340f05876963310e28e4d8c406	1659979319000000	1660584119000000	1723656119000000	1818264119000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
385	\\x955379247a813688aacac648b6ad9484de3f4b9784fc0a22597d7a4d7bb3945e785f114eb781e61648fb787e7cb58a53485cf6e9a495ffa109f7347ece30efa6	1	0	\\x000000010000000000800003bc745ba725dc1cb36cde73a6d2423c1f35599ff13343b87771878f91bd2154f2549d69c3e9641734deea5c020641bf48d0a6477bb4e1c0adce933aafb6927d9372bc61d3a2ed097adbc1c453b28d6dfba0c1b1b453072d6d339cac47f0f8506f76a89016ee67ae11e623201e3e25cbccdeea855afc0a6bfc00d217417738d66f010001	\\x370f072f0c5deeee21e871380bf7c36c5872cd868b7cc161fc4ac019690e7bfe1ac1146ff07ea6474de9405cd4f02ad144b2b89f579d1b4708f53653a7a73802	1677509819000000	1678114619000000	1741186619000000	1835794619000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
386	\\x989f25c593354433b69f2b8c796bdb2cdbbe9f28d590741812b21e35c2394d5ee7509bef10ca7596d1f4fe48203e4ed3cf99831953cf49278ef1aa3b2220865b	1	0	\\x000000010000000000800003bc32b088392c287da9e9560ec132d508754d5ee7ca47ddf66ec41c63965727a7d1c3dd161b2b9481b386882419cfb4b49176edeb5ba9857db5a65062d2bff8294d768bf0ed3112ca7dc9b89389ec9e16d8372eb2bf00d664ab3f1bc61e90f3fcd225bd344efe363023c560c87df1cdd59f8656e2c5f05bfa9b0951ad7bb10999010001	\\x896339705e2cef02a3bf90c039566362ef9a6c75bec52042f6745ff4722258eb63b42e9ce105200f3e8f729fd86ac8b1e223a9e10fcaa3215f71a05b7329b80a	1653934319000000	1654539119000000	1717611119000000	1812219119000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
387	\\x9aff313ecb926a147f3ccbdbfe0a916ae46102aa1fc6edbfcd119d5a69cce5f52f5a677374ac02a8518d88140de9d62320b0c407b719386d25044432e4a0f8ff	1	0	\\x0000000100000000008000039e7de269c18acb11910d9dc83e2b219424728fd8388cfc0e112561ab9c6530264529b3609444e44fbfab0360587e48b387293f2df7cad6126dba9dae6ef36f94ecbda1734a20d371ef700877ac0af11004a9e8479d99d6fc37c178c52edce048a1fcd5113c07a563f4232c17cfb2d24a90e3921354eda3ff00984ad06d98806d010001	\\xac12036b77e761b82968bd5334d4569670bb865ab4f6877fb26e8737d3a318412ae917495c862522b8bfc45224c6955ca9a72b926f509a4eb45e3460641bff08	1680532319000000	1681137119000000	1744209119000000	1838817119000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
388	\\x9ceba87a34700224dbccc5c8a0e7e57b4fd35c20c6f5131c214d4e3b90ebdedbb7d186796d40a94ea60a2747d8651512eedc3a3165821f39e42d62327ba34428	1	0	\\x000000010000000000800003a41a64e56717c1506e94640b2b766cc26512ee6e08306263d13c1643ba153fb63d6398a81d2e4be3e0aca560f44b85b4b1faf705a3cc78e23703c45d7a0144f7cfbdcfa90b1a7ddacc82ca83a953314f0f7887b54342c584dbd6addf086959cd620c8add757757e9beef3821e875f919c365d224c1d2c6da0f5b65a554e2e5d1010001	\\xd515757ded3a8547640f7dfa4d1829b4d254b116a50ff2d401efae5219d066610db0c885139927e67520b5482c212cb385f8508d9dc65d4bb6a20b47323deb04	1682950319000000	1683555119000000	1746627119000000	1841235119000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
389	\\x9f539164d2ff15f396a0395c9ab0e78d9cfb0699e8435c2906b4b1095949e2ca81aef467bed7cb12068fe22d2c3d62bbfa166600277121ac6789a3e1d86f7fed	1	0	\\x000000010000000000800003d7a8a8b986cbe815ab4ab13eb2cf85075d44b26b1ffa701cb83a2b2eeb2549fcf6089bb4a038dc93644dea43196ab5da9e585f7bfec1a665e06916f98a121c12e52dd03b61a520726d121c3650249f3c25f054578e9f3806b643d63486f25a1c33fa8c6a66631fe0ad1b2580c8bfc885c8931c3ca7d674a3ebb02f4668385c83010001	\\x829ca8a2e10bd86f8d62695c1ea58834ffa8f157545bb50ca27b6ed11deb9cd969788ceca42d4e57ff8936de9c765f5c8213581558b5cc76024ddca0dfad2e09	1668442319000000	1669047119000000	1732119119000000	1826727119000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
390	\\x9f133cf0ca6c2198affef5fdb7e3c46642b322fece173236c66ea264572ba1ccd6523825b0528ded876cc9e4937bcded09ff2e74bd49a6016afbad27e323e475	1	0	\\x000000010000000000800003af923a43d3d91344a033ad97da33d7a8bc231e7df4906ccbe975cf876ba5f653033eba786d823d9af3ac779643aabbab4caa557d1b40e3cf25a3cc93de56a0d14419a8862ee4fbb28c190335884a04637829b7a0aae843af128d36b92f759fd8143e81d70704d614a5d322a28d0d20376d745c3bf63277b9819fb63897ccd789010001	\\xb882f855b7f8b105d1b9e158d90c3dec7422345a279a69ca52d7cd6bd77aed2a790ecef43c932cfb9f96038e0c7ece46781cb54c5d81cc7ac5c6b0ac02a3b00b	1669046819000000	1669651619000000	1732723619000000	1827331619000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
391	\\xa5bf5309528f55e82af238645d48ea930f06bf3e676fb44a380a200dbde5d2c04b4732a182a4c85675052bbe54aeb16ddab59b4c1bc9328f69c811eee3960171	1	0	\\x000000010000000000800003dd1bd8827516961b80c6c75f3daaa3397196d2940a7429a3e62a32008cd019e447723a640013f91e8636ddf9ab2d59851bc006b593f1a169a4a9e8d78e107e38f28d8710433ea5812a63a5a0c6ad97c41024ab11eb8f581b9cb6c5204a52c0cb79563b22833181e183cf373d880791fce5afb245d4b923ca608d7b9314aa692b010001	\\x1a8f773ddf85dc14cc9bc93b53b14a6a283a8502db96e14603e5bcb74453338c3537882f75fd135dc3ea024a89647a5796c0a9bb9607667f5e92119bdc515900	1681741319000000	1682346119000000	1745418119000000	1840026119000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
392	\\xa71ff03d59de8833a046543c020ba3f235091c23b43fdb28e1b8f8738c8d478c2adb676b4fe8708a9e21bcd6b2bdaa6e829fa7d310f904c70c9f053df3fd9b12	1	0	\\x000000010000000000800003d3cf53ccaae4296773464f2c4d5697fa916af6938b72ae866a75d43234af0f75f82e011edf34f11b706204778d8b3a580a1c4e644957141e00d380b756b99825fe36c3f4f9662d2eadc8a3d5edaa09609226269b0852942e5dd793059120856acf8590c93f6b7f65ba35233290a29d60e8eb198ef384dc06e770dc4862f96dcf010001	\\xf0b6e2d4d9f25af8788f6bdf278d001211cb5cdf32a2d582a2e7ac8b615b8e3ba7f6b4f9223fceb94cff7e1509e769cc82b75aff2ece1af6dcd7801224fd9a0b	1653934319000000	1654539119000000	1717611119000000	1812219119000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
393	\\xa90b0cc9839a2fc90103f9f5e3b477ad87e896fe0e4b9bbf2f07920884ea8144b4173b02bfbdebd61b00e044339e7c0a4c87b69a87f2bf2bebb37d247b6d4f94	1	0	\\x000000010000000000800003d779d56b9cad2dd38d6301b9548a49588088a9033a16b4be68584a85c2f44eac32a5aae58eb003d4badfa955a6fb8feb3cbe900d165736ed75ca55c3d00c5e8a17dd39ba73af2ca612f7db5aca96c1d580084414f0523bde1db4cc8d7a0d4d535872e85c11a5b3cf50622dccee76b7275164f9f95e6cde670eb9da084a66e7e7010001	\\xd920cbc587d9fcb94d80095fdbcaaaa6df6108ce204c9bb902878a019283ef6e71e7791d07891f26fd28c9f7d066527aea51a0c47fd2dbcaf3d28e86ad0dc30f	1651516319000000	1652121119000000	1715193119000000	1809801119000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
394	\\xaabf1ca890fbf40d200c410e18f148a45b1da8d397bb72236119b61f003385763a460d9ecf3541ce02abe2b5651eaacc5fd39f5e78ef4d4e41f961ebbc7c970f	1	0	\\x000000010000000000800003c7d804fe44cc9051a0681697a0ec6df420cadd113725f307a12e9b4f833ef4cdca308e22b6d419e7a6c3b284b638a8beebfa0c71753453547a227d7ebdb45776585c72bc7e937afb306164428204408730e6408c44b96d52be4de8568db0a8b9de31b445830aaff64426a77fa1d78824356d24127b8e8ff051340efaa9d36ea7010001	\\x1972ac36b7db34ef147fcd71f298c2024c8e19f6ee12497c5664d741521bd99a95f05c23964c67f02fccabbac11a7c817bc4fd5dca39a1cfbdb550f977d67a05	1680532319000000	1681137119000000	1744209119000000	1838817119000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
395	\\xb69b12681ed05e2d76c6014363cb87ff9a67e48cea50693f27f69f17429a4b03ae9dd5d7ba58c6c9b4732888afbb40b22a9f5e02a848416601a7263f72051280	1	0	\\x000000010000000000800003b54f866be5b9fbaccdce8b7200ac718ebd70aede488aba9e99792d9af99e0d486eeac1db42da9617634ff8dd5f1003b5b0737456d16bf9d26aa4a035a37dba78d3b98b26c32fc0b638807023e5fa9263af24d6fb9f7a6765dad256b4b972b00b90099bcf477da8a8d82f9bd8bd60d437dbd2a95134d8c36c565d1524fd4c387b010001	\\x2661476207a79325ac5130861717ad59bc162c1376465e18b6e860f50294908848b2e78f0d681b2e319930f1fa69e5458c1c08398befece06ae53046b3962801	1672673819000000	1673278619000000	1736350619000000	1830958619000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
396	\\xbaa380ad0351c3d4bc8e4bc840a6f848936b6227d099bcbda7db80d8fdaa0b60fa2e2c8395a03e0112a50b3168fe5ee899efc151e1c534f00aff3e0b02c3df40	1	0	\\x000000010000000000800003ba846fe2444e6c58641446e468e204702541bf7c4137ca97d816d2d60f5b9be58695d4fd0e552205165993b8c7575f09db2b7de3ce1d50166c2e279b2ba2d9b506ad2a84a6d4ae943025cdb27adecaa597aafbc2b2b5b44b6ec5f9609f9b640354b0f9b17857be0e60558e7fb03c5df2270a90a77531027491b4068e3e987eef010001	\\xef380caddbdb1ea0e34b05a8c69ed587c00cd2ebd16db01c62cfc978a90e2da6c4156bb7197c192ce6b446f21c0c3d2462528012c8fa06ffe9fa97a266466900	1666024319000000	1666629119000000	1729701119000000	1824309119000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
397	\\xbb736cf2f899e3edc3f9d155bda2c8e84ece5f7a1bf106bf5297a933d5a46ce4f8573a2f6cd1f71cfcf79ed39d98ec5c5fcead8fc30843214257cfb099dfc4dc	1	0	\\x000000010000000000800003c29e161d4734c7d147278768900f96e8193dce681af4eb94d4061fb725197bf63e2dd7cf15891916c72f6c70cf81c318896ace4a153ab32c97ad8a5b6ea1e94794a57dd027b67f2a519d4ac0961ad8755e96cfa45b1e85c704cb9e8d3f15762c95533fa941647b2420befaeeafbaf247baa23eee518c0d92ca224101f0e4c11b010001	\\xaf659576be323447e8eca27b79cb6d889b8aae7af2e161aeaec901d82c4dbb94b4892a385228bd94a258b93c9632b5fb44f77985abf00e5a992365eeec5b4b08	1664815319000000	1665420119000000	1728492119000000	1823100119000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
398	\\xbcab7325912c7c1736ddd629415e1b15c15964a4e901ddaa8277e2346fed1933bac0df3f250665e883c2b950c8a6cc86631aa6328827f18fb3c90deca41a7277	1	0	\\x000000010000000000800003a5d2b1d5040b6d4fe5685ad3ec03c7a18d272d3aac9df780cd462d51be1932177b477b029248686bcd1056b29b25f7a3dd3ad122063933ffa6a690beddaadd08bc8302f6d43d31c16c2788cd809207d9f5c4ebd9ad6b63a0c36bcf2060e7b309421112ea8283bc821a1ea4c8272fc0ccaa1e8f6384b37435d2dd6c9d3294eebd010001	\\xa19097dfb9c7ad4c595d87ee312807b7a5889f690d03d45777e3aad6b31f92e8089a1650e7e25a3e12c676ceb781f3cd52a15384194ebe8b8043235f477c2202	1661792819000000	1662397619000000	1725469619000000	1820077619000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
399	\\xbc133eb71f1221a1369cdfec727c701d2075c80cbf4c1a96eba5b9b0355c479417aa1214ee89bbd315fda8141abd3fe0a368db0507c4b242af2695531ac09c7c	1	0	\\x000000010000000000800003c00ab2f4d6eb8c9d0f29f900b5f24fc0e6cb528bb0f470fa22e6d33654025eee5efa77c6ba04fb7733f3932edc042800d4eb2776b317c74ef6cab63f130ee8a6832ffdac3dfeae153b9a57a5b83b68e13d1f33ea0bae000d65472c48185778f73d5df2531362e16d34ab522aaffaab7d57f52ffdf87a8574dc71c26f0046863d010001	\\x92ba45838dad6e7e561ab6cea94d41c61a2f9501f3fe9391d9c40deef4855eb81fcc1c4477860d54817054f74295d5d6c1718bfe6ce3076d7dd1edb18be4bc08	1677509819000000	1678114619000000	1741186619000000	1835794619000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
400	\\xbd1bf51bffaf6b8c4fc38dd903cfb92b5a3308fc53d6b5956bbb53a8fe4bb94171e6c62fc8c066e941f3be2e3e9cd6e69cdb9f554577a0a8474297cec7a74dce	1	0	\\x000000010000000000800003c816fd778d1346bd1134d4ee5bccf3c59abf03a1935736a7d59537203eab5b8c1f2f135bf8eaab2fdcf31f5b090ac91083b4c82e87d836e1e43f69efefc7652cdced7e5f597f7ec3b3bc241a30c60597759d6b3fe61d424f955b7d0585d8767b135aa0511527d1dc5b8b0b5fc80a0a26d2161b1ca9614374693b8cd37e35bd59010001	\\x9d5ca8348200a4198f2bbf702488c6495eb897e60c2536af632cfdc27ff77b35ced82339b9f64e380e3975ddb287a867ff99981d8fe8ab82e295e2c7d7c9da0e	1668442319000000	1669047119000000	1732119119000000	1826727119000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
401	\\xbe13e6acb0e938292417f0fb01dcc7ee75e7b88409d9f43a7d237c6032ce962b283cb5f3b07c4fceef1186abf1929069143eb2fdb12094a50cc4a86e062d99d6	1	0	\\x000000010000000000800003acf35f3c49bc3a70f369922baf12d4d5461baebbe14f6ea0000e4e91524719913848833ee301d29450d077d08cceed3612b94dc0948a4092820fcf87ca865ab9df15b3b0d0948958e9855a06f44ffde39cbcd71fb6723dc5df9c17a14a7bd14703017f294ebd3f1d3102b7a74b8ec74416637892359e2fd0a635153c0afa8e49010001	\\x836c3a818e641864e9aa094472c6c5ac7a6df5bc8d5dfe2f0e7ac4041ecdd3feb87b4184e960c716d1f1f41142b2e5fae5af82d544d851d35b6ef0a0c1b66e00	1654538819000000	1655143619000000	1718215619000000	1812823619000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
402	\\xbe87280864bc1479a5e40278a1f3380fee04ac269ec8f9d595a2236da2e0595b09053f4b56d48701c6d6f1ea85c0f6b3c944c61927359c3ec2adb2a13354ddf7	1	0	\\x000000010000000000800003bd22092459507844eaa0becb4a921bc6dfce7a53ba46b86419aea4d3ecda646a8b9a8fd4728ed75ebec045819111e6e1f657787512698b2a6bec02f16442da65980c5d06c0eee8a774871d8f563923223d2d8330dc9067615ef90da0a64bd1910421fb9dd5245cd3b602b816f7a8aae0672cc1c8d28786b5520856a8aae1affb010001	\\x70c621901fb6c9308fb5c9886df96f6218bea5a30168854ec7064e11bbaf8e9b884e80487f7c7478c5367a579f7138fd03cd84753c89522fe93faec10f9a5d04	1681741319000000	1682346119000000	1745418119000000	1840026119000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
403	\\xc54f85f5afbef17ee2dc9db005aef52ccb3dd0917ce7028426d22622779b59ab40c4ede096d162581f047ac29264518b0e84410339d14b57a6d03b623db8025b	1	0	\\x000000010000000000800003d860274396b4521fea693c836833fad6c8a02ec88627b1222cebb1d67b2579ef43971ad41608ad1176f11a3f1d46b7b2bb374b815bb1f221ea0ff85829c71373cb326b79b84acb4f164c5c2b063bf3840983aee0c6a0f5c1bae8c982f7b45d18111be0371c64107669dc57b53809cd2f409b5484598f9e28e6fd318de9e99dc5010001	\\xfc56982e40ad690dc776a1483761a3645b8594f6ccb3adf3cd49e6a027c3546a0f0131c03bab1c8ef686512c1060e4471e7508df615cb7b5608dc39b3195f109	1660583819000000	1661188619000000	1724260619000000	1818868619000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
404	\\xc5db5428a51c88c63e327fb09fee2107f7c525b9259348aed7797b7ea0a75bebdfbe36d59c512a7a03faeb03943ba48d9f3a62126925d1c3d45fecb22b17f659	1	0	\\x000000010000000000800003c199ff3498b9aec4242b5f23fc05b516cd0517d1a1423f7b4d07ee9b583ddb034a83ce501cfe265f12e5b3d07d7dd5732025c20222df966ed544edb86ccc3f0e283299e4ad88e867f51f64cc91ac6090c90b0fc942706c8e9874a06ca12eecd78f684128333a64faaeadec0d7cd6f2112406fc9bc3bb4d5899633fca2a93ab23010001	\\xc40a4488ecff7ebf8236952693ab9163df5cbab68caa7b92932e4523e8e313dd4351da4971453217c06df1e0a80f5f6fe33739bb50ed3cb921b9d1a0c4324e01	1666024319000000	1666629119000000	1729701119000000	1824309119000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
405	\\xc71fb650efa6c6288d033506f7c2312f36e19f003bb49836fc64e3bc7c54e04a12928803ab3f14e9de605a087b5359caecf31f5ad0bf9720ccb4a447d6a51e20	1	0	\\x000000010000000000800003c1ce16b49bea299eb145abba772dff79dc13fbdba414f6f7ca854d6dfc471672b6d4fbee630c13c138c476829a9b2266eb985b38e48134434f2a0f95044f8faa14d18daea398872374f34c545cfb48f1e10b0375551fecb2f8c9bbcb8b6527e70bffdae9b8c8c7d14906b4cbd099d892aa9baf8cfcfad92b2699c1b5bd84e7f1010001	\\xece18dbf33cd399126859b59d0df5752432cb88d0dd06c0ef144acb1bacf5f808ea093326500742667c4d3c2f22f452b37acda2e8f443014595ce15bcc06a90f	1659979319000000	1660584119000000	1723656119000000	1818264119000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
406	\\xc9d7ba944ea92c67af91c4103f239e903b218976183933c6bd998d8ad4862aef8b88e3c75a5b3cf8e31333fa804884f196f51fa748ebf047198649a12b9e8157	1	0	\\x000000010000000000800003c6c6f48c12a7d752e293eb6cd7a9b31fc426c6c89fd13a472bb9551d30a671fda0763d7102aca0800b260acfee423a9e002568298547f75b068b6377b4656e5496e19926e78fb76fbb88ba59d03b444866ed1fd5bcaeb5a008787e45fa2a295e0f36d6bba2baf1c5c47eeac83197f4f5fa400bc273f522a5a37b33ff902fd85b010001	\\x193b414486090e411c4f4cd34275cf0ea7977f1f6c9237d6350cfbbc3c80a72edb383892fb8aa7a019087c87bda26d51d1cdfe8d67f7d297473767e0eb96e00d	1669651319000000	1670256119000000	1733328119000000	1827936119000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
407	\\xccb7a4a314a8ba5b2a147ceab7824771f7beea35df1b345c1248d614eb53df7923107be4546e4ab9af435e30541929bf285ffc8efd34d69ea098779b68b1620a	1	0	\\x000000010000000000800003ddf09b9aa0f1a10fee9ae5da8e481b3f7d8f10b6ec02567786c249445c438965ab202eeb518cb1b0bf32823c2f0c75f1ac1d7c68238f3e5107914cc96d2a5c14369867de040e03133169c5e24fd10127d3b3599ca3e49fb545e1b03496830d2dae7196d13ca232359f6ce5edfd11c994aa33772c5e68a937019f1ce50908313d010001	\\x793173e2cfe3b52c9b64d08610807ccea9c818d99bac949e562c94342f4e01cd47d33da3aee2cb984a47c1e2b2761ab1f37f4aba7cb725b3510137e7b4a55907	1675091819000000	1675696619000000	1738768619000000	1833376619000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
408	\\xd327741dcb8647d3d9402d020803ec4776a9433d11832056dd4bf7b2cc2a5771da9e6afc6464f1c9d65b48783dd2f1d44792fa5f2ce0288e6ae6b63001d2bbc1	1	0	\\x000000010000000000800003b945e46fcec5934c24e3d88dceb38cd56a34078316a46969ea6c949525e36872c5b6bd7f3c4d8d31e642d1c3fa793ad05d43754ca8e6d95594bc7fffaf0477fc03201b8175e8ce9d051ec2483f65e6646d29ed5771c20f3cf444bd45e18794ded6370b7c304b3f6f9145d4ff3cbde0f82d2514caa0899ea208c67c4aebb24737010001	\\x2f669c3574b465c6d40dd5479166eb13946f838dfe949088ae45d045bdd6a3227b3ea3ffdef712ecdd475603326b889988e5266c8b5e0b97f7e5c339a60abf06	1670860319000000	1671465119000000	1734537119000000	1829145119000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
409	\\xd6438032010051e1b57726b1545a53a4bd8179974f94212ca9230ca09e68e4981c2836557fc6a7160f50129cb95b7bec0dba7052b56c26c0ad436183b804828a	1	0	\\x0000000100000000008000039c1320362a5ddb2667293244fdb275dc9322a465ea8f4657fa201ec19d8acd8b554c1c4c6ed5bda1eb6722755da67099b6ee51a3884065ec0737b8bd4f9be669a87c97248f4edb9f35f60586d06d1e59a8b17d8daeec8364e31e5cb4a55be1cfe25dc14a30c6ce5e847a1e1d3b28b33752333fb9b954bff1f2f351d24fa03b8b010001	\\xd6335e7c82b0cbec2837fd6467e77c8eb4d84f59c2500b1f0bee3c4eb542568f4d11f348ad9fa5d7f62bd9017bbd4cc531b907399173cb699166669954faa10b	1667233319000000	1667838119000000	1730910119000000	1825518119000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
410	\\xdbcf668bf93b2237072bc432a6c42cfe0bf20dbf287e1ded42ba2df4ce74e802f37ed1c6f82d1c9d4c0453123b8bfe2e8c37d2eb1d646f848d9f55d170885317	1	0	\\x000000010000000000800003cf5f49674483538588832dec1fb0e2811eee36baf08d667bf457cf3da8b97f1d349ef19cc90e0ee144f28bae8ca867fb10f9e872cd17df1743a2be9eff935858cdb4d833636d582401daf526dbaf384ce6263675ee25e51390cd6ee2f2b81924a1fd8f2826faf2aa5284a7ac4012b10c5c84db5e218deedac40613bc141fe125010001	\\x7e1cfebcf3c60f9c315f6b1c7b6e496693dd979dec0cd7e7c83238e49f3446974b93c57ce659398d5a2ae400a09e93bcb8eb04d8862c3605ad473972ae7c6b01	1675091819000000	1675696619000000	1738768619000000	1833376619000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
411	\\xdb570337d29cf1c8c47fc0114d5c63a8e90f86a7ff205dbac3a487878043e375074687720075201579cfd8ad85ba15ce9a60f672335404098106c10e0614f0aa	1	0	\\x000000010000000000800003cde684df95dfdb6103e211f74dc2b568f3fac8a12c25ca5da080d9a6d8c3f8196d32205f7017c467269badd63b1f44888f5d33556fa029b22b27b12ccb3977146af95b7634eb9fe4571a170f440aaa595252308c5b4b659deaa563b7e6bc77dbbe40a8b394359e1f52983a5e03c4f9ad64bd57017be1c6d5677329d561552bc5010001	\\x570ccfb19a5ba80d2a8b76a0816b512049bb000f78d20e1016b3d5070d6f9ac31968d2137f921fd4f276161539920105790a7f07b6dda884f7c8a653c89b5e02	1682345819000000	1682950619000000	1746022619000000	1840630619000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
412	\\xdd9b8acc5647f73a25a0c3edff218a068d866f8cb8c1042b848f1251f5a39274ec11d3c308975f42aab21f59d0f137418d883ba424145f32a7f653570827f1f6	1	0	\\x000000010000000000800003a3690bbd56921e04774cd9321930808d35b736b6fc138e77ab71d3171e73a246d47a2426be09853353f7031bffaf5889ee9cdeeb69c8ea41913fd3095c8e6dd9fa870128c3f33ec7c897fb8870c2f1b034877b3818840f888a5125583edce3866cf2b4e1b8d942f240f7b54111d737a797da80c64d065be0ed97fefd9f710ecd010001	\\x9341d3bb7a34e94b5679052cfd56b3c6247f362325f8d800f1a07facd66480bd21d5315bbeea6ed073d2ec3d1bb2991c600cc5aae167eb5fb832e05988262a07	1667233319000000	1667838119000000	1730910119000000	1825518119000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
413	\\xe25b9e3c47541611c962c2aecb23c65b5484cf2118290524f4b3ece271ae3011029ce8a2db1eb02643cf3f2d715f5f385e7ea604e49756ffcee8b0e94245eb62	1	0	\\x000000010000000000800003cbdabda4dad32af2cf8e638094b7e01290e3c7f192c3dec72b10029250260fd7745dfd1ef469ac42f29875f92fdf97d4a6ca3dc588b3eceb21e347d7cd9160ac26ccbb1ff42fd1ce982f8891b69746911bb8c0fb3279c8508a1898c8c0e3a10b4d7cb03646017c8ac5ff661a60b0f18ce4cf6d19e3c525a5eb136cd283cc835f010001	\\x6091f1d030d2f978c06a9b25844b9b514223765bddd038f3cc937b2a2501cd52e1eee64d35bbbe257f9a540b246dc8e675a9c4503a3307ba2d70214cc44db400	1681741319000000	1682346119000000	1745418119000000	1840026119000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
414	\\xe34b19e979f097b82f935212c0faca9b5ed6103aa0abcf8d1db9480103b0681604999b903e67f837a34d58a75dcd20bf29fc9e54e72610da7698f8e4ea39fdee	1	0	\\x0000000100000000008000039abf717193a6341faa29a9d78e901f564f0f3006094df7fea9899a8d1df5db7ff223047cf8bce1b144520ee344c71d72109c6acd93c169af05a5c2ad7aee12711857992605fb40eb8d9123a8125e27beeb82420118bf10959caaef341889093cd0d2b781ace9b90f5a561170ce46498063cb2d3b79dfbf3f51b6c600cbd84e53010001	\\xd5185246c4dfb88f925964c33e7f56b084a18aa2472d170463ab84955cdbf460350cc2b8beefb0bc24c58fec2c16f466a7683b28a24a8ebec9201e8cd597d309	1663001819000000	1663606619000000	1726678619000000	1821286619000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
415	\\xe4573c7cd65f460e6f985204cb31428b6360050b198680a47142e2b8c655a051a153f31672308f429b1ae7c1fa0a3302094c469938db82002b8786b31e9695f7	1	0	\\x000000010000000000800003afa7c1ccede7397f75a90c63ac5097392eae9af374d6241bbd14899fe90093704ac5961eb35a00517f83eecc3bf2bcae6c26839802c1e273518f29ae6d76b963ba6326b0892b2605998ea05709b822aca806dfcac5153cbb6ae5e32e35a31c158ecaad00ee2e9012ec89f4efc1c30a835974750183e82f63f212d9746788415f010001	\\xb0a799b4b800e045a8bb5e62aad7435dc7216a4bc27b5b76214a6dfa8228345c04015ac70f39e7c48c4a71773a177316c38e2132cea96af168d7a668fd921c0e	1654538819000000	1655143619000000	1718215619000000	1812823619000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
416	\\xe5bf306e54c3844d3c5dbff359fc75b4feb65dbd0c64a5984142e6f235965ab5e8c33a0b4f31d77b21db151103c7d3fe0d9ee171c37cb26ac1461b3a5503d529	1	0	\\x000000010000000000800003bc181b4c98a92cf00e5ffe674f84acb3bfb7977f316ca160acecd3e2e1297c3e5e17457fae131960e8112d5d12b2717545ce3a1f0c751f14189478b8938fb43d4e794c137eeb376b953d393ef5bbc21aea67fc12074a5de30b71ca049740f72c6ed4518afcc71d64dc024923c2c2f5040e473b5e1d4a1cba03a410cfa909d479010001	\\xc69d13cfa2f6d0e0afee4c459210ad2f695d75276c78629853fcacf5f194163162b14bfcdd5127f87a201fb5cce9ff1bfcbb283b3d0e7d2139000b98d9c2710e	1678718819000000	1679323619000000	1742395619000000	1837003619000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
417	\\xe6879a6a58c8bbf31d06afce331f378d77f3c476ee7f01c0fd47d2f2b5602d42f2471e9314a0625416556f6f305eaac845490087699f5d4dcaaddd392e773a08	1	0	\\x000000010000000000800003c2579622ac5a3ac0ffd847dcd4fadc076220202f2b679b9f29ae5bfde5a0a66af2244aa1608216aba900239592bfd74877c3fe37f96ca18041574294e40bf68127d84ae3bcb9e3b9cb77f3e5db9910df939dbc91ea8c257268aa21e3b33fb0ebac10dcfa4318d08ddbbafbeead47b2238477c06311f73a7ea7f41ce5a63fc56d010001	\\xa03e56f50265531bef2fa3b675099208a68f18a7f3e63f2d29c879ed8b41a243a43f8156d5db6ce85d42d8afb86dbe94bb901118dbf87bcab529a697ece20d07	1669651319000000	1670256119000000	1733328119000000	1827936119000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
418	\\xe6a3150e045163f533655de68c1918a19d8bd043fa03735af3ae3682791def2ab699c92ca0b656ea3d18b1dc6f8a05d3d5ec0d86f100d69d1ccc33b15997e97a	1	0	\\x000000010000000000800003c7e69450c0d9961cab98b2f6aaebc1f45fa1b76cb64cbc388fe6739f04ef804c572be83af61322e4f48932a2ba382d5a37976eba17e97a2418c624ed87f7a29d49ec6cc31c3069e206ba05f2553a1aadc6ea5809e0f466eb12b22aff044c61d49950f3ff91908e841b4b55a59b8170c87e6c525bc760c489c6f115679f1f426f010001	\\x2831685eaf3c106f4f2fb0366cba1aca37320d21f5a663319c18b3907c00e25f94e95550fef0b2bad2b08072a4ed8e83b029567cc038311b810f37c0f4cedf04	1656352319000000	1656957119000000	1720029119000000	1814637119000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
419	\\xed1bfd68c15f6868810c7ccc13979fa7ee21b726eabfd44c93fd241abd387e53c6b6c46a05fbc110940263b49ea5b447a8ee6d28c4ce49e8408f0c11cb5deccb	1	0	\\x000000010000000000800003dabc465fd2d234e2d3f63bf87742da95f8cba4d59373bd017b290b21b822c0c767fa4690281ca6717c7889259b513fc1dcd98b069d1d2dc7e25beb158e46f7a8df8233bdb58600c59e6bdea4dae001775b91ae673c98e01a2cb7b49801d893e6166b46d6b394c0c0f1e9a26b6be5cbec648142e4a213157e68ca698a9d493c17010001	\\x589944f8939bd09740cb9a7ba4d632b52f44f2d8cf63e282433f2ce3a7b86ead45de93e48dd6914488a653e3e098bdf89ddacb09a2fe97b657b6d4454aae5808	1664815319000000	1665420119000000	1728492119000000	1823100119000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
420	\\xed73b0be6225b6456e46050a6d5b46ba38b24d8b35d8503c46f7a0cd0d42d0b0d2955d7f85b10a3c9a2cdc92c7905cf802535a11b73f185589eff89030f70717	1	0	\\x000000010000000000800003cb917c524684bf78cdc23648a748e8c94c289c4ebe720ff4c131e4638f4f694844013eb6b3e2298c27de93b6297924e818b3d1f0e1bb49d3b2d34ed16bcd486050b5ba2c1a83e9fdaf54da202a03aae10ea349f01920447b8800929fff30eebe55203b715f4ed9315f8889eaff43a00b91e6bdc013fc1c843f795ba6596c11bf010001	\\x76cbee857cc1cbb1ccab9b4f0e83ff6a597185f893736d0ee14d85d99479b1ccd0eac498682d47e3a1965b2113b99d4d3ce0ac963fa68e566dad42b529b9a802	1673882819000000	1674487619000000	1737559619000000	1832167619000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
421	\\xf03f3147acf0afb477e5f44bcdb3544206a9641d5ae1d815d71e5fead6adff7f5fffc67ea84d16846005abc380455980b255f4bb410f8c945a50b2a60e9f5ee5	1	0	\\x000000010000000000800003d5fcf779c25b97ad26a8ab64d7d7193a88e147f25d256196a24dffa935294f26cc2bb07206a8fc1ccbab0b594c62841ab731d1b8a7bb8eec631a433ce2ab8b5c49f89d0d77848229480017df8ae18e8b039ae2f378e6bae4ad42040494401b1621ffc67d9846f291003eff8c8aa94ac18322f8d5d64ae8eb8ae2a9db825b882f010001	\\x32e281a5ff9f5e958d321205e5416f0fc763b377d91a31393b50c29e155e94f91bd8584d353f7691f330f2ffa0c64319ee68ed7d049a74118726ede3abf21b0e	1656352319000000	1656957119000000	1720029119000000	1814637119000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
422	\\xf24343054e70202aa0b780d7384aacdc9635e4853bfff5306f5d045b75c0b67b86fa69b42dd86eebdf33fa959fe1dc52c62e233680545256dba111a22e330f62	1	0	\\x000000010000000000800003c29885052737bf99b2bb1ba4aceff1180f2ed36c2ef8b627c960334aeb53951ff5e33c861acbe2df36feadc8080fbef30d1e4a8f8041c5c32b41f1cb3cb09b63b71e2077ffaf10097acf748a8f3535d0bd6c1c44204262e5caa733971cdbcbb1c407c4210a0c160be298e4f7d214f60cf531c5fd0d9235c30d4972a7aee432fb010001	\\xa273d7895cbc42881ee4477f0b37013b4e5d8270a68b684f6cb6bf7ad32c6675debaf975b7be1cb36723b6e28296afa028f3d6593c15c30fea8481ddb5f8950f	1682950319000000	1683555119000000	1746627119000000	1841235119000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
423	\\xf833adfa93d0513688e25d5cfed36a62cc180ed76a24584d984726bb8117b2fec2a531a074aea0f3a3cb1a6397a3186938e6a16f2f0ee0d255a73c1b866ee3a2	1	0	\\x000000010000000000800003b5cb5a1e3db9d683075bd66ecc14573c775da86c6242afcd8afb927d9a08b105fb7a716439afc5061e41db8743bb143d63d2a5583ceb024631d34fa295f7cd2934a13c1d5c6242be1388a5dd2317c99de9a2db07e9505b3069ac66dd7a9a5b92053551c930b84e8623c1f42bac96d85db6cf552aa624d8c0a57ab1082fb7420b010001	\\xda824eca221459d58c541b678765cb1942d0d6947ef20014b138294d3d3ca09b1b9ed3f8b65435f07699b020d67b4f2f28635809247c14b417ef260bc858d703	1676300819000000	1676905619000000	1739977619000000	1834585619000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
424	\\xfd0bb032cce4a9417b9e4d90dc8290cdb4bc2fed8dd67968d3e38d317d1b40eee682c4463f07c2e07e8680289cece042486fc968d0b011a5468ef361eccd4a50	1	0	\\x000000010000000000800003d12a7651a432d3070268d3ed6880ad0b3258bb3947ee556b9bfefba53675e2d0e21a94875afba104fb82c81049fedf4105228f379ff95dc1e10f7082049ab40559ea80da61d356d893c517435dfe7d29d4acfc4db63ff2f5766d023db0fe75722143bd76e536da265cf2578033499a2f451c742ba5f4dfebd318e27e31a90af7010001	\\x8b7b629b130b983123641b19879f706df9a99daff46f49867eb5452a4ce3784d05765754f791f1736053df44f382663d70d20b84e9994c3c4a63c9bef17e0f01	1658165819000000	1658770619000000	1721842619000000	1816450619000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\xaf96eb56a9f9586fce845e9a7d730d4b96e369c2f3822ce94684a2bb123bbb3d	1	\\x25d7f52fd910d1ef5a2e3d936c450c9802cf5f4dd2fe153c3794fbc34eae04751da8a895fc50193264ac71b56f6d3a863120f249a0e41f95d7d46a78c7696e8f	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x4332a939dc3c977675db40b1afba3bec4eb37cbd6653599edc4718aac09183f78265ba0c2db1376163e0a548ab2b268085043b7b8cbb636fc5477071bfb9226e	1651516337000000	1651517235000000	1651517235000000	3	98000000	\\x1fa895a49dcc46823e6e3b57dcd9c0a30cae46c2908715be2a4b2acea3a3f58b	\\xb971c55b70c6961519118972895c3afd1611aae9bc4391ed24d7ca229795a778	\\x62f1b06e5afe9ed971811988139c7cb1b59050ccc394173a67a7990e5d08bdee7b0a00105dfa0124bbe467b5fd9b110c021c50b82a909e731c982ff83c2ed404	\\x47ad02a8c69cd47f05a8dd35e227ff48bb5129bcb55b44a4d8626335492424dd	\\x20ecf7cffe7f00001db969dde55500001d2b47dee55500007a2a47dee5550000602a47dee5550000642a47dee555000070ae46dee55500000000000000000000
\\xaf96eb56a9f9586fce845e9a7d730d4b96e369c2f3822ce94684a2bb123bbb3d	2	\\xdd4c0b8289d0b85eca07dbb7f15d9c16142e19c48fb9894a312cf3fba12caf823a428ecc7d3f60a54af21de0d6b2902dbf9c34e3510ab6e85a38c15a3b4fd5db	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x4332a939dc3c977675db40b1afba3bec4eb37cbd6653599edc4718aac09183f78265ba0c2db1376163e0a548ab2b268085043b7b8cbb636fc5477071bfb9226e	1651516344000000	1651517242000000	1651517242000000	6	99000000	\\xdb47c6822d70335b30607ee22ac80c825b054b2810efdd1ca952ffcd93e4867e	\\xb971c55b70c6961519118972895c3afd1611aae9bc4391ed24d7ca229795a778	\\x5b65de867efb08b0fb67bcb0cc1d778d346a09ad83ff0baf7a3418d59027e85561a888c1d0109d2bd57000b163512ebf247fc05d872dc78d23a40b5d343fc200	\\x47ad02a8c69cd47f05a8dd35e227ff48bb5129bcb55b44a4d8626335492424dd	\\x20ecf7cffe7f00001db969dde55500003deb47dee55500009aea47dee555000080ea47dee555000084ea47dee5550000c00e47dee55500000000000000000000
\\xaf96eb56a9f9586fce845e9a7d730d4b96e369c2f3822ce94684a2bb123bbb3d	3	\\x28711c7451f416cdfd3150c1f25209a3ea14a953cddf777e2e5a5159b494e3168e4e4b68c3dbf7f7e2b15bec4ee516f7dcd8a83b230cb8928e6ec404405786f3	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x4332a939dc3c977675db40b1afba3bec4eb37cbd6653599edc4718aac09183f78265ba0c2db1376163e0a548ab2b268085043b7b8cbb636fc5477071bfb9226e	1651516350000000	1651517247000000	1651517247000000	2	99000000	\\x26216aadcbbc75f182255f28b581cbf635fab229c76ca40c7979cfea50415459	\\xb971c55b70c6961519118972895c3afd1611aae9bc4391ed24d7ca229795a778	\\x5935ae539e2a1f0f593408241674c31cde642b9536af69c357aba5fbf99728605d45552ce86eb1e90feb41b6a385b6ab75f00f4627dbf9619c6ceb02bd3c3902	\\x47ad02a8c69cd47f05a8dd35e227ff48bb5129bcb55b44a4d8626335492424dd	\\x20ecf7cffe7f00001db969dde55500001d2b47dee55500007a2a47dee5550000602a47dee5550000642a47dee5550000801247dee55500000000000000000000
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1651517235000000	912124204	\\x1fa895a49dcc46823e6e3b57dcd9c0a30cae46c2908715be2a4b2acea3a3f58b	1
1651517242000000	912124204	\\xdb47c6822d70335b30607ee22ac80c825b054b2810efdd1ca952ffcd93e4867e	2
1651517247000000	912124204	\\x26216aadcbbc75f182255f28b581cbf635fab229c76ca40c7979cfea50415459	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	912124204	\\x1fa895a49dcc46823e6e3b57dcd9c0a30cae46c2908715be2a4b2acea3a3f58b	1	4	0	1651516335000000	1651516337000000	1651517235000000	1651517235000000	\\xb971c55b70c6961519118972895c3afd1611aae9bc4391ed24d7ca229795a778	\\x25d7f52fd910d1ef5a2e3d936c450c9802cf5f4dd2fe153c3794fbc34eae04751da8a895fc50193264ac71b56f6d3a863120f249a0e41f95d7d46a78c7696e8f	\\x78edb02fdfb2961c8276cd5177678bd352554bb589b6490c0ee09f585e52b77f4aa90db589e4c6217f33e13bb15692ea975e4e03a081cbf9ca8068bbc5088d03	\\xeb64a059017e25c81ca2a5719169a1ca	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
2	912124204	\\xdb47c6822d70335b30607ee22ac80c825b054b2810efdd1ca952ffcd93e4867e	3	7	0	1651516342000000	1651516344000000	1651517242000000	1651517242000000	\\xb971c55b70c6961519118972895c3afd1611aae9bc4391ed24d7ca229795a778	\\xdd4c0b8289d0b85eca07dbb7f15d9c16142e19c48fb9894a312cf3fba12caf823a428ecc7d3f60a54af21de0d6b2902dbf9c34e3510ab6e85a38c15a3b4fd5db	\\x1f72829c6d6edb253a18c312bf5bddfde6f690081d420bea48d3402b89ec3a343e7960a380af1a8ec4843c63af89ca2527fc18fa7d9d1d6cf68ab56ac780790f	\\xeb64a059017e25c81ca2a5719169a1ca	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
3	912124204	\\x26216aadcbbc75f182255f28b581cbf635fab229c76ca40c7979cfea50415459	6	3	0	1651516347000000	1651516350000000	1651517247000000	1651517247000000	\\xb971c55b70c6961519118972895c3afd1611aae9bc4391ed24d7ca229795a778	\\x28711c7451f416cdfd3150c1f25209a3ea14a953cddf777e2e5a5159b494e3168e4e4b68c3dbf7f7e2b15bec4ee516f7dcd8a83b230cb8928e6ec404405786f3	\\x87fe0d4963f19fa12858ad923fc980390ff0fb8973a4448cc8f7c62dc4639bbd83d602c6776d057f546a05d4e55d39534342622bc84736c321b44305b3a04f03	\\xeb64a059017e25c81ca2a5719169a1ca	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_for_matching_default (refund_deadline, merchant_pub, coin_pub, deposit_serial_id) FROM stdin;
1651517235000000	\\xb971c55b70c6961519118972895c3afd1611aae9bc4391ed24d7ca229795a778	\\x1fa895a49dcc46823e6e3b57dcd9c0a30cae46c2908715be2a4b2acea3a3f58b	1
1651517242000000	\\xb971c55b70c6961519118972895c3afd1611aae9bc4391ed24d7ca229795a778	\\xdb47c6822d70335b30607ee22ac80c825b054b2810efdd1ca952ffcd93e4867e	2
1651517247000000	\\xb971c55b70c6961519118972895c3afd1611aae9bc4391ed24d7ca229795a778	\\x26216aadcbbc75f182255f28b581cbf635fab229c76ca40c7979cfea50415459	3
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
1	contenttypes	0001_initial	2022-05-02 20:31:59.617606+02
2	auth	0001_initial	2022-05-02 20:31:59.746932+02
3	app	0001_initial	2022-05-02 20:31:59.840833+02
4	contenttypes	0002_remove_content_type_name	2022-05-02 20:31:59.859241+02
5	auth	0002_alter_permission_name_max_length	2022-05-02 20:31:59.871255+02
6	auth	0003_alter_user_email_max_length	2022-05-02 20:31:59.883052+02
7	auth	0004_alter_user_username_opts	2022-05-02 20:31:59.892723+02
8	auth	0005_alter_user_last_login_null	2022-05-02 20:31:59.902632+02
9	auth	0006_require_contenttypes_0002	2022-05-02 20:31:59.905595+02
10	auth	0007_alter_validators_add_error_messages	2022-05-02 20:31:59.91523+02
11	auth	0008_alter_user_username_max_length	2022-05-02 20:31:59.930698+02
12	auth	0009_alter_user_last_name_max_length	2022-05-02 20:31:59.941114+02
13	auth	0010_alter_group_name_max_length	2022-05-02 20:31:59.954007+02
14	auth	0011_update_proxy_permissions	2022-05-02 20:31:59.965557+02
15	auth	0012_alter_user_first_name_max_length	2022-05-02 20:31:59.977777+02
16	sessions	0001_initial	2022-05-02 20:32:00.000481+02
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
1	\\xc68f16bb4ac6c8328a43ea2059b4faec49131d177d490d4af31d62af42e78a23	\\x6f485a1a085fe97f446b66451adca1f6ff55b931eb487ee6e64ee8f7cbb7afb5ca4d3acee20c5c38f7cfa10ace8f8b1feea1a736c0cf521c3226053df066990e	1666030919000000	1673288519000000	1675707719000000
2	\\x47ad02a8c69cd47f05a8dd35e227ff48bb5129bcb55b44a4d8626335492424dd	\\x5c46764aef393066362dc49bbaa54d15ce826c6929709cf64f3061f1526d2df5f8b895379451ef9e678bc5213e4aea5900dd69d1ec66ab21aabccaa1b49ffa0b	1651516319000000	1658773919000000	1661193119000000
3	\\xe8acf0f257771e5fd777911bddf36d880c1893dc3af07164d5ad0c81924b508c	\\x0964874b19b615a99696dc1a5bbfb4196d65896b7b6d97529ae0c99eea5ccc2e13c80c3c5b572df9ce46078c98d0889da127e37d9fba9fac89e06abff42ef50b	1680545519000000	1687803119000000	1690222319000000
4	\\x726368b9bde90c5fec7b3d3770084db2c736c3ef3aa3bf94aca2e83bf4c00e3c	\\xe0e1638ffa4803861c580a8dc5ee5aa9967bbd77885ba8e4ddf4c49aea87a88b9a80e0fe29b9a80843768c68a7b568694efb9edd2955ba455ec295d0837f1e0d	1673288219000000	1680545819000000	1682965019000000
5	\\x99b3417a4235576dd96fc1ecf625c8c02f839f14b3214bd7dd5d2a8a1f7e3e13	\\xea914120053a83a129e12dda4097d5c94423bd1a55cb93327c7921fe1b396b8834b18697868c2897175cbeb54b5c587b7a8d87f71de89ee7a2f2d92ca372dd08	1658773619000000	1666031219000000	1668450419000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\xbd8816912276876ab311c7f654d1bb74eac2bf74739438ebcfa860e079e42e0bcfed965fc527ec83a0b2e8f48eddf1c14bbce174f63bf4799491dec78e060905
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
1	199	\\x1fa895a49dcc46823e6e3b57dcd9c0a30cae46c2908715be2a4b2acea3a3f58b	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000008f166bbf0fc39ac6b1d46f80ad6d09e9271397df3f33a24a87e00b5e2a1815ebdf340a2021038f2bc8d855cb87a5910acc528314fc45b339c3016e442fd1b26a20444aa06c4b52d5982695574cec15f3fd7fa287a0a18c80a06ae16a1862528df2d5b9d7442e5ebaed2a74a26fb0a95288ba4395c75b75a3ea4cf05d0079b11b	0	0
3	358	\\xdb47c6822d70335b30607ee22ac80c825b054b2810efdd1ca952ffcd93e4867e	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000c0138a42a6556b8fd388b98133ba0452ffa9c907e3fecfe3dc167a1323ed10a4048e2e22a43ff98ae7556aaec426cc2e175a22f0435700cda98a1de99a8fcda7fc7f3079cea83ad1acbac160422dba9416618e3a058b6a83def23c7f99519b241ac69ad1aba5369359188be6387a3573eac4a86f8123756d18bfd8413d5c4a4d	0	1000000
6	393	\\x26216aadcbbc75f182255f28b581cbf635fab229c76ca40c7979cfea50415459	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000009b01f3106d1c2eb08b376fab79baf9bad4ca66fe720217f2201a6fc09cf5e4fa2d4fc3e45a0add7164004d5d50e22fc86c0c1cd2e780e9827f61ea70a0e93eda64b567f1cbf87e75a35060d5389e55d116ea3a8e8f61046d658692e561dee7e62f7bcd81d24e3800e87409ba9019826cfcabc7edeb1ee87d35b4df4c68033a1d	0	1000000
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x4332a939dc3c977675db40b1afba3bec4eb37cbd6653599edc4718aac09183f78265ba0c2db1376163e0a548ab2b268085043b7b8cbb636fc5477071bfb9226e	\\xeb64a059017e25c81ca2a5719169a1ca	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.122-034EM9RCCKTH6	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313635313531373233357d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635313531373233357d2c2270726f6475637473223a5b5d2c22685f77697265223a22384353414a454557374a425143584556383252545a45485658483742365a35584353394e4b375057385743414e4734484746565234534454314750563244563143464741414a354235434b38313138343744585253455633445a324d455733485159574a345647222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3132322d303334454d395243434b544836222c2274696d657374616d70223a7b22745f73223a313635313531363333352c22745f6d73223a313635313531363333353030307d2c227061795f646561646c696e65223a7b22745f73223a313635313531393933352c22745f6d73223a313635313531393933353030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224e594245504e4e395a3543365a4b4d34425444375457524439454245365445325945313253544136474a48425034485651435947227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2251355257415056475254423141363848483553384a5131545a4d4231334151395148315333563934545a35323535574e4d585730222c226e6f6e6365223a224a4836315331304441324535345757584e374243384b56524e464d513734304e5248523435303442515043483357584552535747227d	\\x25d7f52fd910d1ef5a2e3d936c450c9802cf5f4dd2fe153c3794fbc34eae04751da8a895fc50193264ac71b56f6d3a863120f249a0e41f95d7d46a78c7696e8f	1651516335000000	1651519935000000	1651517235000000	t	f	taler://fulfillment-success/thx		\\xca90915eed155dc220a34a7cc4a88c78
2	1	2022.122-0205YGEYQYQJ0	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313635313531373234327d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635313531373234327d2c2270726f6475637473223a5b5d2c22685f77697265223a22384353414a454557374a425143584556383252545a45485658483742365a35584353394e4b375057385743414e4734484746565234534454314750563244563143464741414a354235434b38313138343744585253455633445a324d455733485159574a345647222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3132322d30323035594745595159514a30222c2274696d657374616d70223a7b22745f73223a313635313531363334322c22745f6d73223a313635313531363334323030307d2c227061795f646561646c696e65223a7b22745f73223a313635313531393934322c22745f6d73223a313635313531393934323030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224e594245504e4e395a3543365a4b4d34425444375457524439454245365445325945313253544136474a48425034485651435947227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2251355257415056475254423141363848483553384a5131545a4d4231334151395148315333563934545a35323535574e4d585730222c226e6f6e6365223a224d435a313631435456354e5456433837514d4332364843443531415839383733424d4756585154475a5a46533452465846584147227d	\\xdd4c0b8289d0b85eca07dbb7f15d9c16142e19c48fb9894a312cf3fba12caf823a428ecc7d3f60a54af21de0d6b2902dbf9c34e3510ab6e85a38c15a3b4fd5db	1651516342000000	1651519942000000	1651517242000000	t	f	taler://fulfillment-success/thx		\\x9535e79c9b91f66d98453f5f7d27509b
3	1	2022.122-0129HBSR4765E	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f73223a313635313531373234377d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635313531373234377d2c2270726f6475637473223a5b5d2c22685f77697265223a22384353414a454557374a425143584556383252545a45485658483742365a35584353394e4b375057385743414e4734484746565234534454314750563244563143464741414a354235434b38313138343744585253455633445a324d455733485159574a345647222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3132322d30313239484253523437363545222c2274696d657374616d70223a7b22745f73223a313635313531363334372c22745f6d73223a313635313531363334373030307d2c227061795f646561646c696e65223a7b22745f73223a313635313531393934372c22745f6d73223a313635313531393934373030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224e594245504e4e395a3543365a4b4d34425444375457524439454245365445325945313253544136474a48425034485651435947227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2251355257415056475254423141363848483553384a5131545a4d4231334151395148315333563934545a35323535574e4d585730222c226e6f6e6365223a2235303743303032354d355458365a57334b5037344e583839514a57413453315a5646574130455046574a364a4547384351505030227d	\\x28711c7451f416cdfd3150c1f25209a3ea14a953cddf777e2e5a5159b494e3168e4e4b68c3dbf7f7e2b15bec4ee516f7dcd8a83b230cb8928e6ec404405786f3	1651516347000000	1651519947000000	1651517247000000	t	f	taler://fulfillment-success/thx		\\x5f62d7deb35f75c84d74f9f23d594584
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
1	1	1651516337000000	\\x1fa895a49dcc46823e6e3b57dcd9c0a30cae46c2908715be2a4b2acea3a3f58b	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	2	\\x62f1b06e5afe9ed971811988139c7cb1b59050ccc394173a67a7990e5d08bdee7b0a00105dfa0124bbe467b5fd9b110c021c50b82a909e731c982ff83c2ed404	1
2	2	1651516344000000	\\xdb47c6822d70335b30607ee22ac80c825b054b2810efdd1ca952ffcd93e4867e	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	2	\\x5b65de867efb08b0fb67bcb0cc1d778d346a09ad83ff0baf7a3418d59027e85561a888c1d0109d2bd57000b163512ebf247fc05d872dc78d23a40b5d343fc200	1
3	3	1651516350000000	\\x26216aadcbbc75f182255f28b581cbf635fab229c76ca40c7979cfea50415459	http://localhost:8081/	3	0	0	1000000	0	1000000	0	1000000	2	\\x5935ae539e2a1f0f593408241674c31cde642b9536af69c357aba5fbf99728605d45552ce86eb1e90feb41b6a385b6ab75f00f4627dbf9619c6ceb02bd3c3902	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xaf96eb56a9f9586fce845e9a7d730d4b96e369c2f3822ce94684a2bb123bbb3d	\\xc68f16bb4ac6c8328a43ea2059b4faec49131d177d490d4af31d62af42e78a23	1666030919000000	1673288519000000	1675707719000000	\\x6f485a1a085fe97f446b66451adca1f6ff55b931eb487ee6e64ee8f7cbb7afb5ca4d3acee20c5c38f7cfa10ace8f8b1feea1a736c0cf521c3226053df066990e
2	\\xaf96eb56a9f9586fce845e9a7d730d4b96e369c2f3822ce94684a2bb123bbb3d	\\x47ad02a8c69cd47f05a8dd35e227ff48bb5129bcb55b44a4d8626335492424dd	1651516319000000	1658773919000000	1661193119000000	\\x5c46764aef393066362dc49bbaa54d15ce826c6929709cf64f3061f1526d2df5f8b895379451ef9e678bc5213e4aea5900dd69d1ec66ab21aabccaa1b49ffa0b
3	\\xaf96eb56a9f9586fce845e9a7d730d4b96e369c2f3822ce94684a2bb123bbb3d	\\xe8acf0f257771e5fd777911bddf36d880c1893dc3af07164d5ad0c81924b508c	1680545519000000	1687803119000000	1690222319000000	\\x0964874b19b615a99696dc1a5bbfb4196d65896b7b6d97529ae0c99eea5ccc2e13c80c3c5b572df9ce46078c98d0889da127e37d9fba9fac89e06abff42ef50b
4	\\xaf96eb56a9f9586fce845e9a7d730d4b96e369c2f3822ce94684a2bb123bbb3d	\\x726368b9bde90c5fec7b3d3770084db2c736c3ef3aa3bf94aca2e83bf4c00e3c	1673288219000000	1680545819000000	1682965019000000	\\xe0e1638ffa4803861c580a8dc5ee5aa9967bbd77885ba8e4ddf4c49aea87a88b9a80e0fe29b9a80843768c68a7b568694efb9edd2955ba455ec295d0837f1e0d
5	\\xaf96eb56a9f9586fce845e9a7d730d4b96e369c2f3822ce94684a2bb123bbb3d	\\x99b3417a4235576dd96fc1ecf625c8c02f839f14b3214bd7dd5d2a8a1f7e3e13	1658773619000000	1666031219000000	1668450419000000	\\xea914120053a83a129e12dda4097d5c94423bd1a55cb93327c7921fe1b396b8834b18697868c2897175cbeb54b5c587b7a8d87f71de89ee7a2f2d92ca372dd08
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\xaf96eb56a9f9586fce845e9a7d730d4b96e369c2f3822ce94684a2bb123bbb3d	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\xc4bc53a23028f8d21026f07e7e7176f581de0cafb26d3f73087e9507301db0a31e88659125340f8340fd433118c0fdca78cfb42eb9920f50ed8a9926cab95a03
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\xb971c55b70c6961519118972895c3afd1611aae9bc4391ed24d7ca229795a778	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\x057f4ad21723346862205c2817a77ca37e36521585bcd12c1781358426935bfa	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1651516337000000	f	\N	\N	2	1	http://localhost:8081/
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
1	\\x497919a7c8bfa0b1d83cc8328af737efbc2fc8304e2f94d01be746dfc2db2810da251f97fbb8da539098576b9511ffbb46066b1002555a6838fd1b976987b801	2
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1651516344000000	\\xdb47c6822d70335b30607ee22ac80c825b054b2810efdd1ca952ffcd93e4867e	test refund	6	0
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
1	\\xaab4fd264c15497ca138ec28c6ba767f22ce0da5769fd18a9f3ebebcee75bbe7b375f8c52717817f76ef899d34fbf6c17e5c1b3830e0e955919a8b2603e4c806	\\x1fa895a49dcc46823e6e3b57dcd9c0a30cae46c2908715be2a4b2acea3a3f58b	\\x4955b9ccbda1d7a7a98d6978026a908f0afecac448e82211a92556cdeca50a2ad25baef67fa3b64c519393cb0ef77c8df63cb6b12f6a883d90ddf43c2a663e0b	4	0	1
2	\\x37fb5d0d5327304768fc15c6926e1c8d3b921b8ea3b2fc4a09d8179a1c0e411771db0e4743a108a8f02297e1f84b31f16ca264bb510f67e60624b7b6bd7563b9	\\xdb47c6822d70335b30607ee22ac80c825b054b2810efdd1ca952ffcd93e4867e	\\x1722003d502a1dd7f10f144ec49dd1ca0390f2b6250c56eb85e0203d62441126f261bc3e8b5ced7489c35271bc7e988e36169261b57074910c683225af7fd703	3	0	2
3	\\x3156cf11f4fa1c0da8c454278c3c57b07253d2c9bcde786f20b18cc2f40c0992888ee851d9a6d713be96600d30e0cce0b9e170153b9f1b1c277ff6080d95f7ef	\\xdb47c6822d70335b30607ee22ac80c825b054b2810efdd1ca952ffcd93e4867e	\\x50cff39180dff75da02cb442a27c4b17764be652da18726146601bf6c8febab47e01fd0ad28c0fd8f184ac3a90bc61d4f23cb127ba71fe255b4207f30479190d	5	98000000	1
4	\\x8ea1a3dcd194d512f6773776d51bad77b3b8d446343ea7a90ad5479cf76548fa3f2b0f372057008a14fc222db6f16ea62ad041f32eddbcf856d461a7dfa237ee	\\x26216aadcbbc75f182255f28b581cbf635fab229c76ca40c7979cfea50415459	\\x536f114a8324b5442e11430169d79e1a49707d9ef9e1176fa05da3e2b076ccf9112ce18d6ff84ddb7a17367de9e1a424e01b5ad7ddfd919cc5a8245b02307d01	1	99000000	1
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\x75cb05c730d63449fc328f8a5ae1dd7d03991706e2aff9b0274acdadc2d1ada63b6d512726c72f6fa3997a55a7dede937e937c554321cf774e4454e1d79c3402	235	\\x000000010000010077936878b2a5b403179a585328cb694aa08b1563df9ec05ceac2852397179aeb83aa19711df2867eac34fbb4e14cd56c02de9f547476b9856d27be45b422fd1154669e0b2f91e8d50fb4e4c474528cbc49200711f6cc2e79f65a34c1ab0e9ef89626b2a6244a3719b944941a2c04f4cdac89cf0ea15ce5f0ba9d1f2ba525a995	\\x7622e94d0d0de53e90564576f4e1009228ed704a176f2a6c9cc616a2f7902c5a8a104190e35cb4c7a62723a36c1b2aba1b5e980ef7be6487967cd4c8d8ddf9a8	\\x00000001000000010d8db232ac6e422541401c4bc585d48bcf510e46d9ba8ae494ebbf107293b5c857f5d3dc02a9e68744fec47648c9dfaf86a73edc320505ed39f83ba92c311f5cd4a0aa8ee4deba6aaedb375c55e0341856110a1193c4676999ca464ed4f5b31a954a4d687927031ff30f8c8c50a7ca64b01f60f490f6f5684e2005f76446902f	\\x0000000100010000
2	1	1	\\xb00d66dbac9c1ddc4236f05f7c54d04790701630a6f4412692b6a7a597c230752d87641b89f01b14b8841a1f2c9adb084a30ed96de6ce89dd89ef535fd5e4403	144	\\x000000010000010024843e9ed3691d8a4fbff82d95f33041968d2504ec483088ea954f16dc738a7f62e5b4f7f73eb3e131d252292d5856148bbf60e8548f567867f232ebc61a01f1d3326746b500ec2a7473e3ca7322b0d2d4b6dc9c11ba171a60f68d59ad7002aaac907909aadf7a5f85e355300a8df21691b52b35a119247b7b88b0ac279baad8	\\xc2f95d47b7945f80a783d0260577abac3ef38bef15c8c346aad07119d7d742117d7880c423aae3822910ef18847116bc480ff93ea16cd0bf8494ab55ab99335c	\\x0000000100000001c4c107d403aecdbb7ef392ec734b80f6b88ecaa785deef6819d2d92681fcd4674e82908f7ab9a75acf9a08037db0abd54a1e821e969d7728978078721cd4740d67d9991b73d9df0cbac0cc1ec975eccd5c4f239d98b59c89d65aa8c53531a55518b5c44652a12cd9aaf39a19ce841018af6ebb705764815f9cb74cee98adfb0c	\\x0000000100010000
3	1	2	\\x3e1127896ba0fc0094b89db3326b654109420eb1c69f640c5176af6c8b20746206c4df3a98efb7c468728047214bd6141088c9422c96071f4b218af4fa4e8e06	45	\\x0000000100000100506c4317b956c1fe017ed4a6264ac57529f090714dcd64e50bfe6b5b41316292d95b992e38bc952f09b46c8b6542b8c3e8d0dc6a855923960e2dde2f0d9b6793aec50be272176a302a4483778019386b07a9e05bad61cf8f561568f01f4f0327c5e1b997c671d49158e4cb4290c837b5b264718bee6ccbfbdb2d3e87a516ee51	\\x769b5e7d681845ff40539f81e160543b0930772863695c022839117bb282adc58ac919620f08eecca482723e77bac1d8761305e73ddedb772983195fe2f8ea35	\\x00000001000000019095b9cd48360f37ef664479835795bdcd8eb03aceca94ff1425a9dbd02b5da491a73a72ccf3138dbfde17710d3b492c9544c0cc5b8c5c57ed5b3f0f07ea4e7d454111c67008a4c4031ba7a63a50cf98e1f1c2235222329ceb5613359b6bc2d29c6791723d786a702c53e7af9eb3e506f035822f48604aa5d168d754cf4ecfb0	\\x0000000100010000
4	1	3	\\xd7d460835db827709de6d340a2fcf259005fac83272356592ed217deb1523c5447f9efda053c4563b7f5173e5b693b5f8452854090018f78f4af7d654884790a	45	\\x0000000100000100807e7b459e5f7dfde8e02658edb9a8be1d7cf8bceaed76a0376c14167ddc03a15585439c309a39202b048c156804fa004e70299b9d504dd4854bc85852296ab6578c19d0f186ab4a5e96ebce5406b4dac94950ab18e7a7b364a7f520da1e66e642c2a39bc20e5d270cbcd9cf66eb23aab912058d84ed39984e9e1fb2b34bb4fa	\\xb57e800bb30753a52e22503d9a147f1a7916327342dc4e8626ce24a0b08fed684aa8fef55439ee0d2b0362a4dac2011c53b527af99783ce3a8f3d09d142e3cfa	\\x000000010000000158787649b1466bf537e9f24a7f592c7a6138784ca3413f3eee69e8eef311d3e2cd34a5c9a04aeaeeb9d59f9a175a6bd53029f6bf036f8f740d580072e34acc249219cf4465a5c28a19b87be25329bd49ecb18f0743e62c5bf9ac6b9a2b551359758800f89ab595985c0b272dd74a0551ff6738b9b5c50aacd340e4fdb65a20bb	\\x0000000100010000
5	1	4	\\x12a9648cd80ee62fa0bb1bb94f8c5f574b68118e59a4ca70ddd35135507dd2fcde994141eeb9ab50518e916f944d38ccb81ef4c70d458aaef85f66fd378f0009	45	\\x00000001000001001329722f0432d5ab1eb3e1cce2a37e3af9ccfc92d5b795e18f532a7893ccd0e50b6f6dc77f17e8f71a9ef3a9b356f6ab7626cad37025e9899a400b87e3b556bd8d70bdee050ac252ac67c720139cc30684e5e704ec93fe5280bfe918db9b39031d67868c7d22197ac8a545d885961f65d1c027705c68ddf6cf0fdcb3899519e4	\\xa44577805b3ab2fc0545766b36cb48ba6434b8e12a0151e378b0a0bb8ca686183fd426069b5a9eaf57e2b4ef35f13a6f4f3a3153fbc0d185d8e3b53cfee9f4d3	\\x0000000100000001616a4a5a3e309c8bd23654db70f6da4a11d77f488043a5442482446840bc99012696fa1e60094ca10a3887b44d85568c4f096e3e973b09d056b91377d3e63ea152fed78283b33a2ad1f208c0684bbfa83979b5e042861256848c845ca61ab3d8c3e92024319b0d8a4568773cdaab389b8b59da1991911018b67bf6317c2d01bb	\\x0000000100010000
6	1	5	\\x8029661fd2ec7f47b8cc28a9bd08fda5e874643a8af215aae67da4e45a974aa51944b3b91cf8dc574db3f7e507f0d0f41dbc49093a49fc3e5720081c69e64f0a	45	\\x00000001000001008fd135282614113528016ae2d5c79ed43f8e4d51c376d2265ebd67b22e1764a92a3d7f81c08775c2ce0a7268e6679d8ae2ba5b01548174a79403dcb9455eee5870c4bdc2031bd2c246e00dbe85c09cdfd88a98d8461bdbea22355d477ad2fc769c3902dad49b637239f0798a56e67d53c4041dffe4027da609527daf5bcaeab0	\\x38f1703770edb3c59f454434371e8a0f409b89fc06e7dc611cbffbc2e1ffa3f2c0b2363bc5d394bca58f4bd72173d818417b93605bfff65397bef011ea846edd	\\x0000000100000001a861b77bf19f26d453496f5954624369861ae5b8c802d289c402c2b280d5f45b00f9491913c3448ad851a0e3010c3777d46401cb1bd6e38b8a6033e558a4da4fec445f6db0053fdd440aeb4691c4ef8e671dc1503b4bc558ec641fd20077d4db51d78cbf3303f8286740f3dd6234643ff7b5ad2fcc451eb9f4cf5e1c86054817	\\x0000000100010000
7	1	6	\\xa62c28412aecd93405fa41d8f71181974f7adf4fd65e1d3330215433449ce5de4de505e44fd113232332271d6f98c7e5d97e53a42060e87566f9137384c8590e	45	\\x00000001000001008283286c35075709835d943cdff8b4ccaad18dd098e7aa50c7ac0df27dbef274cf61bc5ec5bac68b49cc0d6956eecaafd44ba6338b97f970f286df2b6a6a0964824c5bdea7f8bc84fb58e66c3adf81182f36561222c6d0110766a923ec8c6af9227830b27da4f7d5adf21ea7443c055a718150bb80b4585b8beea7f1e460b811	\\xac5330b3a561540d59f64b2f990502fbdb40e5b4664da3d46ccf01b0890881b0f05f34f1c347a74c6121442a131c4394e32465a60baaee258ed46cf7c9a62469	\\x00000001000000011d532d0efd4983a8be9d74b30adf08441ad00cf0a5fc410e2c4ab3be4e93c90dd12b54c1d5ea092dadfcf640508b83534497345049a79f3eac087a630699ffb3076620980e900f4c6932235bd0469b7ae477bbc15ebcf886830cfa9dcec199267d43d694ce674e69b4fb7aa6e4d9eaf4ba497e46d1c0cf61f7de03df48a63712	\\x0000000100010000
8	1	7	\\x23068705ee025b3bc7937a65175e3a0bb811a3cafca67479cad8fdc70b724a5ec230b61da668bca7457bc8fb2b32978025192569a985c15813e99100cb18580c	45	\\x00000001000001007a5ecaac18c5cd9d5fc357239b33e10e72835014486ad2ead05b1f760b4d91d4ea91ca5867a0d67e0372db9d380a5248df1fdc95c7a42f146b46e2e14e1999d073775ff0272fa1e30a64d129ee0e5a8d99460ec7902bfda595e36a4d74db7dbcb8d7ec8ddb70157b5703f735a2237d7c564cc5ab733ad772c4df6b32d33f23f1	\\x2c0cceb1d435a03efdd368cb998e5a798a5dca23764d4fa07aa50bdf57bb722b104857142403422f2a4439b9cd2d660127234ca123200604a80bd8070570a588	\\x00000001000000017123a15853e086e535e56c137232bb6032e8e6d5d63e7f27a2177b0888be88598350aa046c046199f285050835f6555b9b0dc46888e2d4450b2d878eb01cf366b879f61999280c3d933bd13469227abcb687b0725713ec41ad71c080c8724934be04a201fcd58683a41048719194384aa0c994e407a054624718cc312bd28424	\\x0000000100010000
9	1	8	\\x25455a9dbc8e8d250293cbc0479cfe4791fbb3b0eafe7704fac5650fbfb2bd80408f090cab2b6de48d37646b7eaa5ea4fd83efd6e9193f2c8596f6c4a8e1cf07	45	\\x00000001000001001802dd4f17cbb1c3b0e55ca8b1dd218605f4fbdf27e9797e9f8e27cd62c2d07f14a0a516fc7127d8b408cdbfb25af8817384afcde755ef99b4d7ed2ed323eb104839ea924c2e10a888f3c1b10d6b239808be26b27b6f7cfd8373328455db502446d4a8b950e787f35b4ab16676883d61e65c30417dac787ea39348581e764850	\\x85f0e0be1240cba1983cc543506c6bb8735a2d0853f7082daacf7bf5b9cba3f972a2a665a2f69accf1802df568db30e82323deaccf02056262bf82451d2cf449	\\x0000000100000001a7e7663fc189befd11522d6ee5da0e492fd34c0c1b6fe23ef68446a12cccc48c09d0d10422b7f7ecd5c96bd62ad57771ac0d844f98be2f0dd698c2b505b197597c76c3655a95dbef4be4803125e76830bbcdb6f5f8b0e9e71c621f461eaa92cbb0d74dac3fdf5a2716a77d3bfba7d0dc35b55debfc5256aa87a025235ccd138e	\\x0000000100010000
10	1	9	\\x26da52a57863b47861a18f3b0edb93ff578d9cb706381c6fe0bed79321f84af252eec3f609a624d89fe5bd6e73a127dcacce12384528963459f1d2ae03a2fe0a	45	\\x00000001000001000aa9c01793cc1b5067eebc0c6110fd319bd970eea3581e16ff5dca9c0efdd1f9476427d6d914f4ad32b9a60e1376df174ff4f8eb640d70b390ea6536a74aa1010d0119f1323b93a66e2762fc4f8f1ee99be7631664b786a9c708d6c6e5bc5a77731aa8995ae46ded1ad061476e3ff7d7a09f95c50ee46cc675898ae8da0336b5	\\x5c151a8cadf4b3df2b7fb54fbd4085ba6ff4abee8f3426bd0d6dc95bd945024737f454dff91517d13c95f7094506626bd1cb9055da1fbd6b6254f5603a6cb52d	\\x00000001000000013f98a4e41f9a5e29d74d13413933328e02145ddc1a6213af8a7b92cc0ad4de95cc36aa760c77dc7aba850e21a3eee8f47a2842ecff105bae8fc298e0f5ffd4474e77401b3bca73b59c47a3b49917066db0d434ca48f0472c6199193b2af46fed6c56082962a6e21d75be568f9b0ff4312cff4952bbbd82164d2eda60debf8e82	\\x0000000100010000
11	1	10	\\xc8277985c82f99b513465c0d4e83e87f84ffa56408b929cbca41e1930ca2fe397656457c883af065f677bdf8a7e3c2f0dcf5dc023703f2f4f2218259ab9fd30c	145	\\x0000000100000100992d4ff543651c5983e7cb2920b25b51a7e79b2738953fe39e2459b0b45e73f88a56a9aa6d7e94ab8763920844c567346aa72dfb72b431a2adc212b9230cd3d7b87d1275d131787df9a7f230b94ef4a098d446a9e88fc34b3a6d4549d8faa7a3f09a16f394ea4983d945618d9f9c962aa3636962bdcf767d0fc9054aee85c1bc	\\x365383b9bbe8f9230308e91dccadc22ec7c1a998baffee9a76276307e48166394cd69e33a74b62d0cfbf448ad0558da3be19d295d3c480c2f191b9db460de119	\\x00000001000000015ddeaf04595538428df596cefaca747ef3b16a534c733c3d2823de08e0a037a8f26e0563dea847d293750748832b22e26d3190148737e0ae1ecb73d91bb4e5275dae8477c87d61be53de523ea50e421bf527279ff0831813330ad960fa4f9cd177dc6e92bd8473fbd0f82cb3dd10c9fb338dd9a52566d7b29cfb61401d937ff6	\\x0000000100010000
12	1	11	\\x2e58072126c0cfd10df2de1a6415bf56d7d97f2b16e1c459e18a07afb73b05b95b042954e43d1de64201f0f6ee69ae9846c5368790773131111734e5a16d1500	145	\\x00000001000001009498ec0025dd357781d6019b5ff1b411742109ee0f2b9698a3d0c24a89fd563346f67d05d49be420ac3dbba8ef3cab59d3d3b23d2e078e8a24448aee27cd4cb9365d674f18ba50c2cef16108d3483744165f7d95a1e68fa5db3eb14af930dcd42a1efcc8586be5bf17fe896e6e2047b17405b264dd99ff95212a89542e0c8c1b	\\x37bc5098a08c9efef3b6cc15fad91a7d5a2c34759db45c0f70e67980f2d2882608e00c91fe1827e8455f2e72a0b0edcc1adf7c10587d3b581294eb72e25fba0f	\\x000000010000000159d5d07084a86c7fa3a52daff4848c450317e6150ca0042ac9578cd89e22c5e19bbaba6ae76db7ca0d0813267fc026073b50f0ea0213eac38155ef65b7b9c159344433155539d522302768a4485e2d12d0d742cc649d82581519f6bd55bbe1ec34bab2a2005c48c01de3fd9d93737fc62a4db1393fd530bbfa1fab3bf5432a00	\\x0000000100010000
13	2	0	\\xdfe4a845f5126062c35bde1c68a90d794f0b7590db0af03f8eba987835ccd00c81caafa2ffe80ca7bbf0300d10b94f0866e3c5db92ab6540365d1575b7025e07	235	\\x000000010000010015db3f4b8e13611204a7f00d09a5d610ec21fb57b67dfb0d6fb00bfdb378440078de5c138e48afb6da7862e4c24ffd4a05ff07f30da1af486497cb8f7ab38e7e6011a9b73aba51d665cd2baa76ceff3ca8fd4c73bc06463110c67b320cddf88bb9746c79fdff78cb675e43aa176b4047e13ff1c9b80a40d85899c5251293d1d2	\\x7baa3fd9fc40a860ce43b0caf89aa555756ad263968eefc6b13bba95f7c8ff514dff12dbdba3bcf69cd9783fd8144eb0d24cb6785813e56975c89d476b598eb5	\\x0000000100000001117a585e5aff929bbfd69af3747c54694ce321f5ec4299a6f38af5f058ad7f95c92af156c567b1c16264d00d9f5934d08d8ecfe8ffdfbb4d21888fadc39c6c799143017ca374441ae9f6dc8d1557b2336e1a00188a44e7ebf16834c075347a98ef34e2d49c839baadacd24d006664788dbb57e64789c937ea8c0d47b38ccac15	\\x0000000100010000
14	2	1	\\x7ee45b4b5ab9827df44079d14409b403437a7c3baeea6aeeb68675b8a76e4069c9420d4ecc1695e0c1c98815d7169a09df25d049caa504710ebeee08781a6308	45	\\x0000000100000100a4dd31e73376c49d7ce0532ab1fe7a0b24384a761b51e05aa89da0305553727d762cfff81ff4e71a1a685d61a49231ead41d552f53c5521ea04a828d836466006391f7bf337b107394767c4698f704625e08acbbf13fa5a24d6ab5e506bdc667c0b08b5f81553fc7ba91f8a67e54de69971947405db3dd1888bc219cfcd86ce8	\\x7e83790578a7ed662bbe005f4e451a22d60b92457a9f17bb46d639bedcf50bea7e7419a6959cbf26fba3d985d735dc2b9f39e0f1b81e4f37acde471b84d92989	\\x00000001000000018bc20f8b32e0ad9485e082e05a9b33efae371678de0e670903aef555a60a0d0c3547a0a4ae1feb7b9e7bf7efd7be07c327e65e854790d0d6881f3666d0de98723e873873639f22c4b9e7a77fd3eb492c88492246ec43e6e02879e8aa421b32492f1781efe2b258711e8133295f1f381ba607461d3d0b8e9a09f1cfed0495cb63	\\x0000000100010000
15	2	2	\\x096ef8aff103081ac04c9368779f95898f99221b989d4677469c2ca2f2251b9f6092c05a90ae20fd4b648f0a8a7db1699f883e622e12da667da8b6475b1f2302	45	\\x0000000100000100b10016edf7f7a0e8043b8ef08dc6dbacdb30bd13e6d742603f511ea08f093f84fb1ef8d65bf3527a9a778d7ba9b352d9156e0e60742ea5e2a8d27015343dc505dbcbc8792cc96362af814ce5f8cd82ce641dbeede32f46a1e2c9e21100c825282d534bfe0450cb4624213c504242a2beaf3633f52234ed6933372886bf980f3c	\\x167cd17265f812552104d7da51b714b5b7d437e1fed09e3e24e65cd59eb04cdad391f4f3e838c6ea6ea419eae503ab4a3fa326bd6bdf3add0118371521521dc6	\\x0000000100000001ab21e2136eeac67f359fba5580cd00d37d72f107250fefc8d5a6e425686d8c69b1ac8131af58bdad9ca1f6295fba34e1088a124e0c8cdff1cba9259eef9fec23e93ff30b68ad17b1d9a429abf21d7e8c3c86d485277b1e06544660008a40554350b8848ab90b7be32aee52a0a1fa2273be72a56d9ed1a6d48d20c840e014b890	\\x0000000100010000
16	2	3	\\xc1568703de609c71596b5c9f31e3763488ef7cdc16d657678efbeb1b30c7b65122e56c00a4b7971897a642aa542d8b2ef0166604be61259008f5f0e2cf439207	45	\\x000000010000010052a5067cba4f4f17d751497a0217d16284f184af5172138d6e9f80342fd2ca0a5f0b7fee074a32db6ac4d565a7fa26c057651bf05a3db8989a290f407a81c3737047e19869bbf8da6f4510602a75a47ea6955365c978bf95d8c5d3b537dead42914f5cdd288b3875586fdfde27c9e4ffb5389ecc48064caad3177c9e2b0ae8b4	\\x293f76951fe21f9fb7fcdbdcab9524a4707ebf10ff3cb20dea1103f9cad1c627768a6ba8afb4ac67a32c3cf0fa312257c74f6f8924ecd1e30dc76efccf6dfa96	\\x00000001000000017bf33709ab38945790ecf8fd4007eb618f2c219ce3638508d16e139b38f99576567af6f4845076343074dd5659ecf846952dc5a2673c218412314509ccb057f36066450f7764498a65b50691c5ce0b166de462e717b1ce661080f307fc8b18e571a3fbed4b0eaac41b57c783083b1f212d629162c66293b59dfe46d2b71ec307	\\x0000000100010000
17	2	4	\\xfdfe84da6f6aeb9d1d6ab5fa38937105b5da3d3bf14262ba2095c470c625e116c83d5f032f01110800118c799d48577598c17420aadf9e2ac12d410bb37b1f02	45	\\x00000001000001003199ec5895c65c5a896fb5096fa7903bd681dc856979e18ae7db08c9461bc9b35446ae958f32e3709b53aa94b14a7128f8e43759e14189524f6422c26744aa4ed97ec6e2b9a49df494e338d7da7ee7b73b9486f55218eb330c36757c2bce51046db4c25ba9f0a352836c8f7918f26fb9175bd4e5d81fb21e93e3887ce4577e66	\\xfc9df5d159a3854dcf5793a3799b3ef7f515d5acd1a31e492575ad72c6814f3ed0d5f0e453c75a75219462eef6504e35b819979d58b0ed51e0f0221f8b6e7ab9	\\x00000001000000017d36e2b112980afef2ba690a14b4debe6a9b4caa6a861ef8e65e8f26dd0d8058a385e45505ac85c6c1225dd8546b8429b20220a692336de10cb94e050d36951bc86169122b1b3a08edcdb58ea147bfa7e3fef3111008a2d510d59f2db2a6523e44d20dde569cd1fd2bd670d7864e484edc3889a42c6b1b9a3bd6980ba0b67616	\\x0000000100010000
18	2	5	\\x1b7b60bffda96681f49ac35297fe4f046e907b6ab6ee23e092a1a8794ecd9ce048cf9b02655e7493a4fd1c491e01568a8d4106d9027b1def6a25545bceb25003	45	\\x0000000100000100748fd0756093a0be093e1ec8cb438dff0b1ee26db2fe7885c75dfa4d466915b35ed50a50200c7674cb734cb774962b6908b44909f513f4a3f180bd49368084a56ee4e0263ac93af654440aee912c92c558631d3bfb16e18aee3e4a109d5888b920c1bd4b80731e1dd21e404c96b28cd02eb60d87817743ae70f52bc7260d0c5f	\\x1a9d27050f9508a1a1410f32f54f3eec83aa7e874262b60b8e3deceab1cee46ab80245efa2e06095040faf2f3ddaa4a20daf460c1373eadcd3054d511ce0ba25	\\x00000001000000011f817425456ed2444c2c39fb15a58947d212edcf05b31a0a7d6c9ea11949d34407bb43c77be83faf5ce3254e49541180fd71cd2200cbc265b86e381687022ce0794809f498271488f356cc70dc87af80ff4ec6cba4056e40ce9f4c9a81ee172e4950e8e74c9e0f70dd949d0a005dc781905f0bbf46ca794deb89bfe6cb57c3d4	\\x0000000100010000
19	2	6	\\xe8d2a9d8ea6b40cb08a5b581fc72a2615ad93e712e45f2934839d7b9d4fb800431edaab8c87ce7fdb7690958ce93222193be44bd7cb8bd977db72ef0fab83505	45	\\x0000000100000100515b6dc148d24930d47ddd772be06c6db7a497bca21d997fcb75003791db1f0618ab3c0b9f7d80b92536541f25a805f2796c151d3c26707a8811070762388de235bb412c034c6568d95c82b94c9f9517fcc4fb7ebf94ec42fb2d0c626ef109ef6f7e3276e5b8982f0ebb27fac7ec82d0d091ad7a1b8fd9f570928fc36f48f141	\\xd45b7dd2d9681123fc3f86f3698478436d19d4f4d598e1acab938536e8bae968d2aa8a61a75d72d0d86697ce089af18c5cc087457a7c16d87006fe7e9510b997	\\x000000010000000196e540a858c244c70c2ee72afe8966d929a2cd5f2f3c2c61c2f4a5695b57461b17cef39e047ed276be85eb0654efe7a4ca34e877f9850f6290732b8e916d728854e4aee3af8de2b26e2e59e173285fdf0a6c391e3334a6eba94075dbe73638e9fb867da833beebb46a94829554e55a8aacd5175117e3f13647ba516ffa828524	\\x0000000100010000
20	2	7	\\x5762745f3cf8b882a8c0fa11ca609f35b01a319f08d36223c85ed4de483dd86dc17d53c13b1528ac65178147e0a63f23ba2a93e5b8875d17bc7736233ea5230d	45	\\x000000010000010046cb6534af59af4a40c182679635aa5f362ed0ae015482fe6521c71c52673d530b23afbf3bf27a4291d4ea6ff8a1664934200af5a4628e89826a08db3da7a533e113ae7317e9a8afaee4ef26146cdda5de090a93488c41a18284156dd545258b80877bfc16cf66bcbd67fd075743b4dae5d55406f71ef7343620953cb61e3915	\\x13cbef26c16ad683a07dca5d22f65b16c0d8b526bb14107b21d58858cd8d62188ddfa54400d0967456f845e306df7d50952c0dd361eec91d6958bf5a5de5160f	\\x000000010000000189c5d9eaac94878f16291e5320307e6f69b2e29d3a8aba244436e4920097bb502aa086c8f8e666169c80b76188ec57a87d3aa20ca1c312cda82520fca9de33d2b181a4686439bc2a869dd2b907d9d8536fabb5563d1911b83d03aeaf86b05fd5947965fd79e12c856d37dee92ac94f00cce5161f49e36f27b1640387fb339e9a	\\x0000000100010000
21	2	8	\\xb3dc3b4829bb480e3763c02f07f53ab2b10f532b8cb7361a8889ec1425203403895020a698cc68efde2b651d9fb6ce5292c0b281c73178b70887c48e9b59e90b	45	\\x00000001000001008159b5b09a06da283c431e503b520f62896aa91820199bdc83bb2b63bfd757aee2dc0519abaeef14fff9defe71461bbf118e778952304a68bcd20395e71935df7eec7ba15d87cfe0751ae945efbf1981de3fdb88f7aecb0dcd5ddd1a18bcc01ff8c3f7999900c42621e126bd1576b40e42396f3f9f135058686f9aba239fcdda	\\xa04a741196a194ef279696c037fea9da87746331f50d656e98f3382423b2d22b51cbeaabac5151a7a725bd4acea5002941b917a026afbdd0a3be45097bde9098	\\x00000001000000012e147738e56debdc65a3cc4dbde25cdfc3c7fb61060557d96275a6634f0b07b3834e344e1ae4a1afa3a9cc2e631073a2f34e5cc21a154e61cc426f934120614b2de15b18b959e4ce3d5efdda7fc700a6f0f10e9944e6fdc6fa4269e511f830c1fdbcecd5530d174e7b1266e8cae5030b4ffa371b5a552bbed8acf27307ad38	\\x0000000100010000
22	2	9	\\x299e50501e120ab617fb066c5a1f7af406cf7b662ffde992450365ece92ad65319780a1a46dffe33afd9b11fc11151bd13eb909ecfc3c4a8798d5182a5fc9d0a	145	\\x00000001000001007c74f7499d6a6f2a492f08b533f9440c37b1b848521dd65d0b3f90ba9b0e3e8b27a541f1efcebf25f0f22305945db3485ff4f5dafad506bbe36c42afe251acdd827a166db82ad1af84422be1ea21edc96643c06d210bd001f3676eb7c1b7816270ac173519dd752d523ee906021058ba811e04be3526cece8b750dd265b28061	\\x84071be50887a3281f4b504a3bd959341c2320ed1b74e75be8c543f8905e4da1e2e2abe71b94a5df8ba005849836c11acf8dee0bda86afd89392cae97014020b	\\x0000000100000001385337621e9f1aec2c4934e314e86d0589a4e2fcb8a80b5d41dc81264e6d7a972fd348022c64e6dad22a107e7c9ed6303953fb1abd0c6feafeefa774ca077b641a16818164758ef4b33edb68d2db5e169191e672d9c9de9bd5e1779a59090223f2912de7284b03a5f4f0d4cae315f3ea5f9d4edaf4cc924e40ac5bc1fe1f410e	\\x0000000100010000
23	2	10	\\x3c8e85a7b59937ebea0843a80ccb9fe4def3591708edf9310cfb8f4621b06eb2febe478135f731060704ba767d2dcabb2bd170df68ad813fa367ab95cfc38b0e	145	\\x0000000100000100a97ce5d9c17dae9ce74b18c16b95a1b87bcc133e399d985c527244b4f5a0b7d0b7fee626f6ec01f4d8f11570f5e8ed86a526bc3a426357abc32fce46a7b2a9a5195ea979798237122fb636e16292fa1a8dbad003898b571815a26d4bace8960950f5898b941d4cf455ea8c8efa6f8f5fc233beb4679068edfeb33d187fe6b299	\\xf5a0846c05597c409f4eb72d0a84f8756823899ba1038e945022c98b81034dbabadfbe1d3f09b6e059d1098f22baf358bc09b29c48664c87aed31ff9bfeff162	\\x00000001000000018c6bc8de17e1604cdfde5ea652a6cf82faaf0f43a100d785510d235e1a6c2b83269513e9c4e2dea22195f8c44de3bbf8c30611846c00ec9abc343a393ad062f210a2e5718dd0c4d8bca735b1e59f21163e32bdc8eb830c42d854cad77a5d85943abec6ec5880403a02bcaa90b11e1c46b60fed91427fa967e847753af8ae15f9	\\x0000000100010000
24	2	11	\\xa112af33f7de699f63675c578358a72b5ba355e91a5bb981b1278b2f63c152fa51f1d2f85d24da11d210817ac74d8aeae32395637a8a23962ef0e538fd44330f	145	\\x000000010000010001833b95e8091d32d39d85469b5f84339614bed029537f0ba2b3cb016a10bf40da9b4767ad0367c6610ddfac6a12b9a34772217704f5b9c586522231c78cb28053ca2f7b00a3f841c2a7ef1a23b1552c2eb98570c67bbe96031f50e0f2941bbb7fcc60cf326f02e67f4c81b28e14a773fe8ec0bb48e6e5589d62cb14ab03d5b8	\\xf7306226b8bcd17d048e0694e3d8730a5166d43daa52b1e2afcd44f627d5232a92e618d9984b02cc7d96f9e6e76941808ea6a87dd3e4237c394746b2b82e6341	\\x000000010000000155dd77fb900fa7378e26e93be69d1fac7a8328497a8b7c9086bc8d8cf228c1f299d00ce1c3169738b66eb850813b4a717aba58e83bcb86669c55efc17e7a1687607bfad0f983511d7b072914b6c8a0246a5a7efc48c786f2f53257ca9e8eacfe40014a00913c743c9e4f027032d474e30466263e5f987b68fce1ccfe915a0aa0	\\x0000000100010000
25	3	0	\\x4287d29c4563c8d732470d8354440e40c936d0ffbee517d9aa76c914cfeab563c63c8133da9e4dbfd69b19d6f77c1ce018add66a94b1408e1576a3d02d551501	393	\\x0000000100000100c91d509f553a25187f87e227d416a02497870dbee0a3d54fac838bad3fa52f005beae495cf7330084c5fd824dae61c3a234f196d3c2632bbfa7592b88b0f6d08cec916794b8aee0abd4af9bcf6e19b751c29af733a42488e9fae99726739d9ca1e24d0347b52e6de67d427c4d3919cc2303afdce48c6e5df173792bed9872847	\\x90f459c526f21530364a828f0deb9fda7d6559d1bde17927139723538116572d7c6436968317a73e9dc79f4ddf5d81faa5d93cd56f9b8d6b138aa3edc3be36f6	\\x00000001000000017cd2ca97eb075bd39c3cdee8624134b6415d1053e8a1f56ef4f3d8d35ea278cebe93b79be50d3596cce622c194b6b12136ee88ff7d99706ff5d95e86e9d4af298536ea44bb1ec96274329628b2e569551170117423243e99b9f94009321d716713e452bf000a59213a33e922f7334dcbbc7a1addf539afb8f394a7c0c05021dc	\\x0000000100010000
26	3	1	\\xffc85349aae5dfa0befea5ec60edd0e8e5a21a40aa1a95bdf7701f09f7281383c9ad037ff925bc044732f3f952d35da806e3acf53a97357bd41d145390ee590a	45	\\x0000000100000100ab8a025dcef1c598aa21739a49b0be005297214d2e7e832c719f7f54e3076104e35a58aa85bbe267a122a37251eb4743e0dcdf22a3ded81c885af04fd95720f2d3b9ffb31fd8a3418b88816173b0855feccc266b5d3f1102c07410c83b4fe716999ca181abd577f92794816d7ec89cf912fb12cc59887516373021ffe5516b3e	\\xbd7df3b54d992492068623db872786edc9541f1dcb3c73800da8071e0b8553df9608db99d517f4bf1359e263033528248436b8cc29a7a4975e975b6ef09cfcff	\\x000000010000000140116c1b6005ac1e492d0c67ab76767a2bbc600f3f95a74a7923c2760fa30d7cac00e8a67568dbfa8a40bd9e66a116b943a9a4b9e7078427bf1be73cbb1e8cffbec8a080187eb5c32882e5cd7fec8e023899bd0e9f5704008853ffef0bdbae4eae5c0675197989e581a882f699c3c0d8c295751cc9e310746e3b4d41382ac10e	\\x0000000100010000
27	3	2	\\x98ebfaccecef5609ee754b6fe38c27fb131d8e70c056e35e99d0a94aaac6fb18c7a7fb13d428e9a3230e341048c93f08891b579fe63c38ff7446ec314a729409	45	\\x000000010000010023dc57aae00d04f2d6e7c7a8ae18651eb8b7aa8de9502832069566ca78665d82e675f376837d4e71ccb74af1b8737bbe5d5690be924e87a25fe87ae92b873ca7a9fe050564588155b012961e70dc5968d72660b5dd738bf918282addcd7f95fd7b281b901540a19020a36e180593b3dbf4f4ba90cb4ffe39f4c874bb85f55f04	\\xc676c05522b1fa1ac49f618ea4f4c65abf82b1d77bcdea664904122a38a68e3d838bb35d009ee024902c8f558406a71605366f800b6f383fb5fe811e74934fdc	\\x0000000100000001358cb01bd11cc275fd4ca67f6df4bc400dc1d932d2b61dccd8347b6efe079ec6380e0279c14923350bdd4fb8e32a8cbeb0f224dd3608e3e14f40e59b2a31fc7f2039769e22ccaf524f5cbfb5ac82f18e955b4d99b52321e35c3a49efcf264a48793f112717199ce03bff4b0732d61baf6d1a20c388bfe1337a5fdac1cde7a2c6	\\x0000000100010000
28	3	3	\\xa6c4ad8a55f0faa049b02b1af027bb915ca63318c726ccb3e5702efcc03a36e8849213674077183c92ba044276fd98041eefdb25cbfe619089b014c96777de0a	45	\\x000000010000010097fd09dfe1f96b505ef708b74c3ac5388db4b9246b1abfa279109eae4439279c523ebe49aa1305678862a53f790f91cbec6862877acbd2865a9182624d87450ffbf8f4a3d8146d003ddc0bbaf9183124361bc73c256d53edacb0cb23f46752fc0456ec8c175367e5a47fb5e14426f693e120c632174526e0a263df0f794666b3	\\xce7b2b1c04bf293e8ac9b5feadcb2e275397ffc54f17a2c64b139ed3a2bd18fbeeaba75646842de3ab381f5a92bedbe497d2daaab98b949798c9bbea513d705d	\\x0000000100000001aad43ae985f804fa607e0990f1193eb1ae75fc5623197a8038bda7e2dc19285825722844369d3e3c5784ef76d628010d411f4782122bcca33f78d2f948f13cea196736688c71ef76f28e6b2708b3fa678b8aa5bade83b0292c8881d8a1bf196cbc48d4d32bed799107fa6353d14be5e7f8b4a7278c937012f590e76a46eccae6	\\x0000000100010000
29	3	4	\\xce09c5a53ed43215de3e09a3ee39b3e3835ac3d1c31719086158fdea7046f4805d2a4206d0a62bba50bbef3035aa69d2d22e27aedceec61660d223c9271aa403	45	\\x00000001000001002d129a0717ce98c376bcf978211b17c9153371344eb21d94d214e257572adca8a4e015d8a07dca7bc4df99ccc0ab8996a5e1914b7cec0a397cfced5fbbe08fa692cefb1f8f7c9329adecf0a85131887f266803eb35b7871b9fb0945ee3148653e691e82c8fb71f417d9e5ce11c305ad5f4ddcfa03e4491a5cdf08256e9caad05	\\xedbc3c5f54a916877963ed1ac20283c5073851503dd050e8c6f99bfad603d21a2cd39d895b2fdece001c56b2829e01782778d2c6024a2009ddcd5b35d09586c2	\\x00000001000000018ae2b2f74b85406a6645ed3a4c5231984a72b1ccf39d281b32594460f4f86baf3296951cdd401bcd59611478996916adbd057a03ca3295c2c95aab1b832c9816450a309c2bae1e772a81fda6a1f04449276456f3dd13b2abc86ac765653e0412b317370ccbbb7892c95158767f253a75b881aeac75f2603bd203807e235d7ff9	\\x0000000100010000
30	3	5	\\x28f882118955ab2684f63c3c2f359be94c7a4917ff7142f9382a261aeda3972de9d5c997c1b11a7238c197aa961f97f79ef3898705400463bb2a349f9e8b9206	45	\\x000000010000010065bb0d760b22264a4c44b7229ba5e457f186f7c7b041b3977607e7151d74c93043be6aac0b5a0249d295c8f9783cf8a2e2ac791d58a86b23cb6d3412b1ea6b76d529eb2b6b8f5f7fc02d074eb5c99e34bc4af399a76e60626c575e54447c4486947328a2f1184ed304cf589907611c795e9dcdc047536c85831e9d4a49d977c8	\\x3437f776358692b5cefe1eb04e99d47677ad0f36c9c31bde9c367fca9c9df5bb42c0c584175671a55b8214fa529d99d93074247112c5f1c863e4aba10a941a69	\\x000000010000000138a0dbcce423e5097ca41290401e106051ed40d48c0718b9a1413aa37eb07be09d5e1b79f641d64970210782271891193301393aba544428f0f74822ee2e5e4db577b9784408b347cf3ebc7432a00fd280871a16a986b8e444412aecee3501c41a49443c0f5fd6615b988e66f158cad65fa5d16cccf606b9d707ba87e28cb635	\\x0000000100010000
31	3	6	\\x028a863ca7c7647e7d67727415768337e5954cde2fa9abdfd8cd42677d14d7ae18870283a0074c526c5aa488e2be27c41692c36888a523bc6291116be563520c	45	\\x0000000100000100379eeb247f3550d807c554c3116d47135b536f03a55c6ab8402c339d6e43a42155a1800ed6e8da2e0931f6991ecde0459baa9b1c486765c481302a5415769ddaedba6dc57b050d8fd8883b2f302368cbe7e39e4e7a31dd813c56b2cdc1b916dc5d6bf29af1542ce8ca4dc351e00b1a98762679934a9b28531da4f8e3c1d85895	\\x8bf391b76706df44b2114617335d6ef3431224b7fba09076e7773482cb25451528782c3bc612c10c0c969f6e92a531475893e6d53dbe654fa8e2d05867639a6e	\\x0000000100000001782d6aad7045cf31f3bbfdddd7f3b232b6c91f8ef8d5839ef4ad280bf88f57eb344ed7c64da5f9a8d1728f5708a7224dcf8389433ce6e03705c89fc3feaccbba24b2b912ab73ef0e2ef38b03110e2b748d32eb5f058a971f80fb9574f671f593b8e6ac2e66efc09f7415e0b2662c29a6e53a527a204963e144e15618f320b8dc	\\x0000000100010000
32	3	7	\\xc4b724d126ee14b16358e8ab61030d8bdc631fd90472ea6c1538ae37577f2203b3f8451e29c40473a1a6fadd9b8021023a0796912f0abcfa9ff48f2eede85e05	45	\\x00000001000001002746bd111be97bd8e30a1a75b79e400b31e8aee2b51b977ecbdd407f3dc9b69660742278006044e6e5778c0cd4f1a3ab1223f2acc6bbb930bd426bee7c505402eff070ceb6936ff52a4629a1488fbad9d3aaa9a59eb3e0ad45cf1b102e4c0ca9cd76368669d49c6984445544264f8ce45fbd2aea6230632e39913216e87f3db2	\\x07ada5b209f3284ee6c0e1f79e9125c29bc1b6389bf7c8d0331e9bed35922230cd7aec9cd97ad7191a5ee95f9c2405926fbff71460972890ca9f0b82c9defd8d	\\x000000010000000107eba992e6996cfc3d9494cfa0572bf1c212f31da76933ad66f9f88204052c902cf51fbb42cb8928177c024f67623c3961f314a2ee1c44064e61570b862e7bb560f624b51fa337f36a27a66db4c3fd5f04b0b331565d5ae081c9808a138efb6affc50615a2100c858f6c5a574acc897a980c6fbdc41167833a823b27a2e30292	\\x0000000100010000
33	3	8	\\xef0e97afdca65aa3f81ebb98abeab6e3e36e2a6acc13714171df76384dcccbfb884974e14154fdc60c2674845a3291af6ee50511851b90007fbddd21bcf8820e	45	\\x00000001000001000369e7f810a23c61d43ee90d24d2efab238ee6716e29a0affe4d35b4378a16bb40c36de10bd1d48bc4f88427755564d3a32d1e4d6a8abceb003b8625658d77e60162c0a19f12669e5695d08dec7e98b419e8a4eec47320189191127b05dc8e067ebc4494ee37f19810763fdfc5dd4405fdaa19abe644cc9a0cdad9b51da3fc52	\\xb39cd051fc3cb77aadd701cebdfb4744b7b242baf365f13468e0a27ecd04d494ccaf16a62d962f4e85ce46f839e2c243f59cb638253dffe9f34be564ecd36222	\\x00000001000000017954fecb0de70aecde26d0d53878ac864a09a3f145ad926c3e29f1c9bfc575270125620067f0bc72a4e74fa7f9d1275aa349cc0a68a97ce31a1dab52288fc53a898b83961992b40da8f382c60ff0ce2fb885c5af29f9d4a80d54fd5eb7ccf09122066aa6b918836ef8693d25c64503ba5443570f66464677eb581ec1a847f5bf	\\x0000000100010000
34	3	9	\\xa0028e8c119575fc94c740c3ecdc3f0948211ecf4eb03363d5b504061d4cc00eb9f1711472f526ec8eb39ca7403748a4066b8639a34c8394a6ea42506b70ad00	145	\\x0000000100000100599aa7d96bdbe86c449f51eb1f700e2d61980d52d46f68874d3bd1662755cb16400d59341a6e89e73777e7b072bf052d34f7f69cf3b9fa11dfe91d6b52cf9ee332bcd962ddb9fae11d7843d4a72df80f666c8013354f46e92de1a2cc569f185f42cf1f2415d0f4052e21e0c761e76578a611356524b4b87d2dc9fe1920748a42	\\x69a3288985851e578ff43e91ae6d007dd980a4e80bb5e4716c047cb30bde50b0d0884960c3de347efee4a1f638734e04397f79e3e5d6409fd191f065f35de3b9	\\x00000001000000016fe4a757035f9f375816804c4e8b7336ec72fe2ef43fd46d6f2fa3cb8c8d9401a5409869fc204e01bfc3b244d86f4308155608568128d87fa43337a5574127c83ee85d04fa1ae23f248b24f1463631ba7a2e526b1ddd8be748adfca9d0ce198127d258bbb08e5bf72b5cc1b3a3671fd7acf7a2a0e0aa5af1ac3836cd51e823ea	\\x0000000100010000
35	3	10	\\x42d5c337e59875eb2999e45c739f3ee7985a89dd1d27271aad6eb3fb76ff560ab36d1a22aac648f6fcef3c54b85c9d8537592dda9a30aaad67c396e15b7a9405	145	\\x00000001000001007a02d60ad8735a90015925c03a1520c44b8be454c804ff223a2151f82ee359fed86b3d6d144434cbc1e47e3572a403f238775eed5fb85ec0c941109351bc91ada922edc3a16a593879591df2c3ec1af02dc92d72c9db4a02a964f1e16383b2f1bb3d578c4d9f6048221b8db3cfcfe86ea6f90cf9acbce77531c788113088ee53	\\xeb0fce5b693f6f726d140ef972ec80919db3923d61a71df6d261bfecb9aaa127e97af6d59f07c44adf9d4c7d370c39fdeb707f031143a216e3e9978450325a89	\\x00000001000000015e2424156b227bb1aa5d9177b6b0f1e68963bd7de701c340f312912bbea33661b6fa49f356b17d90c8d514d8ffe0fc0968d9e5ea5954bd0022c529c8738a786b2ad19e51b21cff76b76ae5bc8f38508ba70b309c7899e8a0fe7982d0c10a4bee958ab9d1e0eb27d6c00cf2c79939dd138f66a37971e6569fa735be3ad3745c72	\\x0000000100010000
36	3	11	\\x06e33c6067b450b3767b5b3a14a0f61df17b20a6a7f0bbb29438b388949efa50a92d77accadb474fef6b5988f8ddea59f6ad0fb661d13a84761731a2a14ec203	145	\\x000000010000010050caabc22ab330307d95d3135d22bd8913b30fe6c7d2d21822f616ab31720f1cd28e6e69f79f3bbba95d867943fa70c1b8a52fba30755ea0019707a9464b266fb7d9319a0b5e0f6f0875f4ec7d65cc56491d73cad860fc418859f41ea538fee65f61d1a31609191cc3458a2c227264585f00d3104a5d338328a2b8e7c3f2f041	\\xeeb4f593236cab2483f82489a0c0c8764610ccddfcaf303acca0b2ce1aadbbe99a40f66a53754936a60785bb7e603dcbf69fcc6b6e11a59a2c6e635611f61aba	\\x00000001000000015d5eed8c5e29acd2c677cec2dc8c734aa901c09152ea89e289db3fd83811fc5fdb8f79816bf7f17de46dcba2b2075012727a15d114bc67cd53e06798aded17ae5c724c5c3852732568403c4f59e58d0b57f3f9faf93785500b07cd0b099ca2aa8a67020b9b36fc0aa4659dd2a6e1396d21992d31cc2e8e1fe1db513bec567bb4	\\x0000000100010000
37	4	0	\\x752a0cd258e5c8a49ee9dc8867adad72af9ea9e58806e24ba21ab21c701f5bc421cd4e8127f594de72dd844e22da072ad8e7d4f3e51372205f8e45c493b8c40e	144	\\x0000000100000100ad42e15fb6c6d6646aa618005a5df1926df8b1f4e8e2fb2fab50e34f9669c442bdd5a029299cb0d33327fbc1b55f56f4df1f2c5e0645196c4476a0d20df7e6645a0ac49589f5173169a838453021966b3cf96a81281a92a4b9956980e5443f314b166743aff832d7c89214719f71bc53f1c594d30b83c3a076fb3d65216d9746	\\xcb90901d624bfed1814294abcf2606ee5813e0e81347aff5dd5eda0109018c8f4f1c57606f5532bf3bdbc47e0b152aca78518485741315cabb44158e5fafcaca	\\x0000000100000001b9f82726cb9c463b385cf9ebd9cf77cb87c6c41ff5c1b3121062880a210e25d4d97aa08226c3ae2c80ea309ff1b1f51c3402a334e881828306ca2287edd79e8bf285f0f27116a15ad381670af741821bd4f9fc930eb6251814a08e1004be74907ec0bc1ec6b5e83a6396b36fb6384f93f2309119c55c6403476125fc2909ca15	\\x0000000100010000
38	4	1	\\x8938736262e1d4fc15c949352c17989c3dd840684045c20aecb6f50b4ff35b586c63a63390181a915b9334404363c84d3eaaae4517933946dff623d7f88f4202	45	\\x00000001000001002108e5f5969b63fc20adc326676db8cb984d206779bd8a3a376b1513062f92e2ac85cd289df0dbaebdc69f5b4e385e41d1aeeb1a4f1318b474c98c6d100ad6c69b54ed01ec905f02c1b3a8b59fef8a492547441a1b1cf9e0e71fa9921f32abf2115c23654461473f64e76b2b8f07f9d4b18caa03bd1f8a0fa13c420446a97a9f	\\xf5509fe82f59fc1283eff93fee560c4dd5ba6a7fdb931f8c48065b457af6df95fa8495122111272ee06d0a5b361feaaa240e57f753c7f0c6d2a99a469c0dd67d	\\x0000000100000001704509d91ddd3e1547a307c2c8813a09d8f464159752b5e87c72c35229a0aa9f6a841fa1e0bb3a3ec664c1f7cd3d2f6e962bf5ee4138ba87b79e40368734576ad824a08a9bb887686055859c68f4db253770f74379f86a1e43147c650f549707e82a0740ce775ebb551f0d13730e2b1707e9c7974d3b878a480773d6a45ca163	\\x0000000100010000
39	4	2	\\x140d227aed535230cda868439b79b947af2b2a109b0fc658b36a7cc58ba70cfa0fa6e4eefe585c9a0163ae7874a6b626b2be875cb36596a9ec5287b554781f04	45	\\x000000010000010075cc4e93b7da1cfb6bd4392804b8e10e23640aa4a07e2769eb33954d80db672d6a9e1812ebe9abc7a2be57d62464c24c190f4757216e8c60b06d4887c55d626a33f48f7c5175fb11ffca24f8f9b31c70513bdd7260194392db983304048fd97a55fde7dcaa0cebc87c6bd0229b51fb7358b53b0e73395a2af26379f6a6296d90	\\xdbd1f7041b177363aa89d819116b72ac05314950a1f95440b0427d8322385649a49a9b575c2e06a148be8f04fb94fc72015f94c43c6ef89c0fa0f209cb777bc3	\\x0000000100000001a4480ac3185889176d5cf33086e293ac3326579aef6f7504e855d1980175f7e9e80f44770ec78503e6052e380669016a30b359768886bd928a946718dacce660c5a03d435da37a1ec407095451e8320c1d8f53a6023ea6f346abd0d9766f8c45de8632f7f5a59df3ed73f250161f5167a7d33e0e8e5cd795200731f4ea4f3f0c	\\x0000000100010000
40	4	3	\\x03bf49e7f11e9b032aa459a3361f202b41c88b17e3fa9cae3e64b5c5c3c688550532d39ba9d41afdd2014edf5e73135069f744b3b15d93d77eb95285ca034f08	45	\\x00000001000001001f93797958a0eb3b7dcbcc57b0af41a21424ac3749e0a555d67fa34e994f556fb19feee32576049209b2781c126cd04b997fc862605f6bac76564842a4e8e18d51c216a1b946428aacae5eaff8f6dd7cc3a10b4fec3eb6882fb8af557777e2f3624c9e2dc7b0ffe6258cfc20f872a4a613aa7915077e7a7423e502852aa57401	\\xa6131b57b688815566fdc5f01f67f73f3d8483eeed255bfbfb72fdc436a3db2c4282554e0f7377d4500d489052f0f219c3c5d83de10cfb02d6a11e675a74161f	\\x0000000100000001b9a419c30f01bfd198a6edd7432e4568daa39ca08ef3ef61b9aad813a86511cd5116f7332a806c0cbea5dc06960477ee5abf318aedee4166c86ea82857088c9ef21ddd252bc468ea19802cd5337c561a42efd1906dd1c41b7f729cfe70500575ea771b8f254a42cf1e5e210aa87fce8c7887c5ac77f615cf0f66bbe73b75c5ec	\\x0000000100010000
41	4	4	\\x699c8d9e30167738525d5ad7ed0929d0ec9d3fb40d3181289a79ca5073920b2405cd87f75201acaeabec594c43ae6fa9953a7eca45d41f68619515b836c3bc06	45	\\x00000001000001006d23d5c7199953773402012eea1808b974bd226160d10082105816df7f8ab41fe1d3fdcb1aa1abe94fb5a0f26f4bacef9d9e7b180ed5c06daeb0d3880f8de9575a48fc6e16548be07b05a85ee0e216980a2cb90f9c6819d15705353c96378c8a642d13630056e1b2342418138a61a3a27f83db70ef115d60a35e1a7ebae29de9	\\xa02248ff8116745859f71b13d1730a864468dc95d35966c9f0357485cb8c9e3f66e04f03a4717deee94faa8e31e11fa691a86b5e99ee5a4fbc374fa6d971c65b	\\x00000001000000018fc010f27b780f77a8f9f1508d3f35a7068553c4b8101ae49416fda1a684cf6330732340d96bb627e9526f90c56750082ec71c841684a5061ebcedb8ec7e0708e8186b06f529b9aa5dfde1c0916cc8b49915161f1e09bcc34764a79ad76541ede4d328ad787108c48552f88adb4373ee2143118e24f48c1a7e19e7f4468d90bb	\\x0000000100010000
42	4	5	\\xe65eba65abd753daf428bda7cf6e1a6184fbe132a819f6d80eea1a9d888f6a26ffe07a6b7dbef37b02ebfbb37be723419ee42474a076d687ed058ac67dd0010b	45	\\x0000000100000100735a910178eb783a5bb08032eef0bf4bf5aaea9029e2dd7fb2598e8a85ac1f537b5569041efe4a116854a4a6dcd6d8affe29d085e0a7c68e115adb8a9bbd9ef2d7b3b7632825102f221ebc779d89cb4432452a6115b4d0a729cf308da10fc6f8fd512e124190608f5cdcff61bf8d2d01a96caa66447f23121eaf7608ff26e2	\\xce7fb3c06db04316750e1deff45383863481ad2855736487f8d5863ca6330c39c8745b4afecc3759f60192693fe8ef763cc0e039246e7080b434e893a14e3ba1	\\x0000000100000001370f91d72ab43d488c5b13d32b2b4167e5037f0a588a19816476ca50791391aed98953b0f614e3c2fddb50a763a6836cd10ac19934be1695c1f6c636b45f8bbfcfdc5b7cfa9ae66cb8b7fe577ff3d16693d68b25986987e9c31da0266d34cdf660bb0603efe0164f722ca5981b710e26d1ac96686ef53ace0d8c4e39bce5c512	\\x0000000100010000
43	4	6	\\x8467c0736162821eec350fb4c3494f38bbced73e62288b9b4e714af0d3e713ba6cfe69a437d1f82030d5f6c68c7d04c07555fca18453552db191345c713ff706	45	\\x0000000100000100718699a1b083f5b6d481665b957575ff763dcf52ac3b1b638dbb3b744406ad418726726b40ac270053be9187f65e1c1ec09e515ddd0aebe047a64c39e7f44d1b2fe3bdd9307ea95ad9ba5868ba6e0552ec0958f7705bd271d3be4f2e3539fb826e5462abb059d4107735829b1616a69b79aec2936c64daac155a8c1aaa2a1156	\\x8c9d0853cf022c2a8956ffb4304f54cf19b8b9cf22ee818818b8f214bea699e7758a8c816b095c093445865c10162b735390f24b152e3e7b8e510606b1abe002	\\x00000001000000017472e94cb109043175dddab7e53ed88a06a2b0257079f3ee091aa6f3705d54daa5772b14d757a220f9ffa8c75279d2eec753f0e02b08666f46e96e2e8ce0f0bb2eb3fba50b96fad31d9831637e528187d4e7499453e001f226e3ce7bcd86395df3571eaac887a49f6a2c3ad15c8dc039a533207bd41680d8ac2133a83d5e9ffc	\\x0000000100010000
44	4	7	\\x627751089df0be8fa4e2bc4f10a09dcb60ed478ee0515eea4c7268885fb11f06484f3314c694fb58a5187c56b27a3688f6c8cb8533c1ec8a53cf6ff8f2c20c0d	45	\\x00000001000001000f1a45c34179c344652637dc61aa48dc58b57bbfb5722445dca2bf228ee0c6c46e2cec44584b533d08cd472e3601d2d3aac4e53e4dcebde7a7e09286585732992e6edb51974eb74df6b5340e8a4ba8d3bd080bb332984cf888f9cce5525fb6af29d7460a99a6990fe175f0aa4fe357cd3c5af74c9b708a591fceb181632b71e0	\\xbeeaa5fbccdfdadd119481ead443c7d585a706db92f11b0c585622b2204fca34292ec0bc3a2c724e0cb005499116135e0bbe15e86b76da7a84f034c9dadf067f	\\x00000001000000015fd6d47c6c97ca07fdfc6f9bcbd36d12a18562e3d3962c835ab24325c1ca3b50f7f9556ae213c08142d38b70d11ba1732cbfa9411963ae04b04ed5955f1a3460801e1be25777b49cf8c766460501c24508e7a6ec947b599da4b335f2590a7dc7504ec977c0f068bb735c2531ac050a9f967e6405336fe698215fea98fee26719	\\x0000000100010000
45	4	8	\\xf6a26abd6871f3ebf05f37c5002a15564013f7d538ad5b35b6ec162d9193cee232c7144683eae5786aa7ffca7fc4d54877b8c3ec9821c527c6c031ed21dea809	45	\\x0000000100000100b2f056f2a077d8213af80f217b43f94b5ec4c2307a304a77bcdc7499f651b36deeb7729950c8233da6d46b3efca5fcfe4e69e20e4cb858beb2ec2512bb5cb2c74e0c8cb6a466c9da79d7469ad049009d98169e13cd9f90d93eaa33af52b5608ee6149b8b11863445b0868cc8751e090ae132d4e819f32ade8a3ef43c365c38e8	\\x17009db653541773beb2fa841b3924776c01d63effc526ad50d392c125133d08daeda866d5710f982e67473c15aaf74dfe6c40e123897f780364d4e9ae2650ac	\\x00000001000000017f0fa53a181fc27e01005f8abe7739c6b03b425357543c64081fee4e96609242d9fa0234f9557efa5a1ee6bae5c9704497f0b537f0d9c253506583675f01af17520ef482c3d93f723ac405850ff0c4346ccff0e2a589ed396e4e6c6ecd3a995fd63311550469bfef3ad7788f3f28b82e1ede28b3b481decd1ecfbe93d6ac24bc	\\x0000000100010000
46	4	9	\\x0446993279402c721a6400cfe65554406b9295bf7ffcc472213009fe480cdd595b49a38beb45e231e40d9fae38bc3892c53b624300cf8c40f01b9c301804170f	145	\\x00000001000001004da8fe6396de7399f41d3363df31cb2229ca630004f2fd1355dc12093433bc17a04f0c287eb4b734358855a24a77f77a6b76bca7f02ee247c6e452b7341139a535c9c677c2da55f30fd5fc91a16f003ab612154b2d5708495c0a478aed4ecb4ea7fcef09ea0b5d0aa6428525b18a5414a8f9ea2fa6d2820cceb5932507c723ba	\\x7c42603fafcba7d1cfa3b327e043147e9ca5f9b2ff1c3cb7c1f5fa2738013049839ee09703cf26a5651c718ac1842f69de37f68b3a632cf4efd3a2941eb37d75	\\x000000010000000182f1515d78f1741e807b1396cfe0fd1826b0ad431f38812c13f110e45f26529d79da12facaa2beaefaa871282cd61bb2a88b08a4e68c02480757b04c6fc32379adda9a7f28a37e7db10f367034ea1d6e1d1f527a03ec0cc23c9af3a002f8a368c0c5ebb782be77a4a491fb9b7d6ae13ac89d1e98379e76dcd338d50aee186235	\\x0000000100010000
47	4	10	\\x481b24d847e41fec5510427f8e8eff0b9f5ccb79dfa174ac9f953683675c0acbf1dd7a8b7707bcfc756ce226ae82587716ee5e9829ac77044f67bdd9e07eed09	145	\\x00000001000001008336ea10d18f5f1c2f2660bf89e9eef1356bdfa827b0458f718ae8fc68563ab7d28f723e24388b4ef8e3238e2ece8dcf47c117d543121470fa90f0d13d29563295bf8907cafba4eab575cbea8f5f8cf4f585a3af9cbcb8754d82669b85bcbe049f834283319af4b6fbf29ffd4bdfd25fa3080b6e7676cb1f2dd6f697c874c715	\\x32bba803399ec99606fdcc1d554c0fecc4493f73b20cb53e4abd3c031d50f6d878dc9bac7f427745755c89a5fe752f30bb36a8e7472e68e22487eab7487e26db	\\x000000010000000199b5eb8a96d8ef3e411bcf94978338329b09c49ffb360f408af395cadb9ee4f071a9c714e239a7a1e6fb935ce7b79b5b402f7cc0264878ae1d447234692dbea34483675df4d31e9da2a7e43e82d6926167ccee1959fd314bc4946884885cc361be2027be169002cbbd8b67888e6b862066bf9d84775340048714e51661189db4	\\x0000000100010000
48	4	11	\\xde94687a485b21c1c554ada5b4da299e32b66e377ba929dcb523d727b8c8ef675fbecb54b0754cdc96d61eab5adfe5f8fc483cdad062c816c2ff23797ef72b07	145	\\x00000001000001009fa4a7b3f71b80edea2d86b600a89dd557260c3e4965bd2902d05c89f6062348348eb5c3792f272c60703272d533e8d574b3271c7bd137d8351c4fe6e0f8489636f0557a6556349adce19272e61be00996707bb3306596e37d23b1d406a6fafc66bfcfd734c3b6672862844feb0a4e42a056db771e9ad79244a0f20f66f879a9	\\xe04d19dc64ac4b3a3403789d2b424ee30c2c7359c40906178cd7753db399a7569358b74baabd2de71b24c9b700eed31b292351e194910496a01c4de0081e9cd8	\\x0000000100000001702eeac39beba0ffbafc0a4cf307452fabaa05fd4c65b68e83e544a8faf946e4a932b5caf506eeb25dacd17cda5cd5dc8e918ce5c9b77bc4f45b839caed5a7b6e250d43650a6d648dd87aa756e74a6797a865ae68a813d78a44cd676c529f4997673bec08e1c32f895bda10495d65fb2e0e1e3ee163876c30303a0d1cf2a0a41	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\xfb802fc9b82eb301e6668ae850513755e256b007bc746a3f9679f7381291ab77	\\x647e509f4c9ecf6d1506dc52d6a40c5b714560728e85a0e65f49e4fc7ea89e61197507db0ba10a6546bcb90279bc885a2e9355514efe14fb86cd244731110835
2	2	\\x5839f8558f140814707e9d583045ac36837d69c5ade616c2e74c35a73b195645	\\x596f7530efdaeae6d354a4ec53f6050654cf763ddbb067c408b80bcd83dbbfc94f72ea1043f715254b5d1e70d711649043d62f63a47a84314956d848fa87d9dc
3	3	\\x3676ef42e4cf7227b5c6ff1ce1841fca3fc5dbc3e77ea004161cec082f6f317c	\\xd8ad3e83026472ae359216bad5538961fa7410de6d0bbc688ea0301a412570eb0c761850a586201ec1caf3b735116a2ada4205e448bd14b927b6ebb4457fb83d
4	4	\\x77ce177474ec1691c5c9093656e08dd59ee9efbd542497774c29618e52bb594b	\\x910e1dd63ce3bd617527f029420c07af564c8cef85029eb0d86213178341f006e7738b76b7e52907789ee2708bf1cc3196540aba21aaaecdef0ccd995281db77
\.


--
-- Data for Name: refunds_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds_default (refund_serial_id, coin_pub, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xdb47c6822d70335b30607ee22ac80c825b054b2810efdd1ca952ffcd93e4867e	2	\\x679ef7235a470bb8442d5ccb7a9c61861867e4e21306ec618197ae517647f2072707ca5ae91857d5328d3ebc5921edb985bbfae74720f71fbc150094bf83a109	1	6	0
\.


--
-- Data for Name: reserves_close_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_close_default (close_uuid, reserve_pub, execution_date, wtid, wire_target_h_payto, amount_val, amount_frac, closing_fee_val, closing_fee_frac) FROM stdin;
\.


--
-- Data for Name: reserves_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_default (reserve_uuid, reserve_pub, current_balance_val, current_balance_frac, purses_active, purses_allowed, kyc_required, kyc_passed, expiration_date, gc_date) FROM stdin;
1	\\x8bfc3ecb05ec429d2e7210bf4845bb65da1fa1496db0d4e5ba59ad86a67d49b5	0	1000000	0	0	f	f	1653935532000000	1872268335000000
2	\\x69155d4eb15492974d51f2d3b9be93c9d7863df31f54630bd6d397044cbcdf8e	0	1000000	0	0	f	f	1653935539000000	1872268341000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\x8bfc3ecb05ec429d2e7210bf4845bb65da1fa1496db0d4e5ba59ad86a67d49b5	2	10	0	\\x9fdccd6e7dcee5d5170f969c3ff68fe716445016e622f0bd2beb7cab7de6589a	exchange-account-1	1651516332000000
2	\\x69155d4eb15492974d51f2d3b9be93c9d7863df31f54630bd6d397044cbcdf8e	4	18	0	\\xdcd64d0315f126bffea43abc7779ad044bee42a64ba4c827d4005d1d0eac966d	exchange-account-1	1651516339000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x01ed3cde21d0382981f65901d84f68ffa4f083909a0e7ef9849a872aba5c3cbcd725fcde088d64ca6cfdec3be17bab3201982b7a45bae5539dade0f788d4b7d4
1	\\x6456eba14a64896eb30254d149fc9939813b57d872eb688f4dba7cac28429125c8e02da4621ced840f3a9f8eeaad50131d3f680b549b1bff4d55bfd0938440e3
1	\\x02c0d9bb52a6143fde9f441c14ef2687398b9e840b1971ab5caf209d7a7f1f63d8808c13f6c20a6b5fff0c1d70701259c9b2d1e5a09d01edb9bdb291d9199b9f
1	\\xaac9050d3975156b1da4d502bdde854562276d22101e97083ec1e991443809f657fc9a25e3d6acfcf4530ad84b0e1c9131d0838a581958ae258e87b5ab8af283
1	\\xf5c7b601a005e95f2ee9c3987d73e5ec7bd6c01a26a330266a662a0323ecb126c664e8de4ce5133cd07655ab895555e07169afc718593723b45fdd41ea37a90a
1	\\xf36811355187ffb5c030f0ac504325d0fc9c8693348a74c390ed33128b94bd3b17d99e09f52b0ad27e87d64b2550b5b4ba0fda97c9db10dab182c2aebf017df1
1	\\x13a01a8fbde97dc0bb363e2f9c45a81709e17ac0d9f8b89db44365123cf9043a1134d589d9ea5497dcec8cd40a464d4df0f2f1eb8b025deb30a0da23fd50ac93
1	\\xebddd3a606bc8c84e63a272a150b89457e82d5265d4e20a4fa374625e8d310ef68d538c28ecad5c9cff7cc20c1beade09fa6560870f37cca176a5c30b442ce40
1	\\x5897d679a6235b154fd33ac94c8d8c3974e66988ca66c3687f47d98e635be9fc0d957547abd3b7c2a09be62f96371a3b69b1e4e61f9bd0400e99e10532f5b4fe
1	\\x378c1a1d31bf2108a6d5400ad5f1e3af2f6e77a376c7e2470f7764b49a10ee00e3a230c6405e1faf47f781c18a10d3b31714d83976b51ceb286910b2c5c836d3
1	\\x298d3e1c5d96b27854c6617abc07c15759fa8ab8d9be34b3e6adb8a174e2bfaa873a6c323429ecde54c7c1227d2ea48238166377b1f828f6fdddaa081a222080
1	\\x7dfbb946bdbbfd51a04142f100eefa0489c7cd257fdceb104a6d972695c9f7215fa1991036ca727acfe47488d763c006c3091d08aea30d63751d175471950316
2	\\xafea2551572c9dd021c82e15b6ae68d96948cca99296d1c5c125d5f358fec29d32a5f8422d8c516767f79d8af214c0c33491daef9b306f457a2fba00b6fab800
2	\\x9b40a1dcdb68eafca2559dcf2db8b766aa416f747a47334671f72f1188e58a06563eefa15d9dba3516d5c864e2ddd3d1c2aaec8b4758fda48a20882155824352
2	\\x29095c3964a596bb78a06ca9f3adec3ff1aa1520840e4a3544fbff139e4f71505431826c47ac60135acaed42caf00a591d8f6ee97323befb0b8346963a72fe82
2	\\xff4e506199cefe53db3d7fe6957fe8ece8355df93bce75deeccb31c568f675e37e9170cee3857754ecbd39203261cdb202ceeed9d8a1bb5643be04bff2d342d0
2	\\x7d4a2872c2f31703683f5cbe1606430ad9d7f92e834d8a8683cda0c0d12b7ed3f512594d11e03f35da6da7c7d2d244b681c32d690402d15879eb6f070a904c23
2	\\x2e5bef5ba80a3e779fb9c83538dcfe88b3f756e3b3c3bf86c43848bcc82cfdd6531e14566a5c6dec2078f68a7ffd4f1a8459096b8759adf5705fb4e527838276
2	\\x6d34dd310dc7ba84cfe621cb8921374d30362918a4d36bcbfe441bd9bab4c4f8ec6e7a24f2b89971f7067b240ca40063521c77f60e7acdff5589e2c95e5f9b57
2	\\xd18b5384a3841b46935c3f62aa33d2e7eb12ecd85e7622cccfd3881d88b96fd2c193fdbea90bf22f3e61ed7c8c2a4862bce810832455d6b4a7a3b7d0f28173da
2	\\x89129e1959b4257a11c689d9a05d245f84c345ad3d4c585b3b9e49d956bf58a2c934eaddbab7d59057092bf344f48920b3df866586ee80d97b70ec99d65a3eda
2	\\x410f2098735a8a8d6f1b080354001c1fd0823ec3fc1bb6d81afb1044b26d94154625d2a665f5aaf081e5a4b0ffaebf2afadfb1d40f29c77d5fd1a90a9ce1f2c8
2	\\x64664ab99dd598ad76475bedf0f833da271efd85606159a62d4c447a9bac72ff838d547ed369a09e27e46cd429d530c4a349e35b7fca8919e1f766f16b3e69d7
2	\\x90cea31f56472a2a10ee60e65a36cd396ced1635518fda48865a01c73b8a2573f222f4ee16cf3af259d4a97d05d8fcc65951a7d38b4f5efdd57b2b3d3e059326
2	\\xa70f22cc7c33d2fb4a75683771f4b1afa075083b8eaad3512415af94c54f4ffa71e54bf02cc36cd85314a14222e1513312b763af77475bed82980b1b6ad79fdb
2	\\xeec9da07dad2e0ea1ef02c9efdd229043e5fe6ae3df5d3a93219d99010746291b883996f020b5ffde76934b2ab609b9fbe7daa09441558cc5433087f3b330bbd
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x01ed3cde21d0382981f65901d84f68ffa4f083909a0e7ef9849a872aba5c3cbcd725fcde088d64ca6cfdec3be17bab3201982b7a45bae5539dade0f788d4b7d4	199	\\x0000000100000001318151ddd422237644bc194d193cb7ff651469ac7ab3752121be619aaeb516b0b8761f4c0d5551b74979cd07eb8edaa85b1aa3432cf8ee11701afe0ca44776498a0a0ce0947421e18b09844fd20f6e465f67b4052cc5341970bfda6e8df9cc073aee8fb5ab8c472e9dad432527bf32880a6a21ec267fbcf05bd8d2f7c0e845d7	1	\\xbcef026a8567bfe41648844ca1c9a7e110b036f6995c110e7c771fc36cd33769c619a94c101c7bc77c7475089a7b709422c92c71f4e3d9c028fc2e6d75e94e0f	1651516334000000	8	5000000
2	\\x6456eba14a64896eb30254d149fc9939813b57d872eb688f4dba7cac28429125c8e02da4621ced840f3a9f8eeaad50131d3f680b549b1bff4d55bfd0938440e3	144	\\x000000010000000176b71917490543e136de968c405c430815a6bd6e99088d09982812590e035ccfdae1ac56f5ad089ad896d513cafade7814144e9f95aad20ffa2e9e0ee821a2454e52d804beff0d925b7cb7ce972efd6a77bae73b371c6d476338fa25037bcd60b80669d8a52c83c0da3e30690481953d47a3872051dd848518a3a1c51fe0d626	1	\\x15decaf2a067433bc177b958fc1a06e0f73c3abe5ff2bf001b3aa7f5695a78111e0615c34bc900bea8bae60afbe0e2d99247683cc869d6b016503035886be80e	1651516334000000	1	2000000
3	\\x02c0d9bb52a6143fde9f441c14ef2687398b9e840b1971ab5caf209d7a7f1f63d8808c13f6c20a6b5fff0c1d70701259c9b2d1e5a09d01edb9bdb291d9199b9f	45	\\x000000010000000156aa8afabfa5815281d28a3394ec371c89d388f3d67cff2857bc62d69aae639fa782ad05065ad50ff75794aca4e269003a3b64db5cfa74d68bfc2fd917f9f9642cb9f7310eb978cdf064ff99627eef54fe27cdaa40de16bd73856543ca571087f65233aa480e4a7f026826214650466186e135918707c238b17493a17398da81	1	\\xeef4524c6e89fa70313aa2e867f85ddef25f1052b70f21b782d5b414d528a99feb98737ee149de9dc1e3c96eb46527c5a108e80531da06396483f582d0f7b008	1651516334000000	0	11000000
4	\\xaac9050d3975156b1da4d502bdde854562276d22101e97083ec1e991443809f657fc9a25e3d6acfcf4530ad84b0e1c9131d0838a581958ae258e87b5ab8af283	45	\\x00000001000000013fcc4d44c75cfe8aef2fb34db32bca8a0e883a41cfc7b0bcf945b4363d5509c4e38ec2206b755ba8c8a370da3e23135739a2f8a3cd883f9576d1e7ffc3881fc04bd09ce9f6372561997c7db4ddf385e447882d9a0870ef7c9199ab1e79b8d60389ec45c54aa4f2d25a2bdfef820c02ea19a1c405e7c90ce887873a6ee2d70fb4	1	\\x6c1926ac1a731726b917fc26a9b37d40ff1d9a0a13521dfc216933a41b5165c692fa6dcb99c291c85de25a0b4ace4636eb4cdc80259da0dcf00350a687eb9406	1651516334000000	0	11000000
5	\\xf5c7b601a005e95f2ee9c3987d73e5ec7bd6c01a26a330266a662a0323ecb126c664e8de4ce5133cd07655ab895555e07169afc718593723b45fdd41ea37a90a	45	\\x00000001000000019246c997a9c06edb153fca0f90a36aaf51e013dc83f51095711a769e975eb67f29c69abee2615bac160283090bd5499a6942633de2d56fa949e1a317136d6c1f57d2c859d36a5c49f5931e383e9564a1e4758064a2d60bc7d451a9c10ac0d3f09b3982f8d159a3ccd7f08e9460d968c9e046cb768bc6bf5c39c99b4a76991119	1	\\x558187c68a2192f7e7d52c1ed0e4bd2c2e0fc15069926537f05ff19eb41fe707f07069940595d731c62b74b4f2ed37d890d17395795f13f2b2db4afc1a868908	1651516334000000	0	11000000
6	\\xf36811355187ffb5c030f0ac504325d0fc9c8693348a74c390ed33128b94bd3b17d99e09f52b0ad27e87d64b2550b5b4ba0fda97c9db10dab182c2aebf017df1	45	\\x0000000100000001595d39858a0d8e62484b2596378198d13150f6f52337bd0f5b657ca85589a7fca0c7fda93c99e72b9a736003ca8ac097169530083799e505afe7375cafd1fe209f1235f2543a2b274154fe3369c9a57c085a0093f4eae1401b163d0fc55e620c440e5b45d3ff019fcf87687f151e3ed973ab4f61fe87ae049c571b4bb2581186	1	\\x3fd1e90d6902fbbee79d296d1fce0d100b15d625434d73478af7fa1f248a6c896031b8dcd598b9a531bab7073b545034aa1ea79b7244f748ef787d5565b97006	1651516335000000	0	11000000
7	\\x13a01a8fbde97dc0bb363e2f9c45a81709e17ac0d9f8b89db44365123cf9043a1134d589d9ea5497dcec8cd40a464d4df0f2f1eb8b025deb30a0da23fd50ac93	45	\\x0000000100000001692d9faced981b8bfefd4381ef60b51ddff021bb02778e4d461052465ba7ac06eb42f6848dbc8d46ed2c9d1b77a11a6dccbe806436c2025ba2dd2ed04211cfa984abe04aa32a68537851022777c4a80ed76a13f186cc02bdc628a3268c3153741a18f027df86c9d93c460cbd1c34ea12e9c2ed9b92277e5ad6b933f1a1e83723	1	\\x184b891d32c2a047a7cfc10d55ccc5c36e5fe6135445c138a58c907e4de4c3d5d5b519a7b765bcc456b1f67dc3ba60269e6b288d973c7ec89b34c49db6d48c01	1651516335000000	0	11000000
8	\\xebddd3a606bc8c84e63a272a150b89457e82d5265d4e20a4fa374625e8d310ef68d538c28ecad5c9cff7cc20c1beade09fa6560870f37cca176a5c30b442ce40	45	\\x00000001000000012e4ed97ab2558c3eb6175e691fe22cbf3063c0d676ba38d04e84ba50538884276df9fa5b16cf257a7c44a9e643b8022a9ed001d4a3e64ea7ebf768a5fade80ba1a5b2b502b66e0004c050192039753c9154fbd4c578e498472d2c12b8a7607bd243b14dcd4fa5c569bbb5015d783edab672722781b3358723406b345548b7d20	1	\\x3b4547f794a1942bc62091b62b46118173a85e3bc5ed56f26471a00ba9d512ac38592d886f2df89caff6b6e571cbd77708671bfeb9b5a1baab7de6dd3a86200a	1651516335000000	0	11000000
9	\\x5897d679a6235b154fd33ac94c8d8c3974e66988ca66c3687f47d98e635be9fc0d957547abd3b7c2a09be62f96371a3b69b1e4e61f9bd0400e99e10532f5b4fe	45	\\x0000000100000001419110bafd89a827b60282826036e1ab03525237af4b22bad6907dc9cf8743e19ff802607c4e8e317e9d2876e6090331230f636fe24428a4bd93dbfb90a641254807c47ffa31abe9f3324d117eefe9ce80dd5ceffb68a1cfe6a7bd62ede0ef8256da065b5e957aef96cda4f833addfe7e1f512e3d90084890f83f7887c4f3832	1	\\xdaf04a5064ae7a6e4d76789c80694ca1f6e65fd9546eece5fc4113c0ea75d94fedbb9b34d6cece49fae43b66c05175ed6bdee1945723182d5098179fb521a10d	1651516335000000	0	11000000
10	\\x378c1a1d31bf2108a6d5400ad5f1e3af2f6e77a376c7e2470f7764b49a10ee00e3a230c6405e1faf47f781c18a10d3b31714d83976b51ceb286910b2c5c836d3	45	\\x00000001000000013120fbb952281f6ecf628a978ef9cd1267eabf768aa639151a9972e1c0e07f34670b7c55979196e3120af95202038e6d9820e92489fb8b396cd0149973dc350e86a2e39d6f6dcca1fb60ea891dd1ba05cc7053e39946d263214d1be22e97ca609cbe339998d4f54905c0ac2ed807657921a9889372dcd237fa894cd98f516a92	1	\\x01e553d6b18895530945f400ecdaf6bb6d3dbfb7b0ce49cb47d11fc975f9dd214c035b89c7c7928a0d0f6ef029a58dcf29ef88850e199c94c7f9bb46a40d360b	1651516335000000	0	11000000
11	\\x298d3e1c5d96b27854c6617abc07c15759fa8ab8d9be34b3e6adb8a174e2bfaa873a6c323429ecde54c7c1227d2ea48238166377b1f828f6fdddaa081a222080	145	\\x00000001000000019271c244eff64e21418b612105bf96b11862d3b9ec6ea17eaa376dee63b2a800065237205420ed964d6656ef49cd169937f680dbd68f5678ed46c81b4e01385c4651b93dd304b54676fef3e2e70c6a99c8340a23ccf4006b69e0b240a74e4ff4045eadeb7306803590a36201fa8f8bf6897ecae5ba90d9bc31fc7bd00c7f05b0	1	\\x2559ea40da5f1ecbdbda1d4e2b5dd74a84b902f65a4e7571cbb4216117f8939de40cd852af226f211059977b1f86107b34bf27be12c9ae9db76f22607ec35d0e	1651516335000000	0	2000000
12	\\x7dfbb946bdbbfd51a04142f100eefa0489c7cd257fdceb104a6d972695c9f7215fa1991036ca727acfe47488d763c006c3091d08aea30d63751d175471950316	145	\\x000000010000000109af50c6c9604426404d3b4fc178503016316fde8d84cbddb43c0a12d934cc2b47f1a0f35c6a8217d0c6a336efd6cf2c84284829bd809fc7b665bc1c888d84795c014cfce930fdbfb0a3f047d749bc452e9e2cf64b627f95acf6441fe3f492e1c0627f5c865de6553b22f199d5c537459e2f5e9717b93da0175759c59c313a59	1	\\x2a86e686e1877e03e89e0840246a4198197b75e7a5780bb33ec5733782d2aa65221377c102ec0306303a804ab7fdbe5956b5a8258ef3d78fb08abead7d127203	1651516335000000	0	2000000
13	\\xafea2551572c9dd021c82e15b6ae68d96948cca99296d1c5c125d5f358fec29d32a5f8422d8c516767f79d8af214c0c33491daef9b306f457a2fba00b6fab800	358	\\x0000000100000001cb7384b3c0b8e4cbf0132257ccc157eabfdcdcd3bb8f71f2ee10125e57e227b4348c2547fc411fffe1f13ed6b44a0e2e7508668bb61f2474d049a610ef69a6c53a955b5ae307c13e77ae57c43188049758e6dedb1c7c3650b4278c9e4e82777863cf51eba16c1373736f4bd2335474869e4266db18992f0c4f690b5133bb9ab3	2	\\xb830de0ffdfd9daf70416d250ecf728c75ca9358ce565d21d09a6119a9ce09a7e1b1eccac2909c477d103a6edc325046f1f512342c40b1dbbcf751e4e878ca09	1651516341000000	10	1000000
14	\\x9b40a1dcdb68eafca2559dcf2db8b766aa416f747a47334671f72f1188e58a06563eefa15d9dba3516d5c864e2ddd3d1c2aaec8b4758fda48a20882155824352	393	\\x0000000100000001c890007dc292a6defc008bf3241a134e3b85e9193dbfbd17ee9954d1dd08ac22f5fbb2df964f069da6d959230cd8ca42f381c77d27d5839030ded1d820d6f90f1b2ba0eb9240cedf08d37e70cff4439652a9d05dbb664d0baa0263025fca0d8b26dc4138c7bdb1cd3c02d9fd92ce738ad7564c84005cfdad804b3a790de9db8a	2	\\x7870a65558a801140f9ef97dbdaaec4b49e7a557db26a360ebf8f8fd7cbb80a07d850f2f0e9705950226607d97c1c253e4814b1747d0f0ded91db8f6427c960d	1651516341000000	5	1000000
15	\\x29095c3964a596bb78a06ca9f3adec3ff1aa1520840e4a3544fbff139e4f71505431826c47ac60135acaed42caf00a591d8f6ee97323befb0b8346963a72fe82	235	\\x000000010000000170f546de9796a42a24570887e5c78c00375f37f9399d368575c8130f22118b15848e5bd1009561486a39876ef35a3945fad9f4722079c7e2fb384a66981c344c995b6c6bc3fecf30cbaf00227061787e54adcafaa4607b2246c1c5e1d6fb2251ddd97231f89ce4ebb8c5928c2d040c5643c4bcafd43f0929640b6773a188d114	2	\\xefb0c3d99fef8faa8915ba96f2ce50f7d6b2ef3212df43b5b494ad0598b1a017c48b25de346aebf558cfbf0bb05cd55c0a8c62f196e6ab04f829d1a2f4a8e501	1651516341000000	2	3000000
16	\\xff4e506199cefe53db3d7fe6957fe8ece8355df93bce75deeccb31c568f675e37e9170cee3857754ecbd39203261cdb202ceeed9d8a1bb5643be04bff2d342d0	45	\\x000000010000000173e53391d0b117287f30e1b84227f321575df97a0a902c44d56c343aee1a77b95ef0cb7dbe07b735666109de5dcc6f567c20278be7de40711620d8adb49c4e4f870cefdb9d713a442c38748d1a3667fc713ddf374d39b0891bfb924241f1459b6e07e30b08de8c87db9f718b33eb124301b2f2f624f9f3c9f1c9045c5fe3e12d	2	\\x069750e67dfe4f15196f8c0cde7a99125d2c30ceb21ebf8a2c091f8523c00a8de9011f50f18e6ec3f6223045dd3207e7374e0a9b121b5031e9239e0d67c1fb0f	1651516341000000	0	11000000
17	\\x7d4a2872c2f31703683f5cbe1606430ad9d7f92e834d8a8683cda0c0d12b7ed3f512594d11e03f35da6da7c7d2d244b681c32d690402d15879eb6f070a904c23	45	\\x00000001000000016429d1fba18b335683d37ba1c2226c97660b46783a7069c20bf12f104dde53460e1ef017c2e18faefa2ee7670fe62a0bc8e5dfaed07581c5cec2bad6432534defd26d58d8745e320bb05e8e28dad41fc49455fd971d0a59b672b1b3925e54e27c3fe9947b6c0147e94d0beee57bebfeb72622edbbd273244251a9906e508ebc0	2	\\x3c054176c30782ef92abe69ec99e7c523fd8c160e72008c01f3a7e6bbf4018a87858cdc99a793f4322960aff6d5945520a7641c58ddc14dd5a18e3d07d371403	1651516341000000	0	11000000
18	\\x2e5bef5ba80a3e779fb9c83538dcfe88b3f756e3b3c3bf86c43848bcc82cfdd6531e14566a5c6dec2078f68a7ffd4f1a8459096b8759adf5705fb4e527838276	45	\\x000000010000000108a4ac03860016d9b9ff6f08874aee00f254778dd8fa4ad5b106924c3368f012f98b3c8406e3c5d6e8100892c2e01a435bcba3e89b4cc5017e1617f9547798a5ece3fc8c3987aeb9bce758f5133e09b95cef69477dd1fc7be68d875cc9f1cb9bade341c28e95c8d0657b40793dfadbdfc056250e4502fcee533cfd4a1d8467e8	2	\\x725e5a580f29f46efdf2feed34f878e503caceeef809e1a5997d87a6e84bd476dc069e021eda1a6d5f92d497594f34390ae081461fcd51055017993eed6b730d	1651516341000000	0	11000000
19	\\x6d34dd310dc7ba84cfe621cb8921374d30362918a4d36bcbfe441bd9bab4c4f8ec6e7a24f2b89971f7067b240ca40063521c77f60e7acdff5589e2c95e5f9b57	45	\\x00000001000000016a01a862297f0ec7a399fbe5f5a697ea3fe80baa1c566e0a5c9d0f1c659f79fbc636c4855bf5578a2d1dd0747b1b1e51c15bd2d106f26ec33392b3a2f6616c558d37da43470bb371ff0c9fce99c04507b63ca50501d2e022efdb29751cab65c755c982d96bb1aa6ccd1a065c2f80321926e0e27bec2d362f6a95707fabc8e7c3	2	\\x64b0f438212c3573fd8543a0c15e7f39dd87ce27e2ce22578a83fc3b4f3de4f58d0db1a544c8088bdc34bbdf5256a3b0b758540b605a8e9b63034cf6f213bd0d	1651516341000000	0	11000000
20	\\xd18b5384a3841b46935c3f62aa33d2e7eb12ecd85e7622cccfd3881d88b96fd2c193fdbea90bf22f3e61ed7c8c2a4862bce810832455d6b4a7a3b7d0f28173da	45	\\x000000010000000166d624a079c32ec98cdb4729bd5df99617a6b2f530a9ad0ab60ea7c2dddb2f433afbffa9145d060c9fc8b794254cb2944f9e5fb0d1b5c0f44540f0befe3ba0fc19bf261a6c95b458f5a94e386ddc7b700f5b6487ca0476621ddd2c90582e003384c2a24ce98fe2cfa310b49fd6cd4583f52763ae1bfa9d2f2e8dc1e72238ef59	2	\\x16098645b42ce413db31208ed74ff95976c9b97ea680564d198d50014534c71f82234301232359955b043cfeae920a6f629187ebe2a01512e8a3549b55a02609	1651516341000000	0	11000000
21	\\x89129e1959b4257a11c689d9a05d245f84c345ad3d4c585b3b9e49d956bf58a2c934eaddbab7d59057092bf344f48920b3df866586ee80d97b70ec99d65a3eda	45	\\x0000000100000001ab6d79005d35d02481dfca68661e99b5321f8eeba8b5008eba9be31f994efbbce8784788db3f7c04085ad9217b432e224dd3c5e11924c27c5b8500f5f924dc93330a717e20d08c857a12e3359d60a9d38b23456bba44bc196e7582624409ac5d8b442cd571a147b5ed7fe49b88ad244321aed0cef0b7baa8cf20cf7a532b08	2	\\x5deae9ce7e3fac11619e328e67b013acb9bacf68dd3d737db5936ae66dd5efedb0b7948999a1729e226d0b577702dc9a619881a3c1d1c29f23ccbfed06955a0d	1651516341000000	0	11000000
22	\\x410f2098735a8a8d6f1b080354001c1fd0823ec3fc1bb6d81afb1044b26d94154625d2a665f5aaf081e5a4b0ffaebf2afadfb1d40f29c77d5fd1a90a9ce1f2c8	45	\\x000000010000000120a89221e74d312ea6c0b8ea2c05011cf9eba3eef03ae77896b3937f371f1df002330f1be186019ed0ea5f3404cd048e963e2bc125d4368282379adbe7510c1078b02bc6b7752abdc01e06f0348a24af6f951b0edbdb93b30d583c261ad8b61e5e7cac37d46a4e175c997451e2ba5f6473d64d7ccaca28cfd89b6a82ccb24b83	2	\\x38ef2d8790b6218589e12d7f2b65002b267e76e5f5bb665d7b6bf053a01930c4a0e766fc0f082961bb8f4c5833e1c7b24875b8794a27699b2308907d4053b604	1651516341000000	0	11000000
23	\\x64664ab99dd598ad76475bedf0f833da271efd85606159a62d4c447a9bac72ff838d547ed369a09e27e46cd429d530c4a349e35b7fca8919e1f766f16b3e69d7	45	\\x00000001000000018440921b9963700edb0ad0d4d880a9049205c917514964d47e815d3590b02c1839f8f8af8cee989228066dfc595e8b494fd8e37a9f9e07e2f1a74f5a24d7bc6e6708588fe226b603a60cc35dea4df0d80ef8a58205bb99631b5637c29c84c33bf6b32558339b4a963164d079ad40298b03633b0e272e85a878a22fa1dba6113e	2	\\xad759d5b0db5b5a48346a5c70e4d1259c84b7f2455ac07ba0b104db9827263c47067937bc4a5985cf23c3f91e72a867865e08325ec22b0b3a3039c8adbc06a01	1651516341000000	0	11000000
24	\\x90cea31f56472a2a10ee60e65a36cd396ced1635518fda48865a01c73b8a2573f222f4ee16cf3af259d4a97d05d8fcc65951a7d38b4f5efdd57b2b3d3e059326	145	\\x000000010000000168e6626c43d09c81044f24909995a502215a56cc961d2fee531e8a360e74e4886d98b12434ac308d9f3c0cdc38266a7ba18cb8fbba6056351513f0d728fc86319b46bcb6e628072e79dd9458a13a8814bc8e79c3edd0a4b95206a61e0aac593837377101a98d9fa7d9f49bf656d32a3f55de8143b3adeabed6e58fe7c742f502	2	\\x17fb776feb130e0693ec856b850f25cfd26ec1e7be631086935edc95050da442ef1c80bb8aacf978d4f18a3427951ae2d4422a87dd8093d0e38d8b88dcc8410d	1651516341000000	0	2000000
25	\\xa70f22cc7c33d2fb4a75683771f4b1afa075083b8eaad3512415af94c54f4ffa71e54bf02cc36cd85314a14222e1513312b763af77475bed82980b1b6ad79fdb	145	\\x0000000100000001464c9b34de9afb94e45ac568cd2dc622c2249ebfdfe812aed17713faa6327d720af337e08bb836d391502255328f40ae998728186596a72bdd6ab1a7f59bc4840e5e83969345c2429d49ab1cf9c6a9f28fbcb694acb096c3f1e6c2415c2b9d2a4be9337f0a206163e6c935cc94426acfd582b38ab64f6edd4ddd8ecffee8858c	2	\\x4ce37c5b7d2fb138630f916fa03b28ca5c8f126ce5c6fcc8d83b0ad5058f05aa793d72911c1b735160620269690d06187aecb9fc79ce77d50ff1e5b2bf0a7a07	1651516341000000	0	2000000
26	\\xeec9da07dad2e0ea1ef02c9efdd229043e5fe6ae3df5d3a93219d99010746291b883996f020b5ffde76934b2ab609b9fbe7daa09441558cc5433087f3b330bbd	145	\\x0000000100000001a3e2f18446950f07a099c9fb915aeb45eb85fc1463831a158f1607e2f1b616922aac6b970f353e2786cbb4fb6b90e66edbc3e825ee4e910ee85c3d608329b163bc0f9a4ab5bfa7a2f20f3dfd16e24183e4b7497be4e0101a3f17cf7c6c7a30a9da5379a2899ad15f2ed314e6af7024d34ad1730d1a99294eae194629cedde1f9	2	\\x4b54a8b5769c739fb2a121453978eb62d977a6570f9df375c3e7509f979ae085ba0dfdd51ee4b1779c46ceecc0ba4a88bcb2ccd9c293cd2f05e88b166074380d	1651516341000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\x37ee013beee22858235b0d57dca4462ee47c273f90dcc1d6146eb0b1f9c22c9a7543a6f55c70fb532e12bfbc651729632b2bcea1d73262970959dffedaeb1602	t	1651516325000000
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
1	x-taler-bank	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\xc4bc53a23028f8d21026f07e7e7176f581de0cafb26d3f73087e9507301db0a31e88659125340f8340fd433118c0fdca78cfb42eb9920f50ed8a9926cab95a03
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
1	\\x9fdccd6e7dcee5d5170f969c3ff68fe716445016e622f0bd2beb7cab7de6589a	payto://x-taler-bank/localhost/testuser-pc10aumb	f	\N
2	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	payto://x-taler-bank/localhost/43	f	\N
3	\\xdcd64d0315f126bffea43abc7779ad044bee42a64ba4c827d4005d1d0eac966d	payto://x-taler-bank/localhost/testuser-5saj9erp	f	\N
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

