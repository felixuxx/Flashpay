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
exchange-0001	2022-05-02 20:33:08.632456+02	grothoff	{}	{}
merchant-0001	2022-05-02 20:33:09.495945+02	grothoff	{}	{}
auditor-0001	2022-05-02 20:33:10.025629+02	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2022-05-02 20:33:19.710863+02	f	55d53162-0d60-4f87-95a1-a30a36a7c617	12	1
2	TESTKUDOS:8	CDMQCHRC8MTHV2T34NXGSCM9QNJBT73GHRYT7K2QDS1XA8NET490	2022-05-02 20:33:23.213741+02	f	89d148cf-c9a9-43bb-9a17-003cd5338715	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
f2ffc636-d7ba-4f83-b5d7-2c3c9e157746	TESTKUDOS:8	t	t	f	CDMQCHRC8MTHV2T34NXGSCM9QNJBT73GHRYT7K2QDS1XA8NET490	2	12
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
1	1	82	\\x148db4e721b797b96cbe2af707fd739af3a821670254b641b65c96074cfc9c0878deaf21315770de8079a326a063f94c0f97fb6f3cccc9b8b0ee3ec7af95af07
2	1	170	\\xba0dd58ffa5a51e8ea064c3bffeb0366a5df876a80d6c3d1414dcdc36062c86dd139038380768b165c75b8435b7c31fa8a675bbdbb52399603f279847d9f1709
3	1	331	\\x3c220644b63503c10b71489686442ae23b37b0ded42bed68a59460955c7962b2c87c8c619f1daa9f3331eab924a9f61bf6ba204e977560ca23d9f08d536a1c0c
4	1	104	\\x06ba63a59d1b6b16aebdcfa06a572124499d97d59c0bc9b4f176ebd59f30ca5b27edaf80e85b7ccbec341a9682e43303d7f01fb4f08ad28452229fe13014ab03
5	1	246	\\x850724ba9122a0201616f2ce32f9f66df47f492c483c0c025f60aae86e0fd4a9d02eacf8961f5c0a9574724a9b3d5d75a78c664887965f6fde662b089f9fc30d
6	1	260	\\x86f46f901b9df2bd4d55d7216f4b7c0e93f5269f8b168a43e274e8a07d6a1c2dbdef0f88b9d208ae290fd8c29a540e00f9ea472a29fadbca91ca0f206eb66b04
7	1	276	\\x381b4c5a692b436487060d854d659fdd28716e84508c120423d4675755c7f35468d04b032061926bf29daa3a949bae09d19950c7e8dd551e257562233c3c3b0c
8	1	407	\\xa350e8aff07a3c7540c0aeea74100b195d55b042d86be11b72676622ed5f5ba7044eb2778108c1036f6bb84fa10b42de0c88d72087bd6b9be57e1160fb482808
9	1	227	\\xf6227bbc19661acce2bdf966103520a5453de7ce2ed5350d3083152f13bf2328429c020d740410cd81b8a7feac2a91016c0647b45b6b8171a5ff4ff2f082650f
10	1	287	\\xf75a67bb2291cb9e4ff0b5e0c02821f6b5a09a3103d99c823fe84d2923c388d847c68d8af14e18db0ec02913ed6964b35541a313831b0f3f429a1c4428a1800d
11	1	247	\\x02a6c21bcc318e021a7836f8ca0eaa7f2057b77208710cf309bcd0b3123ae6fd466c3f2f02d1cf5a8547f3edd0888d3de9092dec048ad4dc5aaa87f10dbf0807
12	1	17	\\x0f39b94e1d9215b5bf5c14813011d7f45658629332af9e0b2f4a7e0508632f8c0e08032ad555be2d0f33d113a34deeed3aeb26c2ad34b74d2fc913d593b4ac07
13	1	24	\\x19357e6a07e3094742b528714fdd498534f198b136bd397321a75db7ca6805ca51e8664678ed5497581ff03638c89f1d15e9bb17205db5d38456efb88c1c8f04
14	1	34	\\xf02382bbee8f54d541e8b3784b1d1b36045ed3ba998fa225e6f927037f2f3d8f16c9f9450d09811ba16813201bd8ddea60cb473fff4df2baab30a05f0a08540b
15	1	265	\\xe04e19e4f656fefeca9a88ec97eb8ebfea0a625508c6ea6d0c45650097d7c9520f6036d72cb0e427445e22b75cc0c78b4f7a7d78a63d7c4f2a2237be9d50c90b
16	1	306	\\xe7f675708a9afbf635cd145d006da38a8cb2f130f6bc0822f90f8cf7b4516d1b87db80b2e208d9984d1879f419e0177bb103a52a761b712dba50646b8d887d04
17	1	297	\\x62db426318a3af2a76c45e974f981523b654f07c8799ba9d1de779e7de0dcb04aef92993948481239ec42dffbcd4a49a4d9df44699b2370c2bcce7fba7c52408
18	1	137	\\x5efef1bd7ffc2226c93b5f953aeebfa3b5905e7dee8e7f2b77cb75b5235ec40c577091503f23e971beaafd8235aedd63abc5b3ba0bce24dbc563c59d7aff9203
19	1	100	\\x7be7830767db3987f760ffd0514352eddc4da78cf416646a156883f5d1789b27af939b9ab6b2eb03676593c39e471ae6f63ddd14c1813c8ea376f8b352758202
20	1	303	\\x7c065828bb5f37b0c6349a293c2f428a1f299aa958ce0fb8a922fb6121ea13a424082b8a5eab46f27e99f15a1ddeee8a057d5b09896b6173b9c2eb22c86fd70b
21	1	378	\\x439105de2faa56c673b5a0734aa85ceab74408009bf4d37bf443a64e81d1b6c56295fe14414f7ea2073923f23c946d288f97b236f52868837021f9a12dd40609
22	1	68	\\x76c9ef6f6f7304f9d66a6146b3bd5fcc1ca16f4a8f20943a1fc25b3b3c1662735e777a50fcccaf26d0507b12586b7067738e40c3ab7773a564eeb0366ca74b0c
23	1	384	\\xbf6e886af88b32f16932b7dbdf4e1dca22485b0134bb9d016977d19891e6ddf6d7af326d26064f9577c7944da4edccee38af15c3c919eb65806d7312401ca203
24	1	424	\\xa7debcc6bcfe592b2d6cff752aa7c6d8b15815b99834c93a0e8d41181817820e91124751ab8a4f0fcac15f12bf402934b91eb838f13d74c0fa79bc038d51dc0e
25	1	63	\\x99bf8ac8433946201578580620ec2723295375c5cbca04dee1483eea79b69d379bbb7c97c7f7e643e4ca154b7a0016596c3b8980a6212b9b75b035f503b32103
26	1	326	\\xa31e4e5fee6e671c6d449181ea699b6af807accc956f93bcdf078433cacd12e334f7ba5291fe2f373b0b1ff97041ba11403ff6d7859fae20b7e2b9eb852f2f06
27	1	173	\\xedee540955ccd603b35f13285c045d4d0068df6417e917d035a955e66842937f180875c2fefd327acab41ced1c25533a0f8a0382a03a235a8a8ded7ad0bd3705
28	1	336	\\xb6a51478a9f7ea0f5042a03fd085035e1b18a2960c3e66e6ef3e18c70d75ca6a1f3a7dc5c9d6b06f997dda913ff9c206d1d5c370690d7c85caecba367d14220e
29	1	296	\\xa102175fbca9cc722734c4258c82b14c29e8e6cde1300b12e75909f079f62a193695e13b9c66deff05ce7b3622d86534290bc55534af7967a6bb77a034a29c0f
30	1	201	\\x2fe539faf7771dcc34fd46da896901c48d0796c127e5942d22fb20ab1a52c69bb7a0177b957628ae4eb2858e4164893e5a2575c599422be937ff5d3d1f9b1e0a
31	1	254	\\x09ff7bdad5fd36628c300f95244a77233786ac43a5cde11972e8b21f306b9b71c5068b0489db27fa9ba40970262c2a2969978a8b3fa8ec074c1629670ced5804
32	1	252	\\xdbcaabf5424c48302a74f9c7f1b65d95c3f3e27457d6a35e02f3fdd89ee80f8d32d2e77c0f788f8d52e0b64dc9dd0ad38034216dd203681264a62fce3e656006
33	1	158	\\x0c6cfeff038bdaf371ceb47a53347c8bbc4256cf07b85225d894651c62bcc65246f49f44ee10d1b66e0cd02bad4397c810774645ef27366b56b192133a909400
34	1	178	\\x81f5498e9b653a61e1fe1cf98020620b783aecf98aa4c42d0495b83c8658e75319366e6b5536d1463b5ff24a5c2532a86905ceb8fb1941b1b179634c824ca101
35	1	88	\\xaee93925716102dad82f3388aeed7b35d4f52fe8a882c13866e5e03069fa42d59502ec2745f1075ddc35dc0bd19225adda34e024ea73333663b80100edeb370d
36	1	190	\\x65ac5d7fd3289a6f0de7c8e64aa4423de23173579c5a06beedb8cee0097afc462ff6ae62ace3193800ab9df90c8e74aecaa32b2d9eddcbfed27919f3a377e303
37	1	77	\\xa4b1de97409a7ff9e1c4253abdfd1123384a7c0f8736c4f47d54343edaa6627934f48dbf4adc1aa011805677fbdbd6ca885c412e9fe1ee3995bdf2c211f6470e
38	1	298	\\xf0dd9182157607729910a4176b6b624a85bf4fc5ba11f805264cf896a7627740a85662811cbae9df9974c8ba440fca15e27820a99856510378ee22062f012e00
39	1	211	\\x76c4e2f18f9567ce78c47c3dcd6e63b37fe57b1b5c980a59981194ee10f416d16cc845e08e29fed591bb51a29cb8d8d6768b6acb5481de9af1ce3a6b54858900
40	1	41	\\xa4c364673c9a2c1cb6325f75309d03df06080ef6b0c8982991db21051b1e98c7ffa0d5852bb11c84e96a367330a10eaf2f57f11cdfdc1f94a8d588266634a407
41	1	19	\\x98a8695f11983994d8f7753eeffeb13e6237368289a04558b907150d48e743573ef42ae0d7e1798b78f1b5464fbda6252f2c94ddc1c0c0588d089891db9bd008
42	1	335	\\x5169b96eff456f8a56d068af4a0cd95a3272504bc6c82d8830dc8cb17c638a02e80326ebcbd12f6e0c725fe0ffd0eecd4419e8e423ae844614d7bc70ca294508
43	1	91	\\xfda0917ac08f905ed4f625e204680f8c6ec7da988972bf4c273816502b1871b353945ece72585850cae2dfce6a740e2c396173dedda0493409b2c519fd7f0b0c
44	1	240	\\x4ebf817da5b58eaf3b13d587cfc6be826dc024568bc2bf5bdc51674d975fdddba00dedca01e92988ce4000fd8af9e9ba3f0dbb5d93d1da0686cb17f741257a08
45	1	413	\\xb17c12ef0b8e269a933e956c794846f1be2197ba0c4049e85573bf15936779d985033762474eb973a7933b8ef1332e27aefe44e1085989f39b1c567631f61707
46	1	243	\\x0fe31860fc6435e140c2cb81b77fa62a93bd2e685311d067bbda89397f3fcbea957b657b48cec734c53fd7eae3bdc2ce8646287f016e5bb74abc24033f08d903
47	1	154	\\x62185cdc04eb4bbeab6c573b5048eb2ed352f873025a848a958205ea07fc8e1bd899c02a708255387124b99957373931da1b492a44d48a300b75dac92e75370b
48	1	128	\\xaca3eb6afe5c23352ab802f6cacec6af14de704da734506f953bcca3e5ab3a3686f3338376872f5098700072f2c689e26726fcc96f218df12af693db0e55a50e
49	1	26	\\x91f02e10d18e7681f0d9cbc921b6674aa5012352d352d00dfeb69fa7396d2ac07d5f2c9a428ccd95b24bc798fe04871e56f2c01b1c90212da731ee84b02d460c
50	1	169	\\xbb69878c8e35bbc0e8fd582506ebe80c84060eb4a64745add319657af584901d8e5767090803c7d465c64021b0656917585bb2b97e1f9212eed3790dde32520e
51	1	340	\\x2e7dd5c10bd46cccb909e5271357ffd31aaf6a3271c571ed643e0e5ab2e99f1a715f8fbb138089867b1c6a9b94cdd56a832b71d93f24777cc04d441624b1f10d
52	1	405	\\xe714511755a74c56d4a3fac68d3085603b1005212efcb57e04842b9bee1faa57b72728318f4fa901dd8733d9fd1d8e833a1ec20775e156671ad35f93f5586308
53	1	272	\\xfd0c0c87ce70f55729c0344f95e2eb966237ae6d0e1428895de96cd31273b27d2b0cccf64b916067357b6621acd6950bf7ba52c7bcb88b7c7f44a275fef1100c
54	1	311	\\x2da23a254e0ba65bd67638613ea23b06a037690f564457ee74f81a064800fb399a3bb7f0e652564a6806d496632017df629b51102fee5f845d55d47470cc640f
55	1	80	\\xe771e816004161360ff21bc2ff9a6f1c929772de1504aabef6b1505d897c837ff25c70ffaffba96be7990daff29526acc4a64aba0995f2f07ce3feeb8202ed0a
56	1	1	\\x3df22147066e980bb915c9c0207c46c62d061a2b7356d84f29b827c533710077e9d538c0feab7aa9b8e62ee75407b220597eed386042f90ec8c2648aad6ba800
57	1	360	\\x665dd03b840b76bd0f925a9de8bed71fb71834a50f430dbbb86f7d5fa13eaf5d069d67fc588cddcaf3c20e1312906217be24d94b6d4a2929b9ead4c1aa94e503
58	1	56	\\x07adf319ddf7102ae0e21604e8535dd43c5667e412a8e4d3c2f46a298fa56c7c657e155efe34366264b4f5e2c175afc72ffad95111c2d309e36ddd6f52a43c0c
59	1	10	\\x45f07f93cd48aa3f7cf6347adb3cf1be5f0cfc3a74ab2a4c8d851adcff55b5377aaa5cf967daf51b7571056d23ad925bb06ed1a5be44e8df5b62486e67735908
60	1	350	\\x9a5458405f2094f4a6e028757f3b71c17752e49b46aeb96cb37dbb657801fecaed1d607ad3289bc13c0ab7e4f64767e5d2e644f6d2f93ed146c9a83b6ccdb103
61	1	95	\\xc5ce91f1bd5d436f50287d36572a587280ce01a6a1aafb374a19806e5b3f459f2a7eac5b382043c9b9eb342fa5e631e14754848bb3d95d20b06d45294f6c7c07
62	1	363	\\xb1746ac33955c9eb20bb0a61b149611c1182b2a57746b388469eb9d618cb4556392c64579f25a5dff0a32493e35bc2c5ccbebf268353071cebdfbf305cf0f502
63	1	174	\\x5acc0500c600d9d9f122a15393f1d5f814274e962e96e53feb75367c509da86e0614301daaf6c849a3aa67e69486f3612a135e6ee748f8c666d991f0cc32db0a
64	1	390	\\xc0f418868450228abdf38434a53a7d9639f7051bdba3eb0bfe5f490d867259a9400d26cddf90d8628be2774e54c04999a49cb936faf828e7a03282bfafc4f600
65	1	25	\\x0365e563b6fcce85a03f689f5d7e4ad81d16edb760ee26d7bcaf9ed5b069207255c4cc1798df0e10f3317af37cc5f68250f5b32ed4e74a7ee204303955c74705
66	1	357	\\x83d94dcd5926879ae7dbcda546c35c9c5d75994c34b7923f8b707041875ef7d62fe574dae666b18403614999e3b0c6a8593e79711395d8fc7ed42deab097d50d
67	1	310	\\x62247f26657ba74fc30dd1917d46a50153d7c2963b60cd8e31787bfe5d6137e5647fec52ff379c2fc050cd570014a1ac7485321a580a28aaec433f4f42c95d04
68	1	69	\\x6ed2d376a199e1b180bcdf790ad77a02e765f45b6c3fef24dbb793cb3f594fd99359b59a226f2eb12dfde1688e4c7a2f06dbe327e175abb550f1380e7d1c5f0e
69	1	62	\\xdc4d3e6c0b53316a7710c3a6f586cef07bb2a56085872f3de7261980538b787ada0c8708acedf062d37891a78ea67bf95db96479122ee27802edc72c2a794005
70	1	402	\\xa8b7dd455bbec0633d0d08c89d7f2c89dd9aa3f2d8dbc38db9f13c5c910bd05a9880736cf9c4ecb16b21993f2c7c750b4f26fa98bb2fa775ccfd8340efc8cc05
71	1	223	\\x2067265c0ee1695f5a6789500ccac020b982173e40f8ab97db1adfffc3fcdcff16b06da6d5d6aa4104cf8f98d3bbf6ff2bd49ea809977b820ffe4da29e9e8503
72	1	379	\\xedbf25c971f937ca6687c0c48dea23c3f69b8c33c70770c4a138b012685d651a1f869346f6c8fb58c9ab7e0d9de7c43cc55b7d2942428cd647ee881ea9664a07
73	1	79	\\x7705a4d4c93a9ecd268baba9d8f7ff15b4b2eb59ae2e93de284b9ce8673c41a421221c364ed737134a68e96828f66f9625a7d0beb8809f6cb888775e6b2a7f0d
74	1	54	\\x20343bf992c277cbee499723b40ca38b4964bfc56b82c9423b441e698ab4a306117d8d99f2766af70cb828f1d5b574fcd444f13abc38590bb6bf75e8da0bc908
75	1	93	\\xa31ed6fc3063b160c3cb93a8c055747c3616a6b3f0445e0edd9d491720d2ac989819ce9a4f7556a3e74112f624d57ef457035fa1d06f477cce5340acbaac190e
76	1	42	\\xa19c77273919c2b266fca4a022f77c44edc6c9193b08050be6f4a4561a298f451d0f14a0a6bb2636cb0dd391068ea95764abb880ac1fd7d3c3532bff40835202
77	1	239	\\x5e7635a0f5fa5732e1c9f08c6d68722838a88a2c42c51ef6668b4de3ba423d15b174c1f1eb95fed6e192e02b73c5075cba9558bebacc62a5144a3384f5a5b603
78	1	349	\\xbd54a00311111bf334cda65552456a7f00bd0ac4c34027e0c1cb6d325875e858f3340b2346f8e0e07e3c51ae7e7de918967852cd75741b40d74385a12f0dbe00
79	1	251	\\xc7b6149127159e3a304894428f41e5a676fb5b98d12db03ad185d91648f574c7faf96f2217a9d3fe0b8f3a82e72f8f74e8d210b9ceaf9cd88b0cd629ae9be606
80	1	256	\\x1c51c45907fb795e923e7f4a2f68e6b03499b8fcb0934aafe572835ca4d8661fdab62fd5c42a32930acb6bb1598e76727ad6c0efd49c421eda64e1512f55ef0f
81	1	213	\\x781b7f875b5889311121cf050e32791dc9f787114b32e1c64ab5f03ec0313680d5dc3ee141c77d72dec05a2515299292f26ab33f78d60aeae4be9d92208bf60c
82	1	40	\\xbf540008a56baee43e5821432d569e6368d5d1d3e171058114da82d3c958fdd830c4a3fb59476217c3afd606884f8572cd266c1fd3fd4073676055c8f1f81603
83	1	89	\\x6d54f0bb237edf33d0d52de813b07d9c3642be37dbf0b24d46f72c6ebc3f2c5bb574c5309eb87fc2a1e071727bd0748145065a86361fd4b75a66e463e44e5b0e
84	1	365	\\xb2fe4d389b3a11e0596939d47d0d20b41fa5ec67290590fa1deb0615fa92f9ad14745c3113346088c8ceab235bc27dac2ce875fad460595f47a54b9711959f01
85	1	96	\\x4e54414b95bd1773f89d6a332f4159751fc1cc4c5795e665611c318ec5a5be628608c30602ef4a49295a3f932bcc2bca566249e4f107e023c29e291b144cf609
86	1	175	\\x2451847f3643fbd484bb8652c8ba96978dc970bc1d8e1bdd0af88e807bb9e61af595ba8f293a822c8e4db6f523133ac9a9251e09b1b199eee5d49f406ffcb00f
87	1	386	\\x1159bfd3552a9dfec92f98ca009575b338a697c4c9c2dfb45830d816b440919645502088ac028fbb9c173b6ef6fe5ecb6ea20cd27aea514149e91cd64b6e4801
88	1	123	\\x35aa17739756600ebc9efaae7cc218975c685acf4fdafd6c28d09b283a2c6539e13b3193a41648b99ff182bb91e93126cae59d4610b778bc58834d3e70e3f500
89	1	35	\\x2eb4895bd7b7081d2c16c0fcfb05bdb157e13ea2343c73300890391eac28c7644f55e4f9f6a576d0ca1489f4f7672915782dae9a93f1385548cf1339d841f10c
90	1	136	\\xdfa9b893916876655ef56308c08b86b3c712b480d4318286cb1adf93bfdc72f4b483448850929c372cd2fab96a6bd27cc9567aa41d50438faa14bdee6dffa201
91	1	203	\\xd10875a62059dc560b94d242245cbe729edfa1c5ba4e739694da1c294aced24a01143761c64e9f28e0b3f9bb3c2c2e4c9f886d889f449793324a9eba2b5fd50b
92	1	262	\\x268d657dce741895baff0fd1bf4041926b38fb2c064e32743668b9bb0b07ffe0ea9fdb3c2da6590ec209e98df21f640734d1d665de2b9441fd89bb149b69540d
93	1	258	\\x52d0f691c31a18908b9e37732fd6fabbfc4ed93934e2ead2c82c2f721db9a02a1ced9021a55e27ba947d18c3d08b9f2e091cf4202758d474276923a95303520b
94	1	218	\\xece537997c761b8d47c99f84e75f18bc29d26eaf6ac29ad75d1bde66228b759f9e2de33e9627ee071659237e162f188949587df0002cc21f9428a56554434f01
95	1	18	\\xaaf708383fb842e5952d0c84d1e51486b45361abba3dd8ec9a22f60cd24d2457e29899b56c8312a8ea3af38605196563db692c96a2768f727a91fbe407bfcc03
96	1	159	\\x00c922d7893ab1174acbdc5c7c201a20c9fef47da24d1ae9bf36e0cae9e45e6b715d3126e5de6264c1e8f4161ee385dfbcbaec1f0257a7c8b6f256cfb0ce200d
97	1	408	\\xe37de67ba5a7c12c088fb334eb395bd8b85f2f301342f2e8dfe3e2a9367ecc57e1d9bf4fe589fab9c8865288ffa13fffa17cf871b5ccc825455adf09bb28f308
98	1	86	\\x0ffa85c817aed0bea174a4bd7e39e167b5176c56affe38ecea28a714ba3dab9838e5d5152b9678f09ed5faaff66281218d730846c856b8b6a53b340ba52f4d0a
99	1	29	\\x77c4ed3b45a935bc1d9bbe86b0d1cbe9667657ec9ffbbed12bca1c0e83b97a2b54f698ebf54eb7c9fbe976331d4599dd4ccbf4b0071c4a285e96ac062e9d6b03
100	1	344	\\x6e5e8290af53674fca8a145f78f5f9d780917a6861afbcb080a3d11b190fee3d9d94dadc5991bb63a96f7c16f8bb271a534dfee13be85cc15063b6c38e26c802
101	1	230	\\x02c675413b84d62d5d4a3029636a4b6c9a61e0f76ecf979de357b5535701d47fa4119df7d839a809ce2bbc25dd7866781e402cb4150b563bed2f2e560d2e7c0d
102	1	361	\\x0db62d3fb74e1f4f5b8c2a54aede978ffca4c37c6be091a4bf97569469a58b1cb9be8ead7b5985ea1af378bbdee299c91d0a879e2ee7a149936502858f00810d
103	1	341	\\x193767d67b1505d7b108e2f0e0a347532714b503b1fcbb5a44363a7a4fdb53a406c93cb803329ac300c7b09046a98f8b204eb2202b5d668e073cba3f21fd9a09
104	1	151	\\xd578b9af178b4d1c1f894932eb51f21af0d5e6879f2bf2c570cb9af6eb1cd7a11f01e8e33cfaa4785a8d19e2e79ff93de9e6359b3a16314d867063c86938990f
105	1	52	\\xf3d9d88573a6b38a61d525b9384b58b553798c523865b30b4e6d3458bc1aed83616186b87cb2506815c08bbf7a7f0f741f3dd7861bd1dba850f41cdf833b3d00
106	1	179	\\x4b2c480f90aaa9e13f5777e0f23f2f4e88defc7f1a18728c3570539d1e664924c40f691d680600a8e70e3e5666861153a573820a76d2cb2fb277c4d5d57cae00
107	1	163	\\x11292b021cac955c753300f42dca7bc1d43188c0e1c3f126b7a28775ec3556dd64d869d7e3a58b6a8661579660b724df8af69598c05c3d9f3d3009297200fd03
108	1	198	\\xc8f9cdeed19d322a27398476abb08f56901c12103deb2b03c4996faff36037019c261aae94c9e0d986e4f5b8d7c27723b65ddad163a3b0f4ccca00d60fffea05
109	1	294	\\x2c33d9b34fedd08b6f3a1743a2d0e22aee9313722afc76f35d83fbf00ee6a0e42efc33737a0e88a5ba3878806293cf4635eb0ffba156711ea4e4bc51b113b901
110	1	162	\\x2f694a0e7f55b01689620f3ca7ec366a30cb9dd9be8602a65bf24194317368b08f77a48074a7ddd4a1663a49e130977af5b9e88236ac17d1dd16b7a2159d0e01
111	1	146	\\xc43f264ecff361ad44b942ffed165cd24bbb0bd8be208cb2089424983faaad1290d19e8a99e3c1ff8d414534a4bde1019363450c6fa126b9e36a614695198a03
112	1	204	\\x8e314e20d5746c04fb4cff77af91b297252dcc33fe9f71a1853e45b0f9d05be96a2a855ea28d3b39f1841ecf5446e08a31421e991a5a9e9c0042d3382d865c08
113	1	325	\\x8d4b15839d795249fcdace4e6885d806c40dfc714da8d0a1af03cd789fb582078c4a76667b7cbd931f5f9d2949f6cc8a4217585a08022442501475c590361c0e
114	1	387	\\xe4c57f483b23d1ba397aca886821e046889abdc545772273f1c961218e3a8a5df0e5c4b8e5ccd57d3d97281d33798b96c54b008a1706781d84de71fbeb5e2e0b
115	1	191	\\x4b81e9631b13129e6bca67502e36cd6b61980bdabedcabe874f9b44ab116224cc2a4b728f643a8f29897f87d9759a58a5191b77657c42f80ad4431e743e93c02
116	1	409	\\x3c3bd4daf9509a4e9f14e22e6732129afef5d08722700faaeeee6747535ee9e323215f31170924e0b763eac93a5ec20c7d4faa454d9ada8dfbac0fa873557901
117	1	406	\\x7e6e5e48f5e7ff214080d73e3ec665fffae73302e8a667733e3932b9eb6944828fa9b491c100ceec912d8946c6582e596edf5ab8e47c2429c0f48ed44575e405
118	1	334	\\x96c2b8fe3db0472cd6c26ea15c70778ecefdfe495441812a494d03b5a421ee3f1debc63e706537e443da62286c3c320298ce774e6810ffdb35fde68c0de3010d
119	1	395	\\x177870235ec0ddf6271015a16fbdb6ae67c88f8911caf04495e8f6b495659f734680cb4441034492d029f24f1ed2bea96bd6405ce2c2d2f33de602adbb97360a
120	1	273	\\xc63929aa9545ca47ebb8cec0ef155b9f58a21afad6987fc094f917c3309f74cb465193aefe8cab36ef1cadc0d9f683480690418b9e1568ac4eabad373d02ec06
121	1	388	\\xb651ee72a70fda5610ba4ccf7d51ad7c56031ab28039cdb0b9441f77f2b0ca31772bf899f21b17edee117ed68572b6e230c1dc599bb80d448a25f24345a35709
122	1	255	\\x9df888d84ccce92950c1736b4e5b349262b6b0e8edff9d4c567a7cbc827d7e716cbc646d50abad96ac66a471a88174feecba9310f1519a4313fa49645968ca08
123	1	353	\\xb53368a38255659cef0407da744f8ea402301eb922f4ab1809cd28cf32402421e5ebacf0ea114b94257c0408875085e855b27ddcdbea8d1d33c81646b1ce4602
124	1	237	\\x5376b80a7f7bccf49f941bf35bd1dd1ac61673673f338dcc38efd20edcc841e1a8082670ace28368277e400b06a4d57f6e6863ab9bd76403c8aa5be898d8ab0c
125	1	290	\\x50bcde93bc4c503d7d72a2c066511246a93893e02ee3d79d7b5dabc15d8b9d93032ceba873efe626e7645885f3a87300d35787ba0c4a8d435710038396259f06
126	1	65	\\x9c5973b71930da152fd2b8d610299eace7ea48c72ef639b83a41b3a7f801ce1f72f46646dcbf95f8dd4885bdabea02cbc83e88bc362adc08919d1cfc04382a07
127	1	51	\\xc965a09be31fda585007eb97167703092bf4fd47b83741aae0bd69c8cecbd9b5240c9ceec26ba7a49885369bc09ce056824f3ed32ca7345e9827b6cdf66eaf06
128	1	196	\\xd840216ea64056ffd5b1dd876cdc15eb8ccbf7cfa3ab674ddb535ceb5161d4d49a4dfba4f95ae2869781f0944f5ce1b7b21c75b3c104289a04d1031612a77306
129	1	184	\\x883c1ef81fcb10539794350afdff84cd84518f553d8f6dabd52289b9e381d53b623e72cf4aea2b0bb2e4d974a6519a94ee1c8e5f16fd8d0aaa36c37c68d4db02
130	1	278	\\x628fc244f19f2616508ca8be9816e75e49e0f341b2e6cc59ae60425d9178957482396eac7caf0a3dfdc87321d459c6aadf125734c47bb18a36e18f914c480a00
131	1	233	\\x30c9346b9d9cb1ed0ccecf186ffbf60dac3e38883abfd05dbe9f274370f6d151b4eaf396441efcf7f1ce0f6ab261ff3ef2f480c7721a13f4c4f451f3e98f9907
132	1	153	\\xc340e42f0c42a4cb3cde90f1177d31dc5d8aeddc2ec8f581b1589bbbcb15e42ea7a11a37ed147bf52d9f33d044751137fe214c6aa12e9466c8b6f476ad7ed207
133	1	195	\\x0b92d852d7998fa547c0107dea9d9dcca2f439c95f7047a80ef0ee2e5d2d4f3db5e2db3872004b9ec00fda6e192d8d8806a9aef4687de82a089524a1927e3003
134	1	248	\\x7e49e9ecc51b5de856094bc9193428635e7b470a2b9b0349ee75a8e8eed6c934674edb1d1e745bf2857c3b88bc584b82b3158268bc29ec0d62818b1857914503
135	1	149	\\x0b68c947f2b359b8bb365dfd4db79cc310d4cacf77fabbff517c0c4eb3f176cc1e7bd6a478c262750e2892075a224b23011cb2bf6ae857ca793b66be2b62a206
136	1	150	\\xe563e6eb99c07efa6e77616f33dce29805531b3fb8e9ce4b3b3c4e95884f112c33b8dd12b1ca3045d08307dfe0eb275a0a56ebe9d0085fa97f27d37d2c9a870b
137	1	194	\\x8686404874fec5faaac09636fdc99ca51b3b47acca4dd5e99fea2b6d85e4d202433595f3cc79c2360dec1fedad4640cf338820bdf99b07151940692891a82702
138	1	253	\\xa167d695c8eed79c598cd10896277af8eca3339ee638e78a02fc1018b337d475fa216d50df1e025837749f10ba929ab73ca05445fbb05f507ca236dc4ee81b0b
139	1	139	\\x315fc9cb9e7cbcd1794813892bf902c67019fa2d81e1a0e2e6df11a0bd4229322c78af3c156c14b28354eedae50bb15549aea68100379b6a76c50892b1648908
140	1	47	\\x2e1c540097db59300d77ba09f183998bcec911679feceffd989ba81bb4ff552e0de2ae8471edcb12bd29527c236cf52e958cd3540ec4b5a987b63da0fdd89903
141	1	232	\\x7fb9d960ab49fe7ea99496e89cfc0eff6fbed1f1c30d4b79057321f33c2c0036a50f8705334e7af06310ecc5fd57fd9f99105ed3877607351f31062b6c066505
142	1	337	\\x770b3615009129750c53cf6b213782df3a09cb4b317263649de1d7e4d589ffe9d4d004ef937a2ec6a3f9143378f64c9187ff936c537d1403da735ec65cc82d08
143	1	327	\\x0536e7d6bb877b9cbb65e32d898b9634fb80e213864d7da18fcb4a2c9c39aab80e1829af424f6578a35c77a85cc7ef61d69547f5e73c4adea01fdd8e78a01b04
144	1	30	\\xc5cef7f548a9fffc2edb6a1a0571053760b23b2d6c3f37dd2d1d56479425b861b3557c77b4c29646ecaef32b9b39a4248bfe266cadf7b4f235cace462886b001
145	1	333	\\x2d9a999ffc31ac0288d69f4441dea1c934a0372a816f28489fe92906273e9b2c388c33f1fccfeddc2cb7b2854996e6fcaf87a33aba1f78415ece72e561fa150f
146	1	5	\\xc00d3c93d77b4c120ba2a64dac5059ef101deb49d9d59bc7a6df49b5d2f2011d8205b51c742e4f1ac52ba5d45edfa848c9c7d5d1b9b10d3ba1d9b25b3d9cff02
147	1	15	\\x91d8b3aca41c5199397237c39f5fdad47c73807f3d61f8cb33da8b52858c1ee0d51071a3ad1a272ce7fac6c4bf6715f6e3a0da342ceb0a2271030fe0d5743500
148	1	317	\\xc3e29af0f3657c6a62477cc7b0c6dad8d6a72585029f74143ac9ea7aee7a5f232b013e5faa5b1ca6e78a8da8589321b2ba0abf38d75714e1b5c270ed82290109
149	1	53	\\x5a37810cfa69b4ee07290291e561748a29571f49a3b3f1fcdd4993adab371adaf1f0d0f6c5f7ae5bb57855e250419fc13148407488c7f9f14eb891cc8c86b90c
150	1	314	\\xad22d20322cdf2f0106228dab3233093264c7275840e40a4920df4518f2bb97e25dcf313651682fa17aac9ad9014c97ad67d096f94ed121f7ffed43d2808b308
151	1	355	\\x490dbadab6ffaeb446289be55158115cd67b28c1d3d092f856754bc3b394bbb5e940eb344f6b41280d0ce3595885a9c6ea9330b568e19291b45e2d08eb6da100
152	1	192	\\x95516fab5967e66852073c1745337076e53d64dd32f7843fffe76b5f200b641356a2be63475295b9eaab3c8da0a322019c692b54486acadcd461493716ae7f08
153	1	312	\\x77cd41456b32ca3711df80af5a5027b5cf87b7ca49fe4da6ae05a1ef98994644670c5ae748b842993f050a87257ba741cb43159034bd4f8bdfafa1c587c70d0c
154	1	323	\\xd989d6eabfac52fc6f3d3c49af2f3352f1f0376b94f0b92425b3d565d3a7a3fc60ce4d247fc6988c035d638fd9ff1cdc254b4cdd128a7160c5c3865cf11fa20b
155	1	313	\\x0bce16e993b8a3668e41eaef86d7dfc581eb49a1a332139702bbba61e740334d77a9ea8f503981c224673f24966c5838ca03beb2be9321e5b74458552c8cb108
156	1	295	\\x3aa1c3250003ca9f6f077c566f6df69967131e071d02c137db18a8aac2149c529b02fa349b848fe21ce3e8c74bca68669f06c9e5490fdfbc46c9d916ddbaea06
157	1	364	\\x828663c68d15b5bf04dab5e11d0d54ae46d61a44a863cf059729d14f9c38132b530c024fc1df624a08b3eb20b873ea78b6ea1383067e9148283cbab8442e5c02
158	1	171	\\x130e4fbd32748dee72876f64ae4b6d0fc38b802e6374640078e4ea4dd4c96ca25e68fbefb1f257614c2be5c23a712472c8b40fb1bd67b8c4a21e64ad38f06f0a
159	1	133	\\x855163031c63721afd67b86a9891180b0e8fe3d940c670da6c6645ac4d3e55cc8e44c263948ff97727d11fd0faffdda7becb0c85cab8cbad9a2a76bce62cdc04
160	1	4	\\x1307c113ea7760171f422cbf0496effea426a9fb4553a14b822aec41be88693e3819b00feb691209e902ec495bf9f602b8610265a13bfa67d948bc7ee24dbd0a
161	1	108	\\x7fd5ab753d956595a48439e9e985063d298e5820c5ce86f0cc74261242c6e0b5f63b3249d2020bf77e68de101f2cf1fe4494410f34e963b3a1d8c79737b73b03
162	1	113	\\xcee006fd05760bd71c7b3f5988b49735e3e7b0d4445a6221d75d1998f09b8a22f0d4a89c205b31b2ed6a5f39bbbaef037809a0dfb5d4d2fb87cf85859b803b03
163	1	160	\\x5e8eb311ca6febd61bdafcd095729a40b441d85ce8f68832d6fcf1c1d2d6c1fb2b550c8fb8adaca0f2ecf998aea9aabd04d06c98222d454a875bc511946dc00d
164	1	214	\\xde2bacff72f2f478fb81cb40f77ef1484d4ca765c5b881c374a11f14d0d12899520e31eb1a93b317ccbaa490e1b3bba8b0fb42277164c2c12543b9dfc2c2ac09
165	1	57	\\xdb7c7e588255b1aaf97c4453eca81d71a77e12ae48571e470fde03c623717626d7ebacf0fd26dfb5db42f1c2e50ed769a26ed5b133ae189ff1f7a11c9fb52b07
166	1	259	\\x334cd5fa01406d76dd114a4b6fcf37766597c7442d6ae35d4f70cc9fa8d25b05bba9f100da2a76034b5e540513e78547ff2d883320ecf914f4710dffe1ce260f
167	1	321	\\xf7555f591e9702937b4a5608e9a8ceb8fe07363f4ad2966773f7bfecda918d097eaf80453aff9bf7a0bc62ffe7503b47152f3f2341adc27482b7099595aeb404
168	1	375	\\xd220c4aeb3e5514fd65dd418a191ddaddb5b5f97eb0d91fabc4cf3e3a0da87bbb6df6227fdcbf737ab08d084b03c79fe6f15c7058d159489b2db0b0c16b25505
169	1	172	\\x16f60991f302ad75c90b616708547f1ffa63ec3d0d49490480d20c1b71f2437ebad4b34e6d6ac1a81f829233398b8f36949124e0d2a5c5da440ae1b3077fd109
170	1	87	\\x74c2293a823b1ce99e1dbac3209882e2c15527971430d71718b6f91fcc55aff7abbc997f72d78e46405182d73b7e65fcd9f43fc1fe939a49600b67fc2c1db009
171	1	182	\\x20f6e2b653bc32a6f0675cac1cf4e8e4a552e49d6cba0087f323a0d1bf1d818027651b12c257ffcf280a54d6e21d874ae02a232b81b2cffd28b515f137d58c01
172	1	281	\\xf72cc4de82d2aa0370073714ecc87a2a262abdd552cec321cf750b18ef709e481fb438adce786a5bf2c46345d81f0566c1620e40802d2030a342c181a6a68307
173	1	316	\\xb0bee147f7368fdb0c6cc70d37240b8c15cf5cae6cf3ecc99b365a3dbb5c7cc42c33fca17dfe8e639059c53b4f68316e87d0a7b4ac6e4ed9e1f8b0a017a6040d
174	1	410	\\x9544a67e2f94a28cc02aaad0deb3850945113d2f329cffdb20d5db7b7f175eba6c0dbef356e86150de7be0061f03a5cf6a3f1244eb5075cc929246a80b5d3204
175	1	288	\\xd9652e6d460d474a0b830ba6c5267342be20280c108d78fcdfba1a1f6e19a8bd3b48a7ab9dedfe6fced38ad1382e211d5096a45438430bc6a042b3add6a18a09
176	1	144	\\x16f2b2c2c77ff6d683f3184a5920e677217efa3f5e99db926bfbbe7dd5d6f86a79f0b41064035cee643a450f251d9dc59a17e2af71abdb493187ef2146dd730b
177	1	135	\\x79eef86cf7c985af2e2be51e4eefa7f462a24d718fd4f0083d1b2852bd9602a86dd1146d3df5dd7c5b859c001205bb08e960588362002053fd60299ada941103
178	1	319	\\xee9275fb55eef19d82b4a1b91b0ed7435a0f3253c9e2dabc45f8ba167e4520a424329e7bbf5c6587505d9ed0741481b00fc92e1f5df7cba73d02d4d2f33ac504
179	1	188	\\xf7c0fe504692a60b426dc3009a05d72ea603534573ace1055ebe556672bed0e3fd54379a7ce105fc175cad6774f422d3a4906dd240bd1ac184767374a992130c
180	1	270	\\xdec12e7884f77784b18e1baf8292d919280d6eb560a62c453249804257e26fe9a95e8e370c5c76ff5061be73df4a4d454e7e72c7116afaea013676c7af32c906
181	1	12	\\x5c68d3c89a6b4db57f222db7db644a361114e07422b20f70c230eaf5c04c0141b13cbf01532c0270e122520e85e1ad9ae61c0d1030fa0bc91137a22a508a4401
182	1	127	\\x107bd5d4c326a35d480dab4fa73f46d64fb18b971535244d3ab075994f90d6af9a647e83de1e846b61977d67d6e24a73a62c140b15a4b9455854ad25850ec507
183	1	67	\\x4f58e48a21e320dac381407418b1c844d5b6d727bb7d1e646f403b867a59cf4decdf61d451cbf8c201b2c9251f63f0d994706eb111ca347a353e936ea19e8308
184	1	261	\\xfa719325c7a07a5931507e1eb9ad61ca17d3f781751fad52be1ac2391912f754a68a6de95a75307ed77f907981ef3126bbaba05d1608f5d176e734db0598ce0d
185	1	132	\\xcb8a91fe91c1c2a8077cf08d333be4476127c7fc699c162e1b23bc68722f02974840705ee0805416f4c866bc9c1e8b168347e2d2ebfd78b4d3b5568e1014e60d
186	1	366	\\x27c187a352d86c0203578d4465f5d42774faa710e0b34b622ae592d4bb05d321ee3dc5e97e5e455d13c22c0d6bd21b4bee125bdd2c41b399188fd74e1f13750b
187	1	231	\\x02e5395b8e3dd92f8df05ef628f8269506926058ad18d4edf18c72ea40b079940e106d74e5913c0c4fe79363435217a532f590c03f9f31b66d60feaf23c34a09
188	1	371	\\xca999c1e34c27f5c829be149b1e19e49dd844eb9b7d79f405a11e9e8798c5875b5b80900f3de464f9cca30179a3a38b2202574c898fa64b46776d38bf008b60b
189	1	138	\\xf3e736d00b4242bfe9cc299879eebcb06bca6b88cb0099b3a24e8f1c6f8fa93825ab156554d529cc539b7267b7af35d5912996d68bf7df1f9ecfab600bd54006
190	1	105	\\xf7f932c89585f253a82651c8722a36d94f925c16b3cc4b18006c21fea95e4bae7f8bfab72767671f4462e45b0c0b4ff140e410dcd49de4b5e12db680a6d7190b
191	1	245	\\xaa35aabad330c83de015f1923a16e9c2699c099d7cd2a35dccd70d3ccacbae3e6688128aa0dd6f3588e7d9600272f903c6a8c434ffb5b5f6e3779fc9bef65f09
192	1	234	\\x7b9243da23e19f529c22695914134c74174e9f73bdc0cc49e944915b8768e49473913577984276cd571c2b0386cc254a208731fa4074a37ce9c5ae6de993530f
193	1	267	\\x695fbcfd1bd6d5391ca6e7a4267627bcb9691c6b5fa834b3ac8a29002fb981e7181bc41548fbe72efd13ffc09032cd71301e1e61ad12c6a11624aa5aa400f30d
194	1	301	\\x3445fcabe03bbf8d29cfa9cf55a2cad98ce50707cd30d939219c05f44695f98eb0be2d3fde27ebe1703adb7f12907e1cb0a5b792cca1ff7061ce0486fac1af0b
195	1	277	\\xdce5c31552e38eb1d30eabfc7cc2ce9377ea52e507a6c8af3bda3d5a0dcc32fbe5e04fcf9a6eca0b30f271dd471957d1adbdb99a09a5d34c63a6dec1453a6507
196	1	16	\\x79c38d3b6420f5b0a6b328a4a6241ff12abc02ba3abc9b1095ca7bc5fec5863fb37383f15a639a0280f9573cb795ac9ae79bc49e993a3e83fa79ab843276e800
197	1	6	\\x90cd5eb53e175b27496e47167ef04f98002fd0cf8788fe5de79f0c008de7f32e8fc73894af423cd3403f4e12df82eaa83930cf313a5fbf214f0c8711f1be8f0f
198	1	421	\\x9d95fcc59969fa816a652f1eee955f6bddb3648b12734f6658cf1ae35b564d907dd182bba149ac1032895570beb234b39db6ed4745f0acfb47e8ee051def2700
199	1	129	\\xa00c2068f7ed7424c21e602e2e0598cfe0ba18365cd4dd11fda62c1c610f52cbd8e71dc7a51dae76f04961a59b286b7cfd466ee169284f4938790ea8f1207900
200	1	39	\\x0d6155d494a46957c37b662f735af77935e4b76648ab613dec08068ea85f2fb3b5f895d020fdb2fb09d871edb4671b80db2028a4b4bee09569d9a298398e6d03
201	1	102	\\x6fe600c8780732f4b823cc1d02826e30937051dee3ccbbad0e95ed570398f22f76232a4a1bb2ce66b7ba222afb1ea5efa4ca88177cf20422c4413773c8456b05
202	1	362	\\xbfa31646f514da3e09089d03de4ad20d729e572bc96d8be384ed07269a5e0a3d68882e8b7e0bf864c71029f068895887c0e3f356d4cd89a84e964dfb7e61c506
203	1	271	\\xabd6f90be35df4a7498e169050a532bc17e530faa99008a6d733b94418199065363f0b8b3d166a1edee139beecfed217b994429ca6f495334d2951de1bd8da09
204	1	73	\\x59ab57e2dfa5c1af86a8025b1be5bc81806e5d73a600197537331ab4b8cf9e290058f6594aacd449e35ad9486f56e78cf204c091179e9641d2915ed6415ea001
205	1	28	\\x02c8e944c6e655926602d766c79ee093c4ebb4b582de74e886dcb60c67f5b066072282800dd259f6d6dea4d567a238d8199620765e7daf66d50eab751c025b08
206	1	419	\\x48fe79213d15321726bc85ae1de3286ae6181f55da376a17f9072a912441037e3207d21675669d6e2032e5e48acb0380d275cbacc517de205bf72d2f6d93ce05
207	1	3	\\xe134bfd9c3f010f905db042f3e8009ae77b8c12b4362e596dd2f6eb4c1f9e2f06d84a29e5653dd87b83ab7ad0c48188796b517d731095dbfdda32f7932377804
208	1	423	\\xeb37072737147763c4b69e4ff741b334084ee4772a6dba766d0689ccd5a4ebe5a7e8fdbde6c487c33a8d41af1aa151aeafb979aa45ba53455247090bd8d3120b
209	1	101	\\xab3bafd3d6358c6a7f735a0f34b80a85c4cfa46cf3b140ccc22715ccbc426ba2de379ca4148b1b88fe3354818c36c2e81efdbef33a4aab1cbf4b4a9f06c56107
210	1	48	\\xc36396d375e7d185967175886ec76a9ef86c4bf47657f627fdcf3e3aef041a33ddcf0c9c661cd0ec20e1a4f86620210cbc3b5596796941128463d3356d708b09
211	1	263	\\x0d1d27c649ad14213eb921b7f80cebba85077647955c2e01b63d512d914debfb9d43bb2b1c2d0248c45805c04a175a69c6963afc63e78449b9a7344bb51f4203
212	1	119	\\x37987927b322f2520f4e2924fac6ed35c446f9137bd563caff1d1dfd80b8b0b2edf704b8147eaccd2e0189a552eb2c671a3502016d6507deb57e60bf30d8690f
213	1	207	\\xda1053040a7baef552a52bc5735ea580eeeb28c359bf51e869280638ef1a96dab4d090f1b1a63e2053d36c3ca1773d34d10fd06871bf659ee9b6ceb5d81f7e06
214	1	352	\\x6db9def4db5133946099ae3de64099e68008562b267ca135fa5d1638cdffab20232b7add65db43cd4795c79c782c2b0ce36743d04adcb6f7f0441577fe9ccb07
215	1	264	\\xb60c358ba18166f82f1645e8c4f26777505a88de21c6d22a4b5e925499550e5ee94f4825f09d90ede7b2e0864db6f732c9b7747179c5218988a8d9f6daeb110f
216	1	114	\\x8dece950c41f8a39ac7a3285a846abd46475b8c91661b33c9e700ac3e05196d3603ecd7ea93af65d833970c1edcf5274b18970e97d3944c4dea4cf9ae824df05
217	1	111	\\x888978574af2f5a448e9cc0ce014fe6e674d30c39b02d2c59b31b4e359c70e1f25f44a9037e7bd706bfc95e11001a558fa110fddd8ceb7ed1785d8dafb4a1809
218	1	71	\\x10778c60ae02c22592654b30bbc8c5080b4902bc2072046173e3cacf196450c169632186b488addba752a2072857f33e284ccab61b540b1688b674ff33f7460e
219	1	83	\\x3e7bea11dc09f6255ada93d6b421fc48361ff795182e9e800edc52de33879cebcfc9ec3decd9e9a784cded3541835d07734f6802dce2d130e773386a841fba09
220	1	220	\\xa4c5648e79e6c4d6c483f9b085f965875a6bd5e6d049677a65e8fc6830b7af61b127a00e2807068120d786b24ab46e76c0bd419f0d18971e1f20b115c12f1901
221	1	416	\\x87d6c02548175b20f8e20c3d30ed4be52e9e0a565c7fc4a4af68e18b5ced7deef8323596157ab567567f773080f546d18383796118714d9860de2f096968ce00
222	1	284	\\xa9ed7ebff702a89be843f9eaa4bbc18d1babf02d6dc6ecc344e85c3cc24f000675bd777a5992473a8a933a3af5e9f4a0604a460efdf039516eb9a2fd45145f0a
223	1	417	\\x0913f7ef3efc6c2ef8326ea03e835f31c6cc1a5b3efd8ca45d2cf6027e34f881241145c425d5adb1edbd4ef12b7b32087183a1cf502daa0df374a3c703d61505
224	1	226	\\xf8eadb3898b67bd9030ef22f4b9b6ab47576baa9a9da74aaca1e223441d6d0a0c4cf33bab3d77de86dbb043e5d3753ee6c4c77b8fef04702ca6a7e2009cb5807
225	1	120	\\x700968d383ea05a60d30a75da681e0858450e837766ab7291a2eb627dc2fceb84791ff1cdabc52676ab3a58e756d5520e38ee4338450a4c5af4180b2160cc10a
226	1	110	\\x6b1e023b8930e116479c74e6df7d892f1ee02405f0c93d48b1eaee5ea19c6afb047cd0bc585f5c9564c913d2106784b8c0917dbba124603194fd8e8f47ddb00c
227	1	356	\\x3160f7bd6fe14e8b4ee77ed183e6ddd1d67fea3a4a6d51f7ad00de04fb23532e40c55693a6553c0475aaf5db54175910c9b762e52e3159d3af38850a46d6100d
228	1	31	\\x81f43cfcf561b721ef253ec9863611d8b3bc295b4d7854b9e57f97e33df1ad03483322f0b8cf07bbe79b5839f2d51f152d224a9c874061c4fa61094e37c75c0e
229	1	167	\\x063fea6af822d8494814100e96994367978a653fd3298715a37bf7ca47a8c02bab7009c75407b743bbb6db72ef519d6f0bcf2b3321e6cdf7c2b7bd58c5f3830f
230	1	121	\\x70f5873252d421732f8799fe928bdb688e6b6567568dadf9bbe9ed1a4c0dc70a9abb4d9b1aacb18959f73e34aeef62a81a41278c93876d049e19813be8dfc003
231	1	358	\\x0ee5909843eddb7bc8b99701cf4669f114fe2e85c8ca4490a7ad94c31784afd0002f85d1e14ecd408f1567959e1a0ee1fe56a68f7e4592099babdc68b16cd107
232	1	285	\\x5384d51eaa9759182661096efab6f4962bf02c71c041f5e7dc4c84a04f105c6c3fc35b3728e7ffe60f1619848583aac8bcec3f9e61ed8df9bd40f34653149900
233	1	117	\\x9c2ef19a05ceeea1874ad56e3471033401b6ef714d54054f43c8d8ee93143581355bfc694dc184f0f311259735537650d4238e075d2b5bd6c0b3c1fdc78bfa01
234	1	367	\\x33c07eba3e8fa15265dd595f4536c48e5677f4963d166d5220f3b88011b3dd8483c1c2efb396afcde55a6aedf2da7c7792777f1ae15c3dfd5065cf855c622f08
235	1	200	\\x2d8b2ad5dbd3e7a23eb28dd75d04c9e4666839ab5d84638959aad7828731311e1201dbff786d11a2accf1a2454d26202dafb6f5b95ff4721ab78a660e50b770d
236	1	147	\\x376135c9a51f823ac248cb12d99fd26dd4e4e91cd4a339d6bb0bf1d4764f7dd596184b36657ecfa9cf38016ab63d3de12f100eabd3e3f8491fbab5b523652105
237	1	332	\\x07b5cba414811c4e2b29dea13602acf3fc9cd0f525d0741f70f48e9a3ecc86c7c72305e06b65fea62a4c174cf66ac7d4a0a11e39092cb59d719cabfc5c0a5908
238	1	165	\\xb3c28ce399bf8fc36b8513d9a137d515abf77a36b4a3c1ee575cae26053f707730b06377db419f9a9e4a6f406429774ad471f85affa12af2a2c8788dd61fe103
239	1	64	\\x5fab5d500968d6daaa203d56ce118642a0b3bcf0a35931d74fd752024ee4d5fefb94afd7607501548a5629de0106837b4f0ec01919b8597111a4c83e40ca6206
240	1	177	\\xb763b00598a6760bbf87ae87f9fe755ed72483fd55d157f7bebab2fb256bccc5ba2d90940e5630ed15de18335d6fbad68e1b6fefdc581c0d702ad9ce0afe7a0e
241	1	60	\\x3927e3351d55d1e39e072e9b8756fd158b886df9d8b7b6b59cd0cdc2fb74f708925cbaa9f841651e6568c28a1d632b68eb2f7a543a6d59d50216ede8f16b4003
242	1	193	\\x1c539e82a58e42178f725c8946e409e7a345c30eca9d003d28baeeb8738f028ca6320d09caf5f7bc20b596e63ca465e30602a6c46ef5d18be4cad516cbc13b02
243	1	134	\\xece0aad4e4a2b149917e461758f2ae3d40134deed7978a770f894fdbc4b77140319054b0464d2413b496c3fbe5f29f437b4c1a771abddc646466711484c07209
244	1	45	\\xbc0e3e74a2faad9d90f6fe568299370c6bdb78f3e4a3db126c5d665f1ae8546d3c5364431b73d1570bfb194f5ea856777f226d92eee66e965df9a55cf49bac08
245	1	238	\\x6f93e51af60b6660ada87e29973e2283f78f671a40c2722454dbba2bea7fb37d4044dd427175288f5af39f2f74f14e5e44707441ddd71e46cad2a54735c5a007
246	1	279	\\xa810623ec3529d424f4cc83dc72cc32884f59376900533c4b4646393fafe97bb8e12a85017cb8059ca64466ce20a76170a4f2bc682790273007e81bf708c350d
247	1	46	\\x02d6c57f783e89a429feb3eb1b474da6b05bf25c168d8027a019051bdc3e6bc555ef6355e014cb4f17202ef352c8bfbb2a6fe69fa593de4518b8a29b62fc1e03
248	1	286	\\xb2d0665094d955453d131176065e3de794572f647a41aaaa0e3c6ba828d899622e704ce059a6817ae9755a087db11c4d52c54157ad09ba61b52c9ff93053b508
249	1	49	\\x247e432caf237888cbe19a8ccce0e85d4c289a6aff9b7368780a27a81f47b8a9c5bdb5d5ef1aad3957d5cd869005a41b947c1eef8caf1e368aaa0cfa31807f01
250	1	74	\\xfe2275fa4f8aede42bf8c0df5b46adb59126874876dd160fe36ff40a58d3743bca1851f4b16e8be7e8bf02a8138ee3bcce344b21a908baba63fc2bd308d68606
251	1	199	\\xad08068a02fa53bd04226e15258719348c93d6042b997e9ae750141ed25d3647ce3963cfa1dd805b961e46051b81561fea5ca2e2f6feca6940e7183ecd60960a
252	1	50	\\x7fb767d7995e30ea96b6122038e216686a87db7570106e8c4f3401f7f0b640af47c1704db05ba34f2e5594bc1472f4c2765ef15c59167d9e159409cbdcdd2103
253	1	94	\\x9fb603a3df2838e72a12643435af32b2d0dbdc312bae6f1dc7263212311f62301b0dd7d1d02399f42392f1e4399e7c6407a00e4fbce0555fc572c9abe6f24d0a
254	1	269	\\x7a02f3690841d0548bd8e6d53e4b112193361dc2d400cac95df50d5859dfc8749ab5d853123c75319da9408a0dda801e019f0e13c8b56db080271438b557b601
255	1	142	\\x67f1f4bef3157518f2dc1830f33ab5143eaab5835b05f44ed1e3cce7bf9793169e637443074182a4e0dc50b82db554f2d56fbc84d393497ac39eb3ae1944a501
256	1	61	\\x44b5013ddccee213e0b1c3eff26826b97238454a52cbacb108a730439394ef4c8e3fdfc900734b1ff398e92058e0aea4b40a35ab592a03fea23607fe8be06109
257	1	103	\\xc88d1ba8820d3c6c4724394cf2f644542053071fa7ca6101dd89afbe1f40ec2e4457b7894e229ad8934df4ed48ef84845db018a4d666e7a1d8ac8fc5e8959801
258	1	318	\\x87b2f5c72d303cd74135f16365d97ba00ca1bd2adb3a5b457142678cd965b5292d82f7adb48ab3c4bdbdc44e95853894c7454b9c8b09b052afbc739559c47007
259	1	397	\\xffc9cee60b7375666bd4d9311c07f9d5affd1edaf5ee4498483b69098c21f098fb779cd7b967c1586e2efd7cda4ee21a5a832624701ba4149f7737ffd0ba6c04
260	1	274	\\x4e322c92a753e1e5a0c2cf3fab87245cd48ec58b5b3b30a51f8cb0a4f232a5d7ae45d508e8f55a92e08e05e47ad1cf2a72c169722eb8679e9346eac20d410e08
261	1	131	\\xc3cade3cb07d992e7fc22e4c54dc2e85a49e66a41988cd47a238ec7092b9009c1861cebeec4074631c38ee371bb733a59ec4e2a21fa074e3684ed5883a29ea03
262	1	202	\\x02b186d9bbf8a7fdb50213c9436d2208f90c3c2d58766654a149cf579a8f61da58fa238bd4b54baa48693780a76141dfbb1005e32429ca613952c5d45be1cf03
263	1	302	\\xe00b935d144d9821697710cf2eb318d663c53135b9354eb5d80d60f3dec727cf63bbd4cfb7691e8027734b0943757887b6df0d7efcd9f5d56df4a107cc64d709
264	1	229	\\xb207fb29027c6cdca24198cf765ea62c15b03d3848fb3f02fad62c417eaee1629b82b6cc5bc20973003f2d5fbdc9c4e66d1b78f170449556af83fa95335b120c
265	1	412	\\x76cbeb58bc6753073c08157cb52e76602b026141aea2d77a46ce787e451c39ad1deab77b7a51da2934894241f90b696acfe0d05234fa3ae18fdd2780139ade0c
266	1	242	\\x49e0f827619234f5b4f1a8fc007a889203fbb74d79c712884f1e912b9541af1df9f7289a07a238667d992a9cce029cdf4f069d5b9f1d4a2d51ef87063eb6a909
267	1	166	\\x60681000d75d58fe78372d80327667909151b26183096ed85fbae6021e4beda96194a2011dba86fe37db51c0365531fb7ddebfd94901cfa983ed485fcbb5c902
268	1	280	\\xbcbd14134deba578cb8fd10ce382c6be129033ccd0a8366280041409762174c18cd5224d0dced9d004e2a44f01f22a0aa4acd3b42a108736b56c1415f2610a07
269	1	13	\\x4b9824a4c39b5a46b9a655a0970405a5082048de965f9ffb38dfdd1bfbad0edb8c6c087f380bfd6e496295c028135dcff20d415984292a642ce0929f37795b0b
270	1	268	\\x59cb944a82b01fff46b33950a5a1e37fff99402062e49eeae1037ca790d82baf546a45ba968a4bf53c8de39a73f940c95ffb00d889dc408efbaccf4705fde306
271	1	235	\\x478e5fa28ab6b97acacee32b01a123d5910127595f244f21354cec38f0e76eeaf51ebc2b0e8b9f26b57bf3179f075e4fb1232da7518eb343cc6fbd7a8db7eb0d
272	1	289	\\x751085aeb60ee80d21802e72176ced465813bcd23e974431a4bfbce87983616398378160add45920c3d723e6a168493c83e18729c9d1ced5d939acdb0134a707
273	1	398	\\x62c177fbd0b475c9bade11c49648586aa9218d9432700a16a8915615cc8ccadb771361c5efbed7afa699fdd08377e7a00df39fdd75e51b9176ee2f965dbf2002
274	1	70	\\x63fcbbd232a5e9581dcb4f8c63385deefc5ca1d1613b315bfa88817293895e08b464d67c6994bc047a58233ab33c668caef82cf87595a463c855cbee969c0604
275	1	112	\\x09e9af1f9c3b51e634f81614d2a8128d6d98837c47ebbc1aea789524097b3d62989ea72d56171175e7e29004548dc018bb333bd10de37a53a29acd927b71e109
276	1	59	\\x371a5294bf4b4e957b3894f2d6df2cea05653c09adbdd0f8b8bbab29a7cda657c8005741bd0417b614e99107081534d3760431b7a3236a390e59af3bc3638e06
277	1	228	\\xdc30f3276cc6f8a13eec79a972724f261b95d5515534c9bcc20220ec4d793ad27dd1e3e42dbe58f6ce32aa5bef22a85e74687a377e9575359d49f42388602a0c
278	1	345	\\xe9c9a699e9470c30e543a85ac3e73417810466088080f473f62d2700b7b4475778d90ea2b41f8e13b02e7bf82ef29802dd5b5aac04cd5fac4827736a81ee640f
279	1	155	\\x9dcc6e678b65b2f5489198cbc69118cad7725c0b5f8f71465b256efb492ca99e710646a12a80ffe709654302f6bde2c8732a721a5e19a1e2c90a25c80dd65605
280	1	98	\\x40a99a5dbb5997cef03d3e412f995424aec3463b8fcf4b0d0f875768a4553bb5b7496548510ceacb0722aa7928f7261021a528627b4910950b9c47965ae42800
281	1	145	\\xabbb468fbc9673cefc6f7d6bf9a9b8972ffc57415f61f2faa518cd50c67130d70863ec0fd392a05735c21503c215bbda08f0912e3e00862c5ce4d639b7f2ff00
282	1	396	\\xe0a1bc4394877ee8d0028f0eadad2af6994723055e905e37104388f3b201983283dbe271131c135e363a543ddcb79d20e6171c311690a6771c4e21bc31793e05
283	1	315	\\x8d5a5873043e5e1d4ced676900693e88d7be438d0ec2d53b5bcf98f7d7f2e105b46009390d637a22ac7be4fe85c848947a8922a3ec9877407daf9f6f620b830e
284	1	216	\\x18b44e93ab4c04f33e624dba1953caaa6924e82779fc0d7d7ae75a7cdeddd758dfee425d0001b68428c8c84ead4e74474fa8b1e2fd7230d8da99e9169a1e6c03
285	1	156	\\xb64e61113834f945ab400f7103dde2e4cc897c784a42ab4158fccac51c37412a520ec04dd2e68f2c17ffa2e39d7ca096898fdd15d2cf26b223fb57b0710acd08
286	1	283	\\xad80fc7f4b64ee3acffa630e766a0d4d0995c8a24299205ae22f6f86626053fd095773a578ef84013c26562d29170ad7b564c5a04b467a8f4fa305de9ab74108
287	1	328	\\x790d5038d5fd474c0697153f1090669eebe6a8db874281c194b228c3783d3d4fdf5183281195f2aa4c6f0dcd00b01e63b02866d28a40c77603687f1d9e4e460a
288	1	97	\\x58e994a4bc81fcdb78cff801b51d402b0b76705b493de19626a63d31ed132c3d6493484c747978d5da18da42aa0db927805b73b4d2780d65aedfffab0727630b
289	1	14	\\x6670e7cd0c31ef5b3adc26adeb5286713a626fa03a2c04ac695cc0a714610f67ad6f6a5936144d0fa6f9be2999b7312dd079cd1e68452309f31eb0603375b90d
290	1	148	\\x1f2b95273ccd05e2cf14ad3f3c72ee7780062165b94e4c65e1863ed5d1b25eb879df4448fd73b6607e6521de137f29d38c658c4e423efe0cdaaa706911d2da0c
291	1	206	\\xa73a22b8b837b1753381f944ed9309ec67ce619dd441ece667575ec3faff9df664b9a879440a353e515104eb72f504d58a596b41951ffbf18f2562a010467d08
292	1	186	\\x85b3222397e26beb580a91500f5e68bacadba211bf580032cec0192601fc45a5e895ebf36071b7846d2fec248672bbdb8652f84d8b4bc0c4a7de1a6a490b4409
293	1	189	\\x7bdf23b58834cbc42fd25b9b9d6e25a40a36dae0f14652a894eeae924f5ccf375782d0e266465dd466b37e597e732876537e1055396421c0c45b90e0e5107b01
294	1	354	\\xbf86f6768190881fce2a3b79fbd1f659495a2037068c0c060df44b478ce914bce73b64a9797d79198aed8008b9c89d2fb4fd09b346e3a25f019c44231a52c90c
295	1	372	\\xf04d6d99cc85956f279c0662428504672cb7b8cdc62f741d16cdfb3f6f569a8e2ebfde2ea87061962183294dbd12a0180d61c6634234e2bfa102258e69201204
296	1	422	\\x6fec180f61c76823c6a0833d84af78b8d4ed02d22d18c381786e543673519bc57e87f55dfce4943796dd39a1e280aac66683569c96a36a3968a8bf7ea616aa0d
297	1	418	\\x640d1b603e3c237beae740fd64e97f34053f52055fcd3203e5aed19726f903e016e715c9c7d5ac118ebbee4c3cc32cb770f6cab7c7e1596ecce0418b45b05708
298	1	81	\\x3559d072ab5e3ad01d85f72ac14159b981e4aec9b23a0dba03eb0105e7e88b513dc458040f9560dcb95a37967e087c210ee93fad4fd87b42ec0a5763f7e0fe07
299	1	236	\\x72854b868e207f160f691617be818bb2ee5deb36997ad0263579570311847f8e8523bb0578d133c158c3fe3e97d7f646b7116bbcbec496362dff18ae97d0ee08
300	1	197	\\x5468a51ffdd850ed3c6a0a54a15cae8b0548aff90c41e5b3a5d1e101656d5caba3a102fd244183594f46db1d0d523b490c665037f416725ce8dd4428b4f87303
301	1	23	\\x1692badc641ce2dccd38a3f1486616d568cbea9f347b6de1c6bde4c15876823a4c21fd56c482b6d5cfebd26ed4a9cf87029ce0deedebec32142b978006d1dc08
302	1	324	\\xeb3a491be932566b9305e8bd572dee4edb7b6b953eb4e0ecdd96b72eca1be52bf82ef6a5bc32906b831fd3e06caff73697a9583782c4108ee982df6a31aa2c02
303	1	187	\\x2be6c6b6387190ebb02ef7cb9eff733ec9c060f242f37ad6e2e53bc3a983f8eaac8d81747c796232cfa5e2d38c206cb7ac49b54dfc0d34ace55a150a6a29220b
304	1	266	\\x1603be7f158ca72fc85bef93bf4c1e9b798a4b1ec316d673f0d011812e3f7211f0b78a94a45500c6ff545d629ba4d98581107b62fa77b0c51db948f0b494f608
305	1	21	\\xe9e2e8929722aa33da7efbc857aa44e7e94a0a013c164a72fbd2b22bbc18f38adc65a136994cea00945d7eea683f6fc8d57caa0f20d4a76cdee765d7180e130b
306	1	369	\\xec31bdd6c119b0ccc13dba31bb751bbb0863c455e8ecb916c2c07ed567c8bc703dd7b1b6cbd6ad720a63d7cae987b47bb2ae24ff0f70054387ad4dfc7933c10e
307	1	343	\\x7ac7caaa33137cd9d845561d8f2eb5e6f1c3b7cfd93f6ffc539956676db0b3b217025fad8938983506fb83217c63cbac248d85c58ebce873fb0ff8d0be3e750c
308	1	164	\\xfc2c538f73dfc815daa54c147b644347547d5f372be01f83b27bad3d899bd97ade2cf30ca5408d47d8493d535ca05724da6eb149364eef3eaf0418d2cbdd3b08
309	1	368	\\x7dd8518444937a548b5e860481bd2241cdcda4fda58a1c0cdc37ac0888be5cbd39313f7ba4303a8a798bb203290fb375eb56fb94b42f060c50f5247f99d3db04
310	1	33	\\x4a17ef7f066705daba868cce3d39ca62496ac2804f043deaa118017ad9101ef2d7c3c83c6857e096586285e4cc7f700075d04f6997464bdd6ba05e6ac83f070c
311	1	399	\\x4c518f09bbe9da3e7ce9be25b9a880eb4a30047ea7c7ce816c11529681d3377ea92f3580dcfa2a3cfa4bbe81fd0e0aa99e31b32a5ee9b70ee8bacdc79abe590c
312	1	415	\\xa829b44ec1fe7f5379cbe14027ebc922c1e7bf001b58980d9b10e7e65b01d4c37ce4315d345a0116eaae00e2e19822c9c3fccb3e6492dd2d8dcc2b434c32bb09
313	1	322	\\x21d298914946acd7d46932bdfa6f0e521afc0060e616d2ab37c32ff4b9a9352699200a0362baa90a024d541a9a27fff66e2e176c008af40d85a756e3b9dcdf03
314	1	293	\\xfefc084d65749b1ba2255ac0a5c87d3e1f765c01744174901d9c4a8e11a3b39f8892536bfb0cadd9304243a725bc4ed116960d543c0f307533c281ed672e790f
315	1	217	\\x238dda771acbe8d042a50a16bd2ad062b27cf94475cd875b6b488a1ed5768d56b0d1777376214b2793af3ba9cb6adde0fdcb909a3536d716d136ab0630141d09
316	1	224	\\xca3a195202cf7c4ce97494b15835a0e02a6a02bf81568be338a133297f403e5b1379c648faafbfc595d8b838533637452fc05eb0cc8ded908289c8d00f430f0e
317	1	55	\\x45b1826a5376514d262bfe77d89065971b34144fefa448ca683893d48c23622a4188e79b09b56e948e0c039c3d012f03c3adc69a88233d0b693bfb2fc6544c06
318	1	403	\\x7854e45fe0af042d3836e9b3f2be9a7d12fdb4e89424d5d1c0cfab8e9159df1c295dd170da9fb1ab565502ea92cdfd785a1ddfacdb215fa9bdf47fc0f9a34403
319	1	176	\\xe7ba9f9ddd025d0ca9bfd0fa03cfab65ed853d2f0f8d28b152884ea1bc7d1b0f1194fe4e1a646fa4ebb6ec7d78b8a82695e700e845134831be330792a9732601
320	1	300	\\xa982cbfaafb9ebfd0ef0c3b35b05d0be12bc283c275be8bd1fb2bb63d4775ab2bbcb5d330d92d72f1e65d626df15efd50b2b44015cfdcdd075396a78f96df006
321	1	9	\\xbafd317b9a062884c18bab8318ad06259b7286de70e74e8e90ee896e1594d6f2f332420a579ba8781bb5ab165e721e47db8179722e09d70cc84b4827a3dae105
322	1	125	\\x5f76c52fb8fd95d873ec22b15069d2eba6beff0e2361ce5c212605be44db664a2fa95d14791bb355d4fd48c94ec0ae9d17a64b5906bfdb3179f085267bf8af0a
323	1	107	\\x0c93a918cc85badab7f3cb320b75b3f5046cee99706398a35df68f41d692c997eda6d2fd75ba81e07279c5c3811bb0edeeeaacc7618a1e9b6f5aa9decca0470b
324	1	249	\\x646ed02fcacd59c7bc5c899875e92ac94727058dfe7fed73774370451236f6ae1867d3c5a935a7a96f7797b0587178d3683a8dd976b3ff7143c6628b502f2906
325	1	116	\\x19c5fcc9893bca1348b51eb09725c483a2359315397d755ec592d3d3aa0673aac8c1e083e99a287b356f84be4407cf6674ade3e30930e34bd6257b9515fa2003
326	1	215	\\x794a5a06c8ec0d62411a5d68ac5e1e2a2497574244609f7ffb61addf66eea3f323b988d6fb21457c697f61c5719e9732da56bcf90a270fa7358b54b2794c1009
327	1	373	\\x5420a917dc181a6dacdda86485de71f3d8090f1cff8427846b3aed108a173542231ac19d5d9c8accc6be57fa8789fe6389ba73d37ecedb65d4f6a2220564d801
328	1	168	\\x8c87c6ccf7f5964ba8aea3e8359caff5af49ac8409c9b71f9ada70b4ba63fb67aab7962f6f2acecc5b3d266b4c9104e3fac39910b8c1d0643079c9ac37342b04
329	1	37	\\x68faf68b1b8c3cbfbd3254648548dc5035889911155394b184a27173871f45ce7443dbde85e6817e41d73755845b17e83971076f6ad928d33ee0772c780d8706
330	1	36	\\x29695b9c3d498817b71c474954811f74f84c86a8a0e2783f069030206465a88612fb697906df716456cbdf7a33a669722b81c44b41a3ff066d5a7cdf0bf77d03
331	1	99	\\x929928a1b85525174cc1f722568ef31e19ef1e4fd9b1e337eadd879e6b5c296723e9b2ae245da326aec8c77c3820ff2484bf7e90eb11037e4f9f22a026270103
332	1	329	\\x014e405bc03f0055d66c01aabd8e39d5e69d323aeeb1b50a4b2e26f401ec6bbacc80e0c6249ecfb138ef40e0e2d46875d010e2a74bba1f8b989f6fb34c242a0c
333	1	130	\\xbadd14bb597e3d9e3aa4de9a29126f6593c9c0b0f8349958cb529e3a0686d7caf45c75beaf07be590c7edbf13709541f797cf3d58370321d27ef835238b39c05
334	1	305	\\x27e189dc1ee434fa83bd929e80b4af5cc08c332b5ad111d51f819aa7fa246a8db98e819c4af14a543ba8fc1bf6dba6d14f44897404be121f1e374ed7bb9e370f
335	1	392	\\x85a4ae924869a496e85a99e44f27a408780f2ba3a4a6f7f4f0ea9cde5788e9ac04b50484a6606176a40362e16920d1774a701af950071bd7bbe80f69b8c1cf0d
336	1	205	\\x2ddb3ec91f38ec08bb617eec74993e55d9bb03378a0537dbe0bbaa88c48287bec63114f9652ac849b9bfd88445d1216fa77e7af909cc04fc04b4a703014be908
337	1	389	\\x50d50c430eee17aca15c725735092d2bbb5cb20ed51143a24468eecc179e993cd771d31bcbd3e309e21a7780adc709312b1fa1eadbf0310672af57564ce82205
338	1	115	\\x7b55656f9dce9f0fe2364156fef246d6c26e62140fe831a819d4d01104256bbd9034369763f9358dcc0c36bc7d3ad8df0f18b1b85edb4e9be31f9bc311f95d0b
339	1	43	\\x216627a922b7c583dab1174e5160b89a6913ecf20f2434a42ae81bae7c8cc2af0df126d286a69c980aa8d31740823fe4b22a143452457d172d5152c0a750850a
340	1	58	\\x7a6bfac4eda738096edd7dfeba00b3878dd4516b20f19fff2f0b870e424119831be4ea517251c7dd4c845cd30ebdb23a3d131afebb4a45f0534d6bb8fc42e607
341	1	307	\\xc269fccea67a0d413626bdfc4325004f6180028a06186b93cfa6258d0aaad72a3dc368d1ce098ca5f7aa78e09d13791e35116f7545fd6e8f5f6463c6b2ff0907
342	1	394	\\x3b2f4c7aebd32bce4e1d6b9984e77cff34203a2f44fa79c9b65f23bc3580b5ecf8e0637f6553ef2b7db710a7f65accd1ca505ca5dbed8afdba955c5e1426b805
343	1	78	\\xf9893136ee9a3da8c234e0d8e17c1547e285dc064087980e0e4fa83bcb8d0f7115d65940d0bb345dd73efe500f4675e42e99dc62b085ae73054e143fea27990d
344	1	208	\\xf637f38975b3fd4e29749b5dd34265061d6e1ddfedb6c64c0ba68b1d4416c8f1a16304502f11831274f7809a0d6586a3ba44477e2c260fcbc94de305c4fe7206
345	1	359	\\x52c82bb99e63fcfd827bbc8a2a28337a3181476d6fd4b91ee4d707d306cc822766b0d0eb4af657052beb8a6dea549b81b6cd8aad380347cffd8f905985ac8b0a
346	1	282	\\xc149219b082115bcfb62708a5f58e928b144d0bce83668b6fe40944cdc738afb4bb00cd9229801c4484fe2a810a07ec2408a741d16e34b25b3728aad52bd4c06
347	1	338	\\x193f32bb367aa31261ada29f68688a2b2009266fbc2a65a058999174a512ccebe21e7e109da902c97fd04bd29fc6889ed328d43920d0cec51179bfbe462d610d
348	1	143	\\x55d372f8f111f6da209256e2129af7cf4259575bd5eef8e4e7e201c4f6c5bf2cad080f227e2180ac4599997a229f5fda0467f3730cd0418d3a30325b82d1520f
349	1	393	\\xdd3fc656005fdf7f4a913099354b3e830c15e991434ca9f4664243407a93f12702802aeb49ef4e686809d85850e09a718df45b6aa2e364cef0f1d190f78d390d
350	1	411	\\x8b18b97df7111e5e4dfc82727424f9b904ab4a3df45322ac43f10408f1cdbb93632efd3ca7dadf35a2573012adf59017649e9446ebebe6c5b28e15e859f3b003
351	1	391	\\x71c371192740ac12215294d8f44b49ba8a1dfebf3c60592aa53d586ab835ce0fd87a29fb22d2fd4e4271ea583403fb9e76f15928c822becf44630950eeba3808
352	1	225	\\x96e22a90c8f5ca6a42599d406871edbb85170412d7eb93534223157190f230f698a8005ee66625f2f47d8154516cc904975408f0cedd5586b5776994bd62e907
353	1	291	\\x2ee5632c3210df7921682e7823b12e0c5b3f55b6e8853ac6173577b65ceef4a0ab4f45ef2f657315798834e8447613968cad49793173179bbc678fa8c0733301
354	1	320	\\x82879b34b857f9f66d35534a582e7ae5f44d960b7479fc8708b8b8da60f3d87884e742dfe8d7d82527b9de36f5e58d3e19715f491b4ee9c2e0657d8a9137990b
355	1	7	\\x9a30147286286d7efe61fa14612997385788679fa9966b7eee2d58a9dc1418e1651feb810596c11dcfaa969f2c2d40d05c4d488e9086bf19c3ee92dc871ea80c
356	1	185	\\x74d0064e0997337f450b625f33ff56201adbc2c594afb6da675b4dfff8997486a3251dc8d35b32ce9dc9a119bd9048511954570fceed93d9af7b8af93a394802
357	1	330	\\xfcd850956a4061f56f266bd4a4940435f3cf85da2014cdd0881fd0a45888c5c1e58caa29ace6355e28adfbb0917847ee0e4e03cb866c84c93a56f2a888799901
358	1	122	\\x1cfb1ed43e967d14ae2ccb9d5c2ce410c264167e7ec97338cedb632379a358af8516dbaf6844e683dcfcaa1db2df0d12ac029bbe49304ec95e2405c9e0d11c0d
359	1	221	\\x9dbe0ae544706865f19922b2553a5d795011b9ffa9f7e2b2856c33fbf4d91a45f3bd1a9d524a9365fa191f43e5df04cdaa1df36e5a7a66620f4a46d02a34f00b
360	1	383	\\xc3c47663410f8cab2c96bb0da41502adaae64bee3684395e9459dd6ce70a862ae0be5121c63a4da31ad87287680695a0123a75eeeb9d1a2f590ef0b4e0b86b03
361	1	377	\\x680aa7912011df1b1ab2213fdec5a87705bc82e0ecd44def5b86d1d59fb6d7c20d184e91c4e9fbea25924a6ee2fb1ddcf3ba260f55600427a8aeb3daf5d96504
362	1	27	\\x17e6ce83cb5097c0e6bc267005602b200b55b7c71318d1e43958305e81b921169db78189b66f60e49ee548aa538185323ddb33c5b3c45cc113a4a9ae7706d30b
363	1	304	\\x60645c2ff29d6a55c4b98b795142e1050b7f55ca202a59234d4c4269084f41f3674edce84183f364b690f292f2a3d49f920872d9e499e8d00ffef8163bda000a
364	1	22	\\x0aaf918057dd1601aad782c075346a9366054b4ef05a7f7faa3bd52d2fdd48411b2b6432e9ffeb735ed58a762c698059433d455b037c7c132a5cb9814b75e904
365	1	11	\\x9fd0e932028069fa4fdaa042daceda2e9fb60d9610d1ee45013c9d43e79e5cb4140c8e5061ff7396bc88557bfb3c22716b22d83004e1d5080f04537a64307305
366	1	32	\\x0a4af9ac46e4526993698565025209a601285a49e8b9e93fdbb73aa35f6af675c4f5fdac146750005ed3e43f757de89f6e6bad2a1344d98bbf35a5a58821130f
367	1	374	\\x65ce8247ea1465e2443409907dc5df4664ea515afa82d9c59e7ebc2f89f9e4fb889d09cb8dca4cc0d3de04bf0c988788f5b838b3fd28fc7c552edea47db7a80c
368	1	381	\\x65d1889bafdce7501175d2700d7ca6c9987cffb80998fe64908f14d2364b417842b07650ba90caa11a623447cb0acd06c677db82d70a69ed264dc7ddd8370909
369	1	157	\\xf83492e3226921bfdcfeae65aa590329c7cef2234c94440577cd97e0cd5aa91bcd0237a2ef1e3410465123fb7c2c171eb506237e6ba1bbe4c88a7a68c763e60a
370	1	72	\\x4ea07320d1d5066b96a773d4675f0feb3e1780cbdc65565f33a98096886eaeb77aeb78d11513dd74e3ef6bdef6693f9207abe0fc748876b36ea9c72c0dcc1603
371	1	404	\\xfe3d2f5814a44c62483c1c01a09ff251dcfc6b862d66de9a4abf701a2c14d46f278c3509716bb7c8ba91a4437d87694bcedc9c9a2ffd78bc1f9a71030a424d0a
372	1	348	\\x4969be60e7d7524f3f215d3b5626dc03e623cf53953b0c14a1eef9cf85ca331f2a8ee59b1823aa1e8be41ab98e1a68e5bc379557ffd1c59c7e7ec3f7b21c3406
373	1	38	\\x8364aedf8af082ef58ac502d4bc9052b94c554c9bd940e885590c9d6a8a5bb52da2123d4fcd181010d08325059bceedb7c50a7129ee0c06ca2d3e4f37c7f3f06
374	1	209	\\xc56fbab5814e1464279ed87907ca925b30c3972f56b5e049975f4ac2bd84dc9ad1f2cdfd03a2e195e6f181820fab8118dd4634da0b6a55f3a89adc95b7f3cc0b
375	1	219	\\xef07ec00a509b39c046fe6a165a0f687d1d54ca11e45f3305b27d90a6fd92da447dd6728300b969ae80a6b557bff76018eba6bc10267f99271d537d7d5f9f500
376	1	20	\\x90845be9591de2501032dfc98e3c4869b4141a6284858ac2cf8918834abd44ce89718393bb0cbc36fbed16312a249d4c703e97dc187da415381b9b627f731407
377	1	90	\\xbb9bf414bceb8a95e771c593e4c0cec93f0b35969ac5369eb172ade71c8e20219833c960db9b722eedb8e74747730aa83c29d7e0631fccfaf96df2abf78ff00d
378	1	140	\\x7a879cdfb51ca58d35f8ec81eed68539bdcce23f762be528754cf18cb70c754f8c0c8fc03e590adc767b6b114553b88d7837f93da791de2f5fc1c5c0c6660d07
379	1	44	\\xaa8f298d75838ea9e1697d95fbcef6464b67c41a95d2eca8eb3de9c5541f44753f85736971acb29587165a3c013fb0c50b4351c6dee9799960ea4eb01e7d430a
380	1	250	\\x11f7ecfcbefbb0ba8f75b0b51bd6c30c54bbbaf10b7f13eb4694ded6645814efad5f6fdfa09536c81b3e0865f82e8b6d79aaab073400ff6ce5d3ad5b25fa4406
381	1	347	\\x4f0d44615c6585518e6851456ba2e94995faf168f774bcff689475d5c54ad890d81732fe6576f1bc4e58c74f185a39aa1b2deaaf7afc736c78bc200aac61410f
382	1	385	\\x5322bc85f99d6c8b26ff385a1568a913fa138f4e69858a264249c98a63c115247d3bd6cb4aa608fe5d3c8f3bc3d382547333dc4ef296c59b94be2c35d6f80601
383	1	241	\\xa9d149fe43d95bf537dc67900abb84795176ed6440b6e21476ec8f3af8e8d23ca6be4e4a3493c63b4be1d69da4573f23230fd01e3b00ead881dd1f44f285da04
384	1	414	\\xbb454acab0d6e07e2c639968b5b77dc5bbbc8d6c607a7ab47925f77f32cb81942f8a48c657b4a2f2337e84b1c2e3d107ab4d4811af8d35b161a3f85d0054780b
385	1	106	\\x3f978dcbedfd9f0c4017a617f5ba2ee6776347baf2b59627ddf501efbacff8287706d5da86e3c32580a2004a39dff898987aa78329eb068fa207c3fd74195b06
386	1	76	\\x6d53eaa7c03caf210d9d4c433ba1beac570ad3e2d60016485f405140dc86ca055ac93d43d4b90d6ccd4c1dbec61875d41bb01262ec49305c78ae14f226329100
387	1	309	\\x25939daaed4313a17a1bd017f48ecddb7a134266ee331bf0c2e84560c6a57590fdbb8a4b33de85ebb792d3c507cfe6b66e364b6f89c6aa7be5b46337198acb0c
388	1	420	\\xf90ecf8acd052f4ff19da004989bc9533f73f7f1037342e9c3871d6827cf5dde783c7e4359d6baed09a67999db7780ac74ab856d2f332315499a7b6f9909af0b
389	1	181	\\x403638353ae32ea0e6bc3e278f8289cfe1bee95add0a0e76b24ce035f7d578b69f691c490b2d6652be0f1e3aadc75a11db168d05a7190b6ec94333dafc344704
390	1	212	\\x89afb1e15a84ffeead8e62bad326e7e0de092f6863addd556328801ce130d2bed6efe3bb99591e4d9b8b417aa0a2861274a17893dbb311e6721e250fff99d40b
391	1	370	\\xc5fb63f3b08aebb1168ac4b4332242e6b89d6f798d0a9de5aa682cffeae0eb465711e2a920cd611255223908367daa231b4f453c271f1e3d9f897d8f1ad3890b
392	1	400	\\x6b1bf2ba703a158d957fafa75e2d2e029b9d491cd65db2b54ade5587757512abb7ad2abae8227b027cf176f53439e5b5f28e24d71228ec1503833b862dcef208
393	1	342	\\x63133f50ea01aea33cb0cc7eb4b66804e395e0ec22b67e0f636234b57454a4cb5e18195d26610bf9ae9e067450069f323c11b071a26d0f4ee80f49cd70ee8304
394	1	351	\\x7a9621df0be09d6bea2c164347a2105091de3f5f07d4ca4306073d65f9c9d59cc34a84b488492ba640eb710f9c16c54b0710406ec3eae9481b8113a62ed92505
395	1	92	\\x4a11b8853fdbe5c05dfabd881f70c22c30700d62e451bd3f96a367a571a800c614bc3522a81e9e3e933a8d6a69b10c0a795f173fc74d15ec805ba1135d0a0502
396	1	292	\\xb3a753388827687c33009cab22bb7b0abeda8e213c88580acb49c8eb0d57f9defcb3d81cadb1e6cde8c09d0fef3b4c42ceb35a2dca5a9b947fa58647c3a1220d
397	1	161	\\xee774866ff1a72906a81b4e3caaa79c38f70cab92b94e7a90af5da5cc0c49f75e749295c2766d79163608689eef6f829b441df145ed8674a4a1786b2b88a8d02
398	1	183	\\xb775d52b6475a0f570685363c299d0fca781ee5a6f2a263ffe411926ec4ac25be82fe3e82200296402d6593aa865f4bfe65d1b9a78782cf1db3687398e1b0802
399	1	257	\\xb5a37aa4d31df2ed95c809b0cb7b36b2a35de065853c321fd2be0cb5b3ee9a7a3cb904259e0d51ce870382368cc1c5ed234e4905c5af5e51569ee70f074b7b0a
400	1	141	\\x17acf2148c44a78404413631241e445e6418ceab8256e22437a48fbc8a97974b9069a564509b988e7a5560e608949e14b2c6daf5b3ccf7ef1572dae80218a206
401	1	84	\\x04017c9cff61b106284d24725c18fc4a4a2f2b3f96b7ffbf42b461ef7853f28b94f066cce5611bdcb482dd626cbeef4206b21d6b60076434db8c965bbe3f0d03
402	1	85	\\xbf7dc046df475e2f945404478dbc2acee36b4261a622fcd88fbce21761a839289c27347c161b2bbae698c5bd8ffc2bc5177bcb0f22e64e7b7d9aea467e5dc40e
403	1	180	\\xbb1887f5e6b2d9c22110e0ec22f82add94e5308126005c49c8c8aff505832f9e20053f7aa096d67c6b3a430ba77b70ee3bd12ed233df2e8ee3ae44f257c3fa02
404	1	126	\\xde72b43db6d3475d13d008ccd37f1db6f0ae8b0b774a3c47b65da22e63f1add16c31193546b9d8ddda0f8b87695aded1a4ec4c57166e98cd37135704f97e370b
405	1	339	\\xf542910eb33fb7601cc6f9d11cc5ce693b3d2f2b85d8b6a857adec37eb328304b2c2ab1b2825116e7f17318582e1f221937dd14fe4832c581293969b54bda305
406	1	401	\\x50989810666452466b7aa42d142e5c2cb8fb0ef5b87a975c9a5d074f2a9867001a9a71a1e1f1016676c145a9c0e42b800e5903a219e7164e35c942e98b54b803
407	1	124	\\x39c69a33a7e1c2e7a16abe49f48967c1724ccf4c303e393fcd2a2974822a9c7251ee161ab68faee7f1004f84bd8906abcc4d4bf6f592ead821541cf83e99750d
408	1	66	\\xc4a66691b890611f95df6d08d2502d1e694f0c9ca57776c023d1fa3af16aea6d7bd14282b39ed917f50b6482d8436fe1278a359f393c677cb3775afe4dbd3c05
409	1	376	\\xafe5aafeab998c768107c1e7c51d3c968037e0cb304e0375dc54733d7ee0298cf3ddfc65cdda1ce6f8d4f857a4bfb8bc8ad879504a1ba54a274fe5ac540c5b08
410	1	244	\\x8923bdecd2e2e8693efe30034d344f897fe9013f46eb1d1e456050937678f1cb04fb682cd0360b2ebcf5182f42057f37c423bdae9fbf4dabd34b0568cf18a80b
411	1	382	\\xe322e111832c2f3d2192e607b62dc6d0091605519bed0c207c94303e3a78c6d485fad10f841731789413b2a608bb73925c9558ab2bc25e4ee7f5a93038b11900
412	1	210	\\xc8e2765a204d379e056ab189a5947f3b8e6fac642bd4ef897a7e34b935d96b3d288f276b4321e5509be9dc3c1c12be88fcb96fc7015a596d48f9f0c27a11ee06
413	1	308	\\xb012d1bac642b25c7578732d7a571e607cd0bab7e71ddf6e13176733ab56542bf4a45b6f92d6f90c374c2aeda8b8e3e2fd157b4491fb60d38b8628b4e8f06d02
414	1	8	\\x93904404013f25dd6f1b0aa4b9968daf95f67238cf2678962c67a9a4852a81d1158fe8a3e5ebf142227ee77bad12544e6d4984f255a187fda6f345b9c674d003
415	1	346	\\xe0480e289d6598f944024b03504e53172c4f027f88dc9cc9b9689d5011a070bc13a1845b5bf7d17374427a9c3c463b3396cd9765be3c665e27d07aa9d8e4e90d
416	1	2	\\x8ada1038f0d0e599688055a9bb5d71d0b22b6d9e573c8ddf2f2309f2e3c17ef38aa13f9b12513983770f52904525f6f80d3af62f9b11eac0d2e12d44f3967300
417	1	275	\\x1e9fc939b60d6b83b773c444e97d381deff2af1971f10f615a3d275eea86f849bfe451446b73686acb97a1aa241ae90a0bec1ee99bef2d3b2a0d74a0b587aa0f
418	1	152	\\xf18569f97f370507ef6a59c1287f02971ddba531a64ba912d2621c4a5e8e263ef4539dad33968fab5343299e184e2a654972f5ed6b7d8f20b98516968ba6d608
419	1	75	\\x2f293675e44688f0fe753dd8e3938e26c96503f072d9e42485634d39e566e91c8db37b1d0642b9329442e53bea8a55315283d53937314c49a5cb00c6ddc4d809
420	1	118	\\x904ea32af7897a294f42fa165a1aaf6de2496cd9c434635a907920f67044254f93a8fd7abc97065bbe7381156003f38ce23fd6f00d96771e1a5cd8e394f60304
421	1	299	\\xe2be615a27ba28db4f3f8e9904ed1838b11ca310153fb82f3e84a810a0f2a8816c7787f7e9234bb812a6d74b58039e43822b1758c0e037e3ce8e4f6e0b318f07
422	1	380	\\xb1a511b5b906d1d3324a05c581f9d3a7e65abe3b0a221779dc7ba5f6d04894205ff08eb2713f67c44f8e577c2c17121ea56afc719147b165afeb7c2316780e04
423	1	109	\\x8d289f1c7a197e706e9878c02f0ecfc313bcdd7b03aaff6344ee6482ba3f7db6a4b3a9c22ad4091b47b377b89385ee7c64fd1f79be17c216c57d41ec5876820d
424	1	222	\\x5d390334afc6fe298ff89534e362ff88e8cecbc362669305196770d726f95b8dacda3c65506ca93876ed7aecb6cd6edc0f1e8f315c17389437d0fee4daf68008
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
\\x4d049dd5bcd99bfb41c56f63447c0a2058d61a5ad3852415816276131750b2b3	1651516390000000	1658773990000000	1661193190000000	\\x8e352f9e7b1dbda4e3dd96c940287f6fa15410430ff4fe0a3f1f4978c467f837	\\xbe18532731b429ee445c8b367e4d56ce354f1f06384fe30567806ab41b300889a5dccb672b47953482d4506e9fe954188db1f3591429ef8e6b51aeaf658ab30d
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x4d049dd5bcd99bfb41c56f63447c0a2058d61a5ad3852415816276131750b2b3	http://localhost:8081/
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
1	\\x37fee5c036fb332e17758fbcb953bfc3d67b47d732d1447cc4631f6db4341720	TESTKUDOS Auditor	http://localhost:8083/	t	1651516396000000
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
1	pbkdf2_sha256$260000$tmAQElYisF5E0ijCJmINqO$wvPhjFwky2USL4S2jr7Re5ZZu1B99ikFmMcbSRJKJjE=	\N	f	Bank				f	t	2022-05-02 20:33:10.893062+02
3	pbkdf2_sha256$260000$EOfF9qjOwaA98HPdDkZY6o$gv1q6HAs7BC1BASrIXW5pK6OzYTQWGM+FZqmLetqZ2M=	\N	f	blog				f	t	2022-05-02 20:33:11.081951+02
4	pbkdf2_sha256$260000$Xfu2ZitqJbSvOX3wkb6ulj$9zYhKpWO7yzpKLiz1cYSuGcvvwrH8KKd8/+MBvu6tLk=	\N	f	Tor				f	t	2022-05-02 20:33:11.175804+02
5	pbkdf2_sha256$260000$97ZZAEUxi49jHPANbyDJ1r$5llbYb0LfOKS+M3XjN4AkscAALGTqxMt1wmiyFVMvTA=	\N	f	GNUnet				f	t	2022-05-02 20:33:11.272562+02
6	pbkdf2_sha256$260000$I1w8Ty0XVi80DOBUXDBwZg$1LsY2x+omJSnXDzx7jU9U/9oRGkIJMjMHBn9GG9jyqM=	\N	f	Taler				f	t	2022-05-02 20:33:11.369859+02
7	pbkdf2_sha256$260000$o3mijM4nCuPxHlm6Fg5qKm$zjFCbw7S3NlHPAwZb4CSmsBZNELGG6/JP4PzlYGYzXI=	\N	f	FSF				f	t	2022-05-02 20:33:11.465711+02
8	pbkdf2_sha256$260000$ytl8iFzcwozShli24pMjaG$cOnkgup2zoWCyGvmhnCOjbb3ubunL1IHLjAXIqxrW/4=	\N	f	Tutorial				f	t	2022-05-02 20:33:11.562902+02
9	pbkdf2_sha256$260000$BLJcw4bDrLy2kglZUo2WVn$KSJUk92ScPti0X0tJSB2taQVPXveASN5TcdtahgPDds=	\N	f	Survey				f	t	2022-05-02 20:33:11.658226+02
10	pbkdf2_sha256$260000$shkywwwTBeVhvuOGe8Kl8h$IGVo6J6zra0Zmw8LQS6L/4DFWFHalo8ftpKDgdPfyUU=	\N	f	42				f	t	2022-05-02 20:33:12.107885+02
11	pbkdf2_sha256$260000$jCjSykTeQFPz0vKIbxc4xB$nZICGJ5llfGI0pJQudv0Lv0cIczgJUGcUb7P0tM3GB4=	\N	f	43				f	t	2022-05-02 20:33:12.566959+02
2	pbkdf2_sha256$260000$K3jdHDdJ27Xl8BqdhlJgsu$SHIhv+piYkN4N3aT9+mT/2BMZSJSBGBGopvdgef8lG8=	\N	f	Exchange				f	t	2022-05-02 20:33:10.987938+02
12	pbkdf2_sha256$260000$qouz7nIUDG1e6HlmFn0kNf$+ngIn2KffZdxitSz1qpWGWVZpP11lGkCGWussS4opiw=	\N	f	testuser-zzeu1aog				f	t	2022-05-02 20:33:19.585113+02
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
1	152	\\x024ff7b493a5e689a0d6c9b533859b3e7dbedb2a7bcab1c6569af4e19754f24b4d5c198501d4c34354485051ec5161247991da6bf06b729e1b7379e86e0d3b0e
2	244	\\x41ecbc6621bc2ab3bdb1a15174766f277534395cc8384c833e8a96a72ad83ebac9c9a6974dbf179e6818cf0e782220ab6b70f7491087194e14ee9e14b76a0207
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denominations_serial, denom_pub_hash, denom_type, age_mask, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
1	\\x01f4b242f370231dcd9dc623b24b48b4e3034fac937e4d4f625102d1ca0264999bf3360d79a44c165f8d4bd1c82ec55f56d575ef6678cd82295f1c26d5d7b174	1	0	\\x000000010000000000800003f38cd6a481acef416652df92fa2181c4c0a6b4021d8b1d97b8a91e779d1911b0e253598acd724219238ec81428f0079c6fe082b12b07806fcd65b04691503dcca48a1714668003eb12e636cf63710ab41e86edd4b48f9a9f1c6166093d240c6b1c85751d1d0fa10e2341d750d508f0812317dfd4badcd89bbec5224c3d6c987f010001	\\x69a85bfbee734b5c4785ba2ae16fe69358e82f2a4482061d7a0ddbb6070467e927e331a6afd7169200c55068bf0039753a634ad87835fd972b692885815a0b08	1679323390000000	1679928190000000	1743000190000000	1837608190000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
2	\\x03f89f021f1acbc2ad83de9c15b4af71b56bcdfc619c35ad345d1cb4dc6c16b01c3c1cc02d5dce8d30b5e246bb1f21dc08050c543b87a8613e82ef89c31102f3	1	0	\\x000000010000000000800003cb18d3ce9633ce13eda8a31d84723effaa280af91916994ca1d8b97be3efaa106c0e67a60ce5210ac46ebea9fe2bd83e89c7e6024a022ba6955d8fc89af23033c9292975105050ae5c3ec2f53e473b0a1f89d302b4c084cc729eb2af9224e33df4dcab6677a8a54fa0d97a73c641dc850314890a1a91b07f582f06d5a3bc27a9010001	\\xb605c4850f1de015224b1b2773e0a56675d7dc86050d1c6b89de6b9e3dca7016ce12a1914e70f28224ea0ad284b428e18816f23c33209d86c3b2ef580e2d5808	1652120890000000	1652725690000000	1715797690000000	1810405690000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
3	\\x05acffb9d096153a6ac49c946bac3d0d2ae6fbb695bdda640b8cc3188afd574e2bd5b63be9436fcd8f4400561b41bab632631f35f4f7013107513e3e48eb0f0e	1	0	\\x000000010000000000800003ca086eeaf7c9c6a4094b81bfb4089823133106446fe162a899a14a1eb685dbdb4098add717c2353756d68a0d659441b5e323e1f4ccd6a388afacc8f9d4fcdef87b5481b7f7c33f429418f93e065211b8415c86a520f30cc865af6b7ead471c63d3f8744e0cf73d51ec28328f52ce10e63679871ee1559e96f83acb49ec804b87010001	\\x77a9ca83d59f8afdd3c3e4670b663cd0e02ce15c1cf4dbaa726f4261dd3122295aa0bd6187345a9d0b1934036c8d28d9d1fa2512009e673be68f5530b342f700	1667837890000000	1668442690000000	1731514690000000	1826122690000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
4	\\x088c69485661c08facd25eb9ef828c0a4a26cd9c39038412f3dc7776643de473b790d9c357a4ab0271c2ce624e8c5203214bb4ad4410374c5efd239a249aa6a7	1	0	\\x000000010000000000800003b70c4e5b490edec20a66322bfe3bccc916e4abe9609d002bb65e99d85697132741ee4383d5b09bc40a83f3647996d833b82291f049d31774065e40fdaca18ffa78066ecd9911623874592d77b5c9f4427be5c81ebeb8b13dd120b79cff8ce7269a154f8dfc23b1938bfb5fca2aa8d570add625f20fe74245bd59c987e89bdb65010001	\\x2dc4e22315126b688450112be911df3c7e62ca789362542b77030057e7a46fe12f681244f686ab7e34c81cb5428d850ad4adfdb827c46180ef5f6a560f6a7608	1671464890000000	1672069690000000	1735141690000000	1829749690000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
5	\\x0a98d5bd1f6d12d85212b5d25121150cfc3947e31edd8c38d53f902f90c39f91916f141d0b3706c5628a6ee6fda857b19c35e132c49ac81616497e6a58ffdad9	1	0	\\x000000010000000000800003a0be5ebcd66737602dd3bdd5f15a8e7389707a5220bd767aa2d96675523812bf88206caaa15a7655ec50643e8a4143a6029e94341c18dfe0697a8af67c295c9c56b0e887ca7304761b9c2e1881129e7853cc5049dd8478e07ceaf2dd3dea5f53a8a1b24445c1c57283e7f0833776d0b5a8ca2d26357ff481ff2046594142cec1010001	\\xf4ac2ed60232189d760b56d38ca6e9c7e6accfe3a7d2ecd0083984bae91573a02c0c4fd5f559d3d411bdf4ff87baea5dccfc2c8cce29e1dc209d3a9ad5b3160d	1672069390000000	1672674190000000	1735746190000000	1830354190000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
6	\\x0e54f55c6151fbb6c4c3d28c5902cade79f153285210fc8ba4db30f42ad8372c20fbed16de969bf02c97d81b74c9b4974fc326e9c715c8601271301759dcad40	1	0	\\x000000010000000000800003b82e4630bd8a148aaacaf3c980d92b88ce3bb8635a715c21d7d6cb3e6dadbfc10cc5f21aacdf0743583d5197cfe832ba2520281f2b178b6ec312083fb872a2242c28e8667104423fff5368f6778f88d24d98fc002334b02dbc7f659f1204e2763dc4cff79651164179325d315647a219de515114aa593a2bb4b15321ccb062ed010001	\\x61d1a02b0de0cbcaebba326cd7a8231a894ac4a8490fee7bf18eb7d3bdc9a7b39f2f29896401fc231a39096bb3fc946a60d12f25f20716e06e901057418d0b0c	1668442390000000	1669047190000000	1732119190000000	1826727190000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
7	\\x10248537ad4ae72cbcd004a510b87f90ba49fc976bb13a62b1b35e9518ecb6b44e42a3a45155dd209f389601768acae777441f67bd69a84ea6751fe948333ca8	1	0	\\x000000010000000000800003caf5e0e7ae348950334d70035beb5ed125e4a8679e58bee63a5a3a92bede22027954c31873e45ff7fc4968928f2281dd4081902f94bb1cc88cdf096f4091273bd6d8d88901be7c6be5a4ae0bcd8f07dc55e07e887fef7353a15261bd722688b727dd91b5367232b7772e6e6e86fdc1b8c52a7c37370a6c022c1baccc913569cf010001	\\x8ad470326c352210a8900498cd1cd9b570034c4b41dd9d597e104c8129e6ce56c0c86c1b0f41e1bffacc52bee86380e3d83ab46a3123ac37c40eec529b3c5a01	1656352390000000	1656957190000000	1720029190000000	1814637190000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
8	\\x1448f784b97c06c68d6f8a85704826724c1bea3107bbd3dd934e680e6c6b248a3661e4927b75f003b3979a47325dc08caae001be81cad50b3d834aa31f6ca442	1	0	\\x000000010000000000800003bc75366a44685a583b82ef28d8c24f5f0efa845fb8fa1a317b1091dd05a6e3ea8f36fc4591af3b968464f73bc951532f02b58fad4691ee3867357bb7813bf328fa16f8c640a19beb6a6eb9399de79212eacca72fcc15715048304ed22f23781e9b5aa2389ebfceffda793810589fe47c1cbb3226bc420287f6a65cdf697b2eaf010001	\\xc1f7013e1d6cf6a4937c1ac4175fac32196b22db1f76dac45ed434d81e0b85c90bdfb655ba9d0585d09dc6f3e4d7b09f0f13b1ee77b3c5956e8b2f9c5f33d00d	1652120890000000	1652725690000000	1715797690000000	1810405690000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
9	\\x1524c0578ce8601ab790219949557153875f23af183634258e4af801a1a25da97ab5aae54119976decd396193d8f8d2f88df71a35d193cabe088d668694a2552	1	0	\\x000000010000000000800003b4dc113e403fefbeca1b2642f860bed0fa8ffcd7e361b1871d47567652195c45dbe640da8f696d0a94b968bfd3c4d4514be0083b6db628d91ae46e9a9938f05f74cdc986b39bb438633d6dad3a5d3b122681461d3c5e42330d747d9e63bab4a62395f5e52a9bc0ce45a21f974758daf0d905ba124a247188edffb973355d96d7010001	\\xf9261edb9972f45ff9e3a776b9416db2bd79da898b512af0ec12960edcc152ad28b50cb65ba95c86a936bc3382a1da81bf6d2bff6fcd1cc41145c99c55bf0701	1658770390000000	1659375190000000	1722447190000000	1817055190000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
10	\\x169c5f4e17f3a111cba3759f4a7154c7a204105c9bf50fe53e3e98ea9271cceba3ed62df84c39fdf95b956844d9422c8939c771763ec3f9d01661fc2e9f89724	1	0	\\x000000010000000000800003c1fd0055e229ca3469ae822931567cbab5d74902839d09e71e36c59a49fb5d0f49c29373364da294d7007ddb7556cb71601239497ad7f8ded5d83a65ac1b8272e74e2fa561f920a5cdfaa3553a51a23bc6e2298b6b9253b831323af613ee685567125ad6785b8777734eac4298ca8b66980abe815a0b214f1475b7915f8c8d0f010001	\\xea16eb4b055228256850d55f24f6c5d12213f005f6647cbe50767f3cc27bc4f816b8c7e8d54b8d80dd67aaa2219c7af458ad8c9ddf450f75dc940fd1403e630e	1678718890000000	1679323690000000	1742395690000000	1837003690000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
11	\\x19ac85e705067701dab9a2a938ed65961113341437884a9bf418cfcadddde8efe93bf4aa32c33ad43d5773155f96e2ca708f6cb7dfe82160dd5e519b65f99ed6	1	0	\\x000000010000000000800003d958351c3f1ac89e21334f32059c795a9870efb71bcbf1cf8cc656f16f0a3f6f159653da9b7ad5ec825f7eccca56c32a7783d0ed560577dcf23266599b5bf558605c9d9ac50ae87c95d01a767cd55015e857ac87bc7b88f8db4e86412eeee9f8355ca1ea8daada2024aa2ef21cc7d221670244e66cef71f6b0d446e0ed963e79010001	\\xa3a6c42b678a57f5a3420ed1c1c42882d815c035097716493b3ccad73319ded200af5123c322d335ebc717b8d12e9fc0b7d2f7382534b20d5831a1418bae6b00	1655747890000000	1656352690000000	1719424690000000	1814032690000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
12	\\x1ca037ad1b175a0492e272e299553751955cb13a46e76dfa8b20bdc49f8df930dce72656301b38e21fc86354e1026ab4af5e40d4c291a19b6219b083486149e7	1	0	\\x000000010000000000800003df3eb50e23533f0bfdea20775576332ff391c99ce4d4f8b05809a959d71fb8872e3828d1b0a558e2b2920d5801f63c0284e06411e27f4d02c0a80fd76c73e05e091c70c62842bbb1d4a5f82b91f7a14c3a1245e0dde466d6ca3c93b92bee72822f5f218072f17c78ccc18ea9c05e67b0643c0570f5575274643c182ec12a7af5010001	\\x396938f8624bc9871d382bbfc288ab2de622a72f00065b21eb8eabb82da3abbd2dfc83423fecc0fa9e6422c16fbd02a47f3459a0ff9a4feec0610f618bfd9009	1669651390000000	1670256190000000	1733328190000000	1827936190000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
13	\\x2174bd6a177303e111d35202c39a54f3c1f7f3903c013bc226beb8eb432a5efa133761b175fae61e3598c17410e8db4b5257ab5168c65abccd1829d638a5fe0a	1	0	\\x000000010000000000800003ba6621b114da75843fe6419d8e077a556f5e15ac3cfae5ace64a2af53b5a17a881cc47fe6f3f234cc2156a94d3914e6dc53922ea403aee1e5077698789910da58ac4cebb5f3b99cd522d16502e5fc0591806ea52d414c769339f7e44a6311c2a22347ddae222538f6193ff5418280520b82918d339aefcaa46e7b6af37167caf010001	\\xbac6026e2613eba482082ca15a44be79e17059a7c80928560b5caf3fab9533e614cb6f1391fcfb77be35bb865b17a3fe8c4231a5113a4a84cae634c74b0bb90a	1663001890000000	1663606690000000	1726678690000000	1821286690000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
14	\\x2118914df520c7e20bf0cad1e5ba04efe6448252e5f113c9fea18575b88dad7a205493f19501fc937c20d79bd27957c3443c295e9a2cc85f3dd04cabd3213502	1	0	\\x000000010000000000800003dba3c511b65f4155d9ec93bd2c668b189d53b22480404e7224c53b12b8cd93b31fabdf634803837ed0051170d43e00f7ef7e215c42344331a86c0077835dd154f35b9a197631416394d83c3d8f31dbc546cb81360950b13992529d2dac6398896d9fe93b3ca8911b2a193f524f22f54bf8cd8e4666619264fcf7bf475fade51f010001	\\xa3da375d44cbf6fdc869c6d343433d32446cab43b73b2ea0fcde5a855008e3761b93a4b1520072288ee53d51f8e87303e60e6639444be62f93dbfb18c34f8f05	1661188390000000	1661793190000000	1724865190000000	1819473190000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
15	\\x26d84e909f588c0b7b099759e4d0cd33f6f1f2b825e3fa1f2a78a6593f39f3ec727c09aaf62a44ea5878206e12457f63531f07ecaab6fe58b22da1c0c1722bb9	1	0	\\x000000010000000000800003c195e19e945374ea71a24f7868143161fc4a40e863f0b9faab1d92ae518a7eff85b6b7b021fc8c1a2635569cbe4fff406f589965576bfd72fafee93fdce78ec87ce74f49fe74543b8e42c1e4a267dc18cd6b8e1460104b1998d4097f43cdeb6aafd6f1ca6ec6e4626722f418bc8f43b4d7692a90c99bbddbff1171a8ec19a49b010001	\\x85f267945613a2bea5e529398695868ede3665a026bf0f195f302915c142c096d2f3a31ddae3071df277a673c396e43250c696d250cff7ac7d0d684a9cbd020a	1672069390000000	1672674190000000	1735746190000000	1830354190000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
16	\\x2fb064fd3d74febf81e9f4f90bbcd762ae152911fcf7605019e4239a2bfe23fffc2abb9b262ef32cb4db9a34d635b3824a84bd65e5dd52d8eda6acc2db9244cf	1	0	\\x000000010000000000800003cd7fe6de42efc5cef3a1670206fa9af89da9eacab2a59ca4b4ea49d95e3dc34bdd349be0c104f4bd67a2939129d89dfe13dc313cac62992ff9a7be4d9076385f467cf468b5efd68e238614e89ad8baf6734040f3b12600a3e0ef5977fe27e47f9b323bd089283ccd02c4e01c9f3ee79c55f3ee8912e70cdf5bc6898b90c138f3010001	\\x80c9f68b43ddd25fd5fc3a9f7f80a2705db8838a03ea961d3bba4a45327e74541227c0e421ea601eef28af368c0a42673462a172029ce0f889d35ab0b5afaa05	1668442390000000	1669047190000000	1732119190000000	1826727190000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
17	\\x31fc95dee14d22c79cd35130e32e06230b8098c069054840cea4b98b8f6757cbbea1741a738d8db2c1bc792be0243f766cf8161432c973a1f45681354fe62fdf	1	0	\\x000000010000000000800003bd69b15fed77f16bc21cb4996c19ccd9d93693f6876b7d69f51d89c4f525a4fcb693fa2df4c9e625d2148490f5754670f54e47436d9dd6a9e672e5431b08b3302baee938a3b7a569a00809443b96880a8ffa1cfe0e755d1553e0e9359a7d27d58d57246284804cab9dd849e85792ff1b69d9c436cd60e8f6ec358ce98c2c406d010001	\\x527201eb76729daa276610c23490bfd62ff8535b020d112ad456cd6840c1aa1da967a12f3480dbcc5eb0770a1d6ce5e70e52e6fb995d0a3a0a94b4d4f7d0890a	1682345890000000	1682950690000000	1746022690000000	1840630690000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
18	\\x34fc34fac359c7f592846a290f43ad58a0e31ed8f801004411d4b403a0c777473573d1d96848e44c9bfa0f0e13b5443ac49489efa83e5df73412f854e412faae	1	0	\\x000000010000000000800003b17560dc67140beb2a07aefc148bea5bc141073573d28c1a8f288e38f875fce0afcb0409b076e3825b60449bd6e8756802b2face652ca18fef75647f1ddba2cbfe9cfa73f2e56118ebd3f92221c96ee6763c6fd1076e3f780b5234caac0e2ba2783322e97096f9e388723e677ad4f18e02a5ccd752d1762a64dd745a7b294745010001	\\x755739edf6a8d362adc71ec88b0e6b7bc62c0d46c884821968b0de1616d9a13e406ed267e252d71f46fa41ca19c3994dd7d3708279e71b764cee009e01dc1c07	1676300890000000	1676905690000000	1739977690000000	1834585690000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
19	\\x36c0ccd1f09e895096a015013ca80cfeaec7603474caa4ac21a2cfcf2646ae5ebed170617d446abebc0e66fbfe59ceebe57f1197950735803dd962070742a27f	1	0	\\x000000010000000000800003cc62b5f71366af41ff75e3a049e9d1c4f37e2d1f20ff709681133d704afaf58c9b6a7c02b0190cd5dffe450ad26bd814f42d046eec5ee8f826a931204a81fe86fd3ad22c4e063555c67caf16b2536a08a102c17e3e160aeb3748bb4b0bb57ae467c4065b70e2a37fff0c596a9110b91459e23d25ad69f6540784c1334dd78017010001	\\x104e06f058490a68116b7399683254d3556492b98044fbcbfc09eed07b453c30eb04d2a807fc2560272c58b29b18731d92fb3d4ae6b6dd3a91ddc395cdc77703	1679927890000000	1680532690000000	1743604690000000	1838212690000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
20	\\x371c6a724a21464388cabf26ebd78af850e814827bd0561a6bd853353c01f3ed5c6d539e9c3158ec72e248ffcc6629887c3d27b3be2198cbf0a2cca58e136daa	1	0	\\x000000010000000000800003ac679ce27972b0d9248a87ed89dcb4bb2d545d166c36536eedfffface5e7d23006943e35a3fca7cbabb7474def04ffac2ae1e40540fc02dc6a2f1637c56c1e3d97a64868f7596a5c8edb5c7ec493ed23c1343f0e115cf5b4610e9e5eae0f8d6ee9644c452e23fc915b798028f179fc46ce06883487e02f0d50e2be7969e544c5010001	\\x85668a1b7f83a20fb6e086daf7a8092a9a8adcbe4a9618003c93105cc83bc00e899d0165310c82cf53e1bccce0e49a121feeaa90f856d33f3f0539b1668e300b	1655143390000000	1655748190000000	1718820190000000	1813428190000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
21	\\x39002ec78f5bee8e77b20776252c984b0521b0db3950fd33359d14742c7db92891b9fe7d9d81be7afa60d52add1f509b6ef9681d17aeb13b5fb1275828d26f7c	1	0	\\x000000010000000000800003cdc98ec90633ed875d4ccc5f444588970bc17cca75d58f5d3ff4afedc3e5f05969ea625858389e46ca3a43491032f3a16c01ef95589275e2a5fc7ef07583b060110e1b1c093bb5f9f467af909257b99a3e5120e71e68610862103fd46ac562b826f939bbb5457dfead3704649b99f673cf740c04d216803591b4e9242cfcce3b010001	\\x194f9542894323eb64d159df564782b6a79455b63bafe935746e149be8682f19f242272141dc41e34c0a0b40ac5fa033ed34caa636c97d67ac972c30fe637302	1659979390000000	1660584190000000	1723656190000000	1818264190000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
22	\\x3988644a4cc6e3ce4cd28224eb334aa3025328add9c629c1306ccc413b6a8f6712a8a78af8ca9c4d9bb1e1860c7d0064f75c09a6535fd20bdc372c8eee0563de	1	0	\\x000000010000000000800003c8aa86e8470e376645165b4aff0a8d8a0c30a2f70296bf07fbe3a158921e8d0ce854a87ff5e80236afe3e237c28a709278cd097382465247925eb5c42ea018c57cf5c67c82b24dd454fb10eeff1a48a5a0ca9a19492eabcb20edf070aee47d0a5e16a3e096207613ba1d37f7b7fb12a0b8191d8349527d3287cf7af596a52c89010001	\\x7d77e3dca57630701c909c069ed574dd36b835a42895e7cb4ec508895911280da93f89b447951ad271bac8866794f3431ec8962dc1e6095df454d15e7d5d4402	1655747890000000	1656352690000000	1719424690000000	1814032690000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
23	\\x3e00d70cf7daa441f5f2c7112f456bfe9b060710c7845f728f3f7b0f4ca1fa06939d43e4aaa67fe762e9fac6e1bb16b8244b36d7b9791b4940105c3520be44f8	1	0	\\x000000010000000000800003b73dd1852b2811ea5913f0cd7e20e570e34ed4c96f01e0e823d7a18d4370a86c5f9e4adb8fffc40625ccf918c1263a1c23dacee7758d4a4c253698d1bd763ae1d7816da95b1bf42a39d1828c7c295842587b46dfd0ef6129d075b3c8a59e0d9d0747c2d34cf2ed5cc1e2de81b71cd7c4acb13e8cf55da6a33e7269550e30ff9f010001	\\x7a78f246d1badc3e7a73ff30e72b944f99066473188862edea0fb8e2728e5622e14122fd5417389925a60e7ad53032a6f2300ac7a9eecb82056ad82c955b2a01	1660583890000000	1661188690000000	1724260690000000	1818868690000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
24	\\x4184d52bdbf2bcd9a6e2c4e45ad293216251094f438519666e2051b597811a7e271c900b0dafb06e162157a3e2a19fd55ff21b8a14591d0f071f3236b9aa1d2b	1	0	\\x000000010000000000800003d788fd2bd4b78edcea12660843ecc4d42bad9fceaae9e6c26eaea4bc98573e6c204018440cbab650b88306acb697c39e262cca5461c838473822c5fde55db8d9e6627171941f568916e256096593016ac1078b4a4d5a53008b4950ea3c15722fdd5b7e2f3a9f05de51524123bc63c4dd29c210b9c55c887aa3a26f4015c68989010001	\\x07e8264987812abc238eacd911c396c5dd70da751cc65605a2389d58b0cb7c8a2da45f919b93a051b5faf3bcd5e5a5d866b797f05ed9f74b2ca9d5db59d5320b	1682345890000000	1682950690000000	1746022690000000	1840630690000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
25	\\x47c431d372c2d88ac563fa5545268776f37c580c9a4d2b034a29de51c528a378f9c7abb6e1dea13e001c555d18961a26ca041810e9edf4e4a5f042addeaea073	1	0	\\x000000010000000000800003e1f7e9609d1f92d9e98d383611a7c272beecafd7a68b81345d368f4b54faff17039469692c0692d037016c676f137267067e4fa50104b5251c737df49a287b71ec427e979244f5e970eaaaba5a758f82b3276fd262068ec33a1ec202eb54a7e0bf49cbc1d2615e49aa5511458d0da9ca71949cd76f9510cd49ad77ed68a6fc85010001	\\x7b1193e2e0762264e0d8a5cff148980de60d85eb8282e2b2493e53ca36b81d02a0d11c62b4d4c9ad604d17a9a8f43be3d2b74a172baf9bddefbbd959f5b88501	1678114390000000	1678719190000000	1741791190000000	1836399190000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
26	\\x47d4d187ef60ccbb0f8161fa7309d0bdd78c0fade6ede99d212cf986ff0d363c54fe3772dbdbfac9f42bc1dd5393a61af6916772a59d12363b1d06673173cf49	1	0	\\x000000010000000000800003eb5678ebf91259a1dce43b9d96bab6b1592e61893c4b593d7a0e4d3c325084615295f93748888dc27ad5670b8287ee9b4237e42b2071efb78da94452b81f2825c02409e696ecbc9df2f87ed9d6255b784003b977aaef5853937d8efc1d3efa51dbcbf6c34927d2a1bc80f19f3a4ba28be73bc1d3c9c4ea04075935c7eb0a10f3010001	\\x51df572380c93352d6610e799cb20892a4ef1eac787642db5a3b9eb84189daccbf105ac8059a2965634142cb4f37800d31db288523d3eb5821c272c64207e60d	1679323390000000	1679928190000000	1743000190000000	1837608190000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
27	\\x4da0b08672fb7d0b880f50f4ebfaa3a01efea3efc706f460499d78f56553f5e2ebb798fb1c9675406b3e554f63e14e335e953d264a302e4a429149d615f4a7e4	1	0	\\x000000010000000000800003c9ed65ed531b29d9e3c006bfe96400fff24b91efd6271822f49e859bdba3f0a6a8e26d70b3d8b3348a2d3f02c4009f6f85254c0e45d74496a582a2ac61f178dbf7c906bfbed241d4d521525716437c54977df8c8e0e5d6047fd3bff46e4bc05fed8cb8c5b948ea1e9375c9693b26c9d3fbcd4f8fdee805c82e975771ad0733c9010001	\\x368740e6c2098a992f6af9596ad1c0bc3bb15ff7dc6d4a8280e2d75e767df96c1f21a6eebcfdd617b36b8e56538caddbf219b1872d5758f7c363fa619ad79000	1655747890000000	1656352690000000	1719424690000000	1814032690000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
28	\\x4f48eb3ad7ddabdc6cdc31501bda0fee8f88849ca4a95b0eb91126206dcde9641ab9d49521fa4bcca2c5981974cbf71d1d63a266d2d0877724c4d61e1ef600ae	1	0	\\x000000010000000000800003cd0cbe3fcfaa9d71f6b8263f1fd15fb1c394c0667540e63fc584e51b5bdcad682e8cc18ea8476e39b37881e971c1388d9556131767f122912ba48629cc6b260cafde79d620fc64923a9b62d8c5e6325db5f6051a0f0012d6c8b26e73ef042812d9e85bb765470c7761c2d1a7dbd1a9adb3c9e6531deaf7079f893ca650ce1157010001	\\x76ed69584aaaa4204681de5df9ebc9557e5adad4c41768ca16ff0a25b914eb77f23ca759b4dea504bb6324776adc8155cac2331d7f1184b8c268f3c3c255e20f	1667837890000000	1668442690000000	1731514690000000	1826122690000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
29	\\x51306784c550289d0f2e09e7ab77d959ff8855a9afd1fec9e54b421fcb59d1ba1944037cb9e431c549404fad10c0eda0fac15a3265dbf82960e10be900053dc7	1	0	\\x000000010000000000800003afe4f14ad02f24d1840960338b3f3ae7ebfdb37373a79e7517f9534bc8a8e2cee61a088605bbb1184b1b08ce457fa136a84884551e53e9e90c2aead4a1d9a985c16fad3e821b758ec04982464cd5e7a80bdcc73121cb74889823b647bc6dcf4ff275e9b0307e1c07e809f29192d803a55de3a88edc8f3209d150c305ebea5799010001	\\x94d057513593aa8a3347938d902736938a558c7f95abb21bdf778fd14fac4a1f7ce830db3e569a36f6aebf874fab7d887cfce3f5ce2bcdf8d1d6a76b413c3903	1675696390000000	1676301190000000	1739373190000000	1833981190000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
30	\\x522c849230386f1715dedd141a682190332783cb73d5b40e4dc228694485b74d2c4cdc351f0647310ead171a62b55ae7ab0fe67d2ca888184418e9318beac8fc	1	0	\\x000000010000000000800003e77274d1836fac8fc8ca5e2a7ffc5d18370ad43973761106bad2dd777cd40b332405465db2e925d56bc90de1ac2a332c11335512a123cd69be6ca96135e03db5f40ea0247a7f22d0d4c127d5e04d475520f97e216f13c5f01f78103bf6763b48198f21b397221adb8d8ceca149e56c9df063bf84e0a2fc26f164ef645735e807010001	\\xbd7ba5ab0c7a7f0835ff1f98673a6048453a96f5934ecb0bbf6921fdb63b38a3e3f4d83a2b358e1918d0aa0578fffd2e76580426d09640dae20d1acae8614a02	1672673890000000	1673278690000000	1736350690000000	1830958690000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
31	\\x52ac9db1803029346232e2bf4fe31dcefbb01d48caf005bc2f48890e220d71993e0b16c410153dec6c6cf53b72b2852d0fc9bd8e303fcfbe30faf87a8af8975d	1	0	\\x000000010000000000800003cd87cbd38d8a2075f3cade845e64a340ab501f880ce6f6a042f4a2f0f19dee07915e74a384fdfef71a2df0138f45fd11e28a3897d78a8ff6a0666a2d0e0770e265d30743fffa5a71114e8d1f5c7381894075fb0d7aa27f3e35c2c4d6d473689be1e096d7723c7493580a5db78c53f25cb901d955c4be9d6fac7325b61ba2ad57010001	\\x2acca4df601365ac3b43fb9e03ba491cb434a4b086761763bcd8f12da218f97b57d46403d9e77e8ea0d6a007225815fd8d4cb6fee6ef052f2b99e1f968e7820c	1666024390000000	1666629190000000	1729701190000000	1824309190000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
32	\\x55d85c47c17d8a6e910dbb2f794e49a5c71f52ec7153706b908632104ae932a99f77fa46bdc9ca965525063b2870daa0d3e8909bda8f1b80930c925fca6d9c31	1	0	\\x000000010000000000800003aa65200c0faaf982a92b95c3cc8cd46ad6f6dcc58bc965f21427f6fed350a04a1438aee493d9eba4719ae36fee92676041b8f946eaf3b40270512e328e32ac0d854eba3e93ec5a9b2de09a75b0288d79eaf72d45855336a53637755a38862193b60954c3b5f7e1c1a3e0a8d3e7ca5a1e69fab24b9479d9632995f03ca977cf23010001	\\x92a0c3cfe45428040441b51bb0d61dc037905bf50a51633028e0c6a91099bc016aea27dbfefafa2a26a6f3059b85817b034f0fced70e191022a2feca7849ff09	1655747890000000	1656352690000000	1719424690000000	1814032690000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
33	\\x56e059429d696ac9a2649a5ed8346f601e2b8b814fb02e65fb7f11641e86496eef62a80fae0e0eb46b0b78bccd7ea84e75c343c66fd7b6aa646c1dce961afa5a	1	0	\\x000000010000000000800003ada824aeaacd22acf2768679c4ff0640296eeb5b0ea8e0667da3be017f9cdafaeff527a81d8bfad279200153b6b58c592a8343b5f74960d1e67ddb8786460938df12959ba462bf6e484f1fc64677e32cda1a94d870bd20b8c09d3e5ceb8c058cbd8ddba65d4703be860acd0fc97b801ed797f62ff3135965cd10a0f424eaa687010001	\\x01c5a91fd6a4b95f3f7330e336385f9a468545b08ba5e46c636e115698edccf99c81e8a3c5db10f2ed25859d469625c7742ac0b120a13cd507fef5f310fc2b0f	1659979390000000	1660584190000000	1723656190000000	1818264190000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
34	\\x57002c31fbf68474e379f4f649b31f400c069f3ca9bd4b393a39ae0770ab6e7161ebc6368f5acf7aa905da01694a7f0b3dd9ad41805e087e88f5ab5351150549	1	0	\\x000000010000000000800003d307efb21091c0d699242598245addee9c0ffe9fbff5174388da1f2fea71976b09b575486c3a6312bfcd16ef176b426d8c9caaad9881cae780ea789062fb3b485950d61e2d8b43c574998d5fe70a7758fde03e24e93f11044f6d9baa6748a29e83f6185bd2f3b47adab650c54631d5d8a006712b45524511a21dbfcf55fbe9dd010001	\\xb059323746412fc0e52449be0996365d9ceace9d5b499ff76067d76261c7c4984f4bbf76f2a2050d8e95c8da94de0840305e3018e80531c422c2fe0916460b02	1682345890000000	1682950690000000	1746022690000000	1840630690000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
35	\\x5c44978f20f8a16f53148b3ad1e77903bcbb9fb0e2e3056afcb388075552b19a9cf4a4cb1a9aa13f28d58badaab62215e9dbaa000720d94c44b760380ae2ff90	1	0	\\x000000010000000000800003d36c73b0d94ccc0e56c971ca0e4862e6d4cd94dcd73358d166d74a0513a986d42c42331f6856283586940842013f54fa4d9fa7bd9f5e1e58c5b6b93228603ade61e89830a204843ff1b9ab751d832f25c8f4568c3a08c4f198991e3b7653ea2a4e1176f44e103065c41ee699c40581960444e2f50a956b762aebede6648ea651010001	\\x673d557af016a1c586fda6af7b5aa61614488e0ed7010f309054e7ef2bc42fc8b193d06d33c6b4ae6cafa035fbc8afb4d8b4c1947c7410233aef5929c4975407	1676300890000000	1676905690000000	1739977690000000	1834585690000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
36	\\x5e3c4505e825d40fd22f133ed2103cd385e87f087db714dce42b46b6767a7f0cd81d32e3db965312df7e2ead8d85a1eecf070cd86ab8cd0486e505e21950aac8	1	0	\\x0000000100000000008000039e3c29a0d119fd982ac7cca639252e887842026dbe542c96a39a0290c29b91671532a547b76f6c3208cc027acde21b407bc9dd33141199ad919730d44403328c093329097dbbb5ba2bc4b57a42fcda33bb9ea5f5f25943e3cde5258b6686c73ee0d7fffb80c24f48df4e3ec906d5a6f121195a13858c8b89e8cbacf0c12347c7010001	\\x67b88301554835ac735b47afa3c16357167bd53c5d05ff52deb4ac306398c0e4481337713359838eb4e5e5d5c5a7b9f6cd04c07100175563937117b8b438a50d	1658165890000000	1658770690000000	1721842690000000	1816450690000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
37	\\x60383f162d1ac270a26fb1dfbd806a17e6e895438be6ad52e97a2f25ddf14bd550a6195b234c8705af127a94f450dcf5160935b60e39bd2d92968498c4b5e26b	1	0	\\x000000010000000000800003b86db29bce8c9eb07a03a8aac80f618de5cba209a37ef63a20ca3e9fc78d3f402043e5f243a3557834e4ea9470be3bd38fad808355eeb62761aa5c9ba188d34e801da4b791a97dc8413df6e619d2de6d577d6c21949f2a5c4ddf64606c7aeaeb01abb7994e3b2c304ddf0c5f87809125d0eb375bd8820d16da932fc1e783cc51010001	\\xc6369d9c98ca217fff053b2a0a308c31f0370707aa3e23998677627ae76cc345eb3a464f6961d07894fb28a9ae3d9832ecb9578b168b906a1a1a28e836c32d06	1658165890000000	1658770690000000	1721842690000000	1816450690000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
38	\\x63849354989826f38e3f2885f575db39ec507254d41f0232886973b3fd3fa4f731f88fada4aec19c4c356cbcd480effa3dd3b0f096a2d94a5c54b32d95476e27	1	0	\\x000000010000000000800003c9471616a4e6b4ea08c75756c9650c9aef024e7cb0dfd5d24967cba611ad34fbd37da2c6ccb0a4f389414e81a476bc2d24e028987751d0361e01f1b0a12aa82f5019a70dd0e8be09692ef6954ded633f5639e1b67751fa195b687f4f4273ddd0d28e458a3dd9e8c407c78872adcf8e5588b9df6dfea638fd6f90eb7b58294abd010001	\\xef73f1fe3b513a91b5430bdcba7e7bc436e9ddb7c705a8283bace780c232b14c977c9768d40b8aa2de9821757249c06edbcd85e382109b2d72b45da57d5a0c0b	1655143390000000	1655748190000000	1718820190000000	1813428190000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
39	\\x6648e6686a264d7511af0e76d32be7323bbed45ae3ba752f3dd879230bee485ca9e4c4ca443238d2294fd1218894f91c5479778fffb33edae278e5f99061c95a	1	0	\\x000000010000000000800003d4af37ef42fea705852b7bede4f56cd2b13bc1246ef7acdea72e177240a089aaa028fd797107f8c052e9507f7e882189c2e4addc16824a39335c3b4c8f2efef8a58282399aa105ecd9f7e4e60e887c68c73b301a8762b2dba7f0f20c6e6536b28f84c8a5f16aa503e70c40e94932713638bdf02e8053468bb89fcb6e6ada9a85010001	\\xcaf5c2fbc9eb5307d69cf7f8ac70b5654c1d59b39ba7828cd0aae436f14a06c922914d1c52d05a183a4091adf87a1a0dbba5f2514e6540c92bc382247b102500	1668442390000000	1669047190000000	1732119190000000	1826727190000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
40	\\x670c396f99e5118cf2324764a94a7bba0ab8aef1716deddfc9cb17f4d408ed044018d4bc8e0f537c26ab1d27821e7b6ebccf89ad8f15b3d8f3dd5127f2a4ef3a	1	0	\\x000000010000000000800003e52769acccebfacc1e3c1fa78653f096a49933a08d7d435580bd4ea42374b4362f394b79a7c13a764e1bee240d6a849f00b4831c79e9082d83368cedd29faa567c704cf7f1286a79be54a61cbe7e8bf36b5a0d6337d83f6513a7d13cf0f5e31bf6a6b69ffb3b4d634c669614f901fb7db9f4dbf7e13c34e49be172f3bcbecdcf010001	\\x9a22384dcdd52e4b245d4a7ba58b725f92321cae993a6e38cdcb0ef1a7f16b87794a723755a0f9f1b956bd2390a2326332400e766dbda1ab969ce999b7a74900	1676905390000000	1677510190000000	1740582190000000	1835190190000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
41	\\x67a0766f715680b07db330f8022207f3a43c9ee38c6f1bbc23d450c340ce4540608e60611039e8c7a17c72b96ed123563d45fbb51dcd06afc6124bc4ac29f4fb	1	0	\\x000000010000000000800003bd66469b7758b0dedfecc563479ba1e04318361424a5d6db75bf6946b0e4ad6559dc9530186af60fd8a4fa420489a4b3d7371df6410bd3fc12f5b18f12cd734326d7197f1b173e3fa25fe0b0051a6f81550b16798134fd6f0bfb8960b34b3cc37829973d365b3a80963bb66225cdf5c2de07cac5fc2c887cf7e64ae3b8809ec7010001	\\x4e180b0c16ecdb203055b7d48d93cc8ac0fc8404a09f6346679892da78b318fb0b78c5836f1635817947e673a6d38f80b9a73c6116c88cb6da09c8c37687f207	1680532390000000	1681137190000000	1744209190000000	1838817190000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
42	\\x6a5caf61a90ff192c036ef56bc0f2ce8e7ae770611ad232af683e18ff61830db01e4035fead932e580e84d30338821c7250c8b7593e626333aa8203745f28a74	1	0	\\x000000010000000000800003d0887e0014b1c1452b5d28bf13ce844c6b80f3a93e3ada4fb6c6e4fc8a02e073269123f56734dcc226665a0abbb537f489316af14a9ca9b158a06b2872ca96a607898df7e8858d9586dafcd43d0e23e137741328a4cb293b63942f121461b11c3cdf77cc259a94cff787d60d56771acb324366f527d606749a6aa712b5187ed5010001	\\x0204c014eb5483e1d75785805374ea9c425f3b17aa2802dcebc1a63c49b06bddeb764493f93f7a38721c8026ac263713e52f2fb0a7f25f184eeadae3ddc3a50f	1677509890000000	1678114690000000	1741186690000000	1835794690000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
43	\\x6e28e613d0b1ad2e14afcef304985ab3495579b4b3b9041a8b091b353139412e8347547acf682d3f6aaadb1e9127ee26099d37937e4536676cbe93e7639e1cd1	1	0	\\x000000010000000000800003a3f8563f45d78b6de1c05cde77caf814a53cb5793b231e2f90c605bf106f859da0add682be6a4ef05a68c94c90350277160e83e4a401447c630bc94374873ea2841b797ec6b98f27ca9e84ae1aeb59c472c59acd3dd3599f478a7e7144029b0d909cf25516c3921df4029be2bfed43e40a2f1ee0b16ec3d509a9d8ee4da93bc5010001	\\xb85bf76a29e3100ad60ba2934bea5dffe3cdd6f6383f9203736f6f68ba64e66ed50029f3537b73d3e1149c07ef66e9a9b94b9d98a7fee5b456cd8918db7cad08	1657561390000000	1658166190000000	1721238190000000	1815846190000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
44	\\x6f1822b50c0bd68cf30f4333d50ab4bed92b4dd08029666dce8edb36f8368eb7b0dd26b0d4dd45b377ff3bc758f1dbb5d3922309e135efa719c7a7381fc78b6f	1	0	\\x000000010000000000800003bc4d5e57285542bb3338ab9fd8fbfe60dcc28efa7c37860b48fcc7bceb6c3dc77677866a89814402b4dded1499174541564ce827163668b55100b5eca8fa1d2be3e0e95bccb7edaf46ad61214765b0179a1aba4abdc6523fae2ad9cd840b2408fb6abd62ad2170e9d37a5a9526ca2a2231243b4d718594af93aa179b8a950aa3010001	\\xb968c90a2c503176129436cd344effa9d44df02aeaea638a0559d2f0a266e97d66d4d3f7bd861c8059d65c843462a4f13b69a9cece416bf468941972601b5d0d	1654538890000000	1655143690000000	1718215690000000	1812823690000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
45	\\x73c4e0ddb35b98f825375e305af7c53b9bcc449e6849218c11764ba4fe1217dbedb05da4adc06af5b13338c68b84480edbf2eac88cb88809b4a60b226115785f	1	0	\\x000000010000000000800003e294aa5fd656952f92d387671788eda1181dfffe908a995faa320a61d937ce46aa865e0bbf32b6dcfa5f98d0be3303c1f2db0cf5d8241f72e8ccfca14d84f973e99f9fe3db762eb2083a225914e5716ba6f83c06e16e9dccc7668f89ae1ede4644528c0dbe3fb9d1c854840a2baa1dbe5c96fa81922b031825ae15cc48424f29010001	\\x9b1a831cb587570d200383d899f0d81074d7dcb3f3ea508813d36eb91f23f5583f53d84809dda6d0eec937d20ffa97f5b20746bc262e182a0c2223c5bc0b180b	1664815390000000	1665420190000000	1728492190000000	1823100190000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
46	\\x77208034d16ea8c94872cbca4ddb4556572799af298a3776704d25f66fb3d848f508ef5fdbf6381e9839ea31678fc5dd763ad1b5f2df74753fc6222fe5240a9b	1	0	\\x000000010000000000800003caad6bba49c2fb6d6f9725c639e313d1d8273418f77829c74f1e1ba3ab3e8df5b7866e869f364537f42d8443f208bd7ff0628c4d39acb0c59366a8583bad375522260edb8fb78d0176bf358476fed6455b27f42bf1050e6b3a5dcac532c3c13b28b3a0cbab5b477dd12a87bfb948a02f83998ae3036e94bdcfbfab0015323ba3010001	\\xf4fb4f4f293b7cd7cfe606980304d1996529a32c96bcbec1d97617d3d6cf4a89f08c96b77b448ccc1c229b2ec7aabfc3243a4db4588359f0ac8fdda1ea8cdf0a	1664815390000000	1665420190000000	1728492190000000	1823100190000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
47	\\x78140a6ada95a22d0b44d720faf92662a0deb3bcf7a05e122ff28d12d11fb7e62deb4d75ba250d5e496f2fc9c8e2740eae2a5693c6d17e5d5709bad3c93cd43c	1	0	\\x000000010000000000800003c6d3ec4828c4b6bfd921069367d479d9d0a0aa54cbc47b0b4f4908099a5604be1358e7be90bf19be1a9f99244fc27c2563314017ceee87f36830f0c307cc0faf1bed4a59aab5cda77ccdf5e7352214ec4ce90f6ac46c876c45658eec4460f146eb9abb203de70a6d10f412da90adc63cd88b08491ba26b3e78b5bf3cf8ce9c93010001	\\x95b45024bc9537f144c23f5b14cf12adea896284ef39d0f40dd376feda8c093ca68589695d6ed72eecae1187bceb429932182cc5ea45db9cd4590c4535bf5207	1672673890000000	1673278690000000	1736350690000000	1830958690000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
48	\\x796424d6f9ae7b26242f525e8c20959c666b25aab75c4c637266aaf83b57002e7eea3355ee7739989e708869fb380a2cf3d92c77841e480bf190329821f8e84d	1	0	\\x000000010000000000800003b6fd2a1520ec5d57291a9d55e584025b7983a83ec5be113d0bc7f08f34042216e25d8edfc9cd4015e81c5e7e08ebc04f8323d9c77914c6bda985a840d5e709bf1c44e71b003b6482f089988f679703967e13dcfc487e3156ebb19d72026c91c2f2ee2156ab7a28f4c7205f0802c96d3ce4fdacebe4258ab2ea36f75f78273d63010001	\\x70c0c541433bfa9dec0e8a9485b3b33d4f13a7e210b097f7cce21f0878cadb4acf5d5985896c411cc104d74a88227525a1b305e9668a1d8880aec9cd27abf003	1667233390000000	1667838190000000	1730910190000000	1825518190000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
49	\\x7a80fae3b5f4b8bf4c6eb798ade668c09fe56573cef0293b30a8abcc0cfdbaf62d32f256ade7400e02c2c89ec4842618e45233b17a9c5c443fe6788ae3cc23b0	1	0	\\x000000010000000000800003c108be76908a9eea54ffed30ce2c91aefa2155e518a999a8d9fd8c1b5fe318da9cff6890074e813d6773682e526d687b411675cad1ac72e8fb46eabb5fed61381a318ff827341e4940ce62a4f103c1f5bb976a8a65281a070adea45eac3bb81cccf264fd27d91771a191edc5addf19babe7d94621cb30c6d44c124a70ff6ad0d010001	\\x123c3fdeb39ec8c7e47d30a611f360d3d4ba82875c395626745c91cfc04f27487963768b21be946632ce5f05d2aa760f0657a1a0acab60ff48c0896297328e00	1664210890000000	1664815690000000	1727887690000000	1822495690000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
50	\\x7af8759d164332867f606ea5f5ba9eb90908c0a36a4469f9560085733ca5465dacfa2072ab6e0c5712c4de4b80b9951f8c7e144f6cfaf38fae7f0c67e6fdceb8	1	0	\\x000000010000000000800003ada47d98fe49e8aed8f85a7181bd5ed171fda3d1da044cdadec999b9cc851f42825f6d3894e7d7ac2686d4beeab3e44d56416287fdc22887bf2a4981f3725978d891f8e0a517e8819323f316b05dfc6a8f71eee3b47e36a0249cffd573b7c5d8b7c102387c46e30438dc7fbe18e0e53f0354c177cc14b4d5a5f49f6422169c53010001	\\x7005cd648fda74ffe848a82b0426b720f4accf55d00525213603c8bc5dd72da0073a1920198dec19bb8fe5e5f6b0de6a38e6ab0a6cdcb8ce58f44f9ed32e350e	1664210890000000	1664815690000000	1727887690000000	1822495690000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
51	\\x7dfc34f86dd053e088c24edfd2a82ece943810ca9134ecedb453e10b3486f54984c1cd0f331c24dc662381908178f26b481625d37d0fa321d1f74cdf8ebb7ad8	1	0	\\x000000010000000000800003be0394e2f293befe7c99a366c7752b4989291605ad0149bfcc4ca7ebb198dcf6651bbcc569f58cd982831928aa1be987775d628db827cdc336af375f569e4945c28aae7bb3dc8026d63c1f05f5c669ff59d188680664209975f19767d727bac462b9ea4ceb6e7008ccb74d6f9c8ae53e53999e6036704f6de3bea3e15ac682a3010001	\\xe9dfba062559e82f1646f7f949a7c3e1f9189e903f04ec340a653f338565021d9e54b42675e41f8d7290b85fad74da1f0f5af95edcb7048a502043cea21ede03	1673882890000000	1674487690000000	1737559690000000	1832167690000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
52	\\x7d446be3b2ef15b3c9b2164902a340b3e494f6644863a6e575445a8faaea032e141224a0ff60a8bf90f470b92071604985eb2c762f10da752f4071052e114b65	1	0	\\x000000010000000000800003f9fa38bed03836237fd5f5921abfc871a0d9d862924c5726795495d42acd3a05bb2da29a8040275c74a4681c3776cf0ebf8ee68177328de0c6709edabae4190099877a17cc824bd8a8aaec0236b8879dd8d56f313a305891c48268e71960fa0223eeee695bf19ce6ccedfef3b88199c4a0c084ba5f11429040682d36b394f33d010001	\\x20cdbdfcbd9be7011589663f3a4b41516f9b11cf80ac4c2ed8b1871fe689c55d2c57ecbe852b86967fe33fd284d2c4fed1b62ab366791a8ff8fab0b4011d2808	1675091890000000	1675696690000000	1738768690000000	1833376690000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
53	\\x80a4ac7bbef9435b32419d33509710ac73fda1d8c8d450ebe94eb769d7d13de017e5be2ad472d42272363e1eabdd8639eb0162e9213af02ceffa85e453a52160	1	0	\\x000000010000000000800003cbb8423c26d9361a5d5cf73bd9528e7b74d4a0de948bc412e1d71da873c031bfd86c9ead88d5fff4d79eb69272b75a2ed0e0e07be7bba8fb85a60d2c04d66117efa22a40a240b84b02a7c4611311a1434dbe6123736a987b3950005c2fd3b48b6b866daf7986577444b33bb0b99cdd19e8989b9b5ac783d415bc8360af27615d010001	\\x87266b9c756699f3932248475ec49da376e1eed61af1236858ef037cb454ad8f8b8e231f1c98782409265364c67182ceb499c290b48c739e1fa387021e298508	1672069390000000	1672674190000000	1735746190000000	1830354190000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
54	\\x80b82f0daa429980b438201cede63719286f41f8407414f05d2282553459ad2f7c62fef53870302761b46c762c15ce3922b7cc3b83ae945e084944a3a30f7516	1	0	\\x000000010000000000800003b74abcdf8fb6f73c589213c453bac244a3eb27227458be7d3819e91eadac8bbb34df07213ac2c9366bc2100d6fc966caa85e9e33580f06c5c715155b80edf590dcc79d441f9372addb90fed5e9d61c2d6c019188342ccbde9cc7cc57f2f51e78a370d43d41aea9d7504904afbd595b357d6a20aaa227767cf8eb209d3183102d010001	\\x63292ccb24640cd6068cad64cb8ea722219bad800468f9e664d13f8f258e034f21d91591e7c2a96b4a0e9a6358a33685ddcf7f9b787b9038271ec8e57b75fd00	1677509890000000	1678114690000000	1741186690000000	1835794690000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
55	\\x8100b851948f7a637030eed0dafab816a57b82ffdfaab0edbacb237ce75afb915fc6ff80ca66e2501aef240f72b8e7d451070b96fd2c7a7d86ec688999de32d3	1	0	\\x000000010000000000800003b70aa4fb84397765266035c3de76304c60d662dbd14042551150e4e20df06bf37e492de5645db1ff61c84f0dc8446d33ad7a0db0e6875ffa1c83baea45f281d5daef9dd378478558a9df006e8dd772304b1663ad35d2ac4f9ea798cf19befa525618a22dd3cfbebbee93f998c596a31ac060085e95d5cc0684daefd21960655b010001	\\x11eeefbca42885b518e4f12a873da18860eae0ed0debf2f9d2fa9b6ddec909e67a32658d898a2c27627c8581200ebd1145e1bbdfcc9cc45e192749e15576e801	1659374890000000	1659979690000000	1723051690000000	1817659690000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
56	\\x8938d198a21b051e9192020889b793a1be1903e7b66b8b200f58b120ab675d06fe91fcac735a9922007ea0c9e4a54ddff92b76897afb4832f4e083f69329ea85	1	0	\\x000000010000000000800003ed525fe77ce228d152832f89026e04cc80466d03e5f5f9f66fa06920a8d53e6fba2fecb8bf31f59d66adc1a91aeb93f93d2e806882a91ad54220a252112ca5f85d12fa4006a8357cc3c25fd5f41806d7cc67c5ecafc6ad6e39ea866ddbae559dd585b23bbe8ae1634c9c6dddbb9bcee84bc54c76b01eb6e807e79f6cedcfdc87010001	\\x2cf822ab32b4bf875e6487be813b54bd8a26f9d97aeed65a4621a5b9eadd1b14162081b128628fcb4321f98295fd8877ffe4f9febb5abc8f8ff86a1cfa78f208	1678718890000000	1679323690000000	1742395690000000	1837003690000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
57	\\x8d20714c4e5bdf7492e6a36a8ec571d4e336d2efd17196400070325bcb14109906e728e4554c570c2045a4804c6ef505f3f8c716e2b837873ee2fdbb1373280e	1	0	\\x000000010000000000800003baccc5e684a1fd1cf0b48ed4e5c031287f195903b937c8ecb544497dbcd8593dcfc326c3a70c2191439e6fb9dc23bf26f23d1d9c5219519d69d2daf57c8982d0aec79387cf45cc4a20f767a7d97abf8c46740d5b10dd4de43e1d18ac725dc3ee5ff66d4106c9e9e543529fe54cea37cd400248f31dcbe92a7c88a1b0edbe1f93010001	\\x7347050ac36fe623c9e52bb944a750e19557a9ecb6490e0a7fd8e5b4a89a3d35f3a7d03d658d2d10655a9d0c608d78ea36b178bf3d04f081e82824d8bdd86109	1670860390000000	1671465190000000	1734537190000000	1829145190000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
58	\\x90e48f3ca16a0999ba1dcd4af5e82b8c8125080372300d2f5fbff48673e2ff33484e7953bb4e215f05f4ee6b81aff9ac49dc73c59c62c0b33439ea5f67a331cd	1	0	\\x000000010000000000800003cf35f3e8d19329c587949b6eb16878c58441931e405301bea62b2494019edeedf4fbc05600efeed359b445d9caf29e8dc139783eacddc2411b6b5125fed2738ab17ee4be2015625e4baeab3a3675e520932bdd6ad99567fc003f553f954cdfbb8123967a9412579326567d11f6c6bcc3d79014833219cea76dd8dc33d8b50bc9010001	\\x7cd6b103279ab43a01a3370bcf6638307c3d603abf028e9c529c32bb81b69d7f4b6679288bb78f3670af277d30e9a185323de71c11dbcf572d4c0e318bdb2309	1657561390000000	1658166190000000	1721238190000000	1815846190000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
59	\\x93c0f687a2ca97d389857a50145f77464ca650077467e680f5a523fbb7df080cbb1840de39daed3a1229eb1bca21e9cf3c1698c78ed8719b3f13f69aa2893053	1	0	\\x000000010000000000800003ab21fe6b13485cd79b22b4d37ce3927a95ccfa264fdb95dc7d96aafd45953a104046c2fb60a89ca6cc65859b49e31e4e2d2d2c51b5a9de46d5d75936a3787a88c7b0f006604bdc8a795a9ae2e151a91ec0324defd360b556b15a5c6d37fd981e6316df345df0444d0d91b508f0d37fe31fd64a291740f97ac8ad02b9ce4a924d010001	\\x6f0f10163513f55e5509b92e034c9b9303560a5725a410dbbd7f9f0816472ad411222d73d4004b23767923a71ef4a9fe63cdba621cbfea1f7da47d9c8a0abf04	1662397390000000	1663002190000000	1726074190000000	1820682190000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
60	\\x93f456132e435b554e80986f6871ed29773ee87124d6f07a60bd19ce74446088a5c58f6504ee5ba5f74e42a12e5986b27eab5d2db41adaef2556f6d5d540769b	1	0	\\x000000010000000000800003a1ee837596e17c815f459a9d2da3b149f24c0d25574c74c00d4cf077a5c098e98910809530ce1f65b62c9dce1f696d65e0a957902be3b00623ab9f390e0f4be5be95a41cde15dde1adc69c25d8f140ddd630fdde6dd72a722dbc007bc32b15d826fd86b3634be876874c5df6bbc9881feeacb87559b31b4e4affad49f1911d5d010001	\\xef2ac89696ee5a722bcd8a4da11a48779d3b0fb1332755f33e982c1d1594ef98b3636eb85466dc7c2b5b131adff1385b683b691835d86d23c8ad07e5fc01e107	1664815390000000	1665420190000000	1728492190000000	1823100190000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
61	\\x97840e3094b9fc50c6e2aca01f885a08289f23f1488890218066dc16c5c8878a9123051e55eef2b5141fe06ba0d93211432f6c7c423e33bd7439fe97951a9020	1	0	\\x000000010000000000800003c1ceccb7bd9526183cb30ab7d61b5e779415631d93814e1a590dc694c4841ac7bd999d384271cec9a01520a6579901bddd8165ee0828d6a19c2995801c16905f20af3f82f47843d3bca08965824b59939c19d9be41bb29c8826c78d5e51bcf37fdfdb6647ccad38558deae74c77b9a924553bd288e6d5feefa3bfbce3557b497010001	\\xebc4aaad2f5d03dd8c4c862726259658e95720b60f4cd1bb1c1c61bd1a348368e8dbbf86ca1ca4124474e4361ec1e393179fecca3e2ec0fb497d5dccb5136f0c	1664210890000000	1664815690000000	1727887690000000	1822495690000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
62	\\x9810e6c1af9897bf074c3a8f34cd02aad45205e52bd79d4aa706abc6d84653978a96da8b0403b8c4e2e77b98af8648719db45e655fd3d4c486ebbd24bae5fb88	1	0	\\x000000010000000000800003c21a8b8c128d3ee7163e7344065ffc77971b77caa418852cceb1415941c64f54e79c90f159fd63c59c6d6b5b11f7b1364238faedd4fa9e96ba358b7bee7324cdc5b6a66cc10cdbb2abfb387564a6ac7e2867bb51d3e653e2616b43a1526bfb2d876ff869e5508f2a89a3b3b2ca5b9f2f4b1d108ed5fdb70d6fb5bb22e54a029d010001	\\x90f30892b254232baf5a2c5e81b0c2ca00d1ee691e15065e577dedf181e3de1e8eedacad98cb05284c28a44c1410626363f0853e72209af6187f78d8a0375e09	1678114390000000	1678719190000000	1741791190000000	1836399190000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
63	\\x9b28290faa75a4ec1c25dcc965621f83a49d43fcd9b70131d82e72e615960bca4610461b232c9fb3433455cd960bca17341ab2b0e458d35388ed45a85cbcfd46	1	0	\\x000000010000000000800003cac09d6b366e4f9ca02d7c64fe82e038631752b66ec9c2a20af349a40c9dedd3a7576fea3988d753280183ce7bf5801bfcb661130876bece6dcf196886e4bf2bc7b528703149b5906ed8bc0ef1f7d2ef5a4515576783292c131f28da413ac234bf742d2c01f064e5cb4d31d52d7624e3c9db1fdc2414bbb1fd19926e9d69b783010001	\\x35589408033cbfcc5f9586670ed00694e6e21f1291a0a6a31e13d6074aca585a8d7728b570abc5193c67d63934a784b95869d0bdb42e27368a92e4815d11ed04	1681136890000000	1681741690000000	1744813690000000	1839421690000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
64	\\x9b6c8b4ae9585d999298b242a5a090be6b538a89e4872051baa96690b75280a6d094a511b5f26e8349ed18e789f1a9f6033391902e01d826dc116aa3fe626ab7	1	0	\\x000000010000000000800003c8bbf88110b4c104e1eb794a9e962862c80ec04d361fab286405658dfe219a9b4799981c74c98ecbcda6999d2b923d6b8bbfb4e6c67eb9f8585fecccd9711918305ad486ff200a4b70eba991b49b1e5c80f9c101c572ade3b0ff07cc130545fb6395c1371e42c85a441a386dc0bf8bdaaf87dc37a598a792547de660f28d22a5010001	\\xc96f3f61d30faddc758498f0ed4b63b68b912089232bfcc25b48d8eb5c4fea53ea01de8f62eb056c323a5bee7069d13adcf756a3a3a1fd39e03c9c3faabafd0a	1665419890000000	1666024690000000	1729096690000000	1823704690000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
65	\\x9f30d4a03ac55a4eff9c17f18352ec5fa3f92a387e5ba3ffa3891053191025084ce6a65f0fdf0d8e49ceef37bbc72e1ae48d429a78a8b7fb501b42dbc27a5c70	1	0	\\x000000010000000000800003c1e1490522e10ac11cee49fe48f297377c13d4007d796e3327829e14abf18380a128f172c378b11750f2dc30b46a756e075fed140872af4382ebd1bbe14623aaea758525aa00c9669bb541e34e4de6b6384478a1025a098c9cdbcd89de68d29c763f3a75466f468bc233f5fec3d80b6cfbf6cfd9d7ee2984404f1166eed53a97010001	\\xbe05d3e21ccf2be14b8da6be8591dced0571562605a5c102d946b4f0299de00e3e404dc0bd5b5e58347af6a6e9f5c23c4cfc9836dec88953bed71e07b2829402	1673882890000000	1674487690000000	1737559690000000	1832167690000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
66	\\xa2a8a6cec2c0fc4a4bd5aa96bb5bc0da048dde26c1aaac51fdb7c16d96b325cbb88382b5de1590d60f647c83142f40717b097a452da1c43a53df9e35d5fade15	1	0	\\x000000010000000000800003c080c15793d3cea052c50eb86e0bb18c02f3c41f636225147ef68fa64287cf626f3f8a82333d18aa604d59a29efe519653d6d3fd0fb362f32d835133ec9bf40c08f2adc0388b451811736a4c3444b672de3e19292e1fa5841b6f8d6a6b8b2a0d4426ce078234cd6f00a7b77e5360fcedcfbd8e5b210a3acef24bdedd460418af010001	\\x4ffd3ee416f8c1e8475390054bca6c8bb64d1b40e11fffc678d8171ebb363e41c0b9b799cbabdfb8e7acebdf0348cc6afd385e35a13949d2ad6bf1571f4bc20f	1652725390000000	1653330190000000	1716402190000000	1811010190000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
67	\\xa69c19ef0b8d47540f1778f3587a0ad526d2c539385306c2e31fe49cb64fe44952a70414d7444ac4ac0252e1be2bf42b52696ddc2251931104db17888c9c56e0	1	0	\\x000000010000000000800003ab9281f853a48c12887277270be65ebdf910a0f7bf67971e2b466c366c9809f6d44ab83c79a81aa2cc7da42113c9092a78db691f597b574a1dfcfa814132ab4907fbd890d0444b35c1221df20c343d85f8b1b1571563b960fd4ef7475eab19718ebc6a937e2c630af4e98fce528a6714e56272b041e314acf64f8126446f32bd010001	\\xb6c1cc3da9ed690b83ca5a8ee790c55940be2d2257288de2c659c9ba8815ce545d816620ab4ebb43b3bdf17ad456d7cd1cfefd4b37f747d7a9738181b6fabe00	1669651390000000	1670256190000000	1733328190000000	1827936190000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
68	\\xa7c84cf8db7ba658dcc417c283f633ef0d9519758ea3943d87bd8ca7f491844a3b54df0de6ba9c1194e8dfd994c59eb0f5f0d4d96e55e971414ec7ae4469bc7f	1	0	\\x000000010000000000800003f4fbb39f934bdccf7f1cdf721b3473083b269ebc0618915aabc8ff21bfe146e6e3d594389d1c59adedbef4a13ca8df03ff4d6aa6fffe2ad2e736f5f5549a12625a63be6dd7e73ad41c706849642b631d31d883b34d5f4ddf0099c42aa303f65b93fea1c218fe89bf0dd2da14b3e0f2912b473a272d343e94a7f507315b0fb153010001	\\xcf772fc4e9b74ad7a76799b904e4c6a01e8e84ea1a76e2d2ee6a8d6ae4b12cd4483f5977004b53da217d30166e196e5915a846775753981b885bd27cc06cba07	1681741390000000	1682346190000000	1745418190000000	1840026190000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
69	\\xa804768f7c76a602be88b37cf000cf41357a1e60930cf8879f02404cfb6ce66b6f4d24c0021b151895a3432ecc80a1ff8c9bc91eb77d95edfa813cd2307206a7	1	0	\\x000000010000000000800003cfb89ef9d839fc2afd9ddbf23a4b83db9b81607f01c3f0fdad2167994c7994d87912e668ee913a0aecc72a6f62219d0f8cf80e01bb6e4ab9a4a9e4202b1d1dd142daf650d9e6d3af61023290947ab0343d71fdac78d30ed25fe50226ed930a57633a12e6fcc1f7aca25bfed232d880b5fdf33cba6a8bea7fe3cbdd39358a88ed010001	\\x08b37ad0b9ed62a304d8f4a7d03970919798e5b44098767b23802d362c912485a0acaefa8127b69e6db1d5ea13ed15730e9198871c9a89dab7e63491a85c9c02	1678114390000000	1678719190000000	1741791190000000	1836399190000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
70	\\xb32422981521a5c6c2f563f7fa3ea9fca9a4e805defaef900d55e8d06d8a37e46bdef17136fbccf84b06f8b040a54db98277396a734418bdb8ae38ca76624fba	1	0	\\x000000010000000000800003ab9c1fdec9e403be5d72b61a9baad128e20a99832b1618d2a4190a086849905638662e37b3c83930c30835b2106921efe95c8cbb8138203ac0ddd3e2ab74f479af2b352ba605c7c2353681a8cab9e930edf012c8c274e976793f6ff9cb7fce60fc79da7fad00011c4f6fefdcc9c63b0b93033bbc6b80e3164de705c0aa674747010001	\\x5af8b10bae19275770a50a47e7fd57391f7652c3d9f409579594a7f70909dfab40a83e5a4e9f271503002e5ad8b3ea725cfc767a124001f4c6794f66b45cc106	1662397390000000	1663002190000000	1726074190000000	1820682190000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
71	\\xb5d80430653dc9f62f412a0daaf401df172d03c197f6f1673910ac9dc95bab5897e7d507fb7264b38b78491db9e34683fce1761d95163ea359edd30963110ebf	1	0	\\x000000010000000000800003cdded49e36beedf8d4597e7ad6d43de4ae1d50a4f76e576c32a4f22af209feb7f13ed28045bbbecdb0ef7f9298ada758de485d200d51ff2ae19a1b2bd565ce6d91e7c11bc8020373092c353403001f18a60756f5156afa7a1730187505e70707feb2ae9c5ed4f7a6ab5a0f8cf1fff0d56381d3ca6e28d9da1579d64e18b58a49010001	\\xd2d022f34bb0d27142a8fdfb4837282ccbb58301c6fe1ce31b7fe8ffa090a6471d2ad9e4ca41ede79a7f9404d2ab2576bff8db1d39268670fdcf95604ca0b604	1666628890000000	1667233690000000	1730305690000000	1824913690000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
72	\\xb6e480ca9f1a693d4f075bfd8dfdb2fb3fc06b0e6c23e02faac200070a8d878be8b127cddcf99923fe8122f8b2cbc8738159d863039eb8353da149dfcb3c1b3e	1	0	\\x000000010000000000800003fabf9051a1c6b22ab84cdc6939352cbac4dc3f8931afc51c62ba86c5f72dd58b5e7d2940dbc9d8e7edd2450f88b606f414bf3895027b087c62718e2cfe702dff909acf75b51e14eb410cc92f3d47f67073d8c21314ec051724f51a95d4ae9291573027a4ed3a0eda385bc33446048afb8c31e05fd03d348b01b63f0b00bde57d010001	\\xa3effff88584b1a320cb467b90a120a1340a4642da84d1da62ceaa60ba61ad9dffb9b7f25dd69db8b8fdecbc487affc94380da25d5f9dec1dd529f43f2534a0e	1655143390000000	1655748190000000	1718820190000000	1813428190000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
73	\\xb818230d317d6ecff533e83fd9432b4dfda5be624c551f5b37a52fd51800b4f3deb74d81f45b8bda8e1694eaa43e4f593defc58649aacef10f4fc74fb0bddc76	1	0	\\x000000010000000000800003a0da2d652fd54119eb9c06d2ff9b88da83ae06673605d68d9516a49ebe4cde00bc56d1d8ae769fb492ad5568f992c61e1347d116876574e0233cef7da75af8bfa952b39594cb66be1dfd42d506b72cf3af2eb143d14e8aa705d5ff5fd720e6e29b47d1a9585c1b1499a39ec44ecf54703f7a79e60f478693edb7a1f2a5604835010001	\\x6f35498570db3f951347ac7a2aa7cdd2ebbad9882539b984ad897421f2aaa8ed4cfc60b200b9dd752e00c0bb63248ae745557b9064870e287c53dee9dd483c0f	1667837890000000	1668442690000000	1731514690000000	1826122690000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
74	\\xb8445f12b38a9e48cb6dc192432b0a2afa261c4b2fb895e0b72c32685648fe483f6c38b53988846c734028ad99aeac5897d817a90adfbfb3e94ca7d8f30256d2	1	0	\\x000000010000000000800003b8f8ffaa51a07000b35051ad84eeb9b1ea25bd8167113a5bf4c608ce17b79ad1afa393083bb5d27c60ae3dacf132cb13ebcbe9dde43c76ce887f4650187076eee7bd75d66f65f73c5f572242823a5669e534ca4da09c1da0077b1a7cddea98b9143e4e8ef59998ce0870c8fba594e4213eb85008fb547acf49f4a441480df0d5010001	\\x38b8a1d6d8be0568fd9d44d0aaf44642147b9646c37d8de1158870bef1ce54190c0e56fae8b8690134d7e8d30ad10d6779eeba35b9c1c63c38816eed5d3d9209	1664210890000000	1664815690000000	1727887690000000	1822495690000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
75	\\xbc8c07a17b043246d7287448e32bf7203529205ced27f55bd8ba8e1c6439d1bc948130471be0bbfc1bc1727100a1114429a471be5308de7d741515fb4effcd92	1	0	\\x000000010000000000800003c24ec4c96f661bdc502779267e7fcbba6cd35b928e43dd0065225b39303e9c7d587e90a3ce29146744126d09d2a73f974280dd201f869b554eb2fd832de5758657b54e93c144d110643cfb3bf909fc56dd60db44e56685434afa285ebf45a4371aa3abdbcb63905e5dec6aa1ff9280a57f2131f2972718d39209f5790b645b29010001	\\x4ade92e3e080cd96b3b56471f5e08305590bc9baeb3fdaa7f3af9ca443d1749de23778d95d617e8faf5b574f382008495e9eb697c81f9f8f3df4dbddec71740b	1651516390000000	1652121190000000	1715193190000000	1809801190000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
76	\\xbd8c429c1e1ccbfd33580a5518ef4a4a52f0528999248786023ced7c51f48bb7abf54f69583a666d7f02fb370a93612d96503b921044ccfcd71189919572a885	1	0	\\x000000010000000000800003f258849b5825900708f1926b81675a9112c2b22f013ee100d53da6e489233bce2d6b0f386bf7aadd66c8b0b34cc04ea70893a9ef4e5c5b115c266d733148863a52ca8191d0614e2fcd89113a4e74c8a7fc39cd01be0e02b39b975fa4dff6d0fdf95b0c94c7e86f309bdab8a7b2586da8734a2d88045434925d19dbfac7b1c3fd010001	\\x267fab8f6ae9fd9aca934d5f7fee12eb50c1c099ecd39b3d7873f50409f2997545ea9691f22b2596e3af8c4047a0ff8f516c84d3394fd946753b4a4c70514c01	1653934390000000	1654539190000000	1717611190000000	1812219190000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
77	\\xbf2cbf13b34f7727ef49c3129b45cab33b32418d286998634bc3dd04ccaf05cef7525c1c052085276dd37fac418e7b7a004c32a3a234a435722b6cd9560ec661	1	0	\\x00000001000000000080000392ec797bcf4de77fb84d205ef44628e82f6a8e3452c8fe5337395fb164f660276fde6e616de28ebd8532ad53d3e1aef85077a3592d0dd4f606c6212047593046f5fc94c26bbca39b68f72db69a2c91a858167aeaa3cb085bf25ecd043dcc471d22d0f985343b64b514ce92f943f4d160178d65ec894edd25d1df50f2438dd585010001	\\x18871b266617a5cc18e09c680581e00601889b4252584e60cf34d7662b9a22cb49e028b5a06036314d88b362323ad6bffbb777013e620eb82a41ec30cc7c5a09	1680532390000000	1681137190000000	1744209190000000	1838817190000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
78	\\xc12414996771ebee5d8d0d6d57d1a218ff7161ac49fdd1312a5ef0ddc82989eda916cefa35b1ad968f890e2799b4b478959633839a04ac6c583b7e1f18a0603d	1	0	\\x000000010000000000800003ccb9f44977e3953c5152fd9dad4dd58be98371184d034a3c16e15c0213892cdc0645dbb41a3426ac72df32b9a3fe22bcf0be1a4c22990e1825eafa272ed27a9dbc9407a624474d65cfd2282f3e92d7d7c0be9c86afde25a4206aea833fa237a54ce3fe2c40ba989b76cfa12089569dc444be6343286302603b97b090a981dbbf010001	\\xc5aee11c89ea513f03734b552d6bc9b511431acb268aacf0a7a018a3ead041fced7ddbe403e983469395c7d1fb3ce092f8cb20890382ebcd935488a839d4780c	1657561390000000	1658166190000000	1721238190000000	1815846190000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
79	\\xc110a3fe368c9c95680417a122b58e96ed839e8eef7b0a3971093953d95a8538c903e79673fa2ec40d43fbdea03f864481ce069ef2a986c47f10e91d53689b4a	1	0	\\x000000010000000000800003f0c9a000167206dffa7b5edb202b8b6e10243218cab23aa08bd10102227957b04588c14ae784841c21f0bede7e5604ff9723be07152fc35b36762777d1c33130aef5155b4088494d0f3032e8399b5f0d18eb467e8c27852916caad23f7abf849aa30dfe7d884c54f09146d38933b64af6e08b223ec464b90d282f24a890858bd010001	\\x2acc9cbd73b71aa947665978ee358e14bb1e4ab6b3ed791adb0e8b8062420612a688cc2e764bd6155381421dee8acb6044771df83f5ac3c3645c0da8fa115603	1677509890000000	1678114690000000	1741186690000000	1835794690000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
80	\\xc498e7344b13fa7cd4162fb5fdf7638b5c66e7bc86f7e42169b98879c11435b729e635460d2e5f5995af3cf0bbe7b2af413a3ca1c192662fef212435a28909cf	1	0	\\x000000010000000000800003a1b1469a154ee3024493fe2d3872a31ea38ef8466495f6efb59e72a65a83f594fe8e4e4ab6f69d0c6998f0d8082cace7aaf098fca0a8addd26ccc3be9c7a6224b3cd894314dc22935417607ea21138830b856ecffd442e31919c4b444b1e45b72d6a9969a44cd9df076b372c47bea89a0387b2edee6c32e1d6c168a917238a4b010001	\\x5300abe73ce111eee833b9b8e28a3ba46482fc761619708ca30f6e284e097b743861c3ede92193680d09dc1139e13a1d6add305b925ac92a5830052a513a1a09	1679323390000000	1679928190000000	1743000190000000	1837608190000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
81	\\xc5ecf1f721f74f7d8e3d45328c1b904ab3efc90695aeaf2843acfd742ca9d08e6eb51646d26276a25800f3d2aaec61e9500f71af4b19b496d3fa06f70dcafe30	1	0	\\x000000010000000000800003be186c931759325731826a49749f14f73be38a58f3cca92ea688f05fbcd60379ebc1648c6ad14e6bcaaa678f00d277d45fca21f333eb17bd364b8b24762ee92314539b04121939287e5a3c4905364da5b05840de0837017a1548ddd28f25a5a8081cd39e85f1b5e3fba679dafa35d205d58c134f575b6d83d6066a558bfe91f9010001	\\x1a33cdc37a95ca150cb3067463fd2b288a66292ff12ab33dadb6a69c9e19007309cdfd7ac7b3b04e5c0c4ea5578f2d85d480a3adacb05b270c46553110d9c906	1660583890000000	1661188690000000	1724260690000000	1818868690000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
82	\\xc51c97b3f2bff7ccd57bc12e283cc3d5d4c300bf29a96dc524ce30df163a020271afd8a1e190b2561f457c7b6bd19498630e0afdfe7e1be6d633e1ca4cfa5f3c	1	0	\\x000000010000000000800003b6d110aa27c28120c4fa5f72ba5a39dc2da18949763d7e8ed45e5f6508230bba5d7626407b39eea0c876f168352c59b806f96827f4426c99120b71e521a2ecf093bccaf2f2c5b3407329280ec3e2dc861a188550a25ed57659a101483ca4f5a20b4d012915e6e07bdc79c1c475c54c93384a31be18f617d0bd09c6d9f3d5b749010001	\\xd71423175617414053622bbfe927374bf243693ca90bafa0e2dcc7711b78ef762dd2f455ff07b397db83348d66809d4e13a7b8a20c50014ec476212e32054009	1682950390000000	1683555190000000	1746627190000000	1841235190000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
83	\\xca3caa0dde5fa209d9a3691c91d059361f605b110578f37b13b5e7c0a4b0ad835ec7daa420224afce5e672e68244da2ca94018da87f14555380c33a5af6c497c	1	0	\\x000000010000000000800003a74ccd4272ef439efa1a6356e2bc6692bc324a6cedc217e9f7dedb33fd87ac0ac82d8ac957076edfc2bc79669fc0b601ec635c11ab65ccea83cc7d183afcebdb1621031056701519253fa40dedb20b467900185abc7d2c21b05ea04401867ea0b59620f2355cddb7a233f649c5291842d5cbf5324cd2ccc2fcbac2a34dba7fdd010001	\\xea356fbcb3f1bea1bc5b51eeefd34b4a4644cc16669730f54dec4811fce3a42dd03f6c0b16520bed7cc4686ad9040ead922c29764a64353b57b9d5134ced6f07	1666628890000000	1667233690000000	1730305690000000	1824913690000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
84	\\xcc3878803df68c6ecf9b1ff4ab178da130b0b6e23d4dec469de8147bfd24e79ac76d1a2e0c4f9fc031b9d54c3878a0eaf3db9d8bba35216291724c547b69e61d	1	0	\\x000000010000000000800003945f694b0fb298a530bcbac4e53e6627e0f8868c3e14bd0225198454d2b705961d22311d1dcb14d5572e154cd8982d40aaa4a6cc2b2eb2c8ccf310f60c867baca9c6bd5fe02d0437ac462cf3843b5815bc5840ccc079a5276cb8e78720381be7abef8619f96e33ac17b63829b98bd314ea44fe8ef1f324a5b7ca8c97ae06c7f7010001	\\x27ada57bdaf838ae9f4270ed0ecda0213e908fb4b13996b9bf8777f8a8563d87e7ac1b99d73a3345424e217e663efb277fec219e75bef6d573d50d3f22032506	1652725390000000	1653330190000000	1716402190000000	1811010190000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
85	\\xcdd08b4b12df50a5414ab1ac835e796369e261e7a343287374f46153bb70e12bf4fb9f8d451ae2b71f6289fe75faf9e31140683d22758c11782d0f543c7875c6	1	0	\\x000000010000000000800003eef2a8d858b087d2d1a2b8fca126a06a43d1497815e9e89bebe8c1d2e9ba42072c3b3d8820a637c2aa42f437606e7d6efd04537e9a5a744b50919dabceef3554a80507df31b669e4eda72a2d7a8aed34169c5e84ee19eb61e7e2bd9a5c03d88ca3d239a90193d123a643f2b1ba672fe866a124d6c6e81a3fd04252bf2712bae7010001	\\xc44cc94a41c77b9168e257ba02707db1434d8a71970313dc4316e775e5551d114ce45c86aa10c23323e17eaa3c661b19518110b12a43ef25566b8b627e00cc05	1652725390000000	1653330190000000	1716402190000000	1811010190000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
86	\\xce34adb3905f5b5c41f7fe0050d48cbd22651791c8bbb2347d6258cec8c4fe5548b03bcc6da0bb7ba1a9ecd8f3325758005f670a0440c0e3a4f29a6693b49507	1	0	\\x000000010000000000800003b0a8e4a4294ecba5ee31a80e4ff5dcd8ef3fd71341786c371083dd9ce5ccf86fc3bf7a43a99d674ae01720b0b2d11fa37b8622d3159dc560e058c5e3aa7b728d52b3436ff5d4c768593db8677a542a8f91083a8b8f5c837f275c51c208148b2fddd6d3f4aaefd210b670fbdbe54220ab8d0f84e7467923cd899b5b2c09f5e5b5010001	\\x165ba84f8ae7228c0060586c23a96ec9f24775bc115917e1178ae9688b27409e21876e0258538a9e9504074953a1b5b889a74971c900d46af856863e33eb6f09	1675696390000000	1676301190000000	1739373190000000	1833981190000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
87	\\xd210136da5653f8bcd8b01d39ccd317e39e13e1379cf47fc48c9d38576dc06986d9990b86fdf881a18dc62c356f19bda9508ecdbec78e0da08f5d398e4e3285b	1	0	\\x000000010000000000800003beea8be0ec943fa9d1ed09211cad6be8f90aa598ca55dc1cf002c67f0a6cb0688d287a77c11ec32275c3427636299b77fda3519f77dcbf7cc1b94e3c595d906b8558f30a0a58a90818b38b22d40878a42ef3c3db26171d35cad1716ffc8bb70530f2e156a162276a8a846a38a187599ef4ea1f1b1d92582c76535dd1d1217ced010001	\\xc23e6798ac3512ba0e895278f84877ab6f4b3ab4ba60bef24fe9bf09394d343c97ac8178fb6583535987c5b50f25b0dce99aa6a9f67b65a921a030bcec05010f	1670255890000000	1670860690000000	1733932690000000	1828540690000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
88	\\xd23c0f1064942e15ca9a561004c35cd9898fe2ace044184f4c4e7f9a9917f469a258a4c7cd68fec956b70d6e99626a6b969b367fc77b4543b1e96d9b640d78f7	1	0	\\x000000010000000000800003cf8013ef56184cfa2479e2baa1ad7929b4f952b2ea5f94e32999f8fe34ddc01dda3738a1cd0375f33e8b3f9a5c5f5639d8d9a18726a9442330331b85965738e8f78479d84789f0eb8b9b7187368561753f53025730f327c336060e703712e13ac50b328b5762b429d500117223e7176e0a44c32208a5a4a2381ea4e129306633010001	\\x164d37dc1237d96615fc7b63b970fcddd5b7d0e4b3f7df9bb968d53fff8c6ce31e1c3edf9f56026907c0ecde6c0198171dfffa783aea4798409a0ed61bc83806	1680532390000000	1681137190000000	1744209190000000	1838817190000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
89	\\xd2b866c8007abe116f7ebfab4fc5f958c5beab940129023937e10c961aca8c11b6326c643557f3134172faf763d6627a08d5fce721e613fdf126326f719c7b8f	1	0	\\x000000010000000000800003d3f971ee38d33e51e37ef033ed152444defc6ac8d2711d30e7755bb699a548e0cb04de0b0054c3b7c3a3bd7158be9842fb14fb124f254cf256a8e099e0f736b7d774c496b1a7d16377d5a83d539ee2509ef2c0de18fecb35d59c2696f827c18b272b89320da5805bbd393f964cfc23fef5b9fca5092d5070bff190f5fcbba18f010001	\\x134f90ee908b81a122d769e64dba19ea5c4945f5b8cbc7c42f7004ef59e4b3e3d040ad8a20c90321f70fc4349d8522f7c8342eab00288ca938d9abba85bc4406	1676905390000000	1677510190000000	1740582190000000	1835190190000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
90	\\xd538a59cc6c4ca9f6d34ac3533d125e129972f41674d6a3276cec657fb83732a938e02d488352efad5447777cd0f907fb0f47dd1266eb7bc4aeab5c322067ebe	1	0	\\x000000010000000000800003d7a0fee12cdd4a36f61d587b0a79d9eee30d7e09578ff90885ba6bd03ecd0be06d7d0f67312469718352be61b4c52c7e26b1f704a3efb6508ae665e1fe8bc6467a09ef3b22a74cfa53e0429644e66136e828019583cb64757d45b8ceb145d424077a9a966998ca326110e29d57923d55addb79477383ae795c7c06cfcefecbb3010001	\\x55317e817ef474a8752f0d808435f967dfb242d9b8143e5d74904c3a5eabd86a8a7f1f89ab434bf6c5063c67c36978789b5782ca8e44d5dbfc057a3bdd5ba502	1654538890000000	1655143690000000	1718215690000000	1812823690000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
91	\\xde98b6f769579d1e5e34e3dcc0ba1b4256721e71e2663694b51cd712dbb0c7c4556c52bf205b9c726ae5434922dc471b290661ffc71312cf63344be4d2d5f381	1	0	\\x000000010000000000800003d34d64afc5571ddb3a4b0c61cfa6d47f2bf310c0a75c9e6ce8d4893126e6f9250fab1a2ebd6b31cefad1e9b7ca3aa91fdf55ceee8b3c8a5daa070d5b8e9acfb794589692d243500f2ec9c8dee86e311dec10c10080fa8402edfd73a98849287ec04eceff89ee517bec88474541d8aab60568bda5ba5eec439bc61c5bb88d96c7010001	\\x55e87abd34fcaf663caddb1938d129ab097f64fb4df10de9fe2ef352ed0a10cc0b134e17b8cc7804f594f1b166792d83b8585b604b1614f978712640c698db05	1679927890000000	1680532690000000	1743604690000000	1838212690000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
92	\\xdfe8ca81a5bc280b6e7b5083e1a6763a17e7d9ae4557fecf2b4c27ea33c91d96fc6f87ddb1f2787e4ad330f10efe1bcf56fcc1451e031f9409a8bb3039e9a590	1	0	\\x000000010000000000800003c7d98e017b6f6bcc971c98f677e180c307a4d1d3ea6e5fab733dafe7306a1b06378f23a08281c38692300f83c9082e40ce90290f3bc1761df064722df57cfbadb9d4e6b97b9ebd62ec315932b41d8d94be5df983cbbb82b51c04d2837fd72fb893ccd6e9ce894a26b6da829737e1f2ba1e3b56e0ab0a6a43864f841a376ac71d010001	\\xb2d57d3d81cd6dda060c78dad02f09c521cc234cf70317db022421b83d80c04f5f73d25501ed5c24e5b01e358b55ea365dfb03c3ad9d7da10d5824971ef16b01	1653329890000000	1653934690000000	1717006690000000	1811614690000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
93	\\xe03435728ebdc4c45606b67d5dfaebe3cef74d6af70c8af667db245b5a0b56fd45bd50eec829755a65fd8d1d6a1dc295e2028cbd9a30529dfd60d2460981c0ea	1	0	\\x000000010000000000800003d42c555103c268766180b8ffd8a3e2679190a8e957e267755f02ed57f403f4cc48dbe32757d495219bdc94b77e364f322e1c619a5a01d83920ccbbf2086fb3f2d028b2ad14b257d0b75259da1482cb8d44a05e04a61ef796d1c545fbad2e2f2cfa40c30aa87c966cc1715cdc50c2facbeff55d7240cc2b1743634986e161b7f5010001	\\xa4ac905df47ba9d6b0c5641ffe0cf78591cd77be052af2e0cdc4e27a0fbabf044af448ccd5eb3bcadc5fb84d83a1f0fd13c1dc460846010400e6d352fa09bf00	1677509890000000	1678114690000000	1741186690000000	1835794690000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
94	\\xe0c8543f7d8e6d86a49ccc71b8ff7a5c47394f66ad54b7477354d4bd83c2aecbf03277cdbecec96ecd79e0772642f3dec43cab637a21a89e02ad431710b165f2	1	0	\\x00000001000000000080000399fb3b0e1df77fd82c8800ce9823a4d172ccd104b0999f97c279f423ce817bf98e65fa1fd0f2774d020f00d7edd19e050e820a5d030383b971f3127e9a0b8ee07964c613114799cef79eedc01e5103eda1caf28e09e3d1123debf7659fd15ddff2dfa91af7894a8e1b4d42b9c7a3006a9a422219fae8eff7e8c6b6559a983193010001	\\x66c6f0bf69df4e1d357e383e1f622c773a349e69a012091805b9d099dab6722946369412a5ccf00b45e2c1cae418afcc5bdee12ebde66c7d0053a0bb6534810c	1664210890000000	1664815690000000	1727887690000000	1822495690000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
95	\\xe3488591c5fe9ef6b179727d00c83146eb6e7091a1fdf9b695f6e09de198bee3aaee50d17b94b2cc1d98de4c9cee959e63878763bb89111512e1fbc8ffff2074	1	0	\\x000000010000000000800003a7620ef1ae7a550c33201238431221a94bc98fc6516838281ecd64db32f5485661a9e5121bfdb19e465cb01730aa1a056eafd15aef059184e91be7e28bc07aa0538145220265389bb1d1d426aae458391ee31111417fb2069c260f06088a0f8bdd18d4d9d613231fa9a03ef7fcd931ceaf15933db05d9001f5dbd1991a689645010001	\\x1c0d943cec97fa373ba15d17618d0f04d56130b50e7ff3f101fb3f011dae8a5ce08e30edd06d1163ef228c184640e6b23d71f892f8bdaef6b418b32cc456a10f	1678718890000000	1679323690000000	1742395690000000	1837003690000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
96	\\xe3d46227295aea952dfb8079bd6f89565dc1351ab6b5c301b2c29fba080d4af5e411d1a296b2cc276b62717149c01fb246b52d1aa81fe131832605175793cdf5	1	0	\\x000000010000000000800003bec7447e15e1be678a51eb10069246f26f2980eefe5144fe74e540bdea8a62f0ed7a5f8df56287fbc9c472bced61bfb8c0fea17928bdf161eeadc76f7b64962970ebc56107e3ce79c454448f33a85560b83c189b3398df12097d307b6019d8d86a2b29bfc21c341484f0b73be226f13fb3f983afeaae777475773b009ab08079010001	\\xbc86c0d61433166fb9f7dbdf1941c0837b88bd751e3d011d8cc6131b378230b79292e98e205153e045c2d4951307bc7deed8442692acdd8d416779df3f54f40d	1676905390000000	1677510190000000	1740582190000000	1835190190000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
97	\\xe3b8cc44334f75da48fe2f6d7e05170c509dbeb04c9e525b0b4b3c964df7d6d383d039a32c49abd566e03db2224c9ae95108b87edf0292c06162ba8b0fe43c28	1	0	\\x000000010000000000800003bfa94b9bf417e6cfd209c4883217b5c2e271539e1ea36dcdad814f38c5bb07a031d8d8f93a02c5a07225675195297ca8c3d79105c160c06fec7d50a0a176da09f29c924b9040544b5610868695f38b800cf2ad2feb7d4a913ffa032c5ec80505ed061aee1e2fb8b10871f7a3ad9b5d1cf753073ca77b96fee101639d6976b0c5010001	\\x5e5dc0551e2c7f08dc8f3fc4bce8df3029c4ee23a271d5766a900d1be231fe64119c2d19d523a8010daf3fa4ad8f893d1557f7b74a9bdfe3e2c2efd4e88be900	1661792890000000	1662397690000000	1725469690000000	1820077690000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
98	\\xe48074f797915b7bc18171f266d6e181c099fa52e1f4b061e0b662a2de7428aaf38940a2431a4dd9a85b5df55c97198e0af7278428151844164e27eaa61ba51f	1	0	\\x000000010000000000800003b40078598a1d1ca0a2ac762b2cb7f8c160c7514e7a625ce13d8aa37cf99c3df7be313c2c32d73742c8e468295f9ba19c91fc555a05d01a6b3c88567fa4b5710ae9c1d949bc6cb72b876ac72aebcc4c4a27c6609913efd002207ecfe2e526f37959680b64ff1c495a3d1066188a50077ee7686a3af43b0acb0047a2d178242bd7010001	\\x22f820af4c641d2dbd72d4fdf9012652e689ca3e5aacccbcddd4a41ccb12e27f181ff7a05040520b6134580224ecc59a40bf7514fa9f5df6e7d15da5966d5e0e	1662397390000000	1663002190000000	1726074190000000	1820682190000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
99	\\xe520f061fb84615630dc42c547a54a48671c1c2b22ad39fad05bb5b8620a35c4ec99e88af7f154d412fbb343a94110c7e70a3392f2874445243d20823251eccd	1	0	\\x000000010000000000800003c090d39ed3ce6e66f0083b25193e166ec519ba5c07bd6976d40fe2b7a64b3995dc7bfc1b0ab6fca162b2b66efa3a90f68e758f721b8e9d8e7b0be1e9149afb5933f927283fc36cddfcbecd1df0bee1a13e8d4bea71b954a3202f027295ee518fdde60962f56369371afe64e2651b84b8bb996a97e53192f9ca611a4518f6c367010001	\\x20e0ed1c81331966ea701171d577965fd6009d5ab7163f0f93f5be7d990d3aa33c3622bd0049d4e296175ec0d9a9ced6d9f5c708d400995fcd1a587fbdd17002	1658165890000000	1658770690000000	1721842690000000	1816450690000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
100	\\xea544efdd4f80f1a6a3130d1e4b201e75f471f0ded68711b8beb183d156e2e1dea46a39211b8e41c4fd971903948fae20a5e22730640366add5bfc401195b5fd	1	0	\\x000000010000000000800003b2a0163913d6563b573411c0d8b942e95b1267b127e97dc4a33b63964d40616952733b41d7351a2b8f64066351f73ecff2ca9974ad2d7fae8f898957c191fbc96289e39492f91d3e2ec93e6e0ed58b32f9dae897ef7718893de510ddc13db05accb4af90c12d1e4130d1117e0ebf2a59a4e5f4decedb98f8b0c0f2727775f4c9010001	\\x51e07bd8b7cbf6f211769f1b03439157dbd2619194d3c8c70df8c008b248803868a591dedb1921db9d237b63e33803f13362407e19dcd5c99998129433f9260b	1681741390000000	1682346190000000	1745418190000000	1840026190000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
101	\\xebd033e858c4995082d0095bf9ddcd56a915837838e075060e62ca39d86fc269b83b55d50721c1140c2b5a0fb959ea7dd5d8f2655f8b9586c6e574c44ee8e739	1	0	\\x000000010000000000800003a2b6bf538da6bc3428ffad834a6b9fee4c4af9ae7913cbcf41758019640cd4fbdaa32e970b372272eae1f5f23609d0dca6086fc9049e77bc660287f8198460231a3509a093e7aa669668d6794ecd9e7267a9c8db940f0a96c74b560efa1354746043e590e4fa6cd586d09698a95746b5b398fa27f842c67f251d920540d57c53010001	\\x9f94f8845b8d920c68ad544f82771e3525f08c0f72a3ba5987824f2b51d61be0003b1445d677d58e25af4d6d355cf1864b3209fb7f572cc23f59a1d3ed0e5609	1667233390000000	1667838190000000	1730910190000000	1825518190000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
102	\\xf584264a2869a3360584051782b5b49d68e6a5f6fde5675e91c059b798949053fabb13c1c424b76e0e553b5268e20b2e8fca8cb4c1b4187bdd1bd8e2673fda62	1	0	\\x000000010000000000800003d75e97e6eede0138984bd86ffdad706baea49d13d1f770cf668956294ba67b93afd1fae2b7186e82861c271c828a9e9a0d92b75b7240bc9a20864c8a34bf17580f4171eb29aa5475ea958bc1c012f09432f94ac0ea1443778c364b8736a3af9448abcaf97899478688cccf8a8615e68d6805370f45368aabf32717d533abc083010001	\\x7c5e01447e623a235cfcb28cffb488f2cc4f892e4251c1535eb1d4b8dd0bd9b9b6e57155f667a9f154b4263fca7d82a30218abb14012f89253350d4f13984a00	1667837890000000	1668442690000000	1731514690000000	1826122690000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
103	\\xf76420c9b32ff7ef7834e5f224bbc9d78025adf5a70f085bde4cb9030ccda9aab8dfef98558744ba79c821dcac1441fd11d61b6b300a965cc6dab81bf8e44a3c	1	0	\\x000000010000000000800003b000f0b9642561bef99f8f201452fcd6daa04455fd18dc32915cc005ebf465ad720ff7cfb1a8cfb5a6f5e12d764296dcba0c50a34f30e306f4c28ffbd44d1826615a1914e6f9bda9ee4a8ca6d3d9d01c464ea71f89fbb05d4d18d3c3dc64708c908f530c38d73b20228b208a23f135526b7fde331cef9186fed592af578b54f5010001	\\xd4b8fd85c2c7fcb8cc37fa05131e90efb9462c1d7bb1303ae04a826e4577a9761896f035befee3ea3f6f3bc880b16a3454e2301e1ab219b49401c36bb3cca107	1663606390000000	1664211190000000	1727283190000000	1821891190000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
104	\\xfdf446f1caa09b77e59c11ba4430fd59d7291e040b419bb393a3d6db24b42218e345d91724aacdbd0f6574c84dd8ed84d1607467be121b35ab7c3da2c554f825	1	0	\\x000000010000000000800003e086260cc208f82a3038ddff40c00e0ec9802547bb254d28eb46b6020a5b44c5dcb4e173c87dc745545247d8ede5569d8018749ca00a63a5d2342f247bc0440d133ba2e737c3281e93b157d63f1dd2cbbccdff0ca2944d812f8ff5325d9de600aaf5333a52b750bc62066b4c8b9b743a5666255a331d57fd74fe47c0c4ba1599010001	\\xa4ee943ddcd24589d2cafe5f7f9de3025d4fbe72b50ad33712245c1fd907470b4ecae46ca6ca30eddf2de7947ef992f4fc52c408f5aa5c6f7ab79b1b5e139b00	1682950390000000	1683555190000000	1746627190000000	1841235190000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
105	\\x00d51b0dc5f1b5d6537d4f9799f3226896aa528587d39acab2719de6f42c621ac4872a909493de46534dffc01a7ff4228ad937b02c4d83b8a2715a2f045469c0	1	0	\\x000000010000000000800003ba790625919d564e783aae55ef5a7f54fd2eec27cf5c28f58fe16b34e03087f9c7400132478ffc45679748f2ae28455874e3a34ecf28408f482c8b19edc14cbc1ba4b183ba67e2c49d1d9359d3487102cf1bbaf9498bf05c32aae4680984e8a6740e2428727bce1721604157ec93d8099ad27fe5c6224440a31a65ddbbd74f9f010001	\\x01e51a77a64fea9653bd20753ecdd21cfc272c0a59b9c04ffb870f365e54e54c84fca5ea5bbc9ad2191fb2831d30ece1f29ed5fa69429fd796f9aa0b66c23e0f	1669046890000000	1669651690000000	1732723690000000	1827331690000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
106	\\x03e50c81cced02f6d6f54c055cc51810259aa59eeb858f7dfdfafb28d7c3ed9cbe6361a6004713490ac37c78dc0d33d089b8b6152d656eb4347c235b58eca0f7	1	0	\\x000000010000000000800003bf29a9c70e6937599e11834287df0bac73b49778b2c2194ff415218f5ce8821013b5574129fadf1d423dafe7cdb31642416c22a8fec46d30c29a4a1dad7cf18bc08fce97c77d0d2f045defcad72f135bfb8efa192abce2bf467b72e1c946ac7702ee657f2b14d9ffe8657346f7d9443b1c9cb21688cedcc9433d0cac74a37499010001	\\x3ee593681711908b4d5bc15bfa73e0b3fe44d8e813616cc14c6d29496b637f67612f8cd3fcbb4d43dfcddf5e267bab8bf14d9b51297acb240eb39db264578006	1653934390000000	1654539190000000	1717611190000000	1812219190000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
107	\\x054148d04d8cd76f385e97be6e0fd2706e7cebb56b455f76bc0d96ae04587cdaac98e4aac6303c665e6c4e9854521d3ebd160693351928af64a49959de2e2c84	1	0	\\x000000010000000000800003bacb6b12aeebb4ca5471b54f7441f4a097fd9c9f81d93fb860536b3a9535db28d5b6e66e34ab4e8f811c5eff5e6a8d3b8611b2c24011d82c474cf27693ea98857553e9d20141e531bbf1ca60aea08a7bad8f6f0cad60c4b68e46756c97da8fcb8e87709648ce962c7e5ae3b0919e7076ee6d84e8a1861d70ff6b11ccb1bcb8d9010001	\\xfc9c4a8a10cfa5f21324db4cc6a7897d32eec49744f74dbddcab53d9fe14666a403e5df68833f39644764eca8fa3ee9aef740077bbc6f673ad2b753b46d0eb07	1658770390000000	1659375190000000	1722447190000000	1817055190000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
108	\\x065db3838d661ec487e081305333d5798d30344786b4cba6c25a157705bafe882d1eac9314cfd5185c705e0240af72411f6fdda17b7cb1c47b4c5195e4717c98	1	0	\\x000000010000000000800003d3f14629d36e16288583f8097e9a67e077835f087609b7754055276e0b3232e6a081d3108c34c143760e5845a66fd897fb2a4b8d14c9c1e5b722a5c3378c329dddd5dad25c86167ce95d873efb2416a24a385f7e1211c79cbe8a5bea353b76c34cdbb40950b71580a082d7c9320987ce390c0470bbbc3e0567ecb4c0064443f5010001	\\xbc7efc6b10f47ef83b0412cba5202064fcece6ba346de2c80b9fcde19d3649cc34d65a9a6bbda8bd88d09ae9a495b3b459de3cfeae6d82c31382e1610fb95106	1670860390000000	1671465190000000	1734537190000000	1829145190000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
109	\\x08e976eb2fa889044212e984fb613ec1c17a8c3df2bcb45a7636eabd0d3a4f88166f78b49fbe09cdd995ee08db05a8e53a04ad3b6abf4f6e77b260bbb6a48d03	1	0	\\x000000010000000000800003b4ca58faf0bfe0163bb4719eefd2560ae2c2e8373379985cd853211824aa55238691188a987ee7c4ec2ceea293e91d7461a226735de6d47746140663ac5cab0fbe49e75a1113cc7c71434e3c4fdb97c52f1f62c22dd25f6c161214a65b46fa16f0e918fa271a6a57f62841f89d66a050847eecdf4f9fab5777ead38bf0fac2cb010001	\\x59ec60d951415b0f50a87803c878a2ace9857b287fa36562573689543ce6b6e3532de814f11a5d912c189650c01b7d2ed407b08c0c4f689eaec67efdd57c1a0c	1651516390000000	1652121190000000	1715193190000000	1809801190000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
110	\\x13957de0e5318d3c567a00b6101f1daf282673577054b092207f589a3222bfb322388d92b126431a8b630028c826441effc8fa4f44655793362f75fee9f11179	1	0	\\x000000010000000000800003a1a4fbca158655563d23b2a604541d99ba7c214016a2fe0407cb60950153ca754666c904bb9059b5c39fa843453a8f433ade85befc386b26eb29b10bfa6a659a72b48ece55977beee83b76266f7699306f451526dc602a8c13e8646509d910fe7ca81154a32972bbf0d7de2ea7f30c07fba4fad5b50623f9036604b07ed14ebd010001	\\x93c404c7acfe09553aa5c4a5e49a916bfadeb3f169282811a303bab48ab62a116bb21ff48c8a17e20e6c2aca367bfd6f02965d3084219c985fa87bc522594502	1666024390000000	1666629190000000	1729701190000000	1824309190000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
111	\\x16857edc4e271cfb1f6573ce0eb89c25cfd5c5f9e8797fc6b93f585346498619011f1075aa567de809b4dbb9a67a98bc085f47d61f87098f5763a999875bb1b9	1	0	\\x000000010000000000800003eede6846394a3e7328a06151d7ad41d0e201aec3cbccb79775674b1c97f57fece627c63cfd2ca5f211a94904ab1dc6e02368ae3d36f325408a90419998010e53a2279d3410a7fe032656ac7bd6a967bb3c174d5970d589d1dd9c78eb1d5e36e695c671d8f0ac2e96b95ab244f7796605123bca604a379dc33e22d396c9599a93010001	\\xc4cdc9e91fa26f1b7fd7bf16e7497fa06542d11aced45f9499d3adc68bd28224198205981acb01ed76daed8ea33206d61ba0b129acccd19d1535e489d16c8a04	1666628890000000	1667233690000000	1730305690000000	1824913690000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
112	\\x16a5e3aa9787b532b24a13a378fcfaa4abd6ab08ed962e4b291d80610ee2dcb4789c30de689a52a730eedd11c38e0e8e78d3912b3790be4e57f04b6cc5f871ee	1	0	\\x000000010000000000800003dc852222e0fa5a8682db49439ed661f8e25399d06bd70a39fa0a774372fb1c5f27ea084f9d3175a94f516e12d905ae49b8e5a3bceedb3a361b9f6ccf63b389ecde7eef5e24b2083bd6052fed089f782f6d6cde962fd59bfa0767ba01d5ea1dead5cddbf6cbe103cf86b24f2910ad07bc4d5c4d5a60995d31d37d241b8100f7d9010001	\\x00e128956a7a01a5152f1a68adb50a625fb6dcfdf080135644a2d7093010f1d3c34e6b70f3eb539e3408ee024688ec97e5e11c4fc3f77f98926e4a46a0736201	1662397390000000	1663002190000000	1726074190000000	1820682190000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
113	\\x17356c5521b4c5957bbbd43cbea68599a1079844095582bdd02f1f16ba28da446812c96aeb27a0934a555d26de4527aacf662608ee97264931d5d3f2714c76e9	1	0	\\x000000010000000000800003baf33635dd9e5989ab5cef756fc7f8e89d97143f56f943cfeaeec453c3c8a4d4d97a1ae38e151778ec716e96b8bb38b660a2ba92000c79c55db29369f81e58ab8d0952130d0736e5ba5056a2648e000cc2a81433504e7a4cff20c15e81f868eb252bb41f48efccc66c1f516a751dd02c8e2bb042d0de791f3e113d9a5011ea49010001	\\x7ba06e58f9e85afa3be68015a9f11c0f83f440095cb0283af05a5dde8dd5f1500b4d80cd955c953272d35f0741ac1a8ae2989649c116d965a2f0e49d66c25d0b	1670860390000000	1671465190000000	1734537190000000	1829145190000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
114	\\x1845db4909861698aba456e107be817a17f3b3b071c70ff8041dedd8b576179c1d74a796a80915427f61da56d279e17335f0ace3054dadbd5b3665d35c7e12aa	1	0	\\x000000010000000000800003cd5f9fee4ddaca91d6790667d33251d3f0d7111b660ab34684fe74b5679cb4c46af198d024ac21a00e7859b1daad2343974e650cd07e3b638b00e2f93311eceb71cc5ddf3ffa4ef294d59430ff3e0ccd9dfde4505be2b5f56307e840ff5f29135c612344b18216c9dce8a54a80101e9103a4f31365229dea76faea7ef44d1ad1010001	\\x5c76987e80f53ac7cf293fc43136176dde0e7cdccad9c3b5ad322fe846659b8b8652bcab404652d7f1ead3d0a4dd868f85fad5718fc9550c221a835d1a208c0f	1667233390000000	1667838190000000	1730910190000000	1825518190000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
115	\\x1a6da4bd9075e61e3d38ccafe54a0fdc60c80a40362783a1b278d9bdb5ed4300bcac4c657096c63841729a854ac0357b7e3d80837b5f7dac7c93e221dbe361c6	1	0	\\x000000010000000000800003d6f9efadb03fb6d827fb6b09e3ca63c736bd6884293c8ab14c4a2375ebe39c89f3e505320b35cf87cbcafa6d5b30085c1891c92da17d752ac39a586f6f8348a7ec5dd27f77d27d9b133f4f9be292e11220b6b33658f587106720aba71aa6402c0190e5c4728f03cf7e1a4790e543f3cf607f3889a608e0ab3859af2a5934e9d1010001	\\xf75e329aeaf61ea0c1fc3c2fa5065ca8e4f1ff2ee921d9a4276e53b8e26cfbc940d4baa97f248cd0a67ed36b74512852e9f53893482f1ad759b59cc487e86201	1657561390000000	1658166190000000	1721238190000000	1815846190000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
116	\\x1d017e57685c698589f93357231a0b9f98b91e3c0944465a1bfd3ad7462e2abb1e9b16ec1c5a596f6f9149712aef86a9e947abe3cea927ac073dc0822cdee5a2	1	0	\\x000000010000000000800003cdc74ba5b1c32998c8a38a15e1f3cd37e57afbe10f3d1fc5e47388c5a27b2d1c8c40c71c8e0e55e8662cbd151070a944da4f53cf2654b1a33d4df946fcbbb952a1deccd53ec9f264b1c6bb378c0990ff95514888f9ac161bc2bae3734ecf7d39af84b4522f2ed698ab0bd1454633648d50d026c1d68df099b42489cfc991cee1010001	\\x2a8c60ee1353e6bea039df6dd873faf11edc5d9ee9f23e886cffcaa3a6bdc4422e7c47752f30c706af6ef5864ab72971afa080644c2a6ffe8d1de5191443db07	1658770390000000	1659375190000000	1722447190000000	1817055190000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
117	\\x1eed8932a444bb2fd953181da557d0c814bdb3d421fd39127a583de8898672ee2b214cac036cdb2db128fb368ae768bec7f1bcd6a9517ec470b4c274df81c28c	1	0	\\x000000010000000000800003adb03ed771b11728173b3b96933d2d0316416731a146b12fa9c19a5ec55eb1f2822d6971cb8998d186e4132ffdd9411946033d1ec1cd09108e88c908ea903dc740de562cf935793a0673c32c199650fb9276bb80cf183965a5e407da4e6acbd6b7fd3352781af857cee91d9a85c5a3e902c19ac59fda6b511c554c75d0c98a57010001	\\x2a6320ae62d0f22eda345e949af7c66d1df5053b55154fb2a660b4fe23be0a00253c7e659ed06e3203be1af47ab9e36803c3574c1c92eb6188638d2ea4301e09	1665419890000000	1666024690000000	1729096690000000	1823704690000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
118	\\x1f99af7b866376a6c7a9bbd1046e83dd626cd682cfc17e6091ed340db939850a49fd33cdbcbb8f64aefe8e172a455d86084fbfc19b1799f7fd82b63b7fa73dcb	1	0	\\x000000010000000000800003f4c75f7fef9edd21d0c97c24519eef18fe4bbbd453d7c68a1d8bb92aa96e48aee22e04ad1355685e6b953be8e9c2733ec5364a16ea826416422d17b187d11c406ba0f7efdc2b7659b05ec70a4ee600eeb413641ba69ca08b830c2f39bea633ea55419a8d132d01f8b9fa2b0d3b6b774cda2eb41a58e85f42ffc6ea170b57a535010001	\\xc0970f34f398d03bd633ee913dbecbad3f1d92a68f501a4190fd6ba5a3778d15eedd34189d81e655e645afbcbb1013645a0ff0624b6414baa5d4c153a7e06e0b	1651516390000000	1652121190000000	1715193190000000	1809801190000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
119	\\x230d36540b344a5afef46c38d973f3bcba840de39a7d581ca51acc2af93dc56ba109eb8828f7cf151f6532c66267d863a0c0d9f75fc3716a8cd10923033388eb	1	0	\\x000000010000000000800003b57d45435186a2fd9ad518de38cf8f0ea5efd975e8f73e55d56523c9be13c9f0f0441fda148cd4a681c798ffe0ef2c35f28666695534d285d91a450acd2784e1fc38b7547793836baefc7c3203d08479dfc384bbce844aba5f5f7a077c5bdfff148888202975b794735737ed5fd7ce6c034af97b977c2bbd8fbe6643e62d795b010001	\\xfdd5102d477a423a8cb37c28661f5778e432260b5708dce7de7d7c0776a43da98e3682d269db5b63b99c29ba2e606c1612a6c6b57a214ae32f2813b24fa0d803	1667233390000000	1667838190000000	1730910190000000	1825518190000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
120	\\x24b5a157b761ca6f14b2a39863ea3509a5af0ac505e5ce7c5d3814c26b053e01c211f130cfc49fad83ce73cd15ec44862cbe81ce1ef3dad8894b331d62605d88	1	0	\\x000000010000000000800003d9b4f151334f4d43b7af3cc115a7e6342e098566a4c9e346fe85e2e6f58edd5889570a3a44ae264862fa5d3fa51cd4cc75ece7e11885cf7e90fd4c80e9534e2816911684dadb69dcceeb36508d57e99b25c216221c9adb052cbfa300bc9d1cfb90a254f70ccc6a62a6df1dc93612ff454a11d790ac4fc68e3c126de735df2a91010001	\\x71de74acddcd2e77f26fdd2b78b1ee8f1821c8bfba54a26ae31c3a154119f8c70fb4b98a8d72a3e76c4a9503a9531c757383d4a15b958e14bd0bc1034604bf01	1666024390000000	1666629190000000	1729701190000000	1824309190000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
121	\\x27fdab3c3d383d329444f19fbe53b7742a5209955a44329b18e62a90bc144a045c86f3881106d23cc8cd2decec693db44d4a92079211ec732b3160d87a9fe185	1	0	\\x000000010000000000800003dc4e4ee126e0e6d3f7858175126431f689a50b4c54e59da4ce9c46beabaae93c7adb85062fa2cd799cb26167d8c1e34d8052c04468268d9dcf0f449f84ffdbde4f6e6505a6ddec97f08bdd099ac521504d90400fc948a15b989c78bac75ad192152261f01fd9586a1cbcfcf98f8d774695850712ea333288dd58b7dd03461ea7010001	\\x9ae4968355ecd8008ebb437ff069d0f190dbc9f03f93ce2f133c77a2a40527721784d74551c4cef878fde074b16626a826a7129eddf3286d37835f11d3f17702	1666024390000000	1666629190000000	1729701190000000	1824309190000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
122	\\x2fbd47d1c1b355a368ad46efed994419a7d79a63076be2ad7d16ab03c77e76d452a62003ee0917730477df97880292bcf68ea5e8469663ad46d0bd7a337433d0	1	0	\\x000000010000000000800003ae031ad10d93b14230a225065beaec814735ad3404bef1cda616efadf3202486ae4bced6eadd673032cdd15fdbb85f620dc08aa153aae6b3c6eeff9ff760fcbdd8b759589e16274c43addc5703f799afc42414d35f60ceb652337d7080bb54926a4ba343a11457fd98ae482b26e0451574fc03c86f9330bfe4cc22b97b29eef1010001	\\xfc3675c005e82b07ed6e67328c39c153637d1ae4dd92e885d7aa3debaae0c46963f8acf9d269bdbf96466b91ceb392c053ba8b67fd7f966977527ac0cddf740b	1656352390000000	1656957190000000	1720029190000000	1814637190000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
123	\\x31e1c6fdc4cb471b4037b5f11e09bc88e6f1c4c499dee0d4fbe28b62cf7b3327892516fda4cdb311c1e53dc1fd52f83184cddf5ffb9cf993256c2ea7ad189fe1	1	0	\\x000000010000000000800003b02f504d4088bf698d3023307c5376cd6a45f2e0a2e1768b0cbdfacc88e3d2297fcb8a479b9403c250b5c1f9af0d8dd0ed3981e49b100493c738b17a182805f998ff42f02bf46d1160e73ed3163bca4ea67255e02560d7d79d63d15b4f13555c0dbedc3e0ae87fe9c1fb63c44098342f0b4bf7d7c59f5b3c49e89ca255a6f7b3010001	\\x04eec47d40fd464c23bcfbfc6dc22707f28518b9a8dafdfcc822fdc6c55dcfdd14a4e03dae64eb096b39ab175ef35fe6cf8a089e0bbfd387dc28c82b0c6ac901	1676905390000000	1677510190000000	1740582190000000	1835190190000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
124	\\x31991f33eb074df03f6c067b7e9200d92bac076fcddf5840efb59a96cb0277666c5419f1cec3de8d4e154765aba73ede3652a5ac6f14e553e6447f42f74911f5	1	0	\\x000000010000000000800003b507d43da0927cc086207637b06595640af98c4c515bf4e411f9cb6b3b6b9db4f43529bdc7313823c1fbb529f80dc60185265cf152295a21cd741b2ed0a7212d683f68331470ec5d4d005e4eaf30c32a81614a0813b4275280d7f7a274dd9c29af189bfb1f06f5bc0c4b6c8a960b4c2758b058eec51f9f50b5baea5e2febaa27010001	\\x86c386534d8d67aac35ca4c2aabbc2087dd4ad122abc0231edd905ed9952eb6d8798672cd1f6fcbaf8890f3ce45877d71161f4456c7080a256a3ffabc1792502	1652725390000000	1653330190000000	1716402190000000	1811010190000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
125	\\x32415decffacb7933fa129191d8183ed06d861764073f94ed6004fc0fc80eff3e7e2fce52d8ef67754e3c18b34b77419ee83483d21b294827bc8809763a8b268	1	0	\\x000000010000000000800003916bc2e5097431758f8105533d0970402324e7edb7855c816cacd5fea1e548f741ccd9fa7e0719898ad591292b2b588b4559676d262a3bab1448793daed1cff79383ceec580837278db20e5c5dcd7d1d280cd05ef51a199ed77180bfda9daabbe1418aea3802e082a5541f3f853a09812d233e2e22f2ea21977b801d7ed2d123010001	\\x2d8ed6bdfe6cc2174e51607281685efaf4a7cef5a52b65be5dd43192b7f7b0a6832a6e1ebcb35af8bf8af7d0793d05b02b4b32dfb4bdc80f4decf192b6e7c304	1658770390000000	1659375190000000	1722447190000000	1817055190000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
126	\\x339d6142403d8c728b616c5165f3b102b0c7e626aabd309ef803a0b0be9da8f176cef9d3fac3c6a1cb688d60e407175f699cb80ed8c61ca37ae8373249c8d84c	1	0	\\x000000010000000000800003c61a1dcd80f8afa81d7753458326f723eac29b061f65030b1e05dc7942208f3842b130a7ccba412cc8a22bd34892d4d20b7d3b9368bd5c0d0b16323017523c08058cb095d860c75dda98e7a4185baefee6179754cfca8a4f766d63008d4c059dcc2f24957142435b995b6470fc88a1c90ab099a86b4689c8a814f3862e979a09010001	\\x8a9abc50dc93d713793331a89e5846c22f24abf47565c377719e1b0d3475b854935d614b3afd616305c15546b96e8b914a69ab3eb5987e61d849637e6a706b01	1652725390000000	1653330190000000	1716402190000000	1811010190000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
127	\\x3311d2dd6c499352f9ec849d6bf6e9612945eabcfcc756d1b77697c92098449323ac8ce734d058d59cc38193463b33395954b12ff792162d56334790ad3a6143	1	0	\\x000000010000000000800003bb3277f4668895a4d644dd25acf400614f81e049e3b80705b67237a0dc0a8045cd3d1fa71bcf01b6e4478cacdf2b1e3d1c70d19faa22b4f6d2d5ffa5688b0eec67b843018bf650f857561153e9690c677bdacd4a43cafd5f14cbed9d4c5e0be13c8f976044cb345c9164d3325c206de7f729060753fd333743c13d1d1154d905010001	\\x417cb45582b135911eb44fdba9ff7e57f098c948dc0ff23d2639c760a63ea1deffcc944bc6f92883c12d3e7b90c1e5e73d3c7fb509508a7a95306cb7c3232805	1669651390000000	1670256190000000	1733328190000000	1827936190000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
128	\\x34315c2728c77a5861cb4f30dbd22b206328cabe42c8d76d620912269ddf62a25d740d5b93f1f671df7c59bc878cb283d6cbae753c6e4748d4dad9e4bbc3fda4	1	0	\\x000000010000000000800003ab0473a3130d6b2d8ff66ba2d2940b56d37c0fe6dd081f05b84627a1695c6b3efb54763bd9de6a9d4539c21f24fe758c7d07cf54be29d22f1ca0026fa9eb3f4d8b24b760c1c4083ead93f59b22f3d15feff7181071fc7bf748713657590ea85ebbc55a0be08a724af8343c8fea77a3634f22b6db3c8bf50c222a2061e884db4d010001	\\xdd45e28bc25dadd9a2ee2d5f516047563c8a6ead37e7e4b4c68c1f0e0f919707d4a06dc36a100ae07ea14e1683a21a8eaca60fe8af4026f1fc3a3a74d7fb1b08	1679927890000000	1680532690000000	1743604690000000	1838212690000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
129	\\x340989fb94c9c84262ff76a555e0bd6782d409442b42ab6e248fc281833a1c28d57b14ed8030d06d89ed4cbb108e9236e03df69aac1cdb2137fe44a27fa26a66	1	0	\\x000000010000000000800003c3af4f243a4156da73462248fabafaeb4dd7de1e9dda9f0379a9651c5765700d6a25e571b5dd7c939d808d3a88c4024edc49e2dc46c2f638592ed1d1cc4e5dc27b2b89c6f94b373ffb6a08daa268c611bf08a1235df2376a4c1615afadf9488fbab118ad10901cc89a966118893bd69528f0e45c97a0400f79c52803027c2199010001	\\x60833dd586090a074dc1eb95951e6cbb6af6a4bff5cbff84938f4d80e086b7e70231f774a764dfa38912e20b47b4a9e08c0d103e5d057959b8597c868c814306	1668442390000000	1669047190000000	1732119190000000	1826727190000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
130	\\x377d6ecb97bd2fc2d474b17690f6deb7471779de07a6fe827801c07f556cc281bbdabb4e987f8873762c0fc26185d65162f18895e64f6ae13eaa23d6b34760a0	1	0	\\x000000010000000000800003b651e5f6ea4e30fa78687583a8d20000986f65cbed8ec85fda7770b5b2255840c01759c25431b2feed203d73d0a7a703a89939fb39e1d584b0844b4581f69b37adab5cad6db04b7717be116e6bf8de070156dfe8c80e4e0f0240481c8d9f76b806b7372f216caa906fd8ac4e228e8d93b66cd71d8ddffec2c59ef6b208ed25e3010001	\\x218064ecb35c19519248b166fe45dcacd87532efe81a422a4705f418a60eceaff40846e18a49a0e102b3402801ecea75ed968ec1c2116b26dbd061bc14fdf90f	1658165890000000	1658770690000000	1721842690000000	1816450690000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
131	\\x378d99b87ee4a593c9bc3561fe1936e16395bd58210e46ea715084b364561339168fe4992423e29d09e5530a6c9cec08656c5da5be6eeaa9ad61627e2b3d5d79	1	0	\\x000000010000000000800003c5a5a573589bc316bd04b728aaa802229f7880e0f1aa32a4c9bcb41f1401fc298877a8e583b100ae094308c42320ebff1921de4b20ef3fe0c06ced3565ce98a4d18abd0a837d49f6bc96ff8611054b78576d28127af66ef03cce2caad2c8a451c39aaa8024780adbde45059af4e1c39076078c504a22b60c9c7978e54369b06b010001	\\x00c5f60f8d032ebe6a73010b5dc4770bb7fc6fe0f8159e5f516ede59651ae05f05df8288cdbe34388c0cb8c96f7b7aa5478728cb27ff4bcde3717d38379ffa0c	1663606390000000	1664211190000000	1727283190000000	1821891190000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
132	\\x37a9d0f087725ed628b60016dc295603a7a2ee320355f123ea32e1053faeb9c8571ef4637ff5b83a3ceb2efc5f445145a0cd12be3f3eb05eafc185d715ff4c35	1	0	\\x000000010000000000800003d16e0b0ca6a1de122722fd5b8739ccf9d8e0ea83096de465a6739efa0cd2320258a5f7a476f0ee4770e0cd1287473e05c761d22ed656cb52b9ba2f5f256d0f86f292f0334ed0743bff1ce04ed65ad71ad43b9fafba0738825899014a2131d4ae961a3340182dc9a61b50ba94605e945f3f3aa704a3243c6206cfa9881b800cf7010001	\\xe6d46684d46df291e8e80277c3198f02a3bd0f982c59aee3e1fe91bfecc02ed2f0398676356b006c4e8bd3c28a81035865cb23b8ba6203608a77375b49baa20e	1669046890000000	1669651690000000	1732723690000000	1827331690000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
133	\\x37016d65120a4aba84a2abe2cb73d0bcdcb1150d5e629f32d8876076f94f30520598cef033278c3130c51251dce1d6467865f3f4fb4a068cb4d21a1778ca4e9a	1	0	\\x000000010000000000800003d55c63db120aa70db00c1cd779c86c981c5d2a705fa9eb78d6077c8128e48f2a6b709f61e506b6a526f2d0a1f95cca9e831ce2a3830dba487b95cd43f3191550691dfab3544a4d165eef036b46c12ff41fc4e1634eb1c35c577d9a34456d691cf58b58c6c6f231cd2e3b47d0e9dc5bcc66b2b3814e6ecef6ed2386fdf39f86af010001	\\x74e401c7940e4f3387edafa80ad8d22186c8ed6c4606d5aa3e22c241a70f2ed24bef3f472122937da7a2776f4d2e920becba01337a7d186256dee83e77933e07	1671464890000000	1672069690000000	1735141690000000	1829749690000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
134	\\x3bd9eaa795d46f45a20a9855424ab35955d566b01a944d0cc6e3f892ed1bed3417d6dfc14eb0b78715de68560bb7d604878f740d03a53004ad0b640c00ff0d96	1	0	\\x000000010000000000800003c7aed69bf28038296e5f2d8f4c5fe6ffe00aa5f1e15ada289d023b9b88ae27fdbb2efa8c25eb3c0874d3d4b70a62c861ac38844381fe15d5590df6cd4fe9f624d55124abdb8f3647a13311f84a4f2e74c56b2a5c23d0b5925526220856cd938f0536f6ac24f8188027a9738eaedeec12835400fd2a24ebf1f04b6e0e1fddf019010001	\\x9dc8d57a6732b099e3ae0356abe3e69e188b30576889e41d3de9e830f730e15817cf9696c0a2f3e5cb10b5fe6f117cdf1b388998af1b83caf8e7784859cff90d	1664815390000000	1665420190000000	1728492190000000	1823100190000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
135	\\x3d21d3fcea35966f1a0af10cd36376359c92cb6ecf863327edc34675805d715dc47a1660313bf5caf75574fbfdeb8f5b9eeb78e0905eeb1b5882983a68040003	1	0	\\x000000010000000000800003a74860cd002707981c9faac21a1ed93c62b55e5347b1b5c328d7902e6d14890d8bfdc89d21f7d46fcbddd526cd63583fb596298201d06f5fec9f6c27ace98e4623a540995834ff9b3ccd4dee80cbf9b0ebe9191dfd89966ed566576edda7c628107a7eef943b5f6f4b4c9d8fb1ade8f03cce06c1845d908edfa56ee179ddaa27010001	\\xdee376ec6c320fab3daba3502a1bb7ca6ea30619917cc93f49ca841f7f55fa596503613bb1334d604004ff6b8c881d5451e0074299ffc3e2748b0b971d1b3f0e	1669651390000000	1670256190000000	1733328190000000	1827936190000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
136	\\x3df18932763d6988fcd500994ba6a263d65a18a252ecb375a809fccf8bdb9b379b85c2db32013b607921b3dbf6ef66c0d90dac897fffde34d8f960fab48f056c	1	0	\\x000000010000000000800003cefa3f36a707b6d4cb5a4fddea7e295705dbec1d1d8ffda6914b48a97bf9aa66da6ef152b6b674d61312f83e9f67ece2d0fd018c23bad9ba73c8378af95945bd4be39945bb80a387902ed6c7515c1cf9125ce878118a0a7fe03097d291f5f2d117967607dc8e76fb05f68a615a12121c4adee177ef0de71d2a8744bf0f102085010001	\\x6aee813ba8ee2820439137b22b2653bd1d0a422ba25948910d2cd262a1579870f6c349636a0deff93a3ffa3418486bc048bfecea8ac2b33c8c75186660d23100	1676300890000000	1676905690000000	1739977690000000	1834585690000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
137	\\x3fadebfffdb03584c8c51ead28e573c5e87862ba28ce18b391786cfd0533f3bca64644a6abfc66874105355a7525044e47d2cd1ee1a6fdda128649d2c29b018b	1	0	\\x000000010000000000800003a6de778b6437e8e17181b276f7aa386fadc71e016f42ae20fff3365c18161587d105680c2bdade72d084965d437dca0bb4a558261d65c3d042028fff363433f1f01333576c9dc0fd145545f9d6909a77b4c872f3a54fc04e84ee52ed8ea70b6dcf4fb2d56f14aa1bc3a0a47528060ecde3208d292d15cc96d7d012804cc28fa9010001	\\x1ba16cab3a5d65a0713ee14e8e7453b4c0d8be7c500d6ed7d7eb5c20bbb8c837c39b91e21f10e45b5e451cfc355f355234948bde32cb19af21b60ba501378f02	1681741390000000	1682346190000000	1745418190000000	1840026190000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
138	\\x44ad3dcf64d355df08131738cee4e4ff767e9b20eda78ea857508909f9850f38237006454d56a952d72a96af76890e14d801a311007af635deef687e8154f89b	1	0	\\x000000010000000000800003d1d6a1e4f2cf02bf6c58ae32fdb1bb1fa7e179f93b20596e679551b268d4911556ae5d3971ccdac82fe1a592529879a0dc74e33d9dcd9d03168f72f1622dabd459e37f8c1d418bad3526d98cdf21d0a933d9381cd8df713e7a5ace58d78ca8368f54f837e8363972b01d86c5cbf8ecbe1b259ed24a5aad912efb1c3700bc1845010001	\\x76a1c0ac11deedc6b2525c6822f98b722ec20366182ba12f38a2e50b5850a0ac2b0fffde6ec7cde97d43a697bc8019f6c639d64994bb43a82e5ed2cb2620e20d	1669046890000000	1669651690000000	1732723690000000	1827331690000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
139	\\x48edc7f0df727aca134c6eec4d604090abea09e1e67d800099bf69d8e2f04c46172e0f2232e94881bffce2e1e52bcddf3a26c56e5cc2ccb695a1a3fcf1b0d464	1	0	\\x000000010000000000800003b48df92a36bcedfdc094c9451c60c9b121e5453f8f30b6f9b1c91603573a77cc766ea37184641765ea6dd9c030812264f349b13b391e94abf05054a26b540a2c5e8e02149ab5d4ec240538413c166effaa0b9098b8a4b684d2187d95a10e905c6cdcc82edc839c0e44770504998b74c3ba33b42bf5145ae47e1cccec9bf3e15f010001	\\x6b9e77b3f294ff8b0c80f5adff7b6a24296a1fb47290a8dfafc0a90403e0994bbc8c7226718f25307c8662427115482ea9dd10c4c524bbb0c7a35e4bf5c19b00	1672673890000000	1673278690000000	1736350690000000	1830958690000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
140	\\x4d218fcb275243db25bdd8c95e327dfbffc47e191ea84b400250a37743b6f26e3e613c184b114b092544e868ffafcd334551d84ec79cde4b5048120a83df1e99	1	0	\\x000000010000000000800003a9c641fd5be9c64d723b65883ff8e480eb395c765c81c7fa282bbf66cbc1f22a9d76a3916b4491dc4201f86409771a61f6f4bfa2b184d24dc1b8e24e75b29a265bc0db45aac83c8f9146cf8bf0973e11056ac96cdb68d5b384ce85cb8039176ca4c5ff96ba5b2e08fe7ab25028615a0d81d2c8097f12c63b4be03d15b89ad695010001	\\x2e3293f0cf3147d71877366bc95922e01a63f551d0186ab34966b871d3ef688930aaeee845b12eb2e745a52e755b44e585a35208f85acd0360abad328ff6d80c	1654538890000000	1655143690000000	1718215690000000	1812823690000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
141	\\x4e39b54a5f63185169d61ec41417c9aa7ca68c3f613c74bf3fab36e43f536cba6f0dc018aef79ce2b1af6666b02499d7da2ba4aa21af974eee77560e589e4f4e	1	0	\\x000000010000000000800003b2e431c95c45bdb597d4f5362d7300a7feab5a81dd18915614bd6509e950a8e3167361dac8003425428afd8431e6d8e90cc25680eac99c0276de71d6d4b18413713a9da8dd4f6c6f8b251b075bb45837687691b93172c61262f1d1d8adba337decc790f776f3c9b55860307181e0ecff39f0a9b33688ae3b38d66614ade7ba2b010001	\\xa00a1eac54d3010d6b2ba7ecff6e816f2b0aefd8319793ef3796bc4115284a74f60f2362325a285f30f19520bd5f7b35f12b3bb6b0f49f55565510e68a4caf09	1653329890000000	1653934690000000	1717006690000000	1811614690000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
142	\\x4ef13b581ce1ffb25c039026dcfd2cc345178ba7a0a2a6194c6727d8d643220438adef36a4f3bf6427c0e9962ee2f4dc86a67c5cd3a062a26d8a310bbe0e6508	1	0	\\x000000010000000000800003bfc5b46854e6994ff61d9a7c51652bf7b24d7527e2457d4f351d819a1d57d17f9cacb4c7d91e48c0aa2217a21b4587cf82191068f8a711604e87edcade5695fdd5c35819a12652dba6483ec3aabdd4d09b55e407fc0d74dec1c3f22ccd4df80086821ec1791e7e0302d2d3c2a1e9507edb65ffc229beeb076b83c36dcea7a497010001	\\xe6a14a35bf4dfdf5c2c13cbae1a5c4532d96718bbb4bc5e834087f68bc6bba2cc989fa04eccc733f1a4709c767a50ae736807dca99d901562fff350b18a99706	1664210890000000	1664815690000000	1727887690000000	1822495690000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
143	\\x50c9854b5ef87cec847cc8489593bb931bda4f6e3693aeeac203d68dbe4202336b5a8717570ead6b6ef01897b8f36b618686a6f5fefa2c5222c92bd1fe85f95f	1	0	\\x000000010000000000800003a1732cc6a3ab85e3d640921bc0edd35fd2afa4b06876be8bfb0031748bd36d9a740f90597a5bd1f1842376e547ce9e175938aca5fd8569529965c0011b91b87893572149217e34daebd6fbb6d1da4ae2c35c48714fe62ffa5fa493ec0ffd8b8f6008edae6c9dcadfcd0d44e2a02f18c851cc4e648c7d6a4e3970f3f64c79e451010001	\\xbef71031ce2016b37c97b25ad1e1df17e3e31cc0bfb0e66ae154d4b6bdcb983db6c4dc9590b164e95a92ccae3fe93d209916e5d6875df48b8edbbd0d4349f00d	1656956890000000	1657561690000000	1720633690000000	1815241690000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
144	\\x503926c631cba6973f836869320d79cd1002501b39e6aaa402f0837d5ac3cf8ecb1dddf76a287de49e173d42694f051fd6e6583eb8b15316f18a6e6691c621a8	1	0	\\x000000010000000000800003ca8c258f8818cb1cbbd4ed6cb6c69063713fc20326898062c706f2fb26e4a0793685887812a2735ee18df983109516ba36287bcd3b242cde3812a728b1746911d1c5121f0bdb81778aa24b9932becd6f2046163e0884ddeea3ddfc6c82bc5a75d6d987281f8b4339f1cba28dfc299d9658941c924fc5933ebce74d7d352f8ebd010001	\\x9b350a5cd2cd6c6b10ed288da168dcf0ec19632b198e112dd4e46edfc30b79f06264a3852c4b4b08d47cbc5f35b9ad1856ce642f0fb0d2c43e38b5c232604207	1670255890000000	1670860690000000	1733932690000000	1828540690000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
145	\\x522981b4d7dbfa2b84ee28db128a6808738391471e54e00558f144f452ecfef9e88196f3166e8122b0684d934a0f319bd7616d68ece5d36ea04ff233f41d60df	1	0	\\x000000010000000000800003f124e57974d8d6c1bf16abfc0ec97cde68ac3f6543f276b4ba7654775671f858bee470dc9162660b11f5176d47cf4d567cf3588511a846ef9e4558527afda13e0b67e35c47b47cfbb4f3fbfbccaef3881cc0537e711f8e070c983e0212091d8d40600deb8d19d83f2a02c3fe29e3c92abfa8e8b226856496c12d39f932f50c49010001	\\xdecb7e485c72d5189943f1d3b83c8b7ea282c8a62e54706cb11015d9e3f9f2bdc748d10532d6a2d8239fac994432cb0bd8b6e384debbeaf1bd5257f519187507	1661792890000000	1662397690000000	1725469690000000	1820077690000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
146	\\x5429a1d02bb438646ce1353cb9c0953889b4b30582c72dd97b12c27d6dab633f7812c9a2eacdee725577e8f65af16e60a6019f1e30f88206d498865f7b3f5076	1	0	\\x000000010000000000800003af0b77be98f5d53864f6728d7b1ef1e4440d6e76ed7ea4d12db1f2998cf47873b474d23c4b7b7412b1f90028306d47772ba99047f49d4cfcbffa33cf266f2abd26359d591778d6361e7d5c30f187709cd8055794f0e0bd380a37385befb9b925cee88de404f8efdaf4729ba5285520fd7af00cc3e6f44b691eda689bbc6a7a99010001	\\xd29310d526bbc622e0a9274711363a9fa3ee5322b741d84dc8b4611dfd169ee1b595889dfeeae1ece9dff64c0d146e97e6654faededade8074c1808856d39f04	1675091890000000	1675696690000000	1738768690000000	1833376690000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
147	\\x586119b77bf656768932c7cda08caaf154dca33280167918879c9935567402b0d2b320c89c55ed351e98db94165a98db98aed771a2d4becdf92335ac268bd20d	1	0	\\x000000010000000000800003be731f63a335a7856dbf6ea68f3d0091af766be7e193c79595d2e8f906c4ad9eb218bfc7c5a6047963be00823bd32cc9ce637b0bdaf51109c28c15bac34694ab341ce4755423bb643f3b876243b3fbd6c4d86d34d2f7ef5f4c71509dc0f1993c61a2ce7dedc1178c71a637f7d3301239d9651b2cf9b4ee798ddad228019d922d010001	\\x597c5695748073ce7eae45e7079f6571666e81861bfb1668f529c9ad5e5b0eb21461d7999275ea8184717dc4371caa6fe0d6e44cb90ef0869b60e5e4530d680a	1665419890000000	1666024690000000	1729096690000000	1823704690000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
148	\\x5a696df6556da5eea34fc23410e952b01b826c2d150cd0f9b1a539fc77b46eebeda7762738110a3053989270f262121ea94d04ccec07864c069d0d53444fb0b6	1	0	\\x000000010000000000800003a764061e797ff17c88ff647fc217ec795ca64f2e5267dabb2bb4c83cb28895214f8484939ab21ff0878a61e28ede57489d6b784f283c6a3dd7bd3bd615c7deeb240eb7ffbb55a6404d81c9bd1a7dc008db550ea7d218b3e484e9fab67d22f7da4eb3196c0015d46e4de7c780e15cef75a0e5b8806058e82a43d51aabf21c24dd010001	\\x27bbc44b27c53d9be0e648341608ba85c3b3009815fc510cf0471bf66109b6d266fc3a39c4c72bd6fdb0d833803bdb333cb7df07499476db4a404d5e7bf20a0c	1661188390000000	1661793190000000	1724865190000000	1819473190000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
149	\\x5a3968c8705d3042f8e0c0a6af6c78ce845767e2c5118d8da200671c1a9ac67ccaddaa55173dec0c9c9d18f4055856ee7c45eb72831e96ead1046ab6ccff408d	1	0	\\x000000010000000000800003eb9c917dbb33cc2a7996f9133393e6b9f7abcbdc5f26a939473fcbaa0ba53df83e1e7017a686cc2b123a14d3cfe9f613a78a0909c873dcd26258c1ff8557a158b7680130ba00e5a04b0b5adc6d668d2c3aea9e64a1d387104f886824aed90088a21372810779dc89a10809197d9abfba1ea2aca9080ace89a37fec5e3d6f3a75010001	\\x89d48c491904c82e06e5c1ad26b0bb1500e9d7008ca23f131bac9ccf292cf9f26a9fe6b18ca2a9e39a30cedbe560e0c0b7b878425cf700055d45d84d03c22b0f	1673278390000000	1673883190000000	1736955190000000	1831563190000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
150	\\x5fe1f37dc3734fcaa6fc4e8a15ec65e2de2966202f28587d8e94d5b9790a57ecc1c5da7e0b79e74748dc6442ab5d3a8b88cebce66942a9e71e65828d02d989b4	1	0	\\x000000010000000000800003d1e18b0eb0ee39f83763f9f47bbb21d5f526cbe271fb0640d78acab72ac845e745104573b8063c0dfb2d7e30c520fb36f5f6c2d9aa57215fe8c09d3cd118512d1255214d4d284d21c37ad45ddd57a913f16458c4ff3cbafef67607f3ed360be910e6c13b01a23493d64f4b7b68f1c0a4fe3563d70a36e279b8f6aff819491619010001	\\xf6dc4883be106249789feddac18347b57c647ebd7defced59ea90feb1faab8695932392dde0e736feb50e0ec0057ea083276becc72e46c0dc4b3ea6fe52aa407	1673278390000000	1673883190000000	1736955190000000	1831563190000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
151	\\x6191405ae21df846f7dff380bdc28baca1380de5008f14060af00b5f6e20ca48323971180ea0ea7ded573f4709078a60c87e9e657ff1d3c4346a6e30af0f2240	1	0	\\x000000010000000000800003cfcd87b780f3952f72125b102827fce268fc9358899acaa0da32f69b692e1116e8993b1c916ff64c63478e495487ea9d756d313205ff03d3d775d7949b5aab2459882dcd34f7361ce5e20812f9f8052839119ea3f3f81acecad81a36e2aee73370daea1a6367ad446f507c43f9b3202b0645f5659e2155029b7e9c7cfb76c545010001	\\xce68025a379d828743fa2790ef3733be41c07991c32f414aeeade141a1d954146cb46a236af8b2c6bf879a4a0254709ce48f1dab16afcdec0c60117232daeb04	1675696390000000	1676301190000000	1739373190000000	1833981190000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
152	\\x62a51f04c730929565ec24c9129a87b7beaba8c991bb2c996383325e6deeaae92a7281bef1506620756e811cc86a6d264539d10760a355b9fbf8944c1df705a1	1	0	\\x0000000100000000008000039adecb706e46c246bb28e86ebac0673424fa13a45508c314cd78dd9c9ea38cc39e487a01782835bb66023b1126d116d9e6bef7d426e04c1941c98847a51ba9ef3e4e282533c6a7e363fd50219459d192b8f0599ae0251fb7d89931538d969a171e17315014f256a538b570317ff06c2059778b1af67328d8a691cbcab1e77df9010001	\\x8b63cc015be3f940e7c9c9783c8053442e9da4ca16200c6a73af22a76b9e30df8d129b8b1cfaeac139bf90828379caaa1086362c29aa508ca60a7a2ad4de8c04	1651516390000000	1652121190000000	1715193190000000	1809801190000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
153	\\x6635cf103908fbbb5e62b2c8b352d468702901504de2c1f4ea8a527b5b2f09ca3f03d4e781c71d1b23ffcb26416ed1d65fe25abd49b554860e0138b0ef8e7f2b	1	0	\\x000000010000000000800003bf72642c6bea71744087b3e295eefc433e8fd188a53662d47a14f5d675a111e99dbf34dee2cdb6e1db23302e579eaf28cbdb3d60b87e52de8d1adfb9d22ca60dc5ea18c5350457b67821c01bc854b3db6f9cf9f85e40e257e77e7e27498dae346603663f67a4c220488ddb1ab429e01a51846c3cb1ab1839b6e555906a1a6e41010001	\\xfac21dee67cfc7767992d2d3e77a6aaa14c7e17d2e830bfe784d149966cc04dd795dbc25d35a4a979a2e8ac9c98d62aa0293ca2880c275cdec77680f2e71350f	1673278390000000	1673883190000000	1736955190000000	1831563190000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
154	\\x687d710c04401577412ae894e3bd3944496347126de943657303b1522a757a2e07787d86d27cfb6eb8f5c753fe3de990459099b1653a3d2db57eab813f04f57a	1	0	\\x000000010000000000800003cf8ba00e327c6f5d151b31192e90985d8c20d812636959089f0a1f4c2cb4517ee1406eb584c19b2b793da94ba19679e3e2a68b1a74b29606d1ed03cde1585c1f5da95da82a794a8d54a47fbf247a690abd109dba18dce741d5e75edeba67595aeb6bc62bc1cd3c651ded9dd57ecdc7609dbed11fc6c8e9c7a098537dfcea3003010001	\\x52633e53828e01445a53f61835b0a450872bdb2485bbf33687da9f88fa5d4fd2640570d5568b0e4b1f445047fda13398a8e0b835dafc3fff81aa2493800de20c	1679927890000000	1680532690000000	1743604690000000	1838212690000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
155	\\x68c502ccf662081c6bbcf330bb5d641a6219ed03f464032f3f7daacd6d946f0e65987b561eb24a8c2d847bef6d2fcc10f5f60d9b6a343bd1e29ad620e7cf38ba	1	0	\\x000000010000000000800003b094d1ef15609fe9892391e21cc317fe3e354e1c8c56fad401ff2c19007a20c71ec1712824e8367f86f6c04a4be219935a6d4b5435a7368624d14587be1cfb03bb0554430a255a7e5ec78e8d5eb679cd47ae3fd4c583e2acb80d45cf72271285ecede0ee762e2698e32d3b4fb54346467d7b4eee50c50fceb4a97050c48382e7010001	\\xabd0452e6e1477aa15a33d29caa7636a509cf3b9f6ffea7a6241e8444a0fc3b0dca6c3b58714920b9f253f4817e2c7fadde3483b2307eaa74820c5ec6171d404	1662397390000000	1663002190000000	1726074190000000	1820682190000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
156	\\x6b355a720471c650eac9cea55a7598329f46585ac0352a736ae9d713d6b0fbaf61a45abf62ad4868d660a372d88b49e9cc4f8b2651fc6ec8c78e60534fd34eb6	1	0	\\x000000010000000000800003dc2ebd20c4daaf18b63e045d21270c0dc251fb725429ba40eedc5238dfe40ee880ae3cc21d4054221b279f690608ebb22f9e5d0803f3adc7a54885ed3dddd992193d67f43c4ea994cae4d180a42cb51940008ccf43bee0eb08486cd901dbde7afa808d0af60f817ad3bf8c9c3d4fbff852d822532ab9f8b54d704e4497e1c073010001	\\x4b8e8ec51755e777faebb1a1b09d523839d04fa4db44d44d11a8a8f6b5f97a7bddffdcdc2a5fed3501e8bb3a31da7614606aa360a464c5f3ceecbf51a6739303	1661792890000000	1662397690000000	1725469690000000	1820077690000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
157	\\x6b9554c124cfbcf5e812259ba7a9830068f2538e443bbbf4fdde444efa77b6306453d0ffabc235c5d351a76d0372ec70ab8867408d8e3025c7cc63d1ada2fda0	1	0	\\x000000010000000000800003b2b374f9510c40ab45b0aa6ef0ef89f4cd129b1eed0fc9e1e970fac61662b15bf577fcb698f19bf6a33eb3e12e591986eb40fea9ea59c00a0d67c180de8684a16b6a55f78e944a47cf421e448a5e7c8f0ae0751c1324581e084ff32645e69eae40a8d551ed35a0f127a9717ba7e1d3bfb1dddf31c22144a595bb951faccf4a3d010001	\\x3ea5c816a6efb62db2ee9a3521e61bb50a6243bbb8a5a9ffd6831f9280817edb860d2892d7b587207bf9e3938e7c490cf8ec39ae0c38e281d6360d23784fd90b	1655143390000000	1655748190000000	1718820190000000	1813428190000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
158	\\x6eb1a3de7c191af210415259ccdddd4d65c0e4c8ed8e2c66ef80b3c6a0b5e1b758f2b90245881e32fb4f53b7b01cfc51c6e5520ba30013a74b325c853c4fef1d	1	0	\\x000000010000000000800003b84bd60cd5a846ebd0ee5549df468839cd086f022212a20c20bfaaaa6c5ce3ed4c806e028779b27863f7c9a5830826d71f3e048461f433fef321a72d1f1c85bce77efe59956c67df7298d1ef055e32d7dd77c6a0c4f5a1013afd533518a47da8e5c8f817378d73e8acf9fda029e914dd701a97ff1a98b6bad8e0b3fdfa31e091010001	\\x373e84492b87f68a1977c3bee6eecaa16c0cb1983c5ec4c34976f5e83d8e6af84d6fcc6eb6772116bff084a44aea08a376f00c357b82a23dac2011faeab9db06	1680532390000000	1681137190000000	1744209190000000	1838817190000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
159	\\x6ed95bf5f84a72c23833d6dd9608bed181e9ee8aa9aa137fd16ef90979d7b94dab6b3bb4459fc08e1e9e8a555de60ad6089b719f846558cdb722946459a21af4	1	0	\\x000000010000000000800003bac24394d0c9f1503449bb50dab05430b9dc80d139b7f5332a2ce1e8bac675eeb9effcad4002192096693b66e19b5d745682ec1d354a6b8f0ae1292e7f671cc039700fa110527ee3d0b825bbe20edb3f42c0345c89d3970f9f28bf43462b18a72f3868119c9034eb216f6be06a00cfdfb7364d93c5c4dbe0a45ea062056e13ed010001	\\xb244b254939998064ac2549ed552e8be4d16d9979f69eeb635c182638025898d28cdfa9c87e62c255ee0e76e3f57869e8cd1114fb3186e7a41472bf2a7237607	1676300890000000	1676905690000000	1739977690000000	1834585690000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
160	\\x6f3da2446085b5c23c4c6c4854b65ec61318d4e4371496d94b57688f36323bfeb60c09f4c6da4fc65fc8cfe30de5197ad5d5299d70de131601e4f51157d14c08	1	0	\\x000000010000000000800003ce85679764d5d74e86624676804f5c3bf8cb5508fa7c4839be5c259cc8374cf1b518940545a1810e7ab663a309e2173580ca75d914d0e116394540b9d3cad7bed494268966ebdfc21cf9a582974ce6820533fd908b9ccb2d8bdd10c80f639c88a28e149e87b20997c3ca9652c297f7efd7d5d17d21688b524adfce41e61f4fe9010001	\\xeb64145cd3c79f5cfac072328db8a4c10a1a150dac53ef3d5d858960c5e548801a873e4c42747694b5c0c9ef213fd6a32f0137764427b1ee58391079a4924f02	1670860390000000	1671465190000000	1734537190000000	1829145190000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
161	\\x7361f7ad77237ee7900b2c21fd3aaf6f7a505a48c6cd57770fb69579d2208a526108fcdb2367f8f03d23c62c494bcb38a440cb27fae5ba62074c75541e60b1ce	1	0	\\x000000010000000000800003e4b1a1e4923ac2f318ae321f3a651730fdca9505103974431ccc7f6a205f733353d3fd92459fe5f6e4de1b72bc79c689fc154065b3371f3a5f215e4a98ad0840764094a188d206a60ec941606a808ea417e0277c618726573369092de7160a38d1a5f2fa2b146aad780eb78914c7a079e7ee1439f8d1a35ea036ae6815dec15d010001	\\xfb8489dd6369f4c1cbc7866b774fd0b742abb4dd96d1c85470b0a59618896c9c76c1a2393ee39e6b9fc9cf3102f23865b4ba4546da7112c66bc1d10d9f774d00	1653329890000000	1653934690000000	1717006690000000	1811614690000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
162	\\x74cd75482418128da48bfb5cf58eb8b8394c9abb29d45229d5bee859844b146f732926f5d3ddd7ad08f940d049381a001570601e4cd2eb7f47e3ae9b8684d78c	1	0	\\x000000010000000000800003ab44e3d160cb2f39a145f9cf5b4a7b67ff7e3e3ebb5531ab47086f5c651a839f83491674b14017cf8fa3bbfceadd2354a8e2f16ea7d4e9aebeb65c3a46d540f5d12bc00dbd43313e25fe8940b94d9c6ba81ed7ff13845028964bc4b7545470e2a015bc9b82c040be34ed7bc320d32ffd07d5ca02f975dc96f8296d5db04033bb010001	\\x7bf1f8a2b4a1cf74649e1f24796bb8d5fc286eb94c7c9559e04e81db8810b1c906dcc024e8edcf92f9cbe0a3cadfeaa1f5fb99cfdefa3564c1fa04027c9bff0c	1675091890000000	1675696690000000	1738768690000000	1833376690000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
163	\\x7919570a5829dc8706b93188d639c871d7daa5f0adc0cfedad7eada9eb2fdfffb18902eff6d2c23a6c7634fdee77e0c3aeabffa4e9ac50521a0030a2e5705b39	1	0	\\x000000010000000000800003d4384d52762ac9a7c3b047825a92be76f3abdfe9daaf75414db1d3c7be77a0498c36e798eaf74d3da75118082b192053bd32c2684c9d9673884e10a738dab012a19b44f68387bf1a3216b33dbd9dd4f758fd4a8222be1ed4bba5a9e335e75491d2fa596f99ac230a89d6afaff48121f6c758fe2294daa8f6c0ea036b0e1e4111010001	\\x45fb039d2996d8543aac3234e2d19a4d7dceca353ae71ba8d0019eccaf79b48cf55e5d167847029fed091f6a505fccc64691d476392558818387defb54f7ed0d	1675091890000000	1675696690000000	1738768690000000	1833376690000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
164	\\x7b1d03ccc9cf362e9602e5a4bbdd7cb4f31e0cdb68bccf52f29347d6cf6213af99eb2c5a86dce2c01004a7c600f317f41fcf7fa639c5c66f48f321871e538f29	1	0	\\x000000010000000000800003c8aa2ec4faa0061460c70cc2041ee57a4a1032886884eec66f346c0a97413753d89c6fc3f0cda290a31bd29698410e4ae992e897d044c930c1c5006317bc4330075433437c384c8bdf87c07eab5a33620f07fd2fa9773ea2995d6910308d367f4b1ce0ea772a0073210a384cede2af31cc14f67842f57ce8a5f46d77211febf3010001	\\xd0bf79299ff8f83959bd8abae3171cdcc303be20ce253cf573badbe97d74f83c6a012cf44979994b85f7559465a31b229212a588f62c68ee5c123039a3c1b10f	1659979390000000	1660584190000000	1723656190000000	1818264190000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
165	\\x7b8dec626935fd3e8eb509f3cf613b6c4eb0af168b0275e286d23c1e804e07c66c59f1be4d77914950ebbe53b52ec67e9a7ef72892b2c8d18ae314fcc86663be	1	0	\\x000000010000000000800003ce7ecb7d2efd629c1331783fa547746006aa2ebc784373d3c693345db60baa0251d8ac44bd89ccfaf3e72d234e10ed62eb1f9096d2a04caceea7ea3f36b09b1fc5aba603e494a46d8464781143d3be2de7c79a881e1ce0470ea806e9071d1dac59c406f59c3e0cfd51a6aef34fd8dfb683abbcc069b84402f03cf643a397aa1b010001	\\x43b7802128d58ec63e7947681223de83172e7aadfac4597200249c2fefe8c5c2633e92ddf7f8b919f32ca59b51173162a6bcb738967785cf943396ab76aa1906	1665419890000000	1666024690000000	1729096690000000	1823704690000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
166	\\x7cad359dc2abe2d27cc35ff8e6fedb725daea684f8029460412f2e7791a6e5e2cce6935ceb3d63cd399d7cfd60016f43328ef0e6c2cc27f0754f871469da5966	1	0	\\x000000010000000000800003e91bde5e5376459c212d5c9554363f05df76b6ee94237de1a4289aec35c875bf4a2852f7cfbdad980f2faa65ddb57ec27be25f78e1738471a460da90905479d6545f6a750482f1dc8d65ec725c15a57166e87146f9aa505d2b4444b21ce51129f993a8227139ee8e9c97330a38ed00688aa443b498e48b0e53d7ac6ac543ebbb010001	\\xc71b7f68e4f009b612d273933b1d59d9c5571427548094e7a5289fe85d0c40feaa15626c02532dd1467740c9cde6c971de1b333ade99b78c5f7b738eab1fbb06	1663001890000000	1663606690000000	1726678690000000	1821286690000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
167	\\x7ead6592a6a4bc22958e180d3433533e62df75c7bbc750887a48f1c507f47536ad883ba79eff262b775ce2ac1920310cf293d688861326a0e518e6eb1b876a19	1	0	\\x000000010000000000800003bf6e22b372cdb05031fcd489e8bbbed857e054e23156419a06922064aaaa6352f4d38556beb2af1a12678f827a67ee0d9017847409cb28170cf921479d699f9de033890b7318b2e3d4c3873d799e89ba0d89fe6796614dba4d515e13fd107a5c28c1c576a68fb5b8a23976975fdc6d6935e9bbb83c6e29945ac1a8eb3aa657cf010001	\\x3edc806b30efa36caedccd245afb7941c712c109ef4d5ccd924b0cde2893ba5535a6015992bceeb88f93860b7417c86e8afffa7f945aa6fb87951e09c0d34305	1666024390000000	1666629190000000	1729701190000000	1824309190000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
168	\\x7ff9a221f3233649876a9f028fcb3578c111449e8e4a45499e741daa8a6328a6d02d7788f5d04d81ff095aa7b2a3bc1427d3ac32b74ded595c726ed114fa5460	1	0	\\x000000010000000000800003e5dcd0a4bfec9eb4289016c836e1d77679eeb70056363b4b9e056db5a14c9526cdb744d75e7eb21aafcc21b079621383cbe8fd9d811529206f0f51f7f5239ea7b510efc7cdc51c1c0c68ea150723847cc0912a85996b395a6e5cd92b8e2718c32fd5635c1ba60b8606ba1c93be0275fe892961db244543796c0e8b118dfd277d010001	\\x7cafd2e86923ffdaceb08aab023342f1e57593638d19a1932c3c478a88cff5d94297eb63fac3d09f9036acafc8c71dc7f8a06f19d5f845a24da291fcd8a86f07	1658770390000000	1659375190000000	1722447190000000	1817055190000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
169	\\x80b52e0c17b6e9e7afee59d42861868b7da94cb6d296ec4bd83b904a4322e65a3c06a302641472dec9a748a524f72556086da30e988cbf71480c616b6bcf365b	1	0	\\x000000010000000000800003a9ab52ba6babd88f5aad42b46d78a7d66a5217143e095fa163780e95611322d89a11713f17cf7b5cc5e430a3f1d4863d4d47497e27389739a1ad9af063c974e07210aad7eef3939c1e2c73748b9a9581161ff2639253bbbd1d1b1877ebdce4e0e276053a13a7f8d42faeec8f10cfe05e81a4b56d4d264e99e72a43f6c92346bb010001	\\x6286fcd25e378858c1407aad840d039cdaab7d2b542e4a408d9a779556f84c8088fefb02312511ca41a68dda7c7f3f91c5b173789d71b21d5f93d9226125b30c	1679323390000000	1679928190000000	1743000190000000	1837608190000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
170	\\x8025fc8a1f3e7fa7d0032fc6145c7d69dbe283dc8fbcbf3d74b4ef0c4af61107f565cafc052567afd17485f679c49d774dd6a93b357a1fcc723ffd5f51b9fa88	1	0	\\x000000010000000000800003ce40d8bea51a63cc9834f85aa6d40c1905507d829fbb53f5eb76f2069ad28e93d625a300799d43adb56af62804b3fe0309dddb2f31f811abe06fdfc4071fd75c6a4cbc747dba351289a45e6cbd60c540f05eff656475683cb338e59566f6c063cbcd931891abbc544de6773fef7bfc29d472a9d76c17e2b20c33de3ca12bf381010001	\\x6da06584b8e1a98a85c005774a3ea55ad167a005477bd940347c23f6a3e71af7146dcdd4d5be30add3e97cadcf2c381eb78c9753832a8c45bb66fb7570ddd203	1682950390000000	1683555190000000	1746627190000000	1841235190000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
171	\\x830d712af43417276b9b0fb079941f644482bc3de4dbc632ba5300b1b9049905cdcf1f6c8dfefd60d9874da9aac0071252a91953201e02e5438a476347b77c3d	1	0	\\x000000010000000000800003ae3a2bc52a38a51d6abce41aa82c1b7ea4830abcb21b9ccaa008fa11fbd6954a75f6120c9d47fa5b53da85773eb2dc29f4fbdf68a55133d2dd38fa4eeee59249ee993fa2b1d0196debe43ae449896700b55266e61d0160869618c2c9c878621d0835d43e6e666ece0612786bb6daeb6422b8db99937c4a30ab71d5080b4b8b8b010001	\\x42331c12921b09cd870c518dff05cc7ea341b296ec28f5d1eb810f87d5ef3e407945c3bf1c8af7337efba6b8c77df50cab6c6482906734f4d84e169fd5492f02	1671464890000000	1672069690000000	1735141690000000	1829749690000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
172	\\x8655445d2fd6eac3e5d347f315b2a3787fcd681c909cbcce50a34e3c676b1146e64bef619c6e4d0bf95332fd4fb8710d48b695ca4106943ccb67bae6dc622e5d	1	0	\\x000000010000000000800003a1987f033883da2a3146ba189c03b8bf54fcd2a2cf68fc8d36db4e4a92f3ab4906d549eaa3237d7dced6ad48efaaa2d170612c4cdd287305fc0738beec30cc2aa9c4b51b8f85a6d83cdee3966680da50f6a76406f33eeb680bea62666ac69a3e8f112a0a576ee0469ccc8f58ebb724ddf42d9d2ba680c81e6af0170417875885010001	\\xfdf6274fd702dcfcdce52e41ded2cc691c67db4e3b45bdae807a40764142de3c43338c646a83fa10eb44edf506c894636e4c66f042ba3e6280b928c47fa2780b	1670255890000000	1670860690000000	1733932690000000	1828540690000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
173	\\x8a81d42582f302023c5ca32f7bc8864ca682c96daca7d1efca4913a76e231818b41326f7d9419427a2c33d704c07ef18db485897a790063ff580632c9f0cd840	1	0	\\x000000010000000000800003baa638a5a9a7fb313fe601f416115a40bd080e3d3188e715894102d125c39a8c257ad1f98dd66ada10ac5dbaeb2300812f29f7830580559af604e27d9d520ef0e9244d97b584481d4f14a7c057b6ffae073f9aa3877a470303bffb98912e809b323a0d0779a3f906eda4abdead466d9516ae6f165208a5c523da2f184750c79d010001	\\x0b991ffa48d7ca5b548f7808fee12a1cf4917f82bb9d496f24266b0703fc7b98d14de7c4ab1a1c94230398b23ba720978d666789ad8f4b4841e0eff1006fc002	1681136890000000	1681741690000000	1744813690000000	1839421690000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
174	\\x8c69618275c73c0512ca844e308b24c9d7130a884b96a5d13da5100f44c70904109dbaf16a4a6ecaaa42c0fbd343751ae31d767b02758b65da0bbf19bb3cca34	1	0	\\x000000010000000000800003bbf793bd7b8d6cc658a01551c525ab7acc0daae405f011b4b6e5a47e606e117b65320a04553816b0a667f77b74b04958406e011382c7e36578aef72f22ad9f2df3e3285d453f51f57a4685da47dc096625e94dfc22d5f91041f82fe8aaf8e3925512d1e808a05bdf9a06ae9af43b48ebe9821795f940e3a61a7645ede1810221010001	\\x65633b09dd5f0123b86b234d9d1ce4c7545a975ca5ae70f3051212adbfac9c868d5fba99facf93df8b229c621ae4d11540a5797c92dbee77510e1c8de742aa0a	1678718890000000	1679323690000000	1742395690000000	1837003690000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
175	\\x8d85512fc573ebf8430167f74a29756d6aa50379d587336f439a7e42e3b361646e72eec485116952dc6b0391093bb06c76a7ce4b5f57cf77275fb25b804022ad	1	0	\\x000000010000000000800003be5ba18f9bab90b6ffb71a74bde12da2aa7ce5f8d1b5ef17276bdbbdd3b8fabdafbcf2435338aa480ab0d245c310f0eff9f11685dcd3112b0f74d3e91b2e3efc711931e780ed2b41acd60470c01f262d2571b038b1fba199d0edba4e639a241526d7b81772e8bfc1706a581278e186bcd539b9651039656fe51f9e5c8a9d3a89010001	\\xb40de38782efdf6754eb767590e97066a371c8d9a436d8cecda829963c23712bb2c5eeb2f8eb86c94ce4a79e5848423115f5c18a4e529cde20673c207693c409	1676905390000000	1677510190000000	1740582190000000	1835190190000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
176	\\x8e69f5822a980c2eb392f3a6a47baf16751fabafc250daac131954a4b680948296836988e24be00c0ebbe6d47687a426f39e0c68c9bc4eb51a6658ddafe0cfef	1	0	\\x000000010000000000800003bb5bc5cc959f0935d32060e09d5e8937ea72f7badfbea9a20340e764b2f3fa2fc0db7d238d4eb042a01444682599d454e9fc0d3179263ced391fcf2ce4f7a318a03be77e0fde62061eb0d77bcc34e621217bca30757354c3dc32a7af126ae83b5652b85781d2b4e85c681cb434b41bdcadbb60c47df47bda473b90af7c27e405010001	\\xe2e65e21c5a65788e37722990dc8069b631c69098209381727fb239b7f1af170fb0773d81ca6b0ea02961c5c0e273028bed17efb4d164ccb01b5a3d8e54baa07	1659374890000000	1659979690000000	1723051690000000	1817659690000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
177	\\x93ed89598f9478486be48a30401bba668996651581bbacbbf3970de39d77144290690492bbda6b25a2178bc93208418baa5b051e02a118a15c0beb9c491d8294	1	0	\\x000000010000000000800003c08a461763c608300610f05131944945ab95ab44939123ac057b9af8f4261127cb4e9439b9f044ecf4a651e7505dd83dd052df1b19b428de177cb50bdacc81f12d8859ab41803348340520dedebc7179d08cf8528ffb5305dc69079cb0037cc90a58c5d6463fb4171db28daf91ad5bd052d42123721bce8048d84056040b599f010001	\\x6ca9f075a9659f4cf99164fdaabdd35c02c854905e820013b3b78e40f5d6940820f2143e7605935d25f6988836a1ca33cb6bee537dbadffcf93ae12261a63a0d	1665419890000000	1666024690000000	1729096690000000	1823704690000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
178	\\x96210d046d3c1cc8024813a9b60311b99fbd7166b37c9d6bf9c4377b88ae34e7cecf5903a19964260df9427d7d4e18899aaeea4e709116a150ecb3cb8a878325	1	0	\\x000000010000000000800003a9fd7a2879c5a22ddfdbfc50758b47b4191135195d9438bfd4f8abed9d216de71fb0bd74ff8c2ddee934bfbb7d3086c2d21f5eb87e79af8620125137bf6bb7572e941abe17a45a4acb93d3dfbfb6703fcf6ee179411dffd5fb856f92ad83f8db697a84cad2e0f5995dad76883e6bea34329a402eac5b5996cd65acb3b58f4b8d010001	\\x12333046364f71fc225fa4ba7d93578163ed6bbdd7776965837991695ab584c7e6129e5a0652174535473fd2e6c07c3d45e3e048770cb8a1671216d8f5c87909	1680532390000000	1681137190000000	1744209190000000	1838817190000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
179	\\x9bbd84ed51955db2b91d278bd762116f294a7dfd6cb9f3de4911632d73618d7c495a1c1c4d9ede948cbe203bbee93031bbf602f26e82e3d54b61da818f59965c	1	0	\\x000000010000000000800003ce6a4f62e71c998c04906213f89741ad21c62275f7fe055668d5bef4ef77ccee4cec6d8fabeaf58429850068189968619b61c5c6801f0d67f13e05af5087aded6ccae7855435f3f8f3b5c455c23198c72a2111022c66754913237c05d7b3c865ce7283b500f68d751666f04db6482085e65e7b23be2a220e4b86f368cf421597010001	\\xe239d1208a484baa7fb5467844f3d2e551189e0fa6aa0961098ebbd3231b6a7d77b49a266f67406eaa6321d5d6a9bd0464212aa1a1657bd25a2ce2cc0fc4b70d	1675091890000000	1675696690000000	1738768690000000	1833376690000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
180	\\xa3b5ea0030b7a2fbad63c9cd1831baa34abf5acee8cee93081d7913fbebc5df1f2704395bc5c02e21e89a225fd30a142925675d71ab23abcf4a5254c09e2ef92	1	0	\\x000000010000000000800003e70060917ef227fabbc8bcb73eb6e697b51563df7e891a770b9d0e04d30a1fb989d8f36e8c7f5d793a9c4833a14c660c9171b03a96d88f99f646b61a1bd7d07ad0592793fe61a9c6b33fc0913ab3ce5b8f19f6653b73f7ee956b480f349b54973d0aee9c4bcd8c8468afa4266bece42186b030ee564e653867dd33206b5451db010001	\\x6f719f784ea6de2e3955225de7adadbf6310fb4ca4d418642a73715764bbc02996e6ebd52ab55eb429591a9b42d455451db8ed0f96937d531b05b46f0a63db0a	1652725390000000	1653330190000000	1716402190000000	1811010190000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
181	\\xa6b9a487e842b4dd1cf6fd254fe5f5cac7835a8a12e17c577fba00133468b04926294e371efaa7fa70fcedad84d704197f721ec758742681355693ab55d137b7	1	0	\\x000000010000000000800003cf3d6a956a6f90de6aa7ad7825320ca11c0c44e3ae2bbefb23cdf35de336b5d134fe40f43db1dac2b4843b236505a90c5d837a2ab617ba6b6d78e926955fbfff26b90fff21d976bc50d70471cc246acd5c38506db046e5a052b03e2590eb59d539334b4b3feddcbedd664907c920a9001abf20f74fb4b225efe41cf066ceb8b3010001	\\x9685cba9a89ff4a103583f693a2dba030ba3fa1d7926885fd155180254f7d913f0b4d332164b6f2f1fb3a9ede779ff452774cc146011765e37422bbf39393a0d	1653934390000000	1654539190000000	1717611190000000	1812219190000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
182	\\xa8a51ac2e06b710580ecb2016bda2edfb1668e919476881389b6bb58b6298b453fe00f1f63c9365622f5e06a53950cdcb59afe767c985bd37f9c34f36510be40	1	0	\\x000000010000000000800003a414e310d526b30b361b80d29f2aabb9a967ba6ab1ff21dc91ea165a9441bdf982eeefc99353abaa1642d90f9d271bc09fa0f96a1b0983c1ae74c9668c4368857748779050f464e3149e47ef7a8ed0145221e146894c000ae04048a35d129685c0a18c999d6eaeb860503e0336e0a385563c4b4715f49eeedda6833f857f8ec5010001	\\x72766ff16124166144b92bc9cc266e53c6426f380e108457d4af2f1cf3da007ba104a589e49811e7f25e36c3047c8fbdde163156eb2e8e4e428b8b62ed526e0a	1670255890000000	1670860690000000	1733932690000000	1828540690000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
183	\\xa899aca356b77f98c819dea99114d256f3034b28a88c83037a6778033343ba30225976df82e33e925d361078859aeaa77906be7e99db3cb2ee29ced1b2f49661	1	0	\\x000000010000000000800003cf1dc61d0cb27dacbdae5f46ebc681900ca3c5f6db2fb4aec5cd8161c291015928c97834c821292dae9321eab08f0640dcefe86812b345177d4c0b584d34ab2cd3368012b85e14d4704e47c35f2125fc7c800b9059d1f695200df1cf5c3654991a01e3402960ac31714a9ba8c3f3a052087c5e416edf1183218a64a887768e47010001	\\x8b2b6ac57cded09a33fcd3e361486169a218033505dafee49cf5217123eb82edd5624ef3bebdb5e3c374339acee4d6412aa490628325516232ea126917b87603	1653329890000000	1653934690000000	1717006690000000	1811614690000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
184	\\xac519b84c0f0dacb27724936a30ef7f087031519923ac6a37a66e3cca6cec13a3457a3b19375bc3cad91ee520f453c358ea8fcf008767387739fb6e24a28e3e3	1	0	\\x000000010000000000800003da5c81d4444aafb84be9dfdc7d6804bd16e5cae54700a17a24ae934914a6bec92303424f183a00e5ce3162249a17ca2e78e6d4f9cf26b6e1b0b5d63b1e533b50ffbcfd4cfa31cae83aac2ebc4360505ab44546627fc5c64ab013500cbbbeb3bc50cd1268cc6d3bbf2c308bbf02803171b7bc17598bc4c9c9f5dc919436f76553010001	\\xcf2f0118983000c16eaa9b7e125c1db11b4bdd701a1b370b924a237d2a3a5b42a16ebf4fd4779830b02a046e86fb40577c0e12dd27ceacc5e9990a597fcb4905	1673278390000000	1673883190000000	1736955190000000	1831563190000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
185	\\xad31e829ab44a9fbfa844025af5f0aca40efd3df74586446a1e575e6243bf04c4fadbb0f614325744ddf144bbdc23861213f3f12d35c0a24d60a75b126841749	1	0	\\x000000010000000000800003ec1212a45e95360c4ea5eafa6b404909be79e69490306cde18f0779ce6ec3ef27fc24d013ccc9f05701f093225b5adcd5b27d1c3039a3d34962df4446737922b058cae83c455d6964789c95c128ef9843e6c15204f3e4ceeb7b1d8ee1a171a40677264db6a9aada1c03005114a6a4423f6d2b05e7aa74ba9fd77a4b000a68fb1010001	\\x66bd7a34fbaa61db40c94e95d7fbff0edd926910a095bafe805be328151c51024db6a0b434192599066e860b843d99a1d0330cfca375d80faa32cf7a1177980e	1656352390000000	1656957190000000	1720029190000000	1814637190000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
186	\\xadfd8ff7cbb955c4172b531f64a4d7bd342f762eccda820158ff1e2ced4898aab13162f5ef166ddb1c2d29344d2aa503a3ba46e4f1d0de6a186e2d072c6b1a03	1	0	\\x000000010000000000800003ba133ad78883068dc67ea2cb4b6fde00b56f4525602c3d99207690a19a2d917e574bc996a2e1aeccb0231820fa6864e60c25d6463135f4849db57e290e453e5a987d325bfa76cbc56a5499f8bb73e8376196175c36a09182236438e7bc4d6ce7a6e9143269a348924b6bac08e9c48ff567ec49a7b8704a405a476955ca4edbd7010001	\\x37daa68f2071b09a387cf5907961c1681008ee543c6c8baaf61e0c0da2f94915b69515b04547c9b9ca9679bb3fad0780f7ba39e6bfa28d037e5b5467bf014b04	1661188390000000	1661793190000000	1724865190000000	1819473190000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
187	\\xad1daf8e7a4d4f7b61264b9456b0668626601d2a6f9c55a4e393c6ec9824682a90299178a608c42967de21b5e38f0f28b6353acc2c2a00ec9465de1bc0eefb83	1	0	\\x000000010000000000800003b7d13b6c38dbcac80d99f1b11f19e1808720f177380d4427232c66d2451d783d0f0861dad2ed62e1e5c3dd7d79536fcaf84ce55cc92f119cab7b75ac5ed6142551c97105b608869fe3beab51795ae2917ae936e426912db4a803439d103c096f439cda22da2859ab99b2816a12168208a595ae235224e6fe0692712ac2b9fadf010001	\\xdd02c826fce08ff82b70e38e6280fac56a75c8c342c8229aeded23e133dbdc62711015f2de1f3ef3931c51de5793d5954d59764f4285a4013e8d9cad2031c30e	1660583890000000	1661188690000000	1724260690000000	1818868690000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
188	\\xb765fe0767eacadfeb44fee53031f641d30ca830ecfbd46386b2fdc1803ddc37d490b3e54ab9a3ece336a363a6f3f3ca39c0409de496f1ec74364a1b1338bb24	1	0	\\x000000010000000000800003b76441472fb97aad6806966fcf22cc61a19520cb16810480acd22c100166047436af3503364ab6da473a2d5d06a4453dc23024be8affdb1625b7faf6e9654a6b5a0c0382284e2f31f7dd12f337072310c56bc2693496b8747544858d97d2c3fa31cf5cc2a4dc8c8a95485d62f00a1d60a915185fa90f5bfd1cb4f258ce941f1d010001	\\xdc856df6a3e7a8ab111189208b202e851b93a843648ac76d16fee209e7914020aae3bee118767b215f27d82ac8eb0d8207503ec3d3d19eb06af65b2b1a0b9c00	1669651390000000	1670256190000000	1733328190000000	1827936190000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
189	\\xba25976233a477effa17e4c42c5d60db801a3dd03639f4ee9cf89a8dcad44c5e63b0302389800e7f65b6fdccadb8dd55e4bb270b0467cb2bb65d507d3f2a004d	1	0	\\x000000010000000000800003e06db897c5712fce1b591818ed8d696898b0b33390170aa50823bd06470dee1451885084da8e6cdddb35d62bde860f7cbf76bb25335963aa20ce4c4598aed801e6f2849ffb7693abfb1926655fd480c94746f99a5fd8f9802e7a166f53bd9bf0cab51a660e2f99c6a5df89985047932575cfd7e80217f77840e9389c52cf19c5010001	\\xf40a9230b86c3131f6df8c046bba5b49dd44c999d8c92376eaca36d3392f5f5b947927b35f640e514ca8867c22d9da7f05aa775680e7af82d2ae1916e935e102	1661188390000000	1661793190000000	1724865190000000	1819473190000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
190	\\xbfc965b6ef6d21a53c0993d7dcfb61a794b0304fbbf4309307b2e54f441b190ba0c8591d407cac9cdec351f34549da169e95729296ac37cb3193fbfe0d9725c6	1	0	\\x000000010000000000800003ccadd0d9f636b405ab52b6edacca2c0a81f80081c9c74afb205a9c2a22a437b3d0b8271280b64f6472839bfb4991a8f1d3532f1bb9dac5f9c1868f3fae274c970c0720e812e8540f09034ba1e6c135cda65468f96a9cbcf46ddb3ab5cc465347549a5dc3adee143430bbecb5c6f62901d96fdad51646d1d5a21a27140f2f1a27010001	\\x7b9021c53efa26b7d2be3d13e14e8b35707e531451aa09d2fa1c8094d2144ca2c47728095f6443c96a48d40cd69a6ed98d1b195f243029005deb2f63422efd0f	1680532390000000	1681137190000000	1744209190000000	1838817190000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
191	\\xc5cd07c4ac756cf075b582f7faa1563ff82cdf293ae0795ce7f1011b0dbc8d90723b517a658132a932a13c657a6685d272400f213d3d80a40bdbd97b001b90bb	1	0	\\x000000010000000000800003952541abc0435a86d1b0f1e8403d25627f38b86473bcb0c4f04612b5f7b03a9d5a9a33ce8982150ee16122ef95e8a739ec98639d0c2d15c45d7ef58d016f86fdeb8944cd8e3bdb34ce30ce687b4c48c8b70defa1dbaa3a8a74f334fdd5e0c49cb6adcb9522bf0bceba48ba62626f57a2f2f7ade3dada0b2197181a2c0d3689e3010001	\\x27b07189358639e5416762490d14e8c56a544effe8738dd07e0605464581e91e496f56ee59b62d2823b5ec7039464cc635f45f690add1fc37195c94332d93f0c	1674487390000000	1675092190000000	1738164190000000	1832772190000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
192	\\xc95903c744b7c2fb300964903d66d7839758e61cbc99a4cadd909a5868230c5f49a91b486e8ed90fc181ce33d1966fe9bffe9c45f0e365a4a8bb7b89c1a05396	1	0	\\x000000010000000000800003cc06e614a3deadb7e37423c5258447d51fa8918b5e6544dfec251e6aec3f7572601188566d756b10b1d34b41bf3ec0d8ba0cf86a6b38e1a514601c2a7b2177da2991ca3d98280db7fc48a39c4087899206bbe502c483eed5768231abb28ff825eb67d68c12a82a75d9a9de534a3bc062221f5bf70c18b7e35b4d60145e972437010001	\\x2b8ff6bbd3a6773803481ea77ba8fd3072f9101a5e56e9414df7be3128b1b583455df6c9c880cdb2959cb4ddcab54bd01073e8a90d86bb8101f71853f3696405	1672069390000000	1672674190000000	1735746190000000	1830354190000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
193	\\xcb817e50ead0ae3557bb7d58f984b0961a0773f5798dd1acc96915f6e9ba7fb4b806ee81158542c8376031965e55ee33842f9be3f061fc47a3bbc9cbf9177ee2	1	0	\\x000000010000000000800003a2f521316fec42639c40a3e96ed717e3e1178cbac333c0ccee474df095c0f25fdf43afae8834e85622bebe01da790827b85efc795dc045e9c07b8a21fc25a289cb1b57e9ee54ef76cceae0ea237577ec45cfad4a30ce62e30fe8b8a604ad7a61f67f221ea8781e43bb7f5dcc87c0a8496732a62bc53b004340b657a168750c49010001	\\x1e2fe0b983e05ad7740e92d44d6c4ad71a8d8c35263507c3a7acffdc4724b4857fef961e0b84e7c301557f75a981c335b2e52eb35f0b67128ffe1979feac7905	1664815390000000	1665420190000000	1728492190000000	1823100190000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
194	\\xd0410f681aced873fb5454ffa718658017586ee558bfeff60e3f06da4d85ec073a403440c9fae44a2fa24ba69b0dcb508629e100812dbc555479941a44e95f15	1	0	\\x000000010000000000800003b7bbff6a10c9c29d95bc214a7ae19883beac3a4281b95ad9c4ab3fdd7b80faa6aa5b799b87987fc60e0ffc3f4c0357cfa689a96d3527b83b3f6f62571849ec3f6a7e5b3880f0fd1fc763f5e3f4820ce789a056ed648e281e201c5985f3ed8c6f2eb69844f8d361cd5596b00a13b6a6ab1c3fe658febec77e9883f37eff03edf3010001	\\x0b262444bb9e54f693027f8b99059f60606f74c0b9192a5162596c5b25a8053491494a88f126955e563a16e1009a4ecaeaa55cc676691d1db141f74ea96d4b01	1672673890000000	1673278690000000	1736350690000000	1830958690000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
195	\\xd7edaf9eb2bc42a46295ca4dc288361123c27a67cf55724394489f0e80a898c3ea96aae9cccf033c42ba89ce33106605398b541f95aaefbd8a2e504df1fadbb9	1	0	\\x000000010000000000800003b58d07921b683bade8fa3cd6fd024a24829871c7f2ebe215e82ebb2719fe3b1fcd207dc3a77e9fae64fddd7b579df7ed199a08777d2ebf65665fedaa40e42619a26f91841635a42d4b7d7ddf44a37ae1237523babf82c7f269b3e2bb5bef37c6b31e3bad0d535b50423e033e1463c765301db0c5af77f281e9442df61307836d010001	\\x17d16aae8d7fd107964d59b90a05f1f1f454a6dfddfd92d3787e07d8dd273467824babe205485da74daafa00e37a459231f627ab49a0c357b3e2557bdfc7180a	1673278390000000	1673883190000000	1736955190000000	1831563190000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
196	\\xdae119d876f120973b799d8e4190d3e7867f7337f3c5eb54db5d79b819827f15bcd21978b946df7c0f761274e66e3547257985980cbbdb7696344bbd05c1c0ee	1	0	\\x000000010000000000800003ade20cadd680aa55dd391937c91a0eeb7b8f8ab4e194bf08afa02b89512636fcdb6732dad5e963e79946ff87b1260dcd388e8cb33f5a527666026812e007e4d15550bc6381e8142b91567733625a917984db61bab92367c02e2a6bfd87f782c302a2cf73a745a635ceb38f17379a70b84ce2a917998b3b3a2aba9257176d2bd7010001	\\x9af3198a7a615149b63d5770df192f0d44704b58ec39091e15c7cf2f1fddf0ab3572cb4fa2665591f8859f3b090082ebf1508f9fd9bfccccf3faa0539732d501	1673882890000000	1674487690000000	1737559690000000	1832167690000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
197	\\xda410d45bb8951ff2d82d6456b618d081f2e9ab6b58c36eaee16f7ccb5ad78ac6afb3cf8fd12e644b8ca80ee50a42c408fa2dcea44544de1e89630d70784234d	1	0	\\x000000010000000000800003cc2223b458fdad18eb1a858ba83347c7db928a8f8cea068dfbb9668fc441999bd1c6918a69453eda332a625977360d18acae04fec95fd615af8f968919babf2ee687db7b43e912491b7be07046cc7dbf780a4ac61d6a6fa48711a0dc5be54f7e0f3ae2233e949c323b1e2844db00f78354ed855ff6ff052ed30f0d3ae0e6930d010001	\\x221e94022e31ede4018f198727c75e5d2878ad65f4d5a9f5a90986c8a2d939633867c59553349b2fcf99e49d832ae839aa1f438c1714550807db98000d310e0c	1660583890000000	1661188690000000	1724260690000000	1818868690000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
198	\\xda51c4364790694f93b7663048003fdf5c531726b6932222e1b380dec55b31d64b3fffcbdaca7b674b43929adc4731830de4a550df0c8a26e752f42791c482e2	1	0	\\x000000010000000000800003c9fee95d9b89b073bbd83ea7b5bd0625736436173204e0ff8de35e4900afd9bb39666338bf861c0cf4c67eb8e7e61e231cfbe8c03e6c1c3ca028b7dcec2787b8e7e69eca1cf17d44af05bee20e49f01b95061e73adedc29a6d36e66ffb8a946165e30c4da7777e78832a6fbb2c1053c4f1012339c366b6eb99b14c76fd746ee5010001	\\x17e33f13d0883a8341576e45d775db31df457899db7e4747eb3de292552afab16b05c68d548cb258b16999cb2dd27284e9f14fddbe1bb16b03628f9a2bdfb001	1675091890000000	1675696690000000	1738768690000000	1833376690000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
199	\\xde71cd9c75a360cd3e197d21829dbb8974646408472296892edf90230462606c1de928a6731c7b51fa459de3e5ef7d2ed3026ac4ce266796ab45508431359da0	1	0	\\x000000010000000000800003b0ea5b93c8df8e9ef9739cdeefeee2407f7f66c7868d28804735351bd422a343667a13b066e1c035e45919d3f53858fe8c405320d8f0a308243b999d8c6ee9bf9b5bcdd62b27b1533b5515777f92181bc7ed814baba06fea81956b291ba11bcef3d296b1913a02044922048f718372bb9b18973da3f91d5b53da8f30df53f1ab010001	\\x77eb45c2d2ca47567935f763dd24b23ff8ccc7aeb1486c9eb370e93ae33a3b195d7994d157c22374188f1844b403741f3abccab131e28cfef9b8a8af86e29d0e	1664210890000000	1664815690000000	1727887690000000	1822495690000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
200	\\xe91171dd9b69841dd15d938352255152ef10e83aab39b73a8c339cb3addd7ac9a3b829735e95c5ae072ecf313971665dbaa726bc8025daf74eab13ccd0f64e94	1	0	\\x000000010000000000800003b6b40c777b6dc2d9c226e6ba2f20cf181380aa83ce036999d046c6765fe1b02b904b094ea12c631b5134a8dfa8941d06335e0993155506eb39bd18e77556b10b9d417c870a3b582f22b2fa7691db3029b05ba8a5e1b32b1021f09d31b1f4c15d6b4fb9b2f5437c04fd0f318a3495864790610e0982bf39cfed6207bbbdecb863010001	\\x89d411bc99bf7bfbf28a8738aa09270ecf4aa323d5652c47e96b089a4b8673c21714830509de26ef44a152322c902cd0c4dc59b12296c6ec41d078785ff6070b	1665419890000000	1666024690000000	1729096690000000	1823704690000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
201	\\xece1bdd8e87cb4d4c1d9018d051f9221dc732ead43108ae714fab52eaa80f75535a46c2e5105291408ade74ec2b56c4627c1de0d2c5679e8238c1b6d74b60d8b	1	0	\\x000000010000000000800003d94c9e2ff680eacb31319ebac7518334911212f3c1861baf9b6f657cef71c381d508a4a199385a296722ca26740eadac50094bd4d791a2d9ce60e903ee7c636bdb4d73a2e9b9a980a65d4adab5a03822201f848f65719763399e1930782f20ed4369f91852c97408bd3c34f6acc5b47e2be3daa5c77faa63f7e722037a41c49d010001	\\xaaa5276be512fc689f1b55a44ba64adea24a2d28ae225d01e6f26bd1cd15187594af16994163584a959c9b7299f42bfca24b3bd8bab842d281df4fd3abad1108	1681136890000000	1681741690000000	1744813690000000	1839421690000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
202	\\xec813b3af6765d6965384d4eb8dd6cc1adec540353f37b60335afd1650eb488445f116a26e449093764a8a21ba6c7a4ff14e32e5b8cd6cda0eaddd63d2718110	1	0	\\x000000010000000000800003c175eb4dc8b213d499627b1d2d904c38085fd53546f52638db8bcf5a0a871c6c50982b18c69231c682fe99035b6cba284bad6bb03fac657cea051f08b070b50081061101b0255fe564955114f2824b065479632c09fc2202081d17b546a82e2791a6b641f6122c5ea1e091d3803279efdb8cc31d54f52cd6993cbdea3c660ec9010001	\\x37bdb9397f050ab8af4ddfdd7b8cf503a5f27bde8787dbe35cb53d2049128ed5d14333cad965a512872740e605088a71bb3fa164710afca1611a7b26392fc40b	1663606390000000	1664211190000000	1727283190000000	1821891190000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
203	\\xedd59333313f03e24d7c1fd490a544213828d502ef19ca311fe8a014c87e9aa73933083e5721046074ec2b1007ffc43ecaa5927e5407c980fb56edbfade59289	1	0	\\x0000000100000000008000039daaef06eecf30b2788715cc9f4bff1ed061cc70a93aa3ebf60db004e847f034c9956603da50f3d16456e8a06b611e949b4c3d2bb0644dcaa32f04068274a2a5683a5d7511c6c60888b3e26660e4b37acc26a68575a5dc847eb3235ce92b4f29ea203bb932cef9346ea6cd45d38fbb2aea395a22b40c7b7427039cf4dcb43899010001	\\x08709643feb08d682e9684bb0ce2e935f0b966b2ed276566d3dfdc096d8e5a3806c59bb993441263a9c5206ac98b48c16cdd3e34cd2554d27b3b688422a9700b	1676300890000000	1676905690000000	1739977690000000	1834585690000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
204	\\xf2ed4e68bb3eac329c11443934a3a17419dff158ef8779d756c7617a63b1d4f9355e5af44c56c1e5bc0011205c807b63b4af88db999be6733ae88ae5cc790046	1	0	\\x000000010000000000800003b271504f2e5e330a25e91b7486f1ca4102810a1d5a9c9cb746f139b3b5093b24c1d6a189aacd8699b3c2724a5db40598175df85e83192a8086fa59003b9a404220829250fdcde329a3e0faf1db3ef319309131399d603493b1f9de19884de2fd5f286a24487c8b9b6184849f3e847a558789d8c80ea24e93184b073e472952e1010001	\\xfbb0d14a634af2ce7f1f5f7a42e671ff03676385a9480f2ecda9327c2a68dfbb867c3cea343f00ab37a0b482ee3c39105f5af3f72174e0b899f69418700d9c0c	1675091890000000	1675696690000000	1738768690000000	1833376690000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
205	\\xf2b1cbcf94d531b6b48e4c7efd2248685bf5c0e5487dcbcdb1aad516f1e485f4e9ee7662f8d7b20b64cf97e916b1563b1e3c0a6393da582908d363a8001e4f32	1	0	\\x000000010000000000800003cbeb3e7379fffcbd94bc64a5c102d9bb38d97156930bd698040a0eccedf4e8e60cce0325ef480fd5e653d434514ce6f598df4b51d1d29cd2e1f893706b85b5c4b8924ca3b8d431f7c2f57af6e4781cd9ae1d04a0a90d567ed0f2e114493e8ed1986025b8f95a25304b101342915d6293e396177ecff08e7b86cbb75e2c3011f9010001	\\x647bf32ada549890ef044c2f59ae16627ec94bdfe3455ac630797b1db8b03a6babdec680ad85cf29480fca87b1c2d69a20e3bc735d3778e5b56843a6d1f76406	1658165890000000	1658770690000000	1721842690000000	1816450690000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
206	\\xf645d5f97b2caeffa8aac271139abd079ed9365aa8316e5cc7b1876b9aecbf1a5bac14b605aed0096f1dd5ae3862113c9ca7140ece71f11591f9ee4eb0b69758	1	0	\\x000000010000000000800003f57ee99b508c1a83dcf9460cc8a17f0d417ebc14d8447e01e036a748f0e824e929e83528d55028b62067e3571e48749b86b118c10e3d834e547538a4501e916ec0f7c4f507386d1096b683f9d1ef31eba02821a81aaf59fab9bfc336d8a8f6954e77019ee4cc0303f7ce9d1a318651241c90f939c1098ba86900cfc0beb6a5f9010001	\\x7678bbab6d77b89b6504021e3e1002fcb7c54c83c05a164cc8bbbd88d138e6068cd6b7542c89368da80625074f46c122e336197bb906b01c3e6131ad43939101	1661188390000000	1661793190000000	1724865190000000	1819473190000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
207	\\xf629afaa7fb030aeaadb1608bfedd8e0068d8c2c3d04a289e0ca26b0ddf715ac802b39d0f26458eee4435183163b160e8ef1a62ec3b404d2d49b61ebce486dcc	1	0	\\x000000010000000000800003bfec9dc09bed86ee95e9e1972d4924053853912729af7130efd32a2e64e9e9b75e7f785b18eb1fc242be9d6cccc17a829a5c6e3d32d17723b46c9a3371499c7b2b8b86709ac0cc43299db9d07331062e2f5e14474b45ee6c83b7e9389a17928d661a3bcf0151669220985657ec6d4b9d00e98384ff578ca38e3c433746c05f49010001	\\xaea240a30f723ff619eb2fdd15d4557b50a2015b1c6592273b474abf9c00a3da4463ddff2186c62b9f676aed9b09ce596a83b3c44b33cad2c6fc079f094ec409	1667233390000000	1667838190000000	1730910190000000	1825518190000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
208	\\xf9c5e11fa3ae57610de04f835c1d1c27359fb58f1fd92d5eb44f24c6c463fec156a24ea0197c6bf04f620a219da0cc20c836e202ebaa79bd17ed8a94978797b5	1	0	\\x000000010000000000800003c00241c7cdda399033ab3fefdb051c3e27eb512424d86ca1ce9979777b8b1ff95c71e1c2dd2e5758b1d8fc849ff7d62d09fc1686e676465edca1c1fc33ffd57c0818c41d803c16e33448c749318661c8c381d37dc8b42f362d94fb79b761a0b4bb1cb0dba28f0b02edb041bb75dc8f23a3146a98d1cc1e8c9972e9d3fe8c024b010001	\\x8bdfd0ca23cd064a359053c2e0ee99b52775d15afce390c68940558980be9586fe4985a933ec0c090519272d22d9f9cd24b59edfa09749e70503b51b3e83a40a	1657561390000000	1658166190000000	1721238190000000	1815846190000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
209	\\xfb21f800fa3a6d102ad3dbff49317b4eb5af77af4d00825137232ca67830b72d200037c73d242e8887de6235136a56061a8d0ac73860d4790c407812dbc37a6f	1	0	\\x000000010000000000800003e6da52bdea40208706684e30bb7e338ce471c93fb02249ce8a55402211e422ce887dc86967ba41f1f00c52edf5427640d12e6704fc17c0b825f552f03de00df016016c48613612eacde80024c1f154a2a669c7a351015d90ebf7462bc8a2519d6f9deb72bd672115403899eec7eb9495f0b6d8241c6b006ce325d9a79b4ade03010001	\\x07c5abf98b5fee80191079ef30a767074e269748b666bfb1323f723eab2e013f5ad39334ffd44964364a3130351eb9508bb05efe24291d568cd81980fd97d00d	1655143390000000	1655748190000000	1718820190000000	1813428190000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
210	\\xffc93955ae6a6856542427341d17bed9bd9db3b4858ab48e48645d3e86c84698a6253da05c5f23888570103ec95dd92231fc8346d70d8418a75349ceee35e432	1	0	\\x000000010000000000800003b067fc6cecf9d885a70be4c81d08370e4c7a5d4e7c89e25cc535947ea3a706c3a7e4de11ad8081b90f81e099d7f0358856cf049fce68471f1362f82d7ba60e9d4c21fef999d308af7b2b836385d13fd2908dc40d922e62cd9754c6c6d0bd6f35eec42868adc4db5320a694406a480ed82a656f195cdeddb405b98633c3eb6b87010001	\\x5e30f85df863e399b3120d1e9b93a74f4023d8bbcae80a735c1a00550a23a868edbe01a300e18594be22b8ccd9657490840c32c12e6412274572a03f58a1ac09	1652120890000000	1652725690000000	1715797690000000	1810405690000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
211	\\x012e9cd2c3aee45f6536f2084ee18789cd8e5bd273f12d853a23a3ba1571d0f52376368c74ce8ec7ecd3ee687b1e7a97070b31cc354ce6e6620eea28e5869629	1	0	\\x000000010000000000800003b861e6a10d45f7f894edd0830621c5f5abae90d4c684b782e518a63e228147fdc4418a5200c29f20eb1f4044205bdcbe00cc443c5acd586b1b9f0df570a8a248bc2bcbe92e2172719de7ad1ec4d4dacb156a53ccd6768a80b598bc31dfb5f07838b8be81026ee684d11d94854bd8b34ac4aa4f6367257f74a0d55610b0970449010001	\\x110fd92b3ef13407daef4dca1935b1817490fc662f92d2020adbbb3e160041d22f308fdcf4c160ed463e0d1baad17f53e9b180441a4b59fa80918ca6cdfd220d	1680532390000000	1681137190000000	1744209190000000	1838817190000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
212	\\x026a3d4ac34e3b34cad93b4899579e6116004f8c831d22ed2c9792c683db410f563b840fbe05d11e998d19ffe68c7edfc530d70bb068aca511abb0971a276ca7	1	0	\\x0000000100000000008000039eb3e47a8bbeabcc882820b65f4af7da9d9264694b4ba5958641c26994c6c058af601c0b3ed1bc0886770bbbea5fd8f2d484697812b53b62018f9b3c935598f8af71845fea5d5e9dc7f98542521bec7dcbe1b05ce0faabc8e45ac3a714374050d0841e094fb3173cfd4992631eaebe2328c938bf7075746999a0fc4208a3b58d010001	\\x149ef7e66a005c98496533ba89a433e444ccba3e028bb2e3afb5ab2533ec67e2f1468e8901bc40e5ab012e90ab4034349777e08100471caf0b0c852052fdbc00	1653934390000000	1654539190000000	1717611190000000	1812219190000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
213	\\x04a21689817343c60f3e7b435494792a2d7314d1ae6f5be6982f25335c1dcc42914670d144420275c34c1a82621108eb80cf72e06c0e6c22e3ce5249d957319a	1	0	\\x000000010000000000800003e5a6d29db20f0b63c8ce94b7a42400e9184f354bb2aa5198929539dab1f6fb6cb9e41e37728d387c8865f17b1a97d41505cb5e783e2e64039fd089f70bbdd092c436dc28a0611b4973391ca00073536c6d659ed7d7910a586681143f94e9867754f3cb984a0842034a1b3aa8448a7c4efb9941345f39ef6b70af2b2902e9147b010001	\\xd9998e7118909e4577f4cde4abcef79ce02eef2405070abf1972ca78e43e967b74a99f908af29f7d7c8b4c213c7eb7b5e8baceca341012c6c6dea7bf13d4d009	1676905390000000	1677510190000000	1740582190000000	1835190190000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
214	\\x048aa407a88885c0e289a2c7a9506ddf4fc36bf2913a7533e3745cc88a900e061ac8fd3143406067e36946b0822875f00bef20286b56f364aa92ee4a1354c29d	1	0	\\x000000010000000000800003c39612e051987e499355c2dab4bddcfab5f4f60957847422b83e924062b09e281566295876c78ed80a9af14b1e4254f6c8e39d6b30efb8784c6bf109de4539a51d985b3263c88e4bb6bfe8fa05d1e9445e699297c9e906b2820dc1aa3533161ac6ab4ca2b516fd7f801958ce5b472b3e0a5cc38fc6c60612e2362c3d12beff4b010001	\\x30a68254b0780542371c59e6228209fd75c58f964b472a3dd5567920e60dde70acef1f313abb683f3c944395b4ec1fb108d3480dcc036f2344cacaab8c23f50c	1670860390000000	1671465190000000	1734537190000000	1829145190000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
215	\\x07eeaefb8816aa8b0ff65f2bbe7d9e755384876331ae272f3b553a597caf769351d3a78e3cadbfb37688962ec0f5b5a8080ab436c86f6b96983072b725d24413	1	0	\\x000000010000000000800003be09fdb63eb17194d9562b7f3fd3c862fb07517d1b7e2d568d495159e149d149403a24c31dcf16b6edc696fbcf8076780d47af358129ac34d674bf234963b1bb9842182388c7e769db7841c29ebf741d1c6b5dd8e1009da5d4248ed404a08b2b2439edd8cfb0578c2e730a4e7fd9c3d7d5ffe939ee40c397b7c86da5acea2139010001	\\x1f373dafac974d390017493590c3e1293ae3f18060b67204c1141bd53b9cf71a61ddf8d1bfcfbc6a838ebf6d36d233f33388920e0751c392523f71dd0601720f	1658770390000000	1659375190000000	1722447190000000	1817055190000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
216	\\x07d6b2c4c2c57a9ccf5f68b016e3905e56ffde52d862643ecb0e938988da9337abc2115b4e3c2d8cae83445bc95bdac421d67699055332fb6ec8b5dcbfd578b8	1	0	\\x000000010000000000800003a687c8b1880623f5cbbfbeb2c4009e2c8f1337d65e7b42cf1e7fff6dd85dd797b157b0c6c47b43fb1dcf0551625523e1a4047c696efb0e59ffcca1a58b28e5e1ef571eec579854e8a4c03b392bed056f293ee0279be718cf36513396ada2f14c11c69d61d8a6a99a09ee8a253804843c359048206dad0a10528645c86eae3977010001	\\x02bd54ea040b23b39c05d1ed3219596a136558698f6394b628ba5e4f1b496f1a630611ed9e1a04f62cd7857ad0d3ed3841b5bfc50ab9fc99fbedb02f55f4990e	1661792890000000	1662397690000000	1725469690000000	1820077690000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
217	\\x0bea98efd2bbcb92e38d267fbdcb7f4c0cf029e41d7ccd9104474a5ba5241a5b0859e635a43c32f7c894dd66e310d8d9d42d5c4556d1fbf6922233262e11492f	1	0	\\x000000010000000000800003caf28b7b81f2dbba78bd8e6f70a1bc4e261d3d55b5ebfc9992eef381a7f62e76f27614a4b74e72a8b8d0f7603d58ecb76f4476602b28ec163dc60b70b3c5b46ab28ecc5b26ba21ec569d41fb2ac6f0469290354b36965d8bc998aacbf77bd041b88b8f39bcfba701c332bc66b4652a1014b97b29b32fbf6e6e705e52f3323a0f010001	\\x5bb69b653bd94b534608714c161afe3392445496af4fdbaf64119c4f21d1191fb7d910ded99c59efa969318daed7548b5ed1dc60e598bfdaeccadee6ea647108	1659374890000000	1659979690000000	1723051690000000	1817659690000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
218	\\x0daea73c18e642e1bd15cd424865d09245f6b4d7e50514ed5681ef2e6e0cb3d7bd3ca789c5648e2c0fbc62fc795e6bd6c09cfc2005019633144217ed0dd58631	1	0	\\x000000010000000000800003e55e6249d8aa4eb9e51b1b2f0409a8447380e515b3ff9bf9443c0fb83301f8d69e4fdabda03bd6ab84011ac34f22ebf090f1f78c2be8abd01a641ebaa978a5218eeec9cbb2fd95660ead49faa5c09b91a1a3a1df0532c4a18ced40797076bc8fded00b1363bdad706d21af404a8f9a60576e8654b3089042ce3b4a80aa07f0f1010001	\\x2e9ef52a54b704147b2172f2cf5b72bfc479bf61ec98d40d03b3e0cab4e051b75ae3b9860333720412872369836f3e9ff32231c2e48f3272518f3aef8f04f50d	1676300890000000	1676905690000000	1739977690000000	1834585690000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
219	\\x13aae4e9a0dbb470d6381de92c6fbfbc7637e26ace71a58d1e00b1396f684372f38097bab6630c8ab3058edec9a0b35c22c6d9724a4f581eb4b4bc7c375c0217	1	0	\\x000000010000000000800003e6d10f7984296c984cbbb3ba411444fa2a57f494de5618165dc2448be6dd92c642626726dd3ed757c24088c409b8cf840c5b444534b206d63ab568a576ad18b8321149028c7219a6914b7140c3770bc7bf7938f763b47b20a088fd3335bd152af7de763ab0987ce821dfbbb35f2297617d9397c0d96ad86ec1957bf345b3aaef010001	\\xfded99cb1718b1de2fd4dcafd3cdb14bd638bc7fecb739592c18118ebc11da7b5caaeef9e7268708d3be9bdea5cc43ab3b808afb51ddacaa3003dd2b3c9b5007	1655143390000000	1655748190000000	1718820190000000	1813428190000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
220	\\x13aed10e8b3052ff31febfd3edc4a0918fad489ecf73f84a79e74360330405a26b208a22d6868cfce6e06602b907579366808f25055b7492f3e14cb04a56ca53	1	0	\\x000000010000000000800003b4b27306da3fc0343f23568a1a1fd09712e7f6e49f57d7e1261833c21fe8eddcffbc2a965ac997bb252912031904b088b0b18590464a7bf6ce0aded6e3b707303e2ac7ced958934dd5bb520ed02b2d7bd7c35dc8d29c22951c28c7615f6ad1f2ae3f55ef241d19dd10592f328c129246ff8c54e0736e8c4b47a317dde6845c3d010001	\\x64b8a43e387ad600905136745956a574ac9551ec4fa1db475241b2f64f14946b3d230821060ee34544dfdab1b07bde53490f55d1d07d1d28c3f3328444509a0d	1666628890000000	1667233690000000	1730305690000000	1824913690000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
221	\\x1682a016b14d2c0c3de009d18e1baf1b1ce6ba574b37bfb477fb1c00450d3fee5fe9d48a9c8f0948b02322997430dfe3be90ea43e15424c013867495926d8907	1	0	\\x000000010000000000800003b5c4784d4c6ac1ac6031a1072ddc5ce7bd1b0d999d1a662c3b12a045cca2616acfdfdbec92c0419c5d6f81821a98f98df6066b435a87c37cee036f25062e929bb63360c971696543e07e5b015024035012cd5d490123686e4d949e1c0aa760fe737a81e99e810ef16552b59cf4394f217714bdb81853df21dfe7a964a73ed5b5010001	\\x4cce3000081e5eaac44229e08e54a15686e66421bef2aa06a84f19e694e6a4e132664e3614dce4059a1b129dcdb72a542f30c6a748e564b93f21a8c6d0f65409	1656352390000000	1656957190000000	1720029190000000	1814637190000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
222	\\x1eaa333c50483baf1087d3f95a2dbecf13bf597cb0d0675d3d89e4b7d15b9d73de85a877999c1f95b37fa6584302f6b283070c749f3d5e1f4b9bc16a9b805b65	1	0	\\x000000010000000000800003c02255621afb8462b0ba03c24aa3d13375a9c6d916cafd9a453514d19fba23d616e052ececc8fdaa28d6d7485f4208d1a777f86d9a37c2f2eaa2d56b9e0ace7c65541ee1b4f322449e7df6cb484510cc9207ddab448cf64b3dc65d15e45826e35c83525563654537f8a2e0e3b2e3c7e9c8d94364bd72a72c2c35157fd0b059a5010001	\\xa9bf0d89031c9695e977e46701091787ea101552fe841f14b6822c6e7d998c4bf985f6f163f63af367f3d3ccb265e86caabd0231491fa35ebd51641f77b4540b	1651516390000000	1652121190000000	1715193190000000	1809801190000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
223	\\x1f7a416d5d28afdd728756ddf08812686edef077cd8b625f0a81c79655f0326d962e30738c883727087b1bb6a1fdcff5f77b8de31402d39850b919762a15b41f	1	0	\\x000000010000000000800003b5524a9053f658d1aacbfc0ed5f495df35e87167cb3f05cbbe3caa41de645026ac944d8108d793f770b22b7de9f15ffaa1b7204479febe188d41705ee573d8d26580ac45ecc930828a02cd5d54e1e455e7ae96d113065845496cb4fd83a45efcfca839f9f6c503852bfcded90d74b6dfb19f2ce6895d7ffcb40c95133c174acb010001	\\x307bf94bf129dbdc84b9f1a2787a508a5a8021699992dd415944cc8ff1bbb6fa13242f30676f4c3fe73174bf67431b2a8570d31a43d4d60125c6b98a22ceb80e	1678114390000000	1678719190000000	1741791190000000	1836399190000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
224	\\x1faef17bde25859867e169d33b987a73e5e5de7486b48ce04d3494ace69d3d0adfb6850d9ce3f0606f24c54f390237386ae42495c493125e1a07e917950f87b1	1	0	\\x000000010000000000800003c882a4d88341b87e6d2c99945785f7b08a204ee6d59a7ce3d8f5883f741a5fe052148d70ae739885aabd044cbeb46f131e24394fb1e3218214874b314570bd243258c3ed3c3f05c1ea50d8663f6132989c9525076f85b4e5999bda98f260f6c10f765defe9599a954c391fdfd07daff384d50394350fcfb52ceb263addb871b1010001	\\x877fdf7a100c752b61d65179882d5374303963ea5207ebdcfdcbef764f171a0fe889879de34ac36cbbfdad7b26a3b471f3659104432593c2ea0bbe16e357df07	1659374890000000	1659979690000000	1723051690000000	1817659690000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
225	\\x1f569dbc3e04f09088ba0954989cf09c02a2b10f85c9ca30e10440eb2ec195b56d48804922fbd94624868367aa3c1a54c7f626db63bca431c2d342f939302d58	1	0	\\x000000010000000000800003cb401ec4b797b9f3eb0399f77cf11674c5a784ae90ccb5d0e916b3eee0f2aa8a2c45fb68c0316613ad74faa55428c8c9cc5e63977848938236f79e252a7e4dc6d1ad2205a7afd53239654db3a782cbb79c668c47417f1d16547b566ecb93da4752e293b4d733f30514e024574165dbc14ba9d39dffc2709522325754a3fdcdcb010001	\\x4f808fe6255eeeef823dce1f5b51c5e50f0f7621b92374b7c9bffa90f5db7816945931fedc00451aa929ac82eefcba6213b2160f4d38df12333266d0d46cf106	1656956890000000	1657561690000000	1720633690000000	1815241690000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
226	\\x210640fb75a3b6802c7fb08f2c6228ba33c29f107bcb036e0800488ed5b12ae5fb073d64758a6b10f1d9621c1fe883d8c86aadf9f23b0db55569d205ce88489f	1	0	\\x000000010000000000800003c0b994a608b1bebff80038f36316f1252031ad696c42794a1fbbfb8a3da625732876b53f1bbc89d2f897a06504b262d0d21b9f4cd5bed4f371d8f5e98e552017664ed5b4f5b08e1bcbbfd392f3cb8b9940ed7aba45cf1822e96eca5bf23f9f83ae5d0fec51b263e8e4dad8afef07c7a547ebfff899afd5751936e872b37f5e75010001	\\xdea4e34319376e6cda272c1713909d9608713bdd2adc033522d296b402480165da6d304ae5bf92a68638a14f7f100766af82e7bdee53a98e342d46ac4255ed09	1666628890000000	1667233690000000	1730305690000000	1824913690000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
227	\\x25b6b2890775f7098b7cd7cbeadcf8628363f747b10f11127101103de072e24e17da0e8f1b2abf8c0c7f6315cb149f442a2b3a85d431e7bf8600465c2ff7cef2	1	0	\\x000000010000000000800003c0b62b6a34d3cf492d241dff034c7e8d9176b97e8bab67b382a3685697658f316dca314bd382318ecdbc73eb4b1941bb6469f1ff829a508bb075effb5d624b771f05b555570fb9af6d4218a5d5bcdf395152c66bb816318c40c7f963c3b69df0f408199ccd3a414159f3cae40329a31656765ba0a1bc16aa1db008659b0e2b57010001	\\x6a3e43c9bee090e4025b72fd8a44a5b49e1232b41a94cf745991656667653210fc53576acbe20045fea7da2bbe4be6ec2469e2c6c6c5f2a748d00b0291348301	1682345890000000	1682950690000000	1746022690000000	1840630690000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
228	\\x26863c7a7ada5f775041a39230dfb1eae8e63530251a4a455b1988dc1da28e7763b77e13627b64919359ee2a965ec3f4414593e0b5bc5e7754aacd33eb31fcf8	1	0	\\x000000010000000000800003e34af8b2dbdd44257bc071f7ee6b891db02f4235ef6d500fc9bda3b943e5acb60672f0a84e7b68a2dc41737d225fa9cb71b918ce5b820cdc1b03731cf9f375ac9080e69505b448657b681648e52ad5efc71db1ff43ba70def6baea3df168db380a0078a7b720864e5135c9cf5f5c428691ae4ada9a9e1e8fe38d720b18c4e8ad010001	\\x2e5923ea33ffefe5104f1f63a1fb384d41639d2fb60c5e871cd29ad4d92b427fb3ac850d6cb4b660f2a7a2f298873f6378fcd764afcd09e8bf0a9ca5d0d7f707	1662397390000000	1663002190000000	1726074190000000	1820682190000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
229	\\x279ac1d3eb35b928d19bc8a7e15a96daafc535f8160081a584c322accbab28565dce03a1d4cb79b1602eac935ecb2d50b156bfd84508b44bcdddd4bbd7bf6bd9	1	0	\\x000000010000000000800003bb075e19365050643eefbda9fe562ee69173ce0fbece475fc2d70e613fc086e1f0d7084d45869bdfb7171735a78b7bb59471ec255018a6f5cdb13591961c92bb644601f51ad4219953c9e5cba8072972880c950e38c3e64d182c96813e16dbe63c3615dca94e1691685b1ca0e90bd2eb06c309ce3424dc95db76e5540d146623010001	\\x2d280c0f5e8e7d8b6ba5d8b70c968ea6fd2b0c207453d85033a06de3e678b630915175d1e65bf7f029b9cfff2ed962ef3d814e17ef38e075699e0a6eb4669404	1663606390000000	1664211190000000	1727283190000000	1821891190000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
230	\\x2a9ede394457aea44c6514b7fcb567d92a3a9e43e19fac3461ec6daeef4c9dcc53d80ee5a60bc4ee8c1265a4dcdd7955a2e320772047121c07a56357b51a243c	1	0	\\x000000010000000000800003da364bb739b4e4936261248e05323197db9a8a23862a1f999708012437327b186ba67cc44324c14fe2b1a498e0503d288ad7ac4bfec80ab56f931f9fa9e6d66f37b5251ee20a9cf28d6d3e750a5327e7d9b2432261f3282eaba031838ef2aa145ea951f74329a5ce6722247c28926c852e1e8e8912dc5ade3267beec0d6e0bdf010001	\\xbf8de60505fcc868fe82b9dafe79134822698651f659e60cb327a4ddef03fa55e2c90dac493141541b7528933655c998d31e5acee02400541c74c7a63c4f8605	1675696390000000	1676301190000000	1739373190000000	1833981190000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
231	\\x2baa2345537454090ffc2734f790ef1c3d1462bd867c617b9d01c27daa1a25fb604306f6bd5510d37f9ffb6dd4f980ecd3b2918d55cf794757704384e9ebf2c1	1	0	\\x000000010000000000800003c6bf03f6ef2576fe9968a00a0f1414c180945540712f991653dc1104f70dd82b1161bc6a005dd097f1f589a2a88a47f08b86d90ac4fe7b4d74b38bcacd2bf0e9f254a9c4e5ef92e6effbb37531b76541a23f57762f7562b1592ea9a361078e944767485d46b16fff93c3c454db6d2613074dea20eb8aadbd23a55e342dfdc439010001	\\x07861f5a76ccf02c42630f48923aa967f0cdb6f1476613617ff2579d886d230d010aea507ae115fb0fde426da3a041c07f41908932e8b78272165ed21ba89508	1669046890000000	1669651690000000	1732723690000000	1827331690000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
232	\\x2dda74b1a0f3de8f8374289200921f8f1a9f8932cd05325bfcc798faaff4f6fed7dfc1dc3e3c86741c1e8ae70802660d5730214b7e5e3af32d79ba627e510896	1	0	\\x000000010000000000800003d9d1589c68ddd8510be95375e13423b0b3f4d600a0d2bb39e49d1cf6286bf7ddbe9d5744750eb103a58394eff6fe031661861f3ea2c69d08a59389074294ce0cd5c7e6bc7e23db40e199b338756d37e2999427cce2d7bc9f3e86a2f266d5d7eb20f45fb79554cee9b4bdea03b46092f6ec48f4f457b8a4afcb29796df0295e3b010001	\\x28d9fbd3e5cb57ec2e5f9269f94eb6544d8046aa0a4f6137e2ffd3ee1e18e227e5d693414caef9664d1de4ad57c5cebbf8d4915a82cc39e0ebb1a26628ef1f09	1672673890000000	1673278690000000	1736350690000000	1830958690000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
233	\\x320a9668cd8c2ee3954cdd0abf30a0bbe59fae284f2c1eabf4a6e9f191cbf5a97fa8cccb56c8af0ca337eff2ec83e5863383cf8ef56124a672330d049bb35894	1	0	\\x000000010000000000800003ef8ee82387413b0386c31bd16cfa52388f5bcc2f863a2f4b75cbf2737b7e8ffcf71ba00027c49dc15183c2e0f36a7e0d6454a0305668eb671e61571cd95b05727fdf4770d08233f2ab48ee66dd279d08c9eac87a5b55db1016d70e0e71b63382965c105e8ab2b03a86ecee2fb5d04173f22eba81019f9118f55436d1a9515a73010001	\\x53b097665fee960bcfc017d3963cfb189ea65d86413016ed2dc282e98453d5c2c82466efb91a8ad90bbffc028a552023e3727873b54ec6ff45216e725ffb6c0e	1673278390000000	1673883190000000	1736955190000000	1831563190000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
234	\\x33caa548352791bfaf96f49d58953ab2cb3a57a6398097056559cfb18bd30b14d031d4ad69ce4c561e2d525f1269ae5ee33de738b8c80a5a25ba2fb6ee2037b4	1	0	\\x000000010000000000800003a5743ce05b05f4c98dbd1a0ea0e5ea080e406003212ac7373ac6f9ff119cfff1c2290cdcacd1144d0bceb6e34b396f7eb54011b390c31dda70f37e4adb8dd93e0cb36170457b7f0f91434481473284119cc13e3d66cc1e7509bcf06cf9da6630a7615c720467700172a08ea8f90a72f16e882eb7ac8a77e33afe927049e7b5d9010001	\\xcad3f0379688d61fcec06cf01a5409a2fa1a13b9ccfab14ab23d076318ccefcb69a4d2a6c936cb4cececc36e8560a70b2dbf17c1b3d1ad46fe016ba40339fc0d	1669046890000000	1669651690000000	1732723690000000	1827331690000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
235	\\x338a826aada88bb6c840e0f45e367131b80ede7f8ed5134f01da3b113623ae7d10f0e7476b07194f73ed616c7f6bc4ef465b251f4e480647b8cb77becf45f4cc	1	0	\\x000000010000000000800003d8bee65341f6b5f2bd90e85b01775853555d41f6aa81e37d300646132f6cb0e4b587858c09e08332431dc97f70bf8d65e950c35dacf7e6c831a9d74a3838bcdb7281b88f132e4a53e952106b1c0f0e1b7fa7adeacceb1110b78b78199d8f81bdbc99104d8ddab39b2f888dda57f9b5499f6450330d9e880294db9a27066a5f13010001	\\x80ec98ab18408bf9f65c1415e4d546102a9b74d493ef1012aa3044c416112c746a4f0871bea7886d3fd5d7ddae5e29696465559f6053149649ede07657c2d30e	1663001890000000	1663606690000000	1726678690000000	1821286690000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
236	\\x38de80e2cdc295644a2154036c36c2b7f44c82216aa298ad1f6205dec99e9c4b6f321e1be9a793a254be3e1ec812128e0bedf4abe375fdea48559334fea82bae	1	0	\\x000000010000000000800003d448824ed087b951f464d447d31b82c44b75a2e389b92ad67969d7f7fe4dd75551b8079200ab802b98686b07af45acdf62ae5774213f24a22f7b8ac0a329750b5605242e37e21a84a4dde964f4c7413292105f4beaeda166f785f3c7f6630ea1ea6ceea98f65adcf058a17601d8622232475668df7fb2a059a00f6d32d341371010001	\\x48cb80aad6e504a7f7cbd0d95bafd904f0df6cb0862b62f9993382b0655a12d6c4ab8960fbd39aa9d1a7a41788ec608e0c415ed90af6523920e24c5859877f08	1660583890000000	1661188690000000	1724260690000000	1818868690000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
237	\\x391a4511cbc1c8f12e70db0174531c991a7207da33ba5a0354872b26973074b302b81818c87dc339f4bc9088b144972989ee23edfcf225cd9ee8fe4617c821df	1	0	\\x000000010000000000800003d147f4afd0746bb15b03f5e0e69949d2054db3633e2a0a7d7ddeabcffa6dfab1e7ec25aed1705c69cac0bf93406637b782391c9edaa324aeef728775399e082a5ac53beb334ffa623126bd60f4dfc0a15dcc77948f9bd41cb8781d634249238b2b3222999e61c676912d87ec2cfad588c2236eb62518b0f58f0698e62cac7ec5010001	\\x064f1e1f198d7d8833050d01d8997b52fed5d0424d13be41a6f1e4745d8b5d05027017c77c4fef6fe784c6faac661c387680ab030529939681355495626bf907	1673882890000000	1674487690000000	1737559690000000	1832167690000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
238	\\x3ac2628e11591c638065cd59b4766a87b850b2b2b014791eb6f947c74c2d005dbf5bdd0859bbcdd3c89540292e4b9361b82f11872ef216d59d01b2875d913aed	1	0	\\x000000010000000000800003d3be496ad2c97f161a34a46c461955d65cb9415e4bc8106f015027c5bc1653caf6b4b5c5770ae5ff59f54957b1a4a2bb6a4cd6553caf627a644068e804c3245268f755f534a91f433dc2052b0b4c12ee58d297ef676434fc9687621838eae1aeb50c9ccb7c10598d2fb4434ed9649211e9b521b586835670845e6b602295807b010001	\\x721ba89732cb6659a472a69198d08c1fc317851e7a01bef910a4a090ac8bb887806ae082ec5275f179f4b31f79f54a7f742dc0432ca136d28668921f60d3ec09	1664815390000000	1665420190000000	1728492190000000	1823100190000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
239	\\x3a9e3e00345c25460efdda05ee68375bb36e0ad83a46be19bc147239a517257d8f87c838b6719fddde30fcd7b27fd967dd3f9199869f0ffe97301776e225551e	1	0	\\x000000010000000000800003b8fcdad92ab2d4e892bdd50ddfc2b7213a955ed64ed7a25ff3fd46689b4d70e2e436d19e96d072ce49b3f0fde64265c610f93024f51cb3ebd3d8a8f8b40a73798ff6161004df990140ccb210e3d2b3243e54e0e8654555aa4f7995b27e087af1f5f9b39072ef2ad9c7be0494282b26bd4a8d8c7d1839233ee11ad253febaefa1010001	\\x15dae91d9731ca621709b60df56008e9936a1dbd635fd4993fbdfa728038b0db38d4ffb0a1ac85e3cf0100ad997219fcc0932f43b6a290ab2da39ccca15d5f0f	1677509890000000	1678114690000000	1741186690000000	1835794690000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
240	\\x3a6efddd58efe1693f69bf72fd7129cce61f185240dfbad30f876b98d31d24e997b9b26935115daa2d80a1c4692575839d1601ff7a5d030fee3b320d0317b665	1	0	\\x000000010000000000800003dea17f9290ede1985094a4c366d88b366debf9a6265052f3d23563d1204e475b9cb25808b9450ed1315f0c80f44f45f3f443cdad5a4aa16e53883c23087a2f403dc81c935bc6feac2f30a49d6daaba46eb8c57d595f4b3d4a772a21bac21f1a63f8ef1690a958444536ee599153a7707189788096964a59476a6de8fcc2ca725010001	\\xa216400895d2965bf6b9e2422ab1058d3912ba874dbecb11333418b621e62ebd5def120c3f6972fa4d77e4539c7d56452a87cc5627345c5f84b3aa93efb0530e	1679927890000000	1680532690000000	1743604690000000	1838212690000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
241	\\x3a0ae4c77d90d5b3aa68ca52cde90ca639cd009decdd2f34522a76ee573e9bb38e7e55806591048e4a1c9ab61d53d77f1ff31c3327b7197c93c5037cd15298db	1	0	\\x000000010000000000800003df042632daaad48360a3b7d436a8b198e348ba384fcd16b4d2782f0835b51962cb6275d4adc81779e7ef1610a9147f857b34b99d7f295ba1b6f619e6076931ea194f7123933631052515f9185d2d7165a5bfc8cc25413ad1048ae06a12034f3b11036c0c2ae196ac316602ad533864915920f2872f0f8c5a3ba988943d2a50d1010001	\\xe3df8e508468a987b8c4d3cc13026b7a992d5abba9f7062b06a5eae676b0790729eab65ed4ec63e1dcb2f5cc4a8bf45ed0d302fce62fdede5323e20df210dc04	1654538890000000	1655143690000000	1718215690000000	1812823690000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
242	\\x3a7a864ac79eb92fb56e13626a4f795ddb8dea82a060c1d4fc6f950e3c7eb2693f8e9902dcccabdeebd0e400b51748c9bc36eeca0eeac45ade3fd29b03fb5df1	1	0	\\x000000010000000000800003ee594ebc8dc6be625ffadf5001cd17cd79bbea6fa7f53a14672ab204fe770dc7f2d25ba026502c62d1c6649d2c313a94f249d54b18f505979e2c58df952d8aadb77831aa16bd8a4a79a62f8011f8a2758f1fe7425b7ec5951ccac507c0c37f4ca464b51213a701bf5ff58dbfc313690d99d4362c539f9bba0b0f6c840e37b63f010001	\\xa4f295ec4cb3ec9511835f473efe7c0b1a538036a15b208057a0dc11387e8dcacd639bb8f8a49f894a74291e41323f484d9d8fa4990c4899e1b8fb444575260a	1663001890000000	1663606690000000	1726678690000000	1821286690000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
243	\\x3b2acaec6eefe7253ccb273bad4f76d3c037f4606b8f36778eacd46039228347ea178a0e5c3324fce9192070b3a9854e8a48c0ece9f513031462f9ad0dfb8b7a	1	0	\\x000000010000000000800003b7fb823e560774bf305202ffae92b80948058de35067c63bedade1df81413f5be29ed7cc470ae608cf4586be99cdd2e5d5f074e8cbb1c68a232f437dedafbd3b21121dbf0418b80e3502389b71e13e73b83a7941bce23cff5bc2e0cfe5ce9a95cdc4bfbb22718afab050aee635dffd1fbeecc94d45d99b1ed038fbdb8b81bb03010001	\\x1e7e7417b8c448684230c81982a97f221479c6a27b8b56dfe5f74a94228113419564655db0ec27ff65667f9331d97e2a557bf9a3b7c266f141667645fed22208	1679927890000000	1680532690000000	1743604690000000	1838212690000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
244	\\x3f0ef61b4206cc211314b74f11cc40377694317affb2a21932dd8d50b80abc655e91b4efc028860264f7447859a5a5180e6fee26593316d560845599fc265bc0	1	0	\\x000000010000000000800003eaf13c931ae50d64e7c13860d8f7bd493bd9fbde114221b456565cc1bb309b0f5180265979208f4416435a6bc4f71a6442da0cd29356959acdce070f9cdd5473cb2e6a6bd937889ac3d4e871597aff51caa387afcb59754766755b77924634f9bb23a26068be105cc2f17da24fe60a8f19c9ec56acc737fa525c70d5638ab2a9010001	\\xfb82c5e862900607de24103a07a0f76323480c019155c0b68fe36046966336fdfad565a6d3a647b489014c4cc42bdcc5ee290016476cb9830d789233bd2cbc0a	1652120890000000	1652725690000000	1715797690000000	1810405690000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
245	\\x407a11b5282e5f4bbb5b6a6d0e164e50fdd155fe1531300eac5c3281b87358c952b51b665c82f0213f8fae7f594a0462a6ee1330336ccfa1ccc733e6cc36d47a	1	0	\\x000000010000000000800003ecc2e7ce66cd5f6c5db92e101f8645bc075854149c16139781e1211720442c6c1fecbaba13060f3514aa864b079e9bb3cae2352d079ed88d86880f0eafe1c256b4a5220da6fcf0c8b979ee52b2537162c3474b917572e5ddc18e58b34bbc600302d9e1d2d088e2043756dae3c009947b980370be76dbf0161f213b4a3cbc02c7010001	\\xe62942762e47abe1c5d8b0b5d3fbc5d67415ceaa25c2645b69647d3e93f60d5d84be1a78e1c4bd1d5d5d47f5ed4e4252fd9dff84f3e0c6aeba4982e022460f0f	1669046890000000	1669651690000000	1732723690000000	1827331690000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
246	\\x41727ca0c889f466a6cba2fb09885899e7d067980142206481013052d3dc81bf086017f725fe14bd05df413627914d8228c48b4e79b3af30628893128989caf9	1	0	\\x000000010000000000800003bbf9f5f537943565c0e051292a009119c79db240b1c3faa8928fdfc6f30a97abb5f23ccef8db5fbade10a21eaef9fdad85e293414175c0774a3e4e036f5769c0488b576f27239fde9a106965e33f11f511c9f888864d487168c9cc1488992d924084810b860a66c5a1bfc53279ae9dd9773966b644162bb9260e37f64aadb3d5010001	\\x293c47a179110590743c64a135360cd55812954bb2dc4d7ffc23db64d83a27357b8ada7b87f08d4ccec375b808a3aedc15be7232d0a270134062472d288a9f0a	1682950390000000	1683555190000000	1746627190000000	1841235190000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
247	\\x4392288f1e0a315910a8077a9b4338558b6300e47fb8b893c8fe7ef24bc45d835338583277560b4952fca7ec24ae4e20c3b372d66e8ea5d4f015cb5947738512	1	0	\\x000000010000000000800003a537a8f15b52c5ce1ae7818499ac55d9bfe77436ef260c20c6681048ec71c6179b5a633c1ff5031c63e9cd23752b4d6ba61ad3ab89d98726ec38cbd96491d7fe92f1949e640c0ca5b67ddcef1f6e70c4e76f5826e1a6f1234f62b4dc6257d8948c5e2b3c6568b8111033152d01884a3d8e365c01df96a37bf814b6e7f7aa787d010001	\\x2eeb437fc7104b8ac22a30222839f74cdcd66d4f8c39fd86a086b4d7ad4b2c7a6847e4ba42f4e17a32effd50491a7637e8a10438e50a89fc882b56e1cc2e8b03	1682345890000000	1682950690000000	1746022690000000	1840630690000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
248	\\x45b6aef94ee6962310b798d6f34e2de702c7c40125af8798504f7660ab49339a95cdc570387851d2f27f4e24301276914142271451105f49e08a523ee23d34e8	1	0	\\x000000010000000000800003b98da0d69e0da315b5c21d3061f1b6b8035918a42895063603fdb9a11d0de002764911caa470ad2c32382cf2dbabb654dd0e5b7d65d163ec07c38f06dc39b59bfea22d65dca846e0aa01ba75b5052bf79c9ceff9d2822265785c5359aaa8433275ea06c0ed49baeca5da556a193b8369e2c0e4f668cee7568b046b96d2e6f069010001	\\x5b68b324eb259ce3f2a778e7d49d33a31c1d5b118202a7521ad7d812fe55a6dd3de8cd92afe71dbc19219b79539e6797673edc25b4586abdcbc4cd98abc7130a	1673278390000000	1673883190000000	1736955190000000	1831563190000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
249	\\x459a86bae8b08c9998b1f7b88cb1abfb4f53f344dde949706ff7fd94de6c84ec2eba5234bf2772bb553156ba1fd4a5f471cd8f8ba36d6a1f809723fd17607ead	1	0	\\x000000010000000000800003d35f79b60ad123423b770955ad1e8271ee827135b1645049261bb9850d82b953bbf47967ec5bfd78b3f9be102c215af71223bd684aed1c4b21c31ada54737e10bc9c86f5a64159386a4620068ce88fc25468b1ba2859e5bb8e9705e34912a5e3790cbf98e03878783bfd9dd4b9bdc55c0825a4bfb4af3d09c6461745be4b1add010001	\\x57a19edef468425594fc49ee6e6018febe6f460fe3e6413fdd472ab82b1085b2ae9ecccb71cb726574a390b9f42f76cd55e585917be4eca95e15650f19902b04	1658770390000000	1659375190000000	1722447190000000	1817055190000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
250	\\x46eeb825c01cde9a3abebd74aa42d69a1f5d4a6db49a40a1d6d6dbf02b78cc93ead217a7d45417d2abe3c5ceff695866a265da2c9036107ed0ef48c4ac3577c2	1	0	\\x000000010000000000800003ce02ade6eeef68c78761f8e9bc01e79f53fea3b2e77f083879e6355b5671a6a0c80f619edead6fa60199a2e513bc5c32c158b5026b3355100244c159c1d5ef164a4abdf150c2121f98bc6c6597d0b1144e265a2f8bae9d5c8c34924c8f81a5d533c658f7ef8c7509e6b203684e5aa74cdb1cae8148513fe6de09e80cabe29117010001	\\x6bfbc19b8dde109a9e0867d047d21dd2c7c1ac1c21a1eab8e76a966994a01cc7d6514293b32504fbf30007efdd1ad4d528ef390232427bf3f0b2e2a0b603ba01	1654538890000000	1655143690000000	1718215690000000	1812823690000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
251	\\x49762322f1ef75ad0ba091dcb991535b7e7c76fc6ad60655796785c2f470f6ed1b7f65ef6401a7707116dd0d6cebd594e51c9f54b300458397f90360fc88a0c5	1	0	\\x000000010000000000800003c3562caf32c33688523c846a4628d3fad061c7831098f95f463b067c887904a5d147219fe3600ed47f8d28e2e9fb4982b0737e5b6747db5a9195bacf16a7021f9221e41ffb4178a80140b7a7982c04c74b5f36deb8609ba767543066cdabcdf252d6cda9795853bab3bbbe5dece32650233bbd810663220504e8b2cf850d3715010001	\\xeeb0ea8112fd498a68da68088132305181a3704b3c628747b6a9186a40ff2b421470be60c09e1c1bc9d7cf87af959982d3374068d6ae5dbc9b51bdc7032d3205	1677509890000000	1678114690000000	1741186690000000	1835794690000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
252	\\x4be698b9e11e89404928764e9b46e43fe0802aec7f0e543f1c898f3415c804a4eb200bd988185897a7453b60dc07ad71ed24395dbabcf712bd0d5050e6c2f454	1	0	\\x000000010000000000800003bb8b242d8c9ccd5fc820c98cbd59759052609e4b15d9de48ee1b9f144762faa7f0373de9e2df5b508f080b34d4e3bec66d96412fe4a782fafb2c8b9722822cd916d004b1d4c1ab116df4bbae49823dc83a7b89ab1c2ebfb8e49a3a566e75a5e38386561ab3e1327f05dfe9292a482e41ac832282aa9a8a1a95079c63a055b309010001	\\x4e2bd69869c4b79e952458e1846d506664cd9d2e7e4cfc3be953fe594ea89eeba6d239e5b1744535b14dbd3e1b32dbc4852250b84b479fe822ca315071df7c09	1681136890000000	1681741690000000	1744813690000000	1839421690000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
253	\\x4eba5cedd38173eb07dc81e0f7272b994fa3a2e7d0206e5e386a2c0b8bb868e9b0e3fdcc66e9ec785f8514f4f5f82d12e6a3bafcd8aa549dee799bc7fbf02d2e	1	0	\\x000000010000000000800003b4eca8918fa96115ce36ca2e6c045b0fe26c7662e9962edbe28e0bda4263de3d9d9ea70ec5efa1272f92a99dc9a36117f7e33369ec006f0c5b2b3d7399ba0d6969dd80472df53c49660ca3775470c6b84ca07d14297d8b99298300eda0cbc057e4f7c2843603fb97da1773206eccd06fc91c68453ebc30ceb75862f57919386d010001	\\x9f2621799e3344b70d1dbcce35eecea6ccbe47a7d0ec1c47b8c67e31bc7259daf6989dbe06cacb9f24f0191cec00270315ec61fed875c22e8b6eddc8b910f706	1672673890000000	1673278690000000	1736350690000000	1830958690000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
254	\\x50466bff2da4d46552bb7140283939e3ec6f669669234f3868376c3e9061847e7c1539de15e5250906443c7d405fcdf8fd82ab559acf7ddff50d8d60427a4010	1	0	\\x000000010000000000800003a5dc9cc9c8b02a9e634706792e471aae5e12df0b5862659a5abb7a17c5117ff79b989adcf0501bff02cc88671aabc05b1ce5eb682e1a39043aa3dba0cd90bedd10355f2cd2e54384f85937aa9e9eef988d5398d24a2308f60b3117c9333d014f7270572d2f3a5ed0d9fbcac116843beb5def5af3b26de1aa7620d813013b92c9010001	\\x132d680524ea3295ed9be00ad9bc1d7cfe49670e44239684f71a6eca200dcc00bc467b64f5df170beb4ebb9cc7bf4b7a8e484418f50d52151518f5cf7fe33608	1681136890000000	1681741690000000	1744813690000000	1839421690000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
255	\\x5282d2868abf5ab6b6db0887eea83b6b3f5576dac6239c8c4786a16e483dcb686869d5cd1ac3b3c96cb3f1cf46bf1277a2487926c1034cedf94560dba72c685b	1	0	\\x000000010000000000800003e2abc7ad096783d518275fe1409394698aa7b48aed04965c899e12811ab18bea275eff9355aa20e650fab3c6b40a35faa5ce042ab706e1e73fde76d15927efd45dfbf7a33d8c04ec7cc7cff96dbdeb3c3d3a8f14ad495d5860c9dba03793a59899a3451a38754408569bb7e90ecaf09e5eab65b0c63ae7aa4a087fec90ef6a39010001	\\xd9deccbeec6c6d71721b3d2e9e7b9f64591725c71d91092684fa385807cc32718713efcf76048e64bd44a4f3cff2f7e69668b755a226ff52223e6710bf659b0c	1673882890000000	1674487690000000	1737559690000000	1832167690000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
256	\\x54564544d3e1ef5c9c0242a5db9496f385a1140ea2a534a70ba3ef215bfea0d91bdaeb0d4f639c1d75fb1a8b836ed2f15edd99b5f637483b4768a3f6f6944e88	1	0	\\x000000010000000000800003adb5e3407893101faef42eea3bd35796c16a3988647b6d2aa7b86948e545eba929ef82610ca3c789dc2f4fab317a2fa43d7fc0cd9d3958a79b251d686f9edb504d70ba990e8fa3fb887586464502485bf761037f15161bfa08e8ff2616bdb0ae5ee5605e400356a709fea0c06d1555b785cf5fa2faef473f6bcb5e6697254d6b010001	\\x30f7ce9458ed95aec05b6d98dd791fb0d1b4e4298ee350ec38baaaf20b6e2b24474e4e2095c471f097cf453b201118ca1b4af0871ea202df16710b46e1293b04	1677509890000000	1678114690000000	1741186690000000	1835794690000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
257	\\x5456a7bdcf0893e8b2105177899d58942d92bf9541ec45aab3d1d833f50b759581ac50d702b0c166482e526eb7e29c84101b20848c525375479083e70b3ce15d	1	0	\\x000000010000000000800003defef28b686b0479e085f7ffe14b7577696cb389ff3d96b0018e3df598856f3e2ea88fb4a4b0fce82cc5424e5817cdc457c78865911d9cfe7da0bdeab5b1fcc0d4db93947751d6f0202a11a48edf39486bf725ae00c094138461b6f3fdbbcb7475be11e66e0b0333778668d919704306d77cbd4a744d6b537db975a703befa33010001	\\x8b7cebf880585e8655ffd87527a24df72d9383169a0ac8edffbc5a77b4fb37879d8f321206b894b75607c705e2357b564beff518f7342fddcdb794557514600f	1653329890000000	1653934690000000	1717006690000000	1811614690000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
258	\\x574695e2e53eb43b59b1aa414596ebd44d2321962a4d1b0dfef76dac6442ffb3e009e1b0adcb91935c3f06c2932b04e3823c0ade3cf36a4f1fd8d5d265bc4798	1	0	\\x000000010000000000800003b197f5ac349524f7d36ea816ffc6378d6f9cdc0fc9cd5043529f50d09a2b7ca99dd2dd3ce890140db967d9a9a780b41522e8dbccb4990fcf63f22519418f3dfa5d131fc4b6a6ecf6dbb391b8763b5a4f4e3cbd78ecfb166057db8a6207ad7eaf1461f1033cb3d4301188f4d5b28c96470fd016d7a1a05bfbe57a9d8eecbd73e7010001	\\x13aee9f506737b19ac51b641c76b0b0df50cffa86f2d696d247dc0cbca547a0b01174f529e11eab0003fa2940551d36d1500b9479f8a7d8867618936c08a620f	1676300890000000	1676905690000000	1739977690000000	1834585690000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
259	\\x571e7d86e6ecc7474dec6d8280aadf17e79833bf90cb5beddc439a45f741aedc0bdc74cecd317e853a1aa2d48d2ffc204d8b820ca2d3ff82a785cd43e240a64e	1	0	\\x000000010000000000800003c5d9828d1aff53038a1ebfea50987f629935782a9415892f33e7548baeb86d34c1533fa4389c92134c931e1091bb08f90971f07d7f3bed297614f1e11e67e1aceb17273e6acb3b9f1dc0da242412acb3f0fd686bb1d1da8329d48f3a8f5fcf9ff52a1505afcead2b6c3c405a4b24860b1f54fe6f8650184d3ffa1eb3d53bd4f5010001	\\x2b83df3976d2a73d011462e0be4731eb0172f7da7a883ffa9080822425e122e0bd544e2dbf17659acc64bc494e45ce81fb393e665f9f64d774d48a0520eb7402	1670860390000000	1671465190000000	1734537190000000	1829145190000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
260	\\x5f8a0b3a5e299104dbf2833e17d7f08d4cbecf36864e64f5e82c876f339bf0bd882ba47fcccb4684da893672b341524d67b31daf7699412b4b71b70992312f45	1	0	\\x000000010000000000800003d471aa910301aeb9f108651b9ac940012cb6a813c0b2e63229a5fa35670ecfe3bc642613b59994535adb5c458a73c002cd9b37367a0f5866baa7b6b243a1c6e8f5a4a7c4e39c6d1719d25d9092f1625093f6fe010fa7af222340cd00ec8e3be2f4cff3b5cae9cd3f3b2a453fe601bb53c77f16aadd1dd5dee4abd3a60bc6be89010001	\\xa1bed8989484ef851bbd17be10306eb3a6c8773826176fdf132583077cd366db8542fc1233669ea2650c366953c1936a50d7cc93cfab3a09410867a2ee2f4604	1682950390000000	1683555190000000	1746627190000000	1841235190000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
261	\\x60d26a427012c73221356cb63fb028c520c8d80acabfed19bb8400a710726ff515238ddb7e8c0cb5b559713a2624d2c2478df68d432d8d3b0b77792da5fff0c0	1	0	\\x000000010000000000800003c48341dae5133828b448be6d82627382c8acccb4d3036ef6236e199c3646aa0823155fabc3b3a61899d6b03de8028c5b916212f337989cbb96f07b330f0aaa93d19d7d51dc53090df9c5e3b886ca6b0d7c7948731a55e7e3c0a557632d54c295f901216968b05678660ad9268246a1c7afcc45090c9bd69b289cf37711c0e2db010001	\\xad374a035da6aa117ae927e9e8b6c753e67ac9492da53967135f3979c59d7cfe92be20bcc0dd120cb11d2f840e5a281b7e3815557a65ca91e07b637f98c4ba07	1669651390000000	1670256190000000	1733328190000000	1827936190000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
262	\\x637a25692f6116815aedb53385ccaa8c833bf8383e20de045315dda4b0b32df44896dc772dbb15ae4244577ccf21cf45ff44414d9d48ba8d1a7d9068d5638e0e	1	0	\\x000000010000000000800003bcffd9108e5728300bd9291cf619d2e48b10fb8f3741e544cc441e3737049e207bf20c3b72e872105d3b4d4749868829e09ee0ec5f35afeb5e64f9575bb37228a2120a4e1b136c9115252897ff7112ab8bf62971d2e2e68207bd840aac588b76679f142e6e2cd334e85a96acad9a4c2bec977a2eacda9544005bb4a4bf710065010001	\\x7114f19f1de238126f13f7b58dd52336be3afba7ffa7078750d87e0fea15a3dad230f4f5d984d3ca86975d4d4a079aa4596a7489655ffa8acfaf85ab2d3fa70a	1676300890000000	1676905690000000	1739977690000000	1834585690000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
263	\\x64da0cc8355741f195407e1837da26d001ca5020083b7fe03562010643b3dbd41d76073101c9f414b194656384adbf4842a7454c26e2019083cb3eedbd941846	1	0	\\x000000010000000000800003a06c05a7956769697f119214d247e1e5c59a74659a62fa1c75d3bd489dfb14b3965a5c9f7d38dd5d00612884b737473327a3f554d4df4486b5f8a1d66544b05bb5628ea4e5ad6267528f7ec701329511668041d59234a49fd8963ef453e77d2afd47edd744999355d39d78a0689a698854c922f35bf934ee61f836aa848338d7010001	\\x21786cd2501d65ffd3d4f46536deb25ee9899fdd01d47c94df9f1db6685982ed5ae2cce1282180c5ff927c1e61648bb9c871328680d9e9a6b52f435788ea8e07	1667233390000000	1667838190000000	1730910190000000	1825518190000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
264	\\x6736b544a1cb9dff71cb65e66fb56a9ad3cd7afb67fd468dc5197fc48b94e6c0e02adbf21ae4fa8845a98e2e59cf4702f78506262c515e0adacec68c6552cc47	1	0	\\x000000010000000000800003b8173e00a3842a4a49357a1ff645d301c8d7a068b4b676a989e303053b512e394236e2410c3cf0caf4dd5ee1e2f2632fc54746a4c9bb37f19011cf06f56656882bb1f21027b42468c4149eb9bd2b1ff52af201b29678c4b09b17642946e85f7124abf509f7878bdadbb6dbd59869bcd853936fab6bd4ec30faf3a45669433343010001	\\xdb098986235fb8a2b1789f7f78d69380ef4db4591dfc9b22c1440f20b24e5c24c05abaab34c964aac5b30f4649f13e63de6aa6bfb5e90def86c10afb0b21d600	1667233390000000	1667838190000000	1730910190000000	1825518190000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
265	\\x68deab112286e15cfb159a76a8bf9388f383181c4816c31eb27e46d4bc1583b0f7cdc9c33a708185e77b1c5969ff647a917252743a22bf07760d71c5587217a3	1	0	\\x0000000100000000008000039a33f8ae693c0b2b67ab3308a5b5c794260b63ad86750a3bbff2e7b2395bced6b3527e94312a0be6d2f3e2230df2c5891781a839db5c0d5af76b93468a3944af5818997a304f72536a050a3cdc8570574fa5fdde36923ef04c09bfcfa027bab33a15ac3cb5e24df89ac5b87da2fe082ed3d58dc12ea7ba825a1e7bf53fec79d5010001	\\x9f687f631d768fb9ff385b782acd5af2da1b2790cfebeb5802221dab256bc904a74abf87d1b9b8be998b9b50465374f30f8da0f403884a9fb9153bc32d2e1a0d	1682345890000000	1682950690000000	1746022690000000	1840630690000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
266	\\x68eeeb5d7c6e1aedf52991450e428c18affb03bcac0833b58c3cfc2bec22ff1e210455715e73bd43866ff1b225927d8a5c813556dfe88de720a344f86973b757	1	0	\\x000000010000000000800003ce782f5890ae5592e973051af72789c2bea69f6de6c1ca45ffe5730803d3560e37015272a8814ce50b9ded5a774ffcb3a89845214ee0703f3157e5f6adc3edd3e1558366bb83b983143b7bbb863ed113448035a0b0888c20a1a1e054a142a2bf826cc9d7f5f9559da9b1e8b0680d1b74b1bb412837ea4b57c2dd819086c097cf010001	\\x3fb0fef527d52d4595682d0eef6edf91ce3bc4fd1dfea8d3527ac9b3874af9d47e5919f7abaaaa35094378ddf37a0c1c7ecba0f82438513f199244f4db8dd00f	1660583890000000	1661188690000000	1724260690000000	1818868690000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
267	\\x6ac67f9e85ba8a6bea1002556bf18ee5682a82497ef204623ca6d37c6c8df19bcfd976f82a005d879c0e87f73dbfffea32e5b30fa8cdc413af740e423fadc5e7	1	0	\\x000000010000000000800003f8927065fb7ef7138505c41fed13e3fe5042f6c46e508e415cac0f62bf9857fbfa2179c5535155ead2c508dff8ac59407067b4482de12d16839f0aeeec46f76b2452f65e3df4d434d3d6a85e0c4f1fb3d8ea48c57c885245ee85c40e17f42a4e21ebb29932e52ba838892ce003870a46e5893ba61363cb5491d9c90b71ae781b010001	\\x03fa6066b103b4d574304b5e6de46fc58b0a855e13834984bda5529179327c2b3d1a879572039c36f3175ef1274caab981f1f7bf1954b7db4e2c227b8af8bd09	1668442390000000	1669047190000000	1732119190000000	1826727190000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
268	\\x6bbae4334eb1aa1d82373c20f67c754b0ff2710e4d8d4be03515bc1a120b88c53e0bef6a34221625f4d766ac359e3bb4d44e0f2a28702c1142713b601d4e3af8	1	0	\\x000000010000000000800003c8520aabedc1b60cbd65856bf909db4929282ad27e1bc0d6aa2c14a80ded97f15ab34dcee756c1f82392db11500188810866009e2a259e7e47663506f24eb6510f2585507103db38266a7f6c8efc019ec17b58c8915b5421070f15a5e392af60b82ff6621c4bea7ca7c9deef83fabae7e24618c93eab23a71b4c3f15e29434a7010001	\\x995b71b4acf0981a5e77a1b525e89ea1b45d3f37130dbe4285d8293fc6e0b4b8cf5405b44ba82322fe0dddebca8145d3915d89661c0a0c03b29c47bfa16ffa01	1663001890000000	1663606690000000	1726678690000000	1821286690000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
269	\\x6fe6a2772179fc768d9a32d1552d2cf0cb847784c9910b1cac6831805797cccb7cb6ec472330ab1083d3e343b60d35b30fe93951cf8f27061cba02988c4aaa62	1	0	\\x000000010000000000800003eded61021e419e4558d5ffd935e089c6212fd1a42ae4536f66bb4030c4512e63b7c998b298d026b8376d81eacb31cd17c30602effefdf9661c7d6636584138ad227892909395e3b596f107e4029ef25dd53485f5d04883fa9d8671bf9f68677845c90f8f2e29e0bbdd84d2034fe07db59d87e2e63972dff4230ced6a96478555010001	\\xb2f378b8d112cd7f31df71228850c4472e7912def4a2a065557c8bad7a641514059dccc3d5ce1ec1e995bc92eb5b53a80f01b7a79003551060cd82e0a3b2310f	1664210890000000	1664815690000000	1727887690000000	1822495690000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
270	\\x725eedb5c86ae9515482b90e6f7fc4357a330bf3148a28b8b0cb34597db05c869466e9808ee69cd22fca565070443b518b9da0fd1aa21b7fdbb0f98a26321d86	1	0	\\x0000000100000000008000039b62fb60e96c51981366134e59d860fb52abf12ef500d2da6a5b6e6bbc090ebdb070dff23909a5bcc732f3eb9d7cbbfa2ef41336b030686247ea2c26b40ff0f5f05caf1de159544dee41b04bb7a3637ff7369641d1803ab307d6701957783afc46fbf494baf50b792f7c3d50827f5f528ad6c4d746c5bf2fb031d55f12b5d451010001	\\x9e73960e407b345486c3d28411c7c70ad3ddbd7eb62892cf23d18e7df86cce52cdf7ae53addff4181233643cbc9ee461fe71572931d7f848eeb11c781e3d1e0f	1669651390000000	1670256190000000	1733328190000000	1827936190000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
271	\\x7346a97810e8f37a9320e7e2b1de9e8e46e385940d53d6b836d93e82ed34d6e324738c1132362381ce112f2fc2be9dfb931e5c28d00907d6c500c96f99b598bd	1	0	\\x000000010000000000800003e0b0680868ce1004ccdf979b0312efc7f40d8ce8e3a28449e069207f45e8f0c620b531c8b96da8f3843356b41d9ade5239ff7e36a0776cd6ccff09c72fa12f38ee0304e53df6b2b064d9d50314dac9182ba0598a3fcd53db973f7d83a7dbeab8b07fa13aa99e887e5646e71d292b3516180e3331efc2ae61722522018db574cb010001	\\xc7003097136b9f71ac0530481ef530a8a0234ce48b43f2acac441de90406bf32578b3e5437361b297b6d38e206e1c856f1d0f0d8c68363640b6cdcaf2e2d4302	1667837890000000	1668442690000000	1731514690000000	1826122690000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
272	\\x797af09728527c2b4b8149c374a147ef04ce136ef5c642f874c5798b099fe6fe14d06cafcb777fd96d8da59c14e7309a3ae547797eb69664bbbd04f2bf825bf7	1	0	\\x000000010000000000800003e41d33ff21311cf22fbc96d69379364f3b4e8f01ac1a8d3fdc6fd0c0f74ad14ce756d882a7153d90f75938c0fc6bf1ef9b684968c53d6879e36e6a3a8ca7f0099623eec8382b5348f161a961ced1f950a5fb9a20cac8b5c18a56e7156cae6dbd15b8cc1de578003f19f8b338f712a56169d5381a235961f4c0ca0ba8c2ff9943010001	\\x27bf72b60524da8b8456d51128155ca03ef3ec3e50cc032004cdac653e385c493fd2db6f869e0744d9ce2efdfd32679f57894a2f6eeb2e68f7549f30e947470d	1679323390000000	1679928190000000	1743000190000000	1837608190000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
273	\\x7a2e17677d08fad702988101c5c825bcc92a94b0052057a11a0d733c42aaa17aa431d00001444a559891aecc86ce6fec15d809efe1ffd9a98d656f883a6c093c	1	0	\\x000000010000000000800003bef451a54aac754bc11f1a2ceb88834a0c151ce4fd05f3c1a9db265ca05914bf498ffb717cf59c22e0df12881a1247034fe666565406f5d30e73be0692340638ca4af93a5d26ac1b4e1fb99cef955446b65be1b2d47424087008a0c32a7dafe90e9e8d90fef8cdfbff08e1cb560dd7c99e06fbfdbb45c01a01f69995cb58d573010001	\\xc09f2d6aa72166defd6792bbb9b2937a8377c572d7f5dc5b3caeda9bfff89efb91020aa57f35958a43854379b9cbbb4920f475de36777992be4dca4a6893c604	1674487390000000	1675092190000000	1738164190000000	1832772190000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
274	\\x7d32fa498fb80f2677c4888f17a2eb8ae702bb0eb42efff6221d20d1be2ac58a00b4e84bbc958f06e491798b099b3b490106b6f4627b7c577ffa7ce685c7963e	1	0	\\x000000010000000000800003b64042f126a7fc64401cc12eeaf5d56ef7fc8b5fdca0d63bcf6ac584c7d99931f439cac3982152639b067d14d4af21fe5560a6111bbc77a6627a059746f01a2c0a8621f5ae2344828c29e2a10bb5d7245714026ed43feefa84c3578ddf51f7f692f9a3a0738fc9a62db5251a23a1e1865f1fba4bbf62cd93bf2ee9bcbe90a8ed010001	\\x8938636a81c70f961282d1a66fab60723ba6777fe64bc4897bbf96debaef6f40d7afda9671b688cec64ea943d4c3a0f5f3ea5d334890d5f41efef53a10cd460e	1663606390000000	1664211190000000	1727283190000000	1821891190000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
275	\\x81a298836d289f8e8ec1c11072c0ab26fa31a9b207d6945232b72cf67e17f7cd4615103561d3aea8dd1cda77ec9a1f7157a99c544382f2b062937ea83807ad92	1	0	\\x000000010000000000800003dec6197ec5b8bd5a69d92ab3ca7dedf8bccd1c11ed46105a823b4b5c9d357ba1cf3286bc3bad26ca1edc8acd6c9b283c2bfd1010a4d62717e4ceb1865c96d5d8ea96788c43632ff820866ee0cc366ff87028e74c04a9086a83fdcf64871cd0c0c1468ce1cd495cb44701870727f03a1cc9e32f5175f1cfa70bfbcfc978636527010001	\\xbf448d21fe05dbdf797c44897976f7f66548bc73cefdddb60d6aad9b30c898513ec8b45ddf79d135a948ac3d69a239185795e4cc95227f77295674b27b383a05	1651516390000000	1652121190000000	1715193190000000	1809801190000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
276	\\x880eab9107c2330e8a6fc11b8aa2c90c66fc51b8cfa928ffb6090ce147df5e90d6c8eb4dafd3a0d83e965b60f3b42a71a1be0a3b61d87d380ef4557bd70d30d1	1	0	\\x000000010000000000800003c4d1c734ae196f0b8236dff16b3fcd35bbbacd317c0269b12335f758d71c4119d04bc3afbf8248467d3bd98331b94725afdf7e46c7353a910c2405f41345fcded817d43eeff7d48113086169eb1371d1a5410bdbdb02a2c6fa28b25a8fb7d9facf0e108dbe0fd67b6a504493b90c1b54405c024f49b0407df8c7031f8ec09d01010001	\\x3b4bf337fb5087f7efb4de4529536f5c5abeb32ff6c67abf486c8d07a07c3175faa057eb4fb98d27eb47ab9661f9c8e47900d05abe9d1497715535332feaac01	1682950390000000	1683555190000000	1746627190000000	1841235190000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
277	\\x894a4659db515cb7331510ff26db98894b158b6f2555fe22f6dc971fb89b6bc19c7a010b1765cd7dc795f3a183403ec473e806363c12b7554e2dfb1acbbfca23	1	0	\\x000000010000000000800003b6d3fe241b424dd6cad30038f129b504bb10a4c01711766d3adebdc8b58428a4593a5d703326c55f18910ae28bad0391b8c6acf217a1fdbc979a7017dcc3a13a23f6e3aad30281cfed5ede1424f5361482dfaf63f19515d052c7cb977302ece747e3dc406485c946daa3be795aaa8a68da7d17233bed36a56fb1d29fc7e70055010001	\\x92b5de78b3215faddbf5f4e8cd028fef921b0e3f7b4a9a917fb028f7117a6d94db07313eeabb5c2cab38b4ce3e8f35b31df719fcb4c755e98d5b42046c8e7c02	1668442390000000	1669047190000000	1732119190000000	1826727190000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
278	\\x8ac618a58442d37424ceae1e4b90cce15157a79424b68b63645cfcca40047b8252dccf1c75891326b601cc00a0a8bcb72c1b3c7e1a2bb3e3f0c4bdeebfecc872	1	0	\\x000000010000000000800003d172a1203a0324dba7888dff8e824388f05d71723f252eefc60210b1ae5ba8372ec2249834bea0c479270fdcacd504ae9e22483aaacbc32fef8a542bae3f687b8b6790e6f405eaf35e07b9fbf7e6e6181b78f8fd4d80ef1348066af77ab0a48ee38c95e362679811db0a66d54cffe2ad51d14d14aacc460e486c46c580bf24a7010001	\\x2d5fba07b56579386097d68358a4d7a7733f4825c1eba20e57ea4d7001e2aaed320f04fa7fda0b4ff8e82371e355917ef159de466ad97cf840375ce5971ca70f	1673278390000000	1673883190000000	1736955190000000	1831563190000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
279	\\x8d9a0f4ee275205f68d35654e4ffa0bc9f457243f36502602ed87ea3c691f6e0b1636f324b078ac804ad1329a07d80265d787f3f9ff930ef3dba99504e2fec90	1	0	\\x000000010000000000800003b66823050ef2e1685f60d10e6fdf8cbd30a582f1fad39fe079c4b2381dbd2a84180988821f3d8e7de67f90dbbcbfd11208c71e5c1a6ed7e849fbe60514bb82950d27591bc15cd91967c56a445f6ae8f800c8226edab403dee53ab485f228581694da5b7f58cf6fffc242fcf09b667a43542e07f33400bfb58fc2f200611b1a57010001	\\xae917eead4c8bec4377065ea49b9813175fe1f173f1cf32aea693c1ad0b9887d504e671358db08cdd62f75c2138a145b9209378fb54f2fafc57a46e215b39809	1664815390000000	1665420190000000	1728492190000000	1823100190000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
280	\\x8f7648fbba638f8bb66215f7c23ff3a61d58afc950fc30fa972d8c8a770cb62bd9d2cc077fc8d65ed0c9977792972697535fded1c8ad6c5d4d969428d71926a7	1	0	\\x000000010000000000800003c3c18d0447d7d7b560abc5d864dee0a08d872ae7860cd144396d7c130a6870cd1f40099891d83f893fee2e4727e37ee2bce5dfd9f99c4374c43e357fc20a47ec7bdb95c71412da816a77491b75c1e438f076d04f478b0a78797da56374ea14ec70abd91d87897f44dd96cad601624298463a22aa5d45559b7a27c2ecc851a845010001	\\x99a144a11fd335b21a08b69275f2cd03a6d03968032d8e559caab73cfd1236ad3f187542a627a1db8474f82425cbc831d545595a0ed7da2775d9ef45a3370e06	1663001890000000	1663606690000000	1726678690000000	1821286690000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
281	\\x9056757e96e4eef014c86f93e96cc509998dc593d35f48dc05e8de462b9b3ccbedec6807bdaa51ba26b03b6024d314a075ce52a65393b76e2a3f201b0c6bce15	1	0	\\x000000010000000000800003e9ba68975466c1cce9800877bd99807d7b1434c908ebfaef9283157386a848ea557629db026a80d468937c7d051d1976aaa3199b8a06383bc87733c0a232ac1ea10cec0deb8043880db76b2f13ce399f89914310ce2c772ed9be4460925c2fe004b1f36eaad35abebb942888322f5869acc56046ac4cd65499e17e5cfaa0392d010001	\\x09bc35b4d96f1fcb5b142c48e8afbbca8c769fd169ce1ebd7c536dd1f677a65421aa17368c257bfaac9e7bf938f1f2177ec7ee9e884488dbb95d02baff2ad502	1670255890000000	1670860690000000	1733932690000000	1828540690000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
282	\\x9416d3cd931c6a8d2c258308ebc379fbbebcf3d09897959bca6374112badf858883b887bed677454e634d1b2ed9f371aad85a7082009bf6861d53dd457f75299	1	0	\\x000000010000000000800003c9b1467bca665772d7d5ae7fb659ba73f8709071b25e68747cc3b9de944b594702a2534b8611ad317b4ea0c876cf2529359dd2a2dcd11a6312c8d9fa3adcd9bf4f7906b194129498798e69dc7d5272389776645e0fcbccb799687ffc1e6d451436c04ee04a9c010faeb26a5e35bf85b29fdb838b6cc0cfea6019373aa3764d73010001	\\x558d4449c952d46c088fd533e60bae13f3ee9db2e0af8eb59fa75feeddb664ecd090e8ec2a6effe698cee305044f4a385fc0f5a4cabbb40f0bfce0ad16dc430b	1656956890000000	1657561690000000	1720633690000000	1815241690000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
283	\\x945ae261cde10dc647af3a8e4464784b09a42975ad1cd512469638a2951f0b285fb016b47d707613f28d2982f74680fffdcf82c616173bdf159817481e488bea	1	0	\\x000000010000000000800003ae7c56e8255de611acad1969aa05e84fc14304bc1459a28e6fc5296c9e061adc555ff68a457cb5e6ff77a1f71fbfbf0ffc7ec2f2edb24583e45e0d8d39c490468481c4bdd6094aaa02394a1de2f4f0e43168987029f0ce0bfa63951565a62bcb5a15b8e7456b11e62e4855a366963b6bdd51c137b2c405e219b9db4856043469010001	\\xa8c9e5b1b58cd0e72941c9b4431c694857422e6bc4742bc3c774940dc32a1fe412ab558dc40103ad79b4979dfe13c7bd4906ef0e0658112e967bdd57a39bfd0b	1661792890000000	1662397690000000	1725469690000000	1820077690000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
284	\\x96baf7242115497e18bc963546c2a48eb810b5d3fbf13e8634ea5cc1f390eff482fde36ef646cec107de97aa6da98d41ef042cbe69218b5bc3ce664afe554f9f	1	0	\\x000000010000000000800003b221534c4eef0f293f00557cec013e3327eae1e05a4721355da2676f4e2b91958b78dd0c888e6b591372d4feedbb2a66ed0d83175c790a33995c93911a7d684e33bf8153d610db577887f510b5ab52977fb58eb20d9fea1dfd4f08a1db95bd4d31cda833e9473916954eadce41199f21f5e3f47c1b7513e74dd718c993128145010001	\\x6c82ec441d7007639bb22137a5da7833cbf03b3a8c5c9a2464d3b55d7a84d00e44660a3f35dfc69772095c797d32b08e85579aeb8544c473beff248ab0dab80b	1666628890000000	1667233690000000	1730305690000000	1824913690000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
285	\\x99ca85752e38acffd343f7675e67a7c164a0844a3bfb85266827222fecd368408138cba11e9b176f34b97e2717a3c558708814640634ebb86cc6558efdbf1f21	1	0	\\x000000010000000000800003eb034746415bfec0ad4ebcd10e00a7f3d77070a445c1ab58f85df7cb35eb63c06f9ade1f26d021770edca9fc636b3df72a9465a4558263fea88e04c516a8d78aaf1c772ff1d208eea1af00fd9aa221c968081baa366c28f4af9952c7ab53dc0288933e3c07292e1921cf2bf1c66aaf0053cb51afb7667e76ec3dbeb64006f45b010001	\\x4a518ec63f087b9ba43bd03919914aa84e09600ab0541b449936ebe72a5dd40d4976ce2020fbbb98a18bfc8ec5107636996c22e08e66fb1205175ad1c804c106	1666024390000000	1666629190000000	1729701190000000	1824309190000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
286	\\x996a1611212283aa781b5fb8c9aecfb812f2ad2103fabbca62b6b50165ac0a64fd2b248cdd01fec619d7257c96d0197354093de2c6d1df9b27292ee712aa2703	1	0	\\x000000010000000000800003de7dd5a7142e081ccfef4c93f2a12f7ba5da8441139465e68e32f76b6049029b5ba99796220ce7c1a6487daee53d19fc756a5e1e235cd4bcfc9dbff65ed6f2ecbac2ce70bdf07879bbdb40d8a622ca237a7ae6a1393f00188a4f742280fd97269be4158408ac1b54a8d648cea2f0bfe7627312990e23925513c45d84c5b7a4b5010001	\\xd1e9b130a482ad63c43c0f8cbf32b03152b0058c20fd2b12f9ffca582d9a2fb0b6a805339234e4d5825ff5b0c92d52d83f4da43e2f315abecade0d553ddc8903	1664815390000000	1665420190000000	1728492190000000	1823100190000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
287	\\xa5524399b57dbf4d1ee78c73721ba52a689887cbb4d5afd364ed997b4bde299000d3fdca1490171d9356734b0cf125f4a7f4821a9737f223eeea1adf8ea08084	1	0	\\x000000010000000000800003e5bde262ef0bbf3dacbeeb6695199f8fcb54409dd630655be5857dd097733c2b13b2fb8b86020210129be4e317b37d6f749424a5e91e9d55cdac96d469f6f03c59b678d26022fb6b317d6008ea54281a09ac6fd2c1ccca16621826075fa7cbc556ba5f0d1ebc1b9b632a3501bbfd9fd2f26cb7a020f5c0c8d234f1c1c43a41fb010001	\\x1c8a5700ae4c0bf202c15ad30aff63fa13efb36c08c683fc7d94e22d85ab13fa326e624e818089507fb702a70c19b9fd45d5e5f4116733b94746752d40359107	1682345890000000	1682950690000000	1746022690000000	1840630690000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
288	\\xa87a5350828de107033e9df2bd04db89260a5ba0de8332c5c057cf22607073e8be33f3175195836d0f192a79f659e4213619388b35ac8e1d51429696bb2a69bb	1	0	\\x000000010000000000800003bcbdd09201e399e172734c75336acb8d7486adda3c55deb49af0397bce34ff064ee878d8bc34b6a22e4aed743fe119859bc27baeedc31b131c2f4a24d1bff8967f0645441acfab30f8d6fff10acba5e759a3193021110c806e4bffa4a32c4fc0001d050c10f6a91d5fbeb919a7f86950b8a611be946d3457421fbefc0e1daa95010001	\\x10130da3befc25eaf1a7940fbb34cc02671d7e51893be539d0ffa45ff2266faa9bbf227b1c44c183117b4f73737d497b84e4d3b5fc05b3c2186da4d972405906	1670255890000000	1670860690000000	1733932690000000	1828540690000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
289	\\xa87af666e6cd0a1e5bebaae42616a8c25cc0f7b8aa0c8323c6be05a1988d6b3a71693c0e79c666f8c34295a3fcb5e0fcb2369ce4b6a0819b03f5323815d0f3d1	1	0	\\x000000010000000000800003bb6d04e307a52819ad04234a52bceb01e3f97be5b352a38ffbe1b23a9a483463fdd83497cc19c399278d450f7ea245dbc8d8e3955c9059961072f0523be161791b5235c6807052debaf5292ed1a5c12d06e53efd5b1d4046a216aa5dfd29613a3d3c6b2546f2cb22f737939b44f7524100fd2676f33e957e9c96ffbea2f13b33010001	\\x77b595c15bbaa7809703b5e2ea89397d53fac3a6de403ff96ef5df1d1327abaeed21b21d7d33b404ae9b6829d6d0f955386a6206cf29671b5727d94bfb92ec0e	1663001890000000	1663606690000000	1726678690000000	1821286690000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
290	\\xab768d2d800ad091466e93e1db603bd0aa9a85bf67682b8c3f35b33eb41b0e98be6be14e50eddb9c35aa4a5cd454cb7f8e3c53c28271946c9f2864295259f4ec	1	0	\\x000000010000000000800003b710cbac5645bd47ea3da1624d5994392aed11d66fdb90142eddd56a4ccf282353a354f229bd1bfb7291d04406345bcd2e94a3cd116c308d7100599503ca3355fd0183b9bafc91e0a481c4b8b5c509e29576429e191130f1435963abd051d3399e9a732ceb9895bd96c5173d66b0468384d5cdb9fe3a4e58944766428c28c797010001	\\x7d064913cd345abbefcb6dd39b21a466469a93bb070e3122476ce14a76e98c9340474c37895f8a9a2cae081101482a0c2f6b0d4355ed90003aa6bd4832c9ed0c	1673882890000000	1674487690000000	1737559690000000	1832167690000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
291	\\xb276d70815969a9511e497606e162f312b5040a7af82d0771411f52d4c36c113cdf3a8a5948d0ab752549ac5eeb94aedbd4764aa1cfe1db149e03b6947508e49	1	0	\\x000000010000000000800003df5dfb8ce2b22d5ad7d1ddba694c19007ad8d35ad9833b2c273d4ecdc22123eb22739d35bbc0218a6d094d73ff6e66c9541bd70ecd9db6161d3b11b876cfc0b5453a7ab627bc9d01f26dd6d95a98cbcbbba91ee07aea06a49a2356b10893746251b6ff9b8d406f73ce15b8574ffacc312c22091c1e76c5da175daa3fa5dadb7d010001	\\x9f0a142bb64984dd1d17b61b9ca9aa10b50e5153853c3a36e9059c3329e6f39c31b524d896f9382ece255040ebb2a8feb113f0d575a141aa0fa82c287bef6404	1656352390000000	1656957190000000	1720029190000000	1814637190000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
292	\\xb366f9d4db8472423ae08dbcd0332d985ecc128622d301707ede56efe04e11ffed1724b0b2b11b3542f01b1392c40043b7744b55b268a646db5953d9d6e2c22a	1	0	\\x000000010000000000800003dbb5569d2763f06d1ee4623030cd25af7cb11ca3c6c50ed79934c71ea430b0c3e1a9d6d703f54d0102d1056c323b167607ba1e33976aa3a7329e2196a822a3892c25cf4cd10c58c820c202ad3e6f3afd7282460c598383769428fe7c040c8725191f73dea4366ee5de87c658bc4633379876d8e5050ed0f4e877e94d98e736af010001	\\xc9b9ec9b438b87e5dd26b90a1e2d3f4f3f6d3db82a3afe35f6a111eb5f7346069c09079ffaf95c5d6a33afff6ca004c5b4254501456d284fd746b754ede43d0a	1653329890000000	1653934690000000	1717006690000000	1811614690000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
293	\\xb7b62e9dcbaf6daf8353f999b41205433db8381994bdfab71052471bc2eb8009b4accf96b31625edb29cf1f133072a3cc636ef8a7115c782b4797761a2d0f62e	1	0	\\x000000010000000000800003e9ef9d28eb8e2408570c9a654aa4fa04783c9740e693710d43bd241ef29af74772d364be1a811409dd98fdba5a4105ebfd67b940ff53e99a4f16d0631e18efdfdb0631a9d2785683138a304dec2af70699cccc0f4634d31b201203441438ad5b12beac56705164c22ccb2998324f413e4e75eceed287d05f17b0347502a7352f010001	\\x1f64981969436c65eb835df5d4c4fb3eaee04786ccc57f33e3b6198a583b4b1df395fa5873fafab036e94f82128d64cbac4a59d46dadce2451bb35accf4a5a0e	1659374890000000	1659979690000000	1723051690000000	1817659690000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
294	\\xc1e65e73218db6c6bfe68d0ad8dd91c9bb08ba6b925883bf84cd53303a4c27b8394d56180125c8f4a88b1994b03996c40c4af2a5f1ece94b4b1aba236af13e18	1	0	\\x000000010000000000800003b79839fd6567301b86f66af13bb91b8f0ca5236997d812892e587afd794db90fa68f0df87f7434ca13a33f669e3529c59b50da70125ed3466bbb008d5560140a5222f0f0bad3733e925ad91d5851b4877b5258cb73fbd7b6152bf876e3fb5b7905fd867f915148c54c8adb02968f6bfd28369d9f582e3db8018c8b011829abf1010001	\\x5996df29008bdcb3458adb278a0e4b40da662f0f8e5cc05df1a57b474a015cf93d5700dc969bbc7577c1b27b5936ad76391fe99a0dde48321ff17c886984ed0a	1675091890000000	1675696690000000	1738768690000000	1833376690000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
295	\\xc11af31113fe50df16a2c83ff80ce1ab656b936cacdacca932ebb8458980c9c59f335497534ceb687c33e312f1bf269f6acfd199b509b3b9fb3264cb99a78d40	1	0	\\x000000010000000000800003ab62764d171c8994ce60491c31b5f9037bc5aaf8dc5571b097e19bfa337c3ab148f42860aa040ae2d9bd935390ccb7e2c6a418dc03bff2fd531a3a08e4a1b39e1203783623470e4b71ec372806add33a1fde80ff5632f054b88b07b868034a43c0881cdfe02cfbb88aef55eab6d924cacb4d80ca19cdf28c7633c0c4ee102aa3010001	\\xbc08fb6a4f1f0be42e9ff76cc6a2ad09ca5baf00c283f2e3116db84d0e83312ca2b436e565e5cc79fb516802a870efd5cc8a2dcb6f12316f4bbdea274d23180d	1671464890000000	1672069690000000	1735141690000000	1829749690000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
296	\\xc2020736cb49de494cee844bb600f508fe4b7c687b03394dd99958130cd367fb44a9b1c55e1c58667a3c9fcf20ef888f393626ce5986d7881eaa2b4a36ba5e8d	1	0	\\x000000010000000000800003c803626e3a1a539dc95294c73243ba028bfc10a1ade0c9c82e09e360f6c50fe5143a18532eac0d733989ac5b3f799d8075738777f3483b74bdb6b351dfafaf679aa3a8bfb9f62b884fdac7c6896ef418f3d6827c41984e3a348a2d859750e550f7c57cd44400bb238d19031397730aba8173907d8bfa1d39dd19c30c40395caf010001	\\xf491173c15443293bccecc98d199c3d8b83b8cd01f3110093ca43af1480821e0d536a4d7229a90e5f304677dd2044123c0e63d8e094926fed5c35f219231b300	1681136890000000	1681741690000000	1744813690000000	1839421690000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
297	\\xc346768cd7b90c712720b6054deb0b7bea55fb74b0536e5d952f4ff820b6369b08525507972335433708ab8573559fb108b7f44a6be1385dfb09b1f7edeba253	1	0	\\x000000010000000000800003d9cf6d73e0e5b773daee0f90b26f14ccc40a9249ef61f6ea19919d6474fbad40527b675df1b97eaf4a70f297a80ffc6c514fd4f915e8b487ed7885c6a0df296d931205a5bb6f688691bd2c4a11b408dddd3dd69ec06949b4c2b04cb12530eda3fc455f89424740c89ef80c27f4907438248a60c19fe93555979f335bc53cb4df010001	\\xb4055b483d978ae589fb66f7055911d78d59f519cd4ba85b1fcabc3c8d4bd9cfbbd43d272f5819a1ae6907ea3868d824e14ccab7688ac2dd2aaf72f99dc11f01	1681741390000000	1682346190000000	1745418190000000	1840026190000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
298	\\xc4b238ef691650ee3c63804d4b88991e5e709ab87bf00d4b4eeff6b63d16e966f4d15bcaee6f166a13e93ecf5a94194ff154ed5d993e14af5b22e01d215b590c	1	0	\\x000000010000000000800003c65cf8ea8fcda3bed8b85b229679acfbad6b53b2b2c3dd1ce8ea3f8a05143f73fbd2219d2db29687db1032ab501d48b0a7e6d32e60a6bde88058cf382ed40810514a64299fc5fbd0971d86631aff7d7da7030df0e0ae45ea56bb5b2683c2da266f3795f604b4659aa2116327b0605121032d34759cc2835fc7a446ac4b553a07010001	\\xa93d40d3873138bad2f3db5f461dbdb04aebab2f02cfff018d33a8ec760536b3298e930d0055f5949a4fb79b558c2f22845fc732caa6e7db27f76013faf2ff09	1680532390000000	1681137190000000	1744209190000000	1838817190000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
299	\\xc46e56fdbd49ec809c357e2bd16a587cd0f4cbb21795fede06ba3dbce4b612e80c6dea2b6f09d6ff261cf446027cffb7176a86616c834485f1d775d4791c83a3	1	0	\\x000000010000000000800003c8df1e9704bc04e3a8163d02a9c220caecba45a25383b08a89a450bb380e70125478cb10f1c27ba6aee2c9ca979e4b8d984f05472d2758c273df68d12755858d5239baaa0db72f477983048c97de016b195a169ed6b44824503a53a89f91210c3e1cf8d029eba513efbb172b43f4d1994295e2b5e92515db71c70080cd31b637010001	\\xecadd83d0e78edac359db3dc0eeb7c9ac6d905c757fcc2be391728faa852d888e20a10f10603750e9ae5ab420ccc703bd514cd928ae319fbf4945655e8be6f04	1651516390000000	1652121190000000	1715193190000000	1809801190000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
300	\\xca02e97c611897b230c3005dc082381e3555870e0d672a09d3de729549ed29f78c2dcc12fd56df41ed9730d0fa131285a09c039aef2b91c135e6f85dc77f32fc	1	0	\\x000000010000000000800003c7520d999e6e2c0de4bc67827184b863df1af172c86adc65a0e5acac4fd25391f69e457aa204b484831a26f65dad61d7a520efa0b41dafaafcc4201de78e7a06727d8cb68d7a1855f9c0a26e977265f8c8b45a4b22c812cd00aa6d341533374b03fd4a3c2ade336b68a955efe68d0110928e6272e0cd700ce226cfd977796169010001	\\x99f429948f13a5d1cedf9f1d3f56735940588e8eccb055fd029dd2a807e12bbd1b0fa10faa9f52d97854bf619407339d3c93a3b6f70856a81e1c63afcfcc920b	1659374890000000	1659979690000000	1723051690000000	1817659690000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
301	\\xce4eec0ece69024ded55349bccf6fcd97d7e152eeee6bcef9676bde4f8b4e6efd09fbe77f4b9242b03594752cecc2b61584f344eb7200b347de34b8cda5fe034	1	0	\\x000000010000000000800003f48d502655a759b514524cfa4c01030177a8fd2611a48c674b706c727e81bf9bcbfcae09489b3018bcb7cb2147fdb74baf068d1abd1cbc13bade85134b080deae733bf7855ebae37ccfc1bd22efc3c6dd4c24774813c38ce495d6b376770aaeedc6fe6c3620077559c5959460ec263e7b7c96170ae806af17e2033419c9a6a95010001	\\x9d1162c99f75d47c860afee3bd12dbcfad45cf6016f3585b0d0813e14b5dbca05bf54da90dc1c9fff240076247cc101fd387ea1af7e38f4fdbfb419d0e30830a	1668442390000000	1669047190000000	1732119190000000	1826727190000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
302	\\xcf26e70ff7d2c99bb52286a999ec94c0566179e80067759e7fa2d54b57b3f4d51c478f4eb22648cd9cf1585cb5de420df53205100699a7a23c6cd847a910b3f3	1	0	\\x000000010000000000800003cba01d96946980fc2d5a422b322997848afb04a9a45a3ccc5dbb56409e72feb994461730248b2e07806c97c856babc5d8b37768a8ec38a2a36793c54c917312efe80b7aa0af937e72242ef62ae1b900a9f7e7fd27af39762063a445bbfb770d981d1130e97531cee2c7a296d226cb6d37b22f84aeda15a63dab459c504c7a437010001	\\x982fcb075b9603886cfad9e89797f2521d05215faa18537ac2cab19ca4a39c15de06d7330c0bbe381390d1c706c4a6f696ea57c272712400fa39e2f81abbf905	1663606390000000	1664211190000000	1727283190000000	1821891190000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
303	\\xd122aa2d25eca70e9b5b115205b351e703906bd1a6458cc5260ce0bd66cdacc65bcf41aa7b47b0602d85e693042ad35ae91e07e61963d6e25fd2baab2fb7fa7d	1	0	\\x00000001000000000080000398505b5ff8d5be7acdb1360ec4988214b47ee7b8a4ef25f1dc63d14b8da24e0c03e76e17081df41ec343d1f319de9b48162eb300d39883e251bcf64c418a0d1bbff87c68f015b09cf0ffb817eacedc789b4d29edd8717b69af491baa7951b3322a82c5954600b064eda8a8a578b99685da858125ab98d0598751aab75a61255f010001	\\x7517c9f0c7bb7649c58c94c8549760f487daf26daee95e3adcbb063f3ab373355039d208c3bccc1e08d506f7b391af857d8aefc8fe3b50e61053fdc1f7206307	1681741390000000	1682346190000000	1745418190000000	1840026190000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
304	\\xd33605e4668bda40925ee3ece3f20e90df1a26042d14f08abc178f8a08c419f23e4497b288598f9dae36cd2925e23f732120d54b5790f2a43e58047df060abff	1	0	\\x000000010000000000800003a32961fe30fda16e7a5aaf28ff32bee50f3a5969f8815782854ac96e55732b1c0d12e9f342e8eec42f3556c57919e55d14d7184452787c6a161914be74c855c7c0a8bb5bb1d108dafc62cfcab1c49ebb5e269ce3c8b85c1b7e9d1917c2cc9fd50109ef8caa67bcbbb39c00f5b889da6acbb9be3d72cb71a2f30e804c3011fdb5010001	\\xe10e9746d52f90b4d041c141d9dfac4bfac78eecb1cec455fc69ef1e8c3ea97fd9af8703c7a5fe94ae050272e95761d331ba3ea10956e647ce9c55947966010e	1655747890000000	1656352690000000	1719424690000000	1814032690000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
305	\\xd726297c74e984806fc5f0bff58ba571c9a0716937d080118fd975471d75a26634d92dfc62b4a74bb592d24d4b9650f1ae6e7a83529af58db1bcd58ddc567e3a	1	0	\\x000000010000000000800003eb910587ddee50f2bb2d9428c73c85d6aca050f741c33522053769c076602e9d1002d9ed470715e63446a4d315b58d3a06fccfb5bbabddfad992f8bc2f9cf16afe9ecec0cc878fdaee37652695756e23139c607016251754e76d0e8b32a5a9435d912f182c7e76f549541fa9e2456ff81cf6a2caa83341eefe0f9432d75786bb010001	\\x4b485a953031c77710e8cc816bb30bf83939349c916f2778ba91a0defaff20cbf500f5c76020f1d955dd8673da0a9511eec6d8ecc2ead36e72b5c4bf65c3420e	1658165890000000	1658770690000000	1721842690000000	1816450690000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
306	\\xd98a9137e145d599eebd679544698e63dcc6270234f7ed158a4267a9f9b068e155990ee25bf84c32b52331315034d588a08497c2b8dc8dcd8ff17ec9ca6661d9	1	0	\\x000000010000000000800003c063f9ef2fa554c8adcb463f4f2c16886bd0680be07badf27109b072c7db86955566bdc221352932b26e38b811a3fc4e5ac0e5435a05883cdb284848c178e4afa6fe2603916c637ecede48e8fbb10619fd33d7f4627171e4c49af199d5da033e80133f868b183c2c3efb0acc1f816148b6057c21b9d35415333d48c8ab3e652b010001	\\xeefaffe299e23900e5c65ebad5cd6265d13ba901080cb604c61799a24efa2bb68b3d5d75f9dfc3c0ffc59b67db6d4bd526c9534e33c867adc2206c72abd26d01	1682345890000000	1682950690000000	1746022690000000	1840630690000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
307	\\xe3ee712c0ea298f59f3eb7ed1610a437f0f5545a7282e86683dbae7db5ac2c1788ebe56f18e7d3dde0b57b7391ebae02c55c91d9e6c44e6f2d2a6bd2c6a85073	1	0	\\x000000010000000000800003ce3f1cac8e822857ba130dc294994f262147203c73c7b0ab7bfe3d5d168e05a59ced159bcf588d88f38f93b3a17c8b5b12ba49cf67fb923b0e7f5bbd8137ce1b319eaabf4407308797d5faef0f1cc7973be8c5d9fe1eb2fa5065d4bb6a59ed5e7097914606c4f6d6da3a7d12141149bfb6e4402e1f328eefa61ab32952cee3e5010001	\\x7ef00d53dfc1343fc0d02aa49a8fb9217159cc73ae6e8c3889ba47358b386cb553aef335203416f9982a9593b0c683b751b081ba3109f791cd08e1317e6e6d02	1657561390000000	1658166190000000	1721238190000000	1815846190000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
308	\\xe5dec19b42a77c5129fcecc321ed32c1bba2ae0507cee541d0ee28852fc2dfbb59c769956855d918d043a9084d961b92c4598f016c44370f4a4d4a1accdbc5ad	1	0	\\x000000010000000000800003db9d84189b5740875cbe490edceb9eb5bfc6fea1988240515b8e0efb3b2068bfb08ad7a717c2526a88858524f891663cad172f4bc7cb1c64f9b84acd753ceb7af54a789069981a31087b1941d97a7640612e71f6d2636b196de394163d17799de464ffc99c5a5ae18260a94ad47aef91209e769d4d5fdf34798f7e11f64e6f23010001	\\x0b7bef9476ddde65f53e3d8f59e7de5afe739a02b068555eb4576e45faae59d70b02f0c7e2656f92b0e865dc837dfda080dd6dd1967dfa5f8e7dafc418736204	1652120890000000	1652725690000000	1715797690000000	1810405690000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
309	\\xe9e21e5df241fe2ea7487131c691d7505cafc8e8271ec381a9e04627c0cd07076bc0339598854b7b5eed61f6ed67f3fbe37a74f02a8ea100f633460feee6c6d0	1	0	\\x000000010000000000800003aca08cab834229e9c60339692da75a12843c58cc2cfdac8c2f1f56a41c66e27632e68f79aeb5c730f539cb7f217fb379175d5ec5744c92fba57cf6e6273a8a6903097e396605c6246a4987a4c629d4318d9998b2b762ef1e6646038bd46b9677f5ccaa3f61d3cbc5cbb10a120cd6bc915e385f1a48ac40d43f7da7778a8cdb89010001	\\x208d88a9f7d53fc09aadadb1636273c7699a4ad39733f5c927e8e227453b0235edeb42a4f0d60e34a804e4c0df67c44452f9ea1b9bcde2ecb35a8b633ce5a00d	1653934390000000	1654539190000000	1717611190000000	1812219190000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
310	\\xea7665e6885ebc4055be11fc7445c844791328d5723036747ca4bbb51e4ecd4f6a920a45dfa9d7f72d23ada92e83e00f2ad1d80ddb16353a53b10fccfb3e5e20	1	0	\\x000000010000000000800003b505e1c1ff348fbf8dddf652b4138f467f9f2960e55df9859d512fb00a4488da62cb0cd646060b97660e2dbfbcda34e036d083cf94d24630f74bde838b0d7f1dcb1ce71dd214decc76ddf79c4c67682c48097af1a926f6b82833825504fbda64d16cfd1cca533f4f28d0e948c91290c8b7b180f867ce01407f7c4f18642f7de9010001	\\x7afa962d5a842a2d158c35d03e18a7e4a767d94f72b7164216801773aa0c724c17214c4be2f70ada39824d77b89b2c45d9841257294d5a987d77327b58c9bd0a	1678114390000000	1678719190000000	1741791190000000	1836399190000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
311	\\xed2a6f79d965ad7f113b7a5a2b4b61c35ef6c0bcbf1e1aa8d50792d8a9b3ebbd381772622d302e8d49aa23e2e6130902a4883dabba9f54cfdd04d9a24ea3f4db	1	0	\\x000000010000000000800003c069c187735b897dba17aa34065abb94b5f07cc544b0158e8172838dbc57d9f41fd234893a54cf58e3f9ff95032b550136e2edfb292c811d9459615f098373829be437f893f87522c0a82da5e9dc6bbb6c0c68acc0dfb4e2c2271883a4691d9e8c2063c9e85a3e57e40bce770de2d367b7bc245650128e699204f669e9467e8b010001	\\x2f3aceb6013916497d1ad9e4d8b79ef184dbe305e2cd212b03dd5c3e45b667fdc10c92bc7dfdc93811c16ab5858356a7194fa3bb61aef623531336c7f0b9ac03	1679323390000000	1679928190000000	1743000190000000	1837608190000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
312	\\xef3efedac69dc39d2ebfd4c6e1f161a56b67cacca766ad509a151fd5174694bc03a54e9366cef74f3a7edf89871310b46de38c8369daa888e686bcd2f27944ad	1	0	\\x000000010000000000800003af9e97ebc2bf1094774c5a73e09531dcdb608382fd0593fa5bf79195137c9c8ea938643ab5dc2c99ec15ef6759e735d9cb12d74ace53d426dbf1e91b46dafc5523e07bcd52da041dda16c741155ee1dfbeae2682b9721daf8844e5be3f218271f815f5bfb528ec6170a10c6cfb9aeaab6be9e7acaa1fdd154617186ee6696005010001	\\xdd9f8536b8397c4e1c67266558ac4309267952ea4ebfadbe6f1fc213e0a284cb91c436872ef177925690c7ef19187996004c2a85940ee7d97aa894ad0992ac08	1671464890000000	1672069690000000	1735141690000000	1829749690000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
313	\\xf08e70d24ece0e99b2ec042e8824ec6b6db6ec940161b4cc2988a2af05bf4fc19bc91e784ccc64b30045723f1e892a42a1c2b9e7fde67c639c721a13a6b5fc45	1	0	\\x000000010000000000800003df98fb2533fb0ad6530066be0e9bc0b9cac1c175c56ee61a43d2fee5ad7f7a3d1c9799caf0c83c2c6ea72c4a53573f6d1aebf322596224f24e302628e4e18a39bf7562f6d7e31d41ff1e256b42f24ca7acd2b423c640903a67ba2147f57cd518239f3b3304d550fefe09f137bc7d5ccb604a320a5fb255925fb3f60aca06244d010001	\\x9c70c886b1ecac902f7edcdf73d9f2320f8a5b83e627396bf4efe24b23a486c34a34983efbafaa97d4a9ca4d38362c36fc94e08fa406dbd44645dfeae3da720f	1671464890000000	1672069690000000	1735141690000000	1829749690000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
314	\\xf4b6239d3fdf7c9600f29818418e294ab943a3dd4c3ea5698f7f8f64292055d1ecf238ac783746f0415758f59e02c8fc649a37f39fed671af4c4f3697c7f36d5	1	0	\\x000000010000000000800003ae62a44b37b343d65b175ac6c59431862937f4c99a944e1801de7196f471ab59904217e0efd1eef8b172f6c964782c0acc4fc5546938b47c010163e50a9e72afdd36101b81f67de85b2e2d664dd8a584c633091a5d3af61601ac05819d3c5a1cbb4acf71d0492b5c160fd5b17b1ea2d534c528c8a99c31d0dc8e3c6cc1d57383010001	\\x3b0c17cc76c29ebba84a43ef8a5b2d2f34524ff6f231ea2d045828936ad1c99d72bd856e446a5b3a9b5539a1897990b811bc6747528d193106bd613bc99ffe01	1672069390000000	1672674190000000	1735746190000000	1830354190000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
315	\\xfce2b987241273b87c06a6b7106cfc0cbbb4d14d69b4277a42e328c66d2b7286d973375b77043c43e290292378385e80bd81aaa4b6c40ba1fb7c4432c17742f5	1	0	\\x000000010000000000800003cd592650f68bd8ea6b6d2fecbef86845ba51dd09fb38a7d96506bdd92497fc1f092ffae65567ca4f689ca8b0b0f82388d649dde3457284a0faa4aa62758c20ec340f37e27f6d77eab47d5c6b3afe366713eca5eb434d5f218a71c63e986dd5d9f344c9f85f82e66002ac9e490fa94e0186c3906e6da8a6764ea62f2a6958ebe1010001	\\x31622bd293bef3322689caa929bb22537e21ace7904c814af13cb6e165c1c6184ea2e5ea319569abd36d07c32286deb7948a282bb45dfbe24498cdacb2e62e01	1661792890000000	1662397690000000	1725469690000000	1820077690000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
316	\\x02bb3b5267b5f9353fbdec2909d7bf4b52ebbfbdaa6814f0096120bf960c9c590acc8a626e1d8919f143246bb45917049078f2f59b3b3b5d9b03576914444282	1	0	\\x000000010000000000800003a57f58f88db38fd1f96d149d8dabe1b40b6af5d2383f44f689ba807d47176ef7e48f75d8ab73811e9e13605f34167b56fce5e5b24855fb5ce86818254cb267df6ee13f769724559ef1df628461cc9d7505bf34b07bdca85551b1ebbc6c4715454c84b465a78cc7c0af37d7516b091079126cea9cb1fb173b763ce31da96e5ce9010001	\\xbefce3e35f3e7463791606f07fcaf079f344fa8bb205ec081b4302283b9a9a8b63d585b621108f1328119c60a1722fa88421338f18f6b87eadb1b754b7ec900e	1670255890000000	1670860690000000	1733932690000000	1828540690000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
317	\\x055bfb133e88d35c427a24f10eba0260bbe18bc39927094126067fe21cdb0dfa63a1a58bcfd0fd01753bbd3c0fea2faa26d31b0445e93fb0e3e16e6f6b0b28cb	1	0	\\x000000010000000000800003a0b06a521c24cb826fc0359cc7c566aada558e26f676bc6401e2deab4e7bfc3db812044e29ee6e4433e846c52de38869dc80cc0ae75fdbddc5fbd178edeb7294a1695c21469d3ad98777e56a9005e64eb258dbe387f9315c2b8c5b5672f23e5a703aaf72f1b43f505e79b575119714eb70e7688d39a559e7b1ca04e935cb49a7010001	\\x13e00406ea6fe40165fb5e3f51cd79286d5e554c11a52c1cb39adf134268891f20bfd15e8912496e02ea0978b227bba6b84bdc26424262a45e163c87808dd00e	1672069390000000	1672674190000000	1735746190000000	1830354190000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
318	\\x0757dd1c1b0d991fee614f5240d56e7cc5823cd9a03f772849fb0681a9b8829117a481e514854cc411237604fc6d4070c2f3c01f75bf72fea2c9cfabba7104ea	1	0	\\x000000010000000000800003ea19c7a1ca86aeabedc6a4cb24ad684cef1d72164b91867c8842ab0a073be079ba1b0024ac7e54dd0b5ab621dca976874eee240a9eb861e1cd10db9f1af53ab338234e955e6e4351703365adc597151cfabbe642268b96828075b5054544811c11d0d2a8c88637a2b9dd5f1f0c86f78e81eb972ff05abb9ef0263c1bd31af93d010001	\\x42e92af513b9ff605d6802cb259ecd109877525cb0cb4b8b4ca4c83e124999d95696be95971dfcb8a9a4e5cddcc40b79f99141ee9e2f5d1d1c731f9be629810c	1663606390000000	1664211190000000	1727283190000000	1821891190000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
319	\\x0aefefa36dd7ec756d01167f44ccc8c263633e5da978e627c63fc90f1a043c4c33902c5af8cf9ff38e2da2b12b42794cd8496004603a8f9bce2cfd874e67de75	1	0	\\x000000010000000000800003c8e495fd92d7a9680d1e512a7fed449492e87906c4cbe872f380d1cea5b01240732bb30ba20a46fdb541fbf90314571d736fb790077ee5b3a02b15aba72d9bb15a081e370bc12c8542b39b837d643a40df83e57f2d33ba1b16c14e4838cc11216b172b9ea455562529318ebdda43044dcf05bad6ec8c44676f3d5493abcda715010001	\\x1e57f41f3c9256971c4e5b97dfa8b65365a04a3224c6604300bab6ae1c6a39e0efa5a951cff332541ade6412df19813a5dbd12d55458b723034aa644e67d0500	1669651390000000	1670256190000000	1733328190000000	1827936190000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
320	\\x0ceb4f00f5f4d7e0619314deed250ced4215483af14d6e4c5d5814befdf5080c072fd05edd10eea2c87869b6ab72aa8c84c22d7f275af689e3fbc13a96b7d285	1	0	\\x000000010000000000800003cb724724dfe03f37db4710a86bb00b1746530c901c8ef8b88ee97cdc48dbcf0b7a16e80db4dd3ac84444f22c394c35c1aa6d125a3c85ac7904beec702178fdfbb625acb6bbcaa3dc62da057f0b342a458754114ad1503d60a569f926bd3893d503e441a8671790c237c43372ab214b51135aae2d560507f525a1b281037289c1010001	\\xe7dd45fcfa337ae99a751ebc632a8abd96fbb78a050ee8f2c70df618382b12a81ccd04df3f20353ebcc0ec6e47e17616c47dbfb31da5afb3037b0478d10bd30d	1656352390000000	1656957190000000	1720029190000000	1814637190000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
321	\\x108f8a7a5ace0d085edc201beca4d9ee59702617ef78750b7f0a986d3dcc5dd8ebdaec2547f44bf451f465784966b691889a04740b81bd5a9a074328ea6a7656	1	0	\\x000000010000000000800003cd04e188f1c1ecbd6d9e32c7f3a34398456ead72283f3fcad884cc18f7d5eb359727e462f30a8c13bd16c7cf25568635886e054b64d972666e437de5b9a93b88da41631896158087b489aa54c0d1c67f97bde28e0c69132dea685523a7e203e6ebb6a0f68be21bd5d3df3fcc1febfa48839085b1ab8097f8d1eadf2a409e94ed010001	\\x056a529f02598699f10fddfa6b91bfdb7aa19e2633f4c943610e1c5e8f6edce5ab594ce651ba52180ae7c2cf2c1d6273922681435cd9f45f3de1485c228c1104	1670860390000000	1671465190000000	1734537190000000	1829145190000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
322	\\x113f027f1933dd70a63dbcb44e23185666ce8ae9af8de21b994501e6665f2cfff5ff940ff117e4fa0fc5675c25151442ab0929cc51fb3f42db6772196bac13d9	1	0	\\x000000010000000000800003c70337cb75a8678a3a7a62a4f805e9d75e2f312470379f7ffd67892d5e63b70d7e7394c0229d74d8c4ace1e19f20f070fbc9222bb63acb0d122c62c6c237d208e0919c9fe70774a8abd2d7f6fe6d34ffd9ad6687620000506a0ad88e6531d40193bb868e67f8b42b018d44ba05790e99f9ae917384a280ca9db9ce56abddf099010001	\\x7dbe1429d568155e6d79787af0f74c117b0d105526af728574f9c5c5eae1e7eab04e9161b5450fcf76f39c5c1878e384367f2c499c9d4c1cda6ea5654506f00b	1659374890000000	1659979690000000	1723051690000000	1817659690000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
323	\\x14637413a9d4cae245bc9f005d7379ca5b01472dfe4f3bcd12442eb2a0b08daeeb920c2c91a25fd9f1454f7c075f19b62ec0ac040195ed394979976e52579457	1	0	\\x000000010000000000800003b5c300f73ec7ffa20d8b2b7ebd53d096aa1cc5737c20447702474e39730c4fd3a5cd986c9645f0d23f664767082e0339741f067c43c4da86f4353e74bce40b543515fcd57b232ea46e0c022e4f5cd1363697179e992ee9166ea3ebae007445bf48888b8841b7a14a45775b1ef34b5e2ef0f735750203730463df61a0ed0ac893010001	\\x4f1b9f335b3b1a64b750290618ef3ae0f89a9f5b741648d5edab1c8322f44738507f9795abc13fa602f334913a6a2d6a32050ce18b487ddebf3b41ebde0ed304	1671464890000000	1672069690000000	1735141690000000	1829749690000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
324	\\x18d3be54e7ac49b0160f0bbab709db9a738aeadb9830991c882f6833a7a4a0493ce6887831ae3fe3f7ee6fd9f81b8bd98772231abf7fedc8503fb0eecf3b6388	1	0	\\x000000010000000000800003d02dc156a553001b26e0f641030d464d124f633334e17d6d3e5d0d02b688c74069a0affaab59dc27cdf5b0576605bafc261d495cfbc15da78e3c79ac5808d664cca8dc5577187a51b1c426341315be45f9af98f8998928de543decc5e15c789b17802150723a40290feeefb98fa0861db419b1950f6baf6d2c348bec7dd1d003010001	\\x7d2f684fdbf497b5f67a7881ccef3aa06c51ec0dbb14369cb7bb960f75c20b7c1805cb0da40050f91a726aaa81f66f831432fe9034cd4612c77c50ddcf880704	1660583890000000	1661188690000000	1724260690000000	1818868690000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
325	\\x18a72fc0b5dc44ac2be72ae4b78bcf79a5481ee6a24bce352a5e9cd395f3a045153d9c42da4fbd5423fd94e4d26a7b248ab613cd84fadd90d0ceca1f666e43a9	1	0	\\x000000010000000000800003af7958d8f7043ff5170b2899bba89ae9f7adec986d831ff931cea27efa3a910dc4808e3b76ff3c546551297594ff727e44513535760c06ad3491021fb31ddeb3881438de2fb1c2798cd599e5f67f221eefe6b4d9c6a123facd190a8eec37bf56507a9154b3ff1762034e1110387d449a7e0bdeaf97e63e338b600e841fd8d1d7010001	\\x78bb7a8bd95cf0ae3fc03895a24a98bc7964e01742db3e362f8c206cd67149063bf95487fef0f3a92fc673ee6efe61bd007bd61776348e060b969d87ea571f09	1674487390000000	1675092190000000	1738164190000000	1832772190000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
326	\\x18c771e9db071cd2d3f0bd169cb71c8b5671ba7658929167f94a302bbaed6266c655da79de66a132e1ec7775138b7469abaa4d00947814f73b847a70b16fe3fd	1	0	\\x000000010000000000800003b753b539029bbbbb99b8c57e751a660a67deedef9858a9d31a7c5c34a90f086563e62337f8c3c628a48765df9999f6c0b3f9664c2828948ce14f66dadb3bd256f20ce595739fdbb18dae6fa567841b9d0ec14ebe33e230b8335b62da7570532c6f8d415ac04aaccf53a8a5f6c35ff7795d7bd274920a70662d24e2055e99f1d7010001	\\xe0ad7d556e7c73f8da582c3bd9987add19d6de63469185fe8fda1f92fc8db562edf3b1f784881f238cba3fd25fc91b8ec6658de710a8fd509fe9cb93fe14440a	1681136890000000	1681741690000000	1744813690000000	1839421690000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
327	\\x197b2c0948c259ee1dd66585ba564477a507fbbb615c9ad7da9d6b168f326c1ac7a4051899150a651429ac3a44661e1cb1ff5d66bc5e3810ca07ba8eddfa39d7	1	0	\\x000000010000000000800003b20b58e2522af21a3089ccf095967e87166160a03d18d72617ded582266fd8783a1904690895235e800a159b171edfd5c845606dd6d11ee36c063bfea95c1d3988396f7125c962a45d82aa40398706a145036619d1ab0eeb97677eccae95fcc88f680de290bf158a4dadd61f10ff37c46af312405188ad61d8dda49ddc04682f010001	\\x9466f29c609739ef4b83b324b1ae614099d389163b7a0a819f7fddbd96391a3b513e3f9bc3877918116b54a9fd8a1024b1742db052b487e23786f81e6a5cff0b	1672673890000000	1673278690000000	1736350690000000	1830958690000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
328	\\x1aaf52066a2030ea117526167db83268d2a5c7bfb7dcfb62891aaedb8c46d6859bd43c2320cc568007fcb970e4d6db5742812fbbc521a41bc2b54dd4da2d8b15	1	0	\\x000000010000000000800003c0efbeba403de79882dc9088915f51ccaaa36f3e59175c2ed2c415e6bd87074e0c23d91f18d0d5f06c111fc83636a3b462d71d4d74fc01d85d9392690f7ec30dce76b788340f591a267b353e155c7981fbbdf730e6c73d91e217c7fde8313081b56d43ea8ab8c78efeb9308cda92e7968dc8929720c0f616d5f95c446d1a7f4d010001	\\x9a524fb666aaf487847d3dd7be7d61afe4366dfa6ee16fed7ea139bcf80ff70eb2dddc72f57e20d80789ee235a347bcd58b702915265e0a7c30e0346e3d20e0a	1661792890000000	1662397690000000	1725469690000000	1820077690000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
329	\\x1b5b6e48468ff61fef7f80727c57b75d8485deb4d96ee1ee9af60be826e41d53c3e104a935612e934a458d37daf8c163a6764854a0614b13a1d8127b9e6aa46f	1	0	\\x000000010000000000800003b262779b96789732d0866a8a4f298b09f188da2e7cb61fc8c3b21622ee91a0a0e6e673aa9d0ee343e3a56c2d5e888178c2729762df380169675a875b2e7af48612b1db5d15b5214dedfd92754dcf7960821c53a1084af26aa669252a90e85c44f0911c7477e86152ea3ab39b1e59faa64bd1660a5762acc40407c691fcd53fd3010001	\\x9ea04810db181cfbab4478a6242e911c76e210fbdf28b9ffe86b972d56f5a03297b5019adf1747c8be6f6aae4f125d8285c249f40a9bc3c998d5f17bb9610401	1658165890000000	1658770690000000	1721842690000000	1816450690000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
330	\\x1c2b85ee42c09b368f05cd45042e2734ca39458c06ce1c2912a6eedc6d7a7c154e81dc1aada8d859a44d8d899dc418794270c8306df982b2472f35d6b58b7627	1	0	\\x000000010000000000800003aebfa125aa497b5740d47aca8969981c0890816be2e16a1eeeda2d34ee8ddeff293f787c8d7ced0e2c094c0db5de32dfb57616c1dd68439372de888506d64692afc9534f08eba1f7bf6a1661950f687385cd0c1f4062ef1409b57de232e5dadb1c7c6d34e96d31bc11ab920c51b13e20930e2927eba3154b5c5f0c8a0ef4f3c7010001	\\x39269f2eb19f7323beb7f0e2b2b25ac649bbe0d28cddbc2b7ce7a946058204d5cd80863b34fca535c1dbacde7706f858bec8afd0eb3240957506838d83891908	1656352390000000	1656957190000000	1720029190000000	1814637190000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
331	\\x1d57905c69b7365c4dc1b01517e7a07d0cc96d06ad296825f83e9d05ebf400c7f3783e9c423874284998d6557e0287a2ce3572764c817608a3b0c0c0324f1dad	1	0	\\x000000010000000000800003be046189fad34fd793b5fdf5871bf6509785d5d599b710b159210e7570efaaaff5a09d3134f883c9cdb5e54bb6b6cfdd31047a7c5d35a7409484db873738f9dfb8119a3b1f650a01914f09ff47920a54c3daa1e58e4454d403ee258188ee6c2d31bead9ccc21a529c157da3a81384db8a75e27420cf0c3fbabc6bb07efbe46c9010001	\\x47d1782e5343d63a5b9456b3b5e90f04eb6bbcb55d82ea6702d2179b534665730bb128494416a8924a9099eb0c3feeee087efb7481de45bb8d289e811f546801	1682950390000000	1683555190000000	1746627190000000	1841235190000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
332	\\x208fa7aa9e514b1102b9457cf5992f6c76f25cfc27c0f018c5f24e9823f125dc455fcd34277cc29ae2701a40b5ecf67b2e5ae3c99625be6035bcf2e6b6dc740f	1	0	\\x000000010000000000800003ca0efe18745750c4555f37c235bf1ed1a32cff4d4ebf459f0dd0e6254294766a7d98b73165e817403ce08d6009f2308d7f070d35bb32954528357434b6288ba8c500cb55990af7e6b7a1a8b637412edf9b05af04fc82969de03d2efcc430c495c1f7d73aafa551fc1c8a5fc1d8848d448e641620cf14b0d3433c9c3b7044d113010001	\\xef799892d71583fe4d7ffe5b6d15d5c2d780747350a73ea0b44c3320523e669a5a1cbf2d2d880dd8cd96cbc673cb27fb797483df9a2739cbf20d9383b597bf0a	1665419890000000	1666024690000000	1729096690000000	1823704690000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
333	\\x227bdf723aa728d568ba250e5679df8b0f58c1f5faba80da6d2c131b72a8cea80db65279e2682fd0ddfd93982e1044682b07322e487122ee7882884d25871260	1	0	\\x000000010000000000800003e9087eb08523d1bf0f4b77f36d3f0a332a163bcd2827e68df5e89543881f79a6b0662d16c0aee05f6b50334675377250e6b1acb790708502209d5c2c3c85e78e3c2e655446b418c673fd2837492f4a82a66801d89f3dd9c04143f9bf8c119ce87220c0b5fd8e6b54d5fe3d0223943b180111cf1d0774c245e9a8c0f388fafe81010001	\\x014f7d2f5431b84614271ba4b58f2018c66dabd019e7fccfdb0edaa1e9bacfc02ef595f1c3b0c8e519694733cfc1b8285dbc586a4225dd5792bdd0a4f0287408	1672069390000000	1672674190000000	1735746190000000	1830354190000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
334	\\x2397bb39e5e18dbd843141d776423c7cee7301164673fe15668dc0d3f3651599938e4b90f7d3ad419917051fd6db871d214ef229b705455bc70a5b03dc077a04	1	0	\\x000000010000000000800003ccc34fb4c65f7c8bee974fbe88340fbc10d65904f66933c37f188b874de7d07b1bb044a1bdb28f0f1e995b3db67177cfa1761a2dd555a2428600e568f306dfabced54777c120261255f54dcb94c3fb5f68e7a94156f44c8e648ebc77c8cc24132c228a8767ba8f2b4e86720d6aee257dfa6d65076ee092b551a6cb6a894f8591010001	\\x16abe100db2a00044731f97ea6954621ceb279926899120f147df4d4563cbe4f48d29931fd1dc9187da7a16c600be5fc4bbba3e66c2bfed55f43a9b714724303	1674487390000000	1675092190000000	1738164190000000	1832772190000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
335	\\x2a27a64f91e8e6289dd8fbcf5d85a2135d1932c50f51e8ddee36c6877754755bd01fc99c12573b04c583e086f5b194af0b0138a75dc01980eb7d822dff497a58	1	0	\\x000000010000000000800003c6d4f2927f030bd29f82e2b3c35129c8f42634fb2830c9821dfaca0c1a18726698a1cf1781cada739a06b116c6475a8c30e1b4885cb050805ac633ac532b193f9d100e0cf72b7c7707e27484a6764ed6b96e94a5a68a4ccb61cbaf7d08061687c4bf4ad968aa6a9c2570b769c06c3d5c673b2700b6029de905ffd49821af91ad010001	\\xe8111bcd0ebe9c822fe395c5602f20d5694af12f953b4f357984b5a4fbf76493dc9666c6da6f028e4c1fa738f197dfe5b36f2ef39758b3620d643855bf6b6305	1679927890000000	1680532690000000	1743604690000000	1838212690000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
336	\\x2b938dc7c978cc67f4c23d5ec5be23c08c1c01767058eac91676272b10b73eb016196c0e361a69955a957f76c593350e6df2e0d6d57e24a6f1baf8ba68c1b09c	1	0	\\x000000010000000000800003a03a7b29c6dc5c7755614d0d5e0a7f5afe7c5fc88556d2ade0adc0f98f18057a6e58bcbb6b6fe1d66deef3f349a0eb6ba55d2510a56dab01a5289ad1f1d32a7d184990894f29717387b18bb0906bf321d23164bfe16e2daefff2aee9295157728f058f4eb87648469273e0d1517a1b436a533d944bd5ee07158d53ab280b939f010001	\\x7cd1bc1088d7f73b318d37a3cf8a038908d0d13abc1397215540778a5c99df65a47d614f252362b927c1026013223fdc4d70c6ce215afd2bd54fcb03685a100d	1681136890000000	1681741690000000	1744813690000000	1839421690000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
337	\\x2b136a4c7d8a6dae99978cb1f5656ca669949263e7cafe560dd920485734ad40393833a2be0586abee40b92dc965a7d460086c3f32de7a1ca70a5b95b4c4a3ea	1	0	\\x000000010000000000800003c22af53ae59e48a9398994e9bbd20ae80576102802f829dec3794efb34b7b2d96c42e43f90ecb76cb819bd77d7bef73ba0ce1914c84cb8f926d3556332af5b49eef3178935f00d3379758df6cd13d568ad034115b412c11905e3fb36683b0603188c2d24a23b028d59445641cfd741c55b6aed62355229a5240b694f0d39227b010001	\\x6070b87af6bd4674c0d677fcf8e2687aa3c19ef34e762b7ad640298509ba14f5c406f11cf641b162f5e6d3a387de07c445fe1441e074172f17003b8feadaed01	1672673890000000	1673278690000000	1736350690000000	1830958690000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
338	\\x2ddf18d3ade2eb2368b5f98f3c15f89db2c595cc768613ecceb2d925ac8d8e06e4eec99cfa5205fec635172130caf5e4a1cb338fe1f2376ed487cb129656ed17	1	0	\\x000000010000000000800003d909ebcc4e75e9dea125a2705034a71a840f5326cea170f7facd2a9a4e24e24c993c292747bc4eab67e199d271c8006c5f8b268a125aa121053164f04d7c4252bad7fd70a50d94922fc3568a95efcf8e984185bee9ba6b7a7196c9164120839073899de01167f5e566863dda48e3886937dec7db1d8715eee85bfebbf5c8655b010001	\\x631b17dad1c755c605ecad2e335fa9c29f32a06e168f9776c5dbb265dc9c767b8661123594923e259ab75c485d42b225dad68c0530ddb921bd0bbe829ca2e90f	1656956890000000	1657561690000000	1720633690000000	1815241690000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
339	\\x2e2b9196b41537d26658d319055bef01b836889b1b9a5cec27e0867172040bdf2523fc5c09905077b4f013c3d6e800f3c72c030862147638a5930a81b03360b4	1	0	\\x000000010000000000800003c4a80b4cbecf99056cb2a6aacf0d0d0b2c9b75b171b5f76c746904604b886051e701b252b1996e4003e12060ef372249c09e1e7261590dc563f8b60c45b977cb1b38b11dfdb09fe3e6e6c21ebaf33497f554fcd466e3f0f4c0927c7f8c5329efc23af872b9e46e22bf2fbf156081cfc6c256b80e073be0151c56111ad9f9a3a7010001	\\x48804824be87c8fb2195819e6200626db39a94665aaba066aea26881663aca4c5a65e761c715b3f4bd0851f19c366448bc74db73b70756a8b855604fbb258f09	1652725390000000	1653330190000000	1716402190000000	1811010190000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
340	\\x302b7a70243b81a088c220b9de975c1babb8b6a9121cf3f6c1fd2e43bb4adef920623610b9159f24e562ec21bc27dd1f8e40931b4079f52b4605803aac96dc9b	1	0	\\x000000010000000000800003ae74ef41917faaee86f94ba7657980d5916864805222a79ef72fd392e0610339045c6e482d66c8ee8586298c6a8864f1be273d0c1d8639687e7aaf3543bd89e3675edc7ef598657e583afd49bf62c5034ddda9881f3d94e9fe23d58a5f788232c4160c7d8815449a1bc20a33e62895019cec0322b59c7b74e520abc6530e1201010001	\\xff3e801b8ff06d7775a76a780b4327a4f3513fca283a128b358f836d55f75ea44c6540b80ad02218036684ecefec6906a19b6ee78bb3c1bf94f2bc16340bf503	1679323390000000	1679928190000000	1743000190000000	1837608190000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
341	\\x32afebe73b770f9bfac0985a6eded216fc7c4f0abc121049b5e531eb3f99c660eb34e86b34a2f3bdc146de5094e0fd3ef9bc6237c470a916cedf87477f633e71	1	0	\\x000000010000000000800003cf52226db2d4a692a1c0fb99de3cd431bdbdbdd8942a1a2feaec70144e0921e300b2dc204109a7f051a10212271c9dfff66acbad7c41c81a7f031c0d6486a0f2fbda8a9b8f481dcf07a426f4f64ea572fe06aa28567f4cf7cc88ba27cea55b740b7348086404819d870f4f5de116fe6e7f61467d19f35bf3f0b32738868b290b010001	\\x325c3da84fc141ca113bf6afc5e643458909c40711252d0de4056f921a9b579e331a7b3fee81e08ea8c46253c6224295ff8fcb57b14a97e08dbfd8b3f1fcb50d	1675696390000000	1676301190000000	1739373190000000	1833981190000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
342	\\x33172291b4403e4a09832c00ecaa625155412f114afd2abf8e571b21425ecaac459e71d19baefb37d18d01ff1de17ebd68a8ce150b78df19811754c0a9786a8a	1	0	\\x000000010000000000800003c005d6b4edbf83704eed39a484c792335f9375e245729a856a947c923ae0b0970a7d132a76ba71c2867af6ca8d19ccdd54077d0538ae5ad9d92c65cbc46937897feac68d76a7a7267d8b82c5fa939cb45a1bf7e667bf594483ab1c4054ed5132461557467703ce636c02331154507fb07f3a4b64267b164e325adf29db23309d010001	\\x0abf5811310177002eeab748f7a193884ed553e2f629232cbb55e2f3b76e0871eebbc08e9479f1124fae7c4fd5e2160ac6c543bb5de812edcc06f1b406e37505	1653329890000000	1653934690000000	1717006690000000	1811614690000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
343	\\x34f39c2b850f6d387dde0a19de98f9f71faf405aa8fbd2737586fc1c1335c3d71cc80b012cd08b8093d9309c50a226384ae7fbce271baca11edcba53caaff144	1	0	\\x000000010000000000800003a0046e3bb12c06d192a70e1331646040092fa32ad57ee6c5051eff3e236d265eab8d5cdc598a786d749eff804034143f3869ce2441022ee53a650a839bf9042f73a4c52bbba1f4e33910193deb7ab869d9a93bffdabefaef7ee1226b4073b2369b63b0c1554a8a7eeb9578a988b0c1b8e150de65b67b5c2150b651e6126a80cb010001	\\xfdc4c2b012535c6a2fd687edecda46565f2c7658962ac6e331cff95c1d150594fff044bda4aca99871c160482b9d063d125bf4b656658f27a87100e02bb0bc02	1659979390000000	1660584190000000	1723656190000000	1818264190000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
344	\\x37cba9ff604a525e879b2027826df06a9a1aea0a5f73c7ffe619d985c136e344c6b7fb023b85c105b86304f632a900fe63ce26460377a405bc4c6fc73d3661c3	1	0	\\x000000010000000000800003d23d66fa853043c2d1f8b45811a8a32f1a47c53421ddfd0120e7d379ce58a007eb7137f57891be81cde4a829b5d4677b2126a4038decbc600ec79b5f468536a8bd43f70c5644832a96b62783fc49f40b64cc1a70baa861ef5f9e369c9f36c914358d620030017c9ad18ee861ff1b0a74664cc208ddb388435a9ff57643764df7010001	\\xadd00154617d7f175ad57cca26fd29603bd3654c311cc293cc1086b04a4dc56306f342cdf662a6f29c01d5a51be29ac1a5703f11b920c737fa29d539c12fbe08	1675696390000000	1676301190000000	1739373190000000	1833981190000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
345	\\x39a7d1805e43663cfd32a963f6b45231ba2069df440d7634125dc95f7daeb6cf7108795d55a32431f4ace70cd7400389a7a8e24c3443415258260efba74203fc	1	0	\\x000000010000000000800003f9b1ac2c639284df36f128b76b6315e665d822eb78b4d655baa4c6e534a6496cd2ce9ac278cd2919c9ae18d6fbf95bc7aee5b7d7d4fe014fe02fc6daf33593152119f53cbd4874037feb3552765af748621552d6c153e7658c0ad00ae78664bca7c8e5e8c8caa32376b2a819abddf6b7a7567ccc2c4a4f6c281a5e0642a7e705010001	\\x1b9d59334387bc69615fefa4a293cc945ca40fb2ffac061866c751c9dbfbd127ba60cdf4f9baeca768a05aff7a18a95c75f07c32ba2069c02c8e2aa60040fc02	1662397390000000	1663002190000000	1726074190000000	1820682190000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
346	\\x3b731dd904b5f142e2cf3e5ad5317dfa746df8f5185481d939c4c1514b0a42b5715348252ffc6d80e98dfe593d9a762e313c760ac81451e085448cd89ca8c787	1	0	\\x000000010000000000800003efcfcf494f100fcbef09ac0aac98abd74a5719af8b159ce2beb3c01f01b9efec99ff245b2299e0940f5d894d075576f656301ad725af01ec40702d841020ff6b944c371bfd0f462000c82a82bafe6326cc04d7e455fe5181e3f596e480a50aaaa71c3775f6ec0ad9cc09f31be8efc916bde128d9e2144ddacdd9ab009c619a3d010001	\\x8c22c4ca907c7301d700f2177b265331969feeb048bd0e5674acca0d1730ebb747d9dc1008e32aeb685c29563abf3e117fbc574b2e22180609d35fa75037400c	1652120890000000	1652725690000000	1715797690000000	1810405690000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
347	\\x3d9b866d794045d008181bc43f5355f0b050cac733b3892ca51767ff9610df627a89d09036908793314f311dc88cf9b61651d31fc0570e64250b5e04afa4d0c4	1	0	\\x000000010000000000800003d34f534a71aefd9016c3b6b871bd5778a15913aa1de3cc09380412b9ca6d54944188cfb5ee2a3a840a97ed7929a0704535c1eb8ccbea6836c57079ec123acf75d284de1f767dd5b5cd16217ae7d26941a5d5c4359885509ed5b55c89ce06c2a5ffbbc7cd7e62cc1d16a743493185c5dad213c5f616a7c3bbc7df547263d95f5b010001	\\x2afceec070382b427257f5d8d4d3dd947321bed046781e53a18380f77e8462a68fa74c2eb1e12bba073dff888e0662c7fa3030882f34e6cc46045a2afbffd402	1654538890000000	1655143690000000	1718215690000000	1812823690000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
348	\\x3f6311e6605fdedf47fca8330062823e57d257e2b63dcff89c47a2ec330db825c3253ef374e97c66a3ec4b307cdc99594d49160ef58bfc0e33806c3efee0e813	1	0	\\x000000010000000000800003aaf3d793b98b12abcf579f011e84d4af8e3d508b3daaa28cb9b1d9efd86aa2d21e038eb7bef6f1c68f62be4554916c977b365f8458396a3612f8d47be96adb576de6d4b1bace52bbd72567c4d6d89f0c3cfba854d8dfe0e966ae66fa12fd6d5e4e15a9b49f3ae755bb5c62a035905dec09ac7c7405c965b06041e84295de0adf010001	\\x858c109c874c0c4375646b3b81ba56ef8fa78ada2c39966f0d55496880719508ec17602f1ea9d9a76bb6ba5c51635581ac088e1324eadf722e722866bf5e0902	1655143390000000	1655748190000000	1718820190000000	1813428190000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
349	\\x41c7f4eeb32c84c0ea6cadabe10396f09c42a088ac6840cbf9625bb1d3320f801b02851c9679e9dfce89dc15ddfb05a098c2d82ffd321213ec1e631b42b00047	1	0	\\x000000010000000000800003e3b43732d884529c67c1ca84254ddc70b6d55961e34f4f49884d5cf8562f33ef63065981db02a5521b01b8eba35e85bf632f1a6f1d9f2303763bb9219b7ebeb43b4497fb679707cabe1abe0fde6c5a6f7c3450a5754bc1e5b36c0cd8b384dd4bf94af1a855a692a89544e4a8c4e8f0d030d58f9ac1d8008f720c457049d8e9b9010001	\\x6dec0edaeb05f8af51ef74a72270d00426a9ddf4f0895c17ae761adef4336bf07ba8463923c196c9c7cef0b06d6b0e5a000521c419eff3c18e090bbe1d13a108	1677509890000000	1678114690000000	1741186690000000	1835794690000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
350	\\x44cb89741a65137acc95e01514efad0a7b595fb444f2a842f341c15b75242d3ec46ae0255771e0f618db292746e7dc34a32409867e123a1b806d61159b44c96c	1	0	\\x000000010000000000800003c691a43a94be0babf85d76bbfc719b26e56ad36718fd35517885ba05699ce3d9404654cc83cb6035c732b9a562b8d7c748329d4621fb281114aa79f5dd8ddf85dcd58aa699ccf0a22aca8a210db2ebf8dde6581b6b64ad4212ef6f069fd52794a7f4ab425d9fbe2e14b3966e8923b0acfe5e8164fffadc22857bfe74fdc803c7010001	\\x5547b9cbec492d792410d16ab6240294605e3affca41a5e7db80561c2846ef4c5dd474d3774ca4b0b545a165cb3b1c4fe50821d6a0c58cc9d20dc2684ce9d70e	1678718890000000	1679323690000000	1742395690000000	1837003690000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
351	\\x464b11d43097e8ec7dabe0feb964845c9620c40295143bec5334cb20599d1163eac6f6fb76720994428a53ef2c02bbd7f5167e2076cc2f0913b680b8b633e821	1	0	\\x000000010000000000800003d0b73aa760ba5e666475993e65106538c7c746aef5454e0ade74e9af13a5aeb7ead43af72288a4e2078af0362f3b6c3cc23623b4705332c7c2c8818b59f3dda3517716021057b447426c15abd7d6d76654f20c88b0b02b0e2d63711b34539425c8a7ee638162e4347851c7bbeaaada2f601d4ba25ea4002607332fe39b800443010001	\\x46a0a389eb44c9168f680d83a3fd6d5f3b65b4c924332ae8489e40a91288daef17b3dfdee9dc06f48ce84935cd3d396b029aa78bccbe07b2bdab1b20380c8c00	1653329890000000	1653934690000000	1717006690000000	1811614690000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
352	\\x4bebc5c8ddd64f96938ac6e82600a9dcbeaaddc709540e93dbef247e3a238d7a779e2ff71d8a7feb3a816c0cd37c50b36a6263703c34180e3f306c45d5f01e64	1	0	\\x000000010000000000800003d861350bacd3f48fd2b6139604b290cd3855fb3ffbe270f49a5c04f61a32a9dadbba6efa95b58aa9c46d808846c4caad3c161e3c147ca65e65824aad653ad1bfca30fff04c6f7a23021cde583675e32b7dd446c4c4789e8306343d587288ac89db04cb95613809356dc02d4acbc77ef036706d7ce8e7ccc9fe8cd644e019f00b010001	\\x127ad0fe15dfae289072babe3d2f2a0abba91d3d0b4abffd0401e9a089d0c88589a6a43c586105e47e93489cb61a93427b3d5db680a864f7dffafe77864d6305	1667233390000000	1667838190000000	1730910190000000	1825518190000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
353	\\x4b03f5efca411012ba2367150bfebdc6ca6ef58c1b22dea29e27e0a5a197a4dd429fdddf8e999575e584d5a7524967bc98f079d97b602243cf73d8738b204907	1	0	\\x000000010000000000800003c5d9e550b5d409c54266f86080c0d15dac5089185d238f07d1951b05a9234d5abeb70346335dc0c2c08a0021bc7390f778bbce447f1472c15ac275dae4c20b447654bd21852c652b0f79902921c1beab59980b06827a7addafab588c1ae3786ca41ffa2228f521049a1ed58b0fad738313a9232fb20ca1afd00343f11579f341010001	\\x07a3dd1aa40bd09a09a077b5b0997c2979058ce299d05afb0a7ca51a4b902786476b99770b8daa9f3f691671cc745c0125d345b3e30e7494fbc7f1a554dbb905	1673882890000000	1674487690000000	1737559690000000	1832167690000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
354	\\x4b4fbd22bf9a30fec831eda7ecf153aa06018327a6c4be1e60283fa413c3de239b60286aa90ebf91e9d68d9861d09b49ca497540ce5a9fab0bed17645770cf26	1	0	\\x000000010000000000800003d0a18ac2312310a8a07934b8c9656385643b057bbf0f72af99651eef32e8a512f1dd130635417fdca6dcdef5dda0fb8fe36f3daedbe1ef0be3d826104be1f40e86e04f11a0b8a31a55965a66858dab3212a08cd8a4e1d34f1e9f76a20ae44d605318a30a02b66f87528312b991c85ad275d3f52e6b5ad72e4960007ea2a1006f010001	\\xdadec52a64228c061cb848d306cb1d00415e3bebfa67d214080c5a075b79f9b4c66f685b1ede799c923131fe217693be1d197fcb9550a967aedea8a005dec80f	1661188390000000	1661793190000000	1724865190000000	1819473190000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
355	\\x4db3fe4d2219acdde5f39573464204d955c857c1f5d8805bff7d5e13cffbcebf59ad1e4226bb79d407b7abcf74ace227ac0b3fe24711c53d76317d6635f6551a	1	0	\\x000000010000000000800003d94eb4137cad6a2d1cef51de67032017266fa769af86f0eabb728a07fe2b86a56c7552e1faef99657c7298bf59a84874c2a3f288e8453dda0e906a8de7fa19e600681f4af4d49a3139f494309c97276dcfde8bb63cdaea7ba044c3aa99bc708604179e4f0d09e02e36d8eb32b963fa7446a8dc0fefdda668b8f64a31bd188b99010001	\\xc923dfad84f1d45ed4e06bf1cabf76c38858fdfbde1023a180c2b6354830d0e05c99fa76412b58f7c8024a6d7bff9ccb3bb969f2ed7b1ca606616a7c9ec67806	1672069390000000	1672674190000000	1735746190000000	1830354190000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
356	\\x52a75ae48a0a7d4996f3bf9f45a1d461fcd739a7fd0ba941d3c735c70f5ebf598c2c965529dc8b0fff7ef635c9b278a9d2301ec78c19a61ca1a92c1c6fdbbbe0	1	0	\\x000000010000000000800003beb97f0210fae103ac9575078425191f8ead4f829aa28a551b042f5bcac246c66e059b608b18f7c34aec4d81094f70ab32455bc8eea978174b2a0f6dbdebd64ffc0f81039511a59984e2bc5ab8a4f550301df82daec4d85fd499d84a93e8486d2bed1eaae77cbcacbbbe747327f1efff594dce26ca333dc4b4a8ef7ece1d3b91010001	\\x49aa0cb286be0cab974754c9ce95575b3ff575c6de96f60edbdaba01b9be70bc822bb188a43407d4e9719441d11233cbaa22859f1fb2b0eace0dac6634e2000a	1666024390000000	1666629190000000	1729701190000000	1824309190000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
357	\\x56d389a26c75778f613c4a5f30ca0c085cd95ae2786fbdc985557ce67bff7c57bcf876060a08e7dbb5bca862ad9a162a1cd41076af9f2273ba8e9206ac75afde	1	0	\\x000000010000000000800003bd8a38090e3c190855f21b3c4b8718702b100dd01d90c57ce85781cfa00b4aa2c719606cdaa9f1529712a8bbe427c48891c841bebb631c7dfec6e72168f3dbdd3a266f1f95e0e0188cce283127e6531bacc1a1503f85cc6298a3b3c5c9f2d60f0813dd3150adef2a4056e6ff8fbed6c378159749f46524de3de67789e9f97fd5010001	\\x25bfeb160594171fd27e00c9feebc373c113c251e6ada9a9432b9b1d1d2115d7e858bf75a142645ee1dd3452a7c1e5420dc5ab2fdc66d36645dd869394dd5204	1678114390000000	1678719190000000	1741791190000000	1836399190000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
358	\\x59d70f6c59ec618da82c8ea2200db5b44bc8561d30102ab1c9fec221e2b4a6dbdb96ae27c3a9c59c77d53beb0754ddea49ced3fc942d0e11bf54efdb0c2dda46	1	0	\\x000000010000000000800003b81fa69b42eae103bb18ce44b122d889aba2d49cba8aca088dece74544ad5f61226b21fe406596e952ce0a1260e43989464fda9186c02d5afbb68cc8d5d412e7c42b582dec3d25a2ed19c86d6a3ed90e5ec65ff8fef72a64633054abf69a46c476341f6bd59af32f16592af276673677b1dda461cf441af53fa243148af446b1010001	\\x58c0976b0ff4bd7c2744a37799a1255775efaefbec42ec2a26e706fcc826b16f4e418bb902aefb1b7c8c71bbbf804d1acbc694930a4611b69a39b008f107fb01	1666024390000000	1666629190000000	1729701190000000	1824309190000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
359	\\x5ab7e87e5419b314ec21197a23aff8f021422e34d2f583d824d893871ab3c74bb59a106f09cccc6194b911308f27b6010f9d425f3e7b89176ddf94819121c5a9	1	0	\\x000000010000000000800003cb0626c61d3ccc5395130259014beacd8b2411f0610e040d914ef2e6f6b2833397b9ad947803480cd4327748c00ea274fd6e9e75f5ab7d04f1d5b7ef1f3307c62b55f38789554c8defa743f3603667c7c4a2f0c8988c4ef35336fade8c3485ed447348c88ce507453b1605c5c9c415f0a4a796140158c3d2143469935019bfed010001	\\x7d59e83f54cdb4282180fb1aad32e3a029dc201c2fc40df01d56fb7ede2bd0ce2de76914fb7c6f0a1359990588fa94390b53c9a2e1b01b246624622c0958a20a	1656956890000000	1657561690000000	1720633690000000	1815241690000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
360	\\x647f0491be5c0ae87df1c6079b705926d0b4e4e4a291faea410f81c3a4a8f71dbecdff42c02059c1da9f46b4946d7ad1e009e0d3e3b2511590fbedd3c3b85b73	1	0	\\x000000010000000000800003c1cd0062268b404fdddfe4aa6344e1c12fb8834071b1f6b879fe9ef30dd807c2ba483a0efff9b4f2aac6e93f45e35efa58516fe29e9f736780169f938d013cd0632c2c0c3fa9eae5a2800b03b88768bcc03b75248d6b6d61ca649b05cd8ae90e2344f4fbd8f265679cbe62fe60295444d7b791483907629249a9bca382251f09010001	\\x13f446da003e94eea478811225265730f4bf877fbcd687eb9825ed5caf8d88a3fe3551166ec3d52ee31070bb5902eb95b57432be1f6f0fd26f1aa7d8a250e009	1678718890000000	1679323690000000	1742395690000000	1837003690000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
361	\\x6a638151277f94ad71b1d2899cea036a6a707bc52b26f0f5a3903460a77f0ffc9fe3564bc6771785050b10de96c7a2766db32b991c0116bf630a08b25a35bc29	1	0	\\x000000010000000000800003e7075929e0d4dc9d9ea56e0e8c77313739261aedb86da7711028cb7bc7a9e39a82aaf79436798355c85f9f69926967c2aa9ae6aa27e2f919df0a04adf41f3f92eb99900e5670ac2e78c3286f28a15ba22f03a4729d5deabd60563ea686bc78753190faee12c343d6aecde19b5ce21240ec65c14633769ec86ee934fdb2cd35b3010001	\\x8d6791ffacaa3a4f9bfac6eefa1189f4f6fc09f041f027483a1f126930db79601d55bdea422d37985db044a1d9f990c613b099c1e672f4caa87621e180948605	1675696390000000	1676301190000000	1739373190000000	1833981190000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
362	\\x707f55ccd0a6c6e892d0126918e42a4c7fdd48c1c6ef4de9f1921803d514d97ba9503c64dea4d5b80c23d754eddd6519dc7b39adff021179962b629c330c4cfa	1	0	\\x000000010000000000800003b800ab781c2ea05b0440a57b3cc37baaed6671eafa18d9f952f97e804725d37fc75e05c4faa7ef2c1eb6467a93962d5c7f2fa30e1ead9ec3a8c7a3ced16028ee00ab05d7a5c283f04c1e54100a2d3ead48c5dd2f296143ff32347d80012eeb37f079f9cf6943f0d138297db261255606e059e3c206f7fb12fbb30d3e5a94eed9010001	\\xcac668312808e62776ba934b4a870e99737d96e3b3044964d9f8d61a4021f5d7e41eeab5b92f65d8583d95ee5d0ee3ed5a364318d12d318184f82d71d7998100	1667837890000000	1668442690000000	1731514690000000	1826122690000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
363	\\x73135ce22fe072b1d9f0df142ba5f87b5eb5b0ed4a2393c0d3005c2e39914c035a2541b9beb1a063658ec7747b1ff388a951286771444460bade91942e2a0b3b	1	0	\\x000000010000000000800003c3be444386997d87c901b41c03c8ecf01f42f57c21529a9dea1c6188af7bd3e9f7ca9e6dc53a6d3594c34936f0ae8ced8cbfba52b58bca2ef6fb19ea18660664ef23532220cab36697f91460b1e81f3d40abb5804b76304ba1673cfe1c26c2ea68f9ab5330894e604288e5786c442e56ac6812badacc19520aad16e7cd4af065010001	\\x3e49535caa2ebacde0e1ff9a30f95b0ba0d7f06a8c5c2dff77d4ddd6f38209790e47cfa79a6fcf9671ca90ce1182184b28162184ab73a7513499e1e6293ea409	1678718890000000	1679323690000000	1742395690000000	1837003690000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
364	\\x77f71993b270fea3dac389e471a9dd2b0a9fec7ba3c305c96f5cde3779d611b853edf21f393881262ae308c36d15f98f369fc6d4ea1fc699f4a02e915c916e61	1	0	\\x000000010000000000800003e3928ef7e563f84d74cb3739b345d1a7037ce555e3580019e028dd94f02723839bb9f6d7cf6cdabd4456c057e1d6784378aa989d5242f9ca58fdabbc809d6c46f0fea9a7fe7ab23d73c46280e3ea31974ea277396998e1b5e0e8b5755e3aaf9ca14daf495d0812116aef49d0bae07fc569d887cd8ad160da8b9d66507793d7ff010001	\\x966fcaeb9d5c6400a3c8a03720c0e4f4dce1c776b422001ea802c30369bdc866328c3d103e8661cbf1ba985721bc98a408056f36cd12c0e427351e9f4b43a40e	1671464890000000	1672069690000000	1735141690000000	1829749690000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
365	\\x7a9bca70f3848fde1b313043664394ce4f82477d8d7c4f958a55b5fa78859ff3a2cf80022e391348df22ca3ef86d64d554d61c52bde8ebe269f5da42fb55d5d4	1	0	\\x000000010000000000800003eef5e65463ae224b478206bdc7bf2f9f32931ed0b3e5acc49dd3bc7126816a03ef75a56c09b96c8892a48d2b6f2c97c4a988eac8c09b453cead8fd71f0f82aad5fb271f0b872555f5f0681c7436b2d78275562b20b81bf13eaa79efe816dcf5750eb05ab4daea108cfe99d1ceb981a61b2b66b542ae06afa4c8f23c29a470e9b010001	\\xb244bcbd38d09724082b10fbdffbfa23145676fec8d262c9a9bdd226b70aa7d5c41c13102d270a0ca31dd1d9835a9a1f17ee7864f968ca1aa30597701c4a2100	1676905390000000	1677510190000000	1740582190000000	1835190190000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
366	\\x7ebf119fcc61a85b56944c4086ea8374e2f519f210a1b0b1a25c2db6636d23225beed192041748aa002b2849010264616cf48b3487200e1ddfc5f02b083b66a2	1	0	\\x000000010000000000800003d85220193e5a8f598e2d419e5271a4b30d0ba990417183efb5d2c45d5bfd0f73ff43ab97c5f151fb09f2c2cb3d2ff5f3eea8b24ac50be35c013d204fc1cee3c76e63705fa337f6753f10ed7a0e4e4317c2bad404a57d6700ee44453c00a648acaf641f86642d5f340be4ccbfd67c55afff8383c05e73ce946d18ae9dd4fe7ecf010001	\\x79c69bef6ec6736a2a0e1c1800463dc501ca823593808b0f39e811a95132c1f2a45b677f5b1a316c9f720c8b01b2664cad02dd575d205106f88c81609c963b03	1669046890000000	1669651690000000	1732723690000000	1827331690000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
367	\\x80e3852bdfd6d556f688495e99feb615f2d09495162846c8b1876cfd405dc7bd66c0f1aa6b0298ed2067e128d29629ede22127fc19a3e507f88cb81d77c30fc9	1	0	\\x000000010000000000800003aec7797f40d0b908434295bda4616ac006e83ab82142d8e8fca4548745b5f5ab45d9ebdf8f1a11dcb323cf7181a020ee77bc92a0dbe21fb1471c2c87679b3b0d9322f8590af63df75f42149650abd0e9fd403ff5eea1dd5b33e251bfe7d20e327d296f7dc9d978aa1db31e172a380b4077970afc16700ca4e31c42a5b5161ac3010001	\\x0a847803c037227cf72ce8b238e68a4891bafe33c2b681bf730523385223fd2b4b3a0ee38e620a86e4bdf69a00ef7fa0ad827b594381a6906095df878d5d2f00	1665419890000000	1666024690000000	1729096690000000	1823704690000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
368	\\x8027f2fafd786a917b7fb2863aa3110a7f8e4f772435f4bcbbe155af3b25cd0ada0c9c76d9beb24a6fb946b24c217b3df92b3c51c764e7693631de638a1bc305	1	0	\\x000000010000000000800003bc85a41cf64409b1e63dacd85ec85d365d4c401abf405df508567dc1c86f52d8490216b5c344c7abcdc7d4fb50a6cbe8bf516882231435e176be88d77b883cbc0f2b775443649346b695e0eb03e85207e2d1193901aed4321827bf7ffcb3925175cb4d1563fe93cd6c6c381ff7b3d4e23d53e1027d8fad516053bc0b8b1a586f010001	\\x5fb968837f34ba8fe7022a0bb8f09b5624fb8476a4f90dec29f11f4a92d683e91514ead90486db2fccc9ef02531ba92f0278eaa13687997ccd2fbc3e7b0d6f03	1659979390000000	1660584190000000	1723656190000000	1818264190000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
369	\\x80af521776f9a40e65126b16f20f70dbffa03fc6c4d0399751580440a88ef35bfa1e83b486b1168b9116d064f1a4c13d6dce44ab30b0c9b7e4a15585ef6395b3	1	0	\\x000000010000000000800003b722c8569bf026848eb783f3a62e8ee5147780cefb80e828726254c730a26ec8e2e7a0255631c1a94885685c96b8174f6ac5259114ccb134a86d76fed6102432d9a4bc00f39ad8ae2e83c59c61a17d0eab146326f10d4cf21e8fbacb6186fb7516799cfae2dab19950123f7b1d8270ca1c31edeeba0718c813d8b5da1eea2095010001	\\x3ebd536d6fc850cc10bd14f7f5ffcc198cba66d0da5f53aabaa6a7b20b8b6a86d86fb7c12770f254cfe88e7715297042f39ba3535c41d6cbccb90193c1cea707	1659979390000000	1660584190000000	1723656190000000	1818264190000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
370	\\x84abe6b0511374ac3709eb959d32236e6929cb93b46a3e30f19fa069ac19b56b23c167ee36ec227bcbc8c3fdab07be2ed3b92f673bc2c1426807a5ec34c42c45	1	0	\\x000000010000000000800003a3c2952851b47381e177e513f6097d90b95bb6ce9f1e52b986dcf09d35aaa721cfd9b614020a30e7e071c842bae5695adb2996762ddd7472081db645ea8522cf2c5031784cab3a2310b357307312c4ca5ee34e4641abf3f3b792f73f63203d49763b9b024e2d15828edbafa791b599d7582bce991964e995d2db86f5e22b988d010001	\\xa2033f8a8e35ff264cfc59e51774a0470ddcec3626abdefc440c79b465b3e58e35a91d5e102de5df6c6f17a4c67c983e0805fad7917dea5259ce5165835cd409	1653934390000000	1654539190000000	1717611190000000	1812219190000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
371	\\x88a7e9c791ba7b1c61852bf36bd5c639f85cbbd306cc728547e9c914bf128a26fa437b86aa3860ad5d0343ce961b5c34edc153aa6f68609e9abb6e3af9adae33	1	0	\\x000000010000000000800003a66f03bcb46265516b0835d8c01e527c392a8bd8a508e953ee08cc5d712d1504e79b3bf8d9c6cd22faf2cb8e3332b9fd59cf0cb92028a46232c615bb6393793a2afe7a29d19d4bbeea94c9518b2099b86eff6a045b5d27630f5e3dea51da3947604c5faee2eb7a5a14821514f21cab8e21e650208b1c3064031c0e9b99353add010001	\\x1fd34d621694506a551658bca05e12748745b714241998e3bdaf01fd425f1a95dd1d6b380bad651e71f16e974467acd824cde9a979b6cb20c91954d916839b02	1669046890000000	1669651690000000	1732723690000000	1827331690000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
372	\\x891781c9b464c40fa18bc9dbced8e25f4c701275433f961640b01c1cbdc4753a8ed3adcfa4830664d4d175f652c804ae9adbf21e77fd4256387ef315c71f4af7	1	0	\\x000000010000000000800003e9169c9c49ef3ab39bbad3a892c269a63c3a2dbd31a5b596c7becdfddae3f44367d9f1572b465140df54703f1db8730b604b44d712dd806fed380e3c8fb94672c1c7a82bd0f3f5bb0e6a7bc4402eb76481d1c813c4bbd526fbb21dd247f6b9b31a213e76d30e039d2e00577032549e91c6fb9353e21021123836896d06f672f3010001	\\x5684b5f21352eb2bdc533e4f9cf4ce4cda533b5456272725edc34a8c465049e26d8a091f9dab7f0b03ffcc7dce8d87818e2da3246e5da051da8094750debe807	1661188390000000	1661793190000000	1724865190000000	1819473190000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
373	\\x8e03d43a0615c9f3b1133e7e5168f7c4ea5f6a9fe011e68e1843b3c71018c4c5c49661cded022c54db88b2e360676bd2e8877091153411694f36b57c4c046d8b	1	0	\\x000000010000000000800003ac39141e95e24327ee11706850b1dcd40d070bed783f15e1d0c8d925e1de896218ac4d193710da5e12877be3a8404b13cea0eda5ce3ebd6c66a42c645ce5037d16126920d90e16cae44db73e67c509598efc9e697aad4e5e5b104cadba405292ff313fb186f0b7410ee5f2bc8de10c0d72cff8aa80c2f49b7d8f06c6f9bc4875010001	\\x0e364035cfffc3d500ae43b44f24b127b036b9357ee76ea5f13316b23d56c71a32da9c41866e9de7411aad0d7d7a972a4362ee97fc922303e3bc4d11b131a000	1658770390000000	1659375190000000	1722447190000000	1817055190000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
374	\\x900bc19cf81db220ad878f9be02b09900165b241663d3e48c58abe33a437a0c6389d7ca814c7ae3c9be8929d04d6a37e2a0370bc1d0c2bb6189bd214158d1e5c	1	0	\\x000000010000000000800003c2c836478ce2ea5f6a5a492d89f758b8626b2c11af76f988d06b0ea6d0ab067490ad4ba4f0f54935c3e2238536f111724c6a91aedf61e2d1395c6a029a39107732ccc3ab2353b38eec43a0b95a4f9b82ed72a7e320f3fde782a089fd8716eb9cd75512ebc408d277286082241576d2723baba0921dbc0d2ca9a8d20832ec943d010001	\\x03065952c722e8aae15fb1c2aec840b19ddc9576866c32a7e532c215e726cf9ea9d56f513ad085afe6658eed304e4e33c160b2abe59dd29bc7a28ae19c7db002	1655747890000000	1656352690000000	1719424690000000	1814032690000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
375	\\x93d3f17e3f19942e6ea911b5eb4781039d02016e83d3c1e66ee3f7217ad14936e95deff4a2e6024bacb15f773ad10211d11bed51936ed511afc8081e0a4a296b	1	0	\\x000000010000000000800003e723cf239c412ccbf739145589f99c9950fa971b61f180b6357edf544fb7b51f9ae48f7f2025693d9ca3726a4fe7b8c15f15dfdac6e3aa857f5e28dc820f32013193ec0d6839a68ebb07d6556d086055a6501ef5fc80138aa760b70b69aa0dff9203b2d9d1dbe9b4d352b54ff30520c55789d083ff20ed92cade0889808dbdb7010001	\\x5b039e42f6c44ece22d0ce8a04cfd048e4dc8bb9e7ec9d04a3365e16cf8f800a16334c64e4a2ff136caf6ec0a0355bb0b49eaf9f12b010afa7b394db6381e200	1670860390000000	1671465190000000	1734537190000000	1829145190000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
376	\\x97bfb4452a9ad76c60f38340c34d844327c79eb010a5cdeea926907b83a64f13daac5dc7cea5ffd905cb440471a269920191b7e082d6687e908eeb009d26db19	1	0	\\x000000010000000000800003b07b1457af908801bf349cee6e95ba5de63153264a7a84c84e6cb340be926a324589dbbf810de657c48700e29e2ece4f90a8925ba58032a1d60f7cba6e1fbf70dff9638c8712356ac29ebb13d6dabfdca626967d06930002b317900bdf72a9a60cc255107231ce3757f03e7163e7c37faac0dc599c8dce026574c900c4ab7993010001	\\x2f503dc1d794e680fd815b892b6906950f94ec3a79edf0865b15f7d99f4bda55f043cc97e12d7111a7628ea815587c6f3a8d5d208e4158b363328a3d30810c07	1652120890000000	1652725690000000	1715797690000000	1810405690000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
377	\\x9c2343a33206c5071ae45fd1fcf5474cf880187714b9d5066789ea3640315c45b95bdefdaca54a1eb30a3d55ab7aae5a6563ccdb88d2f3cb217d4c9bd5504c02	1	0	\\x000000010000000000800003bb0e032490d26e5f513f0bab772e184e03a844b1cc41d77a830abddc1e3ef3de0a813b65a1c1d4e364aaf217524cc015aeb4a4e1bb911ccdb54107a4b985f851b130c1fe2087a20053b25dc54c82a990f774cd22e9d2c9a1239f0a35751a7c72146bdc4bd6dba5cc37bd22682fda2edcffa5ee64a6bb3a51dddba5e11b99a555010001	\\x116d9a32c3c9446796ba25b5674c3d348622d61b6fa67c7fc8c5f42c65e37cb857e2099c8de901ca5d8772c92bf0ba75b2584c312887a54c4c2247a40d274705	1655747890000000	1656352690000000	1719424690000000	1814032690000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
378	\\x9c9fb6d0226505132714c131d60de478e0f54e5f5b4d37159e235f47025243c73460aaf0b9e6daf52f57690db00016d0607ed6eb8f878c75bd5aec080fbc9b80	1	0	\\x000000010000000000800003be9943e5d514163ee9613b519b0e7f1fab07bd6207732cd08d14184ff0174c84f7f7d5e2a45444890eb168ad4947b84f315f857891938963ae8e5e6efd7a5aaeee80a244343459b909604d6083aab5ae7fb49979af34816273a058beef1ddee1e903c3d63e77aafc653dd69967261de0a19d2135bd592a1c7dfc796079b1c3d5010001	\\x88ae9c2f2debf72d1eb19f310504d0fb5bee98d64437bd075b74717a3a3e46b16f1abbaf9cd01cbfa9da5f5983e2acf8d95de12447ef8991338ab34e2f136607	1681741390000000	1682346190000000	1745418190000000	1840026190000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
379	\\x9eb301e4146f1709af1d5dec834beee57488e317e2a8bbc5847e00f0ebb3c994dbe26b042ee9191c1b991241d3d925d04b8f9fa27608ffed2f7d317cbbfc2393	1	0	\\x000000010000000000800003b0580465893b95f33af9febb6c6e23d20f977340bc5191ece326a2df94c21e03868060fb2458fa0560dad7cc29ca5ac239ea228620b1b0442d8e218b010a0c6a8040432701842490ba2866ed3f01dfdd551a6f833c1e821a953d4fd5fb48ab2054814c0d385e36166b3beedd6f778c83fcd5e1b946f09e0c747e2f9d6d5c2c55010001	\\xe9aa5537ab70875612e322c195513830f943f6860c4d90ee22d9d72044c0cf3b76dbb2f7678da66eac12569db8dfdcfe76ed948bd3a1113d182c9c82bd972b0a	1678114390000000	1678719190000000	1741791190000000	1836399190000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
380	\\x9ff7fe431fe540ee9bcad478e04011b5ac25b5021b209a749f9980a2591898a0545ad161342a198908c3a066ec083f39176eb0b674412df5ecdebec92c5ccbfc	1	0	\\x000000010000000000800003bc3a3f547dbeea09fd86c7645c97324deb4d020f2e5dda6001d3dd63a820a4f8cb5ade8af4bc4fcc72def5eca98d59941bb2b9904fa893d12c717048f36c975968348d43eb38684b29c8176b727e4c211ba80c18722346f2058fb7bad77c7ccce3c4397d83220238c5521ffd64cf449ea1c9ae086afd8a6220e0056277b2af51010001	\\x372063417a70e9072c887dacf8a8802b1ddfba29ec6865c6c3829a98fe168d05367727c9e1c0c2fa04d6979e35393a4ec04f3c7b7fb8ba214c25e63802736206	1651516390000000	1652121190000000	1715193190000000	1809801190000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
381	\\xa6ff8dd7fcd3c1f855e25e0412438c9c8e891e4c6e09a522d29cd7cef2dc83c5a398bc68e7b5e89cc5b592b0c089db7b10c3270078fcac200fac661ea8d0cb67	1	0	\\x000000010000000000800003d02b6ad344fbe2a940fc949f213f794b5d5dbe54cf19dfcad744f0714fae8d2cb00040b78ab2dd92e5ac7d06703289f849d00fe159562f743f1543c0dc4b195b0ca171f53c46a506d165c3188de11ce5cb9f6e0e0c777bb349f7cec2c4f4664bded3413f5e315debbe2705423a30facdbf2ec677ffcf8e18ec8d02593ced51a9010001	\\xf31c270d52aadc07228594104d027083c685b5e419680d634f6c01facb9af6ccb0c43dee5d846f05d4881db4331eded2a73e3b9143e8c979ef91ff296b793400	1655747890000000	1656352690000000	1719424690000000	1814032690000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
382	\\xa84b9e12660de5cc923c7f3b2e7542dc019b15d97417d78e1e6c8ef6c7a39f1dba6554e1118f652df8c356499091d9726ae292121640d49b668d71154c7bba6c	1	0	\\x000000010000000000800003a97a35321b835ddc6241d9921218adde8927d7899efdd909bac933044cafbf6946679c1f6703b1b13e91dcc72038d1daf837e41ed9ecd2d21ff373e6e3ea570c61c515ea8442d4637949825249b11c792756b84395c9298a3026d1c96b6e84a11da245b8575fc43f081af9600a994e278d5f8226169a8bdf611c6aa8b21a626d010001	\\x474209202703600a4d69a2400f908fc6ef747c4f165f119943d0c582249c1f1bc2599a28090c5a4c242a5160865230bdf608ddae1d277d459b7495baefe56707	1652120890000000	1652725690000000	1715797690000000	1810405690000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
383	\\xad9fca2a7d4655252e2584f8a41481cb24a65f4df9700af534c6cd34332e59a7b2a12b5970c5ab9b5870e2be7ac410e007b6ba3e07de1b5aabb444d54215a25e	1	0	\\x000000010000000000800003b31446f7c439d8dfe4ab51927682e451f05f1507feae716f49705143d994cae7565386a02d405679bf4e1cf1728e6370ebab4dd17ab4d805651f249b481c6bb0275664de642f2fb5bbb2444899fd0b8aeeaa3ac0bfa864f8ce2158a1f4a75d6764b9798e609e113bb0796cf566bd1693669e44ebcba257ac768a5687194d9043010001	\\xadceca98a0710d0cc2c708639f8ba7eb5416abf57dbac017c5ed433b559b69dd27461614268c22cc29cbd8543817c130a19f35c952ecc3655e45298f9028e205	1656352390000000	1656957190000000	1720029190000000	1814637190000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
384	\\xad33a9da668e68c4f867c65825a58aa5df13faa121d878a3f8bf9ccc3ec2577dba44b2d76ddc770b2f44c05fc45f1e211d78806ed937d5948c7e7f73a24b2ab2	1	0	\\x0000000100000000008000039ce5fa44a84b89bfe63f912cba062e5a662c6da02bb1f39ce25224db0dd4a314cf3eaed8813d7adf49c393bdc86c6cf7b437d9ce9d4fb184c907d6f298b811f0a234ddce19d474eeea007b341c252c3b38a314c4857c70ecb44a7e7a0bb0c1b49837b67317253df7c4621685b547b5759017b27999821c995f04971168f789c9010001	\\x0a4d133aa5b61d3ac4a9762ecd9e7b1c554385422f8c6f7647beac168d0330ae4ed1b3b4522ca5bab2c3b13de1d09f265d271628116aca6ddb553a38caee3b06	1681741390000000	1682346190000000	1745418190000000	1840026190000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
385	\\xb29facaa2c741836e7ab62726fa86acc8a1ebc6d4d5679ebb3fd607661c06905b4bbb5577a4fe529ef89e17f958a6afdf18ca1bf324aae7a8b1fa6e872a8cc40	1	0	\\x000000010000000000800003ad51b57752a3bc822b41bdf4b002890323a0bc0e36ca81d44e369205467696d5451190c0609c081c38a97e35a59a5c482328642503783644600ec26cbd04906dc54d396d0d1abe4a6e92ecc453a2fbb91afadf5d2706162f03eec2e381f7e9fc534f25e6bdeab831336f8fc484e4acf74cb29516448c5b05e8d33fc22b59a413010001	\\xd3fad7e0aff7e3f8cb0ff85d857aaf00eb357562938737643a800c0d022b5f8b7ff4b6cef01ca45640155d79db7b3cd9ca920dce529ba409ad6514f8c4440304	1654538890000000	1655143690000000	1718215690000000	1812823690000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
386	\\xb46772ab06272f57135b6220e701c91ee03b9863eff5f97418e02f9828212085839de7e3c6c9554a184307bd9db56f2c3878579658b00016537d6d11d5457417	1	0	\\x000000010000000000800003cee24eba5740fa95e471f5f735ab131e8a7813856c0005f5b9be2c333e496fe5566ea766b2d0f09225c4ab6693afd999cbac60cd163aa2be02934add41535a3671d472e487193543589e78f3e98cde23d5403b704bd7f7d87ea9a86bd71c41638b9c00b87142138ee1aeca5b42a1044617dbccee5b7cf723cd7605200ac104dd010001	\\x300b4888a982da3c9cc39feb3f522c2ef4c9578df4ec4cb747fa734122989b1588e7950369e1a4620c7b47839a1226f4a0f22fb79cf16ed8950ebef31fc2a70a	1676905390000000	1677510190000000	1740582190000000	1835190190000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
387	\\xb627ce8f0d184bc9c7f82c8ff94d307ee385678982ce63857cbb2d004feaba292c7f0da0e4dd5481a780664e7229841ec5cd839b3c22b0c73c304c86292618cb	1	0	\\x000000010000000000800003dfea19a96ebfb4654274853cbdb74a336c79dd37efd309dcaf020accf47d92a439035f2f4a42021eb45cd89eb0e39fa3db34cdf32697ff7a4269dca87da66c3be3dd725d20d3ec5c17702ad849ec1d2b6097c99a13a066dd8925b1c1553d13fe038e467dfea808217ba6d99872d282321b64de700113517f0685b961a4d0ce93010001	\\xf091b6e83380dbc619d9d4ed60bdc8a3dec96bb6c232067d88243d20cb3745c091d4ecc6114b1b4ac312f3413916cd616f15a226f8c556bec913a59d83bd9604	1674487390000000	1675092190000000	1738164190000000	1832772190000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
388	\\xb61768dd82be473152151b4d2048d69bdec860c56b9466a502dbf058700c5b9180cbcca647e69555e90aedcdf9a61275b5594df159e0d77bf46e3329bf08542a	1	0	\\x000000010000000000800003de0ce9debcc485cecfceabc9a7b209474577008ee2c2cbcd503f2ba02288f38f4d69bb0cc48b6806d25dd6dd510f56be253758e001ddb2f26222ebff3c1c20c3575518d3785d50bd5e6a3be26b425a6bbac51d356f63fe4878f88944bdff6651b4edaf99c8a5cb64f26c502e60d30efbb96ed20c61af1db15529a0e92a4f9f79010001	\\xdba2f54d15e1f119bb7eaa1f724319537639e41c8f5c595bf110495c2c26d6a631d23d5d507d35e061039a152d19b2ca248ddce82a848df3eed80b88e669d404	1673882890000000	1674487690000000	1737559690000000	1832167690000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
389	\\xb62b1649f9a49b83bc01b423ecf298c2b6fbd5964898502fd9b47bed55dcc912d27fd6cc88d6932f6170921e5b60a7bba275a89a5eb01f05a8ffa45273c0d962	1	0	\\x000000010000000000800003b70851e5ea1b42454f292fc75ed791438d250e828baafa6b49f594c37fcf31c98821ce8ef15d777ef8d63e1f81fef95cc05327b2e6a0d5190269efbef2d12287ae0aecb7144bbc19c80bdf523289ed4584e036c976b06af21777fd248191bd33d87413190027787e004885f164f920b7a64b74eeca2e7ee76944dbbad3d5b191010001	\\x9dd2b64ff4fe96387a3f37c6197e2a68f48727fcb4584b185078844535d1c08970ca710508868aae3ab9b4f02ae9675e16c6b5eedf472888d3e2ca54f367be02	1657561390000000	1658166190000000	1721238190000000	1815846190000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
390	\\xb7b73f99c01cbbd9b0fabfd33ae9338903385563d718a5620288f1dc86ca6c9ab0c71069f9f4a39715e944f413d8081a234f05eb7a6dfb38dc900b27323ae021	1	0	\\x000000010000000000800003c5189904ce30a5f04ae306a750497edb0fd4811a418c891cd1b047ae5ba30eddeb939c17e5ff731dd7248d9cfde901c0d9f92c2ec4172b342c5b6289451a69fe6878df40f5921c2a66869695b0c6d43c779cc76d76eb67e83426287bca31e9173d5b346d8c438947837d88101de57b882bf85773a5865055633fe38817920e9d010001	\\x4669be9557b5db18ab554718734a5430172502c20258e7cbf62fa6d7f999f0d864f24dae5534f0037dabfd60ad3a614682a9cfb1aecabeac667d246f8467b807	1678718890000000	1679323690000000	1742395690000000	1837003690000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
391	\\xb94f77dd672981a9d6e6e667f1ce1aa58018026eb6d2f5aaf3596777d64c1ab1a863d3403d80e20c97ec39970a1d690a5f8990f98dee3aa6e63209bcedc0c603	1	0	\\x000000010000000000800003d2f1006e9ff1fee0fc569186ffe3a60263c6020d143ca26aa6764974037ba8e82376069d91893ff062b7b1867fad9730cb6bff002cb9a7dbc736f06e3dd5930e09c3727bf25c3505538974c6dd6751ff29aa5c940b261ab728f85e40860a8ae0a80590931ad314383ece12de2af72e438beccf046f26ad4eaacf1ed54e5e51ed010001	\\x5f3a223a8ef2f01873fe7b7b3f81bb2126090fc291c29aa05e7eca47c93248947e9e6f3a3eb5cb2a235391a628ab4a00eb8e9f5d93ba258d1fd0900286a5220e	1656956890000000	1657561690000000	1720633690000000	1815241690000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
392	\\xba331db60d6f74d03fa9690b368a811ce05d3b89d159d40a3f176d9e99880e7bee0ec56e816f1251e33d9095c1483810cf48f4a430138d107656605a7b35f569	1	0	\\x000000010000000000800003cd4d8c5a3b94317a1bc2267023dd05104d1e086e9efba2e927825b21b23188b9883581b29eded874b53064f066996624437b055cc0ca2fcf10ce174e0fd1a814d3a701f6b4b0feacef6460cf65c05b07b8723c8c293a7e9038cb2897678b5794218bb9739ee1d0c9e2c0a5776e2117bedfe4b367b1f9238fb97561e85731da5d010001	\\xab475d473bd597d7ac951ef10454ec1b7295e8d0fb837b70b48ac66b77110f943b75e05289ef1586ee64bd36d79bb6b35048c8656a1e4e74bbd414a104fc8101	1658165890000000	1658770690000000	1721842690000000	1816450690000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
393	\\xc08b468630b98341685893631256d349a56d2bbb9d2c8fafb91a5ce1a3a50471dbc7a7b828b8c880cf205ae6affb12208f0b30971e42914878deedc662907c08	1	0	\\x000000010000000000800003dd966c1d156a43f8a1fe2656722ed30b28ae8274f776e91d01792fe0c8776aaaf8f27ad5d181497700213d7af9bdc70fb18f42668c787b854c379259c6cc3a63d0d682642b77277ed49fd28ddfa70cdb14e9b9d9540343648913c3d431dd156218f63d79bbe0ffbedeb422b15701c31ff9e482edda1f163586162349373798b1010001	\\x787a2eeea0e22fbadb7a0368dbdf0850f192e1d90dc53eef8f7a7701bec8707e260db387317913ada70e8ee25ce90b3046559d4a0c063052a5900ae369d2db03	1656956890000000	1657561690000000	1720633690000000	1815241690000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
394	\\xc2e3dbb90172f70122aa6eaff6961348894a80d1d27754e864dc0e22041ac9c88c5c3943a72641a5de88e8db60c3abe45460616d47394fcf037eb5ec12d43181	1	0	\\x000000010000000000800003ddcebd7c8d143475a05a16db1f5ba307ede35dd75c95ea94d3be42e0dc3e7ff3832df5a2755ce7cda1705df22365d9a34b8107453d81fcf38a57c34f6d3b96aa2081dfe84c8a212860dce3c9922f00b3a5fbc32c669388750ecdae1189fb72dec8a6339e31f268ca0cff9a8d1d1158c092dba6fdeee29fd3de3a6f8460c990d7010001	\\x6fc23dfe8a077a826119b69481ef606f3770981313f0d2fd5eebaceeb76959bba87d73cd06de800b3a377cd8340d83f3bc37716acc733e7b0e02cd7c82cbc603	1657561390000000	1658166190000000	1721238190000000	1815846190000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
395	\\xc3fbeb52099bc6d8df57590289a45b6257c6d0619f0a30438b54447fb1da82297491b473d49af5e78114dcd13494008e7e61710eb4f6fc804339a617e257c983	1	0	\\x000000010000000000800003b719d287e123baaeefbfa9dfeddbf3d1e72c680e570466a1246e5345dc264eb26f61aad728c103e0284c49dce56ce2c91ea9020a4fdfe538572e93eb2f0a76321b648264cbf5f359de58e0807178b2753f0ffccbcb15c25e6e687f2d63d60ab86b4c19193f9773db9d72ea3bee597bfbd0b19fd2ea849625bbacec528e854f97010001	\\xb778ee6e53c6951b58ec4170e233b2d5fcc95650505e12855bd7d677a0a6e419f1fa65beff1bf79f637646ec136cf71d7267cfb072bf128ad0a1666b6b0ec60e	1674487390000000	1675092190000000	1738164190000000	1832772190000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
396	\\xc9e7ad6040efacc22fbdc477f289810386944b413309461342e603460f6c3fc5f2ea310961c1cb6231513f1a3bfd266c0c47b5fd487251e788a2a3d123b1281d	1	0	\\x000000010000000000800003b9da07f70f304e305e8a1fb94e0ae80ac2c22053dd97b54caa7509934cff5086c20ea9afb5167f25cf0ab46d63083de0cea5a1951827577b8434ce62b1dd2a4dbc9603db445968267a770f0196d48955fb2ad5ab2d13f4d1e3baec9be4ef4aeaa4b6d4bd7e7fb3f132a8b005a92c9adbd1f4efcf9a4a1bf45b94fd876de19a05010001	\\x7866a6ca728153cb552cb9d74ddd890ba8a76283c4127744153dab5b155c755489b853dcdc4e6846ad733bd66a30c88c9f5d9f8e32857a5e162ef5023d0cc807	1661792890000000	1662397690000000	1725469690000000	1820077690000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
397	\\xca3314e35cff85b65b394b484b9b5c134cee8dc932549b0562a5fb3939c901594ba248b3915a3217ebaaeb2ebd7a4c2786fb73dc01112b9ae005a7b4235b40f4	1	0	\\x000000010000000000800003b03f33cb99a64d527baa4bd92808a015fb58d773300ba9a5165d30fb0e4c1d20a3a44f380acd941c4b7237f4ed4daf2d2e339373bb191485ac29a1ea0c235efb15be6cfc1e644d29c54de40a45a8135d48352d7a854ab5d7020af122de6b68ae6a839f1fbf4eb21244305fc00b5cde278a8baf451cf7f820e2e96ea1c6ab51df010001	\\x1dd1cf90a49b0300d2220992f5cd3b4390ed8db748ebe54c71adfcc4a6d14879130a0f5a25d5b990d521b6ab72490740aa3d464b8b81f8c7899af948bcb5c00b	1663606390000000	1664211190000000	1727283190000000	1821891190000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
398	\\xcc77df80a38b0b3749d1aefff55b436e28e2396a1b78353041289f31122a3d0df117300e61be621a533423c69f573e861178580efdbdd8bf4240bb4e2b1f43c6	1	0	\\x000000010000000000800003b89a472b22ec1a95d53e32283482e635c8a7982cfd1c8d5f6eb087f3ff154b6e624fb877f63f311df93b3790e9ac65bcb7dd30a74c8969b6f216baff047170a2079e1735b25b8dc82a1c9da5437de69ab147c5d7849989689be182bab5efc5853ab7ba147e349d96d4a7cf714d53ecf25795ae5889c80c95466a2337bad64a5f010001	\\xfc11ad007cc0f97da6cd7be0e334984541b2b16ff400e31e892922e98f161c506fcd1066851f6f200d2f198ae3b2dee4d81b5b56788ed59fe71549a2f5c4750f	1662397390000000	1663002190000000	1726074190000000	1820682190000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
399	\\xcce7afea9c79ad97190e013705d75d50c32226fc7d6cb467ef423a74901ff3ef1507f6aaa028e0187f902b78d47b9505d42c0515c07e787986205a0ed7dae81f	1	0	\\x000000010000000000800003b2e6c3dc5f191494f76631797576269b1ecdd1ff6a7df1b6362efbd78ab99afbfe758bc13559dc9efeecf822196bca676b0d97de078caad5e057f1905c557bc39eb4fb4878cd748ffb2b1a718c9db60f4d904347520ee01a56e606acb830c62da30dfb00f6c95b691df7fdf42d42d8cba287d500c1e986e022df3554b82ca943010001	\\x4bc30ecc83b41dc7787856f85379909f86a190dadbda2cabbc8347fd377486ded0c1fe0adf740cbac6701f37bb39be09df345b1821902617dab93f9af1d8f907	1659979390000000	1660584190000000	1723656190000000	1818264190000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
400	\\xce6f855bcf6e106e1868c1e27a793c4b740d2ef92934326bac1d498f4f9982efaa8267a574dd31a0d944c99c819138825ed9e3e5a9d5b93067358e3170badc1e	1	0	\\x000000010000000000800003d6e1d5334445f956848f2cd9717b14b88e627429753f52ff6ba1684df4da2878ae008b5ce2a9c8e1e509d416f7c3121808e4f6684825ea4fd176f21cff1dc346713130a34ce6516ab01a6505a135f1b9aca163adc44829e6952c0f6357e2eabc9e874e7840d0b01af533c4c4eec43ad725a62eabf4bd97b2ad3c09422ff78131010001	\\x5e39e940b06087fd964cb6833d0e5c88cd8c553c78a9676ab49e096345b28dff7b0f094c76ddea4a7684f9e3f1666ffbfd6fa6cb0a0e19c8e9328a215b323c09	1653934390000000	1654539190000000	1717611190000000	1812219190000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
401	\\xd3ef74be92c78c6627a0b98c0d2f04fe3529900142989a5dda7a30cafd6453a7c720979aabb8f7eb9b6300af84700580daccef8cc576b57b851689c4a7b13f1f	1	0	\\x000000010000000000800003de8f2f3d6610c98e87a87bac14e1ed6f31840f21e657769f9f59c3cc8d883f0db9ac7bbb8f6ab5485272230410163718996e29161f6293de2fc609e34251ea4886c19c284c10ba18206391583a20b9c2fa93e67d5ab9b516652ac5f17755c791b2100c244032157fc7f9329a4c73da9db7fcbee175ec93eaa70391216546185b010001	\\x85cdfd3513363c80f9a2579e5c90cbbb8494a2445b85a9eda3f8bc019f1ad6519617c3bbce76234d93fe0117ce02099236e31e25612c5054c79ed4391198f20d	1652725390000000	1653330190000000	1716402190000000	1811010190000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
402	\\xd8d7a86c1542276b9798f17a8c79872ea3ef9fff457401b39ed843d63e9c53cdb66dc12c65d9a21071bced6aab7d496ced62080a5f2210f95a3c54f52ae67ada	1	0	\\x000000010000000000800003a8a44d2cd247c0961a196a25d51760696e2cf5f157df6f15184c034ca1a57a4bc2b0d8c33becca59654909cfcc395b6e2207bb97848d9c3168046ef80311620474fc42b96f10acd38e50135f4abbc1c7c6d91b00a6689329852fc187039915f69747cb9cf2a3733e20dd020343b2d310074361a089b50658b60d938c1ccd64cb010001	\\x1265a96df664cea6a7ed8b8d059bae6743f47b613ea71145bb74a6501a3f1cb8ba1591d62658979b72437e2e49ab4b0e3bf0505dff8d5ab3e810219388666c08	1678114390000000	1678719190000000	1741791190000000	1836399190000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
403	\\xdc83c4f68e2c434ada0e7bc92d1f3eac843ebcfb201e86b0e01583d2557919a7078fb72e9fba844e080f665b5a47375e748eabb45a0bf1b6148409e9adb6cf32	1	0	\\x000000010000000000800003c47fffaac6a7c5f091ed0430388d4f270d7d8f3d7f63bae322db5488dba90069a5d9e5872c0fcd745365352989434aaf284514188b7ddb9c4a146e19cb9301b974b95144bd269e0aa0f2a03808ffffd22af8d02b6bce63ecffb58438b01eb18cea420b3dacd894d91638660a6dac595f73bc662dc2c98ce90cc7c5abb91ea179010001	\\xba545585494b1d1961b02d4c0d5da65a1991ced384a5746c9fc376ec62e06c29079af2aa785783bf43afcd75036950c095439183dab274bc157c9ab3e1308d04	1659374890000000	1659979690000000	1723051690000000	1817659690000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
404	\\xdef77e194dcfa7e065f0d7a9a1c5e3f6e4fae4ffeb3973a24ba8434de2dbc10c55b5b5c078bbb608797ef4c681363dbf5c0e03e6900930642f428e746999a8f1	1	0	\\x000000010000000000800003bda4f57e18135b1f3198180ef779e797162561da57681d1071856273a3c32a9334438dc7764b07c5ead5fc920e6e84a29a34772a5eee5e0ef4c5ea39bf3d05abb70d34f9f3bcd987f3b8b6091de01627d9778e7c007e3d73e8b74424ba96ed4e1a128b819e9f6feb0c3072ac8e96c36b74b57045cbf8e2f111f641af5277d2c9010001	\\xf237fec1c2895064107f73aaeb0283c4f8e74d30605b0d050dda819b27fd8a6994258c53c450972970aac77488c0f2b6bf4d62d67717f3c005cec7b0ddead703	1655143390000000	1655748190000000	1718820190000000	1813428190000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
405	\\xdea7caa3ef6fe135a42ffd159656f4ad35db8d5f2bac567211682534a6a082032733ae3adace3afa184df666fcb1803770456247c55ebdf39d18e32c24983900	1	0	\\x000000010000000000800003e1b66a4879c61b472f599b00300aeb15b4ae50ab1d1bc5ae0ea8c1792df548a2cb0431627e41d2fd523868e4b29b108c909f2966806417c889abb457c8b53a1760e82f61821561bcca989f213bbbfdf57f03cc3248831d6e53c38154dc3ae0b40447f021aa1cd2bfda0644a0f3a26b44250928482cc2dbd85932f9d84e51d74f010001	\\x8d269e55912efba8b1095d856bcf10ebe76469b609252b2354f1be4c0b84c84bdee57c402303f06f550e0dc97a432dcd51b5a5b0cd2b1bc2fddd49f0b907b60d	1679323390000000	1679928190000000	1743000190000000	1837608190000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
406	\\xdfa3e6d03bc7faac809cfbce2dcf50eeefaf24e4c16967b0545aecccc7e70524ea53813912e0e6e60b2e1938a97315e90e7c61ef504f2c332f361f08b922a022	1	0	\\x000000010000000000800003c1735865584f2ffe074c4484c60d177c69b33550bf4589cbc41d59b5b8061fe212ee8dd162699fa1b5a3cbb7dea7df188c91a098077d1c93a822a0689ca8e37f55055a7ffdc3626391c5c721db23f713b65ef3430fc6f0fe6763b67e1cd841097bf912dc93fc384c3ee3b28e358bbe8de99ade8d5dd2066b647b4cfb5923fdf5010001	\\x6b1cfa68e20ee0401f333383ccf9118728705505612a6caa5ee54d52ce306a3d22c4e74bcbd32954f0b97d151f79f46490107f3093b105a5f1801c5d5ea30d0e	1674487390000000	1675092190000000	1738164190000000	1832772190000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
407	\\xe1b7f0b863caee174e81ccfbe5bde712c4b522735f4abf45f7a804e72623a72f431fe73100a60b69c32d04cb4e23417184ddb00763c2ffea87c99aac16260f4d	1	0	\\x000000010000000000800003f8473cbf60b493b1940ded7204a8e60f4d042ec37ca659eaf2850381159662a293d458f586f7707fec5a9fbdb9f2a379683a7179e06ec62f55ff36a07bdd9ae53d67e5399eba0b788147d4b821ee1fafdc826597363098495c0bfd5353b27cc6eb18c078edd674ae6791a67212c70d2e321a8a114c645c8222760a21c08b068f010001	\\x07d26d0c159a0f8fc034528f727387f20896a84b2fbae447ead337ff22df31d0f0e0a080186d09fda77b715ce0593bfb43382d5021538e517656f4b85f712c06	1682950390000000	1683555190000000	1746627190000000	1841235190000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
408	\\xe13f67fb8ca127183e0e53970337f0fe86963a9c3e6b69a3a9b1c2bbdd0e8bbad8650dee5b9c6fdad0c75068031ba4018f93894ee80bec309d86093c035f021a	1	0	\\x000000010000000000800003ac2ec02e74b276ffb14d0da426eb2da5a659369b549c80df3c2386be4bd02f9cc729640c0f1c70fd1c43824f24592f20cc72c5e24a9193c4f6656e11cce63f615f69cd05d277e9cd8cf70982c165ff51ec84ce389e07bedfc3ee0e0116713c88b64b148bf4b26bd4b2b66c42c6e1e4100f5b10b88d0eb5b5dabe780b5f2bbd5b010001	\\xd287127bc765099710c28c9ea146ade106cf234de69c884790e873931da127480e552d21727d6189c12a29b977d0038ad3e9ca0bacb0f6d4ef9eb06e87321902	1675696390000000	1676301190000000	1739373190000000	1833981190000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
409	\\xe4234475e4a9238a6e2fb54f81d0d327b957b15fc517d948926198e24f999d6efa9504b5e1a09d5f545764c9acc4072b40f05fe4715176cf577d5ef039b09ff3	1	0	\\x000000010000000000800003f75cdba60ccb1c93e2bb8ad2d19c0413e676b49b75d6af6e1ebd69855e0c03ad3e89ca051740869b5674828de780639b4ef9694d29008aa876c7cc83c59b06cf1d0054e3c1c62faf590cf97dcc5b21086cc8c8d6df2c41f52a7371c4ae0e5fabbd6c237f54979f465092938880059cb3927cbea285c862a6b2271a3abfbad4c3010001	\\xcd4aa8467add30874b55986e3e7173fcbf7f61131c2d103d0733b95c63667afd5cc8758cf6b26e8bb589ca1ccfb1cc1e28a0e3b61cb5b32de8b56c963f431205	1674487390000000	1675092190000000	1738164190000000	1832772190000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
410	\\xe5a3cee713bc953b837952f1e3594dfdba78f29c531439a2bd9cd4b5130d3c3eb32729d8b7b07cc6a8f33d42c60702b0d6b91f953bb44f1bf2bfd71050e1d2b7	1	0	\\x00000001000000000080000393b4215f50bbb8f23f7369dceec00eeca622cc67d13b28bdb5f6c02fc5811d1e5941027613de0d8e9e4eba5226640819b67fb1b2c2ba366442b2329b4575d1d6ed956881ad14651b682679c1701a5e00569071562c38e52ed91c9fc45a49e96255a4bc74a66844c33bfcc413a74bb9585f6187ec6c14924d4f2058a2c5a97f85010001	\\xda6a6e34686e57829fa437818e56efa64d615c2e2c01ab934c8dddbc24595473f7b33cb3312b4ab52f4103932076c3b90a5f391b4304c45c42b8de64b806980b	1670255890000000	1670860690000000	1733932690000000	1828540690000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
411	\\xe6f39d3b82904744c886b0eb120460e995466f579cfdb14d3439f680a683da7593c545a9722e45fdde094b06027c6c30c29ba180b621ffa28a48fcd76b39c69c	1	0	\\x000000010000000000800003ddb5836d18ade98b2f2a20bd5ecbf130075940c44353d436fdf4998e553b8ab0eaa18deb7addf8d937403d086c9a53cbb6573b6f9e277998814e17235e4ae2f13efb485a23d3983fcd2e77cb1b1b8df90e327e389ba12b035955b95a86b6c24b9e50dfa730f0467dd658db93bfbc5e83ddda94b4431d69d1f19a1d31a840cc4f010001	\\x05df61a29cbbba7e73ff951fa20e566ff6e53b1e9547ffe4ef8800e749ad0d70c093c50295b1074161e827761c228fb84a012ddb1366b46d7420d3c675265109	1656956890000000	1657561690000000	1720633690000000	1815241690000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
412	\\xe693126b5adf585587a60dc4f53d729f6a1064d40615d1a6508cba12b755c54730dae77c6a353bfa3355b3cfec0a2d36cd1246f4b782675fc56e6b5e54c2097e	1	0	\\x000000010000000000800003c69ed6a99d0e17b2845fc86c04e185de1e9c702bb6250e30de8f56bf44f09949ca7061e6cc51d097a25f4c0164a68ebe81bced938a22a152d07557ac0509adc72620173443f6803993cca63629ce718a0e31361af68be8e0a82dc93b12d8287483a335912ed340fee3e688ced1b050174114c36743e4e162e37b1b1471f8534d010001	\\x9eeb3939e6b0af6ac423348e9833f8c00e57c7dddf73418e47bfd488b993e2ee66c572ae99262d1f219b4f646eb2672dc03bd01bb8584e3b36a65ccd7bfeb209	1663001890000000	1663606690000000	1726678690000000	1821286690000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
413	\\xe703c4c7c0bb34a28a661dbe25373b82666dd04359a3fee464b207af1477490bcb5363e95bbfac8be2d5d66aa74a3891d10353a301b99119fdc2347fe30dd70a	1	0	\\x000000010000000000800003ab66483a747b7ee9a8ec341092abd84886034e3b4ef7e94d5fb17517f8acfa95c3d6edf01ea87a4988c57f691d306c4b3e629ed20a4f70d834ee14b96518e11a3772aee14e5c7ba6af5a6fb1d52bdda562c881ce59c6ef255d3f38bc489b683e9bda42458d740146c88cefdaf7b0c0e272b01b9ae463a275343ffe9667166e13010001	\\x12bcbcb68c0fff86ee1c7de244f3f8be848200922036cb0258312671bc87977e5eaa8826e00bb77a98bd284d39e73c0cb5f5aa666abe6df75a566294c977020e	1679927890000000	1680532690000000	1743604690000000	1838212690000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
414	\\xe807be652653384efe0c9b2f9f648e844b9ce1266fbceb8d4183ccac37601dbb3759128b883baafbe84f1ea3878380583cdd55a692acaf2ff75a3fe6156b0af9	1	0	\\x000000010000000000800003c34bb2f2f52b6c67b6d73ec96dd4b21857690ffb6e995a59c5512bf45cbf4f15f30c61132f7e1a9b990987978443e0761b22976d103a33ac84b601938b35acb6f7b19bac2278317034beff3c87b8855a5ce7d2a4f5d7528b6bbb6660be49120b3cc85987dab16d034ca936b8d674b25e3997bc4304e5fc6e55c8f12556b7c75f010001	\\x0b9fabc5da9cc5830d7567ffa99d3977bdf432e4fa9a28f0530bfe5347f40948eb3994e581eeaf57c331aabaae9f1d55e964d8637a78d14cd89063e50b69e10f	1654538890000000	1655143690000000	1718215690000000	1812823690000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
415	\\xe8ebf5c12616123e57cebedec39ed26d766dd8c3dd38d98ccc6ae9ccb51c1a5c5b737bac0c7de2e8c338209982e9142dfba0cf085242464c121dbd50487394cb	1	0	\\x000000010000000000800003c7e10a500344569d07cebd06de28a84fc295575318ec0712a02f6eac2ca42a8ecd3f141a098ae309dd8475d8c74a6f56aff232746310c6c9b3a46c516a57add6e7751f39c2932c75918d3e5588fb61914cab03dc46430508c3e73959b3465cc4057306d9e832c6ceeb83dc3470085e5e2406c47f1f3fd9139a0f33c651c8ef31010001	\\x8d5cf183f99715bd9fa0cab741474ed6c9255cf8ece1a49830649afaf94d33b38814459dd744edea3cb3883d2920c8a9c8f141a8dc33e5cb5e34045dee5e8e00	1659979390000000	1660584190000000	1723656190000000	1818264190000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
416	\\xeaab0019870f9ffb9c43d0ca04f4b541038a2a72e04d5af690f21a415ccaf398877b93934b2d6ced4eb3629a46f6f31771a3076a1f7480023e2bad7eaf95f308	1	0	\\x000000010000000000800003cf325532c47952dec526ada0d3c9909a36c512a158b507436d000d7355bd605625cc70e05d85a0fe934bfd50a87e96db3fedce3348b877341b83b382695f406d1db437753c74c8e717cd5d6ea9bfc7c27ee2e132df12af59c187a3972ecefe88bcb8a130bd00874ff75fac52847d66b5c14924059fefcbf9b94696eb7fa00681010001	\\x3bd3a932c6eb2523a8abdd746f41e81364c389152e3489398875c7563a5c06f032b26db820282c72261199cc731b98a05de8bf8095e1340412bbdb5295bf1d01	1666628890000000	1667233690000000	1730305690000000	1824913690000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
417	\\xea1f070c5d0eb5bc9364bce7a8cb52ade84bd36c8a27d5004ff5c8883d747234b03294bdc60058fc68cd980826649bdc1afd080fd5c34542b61168a40531a003	1	0	\\x000000010000000000800003cc2c1e0aea11d0dfbae890bf67cad9d1f1212b5a4cbedb68a89711469edc27fdcaf4b46d6bb7c564cca878f954a7d1600acbfc99568a5a1801af6dd0a643a216e2809fad29ca6b28ed31ad1120c105a386bbc418c772027ecf144fe2b73f9d766f422a265fc179707c344b0b9f049c11276123039d8ff965d8fd4db22e8ba605010001	\\x1d9f2c21d3f1b80e543d1109e0d3c0992ba4b2558cc85c6b107b27ddd3bce0006630116b4f431b68b9689c58d3a8e636ac8962a437b937d2ecd6b226339c3a00	1666628890000000	1667233690000000	1730305690000000	1824913690000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
418	\\xecef17ad8e533dd0bc8ea728ac2df416c4d9b75b6afb24bfeb0d1bc530913f040b8dd6ae353b36c128d2fe4b23d16a138c1d2002d738d576c44a2d8a5738c4c2	1	0	\\x000000010000000000800003d257036efa15fd8e3e1894286f6a2e1f47b7e077102d8ec2b9949a252a0f85abdc74274954fa2b9018a7650e4dbb71c2c1794e9ba445dfa9ab1eea351bfa110938874f6f979a4e8b387a04c3e062ca3d9b0d3e9bc2851ac1da44167ea34706b4528cd428f94fe066a9d95d589d6c1cc4eb7a5db8c27fbcfa461e05ab20517025010001	\\x70289f4f13b801ae4abedd19929ebdf2738a424c13848e931122f330b3882d5bd0092ec825b90a2a3b9f7316eab7082ae4c0818af4c785e838770297c7e4980e	1660583890000000	1661188690000000	1724260690000000	1818868690000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
419	\\xeccb91d3d3d6d4e14a6cf1dce65526c8d02f82942335b1af9592900fcc8e5901a4d44a2dc8ec11fa921cfe27b656e4d0cb9ab3cc4bfb6109029b78d66fb5af9c	1	0	\\x000000010000000000800003c7c536f78e71b1eec2ba8e1051fbcbdfcc39fbe8bb27d8e6ca3eaae74b38527eb866b670073d3208467979d77f0dd3a42614d9889815e70499e00b75956a91af650e1c807cbc323b4110d1d87119aaf75a9c8a7b10ef34d9cb2ed30a5cdbacff996d9056e6347ad44c0a04896b0586859f9323971878f505c150411283bcf9bb010001	\\x23c1fd467a429efb5a314365c41036bfa01528638a047e3330e63c380a8a141f968a9b21f9e1f77f822c1f06def3bf02ea867750c43f7f0b65ee6db9cbbcdc03	1667837890000000	1668442690000000	1731514690000000	1826122690000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
420	\\xf12f5c5a053294a9d506dfa79b3820043ae683e94c00e00b139241752d35fef914589e973f108d4299f14a6bbf8b9e8c83f175466acf9fda50d8ed87505035e2	1	0	\\x000000010000000000800003ab096c553d3d171d8bd288644256b39733cf7e24b0c31f926bcb57695758b84fc507153ce88dc6f5da3ba57bcd49997f00666317da3602a70823df659797a63b914a7af6e48754a5e136b726658df1993e75564f5809a1a87ca19804acb7cc021b410afb35fa49c652ca90e383a50a44800284d738972647496a4416ddac9a8d010001	\\x6a56e76e1902a1cf293db72c30cdbc82b74aadfab3a8cbe6ecbe1de3774d31f4e5c5149c916a12a18a9e72e7c5c83b65c85251f4be5ae2768db82180cf9a0d02	1653934390000000	1654539190000000	1717611190000000	1812219190000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
421	\\xf2877098eb9e5e4f3ffd63501f5686e656977f3831123d6f63ec63389258fbf155a86cd30d001d66182e6f7c3b30a58663ea9cd4093428eb5d9a32c0602e488b	1	0	\\x000000010000000000800003a361b005dc0ae5fb58e7766471ceb29f81a5d19414ad6c0c06df3ab7efb8e032ebbb7f8158fea5c83d398fe7c6a800294cb11a4dd14e2d74ee40e503cb294fdfc42f785c252e2e696f598e486497f22ffa9fe06035ef1aa6deea84e10cc9ada423054d2ea1f82ddebcd5f295533614ea226691faa2d77b3a718cb65001c1a5e3010001	\\x1121086c01db0d00695f7221e2a4bf9239fb1a99e43bd10316182c4893d0e902686697ea7d2f31a53abc51b12e86cc97d93c7db8860319a48542c0205858d207	1668442390000000	1669047190000000	1732119190000000	1826727190000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
422	\\xf4b33fa27d38c7d90b73e7025d8812630d6b14ea55a0c95b60d34cde12a66394b6f70de3a1580e85fde178d84f3912d95085f1d51184e0de55f23aa9e246bb0c	1	0	\\x000000010000000000800003e039b77ca3f351189ed82a35b947345976c0b2b975cbc3c95846e48854bcba2d803f31d98c22da644bf13ad0eadbca9f350f76190296963f3643cb6fdf4ddd0c66fb157dfceb0109d21ea83a83c7988dec64c55f458dcc5ac54b554854fe8c0710dbd4b2c1e89e000ff050218d5843ab3e17fcb06b461d30cdb5be4a6e66fc6d010001	\\x2e093006921bc1ed93282aee1701d58125795025208955007311b3acdca801ba7545ee0261c858fe9a1f22395d420e1ddaa2a248c2a5d8d54435bb96b1d5c804	1661188390000000	1661793190000000	1724865190000000	1819473190000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
423	\\xf55f9b19449793c97f6926dca00fbb74490f7c35fb06f0acf2287987e14935097c7c48ef544491ae68eadd99c5641ee5c32fad42f4b304951219882f0900736e	1	0	\\x000000010000000000800003ec651e8ee6a588857484502baf8959874d2713d5dbe3d5f0799059afba88c2481cf4e7f176e2a3509f2704442df8f685593b81f2a378b80ebfeb03d29b861f138426abf9850a1eb0ef203de2efa95fad6809c258020c203b1fdb3337692bac934dffe84784535d67de9ad5f75ffaf31291177453b78c80d3bb2954f0a7062f2b010001	\\x32fafe11d86676ca3fa854268d1de7ba8e76319ac5c1857cc613c5092b9f87349c341163825c3631eadab5b9715c3ae7f24501ef8fa1b9a82c92f15e17579108	1667837890000000	1668442690000000	1731514690000000	1826122690000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
424	\\xf5339ea2043d2204cad54b1d4153184cb6a4226e034a7516f03424dcd83ed00fdc89f7b7b72f17750a89d24bdd077c72ef389c8d4b6c5a84816e9000a6205e49	1	0	\\x000000010000000000800003d9130390a3c09d489f165ff6430d17458549543d1e3a447a95983d3174725fdaccd9601b03f4db9746962cb6f6b998f30ef5ceeb02f94ed7b441fcd0335bb78620d8ae7d986595820ffa29e15267b291e3be0dd23dbe9e9d8b317cb33c058d81594b391b5dd574a60b68b5409b65569ab98ef6da1fae9a91de459c8a31d3eca9010001	\\x74b9a381dabcb1f62a9703c055220e203988aa701fd9c9c84aeca253c10a3998efa0d3317ab206af20e0d98ee37ac35acc9996fb108bf592e4bd8412d7a1bf04	1681741390000000	1682346190000000	1745418190000000	1840026190000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x4d049dd5bcd99bfb41c56f63447c0a2058d61a5ad3852415816276131750b2b3	1	\\x312702caa88ce5e161ab50bf5f84ec046f34e35885ff7357b8ed30a70a634c854257b4a682af97a007566506c16e7b1263d33468d65f45e6cfee1f35ae6d6813	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x4fab48b22917badfc1e350e125e5d856b58803dae378443126f2dc71aa916ad0d9b39ad576e9930741fffe22b29813c426b12953a4a9da9ffab8bdb4c29ea8e0	1651516421000000	1651517318000000	1651517318000000	0	98000000	\\xe48798cfc252c42977fd5d2c5e2636ee283969bfa3e92b48777fea185d0f6f59	\\xa2c99f8af4e9f8a1054abeae456732c37feecbd7fcbdbee9a33e39f0d636cad2	\\xbbbb92716a3d74d45f05685433cfe62279df0657f2d54362341120f5d1a4b687c51ef26e346f04f83096689fe1d5edecdbc29ba03800bd73e25d37bb0cdbff0b	\\x8e352f9e7b1dbda4e3dd96c940287f6fa15410430ff4fe0a3f1f4978c467f837	\\x20f806d2fc7f00001d491b7feb550000fd84cd80eb5500005a84cd80eb5500004084cd80eb5500004484cd80eb550000200dce80eb5500000000000000000000
\\x4d049dd5bcd99bfb41c56f63447c0a2058d61a5ad3852415816276131750b2b3	2	\\x5c5700ec96e5fc731ad79d3ef634c8c04b899bcae143b8a66a3c4c7d51bc2a1d272f0c9773071e46dc5ca64dc9db23b0ce47f1c27d9f1894aae9c223fa8bca6a	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x4fab48b22917badfc1e350e125e5d856b58803dae378443126f2dc71aa916ad0d9b39ad576e9930741fffe22b29813c426b12953a4a9da9ffab8bdb4c29ea8e0	1652121256000000	1651517352000000	1651517352000000	0	0	\\x036509e108ca700c89abf5e7bc751f1789aa13d65eec048f4ad8e9600f2d2a42	\\xa2c99f8af4e9f8a1054abeae456732c37feecbd7fcbdbee9a33e39f0d636cad2	\\x9539b75958fd108f0895cf8b90d481efccfcdfbaf9b06492121081de8ba5279bc28ba7efd16b056c708c2408d4371fa300df9993a14fbf5be97306f5e5ea5302	\\x8e352f9e7b1dbda4e3dd96c940287f6fa15410430ff4fe0a3f1f4978c467f837	\\x20f806d2fc7f00001d491b7feb5500001db5ce80eb5500007ab4ce80eb55000060b4ce80eb55000064b4ce80eb5500004084cd80eb5500000000000000000000
\\x4d049dd5bcd99bfb41c56f63447c0a2058d61a5ad3852415816276131750b2b3	3	\\x5c5700ec96e5fc731ad79d3ef634c8c04b899bcae143b8a66a3c4c7d51bc2a1d272f0c9773071e46dc5ca64dc9db23b0ce47f1c27d9f1894aae9c223fa8bca6a	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x4fab48b22917badfc1e350e125e5d856b58803dae378443126f2dc71aa916ad0d9b39ad576e9930741fffe22b29813c426b12953a4a9da9ffab8bdb4c29ea8e0	1652121256000000	1651517352000000	1651517352000000	0	0	\\x1712a4ba2c33dd8f975f1232eb31f1df66bf971a1b79f809841cd0031ae99017	\\xa2c99f8af4e9f8a1054abeae456732c37feecbd7fcbdbee9a33e39f0d636cad2	\\x81765513b26470e6de0fab1b29d8f354f7879c9d95582ef3182af5ecf33b7da3f08512223f60be5ec50a61788714ae6bbd77572d57c95dd04d317cf74603b20e	\\x8e352f9e7b1dbda4e3dd96c940287f6fa15410430ff4fe0a3f1f4978c467f837	\\x20f806d2fc7f00001d491b7feb5500002d35cf80eb5500008a34cf80eb5500007034cf80eb5500007434cf80eb550000b08dcd80eb5500000000000000000000
\.


--
-- Data for Name: deposits_by_ready_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_by_ready_default (wire_deadline, shard, coin_pub, deposit_serial_id) FROM stdin;
1651517318000000	1819058408	\\xe48798cfc252c42977fd5d2c5e2636ee283969bfa3e92b48777fea185d0f6f59	1
1651517352000000	1819058408	\\x036509e108ca700c89abf5e7bc751f1789aa13d65eec048f4ad8e9600f2d2a42	2
1651517352000000	1819058408	\\x1712a4ba2c33dd8f975f1232eb31f1df66bf971a1b79f809841cd0031ae99017	3
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	1819058408	\\xe48798cfc252c42977fd5d2c5e2636ee283969bfa3e92b48777fea185d0f6f59	2	1	0	1651516418000000	1651516421000000	1651517318000000	1651517318000000	\\xa2c99f8af4e9f8a1054abeae456732c37feecbd7fcbdbee9a33e39f0d636cad2	\\x312702caa88ce5e161ab50bf5f84ec046f34e35885ff7357b8ed30a70a634c854257b4a682af97a007566506c16e7b1263d33468d65f45e6cfee1f35ae6d6813	\\x09f2f0defeeab55e120a6f2b658bed3b93811843056fb19e49f319155ce93131417c97899e5b19106cdb601f32b0dbdfd6fcec19e1d32fc5561a732c00f42706	\\xb04cd571d47d7e582f93924046291041	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
2	1819058408	\\x036509e108ca700c89abf5e7bc751f1789aa13d65eec048f4ad8e9600f2d2a42	13	0	1000000	1651516452000000	1652121256000000	1651517352000000	1651517352000000	\\xa2c99f8af4e9f8a1054abeae456732c37feecbd7fcbdbee9a33e39f0d636cad2	\\x5c5700ec96e5fc731ad79d3ef634c8c04b899bcae143b8a66a3c4c7d51bc2a1d272f0c9773071e46dc5ca64dc9db23b0ce47f1c27d9f1894aae9c223fa8bca6a	\\x211f79f665f033d80f1bc992688d4fcad6433b7f2e14ea92bd89034ad32e57a480550ba9ae3eb5368b7daed2bc7d89391c3bb13d3e46d9b20e0cc310f839790d	\\xb04cd571d47d7e582f93924046291041	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
3	1819058408	\\x1712a4ba2c33dd8f975f1232eb31f1df66bf971a1b79f809841cd0031ae99017	14	0	1000000	1651516452000000	1652121256000000	1651517352000000	1651517352000000	\\xa2c99f8af4e9f8a1054abeae456732c37feecbd7fcbdbee9a33e39f0d636cad2	\\x5c5700ec96e5fc731ad79d3ef634c8c04b899bcae143b8a66a3c4c7d51bc2a1d272f0c9773071e46dc5ca64dc9db23b0ce47f1c27d9f1894aae9c223fa8bca6a	\\xbe10b886ed008dae3e138c4fc05eacaebcb9b28971d7e41dee4b853963be0ae47a5069b6afc354184c159da38f035451baf0092fece3871eac1d28bf8abb7b03	\\xb04cd571d47d7e582f93924046291041	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	\N
\.


--
-- Data for Name: deposits_for_matching_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_for_matching_default (refund_deadline, merchant_pub, coin_pub, deposit_serial_id) FROM stdin;
1651517318000000	\\xa2c99f8af4e9f8a1054abeae456732c37feecbd7fcbdbee9a33e39f0d636cad2	\\xe48798cfc252c42977fd5d2c5e2636ee283969bfa3e92b48777fea185d0f6f59	1
1651517352000000	\\xa2c99f8af4e9f8a1054abeae456732c37feecbd7fcbdbee9a33e39f0d636cad2	\\x036509e108ca700c89abf5e7bc751f1789aa13d65eec048f4ad8e9600f2d2a42	2
1651517352000000	\\xa2c99f8af4e9f8a1054abeae456732c37feecbd7fcbdbee9a33e39f0d636cad2	\\x1712a4ba2c33dd8f975f1232eb31f1df66bf971a1b79f809841cd0031ae99017	3
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
1	contenttypes	0001_initial	2022-05-02 20:33:10.426664+02
2	auth	0001_initial	2022-05-02 20:33:10.54251+02
3	app	0001_initial	2022-05-02 20:33:10.634903+02
4	contenttypes	0002_remove_content_type_name	2022-05-02 20:33:10.653143+02
5	auth	0002_alter_permission_name_max_length	2022-05-02 20:33:10.666261+02
6	auth	0003_alter_user_email_max_length	2022-05-02 20:33:10.678521+02
7	auth	0004_alter_user_username_opts	2022-05-02 20:33:10.688539+02
8	auth	0005_alter_user_last_login_null	2022-05-02 20:33:10.698676+02
9	auth	0006_require_contenttypes_0002	2022-05-02 20:33:10.701434+02
10	auth	0007_alter_validators_add_error_messages	2022-05-02 20:33:10.710821+02
11	auth	0008_alter_user_username_max_length	2022-05-02 20:33:10.726919+02
12	auth	0009_alter_user_last_name_max_length	2022-05-02 20:33:10.736815+02
13	auth	0010_alter_group_name_max_length	2022-05-02 20:33:10.749678+02
14	auth	0011_update_proxy_permissions	2022-05-02 20:33:10.760192+02
15	auth	0012_alter_user_first_name_max_length	2022-05-02 20:33:10.771497+02
16	sessions	0001_initial	2022-05-02 20:33:10.793458+02
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
1	\\x43b2caf21f1f69b8f3d39ddc818c831240c5b13543f3622ab5e25ccf5b0aa67f	\\xbfc068b73399671267f80e7a2db9367fdbc0ad85408b2256bbbb552e8f1d2e699983118981771876612c6fd9b4958831dd5a7fc44141f0612451a8c3a0664805	1680545590000000	1687803190000000	1690222390000000
2	\\x23b4dc4c9aee3e39da1377d4f71c695a69260b97f6c85e1d4c3f0d9f2187550c	\\xccb45322f4e80ba85ccde353fec15d5901ffe50dc429e3da3a95055dfd815e18d1a951a1e7bc09a9e0393684dee4935e45e7112b56d0b2d58fbda6688d55100c	1673288290000000	1680545890000000	1682965090000000
3	\\x6e334214c767617221826ff543e90c523e117283184336d9b4def326c85a6799	\\xeba1ea62e47559c9135214af639db088ec74f5efab74848a76401d8ae3138f0f5c1a41495c8159a8f4b60e3e0c77346c083af0a73769e1bed8468b1fc8d58307	1658773690000000	1666031290000000	1668450490000000
4	\\x8e352f9e7b1dbda4e3dd96c940287f6fa15410430ff4fe0a3f1f4978c467f837	\\xbe18532731b429ee445c8b367e4d56ce354f1f06384fe30567806ab41b300889a5dccb672b47953482d4506e9fe954188db1f3591429ef8e6b51aeaf658ab30d	1651516390000000	1658773990000000	1661193190000000
5	\\x536a7531cbb6a84f720ed2f8924090d29c76c76a70cc42598f88bbea8ba124d3	\\x94de65944f1aa5105e8fa5a333b3497c8ce3e74178277cbd143362ffbc74176cd8bacc173667376f52312784b815face6e7277b85e639cfaeb94d2a94446dc01	1666030990000000	1673288590000000	1675707790000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\x0630b30ae08868c844ad1915c23eccfa307ee09fdaf19390afad81c6374e22b7012297193f2d51d55318220b5081e4b1603bbaac023aced98155fe729861610e
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
1	152	\\x37d3a4338f21aceaa932c76a56290b36329080e26e1ace64b91e9832fca0522a	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000048bfa9d9f4ac973a79f254e0d8d3b8cbd5abd23565fef5917aae9b4730c72dd6f3cec7a3fb5aee6add77822c1f2e6b3ee2c5d977b57d2bd0c338b135f70461e25609abda8d9e997d970610f3b1dcefa90c1f0dd24e9348c7a8b9a2249c39da96c4be1a1961da89a2e75f168616af076bb92d468119463aa291c4b06d51ef9894	0	0
2	222	\\xe48798cfc252c42977fd5d2c5e2636ee283969bfa3e92b48777fea185d0f6f59	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000005abfbc7e5412fd8e1d8ff09a51c50d7c1f3e5224caf37e4ba2642a76285eba04e030b456d449807d2dfdd16b726e23811d5273f870bed0b45e3d506f84e6f22b0eae62125716bd79124e50c894815d3e01c68ef42bcae4affc03c2f42fd10fd477fb77233cc336b1b2b8ed6843ecf5ec74b8ce7ea2cf0dca955841d0fcca919	0	0
11	244	\\xee727cc81498e5bdef42a2877354ace3d26d2e69d9db3a21d054144c1a58e93d	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000006bccbcf0884235b97b68191377e959671b1883d6dc695df564af5d52b83474302f309d9586806e96929f33145b9c47beb5a82affaf7247fa8b0bdc660511ad3b7e4b84f64a556a8b36508e7668e5583e2da3db3e3b2c1ec5c2fb04bf07d61755a6f46de9ecb0eb424998527328526d37c30463e51857a82841fe5efe2b1982a0	0	0
4	244	\\x2c2140d9df871ef4c412156e9465d8415015dba86d8bd09d1afaefb352eaf94e	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000617943b6718cf3fd3f2d15dfca27c91f6e925d0313e70a719c7921e1e5bc650064406891c51e1d0a6bc627ad00119fd8658a5dae765d2edec31e08d5431f9ea25d68af54b8773f3e08a5501557a10e1227a512b6f25fa1f79525afe5d08683d4e83188c775c16b0753631406ae9aa1f0e7e5fdb1f887ba6f89aa52370ee8c8fa	0	0
5	244	\\x46a94bd60bd44fbcfd1ff77d5dceaa6e1d8fc7fa98569e757b2ce0bce8d5147c	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000d4b999926a1cc09ce20a8d7f3ad53159e71614a52d79ac195c1c89fe926fe6ab47c9a740a6fed99acba126bd3f617afab34c020f59e8887fabf7603a6cbf3ac09e0193f660ec4dace42e3a8b654f85bc5c7cf621cc2e0aa8a329cbca02fd94964e2793ca9daf06906fb30cfb3f85342daccdbbec790d24e488af8517ba16f8c3	0	0
3	109	\\xdd75545f68ef9faddd51568747d1e48a1f5eecf5ae627d1a827aad83183db95e	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000000a7ce3315255efd9b5a22073724eeb1987127d126309a75a019f5cc9bab78839191dd8e6f8d84aa0dc22fe8bfcee93030bd160ad7a60573e84685a91ab42cd6de370c65419cd675274dff48bdeb3d82995591fbf652c8c2ac88d7b6869c364f81336714e901ec79a98463affe37144af4424f20e9e0717b884ef47af0bad9e75	0	1000000
6	244	\\xa890fa0b8b4c403cf27db984a87366a6e00ae7dee056d9210645deb4db1b5ffe	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000082739274d5fb740147593c439611a64a03c439bfb03dcb0be8bd1434f8beaa2b692b1e52338001bf1f4c98ad2e7ee750c239bbbd7632f5c9ceb60c420ca28212c23909a64f44fab43a1dbe96071ad3ff65b5dc86c0672c95f5a924b8ea06037c21d8f3d456d118411ff2bc3de5fac88419b5a2ff395742cdb357d05422b46aba	0	0
7	244	\\x859e46285e61995eb4e4a4bbffba81d1326cdab1530aab30e0c58dc247528c6c	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000001b032029c5837b05ea7bb1fc04266f93ff491a09240358d147ad8a597701b46c5fb6af1fb690966f3229daa03f42bf7a653a3678ccce9c16472e3c2868ea11401e2f1a4d1f613d8fa0e6e17d425648b4e7b8741290754b5f46e9b494b2c23c9144cfb4b3ce20e853ab7ae71fc723f21686cdf8e7bb1dbf37a1fc4a0100c23cc4	0	0
13	2	\\x036509e108ca700c89abf5e7bc751f1789aa13d65eec048f4ad8e9600f2d2a42	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000009152b1f47df7fa4e6833776225cbfdc37aca57d25e28fd406a66dbc214deadcd89aaa1aaf667a2b6e460db08da5084eaccd9ddee1f93253b8f94f831ac7e3125ca8b1d6526768b88bba3f1eccc186f9e1c6c11dff4b6284321d390e242f9d3a0cf89ea21eb76a0878ff2657a810c265f034cdfb804ae7337d23e461e36261e2	0	0
8	244	\\xde5d95fbbe7c727df79db4a7123869827bc6fe82e56b3b71c67ee96b5c2c8946	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000002c199f7cb5ac87f309f0c4954ca82064e43e9a3fe78f771f2f55a6ba5a49a05cf2d67ca85ef56d65a4a75ca1835abe2df632e86d96dac7847a849160ad5197f5a4bb377a3fae4ea947fb8ffa3b4a7a41f4a9f8cde4f53ef8fbf492f6222eb3e8705ed54af718e618594d277aa27c4da30896e94812a7ca4b676ae8a0c2c91125	0	0
9	244	\\xcf259169d898619e0d19710f1d3eb1e10c5f369323d8c549d036fbec40ebf8db	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000a9059ba3a2cb53775b016313511f8456159ab99e3d9d29f334541fe72700286d267b210701ef03c5b7c4390468f0201317f163ebac8f47c965801948d36e6bfc7eadce561290dfad8aaed879a676171db9c6cd1d1c8f06d704aa778610c381db0f3b6c12d435d8739e26b6fce39ae1bf9b8b55881257bace6775a520995d697e	0	0
14	2	\\x1712a4ba2c33dd8f975f1232eb31f1df66bf971a1b79f809841cd0031ae99017	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000004c561d445476dc760ef7ef1718b6acc403ebab4b8e81ce5b7b8a3f91043a767b5ba8cdfb6b4da92cdcbd188726ecef284433286b4dc97bcab69d4420ab178491e5c92446d691ef68695e41ab98712153d8c3c7341b844e984bf7e354fe8fd95d94c71167f414c5414cf6ffbe41801fee482d0462912a47bba344637e89e3ac9c	0	0
10	244	\\xddee2c25c1c7186cae13abcd3c8fc8c3f445bb758a315de3ff9efa0e3c8516cd	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000abd12319b1b212d8c8c02dc7891ec0f19e5cb7ba5e5fbd314f6349b19c76f294bb5645283a5be46bcb4f9c2c083ff7b0c9d2f20af064f5de55e70c1ac7d87cca7c488d0a02cac01d8549c022520d89ee33499815f8659402746cd511c5ef9661cc17cb9dfbe88c00713c3394e9c283e5c049ed29f293c4920e37239076457be8	0	0
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x4fab48b22917badfc1e350e125e5d856b58803dae378443126f2dc71aa916ad0d9b39ad576e9930741fffe22b29813c426b12953a4a9da9ffab8bdb4c29ea8e0	\\xb04cd571d47d7e582f93924046291041	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.122-01Q4WKM66RKJE	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313635313531373331387d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635313531373331387d2c2270726f6475637473223a5b5d2c22685f77697265223a2239594e4d48434839325958445a4746334133474a42534552415454524730595457445734384339365942453733414d48444238444b435754544e56454b34523738375a5a57384e4a4b30395738394e4835353954394145544b5a58424846444d52414641485230222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3132322d30315134574b4d3636524b4a45222c2274696d657374616d70223a7b22745f73223a313635313531363431382c22745f6d73223a313635313531363431383030307d2c227061795f646561646c696e65223a7b22745f73223a313635313532303031382c22745f6d73223a313635313532303031383030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22394d3239564e44575636445a504745354458484d385a30413431434443364a545445324a38354331433956313635544750415347227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224d4234535a32514d5837574132314141515451344153534a52445a59584a59515a4a5956585444333752575a314e485053423930222c226e6f6e6365223a225648544a4147585351574d364e4b48314a43473457394a4248433744343936344e5830334d4a435834564643485a354851474147227d	\\x312702caa88ce5e161ab50bf5f84ec046f34e35885ff7357b8ed30a70a634c854257b4a682af97a007566506c16e7b1263d33468d65f45e6cfee1f35ae6d6813	1651516418000000	1651520018000000	1651517318000000	t	f	taler://fulfillment-success/thank+you		\\x3f75a41cccb519f3c405344e42ac54a0
2	1	2022.122-0388CJD7CZ1T8	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f73223a313635313531373335327d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f73223a313635313531373335327d2c2270726f6475637473223a5b5d2c22685f77697265223a2239594e4d48434839325958445a4746334133474a42534552415454524730595457445734384339365942453733414d48444238444b435754544e56454b34523738375a5a57384e4a4b30395738394e4835353954394145544b5a58424846444d52414641485230222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3132322d30333838434a4437435a315438222c2274696d657374616d70223a7b22745f73223a313635313531363435322c22745f6d73223a313635313531363435323030307d2c227061795f646561646c696e65223a7b22745f73223a313635313532303035322c22745f6d73223a313635313532303035323030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22394d3239564e44575636445a504745354458484d385a30413431434443364a545445324a38354331433956313635544750415347227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224d4234535a32514d5837574132314141515451344153534a52445a59584a59515a4a5956585444333752575a314e485053423930222c226e6f6e6365223a223943304d37394e395251334743324742525051523944325434413842455041314348375945355756475233433041513657583047227d	\\x5c5700ec96e5fc731ad79d3ef634c8c04b899bcae143b8a66a3c4c7d51bc2a1d272f0c9773071e46dc5ca64dc9db23b0ce47f1c27d9f1894aae9c223fa8bca6a	1651516452000000	1651520052000000	1651517352000000	t	f	taler://fulfillment-success/thank+you		\\x79f8293977a1df17ed7b38353ae34011
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
1	1	1651516421000000	\\xe48798cfc252c42977fd5d2c5e2636ee283969bfa3e92b48777fea185d0f6f59	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	3	\\xbbbb92716a3d74d45f05685433cfe62279df0657f2d54362341120f5d1a4b687c51ef26e346f04f83096689fe1d5edecdbc29ba03800bd73e25d37bb0cdbff0b	1
2	2	1652121256000000	\\x036509e108ca700c89abf5e7bc751f1789aa13d65eec048f4ad8e9600f2d2a42	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	3	\\x9539b75958fd108f0895cf8b90d481efccfcdfbaf9b06492121081de8ba5279bc28ba7efd16b056c708c2408d4371fa300df9993a14fbf5be97306f5e5ea5302	1
3	2	1652121256000000	\\x1712a4ba2c33dd8f975f1232eb31f1df66bf971a1b79f809841cd0031ae99017	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	3	\\x81765513b26470e6de0fab1b29d8f354f7879c9d95582ef3182af5ecf33b7da3f08512223f60be5ec50a61788714ae6bbd77572d57c95dd04d317cf74603b20e	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x4d049dd5bcd99bfb41c56f63447c0a2058d61a5ad3852415816276131750b2b3	\\x23b4dc4c9aee3e39da1377d4f71c695a69260b97f6c85e1d4c3f0d9f2187550c	1673288290000000	1680545890000000	1682965090000000	\\xccb45322f4e80ba85ccde353fec15d5901ffe50dc429e3da3a95055dfd815e18d1a951a1e7bc09a9e0393684dee4935e45e7112b56d0b2d58fbda6688d55100c
2	\\x4d049dd5bcd99bfb41c56f63447c0a2058d61a5ad3852415816276131750b2b3	\\x43b2caf21f1f69b8f3d39ddc818c831240c5b13543f3622ab5e25ccf5b0aa67f	1680545590000000	1687803190000000	1690222390000000	\\xbfc068b73399671267f80e7a2db9367fdbc0ad85408b2256bbbb552e8f1d2e699983118981771876612c6fd9b4958831dd5a7fc44141f0612451a8c3a0664805
3	\\x4d049dd5bcd99bfb41c56f63447c0a2058d61a5ad3852415816276131750b2b3	\\x8e352f9e7b1dbda4e3dd96c940287f6fa15410430ff4fe0a3f1f4978c467f837	1651516390000000	1658773990000000	1661193190000000	\\xbe18532731b429ee445c8b367e4d56ce354f1f06384fe30567806ab41b300889a5dccb672b47953482d4506e9fe954188db1f3591429ef8e6b51aeaf658ab30d
4	\\x4d049dd5bcd99bfb41c56f63447c0a2058d61a5ad3852415816276131750b2b3	\\x6e334214c767617221826ff543e90c523e117283184336d9b4def326c85a6799	1658773690000000	1666031290000000	1668450490000000	\\xeba1ea62e47559c9135214af639db088ec74f5efab74848a76401d8ae3138f0f5c1a41495c8159a8f4b60e3e0c77346c083af0a73769e1bed8468b1fc8d58307
5	\\x4d049dd5bcd99bfb41c56f63447c0a2058d61a5ad3852415816276131750b2b3	\\x536a7531cbb6a84f720ed2f8924090d29c76c76a70cc42598f88bbea8ba124d3	1666030990000000	1673288590000000	1675707790000000	\\x94de65944f1aa5105e8fa5a333b3497c8ce3e74178277cbd143362ffbc74176cd8bacc173667376f52312784b815face6e7277b85e639cfaeb94d2a94446dc01
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\x4d049dd5bcd99bfb41c56f63447c0a2058d61a5ad3852415816276131750b2b3	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\xfbe39dd94c8698ca3a9d45c7f4656143ee091720b005d716e6e46e51673b6f566618e7e3aebc09c949fe6206575f221b3e262e0edf17300e839257f1fda7ad0a
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\xa2c99f8af4e9f8a1054abeae456732c37feecbd7fcbdbee9a33e39f0d636cad2	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\xe8c1c721a457408c01bdaae848465d56f33a03f8acbb8437fba92cbdf5993ec0	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1651516421000000	f	\N	\N	2	1	http://localhost:8081/
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
2	\\x37d3a4338f21aceaa932c76a56290b36329080e26e1ace64b91e9832fca0522a
\.


--
-- Data for Name: recoup_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_default (recoup_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, reserve_out_serial_id) FROM stdin;
1	\\x37d3a4338f21aceaa932c76a56290b36329080e26e1ace64b91e9832fca0522a	\\x4632d98faa1b616be808a5f51a7c8fc7c196d59c42a13bd158ceb1b4b936cdaa0bdb21be5408704b6955b3d107a6d13242a4698dcbe70db83ac0c456188cf400	\\xc48487c627af5a5f041c503a2ebf0d895e5787020f3a1be63b90c150505c4775	2	0	1651516416000000	2
\.


--
-- Data for Name: recoup_refresh_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh_default (recoup_refresh_uuid, coin_pub, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, rrc_serial) FROM stdin;
1	\\x2c2140d9df871ef4c412156e9465d8415015dba86d8bd09d1afaefb352eaf94e	4	\\x6f7b063533ea5331862df3a34be3dba5e8c69d601c4068ffb7dfeea559bc6375eaf524f1ecd95da63c6ed455c113146c4e41880f8e84aca6c6ac3cded4a6e602	\\xe0a13e5c4c77910a587c4716a117fc59f0750c8fe8749e433db9259c1f855327	0	10000000	1652121242000000	4
2	\\x46a94bd60bd44fbcfd1ff77d5dceaa6e1d8fc7fa98569e757b2ce0bce8d5147c	5	\\x0400d70018249fd2d739185259db8ae3a7595c9d929dfc139287dbd757d2d6ccf05910df0701d7729c3e7e7d621c0c1d9e662c41b38ae7dd68cab129a570a003	\\xc0b1651f471f2a6ccbfcb7316967d833c019d70b4bc1d467f4b8d35b3ca681fc	0	10000000	1652121242000000	9
3	\\xa890fa0b8b4c403cf27db984a87366a6e00ae7dee056d9210645deb4db1b5ffe	6	\\x165af153f3f9c550d8fbbee4374cf189f095eda1d0a7debb166d87282a5e8672046178cd060c74a47eab60111e581dbc22b683ce2c1cf882cfa95390aaf6ff0d	\\x257779444159ff391e2c081fb96e1717a0c74a73824925770b1276a8a4b635c2	0	10000000	1652121242000000	8
4	\\x859e46285e61995eb4e4a4bbffba81d1326cdab1530aab30e0c58dc247528c6c	7	\\xed971d09d4f7f02b81b7682ff8483318ddaf36fd469e6db46ce7a5cc94ec5d76da9af7b1c5017eaccedd9125bce41d6d20639e7a12c0819c6e838730f18b9502	\\xd228d819b987989c1ee967c18377d94136931ba924445d8ee07de72ab56da3b0	0	10000000	1652121242000000	3
5	\\xde5d95fbbe7c727df79db4a7123869827bc6fe82e56b3b71c67ee96b5c2c8946	8	\\x11c8956065d1d21205cd268ac513908261d0b813d4abc1252b750a29847140e73f947cc6c75b29b56304bdcce49edbe79ebe2563d90e2842291e0597faf72003	\\x609b91734422ac005ad43cb7b7aa876c2e1c05f19cd0ae1045941334ef6d062c	0	10000000	1652121242000000	7
6	\\xcf259169d898619e0d19710f1d3eb1e10c5f369323d8c549d036fbec40ebf8db	9	\\x77bf3fe54cc03af4756252a83ab1962a037f1d6b57e1f0e65a24e81b63b252308374e9d40a1cef386a1b3247af845507c74296b49e15f520a7c86f70375c0601	\\x5c3fc7dbc4371be2b11523ad45d076b9d66520b910b89b6f77b73c89a73e9f51	0	10000000	1652121242000000	2
7	\\xddee2c25c1c7186cae13abcd3c8fc8c3f445bb758a315de3ff9efa0e3c8516cd	10	\\x8dd80e2fcbf034f2f1e37c748a45490af35484e7658f79266d6934bab94ace41110f0947d3295e285381c541712f3cd809104e2fd433e02e88d8067c29ad0102	\\xb1a2031b6d18a15a5292662058edd19736f2e936ba24f312f7ecba3ea0143040	0	10000000	1652121242000000	6
8	\\xee727cc81498e5bdef42a2877354ace3d26d2e69d9db3a21d054144c1a58e93d	11	\\xba98941bafdf2ffcf82c5f90cd2a2b23671b85d0ebfddd0ce40a793125973f978636316a5544a8a235ac1854ca14a98879a501504bddf73849486ca678c22f03	\\x9d3c52bc1da63b9ba505ecb87adc15a9ef4a76a109ade33e008c724826a33ecd	0	10000000	1652121242000000	5
\.


--
-- Data for Name: refresh_commitments_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments_default (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\x608cee4350df48ce9e86fdb755349ebea460c1a8a81f37c36d0727f7a0ef2e7fb4cefa2d5d2728cb9abcd9685732512b9804c3fc48d983c51455dad962ea39f1	\\xdd75545f68ef9faddd51568747d1e48a1f5eecf5ae627d1a827aad83183db95e	\\xe7279b799ef5a086f27f9094eef366860637cc93d28ffd0ab2bbacf69044b503ffcb7ea64546c7eca5aa4ff4d67cc05cd7a30a96517cacec9e75f7d867d67b0b	5	0	2
2	\\x7a923d7d2a67bd9179f77de0495bb982d3885336e2520fb7838a8d612b947586d42604241c48c9ac337cbf67b8e1dbae0333306e2a0ef425d7a56695a6c4b2bc	\\xdd75545f68ef9faddd51568747d1e48a1f5eecf5ae627d1a827aad83183db95e	\\x75e5db0c89e064baf67f2d9fed93ce8f159459e4a71a10484c3fcf96012ae266e511882cca89e70a51caaeff602685ccb60bc46bd9b24d1e94c3105b11b14e05	0	79000000	1
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\x85607ce3fe7b3fe18a252a19f238d5a95e48de2f08f23a3f7fe70ae08f0707001feb5625067a3168959715bd0c3219b5a2f5cf4789a069f4759d8e1c4f8e440f	382	\\x00000001000001004492fc6c81045507a45a503d2ed5bb4bb8c8ae97e9c7eb1b949821df70dfc88ed82ef634de50e7f648962be3e5b1ec84826ca66a2470e542bd10172d065073a1a9d220e7efaaacf1e1ddc5523b54268ecd19ff1d7e00509125033bca7ca9b827e87229931311c18674c5f08af4d4a3eeecea5641c33358c47b5c8eb7ef88d9fd	\\x8b782f9e222d92ef89bc9c5d843042ee90b87d977260ffcc0ee097e617d1c1bd11313a93d31b3eced14cba65951ad55628f9d4b0282ba0825185a1167a64f231	\\x0000000100000001410c32c2b958be3a1b9e20cc1b243d51f7c72a03b6d12950941d7426388166b71973300e19fd6f79bfd8de1af234b565d3fa9a8be51667da316a60452688d64b2dfead80c73ef9549ae0056cfabe6c321c0e2ea0c08bdb70fdb48941db4b9e35f182941eacf0d3023657716aa62e29f358a479052c989bc07ff7bb7b675dd537	\\x0000000100010000
2	1	1	\\xa29978124ddb5132a2353b0a9540a8bc2782dc925b1ca43463691c28ddb8ed8c53e77bf8624d1aebb460c1211666d360bc9075767914536f62d7875318d7f80a	244	\\x00000001000001003249a888ac4494ccd118a7ac457bae90b9dd46fc6f11e2b9e5e6680a053f41c73007f50e2e3a69b307e992b1d4d949e810ecb82d4c83e9f07a0e1ebcc2bdaad11c05f987869c1e02257b23ade19e5934146d71805cd06712702a917e31c56575f6b33519c01665195bf26c556297e0238fc1e780900c4b47d5d59303e98ae447	\\xb44f60bd4c4bbd0732b74ff13c11da6fa86543b6d33cda7dfebca8b9ddd1b66626e2d5abfe78cb77e40c33c9987c46b955db65f34dc6877b294723af3bc6ab50	\\x00000001000000010eea2f2f635c84b0ebbe37c91172c3ed4c3c3a148addb2c12a6fd7aa78f1bce8744cfc3e5d838741b02117458acd0633c79abd25cf9b2a38e947875c42f5a3c0ddcde5eb33055a37c9d29d602ef8eefa71c1759eabca9971fab3261a5a1a619b8f03c18269c12d390e123cc76cfbded5aba77beb6dbb0600f9ad5b5eb8e5b986	\\x0000000100010000
3	1	2	\\x083c6d1082d3bedc56552530ef96728fc348fea2c7ffddf006015296e416fb233bc2a74bdcfb93175b0a8150d3008d3e5c5dcdd6bbd6944a879c7e5f071be30f	244	\\x00000001000001002533ad993dd6c1f2af8e6400cb5f895da01938f3e133e948d58b1f800a994ef15cef00655f57ca5b4786256afa6a7514ea7604c9f40db215bc8caa87d6dc90ee666db321b0984e69ad357af2d5cdc50634ce0932d7ed15e0ca013d177cb291db861fb79e1f64f431612b8ecad672e4af5f2d939c5c32d05409bcc086c1bc61be	\\x81e6840ee3e23cca949cf2c270bb7984a472283f38d627d1efb11e8c3e95387584bfc7b8b1da42099f82a031a93c7caea1b5eeffffac523430e55d3a65108e02	\\x000000010000000188be2af8716c4cc2fe39a50c615e0ae11bb5c1fba08c37dc73e7058ded6da7537a8f4af6f4a1bf038ef0e4a350689eabfb9cfc83b32955bdfa0fb5100899534e41572e2e692df5abd2355fcb116da9c651d74227a737b27f47fe384940ce7120947b6f918f249958d753e1cb79147311dc7d27400d942b7f3982167f25de6e06	\\x0000000100010000
4	1	3	\\x40570aafe14f350e6ac9e69bb88c09a8f0bd12f769d1134ae2b94fdbdeca7feba37757749873a0c989bf5f952377fda42dff37e12e706bbacfd501cbb835440c	244	\\x00000001000001002219bf55887ce6bf8c4637931bfac946fab26b8f17f7f40b71d1fb5bc849d709a8a53b6515b43af26aba9e19039b5602d2d4535092a897a3d106982684ca5d0dc800b94c96f016ee6a843a9ecb872c327e03ec3efd65008924e4072ad2b2e649b3f5e7e0f0b370a783a63bc79d41e2fde312dabd098370d690151a6b413a00db	\\x1cbdd508984ce4426e3d7b8be222bbe8e0ff69f5a79ee47721221b7271d5834603bd9260a6300256bbce3ca520e0ecf58c155ab8de5b5f106ef9f516ebfc0a72	\\x00000001000000016dea63c7eebf4af6461cf4d5fad043f433007dc6f8114434c9d79715bba6b73f2f62f4c374b0f33016a56363102cbf9ac81c8d6e41ce7d4741e5f92a040c2b4f9aedaf9c611e82197fbae3220c44c34eeb2c48949e890e9bfe395bec1b39f102c698de8103e88ec63c03443fe5a19df1ff9801a7b904f457b81b3c6067ecbcd4	\\x0000000100010000
5	1	4	\\x46166f44e3d31e9394b7daeacb0373260841c737fe63ed8cf4569e1b3e6a88cdc8f3eed54e1bb3606f9321a09197d07fb637289043e9efacba4f61b2288b8203	244	\\x00000001000001007e026cbf9dc57e7d53d7b7b92bbdec8a1b9cdb791e7414519f0227f1db94b7fd9354ba701fa3b625db4833f2c9ffab2cd6a43e90bbdb16ec9eb2ef624e0774b9d9c7c6401556e0602d4dfc216419e35096f8dbd530480b67953a26fdd2baf053bc44f668b131a70df2d582e46f38db75b5ced42af39b9c09f2267781543f4577	\\x01b23d79c403f34d4b2d659c3090d2ebd7b7592f6f65958ae2a073277aab64fec3b2f83946f89c656697583c07c7a63a0d478b24a79a484d6b396f59b4f310d3	\\x0000000100000001ca336c77d470fda362b210203aa3f0678c71a030ef6c30665e6a48b86fa59271b841f2b3a1d3f4e7c18f2396dce49c08a1b18132253af3265b2c74be5fee9e650d243d05d54f610e9f3cbf7cdd67fd3715bf4164c3ffe0e54b9d486891de5c0b05759f7b932f2e4eb323944a69832086b8a9e4ded3fe1bec69f7bcb91b635a23	\\x0000000100010000
6	1	5	\\xbdac2c742db0fad5d9a5b0d359e650c10039489cfa54931f27cf51a9c348041036960b4b196e68b647f238f2efa4b6d48f7fa30ee305c9e7bacc9f0f5b03eb0c	244	\\x00000001000001000bded5df8b4815adb1681ed89c138041428b750e3c80cd4e539bc9c897004603a62515273a82fb086d11f0e1e01d4b3b9438cd4b510915bc636097945a267163787bb9cf947baebcdba2fcae5c7e2d091606128a4708620fa3e196c379ffc3706dae392a502215bfac1c48dcbb47bab25fa21fe60a66efbf2c7953f0bf3dc41d	\\xa6dd4f9bb07f5f716152644784892f5108c03ce8d50a70b53803fe5917b4dbe8bc49898eb4ec61db14f4c442ad942924e9d7b2aa9825493f1e6a404f0e311e6f	\\x0000000100000001a8a5e587127b43183710b92629ee1ad6967283aede62c55dcde90e046c7ec6ec0b1c6a2b6f4a0eec51668202c021754deedaafc385b52ee1b9d8b4dedbc7f5c1384be87e49cf04db30033fa45558426960eb588099d65774f5c77ba4aced5c54cd3bfddde022fcb63d949d403ddf4add7333c703006f6f3b72a7b8a8d4297c9c	\\x0000000100010000
7	1	6	\\xe8be481e6b9491e446b3bd62e5d0179a0f4d0f9294b4d090255e105a9297be62e63cea0badd312b2e4f0962c545fe2eec884c7d44b9c3d353d3f20d1db1d5f0b	244	\\x0000000100000100b0fc83ecd648d4e9be16e3a91a82da461c7c13486064a8f5a80e52e06c39b801f3b62e535dc1ced070b432b92220ce08ab255b9a133ebfc1eee6895e1005f90465f3df1317be962d5b29991469891c22292ec56ae496c16aa1f1c20b1180ae6d107c2bb0ab71e67fddad0fcbb792cfaceb2f88834ca8c0caa9fd852b4c64b5c2	\\x9e31a5ade1eb0e65090a04d8dd4a3c962672bbed76bb21a839e0df358ba570bcdeca38a9a94774eb483ea8ca65da1e4e7037c0289bf08dd8cae0ccc23e6a7160	\\x0000000100000001c2d63224fc9665fbbaac190851b86badc811c6a6e11af89d4f341b8eb9151c2e8e9df570d27653db2b96548228206e2a762f69b9ed7d6ab3876fcbd21af6c1cd060d802661400f09ef2ac8116a960f17f87492c5eeec85da81518e515474af66ba1afdabda09f2c917cbaee8ac91bcb2b2ac0c103fcd84480f4f769ee8789a50	\\x0000000100010000
8	1	7	\\xb2091821a909fe0217ef1fd04fc9785839c158abedc5f50cc9e76053f0fc0e4aad6e790095c2e82d0576bae51b67fb80c3f39065b1e6a8fecef3f6938ef2c701	244	\\x0000000100000100208ee435410093b6facd5cb379b2d8903b78e69ee3fce72f1e1a8095b6fa241673136f3903b776fe9a01932d695f18c2478e45c18df5d7f578cf5753c5c378e9b21f69de859d06ba96effa62fa2e2aef2a50ae8aac0062a118bacb2bfe4d00ff123c6c2cba396fc71eebd3746a3f350c9a23a42d1824279b64999d9a9f9ae575	\\x23b4103d4c7f454f72fca37ae339a30ef5e0d611f3124a79d84de72eb01621819fa45fe796344148840a574ff00b9ba4de5def3f1eacda84f283df0c0a226f36	\\x0000000100000001112f8408d3eabf0401ced3759bfadca2f8e5bffe6825098038337165b5db88db40a95ee4b6415c821a0b2a7173045b973540fad194df58acf9ed14a6a63514f3b03c81f4c1035b1a08416c30ce1be093589f33e1810bc5602f8b6c2ab389113434a22a0cea58064fedb8912296f1321b2d5c8587b6070168b17ad5bf77ddd12a	\\x0000000100010000
9	1	8	\\x1e374124cede56edbf728bb836a09e6bbf979a7bd9c65da0157fc8a948a36209f28fd81c557d0de43d11155ad9dd1daa891137e6fafe2a1bfabc3a9ae929fa08	244	\\x000000010000010001722fd47b14f2b353ba1a44c2761aceae5e87da625f8e5afeb6485f94eef4d6a05db6402dec25150c5793f928ea1c80f614f464481986e82d0dda1462cd9a4a8ecb1677d7b82dfa8a07728c40f098f5feac7233676014c023ff09627c6d9f913640500c7fcdcc917327d08b76c770c0f969b29f644ae033f7648ad21b5c76b9	\\x7160ba5bd2f693d3005425721ca09a09039a0c4b7ad732e7d7dd84b030dd40f2c85be17b07863ad5b0b0f93e593b7ef1c58d4648493f4076be2a188bd5d18b0b	\\x0000000100000001ad70f3b06be8a3f4c0df4e223a870ae6d90ab2d40733c764f254ff0ecd9b348c88944de2be037cd7a09c6bb20d5b2510e82ba995cc92b6e9ec870c6ed74f926e10f24ff69ef4ab5b3412bc07944834a71a857d736ab3f84390c8647bcf6abbaa6d781ccc6aa047db7771969d79fda51d6a6cd0df3c9c8f9fadbc42ef7229540a	\\x0000000100010000
10	1	9	\\x97d9de8bae626d2f7ca1148f5112497a9c1f68af2052986ade35bef64c207f75cc9dfc77f325191704e697563f82cc1b2cce66a8522c8fcea33a80d0aa2ad806	2	\\x000000010000010026c70b50711872c1e6e2b15f693564886384fe6df32bb55dcdfe16b97c0670a48ad05dcfd09d643633f07400d75180371061a9b1cf11f789dfdfb2c0a2ec4d60aa666a0835cddc34af5e1b6be30fee19c6fb6c3319b97c2780778eefed6e3f3180f71e2979cef9eb1e4957750303e745484c7465b90e77ca84c34c46c73ea324	\\xd080ff97ba144affbb017d960f6dab203aa01f6e7aa6b6483f6f95aa03bc0523e90fe2e1569bcad0c8521f4d46b77f08674f0ad971d980e945920b95e580d481	\\x000000010000000181cfbb54ac2958e36efbcc2e1ac1a0cee1a9c8462b09ab53e2c56a48da1eb106a758ca0f6584387232e4510c146011a7353c7f9dfe0a22ec6ec5cd310b5d7ebba225f57b50802b51181f7722f3c8b201c9b697d40d1303343ebdbdd8be8014af752b8f1af71c6830ef0b59b2f721891fe966474fd59fd35deb86925e0785908e	\\x0000000100010000
11	1	10	\\x4a1b5027e358da25458acd29b0b37c79daf5b68b2102c80f9a5de2a6323ee8966d019dd3edaebd482ba26cac7cfb4e864d6b260c6e64641f6cd71b248f30b602	2	\\x0000000100000100c20a4b491ac237a2a282097b8e0a4935caa54c04018dd3f321d717d327c3810009633d23cc921087f1c040127a6b0c3cdab869a924d42a6836dd7a0dbf0c4dc3c12d71367e2dc11dc12f5a08c81abbed44d2afaa6d68da5b4bf67e19227404a6df55d5d25cc53353faf122b81f1bee45bbb81b85e27801b1c9a1b90750532a2c	\\x6fa170958d325ac4f3eae947e8e54f7f6d7fc24ee94f409f75e4d2573a87ab86c051ae5764739b2f97311fb3b2c295e3642f430e72cd92b5e9655c3b855f6b33	\\x000000010000000163099ce169b3b133a4ab3a5852f6a832a0e8ebee961ebc6c41af71685d0460070a8681bd7ebfd583c73bc9e30f18eb90742d9b64f692d589d96606d3e8d4f73140fbdcce4e568d047cf59934d71b65eb338df08d75f93db19055debe25ce59d1e120d2ecde86f9b3016d3a0a832d4fc10cd6e0e6beaa99c38fcbe660e89574c5	\\x0000000100010000
12	1	11	\\x1bf5c0a2ae8de86cd40524af5e73956ca52c3b38ab8c86934633d777d31bea165968e09634fb50a3dfb2fe48b991380e4fb30ee65c909e01d841d5160254b60a	2	\\x0000000100000100733481c9c49a1ae9ec40063194bd3256de07beea5028200c8f6b82c01f6112b31aab5defbb626c676ea0702469ffb199908ac7737c3e89e254616f127fe62ae46b92c94fae937a92ca1ef2d3153a7e7c3a8e15341ffd4adbfa8a9f5b957b8e24465c36a310c1dccd5d780e61a130c9578e9a59897d870195a189b769d9080306	\\x58ec1a447b877666b0b99f7603234d8dacb565c308c96397ced1d9de0e1b4b5f6507848d1ff071988080cad9a33e9bf836eadc64dd5afc5c8134b0fc4309a242	\\x000000010000000193eeb6243d3315c823f87954bed0cb4d4471a0b8dc87a6137806cb7603d2d220a1bd1a21cc8eb87d8a5bf4f19f67673164ced876bf50d69975a052b81e8d2a4d36b847709b0f6ce9c42e250f8005c0d8d7a80a58679c87e150cbb0c11c645441ab08685a53be787838a0034a512a51ee189ba1c8c12ef6047129210907a53f9b	\\x0000000100010000
13	2	0	\\x54be7eb5f06bc313a132d396174139cbf29a5cf5d9eb14627fae4e6f7ebb9c48fd36d1b1ec3006e0ac350e04e80cdc370578220f136c3282f2fdf40d6346ed09	2	\\x000000010000010027b5d612d016a35f54d4b8db502eb2bf7426dcc2499e5cb3945db4476dbd652a81942153e0f02100c42c6c07fcd64ce9a5d81377bd880d356e6f89fd33254b79726c1ab8ea26e21d70d8e2c5428805a62f9b3396b6a6a147f42ce0100f89a705b7f5f2b9686339ab3879f50fa16faa6b870d0682e32992623af6ce18ffbea8f8	\\xdb506b45d6c311e032f6941ea720ebaa447584354e2da5585890a76bb10d64e7cf93aaa179001bc23bb9dd759ae2a8be0466f7696ef0f7a711a8199139e2146f	\\x0000000100000001abd3034c2ea23bce8cb6ecdefe69cd3a44b7255175d1d05d17a0126193705c3a576f0bc3bfe39fb0a58d161f16a7db8d1e568d64dbfd10c4c972af3ad18eb1aeaaa6c5732a87d64b168b0bfefcecf5eea37e996eb67374c6fef26af3644cfdf255fe62c58b82d07186ec610d64f6b035b3fa24687ae22cd12fcb5d443354c7da	\\x0000000100010000
14	2	1	\\x9ccadf9230dcea9248d5c82bc054e86dbac8b3bcbf6bcb153e9eb697ac5d46ee51cad4ab660720f1b96bd4cbd319ffa7e473be9eafd4dc1e9ad3eff5cafe4001	2	\\x0000000100000100288a3e955f1f86d3df6abb09cd7dc728a68122450845896f593a84d931e0c6d278893a5536e2b1202e4539419ee05f4ccd53c06ed654f23ddca62baa1cd4302b0709eb34e2dce62a878065169df9a2818a39601d325dae81df82d17ff04d082026a37c8114c161aefaca1da14e15856ac76494141a045252b05ba86e30c53b92	\\x6eddabe9f3e6cd21394eb8e2ebcaa7dd8448e743558757b33288cabd970961dd9267136a4dc23fa38ef2a667dde22275eef73d63ed09d81c453a20af7713873f	\\x00000001000000013a0d30e3162a4a8d7779ed8bf42e6216fa5612c0977ed3b31e28ee24923b0cb4993d77066f2ee21734b9738e2baa6862b2555235d560ac931d04dca69bf02a0ac93fd03fb17fc1bc530dc979a12f27dae0f2ea74f330ec270c38a76976ee8cc232838083eaf4811cc068344a20efbc29e298216c4488191b22017473cfafc661	\\x0000000100010000
15	2	2	\\x10253d875545e2f1817481c30986dbaaff4d76b802873490d2a8746cec40ea39829366940b876499d94225a695449582b62fc45a902ed557aa5cb7c9a7d98901	2	\\x00000001000001005a94220bbb231902e58f70e5b64c8e0984e5fb86e7c7f3ad2b1f8c6060de8c1349590324956168e9576eeaa0829a73738146cc28447785841d4ef39baaf8af5e8987ce4803577c5354d38ac4761a835ceccbc6522eb60539fb8b6d34847d333b666dcce2765f73370c9f1ac0c84222072dfc48dba063af9cc9ca89f2c1311452	\\x41cb98b136ec4a4e4598992709ea2f7b5c5d9db14975fd13d46f118a86a7a38b802f7ab00c36decafc1b24034a8f5e74637b954f24fd4fce5a4a21fd401e500a	\\x0000000100000001a8dccd21536dddad3ff06a97e2b521cabcf2c19f0432208e09694b4b5ee5ccc378463513306a0d598ab5571fc910c2c85ce539cd1e2d01d82ec167234eb265077acffa1c92cd6e03fb6f9922a87f652574b93732ddb66023b9d5d857ada0cda960748bf241bb0c0be7279370f7c765e22b20e819ef9586146703390e93856a20	\\x0000000100010000
16	2	3	\\xda66e069e7f682b06a28014618f600bf2ae6639a73f83811d96843be20b77042f0f2d5043dfaf84e082b76e500f264910e2be6d41cd27a89d8a0b5e4693ee40c	2	\\x0000000100000100a69c52761103bfef94d63fcd8a27dbeded18115c2f013e7c7eec0f53acc43bbdd48103a5681bafed409ad97bb204cb4a6435d6abd1e8e85bb6ac3451bb31da6f05a3e1afa42a21a8e1a77be70bcaba573de1295dea56943536012d039ce28101c17910716bdfb45de49ab027b82862a127ac7ea21c27d0568511c8ca20bcfdb8	\\x27dc692200e30319dd1bcd55a632b92689a4c6a3dc80db7c7482338409a76e11b7bd61bf2639219c79b225c0e898251ad73d025a915c148ba8f104ef66191ba7	\\x00000001000000010a0891598c719c4a8b58172d572d78ab948847d4d327730af3af2927ac8d4f60d9f46f37289e511ee089f7e85602ce7e8d5ae1453eb955541da6cece4edad39bb10880475edfe1d730fa29c07dbdfd9297480a28b14efc199f7600f58194eddf460a950828beaefbe455650e5d3d33a55f20e2d43f4427c884393b78b45e2825	\\x0000000100010000
17	2	4	\\x266a8d5103eb72194d5705ca2a9b365519a263daf79b9be559aef815c75cab656dfebead5ef2474f344aa1911ed33f5cc57ad182ad5250c19cb8e85966742608	2	\\x00000001000001001f2664d29f08d641983d8ab558b26a12586ee4b9b06987c2aca503e0cd791117bf76db46ee46a1fdf6c61f534958d4f3fb5d2f1ea719e48a4a93d9fb0abffb6c28fac14951f292d5b665872249fcfebb83d283eb8bd7b1006d316158a5cdf591f701bf32f183927b9719c9776ba754ac580093402f30cf4f0c89d91f0f2ed142	\\x31e3a51655563e3e22709b814f6e59f80b0ed9af273cd36aa3b1c08aad341202988d71dd5ff17aac0efc7d661e99599643f3ae14cc3e911a3c40a5961d0376fc	\\x00000001000000013525e28ca2a011359abc65295ad0bf093360d80ea49e850552e01f9dbb67a744f04f3f659f762610b9e7b14e14b942ffb3cc793a7ab28f900bc0c77058f3da67aa58b681bc1bc86db0212689f18dadb24faa7ab252ccc196d82c5c562c244d56cc593cf08ad891fb94122c02b9c563e358ec49348dd07850209b82393359838e	\\x0000000100010000
18	2	5	\\x67b9af246502d0f994eed88afc37f535ac13a3f0f36c4d7d60f4d62e27649f4cefe4b4977f99073e3125755117bbe8c9e88b8c68e23a83d2c92472fbda66b00f	2	\\x000000010000010093fee280c1cf6e2ddcd086a6fc118bc83d73114c553db9e870cadd6186606b8c0748d636e4c4c4e605d09c9f7439ea9e4d366e155d23a1c0e458336c1fe24dc78a56a856cf08508f7e58a8abeba2f1c2b922fae03c81339cba1d49f035985ee06cc67403381be30dccd92ad862097949785103a5a8294fe75f69ba25aa237801	\\xc6fe062dc2eb23dd903e405a59b961036a00d2642e28e274d6871b8003c9a312ead249656437a5c2b687a50443126e4e2a5dfeba801db89221d062d6d8b677d3	\\x00000001000000019c96f17eed7fcd00ba853ea9898d270f01332f05946454e35ca8447e1d8651845c1026f9793013c8ef2340b50f1dc3b2be359a988867125d98f6e6bfafe02f3811319d840d95b7de57df5ffdc71e54fb643e27157aca2fa4b54a2b1fa93226688aecadceeee78294587500d1394f213db9d1d5f0862641c2e92c54af5c9f80ac	\\x0000000100010000
19	2	6	\\xc5df172bdb886d1633d3e46f4616c594c55f59ac9145b8013b7624cad635420df24062c163e1058c641b98054fc65ce5a726efa59e5bc849b67c33f579abfc0f	2	\\x0000000100000100941fccb20f0be031070585e63bbdef5f0b80095144dae00cfd66dc93af35cf750b91d33f7aa79a853559fbc9e40146f6df7522e25af27cef09379ee9b95c5999a4e9db068db50998b66c26f6b5961fd972acb32428ba81eced079ae634664e4a87c7161d2d2b85cb1509ac3227175d5d195b514eb6e1efe56635bf205bce3589	\\xefda4061288a419aedcf60efdd5c3a411ee6b604aec23a528b1f9594093b2279df1aeeb88601cb85b7d947fa4aa2e7e8d33f52e084f7325ade3dba8f254e1858	\\x0000000100000001c76428049fd61cafaf5fce5bb33536d58f1e48a5d25e6ed072f68b796a8c55e450c180167a5f1629fd36e1990bb3074f8d3bcf127357a953d2d78b332e95a6926ecbdce11e1fb4458779c7539acb29a22bb007927adcc444fde0de56c6476ebe61b0ce7e49aeb3c4530deac53ffe859732e3af84d05036452bad4ece2d4e64c4	\\x0000000100010000
20	2	7	\\x74d104dceb3a3d5ba148555c65ead19a56034a97b073eab03a4e62de6bdd1f871a312a72c6644bfc3d4bd3b4a01182574a88cd9cce6bfb11f0137d85a059d70a	2	\\x000000010000010028db7ad1f5c3d195e36d9944e551e31885396cec9042d24722149f20f5846f5059e8902d05d5558e07be7765a73a1150fe8c83810e25a0c622704ff1534ebd6fba98714899ea0e69bd29c4669e993bc5dccb6105508a61cf0cc44f6a98d1441c070006d289adce45e79ad8baf439fe570aec8b43360cec650516859d55b7540a	\\xfb41362bc5be8a8ed957a88763059a88465bd94e1a78185d90a9ab2dc3ebf6a8ad2789147d72d05efe9916e6ba5f73bb75dac776c19571b9ccb1a0be67d2c917	\\x00000001000000019cf222cf48609994ed71e4f05130463bfb2bc065a1d9bf9ae9fa6bb37f0830c64bd25b4c490346ff00293e25546eeab75a2657b36b28a7dfbd7175ff4db99cc521ee97e477b23a67653f10336e65ed5637c6ff42244475680833ae89167e58e7e3a792749944b52b32f8563c78fffa21ec68b612b3851384e4ac9ec030b192dd	\\x0000000100010000
21	2	8	\\xce9bdffacfc507dfebfc276befe671fb8dbf9c0d63803b63b8a82b33f9f68fe628b90f0f355ddeb82170d80ed19afbf5febb44a0d165b94822fd1cf1b97d5f01	2	\\x000000010000010001138cc5a587927a52302950386dc7640fcae929ad579c2561f0bbe6f55aa5463ec248c285bc13ddea079d4462d5fcfe07137bfd87fd9db07cf7e4a17245cff24cf7cbecda6e24a281bd141f270256ec1246946645de37f6629d87897fd35bfa93763e192a22954d35af762d36d51668e1c4db43d3c1930720d0f286791e0021	\\x6369786dbb40012fea118897287bd217ff3bb5a09cd14599bf38a7560f780c106470a6250042132fa9468c62ed3ee7953c37dce6e74dcdc4fab8cb2afc9c69ba	\\x000000010000000111a8f72f1d135baa35e1b7dc8df338f4341a770619f0a72198011818fbfccf31f4d591780f0136d867b52ba49499ab23260596b2a8f7aefeac1a3e1db44c963b72579764562b5e1475a82313e70036a0df2d4ff09c5ce788bdfcfd2b48a1960583e9373cf104570f7b8271b26506ec516714b780768980d7554f0444ef4e5492	\\x0000000100010000
22	2	9	\\x224f903529ddde5b8b77aa8ae9e0950c5a52cb2ee424adb1fe70d749f5a92ff0b7b581c2e7a31e0c376c54da4d4b0ac208ac5d9b68aaf7c7dc862124f583130f	2	\\x000000010000010031eb251a659b20e782e1465b8b7a5ff8cbcbe219ad8b87cfa16a8d74a854dcdebef89698f159cbd7413a4c67a885fb14365c2973d4c165e6572f291ff11a5ac00575463abc42d770c1d3be01ea672b69653d1c5c7738c85433e91c4a9cf6f06ab1164375e67f22ff5690ba2fb9c6f79027b432cd63f03a48ce981a005b97fb	\\x6e9a12e3d21460c4fb9957ecd29c194be654d8767cafe2329fae46295f927644e205073ab980e41785821d0c9614a6af50aef858ee67ea049e7be84fc1cdd0b1	\\x0000000100000001386bf78695de4118aab930e080838f8835672ef9703a49e94ed3f82bc6cd4ed5bd535fc1b98513970d0b571458f00bcc1b5dc28d9de0d0b8e9d70c0d80539ce6b71f9a913e7bb9b16a070af1c0e90d0ccde283281ff3ab895579b6ac1980a70baa6b6e57c14ab1dfbde85caa8ee41488d97f5922f03315b953b7fa4dc39f99d1	\\x0000000100010000
23	2	10	\\x07f1482faf4368ae3c17227a3968f13b4bafb69796ff7ba37426a464de313ae5e821ecb4aea7e7de0aaf76fe068b2bff859de07a595d3450323bae350dbf3309	2	\\x0000000100000100738e007f16168da04a9c74846d7654fb720cb9ebde8423f5eb3ff8e266eb8976a3ff35d8f8f081e8b6357712f1f75f9700f0b8ebdf8138de28ae8a8a839e4b6c275220af8ed7340a49b5f32609e4f2e0acf4612683d477378c5fe1a9df9e09df82f0ef5964cc26ed4db5b6d7ac6f986c67bd77d71035cfc88292091acf05feb9	\\xc6d076552dd050e48560ede99e3e9ee6978cd60a3c65006dd91c196a9f2ce50248c12956d92ffe3753fd414ff242c8185709d3ba99cd57e936e679f97ae74d66	\\x0000000100000001c9e97564daeeb49f896c2ee45d1cedd94704e4ad828521ed7c65fc502880bfc2a6fbe0dfb6eb437d23a626f4897d5077cec5c51d7493d7970d1e61abec5ebaeda53f06c8cedbe955fc89aee8964658bbf934f6b3b61573135cae6770284ed6cdb3ad1bc7d36e040c3cd563c1cc9cd27d64a84040e695489feba0db52640ff326	\\x0000000100010000
24	2	11	\\xa29a692dd253b46a5af8fa5eda28d85b199451d54c6eb110ece42f82d000f4f2097c3de14b6084cf0061709850cf2bb51fd5c211eab36cf59f7c2d4d6c32fd07	2	\\x0000000100000100088714d83743d40a4424e155b3bb758b02b09af3fa58fb435bc36c150099cc1e0d2ec233f375846048d44f0e5772991a6b55a0322c75ae612b2c3defd9ec11ba7a9841d79fe4734b55fd4bac94718721ddcafe797a2dbceec5f2cb051161e322319452d9796d3e09aca40a8ac55c04d4f5ec2be58fe0959af2939d489eaa9e4d	\\x9637e15e982ac95f52c7f41bb79ce8b137f74470227083758520cb071f9ac7651bdd17be94b340b5377350c207e1defe31c137157fe180feaa8b701e4d5ace38	\\x0000000100000001ae6ada9322f0656d7e20dce6f982ba2de58329fd0f3617fa286913d1feba5ecd7f9fdc6aa31ade9dbe0bab498aa4e5ce03eb8952ad315c3b644f6883189f00a7a204adc0da1457d6febd246b13a60a5c3000249cca09681662c9a73e433c8842abd73c1a8cafed5b72dcf8d06c43dcc7a1dd7810f9915cbd7e70d68a2239921f	\\x0000000100010000
25	2	12	\\xa6455746ad9d15ff8a07a3561d594511c6231c55b31e86a95e276e728f5100b1c9d6200bdb5f7e61d993f4cb2dcba81806d287fc90149b088c620e3a8eaa6e00	2	\\x00000001000001005e8489148e20f55842d61d8991b9c045e675d7c649d0b319ad550a1bba8b6537aaf6c7483a1093fd5ac1283c0d0074e6a2bd4fd67656cd7af3e36bbf39b7fffc8c0a49b64451aaa14e6f11a2ff1db7d22705b02a20eadf50e61ee4245010a082468efbf3cc5f328dceb590a408fd4ab97560595a81d4d47f1da573243fe7721e	\\xf63b613facea60683375c7557b2ab9f8ff2fb255dc0f13dcd63b45e4c07f3f5072165e96bfe1bb6fb15c276a233de71108a33b08f29b6ab57c8c4c71b5eedd89	\\x00000001000000013047747bf5a2376517bf016af3787c3a78b76064e1fc1b6ec26d18f6f6ed41a0e6890d85570d0687c30b9571cd5ab2e6f49ed290092bb20d49568176944aadfe78f12cc5af2172a15728f2b5f9bb7eba55cb3010f76dd4af8b1c2b1abc90c72813d4617d8568a2ad58c2186201746094cc1cedb3786895bded0ea4f737eaf025	\\x0000000100010000
26	2	13	\\xa6bb30e69cae9563f12f4fa69d270a3fca582ae7c7d1bfac4a22cf6bab8bfb8b97c62c3edc35d2b7e35b05f6ef5b293b33c0cb6b2755da1e05c8a5242cf0610b	2	\\x000000010000010038fea413b961c6a3a8b6660989353d2e98bd84cee6b369782b0f1924ff06696c38491128aa7f5b82d2a3ce3eb4f360bc6f1a2812b5db79c6a1aab12daae41e45ca3c94128784382bf3fedb5225f1515428602f6f05bfa77d842adbf758e7890d1871d47e7e6f6c5c0fdee99799d0291b995d77216b234f61975acf58a8fe3f7b	\\xa2b4188283c1f7f068e7f4e81c1af0da978607bb2ad34a23a0a51e8688f75992f8cf8ae2dc81a444539e99840c4582ce2a3db35f97f27cddc18c4c859885e623	\\x000000010000000171a83165307e0da4f6232f79cbb06fbc058316238abb39df82132aec1ff7cfd9fca433d2e62b9bcef7dd40cbd376fbe337dfb5002fd75b69fbfb8c58497597cd479eed4e64fbc5fcc4d4fccb5d85ee4a2f77824545f3bfe63af61d582d2a3093c0107711eab25f261581acf93a709a17ab0afe486ff9430ec8ecfa3e614e9df4	\\x0000000100010000
27	2	14	\\x6ec6d915c1dad01ae2ce8fdf8060472a04b1351aae945fdb6d7d370bf29de1cdacd5b4883cf8f0acc8a03c04b347dee7ddc8a3111a1f71e84017084910bd1700	2	\\x0000000100000100b70f4fdc5022c5d68c144f5f041dbadc56b5adebe87c8c4347d0010761522a1d303e72d15738a78391d03891558d8849ea46da3950fa00e50c96d7c088020f76d495dfbbf21ba7be58f749194ed26445029b4982a96b87105d273c74f5783da983eee3f0f1cf0a8d667dd9da78a7c1f9d019d138d7b71a1e64e2139884fb90b3	\\xfd6d4e5926c019cb8dce2103bda5209e99d650c2c8d2c6e625c34f4555e491eedefb5589885c3a376b532f7c1f903c1313733a5e6445d7863c66569a90562398	\\x00000001000000015ba013f86af7333a89821e4cac5edbca09699f51f86ff74eb2926c9404024ea05c4b8dd3dcaadd5582e1941bcf63a01864d085f18b0783956ed4d66aff9b85eafe254027170131899e7f3ec51f2811c88a8308737482f21dee0bdeefc4b628f1796b67616c644e06376a6252bd98f01dbe97f8754376139e45310ca3821fa1ad	\\x0000000100010000
28	2	15	\\xa0d3bbe0cc6f5803c5398bd39a6167431afee49bfa79a1f0884b2298b7636d7a9fd28e5eba9a949266bbc28c81683d88c85413da70b8e86c33d18d68e80af80d	2	\\x000000010000010044d73c9facf37608cf0a0fd189a6ba094068a578b13a9a83f91add5950ab673374ca70eba1796b53308c1f9ae711f1468772c8e59b8deb326fe72d81b6947e06e5043c5537234fdd5baf6157d687142dcdb8bf8e304bfee305f55a1c2abb64d36f27e59de8d267a51159c16c036a22de2fdecdd1a0fbb27940db91f591e43497	\\x3545b551941a5bb36451ecb0769c279361b249f8151cf3c787c75cc81648c449793c5b11f4eab98b4f14f764940c4e6c86c772ab25a2de5b85ceee9ea4752f84	\\x00000001000000013e076ff66fe130d55485cf30d6ce614e71314dc5795b75dd1f54c9ec61124e82ad24e4fc45b2b435640812729cf7095dfc7fdf961c435f29ff7fb018ec3effbadb9be7819a8683be4d9c243593ff95d587f1085e2a1edb9d649cdca205e516dc31106b4def1483bffa88148d6c4b4eb2cf1d1394ac6483921a8eda055963d922	\\x0000000100010000
29	2	16	\\xcb321b6f078019cb8ccc331e2f15ebe6a89a46a7ad1dc9c0251166d82ff312b1edc0f9dc264b5edd33ea30cd525fc8db4bc05ab6bd44d748d48003fcd6cb0c09	2	\\x00000001000001009776f84d020eb09477cccfb22635dff33f4bc2a0d38d97204de5806fe9bd819ea216aa05a2ee328d6bd4f313f9e0bd795d51b87dc3268079b18b4b12cf3c28e771695975b33ea16c588a805a2027a1fda9ac1f4d278df62014586d94a5cf8a067b77c4737070fb14fa96871bdc9d699211ec9dedf9124e3d552331d7a3f3b292	\\x53f54f0f7857be8b9b4542baca6643617471f311a3c806b9a9c212ac58a60dcf6aef113b6295036735a387bb4ab18f877c2fe5988e874be581b5b571a7080819	\\x00000001000000014d1d897b0823be8cdecd070d1f24850c7e6c0bb289a2183111080e05c216a675595e72bd75a5749be0e5c894cf3275960d09a32d29edc77644ee462ad7e8c5a54954d2d70b4ab657169e0c5368c3bcec762c7ac2ad2c6beebc3947e08ec8a465e8fb56a416ab185718318722fa3f42feb2dabd07d98c0cd55c83f0fa463a72a5	\\x0000000100010000
30	2	17	\\x06d4968670330ad3fa3247dd29e913d6412aded5e9637de132158022ee32177198b57a9f4a285aecbd25b700fc63858087f231373035d915d9f876b2bc6e580f	2	\\x000000010000010034adaa8c16283c12d6d6d4714f645e160ff08f2f268d0b1e39397c3ed568e3362334133eee55478bdfbe32caed72386008d803aebcd9ff0fd0d49b22e5f57798d8b2dcea10a8f40fb4bb1bb2433321b42198f9fa1412b8c03d8bf13bcdafc1c199c49bb94f5ed2dae0489fce08c117dfa60140728465acebf9250bb86b713698	\\xd4c9ead69ab929443ae39ec7657ffdba26ecebc08823d278c1b9c1bb0d6379ae837b641e8dd4e9daf178844633fdf487296f34a4976e87d157dcfb08b28c883c	\\x000000010000000139f726927a65f805f9fd2f0b3f625121c6fcf2f24ee120a61f8fb6f4873a7f12ea82a8aa2be8c802c9dbeac7488736749b5f46abcbe7c4948e9cf5b10e4d21e32810a50fd42b03eff89bda92b73cee008bf1ea2f2b5fde2209f997dfeabfa29ed2d2c388ced63d33cb04df222bc62a7e8619a60b27fc740bf8f6f9f7f23b184e	\\x0000000100010000
31	2	18	\\x8cebda1c932e29f70ded1d7b23ec519c717a4d2599f7648c905eea9940c6ca1ee028213484b820d871cddd32a0b59cddbd77d0bfd4e2d17f1f17a44b9b1ab804	2	\\x00000001000001003f79a97d5d4b24c805c4c238685b5f741f3d4c352285c7e3bbac4f8bc6019e1b290dc51714b4592ec02d019b1167560e220f7cfb42033c396f57c496f8cd07e8ec7f608bc19aae315579a3fd504a9f547c3a80c5b48d84c9a7876d6afb2430a53ed5c7bd215f5a23ff3a44157ddba032cf5ebfef184ef625f3b84b933d3b21b4	\\xa5f667d1b44279603c1ca7b15ded0354302592fe92e1722b020e30d272adc1e887db73729060e99b7f6a6403b067b52453e9504432973d8ef265b47804fc6a28	\\x00000001000000010ddb941e0f67699c617dc61dd04ee930da8f857c9fc050d27970f4c8840e0f3097ddb92b10b80f03e34f20b6e38d8995ab1f0f66cad58df4835a5fb6c53eb04c53426e0e31ee83ef8ea0eaf7c7b6fdc2a6af0e675a4616bcf3fdc3756f0e408b5b315d199d79bd4a5529bee6efc536d5c726eca051fe13c3062c7de4533f3464	\\x0000000100010000
32	2	19	\\xbdb6923230b0dfbd00668dd1d709f2e7962f4583e1536fd1d92cbb45e68944be37c4568830aac44b2eca68a5ae678cdf05b4833feb430268194dccc8f0aa500c	2	\\x000000010000010037263aa4d889f558bb6acc1476e10c06c18a2fbd12a86c1551b6db6abc99112d4a31227600925b0fe85d338a8205ff46a3901f3546bafc4e1a38c15b7b467fd203330ae6ee626eba53b84dcd2e82b8da2446810ef4f6af29be143f50aeb019b56eae9b15f3364a9fac0264eea7e4c4819ee61519732ec9e7690e12f1334ca870	\\x3a5e4db1065ae0ac1462e3cb0a66eade3514481d898fdbccb66ad42d168b822e39428ede07ac23bbd40d12e43701761d6473ae73fe436a8ba7dba9758dae37cf	\\x0000000100000001432392f4684ac4357ef77f07bf8fd9dfe7c64f2c39b4736aaa15e8e8aa0ac3482196575c5929f23e00c0b47d7545c18999feaebfb11536e2e449aac9e7187ad1d768a45d838c3d9aca6cc762afd1331ddfbe43fef7a2e2f32c1b47eba626f823ac9af7d36c981bc5fe57842e45dab66c5f0806934069c29eea945fb65fa0b58a	\\x0000000100010000
33	2	20	\\xb054970ad557c15d4b1e7f625a734a09552947f5414c29ba4b44d5834756856269a1281b5113a621569b05a8a76c10ae97d93f467d630f84e1b3124a1c22200a	2	\\x000000010000010027708be73b48ed6ccf87a2d19bdacb0fc666bcdaf6b39bba68929a54d18bdec39ca59addf66ea6e191bd4f3df6f1e6a3a0e35fa906bf388a3f8d28f21f0d500d500a11cf99eb54d3cf6b8be014caabafa5b45fc927b5ab611773e03a71f0cb20c83d6caf9c8803852434bd6f0d9d5b0cfb6fd06ba57b76822dcf61c00dfc8a1f	\\x8b0c2163ed93a69af2b103b50db8f9d1c4e364d8191b202eb27ff8a43fba3f01cc079e3ea91fab81673720c3a48693005e1ebd50931cbb474238320abde43d60	\\x000000010000000150e095ad650b133403cd71c568950a6c06e0a5de9e618e42b793994564a65b3ede90d50e91131e4e9130d9d4f64e0a4d348384b743296ecd4aa48b39b1a533fafd277fe48baa2326b2c1f0cfbe533576faa505a3931f55e58cec10c91da70eafd4afeb97e8b43604d2142e07e8f54aa666ed247d8de49ad7d0361ead9b3e8bf1	\\x0000000100010000
34	2	21	\\xe6a31d3208af2334685d81f2ba55628bd2b3591787c2a51e6bd3783d0761647515df9de6db92d54a6299c70731edb7b2ebc3647010bc582f2c22573f4b2b8f00	2	\\x000000010000010092ef7f5d9bb695bdb971ce85c1693db4be4e4611954e798481ad8d038f5599a287dce4545493773dca8246057b45278c93464e4e2d283d97f1aee8d83b58f1b37c46b438366a1c2c8405e48c8b66079ef4ce09a30f04272dd53158d60fa34d2bb0e6074dc83e28a75daae075d88f385e7a49ebaeaa1816883c707a17bc142cc9	\\x05cd360c7dda959d4dbf945083e83ac090100e62c247e8f48f2a20e368990c0837164ebecc9451c29022c55e0f6e1f5ade7f815ac5548caac5f0e1bf67cd7db5	\\x0000000100000001baef4149c37a47482863b62c5c5563f7451e56adbee6b160e30900339388e7b0739c2d5843e6622a4ec2fbd50808953971c14359d74c4b8488dd582c2f5b63ef13aeb6b75ae4153eaf10bf43949c4e11cb63004a7350caef3192684debbb63f10b045a0ba6a93d02876129069735c9eb18408bc5d2aa75d5df54ba69a0c21b4a	\\x0000000100010000
35	2	22	\\x70063a72ed30709d12325af91a17ac0a8b98fc044d44367471304cfc540f75a4f734b22fc0d855c6811e897d2a3ea49accecf0f1149f81289e2a62ca56d55c08	2	\\x0000000100000100b93f8f647ae6ddecdb7e1dcd9f752564ed4314a909e8341e73968c62531b4e05ab8d4acb7f4573ccdcc8a365fc705fc8936bbea216597f924408807c0e199c99992f1437eed834fc6b4555084595ed9f56df59c31b0b0414e29bae34b3b11ea893a7b1bd331a67b7d1e99227aa8d653d4ff31a680d12f7aca04b5f62ce625135	\\x75b32eeb15455445117465cca51662e778e5023ed9bc1578f1b2c43cc87c210ef8ebe62006ba987c7f8aebca4ae131d48acac4418094f343b5b355837208c53d	\\x00000001000000010e0db2b90cd6b1cbaf6b3ad7228c7ce406f4e412ce0dc17ec189b716e0c423b32b417127d4a29e468d083ab94d5ac0e6ebe5d7ef25b45798872707117a7b652f01941ebff462f295e4bab7461bfcbef28997bc5ff5ea465d3ee791e0f0c5cf2106a70401c0cac52ffe366bf6e0df6bfed74bef4186fb1726a8852bdd3513dc86	\\x0000000100010000
36	2	23	\\xa1fb5cc6f14e485a94fe218d56867761c6c9b06114cbaf86dde5f911f3ae3966e7438b32263d980713c5eaa6dcd03038d81f46392ffb3e502bbd8a32d4c8860e	2	\\x000000010000010068f544c7a6d2e3b51f5875cfc3710bf8dbc7a087e7e6e97960b1cfbd7b4119fa8ec346585e68996b207bd9b4972af0e67c1ee18e55d8c9f11f0e876378c30eceab53db5c2a59921e6b14b94d2662ecacd27f2697ee3f3931679d55bc996faf4f09a8263489e364dca12dfd81875f033982b645fade5821c151422e8c41eaf895	\\x3278ff5b3c3faedc2e005935341d361f9146949dfd4f095f0f2a0efc23a0e447e2ec7585596da58a722757a192c8739951a7dd55f00982c50c247fb9ddbde4be	\\x0000000100000001ac0f807a4772df85ea7879329cda59004b3adfdfc2f683b18588db60382431e7c5ef1a370071ad358827ac3f47fce6ebee2c5c82fdfabb1775335e5fdb8650666606f54ab2af9c8a4d32071068ed4677916c4b8d32d29cec8e3c226c4d1a68928aee83ab49bf58df0d8daf31386b939587a226f683cdbf732a7bd6aaab79e70c	\\x0000000100010000
37	2	24	\\x52535ef43efcd23aa983a44474c78172daa7147d994713da3e80dbcaa60349a028f74def9aa6aab716af2d685a5a50e289fb368f2eb5256ecb57f4d16ab6e102	2	\\x0000000100000100173568a2e3848f6bb0a67d96b55a1d4aecfa3c6a2b18965b33b94524f5e132456efa9dd4171f7d5b886da7b8f8c00376dc34c883dd4ae662c904d0ed1e0ab6d9962e3aa4b4663725b9fd4c9cf6f6d6cf202e6cc89a0a5f1db32f4e42507f8d99dbce438b325a78a7486c99e911eab3aa96c8dad159cc1d0bf744de6713fd2291	\\xfec7bbcf7bda580083103d47ef1d70047f167c26bb3cffab278ced8077e627c222587c6ac0e228223daabebb5c4f5a60fcb8fef2988373465bfe87c6c23c811d	\\x000000010000000193a70bedd811abc08b7f7bae6a94256507a6984101059330b6a1f0110fae1f7f0ad1863d8d05f784b951d174647a0c4208dd7abd6bea806c96495a344d214b96bc3b0df5d766007b6e44602d383b964f2f10b391d1ef9faf932cb38bc5fd6d10952afcb3308c739a7afc6b68dcec3135255dc9cd017893b9f4cf45053c834594	\\x0000000100010000
38	2	25	\\x2b176340f1d0e26a648ceb04810d06d095a6ae27612558c7de1ad215a283fc66b7a11c456d04c73cfd3f5aa5e84aaf3af5a19a02f4e6fe90916240a0d9d36a0b	2	\\x0000000100000100777de581ccf39bc86a0477e3f3e71ef1716948796823cabe948704e92baeb801eb65dbce633e8fdb65841f351790a638cf434ec0887046add9def31bbe388cb39ddb8b5d3682bf14dcbabcd266c1bf343a71a4b480ba5666508693a2c2b22c0c9a0feb1fc012baf4e6b969c72376b470194dd8184dcfd8a5c3c5e1f5e6e42a69	\\x25c85a685ba930ef953604d77f323d89edca611646c964a561575f051003de7cf6b935315a6b99035e2799834490942015de74e309af45b0031e9388b30ca504	\\x0000000100000001936f7c0a8caf8daa62b2d9c4a6faa336d921a6650c4d69976a7e0cac065ca70a851bd733e96e924134ddd7c8c8a3ff361587c561ffec376dd3d2be2ea8430fbb47da81b13ccb3761afd9418cbf0eea1435ce347434bfc72e0fd2a681beb7ba1af8e98f066ac5c26946d296eeee61a54bab0714197c88772f567dff92a308d5de	\\x0000000100010000
39	2	26	\\x8d41e6e0b273fe9e472050b6572e78785e1004415609ab66e8a3e8c90bdf14fdad90d8091f3f55ec595a5804afc67c2e84e096c135972c1049c3e11460210208	2	\\x00000001000001000df9d560016e7aa766317b4d4b3549abc6f0399b22493320114c0b4c217599c961e7927f991fa3375bed473f538e829312e5ee73d6dcb2b8a1bfd65ff8bff37f940798533e2a5a94a5358009e62cf40d2278f72c1226da0b8ac1cbb94b12e6cbb199a02869ebe1e49c689bbdc043422fc6a65bee2065a34d1bdd55e695a25287	\\xb472198ab8523acc9f5c5e14121669f0f63ae0bff5fb89751d033f87f8cfc6bee88237b352971466046c6999c627414d6d557fe6f1a94a72e188fc3f1224cb42	\\x0000000100000001517948c14e9f383fd6ac46d8432ada1534d17d5d15eb6385c1de22d4a2c26f38c0518393905ee2253b742aef36f57b2223ac33aeefdabaa9c0847c4df49d9b9aec308e524db20d5bf2fc28d77e9819ad33ecdb99f1a51aff87fa1b3a1b114b5b0bea2d7aca76026dc0121a18b2f1401eb078ba88829213c47569cb3e0e204c5e	\\x0000000100010000
40	2	27	\\x64d5fa7ef14e521e29e0a6679f0a5af2aa875615499badc52c36d59b0f36a267221148eb0707c3fd9cba66ef9b8d920675eaa503f9b74dafca867ce4b4d7360e	2	\\x00000001000001005680fde54efeb3c170318a9de400c16c8181f718a9bea5211ea2e38c8c180608b8907f32d3724fbee47925730b40ae187c49d021871206091d8aad2cd93df46ff537eca1de29d0680d3c8de14210ad898240fe87ea85e69a67456bf12b690494733c71e6efc707b40cff0f5048f839bcf43ed905e1413d285eac265b38fe5f06	\\xaac22e8edb9cb40549a6294b12f2962475b867909b5f3038310b57ff9331b1a9d2f99ebb8cb3c5d2dc80a84b41e3ed6e65c47b94f41171918e7718a7d58664c9	\\x000000010000000122432ff98edfa3670a1233afb97d09ebd353822858d1ec73da2aba1de48da77c8a7690a618f28da0fb005d35dbecdeb72c422c8d71b9bc317a118454fa043d608bbd49429ebd500d220ec7fd62685e91795ba5465a2938aaa330f105a492f555e3b8d249f6c02b7b361ac73ea13d2f7f23aef5ba119b0d945ad70063b5bbba01	\\x0000000100010000
41	2	28	\\x539acb651f0c710672aff65658c90b3ba78d8c5f3a54b7d864212c706488ccb4046ac776efe0f74fbb3f00eda18c798dd13b08c872c6cd395fcd2fc0557d8906	2	\\x0000000100000100b09a420e4ec9528042b1725bdc0adbc33ae641f9b91135b9f80b75c33f6c8647a3cd05aa699c04b1f82b2c1242db8917a903460260e90f1ec40b2d30e8aa72ef2f0a68c274995f8260412aeb8a3d65dcfe70b9e35ac34df74afb9ad488035d5376be7d1571f95c1d1042c1850d7658883407a5011de09720100a207801b3f7c7	\\x76202522d6fc57d2e6fb2f271fcd801a130d01c67a27a966229e283e8eae6b7e2a879833541d17262b92092a56d885e6dd27156593592cdd6b6889bcf66de12e	\\x000000010000000141c5152dae91ee572fc81ea5359602822a6399ce982f11df1fc757ee336e8cb6ca89c685fe4afa02c608c66795e7e699d6d9ff7763b7b5bd791a8dd6761f635ccfc033797d40a8a9bf3573e6f1c2bf6015300da6f974798a67993b2e9dd98c49212ac55c7d3c90522ecedf4c1d80af76e9b78012b7cff6224a6465b4c2581f03	\\x0000000100010000
42	2	29	\\x26a30297f82a6bea79fa6ddd6249b7fc62c20e2e6279322409b0db90c7b7efd87f742d864d02f3fa3287e0d28f306d9a2c779ca0eaf1d2ea8c78b8f269754105	2	\\x000000010000010042e8d3e47cc91d8b7e5f76ea6bd8b7024644ea6f2be6df41afee85dcba13533392527584d4d421068a9f0bca3bdb8c234bd23c50a7934e10471ff14d0cf5a90be0b3f5ce0c96fe3d7cff9417238248645389752a7c06b86ad750bb748c2facec869a8cb611dc683ef6d436675acef70662f93272fed30aa975e9ea9148172312	\\x62e6b5ec9755818032c7ae3f243bf0606be8619e2ab5b9b321fa0c6579760888d108980342ebb1f8ffc40507fc8013654b28f68e1e65d7017803a1c6b54ff8c1	\\x00000001000000016ec31eca8b423a8a78da275b0b4fcbf585f14470a227f344b8dfee4a0085068042be0af467b52b845ddcb73025216ce8efb4bf101ba40f916101c815c073cb8c68284540daff99abd4a88a6f7746b60f0a1785aa59ee03aab6cd096ce4d23f9bacc695e29262959ed7eb0fde0ac00312819158102eb40f8d7d19de4b499a4465	\\x0000000100010000
43	2	30	\\x7bf86e4ecf418027fab4b2abe34c890e2526c66854395cec60f71c029bb1a3eda7979195afd9e44d9f05322beb1282e30c4a442cc8729c9822db9832f0b4a80e	2	\\x0000000100000100586c153e02dd2eb46c39159a9d57b7bc8c15f70851ea276b82501b76c2dabf1f1ca34dcd488df27771a9e03851a435a5dc2c050333b7c4c470b1ece60fcd8a0eac6ccac597d42eb791fcfad04399dd84647b573ed91ba91192500914db51c26dab50c87b37ab02f0b59a44f9225460bd5c7b6df3939d09a76d333db71f49d5d7	\\xb4dbbd7eefea1e942d890082d6ee3e2516474b1931ffc2e16abc174fb4ad722cd1064f6534bf549cbaee534b9677070c390d7c3ade6a45007f95f15312ea4343	\\x0000000100000001a7002d52cd61f10ecb268544184b75cf4efb0e3260d3266a84b3771595e65f102523502a87844c422e6d7d3c4ccf7132a0e7900ced638b2590179c485ee49179e47ea1ecdf4fdeb1d65db5fd08f98e2a6ae401ec4af257db7fb3d33fe1a8580bdce6a4ff7d35163793ddfe4de321d919db577799ef788fb5dc87f315a341b13b	\\x0000000100010000
44	2	31	\\xe2453dbe16fe295e03096893b59ce2c38f3a59c1d789463dc7259469076af2b87fb06a54ee88fff8de7c5326831388fbb357b50967799ebd7175fb9a11f6290c	2	\\x000000010000010007c2ed09b481213f0a8673390e4a00cbcb04d9cc39f4fa6a75b381cf570029087cb31252bbc65539bc26cbf5964224cc3c4d8396e35c186dae05f7bff52cfe81ee4a7802bebd8b0361064d06fb5a1952eb707bae74f7e4e5fd0b5ac4b6cf8ff85364ea03a4176e4c1f8ee976440f7f0b8ee937bcebe741ab8d0e7aa8016c9d05	\\xce2805062f19f3fe455b923a485669c62741eca9e456ff177dd78717ee8dd71ff0acf2ed46b59739cd523b96581f0d8fa240001c012ffea08c3091c76e0cf519	\\x00000001000000014b9d67fc74822d3a91f1338764da749dd8f5628c2ada54cfdf31f42a6b4994e9ec869a518d6cb89f6daf0a72a6089ea264a22928ab2059bf0c2a6cfa3f260b3f00ca44702ab857466955409e81bc1c9d3b17c77d748cc7f4f91d9920178b2f8da6e629bee0e7e8ad97b2ca002f8548eb3858538d193273325fd31b9621fbbc4e	\\x0000000100010000
45	2	32	\\xd5b36a0f21a4550de7f566ab12240dbb3a82678275178034ab4cd6ee3d76a763bc9b8c06d934378c179697cbfb3e3d719daeeb4c74a425cbbd02d2d3f611fd05	2	\\x0000000100000100ad4810afdf180a411e0800ee362b891726e97b2508e82238e6764063f1c36f1b2545283cf9131c308d3e710a2fbd70ae5a50a44917ce8bd24205d9ca8c5e799c8f0ad52d692199a3c66a169c069b2f15f10dd1cff9ad965cb5ac5a0e997d6f12e10d3066f829184011f2a2f6457fed78f1965deb5845712c8a2a52597b8e621d	\\x8f9def217c8c67242d95de68df1752965038ed6dea4a99c0a41e2373e18d9f252e7b22797c9e39ebf6370cd8e99704505f15c6d4c3f5243c3fd3c2ccf9ba6edd	\\x0000000100000001674a93fecf1047d569937e6dd1763dcef1889f04d0587c5d4d950da4438d375f7af703970b1ce1c807bce0ed7bb4c14ee5d6106295840d974d4f97686be792ed2c6968dcd2aab23cac24afe8baa1c705be03517e8b97e7f75e3e615760bb07af02d429fb19683831397eeb4b0e1cc904e487a861356ceb3ceecc47c1e81efcdf	\\x0000000100010000
46	2	33	\\x6c67bca476c28497600ac73704e58e2207e4a9c0368e6b23f37f554857ace73ebbf4ec6345568cd65a725ff769c12a8c471e50008843fbe022f2f62f6fa14602	2	\\x00000001000001008ee99f3e89a6c88eed14fe0b792623de77f9f3efe42edf3bf8fc56b1e74fbb26816a34b45d5a0d8ce1042cb463c79dc1e55264d07205fd698f0b245db60b2422bd5e0e2a142c8b222e5fdd9412bacc9679a4f4bf198ef4e13dae08cb898ec5c35a7068c92412197644af842c435947cc39c6c026e9b2d0f7408a905e1072ebdd	\\xba031aa9905331935402c93e1ebb63ce3ba85dff38881e180a067edb7a5d1d9cc49464299a38a6ee2932e69db6fbbd711c5744cf327ed2b7e4e1fb42c8be148b	\\x0000000100000001c9e7c9319d9078528c499cf077f61b5db460b067e889ecb42fef64cc0b24089b7e7bf153a1978ea1e563c39e181bc6d4936f2af5105fa4e9bc0a5ce37480bb328e2f52d63d941dd8003713c11fefd63d9c0155b390e9591b46adff61c122535ef7b5096d1c5ab86a0ccaf87f658d05c978205daf5b5081d195501085392e0e33	\\x0000000100010000
47	2	34	\\xb4a3201bec1bf618d7d7f6995d1e09efa3aac6495cb420be955081ec5026c8cd39315acfffd6a986bb44650ca0b2cd46cd7ea56827ec41ac3a7b3d9617494e0f	2	\\x0000000100000100140a13ef94fb631b1cb852137b96e779753b95c7f84148be3733c9ee7a66bd369e3bc3644d5e0ac3f5db9873b5b62516d11ac95ae6acbc0593ff7c663b3347495ebdbc337d9f9dd8391956ca99af8a9c94b7f5522082ba3b70e3e2a2453e3e2f12f30953e2e461f9c08f324cab4fa75163338ba0ff3615c4c872c77c4f6d9b77	\\x932f2a8e856207c54983338cb8ffbf77d673a5c40931494cb1267663f0de14259b3eefe574120ac39cbbe237e3b5629dea9e73759925b5cb590a8563b7a1ba1b	\\x000000010000000130f99969a0913e532a44e12bb0e027d2610cde8ff79072cf633e6a723dcf57459ec789d33d8dd9db72de5cf53ee2900362c6352bc10e4b3fe77813b1425b40d622c2e17a1242a2bf68910c7e9135ff2fbc2d6a7736aaa52bcb26b7290692fc46ecc762f21ef167c585d1e479d71081ec7b9e9c0c2c0355c40ce2a102ab4dd7dc	\\x0000000100010000
48	2	35	\\xb9597608befdd0093287b108b2a3847290a2c3d1d1218447fa194a663843cb129cea15c26b6ef51c480b877642d25889099fd11ecaf7fcd93a4d076f9364260e	2	\\x00000001000001008a62e922f33af98d8c91606ba73b51da86b4240949857d3880364da16a9f82ba35db55a910a15583c949f96932e288e8d8211248af2417318049d2017e2a4921cf443b34bcfe650c40168ed6e8eb2fee58317268b4cb0f3f7d9f5b2b613b7ce49a4628897479e97133302195a012da56e422594aa456aa93620d8a0181be57ac	\\x52fd437a782479c51cddf5e7c99b77e3feb37409c35effb3897325b352fe3d5be7e09c7ab57392964492f0650fa186c20e64d7996b9a5e7de1095feb9bc11bad	\\x0000000100000001533e38ca0620b5191f9b1032a2c5dbefd86b0030e43697c3fe03199110bb3083fbfee205243040fddde6f6d4b2c9bc4751d6b007b625a28bbeba2ed58b03c807694196793571b66946d6be6e1793053928299f15ed713cc9fd7ff3ecb2e6d818a2a651d1cb552b87828844c8289b1edfed72e0d1a73eb40a0879480bb7f6474b	\\x0000000100010000
49	2	36	\\xdd26fe818bed4213078a18c96a1a971277eb224d671e7cad4ac675501842df77699f278de314b61c752708fd8d89d5111d012fe2741c066201578663479c4209	2	\\x00000001000001005292ec1a20185340bf96bcb66050c0cf7294507ca305153188f4597e6e2eb185849dab94bfdfd2722ac6881a9a6f981781c60704590ef5fd8dbbf07f90eea238060d207980cd7533fae17399853f90f7ba7542be2c37954e64f36f30720afc644d3067b12120e7d9c8775adce2d04a25549d06932bf766cc8e7d4e6fd296fcff	\\xe1d41396aa213d9ce1ce2787ef3ba1e8bbd3372ee92b618a2de82f61257f28e1b1fb84a73843b10fdd4b16dd2aa5bde3f3850e19834186bb9bf5d53c32e06052	\\x0000000100000001b269ecb91aa82e181fda9a18c4cc72527512f175a73de6b8036b84b27585c8dc66b96ee2ca43108c51b9463bcef0d21d61a98c08ec59fc6f77c422a6aceecce455c40f41a13cc0e38cbf83d4d423d6a021fb858812cd22428b5cb348185f571e836e092f68449ab4db30ae5d4607624d8393616ebe8a86372b328f787c595bb2	\\x0000000100010000
50	2	37	\\x9d812a8dfe3d43e0cb52982ca26989b768964491684b1375498d0274005d56816bc1b865cc689ee48d802043b99b49469dca5557240efd9408944c26d47fc004	2	\\x0000000100000100afab7cfc391d0686a17b2cdc00b7ff30c5524d1b59cc62bf90f5405d55d98aeb103b920de0e9f5ac01e8520b91401676bac62bd508da6e3be1565c1bea3ae9b81923c70cd33511cd305f449604a1a384786cd083dc5d54ec0918c49f0976aa47eee3f8bcef1ce6c9c9174924059ad349cbdfd506c07dd2a659d6cec764ff8dc5	\\xf3c4f0e5ca491216c7ef5195dbb0fec717a9e279e24ad694e844dea8473c57bf88fb3ac5774c06cee2d9e4d7ded20dcd81120b8b73862d58fae37c348e189028	\\x000000010000000130709133545ab15d15bd290b68ecf22377bf664320027c03ddcea4308a2198f2e407d5bc3c95ef898301a26060871d068e526e52d8312c80fcb974c1c423ebd077ef9938b19bf7b88625edeb1626d4e5d8d82aa4a06c0644071844403907231d19e65bd9170f2770bcfb8bef81990a3d79f0d6628f18d0b7cc49ad403616e765	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\xf83d5f7daa08c0ad69dced2ff0958f29fb29a6e5934b94a74912447ffbab5334	\\x3530549f5a9ce900120c86d16be7ec7297c9075efdbe35298db6ff0f6d0d1df7f542d08d77467d22637016d157603e4063c34d058bce859642f9786b9b53dfa8
2	2	\\xffc39bbca783f56cf958f5f69465a13feaf47393f0567870eb262ac7a2dd946e	\\x355a23fca497dd8596e76f4123f64378458a7d694782fdd1157acece8505454ee1e44c3a3916765a1a428d21cace0ad0d40bdd542b3a824508ea1fb24f47dfa6
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

COPY public.reserves_default (reserve_uuid, reserve_pub, current_balance_val, current_balance_frac, purses_active, purses_allowed, kyc_required, kyc_passed, expiration_date, gc_date) FROM stdin;
1	\\x636976470c45351d8b43257b0cb289bd64bd1c708e3da3cc576e43d522aed112	0	0	0	0	f	f	1653935616000000	1872268418000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\x636976470c45351d8b43257b0cb289bd64bd1c708e3da3cc576e43d522aed112	2	8	0	\\x6506e969615b4c10cea61d3c3798f501407a5eaea24e4176326639c1ea1a89b3	exchange-account-1	1651516403000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x0849dca29aaf92495684302c537aa87ace39aafa5b9561bedaad4cc8a3a845eff712294a6a6d7560f6e3c8c0446ed2a72f2735356e4e6e02798d0b67a5a5be72
1	\\x08a818c2b20e3682a7ff42cfec548d6b7d3a9fd8b7ff4710f2af804eec02a92f2db0818e76ab8961d7f2ddb8b218a53647d8eef869e92ff2e6316f15311dce7a
1	\\xce052faf02e230cdf0acfa47ce25761f738167cae89ce290d065bc72b6279b30baa4d5bb705a3de7dff83b01d789ea52176da00fa945a6aa52826ed3b1e7ad3d
1	\\x7bb98968d6b175cacb1eb0a3f3dedca1d9da9f1e1d526569cf04821bbb15485d83a7e9e373d66064dd1998910ebd6a0aa0e231b1d7a66776c35bcb2ea6aac7f0
1	\\x0caf281ea8a72019498b449c760bce76a37f6a0b6fe23d7290edcdb193a8187820fc938f30f48068db80373ecf62ac8513fcfc5a709f7730c4c78bb0be468929
1	\\x7240f894c1516804fcdb498219c4b6e0e40953ce24399512f1d3fd3ed60d9bf7381ae1741e5008f5cf7c4e1f19b6104ba733723de18cdc7d3e7beaaaa45370a2
1	\\x689ed1b36129962c260967ca7f2c9e6ce685c6fb0c6082efecfe98d9f40739b3a8e028777d09461b09efe0e535aa0bc9f16db46b67e370c6898be5c97fefc7f6
1	\\x160611eb63b0ff7979b281c7b3c8df7c689a28cd062f8ed000b9a660a381cc67a78082e6f4b9c6f4031fa64a9559d8f5595266aa3f03c297a0f69b151e6c875c
1	\\xba7d2f55f29ef9275f36b4c189da7337700fd295e16c5d3cb430191e603301aeca08cec65538b6c0adfe7b0be4c59cc6bad3055fc65168f6b9aebaa70d04a618
1	\\x01be5dc0503cee145cbfcf963a2ebed49ccd0edaec06c6f9cafa0ecc0ab80474b39c485564322a7cbb18b1dc76ac7e41ecb4c8aa2485d8ef8ddf46e286b5b0d7
1	\\xc3bf5fc826c0340f45530ea8511296cd1153d33d204b62142f85357500155abe273244c53203854bb8fd366e9879a3f71c2c0718d378f3892809993d8d1f3453
1	\\xc5eea6a0431bc1613c41c028582dd9d686fdd609740e7de8a6e322b09e7d985e78f5645e8dd21978e66a7a5a173e56bf0dd277bb007331db8067daaa900956b5
1	\\x1265baa10f22e8163d990a085b28917c86599a90f591f3201f92ea9546b89345b704309cf9efe83f91185d471ac49380184fdcbcff8a1010cea08276f6339729
1	\\x09dd376ca56bcf291aa080136f163af93506a8291ec9c44c59654773d26217cfeab8b0b031ea4c0d4962842c4b0a99b21a500af33bceebc790d1b277c2fe1f41
1	\\xbe98a873b03f8548345558578e7a2a2362bd64c0d4982e3ae768a62b9ffdbe50062722ac3972234b77bf4502ecf3369f8a2d0b6ed616cc358ee8c253a85c364d
1	\\x35328180e0e883fc1a8abd888e15fc7bdf30cc787221a00b8fc33cd165e8357ef5dae73971f13ac68a7d21708db85f6d711ac413e1c658edd84595a3fff702e4
1	\\x4726bc8884901cf1870ff34f30e078bfbd1585930abc8fb8b38bd7300968ebde611228fb38b3caa0f81f49ae072e92a1eb8209452f0f1b687f85bb6bec2ace41
1	\\x32fcaa5604cccacee75ae503e95f934ddfc82e1985096771163cba9bf8414a7ca8fea80eeeaba561d4b47cc53579858fddd9d60e81b6ca54246f62ba8204c481
1	\\xf4c47fbc700f6ef693325a6c6c54b088f46a2770821a8484299a5dd6cedbc25219c66af01dbecdef631451bff9622d4019181acd0dd7a56614dc3f6fd8471ac6
1	\\x9abcb5ebc9f1022f1aeae70a3f1558637a6602b517ef3cddbef5bcff9394d722ed4edae092cc899a000fc0425e111da623e568411e543ac80dd31f8180f2b66b
1	\\xb1d1a159afa697e852cc99c63914410e04c7a428749e4a46a995ae0eafdcd75738f4bcb7bd8d96fcd627b91e408480a06cc580492b7ab56f8d9fd18b67646e6c
1	\\x9053a065acc591e13889f10cf3733e93513851343148c09d2f5443edbcf17b28ee7a9c42fbfdd448860554fa041286a2495558936994452433a81c978108b245
1	\\xa57efb259bd7a40b7c4ff6b127bcb4963e62ddbe458220e6e9c1444a9723c67b87c96e630bb3a394efbbcb3d8408ee4e788f37dad06f44aa1b626ac54bed7cc2
1	\\xadb725f4d1bd64f8d3e8708289e61f02c940100f16682bf821fc69485089f3c8b32da31d462af44df45566c443fa0e68e00c56d8d06fbfe025f3cc64ebb63717
1	\\x36a340d7187b1c8642694588ed9a64825ab2b86bc4cc9dcd35659fc63075bdd610ce07971895dbc8e1b7239e4cb96d928ff890ec8dd98f1eeae2d61be5b50422
1	\\xe8d925503c78d85c4ece4cdf5a14bbe11374591a37d2c2ef775d92f5f29d42369e7716516db1e1ab80467d00c8c310570a3a0c0a5a9c6cada8ba37f35947fb24
1	\\xf238c2125d57802530dddb6478ac55a10ff084e51a17e57cf7ddf5acb7bf30ed09f7848d5e9ce86ea1855acb667470b7461ef5ed77be35adb8041ebb56258b3f
1	\\x52157e06a1af77afdee74dac64a7f0414eb654b4ee6026576fab176799ec9e3f87eb84ec411ffbccc43b45f92881afcb0ec15065669f49e06250d9e0078e44d0
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x0849dca29aaf92495684302c537aa87ace39aafa5b9561bedaad4cc8a3a845eff712294a6a6d7560f6e3c8c0446ed2a72f2735356e4e6e02798d0b67a5a5be72	109	\\x00000001000000010c70c7ee0ded04ab20aa8a72131c0373b000dd593679143fdcf761d36a0e3f4230fe4ced07d6bcc355de3368a39cdedba8c84ae5f9eba90033d71bb55ce3f11920cec5f9130e70effd28f825262ffa56201cb50680a7df6ecc5a02beaae903fd91b55718436fdfa3c67c1a2903e03f4efa12a0862a07d29d798490987e42cafc	1	\\x0f336908f804bad59fbc03474029558b25461506abe8a52578fa0b3ab63f6c6e8b3ce17bad31f1f3290ef8036cb14fcf03e76150d0ce7db4f52ec54c53819b06	1651516406000000	5	1000000
2	\\x08a818c2b20e3682a7ff42cfec548d6b7d3a9fd8b7ff4710f2af804eec02a92f2db0818e76ab8961d7f2ddb8b218a53647d8eef869e92ff2e6316f15311dce7a	152	\\x00000001000000010556ad92c5503019df098d904c30c7b760aa54e303bf34ad2bbf3d8e40d795c29ad3c581371ce9d336f7455cc41a0739e34a82b14ebdfe737d494698a98480ca3cb946f979d1bb642601c2e38b23ebf70993dc4226450f112296fa232723d0a17ae7a09dcba594718dcc5f91e395e67ae0a8d2afe9e1b8985f5110a76bc828de	1	\\xa8672a68706a2c6a99af6e5fcd407a3a6a96e192c336a20b66c34050555c466562ebb41c86624a515520005a1bfbf1ac44697cde4eb607fee5e0e3aac8b7b609	1651516406000000	2	3000000
3	\\xce052faf02e230cdf0acfa47ce25761f738167cae89ce290d065bc72b6279b30baa4d5bb705a3de7dff83b01d789ea52176da00fa945a6aa52826ed3b1e7ad3d	380	\\x000000010000000124dc58cf324eab53254223b24e0bed35318ff115f539cdfb19fc40c0d7a713f8d4c4d3ad9ea4008ae74a34ac0f3eaafe7d2a5fd462af0e8415792d3295e11f6bc4b7f2f4010bdec7cf8b6fb9169b5146932de009658af6ed258b23b318006d3c3a5ac769493295a7c480b7f86612c40fd928f7a96e7f094fd694b0118859d30a	1	\\xe7866377ee86646799b874d8d1c4da3f0023e06db82fd9a62d04ecf72f30b9a7e7c84b52d3c953412537ee6f7e2847162f28f7bb57dbced1f61dadc8fdc3360c	1651516406000000	0	11000000
4	\\x7bb98968d6b175cacb1eb0a3f3dedca1d9da9f1e1d526569cf04821bbb15485d83a7e9e373d66064dd1998910ebd6a0aa0e231b1d7a66776c35bcb2ea6aac7f0	380	\\x000000010000000181d3180a7442d0228dbf287b621f23b4007e8fde1e36e2d3a59a2e457a3e980e13020791eb15a208f7fad54de1c159e90fb665ac1fa70e992538b1d7459a996cd5525378032ff948ddc02ef29b702265e1936fbe9fd3ad8f656bd415a0c8060639faee8ce6155f1308efba520bae91f2ba8c801f48518a3de33ab08ecab1c568	1	\\x8d0e66842d52ddb6416235276afb62db08c25a81be3f9d896e32c2d0269f07a2265a21291194341c051b08d69d1aca1ace9c5feddfdcad43b45803b0929e3c0f	1651516406000000	0	11000000
5	\\x0caf281ea8a72019498b449c760bce76a37f6a0b6fe23d7290edcdb193a8187820fc938f30f48068db80373ecf62ac8513fcfc5a709f7730c4c78bb0be468929	380	\\x00000001000000018eea9887f8a8c613a93a63864927dbcd2e558db97ad8ceec96a476c9cae3a1edd0b3628f2cbbe20f02cb206e5a0b0a84380aa5e18c32c81cd0dc1fc4157a73b264fa249d15e1cf28891064f963fdba31acd8fbf3ba690d792765e5528f339a6f1c1a430e3eea802f15884f5dc453f2f2503c960a14e07bc72f1421d70294d6b8	1	\\x714e9999d1b482bdc234ca82af057d2f70023282f3ef4b70512e75472f2130a86db256eec3fc5d0245ac68261beda21ade33804114061a76b6159dbdae53f607	1651516406000000	0	11000000
6	\\x7240f894c1516804fcdb498219c4b6e0e40953ce24399512f1d3fd3ed60d9bf7381ae1741e5008f5cf7c4e1f19b6104ba733723de18cdc7d3e7beaaaa45370a2	380	\\x00000001000000015ec384ad053acb8508f3904039b6512f5f457b35c1f728bcabc9ff6d3bd25134433deedcd782bca82ad21e2d790a5ccd45ef68ff3fcbaf2cc6102a59900129c248611455c65659af0d81fac7a77cb383677cbd4951bb203a1040ac064e0ab2debd6118d6deb040ce3c39ad0536df18b4340524c2d52c508fb7b53878fed90401	1	\\x2d46deeacd82470e62ddf11278c374721de6a7ec0dbef5ab1b03927a341da82c3b433cef87ca41232d92687aed296353f763af6c34176e3f391ab0bcbb7c5f07	1651516406000000	0	11000000
7	\\x689ed1b36129962c260967ca7f2c9e6ce685c6fb0c6082efecfe98d9f40739b3a8e028777d09461b09efe0e535aa0bc9f16db46b67e370c6898be5c97fefc7f6	380	\\x0000000100000001a1194dd7d15d8fa76b46946868a99da7c8a492b948e57c98831dc926a383b94e57d4d42139b1de50367e58d8c90b8db8518a87d952c74cb19fd7463296446d8b3383a205c33e4277b7847fa06421868c30f7caf891ddc2d195f01e3d5750d68d6349384f151b59efe740bab00bbc7cd8ed24da1e8529bc1e975dda5779026ebc	1	\\x4ddc395724c11a6d880e4d5d8e77d83e4cd584492e6c924dc704dd0fe4f66dcd40c297c99096e62b783b770270453aa8d04f58e47583c57c63271bd6bd992801	1651516406000000	0	11000000
8	\\x160611eb63b0ff7979b281c7b3c8df7c689a28cd062f8ed000b9a660a381cc67a78082e6f4b9c6f4031fa64a9559d8f5595266aa3f03c297a0f69b151e6c875c	380	\\x0000000100000001b680e45ea761c48f75f39c8dcec3edc146cde7a44435f1d44672db640b964bbd0fa49648c9a0c145737502533979b10754506677c582c318890822d3f73357d30b05c87d0d2110c1c3cca6e49238a5f90673bf120f79336affe0f596627cfae035855f7957a179a9a3374c8fd3e63ddc1593d046cca29c5173427335a7aadb5d	1	\\x8b38ed8a1549ddbc7316a54e07c944bd0306508bed5797f6292cedf62cadb14cc22218b2d9a11d5e34ad74dcc95aa172b82548baec2b2d109b0977dd58748f07	1651516406000000	0	11000000
9	\\xba7d2f55f29ef9275f36b4c189da7337700fd295e16c5d3cb430191e603301aeca08cec65538b6c0adfe7b0be4c59cc6bad3055fc65168f6b9aebaa70d04a618	380	\\x00000001000000019b779fbffd2627b8cc58e7fb7454c4524a0e4a613cfda2c141b61c3d986338fea8c328a3c9cbfbccf819fcdf9a01ec60b2eb5ca4b08be2df45f7b3d92de229df44f9feeb5c9405e29e2a49b910744a7ffdef9e08355026fd9c2b8b9af4dd08377df45cf176a10c856e52f093f5aacd4f14fe2aaab1018e7e2867a28d0acb480d	1	\\xba20e87afb14bf9ef23c85934e3999bc09adbad498282e9b9b51ab6019bac3e3a5912d36fc0f361fb8218092c28e2c2949cfe59a2f3941e43bd504e35d88e10b	1651516406000000	0	11000000
10	\\x01be5dc0503cee145cbfcf963a2ebed49ccd0edaec06c6f9cafa0ecc0ab80474b39c485564322a7cbb18b1dc76ac7e41ecb4c8aa2485d8ef8ddf46e286b5b0d7	380	\\x00000001000000012b44554f8b31e9f3500ee2e58817b7f6fde8b82c97043cc7639b10032a47f3186114070e3e7cdf9d2ec3d47d2c61f6edda4890f42d8acd2b13634bae58803efb886b82714e5795caa95471fc597c996732be52e3a34d5d291eaa6b1d5948f3f67a4819a62e1690bc13e3e5209baf38a113064cc4b0284dbe18d522528d6bc469	1	\\xfecebf24558f0e86f12be254638f73533e44d4dd195d9e58f4e0ddc1aa5c9e94d766399d88de237535e4772a62df534108a39f498f7d09c3928f15de724b6a0a	1651516406000000	0	11000000
11	\\xc3bf5fc826c0340f45530ea8511296cd1153d33d204b62142f85357500155abe273244c53203854bb8fd366e9879a3f71c2c0718d378f3892809993d8d1f3453	75	\\x00000001000000014241761740c69ec8615974a08fcb513702f11b447e884d7722bb164955ba791dd0919d0fc3d95eb9eba4e14794c4613df37b38be14bfb7a78d6e701e0697e98873f6d3f1e0fbfe59d288f183766375329b6c38a2b010e50f6d9d1e590e08b6a11105f6f3079627f482e67a080705d986c14c1d97709c41a37e8bd2a15d102e2c	1	\\x89745d4f85222058eee46a912f99dc7cd13ab7d97568b48b54d856ceedf44dedd7ff8a9aa2f6df29fe1be5fc091c1c708a195114380202518c424c39edecfb05	1651516406000000	0	2000000
12	\\xc5eea6a0431bc1613c41c028582dd9d686fdd609740e7de8a6e322b09e7d985e78f5645e8dd21978e66a7a5a173e56bf0dd277bb007331db8067daaa900956b5	75	\\x0000000100000001971f87ce3a0d80bdf926181ce8da9a3472449cd167960901a6ce3eeb1b3c701efcf6c14c92dc963c09c352f556c7505cd420509cd17f65105c8009cd4f51c8d0d777878a8dd2b8b12c16c061b7af6563feb2fdad2bf27a480443a73148ba1be1b923c7bcdf75d6a21b32bc542ebe2329a555706ec1648cf0985bd9600585fb23	1	\\x70075242785e00c1746e9ce1c38217e600e94dcd1cecd4ff20b15053b4b48fcd2b9238a74eb544df912531ce67b5481a1b0c1be193fea6f441255cce5e3e1c09	1651516406000000	0	2000000
13	\\x1265baa10f22e8163d990a085b28917c86599a90f591f3201f92ea9546b89345b704309cf9efe83f91185d471ac49380184fdcbcff8a1010cea08276f6339729	75	\\x0000000100000001572a9207abbf4f1fd966a620ee5000b80f6789903163d6164a1d91f392a304e1dad256b29a936f85d4b7bbaf247edbe24413e8820a6fd336ae66e1fcf1d58275402889cc2558202192b4237942cca1c1f2497ab126bc7f2e139320ef130016fc96df0a17ba21ce3e147c70ad22f69e467f1fb6a836a99975d486c5256e82a00e	1	\\xceffcf81dae5c7129652a7dbc5238b442ce8fdd69b552055adb7b14aff312db42cc149009f1a476bf9e303e0f8d7e876c37e6889cea3576bf6591179276b8a0f	1651516406000000	0	2000000
14	\\x09dd376ca56bcf291aa080136f163af93506a8291ec9c44c59654773d26217cfeab8b0b031ea4c0d4962842c4b0a99b21a500af33bceebc790d1b277c2fe1f41	75	\\x00000001000000013fa80cb7fb15c392bec29b35ccac99cef0ea5ae16cf50de4a5b4c020322dc20bdbcf19e7a0fef5d27fd744d629c6e3e487e56734db191b241af904dd0a0f19f864c46a9dd88abff21d9c00400797fb679fd5f3aab4254300544697d9fb3fefaf28451e93c4095c157e236ed56d161f9d84527bee242aa4558a2149320a261967	1	\\x2a4f63c96db89df94cf09801ff2ab292d5c997e85e31570847b2eb698fcfe2ac3d1bd5cfc20a35efc0095c2e5b7cdf6230166eb494d9d266a4fe539767c70306	1651516406000000	0	2000000
15	\\xbe98a873b03f8548345558578e7a2a2362bd64c0d4982e3ae768a62b9ffdbe50062722ac3972234b77bf4502ecf3369f8a2d0b6ed616cc358ee8c253a85c364d	222	\\x0000000100000001af0ef971e9924f5e20eee3bf2a5fd4e81b533227c0a33ebd41dba53bbeec959add5077422287c70e9403ebffc836aa39310b30624cc7d2a6f6e2cb58d3ca668635c4c71309d191f656ce07533e4bc60b40a5ab1f677d76a1beb8a7b09eb681f00184aa11a6503e9df112140a7390c9c4f61e2dec3a1ccb9034f5880bc3eaa6bd	1	\\x56548d1e1fc0081941c789609c1638bf3b8e5963cf78411acc6768a4d8c95a599455731b14a9ba551c9b3df0f8b04b09f848ed1210ff4885415030c84b4cee03	1651516417000000	1	2000000
16	\\x35328180e0e883fc1a8abd888e15fc7bdf30cc787221a00b8fc33cd165e8357ef5dae73971f13ac68a7d21708db85f6d711ac413e1c658edd84595a3fff702e4	380	\\x0000000100000001138b02b8f050a0f814d298f3aa0e19d1fa635af066d6b6edc759643c80c059f39bb8279bf7362562505314f829b022e313fd8df9dfc1e0513c022ab6399e8e07431e01c0e8ea6020b8cf6563ec6791c19e332e1cba1f9ab9cc9f10db2bf4775bfd46ed4e491e971bb63224d459d304a3e09f0179e140443369f8a5823a3492a8	1	\\x4d333f6d279d63edd855b99e891864cb6245edef0ff178f591005c0004b5a9fc2c5d0e8d8ce760d737821020163c0addcbb2ef346a5a7e3517f220ea3f03290b	1651516417000000	0	11000000
18	\\x4726bc8884901cf1870ff34f30e078bfbd1585930abc8fb8b38bd7300968ebde611228fb38b3caa0f81f49ae072e92a1eb8209452f0f1b687f85bb6bec2ace41	380	\\x0000000100000001770557845d07afb557ce62672303499350088d7de8e244380616a231f7eab85073df6bc60f38bdd1fce009b293165fe3c8608b2e3148da83712fca23e692bce0385823b745c1609c683d6f24db100eb2d7608179650649c33d7f7df6a9f8a05d9fb00807db946546cd5a4681c6784ed67027aca1c8f0e559aab33a93cb715cc5	1	\\x93c5551bdb8a2253bad1805440d8c1934add272a83173eeab0a8b79bc42d1f655b37840ae7c29ccfeca5ecdfdd684db7cf075ebc13007cf320cba1d25cae3107	1651516417000000	0	11000000
20	\\x32fcaa5604cccacee75ae503e95f934ddfc82e1985096771163cba9bf8414a7ca8fea80eeeaba561d4b47cc53579858fddd9d60e81b6ca54246f62ba8204c481	380	\\x00000001000000010e1505f60ba32ee7065b43ad5283dafbc2357e38c1409370b1418dd234d15209476324de01ae05a09c6637186d67fed9a23da46fd4b347b1c3ce8f397d0f97598a78aa92bfe0beefbb1ea6783d929df82c23c7a36748a6a3223859a55d5c5a20403c2bc548022757b48a8d1dea3cf022813bf23bb21c4deb24b6dfec87dc3c9d	1	\\x8aa6e524a3c0a908deee7e502e763932aadcd00ac4f7d4f434da17671e5a94c4545d45d59219e4d32476aefa6cc26b4483c2f131529e6fecaf8830bc4c330007	1651516417000000	0	11000000
22	\\xf4c47fbc700f6ef693325a6c6c54b088f46a2770821a8484299a5dd6cedbc25219c66af01dbecdef631451bff9622d4019181acd0dd7a56614dc3f6fd8471ac6	380	\\x000000010000000139b15073f9e05eedebff4172b1593b95deec27e24cc7a111d661835d667ea724ee9791054a77218663805a8995d228ac2936902a684756e4308267a56ceb0abc3f294dc534a150a12d9e6b5fb7558ea25b4bb7420274e6bd4c5a52cb916481c3d6c64bcb34832f7f013f83df87c9cbdb908e96c5cc3dba357034908941921b1a	1	\\x079f2cdae9e0f9f581b45af3fbd3dce1bfb7f1d503a2bdf8c4809e820e1cf45c4f7bb3f8c70d406474c624232a33eadb71eab3852a2c0e725c0e2e8a5b40b506	1651516417000000	0	11000000
24	\\x9abcb5ebc9f1022f1aeae70a3f1558637a6602b517ef3cddbef5bcff9394d722ed4edae092cc899a000fc0425e111da623e568411e543ac80dd31f8180f2b66b	380	\\x00000001000000011eddf4f82c1ae9c22d439a8916ff77c2536d8e072c55adabb5947ee7187c1b407332160486c717628f37e8e30c5fcbf76170fd1304303a03ef4bc30cc032164d1908bc40a1341765d67e6b9470602cb8b2977c355a45a67d68ce1740d72bafbe55f1763a9b3df22ea5b94d887e2e3e658bd117a21c490ed4c85c44e2c80e7ab4	1	\\xa7b80f4c22b2c144be74a0e68d9ae4d5594d49d32bd6a7168afb17665a97b3f602de9fd5248ce6cc41410095682cd905818e136e403863b2f9cbd9a25dac5e04	1651516417000000	0	11000000
26	\\xb1d1a159afa697e852cc99c63914410e04c7a428749e4a46a995ae0eafdcd75738f4bcb7bd8d96fcd627b91e408480a06cc580492b7ab56f8d9fd18b67646e6c	380	\\x00000001000000014b5bd24f071c39d81b1453fabf10df0aadcb4034367688d0f1fbd8519525686e7087b22421bf1ad2bffa465be24cfbc286ec2ea3108bc4b61a5fd03143642a14486ee0e14b4f07206a52b0905c184c7d1e6726ddd00612bab883b1d1724fab27321773d63efea38d161326178fab7f85768108a679769adcd1e7399891096e70	1	\\xf62bb07666b0188ad59f0aadd4018cfd5752cb875faa9ec6ab709bd97f18b6aa839f671b70b3d1e26ba75d17449b4b33374b2c2ca2e7936bccd93042977ccf07	1651516417000000	0	11000000
28	\\x9053a065acc591e13889f10cf3733e93513851343148c09d2f5443edbcf17b28ee7a9c42fbfdd448860554fa041286a2495558936994452433a81c978108b245	380	\\x0000000100000001605af657e8ce0e96104e40fc74e9a6074582735bd860474e53405f6462e6391ecf66100dad03c72c1a2e009870eccc937cc9851d7744bab4ac7895093d74b2f5f151ccb47be68d2eec2c3778b5bd3e1b38cf71458efb3db3608930f9e239fd7aea2e79aa024504cf6439a2ebca9b5712fa3ea8bcb8531ff5a3b85f7311358dcd	1	\\x167bc328263e14e90db87890807bab083969ed211f3c27abce7f99fe976589e19ddfc02d3d9f0f721e0ce509840f177dc2436961bfe61f3b2873d18998bb7e0a	1651516417000000	0	11000000
30	\\xa57efb259bd7a40b7c4ff6b127bcb4963e62ddbe458220e6e9c1444a9723c67b87c96e630bb3a394efbbcb3d8408ee4e788f37dad06f44aa1b626ac54bed7cc2	380	\\x00000001000000013360f639c649ea4078e20771cd00725f0abc36997fa25383dbdc36f1844e6d4a2f21f37bb0128323d55a9fb6278dc7d599921cf99b30304af699a5119fa7a59a4e914cd8074304723af2ec59bd206de756fec303d36c80cd9aa9bab5a989811807103c45e8459645a32bb415328dae5d040954e467597b0a652c315507e8aa07	1	\\xd91951e60d0e0bbe2038ec2b366a8711c4cfec25bd9fe52989bcffac3453004f830db7610e29cf9db9ca817dc56f1665a362aff853f759a520143cf0a1e9160b	1651516417000000	0	11000000
32	\\xadb725f4d1bd64f8d3e8708289e61f02c940100f16682bf821fc69485089f3c8b32da31d462af44df45566c443fa0e68e00c56d8d06fbfe025f3cc64ebb63717	75	\\x00000001000000016be1dd562630b0eea7328c8a50bf8fe6c08ed5af67378fbff973e60ee86069da0ed10cc8a9b73b432678809cb5ecb57a359047e9f5ae7bad7587698dc7e8f61573c608897690e0ff69738a40381b9d0f19be12620519218d418c451777fdbbaaa33b0160967692fcacbb9a541b32b066579aa117f02e8e1d2558c06f14b7e8e8	1	\\x53bef47d870ad3f69f126accbcd485ae0490f0a50c7890ff2d40655e581567ce5ef9f49e52c518d41ed35576f0dd417c8516ea6e15902240eaf95469d839a80b	1651516417000000	0	2000000
34	\\x36a340d7187b1c8642694588ed9a64825ab2b86bc4cc9dcd35659fc63075bdd610ce07971895dbc8e1b7239e4cb96d928ff890ec8dd98f1eeae2d61be5b50422	75	\\x0000000100000001159cac5c078c2e20221eff0e68b34ef85c562a511f9ce038268f4541454b3be4728e4cadc9a50db291fe542ded1245b2a4d8a31495af90f37bb76b82507cdc8761ac708de2d1863317bb05ec857cdda7f0f14e27ff350493b6e781a2ad4619c3699904fe5d695077bff4aa89c5ec1929b354a9d04c7e48a91ee1c6aefa6ed592	1	\\x6a9d6ce1e770cb3d27fb7e86e39aa6ea75f59440a42639a3b2fe8582084980f0a401d3403c3bbdea791e85f787a594d9c0685d86217f5dc6ca857ff3e0c9a80b	1651516417000000	0	2000000
36	\\xe8d925503c78d85c4ece4cdf5a14bbe11374591a37d2c2ef775d92f5f29d42369e7716516db1e1ab80467d00c8c310570a3a0c0a5a9c6cada8ba37f35947fb24	75	\\x000000010000000136723a2a4b2d6a44cf55d778dd423c81ae0af2c3024e9e3d77817cd337fbff7b66e31e824fcbf2017c1715f2c9bf3221cbbaec9a5e1235aad9766fbb2a75ec1975a5706430f3fa6ed88c68d2b5bfd029d6732472be040179cc52b8aaf1d7282891e99a979b4e63afa2895c1bfcd907c8d0b8eaedb623f7d1432a7a86d3de6a64	1	\\x40aeefc2f4c5a13692fec697bebb0c4ddb375c8e9c887541e8b5becc62bf64860556ae84df9037b02470f4843d81601b665f183c269b84ca1e8c9dc36ebabc0c	1651516417000000	0	2000000
38	\\xf238c2125d57802530dddb6478ac55a10ff084e51a17e57cf7ddf5acb7bf30ed09f7848d5e9ce86ea1855acb667470b7461ef5ed77be35adb8041ebb56258b3f	75	\\x000000010000000198744be13f09e279918189fc365495908d3fe77238d7383b7fdd404f4dd50eb96cfb2435fb1b0462fca76be8f2781fd4e48f00c4bc299a8fb3f64db6d58c798f0d2ca750aa4f760dde7bdc80dd79c332cd9d8a1693840a532a6f78bd4604dedc3c91e26b18cee5268a84168560d3ef165cdd65e01cd1013bf762c26af8bcae	1	\\xd84a39fd6846f45cff8f575e5c2da3da0ca6567525d9f2ae65cb47f2b97541b7664343a86357ee7a1b8c3ebf14b1108e88725426ef401c107ce4ca56bb263c07	1651516418000000	0	2000000
40	\\x52157e06a1af77afdee74dac64a7f0414eb654b4ee6026576fab176799ec9e3f87eb84ec411ffbccc43b45f92881afcb0ec15065669f49e06250d9e0078e44d0	75	\\x0000000100000001b7b0e8043fb2f3d12e78f74a55202e1f8787acc9819aa914634d5bbb0e4690d9ca6d8af2bde5eb524082917dafd83da4a559aaa8b8a65908e0681d4cccb734126ffb4291cd55a696ba82e93ef7dfb1a9bc4437df08ae73270db9870b35224786cfeb38cc821d7c3e867aa383b8fbcc47721c686e9d24b8d193c4b21f98e78a1b	1	\\xc8ae4ba8ea168006449eaeb849a0694e4ade6d8629d3cba92aa5ff563ed173e1161fd1a83b31c707b53e953cd53518c9984aaf8fac6ebe922b047b2d7951ec00	1651516418000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\xd457d175b23a69f3027a15b2662f9e0dbf4931aeae3a97eb9030eb460654245b528969e9a98f1f598386cbe4fde62816da5b0797475beabe16960fec2d11d80b	t	1651516396000000
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
1	x-taler-bank	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\xfbe39dd94c8698ca3a9d45c7f4656143ee091720b005d716e6e46e51673b6f566618e7e3aebc09c949fe6206575f221b3e262e0edf17300e839257f1fda7ad0a
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
1	\\x6506e969615b4c10cea61d3c3798f501407a5eaea24e4176326639c1ea1a89b3	payto://x-taler-bank/localhost/testuser-zzeu1aog	f	\N
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

